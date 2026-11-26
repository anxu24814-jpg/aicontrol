// 热力图满日历网格纯展示组件（近七天带状/近三十天日历网格共用；全部档周列仍走 UsageHeatMap
// 已验证的横滚形态零改动）——两形态数据组织（行表 vs 周列）与交互（满铺 vs 横滚）不同，
// 拆件各自一句话说清职责、不动已验证件（反碎片下限①职责缝在案）。
// ★ 满铺实现（零数值计算）：行 = Row({space:6}) 内 7 格 Column layoutWeight(1) 均分 +
// aspectRatio(1) 正方形自动铺满（官方：仅设 width + aspectRatio 时 height = width/比例），
// 行数由数据决定卡高自然随档。★ 不用 Grid（官方 FAQ-arkui-241 实锤：Grid 高度不随
// GridItem 内容自适应，列数不定需手动算高）——一层 Column>Row 常规布局零此坑。
// 数据 @Link 下发（坑16：PageShell.content @BuilderParam 内禁 @Prop——与 UsageHeatMap
// 同通道）；行表由页面分档构建；null 格 = 透明保位格（周一对齐/尾行补位）。图例已撤销
//（两组件与页面均零残留）。点击格 bindPopup 气泡与 UsageHeatMap 全同（重复第 2 次暂不
// 提炼，第三处再抽共有件）。
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
      // 行表网格：左右各 16vp 内边距与卡 padding 对齐（格缩小后总宽 < 卡宽，防「缩进悬空」观感）
      Column({ space: 6 }) {
        ForEach(this.rows, (row: (DayValue | null)[], rowIndex: number): void => {
          Row({ space: 6 }) {
            ForEach(row, (cell: DayValue | null, colIndex: number): void => {
              // null = 范围外空位：透明保位格；满日历大格（~31vp）圆角 8（全部档小格仍 3）
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
                // 点击气泡：宿主 = 该格；onStateChange 关态同步清选中（点外 autoCancel 关闭）
                //——UsageHeatMap 同款配置
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
