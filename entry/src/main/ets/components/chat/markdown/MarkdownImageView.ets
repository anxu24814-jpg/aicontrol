/**
 * 原生远程图片与失败文字出口。不接附件发送下载器，不放开 file/data/桥协议。
 * 请求以文档世代+节点+原URL为身份，增长修订不取消同图请求；回调重验当前修订下的
 * 节点与URL以及组件生命周期，防旧图/旧错误回填。原生Image随请求身份销毁，不全局缓存。
 */
import { ConfigurationConstant } from '@kit.AbilityKit';
import { MarkdownDocumentToken } from '../../../common/markdown/MarkdownDocumentModel';
import { MarkdownNode } from '../../../common/markdown/MarkdownSemanticModel';
import { MARKDOWN_BODY_FONT_SIZE, MARKDOWN_BODY_LINE_HEIGHT }
from '../../../common/markdown/MarkdownPresentation';
import { markdownSafeRemoteUrl } from '../../../common/markdown/MarkdownRenderProjection';
import { badgeBg, cardDescColor, cardTitleColor } from '../../../common/Theme';

interface MarkdownImageRequest {
  identity: string;
  token: MarkdownDocumentToken;
  nodeId: number;
  originalUrl: string;
  url: string;
  lifecycle: number;
  serial: number;
}

@ComponentV2
export struct MarkdownImageView {
  @Require @Param node: MarkdownNode;
  @Require @Param token: MarkdownDocumentToken;
  @Param darkMode: boolean = false;
  @Param imageHeight: number = 180;
  @Local private requests: MarkdownImageRequest[] = [];
  @Local private imageState: string = 'loading';
  private alive: boolean = false;
  private lifecycle: number = 0;
  private requestSerial: number = 0;
  private currentRequest: MarkdownImageRequest | null = null;

  private requestIdentity(): string {
    return this.token.documentId.length.toString() + ':' + this.token.documentId + ':' +
      this.token.generation.toString() + ':' + this.node.id.toString() + ':' +
      this.node.destination.length.toString() + ':' + this.node.destination;
  }

  private colorMode(): number {
    return this.darkMode ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  }

  aboutToAppear(): void {
    this.alive = true;
    this.lifecycle++;
    this.syncRequest();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.lifecycle++;
    this.currentRequest = null;
    // 原生Image由UI树销毁取消/释放；不在销毁钩子写@Local触发额外UI更新。
  }

  @Monitor('node', 'token')
  private onImageInput(): void {
    this.syncRequest();
  }

  private syncRequest(): void {
    if (!this.alive) {
      return;
    }
    const identity: string = this.requestIdentity();
    if (this.currentRequest !== null && this.currentRequest.identity === identity &&
      this.currentRequest.lifecycle === this.lifecycle &&
      this.token.revision >= this.currentRequest.token.revision) {
      // 相同资源的新修订仍合法，回调到达时再核当前node；绝不逐帧重启造成请求饿死。
      return;
    }
    const url: string = markdownSafeRemoteUrl(this.node.destination);
    const request: MarkdownImageRequest = {
      identity: identity,
      token: {
        documentId: this.token.documentId, generation: this.token.generation, revision: this.token.revision
      },
      nodeId: this.node.id,
      originalUrl: this.node.destination,
      url: url,
      lifecycle: this.lifecycle,
      serial: ++this.requestSerial
    };
    this.currentRequest = request;
    this.imageState = url === '' ? 'blocked' : 'loading';
    // ForEach键绑定不可变请求，不从可变this.node反查旧事件的“来源”。
    this.requests = url === '' ? [] : [request];
  }

  private accepts(request: MarkdownImageRequest): boolean {
    const current: MarkdownImageRequest | null = this.currentRequest;
    // 原生事件允许跨同资源修订接纳，但不是只核旧token。当前Param三元组、node与URL均重新读。
    return this.alive && current === request && request.lifecycle === this.lifecycle &&
      this.token.documentId === request.token.documentId && this.token.generation === request.token.generation &&
      this.token.revision >= request.token.revision && this.node.kind === 'image' &&
      this.node.id === request.nodeId && this.node.destination === request.originalUrl &&
      markdownSafeRemoteUrl(this.node.destination) === request.url;
  }

  private acceptComplete(request: MarkdownImageRequest, width: number, height: number, status: number): void {
    if (!this.accepts(request)) {
      return;
    }
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
      this.imageState = 'failed';
    } else if (status === 1) {
      // 0仅为数据到达，1才是解码成功；解码前继续显示alt+URL，不能成功空白。
      this.imageState = 'loaded';
    }
  }

  private acceptError(request: MarkdownImageRequest): void {
    if (this.accepts(request)) {
      this.imageState = 'failed';
    }
  }

  private statusText(): string {
    return this.imageState === 'blocked' ? '未加载图片。仅支持安全的 http 或 https 地址' :
      this.imageState === 'failed' ? '图片加载失败' : '图片加载中';
  }

  build() {
    Column({ space: 4 }) {
      if (this.imageState !== 'failed' && this.imageState !== 'blocked') {
        // URL换为无效地址时原生Image会保留旧图，因此只在请求身份变化时新建Image节点。
        ForEach(this.requests, (request: MarkdownImageRequest) => {
          Image(request.url)
            .width('100%')
            .height(this.imageHeight)
            .objectFit(ImageFit.Contain)
            .autoResize(true)
            .syncLoad(false)
            .copyOption(CopyOptions.None)
            .accessibilityText(this.node.text !== '' ? this.node.text : 'Markdown 图片')
            .onComplete((event) => {
              if (event !== undefined) {
                this.acceptComplete(request, event.width, event.height, event.loadingStatus);
              }
            })
            .onError((): void => {
              this.acceptError(request);
            })
        }, (request: MarkdownImageRequest): string =>
          request.identity + ':' + request.lifecycle.toString() + ':' + request.serial.toString())
      }
      if (this.imageState !== 'loaded') {
        Text(this.statusText())
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
        Text(this.node.text !== '' ? this.node.text : '未提供替代文字')
          .fontSize(MARKDOWN_BODY_FONT_SIZE)
          .lineHeight(MARKDOWN_BODY_LINE_HEIGHT)
          .fontColor(cardTitleColor())
          .width('100%')
        Text(this.node.destination !== '' ? this.node.destination : '图片地址为空')
          .fontSize(13)
          .lineHeight(20)
          .fontColor(cardDescColor())
          .wordBreak(WordBreak.BREAK_ALL)
          .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    // 预览框 20vp 圆角（决明拍板，与受限预览页 MarkdownPreview Web 框同口径）：本组件
    // 唯一挂载点 = 图片预览半模态 MarkdownImageCover，聊天正文不走此件；clip 裁背景底与
    // 位图边缘（badgeBg 背景框同被裁圆）。
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.imageState === 'loaded' ? Color.Transparent : badgeBg(this.colorMode()))
  }
}
