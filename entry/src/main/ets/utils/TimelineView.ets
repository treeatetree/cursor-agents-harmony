import { TimelineItem } from '../models/Timeline';

/**
 * Rows the conversation list should actually paint.
 * Process / tools fold into the lead ActivityCard; leftover ListItems
 * were leaving a blank gap above the assistant markdown.
 */
export function visibleTimeline(items: TimelineItem[]): TimelineItem[] {
  const leadSeen: Record<string, boolean> = {};
  const out: TimelineItem[] = [];
  for (let i = 0; i < items.length; i++) {
    const it = items[i];
    if (it.kind === 'runHeader' || it.kind === 'tool' || it.kind === 'streamNotice') {
      continue;
    }
    if (it.kind === 'thinking' || it.kind === 'progress' || it.kind === 'step') {
      const run = it.runId ?? '';
      if (leadSeen[run] === true) {
        continue;
      }
      leadSeen[run] = true;
    }
    out.push(it);
  }
  return out;
}
