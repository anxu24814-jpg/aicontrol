// 服务商域存储层（2026-08-30 服务商管理域新建，2026-08-29 M1 预建的 providers 表自此
// 接线）：providers / provider_models 两表 CRUD + 聊天页当前连接解析 + 遗留单连接迁移。
// 表结构/迁移在 ChatDbMigrate.ets（DB 单一初始化源），本文件只做数据操作——复用同一 RdbStore
// 句柄（ChatDb.sharedRdbStore），红线同源：ResultSet 用完 close / 查询有界（服务商与
// 模型清单均为用户手建小数据集，自然有界）/ 事务三件套删服务商（级联清模型行与 key 池
// 行防孤儿——Asset 池条目清理在调用方，非库内资源不入事务）。
// ★ 当前连接模型（聊天页消费）：defaultProviderId/defaultModelId 全局默认两键（2026-09-05
// 功能模型页，persistProp）+ 会话级模型覆盖两列（conversations.modelProviderId/modelId，
// DB v24）。解析 = 四级兜底链（2026-09-05 决明指令「会话页所选 > 会话所属的助手绑定 >
// 全局默认 > 首个启用模型，中途不停」，resolveActiveConnection 头注释）；key 池须有启用
// 条目（多 Key 池 v4——连接解析只验池非空、只查行不读明文；2026-08-31 明文最小化：「行在
// 明文无」＝解析通过、发送期逐支取钥失败跳过、全部失败 notice 呈报）；全链落空返回 null
//（聊天页提示去「服务商管理」配置）。
// ★ 2026-09-10 会话级覆盖层笔（方案-会话级覆盖层模型与联网-20260910）：**①级「会话页
// 所选」由原来的 activeProviderId/activeModelId 两个全局持久键改为会话级覆盖列**——原实现
// 的键与会话无关，任何一次会话内手选都被写成"全局最近选择"，此后所有新会话恒命中①级、
// 助手绑定（②级）永远轮不到（决明报障：助手默认 A，某会话选 B 后新会话全变 B）。两键**整体
// 退役**（常量/写点/清理函数/EntryAbility 注册一并删除，见变更记录三百二十四）；缓存失效
// 语义不变（②③④借用不留底）。
// 2026-08-30 三协议：ProviderRow 增 protocol（协议常量 AiTypes）/ headers（自定义头 JSON 串）。
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AiConnection, effectiveCapsOf, ENDPOINT_CHAT, ENDPOINT_RESPONSES, lookupContextBaseline,
  parseHeaderPairs, PROTOCOL_OPENAI, resolveReasoningStrategy, supportsThinkingOff,
  thinkingOptionsFor } from '../providers/AiTypes';
import { clearConversationModelOverride, nextMessageId, ProviderModelRow,
  sharedRdbStore } from './ChatDb';
import { LegacyConnection, loadConnection } from './KeyStore';
import { KEY_PICK_RANDOM, KEY_PICK_ROTATE, queryEnabledKeyIds, seedPoolKey } from './ProviderKeyDb';
import { clearAssistantBindingByModel, clearAssistantBindingByProvider,
  AssistantRow, queryAssistant } from './AssistantDb';

const DOMAIN: number = 0xD5A2;
const TAG: string = 'ProviderDb';

// ── 行模型（表列直映；UI 消费）──

export interface ProviderRow {
  id: string;
  name: string;
  baseUrl: string;
  enabled: boolean;
  sortOrder: number;
  createdAt: number;
  // 余额两字段（v3 列，2026-08-30 列表卡余额显示接线）：balanceEnabled = 余额总开关；
  // balanceLastText = 上次查询结果文本（详情页余额查询成功落库，重启保留——列表卡徽章
  // 与详情页顶部卡同源消费）
  balanceEnabled: boolean;
  balanceLastText: string;
  // 协议与自定义头（v4 列）：protocol = PROTOCOL_VALUES 之一（默认 openai）；headers =
  // JSON 串 [{k,v}]（空串 = 无；解析/序列化在 AiTypes，UI kv 行编辑）
  protocol: string;
  headers: string;
  // OpenAI 接口形态（v5 列）：endpoint = ENDPOINT_VALUES 之一（'chat' 默认 =
  // /chat/completions；'responses' = /v1/responses——仅对 openai 有意义，a/g 恒 'chat'）
  endpoint: string;
  // Anthropic 提示缓存（v12 列，2026-09-01）：promptCacheEnabled = 缓存开关（默认关——
  // 写入 1.25× 计费）；promptCacheTtl = '5m' | '1h'（官方两档）。仅 anthropic 协议消费
  //（请求体断点落点见 RequestCompose 头注释），其余协议列存在但开关 UI 不显示
  promptCacheEnabled: boolean;
  promptCacheTtl: string;
  // 自定义 Body 覆盖（v13 列，2026-09-02）：JSON 串 [{k,v}]——k = 请求体顶层键名，
  // v = 合法 JSON 值文本；'' = 无。解析/序列化复用 HeaderPair 工具（结构同构），
  // 发送时 ChatStreamBase.start 统一 merge 到请求体根对象（四协议单一落点）
  bodyOverrides: string;
  // 取钥方式（v32 列，2026-09-17）：KEY_PICK_ROTATE（默认，按池内卡片顺序轮换）|
  // KEY_PICK_RANDOM（每次发送随机挑起始支）——常量表在 ProviderKeyDb.ets，读侧已钳位；
  // 只影响发请求前的取钥起始位，协议链路零消费
  keyPickMode: string;
}

// provider_models 行（表定义与列语义见 ChatDb.ets SQL_CREATE_PROVIDER_MODELS 注释）
export type ModelRow = ProviderModelRow;

// ★ 2026-09-10 会话级覆盖层笔：原 `ACTIVE_PROVIDER_KEY` / `ACTIVE_MODEL_KEY` 两个全局键
// 已整体退役（①级改会话级覆盖列，见头注释）——**不要再引入任何"全局当前模型"键**：
// 它是本笔修掉那个 bug 的根因形态（会话内的选择被写成全局默认）。

// 全局默认模型两键（2026-09-05 功能模型页首项「默认模型」，持久化注册在 EntryAbility）：
// 发送链四级兜底的第 3 级来源——会话页所选与助手绑定均不可用时才消费（链细则见
// resolveActiveConnection 头注释）；'' = 未设置。功能模型页选择写入，重启保留
export const DEFAULT_PROVIDER_KEY: string = 'defaultProviderId';
export const DEFAULT_MODEL_KEY: string = 'defaultModelId';

// 标题生成两键（2026-09-05 功能模型页第二卡「标题生成」，2026-09-06 卡名去「模型」
// 二字，持久化注册在
// EntryAbility；'' = 未设置）：AI 会话标题生成的**显式开关**——★ 决明 2026-09-05 二次
// 拍板：两键未配置 = 功能未启用，静默不生成（无会话连接兜底，用户不配就不发任何请求）。
// 解析 = TitleGen 按 tryCandidate 同级标准单级验证（服务商启用 + 模型启用 + key 池非空）
// ——**禁走 resolveActiveConnection 四级链**（四级链容忍降级：槽位未配置时会被别的模型
// 顶上，而「标题两键未配置 = 标题功能未启用」必须硬区分）。功能模型页选择写入，重启保留
export const TITLE_PROVIDER_KEY: string = 'titleProviderId';
export const TITLE_MODEL_KEY: string = 'titleModelId';

// 推荐问题三键（2026-09-19 推荐问题功能，任务书-推荐问题-20260919；TITLE_* 同位——
// 功能模型页第六卡，持久化注册在 EntryAbility，备份白名单登记在 AppPreferences
// BACKUP_PREF_KEYS 功能模型绑定段）：AI 回复后的追问推荐生成配置。
// · SUGGEST_ENABLED_KEY 总开关——boolean，**默认 false 关**（BYOK 成本敏感 + ChatGPT
//   无开关扰人教训，每轮多一次请求由用户显式授权——决策 1）；
// · SUGGEST_PROVIDER_KEY/SUGGEST_MODEL_KEY 已选模型两键——两键齐 = 已配置，**未配置 =
//   零请求无兜底**（照标题生成 2026-09-05 拍板：不回退标题模型、禁走四级连接链——
//   决策同源：功能模型是显式开关，用户不配就不发任何请求）。
// 解析 = TitleGen.resolveTitleEndpoint 单级验证（服务商启用 + 模型启用 + key 池非空，
// 复用同一标准）；编排域 = common/SuggestGen.ets（TitleGen 同构独立域件）
export const SUGGEST_ENABLED_KEY: string = 'suggestEnabled';
export const SUGGEST_PROVIDER_KEY: string = 'suggestProviderId';
export const SUGGEST_MODEL_KEY: string = 'suggestModelId';

// OCR 键（2026-09-15 附件 OCR 二期，任务书-附件OCR链路 §3.8；★ 2026-09-16 决明拍板
// 「系统识别开关化」——引擎偏好由「两键齐否」的隐式口径改为显式开关；★★ 同日「内置识别
// 引擎」落地（方案-内置PaddleOCR §3.4）——引擎选中面由 Toggle 改为**卡内三分段胶囊**，
// 第五键 OCR_ENGINE_KEY 成为唯一写侧，偏好键退役为只读兜底）：
// · OCR_ENABLED_KEY 总开关——'true' | 'false'，**缺省/未写 = 开**（读侧 OcrEngine.ocrEnabled
//   按 ?? 'true' 兜底，读侧不依赖注册）；关 = 零识别零耗时回一期行为；
// · OCR_ENGINE_KEY 引擎三态——'system' | 'builtin' | 'model'；''/未写 = 按旧口径推导
//  （见 resolveOcrEngine）；非法值（脏写）同落未写推导。**写侧只写本键**（三段胶囊落键；
//   选模型完成时写 'model'——维持「选模型即用它」既有观感）；
// · OCR_PREFER_SYSTEM_KEY **退役为只读兜底**——UI 不再写，仅 resolveOcrEngine 推导时读
//  （老用户升级零行为变化：旧库只有偏好键，推导结果与开关化之前一致）；
// · OCR_PROVIDER_KEY/OCR_MODEL_KEY 已选模型两键——双键都非空 = 已选视觉引擎
//  （providers/OcrVisionApi，编排见 OcrEngine 头注释）；引擎非 model 时两键仍保留，作回退目标。
// 写点 = 功能模型页「文字识别」卡；persistProp 注册在 EntryAbility
//（缺省 'true' / ''〔引擎键〕/ ''〔偏好键〕/ '' / ''）、备份白名单登记在
// AppPreferences.BACKUP_PREF_KEYS 功能模型绑定段（11 键）
export const OCR_ENGINE_KEY: string = 'ocrEngine';
export const OCR_PREFER_SYSTEM_KEY: string = 'ocrPreferSystem';
export const OCR_PROVIDER_KEY: string = 'ocrProviderId';
export const OCR_MODEL_KEY: string = 'ocrModelId';
export const OCR_ENABLED_KEY: string = 'ocrEnabled';
// 引擎三态合法值（写侧与解析共用，禁散写字面量）
export const OCR_ENGINE_SYSTEM: string = 'system';
export const OCR_ENGINE_BUILTIN: string = 'builtin';
export const OCR_ENGINE_MODEL: string = 'model';

// OCR 引擎偏好缺省推导（2026-09-16）：偏好键未写（''）时按旧口径推导——引擎两键齐 = 用
// 已选模型（false），任一空 = 系统识别（true）。**升级路径零行为变化**：开关化之前已配
// 模型引擎的用户推导后仍用模型，没配过的仍是系统（真值表见 assert-attach-domain 100 组直跑）。
// 读侧共用：resolveOcrEngine 内部推导支（禁各写一遍三目链）
export function resolveOcrPreferSystem(raw: string, providerId: string, modelId: string): boolean {
  if (raw === 'true') {
    return true;
  }
  if (raw === 'false') {
    return false;
  }
  return providerId === '' || modelId === '';
}

// OCR 三态引擎解析（2026-09-16，方案-内置PaddleOCR §3.4；读侧单源 = OcrEngine 首选引擎 +
// 功能模型页分段胶囊镜像，禁各写一遍）。真值表（断言 105 组直跑）：
//   rawEngine 三合法值 → 直取；非法值 → 落未写推导；
//   未写 + 偏好 'false' + 模型两键齐 → 'model'（老用户升级零行为变化）；
//   未写 + 其余 → 'system'。
// 「偏好 'false' 但两键不齐」也落 'system'——旧 preferredEngine 同兜底（防空 modelId 进链，
// 那会以空名失败后再播「未成功」toast）
export function resolveOcrEngine(rawEngine: string, rawPreferSystem: string, providerId: string,
  modelId: string): string {
  if (rawEngine === OCR_ENGINE_SYSTEM || rawEngine === OCR_ENGINE_BUILTIN ||
    rawEngine === OCR_ENGINE_MODEL) {
    return rawEngine;
  }
  const preferSystem: boolean = resolveOcrPreferSystem(rawPreferSystem, providerId, modelId);
  return !preferSystem && providerId !== '' && modelId !== '' ? OCR_ENGINE_MODEL : OCR_ENGINE_SYSTEM;
}

// 连接解析输入变化广播键（2026-09-05 决明拍板方案 a「广播键 + @Watch 重解析」——自检轮
// P2 生效时机缺口闭环）：发送链连接 = ChatPage.conn 缓存（refs.conn() 现读），reloadConn
// 触发集 = {进页/手选模型/更多·刷新}，页签切换不销毁重建——助手绑定/全局默认修改后切回
// 会话页直接发送仍走旧缓存。本键 tick 递增广播（@Watch 对同值不触发，递增保证每次触发；
// 语义随 SESSION_LIST_RELOAD_KEY/fullInputCmd 先例）：
// 写点 = ModelSettingsPage 改绑保存链 + FunctionalModelPage 改全局默认 + ChatSendCtrl
// 面板覆盖助手（无行会话有效归属因子）+ AssistantPage 切换/删除归默认当前助手（同因子）
//（会话页手选不写——onPickModel 已显式 reloadConn）；读点 = ChatPage @StorageProp @Watch
// → reloadConn。级联清绑定（删服务商/删模型）不写——有会话级模型覆盖级联清
//（clearConversationModelOverride，在 deleteModel/deleteProvider 内）+ 发送失败 notice
// 呈报 + 「重试」重解析恢复路径，观察项登记
export const CONN_RESOLVE_TICK_KEY: string = 'connResolveTick';

// 模型能力码表（编辑模型页多选项 ↔ caps 逗号串的双向映射；顺序 = UI 展示序）
export const MODEL_CAP_CODES: string[] = ['tool', 'reason', 'web', 'vision', 'image'];
export const MODEL_CAP_LABELS: string[] = ['工具调用', '推理', '内置联网', '视觉理解', '图片生成'];

// caps 逗号串 → 文案数组（未知码忽略——码表演进不炸旧数据）
export function capLabels(caps: string): string[] {
  const set: string[] = caps.split(',').filter((code: string): boolean => code !== '');
  const labels: string[] = [];
  for (let i = 0; i < MODEL_CAP_CODES.length; i++) {
    if (set.includes(MODEL_CAP_CODES[i])) {
      labels.push(MODEL_CAP_LABELS[i]);
    }
  }
  return labels;
}

// 自定义头 / 自定义体有无判定（2026-09-13 工具补齐三件新增：get_provider_config 的
// customHeaders / customBody 两布尔位——三敏感列名不出存储层，工具域文件据此零出现
//（scripts/assert-app-domain.mjs 83 组负向钉）；判空走 parseHeaderPairs 与发送链同口径，
// 坏 JSON = 无覆盖 = false，只回布尔不回内容）
export function hasCustomHeaders(row: ProviderRow): boolean {
  return parseHeaderPairs(row.headers).length > 0;
}

export function hasCustomBody(row: ProviderRow): boolean {
  return parseHeaderPairs(row.bodyOverrides).length > 0;
}

// 模型行生效能力（2026-09-03 Cube 吸收 A1，任务书-Cube兼容画像与模型匹配引擎吸收）：
// capsUserModified = true → 用户 caps 原样（固化含显式全不勾）；false → 按模型名读时
// 派生（ModelRegistry 注册表，规则升级自动跟随，派生值不落库）。★ caps 的展示/勾选
// 回填一律走本函数，禁直读 row.caps——派生空 = 不误标，'web' 码无注册表来源仅用户
// 手改可设（01 卷 A1 明令）。纯函数，派生语义单源在 ModelRegistry.effectiveCapsOf
export function effectiveCaps(row: ModelRow): string {
  return effectiveCapsOf(row.capsUserModified, row.caps, row.modelId);
}

// 模型行生效上下文窗口（2026-09-17 DB v33，任务书-模型上下文窗口）：用户覆盖优先
//（row.contextWindow > 0 原样返回），未配置（0）则读内置参考值（ModelRegistry.
// lookupContextBaseline 按模型名派生，参考值不落库——与 effectiveCaps 的派生/覆盖同构）。
// 返回 0 = 两者皆无（调用方按「未配置」理解）。
// ★ 消费面（2026-09-17 会话上下文用量笔起）：连接侧取数单点 = contextWindowForConnection
//（其下经本函数）；历史裁剪、请求组装、费用估计仍不读它。**禁各处自行拼
// row.contextWindow || lookupContextBaseline**——本函数是消费面的单一入口
export function effectiveContextWindow(row: ModelRow): number {
  return row.contextWindow > 0 ? row.contextWindow : lookupContextBaseline(row.modelId);
}

// 连接的上下文窗口取数单点（2026-09-17 会话上下文用量——窗口值表〔v33 列 + 参考值表〕的
// 第一个消费方，方案 §3.3）：按 conn 的（providerId, modelId）取模型行 →
// effectiveContextWindow；行不存在（解析链外构造的连接/模型已删）返回 0 = 未知（按已拍板
// 降级 = 只显已用数不显占比）。取数时机 = 面板打开/切模型/切会话等事件点（异步一次，不进
// 渲染热路径——宪法性能红线）。失败吞错回 0（窗口未知只降级显示，不阻断会话链）
export async function contextWindowForConnection(conn: AiConnection): Promise<number> {
  try {
    const models: ModelRow[] = await queryModels(conn.providerId, 'chat');
    const row: ModelRow | undefined =
      models.find((m: ModelRow): boolean => m.modelId === conn.model);
    if (row === undefined) {
      return 0;
    }
    return effectiveContextWindow(row);
  } catch (e) {
    hilog.warn(DOMAIN, TAG, '上下文窗口取数失败（按未知降级）：%{public}s', (e as Error).message);
    return 0;
  }
}

// ── providers CRUD ──

// 全量服务商（sortOrder 升序、同序按创建先后；列表页拖拽序即此序）
export async function queryProviders(): Promise<ProviderRow[]> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('providers');
  predicates.orderByAsc('sortOrder');
  predicates.orderByAsc('createdAt');
  const columns: string[] = ['id', 'name', 'baseUrl', 'enabled', 'sortOrder', 'createdAt',
    'balance_enabled', 'balance_last_text', 'protocol', 'headers', 'endpoint',
    'prompt_cache_enabled', 'prompt_cache_ttl', 'body_overrides', 'key_pick_mode'];
  const result: relationalStore.ResultSet = await sharedRdbStore().query(predicates, columns);
  const rows: ProviderRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        id: result.getString(result.getColumnIndex('id')),
        name: result.getString(result.getColumnIndex('name')),
        baseUrl: result.getString(result.getColumnIndex('baseUrl')),
        enabled: result.getLong(result.getColumnIndex('enabled')) === 1,
        sortOrder: result.getLong(result.getColumnIndex('sortOrder')),
        createdAt: result.getLong(result.getColumnIndex('createdAt')),
        balanceEnabled: result.getLong(result.getColumnIndex('balance_enabled')) === 1,
        balanceLastText: result.getString(result.getColumnIndex('balance_last_text')),
        protocol: result.getString(result.getColumnIndex('protocol')),
        headers: result.getString(result.getColumnIndex('headers')),
        endpoint: result.getString(result.getColumnIndex('endpoint')),
        promptCacheEnabled: result.getLong(result.getColumnIndex('prompt_cache_enabled')) === 1,
        promptCacheTtl: result.getString(result.getColumnIndex('prompt_cache_ttl')) === '1h' ?
          '1h' : '5m', // 脏值钳位官方两档
        bodyOverrides: result.getString(result.getColumnIndex('body_overrides')),
        keyPickMode: result.getString(result.getColumnIndex('key_pick_mode')) === KEY_PICK_RANDOM ?
          KEY_PICK_RANDOM : KEY_PICK_ROTATE // 脏值/空值钳位 rotate（存量语义——promptCacheTtl 同款）
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// 新建服务商（name/baseUrl 必填非空由调用方校验；sortOrder = 当前最大值 + 1 追加到尾；
// protocol 默认 openai、endpoint 默认 chat——存量调用兼容，UI 保存链显式传值；
// headersJson/bodyJson 默认 ''——UI 新建保存链显式传入（2026-09-02 随 v13 补传：原新建
// 保存不写 headers 列 = 高级页签新建态配置丢失的既有缺陷，一并修复）
// enabled 默认 true（存量语义）；2026-09-21 B-3：预置 seed 由两步法（插入 + setProviderEnabled）
// 改一步插入——两步法第二步失败后重跑会被查重 continue 跳过，停用位永久补不上。
// ★ 本参数是**插入初值**，不是启用态通道——改已有行的启用态仍走 setProviderEnabled（单独通道）。
export async function insertProvider(name: string, baseUrl: string,
  protocol: string = PROTOCOL_OPENAI, endpoint: string = ENDPOINT_CHAT,
  headersJson: string = '', bodyJson: string = '',
  enabled: boolean = true): Promise<ProviderRow> {
  const all: ProviderRow[] = await queryProviders();
  let maxOrder: number = 0;
  for (const row of all) {
    if (row.sortOrder > maxOrder) {
      maxOrder = row.sortOrder;
    }
  }
  const now: number = Date.now();
  const row: ProviderRow = {
    id: nextMessageId('prov'),
    name: name,
    baseUrl: baseUrl,
    enabled: enabled,
    sortOrder: maxOrder + 1,
    createdAt: now,
    // 新服务商余额默认关/空（库列 DEFAULT 同值；bucket 不写 = 落库默认一致）；协议默认
    // openai / 自定义头空（v4 列 DEFAULT 同值——headers 不写即空）；形态默认 chat；
    // 提示缓存默认关 / TTL 5m（v12 列 DEFAULT 同值——bucket 不写）
    balanceEnabled: false,
    balanceLastText: '',
    protocol: protocol,
    headers: '',
    endpoint: endpoint,
    promptCacheEnabled: false,
    promptCacheTtl: '5m',
    bodyOverrides: '',
    // 取钥方式默认轮换（v32 列 DEFAULT 同值——bucket 不写 = 落库默认一致；改值走
    // setProviderKeyPickMode 单列通道）
    keyPickMode: KEY_PICK_ROTATE
  };
  const bucket: relationalStore.ValuesBucket = {
    'id': row.id, 'name': row.name, 'baseUrl': row.baseUrl, 'model': '', 'remark': '',
    'createdAt': row.createdAt, 'enabled': enabled ? 1 : 0, 'sortOrder': row.sortOrder,
    'protocol': row.protocol, 'endpoint': row.endpoint,
    'headers': headersJson, 'body_overrides': bodyJson
  };
  await sharedRdbStore().insert('providers', bucket);
  return row;
}

// 更新服务商基础字段（name/baseUrl/protocol/endpoint/headers/bodyOverrides；启用开关走
// setProviderEnabled 单独通道；headersJson/bodyJson 已由调用方序列化并丢弃空行——
// AiTypes.serializeHeaderPairs；body 侧调用方先校验各 v 合法 JSON 再序列化）
export async function updateProvider(id: string, name: string, baseUrl: string,
  protocol: string = PROTOCOL_OPENAI, headersJson: string = '',
  endpoint: string = ENDPOINT_CHAT, bodyJson: string = ''): Promise<void> {
  const bucket: relationalStore.ValuesBucket = {
    'name': name, 'baseUrl': baseUrl, 'protocol': protocol, 'headers': headersJson,
    'endpoint': endpoint, 'body_overrides': bodyJson
  };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('providers');
  predicates.equalTo('id', id);
  await sharedRdbStore().update(bucket, predicates);
}

// 启用/停用（停用的服务商不参与当前连接解析与选择面板）
export async function setProviderEnabled(id: string, enabled: boolean): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'enabled': enabled ? 1 : 0 };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('providers');
  predicates.equalTo('id', id);
  await sharedRdbStore().update(bucket, predicates);
}

// 持久化列表序（拖拽落定后整表回写 sortOrder = 数组下标；条目数 = 用户手建小数据集）
export async function saveProviderOrder(ids: string[]): Promise<void> {
  for (let i = 0; i < ids.length; i++) {
    const bucket: relationalStore.ValuesBucket = { 'sortOrder': i };
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('providers');
    predicates.equalTo('id', ids[i]);
    await sharedRdbStore().update(bucket, predicates);
  }
}

// 更新服务商提示缓存两列（2026-09-01 DB v12；服务商编辑页保存链调用——随保存键落库，
// 不走即时落库；0 行 throw = P0-1 假成功防御，updateTemplate/updateAssistantName 同款）
export async function updateProviderPromptCache(providerId: string, enabled: boolean,
  ttl: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = {
    'prompt_cache_enabled': enabled ? 1 : 0,
    'prompt_cache_ttl': ttl === '1h' ? '1h' : '5m' // 脏值钳位官方两档
  };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('providers');
  predicates.equalTo('id', providerId);
  const affected: number = await sharedRdbStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标服务商行不存在（已被删除），保存未生效');
  }
}

// 更新取钥方式单列（2026-09-17 DB v32；服务商编辑页保存链尾调用——随保存键落库，与提示
// 缓存同口径）。脏值钳位 rotate（写侧第二道闸，读侧 queryProviders 已钳；两处同源常量）。
// 0 行 throw = P0-1 假成功防御（updateProviderPromptCache 同款）。★ 本列只被发送链取钥
// 起始位消费（ProviderKeyDb.nextPickStart），协议层零引用
export async function setProviderKeyPickMode(providerId: string, mode: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = {
    'key_pick_mode': mode === KEY_PICK_RANDOM ? KEY_PICK_RANDOM : KEY_PICK_ROTATE
  };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('providers');
  predicates.equalTo('id', providerId);
  const affected: number = await sharedRdbStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标服务商行不存在（已被删除），保存未生效');
  }
}

// 删除服务商（事务级联：先删 provider_models 行、provider_keys 行、price_templates 行
// 再删 providers 行，防孤儿模型/key/价格模板元数据行；2026-09-01 助手模型绑定 v10 起
// 同事务清 assistants 绑定列（clearAssistantBindingByProvider——绑定该服务商的助手归回
// 未绑定态，强度档位一并复位）；2026-09-11 价格模板 v28 起 price_templates 随删（模板按
// 服务商隔离，归属没了模板不留）；Asset 池条目清理与当前键失效在调用方编排——Asset 与
// AppStorage 非库内资源不入事务）。返回删除行数。
export async function deleteProvider(id: string): Promise<number> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const modelPredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('provider_models');
  modelPredicates.equalTo('providerId', id);
  const keyPredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('provider_keys');
  keyPredicates.equalTo('providerId', id);
  const templatePredicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('price_templates');
  templatePredicates.equalTo('providerId', id);
  const providerPredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('providers');
  providerPredicates.equalTo('id', id);
  db.beginTransaction();
  try {
    await db.delete(modelPredicates);
    await db.delete(keyPredicates);
    await db.delete(templatePredicates);
    await clearAssistantBindingByProvider(id);
    const deleted: number = await db.delete(providerPredicates);
    db.commit();
    // 会话级模型覆盖级联清（2026-09-10 会话级覆盖层笔）：事务外执行——上表已删，清列
    // 失败只会留下指向已删服务商的覆盖（解析①级严格验证会判不可用自动降级，非致命）；
    // 不进事务 = 不因该笔新增面把「删服务商」整体拖成失败。
    // ★ 2026-09-11 自检修（本步必须自吞异常）：它跑在 commit **之后**，抛错会落进下面的
    // catch——那里对**已提交**的事务再 rollBack（无活动事务，行为未定义且可能掩盖原始
    // 异常），并把整笔报成「删除失败」；实况是 providers 行已删，调用方
    // （ProviderPage.deletePending）的 Asset 池清理与列表刷新会被一并跳过，留下跨卸载
    // 保留的孤儿密钥明文与不刷新的列表。故此处吞错只留 hilog，语义仍是「非致命」。
    try {
      await clearConversationModelOverride(id, '');
    } catch (e) {
      hilog.error(DOMAIN, TAG, '会话级模型覆盖级联清失败（解析①级会判不可用降级，非致命）：%{public}s',
        (e as Error).message);
    }
    return deleted;
  } catch (e) {
    db.rollBack();
    throw e as Error;
  }
}

// 全服务商的模型计数（providerId → 行数；列表页徽章消费——一条 GROUP BY 免逐服务商
// 查询循环）。querySql 直查（RdbPredicates 无聚合能力），ResultSet 用完 close
export async function queryProviderModelCounts(): Promise<Map<string, number>> {
  const result: relationalStore.ResultSet = await sharedRdbStore().querySql(
    'SELECT providerId, COUNT(*) AS cnt FROM provider_models GROUP BY providerId');
  const counts: Map<string, number> = new Map();
  try {
    while (result.goToNextRow()) {
      counts.set(result.getString(result.getColumnIndex('providerId')),
        result.getLong(result.getColumnIndex('cnt')));
    }
  } finally {
    result.close();
  }
  return counts;
}

// ── provider_models CRUD ──

// 某服务商的模型清单（创建先后序）；kindFilter 传 '' = 不过滤。enabled = 模型级启停
//（v3 列；停用行照常返回，消费方自行过滤——选择面板与连接解析过滤 enabled，详情页
// 模型页签全量展示带开关）
export async function queryModels(providerId: string, kindFilter: string): Promise<ModelRow[]> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('provider_models');
  predicates.equalTo('providerId', providerId);
  if (kindFilter !== '') {
    predicates.equalTo('kind', kindFilter);
  }
  predicates.orderByAsc('createdAt');
  const columns: string[] = ['id', 'providerId', 'modelId', 'name', 'kind', 'caps', 'createdAt', 'enabled',
    'caps_user_modified', 'favorite', 'price_config', 'context_window'];
  const result: relationalStore.ResultSet = await sharedRdbStore().query(predicates, columns);
  const rows: ModelRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        id: result.getString(result.getColumnIndex('id')),
        providerId: result.getString(result.getColumnIndex('providerId')),
        modelId: result.getString(result.getColumnIndex('modelId')),
        name: result.getString(result.getColumnIndex('name')),
        kind: result.getString(result.getColumnIndex('kind')),
        caps: result.getString(result.getColumnIndex('caps')),
        createdAt: result.getLong(result.getColumnIndex('createdAt')),
        enabled: result.getLong(result.getColumnIndex('enabled')) === 1,
        capsUserModified: result.getLong(result.getColumnIndex('caps_user_modified')) === 1,
        favorite: result.getLong(result.getColumnIndex('favorite')) === 1,
        priceConfig: result.getString(result.getColumnIndex('price_config')),
        // v33 上下文窗口（2026-09-17）：0 = 未配置（跟随参考值）/ 非 0 = 用户覆盖
        contextWindow: result.getLong(result.getColumnIndex('context_window'))
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// 全量模型行（2026-09-10 费用估计：价格 map 数据源——费用页对时段内事件按
// providerId+'/'+modelId 关联价格，需跨服务商全量行一次拉齐；行数 = 用户手建模型清单
// 自然有界）。★ 独立实现不借用 queryModels——后者按 providerId equalTo 过滤，本函数
// 要的就是跨服务商全量。排序 createdAt 升序 = queryModels 同序（modelId 单键兜底
// 「首个命中」的确定序）；kind 不过滤（费用事件天然只出自对话模型，行过滤反而可能砍掉
// 事件命中的目标行）
export async function queryAllModels(): Promise<ModelRow[]> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('provider_models');
  predicates.orderByAsc('createdAt');
  const columns: string[] = ['id', 'providerId', 'modelId', 'name', 'kind', 'caps', 'createdAt', 'enabled',
    'caps_user_modified', 'favorite', 'price_config', 'context_window'];
  const result: relationalStore.ResultSet = await sharedRdbStore().query(predicates, columns);
  const rows: ModelRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        id: result.getString(result.getColumnIndex('id')),
        providerId: result.getString(result.getColumnIndex('providerId')),
        modelId: result.getString(result.getColumnIndex('modelId')),
        name: result.getString(result.getColumnIndex('name')),
        kind: result.getString(result.getColumnIndex('kind')),
        caps: result.getString(result.getColumnIndex('caps')),
        createdAt: result.getLong(result.getColumnIndex('createdAt')),
        enabled: result.getLong(result.getColumnIndex('enabled')) === 1,
        capsUserModified: result.getLong(result.getColumnIndex('caps_user_modified')) === 1,
        favorite: result.getLong(result.getColumnIndex('favorite')) === 1,
        priceConfig: result.getString(result.getColumnIndex('price_config')),
        // v33 上下文窗口（2026-09-17）：0 = 未配置（跟随参考值）/ 非 0 = 用户覆盖
        contextWindow: result.getLong(result.getColumnIndex('context_window'))
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// 新建模型行（modelId 同服务商内查重在调用方校验；新建恒启用——启停是存量行的开关）。
// ★ caps_user_modified 不扩签（2026-09-03 Cube 吸收 A1）：内部按「caps 非空 ⇒ 1（用户
// 手设固化），空 ⇒ 0（读时按模型名派生）」落值——获取模型（ModelFetchSheet 恒空串）/
// 手动添加（编辑页勾选保存即手设）/ 导入（ProviderShare 原样 caps 含空）/ 遗留迁移
//（恒空串）各调用方语义自动正确
// ★ 2026-09-17 v33 上下文窗口：尾参 contextWindow（0 = 未配置 = 跟随内置参考值）。
// **可选参**——上列四调用点不传即 0（未配置），编辑页新建链显式传值；与 priceConfig 同姿态
export async function insertModel(providerId: string, modelId: string, name: string,
  kind: string, caps: string, priceConfig: string = '',
  contextWindow: number = 0): Promise<ModelRow> {
  const userModified: boolean = caps !== '';
  const row: ModelRow = {
    id: nextMessageId('model'),
    providerId: providerId,
    modelId: modelId,
    name: name,
    kind: kind,
    caps: caps,
    createdAt: Date.now(),
    enabled: true,
    capsUserModified: userModified,
    // v21 收藏标记：新行恒未收藏（bucket 不写 = 落库 DEFAULT 0 同值）
    favorite: false,
    // v27 价格配置：缺省 '' = 未配置（bucket 不写 = 落库 DEFAULT 同值——获取模型/导入/
    // 遗留迁移三调用点零改动；编辑模型页新建链显式传值）
    priceConfig: priceConfig,
    // v33 上下文窗口：缺省 0 = 未配置（bucket 不写 = 落库 DEFAULT 同值，同上）
    contextWindow: contextWindow
  };
  const bucket: relationalStore.ValuesBucket = {
    'id': row.id, 'providerId': row.providerId, 'modelId': row.modelId, 'name': row.name,
    'kind': row.kind, 'caps': row.caps, 'createdAt': row.createdAt, 'enabled': 1,
    'caps_user_modified': userModified ? 1 : 0
  };
  if (priceConfig !== '') {
    bucket['price_config'] = priceConfig;
  }
  if (contextWindow > 0) {
    bucket['context_window'] = contextWindow;
  }
  await sharedRdbStore().insert('provider_models', bucket);
  return row;
}

// 更新模型行（modelId 不可改——行身份；name/kind/caps 可编辑；capsUserModified = 能力
// 派生/覆盖标志（2026-09-03 Cube 吸收 A1）——true = 用户手改固化（含「全不勾」的显式
// 清空，此后不再派生）；★ 2026-09-17 重置语义修正后**false 也是合法落值**：能力卡「重置」
// = 恢复自动识别，父侧写 userModified=false 并落回派生勾选态，本列随之为 0（回到跟随态，
// 与「从未手改」的行完全同态）。priceConfig = v27 价格 JSON 串（'' = 清除配置回到未配置；
// 合法性与结构由编辑页保存链 + CostStatsCalc.parsePriceConfig 双侧把守——本层透传不解析）。
// contextWindow = v33 上下文窗口（0 = 未配置 = 跟随参考值 / 非 0 = 用户覆盖值）。
// ★ 调用方仅 ModelEditPage 保存链**一处**——故尾参不给缺省值：漏传即编译错，
// 防将来新增调用点静默把用户值清成 0（与 capsUserModified/priceConfig 同姿态）
export async function updateModel(rowId: string, name: string, kind: string, caps: string,
  capsUserModified: boolean, priceConfig: string, contextWindow: number): Promise<void> {
  const bucket: relationalStore.ValuesBucket = {
    'name': name, 'kind': kind, 'caps': caps, 'caps_user_modified': capsUserModified ? 1 : 0,
    'price_config': priceConfig, 'context_window': contextWindow
  };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('provider_models');
  predicates.equalTo('id', rowId);
  await sharedRdbStore().update(bucket, predicates);
}

// 模型启停（2026-08-30 详情页改版：模型卡开关；停用 = 不进选择面板与连接解析）
export async function setModelEnabled(rowId: string, enabled: boolean): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'enabled': enabled ? 1 : 0 };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('provider_models');
  predicates.equalTo('id', rowId);
  await sharedRdbStore().update(bucket, predicates);
}

// 模型收藏（2026-09-08 v21 模型选择半模态优化：选择面板行内爱心键；单列 UPDATE，
// 不动 createdAt/updatedAt——收藏不改变列表序，与 setConversationFavorite 同口径。
// 随模型行同生命周期：删行即标记消失，无级联面）
export async function setModelFavorite(rowId: string, favorite: boolean): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'favorite': favorite ? 1 : 0 };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('provider_models');
  predicates.equalTo('id', rowId);
  await sharedRdbStore().update(bucket, predicates);
}

// 批量启停全部已添加模型（2026-08-31 模型页签「更多」菜单其一：作用域 = 本服务商
// provider_models 全行——表内行即「已添加」（获取模型入库 + 手动添加）；未添加模型
//（API 清单未入库）不在表内，天然不受影响；返回受影响行数，调用方 toast N 反馈）
export async function setModelsEnabled(providerId: string, enabled: boolean): Promise<number> {
  const bucket: relationalStore.ValuesBucket = { 'enabled': enabled ? 1 : 0 };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('provider_models');
  predicates.equalTo('providerId', providerId);
  return await sharedRdbStore().update(bucket, predicates);
}

// 删除模型行（2026-09-01 助手模型绑定 v10 起先查行取 providerId/modelId——删后级联清
// 绑定该模型的助手行〔clearAssistantBindingByModel，三列归空〕+ 会话级模型覆盖
//〔clearConversationModelOverride，2026-09-10 会话级覆盖层笔〕；行已不存在 = 直接返回，
// 无级联目标。与 deleteProvider 同形制：三步包事务，任一步失败整体回滚——防悬空绑定/
// 悬空覆盖）
export async function deleteModel(rowId: string): Promise<void> {
  // 前置查询留在事务外（ResultSet 必须在事务前用完并 close——长事务不持结果集）
  const rowPredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('provider_models');
  rowPredicates.equalTo('id', rowId);
  const result: relationalStore.ResultSet =
    await sharedRdbStore().query(rowPredicates, ['providerId', 'modelId']);
  let boundProviderId: string = '';
  let boundModelId: string = '';
  try {
    if (result.rowCount > 0 && result.goToNextRow()) {
      boundProviderId = result.getString(result.getColumnIndex('providerId'));
      boundModelId = result.getString(result.getColumnIndex('modelId'));
    }
  } finally {
    result.close();
  }
  const db: relationalStore.RdbStore = sharedRdbStore();
  db.beginTransaction();
  try {
    await db.delete(rowPredicates);
    if (boundProviderId !== '' && boundModelId !== '') {
      await clearAssistantBindingByModel(boundProviderId, boundModelId);
      // 会话级模型覆盖级联清（2026-09-10 会话级覆盖层笔：原 clearActiveSelection 清全局键
      // 的位置——覆盖指向的行没了，留着只会在解析①级空转（严格对验证会判不可用降级），
      // 清掉让会话干净地落回默认源）。清列不删会话不删历史
      await clearConversationModelOverride(boundProviderId, boundModelId);
    }
    db.commit();
  } catch (e) {
    db.rollBack();
    throw e as Error;
  }
}

// ── 当前连接（聊天页）──

// 解析结果（连接三件 + 服务商名——providerName 现无 UI 消费（2026-08-31 状态胶囊取消），
// 字段保留：调试/后续功能可用，解析链零改动）。
// ★ 2026-09-15 附件 PDF 页渲染一期：+ caps 生效能力串（发送前置视觉门控的唯一输入源）。
// 带出理由 = buildCandidateConnection 手里正拿 model 行（填充点现成）、零额外查询、
// 切模型随 reloadConn 自动更新；消费侧禁在发送时另起 DB 查询、禁直读 row.caps（A1 明令）
export interface ActiveConnectionInfo {
  conn: AiConnection;
  providerName: string;
  caps: string;
}

// 解析聊天页当前连接（2026-09-05 四级兜底链，决明指令「会话页所选 > 会话所属的助手绑定
// > 全局默认 > 首个启用模型」——调研待办 2 发送链助手级覆盖落地；★ 中途不停：每级候选
// 按同一标准验证（服务商启用 + 模型可用 + key 池非空），任一环不满足即静默降下一级，
// 全链落空才返回 null，不中途报错停链）：
// ①会话页所选 = **本会话覆盖**（conversations.modelProviderId/modelId 两列，无行会话由
//   调用方传内存覆盖——DB v24，2026-09-10 会话级覆盖层笔）。覆盖是用户在**该会话内**的
//   显式选择，**严格对（providerId, modelId）验证、不自愈换模**（原①级键指失效换同服务商
//   首个启用模型的擦屁股语义随 active 键一并退役——用户没选过就不该算①级命中）；
// ②助手绑定 = ownerAssistantId 指向 assistants 行的 providerId/modelId 两列（调用方解析
//   好的会话归属助手 id，归属口径与注入链 ChatPromptState 一致；严格按绑定对验证——绑定
//   模型停用不自愈换模，绑定意图精确到模型）；
// ③全局默认 = default 两键（功能模型页「默认模型」）；
// ④首个启用模型 = 按服务商排序序跨服务商找第一个「启用 + 有启用对话模型 + key 池非空」组合。
// key 池只验非空不读明文（v4 多 Key 池；明文最小化：「行在明文无」＝解析通过、发送期
// 逐支取钥失败跳过 + 全部失败 notice 呈报）。
// 缓存/回写口径（2026-09-05 决明拍板方案 A「兜底借用不留底」，2026-09-10 起语义不变）：
// **全部四级一律不回写任何全局状态**——2026-09-10 会话级覆盖层笔后连①级也不再回写
//（覆盖由用户在会话内的显式操作落列，解析只读）。这样"兜底借用"与"显式选择"彻底分离：
// 改助手绑定/改全局默认后，未被显式覆盖过的会话下次发送即时生效。
// ★ 会话级覆盖的读取与落库不在本文件（避免 ProviderDb 反向依赖会话查询）：由调用方
//（ChatPageLoad.reloadConn / 发送链）读 conversations 覆盖列或内存覆盖后作入参传入。
export async function resolveActiveConnection(ownerAssistantId: string = '',
  overrideProviderId: string = '', overrideModelId: string = ''):
  Promise<ActiveConnectionInfo | null> {
  const providers: ProviderRow[] = await queryProviders();
  // ①本会话覆盖（严格对验证：不自愈换模——覆盖是用户在该会话内的显式选择）
  let info: ActiveConnectionInfo | null = await tryCandidate(providers,
    overrideProviderId, overrideModelId);
  // ②会话所属助手绑定（v10 三列；助手行已删/未绑定 = 本级不可用，降级不停链）
  if (info === null && ownerAssistantId !== '') {
    const owner: AssistantRow | null = await queryAssistant(ownerAssistantId);
    if (owner !== null) {
      info = await tryCandidate(providers, owner.providerId, owner.modelId);
    }
  }
  // ③全局默认（default 两键；未设置 = '' 直接判不可用）
  if (info === null) {
    info = await tryCandidate(providers,
      AppStorage.get<string>(DEFAULT_PROVIDER_KEY) ?? '',
      AppStorage.get<string>(DEFAULT_MODEL_KEY) ?? '');
  }
  // ④首个启用模型（跨启用服务商——旧逻辑只看首个启用服务商，其无可用模型/key 即 null
  // = 中途停链；现按「中途不停」续找下一家）
  if (info === null) {
    const enabled: ProviderRow[] = providers.filter((row: ProviderRow): boolean => row.enabled);
    for (const provider of enabled) {
      const models: ModelRow[] = (await queryModels(provider.id, 'chat'))
        .filter((row: ModelRow): boolean => row.enabled); // 停用模型不参与解析
      if (models.length === 0) {
        continue;
      }
      info = await buildCandidateConnection(provider, models[0]);
      if (info !== null) {
        break;
      }
    }
  }
  if (info === null) {
    return null;
  }
  // ②③④级命中不回写（方案 A「兜底借用不留底」——口径见头注释）
  return info;
}

// 单级候选尝试（①②③级共用）：providerId 空 = 本级未配置；服务商须存在且启用；模型须在
// 该服务商启用对话模型清单内——严格按（providerId, modelId）对验证，覆盖/绑定/默认意图
// 精确到模型，不自愈换模。★ 原第①级「键指失效取同服务商首个启用模型」自愈语义已随
// 2026-09-10 会话级覆盖层笔退役，自愈形参 fallbackFirstModel 连同两死分支于 2026-09-17
// 自检第4轮笔1 整体拆除（五百七十一节观察五件销账）——形参在场即留「传 true 复活退役
// 行为」的口子，严格性改由签名结构保证；第④级首个启用不经本函数（直取 models[0] 走
// buildCandidateConnection）。返回 null = 本级不可用（不抛错——降级是正常路径，中途不停）
async function tryCandidate(providers: ProviderRow[], providerId: string,
  modelId: string): Promise<ActiveConnectionInfo | null> {
  if (providerId === '' || modelId === '') {
    return null;
  }
  const provider: ProviderRow | undefined =
    providers.find((row: ProviderRow): boolean => row.id === providerId && row.enabled);
  if (provider === undefined) {
    return null;
  }
  const chatModels: ModelRow[] = (await queryModels(provider.id, 'chat'))
    .filter((row: ModelRow): boolean => row.enabled); // 停用模型不参与解析
  const model: ModelRow | undefined =
    chatModels.find((row: ModelRow): boolean => row.modelId === modelId);
  if (model === undefined) {
    return null;
  }
  return buildCandidateConnection(provider, model);
}

// 候选连接组装（tryCandidate 与第④级共用；key 池只验非空不读明文——明文最小化口径）。
// null = key 池无启用条目（含明文缺失态——发送期逐支取钥失败兜底）
async function buildCandidateConnection(provider: ProviderRow,
  model: ModelRow): Promise<ActiveConnectionInfo | null> {
  const keyIds: string[] = await queryEnabledKeyIds(provider.id);
  if (keyIds.length === 0) {
    return null;
  }
  const info: ActiveConnectionInfo = {
    conn: {
      baseUrl: provider.baseUrl,
      model: model.modelId,
      protocol: provider.protocol,
      // 接口形态透传（v5 列；异常值/空兜底 chat——工厂同款保守语义）
      endpoint: provider.endpoint === ENDPOINT_RESPONSES ? ENDPOINT_RESPONSES : ENDPOINT_CHAT,
      headers: parseHeaderPairs(provider.headers),
      // 自定义 Body 覆盖透传（v13；'' 解析回 [] = 无覆盖 = 请求体零回归）
      bodyOverrides: parseHeaderPairs(provider.bodyOverrides),
      providerId: provider.id,
      // 提示缓存两列透传（v12；false = 关 = compose 不带 cache 参零回归；仅 anthropic 消费）
      promptCacheEnabled: provider.promptCacheEnabled,
      promptCacheTtl: provider.promptCacheTtl,
      // 取钥方式透传（v32 列；发送轮次起始位分派读它——ProviderKeyDb.nextPickStart）。
      // ★ 只到「选哪支密钥」为止：协议层（compose/stream 四协议）零消费，请求字节不变
      keyPickMode: provider.keyPickMode,
      // 思考策略（2026-09-03 Cube 吸收 A2 唯一填充点）：协议+接口形态+baseUrl+模型 id
      // 二维画像解析（ModelRegistry，2026-09-06 模型级精化）——off 生效判定与将来策略化
      // compose 的单一来源；无解析失败路径（未知协议兜底 'none'）。
      // 同填充点模型级两字段：off 支持（supportsThinkingOff 恒查 openai chat 画像——
      // 「与协议形态无关」语义在判定侧归一）+ 菜单选项集（thinkingOptionsFor 按本连接
      // 形态派生——画像行收窄或全量缺省）
      reasoningStrategy: resolveReasoningStrategy(provider.protocol, provider.endpoint,
        provider.baseUrl, model.modelId),
      reasoningOffSupported: supportsThinkingOff(provider.baseUrl, model.modelId),
      reasoningMenuOptions: thinkingOptionsFor(provider.protocol, provider.endpoint,
        provider.baseUrl, model.modelId)
    },
    providerName: provider.name,
    // 生效能力串（2026-09-15 页渲染一期）：用户改过则原样 / 否则按模型名派生（单源
    // effectiveCaps——发送侧视觉门控读它，禁直读 row.caps）
    caps: effectiveCaps(model)
  };
  return info;
}

// ── 遗留单连接迁移（启动一次性，EntryAbility 在 initChatDb 后调用）──

// providers 空表时把 v1 单连接资产导入为首个服务商（名「默认服务商」+ 首个对话模型 +
// key 池首条 k1——2026-08-30 池化：直接写池，不再经单 key 形态），并设为当前选择；
// 已有服务商/无遗留资产 = 直接返回。失败打日志不阻断启动（解析侧对空态自有兜底，
// 迁移下次启动重试——幂等：只在空表时动作）
export async function ensureProvidersMigrated(): Promise<void> {
  try {
    const existing: ProviderRow[] = await queryProviders();
    if (existing.length > 0) {
      return;
    }
    const legacy: LegacyConnection | null = await loadConnection();
    if (legacy === null) {
      return;
    }
    const provider: ProviderRow = await insertProvider('默认服务商', legacy.baseUrl);
    await insertModel(provider.id, legacy.model, '', 'chat', '');
    await seedPoolKey(provider.id, legacy.apiKey);
    // ★ 2026-09-10 会话级覆盖层笔：原此处 setActiveConnection（写「当前选择」两键）随键退役
    // ——不再写任何「当前」状态：本函数只在 providers 空表时动作（新装/迁移首启），此时该
    // 服务商是唯一启用且有钥的候选 = 解析链④级必然命中它，行为等价（零回归）
    hilog.info(DOMAIN, TAG, '遗留连接已迁移为首服务商 %{public}s', provider.id);
  } catch (e) {
    hilog.error(DOMAIN, TAG, '遗留连接迁移失败（下次启动重试）：%{public}s', (e as Error).message);
  }
}
