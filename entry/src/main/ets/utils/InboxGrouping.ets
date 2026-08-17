import { AgentSummary } from '../models/Api';
import { repoTail, shortRepoName } from './DisplayFmt';

export type FilterMode = 'all' | 'running' | 'error' | 'done';
export type SortMode = 'updated' | 'created' | 'name';
export type ViewMode = 'list' | 'cards';
export type GroupMode = 'none' | 'time' | 'repo' | 'status';

export interface GroupBucket {
  key: string;
  label: string;
  items: AgentSummary[];
}

export interface CardPair {
  key: string;
  left: AgentSummary;
  right: AgentSummary;
  hasRight: boolean;
}

export interface RecentRepo {
  url: string;
  ref: string;
  title: string;
}

export interface RecentRepoRow {
  key: string;
  left: RecentRepo;
  right: RecentRepo;
  hasRight: boolean;
}

export function pairRecentRepos(items: RecentRepo[]): RecentRepoRow[] {
  const out: RecentRepoRow[] = [];
  for (let i = 0; i < items.length; i += 2) {
    const left = items[i];
    const hasRight = i + 1 < items.length;
    out.push({
      key: hasRight ? `${left.url}|${items[i + 1].url}` : left.url,
      left: left,
      right: hasRight ? items[i + 1] : left,
      hasRight: hasRight
    });
  }
  return out;
}

export function pairAgents(items: AgentSummary[]): CardPair[] {
  const out: CardPair[] = [];
  for (let i = 0; i < items.length; i += 2) {
    const left = items[i];
    const hasRight = i + 1 < items.length;
    out.push({
      key: hasRight ? `${left.id}|${items[i + 1].id}` : left.id,
      left: left,
      right: hasRight ? items[i + 1] : left,
      hasRight: hasRight
    });
  }
  return out;
}

export function isRunInFlight(status?: string): boolean {
  return status === 'RUNNING' || status === 'CREATING';
}

export function isPinnedId(id: string, pinned: string[]): boolean {
  return pinned.indexOf(id) >= 0;
}

export function applyInboxQuery(
  items: AgentSummary[],
  query: string,
  filter: FilterMode,
  sort: SortMode,
  pinned: string[] = []
): AgentSummary[] {
  const q = (query ?? '').trim().toLowerCase();
  const out: AgentSummary[] = [];
  for (let i = 0; i < items.length; i++) {
    const a = items[i];
    if (!matchesFilter(a, filter)) {
      continue;
    }
    if (q.length > 0 && !matchesQuery(a, q)) {
      continue;
    }
    out.push(a);
  }
  out.sort((x: AgentSummary, y: AgentSummary) => comparePinned(x, y, sort, pinned));
  return out;
}

export function groupAgents(items: AgentSummary[], mode: GroupMode, pinned: string[] = []): GroupBucket[] {
  const archived: AgentSummary[] = [];
  const pinItems: AgentSummary[] = [];
  const rest: AgentSummary[] = [];
  for (let i = 0; i < items.length; i++) {
    if (items[i].status === 'ARCHIVED') {
      archived.push(items[i]);
    } else if (isPinnedId(items[i].id, pinned)) {
      pinItems.push(items[i]);
    } else {
      rest.push(items[i]);
    }
  }
  pinItems.sort((x: AgentSummary, y: AgentSummary) => pinRank(x.id, pinned) - pinRank(y.id, pinned));

  let buckets: GroupBucket[] = [];
  if (mode === 'none') {
    buckets = [{ key: 'all', label: '', items: rest }];
  } else if (mode === 'repo') {
    buckets = groupByKey(rest, (a: AgentSummary) => repoKey(a), (a: AgentSummary) => repoLabel(a));
  } else if (mode === 'status') {
    buckets = groupByKey(rest, (a: AgentSummary) => statusKey(a), (a: AgentSummary) => statusLabel(a));
  } else {
    buckets = groupByTime(rest);
  }
  for (let i = 0; i < buckets.length; i++) {
    buckets[i].items.sort((x: AgentSummary, y: AgentSummary) => recencyMs(y) - recencyMs(x));
  }
  // Time buckets stay today → older. Repo groups rise by latest item. Status by urgency.
  if (mode === 'repo') {
    buckets.sort((g: GroupBucket, h: GroupBucket) => bucketLatest(h) - bucketLatest(g));
  } else if (mode === 'status') {
    buckets.sort((g: GroupBucket, h: GroupBucket) => bucketUrgency(g) - bucketUrgency(h));
  }
  const next: GroupBucket[] = [];
  if (pinItems.length > 0) {
    next.push({ key: 'pinned', label: '置顶', items: pinItems });
  }
  for (let i = 0; i < buckets.length; i++) {
    if (buckets[i].items.length > 0) {
      next.push(buckets[i]);
    }
  }
  if (archived.length > 0) {
    archived.sort((x: AgentSummary, y: AgentSummary) => recencyMs(y) - recencyMs(x));
    next.push({ key: 'archived', label: '归档', items: archived });
  }
  return next;
}

export function hasPr(a: AgentSummary): boolean {
  if (!a.repos) {
    return false;
  }
  for (let i = 0; i < a.repos.length; i++) {
    const u = a.repos[i].prUrl ?? '';
    if (u.length > 0) {
      return true;
    }
  }
  return false;
}

export function firstPrUrl(a: AgentSummary): string {
  if (!a.repos) {
    return '';
  }
  for (let i = 0; i < a.repos.length; i++) {
    const u = a.repos[i].prUrl ?? '';
    if (u.length > 0) {
      return u;
    }
  }
  return '';
}

export function urgencyOf(a: AgentSummary): number {
  const run = `${a.latestRunStatus ?? ''}`;
  if (isRunInFlight(run)) {
    return 0;
  }
  if (run === 'ERROR' || run === 'EXPIRED') {
    return 1;
  }
  if (hasPr(a)) {
    return 2;
  }
  return 3;
}

function bucketLatest(g: GroupBucket): number {
  let best = 0;
  for (let i = 0; i < g.items.length; i++) {
    const t = recencyMs(g.items[i]);
    if (t > best) {
      best = t;
    }
  }
  return best;
}

function bucketUrgency(g: GroupBucket): number {
  let best = 9;
  for (let i = 0; i < g.items.length; i++) {
    const u = urgencyOf(g.items[i]);
    if (u < best) {
      best = u;
    }
  }
  return best;
}

function matchesFilter(a: AgentSummary, filter: FilterMode): boolean {
  if (filter === 'all') {
    return true;
  }
  const run = `${a.latestRunStatus ?? ''}`;
  if (filter === 'running') {
    return isRunInFlight(run);
  }
  if (filter === 'error') {
    return run === 'ERROR' || run === 'EXPIRED';
  }
  if (filter === 'done') {
    return run === 'FINISHED' || run === 'CANCELLED';
  }
  return true;
}

function matchesQuery(a: AgentSummary, q: string): boolean {
  const name = (a.name ?? '').toLowerCase();
  if (name.indexOf(q) >= 0) {
    return true;
  }
  const id = (a.id ?? '').toLowerCase();
  if (id.indexOf(q) >= 0) {
    return true;
  }
  const repo = repoLabel(a).toLowerCase();
  return repo.indexOf(q) >= 0;
}

function pinRank(id: string, pinned: string[]): number {
  const i = pinned.indexOf(id);
  return i < 0 ? 10000 : i;
}

function comparePinned(x: AgentSummary, y: AgentSummary, sort: SortMode, pinned: string[]): number {
  const px = pinRank(x.id, pinned);
  const py = pinRank(y.id, pinned);
  const xPin = px < 10000;
  const yPin = py < 10000;
  if (xPin && yPin) {
    return px - py;
  }
  if (xPin !== yPin) {
    return xPin ? -1 : 1;
  }
  return compareAgents(x, y, sort);
}

function compareAgents(x: AgentSummary, y: AgentSummary, sort: SortMode): number {
  if (sort === 'name') {
    return (x.name ?? x.id).localeCompare(y.name ?? y.id);
  }
  if (sort === 'created') {
    return stamp(y.createdAt) - stamp(x.createdAt);
  }
  return recencyMs(y) - recencyMs(x);
}

export function stamp(iso: string): number {
  if (!iso || iso.length === 0) {
    return 0;
  }
  const t = Date.parse(iso);
  return t === t ? t : 0;
}

export function isLocalAgentId(id: string): boolean {
  return id.indexOf('local-') === 0;
}

export function userStampIso(a: AgentSummary): string {
  if (a.lastUserAt && a.lastUserAt.length > 0) {
    return a.lastUserAt;
  }
  if (a.createdAt && a.createdAt.length > 0) {
    return a.createdAt;
  }
  return a.updatedAt ?? '';
}

export function recencyMs(a: AgentSummary): number {
  return stamp(userStampIso(a));
}

export function sortByRecency(items: AgentSummary[]): AgentSummary[] {
  const out: AgentSummary[] = [];
  for (let i = 0; i < items.length; i++) {
    out.push(items[i]);
  }
  out.sort((x: AgentSummary, y: AgentSummary) => recencyMs(y) - recencyMs(x));
  return out;
}

export function pickNewerIso(a: string, b: string): string {
  if (!a || a.length === 0) {
    return b ?? '';
  }
  if (!b || b.length === 0) {
    return a;
  }
  return stamp(a) >= stamp(b) ? a : b;
}

const LOCAL_GRACE_MS = 3 * 60 * 1000;

/** Keep local recency / not-yet-listed cards when the list API lags. */
export function mergeInboxLists(
  remote: AgentSummary[],
  local: AgentSummary[],
  heldIds: string[],
  nowMs: number
): AgentSummary[] {
  const localById: Record<string, AgentSummary> = {};
  for (let i = 0; i < local.length; i++) {
    localById[local[i].id] = local[i];
  }
  const held: Record<string, boolean> = {};
  for (let i = 0; i < heldIds.length; i++) {
    held[heldIds[i]] = true;
  }
  const seen: Record<string, boolean> = {};
  const out: AgentSummary[] = [];
  for (let i = 0; i < remote.length; i++) {
    const a = remote[i];
    const prev = localById[a.id];
    if (prev) {
      a.updatedAt = pickNewerIso(a.updatedAt, prev.updatedAt);
      a.createdAt = pickNewerIso(a.createdAt, prev.createdAt);
      const userAt = pickNewerIso(a.lastUserAt ?? '', prev.lastUserAt ?? '');
      if (userAt.length > 0) {
        a.lastUserAt = userAt;
      }
      const remoteRun = `${a.latestRunId ?? ''}`;
      const localRun = `${prev.latestRunId ?? ''}`;
      if (remoteRun.length === 0 && localRun.length > 0) {
        a.latestRunId = prev.latestRunId;
      }
      const sameRun = `${a.latestRunId ?? ''}` === localRun || localRun.length === 0;
      if (sameRun && (!a.latestRunStatus || `${a.latestRunStatus}`.length === 0) &&
        prev.latestRunStatus) {
        a.latestRunStatus = prev.latestRunStatus;
      }
      if (sameRun && (!a.latestResult || a.latestResult.length === 0) && prev.latestResult) {
        a.latestResult = prev.latestResult;
      }
    }
    out.push(a);
    seen[a.id] = true;
  }
  for (let i = 0; i < local.length; i++) {
    const a = local[i];
    if (seen[a.id]) {
      continue;
    }
    const age = nowMs - recencyMs(a);
    if (held[a.id] || isLocalAgentId(a.id) || (age >= 0 && age < LOCAL_GRACE_MS)) {
      out.push(a);
    }
  }
  return out;
}

function repoKey(a: AgentSummary): string {
  if (a.repos && a.repos.length > 0) {
    return shortRepoName(a.repos[0].url ?? '') || 'repo';
  }
  return 'none';
}

function repoLabel(a: AgentSummary): string {
  if (a.repos && a.repos.length > 0) {
    return repoTail(a.repos[0].url ?? '');
  }
  if (a.env?.name && a.env.name.length > 0) {
    return a.env.name;
  }
  return '未绑定仓库';
}

function statusKey(a: AgentSummary): string {
  if (a.status === 'ARCHIVED') {
    return 'archived';
  }
  const run = `${a.latestRunStatus ?? ''}`;
  if (isRunInFlight(run)) {
    return 'running';
  }
  if (run === 'ERROR' || run === 'EXPIRED') {
    return 'error';
  }
  if (run === 'CANCELLED') {
    return 'cancelled';
  }
  if (run === 'FINISHED') {
    return 'done';
  }
  return 'idle';
}

function statusLabel(a: AgentSummary): string {
  const key = statusKey(a);
  if (key === 'archived') {
    return '已归档';
  }
  if (key === 'running') {
    return '运行中';
  }
  if (key === 'error') {
    return '失败';
  }
  if (key === 'cancelled') {
    return '已取消';
  }
  if (key === 'done') {
    return '已完成';
  }
  return '空闲';
}

function groupByTime(items: AgentSummary[]): GroupBucket[] {
  const now = Date.now();
  const startToday = startOfDay(now);
  const startYesterday = startToday - 86400000;
  const startWeek = startToday - 6 * 86400000;
  const buckets: GroupBucket[] = [
    { key: 'today', label: '今天', items: [] },
    { key: 'yesterday', label: '昨天', items: [] },
    { key: 'week', label: '本周', items: [] },
    { key: 'older', label: '更早', items: [] }
  ];
  for (let i = 0; i < items.length; i++) {
    const t = recencyMs(items[i]);
    if (t >= startToday) {
      buckets[0].items.push(items[i]);
    } else if (t >= startYesterday) {
      buckets[1].items.push(items[i]);
    } else if (t >= startWeek) {
      buckets[2].items.push(items[i]);
    } else {
      buckets[3].items.push(items[i]);
    }
  }
  return buckets.filter((b: GroupBucket) => b.items.length > 0);
}

function startOfDay(ms: number): number {
  const d = new Date(ms);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

function groupByKey(
  items: AgentSummary[],
  keyOf: (a: AgentSummary) => string,
  labelOf: (a: AgentSummary) => string
): GroupBucket[] {
  const order: string[] = [];
  const map: Map<string, GroupBucket> = new Map();
  for (let i = 0; i < items.length; i++) {
    const key = keyOf(items[i]);
    let bucket = map.get(key);
    if (!bucket) {
      bucket = { key: key, label: labelOf(items[i]), items: [] };
      map.set(key, bucket);
      order.push(key);
    }
    bucket.items.push(items[i]);
  }
  const out: GroupBucket[] = [];
  for (let i = 0; i < order.length; i++) {
    const b = map.get(order[i]);
    if (b) {
      out.push(b);
    }
  }
  return out;
}

/** Newest-first unique repos from inbox cards, for the new-task sheet. */
export function collectRecentRepos(agents: AgentSummary[], maxN: number): RecentRepo[] {
  const out: RecentRepo[] = [];
  for (let i = 0; i < agents.length; i++) {
    const repos = agents[i].repos;
    if (!repos || repos.length === 0) {
      continue;
    }
    const url = `${repos[0].url ?? ''}`.trim();
    if (url.length === 0) {
      continue;
    }
    let seen = false;
    for (let j = 0; j < out.length; j++) {
      if (out[j].url === url) {
        seen = true;
        break;
      }
    }
    if (seen) {
      continue;
    }
    const ref = `${repos[0].startingRef ?? ''}`.trim();
    const title = repoTail(url);
    const item: RecentRepo = {
      url: url,
      ref: ref.length > 0 ? ref : 'main',
      title: title.length > 0 ? title : url
    };
    out.push(item);
    if (out.length >= maxN) {
      break;
    }
  }
  return out;
}
