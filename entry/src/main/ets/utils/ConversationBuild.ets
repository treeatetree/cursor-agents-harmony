import { ConversationMessage } from '../models/Api';
import { TimelineItem } from '../models/Timeline';
import {
  agentPromptBody, ParsedTask, parseComposerProtocol, stripComposerWrapper,
  taskCardBody, taskCardTitle, taskFailed
} from './ConvProtocol';
import { extraImageUrls, imageUrlsFromMessage, pickMessageTime } from './TimelineMedia';
import { isProgressText } from './StreamText';
import { foldPlanItems } from './PlanDoc';

function isTaskResultCard(item: TimelineItem): boolean {
  if (item.kind !== 'subagent') {
    return false;
  }
  const s = item.statusLabel ?? '';
  return s === '子任务' || s.indexOf('子任务 ·') === 0;
}

function hasEarlierUserPrompt(items: TimelineItem[], before: number): boolean {
  for (let i = 0; i < before; i++) {
    if (items[i].kind === 'userPrompt') {
      return true;
    }
  }
  return false;
}

function isPromptCard(item: TimelineItem): boolean {
  if (item.kind !== 'subagent') {
    return false;
  }
  const s = item.statusLabel ?? '';
  return s === '子任务提示词' || s.indexOf('子任务提示词') === 0 || s.indexOf('提示词') === 0;
}

function attachPrompt(task: TimelineItem, raw: string): void {
  const prompt = agentPromptBody(raw);
  if (prompt.length === 0) {
    return;
  }
  if ((task.promptText ?? '').length === 0) {
    task.promptText = prompt;
  }
}

/**
 * Spawn briefs are the user/prompt turn immediately before a task-result card.
 * Keyword matching alone is not enough — wait until the next payload is a
 * subtask result, then nest the brief into that card.
 */
export function foldSpawnBeforeTaskResults(items: TimelineItem[]): TimelineItem[] {
  if (!items || items.length < 2) {
    return items;
  }
  const out: TimelineItem[] = [];
  for (let i = 0; i < items.length; i++) {
    out.push(items[i]);
  }
  let changed = false;
  for (let i = out.length - 1; i >= 1; i--) {
    if (!isTaskResultCard(out[i])) {
      continue;
    }
    let j = i - 1;
    while (j >= 0 && !isSpawnCandidate(out[j])) {
      j -= 1;
    }
    if (j < 0) {
      continue;
    }
    const src = out[j];
    if (src.kind === 'userPrompt' && !hasEarlierUserPrompt(out, j)) {
      continue;
    }
    attachPrompt(out[i], src.text ?? '');
    out.splice(j, 1);
    changed = true;
  }
  return changed ? out : items;
}

function isSpawnCandidate(item: TimelineItem): boolean {
  return item.kind === 'userPrompt' || isPromptCard(item);
}

/** Cached / SSE path: only fold when a task-result card follows. */
export function foldAgentWrittenPrompts(items: TimelineItem[]): TimelineItem[] {
  return foldSpawnBeforeTaskResults(items);
}

/** History transcript → timeline. Protocol / subagent turns are not user bubbles. */
export function conversationToTimeline(messages: ConversationMessage[]): TimelineItem[] {
  const items: TimelineItem[] = [];
  let assistantIdx = 0;
  let pendingShort: string[] = [];
  let pendingKey = '';

  const flushProgress = (): void => {
    if (pendingShort.length === 0) {
      return;
    }
    const joined = pendingShort.join('\n\n');
    items.push({
      key: `progress-${pendingKey}-${assistantIdx}`,
      kind: 'progress',
      runId: 'history',
      text: joined,
      collapsed: true,
      stepCount: pendingShort.length
    });
    assistantIdx++;
    pendingShort = [];
    pendingKey = '';
  };

  const flushAsAssistant = (): void => {
    if (pendingShort.length === 0) {
      return;
    }
    const joined = pendingShort.join('\n\n');
    items.push({
      key: `asst-${pendingKey}-${assistantIdx}`,
      kind: 'assistant',
      runId: 'history',
      text: joined
    });
    assistantIdx++;
    pendingShort = [];
    pendingKey = '';
  };

  const pushAssistant = (mid: string, raw: string, at: string, imgs: string[]): void => {
    const body = stripComposerWrapper(raw);
    if (body.length === 0 && imgs.length === 0) {
      return;
    }
    items.push({
      key: `asst-${mid}-${assistantIdx}`,
      kind: 'assistant',
      runId: 'history',
      text: body,
      localAt: at.length > 0 ? at : undefined,
      imageUrls: imgs.length > 0 ? imgs : undefined
    });
    assistantIdx++;
  };

  const pushUser = (mid: string, raw: string, at: string, imgs: string[]): void => {
    items.push({
      key: `user-${mid}`,
      kind: 'userPrompt',
      runId: 'history',
      text: raw,
      localAt: at.length > 0 ? at : undefined,
      imageUrls: imgs.length > 0 ? imgs : undefined
    });
  };

  const pushTasks = (mid: string, protoTasks: ParsedTask[], promptRaw: string): void => {
    for (let t = 0; t < protoTasks.length; t++) {
      const task = protoTasks[t];
      const body = taskCardBody(task);
      const title = taskCardTitle(task);
      if (title === '子任务' && body.length === 0) {
        continue;
      }
      const id = task.taskId.length > 0 ? task.taskId : `${mid}-${t}`;
      const row: TimelineItem = {
        key: `sub-${id}`,
        kind: 'subagent',
        runId: 'history',
        text: body,
        statusLabel: title,
        collapsed: true,
        failed: taskFailed(task),
        tool: {
          callId: id,
          name: 'task',
          status: 'completed',
          resultText: body.length > 0 ? body : undefined
        }
      };
      if (t === 0 && promptRaw.length > 0) {
        row.promptText = agentPromptBody(promptRaw);
      }
      items.push(row);
    }
  };

  for (let i = 0; i < messages.length; i++) {
    const m = messages[i];
    const text = (m.text ?? '').trim();
    const allImgs = imageUrlsFromMessage(m);
    const extraImgs = extraImageUrls(m);
    const at = pickMessageTime(m);
    if (text.length === 0 && allImgs.length === 0) {
      continue;
    }
    const mid = m.id && m.id.length > 0 ? m.id : `i${i}`;
    if (m.type === 'assistant_message') {
      const body = stripComposerWrapper(text);
      if (body.length === 0 && extraImgs.length === 0) {
        continue;
      }
      const last = i === messages.length - 1;
      if (isProgressText(body) && !last) {
        if (pendingKey.length === 0) {
          pendingKey = mid;
        }
        pendingShort.push(body);
      } else if (isProgressText(body) && last) {
        const hasAnswer = items.length > 0 && items[items.length - 1].kind === 'assistant';
        if (hasAnswer) {
          pendingShort.push(body);
          flushProgress();
        } else if (pendingShort.length > 0) {
          pendingShort.push(body);
          flushAsAssistant();
        } else {
          pushAssistant(mid, body, at, extraImgs);
        }
      } else {
        flushProgress();
        pushAssistant(mid, body, at, extraImgs);
      }
      continue;
    }
    const proto = parseComposerProtocol(text);
    if (proto.protocol) {
      flushAsAssistant();
      if (proto.userText.length > 0 || (allImgs.length > 0 && proto.tasks.length === 0)) {
        if (proto.tasks.length === 0) {
          pushUser(mid, proto.userText, at, allImgs);
        }
      }
      pushTasks(mid, proto.tasks, proto.tasks.length > 0 ? proto.userText : '');
      continue;
    }
    if (m.type === 'user_message') {
      flushAsAssistant();
      pushUser(mid, stripComposerWrapper(text), at, allImgs);
    }
  }
  flushAsAssistant();
  return foldPlanItems(foldSpawnBeforeTaskResults(items));
}
