// 输入胶囊内「下一条消息指定技能」条：单排形制复用引用条单排成品（条族形态单源 =
// ChatQuoteBar，常量 import 防两处漂移）。不能并入 ChatQuoteBar：内容源与删除语义不同
//（引用 = 待发文本，删除清文本；技能 = 指定双值，删除取消指定）——两者可同屏并存，合件会把
// 两条上行链耦成一条。恒挂不设外层 if：判空收在组件内部（与 ChatQuoteBar 同构——
// ChatInputBar 只承担恒挂接线，判据不散落宿主）；条体无点击交互（入口仍是「+」→ 会话设置 →
// 技能卡）。删除 = 取消指定（清 designatedSkillId/Name 两值，同技能选择面板关当前开关
// 语义）；与面板/状态面板经 ChatPage 两 @State 真源自然双向同步。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { cardBorderColor, quoteBarColor, usageAccentColor } from '../../common/Theme';
import {
  QUOTE_BAR_EDGE_INSET, QUOTE_BAR_FONT, QUOTE_BAR_LINE_HEIGHT,
  QUOTE_BAR_TEXT_GAP, QUOTE_BAR_TOP
} from './ChatQuoteBar';
// 缘内缩零本地常量——EDGE_INSET 单源 import（条族形态单源在 ChatQuoteBar，
// 本件禁再定义同义常量）

@Component
export struct ChatSkillBar {
  // 指定真源双值（ChatPage 两 @State 经 Content → ChatInputBar @Link 链下行；id 非空 =
  // 已指定，与 statusIconColor/canSend 同口径；名与 id 双值同写恒同步——写入点 =
  // 面板 onSkillDesignated / 发送清态 / 本条删除键三处）
  @Prop skillId: string = '';
  @Prop skillName: string = '';
  // × 键上行：取消指定（链回页面清两值；命名避开 onClearDesignate 子串——104 组负向钉）
  onRemoveSkillDesignate: () => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  build() {
    // 根 Column 恒挂（判空在内部 if，条体零占位）；无半模态面、无点击开面板
    Column() {
      if (this.skillId !== '') {
        // 条体（单排，同引用条）：Row = 独立竖线（高 = 单行字高 20）+ 「技能」标签
        //（14fp 强调蓝）+ 技能名（maxLines(1) + ellipsis，layoutWeight(1) 保证不遮挡
        // 右侧删除键）+ × 行内图标键（官方形制：无底 TEXTUAL + font_secondary）
        Row({ space: QUOTE_BAR_TEXT_GAP }) {
          Column()
            .width(3)                                  // markdown 引用块同款 3vp（同引用条）
            .height(QUOTE_BAR_LINE_HEIGHT)             // 20
            .backgroundColor(quoteBarColor(this.appColorMode))
          Text('技能')                                 // 恰「技能」二字——禁「技能 · 」整串（104 组负向钉）
            .fontSize(QUOTE_BAR_FONT)                  // 14
            .fontColor(usageAccentColor(this.appColorMode))
          Text(this.skillName)
            .fontSize(QUOTE_BAR_FONT)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)                           // 权重保证不遮挡右侧删除键
          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))        // xmark——禁 wand_and_stars（104 组负向钉）
              .fontSize(16)
              .fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)        // 行内图标键官方形制：无底 TEXTUAL + font_secondary
          // 键高钉 26：TEXTUAL 默认 40 高会撑高单排条体；26 = 16 图标 + 上下各 5 热区（同引用条）
          .height(26)
          .padding(0)
          .onClick((): void => {
            this.onRemoveSkillDesignate();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ top: QUOTE_BAR_TOP })
        // 条下分隔线（同引用条形制，水平落点同在根 padding 内容区；与引用条同屏时两道线
        // 各随各条显隐——真机观感待验）
        Divider()
          .strokeWidth(0.5)
          .color(cardBorderColor(this.appColorMode))
          .margin({ top: 2 })
      }
    }
    .width('100%')
    // 条族水平内缩单一下发点（机制单源注释 = ChatQuoteBar 常量块 EDGE_INSET；只许水平、
    // 破空态零占位同理）
    .padding({ left: QUOTE_BAR_EDGE_INSET, right: QUOTE_BAR_EDGE_INSET })
  }
}
