/**
 * 消息流 HTML 块的白名单投影渲染（最高危项，默认开）。
 * 输入 = MarkdownPreviewPolicy.markdownHtmlProjection 的有界结构（父件已判非空），本件零解析、
 * 零 Web、零脚本、无链接跳转面：结构标签直映原生组件——属性/URL/事件在投影期已不存在，
 * 纯同步渲染**无异步面**（无票据校验适用点）。
 * 流式域纪律：无状态幂等（同一入参恒同一树）、度量确定（全部定值常量，无测量依赖）；不设
 * 外层显式高度、块内纵向零滚动（表格与代码块只许横向 Scroll）。
 * 排印照 markdown 域既有件：正文 16/24 + 标题五级族；代码 13/18 与阅读面源码显示同档
 *（流式源码态与终态渲染态视觉连续）。键纪律：块级键 = 投影身份；文本段键覆盖文本 + 七个
 * 样式旗标（漏项即静默冻结）。
 */
import { ConfigurationConstant } from '@kit.AbilityKit';
import { MarkdownHtmlBlock, MarkdownHtmlRun, markdownHtmlHeadingLevel }
  from '../../../common/markdown/MarkdownPreviewPolicy';
import { MARKDOWN_BODY_FONT_SIZE, MARKDOWN_BODY_LINE_HEIGHT, markdownHeadingLineHeight,
  markdownHeadingSize } from '../../../common/markdown/MarkdownPresentation';
import { isCodeLineNumbersEnabled } from '../../../common/AppPreferences';
import { codeLineNumberText } from '../../../common/markdown/CodeLineNumbers';
import { badgeBg, cardBorderColor, cardDescColor, cardTitleColor, quoteBarColor, quoteBlockBg,
  usageAccentColor } from '../../../common/Theme';
import { FONT_FAMILY_MONO, FONT_FAMILY_SYSTEM } from '../../../common/ChatFont';

// ── 排印与几何常量（全部定值：度量确定，无测量依赖）──
const HTML_CODE_FONT_SIZE: number = 13;      // 与阅读面源码显示同档（MarkdownReadingContent 13/18）
const HTML_CODE_LINE_HEIGHT: number = 18;
const HTML_LIST_INDENT_VP: number = 16;      // 嵌套列表逐层附加缩进（定值×层级）
const HTML_TABLE_CELL_WIDTH: number = 160;   // 简表列宽（同 MarkdownReadingCell 定值）
const HTML_TABLE_CELL_PAD_VP: number = 12;
const HTML_TABLE_ROW_PAD_VP: number = 8;
const HTML_QUOTE_PAD_VP: number = 8;         // 引用块四向内距（同 message 引用块形制）
const HTML_QUOTE_BAR_VP: number = 3;

/** 块间距梯度：同 markdownBlockGap 语义（标题前 20 / 标题后 6 / 容器 18 / 列表项间 4 / 默认 6；
 *  分割线两侧让位 0——自带上下 margin 即总间距，防叠加翻倍）。
 *  ★ 默认段距与 MarkdownPresentation.markdownBlockGap 两处同语义单源，改一处必改另一处。 */
function htmlProjectionGap(node: MarkdownHtmlBlock, previous: MarkdownHtmlBlock | null): number {
  if (previous === null) { return 0; }
  if (node.tag === 'hr' || previous.tag === 'hr') { return 0; }
  if (markdownHtmlHeadingLevel(node.tag) > 0) { return 20; }
  if (markdownHtmlHeadingLevel(previous.tag) > 0) { return 6; }
  if (node.tag === 'pre' || node.tag === 'table' || node.tag === 'blockquote' ||
    previous.tag === 'pre' || previous.tag === 'table' || previous.tag === 'blockquote') { return 18; }
  if (node.tag === 'li' && previous.tag === 'li') { return 4; }
  return 6;
}

@ComponentV2
export struct MarkdownHtmlBlockView {
  @Require @Param nodes: MarkdownHtmlBlock[];
  @Param darkMode: boolean = false;
  // 消息字体家族串：投影文本走正文字体、投影 code 走代码字体
  @Param bodyFontFamily: string = FONT_FAMILY_SYSTEM;
  @Param codeFontFamily: string = FONT_FAMILY_MONO;

  build() {
    Column() {
      Repeat<number>(this.nodes.map((node: MarkdownHtmlBlock): number => node.id))
        .each((item: RepeatItem<number>) => {
          MarkdownHtmlProjectionNode({ node: this.nodes[item.index], darkMode: this.darkMode,
            bodyFontFamily: this.bodyFontFamily, codeFontFamily: this.codeFontFamily,
            gap: htmlProjectionGap(this.nodes[item.index],
              item.index > 0 ? this.nodes[item.index - 1] : null) })
        })
        .key((_id: number, index: number): string => this.nodes[index].id.toString())
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    // 内距与阅读面 htmlBlock 源码显示同档（左 12 / 上 10）：源码态与渲染态视觉连续
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
  }
}

@ComponentV2
struct MarkdownHtmlProjectionNode {
  @Require @Param node: MarkdownHtmlBlock;
  @Param darkMode: boolean = false;
  @Param gap: number = 0;
  // 消息字体家族串：只透传至文本段与嵌套子块
  @Param bodyFontFamily: string = FONT_FAMILY_SYSTEM;
  @Param codeFontFamily: string = FONT_FAMILY_MONO;

  private colorMode(): number {
    return this.darkMode ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  }

  private fontSize(): number {
    const level: number = markdownHtmlHeadingLevel(this.node.tag);
    return level > 0 ? markdownHeadingSize(level) : MARKDOWN_BODY_FONT_SIZE;
  }

  private lineHeight(): number {
    const level: number = markdownHtmlHeadingLevel(this.node.tag);
    return level > 0 ? markdownHeadingLineHeight(level) : MARKDOWN_BODY_LINE_HEIGHT;
  }

  private runKey(run: MarkdownHtmlRun, index: number): string {
    return index.toString() + ':' + (run.bold ? '1' : '0') + (run.italic ? '1' : '0') +
      (run.underline ? '1' : '0') + (run.strike ? '1' : '0') + (run.mark ? '1' : '0') +
      (run.code ? '1' : '0') + (run.link ? '1' : '0') + ':' + run.text;
  }

  // 代码块纯文本：只供 <pre> 行号列算行数，不参与 Runs 渲染。
  @Computed
  get codePlainText(): string {
    let text: string = '';
    for (const run of this.node.runs) {
      text += run.text;
    }
    return text;
  }

  // 文本段渲染：样式旗标 → Span 属性（与 MarkdownInlineView StyledSpan 同族形制：code 走
  // badgeBg 底 + monospace 且字号 −1，mark 走官方文本高亮色，link 只着色**无点击**——投影无
  // URL 面）。fillWidth：默认 true = 满宽；<pre> 传 false = 取内容固有宽度，长行交给外层
  // 横向 Scroll（行号列与代码同处滚动内容）。
  @Builder
  Runs(runs: MarkdownHtmlRun[], fontSize: number, lineHeight: number, bold: boolean, italic: boolean,
    fillWidth: boolean = true) {
    Text() {
      Repeat<string>(runs.map((run: MarkdownHtmlRun, index: number): string => this.runKey(run, index)))
        .each((row: RepeatItem<string>) => {
          Span(runs[row.index].text)
            .fontSize(runs[row.index].code ? fontSize - 1 : fontSize)
            .fontColor(runs[row.index].link ? usageAccentColor(this.colorMode()) : cardTitleColor())
            .fontWeight(bold || runs[row.index].bold ? FontWeight.Bold : FontWeight.Normal)
            .fontStyle(italic || runs[row.index].italic ? FontStyle.Italic : FontStyle.Normal)
            .fontFamily(runs[row.index].code ? this.codeFontFamily : this.bodyFontFamily)
            .decoration({ type: runs[row.index].strike ? TextDecorationType.LineThrough :
              runs[row.index].underline ? TextDecorationType.Underline : TextDecorationType.None })
            .textBackgroundStyle({ color: runs[row.index].code ? badgeBg(this.colorMode()) :
              runs[row.index].mark ? $r('sys.color.ohos_id_color_text_highlight_bg') : Color.Transparent })
        })
        .key((key: string): string => key)
    }
    .width(fillWidth ? '100%' : undefined).fontSize(fontSize).lineHeight(lineHeight)
    .fontColor(cardTitleColor()).fontFamily(this.bodyFontFamily)
  }

  @Builder
  Children() {
    Column() {
      Repeat<number>(this.node.children.map((child: MarkdownHtmlBlock): number => child.id))
        .each((item: RepeatItem<number>) => {
          MarkdownHtmlProjectionNode({ node: this.node.children[item.index], darkMode: this.darkMode,
            bodyFontFamily: this.bodyFontFamily, codeFontFamily: this.codeFontFamily,
            gap: htmlProjectionGap(this.node.children[item.index],
              item.index > 0 ? this.node.children[item.index - 1] : null) })
        })
        .key((_id: number, index: number): string => this.node.children[index].id.toString())
    }
    .width('100%').alignItems(HorizontalAlign.Start)
  }

  // 列表项：标记与缩进投影期定死（组件零推导）；行内文本与嵌套子块（嵌套列表/段落）共列。
  @Builder
  Item() {
    Row({ space: 8 }) {
      Text(this.node.marker)
        .fontSize(MARKDOWN_BODY_FONT_SIZE).lineHeight(MARKDOWN_BODY_LINE_HEIGHT)
        .fontColor(cardTitleColor()).constraintSize({ minWidth: 20 })
      Column() {
        if (this.node.runs.length > 0) {
          this.Runs(this.node.runs, MARKDOWN_BODY_FONT_SIZE, MARKDOWN_BODY_LINE_HEIGHT, false, false)
        }
        this.Children()
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
    }
    .width('100%').alignItems(VerticalAlign.Top)
    .padding({ left: this.node.indent * HTML_LIST_INDENT_VP })
  }

  // 引用块：形制同一级 Markdown 引用块（左条 + 底色 + 内距；内容斜体照 MarkdownInlineView quoted 口径）
  @Builder
  Quote() {
    Column() {
      if (this.node.runs.length > 0) {
        this.Runs(this.node.runs, MARKDOWN_BODY_FONT_SIZE, MARKDOWN_BODY_LINE_HEIGHT, false, true)
      }
      this.Children()
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    .padding(HTML_QUOTE_PAD_VP)
    .backgroundColor(quoteBlockBg(this.colorMode()))
    .border({ width: { left: HTML_QUOTE_BAR_VP }, color: quoteBarColor(this.colorMode()) })
  }

  // 代码块：横向 Scroll 承载（宪法红线：块内只许横向滚动；长行不折行、纵向恒定随块高）。
  // 左侧可选行号列，与代码同 lineHeight；Runs 传 fillWidth=false 取固有宽度，长行由外层
  // 横向 Scroll 承载，行号随代码一起移出视野（与阅读面 Markdown 代码块同形制）。
  @Builder
  Code() {
    Scroll() {
      Row({ space: 8 }) {
        if (isCodeLineNumbersEnabled() && this.codePlainText !== '') {
          Text(codeLineNumberText(this.codePlainText))
            .fontSize(HTML_CODE_FONT_SIZE).lineHeight(HTML_CODE_LINE_HEIGHT)
            .fontFamily(FONT_FAMILY_MONO).fontColor(cardDescColor()).opacity(0.4)
            .copyOption(CopyOptions.None)
        }
        this.Runs(this.node.runs, HTML_CODE_FONT_SIZE, HTML_CODE_LINE_HEIGHT, false, false, false)
      }
      .alignItems(VerticalAlign.Top)
    }
    .width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.TopStart)
    // 横滑回弹补齐：与阅读面原生代码块/表格同形制（Spring + alwaysEnabled）
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  // 简表（投影期已钉死范围）：行列原生拼装、统一左对齐、表头行加粗、行底线分隔；定宽单元格 +
  // 横向 Scroll（同阅读面表格形态），嵌套表在投影期已降级为文本。
  @Builder
  TableRow(row: MarkdownHtmlBlock) {
    Row() {
      Repeat<number>(row.cells.map((_cell: MarkdownHtmlRun[], index: number): number => index))
        .each((cell: RepeatItem<number>) => {
          Column() {
            this.Runs(row.cells[cell.index], MARKDOWN_BODY_FONT_SIZE, MARKDOWN_BODY_LINE_HEIGHT,
              row.header, false)
          }
          .width(HTML_TABLE_CELL_WIDTH).alignItems(HorizontalAlign.Start)
          .padding({ left: HTML_TABLE_CELL_PAD_VP, right: HTML_TABLE_CELL_PAD_VP,
            top: HTML_TABLE_ROW_PAD_VP, bottom: HTML_TABLE_ROW_PAD_VP })
        })
        // 单元格盒几何恒定（定宽定距），内容经 Runs 的 @Param 正道下发
        .key((_index: number, index: number): string => row.id.toString() + ':' + index.toString())
    }
    .alignItems(VerticalAlign.Top)
    .border({ width: { bottom: 0.5 }, color: cardBorderColor(this.colorMode()) })
  }

  @Builder
  Table() {
    Scroll() {
      Column() {
        Repeat<number>(this.node.children.map((row: MarkdownHtmlBlock): number => row.id))
          .each((item: RepeatItem<number>) => { this.TableRow(this.node.children[item.index]) })
          .key((_id: number, index: number): string => this.node.children[index].id.toString())
      }
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.TopStart)
    // 横滑回弹补齐：同投影代码块（Spring + alwaysEnabled）
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  build() {
    Column() {
      if (this.node.tag === 'hr') {
        Divider()
          .strokeWidth(0.5)
          .color(cardBorderColor(this.colorMode()))
          // 上下 16 对齐 Markdown 分割线同款；间距让位（gap = 0）见 htmlProjectionGap
          .margin({ top: 16, bottom: 16 })
      } else if (this.node.tag === 'table') {
        this.Table()
      } else if (this.node.tag === 'ul' || this.node.tag === 'ol') {
        this.Children()
      } else if (this.node.tag === 'li') {
        this.Item()
      } else if (this.node.tag === 'blockquote') {
        this.Quote()
      } else if (this.node.tag === 'pre') {
        this.Code()
      } else {
        // 段落 / 标题 / 顶层文本（text）：字级由标题级别派生，其余走正文常量
        Column() {
          if (this.node.runs.length > 0) {
            this.Runs(this.node.runs, this.fontSize(), this.lineHeight(), false, false)
          }
          this.Children()
        }
        .width('100%').alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    .padding({ top: this.gap })
  }
}
