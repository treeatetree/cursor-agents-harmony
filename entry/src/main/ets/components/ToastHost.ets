import { StatusPill } from './StatusPill';

/** Ephemeral notice. Only paints when AppStorage toastPage matches `page`. */
@Component
export struct ToastHost {
  @Prop page: string = '';
  @StorageLink('toastText') text: string = '';
  @StorageLink('toastTone') tone: string = 'info';
  @StorageLink('toastPage') toastPage: string = '';

  private visible(): boolean {
    if (this.text.length === 0) {
      return false;
    }
    if (this.page.length === 0 || this.toastPage.length === 0) {
      return true;
    }
    return this.page === this.toastPage;
  }

  build() {
    if (!this.visible()) {
      Column().width(0).height(0)
    } else {
      StatusPill({
        text: this.text,
        tone: this.tone.length > 0 ? this.tone : 'info'
      })
    }
  }
}
