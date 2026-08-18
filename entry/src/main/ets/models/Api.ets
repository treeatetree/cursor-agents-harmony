export interface MeResponse {
  apiKeyName?: string;
  userEmail?: string;
  createdAt?: string;
  userId?: string;
  userFirstName?: string;
  userLastName?: string;
}

export type AgentStatus = 'ACTIVE' | 'ARCHIVED';
export type RunStatus = 'CREATING' | 'RUNNING' | 'FINISHED' | 'ERROR' | 'CANCELLED' | 'EXPIRED';

export interface RepoRef {
  url: string;
  startingRef?: string;
  prUrl?: string;
}

export interface GitBranch {
  repoUrl: string;
  branch?: string;
  prUrl?: string;
}

export interface AgentEnv {
  type: string;
  name?: string;
}

/** Create-time execution target. `default` means omit `env` and use repos. */
export interface EnvTarget {
  kind: string; // default | cloud | pool | machine
  name: string;
}

export interface McpServerDef {
  name: string;
  type: string; // http | sse | stdio
  url: string;
  command: string;
  argsText: string;
  envText: string;
  /** Remote MCP request headers, KEY=VAL;KEY=VAL. Official `headers`. */
  headersText: string;
}

export interface CustomSubagentDef {
  name: string;
  description: string;
  prompt: string;
  model: string;
}

export interface EnvVarDef {
  key: string;
  value: string;
}

export interface AgentSummary {
  id: string;
  name: string;
  status: AgentStatus;
  url: string;
  createdAt: string;
  updatedAt: string;
  /** Last time the user sent a prompt (create or follow-up). Inbox sort key. */
  lastUserAt?: string;
  latestRunId?: string;
  /** Enriched client-side from GET run — not always present on list payload. */
  latestRunStatus?: RunStatus | string;
  /** First lines of latest run.result, filled when Inbox enriches. */
  latestResult?: string;
  repos?: RepoRef[];
  env?: AgentEnv;
  workOnCurrentBranch?: boolean;
  autoCreatePR?: boolean;
  openAsCursorGithubApp?: boolean;
  skipReviewerRequest?: boolean;
}

export interface AgentDetail extends AgentSummary {
  customSubagents?: CustomSubagentDef[];
}

export interface RunGitInfo {
  branches: GitBranch[];
}

export interface Run {
  id: string;
  agentId: string;
  status: RunStatus;
  createdAt: string;
  updatedAt: string;
  durationMs?: number;
  result?: string;
  git?: RunGitInfo;
}

export interface AgentsListResponse {
  items?: AgentSummary[];
  agents?: AgentSummary[]; // legacy alias
  nextCursor?: string;
}

export interface RunsListResponse {
  items?: Run[];
  nextCursor?: string;
}

export interface CreateAgentResponse {
  agent?: AgentDetail;
  run?: Run;
}

/** POST /v1/agents/{id}/runs returns `{ run: Run }`, not a bare Run. */
export interface CreateRunResponse {
  run?: Run;
  id?: string; // legacy / defensive
  agentId?: string;
  status?: RunStatus;
  createdAt?: string;
  updatedAt?: string;
}

export interface ModelParamValue {
  value: string;
  displayName?: string;
}

export interface ModelParamDef {
  id: string;
  type?: string;
  displayName?: string;
  values?: ModelParamValue[];
}

export interface ModelVariantParam {
  id: string;
  value: string;
}

export interface ModelVariant {
  displayName?: string;
  isDefault?: boolean;
  params?: ModelVariantParam[];
}

export interface ModelInfo {
  id: string;
  displayName?: string;
  params?: ModelParamDef[];
  parameters?: ModelParamDef[];
  variants?: ModelVariant[];
  aliases?: string[];
  description?: string;
}

export interface ModelsResponse {
  models?: ModelInfo[];
  items?: ModelInfo[];
}

export interface RepoInfo {
  owner: string;
  name: string;
  repository: string;
}

export interface RepositoriesResponse {
  repositories?: RepoInfo[];
  items?: RepoInfo[];
}

export interface ArtifactInfo {
  path: string;
  sizeBytes?: number;
  updatedAt?: string;
}

export interface ArtifactsResponse {
  items?: ArtifactInfo[];
}

export interface ArtifactDownloadResponse {
  url: string;
  expiresAt?: string;
}

export interface TokenUsage {
  inputTokens?: number;
  outputTokens?: number;
  cacheWriteTokens?: number;
  cacheReadTokens?: number;
  totalTokens?: number;
}

export interface RunUsage {
  id: string;
  usageUuid?: string;
  usage: TokenUsage;
}

/** Loose usage payload — field shapes vary by API revision. */
export interface UsageResponse {
  totalUsage?: Record<string, Object>;
  cost?: Record<string, Object>;
  runs?: RunUsage[] | Object[];
}

/** Legacy Cloud Agents conversation transcript (v0). */
export type ConversationMessageType = 'user_message' | 'assistant_message';

export interface ConversationMessage {
  id: string;
  type: ConversationMessageType | string;
  text: string;
  createdAt?: string;
  images?: Object[];
}

export interface ConversationResponse {
  id?: string;
  messages?: ConversationMessage[];
}

export interface ApiErrorDetail {
  code?: string;
  message?: string;
}

export interface ApiErrorBody {
  error?: ApiErrorDetail;
  message?: string;
}

export class ApiException extends Error {
  code: number;
  apiCode: string;
  retryable: boolean;

  constructor(code: number, message: string, apiCode: string = '', retryable: boolean = false) {
    super(message);
    this.name = 'ApiException';
    this.code = code;
    this.apiCode = apiCode;
    this.retryable = retryable;
  }
}
