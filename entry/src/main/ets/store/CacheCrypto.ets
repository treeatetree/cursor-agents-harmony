import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { huks } from '@kit.UniversalKeystoreKit';
import { Log } from '../utils/Log';

const TAG = 'CacheCrypto';
const PREF_NAME = 'cursor_cache_crypto';
const KEY_ALIAS = 'cursor_cache_wrap_v1';
const KEY_BLOB = 'data_key_blob';
const KEY_IV = 'data_key_iv';
const AAD = stringToU8('cursor.cache.aad.v1');

interface EncEnvelope {
  enc: number;
  iv: string;
  ct: string;
}

class CryptoBlob {
  data: Uint8Array;

  constructor(d: Uint8Array) {
    this.data = d;
  }
}

/**
 * HUKS wraps a 32-byte data key; AES-256-GCM seals cache JSON in process.
 */
export class CacheCrypto {
  private static instance: CacheCrypto | undefined = undefined;
  private pref: preferences.Preferences | undefined = undefined;
  private dataKey: Uint8Array | undefined = undefined;
  private ready: boolean = false;
  private initTask: Promise<void> | undefined = undefined;

  static getInstance(): CacheCrypto {
    if (!CacheCrypto.instance) {
      CacheCrypto.instance = new CacheCrypto();
    }
    return CacheCrypto.instance;
  }

  isReady(): boolean {
    return this.ready && this.dataKey !== undefined;
  }

  isSealed(raw: string): boolean {
    return raw.indexOf('"enc":1') >= 0;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.ready) {
      return;
    }
    if (this.initTask) {
      await this.initTask;
      return;
    }
    this.initTask = this.initialize(context);
    try {
      await this.initTask;
    } finally {
      this.initTask = undefined;
    }
  }

  private async initialize(context: common.UIAbilityContext): Promise<void> {
    try {
      this.pref = await preferences.getPreferences(context, PREF_NAME);
      await this.ensureWrapKey();
      await this.loadOrCreateDataKey();
      this.ready = true;
    } catch (e) {
      Log.warn(TAG, `init failed: ${errMsg(e)}`);
      this.ready = false;
    }
  }

  async clear(): Promise<void> {
    if (this.initTask) {
      try {
        await this.initTask;
      } catch (_e) {
      }
    }
    this.dataKey = undefined;
    this.ready = false;
    if (this.pref) {
      try {
        await this.pref.delete(KEY_BLOB);
        await this.pref.delete(KEY_IV);
        await this.pref.flush();
      } catch (_e) {
      }
    }
    try {
      await huks.deleteKeyItem(KEY_ALIAS, { properties: [] });
    } catch (_e) {
    }
  }

  seal(plain: string): string {
    if (!this.dataKey) {
      Log.warn(TAG, 'seal skipped: key unavailable');
      return '';
    }
    try {
      const iv = cryptoFramework.createRandom().generateRandomSync(12).data;
      const pt = new util.TextEncoder().encodeInto(plain);
      const ct = this.aesGcm(true, iv, pt);
      const env: EncEnvelope = { enc: 1, iv: b64(iv), ct: b64(ct) };
      return JSON.stringify(env);
    } catch (e) {
      Log.warn(TAG, `seal failed: ${errMsg(e)}`);
      return '';
    }
  }

  open(raw: string): string {
    if (!raw || !this.isSealed(raw)) {
      return raw;
    }
    if (!this.dataKey) {
      return '';
    }
    try {
      const env = JSON.parse(raw) as EncEnvelope;
      if (env.enc !== 1 || !env.iv || !env.ct) {
        return raw;
      }
      const iv = unb64(env.iv);
      const ct = unb64(env.ct);
      const pt = this.aesGcm(false, iv, ct);
      return util.TextDecoder.create('utf-8').decodeToString(pt);
    } catch (e) {
      Log.warn(TAG, `open failed: ${errMsg(e)}`);
      return '';
    }
  }

  private aesGcm(encrypt: boolean, iv: Uint8Array, data: Uint8Array): Uint8Array {
    const key = this.dataKey as Uint8Array;
    const gen = cryptoFramework.createSymKeyGenerator('AES256');
    const sym = gen.convertKeySync(new CryptoBlob(key));
    const cipher = cryptoFramework.createCipher('AES256|GCM|NOPADDING');
    const tagSrc = encrypt ? new Uint8Array(16) : data.subarray(data.length - 16);
    const params: cryptoFramework.GcmParamsSpec = {
      algName: 'GcmParamsSpec',
      iv: new CryptoBlob(iv),
      aad: new CryptoBlob(AAD),
      authTag: new CryptoBlob(tagSrc)
    };
    const mode = encrypt ? cryptoFramework.CryptoMode.ENCRYPT_MODE : cryptoFramework.CryptoMode.DECRYPT_MODE;
    cipher.initSync(mode, sym, params);
    const body = encrypt ? data : data.subarray(0, data.length - 16);
    const out = cipher.doFinalSync(new CryptoBlob(body));
    if (!out || !out.data) {
      throw new Error('cipher empty');
    }
    if (encrypt) {
      const packed = new Uint8Array(out.data.length + 16);
      packed.set(out.data, 0);
      packed.set(params.authTag.data, out.data.length);
      return packed;
    }
    return out.data;
  }

  private async ensureWrapKey(): Promise<void> {
    try {
      if (await huks.isKeyItemExist(KEY_ALIAS, { properties: [] })) {
        return;
      }
    } catch (_e) {
    }
    await huks.generateKeyItem(KEY_ALIAS, {
      properties: [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
        { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
        {
          tag: huks.HuksTag.HUKS_TAG_PURPOSE,
          value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
        }
      ]
    });
  }

  private async loadOrCreateDataKey(): Promise<void> {
    if (!this.pref) {
      throw new Error('no pref');
    }
    const blob = (await this.pref.get(KEY_BLOB, '')) as string;
    const ivB64 = (await this.pref.get(KEY_IV, '')) as string;
    if (blob.length > 0 && ivB64.length > 0) {
      const iv = unb64(ivB64);
      const packed = unb64(blob);
      this.dataKey = await this.huksDecrypt(iv, packed);
      return;
    }
    const raw = cryptoFramework.createRandom().generateRandomSync(32).data;
    const iv = cryptoFramework.createRandom().generateRandomSync(12).data;
    const sealed = await this.huksEncrypt(iv, raw);
    await this.pref.put(KEY_BLOB, b64(sealed));
    await this.pref.put(KEY_IV, b64(iv));
    await this.pref.flush();
    this.dataKey = raw;
  }

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
    if (!finished.outData) {
      throw new Error('wrap encrypt empty');
    }
    return finished.outData;
  }

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
      throw new Error('wrap decrypt empty');
    }
    return finished.outData;
  }
}

function stringToU8(s: string): Uint8Array {
  const a: number[] = [];
  for (let i = 0; i < s.length; i++) {
    a.push(s.charCodeAt(i));
  }
  return new Uint8Array(a);
}

function b64(buf: Uint8Array): string {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let result = '';
  for (let i = 0; i < buf.length; i += 3) {
    const b0 = buf[i];
    const b1 = i + 1 < buf.length ? buf[i + 1] : 0;
    const b2 = i + 2 < buf.length ? buf[i + 2] : 0;
    result += alphabet.charAt(b0 >> 2);
    result += alphabet.charAt(((b0 & 3) << 4) | (b1 >> 4));
    result += i + 1 < buf.length ? alphabet.charAt(((b1 & 15) << 2) | (b2 >> 6)) : '=';
    result += i + 2 < buf.length ? alphabet.charAt(b2 & 63) : '=';
  }
  return result;
}

function unb64(s: string): Uint8Array {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const clean = s.replace(/=+$/g, '');
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
  return new Uint8Array(out);
}

function errMsg(e: Object): string {
  return e instanceof Error ? e.message : `${e}`;
}
