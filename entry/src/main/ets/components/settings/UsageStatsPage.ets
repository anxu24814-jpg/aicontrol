// 用量统计页（设置页「用量统计」卡 push；2026-09-06 首笔纯列表版，同日按任务书-用量统计
// 页改版重写为五板块时段联动版）：顶部光感分段胶囊（近七天/近三十天/全部，公共件
// SegmentBar 复用；★2026-09-07 决明指令改吸顶——Stack 悬浮固定层不随内容滚动，先例
// AppearancePage/LogPageContent 定型姿势）切时段，五卡全部联动重查。板块自上而下 =
// 活动热力图（★2026-09-07「满日历」三形态：近七天 = 单行 7 格带状、近三十天 = 日历网格
// 〔列=周一~周日 6 行〕——Grid 1fr×7 + aspectRatio 自适应铺满；全部 = 53 列周列横滚）→ 总览
// 2×3（2026-09-07 决明：活跃天数拆换为累计生成时长/每日平均 token/最长连续活跃三格 = 6 格）
// → Token 用量 2×2（含每条平均）→ 模型用量排行 Top10（项目行样式，
// 不做横向进度条；2026-09-07 顶部加占比分段条；2026-09-08 卡右上角切换键在占比条 ↔ 环形图
// 间切换——官方 DataPanel 承托，饼状图无官方件，调研结论见 UsageRankRing.ets 头注释）
// → 用量趋势柱状图（逐日/逐月随时段，含峰值；2026-09-08 卡右上角切换键在柱状 ↔ 折线
// 〔官方 Polyline，组件 UsageLineChart〕间切换）。板块组织参照决明供图
// 参考稿（只取布局组织，不复刻尺寸）。
// · 数据单源 = common/store/UsageStatsDb.ets（usageOverview/usageByModel/usageByDay
//   三聚合带 sinceMs 时段参，口径见其头注释）；轴/格/聚合纯函数 =
//   common/store/UsageStatsCalc.ets（公式见各函数头注释，scripts/usage-stats-calc-check.mjs
//   机械断言钉死）；
// · 切档联动：rangeIndex @Watch → 三聚合并行重查，保留旧数据静默刷新不闪加载态；
//   loadSeq 序号守卫防快速连切时旧响应覆盖新数据；失败 toast 明示 + 保留旧数据
//   （首载失败按空态展示，原口径沿用）；
// · 空态 = 全时段也无任何用量记录才显示（globalEmpty：首载额外一炮全量 overview 判
//   rounds===0；官方正色卡禁灰置——存量不回填口径下升级后空态属正常形态而非异常）；
//   单档无数据正常渲染零值形态（零值柱/灰格/0 数字）；
// · 图组件与格值刷新通道：UsageHeatMap/UsageBarChart 数据 @Link（$ 语法）下发——★坑16
//   热点（PageShell.content @BuilderParam 内子组件 @Prop 首帧冻结实锤，禁 @Prop）；
//   卡内动态数值一律 ForEach（键含内容变化即重建）——@Builder 值参直调动态文本同族
//   黑名单免疫；
// ★ 2026-09-07 修复（决明真机反馈「热力图显示不全/首载全灰/数据不切换」三问，五轮自检
//   见当日节）：时段最大值 heatMax / 趋势峰值 trendPeak 由本页在 loadStats 完成时算好、
//   @Link 下发——原实现 = 图组件 @Watch 内算普通成员，@Watch 对首帧初始化不触发（官方
//   《@Watch 触发时机》实锤），首载档（loaded 未置位不渲染图组件 → Promise 完成后首次
//   创建）分母停在 0 → 热力图 heatLevel(x,0)=0 全灰、趋势柱全落 3vp 零值条；切档后
//   组件已存在 @Watch 才触发而正常。父算下发 = 初值即正确值，不依赖任何 @Watch 时序；
//   状态最小化条：两值按「先算后赋」与既有五态同帧合并赋值（本页现有姿势）。
// · 无编辑无保存动作 → 返回无参 pop 不挂 onPop（坑17 口径「无数据变化不加 result」）；
// · 各卡说明小字置于数据上方（功能设置卡布局次序规约）。
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { PageShell } from '../../common/PageShell';
import { SETTING_TITLE_USAGE_STATS } from '../../common/SettingSearch';
import { CARD_PANEL_WIDTH, CARD_SPACING, SEGMENT_BAR_HEIGHT, badgeBg, cardBg, cardDescColor,
  cardTitleColor, usageAccentColor } from '../../common/Theme';
import { UsageByDayRow, UsageByModelRow, UsageDayMsgRow, UsageOverview, usageByDay,
  usageByDayMessageCounts, usageByModel, usageOverview } from '../../common/store/UsageStatsDb';
import { DayValue, TrendPoint, UsageStatCell, WeekColumn, aggregateByMonth, axisStartDayKey,
  buildOverviewCells, buildTokenCells, fillDailyRange, fmtCompact, longestStreak, rangeSinceMs,
  splitIntoCalendarRows, splitIntoWeekColumns, toLocalDayKey } from '../../common/store/UsageStatsCalc';
import { SegmentBar } from '../SegmentBar';
import { StatGrid } from '../stats/StatGrid';
import { UsageBarChart } from '../stats/UsageBarChart';
import { UsageHeatGrid } from '../stats/UsageHeatGrid';
import { UsageHeatMap } from '../stats/UsageHeatMap';
import { UsageLineChart } from '../stats/UsageLineChart';
import { UsageRankRing } from '../stats/UsageRankRing';

// 总览/Token 卡格数据（StatGrid 的 ForEach 数据源；★2026-09-07 决明拍板：8 卡去图标——
// icon 字段随图标行一并删除，排版改「上标签下数值」。★2026-09-08 类型与格值构造上收
// UsageStatsCalc〔UsageStatCell + buildOverviewCells/buildTokenCells〕——用量统计工具同源
// 消费，见 2026-09-08 工具笔）

@Component
export struct UsageStatsPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 时段档（0 近七天默认 / 1 近三十天 / 2 全部）：@Watch 切档即三聚合并行重查
  @State @Watch('onRangeChange') private rangeIndex: number = 0;
  @State private overview: UsageOverview | null = null;
  @State private byModel: UsageByModelRow[] = [];
  // 热力图周列 / 趋势点（图组件 @Link 下发）+ 完整逐日轴（统计行「最长连续」同源）
  @State private heatColumns: WeekColumn[] = [];
  // 满日历行表（近七天 = 单行带状 [axis]、近三十天 = splitIntoCalendarRows 日历网格；
  // 全部档周列走 heatColumns——两种形态分档分支渲染）
  @State private heatGridRows: (DayValue | null)[][] = [];
  // 按日消息数（messages 表 user+assistant 当日 COUNT——热力图点击气泡「当天消息总数」，
  // 与总览 messageCount 同口径；三档同 since，与 usageByDay 并行查询同源下发）
  @State private dayMsgCounts: UsageDayMsgRow[] = [];
  @State private trendPoints: TrendPoint[] = [];
  // 最长连续活跃天数（loadStats 局部算好存此——总览「最长连续活跃」格消费；calc 层
  // longestStreak 复用，无需恢复整轴 @State）
  @State private longestStreakDays: number = 0;
  // 时段最大值 / 趋势峰值（图组件 heatLevel/柱高 分母；本页算好 @Link 下发——见头注释
  // 2026-09-07 修复：图组件自算的 @Watch 版首帧不触发，首载全灰）
  @State private heatMax: number = 0;
  @State private trendPeak: number = 0;
  @State private loaded: boolean = false;
  // 总览/Token 格值数组（2026-09-10 费用估计笔随 StatGrid 公共件提取改 @State 先算后赋
  // @Link 下发——坑16：@Builder 值参直调的旧免疫姿势不可迁移到子组件，@Prop 在
  // PageShell.content 内首帧冻结；与 overview 等态同帧合并赋值〔状态最小化条〕）
  @State private overviewCellsData: UsageStatCell[] = [];
  @State private tokenCellsData: UsageStatCell[] = [];
  // 全库无记录标记（首载多查一炮全量 overview；空态卡唯一条件——单档无数据走零值形态）
  @State private globalEmpty: boolean = false;
  // ── 图表形态切换（2026-09-08 决明指令「排行加饼状图切换 / 趋势加柱状折线切换，卡右上角
  // 切换图标」）：两卡各自独立、会话内态不持久化（与 rangeIndex 同口径——形态偏好随次进入
  // 回默认柱状，避免偏好面扩散）──
  // 排行卡：false = 占比分段条（默认）/ true = 环形图（官方 DataPanel——饼状图无官方件，
  // 调研结论见 UsageRankRing.ets 头注释）
  @State private rankRingOn: boolean = false;
  // 趋势卡：false = 柱状图（默认）/ true = 折线图（官方 Polyline）
  @State private trendLineOn: boolean = false;
  // 深浅色（卡底/图标块底/主蓝/热力档分治消费；原纯列表版同款订阅键）
  @StorageProp('appColorMode') appColorMode: number = 1;
  // 重查序号守卫：快速连切时段时丢弃旧响应（后发查询的响应才算数）
  private loadSeq: number = 0;
  // 分段胶囊选项（任务书死参数：近七天/近三十天/全部；SegmentButtonV2Items 构造照
  // LogPageContent 先例）
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

  // 时段起点毫秒：近 N 天 = 含今天的最近 N 个本地自然日零点（rangeSinceMs 单源，与
  // get_usage_stats 工具同口径）；全部 = 0 不过滤
  private sinceMs(): number {
    return rangeSinceMs(this.rangeIndex, Date.now());
  }

  private loadStats(): void {
    const seq: number = ++this.loadSeq;
    const since: number = this.sinceMs();
    const first: boolean = !this.loaded;
    // 四聚合并行拉取（互不依赖；第 4 炮 = 按日消息数供热力图气泡——同 since 同口径）；
    // 失败 = toast 明示 + 保留旧数据（P0-1 不静默假成功）
    Promise.all([usageOverview(since), usageByModel(since), usageByDay(since),
      usageByDayMessageCounts(since)])
      .then((results: [UsageOverview, UsageByModelRow[], UsageByDayRow[],
        UsageDayMsgRow[]]): void => {
        if (seq !== this.loadSeq) {
          return; // 已有更新档查询发出，丢弃本次旧响应
        }
        const byDay: UsageByDayRow[] = results[2];
        // 完整逐日轴：近 N 天 = 时段起点~今天；全部 = 近一年窗口（今天往回 364 天）~今天。
        // ★2026-09-07 决明真机反馈「全部只显示两格、滚不动」改口径：原「全部 = 最早记录日~
        //   今天」（统计 9/6 上线、存量不回填 → 仅有记录两天 → 2 列 27vp 装不下滚动且观感
        //   「显示不全」）；改固定一年窗口 = 53 列 ≈780vp 必可横向滚动、早期无记录灰格
        //   （GitHub 惯例，历史不足一年时即完整全部），进页 scrollEdge 定位最右不变。
        const todayKey: string = toLocalDayKey(Date.now());
        const startKey: string = axisStartDayKey(this.rangeIndex, since, Date.now());
        const dayRows: DayValue[] = byDay.map((r: UsageByDayRow): DayValue => {
          return { day: r.day, totalTokens: r.totalTokens };
        });
        const axis: DayValue[] = fillDailyRange(startKey, todayKey, dayRows);
        // 热力图三形态分档构建（★2026-09-07「满日历」方案，决明拍板）：近七天 = 单行带状
        // [axis]（7 格横排铺满）、近三十天 = 日历网格 splitIntoCalendarRows（列=周一~周日、
        // 6 行铺满）、全部 = 周列 splitIntoWeekColumns（53 列横滚，用户满意形态不动）——
        // 非本档置空数组（图组件按档分支渲染，未用档零渲染零遍历）
        const cols: WeekColumn[] = this.rangeIndex === 2 ? splitIntoWeekColumns(axis) : [];
        const gridRows: (DayValue | null)[][] =
          this.rangeIndex === 1 ? splitIntoCalendarRows(axis) :
            (this.rangeIndex === 0 ? [axis] : []);
        const pts: TrendPoint[] = this.rangeIndex === 2 ? aggregateByMonth(axis) :
          axis.map((d: DayValue): TrendPoint => {
            return { key: d.day, totalTokens: d.totalTokens };
          });
        // 时段最大值 / 趋势峰值（图组件分母，本页算好下发——先算后赋，见头注释修复条）
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
        // 连续赋值先算后赋（状态最小化条：同帧合并为一次刷新）——格值数组同帧组好
        //（StatGrid @Link 下发，buildOverviewCells/buildTokenCells 构造单源不变）
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
        this.loaded = true;
      })
      .catch((e: Object): void => {
        if (seq !== this.loadSeq) {
          return;
        }
        this.getUIContext().getPromptAction().showToast(
          { message: '用量统计读取失败：' + (e as Error).message });
        this.loaded = true; // 首载失败也进展示态（overview null 分支渲染空态卡）
      });
    if (first) {
      // 全局空库探针（空态卡唯一判据；数据只增不减，首载查一次即可）
      usageOverview(0)
        .then((all: UsageOverview): void => {
          this.globalEmpty = all.rounds === 0;
        })
        .catch((): void => {
          // 探针失败有界降级：globalEmpty 维持 false 走零值形态（读库失败主查询通道
          // 已 toast 明示，此处不重复弹窗）
        });
    }
  }

  // 2×2 统计格网已提取公共件 components/stats/StatGrid.ets（2026-09-10 费用估计笔——两页
  // 同形制复用）；格值构造单源仍 = UsageStatsCalc.buildOverviewCells/buildTokenCells，
  // 本页在 loadStats 先算后赋 @Link 下发（见 overviewCellsData/tokenCellsData 注释）

  // 卡1 用量热力图（标题行 = 左标题说明列；网格下方行 = 左口径备注 [仅全部档] + 右
  // 「活跃天数 N」蓝字）。★2026-09-07 决明：标题「活动」→「用量」；图例（少→多）曾移
  // 入标题行右上后拍板移除（本页与两组件均不再含图例，零残留）；蓝字去「最长连续」改
  // 「活跃天数 数字」。近七天/近三十天 = UsageHeatGrid（带状/日历网格铺满）、全部 =
  // UsageHeatMap（53 列周列横滚）
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
      // 切档转场（★2026-09-07 决明：铺满网格 ↔ 53 列横滚形态跳变突兀——官方 transition，
      // if 条件改变触发插入/删除动画：旧组件淡出 + 新组件淡入交叉淡化；250ms EaseOut 与
      // 官方胶囊滑块动画（enableStateAnimation）时长协调。Column 为透明壳（官方文档
      // 「if 条件改变递归触发过渡」，先例零——标准容器姿势最无歧义），子组件 width 100%
      // 填满，布局不变）
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
      // 网格下方行：左「网格展示近一年」口径备注（仅全部档——原图例行空位续用）+
      // 右「活跃天数 N」蓝字（★2026-09-07 决明：去「最长连续」，活跃天数字样）
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
    .borderRadius(16)
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
    .borderRadius(16)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  // 卡3 Token 用量
  @Builder
  TokenCard() {
    Column({ space: 10 }) {
      Text('Token 用量')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .width('100%')
      Text('所选时段内 token 消耗与每条平均用量')
        .fontSize(12)
        .fontColor(cardDescColor())
        .width('100%')
      StatGrid({ cells: $tokenCellsData })
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(16)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  // 卡4 模型用量排行（Top10 来自 SQL 端 LIMIT；尾行「其余 N 个」= 时段模型总数 − 已展示
  // 行数；项目行样式，不做横向进度条——决明指令（2026-09-06，指行内进度条，依旧有效）；
  // ★2026-09-07 决明拍板新增顶部占比分段条 = 列表上方整体分布条，不属旧指令所指——行式
  // 列表零改动，条与下方排行/尾行语义闭环）

  // 模型段宽百分比（分母 = 时段总 token，含其余 N 份额；总额 ≤ 0 → '0'；2 位小数防小
  // 占比丢精度——纯展示字符串，Width 百分比语法消费）
  private pctWidth(row: UsageByModelRow): string {
    const total: number = this.overview === null ? 0 : this.overview.totalTokens;
    if (total <= 0) {
      return '0';
    }
    return (row.totalTokens / total * 100).toFixed(2);
  }

  // 「其余 N 个模型」灰段宽 = 100 − ΣTop10 段宽（clamp ≥ 0 防浮点累积超界；仅视觉闭环，
  // 与尾行文字同条件渲染）
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
      // 标题行 + 卡右上角图表切换键（外观页 c839bf6「整卡右上角」定稿姿势：标题
      // layoutWeight(1) 撑满 + 键落整卡右上角；键形 = InfoHintButton 同款 TEXTUAL
      // SymbolGlyph 18 + font_secondary。图标示目标形态——占比条态显示环形图标
      // circle_on_circle，环形态显示柱状图标 rectangle_3_group；系统符号表无 chart 类
      // 字形，取形最近义字形——调研记变更记录）
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
      // 图形态分支（总额 ≤ 0 两形态均不渲染——与原占比条同条件；切换转场 = 热力图
      // 分档切换同款官方 transition 交叉淡化 250ms EaseOut）
      if (this.overview !== null && this.overview.totalTokens > 0) {
        if (this.rankRingOn) {
          Column() {
            UsageRankRing({ byModel: $byModel, overview: $overview })
          }
          .width('100%')
          .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut }))
        } else {
          // 占比分段条（★2026-09-07 决明「卡片上部加比例条，下面 1、2、3 排行保留」）：分母 =
          // overview.totalTokens（含其余 N 份额）→ Top10 各段主蓝 + 其余 N 灰段 badgeBg；
          // 段宽 = 占比%（2 位小数），Row space 2 分段间隙（卡底色漏出 = 天然分段线）；
          // 「其余」占比 ≤ 0 不渲染灰段（与尾行文字同条件）
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
            // 排名数字全灰（★2026-09-07 决明：1~3 不再主蓝——焦点回到占比条与总量，
            // 名次不抢色）
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
    .borderRadius(16)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  // 卡5 用量趋势（峰值行/图区/范围行在 UsageBarChart/UsageLineChart；卡右上角切换键
  // 在柱状 ↔ 折线间切换——图标示目标形态：柱状态 arrow_up_right〔趋势线最近义〕/
  // 折线态 rectangle_3_group）
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
    .borderRadius(16)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  Content() {
    // Stack 叠加（先例 = AppearancePage:225-268/LogPageContent 吸顶定型姿势）：内容滚动层
    // + 分段胶囊悬浮固定层——胶囊不随内容滚动；内容向上滚时从胶囊背后穿过（实底态被
    // 胶囊遮住、光感态经背板材质模糊透出）。★2026-09-07 决明指令改吸顶：任务书「放滚动
    // 内容第一个元素（不吸顶）」参数作废，偏差登记变更记录当日节。
    Stack({ alignContent: Alignment.Top }) {
      // 内容滚动层：顶部留白 = 胶囊悬浮位置（topPad，与原静止位一致）+ 胶囊总高
      // SEGMENT_BAR_HEIGHT(40) + 卡间距 CARD_SPACING——内容初始静止在胶囊下方，
      // 滚动时滑入胶囊背后
      Scroll() {
        Column({ space: CARD_SPACING }) {
          if (!this.loaded) {
            Text('正在读取统计数据…')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
          } else if (this.globalEmpty || this.overview === null) {
            // 空态卡（官方正色卡底——禁灰置）：全库无任何用量记录（或首载失败）才显示；
            // 存量不回填口径下升级后空态属正常形态而非异常
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
            .borderRadius(16)
          } else {
            this.HeatMapCard()
            this.OverviewCard()
            this.TokenCard()
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

      // ── 分段胶囊悬浮固定层：Stack 顶层（后声明在上），顶部对齐，位置 = 原静止位置
      //（topPad）；宽度约束 = CARD_PANEL_WIDTH（官方无宽度参数且 width 通用属性无效）——
      // SegmentBar 公共件参数定稿勿调（唯一来源 components/SegmentBar.ets）
      Column() {
        SegmentBar({ items: this.rangeItems, selectedIndex: $rangeIndex })
      }
      .width(CARD_PANEL_WIDTH)
      .margin({ top: this.topPad })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    PageShell({
      title: SETTING_TITLE_USAGE_STATS,
      content: (): void => {
        this.Content();
      }
    })
  }
}
