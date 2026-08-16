import { AgentSummary } from '../models/Api';
import { Tokens } from '../theme/Tokens';
import { relativeTime } from '../utils/TimeFmt';
import { shortRepoName } from '../utils/DisplayFmt';

@Reusable
@Component
export struct AgentRow {
  @Prop agent: AgentSummary = {
    id: '',
    name: '',
    status: 'ACTIVE',
    url: '',
    createdAt: '',
    updatedAt: ''
  };
  /** Optional secondary line override. */
  @Prop subtitle: string = '';
  /** When true, show running status. */
  @Prop running: boolean = false;
  @State private pressed: boolean = false;
  onOpen: (id: string) => void = () => {
  };
  onLong: (agent: AgentSummary) => void = () => {
  };

  aboutToReuse(): void {
    // Reset transient state when the reusable component is recycled to a new row.
    this.pressed = false;
  }

  private isRunning(): boolean {
    return this.running || this.agent.latestRunStatus === 'RUNNING' ||
      this.agent.latestRunStatus === 'CREATING';
  }

  /** Returns a short status word or '' for default ok state. */
  private statusLabel(): string {
    if (this.agent.status === 'ARCHIVED') {
      return '已归档';
    }
    const r = this.agent.latestRunStatus;
    if (r === 'RUNNING' || r === 'CREATING') {
      return '运行中';
    }
    if (r === 'ERROR') {
      return '失败';
    }
    if (r === 'CANCELLED') {
      return '已取消';
    }
    if (r === 'EXPIRED') {
      return '已过期';
    }
    return '';
  }

  /** Linear-style rail color for the status edge. */
  private railColor(): Resource {
    if (this.agent.status === 'ARCHIVED') {
      return $r('app.color.text_tertiary');
    }
    const r = this.agent.latestRunStatus;
    if (r === 'RUNNING' || r === 'CREATING') {
      return $r('app.color.accent');
    }
    if (r === 'ERROR' || r === 'EXPIRED') {
      return $r('app.color.err');
    }
    if (r === 'CANCELLED') {
      return $r('app.color.warn');
    }
    // FINISHED, undefined, or anything else — treat idle/ready as a calm "ok" tint
    // so the rail is always visible on light bg.
    return $r('app.color.ok');
  }

  /** Status label tone color. */
  private statusTone(): Resource {
    if (this.agent.status === 'ARCHIVED') {
      return $r('app.color.text_tertiary');
    }
    const r = this.agent.latestRunStatus;
    if (r === 'RUNNING' || r === 'CREATING') {
      return $r('app.color.accent');
    }
    if (r === 'ERROR' || r === 'EXPIRED') {
      return $r('app.color.err');
    }
    if (r === 'CANCELLED') {
      return $r('app.color.warn');
    }
    return $r('app.color.text_tertiary');
  }

  private repoLine(): string {
    if (this.subtitle.length > 0) {
      return this.subtitle;
    }
    if (this.agent.repos && this.agent.repos.length > 0) {
      return shortRepoName(this.agent.repos[0].url ?? '');
    }
    if (this.agent.env?.name && this.agent.env.name.length > 0) {
      return this.agent.env.name;
    }
    return '';
  }

  build() {
    Row({ space: Tokens.space3 }) {
      // Status pill — fixed-size so it always renders, regardless of Row alignment quirks.
      Column()
        .width(4)
        .height(28)
        .borderRadius(2)
        .backgroundColor(this.railColor())
        .margin({ top: 14 })

      Column({ space: 3 }) {
        Text(this.agent.name.length > 0 ? this.agent.name : this.agent.id)
          .fontSize(Tokens.typeBody)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: 8 }) {
          if (this.statusLabel().length > 0) {
            Text(this.statusLabel())
              .fontSize(Tokens.typeMicro)
              .fontColor(this.statusTone())
          }
          if (this.repoLine().length > 0) {
            Text(this.repoLine())
              .fontSize(Tokens.typeMicro)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          } else {
            Blank().layoutWeight(1)
          }
          Text(relativeTime(this.agent.updatedAt || this.agent.createdAt))
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: 0,
        right: Tokens.pagePad,
        top: Tokens.space3,
        bottom: Tokens.space3
      })
      .backgroundColor(this.pressed ? $r('app.color.bg_hover') : Color.Transparent)
      .animation({ duration: 120, curve: Curve.EaseOut })
      .onClick(() => {
        this.onOpen(this.agent.id);
      })
      .gesture(
        LongPressGesture({ repeat: false })
          .onAction(() => {
            this.onLong(this.agent);
          })
      )
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.pressed = true;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressed = false;
        }
      })
    }
    .width('100%')
    .padding({ left: Tokens.pagePad - Tokens.space1 })
    .constraintSize({ minHeight: Tokens.rowMin })
    .border({ width: { bottom: 1 }, color: $r('app.color.border') })
  }
}
