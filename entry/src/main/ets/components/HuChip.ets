import { Tokens } from '../theme/Tokens';
import { Haptics } from '../utils/Haptics';
import { pressMs, pressScaleOf } from '../utils/Motion';

/**
 * Chip: visual 32. Composer toolbar is 44 and centers this; do not wrap to 44
 * or Scroll/alignStart will park the pill at the top of the field.
 */
@Component
export struct HuChip {
  @Prop label: string = '';
  @Prop on: boolean = false;
  @Prop maxVp: number = 0;
  /** '' | plan — plan on uses a light-blue tint. */
  @Prop tone: string = '';
  @State private pressed: boolean = false;
  onTap: () => void = () => {
  };

  private planOn(): boolean {
    return this.on && this.tone === 'plan';
  }

  private ink(): Resource {
    if (this.planOn()) {
      return $r('app.color.plan_fg');
    }
    return this.on ? $r('app.color.text_primary') : $r('app.color.text_secondary');
  }

  private wash(): ResourceColor {
    if (this.planOn()) {
      return $r('app.color.plan_bg');
    }
    return this.on ? $r('app.color.bg2') : Color.Transparent;
  }

  private line(): Resource {
    if (this.planOn()) {
      return $r('app.color.plan_border');
    }
    return this.on ? $r('app.color.border_strong') : $r('app.color.border');
  }

  build() {
    Row() {
      Text(this.label)
        .fontSize(Tokens.typeMicro)
        .fontWeight(this.on ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.ink())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(32)
    .padding({ left: 10, right: 10 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.wash())
    .borderRadius(Tokens.radiusChip)
    .border({
      width: 1,
      color: this.line()
    })
    .constraintSize({ maxWidth: this.maxVp > 0 ? this.maxVp : 280 })
    .flexShrink(0)
    .alignSelf(ItemAlign.Start)
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
    .gesture(
      TapGesture()
        .onAction(() => {
          Haptics.tick();
          this.onTap();
        })
    )
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
          Haptics.click();
        } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
          this.pressed = false;
        }
      })
      .onClick(() => {
        this.onTap();
      })
  }
}
