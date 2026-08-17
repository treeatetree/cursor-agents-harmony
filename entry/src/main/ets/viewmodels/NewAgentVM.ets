import {
  AgentSummary, ApiException, CreateAgentResponse, CustomSubagentDef, EnvTarget, EnvVarDef,
  McpServerDef, ModelInfo, ModelParamDef, ModelParamValue, ModelVariant,
  ModelVariantParam, RepoInfo
} from '../models/Api';
import { unwrapCreateAgent, unwrapModels } from '../api/ApiUnwrap';
import { CursorApiClient } from '../api/CursorApiClient';
import { AgentCache } from '../store/AgentCache';
import { ApiKeyStore } from '../store/ApiKeyStore';
import { PrefStore } from '../store/PrefStore';
import { recencyMs } from '../utils/InboxGrouping';
import {
  defaultEnv, parseToolsPref, serializeTools, toApiEnv, toApiEnvVars, toApiMcp,
  toApiSubagents, usesNamedEnv
} from '../utils/AgentCapabilities';
import { Log } from '../utils/Log';
import { coerceParamsToVariant, findModel, modelSentJson } from '../utils/ModelGroups';
import { util } from '@kit.ArkTS';

const TAG = 'NewAgentVM';
const REPO_COOLDOWN_MS = 60 * 1000;
const META_WARM_MS = 10 * 60 * 1000;
const REPO_LIMIT_MSG = '仓库列表每分钟只能刷新一次，请稍后再试';

let reposInFlight: Promise<RepoInfo[]> | undefined = undefined;
let lastReposAttemptAt: number = 0;

export class NewAgentVM {
  prompt: string = '';
  repos: RepoInfo[] = [];
  models: ModelInfo[] = [];
  selectedRepo: string = '';
  selectedBranch: string = 'main';
  selectedPrUrl: string = '';
  repoMode: string = 'repo'; // repo | pr | none
  selectedModel: string = '';
  selectedVariant: string = '';
  mode: string = 'agent'; // agent | plan
  autoCreatePR: boolean = true;
  workOnCurrentBranch: boolean = false;
  openAsCursorGithubApp: boolean = false;
  skipReviewerRequest: boolean = false;
  /** Optional display name. Empty = server derives from prompt. Max 100. */
  agentName: string = '';
  /** Index into selected model's variants; -1 = default / none. */
  selectedVariantIndex: number = -1;
  /** Chosen parameter pairs (effort / fast / …). Empty = omit. */
  selectedParams: ModelVariantParam[] = [];
  env: EnvTarget = defaultEnv();
  mcpServers: McpServerDef[] = [];
  subagents: CustomSubagentDef[] = [];
  envVars: EnvVarDef[] = [];
  busy: boolean = false;
  loadingMeta: boolean = false;
  errorMsg: string = '';
  repoQuery: string = '';
  /** Base64 / URL images for prompt.images — filled by page picker. */
  imagePayloads: Object[] = [];
  private prefsApplied: boolean = false;
  private retryAgentId: string = '';

  hydrateFromCache(): void {
    const cache = AgentCache.getInstance();
    this.repos = cache.loadRepos();
    this.models = cache.loadModels();
    if (this.selectedRepo.length === 0 && this.repos.length > 0) {
      this.selectedRepo = this.repos[0].repository;
    }
  }

  async loadMeta(_forceRepos: boolean = false): Promise<void> {
    this.errorMsg = '';
    const cache = AgentCache.getInstance();
    if (this.repos.length === 0) {
      this.repos = cache.loadRepos();
    }
    if (this.models.length === 0) {
      this.models = cache.loadModels();
    }
    this.loadingMeta = false;
    try {
      if (this.models.length === 0 || cache.isStale(cache.modelsFetchedAt())) {
        try {
          const modelResp = await CursorApiClient.getInstance().listModels();
          this.models = normalizeModels(modelResp);
          cache.saveModels(this.models);
        } catch (_e) {
          // models optional — default empty = Auto; keep stale cache if present
        }
      }

      // Apply persisted defaults once per VM lifetime.
      if (!this.prefsApplied) {
        const prefs = PrefStore.getInstance();
        if (this.selectedModel.length === 0) {
          const defModel = await prefs.getDefaultModel();
          if (defModel.length > 0) {
            this.selectedModel = defModel;
          }
        }
        this.autoCreatePR = await prefs.getDefaultAutoPR();
        const saved = parseToolsPref(await prefs.getLastTools());
        this.env = saved.env;
        this.mcpServers = saved.mcp;
        this.subagents = saved.subs;
        this.prefsApplied = true;
      }

      if (this.selectedRepo.length === 0 && this.repos.length > 0) {
        this.selectedRepo = this.repos[0].repository;
      }
    } catch (e) {
      if (e instanceof ApiException) {
        this.errorMsg = e.message;
      } else {
        this.errorMsg = '加载模型失败';
      }
      Log.error(TAG, this.errorMsg);
    }
  }

  /** GET /v1/repositories is 1/user/min. Only call from explicit UI (仓库 chip / pull / 刷新). */
  async refreshRepos(force: boolean = false): Promise<void> {
    const cache = AgentCache.getInstance();
    if (this.repos.length === 0) {
      this.repos = cache.loadRepos();
    }
    if (repoCooldownActive()) {
      if (force) {
        this.errorMsg = REPO_LIMIT_MSG;
      }
      return;
    }
    this.errorMsg = '';
    this.loadingMeta = true;
    try {
      this.repos = await fetchReposShared();
      if (this.selectedRepo.length === 0 && this.repos.length > 0) {
        this.selectedRepo = this.repos[0].repository;
      }
    } catch (e) {
      if (this.repos.length === 0 || force) {
        if (e instanceof ApiException) {
          this.errorMsg = e.code === 429 ? REPO_LIMIT_MSG : e.message;
        } else {
          this.errorMsg = '加载仓库失败';
        }
        Log.error(TAG, this.errorMsg);
      }
    } finally {
      this.loadingMeta = false;
    }
  }

  filteredRepos(): RepoInfo[] {
    const q = this.repoQuery.trim().toLowerCase();
    let list: RepoInfo[] = this.repos;
    if (q.length > 0) {
      list = this.repos.filter((r: RepoInfo) => {
        return r.repository.toLowerCase().indexOf(q) >= 0 ||
          r.name.toLowerCase().indexOf(q) >= 0 ||
          r.owner.toLowerCase().indexOf(q) >= 0;
      });
    }
    const agents = AgentCache.getInstance().loadInbox();
    const scored: RepoInfo[] = [];
    for (let i = 0; i < list.length; i++) {
      scored.push(list[i]);
    }
    scored.sort((a: RepoInfo, b: RepoInfo) => repoRecency(b, agents) - repoRecency(a, agents));
    return scored;
  }

  canSubmit(): boolean {
    if (this.busy || this.prompt.trim().length === 0) {
      return false;
    }
    if (this.env.kind !== 'default') {
      return usesNamedEnv(this.env);
    }
    if (this.repoMode === 'none') {
      return true;
    }
    if (this.repoMode === 'pr') {
      return this.selectedRepo.trim().length > 0 && this.selectedPrUrl.trim().length > 0;
    }
    return this.selectedRepo.trim().length > 0;
  }

  hideBranchChip(): boolean {
    return this.repoMode === 'none' || this.repoMode === 'pr' || usesNamedEnv(this.env);
  }

  setManualRepoUrl(url: string): void {
    const cleaned = url.trim();
    if (cleaned.length === 0) {
      return;
    }
    this.selectedRepo = cleaned;
  }

  titleFromPrompt(): string {
    const named = this.agentName.trim();
    if (named.length > 0) {
      return named.length > 40 ? named.substring(0, 40) : named;
    }
    let line = this.prompt.trim();
    const nl = line.indexOf('\n');
    if (nl >= 0) {
      line = line.substring(0, nl);
    }
    if (line.length > 28) {
      return line.substring(0, 28);
    }
    return line.length > 0 ? line : '新任务';
  }

  buildCreateBody(): Record<string, Object> {
    const body: Record<string, Object> = {};
    const promptObj: Record<string, Object> = {};
    promptObj['text'] = this.prompt.trim();
    if (this.imagePayloads.length > 0) {
      promptObj['images'] = this.imagePayloads;
    }
    body['prompt'] = promptObj;
    const namedTitle = this.agentName.trim();
    if (namedTitle.length > 0) {
      body['name'] = namedTitle.length > 100 ? namedTitle.substring(0, 100) : namedTitle;
    }
    body['mode'] = this.mode;
    body['autoCreatePR'] = this.autoCreatePR;
    body['workOnCurrentBranch'] = this.workOnCurrentBranch;
    if (this.autoCreatePR) {
      body['openAsCursorGithubApp'] = this.openAsCursorGithubApp;
      body['skipReviewerRequest'] = this.skipReviewerRequest;
    }
    const named = toApiEnv(this.env);
    if (named) {
      body['env'] = named;
    } else if (this.repoMode !== 'none') {
      const repo: Record<string, Object> = {};
      repo['url'] = this.selectedRepo.trim();
      if (this.repoMode === 'pr') {
        repo['prUrl'] = this.selectedPrUrl.trim();
      } else if (this.selectedBranch.trim().length > 0) {
        repo['startingRef'] = this.selectedBranch.trim();
      }
      body['repos'] = [repo];
    }
    const model = this.modelPayload();
    if (model) {
      body['model'] = model;
    }
    const mcp = toApiMcp(this.mcpServers);
    if (mcp.length > 0) {
      body['mcpServers'] = mcp;
    }
    const subs = toApiSubagents(this.subagents);
    if (subs.length > 0) {
      body['customSubagents'] = subs;
    }
    const vars = toApiEnvVars(this.envVars);
    if (vars) {
      body['envVars'] = vars;
    } else {
      if (this.retryAgentId.length === 0) {
        this.retryAgentId = mintAgentId();
      }
      body['agentId'] = this.retryAgentId;
    }
    return body;
  }

  async submit(): Promise<CreateAgentResponse | undefined> {
    if (!this.canSubmit()) {
      if (this.prompt.trim().length === 0) {
        this.errorMsg = '先写一下要做的事';
      } else if (this.env.kind !== 'default' && !usesNamedEnv(this.env)) {
        this.errorMsg = '命名环境需要填写名称';
      } else if (this.repoMode === 'pr') {
        this.errorMsg = 'PR 模式需要仓库 URL 和 PR 链接';
      } else if (this.repoMode === 'repo' && !usesNamedEnv(this.env)) {
        this.errorMsg = '请先选择或粘贴仓库 URL';
      }
      return undefined;
    }
    this.busy = true;
    this.errorMsg = '';
    try {
      const body = this.buildCreateBody();
      Log.info(TAG, `create model ${modelSentJson(this.modelPayload())}`);
      const raw = await CursorApiClient.getInstance().createAgent(body);
      const resp = unwrapCreateAgent(raw as object);
      Log.info(TAG, `created ${resp.agent?.id ?? ''}`);
      PrefStore.getInstance().setLastTools(serializeTools(this.env, this.mcpServers, this.subagents));
      this.retryAgentId = '';
      return resp;
    } catch (e) {
      if (e instanceof ApiException) {
        this.errorMsg = e.message;
      } else {
        this.errorMsg = '创建失败';
      }
      return undefined;
    } finally {
      this.busy = false;
    }
  }

  /** Follow-up / create: omit when empty so the server keeps the default. */
  modelPayload(): Record<string, Object> | undefined {
    if (this.selectedModel.length === 0) {
      return undefined;
    }
    const model: Record<string, Object> = {};
    model['id'] = this.selectedModel;
    const variantParams = this.resolveVariantParams();
    if (variantParams.length > 0) {
      model['params'] = variantParams;
    }
    return model;
  }

  /** Map selected params / variant index → API `model.params` array. */
  private resolveVariantParams(): Object[] {
    if (this.selectedParams.length > 0) {
      const model = findModel(this.models, this.selectedModel);
      const coerced = coerceParamsToVariant(model, this.selectedParams);
      return variantParamsToObjects(coerced);
    }
    if (this.selectedVariantIndex < 0 || this.selectedModel.length === 0) {
      return [];
    }
    for (let i = 0; i < this.models.length; i++) {
      const m = this.models[i];
      if (m.id !== this.selectedModel || !m.variants) {
        continue;
      }
      if (this.selectedVariantIndex >= m.variants.length) {
        return [];
      }
      const v = m.variants[this.selectedVariantIndex];
      return variantParamsToObjects(coerceParamsToVariant(m, v.params ?? []));
    }
    return [];
  }
}

function variantParamsToObjects(params: ModelVariantParam[]): Object[] {
  const out: Object[] = [];
  for (let i = 0; i < params.length; i++) {
    if (params[i].id === 'cyber') {
      continue;
    }
    const p: Record<string, Object> = {};
    p['id'] = params[i].id;
    p['value'] = params[i].value;
    out.push(p);
  }
  return out;
}

function repoCooldownActive(): boolean {
  const lastOk = AgentCache.getInstance().reposFetchedAt();
  const lastTry = Math.max(lastOk, lastReposAttemptAt);
  return lastTry > 0 && (Date.now() - lastTry) < REPO_COOLDOWN_MS;
}

async function fetchReposShared(): Promise<RepoInfo[]> {
  if (reposInFlight) {
    return reposInFlight;
  }
  lastReposAttemptAt = Date.now();
  reposInFlight = (async () => {
    try {
      const repoResp = await CursorApiClient.getInstance().listRepositories();
      const repos = normalizeRepos(repoResp);
      AgentCache.getInstance().saveRepos(repos);
      return repos;
    } finally {
      reposInFlight = undefined;
    }
  })();
  return reposInFlight;
}

function normalizeRepos(raw: object): RepoInfo[] {
  const r = raw as RepositoriesLoose;
  const list = r.repositories ?? r.items ?? r.data ?? [];
  const out: RepoInfo[] = [];
  for (let i = 0; i < list.length; i++) {
    const item = list[i];
    const repository = item.repository ?? item.url ?? '';
    if (repository.length === 0) {
      continue;
    }
    let owner = item.owner ?? '';
    let name = item.name ?? '';
    if ((!owner || !name) && repository.indexOf('/') >= 0) {
      const cleaned = repository.replace(/\.git$/, '');
      const parts = cleaned.split('/');
      name = parts[parts.length - 1];
      owner = parts[parts.length - 2] ?? '';
    }
    const info: RepoInfo = { owner: owner, name: name, repository: repository };
    out.push(info);
  }
  return out;
}

function normalizeModels(raw: object): ModelInfo[] {
  const list = unwrapModels(raw);
  if (list.length > 0) {
    for (let i = 0; i < list.length; i++) {
      const m = list[i];
      if (!m) {
        continue;
      }
      if (!m.displayName) {
        m.displayName = m.id;
      }
      m.params = normalizeParamDefs(m.params ?? m.parameters ?? []);
      if (m.variants && m.variants.length > 0) {
        m.variants = normalizeVariants(m.variants as Object[]);
      }
    }
    return list;
  }
  const r = raw as ModelsLoose;
  const loose = r.models ?? r.items ?? r.data ?? [];
  const out: ModelInfo[] = [];
  for (let i = 0; i < loose.length; i++) {
    const item = loose[i];
    const id = typeof item === 'string' ? item : (item.id ?? '');
    if (id.length === 0) {
      continue;
    }
    const info: ModelInfo = {
      id: id,
      displayName: typeof item === 'string' ? item : (item.displayName ?? id),
      params: typeof item === 'string' ? undefined :
        normalizeParamDefs((item.params ?? item.parameters ?? []) as Object[]),
      variants: typeof item === 'string' ? undefined : normalizeVariants(item.variants ?? []),
      aliases: typeof item === 'string' ? undefined : item.aliases,
      description: typeof item === 'string' ? undefined : item.description
    };
    out.push(info);
  }
  return out;
}

function normalizeParamDefs(raw: Object[]): ModelParamDef[] {
  const out: ModelParamDef[] = [];
  for (let i = 0; i < raw.length; i++) {
    const item = raw[i];
    if (!item) {
      continue;
    }
    const o = item as Record<string, Object>;
    const id = `${o['id'] ?? ''}`;
    if (id.length === 0) {
      continue;
    }
    const valuesRaw = (o['values'] ?? []) as Object[];
    const values: ModelParamValue[] = [];
    for (let j = 0; j < valuesRaw.length; j++) {
      const v = valuesRaw[j] as Record<string, Object>;
      const value = `${v['value'] ?? ''}`;
      if (value.length === 0) {
        continue;
      }
      values.push({
        value: value,
        displayName: v['displayName'] ? `${v['displayName']}` : undefined
      });
    }
    out.push({
      id: id,
      type: o['type'] ? `${o['type']}` : undefined,
      displayName: o['displayName'] ? `${o['displayName']}` : undefined,
      values: values
    });
  }
  return out;
}

function normalizeVariants(raw: Object[]): ModelVariant[] {
  const out: ModelVariant[] = [];
  for (let i = 0; i < raw.length; i++) {
    const item = raw[i];
    if (typeof item === 'string') {
      out.push({ displayName: item as string, params: [] });
      continue;
    }
    const o = item as Record<string, Object>;
    const paramsRaw = (o['params'] ?? []) as Object[];
    const params: ModelVariantParam[] = [];
    for (let j = 0; j < paramsRaw.length; j++) {
      const p = paramsRaw[j] as Record<string, Object>;
      params.push({ id: `${p['id'] ?? ''}`, value: `${p['value'] ?? ''}` });
    }
    out.push({
      displayName: o['displayName'] ? `${o['displayName']}` : undefined,
      isDefault: o['isDefault'] === true,
      params: params
    });
  }
  return out;
}

interface RepositoriesLoose {
  repositories?: RepoLoose[];
  items?: RepoLoose[];
  data?: RepoLoose[];
}

interface RepoLoose {
  owner?: string;
  name?: string;
  repository?: string;
  url?: string;
}

interface ModelsLoose {
  models?: (ModelLoose | string)[];
  items?: (ModelLoose | string)[];
  data?: (ModelLoose | string)[];
}

function repoRecency(r: RepoInfo, agents: AgentSummary[]): number {
  let best = 0;
  const key = `${r.owner}/${r.name}`.toLowerCase();
  const url = (r.repository ?? '').toLowerCase();
  for (let i = 0; i < agents.length; i++) {
    const repos = agents[i].repos;
    if (!repos || repos.length === 0) {
      continue;
    }
    const u = (repos[0].url ?? '').toLowerCase();
    if ((url.length > 0 && u.indexOf(url) >= 0) || (key.length > 1 && u.indexOf(key) >= 0)) {
      const t = recencyMs(agents[i]);
      if (t > best) {
        best = t;
      }
    }
  }
  return best;
}

function mintAgentId(): string {
  try {
    return `bc-${util.generateRandomUUID()}`;
  } catch (_e) {
    return `bc-${Date.now().toString(16)}-${Math.floor(Math.random() * 1e8).toString(16)}`;
  }
}

interface ModelLoose {
  id?: string;
  displayName?: string;
  variants?: Object[];
  aliases?: string[];
  description?: string;
  params?: Object[];
  parameters?: Object[];
}

export async function warmCreateMeta(): Promise<void> {
  if (!ApiKeyStore.getInstance().isUnlocked()) {
    return;
  }
  const cache = AgentCache.getInstance();
  if (cache.isStale(cache.modelsFetchedAt(), META_WARM_MS)) {
    try {
      const modelResp = await CursorApiClient.getInstance().listModels();
      cache.saveModels(normalizeModels(modelResp));
    } catch (_e) {
    }
  }
}
