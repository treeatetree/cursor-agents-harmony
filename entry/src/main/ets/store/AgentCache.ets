import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AgentDetail, AgentSummary, ArtifactInfo, ConversationMessage, RepoInfo, ModelInfo, Run,
  RunUsage } from '../models/Api';
import { TimelineItem } from '../models/Timeline';
import { Log } from '../utils/Log';
import { CacheCrypto } from './CacheCrypto';
import { capMessages, capTimeline, clipText, CACHE_SUMMARY_MAX } from '../utils/CacheLimit';

const TAG = 'AgentCache';
const LRU_MAX = 80;
const DISK_HARD_MAX = 2000;
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
  eventIdWatermark?: string;
  timelineRunId?: string;
  artifacts?: ArtifactInfo[];
  usageLabel?: string;
  usageRuns?: RunUsage[];
  extrasFetched?: boolean;
}

interface SummariesFile {
  schema: number;
  byId: Record<string, string>;
}

interface QueueImagesFile {
  schema: number;
  images: object[];
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
  private summaries: Record<string, string> = {};
  private summariesLoaded: boolean = false;

  static getInstance(): AgentCache {
    if (!AgentCache.instance) {
      AgentCache.instance = new AgentCache();
    }
    return AgentCache.instance;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    this.dir = `${context.filesDir}/cache`;
    try {
      fs.mkdirSync(this.dir);
    } catch (_e) {
      Log.info(TAG, `cache dir ready: ${this.dir}`);
    }
    await CacheCrypto.getInstance().init(context);
  }

  async wipeAll(): Promise<void> {
    this.agentMemIds = [];
    this.agentMemVals = [];
    this.inboxFile = undefined;
    this.summaries = {};
    this.sweepAgentFiles();
    this.sweepQueueDirs();
    this.safeUnlink('inbox.json');
    this.safeUnlink('index.json');
    this.safeUnlink('summaries.json');
    await CacheCrypto.getInstance().clear();
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

  /** kind=full replaces the unfiltered list. kind=merge updates by id and never shrinks to a filter remnant. */
  saveInbox(agents: AgentSummary[], kind: string = 'full'): void {
    if (kind === 'merge') {
      this.mergeInbox(agents);
      return;
    }
    const payload: InboxFile = {
      schema: 1,
      fetchedAt: Date.now(),
      agents: agents.slice(0, 100)
    };
    this.inboxFile = payload;
    this.writeJson('inbox.json', payload);
  }

  removeInboxId(agentId: string): void {
    const cur = this.loadInbox();
    const next: AgentSummary[] = [];
    for (let i = 0; i < cur.length; i++) {
      if (cur[i].id !== agentId) {
        next.push(cur[i]);
      }
    }
    if (next.length === cur.length) {
      return;
    }
    const fetchedAt = this.inboxFetchedAt();
    this.inboxFile = {
      schema: 1,
      fetchedAt: fetchedAt > 0 ? fetchedAt : Date.now(),
      agents: next
    };
    this.writeJson('inbox.json', this.inboxFile);
  }

  private mergeInbox(agents: AgentSummary[]): void {
    const cur = this.loadInbox();
    const byId: Record<string, AgentSummary> = {};
    const order: string[] = [];
    for (let i = 0; i < cur.length; i++) {
      byId[cur[i].id] = cur[i];
      order.push(cur[i].id);
    }
    for (let i = 0; i < agents.length; i++) {
      const a = agents[i];
      const prev = byId[a.id];
      if (prev) {
        byId[a.id] = a;
      } else {
        byId[a.id] = a;
        order.unshift(a.id);
      }
    }
    const next: AgentSummary[] = [];
    for (let i = 0; i < order.length; i++) {
      const row = byId[order[i]];
      if (row) {
        next.push(row);
      }
    }
    const fetchedAt = this.inboxFetchedAt();
    this.inboxFile = {
      schema: 1,
      fetchedAt: fetchedAt > 0 ? fetchedAt : Date.now(),
      agents: next.slice(0, 100)
    };
    this.writeJson('inbox.json', this.inboxFile);
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

  /** Memory-only preview — never hits agent_*.json (Inbox cards). */
  peekMemSummary(agentId: string): string {
    if (!agentId || agentId.length === 0) {
      return '';
    }
    const hit = this.memGet(agentId);
    if (hit && hit.timelineSummary && hit.timelineSummary.length > 0) {
      return hit.timelineSummary;
    }
    this.ensureSummaries();
    return this.summaries[agentId] ?? '';
  }

  hydrateSummaries(): void {
    this.ensureSummaries();
  }

  peekSummary(agentId: string): string {
    if (!agentId || agentId.length === 0) {
      return '';
    }
    const hit = this.memGet(agentId);
    if (hit && hit.timelineSummary && hit.timelineSummary.length > 0) {
      return hit.timelineSummary;
    }
    this.ensureSummaries();
    const indexed = this.summaries[agentId] ?? '';
    if (indexed.length > 0) {
      return indexed;
    }
    const disk = this.readJson<CachedAgentPayload>(this.agentFileName(agentId));
    if (disk && disk.timelineSummary && disk.timelineSummary.length > 0) {
      this.summaries[agentId] = disk.timelineSummary;
      this.writeSummaries();
      return disk.timelineSummary;
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
    if (messages && messages.length > 0) {
      payload.messages = capMessages(messages);
    } else if (prev?.messages && prev.messages.length > 0) {
      payload.messages = capMessages(prev.messages);
    } else if (messages) {
      payload.messages = capMessages(messages);
    }
    if (prev?.timeline && prev.timeline.length > 0) {
      payload.timeline = capTimeline(prev.timeline);
    }
    if (prev?.eventIdWatermark && prev.eventIdWatermark.length > 0) {
      payload.eventIdWatermark = prev.eventIdWatermark;
    }
    if (prev?.timelineRunId && prev.timelineRunId.length > 0) {
      payload.timelineRunId = prev.timelineRunId;
    }
    copyExtras(prev, payload);
    if (timelineSummary !== undefined) {
      payload.timelineSummary = clipText(timelineSummary, CACHE_SUMMARY_MAX);
    } else if (prev?.timelineSummary !== undefined) {
      payload.timelineSummary = clipText(prev.timelineSummary, CACHE_SUMMARY_MAX);
    }
    if (payload.timelineSummary && payload.timelineSummary.length > 0) {
      this.ensureSummaries();
      this.summaries[agentId] = payload.timelineSummary;
      this.writeSummaries();
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
    payload.timeline = capTimeline(items);
    if (prev?.timelineSummary !== undefined) {
      payload.timelineSummary = prev.timelineSummary;
    }
    if (prev?.eventIdWatermark && prev.eventIdWatermark.length > 0) {
      payload.eventIdWatermark = prev.eventIdWatermark;
    }
    if (prev?.timelineRunId && prev.timelineRunId.length > 0) {
      payload.timelineRunId = prev.timelineRunId;
    }
    copyExtras(prev, payload);
    this.memPut(agentId, payload);
    this.writeJson(this.agentFileName(agentId), payload);
    this.touchLru(agentId);
  }

  saveTimelineMeta(agentId: string, summary: string, eventId: string, runId: string,
    runStatus: string = ''): void {
    if (!agentId || agentId.length === 0) {
      return;
    }
    const prev = this.loadAgent(agentId);
    if (!prev) {
      return;
    }
    if (summary.length > 0) {
      prev.timelineSummary = clipText(summary, CACHE_SUMMARY_MAX);
      this.ensureSummaries();
      this.summaries[agentId] = summary;
      this.writeSummaries();
    }
    if (eventId.length > 0) {
      prev.eventIdWatermark = eventId;
    }
    if (runId.length > 0) {
      prev.timelineRunId = runId;
    }
    if (runStatus.length > 0 && prev.detail) {
      prev.detail.latestRunStatus = runStatus;
      if (runId.length > 0) {
        prev.detail.latestRunId = runId;
      }
      if (runStatus !== 'RUNNING' && runStatus !== 'CREATING') {
        prev.fetchedAt = Date.now();
      }
    }
    this.memPut(agentId, prev);
    this.writeJson(this.agentFileName(agentId), prev);
  }

  saveArtifacts(agentId: string, artifacts: ArtifactInfo[], usageLabel: string,
    usageRuns: RunUsage[], fetched: boolean = true): void {
    if (!agentId || agentId.length === 0) {
      return;
    }
    const prev = this.loadAgent(agentId);
    if (!prev) {
      return;
    }
    prev.artifacts = artifacts;
    prev.usageLabel = usageLabel;
    prev.usageRuns = usageRuns;
    if (fetched) {
      prev.extrasFetched = true;
    }
    this.memPut(agentId, prev);
    this.writeJson(this.agentFileName(agentId), prev);
  }

  saveQueueImages(agentId: string, images: object[]): void {
    if (!agentId || agentId.length === 0) {
      return;
    }
    const folder = this.queueDirName(agentId);
    this.ensureDir(this.pathOf(folder));
    const payload: QueueImagesFile = { schema: 1, images: images };
    this.writeJson(`${folder}/images.json`, payload);
  }

  loadQueueImages(agentId: string): object[] {
    if (!agentId || agentId.length === 0) {
      return [];
    }
    const data = this.readJson<QueueImagesFile>(`${this.queueDirName(agentId)}/images.json`);
    if (!data || !data.images) {
      return [];
    }
    return data.images;
  }

  clearQueueImages(agentId: string): void {
    if (!agentId || agentId.length === 0) {
      return;
    }
    this.safeUnlink(`${this.queueDirName(agentId)}/images.json`);
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
    this.safeUnlink('summaries.json');
    this.summaries = {};
    this.summariesLoaded = false;
    this.sweepAgentFiles();
    this.sweepQueueDirs();
    CacheCrypto.getInstance().clear().catch((e: Object) => {
      Log.warn(TAG, `crypto clear failed: ${JSON.stringify(e)}`);
    });
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

  trimMemory(): void {
    let keepId = '';
    try {
      keepId = `${AppStorage.get<string>('watchingAgentId') ?? ''}`;
      if (keepId.length === 0) {
        keepId = `${AppStorage.get<string>('streamingAgentId') ?? ''}`;
      }
    } catch (_e) {
      keepId = '';
    }
    if (keepId.length === 0) {
      this.agentMemIds = [];
      this.agentMemVals = [];
      return;
    }
    const hit = this.memGet(keepId);
    this.agentMemIds = hit ? [keepId] : [];
    this.agentMemVals = hit ? [hit] : [];
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
    this.writeJson('index.json', { schema: 1, order: next } as CacheIndex);
    this.pruneDisk(next);
  }

  private pruneDisk(order: string[]): void {
    if (order.length <= DISK_HARD_MAX) {
      return;
    }
    const drop: string[] = [];
    for (let i = order.length - 1; i >= 0 && drop.length < order.length - DISK_HARD_MAX; i--) {
      drop.push(order[i]);
    }
    if (drop.length === 0) {
      return;
    }
    const keep: string[] = [];
    for (let i = 0; i < order.length; i++) {
      let gone = false;
      for (let j = 0; j < drop.length; j++) {
        if (order[i] === drop[j]) {
          gone = true;
          break;
        }
      }
      if (gone) {
        this.safeUnlink(this.agentFileName(order[i]));
      } else {
        keep.push(order[i]);
      }
    }
    this.writeJson('index.json', { schema: 1, order: keep } as CacheIndex);
  }

  private queueDirName(agentId: string): string {
    const safe = agentId.replace(/\//g, '_').replace(/\\/g, '_');
    return `queue_${safe}`;
  }

  private ensureDir(path: string): void {
    try {
      fs.mkdirSync(path);
    } catch (_e) {
    }
  }

  private ensureSummaries(): void {
    if (this.summariesLoaded) {
      return;
    }
    const data = this.readJson<SummariesFile>('summaries.json');
    if (data && data.schema === 1 && data.byId) {
      this.summaries = data.byId;
    }
    this.summariesLoaded = true;
  }

  private writeSummaries(): void {
    this.summariesLoaded = true;
    this.writeJson('summaries.json', { schema: 1, byId: this.summaries } as SummariesFile);
  }

  private sweepQueueDirs(): void {
    if (!this.dir || this.dir.length === 0) {
      return;
    }
    try {
      const names = fs.listFileSync(this.dir);
      for (let i = 0; i < names.length; i++) {
        const n = names[i];
        if (n.indexOf('queue_') === 0) {
          this.safeUnlink(`${n}/images.json`);
        }
      }
    } catch (_e) {
    }
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
      const opened = this.shouldSeal(name) ? CacheCrypto.getInstance().open(text) : text;
      if (!opened || opened.length === 0) {
        return undefined;
      }
      return JSON.parse(opened) as T;
    } catch (_e) {
      return undefined;
    }
  }

  private writeJson(name: string, obj: object): void {
    try {
      const p = this.pathOf(name);
      const tmp = `${p}.tmp`;
      const raw = JSON.stringify(obj);
      const text = this.shouldSeal(name) ? CacheCrypto.getInstance().seal(raw) : raw;
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

  private shouldSeal(name: string): boolean {
    return name.indexOf('agent_') === 0 || name.indexOf('queue_') === 0 ||
      name.indexOf('images.json') >= 0;
  }

  private safeUnlink(name: string): void {
    try {
      fs.unlinkSync(this.pathOf(name));
    } catch (_e) {
      // ignore
    }
  }
}

function copyExtras(prev: CachedAgentPayload | undefined, payload: CachedAgentPayload): void {
  if (!prev) {
    return;
  }
  if (prev.artifacts) {
    payload.artifacts = prev.artifacts;
  }
  if (prev.usageLabel !== undefined) {
    payload.usageLabel = prev.usageLabel;
  }
  if (prev.usageRuns) {
    payload.usageRuns = prev.usageRuns;
  }
  if (prev.extrasFetched === true) {
    payload.extrasFetched = true;
  }
}
