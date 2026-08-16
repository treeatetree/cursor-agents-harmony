import { Tokens } from '../theme/Tokens';
import { HuTextButton } from './HuTextButton';

@Component
export struct NetworkBanner {
  @Prop online: boolean = true;
  onRetry: () => void = () => {
  };

  build() {
    if (!this.online) {
      Row() {
        Text('网络已断开 · 显示缓存内容')
          .fontSize(Tokens.typeCaption)
          .fontColor($r('app.color.warn'))
          .layoutWeight(1)
        HuTextButton({
          label: '重试',
          color: $r('app.color.accent'),
          onTap: () => {
            this.onRetry();
          }
        })
      }
      .width('100%')
      .padding({ left: Tokens.pagePad, right: Tokens.space2 })
      .backgroundColor($r('app.color.banner_offline_bg'))
    }
  }
}
