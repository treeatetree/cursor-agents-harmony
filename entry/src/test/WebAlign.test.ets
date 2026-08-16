import { describe, it, expect } from '@ohos/hypium';
import { gitCompareUrl, parseGitWeb } from '../main/ets/utils/GitLinks';
import { applyInboxQuery, groupAgents } from '../main/ets/utils/InboxGrouping';
import { clipNotice, parseMarkdown, tokenizeInline } from '../main/ets/utils/MarkdownParse';
import { AgentSummary } from '../main/ets/models/Api';
import { fileNameOf, isImagePath, isVideoPath } from '../main/ets/utils/DisplayFmt';
import { sniffMime } from '../main/ets/utils/ImagePicker';
import { isSubagentTool, subagentDetail } from '../main/ets/utils/StreamText';
import { unwrapUsageRuns } from '../main/ets/api/ApiUnwrap';

function agent(partial: Record<string, string>): AgentSummary {
  return {
    id: partial['id'] ?? 'bc-1',
    name: partial['name'] ?? 'Task',
    status: (partial['status'] ?? 'ACTIVE') as 'ACTIVE' | 'ARCHIVED',
    url: '',
    createdAt: partial['createdAt'] ?? '2026-08-01T00:00:00.000Z',
    updatedAt: partial['updatedAt'] ?? '2026-08-01T00:00:00.000Z',
    latestRunStatus: partial['latestRunStatus'],
    repos: partial['repo'] ? [{ url: partial['repo'] }] : undefined
  };
}

export default function webAlignTest() {
  describe('GitLinks', () => {
    it('parses https github remote', 0, () => {
      const g = parseGitWeb('https://github.com/acme/app.git');
      expect(g !== undefined).assertTrue();
      expect(g?.owner).assertEqual('acme');
      expect(g?.repo).assertEqual('app');
    });

    it('parses ssh github remote', 0, () => {
      const g = parseGitWeb('git@github.com:acme/app.git');
      expect(g !== undefined).assertTrue();
      expect(g?.host).assertEqual('github.com');
      expect(g?.owner).assertEqual('acme');
    });

    it('builds github compare url', 0, () => {
      const url = gitCompareUrl('https://github.com/acme/app', 'main', 'cursor/fix-login');
      expect(url).assertEqual('https://github.com/acme/app/compare/main...cursor%2Ffix-login');
    });

    it('falls back to tree when base missing', 0, () => {
      const url = gitCompareUrl('https://github.com/acme/app.git', '', 'feat/x');
      expect(url).assertEqual('https://github.com/acme/app/tree/feat%2Fx');
    });
  });

  describe('InboxGrouping', () => {
    it('filters running agents', 0, () => {
      const items = [
        agent({ id: 'a', latestRunStatus: 'RUNNING', name: 'Live' }),
        agent({ id: 'b', latestRunStatus: 'FINISHED', name: 'Done' })
      ];
      const out = applyInboxQuery(items, '', 'running', 'updated');
      expect(out.length).assertEqual(1);
      expect(out[0].id).assertEqual('a');
    });

    it('searches repo and name', 0, () => {
      const items = [
        agent({ id: 'a', name: 'Auth', repo: 'https://github.com/acme/app' }),
        agent({ id: 'b', name: 'Other', repo: 'https://github.com/acme/web' })
      ];
      expect(applyInboxQuery(items, 'auth', 'all', 'name').length).assertEqual(1);
      expect(applyInboxQuery(items, 'web', 'all', 'name')[0].id).assertEqual('b');
    });

    it('sorts by updatedAt newest first', 0, () => {
      const items = [
        agent({ id: 'old', latestRunStatus: 'FINISHED', updatedAt: '2026-08-14T12:00:00.000Z' }),
        agent({ id: 'run', latestRunStatus: 'CREATING', updatedAt: '2026-08-14T11:00:00.000Z' }),
        agent({ id: 'fresh', latestRunStatus: 'FINISHED', updatedAt: '2026-08-16T09:00:00.000Z' })
      ];
      expect(applyInboxQuery(items, '', 'all', 'updated')[0].id).assertEqual('fresh');
      expect(applyInboxQuery(items, '', 'all', 'updated')[1].id).assertEqual('old');
    });

    it('keeps recency inside repo groups', 0, () => {
      const items = applyInboxQuery([
        agent({
          id: 'older',
          repo: 'https://github.com/acme/app',
          updatedAt: '2026-08-10T12:00:00.000Z'
        }),
        agent({
          id: 'newer',
          repo: 'https://github.com/acme/app',
          updatedAt: '2026-08-16T12:00:00.000Z'
        })
      ], '', 'all', 'updated');
      const buckets = groupAgents(items, 'repo');
      expect(buckets[0].items[0].id).assertEqual('newer');
    });

    it('groups by status', 0, () => {
      const items = [
        agent({ id: 'a', latestRunStatus: 'ERROR' }),
        agent({ id: 'b', latestRunStatus: 'RUNNING' })
      ];
      const buckets = groupAgents(items, 'status');
      expect(buckets.length).assertEqual(2);
    });

    it('pinned ids stay first in pin order', 0, () => {
      const items = [
        agent({ id: 'a', latestRunStatus: 'FINISHED', updatedAt: '2026-08-16T12:00:00.000Z' }),
        agent({ id: 'b', latestRunStatus: 'FINISHED', updatedAt: '2026-08-16T11:00:00.000Z' }),
        agent({ id: 'c', latestRunStatus: 'RUNNING', updatedAt: '2026-08-16T10:00:00.000Z' })
      ];
      const out = applyInboxQuery(items, '', 'all', 'updated', ['b', 'a']);
      expect(out[0].id).assertEqual('b');
      expect(out[1].id).assertEqual('a');
      expect(out[2].id).assertEqual('c');
      const buckets = groupAgents(out, 'status', ['b', 'a']);
      expect(buckets[0].key).assertEqual('pinned');
      expect(buckets[0].items[0].id).assertEqual('b');
      expect(buckets[0].items.length).assertEqual(2);
    });

    it('repo groups order by latest conversation', 0, () => {
      const items = [
        agent({
          id: 'old',
          repo: 'https://github.com/acme/old',
          updatedAt: '2026-08-10T12:00:00.000Z'
        }),
        agent({
          id: 'fresh',
          repo: 'https://github.com/acme/new',
          updatedAt: '2026-08-16T12:00:00.000Z'
        })
      ];
      const buckets = groupAgents(items, 'repo');
      expect(buckets.length).assertEqual(2);
      expect(buckets[0].key).assertEqual('acme/new');
      expect(buckets[1].key).assertEqual('acme/old');
    });

    it('none grouping keeps a single unlabeled bucket', 0, () => {
      const items = [
        agent({ id: 'a', latestRunStatus: 'ERROR' }),
        agent({ id: 'b', latestRunStatus: 'RUNNING' })
      ];
      const buckets = groupAgents(items, 'none');
      expect(buckets.length).assertEqual(1);
      expect(buckets[0].items.length).assertEqual(2);
      expect(buckets[0].label).assertEqual('');
    });
  });

  describe('ArtifactsFmt', () => {
    it('classifies screenshot and video paths', 0, () => {
      expect(isImagePath('artifacts/demo.png')).assertTrue();
      expect(isImagePath('IMG_001.heic')).assertTrue();
      expect(isVideoPath('walkthrough.webm')).assertTrue();
      expect(fileNameOf('artifacts/foo/bar.jpg')).assertEqual('bar.jpg');
    });
  });

  describe('Image sniff', () => {
    it('detects jpeg and heif even when named jpg', 0, () => {
      const jpeg = new ArrayBuffer(3);
      const j = new Uint8Array(jpeg);
      j[0] = 0xFF;
      j[1] = 0xD8;
      j[2] = 0xFF;
      expect(sniffMime(jpeg, 'a.heic')).assertEqual('image/jpeg');
      const heif = new ArrayBuffer(12);
      const h = new Uint8Array(heif);
      h[4] = 0x66;
      h[5] = 0x74;
      h[6] = 0x79;
      h[7] = 0x70;
      h[8] = 0x68;
      h[9] = 0x65;
      h[10] = 0x69;
      h[11] = 0x63;
      expect(sniffMime(heif, 'IMG_001.jpg')).assertEqual('image/heif');
    });
  });

  describe('Subagent tools', () => {
    it('recognizes Task and explore as subagent cards', 0, () => {
      expect(isSubagentTool('Task')).assertTrue();
      expect(isSubagentTool('explore')).assertTrue();
      expect(isSubagentTool('read_file')).assertFalse();
    });

    it('summarizes subagent description', 0, () => {
      const d = subagentDetail('{"description":"Scan auth","subagent_type":"explore","prompt":"look around"}');
      expect(d.indexOf('explore') >= 0).assertTrue();
      expect(d.indexOf('Scan auth') >= 0).assertTrue();
    });
  });

  describe('MarkdownParse', () => {
    it('keeps markdown links as label not raw syntax', 0, () => {
      const blocks = parseMarkdown('见 [PR #1](https://github.com/acme/app/pull/1) 和正文');
      expect(blocks.length).assertEqual(1);
      const segs = tokenizeInline(blocks[0].text);
      let found = false;
      for (let i = 0; i < segs.length; i++) {
        if (segs[i].url.indexOf('github.com') >= 0 && segs[i].text === 'PR #1') {
          found = true;
        }
      }
      expect(found).assertTrue();
    });

    it('does not treat [PR] list items as tasks', 0, () => {
      const blocks = parseMarkdown('- [PR #2](https://github.com/acme/app/pull/2)');
      expect(blocks[0].kind).assertEqual('li');
      const segs = tokenizeInline(blocks[0].text);
      expect(segs[0].text).assertEqual('PR #2');
      expect(segs[0].url.indexOf('/pull/2') >= 0).assertTrue();
    });

    it('parses table cells with inline code', 0, () => {
      const md = '| 轨道 | 路径 |\n| --- | --- |\n| Notion | `product/` |';
      const blocks = parseMarkdown(md);
      expect(blocks[0].kind).assertEqual('table');
      expect(blocks[0].text.indexOf('product/') >= 0).assertTrue();
    });

    it('clips notice without raw markdown', 0, () => {
      const s = clipNotice('## 结论\n修好了 [Inbox](https://example.com) 排序', 40);
      expect(s.indexOf('http') < 0).assertTrue();
      expect(s.indexOf('Inbox') >= 0).assertTrue();
    });
  });

  describe('ApiUnwrap usage', () => {
    it('reads per-run token usage', 0, () => {
      const runs = unwrapUsageRuns({
        runs: [{
          id: 'run-1',
          usage: { inputTokens: 10, outputTokens: 4, totalTokens: 14 }
        }]
      });
      expect(runs.length).assertEqual(1);
      expect(runs[0].usage.inputTokens).assertEqual(10);
      expect(runs[0].usage.totalTokens).assertEqual(14);
    });
  });
}
