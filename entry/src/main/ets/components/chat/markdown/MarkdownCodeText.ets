/**
 * 代码正文专用原生Text/Span。ReadingContent独占横滚、折叠与动作，本件不套滚动或Web。
 * @Computed仅依赖代码内容；单内容缓存承接语义快照换壳，主题只影响颜色，不解析正文AST。
 * 全量Repeat只承载至多1024个有界片段；不可变键只定位，载荷从当前结果按观察index读取。
 * 同步扫描无迟到回填任务；token只隔离文档/世代/节点的Span身份，revision不重建正文宿主。
 * diff 行级红绿：kind 含 addition/deletion/hunk/fileHeader，+/- 行字色固定不随主题、
 * 行底同色 12% 半透明。流式降载三档（见常量区）+ 非跳过档高亮耗时补采样。行号列 =
 * 可选显示层独立 Text（默认开，重进会话生效），不进 runs/node.text/复制导出，随外层横滚移动。
 */
import { ConfigurationConstant } from '@kit.AbilityKit';
import { MarkdownDocumentToken } from '../../../common/markdown/MarkdownDocumentModel';
import { MarkdownNode } from '../../../common/markdown/MarkdownSemanticModel';
import { MarkdownHighlightCache, MarkdownHighlightKind, MarkdownHighlightResult, MarkdownHighlightRun,
  MARKDOWN_HIGHLIGHT_MAX_UNITS, markdownHighlight } from '../../../common/markdown/MarkdownHighlight';
import { ChatDisplayBudget } from '../../../common/chat/ChatDisplayBudget';
import { isCodeLineNumbersEnabled } from '../../../common/AppPreferences';
import { codeLineNumberText } from '../../../common/markdown/CodeLineNumbers';
import { cardDescColor, cardTitleColor, usageAccentColor, DIFF_ADDITION_COLOR,
  DIFF_ADDITION_LINE_BG, DIFF_DELETION_COLOR, DIFF_DELETION_LINE_BG } from '../../../common/Theme';
import { FONT_FAMILY_MONO } from '../../../common/ChatFont';

// ── 流式降载三档（kel 三档语义，机制采信）──
// ①非流式（live 假）→ 恒全量高亮；②流式 + 未闭合 → 跳高亮（单 plain run 等宽无着色）；
// ③流式 + 已闭合 + 超长（行数或字符任一超档）→ 跳高亮（防闭合帧一次性全量上色尖峰）。
// 不抽搐论证：跳过档 Span 单 run，与高亮态同字体/字号/行高 ⇒ 恢复帧只有字色变化、无位变。
// 总开关常量（单源）：false 即回全量现状；判据件与超长代码块自动折叠同族落组件件，不下沉公共层。
export const MARKDOWN_STREAM_HIGHLIGHT_DEFER_ENABLED: boolean = true;
export const MARKDOWN_STREAM_HIGHLIGHT_SKIP_LINES: number = 300;
export const MARKDOWN_STREAM_HIGHLIGHT_SKIP_CHARS: number = 12288;

/** 行数是否超限（有界扫描：数到超限即返回，不做全量行数统计；口径同 markdownCodeLineCount
 *  ——尾终止符不另起一行，空文本 0 行）。 */
function markdownStreamLineOverflow(text: string, limit: number): boolean {
  if (limit <= 0) { return text.length > 0; }
  const separators: number = text.length > 0 && text.charCodeAt(text.length - 1) === 10 ? limit : limit - 1;
  let seen: number = 0;
  for (let index: number = 0; index < text.length; index++) {
    if (text.charCodeAt(index) !== 10) { continue; }
    seen++;
    if (seen > separators) { return true; }
  }
  return false;
}

/** 流式降载判定（无副作用，单独导出供断言直跑，照 shouldAutoCollapse 范式）：三档见上。 */
export function shouldDeferStreamingHighlight(live: boolean, closed: boolean, text: string): boolean {
  if (!MARKDOWN_STREAM_HIGHLIGHT_DEFER_ENABLED || !live) { return false; }
  if (!closed) { return true; }
  if (text.length > MARKDOWN_STREAM_HIGHLIGHT_SKIP_CHARS) { return true; }
  return markdownStreamLineOverflow(text, MARKDOWN_STREAM_HIGHLIGHT_SKIP_LINES);
}

/** 跳高亮态结果：单 plain run 覆盖全文、零提示语（与无语言「按纯源码显示」降级提示区分——
 *  那是有话要说的降级，本态是刻意的零着色）。 */
function markdownPlainHighlightResult(source: string, language: string): MarkdownHighlightResult {
  const runs: MarkdownHighlightRun[] = [];
  if (source.length > 0) { runs.push({ start: 0, end: source.length, text: source, kind: 'plain' }); }
  return { runs: runs, language: language, status: 'plain', message: '', readUnits: 0 };
}

@ComponentV2
export struct MarkdownCodeText {
  @Require @Param node: MarkdownNode;
  @Require @Param token: MarkdownDocumentToken;
  @Param darkMode: boolean = false;
  // 代码字体家族串：代码正文整体走代码字体（默认 = 通用等宽零变化）
  @Param codeFontFamily: string = FONT_FAMILY_MONO;
  // 流式态标量：live = 本行仍在流式输出（单源 = ChatMarkdownBody 入参，
  // 沿正文链下行）；缺省 false = 非流式（历史回放/完整阅读半模态/预览旁路），恒全量高亮。
  @Param live: boolean = false;
  // 显示成本预算（补采样通道）：仅实时正文链传入（同 live 条件），build 期高亮耗时
  // 经其并入当拍成本反馈；旁路消费点缺省 undefined = 零采样零行为。
  @Param displayBudget: ChatDisplayBudget | undefined = undefined;
  private highlightCache: MarkdownHighlightCache = new MarkdownHighlightCache();

  // 流式降载三档（判据单源 = 本件 shouldDeferStreamingHighlight）：跳过档返回单 plain run
  //（等宽无着色、零提示语），遮住全块重扫与多 Span 物化；终态与历史回放恒走全量高亮。
  // 降载期不写 highlightCache（恢复帧首扫即全量，无中间态残留）。补采样：非跳过档实测本拍
  // 高亮耗时（含缓存命中的零耗时）回报当拍预算。
  @Computed
  get highlighting(): MarkdownHighlightResult {
    if (shouldDeferStreamingHighlight(this.live, this.node.closed === true, this.node.text)) {
      // 超字符上限档与全量路径同结论（长度前置早退、零扫描、单 plain run）：返回同一条
      //「代码较长」提示结果，防提示行在流式态与终态之间出现/消失（行高跳变，红线不许）。
      // 其余跳过档 = 零提示单 plain run（终态恢复着色时只有字色变化）。
      return this.node.text.length > MARKDOWN_HIGHLIGHT_MAX_UNITS ?
        markdownHighlight(this.node.text, this.node.language) :
        markdownPlainHighlightResult(this.node.text, this.node.language);
    }
    const budget: ChatDisplayBudget | undefined = this.live ? this.displayBudget : undefined;
    if (budget === undefined) {
      return this.highlightCache.read(this.node.text, this.node.language);
    }
    const started: number = Date.now();
    const result: MarkdownHighlightResult = this.highlightCache.read(this.node.text, this.node.language);
    budget.recordBuildCost(Date.now() - started, Date.now());
    return result;
  }

  aboutToDisappear(): void { this.highlightCache.clear(); }

  private runKey(run: MarkdownHighlightRun): string {
    return this.token.documentId.length.toString() + ':' + this.token.documentId + ':' +
      this.token.generation.toString() + ':' + this.node.id.toString() + ':' + run.start.toString();
  }

  // Atom One Dark/Light 代码色板（15 槽全表与 kind→槽分派唯一依据 =
  // docs/调研-HTML修复与渲染美化取证合成-20261014.md §4.1，逐字抄录自 RIK CodeColor.kt）：
  // plain→fallback、keyword→keyword、type→number（One Dark 语义中类型词为暖金色，函数蓝
  // 属 title/function 族，我方 kind 无函数名类）、string→string、comment→comment、
  // number→number、property→property、tag→tag。
  // diff 四类（配色 RIK 缺省钉死，上收 Theme 常量）：+/- 行固定色不随主题；@@ hunk 行 =
  // 强调蓝；+++/--- 文件头行 = 次级灰 cardDescColor。
  private runColor(kind: MarkdownHighlightKind): ResourceColor {
    switch (kind) {
      case 'plain': return this.darkMode ? '#ABB2BF' : '#383A42';
      case 'keyword': return this.darkMode ? '#C678DD' : '#A626A4';
      case 'type': return this.darkMode ? '#D19A66' : '#C18401';
      case 'string': return this.darkMode ? '#98C379' : '#50A14F';
      case 'comment': return this.darkMode ? '#5C6370' : '#9CA0A4';
      case 'number': return this.darkMode ? '#D19A66' : '#C18401';
      case 'property': return this.darkMode ? '#E06C75' : '#E45649';
      case 'tag': return this.darkMode ? '#E06C75' : '#E45649';
      case 'addition': return DIFF_ADDITION_COLOR;
      case 'deletion': return DIFF_DELETION_COLOR;
      case 'hunk': return usageAccentColor(this.colorMode());
      case 'fileHeader': return cardDescColor();
      default: return cardTitleColor();
    }
  }

  private colorMode(): number {
    return this.darkMode ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  }

  /** diff 行底：+/- 行同色 12% 半透明（Theme.DIFF_*_LINE_BG）；其余 kind 无行底，
   *  返回全透明 ARGB 字面量（与 Color.Transparent 等价）。 */
  private diffLineBackground(kind: MarkdownHighlightKind): ResourceColor {
    switch (kind) {
      case 'addition': return DIFF_ADDITION_LINE_BG;
      case 'deletion': return DIFF_DELETION_LINE_BG;
      default: return '#00000000';
    }
  }

  // 行号列：固定等宽字体 + 不换行空格补齐，行高与代码完全一致；只读展示 copyOption(None)
  //——复制/保存仍走 node.text（本件不把行号写回任何业务载荷）。
  @Builder
  LineNumberGutter() {
    Text(codeLineNumberText(this.node.text))
      .fontSize(13).lineHeight(18).fontFamily(FONT_FAMILY_MONO)
      .fontColor(cardDescColor()).opacity(0.4).copyOption(CopyOptions.None)
  }

  build() {
    Column({ space: 6 }) {
      if (this.highlighting.message !== '') {
        // 提示独立于源码Text，不污染词法片段，也不进入宿主的复制/导出原文。
        Text(this.highlighting.message)
          .fontSize(12).lineHeight(18).fontColor(cardDescColor()).copyOption(CopyOptions.None)
      }
      if (this.node.text === '') {
        Text('空源码')
          .fontSize(13).lineHeight(18).fontFamily(this.codeFontFamily).fontColor(cardTitleColor())
          .copyOption(CopyOptions.None)
      } else {
        Row({ space: 8 }) {
          if (isCodeLineNumbersEnabled()) {
            this.LineNumberGutter()
          }
          Text() {
            Repeat<string>(this.highlighting.runs.map((run: MarkdownHighlightRun): string => this.runKey(run)))
              .each((row: RepeatItem<string>) => {
                Span(this.highlighting.runs[row.index].text)
                  .fontColor(this.runColor(this.highlighting.runs[row.index].kind))
                  .textBackgroundStyle({ color: this.diffLineBackground(this.highlighting.runs[row.index].kind) })
              })
              .key((key: string): string => key)
          }
          .fontSize(13).lineHeight(18).fontFamily(this.codeFontFamily).fontColor(cardTitleColor())
          .copyOption(CopyOptions.None)
        }
        .alignItems(VerticalAlign.Top)
      }
    }
    .alignItems(HorizontalAlign.Start).padding({ left: 12, right: 12, top: 10, bottom: 10 })
  }
}
