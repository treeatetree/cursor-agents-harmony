import { common } from '@kit.AbilityKit';
import { SessionVM } from '../viewmodels/SessionVM';
import { InboxVM } from '../viewmodels/InboxVM';
import { DetailVM } from '../viewmodels/DetailVM';
import { Tokens } from '../theme/Tokens';
import { applyAppFont, registerAppFonts } from '../theme/AppFonts';
import { AgentCard } from '../components/AgentCard';
import { InboxFilterBar } from '../components/InboxFilterBar';
import { EmptyState } from '../components/EmptyState';
import { SkeletonList } from '../components/SkeletonList';
import { AgentSummary } from '../models/Api';
import { BreakpointStore } from '../store/BreakpointStore';
import { PrefStore } from '../store/PrefStore';
import { AgentCache } from '../store/AgentCache';
import { UnreadItem, UnreadStore } from '../store/UnreadStore';
import { NetworkMonitor } from '../utils/NetworkMonitor';
import { Haptics } from '../utils/Haptics';
import { expandTransition, fadeTransition, motionMs, runLayout } from '../utils/Motion';
import { NetworkBanner } from '../components/NetworkBanner';
import { StatusBanner } from '../components/StatusBanner';
import { CreateDraftStore } from '../store/CreateDraftStore';
import { HuAvatar, HuAvatarPicker } from '../components/HuAvatar';
import { HuButton } from '../components/HuButton';
import { HuIcon } from '../components/HuIcon';
import { HuIconButton } from '../components/HuIconButton';
import { HuTextButton } from '../components/HuTextButton';
import { normalizeAvatarId } from '../utils/AvatarPresets';
import { confirmDanger } from '../utils/AppDialog';
import { showToast } from '../utils/AppToast';
import { SettingsPageBuilder } from './SettingsPage';
import { NewAgentPage, NewAgentPageBuilder } from './NewAgentPage';
import { AgentDetailPageBuilder } from './AgentDetailPage';
import { InAppBrowserPageBuilder, shouldUseInAppBrowser } from './InAppBrowserPage';
import { shortAgentId } from '../utils/DisplayFmt';
import { pushInAppBrowser } from '../utils/WebLinks';
import {
  FilterMode,
  GroupMode,
  SortMode,
  GroupBucket,
  CardPair,
  applyInboxQuery,
  groupAgents,
  isPinnedId,
  pairAgents
} from '../utils/InboxGrouping';

const GROUP_ALL_COLLAPSED = '__none__';

@Entry
@Component
struct Index {
  @Provide('navPathStack') navStack: NavPathStack = new NavPathStack();
  private session: SessionVM = SessionVM.getInstance();
  private inbox: InboxVM = InboxVM.getInstance();
  private bpStore: BreakpointStore = BreakpointStore.getInstance();

  @State ready: boolean = false;
  @State hasKey: boolean = false;
  @State keyReady: boolean = false;
  @State email: string = '';
  @State userName: string = '';
  @State maskedKey: string = '';
  @State errorMsg: string = '';
  @State inboxError: string = '';
  @State inboxLoading: boolean = false;
  @State inboxRefreshing: boolean = false;
  @State loadedOnce: boolean = false;
  @State agentCount: number = 0;
  @State useSplit: boolean = false;
  @State pagePad: number = 16;
  @State topInset: number = 0;
  @State bottomInset: number = 0;
  @State online: boolean = true;
  @State isRefreshing: boolean = false;
  @State includeArchived: boolean = false;
  @State prUrlFilter: string = '';
  @State showPrFilter: boolean = false;
  @State prUrlInput: string = '';
  @State authExpired: boolean = false;
  @State needsPlanUpgrade: boolean = false;
  @State menuAgentId: string = '';
  @State menuAgentName: string = '';
  @State menuAgentUrl: string = '';
  @State menuAgentStatus: string = '';
  @State menuAgentPinned: boolean = false;
  @State pinnedIds: string[] = [];
  @State showChromeSheet: boolean = false;
  @State showNewSheet: boolean = false;
  @State keyboardInset: number = 0;
  @State actionBanner: string = '';
  @State actionKind: string = '';
  @State chromeKind: string = '';
  @State pressKey: string = '';
  @State avatarPreset: string = 'iridescent';
  private pollTimer: number = -1;

  // Inbox toolbar state
  @State query: string = '';
  @State filterMode: FilterMode = 'all';
  @State sortMode: SortMode = 'updated';
  @State groupMode: GroupMode = 'none';
  @State selectedId: string = '';
  @State inboxOpen: boolean = true;
  @State expandedKey: string = '';
  @StorageLink('readPrefRev') readPrefRev: number = 0;
  @StorageLink('pendingAgentRev') @Watch('onPendingRev') pendingAgentRev: number = 0;
  @StorageLink('pendingUnreadRev') @Watch('onPendingUnread') pendingUnreadRev: number = 0;

  // Computed view models — re-derived whenever query/filter/sort/group/source changes.
  @State flatItems: AgentSummary[] = [];
  @State buckets: GroupBucket[] = [];
  @State filteredCount: number = 0;
  @State runningCount: number = 0;
  @State unreadLine: string = '';
  @State unreadIds: string[] = [];
  @State unreadItems: UnreadItem[] = [];

  aboutToAppear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    try {
      registerAppFonts(this.getUIContext());
      applyAppFont(ctx.getApplicationContext());
    } catch (_e) {
      registerAppFonts();
    }
    NetworkMonitor.getInstance().start();
    NetworkMonitor.getInstance().onChange((v: boolean) => {
      this.online = v;
      if (v && this.hasKey && this.session.keyReady) {
        this.inbox.refresh(true).then(() => {
          this.pullInboxUi();
        });
        const active = DetailVM.getActive();
        if (active) {
          active.resumeIfNeeded();
        }
      }
    });
    this.online = NetworkMonitor.getInstance().online;
    this.bpStore.onChange(() => {
      this.syncBreakpoint();
    });
    // Split mode keeps Index painted — Settings save must push state via SessionVM.onChange.
    this.inbox.onChange(() => {
      this.pullInboxUi();
    });
    this.session.onChange(() => {
      const hadKey = this.hasKey;
      this.refreshSession();
      this.pullInboxUi();
      if (this.hasKey && !hadKey && this.session.keyReady) {
        this.inbox.startWatch();
        this.inbox.refresh(true).then(() => {
          this.pullInboxUi();
        });
        this.startPoll();
      } else if (!this.hasKey) {
        this.inbox.stopWatch();
        this.stopPoll();
      }
    });
    this.syncBreakpoint();
    const ctxReady = Promise.all([
      this.session.hydrate(ctx),
      this.inbox.bootstrap(ctx)
    ]);
    ctxReady.then(async () => {
      await this.loadInboxPrefs();
      this.refreshSession();
      this.pullInboxUi();
      this.session.unlockAndValidate().then(() => {
        this.refreshSession();
        this.pullInboxUi();
        if (this.hasKey && this.session.keyReady) {
          this.inbox.startWatch();
          this.inbox.refresh(true).then(() => {
            this.pullInboxUi();
          });
          this.startPoll();
        }
        this.consumePendingAgent();
        this.consumePendingUnread();
      });
    }).catch(() => {
      this.ready = true;
    });
  }

  aboutToDisappear(): void {
    this.stopPoll();
  }

  onPageShow(): void {
    this.consumePendingAgent();
    this.consumePendingUnread();
    this.refreshSession();
    this.pullInboxUi();
    PrefStore.getInstance().getAvatarPreset().then((id: string) => {
      this.avatarPreset = normalizeAvatarId(id);
    });
    PrefStore.getInstance().getPinnedIds().then((ids: string[]) => {
      this.pinnedIds = ids;
      this.recomputeView();
    });
    if (this.hasKey && this.session.keyReady) {
      this.inbox.refresh(true).then(() => {
        this.pullInboxUi();
      });
    }
    if (this.hasKey && this.session.keyReady) {
      this.inbox.startWatch();
      this.startPoll();
    }
  }

  onPageHide(): void {
    this.stopPoll();
  }

  private startPoll(): void {
    this.stopPoll();
    this.pollTimer = setInterval(() => {
      if (!this.hasKey) {
        return;
      }
      this.inbox.refresh(true).then(() => {
        this.pullInboxUi();
      });
    }, 8000) as number;
  }

  private stopPoll(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private openBrowser(url: string, title: string = 'Web'): void {
    if (!url) {
      return;
    }
    if (shouldUseInAppBrowser(url)) {
      pushInAppBrowser(this.navStack, url, title);
      return;
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    ctx.openLink(url).catch(() => {
    });
  }

  private syncBreakpoint(): void {
    this.useSplit = this.bpStore.useSplit;
    this.pagePad = Tokens.pagePad;
    this.topInset = this.bpStore.safeTop();
    this.bottomInset = this.bpStore.bottomInsetVp;
    this.keyboardInset = this.bpStore.keyboardInsetVp;
  }

  private refreshSession(): void {
    this.session.syncFromStore();
    this.ready = this.session.ready;
    this.hasKey = this.session.hasKey;
    this.keyReady = this.session.keyReady;
    this.email = this.session.email;
    this.userName = this.session.userName;
    this.maskedKey = this.session.maskedKey;
    this.errorMsg = this.session.errorMsg;
  }

  private pullInboxUi(): void {
    this.inboxError = this.inbox.errorMsg;
    this.agentCount = this.inbox.source.totalCount();
    this.inboxLoading = this.inbox.refreshing || (this.inbox.loading && this.agentCount === 0);
    this.inboxRefreshing = this.inbox.refreshing;
    this.loadedOnce = this.inbox.loadedOnce;
    this.includeArchived = this.inbox.includeArchived;
    this.prUrlFilter = this.inbox.prUrlFilter;
    this.authExpired = this.inbox.authExpired;
    this.needsPlanUpgrade = this.inbox.needsPlanUpgrade;
    this.actionBanner = this.inbox.actionBanner;
    this.actionKind = this.inbox.actionKind;
    this.runningCount = this.inbox.runningCount();
    const unread = UnreadStore.getInstance();
    this.unreadLine = unread.headline();
    this.unreadIds = unread.ids();
    this.unreadItems = unread.peek();
    this.recomputeView();
  }

  /** Recompute flat / grouped view models from the inbox source + current toolbar state. */
  private recomputeView(): void {
    const all = this.inbox.source.snapshot();
    const filtered = applyQueryInternal(all, this.query, this.filterMode, this.sortMode, this.pinnedIds);
    const grouped = groupAgents(filtered, this.groupMode, this.pinnedIds);
    let hasNamed = false;
    let n = 0;
    for (let i = 0; i < grouped.length; i++) {
      n += grouped[i].items.length;
      if (grouped[i].label.length > 0) {
        hasNamed = true;
      }
    }
    this.filteredCount = n;
    if (this.groupMode === 'none' && !hasNamed) {
      this.flatItems = filtered;
      this.buckets = [];
    } else {
      this.buckets = grouped;
      this.flatItems = [];
    }
  }

  private async loadInboxPrefs(): Promise<void> {
    const prefs = PrefStore.getInstance();
    const group = await prefs.getInboxGroup();
    if (group === 'time' || group === 'status' || group === 'none' || group === 'repo') {
      this.groupMode = group as GroupMode;
    }
    const sort = await prefs.getInboxSort();
    if (sort === 'created' || sort === 'name' || sort === 'updated') {
      this.sortMode = sort as SortMode;
    }
    this.inboxOpen = await prefs.getInboxOpen();
    const showArchived = await prefs.getIncludeArchived();
    this.includeArchived = showArchived;
    this.inbox.setIncludeArchived(showArchived);
    this.expandedKey = await prefs.getInboxExpanded();
    this.pinnedIds = await prefs.getPinnedIds();
    this.avatarPreset = normalizeAvatarId(await prefs.getAvatarPreset());
  }

  private pickAvatar(id: string): void {
    this.avatarPreset = normalizeAvatarId(id);
    PrefStore.getInstance().setAvatarPreset(this.avatarPreset);
  }

  private persistInboxChrome(): void {
    const prefs = PrefStore.getInstance();
    prefs.setInboxGroup(this.groupMode);
    prefs.setInboxSort(this.sortMode);
  }

  private hasBucketKey(key: string): boolean {
    for (let i = 0; i < this.buckets.length; i++) {
      if (this.buckets[i].key === key) {
        return true;
      }
    }
    return false;
  }

  private openGroupKey(): string {
    if (this.expandedKey === GROUP_ALL_COLLAPSED) {
      return '';
    }
    if (this.expandedKey.length > 0 && this.hasBucketKey(this.expandedKey)) {
      return this.expandedKey;
    }
    if (this.buckets.length > 0) {
      return this.buckets[0].key;
    }
    return '';
  }

  private groupCollapsed(key: string): boolean {
    const open = this.openGroupKey();
    return open.length === 0 || key !== open;
  }

  private toggleGroup(key: string): void {
    Haptics.tick();
    runLayout(() => {
      if (this.openGroupKey() === key) {
        this.expandedKey = GROUP_ALL_COLLAPSED;
      } else {
        this.expandedKey = key;
      }
    });
    PrefStore.getInstance().setInboxExpanded(this.expandedKey);
  }

  private setGroupMode(mode: GroupMode): void {
    runLayout(() => {
      this.groupMode = mode;
      this.expandedKey = '';
      this.recomputeView();
    });
    this.persistInboxChrome();
    PrefStore.getInstance().setInboxExpanded('');
  }

  private setInboxOpen(open: boolean): void {
    runLayout(() => {
      this.inboxOpen = open;
    });
    PrefStore.getInstance().setInboxOpen(open);
  }

  private openPr(url: string): void {
    this.openBrowser(url, 'Pull Request');
  }

  private bindLong(agent: AgentSummary): void {
    this.menuAgentId = agent.id;
    this.menuAgentName = agent.name.length > 0 ? agent.name : shortAgentId(agent.id);
    this.menuAgentUrl = agent.url;
    this.menuAgentStatus = agent.status;
    this.menuAgentPinned = isPinnedId(agent.id, this.pinnedIds);
    this.chromeKind = 'agent';
    this.showChromeSheet = true;
  }

  private openNew(): void {
    Haptics.click();
    this.showNewSheet = true;
  }

  private newSheetHeight(): number | SheetSize {
    return SheetSize.LARGE;
  }

  private retryCreateFromBanner(): void {
    this.inbox.clearActionBanner();
    const draft = CreateDraftStore.getInstance().peek();
    if (!draft) {
      this.openNew();
      return;
    }
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
    const param: Record<string, Object> = {};
    param['agentId'] = draft.localId;
    param['seed'] = '1';
    this.navStack.pushPath({ name: 'AgentDetail', param: param });
  }

  private async togglePin(id: string): Promise<void> {
    const next: string[] = [];
    let found = false;
    for (let i = 0; i < this.pinnedIds.length; i++) {
      if (this.pinnedIds[i] === id) {
        found = true;
      } else {
        next.push(this.pinnedIds[i]);
      }
    }
    if (!found) {
      next.unshift(id);
    }
    this.pinnedIds = next;
    this.menuAgentPinned = !found;
    await PrefStore.getInstance().setPinnedIds(next);
    this.recomputeView();
  }

  onPendingRev(): void {
    this.consumePendingAgent();
  }

  onPendingUnread(): void {
    this.consumePendingUnread();
  }

  private consumePendingUnread(): void {
    let flag = '';
    try {
      flag = AppStorage.get<string>('pendingUnreadSheet') ?? '';
    } catch (_e) {
      flag = '';
    }
    if (flag !== '1') {
      return;
    }
    try {
      AppStorage.setOrCreate('pendingUnreadSheet', '');
    } catch (_e) {
    }
    this.openUnreadSheet();
  }

  private openUnreadSheet(): void {
    this.pullInboxUi();
    if (this.unreadItems.length === 0) {
      return;
    }
    this.chromeKind = 'unread';
    this.showChromeSheet = true;
  }

  private async clearUnread(): Promise<void> {
    Haptics.click();
    await UnreadStore.getInstance().clearAll();
    this.pullInboxUi();
    if (this.chromeKind === 'unread') {
      this.showChromeSheet = false;
    }
  }

  private consumePendingAgent(): void {
    let id = '';
    try {
      const raw = AppStorage.get<string>('pendingAgentId');
      if (raw && raw.length > 0) {
        id = raw;
      }
    } catch (_e) {
    }
    if (id.length === 0) {
      return;
    }
    if (!this.hasKey) {
      return;
    }
    try {
      AppStorage.setOrCreate('pendingAgentId', '');
    } catch (_e) {
    }
    this.openAgent(id);
  }

  private openAgent(id: string): void {
    if (id.length === 0) {
      return;
    }
    Haptics.click();
    this.selectedId = id;
    UnreadStore.getInstance().markSeen(id).then(() => {
      this.pullInboxUi();
    });
    const active = DetailVM.getActive();
    if (active && active.agentId === id) {
      return;
    }
    const param: Record<string, Object> = {};
    param['agentId'] = id;
    try {
      this.navStack.clear();
    } catch (_e) {
    }
    this.navStack.pushPath({ name: 'AgentDetail', param: param });
  }

  private listFooterH(): number {
    return Math.max(this.bottomInset, 24) + 16;
  }

  private showSkeleton(): boolean {
    return this.inboxLoading && this.agentCount === 0 && !this.loadedOnce;
  }

  private showRefreshBar(): boolean {
    return this.inboxRefreshing && this.agentCount > 0;
  }

  @Builder
  pageMap(name: string) {
    if (name === 'Settings') {
      SettingsPageBuilder()
    } else if (name === 'NewAgent') {
      NewAgentPageBuilder()
    } else if (name === 'AgentDetail') {
      AgentDetailPageBuilder()
    } else if (name === 'InAppBrowser') {
      InAppBrowserPageBuilder()
    }
  }

  build() {
    Navigation(this.navStack) {
      Column() {
        if (!this.hasKey) {
          this.topBar()
          NetworkBanner({
            online: this.online,
            onRetry: () => {
              this.inbox.refresh(false).then(() => {
                this.pullInboxUi();
              });
            }
          })
        }

        if (!this.ready) {
          Column() {
            SkeletonList({ rows: 6 })
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ top: this.hasKey ? this.topInset : 0 })
        } else if (!this.hasKey) {
          this.emptyNoKey()
        } else {
          this.inboxBody()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg0'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.showNewSheet, this.newAgentSheet(), {
        height: this.newSheetHeight(),
        detents: [SheetSize.LARGE],
        dragBar: true,
        showClose: false,
        backgroundColor: $r('app.color.overlay')
      })
    }
    .navDestination(this.pageMap)
    .mode(this.useSplit ? NavigationMode.Split : NavigationMode.Stack)
    .navBarWidth(this.useSplit ? (this.inboxOpen ? Tokens.splitMasterVp : Tokens.splitRailVp) : '100%')
    .animation({ duration: motionMs(), curve: Curve.FastOutSlowIn })
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg0'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  topBar() {
    Row() {
      Blank()
      HuIconButton({
        name: 'settings',
        label: '设置',
        iconColor: $r('app.color.text_secondary'),
        onTap: () => {
          this.navStack.pushPath({ name: 'Settings' });
        }
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: this.pagePad,
      right: this.pagePad,
      top: this.topInset + 2,
      bottom: 6
    })
  }

  @Builder
  emptyNoKey() {
    Column({ space: Tokens.space3 }) {
      Text('Cursor Agents')
        .fontSize(Tokens.typeTitle)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text('粘贴个人 API Key，在鸿蒙上指挥云端 Agent。\n与 cursor.com/agents 共用同一批任务。')
        .fontSize(Tokens.typeBody)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .lineHeight(Tokens.lineBody)
        .padding({ left: 28, right: 28 })
      HuButton({
        label: '粘贴 API Key',
        variant: 'primary',
        onTap: () => {
          this.navStack.pushPath({ name: 'Settings' });
        }
      })
        .margin({ top: 8 })
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .constraintSize({ maxWidth: 560 })
  }

  @Builder
  inboxRail() {
    Column({ space: Tokens.space2 }) {
      HuIconButton({
        name: 'chevronRight',
        label: '展开列表',
        iconColor: $r('app.color.text_secondary'),
        onTap: () => {
          this.setInboxOpen(true);
        }
      })
      HuAvatar({
        preset: this.avatarPreset,
        box: Tokens.touchMin,
        onTap: () => {
          this.chromeKind = 'account';
          this.showChromeSheet = true;
        }
      })
      HuIconButton({
        name: 'plus',
        label: '新建任务',
        filled: true,
        onTap: () => {
          this.openNew();
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.topInset + 2 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  inboxBody() {
    if (this.useSplit && !this.inboxOpen) {
      this.inboxRail()
    } else {
    Column() {
        if (this.showRefreshBar()) {
          Progress({ value: 0, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(2)
            .color($r('app.color.accent'))
            .style({ strokeWidth: 2, enableSmoothEffect: true })
        }

        if (this.keyReady && (this.authExpired || (this.errorMsg.length > 0 && this.errorMsg.indexOf('API Key') >= 0))) {
          StatusBanner({
            text: this.authExpired ? 'API Key 失效，请重新粘贴' : this.errorMsg,
            tone: 'danger',
            action: '去设置',
            onAction: () => {
              this.navStack.pushPath({ name: 'Settings' });
            }
          })
        } else if (this.errorMsg.length > 0) {
          StatusBanner({
            text: this.errorMsg,
            tone: 'danger',
            action: '去设置',
            onAction: () => {
              this.navStack.pushPath({ name: 'Settings' });
            }
          })
        }

        if (this.needsPlanUpgrade) {
          StatusBanner({
            text: '套餐不足，打开 Dashboard 升级',
            tone: 'warn',
            action: '升级',
            onAction: () => {
              this.openBrowser('https://cursor.com/dashboard', 'Dashboard');
            }
          })
        }

        if (this.inboxError.length > 0 && !this.authExpired && !this.needsPlanUpgrade) {
          StatusBanner({
            text: this.inboxError,
            tone: 'warn',
            action: '重试',
            onAction: () => {
              this.inbox.refresh(false).then(() => {
                this.pullInboxUi();
              });
            }
          })
        }

        if (this.actionBanner.length > 0) {
          StatusBanner({
            text: this.actionBanner,
            tone: 'danger',
            action: this.actionKind === 'retry-create' ? '重试' : '',
            onAction: () => {
              this.retryCreateFromBanner();
            }
          })
        }

        // Filter bar — always visible once we have data (or once first load finished)
        InboxFilterBar({
          query: this.query,
          filter: this.filterMode,
          sort: this.sortMode,
          group: this.groupMode,
          count: this.filteredCount,
          total: this.agentCount,
          refreshing: this.inboxRefreshing,
          includeArchived: this.includeArchived,
          prActive: this.prUrlFilter.length > 0 || this.showPrFilter,
          pad: this.pagePad,
          topInset: this.topInset,
          compact: this.useSplit,
          hideSearch: this.bpStore.bp === 'sm',
          avatarPreset: this.avatarPreset,
          onQuery: (s: string) => {
            this.query = s;
            this.recomputeView();
          },
          onFilter: (m: FilterMode) => {
            runLayout(() => {
              this.filterMode = m;
              this.recomputeView();
            });
          },
          onSort: (m: SortMode) => {
            runLayout(() => {
              this.sortMode = m;
              this.recomputeView();
            });
            this.persistInboxChrome();
          },
          onGroup: (m: GroupMode) => {
            this.setGroupMode(m);
          },
          onToggleArchived: async () => {
            const next = !this.includeArchived;
            this.inbox.setIncludeArchived(next);
            this.includeArchived = next;
            PrefStore.getInstance().setIncludeArchived(next);
            await this.inbox.refresh(false);
            this.pullInboxUi();
          },
          onTogglePr: () => {
            this.prUrlInput = this.prUrlFilter;
            this.showPrFilter = !this.showPrFilter;
          },
          onRefresh: async () => {
            await this.inbox.refresh(false);
            this.pullInboxUi();
          },
          onSettings: () => {
            this.navStack.pushPath({ name: 'Settings' });
          },
          onAvatar: () => {
            this.chromeKind = 'account';
            this.showChromeSheet = true;
          },
          onNew: () => {
            this.openNew();
          },
          onCollapse: () => {
            this.setInboxOpen(false);
          }
        })
        if (!this.online) {
          StatusBanner({
            text: '网络已断开 · 显示缓存内容',
            tone: 'warn',
            action: '重试',
            onAction: () => {
              this.inbox.refresh(false).then(() => {
                this.pullInboxUi();
              });
            }
          })
        }

        if (this.unreadLine.length > 0) {
          StatusBanner({
            text: this.unreadLine,
            tone: 'info',
            action: '查看',
            onAction: () => {
              this.openUnreadSheet();
            }
          })
        }

        if (this.showPrFilter) {
          Row({ space: 8 }) {
            TextInput({ text: this.prUrlInput, placeholder: '粘贴 PR URL 按此筛选' })
              .fontSize(Tokens.typeCaption)
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.bg1'))
              .border({ width: 1, color: $r('app.color.border') })
              .borderRadius(Tokens.radiusField)
              .height(Tokens.touchMin)
              .layoutWeight(1)
              .onChange((v: string) => {
                this.prUrlInput = v;
              })
            HuTextButton({
              label: '应用',
              color: $r('app.color.accent'),
              onTap: async () => {
                this.inbox.setPrUrlFilter(this.prUrlInput.trim());
                this.showPrFilter = false;
                await this.inbox.refresh(false);
                this.pullInboxUi();
              }
            })
            if (this.prUrlFilter.length > 0) {
              HuTextButton({
                label: '清除',
                onTap: async () => {
                  this.prUrlInput = '';
                  this.inbox.setPrUrlFilter('');
                  this.showPrFilter = false;
                  await this.inbox.refresh(false);
                  this.pullInboxUi();
                }
              })
            }
          }
          .width('100%')
          .padding({ left: this.pagePad, right: this.pagePad, top: 4, bottom: 8 })
        }

        if (this.showSkeleton()) {
          Column() {
            SkeletonList({ rows: 6 })
          }
          .layoutWeight(1)
          .width('100%')
        } else if (this.agentCount === 0 && !this.inboxLoading) {
          Column() {
            EmptyState({
              title: '还没有任务',
              subtitle: '点右上角 +，写一句要做的事。',
              actionLabel: '新建任务',
              onAction: () => {
                this.openNew();
              }
            })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .width('100%')
        } else if (this.filteredCount === 0) {
          Column() {
            EmptyState({
              title: '没有匹配的任务',
              subtitle: '试试调整筛选，或点右上角 + 新建。',
              actionLabel: '查看全部',
              onAction: () => {
                this.query = '';
                this.filterMode = 'all';
                this.sortMode = 'updated';
                this.recomputeView();
              }
            })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .width('100%')
        } else {
          this.renderView()
        }
    }
    .width('100%')
    .layoutWeight(1)
    .bindSheet($$this.showChromeSheet, this.chromeSheet(), {
      height: this.chromeKind === 'unread' ? SheetSize.MEDIUM : SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('app.color.overlay')
    })
    }
  }

  @Builder
  renderView() {
    if (this.useSplit) {
      this.listFeed()
    } else {
      this.cardFeed()
    }
  }

  @Builder
  listFeed() {
    Refresh({ refreshing: $$this.isRefreshing }) {
      List({ space: 0 }) {
        if (this.buckets.length === 0) {
          this.listItems(this.flatItems)
        } else {
          ForEach(this.buckets, (bucket: GroupBucket) => {
            if (bucket.label.length > 0) {
              ListItem() {
                this.sectionHeader(bucket)
              }
            }
            if (!this.groupCollapsed(bucket.key)) {
              this.listItems(bucket.items)
            }
          }, (bucket: GroupBucket) => bucket.key)
        }
        ListItem() {
          Column()
            .width('100%')
            .height(this.listFooterH())
        }
      }
      .width('100%')
      .padding({ top: Tokens.space2 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .cachedCount(8)
      .sticky(StickyStyle.Header)
      .onReachEnd(() => {
        this.inbox.loadMore().then(() => {
          this.pullInboxUi();
        });
      })
    }
    .layoutWeight(1)
    .onRefreshing(async () => {
      Haptics.tick();
      this.isRefreshing = true;
      await this.inbox.refresh(false);
      this.pullInboxUi();
      this.isRefreshing = false;
    })
  }

  @Builder
  listItems(items: AgentSummary[]) {
    ForEach(items, (item: AgentSummary) => {
      ListItem() {
        AgentCard({
          agent: item,
          showRepo: this.groupMode !== 'repo',
          preview: AgentCache.getInstance().peekSummary(item.id),
          list: true,
          pinned: isPinnedId(item.id, this.pinnedIds),
          unread: this.unreadIds.indexOf(item.id) >= 0,
          active: item.id === this.selectedId,
          onOpen: (id: string) => {
            this.openAgent(id);
          },
          onLong: (agent: AgentSummary) => {
            this.bindLong(agent);
          },
          onOpenPr: (url: string) => {
            this.openPr(url);
          }
        })
          .padding({
            left: this.pagePad,
            right: this.pagePad,
            bottom: Tokens.space2
          })
      }
      .transition(expandTransition())
    }, (item: AgentSummary) => item.id)
  }

  @Builder
  cardFeed() {
    Refresh({ refreshing: $$this.isRefreshing }) {
      List({ space: 0 }) {
        if (this.buckets.length === 0) {
          this.cardItems(this.flatItems)
        } else {
          ForEach(this.buckets, (bucket: GroupBucket) => {
            if (bucket.label.length > 0) {
              ListItem() {
                this.sectionHeader(bucket)
              }
            }
            if (!this.groupCollapsed(bucket.key)) {
              this.cardItems(bucket.items)
            }
          }, (bucket: GroupBucket) => bucket.key)
        }
        ListItem() {
          Column()
            .width('100%')
            .height(this.listFooterH())
        }
      }
      .width('100%')
      .padding({ top: Tokens.space2 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .cachedCount(6)
      .sticky(StickyStyle.Header)
      .onReachEnd(() => {
        this.inbox.loadMore().then(() => {
          this.pullInboxUi();
        });
      })
    }
    .layoutWeight(1)
    .onRefreshing(async () => {
      Haptics.tick();
      this.isRefreshing = true;
      await this.inbox.refresh(false);
      this.pullInboxUi();
      this.isRefreshing = false;
    })
  }

  @Builder
  sectionHeader(bucket: GroupBucket) {
    Row({ space: 6 }) {
      Column() {
        HuIcon({
          name: 'chevronRight',
          iconSize: 16,
          tint: $r('app.color.text_tertiary')
        })
      }
      .width(16)
      .height(16)
      .rotate({ angle: this.groupCollapsed(bucket.key) ? 0 : 90 })
      .animation({ duration: motionMs(), curve: Curve.FastOutSlowIn })
      Text(bucket.label)
        .fontSize(Tokens.typeCaption)
        .fontFamily(Tokens.fontUi)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .letterSpacing(Tokens.letterGroup)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.groupCollapsed(bucket.key)) {
        Text(`${bucket.items.length}`)
          .fontSize(Tokens.typeMicro)
          .fontColor($r('app.color.text_tertiary'))
          .transition(fadeTransition())
      }
    }
    .width('100%')
    .constraintSize({ minHeight: Tokens.touchMin })
    .alignItems(VerticalAlign.Center)
    .padding({
      left: this.pagePad,
      right: this.pagePad,
      top: this.readPrefRev >= 0 ? Tokens.sec : Tokens.sec,
      bottom: 8
    })
    .backgroundColor($r('app.color.bg0'))
    .onClick(() => {
      this.toggleGroup(bucket.key);
    })
  }

  @Builder
  cardItems(items: AgentSummary[]) {
    ForEach(pairAgents(items), (pair: CardPair) => {
      ListItem() {
        this.cardPairRow(pair)
      }
      .transition(expandTransition())
    }, (pair: CardPair) => pair.key)
  }

  @Builder
  cardPairRow(pair: CardPair) {
    Flex({
      direction: FlexDirection.Row,
      justifyContent: FlexAlign.SpaceBetween,
      alignItems: ItemAlign.Stretch
    }) {
      Column() {
        this.gridCard(pair.left)
      }
      .layoutWeight(1)
      .constraintSize({ minWidth: 0 })
      .margin({ right: pair.hasRight ? Tokens.space2 : 0 })
      if (pair.hasRight) {
        Column() {
          this.gridCard(pair.right)
        }
        .layoutWeight(1)
        .constraintSize({ minWidth: 0 })
      } else {
        Column()
          .layoutWeight(1)
          .constraintSize({ minWidth: 0 })
      }
    }
    .width('100%')
    .padding({
      left: this.pagePad,
      right: this.pagePad,
      bottom: Tokens.space3
    })
  }

  @Builder
  gridCard(item: AgentSummary) {
    AgentCard({
      agent: item,
      showRepo: this.groupMode !== 'repo',
      preview: AgentCache.getInstance().peekSummary(item.id),
      pinned: isPinnedId(item.id, this.pinnedIds),
      unread: this.unreadIds.indexOf(item.id) >= 0,
      onOpen: (id: string) => {
        this.openAgent(id);
      },
      onLong: (agent: AgentSummary) => {
        this.bindLong(agent);
      },
      onOpenPr: (url: string) => {
        this.openPr(url);
      }
    })
      .width('100%')
  }

  @Builder
  newAgentSheet() {
    NewAgentPage({
      embedded: true,
      onCreated: (localId: string) => {
        this.showNewSheet = false;
        const param: Record<string, Object> = {};
        param['agentId'] = localId;
        param['seed'] = '1';
        this.navStack.pushPath({ name: 'AgentDetail', param: param });
      },
      onDismiss: () => {
        this.showNewSheet = false;
      }
    })
  }

  @Builder
  chromeSheet() {
    if (this.chromeKind === 'account') {
      this.accountSheet()
    } else if (this.chromeKind === 'unread') {
      this.unreadSheet()
    } else {
      this.agentMenuSheet()
    }
  }

  @Builder
  unreadSheet() {
    Column({ space: 8 }) {
      Row() {
        Text(this.unreadItems.length > 0 ? `${this.unreadItems.length} 条新结果` : '没有新结果')
          .fontSize(Tokens.typeBody)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        if (this.unreadItems.length > 0) {
          HuTextButton({
            label: '清空',
            color: $r('app.color.accent'),
            onTap: () => {
              this.clearUnread();
            }
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.unreadItems.length === 0) {
        Text('全部已读')
          .fontSize(Tokens.typeCaption)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .padding({ top: 12, bottom: 12 })
      } else {
        List({ space: 8 }) {
          ForEach(this.unreadItems, (it: UnreadItem) => {
            ListItem() {
              Column({ space: 4 }) {
                Text(`${it.name} · ${it.statusZh}`)
                  .fontSize(Tokens.typeCallout)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                if (it.snippet.length > 0) {
                  Text(it.snippet)
                    .fontSize(Tokens.typeCaption)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .backgroundColor($r('app.color.bg2'))
              .borderRadius(Tokens.radiusMd)
              .constraintSize({ minHeight: Tokens.touchMin })
              .onClick(() => {
                this.showChromeSheet = false;
                this.openAgent(it.id);
              })
            }
          }, (it: UnreadItem) => `${it.id}-${it.at}`)
        }
        .width('100%')
        .constraintSize({ maxHeight: 420 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .padding(16)
    .width('100%')
  }

  @Builder
  accountSheet() {
    Column({ space: 2 }) {
      Row({ space: 12 }) {
        HuAvatar({
          preset: this.avatarPreset,
          box: Tokens.touchMin
        })
        Column({ space: 2 }) {
          Text(this.userName.length > 0 ? this.userName : (this.email.length > 0 ? this.email : '账号'))
            .fontSize(Tokens.typeBody)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (this.userName.length > 0 && this.email.length > 0) {
            Text(this.email)
              .fontSize(Tokens.typeCaption)
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ bottom: 8 })
      .alignItems(VerticalAlign.Center)

      Text('头像')
        .fontSize(Tokens.typeCaption)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .padding({ top: 4, bottom: 2 })
      HuAvatarPicker({
        selected: this.avatarPreset,
        onPick: (id: string) => {
          this.pickAvatar(id);
        }
      })

      this.menuBtn('设置', () => {
        this.showChromeSheet = false;
        this.navStack.pushPath({ name: 'Settings' });
      })
      this.menuBtn('刷新 Inbox', async () => {
        this.showChromeSheet = false;
        await this.inbox.refresh(false);
        this.pullInboxUi();
      })

      Text('分组')
        .fontSize(Tokens.typeCaption)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .padding({ top: 10, bottom: 2 })
      this.pickRow('仓库', this.groupMode === 'repo', () => {
        this.setGroupMode('repo');
      })
      this.pickRow('时间', this.groupMode === 'time', () => {
        this.setGroupMode('time');
      })
      this.pickRow('状态', this.groupMode === 'status', () => {
        this.setGroupMode('status');
      })
      this.pickRow('无分组', this.groupMode === 'none', () => {
        this.setGroupMode('none');
      })

      Text('排序')
        .fontSize(Tokens.typeCaption)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .padding({ top: 10, bottom: 2 })
      this.pickRow('最近发送', this.sortMode === 'updated', () => {
        this.sortMode = 'updated';
        this.persistInboxChrome();
        this.recomputeView();
      })
      this.pickRow('创建', this.sortMode === 'created', () => {
        this.sortMode = 'created';
        this.persistInboxChrome();
        this.recomputeView();
      })
      this.pickRow('名称', this.sortMode === 'name', () => {
        this.sortMode = 'name';
        this.persistInboxChrome();
        this.recomputeView();
      })

      this.pickRow(this.prUrlFilter.length > 0 || this.showPrFilter ? '按 PR 筛选 · 开' : '按 PR 筛选',
        this.prUrlFilter.length > 0 || this.showPrFilter, () => {
          this.prUrlInput = this.prUrlFilter;
          this.showPrFilter = !this.showPrFilter;
        })
      this.pickRow(this.includeArchived ? '含归档 · 开' : '含归档', this.includeArchived, async () => {
        const next = !this.includeArchived;
        PrefStore.getInstance().setIncludeArchived(next);
        this.inbox.setIncludeArchived(next);
        this.includeArchived = next;
        await this.inbox.refresh(false);
        this.pullInboxUi();
      })
    }
    .padding(16)
    .width('100%')
  }

  @Builder
  pickRow(label: string, on: boolean, action: () => void) {
    Row() {
      Text(label)
        .fontSize(Tokens.typeProse)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      if (on) {
        HuIcon({
          name: 'check',
          iconSize: 18,
          tint: $r('app.color.text_primary')
        })
      }
    }
    .width('100%')
    .height(44)
    .alignItems(VerticalAlign.Center)
    .opacity(this.pressKey === `pick:${label}` ? 0.7 : 1)
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressKey = `pick:${label}`;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressKey = '';
      }
    })
    .onClick(() => {
      Haptics.tick();
      action();
    })
  }

  @Builder
  agentMenuSheet() {
    Column({ space: 4 }) {
      Text(this.menuAgentName.length > 0 ? this.menuAgentName : shortAgentId(this.menuAgentId))
        .fontSize(Tokens.typeBody)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(shortAgentId(this.menuAgentId))
        .fontSize(Tokens.typeMicro)
        .fontColor($r('app.color.text_tertiary'))
        .fontFamily(Tokens.fontMono)
        .width('100%')
        .padding({ bottom: 8 })
      this.menuBtn(this.menuAgentPinned ? '取消置顶' : '置顶', async () => {
        const wasPinned = this.menuAgentPinned;
        await this.togglePin(this.menuAgentId);
        this.showChromeSheet = false;
        Haptics.success();
        showToast(wasPinned ? '已取消置顶' : '已置顶');
      })
      this.menuBtn('在浏览器打开', () => {
        this.showChromeSheet = false;
        this.openBrowser(this.menuAgentUrl, this.menuAgentName);
      })
      if (this.menuAgentStatus === 'ARCHIVED') {
        this.menuBtn('取消归档', async () => {
          const ok = await this.inbox.unarchive(this.menuAgentId);
          this.pullInboxUi();
          this.showChromeSheet = false;
          if (ok) {
            Haptics.success();
            showToast('已取消归档');
          } else {
            Haptics.fail();
            this.pullInboxUi();
          }
        })
      } else {
        this.menuBtn('归档', async () => {
          const ok = await this.inbox.archive(this.menuAgentId);
          this.includeArchived = true;
          PrefStore.getInstance().setIncludeArchived(true);
          this.pullInboxUi();
          this.showChromeSheet = false;
          if (ok) {
            Haptics.success();
            showToast('已归档');
          } else {
            Haptics.fail();
            this.pullInboxUi();
          }
        })
      }
      this.menuBtn('永久删除', () => {
        const id = this.menuAgentId;
        const title = this.menuAgentName.length > 0 ? this.menuAgentName : shortAgentId(id);
        this.showChromeSheet = false;
        confirmDanger('永久删除', `删除「${title}」后无法恢复。`, '删除', () => {
          this.inbox.deleteRemote(id).then((ok: boolean) => {
            this.pullInboxUi();
            if (ok) {
              Haptics.success();
              showToast('已删除');
            } else {
              Haptics.fail();
            }
          });
        });
      })
    }
    .padding(16)
    .width('100%')
  }

  @Builder
  menuBtn(title: string, action: () => void) {
    Text(title)
      .width('100%')
      .height(48)
      .fontSize(Tokens.typeProse)
      .fontColor(title.indexOf('删除') >= 0 ? $r('app.color.err') : $r('app.color.text_primary'))
      .textAlign(TextAlign.Start)
      .padding({ left: 4 })
      .opacity(this.pressKey === `menu:${title}` ? 0.7 : 1)
      .onTouch((e: TouchEvent) => {
        if (e.type === TouchType.Down) {
          this.pressKey = `menu:${title}`;
        } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
          this.pressKey = '';
        }
      })
      .onClick(() => {
        if (title.indexOf('删除') >= 0) {
          Haptics.warn();
        } else {
          Haptics.tick();
        }
        action();
      })
  }
}

/** Internal helper — applyInboxQuery without group, returns AgentSummary[]. */
function applyQueryInternal(
  items: AgentSummary[],
  query: string,
  filter: FilterMode,
  sort: SortMode,
  pinned: string[]
): AgentSummary[] {
  return applyInboxQuery(items, query, filter, sort, pinned);
}
