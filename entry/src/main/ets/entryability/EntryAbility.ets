import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { initAppStore } from '../store/AppStore';
import { loadLang } from '../i18n/L10n';

const TAG: string = 'AnyShortHM';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    initAppStore(this.context);
    loadLang();
    hilog.info(0x0000, TAG, 'Ability onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(0x0000, TAG, 'loadContent succeeded');
    });
    windowStage.getMainWindow().then((win: window.Window) => {
      win.setWindowBackgroundColor('#0E0B16');
    }).catch((e: Error) => {
      hilog.warn(0x0000, TAG, 'set bg failed: %{public}s', e.message);
    });
  }
}
