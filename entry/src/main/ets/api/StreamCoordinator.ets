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
  private generation: number = 0;

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

  currentGeneration(): number {
    return this.generation;
  }

  async acquire(agentId: string, runId: string, onFrame: FrameHandler, onStatus: StatusHandler,
    resumeId: string = ''): Promise<void> {
    this.release();
    this.generation += 1;
    const generation = this.generation;
    this.agentId = agentId;
    this.runId = runId;
    this.frameHandler = onFrame;
    this.statusHandler = onStatus;
    this.lastEventId = resumeId;
    this.reconnectAttempt = 0;
    this.active = true;
    await this.open(generation);
  }

  release(): void {
    this.generation += 1;
    this.active = false;
    this.frameHandler = undefined;
    this.statusHandler = undefined;
    if (this.reconnectTimer >= 0) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
    if (this.client) {
      this.lastEventId = this.client.getLastEventId() || this.lastEventId;
      this.client.stop();
      this.client = undefined;
    }
    Log.info(TAG, 'released');
  }

  private async open(generation: number): Promise<void> {
    if (!this.active || this.generation !== generation) {
      return;
    }
    const agentId = this.agentId;
    const runId = this.runId;
    const onFrame = this.frameHandler;
    const onStatus = this.statusHandler;
    this.client = new RunSseClient();
    await this.client.start(agentId, runId, this.lastEventId, (frame: SseFrame) => {
      if (this.generation !== generation || !this.active) {
        return;
      }
      this.reconnectAttempt = 0;
      if (frame.id.length > 0) {
        this.lastEventId = frame.id;
      }
      if (onFrame) {
        onFrame(frame);
      }
    }, (kind: string, detail: string) => {
      if (this.generation !== generation) {
        return;
      }
      if (kind === 'expired' || kind === 'done') {
        this.active = false;
      }
      if (onStatus) {
        onStatus(kind, detail);
      }
      if (!this.active || this.generation !== generation) {
        return;
      }
      if (kind === 'error' || kind === 'ended' || kind === 'stale') {
        this.scheduleReconnect(generation);
      }
    }, generation);
  }

  private scheduleReconnect(generation: number): void {
    if (!this.active || this.generation !== generation) {
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
      if (this.generation !== generation || !this.active) {
        return;
      }
      if (this.client) {
        this.lastEventId = this.client.getLastEventId() || this.lastEventId;
        this.client.stop();
        this.client = undefined;
      }
      this.open(generation);
    }, delay) as number;
  }
}
