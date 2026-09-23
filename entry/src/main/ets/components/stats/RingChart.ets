// 通用环形图（2026-09-09 存储管理页图表切换笔：自 UsageRankRing 渲染部分提炼，用量统计页
// 排行卡与存储管理页卡1 共用——决明「存储管理是否也可以加上〔占比条↔环形图切换〕？这应该
// 已有成熟实现，可以复用吧」）。
// · 承托 = 官方 DataPanel 环形型（调研结论见 UsageRankRing 头注释：ArkUI 无饼图组件，
//   官方比例图唯一组件 = DataPanel 环形/线性两型，strokeWidth 超半径钳到 12% 半径做不了
//   实心饼，本质环形；HDS UIDesignKit 亦无图表件。选官方件 = 实现选型三级优先第①级，
//   不自绘 Canvas）。
// · 本件 = 纯渲染：values/colors 由调用方算好传入（两页段色语义各留调用方——用量页名次
//   蓝阶梯 + 其余灰段，存储页六分类蓝阶梯 + 其他灰段）；DataPanel values ≤ 9 段（超出取
//   前 9，d.ts/官方文档同义）由调用方保证。
// · ★ 刷新通道（坑16 家族）：本件入参为普通成员，父组件重渲不更新它——调用方须把本件
//   放进「键含数据签名」的 ForEach（规范 §3 主通道「键变重建」）；两页调用点均如此
//   （UsageRankRing.ringKey / StoragePage.ringKey）。
// · closeEffect(true) 关默认旋转/阴影动画（统计卡静态形态，官方默认动效在此为噪音）；
//   中心两行文字走 Stack 叠加（DataPanel 无子组件——d.ts Child Components: Not supported，
//   布局层叠加非子组件不违反约束）；底部口径备注 = 环段无间隙的自解释性补偿（分段条靠卡
//   底色漏出天然分段，环段没有）。
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
  // 中心下行数值（调用方格式化好的字符串——token 用 fmtCompact）；★ 宽度受 96vp 约束、
  // 超长单行省略；字节类长文本（formatBytes 如「12.3 GB」）建议由卡内大数字承载，勿塞环心
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
          // ★ 可选（2026-09-09 存储页真机反馈「环内总占用过长与环重叠」修复）：两串皆空 =
          // 不渲染中心——存储页环上方已有 32fp 总占用大数字，环心重复且 formatBytes 文本
          // （如「12.3 GB」）远长于用量页 fmtCompact（如「12.3M」），故存储页不传；宽度约束
          // + 单行省略兜底未来调用方的长文本（内径 112vp，留白后取 96vp）
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
