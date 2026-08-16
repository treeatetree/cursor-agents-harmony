import { Tokens } from '../theme/Tokens';
import { FilterMode, GroupMode, SortMode } from '../utils/InboxGrouping';
import { Haptics } from '../utils/Haptics';
import { motionMs } from '../utils/Motion';
import { HuAvatar } from './HuAvatar';
import { HuIcon } from './HuIcon';
import { HuIconButton } from './HuIconButton';
import { HuTextButton } from './HuTextButton';

/**
 * Single-row inbox chrome: status chips + search + avatar + new.
 */
@Component
export struct InboxFilterBar {
  @Prop query: string = '';
  @Prop filter: FilterMode = 'all';
  @Prop sort: SortMode = 'updated';
  @Prop group: GroupMode = 'repo';
  @Prop count: number = 0;
  @Prop total: number = 0;
  @Prop refreshing: boolean = false;
  @Prop includeArchived: boolean = false;
  @Prop prActive: boolean = false;
  @Prop pad: number = Tokens.pagePad;
  @Prop topInset: number = 0;
  /** Narrow master pane: chips + overflow + new. Search/filter/settings stay behind 更多. */
  @Prop compact: boolean = false;
  /** Cover: no search icon (plan: 外屏不要搜索). */
  @Prop hideSearch: boolean = false;
  @Prop avatarPreset: string = 'iridescent';
  @State private showSearch: boolean = false;
  onQuery: (s: string) => void = () => {
  };
  onFilter: (m: FilterMode) => void = () => {
  };
  onSort: (m: SortMode) => void = () => {
  };
  onGroup: (m: GroupMode) => void = () => {
  };
  onToggleArchived: () => void = () => {
  };
  onTogglePr: () => void = () => {
  };
  onRefresh: () => void = () => {
  };
  onSettings: () => void = () => {
  };
  onAvatar: () => void = () => {
  };
  onNew: () => void = () => {
  };
  onCollapse: () => void = () => {
  };

  private searchVisible(): boolean {
    return this.showSearch || this.query.length > 0;
  }

  private filterActive(): boolean {
    return this.prActive || this.includeArchived || this.filter !== 'all' ||
      this.group !== 'repo' || this.sort !== 'updated';
  }

  private tabLabel(mode: FilterMode): string {
    if (mode === 'all') {
      return '全部';
    }
    if (mode === 'running') {
      return this.compact ? '运行' : '运行中';
    }
    if (mode === 'error') {
      return '失败';
    }
    return this.compact ? '完成' : '已完成';
  }

  build() {
    Column({ space: Tokens.space2 }) {
      Row({ space: 8 }) {
        this.avatarBtn()

        if (this.searchVisible()) {
          TextInput({ text: this.query, placeholder: '搜索任务' })
            .layoutWeight(1)
            .height(Tokens.touchMin)
            .fontSize(Tokens.typeCallout)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_tertiary'))
            .backgroundColor($r('app.color.bg1'))
            .borderRadius(Tokens.radiusField)
            .border({ width: 1, color: $r('app.color.border') })
            .padding({ left: 12, right: 12 })
            .defaultFocus(true)
            .onChange((v: string) => {
              this.onQuery(v);
            })
          HuTextButton({
            label: '取消',
            onTap: () => {
              this.showSearch = false;
              this.onQuery('');
            }
          })
        } else {
          Scroll() {
            Row({ space: 4 }) {
              this.seg(this.tabLabel('all'), 'all')
              this.seg(this.tabLabel('running'), 'running')
              this.seg(this.tabLabel('error'), 'error')
              this.seg(this.tabLabel('done'), 'done')
            }
            .constraintSize({ minHeight: Tokens.touchMin })
            .alignItems(VerticalAlign.Center)
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.None)
          .layoutWeight(1)
          .height(Tokens.touchMin)
          .constraintSize({ minWidth: 0 })
        }

        if (!this.searchVisible() && !this.compact && !this.hideSearch) {
          HuIconButton({
            name: 'search',
            label: '搜索',
            iconColor: this.query.length > 0 ? $r('app.color.accent') : $r('app.color.text_secondary'),
            onTap: () => {
              this.showSearch = true;
            }
          })
        }

        if (this.compact && !this.searchVisible()) {
          Column() {
            HuIcon({
              name: 'back',
              iconSize: 18,
              tint: $r('app.color.text_secondary')
            })
          }
          .width(32)
          .height(Tokens.touchMin)
          .justifyContent(FlexAlign.Center)
          .accessibilityText('收起列表')
          .onClick(() => {
            Haptics.click();
            this.onCollapse();
          })
        }

        HuIconButton({
          name: 'plus',
          label: '新建任务',
          filled: true,
          onTap: () => {
            this.onNew();
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({
      left: this.pad,
      right: this.pad,
      top: this.topInset + 2,
      bottom: Tokens.space2
    })
  }

  @Builder
  seg(label: string, mode: FilterMode) {
    Column() {
      Text(label)
        .fontSize(Tokens.typeCaption)
        .fontWeight(this.filter === mode ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.filter === mode ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
        .height(32)
        .padding({ left: this.compact ? 8 : 10, right: this.compact ? 8 : 10 })
        .textAlign(TextAlign.Center)
        .backgroundColor(this.filter === mode ? $r('app.color.bg2') : Color.Transparent)
        .borderRadius(Tokens.radiusChip)
        .border({
          width: 1,
          color: this.filter === mode ? $r('app.color.border_strong') : Color.Transparent
        })
    }
    .constraintSize({ minHeight: Tokens.touchMin })
    .justifyContent(FlexAlign.Center)
    .animation({ duration: motionMs(), curve: Curve.FastOutSlowIn })
    .onClick(() => {
      Haptics.tick();
      this.onFilter(mode);
    })
  }

  @Builder
  avatarBtn() {
    HuAvatar({
      preset: this.avatarPreset,
      box: Tokens.touchMin,
      ring: this.filterActive(),
      onTap: () => {
        this.onAvatar();
      }
    })
  }
}
