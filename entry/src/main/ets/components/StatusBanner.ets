import { Tokens } from '../theme/Tokens';
import { chromeTransition } from '../utils/Motion';
import { HuTextButton } from './HuTextButton';

/** Inbox / detail shared strip: info, warn, danger + optional action. */
@Component
export struct StatusBanner {
  @Prop text: string = '';
  @Prop tone: string = 'info';
  @Prop action: string = '';
  onAction: () => void = () => {
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
      return $r('app.color.banner_error_bg');
    }
    if (this.tone === 'warn') {
      return $r('app.color.banner_offline_bg');
    }
    return $r('app.color.bg2');
  }

  build() {
    if (this.text.length === 0) {
      Column().width('100%').height(0)
    } else {
      Row({ space: 8 }) {
        Text(this.text)
          .fontSize(Tokens.typeCaption)
          .fontFamily(Tokens.fontUi)
          .fontColor(this.ink())
          .lineHeight(Tokens.lineCaption)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.action.length > 0) {
          HuTextButton({
            label: this.action,
            color: this.tone === 'danger' ? $r('app.color.err') : $r('app.color.accent'),
            onTap: () => {
              this.onAction();
            }
          })
        }
      }
      .width('100%')
      .constraintSize({ minHeight: Tokens.touchMin })
      .padding({ left: Tokens.pagePad, right: Tokens.space2, top: 8, bottom: 8 })
      .backgroundColor(this.wash())
      .alignItems(VerticalAlign.Center)
      .transition(chromeTransition())
    }
  }
}
