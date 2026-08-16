import { Tokens } from '../theme/Tokens';
import { Haptics } from '../utils/Haptics';
import { pressMs, pressScaleOf } from '../utils/Motion';

@Component
export struct HuTextButton {
  @Prop label: string = '';
  @Prop color: Resource = $r('app.color.text_secondary');
  @Prop active: boolean = false;
  @Prop isEnabled: boolean = true;
  @Prop compact: boolean = false;
  @State private pressed: boolean = false;
  onTap: () => void = () => {
  };

  build() {
    Text(this.label)
      .fontSize(Tokens.typeCaption)
      .fontWeight(this.active ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.active ? $r('app.color.accent') : this.color)
      .constraintSize({
        minHeight: this.compact ? 32 : Tokens.touchMin,
        minWidth: this.compact ? 32 : Tokens.touchMin
      })
      .padding({ left: this.compact ? 6 : 8, right: this.compact ? 6 : 8 })
      .textAlign(TextAlign.Center)
      .scale({
        x: pressScaleOf(this.isEnabled && this.pressed),
        y: pressScaleOf(this.isEnabled && this.pressed)
      })
      .opacity(this.isEnabled ? (this.pressed ? 0.55 : 1) : 0.4)
      .animation({ duration: pressMs(), curve: Curve.EaseOut })
      .onTouch((e: TouchEvent) => {
        if (!this.isEnabled) {
          return;
        }
        if (e.type === TouchType.Down) {
          this.pressed = true;
          if (this.active) {
            Haptics.click();
          } else {
            Haptics.tick();
          }
        } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
          this.pressed = false;
        }
      })
      .onClick(() => {
        if (this.isEnabled) {
          this.onTap();
        }
      })
  }
}
