@Entry
@Component
struct Index {
  @State message: string = 'Hypium';

  build() {
    Column() {
      Text(this.message)
        .fontSize(20)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
