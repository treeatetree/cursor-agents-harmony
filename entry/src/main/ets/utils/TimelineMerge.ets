import { ConversationMessage } from '../models/Api';
import { TimelineItem } from '../models/Timeline';

/**
 * Conversation GET /v0/agents/{id}/conversation only has
 * { id, type: user_message|assistant_message, text }.
 * Message ids are not a stable fingerprint (Cursor has regenerated them).
 */
export function convFingerprint(messages: ConversationMessage[]): string {
  if (!messages || messages.length === 0) {
    return '';
  }
  const first = messages[0];
  const last = messages[messages.length - 1];
  const firstText = first.text ?? '';
  const lastText = last.text ?? '';
  const firstBit = firstText.length > 24 ? firstText.substring(0, 24) : firstText;
  const lastBit = lastText.length > 24 ? lastText.substring(0, 24) : lastText;
  return `${messages.length}|${first.type}|${firstText.length}|${firstBit}|${last.type}|${lastText.length}|${lastBit}`;
}

function isActivity(kind: string): boolean {
  return kind === 'thinking' || kind === 'progress' || kind === 'step' || kind === 'tool';
}

function isDurableExtra(kind: string): boolean {
  return isActivity(kind) || kind === 'runHeader' || kind === 'runOutcome';
}

function hasBody(item: TimelineItem): boolean {
  if ((item.text ?? '').trim().length > 0) {
    return true;
  }
  return item.kind === 'tool';
}

function copyItem(src: TimelineItem): TimelineItem {
  return {
    key: src.key,
    kind: src.kind,
    runId: src.runId,
    text: src.text,
    tool: src.tool,
    statusLabel: src.statusLabel,
    collapsed: src.pinnedOpen === true ? false : true,
    pinnedOpen: src.pinnedOpen,
    failed: src.failed,
    streaming: false,
    stepCount: src.stepCount,
    usageShort: src.usageShort
  };
}

function isRealRun(runId: string): boolean {
  return runId.length > 0 && runId !== 'history' && runId !== 'pending';
}

/**
 * Overlay SSE-only facts (thinking/tool/step) onto a conversation rebuild.
 * Conversation items are runId=history and have no tools; process lives in cache.
 * Place each real run's extras after the matching user turn (oldest run → first user).
 */
export function mergeCachedActivity(conv: TimelineItem[], cached: TimelineItem[]): TimelineItem[] {
  if (!cached || cached.length === 0) {
    return conv;
  }
  const next: TimelineItem[] = [];
  for (let i = 0; i < conv.length; i++) {
    next.push(conv[i]);
  }
  const extras: TimelineItem[] = [];
  let changed = false;
  for (let i = 0; i < cached.length; i++) {
    const c = cached[i];
    if (!isDurableExtra(c.kind)) {
      continue;
    }
    let found = -1;
    for (let j = 0; j < next.length; j++) {
      if (next[j].key === c.key) {
        found = j;
        break;
      }
    }
    if (found >= 0) {
      const cur = next[found];
      if ((cur.text ?? '').trim().length === 0 && (c.text ?? '').trim().length > 0) {
        cur.text = c.text;
        changed = true;
      }
      if (!cur.tool && c.tool) {
        cur.tool = c.tool;
        changed = true;
      }
      if (c.pinnedOpen === true) {
        cur.pinnedOpen = true;
        cur.collapsed = false;
        changed = true;
      }
      if ((cur.stepCount ?? 0) <= 0 && (c.stepCount ?? 0) > 0) {
        cur.stepCount = c.stepCount;
        changed = true;
      }
      continue;
    }
    if (c.kind !== 'runHeader' && c.kind !== 'runOutcome' && !hasBody(c)) {
      continue;
    }
    extras.push(copyItem(c));
  }
  const usable: TimelineItem[] = [];
  let realExtra = 0;
  for (let i = 0; i < extras.length; i++) {
    if (isRealRun(extras[i].runId ?? '')) {
      realExtra += 1;
    }
  }
  for (let i = 0; i < extras.length; i++) {
    const run = extras[i].runId ?? '';
    if (realExtra > 0 && !isRealRun(run) && isActivity(extras[i].kind)) {
      continue;
    }
    usable.push(extras[i]);
  }
  if (usable.length === 0) {
    return changed ? next : conv;
  }

  const groups: string[] = [];
  const byRun: Record<string, TimelineItem[]> = {};
  for (let i = 0; i < usable.length; i++) {
    const run = usable[i].runId ?? '';
    if (!byRun[run]) {
      byRun[run] = [];
      groups.push(run);
    }
    byRun[run].push(usable[i]);
  }
  const realGroups: string[] = [];
  for (let i = 0; i < groups.length; i++) {
    if (isRealRun(groups[i])) {
      realGroups.push(groups[i]);
    }
  }
  const userIdxs: number[] = [];
  for (let i = 0; i < next.length; i++) {
    if (next[i].kind === 'userPrompt') {
      userIdxs.push(i);
    }
  }
  if (realGroups.length > 0 && userIdxs.length === realGroups.length) {
    let turn = -1;
    for (let i = 0; i < next.length; i++) {
      if (next[i].kind === 'userPrompt') {
        turn += 1;
      }
      if (turn >= 0 && turn < realGroups.length && next[i].runId === 'history' && isActivity(next[i].kind)) {
        next[i].runId = realGroups[turn];
        changed = true;
      }
    }
  } else if (realGroups.length === 1 && userIdxs.length === 1) {
    for (let i = 0; i < next.length; i++) {
      if (next[i].runId === 'history' && isActivity(next[i].kind)) {
        next[i].runId = realGroups[0];
        changed = true;
      }
    }
  }

  const inserts: TimelineItem[][] = [];
  for (let i = 0; i < userIdxs.length; i++) {
    inserts.push([]);
  }
  const tail: TimelineItem[] = [];
  for (let g = 0; g < groups.length; g++) {
    const run = groups[g];
    const items = byRun[run];
    if (userIdxs.length === 0) {
      for (let i = 0; i < items.length; i++) {
        tail.push(items[i]);
      }
      continue;
    }
    let slot = userIdxs.length - 1;
    if (isRealRun(run)) {
      const ri = realGroups.indexOf(run);
      if (ri >= 0 && ri < userIdxs.length) {
        slot = ri;
      }
    }
    for (let i = 0; i < items.length; i++) {
      inserts[slot].push(items[i]);
    }
  }

  const merged: TimelineItem[] = [];
  let userNo = 0;
  for (let i = 0; i < next.length; i++) {
    merged.push(next[i]);
    if (next[i].kind === 'userPrompt') {
      const extra = inserts[userNo];
      for (let e = 0; e < extra.length; e++) {
        merged.push(extra[e]);
      }
      userNo += 1;
    }
  }
  for (let i = 0; i < tail.length; i++) {
    merged.push(tail[i]);
  }
  return merged;
}
