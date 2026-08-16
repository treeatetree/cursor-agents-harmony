import { Tokens } from '../theme/Tokens';
import { HuButton } from './HuButton';

@Component
export struct EmptyState {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop actionLabel: string = '';
  onAction: () => void = () => {
  };

  build() {
    Column({ space: Tokens.space2 }) {
      Text(this.title)
        .fontSize(Tokens.typeHeadline)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(Tokens.typeCallout)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .lineHeight(Tokens.lineCaption + 2)
          .padding({ left: 28, right: 28 })
      }
      if (this.actionLabel.length > 0) {
        HuButton({
          label: this.actionLabel,
          variant: 'primary',
          onTap: () => {
            this.onAction();
          }
        })
          .margin({ top: 10 })
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 48, bottom: 48 })
  }
}
