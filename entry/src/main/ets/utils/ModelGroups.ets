import { ModelInfo, ModelVariant, ModelVariantParam } from '../models/Api';

export interface ModelVendorGroup {
  vendor: string;
  items: ModelInfo[];
}

export interface ModelParamRow {
  id: string;
  title: string;
  labels: string[];
  values: string[];
  selected: number;
}

const VENDOR_ORDER: string[] = ['Cursor', 'xAI', 'Anthropic', 'OpenAI', 'Google', '其他'];

export function shortModelName(name: string): string {
  return name
    .replace(/^Cursor\s+/i, '')
    .replace(/^Anthropic\s+/i, '')
    .replace(/^OpenAI\s+/i, '')
    .replace(/^Google\s+/i, '')
    .replace(/^xAI\s+/i, '')
    .replace(/^Claude\s+/i, '')
    .trim();
}

/** Composer chip from the picker rows so tapping a param always changes the label. */
export function formatChipFromRows(name: string, rows: ModelParamRow[]): string {
  const bits: string[] = [];
  const short = shortModelName(name);
  if (short.length > 0) {
    bits.push(short);
  }
  for (let i = 0; i < rows.length; i++) {
    const r = rows[i];
    if (r.selected < 0 || r.selected >= r.labels.length) {
      continue;
    }
    const val = r.selected < r.values.length ? r.values[r.selected].toLowerCase() : '';
    if (val === 'false' || val === '0' || val === 'off' || val === 'none') {
      continue;
    }
    const lab = r.labels[r.selected];
    if (lab.length > 0) {
      bits.push(lab);
    }
  }
  return bits.join(' · ');
}

export function paramRowsStamp(rows: ModelParamRow[]): string {
  let s = '';
  for (let i = 0; i < rows.length; i++) {
    s += `${rows[i].id}:${rows[i].selected};`;
  }
  return s;
}

/** Chip: model name + English effort depth + fast when on. */
export function formatFollowChip(name: string, params: Object[]): string {
  const bits: string[] = [];
  const short = shortModelName(name);
  if (short.length > 0) {
    bits.push(short);
  }
  let effort = '';
  let fastOn = false;
  for (let i = 0; i < params.length; i++) {
    const row = params[i] as Record<string, Object>;
    const id = `${row['id'] ?? ''}`.toLowerCase();
    const val = `${row['value'] ?? ''}`.toLowerCase().replace(/_/g, ' ').replace(/-/g, ' ').trim();
    if (id === 'effort' || id === 'reasoning') {
      if (isEffortOn(val)) {
        effort = val;
      }
    } else if (id === 'fast' || id === 'speed') {
      if (val === 'true' || val === '1' || val === 'fast') {
        fastOn = true;
      }
    }
  }
  if (effort.length > 0) {
    bits.push(effort);
  }
  if (fastOn) {
    bits.push('fast');
  }
  return bits.join(' · ');
}

function isEffortOn(val: string): boolean {
  return val.length > 0 && val !== 'false' && val !== '0' && val !== 'off' && val !== 'none';
}

function modelSentBits(model: Record<string, Object> | undefined): string[] {
  if (!model) {
    return ['Auto'];
  }
  const id = `${model['id'] ?? ''}`;
  if (id.length === 0) {
    return ['Auto'];
  }
  const bits: string[] = [];
  const short = shortModelName(id);
  bits.push(short.length > 0 ? short : id);
  const raw = model['params'];
  if (raw) {
    const rows = raw as Object[];
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i] as Record<string, Object>;
      const pid = `${row['id'] ?? ''}`.toLowerCase();
      const val = `${row['value'] ?? ''}`.toLowerCase().replace(/_/g, ' ').replace(/-/g, ' ').trim();
      if (pid === 'effort' || pid === 'reasoning') {
        if (isEffortOn(val)) {
          bits.push(val);
        }
      } else if (pid === 'fast' || pid === 'speed') {
        if (val === 'true' || val === '1' || val === 'fast') {
          bits.push('fast');
        }
      }
    }
  }
  return bits.length > 0 ? bits : ['Auto'];
}

/** One chip under a user bubble: model · effort · fast. */
export function modelSentTags(model: Record<string, Object> | undefined): string[] {
  return [modelSentBits(model).join(' · ')];
}

/** What we actually POST as `model` — for logs. */
export function formatModelSent(model: Record<string, Object> | undefined): string {
  return modelSentBits(model).join(' · ');
}

export function modelSentJson(model: Record<string, Object> | undefined): string {
  if (!model) {
    return '{}';
  }
  const id = `${model['id'] ?? ''}`;
  let line = `{"id":"${id}"`;
  const raw = model['params'];
  if (raw) {
    const rows = raw as Object[];
    const parts: string[] = [];
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i] as Record<string, Object>;
      parts.push(`{"id":"${row['id'] ?? ''}","value":"${row['value'] ?? ''}"}`);
    }
    if (parts.length > 0) {
      line = `${line},"params":[${parts.join(',')}]`;
    }
  }
  return `${line}}`;
}

export function isAutoModel(m: ModelInfo): boolean {
  const id = (m.id ?? '').trim().toLowerCase();
  const name = (m.displayName ?? m.id ?? '').trim().toLowerCase();
  return id === 'auto' || id === 'default' || name === 'auto' || name === '自动';
}

export function vendorOf(m: ModelInfo): string {
  const raw = `${m.id} ${m.displayName ?? ''}`.toLowerCase();
  if (raw.indexOf('grok') >= 0 || raw.indexOf('xai') >= 0) {
    return 'xAI';
  }
  if (raw.indexOf('opus') >= 0 || raw.indexOf('sonnet') >= 0 || raw.indexOf('haiku') >= 0 ||
    raw.indexOf('claude') >= 0 || raw.indexOf('anthropic') >= 0) {
    return 'Anthropic';
  }
  if (raw.indexOf('gpt') >= 0 || raw.indexOf('openai') >= 0 || raw.indexOf('o1') >= 0 ||
    raw.indexOf('o3') >= 0 || raw.indexOf('o4') >= 0) {
    return 'OpenAI';
  }
  if (raw.indexOf('gemini') >= 0 || raw.indexOf('gemma') >= 0) {
    return 'Google';
  }
  if (raw.indexOf('composer') >= 0 || raw.indexOf('fable') >= 0 || raw.indexOf('cursor') >= 0) {
    return 'Cursor';
  }
  return '其他';
}

export function groupModels(models: ModelInfo[]): ModelVendorGroup[] {
  const out: ModelVendorGroup[] = [];
  for (let i = 0; i < VENDOR_ORDER.length; i++) {
    const vendor = VENDOR_ORDER[i];
    const items: ModelInfo[] = [];
    for (let j = 0; j < models.length; j++) {
      const m = models[j];
      if (!isAutoModel(m) && vendorOf(m) === vendor) {
        items.push(m);
      }
    }
    if (items.length > 0) {
      out.push({ vendor: vendor, items: items });
    }
  }
  if (out.length === 0 && models.length > 0) {
    const rest: ModelInfo[] = [];
    for (let j = 0; j < models.length; j++) {
      if (!isAutoModel(models[j])) {
        rest.push(models[j]);
      }
    }
    if (rest.length > 0) {
      out.push({ vendor: '模型', items: rest });
    }
  }
  return out;
}

export function paramTitle(id: string, displayName?: string): string {
  if (id === 'effort' || id === 'reasoning') {
    return '推理深度';
  }
  if (id === 'fast' || id === 'speed') {
    return '速度';
  }
  if (id === 'thinking') {
    return '思考';
  }
  if (displayName && displayName.length > 0) {
    return displayName;
  }
  return id;
}

export function paramValueLabel(id: string, value: string, displayName?: string): string {
  if (id === 'fast') {
    if (value === 'true' || value === '1') {
      return '快速';
    }
    return '标准';
  }
  if (id === 'thinking') {
    if (value === 'true' || value === '1') {
      return '思考';
    }
    return '关闭';
  }
  if (displayName && displayName.length > 0 && displayName.indexOf('=') < 0 &&
    !isModelishName(displayName)) {
    return zhSpeed(displayName);
  }
  return zhSpeed(value);
}

export function buildParamRows(model: ModelInfo): ModelParamRow[] {
  const defs = model.params && model.params.length > 0 ? model.params : (model.parameters ?? []);
  const defaults = defaultVariantParams(model);
  const out: ModelParamRow[] = [];
  for (let i = 0; i < defs.length; i++) {
    const def = defs[i];
    const rawVals = def.values ?? [];
    if (rawVals.length < 2) {
      continue;
    }
    const labels: string[] = [];
    const values: string[] = [];
    for (let j = 0; j < rawVals.length; j++) {
      values.push(rawVals[j].value);
      labels.push(paramValueLabel(def.id, rawVals[j].value, rawVals[j].displayName));
    }
    let selected = 0;
    const preset = valueOf(defaults, def.id);
    if (preset.length > 0) {
      for (let j = 0; j < values.length; j++) {
        if (values[j] === preset) {
          selected = j;
          break;
        }
      }
    }
    out.push({
      id: def.id,
      title: paramTitle(def.id, def.displayName),
      labels: labels,
      values: values,
      selected: selected
    });
  }
  if (out.length > 0) {
    return out;
  }
  return buildParamRowsFromVariants(model);
}

function buildParamRowsFromVariants(model: ModelInfo): ModelParamRow[] {
  const variants = model.variants ?? [];
  const ids: string[] = [];
  for (let i = 0; i < variants.length; i++) {
    const params = variants[i].params ?? [];
    for (let j = 0; j < params.length; j++) {
      const id = params[j].id;
      if (id.length === 0 || id === 'cyber') {
        continue;
      }
      let seen = false;
      for (let k = 0; k < ids.length; k++) {
        if (ids[k] === id) {
          seen = true;
          break;
        }
      }
      if (!seen) {
        ids.push(id);
      }
    }
  }
  const defaults = defaultVariantParams(model);
  const out: ModelParamRow[] = [];
  for (let i = 0; i < ids.length; i++) {
    const id = ids[i];
    const values: string[] = [];
    const labels: string[] = [];
    for (let v = 0; v < variants.length; v++) {
      const raw = valueOf(variants[v].params ?? [], id);
      if (raw.length === 0) {
        continue;
      }
      let exists = false;
      for (let k = 0; k < values.length; k++) {
        if (values[k] === raw) {
          exists = true;
          break;
        }
      }
      if (!exists) {
        values.push(raw);
        labels.push(paramValueLabel(id, raw, undefined));
      }
    }
    if (values.length < 2) {
      continue;
    }
    let selected = 0;
    const preset = valueOf(defaults, id);
    for (let k = 0; k < values.length; k++) {
      if (values[k] === preset) {
        selected = k;
        break;
      }
    }
    out.push({
      id: id,
      title: paramTitle(id, undefined),
      labels: labels,
      values: values,
      selected: selected
    });
  }
  return out;
}

export function rowsToParams(rows: ModelParamRow[]): ModelVariantParam[] {
  const out: ModelVariantParam[] = [];
  for (let i = 0; i < rows.length; i++) {
    const r = rows[i];
    if (r.selected < 0 || r.selected >= r.values.length) {
      continue;
    }
    out.push({ id: r.id, value: r.values[r.selected] });
  }
  return out;
}

export function findModel(models: ModelInfo[], id: string): ModelInfo | undefined {
  if (id.length === 0) {
    return undefined;
  }
  for (let i = 0; i < models.length; i++) {
    if (models[i].id === id) {
      return models[i];
    }
  }
  return undefined;
}

function stripHiddenParams(params: ModelVariantParam[]): ModelVariantParam[] {
  const out: ModelVariantParam[] = [];
  for (let i = 0; i < params.length; i++) {
    if (params[i].id === 'cyber') {
      continue;
    }
    out.push(params[i]);
  }
  return out;
}

function paramWeight(id: string): number {
  if (id === 'context') {
    return 3;
  }
  if (id === 'effort' || id === 'reasoning' || id === 'thinking') {
    return 3;
  }
  if (id === 'fast' || id === 'speed') {
    return 1;
  }
  return 2;
}

function variantMatchScore(variant: ModelVariantParam[], wanted: ModelVariantParam[], preferId: string): number {
  if (preferId.length > 0) {
    const preferVal = valueOf(wanted, preferId);
    if (preferVal.length > 0 && valueOf(variant, preferId) !== preferVal) {
      return -1;
    }
  }
  let score = 0;
  for (let i = 0; i < wanted.length; i++) {
    const id = wanted[i].id;
    if (id === 'cyber') {
      continue;
    }
    if (valueOf(variant, id) === wanted[i].value) {
      score += paramWeight(id);
    }
  }
  return score;
}

function nearestVariant(model: ModelInfo, wanted: ModelVariantParam[], preferId: string): ModelVariantParam[] {
  const variants = model.variants ?? [];
  if (variants.length === 0) {
    return [];
  }
  let bestIdx = -1;
  let bestScore = -1;
  for (let i = 0; i < variants.length; i++) {
    const score = variantMatchScore(variants[i].params ?? [], wanted, preferId);
    if (score < 0) {
      continue;
    }
    let ranked = score;
    if (variants[i].isDefault === true) {
      ranked += 1;
    }
    if (ranked > bestScore) {
      bestScore = ranked;
      bestIdx = i;
    }
  }
  if (bestIdx < 0 && preferId.length > 0) {
    for (let i = 0; i < variants.length; i++) {
      const score = variantMatchScore(variants[i].params ?? [], wanted, '');
      if (score > bestScore) {
        bestScore = score;
        bestIdx = i;
      }
    }
  }
  if (bestIdx < 0) {
    return [];
  }
  return stripHiddenParams(variants[bestIdx].params ?? []);
}

function applyVariantToRows(rows: ModelParamRow[], variant: ModelVariantParam[]): ModelParamRow[] {
  const out: ModelParamRow[] = [];
  for (let i = 0; i < rows.length; i++) {
    const r = rows[i];
    const val = valueOf(variant, r.id);
    let selected = r.selected;
    if (val.length > 0) {
      for (let j = 0; j < r.values.length; j++) {
        if (r.values[j] === val) {
          selected = j;
          break;
        }
      }
    }
    out.push({
      id: r.id,
      title: r.title,
      labels: r.labels,
      values: r.values,
      selected: selected
    });
  }
  return out;
}

/**
 * After the user taps one param, snap the rest onto a real variant.
 * gpt-5.6-sol has no 1m+fast combo; picking 1m forces fast=false.
 */
export function snapParamRows(model: ModelInfo | undefined, rows: ModelParamRow[], preferId: string,
  preferIdx: number): ModelParamRow[] {
  const next: ModelParamRow[] = [];
  for (let i = 0; i < rows.length; i++) {
    const r = rows[i];
    let selected = r.selected;
    if (r.id === preferId && preferIdx >= 0 && preferIdx < r.values.length) {
      selected = preferIdx;
    }
    next.push({
      id: r.id,
      title: r.title,
      labels: r.labels,
      values: r.values,
      selected: selected
    });
  }
  if (!model || !model.variants || model.variants.length === 0) {
    return next;
  }
  const variant = nearestVariant(model, rowsToParams(next), preferId);
  if (variant.length === 0) {
    return next;
  }
  return applyVariantToRows(next, variant);
}

/** Submit-time: replace independent chips with one catalog variant (drops `cyber`). */
export function coerceParamsToVariant(model: ModelInfo | undefined, params: ModelVariantParam[]): ModelVariantParam[] {
  const cleaned = stripHiddenParams(params);
  if (!model || !model.variants || model.variants.length === 0 || cleaned.length === 0) {
    return cleaned;
  }
  const variant = nearestVariant(model, cleaned, '');
  if (variant.length === 0) {
    return cleaned;
  }
  return variant;
}

function defaultVariantParams(model: ModelInfo): ModelVariantParam[] {
  const variants = model.variants ?? [];
  for (let i = 0; i < variants.length; i++) {
    if (variants[i].isDefault === true) {
      return variants[i].params ?? [];
    }
  }
  if (variants.length > 0) {
    return variants[0].params ?? [];
  }
  return [];
}

function valueOf(params: ModelVariantParam[], id: string): string {
  for (let i = 0; i < params.length; i++) {
    if (params[i].id === id) {
      return params[i].value;
    }
  }
  return '';
}

export function variantSectionTitle(variants: ModelVariant[]): string {
  let effort = 0;
  let speed = 0;
  for (let i = 0; i < variants.length; i++) {
    const params = variants[i].params ?? [];
    for (let j = 0; j < params.length; j++) {
      const id = params[j].id;
      if (id === 'effort' || id === 'reasoning') {
        effort += 1;
      } else if (id === 'speed') {
        speed += 1;
      }
    }
  }
  if (effort > 0 && speed === 0) {
    return '推理深度';
  }
  if (speed > 0 && effort === 0) {
    return '速度';
  }
  return '模式';
}

export function zhSpeed(raw: string): string {
  const t = raw.trim().toLowerCase().replace(/_/g, ' ');
  if (t === 'fast') {
    return '快速';
  }
  if (t === 'max' || t === 'extra high' || t === 'extra-high') {
    return '最强';
  }
  if (t === 'high') {
    return '深度';
  }
  if (t === 'medium' || t === 'default' || t === 'standard') {
    return '标准';
  }
  if (t === 'thinking') {
    return '思考';
  }
  return raw;
}

function isModelishName(s: string): boolean {
  const t = s.toLowerCase();
  return t.indexOf('cursor') >= 0 || t.indexOf('grok') >= 0 || t.indexOf('gpt') >= 0 ||
    t.indexOf('opus') >= 0 || t.indexOf('composer') >= 0 || t.indexOf('gemini') >= 0 ||
    t.indexOf('fable') >= 0 || t.indexOf('sonnet') >= 0 || t.indexOf('claude') >= 0;
}

export function variantLabel(v: ModelVariant, idx: number): string {
  const params = v.params ?? [];
  const bits: string[] = [];
  for (let i = 0; i < params.length; i++) {
    const id = params[i].id;
    const value = params[i].value;
    if (id === 'cyber' && value === 'false') {
      continue;
    }
    if (id === 'fast') {
      bits.push(value === 'true' || value === '1' ? '快速' : '标准');
      continue;
    }
    if (id === 'thinking') {
      if (value === 'true' || value === '1') {
        bits.push('思考');
      }
      continue;
    }
    if (value === 'true' || value === 'false') {
      continue;
    }
    if (id === 'effort' || id === 'reasoning' || id === 'speed' || id === 'variant') {
      bits.push(zhSpeed(value));
      continue;
    }
    bits.push(zhSpeed(value));
  }
  if (bits.length > 0) {
    return bits.join(' · ');
  }
  const named = v.displayName ?? '';
  if (named.length > 0 && named.indexOf('=') < 0 && !isModelishName(named)) {
    return zhSpeed(named);
  }
  return `变体 ${idx + 1}`;
}
