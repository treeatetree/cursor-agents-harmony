import { Tokens } from '../theme/Tokens';
import { chromeTransition } from '../utils/Motion';
import { Haptics } from '../utils/Haptics';

/** Compact overlay chip — unread / sync / notice / error. Not a full-width banner. */
@Component
export struct StatusPill {
  @Prop text: string = '';
  @Prop loading: boolean = false;
  @Prop count: string = '';
  @Prop action: string = '';
  @Prop tone: string = 'info';
  @Prop dismissible: boolean = false;
  onTap: () => void = () => {
  };
  onAction: () => void = () => {
  };
  onDismiss: () => void = () => {
  };

  private ink(): Resource {
    if (this.tone === 'danger') {
      return $r('app.color.err');
    }
    if (this.tone === 'warn') {
      return $r('app.color.warn');
    }
    return $r('app.color.text_primary');
  }

  private wash(): Resource {
    if (this.tone === 'danger') {
      return $r('app.color.chip_err_bg');
    }
    if (this.tone === 'warn') {
      return $r('app.color.chip_warn_bg');
    }
    return $r('app.color.bg1');
  }

  private stroke(): Resource {
    if (this.tone === 'danger') {
      return $r('app.color.err');
    }
    if (this.tone === 'warn') {
      return $r('app.color.warn');
    }
    return $r('app.color.border_strong');
  }

  build() {
    if (this.text.length === 0) {
      Column().width(0).height(0)
    } else {
      Row({ space: 8 }) {
        Row({ space: 6 }) {
          if (this.loading) {
            LoadingProgress()
              .width(14)
              .height(14)
              .color(this.ink())
          }
          Text(this.text)
            .fontSize(Tokens.typeMicro)
            .fontFamily(Tokens.fontUi)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.ink())
            .maxLines(this.tone === 'info' ? 1 : 2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: this.tone === 'info' ? 220 : 280 })
          if (this.count.length > 0) {
            Text(this.count)
              .fontSize(Tokens.typeMicro)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.primary_on'))
              .constraintSize({ minWidth: 18, minHeight: 18 })
              .padding({ left: 5, right: 5 })
              .textAlign(TextAlign.Center)
              .backgroundColor($r('app.color.accent'))
              .borderRadius(Tokens.radiusPill)
          }
        }
        .constraintSize({ minHeight: 32 })
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(this.wash())
        .border({ width: 1, color: this.stroke() })
        .borderRadius(Tokens.radiusPill)
        .onClick(() => {
          Haptics.tick();
          this.onTap();
        })
        if (this.action.length > 0) {
          Row() {
            Text(this.action)
              .fontSize(Tokens.typeMicro)
              .fontFamily(Tokens.fontUi)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.ink())
          }
          .constraintSize({ minHeight: 32 })
          .padding({ left: 12, right: 12 })
          .backgroundColor(this.wash())
          .border({ width: 1, color: this.stroke() })
          .borderRadius(Tokens.radiusPill)
          .onClick(() => {
            Haptics.tick();
            this.onAction();
          })
        }
        if (this.dismissible) {
          Row() {
            Text('关闭')
              .fontSize(Tokens.typeMicro)
              .fontFamily(Tokens.fontUi)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
          }
          .constraintSize({ minHeight: 32 })
          .padding({ left: 12, right: 12 })
          .backgroundColor(this.wash())
          .border({ width: 1, color: this.stroke() })
          .borderRadius(Tokens.radiusPill)
          .onClick(() => {
            Haptics.tick();
            this.onDismiss();
          })
        }
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .transition(chromeTransition())
    }
  }
}
