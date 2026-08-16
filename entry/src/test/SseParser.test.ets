import { describe, it, expect } from '@ohos/hypium';
import { SseParser } from '../main/ets/api/SseParser';

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
  });
}
