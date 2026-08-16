import {
  AbilityConstant, ConfigurationConstant, UIAbility, Want, Configuration
} from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KeyboardAvoidMode, window } from '@kit.ArkUI';
import { display } from '@kit.ArkUI';
import { BreakpointStore } from '../store/BreakpointStore';
import { NetworkMonitor } from '../utils/NetworkMonitor';
import { PrefStore } from '../store/PrefStore';
import { ReadPrefStore } from '../store/ReadPrefStore';
import { ThemeStore } from '../store/ThemeStore';
import { DetailVM } from '../viewmodels/DetailVM';
import { InboxVM } from '../viewmodels/InboxVM';
import { ApiKeyStore } from '../store/ApiKeyStore';
import { Notify } from '../utils/Notify';
import { UnreadStore } from '../store/UnreadStore';

const DOMAIN = 0x435552;
const TAG = 'CursorMobile';

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | undefined = undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.consumeWant(want);
    try {
      const mode = this.context.config.colorMode as number;
      ThemeStore.getInstance().onConfiguration(mode);
    } catch (_e) {
    }
    PrefStore.getInstance().init(this.context).then(async () => {
      await ThemeStore.getInstance().loadPref();
      await ReadPrefStore.getInstance().load();
      await UnreadStore.getInstance().load();
      ThemeStore.getInstance().applyToApp(this.context.getApplicationContext());
      Notify.ensureChannel().catch(() => {
      });
    }).catch(() => {
      try {
        this.context.getApplicationContext()
          .setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      } catch (_e) {
      }
    });
    hilog.info(DOMAIN, TAG, 'Application created');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    try {
      const mode = newConfig.colorMode as number;
      ThemeStore.getInstance().onConfiguration(mode);
    } catch (_e) {
      hilog.warn(DOMAIN, TAG, 'onConfigurationUpdate theme sync failed');
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.getMainWindow((windowError, mainWindow) => {
      if (windowError.code) {
        return;
      }
      this.mainWindow = mainWindow;
      ThemeStore.getInstance().setMainWindow(mainWindow);
      try {
        mainWindow.setWindowLayoutFullScreen(true);
      } catch (_e) {
      }
      ThemeStore.getInstance().syncSystemBarsPublic();
      try {
        mainWindow.on('avoidAreaChange', () => {
          this.syncAvoidArea(mainWindow);
        });
      } catch (_e) {
        hilog.warn(DOMAIN, TAG, 'avoidAreaChange listen failed');
      }
      try {
        // RESIZE compresses the page so a bottom composer sits on the IME.
        // Do not also pad by TYPE_KEYBOARD height — that double-counts on cover.
        mainWindow.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
      } catch (_e) {
        hilog.warn(DOMAIN, TAG, 'setKeyboardAvoidMode failed');
      }

      this.syncWindowSize(mainWindow);
      try {
        mainWindow.on('windowSizeChange', (size: window.Size) => {
          this.applySize(size.width, size.height, mainWindow);
        });
      } catch (_e) {
        hilog.warn(DOMAIN, TAG, 'windowSizeChange listen failed');
      }

      this.syncFold();
      try {
        display.on('foldStatusChange', (status: display.FoldStatus) => {
          BreakpointStore.getInstance().updateFold(status as number);
          hilog.info(DOMAIN, TAG, 'foldStatus=%{public}d', status as number);
          if (this.mainWindow) {
            this.syncCrease(this.mainWindow);
            this.syncWindowSize(this.mainWindow);
          }
        });
      } catch (_e) {
        hilog.warn(DOMAIN, TAG, 'foldStatusChange listen failed');
      }
    });

    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load main page: %{public}s', JSON.stringify(error));
      }
    });
  }

  private syncWindowSize(win: window.Window): void {
    try {
      const props = win.getWindowProperties();
      this.applySize(props.windowRect.width, props.windowRect.height, win);
    } catch (_e) {
      hilog.warn(DOMAIN, TAG, 'syncWindowSize failed');
    }
  }

  private applySize(pxW: number, pxH: number, win: window.Window): void {
    let density = 3.2;
    try {
      const ui = win.getUIContext();
      const vpW = ui.px2vp(pxW);
      const vpH = ui.px2vp(pxH);
      BreakpointStore.getInstance().updateWindow(vpW, vpH);
      this.syncCrease(win);
      this.syncAvoidArea(win);
      hilog.info(DOMAIN, TAG, 'window vp=%{public}s x %{public}s bp=%{public}s',
        `${Math.round(vpW)}`, `${Math.round(vpH)}`, BreakpointStore.getInstance().bp);
      return;
    } catch (_e) {
    }
    BreakpointStore.getInstance().updateWindow(pxW / density, pxH / density);
  }

  private syncAvoidArea(win: window.Window): void {
    try {
      const ui = win.getUIContext();
      const sys = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const cut = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      const nav = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const kb = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD);
      const topPx = Math.max(sys.topRect.height, cut.topRect.height);
      const bottomPx = Math.max(sys.bottomRect.height, nav.bottomRect.height);
      // TYPE_KEYBOARD.topRect is the leftover viewport above the IME, not the
      // keyboard. max(bottom, top) pads the composer by almost the full window.
      const kbPx = kb.bottomRect.height;
      const kbVp = ui.px2vp(kbPx);
      BreakpointStore.getInstance().updateInsets(ui.px2vp(topPx), ui.px2vp(bottomPx), kbVp);
      hilog.info(DOMAIN, TAG, 'avoid kb=%{public}s topRect=%{public}s',
        `${Math.round(kbVp)}`, `${Math.round(ui.px2vp(kb.topRect.height))}`);
    } catch (_e) {
      hilog.warn(DOMAIN, TAG, 'syncAvoidArea failed');
    }
  }

  private syncFold(): void {
    try {
      if (display.isFoldable()) {
        const st = display.getFoldStatus();
        BreakpointStore.getInstance().updateFold(st as number);
        hilog.info(DOMAIN, TAG, 'isFoldable fold=%{public}d', st as number);
        if (this.mainWindow) {
          this.syncCrease(this.mainWindow);
        }
      }
    } catch (_e) {
      hilog.warn(DOMAIN, TAG, 'syncFold failed');
    }
  }

  private syncCrease(win: window.Window): void {
    try {
      if (!display.isFoldable()) {
        BreakpointStore.getInstance().updateCrease(0, 0);
        return;
      }
      const region = display.getCurrentFoldCreaseRegion();
      if (!region || !region.creaseRects || region.creaseRects.length === 0) {
        BreakpointStore.getInstance().updateCrease(0, 0);
        return;
      }
      const rect = region.creaseRects[0];
      const ui = win.getUIContext();
      BreakpointStore.getInstance().updateCrease(ui.px2vp(rect.top), ui.px2vp(rect.height));
    } catch (_e) {
      BreakpointStore.getInstance().updateCrease(0, 0);
    }
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.consumeWant(want);
  }

  private consumeWant(want: Want): void {
    try {
      const raw = want.parameters;
      if (raw && raw['agentId']) {
        AppStorage.setOrCreate('pendingAgentId', `${raw['agentId']}`);
      }
      if (raw && raw['noticeText']) {
        AppStorage.setOrCreate('pendingNotice', `${raw['noticeText']}`);
      }
    } catch (_e) {
    }
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'onForeground');
    NetworkMonitor.getInstance().start();
    if (this.mainWindow) {
      this.syncWindowSize(this.mainWindow);
      ThemeStore.getInstance().syncSystemBarsPublic();
    }
    const detail = DetailVM.getActive();
    if (detail) {
      detail.resumeIfNeeded().catch(() => {
      });
    }
    if (ApiKeyStore.getInstance().isUnlocked()) {
      InboxVM.getInstance().refresh(true).catch(() => {
      });
    }
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
    // Keep SSE alive when possible so Last-Event-ID resume is less lossy.
    // OS may still suspend the process; onForeground reconnects via resumeIfNeeded.
  }

  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    hilog.info(DOMAIN, TAG, 'onMemoryLevel %{public}d', level as number);
    const detail = DetailVM.getActive();
    if (detail) {
      detail.clearExpandedState();
    }
  }
}
