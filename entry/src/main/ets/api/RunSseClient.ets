import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { ApiKeyStore } from '../store/ApiKeyStore';
import { SseFrame } from '../models/Sse';
import { SseParser } from './SseParser';
import { Log } from '../utils/Log';

const TAG = 'RunSse';
const BASE = 'https://api.cursor.com';

export type SseListener = (frame: SseFrame) => void;
export type SseStatusListener = (kind: string, detail: string) => void;

export class RunSseClient {
  private httpReq: http.HttpRequest | undefined = undefined;
  private parser: SseParser = new SseParser();
  private lastEventId: string = '';
  private closed: boolean = false;
  private watchdogId: number = -1;
  private agentId: string = '';
  private runId: string = '';
  private generation: number = 0;
  private onFrame: SseListener | undefined = undefined;
  private onStatus: SseStatusListener | undefined = undefined;
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
  private sawData: boolean = false;

  getLastEventId(): string {
    return this.lastEventId;
  }

  async start(agentId: string, runId: string, lastEventId: string, onFrame: SseListener,
    onStatus: SseStatusListener, generation: number = 0): Promise<void> {
    this.stop();
    this.closed = false;
    this.agentId = agentId;
    this.runId = runId;
    this.generation = generation;
    this.lastEventId = lastEventId;
    this.onFrame = onFrame;
    this.onStatus = onStatus;
    this.parser.reset();
    this.sawData = false;
    await this.connect();
  }

  stop(): void {
    this.closed = true;
    this.onFrame = undefined;
    this.onStatus = undefined;
    this.clearWatchdog();
    this.destroyHttp();
  }

  private stillCurrent(generation: number): boolean {
    return !this.closed && this.generation === generation;
  }

  private async connect(): Promise<void> {
    const generation = this.generation;
    if (!this.stillCurrent(generation)) {
      return;
    }
    const key = ApiKeyStore.getInstance().getKey();
    if (!key) {
      this.emitStatus('error', '未配置 API Key');
      return;
    }
    const url =
      `${BASE}/v1/agents/${encodeURIComponent(this.agentId)}/runs/${encodeURIComponent(this.runId)}/stream`;
    this.destroyHttp();
    this.httpReq = http.createHttp();
    const headers: Record<string, string> = {};
    headers['Authorization'] = `Bearer ${key}`;
    headers['Accept'] = 'text/event-stream';
    headers['Cache-Control'] = 'no-cache';
    headers['User-Agent'] = 'CursorHarmonyNative/1.0';
    if (this.lastEventId.length > 0) {
      headers['Last-Event-ID'] = this.lastEventId;
    }

    this.emitStatus('connecting', '');
    this.armWatchdog();

    this.httpReq.on('dataReceive', (data: ArrayBuffer) => {
      if (!this.stillCurrent(generation)) {
        return;
      }
      if (!this.sawData) {
        this.sawData = true;
        this.emitStatus('streaming', '');
      }
      this.armWatchdog();
      try {
        const text = this.decoder.decodeWithStream(new Uint8Array(data), { stream: true });
        const frames = this.parser.feed(text);
        for (let i = 0; i < frames.length; i++) {
          if (!this.stillCurrent(generation)) {
            return;
          }
          const f = frames[i];
          if (f.id.length > 0) {
            this.lastEventId = f.id;
          }
          if (this.onFrame) {
            this.onFrame(f);
          }
          if (f.event === 'done') {
            this.emitStatus('done', '');
            this.stop();
            return;
          }
        }
      } catch (e) {
        Log.error(TAG, `parse chunk failed: ${JSON.stringify(e)}`);
      }
    });

    this.httpReq.on('dataEnd', () => {
      if (this.stillCurrent(generation)) {
        this.emitStatus('ended', 'stream dataEnd');
      }
    });

    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: 15000,
      readTimeout: 180000,
      usingProtocol: http.HttpProtocol.HTTP1_1
    };

    try {
      const code = await this.httpReq.requestInStream(url, options);
      if (!this.stillCurrent(generation)) {
        return;
      }
      Log.info(TAG, `stream finished code=${code}`);
      if (code === 410) {
        this.emitStatus('expired', 'stream_expired');
        this.stop();
      } else if (code >= 400) {
        this.emitStatus('error', `HTTP ${code}`);
        this.stop();
      } else {
        this.emitStatus('ended', `code ${code}`);
      }
    } catch (e) {
      if (this.stillCurrent(generation)) {
        Log.error(TAG, `stream error: ${JSON.stringify(e)}`);
        this.emitStatus('error', 'SSE 连接失败');
      }
    }
  }

  private armWatchdog(): void {
    this.clearWatchdog();
    const generation = this.generation;
    this.watchdogId = setTimeout(() => {
      if (this.stillCurrent(generation)) {
        this.emitStatus('stale', 'heartbeat timeout');
        this.destroyHttp();
      }
    }, 90000) as number;
  }

  private clearWatchdog(): void {
    if (this.watchdogId >= 0) {
      clearTimeout(this.watchdogId);
      this.watchdogId = -1;
    }
  }

  private destroyHttp(): void {
    if (this.httpReq) {
      try {
        this.httpReq.off('dataReceive');
        this.httpReq.off('dataEnd');
      } catch (_e) {
      }
      try {
        this.httpReq.destroy();
      } catch (_e) {
      }
      this.httpReq = undefined;
    }
  }

  private emitStatus(kind: string, detail: string): void {
    if (this.onStatus) {
      this.onStatus(kind, detail);
    }
  }
}
