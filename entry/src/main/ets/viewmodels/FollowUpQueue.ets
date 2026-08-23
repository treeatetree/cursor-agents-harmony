import { PromptImage } from '../utils/ImagePicker';

export interface QueuedFollowUp {
  text: string;
  images: PromptImage[];
  retries: number;
}

export function emptyQueue(): QueuedFollowUp {
  return { text: '', images: [], retries: 0 };
}

export function canFlushQueue(q: QueuedFollowUp, sending: boolean, runActive: boolean): boolean {
  if (q.text.trim().length === 0) {
    return false;
  }
  return !sending && !runActive && q.retries < 5;
}

/** 1s / 2s / 4s … capped at 8s. */
export function queueBackoffMs(retries: number): number {
  let n = retries;
  if (n < 0) {
    n = 0;
  }
  let ms = 1000;
  let i = 0;
  while (i < n && ms < 8000) {
    ms = ms * 2;
    i += 1;
  }
  if (ms > 8000) {
    return 8000;
  }
  return ms;
}
