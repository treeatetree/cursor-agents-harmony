import { Tokens } from '../theme/Tokens';
import { Haptics } from '../utils/Haptics';
import { pressMs, pressScaleOf } from '../utils/Motion';

/**
 * HeroUI-style button: accent fill, 24 radius, press scale 0.97.
 * variant: primary | secondary | danger
 */
@Component
export struct HuButton {
  @Prop label: string = '';
  @Prop variant: string = 'primary';
  @Prop isEnabled: boolean = true;
  @Prop fillWidth: boolean = false;
  @State private pressed: boolean = false;
  onTap: () => void = () => {
  };

  private fg(): Resource {
    if (!this.isEnabled) {
      return $r('app.color.text_secondary');
    }
    if (this.variant === 'secondary') {
      return $r('app.color.text_primary');
    }
    return $r('app.color.accent_on');
  }

  private bg(): Resource {
    if (!this.isEnabled) {
      return $r('app.color.bg2');
    }
    if (this.variant === 'danger') {
      return $r('app.color.err');
    }
    if (this.variant === 'secondary') {
      return $r('app.color.bg2');
    }
    return $r('app.color.accent');
  }

  build() {
    Text(this.label)
      .fontSize(Tokens.typeCallout)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.fg())
      .textAlign(TextAlign.Center)
      .height(Tokens.controlHLg)
      .padding({ left: 18, right: 18 })
      .constraintSize({ minWidth: this.fillWidth ? 0 : 88 })
      .width(this.fillWidth ? '100%' : 'auto')
      .backgroundColor(this.bg())
      .borderRadius(Tokens.radiusMd)
      .border({
        width: this.isEnabled ? 0 : 1,
        color: $r('app.color.border_strong')
      })
      .scale({ x: pressScaleOf(this.isEnabled && this.pressed), y: pressScaleOf(this.isEnabled && this.pressed) })
      .opacity(this.isEnabled ? (this.pressed ? 0.82 : 1) : 1)
      .animation({ duration: pressMs(), curve: Curve.EaseOut })
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
          if (this.variant === 'danger') {
            Haptics.warn();
          } else if (this.variant === 'secondary') {
            Haptics.click();
          } else {
            Haptics.commit();
          }
          this.onTap();
        }
      })
  }
}
