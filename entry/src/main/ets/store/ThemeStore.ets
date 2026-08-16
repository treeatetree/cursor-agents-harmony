import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { PrefStore } from './PrefStore';
import { Log } from '../utils/Log';

const TAG = 'ThemeStore';

/** system | dark | light */
export type ThemePref = 'system' | 'dark' | 'light';

/**
 * Theme preference + system bar sync.
 * Actual paint colors come from resources/base vs resources/dark via $r().
 */
export class ThemeStore {
  private static instance: ThemeStore | undefined = undefined;
  pref: ThemePref = 'system';
  /** Effective dark? */
  isDark: boolean = true;
  rev: number = 0;
  private mainWindow: window.Window | undefined = undefined;

  static getInstance(): ThemeStore {
    if (!ThemeStore.instance) {
      ThemeStore.instance = new ThemeStore();
    }
    return ThemeStore.instance;
  }

  setMainWindow(win: window.Window): void {
    this.mainWindow = win;
    this.syncSystemBars();
  }

  setKeepScreenOn(on: boolean): void {
    if (!this.mainWindow) {
      return;
    }
    try {
      this.mainWindow.setWindowKeepScreenOn(on).then(() => {
      }).catch(() => {
      });
    } catch (_e) {
    }
  }

  async loadPref(): Promise<void> {
    const raw = await PrefStore.getInstance().getThemePref();
    if (raw === 'dark' || raw === 'light' || raw === 'system') {
      this.pref = raw;
    }
  }

  async setPref(pref: ThemePref, appContext: common.ApplicationContext): Promise<void> {
    this.pref = pref;
    await PrefStore.getInstance().setThemePref(pref);
    this.applyToApp(appContext);
    this.bump();
  }

  applyToApp(appContext: common.ApplicationContext): void {
    try {
      if (this.pref === 'dark') {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
        this.isDark = true;
      } else if (this.pref === 'light') {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
        this.isDark = false;
      } else {
        // Follow system — COLOR_MODE_NOT_SET may be unavailable on some API levels.
        try {
          appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
        } catch (_e) {
          // fallback: leave system-managed
        }
        // isDark refined later via onConfigurationUpdate / syncSystemBarsPublic
      }
    } catch (e) {
      Log.warn(TAG, `setColorMode failed: ${JSON.stringify(e)}`);
    }
    this.syncSystemBars();
  }

  /** Call from onConfigurationUpdate when system theme changes. */
  onConfiguration(colorMode: number): void {
    if (this.pref === 'system') {
      // COLOR_MODE_DARK typically 0, LIGHT 1 — treat non-light as dark-ish for bars
      this.isDark = colorMode !== ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    } else {
      this.isDark = this.pref === 'dark';
    }
    this.syncSystemBars();
    this.bump();
    Log.info(TAG, `config colorMode=${colorMode} isDark=${this.isDark} pref=${this.pref}`);
  }

  syncSystemBarsPublic(): void {
    this.syncSystemBars();
  }

  private syncSystemBars(): void {
    if (!this.mainWindow) {
      return;
    }
    try {
      const dark = this.isDark;
      // Transparent bars so page chrome paints edge-to-edge (immersive).
      this.mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: dark ? '#F5F5F5' : '#18181B',
        navigationBarContentColor: dark ? '#F5F5F5' : '#18181B'
      });
    } catch (_e) {
      // ignore
    }
  }

  private bump(): void {
    this.rev += 1;
    AppStorage.setOrCreate('themeRev', this.rev);
    AppStorage.setOrCreate('themeIsDark', this.isDark);
  }
}
