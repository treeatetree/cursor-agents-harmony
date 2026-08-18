import { AgentSummary } from '../models/Api';
import { Tokens } from '../theme/Tokens';
import { relativeTime } from '../utils/TimeFmt';
import { repoTail, shortAgentId, elapsedSince } from '../utils/DisplayFmt';
import { firstPrUrl, hasPr, isRunInFlight, userStampIso } from '../utils/InboxGrouping';
import { Haptics } from '../utils/Haptics';
import { pressMs, pressScaleOf } from '../utils/Motion';
import { PrefStore } from '../store/PrefStore';
import { HuIcon } from './HuIcon';
import { WaveDots } from './WaveDots';

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
  @Prop @Watch('onUnread') unread: boolean = false;
  @Prop active: boolean = false;
  @StorageLink('aliasRev') aliasRev: number = 0;
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

  onUnread(_name: string): void {
    if (this.running()) {
      this.armTick();
    }
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
    const api = `${this.agent.name ?? ''}`;
    const name = PrefStore.getInstance().displayName(`${this.agent.id ?? ''}`, api);
    return name.length > 0 ? name : shortAgentId(`${this.agent.id ?? ''}`);
  }

  private lineText(): string {
    if (this.list) {
      return '';
    }
    const preview = `${this.preview ?? ''}`;
    if (preview.length > 0) {
      return preview;
    }
    const result = `${this.agent.latestResult ?? ''}`;
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

  private repoLabel(): string {
    if (this.agent.repos && this.agent.repos.length > 0) {
      const name = repoTail(this.agent.repos[0].url ?? '');
      if (name.length > 0) {
        return name;
      }
    }
    const env = `${this.agent.env?.name ?? ''}`;
    return env;
  }

  private footerRepo(): string {
    if (this.pinned || this.showRepo) {
      return this.repoLabel();
    }
    return '';
  }

  private hasCorner(): boolean {
    return this.running();
  }

  private sidePad(): number {
    return (this.list ? 14 : Tokens.cardPad) + (this.hasCorner() ? 12 : 0);
  }

  private cardStrokeW(): number {
    if (this.unread) {
      return 2;
    }
    if (this.running()) {
      return 1.5;
    }
    return 1;
  }

  private cardStroke(): Resource {
    if (this.running()) {
      return $r('app.color.accent');
    }
    if (this.unread) {
      return $r('app.color.unread_ring');
    }
    return $r('app.color.border');
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column({ space: this.list ? 4 : 6 }) {
      Text(this.titleText())
        .fontSize(Tokens.typeBody)
        .fontFamily(Tokens.fontUi)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .lineHeight(Tokens.lineBody)
        .maxLines(1)
        .constraintSize({
          minHeight: Tokens.lineBody,
          maxHeight: Tokens.lineBody
        })
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      if (!this.list) {
        Text(this.lineText())
          .fontSize(Tokens.typeMicro)
          .fontFamily(Tokens.fontUi)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(Tokens.lineMicro)
          .maxLines(2)
          .constraintSize({
            minHeight: Tokens.lineMicro,
            maxHeight: Tokens.lineMicro * 2
          })
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      Blank().layoutWeight(1)

      Row({ space: 8 }) {
        if (this.footerRepo().length > 0) {
          Text(this.footerRepo())
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .constraintSize({ minWidth: 0 })
        }
        if (this.statusLabel().length > 0) {
          Text(this.statusLabel())
            .fontSize(Tokens.typeMicro)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.statusColor())
            .flexShrink(0)
        }
        if (this.prText().length > 0) {
          Row({ space: 3 }) {
            Text(this.prText())
              .fontSize(Tokens.typeMicro)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            HuIcon({
              name: 'external',
              iconSize: 10,
              tint: $r('app.color.text_tertiary')
            })
          }
          .alignItems(VerticalAlign.Center)
          .flexShrink(0)
          .onClick(() => {
            this.skipOpen = true;
            Haptics.tick();
            this.onOpenPr(firstPrUrl(this.agent));
          })
        }
        if (this.footerRepo().length === 0) {
          Blank().layoutWeight(1)
        }
        Text(this.timeText())
          .fontSize(Tokens.typeMicro)
          .fontColor(this.running() ? $r('app.color.accent') : $r('app.color.text_tertiary'))
          .flexShrink(0)
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
      right: this.sidePad(),
      top: 12,
      bottom: 12
    } : {
      left: Tokens.cardPad,
      right: this.sidePad(),
      top: Tokens.cardPad,
      bottom: Tokens.cardPad
    })
    .backgroundColor(this.active ? $r('app.color.bg2') : (this.pressed ? $r('app.color.bg_hover') : $r('app.color.bg1')))
    .border({
      width: this.cardStrokeW(),
      color: this.cardStroke()
    })
    .borderRadius(this.list ? 12 : Tokens.radiusCard)
    .scale({ x: pressScaleOf(this.pressed), y: pressScaleOf(this.pressed) })
    .animation({ duration: pressMs(), curve: Curve.EaseOut })
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
      Haptics.soft();
      this.onOpen(this.agent.id);
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          Haptics.press();
          this.onLong(this.agent);
        })
    )
      if (this.running()) {
        WaveDots({ tint: $r('app.color.text_tertiary') })
          .margin({ top: 8, right: 8 })
          .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
  }
}
