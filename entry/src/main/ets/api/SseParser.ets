import { SseEventType, SseFrame } from '../models/Sse';

export const SSE_LINE_MAX = 256 * 1024;
export const SSE_FRAME_MAX = 1024 * 1024;

/**
 * Incremental SSE line parser. Feed UTF-8 text chunks; returns complete frames.
 * Retains trailing incomplete line between chunks.
 */
export class SseParser {
  private lineBuf: string = '';
  private eventName: string = '';
  private dataLines: string[] = [];
  private id: string = '';
  private droppingLine: boolean = false;
  private droppingFrame: boolean = false;
  private frameSize: number = 0;

  feed(chunk: string): SseFrame[] {
    const out: SseFrame[] = [];
    let incoming = chunk;
    if (this.droppingLine) {
      const newline = incoming.indexOf('\n');
      if (newline < 0) {
        return out;
      }
      this.droppingLine = false;
      this.droppingFrame = false;
      this.clearFrame();
      incoming = incoming.substring(newline + 1);
    }
    this.lineBuf += incoming;
    const lines = this.lineBuf.split('\n');
    this.lineBuf = lines.pop() ?? '';
    const trailingOverflow = this.lineBuf.length > SSE_LINE_MAX;
    if (trailingOverflow) {
      this.lineBuf = '';
    }
    for (let i = 0; i < lines.length; i++) {
      let line = lines[i];
      if (line.length > SSE_LINE_MAX) {
        this.clearFrame();
        this.droppingFrame = true;
        continue;
      }
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      if (line.length === 0) {
        if (this.droppingFrame) {
          this.droppingFrame = false;
          this.clearFrame();
          continue;
        }
        const frame = this.flushFrame();
        if (frame) {
          out.push(frame);
        }
        continue;
      }
      if (line.startsWith(':')) {
        continue; // comment
      }
      if (this.droppingFrame) {
        continue;
      }
      this.frameSize += line.length;
      if (this.frameSize > SSE_FRAME_MAX) {
        this.clearFrame();
        this.droppingFrame = true;
        continue;
      }
      const colon = line.indexOf(':');
      let field = line;
      let value = '';
      if (colon >= 0) {
        field = line.substring(0, colon);
        value = line.substring(colon + 1);
        if (value.startsWith(' ')) {
          value = value.substring(1);
        }
      }
      if (field === 'event') {
        this.eventName = value;
      } else if (field === 'data') {
        this.dataLines.push(value);
      } else if (field === 'id') {
        this.id = value;
      }
    }
    if (trailingOverflow) {
      this.droppingLine = true;
      this.droppingFrame = true;
      this.clearFrame();
    }
    return out;
  }

  reset(): void {
    this.lineBuf = '';
    this.droppingLine = false;
    this.droppingFrame = false;
    this.clearFrame();
  }

  private clearFrame(): void {
    this.eventName = '';
    this.dataLines = [];
    this.id = '';
    this.frameSize = 0;
  }

  private flushFrame(): SseFrame | undefined {
    if (this.dataLines.length === 0 && this.eventName.length === 0) {
      this.clearFrame();
      return undefined;
    }
    const data = this.dataLines.join('\n');
    const event = mapEvent(this.eventName.length > 0 ? this.eventName : 'message');
    const frame: SseFrame = {
      id: this.id,
      event: event,
      data: data
    };
    this.clearFrame();
    return frame;
  }
}

function mapEvent(name: string): SseEventType {
  if (name === 'status' || name === 'assistant' || name === 'thinking' || name === 'tool_call' ||
    name === 'interaction_update' || name === 'heartbeat' || name === 'result' || name === 'error' ||
    name === 'done') {
    return name;
  }
  return 'unknown';
}
