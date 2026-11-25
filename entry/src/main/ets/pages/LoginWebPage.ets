import { router, promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { ensureSession, clearSession, API_BASE } from '../net/ApiClient';
import { currentLang, t } from '../i18n/L10n';
import { Theme } from '../ui/Theme';

@Entry
@Component
struct LoginWebPage {
  controller: webview.WebviewController = new webview.WebviewController();
  @State progress: number = 0;
  private handled: boolean = false;

  private startUrl(): string {
    return API_BASE + '/auth/google/start?next=' + encodeURIComponent('/' + currentLang() + '/');
  }

  build() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(26)
          .fontColor(Theme.TEXT)
          .onClick(() => { router.back(); })
          .margin({ right: 12 })
        Text(t('login'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT)
      }
      .width('100%')
      .padding({ left: 12, right: 16, top: 12, bottom: 10 })

      Stack() {
        Web({ src: this.startUrl(), controller: this.controller })
          .width('100%')
          .height('100%')
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(false)
          .onPageEnd((e) => {
            const url: string = e ? e.url : '';
            // OAuth 流程结束、回到站点自身页面 -> 重新握手拿到 user
            if (!this.handled && url.indexOf('anyshort.net') >= 0
              && url.indexOf('/auth/') < 0 && url.indexOf('accounts.google') < 0) {
              this.handled = true;
              clearSession();
              ensureSession()
                .then(() => {
                  AppStorage.setOrCreate('user_version', Date.now());
                  promptAction.showToast({ message: t('login_success'), duration: 1800 });
                  router.back();
                })
                .catch((er: Error) => {
                  promptAction.showToast({ message: t('err_network'), duration: 1800 });
                  router.back();
                });
            }
          })

        if (this.progress > 0 && this.progress < 100) {
          LoadingProgress().width(36).height(36).color(Theme.ACCENT)
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }
}
