/** 只读源码、行列有界表格与完整阅读半模态。内联与半模态各持独立 Scroller，往返不销毁内联树。 */
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { FrameCallback, UIContext, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { MarkdownDocumentToken } from '../../../common/markdown/MarkdownDocumentModel';
import { MarkdownNode } from '../../../common/markdown/MarkdownSemanticModel';
import { MarkdownReadingCellWindow, MarkdownReadingTablePage, MARKDOWN_READING_COLUMNS,
  MARKDOWN_READING_ROWS, MarkdownTableShapeCheck, markdownReadingCellWindow, markdownReadingRaw,
  markdownReadingTablePage, markdownReadingTitle } from '../../../common/markdown/MarkdownReadingFormat';
import { cardBorderColor, cardDescColor, cardTitleColor, CARD_PANEL_WIDTH, pageBgFade } from '../../../common/Theme';
import { ChatDisplayBudget } from '../../../common/chat/ChatDisplayBudget';
import { IMMERSIVE_LEVEL_KEY } from '../../../common/ImmersiveLevel';
import { MARKDOWN_BODY_FONT_SIZE, MARKDOWN_BODY_LINE_HEIGHT } from '../../../common/markdown/MarkdownPresentation';
import { FONT_FAMILY_MONO, FONT_FAMILY_SYSTEM } from '../../../common/ChatFont';
import { DETENTS_FULL, sheetPanelOptions, sheetTitleBarOptions } from '../KimiSheetCommon';
import { MarkdownInlineView } from './MarkdownInlineView';
import { MarkdownReadingButton } from './MarkdownReadingButton';
import { MarkdownCodeText } from './MarkdownCodeText';
import { MarkdownReferenceJump, markdownAnchorId, markdownHasNode } from '../../../common/markdown/MarkdownNavigation';

class MarkdownReadingFrame extends FrameCallback {
  private callback: (() => void) | null;
  constructor(callback: () => void) { super(); this.callback = callback; }
  cancel(): void { this.callback = null; }
  onIdle(_time: number): void {
    const callback: (() => void) | null = this.callback;
    this.callback = null;
    if (callback !== null) { callback(); }
  }
}

function contentIdentity(token: MarkdownDocumentToken, node: MarkdownNode): string {
  return token.documentId.length.toString() + ':' + token.documentId + ':' +
    token.generation.toString() + ':' + node.id.toString() + ':' + node.kind;
}

@ComponentV2
export struct MarkdownReadingContent {
  @Require @Param node: MarkdownNode;
  @Require @Param token: MarkdownDocumentToken;
  @Param source: string = '';
  @Param darkMode: boolean = false;
  @Event onNavigate: (destination: string) => void = (_destination: string): void => {};
  @Param referenceJump: MarkdownReferenceJump = { referenceId: 0, serial: 0 };
  @Param anchorEnabled: boolean = true;
  @Param scroller: Scroller = new Scroller();
  // 流式态标量：仅可复用块面经壳继承；完整阅读半模态不传 = 非流式缺省。
  @Param live: boolean = false;
  // 显示成本预算：同上通道透传至 MarkdownCodeText 补采样；不传 = 不采样。
  @Param displayBudget: ChatDisplayBudget | undefined = undefined;
  // 消息字体家族串：表格单元格正文走正文字体、源码档走代码字体（默认参与未配置逐字同）
  @Param bodyFontFamily: string = FONT_FAMILY_SYSTEM;
  @Param codeFontFamily: string = FONT_FAMILY_MONO;
  @Local private rowPage: number = 0;
  @Local private columnPage: number = 0;
  @Local private identity: string = '';
  private pendingScroll: MarkdownReadingFrame | null = null;
  // 表格结构增量校验器：跨拍续验水位，只重验末行与新行；身份/表头变化与缩短
  // 由校验器内部归零（另在本件身份变动点显式复位，防跨文档 id 撞号）。
  private tableShape: MarkdownTableShapeCheck = new MarkdownTableShapeCheck();

  aboutToDisappear(): void { this.pendingScroll?.cancel(); this.pendingScroll = null; }

  aboutToAppear(): void {
    this.identity = contentIdentity(this.token, this.node);
    this.rowPage = 0;
    this.columnPage = 0;
    this.tableShape = new MarkdownTableShapeCheck();
    this.jumpToReference();
  }

  @Monitor('referenceJump')
  private jumpToReference(): void {
    if (this.node.kind !== 'table' || this.referenceJump.referenceId <= 0) { return; }
    for (let row: number = 0; row < this.node.children.length; row++) {
      for (let column: number = 0; column < this.node.children[row].children.length; column++) {
        if (markdownHasNode([this.node.children[row].children[column]], this.referenceJump.referenceId)) {
          this.rowPage = Math.floor(Math.max(0, row - 1) / MARKDOWN_READING_ROWS);
          this.columnPage = Math.floor(column / MARKDOWN_READING_COLUMNS);
          const identity: string = contentIdentity(this.token, this.node);
          const serial: number = this.referenceJump.serial;
          const offset: number = (column % MARKDOWN_READING_COLUMNS) * 160;
          this.pendingScroll?.cancel();
          const frame: MarkdownReadingFrame = new MarkdownReadingFrame((): void => {
            if (this.pendingScroll === frame && identity === contentIdentity(this.token, this.node) &&
              serial === this.referenceJump.serial) {
              this.pendingScroll = null;
              try { this.scroller.scrollTo({ xOffset: offset, yOffset: 0, animation: false }); }
              catch (error) {
                this.getUIContext().getPromptAction().showToast({ message: '引用所在列暂时无法定位，请横向滚动查看' });
              }
            }
          });
          this.pendingScroll = frame;
          this.getUIContext().postFrameCallback(frame);
          return;
        }
      }
    }
  }

  @Monitor('node', 'token')
  private syncIdentity(): void {
    const current: string = contentIdentity(this.token, this.node);
    if (this.identity !== current) {
      this.identity = current;
      this.rowPage = 0;
      this.columnPage = 0;
      this.tableShape = new MarkdownTableShapeCheck();
    }
  }

  @Computed
  get page(): MarkdownReadingTablePage {
    const same: boolean = contentIdentity(this.token, this.node) === this.identity;
    return markdownReadingTablePage(this.node, same ? this.rowPage : 0, same ? this.columnPage : 0,
      this.tableShape);
  }

  private mode(): number {
    return this.darkMode ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  }

  private rawFallback(): string {
    try {
      const raw: string = markdownReadingRaw(this.source, this.node);
      return raw !== '' ? raw : '此表格原文为空';
    } catch (failure) {
      return (failure as Error).message;
    }
  }

  private rowDescription(): string {
    const start: number = this.page.rowCount === 0 ? 0 : this.page.rowPage * MARKDOWN_READING_ROWS + 1;
    return '第 ' + start.toString() + '–' +
      Math.min(this.page.rowCount, (this.page.rowPage + 1) * MARKDOWN_READING_ROWS).toString() +
      ' 行 / 共 ' + this.page.rowCount.toString() + ' 行';
  }

  private columnDescription(): string {
    return '第 ' + (this.page.columnPage * MARKDOWN_READING_COLUMNS + 1).toString() + '–' +
      Math.min(this.page.columnCount, (this.page.columnPage + 1) * MARKDOWN_READING_COLUMNS).toString() +
      ' 列 / 共 ' + this.page.columnCount.toString() + ' 列';
  }

  @Builder
  TableControls() {
    // 只留翻页键 + 最短位置提示；翻页键 = 裸图标键（宪法图标键形制，与标题条三键同族）。
    // 未分页的轴不显示提示，两轴都未分页时整个控制区不占位（调用点守卫）。
    Column({ space: 6 }) {
      if (this.page.rowCount > MARKDOWN_READING_ROWS) {
        Row({ space: 4 }) {
          Text(this.rowDescription())
            .fontSize(12).lineHeight(18).fontColor(cardDescColor()).layoutWeight(1)
          Button() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(16).fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .accessibilityText('上一页')
          .enabled(this.page.rowPage > 0)
          .onClick((): void => { this.rowPage = Math.max(0, this.page.rowPage - 1); })
          Button() {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16).fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .accessibilityText('下一页')
          .enabled((this.page.rowPage + 1) * MARKDOWN_READING_ROWS < this.page.rowCount)
          .onClick((): void => { this.rowPage = this.page.rowPage + 1; })
        }
        .width('100%')
      }
      if (this.page.columnCount > MARKDOWN_READING_COLUMNS) {
        Row({ space: 4 }) {
          Text(this.columnDescription())
            .fontSize(12).lineHeight(18).fontColor(cardDescColor()).layoutWeight(1)
          Button() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(16).fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .accessibilityText('前列')
          .enabled(this.page.columnPage > 0)
          .onClick((): void => { this.columnPage = Math.max(0, this.page.columnPage - 1); })
          Button() {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16).fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .accessibilityText('后列')
          .enabled((this.page.columnPage + 1) * MARKDOWN_READING_COLUMNS < this.page.columnCount)
          .onClick((): void => { this.columnPage = this.page.columnPage + 1; })
        }
        .width('100%')
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start).padding(12)
  }

  @Builder
  Table() {
    if (this.page.error !== '') {
      Text(this.page.error)
        .fontSize(13).lineHeight(20).fontColor(cardDescColor()).width('100%').padding(12)
      Text(this.rawFallback())
        .fontSize(13).lineHeight(18).fontFamily(this.codeFontFamily).fontColor(cardTitleColor())
        .copyOption(CopyOptions.None).width('100%').padding(12)
    } else if (this.page.columnCount === 0) {
      Text('空表格，暂无列。仍可复制原文')
        .fontSize(MARKDOWN_BODY_FONT_SIZE).lineHeight(MARKDOWN_BODY_LINE_HEIGHT).fontColor(cardDescColor()).width('100%').padding(12)
    } else {
      if (this.page.rowCount > MARKDOWN_READING_ROWS || this.page.columnCount > MARKDOWN_READING_COLUMNS) {
        this.TableControls()
      }
      Scroll(this.scroller) {
        Column() {
          Repeat<number>(this.page.rowIndices)
            .each((row: RepeatItem<number>) => {
              MarkdownReadingRow({ node: this.node.children[this.page.rowIndices[row.index]],
                header: this.page.rowIndices[row.index] === 0, token: this.token, darkMode: this.darkMode,
                columns: this.page.columnIndices, alignments: this.node.alignments, source: this.source,
                referenceJump: this.referenceJump, anchorEnabled: this.anchorEnabled,
                live: this.live,
                bodyFontFamily: this.bodyFontFamily, codeFontFamily: this.codeFontFamily,
                onNavigate: (destination: string): void => { this.onNavigate(destination); } })
            })
            .key((index: number): string => this.node.children[index].id.toString())
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.TopStart)
      // 横滑回弹；滚动条统一隐藏（BarState.Off）
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
  }

  build() {
    Column() {
      if (this.node.kind === 'table') {
        this.Table()
      } else {
        Scroll(this.scroller) {
          if (this.node.kind === 'codeBlock') {
            MarkdownCodeText({ node: this.node, token: this.token, darkMode: this.darkMode,
              live: this.live, displayBudget: this.displayBudget, codeFontFamily: this.codeFontFamily })
          } else {
            Text(this.node.text !== '' ? this.node.text : '空源码')
              .fontSize(13).lineHeight(18).fontFamily(this.codeFontFamily).fontColor(cardTitleColor())
              .copyOption(CopyOptions.None).padding({ left: 12, right: 12, top: 10, bottom: 10 })
          }
        }
        .width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.TopStart)
        // 横滑回弹；滚动条统一隐藏（BarState.Off）
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start)
  }
}

@ComponentV2
struct MarkdownReadingRow {
  @Require @Param node: MarkdownNode;
  @Param source: string = '';
  @Require @Param token: MarkdownDocumentToken;
  @Param columns: number[] = [];
  @Param alignments: string[] = [];
  @Param header: boolean = false;
  @Param darkMode: boolean = false;
  @Event onNavigate: (destination: string) => void = (_destination: string): void => {};
  @Param referenceJump: MarkdownReferenceJump = { referenceId: 0, serial: 0 };
  @Param anchorEnabled: boolean = true;
  // 流式态标量：本行单元格内的行内公式提升判宽同受终态定格约束（流式在途不
  // 提升）；完整阅读半模态不传 = 非流式缺省。
  @Param live: boolean = false;
  // 消息字体家族串：只透传至单元格
  @Param bodyFontFamily: string = FONT_FAMILY_SYSTEM;
  @Param codeFontFamily: string = FONT_FAMILY_MONO;

  private mode(): number {
    return this.darkMode ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  }

  build() {
    Row() {
      Repeat<number>(this.columns)
        .each((column: RepeatItem<number>) => {
          MarkdownReadingCell({ node: this.node.children[this.columns[column.index]],
            token: this.token, darkMode: this.darkMode, header: this.header,
            alignment: this.alignments[this.columns[column.index]] ?? '', source: this.source,
            referenceJump: this.referenceJump, anchorEnabled: this.anchorEnabled,
            live: this.live,
            bodyFontFamily: this.bodyFontFamily, codeFontFamily: this.codeFontFamily,
            onNavigate: (destination: string): void => { this.onNavigate(destination); } })
        })
        .key((index: number): string => this.node.children[index].id.toString())
    }
    .alignItems(VerticalAlign.Top)
    .border({ width: { bottom: 0.5 }, color: cardBorderColor(this.mode()) })
    // 表头底色与表正文统一（真机反馈：badgeBg 灰头紧贴灰标题栏显灰面过大；表头仍靠加粗
    // 区分），内联与半模态同组件同改
    .backgroundColor(Color.Transparent)
  }
}

@ComponentV2
struct MarkdownReadingCell {
  @Require @Param node: MarkdownNode;
  @Param source: string = '';
  @Require @Param token: MarkdownDocumentToken;
  @Param darkMode: boolean = false;
  @Event onNavigate: (destination: string) => void = (_destination: string): void => {};
  @Param referenceJump: MarkdownReferenceJump = { referenceId: 0, serial: 0 };
  @Param anchorEnabled: boolean = true;
  @Param header: boolean = false;
  @Param alignment: string = '';
  // 流式态标量：同 MarkdownReadingRow——单元格内行内公式提升的终态定格判据
  @Param live: boolean = false;
  // 消息字体家族串：单元格正文段走正文字体、行内代码走代码字体
  @Param bodyFontFamily: string = FONT_FAMILY_SYSTEM;
  @Param codeFontFamily: string = FONT_FAMILY_MONO;
  @Local private part: number = 0;
  @Local private identity: string = '';

  aboutToAppear(): void { this.identity = contentIdentity(this.token, this.node); this.part = 0; this.jumpToReference(); }

  @Monitor('referenceJump')
  private jumpToReference(): void {
    if (this.referenceJump.referenceId > 0 && markdownHasNode([this.node], this.referenceJump.referenceId)) {
      this.part = markdownReadingCellWindow(this.node, 0, this.referenceJump.referenceId).page;
    }
  }

  @Monitor('node', 'token')
  private syncIdentity(): void {
    const identity: string = contentIdentity(this.token, this.node);
    if (identity !== this.identity) {
      this.identity = identity;
      this.part = 0;
    }
  }

  @Computed
  get window(): MarkdownReadingCellWindow {
    return markdownReadingCellWindow(this.node,
      contentIdentity(this.token, this.node) === this.identity ? this.part : 0);
  }

  private textAlignment(): TextAlign {
    return this.alignment === 'right' ? TextAlign.End : this.alignment === 'center' ? TextAlign.Center : TextAlign.Start;
  }

  build() {
    Column({ space: 6 }) {
      ForEach([contentIdentity(this.token, this.node) + '/' + this.window.page.toString()], (_identity: string) => {
        MarkdownInlineView({ nodes: this.window.nodes, source: this.source, token: this.token, darkMode: this.darkMode,
          bold: this.header, textAlign: this.textAlignment(), live: this.live,
          bodyFontFamily: this.bodyFontFamily, codeFontFamily: this.codeFontFamily,
          onNavigate: (destination: string): void => { this.onNavigate(destination); } })
      }, (identity: string): string => identity)
      if (this.window.page > 0 || this.window.hasNext) {
        Text('第 ' + (this.window.page + 1).toString() + ' 部分')
          .fontSize(12).lineHeight(18).fontColor(cardDescColor()).width('100%')
        // 翻部分键 = 裸图标键并排（与表格翻页键同族），两枚约 100vp 落在 160vp 列内容宽内；不累计渲染已看过的部分。
        Row({ space: 4 }) {
          Button() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(16).fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .accessibilityText('上一部分')
          .enabled(this.window.page > 0)
          .onClick((): void => { this.part = Math.max(0, this.window.page - 1); })
          Button() {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16).fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .accessibilityText('下一部分')
          .enabled(this.window.hasNext)
          .onClick((): void => { this.part = this.window.page + 1; })
        }
      }
    }
    .id(this.anchorEnabled ? markdownAnchorId(this.token, this.node.id) : undefined)
    .width(160).alignItems(HorizontalAlign.Start).padding({ left: 12, right: 12, top: 8, bottom: 8 })
  }
}

// 底部渐隐蒙层高（vp，★ 单源：蒙层与滚动尾占位同用「本值 + 底部安全区」，一处改两处同效；
// MessageCopySheet COPY_BOTTOM_FADE_HEIGHT 同款沉淀值 = 键带基高 64 + 26vp 渐隐余量）
const READING_BOTTOM_FADE_HEIGHT: number = 90;

/** 完整阅读半模态宿主（bindSheet 全屏单挡位）。短命会话宿主——父件 covers 一会话一条，
 *  本组件随会话挂载/卸载；旧关闭事件只携旧 session 与旧代际，不写新宿主的 isPresent。
 *  关闭链四件（规范-半模态 §1）：①可见性 $$ 双向；②onWillDismiss 放行后路由 requestClose
 *  单入口；③关闭恒不复位内容形态（只写可见性）；④关闭-再开协调 = 结构式——开意图只经
 *  父件「完整阅读」键与 openCover 早退，covers 常规清空口只有 onDisappear 上行 onClosed；
 *  非常规口（换代与锚点导航）直接整体销毁本宿主 ⇒ 动效在途期开意图结构性为零，无需
 *  pendingOpen/applyOpen 状态机。 */
@ComponentV2
export struct MarkdownReadingCover {
  @Require @Param node: MarkdownNode;
  @Require @Param token: MarkdownDocumentToken;
  @Require @Param session: string;
  @Param source: string = '';
  @Param darkMode: boolean = false;
  @Event onNavigate: (destination: string) => void = (_destination: string): void => {};
  @Param referenceJump: MarkdownReferenceJump = { referenceId: 0, serial: 0 };
  @Param anchorEnabled: boolean = true;
  @Param busy: boolean = false;
  // 消息字体家族串：完整阅读语义 = 消息内容的阅读视图，全跟随
  @Param bodyFontFamily: string = FONT_FAMILY_SYSTEM;
  @Param codeFontFamily: string = FONT_FAMILY_MONO;
  @Event onClosed: (session: string) => void = (_session: string): void => {};
  @Event onCopy: () => void = (): void => {};
  @Event onSave: () => void = (): void => {};
  // 半模态可见性（关闭链①：$$ 双向目标；全文件唯一写 true 落 aboutToAppear——宿主挂载即拉起）
  @Local private isPresent: boolean = false;
  // 底部系统导航条高（vp）：吸底键带底距 / 渐变蒙层高 / 滚动尾占位三处同源消费
  @Local private bottomInset: number = 0;
  private horizontal: Scroller = new Scroller();
  private vertical: Scroller = new Scroller();
  private alive: boolean = false;
  private lifecycle: number = 0;
  // 占位空选项（aboutToAppear 必先于 build 执行，真实选项在那里按本会话代际装配）
  private panelOptions: SheetOptions = {};

  aboutToAppear(): void {
    this.alive = true;
    const lifecycle: number = ++this.lifecycle;
    this.horizontal = new Scroller();
    this.vertical = new Scroller();
    this.loadBottomInset();
    this.panelOptions = sheetPanelOptions(
      (action: DismissSheetAction): void => {
        // 关闭链②：框架级关闭（下拉/蒙层/系统返回）经官方漏斗放行，再路由关闭单入口
        action.dismiss();
        if (this.alive && lifecycle === this.lifecycle) { this.requestClose(); }
      },
      DETENTS_FULL,
      undefined,
      (): void => {
        if (this.alive && lifecycle === this.lifecycle) { this.onSheetGone(); }
      });
    // 宿主挂载即拉起：父件置 covers 即开意图，本会话是新鲜宿主，无离场动效在途
    this.isPresent = true;
  }
  aboutToDisappear(): void { this.alive = false; this.lifecycle++; }

  private mode(): number {
    return this.darkMode ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  }

  // 标题栏材质档（V2 组件无 @StorageProp——弹出瞬间现读，KimiSheetCommon.overlayMaterial 同
  // 口径：面板打开期间档位不会变，无需订阅刷新）
  private titleLevel(): number {
    const level: number | undefined = AppStorage.get<number>(IMMERSIVE_LEVEL_KEY);
    return level === undefined ? 0 : level;
  }

  // 底部系统导航条高（Index.ets 同款：getLastWindow + 同步 getWindowAvoidArea + px2vp，系统区
  // 与手势条取大；读失败保持 0——键带回落 12vp 底距，面板仍可用）
  private loadBottomInset(): void {
    try {
      const ui: UIContext = this.getUIContext();
      const context: common.UIAbilityContext = ui.getHostContext() as common.UIAbilityContext;
      window.getLastWindow(context).then((win: window.Window): void => {
        if (!this.alive) { return; }
        const system: number = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).bottomRect.height;
        const indicator: number = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height;
        this.bottomInset = Math.max(ui.px2vp(system), ui.px2vp(indicator));
      }).catch((failure: Object): void => {
        hilog.error(0xD5A0, 'MarkdownReading', '读取底部避让区失败：%{public}s', (failure as Error).message);
      });
    } catch (failure) {
      hilog.error(0xD5A0, 'MarkdownReading', '底部避让区窗口不可达：%{public}s', (failure as Error).message);
    }
  }

  // 蒙层与滚动尾占位高（含底部安全区——键带底距让位同源值）
  private bottomFadeHeight(): number {
    return READING_BOTTOM_FADE_HEIGHT + this.bottomInset;
  }

  // 关闭单入口（规范-半模态 §1：标题栏 xmark 与 onWillDismiss 两路同调；纯阅读零暂存恒直关；
  // 关闭链③：只写可见性，不复位内容形态——内容树随关闭动画完整走完）
  private requestClose(): void {
    if (this.alive) { this.isPresent = false; }
  }

  // 关闭链④的动效结束执行点（sheetPanelOptions 第四参 onDisappear——d.ts「动画结束后回调」）：
  // 上行 onClosed，父件清 covers（卸载本宿主并放开「完整阅读」键）——下一次开只可能在此之后
  private onSheetGone(): void {
    this.onClosed(this.session);
  }

  @Builder
  Page() {
    HdsNavigation() {
      // 吸底键条层（规范-半模态 §2 第三条）：Stack 底对齐叠〔滚动区 + 底部渐变蒙层 + 键带〕
      Stack({ alignContent: Alignment.Bottom }) {
        Scroll(this.vertical) {
          Column() {
            MarkdownReadingContent({ node: this.node, token: this.token, source: this.source,
              darkMode: this.darkMode, scroller: this.horizontal, anchorEnabled: false,
              bodyFontFamily: this.bodyFontFamily, codeFontFamily: this.codeFontFamily,
              onNavigate: (destination: string): void => { this.onNavigate(destination); } })
              .width(CARD_PANEL_WIDTH)
            // 尾占位 = 蒙层高（含安全区，两处同源）：滚到底末行停在蒙层上方完整可见
            Row().height(this.bottomFadeHeight())
          }
          .width('100%').alignItems(HorizontalAlign.Center).padding({ top: 12 })
        }
        .width('100%').height('100%').align(Alignment.TopStart)
        .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        // 滚动内容穿透标题栏背后供 GRADIENT_BLUR 采样（规范-半模态 §2：缺省裁剪 = 模糊空转）
        .clip(false)

        // 底部渐变蒙层（上透下实 / 深浅分治 / 不拦滚动与长按选择）
        Column()
          .width('100%').height(this.bottomFadeHeight())
          .linearGradient({ angle: 180,
            colors: [[pageBgFade(this.mode()), 0], [$r('app.color.page_bg'), 1]] })
          .hitTestBehavior(HitTestMode.None)

        // 吸底键带（条透明——键自身 fallbackButton* 四件套承担实底/光感两态；Transparent =
        // 条面不阻断下层滚动）。双键各落包裹列 layoutWeight(1) 半宽 + stretch 满宽（width 挂
        // 自定义组件实例不进内部根节点——真机实锤，满宽由根 Button 承载）；键带宽
        // CARD_PANEL_WIDTH 与面板内容边对齐（MessageCopySheet 同款先例）。
        Column() {
          Row({ space: 12 }) {
            Column() {
              MarkdownReadingButton({ label: this.node.kind === 'table' ? '复制原文' : '复制',
                isEnabled: !this.busy, stretch: true, onAction: (): void => { this.onCopy(); } })
            }
            .layoutWeight(1)
            Column() {
              MarkdownReadingButton({ label: this.node.kind === 'table' ? '导出 CSV' : '保存 txt',
                isEnabled: !this.busy, stretch: true, onAction: (): void => { this.onSave(); } })
            }
            .layoutWeight(1)
          }
          .width(CARD_PANEL_WIDTH)
        }
        .width('100%').hitTestBehavior(HitTestMode.Transparent)
        .padding({ top: 12, bottom: this.bottomInset + 12 })
      }
      .width('100%').height('100%')
    }
    // 官方半模态标题形制（规范-半模态 §1：HdsNavigation MODAL 壳 + sheetTitleBarOptions 同源，
    // 勿自绘标题）；关闭键在标题栏（决明拍板）
    .titleBar(sheetTitleBarOptions(markdownReadingTitle(this.node), '',
      (): void => { this.requestClose(); }, this.titleLevel()))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.vertical])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }

  build() {
    Blank()
      .width(0).height(0)
      .bindSheet($$this.isPresent, this.Page(), this.panelOptions)
  }
}
