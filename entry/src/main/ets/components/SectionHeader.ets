// 「设置页板块头」（组卡化新增）：卡外板块标题——偏好设置页/更多信息页同构复用（同类页面
// 同版式防跨页漂移）。样式 = Theme SECTION_TITLE_FONTSIZE 规范：14fp 常规字重 +
// $r('sys.color.ohos_id_color_emphasize') 官方强调蓝（HdsTabs 选中同源，2026-11-01 改档；
// 字级与组卡行副标题同档）。标题行挂 CARD_PANEL_WIDTH（与卡宽三线对齐：Text 宽 =
// CARD_PANEL_WIDTH，父 Column 默认 Center 对齐 → 左缘 = 卡左缘，与卡天然对齐；★ 真机反馈
// 修正——本组件内禁设 alignItems(Start)，Start 会把 Text 拉到面板左缘（卡左缘对齐丢失）；
// 首版直排 Text 的 Start 口径只适用无外层居中容器的场景，勿沿用）。
// ★ 副标题行整行退役（2026-11-01 决明拍板「去掉所有板块副标题」——subtitle prop 与 13fp
// 灰副标题行撤除，板块面只留标题；计数与说明改由卡面行副标题、空态行与 ⓘ 气泡承接）。
// title 为静态传入文本（无状态变化源），@Prop 不构成刷新热点（坑16 家族约束针对「状态驱动
// 下发热点」，本组件不适用——走静态常量即可）。
// ★ hint 可选气泡（长说明收入气泡、板块头只留标题）：非空 = 标题行右端出 ⓘ 气泡键
//（InfoHintButton 单源复用，勿另起气泡件）；空 = 单行标题。
import { CARD_PANEL_WIDTH, SECTION_TITLE_FONTSIZE } from '../common/Theme';
import { InfoHintButton } from './InfoHintButton';

@Component
export struct SectionHeader {
  @Prop title: string = '';
  // 气泡说明全文（空 = 不出气泡键）
  @Prop hint: string = '';

  build() {
    Column() {
      // 标题行：标题撑满剩余宽 + 气泡键落行尾（行宽 = 卡宽 → 键落卡右缘，与左端标题对称）
      Row() {
        Text(this.title)
          .fontSize(SECTION_TITLE_FONTSIZE)
          .fontColor($r('sys.color.ohos_id_color_emphasize'))
          .layoutWeight(1)
        if (this.hint !== '') {
          InfoHintButton({ text: this.hint })
        }
      }
      .width(CARD_PANEL_WIDTH)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
  }
}
