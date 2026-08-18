import { common } from '@kit.AbilityKit';
import { KeyboardAvoidMode, LengthMetrics } from '@kit.ArkUI';
import { DetailVM } from '../viewmodels/DetailVM';
import { TimelineItem } from '../models/Timeline';
import { TimelineSource } from '../datasource/TimelineSource';
import {
  ArtifactInfo, CustomSubagentDef, EnvVarDef, McpServerDef, ModelInfo, RunUsage
} from '../models/Api';
import { NewAgentVM } from '../viewmodels/NewAgentVM';
import { ModelPicker } from '../components/ModelPicker';
import { StatusPill } from '../components/StatusPill';
import { ToastHost } from '../components/ToastHost';
import {
  buildParamRows, formatChipFromRows, formatFollowChip, findModel, groupModels, isAutoModel,
  ModelParamRow, ModelVendorGroup, paramRowsStamp, rowsToParams, snapParamRows, variantLabel,
  variantSectionTitle
} from '../utils/ModelGroups';
import { Tokens } from '../theme/Tokens';
import { BreakpointStore } from '../store/BreakpointStore';
import { ActivityCard } from '../components/ActivityCard';
import { PromptShell } from '../components/PromptShell';
import { MarkdownLite } from '../components/MarkdownLite';
import { InboxVM } from '../viewmodels/InboxVM';
import { shouldUseInAppBrowser } from './InAppBrowserPage';
import { shareAgentLinks } from '../utils/Share';
import { elapsedLabel, repoTail, shortAgentId } from '../utils/DisplayFmt';
import { shortPathForTool } from '../utils/StreamText';
import { chromeTransition, runLayout, shimmerMs, shimmerOpacity } from '../utils/Motion';
import { WebLinks, pushInAppBrowser } from '../utils/WebLinks';
import { ArtifactRow } from '../components/ArtifactRow';
import { McpListEditor } from '../components/CapabilityEditors';
import { countMcp, isMcpReady, parseToolsPref, toolsChipLabel, defaultEnv } from '../utils/AgentCapabilities';
import { PrefStore } from '../store/PrefStore';
import { HuIcon } from '../components/HuIcon';
import { HuIconButton } from '../components/HuIconButton';
import { SheetActionRow } from '../components/SheetAction';
import { dropPreviewMap, maxPromptImages, pickPromptImages, previewSrc, PromptImage } from '../utils/ImagePicker';
import { copyToClipboard } from '../utils/Clipboard';
import { confirmDanger } from '../utils/AppDialog';
import { showToast } from '../utils/AppToast';
import { Haptics } from '../utils/Haptics';
import { NetworkMonitor } from '../utils/NetworkMonitor';
import { relativeTime } from '../utils/TimeFmt';
import { isShowableImageUrl, isOpaqueStepLabel } from '../utils/TimelineMedia';
import { isWaitingThink, nextUserJumpAt, visibleKeySig, visibleRowSig, visibleTimeline } from '../utils/TimelineView';
import { isSafeHttpsUrl } from '../utils/SafeUrl';
import { meaningfulStepTitle, processDoneTitle, processLiveTitle, runHeaderVerb, toolSlug,
  waitingThinkLabel } from '../utils/TimelineCopy';
import { makeQuoteEditMenu } from '../utils/TextSelectMenu';

function fmtTk(n: number | undefined): string {
  const v = n ?? 0;
  if (v < 1000) return `${v}`;
  if (v < 10000) return `${(v / 1000).toFixed(1)}k`;
  return `${Math.round(v / 1000)}k`;
}

@Builder
export function AgentDetailPageBuilder() {
  AgentDetailPage()
}

@Component
struct AgentDetailPage {
  @Consume('navPathStack') navStack: NavPathStack;
  private vm: DetailVM = DetailVM.getInstance();
  private modelVm: NewAgentVM = new NewAgentVM();
  private bp: BreakpointStore = BreakpointStore.getInstance();
  private listScroller: Scroller = new Scroller();

  @State noticeLine: string = '';
  @State agentId: string = '';
  @State name: string = '';
  @State status: string = '';
  @State runStatus: string = '';
  @State url: string = '';
  @State loading: boolean = false;
  @State errorMsg: string = '';
  @State resultText: string = '';
  @State streamNotice: string = '';
  @State createRetryable: boolean = false;
  @State queueImagesLost: boolean = false;
  @State runActive: boolean = false;
  @State sending: boolean = false;
  @State cancelling: boolean = false;
  @State draft: string = '';
  @State pagePad: number = 16;
  @State showJump: boolean = false;
  @State showSheet: boolean = false;
  @State sheetKind: string = '';
  @State tick: number = 0;
  @State shimmerOn: boolean = true;
  @State durationMs: number = 0;
  @State repoLabel: string = '';
  @State metaLine: string = '';
  @State usageLabel: string = '';
  @State needsPlanUpgrade: boolean = false;
  @State artifacts: ArtifactInfo[] = [];
  @State usageRuns: RunUsage[] = [];
  @State topInset: number = 0;
  @State bottomInset: number = 0;
  @State queuedFollowUp: string = '';
  @State feed: TimelineItem[] = [];
  private visibleSource: TimelineSource = new TimelineSource();
  private feedKeySig: string = '';
  private feedRowSigs: string[] = [];
  private unsubBp: (() => void) | undefined = undefined;
  @State followUpMode: string = 'agent';
  @State followModelLabel: string = '';
  @State followUpModel: string = '';
  @State followVariantIndex: number = -1;
  @State followVariant: string = '';
  @State followModelGroups: ModelVendorGroup[] = [];
  @State followModelsLoading: boolean = false;
  @State followModelsError: string = '';
  @State followVariantOptions: string[] = [];
  @State followVariantTitle: string = '模式';
  @State followParamRows: ModelParamRow[] = [];
  @State followParamStamp: string = '';
  @State followChipLabel: string = '';
  @State failedFollow: boolean = false;
  @State compareUrl: string = '';
  @State pinned: boolean = false;
  @State attachedImages: PromptImage[] = [];
  @State imageUris: string[] = [];
  @State followUpMcp: McpServerDef[] = [];
  @State followToolsLabel: string = 'MCP';
  @State mdSettled: boolean = true;
  @State syncing: boolean = false;
  @State convError: string = '';
  @State unreadPill: number = 0;
  @State unreadAnchorKey: string = '';
  @State renameDraft: string = '';
  @State isHover: boolean = false;
  @State pressKey: string = '';
  @State jumpIndex: number = 0;
  @State jumpTotal: number = 0;
  @State showJumpHint: boolean = false;
  @State quoteText: string = '';
  @State bubbleMax: number = 280;
  @State online: boolean = true;
  private tickTimer: number = -1;
  private mdTimer: number = -1;
  private runStartMs: number = 0;
  private lastKb: number = 0;
  private lastListH: number = 0;
  private pinTimer: number = -1;
  private followSig: string = '';
  private unreadJumped: boolean = false;
  private jumpHintTimer: number = -1;
  private lastUserKey: string = '';
  private lastJumpedKey: string = '';
  private feedViewStart: number = 0;
  private feedViewEnd: number = -1;
  private unsubNet: (() => void) | undefined = undefined;

  aboutToDisappear(): void {
    try {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    } catch (_e) {
    }
    this.clearTick();
    if (this.mdTimer >= 0) {
      clearTimeout(this.mdTimer);
      this.mdTimer = -1;
    }
    if (this.pinTimer >= 0) {
      clearTimeout(this.pinTimer);
      this.pinTimer = -1;
    }
    if (this.jumpHintTimer >= 0) {
      clearTimeout(this.jumpHintTimer);
      this.jumpHintTimer = -1;
    }
    this.vm.detachView();
    if (this.unsubBp) {
      this.unsubBp();
      this.unsubBp = undefined;
    }
    if (this.unsubNet) {
      this.unsubNet();
      this.unsubNet = undefined;
    }
  }

  private armMdSettle(): void {
    let streaming = false;
    const total = this.vm.source.totalCount();
    for (let i = 0; i < total; i++) {
      if (this.vm.source.getData(i).streaming === true) {
        streaming = true;
        break;
      }
    }
    if (streaming) {
      this.mdSettled = false;
      if (this.mdTimer >= 0) {
        clearTimeout(this.mdTimer);
      }
      this.mdTimer = setTimeout(() => {
        this.mdSettled = true;
        this.mdTimer = -1;
      }, 240) as number;
    } else {
      this.mdSettled = true;
    }
  }

  private sync(): void {
    if (this.vm.agentId.length > 0 && this.vm.agentId !== this.agentId) {
      this.agentId = this.vm.agentId;
      this.lastUserKey = '';
      this.feedViewEnd = -1;
      this.feedKeySig = '';
      this.feedRowSigs = [];
    }
    this.name = this.vm.name;
    this.status = this.vm.status;
    this.runStatus = this.vm.runStatus;
    this.url = this.vm.url;
    this.loading = this.vm.loading;
    this.syncing = this.vm.syncing;
    this.errorMsg = this.vm.errorMsg;
    this.convError = this.vm.convError;
    this.unreadPill = this.vm.unreadNewCount;
    this.unreadAnchorKey = this.vm.unreadAnchorKey;
    this.resultText = this.vm.resultText;
    this.streamNotice = this.vm.streamNotice;
    this.createRetryable = this.vm.createRetryable;
    this.queueImagesLost = this.vm.queueImagesLost;
    this.runActive = this.vm.isRunActive();
    this.sending = this.vm.sending;
    this.cancelling = this.vm.cancelling;
    this.durationMs = this.vm.durationMs;
    this.repoLabel = this.vm.repoLabel;
    this.metaLine = this.vm.metaLine;
    this.usageLabel = this.vm.usageLabel;
    this.needsPlanUpgrade = this.vm.needsPlanUpgrade;
    this.artifacts = this.vm.artifacts;
    this.usageRuns = this.vm.usageRuns;
    this.queuedFollowUp = this.vm.queuedFollowUp;
    this.followUpMode = this.vm.followUpMode;
    this.followUpModel = this.vm.followUpModel;
    this.failedFollow = this.vm.lastFailedPrompt.length > 0 || this.vm.lastFailedImages.length > 0;
    this.rebuildFeed();
    this.compareUrl = this.vm.compareUrl;
    this.followToolsLabel = toolsChipLabel(defaultEnv(), this.followUpMcp, [] as CustomSubagentDef[],
      [] as EnvVarDef[]);
    this.armMdSettle();
    this.armTick();

    if (this.vm.deleted) {
      InboxVM.getInstance().removeLocal(this.agentId);
      this.vm.close();
      this.navStack.pop();
      return;
    }

    if (this.vm.stickToBottom) {
      this.pinFeedToComposer(16, false);
    } else if (this.unreadAnchorKey.length > 0 && this.lastJumpedKey !== this.unreadAnchorKey) {
      let found = false;
      for (let i = 0; i < this.feed.length; i++) {
        if (this.feed[i].key === this.unreadAnchorKey) {
          found = true;
          break;
        }
      }
      if (found) {
        this.lastJumpedKey = this.unreadAnchorKey;
        this.unreadJumped = true;
        this.scrollToKey(this.unreadAnchorKey);
      }
    }
  }

  private scrollToKey(key: string): void {
    if (key.length === 0) {
      return;
    }
    let idx = -1;
    for (let i = 0; i < this.feed.length; i++) {
      if (this.feed[i].key === key) {
        idx = i;
        break;
      }
    }
    if (idx < 0) {
      return;
    }
    setTimeout(() => {
      try {
        this.listScroller.scrollToIndex(idx);
      } catch (_e) {
      }
    }, 32);
  }

  private jumpUser(dir: number): void {
    const keys: string[] = [];
    const idxs: number[] = [];
    for (let i = 0; i < this.feed.length; i++) {
      if (this.feed[i].kind === 'userPrompt') {
        keys.push(this.feed[i].key);
        idxs.push(i);
      }
    }
    if (keys.length === 0) {
      return;
    }
    const viewEnd = this.feedViewEnd >= 0 ? this.feedViewEnd :
      (this.vm.stickToBottom ? Math.max(this.feed.length - 1, 0) : this.feedViewStart);
    const at = nextUserJumpAt(keys, idxs, this.lastUserKey, dir, this.feedViewStart, viewEnd);
    if (at < 0) {
      return;
    }
    this.lastUserKey = keys[at];
    this.jumpIndex = at + 1;
    this.jumpTotal = keys.length;
    this.showJumpHint = true;
    if (this.jumpHintTimer >= 0) {
      clearTimeout(this.jumpHintTimer);
    }
    this.jumpHintTimer = setTimeout(() => {
      this.showJumpHint = false;
      this.jumpHintTimer = -1;
    }, 1400) as number;
    this.vm.stickToBottom = false;
    try {
      this.listScroller.scrollToIndex(idxs[at]);
    } catch (_e) {
    }
  }

  private applyQuote(text: string): void {
    const t = text.trim();
    if (t.length === 0) {
      return;
    }
    this.quoteText = t.length > 600 ? `${t.substring(0, 600)}…` : t;
    this.pinFeedToComposer(16, true);
    try {
      Haptics.click();
    } catch (_e) {
    }
  }

  private wrapQuote(body: string): string {
    if (this.quoteText.length === 0) {
      return body;
    }
    const lines = this.quoteText.split('\n');
    let quoted = '';
    for (let i = 0; i < lines.length; i++) {
      quoted = quoted.length === 0 ? `> ${lines[i]}` : `${quoted}\n> ${lines[i]}`;
    }
    if (body.trim().length === 0) {
      return quoted;
    }
    return `${quoted}\n\n${body}`;
  }

  private hasUserPrompts(): boolean {
    for (let i = 0; i < this.feed.length; i++) {
      if (this.feed[i].kind === 'userPrompt') {
        return true;
      }
    }
    return false;
  }

  private feedFollowSig(): string {
    const last = this.feed.length > 0 ? this.feed[this.feed.length - 1].key : '';
    return `${this.runActive ? 1 : 0}:${this.feed.length}:${last}:${this.queuedFollowUp.length}:${this.processFoot()}`;
  }

  private pinFeedToComposer(delayMs: number = 16, force: boolean = true): void {
    const sig = this.feedFollowSig();
    if (!force && sig === this.followSig) {
      return;
    }
    this.followSig = sig;
    this.vm.stickToBottom = true;
    this.showJump = false;
    if (this.pinTimer >= 0) {
      clearTimeout(this.pinTimer);
      this.pinTimer = -1;
    }
    const kick = (ms: number): void => {
      setTimeout(() => {
        try {
          this.listScroller.scrollEdge(Edge.Bottom);
        } catch (_e) {
        }
      }, ms);
    };
    kick(delayMs);
    this.pinTimer = setTimeout(() => {
      this.pinTimer = -1;
      try {
        this.listScroller.scrollEdge(Edge.Bottom);
      } catch (_e) {
      }
    }, delayMs + 200) as number;
  }

  private onKeyboardChrome(): void {
    const kb = this.bp.keyboardInsetVp;
    if (kb > 16 && this.lastKb <= 16) {
      this.pinFeedToComposer(32, true);
    } else if (kb <= 16 && this.lastKb > 16 && this.vm.stickToBottom) {
      this.pinFeedToComposer(16, true);
    }
    this.lastKb = kb;
  }

  private rebuildFeed(): void {
    const rows = visibleTimeline(this.vm.source.snapshot());
    const next: TimelineItem[] = [];
    for (let i = 0; i < rows.length; i++) {
      if (rows[i].kind === 'runOutcome' && this.shouldSkipOutcome(rows[i])) {
        continue;
      }
      next.push(rows[i]);
    }
    const keys = visibleKeySig(next);
    if (keys === this.feedKeySig && next.length === this.feed.length &&
      next.length === this.feedRowSigs.length && next.length > 0) {
      for (let i = 0; i < next.length; i++) {
        const sig = visibleRowSig(next[i]);
        if (this.feedRowSigs[i] !== sig) {
          this.feedRowSigs[i] = sig;
          this.feed[i] = next[i];
          this.visibleSource.updateAt(i, next[i]);
        }
      }
      return;
    }
    const rowSigs: string[] = [];
    for (let i = 0; i < next.length; i++) {
      rowSigs.push(visibleRowSig(next[i]));
    }
    this.feedKeySig = keys;
    this.feedRowSigs = rowSigs;
    this.feed = next;
    this.visibleSource.replaceAll(next);
  }

  private consumeNotice(): void {
    let line = '';
    try {
      const raw = AppStorage.get<string>('pendingNotice');
      if (raw && raw.length > 0) {
        line = raw;
        AppStorage.setOrCreate('pendingNotice', '');
      }
    } catch (_e) {
    }
    if (line.length > 0) {
      this.noticeLine = line;
    }
  }

  private dismissNotice(): void {
    this.noticeLine = '';
  }

  private openLink(link: string, title: string = 'Web'): void {
    if (!isSafeHttpsUrl(link)) {
      return;
    }
    if (shouldUseInAppBrowser(link)) {
      pushInAppBrowser(this.navStack, link, title);
      return;
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    ctx.openLink(link).catch(() => {
    });
  }

  private async attachImages(): Promise<void> {
    const remain = maxPromptImages() - this.attachedImages.length;
    if (remain <= 0) {
      showToast('最多 5 张图', 'info', 'detail');
      return;
    }
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const picked = await pickPromptImages(ctx, remain);
      if (picked.length > 0) {
        this.attachedImages = this.attachedImages.concat(picked);
        this.syncImageUris();
      }
    } catch (_e) {
      showToast('选图取消或失败', 'warn', 'detail');
    }
  }

  private removeAttached(index: number): void {
    if (index >= 0 && index < this.attachedImages.length) {
      dropPreviewMap(previewSrc(this.attachedImages[index]));
    }
    const next: PromptImage[] = [];
    for (let i = 0; i < this.attachedImages.length; i++) {
      if (i !== index) {
        next.push(this.attachedImages[i]);
      }
    }
    this.attachedImages = next;
    this.syncImageUris();
  }

  private syncImageUris(): void {
    const uris: string[] = [];
    for (let i = 0; i < this.attachedImages.length; i++) {
      const src = previewSrc(this.attachedImages[i]);
      if (src.length > 0) {
        uris.push(src);
      }
    }
    this.imageUris = uris;
  }

  private openSheet(kind: string): void {
    this.sheetKind = kind;
    this.showSheet = true;
    if (kind === 'model') {
      this.ensureFollowModelsLoaded(this.followModelGroups.length === 0);
    }
  }

  private closeSheet(): void {
    this.showSheet = false;
  }

  private armTick(): void {
    if (this.runActive || this.sending) {
      if (this.runActive && this.runStartMs === 0) {
        this.runStartMs = Date.now();
      }
      if (this.tickTimer < 0) {
        this.tickTimer = setInterval(() => {
          this.tick += 1;
          this.shimmerOn = !this.shimmerOn;
        }, 900) as number;
      }
    } else {
      this.runStartMs = 0;
      this.clearTick();
    }
  }

  private clearTick(): void {
    if (this.tickTimer >= 0) {
      clearInterval(this.tickTimer);
      this.tickTimer = -1;
    }
  }

  private failed(): boolean {
    return this.runStatus === 'ERROR' || this.runStatus === 'EXPIRED';
  }

  private authFail(): boolean {
    const e = this.errorMsg;
    return e.indexOf('401') >= 0 || e.indexOf('API Key') >= 0 || e.indexOf('Unauthorized') >= 0 ||
      e.indexOf('失效') >= 0;
  }

  private processFoot(): string {
    const n = this.streamNotice;
    if (n === '正在提交…' || n === '连接中…') {
      return n;
    }
    if (n.indexOf('重连') >= 0 || n.indexOf('流已过期') >= 0 || n.indexOf('正在加载最终') >= 0) {
      return n;
    }
    if (this.sending) {
      return '正在提交…';
    }
    if (this.loading || this.syncing) {
      return '同步对话…';
    }
    return '';
  }

  private processFootRetry(): boolean {
    return this.processFoot().indexOf('重连') >= 0;
  }

  private streamFailNotice(): boolean {
    const n = this.streamNotice;
    if (n.length === 0) {
      return false;
    }
    if (this.processFoot() === n) {
      return false;
    }
    if (n === '结束后发送' || n.indexOf('结束后') >= 0 || n.indexOf('稍后自动') >= 0 ||
      n === '已取消') {
      return false;
    }
    return true;
  }

  private retryLabel(): string {
    if (this.createRetryable) {
      return '重试提交';
    }
    if (this.errorMsg.indexOf('排队') >= 0) {
      return '重发';
    }
    const n = this.streamNotice;
    if (n.indexOf('断开') >= 0 || n.indexOf('异常') >= 0 || n.indexOf('无法获取') >= 0) {
      return '重连';
    }
    if (this.errorMsg.length > 0 && !this.authFail()) {
      return '重试';
    }
    return '';
  }

  private syncFollowModels(): void {
    const models = this.modelVm.models;
    let groups = groupModels(models);
    if (groups.length === 0 && models.length > 0) {
      const items: ModelInfo[] = [];
      for (let i = 0; i < models.length; i++) {
        if (!isAutoModel(models[i])) {
          items.push(models[i]);
        }
      }
      if (items.length > 0) {
        groups = [{ vendor: '模型', items: items }];
      }
    }
    this.followModelGroups = groups;
    this.refreshFollowModelMeta();
  }

  private ensureFollowModelsLoaded(force: boolean = false): void {
    this.syncFollowModels();
    if (!force && this.followModelGroups.length > 0) {
      this.followModelsError = '';
      return;
    }
    this.followModelsLoading = true;
    this.followModelsError = '';
    this.modelVm.loadMeta(false).then(() => {
      this.followModelsLoading = false;
      this.syncFollowModels();
      this.ensureFollowModel();
      if (this.followModelGroups.length === 0 && this.modelVm.models.length === 0) {
        this.followModelsError = '模型列表没加载到，点重试。';
      }
    }, () => {
      this.followModelsLoading = false;
      this.syncFollowModels();
      if (this.followModelGroups.length === 0) {
        this.followModelsError = '模型列表没加载到，点重试。';
      }
    });
  }

  private refreshFollowChip(): void {
    this.followParamStamp = paramRowsStamp(this.followParamRows);
    if (this.followUpModel.length === 0) {
      this.followChipLabel = '自动';
      return;
    }
    const name = this.followModelLabel.length > 0 ? this.followModelLabel : this.followUpModel;
    if (this.followParamRows.length > 0) {
      const chip = formatChipFromRows(name, this.followParamRows);
      this.followChipLabel = chip.length > 0 ? chip : name;
      return;
    }
    const chip = formatFollowChip(name, this.vm.followUpParams);
    this.followChipLabel = chip.length > 0 ? chip : name;
  }

  private ensureFollowModel(): void {
    if (this.followUpModel.length > 0) {
      this.refreshFollowModelMeta();
      return;
    }
    const fromVm = this.modelVm.selectedModel;
    if (fromVm.length > 0) {
      this.pickFollowModel(fromVm);
      return;
    }
    const models = this.modelVm.models;
    for (let i = 0; i < models.length; i++) {
      if (!isAutoModel(models[i])) {
        this.pickFollowModel(models[i].id);
        return;
      }
    }
  }

  private pickFollowModel(id: string): void {
    this.followUpModel = id;
    this.modelVm.selectedModel = id;
    this.followVariantIndex = -1;
    this.followVariant = '';
    this.modelVm.selectedVariantIndex = -1;
    this.modelVm.selectedVariant = '';
    this.modelVm.selectedParams = [];
    this.refreshFollowModelMeta();
    this.vm.followUpModel = id;
    const payload = this.modelVm.modelPayload();
    this.vm.followUpParams = payload && payload['params'] ? payload['params'] as Object[] : [];
    this.refreshFollowChip();
  }

  private refreshFollowModelMeta(): void {
    this.followVariantOptions = [];
    this.followVariantTitle = '模式';
    this.followParamRows = [];
    this.followModelLabel = '';
    if (this.followUpModel.length === 0) {
      this.refreshFollowChip();
      return;
    }
    const models = this.modelVm.models;
    for (let i = 0; i < models.length; i++) {
      const m = models[i];
      if (m.id !== this.followUpModel) {
        continue;
      }
      this.followModelLabel = m.displayName ?? m.id;
      const rows = buildParamRows(m);
      if (rows.length > 0) {
        this.followParamRows = snapParamRows(m, rows, '', -1);
        this.modelVm.selectedParams = rowsToParams(this.followParamRows);
        this.refreshFollowChip();
        return;
      }
      if (m.variants && m.variants.length > 0) {
        const labels: string[] = [];
        for (let j = 0; j < m.variants.length; j++) {
          labels.push(variantLabel(m.variants[j], j));
        }
        this.followVariantOptions = labels;
        this.followVariantTitle = variantSectionTitle(m.variants);
        if (this.followVariantIndex < 0) {
          let def = 0;
          for (let j = 0; j < m.variants.length; j++) {
            if (m.variants[j].isDefault === true) {
              def = j;
              break;
            }
          }
          this.followVariantIndex = def;
          this.modelVm.selectedVariantIndex = def;
        }
      }
      this.refreshFollowChip();
      return;
    }
    this.followModelLabel = this.followUpModel;
    this.refreshFollowChip();
  }

  private pickFollowParam(rowId: string, valueIdx: number): void {
    this.followParamRows = snapParamRows(findModel(this.modelVm.models, this.followUpModel),
      this.followParamRows, rowId, valueIdx);
    this.modelVm.selectedParams = rowsToParams(this.followParamRows);
    const payload = this.modelVm.modelPayload();
    this.vm.followUpParams = payload && payload['params'] ? payload['params'] as Object[] : [];
    this.refreshFollowChip();
  }

  private async runRetry(): Promise<void> {
    const label = this.retryLabel();
    if (label === '重试提交') {
      await this.vm.retryCreate();
    } else if (label === '重发') {
      await this.vm.retryQueuedFollowUp();
    } else {
      await this.vm.retryConnection();
    }
    this.sync();
  }

  private shortRepo(): string {
    if (this.vm.repoUrl.length > 0) {
      return repoTail(this.vm.repoUrl);
    }
    return this.repoLabel;
  }

  private firstPr(): string {
    for (let i = 0; i < this.vm.branches.length; i++) {
      const u = this.vm.branches[i].prUrl ?? '';
      if (u.length > 0) {
        return u;
      }
    }
    return '';
  }

  private firstBranch(): string {
    for (let i = 0; i < this.vm.branches.length; i++) {
      const b = this.vm.branches[i].branch ?? '';
      if (b.length > 0) {
        return b;
      }
    }
    return '';
  }

  private prLabel(): string {
    const u = this.firstPr();
    const m = u.match(/\/pull\/(\d+)/);
    if (m && m[1]) {
      return `PR ${m[1]}`;
    }
    return u.length > 0 ? 'PR' : '';
  }

  private toolStepCount(): number {
    let n = 0;
    const total = this.vm.source.totalCount();
    for (let i = 0; i < total; i++) {
      const it = this.vm.source.getData(i);
      if (it.kind === 'tool' || it.kind === 'step') {
        n += 1;
      }
    }
    return n;
  }

  private currentFile(): string {
    const total = this.vm.source.totalCount();
    for (let i = total - 1; i >= 0; i--) {
      const it = this.vm.source.getData(i);
      if (it.kind === 'tool') {
        const raw = it.tool?.argsText ?? it.text ?? '';
        const path = shortPathForTool(raw);
        if (path.length > 0) {
          return path;
        }
        if ((it.text ?? '').length > 0) {
          return it.text ?? '';
        }
      }
    }
    return '';
  }

  private compactElapsed(): string {
    const _t = this.tick;
    if (this.runActive && this.runStartMs > 0) {
      return this.liveElapsed();
    }
    if (this.durationMs > 0) {
      return elapsedLabel(Math.floor(this.durationMs / 1000));
    }
    return '';
  }

  private liveElapsed(): string {
    if (this.runStartMs <= 0) {
      return '';
    }
    const sec = Math.max(0, Math.floor((Date.now() - this.runStartMs) / 1000));
    if (sec < 15) {
      return '';
    }
    return elapsedLabel(sec);
  }

  private cardProcessTitle(item: TimelineItem): string {
    const live = item.streaming === true && (this.runActive || this.sending);
    const tools = this.toolsForRun(item.runId);
    const elapsed = this.elapsedForCard(item.runId, live);
    if (!live) {
      return processDoneTitle(tools.length > 0, elapsed);
    }
    const slug = this.liveToolSlug(tools);
    if (slug.length > 0) {
      return processLiveTitle(false, slug, true, elapsed);
    }
    const named = this.latestStepTitle(item.runId);
    if (named.length > 0) {
      return elapsed.length > 0 ? `${named} · ${elapsed}` : named;
    }
    const connecting = item.runId === 'pending' || (item.text ?? '').trim().length === 0;
    return processLiveTitle(connecting, '', tools.length > 0, elapsed);
  }

  private latestStepTitle(runId: string): string {
    let last = '';
    const total = this.vm.source.totalCount();
    for (let i = 0; i < total; i++) {
      const it = this.vm.source.getData(i);
      if (it.runId !== runId || it.kind !== 'step') {
        continue;
      }
      const t = meaningfulStepTitle(it.text ?? '');
      if (t.length > 0) {
        last = t;
      }
    }
    return last;
  }

  private elapsedForCard(runId: string, live: boolean): string {
    const _t = this.tick;
    if (live) {
      return this.liveElapsed();
    }
    if (this.durationMs > 0 && (runId === this.vm.activeRunId || runId.length === 0)) {
      return elapsedLabel(Math.floor(this.durationMs / 1000));
    }
    return '';
  }

  private liveToolSlug(tools: TimelineItem[]): string {
    for (let i = tools.length - 1; i >= 0; i--) {
      const t = tools[i].tool;
      if (t && (t.status ?? 'running') !== 'completed') {
        return toolSlug(t.name);
      }
    }
    return '';
  }

  private processLabel(): string {
    const _t = this.tick;
    let elapsed = '';
    if (this.runActive && this.runStartMs > 0) {
      elapsed = this.liveElapsed();
    } else if (this.durationMs > 0) {
      elapsed = elapsedLabel(Math.floor(this.durationMs / 1000));
    }
    const steps = this.toolStepCount();
    if (this.runActive) {
      return elapsed.length > 0 ? `在想下一步 · ${elapsed}` : '在想下一步';
    }
    if (steps === 0 && elapsed.length === 0) {
      return '';
    }
    if (elapsed.length > 0) {
      return steps > 0 ? `用了 ${elapsed}` : `思考了 ${elapsed}`;
    }
    return steps > 0 ? '过程' : '';
  }

  private processBody(): string {
    const total = this.vm.source.totalCount();
    for (let i = total - 1; i >= 0; i--) {
      const it = this.vm.source.getData(i);
      if (it.kind === 'thinking' && (it.text ?? '').length > 0) {
        return it.text ?? '';
      }
    }
    return '';
  }

  private followHints(): string[] {
    if (this.runActive || this.failed()) {
      return [];
    }
    const out: string[] = [];
    const lines = this.resultText.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const t = lines[i].trim();
      if (t.endsWith('？') || t.endsWith('?')) {
        const clean = t.replace(/^[-*\d.\s]+/, '');
        if (clean.length > 4 && clean.length < 36) {
          out.push(clean);
        }
      }
      if (out.length >= 2) {
        break;
      }
    }
    return out;
  }

  private isShortMsg(text: string): boolean {
    if (text.length === 0 || text.length > 40) {
      return false;
    }
    return text.indexOf('\n') < 0 && text.indexOf('```') < 0 && text.indexOf('|') < 0;
  }

  private copyText(text: string): void {
    if (!text) {
      return;
    }
    Haptics.click();
    copyToClipboard(text).then((ok: boolean) => {
      if (ok) {
        showToast('已复制', 'info', 'detail');
      } else {
        showToast(text.length > 48 ? `${text.substring(0, 48)}…` : text, 'warn', 'detail');
      }
    });
  }

  private statusZh(raw: string): string {
    if (raw === 'FINISHED') {
      return '已完成';
    }
    if (raw === 'RUNNING') {
      return '运行中';
    }
    if (raw === 'CREATING') {
      return '创建中';
    }
    if (raw === 'ERROR') {
      return '失败';
    }
    if (raw === 'CANCELLED') {
      return '已取消';
    }
    if (raw === 'EXPIRED') {
      return '已过期';
    }
    if (raw === 'ACTIVE') {
      return '活跃';
    }
    if (raw === 'ARCHIVED') {
      return '已归档';
    }
    return raw;
  }

  private async togglePin(): Promise<void> {
    const ids = await PrefStore.getInstance().getPinnedIds();
    const next: string[] = [];
    let found = false;
    for (let i = 0; i < ids.length; i++) {
      if (ids[i] === this.agentId) {
        found = true;
      } else {
        next.push(ids[i]);
      }
    }
    if (!found) {
      next.unshift(this.agentId);
    }
    this.pinned = !found;
    await PrefStore.getInstance().setPinnedIds(next);
  }

  private menuStatusLine(): string {
    const raw = this.runStatus.length > 0 ? this.runStatus : this.status;
    const st = this.runActive ? '运行中' : this.statusZh(raw);
    const el = this.compactElapsed();
    if (el.length > 0) {
      return `${st} · ${el}`;
    }
    return st;
  }

  build() {
    NavDestination() {
      Column() {
        Column() {
          Row() {
            HuIconButton({
              name: 'back',
              label: '返回',
              onTap: () => {
                this.navStack.pop();
              }
            })
            Row({ space: 6 }) {
              Text(this.name.length > 0 ? this.name : shortAgentId(this.agentId))
                .fontSize(Tokens.typeHeadline)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
                .constraintSize({ minWidth: 0 })
              if (this.runActive && this.processLabel().length > 0) {
                Text(this.compactElapsed())
                  .fontSize(Tokens.typeMicro)
                  .fontColor($r('app.color.text_secondary'))
                  .opacity(shimmerOpacity(this.shimmerOn))
                  .animation({ duration: shimmerMs(), curve: Curve.EaseInOut })
              }
            }
            .layoutWeight(1)
            .constraintSize({ minWidth: 0 })
            .height(Tokens.touchMin)
            .alignItems(VerticalAlign.Center)
            HuIconButton({
              name: 'more',
              label: '更多操作',
              iconColor: $r('app.color.text_secondary'),
              onTap: () => {
                this.openSheet('menu');
              }
            })
          }
          .width('100%')
          .height(Tokens.touchMin)
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({
          left: Tokens.chromePad,
          right: Tokens.chromePad,
          top: this.topInset
        })

        if (this.isHover) {
          FolderStack({ upperItems: ['hoverTimeline'] }) {
            Column() {
              this.timelinePane()
            }
            .id('hoverTimeline')
            .width('100%')
            .height('100%')
            Column() {
              this.composerPane()
            }
            .width('100%')
          }
          .width('100%')
          .layoutWeight(1)
        } else {
          this.timelinePane()
          this.composerPane()
        }
      }
      .width('100%')
      .height('100%')
      .overlay(this.detailDock(), { align: Alignment.Bottom })
      .backgroundColor($r('app.color.bg0'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    }
    .hideTitleBar(true)
    .bindSheet($$this.showSheet, this.sheetBody(), {
      height: this.sheetKind === 'artifacts' || this.sheetKind === 'model' ? SheetSize.MEDIUM :
        SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      radius: LengthMetrics.vp(Tokens.radiusSheet),
      backgroundColor: $r('app.color.overlay')
    })
    .backgroundColor($r('app.color.bg0'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    .onReady((ctx: NavDestinationContext) => {
      try {
        this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
      } catch (_e) {
      }
      this.pagePad = this.bp.pagePad();
      this.topInset = this.bp.safeTop();
      this.bottomInset = this.bp.followComposerBottom();
      this.isHover = this.bp.isHover;
      this.unsubBp = this.bp.onChange(() => {
        runLayout(() => {
          this.pagePad = this.bp.pagePad();
          this.topInset = this.bp.safeTop();
          this.bottomInset = this.bp.followComposerBottom();
          this.isHover = this.bp.isHover;
        });
        this.onKeyboardChrome();
      });
      NetworkMonitor.getInstance().start();
      this.online = NetworkMonitor.getInstance().online;
      this.unsubNet = NetworkMonitor.getInstance().onChange((v: boolean) => {
        this.online = v;
      });
      const p = ctx.pathInfo.param as Record<string, Object>;
      if (p && p['agentId']) {
        this.agentId = `${p['agentId']}`;
        this.vm.setUiListener(() => {
          this.sync();
        });
        const seeded = `${p['seed'] ?? ''}` === '1' || this.agentId.indexOf('local-') === 0;
        let opened: Promise<void> = Promise.resolve();
        if (seeded) {
          opened = this.vm.openFromCreate(this.agentId);
        } else if (this.vm.canReattach(this.agentId)) {
          this.vm.attachView();
          opened = this.vm.resumeIfNeeded();
          this.sync();
        } else {
          opened = this.vm.open(this.agentId);
        }
        opened.then(() => {
          this.vm.restoreQueue().then(() => {
            this.sync();
            this.consumeNotice();
          });
        });
        PrefStore.getInstance().getPinnedIds().then((ids: string[]) => {
          this.pinned = ids.indexOf(this.agentId) >= 0;
        });
        this.modelVm.hydrateFromCache();
        this.ensureFollowModelsLoaded(true);
        PrefStore.getInstance().getLastTools().then((raw: string) => {
          if (this.followUpMcp.length === 0) {
            const loaded = parseToolsPref(raw).mcp;
            const ready: McpServerDef[] = [];
            for (let i = 0; i < loaded.length; i++) {
              if (isMcpReady(loaded[i])) {
                ready.push(loaded[i]);
              }
            }
            this.followUpMcp = ready;
            this.vm.followUpMcp = ready;
          }
        });
      }
    })
    .onShown(() => {
      this.consumeNotice();
      this.vm.resumeIfNeeded().then(() => {
        this.sync();
      });
    })
    .onBackPressed(() => {
      try {
        this.getUIContext().getFocusController().clearFocus();
      } catch (_e) {
      }
      this.vm.detachView();
      return false;
    })
  }

  @Builder
  detailDock() {
    Column({ space: 8 }) {
      this.detailActionPill()
      ToastHost({ page: 'detail' })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 16, right: 16, bottom: Tokens.toastBottom })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  detailActionPill() {
    if (this.authFail()) {
      StatusPill({
        text: this.errorMsg.length > 0 ? this.errorMsg : 'API Key 失效，请重新粘贴',
        tone: 'danger',
        action: '去设置',
        onAction: () => {
          this.navStack.pushPath({ name: 'Settings' });
        }
      })
    } else if (this.needsPlanUpgrade) {
      StatusPill({
        text: '套餐不足，打开 Dashboard 升级',
        tone: 'warn',
        action: '升级',
        onAction: () => {
          this.openLink('https://cursor.com/dashboard');
        }
      })
    } else if (this.convError.length > 0) {
      StatusPill({
        text: this.convError,
        tone: 'warn',
        action: '重试',
        onAction: () => {
          this.vm.retryConversation().then(() => {
            this.sync();
          });
        }
      })
    } else if (this.failed() || this.errorMsg.length > 0) {
      StatusPill({
        text: this.errorMsg.length > 0 ? this.errorMsg : '失败',
        tone: 'danger',
        action: this.retryLabel(),
        onAction: () => {
          this.runRetry();
        }
      })
    } else if (this.streamFailNotice()) {
      StatusPill({
        text: this.streamNotice,
        tone: 'warn',
        action: this.retryLabel() === '重连' ? '重连' : '重试',
        onAction: () => {
          this.runRetry();
        }
      })
    } else if (!this.online) {
      StatusPill({
        text: '网络已断开',
        tone: 'warn',
        action: '重试',
        onAction: () => {
          this.runRetry();
        }
      })
    } else if (this.showJump) {
      StatusPill({
        text: '最新',
        onTap: () => {
          this.vm.stickToBottom = true;
          this.showJump = false;
          this.listScroller.scrollEdge(Edge.Bottom);
        }
      })
    } else if (this.unreadPill > 0 && this.unreadAnchorKey.length > 0 && !this.vm.stickToBottom) {
      StatusPill({
        text: `${this.unreadPill} 条新消息`,
        onTap: () => {
          this.vm.stickToBottom = false;
          this.scrollToKey(this.unreadAnchorKey);
          this.unreadPill = 0;
        }
      })
    }
  }

  @Builder
  timelinePane() {
    Column() {
      Stack() {
        List({ space: Tokens.sec, scroller: this.listScroller }) {
          LazyForEach(this.visibleSource, (item: TimelineItem) => {
            ListItem() {
              this.timelineItem(item)
            }
          }, (item: TimelineItem) => this.rowKey(item))
          if (this.processFoot().length > 0) {
            ListItem() {
              Text(this.processFoot())
                .fontSize(Tokens.typeCaption)
                .fontFamily(Tokens.fontUi)
                .fontColor($r('app.color.text_tertiary'))
                .padding({ top: 8, bottom: 4 })
                .onClick(() => {
                  if (this.processFootRetry()) {
                    this.runRetry();
                  }
                })
            }
          }
        }
        .width('100%')
        .height('100%')
        .padding({ left: this.pagePad, right: this.pagePad, bottom: Tokens.sec + 8 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(18)
        .focusable(true)
        .defaultFocus(false)
        .onScrollIndex((start: number, end: number) => {
          this.feedViewStart = start;
          this.feedViewEnd = end;
          const extra = this.processFoot().length > 0 ? 1 : 0;
          const nearBottom = this.feed.length === 0 || end >= this.feed.length + extra - 2;
          this.vm.stickToBottom = nearBottom;
          this.showJump = !nearBottom && this.runActive;
        })

          Column() {
            Blank()
              .layoutWeight(1)
              .hitTestBehavior(HitTestMode.Transparent)
            if (this.hasUserPrompts()) {
              Column({ space: 6 }) {
                if (this.showJumpHint) {
                  StatusPill({
                    text: `${this.jumpIndex} / ${this.jumpTotal}`
                  })
                }
                this.jumpCluster()
              }
              .alignItems(HorizontalAlign.End)
              .alignSelf(ItemAlign.End)
              .margin({ right: 12, bottom: 12 })
            }
          }
          .width('100%')
          .height('100%')
          .alignItems(HorizontalAlign.Center)
          .hitTestBehavior(HitTestMode.Transparent)
        }
        .layoutWeight(1)
        .width('100%')
        .height('100%')
        .onAreaChange((_old: Area, now: Area) => {
          const raw = now.height;
          const h = typeof raw === 'number' ? raw : 0;
          if (h > 0 && this.lastListH > 8 && h < this.lastListH - 12 && this.vm.stickToBottom) {
            this.pinFeedToComposer(20);
          }
          if (h > 0) {
            this.lastListH = h;
          }
          const rawW = now.width;
          const w = typeof rawW === 'number' ? rawW : 0;
          if (w > 80) {
            const next = Math.floor(w * 0.78);
            if (next !== this.bubbleMax) {
              this.bubbleMax = next;
            }
          }
        })
      }
      .layoutWeight(1)
      .width('100%')
  }

  @Builder
  jumpCluster() {
    Column() {
      this.jumpIcon('chevronUp', -1, '上一条提问')
      Divider()
        .color($r('app.color.separator'))
        .strokeWidth(1)
        .width(20)
      this.jumpIcon('chevronDown', 1, '下一条提问')
    }
    .backgroundColor($r('app.color.bg1'))
    .border({ width: 1, color: $r('app.color.border') })
    .borderRadius(Tokens.radiusMd)
    .clip(true)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  jumpIcon(name: string, dir: number, label: string) {
    Column() {
      HuIcon({
        name: name,
        iconSize: 18,
        tint: $r('app.color.text_secondary')
      })
    }
    .width(40)
    .height(40)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .opacity(this.pressKey === `jump:${dir}` ? 0.55 : 1)
    .animation({ duration: 160, curve: Curve.EaseOut })
    .accessibilityText(label)
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressKey = `jump:${dir}`;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressKey = '';
      }
    })
    .onClick(() => {
      Haptics.click();
      this.jumpUser(dir);
    })
  }

  @Builder
  composerPane() {
    if (this.followHints().length > 0) {
      Row({ space: 8 }) {
        ForEach(this.followHints(), (h: string) => {
          Text(h)
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor($r('app.color.bg2'))
            .borderRadius(Tokens.radiusPill)
            .onClick(() => {
              this.draft = h;
            })
        }, (h: string) => h)
      }
      .width('100%')
      .padding({ left: Tokens.pagePad, right: Tokens.pagePad, bottom: 4 })
    }

    PromptShell({
      follow: true,
      placeholder: '追问…',
      text: $draft,
      live: this.runActive,
      cancelling: this.cancelling,
      busy: this.sending,
      status: this.sending ? '发送中' : '',
      imageCount: this.attachedImages.length,
      imageUris: $imageUris,
      toolsOn: countMcp(this.followUpMcp) > 0,
      toolsLabel: this.followToolsLabel,
      followUpMode: this.followUpMode,
      modelLabel: this.followChipLabel.length > 0 ? this.followChipLabel : '自动',
      failedFollow: this.failedFollow,
      queued: this.queuedFollowUp,
      queueNote: this.queueImagesLost ? '图片未保存' : '',
      quoteText: this.quoteText,
      bottomPad: this.bottomInset,
      onFocusChange: (on: boolean) => {
        if (on) {
          this.pinFeedToComposer(40, true);
        }
      },
      onClearQuote: () => {
        this.quoteText = '';
      },
      onSend: async () => {
        const body = this.draft;
        const keptQuote = this.quoteText;
        const text = this.wrapQuote(body);
        const imgs = this.attachedImages;
        this.draft = '';
        this.quoteText = '';
        this.attachedImages = [];
        this.imageUris = [];
        this.sending = true;
        this.vm.followUpMcp = this.followUpMcp;
        const ok = await this.vm.followUp(text, imgs);
        if (!ok) {
          this.draft = body;
          this.quoteText = keptQuote;
          this.attachedImages = imgs;
          this.syncImageUris();
        } else {
          for (let i = 0; i < imgs.length; i++) {
            dropPreviewMap(previewSrc(imgs[i]));
          }
        }
        this.sync();
      },
      onCancel: async () => {
        await this.vm.cancelActive();
        this.sync();
      },
      onClearQueue: () => {
        this.vm.clearQueuedFollowUp();
        this.sync();
      },
      onEditQueue: () => {
        const text = this.vm.takeQueuedForEdit();
        if (text.length > 0) {
          this.draft = text;
        }
        this.sync();
      },
      onModeChange: (mode: string) => {
        this.vm.followUpMode = mode;
        this.followUpMode = mode;
      },
      onModel: () => {
        this.openSheet('model');
      },
      onRetryFollow: async () => {
        await this.vm.retryFailedFollowUp();
        this.sync();
      },
      onImage: async () => {
        await this.attachImages();
      },
      onRemoveImage: (idx: number) => {
        this.removeAttached(idx);
      },
      onTools: () => {
        this.openSheet('tools');
      }
    })
  }

  @Builder
  sheetBody() {
    if (this.sheetKind === 'artifacts') {
      this.artifactsSheet()
    } else if (this.sheetKind === 'usage') {
      this.usageSheet()
    } else if (this.sheetKind === 'tools') {
      this.followToolsSheet()
    } else if (this.sheetKind === 'model') {
      this.followModelSheet()
    } else if (this.sheetKind === 'rename') {
      this.renameSheet()
    } else {
      this.detailMenu()
    }
  }

  @Builder
  renameSheet() {
    Column({ space: 10 }) {
      Text('重命名')
        .fontSize(Tokens.typeHeadline)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      TextInput({ text: this.renameDraft, placeholder: '本地别名' })
        .fontSize(Tokens.typeCallout)
        .placeholderColor($r('app.color.text_placeholder'))
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.bg1'))
        .border({ width: 1, color: $r('app.color.border') })
        .borderRadius(Tokens.radiusField)
        .height(Tokens.touchMin)
        .width('100%')
        .onChange((v: string) => {
          this.renameDraft = v;
        })
      Text('只改本机显示，云端名称不变')
        .fontSize(Tokens.typeMicro)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
      Row({ space: 12 }) {
        Text('取消')
          .fontSize(Tokens.typeCallout)
          .fontColor($r('app.color.text_secondary'))
          .constraintSize({ minHeight: Tokens.touchMin })
          .onClick(() => {
            this.closeSheet();
          })
        Text('保存')
          .fontSize(Tokens.typeCallout)
          .fontColor($r('app.color.accent'))
          .constraintSize({ minHeight: Tokens.touchMin })
          .onClick(async () => {
            await PrefStore.getInstance().setAlias(this.agentId, this.renameDraft);
            this.vm.applyAlias(PrefStore.getInstance().displayName(this.agentId, this.renameDraft));
            this.name = this.vm.name;
            this.closeSheet();
            Haptics.success();
            showToast('已保存本地名称', 'info', 'detail');
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .padding({
      left: Tokens.sheetPadH,
      right: Tokens.sheetPadH,
      top: Tokens.sheetPadTop,
      bottom: Tokens.sheetPadBottom
    })
    .width('100%')
  }

  @Builder
  followModelSheet() {
    Column({ space: Tokens.sheetGap }) {
      Text('本轮模型')
        .fontSize(Tokens.typeHeadline)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text('这一轮用的模型和参数。')
        .fontSize(Tokens.typeCaption)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
      if (this.followModelsLoading && this.followModelGroups.length === 0) {
        Text('正在加载模型…')
          .fontSize(Tokens.typeCallout)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ top: 12, bottom: 12 })
      } else if (this.followModelGroups.length === 0) {
        Column({ space: 8 }) {
          Text(this.followModelsError.length > 0 ? this.followModelsError : '模型列表还没加载出来。')
            .fontSize(Tokens.typeCallout)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Text('重新加载')
            .fontSize(Tokens.typeCallout)
            .fontColor($r('app.color.text_link'))
            .onClick(() => {
              Haptics.click();
              this.ensureFollowModelsLoaded(true);
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 8, bottom: 8 })
      }
      Scroll() {
        ModelPicker({
          selectedModel: this.followUpModel,
          selectedVariantIndex: this.followVariantIndex,
          groups: this.followModelGroups,
          variantOptions: this.followVariantOptions,
          variantTitle: this.followVariantTitle,
          paramRows: this.followParamRows,
          paramStamp: this.followParamStamp,
          allowAuto: true,
          onPick: (id: string) => {
            this.pickFollowModel(id);
          },
          onPickParam: (rowId: string, valueIdx: number) => {
            this.pickFollowParam(rowId, valueIdx);
          },
          onPickVariant: (idx: number) => {
            this.followVariantIndex = idx;
            this.modelVm.selectedVariantIndex = idx;
            if (idx >= 0 && idx < this.followVariantOptions.length) {
              this.followVariant = this.followVariantOptions[idx];
              this.modelVm.selectedVariant = this.followVariant;
            }
            const payload = this.modelVm.modelPayload();
            this.vm.followUpParams = payload && payload['params'] ? payload['params'] as Object[] : [];
            this.refreshFollowChip();
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .padding({
      left: Tokens.sheetPadH,
      right: Tokens.sheetPadH,
      top: Tokens.sheetPadTop,
      bottom: Tokens.sheetPadBottom
    })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.bg0'))
  }

  @Builder
  followToolsSheet() {
    Column({ space: Tokens.sheetGap }) {
      Text('本轮 MCP')
        .fontSize(Tokens.typeHeadline)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text('空着则沿用创建时的配置。')
        .fontSize(Tokens.typeCaption)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
      McpListEditor({ servers: $followUpMcp })
    }
    .width('100%')
    .padding({
      left: Tokens.sheetPadH,
      right: Tokens.sheetPadH,
      top: Tokens.sheetPadTop,
      bottom: Tokens.sheetPadBottom
    })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.bg0'))
    .onDisAppear(() => {
      this.vm.followUpMcp = this.followUpMcp;
    })
  }

  @Builder
  usageSheet() {
    Column({ space: Tokens.sheetGap }) {
      Text('用量明细')
        .fontSize(Tokens.typeHeadline)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ bottom: 4 })

      if (this.usageRuns.length === 0) {
        Text('暂无用量数据')
          .fontSize(14)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .padding({ top: 24, bottom: 24 })
          .textAlign(TextAlign.Center)
      } else {
        List({ space: 6 }) {
          ForEach(this.usageRuns, (r: RunUsage, idx: number) => {
            ListItem() {
              Row({ space: 8 }) {
                Text(r.id === this.vm.activeRunId ? '本轮' : `#${this.usageRuns.length - idx}`)
                  .fontSize(13)
                  .fontColor($r('app.color.text_tertiary'))
                  .width(36)
                Column({ space: 2 }) {
                  Text(`输入 ${fmtTk(r.usage.inputTokens)} · 输出 ${fmtTk(r.usage.outputTokens)}`)
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                  Text(`合计 ${fmtTk(r.usage.totalTokens)} · 缓存读 ${fmtTk(r.usage.cacheReadTokens)}`)
                    .fontSize(12)
                    .fontColor($r('app.color.text_tertiary'))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .backgroundColor($r('app.color.bg2'))
              .borderRadius(Tokens.radiusMd)
            }
          }, (r: RunUsage, idx: number) => `${r.id}-${idx}`)
        }
      }
    }
    .width('100%')
    .padding({
      left: Tokens.sheetPadH,
      right: Tokens.sheetPadH,
      top: Tokens.sheetPadTop,
      bottom: Tokens.sheetPadBottom
    })
  }

  @Builder
  artifactsSheet() {
    Column({ space: Tokens.sheetGap }) {
      Text('产物')
        .fontSize(Tokens.typeHeadline)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ bottom: 4 })

      if (this.artifacts.length === 0) {
        Text('暂无产物')
          .fontSize(14)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .padding({ top: 24, bottom: 24 })
          .textAlign(TextAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.artifacts, (a: ArtifactInfo) => {
            ListItem() {
              ArtifactRow({
                item: a,
                resolveUrl: async (path: string): Promise<string> => {
                  return await this.vm.openArtifact(path);
                },
                onOpen: (url: string, title: string) => {
                  this.closeSheet();
                  this.openLink(url, title);
                },
                onFail: (msg: string) => {
                  this.closeSheet();
                  showToast(msg, 'warn', 'detail');
                }
              })
            }
          }, (a: ArtifactInfo) => a.path)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
    }
    .padding({
      left: Tokens.sheetPadH,
      right: Tokens.sheetPadH,
      top: Tokens.sheetPadTop,
      bottom: Tokens.sheetPadBottom
    })
    .width('100%')
    .height('100%')
  }

  @Builder
  detailMenu() {
    Scroll() {
      Column({ space: Tokens.sheetGap }) {
        Text('会话')
          .fontSize(Tokens.typeHeadline)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')

        Column({ space: 2 }) {
          this.menuFact('状态', this.menuStatusLine())
          if (this.shortRepo().length > 0) {
            this.menuFact('仓库', this.shortRepo())
          }
          if (this.vm.envLabel.length > 0) {
            this.menuFact('环境', this.vm.envLabel)
          }
          if (this.firstBranch().length > 0) {
            this.menuFact('分支', this.firstBranch())
          }
          if (this.currentFile().length > 0) {
            this.menuFact('文件', this.currentFile())
          }
          if (this.usageLabel.length > 0) {
            this.menuFact('用量', this.usageLabel)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .backgroundColor($r('app.color.bg2'))
        .borderRadius(Tokens.radiusCard)

        Text('查看')
          .fontSize(Tokens.typeCaption)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
        Column() {
          SheetActionRow({
            label: 'MCP',
            hint: countMcp(this.followUpMcp) > 0 ? this.followToolsLabel : '未配置',
            trailing: 'chevron',
            last: this.artifacts.length === 0 && this.usageRuns.length === 0,
            onTap: () => {
              this.sheetKind = 'tools';
            }
          })
          if (this.artifacts.length > 0) {
            SheetActionRow({
              label: '产物',
              hint: `${this.artifacts.length} 个文件`,
              trailing: 'chevron',
              last: this.usageRuns.length === 0,
              onTap: () => {
                this.sheetKind = 'artifacts';
              }
            })
          }
          if (this.usageRuns.length > 0) {
            SheetActionRow({
              label: '用量',
              hint: this.usageLabel,
              trailing: 'chevron',
              last: true,
              onTap: () => {
                this.sheetKind = 'usage';
              }
            })
          }
        }
        .width('100%')
        .backgroundColor($r('app.color.bg2'))
        .borderRadius(Tokens.radiusCard)
        .clip(true)

        Text('操作')
          .fontSize(Tokens.typeCaption)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
        Column() {
          if (this.prLabel().length > 0) {
            SheetActionRow({
              label: this.prLabel(),
              trailing: 'external',
              onTap: () => {
                this.closeSheet();
                this.openLink(this.firstPr(), 'Pull Request');
              }
            })
          }
          if (this.compareUrl.length > 0) {
            SheetActionRow({
              label: '改动',
              hint: '对比分支',
              trailing: 'external',
              onTap: () => {
                this.closeSheet();
                this.openLink(this.compareUrl, '改动');
              }
            })
          }
          if (this.firstBranch().length > 0) {
            SheetActionRow({
              label: '复制分支',
              hint: this.firstBranch(),
              onTap: () => {
                this.closeSheet();
                this.copyText(this.firstBranch());
              }
            })
          }
          SheetActionRow({
            label: '分享',
            onTap: async () => {
              this.closeSheet();
              const pr = this.vm.branches.length > 0 ? (this.vm.branches[0].prUrl ?? '') : '';
              const branch = this.vm.branches.length > 0 ? (this.vm.branches[0].branch ?? '') : '';
              const ctx = getContext(this) as common.UIAbilityContext;
              await shareAgentLinks(ctx, this.name, this.url, pr, branch);
            }
          })
          SheetActionRow({
            label: '系统浏览器打开',
            trailing: 'external',
            last: true,
            onTap: () => {
              this.closeSheet();
              const ctx = getContext(this) as common.UIAbilityContext;
              const link = this.url.length > 0 ? this.url : WebLinks.agentPage(this.agentId);
              ctx.openLink(link).catch(() => {
              });
            }
          })
        }
        .width('100%')
        .backgroundColor($r('app.color.bg2'))
        .borderRadius(Tokens.radiusCard)
        .clip(true)

        Column() {
          SheetActionRow({
            label: this.pinned ? '取消置顶' : '置顶',
            onTap: async () => {
              const wasPinned = this.pinned;
              await this.togglePin();
              this.closeSheet();
              Haptics.success();
              showToast(wasPinned ? '已取消置顶' : '已置顶', 'info', 'detail');
            }
          })
          SheetActionRow({
            label: '重命名',
            hint: '本机别名',
            trailing: 'chevron',
            last: true,
            onTap: () => {
              this.renameDraft = this.name;
              this.sheetKind = 'rename';
            }
          })
        }
        .width('100%')
        .backgroundColor($r('app.color.bg2'))
        .borderRadius(Tokens.radiusCard)
        .clip(true)

        Column() {
          if (this.status === 'ARCHIVED') {
            SheetActionRow({
              label: '取消归档',
              onTap: async () => {
                const ok = await this.vm.unarchive();
                this.closeSheet();
                this.sync();
                if (ok) {
                  Haptics.success();
                  InboxVM.getInstance().refresh(true);
                } else {
                  Haptics.fail();
                }
              }
            })
          } else {
            SheetActionRow({
              label: '归档',
              hint: '从 Inbox 收起',
              onTap: async () => {
                const ok = await this.vm.archive();
                this.closeSheet();
                if (ok) {
                  Haptics.success();
                  showToast('已归档', 'info', 'inbox');
                  this.vm.close();
                  this.navStack.pop();
                } else {
                  this.sync();
                }
              }
            })
          }
          SheetActionRow({
            label: '永久删除',
            hint: '无法从 Inbox 恢复',
            danger: true,
            last: true,
            onTap: () => {
              const id = this.agentId;
              this.closeSheet();
              confirmDanger('永久删除', '删除后无法从 Inbox 恢复此任务。', '删除', () => {
                this.vm.deleteRemote().then((ok: boolean) => {
                  if (ok) {
                    Haptics.success();
                    showToast('已删除', 'info', 'inbox');
                    InboxVM.getInstance().removeLocal(id);
                    this.vm.close();
                    this.navStack.pop();
                  } else {
                    Haptics.fail();
                    this.sync();
                  }
                });
              });
            }
          })
        }
        .width('100%')
        .backgroundColor($r('app.color.bg2'))
        .borderRadius(Tokens.radiusCard)
        .clip(true)
      }
      .width('100%')
      .padding({
        left: Tokens.sheetPadH,
        right: Tokens.sheetPadH,
        top: Tokens.sheetPadTop,
        bottom: Tokens.sheetPadBottom
      })
    }
    .width('100%')
    .constraintSize({ maxHeight: 560 })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  menuFact(label: string, value: string) {
    Row({ space: 10 }) {
      Text(label)
        .fontSize(Tokens.typeCaption)
        .fontColor($r('app.color.text_tertiary'))
        .width(36)
      Text(value)
        .fontSize(Tokens.typeCaption)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ minWidth: 0 })
    }
    .width('100%')
    .constraintSize({ minHeight: 28 })
    .alignItems(VerticalAlign.Center)
  }

  private activityTitle(item: TimelineItem): string {
    if (item.kind === 'step') {
      const title = meaningfulStepTitle(item.text ?? '');
      if (this.runActive && item.streaming === true) {
        return title.length > 0 ? title : '在想下一步';
      }
      return title.length > 0 ? title : '过程';
    }
    const tools = this.toolsForRun(item.runId);
    const elapsed = this.elapsedForCard(item.runId, item.streaming === true && this.runActive);
    if (item.streaming === true && this.runActive) {
      return processLiveTitle(false, this.liveToolSlug(tools), tools.length > 0, elapsed);
    }
    return processDoneTitle(tools.length > 0 || item.kind !== 'thinking', elapsed);
  }

  private rowKey(item: TimelineItem): string {
    return item.key;
  }

  private isProcessKind(kind: string): boolean {
    return kind === 'thinking' || kind === 'progress' || kind === 'step';
  }

  private isLeadProcess(item: TimelineItem): boolean {
    const total = this.vm.source.totalCount();
    for (let i = 0; i < total; i++) {
      const it = this.vm.source.getData(i);
      if (it.runId === item.runId && this.isProcessKind(it.kind)) {
        return it.key === item.key;
      }
    }
    return true;
  }

  private isWaitingRow(item: TimelineItem): boolean {
    if (!isWaitingThink(item, this.toolsForRun(item.runId).length > 0)) {
      return false;
    }
    if (this.toolsForRun(item.runId).length > 0 && this.isLeadProcess(item)) {
      return false;
    }
    return this.processBodyForRun(item.runId).trim().length === 0 ||
      (item.key.indexOf('waiting-') === 0);
  }

  private waitingLine(): string {
    const _t = this.tick;
    return waitingThinkLabel(this.tick);
  }

  private processBodyForRun(runId: string): string {
    const bits: string[] = [];
    const total = this.vm.source.totalCount();
    for (let i = 0; i < total; i++) {
      const it = this.vm.source.getData(i);
      if (it.runId !== runId || !this.isProcessKind(it.kind) || it.kind === 'step') {
        continue;
      }
      const t = (it.text ?? '').trim();
      if (t.length === 0 || isOpaqueStepLabel(t)) {
        continue;
      }
      bits.push(t);
    }
    return bits.join('\n\n');
  }

  private toolsForRun(runId: string): TimelineItem[] {
    const out: TimelineItem[] = [];
    const total = this.vm.source.totalCount();
    for (let i = 0; i < total; i++) {
      const it = this.vm.source.getData(i);
      if (it.runId === runId && it.kind === 'tool') {
        out.push(it);
      }
    }
    return out;
  }

  private isPlainUser(text: string): boolean {
    if (text.length === 0 || text.length >= 80) {
      return false;
    }
    return text.indexOf('\n') < 0 && text.indexOf('```') < 0;
  }

  private modelTagsOf(item: TimelineItem): string[] {
    const tags: string[] = [];
    if (item.sentTags && item.sentTags.length > 0) {
      for (let i = 0; i < item.sentTags.length; i++) {
        tags.push(item.sentTags[i]);
      }
    } else {
      const s = (item.usageShort ?? '').trim();
      if (s.length === 0 || this.isTokenShort(s)) {
        return [];
      }
      const bits = s.split(' · ');
      for (let i = 0; i < bits.length; i++) {
        if (bits[i].trim().length > 0) {
          tags.push(bits[i].trim());
        }
      }
    }
    if (tags.length <= 1) {
      return tags;
    }
    return [tags.join(' · ')];
  }

  private isTokenShort(s: string): boolean {
    if (s.length === 0) {
      return true;
    }
    const last = s.charAt(s.length - 1);
    if (last === 'k' || last === 'K') {
      return true;
    }
    for (let i = 0; i < s.length; i++) {
      const c = s.charAt(i);
      if (c !== '.' && (c < '0' || c > '9')) {
        return false;
      }
    }
    return true;
  }

  private tokenLineOf(item: TimelineItem): string {
    const s = item.usageShort ?? '';
    if (s.length === 0) {
      return '';
    }
    const tags = this.modelTagsOf(item);
    if (tags.length > 0 && s === tags.join(' · ')) {
      return '';
    }
    if (s.indexOf(' · ') >= 0) {
      return '';
    }
    return s;
  }

  private bubbleInner(): number {
    return this.bubbleMax > 48 ? this.bubbleMax - 24 : this.bubbleMax;
  }

  private bubbleTime(item: TimelineItem): string {
    return relativeTime(item.localAt ?? '');
  }

  private showableImages(item: TimelineItem): string[] {
    const src = item.imageUrls ?? [];
    const out: string[] = [];
    for (let i = 0; i < src.length; i++) {
      if (isShowableImageUrl(src[i])) {
        out.push(src[i]);
      }
    }
    return out;
  }

  @Builder
  bubbleImages(item: TimelineItem) {
    ForEach(this.showableImages(item), (src: string) => {
      Image(src)
        .width('100%')
        .constraintSize({ maxWidth: this.bubbleMax, maxHeight: 180 })
        .objectFit(ImageFit.Cover)
        .borderRadius(Tokens.radiusSm)
    }, (src: string) => src)
  }

  @Builder
  tagRow(tags: string[]) {
    Row({ space: 4 }) {
      ForEach(tags, (t: string) => {
        Text(t)
          .fontSize(Tokens.typeMicro)
          .fontColor($r('app.color.text_tertiary'))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor($r('app.color.bg2'))
          .border({ width: 1, color: $r('app.color.border') })
          .borderRadius(Tokens.radiusChip)
      }, (t: string) => t)
    }
    .constraintSize({ maxWidth: this.bubbleMax })
    .padding({ top: 2 })
  }

  @Builder
  timelineItem(item: TimelineItem) {
    if (item.kind === 'userPrompt') {
      Column({ space: 4 }) {
        Row() {
          Blank()
            .layoutWeight(1)
          Column({ space: 4 }) {
            Row() {
              if (this.isPlainUser(item.text ?? '')) {
                Text(item.text ?? '')
                  .fontSize(Tokens.typeProse)
                  .fontFamily(Tokens.fontUi)
                  .fontColor($r('app.color.text_primary'))
                  .lineHeight(Tokens.typeProse + 4)
                  .maxLines(6)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .wordBreak(WordBreak.BREAK_WORD)
                  .focusable(true)
                  .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
                  .constraintSize({ maxWidth: this.bubbleInner() })
                  .copyOption(CopyOptions.LocalDevice)
                  .editMenuOptions(makeQuoteEditMenu(item.text ?? '', (t: string) => {
                    this.applyQuote(t);
                  }))
              } else {
                MarkdownLite({
                  content: item.text ?? '',
                  compact: false,
                  inBubble: true,
                  capWidth: this.bubbleInner(),
                  onQuote: (t: string) => {
                    this.applyQuote(t);
                  }
                })
              }
            }
            .alignItems(VerticalAlign.Center)
            .constraintSize({ maxWidth: this.bubbleMax })
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(item.failed ? $r('app.color.banner_error_bg') : $r('app.color.user_bubble'))
            .border({
              width: item.failed ? 0 : 1,
              color: $r('app.color.border')
            })
            .borderRadius(Tokens.radiusMd)
            this.bubbleImages(item)
            if (this.bubbleTime(item).length > 0) {
              Text(this.bubbleTime(item))
                .fontSize(Tokens.typeMicro)
                .fontFamily(Tokens.fontUi)
                .fontColor($r('app.color.text_tertiary'))
            }
            if (this.modelTagsOf(item).length > 0) {
              this.tagRow(this.modelTagsOf(item))
            }
            if (this.tokenLineOf(item).length > 0) {
              Text(this.tokenLineOf(item))
                .fontSize(Tokens.typeMicro)
                .fontFamily(Tokens.fontUi)
                .fontColor($r('app.color.text_tertiary'))
            }
          }
          .constraintSize({ maxWidth: this.bubbleMax })
          .alignItems(HorizontalAlign.Start)
          .alignSelf(ItemAlign.End)
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .focusable(true)
      }
      .width('100%')
      .alignItems(HorizontalAlign.End)
      .focusable(true)
    } else if (item.kind === 'runHeader') {
      Row({ space: 8 }) {
        Text(runHeaderVerb(item.statusLabel ?? '', this.elapsedForCard(item.runId, false)))
          .fontSize(Tokens.typeMicro)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .padding({ top: 10, bottom: 2 })
      .alignItems(VerticalAlign.Center)
      .transition(chromeTransition())
    } else if (item.kind === 'thinking' || item.kind === 'progress' || item.kind === 'step') {
      if (this.isWaitingRow(item)) {
        Text(this.waitingLine())
          .fontSize(Tokens.typeCaption)
          .fontFamily(Tokens.fontUi)
          .fontColor($r('app.color.text_tertiary'))
          .opacity(shimmerOpacity(this.shimmerOn))
          .padding({ top: 8, bottom: 4 })
      } else if (this.isLeadProcess(item)) {
        ActivityCard({
          item: item,
          runActive: this.runActive,
          shimmerOn: this.shimmerOn,
          title: this.cardProcessTitle(item),
          body: this.processBodyForRun(item.runId),
          tools: this.toolsForRun(item.runId),
          onToggle: () => {
            Haptics.tick();
            this.vm.toggleCollapsed(item.key);
          },
          onToggleTool: (key: string) => {
            Haptics.tick();
            this.vm.toggleCollapsed(key);
          }
        })
      } else {
        Column().width('100%').height(0)
      }
    } else if (item.kind === 'assistant') {
      Column({ space: 4 }) {
        if (item.streaming === true && !this.mdSettled) {
          Text(item.text ?? '')
            .fontSize(Tokens.typeProse)
            .fontFamily(Tokens.fontUi)
            .fontColor($r('app.color.text_primary'))
            .lineHeight(Tokens.lineProse)
            .textAlign(TextAlign.Start)
            .wordBreak(WordBreak.BREAK_WORD)
            .focusable(true)
            .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
            .copyOption(CopyOptions.LocalDevice)
            .editMenuOptions(makeQuoteEditMenu(item.text ?? '', (t: string) => {
              this.applyQuote(t);
            }))
            .width('100%')
        } else {
          MarkdownLite({
            content: item.text ?? '',
            compact: this.isShortMsg(item.text ?? ''),
            onQuote: (t: string) => {
              this.applyQuote(t);
            }
          })
        }
        this.bubbleImages(item)
        if (this.bubbleTime(item).length > 0) {
          Text(this.bubbleTime(item))
            .fontSize(Tokens.typeMicro)
            .fontFamily(Tokens.fontUi)
            .fontColor($r('app.color.text_tertiary'))
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 2, bottom: 6 })
      .focusable(true)
    } else if (item.kind === 'tool') {
      Column().width('100%').height(0)
    } else if (item.kind === 'runOutcome') {
      this.outcomeRow(item)
    } else {
      Text(item.text ?? '')
        .fontSize(Tokens.typeMicro)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 2, bottom: 2 })
    }
  }

  private shouldSkipOutcome(item: TimelineItem): boolean {
    const body = (item.text ?? '').trim();
    if (body.length === 0) {
      return true;
    }
    if (body === this.resultText && this.resultText.length > 0) {
      return true;
    }
    if (body.indexOf('状态：') === 0) {
      return true;
    }
    const st = `${item.statusLabel ?? ''}`;
    if (st === 'FINISHED' && (body === '已完成' || body === '运行 · 已完成')) {
      return true;
    }
    return false;
  }

  @Builder
  outcomeRow(item: TimelineItem) {
    if (this.shouldSkipOutcome(item)) {
      Column().width('100%').height(0)
    } else {
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          HuIcon({
            name: this.outcomeIconName(item.statusLabel ?? ''),
            iconSize: 16,
            tint: this.outcomeTone(item.statusLabel ?? '')
          })
          Text(this.statusZh(item.statusLabel ?? ''))
            .fontSize(Tokens.typeMicro)
            .fontFamily(Tokens.fontUi)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.outcomeTone(item.statusLabel ?? ''))
        }
        .width('100%')
        if ((item.text ?? '').length > 0) {
          Text(item.text ?? '')
            .fontSize(Tokens.typeCallout)
            .fontFamily(Tokens.fontUi)
            .fontColor($r('app.color.text_secondary'))
            .lineHeight(Tokens.lineCaption)
            .width('100%')
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r('app.color.bg2'))
      .borderRadius(Tokens.radiusMd)
    }
  }

  private outcomeIconName(label: string): string {
    if (label === 'FINISHED') {
      return 'check';
    }
    if (label === 'ERROR' || label === 'EXPIRED' || label === 'CANCELLED') {
      return 'close';
    }
    if (label === 'RUNNING' || label === 'CREATING') {
      return 'refresh';
    }
    return 'more';
  }

  private outcomeTone(label: string): Resource {
    if (label === 'FINISHED') {
      return $r('app.color.ok');
    }
    if (label === 'ERROR' || label === 'EXPIRED') {
      return $r('app.color.err');
    }
    if (label === 'CANCELLED') {
      return $r('app.color.warn');
    }
    if (label === 'RUNNING' || label === 'CREATING') {
      return $r('app.color.accent');
    }
    return $r('app.color.text_tertiary');
  }
}
