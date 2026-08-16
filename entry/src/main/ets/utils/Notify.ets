import { notificationManager } from '@kit.NotificationKit';
import { wantAgent } from '@kit.AbilityKit';
import { Log } from './Log';

const TAG = 'Notify';

/**
 * Local notification when a Cloud Agent run finishes.
 * Best-effort across API levels — failures are swallowed.
 */
export class Notify {
  private static enabled: boolean = true;

  static setEnabled(v: boolean): void {
    Notify.enabled = v;
  }

  static async ensureChannel(): Promise<void> {
    try {
      await notificationManager.requestEnableNotification();
    } catch (_e) {
      // Already enabled or unavailable on this build.
    }
  }

  static async setRunningBadge(count: number): Promise<void> {
    try {
      await notificationManager.setBadgeNumber(Math.max(0, count));
    } catch (_e) {
    }
  }

  static async runFinished(agentName: string, statusZh: string, agentId: string): Promise<void> {
    if (!Notify.enabled) {
      return;
    }
    try {
      const title = agentName.length > 0 ? agentName : 'Cursor Agent';
      const info: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: 'com.brian.cursor.mobile',
          abilityName: 'EntryAbility',
          parameters: { 'agentId': agentId }
        }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: Math.abs(hashCode(agentId)) % 100000
      };
      const agent = await wantAgent.getWantAgent(info);
      const req: notificationManager.NotificationRequest = {
        id: Math.abs(hashCode(agentId)) % 100000,
        wantAgent: agent,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: `运行${statusZh}`,
            additionalText: '点按打开对话'
          }
        }
      };
      await notificationManager.publish(req);
    } catch (e) {
      Log.warn(TAG, `publish failed: ${JSON.stringify(e)}`);
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
