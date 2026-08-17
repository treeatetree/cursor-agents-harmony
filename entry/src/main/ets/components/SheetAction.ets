import { Tokens } from '../theme/Tokens';
import { Haptics } from '../utils/Haptics';
import { pressMs, pressScaleOf } from '../utils/Motion';
import { HuIcon } from './HuIcon';

/**
 * Grouped action row for bindSheet menus. Parent supplies the card chrome.
 * trailing: '' | 'chevron' | 'external' | 'check'
 */
@Component
export struct SheetActionRow {
  @Prop label: string = '';
  @Prop hint: string = '';
  @Prop danger: boolean = false;
  @Prop trailing: string = '';
  @Prop last: boolean = false;
  @State private pressed: boolean = false;
  onTap: () => void = () => {
  };

  build() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(this.label)
          .fontSize(Tokens.typeCallout)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.danger ? $r('app.color.err') : $r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.hint.length > 0) {
          Text(this.hint)
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .constraintSize({ minWidth: 0 })

      if (this.trailing === 'check') {
        HuIcon({
          name: 'check',
          iconSize: 18,
          tint: $r('app.color.text_primary')
        })
      } else if (this.trailing === 'external') {
        HuIcon({
          name: 'external',
          iconSize: 16,
          tint: $r('app.color.text_tertiary')
        })
      } else if (this.trailing === 'chevron') {
        HuIcon({
          name: 'chevronRight',
          iconSize: 16,
          tint: $r('app.color.text_tertiary')
        })
      }
    }
    .width('100%')
    .constraintSize({ minHeight: Tokens.rowMin })
    .padding({
      left: 16,
      right: 16,
      top: this.hint.length > 0 ? 11 : 14,
      bottom: this.hint.length > 0 ? 11 : 14
    })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.pressed ? $r('app.color.bg1') : Color.Transparent)
    .border({
      width: { bottom: this.last ? 0 : 1 },
      color: $r('app.color.border')
    })
    .opacity(this.pressed ? 0.86 : 1)
    .animation({ duration: pressMs(), curve: Curve.EaseOut })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => {
      if (this.danger) {
        Haptics.warn();
      } else {
        Haptics.tick();
      }
      this.onTap();
    })
  }
}

/** Two-up tile for the primary actions in a sheet. */
@Component
export struct SheetActionTile {
  @Prop label: string = '';
  @Prop hint: string = '';
  @State private pressed: boolean = false;
  onTap: () => void = () => {
  };

  build() {
    Column({ space: 2 }) {
      Text(this.label)
        .fontSize(Tokens.typeCallout)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(Tokens.typeMicro)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .height(56)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 10, right: 10 })
    .backgroundColor($r('app.color.bg2'))
    .borderRadius(Tokens.radiusCard)
    .border({
      width: 1,
      color: this.pressed ? $r('app.color.border_strong') : $r('app.color.border')
    })
    .scale({ x: pressScaleOf(this.pressed), y: pressScaleOf(this.pressed) })
    .opacity(this.pressed ? 0.78 : 1)
    .animation({ duration: pressMs(), curve: Curve.EaseOut })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => {
      Haptics.tick();
      this.onTap();
    })
  }
}

/** Selectable card row for picker sheets (repo, etc.). */
@Component
export struct SheetPickRow {
  @Prop title: string = '';
  @Prop caption: string = '';
  @Prop selected: boolean = false;
  @State private pressed: boolean = false;
  onTap: () => void = () => {
  };

  build() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(Tokens.typeCallout)
          .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Regular)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.caption.length > 0) {
          Text(this.caption)
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .constraintSize({ minWidth: 0 })

      if (this.selected) {
        HuIcon({
          name: 'check',
          iconSize: 18,
          tint: $r('app.color.text_primary')
        })
      }
    }
    .width('100%')
    .constraintSize({ minHeight: Tokens.rowMin })
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.selected || this.pressed ? $r('app.color.bg2') : $r('app.color.bg1'))
    .border({
      width: 1,
      color: this.selected ? $r('app.color.border_strong') : $r('app.color.border')
    })
    .borderRadius(Tokens.radiusMd)
    .opacity(this.pressed ? 0.86 : 1)
    .animation({ duration: pressMs(), curve: Curve.EaseOut })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => {
      Haptics.tick();
      this.onTap();
    })
  }
}
