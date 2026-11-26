// 内置图表工具域（chart_display 形态；matplotlib 形态已排除——依赖 Linux rootfs + python
// 沙箱，鸿蒙无等价物）。机制蓝本 = rik chart_display（只采信机制、禁抄码）：
// · **入参即数据、回执即确认、渲染即解析入参**——图表数据全在工具调用 arguments JSON 里，
//   本件 execute 纯校验零绘制、**不产生任何图片文件**（合法回 {"success":true,...}；非法回
//   INVALID_CHART + 人话原因供模型自纠，对齐「工具回执错误文案原样透传」拍板口径）；渲染层
//   （components/chat/ChatToolChartCard.ets）在消息气泡解析**同一入参 JSON** 画 Canvas 图表
//   卡——入参 JSON 随消息落库 = 天然存档零迁移（历史回放重解析重绘）。
// · 上限与轴约束（上限值 = rik 真机验证值）：12 系列 × 每系列 2000 点；bar 恒从 0（禁 y 轴
//   min/max/log）；line/bar 的 x 轴是类目轴（禁 min/max/log）；values（line/bar）与
//   points（scatter）按 style 互斥——约束文本写进 desc 与属性 description 供模型自纠（数字
//   随 CHART_* 常量动态拼，禁字面量双源）。★ categories **空数组合法**（空 = 视同未给
//   类目，渲染层退序号标签——模型空类目高发，勿拒）。
// · 政策字段显式拍板：**不标 consoleCore / consoleExclusive**（缺省 = 不对控制台助手开放，
//   开放须另拍板）；**不设 preflight**（只读展示类零外部副作用、零落库、零系统能力，写明防
//   后来者好心补卡）；**defaultEnabled=false**（用户未在助手工具页「图表」卡启用前不进任何
//   默认集合、模型看不到，避免存量助手行为突变）。
// · 纯函数区（解析/校验/回执构造）零 import 依赖——断言直跑（照 HttpTemplate /
//   ChatToolDiffBlock 纯区先例，本区禁引用任何 import 绑定）。
// · 注册面自洽：组标签常量 + 注册函数同居本件**文件末段**（ToolTypes 只留一字接线；切片锚
//   与断言夹具的关系见末位段注释——与 ToolMount.ets 末位段同构）。
import { ToolExecutor, toolArgsParseErrorText } from './ToolContracts';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { toolRegistry } from './ToolRegistry';
import { TOOL_CHART_DISPLAY } from './ToolIds';

// ═══ 纯函数区（零 import 依赖——断言直跑；本区禁引用任何 import 绑定）═══

// 系列数 / 单系列数据点上限（rik 真机验证值；desc 与 schema 的数字源 = 本常量拼接）
export const CHART_MAX_SERIES: number = 12;
export const CHART_MAX_POINTS: number = 2000;
// 图表类型三值（enum 取值唯一来源——schema 与校验共用）
export const CHART_STYLE_LINE: string = 'line';
export const CHART_STYLE_BAR: string = 'bar';
export const CHART_STYLE_SCATTER: string = 'scatter';
export const CHART_STYLES: string[] = [CHART_STYLE_LINE, CHART_STYLE_BAR, CHART_STYLE_SCATTER];

// 散点数据点（scatter 系列元素）
export interface ChartPointData {
  x: number;
  y: number;
}

// 系列数据（line/bar 用 values 非空、scatter 用 points 非空——互斥由校验/解析两侧保证；
// 空侧恒为空数组，渲染层按 style 取用）
export interface ChartSeriesData {
  name: string;
  values: number[];
  points: ChartPointData[];
}

// 轴设置（min/max = Number.NaN 表未给；log = 对数轴；label = 轴名）
export interface ChartAxisData {
  label: string;
  min: number;
  max: number;
  log: boolean;
}

// 图表视图（宽松解析产物——渲染层唯一消费形态；坏字段在解析时丢弃、构不成图回 null）
export interface ChartSpecData {
  style: string;
  title: string;
  categories: string[];
  xAxis: ChartAxisData;
  yAxis: ChartAxisData;
  series: ChartSeriesData[];
}

// 有限数取值（非数 / NaN / Infinity 一律 NaN——JSON.parse 产不出 Infinity，防御位）
function numberOrNaN(raw: Object | undefined): number {
  return typeof raw === 'number' && Number.isFinite(raw) ? raw : Number.NaN;
}

// 轴对象取字段（非对象一律 default）
function axisMember(raw: Object | undefined, key: string): Object | undefined {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    return undefined;
  }
  return (raw as Record<string, Object>)[key];
}

// 轴布尔位（严格 === true 才真——"true" 字符串不算）
function axisFlagTrue(raw: Object | undefined, key: string): boolean {
  return axisMember(raw, key) === true;
}

// 轴对象解析（宽松：坏轴对象回缺省轴；label 非串丢、min/max 非有限数记 NaN、log 非真丢）
function parseChartAxis(raw: Object | undefined): ChartAxisData {
  const axis: ChartAxisData = { label: '', min: Number.NaN, max: Number.NaN, log: false };
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    return axis;
  }
  const labelRaw: Object | undefined = (raw as Record<string, Object>)['label'];
  axis.label = typeof labelRaw === 'string' ? labelRaw : '';
  axis.min = numberOrNaN((raw as Record<string, Object>)['min']);
  axis.max = numberOrNaN((raw as Record<string, Object>)['max']);
  axis.log = (raw as Record<string, Object>)['log'] === true;
  return axis;
}

// 宽松解析（渲染层入口）：JSON 坏 / style 非法 / 零有效系列 → null（调用方零渲染退原始
// JSON 面板，不崩不错画）；坏系列项 / 坏点项逐项丢弃，空数据系列弃。类目表仅在「全数系列
// 长度一致」时保留（否则丢表退序号标签）；scatter 恒丢类目表（该型不用）
export function parseChartSpec(inputJson: string): ChartSpecData | null {
  if (inputJson === '') {
    return null;
  }
  let parsed: Object;
  try {
    parsed = JSON.parse(inputJson);
  } catch (e) {
    return null;
  }
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
    return null;
  }
  const root = parsed as Record<string, Object>;
  const styleRaw: Object | undefined = root['style'];
  const style: string = typeof styleRaw === 'string' ? styleRaw.trim().toLowerCase() : '';
  if (!CHART_STYLES.includes(style)) {
    return null;
  }
  const titleRaw: Object | undefined = root['title'];
  const title: string = typeof titleRaw === 'string' ? titleRaw : '';
  const isScatter: boolean = style === CHART_STYLE_SCATTER;
  // 类目表（仅字符串项全通过才收；坏项整表弃用）
  const categories: string[] = [];
  const catsRaw: Object | undefined = axisMember(root['x_axis'], 'categories');
  let catsOk: boolean = Array.isArray(catsRaw);
  if (catsOk) {
    for (const item of catsRaw as Object[]) {
      if (typeof item !== 'string') {
        catsOk = false;
        break;
      }
      categories.push(item);
    }
  }
  if (!catsOk) {
    categories.length = 0;
  }
  const seriesRaw: Object | undefined = root['series'];
  if (!Array.isArray(seriesRaw)) {
    return null;
  }
  const series: ChartSeriesData[] = [];
  let uniformLength: number = -1;
  for (const item of seriesRaw as Object[]) {
    if (series.length >= CHART_MAX_SERIES) {
      break; // 渲染上限（校验拦在前；此处防越限入参画爆——宽松解析不报错只截断）
    }
    if (typeof item !== 'object' || item === null || Array.isArray(item)) {
      continue;
    }
    const rec = item as Record<string, Object>;
    const nameRaw: Object | undefined = rec['name'];
    const name: string = typeof nameRaw === 'string' ? nameRaw : '';
    if (name === '') {
      continue;
    }
    if (isScatter) {
      const points: ChartPointData[] = [];
      const ptsRaw: Object | undefined = rec['points'];
      if (Array.isArray(ptsRaw)) {
        for (const pt of ptsRaw as Object[]) {
          if (points.length >= CHART_MAX_POINTS) {
            break;
          }
          if (typeof pt !== 'object' || pt === null || Array.isArray(pt)) {
            continue;
          }
          const x: number = numberOrNaN((pt as Record<string, Object>)['x']);
          const y: number = numberOrNaN((pt as Record<string, Object>)['y']);
          if (!Number.isNaN(x) && !Number.isNaN(y)) {
            points.push({ x: x, y: y });
          }
        }
      }
      if (points.length === 0) {
        continue;
      }
      series.push({ name: name, values: [], points: points });
    } else {
      const values: number[] = [];
      const valsRaw: Object | undefined = rec['values'];
      if (Array.isArray(valsRaw)) {
        for (const v of valsRaw as Object[]) {
          if (values.length >= CHART_MAX_POINTS) {
            break;
          }
          const n: number = numberOrNaN(v);
          if (!Number.isNaN(n)) {
            values.push(n);
          }
        }
      }
      if (values.length === 0) {
        continue;
      }
      series.push({ name: name, values: values, points: [] });
      uniformLength = uniformLength < 0 ? values.length : uniformLength;
      if (values.length !== uniformLength) {
        uniformLength = -2; // -2 = 已失齐（终检处按不一致处理）
      }
    }
  }
  if (series.length === 0) {
    return null;
  }
  // 类目表生效条件 = 非散点 ∧ 非空 ∧ 与全部系列长度一致（不齐丢表退序号）
  if (isScatter || categories.length === 0 || uniformLength !== categories.length) {
    categories.length = 0;
  }
  return {
    style: style,
    title: title,
    categories: categories,
    xAxis: parseChartAxis(root['x_axis']),
    yAxis: parseChartAxis(root['y_axis']),
    series: series
  };
}

// 校验拒绝文案统一前缀（模型读回执自纠的稳定记号；rik 同款记号）
function chartInvalid(reason: string): string {
  return 'INVALID_CHART：' + reason;
}

// 轴校验（'' = 过）：numericAxis = 该轴是否数值轴——scatter 的 x/y 与 line 的 y 是数值轴；
// line/bar 的 x（类目轴）与 bar 的 y（恒从 0）不是。非数值轴出现 min/max/log = 拒；数值轴的
// min/max 须为数字且 min < max；log 非布尔拒；log=true 的数据正值性在系列段判
function validateChartAxis(raw: Object | undefined, axisName: string,
  numericAxis: boolean): string {
  if (raw === undefined) {
    return '';
  }
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    return chartInvalid(axisName + ' 必须是对象');
  }
  const rec = raw as Record<string, Object>;
  const hasMin: boolean = rec['min'] !== undefined;
  const hasMax: boolean = rec['max'] !== undefined;
  const logRaw: Object | undefined = rec['log'];
  const hasLog: boolean = logRaw !== undefined;
  if (!numericAxis && (hasMin || hasMax || hasLog)) {
    if (axisName === 'y 轴') {
      return chartInvalid('bar 图的 y 轴恒从 0 开始，不支持 min、max 或 log');
    }
    return chartInvalid(axisName + '是类目轴，只支持 label 与 categories，不支持 min、max 或 log');
  }
  if (hasMin && Number.isNaN(numberOrNaN(rec['min']))) {
    return chartInvalid(axisName + '的 min 必须是数字');
  }
  if (hasMax && Number.isNaN(numberOrNaN(rec['max']))) {
    return chartInvalid(axisName + '的 max 必须是数字');
  }
  if (hasLog && typeof logRaw !== 'boolean') {
    return chartInvalid(axisName + '的 log 必须是 true 或 false');
  }
  const min: number = numberOrNaN(rec['min']);
  const max: number = numberOrNaN(rec['max']);
  if (!Number.isNaN(min) && !Number.isNaN(max) && min >= max) {
    return chartInvalid(axisName + '的 min 必须小于 max');
  }
  return '';
}

// 入参校验（'' = 合法；非空 = INVALID_CHART + 人话原因——供模型读回执自纠）。执行器侧
// JSON 解析失败先走 toolArgsParseErrorText 通用回执（含收到内容开头片段），本函数内解析
// 失败为防御性回落（纯区不可引 ToolContracts 帮助函数）
export function validateChartArgs(argsJson: string): string {
  let parsed: Object;
  try {
    parsed = JSON.parse(argsJson);
  } catch (e) {
    return chartInvalid('参数不是合法的 JSON');
  }
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
    return chartInvalid('参数必须是一个 JSON 对象');
  }
  const root = parsed as Record<string, Object>;
  const styleRaw: Object | undefined = root['style'];
  const style: string = typeof styleRaw === 'string' ? styleRaw.trim().toLowerCase() : '';
  if (!CHART_STYLES.includes(style)) {
    return chartInvalid('style 必须是 line、bar 或 scatter 之一');
  }
  const isScatter: boolean = style === CHART_STYLE_SCATTER;
  const seriesRaw: Object | undefined = root['series'];
  if (!Array.isArray(seriesRaw)) {
    return chartInvalid('缺少 series 数组。series 是必填项，逐个给出系列名与数据');
  }
  const seriesArr: Object[] = seriesRaw as Object[];
  if (seriesArr.length === 0) {
    return chartInvalid('series 至少要有一个系列');
  }
  if (seriesArr.length > CHART_MAX_SERIES) {
    return chartInvalid('系列数量 ' + seriesArr.length + ' 超过上限 ' + CHART_MAX_SERIES +
      '，请合并或减少系列');
  }
  const xNumeric: boolean = isScatter;
  const yNumeric: boolean = !(style === CHART_STYLE_BAR);
  const xReject: string = validateChartAxis(root['x_axis'], 'x 轴', xNumeric);
  if (xReject !== '') {
    return xReject;
  }
  const yReject: string = validateChartAxis(root['y_axis'], 'y 轴', yNumeric);
  if (yReject !== '') {
    return yReject;
  }
  // 类目表（x 轴）：存在须为字符串数组且不超点上限，数量与各系列在下方逐系列对齐；空数组
  // 合法 = 视同未给类目（渲染层退序号标签）——模型空类目高发，勿拒
  const catsRaw: Object | undefined = axisMember(root['x_axis'], 'categories');
  let categoriesCount: number = -1;
  if (catsRaw !== undefined) {
    if (!Array.isArray(catsRaw)) {
      return chartInvalid('x 轴的 categories 必须是字符串数组');
    }
    const catArr: Object[] = catsRaw as Object[];
    if (catArr.length > CHART_MAX_POINTS) {
      return chartInvalid('categories 有 ' + catArr.length + ' 个类目，超过上限 ' +
        CHART_MAX_POINTS);
    }
    for (const c of catArr) {
      if (typeof c !== 'string') {
        return chartInvalid('x 轴的 categories 里必须都是字符串');
      }
    }
    categoriesCount = catArr.length;
  }
  const xLog: boolean = axisFlagTrue(root['x_axis'], 'log');
  const yLog: boolean = axisFlagTrue(root['y_axis'], 'log');
  for (let i = 0; i < seriesArr.length; i++) {
    const item: Object = seriesArr[i];
    if (typeof item !== 'object' || item === null || Array.isArray(item)) {
      return chartInvalid('第 ' + (i + 1) + ' 个系列必须是对象');
    }
    const rec = item as Record<string, Object>;
    const nameRaw: Object | undefined = rec['name'];
    if (typeof nameRaw !== 'string' || nameRaw === '') {
      return chartInvalid('第 ' + (i + 1) + ' 个系列缺少 name。每个系列都要有系列名');
    }
    if (isScatter) {
      if (rec['values'] !== undefined) {
        return chartInvalid('scatter 图用 points 不用 values。第 ' + (i + 1) +
          ' 个系列请改用 points');
      }
      const ptsRaw: Object | undefined = rec['points'];
      if (!Array.isArray(ptsRaw)) {
        return chartInvalid('scatter 图的第 ' + (i + 1) + ' 个系列缺少 points 数组');
      }
      const ptsArr: Object[] = ptsRaw as Object[];
      if (ptsArr.length === 0) {
        return chartInvalid('第 ' + (i + 1) + ' 个系列的 points 为空，至少要有一个点');
      }
      if (ptsArr.length > CHART_MAX_POINTS) {
        return chartInvalid('第 ' + (i + 1) + ' 个系列有 ' + ptsArr.length + ' 个点，超过每系列 ' +
          CHART_MAX_POINTS + ' 个的上限');
      }
      for (let k = 0; k < ptsArr.length; k++) {
        const pt: Object = ptsArr[k];
        if (typeof pt !== 'object' || pt === null || Array.isArray(pt)) {
          return chartInvalid('第 ' + (i + 1) + ' 个系列的第 ' + (k + 1) +
            ' 个点必须是含 x 与 y 的对象');
        }
        const prec = pt as Record<string, Object>;
        const x: number = numberOrNaN(prec['x']);
        const y: number = numberOrNaN(prec['y']);
        if (Number.isNaN(x) || Number.isNaN(y)) {
          return chartInvalid('第 ' + (i + 1) + ' 个系列的第 ' + (k + 1) +
            ' 个点的 x 与 y 必须是数字');
        }
        if (xLog && x <= 0) {
          return chartInvalid('x 轴开启了 log，所有 x 必须大于 0。第 ' + (i + 1) +
            ' 个系列的第 ' + (k + 1) + ' 个点不满足');
        }
        if (yLog && y <= 0) {
          return chartInvalid('y 轴开启了 log，所有 y 必须大于 0。第 ' + (i + 1) +
            ' 个系列的第 ' + (k + 1) + ' 个点不满足');
        }
      }
    } else {
      if (rec['points'] !== undefined) {
        return chartInvalid(style + ' 图用 values 不用 points。第 ' + (i + 1) +
          ' 个系列请改用 values');
      }
      const valsRaw: Object | undefined = rec['values'];
      if (!Array.isArray(valsRaw)) {
        return chartInvalid('第 ' + (i + 1) + ' 个系列缺少 values 数组');
      }
      const valsArr: Object[] = valsRaw as Object[];
      if (valsArr.length === 0) {
        return chartInvalid('第 ' + (i + 1) + ' 个系列的 values 为空，至少要有一个数值');
      }
      if (valsArr.length > CHART_MAX_POINTS) {
        return chartInvalid('第 ' + (i + 1) + ' 个系列有 ' + valsArr.length +
          ' 个数值，超过每系列 ' + CHART_MAX_POINTS + ' 个的上限');
      }
      // 空类目数组放行（categoriesCount === 0 视同未给类目，与 parseChartSpec 空表同口径）
      if (categoriesCount > 0 && valsArr.length !== categoriesCount) {
        return chartInvalid('x 轴的 categories 有 ' + categoriesCount + ' 个类目，第 ' + (i + 1) +
          ' 个系列有 ' + valsArr.length + ' 个数值，两者数量要一致');
      }
      for (let k = 0; k < valsArr.length; k++) {
        const n: number = numberOrNaN(valsArr[k]);
        if (Number.isNaN(n)) {
          return chartInvalid('第 ' + (i + 1) + ' 个系列的第 ' + (k + 1) + ' 个值不是数字');
        }
        if (yLog && n <= 0) {
          return chartInvalid('y 轴开启了 log，所有数值必须大于 0。第 ' + (i + 1) +
            ' 个系列的第 ' + (k + 1) + ' 个值不满足');
        }
      }
    }
  }
  return '';
}

// 成功回执（回执即确认——模型读到 success 与规模即可，勿在正文重复画数据）
interface ChartSuccessReceipt {
  success: boolean;
  style: string;
  series_count: number;
  point_count: number;
}

export function chartSuccessReceipt(spec: ChartSpecData): string {
  let pointCount: number = 0;
  for (const s of spec.series) {
    pointCount += spec.style === CHART_STYLE_SCATTER ? s.points.length : s.values.length;
  }
  const receipt: ChartSuccessReceipt = {
    success: true,
    style: spec.style,
    series_count: spec.series.length,
    point_count: pointCount
  };
  return JSON.stringify(receipt);
}

// ── 图表上屏判据（纯函数零 import——两消费方同源单条）──
// 消费方：①展示投影（ChatDisplayProjection——工具行提升为正文图表展示项）；②工具卡
//（ChatToolCard 展开区图表块）。判据 = 回执严格位 `success === true`（成功回执只由本件
// 产出：非法入参恒回 error，等价于已过 validateChartArgs）∧ 入参宽松解析成图（构不成图回
// null：失败调用留错误回执与原始面板，不画半截图）
export function chartReceiptSucceeded(outputJson: string): boolean {
  if (outputJson === '') {
    return false;
  }
  try {
    const parsed: Object = JSON.parse(outputJson);
    return (parsed as Record<string, Object>)['success'] === true;
  } catch (e) {
    return false;
  }
}

// 图表展示就绪判据（渲染与提升共用的唯一入口）：就绪 = 回执成功 ∧ 入参成图；回 null = 不上屏
//（零渲染退原始面板；不崩不错画）
export function chartDisplaySpec(inputJson: string, outputJson: string): ChartSpecData | null {
  if (!chartReceiptSucceeded(outputJson)) {
    return null;
  }
  return parseChartSpec(inputJson);
}

// ═══ 依赖区（消费导入绑定的 desc / schema / 执行器 / 注册面）═══

// 模型面 desc（中文三段式；「能力单源」红线——何时用本工具的引导只住 desc，系统提示词零
// 改动；上限数字随常量拼接零双源）
export const CHART_DISPLAY_DESC: string =
  '在对话里为用户画一幅图表并直接显示。用户的问题涉及数据对比、趋势或分布，且已有具体数值时调用。' +
  'style 选 line 折线、bar 柱状或 scatter 散点；title 是图表标题，可省略；x_axis 与 y_axis 提供轴标签与轴设置；series 是数据系列数组，每个系列给 name 与数据。' +
  'line 与 bar 用 values 数字数组，可配 x_axis.categories 类目名，数量须与每个系列的 values 一致；scatter 用 points 数组，每项含数字 x 与 y。' +
  '最多 ' + CHART_MAX_SERIES + ' 个系列，每个系列最多 ' + CHART_MAX_POINTS + ' 个数据点。' +
  'bar 图 y 轴恒从 0 开始，不支持 min、max 或 log；line 与 bar 的 x 轴是类目轴，不支持 min、max 或 log。' +
  'line 与 bar 不支持 points，scatter 不支持 values，两者不能同时使用，数据必须是有限数字。' +
  '调用成功后图表会显示在对话里，不要在回答里再用文本重复画出全部数据。';

// 模型面 schema（JSON Schema 原串——ArkTS 禁无类型对象字面量，全工具同款姿势；约束文本
// 与 desc 同源互证，数字随常量拼接）
export const CHART_DISPLAY_SCHEMA: string = '{"type":"object","properties":{' +
  '"style":{"type":"string","enum":["line","bar","scatter"],' +
    '"description":"图表类型。line 折线看趋势，bar 柱状比大小，scatter 散点看分布。"},' +
  '"title":{"type":"string","description":"图表标题，可省略。"},' +
  '"x_axis":{"type":"object","properties":{' +
    '"label":{"type":"string","description":"x 轴名称，可省略。"},' +
    '"categories":{"type":"array","items":{"type":"string"},"maxItems":' + CHART_MAX_POINTS +
      ',"description":"类目名列表，line 与 bar 用，数量须与每个系列的 values 一致。scatter 不用。"},' +
    '"min":{"type":"number","description":"数值轴下限，仅 scatter 的 x 轴支持，可省略。"},' +
    '"max":{"type":"number","description":"数值轴上限，仅 scatter 的 x 轴支持，可省略。"},' +
    '"log":{"type":"boolean","description":"对数轴，仅 scatter 的 x 轴支持，可省略。开启后该轴数值必须都大于 0。"}}},' +
  '"y_axis":{"type":"object","properties":{' +
    '"label":{"type":"string","description":"y 轴名称，可省略。"},' +
    '"min":{"type":"number","description":"y 轴下限，line 与 scatter 支持，可省略。bar 恒从 0 开始，不支持。"},' +
    '"max":{"type":"number","description":"y 轴上限，line 与 scatter 支持，可省略。bar 不支持。"},' +
    '"log":{"type":"boolean","description":"对数轴，line 与 scatter 支持，可省略。开启后数值必须都大于 0。bar 不支持。"}}},' +
  '"series":{"type":"array","minItems":1,"maxItems":' + CHART_MAX_SERIES +
    ',"items":{"type":"object","properties":{' +
    '"name":{"type":"string","description":"系列名，显示在图例里。"},' +
    '"values":{"type":"array","items":{"type":"number"},"maxItems":' + CHART_MAX_POINTS +
      ',"description":"line 与 bar 的数值数组，顺序对应 x_axis.categories，只给数字。"},' +
    '"points":{"type":"array","items":{"type":"object","properties":{' +
      '"x":{"type":"number"},"y":{"type":"number"}},"required":["x","y"]},"maxItems":' +
      CHART_MAX_POINTS + ',"description":"scatter 的散点数组，每项含数字 x 与 y。"}},' +
    '"required":["name"]}}},' +
  '"required":["style","series"]}';

// 图表执行器（纯校验零绘制——图由渲染层按同一入参 JSON 画；校验先于解析：非法入参不产图）
export class ChartDisplayExecutor implements ToolExecutor {
  execute(argsJson: string, _ctx: ToolExecutionContext): Promise<string> {
    try {
      const probe: Object = JSON.parse(argsJson);
      if (typeof probe !== 'object' || probe === null || Array.isArray(probe)) {
        return Promise.resolve(JSON.stringify({ error: toolArgsParseErrorText(argsJson) }));
      }
    } catch (e) {
      return Promise.resolve(JSON.stringify({ error: toolArgsParseErrorText(argsJson) }));
    }
    const reject: string = validateChartArgs(argsJson);
    if (reject !== '') {
      return Promise.resolve(JSON.stringify({ error: reject }));
    }
    const spec: ChartSpecData | null = parseChartSpec(argsJson);
    if (spec === null) {
      // 校验已过而宽松解析仍构不成图 = 防御位（理论不可达——宁可给错误回执，不静默成空图）
      return Promise.resolve(JSON.stringify({ error: chartInvalid('图表数据无法解析，请检查参数后重试') }));
    }
    return Promise.resolve(chartSuccessReceipt(spec));
  }
}

// ═══ 工具注册面（与 ToolMount.ets 末位段同构：自注册域件）═══
// ToolTypes 只留一字接线（宪法 1200 硬线纪律：聚合根越线后新增注册面必须落自注册域件）；
// 组标签常量随注册面同居本件（域件不能反向引聚合根，标签留聚合根则自注册无解）。政策面
// 拍板见文件头：零政策字段、零 preflight、defaultEnabled=false（不进任何默认集合与 seed）。
// ★ 形态约束：**自本件「export const CHART_MAX_SERIES」行至文件末须保持为连续可求值段**
//（常量 → 纯函数 → desc/schema → 执行器 → 组标签 + 注册函数）——断言夹具（sse-assert /
// set-pref-tool-check）自该行切片直拼求值副本（真实注册内容装进夹具同一注册表实例，非第二
// 份注册源；锚点须在常量行——desc/schema 的数字源在 CHART_MAX_* 上）；两件夹具锚点与本节
// 形态互锁——锚点行改名/移位前先同步两脚本，否则夹具副本求值即红。
export const TOOL_GROUP_CHART: string = '图表';

// 图表卡注册块（标题与工具页卡面无第二源）
export function registerChartTools(): void {
  toolRegistry.register({
    name: TOOL_CHART_DISPLAY,
    group: TOOL_GROUP_CHART,
    title: '生成图表',
    desc: CHART_DISPLAY_DESC,
    parametersJson: CHART_DISPLAY_SCHEMA,
    defaultEnabled: false,
    executor: new ChartDisplayExecutor()
  });
}
