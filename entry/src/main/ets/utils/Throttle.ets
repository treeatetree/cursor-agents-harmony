export class Throttle {
  private delayMs: number;
  private timerId: number = -1;
  private pending: boolean = false;
  private callback: () => void;

  constructor(delayMs: number, callback: () => void) {
    this.delayMs = delayMs;
    this.callback = callback;
  }

  kick(): void {
    this.pending = true;
    if (this.timerId >= 0) {
      return;
    }
    this.timerId = setTimeout(() => {
      this.timerId = -1;
      if (this.pending) {
        this.pending = false;
        this.callback();
      }
    }, this.delayMs) as number;
  }

  flush(): void {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
    if (this.pending) {
      this.pending = false;
      this.callback();
    }
  }

  cancel(): void {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
    this.pending = false;
  }
}
