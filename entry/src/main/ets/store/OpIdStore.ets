/** Local operation ids for create / follow-up. Persist until the result is known. */
export class OpIdStore {
  static nextId(prefix: string): string {
    const rand = Math.floor(Math.random() * 1000000000);
    return `${prefix}-${Date.now()}-${rand}`;
  }
}
