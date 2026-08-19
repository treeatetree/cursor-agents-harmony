import { ConversationMessage } from '../models/Api';
import { TimelineItem } from '../models/Timeline';
import { ParsedTask, parseComposerProtocol, taskCardBody, taskCardTitle, taskFailed } from './ConvProtocol';
import { extraImageUrls, imageUrlsFromMessage, pickMessageTime } from './TimelineMedia';
import { isProgressText } from './StreamText';

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

  const pushTasks = (mid: string, protoTasks: ParsedTask[]): void => {
    for (let t = 0; t < protoTasks.length; t++) {
      const task = protoTasks[t];
      const body = taskCardBody(task);
      const title = taskCardTitle(task);
      if (title === '子任务' && body.length === 0) {
        continue;
      }
      const id = task.taskId.length > 0 ? task.taskId : `${mid}-${t}`;
      items.push({
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
      });
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
    const proto = parseComposerProtocol(text);
    if (proto.protocol) {
      if (m.type === 'user_message') {
        flushAsAssistant();
      } else {
        flushProgress();
      }
      if (proto.userText.length > 0 || (m.type === 'user_message' && allImgs.length > 0 && proto.tasks.length === 0)) {
        items.push({
          key: `user-${mid}`,
          kind: 'userPrompt',
          runId: 'history',
          text: proto.userText,
          localAt: at.length > 0 ? at : undefined,
          imageUrls: allImgs.length > 0 ? allImgs : undefined
        });
      }
      pushTasks(mid, proto.tasks);
      continue;
    }
    if (m.type === 'user_message') {
      flushAsAssistant();
      items.push({
        key: `user-${mid}`,
        kind: 'userPrompt',
        runId: 'history',
        text: text,
        localAt: at.length > 0 ? at : undefined,
        imageUrls: allImgs.length > 0 ? allImgs : undefined
      });
    } else if (m.type === 'assistant_message') {
      const last = i === messages.length - 1;
      if (isProgressText(text) && !last) {
        if (pendingKey.length === 0) {
          pendingKey = mid;
        }
        pendingShort.push(text);
      } else if (isProgressText(text) && last) {
        const hasAnswer = items.length > 0 && items[items.length - 1].kind === 'assistant';
        if (hasAnswer) {
          pendingShort.push(text);
          flushProgress();
        } else if (pendingShort.length > 0) {
          pendingShort.push(text);
          flushAsAssistant();
        } else {
          items.push({
            key: `asst-${mid}-${assistantIdx}`,
            kind: 'assistant',
            runId: 'history',
            text: text,
            localAt: at.length > 0 ? at : undefined,
            imageUrls: extraImgs.length > 0 ? extraImgs : undefined
          });
          assistantIdx++;
        }
      } else {
        flushProgress();
        items.push({
          key: `asst-${mid}-${assistantIdx}`,
          kind: 'assistant',
          runId: 'history',
          text: text,
          localAt: at.length > 0 ? at : undefined,
          imageUrls: extraImgs.length > 0 ? extraImgs : undefined
        });
        assistantIdx++;
      }
    }
  }
  flushAsAssistant();
  return items;
}
