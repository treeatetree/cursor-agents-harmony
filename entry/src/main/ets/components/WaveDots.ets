import { prefersReducedMotion } from '../utils/Motion';

/** Quiet typing-wave dots for in-flight inbox cards. */
@Component
export struct WaveDots {
  @Prop tint: Resource = $r('app.color.text_tertiary');
  @State private phase: number = 0;
  private timer: number = -1;

  aboutToAppear(): void {
    this.start();
  }

  aboutToDisappear(): void {
    this.stop();
  }

  private start(): void {
    this.stop();
    if (prefersReducedMotion()) {
      this.phase = 1;
      return;
    }
    this.timer = setInterval(() => {
      this.phase = (this.phase + 1) % 3;
    }, 280) as number;
  }

  private stop(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private dotY(i: number): number {
    if (prefersReducedMotion()) {
      return 0;
    }
    return this.phase === i ? -3 : 0;
  }

  private dotOpacity(i: number): number {
    if (prefersReducedMotion()) {
      return 0.55;
    }
    return this.phase === i ? 1 : 0.28;
  }

  @Builder
  dot(i: number) {
    Column()
      .width(3)
      .height(3)
      .borderRadius(1.5)
      .backgroundColor(this.tint)
      .opacity(this.dotOpacity(i))
      .translate({ y: this.dotY(i) })
      .animation({ duration: 260, curve: Curve.EaseInOut })
  }

  build() {
    Row({ space: 3 }) {
      this.dot(0)
      this.dot(1)
      this.dot(2)
    }
    .height(10)
    .alignItems(VerticalAlign.Bottom)
    .justifyContent(FlexAlign.End)
  }
}
