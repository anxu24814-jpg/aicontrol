// 用量统计页（设置页「用量统计」卡 push）：顶部吸顶分段胶囊（近七天 / 近三十天 / 全部）切时段，
// 五卡全部联动重查。板块自上而下 = Token 用量（大字体总量 + 比前 N 天变动行 + 分割线下输入/输出/
// 每条平均三列；2026-11-08 首卡改版笔，形制参照决明供图两张）→ 总览 2×3（累计生成时长 / 每日
// 平均 token / 最长连续活跃等 6 格）→ 用量热力图（满日历三形态：近七天 = 单行 7 格带状、近三十天
// = 日历网格〔列 = 周一~周日 6 行，Grid 1fr×7 + aspectRatio 自适应铺满〕、全部 = 53 列周列横滚）→
// 模型用量排行 Top10（项目行样式不做横向进度条；顶部占比条 ↔ 环形图切换，见 UsageRankRing.ets）→
// 用量趋势柱状图（逐日/逐月随时段，含峰值；柱状 ↔ 折线切换）。
// · 首卡口径：标题恒「Token 用量」；总量与三列格值同源 buildTokenCells（工具侧同函数，第 1 格
//   放大、后 3 格进三列，禁改四格序）；大字与单位走单 Text 双 Span 基线平齐；变动走绝对量
//   口径不写百分比，箭头为官方 SymbolGlyph 中性灰；全部档无可比周期 → 不发上期查询，改在
//   同一等高信息行显「自 YYYY年M月 起累计」（取 usageByDay(0) 最早记录日，零新 SQL）。
//   上期总量 ≤ 0（新装/刚升级）或上期查询失败同样留空，不写恒真的「增加」噪声。
// · 三处横滚容器（UsageHeatMap / UsageBarChart / UsageLineChart）显式挂 Spring 回弹——
//   SDK 26 的 Scroll.edgeEffect 默认 EdgeEffect.None，不显式设则横向滑到头没有回弹。
// · 数据单源 = common/store/UsageStatsDb.ets（usageOverview/usageByModel/usageByDay 三聚合带
//   sinceMs 时段参 + usageTokenTotalBetween 单行 SUM 查上期）；轴/格/聚合与上期比较纯函数 =
//   common/store/UsageStatsCalc.ets（scripts/usage-stats-calc-check.mjs 机械断言钉死）。
// · 切档联动：rangeIndex @Watch → 五路并行重查（第五炮仅近七天/近三十天发，单炮独立降级只
//   隐藏变动行），保留旧数据静默刷新不闪加载态；loadSeq 序号守卫防快速连切时旧响应覆盖新数据；
//   prevRangeIndex 挡住切档瞬间「旧数据配新档文案」的错配；失败 toast 明示 + 保留旧数据（首载
//   失败按空态展示）。
// · 空态 = 全时段也无任何用量记录才显示（globalEmpty：首载额外一炮全量 overview 判 rounds===0；
//   存量不回填口径下升级后空态属正常形态）；单档无数据正常渲染零值形态。
// · 图组件与格值刷新通道：UsageHeatMap/UsageBarChart 数据 @Link（$ 语法）下发——★坑16 热点
//  （PageShell.content @BuilderParam 内子组件 @Prop 首帧冻结，禁 @Prop）；卡内动态数值一律 ForEach。
// ★ 时段最大值 heatMax / 趋势峰值 trendPeak 由本页在 loadStats 完成时算好 @Link 下发——图组件 @Watch
//   内自算时首帧初始化不触发（首载分母停在 0 → 热力图全灰、趋势柱全落 3vp 零值条）；父算下发 =
//   初值即正确值，不依赖任何 @Watch 时序。
// · 无编辑无保存动作 → 返回无参 pop 不挂 onPop（坑17 口径）；各卡说明小字置于数据上方。
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { PageShell } from '../../common/PageShell';
import { SETTING_TITLE_USAGE_STATS } from '../../common/SettingSearch';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, SEGMENT_BAR_HEIGHT, SEGMENT_BAR_BAND_TOP_INSET_STATS,
  badgeBg, cardBg, cardBorderColor, cardDescColor, cardTitleColor,
  usageAccentColor, CARD_RADIUS
} from '../../common/Theme';
import { UsageByDayRow, UsageByModelRow, UsageDayMsgRow, UsageOverview, usageByDay,
  usageByDayMessageCounts, usageByModel, usageOverview,
  usageTokenTotalBetween } from '../../common/store/UsageStatsDb';
import { DayValue, TrendPoint, UsageStatCell, WeekColumn, aggregateByMonth, axisStartDayKey,
  buildOverviewCells, buildTokenCells, comparisonPeriodLabel, comparisonSinceMs, fillDailyRange,
  fmtCompact, longestStreak, rangeSinceMs, splitIntoCalendarRows, splitIntoWeekColumns,
  toLocalDayKey, tokenDeltaDirection, tokenDeltaText } from '../../common/store/UsageStatsCalc';
import { PageTopSegmentBand } from '../SegmentBar';
import { StatGrid } from '../stats/StatGrid';
import { UsageBarChart } from '../stats/UsageBarChart';
import { UsageHeatGrid } from '../stats/UsageHeatGrid';
import { UsageHeatMap } from '../stats/UsageHeatMap';
import { UsageLineChart } from '../stats/UsageLineChart';
import { UsageRankRing } from '../stats/UsageRankRing';

// 总览/Token 卡格数据（StatGrid 的 ForEach 数据源；类型与格值构造上收 UsageStatsCalc——用量统计
// 工具同源消费）

@Component
export struct UsageStatsPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI、不上行（数据层意图照常完成）
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 时段档（0 近七天默认 / 1 近三十天 / 2 全部）：@Watch 切档即三聚合并行重查
  @State @Watch('onRangeChange') private rangeIndex: number = 0;
  // 标题栏下方带承载：**下移量取 STATS 档 16**——本页现状为 `margin top: topPad`（不探入
  // 蒙层，比其余八处低 8vp），按「不动位置」原则各保现状（Theme 常量注释）
  @Builder
  TopSegmentBand() {
    PageTopSegmentBand({
      items: this.rangeItems,
      selectedIndex: $rangeIndex,
      inset: SEGMENT_BAR_BAND_TOP_INSET_STATS
    })
  }
  @State private overview: UsageOverview | null = null;
  @State private byModel: UsageByModelRow[] = [];
  // 热力图周列 / 趋势点（图组件 @Link 下发）+ 完整逐日轴（统计行「最长连续」同源）
  @State private heatColumns: WeekColumn[] = [];
  // 满日历行表（近七天 = 单行带状 [axis]、近三十天 = 日历网格；全部档走 heatColumns——分档分支渲染）
  @State private heatGridRows: (DayValue | null)[][] = [];
  // 按日消息数（messages 表 user+assistant 当日 COUNT——热力图气泡「当天消息总数」，与总览
  // messageCount 同口径）
  @State private dayMsgCounts: UsageDayMsgRow[] = [];
  @State private trendPoints: TrendPoint[] = [];
  // 最长连续活跃天数（loadStats 局部算好存此——总览「最长连续活跃」格消费；calc 层 longestStreak 复用）
  @State private longestStreakDays: number = 0;
  // 时段最大值 / 趋势峰值（图组件 heatLevel/柱高 分母；本页算好 @Link 下发——见文件头修复条）
  @State private heatMax: number = 0;
  @State private trendPeak: number = 0;
  @State private loaded: boolean = false;
  // 总览/Token 格值数组（先算后赋 @Link 下发——坑16：@Prop 在 PageShell.content 内首帧冻结；
  // 与 overview 等态同帧合并赋值）
  @State private overviewCellsData: UsageStatCell[] = [];
  @State private tokenCellsData: UsageStatCell[] = [];
  // 首卡变动行的上期读数：-1 = 无可比周期 / 查询失败 / 上期零记录；>0 才渲染变动行。
  // prevRangeIndex 记该读数所属时段档，切档瞬间与 rangeIndex 不等即隐藏，防旧数据配新档文案。
  @State private prevTotalTokens: number = -1;
  @State private prevRangeIndex: number = -1;
  // 全部档说明行的记录起点月（由 usageByDay(0) 的最早记录日派生，零新查询；空串 = 无记录）
  @State private firstRecordMonth: string = '';
  // 全库无记录标记（首载多查一炮全量 overview；空态卡唯一条件——单档无数据走零值形态）
  @State private globalEmpty: boolean = false;
  // ── 图表形态切换（两卡各自独立、会话内态不持久化）──
  // 排行卡：false = 占比分段条（默认）/ true = 环形图（官方 DataPanel；饼状图无官方件，见
  // UsageRankRing.ets 头注释）
  @State private rankRingOn: boolean = false;
  // 趋势卡：false = 柱状图（默认）/ true = 折线图（官方 Polyline）
  @State private trendLineOn: boolean = false;
  // 深浅色（卡底/图标块底/主蓝/热力档分治消费）
  @StorageProp('appColorMode') appColorMode: number = 1;
  // 重查序号守卫：快速连切时段时丢弃旧响应（后发查询的响应才算数）
  private loadSeq: number = 0;
  // 分段胶囊选项（近七天 / 近三十天 / 全部）
  private rangeItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '近七天' },
    { text: '近三十天' },
    { text: '全部' }
  ]);

  aboutToAppear(): void {
    this.loadStats();
  }

  private onRangeChange(): void {
    this.loadStats();
  }

  // 时段起点毫秒：近 N 天 = 含今天的最近 N 个本地自然日零点（rangeSinceMs 单源）；全部 = 0 不过滤
  private sinceMs(): number {
    return rangeSinceMs(this.rangeIndex, Date.now());
  }

  private loadStats(): void {
    const seq: number = ++this.loadSeq;
    const reqRange: number = this.rangeIndex;
    const since: number = this.sinceMs();
    const first: boolean = !this.loaded;
    // 第五炮 = 上一周期 token 总量（首卡变动行）。全部档无可比周期直接回 -1 不发 SQL；
    // 单炮独立降级成 -1：上期查询失败只隐藏变动行，不拖垮整页统计（不走下方全页 toast）。
    const prevSince: number = comparisonSinceMs(reqRange, since);
    const prevTotalPromise: Promise<number> = prevSince < 0 ? Promise.resolve(-1) :
      usageTokenTotalBetween(prevSince, since).catch((): number => -1);
    // 五路并行拉取（互不依赖；第 4 炮 = 按日消息数供热力图气泡）；失败 = toast 明示 + 保留旧数据
    Promise.all([usageOverview(since), usageByModel(since), usageByDay(since),
      usageByDayMessageCounts(since), prevTotalPromise])
      .then((results: [UsageOverview, UsageByModelRow[], UsageByDayRow[],
        UsageDayMsgRow[], number]): void => {
          if (this.departed) {
            return;
          }
        if (seq !== this.loadSeq) {
          return; // 已有更新档查询发出，丢弃本次旧响应
        }
        const byDay: UsageByDayRow[] = results[2];
        // 完整逐日轴：近 N 天 = 时段起点~今天；全部 = 固定一年窗口（今天往回 364 天）~今天。
        // ★「全部」原口径「最早记录日~今天」在存量不回填下只有两三列、装不下滚动；固定一年 =
        //   53 列 ≈780vp 必可横滚、早期无记录灰格（GitHub 惯例）
        const todayKey: string = toLocalDayKey(Date.now());
        const startKey: string = axisStartDayKey(this.rangeIndex, since, Date.now());
        const dayRows: DayValue[] = byDay.map((r: UsageByDayRow): DayValue => {
          return { day: r.day, totalTokens: r.totalTokens };
        });
        const axis: DayValue[] = fillDailyRange(startKey, todayKey, dayRows);
        // 热力图三形态分档：近七天 = 单行带状 [axis]、近三十天 = splitIntoCalendarRows 日历网格、
        // 全部 = splitIntoWeekColumns 周列（53 列横滚）——非本档置空数组
        const cols: WeekColumn[] = this.rangeIndex === 2 ? splitIntoWeekColumns(axis) : [];
        const gridRows: (DayValue | null)[][] =
          this.rangeIndex === 1 ? splitIntoCalendarRows(axis) :
            (this.rangeIndex === 0 ? [axis] : []);
        const pts: TrendPoint[] = this.rangeIndex === 2 ? aggregateByMonth(axis) :
          axis.map((d: DayValue): TrendPoint => {
            return { key: d.day, totalTokens: d.totalTokens };
          });
        // 时段最大值 / 趋势峰值（图组件分母，本页算好下发——先算后赋）
        let rangeMax: number = 0;
        for (const d of axis) {
          if (d.totalTokens > rangeMax) {
            rangeMax = d.totalTokens;
          }
        }
        let trendMax: number = 0;
        for (const p of pts) {
          if (p.totalTokens > trendMax) {
            trendMax = p.totalTokens;
          }
        }
        // 连续赋值先算后赋（同帧合并为一次刷新）
        this.overview = results[0];
        this.byModel = results[1];
        this.longestStreakDays = longestStreak(axis);
        this.overviewCellsData = buildOverviewCells(results[0].activeConversations,
          results[0].messageCount, results[0].totalDurationMs, results[0].activeDays,
          results[0].totalTokens, this.longestStreakDays);
        this.tokenCellsData = buildTokenCells(results[0].totalTokens,
          results[0].totalPromptTokens, results[0].totalCompletionTokens, results[0].rounds);
        this.heatColumns = cols;
        this.heatGridRows = gridRows;
        this.trendPoints = pts;
        this.heatMax = rangeMax;
        this.trendPeak = trendMax;
        this.dayMsgCounts = results[3];
        // 上期读数与所属档同帧落地（与 overview 等态一起赋值，杜绝半新半旧）
        this.prevTotalTokens = results[4];
        this.prevRangeIndex = reqRange;
        // 全部档说明行的记录起点：byDay 是 ASC 有记录日全量，首行即最早记录日（零新 SQL）
        this.firstRecordMonth = byDay.length > 0 ? this.firstMonthLabel(byDay[0].day) : '';
        this.loaded = true;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        if (seq !== this.loadSeq) {
          return;
        }
        this.getUIContext().getPromptAction().showToast(
          { message: '用量统计读取失败：' + (e as Error).message });
        this.loaded = true; // 首载失败也进展示态（overview null 分支渲染空态卡）
      });
    if (first) {
      // 全局空库探针（空态卡唯一判据，首载查一次）；失败有界降级：维持 false 走零值形态，不重复弹窗
      usageOverview(0)
        .then((all: UsageOverview): void => {
          if (this.departed) {
            return;
          }
          this.globalEmpty = all.rounds === 0;
        })
        .catch((): void => {
        });
    }
  }

  // 总览 2×3 统计格网 = 公共件 components/stats/StatGrid.ets（两页同形制复用）；格值构造
  // 单源 = UsageStatsCalc.buildOverviewCells / buildTokenCells（后者卡1 取第 1 格放大、
  // 后 3 格走卡内三列，不再挂 StatGrid）。

  // 卡3 用量热力图（标题行 + 网格下方行：左口径备注〔仅全部档〕+ 右「活跃天数 N」蓝字）。
  // 近七天/近三十天 = UsageHeatGrid、全部 = UsageHeatMap（53 列横滚）
  @Builder
  HeatMapCard() {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 2 }) {
          Text('用量热力图')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
          Text('每格代表一天，颜色越深当日 token 用量越多')
            .fontSize(12)
            .fontColor(cardDescColor())
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // 切档转场（官方 transition：if 条件改变触发交叉淡化 250ms EaseOut；Column 透明壳，子件填满）
      if (this.rangeIndex === 2) {
        Column() {
          UsageHeatMap({ columns: $heatColumns, maxTotal: $heatMax,
            dayMsgCounts: $dayMsgCounts })
        }
        .width('100%')
        .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut }))
      } else {
        Column() {
          UsageHeatGrid({ rows: $heatGridRows, maxTotal: $heatMax,
            dayMsgCounts: $dayMsgCounts })
        }
        .width('100%')
        .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut }))
      }
      // 网格下方行：左「网格展示近一年」口径备注（仅全部档）+ 右「活跃天数 N」蓝字
      Row() {
        if (this.rangeIndex === 2) {
          Text('网格展示近一年')
            .fontSize(11)
            .fontColor(cardDescColor())
            .layoutWeight(1)
        } else {
          Column().layoutWeight(1)
        }
        Text('活跃天数 ' + (this.overview === null ? 0 : this.overview.activeDays))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(usageAccentColor(this.appColorMode))
      }
      .width('100%')
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  // 卡2 总览（说明小字置于数据上方——功能设置卡布局次序规约）
  @Builder
  OverviewCard() {
    Column({ space: 10 }) {
      Text('总览')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .width('100%')
      Text('所选时段内的对话与用量规模')
        .fontSize(12)
        .fontColor(cardDescColor())
        .width('100%')
      StatGrid({ cells: $overviewCellsData })
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  // 首卡大字读数（tokenCellsData[0] 与工具单源；空数组兜底 '0'）
  private tokenTotalText(): string {
    return this.tokenCellsData.length > 0 ? this.tokenCellsData[0].value : '0';
  }

  // 变动行可用性：读数属于当前档 + 上期查询成功且有量 + 总览已就绪。全部档回 -1、
  // 切档瞬间档号不等、上期零基线（新装或升级）、查询失败一律隐藏，不写恒真的「增加」。
  private hasComparison(): boolean {
    return this.prevRangeIndex === this.rangeIndex && this.prevTotalTokens > 0 &&
      this.overview !== null;
  }

  private deltaDirection(): number {
    return this.overview === null ? 0 :
      tokenDeltaDirection(this.overview.totalTokens, this.prevTotalTokens);
  }

  private deltaText(): string {
    return this.overview === null ? '' :
      tokenDeltaText(this.overview.totalTokens, this.prevTotalTokens,
        comparisonPeriodLabel(this.rangeIndex));
  }

  // 日键 'YYYY-MM-DD' → 'YYYY年M月'（全部档说明行；月不补零，与月份刻度同款）
  private firstMonthLabel(dayKey: string): string {
    return Number(dayKey.substring(0, 4)) + '年' + Number(dayKey.substring(5, 7)) + '月';
  }

  // 全部档说明行：与变动行共用同一等高占位，把「没有上期可比」换成有用的记录起点。
  // 数据须属于当前档（切档瞬间不拿旧值顶新档）；全库无记录时不显，避免空串文案。
  private hasAllRangeNote(): boolean {
    return this.rangeIndex === 2 && this.prevRangeIndex === this.rangeIndex &&
      this.firstRecordMonth !== '' && !this.hasComparison();
  }

  // 卡1 Token 用量（2026-11-08 改版：标题 + 说明小字 → 大字体总量 → 比前 N 天变动行 →
  // 卡内分割线 → 输入/输出/每条平均三列）。照参考图 2 的大字体与三列形制、图 1 的
  // 变动行样式；不放柱状图、峰值行与标签胶囊（柱状图仍在卡5 用量趋势）。
  // ★ 2026-11-09 反馈笔：卡底与 InfoCard 同取 app.color.info_card_bg、撤 0.5vp 描边
  // （info 卡无描边），深浅两模式随资源色自动分治；总览卡六格仍是 statCellBg 淡一档的蓝。
  @Builder
  TokenCard() {
    Column({ space: 10 }) {
      Text('Token 用量')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .width('100%')
      Text('所选时段内 token 消耗')
        .fontSize(12)
        .fontColor(cardDescColor())
        .width('100%')
      // 大字体总量与 Token 单位：单 Text 双 Span 天然基线平齐。两枚独立 Text 即使用
      // VerticalAlign.Bottom 对的是盒子底，字号差带来的字体下留白会读出「单位浮起来」。
      Text() {
        Span(this.tokenTotalText())
          .fontSize(46)
          .fontWeight(FontWeight.Bold)
          .fontColor(cardTitleColor())
        Span(' Token')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardDescColor())
      }
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
      // 信息行：近七天/近三十天显「比前 N 天」变动（官方 SymbolGlyph 实心箭头 + 次要色
      // 灰字，持平不显箭头）；全部档显记录起点月；上期零记录或查询失败才留空。固定 20vp
      // 等高占位——任何档卡高都不跳（切档不闪）。
      Row({ space: 6 }) {
        if (this.hasComparison()) {
          if (this.deltaDirection() !== 0) {
            SymbolGlyph(this.deltaDirection() > 0 ? $r('sys.symbol.arrowtriangle_up_fill') :
              $r('sys.symbol.arrowtriangle_down_fill'))
              .fontSize(14)
              .fontColor([cardDescColor()])
          }
          Text(this.deltaText())
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardDescColor())
            .maxLines(1)
        } else if (this.hasAllRangeNote()) {
          Text('自 ' + this.firstRecordMonth + ' 起累计')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardDescColor())
            .maxLines(1)
        }
      }
      .height(20)
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Divider()
        .strokeWidth(1)
        .color(cardBorderColor(this.appColorMode))
        .width('100%')
      // 分割线下三列：数值在上、标签在下，列间竖线走官方 borderWidth 左边框。
      // ForEach 键覆盖格值（坑44/80：值随切档变，漏进键即静默冻结）。
      Row() {
        ForEach(this.tokenCellsData.slice(1), (cell: UsageStatCell, index: number): void => {
          Column({ space: 4 }) {
            Text(cell.value)
              .fontSize(21)
              .maxFontSize(21)
              .minFontSize(14)
              .maxLines(1)
              .fontWeight(FontWeight.Bold)
              .fontColor(cardTitleColor())
            Text(cell.label)
              .fontSize(12)
              .fontColor(cardDescColor())
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .padding({ left: index > 0 ? 12 : 0 })
          .borderWidth({ left: index > 0 ? 1 : 0 })
          .borderColor(cardBorderColor(this.appColorMode))
        }, (cell: UsageStatCell): string => cell.key + '|' + cell.value)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    // info 卡色（2026-11-09 反馈笔）：与 InfoCard 共用 app.color.info_card_bg 资源色，
    // 不加渐变、不叠卡底透明度档、不加描边（info 卡无形制描边）；几何 / 字号 / 三列零改动
    .backgroundColor($r('app.color.info_card_bg'))
    .alignItems(HorizontalAlign.Start)
  }

  // 卡4 模型用量排行（Top10 来自 SQL 端 LIMIT；尾行「其余 N 个」= 时段模型总数 − 已展示行数；
  // 项目行样式不做横向进度条〔决明指令，指行内进度条〕；顶部占比分段条 = 列表上方整体分布条，
  // 不属旧指令所指——行式列表零改动）

  // 模型段宽百分比（分母 = 时段总 token，含其余 N 份额；总额 ≤ 0 → '0'；2 位小数防小占比丢精度）
  private pctWidth(row: UsageByModelRow): string {
    const total: number = this.overview === null ? 0 : this.overview.totalTokens;
    if (total <= 0) {
      return '0';
    }
    return (row.totalTokens / total * 100).toFixed(2);
  }

  // 「其余 N 个模型」灰段宽 = 100 − ΣTop10 段宽（clamp ≥ 0；与尾行文字同条件渲染）
  private restPct(): string {
    const total: number = this.overview === null ? 0 : this.overview.totalTokens;
    if (total <= 0) {
      return '0';
    }
    let sum: number = 0;
    for (const row of this.byModel) {
      sum += row.totalTokens / total * 100;
    }
    const rest: number = 100 - sum;
    return (rest < 0 ? 0 : rest).toFixed(2);
  }
  @Builder
  ModelRankCard() {
    Column({ space: 10 }) {
      // 标题行 + 卡右上角图表切换键（标题 layoutWeight(1) 撑满；键形 = TEXTUAL SymbolGlyph 18 +
      // font_secondary。图标示目标形态：占比条态显 circle_on_circle，环形态显 rectangle_3_group
      // ——系统符号表无 chart 类字形，取最近义）
      Row() {
        Text('模型用量排行')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        Button() {
          SymbolGlyph(this.rankRingOn ? $r('sys.symbol.rectangle_3_group') :
            $r('sys.symbol.circle_on_circle'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .onClick((): void => {
          this.rankRingOn = !this.rankRingOn;
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text('Top 10 · 按总 token 排序')
        .fontSize(12)
        .fontColor(cardDescColor())
        .width('100%')
      // 图形态分支（总额 ≤ 0 两形态均不渲染；切换转场 = 同款官方 transition 交叉淡化 250ms）
      if (this.overview !== null && this.overview.totalTokens > 0) {
        if (this.rankRingOn) {
          Column() {
            UsageRankRing({ byModel: $byModel, overview: $overview })
          }
          .width('100%')
          .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut }))
        } else {
          // 占比分段条：分母 = overview.totalTokens（含其余 N 份额）→ Top10 各段主蓝 + 其余 N 灰段
          // badgeBg；段宽 = 占比%（2 位小数），Row space 2 分段间隙（卡底色漏出 = 天然分段线）
          Row({ space: 2 }) {
            ForEach(this.byModel, (row: UsageByModelRow): void => {
              Row()
                .width(this.pctWidth(row) + '%')
                .height(8)
                .backgroundColor(usageAccentColor(this.appColorMode))
            }, (row: UsageByModelRow): string =>
              row.modelId + '|' + row.totalTokens + '|' + row.promptTokens + '|' +
              row.completionTokens)
            if (this.overview !== null && this.overview.usedModels > this.byModel.length) {
              Row()
                .width(this.restPct() + '%')
                .height(8)
                .backgroundColor(badgeBg(this.appColorMode))
            }
          }
          .width('100%')
          .borderRadius(4)
          .clip(true)
          .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut }))
        }
      }
      if (this.byModel.length === 0) {
        Text('暂无模型维度记录')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      } else {
        ForEach(this.byModel, (row: UsageByModelRow, index: number): void => {
          Row() {
            // 排名数字全灰（1~3 不再主蓝——焦点在占比条与总量，名次不抢色）
            Text('' + (index + 1))
              .fontSize(14)
              .fontWeight(index < 3 ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(cardDescColor())
              .width(24)
            Column({ space: 2 }) {
              Text(row.modelId !== '' ? row.modelId : '未知模型')
                .fontSize(15)
                .fontColor(cardTitleColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text('输入 ' + fmtCompact(row.promptTokens) + ' · 输出 ' +
                fmtCompact(row.completionTokens))
                .fontSize(12)
                .fontColor(cardDescColor())
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text(fmtCompact(row.totalTokens))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }, (row: UsageByModelRow): string =>
          row.modelId + '|' + row.totalTokens + '|' + row.promptTokens + '|' +
          row.completionTokens)
        if (this.overview !== null && this.overview.usedModels > this.byModel.length) {
          Text('其余 ' + (this.overview.usedModels - this.byModel.length) + ' 个模型未展示')
            .fontSize(12)
            .fontColor(cardDescColor())
            .width('100%')
        }
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  // 卡5 用量趋势（峰值行/图区/范围行在图表件；卡右上角切换键在柱状 ↔ 折线间切换——图标示目标
  // 形态：柱状态 arrow_up_right / 折线态 rectangle_3_group）
  @Builder
  TrendCard() {
    Column({ space: 10 }) {
      Row() {
        Text('用量趋势')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        Button() {
          SymbolGlyph(this.trendLineOn ? $r('sys.symbol.rectangle_3_group') :
            $r('sys.symbol.arrow_up_right'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .onClick((): void => {
          this.trendLineOn = !this.trendLineOn;
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text('近七天与近三十天按天汇总，全部按月汇总')
        .fontSize(12)
        .fontColor(cardDescColor())
        .width('100%')
      // 图形态分支（切换转场 = 排行卡/热力图同款官方 transition 交叉淡化）
      if (this.trendLineOn) {
        Column() {
          UsageLineChart({ points: $trendPoints, peak: $trendPeak })
        }
        .width('100%')
        .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut }))
      } else {
        Column() {
          UsageBarChart({ points: $trendPoints, peak: $trendPeak })
        }
        .width('100%')
        .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut }))
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  Content() {
    Stack({ alignContent: Alignment.Top }) {
      // 内容滚动层：顶部留白 = 分段胶囊位（topPad）+ SEGMENT_BAR_HEIGHT(40) + 卡间距——内容初始
      // 静止在分段胶囊下方（胶囊经标题栏下方带承载）
      Scroll() {
        Column({ space: CARD_SPACING }) {
          if (!this.loaded) {
            Text('正在读取统计数据…')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
          } else if (this.globalEmpty || this.overview === null) {
            // 空态卡（官方正色卡底——禁灰置）：全库无任何用量记录（或首载失败）才显示；存量不回填
            // 口径下升级后空态属正常形态
            Column({ space: 8 }) {
              Text('暂无统计数据')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
              Text('对话完成后会自动记录每次回复的 token 用量与生成速度。升级前产生的历史对话不参与统计。')
                .fontSize(13)
                .fontColor(cardDescColor())
            }
            .alignItems(HorizontalAlign.Start)
            .width(CARD_PANEL_WIDTH)
            .padding(16)
            .backgroundColor(cardBg(this.appColorMode))
            .borderRadius(CARD_RADIUS)
          } else {
            this.TokenCard()
            this.OverviewCard()
            this.HeatMapCard()
            this.ModelRankCard()
            this.TrendCard()
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .padding({
          top: Math.max(this.topPad, 0) + SEGMENT_BAR_HEIGHT + CARD_SPACING,
          bottom: this.bottomPad + 16
        })
      }
      .width('100%')
      .height('100%')
      // 滚动内容不足视口时顶对齐（坑18：Scroll align 默认 Center 会垂直居中）
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  build() {
    PageShell({
      title: SETTING_TITLE_USAGE_STATS,
      // 标题栏下方带承载；下移量 16 = 本页现状档
      titleBarBottom: (): void => {
        this.TopSegmentBand();
      },
      titleBarBottomInset: SEGMENT_BAR_BAND_TOP_INSET_STATS,
      content: (): void => {
        this.Content();
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
