import { GitBranch } from '../models/Api';
import { Tokens } from '../theme/Tokens';
import { HuTextButton } from './HuTextButton';

@Component
export struct OutcomeStrip {
  @Prop resultText: string = '';
  @Prop branches: GitBranch[] = [];
  @Prop highlight: boolean = false;
  @Prop durationMs: number = 0;
  @Prop artifactCount: number = 0;
  @Prop compareUrl: string = '';
  onOpenPr: (url: string) => void = () => {
  };
  onOpenAgent: () => void = () => {
  };
  onArtifacts: () => void = () => {
  };
  onCopyBranch: (branch: string) => void = () => {
  };
  onOpenCompare: (url: string) => void = () => {
  };

  private firstPr(): string {
    for (let i = 0; i < this.branches.length; i++) {
      if (this.branches[i].prUrl && (this.branches[i].prUrl as string).length > 0) {
        return this.branches[i].prUrl as string;
      }
    }
    return '';
  }

  private firstBranch(): string {
    for (let i = 0; i < this.branches.length; i++) {
      if (this.branches[i].branch && (this.branches[i].branch as string).length > 0) {
        return this.branches[i].branch as string;
      }
    }
    return '';
  }

  /** Hide trivial one-word results that already live in the transcript. */
  private showResultBody(): boolean {
    const t = this.resultText.trim();
    if (t.length === 0) {
      return false;
    }
    if (t.length <= 8 && this.firstPr().length > 0) {
      return false;
    }
    return true;
  }

  private hasBody(): boolean {
    return this.resultText.length > 0 || this.branches.length > 0 || this.durationMs > 0 ||
      this.artifactCount > 0 || this.compareUrl.length > 0;
  }

  build() {
    if (!this.hasBody()) {
      Column() {
      }
    } else {
      Column({ space: Tokens.space2 }) {
        if (this.showResultBody()) {
          Text(this.resultText.length > 160 ? `${this.resultText.substring(0, 160)}…` : this.resultText)
            .fontSize(Tokens.typeCallout)
            .fontColor($r('app.color.text_secondary'))
            .lineHeight(Tokens.lineCaption + 2)
            .width('100%')
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          if (this.firstPr().length > 0) {
            HuTextButton({
              label: '查看 PR',
              compact: true,
              color: $r('app.color.accent'),
              active: true,
              onTap: () => {
                this.onOpenPr(this.firstPr());
              }
            })
          }
          if (this.compareUrl.length > 0) {
            HuTextButton({
              label: '改动',
              compact: true,
              onTap: () => {
                this.onOpenCompare(this.compareUrl);
              }
            })
          }
          if (this.artifactCount > 0 || this.firstBranch().length > 0 || this.firstPr().length > 0) {
            HuTextButton({
              label: this.artifactCount > 0 ? `产物 ${this.artifactCount}` : '产物',
              compact: true,
              onTap: () => {
                this.onArtifacts();
              }
            })
          }
          HuTextButton({
            label: '网页打开',
            compact: true,
            onTap: () => {
              this.onOpenAgent();
            }
          })
        }
        .width('100%')
      }
      .width('100%')
      .padding({
        left: Tokens.space3,
        right: Tokens.space3,
        top: Tokens.space3,
        bottom: Tokens.space3
      })
      .backgroundColor(this.highlight ? $r('app.color.outcome_hi_bg') : $r('app.color.bg1'))
      .borderRadius(Tokens.radiusCard)
      .border({ width: 1, color: $r('app.color.border') })
      .animation({ duration: 280, curve: Curve.EaseOut })
    }
  }
}
