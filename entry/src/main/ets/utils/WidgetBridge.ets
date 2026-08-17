import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { formBindingData, formProvider } from '@kit.FormKit';
import { AgentSummary } from '../models/Api';
import { Log } from './Log';
import { PrefStore } from '../store/PrefStore';

const TAG = 'WidgetBridge';
const PREF = 'cursor_widget';
const KEY_IDS = 'form_ids';
const KEY_RUN = 'running';
const KEY_NAME = 'latest_name';
const KEY_ST = 'latest_status';
const KEY_ID = 'latest_id';

export interface WidgetSnap {
  running: number;
  latestName: string;
  latestStatus: string;
  latestAgentId: string;
}

export class WidgetBridge {
  static snapFromInbox(agents: AgentSummary[], running: number): WidgetSnap {
    let name = '暂无任务';
    let status = '';
    let id = '';
    for (let i = 0; i < agents.length; i++) {
      const st = `${agents[i].latestRunStatus ?? ''}`;
      if (st === 'RUNNING' || st === 'CREATING') {
        name = PrefStore.getInstance().displayName(agents[i].id,
          agents[i].name.length > 0 ? agents[i].name : '未命名');
        status = '运行中';
        id = agents[i].id;
        return { running, latestName: name, latestStatus: status, latestAgentId: id };
      }
    }
    if (agents.length > 0) {
      name = PrefStore.getInstance().displayName(agents[0].id,
        agents[0].name.length > 0 ? agents[0].name : '未命名');
      status = widgetStatusZh(`${agents[0].latestRunStatus ?? agents[0].status}`);
      id = agents[0].id;
    }
    return { running, latestName: name, latestStatus: status, latestAgentId: id };
  }

  static bind(snap: WidgetSnap): formBindingData.FormBindingData {
    return formBindingData.createFormBindingData({
      'running': snap.running,
      'runningLine': snap.running > 0 ? `${snap.running} 个在跑` : '没有在跑的任务',
      'latestName': snap.latestName,
      'latestStatus': snap.latestStatus,
      'latestAgentId': snap.latestAgentId
    });
  }

  static emptyBind(): formBindingData.FormBindingData {
    return WidgetBridge.bind({
      running: 0,
      latestName: 'Cursor Agents',
      latestStatus: '打开查看',
      latestAgentId: ''
    });
  }

  static async publish(ctx: common.Context, snap: WidgetSnap): Promise<void> {
    try {
      const pref = await preferences.getPreferences(ctx, PREF);
      await pref.put(KEY_RUN, snap.running);
      await pref.put(KEY_NAME, snap.latestName);
      await pref.put(KEY_ST, snap.latestStatus);
      await pref.put(KEY_ID, snap.latestAgentId);
      await pref.flush();
      const ids = await WidgetBridge.formIds(ctx);
      for (let i = 0; i < ids.length; i++) {
        try {
          await formProvider.updateForm(ids[i], WidgetBridge.bind(snap));
        } catch (_e) {
        }
      }
    } catch (e) {
      Log.warn(TAG, `publish failed: ${JSON.stringify(e)}`);
    }
  }

  static async read(ctx: common.Context): Promise<WidgetSnap> {
    try {
      const pref = await preferences.getPreferences(ctx, PREF);
      return {
        running: (await pref.get(KEY_RUN, 0)) as number,
        latestName: (await pref.get(KEY_NAME, 'Cursor Agents')) as string,
        latestStatus: (await pref.get(KEY_ST, '打开查看')) as string,
        latestAgentId: (await pref.get(KEY_ID, '')) as string
      };
    } catch (_e) {
      return { running: 0, latestName: 'Cursor Agents', latestStatus: '打开查看', latestAgentId: '' };
    }
  }

  static async addForm(ctx: common.Context, formId: string): Promise<void> {
    if (formId.length === 0) {
      return;
    }
    const ids = await WidgetBridge.formIds(ctx);
    if (ids.indexOf(formId) >= 0) {
      return;
    }
    ids.push(formId);
    await WidgetBridge.saveIds(ctx, ids);
  }

  static async removeForm(ctx: common.Context, formId: string): Promise<void> {
    const ids = (await WidgetBridge.formIds(ctx)).filter((id: string) => id !== formId);
    await WidgetBridge.saveIds(ctx, ids);
  }

  static async formIds(ctx: common.Context): Promise<string[]> {
    try {
      const pref = await preferences.getPreferences(ctx, PREF);
      const raw = (await pref.get(KEY_IDS, '[]')) as string;
      return JSON.parse(raw) as string[];
    } catch (_e) {
      return [];
    }
  }

  private static async saveIds(ctx: common.Context, ids: string[]): Promise<void> {
    const pref = await preferences.getPreferences(ctx, PREF);
    await pref.put(KEY_IDS, JSON.stringify(ids));
    await pref.flush();
  }
}

function widgetStatusZh(raw: string): string {
  if (raw === 'RUNNING' || raw === 'CREATING') {
    return '运行中';
  }
  if (raw === 'FINISHED') {
    return '已完成';
  }
  if (raw === 'ERROR') {
    return '失败';
  }
  if (raw === 'CANCELLED') {
    return '已取消';
  }
  if (raw === 'EXPIRED') {
    return '已过期';
  }
  if (raw === 'ARCHIVED') {
    return '已归档';
  }
  return raw.length > 0 ? raw : '';
}
