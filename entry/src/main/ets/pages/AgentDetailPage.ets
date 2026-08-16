import { common } from '@kit.AbilityKit';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { DetailVM } from '../viewmodels/DetailVM';
import { TimelineItem } from '../models/Timeline';
import { ArtifactInfo, CustomSubagentDef, EnvVarDef, McpServerDef, RunUsage } from '../models/Api';
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
import { motionMs, shimmerMs, shimmerOpacity } from '../utils/Motion';
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

  aboutToDisappear(): void {
    this.clearTick();
    if (this.mdTimer >= 0) {
      clearTimeout(this.mdTimer);
      this.mdTimer = -1;
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
    this.name = this.vm.name;
    this.status = this.vm.status;
    this.runStatus = this.vm.runStatus;
    this.url = this.vm.url;
    this.loading = this.vm.loading;
    this.syncing = this.vm.syncing;
    this.errorMsg = this.vm.errorMsg;
    this.resultText = this.vm.resultText;
    this.streamNotice = this.vm.streamNotice;
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
      setTimeout(() => {
        try {
          this.listScroller.scrollEdge(Edge.Bottom);
        } catch (_e) {
        }
      }, 16);
    }
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
      return elapsedLabel(Math.max(0, Math.floor((Date.now() - this.runStartMs) / 1000)));
    }
    if (this.durationMs > 0) {
      return elapsedLabel(Math.floor(this.durationMs / 1000));
    }
    return '';
  }

  private processLabel(): string {
    const _t = this.tick;
    let elapsed = '';
    if (this.runActive && this.runStartMs > 0) {
      elapsed = elapsedLabel(Math.max(0, Math.floor((Date.now() - this.runStartMs) / 1000)));
    } else if (this.durationMs > 0) {
      elapsed = elapsedLabel(Math.floor(this.durationMs / 1000));
    }
    const steps = this.toolStepCount();
    if (this.runActive) {
      return elapsed.length > 0 ? `推理中 · ${elapsed}` : '推理中';
    }
    if (steps === 0 && elapsed.length === 0) {
      return '';
    }
    let s = '过程';
    if (elapsed.length > 0) {
      s += ` · ${elapsed}`;
    }
    if (steps > 0) {
      s += ` · ${steps}步`;
    }
    return s;
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
          Text(this.noticeLine)
            .width('100%')
            .fontSize(Tokens.typeCaption)
            .fontColor($r('app.color.text_primary'))
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: this.pagePad, right: this.pagePad, top: 8, bottom: 8 })
            .backgroundColor($r('app.color.bg2'))
            .onClick(() => {
              this.dismissNotice();
            })
        }

        if (this.needsPlanUpgrade) {
          Text('套餐不足，打开 Dashboard 升级 ↗')
            .width('100%')
            .fontSize(Tokens.typeCaption)
            .fontColor($r('app.color.warn'))
            .padding({ left: this.pagePad, right: this.pagePad, top: 6, bottom: 6 })
            .backgroundColor($r('app.color.banner_offline_bg'))
            .onClick(() => {
              this.openLink('https://cursor.com/dashboard');
            })
        }

        if (this.failed() || this.errorMsg.length > 0) {
          Row({ space: 8 }) {
            Text(this.errorMsg.length > 0 ? this.errorMsg : '失败')
              .fontSize(Tokens.typeCaption)
              .fontColor($r('app.color.err'))
              .layoutWeight(1)
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.authFail()) {
              Text('去设置')
                .fontSize(Tokens.typeCaption)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.accent_on'))
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .backgroundColor($r('app.color.accent'))
                .borderRadius(Tokens.radiusChip)
                .onClick(() => {
                  this.navStack.pushPath({ name: 'Settings' });
                })
            }
          }
          .width('100%')
          .constraintSize({ minHeight: Tokens.touchMin })
          .padding({ left: this.pagePad, right: this.pagePad, top: 10, bottom: 10 })
          .backgroundColor($r('app.color.banner_error_bg'))
          .alignItems(VerticalAlign.Center)
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
      height: this.sheetKind === 'artifacts' ? SheetSize.MEDIUM : SheetSize.FIT_CONTENT,
      dragBar: true,
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
      });
      const p = ctx.pathInfo.param as Record<string, Object>;
      if (p && p['agentId']) {
        this.agentId = `${p['agentId']}`;
        this.vm.setUiListener(() => {
          this.sync();
        });
        this.vm.open(this.agentId).then(() => {
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
          List({ space: 10, scroller: this.listScroller }) {
            ForEach(this.feed, (item: TimelineItem) => {
              ListItem() {
                this.timelineItem(item)
              }
            }, (item: TimelineItem) => this.rowKey(item))
          }
          .width('100%')
          .height('100%')
          .padding({ left: this.pagePad + 4, right: this.pagePad + 4 })
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
      imageCount: this.attachedImages.length,
      imageUris: $imageUris,
      toolsOn: countMcp(this.followUpMcp) > 0,
      toolsLabel: this.followToolsLabel,
      followUpMode: this.followUpMode,
      queued: this.queuedFollowUp,
      bottomPad: this.bottomInset,
      onSend: async () => {
        const text = this.draft;
        const imgs = this.attachedImages;
        this.vm.followUpMcp = this.followUpMcp;
        const ok = await this.vm.followUp(text, imgs);
        if (ok) {
          this.draft = '';
          for (let i = 0; i < this.attachedImages.length; i++) {
            dropPreviewMap(previewSrc(this.attachedImages[i]));
          }
          this.attachedImages = [];
          this.imageUris = [];
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
      onModeChange: (mode: string) => {
        this.vm.followUpMode = mode;
        this.followUpMode = mode;
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
    } else {
      this.detailMenu()
    }
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
            .fontFamily('monospace')
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
          await this.togglePin();
          this.closeSheet();
          Haptics.success();
          showToast(this.pinned ? '已置顶' : '已取消置顶');
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
              InboxVM.getInstance().removeLocal(this.agentId);
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

  private runHeaderLabel(raw: string): string {
    const t = raw.trim();
    if (t.length === 0 || t === 'Run' || t === 'run') {
      return '运行';
    }
    if (t.indexOf('Run') === 0) {
      return `运行${t.substring(3)}`;
    }
    return t;
  }

  private activityTitle(item: TimelineItem): string {
    if (item.kind === 'step') {
      const title = (item.text ?? '').trim();
      if (this.runActive && item.streaming === true) {
        return title.length > 0 ? `步骤 · ${title}` : '步骤';
      }
      return title.length > 0 ? title : '步骤';
    }
    const isThink = item.kind === 'thinking';
    if (isThink) {
      return (this.runActive && item.streaming === true) ? '推理中' : '推理过程';
    }
    if (this.runActive && item.streaming === true) {
      return '进行中';
    }
    const n = item.stepCount && item.stepCount > 0 ? item.stepCount : 1;
    return `过程 · ${n} 步`;
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
      Column() {
        if (this.isPlainUser(item.text ?? '')) {
          Text(item.text ?? '')
            .fontSize(Tokens.typeCallout)
            .fontColor($r('app.color.text_primary'))
            .lineHeight(22)
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
      }
      .width('100%')
      .constraintSize({ minHeight: 52 })
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor(item.failed ? $r('app.color.banner_error_bg') : $r('app.color.user_bubble'))
      .borderRadius(Tokens.radiusMd)
    } else if (item.kind === 'runHeader') {
      Column().width('100%').height(0)
    } else if (item.kind === 'thinking' || item.kind === 'progress' || item.kind === 'step') {
      if (this.isLeadProcess(item)) {
        ActivityCard({
          item: item,
          runActive: this.runActive,
          shimmerOn: this.shimmerOn,
          title: this.processLabel().length > 0 ? this.processLabel() : this.activityTitle(item),
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
          Row({ space: 6 }) {
            Text('正在写')
              .fontSize(Tokens.typeMicro)
              .fontColor($r('app.color.text_tertiary'))
              .opacity(shimmerOpacity(this.shimmerOn))
              .animation({ duration: shimmerMs(), curve: Curve.EaseInOut })
          }
          Text(item.text ?? '')
            .fontSize(Tokens.typeProse)
            .fontColor($r('app.color.text_primary'))
            .lineHeight(Tokens.lineProse)
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
    const body = item.text ?? '';
    if (body.length === 0) {
      return this.resultText.length > 0;
    }
    if (body === this.resultText && this.resultText.length > 0) {
      return true;
    }
    if (body.indexOf('状态：') === 0 && this.resultText.length > 0) {
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
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.outcomeTone(item.statusLabel ?? ''))
        }
        .width('100%')
        if ((item.text ?? '').length > 0) {
          Text(item.text ?? '')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .lineHeight(Tokens.lineCaption + 2)
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
