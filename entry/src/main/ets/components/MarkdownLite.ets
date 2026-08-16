import { common } from '@kit.AbilityKit';
import { Tokens } from '../theme/Tokens';
import { copyToClipboard } from '../utils/Clipboard';
import { showToast } from '../utils/AppToast';
import { Haptics } from '../utils/Haptics';

interface MdBlock {
  kind: string; // text | code | link | h1 | h2 | h3 | li | ol | quote | hr | table
  text: string;
  url: string;
  lang: string;
}

interface InlineSeg {
  text: string;
  bold: boolean;
  italic: boolean;
  code: boolean;
}

interface TableRow {
  key: string;
  cells: string[];
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
 * Conversation markdown: headings, lists, quotes, tables, fenced/inline code,
 * bold/italic, [label](url) and bare links.
 */
@Component
export struct MarkdownLite {
  @Prop content: string = '';
  @Prop compact: boolean = false;

  private proseSize(): number {
    return this.compact ? Tokens.typeCallout : Tokens.typeProse;
  }

  private proseLine(): number {
    return this.compact ? Tokens.lineBody : Tokens.lineProse;
  }

  private listLine(): number {
    return this.compact ? 20 : Tokens.lineList;
  }

  /** Process / compact rows sit back; the main answer stays ink. */
  private bodyColor(): Resource {
    return this.compact ? $r('app.color.text_secondary') : $r('app.color.text_primary');
  }

  private blocks(): MdBlock[] {
    const out: MdBlock[] = [];
    const src = this.content ?? '';
    const parts = src.split('```');
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
        out.push({ kind: 'code', text: code, url: '', lang: lang });
      } else if (chunk.length > 0) {
        this.pushStructured(chunk, out);
      }
    }
    return out;
  }

  private pushStructured(text: string, out: MdBlock[]): void {
    const lines = text.split('\n');
    let para: string[] = [];
    let olCounter = 0;
    const flushPara = (): void => {
      if (para.length === 0) {
        return;
      }
      this.pushRichText(para.join('\n'), out);
      para = [];
    };
    let i = 0;
    while (i < lines.length) {
      const raw = lines[i];
      const trimmed = raw.trim();

      if (this.looksLikeTableRow(trimmed) && i + 1 < lines.length &&
        this.looksLikeTableSep(lines[i + 1].trim())) {
        flushPara();
        olCounter = 0;
        const packed = this.collectTable(lines, i);
        out.push({ kind: 'table', text: packed.text, url: '', lang: '' });
        i = packed.next;
        continue;
      }

      const olMatch = this.matchOrdered(trimmed);
      if (olMatch !== null) {
        flushPara();
        olCounter += 1;
        out.push({ kind: 'ol', text: olMatch, url: '', lang: `${olCounter}` });
        i += 1;
        continue;
      }
      if (olCounter > 0 && !(trimmed.startsWith('- ') || trimmed.startsWith('* '))) {
        olCounter = 0;
      }

      if (trimmed.startsWith('### ')) {
        flushPara();
        out.push({ kind: 'h3', text: trimmed.substring(4), url: '', lang: '' });
      } else if (trimmed.startsWith('## ')) {
        flushPara();
        out.push({ kind: 'h2', text: trimmed.substring(3), url: '', lang: '' });
      } else if (trimmed.startsWith('# ')) {
        flushPara();
        out.push({ kind: 'h1', text: trimmed.substring(2), url: '', lang: '' });
      } else if (trimmed.startsWith('- [') || trimmed.startsWith('* [')) {
        flushPara();
        out.push({ kind: 'li', text: this.taskLabel(trimmed), url: '', lang: '' });
      } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        flushPara();
        out.push({ kind: 'li', text: trimmed.substring(2), url: '', lang: '' });
      } else if (trimmed.startsWith('>')) {
        flushPara();
        const q = this.collectQuote(lines, i);
        out.push({ kind: 'quote', text: q.text, url: '', lang: '' });
        i = q.next;
        continue;
      } else if (trimmed === '---' || trimmed === '***' || trimmed === '___') {
        flushPara();
        out.push({ kind: 'hr', text: '', url: '', lang: '' });
      } else if (trimmed.length === 0) {
        flushPara();
      } else {
        para.push(raw);
      }
      i += 1;
    }
    flushPara();
  }

  private taskLabel(trimmed: string): string {
    const body = trimmed.substring(2);
    if (body.startsWith('[x] ') || body.startsWith('[X] ')) {
      return `☑ ${body.substring(4)}`;
    }
    if (body.startsWith('[ ] ')) {
      return `☐ ${body.substring(4)}`;
    }
    return body;
  }

  private collectQuote(lines: string[], start: number): ScanChunk {
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

  private looksLikeTableRow(trimmed: string): boolean {
    if (trimmed.length < 3 || trimmed.indexOf('|') < 0) {
      return false;
    }
    return trimmed.indexOf('|') !== trimmed.lastIndexOf('|') || trimmed.startsWith('|');
  }

  private looksLikeTableSep(trimmed: string): boolean {
    if (!this.looksLikeTableRow(trimmed)) {
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

  private collectTable(lines: string[], start: number): ScanChunk {
    const rows: string[] = [];
    let i = start;
    while (i < lines.length) {
      const t = lines[i].trim();
      if (!this.looksLikeTableRow(t)) {
        break;
      }
      if (!this.looksLikeTableSep(t)) {
        rows.push(this.packCells(t));
      }
      i += 1;
    }
    return { text: rows.join('\n'), next: i };
  }

  private packCells(line: string): string {
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

  private tableRows(packed: string): TableRow[] {
    const out: TableRow[] = [];
    if (packed.length === 0) {
      return out;
    }
    const lines = packed.split('\n');
    for (let i = 0; i < lines.length; i++) {
      out.push({ key: `tr-${i}`, cells: lines[i].split('\t') });
    }
    return out;
  }

  private matchOrdered(trimmed: string): string | null {
    let i = 0;
    while (i < trimmed.length && trimmed.charAt(i) >= '0' && trimmed.charAt(i) <= '9') {
      i++;
    }
    if (i > 0 && i < trimmed.length - 1 && trimmed.charAt(i) === '.' && trimmed.charAt(i + 1) === ' ') {
      return trimmed.substring(i + 2);
    }
    return null;
  }

  private pushRichText(text: string, out: MdBlock[]): void {
    let rest = text;
    while (rest.length > 0) {
      const md = this.findMdLink(rest);
      const bare = this.findBareUrl(rest);
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
        out.push({ kind: 'text', text: rest, url: '', lang: '' });
        return;
      }
      if (hit > 0) {
        out.push({ kind: 'text', text: rest.substring(0, hit), url: '', lang: '' });
      }
      if (useMd) {
        const parsed: MdLink = this.takeMdLink(rest.substring(hit));
        out.push({ kind: 'link', text: parsed.label, url: parsed.url, lang: '' });
        rest = rest.substring(hit + parsed.consume);
      } else {
        const taken = this.takeBareUrl(rest.substring(hit));
        out.push({ kind: 'link', text: taken, url: taken, lang: '' });
        rest = rest.substring(hit + taken.length);
      }
    }
  }

  private findMdLink(s: string): number {
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

  private takeMdLink(s: string): MdLink {
    const mid = s.indexOf('](');
    const end = s.indexOf(')', mid + 2);
    return {
      label: s.substring(1, mid),
      url: s.substring(mid + 2, end),
      consume: end + 1
    };
  }

  private findBareUrl(s: string): number {
    const a = s.indexOf('https://');
    const b = s.indexOf('http://');
    if (a >= 0 && b >= 0) {
      return Math.min(a, b);
    }
    return a >= 0 ? a : b;
  }

  private takeBareUrl(s: string): string {
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

  private open(url: string): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    ctx.openLink(url).catch(() => {
    });
  }

  private tokenizeInline(s: string): InlineSeg[] {
    const out: InlineSeg[] = [];
    const parts = s.split('`');
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      if (i % 2 === 1) {
        if (part.length > 0) {
          out.push({ text: part, bold: false, italic: false, code: true });
        }
      } else {
        this.pushBoldItalic(part, out);
      }
    }
    return out;
  }

  private pushBoldItalic(s: string, out: InlineSeg[]): void {
    const norm = s.replace(/__/g, '**');
    const boldParts = norm.split('**');
    for (let j = 0; j < boldParts.length; j++) {
      const chunk = boldParts[j];
      if (chunk.length === 0) {
        continue;
      }
      const bold = j % 2 === 1;
      const ital = chunk.split('*');
      if (ital.length === 1) {
        out.push({ text: chunk, bold: bold, italic: false, code: false });
      } else {
        for (let k = 0; k < ital.length; k++) {
          if (ital[k].length > 0) {
            out.push({ text: ital[k], bold: bold, italic: k % 2 === 1, code: false });
          }
        }
      }
    }
  }

  @Builder
  renderInline(text: string, size: number, color: ResourceColor, weight: FontWeight = FontWeight.Normal,
    line: number = Tokens.lineProse) {
    Text() {
      ForEach(this.tokenizeInline(text), (seg: InlineSeg, idx: number) => {
        if (seg.code) {
          Span(` ${seg.text} `)
            .fontSize(size - 1)
            .fontColor($r('app.color.text_primary'))
            .fontFamily('monospace')
            .backgroundColor($r('app.color.code_inline_bg'))
        } else if (seg.bold) {
          Span(seg.text)
            .fontSize(size)
            .fontColor($r('app.color.text_primary'))
            .fontWeight(FontWeight.Bold)
            .fontStyle(seg.italic ? FontStyle.Italic : FontStyle.Normal)
        } else if (seg.italic) {
          Span(seg.text)
            .fontSize(size)
            .fontColor($r('app.color.text_secondary'))
            .fontWeight(weight)
            .fontStyle(FontStyle.Italic)
        } else {
          Span(seg.text)
            .fontSize(size)
            .fontColor(color)
            .fontWeight(weight)
            .fontStyle(FontStyle.Normal)
        }
      }, (seg: InlineSeg, idx: number) => `s-${idx}-${seg.text.length}-${seg.code ? 1 : 0}-${seg.bold ? 1 : 0}`)
    }
    .lineHeight(line)
    .width('100%')
  }

  build() {
    Column() {
      ForEach(this.blocks(), (b: MdBlock, idx: number) => {
        if (b.kind === 'code') {
          this.codeBlock(b)
        } else if (b.kind === 'table') {
          this.tableBlock(b.text, idx)
        } else if (b.kind === 'link') {
          Text(b.text)
            .fontSize(this.proseSize())
            .fontColor($r('app.color.text_primary'))
            .fontWeight(FontWeight.Medium)
            .lineHeight(this.proseLine())
            .decoration({ type: TextDecorationType.Underline, color: $r('app.color.text_tertiary') })
            .width('100%')
            .constraintSize({ minHeight: Tokens.touchMin })
            .margin({ top: 4, bottom: 4 })
            .onClick(() => {
              this.open(b.url);
            })
        } else if (b.kind === 'h1') {
          Column() {
            this.renderInline(b.text, this.compact ? Tokens.typeBody : Tokens.typeTitle,
              $r('app.color.text_primary'),
              FontWeight.Bold, this.compact ? Tokens.lineBody : 26)
          }
          .width('100%')
          .margin({ top: idx > 0 ? 18 : 0, bottom: 8 })
        } else if (b.kind === 'h2') {
          Column() {
            this.renderInline(b.text, this.compact ? Tokens.typeBody : Tokens.typeHeadline,
              $r('app.color.text_primary'),
              FontWeight.Bold, this.compact ? Tokens.lineBody : Tokens.lineProse)
          }
          .width('100%')
          .margin({ top: idx > 0 ? 16 : 0, bottom: 6 })
        } else if (b.kind === 'h3') {
          Column() {
            this.renderInline(b.text, this.proseSize(), $r('app.color.text_primary'), FontWeight.Bold,
              this.listLine())
          }
          .width('100%')
          .margin({ top: idx > 0 ? 12 : 0, bottom: 4 })
        } else if (b.kind === 'li') {
          this.bulletItem(b.text, '•')
        } else if (b.kind === 'ol') {
          this.bulletItem(b.text, `${b.lang}.`)
        } else if (b.kind === 'quote') {
          Column() {
            this.quoteBlock(b.text)
          }
          .width('100%')
          .margin({ top: 8, bottom: 8 })
        } else if (b.kind === 'hr') {
          Divider()
            .color($r('app.color.border'))
            .width('100%')
            .margin({ top: 12, bottom: 12 })
        } else {
          Column() {
            this.renderInline(b.text, this.proseSize(), this.bodyColor(), FontWeight.Regular,
              this.proseLine())
          }
          .width('100%')
          .margin({ top: 0, bottom: 8 })
        }
      }, (b: MdBlock, idx: number) => `md-${idx}-${b.kind}-${b.text.length}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  bulletItem(text: string, marker: string) {
    Row({ space: 8 }) {
      Text(marker)
        .fontSize(this.proseSize())
        .fontColor($r('app.color.text_tertiary'))
        .fontWeight(FontWeight.Medium)
        .width(marker.length > 2 ? 26 : 16)
        .lineHeight(this.listLine())
        .textAlign(TextAlign.End)
      Column() {
        this.renderInline(text, this.proseSize(), this.bodyColor(), FontWeight.Regular,
          this.listLine())
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: 3, bottom: 3 })
  }

  @Builder
  quoteBlock(text: string) {
    Column() {
      this.renderInline(text, this.proseSize(), $r('app.color.text_tertiary'), FontWeight.Regular,
        this.proseLine())
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.bg2'))
    .borderRadius(Tokens.radiusSm)
  }

  @Builder
  tableBlock(packed: string, idx: number) {
    Column() {
      ForEach(this.tableRows(packed), (row: TableRow, ri: number) => {
        Row() {
          ForEach(row.cells, (cell: string, ci: number) => {
            Text(cell)
              .fontSize(Tokens.typeCaption)
              .fontWeight(ri === 0 ? FontWeight.Bold : FontWeight.Regular)
              .fontColor(ri === 0 ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
              .lineHeight(Tokens.lineCaption + 2)
              .maxLines(6)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .padding({ left: 8, right: 8, top: 7, bottom: 7 })
          }, (cell: string, ci: number) => `${row.key}-c${ci}-${cell.length}`)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .backgroundColor(ri === 0 ? $r('app.color.bg2') : Color.Transparent)
        .border({
          width: { bottom: 1 },
          color: $r('app.color.border')
        })
      }, (row: TableRow) => `${idx}-${row.key}`)
    }
    .width('100%')
    .backgroundColor($r('app.color.bg1'))
    .border({ width: 1, color: $r('app.color.border') })
    .borderRadius(Tokens.radiusMd)
    .clip(true)
    .margin({ top: 8, bottom: 10 })
  }

  @Builder
  codeBlock(b: MdBlock) {
    Column({ space: 0 }) {
      Row() {
        Text(b.lang.length > 0 ? b.lang : 'code')
          .fontSize(Tokens.typeMicro)
          .fontColor($r('app.color.text_tertiary'))
          .fontFamily('monospace')
          .layoutWeight(1)
        Text('复制')
          .fontSize(Tokens.typeMicro)
          .fontColor($r('app.color.text_secondary'))
          .constraintSize({ minHeight: Tokens.touchMin })
          .padding({ left: 8, right: 4 })
          .textAlign(TextAlign.Center)
          .onClick(() => {
            Haptics.click();
            copyToClipboard(b.text).then((ok: boolean) => {
              showToast(ok ? '已复制' : '复制失败');
            });
          })
      }
      .width('100%')
      .padding({ left: 12, right: 8, top: 6, bottom: 6 })
      .backgroundColor($r('app.color.bg2'))

      Text(b.text)
        .fontSize(Tokens.typeCaption)
        .fontColor($r('app.color.text_primary'))
        .fontFamily('monospace')
        .lineHeight(Tokens.lineCaption + 2)
        .width('100%')
        .copyOption(CopyOptions.None)
        .padding({ left: 12, right: 12, top: 10, bottom: 12 })
    }
    .width('100%')
    .backgroundColor($r('app.color.code_bg'))
    .borderRadius(Tokens.radiusMd)
    .clip(true)
    .margin({ top: 8, bottom: 10 })
  }
}
