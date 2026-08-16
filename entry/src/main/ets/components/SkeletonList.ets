import { Tokens } from '../theme/Tokens';

@Component
export struct SkeletonList {
  @Prop rows: number = 6;

  build() {
    Column({ space: 0 }) {
      ForEach(this.rowKeys(), (key: string) => {
        Row() {
          Column({ space: 8 }) {
            Row()
              .width('48%')
              .height(12)
              .borderRadius(3)
              .backgroundColor($r('app.color.bg2'))
            Row()
              .width('28%')
              .height(10)
              .borderRadius(3)
              .backgroundColor($r('app.color.bg2'))
              .opacity(0.65)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Row()
            .width(36)
            .height(10)
            .borderRadius(3)
            .backgroundColor($r('app.color.bg2'))
            .opacity(0.55)
        }
        .width('100%')
        .padding({
          left: Tokens.pagePad,
          right: Tokens.pagePad,
          top: Tokens.space3,
          bottom: Tokens.space3
        })
        .constraintSize({ minHeight: Tokens.rowMin })
        .border({ width: { bottom: 1 }, color: $r('app.color.border') })
      }, (key: string) => key)
    }
    .width('100%')
  }

  private rowKeys(): string[] {
    const n = this.rows > 0 ? this.rows : 6;
    const keys: string[] = [];
    for (let i = 0; i < n; i++) {
      keys.push(`sk_${i}`);
    }
    return keys;
  }
}
