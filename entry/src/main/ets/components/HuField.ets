import { Tokens } from '../theme/Tokens';

/** HeroUI field metrics — apply field_bg + radiusField + optional surface shadow on inputs. */
export class HuField {
  static radius(): number {
    return Tokens.radiusField;
  }
}
