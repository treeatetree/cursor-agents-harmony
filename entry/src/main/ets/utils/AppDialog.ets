import { Haptics } from './Haptics';

export function confirmDanger(title: string, message: string, okLabel: string, onOk: () => void): void {
  AlertDialog.show({
    title: title,
    message: message,
    autoCancel: true,
    alignment: DialogAlignment.Center,
    primaryButton: {
      value: '取消',
      action: () => {
      }
    },
    secondaryButton: {
      value: okLabel,
      fontColor: $r('app.color.err'),
      action: () => {
        Haptics.warn();
        onOk();
      }
    }
  });
}
