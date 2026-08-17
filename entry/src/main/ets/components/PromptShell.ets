import { Tokens } from '../theme/Tokens';
import { Haptics } from '../utils/Haptics';
import { hasPreviewMap, requirePreviewMap } from '../utils/ImagePicker';
import { chromeTransition, fadeTransition, motionMs, prefersReducedMotion, runLayout, shakeSeq } from '../utils/Motion';
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
  @Prop branch: string = '';
  @Prop modelLabel: string = '';
  @Prop autoPr: boolean = true;
  @Prop imageCount: number = 0;
  @Link imageUris: string[];
  @Prop toolsOn: boolean = false;
  @Prop toolsLabel: string = 'MCP';
  @Prop moreLabel: string = '更多';
  @Prop followUpMode: string = 'agent';
  @Prop failedFollow: boolean = false;
  @Prop queued: string = '';
  @Prop queueNote: string = '';
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
  onEditQueue: () => void = () => {
  };
  onRepo: () => void = () => {
  };
  onBranch: () => void = () => {
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
  onRetryFollow: () => void = () => {
  };
  onText: (s: string) => void = () => {
  };
  onFocusChange: (on: boolean) => void = (_on: boolean) => {
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

  private fieldH(): number {
    if (!this.follow) {
      return 144;
    }
    return this.expanded() ? 72 : 36;
  }

  private fieldMin(): number {
    if (!this.follow) {
      return 132;
    }
    return this.expanded() ? 56 : 36;
  }

  private fieldMax(): number {
    if (!this.follow) {
      return 180;
    }
    return this.expanded() ? 96 : 36;
  }

  private cardPadH(): number {
    return 14;
  }

  private cardPadV(): number {
    return this.follow && !this.expanded() ? 10 : 14;
  }

  build() {
    Column({ space: Tokens.space2 }) {
      if (this.follow && this.queued.length > 0) {
        Row({ space: Tokens.space2 }) {
          Column({ space: 2 }) {
            Text(`结束后发送 · ${this.queued}`)
              .fontSize(Tokens.typeMicro)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            if (this.queueNote.length > 0) {
              Text(this.queueNote)
                .fontSize(Tokens.typeMicro)
                .fontColor($r('app.color.warn'))
                .maxLines(1)
                .width('100%')
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          HuTextButton({
            label: '改',
            onTap: () => {
              this.onEditQueue();
            }
          })
          HuTextButton({
            label: '取消',
            onTap: () => {
              this.onClearQueue();
            }
          })
        }
        .width('100%')
        .constraintSize({ minHeight: Tokens.touchMin })
        .padding({ left: 10, right: 4, top: 4, bottom: 4 })
        .backgroundColor($r('app.color.bg2'))
        .borderRadius(Tokens.radiusMd)
        .alignItems(VerticalAlign.Center)
        .transition(chromeTransition())
      }

      Column({ space: 4 }) {
        if (this.imageUris.length > 0 && this.expanded()) {
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

        Row({ space: 6 }) {
          Stack({ alignContent: this.follow && !this.expanded() ? Alignment.Start : Alignment.TopStart }) {
            TextArea({
              text: this.text,
              placeholder: this.follow && !this.expanded() ? ' ' : this.placeholder
            })
              .width('100%')
              .height(this.fieldH())
              .constraintSize({
                minHeight: this.fieldMin(),
                maxHeight: this.fieldMax()
              })
              .fontSize(this.follow ? Tokens.typeCallout : Tokens.typeProse)
              .fontColor($r('app.color.text_primary'))
              .placeholderFont({
                size: this.follow ? Tokens.typeCallout : Tokens.typeProse,
                weight: FontWeight.Regular
              })
              .placeholderColor($r('app.color.text_placeholder'))
              .backgroundColor(Color.Transparent)
              .padding({
                left: 4,
                right: 4,
                top: this.follow && !this.expanded() ? 0 : 6,
                bottom: this.follow && !this.expanded() ? 0 : 2
              })
              .caretColor($r('app.color.accent'))
              .enabled(!this.busy)
              .id('promptArea')
              .defaultFocus(this.wantFocus)
              .onChange((v: string) => {
                this.text = v;
                this.onText(v);
              })
              .onFocus(() => {
                runLayout(() => {
                  this.focused = true;
                });
                this.wantFocus = false;
                this.onFocusChange(true);
              })
              .onBlur(() => {
                runLayout(() => {
                  this.focused = false;
                });
                this.onFocusChange(false);
              })
              .animation({ duration: motionMs(), curve: Curve.FastOutSlowIn })
            if (this.follow && !this.expanded() && this.text.trim().length === 0) {
              Row() {
                Text(this.placeholder)
                  .fontSize(Tokens.typeCallout)
                  .fontColor($r('app.color.text_placeholder'))
                  .maxLines(1)
              }
              .width('100%')
              .height(36)
              .padding({ left: 4, right: 4 })
              .alignItems(VerticalAlign.Center)
              .hitTestBehavior(HitTestMode.Transparent)
            }
          }
          .layoutWeight(1)
          .constraintSize({ minWidth: 0 })
          .height(this.fieldH())
          if (this.follow && !this.expanded()) {
            this.actionSwap()
          }
        }
        .width('100%')
        .alignItems(this.follow && !this.expanded() ? VerticalAlign.Center : VerticalAlign.Top)

        if (!this.follow || this.expanded()) {
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
          .transition(fadeTransition())
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: this.cardPadH(),
        right: this.cardPadH(),
        top: this.cardPadV(),
        bottom: this.cardPadV()
      })
      .backgroundColor($r('app.color.bg1'))
      .border({
        width: 1,
        color: this.focused ? $r('app.color.border_strong') : $r('app.color.border')
      })
      .borderRadius(Tokens.radiusSheet)
      .clip(true)
      .translate({ x: this.shake })
      .animation({ duration: motionMs(), curve: Curve.FastOutSlowIn })
    }
    .width('100%')
    .padding({
      left: Tokens.pagePad,
      right: Tokens.pagePad,
      bottom: this.bottomPad
    })
    .animation({ duration: motionMs(), curve: Curve.FastOutSlowIn })
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
    .borderRadius(Tokens.radiusMd)
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
      if (!this.follow) {
        HuChip({
          label: this.imageCount > 0 ? `图片 ${this.imageCount}` : '图片',
          on: false,
          maxVp: 88,
          onTap: () => {
            this.onImage();
          }
        })
        HuChip({
          label: this.repo.length > 0 ? this.repo : '仓库',
          on: false,
          maxVp: 168,
          onTap: () => {
            this.onRepo();
          }
        })
        HuChip({
          label: this.modelLabel.length > 0 ? this.modelLabel : '自动',
          on: false,
          maxVp: 220,
          onTap: () => {
            this.onModel();
          }
        })
        HuChip({
          label: this.moreLabel,
          on: false,
          maxVp: 80,
          onTap: () => {
            this.onMoreExtra();
          }
        })
      } else {
        HuChip({
          label: this.followUpMode === 'plan' ? 'Plan' : 'Agent',
          on: this.followUpMode === 'plan',
          onTap: () => {
            this.onModeChange(this.followUpMode === 'plan' ? 'agent' : 'plan');
          }
        })
        HuChip({
          label: this.modelLabel.length > 0 ? this.modelLabel : '自动',
          on: false,
          maxVp: 168,
          onTap: () => {
            this.onModel();
          }
        })
        HuChip({
          label: this.imageCount > 0 ? `图片 ${this.imageCount}` : '图片',
          on: this.imageCount > 0,
          maxVp: 88,
          onTap: () => {
            this.onImage();
          }
        })
        if (this.failedFollow) {
          HuChip({
            label: '重发',
            on: true,
            onTap: () => {
              this.onRetryFollow();
            }
          })
        }
      }
    }
    .constraintSize({ minHeight: Tokens.touchMin })
    .justifyContent(FlexAlign.Start)
  }
}
