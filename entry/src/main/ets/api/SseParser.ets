import { SseEventType, SseFrame } from '../models/Sse';

/**
 * Incremental SSE line parser. Feed UTF-8 text chunks; returns complete frames.
 * Retains trailing incomplete line between chunks.
 */
export class SseParser {
  private lineBuf: string = '';
  private eventName: string = '';
  private dataLines: string[] = [];
  private id: string = '';

  feed(chunk: string): SseFrame[] {
    const out: SseFrame[] = [];
    this.lineBuf += chunk;
    const lines = this.lineBuf.split('\n');
    this.lineBuf = lines.pop() ?? '';
    for (let i = 0; i < lines.length; i++) {
      let line = lines[i];
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      if (line.length === 0) {
        const frame = this.flushFrame();
        if (frame) {
          out.push(frame);
        }
        continue;
      }
      if (line.startsWith(':')) {
        continue; // comment
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
    return out;
  }

  reset(): void {
    this.lineBuf = '';
    this.eventName = '';
    this.dataLines = [];
    this.id = '';
  }

  private flushFrame(): SseFrame | undefined {
    if (this.dataLines.length === 0 && this.eventName.length === 0) {
      this.id = '';
      return undefined;
    }
    const data = this.dataLines.join('\n');
    const event = mapEvent(this.eventName.length > 0 ? this.eventName : 'message');
    const frame: SseFrame = {
      id: this.id,
      event: event,
      data: data
    };
    this.eventName = '';
    this.dataLines = [];
    // keep last id for sticky semantics externally; clear local for next frame
    this.id = '';
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
