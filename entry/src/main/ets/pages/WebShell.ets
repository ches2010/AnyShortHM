import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'AnyShortWebShell';

// Tauri HAP WebView shell: loads the Vite bundle injected into rawfile by build-ohos.sh.
// Frontend uses src/http.ts runtime adapter: native fetch in ArkWeb, plugin-http on Tauri desktop.
@Entry
@Component
struct WebShell {
  controller: webview.WebviewController = new webview.WebviewController();

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
    }
    .width('100%')
    .height('100%')
  }
}
