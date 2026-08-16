import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { Tokens } from '../theme/Tokens';
import { BreakpointStore } from '../store/BreakpointStore';
import { HuIconButton } from '../components/HuIconButton';

/**
 * Prefer in-app WebView for Cursor product/docs surfaces.
 * Login / Cloudflare challenges can still fall back to system browser.
 */
export function shouldUseInAppBrowser(url: string): boolean {
  const u = url.toLowerCase();
  if (u.indexOf('cursor.com') < 0 && u.indexOf('cursor.so') < 0) {
    return false;
  }
  // Auth callbacks that must leave the app — keep external.
  if (u.indexOf('accounts.google.com') >= 0 || u.indexOf('github.com/login') >= 0) {
    return false;
  }
  return true;
}

@Builder
export function InAppBrowserPageBuilder() {
  InAppBrowserPage()
}

@Component
struct InAppBrowserPage {
  @Consume('navPathStack') navStack: NavPathStack;
  private controller: webview.WebviewController = new webview.WebviewController();
  @State pageUrl: string = '';
  @State pageTitle: string = 'Web';
  @State loading: boolean = true;
  @State topInset: number = 0;
  @State errorHint: string = '';
  @State challengeHint: boolean = false;

  private openExternal(): void {
    if (!this.pageUrl) {
      return;
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    ctx.openLink(this.pageUrl).catch(() => {
    });
  }

  private reload(): void {
    try {
      this.controller.refresh();
    } catch (_e) {
      // Fall back to remounting src via state bump.
      const u = this.pageUrl;
      this.pageUrl = '';
      setTimeout(() => {
        this.pageUrl = u;
      }, 16);
    }
  }

  private maybeMarkChallenge(title: string, url: string): void {
    const t = `${title} ${url}`.toLowerCase();
    if (t.indexOf('just a moment') >= 0 || t.indexOf('cloudflare') >= 0 ||
      t.indexOf('attention required') >= 0 || t.indexOf('cf-chl') >= 0 ||
      t.indexOf('turnstile') >= 0) {
      this.challengeHint = true;
      this.errorHint = '页面需要人机验证或登录。可点「系统浏览器打开」完成，再返回 App。';
    }
  }

  build() {
    NavDestination() {
      Column() {
        Row({ space: 4 }) {
          HuIconButton({
            name: 'back',
            label: '关闭',
            onTap: () => {
              this.navStack.pop();
            }
          })
          Text(this.pageTitle)
            .fontSize(Tokens.typeHeadline)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .height(Tokens.touchMin)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          HuIconButton({
            name: 'refresh',
            label: '刷新',
            iconColor: $r('app.color.text_secondary'),
            onTap: () => {
              this.reload();
            }
          })
          HuIconButton({
            name: 'external',
            label: '系统浏览器打开',
            iconColor: $r('app.color.accent'),
            onTap: () => {
              this.openExternal();
            }
          })
        }
        .width('100%')
        .padding({
          left: 4,
          right: 4,
          top: this.topInset,
          bottom: 6
        })
        .alignItems(VerticalAlign.Center)
        .border({ width: { bottom: 1 }, color: $r('app.color.border') })
        .zIndex(2)
        .backgroundColor($r('app.color.bg0'))

        if (this.loading) {
          Progress({ value: 0, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(2)
            .color($r('app.color.accent'))
            .style({ strokeWidth: 2, enableSmoothEffect: true })
        }

        if (this.errorHint.length > 0) {
          Text(this.errorHint)
            .width('100%')
            .fontSize(Tokens.typeCaption)
            .fontColor($r('app.color.warn'))
            .padding(12)
            .backgroundColor($r('app.color.banner_offline_bg'))
            .onClick(() => {
              this.openExternal();
            })
        }

        if (this.pageUrl.length > 0) {
          Web({ src: this.pageUrl, controller: this.controller })
            .layoutWeight(1)
            .width('100%')
            .constraintSize({ minHeight: 120 })
            .zIndex(0)
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .fileAccess(true)
            .imageAccess(true)
            .onlineImageAccess(true)
            .mixedMode(MixedMode.All)
            .onPageBegin((event) => {
              this.loading = true;
              if (event && event.url) {
                this.maybeMarkChallenge('', event.url);
              }
            })
            .onPageEnd((event) => {
              this.loading = false;
              if (event && event.url) {
                this.maybeMarkChallenge('', event.url);
              }
            })
            .onTitleReceive((event) => {
              if (event && event.title && event.title.length > 0 && event.title.length < 40) {
                // Keep caller title for product pages; only adopt short page titles.
                if (this.pageTitle === 'Web' || this.pageTitle === '浏览') {
                  this.pageTitle = event.title;
                }
                this.maybeMarkChallenge(event.title, this.pageUrl);
              }
            })
            .onErrorReceive((_event) => {
              this.loading = false;
              this.errorHint = '加载失败。点此用系统浏览器打开，或点右上角「刷新」重试。';
            })
            .onHttpErrorReceive((_event) => {
              this.loading = false;
              this.errorHint = '页面返回错误。若需登录或验证，请用「外开」。';
            })
        } else {
          Column() {
            Text('无有效链接')
              .fontSize(Tokens.typeBody)
              .fontColor($r('app.color.text_tertiary'))
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('100%')
      .height('100%')
      .clip(true)
      .backgroundColor($r('app.color.bg0'))
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg0'))
    .onBackPressed(() => {
      try {
        if (this.controller.accessBackward()) {
          this.controller.backward();
          return true;
        }
      } catch (_e) {
      }
      return false;
    })
    .onReady((ctx: NavDestinationContext) => {
      this.topInset = BreakpointStore.getInstance().safeTop();
      BreakpointStore.getInstance().onChange(() => {
        this.topInset = BreakpointStore.getInstance().safeTop();
      });
      const p = ctx.pathInfo.param as Record<string, Object>;
      if (p) {
        this.pageUrl = p['url'] ? `${p['url']}` : '';
        this.pageTitle = p['title'] ? `${p['title']}` : 'Web';
      }
    })
  }
}
