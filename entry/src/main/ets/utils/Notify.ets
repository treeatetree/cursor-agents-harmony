import { notificationManager } from '@kit.NotificationKit';
import { Want, wantAgent } from '@kit.AbilityKit';
import { Log } from './Log';

interface InboxLine {
  id: string;
  name: string;
  statusZh: string;
  snippet: string;
}

const TAG = 'Notify';
const SUMMARY_ID = 435552;

/**
 * Local notification when a Cloud Agent run finishes.
 * One inbox-style card lists every unread result; tap opens the in-app list.
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

  static async setBadge(count: number): Promise<void> {
    try {
      await notificationManager.setBadgeNumber(Math.max(0, count));
    } catch (_e) {
    }
  }

  /** @deprecated use setBadge — kept so older call sites compile during the cutover. */
  static async setRunningBadge(count: number): Promise<void> {
    await Notify.setBadge(count);
  }

  static isEnabled(): boolean {
    return Notify.enabled;
  }

  static async refreshInbox(items: InboxLine[]): Promise<void> {
    if (!Notify.enabled || items.length === 0) {
      try {
        await notificationManager.cancel(SUMMARY_ID);
      } catch (_e) {
      }
      return;
    }
    try {
      const title = items.length === 1 ?
        `${items[0].name} · ${items[0].statusZh}` :
        `${items.length} 条新结果`;
      const lines: string[] = [];
      for (let i = 0; i < items.length && i < 8; i++) {
        const it = items[i];
        const bit = it.snippet.length > 0 ? ` · ${it.snippet}` : '';
        lines.push(`${it.name} ${it.statusZh}${bit}`);
      }
      if (items.length > 8) {
        lines.push(`另有 ${items.length - 8} 条`);
      }
      const body = lines.length > 0 ? lines[0] : '点按查看全部';
      const launch: Want = {
        bundleName: 'com.brian.cursor.mobile',
        abilityName: 'EntryAbility',
        action: 'action.ohos.cursor.openInbox',
        uri: 'cursoragent://inbox',
        parameters: {
          'showUnread': '1'
        }
      };
      const info: wantAgent.WantAgentInfo = {
        wants: [launch],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: SUMMARY_ID,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent = await wantAgent.getWantAgent(info);
      const req: notificationManager.NotificationRequest = {
        id: SUMMARY_ID,
        wantAgent: agent,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_MULTILINE,
          multiLine: {
            title: title,
            text: body,
            additionalText: '点按查看全部',
            briefText: `${items.length} 条`,
            longTitle: title,
            lines: lines
          }
        }
      };
      await notificationManager.publish(req);
      for (let i = 0; i < items.length; i++) {
        try {
          await notificationManager.cancel(Math.abs(hashCode(items[i].id)) % 100000);
        } catch (_e) {
        }
      }
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
