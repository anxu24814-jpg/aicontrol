// 费用估计读取工具域（2026-09-13 任务书-工具补齐三件-20260913 §2.2）。
// 一个内置工具 get_cost_stats（defaultEnabled=false + console-exclusive 反向拦截——仅控制台
// 助手可用，同 get_usage_stats 族）：
// · range 三档（近七天 / 近三十天 / 全部，缺省近七天）——时段起点走
//   UsageStatsCalc.rangeSinceMs，与费用估计页切档同一套口径；档名常量直接复用
//   ToolUsageStats 的 USAGE_RANGE_*（与用量统计工具、两页分段文案逐字同源，禁另写字面量）；
// · 返回 = 费用总览四格 + 模型费用排行（前 COST_TOP_MODEL_MAX 名，含占比）+ 用途分布
//   （全零行不显示）+ 未配置价格的模型数 + 估算口径自述；四格构造走
//   UsageStatsCalc.buildCostCells 单源（与费用估计页逐格同文案同格式）；
// · 只读：零写库零改状态零广播（聚合查询走 UsageStatsDb / ProviderDb 既有函数，ResultSet
//   由各层 close；本文件不碰 AppStorage）。
// 边界：价格解析/折算/聚合在 CostStatsCalc，本文件只做工具协议层（schema / desc / 校验纯函数 /
// 载荷组装纯函数 / 执行器）；校验与载荷纯函数自包含可直跑（断言脚本剥 import 求值，同
// ToolUsageStats 姿势）。
import { ToolExecutor } from './ToolContracts';
import { USAGE_RANGE_ALL, USAGE_RANGE_MONTH, USAGE_RANGE_WEEK } from './ToolUsageStats';
import { COST_TOP_MODEL_MAX, CostAggregate, CostByModelRow, CostByPurposeRow, CostEventInput,
  ModelPriceSourceRow, aggregateCosts, buildPriceMap, fmtCost, purposeLabel } from '../store/CostStatsCalc';
import { ModelRow, queryAllModels } from '../store/ProviderDb';
import { queryCostEvents } from '../store/UsageStatsDb';
import { UsageStatCell, buildCostCells, rangeSinceMs } from '../store/UsageStatsCalc';

// 工具名常量 TOOL_GET_COST_STATS 归口 ToolTypes.ets（注册/反向拦截/seed 同源引用）。

// 入参 schema（range 可选——缺省近七天，与费用页默认档一致；枚举自三档名常量拼接防双源）
export const GET_COST_STATS_SCHEMA: string =
  '{"type":"object","properties":{"range":{"type":"string",' +
  '"description":"统计时段，不传按 ' + USAGE_RANGE_WEEK + '","enum":["' + USAGE_RANGE_WEEK +
  '","' + USAGE_RANGE_MONTH + '","' + USAGE_RANGE_ALL + '"]}}}';

// 估算口径自述（desc 与结果 note 同引一处——模型价格乘 token 用量折算、实际计费以服务商
// 账单为准、未配置价格的模型不计入任何金额）
export const COST_ESTIMATE_NOTE: string = '费用为估算值，按模型价格乘 token 用量折算，实际计费以服务商账单为准。未配置价格的模型不计入任何金额。';

// 工具 desc（调用纪律 + 返回面自述；Top 条数随 COST_TOP_MODEL_MAX 动态拼——禁字面量双源。
// 文案守宪法「面向用户文案写作规约」精神——无冒号分号括号连环与等号分列）
export function buildGetCostStatsDesc(): string {
  return '读取本应用的费用估计数据。只读查询，不修改任何内容。range 取 ' + USAGE_RANGE_WEEK +
    '、' + USAGE_RANGE_MONTH + ' 或 ' + USAGE_RANGE_ALL + '，不传按 ' + USAGE_RANGE_WEEK +
    '。返回所选时段的费用总览四项（总费用、输入费用、缓存输入费用、输出费用）、按费用排序的' +
    '前 ' + COST_TOP_MODEL_MAX + ' 个模型与各自占比、按用途汇总的费用，模型数超过 ' +
    COST_TOP_MODEL_MAX + ' 时附未展示的数量。' + COST_ESTIMATE_NOTE +
    '用户询问花了多少钱、哪个模型最费钱、费用构成时调用。回答费用数据前先调用本工具查实，' +
    '不要凭记忆或猜测回答。';
}

// 参数校验结果（纯函数可断言）
export interface GetCostStatsValidation {
  ok: boolean;
  range: string;
  error: string;
}

function rejectGetCostStats(error: string): GetCostStatsValidation {
  return { ok: false, range: '', error: error };
}

// 参数校验纯函数：坏 JSON / 枚举外档名拒且回显合法档名；缺 range 或空白串 = 缺省近七天
export function validateGetCostStatsArgs(argsJson: string): GetCostStatsValidation {
  let range: string = '';
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    const raw: Object | undefined = parsed['range'];
    if (typeof raw === 'string') {
      range = raw.trim();
    }
  } catch (e) {
    return rejectGetCostStats('参数解析失败，range 取：' + USAGE_RANGE_WEEK + '、' +
      USAGE_RANGE_MONTH + '、' + USAGE_RANGE_ALL);
  }
  if (range === '') {
    return { ok: true, range: USAGE_RANGE_WEEK, error: '' };
  }
  if (range !== USAGE_RANGE_WEEK && range !== USAGE_RANGE_MONTH && range !== USAGE_RANGE_ALL) {
    return rejectGetCostStats('range 必须是：' + USAGE_RANGE_WEEK + '、' + USAGE_RANGE_MONTH +
      '、' + USAGE_RANGE_ALL);
  }
  return { ok: true, range: range, error: '' };
}

// ── 载荷结构（键集合被断言钉死——格值与费用页同源同文案）──

export interface CostStatCellPayload {
  label: string;
  value: string;
  unit: string;
}

export interface CostModelRankPayload {
  rank: number;
  modelId: string;
  cost: string;
  percent: string;
}

export interface CostPurposePayload {
  label: string;
  cost: string;
  percent: string;
}

export interface CostStatsPayload {
  ok: boolean;
  range: string;
  totals: CostStatCellPayload[];
  byModel: CostModelRankPayload[];
  otherModelCount: number;
  byPurpose: CostPurposePayload[];
  unpricedModelCount: number;
  note: string;
}

// 占比百分比串（分母 ≤ 0 回 '0'——与费用页 pctOf 同口径；两位小数防小占比丢精度）
function pctText(part: number, total: number): string {
  if (total <= 0) {
    return '0';
  }
  return (part / total * 100).toFixed(2);
}

// 载荷组装纯函数（接收聚合结果，不碰 DB——断言可直跑）：四格走 buildCostCells 单源；
// byModel 截断注记、全部零值用途行不显示、空态 note 改引导文案（指引到服务商页配置价格）
export function buildCostStatsPayload(range: string, agg: CostAggregate): CostStatsPayload {
  const cells: UsageStatCell[] = buildCostCells(agg.totals.total, agg.totals.inputCost,
    agg.totals.cachedCost, agg.totals.outputCost);
  const totals: CostStatCellPayload[] = [];
  for (const cell of cells) {
    totals.push({ label: cell.label, value: cell.value, unit: cell.unit });
  }
  const byModel: CostModelRankPayload[] = [];
  for (let i: number = 0; i < agg.byModel.length; i++) {
    const row: CostByModelRow = agg.byModel[i];
    byModel.push({
      rank: i + 1,
      modelId: row.modelId,
      cost: '¥' + fmtCost(row.total),
      percent: pctText(row.total, agg.totals.total)
    });
  }
  const byPurpose: CostPurposePayload[] = [];
  for (const row of agg.byPurpose) {
    if (row.total > 0) {
      byPurpose.push({
        label: purposeLabel(row.purpose),
        cost: '¥' + fmtCost(row.total),
        percent: pctText(row.total, agg.totals.total)
      });
    }
  }
  const empty: boolean = agg.pricedEventCount === 0;
  return {
    ok: true,
    range: range,
    totals: totals,
    byModel: byModel,
    otherModelCount: agg.pricedModelCount > byModel.length ?
      agg.pricedModelCount - byModel.length : 0,
    byPurpose: byPurpose,
    unpricedModelCount: agg.unpricedModels.length,
    note: empty ?
      '所选时段没有已配置价格模型的记录。请提醒用户先到 设置 → 服务商管理 打开服务商详情，' +
      '在模型页签点开模型的编辑页填写模型价格。' : COST_ESTIMATE_NOTE
  };
}

// 费用估计执行器（只读）：校验 → 档名映射 rangeIndex → 两炮并行查（时段内全用途事件 +
// 全量模型行价格 map，与费用页 loadStats 同两函数同 since）→ 聚合纯函数 → 载荷。DB 查询
// 抛错上抛由 executeToolCall 统一包装 error JSON（不炸轮次）
export class GetCostStatsExecutor implements ToolExecutor {
  execute(argsJson: string): Promise<string> {
    const v: GetCostStatsValidation = validateGetCostStatsArgs(argsJson);
    if (!v.ok) {
      return Promise.resolve(JSON.stringify({ error: v.error }));
    }
    const rangeIndex: number = v.range === USAGE_RANGE_MONTH ? 1 :
      (v.range === USAGE_RANGE_ALL ? 2 : 0);
    const since: number = rangeSinceMs(rangeIndex, Date.now());
    return Promise.all([queryCostEvents(since), queryAllModels()])
      .then((results: [CostEventInput[], ModelRow[]]): string => {
        const sourceRows: ModelPriceSourceRow[] = results[1].map((row: ModelRow):
          ModelPriceSourceRow => {
          return { providerId: row.providerId, modelId: row.modelId, priceConfig: row.priceConfig };
        });
        const agg: CostAggregate = aggregateCosts(results[0], buildPriceMap(sourceRows));
        return JSON.stringify(buildCostStatsPayload(v.range, agg));
      });
  }
}
