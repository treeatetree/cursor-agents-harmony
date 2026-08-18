import { CachedAgentPayload } from '../store/AgentCache';
import { isRunInFlight } from './InboxGrouping';

function hasConversation(cached: CachedAgentPayload): boolean {
  if (cached.messages && cached.messages.length > 0) {
    return true;
  }
  return cached.timeline !== undefined && cached.timeline.length > 0;
}

function cacheRunId(cached: CachedAgentPayload): string {
  const fromDetail = cached.detail?.latestRunId ?? '';
  if (fromDetail.length > 0) {
    return fromDetail;
  }
  if (cached.timelineRunId && cached.timelineRunId.length > 0) {
    return cached.timelineRunId;
  }
  if (cached.runs && cached.runs.length > 0) {
    return cached.runs[0].id ?? '';
  }
  return '';
}

function cacheRunStatus(cached: CachedAgentPayload): string {
  const fromDetail = `${cached.detail?.latestRunStatus ?? ''}`;
  if (fromDetail.length > 0) {
    return fromDetail;
  }
  if (cached.runs && cached.runs.length > 0) {
    return `${cached.runs[0].status ?? ''}`;
  }
  return '';
}

/** True when disk already has a finished conversation and Inbox does not show a newer run. */
export function cacheCoversDetail(cached: CachedAgentPayload | undefined, inboxRunId: string = '',
  inboxRunStatus: string = ''): boolean {
  if (!cached || !cached.detail || !hasConversation(cached)) {
    return false;
  }
  if (inboxRunId.length === 0 && inboxRunStatus.length === 0) {
    return false;
  }
  const status = inboxRunStatus.length > 0 ? inboxRunStatus : cacheRunStatus(cached);
  if (isRunInFlight(status)) {
    return false;
  }
  const localRun = cacheRunId(cached);
  if (inboxRunId.length > 0 && localRun.length > 0 && inboxRunId !== localRun) {
    return false;
  }
  if (isRunInFlight(cacheRunStatus(cached))) {
    return false;
  }
  return true;
}

/** Same run already on disk — skip getConversation even if the run is still live. */
export function cacheCoversConversation(cached: CachedAgentPayload | undefined,
  inboxRunId: string = ''): boolean {
  if (!cached || !hasConversation(cached)) {
    return false;
  }
  const localRun = cacheRunId(cached);
  if (inboxRunId.length > 0 && localRun.length > 0 && inboxRunId !== localRun) {
    return false;
  }
  return true;
}
