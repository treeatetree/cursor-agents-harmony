@Entry
@Component
struct WidgetCard {
  @LocalStorageProp('runningLine') runningLine: string = '没有在跑的任务';
  @LocalStorageProp('latestName') latestName: string = 'Cursor Agents';
  @LocalStorageProp('latestStatus') latestStatus: string = '打开查看';

  build() {
    FormLink({
      action: 'router',
      abilityName: 'EntryAbility'
    }) {
      Column({ space: 8 }) {
        Text(this.runningLine)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.latestName)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.latestStatus.length > 0) {
          Text(this.latestStatus)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .width('100%')
        }
      }
      .width('100%')
      .height('100%')
      .padding(16)
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.bg0'))
      .borderRadius(16)
    }
  }
}
