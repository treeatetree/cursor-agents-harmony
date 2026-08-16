import { common } from '@kit.AbilityKit';
import { audio } from '@kit.AudioKit';
import { media } from '@kit.MediaKit';
import { Log } from './Log';

const TAG = 'Sounds';
const DEBOUNCE_MS = 80;

export type SoundKind = 'click' | 'commit' | 'toggle' | 'success' | 'fail' | 'warn';

/**
 * Outcome ticks only: send / success / fail / warn.
 * Routine click / toggle stay haptic-only.
 */
export class Sounds {
  static enabled: boolean = true;
  private static ready: boolean = false;
  private static loading: boolean = false;
  private static pool: media.SoundPool | undefined = undefined;
  private static ids: Record<string, number> = {};
  private static lastAt: Record<string, number> = {};
  private static ctx: common.UIAbilityContext | undefined = undefined;

  static setEnabled(value: boolean): void {
    Sounds.enabled = value;
  }

  static async init(context: common.UIAbilityContext): Promise<void> {
    Sounds.ctx = context;
    if (Sounds.ready || Sounds.loading) {
      return;
    }
    Sounds.loading = true;
    try {
      const info: audio.AudioRendererInfo = {
        usage: audio.StreamUsage.STREAM_USAGE_NOTIFICATION,
        rendererFlags: 0
      };
      Sounds.pool = await media.createSoundPool(4, info);
      await Sounds.loadOne('commit', 'snd_commit.mp3');
      await Sounds.loadOne('success', 'snd_ok.mp3');
      await Sounds.loadOne('fail', 'snd_fail.mp3');
      await Sounds.loadOne('warn', 'snd_warn.mp3');
      Sounds.ready = true;
    } catch (e) {
      Log.warn(TAG, `init failed: ${JSON.stringify(e)}`);
    } finally {
      Sounds.loading = false;
    }
  }

  static play(kind: SoundKind): void {
    if (!Sounds.enabled) {
      return;
    }
    const now = Date.now();
    const prev = Sounds.lastAt[kind] ?? 0;
    if (now - prev < DEBOUNCE_MS) {
      return;
    }
    Sounds.lastAt[kind] = now;
    if (!Sounds.ready || !Sounds.pool) {
      if (Sounds.ctx && !Sounds.loading) {
        Sounds.init(Sounds.ctx).catch(() => {
        });
      }
      return;
    }
    const id = Sounds.ids[kind] ?? 0;
    if (id <= 0) {
      return;
    }
    const vol = kind === 'click' ? 0.88 : 1.0;
    Sounds.pool.play(id, {
      loop: 0,
      leftVolume: vol,
      rightVolume: vol,
      priority: 0
    }).catch(() => {
    });
  }

  private static async loadOne(kind: string, file: string): Promise<void> {
    if (!Sounds.ctx || !Sounds.pool) {
      return;
    }
    const raw = await Sounds.ctx.resourceManager.getRawFd(file);
    const id = await Sounds.pool.load(raw.fd, raw.offset, raw.length);
    if (id > 0) {
      Sounds.ids[kind] = id;
    }
  }
}
