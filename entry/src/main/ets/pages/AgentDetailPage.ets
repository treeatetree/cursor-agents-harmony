import { common } from '@kit.AbilityKit';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { DetailVM } from '../viewmodels/DetailVM';
import { TimelineItem } from '../models/Timeline';
import { ArtifactInfo, CustomSubagentDef, EnvVarDef, McpServerDef, RunUsage } from '../models/Api';
import { NewAgentVM } from '../viewmodels/NewAgentVM';
import { ModelPicker } from '../components/ModelPicker';
import { StatusBanner } from '../components/StatusBanner';
import {
  buildParamRows, groupModels, ModelParamRow, ModelVendorGroup, rowsToParams,
  shortModelName, variantLabel, variantSectionTitle
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
import { chromeTransition, shimmerMs, shimmerOpacity } from '../utils/Motion';
import { WebLinks, pushInAppBrowser } from '../utils/WebLinks';
import { ArtifactRow } from '../components/ArtifactRow';
import { McpListEditor } from '../components/CapabilityEditors';
import { countMcp, isMcpReady, parseToolsPref, toolsChipLabel, defaultEnv } from '../utils/AgentCapabilities';
import { PrefStore } from '../store/PrefStore';
import { UnreadStore } from '../store/UnreadStore';
import { HuIcon } from '../components/HuIcon';
import { HuIconButton } from '../components/HuIconButton';
import { dropPreviewMap, maxPromptImages, pickPromptImages, previewSrc, PromptImage } from '../utils/ImagePicker';
import { copyToClipboard } from '../utils/Clipboard';
import { confirmDanger } from '../utils/AppDialog';
import { showToast } from '../utils/AppToast';
import { Haptics } from '../utils/Haptics';
import { visibleTimeline } from '../utils/TimelineView';
import { processDoneTitle, processLiveTitle, runHeaderVerb, toolSlug } from '../utils/TimelineCopy';

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
  private vm: DetailVM = new DetailVM();
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
  @State copyHint: string = '';
  @State topInset: number = 0;
  @State bottomInset: number = 0;
  @State queuedFollowUp: string = '';
  @State feed: TimelineItem[] = [];
  @State followUpMode: string = 'agent';
  @State followModelLabel: string = '沿用';
  @State followUpModel: string = '';
  @State followVariantIndex: number = -1;
  @State followVariant: string = '';
  @State followModelGroups: ModelVendorGroup[] = [];
  @State followVariantOptions: string[] = [];
  @State followVariantTitle: string = '模式';
  @State followParamRows: ModelParamRow[] = [];
  @State failedFollow: boolean = false;
  @State compareUrl: string = '';
  @State pinned: boolean = false;
  @State attachedImages: PromptImage[] = [];
  @State imageUris: string[] = [];
  @State followUpMcp: McpServerDef[] = [];
  @State followToolsLabel: string = '能力';
  @State mdSettled: boolean = true;
  @State syncing: boolean = false;
  @State isHover: boolean = false;
  private tickTimer: number = -1;
  private mdTimer: number = -1;
  private runStartMs: number = 0;
  private lastKb: number = 0;
  private lastListH: number = 0;
  private pinTimer: number = -1;
  private followSig: string = '';

  aboutToDisappear(): void {
    this.clearTick();
    if (this.mdTimer >= 0) {
      clearTimeout(this.mdTimer);
      this.mdTimer = -1;
    }
    if (this.pinTimer >= 0) {
      clearTimeout(this.pinTimer);
      this.pinTimer = -1;
    }
    this.vm.close();
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
    }
    this.name = this.vm.name;
    this.status = this.vm.status;
    this.runStatus = this.vm.runStatus;
    this.url = this.vm.url;
    this.loading = this.vm.loading;
    this.syncing = this.vm.syncing;
    this.errorMsg = this.vm.errorMsg;
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
    }
  }

  private feedFollowSig(): string {
    const last = this.feed.length > 0 ? this.feed[this.feed.length - 1].key : '';
    return `${this.runActive ? 1 : 0}:${this.feed.length}:${last}:${this.queuedFollowUp.length}`;
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
    this.feed = next;
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
    if (!link) {
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
      this.copyHint = '最多 5 张图';
      setTimeout(() => {
        this.copyHint = '';
      }, 2000);
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
      this.copyHint = '选图取消或失败';
      setTimeout(() => {
        this.copyHint = '';
      }, 2000);
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
  }

  private closeSheet(): void {
    this.showSheet = false;
  }

  private armTick(): void {
    if (this.runActive) {
      if (this.runStartMs === 0) {
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

  private showStreamNotice(): boolean {
    const n = this.streamNotice;
    if (n.length === 0) {
      return false;
    }
    if (n === '结束后发送' || n.indexOf('结束后') >= 0 || n.indexOf('稍后自动') >= 0) {
      return false;
    }
    return true;
  }

  private streamBusy(): boolean {
    const n = this.streamNotice;
    return n.indexOf('连接') >= 0 || n.indexOf('重连') >= 0 || n.indexOf('过期') >= 0 ||
      n.indexOf('提交') >= 0;
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
    this.followModelGroups = groupModels(this.modelVm.models);
    this.refreshFollowModelMeta();
  }

  private followModelLabelText(): string {
    if (this.followUpModel.length === 0) {
      return '沿用';
    }
    return shortModelName(this.followModelLabel.length > 0 ? this.followModelLabel : this.followUpModel);
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
  }

  private refreshFollowModelMeta(): void {
    this.followVariantOptions = [];
    this.followVariantTitle = '模式';
    this.followParamRows = [];
    this.followModelLabel = '沿用';
    if (this.followUpModel.length === 0) {
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
        this.followParamRows = rows;
        this.modelVm.selectedParams = rowsToParams(rows);
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
      return;
    }
    this.followModelLabel = this.followUpModel;
  }

  private pickFollowParam(rowIdx: number, valueIdx: number): void {
    const next: ModelParamRow[] = [];
    for (let i = 0; i < this.followParamRows.length; i++) {
      const r = this.followParamRows[i];
      next.push({
        id: r.id,
        title: r.title,
        labels: r.labels,
        values: r.values,
        selected: i === rowIdx ? valueIdx : r.selected
      });
    }
    this.followParamRows = next;
    this.modelVm.selectedParams = rowsToParams(next);
    const payload = this.modelVm.modelPayload();
    this.vm.followUpParams = payload && payload['params'] ? payload['params'] as Object[] : [];
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

  private isFollowUpUser(item: TimelineItem): boolean {
    let seen = 0;
    for (let i = 0; i < this.feed.length; i++) {
      if (this.feed[i].kind !== 'userPrompt') {
        continue;
      }
      if (this.feed[i].key === item.key) {
        return seen > 0;
      }
      seen += 1;
    }
    return false;
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
    const live = item.streaming === true && this.runActive;
    const tools = this.toolsForRun(item.runId);
    const elapsed = this.elapsedForCard(item.runId, live);
    if (!live) {
      return processDoneTitle(tools.length > 0, elapsed);
    }
    const connecting = item.runId === 'pending' || (item.text ?? '').trim().length === 0;
    return processLiveTitle(connecting, this.liveToolSlug(tools), tools.length > 0, elapsed);
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
        this.copyHint = '已复制';
        showToast('已复制');
      } else {
        this.copyHint = text.length > 48 ? `${text.substring(0, 48)}…` : text;
        showToast(this.copyHint);
      }
      setTimeout(() => {
        this.copyHint = '';
      }, 2500);
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
                this.vm.close();
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

        if (this.noticeLine.length > 0) {
          StatusBanner({
            text: this.noticeLine,
            tone: 'info',
            action: '知道了',
            onAction: () => {
              this.dismissNotice();
            }
          })
        }

        if (this.showStreamNotice()) {
          StatusBanner({
            text: this.streamNotice,
            tone: 'info',
            action: this.retryLabel() === '重连' ? '重连' : '',
            onAction: () => {
              this.runRetry();
            }
          })
        }

        if (this.needsPlanUpgrade) {
          StatusBanner({
            text: '套餐不足，打开 Dashboard 升级',
            tone: 'warn',
            action: '升级',
            onAction: () => {
              this.openLink('https://cursor.com/dashboard');
            }
          })
        }

        if (this.failed() || this.errorMsg.length > 0) {
          StatusBanner({
            text: this.errorMsg.length > 0 ? this.errorMsg : '失败',
            tone: 'danger',
            action: this.authFail() ? '去设置' : this.retryLabel(),
            onAction: () => {
              if (this.authFail()) {
                this.navStack.pushPath({ name: 'Settings' });
              } else {
                this.runRetry();
              }
            }
          })
        }

        if (this.copyHint.length > 0) {
          Text(this.copyHint)
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.ok'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ bottom: 4 })
        }

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
      .backgroundColor($r('app.color.bg0'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    }
    .hideTitleBar(true)
    .bindSheet($$this.showSheet, this.sheetBody(), {
      height: this.sheetKind === 'artifacts' || this.sheetKind === 'model' ? SheetSize.MEDIUM :
        SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('app.color.overlay')
    })
    .backgroundColor($r('app.color.bg0'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    .onReady((ctx: NavDestinationContext) => {
      try {
        this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
      } catch (_e) {
      }
      this.pagePad = this.bp.pagePad();
      this.topInset = this.bp.safeTop();
      this.bottomInset = this.bp.composerBottom();
      this.isHover = this.bp.isHover;
      this.bp.onChange(() => {
        this.pagePad = this.bp.pagePad();
        this.topInset = this.bp.safeTop();
        this.bottomInset = this.bp.composerBottom();
        this.isHover = this.bp.isHover;
        this.onKeyboardChrome();
      });
      const p = ctx.pathInfo.param as Record<string, Object>;
      if (p && p['agentId']) {
        this.agentId = `${p['agentId']}`;
        this.vm.setUiListener(() => {
          this.sync();
        });
        const seeded = `${p['seed'] ?? ''}` === '1' || this.agentId.indexOf('local-') === 0;
        const opened = seeded ? this.vm.openFromCreate(this.agentId) : this.vm.open(this.agentId);
        opened.then(() => {
          this.vm.restoreQueue().then(() => {
            this.sync();
            this.consumeNotice();
          });
        });
        UnreadStore.getInstance().markSeen(this.agentId).catch(() => {
        });
        PrefStore.getInstance().getPinnedIds().then((ids: string[]) => {
          this.pinned = ids.indexOf(this.agentId) >= 0;
        });
        this.modelVm.hydrateFromCache();
        this.syncFollowModels();
        this.modelVm.loadMeta(false).then(() => {
          this.syncFollowModels();
        });
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
      this.vm.close();
      return false;
    })
  }

  @Builder
  timelinePane() {
    if (this.loading && this.vm.source.totalCount() === 0) {
      Column() {
        LoadingProgress().width(32).height(32).color($r('app.color.accent'))
        Text('加载对话…')
          .fontSize(Tokens.typeCaption)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 12 })
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .width('100%')
    } else {
      Column() {
        Stack({ alignContent: Alignment.Bottom }) {
          List({ space: Tokens.sec, scroller: this.listScroller }) {
            ForEach(this.feed, (item: TimelineItem) => {
              ListItem() {
                this.timelineItem(item)
              }
            }, (item: TimelineItem) => this.rowKey(item))
          }
          .width('100%')
          .height('100%')
          .padding({ left: this.pagePad, right: this.pagePad })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .cachedCount(18)
          .onScrollIndex((start: number, end: number) => {
            const total = this.vm.source.totalCount();
            const nearBottom = end >= total - 2;
            this.vm.stickToBottom = nearBottom;
            this.showJump = !nearBottom && this.runActive;
          })

          if (this.showJump) {
            Text('最新')
              .fontSize(Tokens.typeMicro)
              .fontColor($r('app.color.primary_on'))
              .constraintSize({ minHeight: Tokens.touchMin })
              .padding({ left: 14, right: 14 })
              .backgroundColor($r('app.color.primary'))
              .borderRadius(Tokens.radiusChip)
              .margin({ bottom: 12 })
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.vm.stickToBottom = true;
                this.showJump = false;
                this.listScroller.scrollEdge(Edge.Bottom);
              })
          }
        }
        .layoutWeight(1)
        .width('100%')
        .onAreaChange((_old: Area, now: Area) => {
          const raw = now.height;
          const h = typeof raw === 'number' ? raw : 0;
          if (h > 0 && this.lastListH > 8 && h < this.lastListH - 12 && this.vm.stickToBottom) {
            this.pinFeedToComposer(20);
          }
          if (h > 0) {
            this.lastListH = h;
          }
        })
      }
      .layoutWeight(1)
      .width('100%')
    }
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
      modelLabel: this.followModelLabelText(),
      failedFollow: this.failedFollow,
      queued: this.queuedFollowUp,
      queueNote: this.queueImagesLost ? '图片未保存' : '',
      bottomPad: this.bottomInset,
      onFocusChange: (on: boolean) => {
        if (on) {
          this.pinFeedToComposer(40, true);
        }
      },
      onSend: async () => {
        const text = this.draft;
        const imgs = this.attachedImages;
        this.draft = '';
        this.attachedImages = [];
        this.imageUris = [];
        this.sending = true;
        this.vm.followUpMcp = this.followUpMcp;
        const ok = await this.vm.followUp(text, imgs);
        if (!ok) {
          this.draft = text;
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
    } else {
      this.detailMenu()
    }
  }

  @Builder
  followModelSheet() {
    Column({ space: 10 }) {
      Text('本轮模型')
        .fontSize(Tokens.typeHeadline)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text('默认沿用创建时的模型。选了才覆盖这一轮。')
        .fontSize(Tokens.typeCaption)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
      ModelPicker({
        selectedModel: this.followUpModel,
        selectedVariantIndex: this.followVariantIndex,
        groups: this.followModelGroups,
        variantOptions: this.followVariantOptions,
        variantTitle: this.followVariantTitle,
        paramRows: this.followParamRows,
        allowAuto: true,
        autoLabel: '沿用',
        onPick: (id: string) => {
          this.pickFollowModel(id);
        },
        onPickParam: (rowIdx: number, valueIdx: number) => {
          this.pickFollowParam(rowIdx, valueIdx);
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
        }
      })
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.bg1'))
  }

  @Builder
  followToolsSheet() {
    Column({ space: 10 }) {
      Text('本轮 MCP')
        .fontSize(17)
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
    .padding(16)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.bg1'))
    .onDisAppear(() => {
      this.vm.followUpMcp = this.followUpMcp;
    })
  }

  @Builder
  usageSheet() {
    Column({ space: 8 }) {
      Text('用量明细')
        .fontSize(17)
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
              .padding(12)
              .backgroundColor($r('app.color.bg2'))
              .borderRadius(8)
            }
          }, (r: RunUsage, idx: number) => `${r.id}-${idx}`)
        }
      }
    }
    .width('100%')
    .padding(16)
  }

  @Builder
  artifactsSheet() {
    Column({ space: 8 }) {
      Text('产物')
        .fontSize(17)
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
                  this.copyHint = msg;
                  showToast(msg);
                  setTimeout(() => {
                    this.copyHint = '';
                  }, 2500);
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
    .padding(16)
    .width('100%')
    .height('100%')
  }

  @Builder
  detailMenu() {
    Column({ space: 4 }) {
      Column({ space: 4 }) {
        Text(this.menuStatusLine())
          .width('100%')
          .fontSize(Tokens.typeCaption)
          .fontColor($r('app.color.text_secondary'))
        if (this.shortRepo().length > 0) {
          Text(this.shortRepo())
            .width('100%')
            .fontSize(Tokens.typeCaption)
            .fontColor($r('app.color.text_tertiary'))
            .fontFamily(Tokens.fontMono)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (this.metaLine.length > 0) {
          Text(this.metaLine)
            .width('100%')
            .fontSize(Tokens.typeCaption)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (this.currentFile().length > 0) {
          Text(this.currentFile())
            .width('100%')
            .fontSize(Tokens.typeCaption)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (this.usageLabel.length > 0) {
          Text(this.usageLabel)
            .width('100%')
            .fontSize(Tokens.typeCaption)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ bottom: 8 })
      if (this.prLabel().length > 0) {
        Text(this.prLabel())
          .width('100%')
          .height(48)
          .fontSize(Tokens.typeProse)
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.closeSheet();
            this.openLink(this.firstPr(), 'Pull Request');
          })
      }
      if (this.firstBranch().length > 0) {
        Text('复制分支')
          .width('100%')
          .height(48)
          .fontSize(Tokens.typeProse)
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.closeSheet();
            this.copyText(this.firstBranch());
          })
      }
      if (this.artifacts.length > 0) {
        Text('产物')
          .width('100%')
          .height(48)
          .fontSize(Tokens.typeProse)
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.sheetKind = 'artifacts';
          })
      }
      if (this.compareUrl.length > 0) {
        Text('改动')
          .width('100%')
          .height(48)
          .fontSize(Tokens.typeProse)
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.closeSheet();
            this.openLink(this.compareUrl, '改动');
          })
      }
      Text('分享')
        .width('100%')
        .height(48)
        .fontSize(Tokens.typeProse)
        .fontColor($r('app.color.text_primary'))
        .onClick(async () => {
          this.closeSheet();
          const pr = this.vm.branches.length > 0 ? (this.vm.branches[0].prUrl ?? '') : '';
          const branch = this.vm.branches.length > 0 ? (this.vm.branches[0].branch ?? '') : '';
          const ctx = getContext(this) as common.UIAbilityContext;
          await shareAgentLinks(ctx, this.name, this.url, pr, branch);
        })
      if (this.usageRuns.length > 0) {
        Text('用量')
          .width('100%')
          .height(48)
          .fontSize(Tokens.typeProse)
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.sheetKind = 'usage';
          })
      }
      Text(this.pinned ? '取消置顶' : '置顶')
        .width('100%')
        .height(48)
        .fontSize(Tokens.typeProse)
        .fontColor($r('app.color.text_primary'))
        .onClick(async () => {
          const wasPinned = this.pinned;
          await this.togglePin();
          this.closeSheet();
          Haptics.success();
          showToast(wasPinned ? '已取消置顶' : '已置顶');
        })
      Text('系统浏览器打开')
        .width('100%')
        .height(48)
        .fontSize(Tokens.typeProse)
        .fontColor($r('app.color.text_secondary'))
        .onClick(() => {
          this.closeSheet();
          const ctx = getContext(this) as common.UIAbilityContext;
          const link = this.url.length > 0 ? this.url : WebLinks.agentPage(this.agentId);
          ctx.openLink(link).catch(() => {
          });
        })
      if (this.status === 'ARCHIVED') {
        Text('取消归档')
          .width('100%')
          .height(48)
          .fontSize(Tokens.typeProse)
          .fontColor($r('app.color.text_primary'))
          .onClick(async () => {
            const ok = await this.vm.unarchive();
            this.closeSheet();
            this.sync();
            if (ok) {
              Haptics.success();
              InboxVM.getInstance().refresh(true);
            } else {
              Haptics.fail();
            }
          })
      } else {
        Text('归档')
          .width('100%')
          .height(48)
          .fontSize(Tokens.typeProse)
          .fontColor($r('app.color.text_primary'))
          .onClick(async () => {
            const ok = await this.vm.archive();
            this.closeSheet();
            if (ok) {
              Haptics.success();
              showToast('已归档');
              PrefStore.getInstance().setIncludeArchived(true);
              this.vm.close();
              this.navStack.pop();
            } else {
              Haptics.fail();
              this.sync();
            }
          })
      }
      Text('永久删除')
        .width('100%')
        .height(48)
        .fontSize(Tokens.typeProse)
        .fontColor($r('app.color.err'))
        .onClick(() => {
          const id = this.agentId;
          this.closeSheet();
          confirmDanger('永久删除', '删除后无法从 Inbox 恢复此任务。', '删除', () => {
            this.vm.deleteRemote().then((ok: boolean) => {
              if (ok) {
                Haptics.success();
                showToast('已删除');
                InboxVM.getInstance().removeLocal(id);
                this.vm.close();
                this.navStack.pop();
              } else {
                Haptics.fail();
                this.sync();
              }
            });
          });
        })
    }
    .padding(16)
    .width('100%')
  }

  private activityTitle(item: TimelineItem): string {
    if (item.kind === 'step') {
      const title = (item.text ?? '').trim();
      if (this.runActive && item.streaming === true) {
        return title.length > 0 ? title : '在想下一步';
      }
      return title.length > 0 ? title : '步骤';
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

  private processBodyForRun(runId: string): string {
    const bits: string[] = [];
    const total = this.vm.source.totalCount();
    for (let i = 0; i < total; i++) {
      const it = this.vm.source.getData(i);
      if (it.runId !== runId || !this.isProcessKind(it.kind)) {
        continue;
      }
      const t = (it.text ?? '').trim();
      if (t.length > 0) {
        bits.push(t);
      }
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

  @Builder
  timelineItem(item: TimelineItem) {
    if (item.kind === 'userPrompt') {
      Column({ space: 4 }) {
        if (this.isFollowUpUser(item)) {
          Row({ space: 8 }) {
            Divider()
              .color($r('app.color.border'))
              .layoutWeight(1)
            Text('追问')
              .fontSize(Tokens.typeMicro)
              .fontColor($r('app.color.text_tertiary'))
            Divider()
              .color($r('app.color.border'))
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ top: 12, bottom: 4 })
          .alignItems(VerticalAlign.Center)
          .transition(chromeTransition())
        }
        Column() {
          if (this.isPlainUser(item.text ?? '')) {
            Text(item.text ?? '')
              .fontSize(Tokens.typeCallout)
              .fontFamily(Tokens.fontUi)
              .fontColor($r('app.color.text_primary'))
              .lineHeight(Tokens.lineList)
              .maxLines(6)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .constraintSize({ minHeight: Tokens.touchMin })
          } else {
            MarkdownLite({
              content: item.text ?? '',
              compact: true
            })
          }
          if ((item.usageShort ?? '').length > 0) {
            Text(item.usageShort ?? '')
              .fontSize(Tokens.typeMicro)
              .fontFamily(Tokens.fontUi)
              .fontColor($r('app.color.text_tertiary'))
              .width('100%')
              .padding({ top: 6 })
          }
        }
        .width('100%')
        .constraintSize({ minHeight: 52 })
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor(item.failed ? $r('app.color.banner_error_bg') : $r('app.color.user_bubble'))
        .borderRadius(Tokens.radiusMd)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
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
      if (this.isLeadProcess(item)) {
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
            .wordBreak(WordBreak.BREAK_ALL)
            .width('100%')
        } else {
          MarkdownLite({
            content: item.text ?? '',
            compact: this.isShortMsg(item.text ?? '')
          })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 2, bottom: 6 })
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
