import { promptAction } from '@kit.ArkUI';

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
