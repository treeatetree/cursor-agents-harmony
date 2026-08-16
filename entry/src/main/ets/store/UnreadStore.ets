import { PrefStore } from './PrefStore';
import { Notify } from '../utils/Notify';
import { clipNotice } from '../utils/MarkdownParse';

export interface UnreadItem {
  id: string;
  name: string;
  statusZh: string;
  snippet: string;
  at: number;
}

/**
 * Finished / failed runs the user has not opened yet.
 * Drives the app badge and the Inbox "what happened" strip.
 */
export class UnreadStore {
  private static instance: UnreadStore | undefined = undefined;
  private items: UnreadItem[] = [];
  private loaded: boolean = false;

  static getInstance(): UnreadStore {
    if (!UnreadStore.instance) {
      UnreadStore.instance = new UnreadStore();
    }
    return UnreadStore.instance;
  }

  async load(): Promise<void> {
    this.items = await PrefStore.getInstance().getUnreadItems();
    this.loaded = true;
    this.syncBadge();
  }

  peek(): UnreadItem[] {
    return this.items.slice();
  }

  ids(): string[] {
    const out: string[] = [];
    for (let i = 0; i < this.items.length; i++) {
      out.push(this.items[i].id);
    }
    return out;
  }

  count(): number {
    return this.items.length;
  }

  firstId(): string {
    return this.items.length > 0 ? this.items[0].id : '';
  }

  isUnread(id: string): boolean {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id === id) {
        return true;
      }
    }
    return false;
  }

  headline(): string {
    if (this.items.length === 0) {
      return '';
    }
    const first = this.items[0];
    const bit = first.snippet.length > 0 ? ` · ${first.snippet}` : '';
    if (this.items.length === 1) {
      return `${first.name} ${first.statusZh}${bit}`;
    }
    return `${this.items.length} 条新结果 · ${first.name} ${first.statusZh}`;
  }

  async markFinished(id: string, name: string, statusZh: string, snippet: string): Promise<void> {
    if (id.length === 0) {
      return;
    }
    const next: UnreadItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id !== id) {
        next.push(this.items[i]);
      }
    }
    next.unshift({
      id: id,
      name: name.length > 0 ? name : '任务',
      statusZh: statusZh,
      snippet: clipNotice(snippet, 56),
      at: Date.now()
    });
    if (next.length > 20) {
      next.length = 20;
    }
    this.items = next;
    await this.persist();
  }

  async markSeen(id: string): Promise<void> {
    if (id.length === 0 || !this.isUnread(id)) {
      return;
    }
    const next: UnreadItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id !== id) {
        next.push(this.items[i]);
      }
    }
    this.items = next;
    await this.persist();
  }

  private async persist(): Promise<void> {
    await PrefStore.getInstance().setUnreadItems(this.items);
    this.syncBadge();
  }

  syncBadge(): void {
    Notify.setBadge(this.items.length).catch(() => {
    });
  }
}
