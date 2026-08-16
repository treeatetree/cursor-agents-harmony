import { notificationManager } from '@kit.NotificationKit';
import { wantAgent } from '@kit.AbilityKit';
import { AgentSummary } from '../models/Api';
import { isRunInFlight } from './InboxGrouping';
import { Log } from './Log';

const TAG = 'LiveIsland';
const BUNDLE = 'com.brian.cursor.mobile';

/**
 * In-flight status as an ongoing notification.
 * Live View Kit is parked: this bundle has no AGC 实况窗 entitlement.
 */
export class LiveIsland {
  private static notifOn: boolean = false;
  private static ready: boolean = false;
  private static agentId: string = '';
  private static title: string = '';
  private static lastZh: string = '';

  static async start(agentId: string, name: string, statusZh: string): Promise<void> {
    if (!agentId || agentId.length === 0) {
      return;
    }
    if (LiveIsland.agentId === agentId && LiveIsland.notifOn && statusZh === LiveIsland.lastZh) {
      return;
    }
    if (LiveIsland.agentId.length > 0 && LiveIsland.agentId !== agentId) {
      await LiveIsland.finish(LiveIsland.lastZh, LiveIsland.agentId);
    }
    LiveIsland.agentId = agentId;
    LiveIsland.title = name.length > 0 ? name : 'Cursor Agent';
    LiveIsland.lastZh = statusZh;
    await LiveIsland.ensureReady();
    await LiveIsland.publishOngoing(statusZh);
  }

  static async update(statusZh: string): Promise<void> {
    if (LiveIsland.agentId.length === 0 || statusZh === LiveIsland.lastZh) {
      return;
    }
    LiveIsland.lastZh = statusZh;
    if (LiveIsland.notifOn) {
      await LiveIsland.publishOngoing(statusZh);
    }
  }

  static async finish(_statusZh: string, agentId: string = ''): Promise<void> {
    if (agentId.length > 0 && LiveIsland.agentId.length > 0 && agentId !== LiveIsland.agentId) {
      return;
    }
    if (LiveIsland.notifOn) {
      try {
        notificationManager.cancel(LiveIsland.nid());
      } catch (_e) {
      }
      LiveIsland.notifOn = false;
    }
    LiveIsland.agentId = '';
    LiveIsland.title = '';
    LiveIsland.lastZh = '';
  }

  /** Keep the notice on the newest in-flight inbox card. */
  static async syncRunning(agents: AgentSummary[]): Promise<void> {
    let pick: AgentSummary | undefined = undefined;
    for (let i = 0; i < agents.length; i++) {
      const st = `${agents[i].latestRunStatus ?? ''}`;
      if (isRunInFlight(st)) {
        pick = agents[i];
        break;
      }
    }
    if (!pick) {
      if (LiveIsland.notifOn) {
        await LiveIsland.finish(LiveIsland.lastZh.length > 0 ? LiveIsland.lastZh : '已完成');
      }
      return;
    }
    const zh = `${pick.latestRunStatus}` === 'CREATING' ? '创建中' : '运行中';
    await LiveIsland.start(pick.id, pick.name ?? '', zh);
  }

  private static nid(): number {
    return 41000 + (Math.abs(hashCode(LiveIsland.agentId)) % 9000);
  }

  private static async ensureReady(): Promise<void> {
    if (LiveIsland.ready) {
      return;
    }
    try {
      await notificationManager.requestEnableNotification();
    } catch (_e) {
    }
    try {
      await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION);
    } catch (_e) {
    }
    LiveIsland.ready = true;
  }

  private static async publishOngoing(statusZh: string): Promise<void> {
    try {
      const info: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: BUNDLE,
          moduleName: 'entry',
          abilityName: 'EntryAbility',
          parameters: { 'agentId': LiveIsland.agentId }
        }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: LiveIsland.nid()
      };
      const agent = await wantAgent.getWantAgent(info);
      const req: notificationManager.NotificationRequest = {
        id: LiveIsland.nid(),
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        isOngoing: true,
        isUnremovable: false,
        isAlertOnce: true,
        wantAgent: agent,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: LiveIsland.title,
            text: statusZh,
            additionalText: '点按回到任务'
          }
        }
      };
      await notificationManager.publish(req);
      LiveIsland.notifOn = true;
    } catch (e) {
      Log.warn(TAG, `ongoing notify failed: ${JSON.stringify(e)}`);
    }
  }
}

function hashCode(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) {
    h = ((h << 5) - h) + s.charCodeAt(i);
    h |= 0;
  }
  return h;
}
