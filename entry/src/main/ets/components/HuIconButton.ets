import { Tokens } from '../theme/Tokens';
import { Haptics } from '../utils/Haptics';
import { pressMs, pressScaleOf } from '../utils/Motion';
import { HuIcon } from './HuIcon';

@Component
export struct HuIconButton {
  @Prop name: string = 'more';
  @Prop label: string = '';
  @Prop iconColor: Resource = $r('app.color.text_primary');
  @Prop filled: boolean = false;
  @Prop accentFill: Resource = $r('app.color.accent');
  @Prop onColor: Resource = $r('app.color.accent_on');
  @Prop isEnabled: boolean = true;
  @State private pressed: boolean = false;
  onTap: () => void = () => {
  };

  build() {
    Column() {
      HuIcon({
        name: this.name,
        iconSize: 22,
        tint: this.filled ? this.onColor : this.iconColor
      })
    }
    .width(Tokens.touchMin)
    .height(Tokens.touchMin)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(Tokens.radiusPill)
    .backgroundColor(this.filled ? this.accentFill : Color.Transparent)
    .scale({
      x: pressScaleOf(this.isEnabled && this.pressed, this.filled),
      y: pressScaleOf(this.isEnabled && this.pressed, this.filled)
    })
    .opacity(this.isEnabled ? (this.pressed ? 0.7 : 1) : 0.4)
    .animation({ duration: pressMs(), curve: Curve.EaseOut })
    .accessibilityText(this.label)
    .onTouch((e: TouchEvent) => {
      if (!this.isEnabled) {
        return;
      }
        if (e.type === TouchType.Down) {
          this.pressed = true;
        } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
          this.pressed = false;
        }
    })
      .onClick(() => {
        if (this.isEnabled) {
          if (this.filled) {
            Haptics.commit();
          } else {
            Haptics.click();
          }
          this.onTap();
        }
      })
  }
}
