// 活动热力图纯展示组件（周列×7 格热力网格 + 月份刻度）：周列数据 @Link 下发（★坑16——
// 本组件居 PageShell.content @BuilderParam 内，@Prop 首帧冻结实锤，禁 @Prop），深浅色自订阅
// appColorMode。
// ★ 时段最大值 maxTotal 由页面在 loadStats 完成后计算、经 @Link 下发——@Watch 对首帧初始
//   化不触发（官方《@Watch 触发时机》），子组件自算首载停 0 → heatLevel(x,0)=0 全灰；父算
//   下发初值即正确值，不依赖任何 @Watch 时序（同修 UsageBarChart.peak）。
// 布局死参数：格 14×14vp 圆角 4、列/格间距 4、null 空位渲染透明格保对位、首列周一顶对齐；
// 图例已撤销零残留。横向 Scroll 补 .align(Alignment.TopStart)——官方默认 Center，窄内容
// 列悬空居中 = 真机「显示不全」根因（超宽时 align 不生效，滚动定位最右逻辑不变）。
// 全部档列数超宽时初始/换档定位最右：内容 Row onAreaChange 触发消费 pendingEdge 标记
//（columns 变更重置标记；坑63 家族 try/catch）。全部档约 365 格 ForEach 全量渲染 = 静态
// 小格子非长列表（已登记变更记录；真机卡顿另立笔，性能不许愿）。
// 月份轴 = 网格正下方一行「X月」刻度（仅全部档消费），置于同一横向 Scroll 内容内随格同滚；
// 刻度块宽 = 该月占列数折算，块边界与网格列边界逐列对位（对位数学见 MonthSpan 注释）。
// 数据 = columns 纯派生，在 build 内实时算（monthSpans）——普通成员 + @Watch 会重蹈「首帧
// 不触发 → 首载空白」覆辙；成本 ≤1ms 不违构建函数红线。
// ★ 2026-11-08 回弹笔：横向 Scroll 显式 edgeEffect(Spring, alwaysEnabled true)——SDK 26
//   默认 EdgeEffect.None，不显式设则横滑到头没有回弹（与页面外层纵向 Scroll 同款）。
import { DayValue, WeekColumn, fmtCompact, heatLevel } from '../../common/store/UsageStatsCalc';
import { cardBg, cardDescColor, cardTitleColor, usageHeatColor } from '../../common/Theme';
import { overlayMaterial } from '../../common/ImmersiveLevel';
import { UsageDayMsgRow } from '../../common/store/UsageStatsDb';

// 点击选中格快照（气泡内容数据源：day + 当日总 token；当天消息数由 dayMsgCounts 查表，
// 与热力格数据同源更新——页面 loadStats 完成后与 columns 同帧下发）
interface SelectedCell {
  day: string;
  totalTokens: number;
}

// 月份刻度块（label = 「X月」；width = 该月占列数×18 − 4〔列宽 14 + 间距 4 同网格死参数〕，
// 块起点 18×列索引逐列对位）。★ Text 固定宽 MONTH_LABEL_W + position 重居中：Stack 层叠布局
// 会约束子项宽度（官方 FAQ faqs-arkui-1650：Text 被压缩超宽换行），position 脱离布局流后
// 文字可溢出窄块（首/尾月仅 1~2 列）到两侧空槽，相邻月份块中心距 ≥52vp 无碰字。
interface MonthSpan {
  label: string;
  width: number;
}

// 月份刻度文字框宽（9fp 最长「12月」≈21vp；固定 24 保证单行不换行——见 MonthSpan 注释）
const MONTH_LABEL_W: number = 24;

// 'YYYY-MM' → 'X月'（月数字不补零；近一年窗口首尾月可能同名不同年，相距 ≥51 列无歧义）
function monthLabelOf(monthKey: string): string {
  return Number(monthKey.substring(5)) + '月';
}

@Component
export struct UsageHeatMap {
  // 周列数组（完整日轴 splitIntoWeekColumns 产物，恒 7 格/列含 null 空位）
  @Link @Watch('onColumnsChange') columns: WeekColumn[];
  // 时段最大值（heatLevel 分母；页面 loadStats 完成时算好下发——见头注释）
  @Link maxTotal: number;
  // 按日消息数（页面与 columns 同帧下发——点击气泡「当天消息总数」数据源）
  @Link dayMsgCounts: UsageDayMsgRow[];
  // 点击选中格快照（null = 无气泡；toggle 语义：点已选中格关闭）
  @State private selectedCell: SelectedCell | null = null;
  // 深浅色模式（热力四档/空档灰分治）
  @StorageProp('appColorMode') appColorMode: number = 1;
  private scroller: Scroller = new Scroller();
  // 定位最右待执行标记（初始 true = 首载定位最右；columns 变更时重置 → 换档后再定位）
  private pendingEdge: boolean = true;

  private onColumnsChange(): void {
    // 仅重置定位标记；maxTotal 由父下发，不在本组件遍历（数据变更的遍历在页面侧）
    this.pendingEdge = true;
  }

  // 全部档月份刻度派生（build 内实时算——@Watch 首帧不触发会首载空白，见头注释）
  private monthSpans(): MonthSpan[] {
    const spans: MonthSpan[] = [];
    if (this.columns.length === 0) {
      return spans;
    }
    let curMonth: string = '';
    let curCols: number = 0;
    for (const col of this.columns) {
      const m: string = this.columnMonth(col);
      if (curMonth === '') {
        curMonth = m;
      } else if (m !== curMonth) {
        spans.push({ label: monthLabelOf(curMonth), width: curCols * 18 - 4 });
        curMonth = m;
        curCols = 0;
      }
      curCols++;
    }
    spans.push({ label: monthLabelOf(curMonth), width: curCols * 18 - 4 });
    return spans;
  }

  // 列归属月 = 列内非空 day 的多数月（并列取最早月；跨月列整体归多数侧，月块边界允许
  // ±1 列——标注语义为月度主体区间而非精确换月线；null 空位无 day 不计）
  private columnMonth(col: WeekColumn): string {
    const counts: Map<string, number> = new Map();
    for (const cell of col.cells) {
      if (cell !== null) {
        const mk: string = cell.day.substring(0, 7);
        counts.set(mk, (counts.get(mk) ?? 0) + 1);
      }
    }
    let best: string = '';
    let bestN: number = 0;
    counts.forEach((n: number, mk: string): void => {
      if (n > bestN || (n === bestN && (best === '' || mk < best))) {
        best = mk;
        bestN = n;
      }
    });
    return best;
  }

  // 点击格 toggle 选中（跨格点击 = 直接切换——popup 宿主由 show 表达式判定，只可能一个格
  // show=true）
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

  // 气泡内容（日期 + 消息数 + 总 token；文案规约：句号分句、避免冒号分号括号——
  // 「消息 12 条 · 总 token 47.8k」同卡内统计行顿点先例）
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
      // 网格 + 月份轴：横向滚动（月份刻度随格同滚）
      Scroll(this.scroller) {
        Column({ space: 4 }) {
          // 网格：周列 Row > 列内固定 7 格
          Row({ space: 4 }) {
            ForEach(this.columns, (col: WeekColumn): void => {
              Column({ space: 4 }) {
                ForEach(col.cells, (cell: DayValue | null, index: number): void => {
                  if (cell === null) {
                    // 范围外空位：透明格保对位（与实格同尺寸 14×14）
                    Column()
                      .width(14)
                      .height(14)
                  } else {
                    Column()
                      .width(14)
                      .height(14)
                      .borderRadius(4)
                      .backgroundColor(usageHeatColor(this.appColorMode,
                        heatLevel(cell.totalTokens, this.maxTotal)))
                      .onClick((): void => {
                        this.toggleCell(cell);
                      })
                      // 点击气泡：placement Bottom 系统自动避让边缘；popupColor 卡底色同
                      // 深浅色；onStateChange 关态同步清选中（点外 autoCancel 关闭）
                      .bindPopup(this.selectedCell !== null &&
                        this.selectedCell.day === cell.day, {
                        builder: this.cellTip(),
                        placement: Placement.Bottom,
                        // 「无」档专用实底回退（材质生效时官方忽略 popupColor）
                        popupColor: cardBg(this.appColorMode),
                        // 弹层族材质（决明指令「气泡全 thick」）
                        systemMaterial: overlayMaterial(),
                        onStateChange: (e: PopupStateChangeParam): void => {
                          if (!e.isVisible) {
                            this.selectedCell = null;
                          }
                        }
                      })
                  }
                }, (cell: DayValue | null, index: number): string =>
                  cell === null ? 'pad-' + index : cell.day + '|' + cell.totalTokens)
              }
            }, (col: WeekColumn): string => col.key)
          }
          // 月份轴行：块宽逐列对位网格列起点；Text 固定宽 + position 重居中（见 MonthSpan 注释）
          Row({ space: 4 }) {
            ForEach(this.monthSpans(), (span: MonthSpan): void => {
              Stack() {
                Text(span.label)
                  .fontSize(9)
                  .fontColor(cardDescColor())
                  .width(MONTH_LABEL_W)
                  .maxLines(1)
                  .textAlign(TextAlign.Center)
                  .position({ x: (span.width - MONTH_LABEL_W) / 2, y: 0.5 })
              }
              .width(span.width)
              .height(14)
            }, (span: MonthSpan, index: number): string => span.label + '|' + index)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .onAreaChange((): void => {
          // 内容宽就绪/变化后定位最右（首触发消费标记防重复；坑63 家族 try/catch）
          if (this.pendingEdge) {
            this.pendingEdge = false;
            try {
              this.scroller.scrollEdge(Edge.End);
            } catch (e) {
              // 滚动器未就绪时容错（观感降级为从最早一列显示，不阻断渲染）
            }
          }
        })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      // SDK 26 的 Scroll 默认 EdgeEffect.None——显式挂 Spring 才有滑到头的回弹
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      // 内容窄于视口时靠左（理由见头注释）
      .align(Alignment.TopStart)
    }
    .width('100%')
  }
}
