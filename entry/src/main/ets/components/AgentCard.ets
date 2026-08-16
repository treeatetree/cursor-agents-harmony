import { AgentSummary } from '../models/Api';
import { Tokens } from '../theme/Tokens';
import { relativeTime } from '../utils/TimeFmt';
import { repoTail, shortAgentId, elapsedSince } from '../utils/DisplayFmt';
import { firstPrUrl, hasPr, isRunInFlight, userStampIso } from '../utils/InboxGrouping';
import { Haptics } from '../utils/Haptics';
import { motionMs, pressScaleOf } from '../utils/Motion';

@Component
export struct AgentCard {
  @Prop @Watch('onAgent') agent: AgentSummary = {
    id: '',
    name: '',
    status: 'ACTIVE',
    url: '',
    createdAt: '',
    updatedAt: ''
  };
  @Prop showRepo: boolean = false;
  @Prop preview: string = '';
  @Prop list: boolean = false;
  @Prop pinned: boolean = false;
  @Prop unread: boolean = false;
  @Prop active: boolean = false;
  @State private pressed: boolean = false;
  @State private tick: number = 0;
  private skipOpen: boolean = false;
  private timer: number = -1;
  onOpen: (id: string) => void = () => {
  };
  onLong: (agent: AgentSummary) => void = () => {
  };
  onOpenPr: (url: string) => void = () => {
  };

  aboutToAppear(): void {
    this.armTick();
  }

  onAgent(_name: string): void {
    this.armTick();
  }

  aboutToDisappear(): void {
    this.clearTick();
  }

  private armTick(): void {
    this.clearTick();
    if (!this.running()) {
      return;
    }
    this.timer = setInterval(() => {
      this.tick += 1;
    }, 1000) as number;
  }

  private clearTick(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private running(): boolean {
    return isRunInFlight(`${this.agent.latestRunStatus ?? ''}`);
  }

  private failed(): boolean {
    const r = `${this.agent.latestRunStatus ?? ''}`;
    return r === 'ERROR' || r === 'EXPIRED';
  }

  private statusLabel(): string {
    if (this.agent.status === 'ARCHIVED') {
      return '已归档';
    }
    if (this.running()) {
      return '';
    }
    if (this.failed()) {
      return '失败';
    }
    const r = `${this.agent.latestRunStatus ?? ''}`;
    if (r === 'CANCELLED') {
      return '已取消';
    }
    return '';
  }

  private statusColor(): Resource {
    if (this.failed()) {
      return $r('app.color.err');
    }
    if (this.running()) {
      return $r('app.color.accent');
    }
    return $r('app.color.text_tertiary');
  }

  private titleText(): string {
    return this.agent.name.length > 0 ? this.agent.name : shortAgentId(this.agent.id);
  }

  private lineText(): string {
    if (this.list) {
      return '';
    }
    if (this.preview.length > 0) {
      return this.preview;
    }
    const result = this.agent.latestResult ?? '';
    if (result.length > 0) {
      return result;
    }
    if (this.agent.repos && this.agent.repos.length > 0) {
      return repoTail(this.agent.repos[0].url ?? '');
    }
    return '无结果';
  }

  private timeText(): string {
    const when = userStampIso(this.agent);
    if (this.running()) {
      const _n = this.tick;
      return elapsedSince(when) || '0s';
    }
    return relativeTime(when);
  }

  private prText(): string {
    const u = firstPrUrl(this.agent);
    if (u.length === 0) {
      return '';
    }
    const m = u.match(/\/pull\/(\d+)/);
    if (m && m[1]) {
      return `PR ${m[1]}`;
    }
    return 'PR';
  }

  build() {
    Column({ space: this.list ? 4 : 6 }) {
      Text(this.titleText())
        .fontSize(Tokens.typeBody)
        .fontFamily(Tokens.fontUi)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .lineHeight(Tokens.lineBody)
        .maxLines(this.list ? 1 : 2)
        .constraintSize({
          minHeight: Tokens.lineBody,
          maxHeight: this.list ? Tokens.lineBody : Tokens.lineBody * 2
        })
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      if (!this.list) {
        Text(this.lineText())
          .fontSize(Tokens.typeMicro)
          .fontFamily(Tokens.fontUi)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(Tokens.lineMicro)
          .maxLines(1)
          .height(Tokens.lineMicro)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      Blank().layoutWeight(1)

      Row({ space: 8 }) {
        if (this.unread) {
          Column()
            .width(6)
            .height(6)
            .borderRadius(3)
            .backgroundColor($r('app.color.text_primary'))
        }
        if (this.pinned) {
          Text('置顶')
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.text_tertiary'))
        }
        if (this.statusLabel().length > 0) {
          Text(this.statusLabel())
            .fontSize(Tokens.typeMicro)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.statusColor())
        }
        if (this.prText().length > 0) {
          Text(this.prText())
            .fontSize(Tokens.typeMicro)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .onClick(() => {
              this.skipOpen = true;
              Haptics.tick();
              this.onOpenPr(firstPrUrl(this.agent));
            })
        }
        Blank().layoutWeight(1)
        Text(this.timeText())
          .fontSize(Tokens.typeMicro)
          .fontColor(this.running() ? $r('app.color.accent') : $r('app.color.text_tertiary'))
      }
      .width('100%')
      .height(16)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(this.list ? Tokens.listCardH : Tokens.cardH)
    .alignItems(HorizontalAlign.Start)
    .padding(this.list ? {
      left: 14,
      right: 14,
      top: 12,
      bottom: 12
    } : {
      left: Tokens.cardPad,
      right: Tokens.cardPad,
      top: Tokens.cardPad,
      bottom: Tokens.cardPad
    })
    .backgroundColor(this.active ? $r('app.color.bg2') : (this.pressed ? $r('app.color.bg_hover') : $r('app.color.bg1')))
    .border({
      width: 1,
      color: this.running() ? $r('app.color.accent') : $r('app.color.border')
    })
    .borderRadius(this.list ? 12 : Tokens.radiusCard)
    .scale({ x: pressScaleOf(this.pressed), y: pressScaleOf(this.pressed) })
    .animation({ duration: motionMs(), curve: Curve.EaseOut })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => {
      if (this.skipOpen) {
        this.skipOpen = false;
        return;
      }
      this.onOpen(this.agent.id);
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          Haptics.press();
          this.onLong(this.agent);
        })
    )
  }
}
