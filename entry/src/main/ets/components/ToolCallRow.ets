import { TimelineItem } from '../models/Timeline';
import { Tokens } from '../theme/Tokens';
import { isSubagentTool } from '../utils/StreamText';
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
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        if (this.running()) {
          Column()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor($r('app.color.accent'))
        } else {
          HuIcon({
            name: 'check',
            iconSize: 14,
            tint: $r('app.color.text_secondary')
          })
        }
        if (this.isSub()) {
          Text('子任务')
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.accent'))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor($r('app.color.bg2'))
            .borderRadius(Tokens.radiusSm)
        }
        Text(this.item.text ?? this.item.tool?.name ?? 'tool')
          .fontSize(Tokens.typeCaption)
          .fontColor(this.isSub() ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
          .layoutWeight(1)
          .maxLines(this.isSub() ? 2 : 1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.canExpand()) {
          HuIcon({
            name: this.folded() ? 'chevronRight' : 'chevronDown',
            iconSize: 16,
            tint: $r('app.color.text_secondary')
          })
        }
      }
      .width('100%')
      .constraintSize({ minHeight: Tokens.touchMin })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        if (this.canExpand()) {
          this.opened = !this.opened;
          this.onToggle();
        }
      })

      if (!this.folded() && this.canExpand()) {
        if (this.item.tool?.truncatedArgs || this.item.tool?.truncatedResult) {
          Text('内容过大，已截断')
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.warn'))
            .width('100%')
            .padding({ left: 22 })
        }
        if (this.item.tool?.argsText) {
          Text(this.item.tool.argsText)
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.text_secondary'))
            .fontFamily('monospace')
            .width('100%')
            .padding({ left: 22 })
            .maxLines(16)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (this.item.tool?.resultText) {
          Text(this.item.tool.resultText)
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.text_primary'))
            .fontFamily('monospace')
            .width('100%')
            .padding({ left: 22 })
            .maxLines(28)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (!this.item.tool?.argsText && !this.item.tool?.resultText) {
          Text((this.item.text ?? '').length > 0 ? (this.item.text ?? '') : '没有输出')
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
            .padding({ left: 22 })
        }
      }
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 7, bottom: 7 })
    .backgroundColor(this.isSub() ? $r('app.color.accent_soft') : $r('app.color.bg2'))
    .borderRadius(Tokens.radiusMd)
  }
}
