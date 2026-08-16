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

export function pressScaleOf(pressed: boolean): number {
  if (prefersReducedMotion() || !pressed) {
    return 1;
  }
  return Tokens.pressScale;
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

/** Appear/disappear for chrome bars (notice, error, queue). */
export function chromeTransition(): TransitionEffect {
  const ms = motionMs();
  if (ms <= 0) {
    return TransitionEffect.IDENTITY;
  }
  return TransitionEffect.OPACITY
    .combine(TransitionEffect.translate({ y: -6 }))
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
