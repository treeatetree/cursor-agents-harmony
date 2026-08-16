import { vibrator } from '@kit.SensorServiceKit';
import { Log } from './Log';
import { Sounds } from './Sounds';

const TAG = 'Haptics';

/**
 * Touch vocabulary. Usage `touch` / `physicalFeedback` is louder than `notification`
 * on HarmonyOS; intensity 0–100 is honored on API 12+.
 */
export class Haptics {
  static enabled: boolean = true;

  static setEnabled(value: boolean): void {
    Haptics.enabled = value;
  }

  /** Chip / filter / light selection. */
  static tick(): void {
    Haptics.fire('haptic.effect.sharp', 72, 'touch');
  }

  /** Toolbar icon, secondary control. Sound stays off — too frequent. */
  static click(): void {
    Haptics.fire('haptic.effect.hard', 86, 'touch');
  }

  /** Open a card or push a page. */
  static soft(): void {
    Haptics.fire('haptic.effect.soft', 92, 'physicalFeedback');
  }

  /** Send / create / confirm a primary action. */
  static commit(): void {
    Sounds.play('commit');
    Haptics.fire('haptic.effect.hard', 100, 'physicalFeedback');
  }

  /** Long-press menus. */
  static press(): void {
    Haptics.fire('haptic.gestures.long_press', 100, 'physicalFeedback');
  }

  /** Switch / theme / mode change. */
  static toggle(): void {
    Haptics.fire('haptic.effect.sharp', 88, 'physicalFeedback');
  }

  static success(): void {
    Sounds.play('success');
    Haptics.fire('haptic.notice.success', 100, 'notification');
  }

  static fail(): void {
    Sounds.play('fail');
    Haptics.fire('haptic.notice.fail', 100, 'notification');
  }

  static warn(): void {
    Sounds.play('warn');
    Haptics.fire('haptic.notice.warning', 94, 'notification');
  }

  private static fire(effectId: string, intensity: number, usage: vibrator.Usage): void {
    if (!Haptics.enabled) {
      return;
    }
    try {
      vibrator.startVibration({
        type: 'preset',
        effectId: effectId,
        count: 1,
        intensity: intensity
      }, {
        usage: usage
      }).catch(() => {
        Haptics.fallback(usage);
      });
    } catch (_e) {
      Log.warn(TAG, 'vibrate unavailable');
    }
  }

  private static fallback(usage: vibrator.Usage): void {
    try {
      vibrator.startVibration({
        type: 'time',
        duration: 18
      }, {
        usage: usage
      }).catch(() => {
      });
    } catch (_e) {
    }
  }
}
