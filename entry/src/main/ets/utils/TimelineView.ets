import { TimelineItem } from '../models/Timeline';
import { isLiveWaitItem } from './TimelineMedia';

function activityHasBody(it: TimelineItem, hasTool: boolean): boolean {
  if ((it.text ?? '').trim().length > 0) {
    return true;
  }
  return hasTool;
}

/** Empty streaming think — the live "still running" tail, even after tools/assistant. */
export function isWaitingThink(item: TimelineItem, _hasTool: boolean = false): boolean {
  return isLiveWaitItem(item);
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
      const liveWait = isLiveWaitItem(it);
      if (leadSeen[run] === true && !liveWait) {
        continue;
      }
      const live = it.streaming === true;
      if (!live && !activityHasBody(it, hasTool[run] === true)) {
        continue;
      }
      if (!liveWait) {
        leadSeen[run] = true;
      }
    }
    out.push(it);
  }
  return out;
}

export function lastContentKey(items: TimelineItem[]): string {
  for (let i = items.length - 1; i >= 0; i--) {
    const k = items[i].kind;
    if (k === 'userPrompt' || k === 'assistant' || k === 'plan') {
      return items[i].key;
    }
  }
  return items.length > 0 ? items[items.length - 1].key : '';
}

/** First new userPrompt after lastSeen; else that run's assistant head.
 *  Never-seen (empty lastSeen): latest userPrompt. Unknown lastSeen: none. */
export function findUnreadAnchor(items: TimelineItem[], lastSeenKey: string): string {
  if (lastSeenKey.length === 0) {
    for (let i = items.length - 1; i >= 0; i--) {
      if (items[i].kind === 'userPrompt') {
        return items[i].key;
      }
    }
    for (let i = items.length - 1; i >= 0; i--) {
      if (items[i].kind === 'assistant' || items[i].kind === 'plan') {
        return items[i].key;
      }
    }
    return '';
  }
  let start = 0;
  let found = false;
  for (let i = 0; i < items.length; i++) {
    if (items[i].key === lastSeenKey) {
      start = i + 1;
      found = true;
      break;
    }
  }
  if (!found) {
    // Stale lastSeen (key format changed) is not "never opened".
    // Jumping to the latest userPrompt would pin a read thread at the top.
    return '';
  }
  for (let i = start; i < items.length; i++) {
    if (items[i].kind === 'userPrompt') {
      return items[i].key;
    }
  }
  for (let i = start; i < items.length; i++) {
    if (items[i].kind === 'assistant' || items[i].kind === 'plan') {
      return items[i].key;
    }
  }
  return '';
}

export function countNewContent(items: TimelineItem[], lastSeenKey: string): number {
  let start = 0;
  if (lastSeenKey.length === 0) {
    for (let i = items.length - 1; i >= 0; i--) {
      if (items[i].kind === 'userPrompt') {
        start = i;
        break;
      }
    }
  } else {
    let found = false;
    for (let i = 0; i < items.length; i++) {
      if (items[i].key === lastSeenKey) {
        start = i + 1;
        found = true;
        break;
      }
    }
    if (!found) {
      return 0;
    }
  }
  let n = 0;
  for (let i = start; i < items.length; i++) {
    const k = items[i].kind;
    if (k === 'userPrompt' || k === 'assistant' || k === 'plan') {
      n++;
    }
  }
  return n;
}

/** Grey from the 1-based counter only. 1 disables up; total disables down. */
export function jumpCanFromIndex(index: number, total: number, dir: number): boolean {
  if (total <= 0 || index < 1) {
    return false;
  }
  if (dir < 0) {
    return index > 1;
  }
  return index < total;
}

/**
 * Which user prompt the jump buttons are on.
 * lastKey is the cursor after a tap. If empty: last prompt when pinned to
 * the bottom, otherwise the prompt at the top of the screen.
 */
export function currentUserJumpAt(
  keys: string[],
  idxs: number[],
  lastKey: string,
  viewStart: number,
  stickToBottom: boolean
): number {
  if (keys.length === 0 || keys.length !== idxs.length) {
    return -1;
  }
  if (lastKey.length > 0) {
    for (let i = 0; i < keys.length; i++) {
      if (keys[i] === lastKey) {
        return i;
      }
    }
  }
  if (stickToBottom) {
    return keys.length - 1;
  }
  for (let i = keys.length - 1; i >= 0; i--) {
    if (idxs[i] <= viewStart) {
      return i;
    }
  }
  return 0;
}

/**
 * Next user-prompt index in `keys` for up/down jump. No wrap.
 * Returns -1 when the move is past either end.
 */
export function nextUserJumpAt(
  keys: string[],
  idxs: number[],
  lastKey: string,
  dir: number,
  viewStart: number,
  viewEnd: number,
  stickToBottom: boolean = false
): number {
  const cur = currentUserJumpAt(keys, idxs, lastKey, viewStart, stickToBottom);
  if (cur < 0) {
    return -1;
  }
  const next = cur + dir;
  if (next < 0 || next >= keys.length) {
    return -1;
  }
  return next;
}

/** False when this direction would not move to another user prompt. */
export function canUserJump(
  keys: string[],
  idxs: number[],
  lastKey: string,
  dir: number,
  viewStart: number,
  viewEnd: number,
  stickToBottom: boolean = false
): boolean {
  return nextUserJumpAt(keys, idxs, lastKey, dir, viewStart, viewEnd, stickToBottom) >= 0;
}

export function visibleKeySig(items: TimelineItem[]): string {
  let out = '';
  for (let i = 0; i < items.length; i++) {
    if (i > 0) {
      out += '\n';
    }
    out += items[i].key;
  }
  return out;
}

export function visibleRowSig(item: TimelineItem): string {
  return `${item.text ?? ''}|${item.promptText ?? ''}|${item.streaming === true ? '1' : '0'}|${item.statusLabel ?? ''}|${item.stepCount ?? 0}|${item.collapsed === true ? '1' : '0'}|${item.pinnedOpen === true ? '1' : '0'}|${item.failed === true ? '1' : '0'}`;
}
