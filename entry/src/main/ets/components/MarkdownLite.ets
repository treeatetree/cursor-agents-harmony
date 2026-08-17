import { common } from '@kit.AbilityKit';
import { Tokens } from '../theme/Tokens';
import { copyToClipboard } from '../utils/Clipboard';
import { showToast } from '../utils/AppToast';
import { Haptics } from '../utils/Haptics';
import { makeQuoteEditMenu } from '../utils/TextSelectMenu';
import {
  citationQuote, InlineSeg, isCitationFence, MdBlock, parseMarkdown, tableRows, tokenizeInline
} from '../utils/MarkdownParse';

interface TableRow {
  key: string;
  cells: string[];
}

/**
 * Conversation markdown: headings, lists, quotes, tables, fenced/inline code,
 * bold/italic, [label](url) and bare links. Links stay as the label, not raw syntax.
 */
@Component
export struct MarkdownLite {
  @Prop content: string = '';
  @Prop compact: boolean = false;
  /** Nested in a user bubble — boxes stay transparent, no second fill. */
  @Prop inBubble: boolean = false;
  /** Pixel cap so quotes / code cannot inflate the bubble past the feed. */
  @Prop capWidth: number = 0;
  onQuote: (text: string) => void = (_text: string) => {
  };

  private textCap(): number {
    return this.capWidth > 0 ? this.capWidth : 8192;
  }

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
    return parseMarkdown(this.content ?? '');
  }

  private rowsOf(packed: string): TableRow[] {
    const raw = tableRows(packed);
    const out: TableRow[] = [];
    for (let i = 0; i < raw.length; i++) {
      out.push({ key: `tr-${i}`, cells: raw[i] });
    }
    return out;
  }

  private open(url: string): void {
    if (url.length === 0) {
      return;
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    ctx.openLink(url).catch(() => {
    });
  }

  @Builder
  renderInline(text: string, size: number, color: ResourceColor, weight: FontWeight = FontWeight.Normal,
    line: number = Tokens.lineProse) {
    Text() {
      ForEach(tokenizeInline(text), (seg: InlineSeg, idx: number) => {
        if (seg.code) {
          Span(this.softWrapCode(seg.text))
            .fontSize(Math.max(12, size - 2))
            .fontColor($r('app.color.text_primary'))
            .fontFamily(Tokens.fontMono)
            .fontWeight(FontWeight.Medium)
            .backgroundColor(this.inBubble ? Color.Transparent : $r('app.color.code_inline_bg'))
        } else if (seg.url.length > 0) {
          Span(seg.text)
            .fontSize(size)
            .fontColor($r('app.color.text_link'))
            .fontWeight(FontWeight.Medium)
            .decoration({
              type: TextDecorationType.Underline,
              color: $r('app.color.text_link')
            })
            .onClick(() => {
              this.open(seg.url);
            })
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
      }, (seg: InlineSeg, idx: number) =>
        `s-${idx}-${seg.text.length}-${seg.code ? 1 : 0}-${seg.bold ? 1 : 0}-${seg.url.length}`)
    }
    .fontFamily(Tokens.fontUi)
    .lineHeight(line)
    .textAlign(TextAlign.Start)
    .wordBreak(WordBreak.BREAK_WORD)
    .focusable(true)
    .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
    .copyOption(CopyOptions.LocalDevice)
    .editMenuOptions(makeQuoteEditMenu(text, (q: string) => {
      this.onQuote(q);
    }))
    .constraintSize({ maxWidth: this.textCap() })
    .width(this.capWidth > 0 ? this.capWidth : '100%')
  }

  private softWrapCode(raw: string): string {
    let out = '';
    for (let i = 0; i < raw.length; i++) {
      const ch = raw.charAt(i);
      out += ch;
      if (ch === '/' || ch === '_' || ch === '-' || ch === '.') {
        out += '\u200B';
      }
    }
    return out;
  }

  build() {
    Column() {
      ForEach(this.blocks(), (b: MdBlock, idx: number) => {
        if (b.kind === 'code') {
          if (isCitationFence(b.lang)) {
            this.citeBlock(citationQuote(b.text))
          } else {
            this.codeBlock(b)
          }
        } else if (b.kind === 'table') {
          this.tableBlock(b.text, idx)
        } else if (b.kind === 'h1') {
          Column() {
            this.renderInline(b.text, this.compact ? Tokens.typeBody : Tokens.typeTitle,
              $r('app.color.text_primary'),
              FontWeight.Bold, this.compact ? Tokens.lineBody : Tokens.lineTitle)
          }
          .width('100%')
          .margin({ top: idx > 0 ? 20 : 0, bottom: 8 })
        } else if (b.kind === 'h2') {
          Column() {
            this.renderInline(b.text, this.compact ? Tokens.typeBody : Tokens.typeHeadline,
              $r('app.color.text_primary'),
              FontWeight.Bold, this.compact ? Tokens.lineBody : Tokens.lineBody + 2)
          }
          .width('100%')
          .margin({ top: idx > 0 ? 18 : 0, bottom: 8 })
        } else if (b.kind === 'h3') {
          Column() {
            this.renderInline(b.text, this.proseSize(), $r('app.color.text_primary'), FontWeight.Bold,
              this.listLine())
          }
          .width('100%')
          .margin({ top: idx > 0 ? 14 : 0, bottom: 6 })
        } else if (b.kind === 'li') {
          this.bulletItem(b.text, '•', b.indent)
        } else if (b.kind === 'ol') {
          this.bulletItem(b.text, `${b.lang}.`, b.indent)
        } else if (b.kind === 'quote') {
          Column() {
            this.quoteBlock(b.text)
          }
          .width('100%')
          .margin({ top: 10, bottom: 10 })
        } else if (b.kind === 'hr') {
          Divider()
            .color($r('app.color.border'))
            .width('100%')
            .margin({ top: 16, bottom: 16 })
        } else {
          Column() {
            this.renderInline(b.text, this.proseSize(), this.bodyColor(), FontWeight.Regular,
              this.proseLine())
          }
          .width('100%')
          .margin({ top: 0, bottom: this.compact ? 8 : 12 })
        }
      }, (b: MdBlock, idx: number) => `md-${idx}-${b.kind}-${b.text.length}-${b.indent}`)
    }
    .constraintSize({ maxWidth: this.textCap() })
    .width(this.capWidth > 0 ? this.capWidth : '100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  bulletItem(text: string, marker: string, indent: number) {
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
    .padding({ left: indent * 16 })
    .margin({ top: 3, bottom: 3 })
  }

  @Builder
  quoteBlock(text: string) {
    this.citeBlock(text)
  }

  @Builder
  citeBlock(text: string) {
    Column({ space: 4 }) {
      Text('引用')
        .fontSize(Tokens.typeMicro)
        .fontColor($r('app.color.text_tertiary'))
      this.renderInline(text, this.proseSize(), $r('app.color.text_secondary'), FontWeight.Regular,
        this.proseLine())
    }
    .constraintSize({ maxWidth: this.textCap() })
    .width(this.capWidth > 0 ? this.capWidth : '100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: this.inBubble ? 0 : 10, right: this.inBubble ? 0 : 10, top: 2, bottom: 6 })
    .backgroundColor(Color.Transparent)
    .border({
      width: this.inBubble ? 0 : 1,
      color: $r('app.color.border')
    })
    .borderRadius(this.inBubble ? 0 : Tokens.radiusSm)
    .margin({ top: 0, bottom: 8 })
  }

  @Builder
  tableBlock(packed: string, idx: number) {
    Column() {
      ForEach(this.rowsOf(packed), (row: TableRow, ri: number) => {
        Row() {
          ForEach(row.cells, (cell: string, ci: number) => {
            Column() {
              this.renderInline(cell, Tokens.typeCaption,
                ri === 0 ? $r('app.color.text_primary') : $r('app.color.text_secondary'),
                ri === 0 ? FontWeight.Medium : FontWeight.Regular, Tokens.lineCaption + 2)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 8, right: 8, top: 8, bottom: 8 })
          }, (cell: string, ci: number) => `${row.key}-c${ci}-${cell.length}`)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .backgroundColor(ri === 0 && !this.inBubble ? $r('app.color.bg2') : Color.Transparent)
        .border({
          width: { bottom: 1 },
          color: $r('app.color.border')
        })
      }, (row: TableRow) => `${idx}-${row.key}`)
    }
    .constraintSize({ maxWidth: this.textCap() })
    .width(this.capWidth > 0 ? this.capWidth : '100%')
    .backgroundColor(this.inBubble ? Color.Transparent : $r('app.color.bg1'))
    .border({ width: 1, color: $r('app.color.border') })
    .borderRadius(Tokens.radiusSm)
    .clip(true)
    .margin({ top: 8, bottom: 12 })
  }

  @Builder
  codeBlock(b: MdBlock) {
    Column({ space: 0 }) {
      Row() {
        Text(b.lang.length > 0 ? b.lang : 'code')
          .fontSize(Tokens.typeMicro)
          .fontColor($r('app.color.text_tertiary'))
          .fontFamily(Tokens.fontMono)
          .layoutWeight(1)
        Text('复制')
          .fontSize(Tokens.typeMicro)
          .fontColor($r('app.color.text_secondary'))
          .height(28)
          .padding({ left: 8, right: 8 })
          .textAlign(TextAlign.Center)
          .onClick(() => {
            Haptics.click();
            copyToClipboard(b.text).then((ok: boolean) => {
              showToast(ok ? '已复制' : '复制失败');
            });
          })
      }
      .width('100%')
      .height(32)
      .padding({ left: 12, right: 4 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.inBubble ? Color.Transparent : $r('app.color.bg2'))

      Text(b.text)
        .fontSize(Tokens.typeCaption)
        .fontColor($r('app.color.text_primary'))
        .fontFamily(Tokens.fontMono)
        .lineHeight(Tokens.lineCaption + 2)
        .constraintSize({ maxWidth: this.textCap() })
        .width(this.capWidth > 0 ? this.capWidth : '100%')
        .wordBreak(WordBreak.BREAK_ALL)
        .focusable(true)
        .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
        .copyOption(CopyOptions.LocalDevice)
        .editMenuOptions(makeQuoteEditMenu(b.text, (q: string) => {
          this.onQuote(q);
        }))
        .padding({ left: 12, right: 12, top: 10, bottom: 14 })
    }
    .constraintSize({ maxWidth: this.textCap() })
    .width(this.capWidth > 0 ? this.capWidth : '100%')
    .backgroundColor(this.inBubble ? Color.Transparent : $r('app.color.code_bg'))
    .border({ width: 1, color: $r('app.color.border') })
    .borderRadius(Tokens.radiusMd)
    .clip(true)
    .margin({ top: 8, bottom: 14 })
  }
}
