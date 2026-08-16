import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Haptics } from '../utils/Haptics';
import { Log } from '../utils/Log';

const TAG = 'PrefStore';
const PREF_NAME = 'cursor_prefs';
const KEY_DRAFT = 'new_agent_draft';
const KEY_LAST_EVENT = 'last_event_ids'; // JSON map agentId:runId -> eventId
const KEY_THEME = 'theme_pref'; // system | dark | light
const KEY_DEFAULT_MODEL = 'default_model';
const KEY_DEFAULT_AUTO_PR = 'default_auto_pr';
const KEY_HAPTICS = 'haptics_enabled';
const KEY_INBOX_VIEW = 'inbox_view';
const KEY_INBOX_GROUP = 'inbox_group';
const KEY_INBOX_SORT = 'inbox_sort';
const KEY_INBOX_OPEN = 'inbox_open';
const KEY_INBOX_COLLAPSED = 'inbox_collapsed';
const KEY_INBOX_PINNED = 'inbox_pinned';
const KEY_LAST_TOOLS = 'last_agent_tools';
const KEY_TYPE = 'type_pref';
const KEY_DENSITY = 'density_pref';
const KEY_AVATAR = 'avatar_preset';
const KEY_UNREAD = 'unread_items';

export class PrefStore {
  private static instance: PrefStore | undefined = undefined;
  private pref: preferences.Preferences | undefined = undefined;

  static getInstance(): PrefStore {
    if (!PrefStore.instance) {
      PrefStore.instance = new PrefStore();
    }
    return PrefStore.instance;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.pref) {
      return;
    }
    try {
      this.pref = await preferences.getPreferences(context, PREF_NAME);
      // Sync haptics gate into process-local cache.
      const enabled = await this.getHapticsEnabled();
      Haptics.setEnabled(enabled);
    } catch (e) {
      Log.warn(TAG, `init failed: ${JSON.stringify(e)}`);
    }
  }

  async getDraft(): Promise<string> {
    if (!this.pref) {
      return '';
    }
    return (await this.pref.get(KEY_DRAFT, '')) as string;
  }

  async setDraft(text: string): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.put(KEY_DRAFT, text);
    await this.pref.flush();
  }

  async clearDraft(): Promise<void> {
    await this.setDraft('');
  }

  async getThemePref(): Promise<string> {
    if (!this.pref) {
      return 'system';
    }
    return (await this.pref.get(KEY_THEME, 'system')) as string;
  }

  async setThemePref(value: string): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.put(KEY_THEME, value);
    await this.pref.flush();
  }

  async getDefaultModel(): Promise<string> {
    if (!this.pref) {
      return '';
    }
    return (await this.pref.get(KEY_DEFAULT_MODEL, '')) as string;
  }

  async setDefaultModel(modelId: string): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.put(KEY_DEFAULT_MODEL, modelId);
    await this.pref.flush();
  }

  async getDefaultAutoPR(): Promise<boolean> {
    if (!this.pref) {
      return false;
    }
    return (await this.pref.get(KEY_DEFAULT_AUTO_PR, false)) as boolean;
  }

  async setDefaultAutoPR(value: boolean): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.put(KEY_DEFAULT_AUTO_PR, value);
    await this.pref.flush();
  }

  async getHapticsEnabled(): Promise<boolean> {
    if (!this.pref) {
      return true;
    }
    return (await this.pref.get(KEY_HAPTICS, true)) as boolean;
  }

  async setHapticsEnabled(value: boolean): Promise<void> {
    Haptics.setEnabled(value);
    if (!this.pref) {
      return;
    }
    await this.pref.put(KEY_HAPTICS, value);
    await this.pref.flush();
  }

  async getInboxView(): Promise<string> {
    if (!this.pref) {
      return 'cards';
    }
    return (await this.pref.get(KEY_INBOX_VIEW, 'cards')) as string;
  }

  async setInboxView(value: string): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.put(KEY_INBOX_VIEW, value);
    await this.pref.flush();
  }

  async getInboxGroup(): Promise<string> {
    if (!this.pref) {
      return 'repo';
    }
    return (await this.pref.get(KEY_INBOX_GROUP, 'repo')) as string;
  }

  async setInboxGroup(value: string): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.put(KEY_INBOX_GROUP, value);
    await this.pref.flush();
  }

  async getInboxSort(): Promise<string> {
    if (!this.pref) {
      return 'updated';
    }
    return (await this.pref.get(KEY_INBOX_SORT, 'updated')) as string;
  }

  async setInboxSort(value: string): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.put(KEY_INBOX_SORT, value);
    await this.pref.flush();
  }

  async getInboxOpen(): Promise<boolean> {
    if (!this.pref) {
      return true;
    }
    return (await this.pref.get(KEY_INBOX_OPEN, true)) as boolean;
  }

  async setInboxOpen(value: boolean): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.put(KEY_INBOX_OPEN, value);
    await this.pref.flush();
  }

  async getCollapsedGroups(): Promise<string[]> {
    if (!this.pref) {
      return [];
    }
    try {
      const raw = (await this.pref.get(KEY_INBOX_COLLAPSED, '[]')) as string;
      const parsed = JSON.parse(raw) as string[];
      return parsed ?? [];
    } catch (_e) {
      return [];
    }
  }

  async setCollapsedGroups(keys: string[]): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.put(KEY_INBOX_COLLAPSED, JSON.stringify(keys));
    await this.pref.flush();
  }

  async getPinnedIds(): Promise<string[]> {
    if (!this.pref) {
      return [];
    }
    try {
      const raw = (await this.pref.get(KEY_INBOX_PINNED, '[]')) as string;
      const parsed = JSON.parse(raw) as string[];
      return parsed ?? [];
    } catch (_e) {
      return [];
    }
  }

  async setPinnedIds(ids: string[]): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.put(KEY_INBOX_PINNED, JSON.stringify(ids));
    await this.pref.flush();
  }

  async getTypePref(): Promise<string> {
    if (!this.pref) {
      return 'default';
    }
    return (await this.pref.get(KEY_TYPE, 'default')) as string;
  }

  async setTypePref(value: string): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.put(KEY_TYPE, value);
    await this.pref.flush();
  }

  async getDensityPref(): Promise<string> {
    if (!this.pref) {
      return 'comfortable';
    }
    return (await this.pref.get(KEY_DENSITY, 'comfortable')) as string;
  }

  async setDensityPref(value: string): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.put(KEY_DENSITY, value);
    await this.pref.flush();
  }

  async getAvatarPreset(): Promise<string> {
    if (!this.pref) {
      return 'iridescent';
    }
    const raw = (await this.pref.get(KEY_AVATAR, 'iridescent')) as string;
    return raw.length > 0 ? raw : 'iridescent';
  }

  async setAvatarPreset(value: string): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.put(KEY_AVATAR, value);
    await this.pref.flush();
  }

  async getLastTools(): Promise<string> {
    if (!this.pref) {
      return '';
    }
    return (await this.pref.get(KEY_LAST_TOOLS, '')) as string;
  }

  async setLastTools(raw: string): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.put(KEY_LAST_TOOLS, raw);
    await this.pref.flush();
  }

  async getUnreadItems(): Promise<UnreadRow[]> {
    if (!this.pref) {
      return [];
    }
    try {
      const raw = (await this.pref.get(KEY_UNREAD, '[]')) as string;
      const parsed = JSON.parse(raw) as UnreadRow[];
      return parsed ?? [];
    } catch (_e) {
      return [];
    }
  }

  async setUnreadItems(items: UnreadRow[]): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.put(KEY_UNREAD, JSON.stringify(items));
    await this.pref.flush();
  }

  async getLastEventId(agentId: string, runId: string): Promise<string> {
    const map = await this.loadEventMap();
    return map[`${agentId}:${runId}`] ?? '';
  }

  async setLastEventId(agentId: string, runId: string, eventId: string): Promise<void> {
    if (!this.pref || eventId.length === 0) {
      return;
    }
    const map = await this.loadEventMap();
    map[`${agentId}:${runId}`] = eventId;
    await this.pref.put(KEY_LAST_EVENT, JSON.stringify(map));
    await this.pref.flush();
  }

  private async loadEventMap(): Promise<Record<string, string>> {
    if (!this.pref) {
      return {};
    }
    try {
      const raw = (await this.pref.get(KEY_LAST_EVENT, '{}')) as string;
      return JSON.parse(raw) as Record<string, string>;
    } catch (_e) {
      return {};
    }
  }
}

export interface UnreadRow {
  id: string;
  name: string;
  statusZh: string;
  snippet: string;
  at: number;
}
