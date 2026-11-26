/** 代码/表格阅读入口与局部操作所有者。修订增长不换资源键，所有异步出口现读 Param 守票据。 */
import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MarkdownDocumentToken, MarkdownEndReason, nextMarkdownBindingId }
  from '../../../common/markdown/MarkdownDocumentModel';
import { MarkdownNode, markdownNode } from '../../../common/markdown/MarkdownSemanticModel';
import { MarkdownReadingInput, MarkdownReadingState, MarkdownReadingTicket, markdownReadingIdentity }
  from '../../../common/markdown/MarkdownReadingState';
import { MarkdownReadingActionResult, markdownReadingCopy, markdownReadingSave, markdownReadingSaveBytes }
  from '../../../common/markdown/MarkdownReadingActions';
import { markdownReadingCsv, markdownReadingRaw, markdownReadingTitle }
  from '../../../common/markdown/MarkdownReadingFormat';
import { withAiContentLabel } from '../../../common/AiDisclosure';
import { badgeBg, cardBorderColor, cardDescColor } from '../../../common/Theme';
import { ChatDisplayBudget } from '../../../common/chat/ChatDisplayBudget';
import { FONT_FAMILY_MONO, FONT_FAMILY_SYSTEM } from '../../../common/ChatFont';
import { isCodeAutoCollapseEnabled, isHtmlBlockRenderEnabled, isMermaidInlineEnabled, isSvgPreviewEnabled }
  from '../../../common/AppPreferences';
import { markdownPreviewVisible, markdownPreviewSvgLanguage, markdownPreviewSvgError,
  markdownHtmlProjection, MarkdownHtmlBlock } from '../../../common/markdown/MarkdownPreviewPolicy';
import { MarkdownReadingContent, MarkdownReadingCover } from './MarkdownReadingContent';
import { MarkdownHtmlBlockView } from './MarkdownHtmlBlockView';
import { MarkdownPreviewCover } from './MarkdownPreview';
import { MarkdownMermaidView } from './MarkdownMermaidView';
import { MERMAID_RENDER_SERVICE, MermaidUnsubscribe } from './MermaidRenderHost';
import { MERMAID_INLINE_SCALE, mermaidInlineEligible } from '../../../common/markdown/MermaidInlinePolicy';
import { MarkdownReferenceJump } from '../../../common/markdown/MarkdownNavigation';

// ── 超长代码块终态自动折叠（偏好开关默认关）──
// 阈值 N = 10 行，折叠形态 = 前 N 行 + 块底居中展开条。终态双层口径 = 块级闭合
//（node.closed）**且** 文档级终态（bodyEndReason 已在场）；**禁用 streaming 判终态**——
// 工具等待期 streaming=false 为假终态，无终态依据一律不折。
export const MARKDOWN_CODE_AUTO_COLLAPSE_LINES: number = 10;

/** 代码行数：语义节点 codeBlock.text 行分隔恒为 LF（块字面量 blockLiteral 归一），尾终止符
 *  不另起一行（'a\nb\n' = 2 行）。空文本 0 行。 */
export function markdownCodeLineCount(text: string): number {
  if (text === '') { return 0; }
  let count: number = 1;
  for (let index: number = 0; index < text.length; index++) {
    if (text.charCodeAt(index) === 10) { count++; }
  }
  return text.charCodeAt(text.length - 1) === 10 ? count - 1 : count;
}

/** 折叠态显示文本 = 前 maxLines 行（不足时原文原样；尾终止符不再带出）。 */
export function markdownCodeHeadText(text: string, maxLines: number): string {
  if (maxLines <= 0) { return ''; }
  let seen: number = 1;
  for (let index: number = 0; index < text.length; index++) {
    if (text.charCodeAt(index) !== 10) { continue; }
    if (seen === maxLines) { return text.substring(0, index); }
    seen++;
  }
  return text;
}

/** 终态自动折叠判定（无副作用，单独导出供断言直跑）：开关开 + 块级闭合 + 文档级终态
 *（bodyEndReason 非空）+ 行数超阈值四项齐备才折。 */
export function shouldAutoCollapse(lineCount: number, blockClosed: boolean,
  bodyEndReason: MarkdownEndReason | undefined, enabled: boolean): boolean {
  if (!enabled || !blockClosed || bodyEndReason === undefined) { return false; }
  return lineCount > MARKDOWN_CODE_AUTO_COLLAPSE_LINES;
}

// ── 长消息终态自动折叠（偏好开关默认关）──
// 代码块折叠范式扩展到消息级：助手正文源字符数超阈值（4000 起步）在文档级终态一次评估
// 收起为收起条 + 展开键（跳过整树解析与组件构建）。终态口径同上 = bodyEndReason 在场
//（**不用 streaming**——工具等待假终态）；流式期不折叠（流式红线）。判定消费在
// ChatMessageItem（展开意愿落 @Observed 字段，组件回收重建不回折）；展开即用户最终意图，
// 不提供反向收起键。
export const LONG_MSG_COLLAPSE_CHARS: number = 4000;

/** 长消息终态自动折叠判定（无副作用，单独导出供断言直跑，照 shouldAutoCollapse 范式）：
 * 开关开 + 文档级终态 + 源字符数超阈值三项齐备才折。 */
export function shouldCollapseLongMessage(charCount: number,
  bodyEndReason: MarkdownEndReason | undefined, enabled: boolean): boolean {
  if (!enabled || bodyEndReason === undefined) { return false; }
  return charCount > LONG_MSG_COLLAPSE_CHARS;
}

// ── HTML 投影流式护栏（缺陷修复）──
// 为什么：投影的「未闭合」判据只看 text 内部标签平衡，而流式在途的 htmlBlock text = 已
// 揭示前缀——多元素 htmlBlock 在每个元素闭合点都产生「可渲染窗口」，揭示拍落入即源码↔
// 渲染拍级翻转（闪烁 + 行高跳变）。判据：非尾块（其后已有新块 = 文本已封存）或已终态才
// 投影渲染；尾块且未终态恒走源码态。投影纯函数不懂流式（职责分离），流式时序判据只在本
// 挂点收口；终态到达后尾块一次切入渲染（允许一次切换）。
/** HTML 投影挂点判定（无副作用，单独导出供断言直跑）：非尾块或已终态才投影。 */
export function shouldRenderHtmlProjection(documentTail: boolean,
  bodyEndReason: MarkdownEndReason | undefined): boolean {
  return !documentTail || bodyEndReason !== undefined;
}

/** 折叠显示节点投影：字段级复制后只把 text 截为前 N 行——身份（id/kind/range）与其余字段
 *  逐项保留，故资源键、锚点、票据、复制/导出、完整阅读恒取原节点；children/parts 沿同一
 *  引用（语义快照不可变）。 */
function markdownCodeCollapsedNode(node: MarkdownNode, maxLines: number): MarkdownNode {
  const display: MarkdownNode = markdownNode(node.kind, node.range.start, node.range.end);
  display.id = node.id;
  display.text = markdownCodeHeadText(node.text, maxLines);
  display.destination = node.destination;
  display.title = node.title;
  display.label = node.label;
  display.closed = node.closed;
  display.level = node.level;
  display.ordered = node.ordered;
  display.startNumber = node.startNumber;
  display.tight = node.tight;
  display.checked = node.checked;
  display.language = node.language;
  display.headingId = node.headingId;
  display.alignments = node.alignments;
  display.children = node.children;
  display.parts = node.parts;
  return display;
}

@ComponentV2
export struct MarkdownScrollableBlock {
  @Require @Param node: MarkdownNode;
  @Require @Param token: MarkdownDocumentToken;
  @Param source: string = '';
  @Param darkMode: boolean = false;
  @Param aiContent: boolean = true;
  @Param referenceJump: MarkdownReferenceJump = { referenceId: 0, serial: 0 };
  // 文档级终态（自动折叠消费）：单源 = 消息 bodyEndReason，经快照 endReason 沿
  // MarkdownDocumentView/BlockView 下行——**不用 streaming**（工具等待假终态陷阱）。
  @Param bodyEndReason: MarkdownEndReason | undefined = undefined;
  // 文档尾块标记：本壳所在顶层块是文档最后一个可见块（其 text 仍在受揭示增长；顶层判定在
  // MarkdownDocumentView，子树整树继承）。HTML 投影护栏据此禁渲染。
  @Param documentTail: boolean = false;
  // 流式态标量：整树继承下行，本件只透传至内容面（代码降载判据在 MarkdownCodeText）；
  // 完整阅读半模态恒非流式读，不在本通道内。
  @Param live: boolean = false;
  // 显示成本预算：同上通道透传至内容面（高亮耗时补采样）；完整阅读不采样。
  @Param displayBudget: ChatDisplayBudget | undefined = undefined;
  // 消息字体家族串：随正文链下行——标题条与内容面分开取族（语言标签条属标题随正文字体；
  // 代码/表格/公式/HTML 投影/完整阅读内容随各自类型分发代码字体）
  @Param bodyFontFamily: string = FONT_FAMILY_SYSTEM;
  @Param codeFontFamily: string = FONT_FAMILY_MONO;
  @Event onNavigate: (destination: string) => void = (_destination: string): void => {};
  @Local private collapsed: boolean = false;
  // mermaid 内联图态：true = 服务已交出位图，内容面图/码 visibility 互斥；渲染失败恒
  // false = 代码态（零静默错渲染）。产物不进任何键（键纪律）。
  @Local private mermaidReady: boolean = false;
  // 自动折叠显示态：与手动折叠同为组件内 UI 态，不进任何键（同 collapsed 先例）；
  // autoCollapsible = 本块经终态评估命中「开关开 + 终态 + 超阈值」，其后用户展开/收起即最终形态。
  @Local private autoCollapsed: boolean = false;
  @Local private autoCollapsible: boolean = false;
  @Local private busy: boolean = false;
  @Local private covers: string[] = [];
  @Local private previews: string[] = [];
  @Local private mountKey: string = '';
  private autoEvaluated: boolean = false;
  private operations: MarkdownReadingState = new MarkdownReadingState();
  private alive: boolean = false;

  private input(): MarkdownReadingInput {
    return { token: this.token, nodeId: this.node.id, kind: this.node.kind, source: this.source };
  }

  private colorMode(): number {
    return this.darkMode ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  }

  aboutToAppear(): void {
    // 同一组件对象重挂也不能复活 dispose 的旧票据。
    this.operations = new MarkdownReadingState();
    this.alive = true;
    this.mountKey = nextMarkdownBindingId();
    this.collapsed = false;
    this.autoCollapsed = false;
    this.autoCollapsible = false;
    this.autoEvaluated = false;
    this.busy = false;
    this.mermaidReady = false;
    this.covers = [];
    this.previews = [];
    this.operations.bind(this.input());
    // 挂载即评估一次（重进会话/历史消息已终态块）；流式在途块由终态 Monitor 承接。
    this.evaluateAutoCollapse();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.operations.dispose();
    // 子 Cover/Scroll 随资源树销毁；旧任务不再允许 UI 回填。
  }

  @Monitor('node', 'token', 'source')
  private syncInput(): void {
    if (!this.alive) { return; }
    if (this.operations.bind(this.input())) {
      this.collapsed = false;
      this.autoCollapsed = false;
      this.autoCollapsible = false;
      this.autoEvaluated = false;
      this.mermaidReady = false;
      this.covers = [];
      this.previews = [];
      this.evaluateAutoCollapse();
    }
    this.busy = this.operations.isBusy();
  }

  // 终态到达（文档级 bodyEndReason 下行）即复评：仅在首达终态时评估一次，此后不再重评
  //（展开即用户最终意图——滚出/重渲染不重折，RIK「展开态组件实例内保持」同口径）。
  @Monitor('bodyEndReason')
  private onDocumentSettled(): void {
    this.evaluateAutoCollapse();
  }

  // 终态自动折叠评估：双层口径齐备才评估——文档级终态已在场时评估一次并记档，
  // 命中判定交纯函数 shouldAutoCollapse（开关态现读，重进会话后生效）。
  private evaluateAutoCollapse(): void {
    if (!this.alive || this.autoEvaluated || this.node.kind !== 'codeBlock' ||
      this.bodyEndReason === undefined) { return; }
    this.autoEvaluated = true;
    this.autoCollapsible = shouldAutoCollapse(markdownCodeLineCount(this.node.text),
      this.node.closed === true, this.bodyEndReason, isCodeAutoCollapseEnabled());
    if (this.autoCollapsible) { this.autoCollapsed = true; }
  }

  // 折叠显示节点：自动折叠态只把显示文本截为前 N 行；其余状态恒返回原节点（引用不变）。
  private displayedNode(): MarkdownNode {
    if (!this.autoCollapsible || !this.autoCollapsed) { return this.node; }
    return markdownCodeCollapsedNode(this.node, MARKDOWN_CODE_AUTO_COLLAPSE_LINES);
  }

  // 消息流 HTML 块渲染投影（最高危项默认开）：开关开 + htmlBlock + 流式护栏（尾块未
  // 终态恒 null）+ 结构投影非空（未闭合/超限/畸形/无可见内容一律 null）才走原生渲染组件，
  // 否则原源码阅读面。@Computed 缓存重复求值；刷新走 @Param 正道（挂点键零改动），开关态
  // 现读 = 重进会话后生效。复制/保存/完整阅读仍取原节点源文（投影只改显示面）。
  @Computed
  get htmlBlockProjection(): MarkdownHtmlBlock[] | null {
    if (this.node.kind !== 'htmlBlock' || !isHtmlBlockRenderEnabled() ||
      !shouldRenderHtmlProjection(this.documentTail, this.bodyEndReason)) { return null; }
    return markdownHtmlProjection(this.node.text);
  }

  // mermaid 内联挂点判定：开关现读 + 闭合 + 准入通过（与点开受限预览同源，禁第二套语言
  // 判定）。与 HTML 投影尾块护栏刻意不同：mermaid 围栏闭合后文本不再增长，闭合即可渲，
  // 无需等文档终态——渲染完成前代码面照常显示，完成后一次切换。
  @Computed
  get mermaidInlineCandidate(): boolean {
    return this.node.kind === 'codeBlock' && mermaidInlineEligible(this.node, isMermaidInlineEnabled());
  }

  // 反馈面 = toast 单通道（真机反馈：消息块内常驻提示行占版面，退役）；
  // toast 抛错只剩 hilog 可依，不得改成静默吞掉。
  private showFeedback(message: string): void {
    if (!this.alive) { return; }
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (failure) {
      hilog.error(0xD5A0, 'MarkdownReading', '阅读反馈提示失败：%{public}s', (failure as Error).message);
    }
  }

  private acceptResult(state: MarkdownReadingState, ticket: MarkdownReadingTicket,
    result: MarkdownReadingActionResult, save: boolean): void {
    if (!this.alive || this.operations !== state || !state.sameBinding(ticket, this.input())) { return; }
    if (result.status === 'cancelled') {
      // 用户取消是单独结果，不报失败、不弹成功。
      this.showFeedback('已取消保存');
      return;
    }
    const fileNotice: string = result.fileTouched ? '\n所选文件可能不完整，请检查 ' + result.uri : '';
    if (!state.accepts(ticket, this.input()) || result.status === 'stale') {
      this.showFeedback('内容已更新，请重试' + fileNotice);
      return;
    }
    if (result.status === 'failed') {
      this.showFeedback((result.message !== '' ? result.message : '操作失败，请重试') + fileNotice);
      return;
    }
    this.showFeedback(save ? '已保存' : '已复制');
  }

  private async perform(save: boolean): Promise<void> {
    if (!this.alive) { return; }
    this.syncInput();
    // 捕获票据、节点和源文在第一个 await 之前完成，不能拿新节点搭旧 token。
    const state: MarkdownReadingState = this.operations;
    const current: MarkdownReadingInput = this.input();
    const ticket: MarkdownReadingTicket | null = state.begin(current);
    if (ticket === null) { return; }
    const node: MarkdownNode = this.node;
    const csv: boolean = node.kind === 'table';
    this.busy = true;
    try {
      if (node.kind === 'codeBlock' && node.text === '') {
        throw new Error('代码内容为空，暂无可复制或保存的内容');
      }
      const raw: string = csv ? markdownReadingRaw(ticket.source, node) : node.text;
      const text: string = save && csv ? markdownReadingCsv(node, this.aiContent) :
        this.aiContent ? withAiContentLabel(raw) : raw;
      const accepts: () => boolean = (): boolean => this.alive && this.operations === state &&
        state.accepts(ticket, this.input());
      const result: MarkdownReadingActionResult = save ? await markdownReadingSave(
        this.getUIContext().getHostContext() as common.UIAbilityContext, text,
        csv ? '表格.csv' : '代码.txt', csv, accepts) : await markdownReadingCopy(text, accepts);
      this.acceptResult(state, ticket, result, save);
    } catch (failure) {
      const message: string = (failure as Error).message;
      hilog.error(0xD5A0, 'MarkdownReading', '阅读操作准备失败：%{public}s', message);
      if (this.alive && this.operations === state && state.sameBinding(ticket, this.input())) {
        this.showFeedback(state.accepts(ticket, this.input()) ? message : '内容已更新，请重试');
      }
    } finally {
      state.finish(ticket);
      if (this.alive && this.operations === state) { this.busy = state.isBusy(); }
    }
  }

  // 保存键两态：图态 = 保存图片（PNG 携 AI 标识条），码态 = 原语义（表格 CSV / 代码 txt）；
  // 语义随显示形态切换，不新增第六枚键。
  private saveLabel(): string {
    if (this.node.kind === 'table') { return '导出 CSV'; }
    return this.mermaidReady ? '保存图片' : '保存 txt';
  }

  // 导出走服务同一条渲染链（watermark=true 独立缓存键）：产物带 AI 标识条，与复制/CSV 的
  // aiContent 标识义务同源；保存出口复用阅读链票据与 picker 纪律（同 busy 单任务闸）。
  private async exportMermaidImage(): Promise<void> {
    if (!this.alive) { return; }
    this.syncInput();
    const state: MarkdownReadingState = this.operations;
    const current: MarkdownReadingInput = this.input();
    const ticket: MarkdownReadingTicket | null = state.begin(current);
    if (ticket === null) { return; }
    this.busy = true;
    try {
      const bytes: Uint8Array | null = await this.requestMermaidExport();
      if (!this.alive || this.operations !== state || !state.sameBinding(ticket, this.input())) { return; }
      if (bytes === null) {
        this.showFeedback('图表导出失败，请重试');
        return;
      }
      const accepts: () => boolean = (): boolean => this.alive && this.operations === state &&
        state.accepts(ticket, this.input());
      const result: MarkdownReadingActionResult = await markdownReadingSaveBytes(
        this.getUIContext().getHostContext() as common.UIAbilityContext, bytes, '图表.png', accepts);
      this.acceptResult(state, ticket, result, true);
    } catch (failure) {
      const message: string = (failure as Error).message;
      hilog.error(0xD5A0, 'MarkdownReading', '图表导出准备失败：%{public}s', message);
      if (this.alive && this.operations === state && state.sameBinding(ticket, this.input())) {
        this.showFeedback(state.accepts(ticket, this.input()) ? message : '内容已更新，请重试');
      }
    } finally {
      state.finish(ticket);
      if (this.alive && this.operations === state) { this.busy = state.isBusy(); }
    }
  }

  private requestMermaidExport(): Promise<Uint8Array | null> {
    return new Promise<Uint8Array | null>((resolve: (value: Uint8Array | null) => void): void => {
      let settled: boolean = false;
      const unsubscribe: MermaidUnsubscribe = MERMAID_RENDER_SERVICE.subscribe(this.node.text, this.darkMode,
        MERMAID_INLINE_SCALE, true, (bytes: Uint8Array | null, _message: string): void => {
          if (settled) { return; }
          settled = true;
          unsubscribe();
          resolve(bytes);
        });
    });
  }

  private openCover(): void {
    if (!this.alive) { return; }
    this.syncInput();
    if (this.covers.length > 0) { return; }
    this.covers = [markdownReadingIdentity(this.input()) + '/' + nextMarkdownBindingId()];
  }

  // 受限预览开启守卫：预览宿主随 previews 数组挂载，onClosed 单口回收。拒因可见化：
  // 准入失败的闭合 svg/xml 围栏不再静默无键——点击弹策略单源给出的具体拒因（UIContext
  // toast），点击前不重判校验。
  private openPreview(): void {
    if (!this.alive || this.previews.length > 0 || !this.previewEnabled() ||
      (this.node.kind === 'codeBlock' && !this.node.closed)) { return; }
    const reason: string = this.previewBlockReason();
    if (reason !== '') { this.showFeedback(reason); return; }
    this.previews = [nextMarkdownBindingId()];
  }

  // 拒因单源：svg/xml 面现取策略纯函数的准入结论（校验逻辑全在
  // MarkdownPreviewPolicy，本件只消费结果）；空串 = 通过，非空 = 可直接上屏的拒因文案。
  private previewBlockReason(): string {
    if (!markdownPreviewSvgLanguage(this.node)) { return ''; }
    return markdownPreviewSvgError(this.node.text, this.node.closed === true);
  }

  // 受限预览键在场判定（改判口径）：可见性（含准入失败的闭合 svg/xml 围栏）+ svg/xml
  // 面偏好开关现读（prefSvgPreview 默认开；关态 = 无预览入口，已挂载块不即时增删键，重进
  // 会话后生效）。html 与 mermaid 面不受此开关约束。
  private previewEnabled(): boolean {
    if (!markdownPreviewVisible(this.node)) { return false; }
    if (markdownPreviewSvgLanguage(this.node)) { return isSvgPreviewEnabled(); }
    return true;
  }

  private closePreview(session: string): void {
    if (this.alive && this.previews.length === 1 && this.previews[0] === session) {
      this.previews = [];
    }
  }

  private coverAction(session: string, save: boolean): void {
    if (!this.alive || this.covers.length !== 1 || this.covers[0] !== session ||
      !session.startsWith(markdownReadingIdentity(this.input()) + '/')) { return; }
    this.perform(save);
  }

  private closeCover(session: string): void {
    if (this.alive && this.covers.length === 1 && this.covers[0] === session) {
      this.covers = [];
    }
  }

  @Builder
  ReadingHeader() {
    Column() {
      // 间距 8（真机反馈：4 过密易误触；标题 layoutWeight 收缩避让，两行截断兜底）
      Row({ space: 8 }) {
        // 语言名只占余量，不与操作争宽；标题随正文字体（语言名是标签不是代码内容）
        Text(markdownReadingTitle(this.node))
          .fontSize(14).fontFamily(this.bodyFontFamily).fontWeight(FontWeight.Medium).fontColor(cardDescColor())
          .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .accessibilityText(markdownReadingTitle(this.node))
        // 三枚裸图标键收进标题条右槽（宪法「行内操作按钮官方形制」图标键：TEXTUAL 无底 +
        // font_secondary，先例 ProviderHeadCard 刷新键）；复制/保存语义与票据链零改动。
        if (this.node.kind === 'table' || this.node.kind === 'codeBlock') {
          Button() {
            SymbolGlyph($r('sys.symbol.doc_filled_on_doc'))
              .fontSize(16).fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .accessibilityText(this.node.kind === 'table' ? '复制原文' : '复制')
          .enabled(!this.busy)
          .onClick((): void => { this.perform(false); })
          Button() {
            SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
              .fontSize(16).fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .accessibilityText(this.saveLabel())
          .enabled(!this.busy)
          .onClick((): void => {
            // 图态导出 PNG（带 AI 标识条），码态保持原保存语义；两路共用 busy 单任务闸。
            if (this.mermaidReady) { this.exportMermaidImage(); } else { this.perform(true); }
          })
          Button() {
            SymbolGlyph($r('sys.symbol.arrow_up_left_and_arrow_down_right'))
              .fontSize(16).fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .accessibilityText('完整阅读')
          .enabled(this.covers.length === 0)
          .onClick((): void => { this.openCover(); })
        }
        // 受限预览键：HTML 块、Mermaid 图表与 SVG 图形入标题条右槽，与完整阅读同槽族；
        // 行内 HTML 段落无标题栏，入口由 MarkdownInlineView 承载。SVG 面另受 prefSvgPreview
        // 开关约束（previewEnabled 单口判定）。
        if (this.previewEnabled()) {
          Button() {
            SymbolGlyph($r('sys.symbol.eye'))
              .fontSize(16).fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .accessibilityText('受限预览')
          .enabled(this.previews.length === 0 && (this.node.kind !== 'codeBlock' || this.node.closed))
          .onClick((): void => { this.openPreview(); })
        }
        if (this.node.kind === 'codeBlock') {
          Button() {
            SymbolGlyph(this.collapsed ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_up'))
              .fontSize(16).fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .accessibilityText(this.collapsed ? '展开代码' : '折叠代码')
          .onClick((): void => { this.syncInput(); this.collapsed = !this.collapsed; })
        }
      }
      .width('100%')
    }
    .width('100%').alignItems(HorizontalAlign.Start).padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(badgeBg(this.colorMode()))
    Divider().strokeWidth(0.5).color(cardBorderColor(this.colorMode()))
  }

  // 底部居中展开条：自动折叠态下的收起/展开入口。形制照行内按钮宪法「裸图标键族」
  //（TEXTUAL 无底 + font_secondary，与 ReadingHeader 五键同族），不自绘底色/圆角/按压；
  // 条内状态直读组件 @Local 不经值参（可变状态不进 @Builder 值参——坑16 家族实锤）；
  // 记号与手动折叠键同义（折叠态 chevron_down = 向下展开）。
  @Builder
  AutoCollapseBar() {
    Row() {
      Button() {
        Row({ space: 4 }) {
          SymbolGlyph(this.autoCollapsed ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_up'))
            .fontSize(16)
            .fontColor([$r('sys.color.font_secondary')])
          Text(this.autoCollapsed ? '展开全部' : '收起')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }
        .alignItems(VerticalAlign.Center)
      }
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .accessibilityText(this.autoCollapsed ? '展开全部代码' : '收起代码')
      .onClick((): void => { this.autoCollapsed = !this.autoCollapsed; })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 2, bottom: 8 })
  }

  build() {
    Column() {
      this.ReadingHeader()
      // 受限预览宿主（MarkdownPreviewCover 自持 isPresent 与 Web 生命周期）随 previews 挂载；
      // 行内 HTML 的段落内入口由 MarkdownInlineView 挂 MarkdownPreview 承载。
      ForEach(this.previews, (session: string) => {
        MarkdownPreviewCover({ node: this.node, token: this.token, darkMode: this.darkMode, session: session,
          codeFontFamily: this.codeFontFamily,
          onClosed: (closed: string): void => { this.closePreview(closed); } })
      }, (session: string): string => session)
      ForEach([this.mountKey + '/' + markdownReadingIdentity(this.input())], (_identity: string) => {
        // 内容分支（挂点键零改动）：htmlBlock 且开关开且护栏放行且投影非空 → 白名单
        // 投影渲染，否则原阅读面（源码/代码/表格/公式）；头部标题条与五键不动，投影只改
        // 显示面——复制/导出与完整阅读恒取原节点源文。
        if (this.htmlBlockProjection !== null) {
          MarkdownHtmlBlockView({ nodes: this.htmlBlockProjection, darkMode: this.darkMode,
            bodyFontFamily: this.bodyFontFamily, codeFontFamily: this.codeFontFamily })
            .visibility(this.collapsed ? Visibility.None : Visibility.Visible)
        } else if (this.mermaidInlineCandidate) {
          // mermaid 图与代码面同挂、visibility 互斥（键零改动：产物不进键）。图出面后
          // 代码面仍在树上——折叠键、复制/保存与完整阅读恒取原节点源文；图点击开全屏预览。
          MarkdownMermaidView({ source: this.node.text, darkMode: this.darkMode,
            onReady: (): void => { this.mermaidReady = true; },
            onUnavailable: (_message: string): void => { this.mermaidReady = false; },
            onOpenPreview: (): void => { this.openPreview(); } })
            // 不与代码面做 visibility 互斥：图组件要恒参与布局，onAreaChange 才量得到容器宽
            //（Visibility.None 不参与布局，宽度恒 0 → 有像素也画不出来）；未出图时它自身
            // 无可见子节点（零高度），出图后代码面让位。
            .visibility(this.collapsed ? Visibility.None : Visibility.Visible)
          MarkdownReadingContent({ node: this.displayedNode(), token: this.token, source: this.source, darkMode: this.darkMode,
            referenceJump: this.referenceJump, live: this.live, displayBudget: this.displayBudget,
            bodyFontFamily: this.bodyFontFamily, codeFontFamily: this.codeFontFamily,
            onNavigate: (destination: string): void => { this.onNavigate(destination); } })
            .visibility(!this.mermaidReady && !this.collapsed ? Visibility.Visible : Visibility.None)
        } else {
          MarkdownReadingContent({ node: this.displayedNode(), token: this.token, source: this.source, darkMode: this.darkMode,
            referenceJump: this.referenceJump, live: this.live, displayBudget: this.displayBudget,
            bodyFontFamily: this.bodyFontFamily, codeFontFamily: this.codeFontFamily,
            onNavigate: (destination: string): void => { this.onNavigate(destination); } })
            // 保留内联树与 Scroller；折叠不把内容从源文裁掉，展开不重新挂载（自动折叠只改
            // 显示节点投影，源文与复制/导出恒取原节点）。
            .visibility(this.collapsed ? Visibility.None : Visibility.Visible)
        }
      }, (identity: string): string => identity)
      // 自动折叠展开条：仅终态评估命中的长代码块在场；手动整块折叠时随内容让位。
      if (this.autoCollapsible && !this.collapsed) {
        this.AutoCollapseBar()
      }
      ForEach(this.covers, (session: string) => {
        MarkdownReadingCover({ node: this.node, token: this.token, source: this.source, session: session,
          darkMode: this.darkMode, busy: this.busy,
          bodyFontFamily: this.bodyFontFamily, codeFontFamily: this.codeFontFamily,
          onNavigate: (destination: string): void => { this.closeCover(session); this.onNavigate(destination); },
          onClosed: (closed: string): void => { this.closeCover(closed); },
          onCopy: (): void => { this.coverAction(session, false); },
          onSave: (): void => { this.coverAction(session, true); } })
      }, (session: string): string => session)
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    .border({ width: 0.5, color: cardBorderColor(this.colorMode()) }).borderRadius(10).clip(true)
  }
}
