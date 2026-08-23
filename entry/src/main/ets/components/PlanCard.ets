import { TimelineItem } from '../models/Timeline';
import { Tokens } from '../theme/Tokens';
import { fadeTransition, motionMs, pressMs, pressScaleOf, runLayout } from '../utils/Motion';
import { Haptics } from '../utils/Haptics';
import { PlanDoc, PlanTodo, planDocFromItem, previewTodos } from '../utils/PlanDoc';
import { HuIcon } from './HuIcon';
import { MarkdownLite } from './MarkdownLite';

@Component
export struct PlanCard {
  @Prop @Watch('onItem') item: TimelineItem = {
    key: '',
    kind: 'plan',
    runId: ''
  };
  @State opened: boolean = false;
  @State private pressed: boolean = false;
  private boundKey: string = '';
  onToggle: () => void = () => {
  };
  onQuote: (text: string) => void = (_text: string) => {
  };

  aboutToAppear(): void {
    this.bindItem();
  }

  onItem(_name: string): void {
    this.bindItem();
  }

  private bindItem(): void {
    if (this.item.key === this.boundKey) {
      this.opened = this.item.pinnedOpen === true || this.item.collapsed === false;
      return;
    }
    this.boundKey = this.item.key;
    this.opened = this.item.pinnedOpen === true || this.item.collapsed === false;
  }

  private doc(): PlanDoc {
    return planDocFromItem(this.item);
  }

  private title(): string {
    const n = this.doc().name;
    return n.length > 0 ? n : '计划';
  }

  private pathLine(): string {
    return this.item.usageShort ?? '';
  }

  private hasBody(): boolean {
    const d = this.doc();
    return d.body.trim().length > 0 || d.todos.length > 0 || d.overview.length > 0;
  }

  private shownTodos(): PlanTodo[] {
    return previewTodos(this.doc().todos, 3);
  }

  private moreCount(): number {
    const n = this.doc().todos.length;
    const shown = this.shownTodos().length;
    return n > shown ? n - shown : 0;
  }

  private todoDone(todo: PlanTodo): boolean {
    const s = (todo.status ?? '').toLowerCase();
    return s === 'completed' || s === 'done' || s === 'complete';
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

  @Builder
  todoRow(todo: PlanTodo, key: string) {
    Row({ space: 8 }) {
      Column()
        .width(10)
        .height(10)
        .borderRadius(5)
        .border({
          width: 1,
          color: $r('app.color.text_tertiary')
        })
        .backgroundColor(this.todoDone(todo) ? $r('app.color.text_primary') : Color.Transparent)
        .margin({ top: 4 })
      Text(todo.content)
        .fontSize(Tokens.typeCaption)
        .fontColor($r('app.color.text_primary'))
        .lineHeight(18)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 3, bottom: 3 })
    .alignItems(VerticalAlign.Top)
  }

  build() {
    Column({ space: 2 }) {
      Column({ space: 2 }) {
        Row({ space: 8 }) {
          HuIcon({
            name: 'plan',
            iconSize: 16,
            tint: $r('app.color.text_secondary')
          })
          Text(this.title())
            .fontSize(Tokens.typeCaption)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.hasBody()) {
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
        }
        .width('100%')
        .constraintSize({ minHeight: 28 })
        .alignItems(VerticalAlign.Center)

        if (this.pathLine().length > 0) {
          Text(this.pathLine())
            .fontSize(Tokens.typeMicro)
            .fontFamily(Tokens.fontMono)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .padding({ left: 24, right: 0, top: 0, bottom: 4 })
        }

        if (this.doc().overview.length > 0) {
          Text(this.doc().overview)
            .fontSize(Tokens.typeCaption)
            .fontFamily(Tokens.fontUi)
            .fontColor($r('app.color.text_secondary'))
            .lineHeight(Tokens.lineCaption)
            .maxLines(this.opened ? 8 : 3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .padding({ left: 24, right: 0, top: 0, bottom: this.opened ? 6 : 8 })
        }

        if (!this.opened && this.doc().todos.length > 0) {
          Text(`${this.doc().todos.length} 项待办`)
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
            .padding({ left: 24, top: 0, bottom: 4 })
        }

        if (this.opened && this.doc().body.length === 0 && this.doc().todos.length === 0 &&
          this.doc().overview.length === 0) {
          Text('计划还在写入')
            .fontSize(Tokens.typeCaption)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
            .padding({ left: 24, top: 0, bottom: 8 })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 10, right: 10, top: 8, bottom: 6 })
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

      if (this.opened && this.hasBody()) {
        Column({ space: 8 }) {
          if (this.doc().body.length > 0) {
            Column() {
              MarkdownLite({
                content: this.doc().body,
                compact: true,
                nested: true,
                onQuote: (t: string) => {
                  this.onQuote(t);
                }
              })
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 8, bottom: this.doc().todos.length > 0 ? 0 : 10 })
          }

          if (this.doc().todos.length > 0) {
            Column({ space: 4 }) {
              Text(`${this.doc().todos.length} 项待办`)
                .fontSize(Tokens.typeCaption)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
              ForEach(this.shownTodos(), (todo: PlanTodo, i: number) => {
                this.todoRow(todo, `todo-${i}-${todo.content}`)
              }, (todo: PlanTodo, i: number) => `todo-${i}-${todo.content}`)
              if (this.moreCount() > 0) {
                Text(`还有 ${this.moreCount()} 项`)
                  .fontSize(Tokens.typeCaption)
                  .fontColor($r('app.color.text_tertiary'))
                  .padding({ left: 18, top: 2 })
              }
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 8, bottom: 10 })
            .border({
              width: { top: 1 },
              color: $r('app.color.border')
            })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .transition(fadeTransition())
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.bg2'))
    .border({
      width: 1,
      color: $r('app.color.border')
    })
    .borderRadius(Tokens.radiusCard)
    .clip(true)
  }
}
