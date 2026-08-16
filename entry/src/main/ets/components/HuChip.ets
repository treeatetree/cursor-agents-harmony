import { Tokens } from '../theme/Tokens';
import { Haptics } from '../utils/Haptics';

/**
 * Chip: visual 32 / hit 44. Selected = bg2 + border, never ink fill.
 */
@Component
export struct HuChip {
  @Prop label: string = '';
  @Prop on: boolean = false;
  @Prop maxVp: number = 0;
  @State private pressed: boolean = false;
  onTap: () => void = () => {
  };

  build() {
    Row() {
      Text(this.label)
        .fontSize(Tokens.typeMicro)
        .fontWeight(this.on ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.on ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .height(32)
        .padding({ left: 10, right: 10 })
        .textAlign(TextAlign.Center)
        .backgroundColor(this.on ? $r('app.color.bg2') : Color.Transparent)
        .borderRadius(Tokens.radiusChip)
        .border({
          width: 1,
          color: this.on ? $r('app.color.border_strong') : $r('app.color.border')
        })
    }
    .constraintSize({
      minHeight: Tokens.touchMin,
      maxWidth: this.maxVp > 0 ? this.maxVp : 280
    })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .opacity(this.pressed ? 0.7 : 1)
    .animation({ duration: 120, curve: Curve.EaseOut })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => {
      Haptics.tick();
      this.onTap();
    })
  }
}
