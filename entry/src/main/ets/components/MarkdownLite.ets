import { common } from '@kit.AbilityKit';
import { Tokens } from '../theme/Tokens';
import { copyToClipboard } from '../utils/Clipboard';
import { showToast } from '../utils/AppToast';
import { Haptics } from '../utils/Haptics';
import { InlineSeg, MdBlock, parseMarkdown, tableRows, tokenizeInline } from '../utils/MarkdownParse';

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
          Span(` ${seg.text} `)
            .fontSize(size - 1)
            .fontColor($r('app.color.text_primary'))
            .fontFamily('monospace')
            .backgroundColor($r('app.color.code_inline_bg'))
        } else if (seg.url.length > 0) {
          Span(seg.text)
            .fontSize(size)
            .fontColor($r('app.color.text_link'))
            .fontWeight(FontWeight.Medium)
            .decoration({ type: TextDecorationType.Underline, color: $r('app.color.text_link') })
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
        } else if (b.kind === 'h1') {
          Column() {
            this.renderInline(b.text, this.compact ? Tokens.typeBody : Tokens.typeHeadline,
              $r('app.color.text_primary'),
              FontWeight.Bold, this.compact ? Tokens.lineBody : Tokens.lineProse)
          }
          .width('100%')
          .margin({ top: idx > 0 ? 16 : 0, bottom: 6 })
        } else if (b.kind === 'h2') {
          Column() {
            this.renderInline(b.text, this.compact ? Tokens.typeBody : Tokens.typeHeadline,
              $r('app.color.text_primary'),
              FontWeight.Medium, this.compact ? Tokens.lineBody : Tokens.lineProse)
          }
          .width('100%')
          .margin({ top: idx > 0 ? 14 : 0, bottom: 5 })
        } else if (b.kind === 'h3') {
          Column() {
            this.renderInline(b.text, this.proseSize(), $r('app.color.text_primary'), FontWeight.Medium,
              this.listLine())
          }
          .width('100%')
          .margin({ top: idx > 0 ? 10 : 0, bottom: 4 })
        } else if (b.kind === 'li') {
          this.bulletItem(b.text, '•', b.indent)
        } else if (b.kind === 'ol') {
          this.bulletItem(b.text, `${b.lang}.`, b.indent)
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
      }, (b: MdBlock, idx: number) => `md-${idx}-${b.kind}-${b.text.length}-${b.indent}`)
    }
    .width('100%')
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
    .margin({ top: 2, bottom: 2 })
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
        .wordBreak(WordBreak.BREAK_ALL)
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
