import { ArtifactInfo } from '../models/Api';
import { Tokens } from '../theme/Tokens';
import { fileNameOf, formatBytes, isImagePath, isVideoPath } from '../utils/DisplayFmt';
import { relativeTime } from '../utils/TimeFmt';

@Component
export struct ArtifactRow {
  @Prop item: ArtifactInfo = { path: '' };
  @State previewUrl: string = '';
  @State loading: boolean = false;
  @State openError: string = '';
  resolveUrl: (path: string) => Promise<string> = async () => {
    return '';
  };
  onOpen: (url: string, title: string) => void = () => {
  };
  onFail: (msg: string) => void = () => {
  };

  aboutToAppear(): void {
    if (isImagePath(this.item.path) && this.previewUrl.length === 0 && !this.loading) {
      this.loading = true;
      this.resolveUrl(this.item.path).then((url: string) => {
        this.previewUrl = url;
        this.loading = false;
      }).catch(() => {
        this.loading = false;
      });
    }
  }

  private metaLine(): string {
    const bits: string[] = [this.kindLabel()];
    const size = formatBytes(this.item.sizeBytes);
    if (size.length > 0) {
      bits.push(size);
    }
    if (this.item.updatedAt && this.item.updatedAt.length > 0) {
      bits.push(relativeTime(this.item.updatedAt));
    }
    return bits.join(' · ');
  }

  private kindLabel(): string {
    if (isImagePath(this.item.path)) {
      return '截图';
    }
    if (isVideoPath(this.item.path)) {
      return '视频';
    }
    return '文件';
  }

  private open(): void {
    this.openError = '';
    this.resolveUrl(this.item.path).then((url: string) => {
      if (url.length > 0) {
        this.onOpen(url, fileNameOf(this.item.path));
        return;
      }
      this.openError = '无法打开产物';
      this.onFail(this.openError);
    }).catch(() => {
      this.openError = '打开失败';
      this.onFail(this.openError);
    });
  }

  build() {
    Column({ space: 8 }) {
      if (this.previewUrl.length > 0) {
        Image(this.previewUrl)
          .width('100%')
          .constraintSize({ maxHeight: 220 })
          .objectFit(ImageFit.Contain)
          .borderRadius(Tokens.radiusMd)
          .onClick(() => {
            this.open();
          })
      } else if (this.loading) {
        Row() {
          LoadingProgress().width(16).height(16).color($r('app.color.accent'))
          Text('加载预览…')
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ left: 8 })
        }
        .width('100%')
      }

      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(fileNameOf(this.item.path))
            .fontSize(Tokens.typeCallout)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.metaLine())
            .fontSize(Tokens.typeMicro)
            .fontColor($r('app.color.text_tertiary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Text('打开')
          .fontSize(Tokens.typeCaption)
          .fontColor($r('app.color.accent'))
          .constraintSize({ minHeight: Tokens.touchMin })
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .constraintSize({ minHeight: Tokens.touchMin })
      .onClick(() => {
        this.open();
      })

      if (this.openError.length > 0) {
        Text(this.openError)
          .fontSize(Tokens.typeMicro)
          .fontColor($r('app.color.err'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.bg2'))
    .borderRadius(Tokens.radiusMd)
  }
}
