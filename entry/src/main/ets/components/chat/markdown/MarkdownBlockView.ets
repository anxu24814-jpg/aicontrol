/**
 * 语义块分派与阅读节奏。全量 Repeat 只携稳定 ID，载荷从当前数组按受观察的 index 读取。
 * 代码/表格资源由独立阅读表面持有；本件不参与消息纵向滚动或文本揭示。
 */
import { ConfigurationConstant } from '@kit.AbilityKit';
import { UIUtils } from '@kit.ArkUI';
import { MarkdownDocumentToken, MarkdownEndReason } from '../../../common/markdown/MarkdownDocumentModel';
import { MarkdownHeadingEntry, MarkdownNode } from '../../../common/markdown/MarkdownSemanticModel';
import { markdownNodeText } from '../../../common/markdown/MarkdownRenderProjection';
import { MARKDOWN_BODY_FONT_SIZE, MARKDOWN_BODY_LINE_HEIGHT, MARKDOWN_QUOTE_MAX_VISUAL_DEPTH,
  MARKDOWN_QUOTE_MERGED_MARK_WIDTH, markdownBlockGap,
  markdownHeadingSize, markdownHeadingLineHeight }
  from '../../../common/markdown/MarkdownPresentation';
import { cardBorderColor, cardDescColor, cardTitleColor, quoteBarColor, quoteBlockBg,
  usageAccentColor, usageIconBg } from '../../../common/Theme';
import { ChatDisplayBudget } from '../../../common/chat/ChatDisplayBudget';
import { FONT_FAMILY_MONO, FONT_FAMILY_SYSTEM } from '../../../common/ChatFont';
// DS 来源角标区间类型（S3③ 最小穿透——只透传类型与值，本件不判读）
import { DsCitationSpan } from '../ChatMessageCompose';
import { MarkdownInlineView } from './MarkdownInlineView';
import { MarkdownMath } from './MarkdownMath';
import { MarkdownScrollableBlock } from './MarkdownScrollableBlock';
import { MarkdownAnchorEntry, MarkdownReferenceJump, markdownAnchorId, markdownFootnoteDestination, markdownFootnoteNumber }
  from '../../../common/markdown/MarkdownNavigation';

// ── 入场动画参数族 ──
// 机制不动（enteringIds → entering → 一次性属性动画），只强化参数：旧值未达观感阈值，
// 新块被感知为「瞬时跳变出现」。观感不达标只在三常量上单点调，不改机制。
const ENTRY_OPACITY_FROM: number = 0.5;  // 入场透明度起点（调参域 0.4~0.6）
const ENTRY_DURATION_MS: number = 200;   // 入场时长：120ms 低于观感阈值
const ENTRY_OFFSET_Y_VP: number = 6;     // 入场向下偏移起点 vp（调参域 4~8）；translate 为渲染
                                        // 域属性，不触布局、不触发重排

// ── 特殊块形制常量族（形制 = RIK 换算）──
// 任务框自绘（甲式，天然不可点——RIK/KEL 先例均无交互）：边长 = 正文字号×0.8 + 2vp 内距×2、
// 2vp 圆角 + primary 10% 底、勾态 Tick 符号 primary 填满内框。全部由排印常量推导不含运行期
// 变量——定尺寸占位，尾段每拍重渲染几何恒定，不构成重排抽搐面。
const TASK_CHECK_SIDE_VP: number = Math.round(MARKDOWN_BODY_FONT_SIZE * 0.8) + 4;
const TASK_CHECK_ICON_FP: number = Math.round(MARKDOWN_BODY_FONT_SIZE * 0.8);
// 沿行高垂直居中补偿：正文 Text 行高 24、任务框 17，顶对齐下补差半值使框心对齐首行字心
const TASK_CHECK_TOP_VP: number = (MARKDOWN_BODY_LINE_HEIGHT - TASK_CHECK_SIDE_VP) / 2;
// 无序列表三级符号按嵌套层级循环（RIK •/◦/▪）；层级深度经 @Param depth 通道自 Children 下行
const LIST_BULLET_MARKS: string[] = ['•', '◦', '▪'];
// 嵌套列表逐层附加左缩进（RIK 缩进层级×8dp；层级自然缩进 = 标记列 20 + 行距 8，本值为加性）
const LIST_NEST_INDENT_VP: number = 8;

function blockNamespace(token: MarkdownDocumentToken, node: MarkdownNode): string {
  return token.documentId.length.toString() + ':' + token.documentId + ':' +
    token.generation.toString() + ':' + node.id.toString();
}

function readableBlockFallback(node: MarkdownNode): string {
  const value: string = markdownNodeText(node);
  return value !== '' ? value : '未能显示此内容 ' + node.kind;
}

@ComponentV2
export struct MarkdownBlockView {
  @Require @Param node: MarkdownNode;
  @Param index: number = 0;
  @Require @Param token: MarkdownDocumentToken;
  @Param source: string = '';
  @Param headingEntries: MarkdownHeadingEntry[] = [];
  @Param darkMode: boolean = false;
  @Param gap: number = 0;
  @Param quoted: boolean = false;
  // quoteDepth = 祖先引用层数（顶层 0，与列表 depth 分域）：引用块三层视觉封顶消费——
  // 第 1~3 层画条/底/内距，第 4 层起并入第 3 层框（只首行前置 ⋯，不再加深、不再收窄）
  @Param quoteDepth: number = 0;
  // depth = 列表嵌套层级（顶层 0）：无序符号三级循环与逐层附加缩进消费
  @Param depth: number = 0;
  // taskDone = 处于已勾选任务项的内容树内（quoted 同款下行旗标）：行内删除线 + 0.75 不透明度
  @Param taskDone: boolean = false;
  @Param listStart: number = 1;
  @Param listOrdered: boolean = false;
  @Param tight: boolean = false;
  @Param entering: boolean = false;
  @Param motionEnabled: boolean = false;
  @Param aiContent: boolean = true;
  @Param compact: boolean = false;
  // 流式态标量：随正文链整树下行（子块与资源壳同值继承），只透传不判读；
  // 缺省 = 非流式。
  @Param live: boolean = false;
  // 显示成本预算：随同一链整树下行至 MarkdownCodeText 补采样；只透传
  //（缺省 undefined = 不采样）。
  @Param displayBudget: ChatDisplayBudget | undefined = undefined;
  @Param anchors: MarkdownAnchorEntry[] = [];
  @Param referenceJump: MarkdownReferenceJump = { referenceId: 0, serial: 0 };
  // 文档级终态（自动折叠消费，随快照 endReason 下行）：只透传给资源壳，本件不判读。
  @Param bodyEndReason: MarkdownEndReason | undefined = undefined;
  // DS 来源角标（S3③ 最小穿透，缺省空数组零行为变化）：随正文链下传至行内视图；本件
  // 不判读（白名单缺口登记——S3 施工面按行内视图最小穿透处置，笔记与交付回复申报）
  @Param citations: DsCitationSpan[] = [];
  // 消息字体家族串：随正文链下行透传——块内文本类（段落/兜底原文/列表标记/目录/脚注）取
  // 正文字体，等宽类（代码/表格壳与各壳标题条）取代码字体；块级公式兜底源码改走等宽
  //（见 MarkdownMath 兜底分支）
  @Param bodyFontFamily: string = FONT_FAMILY_SYSTEM;
  @Param codeFontFamily: string = FONT_FAMILY_MONO;
  // 文档尾块标记（HTML 投影护栏）：顶层由 MarkdownDocumentView 按「最后一个可见
  // 节点」判定，子树整树继承（父块在尾 = 其子块文本也可能在增长）；本件只透传不判读。
  @Param documentTail: boolean = false;
  @Event onNavigate: (destination: string) => void = (_destination: string): void => {};
  // 角标点击上行（S3③ 最小穿透——行内视图直发，不进 navigate 文档内锚点解析）
  @Event onCitationTap: (entry: number) => void = (_entry: number): void => {};
  @Local private entryOpacity: number = 1;
  // 入场浮入位移，与 entryOpacity 同生命周期（aboutToAppear 起值 / 身份变化归零 / revealEntry 落位归零）
  @Local private entryOffsetY: number = 0;
  private entryIdentity: string = '';
  private entryPending: boolean = false;
  private entryMotionEnabled: boolean = false;
  private alive: boolean = false;

  aboutToAppear(): void {
    this.alive = true;
    this.entryIdentity = blockNamespace(this.token, this.node);
    this.entryPending = this.entering && this.motionEnabled;
    this.entryMotionEnabled = this.motionEnabled;
    this.entryOpacity = this.entryPending ? ENTRY_OPACITY_FROM : 1;
    this.entryOffsetY = this.entryPending ? ENTRY_OFFSET_Y_VP : 0;
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.entryPending = false;
  }

  @Monitor('node', 'token', 'motionEnabled')
  private onEntryBinding(): void {
    const identity: string = blockNamespace(this.token, this.node);
    if (!this.alive) {
      return;
    }
    const needsReset: boolean = identity !== this.entryIdentity ||
      (this.entryMotionEnabled && !this.motionEnabled);
    this.entryMotionEnabled = this.motionEnabled;
    if (!needsReset) {
      return;
    }
    this.entryIdentity = identity;
    this.entryPending = false;
    this.getUIContext().animateTo({ duration: 0 }, (): void => {
      // 归零链同事务重置透明度与位移两值，保持两属性同生命周期
      UIUtils.applySync((): void => { this.entryOpacity = 1; this.entryOffsetY = 0; });
    });
  }

  private revealEntry(): void {
    if (!this.alive || !this.entryPending) {
      return;
    }
    const animate: boolean = this.motionEnabled && this.entryIdentity === blockNamespace(this.token, this.node);
    this.entryPending = false;
    // Column 中不依赖 Repeat 的插入转场；只对已挂载根的 opacity/位移做一次属性动画。
    // 时长走常量；animate 为 false（减弱动效或身份不匹配）时 0ms 同事务覆盖两属性即位。
    this.getUIContext().animateTo({ duration: animate ? ENTRY_DURATION_MS : 0, curve: Curve.EaseOut }, (): void => {
      UIUtils.applySync((): void => { this.entryOpacity = 1; this.entryOffsetY = 0; });
    });
  }

  private colorMode(): number {
    return this.darkMode ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  }

  private itemMarker(): string {
    if (this.listOrdered) {
      return (this.listStart + this.index).toString() + '.';
    }
    // 任务项不再走文本标记（自绘任务框分支承载），无序按层级取三级符号循环
    return LIST_BULLET_MARKS[this.depth % LIST_BULLET_MARKS.length];
  }

  // 本引用块的视觉层级（最外层 = 1）：三层封顶与第 4 层 ⋯ 判据同源
  private quoteLevel(): number {
    return this.quoteDepth + 1;
  }

  @Computed
  get children(): MarkdownNode[] {
    return this.node.children.filter((child: MarkdownNode): boolean =>
      child.kind !== 'blank' && child.kind !== 'referenceDefinition');
  }

  private childGap(index: number): number {
    return markdownBlockGap(this.children[index], index > 0 ? this.children[index - 1] : null,
      this.node.kind === 'list' ? this.node.tight : this.tight);
  }

  @Builder
  Children() {
    Column() {
      Repeat<number>(this.children.map((node: MarkdownNode): number => node.id))
        .each((child: RepeatItem<number>) => {
          MarkdownBlockView({
            node: this.children[child.index],
            index: child.index,
            token: this.token,
            source: this.source,
            headingEntries: this.headingEntries,
            darkMode: this.darkMode,
            gap: this.childGap(child.index),
            quoted: this.quoted || this.node.kind === 'blockquote',
            // 引用层数只随 blockquote 增；列表/其它容器原样透传（第 4 层起封顶判据）
            quoteDepth: this.quoteDepth + (this.node.kind === 'blockquote' ? 1 : 0),
            depth: this.node.kind === 'listItem' ? this.depth + 1 : this.depth,
            taskDone: this.taskDone || (this.node.kind === 'listItem' && this.node.checked === true),
            listStart: this.node.startNumber,
            listOrdered: this.node.ordered,
            tight: this.node.kind === 'list' ? this.node.tight : this.tight,
            aiContent: this.aiContent, anchors: this.anchors, referenceJump: this.referenceJump,
            bodyEndReason: this.bodyEndReason,
            documentTail: this.documentTail,
            live: this.live,
            displayBudget: this.displayBudget,
            citations: this.citations,
            bodyFontFamily: this.bodyFontFamily, codeFontFamily: this.codeFontFamily,
            onNavigate: (destination: string): void => { this.onNavigate(destination); },
            onCitationTap: (entry: number): void => { this.onCitationTap(entry); }
          })
            .transition(TransitionEffect.IDENTITY)
        })
        .key((_id: number, index: number): string => blockNamespace(this.token, this.children[index]))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  Fallback() {
    Text(readableBlockFallback(this.node))
      .fontSize(MARKDOWN_BODY_FONT_SIZE)
      .lineHeight(MARKDOWN_BODY_LINE_HEIGHT)
      .fontColor(cardTitleColor())
      .fontFamily(this.bodyFontFamily)
      .copyOption(CopyOptions.None)
      .width('100%')
  }

  build() {
    Column() {
      if (this.node.kind === 'paragraph' || this.node.kind === 'heading' ||
        this.node.kind === 'tableCell') {
        if (this.node.children.length > 0) {
          MarkdownInlineView({
            nodes: this.node.children,
            source: this.source,
            compact: this.compact,
            token: this.token,
            darkMode: this.darkMode,
            fontSize: this.node.kind === 'heading' ? markdownHeadingSize(this.node.level) : MARKDOWN_BODY_FONT_SIZE,
            lineHeight: this.node.kind === 'heading' ? markdownHeadingLineHeight(this.node.level) : MARKDOWN_BODY_LINE_HEIGHT,
            bold: this.node.kind === 'heading',
            quoted: this.quoted,
            taskDone: this.taskDone,
            // 流式态：行内超宽公式提升的终态定格判据——流式在途不提升（防抽搐）
            live: this.live,
            citations: this.citations,
            bodyFontFamily: this.bodyFontFamily,
            codeFontFamily: this.codeFontFamily,
            onNavigate: (destination: string): void => { this.onNavigate(destination); },
            onCitationTap: (entry: number): void => { this.onCitationTap(entry); }
          })
        } else if (this.node.text === '') {
          Text('')
            .fontSize(MARKDOWN_BODY_FONT_SIZE)
            .lineHeight(MARKDOWN_BODY_LINE_HEIGHT)
        } else {
          this.Fallback()
        }
      } else if (this.node.kind === 'thematicBreak') {
        Divider()
          .strokeWidth(0.5)
          .color(cardBorderColor(this.colorMode()))
          // 上下 16 对齐 RIK；markdownBlockGap 已对分割线两侧让位为 0，此 margin 即总间距，不叠加。
          .margin({ top: 16, bottom: 16 })
      } else if (this.node.kind === 'blockquote') {
        // 引用块三层视觉封顶：level 1~3 照常画条/底/内距；level 4 起不再新增视觉层——底色
        // 不叠、条不叠、左右 19vp 不再重复扣，正文宽度从第三层起恒定。level 4 首行前置一个
        // ⋯（固定 14vp 列、不另起行），level 5+ 静默并入。真实嵌套层数仍在语义树里，斜体
        //（quoted）继续下行，引用语义不丢。
        if (this.quoteLevel() <= MARKDOWN_QUOTE_MAX_VISUAL_DEPTH) {
          Column() {
            if (this.children.length > 0) {
              this.Children()
            } else {
              Text('>')
                .fontSize(MARKDOWN_BODY_FONT_SIZE)
                .lineHeight(MARKDOWN_BODY_LINE_HEIGHT)
                .fontColor(cardDescColor())
                .fontFamily(this.bodyFontFamily)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          // 引用块几何（RIK 换算）：左条 3vp + 四向内距 8dp；底色与左条走 Theme 双函数
          //（常量级底层底色，不做上层叠层——裁定免触控面与压字两面）
          .padding({ left: 8, right: 8, top: 8, bottom: 8 })
          .backgroundColor(quoteBlockBg(this.colorMode()))
          .border({ width: { left: 3 }, color: quoteBarColor(this.colorMode()) })
        } else if (this.quoteLevel() === MARKDOWN_QUOTE_MAX_VISUAL_DEPTH + 1) {
          Row() {
            Text('⋯')
              .fontSize(MARKDOWN_BODY_FONT_SIZE)
              .lineHeight(MARKDOWN_BODY_LINE_HEIGHT)
              .fontColor(cardDescColor())
              .fontFamily(this.bodyFontFamily)
              .copyOption(CopyOptions.None)
              .width(MARKDOWN_QUOTE_MERGED_MARK_WIDTH)
            Column() {
              if (this.children.length > 0) {
                this.Children()
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        } else {
          this.Children()
        }
      } else if (this.node.kind === 'list') {
        if (this.children.length > 0) {
          this.Children()
        } else {
          this.Fallback()
        }
      } else if (this.node.kind === 'listItem') {
        Row({ space: 8 }) {
          if (this.node.checked !== undefined) {
            // 任务框自绘（甲式）：定尺寸（常量族注释）；无 onClick 天然不可点（RIK/KEL 先例）；
            // justifyContent Center = 勾在框内垂直居中（Column 主轴默认 Start 贴顶——2026-11-02 修复勾偏高）
            Column() {
              if (this.node.checked) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(TASK_CHECK_ICON_FP)
                  .fontColor([usageAccentColor(this.colorMode())])
              }
            }
            .width(TASK_CHECK_SIDE_VP)
            .height(TASK_CHECK_SIDE_VP)
            .borderRadius(2)
            .backgroundColor(usageIconBg(this.colorMode()))
            .justifyContent(FlexAlign.Center)
            .margin({ top: TASK_CHECK_TOP_VP })
          } else {
            Text(this.itemMarker())
              .fontSize(MARKDOWN_BODY_FONT_SIZE)
              .lineHeight(MARKDOWN_BODY_LINE_HEIGHT)
              .fontColor(cardTitleColor())
              .fontFamily(this.bodyFontFamily)
              .constraintSize({ minWidth: 20 })
          }
          Column() {
            if (this.children.length > 0) {
              this.Children()
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        // 嵌套逐层附加左缩进（顶层 0 = 无附加；缩进量 = 常量×层级，布局确定性）
        .padding({ left: this.depth * LIST_NEST_INDENT_VP })
      } else if (this.node.kind === 'footnoteDefinition') {
        Column({ space: 4 }) {
          Text('[' + markdownFootnoteNumber(this.anchors, this.node.label).toString() + '] ' + this.node.label)
            .fontSize(13)
            .fontColor(cardDescColor())
            .fontFamily(this.bodyFontFamily)
          Text('返回引用')
            .fontSize(13)
            .fontColor($r('sys.color.ohos_id_color_emphasize'))
            .fontFamily(this.bodyFontFamily)
            .onClick((): void => { this.onNavigate('back:' + markdownFootnoteDestination(this.node.label)); })
          if (this.children.length > 0) {
            this.Children()
          } else if (this.node.text !== '') {
            this.Fallback()
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      } else if (this.node.kind === 'toc') {
        Column({ space: 4 }) {
          Text('目录')
            .fontSize(MARKDOWN_BODY_FONT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .fontFamily(this.bodyFontFamily)
          if (this.headingEntries.length === 0) {
            Text('暂无标题')
              .fontSize(13)
              .fontColor(cardDescColor())
          } else {
            // toc.children 为空，目录只读共享 outline，不克隆标题树。
            Repeat<number>(this.headingEntries.map((heading: MarkdownHeadingEntry): number => heading.nodeId))
              .each((heading: RepeatItem<number>) => {
                Text(this.headingEntries[heading.index].text !== '' ? this.headingEntries[heading.index].text : this.headingEntries[heading.index].headingId)
                  .fontSize(MARKDOWN_BODY_FONT_SIZE)
                  .lineHeight(MARKDOWN_BODY_LINE_HEIGHT)
                  .fontColor(cardTitleColor())
                  .fontFamily(this.bodyFontFamily)
                  .padding({ left: Math.max(0, this.headingEntries[heading.index].level - 1) * 10 })
                  .width('100%')
                  .onClick((): void => { this.onNavigate('node:' + this.headingEntries[heading.index].nodeId.toString()); })
              })
              .key((nodeId: number): string => nodeId.toString())
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      } else if (this.node.kind === 'mathBlock') {
        // 块级公式去壳（总指挥裁定）：渲染态与兜底态均脱离 MarkdownScrollableBlock 阅读壳，
        // 横滚/状态行/源码兜底全部由 MarkdownMath 自持。身份包裹沿用 blockNamespace
        //（不含 revision——修订不进键，跨键复用时资源 owner 按 node/token 重建，防串语义）。
        ForEach([blockNamespace(this.token, this.node)], (_identity: string) => {
          MarkdownMath({ node: this.node, token: this.token, darkMode: this.darkMode,
            codeFontFamily: this.codeFontFamily })
            .transition(TransitionEffect.IDENTITY)
        }, (identity: string): string => identity)
      } else if (this.node.kind === 'codeBlock' ||
        this.node.kind === 'htmlBlock' || this.node.kind === 'table') {
        // 全量 Repeat 可能跨键复用外层，资源壳须按当前 node/token 重建，修订不进键。
        ForEach([blockNamespace(this.token, this.node)], (_identity: string) => {
          MarkdownScrollableBlock({ node: this.node, token: this.token, source: this.source,
            darkMode: this.darkMode, aiContent: this.aiContent, referenceJump: this.referenceJump,
            bodyEndReason: this.bodyEndReason,
            documentTail: this.documentTail,
            live: this.live,
            displayBudget: this.displayBudget,
            bodyFontFamily: this.bodyFontFamily, codeFontFamily: this.codeFontFamily,
            onNavigate: (destination: string): void => { this.onNavigate(destination); } })
            .transition(TransitionEffect.IDENTITY)
        }, (identity: string): string => identity)
      } else if (this.node.kind === 'blank' || this.node.kind === 'referenceDefinition') {
        // 非显示语法不产生占位。
      } else if (this.node.kind === 'tableRow') {
        this.Children()
      } else if (this.node.kind === 'text' || this.node.kind === 'emphasis' ||
        this.node.kind === 'strong' || this.node.kind === 'strikethrough' ||
        this.node.kind === 'highlight' ||
        this.node.kind === 'code' || this.node.kind === 'softBreak' ||
        this.node.kind === 'hardBreak' || this.node.kind === 'link' ||
        this.node.kind === 'image' || this.node.kind === 'math' ||
        this.node.kind === 'subscript' || this.node.kind === 'superscript' ||
        this.node.kind === 'footnoteReference' || this.node.kind === 'htmlInline') {
        MarkdownInlineView({ nodes: [this.node], source: this.source, token: this.token, darkMode: this.darkMode,
          quoted: this.quoted, taskDone: this.taskDone, live: this.live,
          citations: this.citations,
          bodyFontFamily: this.bodyFontFamily, codeFontFamily: this.codeFontFamily,
          onNavigate: (destination: string): void => { this.onNavigate(destination); },
          onCitationTap: (entry: number): void => { this.onCitationTap(entry); } })
      } else {
        this.Fallback()
      }
    }
    .width(this.compact ? undefined : '100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: this.gap })
    .id(markdownAnchorId(this.token, this.node.id))
    .opacity(this.entryOpacity)
    .translate({ y: this.entryOffsetY })
    .transition(TransitionEffect.IDENTITY)
    .onAppear((): void => { this.revealEntry(); })
  }
}
