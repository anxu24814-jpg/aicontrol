// 服务商与模型配置读取工具域（2026-09-13 任务书-工具补齐三件-20260913 §2.1）。
// 一个内置工具 get_provider_config（defaultEnabled=false + console-exclusive 反向拦截——
// 仅控制台助手可用，同 get_usage_stats 族）：
// · 无参 = 概览：服务商清单（逐家启用态 / 协议 / 接口形态 / 模型数 / 密钥条目数 / 自定义头与
//   自定义体布尔 / 余额开关）+ 当前会话生效连接（四级兜底链，读法与 ChatPageLoad.reloadConn
//   同链）+ 全局默认两键 + 未配置价格的模型数；
// · 传 provider = 该服务商模型清单（名称 / 模型 id / 启停 / 收藏 / 能力中文标签 / 是否已配价格）。
// ★ 敏感面硬约束：**不读** providers 三列明文（headers / balance_key / balance_headers）——
//   自定义头与自定义体只回布尔（判定在存储层 ProviderDb.hasCustomHeaders / hasCustomBody，
//   本文件零出现列名）、密钥只回条目计数与启用数；负向钉在 scripts/assert-app-domain.mjs
//   83 组（本文件剥注释后三列名零出现）。
// ★ 数据有界双封顶：条数上限 PROVIDER_MODEL_LIST_MAX + 字符预算 PROVIDER_RESULT_MAX_CHARS
//   （两者取先到者截断，truncated 回未展示条数）——防清单序列化超 clipToolResult 8192 硬切
//   坏 JSON（全局截断的结构化裁剪只认搜索类载荷，其余载荷走硬切）。
// 边界：数据读取在 ProviderDb / ProviderKeyDb / ChatDb / AssistantDb，本文件只做工具协议层
//   （schema / desc / 校验纯函数 / 载荷组装纯函数 / 执行器）；校验与双封顶纯函数自包含可直跑
//   （断言脚本剥 import 后机械求值，searchHelpTopics 同款姿势）。
import { ToolExecutor } from './ToolContracts';
import { ActiveConnectionInfo, DEFAULT_MODEL_KEY, DEFAULT_PROVIDER_KEY, MODEL_CAP_LABELS,
  ModelRow, ProviderRow, capLabels, effectiveCaps, hasCustomBody, hasCustomHeaders, queryAllModels,
  queryModels, queryProviders, resolveActiveConnection } from '../store/ProviderDb';
import { ProviderKeyRow, queryProviderKeys } from '../store/ProviderKeyDb';
import { ASSISTANT_DEFAULT_ID, AssistantRow, queryAssistant,
  queryConversationAssistantId } from '../store/AssistantDb';
import { ConversationOverride, queryConversationOverride } from '../store/ChatDb';
import { parsePriceConfig } from '../store/CostStatsCalc';
import { CHAT_ACTIVE_CONV_KEY } from './ToolChatSearch';

// 工具名常量 TOOL_GET_PROVIDER_CONFIG 归口 ToolTypes.ets（注册/反向拦截/seed 同源引用）。

// 模型清单条数上限（超出部分只回数量，防无界）
export const PROVIDER_MODEL_LIST_MAX: number = 60;
// 结果字符预算（照 search_chats 的 CHAT_TOOL_RESULT_MAX_CHARS 先例——清单类载荷自带预算，
// 防序列化超全局 8192 硬切线被切成坏 JSON）
export const PROVIDER_RESULT_MAX_CHARS: number = 4000;

// 入参 schema（provider 可选——不传返回概览；精确匹配服务商名称）
export const GET_PROVIDER_CONFIG_SCHEMA: string =
  '{"type":"object","properties":{"provider":{"type":"string",' +
  '"description":"服务商名称，精确填写；不传则只返回服务商清单概览"}}}';

// 工具 desc（调用纪律 + 返回面自述；能力标签清单与条数上限随常量动态拼——禁字面量双源。
// 文案守宪法「面向用户文案写作规约」精神——无冒号分号括号连环与等号分列）
export function buildGetProviderConfigDesc(): string {
  return '读取本应用的服务商与模型配置。只读查询，不修改任何内容。不传 provider 时返回服务商' +
    '概览，含每家的启用状态、协议、接口形态、模型数量、密钥条目数量、是否配置了自定义请求头' +
    '或自定义请求体、余额查询开关，另附当前会话正在使用的服务商与模型，以及全局默认模型。' +
    '用户询问配置了几个服务商、都有哪些服务商、现在用的是哪个模型时调用。传 provider 时返回' +
    '该服务商的模型清单，含名称、模型标识、是否启用、是否收藏、能力标签与是否已配置价格，' +
    '用户询问某个服务商有哪些模型、哪些模型没配价格时调用。清单最多展示 ' +
    PROVIDER_MODEL_LIST_MAX + ' 个模型，超出部分只给数量。模型能力标签取值有 ' +
    MODEL_CAP_LABELS.join('、') + '。密钥只返回条目数量与启用数量，不返回密钥内容。' +
    '回答服务商与模型配置前先调用本工具查实，不要凭记忆或猜测回答。';
}

// 参数校验结果（纯函数可断言）
export interface GetProviderConfigValidation {
  ok: boolean;
  provider: string; // '' = 无参概览
  error: string;
}

function rejectGetProviderConfig(error: string): GetProviderConfigValidation {
  return { ok: false, provider: '', error: error };
}

// 参数校验纯函数：坏 JSON 拒且回显两种用法；缺 provider 或空白串 = 无参概览（与用量统计
// 工具 range 缺省同形）
export function validateGetProviderConfigArgs(argsJson: string): GetProviderConfigValidation {
  let provider: string = '';
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    const raw: Object | undefined = parsed['provider'];
    if (typeof raw === 'string') {
      provider = raw.trim();
    }
  } catch (e) {
    return rejectGetProviderConfig('参数解析失败，provider 传服务商名称可查该家模型清单，' +
      '不传则返回服务商概览');
  }
  return { ok: true, provider: provider, error: '' };
}

// 服务商定位结果（三态——服务商名无唯一性守卫，按名定位须区分 0 命中与多命中，同
// manage_prompts 的处置口径）
export interface ProviderLocateResult {
  state: string; // 'none' / 'one' / 'multi'
  rows: ProviderRow[];
}

export function locateProvidersByName(rows: ProviderRow[], name: string): ProviderLocateResult {
  const hits: ProviderRow[] = rows.filter((row: ProviderRow): boolean => row.name === name);
  if (hits.length === 0) {
    return { state: 'none', rows: [] };
  }
  if (hits.length > 1) {
    return { state: 'multi', rows: hits };
  }
  return { state: 'one', rows: hits };
}

// ── 载荷结构（概览与清单两态；键集合被断言恰等钉死——多键少键均红）──

export interface ProviderSummaryPayload {
  name: string;
  enabled: boolean;
  protocol: string;
  endpoint: string;
  modelCount: number;
  enabledModelCount: number;
  keyCount: number;
  enabledKeyCount: number;
  customHeaders: boolean; // headers 列只判有无，不回内容
  customBody: boolean; // bodyOverrides 列只判有无，不回内容
  balanceEnabled: boolean;
}

export interface ProviderActivePayload {
  assistantName: string;
  sessionOverride: boolean;
  providerName: string;
  modelName: string;
}

export interface ProviderDefaultsPayload {
  providerName: string;
  modelName: string;
}

export interface ProviderOverviewPayload {
  providers: ProviderSummaryPayload[];
  truncated: number;
  active: ProviderActivePayload | null;
  defaults: ProviderDefaultsPayload;
  unpricedModelCount: number;
  note: string;
}

export interface ProviderModelPayload {
  name: string;
  modelId: string;
  enabled: boolean;
  favorite: boolean;
  caps: string[];
  priced: boolean;
}

export interface ProviderModelsPayload {
  provider: string;
  models: ProviderModelPayload[];
  truncated: number;
  note: string;
}

// 概览双封顶（条数上限不适用——服务商数量天然小；只受字符预算约束）：按条数递减重试直到
// 序列化长度进预算或清空（照 clipSearchPayload 的收敛姿势）
export function buildProviderOverviewPayload(providers: ProviderSummaryPayload[],
  active: ProviderActivePayload | null, defaults: ProviderDefaultsPayload,
  unpricedModelCount: number, note: string): ProviderOverviewPayload {
  let count: number = providers.length;
  while (true) {
    const truncated: number = providers.length - count;
    const payload: ProviderOverviewPayload = {
      providers: providers.slice(0, count),
      truncated: truncated,
      active: active,
      defaults: defaults,
      unpricedModelCount: unpricedModelCount,
      note: truncated > 0 ? note + '服务商较多，仅展示前 ' + count + ' 家。' : note
    };
    if (JSON.stringify(payload).length <= PROVIDER_RESULT_MAX_CHARS || count === 0) {
      return payload;
    }
    count = Math.floor(count * 0.9);
  }
}

// 模型清单双封顶（条数上限 + 字符预算，取先到者）：totalCount = 该服务商全量模型数，
// truncated = 未展示条数；note 有截断时附收窄提示
export function buildProviderModelsPayload(providerName: string, models: ProviderModelPayload[],
  totalCount: number): ProviderModelsPayload {
  let count: number = models.length < PROVIDER_MODEL_LIST_MAX ? models.length :
    PROVIDER_MODEL_LIST_MAX;
  while (true) {
    const truncated: number = totalCount - count;
    const payload: ProviderModelsPayload = {
      provider: providerName,
      models: models.slice(0, count),
      truncated: truncated,
      note: truncated > 0 ?
        '该服务商模型较多，仅展示前 ' + count + ' 个，其余未展示，可到服务商管理页查看全量。' : ''
    };
    if (JSON.stringify(payload).length <= PROVIDER_RESULT_MAX_CHARS || count === 0) {
      return payload;
    }
    count = Math.floor(count * 0.9);
  }
}

// 服务商与模型读取执行器（只读）：校验 → 查全量服务商 → 无参走概览 / 传参走清单；零写库
// 零改状态零广播（查询走 ProviderDb / ProviderKeyDb / ChatDb / AssistantDb 既有函数，
// ResultSet 由各层 close；本文件只读 AppStorage 的两个中转键）
export class GetProviderConfigExecutor implements ToolExecutor {
  async execute(argsJson: string): Promise<string> {
    const v: GetProviderConfigValidation = validateGetProviderConfigArgs(argsJson);
    if (!v.ok) {
      return JSON.stringify({ error: v.error });
    }
    const providers: ProviderRow[] = await queryProviders();
    if (v.provider !== '') {
      return this.buildModelsResult(providers, v.provider);
    }
    return this.buildOverviewResult(providers);
  }

  // 概览态：密钥条目逐家查 + 全量模型一次拉齐本地分组计数（免逐家模型查询）+ 当前会话
  // 生效连接（会话链解析失败不阻断整份概览——该段回 null 并在 note 说明）
  private async buildOverviewResult(providers: ProviderRow[]): Promise<string> {
    const keyTasks: Promise<ProviderKeyRow[]>[] =
      providers.map((row: ProviderRow): Promise<ProviderKeyRow[]> => queryProviderKeys(row.id));
    const keyLists: ProviderKeyRow[][] = await Promise.all(keyTasks);
    const models: ModelRow[] = await queryAllModels();
    const active: ProviderActivePayload | null = await this.resolveSessionActive();
    const modelCounts: Map<string, number> = new Map();
    const enabledCounts: Map<string, number> = new Map();
    let unpriced: number = 0;
    for (const model of models) {
      modelCounts.set(model.providerId, (modelCounts.get(model.providerId) ?? 0) + 1);
      if (model.enabled) {
        enabledCounts.set(model.providerId, (enabledCounts.get(model.providerId) ?? 0) + 1);
      }
      if (parsePriceConfig(model.priceConfig) === null) {
        unpriced++;
      }
    }
    const summaries: ProviderSummaryPayload[] = [];
    for (let i: number = 0; i < providers.length; i++) {
      const row: ProviderRow = providers[i];
      const keys: ProviderKeyRow[] = keyLists[i];
      let enabledKeys: number = 0;
      for (const key of keys) {
        if (key.enabled) {
          enabledKeys++;
        }
      }
      summaries.push({
        name: row.name,
        enabled: row.enabled,
        protocol: row.protocol,
        endpoint: row.endpoint,
        modelCount: modelCounts.get(row.id) ?? 0,
        enabledModelCount: enabledCounts.get(row.id) ?? 0,
        keyCount: keys.length,
        enabledKeyCount: enabledKeys,
        customHeaders: hasCustomHeaders(row),
        customBody: hasCustomBody(row),
        balanceEnabled: row.balanceEnabled
      });
    }
    let note: string = '需要某个服务商的模型清单时，可再传 provider 参数查询。';
    if (active === null) {
      note = '当前会话正在使用的模型本次未能解析，会话链只在会话页内可读。' + note;
    }
    const payload: ProviderOverviewPayload = buildProviderOverviewPayload(summaries, active,
      this.resolveDefaults(providers), unpriced, note);
    return JSON.stringify(payload);
  }

  // 清单态：按名定位三态——0 命中回现有名单引导改名，多命中拒歧义并回显同名各家差异
  private async buildModelsResult(providers: ProviderRow[], name: string): Promise<string> {
    const located: ProviderLocateResult = locateProvidersByName(providers, name);
    if (located.state === 'none') {
      if (providers.length === 0) {
        return JSON.stringify({ error: '未找到服务商「' + name +
          '」。应用还没有配置服务商，请提醒用户先到 设置 → 服务商管理 添加服务商。' });
      }
      const names: string = providers.map((row: ProviderRow): string => row.name).join('、');
      return JSON.stringify({ error: '未找到服务商「' + name + '」。现有服务商：' + names });
    }
    if (located.state === 'multi') {
      const briefs: string[] = located.rows.map((row: ProviderRow): string =>
        row.name + '（' + row.protocol + ' / ' + (row.enabled ? '已启用' : '已停用') + '）');
      return JSON.stringify({ error: '有 ' + located.rows.length + ' 家服务商都叫「' + name +
        '」：' + briefs.join('、') + '。为避免答错，请让用户先确认是其中哪一家。' });
    }
    const hit: ProviderRow = located.rows[0];
    const rows: ModelRow[] = await queryModels(hit.id, '');
    const models: ProviderModelPayload[] = rows.map((row: ModelRow): ProviderModelPayload => {
      return {
        name: row.name !== '' ? row.name : row.modelId,
        modelId: row.modelId,
        enabled: row.enabled,
        favorite: row.favorite,
        caps: capLabels(effectiveCaps(row)),
        priced: parsePriceConfig(row.priceConfig) !== null
      };
    });
    return JSON.stringify(buildProviderModelsPayload(hit.name, models, models.length));
  }

  // 全局默认两键解析（默认模型槽：'' = 未配置回空串；服务商 id 查不到回空串——不猜名字）
  private resolveDefaults(providers: ProviderRow[]): ProviderDefaultsPayload {
    const providerId: string = AppStorage.get<string>(DEFAULT_PROVIDER_KEY) ?? '';
    const modelId: string = AppStorage.get<string>(DEFAULT_MODEL_KEY) ?? '';
    let providerName: string = '';
    for (const row of providers) {
      if (row.id === providerId) {
        providerName = row.name;
        break;
      }
    }
    return { providerName: providerName, modelName: modelId };
  }

  // 当前会话生效连接（只读）：会话 id 走 ChatSendCtrl 每次发送现写的中转键（CHAT_ACTIVE_CONV_KEY），
  // 读法与 ChatPageLoad.reloadConn 同链——会话级覆盖 + 会话归属助手 + 四级兜底链。中转键缺失
  // 或链上任一步失败 = 该段回 null（不阻断整份概览，note 说明）；四级链全落空同样回 null。
  // 无行会话（还没落库）按默认助手归属解析，与发送链兜底一致。★ 方法名与 ProviderDb 的
  // resolveActiveConnection 刻意区分（同名会让「模块级函数调用」与「自身递归」难辨）
  private async resolveSessionActive(): Promise<ProviderActivePayload | null> {
    const convId: string = AppStorage.get<string>(CHAT_ACTIVE_CONV_KEY) ?? '';
    if (convId === '') {
      return null;
    }
    let override: ConversationOverride | null = null;
    try {
      override = await queryConversationOverride(convId);
    } catch (e) {
      override = null;
    }
    let ownerId: string = ASSISTANT_DEFAULT_ID;
    try {
      const rowId: string | null = await queryConversationAssistantId(convId);
      if (rowId !== null && rowId !== '') {
        ownerId = rowId;
      }
    } catch (e) {
      ownerId = ASSISTANT_DEFAULT_ID;
    }
    const overrideProviderId: string = override !== null ? override.modelProviderId : '';
    const overrideModelId: string = override !== null ? override.modelId : '';
    let info: ActiveConnectionInfo | null = null;
    try {
      info = await resolveActiveConnection(ownerId, overrideProviderId, overrideModelId);
    } catch (e) {
      info = null;
    }
    if (info === null) {
      return null;
    }
    let assistantName: string = '';
    try {
      const owner: AssistantRow | null = await queryAssistant(ownerId);
      assistantName = owner !== null ? owner.name : '';
    } catch (e) {
      assistantName = '';
    }
    return {
      assistantName: assistantName,
      sessionOverride: overrideProviderId !== '' && overrideModelId !== '',
      providerName: info.providerName,
      modelName: info.conn.model
    };
  }
}
