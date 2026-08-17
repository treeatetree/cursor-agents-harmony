import { ModelInfo } from '../models/Api';
import { Tokens } from '../theme/Tokens';
import { HuChip } from './HuChip';
import {
  ModelParamRow, ModelVendorGroup, shortModelName
} from '../utils/ModelGroups';

@Component
export struct ModelPicker {
  @Prop selectedModel: string = '';
  @Prop selectedVariantIndex: number = -1;
  @Prop groups: ModelVendorGroup[] = [];
  @Prop variantOptions: string[] = [];
  @Prop variantTitle: string = '模式';
  @Prop paramRows: ModelParamRow[] = [];
  @Prop allowAuto: boolean = true;
  @Prop autoLabel: string = '自动';
  onPick: (id: string) => void = (_id: string) => {
  };
  onPickParam: (rowId: string, valueIdx: number) => void = (_id: string, _v: number) => {
  };
  onPickVariant: (idx: number) => void = (_idx: number) => {
  };

  build() {
    Column({ space: 8 }) {
      if (this.allowAuto) {
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start, justifyContent: FlexAlign.Start }) {
          HuChip({
            label: this.autoLabel,
            on: this.selectedModel.length === 0,
            onTap: () => {
              this.onPick('');
            }
          })
            .margin({ right: 6, bottom: 4 })
        }
        .width('100%')
      }
      ForEach(this.groups, (g: ModelVendorGroup) => {
        Column({ space: 2 }) {
          Text(g.vendor)
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start, justifyContent: FlexAlign.Start }) {
            ForEach(g.items, (m: ModelInfo) => {
              HuChip({
                label: shortModelName(m.displayName ?? m.id),
                on: this.selectedModel === m.id,
                maxVp: 160,
                onTap: () => {
                  this.onPick(m.id);
                }
              })
                .margin({ right: 6, bottom: 4 })
            }, (m: ModelInfo) => m.id)
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }, (g: ModelVendorGroup) => g.vendor)
      if (this.paramRows.length > 0) {
        Column({ space: 8 }) {
          ForEach(this.paramRows, (row: ModelParamRow) => {
            Column({ space: 2 }) {
              Text(row.title)
                .fontSize(Tokens.typeMicro)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
              Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start, justifyContent: FlexAlign.Start }) {
                ForEach(row.labels, (lab: string, valueIdx: number) => {
                  HuChip({
                    label: lab,
                    on: row.selected === valueIdx,
                    onTap: () => {
                      this.onPickParam(row.id, valueIdx);
                    }
                  })
                    .margin({ right: 6, bottom: 4 })
                }, (lab: string, valueIdx: number) => `${row.id}-${valueIdx}-${lab}-${row.selected}`)
              }
              .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }, (row: ModelParamRow) => `${row.id}:${row.selected}`)
        }
        .width('100%')
        .padding({ top: 6 })
        .border({ width: { top: 1 }, color: $r('app.color.border') })
        .alignItems(HorizontalAlign.Start)
      } else if (this.variantOptions.length > 0) {
        Column({ space: 2 }) {
          Text(this.variantTitle)
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start, justifyContent: FlexAlign.Start }) {
            ForEach(this.variantOptions, (v: string, idx: number) => {
              HuChip({
                label: v,
                on: this.selectedVariantIndex === idx,
                onTap: () => {
                  this.onPickVariant(idx);
                }
              })
                .margin({ right: 6, bottom: 4 })
            }, (v: string, idx: number) => `var-${idx}-${v}-${this.selectedVariantIndex}`)
          }
          .width('100%')
        }
        .width('100%')
        .padding({ top: 6 })
        .border({ width: { top: 1 }, color: $r('app.color.border') })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
