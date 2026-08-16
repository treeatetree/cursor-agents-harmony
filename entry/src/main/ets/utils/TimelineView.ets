import { TimelineItem } from '../models/Timeline';

function activityHasBody(it: TimelineItem, hasTool: boolean): boolean {
  if ((it.text ?? '').trim().length > 0) {
    return true;
  }
  return hasTool;
}

/** Finished headers were painting "运行 · 已完成" on top of another 已完成. */
function isSettledHeader(it: TimelineItem): boolean {
  const st = `${it.statusLabel ?? ''}`;
  if (st === 'FINISHED' || st === 'ERROR' || st === 'CANCELLED' || st === 'EXPIRED') {
    return true;
  }
  const t = `${it.text ?? ''}`;
  return t.indexOf('已完成') >= 0 || t.indexOf('已取消') >= 0 || t.indexOf('已过期') >= 0 ||
    t.indexOf('失败') >= 0;
}

/**
 * Rows the conversation list should actually paint.
 * Process / tools fold into the lead ActivityCard; leftover ListItems
 * were leaving a blank gap above the assistant markdown.
 * First-run headers stay hidden; later turns keep a thin divider.
 * Hollow process cards (no text, no tools, not streaming) are dropped.
 */
export function visibleTimeline(items: TimelineItem[]): TimelineItem[] {
  const hasTool: Record<string, boolean> = {};
  let firstRun = '';
  for (let i = 0; i < items.length; i++) {
    const it = items[i];
    const run = it.runId ?? '';
    if (it.kind === 'tool') {
      hasTool[run] = true;
    }
    if (firstRun.length === 0 && run.length > 0 && it.kind !== 'streamNotice') {
      firstRun = run;
    }
  }
  const leadSeen: Record<string, boolean> = {};
  const userSeen: Record<string, boolean> = {};
  const out: TimelineItem[] = [];
  for (let i = 0; i < items.length; i++) {
    const it = items[i];
    if (it.kind === 'tool' || it.kind === 'streamNotice') {
      continue;
    }
    if (it.kind === 'runHeader') {
      if (isSettledHeader(it)) {
        continue;
      }
      const run = it.runId ?? '';
      if (run.length === 0 || run === firstRun || userSeen[run] === true) {
        continue;
      }
      out.push(it);
      continue;
    }
    if (it.kind === 'userPrompt') {
      userSeen[it.runId ?? ''] = true;
    }
    if (it.kind === 'thinking' || it.kind === 'progress' || it.kind === 'step') {
      const run = it.runId ?? '';
      if (leadSeen[run] === true) {
        continue;
      }
      const live = it.streaming === true;
      if (!live && !activityHasBody(it, hasTool[run] === true)) {
        continue;
      }
      leadSeen[run] = true;
    }
    out.push(it);
  }
  return out;
}
