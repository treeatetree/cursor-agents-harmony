import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';

const DOMAIN: number = 0x435552;
const TAG: string = 'CursorMobile';
const CURSOR_URL: string = 'https://cursor.com/agents?source=harmony';

/**
 * PARKED (2026-07-12): Cloudflare Turnstile blocks HarmonyOS ArkWeb.
 * Daily path: install `android-shell` APK into 卓易通 — see PARKED.txt / DELIVERY.txt.
 * This Harmony shell is kept as a launcher fallback only; do not treat ArkWeb as the CF path.
 */
@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController('cursor-main');
  @State useWebView: boolean = false;
  @State loadingProgress: number = 0;
  @State statusHint: string = '';

  aboutToAppear(): void {
    // Stay on launcher home; user taps to open. Avoid surprising auto-jump.
  }

  private getAbilityContext(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private openSystemBrowser(): void {
    const context: common.UIAbilityContext = this.getAbilityContext();
    this.statusHint = '正在打开系统浏览器…';
    context.openLink(CURSOR_URL).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'openLink failed: %{public}s', JSON.stringify(err));
      const want: Want = {
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: CURSOR_URL
      };
      context.startAbility(want).catch((startErr: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'startAbility failed: %{public}s', JSON.stringify(startErr));
        this.statusHint = '无法打开浏览器，请检查是否安装浏览器应用';
      });
    });
  }

  private openInAppWebView(): void {
    this.useWebView = true;
    this.statusHint = '';
    this.loadingProgress = 1;
    setTimeout(() => {
      try {
        this.controller.loadUrl(CURSOR_URL);
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'loadUrl failed: %{public}s', JSON.stringify(e));
      }
    }, 50);
  }

  onBackPress(): boolean {
    if (this.useWebView && this.controller.accessBackward()) {
      this.controller.backward();
      return true;
    }
    if (this.useWebView) {
      this.useWebView = false;
      return true;
    }
    return false;
  }

  build() {
    Column() {
      if (this.useWebView) {
        Stack({ alignContent: Alignment.Top }) {
          Web({ src: CURSOR_URL, controller: this.controller })
            .width('100%')
            .height('100%')
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .databaseAccess(true)
            .mixedMode(MixedMode.None)
            .cacheMode(CacheMode.Default)
            .metaViewport(true)
            .zoomAccess(false)
            .darkMode(WebDarkMode.Off)
            .forceDarkAccess(false)
            .backgroundColor($r('app.color.page_background'))
            .onProgressChange((event) => {
              if (event) {
                this.loadingProgress = event.newProgress;
              }
            })
            .onPageEnd(() => {
              this.loadingProgress = 100;
            })

          if (this.loadingProgress > 0 && this.loadingProgress < 100) {
            Progress({ value: this.loadingProgress, total: 100, type: ProgressType.Linear })
              .width('100%')
              .height(2)
              .color($r('app.color.accent'))
              .backgroundColor('#333333')
          }
        }
        .layoutWeight(1)
        .width('100%')

        Row({ space: 8 }) {
          Button('返回启动页')
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor('#333333')
            .onClick(() => {
              this.useWebView = false;
            })
          Button('系统浏览器')
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .fontColor('#141414')
            .backgroundColor($r('app.color.accent'))
            .onClick(() => {
              this.openSystemBrowser();
            })
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#1A1A1A')
      } else {
        Column({ space: 16 }) {
          Blank().height(48)
          Image($r('app.media.app_icon'))
            .width(88)
            .height(88)
          Text('Cursor Mobile')
            .fontSize(28)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('Cloudflare 会拦截鸿蒙应用内网页容器（WebView）。\n人机验证只能在系统浏览器里完成，且登录态无法带回路内页。')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .padding({ left: 28, right: 28 })
            .lineHeight(22)
          Text(this.statusHint)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .height(20)

          Button('打开 Cursor（系统浏览器）')
            .width('80%')
            .height(48)
            .fontSize(16)
            .fontColor('#141414')
            .backgroundColor($r('app.color.accent'))
            .onClick(() => {
              this.openSystemBrowser();
            })

          Button('尝试应用内打开（可能被拦截）')
            .width('80%')
            .height(44)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor('#333333')
            .onClick(() => {
              this.openInAppWebView();
            })

          Text('推荐：桌面点本图标 → 自动进浏览器使用 Cursor。\n这是目前在鸿蒙上个人可用、且不绕过安全检查的路径。')
            .fontSize(12)
            .fontColor('#777777')
            .textAlign(TextAlign.Center)
            .padding({ left: 32, right: 32, top: 8 })
            .lineHeight(18)

          Blank().layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
