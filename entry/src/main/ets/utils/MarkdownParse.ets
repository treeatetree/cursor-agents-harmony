export interface MdBlock {
  kind: string; // text | code | h1 | h2 | h3 | li | ol | quote | hr | table | image
  text: string;
  url: string;
  lang: string;
  indent: number;
}

export interface InlineSeg {
  text: string;
  bold: boolean;
  italic: boolean;
  code: boolean;
  url: string;
}

interface ScanChunk {
  text: string;
  next: number;
}

interface MdLink {
  label: string;
  url: string;
  consume: number;
}

/**
 * Conversation markdown used by MarkdownLite.
 * Links are inline so lists / headings / table cells can render [label](url).
 */
export function parseMarkdown(src: string): MdBlock[] {
  const out: MdBlock[] = [];
  const parts = (src ?? '').split('```');
  for (let i = 0; i < parts.length; i++) {
    const chunk = parts[i];
    if (i % 2 === 1) {
      let code = chunk;
      let lang = '';
      const nl = chunk.indexOf('\n');
      if (nl >= 0 && nl < 24) {
        const head = chunk.substring(0, nl).trim();
        if (head.length > 0 && head.length <= 16 && head.indexOf(' ') < 0) {
          lang = head;
          code = chunk.substring(nl + 1);
        }
      }
      if (code.endsWith('\n')) {
        code = code.substring(0, code.length - 1);
      }
      out.push(blockOf('code', code, '', lang, 0));
    } else if (chunk.length > 0) {
      pushStructured(chunk, out);
    }
  }
  return out;
}

export function tokenizeInline(s: string): InlineSeg[] {
  const out: InlineSeg[] = [];
  const parts = s.split('`');
  const matched = parts.length % 2 === 1;
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i];
    if (matched && i % 2 === 1) {
      if (part.length > 0) {
        out.push({ text: part, bold: false, italic: false, code: true, url: '' });
      }
    } else if (part.length > 0) {
      if (!matched && i > 0) {
        pushLinked('`' + part, out);
      } else {
        pushLinked(part, out);
      }
    } else if (!matched && i > 0 && i === parts.length - 1) {
      pushLinked('`', out);
    }
  }
  return out;
}

function blockOf(kind: string, text: string, url: string, lang: string, indent: number): MdBlock {
  return { kind: kind, text: text, url: url, lang: lang, indent: indent };
}

function pushStructured(text: string, out: MdBlock[]): void {
  const lines = text.split('\n');
  let para: string[] = [];
  let olCounter = 0;
  const flushPara = (): void => {
    if (para.length === 0) {
      return;
    }
    out.push(blockOf('text', para.join('\n'), '', '', 0));
    para = [];
  };
  let i = 0;
  while (i < lines.length) {
    const raw = lines[i];
    const trimmed = raw.trim();
    const indent = listIndent(raw);

    if (looksLikeTableRow(trimmed) && i + 1 < lines.length && looksLikeTableSep(lines[i + 1].trim())) {
      flushPara();
      olCounter = 0;
      const packed = collectTable(lines, i);
      out.push(blockOf('table', packed.text, '', '', 0));
      i = packed.next;
      continue;
    }

    const olMatch = matchOrdered(trimmed);
    if (olMatch !== null) {
      flushPara();
      olCounter += 1;
      out.push(blockOf('ol', olMatch, '', `${olCounter}`, indent));
      i += 1;
      continue;
    }
    if (olCounter > 0 && !isBullet(trimmed)) {
      olCounter = 0;
    }

    if (trimmed.startsWith('### ')) {
      flushPara();
      out.push(blockOf('h3', trimmed.substring(4), '', '', 0));
    } else if (trimmed.startsWith('## ')) {
      flushPara();
      out.push(blockOf('h2', trimmed.substring(3), '', '', 0));
    } else if (trimmed.startsWith('# ')) {
      flushPara();
      out.push(blockOf('h1', trimmed.substring(2), '', '', 0));
    } else if (isTaskLine(trimmed)) {
      flushPara();
      out.push(blockOf('li', taskLabel(trimmed), '', '', indent));
    } else if (isBullet(trimmed)) {
      flushPara();
      out.push(blockOf('li', trimmed.substring(2), '', '', indent));
    } else if (trimmed.startsWith('>')) {
      flushPara();
      const q = collectQuote(lines, i);
      out.push(blockOf('quote', q.text, '', '', 0));
      i = q.next;
      continue;
    } else if (trimmed === '---' || trimmed === '***' || trimmed === '___') {
      flushPara();
      out.push(blockOf('hr', '', '', '', 0));
    } else if (isMdImageLine(trimmed)) {
      flushPara();
      olCounter = 0;
      const mid = trimmed.indexOf('](');
      const end = trimmed.lastIndexOf(')');
      const alt = trimmed.substring(2, mid);
      const url = trimmed.substring(mid + 2, end).trim();
      out.push(blockOf('image', alt, url, '', 0));
    } else if (trimmed.length === 0) {
      flushPara();
    } else {
      para.push(raw);
    }
    i += 1;
  }
  flushPara();
}

function isBullet(trimmed: string): boolean {
  return trimmed.startsWith('- ') || trimmed.startsWith('* ');
}

function isMdImageLine(trimmed: string): boolean {
  if (!trimmed.startsWith('![')) {
    return false;
  }
  const mid = trimmed.indexOf('](');
  const end = trimmed.lastIndexOf(')');
  return mid > 1 && end > mid + 2;
}

function isTaskLine(trimmed: string): boolean {
  if (!trimmed.startsWith('- [') && !trimmed.startsWith('* [')) {
    return false;
  }
  const body = trimmed.substring(2);
  return body.startsWith('[ ] ') || body.startsWith('[x] ') || body.startsWith('[X] ');
}

function taskLabel(trimmed: string): string {
  const body = trimmed.substring(2);
  if (body.startsWith('[x] ') || body.startsWith('[X] ')) {
    return `☑ ${body.substring(4)}`;
  }
  if (body.startsWith('[ ] ')) {
    return `☐ ${body.substring(4)}`;
  }
  return body;
}

function listIndent(raw: string): number {
  let n = 0;
  let i = 0;
  while (i < raw.length) {
    const ch = raw.charAt(i);
    if (ch === ' ') {
      n += 1;
    } else if (ch === '\t') {
      n += 2;
    } else {
      break;
    }
    i += 1;
  }
  return Math.min(3, Math.floor(n / 2));
}

function collectQuote(lines: string[], start: number): ScanChunk {
  const bits: string[] = [];
  let i = start;
  while (i < lines.length) {
    const t = lines[i].trim();
    if (!t.startsWith('>')) {
      break;
    }
    bits.push(t.startsWith('> ') ? t.substring(2) : t.substring(1));
    i += 1;
  }
  return { text: bits.join('\n'), next: i };
}

function looksLikeTableRow(trimmed: string): boolean {
  if (trimmed.length < 3 || trimmed.indexOf('|') < 0) {
    return false;
  }
  return trimmed.indexOf('|') !== trimmed.lastIndexOf('|') || trimmed.startsWith('|');
}

function looksLikeTableSep(trimmed: string): boolean {
  if (!looksLikeTableRow(trimmed)) {
    return false;
  }
  let hasDash = false;
  for (let i = 0; i < trimmed.length; i++) {
    const ch = trimmed.charAt(i);
    if (ch === '-') {
      hasDash = true;
      continue;
    }
    if (ch !== '|' && ch !== ':' && ch !== ' ') {
      return false;
    }
  }
  return hasDash;
}

function collectTable(lines: string[], start: number): ScanChunk {
  const rows: string[] = [];
  let i = start;
  while (i < lines.length) {
    const t = lines[i].trim();
    if (!looksLikeTableRow(t)) {
      break;
    }
    if (!looksLikeTableSep(t)) {
      rows.push(packCells(t));
    }
    i += 1;
  }
  return { text: rows.join('\n'), next: i };
}

function packCells(line: string): string {
  let s = line.trim();
  if (s.startsWith('|')) {
    s = s.substring(1);
  }
  if (s.endsWith('|')) {
    s = s.substring(0, s.length - 1);
  }
  const cells: string[] = [];
  const parts = s.split('|');
  for (let i = 0; i < parts.length; i++) {
    cells.push(parts[i].trim());
  }
  return cells.join('\t');
}

export function tableRows(packed: string): string[][] {
  const out: string[][] = [];
  if (packed.length === 0) {
    return out;
  }
  const lines = packed.split('\n');
  for (let i = 0; i < lines.length; i++) {
    out.push(lines[i].split('\t'));
  }
  return out;
}

function matchOrdered(trimmed: string): string | null {
  let i = 0;
  while (i < trimmed.length && trimmed.charAt(i) >= '0' && trimmed.charAt(i) <= '9') {
    i++;
  }
  if (i > 0 && i < trimmed.length - 1 && trimmed.charAt(i) === '.' && trimmed.charAt(i + 1) === ' ') {
    return trimmed.substring(i + 2);
  }
  return null;
}

function pushLinked(s: string, out: InlineSeg[]): void {
  let rest = s;
  while (rest.length > 0) {
    const md = findMdLink(rest);
    const bare = findBareUrl(rest);
    let hit = -1;
    let useMd = false;
    if (md >= 0 && bare >= 0) {
      hit = Math.min(md, bare);
      useMd = md <= bare;
    } else if (md >= 0) {
      hit = md;
      useMd = true;
    } else if (bare >= 0) {
      hit = bare;
    }
    if (hit < 0) {
      pushBoldItalic(rest, out);
      return;
    }
    if (hit > 0) {
      pushBoldItalic(rest.substring(0, hit), out);
    }
    if (useMd) {
      const parsed: MdLink = takeMdLink(rest.substring(hit));
      out.push({ text: parsed.label, bold: false, italic: false, code: false, url: parsed.url });
      rest = rest.substring(hit + parsed.consume);
    } else {
      const taken = takeBareUrl(rest.substring(hit));
      out.push({ text: taken, bold: false, italic: false, code: false, url: taken });
      rest = rest.substring(hit + taken.length);
    }
  }
}

function findMdLink(s: string): number {
  let i = 0;
  while (i < s.length) {
    if (s.charAt(i) === '[' && s.indexOf('](', i) > i) {
      const mid = s.indexOf('](', i);
      const end = s.indexOf(')', mid + 2);
      if (end > mid) {
        return i;
      }
    }
    i += 1;
  }
  return -1;
}

function takeMdLink(s: string): MdLink {
  const mid = s.indexOf('](');
  const end = s.indexOf(')', mid + 2);
  let url = s.substring(mid + 2, end).trim();
  const low = url.toLowerCase();
  if (low.indexOf('https://') !== 0) {
    url = '';
  }
  return {
    label: s.substring(1, mid),
    url: url,
    consume: end + 1
  };
}

function findBareUrl(s: string): number {
  const a = s.indexOf('https://');
  const b = s.indexOf('http://');
  if (a >= 0 && b >= 0) {
    return Math.min(a, b);
  }
  return a >= 0 ? a : b;
}

function takeBareUrl(s: string): string {
  let end = 0;
  while (end < s.length) {
    const ch = s.charAt(end);
    if (ch === ' ' || ch === '\n' || ch === ')' || ch === ']' || ch === '"' || ch === '\'') {
      break;
    }
    end += 1;
  }
  return s.substring(0, end);
}

function pushBoldItalic(s: string, out: InlineSeg[]): void {
  const norm = s.replace(/__/g, '**');
  const boldParts = norm.split('**');
  for (let j = 0; j < boldParts.length; j++) {
    const chunk = boldParts[j];
    if (chunk.length === 0) {
      continue;
    }
    const bold = j % 2 === 1;
    const ital = chunk.split('*');
    if (ital.length === 1 || ital.length % 2 === 0) {
      out.push({ text: chunk, bold: bold, italic: false, code: false, url: '' });
    } else {
      for (let k = 0; k < ital.length; k++) {
        if (ital[k].length > 0) {
          out.push({ text: ital[k], bold: bold, italic: k % 2 === 1, code: false, url: '' });
        }
      }
    }
  }
}

export function clipNotice(raw: string, maxLen: number = 72): string {
  const t = stripMdMarks(raw ?? '');
  if (t.length === 0) {
    return '';
  }
  return t.length > maxLen ? `${t.substring(0, maxLen - 1)}…` : t;
}

function stripMdMarks(raw: string): string {
  let s = raw;
  let out = '';
  let i = 0;
  while (i < s.length) {
    if (s.charAt(i) === '[' && s.indexOf('](', i) > i) {
      const mid = s.indexOf('](', i);
      const end = s.indexOf(')', mid + 2);
      if (end > mid) {
        out += s.substring(i + 1, mid);
        i = end + 1;
        continue;
      }
    }
    const ch = s.charAt(i);
    if (ch === '#' || ch === '*' || ch === '_' || ch === '`' || ch === '>') {
      i += 1;
      continue;
    }
    if (ch === '\n' || ch === '\t') {
      out += ' ';
    } else {
      out += ch;
    }
    i += 1;
  }
  return out.replace(/  +/g, ' ').trim();
}

/** Cursor injects ```chat_selection fences; those are quotes, not code. */
export function isCitationFence(lang: string): boolean {
  const l = (lang ?? '').toLowerCase();
  return l === 'chat_selection' || l === 'selection' || l === 'quoted_selection';
}

/** Body of a selection fence — `selected_text` only, drop agent_id / line numbers. */
export function citationQuote(code: string): string {
  const raw = (code ?? '').replace(/\r\n/g, '\n');
  const lower = raw.toLowerCase();
  const key = 'selected_text:';
  const at = lower.indexOf(key);
  if (at >= 0) {
    let body = raw.substring(at + key.length);
    if (body.length > 0 && body.charAt(0) === ' ') {
      body = body.substring(1);
    }
    if (body.length > 0 && body.charAt(0) === '\n') {
      body = body.substring(1);
    }
    return stripWrapQuotes(body.trim());
  }
  const lines = raw.split('\n');
  const keep: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    const t = lines[i].trim();
    const colon = t.indexOf(':');
    if (colon > 0 && colon < 24 && t.indexOf(' ') < 0) {
      const k = t.substring(0, colon).toLowerCase();
      if (k === 'agent_id' || k === 'start_line' || k === 'end_line' || k === 'file') {
        continue;
      }
    }
    keep.push(lines[i]);
  }
  return keep.join('\n').trim();
}

function stripWrapQuotes(s: string): string {
  if (s.length >= 2) {
    const a = s.charAt(0);
    const b = s.charAt(s.length - 1);
    if ((a === '"' && b === '"') || (a === "'" && b === "'")) {
      return s.substring(1, s.length - 1);
    }
  }
  return s;
}
