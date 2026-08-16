import { common } from '@kit.AbilityKit';

@Entry
@Component
struct LockScreenPage {
  @LocalStorageProp('title') title: string = 'Cursor Agent';
  @LocalStorageProp('status') status: string = '';
  @LocalStorageProp('agentId') agentId: string = '';

  build() {
    Column({ space: 8 }) {
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FAFAFA')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(this.status.length > 0 ? this.status : '运行中')
        .fontSize(14)
        .fontColor('#A1A1AA')
        .maxLines(1)
        .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(20)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#0B0B0C')
    .onClick(() => {
      try {
        const ctx = getContext(this) as common.UIAbilityContext;
        ctx.startAbility({
          bundleName: 'com.brian.cursor.mobile',
          abilityName: 'EntryAbility',
          parameters: { 'agentId': this.agentId }
        }).catch(() => {
        });
      } catch (_e) {
      }
    })
  }
}
