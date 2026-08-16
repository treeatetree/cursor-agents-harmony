import { http } from '@kit.NetworkKit';
import {
  ApiErrorBody, ApiException, AgentsListResponse, ArtifactDownloadResponse,
  ArtifactsResponse, ConversationResponse, CreateAgentResponse, CreateRunResponse,
  MeResponse, Run, RunsListResponse, UsageResponse
} from '../models/Api';
import { ApiKeyStore } from '../store/ApiKeyStore';
import { Log } from '../utils/Log';

const TAG = 'CursorApi';
const BASE = 'https://api.cursor.com';
const RETRY_DELAYS_MS: number[] = [1000, 2000, 4000, 8000];
const MAX_RETRIES = 3;
const MAX_BACKOFF_MS = 30000;

export class CursorApiClient {
  private static instance: CursorApiClient | undefined = undefined;

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

  /** POST create — no auto-retry (avoid duplicate agents). */
  async createAgent(body: object): Promise<CreateAgentResponse> {
    return await this.request<CreateAgentResponse>('POST', '/v1/agents', body);
  }

  /** POST follow-up — no auto-retry (avoid duplicate runs). Keep unwrap. */
  async createRun(agentId: string, body: object): Promise<Run> {
    const resp = await this.request<CreateRunResponse>('POST',
      `/v1/agents/${encodeURIComponent(agentId)}/runs`, body);
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
  }

  async cancelRun(agentId: string, runId: string): Promise<object> {
    return await this.request<object>('POST',
      `/v1/agents/${encodeURIComponent(agentId)}/runs/${encodeURIComponent(runId)}/cancel`);
  }

  async archiveAgent(agentId: string): Promise<object> {
    return await this.request<object>('POST',
      `/v1/agents/${encodeURIComponent(agentId)}/archive`);
  }

  async unarchiveAgent(agentId: string): Promise<object> {
    return await this.request<object>('POST',
      `/v1/agents/${encodeURIComponent(agentId)}/unarchive`);
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
   * GET retry helper: on 429/5xx (ApiException.retryable), backoff 1/2/4/8s
   * capped at 30s, max 3 retries. Non-retryable errors throw immediately.
   */
  private async requestWithRetry<T>(method: http.RequestMethod | string, path: string,
    body?: object, overrideKey?: string): Promise<T> {
    let attempt = 0;
    while (true) {
      try {
        return await this.request<T>(method, path, body, overrideKey);
      } catch (e) {
        if (!(e instanceof ApiException) || !e.retryable || attempt >= MAX_RETRIES) {
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
    overrideKey?: string): Promise<T> {
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
        const errBody = JSON.parse(raw) as ApiErrorBody;
        if (errBody.error?.message) {
          message = errBody.error.message as string;
        } else if (errBody.message) {
          message = errBody.message as string;
        }
        if (errBody.error?.code) {
          apiCode = errBody.error.code as string;
        }
      } catch (_e) {
        if (raw && raw.length < 200) {
          message = raw;
        }
      }

      const retryable = code === 429 || code >= 500;
      if (code === 401) {
        message = 'API Key 无效或已过期';
      } else if (code === 403) {
        message = '无权限，请检查 Cursor 订阅计划';
      } else if (code === 429) {
        message = '请求过于频繁，请稍后重试';
      }
      throw new ApiException(code, message, apiCode, retryable);
    } catch (e) {
      if (e instanceof ApiException) {
        throw e;
      }
      Log.error(TAG, `network error: ${JSON.stringify(e)}`);
      throw new ApiException(0, '网络不可用，请检查连接', 'network', true);
    } finally {
      client.destroy();
    }
  }
}
