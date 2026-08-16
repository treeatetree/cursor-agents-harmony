import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x435552;

/** hilog helper — never logs raw API keys. */
export class Log {
  static info(tag: string, msg: string): void {
    hilog.info(DOMAIN, tag, '%{public}s', Log.redact(msg));
  }

  static warn(tag: string, msg: string): void {
    hilog.warn(DOMAIN, tag, '%{public}s', Log.redact(msg));
  }

  static error(tag: string, msg: string): void {
    hilog.error(DOMAIN, tag, '%{public}s', Log.redact(msg));
  }

  static maskKey(key: string): string {
    if (!key || key.length < 10) {
      return 'crsr_***';
    }
    return `${key.substring(0, 5)}••••${key.substring(key.length - 4)}`;
  }

  private static redact(msg: string): string {
    // Mask Bearer tokens / crsr_ keys if accidentally interpolated.
    return msg
      .replace(/crsr_[A-Za-z0-9_-]+/g, 'crsr_***')
      .replace(/Bearer\s+[A-Za-z0-9._-]+/gi, 'Bearer ***');
  }
}
