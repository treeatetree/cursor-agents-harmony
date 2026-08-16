import { TimelineItem } from '../models/Timeline';
import { Tokens } from '../theme/Tokens';
import { lastNonEmptyLine } from '../utils/StreamText';
import { shimmerMs, shimmerOpacity } from '../utils/Motion';
import { HuIcon } from './HuIcon';
import { MarkdownLite } from './MarkdownLite';
import { ToolCallRow } from './ToolCallRow';

@Component
export struct ActivityCard {
  @Prop @Watch('onItem') item: TimelineItem = {
    key: '',
    kind: 'progress',
    runId: ''
  };
  @Prop runActive: boolean = false;
  @Prop shimmerOn: boolean = false;
  @Prop title: string = '';
  @Prop body: string = '';
  @Prop tools: TimelineItem[] = [];
  @State opened: boolean = false;
  private boundKey: string = '';
  onToggle: () => void = () => {
  };
  onToggleTool: (key: string) => void = (_key: string) => {
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

  private hasBody(): boolean {
    return this.body.trim().length > 0 || this.tools.length > 0;
  }

  private preview(): string {
    return lastNonEmptyLine(this.body, 72);
  }

  build() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        if (this.hasBody()) {
          HuIcon({
            name: this.opened ? 'chevronDown' : 'chevronRight',
            iconSize: 16,
            tint: $r('app.color.text_secondary')
          })
        }
        Text(this.title)
          .fontSize(Tokens.typeCaption)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .opacity(this.runActive && this.item.streaming === true ? shimmerOpacity(this.shimmerOn) : 1)
          .animation({ duration: shimmerMs(), curve: Curve.EaseInOut })
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .constraintSize({ minHeight: Tokens.touchMin })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        if (!this.hasBody()) {
          return;
        }
        this.opened = !this.opened;
        this.onToggle();
      })

      if (!this.hasBody()) {
        Text('没有过程记录')
          .fontSize(Tokens.typeMicro)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .padding({ left: 22 })
      } else if (!this.opened) {
        if (this.preview().length > 0) {
          Text(this.preview())
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .padding({ left: 22 })
        }
      } else {
        if (this.body.trim().length > 0) {
          MarkdownLite({
            content: this.body,
            compact: true
          })
        }
        ForEach(this.tools, (tool: TimelineItem) => {
          ToolCallRow({
            item: tool,
            onToggle: () => {
              this.onToggleTool(tool.key);
            }
          })
        }, (tool: TimelineItem) => tool.key)
      }
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.bg2'))
    .borderRadius(Tokens.radiusMd)
  }
}
