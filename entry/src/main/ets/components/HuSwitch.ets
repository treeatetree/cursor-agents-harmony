import { Tokens } from '../theme/Tokens';
import { Haptics } from '../utils/Haptics';

@Component
export struct HuSwitch {
  @Prop on: boolean = false;
  @Prop label: string = '';
  @Prop hint: string = '';
  onToggle: () => void = () => {
  };

  build() {
    Row({ space: 12 }) {
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

      Row() {
        Column()
          .width(22)
          .height(22)
          .borderRadius(11)
          .backgroundColor($r('app.color.bg1'))
          .margin({ left: this.on ? 18 : 2 })
          .animation({ duration: 160, curve: Curve.EaseOut })
      }
      .width(46)
      .height(28)
      .borderRadius(14)
      .backgroundColor(this.on ? $r('app.color.accent') : $r('app.color.bg2'))
      .animation({ duration: 160, curve: Curve.EaseOut })
    }
    .width('100%')
    .constraintSize({ minHeight: Tokens.touchMin })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      Haptics.toggle();
      this.onToggle();
    })
  }
}
