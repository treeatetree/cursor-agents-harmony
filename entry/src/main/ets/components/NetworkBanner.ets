import { StatusBanner } from './StatusBanner';

@Component
export struct NetworkBanner {
  @Prop online: boolean = true;
  onRetry: () => void = () => {
  };

  build() {
    if (this.online) {
      Column().width('100%').height(0)
    } else {
      StatusBanner({
        text: '网络已断开 · 显示缓存内容',
        tone: 'warn',
        action: '重试',
        onAction: () => {
          this.onRetry();
        }
      })
    }
  }
}
