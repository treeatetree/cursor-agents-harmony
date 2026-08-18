import { StatusPill } from './StatusPill';

/** Back-compat strip: same props as before, now a centered StatusPill. */
@Component
export struct StatusBanner {
  @Prop text: string = '';
  @Prop tone: string = 'info';
  @Prop action: string = '';
  @Prop external: boolean = false;
  @Prop dismissible: boolean = false;
  onAction: () => void = () => {
  };
  onDismiss: () => void = () => {
  };

  build() {
    if (this.text.length === 0) {
      Column().width(0).height(0)
    } else {
      StatusPill({
        text: this.text,
        tone: this.tone,
        action: this.action,
        dismissible: this.dismissible,
        onAction: () => {
          this.onAction();
        },
        onDismiss: () => {
          this.onDismiss();
        }
      })
    }
  }
}
