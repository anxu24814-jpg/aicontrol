// 服务商域存储层：providers / provider_models 两表 CRUD + 聊天页当前连接解析 + 遗留单连接
// 迁移。表结构/迁移在 ChatDbMigrate.ets（DB 单一初始化源），本文件只做数据操作——复用同一
// RdbStore 句柄（ChatDb.sharedRdbStore），红线同源：ResultSet 用完 close / 查询有界（用户
// 手建小数据集自然有界）/ 事务三件套删服务商（级联清模型行与 key 池行防孤儿——Asset 池
// 条目清理在调用方，非库内资源不入事务）。
// ★ 当前连接模型（聊天页消费）：defaultProviderId/defaultModelId 全局默认两键
//（persistProp）+ 会话级模型覆盖两列（conversations.modelProviderId/modelId，DB v24）。
// 解析 = 四级兜底链（决明指令「会话页所选 > 会话所属的助手绑定 > 全局默认 > 首个启用模型，
// 中途不停」，resolveActiveConnection 头注释）；key 池须有启用条目（只验池非空、只查行不
// 读明文——「行在明文无」＝解析通过、发送期逐支取钥失败跳过、全部失败 notice 呈报）；全链
// 落空返回 null（聊天页提示去「服务商管理」配置）。
// ★ 会话级覆盖层笔：**①级「会话页所选」由原 activeProviderId/activeModelId 两个全局键改为
// 会话级覆盖列**——原键与会话无关，任何一次会话内手选都被写成"全局最近选择"，此后所有新
// 会话恒命中①级、助手绑定（②级）永远轮不到（决明报障形态）。两键**整体退役**（缓存失效
// 语义不变，②③④借用不留底）。
// 2026-08-30 三协议：ProviderRow 增 protocol（协议常量 AiTypes）/ headers（自定义头 JSON 串）。
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AiConnection, effectiveCapsOf, ENDPOINT_CHAT, ENDPOINT_RESPONSES, lookupContextBaseline,
  parseHeaderPairs, PROTOCOL_OPENAI, resolveReasoningStrategy, supportsThinkingOff,
  thinkingOptionsFor } from '../providers/AiTypes';
import { clearConversationModelOverride, nextMessageId, ProviderModelRow,
  sharedRdbStore } from './ChatDb';
import { runWriteQueued } from './DbWriteQueue';
import { LegacyConnection, loadConnection, removePoolKeys } from './KeyStore';
import { KEY_PICK_RANDOM, KEY_PICK_ROTATE, queryEnabledKeyIds, queryProviderKeys,
  ProviderKeyRow, seedPoolKey } from './ProviderKeyDb';
import { clearAssistantBindingByModel, clearAssistantBindingByProvider,
  AssistantRow, queryAssistant } from './AssistantDb';
// ★ 停用即解绑笔：本件删除/停用函数反向调槽位维护件，而彼件要读本件键常量 ⇒ 两件成环。
// 彼件所有外部绑定只在函数体内读（坑50 口径），本件顶层不读彼件任何绑定。
import {
  clearSlotsForModel, clearSlotsForProvider
} from './FunctionalSlotBinding';

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
  // 余额两字段（v3 列）：balanceEnabled = 总开关；balanceLastText = 上次查询结果文本
  //（详情页余额查询成功落库，重启保留——列表卡徽章与详情页同源消费）
  balanceEnabled: boolean;
  balanceLastText: string;
  // 协议与自定义头（v4 列）：protocol = PROTOCOL_VALUES 之一（默认 openai）；headers =
  // JSON 串 [{k,v}]（空串 = 无；解析/序列化在 AiTypes，UI kv 行编辑）
  protocol: string;
  headers: string;
  // OpenAI 接口形态（v5 列）：'chat' 默认 = /chat/completions；'responses' =
  // /v1/responses——仅对 openai 有意义，a/g 恒 'chat'
  endpoint: string;
  // Anthropic 提示缓存（v12 列）：开关（默认关——写入 1.25× 计费）+ TTL '5m'|'1h'（官方
  // 两档）。仅 anthropic 协议消费（请求体断点落点见 RequestCompose 头注释）
  promptCacheEnabled: boolean;
  promptCacheTtl: string;
  // 自定义 Body 覆盖（v13 列）：JSON 串 [{k,v}]——k = 请求体顶层键名，v = 合法 JSON 值
  // 文本；'' = 无。解析/序列化复用 HeaderPair 工具（结构同构），发送时 ChatStreamBase.start
  // 统一 merge 到请求体根对象（四协议单点）
  bodyOverrides: string;
  // 取钥方式（v32 列）：KEY_PICK_ROTATE（默认，按池内卡片顺序轮换）| KEY_PICK_RANDOM
  //（每次发送随机挑起始支）——常量表在 ProviderKeyDb.ets，读侧已钳位；只影响取钥起始位，
  // 协议链路零消费
  keyPickMode: string;
  // 内置服务商标记（v52 列）：true = 预置出厂行 = 不可删只能停用（deleteProvider 数据层
  // 硬拦截 + 菜单隐藏 + AI 工具拒绝三层防线，数据层是硬防线）；false = 用户自建 / 导入 /
  // 改名改址过的预置行。回填与 seed 写点见 ChatDbMigrate v52 分支与 ProviderPresetSeed
  builtin: boolean;
}

// provider_models 行（表定义与列语义见 ChatDb.ets SQL_CREATE_PROVIDER_MODELS 注释）
export type ModelRow = ProviderModelRow;

// ★ 原 `ACTIVE_PROVIDER_KEY` / `ACTIVE_MODEL_KEY` 两全局键已整体退役（①级改会话级覆盖列，
// 见头注释）——**不要再引入任何"全局当前模型"键**：它是本笔修掉那个 bug 的根因形态。

// 全局默认模型两键（2026-09-05 功能模型页首项「默认模型」，持久化注册在 EntryAbility）：
// 发送链四级兜底的第 3 级来源——会话页所选与助手绑定均不可用时才消费（链细则见
// resolveActiveConnection 头注释）；'' = 未设置。功能模型页选择写入，重启保留
export const DEFAULT_PROVIDER_KEY: string = 'defaultProviderId';
export const DEFAULT_MODEL_KEY: string = 'defaultModelId';

// 标题生成两键（功能模型页第二卡，持久化注册在 EntryAbility；'' = 未设置）：AI 会话标题
// 生成的**显式开关**——★ 决明拍板：两键未配置 = 功能未启用，静默不生成（无会话连接兜底，
// 不配就不发任何请求）。解析 = TitleGen 单级验证（服务商启用 + 模型启用 + key 池非空）
//——**禁走 resolveActiveConnection 四级链**（四级链容忍降级，而「未配置 = 未启用」必须硬区分）
export const TITLE_PROVIDER_KEY: string = 'titleProviderId';
export const TITLE_MODEL_KEY: string = 'titleModelId';

// 标题生成总开关：boolean，**缺省 true 开**——给既有功能加闸，缺省 false 会让存量用户
// 升级即功能消失。false = 功能整体停用（生成链守卫序最前早退，零请求零消耗；两键配置保留
// 不清理，重开即恢复）；消费方 = TitleGen 守卫序 + 功能模型页「标题生成」卡 Toggle
//（persistProp 注册在 EntryAbility，备份白名单登记在 AppPreferences）
export const TITLE_ENABLED_KEY: string = 'titleEnabled';

// 推荐问题三键（功能模型页第六卡，持久化注册在 EntryAbility，备份白名单在
// AppPreferences.BACKUP_PREF_KEYS）：AI 回复后的追问推荐生成配置。
// · SUGGEST_ENABLED_KEY 总开关——boolean，**默认 false 关**（BYOK 成本敏感 + ChatGPT
//   无开关扰人教训，每轮多一次请求由用户显式授权）；
// · SUGGEST_PROVIDER_KEY/SUGGEST_MODEL_KEY 已选模型两键——两键齐 = 已配置，**未配置 =
//   零请求无兜底**（照标题生成拍板：不回退标题模型、禁走四级链——功能模型是显式开关，
//   不配就不发任何请求）。
// 解析 = TitleGen.resolveTitleEndpoint 单级验证（复用同一标准）；编排域 = common/SuggestGen.ets
export const SUGGEST_ENABLED_KEY: string = 'suggestEnabled';
export const SUGGEST_PROVIDER_KEY: string = 'suggestProviderId';
export const SUGGEST_MODEL_KEY: string = 'suggestModelId';

// OCR 键（附件 OCR 二期起多轮演进：决明拍板「系统识别开关化」把引擎偏好由隐式口径改为
// 显式开关；「内置识别引擎」落地后引擎选中面由 Toggle 改为**卡内三分段胶囊**，第五键
// OCR_ENGINE_KEY 成为唯一写侧，偏好键退役为只读兜底）：
// · OCR_ENABLED_KEY 总开关——'true' | 'false'，**缺省/未写 = 开**（读侧 OcrEngine.ocrEnabled
//   按 ?? 'true' 兜底）；关 = 零识别零耗时回一期行为；
// · OCR_ENGINE_KEY 引擎三态——'system' | 'builtin' | 'model'；''/非法值（脏写）同落未写
//   推导（见 resolveOcrEngine）。**写侧只写本键**（三段胶囊落键；选模型完成时写 'model'
//   ——维持「选模型即用它」观感）；
// · OCR_PREFER_SYSTEM_KEY **退役为只读兜底**——UI 不再写，仅 resolveOcrEngine 推导时读
//  （老用户升级零行为变化）；
// · OCR_PROVIDER_KEY/OCR_MODEL_KEY 已选模型两键——双键都非空 = 已选视觉引擎
//  （providers/OcrVisionApi，编排见 OcrEngine 头注释）；引擎非 model 时两键保留作回退目标。
// 写点 = 功能模型页「文字识别」卡；persistProp 注册在 EntryAbility、备份白名单登记在
// AppPreferences.BACKUP_PREF_KEYS（11 键）
export const OCR_ENGINE_KEY: string = 'ocrEngine';
export const OCR_PREFER_SYSTEM_KEY: string = 'ocrPreferSystem';
export const OCR_PROVIDER_KEY: string = 'ocrProviderId';
export const OCR_MODEL_KEY: string = 'ocrModelId';
export const OCR_ENABLED_KEY: string = 'ocrEnabled';
// 引擎三态合法值（写侧与解析共用，禁散写字面量）
export const OCR_ENGINE_SYSTEM: string = 'system';
export const OCR_ENGINE_BUILTIN: string = 'builtin';
export const OCR_ENGINE_MODEL: string = 'model';

// 审批模型两键（命令审批功能；persistProp 注册在 EntryAbility，备份白名单在
// AppPreferences.BACKUP_PREF_KEYS；'' = 未设置）：工具调用确认链的 LLM 审批闸配置——确认
// 链命中（预检非 null 且会话白名单未命中）时先由本模型审读「待执行调用 + 对话前文」给出
// 允许/拒绝，不确定与一切失败回退人工卡。
// · 两键齐 = 已配置 = 审批闸启用；未配置 = 功能未启用（确认链照旧弹人工卡）——照标题/
//   推荐「显式开关」口径，**不回退其他槽**；
// · 解析 = providers/ApprovalGate 走 resolveTitleEndpoint 单级验证——**禁走四级链**
//  （同标题槽理由：槽位未配置必须硬区分，四级链容忍降级）；
// · 请求通道 = TitleApi.requestTitleText 共享（taskLabel '审批'），不新开传输件；
// 写点 = 功能模型页「审批模型」卡（ApprovalModelCard 自持有读取）+ 功能模型工具
// set_functional_model 槽位同步可写
export const APPROVAL_PROVIDER_KEY: string = 'approvalProviderId';
export const APPROVAL_MODEL_KEY: string = 'approvalModelId';

// 审批总开关：boolean，**缺省 true 开**（既有功能加闸不改变存量行为，同 TITLE_ENABLED_KEY
// 口径）。false = 功能整体停用：审批闸早退回人工卡——与「两键不齐」同一 fail-closed 去向
//（档位键与模型配置保留，重开即恢复）；消费方 = ApprovalGate.judgeToolCall 早退 +
// 功能模型页「命令审批」卡 Toggle（persistProp 注册在 EntryAbility，备份白名单在 AppPreferences）
export const APPROVAL_ENABLED_KEY: string = 'approvalEnabled';

// 功能任务思考档位：string，值域与会话页思考菜单同 = '' / off / low / high / max
//（AiTypes.THINKING_OPTIONS）。'' = 默认不干预（请求不带任何思考字段，随服务商出厂默认）；
// off = 显式关闭思考（仅开关方言画像域模型生效）；low/high/max = 强制思考档。**作用面 =
// 全部功能模型小任务链**（标题 / 记忆提取 / 记忆导入 / 记忆优化 / 上下文压缩 / 推荐问题 /
// 主动消息 / 审批，共八条，全部走 TitleApi.requestTitleText 共享通道）——**聊天对话不受
// 影响**（会话档位体系在助手/会话两级，与本键互不相干）。归一在消费侧逐链做
//（TitleApi.resolveFunctionalThinking：协议能力闸 + 画像行合法性，不支持思考字段的模型一律
// 落 '' 不发）。写点 = 功能模型页「功能思考档位」卡（FunctionalThinkingCard 自持有读取）；
// persistProp 注册在 EntryAbility，备份白名单登记在 AppPreferences
export const FUNCTIONAL_THINKING_KEY: string = 'functionalThinking';

// OCR 引擎偏好缺省推导：偏好键未写（''）时按旧口径推导——引擎两键齐 = 用已选模型
//（false），任一空 = 系统识别（true）。**升级路径零行为变化**（真值表见
// assert-attach-domain 100 组直跑）。读侧共用：resolveOcrEngine 内部推导支（禁各写一遍三目链）
export function resolveOcrPreferSystem(raw: string, providerId: string, modelId: string): boolean {
  if (raw === 'true') {
    return true;
  }
  if (raw === 'false') {
    return false;
  }
  return providerId === '' || modelId === '';
}

// OCR 三态引擎解析（读侧单源 = OcrEngine 首选引擎 + 功能模型页分段胶囊镜像，禁各写一遍）。
// 真值表（断言 105 组直跑）：rawEngine 三合法值 → 直取；非法值 → 落未写推导；未写 + 偏好
// 'false' + 模型两键齐 → 'model'（老用户升级零行为变化）；未写 + 其余 → 'system'。
// 「偏好 'false' 但两键不齐」也落 'system'——旧 preferredEngine 同兜底（防空 modelId 进链，
// 以空名失败后再播「未成功」toast）
export function resolveOcrEngine(rawEngine: string, rawPreferSystem: string, providerId: string,
  modelId: string): string {
  if (rawEngine === OCR_ENGINE_SYSTEM || rawEngine === OCR_ENGINE_BUILTIN ||
    rawEngine === OCR_ENGINE_MODEL) {
    return rawEngine;
  }
  const preferSystem: boolean = resolveOcrPreferSystem(rawPreferSystem, providerId, modelId);
  return !preferSystem && providerId !== '' && modelId !== '' ? OCR_ENGINE_MODEL : OCR_ENGINE_SYSTEM;
}

// 连接解析输入变化广播键（决明拍板「广播键 + @Watch 重解析」）：发送链连接 = ChatPage.conn
// 缓存（refs.conn() 现读），reloadConn 触发集 = {进页 / 会话内手选模型 / 错误覆盖层「重试」}，
// 页签切换不销毁重建——助手绑定/全局默认修改后切回会话页直接发送仍走旧缓存。本键 tick
// 递增广播（@Watch 对同值不触发，递增保证每次触发；语义随 SESSION_LIST_RELOAD_KEY 先例）：
// 写点清册（名 + 触发语义）：
// · AssistantModelCard 改绑保存链（半模态选模型落库后）；
// · FunctionalModelPage 改全局默认（功能模型页「默认模型」卡手选）；
// · ChatSendCtrl 面板覆盖助手（无行会话有效归属因子）；
// · AssistantPage 切换当前助手 + 删除归默认当前助手（同因子，两处）；
// · setProviderEnabled / setModelEnabled 停用族（停用后恒广播——启用态本身是解析输入）；
// · ModelBindingReconcile 启动/导入对账会话面清空后；
// · ToolFunctional 功能槽工具 set_functional_model（broadcast 槽位，含全局默认）；
// · updateModel 能力编辑保存（caps 是 effectiveCaps 现算的原始列即解析输入，落库成功后
//   恒广播——盖 UI 编辑 / AI edit / AI reset_caps 三调用方）；
// · updateProvider 服务商参数编辑保存（baseUrl / 协议 / endpoint / headers /
//   bodyOverrides 是连接构建的原始列即解析输入，落库成功后恒广播——盖编辑页保存 /
//   AI provider update / AI headers 增删三调用方）。
//（会话页手选不写——onPickModel 已显式 reloadConn）；读点 = ChatPage @StorageProp @Watch →
// reloadConn。级联清绑定（删服务商/删模型）不写——有会话级模型覆盖级联清
//（clearConversationModelOverride，在 deleteModel/deleteProvider 内）+ 发送失败 notice
// 呈报 + 「重试」重解析恢复路径，观察项登记
export const CONN_RESOLVE_TICK_KEY: string = 'connResolveTick';

// 安全输入待填目标（内存键，不 persistProp——一次配置工作流语义，重启即清）。写点 =
// ToolProviderAdmin 的 create / add_key 成功后；读点 = ChatInputBar（chip 显隐）+
// SecureInputSheet（目标显示）；清点 = 面板保存成功后置 ''。值 = JSON 串
// {"providerId","keyId"}（读侧坏 JSON / 缺字段一律视为无目标，不抛错）。键非空在所有会话
// 显示——服务商是全局配置，无论在哪个会话看到都指向同一目标（拍板取舍，申报见任务书 §4.1）
export const PROVIDER_SECURE_INPUT_TARGET_KEY: string = 'providerSecureInputTarget';

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

// 自定义头 / 自定义体有无判定（get_provider_config 的 customHeaders / customBody 两布尔位
//——三敏感列名不出存储层，工具域文件据此零出现〔assert-app-domain 83 组负向钉〕；判空走
// parseHeaderPairs 与发送链同口径，坏 JSON = 无覆盖 = false，只回布尔不回内容）
export function hasCustomHeaders(row: ProviderRow): boolean {
  return parseHeaderPairs(row.headers).length > 0;
}

export function hasCustomBody(row: ProviderRow): boolean {
  return parseHeaderPairs(row.bodyOverrides).length > 0;
}

// 模型行生效能力：capsUserModified = true → 用户 caps 原样（固化含显式全不勾）；false →
// 按模型名读时派生（ModelRegistry，规则升级自动跟随，派生值不落库）。★ caps 的展示/勾选
// 回填一律走本函数，禁直读 row.caps——派生空 = 不误标，'web' 码无注册表来源仅用户手改可设
//（A1 明令）。派生语义单源在 ModelRegistry.effectiveCapsOf
export function effectiveCaps(row: ModelRow): string {
  return effectiveCapsOf(row.capsUserModified, row.caps, row.modelId);
}

// 模型行生效上下文窗口：用户覆盖优先（row.contextWindow > 0 原样返回），未配置（0）读
// 内置参考值（ModelRegistry.lookupContextBaseline 按模型名派生不落库——与 effectiveCaps
// 派生/覆盖同构）。返回 0 = 两者皆无（按「未配置」理解）。★ 消费面：连接侧取数单点 =
// contextWindowForConnection（其下经本函数）；历史裁剪、请求组装、费用估计仍不读它。
// **禁各处自行拼 row.contextWindow || lookupContextBaseline**——本函数是消费面单一入口
export function effectiveContextWindow(row: ModelRow): number {
  return row.contextWindow > 0 ? row.contextWindow : lookupContextBaseline(row.modelId);
}

// 连接的上下文窗口取数单点（窗口值表〔v33 列 + 参考值表〕的连接侧消费方）：按 conn 的
//（providerId, modelId）取模型行 → effectiveContextWindow；行不存在（解析链外构造的连接/
// 模型已删）返回 0 = 未知（降级 = 只显已用数不显占比）。取数时机 = 面板打开/切模型/切会话
// 等事件点（异步一次，不进渲染热路径——宪法性能红线）；失败吞错回 0
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
    'prompt_cache_enabled', 'prompt_cache_ttl', 'body_overrides', 'key_pick_mode', 'builtin'];
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
          KEY_PICK_RANDOM : KEY_PICK_ROTATE, // 脏值/空值钳位 rotate（存量语义——promptCacheTtl 同款）
        builtin: result.getLong(result.getColumnIndex('builtin')) === 1
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// 新建服务商（name/baseUrl 必填非空由调用方校验；sortOrder = 当前最大值 + 1 追加到尾；
// protocol 默认 openai、endpoint 默认 chat——存量调用兼容，UI 保存链显式传值；
// headersJson/bodyJson 默认 ''——UI 新建保存链显式传入；enabled 默认 true）。★ 本参数是
// **插入初值**，不是启用态通道——改已有行的启用态走 setProviderEnabled（单独通道）。
// ★ 预置 seed 须一步插入（B-3 教训：两步法第二步失败后重跑会被查重 continue 跳过，停用位
// 永久补不上）。builtin 尾参（v52）：唯一传 true 的调用点 = ProviderPresetSeed（预置行随
// 同一 INSERT 一步落库）；**缺省 false = 安全向**——漏传后果是「可删」而非「误锁」，一切
// 非 seed 路径不传即非内置
export async function insertProvider(name: string, baseUrl: string,
  protocol: string = PROTOCOL_OPENAI, endpoint: string = ENDPOINT_CHAT,
  headersJson: string = '', bodyJson: string = '',
  enabled: boolean = true, builtin: boolean = false): Promise<ProviderRow> {
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
    // 新行各默认值 = 对应列 DEFAULT 同值（bucket 不写 = 落库默认一致）：余额关/空、协议
    // openai、头空、形态 chat、提示缓存关 + TTL 5m
    balanceEnabled: false,
    balanceLastText: '',
    protocol: protocol,
    headers: '',
    endpoint: endpoint,
    promptCacheEnabled: false,
    promptCacheTtl: '5m',
    bodyOverrides: '',
    // 取钥方式默认轮换（DEFAULT 同值；改值走 setProviderKeyPickMode 单列通道）
    keyPickMode: KEY_PICK_ROTATE,
    // 内置标记默认 false（DEFAULT 同值；seed 侧显式传 true）
    builtin: builtin
  };
  const bucket: relationalStore.ValuesBucket = {
    'id': row.id, 'name': row.name, 'baseUrl': row.baseUrl, 'model': '', 'remark': '',
    'createdAt': row.createdAt, 'enabled': enabled ? 1 : 0, 'sortOrder': row.sortOrder,
    'protocol': row.protocol, 'endpoint': row.endpoint,
    'headers': headersJson, 'body_overrides': bodyJson,
    'builtin': builtin ? 1 : 0
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
  // 已开会话页连接缓存失效（baseUrl / 协议 / endpoint / headers / bodyOverrides 都是
  // buildCandidateConnection 的解析输入）——广播重解析；update 抛错即不广播（失败无假
  // 信号）；一处盖三调用方 = 编辑页保存 / AI provider update / AI headers 增删
  AppStorage.setOrCreate<number>(CONN_RESOLVE_TICK_KEY,
    (AppStorage.get<number>(CONN_RESOLVE_TICK_KEY) ?? 0) + 1);
}

// 启用/停用（停用的服务商不参与当前连接解析与选择面板）。
// ★ 停用即解绑（决明拍板「停用就回到未选择态、复启仍显示未选择」）：**停用 = 解除所有
// 指向它的模型选择**——助手绑定两列与思考档位复位、会话级模型覆盖两列、功能模型 8 槽两键
// 全清；重新启用不回填，须由用户重选。三面清理与行状态更新同事务（失败整体回滚，不留
//「停用了但绑定还在」的半态）；槽位两键是 AppStorage 不参与 DB 事务，故在 commit 后清
//（提交已落，清键不可能失败）。返回解除的绑定处数（0 = 无引用；启用恒 0）——调用方给回执
export async function setProviderEnabled(id: string, enabled: boolean): Promise<number> {
  const bucket: relationalStore.ValuesBucket = { 'enabled': enabled ? 1 : 0 };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('providers');
  predicates.equalTo('id', id);
  const db: relationalStore.RdbStore = sharedRdbStore();
  if (enabled) {
    await db.update(bucket, predicates);
    return 0;
  }
  const cleared: number = await runWriteQueued('setProviderEnabled', async (): Promise<number> => {
    db.beginTransaction();
    try {
      await db.update(bucket, predicates);
      const assistants: number = await clearAssistantBindingByProvider(id);
      const conversations: number = await clearConversationModelOverride(id, '');
      db.commit();
      const slots: number = clearSlotsForProvider(id);
      return assistants + conversations + slots;
    } catch (e) {
      db.rollBack();
      throw e as Error;
    }
  });
  // 已开会话页连接缓存失效——广播重解析（停用是用户显式动作，代价一次重解析）。★ 停用
  // 恒广播不看 cleared 计数——启用态本身是解析输入（四级兜底④级「首个启用模型」可能正停
  // 在这家，三面零命中但 conn 已失效）；计数只服务调用方回执
  AppStorage.setOrCreate<number>(CONN_RESOLVE_TICK_KEY,
    (AppStorage.get<number>(CONN_RESOLVE_TICK_KEY) ?? 0) + 1);
  return cleared;
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

// 更新服务商提示缓存两列（v12；服务商编辑页保存链调用——随保存键落库；0 行 throw =
// P0-1 假成功防御，updateTemplate/updateAssistantName 同款）
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

// 更新取钥方式单列（v32；服务商编辑页保存链尾调用——随保存键落库，与提示缓存同口径）。
// 脏值钳位 rotate（写侧第二道闸，读侧 queryProviders 已钳；两处同源常量）；0 行 throw =
// P0-1 假成功防御（同上款）。★ 本列只被发送链取钥起始位消费（ProviderKeyDb.nextPickStart），
// 协议层零引用
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
// 再删 providers 行，防孤儿模型/key/价格模板元数据行——价格模板按服务商隔离，归属没了模板
// 不留；同事务清 assistants 绑定列〔clearAssistantBindingByProvider——绑定该服务商的助手
// 归回未绑定态，强度档位一并复位〕；Asset 池条目清理与当前键失效在调用方编排——Asset 与
// AppStorage 非库内资源不入事务）。返回删除行数。
// ★ 合规整改①：allowBuiltin 尾参是**唯一**放行口，调用点白名单 = 内置境外行退役执行器
//（ProviderPresetRetire）+ 重复内置行收敛执行器（ProviderBuiltinDedup——备份导入让位与
// 启动收敛）——「用户 / AI 不可删内置」语义不变，业务调用一律不传（缺省 false）；放行仍走
// 同一事务级联，禁另抄删除实现。
export async function deleteProvider(id: string, allowBuiltin: boolean = false): Promise<number> {
  // ★ v52 内置保护硬拦截：内置服务商（builtin=1）不可删——前置查询照 deleteModel 先例
  // 留在事务与写链外（ResultSet 事务前用完并 close），命中即抛中文错误（调用方 toast /
  // 工具回执呈报）。三层防线中的数据层硬防线：UI 菜单隐藏与 AI 工具拒绝只是入口收敛，任何
  // 程序路径都过本闸。行不存在 = 落下方事务删 0 行返回 0（既有语义，调用方兜底），不报错
  //（查询变量名沿本件 result 惯例——71 组「close 数 == 查询点数」关系钉按 result.close() 计数）
  const guardPredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('providers');
  guardPredicates.equalTo('id', id);
  const result: relationalStore.ResultSet =
    await sharedRdbStore().query(guardPredicates, ['builtin']);
  try {
    if (!allowBuiltin && result.rowCount > 0 && result.goToNextRow() &&
      result.getLong(result.getColumnIndex('builtin')) === 1) {
      throw new Error('内置服务商不可删除，可改为停用');
    }
  } finally {
    result.close();
  }
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
  // ★ 写串行链入链（commit 后的会话覆盖级联清段随 work 保持原时序原语义）
  return runWriteQueued('deleteProvider', async (): Promise<number> => {
    db.beginTransaction();
    try {
      await db.delete(modelPredicates);
      await db.delete(keyPredicates);
      await db.delete(templatePredicates);
      await clearAssistantBindingByProvider(id);
      const deleted: number = await db.delete(providerPredicates);
      db.commit();
      // 会话级模型覆盖级联清：事务外执行——上表已删，清列失败只会留指向已删服务商的覆盖
      //（解析①级严格验证判不可用自动降级，非致命）；不进事务 = 不把「删服务商」整体拖成失败。
      // ★ 本步必须自吞异常：它跑在 commit **之后**，抛错会落进下方 catch——对已提交事务再
      // rollBack（无活动事务，行为未定义且可能掩盖原始异常）并把整笔报成「删除失败」，跳过
      // 调用方的 Asset 池清理与列表刷新，留跨卸载孤儿密钥明文——故吞错只留 hilog，语义仍
      //「非致命」
      try {
        await clearConversationModelOverride(id, '');
      } catch (e) {
        hilog.error(DOMAIN, TAG, '会话级模型覆盖级联清失败（解析①级会判不可用降级，非致命）：%{public}s',
          (e as Error).message);
      }
      // 功能模型 8 槽两键：槽位在 AppStorage 不在库，commit 后清（提交已落，清键不可能
      // 失败）。内置让位/收敛调用本函数前已先 remap 到保留行，此处对它们恒零命中
      clearSlotsForProvider(id);
      return deleted;
    } catch (e) {
      db.rollBack();
      throw e as Error;
    }
  });
}

// 清空全部服务商（唯一调用方 = 快速清理页）：逐家走既有「查池条目 id 集 → deleteProvider
// 库内事务级联 → removePoolKeys 清 Asset 明文」三步（与单家删除**同一顺序与同一理由**，
// 不复制实现、只驱动）。返回实删服务商行数。★ v52 起内置行跳过（循环首行判 builtin 直接
// continue——硬拦截对内置行必抛，跳过在前才不炸整链）；调用方清空后重置 seed 标记重跑
// seed，预置行经 name+baseUrl 查重全部跳过，「回到首次安装的预置服务商列表」语义仍真。
// ★ Asset 成对释放铁律（顺序不可换）：池条目明文不在 DB、且带 IS_PERSISTENT 卸载不删，
// 必须**先查 id 再删行**最后删明文——Asset 无前缀/枚举能力，行删了就再也拿不到 id 集，
// 留跨卸载孤儿密钥明文（deleteProvider 头注释同口径）。某家 removePoolKeys 抛错即整体抛
//（该家行已删、明文残留）——调用方按失败报出，不静默。
// ★ 不动预置 seed 标记（provider_presets_seeded）：本函数只负责「清空」，是否回到首次安装
// 的预置列表由调用方决定（见 common/QuickClean.ets；标记读写单源在 ProviderPresetSeed.ets，
// 本域不 import 它——反向 import 成环，坑50 零环红线）。不动 token_usage_events（历史账本
// 有意保留）。逐家 await 串行：Asset 写操作无并发收益，串行保证失败点位可定位（家数有界）。
export async function clearAllProviders(): Promise<number> {
  const rows: ProviderRow[] = await queryProviders();
  let removed: number = 0;
  for (const row of rows) {
    if (row.builtin) {
      continue; // 内置服务商保留（v52）——Asset 池三步骤同跳过
    }
    const keyRows: ProviderKeyRow[] = await queryProviderKeys(row.id);
    const keyIds: string[] = keyRows.map((key: ProviderKeyRow): string => key.id);
    removed += await deleteProvider(row.id);
    await removePoolKeys(row.id, keyIds);
  }
  return removed;
}

// 全服务商的模型计数（providerId → 行数；列表页徽章消费——一条 GROUP BY 免逐家查询循环）。
// querySql 直查（RdbPredicates 无聚合能力）
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

// 某服务商的模型清单（创建先后序）；kindFilter 传 '' = 不过滤。停用行照常返回，消费方
// 自行过滤（选择面板与连接解析过滤 enabled，详情页模型页签全量展示带开关）
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

// 全量模型行（费用估计价格 map 数据源——按 providerId+'/'+modelId 关联价格需跨服务商
// 全量一次拉齐；用户手建清单自然有界）。★ 独立实现不借用 queryModels——后者按
// providerId equalTo 过滤；排序 createdAt 升序同 queryModels（modelId 单键兜底「首个
// 命中」的确定序）；kind 不过滤（费用事件天然只出自对话模型，行过滤反而可能砍掉命中目标行）
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
// ★ caps_user_modified 不扩签：内部按「caps 非空 ⇒ 1（用户手设固化），空 ⇒ 0（读时按
// 模型名派生）」落值——获取模型（恒空串）/手动添加（勾选保存即手设）/导入（原样含空）/
// 遗留迁移（恒空串）各调用方语义自动正确。
// ★ v33 尾参 contextWindow（0 = 未配置 = 跟随内置参考值）**可选参**——上列调用点不传即 0，
// 编辑页新建链显式传值（与 priceConfig 同姿态）
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
    // v21 收藏标记：新行恒未收藏（bucket 不写 = DEFAULT 0 同值）
    favorite: false,
    // v27 价格配置：缺省 '' = 未配置（bucket 不写 = DEFAULT 同值；编辑页新建链显式传值）
    priceConfig: priceConfig,
    // v33 上下文窗口：缺省 0 = 未配置（同上）
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

// 更新模型行（modelId 不可改——行身份；name/kind/caps 可编辑；capsUserModified = 派生/
// 覆盖标志——true = 用户手改固化（含「全不勾」的显式清空，此后不再派生）；★ false 也是
// 合法落值：能力卡「重置」= 恢复自动识别，父侧写 false 并落回派生勾选态（与「从未手改」
// 完全同态）。priceConfig = v27 价格 JSON 串（'' = 清除回未配置；合法性由编辑页保存链 +
// CostStatsCalc.parsePriceConfig 双侧把守，本层透传不解析）。contextWindow = v33（0 =
// 未配置 / 非 0 = 覆盖值）。★ 调用方三处 = ModelEditPage 保存链 + ToolModelAdmin 的
// model_admin edit 与 reset_caps（模型可在会话内改自己的 caps）——尾参仍不给缺省值：
// 漏传即编译错，防新增调用点静默把用户值清成 0（与 capsUserModified/priceConfig 同姿态）
export async function updateModel(rowId: string, name: string, kind: string, caps: string,
  capsUserModified: boolean, priceConfig: string, contextWindow: number): Promise<void> {
  const bucket: relationalStore.ValuesBucket = {
    'name': name, 'kind': kind, 'caps': caps, 'caps_user_modified': capsUserModified ? 1 : 0,
    'price_config': priceConfig, 'context_window': contextWindow
  };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('provider_models');
  predicates.equalTo('id', rowId);
  await sharedRdbStore().update(bucket, predicates);
  // 已开会话页连接缓存失效（caps 是解析输入——effectiveCaps 现算的原始列）——广播重解析；
  // 不广播则同会话 hasVision 停旧值，截图硬门把可读图错拦成「不支持读图」。一处广播盖全
  // 三调用方（UI 编辑 / AI edit / AI reset_caps）；update 抛错即不广播（失败无假信号）
  AppStorage.setOrCreate<number>(CONN_RESOLVE_TICK_KEY,
    (AppStorage.get<number>(CONN_RESOLVE_TICK_KEY) ?? 0) + 1);
}

// 模型启停（停用 = 不进选择面板与连接解析）。
// ★ 停用即解绑（setProviderEnabled 同款语义）：停用单个模型 = 解除恰好指向（providerId,
// modelId）这一对的模型选择——助手绑定两列与思考档位、会话覆盖两列、功能模型 8 槽两键；
// 复启不回填；同服务商换绑其他模型的绑定不受影响。行身份先查（事务外取、用完 close）；
// 返回解除处数（启用恒 0）
export async function setModelEnabled(rowId: string, enabled: boolean): Promise<number> {
  const bucket: relationalStore.ValuesBucket = { 'enabled': enabled ? 1 : 0 };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('provider_models');
  predicates.equalTo('id', rowId);
  const db: relationalStore.RdbStore = sharedRdbStore();
  if (enabled) {
    await db.update(bucket, predicates);
    return 0;
  }
  const rowPredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('provider_models');
  rowPredicates.equalTo('id', rowId);
  // 查询点写法照 deleteModel（sharedRdbStore().query 直取）——71 组「close 数 == 查询点数」
  // 关系钉按该形态计数，写成局部 db 变量会漏计一侧
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
  const cleared: number = await runWriteQueued('setModelEnabled', async (): Promise<number> => {
    db.beginTransaction();
    try {
      await db.update(bucket, predicates);
      let assistants: number = 0;
      let conversations: number = 0;
      if (boundProviderId !== '' && boundModelId !== '') {
        assistants = await clearAssistantBindingByModel(boundProviderId, boundModelId);
        conversations = await clearConversationModelOverride(boundProviderId, boundModelId);
      }
      db.commit();
      const slots: number = boundProviderId !== '' && boundModelId !== ''
        ? clearSlotsForModel(boundProviderId, boundModelId) : 0;
      return assistants + conversations + slots;
    } catch (e) {
      db.rollBack();
      throw e as Error;
    }
  });
  // 停用恒广播（同 setProviderEnabled 口径）：启用态本身是解析输入，四级兜底④级「首个启用
  // 模型」可能正停在这个模型上——三面零命中时 conn 仍已失效；计数只服务回执
  AppStorage.setOrCreate<number>(CONN_RESOLVE_TICK_KEY,
    (AppStorage.get<number>(CONN_RESOLVE_TICK_KEY) ?? 0) + 1);
  return cleared;
}

// 模型收藏（v21：单列 UPDATE，不动 createdAt/updatedAt——收藏不改变列表序，
// setConversationFavorite 同口径。随模型行同生命周期：删行即标记消失，无级联面）
export async function setModelFavorite(rowId: string, favorite: boolean): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'favorite': favorite ? 1 : 0 };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('provider_models');
  predicates.equalTo('id', rowId);
  await sharedRdbStore().update(bucket, predicates);
}

// 删除模型行（先查行取 providerId/modelId——删后级联清绑定该模型的助手行
//〔clearAssistantBindingByModel，三列归空〕+ 会话级模型覆盖〔clearConversationModelOverride〕；
// 行已不存在 = 直接返回，无级联目标。与 deleteProvider 同形制：三步包事务，任一步失败整体
// 回滚——防悬空绑定/悬空覆盖）
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
  // ★ 写串行链入链（前置查询按既有注释留在链外）
  return runWriteQueued('deleteModel', async (): Promise<void> => {
    db.beginTransaction();
    try {
      await db.delete(rowPredicates);
      if (boundProviderId !== '' && boundModelId !== '') {
        await clearAssistantBindingByModel(boundProviderId, boundModelId);
        // 会话级模型覆盖级联清：覆盖指向的行没了，留着只在解析①级空转（严格对验证判不可用
        // 降级），清掉让会话干净落回默认源。清列不删会话不删历史
        await clearConversationModelOverride(boundProviderId, boundModelId);
      }
      db.commit();
      // 功能模型 8 槽两键：commit 后清（AppStorage 不参与事务）
      if (boundProviderId !== '' && boundModelId !== '') {
        clearSlotsForModel(boundProviderId, boundModelId);
      }
    } catch (e) {
      db.rollBack();
      throw e as Error;
    }
  });
}

// ── 当前连接（聊天页）──

// 解析结果（连接三件 + 服务商名——providerName 现无 UI 消费，字段保留：调试/后续功能可用，
// 解析链零改动）。
// ★ + caps 生效能力串（发送前置视觉门控的唯一输入源）：buildCandidateConnection 手里正拿
// model 行（填充点现成、零额外查询、切模型随 reloadConn 自动更新）；消费侧禁在发送时另起
// DB 查询、禁直读 row.caps（A1 明令）
// ★ + modelName 模型显示名（2026-11-25 五轮「模型思考热区合一」）：同一填充点顺手取
// `model.name`，空串回落 modelId（与 resolveModelDisplayLabel 同口径）——标题栏单热区与卡内
// 模型入口共用；同样禁消费侧另起 DB 查询（那会把每次重解析放大成两条查询）。
export interface ActiveConnectionInfo {
  conn: AiConnection;
  providerName: string;
  caps: string;
  modelName: string;
}

// 解析聊天页当前连接（四级兜底链，决明指令「会话页所选 > 会话所属的助手绑定 > 全局默认 >
// 首个启用模型」——★ 中途不停：每级候选按同一标准验证（服务商启用 + 模型可用 + key 池非空），
// 任一环不满足即静默降下一级，全链落空才返回 null，不中途报错停链）：
// ①会话页所选 = **本会话覆盖**（conversations.modelProviderId/modelId 两列，无行会话由
//   调用方传内存覆盖——DB v24）。覆盖是用户在**该会话内**的显式选择，**严格对（providerId,
//   modelId）验证、不自愈换模**（原①级键指失效换同服务商首个启用模型的自愈语义已随 active
//   键退役——用户没选过就不该算①级命中）；
// ②助手绑定 = ownerAssistantId 指向 assistants 行的 providerId/modelId 两列（归属口径与
//   注入链 ChatPromptState 一致；严格按绑定对验证——绑定意图精确到模型，停用不自愈换模）；
// ③全局默认 = default 两键（功能模型页「默认模型」）；
// ④首个启用模型 = 按服务商排序序跨服务商找第一个「启用 + 有启用对话模型 + key 池非空」组合。
// key 池只验非空不读明文（明文最小化：「行在明文无」＝解析通过、发送期逐支取钥失败跳过 +
// 全部失败 notice 呈报）。
// 缓存/回写口径（决明拍板「兜底借用不留底」）：**全部四级一律不回写任何全局状态**——①级
// 覆盖由用户在会话内的显式操作落列，解析只读；"兜底借用"与"显式选择"彻底分离——改助手
// 绑定/改全局默认后，未被显式覆盖过的会话下次发送即时生效。
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
// 精确到模型，不自愈换模。★ 原①级「键指失效取同服务商首个启用模型」自愈语义已随覆盖层笔
// 退役，自愈形参 fallbackFirstModel 连同两死分支整体拆除——形参在场即留「传 true 复活
// 退役行为」的口子，严格性由签名结构保证；第④级首个启用不经本函数（直取 models[0] 走
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
  // 生效能力串一次计算（★ 2026-10-03 工具图挂载笔：conn.caps 与 info.caps 同源同值——
  // effectiveCaps 单源〔用户改过则原样、否则按模型名派生〕，AiConnection.caps 唯一填充点）
  const caps: string = effectiveCaps(model);
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
      // 思考策略（A2 唯一填充点）：协议+接口形态+baseUrl+模型 id 画像解析（ModelRegistry，
      // 模型级精化）——off 生效判定与将来策略化 compose 的单一来源；无解析失败路径（未知
      // 协议兜底 'none'）。同填充点两字段：off 支持（supportsThinkingOff 恒查 openai chat
      // 画像——「与协议形态无关」语义在判定侧归一）+ 菜单选项集（thinkingOptionsFor 按本
      // 连接形态派生——画像行收窄或全量缺省）
      reasoningStrategy: resolveReasoningStrategy(provider.protocol, provider.endpoint,
        provider.baseUrl, model.modelId),
      reasoningOffSupported: supportsThinkingOff(provider.baseUrl, model.modelId),
      reasoningMenuOptions: thinkingOptionsFor(provider.protocol, provider.endpoint,
        provider.baseUrl, model.modelId),
      // 随连接走的 caps 快照（★ 2026-10-03 工具图挂载笔——与下方 info.caps 同源同值）
      caps: caps
    },
    providerName: provider.name,
    // 生效能力串（用户改过则原样 / 否则按模型名派生，单源 effectiveCaps——发送侧视觉门控
    // 读它，禁直读 row.caps）
    caps: caps,
    // 模型显示名（★ 2026-11-25 五轮）：行 name 空则回落 modelId——与 resolveModelDisplayLabel
    // 同口径；标题栏单热区/卡内模型入口直接消费，禁消费侧二次查库
    modelName: model.name !== '' ? model.name : model.modelId
  };
  return info;
}

// ── 遗留单连接迁移（启动一次性，EntryAbility 在 initChatDb 后调用）──

// providers 空表时把 v1 单连接资产导入为首个服务商（名「默认服务商」+ 首个对话模型 +
// key 池首条 k1——直接写池，不经单 key 形态），并设为当前选择；已有服务商/无遗留资产 =
// 直接返回。失败打日志不阻断启动（解析侧对空态自有兜底，迁移下次启动重试——幂等：只在
// 空表时动作）
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
    // ★ 原此处 setActiveConnection（写「当前选择」两键）随 active 键退役——不再写任何
    //「当前」状态：本函数只在 providers 空表时动作（新装/迁移首启），此时该服务商是唯一
    // 启用且有钥候选 = 解析链④级必然命中它，行为等价（零回归）
    hilog.info(DOMAIN, TAG, '遗留连接已迁移为首服务商 %{public}s', provider.id);
  } catch (e) {
    hilog.error(DOMAIN, TAG, '遗留连接迁移失败（下次启动重试）：%{public}s', (e as Error).message);
  }
}
