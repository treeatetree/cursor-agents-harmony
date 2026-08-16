import { PrefStore } from './PrefStore';

export interface SeedCreate {
  localId: string;
  prompt: string;
  name: string;
  body: Record<string, Object>;
}

/** Hands a new-task payload from the composer page to the detail thread. */
export class CreateDraftStore {
  private static instance: CreateDraftStore | undefined = undefined;
  private draft: SeedCreate | undefined = undefined;

  static getInstance(): CreateDraftStore {
    if (!CreateDraftStore.instance) {
      CreateDraftStore.instance = new CreateDraftStore();
    }
    return CreateDraftStore.instance;
  }

  park(draft: SeedCreate): void {
    this.draft = draft;
    try {
      PrefStore.getInstance().setCreateSeed(JSON.stringify(draft)).catch(() => {
      });
    } catch (_e) {
    }
  }

  peek(): SeedCreate | undefined {
    return this.draft;
  }

  take(): SeedCreate | undefined {
    const d = this.draft;
    this.draft = undefined;
    PrefStore.getInstance().setCreateSeed('').catch(() => {
    });
    return d;
  }

  clear(): void {
    this.draft = undefined;
    PrefStore.getInstance().setCreateSeed('').catch(() => {
    });
  }

  async hydrate(): Promise<void> {
    if (this.draft) {
      return;
    }
    try {
      const raw = await PrefStore.getInstance().getCreateSeed();
      if (raw.length === 0) {
        return;
      }
      this.draft = JSON.parse(raw) as SeedCreate;
    } catch (_e) {
    }
  }
}
