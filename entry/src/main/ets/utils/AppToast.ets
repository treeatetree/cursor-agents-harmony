import { promptAction } from '@kit.ArkUI';
import { Haptics } from './Haptics';

export function showToast(message: string): void {
  if (!message) {
    return;
  }
  try {
    promptAction.showToast({
      message: message,
      duration: 2000
    });
  } catch (_e) {
  }
}

/** User-started load finished — toast either way so the spinner is not the only signal. */
export function notifyResult(ok: boolean, okText: string, failText: string = '失败'): void {
  if (ok) {
    showToast(okText);
    return;
  }
  Haptics.fail();
  showToast(failText.length > 0 ? failText : '失败');
}
