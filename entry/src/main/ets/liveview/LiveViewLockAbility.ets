import { Want } from '@kit.AbilityKit';
import { UIExtensionContentSession } from '@kit.AbilityKit';
import { LiveViewLockScreenExtensionAbility } from '@kit.LiveViewKit';

export default class LiveViewLockAbility extends LiveViewLockScreenExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    const storage = new LocalStorage();
    const raw = want.parameters;
    const title = raw && raw['title'] ? `${raw['title']}` : 'Cursor Agent';
    const status = raw && raw['status'] ? `${raw['status']}` : '';
    const agentId = raw && raw['agentId'] ? `${raw['agentId']}` : '';
    storage.setOrCreate('title', title);
    storage.setOrCreate('status', status);
    storage.setOrCreate('agentId', agentId);
    session.loadContent('liveview/LockScreenPage', storage);
  }
}
