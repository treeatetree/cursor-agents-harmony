import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x435552;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } catch (_e) {
      hilog.warn(DOMAIN, 'CursorMobile', 'setColorMode failed');
    }
    hilog.info(DOMAIN, 'CursorMobile', 'Application created');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.getMainWindow((windowError, mainWindow) => {
      if (!windowError.code) {
        mainWindow.setWindowSystemBarProperties({
          statusBarColor: '#141414',
          navigationBarColor: '#141414',
          statusBarContentColor: '#FFFFFF',
          navigationBarContentColor: '#FFFFFF'
        });
        // Keep system bars visible for safe-area insets; content is full-bleed dark.
        try {
          mainWindow.setWindowLayoutFullScreen(true);
        } catch (_e) {
          // older API — ignore
        }
      }
    });

    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) {
        hilog.error(DOMAIN, 'CursorMobile', 'Failed to load main page: %{public}s', JSON.stringify(error));
      }
    });
  }
}
