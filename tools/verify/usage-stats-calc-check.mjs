#!/usr/bin/env node
// ★ 公开仓副本（2026-09-24 公开仓可验证性笔）：自私有仓 scripts/ 同名件复制而来——只把
//   「相对仓库根」的深度由 1 层改成 2 层（落点自 scripts/ 移到 tools/verify/），其余同源；
//   运行 node tools/verify/<文件名>，零第三方依赖。
//   ★ 公开面到不了的内容（需读 scripts/ 其它件、需调私有工具链的钉）另有删节者，见文内说明。
// 用量统计纯函数断言（2026-09-06 用量统计页改版；运行：node scripts/usage-stats-calc-check.mjs）
// 目的：钉死 common/store/UsageStatsCalc.ets 全部纯函数的行为公式——热力图周列/补零轴/
// 月聚合算错一格，页面上就是一片错位色块或错柱，编译期零报错，全靠本脚本机械兜底。
// 姿势 = setting-search-check.mjs 第 8 查同款机械段：读 .ets 文本 → 剥注释 / export /
// interface / 白名单类型标注 → new Function 求值 → 行为断言。
// ★ 验收只认打印「过/败」计数（node 类型剥离退出期可能崩溃，与既有脚本基线同——退出码
//   仅供参考）；断言失败输出 ✗ 明细并计入败数。汇总行 2026-09-07 对齐 delivery-gate
//   解析协议「结果：N 过 / M 败」（数字在前形态）——已入交付门禁第六件。
// UsageStatsCalc.ets 按设计零 import 纯函数（本脚本可求值的前提）；类型标注走白名单剥除
// ——新增标注形态须同步下方 TYPE_RE（求值失败会显式报错，不静默漏检）。

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (rel) => readFileSync(join(root, rel), 'utf8');

let errors = 0;
let passed = 0;
function eq(name, actual, expected) {
  if (JSON.stringify(actual) === JSON.stringify(expected)) {
    passed++;
  } else {
    errors++;
    console.error('  ✗ ' + name + '：期望 ' + JSON.stringify(expected) + '，实得 ' + JSON.stringify(actual));
  }
}

// ── 剥 TS 机械段求值 ──
let calc;
try {
  const TYPE_RE = new RegExp(
    ':\\s*(number \\| undefined|Map<string, number>|\\(DayValue \\| null\\)\\[\\]\\[\\]|' +
    '\\(DayValue \\| null\\)\\[\\]|UsageStatCell\\[\\]|' +
    'DayValue\\[\\]|TrendPoint\\[\\]|WeekColumn\\[\\]|DayValue|TrendPoint|WeekColumn|' +
    'UsageStatCell|' +
    'string\\[\\]|number|string|boolean|Date|void)(?=\\s*[=),;{])', 'g');
  const evaled = read('entry/src/main/ets/common/store/UsageStatsCalc.ets')
    .replace(/\/\/[^\n]*/g, '')
    .replace(/^export /gm, '')
    .replace(/^interface \w+ \{[\s\S]*?\n\}\n/gm, '')
    .replace(TYPE_RE, '');
  const mod = { exports: {} };
  new Function('module', 'exports', evaled +
    '\nmodule.exports = { fmtCompact, dayStartMs, toLocalDayKey, fillDailyRange, ' +
    'splitIntoWeekColumns, splitIntoCalendarRows, longestStreak, aggregateByMonth, heatLevel, ' +
    'avgPerRound, avgMessagesPerConversation, rangeSinceMs, axisStartDayKey, buildOverviewCells, ' +
    'buildTokenCells, fmtFirstTokenMs };')(mod, mod.exports);
  calc = mod.exports;
} catch (e) {
  console.error('✗ UsageStatsCalc 剥 TS 求值失败（标注形态变化须同步 TYPE_RE）：' + e.message);
  console.log('用量统计纯函数断言 结果：0 过 / 1 败');
  process.exit(1);
}

// 测试工具：本地时刻毫秒 / 日键（与被测函数同走本地时区，任何机器时区下断言一致）
const D = (y, m, d, h, min) => new Date(y, m - 1, d, h || 0, min || 0).getTime();
const KEY = (d) => d.getFullYear() + '-' + (d.getMonth() + 1 < 10 ? '0' : '') + (d.getMonth() + 1) +
  '-' + (d.getDate() < 10 ? '0' : '') + d.getDate();
const DV = (day, totalTokens) => ({ day: day, totalTokens: totalTokens });

// ── fmtCompact：k 小写 M 大写一位小数，999500 进位 1M ──
eq('fmtCompact(0)', calc.fmtCompact(0), '0');
eq('fmtCompact(999)', calc.fmtCompact(999), '999');
eq('fmtCompact(1000)', calc.fmtCompact(1000), '1k');
eq('fmtCompact(1234)', calc.fmtCompact(1234), '1.2k');
eq('fmtCompact(999499)', calc.fmtCompact(999499), '999.5k');
eq('fmtCompact(999500)', calc.fmtCompact(999500), '1M');
eq('fmtCompact(1234567)', calc.fmtCompact(1234567), '1.2M');
eq('fmtCompact(1100000)', calc.fmtCompact(1100000), '1.1M');

// ── dayStartMs：当日零点 / setDate 回退跨月跨年 ──
{
  const now = Date.now();
  const t = new Date(now);
  eq('dayStartMs 当日零点', calc.dayStartMs(now, 0),
    new Date(t.getFullYear(), t.getMonth(), t.getDate()).getTime());
}
eq('dayStartMs 9月1日 back5 = 8月27日', calc.dayStartMs(D(2026, 9, 1, 15, 30), 5), D(2026, 8, 27));
eq('dayStartMs 跨年 1月3日 back5 = 上年12月29日', calc.dayStartMs(D(2026, 1, 3, 12), 5), D(2025, 12, 29));

// ── toLocalDayKey：与 dayStartMs 一致 + 月日补零 ──
eq('toLocalDayKey 与 dayStartMs 一致', calc.toLocalDayKey(calc.dayStartMs(D(2026, 9, 1, 15, 30), 5)), '2026-08-27');
eq('toLocalDayKey 补零', calc.toLocalDayKey(D(2026, 3, 7, 23, 59)), '2026-03-07');

// ── fillDailyRange：跨月衔接长度与零值 ──
eq('fillDailyRange 跨月补齐', calc.fillDailyRange('2026-08-29', '2026-09-02',
  [DV('2026-08-29', 5), DV('2026-09-01', 7)]),
  [DV('2026-08-29', 5), DV('2026-08-30', 0), DV('2026-08-31', 0), DV('2026-09-01', 7), DV('2026-09-02', 0)]);
eq('fillDailyRange 空范围', calc.fillDailyRange('2026-09-02', '2026-08-29', []), []);

// ── splitIntoWeekColumns：周一顶对齐 ──
// 动态定位一个真实周日/周一/周三（免手算星期错，任何年份重跑都成立）
function findWeekday(target) {
  for (let i = 0; i < 7; i++) {
    const d = new Date(2026, 0, 5 + i);
    if (d.getDay() === target) {
      return d;
    }
  }
  return null;
}
const sunday = findWeekday(0);
const monday = findWeekday(1);
const wednesday = findWeekday(3);
if (sunday === null || monday === null || wednesday === null) {
  errors++;
  console.error('  ✗ 星期定位失败（2026-01-05 起扫 7 天应覆盖全部星期）');
} else {
  // 周日单日落首列第 7 行（前导 6 null）
  const sunCols = calc.splitIntoWeekColumns([DV(KEY(sunday), 3)]);
  eq('周日单日落首列第 7 行', sunCols.length === 1 ?
    sunCols[0].cells.map((c) => c === null ? null : c.day) : '列数=' + sunCols.length,
    [null, null, null, null, null, null, KEY(sunday)]);
  eq('周列 key = 首格非空日', sunCols[0].key, KEY(sunday));
  // 周一起 8 天 = 2 列（首列满 7，次列首格第 8 天 + 补 null 至 7）
  const monDays = [];
  for (let i = 0; i < 8; i++) {
    monDays.push(DV(KEY(new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + i)), i + 1));
  }
  const monCols = calc.splitIntoWeekColumns(monDays);
  eq('周一起 8 天 = 2 列', monCols.length, 2);
  eq('周一列前导 null 数 = 0', monCols[0].cells.filter((c) => c === null).length, 0);
  eq('次列首格 = 第 8 天且补 null 至 7 格',
    [monCols[1].cells[0] === null ? null : monCols[1].cells[0].day, monCols[1].cells.length],
    [monDays[7].day, 7]);
  // 前导 null 数 = 星期偏移（周三 = 2；取首个非空格下标——尾列补 null 也在列内，
  // 数总数会把尾随 null 算进去）
  const wedCols = calc.splitIntoWeekColumns([DV(KEY(wednesday), 1)]);
  eq('前导 null 数 = 星期偏移（周三 → 2）',
    wedCols[0].cells.findIndex((c) => c !== null), 2);
  eq('空轴 → 空列', calc.splitIntoWeekColumns([]), []);
}

// ── longestStreak：空 / 全零 / 全满 / 中断 ──
eq('longestStreak 空', calc.longestStreak([]), 0);
eq('longestStreak 全零', calc.longestStreak([DV('2026-09-01', 0), DV('2026-09-02', 0)]), 0);
eq('longestStreak 全满', calc.longestStreak(
  [DV('2026-09-01', 1), DV('2026-09-02', 2), DV('2026-09-03', 3), DV('2026-09-04', 4)]), 4);
eq('longestStreak 中断取最长段', calc.longestStreak(
  [DV('2026-09-01', 1), DV('2026-09-02', 1), DV('2026-09-03', 0),
    DV('2026-09-04', 1), DV('2026-09-05', 1), DV('2026-09-06', 1)]), 3);

// ── splitIntoCalendarRows：日历行网格（2026-09-07 近三十天「满日历」新增；与周列对偶）──
{
  // 周日单日落首行第 7 列（前导 6 null）
  const sunRows = calc.splitIntoCalendarRows([DV(KEY(sunday), 3)]);
  eq('日历网 周日单日落首行第 7 列', sunRows.length === 1 ?
    sunRows[0].map((c) => c === null ? null : c.day) : '行数=' + sunRows.length,
    [null, null, null, null, null, null, KEY(sunday)]);
  // 周一起 8 天 = 2 行（首行满 7，次行首格第 8 天 + 补 null 至 7）
  const monDays8 = [];
  for (let i = 0; i < 8; i++) {
    monDays8.push(DV(KEY(new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + i)), i + 1));
  }
  const monRows = calc.splitIntoCalendarRows(monDays8);
  eq('日历网 周一起 8 天 = 2 行', monRows.length, 2);
  eq('日历网 首行前导 null 数 = 0', monRows[0].filter((c) => c === null).length, 0);
  eq('日历网 次行首格 = 第 8 天且补 null 至 7 格',
    [monRows[1][0] === null ? null : monRows[1][0].day, monRows[1].length],
    [monDays8[7].day, 7]);
  // 前导 null 数 = 星期偏移（周三 = 2）
  const wedRows = calc.splitIntoCalendarRows([DV(KEY(wednesday), 1)]);
  eq('日历网 前导 null 数 = 星期偏移（周三 → 2）',
    wedRows[0].findIndex((c) => c !== null), 2);
  eq('日历网 空轴 → 空行表', calc.splitIntoCalendarRows([]), []);
  // 30 天真实场景（近三十天档 = 8/9 周日~9/7 周一）：6 行 7 列，首行 6null+8/9、末行 9/7+6null
  const d30 = [];
  for (let i = 0; i < 30; i++) {
    const t = new Date(2026, 8, 7);
    t.setDate(t.getDate() - 29 + i);
    d30.push(DV(KEY(t), 0));
  }
  const rows30 = calc.splitIntoCalendarRows(d30);
  eq('日历网 30天(8/9周日~9/7周一) = 6 行', rows30.length, 6);
  eq('日历网 每行恒 7 列', rows30.every((r) => r.length === 7), true);
  eq('日历网 首行 = 6null + 8/9', rows30[0].map((c) => c === null ? null : c.day),
    [null, null, null, null, null, null, '2026-08-09']);
  eq('日历网 末行首格 = 9/7 且其后全 null',
    [rows30[5][0] === null ? null : rows30[5][0].day,
      rows30[5].slice(1).filter((c) => c !== null).length], ['2026-09-07', 0]);
}

// ── aggregateByMonth：跨年两月升序 + 同月求和 ──
eq('aggregateByMonth 跨年同月求和升序', calc.aggregateByMonth(
  [DV('2026-11-30', 5), DV('2026-12-01', 3), DV('2026-12-15', 4), DV('2027-01-01', 2)]),
  [{ key: '2026-11', totalTokens: 5 }, { key: '2026-12', totalTokens: 7 }, { key: '2027-01', totalTokens: 2 }]);

// ── heatLevel：max=0 → 0 / value=max → 4 / value=0 → 0 / 3/10 → 2 ──
eq('heatLevel max=0 → 0', calc.heatLevel(5, 0), 0);
eq('heatLevel value=max → 4', calc.heatLevel(10, 10), 4);
eq('heatLevel value=0 → 0', calc.heatLevel(0, 10), 0);
eq('heatLevel 3/10 → 2', calc.heatLevel(3, 10), 2);

// ── avgPerRound：除零 → 0 ──
eq('avgPerRound 除零 → 0', calc.avgPerRound(100, 0), 0);
eq('avgPerRound(100,4)', calc.avgPerRound(100, 4), 25);

// ── avgMessagesPerConversation：除零 → 0 / 整除取整 / 一位小数不塌零 ──
eq('avgMessagesPerConversation 会话 0 → 0', calc.avgMessagesPerConversation(120, 0), 0);
eq('avgMessagesPerConversation 消息 0 → 0', calc.avgMessagesPerConversation(0, 3), 0);
eq('avgMessagesPerConversation 整除(42/3)', calc.avgMessagesPerConversation(42, 3), 14);
eq('avgMessagesPerConversation 一位小数(10/4)', calc.avgMessagesPerConversation(10, 4), 2.5);
eq('avgMessagesPerConversation 小于 1 不塌零(1/3)', calc.avgMessagesPerConversation(1, 3), 0.3);
// 进位形态（2026-09-09 自检轮补：×10=6.67 四舍五入 7——round/floor 分水样例，此前五条
// 样例 ×10 后全为整数或 .33 形态，round→floor 变异体杀不死 = 假保护实证）
eq('avgMessagesPerConversation 四舍五入进位(2/3)', calc.avgMessagesPerConversation(2, 3), 0.7);

// ── 时段口径（2026-09-08 用量统计工具笔：页面与 get_usage_stats 工具共用——起点错一天
//    就是工具读数与页面差一天的静默漂移，全部档一年窗口同源）──
{
  const now = D(2026, 9, 8, 15, 30);
  eq('rangeSinceMs 近七天 = 今天零点回退 6 天', calc.rangeSinceMs(0, now), D(2026, 9, 2));
  eq('rangeSinceMs 近三十天 = 回退 29 天', calc.rangeSinceMs(1, now), D(2026, 8, 10));
  eq('rangeSinceMs 全部 = 0 不过滤', calc.rangeSinceMs(2, now), 0);
  eq('axisStartDayKey 近七天 = 时段起点日', calc.axisStartDayKey(0, D(2026, 9, 2), now), '2026-09-02');
  eq('axisStartDayKey 全部 = 近一年窗口首日', calc.axisStartDayKey(2, 0, now), '2025-09-09');
}

// ── fmtFirstTokenMs：首字均值（分母 = 非 0 行计数）+ 除零守卫 + 亚秒档（2026-09-23 首字耗时笔）──
eq('fmtFirstTokenMs 除零 → 0', calc.fmtFirstTokenMs(5000, 0), '0');
eq('fmtFirstTokenMs 均值一位小数(3600ms/3)', calc.fmtFirstTokenMs(3600, 3), '1.2');
eq('fmtFirstTokenMs 亚秒档(800ms/1)', calc.fmtFirstTokenMs(800, 1), '0.8');
// 分母口径钉：老行/无产出轮恒 0 不进分母 ⇒ 同为 3 秒的 2 轮，和 6000 而非 6000/3
eq('fmtFirstTokenMs 分母只认非 0 行（6000ms/2 → 3 秒）', calc.fmtFirstTokenMs(6000, 2), '3');

// ── 统计卡构造（buildOverviewCells/buildTokenCells：页面与工具逐格同源）──
// ★ 2026-09-23 首字耗时笔同日**两度**改判落点：总览回到**六格**（曾加过的第七格「平均首字
// 耗时」撤除，首字均值最终落「会话统计」面板 Token 用量卡——fmtFirstTokenMs 仍在本组直跑）
{
  const cells = calc.buildOverviewCells(3, 42, 4320000, 5, 12345, 7);
  eq('buildOverviewCells 六格序与文案', cells.map((c) => c.label),
    ['活跃会话', '消息总数', '每会话消息数', '累计生成时长', '每日平均 token', '最长连续活跃']);
  eq('buildOverviewCells 值/单位逐格（时长小时档 + 每日平均 + 每会话消息数）',
    cells.map((c) => c.value + '|' + c.unit),
    ['3|个', '42|条', '14|条', '1.2|小时', '2.5k|/天', '7|天']);
  // 每会话消息数一位小数档（10 条 ÷ 4 会话 = 2.5 条）
  eq('buildOverviewCells 每会话消息数保留一位小数',
    calc.buildOverviewCells(4, 10, 0, 1, 0, 0)[2].value, '2.5');
  // 分钟档（<1 小时）+ 活跃天数 0 除零守卫（每日平均回 '0'）+ 会话 0 除零守卫
  const minCells = calc.buildOverviewCells(0, 0, 2700000, 0, 100, 0);
  eq('buildOverviewCells 分钟档与三处除零守卫',
    minCells.map((c) => c.value + '|' + c.unit),
    ['0|个', '0|条', '0|条', '45|分钟', '0|/天', '0|天']);
  const tCells = calc.buildTokenCells(1234567, 1000000, 234567, 40);
  eq('buildTokenCells 四格序与值（fmtCompact 与每条平均）',
    tCells.map((c) => c.label + '=' + c.value + c.unit),
    ['总 Token=1.2M', '输入=1M', '输出=234.6k', '每条平均=30.9k']);
  const tZero = calc.buildTokenCells(0, 0, 0, 0);
  eq('buildTokenCells 轮数 0 每条平均回 0（除零守卫）',
    tZero.map((c) => c.value), ['0', '0', '0', '0']);
}

console.log('用量统计纯函数断言 结果：' + passed + ' 过 / ' + errors + ' 败');
process.exit(errors > 0 ? 1 : 0);
