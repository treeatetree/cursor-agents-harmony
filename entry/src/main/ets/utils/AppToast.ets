import { Haptics } from './Haptics';
import { SessionDiag } from './SessionDiag';

/** In-app StatusPill toast. Hosts only render when `page` matches. */
class ToastBus {
  private static inst: ToastBus | undefined = undefined;
  private timer: number = -1;

  static getInstance(): ToastBus {
    if (!ToastBus.inst) {
      ToastBus.inst = new ToastBus();
    }
    return ToastBus.inst;
  }

  show(message: string, tone: string, page: string): void {
    if (!message) {
      return;
    }
    AppStorage.setOrCreate('toastText', message);
    AppStorage.setOrCreate('toastTone', tone);
    AppStorage.setOrCreate('toastPage', page);
    SessionDiag.emit({ tag: 'Toast', event: 'show', extra: `${page}:${tone}:${message}` });
    if (this.timer >= 0) {
      clearTimeout(this.timer);
    }
    this.timer = setTimeout(() => {
      AppStorage.setOrCreate('toastText', '');
      this.timer = -1;
    }, 2400);
  }
}

export function showToast(message: string, tone: string = 'info', page: string = ''): void {
  ToastBus.getInstance().show(message, tone, page);
}

/** User-started load finished — toast either way so the spinner is not the only signal. */
export function notifyResult(ok: boolean, okText: string, failText: string = '失败',
  page: string = ''): void {
  if (ok) {
    showToast(okText, 'info', page);
    return;
  }
  Haptics.fail();
  showToast(failText.length > 0 ? failText : '失败', 'danger', page);
}
