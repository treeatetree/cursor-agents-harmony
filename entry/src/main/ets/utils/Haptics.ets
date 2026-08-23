import { vibrator } from '@kit.SensorServiceKit';
import { Log } from './Log';
import { Sounds } from './Sounds';
import { SessionDiag } from './SessionDiag';

const TAG = 'Haptics';

/**
 * Touch vocabulary. Usage `touch` / `physicalFeedback` is louder than `notification`
 * on HarmonyOS; intensity 0–100 is honored on API 12+.
 */
const NOTICE_GAP_MS = 8000;

export class Haptics {
  static enabled: boolean = true;
  private static lastNoticeAt: number = 0;

  static setEnabled(value: boolean): void {
    Haptics.enabled = value;
  }

  /** Finger-down, synced with press scale. */
  static down(): void {
    Haptics.fire('haptic.effect.hard', 88, 'physicalFeedback');
  }

  /** Chip / filter / light selection. */
  static tick(): void {
    Haptics.fire('haptic.effect.soft', 52, 'physicalFeedback');
  }

  /** Toolbar icon, secondary control. Sound stays off — too frequent. */
  static click(): void {
    Haptics.fire('haptic.effect.soft', 72, 'physicalFeedback');
  }

  /** Open a card or push a page. */
  static soft(): void {
    Haptics.fire('haptic.effect.soft', 100, 'physicalFeedback');
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
    Haptics.fire('haptic.effect.sharp', 96, 'physicalFeedback');
  }

  static success(): void {
    Sounds.play('success');
    SessionDiag.emit({ tag: 'Haptic', event: 'success', extra: 'fire' });
    Haptics.fire('haptic.notice.success', 100, 'notification');
  }

  static fail(): void {
    Haptics.notice('fail');
  }

  static warn(): void {
    Haptics.notice('warn');
  }

  private static notice(kind: string): void {
    if (!Haptics.enabled) {
      SessionDiag.emit({ tag: 'Haptic', event: kind, extra: 'disabled' });
      return;
    }
    if (!Haptics.noticeReady()) {
      SessionDiag.emit({ tag: 'Haptic', event: kind, extra: 'skip_gap' });
      return;
    }
    SessionDiag.emit({ tag: 'Haptic', event: kind, extra: 'fire' });
    Sounds.play(kind === 'fail' ? 'fail' : 'warn');
    if (kind === 'fail') {
      Haptics.fire('haptic.notice.fail', 100, 'notification');
    } else {
      Haptics.fire('haptic.notice.warning', 94, 'notification');
    }
  }

  private static noticeReady(): boolean {
    const now = Date.now();
    if (now - Haptics.lastNoticeAt < NOTICE_GAP_MS) {
      return false;
    }
    Haptics.lastNoticeAt = now;
    return true;
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
        duration: 28
      }, {
        usage: usage
      }).catch(() => {
      });
    } catch (_e) {
    }
  }
}
