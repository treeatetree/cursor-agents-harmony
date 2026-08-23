import { http } from '@kit.NetworkKit';
import {
  ApiErrorDetail, ApiException, AgentsListResponse, ArtifactDownloadResponse,
  ArtifactsResponse, ConversationResponse, CreateAgentResponse, CreateRunResponse,
  MeResponse, Run, RunsListResponse, UsageResponse
} from '../models/Api';
import { ApiKeyStore } from '../store/ApiKeyStore';
import { Log } from '../utils/Log';
import { SessionDiag } from '../utils/SessionDiag';
import { mapHttpUserMessage } from '../utils/ApiErrorMap';

const TAG = 'CursorApi';
const BASE = 'https://api.cursor.com';
const EMPTY_BODY: Record<string, Object> = {};
const RETRY_DELAYS_MS: number[] = [1000, 2000, 4000, 8000];
const MAX_RETRIES = 3;
const MAX_BACKOFF_MS = 30000;

export class CursorApiClient {
  private static instance: CursorApiClient | undefined = undefined;
  private mutating: number = 0;

  static getInstance(): CursorApiClient {
    if (!CursorApiClient.instance) {
      CursorApiClient.instance = new CursorApiClient();
    }
    return CursorApiClient.instance;
  }

  async me(apiKey?: string): Promise<MeResponse> {
    return await this.requestWithRetry<MeResponse>('GET', '/v1/me', undefined, apiKey);
  }

  async listAgents(limit: number = 50, cursor?: string,
    includeArchived?: boolean, prUrl?: string): Promise<AgentsListResponse> {
    let path = `/v1/agents?limit=${limit}`;
    if (cursor && cursor.length > 0) {
      path = `${path}&cursor=${encodeURIComponent(cursor)}`;
    }
    if (includeArchived === true) {
      path = `${path}&includeArchived=true`;
    } else if (includeArchived === false) {
      path = `${path}&includeArchived=false`;
    }
    if (prUrl && prUrl.length > 0) {
      path = `${path}&prUrl=${encodeURIComponent(prUrl)}`;
    }
    return await this.requestWithRetry<AgentsListResponse>('GET', path);
  }

  async getAgent(agentId: string): Promise<object> {
    return await this.requestWithRetry<object>('GET', `/v1/agents/${encodeURIComponent(agentId)}`);
  }

  async getRuns(agentId: string, limit: number = 20, cursor?: string): Promise<RunsListResponse> {
    let path = `/v1/agents/${encodeURIComponent(agentId)}/runs?limit=${limit}`;
    if (cursor && cursor.length > 0) {
      path = `${path}&cursor=${encodeURIComponent(cursor)}`;
    }
    return await this.requestWithRetry<RunsListResponse>('GET', path);
  }

  async getRun(agentId: string, runId: string): Promise<Run> {
    return await this.requestWithRetry<Run>('GET',
      `/v1/agents/${encodeURIComponent(agentId)}/runs/${encodeURIComponent(runId)}`);
  }

  /**
   * Full chat transcript. v1 has no conversation endpoint; Cloud Agents expose
   * history on legacy `GET /v0/agents/{id}/conversation` (Bearer works).
   */
  async getConversation(agentId: string): Promise<ConversationResponse> {
    return await this.requestWithRetry<ConversationResponse>('GET',
      `/v0/agents/${encodeURIComponent(agentId)}/conversation`);
  }

  async listArtifacts(agentId: string): Promise<ArtifactsResponse> {
    return await this.requestWithRetry<ArtifactsResponse>('GET',
      `/v1/agents/${encodeURIComponent(agentId)}/artifacts`);
  }

  async downloadArtifact(agentId: string, path: string): Promise<ArtifactDownloadResponse> {
    const q = encodeURIComponent(path);
    return await this.requestWithRetry<ArtifactDownloadResponse>('GET',
      `/v1/agents/${encodeURIComponent(agentId)}/artifacts/download?path=${q}`);
  }

  async getUsage(agentId: string, runId?: string): Promise<UsageResponse> {
    let path = `/v1/agents/${encodeURIComponent(agentId)}/usage`;
    if (runId && runId.length > 0) {
      path = `${path}?runId=${encodeURIComponent(runId)}`;
    }
    return await this.requestWithRetry<UsageResponse>('GET', path);
  }

  /** True while a create/follow-up POST is in flight — Inbox must not poll then. */
  isMutating(): boolean {
    return this.mutating > 0;
  }

  /** POST create — no auto-retry (avoid duplicate agents). */
  async createAgent(body: object, idempotencyKey: string = ''): Promise<CreateAgentResponse> {
    this.mutating++;
    const started = Date.now();
    SessionDiag.emit({ tag: TAG, event: 'mutate', extra: `create begin n=${this.mutating}` });
    try {
      return await this.request<CreateAgentResponse>('POST', '/v1/agents', body, undefined, idempotencyKey);
    } finally {
      this.mutating--;
      SessionDiag.emit({
        tag: TAG,
        event: 'mutate',
        elapsedMs: Date.now() - started,
        extra: `create end n=${this.mutating}`
      });
    }
  }

  /** POST follow-up — no auto-retry (avoid duplicate runs). Keep unwrap. */
  async createRun(agentId: string, body: object, idempotencyKey: string = ''): Promise<Run> {
    this.mutating++;
    const started = Date.now();
    SessionDiag.emit({ tag: TAG, event: 'mutate', extra: `run begin n=${this.mutating}` });
    try {
      const resp = await this.request<CreateRunResponse>('POST',
        `/v1/agents/${encodeURIComponent(agentId)}/runs`, body, undefined, idempotencyKey);
    if (resp.run && resp.run.id) {
      return resp.run;
    }
    // Defensive: some gateways may flatten the Run.
    if (resp.id) {
      return {
        id: resp.id,
        agentId: resp.agentId ?? agentId,
        status: resp.status ?? 'CREATING',
        createdAt: resp.createdAt ?? '',
        updatedAt: resp.updatedAt ?? ''
      };
    }
    throw new ApiException(500, '创建 Run 响应缺少 id', 'invalid_create_run', true);
    } finally {
      this.mutating--;
      SessionDiag.emit({
        tag: TAG,
        event: 'mutate',
        elapsedMs: Date.now() - started,
        extra: `run end n=${this.mutating}`
      });
    }
  }

  async cancelRun(agentId: string, runId: string): Promise<object> {
    return await this.request<object>('POST',
      `/v1/agents/${encodeURIComponent(agentId)}/runs/${encodeURIComponent(runId)}/cancel`, EMPTY_BODY);
  }

  async archiveAgent(agentId: string): Promise<object> {
    return await this.request<object>('POST',
      `/v1/agents/${encodeURIComponent(agentId)}/archive`, EMPTY_BODY);
  }

  async unarchiveAgent(agentId: string): Promise<object> {
    return await this.request<object>('POST',
      `/v1/agents/${encodeURIComponent(agentId)}/unarchive`, EMPTY_BODY);
  }

  async deleteAgent(agentId: string): Promise<object> {
    return await this.request<object>('DELETE', `/v1/agents/${encodeURIComponent(agentId)}`);
  }

  async listModels(): Promise<object> {
    return await this.requestWithRetry<object>('GET', '/v1/models');
  }

  async listRepositories(): Promise<object> {
    return await this.requestWithRetry<object>('GET', '/v1/repositories');
  }

  /**
   * GET retry helper: on 5xx (ApiException.retryable), backoff 1/2/4/8s
   * capped at 30s, max 3 retries. 429 is not retried — repo list is 1/min,
   * short retries burn the quota and surface as「请求繁忙」.
   */
  private async requestWithRetry<T>(method: http.RequestMethod | string, path: string,
    body?: object, overrideKey?: string): Promise<T> {
    let attempt = 0;
    while (true) {
      try {
        return await this.request<T>(method, path, body, overrideKey, '');
      } catch (e) {
        const rateLimited = e instanceof ApiException && e.code === 429;
        if (!(e instanceof ApiException) || rateLimited || !e.retryable || attempt >= MAX_RETRIES) {
          if (e instanceof ApiException) {
            throw e;
          }
          throw new ApiException(0, 'request failed', 'request_failed', true);
        }
        const base = RETRY_DELAYS_MS[Math.min(attempt, RETRY_DELAYS_MS.length - 1)];
        const delay = Math.min(base, MAX_BACKOFF_MS);
        Log.warn(TAG, `retry ${attempt + 1}/${MAX_RETRIES} after ${delay}ms: ${method} ${path}`);
        await this.sleep(delay);
        attempt++;
      }
    }
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  private async request<T>(method: http.RequestMethod | string, path: string, body?: object,
    overrideKey?: string, idempotencyKey: string = ''): Promise<T> {
    const key = overrideKey && overrideKey.length > 0 ? overrideKey : ApiKeyStore.getInstance().getKey();
    if (!key) {
      // Not a server 401 — key may still be locked in HUKS. Callers must not treat this as expired.
      throw new ApiException(0, '未配置 API Key', 'no_api_key', false);
    }

    const client = http.createHttp();
    const url = `${BASE}${path}`;
    const headers: Record<string, string> = {};
    headers['Authorization'] = `Bearer ${key}`;
    headers['Accept'] = 'application/json';
    headers['Content-Type'] = 'application/json';
    headers['User-Agent'] = 'CursorHarmonyNative/1.0';
    if (idempotencyKey.length > 0) {
      headers['Idempotency-Key'] = idempotencyKey;
    }

    const started = Date.now();
    try {
      Log.info(TAG, `${method} ${path}`);
      const extra: http.HttpRequestOptions = {
        method: method as http.RequestMethod,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 60000,
        usingProtocol: http.HttpProtocol.HTTP1_1
      };
      if (body !== undefined) {
        extra.extraData = JSON.stringify(body);
      }
      const resp = await client.request(url, extra);
      const elapsedMs = Date.now() - started;
      const code = resp.responseCode;
      const raw = typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result);

      if (code >= 200 && code < 300) {
        if (!raw || raw.length === 0) {
          return JSON.parse('{}') as T;
        }
        return JSON.parse(raw) as T;
      }

      let message = `HTTP ${code}`;
      let apiCode = '';
      try {
        const errBody = JSON.parse(raw) as Record<string, Object>;
        const errField = errBody['error'];
        if (typeof errField === 'string' && `${errField}`.length > 0) {
          message = `${errField}`;
        } else if (errField) {
          const detail = errField as ApiErrorDetail;
          if (detail?.message) {
            message = detail.message as string;
          }
          if (detail?.code) {
            apiCode = detail.code as string;
          }
        }
        if (errBody['message']) {
          message = `${errBody['message']}`;
        }
      } catch (_e) {
        if (raw && raw.length < 200) {
          message = raw;
        }
      }
      Log.warn(TAG, `${method} ${path} -> ${code} ${message}`);
      SessionDiag.emit({
        tag: TAG,
        event: 'http',
        elapsedMs: elapsedMs,
        extra: `${method} ${path} ${code}${apiCode.length > 0 ? ` ${apiCode}` : ''} ${clipDiag(message, 160)}`
      });

      const retryable = code >= 500;
      message = mapHttpUserMessage(`${method}`, path, code, apiCode, message);
      throw new ApiException(code, message, apiCode, retryable);
    } catch (e) {
      if (e instanceof ApiException) {
        throw e;
      }
      Log.error(TAG, `network error: ${JSON.stringify(e)}`);
      SessionDiag.emit({
        tag: TAG,
        event: 'http',
        elapsedMs: Date.now() - started,
        extra: `${method} ${path} network`
      });
      throw new ApiException(0, '网络不可用，请检查连接', 'network', true);
    } finally {
      client.destroy();
    }
  }
}

function clipDiag(s: string, max: number): string {
  const t = s.replace(/\n/g, ' ').trim();
  if (t.length <= max) {
    return t;
  }
  return t.substring(0, max);
}
