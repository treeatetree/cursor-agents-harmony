import { common } from '@kit.AbilityKit';
import { ApiException, AgentSummary, Run } from '../models/Api';
import { unwrapAgentsList } from '../api/ApiUnwrap';
import { CursorApiClient } from '../api/CursorApiClient';
import { AgentCache } from '../store/AgentCache';
import { AgentPrefetch } from '../store/AgentPrefetch';
import { AgentListSource } from '../datasource/AgentListSource';
import { ApiKeyStore } from '../store/ApiKeyStore';
import { Log } from '../utils/Log';
import { SessionDiag } from '../utils/SessionDiag';
import { WidgetBridge } from '../utils/WidgetBridge';
import { UnreadStore } from '../store/UnreadStore';
import { PrefStore } from '../store/PrefStore';
import { clipNotice } from '../utils/MarkdownParse';
import {
  InboxDelta, diffInboxAgents, emptyInboxDelta, isRunInFlight, mergeInboxLists, pickNewerIso,
  sortByRecency
} from '../utils/InboxGrouping';
import { repoTail } from '../utils/DisplayFmt';
import { AppState } from '../utils/AppState';
import { LiveIsland } from '../utils/LiveIsland';
import { DetailVM } from './DetailVM';

const TAG = 'InboxVM';

export class InboxVM {
  private static instance: InboxVM | undefined = undefined;
  source: AgentListSource = new AgentListSource();
  loading: boolean = false;
  refreshing: boolean = false;
  loadingMore: boolean = false;
  errorMsg: string = '';
  loadedOnce: boolean = false;
  nextCursor: string = '';
  includeArchived: boolean = false;
  prUrlFilter: string = '';
  authExpired: boolean = false;
  needsPlanUpgrade: boolean = false;
  lastRefreshAt: number = 0;
  dirty: boolean = false;
  actionBanner: string = '';
  actionKind: string = '';
  lastDelta: InboxDelta = emptyInboxDelta();
  private ctx: common.UIAbilityContext | undefined = undefined;
  private heldIds: string[] = [];
  private refreshQueued: boolean = false;
  private watchTimer: number = -1;
  private watchBusy: boolean = false;
  private listeners: Array<() => void> = [];

  onChange(cb: () => void): void {
    this.listeners.push(cb);
  }

  private emitChange(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i]();
    }
  }

  static getInstance(): InboxVM {
    if (!InboxVM.instance) {
      InboxVM.instance = new InboxVM();
    }
    return InboxVM.instance;
  }

  async bootstrap(context: common.UIAbilityContext): Promise<void> {
    this.ctx = context;
    await AgentCache.getInstance().init(context);
    const cached = AgentCache.getInstance().loadInbox();
    if (cached.length > 0) {
      this.source.replaceAll(cached);
      this.loadedOnce = true;
      const fetchedAt = AgentCache.getInstance().inboxFetchedAt();
      if (fetchedAt > 0) {
        this.lastRefreshAt = fetchedAt;
      }
    }
  }

  shouldRefresh(minIntervalMs: number = 10000): boolean {
    if (this.dirty || this.heldIds.length > 0) {
      return true;
    }
    if (this.lastRefreshAt <= 0) {
      return true;
    }
    return (Date.now() - this.lastRefreshAt) > minIntervalMs;
  }

  prefetchOnShow(): void {
    if (this.includeArchived) {
      SessionDiag.emit({ tag: TAG, event: 'prefetch_skip', extra: 'archived' });
      return;
    }
    const snap = this.source.snapshot();
    const ids: string[] = [];
    for (let i = 0; i < snap.length && ids.length < 2; i++) {
      const id = snap[i].id;
      if (id.indexOf('local-') === 0) {
        continue;
      }
      ids.push(id);
    }
    if (ids.length > 0) {
      AgentPrefetch.getInstance().enqueueVisible(ids, 'show');
    }
  }

  async refresh(silent: boolean = false): Promise<boolean> {
    if (!ApiKeyStore.getInstance().isUnlocked()) {
      return false;
    }
    if (this.loading || CursorApiClient.getInstance().isMutating()) {
      this.refreshQueued = true;
      return true;
    }
    this.loading = true;
    if (!silent) {
      this.refreshing = true;
    }
    this.errorMsg = '';
    this.authExpired = false;
    this.needsPlanUpgrade = false;
    const started = Date.now();
    const prevN = this.source.totalCount();
    try {
      const client = CursorApiClient.getInstance();
      const resp = await client.listAgents(100, undefined, this.includeArchived, this.prUrlFilter);
      const unwrapped = unwrapAgentsList(resp as object);
      let agents = unwrapped.items ?? [];
      this.nextCursor = unwrapped.nextCursor ?? '';
      if (this.nextCursor.length > 0) {
        try {
          const moreResp = await client.listAgents(100, this.nextCursor, this.includeArchived,
            this.prUrlFilter);
          const more = unwrapAgentsList(moreResp as object);
          const extra = more.items ?? [];
          for (let i = 0; i < extra.length; i++) {
            agents.push(extra[i]);
          }
          this.nextCursor = more.nextCursor ?? '';
        } catch (_e) {
        }
      }
      if (!this.includeArchived) {
        agents = agents.filter((a: AgentSummary) => a.status !== 'ARCHIVED');
      }
      this.mergeRunStatus(agents);
      const prev = this.source.snapshot();
      agents = mergeInboxLists(agents, prev, this.heldIds, Date.now());
      agents = sortByRecency(agents);
      this.heldIds = this.heldIdsStillMissing(agents);
      this.noteStatusChanges(prev, agents);
      this.lastDelta = silent ? emptyInboxDelta() : diffInboxAgents(prev, agents);
      this.source.replaceAll(agents);
      const filtered = this.includeArchived || this.prUrlFilter.length > 0;
      AgentCache.getInstance().saveInbox(agents, filtered ? 'merge' : 'full');
      this.loadedOnce = true;
      this.lastRefreshAt = Date.now();
      this.dirty = this.heldIds.length > 0;
      const nextN = agents.length;
      SessionDiag.emit({
        tag: TAG,
        event: 'refresh',
        elapsedMs: Date.now() - started,
        extra: `n=${nextN} prev=${prevN} diff=${nextN - prevN} silent=${silent ? 1 : 0}`
      });
      Log.info(TAG, `inbox ${agents.length}`);
      this.startWatch();
      LiveIsland.syncRunning(this.inFlightAgents()).catch(() => {
      });
      this.enrichRunStatuses(this.inFlightAgents());
      UnreadStore.getInstance().syncBadge();
      this.pushWidget();
      this.emitChange();
      if (!this.includeArchived && !silent && this.lastDelta.ids.length > 0) {
        const deltaIds = this.lastDelta.ids.slice(0, 3);
        AgentPrefetch.getInstance().enqueue(deltaIds, 'delta');
      }
      return true;
    } catch (e) {
      this.applyError(e, '刷新失败');
      return false;
    } finally {
      this.loading = false;
      this.refreshing = false;
      if (this.refreshQueued) {
        this.refreshQueued = false;
        this.refresh(true).catch(() => {
        });
      }
    }
  }

  private mergeRunStatus(agents: AgentSummary[]): void {
    const prev = this.source.snapshot();
    for (let i = 0; i < agents.length; i++) {
      const id = agents[i].id;
      for (let j = 0; j < prev.length; j++) {
        if (prev[j].id !== id) {
          continue;
        }
        const remoteRun = `${agents[i].latestRunId ?? ''}`;
        const localRun = `${prev[j].latestRunId ?? ''}`;
        if (remoteRun.length === 0 && localRun.length > 0) {
          agents[i].latestRunId = prev[j].latestRunId;
        }
        const sameRun = `${agents[i].latestRunId ?? ''}` === localRun || localRun.length === 0;
        if (sameRun && (!agents[i].latestRunStatus || `${agents[i].latestRunStatus}`.length === 0)) {
          const oldStatus = prev[j].latestRunStatus;
          if (oldStatus) {
            agents[i].latestRunStatus = oldStatus;
          }
        }
        const oldResult = prev[j].latestResult ?? '';
        const curResult = agents[i].latestResult ?? '';
        if (sameRun && oldResult.length > 0 && curResult.length === 0) {
          agents[i].latestResult = oldResult;
        }
        const oldRepos = prev[j].repos;
        const curRepos = agents[i].repos;
        if ((!curRepos || curRepos.length === 0) && oldRepos) {
          agents[i].repos = oldRepos;
        }
        const userAt = pickNewerIso(agents[i].lastUserAt ?? '', prev[j].lastUserAt ?? '');
        if (userAt.length > 0) {
          agents[i].lastUserAt = userAt;
        }
        break;
      }
    }
  }

  startWatch(): void {
    if (this.watchTimer >= 0) {
      return;
    }
    this.tickWatch();
    this.watchTimer = setInterval(() => {
      this.tickWatch();
    }, 1000) as number;
  }

  stopWatch(): void {
    if (this.watchTimer >= 0) {
      clearInterval(this.watchTimer);
      this.watchTimer = -1;
    }
  }

  private tickWatch(): void {
    if (this.watchBusy || !ApiKeyStore.getInstance().isUnlocked()) {
      return;
    }
    const inflight = this.inFlightAgents();
    if (inflight.length === 0) {
      return;
    }
    this.enrichRunStatuses(inflight).catch(() => {
    });
  }

  private inFlightAgents(): AgentSummary[] {
    const snap = this.source.snapshot();
    const out: AgentSummary[] = [];
    for (let i = 0; i < snap.length; i++) {
      const a = snap[i];
      if (a.status !== 'ACTIVE' || !a.latestRunId || a.latestRunId.length === 0) {
        continue;
      }
      const st = `${a.latestRunStatus ?? ''}`;
      if (st.length === 0 || isRunInFlight(st)) {
        out.push(a);
      }
    }
    return out;
  }

  /** Fetch latest run status for in-flight agents so finish can notify immediately. */
  private async enrichRunStatuses(agents: AgentSummary[]): Promise<void> {
    if (this.watchBusy) {
      return;
    }
    this.watchBusy = true;
    const tasks: Promise<void>[] = [];
    const cap = agents.length > 12 ? 12 : agents.length;
    for (let i = 0; i < cap; i++) {
      const a = agents[i];
      if (!a.latestRunId || a.latestRunId.length === 0 || a.status !== 'ACTIVE') {
        continue;
      }
      const agentId = a.id;
      const runId = a.latestRunId;
      tasks.push((async () => {
        try {
          const run = await CursorApiClient.getInstance().getRun(agentId, runId);
          const snap = this.source.snapshot();
          for (let j = 0; j < snap.length; j++) {
            if (snap[j].id === agentId) {
              const oldStatus = `${snap[j].latestRunStatus ?? ''}`;
              const next = copyAgent(snap[j]);
              next.latestRunStatus = run.status;
              if (run.updatedAt && run.updatedAt.length > 0) {
                next.updatedAt = pickNewerIso(next.updatedAt, run.updatedAt);
              }
              if ((!next.lastUserAt || next.lastUserAt.length === 0) &&
                run.createdAt && run.createdAt.length > 0) {
                next.lastUserAt = run.createdAt;
              }
              applyRunGit(next, run);
              applyRunResult(next, run);
              this.source.updateAt(j, next);
              this.noteTerminal(next, oldStatus);
              break;
            }
          }
        } catch (_e) {
        }
      })());
    }
    try {
      if (tasks.length > 0) {
        await Promise.all(tasks);
        AgentCache.getInstance().saveInbox(this.source.snapshot(), 'merge');
        UnreadStore.getInstance().syncBadge();
        this.pushWidget();
        LiveIsland.syncRunning(this.inFlightAgents()).catch(() => {
        });
        this.emitChange();
      }
    } finally {
      this.watchBusy = false;
    }
  }

  async loadMore(): Promise<boolean> {
    if (this.loadingMore || this.loading || this.nextCursor.length === 0) {
      return true;
    }
    this.loadingMore = true;
    try {
      const resp = await CursorApiClient.getInstance()
        .listAgents(50, this.nextCursor, this.includeArchived, this.prUrlFilter);
      const unwrapped = unwrapAgentsList(resp as object);
      let more = unwrapped.items ?? [];
      if (!this.includeArchived) {
        more = more.filter((a: AgentSummary) => a.status !== 'ARCHIVED');
      }
      this.nextCursor = unwrapped.nextCursor ?? '';
      const merged = sortByRecency(this.source.snapshot().concat(more));
      this.source.replaceAll(merged);
      const filtered = this.includeArchived || this.prUrlFilter.length > 0;
      AgentCache.getInstance().saveInbox(merged, filtered ? 'merge' : 'full');
      this.emitChange();
      return true;
    } catch (e) {
      this.applyError(e, '加载更多失败');
      return false;
    } finally {
      this.loadingMore = false;
    }
  }

  runningCount(): number {
    let n = 0;
    const snap = this.source.snapshot();
    for (let i = 0; i < snap.length; i++) {
      const st = `${snap[i].latestRunStatus ?? ''}`;
      if (st === 'RUNNING' || st === 'CREATING') {
        n++;
      }
    }
    return n;
  }

  setIncludeArchived(value: boolean): void {
    this.includeArchived = value;
  }

  setPrUrlFilter(value: string): void {
    this.prUrlFilter = value;
  }

  prependOptimistic(agent: AgentSummary): void {
    this.heldIds = [agent.id].concat(this.heldIds.filter((id: string) => id !== agent.id));
    this.dirty = true;
    this.source.prepend(agent);
    AgentCache.getInstance().saveInbox(this.source.snapshot(), 'merge');
    this.pushWidget();
    this.emitChange();
  }

  /** Record the last user prompt time so Inbox can sort by it. */
  markUserAt(agentId: string, whenIso: string = ''): void {
    if (!agentId || agentId.length === 0) {
      return;
    }
    const iso = whenIso.length > 0 ? whenIso : new Date().toISOString();
    const snap = this.source.snapshot();
    for (let i = 0; i < snap.length; i++) {
      if (snap[i].id !== agentId) {
        continue;
      }
      const item = copyAgent(snap[i]);
      item.lastUserAt = pickNewerIso(item.lastUserAt ?? '', iso);
      item.updatedAt = pickNewerIso(item.updatedAt, iso);
      this.source.updateAt(i, item);
      AgentCache.getInstance().saveInbox(this.source.snapshot(), 'merge');
      this.dirty = true;
      this.emitChange();
      return;
    }
  }

  /** Update name / run status only. Does not rewrite lastUserAt. */
  touch(agentId: string, name?: string, status?: string, runUpdatedAt?: string,
    latestRunId?: string): void {
    if (!agentId || agentId.length === 0) {
      return;
    }
    const snap = this.source.snapshot();
    let found = -1;
    for (let i = 0; i < snap.length; i++) {
      if (snap[i].id === agentId) {
        found = i;
        break;
      }
    }
    if (found < 0) {
      return;
    }
    const item = copyAgent(snap[found]);
    if (name && name.length > 0) {
      item.name = name;
    }
    if (status && status.length > 0) {
      item.latestRunStatus = status;
    }
    if (runUpdatedAt && runUpdatedAt.length > 0) {
      item.updatedAt = pickNewerIso(item.updatedAt, runUpdatedAt);
    }
    if (latestRunId && latestRunId.length > 0) {
      item.latestRunId = latestRunId;
    }
    this.source.updateAt(found, item);
    AgentCache.getInstance().saveInbox(this.source.snapshot(), 'merge');
    this.dirty = true;
    this.emitChange();
  }

  replaceHeld(oldId: string, agent: AgentSummary): void {
    this.heldIds = [agent.id].concat(this.heldIds.filter((id: string) => id !== oldId && id !== agent.id));
    this.source.removeById(oldId);
    this.source.removeById(agent.id);
    this.source.prepend(agent);
    this.dirty = true;
    AgentCache.getInstance().saveInbox(this.source.snapshot(), 'merge');
    this.pushWidget();
    this.emitChange();
  }

  private heldIdsStillMissing(remote: AgentSummary[]): string[] {
    const seen: Record<string, boolean> = {};
    for (let i = 0; i < remote.length; i++) {
      seen[remote[i].id] = true;
    }
    const still: string[] = [];
    for (let i = 0; i < this.heldIds.length; i++) {
      const id = this.heldIds[i];
      if (!seen[id]) {
        still.push(id);
      }
    }
    return still;
  }

  private noteStatusChanges(prev: AgentSummary[], next: AgentSummary[]): void {
    for (let i = 0; i < next.length; i++) {
      const a = next[i];
      let old = '';
      for (let j = 0; j < prev.length; j++) {
        if (prev[j].id === a.id) {
          old = `${prev[j].latestRunStatus ?? ''}`;
          break;
        }
      }
      this.noteTerminal(a, old);
    }
  }

  private noteTerminal(a: AgentSummary, oldStatus: string): void {
    const now = `${a.latestRunStatus ?? ''}`;
    if (!isTerminalRun(now)) {
      return;
    }
    if (oldStatus === now || (oldStatus.length > 0 && isTerminalRun(oldStatus))) {
      return;
    }
    const watching = DetailVM.getActive()?.agentId ?? '';
    if (watching === a.id && AppState.foreground) {
      return;
    }
    const zh = runStatusLabel(now);
    const snippet = clipNotice(a.latestResult ?? a.name ?? '', 56);
    const repo = (a.repos && a.repos.length > 0) ? repoTail(a.repos[0].url ?? '') : '';
    const shown = PrefStore.getInstance().displayName(a.id, a.name ?? '');
    SessionDiag.emit({
      tag: TAG,
      event: 'noteTerminal',
      agentId: a.id,
      extra: `status=${now} old=${oldStatus} repo=${repo}`
    });
    UnreadStore.getInstance().markFinished(a.id, shown, zh, snippet, repo).catch(() => {
    });
    if (!this.includeArchived) {
      AgentPrefetch.getInstance().enqueue([a.id], 'terminal');
    }
  }

  removeLocal(agentId: string): void {
    this.source.removeById(agentId);
    AgentCache.getInstance().removeInboxId(agentId);
    this.pushWidget();
    this.emitChange();
  }

  private pushWidget(): void {
    if (!this.ctx) {
      return;
    }
    const snap = WidgetBridge.snapFromInbox(this.source.snapshot(), this.runningCount());
    WidgetBridge.publish(this.ctx, snap).catch(() => {
    });
  }

  noteCreateFailed(name: string): void {
    const title = name.length > 0 ? name : '新任务';
    this.actionBanner = `「${title}」创建失败`;
    this.actionKind = 'retry-create';
    this.emitChange();
  }

  clearActionBanner(): void {
    this.actionBanner = '';
    this.actionKind = '';
    this.emitChange();
  }

  private findIndex(agentId: string): number {
    const snap = this.source.snapshot();
    for (let i = 0; i < snap.length; i++) {
      if (snap[i].id === agentId) {
        return i;
      }
    }
    return -1;
  }

  async archive(agentId: string): Promise<boolean> {
    const idx = this.findIndex(agentId);
    if (idx < 0) {
      return false;
    }
    const prev = copyAgent(this.source.snapshot()[idx]);
    const next = copyAgent(prev);
    next.status = 'ARCHIVED';
    next.updatedAt = new Date().toISOString();
    this.source.updateAt(idx, next);
    this.dirty = true;
    AgentCache.getInstance().saveInbox(this.source.snapshot(), 'merge');
    this.emitChange();
    try {
      await CursorApiClient.getInstance().archiveAgent(agentId);
      SessionDiag.emit({
        tag: TAG,
        event: 'archive',
        agentId: agentId,
        extra: 'ok'
      });
      this.refresh(true).catch(() => {
      });
      return true;
    } catch (e) {
      SessionDiag.emit({
        tag: TAG,
        event: 'archive',
        agentId: agentId,
        extra: 'fail'
      });
      const cur = this.findIndex(agentId);
      if (cur >= 0) {
        this.source.updateAt(cur, prev);
      } else {
        this.source.prepend(prev);
      }
      this.applyError(e, '归档失败');
      this.emitChange();
      return false;
    }
  }

  async unarchive(agentId: string): Promise<boolean> {
    const idx = this.findIndex(agentId);
    let prev: AgentSummary | undefined = undefined;
    if (idx >= 0) {
      prev = copyAgent(this.source.snapshot()[idx]);
      const next = copyAgent(prev);
      next.status = 'ACTIVE';
      next.updatedAt = new Date().toISOString();
      this.source.updateAt(idx, next);
      this.dirty = true;
      AgentCache.getInstance().saveInbox(this.source.snapshot(), 'merge');
      this.emitChange();
    }
    try {
      await CursorApiClient.getInstance().unarchiveAgent(agentId);
      await this.refresh(true);
      return true;
    } catch (e) {
      if (prev) {
        const cur = this.findIndex(agentId);
        if (cur >= 0) {
          this.source.updateAt(cur, prev);
        }
      }
      this.applyError(e, '取消归档失败');
      this.emitChange();
      return false;
    }
  }

  async deleteRemote(agentId: string): Promise<boolean> {
    try {
      await CursorApiClient.getInstance().deleteAgent(agentId);
      this.removeLocal(agentId);
      return true;
    } catch (e) {
      this.applyError(e, '删除失败');
      return false;
    }
  }

  private applyError(e: Object, fallback: string): void {
    if (e instanceof ApiException) {
      this.errorMsg = e.message;
      if (e.code === 401 && e.apiCode !== 'no_api_key') {
        this.authExpired = true;
        this.errorMsg = 'API Key 失效，请重新粘贴';
      } else if (e.code === 403) {
        this.needsPlanUpgrade = true;
      }
    } else {
      this.errorMsg = fallback;
    }
    Log.error(TAG, this.errorMsg);
  }
}

/** List items omit repos; GET run.git has the current PR / repo snapshot. */
function applyRunGit(agent: AgentSummary, run: Run): void {
  const branches = run.git?.branches ?? [];
  if (branches.length === 0) {
    return;
  }
  const b = branches[0];
  const pr = b.prUrl ?? '';
  let url = '';
  if (agent.repos && agent.repos.length > 0) {
    url = agent.repos[0].url ?? '';
  }
  if (url.length === 0 && (b.repoUrl ?? '').length > 0) {
    const raw = b.repoUrl as string;
    url = raw.indexOf('http') === 0 ? raw : `https://${raw}`;
  }
  if (url.length === 0 && pr.length === 0) {
    return;
  }
  agent.repos = [{ url: url, prUrl: pr.length > 0 ? pr : undefined }];
}

function isTerminalRun(status: string): boolean {
  return status === 'FINISHED' || status === 'ERROR' || status === 'CANCELLED' || status === 'EXPIRED';
}

function runStatusLabel(status: string): string {
  if (status === 'FINISHED') {
    return '已完成';
  }
  if (status === 'ERROR') {
    return '失败';
  }
  if (status === 'CANCELLED') {
    return '已取消';
  }
  if (status === 'EXPIRED') {
    return '已过期';
  }
  return status;
}

function copyAgent(a: AgentSummary): AgentSummary {
  const next: AgentSummary = {
    id: a.id ?? '',
    name: a.name ?? '',
    status: a.status ?? 'ACTIVE',
    url: a.url ?? '',
    createdAt: a.createdAt ?? '',
    updatedAt: a.updatedAt ?? ''
  };
  if (a.lastUserAt && a.lastUserAt.length > 0) {
    next.lastUserAt = a.lastUserAt;
  }
  if (a.latestRunId && a.latestRunId.length > 0) {
    next.latestRunId = a.latestRunId;
  }
  if (a.latestRunStatus && `${a.latestRunStatus}`.length > 0) {
    next.latestRunStatus = a.latestRunStatus;
  }
  if (a.latestResult && a.latestResult.length > 0) {
    next.latestResult = a.latestResult;
  }
  if (a.repos) {
    next.repos = a.repos;
  }
  if (a.env) {
    next.env = a.env;
  }
  if (a.workOnCurrentBranch !== undefined) {
    next.workOnCurrentBranch = a.workOnCurrentBranch;
  }
  if (a.autoCreatePR !== undefined) {
    next.autoCreatePR = a.autoCreatePR;
  }
  if (a.openAsCursorGithubApp !== undefined) {
    next.openAsCursorGithubApp = a.openAsCursorGithubApp;
  }
  if (a.skipReviewerRequest !== undefined) {
    next.skipReviewerRequest = a.skipReviewerRequest;
  }
  return next;
}

function applyRunResult(agent: AgentSummary, run: Run): void {
  const raw = (run.result ?? '').replace(/\s+/g, ' ').trim();
  if (raw.length === 0) {
    return;
  }
  agent.latestResult = raw.length > 120 ? `${raw.substring(0, 118)}…` : raw;
}
