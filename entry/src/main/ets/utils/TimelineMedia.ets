import { ConversationMessage } from '../models/Api';
import { TimelineItem } from '../models/Timeline';
import { PromptImage, previewSrc } from './ImagePicker';
import { isSafeHttpsUrl } from './SafeUrl';

/** Empty streaming think used as the live "still running" tail. */
export function isLiveWaitItem(item: TimelineItem): boolean {
  if (item.kind !== 'thinking') {
    return false;
  }
  if (item.streaming !== true) {
    return false;
  }
  return (item.text ?? '').trim().length === 0;
}

export function waitingKey(runId: string): string {
  return `waiting-${runId}`;
}

/** Cursor stepId without a title — not a user-facing "step N". */
export function isOpaqueStepLabel(named: string): boolean {
  const t = named.trim();
  if (t.length === 0) {
    return true;
  }
  if (t === '步骤' || t === 'step' || t === 'Step') {
    return true;
  }
  if (t.indexOf('步骤') === 0) {
    const rest = t.substring(2).trim();
    if (rest.length > 0 && Number(rest) > 0 && `${Number(rest)}` === rest) {
      return true;
    }
  }
  const low = t.toLowerCase();
  if (low.indexOf('step ') === 0) {
    const rest = t.substring(5).trim();
    if (rest.length > 0 && Number(rest) > 0 && `${Number(rest)}` === rest) {
      return true;
    }
  }
  return false;
}

export function isShowableImageUrl(url: string): boolean {
  if (!url || url.length === 0) {
    return false;
  }
  if (url.indexOf('data:') === 0) {
    return false;
  }
  if (url.indexOf('file://') === 0 || url.indexOf('/') === 0) {
    return true;
  }
  return isSafeHttpsUrl(url);
}

export function imageUrlsFromText(text: string): string[] {
  const out: string[] = [];
  const src = text ?? '';
  let i = 0;
  while (i < src.length) {
    const bang = src.indexOf('![', i);
    if (bang < 0) {
      break;
    }
    const mid = src.indexOf('](', bang);
    const end = mid >= 0 ? src.indexOf(')', mid + 2) : -1;
    if (mid < 0 || end < 0) {
      break;
    }
    const url = src.substring(mid + 2, end).trim();
    if (isShowableImageUrl(url)) {
      pushUnique(out, url);
    }
    i = end + 1;
  }
  return out;
}

export function imageUrlsFromPrompt(images: PromptImage[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < images.length; i++) {
    const src = previewSrc(images[i]);
    if (isShowableImageUrl(src)) {
      pushUnique(out, src);
    }
  }
  return out;
}

export function imageUrlsFromMessage(msg: ConversationMessage): string[] {
  const out: string[] = imageUrlsFromText(msg.text ?? '');
  const extra = msg.images;
  if (extra && extra.length > 0) {
    for (let i = 0; i < extra.length; i++) {
      const url = imageUrlFromUnknown(extra[i]);
      if (url.length > 0) {
        pushUnique(out, url);
      }
    }
  }
  return out;
}

export function extraImageUrls(msg: ConversationMessage): string[] {
  const fromText = imageUrlsFromText(msg.text ?? '');
  const all = imageUrlsFromMessage(msg);
  const out: string[] = [];
  for (let i = 0; i < all.length; i++) {
    let seen = false;
    for (let j = 0; j < fromText.length; j++) {
      if (fromText[j] === all[i]) {
        seen = true;
        break;
      }
    }
    if (!seen) {
      out.push(all[i]);
    }
  }
  return out;
}

export function pickMessageTime(msg: ConversationMessage): string {
  const direct = `${msg.createdAt ?? ''}`.trim();
  if (direct.length > 0) {
    return direct;
  }
  const rec = msg as Object as Record<string, Object>;
  const alt = `${rec['created_at'] ?? rec['timestamp'] ?? ''}`.trim();
  return alt;
}

function imageUrlFromUnknown(raw: Object): string {
  if (typeof raw === 'string') {
    const s = raw as string;
    return isShowableImageUrl(s) ? s : '';
  }
  try {
    const rec = raw as Object as Record<string, Object>;
    const url = `${rec['url'] ?? rec['src'] ?? rec['uri'] ?? ''}`.trim();
    if (isShowableImageUrl(url)) {
      return url;
    }
  } catch (_e) {
  }
  return '';
}

function pushUnique(out: string[], url: string): void {
  for (let i = 0; i < out.length; i++) {
    if (out[i] === url) {
      return;
    }
  }
  out.push(url);
}
