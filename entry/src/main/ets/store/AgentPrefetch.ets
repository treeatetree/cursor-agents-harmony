import { AgentDetail, ConversationMessage, Run, RunStatus, RunsListResponse } from '../models/Api';
import { unwrapAgentDetail } from '../api/ApiUnwrap';
import { CursorApiClient } from '../api/CursorApiClient';
import { AgentCache } from './AgentCache';
import { ApiKeyStore } from './ApiKeyStore';
import { SessionDiag } from '../utils/SessionDiag';

const TAG = 'Prefetch';
const QUEUE_MAX = 3;
const FRESH_MS = 30 * 1000;
const VISIBLE_STALE_MS = 2 * 60 * 1000;

/**
 * Narrow background warm-up for conversation cache.
 * At most 1 conversation in flight; queue keeps the latest 3 ids.
 */
export class AgentPrefetch {
  private static instance: AgentPrefetch | undefined = undefined;
  private queue: string[] = [];
  private lastAt: Record<string, number> = {};
  private inflight: Record<string, boolean> = {};
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
    for (let i = 0; i < ids.length; i++) {
      const id = ids[i];
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
      this.queue.push(id);
      SessionDiag.emit({
        tag: TAG,
        event: 'enqueue',
        agentId: id,
        extra: `reason=${reason} q=${this.queue.length}`
      });
    }
    while (this.queue.length > QUEUE_MAX) {
      const dropped = this.queue.shift();
      if (dropped && dropped.length > 0) {
        SessionDiag.emit({
          tag: TAG,
          event: 'skip',
          agentId: dropped,
          extra: `reason=${reason} overflow=1`
        });
      }
    }
    this.pump();
  }

  clear(): void {
    this.queue = [];
    this.lastAt = {};
    this.inflight = {};
    this.running = false;
  }

  /** Top-of-inbox: skip when conversation cache is fresh enough. */
  enqueueVisible(ids: string[], reason: string): void {
    const cache = AgentCache.getInstance();
    const want: string[] = [];
    for (let i = 0; i < ids.length; i++) {
      const id = ids[i];
      const cached = cache.loadAgent(id);
      const n = cached?.messages?.length ?? 0;
      const age = cached && cached.fetchedAt > 0 ? Date.now() - cached.fetchedAt : -1;
      if (n > 0 && age >= 0 && age < VISIBLE_STALE_MS) {
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
      return AppStorage.get<string>('watchingAgentId') ?? '';
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
      await this.fetchOne(id);
    }
  }

  private async fetchOne(agentId: string): Promise<void> {
    this.inflight[agentId] = true;
    const started = Date.now();
    try {
      const client = CursorApiClient.getInstance();
      const settled = await Promise.all([
        client.getAgent(agentId),
        client.getRuns(agentId, 20)
      ]);
      if (this.watchingId() === agentId) {
        SessionDiag.emit({
          tag: TAG,
          event: 'skip',
          agentId: agentId,
          elapsedMs: Date.now() - started,
          extra: 'reason=opened'
        });
        return;
      }
      const detail: AgentDetail = unwrapAgentDetail(settled[0] as object);
      const runs: Run[] = extractRuns(settled[1] as object);
      const conv = await client.getConversation(agentId);
      const messages: ConversationMessage[] = conv.messages ?? [];
      AgentCache.getInstance().saveAgent(agentId, detail, runs, undefined, messages);
      this.lastAt[agentId] = Date.now();
      SessionDiag.emit({
        tag: TAG,
        event: 'done',
        agentId: agentId,
        elapsedMs: Date.now() - started,
        extra: `n=${messages.length} runs=${runs.length}`
      });
    } catch (_e) {
      SessionDiag.emit({
        tag: TAG,
        event: 'fail',
        agentId: agentId,
        elapsedMs: Date.now() - started
      });
    } finally {
      this.inflight[agentId] = false;
    }
  }
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
