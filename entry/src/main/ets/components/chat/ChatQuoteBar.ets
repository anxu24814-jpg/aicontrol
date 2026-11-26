// 输入侧引用条 + 完整引用查看半模态宿主。域定义一句话：**待发引用的「条 + 截断摘要」呈现
// 与「看全文」半模态宿主**。不能并入 ChatInputBar（贴线件只进接线——挂它根需 +46~55 行越
// 1200 硬线，且其 bindSheet 方法名组已被安全输入面板占用）。
// 挂载位：ChatInputBar 胶囊容器内、暂存密钥条之后、附件条之前（引用与附件同属「待发载荷」，
// 条序与拼装次序一致）。**本组件恒挂不设 if**（半模态判据②——存活期不因数据销毁），条体
// 自身按 quoteText 判空零占位；键盘避让零新码——胶囊增高由宿主阅读带实测逐帧跟随。
// 形态（决明供图定稿、四轮真机反馈收敛后，2026-11-02 单排化笔改单排）：单排——「引用」
// 二字（14fp 强调蓝 usageAccentColor，与正文同号）与单行摘要（灰 font_secondary，maxLines(1)
// + ellipsis）并排一行，右端 × 行内图标键（26 高 TEXTUAL）；条体无底（与胶囊同面），左侧
// **缩进竖线**为独立元素（quoteBarColor，3vp = markdown 引用块同款、高 20 = 单行字高、行内
// 垂直居中），条下 0.5 分隔线（cardBorderColor）与输入区分开——消费侧零 hex。
// 水平内缩 = 图标缘 15 经根 Column padding 下发，条体（Row / Divider / × 键）禁水平 margin
// 内缩（width('100%') + 对称 margin 相互抵消实渲贴边，坑 23 + 官方 FAQ arkui-kit-faq-0005；
// 2077 笔即栽此处——2026-11-04 padding 化修复笔）。
// bindSheet 挂**本组件根**（裁定 D-1 批准「卡片根」档：判据三条 ①合法树内〔PageShell.content
// 树内〕②恒挂随会话页常驻③isShow 与触发键〔条身〕同件；三处登记 = 规范-半模态 §8 表 +
// §4 例表 + assert-ui-shape 329 组注册表）。
// 关闭链四件：`$$` 双向 / onWillDismiss 放行（零暂存站点）/ 关闭恒不复位内容形态
//（ChatQuoteSheet 随开重建）/ 关闭-再开协调五件式（照 ChatInputBar 安全输入族逐字同构）。
// 动效：无动效直出直隐（要动效另立项）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { IMMERSIVE_LEVEL_KEY } from '../../common/ImmersiveLevel';
import { cardBorderColor, quoteBarColor, usageAccentColor } from '../../common/Theme';
import { sheetPanelOptions } from './KimiSheetCommon';
import { ChatQuoteSheet } from './ChatQuoteSheet';

// 条体缘内缩（单源，ChatSkillBar import 消费）：竖线左缘 / × 右缘 / 分隔线两端
// 统一距胶囊缘本值 = ChatInputBar TOOL_KEY_INSET 7 + (INPUT_KEY_SIZE 36 − 图标
// fontSize 20)/2 = 15（锚 = 工具行图标缘，2077 拍板沿用；收起态图标缘 12 差 3
// 不追——一套常量防两态漂移）。★ 下发机制 = 本件根 Column padding——条体水平
// 内缩禁走 margin（width('100%') + 对称 margin 相互抵消、实渲贴边，坑 23 +
// 官方 FAQ arkui-kit-faq-0005；2077 笔即栽此处）。
export const QUOTE_BAR_EDGE_INSET: number = 15;
// 条体顶距（距胶囊顶部压紧）；以下形态常量全导出 = 条族唯一形态单源（2026-11-02
// 单排化笔起 export，U4 技能条同形制消费走 import，防两处漂移）
export const QUOTE_BAR_TOP: number = 6;
// 条内横向间距：竖线-「引用」-正文-删除键等距（贴近成引述线）
export const QUOTE_BAR_TEXT_GAP: number = 6;
// 竖线高 = 单行字高（行高 20）——2026-11-02 单排化笔：40（双行期「短一截引述线」）改 20，
// 与单排文字同高、Row Center 垂直居中
export const QUOTE_BAR_LINE_HEIGHT: number = 20;
// 「引用」标签与正文同号 14（需求原文「二字字号与具体内容统一」）；2026-11-02 单排化笔：
// QUOTE_TITLE_FONT 12 与 QUOTE_BODY_FONT 14 合一，防同值双源
export const QUOTE_BAR_FONT: number = 14;
// 正文行高，语义与竖线高独立、不合并引用
const QUOTE_BODY_LINE_HEIGHT: number = 20;

// 引用摘要预览（码点安全截断，两消费方单源——输入条与用户气泡摘要条）：空白串拍平为
// 单空格（多行原文在单行条内可读），Array.from 按码点切（防代理对劈开成乱码），超限补「…」
export function quotePreviewOf(text: string, maxChars: number): string {
  const flat: string = text.replace(/\s+/g, ' ').trim();
  const chars: string[] = Array.from(flat);
  if (chars.length <= maxChars) {
    return flat;
  }
  return chars.slice(0, maxChars).join('') + '…';
}

// 输入条摘要长度：单排卡约 20 汉字，80 码点 = 4 倍冗余，只为减少超长文本进 Text 布局的量；
// 视觉收口仍由 maxLines(1) + ellipsis 承担（2026-11-02 单排化笔：值不随行数下调）
export const QUOTE_BAR_PREVIEW_CHARS: number = 80;

@Component
export struct ChatQuoteBar {
  // 待发引用（null/'' = 无引用，条零占位）。@Prop 自 ChatInputBar @Link 链下行
  //（ChatPage → ChatPageContent → ChatInputBar → 本件，坑16 正解通道）
  @Prop quoteText: string | null = null;
  // × 键上行：清待发引用（发送成功清空走发送链 clearPendingQuote 冻结比对，不经本键）；
  // 半模态底部「删除引用」键复用同一上行链（同语义，零新回调）
  onDismissQuote: () => void = () => {
  };
  // 底部安全区（半模态内容避让，ChatInputBar.bottomPad 透传，口径同 ChatAnswerSheet.bottomInset）
  @Prop bottomInset: number = 0;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // ── 半模态五件式（关闭-再开协调，照 ChatInputBar 安全输入族同构；机制单源 =
  //    KimiSheetCommon.sheetPanelOptions 第四参注释）──
  @State @Watch('onSheetVisibleChanged') private sheetShow: boolean = false;
  private sheetClosing: boolean = false;
  private pendingOpen: boolean = false;

  // 开意图落定 → 动效在途挂起 / 否则即开（applyOpen 单入口，补开两路共用）
  private requestOpen(): void {
    this.pendingOpen = true;
    if (this.sheetClosing) {
      return; // 动效在途：待补开
    }
    this.applyOpen();
  }

  private applyOpen(): void {
    if (!this.pendingOpen) {
      return;
    }
    this.sheetShow = true;
  }

  // 离场动效结束（sheetPanelOptions 第四参）：清在途位 + 按开意图补开
  private onSheetGone(): void {
    this.sheetClosing = false;
    if (!this.sheetShow) {
      this.applyOpen();
    }
  }

  // 可见性变化兜底（@Watch）：框架 `$$` 收尾回写压回 false 时按开意图补一次
  private onSheetVisibleChanged(): void {
    if (!this.sheetShow) {
      this.applyOpen();
    }
  }

  // 关闭单入口（标题栏 xmark / 手势两路同调）：先清开意图 + 置离场动效在途位，再写可见性
  private requestClose(): void {
    this.pendingOpen = false;
    this.sheetClosing = true;
    this.sheetShow = false;
  }

  // 完整引用面板（纯展示内容件，随开重建——关闭恒不复位内容形态）。onDelete = 清待发引用
  // + 关面板两件（删除动作即完成动作，同 × 键语义）
  @Builder
  QuoteSheetBuilder() {
    ChatQuoteSheet({
      text: this.quoteText ?? '',
      bottomInset: this.bottomInset,
      onClose: (): void => {
        this.requestClose();
      },
      onDelete: (): void => {
        this.onDismissQuote();
        this.requestClose();
      }
    })
  }

  build() {
    // 根 Column 恒挂（半模态判据②——bindSheet 挂点不因数据销毁）；条体判空零占位在内部 if
    Column() {
      if (this.quoteText !== null && this.quoteText !== '') {
        // 条体（单排）：Row = 独立竖线（高 = 单行字高 20，Row alignItems Center 垂直居中）
        // + 「引用」标签（14fp 强调蓝，与正文同号）+ 单行摘要（maxLines(1) + ellipsis，
        // layoutWeight(1) 保证不遮挡右侧删除键）+ × 行内图标键（形制原样）
        Row({ space: QUOTE_BAR_TEXT_GAP }) {
          Column()
            .width(3)
            .height(QUOTE_BAR_LINE_HEIGHT)
            .backgroundColor(quoteBarColor(this.appColorMode))
          Text('引用')
            .fontSize(QUOTE_BAR_FONT)
            .fontColor(usageAccentColor(this.appColorMode))
          Text(quotePreviewOf(this.quoteText ?? '', QUOTE_BAR_PREVIEW_CHARS))
            .fontSize(QUOTE_BAR_FONT)
            .lineHeight(QUOTE_BODY_LINE_HEIGHT)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(16)
              .fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          // 键高钉 26：TEXTUAL 默认 40 高会撑高单排条体；26 = 16 图标 + 上下各 5 热区，仍
          // 可点——行高由本键撑住，竖线与文字在行内垂直居中
          .height(26)
          .padding(0)
          .onClick((): void => {
            this.onDismissQuote();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .onClick((): void => {
          this.requestOpen();
        })
        .margin({ top: QUOTE_BAR_TOP })
        // 条与输入区的分隔线（条体无底后的唯一分段线）：0.5 细线，水平落点与条体同口径
        // （同在根 padding 内容区 [EDGE_INSET, W−EDGE_INSET]，无显式宽默认填满），只作分段
        // 不抢视觉
        Divider()
          .strokeWidth(0.5)
          .color(cardBorderColor(this.appColorMode))
          .margin({ top: 2 })
      }
    }
    .width('100%')
    // 条族水平内缩单一下发点（机制与算式见常量块 EDGE_INSET 注释）：padding 以内容区为
    // 100% 的解析基准，不存在 margin 对称抵消路径，纸面 = 渲染由构造成立。★ 只许水平
    //（left/right）——并入条体顶距会破空态零占位（空态根 Column 无子件，左右 padding 不
    // 贡献高度，top 会渲染死高度）；垂直间距留在 if 分支内 Row / Divider 自身 margin 上
    .padding({ left: QUOTE_BAR_EDGE_INSET, right: QUOTE_BAR_EDGE_INSET })
    // 完整引用查看半模态：detents 缺省 = [MEDIUM, LARGE]（信息查看类，规范 §4）；
    // 零暂存 → onWillDismiss 直放行 + 下拉直落不回弹（sheetPanelOptions 缺省口径）
    .bindSheet($$this.sheetShow, this.QuoteSheetBuilder(),
      sheetPanelOptions((action: DismissSheetAction): void => {
        action.dismiss();
        this.requestClose();
      }, undefined, undefined, (): void => {
        this.onSheetGone();
      }))
  }
}
