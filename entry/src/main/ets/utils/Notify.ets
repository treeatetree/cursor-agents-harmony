import { notificationManager } from '@kit.NotificationKit';
import { Want, wantAgent } from '@kit.AbilityKit';
import { Log } from './Log';
import { SessionDiag } from './SessionDiag';

interface InboxLine {
  id: string;
  name: string;
  statusZh: string;
  snippet: string;
  repo?: string;
}

const TAG = 'Notify';
const SUMMARY_ID = 435552;

/**
 * Local notification when a Cloud Agent run finishes.
 * One unread → open that session. Several → Inbox unread list.
 */
export class Notify {
  private static enabled: boolean = true;
  private static detail: boolean = false;

  static setEnabled(v: boolean): void {
    Notify.enabled = v;
  }

  static setDetailEnabled(v: boolean): void {
    Notify.detail = v;
  }

  static async ensureChannel(): Promise<void> {
    try {
      await notificationManager.requestEnableNotification();
    } catch (_e) {
      // Already enabled or unavailable on this build.
    }
  }

  static async setBadge(count: number): Promise<void> {
    const n = Math.max(0, count);
    try {
      await notificationManager.setBadgeNumber(n);
    } catch (_e) {
    }
    if (n === 0) {
      try {
        await notificationManager.cancel(SUMMARY_ID);
      } catch (_e) {
      }
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
        SessionDiag.emit({ tag: TAG, event: 'cancel', extra: 'empty_or_off' });
      } catch (_e) {
      }
      return;
    }
    try {
      const first = items[0];
      const title = Notify.detail ?
        (items.length === 1 ?
          `${first.name}${(first.repo ?? '').length > 0 ? ` · ${first.repo}` : ''} · ${first.statusZh}` :
          `${items.length} 条新结果`) :
        (items.length === 1 ? '任务已更新' : `${items.length} 条任务已更新`);
      const lines: string[] = [];
      for (let i = 0; i < items.length && i < 8; i++) {
        const it = items[i];
        if (Notify.detail) {
          const r = (it.repo ?? '').length > 0 ? `${it.repo} · ` : '';
          const bit = it.snippet.length > 0 ? ` · ${it.snippet}` : '';
          lines.push(`${it.name} ${r}${it.statusZh}${bit}`);
        } else {
          lines.push('任务已更新');
        }
      }
      if (items.length > 8) {
        lines.push(`另有 ${items.length - 8} 条`);
      }
      const body = lines.length > 0 ? lines[0] : '点按查看全部';
      const single = items.length === 1;
      const launch: Want = single ? {
        bundleName: 'com.brian.cursor.mobile',
        abilityName: 'EntryAbility',
        action: 'action.ohos.cursor.openAgent',
        uri: `cursoragent://open/${first.id}`,
        parameters: {
          'agentId': first.id
        }
      } : {
        bundleName: 'com.brian.cursor.mobile',
        abilityName: 'EntryAbility',
        action: 'action.ohos.cursor.openInbox',
        uri: 'cursoragent://inbox',
        parameters: {
          'showUnread': '1'
        }
      };
      SessionDiag.emit({
        tag: TAG,
        event: 'publish',
        agentId: first.id,
        extra: `n=${items.length} want=${single ? 'open' : 'inbox'} repo=${first.repo ?? ''}`
      });
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
            additionalText: single ? '点按打开会话' : '点按查看全部',
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
      SessionDiag.emit({ tag: TAG, event: 'publish_fail', extra: 'err' });
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
