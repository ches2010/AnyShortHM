import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'AnyShortWebShell';

// Tauri HAP WebView shell: loads the Vite bundle injected into rawfile by build-ohos.sh.
// The frontend uses src/http.ts runtime adapter: native fetch in plain ArkWeb, tauri-plugin-http on desktop.
@Entry
@Component
struct WebShell {
  controller: webview.WebviewController = new webview.WebviewController();
  @State failed: boolean = false;

  build() {
    Stack() {
      Web({ src: $rawfile('index.html'), controller: this.controller })
        .width('100%')
        .height('100%')
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .onPageBegin(() => { hilog.info(0x0000, TAG, 'frontend load begin'); })
        .onPageEnd(() => { hilog.info(0x0000, TAG, 'frontend loaded'); })
        .onPageError((e) => {
          hilog.error(0x0000, TAG, 'web error: %{public}s', JSON.stringify(e));
          this.failed = true;
        })

      if (this.failed) {
        Column() {
          Text('Failed to load bundled frontend')
            .fontSize(16)
            .fontColor('#E0D8F0')
          Text('Check rawfile/index.html')
            .fontSize(12)
            .fontColor('#9B8FB0')
            .margin({ top: 8 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#0E0B16')
      }
    }
    .width('100%')
    .height('100%')
  }
}
