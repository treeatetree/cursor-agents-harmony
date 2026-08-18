import { describe, it, expect } from '@ohos/hypium';
import { isBlockedLinkScheme, isInAppBrowserUrl, isSafeHttpsUrl, parseHttpUrl } from '../main/ets/utils/SafeUrl';
import { repoIdentity } from '../main/ets/utils/DisplayFmt';
import { canApplyRunStatus, isTerminalStatus, pickNewerIso } from '../main/ets/utils/RunState';
import { canFlushQueue, emptyQueue } from '../main/ets/viewmodels/FollowUpQueue';
import { capMessages, capTimeline, clipText, CACHE_TEXT_MAX, CACHE_TIMELINE_MAX_ITEMS } from '../main/ets/utils/CacheLimit';
import { sanitizeDiagExtra } from '../main/ets/utils/SessionDiag';
import { ConversationMessage } from '../main/ets/models/Api';
import { TimelineItem } from '../main/ets/models/Timeline';

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
    });

    it('clips conversation messages', 0, () => {
      const msg: ConversationMessage = {
        id: '1',
        type: 'user',
        text: fillText('z', CACHE_TEXT_MAX + 4)
      };
      const out = capMessages([msg]);
      expect(out[0].text.length).assertEqual(CACHE_TEXT_MAX);
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
  });
}
