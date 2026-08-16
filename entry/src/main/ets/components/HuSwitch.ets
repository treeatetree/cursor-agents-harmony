import { Tokens } from '../theme/Tokens';
import { Haptics } from '../utils/Haptics';
import { motionMs, prefersReducedMotion, pressMs, pressScaleOf } from '../utils/Motion';

@Component
export struct HuSwitch {
  @Prop on: boolean = false;
  @Prop label: string = '';
  @Prop hint: string = '';
  @State private pressed: boolean = false;
  onToggle: () => void = () => {
  };

  build() {
    Row() {
      Column({ space: 2 }) {
        Text(this.label)
          .fontSize(Tokens.typeBody)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        if (this.hint.length > 0) {
          Text(this.hint)
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width(44)
          .height(26)
          .borderRadius(999)
          .backgroundColor(this.on ? $r('app.color.accent') : $r('app.color.bg2'))
          .animation({ duration: motionMs(), curve: Curve.FastOutSlowIn })
        Column()
          .width(20)
          .height(20)
          .borderRadius(10)
          .backgroundColor($r('app.color.bg1'))
          .margin({ left: this.on ? 21 : 3, top: 3 })
          .animation({
            duration: motionMs(),
            curve: Curve.FastOutSlowIn
          })
      }
      .width(44)
      .height(26)
    }
    .width('100%')
    .constraintSize({ minHeight: Tokens.touchMin })
    .alignItems(VerticalAlign.Center)
    .scale({ x: pressScaleOf(this.pressed), y: pressScaleOf(this.pressed) })
    .opacity(this.pressed ? 0.7 : 1)
    .animation({ duration: pressMs(), curve: Curve.EaseOut })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => {
      Haptics.toggle();
      this.onToggle();
    })
  }
}
