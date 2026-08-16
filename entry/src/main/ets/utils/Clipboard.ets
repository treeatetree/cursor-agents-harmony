import { pasteboard } from '@kit.BasicServicesKit';
import { Log } from './Log';

const TAG = 'Clipboard';

export async function copyToClipboard(text: string): Promise<boolean> {
  if (!text || text.length === 0) {
    return false;
  }
  try {
    const board = pasteboard.getSystemPasteboard();
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    await board.setData(data);
    return true;
  } catch (e) {
    Log.warn(TAG, `copy failed: ${JSON.stringify(e)}`);
    return false;
  }
}

/** Call only after a successful PasteButton click (temporary pasteboard grant). */
export async function readClipboardText(): Promise<string> {
  try {
    const board = pasteboard.getSystemPasteboard();
    const has = await board.hasData();
    if (!has) {
      return '';
    }
    const data = await board.getData();
    const text = data.getPrimaryText();
    return text ?? '';
  } catch (e) {
    Log.warn(TAG, `read failed: ${JSON.stringify(e)}`);
    return '';
  }
}
