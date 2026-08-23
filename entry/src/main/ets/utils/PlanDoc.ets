import { TimelineItem } from '../models/Timeline';
import { ToolCallEvent } from '../models/Sse';
import { fileNameOf } from './DisplayFmt';
import { plainArg, shortPathForTool } from './StreamText';

export interface PlanTodo {
  content: string;
  status: string;
}

export interface PlanDoc {
  name: string;
  overview: string;
  todos: PlanTodo[];
  body: string;
  path: string;
}

interface FoldedYaml {
  text: string;
  next: number;
}

export function isPlanPath(path: string): boolean {
  const p = (path ?? '').replace(/\\/g, '/').toLowerCase();
  if (p.length === 0) {
    return false;
  }
  if (p.endsWith('.plan.md')) {
    return true;
  }
  if (p.indexOf('.cursor/plans/') >= 0 || p.indexOf('/artifacts/plans/') >= 0) {
    return true;
  }
  return p.indexOf('/plans/') >= 0 && p.endsWith('.md');
}

export function looksLikePlanDoc(text: string): boolean {
  const t = (text ?? '').trim();
  if (t.length < 12 || t.indexOf('---') !== 0) {
    return false;
  }
  const rest = t.substring(3);
  const end = rest.indexOf('\n---');
  if (end < 0) {
    return false;
  }
  return rest.substring(0, end).indexOf('todos:') >= 0;
}

export function isPlanToolEvent(name: string, argsText: string): boolean {
  if (isPlanPath(pathFromArgs(argsText))) {
    return true;
  }
  const n = (name ?? '').toLowerCase();
  return n.indexOf('createplan') >= 0 || n.indexOf('create_plan') >= 0;
}

export function shortPlanPath(path: string): string {
  const p = (path ?? '').replace(/\\/g, '/');
  if (p.length === 0) {
    return '';
  }
  const idx = p.indexOf('.cursor/plans/');
  if (idx >= 0) {
    return p.substring(idx);
  }
  const art = p.toLowerCase().indexOf('/artifacts/plans/');
  if (art >= 0) {
    return p.substring(art + '/artifacts/'.length);
  }
  const file = fileNameOf(p);
  return file.length > 0 ? file : shortPathForTool(p);
}

export function titleFromPlanPath(path: string): string {
  let base = fileNameOf(path);
  const low = base.toLowerCase();
  if (low.endsWith('.plan.md')) {
    base = base.substring(0, base.length - 8);
  } else if (low.endsWith('.md')) {
    base = base.substring(0, base.length - 3);
  }
  const under = base.lastIndexOf('_');
  if (under > 0) {
    const tail = base.substring(under + 1);
    if (isHexId(tail)) {
      const head = base.substring(0, under);
      if (head.length > 0 && head.toLowerCase() !== 'plan') {
        base = head;
      }
    }
  }
  return base;
}

export function parsePlanDoc(raw: string, path: string = ''): PlanDoc {
  const src = (raw ?? '').replace(/\r\n/g, '\n');
  const out: PlanDoc = {
    name: '',
    overview: '',
    todos: [],
    body: src.trim(),
    path: path
  };
  const trimmed = src.trim();
  if (!looksLikePlanDoc(trimmed)) {
    if (out.name.length === 0 && path.length > 0) {
      out.name = titleFromPlanPath(path);
    }
    return out;
  }
  const rest = trimmed.substring(3);
  const end = rest.indexOf('\n---');
  const fm = rest.substring(0, end);
  out.body = rest.substring(end + 4).replace(/^\n/, '').trim();
  parseFrontmatter(fm, out);
  if (out.name.length === 0 && path.length > 0) {
    out.name = titleFromPlanPath(path);
  }
  return out;
}

export function planItemFromDoc(key: string, runId: string, doc: PlanDoc, at: string = ''): TimelineItem {
  const row: TimelineItem = {
    key: key,
    kind: 'plan',
    runId: runId,
    text: encodePlanText(doc),
    statusLabel: doc.name.length > 0 ? doc.name : '计划',
    usageShort: shortPlanPath(doc.path),
    promptText: doc.overview,
    stepCount: doc.todos.length,
    collapsed: true
  };
  if (at.length > 0) {
    row.localAt = at;
  }
  return row;
}

export function applyPlanDoc(item: TimelineItem, doc: PlanDoc): void {
  item.kind = 'plan';
  item.text = encodePlanText(doc);
  item.statusLabel = doc.name.length > 0 ? doc.name : (item.statusLabel ?? '计划');
  if (doc.path.length > 0) {
    item.usageShort = shortPlanPath(doc.path);
  }
  if (doc.overview.length > 0) {
    item.promptText = doc.overview;
  }
  item.stepCount = doc.todos.length;
}

export function planDocFromItem(item: TimelineItem): PlanDoc {
  const doc = parsePlanDoc(item.text ?? '', item.usageShort ?? '');
  if (doc.name.length === 0) {
    doc.name = item.statusLabel ?? '';
  }
  if (doc.overview.length === 0) {
    doc.overview = item.promptText ?? '';
  }
  if (doc.path.length === 0) {
    doc.path = item.usageShort ?? '';
  }
  return doc;
}

export function foldPlanItems(items: TimelineItem[]): TimelineItem[] {
  if (!items || items.length === 0) {
    return items;
  }
  let changed = false;
  const lifted: TimelineItem[] = [];
  for (let i = 0; i < items.length; i++) {
    const it = items[i];
    if (it.kind === 'assistant' && looksLikePlanDoc(it.text ?? '')) {
      const doc = parsePlanDoc(it.text ?? '', it.usageShort ?? '');
      lifted.push(planItemFromDoc(it.key, it.runId, doc, it.localAt ?? ''));
      changed = true;
      continue;
    }
    if (it.kind === 'tool' && isPlanToolEvent(it.tool?.name ?? '', it.tool?.argsText ?? '')) {
      const doc = planDocFromTool(it.tool);
      const row = planItemFromDoc(planKeyForTool(it), it.runId, doc, it.localAt ?? '');
      row.tool = it.tool;
      row.streaming = it.streaming;
      lifted.push(row);
      changed = true;
      continue;
    }
    lifted.push(it);
  }
  const merged = mergePlansByRun(lifted);
  if (merged.length !== lifted.length) {
    changed = true;
  }
  return changed ? merged : items;
}

export function planDocFromTool(tool: ToolCallEvent | undefined): PlanDoc {
  const args = tool?.argsText ?? '';
  const path = pathFromTool(tool);
  const raw = contentsFromTool(tool);
  const doc = parsePlanDoc(raw, path);
  applyPlanToolArgs(args, doc);
  if (doc.name.length === 0 && path.length > 0) {
    doc.name = titleFromPlanPath(path);
  }
  if (path.length > 0) {
    doc.path = path;
  }
  return doc;
}

/** True when tool args should keep the full JSON (plan body is larger than 4k). */
export function keepFullToolArgs(name: string, argsJson: string): boolean {
  return isPlanToolEvent(name, argsJson);
}

export function previewTodos(todos: PlanTodo[], max: number = 3): PlanTodo[] {
  if (!todos || todos.length <= max) {
    return todos ?? [];
  }
  const out: PlanTodo[] = [];
  for (let i = 0; i < max; i++) {
    out.push(todos[i]);
  }
  return out;
}

function encodePlanText(doc: PlanDoc): string {
  if (looksLikePlanDoc(doc.body) || (doc.name.length === 0 && doc.todos.length === 0)) {
    return doc.body;
  }
  const lines: string[] = ['---', `name: ${yamlScalar(doc.name)}`];
  if (doc.overview.length > 0) {
    lines.push(`overview: ${yamlScalar(doc.overview)}`);
  }
  lines.push('todos:');
  for (let i = 0; i < doc.todos.length; i++) {
    const t = doc.todos[i];
    lines.push(`  - id: t-${i}`);
    lines.push(`    content: ${yamlScalar(t.content)}`);
    lines.push(`    status: ${t.status.length > 0 ? t.status : 'pending'}`);
  }
  lines.push('---', '', doc.body);
  return lines.join('\n');
}

function yamlScalar(v: string): string {
  const t = (v ?? '').trim();
  if (t.length === 0) {
    return '""';
  }
  if (t.indexOf(':') >= 0 || t.indexOf('#') >= 0 || t.indexOf('"') >= 0 || t.indexOf('\n') >= 0) {
    return `"${t.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
  }
  return t;
}

function parseFrontmatter(fm: string, out: PlanDoc): void {
  const lines = fm.split('\n');
  let i = 0;
  while (i < lines.length) {
    const raw = lines[i];
    const t = raw.trim();
    if (t.length === 0 || t.indexOf('#') === 0) {
      i += 1;
      continue;
    }
    if (t === 'todos:' || t.indexOf('todos:') === 0) {
      i = parseTodos(lines, i + 1, out);
      continue;
    }
    const colon = t.indexOf(':');
    if (colon <= 0) {
      i += 1;
      continue;
    }
    const key = t.substring(0, colon).trim();
    let val = t.substring(colon + 1).trim();
    if (val === '>' || val === '|') {
      const folded = collectFolded(lines, i + 1);
      val = folded.text;
      i = folded.next;
    } else {
      val = unquote(val);
      i += 1;
    }
    if (key === 'name' && out.name.length === 0) {
      out.name = val;
    } else if (key === 'overview' && out.overview.length === 0) {
      out.overview = val;
    }
  }
}

function parseTodos(lines: string[], start: number, out: PlanDoc): number {
  let i = start;
  let cur: PlanTodo | undefined = undefined;
  while (i < lines.length) {
    const raw = lines[i];
    const t = raw.trim();
    if (t.length === 0) {
      i += 1;
      continue;
    }
    if (!raw.startsWith(' ') && t.indexOf(':') > 0 && t.indexOf('- ') !== 0) {
      if (cur && cur.content.length > 0) {
        out.todos.push(cur);
      }
      return i;
    }
    if (t.indexOf('- ') === 0) {
      if (cur && cur.content.length > 0) {
        out.todos.push(cur);
      }
      cur = { content: '', status: 'pending' };
      const rest = t.substring(2).trim();
      applyTodoField(cur, rest);
      i += 1;
      continue;
    }
    if (cur) {
      applyTodoField(cur, t);
    }
    i += 1;
  }
  if (cur && cur.content.length > 0) {
    out.todos.push(cur);
  }
  return i;
}

function applyTodoField(todo: PlanTodo, line: string): void {
  const colon = line.indexOf(':');
  if (colon <= 0) {
    if (todo.content.length === 0 && line.indexOf('- ') !== 0) {
      todo.content = unquote(line);
    }
    return;
  }
  const key = line.substring(0, colon).trim();
  const val = unquote(line.substring(colon + 1).trim());
  if (key === 'content' && val.length > 0) {
    todo.content = val;
  } else if (key === 'status' && val.length > 0) {
    todo.status = val;
  }
}

function collectFolded(lines: string[], start: number): FoldedYaml {
  const bits: string[] = [];
  let i = start;
  while (i < lines.length) {
    const raw = lines[i];
    if (raw.length === 0) {
      break;
    }
    if (!raw.startsWith(' ') && !raw.startsWith('\t')) {
      break;
    }
    bits.push(raw.trim());
    i += 1;
  }
  const out: FoldedYaml = {
    text: bits.join(' '),
    next: i
  };
  return out;
}

function unquote(v: string): string {
  let t = (v ?? '').trim();
  if (t.length >= 2) {
    const a = t.charAt(0);
    const b = t.charAt(t.length - 1);
    if ((a === '"' && b === '"') || (a === "'" && b === "'")) {
      t = t.substring(1, t.length - 1);
    }
  }
  return t.replace(/\\"/g, '"').replace(/\\\\/g, '\\');
}

function isHexId(s: string): boolean {
  if (s.length < 6 || s.length > 16) {
    return false;
  }
  for (let i = 0; i < s.length; i++) {
    const c = s.charAt(i).toLowerCase();
    if ((c < '0' || c > '9') && (c < 'a' || c > 'f')) {
      return false;
    }
  }
  return true;
}

function pathFromTool(tool: ToolCallEvent | undefined): string {
  const fromArgs = pathFromArgs(tool?.argsText ?? '');
  if (fromArgs.length > 0) {
    return fromArgs;
  }
  return pathFromArgs(tool?.resultText ?? '');
}

function pathFromArgs(argsText: string): string {
  if (!argsText || argsText.length === 0) {
    return '';
  }
  try {
    const args = JSON.parse(argsText) as Record<string, Object>;
    const p = plainArg(args['path'] ?? args['file_path'] ?? args['target_file'] ?? args['filePath'] ??
      args['uri'] ?? args['file']);
    return p;
  } catch (_e) {
    return '';
  }
}

function contentsFromTool(tool: ToolCallEvent | undefined): string {
  if (!tool) {
    return '';
  }
  const argsText = tool.argsText ?? '';
  if (argsText.length > 0) {
    try {
      const args = JSON.parse(argsText) as Record<string, Object>;
      const c = plainArg(args['contents'] ?? args['new_string'] ?? args['newString'] ?? args['content'] ??
        args['plan'] ?? args['markdown'] ?? args['body']);
      if (c.length > 0) {
        return c;
      }
    } catch (_e) {
    }
  }
  const res = tool.resultText ?? '';
  if (res.length > 0 && looksLikePlanDoc(res)) {
    return res;
  }
  return '';
}

function applyPlanToolArgs(argsText: string, doc: PlanDoc): void {
  if (!argsText || argsText.length === 0) {
    return;
  }
  try {
    const args = JSON.parse(argsText) as Record<string, Object>;
    const name = plainArg(args['name'] ?? args['title']);
    if (name.length > 0 && doc.name.length === 0) {
      doc.name = name;
    }
    const overview = plainArg(args['overview'] ?? args['summary']);
    if (overview.length > 0 && doc.overview.length === 0) {
      doc.overview = overview;
    }
    if (doc.todos.length === 0) {
      const extra = todosFromArg(args['todos']);
      if (extra.length > 0) {
        doc.todos = extra;
      }
    }
  } catch (_e) {
  }
}

function todosFromArg(raw: Object | undefined): PlanTodo[] {
  if (!raw) {
    return [];
  }
  const arr = raw as Object[];
  if (arr.length === undefined) {
    return [];
  }
  const out: PlanTodo[] = [];
  for (let i = 0; i < arr.length; i++) {
    try {
      const rec = arr[i] as Record<string, Object>;
      const content = plainArg(rec['content'] ?? rec['title'] ?? rec['text']);
      if (content.length > 0) {
        const status = plainArg(rec['status']);
        out.push({ content: content, status: status.length > 0 ? status : 'pending' });
        continue;
      }
    } catch (_e) {
    }
    const s = `${arr[i]}`.trim();
    if (s.length > 0 && s.indexOf('[object') < 0) {
      out.push({ content: s, status: 'pending' });
    }
  }
  return out;
}

function planKeyForTool(item: TimelineItem): string {
  const id = item.tool?.callId ?? item.key;
  return `plan-${item.runId}-${id}`;
}

function mergePlansByRun(items: TimelineItem[]): TimelineItem[] {
  const out: TimelineItem[] = [];
  for (let i = 0; i < items.length; i++) {
    const it = items[i];
    if (it.kind !== 'plan') {
      out.push(it);
      continue;
    }
    let dest = -1;
    for (let j = 0; j < out.length; j++) {
      if (out[j].kind === 'plan' && shouldMergePlans(out[j], it)) {
        dest = j;
        break;
      }
    }
    if (dest >= 0) {
      mergePlanInto(out[dest], it);
      continue;
    }
    out.push(it);
  }
  return out;
}

export function shouldMergePlans(a: TimelineItem, b: TimelineItem): boolean {
  const da = planDocFromItem(a);
  const db = planDocFromItem(b);
  const pa = normalizePlanPath(da.path);
  const pb = normalizePlanPath(db.path);
  if (pa.length > 0 && pb.length > 0) {
    return pa === pb;
  }
  const na = planNameKey(da.name);
  const nb = planNameKey(db.name);
  if (na.length > 0 && nb.length > 0) {
    return na === nb;
  }
  return isPlanHusk(da) || isPlanHusk(db);
}

function planNameKey(name: string): string {
  const n = (name ?? '').trim();
  if (n.length === 0 || n === '计划' || n.toLowerCase() === 'plan') {
    return '';
  }
  return n;
}

function isPlanHusk(doc: PlanDoc): boolean {
  return planNameKey(doc.name).length === 0 && normalizePlanPath(doc.path).length === 0 &&
    doc.todos.length === 0 && (doc.body ?? '').trim().length === 0;
}

/** Drop artifact plans onto the matching turn; merge when the same plan already exists. */
export function weavePlans(items: TimelineItem[], plans: TimelineItem[]): TimelineItem[] {
  if (!plans || plans.length === 0) {
    return items;
  }
  const out: TimelineItem[] = [];
  for (let i = 0; i < items.length; i++) {
    out.push(items[i]);
  }
  const pending: TimelineItem[] = [];
  const used: boolean[] = [];
  for (let i = 0; i < out.length; i++) {
    used.push(false);
  }
  for (let p = 0; p < plans.length; p++) {
    let dest = -1;
    for (let i = 0; i < out.length; i++) {
      if (out[i].kind !== 'plan' || used[i]) {
        continue;
      }
      if (shouldMergePlans(out[i], plans[p])) {
        dest = i;
        break;
      }
    }
    if (dest >= 0) {
      mergePlanInto(out[dest], plans[p]);
      used[dest] = true;
      continue;
    }
    pending.push(plans[p]);
  }
  for (let p = 0; p < pending.length; p++) {
    const userIdxs: number[] = [];
    for (let i = 0; i < out.length; i++) {
      if (out[i].kind === 'userPrompt') {
        userIdxs.push(i);
      }
    }
    let at = out.length;
    if (userIdxs.length > 0) {
      // Artifact plans belong on later turns (CreatePlan is not in conversation GET).
      // A leftover plan sits at the END of its turn — after thinking/assistant —
      // so the plan card follows the reasoning, not the user prompt.
      const turn = userIdxs.length - pending.length + p;
      const idx = turn < 0 ? 0 : (turn < userIdxs.length ? turn : userIdxs.length - 1);
      at = (idx + 1 < userIdxs.length) ? userIdxs[idx + 1] : out.length;
    }
    out.splice(at, 0, pending[p]);
  }
  return out;
}

function normalizePlanPath(path: string): string {
  let p = (path ?? '').replace(/\\/g, '/');
  if (p.indexOf('file://') === 0) {
    p = p.substring(7);
  }
  const low = p.toLowerCase();
  const c = low.indexOf('.cursor/plans/');
  if (c >= 0) {
    return low.substring(c);
  }
  const a = low.indexOf('/artifacts/plans/');
  if (a >= 0) {
    return low.substring(a + 1);
  }
  const slash = low.lastIndexOf('/');
  return slash >= 0 ? low.substring(slash + 1) : low;
}

export function mergePlanInto(dst: TimelineItem, src: TimelineItem): void {
  const a = planDocFromItem(dst);
  const b = planDocFromItem(src);
  if (b.path.length > 0 && (a.path.length === 0 || a.path.indexOf('/') < 0)) {
    a.path = b.path;
  }
  if (planNameKey(b.name).length > 0 && planNameKey(a.name).length === 0) {
    a.name = b.name;
  }
  if (b.overview.length > a.overview.length) {
    a.overview = b.overview;
  }
  if (b.todos.length > a.todos.length) {
    a.todos = b.todos;
  }
  if (b.body.length > a.body.length) {
    a.body = b.body;
  }
  applyPlanDoc(dst, a);
  if (src.tool && !dst.tool) {
    dst.tool = src.tool;
  }
  if (src.pinnedOpen === true) {
    dst.pinnedOpen = true;
    dst.collapsed = false;
  }
}
