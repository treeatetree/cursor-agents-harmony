import { common } from '@kit.AbilityKit';
import { Tokens } from '../theme/Tokens';
import { Haptics } from '../utils/Haptics';
import { CropRect, readImageSize, writeSquareCrop } from '../utils/ImagePicker';
import { HuChip } from './HuChip';

const HOLE = 220;
const MIN_ZOOM = 1;
const MAX_ZOOM = 4;

/**
 * In-app circular mask + pinch/pan. WeChat / Instagram style — no system editor.
 */
@Component
export struct AvatarCrop {
  @Prop src: string = '';
  @State private ready: boolean = false;
  @State private zoom: number = 1;
  @State private panX: number = 0;
  @State private panY: number = 0;
  @State private dispW: number = HOLE;
  @State private dispH: number = HOLE;
  @State private busy: boolean = false;
  @State private failHint: string = '';
  private imgW: number = 1;
  private imgH: number = 1;
  private startZoom: number = 1;
  private startX: number = 0;
  private startY: number = 0;
  onCancel: () => void = () => {
  };
  onDone: (path: string) => void = (_path: string) => {
  };

  aboutToAppear(): void {
    this.loadSize();
  }

  private async loadSize(): Promise<void> {
    const size = await readImageSize(this.src);
    if (!size || size.width <= 0 || size.height <= 0) {
      this.failHint = '这张图读不了';
      return;
    }
    this.imgW = size.width;
    this.imgH = size.height;
    if (this.imgW / this.imgH >= 1) {
      this.dispH = HOLE;
      this.dispW = HOLE * this.imgW / this.imgH;
    } else {
      this.dispW = HOLE;
      this.dispH = HOLE * this.imgH / this.imgW;
    }
    this.zoom = 1;
    this.panX = (HOLE - this.dispW) / 2;
    this.panY = (HOLE - this.dispH) / 2;
    this.ready = true;
  }

  private clampPan(): void {
    const w = this.dispW * this.zoom;
    const h = this.dispH * this.zoom;
    const minX = HOLE - w;
    const minY = HOLE - h;
    if (this.panX > 0) {
      this.panX = 0;
    }
    if (this.panY > 0) {
      this.panY = 0;
    }
    if (this.panX < minX) {
      this.panX = minX;
    }
    if (this.panY < minY) {
      this.panY = minY;
    }
  }

  private cropRect(): CropRect {
    const w = this.dispW * this.zoom;
    const h = this.dispH * this.zoom;
    const rect: CropRect = {
      x: (-this.panX) / w * this.imgW,
      y: (-this.panY) / h * this.imgH,
      width: HOLE / w * this.imgW,
      height: HOLE / h * this.imgH
    };
    return rect;
  }

  private async confirm(): Promise<void> {
    if (this.busy || !this.ready) {
      return;
    }
    this.busy = true;
    this.failHint = '';
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const dest = `${ctx.filesDir}/avatar_${Date.now()}.jpg`;
      const path = await writeSquareCrop(this.src, dest, this.cropRect());
      if (path.length === 0) {
        Haptics.fail();
        this.failHint = '裁切失败，换一张试试';
        return;
      }
      Haptics.commit();
      this.onDone(path);
    } catch (_e) {
      Haptics.fail();
      this.failHint = '裁切失败，换一张试试';
    } finally {
      this.busy = false;
    }
  }

  build() {
    Column({ space: 10 }) {
      Text(this.failHint.length > 0 ? this.failHint : '拖动或捏合，圆内即头像')
        .fontSize(Tokens.typeCaption)
        .fontColor(this.failHint.length > 0 ? $r('app.color.err') : $r('app.color.text_tertiary'))
        .width('100%')

      Stack() {
        if (this.ready) {
          Image(this.src)
            .width(this.dispW * this.zoom)
            .height(this.dispH * this.zoom)
            .objectFit(ImageFit.Fill)
            .offset({ x: this.panX, y: this.panY })
        }
        Circle()
          .width(HOLE)
          .height(HOLE)
          .fill(Color.Transparent)
          .stroke($r('app.color.border_strong'))
          .strokeWidth(1)
          .hitTestBehavior(HitTestMode.Transparent)
      }
      .width(HOLE)
      .height(HOLE)
      .clip(true)
      .borderRadius(HOLE / 2)
      .backgroundColor($r('app.color.bg2'))
      .alignContent(Alignment.TopStart)
      .gesture(
        GestureGroup(GestureMode.Parallel,
          PinchGesture({ fingers: 2 })
            .onActionStart(() => {
              this.startZoom = this.zoom;
            })
            .onActionUpdate((e: GestureEvent) => {
              let z = this.startZoom * e.scale;
              if (z < MIN_ZOOM) {
                z = MIN_ZOOM;
              }
              if (z > MAX_ZOOM) {
                z = MAX_ZOOM;
              }
              this.zoom = z;
              this.clampPan();
            }),
          PanGesture({ fingers: 1, distance: 2 })
            .onActionStart(() => {
              this.startX = this.panX;
              this.startY = this.panY;
            })
            .onActionUpdate((e: GestureEvent) => {
              this.panX = this.startX + e.offsetX;
              this.panY = this.startY + e.offsetY;
              this.clampPan();
            })
        )
      )

      Row({ space: 8 }) {
        HuChip({
          label: '取消',
          onTap: () => {
            this.onCancel();
          }
        })
        HuChip({
          label: this.busy ? '…' : '完成',
          on: !this.busy,
          onTap: () => {
            this.confirm();
          }
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 8, bottom: 4 })
  }
}
