import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { Log } from './Log';

const TAG = 'SessionDiag';
const RING_MAX = 1536 * 1024;

export interface DiagRec {
  ts?: number;
  tag: string;
  event: string;
  agentId?: string;
  runId?: string;
  elapsedMs?: number;
  extra?: string;
}

/**
 * Append-only jsonl for post-hoc session tracing.
 * Never writes prompt text, API keys, or image payloads.
 */
export class SessionDiag {
  private static enabled: boolean = true;
  private static path: string = '';
  private static writing: boolean = false;
  private static pending: string[] = [];

  static setEnabled(v: boolean): void {
    SessionDiag.enabled = v;
  }

  static isEnabled(): boolean {
    return SessionDiag.enabled;
  }

  static filePath(): string {
    return SessionDiag.path;
  }

  static init(context: common.UIAbilityContext): void {
    try {
      const dir = `${context.filesDir}/diag`;
      try {
        fs.mkdirSync(dir);
      } catch (_e) {
      }
      SessionDiag.path = `${dir}/session.jsonl`;
      Log.info(TAG, `diag.path=${SessionDiag.path}`);
      SessionDiag.emit({ tag: TAG, event: 'init', extra: 'path_ok' });
    } catch (e) {
      Log.warn(TAG, `init failed: ${JSON.stringify(e)}`);
    }
  }

  static emit(rec: DiagRec): void {
    if (!SessionDiag.enabled) {
      return;
    }
    const ts = rec.ts !== undefined && rec.ts > 0 ? rec.ts : Date.now();
    const bits: string[] = [];
    bits.push(`"ts":${ts}`);
    bits.push(`"tag":${JSON.stringify(rec.tag)}`);
    bits.push(`"event":${JSON.stringify(rec.event)}`);
    if (rec.agentId && rec.agentId.length > 0) {
      bits.push(`"agentId":${JSON.stringify(hashId(rec.agentId))}`);
    }
    if (rec.runId && rec.runId.length > 0) {
      bits.push(`"runId":${JSON.stringify(hashId(rec.runId))}`);
    }
    if (rec.elapsedMs !== undefined && rec.elapsedMs >= 0) {
      bits.push(`"elapsedMs":${rec.elapsedMs}`);
    }
    if (rec.extra && rec.extra.length > 0) {
      bits.push(`"extra":${JSON.stringify(sanitizeExtra(rec.extra))}`);
    }
    const line = `{${bits.join(',')}}\n`;
    SessionDiag.pending.push(line);
    if (SessionDiag.pending.length > 400) {
      SessionDiag.pending.splice(0, SessionDiag.pending.length - 400);
    }
    SessionDiag.flush();
  }

  private static flush(): void {
    if (SessionDiag.writing || SessionDiag.path.length === 0 || SessionDiag.pending.length === 0) {
      return;
    }
    SessionDiag.writing = true;
    const batch = SessionDiag.pending.splice(0, SessionDiag.pending.length);
    try {
      SessionDiag.rotateIfNeeded();
      const text = batch.join('');
      const bytes = new util.TextEncoder().encodeInto(text);
      const file = fs.openSync(SessionDiag.path,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.APPEND);
      fs.writeSync(file.fd, bytes.buffer);
      fs.closeSync(file);
    } catch (e) {
      Log.warn(TAG, `write failed: ${JSON.stringify(e)}`);
    }
    SessionDiag.writing = false;
    if (SessionDiag.pending.length > 0) {
      SessionDiag.flush();
    }
  }

  private static rotateIfNeeded(): void {
    if (SessionDiag.path.length === 0) {
      return;
    }
    try {
      const st = fs.statSync(SessionDiag.path);
      if (st.size < RING_MAX) {
        return;
      }
      const file = fs.openSync(SessionDiag.path, fs.OpenMode.READ_ONLY);
      const buf = new ArrayBuffer(st.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);
      const raw = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
      const keepFrom = Math.max(0, raw.length - Math.floor(RING_MAX / 2));
      let cut = raw.indexOf('\n', keepFrom);
      if (cut < 0) {
        cut = keepFrom;
      } else {
        cut += 1;
      }
      const kept = raw.substring(cut);
      const out = new util.TextEncoder().encodeInto(kept);
      const tmp = `${SessionDiag.path}.tmp`;
      const wf = fs.openSync(tmp, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(wf.fd, out.buffer);
      fs.closeSync(wf);
      try {
        fs.unlinkSync(SessionDiag.path);
      } catch (_e) {
      }
      fs.renameSync(tmp, SessionDiag.path);
    } catch (_e) {
    }
  }
}

function hashId(id: string): string {
  let h = 0;
  for (let i = 0; i < id.length; i++) {
    h = ((h << 5) - h) + id.charCodeAt(i);
    h |= 0;
  }
  return `h${(h >>> 0).toString(16)}`;
}

export function sanitizeDiagExtra(extra: string): string {
  return sanitizeExtra(extra);
}

function sanitizeExtra(extra: string): string {
  let t = extra.replace(/crsr_[A-Za-z0-9_-]+/g, 'crsr_***')
    .replace(/Bearer\s+[A-Za-z0-9._-]+/gi, 'Bearer ***');
  t = t.replace(/[\u0000-\u001f<>]/g, ' ');
  if (t.length > 240) {
    return t.substring(0, 240);
  }
  return t;
}
