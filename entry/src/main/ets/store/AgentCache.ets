import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AgentDetail, AgentSummary, ConversationMessage, RepoInfo, ModelInfo, Run } from '../models/Api';
import { TimelineItem } from '../models/Timeline';
import { Log } from '../utils/Log';

const TAG = 'AgentCache';
const LRU_MAX = 20;
const STALE_24H_MS = 24 * 60 * 60 * 1000;

interface InboxFile {
  schema: number;
  fetchedAt: number;
  agents: AgentSummary[];
}

interface ReposFile {
  schema: number;
  fetchedAt: number;
  repos: RepoInfo[];
}

interface ModelsFile {
  schema: number;
  fetchedAt: number;
  models: ModelInfo[];
}

export interface CachedAgentPayload {
  schema: number;
  fetchedAt: number;
  detail?: AgentDetail;
  runs?: Run[];
  messages?: ConversationMessage[];
  timeline?: TimelineItem[];
  timelineSummary?: string;
}

interface CacheIndex {
  schema: number;
  order: string[]; // most-recently-used first
}

export class AgentCache {
  private static instance: AgentCache | undefined = undefined;
  private dir: string = '';
  private inboxFile: InboxFile | undefined = undefined;
  private reposFile: ReposFile | undefined = undefined;
  private modelsFile: ModelsFile | undefined = undefined;
  private agentMemIds: string[] = [];
  private agentMemVals: CachedAgentPayload[] = [];

  static getInstance(): AgentCache {
    if (!AgentCache.instance) {
      AgentCache.instance = new AgentCache();
    }
    return AgentCache.instance;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    this.dir = `${context.filesDir}/cache`;
    try {
      // accessSync throws when missing on some API levels — always try mkdir.
      fs.mkdirSync(this.dir);
    } catch (_e) {
      try {
        // already exists or need parent — ignore
        Log.info(TAG, `cache dir ready: ${this.dir}`);
      } catch (__e) {
        Log.warn(TAG, 'mkdir cache skipped');
      }
    }
  }

  loadInbox(): AgentSummary[] {
    const data = this.readInboxFile();
    if (!data || data.schema !== 1 || !data.agents) {
      return [];
    }
    return data.agents;
  }

  inboxFetchedAt(): number {
    const data = this.readInboxFile();
    return data ? data.fetchedAt : 0;
  }

  saveInbox(agents: AgentSummary[]): void {
    const payload: InboxFile = {
      schema: 1,
      fetchedAt: Date.now(),
      agents: agents.slice(0, 100)
    };
    this.inboxFile = payload;
    this.writeJson('inbox.json', payload);
  }

  loadRepos(): RepoInfo[] {
    const data = this.readReposFile();
    if (!data || data.schema !== 1 || !data.repos) {
      return [];
    }
    return data.repos;
  }

  reposFetchedAt(): number {
    const data = this.readReposFile();
    return data ? data.fetchedAt : 0;
  }

  saveRepos(repos: RepoInfo[]): void {
    const payload: ReposFile = { schema: 1, fetchedAt: Date.now(), repos: repos };
    this.reposFile = payload;
    this.writeJson('repos.json', payload);
  }

  loadModels(): ModelInfo[] {
    const data = this.readModelsFile();
    if (!data || data.schema !== 1 || !data.models) {
      return [];
    }
    return data.models;
  }

  modelsFetchedAt(): number {
    const data = this.readModelsFile();
    return data ? data.fetchedAt : 0;
  }

  saveModels(models: ModelInfo[]): void {
    const payload: ModelsFile = { schema: 1, fetchedAt: Date.now(), models: models };
    this.modelsFile = payload;
    this.writeJson('models.json', payload);
  }

  /** True when fetchedAt is missing/zero or older than ttlMs (default 24h). */
  isStale(fetchedAt: number, ttlMs: number = STALE_24H_MS): boolean {
    if (!fetchedAt || fetchedAt <= 0) {
      return true;
    }
    return (Date.now() - fetchedAt) > ttlMs;
  }

  loadAgent(agentId: string): CachedAgentPayload | undefined {
    if (!agentId || agentId.length === 0) {
      return undefined;
    }
    const hit = this.memGet(agentId);
    if (hit) {
      return hit;
    }
    const data = this.readJson<CachedAgentPayload>(this.agentFileName(agentId));
    if (!data || data.schema !== 1) {
      return undefined;
    }
    this.memPut(agentId, data);
    return data;
  }

  /** Memory-only preview — never hits disk (Inbox cards). */
  peekMemSummary(agentId: string): string {
    const hit = this.memGet(agentId);
    if (hit && hit.timelineSummary && hit.timelineSummary.length > 0) {
      return hit.timelineSummary;
    }
    return '';
  }

  saveAgent(agentId: string, detail?: AgentDetail, runs?: Run[], timelineSummary?: string,
    messages?: ConversationMessage[]): void {
    if (!agentId || agentId.length === 0) {
      return;
    }
    const prev = this.loadAgent(agentId);
    const payload: CachedAgentPayload = {
      schema: 1,
      fetchedAt: Date.now()
    };
    if (detail) {
      payload.detail = detail;
    } else if (prev?.detail) {
      payload.detail = prev.detail;
    }
    if (runs) {
      payload.runs = runs;
    } else if (prev?.runs) {
      payload.runs = prev.runs;
    }
    if (messages) {
      payload.messages = messages;
    } else if (prev?.messages) {
      payload.messages = prev.messages;
    }
    if (prev?.timeline && prev.timeline.length > 0) {
      payload.timeline = prev.timeline;
    }
    if (timelineSummary !== undefined) {
      payload.timelineSummary = timelineSummary;
    } else if (prev?.timelineSummary !== undefined) {
      payload.timelineSummary = prev.timelineSummary;
    }
    this.memPut(agentId, payload);
    this.writeJson(this.agentFileName(agentId), payload);
    this.touchLru(agentId);
  }

  saveTimeline(agentId: string, items: TimelineItem[]): void {
    if (!agentId || agentId.length === 0) {
      return;
    }
    const prev = this.loadAgent(agentId);
    const payload: CachedAgentPayload = {
      schema: 1,
      fetchedAt: prev?.fetchedAt ?? Date.now()
    };
    if (prev?.detail) {
      payload.detail = prev.detail;
    }
    if (prev?.runs) {
      payload.runs = prev.runs;
    }
    if (prev?.messages) {
      payload.messages = prev.messages;
    }
    payload.timeline = items.slice();
    if (prev?.timelineSummary !== undefined) {
      payload.timelineSummary = prev.timelineSummary;
    }
    this.memPut(agentId, payload);
    this.writeJson(this.agentFileName(agentId), payload);
    this.touchLru(agentId);
  }

  clearAll(): void {
    this.inboxFile = undefined;
    this.reposFile = undefined;
    this.modelsFile = undefined;
    this.agentMemIds = [];
    this.agentMemVals = [];
    this.safeUnlink('inbox.json');
    this.safeUnlink('repos.json');
    this.safeUnlink('models.json');
    // Prefer index-tracked agent files; also sweep directory for leftovers.
    const index = this.readIndex();
    for (let i = 0; i < index.order.length; i++) {
      this.safeUnlink(this.agentFileName(index.order[i]));
    }
    this.safeUnlink('index.json');
    this.sweepAgentFiles();
  }

  private readInboxFile(): InboxFile | undefined {
    if (this.inboxFile) {
      return this.inboxFile;
    }
    const data = this.readJson<InboxFile>('inbox.json');
    if (data) {
      this.inboxFile = data;
    }
    return data;
  }

  private readReposFile(): ReposFile | undefined {
    if (this.reposFile) {
      return this.reposFile;
    }
    const data = this.readJson<ReposFile>('repos.json');
    if (data) {
      this.reposFile = data;
    }
    return data;
  }

  private readModelsFile(): ModelsFile | undefined {
    if (this.modelsFile) {
      return this.modelsFile;
    }
    const data = this.readJson<ModelsFile>('models.json');
    if (data) {
      this.modelsFile = data;
    }
    return data;
  }

  private memGet(agentId: string): CachedAgentPayload | undefined {
    for (let i = 0; i < this.agentMemIds.length; i++) {
      if (this.agentMemIds[i] === agentId) {
        return this.agentMemVals[i];
      }
    }
    return undefined;
  }

  private memPut(agentId: string, payload: CachedAgentPayload): void {
    for (let i = 0; i < this.agentMemIds.length; i++) {
      if (this.agentMemIds[i] === agentId) {
        this.agentMemVals[i] = payload;
        return;
      }
    }
    this.agentMemIds.unshift(agentId);
    this.agentMemVals.unshift(payload);
    while (this.agentMemIds.length > LRU_MAX) {
      this.agentMemIds.pop();
      this.agentMemVals.pop();
    }
  }

  private agentFileName(agentId: string): string {
    // Sanitize path separators from id.
    const safe = agentId.replace(/\//g, '_').replace(/\\/g, '_');
    return `agent_${safe}.json`;
  }

  private touchLru(agentId: string): void {
    const index = this.readIndex();
    const next: string[] = [agentId];
    for (let i = 0; i < index.order.length; i++) {
      if (index.order[i] !== agentId) {
        next.push(index.order[i]);
      }
    }
    // Evict beyond LRU_MAX.
    while (next.length > LRU_MAX) {
      const evicted = next.pop();
      if (evicted && evicted.length > 0) {
        this.safeUnlink(this.agentFileName(evicted));
      }
    }
    this.writeJson('index.json', { schema: 1, order: next } as CacheIndex);
  }

  private readIndex(): CacheIndex {
    const data = this.readJson<CacheIndex>('index.json');
    if (!data || data.schema !== 1 || !data.order) {
      return { schema: 1, order: [] };
    }
    return data;
  }

  private sweepAgentFiles(): void {
    if (!this.dir || this.dir.length === 0) {
      return;
    }
    try {
      const names = fs.listFileSync(this.dir);
      for (let i = 0; i < names.length; i++) {
        const n = names[i];
        if (n.indexOf('agent_') === 0 && n.indexOf('.json') > 0) {
          this.safeUnlink(n);
        }
      }
    } catch (_e) {
      // listFile may be unavailable — ignore
    }
  }

  private pathOf(name: string): string {
    return `${this.dir}/${name}`;
  }

  private readJson<T>(name: string): T | undefined {
    try {
      const p = this.pathOf(name);
      const file = fs.openSync(p, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(p);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);
      const text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
      return JSON.parse(text) as T;
    } catch (_e) {
      return undefined;
    }
  }

  private writeJson(name: string, obj: object): void {
    try {
      const p = this.pathOf(name);
      const tmp = `${p}.tmp`;
      const text = JSON.stringify(obj);
      const bytes = new util.TextEncoder().encodeInto(text);
      const file = fs.openSync(tmp, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, bytes.buffer);
      fs.closeSync(file);
      try {
        fs.unlinkSync(p);
      } catch (_e) {
        // first write
      }
      fs.renameSync(tmp, p);
    } catch (e) {
      Log.warn(TAG, `write ${name} failed`);
    }
  }

  private safeUnlink(name: string): void {
    try {
      fs.unlinkSync(this.pathOf(name));
    } catch (_e) {
      // ignore
    }
  }
}
