import { common } from '@kit.AbilityKit';
import { ApiException, AgentSummary, Run } from '../models/Api';
import { unwrapAgentsList } from '../api/ApiUnwrap';
import { CursorApiClient } from '../api/CursorApiClient';
import { AgentCache } from '../store/AgentCache';
import { AgentListSource } from '../datasource/AgentListSource';
import { ApiKeyStore } from '../store/ApiKeyStore';
import { Log } from '../utils/Log';
import { Notify } from '../utils/Notify';
import { WidgetBridge } from '../utils/WidgetBridge';

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
  private ctx: common.UIAbilityContext | undefined = undefined;

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
    if (this.lastRefreshAt <= 0) {
      return true;
    }
    return (Date.now() - this.lastRefreshAt) > minIntervalMs;
  }

  async refresh(silent: boolean = false): Promise<void> {
    if (!ApiKeyStore.getInstance().isUnlocked()) {
      return;
    }
    if (CursorApiClient.getInstance().isMutating()) {
      return;
    }
    if (this.loading) {
      return;
    }
    this.loading = true;
    if (!silent) {
      this.refreshing = true;
    }
    this.errorMsg = '';
    this.authExpired = false;
    this.needsPlanUpgrade = false;
    try {
      const resp = await CursorApiClient.getInstance()
        .listAgents(50, undefined, this.includeArchived, this.prUrlFilter);
      const unwrapped = unwrapAgentsList(resp as object);
      let agents = unwrapped.items ?? [];
      if (!this.includeArchived) {
        agents = agents.filter((a: AgentSummary) => a.status !== 'ARCHIVED');
      }
      this.nextCursor = unwrapped.nextCursor ?? '';
      this.mergeRunStatus(agents);
      this.source.replaceAll(agents);
      AgentCache.getInstance().saveInbox(agents);
      this.loadedOnce = true;
      this.lastRefreshAt = Date.now();
      Log.info(TAG, `inbox ${agents.length}`);
      this.enrichRunStatuses(agents.slice(0, 6));
      Notify.setRunningBadge(this.runningCount()).catch(() => {
      });
      this.pushWidget();
    } catch (e) {
      this.applyError(e, '刷新失败');
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  private mergeRunStatus(agents: AgentSummary[]): void {
    const prev = this.source.snapshot();
    for (let i = 0; i < agents.length; i++) {
      if (agents[i].latestRunStatus && `${agents[i].latestRunStatus}`.length > 0) {
        continue;
      }
      const id = agents[i].id;
      for (let j = 0; j < prev.length; j++) {
        if (prev[j].id === id) {
          const oldStatus = prev[j].latestRunStatus;
          const oldResult = prev[j].latestResult ?? '';
          const oldRepos = prev[j].repos;
          if (oldStatus) {
            agents[i].latestRunStatus = oldStatus;
          }
          if (oldResult.length > 0) {
            agents[i].latestResult = oldResult;
          }
          const curRepos = agents[i].repos;
          if ((!curRepos || curRepos.length === 0) && oldRepos) {
            agents[i].repos = oldRepos;
          }
          break;
        }
      }
    }
  }

  /** Fetch latest run status for a few agents so Inbox can show running state. */
  private async enrichRunStatuses(agents: AgentSummary[]): Promise<void> {
    const tasks: Promise<void>[] = [];
    for (let i = 0; i < agents.length; i++) {
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
              snap[j].latestRunStatus = run.status;
              applyRunGit(snap[j], run);
              applyRunResult(snap[j], run);
              this.source.updateAt(j, snap[j]);
              break;
            }
          }
        } catch (_e) {
        }
      })());
    }
    if (tasks.length > 0) {
      await Promise.all(tasks);
      AgentCache.getInstance().saveInbox(this.source.snapshot());
      Notify.setRunningBadge(this.runningCount()).catch(() => {
      });
      this.pushWidget();
    }
  }

  async loadMore(): Promise<void> {
    if (this.loadingMore || this.loading || this.nextCursor.length === 0) {
      return;
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
      const merged = this.source.snapshot().concat(more);
      this.source.replaceAll(merged);
      AgentCache.getInstance().saveInbox(merged);
    } catch (e) {
      this.applyError(e, '加载更多失败');
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
    this.source.prepend(agent);
    AgentCache.getInstance().saveInbox(this.source.snapshot());
    this.pushWidget();
  }

  removeLocal(agentId: string): void {
    this.source.removeById(agentId);
    AgentCache.getInstance().saveInbox(this.source.snapshot());
    this.pushWidget();
  }

  private pushWidget(): void {
    if (!this.ctx) {
      return;
    }
    const snap = WidgetBridge.snapFromInbox(this.source.snapshot(), this.runningCount());
    WidgetBridge.publish(this.ctx, snap).catch(() => {
    });
  }

  async archive(agentId: string): Promise<boolean> {
    try {
      await CursorApiClient.getInstance().archiveAgent(agentId);
      if (!this.includeArchived) {
        this.removeLocal(agentId);
      } else {
        await this.refresh(true);
      }
      return true;
    } catch (e) {
      this.applyError(e, '归档失败');
      return false;
    }
  }

  async unarchive(agentId: string): Promise<boolean> {
    try {
      await CursorApiClient.getInstance().unarchiveAgent(agentId);
      await this.refresh(true);
      return true;
    } catch (e) {
      this.applyError(e, '取消归档失败');
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

function applyRunResult(agent: AgentSummary, run: Run): void {
  const raw = (run.result ?? '').replace(/\s+/g, ' ').trim();
  if (raw.length === 0) {
    return;
  }
  agent.latestResult = raw.length > 120 ? `${raw.substring(0, 118)}…` : raw;
}
