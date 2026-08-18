import { ConversationMessage } from '../models/Api';
import { TimelineItem } from '../models/Timeline';

export const CACHE_TEXT_MAX = 32 * 1024;
export const CACHE_SUMMARY_MAX = 240;
export const CACHE_TIMELINE_MAX_ITEMS = 400;
export const CACHE_MESSAGES_MAX = 200;

export function clipText(s: string, maxN: number = CACHE_TEXT_MAX): string {
  if (!s || s.length <= maxN) {
    return s ?? '';
  }
  return s.substring(0, maxN);
}

export function capTimeline(items: TimelineItem[]): TimelineItem[] {
  let src = items;
  if (src.length > CACHE_TIMELINE_MAX_ITEMS) {
    src = src.slice(src.length - CACHE_TIMELINE_MAX_ITEMS);
  }
  const out: TimelineItem[] = [];
  for (let i = 0; i < src.length; i++) {
    const it = src[i];
    const text = it.text;
    if (text !== undefined && text.length > CACHE_TEXT_MAX) {
      out.push({
        key: it.key,
        kind: it.kind,
        runId: it.runId,
        text: clipText(text),
        tool: it.tool,
        statusLabel: it.statusLabel,
        collapsed: it.collapsed,
        pinnedOpen: it.pinnedOpen,
        failed: it.failed,
        streaming: it.streaming,
        stepCount: it.stepCount,
        usageShort: it.usageShort,
        sentTags: it.sentTags
      });
    } else {
      out.push(it);
    }
  }
  return out;
}

export function capMessages(items: ConversationMessage[]): ConversationMessage[] {
  let src = items;
  if (src.length > CACHE_MESSAGES_MAX) {
    src = src.slice(src.length - CACHE_MESSAGES_MAX);
  }
  const out: ConversationMessage[] = [];
  for (let i = 0; i < src.length; i++) {
    const m = src[i];
    out.push({
      id: m.id,
      type: m.type,
      text: clipText(m.text)
    });
  }
  return out;
}
