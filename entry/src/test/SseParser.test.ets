import { describe, it, expect } from '@ohos/hypium';
import { SSE_FRAME_MAX, SSE_LINE_MAX, SseParser } from '../main/ets/api/SseParser';

export default function sseParserTest() {
  describe('SseParser', () => {
    it('parses framed event with id', 0, () => {
      const p = new SseParser();
      const frames = p.feed(
        'id: 1-0\nevent: assistant\ndata: {"text":"hi"}\n\n'
      );
      expect(frames.length).assertEqual(1);
      expect(frames[0].event).assertEqual('assistant');
      expect(frames[0].id).assertEqual('1-0');
      expect(frames[0].data).assertEqual('{"text":"hi"}');
    });

    it('keeps half line across chunks', 0, () => {
      const p = new SseParser();
      let frames = p.feed('event: status\ndata: {"st');
      expect(frames.length).assertEqual(0);
      frames = p.feed('atus":"RUNNING"}\n\n');
      expect(frames.length).assertEqual(1);
      expect(frames[0].event).assertEqual('status');
    });

    it('joins multiline data', 0, () => {
      const p = new SseParser();
      const frames = p.feed('event: assistant\ndata: {"text":"a"}\ndata: {"text":"b"}\n\n');
      expect(frames.length).assertEqual(1);
      expect(frames[0].data.indexOf('\n') >= 0).assertTrue();
    });

    it('ignores comment lines', 0, () => {
      const p = new SseParser();
      const frames = p.feed(': ping\nevent: heartbeat\ndata: {}\n\n');
      expect(frames.length).assertEqual(1);
      expect(frames[0].event).assertEqual('heartbeat');
    });

    it('drops an unterminated oversized line', 0, () => {
      const p = new SseParser();
      const chunk = 'x'.repeat(1024);
      let frames = p.feed('');
      for (let i = 0; i <= Math.floor(SSE_LINE_MAX / chunk.length); i++) {
        frames = p.feed(chunk);
      }
      expect(frames.length).assertEqual(0);
      const recovered = p.feed('\nevent: heartbeat\ndata: {}\n\n');
      expect(recovered.length).assertEqual(1);
    });

    it('drops an oversized line delivered with its newline', 0, () => {
      const p = new SseParser();
      const huge = 'x'.repeat(SSE_LINE_MAX + 1);
      const frames = p.feed(`event: assistant\ndata: ${huge}\n\n`);
      expect(frames.length).assertEqual(0);
      const recovered = p.feed('event: heartbeat\ndata: {}\n\n');
      expect(recovered.length).assertEqual(1);
    });

    it('discards continuation chunks until the oversized line ends', 0, () => {
      const p = new SseParser();
      p.feed(`event: assistant\ndata: ${'x'.repeat(SSE_LINE_MAX + 1)}`);
      const forged = p.feed('event: done\n\n');
      expect(forged.length).assertEqual(0);
      const recovered = p.feed('event: heartbeat\ndata: {}\n\n');
      expect(recovered.length).assertEqual(1);
      expect(recovered[0].event).assertEqual('heartbeat');
    });

    it('drops a multiline frame whose total payload is oversized', 0, () => {
      const p = new SseParser();
      const part = 'x'.repeat(Math.floor(SSE_FRAME_MAX / 5));
      let raw = 'event: assistant\n';
      for (let i = 0; i < 6; i++) {
        raw = `${raw}data: ${part}\n`;
      }
      const frames = p.feed(`${raw}\n`);
      expect(frames.length).assertEqual(0);
      const recovered = p.feed('event: heartbeat\ndata: {}\n\n');
      expect(recovered.length).assertEqual(1);
    });

    it('resets the size limit after every completed frame', 0, () => {
      const p = new SseParser();
      const data = 'x'.repeat(Math.floor(SSE_FRAME_MAX / 8));
      for (let i = 0; i < 10; i++) {
        const frames = p.feed(`event: assistant\ndata: ${data}\n\n`);
        expect(frames.length).assertEqual(1);
      }
    });
  });
}
