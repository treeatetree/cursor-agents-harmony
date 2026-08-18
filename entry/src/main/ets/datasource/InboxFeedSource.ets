import { InboxFeedRow } from '../utils/InboxGrouping';

export class InboxFeedSource implements IDataSource {
  private list: InboxFeedRow[] = [];
  private listener: DataChangeListener | undefined = undefined;

  totalCount(): number {
    return this.list.length;
  }

  getData(index: number): InboxFeedRow {
    return this.list[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listener = listener;
  }

  unregisterDataChangeListener(_listener: DataChangeListener): void {
    this.listener = undefined;
  }

  replaceAll(items: InboxFeedRow[]): void {
    this.list = items.slice();
    if (this.listener) {
      this.listener.onDataReloaded();
    }
  }
}
