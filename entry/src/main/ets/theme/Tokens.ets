/**
 * beUI — zinc surfaces, ink accent. Colors: $r('app.color.*').
 *
 * Hairline surfaces, no drop shadows.
 * Radii: card 16, chip/button 12, field 10.
 * Accent (ink) is spare: send, plus, running border.
 */
export class Tokens {
  static readonly space1: number = 4;
  static readonly space2: number = 8;
  static readonly space3: number = 12;
  static readonly space4: number = 16;
  static readonly space5: number = 20;
  static readonly space6: number = 24;
  static readonly space8: number = 32;

  static pagePad: number = 16;
  static chromePad: number = 12;
  static cardPad: number = 12;
  static sec: number = 12;
  /** Unified inbox card height (title 2 + outcome 1 + footer). */
  static cardH: number = 116;
  /** Split master list row. */
  static listCardH: number = 68;
  /** Inner landscape inbox — leave the rest for the timeline. */
  static readonly splitMasterVp: number = 280;
  static readonly splitRailVp: number = 56;

  static readonly radiusSm: number = 8;
  static readonly radiusMd: number = 12;
  static readonly radiusCtl: number = 12;
  static readonly radiusField: number = 10;
  static readonly radiusChip: number = 12;
  static readonly radiusCard: number = 16;
  static readonly radiusSheet: number = 16;
  static readonly radiusPill: number = 999;

  static readonly touchMin: number = 44;
  static readonly rowMin: number = 52;
  static readonly controlH: number = 44;
  static readonly controlHLg: number = 44;
  static readonly iconMd: number = 22;
  static readonly pressScale: number = 0.96;
  static readonly motionMs: number = 220;

  /** UI stays on HarmonyOS Sans. Geist Latin + CJK mix looked wrong. */
  static readonly fontUi: string = 'HarmonyOS Sans';
  static readonly fontUiMedium: string = 'HarmonyOS Sans';
  /** Cloud Agents web: Geist Mono on code/pre. */
  static readonly fontMono: string = 'GeistMono';

  static typeDisplay: number = 28;
  static typeTitle: number = 22;
  static typeHeadline: number = 17;
  static typeProse: number = 16;
  static typeBody: number = 15;
  static typeCallout: number = 14;
  static typeCaption: number = 13;
  static typeMicro: number = 12;

  static lineTitle: number = 28;
  static lineBody: number = 20;
  static lineCaption: number = 18;
  static lineMicro: number = 16;
  /** Cloud / Notion prose ~1.6–1.7, not a tight 1.5. */
  static lineProse: number = 26;
  static lineList: number = 24;
  /** Group headers only — light tracking, never negative on CJK. */
  static readonly letterGroup: number = 0.3;

  static readonly safeTopFallback: number = 48;
  static readonly shadowRadius: number = 0;
  static readonly shadowY: number = 0;

  static applyReadPref(type: string, density: string): void {
    let k = 1.0;
    if (type === 'small') {
      k = 0.88;
    } else if (type === 'large') {
      k = 1.12;
    }
    Tokens.typeDisplay = Math.round(28 * k);
    Tokens.typeTitle = Math.round(22 * k);
    Tokens.typeHeadline = Math.round(17 * k);
    Tokens.typeProse = Math.round(16 * k);
    Tokens.typeBody = Math.round(15 * k);
    Tokens.typeCallout = Math.round(14 * k);
    Tokens.typeCaption = Math.round(13 * k);
    Tokens.typeMicro = type === 'large' ? 13 : (type === 'small' ? 11 : 12);
    Tokens.lineTitle = type === 'large' ? 30 : (type === 'small' ? 26 : 28);
    Tokens.lineBody = type === 'large' ? 22 : (type === 'small' ? 18 : 20);
    Tokens.lineProse = type === 'large' ? 28 : (type === 'small' ? 24 : 26);
    Tokens.lineCaption = type === 'large' ? 20 : (type === 'small' ? 16 : 18);
    Tokens.lineMicro = type === 'large' ? 18 : (type === 'small' ? 14 : 16);
    Tokens.lineList = type === 'large' ? 26 : (type === 'small' ? 22 : 24);
    if (density === 'compact') {
      Tokens.pagePad = 12;
      Tokens.cardPad = 10;
      Tokens.sec = 8;
      Tokens.chromePad = 10;
      Tokens.cardH = type === 'large' ? 116 : 108;
      Tokens.listCardH = type === 'large' ? 68 : 64;
    } else {
      Tokens.pagePad = 16;
      Tokens.cardPad = 12;
      Tokens.sec = 12;
      Tokens.chromePad = 12;
      // Keep the locked 116 card for default / small so the dual grid stays even.
      Tokens.cardH = type === 'large' ? 124 : 116;
      Tokens.listCardH = type === 'large' ? 72 : 68;
    }
  }
}
