import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { huks } from '@kit.UniversalKeystoreKit';
import { Log } from '../utils/Log';

const TAG = 'ApiKeyStore';
const PREF_NAME = 'cursor_secure';
/** New alias — old v1 may be half-created with bad params. */
const KEY_ALIAS = 'cursor_api_key_v2';
const KEY_CIPHER = 'api_key_cipher_huks_v2';
const KEY_IV = 'api_key_iv_huks_v2';
const KEY_HAS = 'api_key_present';
const KEY_EMAIL = 'user_email';
const KEY_NAME = 'api_key_name';
const KEY_USER_NAME = 'user_display_name';
/** Non-empty AAD required by HUKS GCM param builder (empty buffer → HksBuildParamSet fail). */
const AAD = stringToUint8Array('cursor.mobile.aad.v2');
const LEGACY_KEYS: string[] = [
  'api_key_cipher_v2', 'api_key_iv_v2',
  'api_key_cipher_v3', 'api_key_iv_v3', 'api_key_tag_v3',
  'api_key_cipher_huks', 'api_key_iv_huks'
];

/**
 * API Key at-rest: HUKS AES-256-GCM (official param layout) + Preferences ciphertext.
 */
export class ApiKeyStore {
  private static instance: ApiKeyStore | undefined = undefined;
  private pref: preferences.Preferences | undefined = undefined;
  private memoryKey: string = '';
  private email: string = '';
  private keyName: string = '';
  private userName: string = '';
  private ready: boolean = false;
  private present: boolean = false;
  private unlockJob: Promise<boolean> | undefined = undefined;

  static getInstance(): ApiKeyStore {
    if (!ApiKeyStore.instance) {
      ApiKeyStore.instance = new ApiKeyStore();
    }
    return ApiKeyStore.instance;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.ready) {
      return;
    }
    try {
      this.pref = await preferences.getPreferences(context, PREF_NAME);
      this.email = (await this.pref.get(KEY_EMAIL, '')) as string;
      this.keyName = (await this.pref.get(KEY_NAME, '')) as string;
      this.userName = (await this.pref.get(KEY_USER_NAME, '')) as string;
      this.present = (await this.pref.get(KEY_HAS, false)) as boolean;
    } catch (e) {
      Log.error(TAG, `init failed: ${errMsg(e)}`);
    }
    this.ready = true;
  }

  /** Decrypt the stored key. Call after init so the UI can paint from cache first. */
  async unlock(): Promise<boolean> {
    if (this.memoryKey.length > 0) {
      return true;
    }
    if (this.unlockJob) {
      return this.unlockJob;
    }
    this.unlockJob = this.unlockOnce();
    try {
      return await this.unlockJob;
    } finally {
      this.unlockJob = undefined;
    }
  }

  private async unlockOnce(): Promise<boolean> {
    if (this.memoryKey.length > 0) {
      return true;
    }
    if (!this.present || !this.pref) {
      return false;
    }
    try {
      await this.ensureHuksKey();
      this.memoryKey = await this.decryptFromPref();
      if (this.memoryKey.length > 0) {
        Log.info(TAG, `unlocked ${Log.maskKey(this.memoryKey)}`);
        return true;
      }
      Log.warn(TAG, 'cipher present but decrypt empty — clear stale');
      await this.clearCipherOnly();
      this.present = false;
      return false;
    } catch (e) {
      const msg = errMsg(e).toLowerCase();
      const transient = msg.indexOf('lock') >= 0 || msg.indexOf('busy') >= 0 ||
        msg.indexOf('unavailable') >= 0 || msg.indexOf('timeout') >= 0 ||
        msg.indexOf('not ready') >= 0;
      Log.error(TAG, `decrypt failed: ${errMsg(e)}`);
      this.memoryKey = '';
      if (transient) {
        return false;
      }
      this.present = false;
      await this.clearCipherOnly();
      return false;
    }
  }

  hasKey(): boolean {
    return this.memoryKey.length > 0 || this.present;
  }

  isUnlocked(): boolean {
    return this.memoryKey.length > 0;
  }

  getKey(): string {
    return this.memoryKey;
  }

  getEmail(): string {
    return this.email;
  }

  getKeyName(): string {
    return this.keyName;
  }

  getUserName(): string {
    return this.userName;
  }

  maskedKey(): string {
    return Log.maskKey(this.memoryKey);
  }

  async saveKey(rawKey: string, email: string = '', keyName: string = '',
    userName: string = ''): Promise<void> {
    const key = rawKey.trim();
    try {
      await this.ensureHuksKey();
      await this.encryptToPref(key);
    } catch (e) {
      Log.error(TAG, `save encrypt failed: ${errMsg(e)}`);
      throw new Error('安全存储失败，请重试或重启应用后再保存');
    }
    this.memoryKey = key;
    this.email = email;
    this.keyName = keyName;
    this.userName = userName;
    this.present = true;
    if (this.pref) {
      await this.pref.put(KEY_HAS, true);
      await this.pref.put(KEY_EMAIL, email);
      await this.pref.put(KEY_NAME, keyName);
      await this.pref.put(KEY_USER_NAME, userName);
      await this.clearLegacyBlobs();
      await this.pref.flush();
    }
    Log.info(TAG, `saved ${Log.maskKey(key)}`);
  }

  async updateProfile(email: string, keyName: string, userName: string = ''): Promise<void> {
    this.email = email;
    this.keyName = keyName;
    this.userName = userName;
    if (this.pref) {
      await this.pref.put(KEY_EMAIL, email);
      await this.pref.put(KEY_NAME, keyName);
      await this.pref.put(KEY_USER_NAME, userName);
      await this.pref.flush();
    }
  }

  async clear(): Promise<void> {
    this.memoryKey = '';
    this.email = '';
    this.keyName = '';
    this.userName = '';
    this.present = false;
    if (this.pref) {
      await this.clearCipherOnly();
      await this.pref.put(KEY_EMAIL, '');
      await this.pref.put(KEY_NAME, '');
      await this.pref.put(KEY_USER_NAME, '');
      await this.pref.flush();
    }
    try {
      await huks.deleteKeyItem(KEY_ALIAS, { properties: [] });
    } catch (_e) {
    }
    try {
      await huks.deleteKeyItem('cursor_api_key_v1', { properties: [] });
    } catch (_e) {
    }
    Log.info(TAG, 'cleared');
  }

  private async clearCipherOnly(): Promise<void> {
    if (!this.pref) {
      return;
    }
    try {
      await this.pref.delete(KEY_CIPHER);
      await this.pref.delete(KEY_IV);
    } catch (_e) {
    }
    await this.clearLegacyBlobs();
    await this.pref.put(KEY_HAS, false);
    this.present = false;
    await this.pref.flush();
  }

  private async clearLegacyBlobs(): Promise<void> {
    if (!this.pref) {
      return;
    }
    for (let i = 0; i < LEGACY_KEYS.length; i++) {
      try {
        await this.pref.delete(LEGACY_KEYS[i]);
      } catch (_e) {
      }
    }
  }

  private async ensureHuksKey(): Promise<void> {
    try {
      const exists = await huks.isKeyItemExist(KEY_ALIAS, { properties: [] });
      if (exists) {
        return;
      }
    } catch (_e) {
      // treat as missing
    }
    // Official generate props: ALGORITHM + KEY_SIZE + PURPOSE only (no padding/mode).
    const properties: Array<huks.HuksParam> = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      {
        tag: huks.HuksTag.HUKS_TAG_PURPOSE,
        value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
      }
    ];
    await huks.generateKeyItem(KEY_ALIAS, { properties: properties });
    Log.info(TAG, 'HUKS key generated');
  }

  private async encryptToPref(plain: string): Promise<void> {
    if (!this.pref) {
      throw new Error('ApiKeyStore not initialized');
    }
    const iv = cryptoFramework.createRandom().generateRandomSync(12).data;
    const plainBytes = new util.TextEncoder().encodeInto(plain);
    const out = await this.huksEncrypt(iv, plainBytes);
    await this.pref.put(KEY_CIPHER, bytesToBase64(out));
    await this.pref.put(KEY_IV, bytesToBase64(iv));
  }

  private async decryptFromPref(): Promise<string> {
    if (!this.pref) {
      throw new Error('ApiKeyStore not initialized');
    }
    const cipherB64 = (await this.pref.get(KEY_CIPHER, '')) as string;
    const ivB64 = (await this.pref.get(KEY_IV, '')) as string;
    if (!cipherB64 || !ivB64) {
      return '';
    }
    const ct = base64ToBytes(cipherB64);
    const iv = base64ToBytes(ivB64);
    if (ct.length < 17 || iv.length !== 12) {
      return '';
    }
    const out = await this.huksDecrypt(iv, ct);
    return util.TextDecoder.create('utf-8').decodeToString(out);
  }

  /** Official path: initSession + finishSession(inData=plain); out = cipher||tag. */
  private async huksEncrypt(iv: Uint8Array, plain: Uint8Array): Promise<Uint8Array> {
    const properties: Array<huks.HuksParam> = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_NONCE, value: iv },
      { tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: AAD }
    ];
    const options: huks.HuksOptions = { properties: properties, inData: plain };
    const session = await huks.initSession(KEY_ALIAS, options);
    const finished = await huks.finishSession(session.handle, options);
    if (!finished.outData || finished.outData.length === 0) {
      throw new Error('HUKS encrypt empty');
    }
    return finished.outData;
  }

  /** Decrypt: AE_TAG = last 16 bytes; inData = body without tag. */
  private async huksDecrypt(iv: Uint8Array, packed: Uint8Array): Promise<Uint8Array> {
    const tag = packed.subarray(packed.length - 16);
    const body = packed.subarray(0, packed.length - 16);
    const properties: Array<huks.HuksParam> = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_NONCE, value: iv },
      { tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: AAD },
      { tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: tag }
    ];
    const options: huks.HuksOptions = { properties: properties, inData: body };
    const session = await huks.initSession(KEY_ALIAS, options);
    const finished = await huks.finishSession(session.handle, options);
    if (!finished.outData) {
      throw new Error('HUKS decrypt empty');
    }
    return finished.outData;
  }
}

function stringToUint8Array(str: string): Uint8Array {
  const arr: number[] = [];
  for (let i = 0; i < str.length; i++) {
    arr.push(str.charCodeAt(i));
  }
  return new Uint8Array(arr);
}

function errMsg(e: Object): string {
  if (e instanceof Error) {
    return e.message;
  }
  try {
    return JSON.stringify(e);
  } catch (_e) {
    return `${e}`;
  }
}

function bytesToBase64(buf: Uint8Array): string {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let result = '';
  const len = buf.length;
  for (let i = 0; i < len; i += 3) {
    const b0 = buf[i];
    const b1 = i + 1 < len ? buf[i + 1] : 0;
    const b2 = i + 2 < len ? buf[i + 2] : 0;
    result += alphabet.charAt(b0 >> 2);
    result += alphabet.charAt(((b0 & 3) << 4) | (b1 >> 4));
    result += i + 1 < len ? alphabet.charAt(((b1 & 15) << 2) | (b2 >> 6)) : '=';
    result += i + 2 < len ? alphabet.charAt(b2 & 63) : '=';
  }
  return result;
}

function base64ToBytes(b64: string): Uint8Array {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const clean = b64.replace(/=+$/g, '');
  const out: number[] = [];
  for (let i = 0; i < clean.length; i += 4) {
    const c0 = alphabet.indexOf(clean.charAt(i));
    const c1 = alphabet.indexOf(clean.charAt(i + 1));
    const c2 = i + 2 < clean.length ? alphabet.indexOf(clean.charAt(i + 2)) : 0;
    const c3 = i + 3 < clean.length ? alphabet.indexOf(clean.charAt(i + 3)) : 0;
    out.push((c0 << 2) | (c1 >> 4));
    if (i + 2 < clean.length) {
      out.push(((c1 & 15) << 4) | (c2 >> 2));
    }
    if (i + 3 < clean.length) {
      out.push(((c2 & 3) << 6) | c3);
    }
  }
  const bytes = new Uint8Array(out.length);
  for (let i = 0; i < out.length; i++) {
    bytes[i] = out[i];
  }
  return bytes;
}
