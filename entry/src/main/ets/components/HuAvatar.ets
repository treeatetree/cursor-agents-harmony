import { Tokens } from '../theme/Tokens';
import { Haptics } from '../utils/Haptics';
import { cleanImageUri, isSafeImageUri } from '../utils/ImagePicker';
import { pressMs, pressScaleOf } from '../utils/Motion';
import { AVATAR_IDS, avatarLabel, normalizeAvatarId } from '../utils/AvatarPresets';

@Component
export struct HuAvatar {
  @Prop preset: string = 'iridescent';
  @Prop @Watch('onPhotoUri') photoUri: string = '';
  @Prop box: number = Tokens.touchMin;
  @Prop ring: boolean = false;
  @Prop haptic: boolean = true;
  @State private pressed: boolean = false;
  @State private photoFailed: boolean = false;
  onTap: () => void = () => {
  };

  onPhotoUri(_name: string): void {
    this.photoFailed = false;
  }

  private canShowPhoto(): boolean {
    return !this.photoFailed && this.preset === 'custom' && isSafeImageUri(this.photoUri);
  }

  build() {
    Column() {
      this.face()
    }
    .width(this.box)
    .height(this.box)
    .justifyContent(FlexAlign.Center)
    .borderRadius(this.box / 2)
    .clip(true)
    .scale({
      x: pressScaleOf(this.pressed, true),
      y: pressScaleOf(this.pressed, true)
    })
    .opacity(this.pressed ? 0.78 : 1)
    .animation({ duration: pressMs(), curve: Curve.EaseOut })
    .accessibilityText(avatarLabel(this.preset))
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
        if (this.haptic) {
          Haptics.click();
        }
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => {
      this.onTap();
    })
  }

  @Builder
  face() {
    if (this.canShowPhoto()) {
      Image(cleanImageUri(this.photoUri))
        .width(this.box)
        .height(this.box)
        .objectFit(ImageFit.Cover)
        .borderRadius(this.box / 2)
        .onError(() => {
          this.photoFailed = true;
        })
    } else if (normalizeAvatarId(this.preset) === 'opal') {
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
  @Prop photoUri: string = '';
  onPick: (id: string) => void = (_id: string) => {
  };
  onPhoto: () => void = () => {
  };

  build() {
    Column({ space: 8 }) {
      Flex({ wrap: FlexWrap.Wrap }) {
        Column() {
          if (isSafeImageUri(this.photoUri)) {
            Image(cleanImageUri(this.photoUri))
              .width(Tokens.touchMin)
              .height(Tokens.touchMin)
              .objectFit(ImageFit.Cover)
              .borderRadius(Tokens.touchMin / 2)
          } else {
            Text('+')
              .fontSize(20)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .width(52)
        .height(52)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.selected === 'custom' ? $r('app.color.bg2') : $r('app.color.bg1'))
        .borderRadius(26)
        .border({ width: 1, color: $r('app.color.border') })
        .onClick(() => {
          this.onPhoto();
        })
        ForEach(AVATAR_IDS, (id: string) => {
          Column() {
            HuAvatar({
              preset: id,
              box: Tokens.touchMin,
              haptic: false,
              onTap: () => {
                this.onPick(id);
              }
            })
          }
          .width(52)
          .height(52)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.selected === id ? $r('app.color.bg2') : Color.Transparent)
          .borderRadius(26)
        }, (id: string) => id)
      }
      .width('100%')
      Text('选完后可拖动、捏合')
        .fontSize(Tokens.typeMicro)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
