import { Tokens } from '../theme/Tokens';
import { BreakpointStore } from '../store/BreakpointStore';
import { HuIconButton } from './HuIconButton';
import { HuTextButton } from './HuTextButton';

@Component
export struct ComposerBar {
  @Prop runActive: boolean = false;
  @Prop busy: boolean = false;
  @Prop cancelling: boolean = false;
  @Prop queued: string = '';
  @Prop followUpMode: string = 'agent';
  @Prop imageCount: number = 0;
  @Prop toolsOn: boolean = false;
  @Link draft: string;
  onSend: () => void = () => {
  };
  onCancel: () => void = () => {
  };
  onClearQueue: () => void = () => {
  };
  onModeChange: (mode: string) => void = () => {
  };
  onPickImage: () => void = () => {
  };
  onTools: () => void = () => {
  };

  private canSend(): boolean {
    return !this.busy && (this.draft.trim().length > 0 || this.imageCount > 0);
  }

  private placeholder(): string {
    if (this.queued.length > 0) {
      return '将替换已排队的追问';
    }
    if (this.runActive) {
      return '运行中也可输入，结束后发送';
    }
    return '追问…';
  }

  build() {
    Column({ space: Tokens.space2 }) {
      if (this.queued.length > 0) {
        Row({ space: Tokens.space2 }) {
          Text(`已排队 · ${this.queued}`)
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.accent'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          HuTextButton({
            label: '取消排队',
            onTap: () => {
              this.onClearQueue();
            }
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      Row({ space: 4 }) {
        HuTextButton({
          label: this.followUpMode === 'plan' ? 'Plan' : 'Agent',
          compact: false,
          active: true,
          color: $r('app.color.text_secondary'),
          onTap: () => {
            this.onModeChange(this.followUpMode === 'plan' ? 'agent' : 'plan');
          }
        })
        HuTextButton({
          label: this.toolsOn ? '能力·' : '能力',
          compact: true,
          active: this.toolsOn,
          color: $r('app.color.text_secondary'),
          onTap: () => {
            this.onTools();
          }
        })
        HuIconButton({
          name: 'image',
          label: this.imageCount > 0 ? `已选 ${this.imageCount} 张图` : '添加图片',
          iconColor: this.imageCount > 0 ? $r('app.color.accent') : $r('app.color.text_secondary'),
          onTap: () => {
            this.onPickImage();
          }
        })
        TextArea({
          text: this.draft,
          placeholder: this.placeholder()
        })
          .layoutWeight(1)
          .constraintSize({ minWidth: 0, minHeight: Tokens.touchMin, maxHeight: 100 })
          .fontSize(Tokens.typeBody)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor($r('app.color.field_bg'))
          .borderRadius(Tokens.radiusField)
          .border({ width: 1, color: $r('app.color.border') })
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .caretColor($r('app.color.accent'))
          .enabled(!this.busy)
          .onChange((v: string) => {
            this.draft = v;
          })

        if (this.runActive) {
          HuIconButton({
            name: 'stop',
            label: this.cancelling ? '正在停止' : '停止运行',
            iconColor: $r('app.color.err'),
            isEnabled: !this.cancelling,
            onTap: () => {
              this.onCancel();
            }
          })
        }

        if (this.runActive) {
          HuTextButton({
            label: this.busy ? '…' : '排队',
            color: this.canSend() ? $r('app.color.accent') : $r('app.color.text_tertiary'),
            isEnabled: this.canSend(),
            onTap: () => {
              this.onSend();
            }
          })
        } else {
          HuIconButton({
            name: 'send',
            label: '发送',
            filled: this.canSend(),
            isEnabled: this.canSend(),
            onTap: () => {
              this.onSend();
            }
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({
      left: Tokens.chromePad,
      right: Tokens.chromePad,
      top: Tokens.space2,
      bottom: Tokens.space2 + Math.max(BreakpointStore.getInstance().bottomInsetVp, 8)
    })
    .backgroundColor($r('app.color.bg0'))
  }
}
