import { ApiException, AgentDetail, ArtifactInfo, ConversationMessage, ConversationResponse,
  GitBranch, McpServerDef, Run, RunStatus, RunUsage } from '../models/Api';
import { SseFrame, ToolCallEvent } from '../models/Sse';
import { TimelineItem } from '../models/Timeline';
import { CursorApiClient } from '../api/CursorApiClient';
import { StreamCoordinator } from '../api/StreamCoordinator';
import { unwrapUsageRuns, unwrapAgentDetail } from '../api/ApiUnwrap';
import { TimelineSource } from '../datasource/TimelineSource';
import { AgentCache } from '../store/AgentCache';
import { PrefStore } from '../store/PrefStore';
import { Throttle } from '../utils/Throttle';
import { Haptics } from '../utils/Haptics';
import { Notify } from '../utils/Notify';
import { clipNotice } from '../utils/MarkdownParse';
import { UnreadStore } from '../store/UnreadStore';
import { LiveIsland } from '../utils/LiveIsland';
import { ThemeStore } from '../store/ThemeStore';
import { Log } from '../utils/Log';
import { formatTokenShort, formatUsageFriendly } from '../utils/DisplayFmt';
import { toApiMcp } from '../utils/AgentCapabilities';
import { countSteps, dropLastStep, friendlyToolName, isProgressText, isSubagentTool, lastStep,
  shortPathForTool, subagentDetail, plainArg } from '../utils/StreamText';
import { gitCompareUrl } from '../utils/GitLinks';
import { PromptImage, toApiImages } from '../utils/ImagePicker';

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
  followUpMcp: McpServerDef[] = [];
  queuedFollowUp: string = '';
  queuedImages: PromptImage[] = [];
  repoUrl: string = '';
  startingRef: string = '';
  compareUrl: string = '';
  syncing: boolean = false;
  source: TimelineSource = new TimelineSource();

  private uiFlush: Throttle;
  private eventIdFlush: Throttle;
  private dirty: boolean = false;
  private activeAssistantKey: string = '';
  private activeThinkingKey: string = '';
  private activeProgressKey: string = '';
  private progressSealed: boolean = true;
  private runHasTools: boolean = false;
  private pendingEventId: string = '';
  private pollTimer: number = -1;
  private queueTimer: number = -1;
  private queueRetries: number = 0;
  private convKey: string = '';
  private streamRunId: string = '';
  private onUi: (() => void) | undefined = undefined;

  constructor() {
    this.uiFlush = new Throttle(40, () => {
      this.source.flushChanges();
      if (this.dirty && this.onUi) {
        this.dirty = false;
        this.onUi();
      }
    });
    this.eventIdFlush = new Throttle(800, () => {
      this.persistLastEventId();
    });
  }

  setUiListener(cb: () => void): void {
    this.onUi = cb;
  }

  private notify(): void {
    this.dirty = true;
    this.uiFlush.kick();
  }

  async open(agentId: string): Promise<void> {
    this.releaseRuntime();
    DetailVM.activeInstance = this;
    this.agentId = agentId;
    this.errorMsg = '';
    this.deleted = false;
    this.needsPlanUpgrade = false;
    this.convKey = '';

    const cached = AgentCache.getInstance().loadAgent(agentId);
    let painted = false;
    if (cached?.detail) {
      this.applyDetail(cached.detail);
      painted = true;
    }
    if (cached?.runs && cached.runs.length > 0) {
      this.applyLatestRunMeta(cached.runs);
      painted = true;
    }
    if (cached?.messages && cached.messages.length > 0) {
      this.buildConversation(cached.messages);
      this.mergeCachedActivity(cached.timeline);
      this.convKey = convFingerprint(cached.messages);
      painted = true;
    } else if (cached?.timeline && cached.timeline.length > 0) {
      this.source.replaceAll(cached.timeline);
      painted = true;
    }
    this.loading = !painted;
    this.syncing = true;
    this.notify();
    this.uiFlush.flush();

    try {
      const client = CursorApiClient.getInstance();
      const settled = await Promise.all([
        client.getAgent(agentId),
        client.getRuns(agentId, 20),
        client.getConversation(agentId).catch((_e: Object): ConversationResponse => {
          return { messages: [] } as ConversationResponse;
        })
      ]);
      const detail = unwrapAgentDetail(settled[0] as object);
      this.applyDetail(detail);

      const runs = extractRuns(settled[1] as object);
      this.applyLatestRunMeta(runs);

      const conv = settled[2] as ConversationResponse;
      const messages = conv.messages ?? [];
      const nextKey = convFingerprint(messages);
      if (messages.length > 0 && nextKey !== this.convKey) {
        this.buildConversation(messages);
        this.mergeCachedActivity(cached?.timeline);
        this.convKey = nextKey;
      } else if (messages.length === 0 && !painted) {
        this.buildRunsFallback(runs);
      }
      AgentCache.getInstance().saveAgent(agentId, detail, runs, undefined, messages);

      if (this.activeRunId.length > 0 && (this.isRunActive() || this.runStatus.length === 0)) {
        const run = await client.getRun(agentId, this.activeRunId);
        this.applyRunSnapshot(run);
        if (!isTerminal(run.status)) {
          await this.startStream(run.id);
        }
      }

      this.loadArtifactsAndUsage();
    } catch (e) {
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
      this.loading = false;
      this.syncing = false;
      this.notify();
      this.uiFlush.flush();
    }
  }

  private releaseRuntime(): void {
    StreamCoordinator.getInstance().release();
    this.clearPoll();
    this.clearQueueTimer();
    this.eventIdFlush.flush();
    this.persistTimeline();
  }

  private applyDetail(detail: AgentDetail): void {
    this.name = detail.name ?? this.agentId;
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
    const bits: string[] = [];
    if (detail.env?.name && detail.env.name.length > 0) {
      bits.push(detail.env.name);
    } else if (detail.env?.type) {
      bits.push(`env:${detail.env.type}`);
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
    try {
      const arts = await CursorApiClient.getInstance().listArtifacts(this.agentId);
      this.artifacts = arts.items ?? [];
    } catch (_e) {
      this.artifacts = [];
    }
    try {
      const usage = await CursorApiClient.getInstance().getUsage(this.agentId);
      this.usageLabel = formatUsageFriendly(usage as object);
      this.usageRuns = unwrapUsageRuns(usage as object);
      this.applyUsageToHeaders();
    } catch (_e) {
      this.usageLabel = '';
      this.usageRuns = [];
    }
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
    if (DetailVM.activeInstance === this) {
      DetailVM.activeInstance = undefined;
    }
    StreamCoordinator.getInstance().release();
    this.clearPoll();
    this.eventIdFlush.flush();
    this.eventIdFlush.cancel();
    this.persistTimeline();
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
    this.queueRetries = 0;
    this.compareUrl = '';
    this.clearQueueTimer();
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
    this.stickToBottom = false;
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
    this.queueRetries = 0;
    this.clearQueueTimer();
    this.persistQueue();
    if (this.streamNotice === '结束后发送' || this.streamNotice.indexOf('结束后') >= 0) {
      this.streamNotice = '';
    }
    this.notify();
  }

  private async sendFollowUp(prompt: string, images: PromptImage[] = []): Promise<boolean> {
    this.sending = true;
    this.errorMsg = '';
    this.streamNotice = '正在提交…';
    const tempKey = `user-${Date.now()}`;
    this.source.append({
      key: tempKey,
      kind: 'userPrompt',
      runId: 'pending',
      text: images.length > 0 ? `${prompt}\n（${images.length} 张图）` : prompt
    });
    this.source.append({
      key: `thinking-${tempKey}`,
      kind: 'thinking',
      runId: 'pending',
      text: '',
      collapsed: true,
      streaming: true
    });
    this.stickToBottom = true;
    this.notify();
    this.uiFlush.flush();
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
      const mcp = toApiMcp(this.followUpMcp);
      if (mcp.length > 0) {
        body['mcpServers'] = mcp;
      }
      const run = await CursorApiClient.getInstance().createRun(this.agentId, body);
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
        this.source.updateAt(thinkIdx, think);
        this.activeThinkingKey = think.key;
      }
      this.source.append({
        key: `run-${run.id}`,
        kind: 'runHeader',
        runId: run.id,
        statusLabel: run.status,
        text: `运行 · ${runStatusZh(run.status)}`
      });
      this.applyRunSnapshot(run);
      this.sending = false;
      this.notify();
      this.uiFlush.flush();
      await this.startStream(run.id);
      return true;
    } catch (e) {
      const idx = this.source.findIndexByKey(tempKey);
      if (idx >= 0) {
        this.source.removeAt(idx);
      }
      const thinkIdx = this.source.findIndexByKey(`thinking-${tempKey}`);
      if (thinkIdx >= 0) {
        this.source.removeAt(thinkIdx);
      }
      if (e instanceof ApiException && (e.code === 409 || e.apiCode === 'agent_busy')) {
        this.queuedFollowUp = prompt;
        this.queuedImages = images;
        this.persistQueue();
        this.streamNotice = 'Agent 忙碌，稍后自动发送';
        this.scheduleFlushQueue(800 * Math.max(1, this.queueRetries + 1));
        Haptics.warn();
        return true;
      }
      if (e instanceof ApiException) {
        this.errorMsg = e.message;
      } else {
        this.errorMsg = '追问失败';
      }
      Haptics.fail();
      return false;
    } finally {
      this.sending = false;
      this.notify();
      this.uiFlush.flush();
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
  }

  async restoreQueue(): Promise<void> {
    if (this.agentId.length === 0) {
      return;
    }
    const saved = await PrefStore.getInstance().getQueuedFollowUp(this.agentId);
    if (saved.length === 0) {
      return;
    }
    this.queuedFollowUp = saved;
    if (this.isRunActive()) {
      this.streamNotice = '结束后发送';
      this.notify();
      return;
    }
    this.scheduleFlushQueue(400);
  }

  private async flushQueuedFollowUp(): Promise<void> {
    const q = this.queuedFollowUp.trim();
    if (q.length === 0) {
      return;
    }
    if (this.sending || this.isRunActive()) {
      this.scheduleFlushQueue(1600);
      return;
    }
    if (this.queueRetries >= 5) {
      this.errorMsg = '追问排队发送失败，请手动重试';
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
    if (!ok && this.queuedFollowUp.length === 0) {
      this.queuedFollowUp = q;
      this.queuedImages = imgs;
      this.persistQueue();
    }
  }

  private announceFinished(status: string, raw: string): void {
    const zh = runStatusZh(status);
    const snippet = clipNotice(raw.length > 0 ? raw : this.resultText, 72);
    Notify.runFinished(this.name, zh, this.agentId, snippet);
    AppStorage.setOrCreate('pendingNotice',
      snippet.length > 0 ? `${this.name} ${zh} · ${snippet}` : `${this.name} ${zh}`);
    if (DetailVM.activeInstance !== this) {
      UnreadStore.getInstance().markFinished(this.agentId, this.name, zh, snippet).catch(() => {
      });
    }
  }

  private afterRunSettled(): void {
    ThemeStore.getInstance().setKeepScreenOn(false);
    LiveIsland.finish(runStatusZh(this.runStatus)).catch(() => {
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
    try {
      const usage = await CursorApiClient.getInstance().getUsage(this.agentId, runId);
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
      this.finishStreamingItems();
      StreamCoordinator.getInstance().release();
      Haptics.warn();
    } catch (e) {
      if (e instanceof ApiException && e.code === 409) {
        // already terminal — refresh
        try {
          const run = await CursorApiClient.getInstance().getRun(this.agentId, this.activeRunId);
          this.applyRunSnapshot(run);
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
    return this.activeRunId.length > 0 && !isTerminal(this.runStatus as RunStatus);
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
    try {
      await CursorApiClient.getInstance().archiveAgent(this.agentId);
      return true;
    } catch (e) {
      if (e instanceof ApiException) {
        this.errorMsg = e.message;
      } else {
        this.errorMsg = '归档失败';
      }
      this.notify();
      return false;
    }
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
    this.activeRunId = runId;
    this.streamRunId = runId;
    if (!resume) {
      this.activeAssistantKey = '';
      this.activeProgressKey = '';
      this.progressSealed = true;
      this.runHasTools = false;
      const existingThink = this.source.findIndexByKey(`thinking-${runId}`);
      this.activeThinkingKey = existingThink >= 0 ? `thinking-${runId}` : '';
    }
    this.streamNotice = '连接中…';
    ThemeStore.getInstance().setKeepScreenOn(true);
    LiveIsland.start(this.agentId, this.name, runStatusZh(this.runStatus.length > 0 ? this.runStatus : 'RUNNING'))
      .catch(() => {
      });
    this.clearPoll();
    // CREATING / flap fallback — design: ~5–15s; use 5s while CREATING else 8s
    const pollMs = this.runStatus === 'CREATING' ? 5000 : 8000;
    this.pollTimer = setInterval(async () => {
      if (this.streamRunId.length > 0 && this.streamRunId !== runId) {
        return;
      }
      if (!this.isRunActive()) {
        this.clearPoll();
        return;
      }
      try {
        const run = await CursorApiClient.getInstance().getRun(this.agentId, runId);
        if (this.streamRunId.length > 0 && this.streamRunId !== runId) {
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
          this.afterRunSettled();
          this.notify();
        }
      } catch (_e) {
      }
    }, pollMs) as number;

    const lastId = await PrefStore.getInstance().getLastEventId(this.agentId, runId);
    await StreamCoordinator.getInstance().acquire(this.agentId, runId, (frame: SseFrame) => {
      if (frame.id.length > 0) {
        this.pendingEventId = frame.id;
        this.eventIdFlush.kick();
      }
      this.onFrame(frame);
    }, (kind: string, detail: string) => {
      this.onStreamStatus(kind, detail);
    }, lastId);
  }

  private onStreamStatus(kind: string, detail: string): void {
    if (kind === 'streaming' || kind === 'connecting') {
      this.streamNotice = kind === 'connecting' ? '连接中…' : '';
    } else if (kind === 'reconnecting') {
      this.streamNotice = '连接已断开，正在重连…';
    } else if (kind === 'expired') {
      this.streamNotice = '流已过期，正在加载最终结果…';
      this.fetchTerminal();
    } else if (kind === 'done') {
      this.streamNotice = '';
      this.clearPoll();
      this.finishStreamingItems();
      this.eventIdFlush.flush();
    } else if (kind === 'error') {
      this.streamNotice = detail.length > 0 ? detail : 'SSE 异常，已切换轮询';
    }
    this.notify();
  }

  private async fetchTerminal(): Promise<void> {
    if (this.activeRunId.length === 0) {
      return;
    }
    try {
      const run = await CursorApiClient.getInstance().getRun(this.agentId, this.activeRunId);
      this.applyRunSnapshot(run);
      this.finishStreamingItems();
      this.ensureOutcomeItem(run);
      this.streamNotice = '已加载最终结果';
      Haptics.success();
      this.afterRunSettled();
    } catch (_e) {
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
    if (frame.event === 'heartbeat' || frame.event === 'unknown') {
      return;
    }
    if (frame.event === 'status') {
      const st = parseJson(frame.data);
      const status = `${st['status'] ?? ''}`;
      if (status.length > 0) {
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
      const status = `${st['status'] ?? 'FINISHED'}`;
      this.runStatus = status;
      const text = `${st['text'] ?? ''}`;
      if (text.length > 0) {
        this.resultText = text;
        this.ensureFinalAssistant(text);
      }
      const git = st['git'];
      if (git) {
        this.branches = extractBranches(git);
      }
      this.outcomeHighlight = true;
      this.finishStreamingItems();
      this.ensureOutcomeItem({
        id: this.activeRunId,
        agentId: this.agentId,
        status: status as RunStatus,
        createdAt: '',
        updatedAt: '',
        result: this.resultText,
        durationMs: Number(st['durationMs'] ?? 0),
        git: { branches: this.branches }
      });
      Haptics.success();
      this.announceFinished(status, this.resultText);
      this.eventIdFlush.flush();
      this.afterRunSettled();
      this.notify();
      return;
    }
    if (frame.event === 'error') {
      const st = parseJson(frame.data);
      this.streamNotice = `${st['message'] ?? '流错误'}`;
      this.notify();
      return;
    }
    if (frame.event === 'done') {
      this.streamNotice = '';
      this.clearPoll();
      this.finishStreamingItems();
      this.eventIdFlush.flush();
      if (!this.isRunActive()) {
        this.afterRunSettled();
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
      if (it.kind === 'thinking' || it.kind === 'progress' || it.kind === 'tool' || it.kind === 'step') {
        this.source.mutateAt(i, (item: TimelineItem) => {
          if (item.pinnedOpen !== true) {
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

  private persistTimeline(): void {
    if (this.agentId.length === 0) {
      return;
    }
    const snap = this.source.snapshot();
    const keep: TimelineItem[] = [];
    for (let i = 0; i < snap.length; i++) {
      const k = snap[i].kind;
      if (k === 'thinking' || k === 'progress' || k === 'step' || k === 'tool' || k === 'assistant' ||
        k === 'userPrompt') {
        snap[i].streaming = false;
        keep.push(snap[i]);
      }
    }
    if (keep.length > 0) {
      AgentCache.getInstance().saveTimeline(this.agentId, keep);
    }
  }

  private mergeCachedActivity(cached: TimelineItem[] | undefined): void {
    if (!cached || cached.length === 0) {
      return;
    }
    const snap = this.source.snapshot();
    for (let i = 0; i < snap.length; i++) {
      if (snap[i].kind === 'tool' || snap[i].kind === 'thinking') {
        return;
      }
    }
    const extras: TimelineItem[] = [];
    for (let i = 0; i < cached.length; i++) {
      const c = cached[i];
      if (c.kind !== 'thinking' && c.kind !== 'tool' && c.kind !== 'progress' && c.kind !== 'step') {
        continue;
      }
      if (this.source.findIndexByKey(c.key) >= 0) {
        continue;
      }
      c.collapsed = true;
      c.streaming = false;
      extras.push(c);
    }
    if (extras.length === 0) {
      return;
    }
    let insertAt = -1;
    for (let i = snap.length - 1; i >= 0; i--) {
      if (snap[i].kind === 'assistant') {
        insertAt = i;
        break;
      }
    }
    const next: TimelineItem[] = [];
    if (insertAt < 0) {
      for (let i = 0; i < snap.length; i++) {
        next.push(snap[i]);
      }
      for (let i = 0; i < extras.length; i++) {
        next.push(extras[i]);
      }
    } else {
      for (let i = 0; i < insertAt; i++) {
        next.push(snap[i]);
      }
      for (let i = 0; i < extras.length; i++) {
        next.push(extras[i]);
      }
      for (let i = insertAt; i < snap.length; i++) {
        next.push(snap[i]);
      }
    }
    this.source.replaceAll(next);
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
    // Open on latest turn (Linear/issue detail convention).
    this.stickToBottom = true;
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
        text: `运行 · ${runStatusZh(run.status)}`
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
        text: `运行 · ${runStatusZh(latest.status)}（完整对话暂不可用）`
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
    this.activeRunId = run.id;
    this.runStatus = run.status;
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
  }

  private recomputeCompareUrl(): void {
    let head = '';
    let repo = this.repoUrl;
    for (let i = 0; i < this.branches.length; i++) {
      const b = this.branches[i];
      if (!head && b.branch && b.branch.length > 0) {
        head = b.branch;
      }
      if (b.repoUrl && b.repoUrl.length > 0) {
        repo = b.repoUrl;
      }
    }
    this.compareUrl = gitCompareUrl(repo, this.startingRef, head);
  }

  private ensureOutcomeItem(run: Run): void {
    const key = `outcome-${run.id}`;
    const hasAnswer = this.hasAssistantForRun(run.id);
    const raw = run.result && run.result.length > 0 ? run.result : '';
    const text = hasAnswer ? '' : (raw.length > 0 ? raw : `状态：${runStatusZh(run.status)}`);
    const idx = this.source.findIndexByKey(key);
    if (idx >= 0) {
      this.source.mutateAt(idx, (item: TimelineItem) => {
        item.text = text;
        item.statusLabel = run.status;
      });
    } else {
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
      item.text = `运行 · ${runStatusZh(status)}`;
      this.source.updateAt(idx, item);
    } else {
      this.source.append({
        key: key,
        kind: 'runHeader',
        runId: runId,
        statusLabel: status,
        text: `运行 · ${runStatusZh(status)}`
      });
    }
  }

  private clearPoll(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
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
  return status === 'FINISHED' || status === 'ERROR' || status === 'CANCELLED' || status === 'EXPIRED';
}

function convFingerprint(messages: ConversationMessage[]): string {
  if (!messages || messages.length === 0) {
    return '';
  }
  const last = messages[messages.length - 1];
  return `${messages.length}|${last.id}|${(last.text ?? '').length}`;
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
  const name = friendlyToolName(tool.name);
  let detail = '';
  if (isSubagentTool(tool.name)) {
    detail = subagentDetail(tool.argsText ?? '');
    return detail.length > 0 ? `${name} · ${detail}` : name;
  }
  if (tool.argsText && tool.argsText.length > 0) {
    try {
      const args = JSON.parse(tool.argsText) as Record<string, Object>;
      if (args['path']) {
        detail = shortPathForTool(plainArg(args['path']));
      } else if (args['command']) {
        const cmd = plainArg(args['command']);
        detail = cmd.length > 48 ? `${cmd.substring(0, 48)}…` : cmd;
      } else if (args['query']) {
        const q = plainArg(args['query']);
        detail = q.length > 48 ? `${q.substring(0, 48)}…` : q;
      }
    } catch (_e) {
      detail = '';
    }
  }
  return detail.length > 0 ? `${name} · ${detail}` : name;
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
