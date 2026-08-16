import { Tokens } from '../theme/Tokens';
import { prefersReducedMotion } from '../utils/Motion';

@Component
export struct StatusChip {
  @Prop label: string = '';
  @Prop tone: string = 'neutral'; // running | ok | err | warn | neutral
  @State private pulse: number = 1.0;
  private timerId: number = -1;

  aboutToAppear(): void {
    this.startPulse();
  }

  aboutToDisappear(): void {
    this.stopPulse();
  }

  onPageShow(): void {
    this.startPulse();
  }

  onPageHide(): void {
    this.stopPulse();
  }

  private startPulse(): void {
    this.stopPulse();
    if (this.tone !== 'running' || prefersReducedMotion()) {
      this.pulse = 1.0;
      return;
    }
    this.timerId = setInterval(() => {
      animateTo({ duration: 800, curve: Curve.EaseInOut }, () => {
        this.pulse = this.pulse > 0.8 ? 0.65 : 1.0;
      });
    }, 1600) as number;
  }

  private stopPulse(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private bg(): Resource {
    if (this.tone === 'running') {
      return $r('app.color.chip_running_bg');
    }
    if (this.tone === 'ok') {
      return $r('app.color.chip_ok_bg');
    }
    if (this.tone === 'err') {
      return $r('app.color.chip_err_bg');
    }
    if (this.tone === 'warn') {
      return $r('app.color.chip_warn_bg');
    }
    return $r('app.color.bg2');
  }

  private fg(): Resource {
    if (this.tone === 'running') {
      return $r('app.color.accent');
    }
    if (this.tone === 'ok') {
      return $r('app.color.ok');
    }
    if (this.tone === 'err') {
      return $r('app.color.err');
    }
    if (this.tone === 'warn') {
      return $r('app.color.warn');
    }
    return $r('app.color.text_secondary');
  }

  build() {
    Text(this.label)
      .fontSize(Tokens.typeMicro)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.fg())
      .opacity(this.tone === 'running' ? this.pulse : 1.0)
      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      .borderRadius(Tokens.radiusChip)
      .backgroundColor(this.bg())
  }
}
