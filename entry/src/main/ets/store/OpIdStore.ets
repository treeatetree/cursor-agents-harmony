import { PrefStore } from './PrefStore';

/** Local operation ids for create / follow-up. Persist until the result is known. */
export class OpIdStore {
  static nextId(prefix: string): string {
    const rand = Math.floor(Math.random() * 1000000000);
    return `${prefix}-${Date.now()}-${rand}`;
  }

  static async getOrCreate(scope: string, prefix: string): Promise<string> {
    const saved = await PrefStore.getInstance().getPendingOperationId(scope);
    if (saved.length > 0) {
      return saved;
    }
    const created = OpIdStore.nextId(prefix);
    await PrefStore.getInstance().setPendingOperationId(scope, created);
    return created;
  }

  static async clear(scope: string): Promise<void> {
    await PrefStore.getInstance().setPendingOperationId(scope, '');
  }

  static bodyScope(kind: string, identity: string, body: object): string {
    return `${kind}:${identity}:${hashText(JSON.stringify(body))}`;
  }
}

export function hashOperationBody(raw: string): string {
  return hashText(raw);
}

function hashText(raw: string): string {
  let h = 2166136261;
  for (let i = 0; i < raw.length; i++) {
    h ^= raw.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return (h >>> 0).toString(16);
}
