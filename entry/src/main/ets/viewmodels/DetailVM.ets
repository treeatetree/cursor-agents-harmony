import { ApiException, AgentDetail, AgentSummary, ArtifactInfo, ConversationMessage,
  GitBranch, McpServerDef, Run, RunStatus, RunUsage } from '../models/Api';
import { SseFrame, ToolCallEvent } from '../models/Sse';
import { TimelineItem } from '../models/Timeline';
import { CursorApiClient } from '../api/CursorApiClient';
import { StreamCoordinator } from '../api/StreamCoordinator';
import { unwrapUsageRuns, unwrapAgentDetail, unwrapCreateAgent } from '../api/ApiUnwrap';
import { TimelineSource } from '../datasource/TimelineSource';
import { AgentCache } from '../store/AgentCache';
import { AgentPrefetch } from '../store/AgentPrefetch';
import { CreateDraftStore } from '../store/CreateDraftStore';
import { InboxVM } from './InboxVM';
import { PrefStore } from '../store/PrefStore';
import { Throttle } from '../utils/Throttle';
import { Haptics } from '../utils/Haptics';
import { clipNotice } from '../utils/MarkdownParse';
import { NetworkMonitor } from '../utils/NetworkMonitor';
import { UnreadStore } from '../store/UnreadStore';
import { LiveIsland } from '../utils/LiveIsland';
import { ThemeStore } from '../store/ThemeStore';
import { Log } from '../utils/Log';
import { formatTokenShort } from '../utils/DisplayFmt';
import { toApiMcp } from '../utils/AgentCapabilities';
import { countSteps, dropLastStep, isProgressText, lastNonEmptyLine, lastStep } from '../utils/StreamText';
import { usedToolFromEvent } from '../utils/TimelineCopy';
import { gitCompareUrl, isOriginRepo } from '../utils/GitLinks';
import { PromptImage, toApiImages } from '../utils/ImagePicker';
import { formatModelSent, modelSentJson, modelSentTags } from '../utils/ModelGroups';
import { convFingerprint, keepPendingTurns, mergeCachedActivity, restoreUserSentTags } from '../utils/TimelineMerge';
import { SessionDiag } from '../utils/SessionDiag';
import { capTimeline } from '../utils/CacheLimit';
import { countNewContent, findUnreadAnchor, lastContentKey, visibleTimeline } from '../utils/TimelineView';
import { canApplyRunStatus, isNewerIso, isTerminalStatus } from '../utils/RunState';
import { OpIdStore } from '../store/OpIdStore';
import { RunStateMachine } from './RunStateMachine';
import { ArtifactService } from './ArtifactService';
import { StreamSession } from '../api/StreamSession';
import { canFlushQueue } from './FollowUpQueue';

const TAG = 'DetailVM';

export class DetailVM {
  private static activeInstance: DetailVM | undefined = undefined;

  static getActive(): DetailVM | undefined {
    return DetailVM.activeInstance;
  }

  agentId: string = '';
  name: string = '';
  status: string = '';
  url: string = '';
  runStatus: string = '';
  activeRunId: string = '';
  resultText: string = '';
  branches: GitBranch[] = [];
  durationMs: number = 0;
  repoLabel: string = '';
  envLabel: string = '';
  metaLine: string = '';
  usageLabel: string = '';
  artifacts: ArtifactInfo[] = [];
  usageRuns: RunUsage[] = [];
  outcomeHighlight: boolean = false;
  streamNotice: string = '';
  loading: boolean = false;
  sending: boolean = false;
  cancelling: boolean = false;
  errorMsg: string = '';
  deleted: boolean = false;
  needsPlanUpgrade: boolean = false;
  stickToBottom: boolean = false;
  followUpMode: string = 'agent';
  followUpModel: string = '';
  followUpParams: Object[] = [];
  followUpMcp: McpServerDef[] = [];
  queuedFollowUp: string = '';
  queuedImages: PromptImage[] = [];
  queueImagesLost: boolean = false;
  lastFailedPrompt: string = '';
  lastFailedImages: PromptImage[] = [];
  createRetryable: boolean = false;
  repoUrl: string = '';
  startingRef: string = '';
  compareUrl: string = '';
  syncing: boolean = false;
  convError: string = '';
  unreadAnchorKey: string = '';
  unreadNewCount: number = 0;
  source: TimelineSource = new TimelineSource();

  private uiFlush: Throttle;
  private eventIdFlush: Throttle;
  private timelineFlush: Throttle;
  private dirty: boolean = false;
  private activeAssistantKey: string = '';
  private activeThinkingKey: string = '';
  private activeProgressKey: string = '';
  private progressSealed: boolean = true;
  private runHasTools: boolean = false;
  private pendingEventId: string = '';
  private pollTimer: number = -1;
  private queueTimer: number = -1;
  private connectNoticeTimer: number = -1;
  private cancelNoticeTimer: number = -1;
  private pendingConnectNotice: boolean = false;
  private queueRetries: number = 0;
  private convKey: string = '';
  private streamRunId: string = '';
  private streamFrames: number = 0;
  private streamEarlyDone: number = 0;
  private followStartedAt: number = 0;
  private followFirstFrame: boolean = false;
  private openWasUnread: boolean = false;
  private openGen: number = 0;
  private streamSession: number = 0;
  private lastRunUpdatedAt: string = '';
  private unknownSubmit: boolean = false;
  private phaseMachine: RunStateMachine = new RunStateMachine();
  private artifactsSvc: ArtifactService = new ArtifactService();
  private streamSessionHandle: StreamSession = new StreamSession();
  private onUi: (() => void) | undefined = undefined;

  constructor() {
    this.uiFlush = new Throttle(100, () => {
      this.source.flushChanges();
      if (this.dirty && this.onUi) {
        this.dirty = false;
        this.onUi();
      }
    });
    this.eventIdFlush = new Throttle(800, () => {
      this.persistLastEventId();
    });
    this.timelineFlush = new Throttle(4000, () => {
      this.persistTimeline();
    });
  }

  setUiListener(cb: () => void): void {
    this.onUi = cb;
  }

  private notify(): void {
    this.dirty = true;
    this.uiFlush.kick();
  }

  private stillSession(gen: number, agentId?: string, runId?: string): boolean {
    if (this.openGen !== gen) {
      return false;
    }
    if (agentId !== undefined && agentId.length > 0 && this.agentId !== agentId) {
      return false;
    }
    if (runId !== undefined && runId.length > 0 && this.streamRunId.length > 0 &&
      this.streamRunId !== runId) {
      return false;
    }
    return true;
  }

  async open(agentId: string): Promise<void> {
    const sameSession = this.agentId === agentId && this.source.totalCount() > 0;
    const liveKeep = sameSession ? this.source.snapshot() : [];
    const keepRunId = sameSession ? this.activeRunId : '';
    const keepStreamId = sameSession ? this.streamRunId : '';
    const keepStatus = sameSession ? this.runStatus : '';
    const keepThinkKey = sameSession ? this.activeThinkingKey : '';
    const liveActive = sameSession && this.isRunActive();
    const streamAlive = liveActive && StreamCoordinator.getInstance().isActive() &&
      StreamCoordinator.getInstance().currentRunId() === this.activeRunId;
    const gen = ++this.openGen;
    if (!streamAlive) {
      this.releaseRuntime();
    }
    if (!sameSession) {
      this.activeRunId = '';
      this.streamRunId = '';
      this.runStatus = '';
      this.activeThinkingKey = '';
      this.activeAssistantKey = '';
      this.activeProgressKey = '';
      this.source.replaceAll([]);
    }
    DetailVM.activeInstance = this;
    this.agentId = agentId;
    AppStorage.setOrCreate('watchingAgentId', agentId);
    this.errorMsg = '';
    this.convError = '';
    this.deleted = false;
    this.needsPlanUpgrade = false;
    this.createRetryable = false;
    this.convKey = '';
    this.unreadAnchorKey = '';
    this.unreadNewCount = 0;
    let pendingFresh = false;
    try {
      pendingFresh = (AppStorage.get<string>('pendingFreshOpen') ?? '') === agentId;
      if (pendingFresh) {
        AppStorage.setOrCreate('pendingFreshOpen', '');
      }
    } catch (_e) {
      pendingFresh = false;
    }
    this.openWasUnread = UnreadStore.getInstance().isUnread(agentId) || pendingFresh;

    const cached = AgentCache.getInstance().loadAgent(agentId);
    let painted = false;
    let cacheHit = 'none';
    if (cached?.detail) {
      this.applyDetail(cached.detail);
      painted = true;
      cacheHit = 'detail';
    }
    if (cached?.runs && cached.runs.length > 0) {
      this.applyLatestRunMeta(cached.runs);
      painted = true;
      cacheHit = cacheHit === 'none' ? 'runs' : `${cacheHit}+runs`;
    }
    if (cached?.messages && cached.messages.length > 0) {
      this.buildConversation(cached.messages);
      this.applyMergedActivity(cached.timeline);
      this.convKey = convFingerprint(cached.messages);
      painted = true;
      cacheHit = cacheHit === 'none' ? 'messages' : `${cacheHit}+messages`;
    } else if (cached?.timeline && cached.timeline.length > 0) {
      this.source.replaceAll(cached.timeline);
      painted = true;
      cacheHit = cacheHit === 'none' ? 'timeline' : `${cacheHit}+timeline`;
    }
    if (liveKeep.length > 0) {
      this.applyMergedActivity(liveKeep);
    }
    if (keepRunId.length > 0 && liveActive) {
      this.activeRunId = keepRunId;
      this.streamRunId = keepStreamId;
      this.runStatus = keepStatus;
      this.activeThinkingKey = keepThinkKey;
    }
    this.applyUnreadScroll();
    this.loading = !painted;
    this.syncing = true;
    const cacheAgeMs = cached && cached.fetchedAt > 0 ? Date.now() - cached.fetchedAt : -1;
    const prefetchHit = AgentPrefetch.getInstance().isFresh(agentId);
    SessionDiag.emit({
      tag: TAG,
      event: 'open',
      agentId: agentId,
      extra: `cache=${cacheHit} unread=${this.openWasUnread ? 1 : 0} n=${this.source.totalCount()} cacheAgeMs=${cacheAgeMs} prefetch=${prefetchHit ? 1 : 0}`
    });
    this.notify();
    this.uiFlush.flush();

    try {
      const client = CursorApiClient.getInstance();
      const settled = await Promise.all([
        client.getAgent(agentId),
        client.getRuns(agentId, 20)
      ]);
      if (this.openGen !== gen) {
        return;
      }
      const detail = unwrapAgentDetail(settled[0] as object);
      this.applyDetail(detail);

      const runs = extractRuns(settled[1] as object);
      this.applyLatestRunMeta(runs);

      const convStarted = Date.now();
      let messages: ConversationMessage[] = [];
      let convOk = false;
      const latestId = detail.latestRunId ?? this.activeRunId;
      const cachedLatest = cached?.detail?.latestRunId ?? '';
      const cachedMsgs = cached?.messages ?? [];
      const skipConv = prefetchHit && cachedMsgs.length > 0 && latestId.length > 0 && latestId === cachedLatest;
      if (skipConv) {
        messages = cachedMsgs;
        convOk = true;
        this.convError = '';
        SessionDiag.emit({
          tag: TAG,
          event: 'conv',
          agentId: agentId,
          elapsedMs: 0,
          extra: `ok=1 n=${messages.length} cache=1 skip=1 prefetch=1`
        });
      } else {
        try {
          const conv = await client.getConversation(agentId);
          messages = conv.messages ?? [];
          convOk = true;
          this.convError = '';
        } catch (_e) {
          convOk = false;
          this.convError = '同步对话失败';
        }
        if (this.openGen !== gen) {
          return;
        }
        const convMs = Date.now() - convStarted;
        SessionDiag.emit({
          tag: TAG,
          event: 'conv',
          agentId: agentId,
          elapsedMs: convMs,
          extra: `ok=${convOk ? 1 : 0} n=${messages.length} cache=${painted ? 1 : 0} prefetch=${prefetchHit ? 1 : 0}`
        });
      }
      const nextKey = convFingerprint(messages);
      const empty = this.source.totalCount() === 0;
      if (convOk && messages.length > 0 && (nextKey !== this.convKey || empty)) {
        const live = this.source.snapshot();
        this.buildConversation(messages);
        this.applyMergedActivity(cached?.timeline);
        this.applyMergedActivity(live);
        if (liveKeep.length > 0) {
          this.applyMergedActivity(liveKeep);
        }
        this.convKey = nextKey;
        this.applyUnreadScroll();
      } else if (convOk && messages.length === 0 && !painted) {
        this.buildRunsFallback(runs);
        this.applyUnreadScroll();
      } else if (!convOk && !painted) {
        this.errorMsg = this.convError;
      }
      AgentCache.getInstance().saveAgent(agentId, detail, runs, undefined, convOk ? messages : undefined);
      this.persistTimeline(true);

      if (this.openGen !== gen) {
        return;
      }
      if (keepRunId.length > 0 && liveActive) {
        this.activeRunId = keepRunId;
        this.streamRunId = keepStreamId;
        this.runStatus = keepStatus;
        this.activeThinkingKey = keepThinkKey;
      }
      if (this.activeRunId.length > 0) {
        const run = await client.getRun(agentId, this.activeRunId);
        this.applyRunSnapshot(run);
        if (this.isRunActive()) {
          const coord = StreamCoordinator.getInstance();
          if (!(streamAlive && coord.isActive() && coord.currentRunId() === run.id)) {
            await this.startStream(run.id);
          } else {
            this.reviveWaitingThink();
          }
        } else if (isTerminal(run.status)) {
          this.settleLive(run.id, run.status);
        }
      }

      this.loadArtifactsAndUsage();
      this.bumpInbox();
    } catch (e) {
      if (this.openGen !== gen) {
        return;
      }
      if (e instanceof ApiException) {
        this.errorMsg = e.message;
        if (e.code === 404) {
          this.deleted = true;
          this.errorMsg = '该 Agent 已删除';
          AgentCache.getInstance().saveAgent(agentId);
        } else if (e.code === 403) {
          this.needsPlanUpgrade = true;
        } else if (e.code === 401) {
          this.errorMsg = 'API Key 失效，请重新粘贴';
        }
      } else {
        this.errorMsg = '加载失败';
      }
      Log.error(TAG, this.errorMsg);
    } finally {
      if (this.openGen !== gen) {
        SessionDiag.emit({
          tag: TAG,
          event: 'open_skip',
          agentId: agentId,
          extra: `stale gen n=${this.source.totalCount()}`
        });
        return;
      }
      this.loading = false;
      this.syncing = false;
      this.rememberSeen();
      SessionDiag.emit({
        tag: TAG,
        event: 'open_done',
        agentId: agentId,
        extra: `stick=${this.stickToBottom ? 1 : 0} anchor=${this.unreadAnchorKey.length > 0 ? 1 : 0} n=${this.source.totalCount()}`
      });
      this.notify();
      this.uiFlush.flush();
    }
  }

  applyAlias(name: string): void {
    this.name = name;
    this.notify();
  }

  async retryConversation(): Promise<void> {
    if (this.agentId.length === 0) {
      return;
    }
    const gen = this.openGen;
    const agentId = this.agentId;
    this.convError = '';
    this.syncing = true;
    this.notify();
    const started = Date.now();
    try {
      const conv = await CursorApiClient.getInstance().getConversation(agentId);
      if (!this.stillSession(gen, agentId)) {
        return;
      }
      const messages = conv.messages ?? [];
      SessionDiag.emit({
        tag: TAG,
        event: 'conv_retry',
        agentId: agentId,
        elapsedMs: Date.now() - started,
        extra: `n=${messages.length}`
      });
      const nextKey = convFingerprint(messages);
      if (messages.length > 0 && nextKey !== this.convKey) {
        const live = this.source.snapshot();
        this.buildConversation(messages);
        this.applyMergedActivity(live);
        this.convKey = nextKey;
      }
    } catch (_e) {
      if (!this.stillSession(gen, agentId)) {
        return;
      }
      this.convError = '同步对话失败';
      SessionDiag.emit({
        tag: TAG,
        event: 'conv_retry',
        agentId: agentId,
        elapsedMs: Date.now() - started,
        extra: 'fail'
      });
    } finally {
      if (this.stillSession(gen, agentId)) {
        this.syncing = false;
        this.notify();
      }
    }
  }

  /** Leave the composer immediately: paint the user turn, then POST create. */
  async openFromCreate(localId: string): Promise<void> {
    const gen = ++this.openGen;
    this.releaseRuntime();
    DetailVM.activeInstance = this;
    this.agentId = localId;
    AppStorage.setOrCreate('watchingAgentId', localId);
    this.errorMsg = '';
    this.deleted = false;
    this.needsPlanUpgrade = false;
    this.convKey = '';
    this.loading = false;
    this.syncing = true;
    this.runStatus = 'CREATING';
    this.streamNotice = '';
    this.createRetryable = false;
    await CreateDraftStore.getInstance().hydrate();
    const draft = CreateDraftStore.getInstance().peek();
    const prompt = draft?.prompt ?? '';
    this.name = PrefStore.getInstance().displayName(localId, draft?.name ?? '新任务');
    const createModel = draft ? createModelOf(draft.body) : undefined;
    Log.info(TAG, `create model ${modelSentJson(createModel)}`);
    this.source.replaceAll([
      {
        key: 'seed-user',
        kind: 'userPrompt',
        runId: 'pending',
        text: prompt,
        usageShort: formatModelSent(createModel),
        sentTags: modelSentTags(createModel)
      },
      {
        key: 'seed-think',
        kind: 'thinking',
        runId: 'pending',
        text: '',
        collapsed: false,
        streaming: true
      }
    ]);
    this.stickToBottom = true;
    this.notify();
    this.uiFlush.flush();
    if (!draft) {
      this.syncing = false;
      this.errorMsg = '创建草稿丢失，请返回重试';
      this.notify();
      return;
    }
    try {
      const opId = OpIdStore.nextId('create');
      const raw = await CursorApiClient.getInstance().createAgent(draft.body, opId);
      if (this.openGen !== gen) {
        return;
      }
      const resp = unwrapCreateAgent(raw as object);
      const agent = resp.agent;
      if (!agent || !agent.id) {
        throw new ApiException(500, '创建响应缺少 id', 'invalid_create', true);
      }
      const nowIso = agent.updatedAt && agent.updatedAt.length > 0 ? agent.updatedAt :
        (agent.createdAt && agent.createdAt.length > 0 ? agent.createdAt : new Date().toISOString());
      const created: AgentSummary = {
        id: agent.id,
        name: agent.name ?? this.name,
        status: agent.status ?? 'ACTIVE',
        url: agent.url ?? '',
        createdAt: agent.createdAt && agent.createdAt.length > 0 ? agent.createdAt : nowIso,
        updatedAt: nowIso,
        lastUserAt: nowIso,
        latestRunId: resp.run?.id,
        latestRunStatus: resp.run?.status ?? 'CREATING'
      };
      InboxVM.getInstance().replaceHeld(localId, created);
      this.agentId = agent.id;
      AppStorage.setOrCreate('watchingAgentId', agent.id);
      this.applyDetail(agent);
      const userIdx = this.source.findIndexByKey('seed-user');
      if (userIdx >= 0) {
        const user = this.source.getData(userIdx);
        user.runId = resp.run?.id ?? 'pending';
        this.source.updateAt(userIdx, user);
      }
      const thinkIdx = this.source.findIndexByKey('seed-think');
      if (thinkIdx >= 0) {
        const think = this.source.getData(thinkIdx);
        think.key = `thinking-${resp.run?.id ?? 'pending'}`;
        think.runId = resp.run?.id ?? 'pending';
        think.streaming = true;
        this.source.updateAt(thinkIdx, think);
        this.activeThinkingKey = think.key;
      }
      if (resp.run && resp.run.id) {
        this.applyRunSnapshot(resp.run);
        this.notify();
        this.uiFlush.flush();
        await this.startStream(resp.run.id);
      }
      CreateDraftStore.getInstance().clear();
      this.createRetryable = false;
      this.unknownSubmit = false;
      this.loadArtifactsAndUsage();
    } catch (e) {
      if (!this.stillSession(gen)) {
        return;
      }
      if (e instanceof ApiException && (e.apiCode === 'network' || e.code === 0)) {
        this.unknownSubmit = true;
        this.errorMsg = '提交结果未知，请先回 Inbox 确认，不要直接重发';
      } else if (e instanceof ApiException) {
        this.errorMsg = e.message;
      } else {
        this.errorMsg = '创建失败';
      }
      this.runStatus = 'ERROR';
      this.createRetryable = true;
      const thinkIdx = this.source.findIndexByKey('seed-think');
      if (thinkIdx >= 0) {
        const think = this.source.getData(thinkIdx);
        think.streaming = false;
        this.source.updateAt(thinkIdx, think);
      }
      InboxVM.getInstance().removeLocal(localId);
      InboxVM.getInstance().noteCreateFailed(this.name);
      Haptics.fail();
      Log.error(TAG, this.errorMsg);
    } finally {
      this.syncing = false;
      this.notify();
      this.uiFlush.flush();
    }
  }

  private bumpInbox(): void {
    if (this.agentId.length === 0) {
      return;
    }
    InboxVM.getInstance().touch(this.agentId, this.name, this.runStatus);
  }

  private releaseRuntime(): void {
    StreamCoordinator.getInstance().release();
    this.clearPoll();
    this.clearQueueTimer();
    this.clearNoticeTimers();
    this.eventIdFlush.flush();
    this.timelineFlush.flush();
    this.persistTimeline();
  }

  private applyDetail(detail: AgentDetail): void {
    const apiName = detail.name ?? this.agentId;
    this.name = PrefStore.getInstance().displayName(this.agentId, apiName);
    this.status = detail.status ?? '';
    this.url = detail.url ?? '';
    this.activeRunId = detail.latestRunId ?? this.activeRunId;
    if (detail.repos && detail.repos.length > 0) {
      const u = detail.repos[0].url ?? '';
      this.repoLabel = shortRepo(u);
      this.repoUrl = u;
      this.startingRef = detail.repos[0].startingRef ?? '';
    }
    this.recomputeCompareUrl();
    if (detail.env?.name && detail.env.name.length > 0) {
      this.envLabel = detail.env.name;
    } else if (detail.env?.type) {
      this.envLabel = detail.env.type;
    } else {
      this.envLabel = '';
    }
    const bits: string[] = [];
    if (this.envLabel.length > 0) {
      bits.push(this.envLabel);
    }
    if (detail.autoCreatePR === true) {
      bits.push('AutoPR');
    }
    if (detail.workOnCurrentBranch === true) {
      bits.push('当前分支');
    }
    if (detail.openAsCursorGithubApp === true) {
      bits.push('Cursor App');
    }
    if (detail.skipReviewerRequest === true) {
      bits.push('跳过评审');
    }
    const subs = detail.customSubagents ?? [];
    if (subs.length > 0) {
      bits.push(`子代理 ${subs.length}`);
    }
    this.metaLine = bits.join(' · ');
  }

  private async loadArtifactsAndUsage(): Promise<void> {
    const gen = this.openGen;
    const agentId = this.agentId;
    const bundle = await this.artifactsSvc.load(agentId);
    if (!this.stillSession(gen, agentId)) {
      return;
    }
    this.artifacts = bundle.artifacts;
    this.usageLabel = bundle.usageLabel;
    this.usageRuns = bundle.usageRuns;
    this.applyUsageToHeaders();
    this.notify();
  }

  private applyUsageToHeaders(): void {
    for (let i = 0; i < this.usageRuns.length; i++) {
      const r = this.usageRuns[i];
      const total = r.usage.totalTokens ?? 0;
      if (total <= 0 || r.id.length === 0) {
        continue;
      }
      const idx = this.source.findIndexByKey(`run-${r.id}`);
      if (idx >= 0) {
        this.source.mutateAt(idx, (item: TimelineItem) => {
          item.usageShort = formatTokenShort(total);
        });
      }
    }
  }

  async openArtifact(path: string): Promise<string> {
    const resp = await CursorApiClient.getInstance().downloadArtifact(this.agentId, path);
    return resp.url ?? '';
  }

  async unarchive(): Promise<boolean> {
    try {
      await CursorApiClient.getInstance().unarchiveAgent(this.agentId);
      this.status = 'ACTIVE';
      this.notify();
      return true;
    } catch (e) {
      if (e instanceof ApiException) {
        this.errorMsg = e.message;
      } else {
        this.errorMsg = '取消归档失败';
      }
      this.notify();
      return false;
    }
  }

  close(): void {
    this.openGen++;
    if (DetailVM.activeInstance === this) {
      DetailVM.activeInstance = undefined;
      AppStorage.setOrCreate('watchingAgentId', '');
    }
    this.streamSessionHandle.release();
    StreamCoordinator.getInstance().release();
    this.clearPoll();
    this.eventIdFlush.flush();
    this.eventIdFlush.cancel();
    this.timelineFlush.flush();
    this.timelineFlush.cancel();
    this.persistTimeline(true);
    this.uiFlush.cancel();
    this.source.replaceAll([]);
    this.activeAssistantKey = '';
    this.activeThinkingKey = '';
    this.activeProgressKey = '';
    this.progressSealed = true;
    this.runHasTools = false;
    this.pendingEventId = '';
    this.streamNotice = '';
    this.resultText = '';
    this.branches = [];
    this.runStatus = '';
    this.activeRunId = '';
    this.streamRunId = '';
    this.durationMs = 0;
    this.artifacts = [];
    this.usageLabel = '';
    this.usageRuns = [];
    this.persistQueue();
    this.queuedImages = [];
    this.queueImagesLost = false;
    this.createRetryable = false;
    this.queueRetries = 0;
    this.compareUrl = '';
    this.clearQueueTimer();
    this.clearNoticeTimers();
    ThemeStore.getInstance().setKeepScreenOn(false);
  }

  clearExpandedState(): void {
    this.notify();
  }

  toggleCollapsed(key: string): void {
    const idx = this.source.findIndexByKey(key);
    if (idx < 0) {
      return;
    }
    const cur = this.source.getData(idx);
    const willOpen = cur.collapsed !== false;
    cur.collapsed = !willOpen;
    cur.pinnedOpen = willOpen;
    this.source.updateAt(idx, cur);
    this.stickToBottom = false;
    this.notify();
  }

  async retryCreate(): Promise<void> {
    if (this.unknownSubmit) {
      this.errorMsg = '提交结果未知，请先回 Inbox 确认是否已创建';
      this.notify();
      return;
    }
    if (this.agentId.indexOf('local-') !== 0) {
      return;
    }
    const draft = CreateDraftStore.getInstance().peek();
    if (draft) {
      const nowIso = new Date().toISOString();
      InboxVM.getInstance().prependOptimistic({
        id: draft.localId,
        name: draft.name,
        status: 'ACTIVE',
        url: '',
        createdAt: nowIso,
        updatedAt: nowIso,
        lastUserAt: nowIso,
        latestRunStatus: 'CREATING'
      });
    }
    await this.openFromCreate(this.agentId);
  }

  async retryConnection(): Promise<void> {
    this.errorMsg = '';
    if (this.agentId.indexOf('local-') === 0 || this.createRetryable) {
      await this.retryCreate();
      return;
    }
    if (this.activeRunId.length > 0 && this.isRunActive()) {
      await this.startStream(this.activeRunId, true);
      return;
    }
    if (this.agentId.length > 0) {
      await this.open(this.agentId);
    }
  }

  async retryQueuedFollowUp(): Promise<void> {
    this.queueRetries = 0;
    this.errorMsg = '';
    await this.flushQueuedFollowUp();
  }

  async retryFailedFollowUp(): Promise<boolean> {
    const prompt = this.lastFailedPrompt;
    const images = this.lastFailedImages;
    if (prompt.length === 0 && images.length === 0) {
      return false;
    }
    this.lastFailedPrompt = '';
    this.lastFailedImages = [];
    return await this.sendFollowUp(prompt, images);
  }

  async followUp(text: string, images: PromptImage[] = []): Promise<boolean> {
    const prompt = text.trim();
    if ((prompt.length === 0 && images.length === 0) || this.sending) {
      return false;
    }
    const bodyText = prompt.length > 0 ? prompt : '请查看附图';
    if (this.isRunActive()) {
      this.queuedFollowUp = bodyText;
      this.queuedImages = images;
      this.queueImagesLost = false;
      this.errorMsg = '';
      this.streamNotice = '结束后发送';
      this.persistQueue();
      this.notify();
      return true;
    }
    return await this.sendFollowUp(bodyText, images);
  }

  clearQueuedFollowUp(): void {
    this.queuedFollowUp = '';
    this.queuedImages = [];
    this.queueImagesLost = false;
    this.queueRetries = 0;
    this.clearQueueTimer();
    this.persistQueue();
    if (this.streamNotice === '结束后发送' || this.streamNotice.indexOf('结束后') >= 0) {
      this.streamNotice = '';
    }
    this.notify();
  }

  takeQueuedForEdit(): string {
    const text = this.queuedFollowUp;
    this.clearQueuedFollowUp();
    return text;
  }

  private async sendFollowUp(prompt: string, images: PromptImage[] = []): Promise<boolean> {
    const gen = this.openGen;
    const agentId = this.agentId;
    this.sending = true;
    this.errorMsg = '';
    this.streamNotice = '正在提交…';
    this.followStartedAt = Date.now();
    this.followFirstFrame = false;
    SessionDiag.emit({
      tag: TAG,
      event: 'follow',
      agentId: this.agentId,
      extra: 'start'
    });
    const tempKey = `user-${Date.now()}`;
    const followModel: Record<string, Object> | undefined = this.followUpModel.length > 0 ?
      followModelBody(this.followUpModel, this.followUpParams) : undefined;
    Log.info(TAG, `follow model ${modelSentJson(followModel)}`);
    this.source.append({
      key: tempKey,
      kind: 'userPrompt',
      runId: 'pending',
      text: images.length > 0 ? `${prompt}\n（${images.length} 张图）` : prompt,
      usageShort: formatModelSent(followModel),
      sentTags: modelSentTags(followModel)
    });
    this.source.append({
      key: `thinking-${tempKey}`,
      kind: 'thinking',
      runId: 'pending',
      text: '',
      collapsed: false,
      streaming: true
    });
    this.stickToBottom = true;
    this.notify();
    this.uiFlush.flush();
    this.persistTimeline(true);
    SessionDiag.emit({
      tag: TAG,
      event: 'follow',
      agentId: this.agentId,
      elapsedMs: Date.now() - this.followStartedAt,
      extra: 'placeholder'
    });
    this.bumpInbox();
    InboxVM.getInstance().markUserAt(this.agentId);
    try {
      const body: Record<string, Object> = {};
      const promptObj: Record<string, Object> = {};
      promptObj['text'] = prompt;
      if (images.length > 0) {
        promptObj['images'] = toApiImages(images);
      }
      body['prompt'] = promptObj;
      if (this.followUpMode.length > 0) {
        body['mode'] = this.followUpMode;
      }
      if (this.followUpModel.length > 0) {
        const model: Record<string, Object> = {};
        model['id'] = this.followUpModel;
        if (this.followUpParams.length > 0) {
          model['params'] = this.followUpParams;
        }
        body['model'] = model;
      }
      const mcp = toApiMcp(this.followUpMcp);
      if (mcp.length > 0) {
        body['mcpServers'] = mcp;
      }
      const opId = OpIdStore.nextId(`run:${agentId}`);
      const run = await CursorApiClient.getInstance().createRun(agentId, body, opId);
      if (!this.stillSession(gen, agentId)) {
        return false;
      }
      SessionDiag.emit({
        tag: TAG,
        event: 'createRun',
        agentId: this.agentId,
        runId: run.id,
        extra: 'ok'
      });
      SessionDiag.emit({
        tag: TAG,
        event: 'follow',
        agentId: this.agentId,
        runId: run.id,
        elapsedMs: Date.now() - this.followStartedAt,
        extra: 'ok'
      });
      this.lastFailedPrompt = '';
      this.lastFailedImages = [];
      this.queueRetries = 0;
      const idx = this.source.findIndexByKey(tempKey);
      if (idx >= 0) {
        const item = this.source.getData(idx);
        item.runId = run.id;
        this.source.updateAt(idx, item);
      }
      const thinkIdx = this.source.findIndexByKey(`thinking-${tempKey}`);
      if (thinkIdx >= 0) {
        const think = this.source.getData(thinkIdx);
        think.key = `thinking-${run.id}`;
        think.runId = run.id;
        think.streaming = true;
        think.collapsed = false;
        this.source.updateAt(thinkIdx, think);
        this.activeThinkingKey = think.key;
      }
      this.source.append({
        key: `run-${run.id}`,
        kind: 'runHeader',
        runId: run.id,
        statusLabel: run.status,
        text: runStatusZh(run.status)
      });
      this.applyRunSnapshot(run);
      InboxVM.getInstance().touch(this.agentId, this.name, run.status,
        run.updatedAt && run.updatedAt.length > 0 ? run.updatedAt : new Date().toISOString(),
        run.id);
      this.sending = false;
      this.notify();
      this.uiFlush.flush();
      await this.startStream(run.id);
      return true;
    } catch (e) {
      if (!this.stillSession(gen, agentId)) {
        return false;
      }
      const idx = this.source.findIndexByKey(tempKey);
      if (idx >= 0) {
        const item = this.source.getData(idx);
        item.failed = true;
        this.source.updateAt(idx, item);
      }
      const thinkIdx = this.source.findIndexByKey(`thinking-${tempKey}`);
      if (thinkIdx >= 0) {
        this.source.removeAt(thinkIdx);
      }
      this.lastFailedPrompt = prompt;
      this.lastFailedImages = images;
      if (e instanceof ApiException && (e.code === 409 || e.apiCode === 'agent_busy')) {
        this.queuedFollowUp = prompt;
        this.queuedImages = images;
        this.persistQueue();
        this.streamNotice = 'Agent 忙碌，稍后自动发送';
        this.scheduleFlushQueue(800 * Math.max(1, this.queueRetries + 1));
        Haptics.warn();
        SessionDiag.emit({
          tag: TAG,
          event: 'follow',
          agentId: this.agentId,
          elapsedMs: Date.now() - this.followStartedAt,
          extra: 'busy'
        });
        return true;
      }
      if (e instanceof ApiException && (e.apiCode === 'network' || e.code === 0)) {
        this.errorMsg = '提交结果未知，请先确认是否已发出，不要直接重发';
      } else if (e instanceof ApiException) {
        this.errorMsg = e.message;
      } else {
        this.errorMsg = '追问失败';
      }
      if (!NetworkMonitor.getInstance().online) {
        this.errorMsg = '网络断开，恢复后可重发';
      }
      SessionDiag.emit({
        tag: TAG,
        event: 'follow',
        agentId: this.agentId,
        elapsedMs: Date.now() - this.followStartedAt,
        extra: 'fail'
      });
      Haptics.fail();
      return false;
    } finally {
      if (this.stillSession(gen, agentId)) {
        this.sending = false;
        this.notify();
        this.uiFlush.flush();
      }
    }
  }

  private scheduleFlushQueue(delayMs: number = 700): void {
    if (this.queuedFollowUp.trim().length === 0) {
      return;
    }
    this.clearQueueTimer();
    this.queueTimer = setTimeout(() => {
      this.queueTimer = -1;
      this.flushQueuedFollowUp();
    }, delayMs) as number;
  }

  private clearQueueTimer(): void {
    if (this.queueTimer >= 0) {
      clearTimeout(this.queueTimer);
      this.queueTimer = -1;
    }
  }

  private persistQueue(): void {
    if (this.agentId.length === 0) {
      return;
    }
    PrefStore.getInstance().setQueuedFollowUp(this.agentId, this.queuedFollowUp.trim()).catch(() => {
    });
    PrefStore.getInstance().setQueuedImageCount(this.agentId, this.queuedImages.length).catch(() => {
    });
    if (this.queuedImages.length > 0) {
      AgentCache.getInstance().saveQueueImages(this.agentId, this.queuedImages);
    } else {
      AgentCache.getInstance().clearQueueImages(this.agentId);
    }
  }

  async restoreQueue(): Promise<void> {
    if (this.agentId.length === 0) {
      return;
    }
    const gen = this.openGen;
    const agentId = this.agentId;
    const saved = await PrefStore.getInstance().getQueuedFollowUp(agentId);
    if (!this.stillSession(gen, agentId)) {
      return;
    }
    const imgCount = await PrefStore.getInstance().getQueuedImageCount(agentId);
    if (!this.stillSession(gen, agentId) || saved.length === 0) {
      return;
    }
    this.queuedFollowUp = saved;
    const cachedImgs = AgentCache.getInstance().loadQueueImages(agentId);
    if (cachedImgs.length > 0) {
      const imgs: PromptImage[] = [];
      for (let i = 0; i < cachedImgs.length; i++) {
        const row = cachedImgs[i] as PromptImage;
        if (row && row.data && row.data.length > 0) {
          imgs.push(row);
        }
      }
      this.queuedImages = imgs;
      this.queueImagesLost = imgCount > 0 && imgs.length === 0;
    } else {
      this.queueImagesLost = imgCount > 0 && this.queuedImages.length === 0;
    }
    if (this.isRunActive()) {
      this.streamNotice = '结束后发送';
      this.notify();
      return;
    }
    this.scheduleFlushQueue(400);
  }

  private async flushQueuedFollowUp(): Promise<void> {
    const gen = this.openGen;
    const agentId = this.agentId;
    const q = this.queuedFollowUp.trim();
    if (q.length === 0) {
      return;
    }
    if (!canFlushQueue({
      text: q,
      images: this.queuedImages,
      retries: this.queueRetries
    }, this.sending, this.isRunActive())) {
      if (this.queueRetries >= 5) {
        this.errorMsg = '追问排队发送失败，请手动重试';
        this.streamNotice = '';
        this.notify();
        return;
      }
      this.scheduleFlushQueue(1600);
      return;
    }
    if (this.queueRetries >= 5) {
      this.errorMsg = '追问排队发送失败，请手动重试';
      this.streamNotice = '';
      this.notify();
      return;
    }
    this.queueRetries += 1;
    const imgs = this.queuedImages;
    this.queuedFollowUp = '';
    this.queuedImages = [];
    this.persistQueue();
    if (this.streamNotice === '结束后发送' || this.streamNotice.indexOf('稍后自动') >= 0) {
      this.streamNotice = '';
    }
    const ok = await this.sendFollowUp(q, imgs);
    if (!this.stillSession(gen, agentId)) {
      return;
    }
    if (!ok && this.queuedFollowUp.length === 0) {
      this.queuedFollowUp = q;
      this.queuedImages = imgs;
      this.persistQueue();
    }
  }

  private announceFinished(status: string, raw: string): void {
    const zh = runStatusZh(status);
    const snippet = clipNotice(raw.length > 0 ? raw : this.resultText, 72);
    AppStorage.setOrCreate('pendingNotice',
      snippet.length > 0 ? `${this.name} ${zh} · ${snippet}` : `${this.name} ${zh}`);
    if (DetailVM.activeInstance !== this) {
      UnreadStore.getInstance().markFinished(this.agentId, this.name, zh, snippet, this.repoLabel)
        .catch(() => {
        });
    }
  }

  private afterRunSettled(): void {
    ThemeStore.getInstance().setKeepScreenOn(false);
    LiveIsland.finish(runStatusZh(this.runStatus), this.agentId).catch(() => {
    });
    if (this.streamRunId === this.activeRunId) {
      this.streamRunId = '';
    }
    this.loadArtifactsAndUsage();
    this.refreshRunUsage(this.activeRunId);
    this.recomputeCompareUrl();
    if (!this.isRunActive()) {
      this.scheduleFlushQueue(400);
    }
  }

  private async refreshRunUsage(runId: string): Promise<void> {
    if (runId.length === 0) {
      return;
    }
    const gen = this.openGen;
    const agentId = this.agentId;
    try {
      const usage = await CursorApiClient.getInstance().getUsage(agentId, runId);
      if (!this.stillSession(gen, agentId)) {
        return;
      }
      const runs = unwrapUsageRuns(usage as object);
      let total = 0;
      if (runs.length > 0) {
        total = runs[0].usage.totalTokens ?? 0;
      }
      if (total <= 0) {
        return;
      }
      const short = formatTokenShort(total);
      const key = `run-${runId}`;
      const idx = this.source.findIndexByKey(key);
      if (idx >= 0) {
        this.source.mutateAt(idx, (item: TimelineItem) => {
          item.usageShort = short;
        });
        this.notify();
      }
    } catch (_e) {
    }
  }

  async cancelActive(): Promise<void> {
    if (this.activeRunId.length === 0 || this.cancelling) {
      return;
    }
    this.cancelling = true;
    this.notify();
    try {
      await CursorApiClient.getInstance().cancelRun(this.agentId, this.activeRunId);
      this.runStatus = 'CANCELLED';
      this.streamNotice = '已取消';
      this.armCancelNoticeClear();
      this.finishStreamingItems();
      this.settleLive(this.activeRunId, 'CANCELLED');
      StreamCoordinator.getInstance().release();
      Haptics.warn();
    } catch (e) {
      if (e instanceof ApiException && e.code === 409) {
        // already terminal — refresh
        try {
          const run = await CursorApiClient.getInstance().getRun(this.agentId, this.activeRunId);
          this.applyRunSnapshot(run);
          this.finishStreamingItems();
          this.settleLive(run.id, run.status);
        } catch (_e) {
        }
      } else if (e instanceof ApiException) {
        this.errorMsg = e.message;
      } else {
        this.errorMsg = '取消失败';
      }
    } finally {
      this.cancelling = false;
      this.notify();
      if (!this.isRunActive()) {
        this.afterRunSettled();
      }
    }
  }

  isRunActive(): boolean {
    return this.activeRunId.length > 0 &&
      (this.runStatus === 'RUNNING' || this.runStatus === 'CREATING');
  }

  private settleLive(runId: string, status: string): void {
    if (status.length > 0) {
      this.runStatus = status;
    }
    const snap = this.source.snapshot();
    for (let i = 0; i < snap.length; i++) {
      const it = snap[i];
      const same = it.runId === runId || it.runId === 'pending' ||
        (runId.length > 0 && (it.key.indexOf(runId) >= 0));
      if (!same && it.streaming !== true) {
        continue;
      }
      this.source.mutateAt(i, (item: TimelineItem) => {
        item.streaming = false;
        if (item.runId === 'pending' && runId.length > 0) {
          item.runId = runId;
        }
      });
    }
    if (runId.length > 0 && status.length > 0) {
      this.upsertRunHeader(runId, status);
    }
    this.activeAssistantKey = '';
    this.activeThinkingKey = '';
    this.activeProgressKey = '';
    this.progressSealed = true;
    if (this.streamNotice !== '结束后发送' && this.streamNotice.indexOf('结束后') < 0) {
      if (this.streamNotice === '连接中…' || this.streamNotice.indexOf('重连') >= 0 ||
        this.streamNotice.indexOf('异常') >= 0 || this.streamNotice.indexOf('流已过期') >= 0) {
        this.streamNotice = '';
      }
    }
    this.persistTimeline(true);
    InboxVM.getInstance().touch(this.agentId, this.name, status);
    if (isTerminal(status as RunStatus)) {
      this.afterRunSettled();
    }
    this.notify();
  }

  private freezeLiveOverlay(): void {
    const snap = this.source.snapshot();
    for (let i = 0; i < snap.length; i++) {
      if (snap[i].streaming === true) {
        this.source.mutateAt(i, (item: TimelineItem) => {
          item.streaming = false;
        });
      }
    }
  }

  /** Call when detail page becomes visible again after background. */
  async resumeIfNeeded(): Promise<void> {
    if (!this.isRunActive()) {
      return;
    }
    if (StreamCoordinator.getInstance().isActive() &&
      StreamCoordinator.getInstance().currentRunId() === this.activeRunId) {
      return;
    }
    Log.info(TAG, `resume stream ${this.activeRunId}`);
    await this.startStream(this.activeRunId, true);
  }

  async archive(): Promise<boolean> {
    const ok = await InboxVM.getInstance().archive(this.agentId);
    if (ok) {
      this.status = 'ARCHIVED';
      this.notify();
    } else {
      this.errorMsg = InboxVM.getInstance().errorMsg.length > 0 ?
        InboxVM.getInstance().errorMsg : '归档失败';
      this.notify();
    }
    return ok;
  }

  async deleteRemote(): Promise<boolean> {
    try {
      await CursorApiClient.getInstance().deleteAgent(this.agentId);
      return true;
    } catch (e) {
      if (e instanceof ApiException) {
        this.errorMsg = e.message;
      } else {
        this.errorMsg = '删除失败';
      }
      this.notify();
      return false;
    }
  }

  private async startStream(runId: string, resume: boolean = false): Promise<void> {
    const gen = this.openGen;
    const agentId = this.agentId;
    this.streamSession = gen;
    this.streamSessionHandle.bind(agentId, runId);
    this.activeRunId = runId;
    this.streamRunId = runId;
    this.streamFrames = 0;
    if (!resume) {
      this.streamEarlyDone = 0;
    }
    SessionDiag.emit({
      tag: TAG,
      event: 'stream_start',
      agentId: this.agentId,
      runId: runId,
      extra: resume ? 'resume' : 'fresh'
    });
    if (resume) {
      this.freezeLiveOverlay();
      this.reviveWaitingThink();
    }
    if (!resume) {
      this.activeAssistantKey = '';
      this.activeProgressKey = '';
      this.progressSealed = true;
      this.runHasTools = false;
      const existingThink = this.source.findIndexByKey(`thinking-${runId}`);
      this.activeThinkingKey = existingThink >= 0 ? `thinking-${runId}` : '';
    }
    if (this.streamNotice !== '结束后发送' && this.streamNotice.indexOf('结束后') < 0) {
      this.streamNotice = '';
    }
    this.armConnectNotice();
    ThemeStore.getInstance().setKeepScreenOn(true);
    LiveIsland.start(this.agentId, this.name, runStatusZh(this.runStatus.length > 0 ? this.runStatus : 'RUNNING'))
      .catch(() => {
      });
    this.armPoll(runId, gen, agentId);

    const lastId = await PrefStore.getInstance().getLastEventId(agentId, runId);
    if (!this.stillSession(gen, agentId, runId)) {
      return;
    }
    await StreamCoordinator.getInstance().acquire(agentId, runId, (frame: SseFrame) => {
      if (!this.stillSession(gen, agentId, runId)) {
        return;
      }
      if (frame.id.length > 0) {
        this.pendingEventId = frame.id;
        this.eventIdFlush.kick();
      }
      this.onFrame(frame);
    }, (kind: string, detail: string) => {
      if (!this.stillSession(gen, agentId, runId)) {
        return;
      }
      this.onStreamStatus(kind, detail);
    }, lastId);
  }

  private armPoll(runId: string, gen: number, agentId: string): void {
    this.clearPoll();
    const pollMs = this.runStatus === 'CREATING' ? 5000 : 8000;
    const tick = async () => {
      if (!this.stillSession(gen, agentId, runId)) {
        return;
      }
      if (!this.isRunActive()) {
        this.clearPoll();
        return;
      }
      try {
        const run = await CursorApiClient.getInstance().getRun(agentId, runId);
        if (!this.stillSession(gen, agentId, runId)) {
          return;
        }
        this.applyRunSnapshot(run);
        if (isTerminal(run.status)) {
          this.finishStreamingItems();
          this.ensureOutcomeItem(run);
          StreamCoordinator.getInstance().release();
          this.streamNotice = '';
          this.clearPoll();
          Haptics.success();
          this.announceFinished(run.status, run.result ?? this.resultText);
          this.settleLive(run.id, run.status);
          return;
        }
      } catch (e) {
        Log.warn(TAG, `poll failed: ${JSON.stringify(e)}`);
      }
      if (this.stillSession(gen, agentId, runId) && this.isRunActive()) {
        this.pollTimer = setTimeout(() => {
          tick();
        }, pollMs) as number;
      }
    };
    this.pollTimer = setTimeout(() => {
      tick();
    }, pollMs) as number;
  }

  private onStreamStatus(kind: string, detail: string): void {
    if (kind === 'streaming') {
      this.pendingConnectNotice = false;
      this.clearConnectNoticeTimer();
      this.streamNotice = '';
    } else if (kind === 'connecting') {
      if (this.streamNotice.indexOf('重连') < 0 && this.streamNotice.indexOf('异常') < 0) {
        this.armConnectNotice();
      }
    } else if (kind === 'reconnecting') {
      this.pendingConnectNotice = false;
      this.clearConnectNoticeTimer();
      this.freezeLiveOverlay();
      this.reviveWaitingThink();
      this.streamNotice = '连接已断开，正在重连…';
    } else if (kind === 'expired') {
      this.pendingConnectNotice = false;
      this.clearConnectNoticeTimer();
      this.streamNotice = '流已过期，正在加载最终结果…';
      this.fetchTerminal();
    } else if (kind === 'done') {
      this.pendingConnectNotice = false;
      this.clearConnectNoticeTimer();
      this.streamNotice = '';
      this.eventIdFlush.flush();
      SessionDiag.emit({
        tag: TAG,
        event: 'stream_terminal',
        agentId: this.agentId,
        runId: this.activeRunId,
        extra: `kind=done frames=${this.streamFrames}`
      });
      this.fetchTerminal();
    } else if (kind === 'error') {
      this.pendingConnectNotice = false;
      this.clearConnectNoticeTimer();
      this.freezeLiveOverlay();
      this.streamNotice = detail.length > 0 ? detail : 'SSE 异常，已切换轮询';
      SessionDiag.emit({
        tag: TAG,
        event: 'stream_terminal',
        agentId: this.agentId,
        runId: this.activeRunId,
        extra: `kind=error frames=${this.streamFrames}`
      });
    }
    this.notify();
  }

  private async fetchTerminal(): Promise<void> {
    if (this.activeRunId.length === 0) {
      return;
    }
    const gen = this.openGen;
    const agentId = this.agentId;
    const runId = this.activeRunId;
    try {
      const run = await CursorApiClient.getInstance().getRun(agentId, runId);
      if (!this.stillSession(gen, agentId)) {
        return;
      }
      this.applyRunSnapshot(run);
      this.streamNotice = '';
      if (isTerminal(run.status)) {
        this.finishStreamingItems();
        this.ensureOutcomeItem(run);
        this.settleLive(run.id, run.status);
        Haptics.success();
        this.announceFinished(run.status, run.result ?? this.resultText);
      } else {
        this.reviveWaitingThink();
        this.streamEarlyDone += 1;
        SessionDiag.emit({
          tag: TAG,
          event: 'stream_early_done',
          agentId: this.agentId,
          runId: run.id,
          extra: `status=${run.status} tries=${this.streamEarlyDone}`
        });
        if (this.streamEarlyDone <= 3) {
          await this.startStream(run.id, true);
        }
      }
    } catch (_e) {
      this.freezeLiveOverlay();
      this.reviveWaitingThink();
      this.streamNotice = '无法获取最终结果';
    }
    this.notify();
  }

  private onInteraction(raw: string): void {
    const st = unwrapInteraction(raw);
    const kind = `${st['type'] ?? st['subtype'] ?? ''}`;
    if (kind === 'text-delta' || kind.indexOf('tool-call') === 0 || kind.indexOf('thinking') === 0 ||
      kind === 'token-delta' || kind.indexOf('summary') === 0) {
      return;
    }
    if (kind === 'step-started' || kind === 'step-completed') {
      const sid = Number(st['stepId'] ?? 0);
      const named = `${st['title'] ?? st['name'] ?? st['text'] ?? ''}`.trim();
      const label = named.length > 0 ? named : (sid > 0 ? `步骤 ${sid}` : '步骤');
      const key = sid > 0 ? `step-${this.activeRunId}-${sid}` : `step-${this.activeRunId}-${label}`;
      const done = kind === 'step-completed';
      const idx = this.source.findIndexByKey(key);
      if (idx >= 0) {
        this.source.mutateAt(idx, (item: TimelineItem) => {
          item.text = label;
          item.streaming = !done;
          if (item.pinnedOpen !== true) {
            item.collapsed = done;
          }
        });
      } else {
        this.source.append({
          key: key,
          kind: 'step',
          runId: this.activeRunId,
          text: label,
          streaming: !done,
          collapsed: done
        });
      }
      this.notify();
      return;
    }
    if (kind === 'turn-ended') {
      this.upsertRunHeader(this.activeRunId, this.runStatus.length > 0 ? this.runStatus : 'RUNNING');
      const usageRaw = st['usage'] as Record<string, Object> | undefined;
      const total = usageTotal(usageRaw);
      if (total > 0) {
        const idx = this.source.findIndexByKey(`run-${this.activeRunId}`);
        if (idx >= 0) {
          this.source.mutateAt(idx, (item: TimelineItem) => {
            item.usageShort = formatTokenShort(total);
          });
        }
      }
      this.notify();
    }
  }

  private onFrame(frame: SseFrame): void {
    if (this.openGen !== this.streamSession) {
      return;
    }
    if (frame.event === 'heartbeat' || frame.event === 'unknown') {
      return;
    }
    this.streamFrames += 1;
    if (!this.followFirstFrame && this.followStartedAt > 0) {
      this.followFirstFrame = true;
      SessionDiag.emit({
        tag: TAG,
        event: 'follow',
        agentId: this.agentId,
        runId: this.activeRunId,
        elapsedMs: Date.now() - this.followStartedAt,
        extra: 'first_frame'
      });
    }
    this.timelineFlush.kick();
    if (frame.event === 'status') {
      const st = parseJson(frame.data);
      const status = `${st['status'] ?? ''}`;
      if (status.length > 0 && canApplyRunStatus(this.runStatus, status)) {
        this.runStatus = status;
        this.upsertRunHeader(this.activeRunId, status);
      }
      this.notify();
      return;
    }
    if (frame.event === 'assistant') {
      const st = parseJson(frame.data);
      const delta = `${st['text'] ?? ''}`;
      if (delta.length === 0) {
        return;
      }
      this.appendAssistant(delta);
      this.notify();
      return;
    }
    if (frame.event === 'thinking') {
      const st = parseJson(frame.data);
      const delta = `${st['text'] ?? ''}`;
      if (delta.length === 0) {
        return;
      }
      this.appendThinking(delta);
      this.notify();
      return;
    }
    if (frame.event === 'interaction_update') {
      this.onInteraction(frame.data);
      return;
    }
    if (frame.event === 'tool_call') {
      this.sealLiveAssistantIfProgress();
      this.freezeProgress();
      this.freezeThinking();
      this.collapseCompletedTools(this.activeRunId);
      this.progressSealed = true;
      this.runHasTools = true;
      const tool = parseTool(frame.data);
      if (!tool) {
        return;
      }
      const key = `tool-${this.activeRunId}-${tool.callId}`;
      const idx = this.source.findIndexByKey(key);
      const done = tool.status === 'completed';
      if (idx >= 0) {
        this.source.mutateAt(idx, (item: TimelineItem) => {
          item.tool = tool;
          item.text = toolSummary(tool);
          if (item.pinnedOpen !== true) {
            item.collapsed = true;
          }
          item.streaming = !done;
        });
      } else {
        this.source.append({
          key: key,
          kind: 'tool',
          runId: this.activeRunId,
          tool: tool,
          text: toolSummary(tool),
          collapsed: true,
          streaming: !done
        });
      }
      this.notify();
      return;
    }
    if (frame.event === 'result') {
      const st = parseJson(frame.data);
      const text = `${st['text'] ?? ''}`;
      if (text.length > 0) {
        this.resultText = text;
        this.ensureFinalAssistant(text);
      }
      const git = st['git'];
      if (git) {
        this.branches = extractBranches(git);
      }
      this.eventIdFlush.flush();
      this.notify();
      this.fetchTerminal();
      return;
    }
    if (frame.event === 'error') {
      const st = parseJson(frame.data);
      this.freezeLiveOverlay();
      this.streamNotice = `${st['message'] ?? '流错误'}`;
      this.notify();
      return;
    }
    if (frame.event === 'done') {
      this.streamNotice = '';
      this.finishStreamingItems();
      this.eventIdFlush.flush();
      if (this.isRunActive()) {
        this.fetchTerminal();
      } else {
        this.announceFinished(this.runStatus, this.resultText);
        this.settleLive(this.activeRunId, this.runStatus);
      }
      this.notify();
    }
  }

  private appendThinking(delta: string): void {
    let key = this.activeThinkingKey;
    if (key.length === 0) {
      key = `thinking-${this.activeRunId}`;
      this.activeThinkingKey = key;
    }
    const idx = this.source.findIndexByKey(key);
    if (idx >= 0) {
      this.source.mutateAt(idx, (item: TimelineItem) => {
        item.text = `${item.text ?? ''}${delta}`;
        item.streaming = true;
        item.runId = this.activeRunId;
        if (item.pinnedOpen !== true) {
          item.collapsed = true;
        }
      });
      return;
    }
    this.source.append({
      key: key,
      kind: 'thinking',
      runId: this.activeRunId,
      text: delta,
      collapsed: true,
      streaming: true
    });
  }

  private appendAssistant(delta: string): void {
    if (this.activeAssistantKey.length > 0) {
      const idx = this.source.findIndexByKey(this.activeAssistantKey);
      if (idx >= 0) {
        this.source.mutateAt(idx, (item: TimelineItem) => {
          item.text = `${item.text ?? ''}${delta}`;
          item.streaming = true;
        });
        return;
      }
      this.activeAssistantKey = '';
    }
    if (this.shouldFoldAsProgress(delta)) {
      this.appendProgress(delta);
      const pidx = this.source.findIndexByKey(this.activeProgressKey);
      if (pidx >= 0) {
        const tail = lastStep(this.source.getData(pidx).text ?? '');
        if (!isProgressText(tail)) {
          this.promoteProgressTail();
        }
      }
      return;
    }
    this.startAssistant(delta);
  }

  private shouldFoldAsProgress(delta: string): boolean {
    if (!isProgressText(delta)) {
      return false;
    }
    if (this.activeProgressKey.length > 0 || this.activeThinkingKey.length > 0 || this.runHasTools) {
      return true;
    }
    return this.isRunActive();
  }

  private freezeProgress(): void {
    if (this.activeProgressKey.length === 0) {
      return;
    }
    const idx = this.source.findIndexByKey(this.activeProgressKey);
    if (idx >= 0) {
      this.source.mutateAt(idx, (item: TimelineItem) => {
        item.streaming = false;
        if (item.pinnedOpen !== true) {
          item.collapsed = true;
        }
        item.stepCount = Math.max(1, countSteps(item.text ?? ''));
      });
    }
  }

  private freezeThinking(): void {
    if (this.activeThinkingKey.length === 0) {
      return;
    }
    const idx = this.source.findIndexByKey(this.activeThinkingKey);
    if (idx >= 0) {
      this.source.mutateAt(idx, (item: TimelineItem) => {
        if (item.pinnedOpen !== true) {
          item.collapsed = true;
        }
        item.streaming = false;
      });
    }
  }

  private collapseCompletedTools(runId: string): void {
    const snap = this.source.snapshot();
    for (let i = 0; i < snap.length; i++) {
      if (snap[i].kind !== 'tool' || snap[i].runId !== runId) {
        continue;
      }
      this.source.mutateAt(i, (item: TimelineItem) => {
        if (item.pinnedOpen !== true) {
          item.collapsed = true;
        }
        item.streaming = false;
      });
    }
  }

  private appendProgress(delta: string): void {
    if (this.activeProgressKey.length === 0 || this.progressSealed) {
      if (this.progressSealed) {
        this.freezeProgress();
      }
      const key = `progress-${this.activeRunId}-${Date.now()}`;
      this.activeProgressKey = key;
      this.progressSealed = false;
      this.source.append({
        key: key,
        kind: 'progress',
        runId: this.activeRunId,
        text: delta,
        collapsed: true,
        streaming: true,
        stepCount: 1
      });
      return;
    }
    const idx = this.source.findIndexByKey(this.activeProgressKey);
    if (idx < 0) {
      this.activeProgressKey = '';
      this.appendProgress(delta);
      return;
    }
    this.source.mutateAt(idx, (item: TimelineItem) => {
      item.text = `${item.text ?? ''}${delta}`;
      item.streaming = true;
      if (item.pinnedOpen !== true) {
        item.collapsed = true;
      }
      item.stepCount = Math.max(1, countSteps(item.text ?? ''));
    });
  }

  private promoteProgressTail(): void {
    const idx = this.source.findIndexByKey(this.activeProgressKey);
    if (idx < 0) {
      return;
    }
    const full = this.source.getData(idx).text ?? '';
    const head = dropLastStep(full);
    const tail = lastStep(full);
    if (head.length === 0) {
      this.source.removeAt(idx);
      this.activeProgressKey = '';
      this.progressSealed = true;
    } else {
      this.source.mutateAt(idx, (item: TimelineItem) => {
        item.text = head;
        item.streaming = false;
        if (item.pinnedOpen !== true) {
          item.collapsed = true;
        }
        item.stepCount = Math.max(1, countSteps(head));
      });
      this.progressSealed = true;
    }
    if (tail.trim().length > 0) {
      this.startAssistant(tail);
    }
  }

  private startAssistant(text: string): void {
    this.collapseActivity(this.activeRunId);
    const key = `assistant-${this.activeRunId}-${Date.now()}`;
    this.activeAssistantKey = key;
    this.source.append({
      key: key,
      kind: 'assistant',
      runId: this.activeRunId,
      text: text,
      streaming: true
    });
  }

  private sealLiveAssistantIfProgress(): void {
    if (this.activeAssistantKey.length === 0) {
      return;
    }
    const idx = this.source.findIndexByKey(this.activeAssistantKey);
    if (idx < 0) {
      this.activeAssistantKey = '';
      return;
    }
    const text = this.source.getData(idx).text ?? '';
    if (isProgressText(text)) {
      this.source.removeAt(idx);
      this.activeAssistantKey = '';
      this.progressSealed = true;
      if (text.trim().length > 0) {
        this.appendProgress(text);
      }
      this.progressSealed = true;
      return;
    }
    this.source.mutateAt(idx, (it: TimelineItem) => {
      it.streaming = false;
    });
    this.activeAssistantKey = '';
  }

  private ensureFinalAssistant(text: string): void {
    if (text.trim().length === 0) {
      return;
    }
    if (this.activeAssistantKey.length > 0) {
      const idx = this.source.findIndexByKey(this.activeAssistantKey);
      if (idx >= 0) {
        const cur = this.source.getData(idx);
        if ((cur.text ?? '').trim().length === 0) {
          this.source.mutateAt(idx, (item: TimelineItem) => {
            item.text = text;
          });
        }
        return;
      }
    }
    if (this.hasAssistantForRun(this.activeRunId)) {
      return;
    }
    if (this.activeProgressKey.length > 0 && !this.hasActivityKeepers(this.activeRunId)) {
      const idx = this.source.findIndexByKey(this.activeProgressKey);
      if (idx >= 0) {
        const body = (this.source.getData(idx).text ?? '').trim();
        if (body.length > 0 && (body === text.trim() || isProgressText(body))) {
          this.source.removeAt(idx);
          this.activeProgressKey = '';
          this.startAssistant(body === text.trim() ? text : body);
          return;
        }
      }
    }
    this.startAssistant(text);
  }

  private hasAssistantForRun(runId: string): boolean {
    const snap = this.source.snapshot();
    for (let i = 0; i < snap.length; i++) {
      if (snap[i].kind === 'assistant' && snap[i].runId === runId && (snap[i].text ?? '').trim().length > 0) {
        return true;
      }
    }
    return false;
  }

  private hasActivityKeepers(runId: string): boolean {
    const snap = this.source.snapshot();
    for (let i = 0; i < snap.length; i++) {
      if (snap[i].runId !== runId) {
        continue;
      }
      if (snap[i].kind === 'thinking' || snap[i].kind === 'tool') {
        return true;
      }
    }
    return false;
  }

  private finishStreamingItems(): void {
    if (!this.hasAssistantForRun(this.activeRunId) && this.activeProgressKey.length > 0 &&
      !this.hasActivityKeepers(this.activeRunId)) {
      const idx = this.source.findIndexByKey(this.activeProgressKey);
      if (idx >= 0) {
        const body = (this.source.getData(idx).text ?? '').trim();
        if (body.length > 0 && isProgressText(body)) {
          this.source.removeAt(idx);
          this.activeProgressKey = '';
          this.startAssistant(body);
        }
      }
    }
    this.collapseActivity(this.activeRunId);
    this.activeAssistantKey = '';
    this.compactProgressForRun(this.activeRunId);
    this.persistTimeline();
    this.source.flushChanges();
  }

  private collapseActivity(runId: string): void {
    if (runId.length === 0) {
      return;
    }
    const snap = this.source.snapshot();
    for (let i = 0; i < snap.length; i++) {
      const it = snap[i];
      if (it.runId !== runId) {
        continue;
      }
      if (it.kind === 'thinking' || it.kind === 'progress' || it.kind === 'tool' ||
        it.kind === 'step' || it.kind === 'assistant') {
        this.source.mutateAt(i, (item: TimelineItem) => {
          if (item.kind !== 'assistant' && item.pinnedOpen !== true) {
            item.collapsed = true;
          }
          item.streaming = false;
        });
      }
    }
  }

  private compactProgressForRun(runId: string): void {
    if (runId.length === 0) {
      return;
    }
    const snap = this.source.snapshot();
    const idxs: number[] = [];
    for (let i = 0; i < snap.length; i++) {
      if (snap[i].kind === 'progress' && snap[i].runId === runId) {
        idxs.push(i);
      }
    }
    if (idxs.length <= 1) {
      if (idxs.length === 1) {
        this.source.mutateAt(idxs[0], (item: TimelineItem) => {
          if (item.pinnedOpen !== true) {
            item.collapsed = true;
          }
          item.streaming = false;
          item.stepCount = Math.max(1, countSteps(item.text ?? ''));
        });
      }
      this.activeProgressKey = '';
      this.progressSealed = true;
      return;
    }
    const parts: string[] = [];
    let steps = 0;
    for (let i = 0; i < idxs.length; i++) {
      const t = (snap[idxs[i]].text ?? '').trim();
      if (t.length > 0) {
        parts.push(t);
        steps += Math.max(1, snap[idxs[i]].stepCount ?? countSteps(t));
      }
    }
    this.source.mutateAt(idxs[0], (item: TimelineItem) => {
      item.text = parts.join('\n\n');
      if (item.pinnedOpen !== true) {
        item.collapsed = true;
      }
      item.streaming = false;
      item.stepCount = Math.max(1, steps);
    });
    for (let i = idxs.length - 1; i >= 1; i--) {
      this.source.removeAt(idxs[i]);
    }
    this.activeProgressKey = '';
    this.progressSealed = true;
  }

  private persistLastEventId(): void {
    if (this.pendingEventId.length === 0 || this.agentId.length === 0 || this.activeRunId.length === 0) {
      return;
    }
    PrefStore.getInstance().setLastEventId(this.agentId, this.activeRunId, this.pendingEventId);
  }

  private persistTimeline(force: boolean = false): void {
    if (this.agentId.length === 0 || this.agentId.indexOf('local-') === 0) {
      return;
    }
    if (!force && this.isRunActive()) {
      return;
    }
    const snap = this.source.snapshot();
    const toolRuns: Record<string, boolean> = {};
    for (let i = 0; i < snap.length; i++) {
      if (snap[i].kind === 'tool') {
        toolRuns[snap[i].runId ?? ''] = true;
      }
    }
    const keep: TimelineItem[] = [];
    for (let i = 0; i < snap.length; i++) {
      const it = snap[i];
      const k = it.kind;
      if (k === 'streamNotice') {
        continue;
      }
      if (k === 'thinking' || k === 'progress' || k === 'step') {
        const text = (it.text ?? '').trim();
        if (text.length === 0 && toolRuns[it.runId ?? ''] !== true && it.streaming !== true) {
          continue;
        }
      }
      if (k === 'thinking' || k === 'progress' || k === 'step' || k === 'tool' ||
        k === 'assistant' || k === 'userPrompt' || k === 'runHeader' || k === 'runOutcome') {
        keep.push({
          key: it.key,
          kind: it.kind,
          runId: it.runId,
          text: it.text,
          tool: it.tool,
          statusLabel: it.statusLabel,
          collapsed: it.collapsed,
          pinnedOpen: it.pinnedOpen,
          failed: it.failed,
          streaming: it.streaming === true,
          stepCount: it.stepCount,
          usageShort: it.usageShort,
          sentTags: it.sentTags
        });
      }
    }
    if (keep.length > 0 || force) {
      if (keep.length > 0) {
        AgentCache.getInstance().saveTimeline(this.agentId, capTimeline(keep));
      }
      let summary = '';
      for (let i = keep.length - 1; i >= 0; i--) {
        const k = keep[i].kind;
        if (k === 'assistant' || k === 'thinking' || k === 'progress' || k === 'step') {
          summary = lastNonEmptyLine(keep[i].text ?? '', 72);
          if (summary.length > 0) {
            break;
          }
        }
      }
      AgentCache.getInstance().saveTimelineMeta(this.agentId, summary, this.pendingEventId,
        this.activeRunId);
    }
  }

  private applyMergedActivity(cached: TimelineItem[] | undefined): void {
    if (!cached || cached.length === 0) {
      return;
    }
    const snap = this.source.snapshot();
    const withLocal = keepPendingTurns(snap, cached);
    const merged = restoreUserSentTags(mergeCachedActivity(withLocal, cached), cached);
    if (merged !== snap) {
      this.source.replaceAll(merged);
    }
  }

  private reviveWaitingThink(): void {
    if (!this.isRunActive()) {
      return;
    }
    const runId = this.activeRunId;
    if (runId.length === 0) {
      return;
    }
    if (this.hasAssistantForRun(runId)) {
      return;
    }
    const snap = this.source.snapshot();
    for (let i = snap.length - 1; i >= 0; i--) {
      const it = snap[i];
      if (it.kind !== 'thinking') {
        continue;
      }
      if (it.runId !== runId && it.runId !== 'pending') {
        continue;
      }
      if ((it.text ?? '').trim().length > 0) {
        return;
      }
      this.source.mutateAt(i, (item: TimelineItem) => {
        item.streaming = true;
        item.collapsed = false;
        if (item.runId === 'pending') {
          item.runId = runId;
        }
      });
      this.activeThinkingKey = this.source.getData(i).key;
      return;
    }
    const key = `thinking-${runId}`;
    if (this.source.findIndexByKey(key) >= 0) {
      return;
    }
    this.source.append({
      key: key,
      kind: 'thinking',
      runId: runId,
      text: '',
      collapsed: false,
      streaming: true
    });
    this.activeThinkingKey = key;
  }

  private buildConversation(messages: ConversationMessage[]): void {
    const items: TimelineItem[] = [];
    let assistantIdx = 0;
    let pendingShort: string[] = [];
    let pendingKey = '';

    const flushProgress = (): void => {
      if (pendingShort.length === 0) {
        return;
      }
      const joined = pendingShort.join('\n\n');
      items.push({
        key: `progress-${pendingKey}-${assistantIdx}`,
        kind: 'progress',
        runId: 'history',
        text: joined,
        collapsed: true,
        stepCount: pendingShort.length
      });
      assistantIdx++;
      pendingShort = [];
      pendingKey = '';
    };

    const flushAsAssistant = (): void => {
      if (pendingShort.length === 0) {
        return;
      }
      // Final short replies (e.g. "pong") stay as real assistant bubbles.
      const joined = pendingShort.join('\n\n');
      items.push({
        key: `asst-${pendingKey}-${assistantIdx}`,
        kind: 'assistant',
        runId: 'history',
        text: joined
      });
      assistantIdx++;
      pendingShort = [];
      pendingKey = '';
    };

    for (let i = 0; i < messages.length; i++) {
      const m = messages[i];
      const text = (m.text ?? '').trim();
      if (text.length === 0) {
        continue;
      }
      const mid = m.id && m.id.length > 0 ? m.id : `i${i}`;
      if (m.type === 'user_message') {
        flushAsAssistant();
        items.push({
          key: `user-${mid}`,
          kind: 'userPrompt',
          runId: 'history',
          text: text
        });
      } else if (m.type === 'assistant_message') {
        const last = i === messages.length - 1;
        if (isProgressText(text) && !last) {
          if (pendingKey.length === 0) {
            pendingKey = mid;
          }
          pendingShort.push(text);
        } else if (isProgressText(text) && last) {
          const hasAnswer = items.length > 0 && items[items.length - 1].kind === 'assistant';
          if (hasAnswer) {
            pendingShort.push(text);
            flushProgress();
          } else if (pendingShort.length > 0) {
            pendingShort.push(text);
            flushAsAssistant();
          } else {
            items.push({
              key: `asst-${mid}-${assistantIdx}`,
              kind: 'assistant',
              runId: 'history',
              text: text
            });
            assistantIdx++;
          }
        } else {
          flushProgress();
          items.push({
            key: `asst-${mid}-${assistantIdx}`,
            kind: 'assistant',
            runId: 'history',
            text: text
          });
          assistantIdx++;
        }
      }
    }
    flushAsAssistant();
    this.source.replaceAll(items);
    this.applyUnreadScroll();
  }

  private applyUnreadScroll(): void {
    if (!this.openWasUnread) {
      this.stickToBottom = true;
      this.unreadAnchorKey = '';
      this.unreadNewCount = 0;
      return;
    }
    const vis = visibleTimeline(this.source.snapshot());
    const lastSeen = UnreadStore.getInstance().lastSeenKey(this.agentId);
    this.unreadAnchorKey = findUnreadAnchor(vis, lastSeen);
    this.unreadNewCount = countNewContent(vis, lastSeen);
    this.stickToBottom = this.unreadAnchorKey.length === 0;
    SessionDiag.emit({
      tag: TAG,
      event: 'unread_scroll',
      agentId: this.agentId,
      extra: `stick=${this.stickToBottom ? 1 : 0} new=${this.unreadNewCount} anchor=${this.unreadAnchorKey.length > 0 ? 1 : 0}`
    });
  }

  private rememberSeen(): void {
    const key = lastContentKey(this.source.snapshot());
    UnreadStore.getInstance().markSeen(this.agentId, key).catch(() => {
    });
  }

  /** Fallback when conversation API is unavailable: avoid N empty "运行·已完成" rows. */
  private buildRunsFallback(runs: Run[]): void {
    const items: TimelineItem[] = [];
    if (runs.length === 0) {
      this.source.replaceAll(items);
      return;
    }
    // Newest first in API; show oldest → newest, but only headers with real result text.
    const ordered = runs.slice().reverse();
    let shown = 0;
    for (let i = 0; i < ordered.length; i++) {
      const run = ordered[i];
      const hasResult = !!(run.result && run.result.length > 0);
      if (!hasResult && isTerminal(run.status)) {
        continue;
      }
      items.push({
        key: `run-${run.id}`,
        kind: 'runHeader',
        runId: run.id,
        statusLabel: run.status,
        text: runStatusZh(run.status)
      });
      if (hasResult) {
        items.push({
          key: `outcome-${run.id}`,
          kind: 'runOutcome',
          runId: run.id,
          statusLabel: run.status,
          text: run.result
        });
        shown++;
      }
    }
    if (items.length === 0 && ordered.length > 0) {
      const latest = ordered[ordered.length - 1];
      items.push({
        key: `run-${latest.id}`,
        kind: 'runHeader',
        runId: latest.id,
        statusLabel: latest.status,
        text: '完整对话暂不可用'
      });
    }
    Log.info(TAG, `runs fallback items=${items.length} withResult=${shown}`);
    this.source.replaceAll(items);
  }

  private applyLatestRunMeta(runs: Run[]): void {
    if (runs.length === 0) {
      return;
    }
    // API returns newest first.
    const latest = runs[0];
    if (this.streamRunId.length > 0 && latest.id !== this.streamRunId) {
      return;
    }
    if (!this.activeRunId || this.activeRunId.length === 0) {
      this.activeRunId = latest.id;
    }
    this.applyRunSnapshot(latest);
  }

  private applyRunSnapshot(run: Run): void {
    if (this.streamRunId.length > 0 && run.id !== this.streamRunId) {
      return;
    }
    const prev = this.runStatus;
    if (!canApplyRunStatus(prev, run.status)) {
      return;
    }
    if (run.updatedAt && run.updatedAt.length > 0 &&
      !isNewerIso(run.updatedAt, this.lastRunUpdatedAt) && prev === run.status) {
      return;
    }
    this.activeRunId = run.id;
    this.runStatus = run.status;
    this.phaseMachine.sync(this.runStatus, this.loading, this.sending);
    if (run.updatedAt && run.updatedAt.length > 0) {
      this.lastRunUpdatedAt = run.updatedAt;
    }
    if (prev !== run.status && !isTerminal(run.status)) {
      LiveIsland.update(runStatusZh(run.status)).catch(() => {
      });
    }
    if (run.result && run.result.length > 0) {
      this.resultText = run.result;
    }
    if (run.git && run.git.branches) {
      this.branches = run.git.branches;
    }
    if (run.durationMs && run.durationMs > 0) {
      this.durationMs = run.durationMs;
    }
    this.recomputeCompareUrl();
    if (prev !== run.status) {
      this.bumpInbox();
    }
  }

  private recomputeCompareUrl(): void {
    let head = '';
    let repo = this.repoUrl;
    let pr = '';
    for (let i = 0; i < this.branches.length; i++) {
      const b = this.branches[i];
      if (!head && b.branch && b.branch.length > 0) {
        head = b.branch;
      }
      if (b.repoUrl && b.repoUrl.length > 0) {
        repo = b.repoUrl;
      }
      if (!pr && b.prUrl && b.prUrl.length > 0) {
        pr = b.prUrl;
      }
    }
    if (isOriginRepo(repo) && pr.length > 0) {
      this.compareUrl = pr;
      return;
    }
    this.compareUrl = gitCompareUrl(repo, this.startingRef, head);
  }

  private ensureOutcomeItem(run: Run): void {
    const key = `outcome-${run.id}`;
    const hasAnswer = this.hasAssistantForRun(run.id);
    const raw = run.result && run.result.length > 0 ? run.result : '';
    const text = hasAnswer ? '' : raw;
    const idx = this.source.findIndexByKey(key);
    if (idx >= 0) {
      this.source.mutateAt(idx, (item: TimelineItem) => {
        item.text = text;
        item.statusLabel = run.status;
      });
    } else if (text.length > 0) {
      this.source.append({
        key: key,
        kind: 'runOutcome',
        runId: run.id,
        statusLabel: run.status,
        text: text
      });
    }
  }

  private upsertRunHeader(runId: string, status: string): void {
    const key = `run-${runId}`;
    const idx = this.source.findIndexByKey(key);
    if (idx >= 0) {
      const item = this.source.getData(idx);
      item.statusLabel = status;
      item.text = runStatusZh(status);
      this.source.updateAt(idx, item);
    } else if (status === 'CREATING' || status === 'RUNNING') {
      this.source.append({
        key: key,
        kind: 'runHeader',
        runId: runId,
        statusLabel: status,
        text: runStatusZh(status)
      });
    }
  }

  private clearPoll(): void {
    if (this.pollTimer >= 0) {
      clearTimeout(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private clearConnectNoticeTimer(): void {
    if (this.connectNoticeTimer >= 0) {
      clearTimeout(this.connectNoticeTimer);
      this.connectNoticeTimer = -1;
    }
  }

  private clearNoticeTimers(): void {
    this.clearConnectNoticeTimer();
    if (this.cancelNoticeTimer >= 0) {
      clearTimeout(this.cancelNoticeTimer);
      this.cancelNoticeTimer = -1;
    }
    this.pendingConnectNotice = false;
  }

  /** Fast connects stay quiet; slow ones show 连接中. */
  private armConnectNotice(): void {
    this.pendingConnectNotice = true;
    if (this.connectNoticeTimer >= 0) {
      return;
    }
    this.connectNoticeTimer = setTimeout(() => {
      this.connectNoticeTimer = -1;
      if (this.pendingConnectNotice &&
        (this.streamNotice.length === 0 || this.streamNotice === '连接中…')) {
        this.streamNotice = '连接中…';
        this.notify();
      }
    }, 420) as number;
  }

  private armCancelNoticeClear(): void {
    if (this.cancelNoticeTimer >= 0) {
      clearTimeout(this.cancelNoticeTimer);
    }
    this.cancelNoticeTimer = setTimeout(() => {
      this.cancelNoticeTimer = -1;
      if (this.streamNotice === '已取消') {
        this.streamNotice = '';
        this.notify();
      }
    }, 1600) as number;
  }
}

function runStatusZh(status: string): string {
  if (status === 'FINISHED') {
    return '已完成';
  }
  if (status === 'RUNNING') {
    return '运行中';
  }
  if (status === 'CREATING') {
    return '创建中';
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

function isTerminal(status: RunStatus | string): boolean {
  return isTerminalStatus(`${status}`);
}

function extractRuns(raw: object): Run[] {
  const obj = raw as Record<string, Object>;
  const list = (obj['items'] ?? obj['runs'] ?? []) as object[];
  const out: Run[] = [];
  for (let i = 0; i < list.length; i++) {
    const r = list[i] as Record<string, Object>;
    const run: Run = {
      id: `${r['id'] ?? ''}`,
      agentId: `${r['agentId'] ?? ''}`,
      status: `${r['status'] ?? 'CREATING'}` as RunStatus,
      createdAt: `${r['createdAt'] ?? ''}`,
      updatedAt: `${r['updatedAt'] ?? ''}`,
      durationMs: Number(r['durationMs'] ?? 0),
      result: r['result'] ? `${r['result']}` : undefined
    };
    if (r['git']) {
      run.git = { branches: extractBranches(r['git'] as Object) };
    }
    out.push(run);
  }
  return out;
}

function parseJson(data: string): Record<string, Object> {
  try {
    return JSON.parse(data) as Record<string, Object>;
  } catch (_e) {
    return {};
  }
}

function unwrapInteraction(data: string): Record<string, Object> {
  const st = parseJson(data);
  const nested = st['update'] as Record<string, Object> | undefined;
  if (nested && `${nested['type'] ?? ''}`.length > 0) {
    return nested;
  }
  const payload = st['payload'] as Record<string, Object> | undefined;
  if (payload && `${payload['type'] ?? ''}`.length > 0) {
    return payload;
  }
  return st;
}

function usageTotal(raw: Record<string, Object> | undefined): number {
  if (!raw) {
    return 0;
  }
  const total = Number(raw['totalTokens'] ?? 0);
  if (total > 0) {
    return total;
  }
  const input = Number(raw['inputTokens'] ?? 0);
  const output = Number(raw['outputTokens'] ?? 0);
  const cacheW = Number(raw['cacheWriteTokens'] ?? 0);
  const cacheR = Number(raw['cacheReadTokens'] ?? 0);
  const n = input + output + cacheW + cacheR;
  return n === n ? n : 0;
}

function parseTool(data: string): ToolCallEvent | undefined {
  const obj = parseJson(data);
  const callId = `${obj['callId'] ?? ''}`;
  if (callId.length === 0) {
    return undefined;
  }
  const truncated = obj['truncated'] as Record<string, Object> | undefined;
  return {
    callId: callId,
    name: `${obj['name'] ?? 'tool'}`,
    status: `${obj['status'] ?? 'running'}`,
    argsText: obj['args'] !== undefined ? safeJson(obj['args']) : undefined,
    resultText: obj['result'] !== undefined ? safeJson(obj['result']) : undefined,
    truncatedArgs: truncated ? !!truncated['args'] : false,
    truncatedResult: truncated ? !!truncated['result'] : false
  };
}

function safeJson(v: Object): string {
  try {
    const s = JSON.stringify(v);
    return s.length > 4000 ? `${s.substring(0, 4000)}…` : s;
  } catch (_e) {
    return `${v}`;
  }
}

function toolSummary(tool: ToolCallEvent): string {
  return usedToolFromEvent(tool);
}

function extractBranches(git: Object): GitBranch[] {
  try {
    const g = git as Record<string, Object>;
    const arr = (g['branches'] ?? []) as object[];
    const out: GitBranch[] = [];
    for (let i = 0; i < arr.length; i++) {
      const b = arr[i] as Record<string, Object>;
      out.push({
        repoUrl: `${b['repoUrl'] ?? ''}`,
        branch: b['branch'] ? `${b['branch']}` : undefined,
        prUrl: b['prUrl'] ? `${b['prUrl']}` : undefined
      });
    }
    return out;
  } catch (_e) {
    return [];
  }
}

function shortRepo(url: string): string {
  if (!url) {
    return '';
  }
  const cleaned = url.replace(/\.git$/, '').replace(/\/$/, '');
  const parts = cleaned.split('/');
  if (parts.length >= 2) {
    return `${parts[parts.length - 2]}/${parts[parts.length - 1]}`;
  }
  return cleaned;
}

function createModelOf(body: Record<string, Object>): Record<string, Object> | undefined {
  const raw = body['model'];
  if (!raw) {
    return undefined;
  }
  return raw as Record<string, Object>;
}

function followModelBody(id: string, params: Object[]): Record<string, Object> {
  const model: Record<string, Object> = {};
  model['id'] = id;
  if (params.length > 0) {
    model['params'] = params;
  }
  return model;
}
