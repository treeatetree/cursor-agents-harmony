import { common } from '@kit.AbilityKit';
import { ApiException, MeResponse } from '../models/Api';
import { CursorApiClient } from '../api/CursorApiClient';
import { ApiKeyStore } from '../store/ApiKeyStore';
import { AgentCache } from '../store/AgentCache';
import { CreateDraftStore } from '../store/CreateDraftStore';
import { PrefStore } from '../store/PrefStore';
import { UnreadStore } from '../store/UnreadStore';
import { Log } from '../utils/Log';

const TAG = 'SessionVM';

export class SessionVM {
  hasKey: boolean = false;
  email: string = '';
  keyName: string = '';
  userName: string = '';
  maskedKey: string = '';
  busy: boolean = false;
  errorMsg: string = '';
  ready: boolean = false;
  keyReady: boolean = false;

  private static instance: SessionVM | undefined = undefined;
  private listeners: Array<() => void> = [];

  static getInstance(): SessionVM {
    if (!SessionVM.instance) {
      SessionVM.instance = new SessionVM();
    }
    return SessionVM.instance;
  }

  /** Index stays visible in split NavigationMode — subscribe so Settings save/clear refreshes it. */
  onChange(cb: () => void): void {
    this.listeners.push(cb);
  }

  /** Force Index (and other listeners) to re-read session after Settings pop. */
  notifyUi(): void {
    this.syncFromStore();
    this.emitChange();
  }

  private emitChange(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      try {
        this.listeners[i]();
      } catch (_e) {
        // ignore listener errors
      }
    }
  }

  async bootstrap(context: common.UIAbilityContext): Promise<void> {
    await this.hydrate(context);
    await this.unlockAndValidate();
  }

  /** Load prefs + key-present flag. Does not wait for HUKS decrypt. */
  async hydrate(context: common.UIAbilityContext): Promise<void> {
    await Promise.all([
      ApiKeyStore.getInstance().init(context),
      PrefStore.getInstance().init(context)
    ]);
    await CreateDraftStore.getInstance().hydrate();
    this.syncFromStore();
    this.ready = true;
  }

  /** Decrypt the API key, then optionally ping /me. */
  async unlockAndValidate(): Promise<void> {
    const unlocked = await ApiKeyStore.getInstance().unlock();
    this.syncFromStore();
    if (!unlocked) {
      this.hasKey = false;
      this.keyReady = false;
    }
    this.emitChange();
    if (this.hasKey) {
      try {
        await this.validateExisting();
      } catch (_e) {
        // soft fail — keep cached key for offline
      }
    }
  }

  syncFromStore(): void {
    const store = ApiKeyStore.getInstance();
    this.hasKey = store.hasKey();
    this.email = store.getEmail();
    this.keyName = store.getKeyName();
    this.userName = store.getUserName();
    this.maskedKey = store.maskedKey();
    this.keyReady = store.isUnlocked();
  }

  async saveAndValidate(rawKey: string): Promise<boolean> {
    this.busy = true;
    this.errorMsg = '';
    try {
      // Paste often includes newlines / zero-width spaces.
      const cleaned = rawKey.replace(/\s+/g, '').replace(/[\u200B-\u200D\uFEFF]/g, '');
      const me = await CursorApiClient.getInstance().me(cleaned);
      const email = me.userEmail ?? '';
      const name = me.apiKeyName ?? '';
      await ApiKeyStore.getInstance().saveKey(cleaned, email, name, meDisplayName(me));
      this.syncFromStore();
      this.emitChange();
      Log.info(TAG, `validated ok`);
      return true;
    } catch (e) {
      if (e instanceof ApiException) {
        this.errorMsg = e.message;
      } else {
        const detail = e instanceof Error ? e.message : JSON.stringify(e);
        Log.error(TAG, `saveAndValidate failed: ${detail}`);
        this.errorMsg = detail && detail.length > 0 ? `保存失败：${detail}` : '验证失败';
      }
      return false;
    } finally {
      this.busy = false;
    }
  }

  async validateExisting(): Promise<boolean> {
    if (!ApiKeyStore.getInstance().isUnlocked()) {
      return false;
    }
    try {
      const me = await CursorApiClient.getInstance().me();
      await ApiKeyStore.getInstance().updateProfile(me.userEmail ?? '', me.apiKeyName ?? '',
        meDisplayName(me));
      this.syncFromStore();
      this.errorMsg = '';
      this.emitChange();
      return true;
    } catch (e) {
      if (e instanceof ApiException && e.code === 401 && e.apiCode !== 'no_api_key') {
        this.errorMsg = 'API Key 失效，请重新粘贴';
      }
      return false;
    }
  }

  async clearKey(): Promise<void> {
    await ApiKeyStore.getInstance().clear();
    try {
      AgentCache.getInstance().clearAll();
    } catch (_e) {
      // ignore
    }
    CreateDraftStore.getInstance().clear();
    try {
      await UnreadStore.getInstance().clearAll();
      await PrefStore.getInstance().clearAccountLocal();
    } catch (_e) {
    }
    this.syncFromStore();
    this.errorMsg = '';
    this.emitChange();
  }
}

function meDisplayName(me: MeResponse): string {
  const first = (me.userFirstName ?? '').trim();
  const last = (me.userLastName ?? '').trim();
  return `${first} ${last}`.trim();
}
