import { liveViewManager } from '@kit.LiveViewKit';
import { notificationManager } from '@kit.NotificationKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { Log } from './Log';

const TAG = 'LiveIsland';
const BUNDLE = 'com.brian.cursor.mobile';

/**
 * Status-bar live capsule (灵动岛/实况窗) while a Cloud Agent run is in flight.
 * Falls back to an ongoing notification if Live View Kit is not entitled.
 */
export class LiveIsland {
  private static seq: number = 1;
  private static liveOn: boolean = false;
  private static notifOn: boolean = false;
  private static agentId: string = '';
  private static title: string = '';
  private static lastZh: string = '';

  static async start(agentId: string, name: string, statusZh: string): Promise<void> {
    LiveIsland.agentId = agentId;
    LiveIsland.title = name.length > 0 ? name : 'Cursor Agent';
    LiveIsland.lastZh = statusZh;
    const ok = await LiveIsland.tryLive('start', statusZh);
    if (!ok) {
      await LiveIsland.publishOngoing(statusZh, false);
    }
  }

  static async update(statusZh: string): Promise<void> {
    if (LiveIsland.agentId.length === 0 || statusZh === LiveIsland.lastZh) {
      return;
    }
    LiveIsland.lastZh = statusZh;
    if (LiveIsland.liveOn) {
      const ok = await LiveIsland.tryLive('update', statusZh);
      if (!ok) {
        await LiveIsland.publishOngoing(statusZh, false);
      }
      return;
    }
    if (LiveIsland.notifOn) {
      await LiveIsland.publishOngoing(statusZh, false);
    }
  }

  static async finish(statusZh: string): Promise<void> {
    if (LiveIsland.liveOn) {
      await LiveIsland.tryLive('stop', statusZh);
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

  private static nid(): number {
    return 41000 + (Math.abs(hashCode(LiveIsland.agentId)) % 9000);
  }

  private static async tryLive(op: string, statusZh: string): Promise<boolean> {
    try {
      const enabled = await liveViewManager.isLiveViewEnabled();
      if (!enabled) {
        return false;
      }
      LiveIsland.seq += 1;
      const capsule: liveViewManager.TextCapsule = {
        type: liveViewManager.CapsuleType.CAPSULE_TYPE_TEXT,
        status: op === 'stop' ? 0 : 1,
        title: LiveIsland.shortTitle(),
        content: statusZh,
        backgroundColor: '#18181B'
      };
      let click: WantAgent | undefined = undefined;
      try {
        click = await wantAgent.getWantAgent({
          wants: [{
            bundleName: BUNDLE,
            abilityName: 'EntryAbility',
            parameters: { 'agentId': LiveIsland.agentId }
          }],
          operationType: wantAgent.OperationType.START_ABILITY,
          requestCode: LiveIsland.nid()
        });
      } catch (_e) {
      }
      const primary: liveViewManager.PrimaryData = {
        title: LiveIsland.title,
        content: [{ text: `运行${statusZh}` }],
        keepTime: op === 'stop' ? 8 : 3600,
        liveViewLockScreenAbilityName: 'LiveViewLockAbility',
        liveViewLockScreenAbilityParameters: {
          'title': LiveIsland.title,
          'status': statusZh,
          'agentId': LiveIsland.agentId
        }
      };
      if (click) {
        primary.clickAction = click;
      }
      const view: liveViewManager.LiveView = {
        id: LiveIsland.nid(),
        event: 'COMMON',
        sequence: LiveIsland.seq,
        isMute: true,
        liveViewData: {
          primary: primary,
          capsule: capsule
        }
      };
      if (op === 'start') {
        await liveViewManager.startLiveView(view);
        LiveIsland.liveOn = true;
      } else if (op === 'update') {
        await liveViewManager.updateLiveView(view);
      } else {
        await liveViewManager.stopLiveView(view);
        LiveIsland.liveOn = false;
      }
      return true;
    } catch (e) {
      Log.warn(TAG, `live ${op} failed: ${JSON.stringify(e)}`);
      LiveIsland.liveOn = false;
      return false;
    }
  }

  private static shortTitle(): string {
    const t = LiveIsland.title;
    if (t.length <= 10) {
      return t;
    }
    return `${t.substring(0, 9)}…`;
  }

  private static async publishOngoing(statusZh: string, silent: boolean): Promise<void> {
    try {
      const info: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: BUNDLE,
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
        wantAgent: agent,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: LiveIsland.title,
            text: `运行${statusZh}`,
            additionalText: '点按回到对话'
          }
        }
      };
      if (silent) {
        req.isAlertOnce = true;
      }
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
