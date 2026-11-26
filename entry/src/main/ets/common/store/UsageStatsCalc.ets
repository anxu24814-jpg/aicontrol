// 用量统计页纯函数计算模块。职责缝 = 「时段轴 / 热力周列与日历网格 / 趋势聚合 / 数值
// 格式化」的公式层——零 import 零 UI 依赖，专为 scripts/usage-stats-calc-check.mjs 机械
// 求值断言而设：剥注释/类型标注后 new Function 即跑，故本文件★禁加 import★、类型标注
// 只用该脚本 TYPE_RE 白名单内形态。
// 时段口径（拍板为法）：近 N 天 = 含今天的最近 N 个本地自然日（dayStartMs 零点 +
// setDate 回退，禁 86400000 固定减——跨月跨年交给 Date 进位）；全部 = 不过滤（sinceMs=0；
// 热力图轴 = 近一年窗口，见 axisStartDayKey）。日键 = 'YYYY-MM-DD' 本地时区，与
// UsageStatsDb 逐日聚合同口径——两侧可逐键对账。
// 时段起点（rangeSinceMs）/日轴起点（axisStartDayKey）/上期比较（comparisonSinceMs 与
// 变动文案族）/统计卡构造（buildOverviewCells / buildTokenCells / buildCostCells）与金额
// 格式化（formatCostValue）收口本文件——页面与 get_usage_stats / get_cost_stats 工具共用
// 同一套口径与文案，两处读数逐格一致（工具域实现在 common/providers/ToolUsageStats.ets）。
// 金额格式化与 CostStatsCalc.fmtCost 双写
//（两件都是零 import 纯函数文件无共享通道），一致性由 assert-app-domain 84 组对拍钉死。

// 逐日数据点（day = 'YYYY-MM-DD' 本地时区；totalTokens = 当日总 token，无记录日补 0）
export interface DayValue {
  day: string;
  totalTokens: number;
}

// 趋势数据点（key 逐日档 = 'YYYY-MM-DD'、逐月档 = 'YYYY-MM'——卡底范围行原样展示首末 key）
export interface TrendPoint {
  key: string;
  totalTokens: number;
}

// 热力图周列（恒 7 格 = 周一~周日自上而下，null = 时段范围外空位保对位；
// key = 首格非空日，ForEach 键稳定唯一）
export interface WeekColumn {
  key: string;
  cells: (DayValue | null)[];
}

// 统计卡单元格（页面 StatGrid 与 get_usage_stats 工具共用——格文案/单位/数值格式单源）
export interface UsageStatCell {
  key: string; // 格身份（标签名，卡内唯一）
  label: string;
  value: string;
  unit: string;
}

// token 数值紧凑格式化（任务书死参数）：n < 1000 原样；1000 ≤ n < 999500 → k 档一位小数
//（四舍五入到百位再除 10）；n ≥ 999500 → M 档一位小数（999500 进位 1M——k 档封顶 999.5k）。
// k 小写 M 大写；与消息行 meta 旧 fmtTokens 不共用不互改。
export function fmtCompact(n: number): string {
  if (n < 1000) {
    return '' + n;
  }
  if (n < 999500) {
    return (Math.round(n / 100) / 10) + 'k';
  }
  return (Math.round(n / 100000) / 10) + 'M';
}

// 本地自然日零点毫秒：setHours 清零后 setDate 回退 backDays 天（跨月/跨年由 Date 自动
// 进位，禁 86400000×N 固定减）。公式：dayStartMs(ms, 0) = 当日 00:00:00.000 本地。
export function dayStartMs(ms: number, backDays: number): number {
  const d: Date = new Date(ms);
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() - backDays);
  return d.getTime();
}

// 毫秒 → 本地日键 'YYYY-MM-DD'（月日补零；与 dayStartMs 同源可互算）
export function toLocalDayKey(ms: number): string {
  const d: Date = new Date(ms);
  const m: number = d.getMonth() + 1;
  const day: number = d.getDate();
  return d.getFullYear() + '-' + (m < 10 ? '0' + m : '' + m) + '-' +
    (day < 10 ? '0' + day : '' + day);
}

// 日键 → 本地零点 Date（拆段数值构造，避 new Date('YYYY-MM-DD') 按 UTC 解析的坑）
function parseDayKey(key: string): Date {
  const parts: string[] = key.split('-');
  return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
}

// 逐日轴补齐：startKey~endKey（含两端）完整日序列，无记录日补 0；rows 按键查表（顺序
// 无关），范围外记录忽略；startKey 晚于 endKey 返回空数组。
export function fillDailyRange(startKey: string, endKey: string, rows: DayValue[]): DayValue[] {
  const byDay: Map<string, number> = new Map();
  for (const r of rows) {
    byDay.set(r.day, r.totalTokens);
  }
  const result: DayValue[] = [];
  const cur: Date = parseDayKey(startKey);
  const end: Date = parseDayKey(endKey);
  while (cur.getTime() <= end.getTime()) {
    const key: string = toLocalDayKey(cur.getTime());
    const hit: number | undefined = byDay.get(key);
    result.push({ day: key, totalTokens: hit === undefined ? 0 : hit });
    cur.setDate(cur.getDate() + 1);
  }
  return result;
}

// 完整日轴 → 热力图周列（周一顶对齐）：首列前导 null 数 = 首日星期偏移（周一 = 0 …
// 周日 = 6；JS getDay() 周日 = 0 → (getDay()+6)%7 换算）；每满 7 格封一列；尾列不足 7 格
// 补 null 保对位；列 key = 该列首格非空日。
export function splitIntoWeekColumns(days: DayValue[]): WeekColumn[] {
  const columns: WeekColumn[] = [];
  if (days.length === 0) {
    return columns;
  }
  const offset: number = (parseDayKey(days[0].day).getDay() + 6) % 7;
  let cells: (DayValue | null)[] = [];
  let key: string = '';
  for (let i: number = 0; i < offset; i++) {
    cells.push(null);
  }
  for (const d of days) {
    if (cells.length === 7) {
      columns.push({ key: key, cells: cells });
      cells = [];
      key = '';
    }
    if (key === '') {
      key = d.day;
    }
    cells.push(d);
  }
  if (cells.length > 0) {
    while (cells.length < 7) {
      cells.push(null);
    }
    columns.push({ key: key, cells: cells });
  }
  return columns;
}

// 完整日轴 → 热力图日历行网格（近三十天「满日历」形态；与 splitIntoWeekColumns 对偶——
// 同款偏移/封行/补 null 逻辑，仅「每 7 格封一行」而非封一列）：行 = 周（首行前导 null 数 =
// 首日星期偏移，周一列顶对齐）、列 = 周一~周日；尾行不足 7 格补 null 保对位；输出行表供
// 月网格组件按行渲染（列少时格子放大铺满卡宽）。
export function splitIntoCalendarRows(days: DayValue[]): (DayValue | null)[][] {
  const rows: (DayValue | null)[][] = [];
  if (days.length === 0) {
    return rows;
  }
  const offset: number = (parseDayKey(days[0].day).getDay() + 6) % 7;
  let cells: (DayValue | null)[] = [];
  for (let i: number = 0; i < offset; i++) {
    cells.push(null);
  }
  for (const d of days) {
    if (cells.length === 7) {
      rows.push(cells);
      cells = [];
    }
    cells.push(d);
  }
  if (cells.length > 0) {
    while (cells.length < 7) {
      cells.push(null);
    }
    rows.push(cells);
  }
  return rows;
}

// 最长连续活跃天数：完整日轴上 totalTokens > 0 的最长连续段长度（遇零清零重计）
export function longestStreak(days: DayValue[]): number {
  let best: number = 0;
  let cur: number = 0;
  for (const d of days) {
    if (d.totalTokens > 0) {
      cur++;
      if (cur > best) {
        best = cur;
      }
    } else {
      cur = 0;
    }
  }
  return best;
}

// 逐日轴 → 逐月聚合（'YYYY-MM' = 日键前 7 位；同月求和；输出升序——输入轴升序 + Map
// 插入序保持，无需另排序）
export function aggregateByMonth(days: DayValue[]): TrendPoint[] {
  const sums: Map<string, number> = new Map();
  for (const d of days) {
    const month: string = d.day.substring(0, 7);
    const prev: number | undefined = sums.get(month);
    sums.set(month, (prev === undefined ? 0 : prev) + d.totalTokens);
  }
  const result: TrendPoint[] = [];
  sums.forEach((value: number, key: string): void => {
    result.push({ key: key, totalTokens: value });
  });
  return result;
}

// 热力档位：max ≤ 0 或 value ≤ 0 → 0（空档灰）；否则 ceil(value/max×4) 钳位 1~4
//（value = max 恒 4；ceil 保「有量即至少一档亮」）
export function heatLevel(value: number, max: number): number {
  if (max <= 0 || value <= 0) {
    return 0;
  }
  const level: number = Math.ceil((value / max) * 4);
  return level > 4 ? 4 : level;
}

// 平均每条 = 时段总 token ÷ 轮数（events 行数，一次发送一条）；轮数 ≤ 0 → 0（除零守卫）
export function avgPerRound(totalTokens: number, rounds: number): number {
  if (rounds <= 0) {
    return 0;
  }
  return Math.round(totalTokens / rounds);
}

// 平均每会话消息数 = 时段消息数 ÷ 活跃会话数（两个入参都是总览卡既有口径——消息数走
// messages 表 user+assistant 时段 COUNT、活跃会话走 events 时段 DISTINCT，本函数零新查询）；
// 会话 ≤ 0 → 0（除零守卫）；一位小数——小值保留小数不塌成 0 或整数，千级以上由调用点
// fmtCompact 走紧凑档。口径边界：全部档下升级前存量消息计入分子而其所在会话（无用量记录）
// 不在分母——存量回填缺失所致，见变更记录一百八十六节
export function avgMessagesPerConversation(messageCount: number, conversations: number): number {
  if (conversations <= 0) {
    return 0;
  }
  return Math.round(messageCount / conversations * 10) / 10;
}

// ── 时段口径与统计卡构造（页面与 get_usage_stats 工具共用——时段起点/日轴起点/格文案
//    与公式三处单源，两处读数不可能漂移）──

// 时段起点毫秒（rangeIndex 0 近七天 / 1 近三十天 / 2 全部不过滤；nowMs 注入便于断言）
export function rangeSinceMs(rangeIndex: number, nowMs: number): number {
  if (rangeIndex === 0) {
    return dayStartMs(nowMs, 6);
  }
  if (rangeIndex === 1) {
    return dayStartMs(nowMs, 29);
  }
  return 0;
}

// 完整日轴起点日键（近 N 天 = 时段起点日；全部 = 近一年窗口首日——热力图/趋势/连续活跃
// 三处共用口径，页面头注释「全部档改固定一年窗口」为源）
export function axisStartDayKey(rangeIndex: number, sinceMs: number, nowMs: number): string {
  return rangeIndex === 2 ? toLocalDayKey(dayStartMs(nowMs, 364)) : toLocalDayKey(sinceMs);
}

// ── 上期比较口径（用量统计页首卡「比前 N 天」变动行；决明 2026-11-08 拍板：标题不带
//    「我们」、变动文案统一「比前 7 天 / 比前 30 天」、全部档不显示变动行）──

// 上一周期起点：入参刻意取**当前时段起点**而非系统时间——同一次查询里两次读 Date.now()
// 跨零点会错开一天；从该起点回退一整个等长窗口（近七天回退 7 天 / 近三十天回退 30 天），
// 与 rangeSinceMs 同帧同基准。全部档回 -1 = 无可比周期（调用方不查询、不渲染变动行）。
export function comparisonSinceMs(rangeIndex: number, sinceMs: number): number {
  if (rangeIndex === 0) {
    return dayStartMs(sinceMs, 7);
  }
  if (rangeIndex === 1) {
    return dayStartMs(sinceMs, 30);
  }
  return -1;
}

// 变动行时段名（文案单源；全部档空串 = 调用方按无可比周期隐藏）
export function comparisonPeriodLabel(rangeIndex: number): string {
  if (rangeIndex === 0) {
    return '前 7 天';
  }
  if (rangeIndex === 1) {
    return '前 30 天';
  }
  return '';
}

// 变动方向：1 增加 / -1 减少 / 0 持平（箭头由调用方按本值取官方 SymbolGlyph，持平不显）
export function tokenDeltaDirection(current: number, previous: number): number {
  const diff: number = current - previous;
  return diff > 0 ? 1 : (diff < 0 ? -1 : 0);
}

// 变动文案：复刻参考图「比上周减少 9 小时 11 分钟」的**绝对量**口径——差值走 fmtCompact
// 加 Token 单位，不写百分比；持平改「与…持平」。箭头不进本串（官方 SymbolGlyph 在调用
// 侧出），本函数零 UI 依赖可被纯函数断言直跑。
export function tokenDeltaText(current: number, previous: number, periodLabel: string): string {
  const diff: number = current - previous;
  if (diff === 0) {
    return '与' + periodLabel + '持平';
  }
  return '比' + periodLabel + (diff > 0 ? '增加 ' : '减少 ') +
    fmtCompact(Math.abs(diff)) + ' Token';
}

// 平均首字耗时数值串：入参 = 时段/会话内 SUM(firstTokenMs) 与**非 0 行计数**（会话级聚合
// sessionUsageTotals 的 fs/fn——分母必须走非 0 计数：存量行与无产出正文的轮次恒 0，混进
// 分母即假数据）。records ≤ 0 → '0'（除零守卫）；否则取均值折秒一位小数。★ 单位恒定「秒」
// 不切档——与时长格的小时/分钟双档刻意不同（首字量级恒在 0.x~十几秒）。消费方 = 会话统计
// 面板 Token 用量卡末行「平均首字耗时」（设置页/上下文面板落点曾两度改判后撤除，决明拍板
//「移入会话统计」）
export function fmtFirstTokenMs(sumMs: number, records: number): string {
  if (records <= 0) {
    return '0';
  }
  return '' + (Math.round(sumMs / records / 100) / 10);
}

// 总览六格（活跃会话/消息总数/每会话消息数/累计生成时长/每日平均 token/最长连续活跃）：
// 入参顺序 = 格序，调用点按名传值；时长 ≥1 小时走小时一位小数、否则分钟整数，每日平均 =
// 时段总量 ÷ 活跃天数（活跃天数 0 → '0'，除零守卫）。★ 格面沿革（防回游）：原「活跃模型」
// 格换为「每会话消息数」（决明指令——活跃模型仍由 DB 层聚合供排行卡尾行消费）；曾加过的
// 启动统计两格与「平均首字耗时」第七格均随拍板退役（后者见 fmtFirstTokenMs）——保持六格。
export function buildOverviewCells(activeConversations: number, messageCount: number,
  totalDurationMs: number, activeDays: number, totalTokens: number,
  longestStreakDays: number): UsageStatCell[] {
  const durHours: number = totalDurationMs / 3600000;
  const durText: string = durHours >= 1 ? '' + (Math.round(durHours * 10) / 10) :
    '' + Math.round(totalDurationMs / 60000);
  const durUnit: string = durHours >= 1 ? '小时' : '分钟';
  const avgDaily: string = activeDays > 0 ? fmtCompact(Math.round(totalTokens / activeDays)) : '0';
  return [
    { key: '活跃会话', label: '活跃会话', value: '' + activeConversations, unit: '个' },
    { key: '消息总数', label: '消息总数', value: '' + messageCount, unit: '条' },
    { key: '每会话消息数', label: '每会话消息数',
      value: fmtCompact(avgMessagesPerConversation(messageCount, activeConversations)),
      unit: '条' },
    { key: '累计生成时长', label: '累计生成时长', value: durText, unit: durUnit },
    { key: '每日平均 token', label: '每日平均 token', value: avgDaily, unit: '/天' },
    { key: '最长连续活跃', label: '最长连续活跃', value: '' + longestStreakDays, unit: '天' }
  ];
}

// Token 四格（总/输入/输出/每条平均；数值均 fmtCompact 无单位）
export function buildTokenCells(totalTokens: number, promptTokens: number,
  completionTokens: number, rounds: number): UsageStatCell[] {
  return [
    { key: '总 Token', label: '总 Token', value: fmtCompact(totalTokens), unit: '' },
    { key: '输入', label: '输入', value: fmtCompact(promptTokens), unit: '' },
    { key: '输出', label: '输出', value: fmtCompact(completionTokens), unit: '' },
    { key: '每条平均', label: '每条平均',
      value: fmtCompact(avgPerRound(totalTokens, rounds)), unit: '' }
  ];
}

// 金额格式化（元；≥1 元两位小数、0~1 元四位小数保精度、0 回 '0'）。★ 与 CostStatsCalc.fmtCost
// 同逻辑且必须同逻辑——两个计算模块都是「禁加 import」的零依赖纯函数文件（各自被断言脚本
// 剥类型直跑），没有共享通道，故实现双写；两处一致性由 assert-app-domain 84 组对拍断言钉死
//（同一组边界值逐值相等），任一处改公式即红
export function formatCostValue(v: number): string {
  if (v >= 1) {
    return v.toFixed(2);
  }
  if (v > 0) {
    return v.toFixed(4);
  }
  return '0';
}

// 费用总览四格（总费用/输入费用/缓存输入费用/输出费用；金额前缀 ¥ + formatCostValue 分档
// 小数）——费用估计页与 get_cost_stats 工具引同一函数，四格文案与金额格式单源，两处读数
// 逐格一致（buildOverviewCells 同族先例；值由调用方从 CostTotals 取数传入——本文件零
// import 契约不引外部类型）
export function buildCostCells(total: number, inputCost: number, cachedCost: number,
  outputCost: number): UsageStatCell[] {
  return [
    { key: '总费用', label: '总费用', value: '¥' + formatCostValue(total), unit: '' },
    { key: '输入费用', label: '输入费用', value: '¥' + formatCostValue(inputCost), unit: '' },
    { key: '缓存输入费用', label: '缓存输入费用',
      value: '¥' + formatCostValue(cachedCost), unit: '' },
    { key: '输出费用', label: '输出费用', value: '¥' + formatCostValue(outputCost), unit: '' }
  ];
}
