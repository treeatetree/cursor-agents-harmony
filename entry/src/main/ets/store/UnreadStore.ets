import { PrefStore, UnreadRow } from './PrefStore';
import { Notify } from '../utils/Notify';
import { clipNotice } from '../utils/MarkdownParse';
import { SessionDiag } from '../utils/SessionDiag';

export interface UnreadItem {
  id: string;
  name: string;
  statusZh: string;
  snippet: string;
  at: number;
  repo: string;
}

/**
 * Finished / failed runs the user has not opened yet.
 * Drives the app badge and the Inbox "what happened" strip.
 */
export class UnreadStore {
  private static instance: UnreadStore | undefined = undefined;
  private items: UnreadItem[] = [];
  private loaded: boolean = false;
  private lastBadge: number = -1;

  static getInstance(): UnreadStore {
    if (!UnreadStore.instance) {
      UnreadStore.instance = new UnreadStore();
    }
    return UnreadStore.instance;
  }

  async load(): Promise<void> {
    const rows = await PrefStore.getInstance().getUnreadItems();
    const next: UnreadItem[] = [];
    for (let i = 0; i < rows.length; i++) {
      next.push({
        id: rows[i].id,
        name: rows[i].name,
        statusZh: rows[i].statusZh,
        snippet: rows[i].snippet,
        at: rows[i].at,
        repo: rows[i].repo ?? ''
      });
    }
    this.items = next;
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

  first(): UnreadItem | undefined {
    return this.items.length > 0 ? this.items[0] : undefined;
  }

  isUnread(id: string): boolean {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id === id) {
        return true;
      }
    }
    return false;
  }

  lastSeenKey(id: string): string {
    return PrefStore.getInstance().lastSeenKey(id);
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

  async markFinished(id: string, name: string, statusZh: string, snippet: string,
    repo: string = ''): Promise<void> {
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
      at: Date.now(),
      repo: repo
    });
    if (next.length > 20) {
      next.length = 20;
    }
    this.items = next;
    SessionDiag.emit({
      tag: 'Unread',
      event: 'markFinished',
      agentId: id,
      extra: `n=${this.items.length} status=${statusZh} repo=${repo}`
    });
    await this.persist();
  }

  async markSeen(id: string, lastKey: string = ''): Promise<void> {
    if (id.length === 0) {
      return;
    }
    if (lastKey.length > 0) {
      await PrefStore.getInstance().setLastSeenKey(id, lastKey);
    }
    if (!this.isUnread(id)) {
      SessionDiag.emit({
        tag: 'Unread',
        event: 'markSeen',
        agentId: id,
        extra: `n=${this.items.length} already_read lastKey=${lastKey.length > 0 ? '1' : '0'}`
      });
      return;
    }
    const next: UnreadItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id !== id) {
        next.push(this.items[i]);
      }
    }
    this.items = next;
    SessionDiag.emit({
      tag: 'Unread',
      event: 'markSeen',
      agentId: id,
      extra: `n=${this.items.length} lastKey=${lastKey.length > 0 ? '1' : '0'}`
    });
    await this.persist();
  }

  async clearAll(): Promise<void> {
    if (this.items.length === 0) {
      return;
    }
    this.items = [];
    await this.persist();
  }

  private async persist(): Promise<void> {
    const rows: UnreadRow[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const it = this.items[i];
      rows.push({
        id: it.id,
        name: it.name,
        statusZh: it.statusZh,
        snippet: it.snippet,
        at: it.at,
        repo: it.repo
      });
    }
    await PrefStore.getInstance().setUnreadItems(rows);
    this.syncBadge();
    Notify.refreshInbox(this.items).catch(() => {
    });
  }

  syncBadge(): void {
    const n = this.items.length;
    if (n !== this.lastBadge) {
      this.lastBadge = n;
      SessionDiag.emit({
        tag: 'Unread',
        event: 'count',
        extra: `${n}`
      });
    }
    Notify.setBadge(n).catch(() => {
    });
  }
}
