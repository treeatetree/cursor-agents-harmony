import { Tokens } from '../theme/Tokens';
import { Haptics } from '../utils/Haptics';
import { AVATAR_IDS, avatarLabel, normalizeAvatarId } from '../utils/AvatarPresets';

@Component
export struct HuAvatar {
  @Prop preset: string = 'iridescent';
  @Prop box: number = Tokens.touchMin;
  @Prop ring: boolean = false;
  @State private pressed: boolean = false;
  onTap: () => void = () => {
  };

  build() {
    Column() {
      this.face()
    }
    .width(this.box)
    .height(this.box)
    .justifyContent(FlexAlign.Center)
    .borderRadius(this.box / 2)
    .clip(true)
    .border({
      width: this.ring ? 2 : 0,
      color: $r('app.color.accent')
    })
    .scale({
      x: this.pressed ? Tokens.pressScale : 1,
      y: this.pressed ? Tokens.pressScale : 1
    })
    .opacity(this.pressed ? 0.85 : 1)
    .animation({ duration: 120, curve: Curve.EaseOut })
    .accessibilityText(avatarLabel(this.preset))
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

  @Builder
  face() {
    if (normalizeAvatarId(this.preset) === 'opal') {
      Image($r('app.media.av_opal'))
        .width(this.box)
        .height(this.box)
        .objectFit(ImageFit.Cover)
        .borderRadius(this.box / 2)
    } else if (normalizeAvatarId(this.preset) === 'lagoon') {
      Image($r('app.media.av_lagoon'))
        .width(this.box)
        .height(this.box)
        .objectFit(ImageFit.Cover)
        .borderRadius(this.box / 2)
    } else if (normalizeAvatarId(this.preset) === 'emerald') {
      Image($r('app.media.av_emerald'))
        .width(this.box)
        .height(this.box)
        .objectFit(ImageFit.Cover)
        .borderRadius(this.box / 2)
    } else if (normalizeAvatarId(this.preset) === 'solar') {
      Image($r('app.media.av_solar'))
        .width(this.box)
        .height(this.box)
        .objectFit(ImageFit.Cover)
        .borderRadius(this.box / 2)
    } else if (normalizeAvatarId(this.preset) === 'orchid') {
      Image($r('app.media.av_orchid'))
        .width(this.box)
        .height(this.box)
        .objectFit(ImageFit.Cover)
        .borderRadius(this.box / 2)
    } else if (normalizeAvatarId(this.preset) === 'peach') {
      Image($r('app.media.av_peach'))
        .width(this.box)
        .height(this.box)
        .objectFit(ImageFit.Cover)
        .borderRadius(this.box / 2)
    } else if (normalizeAvatarId(this.preset) === 'tide') {
      Image($r('app.media.av_tide'))
        .width(this.box)
        .height(this.box)
        .objectFit(ImageFit.Cover)
        .borderRadius(this.box / 2)
    } else if (normalizeAvatarId(this.preset) === 'sunset') {
      Image($r('app.media.av_sunset'))
        .width(this.box)
        .height(this.box)
        .objectFit(ImageFit.Cover)
        .borderRadius(this.box / 2)
    } else if (normalizeAvatarId(this.preset) === 'mint') {
      Image($r('app.media.av_mint'))
        .width(this.box)
        .height(this.box)
        .objectFit(ImageFit.Cover)
        .borderRadius(this.box / 2)
    } else if (normalizeAvatarId(this.preset) === 'midnight') {
      Image($r('app.media.av_midnight'))
        .width(this.box)
        .height(this.box)
        .objectFit(ImageFit.Cover)
        .borderRadius(this.box / 2)
    } else if (normalizeAvatarId(this.preset) === 'rose') {
      Image($r('app.media.av_rose'))
        .width(this.box)
        .height(this.box)
        .objectFit(ImageFit.Cover)
        .borderRadius(this.box / 2)
    } else {
      Image($r('app.media.av_iridescent'))
        .width(this.box)
        .height(this.box)
        .objectFit(ImageFit.Cover)
        .borderRadius(this.box / 2)
    }
  }
}

@Component
export struct HuAvatarPicker {
  @Prop selected: string = 'iridescent';
  onPick: (id: string) => void = (_id: string) => {
  };

  build() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(AVATAR_IDS, (id: string) => {
        Column() {
          HuAvatar({
            preset: id,
            box: Tokens.touchMin,
            ring: this.selected === id,
            onTap: () => {
              this.onPick(id);
            }
          })
        }
        .width(52)
        .height(52)
        .justifyContent(FlexAlign.Center)
      }, (id: string) => id)
    }
    .width('100%')
  }
}
