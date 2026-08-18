import { AgentDetail, AgentSummary, ConversationMessage, Run, RunStatus, RunsListResponse } from '../models/Api';
import { unwrapAgentDetail } from '../api/ApiUnwrap';
import { CursorApiClient } from '../api/CursorApiClient';
import { AgentCache } from './AgentCache';
import { ApiKeyStore } from './ApiKeyStore';
import { lastTextSummary } from '../utils/StreamText';
import { cacheCoversDetail } from '../utils/CachePolicy';
import { isRunInFlight } from '../utils/InboxGrouping';
import { SessionDiag } from '../utils/SessionDiag';

const TAG = 'Prefetch';
const FRESH_MS = 30 * 1000;
const VISIBLE_STALE_MS = 2 * 60 * 1000;

export interface PrefetchHit {
  ok: boolean;
  detail?: AgentDetail;
  runs?: Run[];
  messages?: ConversationMessage[];
}

/**
 * Background warm-up for conversation cache.
 * One conversation in flight; already-covered ids are skipped.
 */
export class AgentPrefetch {
  private static instance: AgentPrefetch | undefined = undefined;
  private queue: string[] = [];
  private lastAt: Record<string, number> = {};
  private inflight: Record<string, boolean> = {};
  private inflightJobs: Record<string, Promise<PrefetchHit>> = {};
  private running: boolean = false;

  static getInstance(): AgentPrefetch {
    if (!AgentPrefetch.instance) {
      AgentPrefetch.instance = new AgentPrefetch();
    }
    return AgentPrefetch.instance;
  }

  isFresh(agentId: string, ttlMs: number = FRESH_MS): boolean {
    if (!agentId || agentId.length === 0) {
      return false;
    }
    const at = this.lastAt[agentId] ?? 0;
    return at > 0 && (Date.now() - at) < ttlMs;
  }

  enqueue(ids: string[], reason: string): void {
    if (!ApiKeyStore.getInstance().isUnlocked()) {
      SessionDiag.emit({ tag: TAG, event: 'skip', extra: `reason=${reason} locked=1` });
      return;
    }
    const watching = this.watchingId();
    const inbox = AgentCache.getInstance().loadInbox();
    const priority: string[] = [];
    const normal: string[] = [];
    const front = reason === 'unread' || reason === 'terminal';
    for (let i = 0; i < ids.length; i++) {
      const id = ids[i];
      if (this.coveredByCache(id, inbox)) {
        SessionDiag.emit({
          tag: TAG,
          event: 'hit',
          agentId: id,
          extra: `reason=${reason} settled=1`
        });
        continue;
      }
      if (!this.canPrefetch(id, watching)) {
        SessionDiag.emit({
          tag: TAG,
          event: 'skip',
          agentId: id,
          extra: `reason=${reason}`
        });
        continue;
      }
      this.removeQueued(id);
      if (front) {
        priority.push(id);
      } else {
        normal.push(id);
      }
      SessionDiag.emit({
        tag: TAG,
        event: 'enqueue',
        agentId: id,
        extra: `reason=${reason} q=${this.queue.length + priority.length + normal.length}`
      });
    }
    this.queue = priority.concat(this.queue.concat(normal));
    this.pump();
  }

  isInflight(agentId: string): boolean {
    return agentId.length > 0 && this.inflight[agentId] === true;
  }

  async awaitInflight(agentId: string): Promise<PrefetchHit | undefined> {
    const job = this.inflightJobs[agentId];
    if (!job) {
      return undefined;
    }
    try {
      return await job;
    } catch (_e) {
      return undefined;
    }
  }

  clear(): void {
    this.queue = [];
    this.lastAt = {};
    this.inflight = {};
    this.inflightJobs = {};
    this.running = false;
  }

  /** Drop queued ids that are not the watching agent. Keep inflight + freshness. */
  trimIdle(): void {
    const watch = this.watchingId();
    const next: string[] = [];
    for (let i = 0; i < this.queue.length; i++) {
      const id = this.queue[i];
      if (id === watch || this.inflight[id] === true) {
        next.push(id);
      }
    }
    this.queue = next;
  }

  /** Top-of-inbox: skip when conversation cache already covers the Inbox row. */
  enqueueVisible(rows: AgentSummary[], reason: string): void {
    const cache = AgentCache.getInstance();
    const want: string[] = [];
    for (let i = 0; i < rows.length; i++) {
      const a = rows[i];
      const id = a.id;
      const cached = cache.loadAgent(id);
      const n = cached?.messages?.length ?? 0;
      const age = cached && cached.fetchedAt > 0 ? Date.now() - cached.fetchedAt : -1;
      const inboxRunId = a.latestRunId ?? '';
      const inboxRunStatus = `${a.latestRunStatus ?? ''}`;
      if (cacheCoversDetail(cached, inboxRunId, inboxRunStatus)) {
        SessionDiag.emit({
          tag: TAG,
          event: 'hit',
          agentId: id,
          extra: `reason=${reason} settled=1 n=${n}`
        });
        continue;
      }
      const localRun = cached?.detail?.latestRunId ?? cached?.timelineRunId ?? '';
      const sameRun = inboxRunId.length === 0 || localRun.length === 0 || inboxRunId === localRun;
      const live = isRunInFlight(inboxRunStatus);
      const staleMs = reason === 'show' ? VISIBLE_STALE_MS : FRESH_MS;
      if (n > 0 && live && sameRun && age >= 0 && age < staleMs) {
        SessionDiag.emit({
          tag: TAG,
          event: 'hit',
          agentId: id,
          extra: `reason=${reason} cacheAgeMs=${age} n=${n}`
        });
        continue;
      }
      SessionDiag.emit({
        tag: TAG,
        event: 'miss',
        agentId: id,
        extra: `reason=${reason} cacheAgeMs=${age} n=${n}`
      });
      want.push(id);
    }
    if (want.length > 0) {
      this.enqueue(want, reason);
    }
  }

  private coveredByCache(id: string, inbox: AgentSummary[]): boolean {
    const cached = AgentCache.getInstance().loadAgent(id);
    let runId = '';
    let status = '';
    for (let i = 0; i < inbox.length; i++) {
      if (inbox[i].id === id) {
        runId = inbox[i].latestRunId ?? '';
        status = `${inbox[i].latestRunStatus ?? ''}`;
        break;
      }
    }
    return cacheCoversDetail(cached, runId, status);
  }

  private canPrefetch(id: string, watching: string): boolean {
    if (!id || id.length === 0) {
      return false;
    }
    if (id.indexOf('local-') === 0) {
      return false;
    }
    if (watching.length > 0 && watching === id) {
      return false;
    }
    if (this.inflight[id] === true) {
      return false;
    }
    return true;
  }

  private watchingId(): string {
    try {
      const watch = AppStorage.get<string>('watchingAgentId') ?? '';
      if (watch.length > 0) {
        return watch;
      }
      return AppStorage.get<string>('streamingAgentId') ?? '';
    } catch (_e) {
      return '';
    }
  }

  private removeQueued(id: string): void {
    const next: string[] = [];
    for (let i = 0; i < this.queue.length; i++) {
      if (this.queue[i] !== id) {
        next.push(this.queue[i]);
      }
    }
    this.queue = next;
  }

  private pump(): void {
    if (this.running) {
      return;
    }
    this.running = true;
    this.drain().catch(() => {
    }).then(() => {
      this.running = false;
      if (this.queue.length > 0) {
        this.pump();
      }
    });
  }

  private async drain(): Promise<void> {
    while (this.queue.length > 0) {
      const id = this.queue.shift() ?? '';
      if (!this.canPrefetch(id, this.watchingId())) {
        SessionDiag.emit({ tag: TAG, event: 'skip', agentId: id, extra: 'reason=watch' });
        continue;
      }
      const job = this.fetchOne(id);
      this.inflightJobs[id] = job;
      await job;
    }
  }

  private async fetchOne(agentId: string): Promise<PrefetchHit> {
    this.inflight[agentId] = true;
    const started = Date.now();
    const miss: PrefetchHit = { ok: false };
    try {
      const client = CursorApiClient.getInstance();
      const settled = await Promise.all([
        client.getAgent(agentId),
        client.getRuns(agentId, 20)
      ]);
      const detail: AgentDetail = unwrapAgentDetail(settled[0] as object);
      const runs: Run[] = extractRuns(settled[1] as object);
      const conv = await client.getConversation(agentId);
      const messages: ConversationMessage[] = conv.messages ?? [];
      const summary = lastTextSummary(messageTexts(messages));
      AgentCache.getInstance().saveAgent(agentId, detail, runs, summary, messages);
      this.lastAt[agentId] = Date.now();
      SessionDiag.emit({
        tag: TAG,
        event: 'done',
        agentId: agentId,
        elapsedMs: Date.now() - started,
        extra: `n=${messages.length} runs=${runs.length} watch=${this.watchingId() === agentId ? 1 : 0}`
      });
      const hit: PrefetchHit = { ok: true, detail: detail, runs: runs, messages: messages };
      return hit;
    } catch (_e) {
      SessionDiag.emit({
        tag: TAG,
        event: 'fail',
        agentId: agentId,
        elapsedMs: Date.now() - started
      });
      return miss;
    } finally {
      this.inflight[agentId] = false;
    }
  }
}

function messageTexts(messages: ConversationMessage[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < messages.length; i++) {
    out.push(messages[i].text ?? '');
  }
  return out;
}

function extractRuns(raw: object): Run[] {
  const typed = raw as RunsListResponse;
  if (typed.items && typed.items.length > 0) {
    return typed.items;
  }
  const obj = raw as Record<string, Object>;
  const list = (obj['items'] ?? obj['runs'] ?? []) as object[];
  const out: Run[] = [];
  for (let i = 0; i < list.length; i++) {
    const r = list[i] as Record<string, Object>;
    const id = `${r['id'] ?? ''}`;
    if (id.length === 0) {
      continue;
    }
    const run: Run = {
      id: id,
      agentId: `${r['agentId'] ?? ''}`,
      status: `${r['status'] ?? 'CREATING'}` as RunStatus,
      createdAt: `${r['createdAt'] ?? ''}`,
      updatedAt: `${r['updatedAt'] ?? ''}`,
      durationMs: Number(r['durationMs'] ?? 0)
    };
    const result = r['result'] ? `${r['result']}` : '';
    if (result.length > 0) {
      run.result = result;
    }
    out.push(run);
  }
  return out;
}
