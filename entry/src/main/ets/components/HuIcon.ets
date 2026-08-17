/**
 * Monochrome filled icons. Theme comes from fillColor + $r('app.color.*'),
 * not from dark/media copies (HarmonyOS fillColor paints fill, not stroke).
 */
@Component
export struct HuIcon {
  @Prop name: string = 'more';
  @Prop iconSize: number = 22;
  @Prop tint: Resource = $r('app.color.text_primary');

  private src(): Resource {
    if (this.name === 'back') {
      return $r('app.media.ic_back');
    }
    if (this.name === 'plus') {
      return $r('app.media.ic_plus');
    }
    if (this.name === 'search') {
      return $r('app.media.ic_search');
    }
    if (this.name === 'settings') {
      return $r('app.media.ic_settings');
    }
    if (this.name === 'send') {
      return $r('app.media.ic_send');
    }
    if (this.name === 'close') {
      return $r('app.media.ic_close');
    }
    if (this.name === 'refresh') {
      return $r('app.media.ic_refresh');
    }
    if (this.name === 'external') {
      return $r('app.media.ic_external');
    }
    if (this.name === 'stop') {
      return $r('app.media.ic_stop');
    }
    if (this.name === 'image') {
      return $r('app.media.ic_image');
    }
    if (this.name === 'filter') {
      return $r('app.media.ic_filter');
    }
    if (this.name === 'chevronRight') {
      return $r('app.media.ic_chevron_right');
    }
    if (this.name === 'chevronDown') {
      return $r('app.media.ic_chevron_down');
    }
    if (this.name === 'chevronUp') {
      return $r('app.media.ic_chevron_up');
    }
    if (this.name === 'check') {
      return $r('app.media.ic_check');
    }
    return $r('app.media.ic_more');
  }

  build() {
    Image(this.src())
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .fillColor(this.tint)
      .draggable(false)
  }
}
