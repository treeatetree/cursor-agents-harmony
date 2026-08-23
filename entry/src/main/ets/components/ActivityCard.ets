import { TimelineItem } from '../models/Timeline';
import { Tokens } from '../theme/Tokens';
import { lastNonEmptyLine } from '../utils/StreamText';
import { fadeTransition, motionMs, pressMs, pressScaleOf, runLayout, shimmerMs, shimmerOpacity } from '../utils/Motion';
import { Haptics } from '../utils/Haptics';
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
  /** full = one card. head/body kept for callers that still pass chrome. */
  @Prop chrome: string = 'full';
  @State opened: boolean = false;
  @State promptOpen: boolean = false;
  @State private pressed: boolean = false;
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
    this.promptOpen = false;
  }

  private promptBody(): string {
    return (this.item.promptText ?? '').trim();
  }

  private hasBody(): boolean {
    return this.body.trim().length > 0 || this.tools.length > 0 || this.promptBody().length > 0;
  }

  private preview(): string {
    const body = lastNonEmptyLine(this.body, 72);
    if (body.length > 0) {
      return body;
    }
    return lastNonEmptyLine(this.promptBody(), 72);
  }

  private showHead(): boolean {
    return this.chrome !== 'body';
  }

  private showBody(): boolean {
    return this.chrome !== 'head' && this.opened && this.hasBody();
  }

  private cardRadiusTop(): number {
    return this.chrome === 'body' ? 0 : Tokens.radiusMd;
  }

  private cardRadiusBottom(): number {
    return this.chrome === 'head' && this.opened ? 0 : Tokens.radiusMd;
  }

  private padTop(): number {
    return this.chrome === 'body' ? 2 : 6;
  }

  private padBottom(): number {
    if (this.chrome === 'head' && this.opened) {
      return 4;
    }
    return 6;
  }

  private toggleOpen(): void {
    if (!this.hasBody()) {
      return;
    }
    runLayout(() => {
      this.opened = !this.opened;
      this.onToggle();
    });
  }

  build() {
    Column({ space: 2 }) {
      if (this.showHead()) {
        Column({ space: 2 }) {
          Row({ space: 6 }) {
            if (this.item.streaming === true) {
              LoadingProgress()
                .width(14)
                .height(14)
                .color($r('app.color.text_secondary'))
            } else if (this.hasBody()) {
              Column() {
                HuIcon({
                  name: 'chevronRight',
                  iconSize: 16,
                  tint: $r('app.color.text_secondary')
                })
              }
              .width(16)
              .height(16)
              .rotate({ angle: this.opened ? 90 : 0 })
              .animation({ duration: motionMs(), curve: Curve.FastOutSlowIn })
            }
            Text(this.title)
              .fontSize(Tokens.typeCaption)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .opacity(this.runActive && this.item.streaming === true ? shimmerOpacity(this.shimmerOn) : 1)
              .animation({ duration: shimmerMs(), curve: Curve.EaseInOut })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '55%' })
            if (!this.opened && this.preview().length > 0) {
              Text(this.preview())
                .fontSize(Tokens.typeMicro)
                .fontColor($r('app.color.text_tertiary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            } else {
              Blank()
            }
          }
          .width('100%')
          .constraintSize({ minHeight: 24 })
          .alignItems(VerticalAlign.Center)

          if (!this.hasBody() && this.item.streaming !== true) {
            Text('此设备未记录过程')
              .fontSize(Tokens.typeMicro)
              .fontColor($r('app.color.text_tertiary'))
              .width('100%')
              .padding({ left: 22 })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .scale({ x: pressScaleOf(this.pressed), y: pressScaleOf(this.pressed) })
        .opacity(this.pressed ? 0.88 : 1)
        .animation({ duration: pressMs(), curve: Curve.EaseOut })
        .onTouch((e: TouchEvent) => {
          if (!this.hasBody()) {
            return;
          }
          if (e.type === TouchType.Down) {
            this.pressed = true;
          } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
            this.pressed = false;
          }
        })
        .onClick(() => {
          if (this.hasBody()) {
            Haptics.tick();
          }
          this.toggleOpen();
        })
      }

      if (this.showBody()) {
        Column({ space: 2 }) {
          if (this.promptBody().length > 0) {
            Row({ space: 6 }) {
              Column() {
                HuIcon({
                  name: 'chevronRight',
                  iconSize: 12,
                  tint: $r('app.color.text_tertiary')
                })
              }
              .width(12)
              .height(12)
              .rotate({ angle: this.promptOpen ? 90 : 0 })
              .animation({ duration: motionMs(), curve: Curve.FastOutSlowIn })
              Text('子任务提示词')
                .fontSize(Tokens.typeMicro)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .constraintSize({ minHeight: 20 })
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              Haptics.tick();
              runLayout(() => {
                this.promptOpen = !this.promptOpen;
              });
            })
            if (this.promptOpen) {
              Column() {
                MarkdownLite({
                  content: this.promptBody(),
                  compact: true,
                  nested: true
                })
              }
              .width('100%')
              .padding({ left: 18 })
              .transition(fadeTransition())
            }
          }
          if (this.body.trim().length > 0) {
            MarkdownLite({
              content: this.body,
              compact: true,
              nested: true
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
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .transition(fadeTransition())
      }
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: this.padTop(), bottom: this.padBottom() })
    .backgroundColor($r('app.color.bg2'))
    .borderRadius({
      topLeft: this.cardRadiusTop(),
      topRight: this.cardRadiusTop(),
      bottomLeft: this.cardRadiusBottom(),
      bottomRight: this.cardRadiusBottom()
    })
  }
}
