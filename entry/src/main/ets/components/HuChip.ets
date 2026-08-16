import { Tokens } from '../theme/Tokens';
import { Haptics } from '../utils/Haptics';
import { motionMs, pressMs, pressScaleOf } from '../utils/Motion';

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
        .animation({ duration: motionMs(), curve: Curve.FastOutSlowIn })
    }
    .constraintSize({
      minHeight: Tokens.touchMin,
      maxWidth: this.maxVp > 0 ? this.maxVp : 280
    })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .scale({ x: pressScaleOf(this.pressed), y: pressScaleOf(this.pressed) })
    .opacity(this.pressed ? 0.82 : 1)
    .animation({ duration: pressMs(), curve: Curve.EaseOut })
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

/** Ink action on banners: 重连 / 重试 / 重发. */
@Component
export struct HuActionChip {
  @Prop label: string = '';
  @State private pressed: boolean = false;
  onTap: () => void = () => {
  };

  build() {
    Text(this.label)
      .fontSize(Tokens.typeCaption)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.accent_on'))
      .constraintSize({ minHeight: 32 })
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .textAlign(TextAlign.Center)
      .backgroundColor($r('app.color.accent'))
      .borderRadius(Tokens.radiusChip)
      .scale({
        x: pressScaleOf(this.pressed),
        y: pressScaleOf(this.pressed)
      })
      .opacity(this.pressed ? 0.82 : 1)
      .animation({ duration: pressMs(), curve: Curve.EaseOut })
      .onTouch((e: TouchEvent) => {
        if (e.type === TouchType.Down) {
          this.pressed = true;
        } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
          this.pressed = false;
        }
      })
      .onClick(() => {
        Haptics.click();
        this.onTap();
      })
  }
}
