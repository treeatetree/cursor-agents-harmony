import { common } from '@kit.AbilityKit';
import { Want } from '@kit.AbilityKit';
import { Log } from './Log';

const TAG = 'Share';

/** Best-effort system share sheet (Harmony Share / sendData). */
export async function shareText(ctx: common.UIAbilityContext, title: string, text: string): Promise<boolean> {
  if (!text || text.length === 0) {
    return false;
  }
  try {
    const want: Want = {
      action: 'ohos.want.action.sendData',
      type: 'text/plain',
      parameters: {
        'ability.params.stream': `${title.length > 0 ? title + '\n' : ''}${text}`,
        'ohos.extra.param.key.shareTitle': title.length > 0 ? title : '分享',
        'ohos.extra.param.key.contentTitle': title.length > 0 ? title : '分享'
      }
    };
    await ctx.startAbility(want);
    return true;
  } catch (e) {
    Log.warn(TAG, `share failed: ${JSON.stringify(e)}`);
    try {
      // Fallback: open as link when it's a URL.
      if (text.indexOf('https://') === 0 || text.indexOf('http://') === 0) {
        await ctx.openLink(text);
        return true;
      }
    } catch (_e2) {
    }
    return false;
  }
}

export async function shareAgentLinks(ctx: common.UIAbilityContext, name: string, agentUrl: string,
  prUrl: string, branch: string): Promise<boolean> {
  const lines: string[] = [];
  if (name.length > 0) {
    lines.push(name);
  }
  if (agentUrl.length > 0) {
    lines.push(agentUrl);
  }
  if (prUrl.length > 0) {
    lines.push(`PR: ${prUrl}`);
  }
  if (branch.length > 0) {
    lines.push(`分支: ${branch}`);
  }
  return await shareText(ctx, name.length > 0 ? name : 'Cursor Agent', lines.join('\n'));
}
