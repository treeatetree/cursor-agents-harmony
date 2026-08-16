import { AgentSummary } from '../models/Api';

export class AgentListSource implements IDataSource {
  private list: AgentSummary[] = [];
  private listener: DataChangeListener | undefined = undefined;

  totalCount(): number {
    return this.list.length;
  }

  getData(index: number): AgentSummary {
    return this.list[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listener = listener;
  }

  unregisterDataChangeListener(_listener: DataChangeListener): void {
    this.listener = undefined;
  }

  replaceAll(items: AgentSummary[]): void {
    this.list = items.slice();
    if (this.listener) {
      this.listener.onDataReloaded();
    }
  }

  prepend(item: AgentSummary): void {
    this.list = [item].concat(this.list);
    if (this.listener) {
      this.listener.onDataAdd(0);
    }
  }

  updateAt(index: number, item: AgentSummary): void {
    if (index < 0 || index >= this.list.length) {
      return;
    }
    this.list[index] = item;
    if (this.listener) {
      this.listener.onDataChange(index);
    }
  }

  removeById(id: string): void {
    let removed = -1;
    const next: AgentSummary[] = [];
    for (let i = 0; i < this.list.length; i++) {
      if (this.list[i].id === id) {
        removed = i;
      } else {
        next.push(this.list[i]);
      }
    }
    if (removed < 0) {
      return;
    }
    this.list = next;
    if (this.listener) {
      this.listener.onDataDelete(removed);
    }
  }

  /** Only true when an ACTIVE agent may still have a non-terminal latest run. */
  hasActiveLatest(): boolean {
    for (let i = 0; i < this.list.length; i++) {
      const a = this.list[i];
      if (a.status === 'ACTIVE' && a.latestRunId && a.latestRunId.length > 0) {
        // Prefer explicit runStatus if enriched on the object.
        const extra = a as object as Record<string, string>;
        const rs = extra['latestRunStatus'] ?? '';
        if (rs.length === 0 ||
          (rs !== 'FINISHED' && rs !== 'ERROR' && rs !== 'CANCELLED' && rs !== 'EXPIRED')) {
          return true;
        }
      }
    }
    return false;
  }

  snapshot(): AgentSummary[] {
    return this.list.slice();
  }
}
