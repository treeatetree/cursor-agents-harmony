import {
  AgentDetail, AgentSummary, AgentsListResponse, ArtifactInfo,
  CreateAgentResponse, CreateRunResponse, CustomSubagentDef, ModelInfo, ModelsResponse,
  RepoInfo, RepositoriesResponse, Run, RunUsage, TokenUsage
} from '../models/Api';

/** Normalize agents list payloads (`items` or legacy `agents`). */
export function unwrapAgentsList(raw: object): AgentsListResponse {
  const r = raw as AgentsListResponse;
  const items: AgentSummary[] = r.items ?? r.agents ?? [];
  const normalized: AgentSummary[] = [];
  for (let i = 0; i < items.length; i++) {
    normalized.push(normalizeAgentSummary(items[i]));
  }
  const out: AgentsListResponse = { items: normalized };
  if (r.nextCursor && r.nextCursor.length > 0) {
    out.nextCursor = r.nextCursor;
  }
  return out;
}

export function normalizeAgentSummary(item: AgentSummary): AgentSummary {
  const raw = item as object as Record<string, Object>;
  const created = `${item.createdAt ?? raw['created_at'] ?? ''}`;
  let updated = `${item.updatedAt ?? raw['updated_at'] ?? ''}`;
  if (updated.length === 0) {
    updated = created;
  }
  item.createdAt = created;
  item.updatedAt = updated;
  const userAt = `${item.lastUserAt ?? raw['lastUserAt'] ?? raw['last_user_at'] ?? ''}`;
  if (userAt.length > 0 && userAt !== 'undefined') {
    item.lastUserAt = userAt;
  }
  const nested = raw['latestRun'] as Record<string, Object> | undefined;
  const runId = `${item.latestRunId ?? raw['latest_run_id'] ?? nested?.['id'] ?? ''}`;
  const runStatus =
    `${item.latestRunStatus ?? raw['latest_run_status'] ?? nested?.['status'] ?? ''}`;
  const result = `${item.latestResult ?? raw['latest_result'] ?? nested?.['result'] ?? ''}`;
  if (runId.length > 0) {
    item.latestRunId = runId;
  }
  if (runStatus.length > 0) {
    item.latestRunStatus = runStatus;
  }
  if (result.length > 0) {
    item.latestResult = result;
  }
  return item;
}

export function unwrapAgentDetail(raw: object): AgentDetail {
  const r = raw as Record<string, Object>;
  const nested = r['agent'] as AgentDetail | undefined;
  const base = nested && nested.id && nested.id.length > 0 ? nested : raw as AgentDetail;
  const src = (nested && nested.id && nested.id.length > 0 ? nested : r) as Record<string, Object>;
  const subs = parseCustomSubagents(src['customSubagents']);
  if (subs.length > 0) {
    base.customSubagents = subs;
  }
  return base;
}

/** Normalize GET/POST run payloads (`{ run }` or bare Run). */
export function unwrapRun(raw: object): Run {
  const wrapped = raw as CreateRunResponse;
  if (wrapped.run && wrapped.run.id) {
    return wrapped.run;
  }
  const bare = raw as Run;
  if (bare.id && bare.id.length > 0) {
    return {
      id: bare.id,
      agentId: bare.agentId ?? '',
      status: bare.status ?? 'CREATING',
      createdAt: bare.createdAt ?? '',
      updatedAt: bare.updatedAt ?? '',
      durationMs: bare.durationMs,
      result: bare.result,
      git: bare.git
    };
  }
  // Flattened create-run shape without nested `run`.
  if (wrapped.id && wrapped.id.length > 0) {
    return {
      id: wrapped.id,
      agentId: wrapped.agentId ?? '',
      status: wrapped.status ?? 'CREATING',
      createdAt: wrapped.createdAt ?? '',
      updatedAt: wrapped.updatedAt ?? ''
    };
  }
  return {
    id: '',
    agentId: '',
    status: 'CREATING',
    createdAt: '',
    updatedAt: ''
  };
}

/** Normalize create-agent `{ agent, run }` payloads. */
export function unwrapCreateAgent(raw: object): CreateAgentResponse {
  const r = raw as CreateAgentResponse;
  const out: CreateAgentResponse = {};
  if (r.agent) {
    out.agent = r.agent;
  }
  if (r.run && r.run.id) {
    out.run = r.run;
  }
  return out;
}

export function unwrapModels(raw: object): ModelInfo[] {
  const r = raw as ModelsResponse;
  return r.models ?? r.items ?? [];
}

export function unwrapRepos(raw: object): RepoInfo[] {
  const r = raw as RepositoriesResponse;
  return r.repositories ?? r.items ?? [];
}

export function unwrapUsageRuns(raw: object): RunUsage[] {
  const r = raw as Record<string, Object>;
  const list = (r['runs'] ?? []) as object[];
  const out: RunUsage[] = [];
  for (let i = 0; i < list.length; i++) {
    const item = list[i] as Record<string, Object>;
    const usageRaw = (item['usage'] ?? {}) as Record<string, Object>;
    const usage: TokenUsage = {
      inputTokens: numOrZero(usageRaw['inputTokens']),
      outputTokens: numOrZero(usageRaw['outputTokens']),
      cacheWriteTokens: numOrZero(usageRaw['cacheWriteTokens']),
      cacheReadTokens: numOrZero(usageRaw['cacheReadTokens']),
      totalTokens: numOrZero(usageRaw['totalTokens'])
    };
    out.push({
      id: `${item['id'] ?? ''}`,
      usageUuid: item['usageUuid'] ? `${item['usageUuid']}` : undefined,
      usage: usage
    });
  }
  return out;
}

function numOrZero(v: Object | undefined): number {
  const n = Number(v ?? 0);
  return n === n ? n : 0;
}

function parseCustomSubagents(raw: Object | undefined): CustomSubagentDef[] {
  if (raw === undefined || raw === null) {
    return [];
  }
  const arr = raw as Object[];
  if (arr.length === undefined) {
    return [];
  }
  const out: CustomSubagentDef[] = [];
  for (let i = 0; i < arr.length; i++) {
    const s = arr[i] as Record<string, Object>;
    const name = `${s['name'] ?? ''}`.trim();
    if (name.length === 0) {
      continue;
    }
    out.push({
      name: name,
      description: `${s['description'] ?? ''}`,
      prompt: `${s['prompt'] ?? ''}`,
      model: `${s['model'] ?? 'inherit'}`
    });
  }
  return out;
}

export function unwrapArtifacts(raw: object): ArtifactInfo[] {
  const r = raw as Record<string, Object>;
  const asArr = raw as Object[];
  const fromKey = r['items'] ?? r['artifacts'] ?? r['files'] ?? r['data'];
  const list = (fromKey ?? (asArr.length !== undefined ? asArr : [])) as Object[];
  const out: ArtifactInfo[] = [];
  if (list.length === undefined) {
    return out;
  }
  for (let i = 0; i < list.length; i++) {
    try {
      const row = list[i] as Record<string, Object>;
      const path = `${row['path'] ?? row['file'] ?? row['filePath'] ?? row['name'] ?? ''}`.trim();
      if (path.length === 0) {
        continue;
      }
      const item: ArtifactInfo = { path: path };
      const size = Number(row['sizeBytes'] ?? row['size'] ?? 0);
      if (size > 0) {
        item.sizeBytes = size;
      }
      const at = `${row['updatedAt'] ?? row['updated_at'] ?? ''}`;
      if (at.length > 0) {
        item.updatedAt = at;
      }
      out.push(item);
    } catch (_e) {
    }
  }
  return out;
}
