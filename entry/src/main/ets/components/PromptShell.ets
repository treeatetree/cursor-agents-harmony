import { Tokens } from '../theme/Tokens';
import { Haptics } from '../utils/Haptics';
import { hasPreviewMap, requirePreviewMap } from '../utils/ImagePicker';
import { motionMs, prefersReducedMotion, shakeSeq } from '../utils/Motion';
import { HuChip } from './HuChip';
import { HuTextButton } from './HuTextButton';

/**
 * Prompt card: new-task field is ~6 lines; follow-up stays compact.
 * Common chips on the shell; uncommon settings behind 更多.
 */
@Component
export struct PromptShell {
  @Prop follow: boolean = false;
  @Prop placeholder: string = '要做什么？目标和约束';
  @Link text: string;
  @Prop live: boolean = false;
  @Prop cancelling: boolean = false;
  @Prop busy: boolean = false;
  @Prop repo: string = '';
  @Prop modelLabel: string = '';
  @Prop autoPr: boolean = true;
  @Prop imageCount: number = 0;
  @Link imageUris: string[];
  @Prop toolsOn: boolean = false;
  @Prop toolsLabel: string = '能力';
  @Prop moreLabel: string = '更多';
  @Prop followUpMode: string = 'agent';
  @Prop queued: string = '';
  @Prop status: string = '';
  @Prop bottomPad: number = 12;
  @State private focused: boolean = false;
  @State private wantFocus: boolean = false;
  @State private shake: number = 0;
  @State private sent: boolean = false;
  @State private sentScale: number = 1;
  onSend: () => void = () => {
  };
  onCancel: () => void = () => {
  };
  onClearQueue: () => void = () => {
  };
  onRepo: () => void = () => {
  };
  onModel: () => void = () => {
  };
  onImage: () => void = () => {
  };
  onRemoveImage: (index: number) => void = () => {
  };
  onTools: () => void = () => {
  };
  onMoreExtra: () => void = () => {
  };
  onAutoPr: (on: boolean) => void = () => {
  };
  onModeChange: (mode: string) => void = () => {
  };
  onText: (s: string) => void = () => {
  };

  private canSend(): boolean {
    return !this.busy && (this.text.trim().length > 0 || this.imageCount > 0);
  }

  private expanded(): boolean {
    if (!this.follow) {
      return true;
    }
    return this.focused || this.text.trim().length > 0 || this.imageCount > 0;
  }

  private kickShake(): void {
    if (prefersReducedMotion()) {
      return;
    }
    const seq = shakeSeq();
    let i = 1;
    const step = (): void => {
      if (i >= seq.length) {
        this.shake = 0;
        return;
      }
      animateTo({ duration: 70, curve: Curve.EaseInOut }, () => {
        this.shake = seq[i];
      });
      i += 1;
      setTimeout(step, 70);
    };
    step();
  }

  private trySend(): void {
    if (!this.canSend()) {
      this.kickShake();
      Haptics.fail();
      return;
    }
    this.sent = true;
    this.sentScale = 0.35;
    if (!prefersReducedMotion()) {
      animateTo({ duration: 280, curve: Curve.FastOutSlowIn }, () => {
        this.sentScale = 1;
      });
    } else {
      this.sentScale = 1;
    }
    Haptics.commit();
    this.onSend();
    setTimeout(() => {
      this.sent = false;
      this.sentScale = 1;
    }, prefersReducedMotion() ? 0 : 280);
  }

  private focusComposer(): void {
    this.focused = true;
    this.wantFocus = true;
    setTimeout(() => {
      focusControl.requestFocus('promptArea');
    }, 30);
  }

  build() {
    Column({ space: Tokens.space2 }) {
      if (this.follow && this.queued.length > 0) {
        Row({ space: Tokens.space2 }) {
          Text(`已排队 · ${this.queued}`)
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          HuTextButton({
            label: '取消',
            onTap: () => {
              this.onClearQueue();
            }
          })
        }
        .width('100%')
        .constraintSize({ minHeight: Tokens.touchMin })
        .alignItems(VerticalAlign.Center)
      }

      Column({ space: 4 }) {
        if (this.follow && !this.expanded()) {
          Row({ space: 8 }) {
            Text(this.placeholder)
              .fontSize(Tokens.typeCallout)
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(1)
              .layoutWeight(1)
            if (this.live) {
              HuChip({
                label: this.cancelling ? '停止中' : '停止',
                on: true,
                onTap: () => {
                  if (!this.cancelling) {
                    this.onCancel();
                  }
                }
              })
            }
          }
          .width('100%')
          .height(Tokens.touchMin)
          .padding({ left: 12, right: this.live ? 6 : 12 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.focusComposer();
          })
        } else {
          if (this.imageUris.length > 0) {
            Row({ space: 8 }) {
              ForEach(this.imageUris, (uri: string, idx: number) => {
                this.thumb(uri, idx)
              }, (uri: string, idx: number) => `pv-${idx}`)
            }
            .width('100%')
            .height(64)
            .justifyContent(FlexAlign.Start)
            .alignItems(VerticalAlign.Top)
          }

          TextArea({
            text: this.text,
            placeholder: this.placeholder
          })
            .width('100%')
            .height(this.follow ? 64 : 144)
            .constraintSize({
              minHeight: this.follow ? 52 : 132,
              maxHeight: this.follow ? 96 : 180
            })
            .fontSize(this.follow ? Tokens.typeCallout : Tokens.typeProse)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_tertiary'))
            .backgroundColor(Color.Transparent)
            .padding({ left: 2, right: 2, top: 6, bottom: 2 })
            .caretColor($r('app.color.accent'))
            .enabled(!this.busy)
            .id('promptArea')
            .defaultFocus(this.wantFocus)
            .onChange((v: string) => {
              this.text = v;
              this.onText(v);
            })
            .onFocus(() => {
              this.focused = true;
              this.wantFocus = false;
            })
            .onBlur(() => {
              this.focused = false;
            })

          Row({ space: 4 }) {
            Scroll() {
              this.moreChipsRow()
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.None)
            .align(Alignment.Start)
            .layoutWeight(1)
            .constraintSize({ minWidth: 0 })
            .height(Tokens.touchMin)
            this.actionSwap()
          }
          .width('100%')
          .height(Tokens.touchMin)
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.Start)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(this.follow && !this.expanded() ? 0 : 10)
      .backgroundColor($r('app.color.bg1'))
      .border({
        width: 1,
        color: this.focused ? $r('app.color.border_strong') : $r('app.color.border')
      })
      .borderRadius(16)
      .translate({ x: this.shake })
      .animation({ duration: motionMs(), curve: Curve.FastOutSlowIn })
    }
    .width('100%')
    .padding({
      left: Tokens.pagePad,
      right: Tokens.pagePad,
      bottom: this.bottomPad
    })
  }

  @Builder
  thumb(uri: string, idx: number) {
    Column() {
      if (hasPreviewMap(uri)) {
        Image(requirePreviewMap(uri))
          .width(64)
          .height(64)
          .objectFit(ImageFit.Cover)
      } else {
        Image(uri)
          .width(64)
          .height(64)
          .objectFit(ImageFit.Cover)
          .alt($r('app.media.ic_image'))
      }
    }
    .width(64)
    .height(64)
    .borderRadius(10)
    .clip(true)
    .backgroundColor($r('app.color.bg2'))
    .flexShrink(0)
    .onClick(() => {
      this.onRemoveImage(idx);
    })
  }

  @Builder
  actionSwap() {
    if (this.sent) {
      HuChip({
        label: '已发',
        on: true,
        onTap: () => {
        }
      })
        .scale({ x: this.sentScale, y: this.sentScale })
    } else if (this.live) {
      Row({ space: 6 }) {
        HuChip({
          label: this.cancelling ? '停止中' : '停止',
          on: true,
          onTap: () => {
            if (!this.cancelling) {
              this.onCancel();
            }
          }
        })
        if (this.follow && this.canSend()) {
          HuChip({
            label: '排队',
            on: true,
            onTap: () => {
              this.trySend();
            }
          })
        }
      }
    } else if (this.busy) {
      HuChip({
        label: this.status.length > 0 ? this.status : '发送中',
        on: true,
        onTap: () => {
        }
      })
    } else {
      HuChip({
        label: '发送',
        on: this.canSend(),
        onTap: () => {
          this.trySend();
        }
      })
    }
  }

  @Builder
  moreChipsRow() {
    Row({ space: 6 }) {
      HuChip({
        label: this.imageCount > 0 ? `图片 ${this.imageCount}` : '图片',
        on: this.imageCount > 0,
        maxVp: 88,
        onTap: () => {
          this.onImage();
        }
      })
      if (!this.follow) {
        HuChip({
          label: this.repo.length > 0 ? this.repo : '仓库',
          on: this.repo.length > 0,
          maxVp: 140,
          onTap: () => {
            this.onRepo();
          }
        })
        HuChip({
          label: this.modelLabel.length > 0 ? this.modelLabel : '自动',
          on: this.modelLabel.length > 0 && this.modelLabel !== '自动',
          maxVp: 120,
          onTap: () => {
            this.onModel();
          }
        })
        HuChip({
          label: '更多',
          on: this.moreLabel !== '更多',
          maxVp: 80,
          onTap: () => {
            this.onMoreExtra();
          }
        })
      } else {
        HuChip({
          label: this.followUpMode === 'plan' ? '规划' : '代理',
          on: this.followUpMode === 'plan',
          onTap: () => {
            this.onModeChange(this.followUpMode === 'plan' ? 'agent' : 'plan');
          }
        })
        HuChip({
          label: this.toolsOn && this.toolsLabel.length > 0 ? this.toolsLabel : '能力',
          on: this.toolsOn,
          maxVp: 120,
          onTap: () => {
            this.onTools();
          }
        })
      }
    }
    .constraintSize({ minHeight: Tokens.touchMin })
    .justifyContent(FlexAlign.Start)
  }
}
