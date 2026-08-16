import { describe, it, expect } from '@ohos/hypium';
import { unwrapAgentsList, unwrapCreateAgent, unwrapRun, unwrapAgentDetail } from '../main/ets/api/ApiUnwrap';

export default function apiUnwrapTest() {
  describe('ApiUnwrap', () => {
    it('unwrapAgentsList prefers items', 0, () => {
      const raw = {
        items: [{ id: 'bc-1', name: 'A', status: 'ACTIVE', url: '', createdAt: '', updatedAt: '' }],
        nextCursor: 'c1'
      };
      const out = unwrapAgentsList(raw);
      expect((out.items ?? []).length).assertEqual(1);
      expect(out.nextCursor).assertEqual('c1');
    });

    it('unwrapAgentsList falls back to agents', 0, () => {
      const raw = {
        agents: [{ id: 'bc-2', name: 'B', status: 'ACTIVE', url: '', createdAt: '', updatedAt: '' }]
      };
      const out = unwrapAgentsList(raw);
      expect((out.items ?? [])[0].id).assertEqual('bc-2');
    });

    it('unwrapRun nested run', 0, () => {
      const raw = {
        run: {
          id: 'run-1',
          agentId: 'bc-1',
          status: 'CREATING',
          createdAt: 't',
          updatedAt: 't'
        }
      };
      const run = unwrapRun(raw);
      expect(run.id).assertEqual('run-1');
    });

    it('unwrapCreateAgent keeps agent+run', 0, () => {
      const raw = {
        agent: { id: 'bc-9', name: 'N', status: 'ACTIVE', url: 'u', createdAt: '', updatedAt: '' },
        run: { id: 'run-9', agentId: 'bc-9', status: 'RUNNING', createdAt: '', updatedAt: '' }
      };
      const out = unwrapCreateAgent(raw);
      expect(out.agent?.id).assertEqual('bc-9');
      expect(out.run?.id).assertEqual('run-9');
    });

    it('unwrapAgentDetail accepts nested or bare agent', 0, () => {
      const nested = unwrapAgentDetail({
        agent: { id: 'bc-1', name: 'N', status: 'ACTIVE', url: 'u', createdAt: '', updatedAt: '' }
      });
      expect(nested.id).assertEqual('bc-1');
      const bare = unwrapAgentDetail({
        id: 'bc-2', name: 'M', status: 'ACTIVE', url: '', createdAt: '', updatedAt: ''
      });
      expect(bare.id).assertEqual('bc-2');
    });
  });
}
