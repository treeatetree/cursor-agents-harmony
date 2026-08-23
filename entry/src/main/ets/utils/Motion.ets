/**
 * Two speeds only: press 130ms EaseOut, layout 280ms FastOutSlowIn.
 * No spring, no stagger. prefers-reduced-motion → 0 / IDENTITY.
 */
import { mediaquery } from '@kit.ArkUI';
import { Tokens } from '../theme/Tokens';

export function prefersReducedMotion(): boolean {
  try {
    const m = mediaquery.matchMediaSync('(prefers-reduced-motion: reduce)');
    return m.matches === true;
  } catch (_e) {
    return false;
  }
}

export function motionMs(): number {
  return prefersReducedMotion() ? 0 : Tokens.motionMs;
}

/** Finger-down feedback — shorter than layout motion. */
export function pressMs(): number {
  return prefersReducedMotion() ? 0 : 130;
}

export function pressScaleOf(pressed: boolean, strong: boolean = false): number {
  if (prefersReducedMotion() || !pressed) {
    return 1;
  }
  return strong ? Tokens.pressScaleStrong : Tokens.pressScale;
}

export function shakeSeq(): number[] {
  return [0, -8, 8, -5, 5, -2, 0];
}

export function shimmerOpacity(on: boolean): number {
  if (prefersReducedMotion()) {
    return 1;
  }
  return on ? 1 : 0.38;
}

export function shimmerMs(): number {
  return prefersReducedMotion() ? 0 : 1200;
}

export function motionEase(): Curve {
  return Curve.FastOutSlowIn;
}

/** Appear/disappear for chrome bars (notice, error, queue). */
export function chromeTransition(): TransitionEffect {
  const ms = motionMs();
  if (ms <= 0) {
    return TransitionEffect.IDENTITY;
  }
  return TransitionEffect.OPACITY
    .combine(TransitionEffect.translate({ y: -14 }))
    .animation({ duration: ms, curve: Curve.EaseOut });
}

/** Expand/collapse body — opacity only, no slide. */
export function fadeTransition(): TransitionEffect {
  const ms = motionMs();
  if (ms <= 0) {
    return TransitionEffect.IDENTITY;
  }
  return TransitionEffect.OPACITY.animation({ duration: ms, curve: Curve.EaseOut });
}

/** Inbox group cards appearing under a section. */
export function expandTransition(): TransitionEffect {
  const ms = motionMs();
  if (ms <= 0) {
    return TransitionEffect.IDENTITY;
  }
  return TransitionEffect.OPACITY
    .combine(TransitionEffect.translate({ y: 14 }))
    .animation({ duration: ms, curve: Curve.FastOutSlowIn });
}

export function runLayout(update: () => void): void {
  const ms = motionMs();
  if (ms <= 0) {
    update();
    return;
  }
  animateTo({ duration: ms, curve: Curve.FastOutSlowIn }, update);
}
