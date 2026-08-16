import { SseFrame } from '../models/Sse';
import { RunSseClient } from './RunSseClient';
import { Log } from '../utils/Log';

const TAG = 'StreamCoord';

export type FrameHandler = (frame: SseFrame) => void;
export type StatusHandler = (kind: string, detail: string) => void;

/** Global single-stream arbitrator — at most one active SSE. */
export class StreamCoordinator {
  private static instance: StreamCoordinator | undefined = undefined;
  private client: RunSseClient | undefined = undefined;
  private agentId: string = '';
  private runId: string = '';
  private lastEventId: string = '';
  private reconnectAttempt: number = 0;
  private reconnectTimer: number = -1;
  private frameHandler: FrameHandler | undefined = undefined;
  private statusHandler: StatusHandler | undefined = undefined;
  private active: boolean = false;

  static getInstance(): StreamCoordinator {
    if (!StreamCoordinator.instance) {
      StreamCoordinator.instance = new StreamCoordinator();
    }
    return StreamCoordinator.instance;
  }

  isActive(): boolean {
    return this.active;
  }

  currentRunId(): string {
    return this.runId;
  }

  async acquire(agentId: string, runId: string, onFrame: FrameHandler, onStatus: StatusHandler,
    resumeId: string = ''): Promise<void> {
    this.release();
    this.agentId = agentId;
    this.runId = runId;
    this.frameHandler = onFrame;
    this.statusHandler = onStatus;
    this.lastEventId = resumeId;
    this.reconnectAttempt = 0;
    this.active = true;
    await this.open();
  }

  release(): void {
    this.active = false;
    if (this.reconnectTimer >= 0) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
    if (this.client) {
      this.lastEventId = this.client.getLastEventId() || this.lastEventId;
      this.client.stop();
      this.client = undefined;
    }
    this.frameHandler = undefined;
    this.statusHandler = undefined;
    Log.info(TAG, 'released');
  }

  private async open(): Promise<void> {
    if (!this.active) {
      return;
    }
    this.client = new RunSseClient();
    await this.client.start(this.agentId, this.runId, this.lastEventId, (frame: SseFrame) => {
      this.reconnectAttempt = 0;
      if (frame.id.length > 0) {
        this.lastEventId = frame.id;
      }
      if (this.frameHandler) {
        this.frameHandler(frame);
      }
    }, (kind: string, detail: string) => {
      if (this.statusHandler) {
        this.statusHandler(kind, detail);
      }
      if (!this.active) {
        return;
      }
      if (kind === 'expired' || kind === 'done') {
        this.active = false;
        return;
      }
      if (kind === 'error' || kind === 'ended' || kind === 'stale') {
        this.scheduleReconnect();
      }
    });
  }

  private scheduleReconnect(): void {
    if (!this.active) {
      return;
    }
    if (this.reconnectTimer >= 0) {
      return;
    }
    const delay = Math.min(30000, 1000 * Math.pow(2, this.reconnectAttempt));
    this.reconnectAttempt = Math.min(this.reconnectAttempt + 1, 5);
    if (this.statusHandler) {
      this.statusHandler('reconnecting', `wait ${delay}ms`);
    }
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = -1;
      if (this.client) {
        this.lastEventId = this.client.getLastEventId() || this.lastEventId;
        this.client.stop();
        this.client = undefined;
      }
      this.open();
    }, delay) as number;
  }
}
