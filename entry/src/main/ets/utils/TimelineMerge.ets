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
    collapsed: src.pinnedOpen === true ? false : (src.streaming === true ? false : true),
    pinnedOpen: src.pinnedOpen,
    failed: src.failed,
    streaming: src.streaming === true,
    stepCount: src.stepCount,
    usageShort: src.usageShort,
    sentTags: src.sentTags
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
    if (c.kind !== 'runHeader' && c.kind !== 'runOutcome' && !hasBody(c) &&
      c.streaming !== true) {
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

function userPromptCount(items: TimelineItem[]): number {
  let n = 0;
  for (let i = 0; i < items.length; i++) {
    if (items[i].kind === 'userPrompt') {
      n += 1;
    }
  }
  return n;
}

/**
 * Conversation GET lags the local follow-up. Keep extra user turns (and the
 * waiting-think / tools that follow them) so a rebuild does not eat the bubble.
 */
export function keepPendingTurns(conv: TimelineItem[], live: TimelineItem[]): TimelineItem[] {
  if (!live || live.length === 0 || !conv) {
    return conv;
  }
  const convUsers = userPromptCount(conv);
  const liveUsers = userPromptCount(live);
  if (liveUsers <= convUsers) {
    return conv;
  }
  let seen = 0;
  let start = -1;
  for (let i = 0; i < live.length; i++) {
    if (live[i].kind !== 'userPrompt') {
      continue;
    }
    if (seen === convUsers) {
      start = i;
      break;
    }
    seen += 1;
  }
  if (start < 0) {
    return conv;
  }
  const out: TimelineItem[] = [];
  for (let i = 0; i < conv.length; i++) {
    out.push(conv[i]);
  }
  for (let i = start; i < live.length; i++) {
    const it = live[i];
    if (it.kind === 'streamNotice') {
      continue;
    }
    out.push(copyItem(it));
  }
  return out;
}

function looksLikeTokenShort(s: string): boolean {
  const t = s.trim();
  if (t.length === 0) {
    return true;
  }
  const last = t.charAt(t.length - 1);
  if (last === 'k' || last === 'K') {
    return true;
  }
  for (let i = 0; i < t.length; i++) {
    const c = t.charAt(i);
    if (c !== '.' && (c < '0' || c > '9')) {
      return false;
    }
  }
  return true;
}

/**
 * Conversation rebuild drops local sentTags. Copy them back onto matching user turns.
 */
export function restoreUserSentTags(conv: TimelineItem[], cached: TimelineItem[]): TimelineItem[] {
  if (!cached || cached.length === 0 || !conv || conv.length === 0) {
    return conv;
  }
  const src: TimelineItem[] = [];
  for (let i = 0; i < cached.length; i++) {
    if (cached[i].kind !== 'userPrompt') {
      continue;
    }
    const tags = cached[i].sentTags;
    const short = cached[i].usageShort ?? '';
    if ((tags && tags.length > 0) || (short.length > 0 && !looksLikeTokenShort(short))) {
      src.push(cached[i]);
    }
  }
  if (src.length === 0) {
    return conv;
  }
  let si = 0;
  let changed = false;
  const next: TimelineItem[] = [];
  for (let i = 0; i < conv.length; i++) {
    const it = conv[i];
    if (it.kind !== 'userPrompt') {
      next.push(it);
      continue;
    }
    if (it.sentTags && it.sentTags.length > 0) {
      next.push(it);
      si += 1;
      continue;
    }
    let found = -1;
    const text = it.text ?? '';
    for (let j = si; j < src.length; j++) {
      if ((src[j].text ?? '') === text) {
        found = j;
        break;
      }
    }
    const take = found >= 0 ? src[found] : (si < src.length ? src[si] : undefined);
    if (!take) {
      next.push(it);
      continue;
    }
    const copy: TimelineItem = {
      key: it.key,
      kind: it.kind,
      runId: it.runId,
      text: it.text,
      tool: it.tool,
      statusLabel: it.statusLabel,
      collapsed: it.collapsed,
      pinnedOpen: it.pinnedOpen,
      failed: it.failed,
      streaming: it.streaming,
      stepCount: it.stepCount,
      usageShort: it.usageShort,
      sentTags: it.sentTags
    };
    if (take.sentTags && take.sentTags.length > 0) {
      copy.sentTags = take.sentTags;
    }
    const srcShort = take.usageShort ?? '';
    if (srcShort.length > 0 && !looksLikeTokenShort(srcShort)) {
      copy.usageShort = srcShort;
    }
    next.push(copy);
    changed = true;
    si = found >= 0 ? found + 1 : si + 1;
  }
  return changed ? next : conv;
}
