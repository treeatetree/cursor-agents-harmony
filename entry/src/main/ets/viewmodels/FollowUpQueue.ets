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
