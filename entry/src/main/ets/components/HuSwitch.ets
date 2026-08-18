import { Tokens } from '../theme/Tokens';
import { Haptics } from '../utils/Haptics';

/**
 * beUI switch: 44×26 track, 20 thumb, 3 inset, 18 travel.
 * Do not use Stack+clip or parent .animation() — both ghost/clip the thumb on device.
 */
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
          .width(20)
          .height(20)
          .borderRadius(10)
          .backgroundColor(this.on ? $r('app.color.accent_on') : $r('app.color.switch_knob'))
          .margin({ left: this.on ? 21 : 3 })
      }
      .width(44)
      .height(26)
      .justifyContent(FlexAlign.Start)
      .alignItems(VerticalAlign.Center)
      .borderRadius(13)
      .backgroundColor(this.on ? $r('app.color.accent') : $r('app.color.switch_off'))
      .flexShrink(0)
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
