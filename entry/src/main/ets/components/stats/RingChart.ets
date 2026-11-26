// 通用环形图（纯渲染，用量统计页排行卡与存储管理页卡1 共用）：承托 = 官方 DataPanel 环形型
//（ArkUI 无饼图组件，strokeWidth 超半径钳到 12% 做不了实心饼；选官方件不自绘 Canvas）。
// values/colors 由调用方算好传入（段色语义各留调用方）；DataPanel values ≤ 9 段由调用方保证。
// ★ 刷新通道（坑16 家族）：本件入参为普通成员，父组件重渲不更新它——调用方须把本件放进
// 「键含数据签名」的 ForEach（规范 §3 键变重建，先例 UsageRankRing.ringKey）。
// closeEffect(true) 关默认动效（静态形态）；中心两行文字走 Stack 叠加（DataPanel 无子组件，
// 布局层叠加不违反约束）；底部口径备注补偿环段无间隙的自解释性。
import { cardDescColor, cardTitleColor } from '../../common/Theme';

// 环直径 / 环厚（vp）：148 直径 + 18 厚 = 中心可容纳两行文字的环形带
const RING_SIZE: number = 148;
const RING_STROKE: number = 18;

@Component
export struct RingChart {
  // 入环值序列（段序 = 展示序；段数 ≤ 9 由调用方保证）
  values: number[] = [];
  // 段色（与 values 等长；半透明色透卡底自动深浅适配）
  colors: string[] = [];
  // 中心上行标签（如「总 token」；与 centerValue 皆空 = 不渲染中心——存储页即此形态）
  centerLabel: string = '';
  // 中心下行数值（调用方格式化好的字符串——token 用 fmtCompact）；宽度受 96vp 约束、超长
  // 单行省略——字节类长文本建议由卡内大数字承载，勿塞环心
  centerValue: string = '';
  // 底部口径备注（段序与色语义说明）
  note: string = '';

  build() {
    Column({ space: 12 }) {
      Row() {
        Stack({ alignContent: Alignment.Center }) {
          DataPanel({ values: this.values, max: 0, type: DataPanelType.Circle })
            .width(RING_SIZE)
            .height(RING_SIZE)
            .strokeWidth(RING_STROKE)
            .valueColors(this.colors)
            .trackBackgroundColor(Color.Transparent)
            .closeEffect(true)
          // 中心两行（DataPanel 无子组件——Stack 叠加非子组件，布局层叠加不违反约束）。
          // 两串皆空 = 不渲染中心（存储页即此形态——环上方已有总占用大数字，长文本勿塞
          // 环心）；宽度约束 + 单行省略兜底调用方长文本（内径 112vp，留白后取 96vp）
          if (this.centerLabel !== '' || this.centerValue !== '') {
            Column({ space: 2 }) {
              Text(this.centerLabel)
                .fontSize(11)
                .fontColor(cardDescColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.centerValue)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(cardTitleColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Center)
            .constraintSize({ maxWidth: 96 })
          }
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      Text(this.note)
        .fontSize(11)
        .fontColor(cardDescColor())
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
