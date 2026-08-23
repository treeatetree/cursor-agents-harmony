import { describe, it, expect } from '@ohos/hypium';
import { ConversationMessage } from '../main/ets/models/Api';
import { TimelineItem } from '../main/ets/models/Timeline';
import {
  agentPromptTitle, isComposerProtocol, looksLikeAgentTaskPrompt, stripComposerWrapper
} from '../main/ets/utils/ConvProtocol';
import { conversationToTimeline, foldAgentWrittenPrompts } from '../main/ets/utils/ConversationBuild';
import { keepPendingTurns } from '../main/ets/utils/TimelineMerge';
import { visibleTimeline } from '../main/ets/utils/TimelineView';
import { foldPlanItems, isPlanToolEvent, looksLikePlanDoc, parsePlanDoc } from '../main/ets/utils/PlanDoc';
import { ToolCallEvent } from '../main/ets/models/Sse';

function msg(id: string, type: string, text: string): ConversationMessage {
  const row: ConversationMessage = {
    id: id,
    type: type,
    text: text
  };
  return row;
}

function item(key: string, kind: 'userPrompt' | 'assistant' | 'subagent', text: string): TimelineItem {
  const row: TimelineItem = {
    key: key,
    kind: kind,
    runId: 'history',
    text: text
  };
  return row;
}

const TASK = [
  '<timestamp>Wednesday, Aug 19, 2026, 8:28 AM (UTC+8)</timestamp>',
  '<task>',
  'kind: subagent',
  'status: success',
  'task_id: t-1',
  'title: 调查鸿蒙与替代渠道',
  '</task>'
].join('\n');

export default function convProtocolTest() {
  describe('ConvProtocolDevice', () => {
    it('timestamp alone is chrome, not composer protocol', 0, () => {
      const wrapped = [
        '<timestamp>Thursday, Aug 20, 2026, 8:12 AM (UTC+8)</timestamp>',
        '',
        '今天仓库主线合入 4 笔。'
      ].join('\n');
      expect(isComposerProtocol(wrapped)).assertFalse();
      expect(isComposerProtocol(TASK)).assertTrue();
      expect(stripComposerWrapper(wrapped).indexOf('今天仓库') >= 0).assertTrue();
      expect(stripComposerWrapper(wrapped).indexOf('<timestamp>') < 0).assertTrue();
    });

    it('assistant finals with timestamp stay assistant bubbles', 0, () => {
      const answer = [
        '<timestamp>Thursday, Aug 20, 2026, 8:12 AM (UTC+8)</timestamp>',
        '',
        '今天（8 月 19 日）仓库主线合入 **4 笔**。'
      ].join('\n');
      const items = conversationToTimeline([
        msg('u1', 'user_message', '核对一下晚间分支里过程卡和图标的改动，避免模块归类偏差。'),
        msg('a1', 'assistant_message', answer)
      ]);
      expect(items.length).assertEqual(2);
      expect(items[0].kind).assertEqual('userPrompt');
      expect(items[1].kind).assertEqual('assistant');
      expect((items[1].text ?? '').indexOf('仓库主线合入') >= 0).assertTrue();
      expect((items[1].text ?? '').indexOf('<timestamp>') < 0).assertTrue();
    });

    it('does not fold a spawn-looking user turn until a task result follows', 0, () => {
      const spawn = 'You are an explore agent. The parent agent needs a survey of HarmonyOS listing pages.';
      expect(looksLikeAgentTaskPrompt(spawn)).assertTrue();
      expect(looksLikeAgentTaskPrompt('补一下隐私政策')).assertFalse();
      const items = conversationToTimeline([
        msg('u1', 'user_message', '查上架风险'),
        msg('a1', 'assistant_message', '我先派一个子任务。'),
        msg('p1', 'user_message', spawn)
      ]);
      let users = 0;
      let prompts = 0;
      for (let i = 0; i < items.length; i++) {
        if (items[i].kind === 'userPrompt') {
          users += 1;
        }
        if (items[i].kind === 'subagent' && (items[i].statusLabel ?? '').indexOf('子任务提示词') >= 0) {
          prompts += 1;
        }
      }
      expect(users).assertEqual(2);
      expect(prompts).assertEqual(0);
      expect(agentPromptTitle(spawn).indexOf('子任务提示词') >= 0).assertTrue();
    });

    it('does not restore cached spawn bubbles after conversation rebuild', 0, () => {
      const spawn = 'You are an explore agent. The parent agent needs a survey of listing pages.';
      const conv: TimelineItem[] = [
        item('u1', 'userPrompt', '查上架风险'),
        item('a1', 'assistant', '先派子任务。'),
        item('p1', 'subagent', spawn)
      ];
      conv[2].statusLabel = '子任务提示词';
      conv[2].collapsed = true;
      const live: TimelineItem[] = [
        item('u1', 'userPrompt', '查上架风险'),
        item('a1', 'assistant', '先派子任务。'),
        item('u-spawn', 'userPrompt', spawn)
      ];
      const merged = keepPendingTurns(conv, live);
      expect(merged.length).assertEqual(3);
      expect(merged[2].kind).assertEqual('subagent');
    });

    it('folds the user turn immediately before a task-result card', 0, () => {
      const spawn = '把 HarmonyOS 上架页和替代渠道都过一遍，只保留能点开的证据 URL。';
      const messages: ConversationMessage[] = [
        msg('u1', 'user_message', '查上架风险'),
        msg('a1', 'assistant_message', '我先派一个子任务。'),
        msg('p1', 'user_message', spawn),
        msg('n1', 'user_message', TASK)
      ];
      const items = conversationToTimeline(messages);
      let users = 0;
      let nested = 0;
      for (let i = 0; i < items.length; i++) {
        if (items[i].kind === 'userPrompt') {
          users += 1;
          expect(items[i].text ?? '').assertEqual('查上架风险');
        }
        if (items[i].kind === 'subagent' && (items[i].promptText ?? '').indexOf('HarmonyOS') >= 0) {
          nested += 1;
        }
      }
      expect(users).assertEqual(1);
      expect(nested).assertEqual(1);
    });

    it('cached spawn bubbles only fold once a task-result card exists', 0, () => {
      const spawn = 'You are an explore agent. The parent agent needs a survey of listing pages.';
      const live: TimelineItem[] = [
        item('u1', 'userPrompt', '查上架风险'),
        item('a1', 'assistant', '先派子任务。'),
        item('u-spawn', 'userPrompt', spawn)
      ];
      const waiting = foldAgentWrittenPrompts(live);
      expect(waiting[2].kind).assertEqual('userPrompt');
      const task = item('sub-1', 'subagent', '未找到可核验的上架页。');
      task.statusLabel = '子任务 · 调查鸿蒙与替代渠道';
      live.push(task);
      const folded = foldAgentWrittenPrompts(live);
      let nested = 0;
      let users = 0;
      for (let i = 0; i < folded.length; i++) {
        if (folded[i].kind === 'userPrompt') {
          users += 1;
        }
        if ((folded[i].promptText ?? '').indexOf('explore agent') >= 0) {
          nested += 1;
        }
      }
      expect(users).assertEqual(1);
      expect(nested).assertEqual(1);
    });

    it('does not paste a cached assistant answer back as a user bubble', 0, () => {
      const answer = '今天（8 月 19 日）仓库主线合入 **4 笔**。';
      const conv: TimelineItem[] = [
        item('u1', 'userPrompt', '核对一下晚间分支'),
        item('a1', 'assistant', answer)
      ];
      const live: TimelineItem[] = [
        item('u1', 'userPrompt', '核对一下晚间分支'),
        item('u-fake', 'userPrompt', answer)
      ];
      const merged = keepPendingTurns(conv, live);
      expect(merged.length).assertEqual(2);
      expect(merged[1].kind).assertEqual('assistant');
    });

    it('lifts YAML plan docs and hides the write tool', 0, () => {
      const sample = [
        '---',
        'name: 鸿蒙商店上架准备',
        'overview: 先解除品牌硬门槛。',
        'todos:',
        '  - id: identity-model',
        '    content: 锁定独立品牌',
        '    status: pending',
        '  - id: privacy-filing',
        '    content: 完成数据清单',
        '    status: pending',
        '---',
        '',
        '# 正文'
      ].join('\n');
      expect(looksLikePlanDoc(sample)).assertTrue();
      expect(looksLikePlanDoc('- [ ] 补隐私政策\n- [ ] 换包名')).assertFalse();
      expect(parsePlanDoc(sample).todos.length).assertEqual(2);
      const conv = conversationToTimeline([
        msg('u1', 'user_message', '梳理上架'),
        msg('a1', 'assistant_message', sample)
      ]);
      expect(conv[1].kind).assertEqual('plan');
      expect(visibleTimeline(conv)[1].kind).assertEqual('plan');

      const write: ToolCallEvent = {
        callId: 'c1',
        name: 'write',
        status: 'completed',
        argsText: '{"path":".cursor/plans/a_abc123.plan.md","contents":"# hi"}'
      };
      expect(isPlanToolEvent(write.name, write.argsText ?? '')).assertTrue();
      const toolRow: TimelineItem = {
        key: 'tool-1',
        kind: 'tool',
        runId: 'r1',
        text: '用了 write',
        tool: write
      };
      const userRow: TimelineItem = {
        key: 'u',
        kind: 'userPrompt',
        runId: 'r1',
        text: '梳理上架'
      };
      const folded = foldPlanItems([userRow, toolRow]);
      expect(folded[1].kind).assertEqual('plan');
      let writes = 0;
      for (let i = 0; i < folded.length; i++) {
        if (folded[i].kind === 'tool') {
          writes += 1;
        }
      }
      expect(writes).assertEqual(0);
    });
  });
}
