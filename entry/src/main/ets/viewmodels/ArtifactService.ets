import { ArtifactInfo, RunUsage } from '../models/Api';
import { unwrapUsageRuns } from '../api/ApiUnwrap';
import { CursorApiClient } from '../api/CursorApiClient';
import { formatUsageFriendly } from '../utils/DisplayFmt';
import { Log } from '../utils/Log';

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
      out.artifacts = arts.items ?? [];
      out.artifactsOk = true;
    } catch (e) {
      Log.warn(TAG, `artifacts failed: ${JSON.stringify(e)}`);
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
}
