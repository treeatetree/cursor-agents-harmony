import { common } from '@kit.AbilityKit';
import { LengthMetrics } from '@kit.ArkUI';
import { SessionVM } from '../viewmodels/SessionVM';
import { InboxVM } from '../viewmodels/InboxVM';
import { DetailVM } from '../viewmodels/DetailVM';
import { warmCreateMeta } from '../viewmodels/NewAgentVM';
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
import { InboxFeedSource } from '../datasource/InboxFeedSource';
import { UnreadItem, UnreadStore } from '../store/UnreadStore';
import { NetworkMonitor } from '../utils/NetworkMonitor';
import { Haptics } from '../utils/Haptics';
import { expandTransition, fadeTransition, motionMs, runLayout } from '../utils/Motion';
import { StatusPill } from '../components/StatusPill';
import { ToastHost } from '../components/ToastHost';
import { CreateDraftStore } from '../store/CreateDraftStore';
import { HuAvatar, HuAvatarPicker } from '../components/HuAvatar';
import { HuButton } from '../components/HuButton';
import { HuIcon } from '../components/HuIcon';
import { HuIconButton } from '../components/HuIconButton';
import { HuChip } from '../components/HuChip';
import { HuTextButton } from '../components/HuTextButton';
import { SheetActionRow, SheetActionTile } from '../components/SheetAction';
import { normalizeAvatarId } from '../utils/AvatarPresets';
import { confirmDanger } from '../utils/AppDialog';
import { notifyResult, showToast } from '../utils/AppToast';
import { SettingsPageBuilder } from './SettingsPage';
import { NewAgentPage, NewAgentPageBuilder } from './NewAgentPage';
import { AgentDetailPageBuilder } from './AgentDetailPage';
import { InAppBrowserPageBuilder, shouldUseInAppBrowser } from './InAppBrowserPage';
import { shortAgentId } from '../utils/DisplayFmt';
import { materializeForCrop, pickOneImageUri, resolveAvatarPhoto, toFileUri } from '../utils/ImagePicker';
import { AvatarCrop } from '../components/AvatarCrop';
import { pushInAppBrowser, WebLinks } from '../utils/WebLinks';
import { readClipboardText } from '../utils/Clipboard';
import {
  FilterMode,
  GroupMode,
  SortMode,
  GroupBucket,
  CardPair,
  InboxFeedRow,
  applyInboxQuery,
  flattenCardFeed,
  flattenListFeed,
  groupAgents,
  isPinnedId
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
  @StorageLink('avatarPreset') avatarPreset: string = 'iridescent';
  @StorageLink('avatarPhoto') avatarPhoto: string = '';
  @State showAvatarEdit: boolean = false;
  @State cropUri: string = '';
  private pollTimer: number = -1;
  private netRefreshTimer: number = -1;
  private unreadOpenTimer: number = -1;
  private openingAgentId: string = '';
  private openingAt: number = 0;
  private inboxHidden: boolean = false;
  private feedSource: InboxFeedSource = new InboxFeedSource();
  private unsubNet: (() => void) | undefined = undefined;
  private unsubBp: (() => void) | undefined = undefined;
  private unsubInbox: (() => void) | undefined = undefined;
  private unsubSession: (() => void) | undefined = undefined;
  private unsubUnread: (() => void) | undefined = undefined;

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
  @State unreadCount: number = 0;
  @State deltaIds: string[] = [];
  @State renameDraft: string = '';
  @StorageLink('aliasRev') @Watch('onAliasRev') aliasRev: number = 0;
  @StorageLink('pinRev') @Watch('onPinRev') pinRev: number = 0;
  @State setupKey: string = '';
  @State setupBusy: boolean = false;
  @State setupError: string = '';

  aboutToAppear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    try {
      registerAppFonts(this.getUIContext());
      applyAppFont(ctx.getApplicationContext());
    } catch (_e) {
      registerAppFonts();
    }
    NetworkMonitor.getInstance().start();
    this.unsubNet = NetworkMonitor.getInstance().onChange((v: boolean) => {
      this.online = v;
      if (v && this.hasKey && this.session.keyReady) {
        const active = DetailVM.getActive();
        if (active) {
          active.resumeIfNeeded();
        }
        if (this.netRefreshTimer >= 0) {
          clearTimeout(this.netRefreshTimer);
        }
        const delay = (active && active.isRunActive()) ? 1500 : 0;
        this.netRefreshTimer = setTimeout(() => {
          this.netRefreshTimer = -1;
          this.silentInboxRefresh();
        }, delay) as number;
      }
    });
    this.online = NetworkMonitor.getInstance().online;
    this.unsubBp = this.bpStore.onChange(() => {
      this.syncBreakpoint();
    });
    // Split mode keeps Index painted — Settings save must push state via SessionVM.onChange.
    this.unsubInbox = this.inbox.onChange(() => {
      this.pullInboxUi();
    });
    this.unsubUnread = UnreadStore.getInstance().onChange(() => {
      this.pullInboxUi();
      this.inbox.prefetchUnread();
    });
    this.unsubSession = this.session.onChange(() => {
      const hadKey = this.hasKey;
      this.refreshSession();
      this.pullInboxUi();
      if (this.hasKey && !hadKey && this.session.keyReady) {
        this.inbox.startWatch();
        this.inbox.requestRefresh(true, 0).then(() => {
          this.pullInboxUi();
          this.inbox.prefetchOnShow();
        });
        this.startPoll();
        warmCreateMeta().catch(() => {
        });
      } else if (!this.hasKey) {
        this.inbox.stopWatch();
        this.stopPoll();
      }
    });
    this.syncBreakpoint();
    const ctxReady = Promise.all([
      this.session.hydrate(ctx).then(() => {
        this.refreshSession();
        this.pullInboxUi();
      }),
      this.inbox.bootstrap(ctx).then(() => {
        this.pullInboxUi();
      })
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
          this.inbox.requestRefresh(true, 0).then(() => {
            this.pullInboxUi();
            this.inbox.prefetchOnShow();
          });
          this.startPoll();
          warmCreateMeta().catch(() => {
          });
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
    if (this.netRefreshTimer >= 0) {
      clearTimeout(this.netRefreshTimer);
      this.netRefreshTimer = -1;
    }
    if (this.unreadOpenTimer >= 0) {
      clearTimeout(this.unreadOpenTimer);
      this.unreadOpenTimer = -1;
    }
    if (this.unsubNet) {
      this.unsubNet();
    }
    if (this.unsubBp) {
      this.unsubBp();
    }
    if (this.unsubInbox) {
      this.unsubInbox();
    }
    if (this.unsubSession) {
      this.unsubSession();
    }
    if (this.unsubUnread) {
      this.unsubUnread();
    }
  }

  onPageShow(): void {
    this.consumePendingAgent();
    this.consumePendingUnread();
    this.refreshSession();
    this.pullInboxUi();
    this.reloadAvatar();
    PrefStore.getInstance().getPinnedIds().then((ids: string[]) => {
      this.pinnedIds = ids;
      this.recomputeView();
    });
    if (this.hasKey && this.session.keyReady) {
      this.inbox.prefetchOnShow();
      this.silentInboxRefresh();
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
      if (this.inbox.runningCount() > 0) {
        return;
      }
      if (!this.inbox.shouldRefresh(30000)) {
        return;
      }
      this.silentInboxRefresh(30000);
    }, 8000) as number;
  }

  private silentInboxRefresh(minIntervalMs: number = 8000): void {
    this.inbox.requestRefresh(true, minIntervalMs).then(() => {
      this.pullInboxUi();
    });
  }

  private stopPoll(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private async saveSetupKey(): Promise<void> {
    if (this.setupBusy) {
      return;
    }
    this.setupBusy = true;
    this.setupError = '';
    const ok: boolean = await this.session.saveAndValidate(this.setupKey);
    if (ok) {
      this.setupKey = '';
      showToast('已保存', 'info', 'inbox');
    } else {
      this.setupError = this.session.errorMsg.length > 0 ? this.session.errorMsg : '验证失败';
    }
    this.setupBusy = false;
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
    const split = this.bpStore.useSplit;
    const splitChanged = split !== this.useSplit;
    this.useSplit = split;
    this.pagePad = Tokens.pagePad;
    this.topInset = this.bpStore.safeTop();
    this.bottomInset = this.bpStore.bottomInsetVp;
    this.keyboardInset = this.bpStore.keyboardInsetVp;
    if (splitChanged) {
      this.rebuildFeed();
    }
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
    this.unreadCount = unread.count();
    this.recomputeView();
  }

  private async runInboxRefresh(okText: string = ''): Promise<void> {
    const ok = await this.inbox.refresh(false);
    this.pullInboxUi();
    if (!ok) {
      const err = this.inboxError.length > 0 ? this.inboxError : '刷新失败';
      notifyResult(false, '', err, 'inbox');
      return;
    }
    if (okText.length > 0) {
      this.clearDelta();
      notifyResult(true, okText, '', 'inbox');
      return;
    }
    const delta = this.inbox.lastDelta;
    if (delta.ids.length === 0) {
      notifyResult(true, '已是最新', '', 'inbox');
      return;
    }
    this.deltaIds = delta.ids;
    this.recomputeView();
    notifyResult(true, `${delta.ids.length} 条更新`, '', 'inbox');
  }

  private clearDelta(): void {
    if (this.deltaIds.length === 0) {
      return;
    }
    this.deltaIds = [];
    this.recomputeView();
  }

  private isFresh(id: string): boolean {
    return this.unreadIds.indexOf(id) >= 0 || this.deltaIds.indexOf(id) >= 0;
  }

  private cardFreshSig(item: AgentSummary): string {
    return `${item.id}:${this.isFresh(item.id) ? 1 : 0}:${isPinnedId(item.id, this.pinnedIds) ? 1 : 0}`;
  }

  private pairFreshSig(pair: CardPair): string {
    let s = this.cardFreshSig(pair.left);
    if (pair.hasRight) {
      s = `${s}|${this.cardFreshSig(pair.right)}`;
    }
    return s;
  }

  private resyncInboxChrome(): void {
    this.pullInboxUi();
    PrefStore.getInstance().getPinnedIds().then((ids: string[]) => {
      this.pinnedIds = ids;
      this.recomputeView();
    });
  }

  /** Recompute flat / grouped view models from the inbox source + current toolbar state. */
  private recomputeView(): void {
    const all = this.inbox.source.snapshot();
    const source: AgentSummary[] = [];
    for (let i = 0; i < all.length; i++) {
      if (!this.includeArchived && all[i].status === 'ARCHIVED') {
        continue;
      }
      source.push(all[i]);
    }
    const filtered = applyQueryInternal(source, this.query, this.filterMode, this.sortMode, this.pinnedIds);
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
    this.rebuildFeed();
  }

  private rebuildFeed(): void {
    const open = this.openGroupKey();
    if (this.useSplit) {
      this.feedSource.replaceAll(flattenListFeed(this.buckets, this.flatItems, open));
    } else {
      this.feedSource.replaceAll(flattenCardFeed(this.buckets, this.flatItems, open));
    }
  }

  private feedRowKey(row: InboxFeedRow): string {
    if (row.kind === 'header') {
      return `${row.key}:${row.collapsed ? 0 : 1}:${row.bucketCount}`;
    }
    if (row.kind === 'pair') {
      return this.pairFreshSig(row.pair);
    }
    return this.cardFreshSig(row.agent);
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
    await this.applyAvatarPrefs(await prefs.getAvatarPreset(), await prefs.getAvatarPhoto());
  }

  private reloadAvatar(): void {
    const prefs = PrefStore.getInstance();
    Promise.all([prefs.getAvatarPreset(), prefs.getAvatarPhoto()]).then((pair: string[]) => {
      this.applyAvatarPrefs(pair[0], pair[1]);
    });
  }

  private async applyAvatarPrefs(preset: string, photo: string): Promise<void> {
    const id = normalizeAvatarId(preset);
    const uri = await resolveAvatarPhoto(photo);
    if (id === 'custom' && uri.length === 0) {
      await PrefStore.getInstance().saveAvatar('iridescent', '');
      return;
    }
    await PrefStore.getInstance().saveAvatar(id, id === 'custom' ? uri : '');
  }

  private avatarSrc(): string {
    if (this.avatarPreset !== 'custom' || this.avatarPhoto.length === 0) {
      return '';
    }
    return this.avatarPhoto;
  }

  private pickAvatar(id: string): void {
    PrefStore.getInstance().saveAvatar(normalizeAvatarId(id), '');
  }

  private async pickAvatarPhoto(): Promise<void> {
    const uri = await pickOneImageUri();
    if (uri.length === 0) {
      return;
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    const local = await materializeForCrop(uri, ctx.cacheDir);
    if (local.length === 0) {
      showToast('这张图读不了', 'info', 'inbox');
      return;
    }
    this.cropUri = toFileUri(local);
  }

  private applyCroppedAvatar(path: string): void {
    this.cropUri = '';
    PrefStore.getInstance().saveAvatar('custom', toFileUri(path));
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
    if (this.expandedKey === GROUP_ALL_COLLAPSED || this.expandedKey.length === 0) {
      return '';
    }
    if (this.hasBucketKey(this.expandedKey)) {
      return this.expandedKey;
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
      this.rebuildFeed();
      PrefStore.getInstance().setInboxExpanded(this.expandedKey);
    });
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
    this.menuAgentName = PrefStore.getInstance().displayName(agent.id,
      agent.name.length > 0 ? agent.name : shortAgentId(agent.id));
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
    this.recomputeView();
    await PrefStore.getInstance().setPinnedIds(next);
  }

  onPendingRev(): void {
    this.consumePendingAgent();
  }

  onPendingUnread(): void {
    this.consumePendingUnread();
  }

  onAliasRev(): void {
    this.recomputeView();
  }

  onPinRev(): void {
    PrefStore.getInstance().getPinnedIds().then((ids: string[]) => {
      this.pinnedIds = ids;
      this.recomputeView();
    });
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
    if (this.unreadOpenTimer >= 0) {
      clearTimeout(this.unreadOpenTimer);
      this.unreadOpenTimer = -1;
    }
    const reopen = this.showChromeSheet && this.chromeKind !== 'unread';
    this.chromeKind = 'unread';
    if (reopen) {
      this.showChromeSheet = false;
      this.unreadOpenTimer = setTimeout(() => {
        this.unreadOpenTimer = -1;
        this.chromeKind = 'unread';
        this.showChromeSheet = true;
      }, 80) as number;
      return;
    }
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
    const now = Date.now();
    if (id === this.openingAgentId && now - this.openingAt < 800) {
      return;
    }
    this.openingAgentId = id;
    this.openingAt = now;
    try {
      if (this.isFresh(id)) {
        AppStorage.setOrCreate('pendingFreshOpen', id);
      }
    } catch (_e) {
    }
    this.markOpened(id);
    Haptics.click();
    this.selectedId = id;
    const active = DetailVM.getActive();
    if (active && active.agentId === id && active.isViewing()) {
      active.resumeIfNeeded();
      return;
    }
    const param: Record<string, Object> = {};
    param['agentId'] = id;
    this.navStack.pushPath({ name: 'AgentDetail', param: param });
  }

  private markOpened(id: string): void {
    const nextDelta: string[] = [];
    for (let i = 0; i < this.deltaIds.length; i++) {
      if (this.deltaIds[i] !== id) {
        nextDelta.push(this.deltaIds[i]);
      }
    }
    this.deltaIds = nextDelta;
    const nextUnread: string[] = [];
    for (let i = 0; i < this.unreadIds.length; i++) {
      if (this.unreadIds[i] !== id) {
        nextUnread.push(this.unreadIds[i]);
      }
    }
    this.unreadIds = nextUnread;
    UnreadStore.getInstance().markSeen(id).catch(() => {
    });
    this.unreadItems = UnreadStore.getInstance().peek();
    this.unreadCount = UnreadStore.getInstance().count();
    this.unreadLine = UnreadStore.getInstance().headline();
    this.recomputeView();
  }

  private listFooterH(): number {
    return Math.max(this.bottomInset, 24) + 16;
  }

  private showSkeleton(): boolean {
    return this.inboxLoading && this.agentCount === 0 && !this.loadedOnce;
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
        }

        if (!this.ready && !this.loadedOnce) {
          Column() {
            SkeletonList({ rows: 6 })
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ top: this.hasKey ? this.topInset : 0 })
        } else if (this.ready && !this.hasKey) {
          this.emptyNoKey()
        } else {
          this.inboxBody()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg0'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .overlay(this.homeDock(), { align: Alignment.Bottom })
      .bindSheet($$this.showNewSheet, this.newAgentSheet(), {
        height: this.newSheetHeight(),
        detents: [SheetSize.LARGE],
        dragBar: true,
        showClose: false,
        radius: LengthMetrics.vp(Tokens.radiusSheet),
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
    Row({ space: 10 }) {
      Image($r('app.media.app_icon'))
        .width(28)
        .height(28)
        .objectFit(ImageFit.Cover)
        .borderRadius(8)
        .draggable(false)
      Text('Cursor Cloud Agents')
        .fontSize(Tokens.typeHeadline)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .constraintSize({ minWidth: 0 })
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
    .constraintSize({ minHeight: Tokens.touchMin })
    .alignItems(VerticalAlign.Center)
    .padding({
      left: this.pagePad,
      right: this.pagePad - 4,
      top: this.topInset + 2,
      bottom: 6
    })
  }

  @Builder
  emptyNoKey() {
    Scroll() {
      Column() {
        Column({ space: Tokens.space5 }) {
          this.setupHowCard()
          this.setupPasteCard()
          this.setupPrivacyCard()
        }
        .width('100%')
        .constraintSize({ maxWidth: 440 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({
        left: this.pagePad,
        right: this.pagePad,
        top: 8,
        bottom: (this.keyboardInset > this.bottomInset ? this.keyboardInset : this.bottomInset) + 24
      })
    }
    .layoutWeight(1)
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  setupHowCard() {
    Column({ space: Tokens.space4 }) {
      Text('如何拿到 Key')
        .fontSize(Tokens.typeCaption)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
      Column({ space: Tokens.space3 }) {
        this.setupStep('1', '打开 Cursor 网站并登录你的账号')
        this.setupStep('2', '进入 API Keys，新建一把 User API Key')
        this.setupStep('3', '复制以 crsr_ 开头的那一串，回到这里粘贴')
      }
      .width('100%')
      Column({ space: Tokens.space2 }) {
        Row() {
          Column({ space: 2 }) {
            Text('去 Cursor 创建 Key')
              .fontSize(Tokens.typeCallout)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text('cursor.com/dashboard/api')
              .fontSize(Tokens.typeMicro)
              .fontColor($r('app.color.text_tertiary'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          HuIcon({
            name: 'external',
            iconSize: 18,
            tint: $r('app.color.text_tertiary')
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .backgroundColor($r('app.color.bg2'))
        .borderRadius(Tokens.radiusMd)
        .opacity(this.pressKey === 'setup-api' ? 0.7 : 1)
        .animation({ duration: 180, curve: Curve.EaseOut })
        .onTouch((e: TouchEvent) => {
          if (e.type === TouchType.Down) {
            this.pressKey = 'setup-api';
          } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
            this.pressKey = '';
          }
        })
        .onClick(() => {
          Haptics.click();
          this.openBrowser(WebLinks.apiKeys, 'API Keys');
        })
        HuTextButton({
          label: '官方说明',
          color: $r('app.color.text_link'),
          compact: true,
          external: true,
          onTap: () => {
            this.openBrowser(WebLinks.docsApiOverview, 'API 说明');
          }
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.bg1'))
    .borderRadius(Tokens.radiusCard)
    .border({ width: 1, color: $r('app.color.border') })
  }

  @Builder
  setupStep(n: string, title: string) {
    Row({ space: 12 }) {
      Column() {
        Text(n)
          .fontSize(Tokens.typeMicro)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
      }
      .width(22)
      .height(22)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.bg2'))
      .borderRadius(Tokens.radiusPill)
      Text(title)
        .fontSize(Tokens.typeCallout)
        .fontColor($r('app.color.text_primary'))
        .lineHeight(Tokens.lineCaption)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  setupPasteCard() {
    Column({ space: Tokens.space3 }) {
      TextArea({
        text: this.setupKey,
        placeholder: '粘贴 crsr_… Key'
      })
        .height(56)
        .width('100%')
        .fontSize(Tokens.typeCallout)
        .fontFamily(Tokens.fontMono)
        .fontColor($r('app.color.text_primary'))
        .placeholderFont({ size: Tokens.typeCallout, weight: FontWeight.Regular })
        .placeholderColor($r('app.color.text_placeholder'))
        .backgroundColor($r('app.color.field_bg'))
        .borderRadius(Tokens.radiusField)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .caretColor($r('app.color.accent'))
        .border({ width: 1, color: $r('app.color.border') })
        .onChange((v: string) => {
          this.setupKey = v;
        })
      Row() {
        PasteButton({ icon: PasteIconStyle.LINES, text: PasteDescription.PASTE })
          .height(Tokens.touchMin)
          .fontSize(Tokens.typeCaption)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor(Color.Transparent)
          .onClick(async (_e: ClickEvent, result: PasteButtonOnClickResult) => {
            if (result !== PasteButtonOnClickResult.SUCCESS) {
              showToast('未授权读取剪贴板', 'info', 'inbox');
              return;
            }
            const text = (await readClipboardText()).trim();
            if (text.length === 0) {
              showToast('剪贴板是空的', 'info', 'inbox');
              return;
            }
            this.setupKey = text;
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      if (this.setupError.length > 0) {
        Text(this.setupError)
          .fontSize(Tokens.typeCaption)
          .fontColor($r('app.color.err'))
          .width('100%')
      }
      HuButton({
        label: this.setupBusy ? '验证中…' : '验证并保存',
        variant: 'primary',
        fillWidth: true,
        isEnabled: !this.setupBusy && this.setupKey.trim().length > 8,
        onTap: () => {
          this.saveSetupKey();
        }
      })
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.bg1'))
    .borderRadius(Tokens.radiusCard)
    .border({ width: 1, color: $r('app.color.border') })
  }

  @Builder
  setupPrivacyCard() {
    Column({ space: Tokens.space2 }) {
      Text('安全与隐私')
        .fontSize(Tokens.typeCaption)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
      Text('本应用使用 Cursor 官方开放 API。所有信息都直达 Cursor 服务器，无需担心安全和隐私问题。')
        .fontSize(Tokens.typeCallout)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(Tokens.lineCaption)
        .width('100%')
      Text('Key 用系统加密保存在本机，对话不经过第三方中转。')
        .fontSize(Tokens.typeCaption)
        .fontColor($r('app.color.text_tertiary'))
        .lineHeight(Tokens.lineCaption)
        .width('100%')
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.bg1'))
    .borderRadius(Tokens.radiusCard)
    .border({ width: 1, color: $r('app.color.border') })
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
        photoUri: this.avatarSrc(),
        box: Tokens.touchMin,
        onTap: () => {
          this.chromeKind = 'account';
          this.showAvatarEdit = false;
          this.cropUri = '';
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
  homeDock() {
    Column({ space: 8 }) {
      this.inboxActionPill()
      if (!this.hasKey) {
        ToastHost({ page: 'inbox' })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 16, right: 16, bottom: Tokens.toastBottom })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  inboxActionPill() {
    if (this.keyReady && (this.authExpired || (this.errorMsg.length > 0 && this.errorMsg.indexOf('API Key') >= 0))) {
      StatusPill({
        text: this.authExpired ? 'API Key 失效，请重新粘贴' : this.errorMsg,
        tone: 'danger',
        action: '去设置',
        onAction: () => {
          this.navStack.pushPath({ name: 'Settings' });
        }
      })
    } else if (this.errorMsg.length > 0) {
      StatusPill({
        text: this.errorMsg,
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
          this.openBrowser('https://cursor.com/dashboard', 'Dashboard');
        }
      })
    } else if (this.actionBanner.length > 0) {
      StatusPill({
        text: this.actionBanner,
        tone: 'danger',
        action: this.actionKind === 'retry-create' ? '重试' : '',
        dismissible: true,
        onAction: () => {
          this.retryCreateFromBanner();
        },
        onDismiss: () => {
          this.inbox.clearActionBanner();
        }
      })
    } else if (this.inboxError.length > 0 && !this.authExpired) {
      StatusPill({
        text: this.inboxError,
        tone: 'warn',
        action: '重试',
        onAction: () => {
          this.runInboxRefresh();
        }
      })
    } else if (!this.online) {
      StatusPill({
        text: '网络已断开 · 显示缓存内容',
        tone: 'warn',
        action: '重试',
        onAction: () => {
          this.runInboxRefresh();
        }
      })
    }
  }

  @Builder
  inboxFloatChrome() {
    Column({ space: 8 }) {
      if (this.inboxRefreshing) {
        StatusPill({
          text: '刷新中…',
          loading: true
        })
      }
      this.inboxUnreadStrip()
      ToastHost({ page: 'inbox' })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 8 })
    .position({ x: 0, y: 0 })
    .hitTestBehavior(HitTestMode.None)
    .zIndex(12)
  }

  @Builder
  inboxUnreadStrip() {
    if (this.hasKey && this.unreadCount > 0) {
      StatusPill({
        text: this.unreadItems.length > 0 ? this.unreadItems[0].name : `${this.unreadCount} 条未读`,
        count: `${this.unreadCount}`,
        action: '清空',
        onTap: () => {
          this.openUnreadSheet();
        },
        onAction: () => {
          this.clearUnread();
        }
      })
    } else {
      Column()
        .width(0)
        .height(0)
    }
  }

  @Builder
  inboxBody() {
    if (this.useSplit && !this.inboxOpen) {
      this.inboxRail()
    } else {
    Column() {
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
            await this.runInboxRefresh(next ? '已显示归档' : '已隐藏归档');
          },
          onTogglePr: () => {
            this.prUrlInput = this.prUrlFilter;
            this.showPrFilter = !this.showPrFilter;
          },
          onRefresh: async () => {
            await this.runInboxRefresh();
          },
          onSettings: () => {
            this.navStack.pushPath({ name: 'Settings' });
          },
          onAvatar: () => {
            this.chromeKind = 'account';
            this.showAvatarEdit = false;
            this.cropUri = '';
            this.showChromeSheet = true;
          },
          onNew: () => {
            this.openNew();
          },
          onCollapse: () => {
            this.setInboxOpen(false);
          }
        })

        if (this.showPrFilter) {
          Row({ space: 8 }) {
            TextInput({ text: this.prUrlInput, placeholder: '粘贴 PR URL 按此筛选' })
              .fontSize(Tokens.typeCaption)
              .placeholderFont({ size: Tokens.typeCaption, weight: FontWeight.Regular })
              .placeholderColor($r('app.color.text_placeholder'))
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
                await this.runInboxRefresh('已按 PR 筛选');
              }
            })
            if (this.prUrlFilter.length > 0) {
              HuTextButton({
                label: '清除',
                onTap: async () => {
                  this.prUrlInput = '';
                  this.inbox.setPrUrlFilter('');
                  this.showPrFilter = false;
                  await this.runInboxRefresh('已清除筛选');
                }
              })
            }
          }
          .width('100%')
          .padding({ left: this.pagePad, right: this.pagePad, top: 4, bottom: 8 })
        }

        Stack({ alignContent: Alignment.Top }) {
          Column() {
            if (this.showSkeleton()) {
              Column() {
                SkeletonList({ rows: 6 })
              }
              .width('100%')
              .height('100%')
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
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
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
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
            } else {
              Column() {
                this.renderView()
              }
              .width('100%')
              .height('100%')
            }
          }
          .width('100%')
          .height('100%')

          this.inboxFloatChrome()
        }
        .width('100%')
        .layoutWeight(1)
        .clip(false)
    }
    .width('100%')
    .layoutWeight(1)
    .onVisibleAreaChange([0.0, 1.0], (_isExpanding: boolean, ratio: number) => {
      const hidden = ratio < 0.15;
      if (this.inboxHidden && !hidden) {
        this.resyncInboxChrome();
      }
      this.inboxHidden = hidden;
    })
    .bindSheet($$this.showChromeSheet, this.chromeSheet(), {
      height: this.chromeKind === 'unread' ? SheetSize.MEDIUM : SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      radius: LengthMetrics.vp(Tokens.radiusSheet),
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
        LazyForEach(this.feedSource, (row: InboxFeedRow) => {
          ListItem() {
            this.feedListRow(row)
          }
          .transition(expandTransition())
        }, (row: InboxFeedRow) => this.feedRowKey(row))
        ListItem() {
          Column()
            .width('100%')
            .height(this.listFooterH())
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: Tokens.space2 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .cachedCount(8)
      .onReachEnd(() => {
        this.inbox.loadMore().then((ok: boolean) => {
          this.pullInboxUi();
          if (!ok) {
            const err = this.inbox.errorMsg.length > 0 ? this.inbox.errorMsg : '加载更多失败';
            notifyResult(false, '', err, 'inbox');
          }
        });
      })
    }
    .width('100%')
    .height('100%')
    .onRefreshing(async () => {
      Haptics.tick();
      this.isRefreshing = false;
      this.inboxRefreshing = true;
      await this.runInboxRefresh();
    })
  }

  @Builder
  feedListRow(row: InboxFeedRow) {
    if (row.kind === 'header') {
      this.sectionHeader(row)
    } else {
      AgentCard({
        agent: row.agent,
        showRepo: this.groupMode !== 'repo',
        preview: AgentCache.getInstance().peekMemSummary(row.agent.id),
        list: true,
        pinned: isPinnedId(row.agent.id, this.pinnedIds),
        unread: this.isFresh(row.agent.id),
        active: row.agent.id === this.selectedId,
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
  }

  @Builder
  cardFeed() {
    Refresh({ refreshing: $$this.isRefreshing }) {
      List({ space: 0 }) {
        LazyForEach(this.feedSource, (row: InboxFeedRow) => {
          ListItem() {
            this.feedCardRow(row)
          }
          .transition(expandTransition())
        }, (row: InboxFeedRow) => this.feedRowKey(row))
        ListItem() {
          Column()
            .width('100%')
            .height(this.listFooterH())
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: Tokens.space2 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .cachedCount(6)
      .onReachEnd(() => {
        this.inbox.loadMore().then((ok: boolean) => {
          this.pullInboxUi();
          if (!ok) {
            const err = this.inbox.errorMsg.length > 0 ? this.inbox.errorMsg : '加载更多失败';
            notifyResult(false, '', err, 'inbox');
          }
        });
      })
    }
    .width('100%')
    .height('100%')
    .onRefreshing(async () => {
      Haptics.tick();
      this.isRefreshing = false;
      this.inboxRefreshing = true;
      await this.runInboxRefresh();
    })
  }

  @Builder
  sectionHeader(row: InboxFeedRow) {
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
      .rotate({ angle: row.collapsed ? 0 : 90 })
      .animation({ duration: motionMs(), curve: Curve.FastOutSlowIn })
      Text(row.bucketLabel)
        .fontSize(Tokens.typeCaption)
        .fontFamily(Tokens.fontUi)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .letterSpacing(Tokens.letterGroup)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (row.collapsed) {
        Text(`${row.bucketCount}`)
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
      this.toggleGroup(row.bucketKey);
    })
  }

  @Builder
  feedCardRow(row: InboxFeedRow) {
    if (row.kind === 'header') {
      this.sectionHeader(row)
    } else {
      this.cardPairRow(row.pair)
    }
  }

  @Builder
  cardPairRow(pair: CardPair) {
    Row({ space: Tokens.space2 }) {
      Column() {
        this.gridCard(pair.left)
      }
      .layoutWeight(1)
      .constraintSize({ minWidth: 0 })
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
    .alignItems(VerticalAlign.Top)
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
      preview: AgentCache.getInstance().peekMemSummary(item.id),
      pinned: isPinnedId(item.id, this.pinnedIds),
      unread: this.isFresh(item.id),
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
    } else if (this.chromeKind === 'rename') {
      this.renameSheet()
    } else {
      this.agentMenuSheet()
    }
  }

  @Builder
  renameSheet() {
    Column({ space: Tokens.sheetGap }) {
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
        HuTextButton({
          label: '取消',
          onTap: () => {
            this.showChromeSheet = false;
          }
        })
        HuTextButton({
          label: '保存',
          color: $r('app.color.accent'),
          onTap: () => {
            this.saveAlias(this.menuAgentId, this.renameDraft);
          }
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

  private async saveAlias(id: string, name: string): Promise<void> {
    await PrefStore.getInstance().setAlias(id, name);
    this.menuAgentName = PrefStore.getInstance().displayName(id, name);
    this.showChromeSheet = false;
    this.recomputeView();
    Haptics.success();
    showToast('已保存本地名称', 'info', 'inbox');
  }

  @Builder
  unreadSheet() {
    Column({ space: Tokens.space2 }) {
      Row() {
        Text(this.unreadItems.length > 0 ? `${this.unreadItems.length} 条新结果` : '没有新结果')
          .fontSize(Tokens.typeCallout)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        if (this.unreadItems.length > 0) {
          HuTextButton({
            label: '清空',
            color: $r('app.color.accent'),
            compact: true,
            onTap: () => {
              this.clearUnread();
            }
          })
        }
      }
      .width('100%')
      .height(32)
      .alignItems(VerticalAlign.Center)

      if (this.unreadItems.length === 0) {
        Text('没有未读结果。若桌面图标还带红点，点下面清掉。')
          .fontSize(Tokens.typeCaption)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .padding({ top: 8, bottom: 8 })
        HuTextButton({
          label: '清除图标红点',
          color: $r('app.color.accent'),
          onTap: () => {
            this.clearUnread();
          }
        })
      } else {
        List({ space: 8 }) {
          ForEach(this.unreadItems, (it: UnreadItem) => {
            ListItem() {
              Column({ space: 4 }) {
                Row({ space: 6 }) {
                  Text(`${it.name} · ${it.statusZh}`)
                    .fontSize(Tokens.typeCallout)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  if (it.repo.length > 0) {
                    Text(it.repo)
                      .fontSize(Tokens.typeMicro)
                      .fontColor($r('app.color.text_tertiary'))
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .backgroundColor($r('app.color.bg2'))
                      .border({ width: 1, color: $r('app.color.border') })
                      .borderRadius(Tokens.radiusChip)
                  }
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
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
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
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
    .padding({
      left: Tokens.sheetPadH,
      right: Tokens.sheetPadH,
      top: Tokens.sheetPadTop,
      bottom: Tokens.sheetPadBottom
    })
    .width('100%')
  }

  @Builder
  accountSheet() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        HuAvatar({
          preset: this.avatarPreset,
          photoUri: this.avatarSrc(),
          box: Tokens.touchMin,
          onTap: () => {
            this.showAvatarEdit = !this.showAvatarEdit;
          }
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
        HuChip({
          label: '设置',
          onTap: () => {
            this.showChromeSheet = false;
            this.navStack.pushPath({ name: 'Settings' });
          }
        })
      }
      .width('100%')
      .padding({ bottom: 4 })
      .alignItems(VerticalAlign.Center)

      Row() {
        Row({ space: 4 }) {
          Text(this.unreadCount > 0 ? `${this.unreadCount} 条未读` : '桌面图标红点')
            .fontSize(Tokens.typeCaption)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
          if (this.unreadCount > 0) {
            HuIcon({
              name: 'chevronRight',
              iconSize: 16,
              tint: $r('app.color.text_tertiary')
            })
          }
        }
        .layoutWeight(1)
        .constraintSize({ minHeight: Tokens.touchMin })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          if (this.unreadCount > 0) {
            Haptics.tick();
            this.openUnreadSheet();
          }
        })
        HuTextButton({
          label: this.unreadCount > 0 ? '全部已读' : '清除',
          color: $r('app.color.accent'),
          onTap: () => {
            this.clearUnread();
          }
        })
      }
      .width('100%')
      .constraintSize({ minHeight: Tokens.touchMin })
      .alignItems(VerticalAlign.Center)

      if (this.cropUri.length > 0) {
        AvatarCrop({
          src: this.cropUri,
          onCancel: () => {
            this.cropUri = '';
          },
          onDone: (path: string) => {
            this.applyCroppedAvatar(path);
          }
        })
      } else if (this.showAvatarEdit) {
        HuAvatarPicker({
          selected: this.avatarPreset,
          photoUri: this.avatarSrc(),
          onPick: (id: string) => {
            this.pickAvatar(id);
          },
          onPhoto: () => {
            this.pickAvatarPhoto();
          }
        })
      }

      Text('分组')
        .fontSize(Tokens.typeCaption)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .padding({ bottom: 4 })
      Row({ space: 4 }) {
        HuChip({
          label: '仓库',
          on: this.groupMode === 'repo',
          onTap: () => {
            this.setGroupMode('repo');
          }
        })
        HuChip({
          label: '时间',
          on: this.groupMode === 'time',
          onTap: () => {
            this.setGroupMode('time');
          }
        })
        HuChip({
          label: '状态',
          on: this.groupMode === 'status',
          onTap: () => {
            this.setGroupMode('status');
          }
        })
        HuChip({
          label: '无分组',
          on: this.groupMode === 'none',
          onTap: () => {
            this.setGroupMode('none');
          }
        })
      }
      .width('100%')

      Text('排序')
        .fontSize(Tokens.typeCaption)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .padding({ bottom: 4 })
      Row({ space: 4 }) {
        HuChip({
          label: '最近发送',
          on: this.sortMode === 'updated',
          onTap: () => {
            runLayout(() => {
              this.sortMode = 'updated';
              this.recomputeView();
            });
            this.persistInboxChrome();
          }
        })
        HuChip({
          label: '创建',
          on: this.sortMode === 'created',
          onTap: () => {
            runLayout(() => {
              this.sortMode = 'created';
              this.recomputeView();
            });
            this.persistInboxChrome();
          }
        })
        HuChip({
          label: '名称',
          on: this.sortMode === 'name',
          onTap: () => {
            runLayout(() => {
              this.sortMode = 'name';
              this.recomputeView();
            });
            this.persistInboxChrome();
          }
        })
      }
      .width('100%')

      Text('筛选')
        .fontSize(Tokens.typeCaption)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .padding({ bottom: 4 })
      Row({ space: 4 }) {
        HuChip({
          label: '含归档',
          on: this.includeArchived,
          onTap: async () => {
            const next = !this.includeArchived;
            PrefStore.getInstance().setIncludeArchived(next);
            this.inbox.setIncludeArchived(next);
            this.includeArchived = next;
            await this.runInboxRefresh(next ? '已显示归档' : '已隐藏归档');
          }
        })
        HuChip({
          label: this.prUrlFilter.length > 0 ? '按 PR · 开' : '按 PR',
          on: this.prUrlFilter.length > 0 || this.showPrFilter,
          onTap: () => {
            this.prUrlInput = this.prUrlFilter;
            this.showPrFilter = !this.showPrFilter;
          }
        })
      }
      .width('100%')
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
  agentMenuSheet() {
    Column({ space: Tokens.sheetGap }) {
      Column({ space: 4 }) {
        Text(this.menuAgentName.length > 0 ? this.menuAgentName : shortAgentId(this.menuAgentId))
          .fontSize(Tokens.typeHeadline)
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
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ bottom: 2 })

      Row({ space: 8 }) {
        SheetActionTile({
          label: this.menuAgentPinned ? '取消置顶' : '置顶',
          onTap: async () => {
            const wasPinned = this.menuAgentPinned;
            await this.togglePin(this.menuAgentId);
            this.showChromeSheet = false;
            Haptics.success();
            showToast(wasPinned ? '已取消置顶' : '已置顶', 'info', 'inbox');
          }
        })
          .layoutWeight(1)
        SheetActionTile({
          label: '重命名',
          hint: '本机别名',
          onTap: () => {
            this.renameDraft = this.menuAgentName;
            this.chromeKind = 'rename';
          }
        })
          .layoutWeight(1)
      }
      .width('100%')

      Column() {
        SheetActionRow({
          label: '浏览器打开',
          hint: '系统浏览器',
          trailing: 'external',
          last: true,
          onTap: () => {
            this.showChromeSheet = false;
            this.openBrowser(this.menuAgentUrl, this.menuAgentName);
          }
        })
      }
      .width('100%')
      .backgroundColor($r('app.color.bg2'))
      .borderRadius(Tokens.radiusCard)
      .clip(true)

      Column() {
        SheetActionRow({
          label: this.menuAgentStatus === 'ARCHIVED' ? '取消归档' : '归档',
          hint: this.menuAgentStatus === 'ARCHIVED' ? '重新出现在 Inbox' : '从 Inbox 收起',
          onTap: async () => {
            if (this.menuAgentStatus === 'ARCHIVED') {
              const ok = await this.inbox.unarchive(this.menuAgentId);
              this.showChromeSheet = false;
              this.pullInboxUi();
              if (ok) {
                Haptics.success();
                showToast('已取消归档', 'info', 'inbox');
              } else {
                Haptics.fail();
                const err = this.inbox.errorMsg.length > 0 ? this.inbox.errorMsg : '取消归档失败';
                showToast(err, 'danger', 'inbox');
              }
            } else {
              const ok = await this.inbox.archive(this.menuAgentId);
              this.showChromeSheet = false;
              if (ok) {
                if (this.includeArchived) {
                  this.expandedKey = 'archived';
                }
                this.pullInboxUi();
                Haptics.success();
                showToast('已归档', 'info', 'inbox');
              } else {
                this.pullInboxUi();
                Haptics.fail();
                const err = this.inbox.errorMsg.length > 0 ? this.inbox.errorMsg : '归档失败';
                showToast(err, 'danger', 'inbox');
              }
            }
          }
        })
        SheetActionRow({
          label: '永久删除',
          hint: '无法恢复',
          danger: true,
          last: true,
          onTap: () => {
            const id = this.menuAgentId;
            const title = this.menuAgentName.length > 0 ? this.menuAgentName : shortAgentId(id);
            this.showChromeSheet = false;
            confirmDanger('永久删除', `删除「${title}」后无法恢复。`, '删除', () => {
              this.inbox.deleteRemote(id).then((ok: boolean) => {
                this.pullInboxUi();
                if (ok) {
                  Haptics.success();
                  showToast('已删除', 'info', 'inbox');
                } else {
                  Haptics.fail();
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
    .padding({
      left: Tokens.sheetPadH,
      right: Tokens.sheetPadH,
      top: Tokens.sheetPadTop,
      bottom: Tokens.sheetPadBottom
    })
    .width('100%')
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
