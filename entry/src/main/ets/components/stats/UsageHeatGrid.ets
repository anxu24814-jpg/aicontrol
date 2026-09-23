// 热力图满日历网格纯展示组件（2026-09-07「满日历」方案新增，近七天带状/近三十天日历
// 网格共用——职责缝 = 「行表 × 7 列 Grid 网格 + 少/多图例」一件独立事；全部档周列仍走
// UsageHeatMap（用户已满意的 53 列横滚形态，零改动）。为什么新组件而非改 UsageHeatMap：
// 两形态数据组织不同（行表 vs 周列）、交互不同（满铺 vs 超宽横滚），同文件会引入分支，
// 拆出后各自一句话说清职责、且不动已验证件（反碎片下限①职责缝 + 「为何不并入页面」式
// 理由在案）。
// ★ 满铺实现（零数值计算）：行 = Row({space:6}) 内 7 格 Column layoutWeight(1) 均分 +
//   aspectRatio(1) = 正方形格子自动铺满（官方通用属性：仅设 width + aspectRatio 时
//   height = width/aspectRatio——d.ts:20532 实锤）；行数由数据决定（七天 = 1 行 7 列带状、
//   三十天 = 6 行 7 列日历网格），卡高自然随档——不设死参数数字，防贴线挤压。
//   ★2026-09-07 决明三调：间距 8→6 + 网格/图例左右 padding 16（对齐卡 padding），格子
//   ~34vp→~31vp 略小、圆角 3→6→10→8（当前 8，≈26%）——详见组件内注释。
//   ★ 不用 Grid 的原因（官方 FAQ-arkui-241 实锤）：Grid 高度不随 GridItem 内容自适应
//   （height auto 也不撑起、不设高 = 与父同高），列数不定场景需手动算高或换 List lanes
//   ——一层 Column>Row 常规布局零此坑，且与「图例行」同構简单直白。
// · 数据 @Link 下发（坑16：PageShell.content @BuilderParam 内禁 @Prop——与 UsageHeatMap
//   同通道）；行表由页面分档构建（七天 = [axis]、三十天 = splitIntoCalendarRows(axis)）；
//   null 格 = 透明保位格（周一对齐/尾行补位，同周列口径）；深浅色自订阅 appColorMode。
// · 图例已移除（★2026-09-07 决明调位后拍板撤销：「少→多」图例曾迁入页面标题行右上，
//   最终版 = 页面与两组件均不再含图例，零残留——口径见 UsageStatsPage 卡头注释）。
// ★ 2026-09-07 新增（决明「点击格子气泡展示当天消息总数与总 token」）：格子 onClick +
//   bindPopup 同款交互（与 UsageHeatMap 全同——气泡内容/选中态/查消息数逻辑两组件
//   重复第 2 次，达到「重复 2 次以上提取」下限前暂不提炼，第三处再抽共有组件或函数）。
import { DayValue, fmtCompact, heatLevel } from '../../common/store/UsageStatsCalc';
import { cardBg, cardDescColor, cardTitleColor, usageHeatColor } from '../../common/Theme';
import { overlayMaterial } from '../../common/ImmersiveLevel';
import { UsageDayMsgRow } from '../../common/store/UsageStatsDb';

// 点击选中格快照（与 UsageHeatMap 同型声明——两组件同构，见头注释重复说明）
interface GridSelectedCell {
  day: string;
  totalTokens: number;
}

@Component
export struct UsageHeatGrid {
  // 行表（每行恒 7 列 = 周一~周日对位；七天档 = 单行日期序带状）
  @Link rows: (DayValue | null)[][];
  // 时段最大值（heatLevel 分母；页面算好下发）
  @Link maxTotal: number;
  // 深浅色模式（热力四档/空档灰分治）
  @StorageProp('appColorMode') appColorMode: number = 1;
  // 按日消息数（页面与 rows 同帧下发——点击气泡「当天消息总数」数据源，UsageHeatMap 同款）
  @Link dayMsgCounts: UsageDayMsgRow[];
  // 点击选中格快照（null = 无气泡；toggle 语义：点已选中格关闭）
  @State private selectedCell: GridSelectedCell | null = null;

  // 点击格 toggle 选中（与 UsageHeatMap 同逻辑：点已选中格关闭、跨格点击直接切换——
  // popup 宿主由 show 表达式判定，同一时刻至多一个格 show=true）
  private toggleCell(cell: DayValue): void {
    if (this.selectedCell !== null && this.selectedCell.day === cell.day) {
      this.selectedCell = null;
    } else {
      this.selectedCell = { day: cell.day, totalTokens: cell.totalTokens };
    }
  }

  // 当日消息数查表（读不到 = 0——与总览 messageCount 同口径：无记录日零值形态）
  private msgCountOf(day: string): number {
    for (const r of this.dayMsgCounts) {
      if (r.day === day) {
        return r.count;
      }
    }
    return 0;
  }

  // 气泡内容（日期 + 消息数 + 总 token；文案规约：避免冒号分号括号，「·」同卡内统计行先例）
  @Builder
  cellTip() {
    if (this.selectedCell !== null) {
      Column({ space: 4 }) {
        Text(this.selectedCell.day)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
        Text('消息 ' + this.msgCountOf(this.selectedCell.day) + ' 条 · 总 token ' +
          fmtCompact(this.selectedCell.totalTokens))
          .fontSize(12)
          .fontColor(cardDescColor())
      }
      .padding(12)
      .alignItems(HorizontalAlign.Start)
    }
  }

  build() {
    Column() {
      // 行表网格：行 = Column({space:6}) 顺序，列 = Row({space:6}) 内 7 格均分；网格与图例
      // 左右各 16vp 内边距（= 卡片 padding 同宽对齐——2026-09-07 决明三调「格与间距同时
      // 略小一点保持协调」：间距 8→6、格（~34vp→~31vp）缩小时总宽 < 卡宽，左右 16 边距
      // 让内容与卡 padding 视觉层一致，避免「缩进悬空」观感）
      Column({ space: 6 }) {
        ForEach(this.rows, (row: (DayValue | null)[], rowIndex: number): void => {
          Row({ space: 6 }) {
            ForEach(row, (cell: DayValue | null, colIndex: number): void => {
              // null = 范围外空位：透明保位格（layoutWeight+aspectRatio 同上保对位）
              // ★2026-09-07 决明三轮反馈「7/30 格子圆角略大一点」→ 3→6→10→8：满日历大格
              //   （~31vp）圆角 8（≈26% 圆角比例；全部档 12vp 小格仍 3 不动）
              Column()
                .layoutWeight(1)
                .aspectRatio(1)
                .borderRadius(8)
                .backgroundColor(cell === null ? Color.Transparent :
                  usageHeatColor(this.appColorMode, heatLevel(cell.totalTokens, this.maxTotal)))
                .onClick((): void => {
                  if (cell !== null) {
                    this.toggleCell(cell);
                  }
                })
                // 点击气泡：宿主 = 该格；popupColor 卡底色同深浅色；onStateChange 关态
                // 同步清选中（点外 autoCancel 关闭）——UsageHeatMap 同款配置
                .bindPopup(cell !== null && this.selectedCell !== null &&
                  this.selectedCell.day === cell.day, {
                  builder: this.cellTip(),
                  placement: Placement.Bottom,
                  // 「无」档专用实底回退（材质生效时官方忽略 popupColor）
                  popupColor: cardBg(this.appColorMode),
                  // 弹层族材质（2026-09-22 决明指令「气泡全 thick」）
                  systemMaterial: overlayMaterial(),
                  onStateChange: (e: PopupStateChangeParam): void => {
                    if (!e.isVisible) {
                      this.selectedCell = null;
                    }
                  }
                })
            }, (cell: DayValue | null, colIndex: number): string =>
              cell === null ? 'pad-' + colIndex : cell.day + '|' + cell.totalTokens)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }, (row: (DayValue | null)[], rowIndex: number): string => {
          // 行键 = 行内首非空日（无非空行不存在——每行至少一个非空格，构造保证）
          for (const c of row) {
            if (c !== null) {
              return c.day;
            }
          }
          return 'row-' + rowIndex;
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
  }
}
