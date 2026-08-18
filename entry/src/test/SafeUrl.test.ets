import { describe, it, expect } from '@ohos/hypium';
import { isBlockedLinkScheme, isInAppBrowserUrl, isSafeHttpsUrl, parseHttpUrl } from '../main/ets/utils/SafeUrl';
import { repoIdentity } from '../main/ets/utils/DisplayFmt';
import { canApplyRunStatus, isInFlightStatus, isTerminalStatus, phaseFromRun, pickNewerIso } from '../main/ets/utils/RunState';
import { canFlushQueue, emptyQueue } from '../main/ets/viewmodels/FollowUpQueue';
import { appendRuntimeText, capMessages, capTimeline, clipText, CACHE_TEXT_MAX,
  CACHE_TIMELINE_MAX_ITEMS } from '../main/ets/utils/CacheLimit';
import { sanitizeDiagExtra } from '../main/ets/utils/SessionDiag';
import { isLiveWaitItem, isOpaqueStepLabel, isShowableImageUrl, imageUrlsFromMessage, imageUrlsFromText } from '../main/ets/utils/TimelineMedia';
import { meaningfulStepTitle } from '../main/ets/utils/TimelineCopy';
import { findUnreadAnchor, countNewContent, isWaitingThink } from '../main/ets/utils/TimelineView';
import { noticeTextFromLaunch, showUnreadFromLaunch } from '../main/ets/utils/WantParse';
import { parseMarkdown } from '../main/ets/utils/MarkdownParse';
import { ConversationMessage } from '../main/ets/models/Api';
import { TimelineItem } from '../main/ets/models/Timeline';
import { hashOperationBody } from '../main/ets/store/OpIdStore';

function fillText(ch: string, n: number): string {
  let s = '';
  for (let i = 0; i < n; i++) {
    s = `${s}${ch}`;
  }
  return s;
}

export default function safeUrlTest() {
  describe('SafeUrl', () => {
    it('rejects substring host spoof', 0, () => {
      expect(isInAppBrowserUrl('https://evilcursor.com')).assertFalse();
      expect(isInAppBrowserUrl('https://cursor.com.evil.tld/x')).assertFalse();
      expect(isInAppBrowserUrl('https://cursor.com/agents')).assertTrue();
      expect(isInAppBrowserUrl('https://docs.cursor.com/x')).assertTrue();
    });

    it('requires https', 0, () => {
      expect(isSafeHttpsUrl('http://cursor.com')).assertFalse();
      expect(isSafeHttpsUrl('https://cursor.com')).assertTrue();
      expect(isBlockedLinkScheme('javascript:alert(1)')).assertTrue();
      expect(isBlockedLinkScheme('file:///tmp')).assertTrue();
      expect(parseHttpUrl('not a url') === undefined).assertTrue();
    });
  });

  describe('RunState', () => {
    it('forbids terminal rollback', 0, () => {
      expect(isTerminalStatus('FINISHED')).assertTrue();
      expect(canApplyRunStatus('FINISHED', 'RUNNING')).assertFalse();
      expect(canApplyRunStatus('RUNNING', 'FINISHED')).assertTrue();
      expect(canApplyRunStatus('FINISHED', '')).assertFalse();
      expect(isInFlightStatus('CREATING')).assertTrue();
      expect(isInFlightStatus('FINISHED')).assertFalse();
      expect(phaseFromRun('RUNNING', false, false)).assertEqual('Streaming');
      expect(phaseFromRun('', true, false)).assertEqual('Loading');
      expect(phaseFromRun('ERROR', false, false)).assertEqual('Error');
      expect(pickNewerIso('2026-01-01T00:00:00Z', '2026-01-02T00:00:00Z'))
        .assertEqual('2026-01-02T00:00:00Z');
    });
  });

  describe('FollowUpQueue', () => {
    it('blocks flush while sending or active', 0, () => {
      const q = emptyQueue();
      q.text = 'hi';
      expect(canFlushQueue(q, true, false)).assertFalse();
      expect(canFlushQueue(q, false, true)).assertFalse();
      expect(canFlushQueue(q, false, false)).assertTrue();
    });
  });

  describe('DisplayFmt', () => {
    it('collapses repo url aliases', 0, () => {
      expect(repoIdentity('https://github.com/a/agents-android-shell.git'))
        .assertEqual(repoIdentity('https://github.com/a/agents-android-shell'));
      expect(repoIdentity('https://github.com/x/MyCloudSever'))
        .assertEqual(repoIdentity('https://github.com/x/mycloudsever'));
      expect(repoIdentity('x/cal')).assertEqual(repoIdentity('https://github.com/x/Cal'));
    });
  });

  describe('CacheLimit', () => {
    it('clips long text and keeps the newest timeline rows', 0, () => {
      expect(clipText('abc', 2)).assertEqual('ab');
      const items: TimelineItem[] = [];
      for (let i = 0; i < CACHE_TIMELINE_MAX_ITEMS + 5; i++) {
        const row: TimelineItem = {
          key: `k${i}`,
          kind: 'assistant',
          runId: 'r1',
          text: i === CACHE_TIMELINE_MAX_ITEMS + 4 ? fillText('x', CACHE_TEXT_MAX + 10) : 'ok'
        };
        items.push(row);
      }
      const out = capTimeline(items);
      expect(out.length).assertEqual(CACHE_TIMELINE_MAX_ITEMS);
      expect(out[0].key).assertEqual('k5');
      const lastText = out[out.length - 1].text ?? '';
      expect(lastText.length).assertEqual(CACHE_TEXT_MAX);
      const kept: TimelineItem = {
        key: 'img',
        kind: 'userPrompt',
        runId: 'r1',
        text: 'hi',
        localAt: '2026-08-18T00:00:00.000Z',
        imageUrls: ['file://preview.jpg']
      };
      const capped = capTimeline([kept]);
      expect(capped[0].localAt).assertEqual('2026-08-18T00:00:00.000Z');
      expect((capped[0].imageUrls ?? []).length).assertEqual(1);
    });

    it('clips conversation messages', 0, () => {
      const msg: ConversationMessage = {
        id: '1',
        type: 'user',
        text: fillText('z', CACHE_TEXT_MAX + 4),
        createdAt: '2026-08-18T00:00:00.000Z',
        images: ['https://cursor.com/x.png']
      };
      const out = capMessages([msg]);
      expect(out[0].text.length).assertEqual(CACHE_TEXT_MAX);
      expect(out[0].createdAt).assertEqual('2026-08-18T00:00:00.000Z');
      expect((out[0].images ?? []).length).assertEqual(1);
    });

    it('caps streaming text with an explicit marker', 0, () => {
      const out = appendRuntimeText('12345678901234567890', 'abcdefghijklmnopqrst', 32);
      expect(out.length).assertEqual(32);
      expect(out.indexOf('截断') >= 0).assertTrue();
      expect(appendRuntimeText(out, 'later', 32)).assertEqual(out);
    });
  });

  describe('OperationId', () => {
    it('hashes the same request body deterministically', 0, () => {
      const body = '{"prompt":{"text":"hi"}}';
      expect(hashOperationBody(body)).assertEqual(hashOperationBody(body));
      expect(hashOperationBody(body) === hashOperationBody('{"prompt":{"text":"bye"}}')).assertFalse();
    });
  });

  describe('SessionDiag', () => {
    it('strips keys and odd characters from extra', 0, () => {
      const fakeKey = 'crsr_' + 'ABCDEFGHijkl';
      const s = sanitizeDiagExtra('Bearer abc.def prompt=<script> ' + fakeKey);
      expect(s.indexOf('crsr_***') >= 0).assertTrue();
      expect(s.indexOf('Bearer ***') >= 0).assertTrue();
      expect(s.indexOf('<') < 0).assertTrue();
    });

    it('keeps chinese extra', 0, () => {
      const s = sanitizeDiagExtra('status=在想下一步 frames=12');
      expect(s.indexOf('在想下一步') >= 0).assertTrue();
    });
  });

  describe('TimelineMedia', () => {
    it('hides opaque step ids', 0, () => {
      expect(isOpaqueStepLabel('')).assertTrue();
      expect(isOpaqueStepLabel('步骤 642')).assertTrue();
      expect(isOpaqueStepLabel('Read src/foo.ts')).assertFalse();
      expect(meaningfulStepTitle('')).assertEqual('');
      expect(meaningfulStepTitle('步骤 642')).assertEqual('');
      expect(meaningfulStepTitle('Exploring the repo')).assertEqual('Exploring the repo');
    });

    it('treats empty streaming think as live wait', 0, () => {
      const item: TimelineItem = {
        key: 'waiting-r1',
        kind: 'thinking',
        runId: 'r1',
        text: '',
        streaming: true
      };
      expect(isLiveWaitItem(item)).assertTrue();
      expect(isWaitingThink(item, true)).assertTrue();
    });

    it('extracts https images and rejects data urls', 0, () => {
      expect(isShowableImageUrl('data:image/png;base64,abc')).assertFalse();
      expect(isShowableImageUrl('https://cursor.com/a.png')).assertTrue();
      expect(isShowableImageUrl('file://preview.jpg')).assertTrue();
      const urls = imageUrlsFromText('see ![shot](https://cursor.com/a.png) and ![skip](data:image/png;base64,xx)');
      expect(urls.length).assertEqual(1);
      expect(urls[0]).assertEqual('https://cursor.com/a.png');
      const msg: ConversationMessage = {
        id: 'm1',
        type: 'user',
        text: '![a](https://cursor.com/a.png)',
        images: ['https://cursor.com/b.png']
      };
      const all = imageUrlsFromMessage(msg);
      expect(all.length).assertEqual(2);
    });
  });

  describe('WantParseUnread', () => {
    it('reads showUnread from launch parameters', 0, () => {
      const yes: Record<string, Object> = { 'showUnread': '1' };
      const notice: Record<string, Object> = { 'noticeText': '已完成' };
      expect(showUnreadFromLaunch(yes)).assertTrue();
      expect(showUnreadFromLaunch(undefined)).assertFalse();
      expect(noticeTextFromLaunch(notice)).assertEqual('');
    });
  });

  describe('MarkdownImage', () => {
    it('parses a standalone markdown image as an image block', 0, () => {
      const blocks = parseMarkdown('![shot](https://cursor.com/a.png)\n\nsee above');
      expect(blocks[0].kind).assertEqual('image');
      expect(blocks[0].url).assertEqual('https://cursor.com/a.png');
      expect(blocks[0].text).assertEqual('shot');
    });
  });

  describe('TimelineUnread', () => {
    it('unread anchor lands on the next user prompt', 0, () => {
      const items: TimelineItem[] = [
        { key: 'u1', kind: 'userPrompt', runId: 'r1', text: 'one' },
        { key: 'a1', kind: 'assistant', runId: 'r1', text: 'ok' },
        { key: 'u2', kind: 'userPrompt', runId: 'r2', text: 'two' },
        { key: 'a2', kind: 'assistant', runId: 'r2', text: 'later' }
      ];
      expect(findUnreadAnchor(items, 'a1')).assertEqual('u2');
      expect(countNewContent(items, 'a1') > 0).assertTrue();
      expect(findUnreadAnchor(items, '')).assertEqual('u2');
    });
  });
}
