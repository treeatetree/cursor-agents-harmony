import { TimelineItem } from '../models/Timeline';
import { Tokens } from '../theme/Tokens';
import { isSubagentTool } from '../utils/StreamText';
import { fadeTransition, motionMs, runLayout } from '../utils/Motion';
import { HuIcon } from './HuIcon';

@Component
export struct ToolCallRow {
  @Prop @Watch('onItem') item: TimelineItem = {
    key: '',
    kind: 'tool',
    runId: ''
  };
  @State opened: boolean = false;
  private boundKey: string = '';
  onToggle: () => void = () => {
  };

  aboutToAppear(): void {
    this.bindItem();
  }

  onItem(_name: string): void {
    this.bindItem();
  }

  private bindItem(): void {
    if (this.item.key === this.boundKey) {
      return;
    }
    this.boundKey = this.item.key;
    this.opened = this.item.collapsed === false;
  }

  private running(): boolean {
    return (this.item.tool?.status ?? 'running') !== 'completed';
  }

  private canExpand(): boolean {
    const t = this.item.tool;
    if (!t) {
      return (this.item.text ?? '').trim().length > 0;
    }
    return true;
  }

  private folded(): boolean {
    return !this.opened;
  }

  private isSub(): boolean {
    return isSubagentTool(this.item.tool?.name ?? '');
  }

  build() {
    Column({ space: 2 }) {
      Row({ space: 6 }) {
        if (this.running()) {
          Column()
            .width(6)
            .height(6)
            .borderRadius(3)
            .backgroundColor($r('app.color.accent'))
        } else {
          HuIcon({
            name: 'check',
            iconSize: 12,
            tint: $r('app.color.text_secondary')
          })
        }
        if (this.isSub()) {
          Text('子任务')
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.accent'))
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .backgroundColor($r('app.color.bg1'))
            .borderRadius(Tokens.radiusSm)
        }
        Text(this.item.text ?? this.item.tool?.name ?? 'tool')
          .fontSize(Tokens.typeMicro)
          .fontColor(this.isSub() ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
          .layoutWeight(1)
          .maxLines(this.isSub() ? 2 : 1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.canExpand()) {
          Column() {
            HuIcon({
              name: 'chevronRight',
              iconSize: 12,
              tint: $r('app.color.text_tertiary')
            })
          }
          .width(12)
          .height(12)
          .rotate({ angle: this.opened ? 90 : 0 })
          .animation({ duration: motionMs(), curve: Curve.FastOutSlowIn })
        }
      }
      .width('100%')
      .constraintSize({ minHeight: 20 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        if (this.canExpand()) {
          runLayout(() => {
            this.opened = !this.opened;
            this.onToggle();
          });
        }
      })

      if (!this.folded() && this.canExpand()) {
        Column({ space: 2 }) {
          if (this.item.tool?.truncatedArgs || this.item.tool?.truncatedResult) {
            Text('内容过大，已截断')
              .fontSize(Tokens.typeMicro)
              .fontColor($r('app.color.warn'))
              .width('100%')
              .padding({ left: 18 })
          }
          if (this.item.tool?.argsText) {
            Text(this.item.tool.argsText)
              .fontSize(Tokens.typeMicro)
              .fontColor($r('app.color.text_secondary'))
              .fontFamily(Tokens.fontMono)
              .width('100%')
              .padding({ left: 18 })
              .maxLines(12)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          if (this.item.tool?.resultText) {
            Text(this.item.tool.resultText)
              .fontSize(Tokens.typeMicro)
              .fontColor($r('app.color.text_primary'))
              .fontFamily(Tokens.fontMono)
              .width('100%')
              .padding({ left: 18 })
              .maxLines(20)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          if (!this.item.tool?.argsText && !this.item.tool?.resultText) {
            Text((this.item.text ?? '').length > 0 ? (this.item.text ?? '') : '没有输出')
              .fontSize(Tokens.typeMicro)
              .fontColor($r('app.color.text_tertiary'))
              .width('100%')
              .padding({ left: 18 })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .transition(fadeTransition())
      }
    }
    .width('100%')
    .padding({ left: 0, right: 0, top: 3, bottom: 3 })
  }
}
