import { Tokens } from '../theme/Tokens';

/**
 * Pura X Max oriented breakpoints (window vp, not deviceType).
 *
 * Folded cover: ~459×672 (portrait sm) / ~672×459 (landscape md)
 * Unfolded inner: ~664×939 (portrait md) / ~939×664 (landscape lg)
 */
export type Breakpoint = 'sm' | 'md' | 'lg';
export type FoldUi = 'folded' | 'expanded' | 'half' | 'unknown';
export type OrientUi = 'portrait' | 'landscape';

export class BreakpointStore {
  private static instance: BreakpointStore | undefined = undefined;

  widthVp: number = 360;
  heightVp: number = 780;
  bp: Breakpoint = 'sm';
  fold: FoldUi = 'unknown';
  orient: OrientUi = 'portrait';
  /** Inbox | Detail side-by-side when true */
  useSplit: boolean = false;
  /** Comfortable content column width for landscape */
  contentMaxVp: number = 720;
  /** System status-bar / cutout inset (vp) when fullscreen. */
  topInsetVp: number = 0;
  /** Gesture / nav bar inset (vp). */
  bottomInsetVp: number = 0;
  /** Soft keyboard inset (vp). 0 when hidden. */
  keyboardInsetVp: number = 0;
  /** Fold crease top edge in window vp. */
  creaseTopVp: number = 0;
  /** Fold crease height in window vp. */
  creaseHVp: number = 0;
  /** Inner half-fold landscape: timeline above crease, composer below. */
  isHover: boolean = false;

  private listeners: Array<() => void> = [];

  static getInstance(): BreakpointStore {
    if (!BreakpointStore.instance) {
      BreakpointStore.instance = new BreakpointStore();
    }
    return BreakpointStore.instance;
  }

  onChange(cb: () => void): () => void {
    this.listeners.push(cb);
    return () => {
      const next: Array<() => void> = [];
      for (let i = 0; i < this.listeners.length; i++) {
        if (this.listeners[i] !== cb) {
          next.push(this.listeners[i]);
        }
      }
      this.listeners = next;
    };
  }

  updateWindow(widthVp: number, heightVp: number): void {
    this.widthVp = widthVp;
    this.heightVp = heightVp;
    this.orient = widthVp >= heightVp ? 'landscape' : 'portrait';
    if (widthVp < 600) {
      this.bp = 'sm';
    } else if (widthVp < 840) {
      this.bp = 'md';
    } else {
      this.bp = 'lg';
    }
    // Only inner landscape (~939vp) is wide enough for a usable master pane.
    // Inner portrait and cover landscape stay stack so status chips are not clipped.
    this.useSplit = this.bp === 'lg' && this.orient === 'landscape';
    this.contentMaxVp = this.bp === 'lg' ? 960 : (this.bp === 'md' ? 720 : widthVp);
    this.refreshHover();
    this.emit();
  }

  updateInsets(topVp: number, bottomVp: number, keyboardVp: number = -1): void {
    const t = topVp > 0 ? topVp : 0;
    const b = bottomVp > 0 ? bottomVp : 0;
    const k = keyboardVp < 0 ? this.keyboardInsetVp : (keyboardVp > 0 ? keyboardVp : 0);
    if (Math.abs(t - this.topInsetVp) < 0.5 && Math.abs(b - this.bottomInsetVp) < 0.5 &&
      Math.abs(k - this.keyboardInsetVp) < 1) {
      return;
    }
    this.topInsetVp = t;
    this.bottomInsetVp = b;
    this.keyboardInsetVp = k;
    this.emit();
  }

  updateFold(status: number): void {
    // display.FoldStatus: FOLD_STATUS_EXPANDED=1, FOLDED=2, HALF_FOLDED=3 (values may vary by SDK)
    if (status === 1) {
      this.fold = 'expanded';
    } else if (status === 2) {
      this.fold = 'folded';
    } else if (status === 3) {
      this.fold = 'half';
    } else {
      this.fold = 'unknown';
    }
    this.refreshHover();
    this.emit();
  }

  updateCrease(topVp: number, heightVp: number): void {
    const t = topVp > 0 ? topVp : 0;
    const h = heightVp > 0 ? heightVp : 0;
    if (Math.abs(t - this.creaseTopVp) < 0.5 && Math.abs(h - this.creaseHVp) < 0.5) {
      return;
    }
    this.creaseTopVp = t;
    this.creaseHVp = h;
    this.refreshHover();
    this.emit();
  }

  private refreshHover(): void {
    this.isHover = this.fold === 'half' && this.orient === 'landscape' && this.creaseHVp > 8;
  }

  private emit(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i]();
    }
  }

  /** Split master is a slim pane; cover still uses two-up cards. */
  narrowPane(): boolean {
    return this.useSplit;
  }

  pagePad(): number {
    return Tokens.pagePad;
  }

  titleSize(): number {
    return this.bp === 'sm' ? 26 : 30;
  }

  /** Top padding for fullscreen chrome; never less than status-bar fallback. */
  safeTop(): number {
    return Math.max(this.topInsetVp, 52);
  }

  /** Gesture / nav bar; keep chrome above the home indicator. */
  safeBottom(): number {
    return Math.max(this.bottomInsetVp, 28);
  }

  /** New-task sheet: RESIZE already shrinks the page; only lift off the home indicator. */
  composerBottom(): number {
    if (this.keyboardInsetVp > 16) {
      return 8;
    }
    return this.safeBottom();
  }

  /** Follow-up: we avoid the IME ourselves (NONE), so pad by keyboard height. */
  followComposerBottom(): number {
    if (this.keyboardInsetVp > 16) {
      return this.keyboardInsetVp + 8;
    }
    return this.safeBottom();
  }
}
