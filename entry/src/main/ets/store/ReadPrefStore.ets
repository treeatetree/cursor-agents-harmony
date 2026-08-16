import { PrefStore } from './PrefStore';
import { Tokens } from '../theme/Tokens';

export type TypePref = 'default' | 'large';
export type DensityPref = 'comfortable' | 'compact';

/**
 * Type size + card density. Paints via Tokens.applyReadPref + AppStorage rev.
 */
export class ReadPrefStore {
  private static instance: ReadPrefStore | undefined = undefined;
  typePref: TypePref = 'default';
  densityPref: DensityPref = 'comfortable';
  rev: number = 0;

  static getInstance(): ReadPrefStore {
    if (!ReadPrefStore.instance) {
      ReadPrefStore.instance = new ReadPrefStore();
    }
    return ReadPrefStore.instance;
  }

  async load(): Promise<void> {
    const type = await PrefStore.getInstance().getTypePref();
    const density = await PrefStore.getInstance().getDensityPref();
    this.apply(type, density);
  }

  async setType(value: TypePref): Promise<void> {
    this.typePref = value;
    await PrefStore.getInstance().setTypePref(value);
    this.apply(this.typePref, this.densityPref);
  }

  async setDensity(value: DensityPref): Promise<void> {
    this.densityPref = value;
    await PrefStore.getInstance().setDensityPref(value);
    this.apply(this.typePref, this.densityPref);
  }

  private apply(type: string, density: string): void {
    this.typePref = type === 'large' ? 'large' : 'default';
    this.densityPref = density === 'compact' ? 'compact' : 'comfortable';
    Tokens.applyReadPref(this.typePref, this.densityPref);
    this.rev += 1;
    AppStorage.setOrCreate('readPrefRev', this.rev);
  }
}
