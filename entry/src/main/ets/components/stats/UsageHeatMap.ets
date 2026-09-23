// 活动热力图纯展示组件（2026-09-06 任务书-用量统计页改版，自 UsageStatsPage 拆出——
// 职责缝 = 「周列×7 格热力网格 + 月份刻度」一件独立事；页面改版后体量 400+ 行且本组件
// 可一句话说清职责，为何不并入页面登记在变更记录当日节）：周列数据 @Link 下发
//（★坑16 热点——本组件居 PageShell.content @BuilderParam 内，@Prop 首帧冻结实锤，
// 禁 @Prop），深浅色自订阅 appColorMode（UsageStatsPage 同款订阅键）。
// ★ 2026-09-07 修复（决明真机反馈「热力图显示不全/首载全灰」）：时段最大值 maxTotal
//   改由页面在 loadStats 完成后计算、经 @Link 下发——原实现 = 子组件 @Watch 内算普通
//   成员，但 @Watch 对首帧初始化不触发（官方《@Watch 触发时机》：初始化不算状态改变），
//   首载档（loaded 未置位不渲染组件 → Promise 完成后首次创建）maxTotal 停在 0 →
//   heatLevel(x,0)=0 全灰；切档后组件已存在 @Watch 才触发。父算下发 = 初值即正确值，
//   不依赖任何 @Watch 时序（同修 UsageBarChart.peak）。（坑16 禁 @Prop，maxTotal 同走
//   @Link。）
// 布局死参数（任务书；★2026-09-07 决明指令「格子略调大，注意排版协调」修订——原
// 12×12/间距3/圆角3/图例10 作废）：格 14×14vp 圆角 4、列/格间距 4、null 空位渲染
// 14×14 透明格保对位、首列周一顶对齐（splitIntoWeekColumns 产物）。
// ★2026-09-07 图例调位后撤销（决明调位：图例曾入页面标题行右上、蓝字「活跃天数」入
//   网格下方——最终版 = 移除，本组件与 UsageHeatGrid/页面均不再含图例，零残留）。
// ★ 2026-09-07 修复（同批真机反馈）：横向 Scroll 补 .align(Alignment.TopStart)——官方
//   align 默认 Center（通用属性默认值实锤），内容窄（7 天 2 列/全部 2 列 ≈32vp）时列
//   悬空居中、左右留白不均，观感「显示不全/错位」；靠左后窄内容贴标题下自然对齐，
//   超宽档（近三十天 6 列/全部 36 列）滚动定位最右逻辑不受 align 影响（内容 > 视口时
//   align 不生效，官方说明）。
// 全部档列数超宽时初始/换档定位最右：内容 Row onAreaChange 触发消费 pendingEdge 标记
//（columns 变更重置标记 → 换档后超宽档同样落最右；坑63 家族 try/catch）。
// 热力图全部档约 365 格 ForEach 全量渲染 = 静态小格子非长列表（LazyForEach 要求不适用，
// 变更记录已登记说明）；真机卡顿另立笔（性能不许愿）。
// ★ 2026-09-07 新增（决明「底部对应列下面加月份标记 数字加月 跟随格子滚动」）：月份轴 =
//   网格正下方一行「X月」刻度（本组件只被全部档消费 = 仅全部档显示），置于同一个横向
//   Scroll 内容内随格同滚；刻度块宽 = 该月占列数折算，块边界与网格列边界逐列对位（块宽
//   公式列数×18−4 + space 4 与网格同参，对位数学见 MonthSpan 注释）。数据 = columns 纯
//   派生，在 build 内实时算（monthSpans）——普通成员 + @Watch 重算会重蹈本头注释上方
//   「@Watch 首帧不触发 → 首载空白」覆辙（初始化不算状态改变），build 内算初值即正确值；
//   成本 = 53 列×7 格次切片 ≤ 1ms，远小于 ForEach 渲染 365 格本身，不违反「构建函数内
//   不执行高耗时操作」（无实测卡顿不做预优化，性能不许愿）。
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

// 月份刻度块（label = 「X月」；width = 该月占列数×18 − 4〔列宽 14 + 间距 4 同网格死参数〕
// ——12 块宽和 + 11 个 space 4 = 53×18 − 4 = 网格行总宽，块起点 18×列索引逐列对位）。
// ★ Text 固定宽 MONTH_LABEL_W + position 重居中：Stack 默认层叠布局会约束子项宽度
// （官方 FAQ faqs-arkui-1650 实锤：Text 被压缩、超宽换行），position 脱离布局流后文字
// 可溢出窄块（近一年窗口首/尾月仅 1~2 列 = 14~32vp）到两侧空槽；相邻月份块中心距
// ≥52vp（窄 1 列月旁宽月 ≥4 列）无碰字；「9月」~「12月」9fp 实测 ≤21vp < 24 不换行。
interface MonthSpan {
  label: string;
  width: number;
}

// 月份刻度文字框宽（9fp 最长「12月」≈21vp；固定 24 保证单行不换行——见 MonthSpan 注释）
const MONTH_LABEL_W: number = 24;

// 'YYYY-MM' → 'X月'（月数字不补零；近一年窗口首尾月可能同名不同年〔2025-09 与 2026-09〕，
// 相距 ≥51 列无歧义）
function monthLabelOf(monthKey: string): string {
  return Number(monthKey.substring(5)) + '月';
}

@Component
export struct UsageHeatMap {
  // 周列数组（完整日轴 splitIntoWeekColumns 产物，恒 7 格/列含 null 空位）
  @Link @Watch('onColumnsChange') columns: WeekColumn[];
  // 时段最大值（heatLevel 分母；页面 loadStats 完成时算好下发——见头注释 2026-09-07 修复）
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

  // 全部档月份刻度派生（build 内实时算——为何不普通成员 + @Watch：@Watch 首帧初始化
  // 不触发，首载时停在 [] = 月份轴空白，重蹈头注释 2026-09-07 覆辙；build 内算用当前
  // @Link 值，初值即正确值，切档亦同步）
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

  // 点击格 toggle 选中（点已选中格 = 关闭；跨格点击 = 直接切换——popup 宿主由 show 表达式
  // 判定：selectedCell.day === 该格 cell.day，只可能一个格 show=true）
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
      // 网格 + 月份轴：横向滚动（月份刻度随格同滚）> Column > 周列网格行 + 月份刻度行
      Scroll(this.scroller) {
        Column({ space: 4 }) {
          // 网格：横向滚动 > 周列 Row > 列内固定 7 格
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
                      // 点击气泡：宿主 = 该格，placement Bottom 系统自动避让边缘；popupColor
                      // 卡底色同深浅色；onStateChange 关态同步清选中（点外 autoCancel 关闭）
                      .bindPopup(this.selectedCell !== null &&
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
                  }
                }, (cell: DayValue | null, index: number): string =>
                  cell === null ? 'pad-' + index : cell.day + '|' + cell.totalTokens)
              }
            }, (col: WeekColumn): string => col.key)
          }
          // 月份轴行：网格正下方「X月」刻度（块宽 = 月占列数折算 = 网格列起点等距对位；
          // Text 固定宽 24 + position 重居中——窄月块（首/尾月 1~2 列）文字溢出两侧空槽，
          // 不换行不截断；y = (14 − 13)/2 按 9fp 行高 ~13 估算居中误差 ≤1vp）
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
          // 内容宽就绪/变化后定位最右（首次触发消费标记即解除防重复；坑63 家族 try/catch）
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
      .width('100%')
      // 内容窄于视口时靠左（官方默认 Center 居中悬空 = 2026-09-07 真机「显示不全」观感
      // 根因；超宽时 align 不生效，滚动定位最右逻辑不变）
      .align(Alignment.TopStart)
    }
    .width('100%')
  }
}
