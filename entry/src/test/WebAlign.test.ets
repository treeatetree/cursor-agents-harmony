import { describe, it, expect } from '@ohos/hypium';
import { gitCompareUrl, isOriginRepo, looksLikeRepoUrl, normalizeCreateRepoUrl, parseGitWeb } from '../main/ets/utils/GitLinks';
import { applyInboxQuery, collectRecentEnvs, diffInboxAgents, groupAgents, inboxDeltaLabel, mergeInboxLists, recencyMs, sortByRecency } from '../main/ets/utils/InboxGrouping';
import { unwrapAgentsList } from '../main/ets/api/ApiUnwrap';
import { agentIdFromLaunch, noticeTextFromLaunch, showUnreadFromLaunch } from '../main/ets/utils/WantParse';
import { citationQuote, clipNotice, isCitationFence, parseMarkdown, tokenizeInline } from '../main/ets/utils/MarkdownParse';
import { AgentSummary, ConversationMessage, ModelInfo, ModelParamValue, ModelVariant, ModelVariantParam } from '../main/ets/models/Api';
import { fileNameOf, isImagePath, isVideoPath } from '../main/ets/utils/DisplayFmt';
import { sniffMime } from '../main/ets/utils/ImagePicker';
import { isSubagentTool, lastTextSummary, subagentDetail } from '../main/ets/utils/StreamText';
import { unwrapUsageRuns } from '../main/ets/api/ApiUnwrap';
import { findUnreadAnchor, countNewContent, isWaitingThink, nextUserJumpAt, visibleKeySig, visibleRowSig, visibleTimeline } from '../main/ets/utils/TimelineView';
import { processDoneTitle, processLiveTitle, runHeaderVerb, toolSlug, usedToolLine, waitingThinkLabel } from '../main/ets/utils/TimelineCopy';
import { convFingerprint, keepPendingTurns, lastMessageStamp, mergeCachedActivity } from '../main/ets/utils/TimelineMerge';
import { cacheCoversConversation, cacheCoversDetail } from '../main/ets/utils/CachePolicy';
import {
  buildParamRows, coerceParamsToVariant, formatModelSent, ModelParamRow, modelSentTags, rowsToParams, snapParamRows
} from '../main/ets/utils/ModelGroups';
import { TimelineItem } from '../main/ets/models/Timeline';

function agent(partial: Record<string, string>): AgentSummary {
  const row: AgentSummary = {
    id: partial['id'] ?? 'bc-1',
    name: partial['name'] ?? 'Task',
    status: (partial['status'] ?? 'ACTIVE') as 'ACTIVE' | 'ARCHIVED',
    url: '',
    createdAt: partial['createdAt'] ?? '2026-08-01T00:00:00.000Z',
    updatedAt: partial['updatedAt'] ?? '2026-08-01T00:00:00.000Z',
    latestRunStatus: partial['latestRunStatus'],
    repos: partial['repo'] ? [{ url: partial['repo'] }] : undefined
  };
  if (partial['lastUserAt'] && partial['lastUserAt'].length > 0) {
    row.lastUserAt = partial['lastUserAt'];
  }
  return row;
}

function pv(value: string): ModelParamValue {
  return { value: value };
}

function vp(id: string, value: string): ModelVariantParam {
  return { id: id, value: value };
}

function solVariant(context: string, reasoning: string, fast: string, isDefault: boolean): ModelVariant {
  const v: ModelVariant = {
    params: [vp('reasoning', reasoning), vp('fast', fast), vp('context', context)]
  };
  if (isDefault) {
    v.isDefault = true;
  }
  return v;
}

function gpt56sol(): ModelInfo {
  const reasonings: string[] = ['none', 'low', 'medium', 'high'];
  const variants: ModelVariant[] = [];
  for (let i = 0; i < reasonings.length; i++) {
    const r = reasonings[i];
    variants.push(solVariant('272k', r, 'true', false));
    variants.push(solVariant('272k', r, 'false', false));
    variants.push(solVariant('1m', r, 'false', r === 'medium'));
  }
  return {
    id: 'gpt-5.6-sol',
    displayName: 'GPT-5.6 sol',
    params: [
      { id: 'reasoning', values: [pv('none'), pv('low'), pv('medium'), pv('high')] },
      { id: 'fast', values: [pv('true'), pv('false')] },
      { id: 'context', values: [pv('272k'), pv('1m')] }
    ],
    variants: variants
  };
}

function rowIndex(rows: ModelParamRow[], id: string): number {
  for (let i = 0; i < rows.length; i++) {
    if (rows[i].id === id) {
      return i;
    }
  }
  return -1;
}

function valueIndex(row: ModelParamRow, value: string): number {
  for (let i = 0; i < row.values.length; i++) {
    if (row.values[i] === value) {
      return i;
    }
  }
  return -1;
}

function paramValue(params: ModelVariantParam[], id: string): string {
  for (let i = 0; i < params.length; i++) {
    if (params[i].id === id) {
      return params[i].value;
    }
  }
  return '';
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

    it('parses origin clone and codebase browse urls', 0, () => {
      const a = parseGitWeb('https://origin.cursor.com/acme/app.git');
      expect(a?.owner).assertEqual('acme');
      expect(a?.repo).assertEqual('app');
      const b = parseGitWeb('https://cursor.com/codebase/acme/app');
      expect(b?.owner).assertEqual('acme');
      expect(b?.repo).assertEqual('app');
      expect(isOriginRepo('https://origin.cursor.com/acme/app')).assertTrue();
      expect(isOriginRepo('https://github.com/acme/app')).assertFalse();
      expect(isOriginRepo('https://cursor.com/docs/origin')).assertFalse();
    });

    it('detects pasted repo urls vs name search', 0, () => {
      expect(looksLikeRepoUrl('https://github.com/acme/app')).assertTrue();
      expect(looksLikeRepoUrl('git@github.com:acme/app.git')).assertTrue();
      expect(looksLikeRepoUrl('family-finance')).assertFalse();
    });

    it('normalizes codebase urls to origin clone urls', 0, () => {
      expect(normalizeCreateRepoUrl('https://cursor.com/codebase/acme/app'))
        .assertEqual('https://origin.cursor.com/acme/app');
      expect(normalizeCreateRepoUrl('https://origin.cursor.com/acme/app.git'))
        .assertEqual('https://origin.cursor.com/acme/app');
      expect(normalizeCreateRepoUrl('https://github.com/acme/app'))
        .assertEqual('https://github.com/acme/app');
    });

    it('origin compare falls back to codebase home', 0, () => {
      const url = gitCompareUrl('https://origin.cursor.com/acme/app', 'main', 'cursor/fix');
      expect(url).assertEqual('https://cursor.com/codebase/acme/app');
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

    it('follow-up recency lifts the agent to the top', 0, () => {
      const older = agent({ id: 'old', updatedAt: '2026-08-01T00:00:00.000Z' });
      const newer = agent({ id: 'new', updatedAt: '2026-08-01T01:00:00.000Z' });
      older.lastUserAt = '2026-08-18T12:00:00.000Z';
      const out = sortByRecency([newer, older]);
      expect(out[0].id).assertEqual('old');
    });

    it('searches repo and name', 0, () => {
      const items = [
        agent({ id: 'a', name: 'Auth', repo: 'https://github.com/acme/app' }),
        agent({ id: 'b', name: 'Other', repo: 'https://github.com/acme/web' })
      ];
      expect(applyInboxQuery(items, 'auth', 'all', 'name').length).assertEqual(1);
      expect(applyInboxQuery(items, 'web', 'all', 'name')[0].id).assertEqual('b');
      const mixed = [
        agent({ id: 'run', latestRunStatus: 'RUNNING', name: 'Live' }),
        agent({ id: 'err', latestRunStatus: 'ERROR', name: 'Boom' }),
        agent({ id: 'done', latestRunStatus: 'FINISHED', name: 'Ok' })
      ];
      expect(applyInboxQuery(mixed, '', 'error', 'name')[0].id).assertEqual('err');
      expect(applyInboxQuery(mixed, '', 'done', 'name')[0].id).assertEqual('done');
    });

    it('sorts by last user message newest first', 0, () => {
      const items = [
        agent({ id: 'old', latestRunStatus: 'FINISHED', lastUserAt: '2026-08-14T12:00:00.000Z' }),
        agent({ id: 'run', latestRunStatus: 'CREATING', lastUserAt: '2026-08-14T11:00:00.000Z' }),
        agent({ id: 'fresh', latestRunStatus: 'FINISHED', lastUserAt: '2026-08-16T09:00:00.000Z' })
      ];
      expect(applyInboxQuery(items, '', 'all', 'updated')[0].id).assertEqual('fresh');
      expect(applyInboxQuery(items, '', 'all', 'updated')[1].id).assertEqual('old');
    });

    it('recency uses lastUserAt, not a newer run updatedAt', 0, () => {
      const a = agent({
        id: 'mine',
        createdAt: '2026-08-10T12:00:00.000Z',
        updatedAt: '2026-08-16T18:00:00.000Z',
        lastUserAt: '2026-08-16T09:00:00.000Z'
      });
      const b = agent({
        id: 'theirs',
        createdAt: '2026-08-01T12:00:00.000Z',
        updatedAt: '2026-08-16T20:00:00.000Z',
        lastUserAt: '2026-08-15T12:00:00.000Z'
      });
      expect(recencyMs(a) > recencyMs(b)).assertTrue();
      expect(applyInboxQuery([b, a], '', 'all', 'updated')[0].id).assertEqual('mine');
    });

    it('recency falls back to createdAt when lastUserAt is missing', 0, () => {
      const a = agent({
        id: 'newer-create',
        createdAt: '2026-08-16T12:00:00.000Z',
        updatedAt: '2026-08-10T12:00:00.000Z'
      });
      const b = agent({
        id: 'old-create',
        createdAt: '2026-08-01T12:00:00.000Z',
        updatedAt: '2026-08-16T20:00:00.000Z'
      });
      expect(recencyMs(a) > recencyMs(b)).assertTrue();
      expect(applyInboxQuery([b, a], '', 'all', 'updated')[0].id).assertEqual('newer-create');
    });

    it('keeps recency inside repo groups', 0, () => {
      const items = applyInboxQuery([
        agent({
          id: 'older',
          repo: 'https://github.com/acme/app',
          lastUserAt: '2026-08-10T12:00:00.000Z'
        }),
        agent({
          id: 'newer',
          repo: 'https://github.com/acme/app',
          lastUserAt: '2026-08-16T12:00:00.000Z'
        })
      ], '', 'all', 'updated');
      const buckets = groupAgents(items, 'repo');
      expect(buckets[0].items[0].id).assertEqual('newer');
    });

    it('merges repo groups that differ only by case', 0, () => {
      const items = [
        agent({ id: 'a', repo: 'https://github.com/x/MyCloudSever' }),
        agent({ id: 'b', repo: 'https://github.com/x/mycloudsever.git' })
      ];
      const buckets = groupAgents(items, 'repo');
      expect(buckets.length).assertEqual(1);
      expect(buckets[0].key).assertEqual('x/mycloudsever');
      expect(buckets[0].items.length).assertEqual(2);
    });

    it('groups by status', 0, () => {
      const items = [
        agent({ id: 'a', latestRunStatus: 'ERROR' }),
        agent({ id: 'b', latestRunStatus: 'RUNNING' })
      ];
      const buckets = groupAgents(items, 'status');
      expect(buckets.length).assertEqual(2);
    });

    it('collects unique cloud env names newest first', 0, () => {
      const a = agent({ id: 'a' });
      a.env = { type: 'cloud', name: 'treeatetree/family-finance' };
      const b = agent({ id: 'b' });
      b.env = { type: 'cloud', name: 'treeatetree/mess' };
      const c = agent({ id: 'c' });
      c.env = { type: 'cloud', name: 'treeatetree/family-finance' };
      const d = agent({ id: 'd' });
      d.env = { type: 'cloud' };
      const e = agent({ id: 'e' });
      e.env = { type: 'pool', name: 'gpu' };
      const names = collectRecentEnvs([a, b, c, d, e], 8);
      expect(names.length).assertEqual(2);
      expect(names[0]).assertEqual('treeatetree/family-finance');
      expect(names[1]).assertEqual('treeatetree/mess');
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
          lastUserAt: '2026-08-10T12:00:00.000Z'
        }),
        agent({
          id: 'fresh',
          repo: 'https://github.com/acme/new',
          lastUserAt: '2026-08-16T12:00:00.000Z'
        })
      ];
      const buckets = groupAgents(items, 'repo');
      expect(buckets.length).assertEqual(2);
      expect(buckets[0].key).assertEqual('acme/new');
      expect(buckets[1].key).assertEqual('acme/old');
    });

    it('time groups stay today before older even if older is running', 0, () => {
      const items = applyInboxQuery([
        agent({
          id: 'old-run',
          latestRunStatus: 'RUNNING',
          lastUserAt: '2026-08-10T12:00:00.000Z'
        }),
        agent({
          id: 'today',
          latestRunStatus: 'FINISHED',
          lastUserAt: '2026-08-16T12:00:00.000Z'
        })
      ], '', 'all', 'updated');
      const buckets = groupAgents(items, 'time');
      expect(buckets[0].key).assertEqual('today');
      expect(buckets[0].items[0].id).assertEqual('today');
    });

    it('merge keeps local-only new cards and newer local updatedAt', 0, () => {
      const remote = [
        agent({ id: 'a', updatedAt: '2026-08-16T10:00:00.000Z' })
      ];
      const local = [
        agent({ id: 'a', updatedAt: '2026-08-16T12:00:00.000Z' }),
        agent({
          id: 'local-1',
          name: 'Seed',
          updatedAt: '2026-08-16T12:01:00.000Z',
          createdAt: '2026-08-16T12:01:00.000Z'
        })
      ];
      const now = Date.parse('2026-08-16T12:01:30.000Z');
      const out = mergeInboxLists(remote, local, ['local-1'], now);
      expect(out.length).assertEqual(2);
      expect(out[0].id).assertEqual('a');
      expect(out[0].updatedAt).assertEqual('2026-08-16T12:00:00.000Z');
      expect(out[1].id).assertEqual('local-1');
    });

    it('keeps local run id when list omits it, not status across runs', 0, () => {
      const remote = [
        agent({ id: 'a', updatedAt: '2026-08-16T12:00:00.000Z' })
      ];
      const local = [
        agent({
          id: 'a',
          latestRunStatus: 'RUNNING',
          updatedAt: '2026-08-16T12:00:00.000Z'
        })
      ];
      local[0].latestRunId = 'run-1';
      const out = mergeInboxLists(remote, local, [], Date.parse('2026-08-16T12:00:10.000Z'));
      expect(out[0].latestRunId).assertEqual('run-1');
      expect(out[0].latestRunStatus).assertEqual('RUNNING');
    });

    it('keeps newer local ARCHIVED when the list API is stale', 0, () => {
      const remote = [
        agent({ id: 'a', status: 'ACTIVE', updatedAt: '2026-08-16T12:00:00.000Z' })
      ];
      const local = [
        agent({ id: 'a', status: 'ARCHIVED', updatedAt: '2026-08-16T12:00:05.000Z' })
      ];
      const out = mergeInboxLists(remote, local, [], Date.parse('2026-08-16T12:00:10.000Z'));
      expect(out[0].status).assertEqual('ARCHIVED');
    });

    it('takes remote unarchive when remote updatedAt is newer', 0, () => {
      const remote = [
        agent({ id: 'a', status: 'ACTIVE', updatedAt: '2026-08-16T12:00:08.000Z' })
      ];
      const local = [
        agent({ id: 'a', status: 'ARCHIVED', updatedAt: '2026-08-16T12:00:01.000Z' })
      ];
      const out = mergeInboxLists(remote, local, [], Date.parse('2026-08-16T12:00:10.000Z'));
      expect(out[0].status).assertEqual('ACTIVE');
    });

    it('merge keeps the newer lastUserAt', 0, () => {
      const remote = [
        agent({ id: 'a', lastUserAt: '2026-08-16T10:00:00.000Z' })
      ];
      const local = [
        agent({ id: 'a', lastUserAt: '2026-08-16T12:00:00.000Z' })
      ];
      const out = mergeInboxLists(remote, local, [], Date.parse('2026-08-16T12:00:10.000Z'));
      expect(out[0].lastUserAt).assertEqual('2026-08-16T12:00:00.000Z');
    });

    it('keeps local in-flight follow-up when list still shows the old run', 0, () => {
      const remote = [
        agent({ id: 'a', lastUserAt: '2026-08-16T10:00:00.000Z', latestRunStatus: 'FINISHED' })
      ];
      remote[0].latestRunId = 'run-old';
      const local = [
        agent({ id: 'a', lastUserAt: '2026-08-16T12:00:00.000Z', latestRunStatus: 'CREATING' })
      ];
      local[0].latestRunId = 'run-new';
      const out = mergeInboxLists(remote, local, [], Date.parse('2026-08-16T12:00:10.000Z'));
      expect(out[0].latestRunId).assertEqual('run-new');
      expect(out[0].latestRunStatus).assertEqual('CREATING');
    });

    it('diffInboxAgents counts added and updated', 0, () => {
      const prev = [agent({ id: 'a', name: 'A', latestRunStatus: 'RUNNING' })];
      const next = [
        agent({ id: 'a', name: 'A', latestRunStatus: 'FINISHED' }),
        agent({ id: 'b', name: 'B', latestRunStatus: 'CREATING' })
      ];
      const d = diffInboxAgents(prev, next);
      expect(d.added).assertEqual(1);
      expect(d.updated).assertEqual(1);
      expect(inboxDeltaLabel(d).indexOf('更新') >= 0).assertTrue();
      expect(inboxDeltaLabel(diffInboxAgents(prev, prev))).assertEqual('已是最新');
    });
  });

  describe('WantParse', () => {
    it('reads agentId from parameters or uri', 0, () => {
      expect(agentIdFromLaunch({ agentId: 'bc-9' }, '')).assertEqual('bc-9');
      expect(agentIdFromLaunch(undefined, 'cursoragent://open/bc-8')).assertEqual('bc-8');
      expect(noticeTextFromLaunch({ noticeText: '已完成' })).assertEqual('');
      expect(showUnreadFromLaunch({ showUnread: '1' })).assertTrue();
      expect(showUnreadFromLaunch({ showUnread: 'true' })).assertTrue();
      expect(showUnreadFromLaunch(undefined)).assertFalse();
    });
  });

  describe('ApiUnwrap list', () => {
    it('fills updatedAt from createdAt when missing', 0, () => {
      const list = unwrapAgentsList({
        items: [{
          id: 'bc-1',
          name: 'Task',
          status: 'ACTIVE',
          url: '',
          createdAt: '2026-08-16T12:00:00.000Z',
          updatedAt: ''
        }]
      });
      const first = list.items ? list.items[0] : undefined;
      expect(first !== undefined).assertTrue();
      expect(first?.updatedAt).assertEqual('2026-08-16T12:00:00.000Z');
    });

    it('reads snake_case and nested latest run', 0, () => {
      const list = unwrapAgentsList({
        items: [{
          id: 'bc-2',
          name: 'Task',
          status: 'ACTIVE',
          url: '',
          created_at: '2026-08-16T12:00:00.000Z',
          latest_run_id: 'run-9',
          latest_run_status: 'FINISHED',
          latest_result: 'ok'
        }]
      });
      const first = list.items ? list.items[0] : undefined;
      expect(first?.latestRunId).assertEqual('run-9');
      expect(first?.latestRunStatus).assertEqual('FINISHED');
      expect(first?.latestResult).assertEqual('ok');
    });
  });

  describe('InboxGroupingRest', () => {
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

    it('puts archived cards in a trailing 归档 group', 0, () => {
      const items = [
        agent({ id: 'a', latestRunStatus: 'FINISHED', name: 'Live' }),
        agent({ id: 'b', status: 'ARCHIVED', name: 'Old' })
      ];
      const buckets = groupAgents(items, 'none');
      expect(buckets.length).assertEqual(2);
      expect(buckets[0].items[0].id).assertEqual('a');
      expect(buckets[1].key).assertEqual('archived');
      expect(buckets[1].label).assertEqual('归档');
      expect(buckets[1].items[0].id).assertEqual('b');
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

  describe('TimelineView', () => {
    it('keeps one process card and drops hidden tool rows', 0, () => {
      const items: TimelineItem[] = [
        { key: 'u', kind: 'userPrompt', runId: 'r1', text: 'hi' },
        { key: 'h', kind: 'runHeader', runId: 'r1' },
        { key: 't', kind: 'thinking', runId: 'r1', text: 'think' },
        { key: 'p', kind: 'progress', runId: 'r1', text: 'step' },
        { key: 'tool', kind: 'tool', runId: 'r1', text: 'read' },
        { key: 'a', kind: 'assistant', runId: 'r1', text: '## 结论' }
      ];
      const out = visibleTimeline(items);
      expect(out.length).assertEqual(3);
      expect(out[0].kind).assertEqual('userPrompt');
      expect(out[1].kind).assertEqual('thinking');
      expect(out[2].kind).assertEqual('assistant');
    });

    it('keeps a process card per run after follow-up', 0, () => {
      const items: TimelineItem[] = [
        { key: 'u1', kind: 'userPrompt', runId: 'r1', text: 'one' },
        { key: 't1', kind: 'thinking', runId: 'r1', text: 'old reason' },
        { key: 'a1', kind: 'assistant', runId: 'r1', text: 'done' },
        { key: 'u2', kind: 'userPrompt', runId: 'r2', text: 'two' },
        { key: 't2', kind: 'thinking', runId: 'r2', text: '', streaming: true }
      ];
      const out = visibleTimeline(items);
      expect(out.length).assertEqual(5);
      expect(out[1].key).assertEqual('t1');
      expect(out[4].key).assertEqual('t2');
      expect(isWaitingThink(out[4], false)).assertTrue();
    });

    it('keeps a trailing live wait after assistant', 0, () => {
      const items: TimelineItem[] = [
        { key: 'u', kind: 'userPrompt', runId: 'r1', text: 'hi' },
        { key: 't', kind: 'thinking', runId: 'r1', text: 'reason' },
        { key: 'a', kind: 'assistant', runId: 'r1', text: 'partial' },
        { key: 'waiting-r1', kind: 'thinking', runId: 'r1', text: '', streaming: true }
      ];
      const out = visibleTimeline(items);
      expect(out.length).assertEqual(4);
      expect(out[3].key).assertEqual('waiting-r1');
      expect(isWaitingThink(out[3], true)).assertTrue();
    });

    it('shows a turn divider from the second run', 0, () => {
      const items: TimelineItem[] = [
        { key: 'u1', kind: 'userPrompt', runId: 'r1', text: 'one' },
        { key: 'h1', kind: 'runHeader', runId: 'r1', text: '运行 · 已完成' },
        { key: 'a1', kind: 'assistant', runId: 'r1', text: 'done' },
        { key: 'h2', kind: 'runHeader', runId: 'r2', text: '运行 · 运行中' },
        { key: 'u2', kind: 'userPrompt', runId: 'r2', text: 'two' }
      ];
      const out = visibleTimeline(items);
      expect(out.length).assertEqual(4);
      expect(out[2].kind).assertEqual('runHeader');
      expect(out[2].runId).assertEqual('r2');
    });

    it('drops finished run headers so 运行/已完成 do not stack', 0, () => {
      const items: TimelineItem[] = [
        { key: 'u1', kind: 'userPrompt', runId: 'r1', text: 'one' },
        { key: 'a1', kind: 'assistant', runId: 'r1', text: 'done' },
        { key: 'h2', kind: 'runHeader', runId: 'r2', statusLabel: 'FINISHED', text: '运行 · 已完成' },
        { key: 'u2', kind: 'userPrompt', runId: 'r2', text: 'two' },
        { key: 'a2', kind: 'assistant', runId: 'r2', text: 'ok' }
      ];
      const out = visibleTimeline(items);
      expect(out.length).assertEqual(4);
      expect(out[0].kind).assertEqual('userPrompt');
      expect(out[1].kind).assertEqual('assistant');
      expect(out[2].kind).assertEqual('userPrompt');
      expect(out[3].kind).assertEqual('assistant');
    });

    it('drops hollow process cards when this device has no log', 0, () => {
      const items: TimelineItem[] = [
        { key: 'u', kind: 'userPrompt', runId: 'history', text: 'hi' },
        { key: 't', kind: 'thinking', runId: 'history', text: '', collapsed: true },
        { key: 'a', kind: 'assistant', runId: 'history', text: 'ok' }
      ];
      const out = visibleTimeline(items);
      expect(out.length).assertEqual(2);
      expect(out[0].kind).assertEqual('userPrompt');
      expect(out[1].kind).assertEqual('assistant');
    });

    it('first down from the latest message does not wrap to the first prompt', 0, () => {
      const keys = ['u0', 'u6'];
      const idxs = [0, 6];
      expect(nextUserJumpAt(keys, idxs, '', 1, 7, 10)).assertEqual(-1);
      expect(nextUserJumpAt(keys, idxs, '', -1, 7, 10)).assertEqual(0);
    });

    it('later taps move from the last jumped prompt', 0, () => {
      const keys = ['u0', 'u3', 'u6'];
      const idxs = [0, 3, 6];
      expect(nextUserJumpAt(keys, idxs, 'u6', -1, 7, 10)).assertEqual(1);
      expect(nextUserJumpAt(keys, idxs, 'u3', 1, 0, 4)).assertEqual(2);
      expect(nextUserJumpAt(keys, idxs, 'u0', -1, 0, 2)).assertEqual(-1);
    });

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

    it('visible key sig changes only when structure changes', 0, () => {
      const a: TimelineItem[] = [
        { key: 'u', kind: 'userPrompt', text: 'hi' },
        { key: 'a', kind: 'assistant', text: 'one', streaming: true }
      ];
      const b: TimelineItem[] = [
        { key: 'u', kind: 'userPrompt', text: 'hi' },
        { key: 'a', kind: 'assistant', text: 'one two', streaming: true }
      ];
      const c: TimelineItem[] = [
        { key: 'u', kind: 'userPrompt', text: 'hi' },
        { key: 'a', kind: 'assistant', text: 'one two', streaming: true },
        { key: 't', kind: 'thinking', text: '', streaming: true }
      ];
      expect(visibleKeySig(a)).assertEqual(visibleKeySig(b));
      expect(visibleKeySig(a) === visibleKeySig(c)).assertFalse();
      expect(visibleRowSig(a[1]) === visibleRowSig(b[1])).assertFalse();
    });
  });

  describe('StreamText summary', () => {
    it('uses the last non-empty message line for inbox preview', 0, () => {
      expect(lastTextSummary(['hello', '', 'line1\nDone here'])).assertEqual('Done here');
      expect(lastTextSummary(['', '  '])).assertEqual('');
    });
  });

  describe('TimelineMerge', () => {
    it('fingerprints conversation without unstable message ids', 0, () => {
      const a: ConversationMessage[] = [
        { id: 'uuid-1', type: 'user_message', text: 'Add a README' },
        { id: 'turn-0:step:12:assistant', type: 'assistant_message', text: 'Created README' }
      ];
      const b: ConversationMessage[] = [
        { id: 'uuid-CHANGED', type: 'user_message', text: 'Add a README' },
        { id: 'turn-0:step:99:assistant', type: 'assistant_message', text: 'Created README' }
      ];
      expect(convFingerprint(a)).assertEqual(convFingerprint(b));
      const c: ConversationMessage[] = [
        { id: 'uuid-1', type: 'user_message', text: 'Add a README' },
        { id: 'turn-0:step:12:assistant', type: 'assistant_message', text: 'Created README' },
        { id: 'uuid-2', type: 'user_message', text: 'Also add troubleshooting' }
      ];
      expect(convFingerprint(a) === convFingerprint(c)).assertFalse();
    });

    it('fingerprint changes when same-length text changes', 0, () => {
      const a: ConversationMessage[] = [
        { id: '1', type: 'user_message', text: 'AAAAAAAA' },
        { id: '2', type: 'assistant_message', text: 'BBBBBBBB' }
      ];
      const b: ConversationMessage[] = [
        { id: '1', type: 'user_message', text: 'AAAAAAAA' },
        { id: '2', type: 'assistant_message', text: 'CCCCCCCC' }
      ];
      expect(convFingerprint(a) === convFingerprint(b)).assertFalse();
    });

    it('fingerprint changes when last run id or stamp changes', 0, () => {
      const msgs: ConversationMessage[] = [
        { id: '1', type: 'user_message', text: 'Add a README', createdAt: '2026-08-01T00:00:00.000Z' },
        { id: '2', type: 'assistant_message', text: 'Created README', createdAt: '2026-08-01T00:01:00.000Z' }
      ];
      expect(convFingerprint(msgs, 'run-a', lastMessageStamp(msgs)) ===
        convFingerprint(msgs, 'run-b', lastMessageStamp(msgs))).assertFalse();
      expect(lastMessageStamp(msgs)).assertEqual('2026-08-01T00:01:00.000Z');
    });

    it('merge keeps tools when conversation fingerprint is unchanged', 0, () => {
      const conv: TimelineItem[] = [
        { key: 'u', kind: 'userPrompt', runId: 'history', text: 'hi' },
        { key: 'a', kind: 'assistant', runId: 'history', text: 'ok' }
      ];
      const cached: TimelineItem[] = [
        { key: 'tool1', kind: 'tool', runId: 'run-1', text: 'read_file' },
        { key: 'th', kind: 'thinking', runId: 'run-1', text: 'looking' }
      ];
      const first = mergeCachedActivity(conv, cached);
      const again = mergeCachedActivity(conv, first);
      let tools = 0;
      for (let i = 0; i < again.length; i++) {
        if (again[i].kind === 'tool') {
          tools += 1;
        }
      }
      expect(tools).assertEqual(1);
    });

    it('places SSE tools after the matching user turn', 0, () => {
      const conv: TimelineItem[] = [
        { key: 'u1', kind: 'userPrompt', runId: 'history', text: 'first' },
        { key: 'p1', kind: 'progress', runId: 'history', text: 'looking' },
        { key: 'a1', kind: 'assistant', runId: 'history', text: 'done one' },
        { key: 'u2', kind: 'userPrompt', runId: 'history', text: 'second' },
        { key: 'a2', kind: 'assistant', runId: 'history', text: 'done two' }
      ];
      const cached: TimelineItem[] = [
        { key: 't1', kind: 'thinking', runId: 'run-aaa', text: 'reason one' },
        { key: 'tool1', kind: 'tool', runId: 'run-aaa', text: 'read_file' },
        { key: 't2', kind: 'thinking', runId: 'run-bbb', text: 'reason two' }
      ];
      const merged = mergeCachedActivity(conv, cached);
      const kinds: string[] = [];
      const runs: string[] = [];
      for (let i = 0; i < merged.length; i++) {
        kinds.push(merged[i].kind);
        runs.push(merged[i].runId);
      }
      expect(kinds[0]).assertEqual('userPrompt');
      expect(kinds[1]).assertEqual('thinking');
      expect(runs[1]).assertEqual('run-aaa');
      expect(kinds[2]).assertEqual('tool');
      expect(kinds[kinds.length - 2]).assertEqual('thinking');
      expect(runs[kinds.length - 2]).assertEqual('run-bbb');
      expect(kinds[kinds.length - 1]).assertEqual('assistant');
      const vis = visibleTimeline(merged);
      expect(vis.length).assertEqual(6);
    });

    it('folds conversation progress into the single live run', 0, () => {
      const conv: TimelineItem[] = [
        { key: 'u', kind: 'userPrompt', runId: 'history', text: 'check git' },
        { key: 'p', kind: 'progress', runId: 'history', text: 'looking at commits' },
        { key: 'a', kind: 'assistant', runId: 'history', text: 'clean tree' }
      ];
      const cached: TimelineItem[] = [
        { key: 'th', kind: 'thinking', runId: 'run-live', text: 'checking log' },
        { key: 'tool', kind: 'tool', runId: 'run-live', text: 'git status' }
      ];
      const merged = mergeCachedActivity(conv, cached);
      const vis = visibleTimeline(merged);
      expect(vis.length).assertEqual(3);
      expect(vis[0].kind).assertEqual('userPrompt');
      expect(vis[1].runId).assertEqual('run-live');
      expect(vis[2].kind).assertEqual('assistant');
    });

    it('skips empty cached thinking', 0, () => {
      const conv: TimelineItem[] = [
        { key: 'u', kind: 'userPrompt', runId: 'history', text: 'hi' },
        { key: 'a', kind: 'assistant', runId: 'history', text: 'ok' }
      ];
      const cached: TimelineItem[] = [
        { key: 'empty', kind: 'thinking', runId: 'run-x', text: '' }
      ];
      const merged = mergeCachedActivity(conv, cached);
      expect(merged.length).assertEqual(2);
    });

    it('keeps streaming empty thinking as a waiting placeholder', 0, () => {
      const conv: TimelineItem[] = [
        { key: 'u', kind: 'userPrompt', runId: 'history', text: 'hi' },
        { key: 'a', kind: 'assistant', runId: 'history', text: 'ok' }
      ];
      const cached: TimelineItem[] = [
        { key: 'wait', kind: 'thinking', runId: 'run-x', text: '', streaming: true }
      ];
      const merged = mergeCachedActivity(conv, cached);
      expect(merged.length).assertEqual(3);
      expect(merged[1].streaming).assertEqual(true);
      expect(isWaitingThink(merged[1], false)).assertTrue();
    });

    it('keeps a local follow-up the conversation GET has not ingested', 0, () => {
      const conv: TimelineItem[] = [
        { key: 'u1', kind: 'userPrompt', runId: 'history', text: 'first' },
        { key: 'a1', kind: 'assistant', runId: 'history', text: 'done' }
      ];
      const live: TimelineItem[] = [
        { key: 'u1', kind: 'userPrompt', runId: 'history', text: 'first' },
        { key: 'a1', kind: 'assistant', runId: 'history', text: 'done' },
        { key: 'u2', kind: 'userPrompt', runId: 'pending', text: 'second' },
        { key: 't2', kind: 'thinking', runId: 'pending', text: '', streaming: true }
      ];
      const merged = keepPendingTurns(conv, live);
      expect(merged.length).assertEqual(4);
      expect(merged[2].kind).assertEqual('userPrompt');
      expect(merged[2].text).assertEqual('second');
      expect(merged[3].kind).assertEqual('thinking');
      expect(merged[3].streaming).assertEqual(true);
    });
  });

  describe('ModelSent', () => {
    it('merges model effort and fast into one chip', 0, () => {
      const effort: Record<string, Object> = {};
      effort['id'] = 'effort';
      effort['value'] = 'high';
      const fast: Record<string, Object> = {};
      fast['id'] = 'fast';
      fast['value'] = 'true';
      const params: Object[] = [];
      params.push(effort);
      params.push(fast);
      const model: Record<string, Object> = {};
      model['id'] = 'Composer 1.5';
      model['params'] = params;
      const tags = modelSentTags(model);
      expect(tags.length).assertEqual(1);
      expect(tags[0]).assertEqual('Composer 1.5 · high · fast');
      expect(formatModelSent(model)).assertEqual(tags[0]);
    });
  });

  describe('ModelVariants', () => {
    it('snaps 1m plus fast to a legal gpt-5.6-sol variant', 0, () => {
      const model = gpt56sol();
      const rows = buildParamRows(model);
      const fastIdx = rowIndex(rows, 'fast');
      const ctxIdx = rowIndex(rows, 'context');
      const reasonIdx = rowIndex(rows, 'reasoning');
      expect(fastIdx >= 0 && ctxIdx >= 0 && reasonIdx >= 0).assertTrue();
      rows[reasonIdx].selected = valueIndex(rows[reasonIdx], 'high');
      rows[fastIdx].selected = valueIndex(rows[fastIdx], 'true');
      const snapped = snapParamRows(model, rows, 'context', valueIndex(rows[ctxIdx], '1m'));
      const params = rowsToParams(snapped);
      expect(paramValue(params, 'context')).assertEqual('1m');
      expect(paramValue(params, 'reasoning')).assertEqual('high');
      expect(paramValue(params, 'fast')).assertEqual('false');
    });

    it('snaps fast on 1m back to 272k', 0, () => {
      const model = gpt56sol();
      const rows = buildParamRows(model);
      const fastIdx = rowIndex(rows, 'fast');
      const ctxIdx = rowIndex(rows, 'context');
      const reasonIdx = rowIndex(rows, 'reasoning');
      rows[reasonIdx].selected = valueIndex(rows[reasonIdx], 'high');
      rows[ctxIdx].selected = valueIndex(rows[ctxIdx], '1m');
      rows[fastIdx].selected = valueIndex(rows[fastIdx], 'false');
      const snapped = snapParamRows(model, rows, 'fast', valueIndex(rows[fastIdx], 'true'));
      const params = rowsToParams(snapped);
      expect(paramValue(params, 'fast')).assertEqual('true');
      expect(paramValue(params, 'context')).assertEqual('272k');
      expect(paramValue(params, 'reasoning')).assertEqual('high');
    });

    it('coerces illegal 1m+high+fast submit params', 0, () => {
      const model = gpt56sol();
      const illegal: ModelVariantParam[] = [
        { id: 'reasoning', value: 'high' },
        { id: 'fast', value: 'true' },
        { id: 'context', value: '1m' }
      ];
      const coerced = coerceParamsToVariant(model, illegal);
      expect(paramValue(coerced, 'context')).assertEqual('1m');
      expect(paramValue(coerced, 'reasoning')).assertEqual('high');
      expect(paramValue(coerced, 'fast')).assertEqual('false');
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

    it('parses a standalone markdown image as an image block', 0, () => {
      const blocks = parseMarkdown('![shot](https://cursor.com/a.png)\n\nsee above');
      expect(blocks[0].kind).assertEqual('image');
      expect(blocks[0].url).assertEqual('https://cursor.com/a.png');
      expect(blocks[0].text).assertEqual('shot');
    });

    it('clips notice without raw markdown', 0, () => {
      const s = clipNotice('## 结论\n修好了 [Inbox](https://example.com) 排序', 40);
      expect(s.indexOf('http') < 0).assertTrue();
      expect(s.indexOf('Inbox') >= 0).assertTrue();
    });

    it('treats chat_selection fences as citations', 0, () => {
      expect(isCitationFence('chat_selection')).assertTrue();
      expect(isCitationFence('ts')).assertFalse();
      const q = citationQuote(
        'agent_id: bc-89c5f128-4db7-4eee-b909-a520d790807c\nselected_text:\n这次 GitHub 鉴权失败，没能重新 fetch，以上是本地缓存。');
      expect(q).assertEqual('这次 GitHub 鉴权失败，没能重新 fetch，以上是本地缓存。');
      const blocks = parseMarkdown('```chat_selection\nagent_id: bc-1\nselected_text:\nhello\n```\n\n怎么处理');
      expect(blocks.length).assertEqual(2);
      expect(blocks[0].kind).assertEqual('code');
      expect(blocks[0].lang).assertEqual('chat_selection');
      expect(blocks[1].kind).assertEqual('text');
    });
  });

  describe('TimelineCopy', () => {
    it('slugs mcp and path tool names', 0, () => {
      expect(toolSlug('mcp_web_fetch')).assertEqual('web-fetch');
      expect(toolSlug('Read')).assertEqual('Read');
    });

    it('uses Cloud-shaped tool verbs', 0, () => {
      expect(usedToolLine('web-fetch', true, '')).assertEqual('正在用 web-fetch');
      expect(usedToolLine('web-fetch', false, 'notion.com')).assertEqual('用了 web-fetch · notion.com');
    });

    it('names live and done process cards', 0, () => {
      expect(processLiveTitle(true, '', false, '')).assertEqual('在准备环境');
      expect(processLiveTitle(false, 'web-fetch', true, '18s')).assertEqual('正在用 web-fetch · 18s');
      expect(processLiveTitle(false, '', false, '')).assertEqual('在想下一步');
      expect(processDoneTitle(false, '1s')).assertEqual('思考了 1s');
      expect(processDoneTitle(true, '1m 18s')).assertEqual('用了 1m 18s');
      expect(waitingThinkLabel(0)).assertEqual('在想下一步.');
      expect(waitingThinkLabel(1)).assertEqual('在想下一步..');
      expect(waitingThinkLabel(2)).assertEqual('在想下一步…');
    });

    it('keeps run headers as quiet verbs', 0, () => {
      expect(runHeaderVerb('CREATING', '')).assertEqual('在准备环境');
      expect(runHeaderVerb('RUNNING', '')).assertEqual('环境就绪');
      expect(runHeaderVerb('FINISHED', '1m 18s')).assertEqual('用了 1m 18s');
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

  describe('CachePolicy', () => {
    const finished = {
      detail: { latestRunId: 'run-1', latestRunStatus: 'FINISHED' },
      messages: [{}]
    };

    it('covers a settled Inbox row from local cache', 0, () => {
      expect(cacheCoversDetail(finished, 'run-1', 'FINISHED')).assertTrue();
      expect(cacheCoversConversation(finished, 'run-1')).assertTrue();
    });

    it('does not cover a newer Inbox run', 0, () => {
      expect(cacheCoversDetail(finished, 'run-2', 'FINISHED')).assertFalse();
      expect(cacheCoversConversation(finished, 'run-2')).assertFalse();
    });

    it('does not cover an in-flight Inbox row as a full detail hit', 0, () => {
      expect(cacheCoversDetail(finished, 'run-1', 'RUNNING')).assertFalse();
      expect(cacheCoversConversation(finished, 'run-1')).assertTrue();
    });

    it('needs an Inbox signal before treating disk as enough', 0, () => {
      expect(cacheCoversDetail(finished, '', '')).assertFalse();
    });

    it('does not cover a mid-run cache after Inbox has settled', 0, () => {
      const mid = {
        detail: { latestRunId: 'run-1', latestRunStatus: 'RUNNING' },
        messages: [{}]
      };
      expect(cacheCoversDetail(mid, 'run-1', 'FINISHED')).assertFalse();
    });
  });
}
