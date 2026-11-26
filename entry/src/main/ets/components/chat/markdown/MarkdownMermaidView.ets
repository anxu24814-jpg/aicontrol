/**
 * 消息内 mermaid 图：订阅渲染服务、解码 PNG 位图并显示；点击交父打开现有受限预览。
 * 产物只来自固定离线壳的双侧校验链（MermaidRenderHost），本件不解析、不执行任何输入。
 * 失败或无产物时不渲染内容（父维持代码态显示，零静默错渲染）；PixelMap 组件独占并释放。
 */
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MERMAID_INLINE_SCALE, mermaidInlineDisplaySize } from '../../../common/markdown/MermaidInlinePolicy';
import { MERMAID_RENDER_SERVICE, MermaidUnsubscribe } from './MermaidRenderHost';

const MERMAID_DECODE_BYTES_LIMIT: number = 6 * 1024 * 1024;
const MERMAID_DECODE_EDGE_LIMIT: number = 4096;

async function releaseMermaidBitmap(resource: image.ImageSource | image.PixelMap | null | undefined): Promise<void> {
  if (resource === null || resource === undefined) {
    return;
  }
  try {
    await resource.release();
  } catch (failure) {
    // 清理失败记录即可；不把图表源码或原生错误详情打入公共日志。
    hilog.error(0xD5A0, 'MermaidInline', '图表位图资源释放失败');
  }
}

@ComponentV2
export struct MarkdownMermaidView {
  @Require @Param source: string;
  @Param darkMode: boolean = false;
  @Event onReady: () => void = (): void => {};
  @Event onUnavailable: (message: string) => void = (_message: string): void => {};
  @Event onOpenPreview: () => void = (): void => {};
  @Local private display: image.PixelMap | null = null;
  @Local private boxWidth: number = 0;
  @Local private pixelWidth: number = 0;
  @Local private pixelHeight: number = 0;
  private unsubscribe: MermaidUnsubscribe = (): void => {};
  private alive: boolean = false;
  private generation: number = 0;
  private decodeSerial: number = 0;

  aboutToAppear(): void {
    this.alive = true;
    this.subscribe();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.generation++;
    this.unsubscribe();
    this.unsubscribe = (): void => {};
    this.releaseDisplay();
  }

  @Monitor('source', 'darkMode')
  private onMermaidInput(): void {
    if (!this.alive) {
      return;
    }
    this.subscribe();
  }

  private subscribe(): void {
    this.unsubscribe();
    this.unsubscribe = (): void => {};
    this.releaseDisplay();
    const generation: number = ++this.generation;
    if (this.source === '') {
      this.onUnavailable('图表内容为空');
      return;
    }
    this.unsubscribe = MERMAID_RENDER_SERVICE.subscribe(this.source, this.darkMode, MERMAID_INLINE_SCALE,
      false, (bytes: Uint8Array | null, message: string): void => {
        if (!this.alive || generation !== this.generation) {
          return;
        }
        if (bytes === null) {
          this.onUnavailable(message);
          return;
        }
        this.decode(bytes, generation);
      });
  }

  private async decode(bytes: Uint8Array, generation: number): Promise<void> {
    const serial: number = ++this.decodeSerial;
    let source: image.ImageSource | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      if (bytes.byteLength === 0 || bytes.byteLength > MERMAID_DECODE_BYTES_LIMIT) {
        throw new Error('图表位图超出限制');
      }
      // createImageSource 只收 ArrayBuffer（官方 d.ts 无 Uint8Array 重载），传字节视图会解码
      // 失败。拷贝一次拿到独立 ArrayBuffer（产物 ≤6MB，代价可接受，也免去视图偏移问题）。
      const buffer: ArrayBuffer = new ArrayBuffer(bytes.byteLength);
      new Uint8Array(buffer).set(bytes);
      source = image.createImageSource(buffer);
      if (source === undefined) {
        throw new Error('图表位图无法解码');
      }
      pixelMap = await source.createPixelMap();
      if (pixelMap === undefined) {
        throw new Error('图表位图无法解码');
      }
      const info: image.ImageInfo = await pixelMap.getImageInfo();
      const stale: boolean = !this.alive || generation !== this.generation || serial !== this.decodeSerial;
      if (stale || info.size.width <= 0 || info.size.height <= 0 ||
        info.size.width > MERMAID_DECODE_EDGE_LIMIT || info.size.height > MERMAID_DECODE_EDGE_LIMIT) {
        await releaseMermaidBitmap(pixelMap);
        pixelMap = undefined;
        if (!stale) {
          this.onUnavailable('图表尺寸不可用');
        }
        return;
      }
      const delivered: image.PixelMap = pixelMap;
      pixelMap = undefined; // 所有权交给 display，finally 只清理未交付结果。
      this.releaseDisplay();
      this.display = delivered;
      this.pixelWidth = info.size.width;
      this.pixelHeight = info.size.height;
      this.onReady();
    } catch (failure) {
      hilog.warn(0xD5A0, 'MermaidInline', '图表位图解码失败：%{public}s', (failure as Error).message);
      if (this.alive && generation === this.generation && serial === this.decodeSerial) {
        this.onUnavailable('图表显示失败');
      }
    } finally {
      await releaseMermaidBitmap(source);
      await releaseMermaidBitmap(pixelMap);
    }
  }

  private releaseDisplay(): void {
    const previous: image.PixelMap | null = this.display;
    this.display = null;
    if (previous !== null) {
      releaseMermaidBitmap(previous);
    }
  }

  private imageFailed(): void {
    if (!this.alive) {
      return;
    }
    this.releaseDisplay();
    this.onUnavailable('图表显示失败');
  }

  build() {
    Column() {
      if (this.display !== null && this.boxWidth > 0) {
        Image(this.display)
          .width(mermaidInlineDisplaySize(this.pixelWidth, this.pixelHeight, this.boxWidth,
            MERMAID_INLINE_SCALE).width)
          .height(mermaidInlineDisplaySize(this.pixelWidth, this.pixelHeight, this.boxWidth,
            MERMAID_INLINE_SCALE).height)
          .objectFit(ImageFit.Contain)
          .copyOption(CopyOptions.None)
          .accessibilityText('Mermaid 图表')
          .onClick((): void => { this.onOpenPreview(); })
          .onError((): void => { this.imageFailed(); })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const width: number = newArea.width as number;
      if (Number.isFinite(width) && width > 0 && width !== this.boxWidth) {
        this.boxWidth = width;
      }
    })
  }
}
