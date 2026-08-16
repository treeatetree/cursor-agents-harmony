import { common } from '@kit.AbilityKit';
import { NewAgentVM } from '../viewmodels/NewAgentVM';
import { InboxVM } from '../viewmodels/InboxVM';
import { CreateDraftStore } from '../store/CreateDraftStore';
import { Tokens } from '../theme/Tokens';
import { BreakpointStore } from '../store/BreakpointStore';
import { PrefStore } from '../store/PrefStore';
import {
  AgentSummary, CustomSubagentDef, EnvTarget, EnvVarDef, McpServerDef, ModelInfo, RepoInfo
} from '../models/Api';
import { Haptics } from '../utils/Haptics';
import { dropPreviewMap, maxPromptImages, pickPromptImages, previewSrc, PromptImage, toApiImages } from '../utils/ImagePicker';
import { HuIconButton } from '../components/HuIconButton';
import { PromptShell } from '../components/PromptShell';
import { EnvVarListEditor, McpListEditor, SubagentListEditor } from '../components/CapabilityEditors';
import { defaultEnv, envNameLabel, hasTools, serializeTools, toolsChipLabel, usesNamedEnv } from '../utils/AgentCapabilities';
import { repoTail } from '../utils/DisplayFmt';
import {
  buildParamRows, groupModels, ModelParamRow, ModelVendorGroup, rowsToParams,
  shortModelName, variantLabel, variantSectionTitle
} from '../utils/ModelGroups';
import { HuChip } from '../components/HuChip';
import { HuTextButton } from '../components/HuTextButton';
import { ModelPicker } from '../components/ModelPicker';
import { StatusBanner } from '../components/StatusBanner';

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
  @State sheetKind: string = '';
  @State repoQuery: string = '';
  @State manualRepoUrl: string = '';
  @State repos: RepoInfo[] = [];
  @State models: ModelInfo[] = [];
  @State modelGroups: ModelVendorGroup[] = [];
  @State variantOptions: string[] = [];
  @State variantTitle: string = '模式';
  @State paramRows: ModelParamRow[] = [];
  @State windowW: number = 360;
  @State topInset: number = 0;
  @State bottomInset: number = 0;
  @State imageNames: string[] = [];
  @State imageUris: string[] = [];
  @State hideBranch: boolean = false;
  @State toolsOn: boolean = false;
  @State toolsLabel: string = '能力';
  @State moreLabel: string = '更多';
  @State showAdvanced: boolean = false;
  private attachedImages: PromptImage[] = [];
  private draftTimer: number = -1;

  aboutToAppear(): void {
    this.topInset = this.embedded ? 8 : this.bp.safeTop();
    this.bottomInset = this.bp.composerBottom();
    this.windowW = this.bp.widthVp;
    this.bp.onChange(() => {
      this.topInset = this.embedded ? 8 : this.bp.safeTop();
      this.bottomInset = this.bp.composerBottom();
      this.windowW = this.bp.widthVp;
    });
    this.vm.hydrateFromCache();
    this.syncFromVm();
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

  private openSheet(kind: string): void {
    this.sheetKind = kind;
    this.showSheet = true;
  }

  private closeSheet(): void {
    this.showSheet = false;
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

  private refreshCanSubmit(): void {
    this.syncVmContext();
    this.hideBranch = this.vm.hideBranchChip();
    this.toolsOn = hasTools(this.env, this.mcpServers, this.subagents, this.envVars);
    this.toolsLabel = toolsChipLabel(this.env, this.mcpServers, this.subagents, this.envVars);
    this.moreLabel = this.moreSummary();
  }

  private moreSummary(): string {
    if (this.toolsOn || this.mode === 'plan' || this.workOnCurrentBranch ||
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
      return;
    }
    for (let i = 0; i < this.models.length; i++) {
      const m = this.models[i];
      if (m.id === this.selectedModel) {
        this.modelDisplayName = m.displayName ?? m.id;
        const rows = buildParamRows(m);
        if (rows.length > 0) {
          this.paramRows = rows;
          this.vm.selectedParams = rowsToParams(rows);
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
        return;
      }
    }
    this.modelDisplayName = this.selectedModel;
    this.vm.selectedParams = [];
  }

  private pickParam(rowIdx: number, valueIdx: number): void {
    const next: ModelParamRow[] = [];
    for (let i = 0; i < this.paramRows.length; i++) {
      const r = this.paramRows[i];
      next.push({
        id: r.id,
        title: r.title,
        labels: r.labels,
        values: r.values,
        selected: i === rowIdx ? valueIdx : r.selected
      });
    }
    this.paramRows = next;
    this.vm.selectedParams = rowsToParams(next);
    this.refreshCanSubmit();
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
    return tail.length > 0 ? tail : this.shortRepo(this.selectedRepo);
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

  private modelLabel(): string {
    if (this.selectedModel.length === 0) {
      return '自动';
    }
    const name = this.modelDisplayName.length > 0 ? this.modelDisplayName : this.selectedModel;
    return shortModelName(name);
  }

  private setRepoMode(mode: string): void {
    this.repoMode = mode;
    this.vm.repoMode = mode;
    if (mode === 'none') {
      this.env = defaultEnv();
      this.vm.env = this.env;
    }
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
    const nowIso = new Date().toISOString();
    const name = this.vm.titleFromPrompt();
    const localId = `local-${Date.now()}`;
    CreateDraftStore.getInstance().park({
      localId: localId,
      prompt: this.vm.prompt.trim(),
      name: name,
      body: this.vm.buildCreateBody()
    });
    const summary: AgentSummary = {
      id: localId,
      name: name,
      status: 'ACTIVE',
      url: '',
      createdAt: nowIso,
      updatedAt: nowIso,
      lastUserAt: nowIso,
      latestRunStatus: 'CREATING'
    };
    InboxVM.getInstance().prependOptimistic(summary);
    PrefStore.getInstance().clearDraft();
    PrefStore.getInstance().setLastTools(serializeTools(this.env, this.mcpServers, this.subagents));
    if (this.selectedModel.length > 0) {
      PrefStore.getInstance().setDefaultModel(this.selectedModel);
    }
    Haptics.success();
    if (this.embedded) {
      this.onCreated(localId);
      return;
    }
    const param: Record<string, Object> = {};
    param['agentId'] = localId;
    param['seed'] = '1';
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
  formColumn() {
    Column() {
      if (this.embedded) {
        Text('新任务')
          .fontSize(Tokens.typeCaption)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 2, bottom: 4 })
      } else {
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

      if (this.errorMsg.length > 0) {
        StatusBanner({
          text: this.errorMsg,
          tone: 'danger'
        })
      }

      Column() {
        PromptShell({
          placeholder: '要做什么？目标和约束',
          text: $prompt,
          busy: this.busy,
          status: '',
          repo: this.repoChipLabel(),
          modelLabel: this.modelLabel(),
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
            this.repoQuery = '';
            this.vm.repoQuery = '';
            this.repos = this.vm.filteredRepos();
            this.openSheet('repo');
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
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Start)
      .padding({ top: 8, bottom: this.bottomInset })
      .animation({ duration: Tokens.motionMs, curve: Curve.FastOutSlowIn })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg0'))
    .bindSheet($$this.showSheet, this.sheetBody(), {
      height: this.sheetKind === 'branch' || this.sheetKind === 'model' ? SheetSize.FIT_CONTENT :
        SheetSize.LARGE,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('app.color.overlay')
    })
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
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('仓库')
          .fontSize(17)
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
            await this.vm.loadMeta(true);
            this.syncFromVm();
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
      }
      .width('100%')

      if (this.repoMode === 'none') {
        Text('不绑定 GitHub 仓库，适合纯问答或规划。')
          .fontSize(Tokens.typeCaption)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ top: 12 })
      } else {
        if (this.repoMode === 'pr') {
          TextInput({ text: this.selectedPrUrl, placeholder: 'https://github.com/org/repo/pull/123' })
            .height(Tokens.touchMin)
            .width('100%')
            .fontSize(Tokens.typeCallout)
            .backgroundColor($r('app.color.field_bg'))
            .borderRadius(Tokens.radiusField)
            .onChange((v: string) => {
              this.selectedPrUrl = v;
              this.vm.selectedPrUrl = v;
              this.refreshCanSubmit();
            })
        }
        TextInput({ text: this.repoQuery, placeholder: '搜索 owner/repo' })
          .height(Tokens.touchMin)
          .width('100%')
          .fontSize(Tokens.typeCallout)
          .backgroundColor($r('app.color.field_bg'))
          .borderRadius(Tokens.radiusField)
          .onChange((v: string) => {
            this.repoQuery = v;
            this.vm.repoQuery = v;
            this.repos = this.vm.filteredRepos();
          })

        List({ space: 6 }) {
          ForEach(this.repos, (r: RepoInfo) => {
            ListItem() {
              Text(r.repository)
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
                .padding(12)
                .backgroundColor($r('app.color.bg2'))
                .borderRadius(Tokens.radiusMd)
                .onClick(() => {
                  this.selectedRepo = r.repository;
                  this.vm.selectedRepo = r.repository;
                  this.closeSheet();
                  this.refreshCanSubmit();
                })
            }
          }, (r: RepoInfo) => r.repository)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)

        Row({ space: 8 }) {
          TextInput({ text: this.manualRepoUrl, placeholder: '或粘贴 https://github.com/org/repo' })
            .layoutWeight(1)
            .height(Tokens.touchMin)
            .fontSize(Tokens.typeCallout)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.field_bg'))
            .borderRadius(Tokens.radiusField)
            .padding({ left: 12, right: 12 })
            .onChange((v: string) => {
              this.manualRepoUrl = v;
            })
          HuTextButton({
            label: '应用',
            color: $r('app.color.text_primary'),
            onTap: () => {
              this.vm.setManualRepoUrl(this.manualRepoUrl);
              this.selectedRepo = this.vm.selectedRepo;
              this.closeSheet();
              this.refreshCanSubmit();
            }
          })
        }
        .width('100%')
      }
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg1'))
  }

  @Builder
  optionsSheet() {
    Scroll() {
      Column({ space: 14 }) {
        Text('更多')
          .fontSize(Tokens.typeHeadline)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')

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
          if (this.autoCreatePR) {
            HuChip({
              label: '以 Cursor App 开 PR',
              on: this.openAsCursorGithubApp,
              onTap: () => {
                this.openAsCursorGithubApp = !this.openAsCursorGithubApp;
                this.vm.openAsCursorGithubApp = this.openAsCursorGithubApp;
              }
            })
              .margin({ right: 6, bottom: 6 })
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
          .fontSize(Tokens.typeCallout)
          .maxLength(100)
          .backgroundColor($r('app.color.field_bg'))
          .borderRadius(Tokens.radiusField)
          .onChange((v: string) => {
            this.agentName = v;
            this.vm.agentName = v;
          })
        Text('模式')
          .fontSize(Tokens.typeCaption)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Row({ space: 6 }) {
          HuChip({
            label: 'agent',
            on: this.mode !== 'plan',
            onTap: () => {
              this.mode = 'agent';
              this.vm.mode = 'agent';
              this.refreshCanSubmit();
            }
          })
          HuChip({
            label: 'plan',
            on: this.mode === 'plan',
            onTap: () => {
              this.mode = 'plan';
              this.vm.mode = 'plan';
              this.refreshCanSubmit();
            }
          })
        }
        .width('100%')
        .constraintSize({ minHeight: Tokens.touchMin })
        .justifyContent(FlexAlign.Start)
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
      .padding(16)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.bg1'))
    .onDisAppear(() => {
      this.vm.mcpServers = this.mcpServers;
      this.vm.subagents = this.subagents;
      this.vm.envVars = this.envVars;
      this.refreshCanSubmit();
    })
  }

  @Builder
  modelSheet() {
    Column({ space: 10 }) {
      Text('模型')
        .fontSize(Tokens.typeHeadline)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      ModelPicker({
        selectedModel: this.selectedModel,
        selectedVariantIndex: this.selectedVariantIndex,
        groups: this.modelGroups,
        variantOptions: this.variantOptions,
        variantTitle: this.variantTitle,
        paramRows: this.paramRows,
        onPick: (id: string) => {
          this.pickModel(id);
          this.refreshCanSubmit();
        },
        onPickParam: (rowIdx: number, valueIdx: number) => {
          this.pickParam(rowIdx, valueIdx);
        },
        onPickVariant: (idx: number) => {
          this.selectedVariantIndex = idx;
          this.vm.selectedVariantIndex = idx;
          if (idx >= 0 && idx < this.variantOptions.length) {
            this.selectedVariant = this.variantOptions[idx];
            this.vm.selectedVariant = this.selectedVariant;
          }
          this.refreshCanSubmit();
        }
      })
    }
    .padding(16)
    .width('100%')
    .backgroundColor($r('app.color.bg1'))
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
                  this.pickParam(rowIdx, valueIdx);
                }
              })
                .margin({ right: 6, bottom: 4 })
            }, (lab: string, valueIdx: number) => `${row.id}-${valueIdx}-${lab}`)
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
      Text('能力')
        .fontSize(Tokens.typeCaption)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
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
        Text('填 Cursor 控制台里的环境名')
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
          .backgroundColor($r('app.color.field_bg'))
          .borderRadius(Tokens.radiusField)
          .onChange((v: string) => {
            this.env = { kind: this.env.kind, name: v };
            this.vm.env = this.env;
            this.refreshCanSubmit();
          })
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

      HuChip({
        label: '高级',
        on: this.showAdvanced,
        onTap: () => {
          this.showAdvanced = !this.showAdvanced;
        }
      })
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
    Column({ space: 12 }) {
      Text('分支 / ref')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      TextInput({ text: this.selectedBranch, placeholder: 'main' })
        .height(Tokens.touchMin)
        .width('100%')
        .fontSize(Tokens.typeCallout)
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
    .padding(16)
    .width('100%')
    .backgroundColor($r('app.color.bg1'))
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

