import { describe, it, expect } from '@ohos/hypium';
import { AgentSummary } from '../main/ets/models/Api';
import { applyInboxQuery, diffInboxAgents, flattenCardFeed, flattenListFeed, groupAgents, inboxDeltaLabel } from '../main/ets/utils/InboxGrouping';

function sample(id: string, name: string, repo: string): AgentSummary {
  const row: AgentSummary = {
    id: id,
    name: name,
    status: 'ACTIVE',
    url: '',
    createdAt: '2026-08-01T00:00:00.000Z',
    updatedAt: '2026-08-01T00:00:00.000Z'
  };
  if (repo.length > 0) {
    row.repos = [{ url: repo }];
  }
  return row;
}

export default function inboxFeedTest() {
  describe('InboxFeed', () => {
    it('card feed keeps unlabeled items open and pairs cards', 0, () => {
      const items: AgentSummary[] = [
        sample('a', 'A', ''),
        sample('b', 'B', ''),
        sample('c', 'C', '')
      ];
      const rows = flattenCardFeed([], items, '');
      expect(rows.length).assertEqual(2);
      expect(rows[0].kind).assertEqual('pair');
      expect(rows[0].pair.hasRight).assertTrue();
      expect(rows[1].pair.hasRight).assertFalse();
      expect(rows[1].pair.left.id).assertEqual('c');
    });

    it('card feed accordion only expands the open labeled group', 0, () => {
      const items: AgentSummary[] = [
        sample('a', 'A', 'https://github.com/acme/app'),
        sample('b', 'B', 'https://github.com/acme/web')
      ];
      const buckets = groupAgents(items, 'repo');
      const closed = flattenCardFeed(buckets, [], '');
      expect(closed.length).assertEqual(buckets.length);
      expect(closed[0].kind).assertEqual('header');
      expect(closed[0].collapsed).assertTrue();
      const open = flattenCardFeed(buckets, [], buckets[0].key);
      expect(open.length).assertEqual(buckets.length + 1);
      expect(open[0].collapsed).assertFalse();
      expect(open[1].kind).assertEqual('pair');
    });

    it('list feed emits one row per agent when ungrouped', 0, () => {
      const items: AgentSummary[] = [
        sample('a', 'A', ''),
        sample('b', 'B', '')
      ];
      const rows = flattenListFeed([], items, '');
      expect(rows.length).assertEqual(2);
      expect(rows[0].kind).assertEqual('agent');
      expect(rows[1].agent.id).assertEqual('b');
    });

    it('filters error and done runs', 0, () => {
      const live = sample('run', 'Live', '');
      live.latestRunStatus = 'RUNNING';
      const boom = sample('err', 'Boom', '');
      boom.latestRunStatus = 'ERROR';
      const ok = sample('done', 'Ok', '');
      ok.latestRunStatus = 'FINISHED';
      const mixed: AgentSummary[] = [live, boom, ok];
      expect(applyInboxQuery(mixed, '', 'error', 'name')[0].id).assertEqual('err');
      expect(applyInboxQuery(mixed, '', 'done', 'name')[0].id).assertEqual('done');
    });

    it('diffInboxAgents counts added and updated', 0, () => {
      const prev: AgentSummary[] = [sample('a', 'A', '')];
      prev[0].latestRunStatus = 'RUNNING';
      const nextA = sample('a', 'A', '');
      nextA.latestRunStatus = 'FINISHED';
      const nextB = sample('b', 'B', '');
      nextB.latestRunStatus = 'CREATING';
      const next: AgentSummary[] = [nextA, nextB];
      const d = diffInboxAgents(prev, next);
      expect(d.added).assertEqual(1);
      expect(d.updated).assertEqual(1);
      expect(inboxDeltaLabel(d).indexOf('更新') >= 0).assertTrue();
      expect(inboxDeltaLabel(diffInboxAgents(prev, prev))).assertEqual('已是最新');
    });
  });
}
