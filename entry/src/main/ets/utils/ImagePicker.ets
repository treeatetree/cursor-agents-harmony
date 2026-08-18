import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { util } from '@kit.ArkTS';
import { Log } from './Log';

const TAG = 'ImagePicker';
const MAX_BYTES = 15 * 1024 * 1024;
const MAX_IMAGES = 5;
const MAX_EDGE = 2048;
const PACK_QUALITY = 85;
const PACK_OVER_BYTES = 4 * 1024 * 1024;
const previewMaps: Map<string, image.PixelMap> = new Map();

export interface PromptImage {
  data: string;
  mimeType: string;
  name: string;
  url?: string;
  /** Local path or picker URI for Image() preview. */
  uri?: string;
}

export function previewSrc(img: PromptImage): string {
  if (img.uri && img.uri.length > 0) {
    return toFileUri(img.uri);
  }
  if (img.url && img.url.length > 0) {
    return img.url;
  }
  return '';
}

export function previewMap(key: string): image.PixelMap | undefined {
  return previewMaps.get(key);
}

export function hasPreviewMap(key: string): boolean {
  return previewMaps.has(key);
}

export function requirePreviewMap(key: string): image.PixelMap {
  return previewMaps.get(key) as image.PixelMap;
}

export function dropAllPreviewMaps(): void {
  const keys: string[] = [];
  const it = previewMaps.keys();
  let step = it.next();
  while (!step.done) {
    keys.push(step.value);
    step = it.next();
  }
  for (let i = 0; i < keys.length; i++) {
    dropPreviewMap(keys[i]);
  }
}

export function unlinkPreviewFile(path: string): void {
  if (!path || path.indexOf('/pv_') < 0) {
    return;
  }
  try {
    const p = path.indexOf('file://') === 0 ? path.substring(7) : path;
    fs.unlinkSync(p);
  } catch (_e) {
  }
}

export function sweepPreviewFiles(cacheDir: string): void {
  if (!cacheDir || cacheDir.length === 0) {
    return;
  }
  try {
    const names = fs.listFileSync(cacheDir);
    const now = Date.now();
    for (let i = 0; i < names.length; i++) {
      const n = names[i];
      if (n.indexOf('pv_') !== 0) {
        continue;
      }
      const full = `${cacheDir}/${n}`;
      try {
        const st = fs.statSync(full);
        if (now - st.mtime > 24 * 60 * 60 * 1000) {
          fs.unlinkSync(full);
        }
      } catch (_e) {
      }
    }
  } catch (_e) {
  }
}

export function dropPreviewMap(key: string): void {
  if (key.length === 0) {
    return;
  }
  const pm = previewMaps.get(key);
  if (pm) {
    try {
      pm.release();
    } catch (_e) {
    }
    previewMaps.delete(key);
  }
}

export function toFileUri(path: string): string {
  if (path.length === 0) {
    return '';
  }
  if (path.indexOf('file://') === 0 || path.indexOf('http://') === 0 ||
    path.indexOf('https://') === 0 || path.indexOf('data:') === 0) {
    return path;
  }
  if (path.charAt(0) === '/') {
    return `file://${path}`;
  }
  return path;
}

/** Strip ?v= cache stamps — Image() treats the query as part of the path and can abort. */
export function cleanImageUri(raw: string): string {
  if (raw.length === 0) {
    return '';
  }
  const q = raw.indexOf('?');
  return q >= 0 ? raw.substring(0, q) : raw;
}

export function isSafeImageUri(raw: string): boolean {
  const uri = cleanImageUri(raw);
  if (uri.length === 0) {
    return false;
  }
  return uri.indexOf('file://') === 0 || uri.indexOf('http://') === 0 ||
    uri.indexOf('https://') === 0;
}

export async function imageFileExists(raw: string): Promise<boolean> {
  const uri = cleanImageUri(raw);
  if (uri.length === 0) {
    return false;
  }
  if (uri.indexOf('http://') === 0 || uri.indexOf('https://') === 0) {
    return true;
  }
  let path = uri;
  if (path.indexOf('file://') === 0) {
    path = path.substring(7);
  }
  if (path.length === 0 || path.charAt(0) !== '/') {
    return false;
  }
  try {
    await fs.access(path);
    return true;
  } catch (_e) {
    return false;
  }
}

export async function resolveAvatarPhoto(raw: string): Promise<string> {
  const uri = cleanImageUri(raw);
  if (uri.length === 0) {
    return '';
  }
  if (await imageFileExists(uri)) {
    return uri;
  }
  return '';
}

export function maxPromptImages(): number {
  return MAX_IMAGES;
}

export interface CropRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface ImageSize {
  width: number;
  height: number;
}

/** Album only — no system crop/editor. */
export async function pickOneImageUri(): Promise<string> {
  const options = new photoAccessHelper.PhotoSelectOptions();
  options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
  options.maxSelectNumber = 1;
  options.isEditSupported = false;
  options.isPreviewForSingleSelectionSupported = false;
  const photoPicker = new photoAccessHelper.PhotoViewPicker();
  const result = await photoPicker.select(options);
  const uris = result.photoUris ?? [];
  return uris.length > 0 ? uris[0] : '';
}

export async function readImageSize(uri: string): Promise<ImageSize | undefined> {
  let file: fs.File | undefined = undefined;
  let src: image.ImageSource | undefined = undefined;
  try {
    file = await fs.open(uri, fs.OpenMode.READ_ONLY);
    const stat = await fs.stat(file.fd);
    if (stat.size <= 0 || stat.size > MAX_BYTES) {
      return undefined;
    }
    const buf = new ArrayBuffer(stat.size);
    await fs.read(file.fd, buf);
    src = image.createImageSource(buf);
    const info = await src.getImageInfo();
    const size: ImageSize = { width: info.size.width, height: info.size.height };
    return size;
  } catch (e) {
    Log.warn(TAG, `image size ${JSON.stringify(e)}`);
    return undefined;
  } finally {
    if (src) {
      try {
        await src.release();
      } catch (_e) {
      }
    }
    if (file) {
      try {
        await fs.close(file);
      } catch (_e) {
      }
    }
  }
}

/** Copy album URI into cache as JPEG so crop does not depend on HEIF / media grants. */
export async function materializeForCrop(uri: string, cacheDir: string): Promise<string> {
  let file: fs.File | undefined = undefined;
  let src: image.ImageSource | undefined = undefined;
  try {
    file = await fs.open(uri, fs.OpenMode.READ_ONLY);
    const stat = await fs.stat(file.fd);
    if (stat.size <= 0 || stat.size > MAX_BYTES) {
      Log.warn(TAG, `crop materialize size=${stat.size}`);
      return '';
    }
    const buf = new ArrayBuffer(stat.size);
    await fs.read(file.fd, buf);
    src = image.createImageSource(buf);
    let width = 0;
    let height = 0;
    try {
      const info = await src.getImageInfo();
      width = info.size.width;
      height = info.size.height;
    } catch (e) {
      Log.warn(TAG, `crop materialize info ${JSON.stringify(e)}`);
    }
    const packed = await packJpeg(src, width, height);
    if (!packed || packed.byteLength <= 0) {
      Log.warn(TAG, `crop materialize pack failed ${width}x${height}`);
      return '';
    }
    return await writePreview(cacheDir, 'image/jpeg', packed);
  } catch (e) {
    Log.warn(TAG, `crop materialize failed ${JSON.stringify(e)}`);
    return '';
  } finally {
    if (src) {
      try {
        await src.release();
      } catch (_e) {
      }
    }
    if (file) {
      try {
        await fs.close(file);
      } catch (_e) {
      }
    }
  }
}

function clampSquareRegion(rect: CropRect, w: number, h: number): image.Region {
  let side = Math.max(1, Math.min(Math.floor(rect.width), Math.floor(rect.height), w, h));
  let x = Math.floor(rect.x);
  let y = Math.floor(rect.y);
  if (x < 0) {
    x = 0;
  }
  if (y < 0) {
    y = 0;
  }
  if (x + side > w) {
    x = Math.max(0, w - side);
  }
  if (y + side > h) {
    y = Math.max(0, h - side);
  }
  if (x + side > w) {
    side = Math.max(1, w - x);
  }
  if (y + side > h) {
    side = Math.max(1, h - y);
  }
  const region: image.Region = {
    x: x,
    y: y,
    size: { width: side, height: side }
  };
  return region;
}

function mapCropRect(rect: CropRect, srcW: number, srcH: number, dstW: number, dstH: number): CropRect {
  if (srcW <= 0 || srcH <= 0) {
    return rect;
  }
  const mapped: CropRect = {
    x: rect.x * dstW / srcW,
    y: rect.y * dstH / srcH,
    width: rect.width * dstW / srcW,
    height: rect.height * dstH / srcH
  };
  return mapped;
}

async function decodeEditable(
  src: image.ImageSource,
  size?: image.Size
): Promise<image.PixelMap | undefined> {
  const attempts: image.DecodingOptions[] = [];
  if (size) {
    const sizedSdr: image.DecodingOptions = {
      editable: true,
      desiredSize: size,
      desiredDynamicRange: image.DecodingDynamicRange.SDR
    };
    attempts.push(sizedSdr);
    const sized: image.DecodingOptions = { editable: true, desiredSize: size };
    attempts.push(sized);
  }
  const sdr: image.DecodingOptions = {
    editable: true,
    desiredDynamicRange: image.DecodingDynamicRange.SDR
  };
  attempts.push(sdr);
  const plain: image.DecodingOptions = { editable: true };
  attempts.push(plain);
  for (let i = 0; i < attempts.length; i++) {
    try {
      return await src.createPixelMap(attempts[i]);
    } catch (e) {
      Log.warn(TAG, `crop decode ${i} ${JSON.stringify(e)}`);
    }
  }
  return undefined;
}

/** Crop user-chosen square → 256 JPEG. */
export async function writeSquareCrop(
  srcUri: string,
  destPath: string,
  rect: CropRect
): Promise<string> {
  let file: fs.File | undefined = undefined;
  let src: image.ImageSource | undefined = undefined;
  let pm: image.PixelMap | undefined = undefined;
  let packer: image.ImagePacker | undefined = undefined;
  let out: fs.File | undefined = undefined;
  try {
    file = await fs.open(srcUri, fs.OpenMode.READ_ONLY);
    const stat = await fs.stat(file.fd);
    if (stat.size <= 0 || stat.size > MAX_BYTES) {
      return '';
    }
    const buf = new ArrayBuffer(stat.size);
    await fs.read(file.fd, buf);
    src = image.createImageSource(buf);
    const info = await src.getImageInfo();
    const w = info.size.width;
    const h = info.size.height;
    const region = clampSquareRegion(rect, w, h);
    Log.info(TAG, `avatar crop ${w}x${h} mime=${info.mimeType ?? ''} r=${region.x},${region.y},${region.size.width}`);
    const direct: image.DecodingOptions = {
      desiredRegion: region,
      desiredSize: { width: 256, height: 256 },
      cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST,
      editable: true,
      desiredDynamicRange: image.DecodingDynamicRange.SDR
    };
    try {
      pm = await src.createPixelMap(direct);
    } catch (e) {
      Log.warn(TAG, `crop region+size ${JSON.stringify(e)}`);
      pm = undefined;
    }
    if (!pm) {
      pm = await decodeEditable(src, scaledSize(w, h, MAX_EDGE));
      if (!pm) {
        return '';
      }
      const pmInfo = await pm.getImageInfo();
      const mapped = mapCropRect(rect, w, h, pmInfo.size.width, pmInfo.size.height);
      const cropped = clampSquareRegion(mapped, pmInfo.size.width, pmInfo.size.height);
      await pm.crop(cropped);
      const side = cropped.size.width;
      if (side !== 256) {
        await pm.scale(256 / side, 256 / side);
      }
    }
    packer = image.createImagePacker();
    const packed = await packer.packToData(pm, { format: 'image/jpeg', quality: 88 });
    if (!packed || packed.byteLength <= 0) {
      return '';
    }
    out = await fs.open(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    await fs.write(out.fd, packed);
    Log.info(TAG, `avatar crop wrote ${destPath} bytes=${packed.byteLength}`);
    return destPath;
  } catch (e) {
    Log.warn(TAG, `avatar crop failed ${JSON.stringify(e)}`);
    return '';
  } finally {
    if (packer) {
      try {
        await packer.release();
      } catch (_e) {
      }
    }
    if (pm) {
      try {
        pm.release();
      } catch (_e) {
      }
    }
    if (src) {
      try {
        await src.release();
      } catch (_e) {
      }
    }
    if (file) {
      try {
        await fs.close(file);
      } catch (_e) {
      }
    }
    if (out) {
      try {
        await fs.close(out);
      } catch (_e) {
      }
    }
  }
}

export async function pickPromptImages(
  context: common.UIAbilityContext,
  remain: number
): Promise<PromptImage[]> {
  const n = Math.min(MAX_IMAGES, Math.max(0, remain));
  if (n <= 0) {
    return [];
  }
  const options = new photoAccessHelper.PhotoSelectOptions();
  options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
  options.maxSelectNumber = n;
  const photoPicker = new photoAccessHelper.PhotoViewPicker();
  const result = await photoPicker.select(options);
  const uris = result.photoUris ?? [];
  const out: PromptImage[] = [];
  for (let i = 0; i < uris.length; i++) {
    const img = await readUriAsImage(uris[i], context.cacheDir);
    if (img) {
      out.push(img);
    }
  }
  return out;
}

export function toApiImages(images: PromptImage[]): Object[] {
  const out: Object[] = [];
  for (let i = 0; i < images.length; i++) {
    const o: Record<string, Object> = {};
    const url = images[i].url ?? '';
    if (url.length > 0) {
      o['url'] = url;
    } else {
      o['data'] = images[i].data;
      o['mimeType'] = images[i].mimeType;
    }
    out.push(o);
  }
  return out;
}

export function imageFromUrl(raw: string): PromptImage | undefined {
  const url = raw.trim();
  if (url.length < 8 || (url.indexOf('https://') !== 0 && url.indexOf('http://') !== 0)) {
    return undefined;
  }
  return {
    data: '',
    mimeType: mimeFromPath(url),
    name: fileNameFromUri(url),
    url: url,
    uri: url
  };
}

export function mimeFromPath(path: string): string {
  const p = (path ?? '').toLowerCase();
  if (p.endsWith('.png')) {
    return 'image/png';
  }
  if (p.endsWith('.gif')) {
    return 'image/gif';
  }
  if (p.endsWith('.webp')) {
    return 'image/webp';
  }
  if (p.endsWith('.heic') || p.endsWith('.heif') || p.endsWith('.hif')) {
    return 'image/heif';
  }
  if (p.endsWith('.avif')) {
    return 'image/avif';
  }
  return 'image/jpeg';
}

/** Magic-byte sniff. Huawei camera HEIF is often named .jpg. */
export function sniffMime(buf: ArrayBuffer, path: string): string {
  const u = new Uint8Array(buf);
  if (u.length >= 3 && u[0] === 0xFF && u[1] === 0xD8 && u[2] === 0xFF) {
    return 'image/jpeg';
  }
  if (u.length >= 8 && u[0] === 0x89 && u[1] === 0x50 && u[2] === 0x4E && u[3] === 0x47) {
    return 'image/png';
  }
  if (u.length >= 6 && u[0] === 0x47 && u[1] === 0x49 && u[2] === 0x46) {
    return 'image/gif';
  }
  if (u.length >= 12 && u[0] === 0x52 && u[1] === 0x49 && u[2] === 0x46 && u[3] === 0x46 &&
    u[8] === 0x57 && u[9] === 0x45 && u[10] === 0x42 && u[11] === 0x50) {
    return 'image/webp';
  }
  if (isFtypHeif(u)) {
    return 'image/heif';
  }
  return mimeFromPath(path);
}

function isFtypHeif(u: Uint8Array): boolean {
  if (u.length < 12) {
    return false;
  }
  if (u[4] !== 0x66 || u[5] !== 0x74 || u[6] !== 0x79 || u[7] !== 0x70) {
    return false;
  }
  const n = Math.min(u.length, 36);
  for (let i = 8; i + 3 < n; i += 4) {
    const a = u[i];
    const b = u[i + 1];
    const c = u[i + 2];
    const d = u[i + 3];
    if (a === 0x68 && b === 0x65 && c === 0x69) {
      return true;
    }
    if (a === 0x6D && c === 0x66 && d === 0x31) {
      return true;
    }
    if (a === 0x61 && b === 0x76 && c === 0x69 && d === 0x66) {
      return true;
    }
  }
  return false;
}

function needsJpeg(mime: string, bytes: number): boolean {
  if (mime.indexOf('heif') >= 0 || mime.indexOf('heic') >= 0 || mime.indexOf('avif') >= 0) {
    return true;
  }
  return bytes > PACK_OVER_BYTES && mime !== 'image/png' && mime !== 'image/gif';
}

async function readUriAsImage(uri: string, cacheDir: string): Promise<PromptImage | undefined> {
  let file: fs.File | undefined = undefined;
  let src: image.ImageSource | undefined = undefined;
  try {
    file = await fs.open(uri, fs.OpenMode.READ_ONLY);
    const stat = await fs.stat(file.fd);
    if (stat.size <= 0 || stat.size > MAX_BYTES) {
      Log.warn(TAG, `skip image size=${stat.size}`);
      return undefined;
    }
    const buf = new ArrayBuffer(stat.size);
    await fs.read(file.fd, buf);
    let mime = sniffMime(buf, uri);
    src = image.createImageSource(buf);
    let width = 0;
    let height = 0;
    try {
      const info = await src.getImageInfo();
      width = info.size.width;
      height = info.size.height;
      const im = (info.mimeType ?? '').toLowerCase();
      if (im.indexOf('heif') >= 0 || im.indexOf('heic') >= 0) {
        mime = 'image/heif';
      } else if (im.indexOf('avif') >= 0) {
        mime = 'image/avif';
      }
    } catch (e) {
      Log.warn(TAG, `image info ${JSON.stringify(e)}`);
    }
    let outBuf = buf;
    let outMime = mime;
    if (needsJpeg(mime, buf.byteLength)) {
      const packed = await packJpeg(src, width, height);
      if (!packed || packed.byteLength <= 0) {
        Log.warn(TAG, `heif/pack failed mime=${mime} ${width}x${height}`);
        return undefined;
      }
      outBuf = packed;
      outMime = 'image/jpeg';
    }
    const helper = new util.Base64Helper();
    const data = helper.encodeToStringSync(new Uint8Array(outBuf));
    const preview = await writePreview(cacheDir, outMime, outBuf);
    const local = preview.length > 0 ? preview : uri;
    const key = toFileUri(local);
    await decodePreview(key, outBuf);
    Log.info(TAG, `preview ${key} src=${mime} out=${outMime} map=${hasPreviewMap(key) ? '1' : '0'}`);
    return {
      data: data,
      mimeType: outMime,
      name: fileNameFromUri(uri),
      uri: local
    };
  } catch (e) {
    Log.warn(TAG, `read failed ${JSON.stringify(e)}`);
    return undefined;
  } finally {
    if (src) {
      try {
        await src.release();
      } catch (_e) {
      }
    }
    if (file) {
      try {
        await fs.close(file);
      } catch (_e) {
      }
    }
  }
}

async function decodePreview(key: string, buf: ArrayBuffer): Promise<void> {
  if (key.length === 0) {
    return;
  }
  let src: image.ImageSource | undefined = undefined;
  try {
    src = image.createImageSource(buf);
    const pm = await src.createPixelMap({
      desiredSize: {
        width: 168,
        height: 168
      }
    });
    dropPreviewMap(key);
    previewMaps.set(key, pm);
  } catch (e) {
    Log.warn(TAG, `pixelmap failed ${JSON.stringify(e)}`);
  } finally {
    if (src) {
      try {
        await src.release();
      } catch (_e) {
      }
    }
  }
}

async function packJpeg(src: image.ImageSource, width: number, height: number): Promise<ArrayBuffer | undefined> {
  const size = scaledSize(width, height, MAX_EDGE);
  const attempts: image.DecodingOptions[] = [
    { desiredSize: size, desiredDynamicRange: image.DecodingDynamicRange.SDR },
    { desiredDynamicRange: image.DecodingDynamicRange.SDR },
    { desiredSize: size },
    {}
  ];
  for (let i = 0; i < attempts.length; i++) {
    const packed = await packOnce(src, attempts[i]);
    if (packed && packed.byteLength > 0) {
      return packed;
    }
  }
  return undefined;
}

function scaledSize(width: number, height: number, maxEdge: number): image.Size {
  if (width <= 0 || height <= 0) {
    return { width: maxEdge, height: maxEdge };
  }
  if (width <= maxEdge && height <= maxEdge) {
    return { width: width, height: height };
  }
  const s = maxEdge / Math.max(width, height);
  return {
    width: Math.max(1, Math.round(width * s)),
    height: Math.max(1, Math.round(height * s))
  };
}

async function packOnce(src: image.ImageSource, opts: image.DecodingOptions): Promise<ArrayBuffer | undefined> {
  let pm: image.PixelMap | undefined = undefined;
  let packer: image.ImagePacker | undefined = undefined;
  try {
    pm = await src.createPixelMap(opts);
    packer = image.createImagePacker();
    return await packer.packToData(pm, { format: 'image/jpeg', quality: PACK_QUALITY });
  } catch (e) {
    Log.warn(TAG, `pack once ${JSON.stringify(e)}`);
    return undefined;
  } finally {
    if (packer) {
      try {
        await packer.release();
      } catch (_e) {
      }
    }
    if (pm) {
      try {
        pm.release();
      } catch (_e) {
      }
    }
  }
}

async function writePreview(cacheDir: string, mime: string, buf: ArrayBuffer): Promise<string> {
  if (!cacheDir || cacheDir.length === 0) {
    return '';
  }
  let out: fs.File | undefined = undefined;
  try {
    const ext = mime === 'image/png' ? 'png' : (mime === 'image/webp' ? 'webp' : 'jpg');
    const dest = `${cacheDir}/pv_${Date.now()}_${Math.floor(Math.random() * 100000)}.${ext}`;
    out = await fs.open(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    await fs.write(out.fd, buf);
    return dest;
  } catch (e) {
    Log.warn(TAG, `preview write failed: ${JSON.stringify(e)}`);
    return '';
  } finally {
    if (out) {
      try {
        await fs.close(out);
      } catch (_e) {
      }
    }
  }
}

function fileNameFromUri(uri: string): string {
  const q = uri.indexOf('?');
  const raw = q >= 0 ? uri.substring(0, q) : uri;
  const slash = raw.lastIndexOf('/');
  const name = slash >= 0 ? raw.substring(slash + 1) : raw;
  return name.length > 0 ? decodeSafe(name) : 'image';
}

function decodeSafe(name: string): string {
  try {
    return decodeURIComponent(name);
  } catch (_e) {
    return name;
  }
}
