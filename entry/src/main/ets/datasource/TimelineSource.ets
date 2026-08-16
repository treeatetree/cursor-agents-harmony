import { TimelineItem } from '../models/Timeline';

export class TimelineSource implements IDataSource {
  private list: TimelineItem[] = [];
  private listener: DataChangeListener | undefined = undefined;
  private pendingChange: number[] = [];

  totalCount(): number {
    return this.list.length;
  }

  getData(index: number): TimelineItem {
    return this.list[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listener = listener;
  }

  unregisterDataChangeListener(_listener: DataChangeListener): void {
    this.listener = undefined;
  }

  replaceAll(items: TimelineItem[]): void {
    this.pendingChange = [];
    this.list = items.slice();
    if (this.listener) {
      this.listener.onDataReloaded();
    }
  }

  append(item: TimelineItem): void {
    this.flushChanges();
    this.list.push(item);
    if (this.listener) {
      this.listener.onDataAdd(this.list.length - 1);
    }
  }

  updateAt(index: number, item: TimelineItem): void {
    if (index < 0 || index >= this.list.length) {
      return;
    }
    this.list[index] = item;
    if (this.listener) {
      this.listener.onDataChange(index);
    }
  }

  mutateAt(index: number, mutator: (item: TimelineItem) => void): void {
    if (index < 0 || index >= this.list.length) {
      return;
    }
    mutator(this.list[index]);
    this.queueChange(index);
  }

  removeAt(index: number): void {
    if (index < 0 || index >= this.list.length) {
      return;
    }
    const next: number[] = [];
    for (let i = 0; i < this.pendingChange.length; i++) {
      const p = this.pendingChange[i];
      if (p < index) {
        next.push(p);
      } else if (p > index) {
        next.push(p - 1);
      }
    }
    this.pendingChange = next;
    this.list.splice(index, 1);
    if (this.listener) {
      this.listener.onDataDelete(index);
    }
  }

  flushChanges(): void {
    if (this.pendingChange.length === 0) {
      return;
    }
    const idxs = this.pendingChange;
    this.pendingChange = [];
    if (!this.listener) {
      return;
    }
    for (let i = 0; i < idxs.length; i++) {
      this.listener.onDataChange(idxs[i]);
    }
  }

  private queueChange(index: number): void {
    for (let i = 0; i < this.pendingChange.length; i++) {
      if (this.pendingChange[i] === index) {
        return;
      }
    }
    this.pendingChange.push(index);
  }

  findIndexByKey(key: string): number {
    for (let i = 0; i < this.list.length; i++) {
      if (this.list[i].key === key) {
        return i;
      }
    }
    return -1;
  }

  getByKey(key: string): TimelineItem | undefined {
    const idx = this.findIndexByKey(key);
    return idx >= 0 ? this.list[idx] : undefined;
  }

  snapshot(): TimelineItem[] {
    return this.list.slice();
  }

  last(): TimelineItem | undefined {
    return this.list.length > 0 ? this.list[this.list.length - 1] : undefined;
  }
}
