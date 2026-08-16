import { font, UIContext } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Tokens } from './Tokens';

interface FontFaceReg {
  familyName: string;
  familySrc: Resource;
}

/** Register Geist Mono for code. UI stays on HarmonyOS Sans. */
export function registerAppFonts(ui?: UIContext): void {
  const faces: FontFaceReg[] = [
    { familyName: Tokens.fontMono, familySrc: $rawfile('fonts/GeistMono-Regular.ttf') }
  ];
  for (let i = 0; i < faces.length; i++) {
    const face = faces[i];
    try {
      if (ui !== undefined) {
        ui.getFont().registerFont(face);
      } else {
        // Preview / early boot — UIContext.getFont is preferred at runtime.
        font.registerFont(face);
      }
    } catch (_e) {
    }
  }
}

export function applyAppFont(_app: common.ApplicationContext): void {
  // Do not setFont(Geist): Latin-only Geist + CJK system fallback looks wrong on Inbox.
}
