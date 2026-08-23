import { common } from '@kit.AbilityKit';
import { LengthMetrics } from '@kit.ArkUI';
import { NewAgentVM } from '../viewmodels/NewAgentVM';
import { InboxVM } from '../viewmodels/InboxVM';
import { Tokens } from '../theme/Tokens';
import { BreakpointStore } from '../store/BreakpointStore';
import { PrefStore } from '../store/PrefStore';
import {
  CustomSubagentDef, EnvTarget, EnvVarDef, McpServerDef, ModelInfo, RepoInfo
} from '../models/Api';
import { Haptics } from '../utils/Haptics';
import { motionMs } from '../utils/Motion';
import { dropPreviewMap, maxPromptImages, pickPromptImages, previewSrc, PromptImage, toApiImages,
  unlinkPreviewFile } from '../utils/ImagePicker';
import { HuIconButton } from '../components/HuIconButton';
import { PromptShell } from '../components/PromptShell';
import { EnvVarListEditor, McpListEditor, SubagentListEditor } from '../components/CapabilityEditors';
import { defaultEnv, envNameLabel, hasTools, serializeTools, toolsChipLabel, usesNamedEnv } from '../utils/AgentCapabilities';
import { repoIdentity, repoTail } from '../utils/DisplayFmt';
import { collectRecentEnvs, collectRecentRepos, pairRecentRepos, RecentRepo, RecentRepoRow } from '../utils/InboxGrouping';
import { isOriginRepo, looksLikeRepoUrl } from '../utils/GitLinks';
import {
  buildParamRows, formatChipFromRows, formatFollowChip, findModel, groupModels, ModelParamRow,
  ModelVendorGroup, paramRowsStamp, rowsToParams, shortModelName, snapParamRows, variantLabel,
  variantSectionTitle
} from '../utils/ModelGroups';
import { HuChip } from '../components/HuChip';
import { HuTextButton } from '../components/HuTextButton';
import { SheetPickRow } from '../components/SheetAction';
import { ModelPicker } from '../components/ModelPicker';
import { StatusBanner } from '../components/StatusBanner';
import { ToastHost } from '../components/ToastHost';
import { notifyResult, showToast } from '../utils/AppToast';

@Builder
export function NewAgentPageBuilder() {
  NewAgentPage()
}

@Component
export struct NewAgentPage {
  @Consume('navPathStack') navStack: NavPathStack;
  @Prop embedded: boolean = false;
  onCreated: (localId: string) => void = (_id: string) => {
  };
  onDismiss: () => void = () => {
  };
  private vm: NewAgentVM = new NewAgentVM();
  private bp: BreakpointStore = BreakpointStore.getInstance();

  @State prompt: string = '';
  @State selectedRepo: string = '';
  @State selectedBranch: string = 'main';
  @State selectedPrUrl: string = '';
  @State repoMode: string = 'repo';
  @State selectedModel: string = '';
  @State selectedVariant: string = '';
  @State modelDisplayName: string = '';
  @State mode: string = 'agent';
  @State autoCreatePR: boolean = true;
  @State workOnCurrentBranch: boolean = false;
  @State openAsCursorGithubApp: boolean = false;
  @State skipReviewerRequest: boolean = false;
  @State agentName: string = '';
  @State selectedVariantIndex: number = -1;
  @State env: EnvTarget = defaultEnv();
  @State mcpServers: McpServerDef[] = [];
  @State subagents: CustomSubagentDef[] = [];
  @State envVars: EnvVarDef[] = [];
  @State busy: boolean = false;
  @State loadingMeta: boolean = false;
  @State errorMsg: string = '';
  @State showSheet: boolean = false;
  /** Outer bindSheet only when this page is not already inside Index's sheet. */
  @State showBindSheet: boolean = false;
  @State sheetKind: string = '';
  @State repoQuery: string = '';
  @State repos: RepoInfo[] = [];
  @State models: ModelInfo[] = [];
  @State modelGroups: ModelVendorGroup[] = [];
  @State variantOptions: string[] = [];
  @State variantTitle: string = '模式';
  @State paramRows: ModelParamRow[] = [];
  @State paramStamp: string = '';
  @State modelChipLabel: string = '自动';
  @State windowW: number = 360;
  @State topInset: number = 0;
  @State bottomInset: number = 0;
  @State imageNames: string[] = [];
  @State imageUris: string[] = [];
  @State hideBranch: boolean = false;
  @State toolsOn: boolean = false;
  @State toolsLabel: string = 'MCP';
  @State moreLabel: string = '更多';
  @State showAdvanced: boolean = false;
  @State recentRepos: RecentRepo[] = [];
  @State recentEnvs: string[] = [];
  @State reposRefreshing: boolean = false;
  @State modelsLoading: boolean = false;
  @State modelsError: string = '';
  private attachedImages: PromptImage[] = [];
  private draftTimer: number = -1;
  private unsubBp: (() => void) | undefined = undefined;
  private pageAlive: boolean = false;

  aboutToAppear(): void {
    this.pageAlive = true;
    this.topInset = this.embedded ? 8 : this.bp.safeTop();
    this.bottomInset = this.bp.composerBottom();
    this.windowW = this.bp.widthVp;
    this.unsubBp = this.bp.onChange(() => {
      this.topInset = this.embedded ? 8 : this.bp.safeTop();
      this.bottomInset = this.bp.composerBottom();
      this.windowW = this.bp.widthVp;
    });
    this.vm.hydrateFromCache();
    this.syncFromVm();
    this.refreshRecentRepos();
    PrefStore.getInstance().getDraft().then((d: string) => {
      if (d.length > 0 && this.prompt.length === 0) {
        this.prompt = d;
        this.vm.prompt = d;
        this.refreshCanSubmit();
      }
    });
    this.vm.loadMeta(false).then(() => {
      this.syncFromVm();
    });
  }

  aboutToDisappear(): void {
    this.pageAlive = false;
    if (this.unsubBp) {
      this.unsubBp();
      this.unsubBp = undefined;
    }
    for (let i = 0; i < this.attachedImages.length; i++) {
      const src = previewSrc(this.attachedImages[i]);
      dropPreviewMap(src);
      unlinkPreviewFile(src);
    }
  }

  private openSheet(kind: string): void {
    this.sheetKind = kind;
    this.showSheet = true;
    if (!this.embedded) {
      this.showBindSheet = true;
    }
    if (kind === 'model') {
      this.ensureModelsLoaded(this.modelGroups.length === 0);
    }
  }

  private closeSheet(): void {
    this.showSheet = false;
    this.showBindSheet = false;
  }

  private scheduleDraftSave(text: string): void {
    if (this.draftTimer >= 0) {
      clearTimeout(this.draftTimer);
    }
    this.draftTimer = setTimeout(() => {
      PrefStore.getInstance().setDraft(text);
      this.draftTimer = -1;
    }, 500) as number;
  }

  private ensureModelsLoaded(force: boolean = false): void {
    this.models = this.vm.models;
    this.updateModelMeta();
    if (!force && this.modelGroups.length > 0) {
      this.modelsError = '';
      return;
    }
    this.modelsLoading = true;
    this.modelsError = '';
    this.vm.loadMeta(false).then(() => {
      this.modelsLoading = false;
      this.syncFromVm();
      if (this.modelGroups.length === 0 && this.models.length === 0) {
        this.modelsError = '模型列表没加载到，点重试。';
      }
    }, () => {
      this.modelsLoading = false;
      this.syncFromVm();
      if (this.modelGroups.length === 0) {
        this.modelsError = '模型列表没加载到，点重试。';
      }
    });
  }

  private refreshCanSubmit(): void {
    this.syncVmContext();
    this.hideBranch = this.vm.hideBranchChip();
    this.toolsOn = hasTools(this.env, this.mcpServers, this.subagents, this.envVars);
    this.toolsLabel = toolsChipLabel(this.env, this.mcpServers, this.subagents, this.envVars);
    this.moreLabel = this.moreSummary();
  }

  private moreSummary(): string {
    if (this.toolsOn || this.workOnCurrentBranch ||
      this.openAsCursorGithubApp || this.skipReviewerRequest || this.agentName.length > 0) {
      return '更多·';
    }
    return '更多';
  }

  private syncVmContext(): void {
    this.vm.prompt = this.prompt;
    this.vm.selectedRepo = this.selectedRepo;
    this.vm.selectedBranch = this.selectedBranch;
    this.vm.selectedPrUrl = this.selectedPrUrl;
    this.vm.repoMode = this.repoMode;
    this.vm.mode = this.mode;
    this.vm.agentName = this.agentName;
    this.vm.env = this.env;
    this.vm.mcpServers = this.mcpServers;
    this.vm.subagents = this.subagents;
    this.vm.envVars = this.envVars;
  }

  private syncImageNames(): void {
    const names: string[] = [];
    const uris: string[] = [];
    for (let i = 0; i < this.attachedImages.length; i++) {
      names.push(this.attachedImages[i].name);
      const src = previewSrc(this.attachedImages[i]);
      if (src.length > 0) {
        uris.push(src);
      }
    }
    this.imageNames = names;
    this.imageUris = uris;
    this.vm.imagePayloads = toApiImages(this.attachedImages);
  }

  private async attachImages(): Promise<void> {
    const remain = maxPromptImages() - this.attachedImages.length;
    if (remain <= 0) {
      this.errorMsg = '最多 5 张图';
      return;
    }
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const picked: PromptImage[] = await pickPromptImages(ctx, remain);
      for (let i = 0; i < picked.length; i++) {
        this.attachedImages.push(picked[i]);
      }
      this.syncImageNames();
    } catch (_e) {
      this.errorMsg = '选图取消或失败';
    }
  }

  private removeImage(index: number): void {
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
    this.syncImageNames();
  }

  private syncFromVm(): void {
    this.prompt = this.vm.prompt;
    this.selectedRepo = this.vm.selectedRepo;
    this.selectedBranch = this.vm.selectedBranch;
    this.selectedPrUrl = this.vm.selectedPrUrl;
    this.repoMode = this.vm.repoMode;
    this.selectedModel = this.vm.selectedModel;
    this.selectedVariant = this.vm.selectedVariant;
    this.mode = this.vm.mode;
    this.autoCreatePR = this.vm.autoCreatePR;
    this.workOnCurrentBranch = this.vm.workOnCurrentBranch;
    this.openAsCursorGithubApp = this.vm.openAsCursorGithubApp;
    this.skipReviewerRequest = this.vm.skipReviewerRequest;
    this.agentName = this.vm.agentName;
    this.selectedVariantIndex = this.vm.selectedVariantIndex;
    this.env = this.vm.env;
    this.mcpServers = this.vm.mcpServers;
    this.subagents = this.vm.subagents;
    this.envVars = this.vm.envVars;
    this.busy = this.vm.busy;
    this.loadingMeta = this.vm.loadingMeta;
    this.errorMsg = this.vm.errorMsg;
    this.repos = this.vm.filteredRepos();
    this.models = this.vm.models;
    this.updateModelMeta();
    this.refreshCanSubmit();
    this.refreshRecentRepos();
    this.refreshRecentEnvs();
  }

  private refreshRecentRepos(): void {
    const seen: string[] = [];
    const out: RecentRepo[] = [];
    const recent = collectRecentRepos(InboxVM.getInstance().source.snapshot(), 80);
    for (let i = 0; i < recent.length; i++) {
      const url = recent[i].url;
      const id = repoIdentity(url);
      if (url.length === 0 || id.length === 0 || seen.indexOf(id) >= 0) {
        continue;
      }
      seen.push(id);
      out.push(recent[i]);
    }
    const list = this.vm.repos;
    for (let i = 0; i < list.length; i++) {
      const url = list[i].repository;
      const id = repoIdentity(url);
      if (url.length === 0 || id.length === 0 || seen.indexOf(id) >= 0) {
        continue;
      }
      seen.push(id);
      const name = repoTail(url);
      const item: RecentRepo = { url: url, ref: 'main', title: name.length > 0 ? name : list[i].name };
      out.push(item);
    }
    this.recentRepos = out;
  }

  private refreshRecentEnvs(): void {
    this.recentEnvs = collectRecentEnvs(InboxVM.getInstance().source.snapshot(), 8);
  }

  private repoGridItems(): RecentRepo[] {
    const cap = 20;
    const total = this.recentRepos.length;
    const n = Math.min(cap, total);
    const items: RecentRepo[] = [];
    for (let i = 0; i < n; i++) {
      items.push(this.recentRepos[i]);
    }
    if (total > cap) {
      items.push({ url: '__more__', ref: '', title: '全部' });
    }
    return items;
  }

  private repoRows(): RecentRepoRow[] {
    return pairRecentRepos(this.repoGridItems());
  }

  private repoSheetName(r: RepoInfo): string {
    if (r.name.length > 0) {
      return r.name;
    }
    return repoTail(r.repository);
  }

  private openRepoSheet(): void {
    this.repoQuery = '';
    this.vm.repoQuery = '';
    this.repos = this.vm.filteredRepos();
    this.openSheet('repo');
    this.vm.refreshRepos(false).then(() => {
      this.syncFromVm();
    });
  }

  private async pullRepos(force: boolean): Promise<void> {
    await this.vm.refreshRepos(force);
    this.syncFromVm();
    if (this.vm.errorMsg.length > 0) {
      notifyResult(false, '', this.vm.errorMsg, 'new');
      this.vm.errorMsg = '';
      this.errorMsg = '';
    } else if (force) {
      notifyResult(true, `已刷新 · ${this.vm.repos.length} 个仓库`, '', 'new');
    }
  }

  private pickRecentRepo(item: RecentRepo): void {
    Haptics.tick();
    this.repoMode = 'repo';
    this.vm.repoMode = 'repo';
    this.applyRepoSelection(item.url, item.ref.length > 0 ? item.ref : 'main');
    this.refreshCanSubmit();
  }

  private applyRepoSelection(url: string, ref?: string): void {
    this.clearNamedEnv();
    if (this.repoMode === 'none') {
      this.repoMode = 'repo';
      this.vm.repoMode = 'repo';
    }
    this.selectedRepo = url;
    this.vm.selectedRepo = url;
    if (ref !== undefined) {
      this.selectedBranch = ref.length > 0 ? ref : 'main';
      this.vm.selectedBranch = this.selectedBranch;
    }
    if (isOriginRepo(url)) {
      this.openAsCursorGithubApp = false;
      this.vm.openAsCursorGithubApp = false;
    }
  }

  private clearNamedEnv(): void {
    if (this.env.kind === 'default' && this.env.name.length === 0) {
      return;
    }
    this.env = defaultEnv();
    this.vm.env = this.env;
  }

  private pickRecentEnv(name: string): void {
    Haptics.tick();
    this.env = { kind: 'cloud', name: name };
    this.vm.env = this.env;
    this.repoMode = 'none';
    this.vm.repoMode = 'none';
    this.refreshCanSubmit();
  }

  private updateModelMeta(): void {
    this.modelGroups = groupModels(this.models);
    this.variantOptions = [];
    this.variantTitle = '模式';
    this.paramRows = [];
    this.modelDisplayName = '';
    if (this.selectedModel.length === 0) {
      this.modelDisplayName = '默认（自动）';
      this.vm.selectedParams = [];
      this.refreshModelChip();
      return;
    }
    for (let i = 0; i < this.models.length; i++) {
      const m = this.models[i];
      if (m.id === this.selectedModel) {
        this.modelDisplayName = m.displayName ?? m.id;
        const rows = buildParamRows(m);
        if (rows.length > 0) {
          this.paramRows = snapParamRows(m, rows, '', -1);
          this.vm.selectedParams = rowsToParams(this.paramRows);
          this.refreshModelChip();
          return;
        }
        this.vm.selectedParams = [];
        if (m.variants && m.variants.length > 0) {
          const labels: string[] = [];
          for (let j = 0; j < m.variants.length; j++) {
            labels.push(variantLabel(m.variants[j], j));
          }
          this.variantOptions = labels;
          this.variantTitle = variantSectionTitle(m.variants);
          if (this.selectedVariantIndex < 0) {
            let def = 0;
            for (let j = 0; j < m.variants.length; j++) {
              if (m.variants[j].isDefault === true) {
                def = j;
                break;
              }
            }
            this.selectedVariantIndex = def;
            this.vm.selectedVariantIndex = def;
          }
        }
        this.refreshModelChip();
        return;
      }
    }
    this.modelDisplayName = this.selectedModel;
    this.vm.selectedParams = [];
    this.refreshModelChip();
  }

  private pickParam(rowId: string, valueIdx: number): void {
    this.paramRows = snapParamRows(findModel(this.models, this.selectedModel), this.paramRows, rowId, valueIdx);
    this.vm.selectedParams = rowsToParams(this.paramRows);
    this.refreshModelChip();
    this.refreshCanSubmit();
  }

  private refreshModelChip(): void {
    this.paramStamp = paramRowsStamp(this.paramRows);
    if (this.selectedModel.length === 0) {
      this.modelChipLabel = '自动';
      return;
    }
    const name = this.modelDisplayName.length > 0 ? this.modelDisplayName : this.selectedModel;
    if (this.paramRows.length > 0) {
      const chip = formatChipFromRows(name, this.paramRows);
      this.modelChipLabel = chip.length > 0 ? chip : '自动';
      return;
    }
    const payload = this.vm.modelPayload();
    const params = payload && payload['params'] ? payload['params'] as Object[] : [];
    const chip = formatFollowChip(name, params);
    this.modelChipLabel = chip.length > 0 ? chip : '自动';
  }

  private repoChipLabel(): string {
    if (usesNamedEnv(this.env)) {
      return envNameLabel(this.env);
    }
    if (this.repoMode === 'none') {
      return '无仓库';
    }
    if (this.repoMode === 'pr') {
      return this.prChipLabel();
    }
    if (!this.selectedRepo) {
      return '选择仓库';
    }
    const tail = repoTail(this.selectedRepo);
    const name = tail.length > 0 ? tail : this.shortRepo(this.selectedRepo);
    if (this.hideBranch) {
      return name;
    }
    const br = this.selectedBranch.length > 0 ? this.selectedBranch : 'main';
    return `${name} · ${br}`;
  }

  private prChipLabel(): string {
    const pr = this.selectedPrUrl.trim();
    const hash = pr.lastIndexOf('/pull/');
    if (hash >= 0) {
      return `PR #${pr.substring(hash + 6)}`;
    }
    if (this.selectedRepo.length > 0) {
      return `PR · ${this.shortRepo(this.selectedRepo)}`;
    }
    return '从 PR';
  }

  private shortRepo(url: string): string {
    if (!url) {
      return '选择仓库';
    }
    const cleaned = url.replace(/\.git$/, '');
    const parts = cleaned.split('/');
    if (parts.length >= 2) {
      return `${parts[parts.length - 2]}/${parts[parts.length - 1]}`;
    }
    return url;
  }

  private setRepoMode(mode: string): void {
    if (mode !== 'none' || this.repoMode !== 'none') {
      this.clearNamedEnv();
    }
    this.repoMode = mode;
    this.vm.repoMode = mode;
    this.refreshCanSubmit();
  }

  private setEnvKind(kind: string): void {
    this.env = { kind: kind, name: kind === 'default' ? '' : this.env.name };
    this.vm.env = this.env;
    if (usesNamedEnv(this.env)) {
      this.repoMode = 'none';
      this.vm.repoMode = 'none';
    }
    this.refreshCanSubmit();
  }

  private async submitAgent(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.syncVmContext();
    this.syncImageNames();
    this.vm.selectedModel = this.selectedModel;
    this.vm.selectedVariant = this.selectedVariant;
    this.vm.mode = this.mode;
    this.vm.autoCreatePR = this.autoCreatePR;
    this.vm.workOnCurrentBranch = this.workOnCurrentBranch;
    this.vm.openAsCursorGithubApp = this.openAsCursorGithubApp;
    this.vm.skipReviewerRequest = this.skipReviewerRequest;
    this.vm.agentName = this.agentName;
    this.vm.selectedVariantIndex = this.selectedVariantIndex;
    if (!this.vm.canSubmit()) {
      Haptics.warn();
      await this.vm.submit();
      this.errorMsg = this.vm.errorMsg;
      return;
    }
    this.errorMsg = '';
    this.busy = true;
    const resp = await this.vm.submit();
    this.syncFromVm();
    const agentId = resp?.agent?.id ?? '';
    if (agentId.length === 0) {
      if (!this.pageAlive) {
        if (this.vm.errorMsg.length > 0) {
          showToast(this.vm.errorMsg, 'danger', '');
        }
        return;
      }
      Haptics.fail();
      return;
    }
    PrefStore.getInstance().clearDraft();
    PrefStore.getInstance().setLastTools(serializeTools(this.env, this.mcpServers, this.subagents));
    if (this.selectedModel.length > 0) {
      PrefStore.getInstance().setDefaultModel(this.selectedModel);
    }
    for (let i = 0; i < this.attachedImages.length; i++) {
      const src = previewSrc(this.attachedImages[i]);
      dropPreviewMap(src);
      unlinkPreviewFile(src);
    }
    this.attachedImages = [];
    this.syncImageNames();
    if (!this.pageAlive) {
      showToast('任务已创建', 'success', 'inbox');
      return;
    }
    Haptics.success();
    if (this.embedded) {
      this.onCreated(agentId);
      return;
    }
    const param: Record<string, Object> = {};
    param['agentId'] = agentId;
    this.navStack.replacePath({ name: 'AgentDetail', param: param });
  }

  build() {
    if (this.embedded) {
      this.formColumn()
    } else {
      NavDestination() {
        this.formColumn()
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.bg0'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    }
  }

  @Builder
  noticeDock() {
    Column({ space: 8 }) {
      if (this.errorMsg.length > 0) {
        StatusBanner({
          text: this.errorMsg,
          tone: 'danger'
        })
      }
      ToastHost({ page: 'new' })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 16, right: 16, bottom: Tokens.toastBottom })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  formColumn() {
    Column() {
      if (this.embedded && this.showSheet) {
        this.sheetBody()
      } else {
      if (!this.embedded) {
        Row() {
          HuIconButton({
            name: 'back',
            label: '返回',
            onTap: () => {
              this.navStack.pop();
            }
          })
          Text('新任务')
            .fontSize(Tokens.typeHeadline)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .layoutWeight(1)
            .constraintSize({ minWidth: 0 })
        }
        .width('100%')
        .height(Tokens.touchMin)
        .alignItems(VerticalAlign.Center)
        .padding({
          left: Tokens.chromePad,
          right: Tokens.chromePad
        })
        .margin({ top: this.topInset })
      }

      Column() {
        PromptShell({
          placeholder: this.embedded ? '新任务：目标和约束' : '要做什么？目标和约束',
          text: $prompt,
          busy: this.busy,
          status: '',
          repo: this.repoChipLabel(),
          modelLabel: this.modelChipLabel,
          followUpMode: this.mode,
          autoPr: this.autoCreatePR,
          imageCount: this.imageNames.length,
          imageUris: $imageUris,
          toolsOn: this.toolsOn,
          toolsLabel: this.toolsLabel,
          moreLabel: this.moreLabel,
          bottomPad: 0,
          onSend: () => {
            this.submitAgent();
          },
          onRepo: () => {
            this.openRepoSheet();
          },
          onImage: () => {
            this.attachImages();
          },
          onRemoveImage: (idx: number) => {
            this.removeImage(idx);
          },
          onModel: () => {
            this.openSheet('model');
          },
          onModeChange: (mode: string) => {
            this.mode = mode;
            this.vm.mode = mode;
            this.refreshCanSubmit();
          },
          onTools: () => {
            this.openSheet('options');
          },
          onMoreExtra: () => {
            this.openSheet('options');
          },
          onText: (v: string) => {
            this.vm.prompt = v;
            this.scheduleDraftSave(v);
            this.refreshCanSubmit();
          }
        })
        Text('仓库')
          .fontSize(Tokens.typeCaption)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .padding({
            left: Tokens.pagePad,
            right: Tokens.pagePad,
            top: 20,
            bottom: 8
          })
        Refresh({ refreshing: $$this.reposRefreshing }) {
          Scroll() {
            this.recentRepoBlock()
          }
          .width('100%')
          .height('100%')
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
        .layoutWeight(1)
        .width('100%')
        .onRefreshing(async () => {
          Haptics.tick();
          this.reposRefreshing = true;
          await this.pullRepos(true);
          this.reposRefreshing = false;
        })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.embedded ? 20 : 12, bottom: this.bottomInset })
      .animation({ duration: motionMs(), curve: Curve.FastOutSlowIn })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg0'))
    .overlay(this.noticeDock(), { align: Alignment.Bottom })
    .bindSheet($$this.showBindSheet, this.sheetBody(), {
      height: this.sheetKind === 'repo' ? SheetSize.LARGE : SheetSize.MEDIUM,
      dragBar: true,
      showClose: false,
      radius: LengthMetrics.vp(Tokens.radiusSheet),
      backgroundColor: $r('app.color.overlay')
    })
  }

  @Builder
  recentRepoBlock() {
    Column({ space: 8 }) {
      ForEach(this.repoRows(), (row: RecentRepoRow) => {
        Row({ space: 8 }) {
          Column() {
            this.repoMiniCard(row.left)
          }
          .layoutWeight(1)
          if (row.hasRight) {
            Column() {
              this.repoMiniCard(row.right)
            }
            .layoutWeight(1)
          } else {
            Column()
              .layoutWeight(1)
          }
        }
        .width('100%')
      }, (row: RecentRepoRow) => row.key)
    }
    .width('100%')
    .padding({ left: Tokens.pagePad, right: Tokens.pagePad, bottom: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  repoMiniCard(item: RecentRepo) {
    if (item.url === '__more__') {
      Column() {
        Text('全部')
          .fontSize(Tokens.typeBody)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .height(64)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.bg1'))
      .border({ width: 1, color: $r('app.color.border') })
      .borderRadius(Tokens.radiusCard)
      .onClick(() => {
        Haptics.tick();
        this.openRepoSheet();
      })
    } else {
      Column({ space: 2 }) {
        Text(item.title)
          .fontSize(Tokens.typeBody)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(item.ref.length > 0 ? item.ref : 'main')
          .fontSize(Tokens.typeMicro)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .width('100%')
      }
      .width('100%')
      .height(64)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 12, right: 12 })
      .backgroundColor(this.selectedRepo === item.url ? $r('app.color.bg2') : $r('app.color.bg1'))
      .border({
        width: 1,
        color: this.selectedRepo === item.url ? $r('app.color.border_strong') : $r('app.color.border')
      })
      .borderRadius(Tokens.radiusCard)
      .onClick(() => {
        this.pickRecentRepo(item);
      })
    }
  }

  @Builder
  sheetBody() {
    if (this.sheetKind === 'repo') {
      this.repoSheet()
    } else if (this.sheetKind === 'branch') {
      this.branchSheet()
    } else if (this.sheetKind === 'model') {
      this.modelSheet()
    } else {
      this.optionsSheet()
    }
  }

  private pickModel(id: string): void {
    this.selectedModel = id;
    this.vm.selectedModel = id;
    this.selectedVariant = '';
    this.vm.selectedVariant = '';
    this.selectedVariantIndex = -1;
    this.vm.selectedVariantIndex = -1;
    this.vm.selectedParams = [];
    this.updateModelMeta();
    if (id.length > 0) {
      PrefStore.getInstance().setDefaultModel(id);
    }
  }

  @Builder
  modeSeg(label: string, mode: string) {
    Text(label)
      .fontSize(Tokens.typeCaption)
      .fontColor(this.repoMode === mode ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
      .constraintSize({ minHeight: 32 })
      .padding({ left: 12, right: 12 })
      .backgroundColor(this.repoMode === mode ? $r('app.color.bg2') : Color.Transparent)
      .borderRadius(Tokens.radiusChip)
      .onClick(() => {
        Haptics.tick();
        this.setRepoMode(mode);
      })
  }

  @Builder
  repoSheet() {
    Column({ space: Tokens.sheetGap }) {
      Row({ space: 8 }) {
        Text('仓库')
          .fontSize(Tokens.typeHeadline)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .constraintSize({ minWidth: 0 })
        HuTextButton({
          label: this.loadingMeta ? '…' : '刷新',
          color: $r('app.color.text_primary'),
          compact: true,
          isEnabled: !this.loadingMeta,
          onTap: async () => {
            this.loadingMeta = true;
            await this.pullRepos(true);
            this.loadingMeta = false;
          }
        })
        HuTextButton({
          label: '关闭',
          color: $r('app.color.text_secondary'),
          compact: true,
          onTap: () => {
            this.closeSheet();
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.errorMsg.length > 0) {
        Text(this.errorMsg)
          .fontSize(Tokens.typeCaption)
          .fontColor($r('app.color.err'))
          .width('100%')
      }

      Row({ space: 4 }) {
        this.modeSeg('仓库', 'repo')
        this.modeSeg('PR', 'pr')
        this.modeSeg('无仓库', 'none')
        if (!this.hideBranch && this.repoMode === 'repo') {
          HuChip({
            label: this.selectedBranch.length > 0 ? this.selectedBranch : 'main',
            on: false,
            maxVp: 140,
            onTap: () => {
              this.openSheet('branch');
            }
          })
        }
      }
      .width('100%')

      if (this.repoMode === 'none') {
        Text(usesNamedEnv(this.env) ? `使用云环境 ${this.env.name}` : '不绑定仓库，适合纯问答或规划。')
          .fontSize(Tokens.typeCaption)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ top: 12 })
      } else {
        if (this.repoMode === 'pr') {
          TextInput({ text: this.selectedPrUrl, placeholder: 'GitHub 或 Origin 的 PR 链接' })
            .height(Tokens.touchMin)
            .width('100%')
            .fontSize(Tokens.typeCallout)
            .placeholderFont({ size: Tokens.typeCallout, weight: FontWeight.Regular })
            .placeholderColor($r('app.color.text_placeholder'))
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.field_bg'))
            .borderRadius(Tokens.radiusField)
            .onChange((v: string) => {
              this.selectedPrUrl = v;
              this.vm.selectedPrUrl = v;
              this.refreshCanSubmit();
            })
        }
        TextInput({ text: this.repoQuery, placeholder: '搜索名称，或粘贴仓库 URL' })
          .height(Tokens.touchMin)
          .width('100%')
          .fontSize(Tokens.typeCallout)
          .placeholderFont({ size: Tokens.typeCallout, weight: FontWeight.Regular })
          .placeholderColor($r('app.color.text_placeholder'))
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.field_bg'))
          .borderRadius(Tokens.radiusField)
          .onChange((v: string) => {
            this.repoQuery = v;
            this.vm.repoQuery = v;
            this.repos = this.vm.filteredRepos();
          })

        List({ space: 8 }) {
          if (looksLikeRepoUrl(this.repoQuery)) {
            ListItem() {
              SheetPickRow({
                title: this.repoQuery.trim(),
                caption: '使用粘贴的地址',
                selected: false,
                onTap: () => {
                  this.vm.setManualRepoUrl(this.repoQuery);
                  this.applyRepoSelection(this.vm.selectedRepo);
                  this.closeSheet();
                  this.refreshCanSubmit();
                }
              })
            }
          }
          ForEach(this.repos, (r: RepoInfo) => {
            ListItem() {
              SheetPickRow({
                title: this.repoSheetName(r),
                caption: r.owner,
                selected: this.selectedRepo === r.repository,
                onTap: () => {
                  this.applyRepoSelection(r.repository);
                  this.closeSheet();
                  this.refreshCanSubmit();
                }
              })
            }
          }, (r: RepoInfo) => r.repository)
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
    .backgroundColor($r('app.color.bg0'))
  }

  @Builder
  optionsSheet() {
    Column({ space: Tokens.sheetGap }) {
      Row() {
        Text('更多')
          .fontSize(Tokens.typeHeadline)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        HuTextButton({
          label: '完成',
          color: $r('app.color.text_secondary'),
          compact: true,
          onTap: () => {
            this.closeSheet();
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: Tokens.sheetGap }) {
          Text('任务')
            .fontSize(Tokens.typeCaption)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start }) {
            HuChip({
              label: '自动创建 PR',
              on: this.autoCreatePR,
              onTap: () => {
                this.autoCreatePR = !this.autoCreatePR;
                this.vm.autoCreatePR = this.autoCreatePR;
                this.refreshCanSubmit();
              }
            })
              .margin({ right: 6, bottom: 6 })
            HuChip({
              label: '推送到当前分支',
              on: this.workOnCurrentBranch,
              onTap: () => {
                this.workOnCurrentBranch = !this.workOnCurrentBranch;
                this.vm.workOnCurrentBranch = this.workOnCurrentBranch;
              }
            })
              .margin({ right: 6, bottom: 6 })
            if (this.autoCreatePR && !isOriginRepo(this.selectedRepo)) {
              HuChip({
                label: '以 Cursor App 开 PR',
                on: this.openAsCursorGithubApp,
                onTap: () => {
                  this.openAsCursorGithubApp = !this.openAsCursorGithubApp;
                  this.vm.openAsCursorGithubApp = this.openAsCursorGithubApp;
                }
              })
                .margin({ right: 6, bottom: 6 })
            }
            if (this.autoCreatePR) {
              HuChip({
                label: '跳过自己评审',
                on: this.skipReviewerRequest,
                onTap: () => {
                  this.skipReviewerRequest = !this.skipReviewerRequest;
                  this.vm.skipReviewerRequest = this.skipReviewerRequest;
                }
              })
                .margin({ right: 6, bottom: 6 })
            }
          }
          .width('100%')

          this.capabilityBlock()

          Text('名称')
            .fontSize(Tokens.typeCaption)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          TextInput({ text: this.agentName, placeholder: '空着则按任务自动起名' })
            .height(Tokens.touchMin)
            .width('100%')
            .constraintSize({ minHeight: Tokens.touchMin, maxHeight: Tokens.touchMin })
            .fontSize(Tokens.typeCallout)
            .placeholderFont({ size: Tokens.typeCallout, weight: FontWeight.Regular })
            .placeholderColor($r('app.color.text_placeholder'))
            .fontColor($r('app.color.text_primary'))
            .maxLength(100)
            .backgroundColor($r('app.color.field_bg'))
            .borderRadius(Tokens.radiusField)
            .onChange((v: string) => {
              this.agentName = v;
              this.vm.agentName = v;
            })
          if (!this.hideBranch) {
            Text('分支')
              .fontSize(Tokens.typeCaption)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
            HuChip({
              label: this.selectedBranch.length > 0 ? this.selectedBranch : 'main',
              on: false,
              maxVp: 200,
              onTap: () => {
                this.openSheet('branch');
              }
            })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
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
    .onDisAppear(() => {
      this.vm.mcpServers = this.mcpServers;
      this.vm.subagents = this.subagents;
      this.vm.envVars = this.envVars;
      this.refreshCanSubmit();
    })
  }

  @Builder
  modelSheet() {
    Column({ space: Tokens.sheetGap }) {
      Row() {
        Text('模型')
          .fontSize(Tokens.typeHeadline)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        HuTextButton({
          label: '关闭',
          color: $r('app.color.text_secondary'),
          compact: true,
          onTap: () => {
            this.closeSheet();
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      if (this.modelsLoading && this.modelGroups.length === 0) {
        Text('正在加载模型…')
          .fontSize(Tokens.typeCallout)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ top: 12, bottom: 12 })
      } else if (this.modelGroups.length === 0) {
        Column({ space: 8 }) {
          Text(this.modelsError.length > 0 ? this.modelsError : '模型列表还没加载出来。')
            .fontSize(Tokens.typeCallout)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Text('重新加载')
            .fontSize(Tokens.typeCallout)
            .fontColor($r('app.color.text_link'))
            .onClick(() => {
              Haptics.click();
              this.ensureModelsLoaded(true);
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 8, bottom: 8 })
      }
      Scroll() {
        ModelPicker({
          selectedModel: this.selectedModel,
          selectedVariantIndex: this.selectedVariantIndex,
          groups: this.modelGroups,
          variantOptions: this.variantOptions,
          variantTitle: this.variantTitle,
          paramRows: this.paramRows,
          paramStamp: this.paramStamp,
          onPick: (id: string) => {
            this.pickModel(id);
            this.refreshCanSubmit();
          },
          onPickParam: (rowId: string, valueIdx: number) => {
            this.pickParam(rowId, valueIdx);
          },
          onPickVariant: (idx: number) => {
            this.selectedVariantIndex = idx;
            this.vm.selectedVariantIndex = idx;
            if (idx >= 0 && idx < this.variantOptions.length) {
              this.selectedVariant = this.variantOptions[idx];
              this.vm.selectedVariant = this.selectedVariant;
            }
            this.refreshModelChip();
            this.refreshCanSubmit();
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring)
    }
    .padding({
      left: Tokens.sheetPadH,
      right: Tokens.sheetPadH,
      top: Tokens.sheetPadTop,
      bottom: Tokens.sheetPadBottom
    })
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.bg0'))
  }

  @Builder
  modelPicker() {
    Column({ space: 8 }) {
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start }) {
        HuChip({
          label: '自动',
          on: this.selectedModel.length === 0,
          onTap: () => {
            this.pickModel('');
            this.refreshCanSubmit();
          }
        })
          .margin({ right: 6, bottom: 4 })
      }
      .width('100%')
      ForEach(this.modelGroups, (g: ModelVendorGroup) => {
        Column({ space: 2 }) {
          Text(g.vendor)
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start }) {
            ForEach(g.items, (m: ModelInfo) => {
              HuChip({
                label: shortModelName(m.displayName ?? m.id),
                on: this.selectedModel === m.id,
                maxVp: 160,
                onTap: () => {
                  this.pickModel(m.id);
                  this.refreshCanSubmit();
                }
              })
                .margin({ right: 6, bottom: 4 })
            }, (m: ModelInfo) => m.id)
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }, (g: ModelVendorGroup) => g.vendor)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  paramBars() {
    Column({ space: 8 }) {
      ForEach(this.paramRows, (row: ModelParamRow, rowIdx: number) => {
        Column({ space: 2 }) {
          Text(row.title)
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start }) {
            ForEach(row.labels, (lab: string, valueIdx: number) => {
              HuChip({
                label: lab,
                on: row.selected === valueIdx,
                onTap: () => {
                  this.pickParam(row.id, valueIdx);
                }
              })
                .margin({ right: 6, bottom: 4 })
            }, (lab: string, valueIdx: number) => `${row.id}-${valueIdx}-${lab}-${row.selected}`)
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }, (row: ModelParamRow) => row.id)
    }
    .width('100%')
    .padding({ top: 6 })
    .border({ width: { top: 1 }, color: $r('app.color.border') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  variantBar() {
    Column({ space: 2 }) {
      Text(this.variantTitle)
        .fontSize(Tokens.typeMicro)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start }) {
        ForEach(this.variantOptions, (v: string, idx: number) => {
          HuChip({
            label: v,
            on: this.selectedVariantIndex === idx,
            onTap: () => {
              this.selectedVariantIndex = idx;
              this.vm.selectedVariantIndex = idx;
              this.selectedVariant = v;
              this.vm.selectedVariant = v;
              this.refreshCanSubmit();
            }
          })
            .margin({ right: 6, bottom: 4 })
        }, (v: string, idx: number) => `var-${idx}-${v}`)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ top: 6 })
    .border({ width: { top: 1 }, color: $r('app.color.border') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  capabilityBlock() {
    Column({ space: 10 }) {
      Text('执行环境')
        .fontSize(Tokens.typeMicro)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start }) {
        this.envKindChip('default', '默认')
        this.envKindChip('cloud', '云环境')
        this.envKindChip('pool', '自建池')
        this.envKindChip('machine', '机器')
      }
      .width('100%')
      .constraintSize({ minHeight: Tokens.touchMin })
      if (this.env.kind === 'cloud') {
        Text('点最近用过的，或填控制台里的环境名')
          .fontSize(Tokens.typeMicro)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
      } else if (this.env.kind === 'pool') {
        Text('填自建 snapshot 池名称')
          .fontSize(Tokens.typeMicro)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
      } else if (this.env.kind === 'machine') {
        Text('填已登记的机器名')
          .fontSize(Tokens.typeMicro)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
      }
      if (this.env.kind !== 'default') {
        TextInput({ text: this.env.name, placeholder: '环境名称' })
          .height(Tokens.touchMin)
          .width('100%')
          .fontSize(Tokens.typeCallout)
          .placeholderFont({ size: Tokens.typeCallout, weight: FontWeight.Regular })
          .placeholderColor($r('app.color.text_placeholder'))
          .backgroundColor($r('app.color.field_bg'))
          .borderRadius(Tokens.radiusField)
          .onChange((v: string) => {
            this.env = { kind: this.env.kind, name: v };
            this.vm.env = this.env;
            if (usesNamedEnv(this.env)) {
              this.repoMode = 'none';
              this.vm.repoMode = 'none';
            }
            this.refreshCanSubmit();
          })
      }
      if (this.env.kind === 'cloud' && this.recentEnvs.length > 0) {
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start }) {
          ForEach(this.recentEnvs, (name: string) => {
            HuChip({
              label: name,
              on: this.env.name === name,
              maxVp: 200,
              onTap: () => {
                this.pickRecentEnv(name);
              }
            })
              .margin({ right: 6, bottom: 6 })
          }, (name: string) => `env-${name}`)
        }
        .width('100%')
      }

      Text('MCP')
        .fontSize(Tokens.typeMicro)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
      Text('给 Agent 接外部工具，例如 Linear / 飞书')
        .fontSize(Tokens.typeMicro)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
      McpListEditor({ servers: $mcpServers })

      Row() {
        HuChip({
          label: '高级',
          on: this.showAdvanced,
          onTap: () => {
            this.showAdvanced = !this.showAdvanced;
          }
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      if (this.showAdvanced) {
        Text('子代理')
          .fontSize(Tokens.typeMicro)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
        SubagentListEditor({ items: $subagents })
        Text('环境变量')
          .fontSize(Tokens.typeMicro)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
        EnvVarListEditor({ items: $envVars })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  branchSheet() {
    Column({ space: Tokens.sheetGap }) {
      Text('分支 / ref')
        .fontSize(Tokens.typeHeadline)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      TextInput({ text: this.selectedBranch, placeholder: 'main' })
        .height(Tokens.touchMin)
        .width('100%')
        .fontSize(Tokens.typeCallout)
        .placeholderFont({ size: Tokens.typeCallout, weight: FontWeight.Regular })
        .placeholderColor($r('app.color.text_placeholder'))
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.field_bg'))
        .borderRadius(Tokens.radiusField)
        .padding({ left: 14, right: 14 })
        .onChange((v: string) => {
          this.selectedBranch = v;
          this.vm.selectedBranch = v;
        })
      HuTextButton({
        label: '完成',
        color: $r('app.color.text_primary'),
        compact: true,
        onTap: () => {
          if (this.selectedBranch.trim().length === 0) {
            this.selectedBranch = 'main';
            this.vm.selectedBranch = 'main';
          }
          this.closeSheet();
        }
      })
    }
    .padding({
      left: Tokens.sheetPadH,
      right: Tokens.sheetPadH,
      top: Tokens.sheetPadTop,
      bottom: Tokens.sheetPadBottom
    })
    .width('100%')
    .backgroundColor($r('app.color.bg0'))
  }

  @Builder
  envKindChip(kind: string, label: string) {
    HuChip({
      label: label,
      on: this.env.kind === kind,
      onTap: () => {
        this.setEnvKind(kind);
      }
    })
      .margin({ right: 6, bottom: 6 })
  }
}

