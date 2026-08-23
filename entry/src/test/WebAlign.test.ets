import { describe, it, expect } from '@ohos/hypium';
import { gitCompareUrl, isOriginRepo, looksLikeRepoUrl, normalizeCreateRepoUrl, parseGitWeb } from '../main/ets/utils/GitLinks';
import { applyInboxQuery, collectRecentEnvs, diffInboxAgents, groupAgents, inboxDeltaLabel, mergeInboxLists, recencyMs, sortByRecency } from '../main/ets/utils/InboxGrouping';
import { unwrapAgentsList, unwrapArtifacts } from '../main/ets/api/ApiUnwrap';
import { agentIdFromLaunch, noticeTextFromLaunch, showUnreadFromLaunch } from '../main/ets/utils/WantParse';
import { citationQuote, clipNotice, isCitationFence, parseMarkdown, tokenizeInline } from '../main/ets/utils/MarkdownParse';
import { AgentSummary, ConversationMessage, ModelInfo, ModelParamValue, ModelVariant, ModelVariantParam } from '../main/ets/models/Api';
import { fileNameOf, isImagePath, isVideoPath } from '../main/ets/utils/DisplayFmt';
import { sniffMime } from '../main/ets/utils/ImagePicker';
import { isSubagentTool, lastTextSummary, subagentDetail } from '../main/ets/utils/StreamText';
import { unwrapUsageRuns } from '../main/ets/api/ApiUnwrap';
import { findUnreadAnchor, countNewContent, isWaitingThink, jumpCanFromIndex, nextUserJumpAt, visibleKeySig, visibleRowSig, visibleTimeline } from '../main/ets/utils/TimelineView';
import { processDoneTitle, processLiveTitle, runHeaderVerb, toolSlug, usedToolLine, waitingThinkLabel } from '../main/ets/utils/TimelineCopy';
import { convFingerprint, keepPendingTurns, lastMessageStamp, mergeCachedActivity } from '../main/ets/utils/TimelineMerge';
import { agentPromptBody, agentPromptTitle, isComposerProtocol, looksLikeAgentTaskPrompt, parseComposerProtocol, taskCardBody, taskCardTitle } from '../main/ets/utils/ConvProtocol';
import { conversationToTimeline, foldAgentWrittenPrompts } from '../main/ets/utils/ConversationBuild';
import {
  foldPlanItems, isPlanPath, isPlanToolEvent, keepFullToolArgs, looksLikePlanDoc, parsePlanDoc,
  planDocFromTool, planItemFromDoc, previewTodos, shortPlanPath, shouldMergePlans, titleFromPlanPath,
  weavePlans
} from '../main/ets/utils/PlanDoc';
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
      expect(nextUserJumpAt(keys, idxs, '', 1, 7, 10, true)).assertEqual(-1);
      expect(nextUserJumpAt(keys, idxs, '', -1, 7, 10, true)).assertEqual(0);
    });

    it('first up from a long assistant stays on the only prompt', 0, () => {
      const keys = ['u0'];
      const idxs = [0];
      expect(nextUserJumpAt(keys, idxs, '', -1, 1, 4)).assertEqual(-1);
      expect(nextUserJumpAt(keys, idxs, '', 1, 1, 4)).assertEqual(-1);
      expect(nextUserJumpAt(keys, idxs, 'u0', -1, 0, 2)).assertEqual(-1);
    });

    it('later taps move from the last jumped prompt', 0, () => {
      const keys = ['u0', 'u3', 'u6'];
      const idxs = [0, 3, 6];
      expect(nextUserJumpAt(keys, idxs, 'u6', -1, 7, 10)).assertEqual(1);
      expect(nextUserJumpAt(keys, idxs, 'u3', 1, 3, 6)).assertEqual(2);
      expect(nextUserJumpAt(keys, idxs, 'u0', -1, 0, 2)).assertEqual(-1);
    });

    it('disables jump at the first and last user prompts', 0, () => {
      // AgentDetailPage greys arrows from jumpCanFromIndex, not nextUserJumpAt.
      expect(jumpCanFromIndex(1, 4, -1)).assertFalse();
      expect(jumpCanFromIndex(1, 4, 1)).assertTrue();
      expect(jumpCanFromIndex(2, 4, -1)).assertTrue();
      expect(jumpCanFromIndex(2, 4, 1)).assertTrue();
      expect(jumpCanFromIndex(4, 4, 1)).assertFalse();
      expect(jumpCanFromIndex(4, 4, -1)).assertTrue();
      expect(jumpCanFromIndex(0, 4, -1)).assertFalse();
      expect(jumpCanFromIndex(1, 1, -1)).assertFalse();
      expect(jumpCanFromIndex(1, 1, 1)).assertFalse();
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
      expect(findUnreadAnchor(items, 'gone')).assertEqual('');
      expect(countNewContent(items, 'gone')).assertEqual(0);
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

    it('does not paste cached spawn prompts back as user bubbles', 0, () => {
      const spawnText = 'You are an explore agent. The parent agent needs a survey of listing pages.';
      const conv: TimelineItem[] = [
        { key: 'u1', kind: 'userPrompt', runId: 'history', text: '查上架风险' },
        { key: 'a1', kind: 'assistant', runId: 'history', text: '先派子任务。' },
        { key: 'p1', kind: 'subagent', runId: 'history', text: spawnText, statusLabel: '子任务提示词', collapsed: true }
      ];
      const live: TimelineItem[] = [
        { key: 'u1', kind: 'userPrompt', runId: 'history', text: '查上架风险' },
        { key: 'a1', kind: 'assistant', runId: 'history', text: '先派子任务。' },
        { key: 'u-spawn', kind: 'userPrompt', runId: 'history', text: spawnText }
      ];
      const merged = keepPendingTurns(conv, live);
      expect(merged.length).assertEqual(3);
      expect(merged[2].kind).assertEqual('subagent');
      const folded = foldAgentWrittenPrompts(live);
      expect(folded[2].kind).assertEqual('userPrompt');
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

    it('does not treat unmatched backticks or globs as styled english', 0, () => {
      const dangling = tokenizeInline('see Inbox `and more');
      let code = 0;
      let joined = '';
      for (let i = 0; i < dangling.length; i++) {
        if (dangling[i].code) {
          code += 1;
        }
        joined += dangling[i].text;
      }
      expect(code).assertEqual(0);
      expect(joined.indexOf('Inbox') >= 0).assertTrue();
      const glob = tokenizeInline('匹配 *.ets 文件');
      expect(glob.length).assertEqual(1);
      expect(glob[0].italic).assertFalse();
      expect(glob[0].text.indexOf('*.ets') >= 0).assertTrue();
    });
  });

  describe('ConvProtocol', () => {
    const TASK = [
      '<timestamp>Wednesday, Aug 19, 2026, 8:28 AM (UTC+8)</timestamp>',
      '<system_notification>',
      'The following task has finished. If you were already aware, ignore this notification and do not restate prior responses.',
      '</system_notification>',
      '<task>',
      'kind: subagent',
      'status: success',
      'task_id: 2db9ace2-7e65-4c17-b5f4-29a5baef5d0a',
      'title: 调查鸿蒙与替代渠道',
      'tool_call_id: call_pipT8xFnPd5url2DuQ7k7nw4',
      'detail: <user_visible_high_level_summary>',
      '未找到可核验的上架页。',
      '</user_visible_high_level_summary>',
      '<response>',
      '结论如下。',
      '</response>',
      '</task>'
    ].join('\n');

    it('detects composer protocol shells', 0, () => {
      expect(isComposerProtocol(TASK)).assertTrue();
      expect(isComposerProtocol('你看一下为啥 inbox 闪蓝')).assertFalse();
      const stamped = '<timestamp>Thursday, Aug 20, 2026, 8:12 AM (UTC+8)</timestamp>\n\n今天合入 4 笔。';
      expect(isComposerProtocol(stamped)).assertFalse();
    });

    it('pulls subagent title and body, drops the notification', 0, () => {
      const p = parseComposerProtocol(TASK);
      expect(p.protocol).assertTrue();
      expect(p.userText).assertEqual('');
      expect(p.tasks.length).assertEqual(1);
      expect(p.tasks[0].title).assertEqual('调查鸿蒙与替代渠道');
      expect(taskCardTitle(p.tasks[0])).assertEqual('子任务 · 调查鸿蒙与替代渠道');
      expect(taskCardBody(p.tasks[0]).indexOf('未找到可核验') >= 0).assertTrue();
      expect(taskCardBody(p.tasks[0]).indexOf('结论如下') >= 0).assertTrue();
    });

    it('keeps real text inside user_query', 0, () => {
      const p = parseComposerProtocol('<user_query>补一下隐私政策</user_query>');
      expect(p.protocol).assertTrue();
      expect(p.userText).assertEqual('补一下隐私政策');
      expect(p.tasks.length).assertEqual(0);
    });

    it('does not paint protocol as a user bubble', 0, () => {
      const items = conversationToTimeline([
        { id: 'u1', type: 'user_message', text: '查上架风险' },
        { id: 'a1', type: 'assistant_message', text: '先看公开文档。' },
        { id: 'n1', type: 'user_message', text: TASK }
      ]);
      const kinds: string[] = [];
      for (let i = 0; i < items.length; i++) {
        kinds.push(items[i].kind);
      }
      expect(kinds.indexOf('userPrompt') >= 0).assertTrue();
      expect(kinds.indexOf('subagent') >= 0).assertTrue();
      let users = 0;
      let subs = 0;
      for (let i = 0; i < items.length; i++) {
        if (items[i].kind === 'userPrompt') {
          users += 1;
          expect((items[i].text ?? '').indexOf('<task>') < 0).assertTrue();
        }
        if (items[i].kind === 'subagent') {
          subs += 1;
          expect(items[i].statusLabel ?? '').assertEqual('子任务 · 调查鸿蒙与替代渠道');
          expect(items[i].collapsed).assertEqual(true);
        }
      }
      expect(users).assertEqual(1);
      expect(subs).assertEqual(1);
    });

    it('folds agent-written subtask prompts into a card', 0, () => {
      const spawn = [
        '<timestamp>Wednesday, Aug 19, 2026, 8:00 AM (UTC+8)</timestamp>',
        '<user_query>',
        'You are an explore agent. The parent agent needs a survey of HarmonyOS listing pages.',
        'Your team\'s answer should list evidence URLs only.',
        '</user_query>'
      ].join('\n');
      expect(looksLikeAgentTaskPrompt(spawn)).assertTrue();
      expect(looksLikeAgentTaskPrompt('补一下隐私政策')).assertFalse();
      expect(agentPromptTitle(spawn).indexOf('子任务提示词') >= 0).assertTrue();
      expect(agentPromptBody(spawn).indexOf('explore agent') >= 0).assertTrue();
      const waiting = conversationToTimeline([
        { id: 'u1', type: 'user_message', text: '查上架风险' },
        { id: 'a1', type: 'assistant_message', text: '我先派一个子任务。' },
        { id: 'p1', type: 'user_message', text: spawn }
      ]);
      let waitingUsers = 0;
      for (let i = 0; i < waiting.length; i++) {
        if (waiting[i].kind === 'userPrompt') {
          waitingUsers += 1;
        }
      }
      expect(waitingUsers).assertEqual(2);
      const items = conversationToTimeline([
        { id: 'u1', type: 'user_message', text: '查上架风险' },
        { id: 'a1', type: 'assistant_message', text: '我先派一个子任务。' },
        { id: 'p1', type: 'user_message', text: spawn },
        { id: 'n1', type: 'user_message', text: TASK }
      ]);
      let users = 0;
      let nested = 0;
      for (let i = 0; i < items.length; i++) {
        if (items[i].kind === 'userPrompt') {
          users += 1;
          expect((items[i].text ?? '').indexOf('parent agent') < 0).assertTrue();
        }
        if ((items[i].promptText ?? '').indexOf('explore agent') >= 0) {
          nested += 1;
        }
      }
      expect(users).assertEqual(1);
      expect(nested).assertEqual(1);
    });

    it('recognizes role-assignment spawns without parent-agent boilerplate', 0, () => {
      const shell = 'You are a shell agent. Run the device tests and paste the failing case only.';
      expect(looksLikeAgentTaskPrompt(shell)).assertTrue();
      const inform = 'Briefly inform the user about the task result and perform any follow-up actions (if needed).';
      expect(looksLikeAgentTaskPrompt(inform)).assertTrue();
      expect(looksLikeAgentTaskPrompt('请帮我看一下 Inbox 刷新为什么会失败')).assertFalse();
    });

    it('folds the user message immediately before a task result', 0, () => {
      const spawn = '把 HarmonyOS 上架页和替代渠道都过一遍，只保留能点开的证据 URL。';
      expect(looksLikeAgentTaskPrompt(spawn)).assertFalse();
      const items = conversationToTimeline([
        { id: 'u1', type: 'user_message', text: '查上架风险' },
        { id: 'a1', type: 'assistant_message', text: '我先派一个子任务。' },
        { id: 'p1', type: 'user_message', text: spawn },
        { id: 'a2', type: 'assistant_message', text: '等子任务回来。' },
        { id: 'n1', type: 'user_message', text: TASK }
      ]);
      let users = 0;
      let nested = 0;
      let results = 0;
      for (let i = 0; i < items.length; i++) {
        if (items[i].kind === 'userPrompt') {
          users += 1;
          expect(items[i].text ?? '').assertEqual('查上架风险');
        }
        if (items[i].kind === 'subagent' && (items[i].statusLabel ?? '').indexOf('子任务 ·') === 0) {
          results += 1;
          if ((items[i].promptText ?? '').indexOf('HarmonyOS') >= 0) {
            nested += 1;
          }
        }
      }
      expect(users).assertEqual(1);
      expect(nested).assertEqual(1);
      expect(results).assertEqual(1);
    });

    it('does not fold the opening human turn just because a task follows', 0, () => {
      const items = conversationToTimeline([
        { id: 'u1', type: 'user_message', text: '查上架风险' },
        { id: 'a1', type: 'assistant_message', text: '先看公开文档。' },
        { id: 'n1', type: 'user_message', text: TASK }
      ]);
      let users = 0;
      for (let i = 0; i < items.length; i++) {
        if (items[i].kind === 'userPrompt') {
          users += 1;
          expect(items[i].text ?? '').assertEqual('查上架风险');
        }
      }
      expect(users).assertEqual(1);
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

  describe('PlanDoc', () => {
    const sample =
      '---\n' +
      'name: 鸿蒙商店上架准备\n' +
      'overview: 先解除品牌硬门槛，再补齐发布工程。\n' +
      'todos:\n' +
      '  - id: identity-model\n' +
      '    content: 锁定独立品牌、bundleName、Cursor 授权结论和 V1 收费模式\n' +
      '    status: pending\n' +
      '  - id: privacy-filing\n' +
      '    content: 完成数据清单、隐私/协议、跨境披露\n' +
      '    status: pending\n' +
      '  - id: release-engineering\n' +
      '    content: 创建 AGC 应用并补齐发布签名\n' +
      '    status: pending\n' +
      '  - id: store-assets\n' +
      '    content: 准备中英文商店文案\n' +
      '    status: pending\n' +
      'isProject: false\n' +
      '---\n\n' +
      '# 鸿蒙商店上架准备计划\n\n' +
      '## 当前结论\n';

    it('parses Cursor plan YAML', 0, () => {
      expect(looksLikePlanDoc(sample)).assertTrue();
      const doc = parsePlanDoc(sample, '/opt/cursor/.cursor/plans/鸿蒙商店上架准备_32f8dfe4.plan.md');
      expect(doc.name).assertEqual('鸿蒙商店上架准备');
      expect(doc.overview.indexOf('先解除品牌') >= 0).assertTrue();
      expect(doc.todos.length).assertEqual(4);
      expect(doc.todos[0].content.indexOf('锁定独立品牌') >= 0).assertTrue();
      expect(doc.body.indexOf('当前结论') >= 0).assertTrue();
    });

    it('shortens plan paths and titles', 0, () => {
      expect(isPlanPath('/opt/cursor/.cursor/plans/鸿蒙商店上架准备_32f8dfe4.plan.md')).assertTrue();
      expect(isPlanPath('README.md')).assertFalse();
      expect(isPlanPath('docs/explanation.md')).assertFalse();
      expect(isPlanPath('assets/airplane.md')).assertFalse();
      expect(isPlanPath('notes/game-plan.md')).assertFalse();
      expect(isPlanPath('/opt/cursor/artifacts/plans/store.md')).assertTrue();
      expect(shortPlanPath('/opt/cursor/.cursor/plans/鸿蒙商店上架准备_32f8dfe4.plan.md'))
        .assertEqual('.cursor/plans/鸿蒙商店上架准备_32f8dfe4.plan.md');
      expect(titleFromPlanPath('/opt/cursor/.cursor/plans/鸿蒙商店上架准备_32f8dfe4.plan.md'))
        .assertEqual('鸿蒙商店上架准备');
    });

    it('detects plan write tools by path', 0, () => {
      const args = '{"path":".cursor/plans/a_abc123.plan.md","contents":"# hi"}';
      expect(isPlanToolEvent('write', args)).assertTrue();
      expect(isPlanToolEvent('write', '{"path":"entry/src/main/ets/Index.ets"}')).assertFalse();
      expect(isPlanToolEvent('CreatePlan', '{"name":"x"}')).assertTrue();
    });

    it('does not treat a checklist answer as a plan', 0, () => {
      const list = '## 清单\n\n- [ ] 补隐私政策\n- [ ] 换包名\n- [ ] 做签名';
      expect(looksLikePlanDoc(list)).assertFalse();
      const items: TimelineItem[] = [
        { key: 'u', kind: 'userPrompt', runId: 'r1', text: '列清单' },
        { key: 'a', kind: 'assistant', runId: 'r1', text: list }
      ];
      const out = conversationToTimeline([
        { id: 'u', type: 'user_message', text: '列清单' },
        { id: 'a', type: 'assistant_message', text: list }
      ]);
      expect(out[1].kind).assertEqual('assistant');
      const folded = foldPlanItems(items);
      expect(folded[1].kind).assertEqual('assistant');
    });

    it('lifts YAML assistant text and plan writes into one card', 0, () => {
      const conv = conversationToTimeline([
        { id: 'u', type: 'user_message', text: '梳理上架' },
        { id: 'a', type: 'assistant_message', text: sample }
      ]);
      expect(conv[1].kind).assertEqual('plan');
      expect(conv[1].statusLabel).assertEqual('鸿蒙商店上架准备');
      expect((conv[1].stepCount ?? 0) >= 3).assertTrue();
      const vis = visibleTimeline(conv);
      expect(vis[1].kind).assertEqual('plan');

      const tools: TimelineItem[] = [
        { key: 'u', kind: 'userPrompt', runId: 'r1', text: '梳理上架' },
        {
          key: 'tool-1',
          kind: 'tool',
          runId: 'r1',
          text: '用了 write',
          tool: {
            callId: 'c1',
            name: 'write',
            status: 'completed',
            argsText: '{"path":".cursor/plans/鸿蒙商店上架准备_32f8dfe4.plan.md","contents":' +
              JSON.stringify(sample) + '}'
          }
        },
        { key: 'think', kind: 'thinking', runId: 'r1', text: '在写计划' }
      ];
      const folded = foldPlanItems(tools);
      let plans = 0;
      let writes = 0;
      for (let i = 0; i < folded.length; i++) {
        if (folded[i].kind === 'plan') {
          plans += 1;
        }
        if (folded[i].kind === 'tool') {
          writes += 1;
        }
      }
      expect(plans).assertEqual(1);
      expect(writes).assertEqual(0);
      expect(previewTodos(parsePlanDoc(sample).todos).length).assertEqual(3);

      const mixed: TimelineItem[] = [
        { key: 'u', kind: 'userPrompt', runId: 'history', text: '梳理上架' },
        {
          key: 'a',
          kind: 'plan',
          runId: 'history',
          text: sample,
          statusLabel: '鸿蒙商店上架准备',
          promptText: '先解除品牌硬门槛',
          collapsed: true
        },
        {
          key: 'plan-run-c1',
          kind: 'plan',
          runId: 'run-1',
          text: sample,
          usageShort: '.cursor/plans/鸿蒙商店上架准备_32f8dfe4.plan.md',
          collapsed: true
        }
      ];
      const one = foldPlanItems(mixed);
      let mixedPlans = 0;
      for (let i = 0; i < one.length; i++) {
        if (one[i].kind === 'plan') {
          mixedPlans += 1;
        }
      }
      expect(mixedPlans).assertEqual(1);
      expect(one[1].usageShort ?? '').assertEqual('.cursor/plans/鸿蒙商店上架准备_32f8dfe4.plan.md');
    });

    it('reads CreatePlan args and artifacts paths', 0, () => {
      expect(isPlanPath('file:///opt/cursor/artifacts/plans/plan_4713bad5.plan.md')).assertTrue();
      expect(shortPlanPath('file:///opt/cursor/artifacts/plans/plan_4713bad5.plan.md'))
        .assertEqual('plans/plan_4713bad5.plan.md');
      expect(titleFromPlanPath('file:///opt/cursor/artifacts/plans/plan_4713bad5.plan.md'))
        .assertEqual('plan_4713bad5');
      const args = JSON.stringify({
        name: '核心上架任务',
        overview: '先把商店资料凑齐',
        todos: [
          { content: '补隐私政策', status: 'pending' },
          { content: '换包名', status: 'pending' },
          { content: '做签名', status: 'pending' }
        ],
        plan: '## 核心任务\n\n先过审核。'
      });
      expect(keepFullToolArgs('CreatePlan', args)).assertTrue();
      const listed = unwrapArtifacts({
        items: [{ path: 'file:///opt/cursor/artifacts/plans/plan_4713bad5.plan.md', sizeBytes: 1200 }]
      });
      expect(listed.length).assertEqual(1);
      expect(listed[0].path).assertEqual('file:///opt/cursor/artifacts/plans/plan_4713bad5.plan.md');
      const asArr = unwrapArtifacts([
        { path: '.cursor/plans/store.plan.md', size: 800 }
      ] as object);
      expect(asArr.length).assertEqual(1);
      expect(asArr[0].path).assertEqual('.cursor/plans/store.plan.md');
      const doc = planDocFromTool({
        callId: 'c2',
        name: 'CreatePlan',
        status: 'completed',
        argsText: args,
        resultText: JSON.stringify({ path: 'file:///opt/cursor/artifacts/plans/plan_4713bad5.plan.md' })
      });
      expect(doc.name).assertEqual('核心上架任务');
      expect(doc.todos.length).assertEqual(3);
      expect(doc.overview.indexOf('商店') >= 0).assertTrue();
      expect(doc.path.indexOf('plan_4713bad5') >= 0).assertTrue();
      expect(doc.body.indexOf('核心任务') >= 0).assertTrue();
    });

    it('merges the same plan path in one turn', 0, () => {
      const first: TimelineItem = {
        key: 'p1',
        kind: 'plan',
        runId: 'r1',
        text: sample,
        statusLabel: '鸿蒙商店上架准备'
      };
      const second: TimelineItem = {
        key: 'p2',
        kind: 'plan',
        runId: 'r1',
        text: sample,
        usageShort: '.cursor/plans/鸿蒙商店上架准备_32f8dfe4.plan.md'
      };
      const folded = foldPlanItems([
        { key: 'u1', kind: 'userPrompt', runId: 'r1', text: '梳理' },
        first,
        second
      ]);
      let n = 0;
      for (let i = 0; i < folded.length; i++) {
        if (folded[i].kind === 'plan') {
          n += 1;
        }
      }
      expect(n).assertEqual(1);
      expect(folded[1].usageShort ?? '').assertEqual('.cursor/plans/鸿蒙商店上架准备_32f8dfe4.plan.md');
    });

    it('keeps two different plans in the same turn', 0, () => {
      const first: TimelineItem = {
        key: 'p1',
        kind: 'plan',
        runId: 'r1',
        text: sample,
        statusLabel: '鸿蒙商店上架准备',
        usageShort: '.cursor/plans/鸿蒙商店上架准备_32f8dfe4.plan.md'
      };
      const second: TimelineItem = {
        key: 'p2',
        kind: 'plan',
        runId: 'r1',
        text: '---\nname: 核心上架任务\noverview: 先过审核\ntodos:\n  - id: t-0\n    content: 补隐私政策\n    status: pending\n---\n\n# 核心',
        statusLabel: '核心上架任务',
        usageShort: 'plans/plan_4713bad5.plan.md'
      };
      const folded = foldPlanItems([
        { key: 'u1', kind: 'userPrompt', runId: 'r1', text: '梳理' },
        first,
        second
      ]);
      let n = 0;
      for (let i = 0; i < folded.length; i++) {
        if (folded[i].kind === 'plan') {
          n += 1;
        }
      }
      expect(n).assertEqual(2);
    });

    it('keeps two plans from different turns', 0, () => {
      const first: TimelineItem = {
        key: 'p1',
        kind: 'plan',
        runId: 'r1',
        text: sample,
        statusLabel: '鸿蒙商店上架准备',
        usageShort: '.cursor/plans/鸿蒙商店上架准备_32f8dfe4.plan.md'
      };
      const second: TimelineItem = {
        key: 'p2',
        kind: 'plan',
        runId: 'r1',
        text: '---\nname: 核心上架任务\noverview: 先过审核\ntodos:\n  - id: t-0\n    content: 补隐私政策\n    status: pending\n---\n\n# 核心',
        statusLabel: '核心上架任务',
        usageShort: 'plans/plan_4713bad5.plan.md'
      };
      expect(shouldMergePlans(first, second)).assertFalse();
      const folded = foldPlanItems([
        { key: 'u1', kind: 'userPrompt', runId: 'r1', text: '梳理' },
        first,
        { key: 'u2', kind: 'userPrompt', runId: 'r1', text: '核心任务' },
        second
      ]);
      let n = 0;
      for (let i = 0; i < folded.length; i++) {
        if (folded[i].kind === 'plan') {
          n += 1;
        }
      }
      expect(n).assertEqual(2);
    });

    it('weaves artifact plans after each user turn', 0, () => {
      const conv: TimelineItem[] = [
        { key: 'u1', kind: 'userPrompt', runId: 'history', text: '梳理' },
        { key: 'a1', kind: 'assistant', runId: 'history', text: '先看品牌' },
        { key: 'u2', kind: 'userPrompt', runId: 'history', text: '核心任务' },
        { key: 'a2', kind: 'assistant', runId: 'history', text: '三条' }
      ];
      const p1 = planItemFromDoc('plan-art-1', 'history', parsePlanDoc(sample,
        '.cursor/plans/鸿蒙商店上架准备_32f8dfe4.plan.md'));
      const p2 = planItemFromDoc('plan-art-2', 'history', parsePlanDoc(
        '---\nname: 核心上架任务\noverview: 先过审核\ntodos:\n  - id: t-0\n    content: 补隐私政策\n    status: pending\n---\n\n# 核心',
        'plans/plan_4713bad5.plan.md'));
      const out = weavePlans(conv, [p1, p2]);
      expect(out[2].kind).assertEqual('plan');
      expect(out[2].statusLabel).assertEqual('鸿蒙商店上架准备');
      expect(out[1].kind).assertEqual('assistant');
      expect(out[5].kind).assertEqual('plan');
      expect(out[5].statusLabel).assertEqual('核心上架任务');
      expect(out[4].kind).assertEqual('assistant');
    });

    it('weaves a single artifact plan after the last turn', 0, () => {
      const conv: TimelineItem[] = [
        { key: 'u1', kind: 'userPrompt', runId: 'history', text: '梳理' },
        { key: 'a1', kind: 'assistant', runId: 'history', text: '先看品牌' },
        { key: 'u2', kind: 'userPrompt', runId: 'history', text: '核心任务' },
        { key: 'a2', kind: 'assistant', runId: 'history', text: '三条' }
      ];
      const p2 = planItemFromDoc('plan-art-2', 'history', parsePlanDoc(
        '---\nname: 核心上架任务\noverview: 先过审核\ntodos:\n  - id: t-0\n    content: 补隐私政策\n    status: pending\n---\n\n# 核心',
        'plans/plan_4713bad5.plan.md'));
      const out = weavePlans(conv, [p2]);
      expect(out[4].kind).assertEqual('plan');
      expect(out[4].statusLabel).assertEqual('核心上架任务');
      expect(out[3].kind).assertEqual('assistant');
    });

    it('keeps an empty cached plan across conversation rebuild', 0, () => {
      const conv: TimelineItem[] = [
        { key: 'u', kind: 'userPrompt', runId: 'history', text: '梳理' },
        { key: 'a', kind: 'assistant', runId: 'history', text: '先看品牌' }
      ];
      const cached: TimelineItem[] = [
        { key: 'plan-1', kind: 'plan', runId: 'run-1', text: '', statusLabel: '计划' }
      ];
      const merged = mergeCachedActivity(conv, cached);
      let plans = 0;
      for (let i = 0; i < merged.length; i++) {
        if (merged[i].kind === 'plan') {
          plans += 1;
        }
      }
      expect(plans).assertEqual(1);
    });
  });
}
