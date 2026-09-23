// 「设置页板块头」（2026-09-08 组卡化新增）：卡外板块标题 + 副标题——偏好设置页/更多
// 信息页同构复用（同类页面同版式防跨页漂移，同 SystemPromptPage 版式同规）。样式 =
// Theme SECTION_TITLE_FONTSIZE 规范：16fp Bold cardTitleColor 标题 + 13fp cardDescColor
// 副标题（标题黑且重/说明灰轻——系统提示词页「内容/点击插入变量」同款）；两行均挂
// CARD_PANEL_WIDTH（与卡宽三线对齐：Text 宽 = CARD_PANEL_WIDTH，父 Column 默认 Center
// 对齐 → 左缘 = 卡左缘，与卡天然对齐；★ 2026-09-08 真机反馈修正——本组件内禁设
// alignItems(Start)，Start 会把 Text 拉到面板左缘（X=16vp 的卡左缘对齐丢失），
// 2026-09-01 首版 Set-Preferences 类页面直排 Text 的 Start 口径只适用无外层居中容器的
// 场景，勿沿用）。
// title/subtitle 为静态传入文本（无状态变化源），@Prop 不构成刷新热点（坑16 家族约束
// 针对「状态驱动下发热点」，本组件不适用——走静态常量即可）。
// ★ 2026-09-08 增 hint 可选气泡（决明「两开关下方提示卡是全宽，改成记忆开关标题行右侧
// 对称放气泡键，点击弹气泡，收入气泡内」）：非空 = 标题行右端出 ⓘ 气泡键，长说明收入
// 气泡、板块头只留标题与副标题——形制照外观页 FallbackSwitchCard 标题行（InfoHintButton
// 单源复用，勿另起气泡件）；空 = 原单行标题，存量调用方零观感变化。
import { CARD_PANEL_WIDTH, SECTION_TITLE_FONTSIZE, cardDescColor, cardTitleColor } from '../common/Theme';
import { InfoHintButton } from './InfoHintButton';

@Component
export struct SectionHeader {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  // 气泡说明全文（空 = 不出气泡键）
  @Prop hint: string = '';

  build() {
    Column({ space: 6 }) {
      // 标题行：标题撑满剩余宽 + 气泡键落行尾（行宽 = 卡宽 → 键落卡右缘，与左端标题对称）
      Row() {
        Text(this.title)
          .fontSize(SECTION_TITLE_FONTSIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        if (this.hint !== '') {
          InfoHintButton({ text: this.hint })
        }
      }
      .width(CARD_PANEL_WIDTH)
      .alignItems(VerticalAlign.Center)
      Text(this.subtitle)
        .fontSize(13)
        .fontColor(cardDescColor())
        .width(CARD_PANEL_WIDTH)
    }
    .width('100%')
  }
}
