import { http } from '@kit.NetworkKit';
import { ArtifactInfo, RunUsage } from '../models/Api';
import { unwrapArtifacts, unwrapUsageRuns } from '../api/ApiUnwrap';
import { CursorApiClient } from '../api/CursorApiClient';
import { CACHE_TEXT_MAX, clipText } from '../utils/CacheLimit';
import { formatUsageFriendly } from '../utils/DisplayFmt';
import { Log } from '../utils/Log';
import { isSafeHttpsUrl } from '../utils/SafeUrl';
import { SessionDiag } from '../utils/SessionDiag';

const TAG = 'ArtifactSvc';

export interface ArtifactBundle {
  artifacts: ArtifactInfo[];
  usageLabel: string;
  usageRuns: RunUsage[];
  artifactsOk: boolean;
  usageOk: boolean;
}

export class ArtifactService {
  async load(agentId: string): Promise<ArtifactBundle> {
    const out: ArtifactBundle = {
      artifacts: [],
      usageLabel: '',
      usageRuns: [],
      artifactsOk: false,
      usageOk: false
    };
    try {
      const arts = await CursorApiClient.getInstance().listArtifacts(agentId);
      const rec = arts as object as Record<string, Object>;
      const keys = Object.keys(rec).join(',');
      out.artifacts = unwrapArtifacts(arts as object);
      out.artifactsOk = true;
      const first = out.artifacts.length > 0 ? (out.artifacts[0].path ?? '') : '';
      SessionDiag.emit({
        tag: TAG,
        event: 'artifacts_list',
        agentId: agentId,
        extra: `keys=${keys} n=${out.artifacts.length} first=${first}`
      });
    } catch (e) {
      Log.warn(TAG, `artifacts failed: ${JSON.stringify(e)}`);
      SessionDiag.emit({
        tag: TAG,
        event: 'artifacts_list',
        agentId: agentId,
        extra: `fail=${JSON.stringify(e)}`
      });
    }
    try {
      const usage = await CursorApiClient.getInstance().getUsage(agentId);
      out.usageLabel = formatUsageFriendly(usage as object);
      out.usageRuns = unwrapUsageRuns(usage as object);
      out.usageOk = true;
    } catch (e) {
      Log.warn(TAG, `usage failed: ${JSON.stringify(e)}`);
    }
    return out;
  }

  async downloadUrl(agentId: string, path: string): Promise<string> {
    const resp = await CursorApiClient.getInstance().downloadArtifact(agentId, path);
    return resp.url ?? '';
  }

  async readText(agentId: string, path: string): Promise<string> {
    const url = await this.downloadUrl(agentId, path);
    if (!isSafeHttpsUrl(url)) {
      SessionDiag.emit({
        tag: TAG,
        event: 'artifact_read',
        agentId: agentId,
        extra: `badUrl path=${path} urlLen=${url.length}`
      });
      return '';
    }
    const client = http.createHttp();
    try {
      const resp = await client.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 30000,
        usingProtocol: http.HttpProtocol.HTTP1_1
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        SessionDiag.emit({
          tag: TAG,
          event: 'artifact_read',
          agentId: agentId,
          extra: `http=${resp.responseCode} path=${path}`
        });
        return '';
      }
      const raw = typeof resp.result === 'string' ? resp.result : `${resp.result ?? ''}`;
      return clipText(raw, CACHE_TEXT_MAX);
    } catch (e) {
      Log.warn(TAG, `readText failed: ${JSON.stringify(e)}`);
      SessionDiag.emit({
        tag: TAG,
        event: 'artifact_read',
        agentId: agentId,
        extra: `fail path=${path}`
      });
      return '';
    } finally {
      client.destroy();
    }
  }
}
