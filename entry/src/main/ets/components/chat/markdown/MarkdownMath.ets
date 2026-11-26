/**
 * 公式专用资源 owner。只调用 formula_hybrid 1.3.2 的公开 API，不依赖旧 Markdown 组件。
 * native 任务与文档修订分离：同文档世代/节点/公式/样式只保一个在途任务，最新票据替换
 * 待办；发布前重读当前三元票据与节点，周围正文增长不重复排同一公式，也不跨换版回填。
 * inlineOutput 将同一纹理交给父 Text 的 ImageSpan；父须按当前节点身份守卫回调，不能缓存
 * 历史纹理。替换、失效、离场均先通知 null，再归还本组件持有的资源。
 * 官方依据：Image Kit image-decoding、arkts-apis-image-imagesource/pixelmap/f；
 * UIContext fp2px/px2vp。公式库随 HAR 携 resfile/res 字体，不能只留下 liblatex.so。
 *
 * 所有权契约：PixelMap 生命周期归 MathRenderService（缓存持有 + 借用计数 + 唯一 release
 * 点）——本组件与父只借用：命中/交付即 acquire，换票/失败/离场经 clearImage 归还 release；
 * 拒收私有面仍归本组件自释放。native 排版与解码链已整体迁入 Service.resolve（在途去重），
 * 本组件保留票据循环、交付判定与父通知。组件代码禁 pixelMap.release()。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MarkdownDocumentToken } from '../../../common/markdown/MarkdownDocumentModel';
import { MarkdownNode } from '../../../common/markdown/MarkdownSemanticModel';
import { FONT_FAMILY_MONO } from '../../../common/ChatFont';
import { cardTitleColor } from '../../../common/Theme';
import { MATH_INLINE_FONT_SCALE, mathResourceKey } from '../../../common/markdown/MathRenderPolicy';
import { MarkdownMathImage, MathRenderResult, mathRenderService, releaseMathResource }
  from './MathRenderService';

// 接口随渲染链迁驻 Service 件（防坑50 模块环：Service 若反向 import 本件的导出单例即构成
// 顶层求值序环）；此处原名再导出，既有消费方（InlineView 等）import 路径零改动。
export { MarkdownMathImage, MathRenderResult } from './MathRenderService';

interface MarkdownMathTicket {
  token: MarkdownDocumentToken;
  nodeId: number;
  kind: string;
  tex: string;
  closed: boolean;
  darkMode: boolean;
  fontSize: number;
  fontPixels: number;
  pixelToVp: number;
  mount: number;
}

// 资源安全上界，不宣称性能阈值。超界仍显示完整源码，不截断/更改 AST。
const MAX_MATH_SOURCE_UNITS: number = 32768;

function sameMathResource(left: MarkdownMathTicket | null, right: MarkdownMathTicket): boolean {
  return left !== null && left.token.documentId === right.token.documentId &&
    left.token.generation === right.token.generation && left.nodeId === right.nodeId &&
    left.kind === right.kind && left.tex === right.tex && left.closed === right.closed &&
    left.darkMode === right.darkMode && left.fontSize === right.fontSize &&
    left.fontPixels === right.fontPixels && left.pixelToVp === right.pixelToVp && left.mount === right.mount;
}

@ComponentV2
export struct MarkdownMath {
  @Require @Param node: MarkdownNode;
  @Require @Param token: MarkdownDocumentToken;
  @Param darkMode: boolean = false;
  @Param fontSize: number = 15;
  @Param inlineOutput: boolean = false;
  // 等宽字体家族串（总指挥裁定：兜底态对齐 RIK 关态形制改等宽源码——公式阅读壳退役后
  // 等宽+横滚是「源码文本」的正形；行内兜底（InlineView StyledSpan 灰底等宽）不受影响
  @Param codeFontFamily: string = FONT_FAMILY_MONO;
  @Event onImage: (value: MarkdownMathImage | null) => void = (_value: MarkdownMathImage | null): void => {};
  // 空串清除旧错误；加载中仍由父显示原公式，未闭合/错误则给可读说明。
  @Event onFailure: (message: string) => void = (_message: string): void => {};
  @Local private display: MarkdownMathImage | null = null;
  @Local private status: string = '公式排版中';
  @Local private imageSerial: number = 0;
  private alive: boolean = false;
  private mount: number = 0;
  private busy: boolean = false;
  private latest: MarkdownMathTicket | null = null;
  private settled: MarkdownMathTicket | null = null;
  // 当前 display 的缓存键（普通成员非状态——不驱动 UI）：null = 拒收私有面（组件自释放）。
  private cacheKey: string | null = null;

  aboutToAppear(): void {
    this.alive = true;
    this.mount++;
    this.syncInput();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.mount++;
    this.latest = null;
    this.settled = null;
    this.clearImage();
    // native Promise 不可取消；完成后按 mount 失效，自行释放未交付纹理，不再通知父。
  }

  @Monitor('node', 'token', 'darkMode', 'fontSize', 'inlineOutput')
  private onMathInput(): void {
    this.syncInput();
  }

  private capture(): MarkdownMathTicket {
    return {
      token: {
        documentId: this.token.documentId, generation: this.token.generation, revision: this.token.revision
      },
      nodeId: this.node.id,
      kind: this.node.kind,
      tex: this.node.text,
      closed: this.node.closed,
      darkMode: this.darkMode,
      fontSize: this.fontSize,
      // native 排版字号走行内补偿系数；票据身份含 fontPixels 数值，系数变化自动触发重排。
      fontPixels: this.getUIContext().fp2px(this.renderFontSize()),
      pixelToVp: this.getUIContext().px2vp(1),
      mount: this.mount
    };
  }

  // 行内公式 1.2 倍视觉补偿系数的单源入口；capture 与 accepts 必须同用本式保票据一致。
  private renderFontSize(): number {
    return this.inlineOutput ? this.fontSize * MATH_INLINE_FONT_SCALE : this.fontSize;
  }

  private accepts(ticket: MarkdownMathTicket): boolean {
    return this.alive && ticket.mount === this.mount &&
      this.token.documentId === ticket.token.documentId && this.token.generation === ticket.token.generation &&
      this.token.revision === ticket.token.revision && this.node.id === ticket.nodeId &&
      this.node.kind === ticket.kind && this.node.text === ticket.tex && this.node.closed === ticket.closed &&
      this.darkMode === ticket.darkMode && this.fontSize === ticket.fontSize &&
      this.getUIContext().fp2px(this.renderFontSize()) === ticket.fontPixels &&
      this.getUIContext().px2vp(1) === ticket.pixelToVp;
  }

  private currentTicket(work: MarkdownMathTicket): MarkdownMathTicket | null {
    const current: MarkdownMathTicket | null = this.latest;
    // 旧任务仅可提供同一纹理，能否显示由最新票据与当前 Param 的精确相等决定。
    return current !== null && sameMathResource(work, current) && this.accepts(current) ? current : null;
  }

  private inputFailure(ticket: MarkdownMathTicket): string {
    if (ticket.kind !== 'math' && ticket.kind !== 'mathBlock') {
      return '无法识别公式。已保留源码';
    }
    if (!ticket.closed) {
      return '公式尚未闭合';
    }
    if (ticket.tex.trim() === '') {
      return '公式内容为空';
    }
    if (ticket.tex.length > MAX_MATH_SOURCE_UNITS) {
      return '公式过长。已保留源码';
    }
    if (!Number.isFinite(ticket.fontPixels) || ticket.fontPixels <= 0 ||
      !Number.isFinite(ticket.pixelToVp) || ticket.pixelToVp <= 0) {
      return '公式显示尺寸不可用。已保留源码';
    }
    return '';
  }

  private clearImage(): void {
    // 父的 ImageSpan 必须先撤引用，再归还/释放 owner；不可把已释放 PixelMap 留在父的 Map 中。
    this.onImage(null);
    const previous: MarkdownMathImage | null = this.display;
    const previousKey: string | null = this.cacheKey;
    this.display = null;
    this.cacheKey = null;
    if (previous !== null) {
      if (previousKey !== null) {
        // 缓存面：借用归还（PixelMap 留缓存由 Service 统一管理），不在此 release。
        mathRenderService.release(previousKey);
      } else {
        // 拒收私有面：所有权在本组件，维持现状自释放。
        releaseMathResource(previous.pixelMap);
      }
    }
  }

  // 命中交付的父通知分流：块级同步直发（aboutToAppear 同步写自身 @Local 合法）；行内
  // owner 的 aboutToAppear 在父 build 执行栈内，同步 onImage → acceptMath 写父 @Local =
  // 构建期重入——走 setTimeout(0) 兜底，带 alive/mount 守卫。此延迟回调是父预填漏填时的
  // 兜底（常态父已预填同值，冗余写无害）。
  private deliverImage(surface: MarkdownMathImage): void {
    if (!this.inlineOutput) {
      // 块级挂点不传 onImage（缺省空实现）；syncInput 本就在 aboutToAppear 同步写自身
      // @Local（status 同款先例），同步直写自身 build 前合法。
      this.onImage(surface);
      return;
    }
    const mount: number = this.mount;
    setTimeout((): void => {
      if (this.alive && this.mount === mount) {
        this.onImage(surface);
      }
    }, 0);
  }

  private syncInput(): void {
    if (!this.alive) {
      return;
    }
    let ticket: MarkdownMathTicket;
    try {
      ticket = this.capture();
    } catch (error) {
      this.latest = null;
      this.settled = null;
      this.clearImage();
      this.status = '公式显示环境不可用。已保留源码';
      this.onFailure(this.status);
      return;
    }
    this.latest = ticket;
    if (sameMathResource(this.settled, ticket)) {
      // 已完成的同纹理随最新正文修订复用，不重新调用 native；通知当前父重新绑定资源。
      this.settled = ticket;
      if (this.accepts(ticket)) {
        this.onImage(this.display);
        this.onFailure(this.display === null ? this.status : '');
      }
      return;
    }
    // 缓存命中分支——位置钉死在 clearImage 之前（R4 致命伤 2）：若放 clearImage 之后，行内
    // 父预填的 mathState 会被 clearImage 首句 onImage(null) 破坏性覆写——首帧仍源码 + 竞态闪烁。
    const key: string = mathResourceKey(ticket.tex, ticket.fontPixels, ticket.darkMode, ticket.pixelToVp);
    const hit: MarkdownMathImage | null = mathRenderService.lookup(key);
    if (hit !== null) {
      // 原子换图（不经 clearImage、无 onImage(null) 中转）：先归还/释放旧面，再定格新面。
      const previous: MarkdownMathImage | null = this.display;
      const previousKey: string | null = this.cacheKey;
      this.display = hit;
      this.imageSerial++;
      this.cacheKey = key;
      mathRenderService.acquire(key);
      if (previous !== null && previousKey !== null) {
        mathRenderService.release(previousKey);
      } else if (previous !== null) {
        // 旧面为拒收私有面（换档场景父侧 mathState 已随 resourceKey 重键过滤撤引用）。
        releaseMathResource(previous.pixelMap);
      }
      this.settled = ticket;
      this.status = '';
      // 同步 onFailure('')（现状先例；纪律口径以 onImage 图换为界——图换走 deliverImage 分流）。
      this.onFailure('');
      this.deliverImage(hit);
      return;
    }
    this.clearImage();
    this.settled = null;
    const failure: string = this.inputFailure(ticket);
    if (failure !== '') {
      this.settled = ticket;
      this.status = failure;
      this.onFailure(failure);
      return;
    }
    this.status = '公式排版中';
    this.onFailure('');
    if (!this.busy) {
      this.busy = true;
      this.drain();
    }
  }

  private fail(work: MarkdownMathTicket, message: string): void {
    const current: MarkdownMathTicket | null = this.currentTicket(work);
    if (current === null) {
      return;
    }
    this.clearImage();
    this.settled = current;
    this.status = message;
    this.onFailure(message);
  }

  private async drain(): Promise<void> {
    try {
      while (this.alive && this.latest !== null) {
        const work: MarkdownMathTicket = this.latest;
        if (!this.accepts(work) || sameMathResource(this.settled, work)) {
          break;
        }
        const key: string = mathResourceKey(work.tex, work.fontPixels, work.darkMode, work.pixelToVp);
        // native 排版 + 解码链整体在 Service.resolve（在途去重；票据已换代时不显示不借用，
        // surface 已在缓存供后来者）——fail 点文案与判据随链驻 Service。
        const outcome: MathRenderResult = await mathRenderService.resolve(key, work.tex,
          work.fontPixels, work.darkMode, work.pixelToVp);
        const current: MarkdownMathTicket | null = this.currentTicket(work);
        if (current === null) {
          continue;
        }
        if (outcome.surface === null) {
          this.fail(work, outcome.failText);
          continue;
        }
        const surface: MarkdownMathImage = outcome.surface;
        if (outcome.cached) {
          mathRenderService.acquire(key);
          this.cacheKey = key;
        } else {
          // 拒收私有面：所有权留组件，clearImage 走旧释放路径。
          this.cacheKey = null;
        }
        this.display = surface;
        this.imageSerial++;
        this.settled = current;
        this.status = '';
        this.onFailure('');
        this.onImage(surface);
        // 任务期间的所有新输入只覆盖 latest；下一轮只处理最后一份，不留修订队列。
      }
    } catch (error) {
      // UIContext 离场等同步异常也必须结束单任务占用，不产生未处理的 Promise rejection。
      if (this.alive) {
        this.latest = null;
        this.settled = null;
        this.clearImage();
        this.status = '公式显示环境不可用。已保留源码';
        this.onFailure(this.status);
      }
      hilog.error(0xD5A1, 'MarkdownMath', '公式排版任务异常结束');
    } finally {
      this.busy = false;
    }
  }

  private imageFailed(surface: MarkdownMathImage): void {
    if (this.display !== surface || this.settled === null) {
      return;
    }
    // 防损坏条目反复命中：display 渲染失败的缓存面先失效（立即移出可服集，PixelMap 等
    // clearImage 借用归零后由 Service 释放）再走现行 fail。
    if (this.cacheKey !== null) {
      mathRenderService.invalidate(this.cacheKey);
    }
    this.fail(this.settled, '公式图片显示失败。已保留源码');
  }

  build() {
    if (this.inlineOutput) {
      Blank().width(0).height(0)
    } else {
      Column({ space: 4 }) {
        if (this.display !== null) {
          Scroll() {
            Row() {
            ForEach([this.display], (surface: MarkdownMathImage) => {
              Image(surface.pixelMap)
                .width(surface.width)
                .height(surface.height)
                .objectFit(ImageFit.Contain)
                .copyOption(CopyOptions.None)
                .accessibilityText(this.node.text)
                .onError((): void => { this.imageFailed(surface); })
            }, (_surface: MarkdownMathImage): string => this.imageSerial.toString())
            }
          }
          .width('100%')
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .align(Alignment.TopStart)
          // 横滑回弹：块级公式横滚补 Spring，scrollBar Off 原样
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        } else {
          // 状态/错误提示行（源码上方小字，现状零位移）：流式中状态行位置稳定，源码增长不推动它。
          Text(this.status)
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
          // 兜底源码 = 等宽 13fp + 自身横滚：与仓内「源码兜底面」既定档同形；去 BREAK_ALL
          // 与 Text 的 width 才能取内容 intrinsic 宽实现横向滚动；横滚形制（Spring +
          // alwaysEnabled，BarState.Off）与上方渲染态分支同款。
          Scroll() {
            Text(this.node.text !== '' ? this.node.text : '公式内容为空')
              .fontSize(13)
              .lineHeight(18)
              .fontFamily(this.codeFontFamily)
              .fontColor(cardTitleColor())
              .copyOption(CopyOptions.None)
          }
          .width('100%')
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .align(Alignment.TopStart)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }
}
