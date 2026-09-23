// 费用估计计算模块（2026-09-10 方案-费用估计-20260910 新增；职责缝 = 「价格配置解析/
// 谷时判定/单事件折算/聚合/金额格式化」的公式层——照 UsageStatsCalc 先例零 import 零 UI
// 依赖，专为断言脚本剥类型直跑而设：★本文件禁加 import★，类型标注只用可剥离形态。
// 2026-09-11 价格模板笔补 priceSummary（价格摘要一行文案——模板列表副行消费，属价格域
// 展示格式化，与 fmtCost 同层故落本文件而非页面）。
// ★ 2026-09-13 工具补齐三件笔：补 COST_TOP_MODEL_MAX 条数上限常量（aggregateCosts 截断与
// get_cost_stats 工具 desc 单源）；费用总览四格构造**不放本文件**——落 UsageStatsCalc
// （UsageStatCell 格族之家；本文件禁加 import 的契约使然，见该函数注释）。
// 单位口径（方案拍板）：全局人民币，价格 = 元/百万 tokens（美元计价服务商由用户手算
// 折算填入——无汇率换算）；cachedInput 缺省回退 input（Cherry Studio 同款口径），显式
// 0 = 缓存免费（2026-09-11 决明拍板放宽，留空才回退）；
// valley 谷时第二套价缺省无峰谷全天统一价，valley 内单项缺回退平时对应价。
// 价格 JSON 结构（price_config 列 / parsePriceConfig 唯一权威；★ 2026-09-11 谷时多时段笔
// 起谷时写新形态，旧形态仅作读取兼容）：
//   {"input":2,"cachedInput":0.5,"output":8,
//    "valley":{"input":1,"cachedInput":0.25,"output":4,
//              "segments":[{"start":"12:00","end":"14:00","days":[1,2]},
//                          {"start":"00:00","end":"00:00","days":[6,0]}]}}
//   旧形态 = valley 内直挂 start/end/days（无 segments），解析时归一为单段——存量配置
//   零迁移零回归；新形态写出的库回退旧版 App 时旧解析器读不到 start/end → 整块丢弃谷价
//   保留主价（不崩不误算，当前未上架可接受）。
// 谷时按事件 createdAt 本地时区落点判价（历史事件回溯天然成立）。

// 谷时段 = 一套适用条件（start/end = 'HH:mm' 本地时区；start==end 视为全天谷时；days =
// 适用周几多选，Date.getDay() 口径 0=周日…6=周六，缺省/空 = 每天谷价〔存量配置兼容〕；
// 跨午夜段周几归属 = 按段开始日算——2026-09-11 决明拍板：勾周五 22:00~06:00 则周六
// 凌晨 0~6 点属周五那段照谷价）
export interface ValleySegment {
  start: string;
  end: string;
  days?: number[];
}

// 谷时第二套价 = 一套谷时价 + 段列表（任一段命中即按谷价，全不命中按平时价）。价格挂
// 顶层不逐段分（2026-09-11 决明拍板①：厂商给的是一个谷价，共用让重叠无歧义）；段序不
// 影响判定、重叠无副作用，故不设优先级也不做重叠校验（拍板⑤）
export interface ValleyPriceConfig {
  input: number;
  cachedInput?: number;
  output: number;
  segments: ValleySegment[];
}

// 模型价格配置（input/output 必填，cachedInput 可选回退 input；valley 可选）
export interface ModelPriceConfig {
  input: number;
  cachedInput?: number;
  output: number;
  valley?: ValleyPriceConfig;
}

// 费用事件行（UsageStatsDb.queryCostEvents 的行投影；与账本行同源字段子集）
export interface CostEventInput {
  providerId: string;
  modelId: string;
  purpose: string;
  promptTokens: number;
  completionTokens: number;
  cachedTokens: number;
  createdAt: number;
}

// 单事件折算结果（total = 三项之和；输入费用 = 非缓存输入部分，缓存输入费用单列）
export interface CostBreakdown {
  total: number;
  inputCost: number;
  cachedCost: number;
  outputCost: number;
}

// 四总额（总/输入/缓存输入/输出；时段内已配置价格事件的折算和）
export interface CostTotals {
  total: number;
  inputCost: number;
  cachedCost: number;
  outputCost: number;
}

// 按模型费用行（费用降序 Top10）
export interface CostByModelRow {
  modelId: string;
  total: number;
}

// 按用途费用行（四类：chat/title/memory/test，label 映射见 COST_PURPOSE_LABELS）
export interface CostByPurposeRow {
  purpose: string;
  total: number;
}

// 聚合结果（byModel = 费用降序前 COST_TOP_MODEL_MAX 名；byPurpose = 四类定序全量含零值行
//——展示侧隐藏全零行；unpricedModels = 时段内出现但模型未配置价格的 modelId 去重集；
// pricedEventCount = 已配置价格的事件数〔0 = 空态引导卡判据〕；pricedModelCount = 已配置价格
// 且有费用的模型总数〔> byModel.length 即截断未展示，尾行提示用〕）
export interface CostAggregate {
  totals: CostTotals;
  byModel: CostByModelRow[];
  byPurpose: CostByPurposeRow[];
  unpricedModels: string[];
  pricedEventCount: number;
  pricedModelCount: number;
}

// 价格 map 数据源行（ProviderDb.queryAllModels 投影——map 构建只吃这三列）
export interface ModelPriceSourceRow {
  providerId: string;
  modelId: string;
  priceConfig: string;
}

// 谷时段数上限（2026-09-11 拍板②：真实组合〔工作日午间 + 夜间 + 周末全天 + 余量〕够用，
// 防无界）。★ 单源常量——UI 添加键置灰与提示文案、解析侧截断都引它，禁各自写字面量
export const VALLEY_SEGMENT_MAX: number = 6;

// 模型费用排行条数上限（★ 2026-09-13 工具补齐三件笔新增：aggregateCosts 的截断与
// get_cost_stats 工具 desc 的「前 N 个」同源引用，禁字面量双源）
export const COST_TOP_MODEL_MAX: number = 10;

// 用途码八值（与 UsageStatsDb 写入点约定一致；顺序 = 用途分布卡行序。2026-09-12 主动
// 消息第一笔 +proactive——追加在尾，消费侧 purposeLabel 未知码透出与本表 for-of 定序
// 均零改动自动进组；2026-09-15 附件 OCR 二期 +ocr 同款追加在尾；2026-09-19 推荐问题
// 功能 +suggest 同款追加在尾；2026-09-23 上下文压缩笔 +compress 同款追加在尾）
export const COST_PURPOSES: string[] = ['chat', 'title', 'memory', 'test', 'proactive', 'ocr',
  'suggest', 'compress'];
// 用途码 → 展示名（用途分布卡与费用页共用单源）
export const COST_PURPOSE_LABELS: Record<string, string> = {
  'chat': '聊天',
  'title': '标题生成',
  'memory': '记忆整理',
  'test': '测试连接',
  'proactive': '主动消息',
  'ocr': '文字识别',
  'suggest': '推荐问题',
  'compress': '上下文压缩'
};

// 用途码 → 展示名（未知码原样透出——码表演进不炸旧数据）
export function purposeLabel(purpose: string): string {
  const hit: string | undefined = COST_PURPOSE_LABELS[purpose];
  return hit !== undefined ? hit : purpose;
}

// 'HH:mm' → 当日分钟数（0~1439）；格式不合法回 -1（parsePriceConfig 据此弃 valley）
function hmToMinutes(hm: string): number {
  const parts: string[] = hm.split(':');
  if (parts.length !== 2) {
    return -1;
  }
  const h: number = Number(parts[0]);
  const m: number = Number(parts[1]);
  if (!Number.isInteger(h) || !Number.isInteger(m) || h < 0 || h > 23 || m < 0 || m > 59) {
    return -1;
  }
  if (parts[0].length !== 2 || parts[1].length !== 2) {
    return -1; // 两位补零形态（TimePickerDialog 产出即此形态，库内值经 serialize 保证）
  }
  return h * 60 + m;
}

// 非负有限数判定（价格字段值域；NaN/负数/Infinity 拒收）
function isPriceNumber(v: Object): boolean {
  if (typeof v !== 'number') {
    return false;
  }
  const n: number = v as number;
  return Number.isFinite(n) && n >= 0;
}

// 周几多选解析（可选件）：数组且逐项为 0~6 整数才返回；非法/空数组回 undefined = 不挂键
//（= 每天，与 cachedInput 缺省同型兜底——保存链只产合法非空值，此处为读取侧防御）
function parseWeekdayCodes(v: Object | undefined): number[] | undefined {
  if (!Array.isArray(v)) {
    return undefined;
  }
  const arr: Object[] = v as Object[];
  if (arr.length === 0) {
    return undefined;
  }
  const codes: number[] = [];
  for (const item of arr) {
    if (typeof item === 'number' && Number.isInteger(item) && item >= 0 && item <= 6) {
      codes.push(item);
    } else {
      return undefined;
    }
  }
  return codes;
}

// 单段校验：段非对象 / start 或 end 非 'HH:mm' 合法串 → null = 丢该段；days 非法或空 →
// 不挂键 = 每天但**段保留**。★ 新形态的段对象与旧形态 valley 顶层同为 {start,end,days?}
// 形态，两路共用本函数（逻辑单一来源）
function parseValleySegment(raw: Object): ValleySegment | null {
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
    return null;
  }
  const obj: Record<string, Object> = raw as Record<string, Object>;
  const startV: Object | undefined = obj['start'];
  const endV: Object | undefined = obj['end'];
  if (typeof startV !== 'string' || typeof endV !== 'string' ||
    hmToMinutes(startV) < 0 || hmToMinutes(endV) < 0) {
    return null;
  }
  const seg: ValleySegment = { start: startV, end: endV };
  const days: number[] | undefined = parseWeekdayCodes(obj['days']);
  if (days !== undefined) {
    seg.days = days;
  }
  return seg;
}

// 谷时字段 → 段列表（双形态归一，2026-09-11 谷时多时段笔；优先级为拍板外补强条）：①
// segments 为数组且校验后至少一段 → 用新形态，遗留 start/end 忽略；②否则回退遗留单段；
// ③两者皆无合法段 → 空数组（调用侧据此整块丢弃谷时）。合法段超上限 → 保留前
// VALLEY_SEGMENT_MAX 段（添加序，不是丢尾不是整块丢）
function parseValleySegments(v: Record<string, Object>): ValleySegment[] {
  const rawSegments: Object | undefined = v['segments'];
  if (Array.isArray(rawSegments)) {
    const arr: Object[] = rawSegments as Object[];
    const segments: ValleySegment[] = [];
    for (const item of arr) {
      const seg: ValleySegment | null = parseValleySegment(item);
      if (seg !== null) {
        segments.push(seg);
      }
    }
    if (segments.length > 0) {
      return segments.slice(0, VALLEY_SEGMENT_MAX);
    }
  }
  const legacy: ValleySegment | null = parseValleySegment(v);
  return legacy !== null ? [legacy] : [];
}

// 价格 JSON 串 → 配置。'' / 坏 JSON / input 或 output 缺失或非非负数 → null = 未配置；
// cachedInput 缺失/非法 → 挂 undefined（回退 input），显式 0 = 合法（缓存免费，
// 2026-09-11 决明拍板放宽）；valley 任一必要件缺失、合法时段为空或时间格式
// 非法 → 整块丢弃（谷时配置不完整 = 不启用峰谷，静默回退全天统一价——保存链已逐项
// 校验拦非法值，此处为库内脏数据的读取侧兜底）
export function parsePriceConfig(json: string): ModelPriceConfig | null {
  if (json === '') {
    return null;
  }
  let root: Record<string, Object>;
  try {
    root = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    return null;
  }
  const inputV: Object | undefined = root['input'];
  const outputV: Object | undefined = root['output'];
  if (!isPriceNumber(inputV ?? null) || !isPriceNumber(outputV ?? null)) {
    return null;
  }
  const cfg: ModelPriceConfig = { input: inputV as number, output: outputV as number };
  const cachedV: Object | undefined = root['cachedInput'];
  if (isPriceNumber(cachedV ?? null)) {
    cfg.cachedInput = cachedV as number;
  }
  const valleyV: Object | undefined = root['valley'];
  if (valleyV !== undefined && typeof valleyV === 'object' && valleyV !== null) {
    const v: Record<string, Object> = valleyV as Record<string, Object>;
    const vInput: Object | undefined = v['input'];
    const vOutput: Object | undefined = v['output'];
    if (isPriceNumber(vInput ?? null) && isPriceNumber(vOutput ?? null)) {
      const segments: ValleySegment[] = parseValleySegments(v);
      if (segments.length > 0) {
        const valley: ValleyPriceConfig = {
          input: vInput as number, output: vOutput as number, segments: segments
        };
        const vCached: Object | undefined = v['cachedInput'];
        if (isPriceNumber(vCached ?? null)) {
          valley.cachedInput = vCached as number;
        }
        cfg.valley = valley;
      }
    }
  }
  return cfg;
}

// 配置 → 价格 JSON 串（serializePriceConfig）；未挂的可选字段不写键（缺省语义在解析侧
// 收敛）；键序固定 input → cachedInput → output，valley 内 input → cachedInput → output
// → segments，段内 start → end → days（round-trip 稳定，断言可钉）。★ 只写新形态——
// 旧形态是读取兼容路径，不再产出
export function serializePriceConfig(cfg: ModelPriceConfig): string {
  const parts: string[] = [];
  parts.push('"input":' + cfg.input);
  if (cfg.cachedInput !== undefined) {
    parts.push('"cachedInput":' + cfg.cachedInput);
  }
  parts.push('"output":' + cfg.output);
  if (cfg.valley !== undefined) {
    const vParts: string[] = [];
    vParts.push('"input":' + cfg.valley.input);
    if (cfg.valley.cachedInput !== undefined) {
      vParts.push('"cachedInput":' + cfg.valley.cachedInput);
    }
    vParts.push('"output":' + cfg.valley.output);
    const segParts: string[] = cfg.valley.segments.map((seg: ValleySegment): string => {
      const sParts: string[] = [];
      sParts.push('"start":"' + seg.start + '"');
      sParts.push('"end":"' + seg.end + '"');
      if (seg.days !== undefined && seg.days.length > 0) {
        const codes: string[] = seg.days.map((d: number): string => '' + d);
        sParts.push('"days":[' + codes.join(',') + ']');
      }
      return '{' + sParts.join(',') + '}';
    });
    vParts.push('"segments":[' + segParts.join(',') + ']');
    parts.push('"valley":{' + vParts.join(',') + '}');
  }
  return '{' + parts.join(',') + '}';
}

// 谷时判定（本地时区 HH:mm 比较）：start<end 普通区间；start>end 跨午夜（t≥start 或
// t<end）；start==end 视为全天谷时（用户显式配置的合法形态）。days = 适用周几
// （Date.getDay() 口径；缺省/空 = 每天）——段归属按「谷段开始时刻所在日」算
//（2026-09-11 决明拍板）：跨午夜段 t<e 的部分是前一天谷段的延续，查 days 含昨天
//（(getDay+6)%7）；全天形态整日谷价查当天
export function inValleyTime(createdAtMs: number, start: string, end: string,
  days?: number[]): boolean {
  const d: Date = new Date(createdAtMs);
  const t: number = d.getHours() * 60 + d.getMinutes();
  const s: number = hmToMinutes(start);
  const e: number = hmToMinutes(end);
  if (s < 0 || e < 0) {
    return false; // 非法时间串防御（parse 侧已拦，兜底不进谷时）
  }
  if (s === e) {
    return days === undefined || days.length === 0 || days.includes(d.getDay());
  }
  if (days !== undefined && days.length > 0) {
    const segDay: number = t >= s ? d.getDay() : (d.getDay() + 6) % 7;
    if (!days.includes(segDay)) {
      return false;
    }
  }
  if (s < e) {
    return t >= s && t < e;
  }
  return t >= s || t < e;
}

// 多段判定（2026-09-11 谷时多时段笔）：逐段调 inValleyTime，任一段命中即谷价；空段列表 →
// 全不命中。★ 导出而非内联进 effectivePrices（后者私有）——断言脚本据此直达判定层，避免
// 「段列表命中 → 切谷价」只能靠 costOfEvent 间接验
export function inAnyValleySegment(createdAtMs: number, segments: ValleySegment[]): boolean {
  for (const seg of segments) {
    if (inValleyTime(createdAtMs, seg.start, seg.end, seg.days)) {
      return true;
    }
  }
  return false;
}

// 生效三价中转（谷时判价后的元/百万 tokens 三值；谷时回退谷时段价、cached 缺省回退
// 当段 input）
interface PriceTriple {
  input: number;
  cached: number;
  output: number;
}

// 生效三价（谷时落点判价后取值；cached 缺省回退当段 input——谷时回退谷时输入价）
function effectivePrices(price: ModelPriceConfig, createdAtMs: number): PriceTriple {
  const valley: ValleyPriceConfig | undefined = price.valley;
  if (valley !== undefined && inAnyValleySegment(createdAtMs, valley.segments)) {
    return {
      input: valley.input,
      cached: valley.cachedInput !== undefined ? valley.cachedInput : valley.input,
      output: valley.output
    };
  }
  return {
    input: price.input,
    cached: price.cachedInput !== undefined ? price.cachedInput : price.input,
    output: price.output
  };
}

// 单事件折算：输入费用 = (prompt−cached)×input（cached≤prompt 防御钳位）、缓存输入费用
// = cached×cachedInput、输出费用 = completion×output，各 ÷1e6（元/百万 tokens 口径）
export function costOfEvent(event: CostEventInput, price: ModelPriceConfig): CostBreakdown {
  const p: PriceTriple = effectivePrices(price, event.createdAt);
  const cached: number = Math.max(0, Math.min(event.cachedTokens, event.promptTokens));
  const uncached: number = event.promptTokens - cached;
  const inputCost: number = uncached * p.input / 1e6;
  const cachedCost: number = cached * p.cached / 1e6;
  const outputCost: number = event.completionTokens * p.output / 1e6;
  return {
    total: inputCost + cachedCost + outputCost,
    inputCost: inputCost,
    cachedCost: cachedCost,
    outputCost: outputCost
  };
}

// 价格 map 构建：键 = providerId+'/'+modelId → 已解析配置；未配置/坏 JSON 行不进 map
//（= 未配置，事件命中走 unpricedModels 计数）。Map 插入序 = rows 序（createdAt 升序，
// modelId 单键兜底「首个命中」的确定序）
export function buildPriceMap(rows: ModelPriceSourceRow[]): Map<string, ModelPriceConfig> {
  const map: Map<string, ModelPriceConfig> = new Map();
  for (const row of rows) {
    const cfg: ModelPriceConfig | null = parsePriceConfig(row.priceConfig);
    if (cfg === null) {
      continue;
    }
    map.set(row.providerId + '/' + row.modelId, cfg);
  }
  return map;
}

// 事件 → 价格查找：先复合键精确命中；providerId 为空（小任务事件快照兜底态）或复合键
// 未命中时，按 modelId 单键兜底首个命中（同模型名跨服务商共用价格的宽容路径）。null =
// 未配置（计入 unpricedModels）
export function priceFor(map: Map<string, ModelPriceConfig>, providerId: string,
  modelId: string): ModelPriceConfig | null {
  const direct: ModelPriceConfig | undefined = map.get(providerId + '/' + modelId);
  if (direct !== undefined) {
    return direct;
  }
  const suffix: string = '/' + modelId;
  const keys: string[] = [];
  map.forEach((value: ModelPriceConfig, key: string): void => {
    keys.push(key);
  });
  for (const key of keys) {
    if (key.endsWith(suffix)) {
      return map.get(key) ?? null;
    }
  }
  return null;
}

// 时段费用聚合：未配置价格的事件不进任何金额（其 modelId 进 unpricedModels 去重集）；
// byModel 费用降序 Top10；byPurpose 四类定序含零值行（展示侧隐藏全零）
export function aggregateCosts(events: CostEventInput[],
  map: Map<string, ModelPriceConfig>): CostAggregate {
  const totals: CostTotals = { total: 0, inputCost: 0, cachedCost: 0, outputCost: 0 };
  const modelSums: Map<string, number> = new Map();
  const purposeSums: Map<string, number> = new Map();
  const unpriced: Set<string> = new Set();
  let pricedEvents: number = 0;
  for (const event of events) {
    const price: ModelPriceConfig | null = priceFor(map, event.providerId, event.modelId);
    if (price === null) {
      unpriced.add(event.modelId !== '' ? event.modelId : '未知模型');
      continue;
    }
    pricedEvents++;
    const cost: CostBreakdown = costOfEvent(event, price);
    totals.total += cost.total;
    totals.inputCost += cost.inputCost;
    totals.cachedCost += cost.cachedCost;
    totals.outputCost += cost.outputCost;
    const modelKey: string = event.modelId !== '' ? event.modelId : '未知模型';
    modelSums.set(modelKey, (modelSums.get(modelKey) ?? 0) + cost.total);
    purposeSums.set(event.purpose, (purposeSums.get(event.purpose) ?? 0) + cost.total);
  }
  // 模型行费用降序（同额按模型名稳定序）；Top 截断（上限常量单源）
  const modelRows: CostByModelRow[] = [];
  modelSums.forEach((value: number, key: string): void => {
    modelRows.push({ modelId: key, total: value });
  });
  modelRows.sort((a: CostByModelRow, b: CostByModelRow): number => {
    if (b.total !== a.total) {
      return b.total - a.total;
    }
    return a.modelId < b.modelId ? -1 : 1;
  });
  const top: CostByModelRow[] = modelRows.slice(0, COST_TOP_MODEL_MAX);
  // 用途五类定序（COST_PURPOSES 序；无事件/全未计价 = 0 值行，展示侧隐藏）
  const purposeRows: CostByPurposeRow[] = [];
  for (const purpose of COST_PURPOSES) {
    purposeRows.push({ purpose: purpose, total: purposeSums.get(purpose) ?? 0 });
  }
  const unpricedModels: string[] = [];
  unpriced.forEach((id: string): void => {
    unpricedModels.push(id);
  });
  unpricedModels.sort();
  return {
    totals: totals,
    byModel: top,
    byPurpose: purposeRows,
    unpricedModels: unpricedModels,
    pricedEventCount: pricedEvents,
    pricedModelCount: modelRows.length
  };
}

// 金额格式化：≥1 元两位小数；<1 元四位小数（小额费用保精度——0.5 分级不失真）；0 → '0'
export function fmtCost(v: number): string {
  if (v >= 1) {
    return v.toFixed(2);
  }
  if (v > 0) {
    return v.toFixed(4);
  }
  return '0';
}

// 价格摘要（2026-09-11 价格模板：模板列表行卡副行消费）：'' / 坏 JSON / 无合法主价 →
// '未配置'（与 parsePriceConfig null 同判据——本函数只转述解析结果，不另立校验）；否则
// '输入 X · 输出 Y'，cachedInput 挂键（显式配置含 0）追加 ' · 缓存 Z'，valley 整块在
// 追加 ' · 含谷时价'。数字 String 原样输出（价格是元/百万 tokens 原值——不套 fmtCost，
// 那是金额两位小数化，语义不同）
export function priceSummary(json: string): string {
  const cfg: ModelPriceConfig | null = parsePriceConfig(json);
  if (cfg === null) {
    return '未配置';
  }
  let text: string = '输入 ' + String(cfg.input) + ' · 输出 ' + String(cfg.output);
  if (cfg.cachedInput !== undefined) {
    text += ' · 缓存 ' + String(cfg.cachedInput);
  }
  if (cfg.valley !== undefined) {
    text += ' · 含谷时价';
  }
  return text;
}
