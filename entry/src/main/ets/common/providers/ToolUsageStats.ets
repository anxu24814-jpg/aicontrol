// 用量统计查询工具域（2026-09-08 决明指令「新增控制台助手可用只读工具，读取用量统计页
// 7/30/全部的统计信息；只读取总览 6 个卡片、token 用量 4 个卡片与模型用量排行 Top10；
// 数据都是已有记录，只读调取」）。
// 一个内置工具 get_usage_stats（defaultEnabled=false + console-exclusive 反向拦截——
// 仅控制台助手可用，同 set_app_preference 族）：
// · range 三档（近七天/近三十天/全部，缺省近七天）——时段起点与日轴起点走
//   UsageStatsCalc.rangeSinceMs/axisStartDayKey，与用量统计页切档同一套口径；
// · 返回 = 总览六格 + Token 四格 + 模型排行 Top10（页面同 10 格 + 10 行，逐格同文案同格式
//   ——格值构造走 UsageStatsCalc.buildOverviewCells/buildTokenCells 单源），另附未展示的
//   模型数与空时段说明；
// · 只读：零写库零改状态零广播（聚合查询走 UsageStatsDb 既有三函数，ResultSet 由该层
//   close；本文件不碰 AppStorage）。
// 边界：数据聚合与逐日轴在 UsageStatsDb / UsageStatsCalc，本文件只做工具协议层
//（schema/desc/校验纯函数/执行器）；校验纯函数自包含可断言（searchHelpTopics 同款姿势，
// 断言脚本剥 TS 求值直跑）。
import { ToolExecutor } from './ToolContracts';
import { UsageByDayRow, UsageByModelRow, UsageOverview, usageByDay, usageByModel,
  usageOverview } from '../store/UsageStatsDb';
import { DayValue, UsageStatCell, axisStartDayKey, buildOverviewCells, buildTokenCells,
  fillDailyRange, fmtCompact, longestStreak, rangeSinceMs, toLocalDayKey } from '../store/UsageStatsCalc';

// 工具名常量 TOOL_GET_USAGE_STATS 归口 ToolTypes.ets（注册/反向拦截/seed 同源引用）。

// 三档时段名（与用量统计页分段胶囊文案逐字一致——模型从用户原话直接取词零映射；
// schema 枚举与校验、执行器三处同源引用）
export const USAGE_RANGE_WEEK: string = '近七天';
export const USAGE_RANGE_MONTH: string = '近三十天';
export const USAGE_RANGE_ALL: string = '全部';

// 入参 schema（range 可选——缺省近七天，与页面默认档一致；枚举自三常量拼接防双源）
export const GET_USAGE_STATS_SCHEMA: string =
  '{"type":"object","properties":{"range":{"type":"string",' +
  '"description":"统计时段，不传按 ' + USAGE_RANGE_WEEK + '","enum":["' + USAGE_RANGE_WEEK +
  '","' + USAGE_RANGE_MONTH + '","' + USAGE_RANGE_ALL + '"]}}}';

// 工具 desc（调用纪律 + 返回面自述；数值口径与页面一致性写明，模型不必自行换算。文案守
// 宪法「面向用户文案写作规约」精神——无冒号分号括号连环与等号分列）
export function buildGetUsageStatsDesc(): string {
  return '读取本应用的用量统计数据。只读查询，不修改任何内容。range 取 ' + USAGE_RANGE_WEEK +
    '、' + USAGE_RANGE_MONTH + ' 或 ' + USAGE_RANGE_ALL + '，不传按 ' + USAGE_RANGE_WEEK +
    '。返回所选时段的总览六项、Token 用量四项与按总 token 排序的前十个模型，模型数超过十个' +
    '时附未展示的数量。总览六项有活跃会话、消息总数、每会话消息数、累计生成时长、每日平均 ' +
    'token 与最长连续活跃，其中每会话消息数是消息总数除以活跃会话数的结果。Token 四项有总 ' +
    'Token、输入、输出、每条平均。数值格式与用量统计页' +
    '一致，最长连续活跃同页面口径，全部时段按近一年窗口计算。用户询问自己的用量、token ' +
    '消耗、生成时长、活跃情况、每会话消息数或哪个模型用得多时调用。回答用量数据前先调用本' +
    '工具查实，不要凭记忆或猜测回答。';
}

// 参数校验结果（纯函数可断言）
export interface GetUsageStatsValidation {
  ok: boolean;
  range: string;
  error: string;
}

function rejectGetUsageStats(error: string): GetUsageStatsValidation {
  return { ok: false, range: '', error: error };
}

// 参数校验纯函数：坏 JSON / 枚举外档名拒且回显合法档名；缺 range 或空白串 = 缺省近七天
export function validateGetUsageStatsArgs(argsJson: string): GetUsageStatsValidation {
  let range: string = '';
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    const raw: Object | undefined = parsed['range'];
    if (typeof raw === 'string') {
      range = raw.trim();
    }
  } catch (e) {
    return rejectGetUsageStats('参数解析失败，range 取：' + USAGE_RANGE_WEEK + '、' +
      USAGE_RANGE_MONTH + '、' + USAGE_RANGE_ALL);
  }
  if (range === '') {
    return { ok: true, range: USAGE_RANGE_WEEK, error: '' };
  }
  if (range !== USAGE_RANGE_WEEK && range !== USAGE_RANGE_MONTH && range !== USAGE_RANGE_ALL) {
    return rejectGetUsageStats('range 必须是：' + USAGE_RANGE_WEEK + '、' + USAGE_RANGE_MONTH +
      '、' + USAGE_RANGE_ALL);
  }
  return { ok: true, range: range, error: '' };
}

// 统计格载荷（label/value/unit 三元组——与页面格值同源同文案）
interface UsageStatCellPayload {
  label: string;
  value: string;
  unit: string;
}

// 模型排行行（rank 从 1 起，与页面行序一致）
interface UsageStatsModelPayload {
  rank: number;
  model: string;
  totalTokens: string;
  promptTokens: string;
  completionTokens: string;
}

// 工具结果载荷（startDate = 近 N 天档的时段起点本地日，全部档为空串；otherModels = 排行
// 之外未展示的模型数；note = 空时段说明，有记录时为空串）
interface UsageStatsPayload {
  ok: boolean;
  range: string;
  startDate: string;
  overview: UsageStatCellPayload[];
  tokens: UsageStatCellPayload[];
  models: UsageStatsModelPayload[];
  otherModels: number;
  note: string;
}

// 用量统计执行器（只读）：校验 → 档名映射 rangeIndex → 三聚合并行查（总览/按模型/逐日，
// 与页面 loadStats 同三函数同 since）→ 逐日轴补零算最长连续活跃（axisStartDayKey 单源，
// 与页面同口径）→ 格值构造走 calc 单源 → 载荷。DB 查询抛错上抛由 executeToolCall 统一
// 包装 error JSON（不炸轮次）
export class GetUsageStatsExecutor implements ToolExecutor {
  execute(argsJson: string): Promise<string> {
    const v: GetUsageStatsValidation = validateGetUsageStatsArgs(argsJson);
    if (!v.ok) {
      return Promise.resolve(JSON.stringify({ error: v.error }));
    }
    const rangeIndex: number = v.range === USAGE_RANGE_MONTH ? 1 :
      (v.range === USAGE_RANGE_ALL ? 2 : 0);
    const nowMs: number = Date.now();
    const since: number = rangeSinceMs(rangeIndex, nowMs);
    return Promise.all([usageOverview(since), usageByModel(since), usageByDay(since)])
      .then((results: [UsageOverview, UsageByModelRow[], UsageByDayRow[]]): string => {
        const overview: UsageOverview = results[0];
        const modelRows: UsageByModelRow[] = results[1];
        const dayRows: DayValue[] = results[2].map((row: UsageByDayRow): DayValue => {
          return { day: row.day, totalTokens: row.totalTokens };
        });
        // 最长连续活跃与页面同口径：完整日轴 = 轴起点~今天，无记录日补零（全部档轴起点为
        // 近一年窗口首日，与页面「全部」档一致）
        const axis: DayValue[] = fillDailyRange(axisStartDayKey(rangeIndex, since, nowMs),
          toLocalDayKey(nowMs), dayRows);
        const streakDays: number = longestStreak(axis);
        const overviewCells: UsageStatCell[] = buildOverviewCells(overview.activeConversations,
          overview.messageCount, overview.totalDurationMs,
          overview.activeDays, overview.totalTokens, streakDays);
        const tokenCells: UsageStatCell[] = buildTokenCells(overview.totalTokens,
          overview.totalPromptTokens, overview.totalCompletionTokens, overview.rounds);
        const models: UsageStatsModelPayload[] = [];
        for (let i: number = 0; i < modelRows.length; i++) {
          const row: UsageByModelRow = modelRows[i];
          models.push({
            rank: i + 1,
            model: row.modelId !== '' ? row.modelId : '未知模型',
            totalTokens: fmtCompact(row.totalTokens),
            promptTokens: fmtCompact(row.promptTokens),
            completionTokens: fmtCompact(row.completionTokens)
          });
        }
        const payload: UsageStatsPayload = {
          ok: true,
          range: v.range,
          startDate: since === 0 ? '' : toLocalDayKey(since),
          overview: toCellPayloads(overviewCells),
          tokens: toCellPayloads(tokenCells),
          models: models,
          otherModels: overview.usedModels > models.length ?
            overview.usedModels - models.length : 0,
          note: overview.rounds === 0 ?
            '所选时段没有任何用量记录。升级前产生的历史对话不参与统计。' : ''
        };
        return JSON.stringify(payload);
      });
  }
}

// 格值载荷投影（key 为页面 ForEach 身份位，模型侧不需要——载荷只留 label/value/unit）
function toCellPayloads(cells: UsageStatCell[]): UsageStatCellPayload[] {
  const payloads: UsageStatCellPayload[] = [];
  for (const cell of cells) {
    payloads.push({ label: cell.label, value: cell.value, unit: cell.unit });
  }
  return payloads;
}
