// AI 协议层公共类型（2026-08-29 任务书 M1 新增）：连接配置与 chat/completions 请求侧模型。
// 分层约定：本文件属 common/providers（最底层），只许被 components/pages 单向 import，
// 禁止反向 import 上层。SSE 帧解析相关类型在 SseParser.ets（该文件零 import，
// 保 node 断言脚本同源直跑，见 scripts/sse-assert.mjs）。
// 2026-08-30 多 Key 池 + 三协议：协议常量表（全工程禁裸字符串协议值——DB/工厂/UI/解析
// 一律引本表）与自定义请求头模型在此；流式回调与流接口（AiStreamHandlers/ChatStream）
// 因三协议共用也收敛在此（原 OpenAiCompatApi 导出处退役）。
import { SseDelta, AiUsageDelta, AiReasoningItem } from './SseParser';
// 采样参数单一来源在 RequestCompose（零 import 约束 + ArkTS 禁结构化类型——双接口同构
// 互传即编译错，故定义在那边 export、此处 re-export 供全工程从 AiTypes 门面消费；与
// import SseParser.SseDelta 同款姿势，无循环依赖）
import { SamplingParams, AiToolDef, AiToolCall } from './RequestCompose';
// 模型能力注册表门面（2026-09-03 Cube 兼容画像与模型匹配引擎吸收 A1+A2）：单一定义在
// ModelRegistry（零 import 纯逻辑域 + sse-assert 复制直跑），本处 re-export 供全工程从
// AiTypes 消费（SamplingParams 同款姿势）：能力派生查询 / 思考策略解析 / 思考开关方言
// 画像判定 / 思考菜单选项集派生（2026-09-06 模型级精化）/ effectiveCaps 派生覆盖语义。
// 值域与语义见 ModelRegistry 头注释。
// ★ 2026-09-17 增 lookupContextBaseline（模型上下文窗口参考值查询，DB v33）：同款门面姿势
// ——消费方 = ProviderDb.effectiveContextWindow 与编辑模型页，禁各处直 import 注册表
import { lookupModelAbilities, resolveReasoningStrategy, supportsDeepSeekProfile,
  effectiveCapsOf, deriveCapsFromAbilities, STRATEGY_DEEPSEEK_THINKING, thinkingOptionsFor,
  lookupContextBaseline } from './ModelRegistry';

export { SamplingParams, AiToolDef, AiToolCall };
export { AiUsageDelta };
export { AiReasoningItem };
export { lookupModelAbilities, resolveReasoningStrategy, supportsDeepSeekProfile,
  effectiveCapsOf, deriveCapsFromAbilities, STRATEGY_DEEPSEEK_THINKING, thinkingOptionsFor,
  lookupContextBaseline };

// ── 协议常量表（providers.protocol 列值域；默认 openai = 存量行为不变）──
export const PROTOCOL_OPENAI: string = 'openai';
export const PROTOCOL_ANTHROPIC: string = 'anthropic';
export const PROTOCOL_GEMINI: string = 'gemini';
// 分段/模板展示序（UI SegmentBar 三选一与预设模板消费；与 PROTOCOL_VALUES 同下标）
export const PROTOCOL_VALUES: string[] = [PROTOCOL_OPENAI, PROTOCOL_ANTHROPIC, PROTOCOL_GEMINI];
export const PROTOCOL_LABELS: string[] = ['OpenAI 兼容', 'Anthropic', 'Gemini'];
// 协议值 → 展示名（未知值兜底 OpenAI 兼容——工厂同款兜底语义）
export function protocolLabel(protocol: string): string {
  const idx: number = PROTOCOL_VALUES.indexOf(protocol);
  return idx >= 0 ? PROTOCOL_LABELS[idx] : PROTOCOL_LABELS[0];
}

// ── 协议能力表（为后续功能能力检查预留；第一版只声明已实测能力，检查函数由注入功能会话补）──
// system = 系统提示词注入落点（三协议均已实测：openai 原样进 messages / anthropic 提顶层
// system / gemini 提 systemInstruction——组装实现见 RequestCompose，落点断言见 sse-assert ⑪ 组）；
// reason = 思考增量解析（openai reasoning_content / anthropic thinking_delta / gemini
// thought 段（2026-08-31 起）/ responses reasoning 事件均在 SseParser 实测断言）。docs/协议能力支持矩阵.md 为本表纯展示，唯一真实源在此。
// 2026-08-30 OpenAI Responses 适配：+ openaiResponses 键（接口形态值域，非协议族）——
// system 落点 = instructions / reason = reasoning 事件解析（parseResponsesPayload 已实现
// 并断言），仅 OpenAI 官方端点支持（第三方「OpenAI 兼容」中转不实现 /v1/responses）。
// 2026-08-31 附件上传：+ vision（图片多模态发送——四协议 compose 层方言适配已落，断言
// 见 sse-assert ⑰ 组；真机验收待装机，见 BLOCKED.md）。
// 2026-08-31 思考档位（任务 B，官方查证入 docs/协议能力支持矩阵.md）：+ thinking（四协议
// 请求体思考参数方言已落 RequestCompose——openai 顶层 reasoning_effort / responses
// reasoning{effort} / anthropic output_config{effort} / gemini
// generationConfig.thinkingConfig，断言见 sse-assert ⑱ 组）；gemini 同时补 reason 键——
// 官方 includeThoughts 开启后思考摘要段以 parts[].thought=true 回传，parseGeminiDelta
// 已路由进 reasoningContent（A2 自检缺口修复）。能力表行（键 = PROTOCOL_* 常量值 +
// 形态后缀，与常量表逐项对齐；ArkTS 禁无显式接口的对象字面量挂 Record——坑59① 同族
// arkts-no-untyped-obj-literals，故以显式接口承载）
export interface ProtocolCaps {
  openai: string[];
  anthropic: string[];
  gemini: string[];
  openaiResponses: string[];
}

export const PROTOCOL_CAPS: ProtocolCaps = {
  openai: ['system', 'reason', 'vision', 'thinking', 'tools'],
  anthropic: ['system', 'reason', 'vision', 'thinking', 'tools'],
  gemini: ['system', 'reason', 'vision', 'thinking', 'tools'],
  openaiResponses: ['system', 'reason', 'vision', 'thinking', 'tools']
};

// 思考档位能力判定（PROTOCOL_CAPS.thinking 键消费——ChatSendCtrl 注入 thinking 前判定，
// 协议不支持 = 不传（零回归）；openai 族按接口形态分流到 openaiResponses 键，兜底语义与
// ChatStreamFactory 同款）
export function supportsThinking(protocol: string, endpoint: string): boolean {
  if (protocol === PROTOCOL_ANTHROPIC) {
    return PROTOCOL_CAPS.anthropic.includes('thinking');
  }
  if (protocol === PROTOCOL_GEMINI) {
    return PROTOCOL_CAPS.gemini.includes('thinking');
  }
  if (endpoint === ENDPOINT_RESPONSES) {
    return PROTOCOL_CAPS.openaiResponses.includes('thinking');
  }
  return PROTOCOL_CAPS.openai.includes('thinking');
}

// 思考档位菜单选项集全量缺省（''=默认不传 / off=关闭思考（开关方言画像域暴露——2026-09-06 起
// DeepSeek/GLM/Kimi 官方域，判定见 supportsThinkingOff）/ low / high / max），
// Gemini 预算映射在 RequestCompose.geminiThinkingBudget；2026-08-31 自 ChatPage 迁入——
// 协议档位值域归协议常量层，页面接线消费。★ 2026-08-31 增 off：菜单序 = 默认/关闭/
// low/high/max（关闭紧挨默认——思考开关语义分组）。★ 2026-09-06 模型级精化：本常量 =
// 缺省全集——画像行显式 menuOptions 时收窄（Kimi K3/K2.x 等模型级参数体系分裂，派生见
// ModelRegistry.thinkingOptionsFor；页面接线消费 conn.reasoningMenuOptions / 派生函数）。
// ★ 2026-09-11 口径纠正：原文「三档枚举四协议官方均合法」已证伪（GLM-4.5/4.6 官方无
// reasoning_effort、GLM-5.3 仅收 max/high/low、GLM-5.2 的 low 官方映射为 high）——本常量
// 只是「未命中画像行的连接」的缺省全集，不代表任意模型都合法；逐模型的合法集与等价冗余
// 一律查画像行（判据三条见 ModelRegistry 的 menuOptions 字段注释），勿以本常量为合法性依据
export const THINKING_OPTIONS: string[] = ['', 'off', 'low', 'high', 'max'];

// ── 「关闭思考」域判定（2026-08-31 新增；2026-09-03 Cube 吸收 A2 归一画像；2026-09-06
// 模型级精化）──
// 判定单一来源 = ModelRegistry 开关画像（baseUrl + 模型 id 二维行命中）：关闭思考 = 服务商
// 官方规格差异项——DeepSeek 官方（OpenAI 格式顶层 thinking{type:enabled/disabled}、
// Anthropic 格式 reasoning{effort:none}）；★ 2026-09-06 扩 GLM/Kimi 官方域（两家官方文档
// 实锤 openai 形态 thinking{type:disabled} 与 DeepSeek 逐字节同形）；同日晚模型级精化——
// GLM-4.7/4.5V/5.3 强制系与 kimi-k3/k2.7-code 恒思考关不掉（K3 实测不收 thinking 参数
// 静默忽略、k2.7-code 传 disabled 必 400——原「传之端侧报错走回显链」预期被实测推翻，
// 依据见 ModelRegistry 表注释）→ 行级 supportOff=false 摘档；OpenAI/Anthropic 官方与
// Gemini 原生均无（effort/thinkingConfig 无 off/none 值，传 none 有 400 实锤——矩阵文档
// 查证节）。
// 「支持非思考的模型」= 此画像内的官方域 + 模型，非逐厂商/逐模型散落特判；将来扩展生态 =
// ModelRegistry 画像表加行，勿在业务层散落特判（文档口径同矩阵）。★ 原
// THINKING_OFF_DOMAINS 域名表已退役（禁留双实现——画像行等价承接，实现改查
// supportsDeepSeekProfile〔历史命名，语义 = 开关方言画像命中且行级未禁 off〕，等价性
// 由 sse-assert 断言组钉死）。modelId 缺省 '' = 模型级行不命中，退化 provider 级旧行为
export function supportsThinkingOff(baseUrl: string, modelId: string = ''): boolean {
  return supportsDeepSeekProfile(baseUrl, modelId);
}

// 连接「关闭思考」生效判定（2026-09-03 Cube 吸收 A2）：协议流 requestBody offEnabled
// 实参与 ChatSendCtrl 发送守卫的单一判定源（原三调用点同款逻辑提取，P2-4）。
// ★ 2026-09-06 模型级精化：首选 conn.reasoningOffSupported（resolveActiveConnection
// 唯一填充 = 画像行模型级判定，「与协议形态无关」语义由填充侧恒查 openai chat 画像
// 归一——anthropic 形态 DeepSeek 的 reasoning{effort:none} 同样支持 off）；
// undefined（解析链外构造的连接）回落 supportsThinkingOff(baseUrl, model) 二维判定。
// 旧快速分支（reasoningStrategy === deepseek_thinking 直返 true）退役——模型级禁 off 行
//（GLM 强制系）strategy 仍标 deepseek_thinking，直返会把禁 off 行放行 = 回归
export function connectionOffEnabled(conn: AiConnection): boolean {
  if (conn.reasoningOffSupported !== undefined) {
    return conn.reasoningOffSupported;
  }
  return supportsThinkingOff(conn.baseUrl, conn.model);
}

// 思考档位合法性归一（2026-09-06 模型级精化；三处消费同款逻辑提取——ChatPage setConnInfo
// 回退 / ModelSettingsPage 绑定守卫 / ChatSendCtrl 发送双保险，P2-4）：'' 恒合法；
// 'off' 须 offSupported 且选项集含 off（行级禁用与收窄同源）；其余档位看选项集包含
//（画像行 menuOptions 收窄后存量非法档位归 '' = 默认不传，静默零字段——防「收窄前
// 选中值 + 收窄后漏网」）
export function legalThinkingTier(tier: string, offSupported: boolean, options: string[]): string {
  if (tier === '') {
    return '';
  }
  if (tier === 'off') {
    return offSupported && options.includes('off') ? 'off' : '';
  }
  return options.includes(tier) ? tier : '';
}

// OpenAI 官方域判定（2026-09-06 Responses 修复）：baseUrl 以 https://api.openai.com 开头 =
// 官方端点。消费面 = Responses 工具轮 reasoning item 保真链（include:
// ['reasoning.encrypted_content'] 请求 + 捕获回传）——该 include 仅官方端点规格内（第三方
// responses 网关/国产无状态实现不支持，Cube 调研 01 卷 supportsOpenAIResponsesEncryptedReasoning
// 仅 openai 官方 true 同款口径；DeepSeek 文档明示 encrypted_content 不支持）；本端连接 UI
// 对「Responses 配非官方域名」本就有 warn 提示（ProviderCatalog.describeMismatch），判定与
// 之一致。★ scheme 锚定非子串包含：`xx-api.openai.com.proxy.xx` 类代理域名不得误命中——
// 误发 include 给不支持的中转可 400，且 body_overrides 只能覆盖键不能删键无自救通道；
// 漏判方向安全（不发 include = 不回传 = 维持现状零回归）
export function isOfficialOpenAiBaseUrl(baseUrl: string): boolean {
  return baseUrl.startsWith('https://api.openai.com');
}

// ── OpenAI 接口形态常量表（providers.endpoint 列值域；仅对 openai 协议有意义——a/g
// 恒 ENDPOINT_CHAT 不显示不保存语义差；默认 chat = 存量行为不变）──
export const ENDPOINT_CHAT: string = 'chat'; // /chat/completions（OpenAI 兼容中转站通用方言）
export const ENDPOINT_RESPONSES: string = 'responses'; // /v1/responses（OpenAI 官方新接口，
// 仅官方端点支持；官方推荐新项目使用——Chat Completions 继续支持可增量迁移）
export const ENDPOINT_VALUES: string[] = [ENDPOINT_CHAT, ENDPOINT_RESPONSES];
export const ENDPOINT_LABELS: string[] = ['chat/completions', 'Responses'];

// 自定义请求头一对（providers.headers 列存 JSON 串 [{k,v}]；发送前逐条追加，允许覆盖
// 内置头含认证头——中转站场景拍板；空 k 或空 v 的行保存时丢弃）
export interface HeaderPair {
  k: string;
  v: string;
}

// headers JSON 串 → 键值对（坏 JSON/非数组容错回 []——不炸加载；元素非 {k,v} 形跳过）
export function parseHeaderPairs(json: string): HeaderPair[] {
  if (json === '') {
    return [];
  }
  let raw: object[] | null = null;
  try {
    const parsed: object = JSON.parse(json);
    raw = Array.isArray(parsed) ? parsed as object[] : null;
  } catch (e) {
    return [];
  }
  if (raw === null) {
    return [];
  }
  const pairs: HeaderPair[] = [];
  for (const item of raw) {
    const rec = item as Record<string, Object>;
    const k: Object | undefined = rec['k'];
    const v: Object | undefined = rec['v'];
    if (typeof k === 'string' && typeof v === 'string') {
      pairs.push({ k: k, v: v });
    }
  }
  return pairs;
}

// 键值对 → headers JSON 串（空 k 或空 v 的行丢弃——拍板；全空回 '' = 库列默认形态）
export function serializeHeaderPairs(pairs: HeaderPair[]): string {
  const kept: HeaderPair[] = pairs.filter((pair: HeaderPair): boolean => pair.k !== '' && pair.v !== '');
  if (kept.length === 0) {
    return '';
  }
  return JSON.stringify(kept);
}

// ── 助手高级设定参数（2026-09-01 高级设定卡，DB v11 assistants.advancedParams 列）──
// SamplingParams（发送侧采样参数——compose 消费，四协议方言落点在 RequestCompose；全
// 可选 = 关闭该项不发送，请求体零回归）**定义在 RequestCompose 并由本文件 re-export**
//（单一来源，见顶部 import 注释）。maxOutput 三态：undefined = 未配置（anthropic 维持
// 8192 现状，其余协议不发字段）/ 0 = 显式不限制（anthropic 兜底 131072，其余协议不发
// 字段）/ 正数 = 按值发送

// 存储侧全量（SamplingParams + contextCount 应用层截取项，不进请求体）
export interface AssistantAdvancedParams extends SamplingParams {
  contextCount?: number; // 0~100（0/undefined = 不限制；截取在 ChatSendCtrl 注入前）
}

// advancedParams 列 JSON 串 → 参数对象（'' / 坏 JSON / 非对象 = null 未配置，容错回退
// 不炸加载——parseHeaderPairs 范式；逐键 number 校验，NaN/非数值键跳过）
export function parseAssistantAdvancedParams(json: string): AssistantAdvancedParams | null {
  if (json === '') {
    return null;
  }
  let rec: Record<string, Object> | null = null;
  try {
    const parsed: object = JSON.parse(json);
    rec = Array.isArray(parsed) ? null : parsed as Record<string, Object>;
  } catch (e) {
    return null;
  }
  if (rec === null) {
    return null;
  }
  const params: AssistantAdvancedParams = {};
  const keys: string[] =
    ['temperature', 'topP', 'presencePenalty', 'frequencyPenalty', 'maxOutput', 'contextCount'];
  for (const key of keys) {
    const v: Object | undefined = rec[key];
    if (typeof v === 'number' && Number.isFinite(v)) {
      if (key === 'temperature') {
        params.temperature = v;
      } else if (key === 'topP') {
        params.topP = v;
      } else if (key === 'presencePenalty') {
        params.presencePenalty = v;
      } else if (key === 'frequencyPenalty') {
        params.frequencyPenalty = v;
      } else if (key === 'maxOutput') {
        params.maxOutput = v;
      } else {
        params.contextCount = v;
      }
    }
  }
  return params;
}

// 参数对象 → advancedParams 列 JSON 串（undefined 键 JSON.stringify 自动省略 = 开关关闭
// 不落键；全默认〔六键全 undefined〕回 '' = 库列默认形态 = 未配置，anthropic max_tokens
// 走 8192 现状——「显式 0」与「未配置」靠键存在性区分，UI 层决定键集合：上下文页保存
// 恒写 contextCount/maxOutput 两键）
export function serializeAssistantAdvancedParams(params: AssistantAdvancedParams): string {
  if (params.temperature === undefined && params.topP === undefined &&
    params.presencePenalty === undefined && params.frequencyPenalty === undefined &&
    params.maxOutput === undefined && params.contextCount === undefined) {
    return '';
  }
  const full: AssistantAdvancedParams = {
    temperature: params.temperature,
    topP: params.topP,
    presencePenalty: params.presencePenalty,
    frequencyPenalty: params.frequencyPenalty,
    maxOutput: params.maxOutput,
    contextCount: params.contextCount
  };
  return JSON.stringify(full);
}

// 连接配置三项（任务书拍板：M1 聊天页内置极简「连接设置」，运行时写入 Asset，不进代码/git）。
// 2026-08-30 三协议扩展：+ protocol（协议分发）/ headers（自定义请求头）/ providerId
//（key 池归属——发送编排按池轮询取钥）；apiKey 字段退役——多 Key 池下密钥改为发送时
// 经 ChatStream.start(conn, apiKey, messages) 按次注入（获取模型/余额的兜底取钥走池首）
// 2026-08-30 Responses 适配：+ endpoint（OpenAI 族接口形态——工厂按 protocol+endpoint
// 分发 chat/completions 或 /v1/responses；a/g 恒 ENDPOINT_CHAT）
export interface AiConnection {
  baseUrl: string; // 如 https://api.deepseek.com/v1（末尾斜杠容忍，协议层归一化）
  model: string;
  protocol: string; // PROTOCOL_VALUES 之一（见常量表）
  endpoint: string; // ENDPOINT_VALUES 之一（仅 openai 有意义；默认 chat）
  headers: HeaderPair[]; // 自定义请求头（空数组 = 无）
  providerId: string; // 所属服务商（key 池轮询/失败切换归属；遗留迁移路径可 ''）
  // Anthropic 提示缓存（2026-09-01 DB v12 providers 两列随解析填充；undefined = 关 =
  // composeAnthropicBody 不带 cache 参零回归；仅 anthropic 协议消费——消费方
  // AnthropicChatStream.requestBody，TTL 值域 '5m' | '1h'）
  promptCacheEnabled?: boolean;
  promptCacheTtl?: string;
  // 取钥方式（2026-09-17 DB v32 providers.key_pick_mode 随解析填充；值域 KEY_PICK_ROTATE
  // 'rotate' 默认 | KEY_PICK_RANDOM 'random'，常量表在 store/ProviderKeyDb.ets）。
  // 消费方唯一 = ChatSendCtrl 轮次启动的起始位选择（nextPickStart）；undefined = 解析链外
  // 构造的连接（防御态——取钥侧按 rotate 兜底）。★ 协议层零消费（compose/stream 不看本字段，
  // 请求字节与升级前逐字节一致）
  keyPickMode?: string;
  // 自定义 Body 覆盖（2026-09-02 DB v13 providers.body_overrides 随解析填充；空数组 =
  // 无覆盖 = 请求体逐字节零回归）。元素复用 HeaderPair 形态：k = 请求体顶层键名，
  // v = 合法 JSON 值文本（入库侧已校验）；发送时 ChatStreamBase.start 统一 merge 到
  // 请求体根对象——协议无关单一落点，同键覆盖内置键（与 headers 覆盖语义一致拍板）
  bodyOverrides?: HeaderPair[];
  // 思考策略（2026-09-03 Cube 吸收 A2）：resolveActiveConnection 唯一填充点（协议+接口
  // 形态+baseUrl+模型 id 二维画像解析，ModelRegistry.resolveReasoningStrategy——DB 无列
  // 不落库；2026-09-06 起传模型 id 模型级精化）。
  // 值域 'none' | 'openai_effort' | 'deepseek_thinking' | 'anthropic_effort' |
  // 'google_thinking'（STRATEGY_* 常量值域）。本期消费 = off 生效判定
  //（connectionOffEnabled）；将来「策略 + 档位 → 方言」策略化 compose 在此字段扩展。
  // undefined = 解析链外构造的连接（防御态——消费侧兜底 supportsThinkingOff 域名判定）
  reasoningStrategy?: string;
  // 「关闭思考」支持（2026-09-06 模型级精化）：与 reasoningStrategy 同填充点同源判定
  //（ModelRegistry.supportsDeepSeekProfile(baseUrl, model)——模型级禁 off 行 = false）。
  // 消费 = connectionOffEnabled 首选 / ChatPage offOk 广播；undefined 同上防御态回落
  reasoningOffSupported?: boolean;
  // 思考菜单选项集（同填充点，ModelRegistry.thinkingOptionsFor 派生——画像行 menuOptions
  // 收窄或全量缺省）。消费 = ChatPage chip 菜单选项 / ChatSendCtrl 发送档位合法性双保险
  reasoningMenuOptions?: string[];
}

// role 事实值 'system' | 'user' | 'assistant' | 'tool'（2026-09-02 起 + tool——工具结果
// 回传消息，携带 toolCallId/toolName；方言翻译在各协议层）。原三态注释：
//（Anthropic/Gemini 的 role 映射——assistant→model、system 提顶层——在各协议层做）。
// 2026-08-31 附件上传：+ images 可选字段（仅 user 消息携带）——协议方言翻译
//（OpenAI image_url / Responses input_image / Anthropic image block / Gemini
// inline_data）在 RequestCompose 各 compose 函数；assistant/system 消息恒无 images
//（历史轮图片不重发——附件仅随当前轮发送，语义见 AttachmentUtil 头注释）。
// 2026-09-01 回传历史思考：+ reasoning 可选字段（仅 assistant 消息携带）——历史思考块
// 经 ChatSendCtrl 组装回 assistant 消息；方言落点 = OpenAI chat 顶层 reasoning_content /
// Responses reasoning 字符串（官方 Responses 输入并非官方规范字段——第三方兼容面窄，
// 以官方文档为主——落点见 RequestCompose）；★ Anthropic/Gemini 不回传（Anthropic 思考
// 块须 signature 保真——aicol 尚未提取存储 signature；Gemini thought 段回传非官方要求，
// 维持现状零回归）
export interface AiChatMessage {
  role: string;
  content: string;
  images?: AiImagePart[];
  reasoning?: string;
  // 工具调用（2026-09-02）：toolCalls 仅 assistant 携带（历史轮工具调用回传——四协议
  // 方言落点在 RequestCompose）；role='tool' 结果消息携带 toolCallId（+toolName，
  // Gemini functionResponse 配对必需）——单一定义在 RequestCompose.AiToolCall
  toolCalls?: AiToolCall[];
  toolCallId?: string;
  toolName?: string;
  // Responses reasoning 输出项（2026-09-06 Responses 修复）：仅 assistant 携带、且仅
  // OpenAI 官方端点工具轮产生（捕获链 = SseParser parseResponsesPayload → ChatSendCtrl
  // 轮内累积 → 本字段 → composeOpenAiResponsesBody 回传，保真要求见 AiReasoningItem 注释）；
  // 跨发送历史重建不持久化（DB 无列——回放轮不带，OpenAI 官方跨发送工具轮回传缺口登记
  // BLOCKED 独立专项）
  reasoningItems?: AiReasoningItem[];
}

// 图片部件（多模态请求侧）：mimeType 如 'image/jpeg'；data 为裸 base64（无 data: 前缀，
// 协议方言前缀在 compose 层拼——四协议前缀形态各不同）
export interface AiImagePart {
  mimeType: string;
  data: string;
}

// chat/completions 请求体（ArkTS 严格模式：对象字面量必须挂显式接口——坑 59 ①）
export interface ChatCompletionRequest {
  model: string;
  messages: AiChatMessage[];
  stream: boolean;
}

// ── 流式回调与流接口（三协议共用；原 OpenAiCompatApi 导出处于 2026-08-30 三协议改造
// 时收敛至此——工厂 ChatStreamFactory 与 ChatSendCtrl 消费）──

// onError 第二参 status = HTTP 状态码（响应码已落定时的失败路径透出；-1 = 网络错误/
// 手动停止等无状态码场景）——Key 池失败切换据此判 401/403/429。
// ★ 2026-09-22 第三参 sawContent（聊天网络层失败自动重试笔）= **本流是否已收到过真正上屏的
// 内容**（正文/思考/工具调用四选一，即交付给 onDelta 的那一类；空保活帧与纯 usage 帧不算）。
// 与 ChatStreamBase.sawValidFrame 的区别 = 后者含空帧（不可拿它判零产出）。消费方 =
// ChatSendCtrl 自动重试判据（-1 且本流零产出才退避重发，见 ChatAutoRetryCtrl）。
// ★ 2026-09-22 自检轮改判：**-1 的语义收窄为「传输层失败」**（连接失败 / 手动停止），
// 不再含「流中错误帧」——后者有专属哨兵 STREAM_ERROR_STATUS（定义见下方常量），因为
// 流中错误帧落在「HTTP 200 已建流、错误以协议事件帧送达」上，**不是网络原因**（Anthropic
// 的 overloaded/rate_limit、Responses 的 error 事件都经该帧到达）。判据若把 -1 等价于
// 传输层失败就会误收这类协议层错误（重发 3 次 + 显示「网络异常」），与「不做 429·5xx
// 自动重试」的红线相抵。
// onDone（2026-09-06 用量采集改签名）：usage = 本流归一用量（流内多帧已 take-max 合并；
// null = 本流未收到任何 usage 帧——含全部失败路径，fail 不带 usage），durationMs =
// 本流 start→onDone 墙钟毫秒（纯流式时间，工具执行等待不在流内天然不计）——跨流聚合
// 在 ChatSendCtrl 轮次累积器（求和口径）。
// ★ 2026-09-23 输出上限治理笔 2 第三参 truncated = 本流是否被输出上限截断（思考 token 与
// 正文共享同一预算打满即真，四协议标记位置见 SseParser.SseDelta.truncated）。口径两条：
// ① 只在本流**正常完成**的路径带出——fail 路径无 onDone，天然不传（截断是模型把上限烧完
// 后的正常收尾，不是错误）；② 消费方按「末流胜出」轮级累积（工具轮多流时以最终呈现的
// 那条流为准，见 ChatUsageRoundCtrl 域头注释）。
// ★ 2026-09-23 首字耗时笔：第四参 firstTokenMs = 本流首个**正文或思考**增量到达时刻 −
// start 锚的墙钟毫秒（0 = 本流未产出过正文/思考增量——空响应 / 纯工具调用轮 / 失败流）。
// 口径三条：①零点与 durationMs 同源 ⇒ 恒 ≤ durationMs；②工具调用帧与 reasoning item 帧
// 不算「字」（不参与打戳）；③**常开**——不随请求日志开关，与 durationMs 同为体感口径
//（请求日志那枚「首字节」是网络诊断口径、只在开关打开时测，两者勿混，见 ChatStreamBase
// 字段注释）。消费方 = ChatSendCtrl.onStreamDone（轮级取**首个非 0 值**——用户第一次看到字
// 的那一刻即定格，与 truncated 的末流胜出相反），落库进 token_usage_events.firstTokenMs。
export interface AiStreamHandlers {
  onDelta: (delta: SseDelta) => void;
  onDone: (usage: AiUsageDelta | null, durationMs: number, truncated: boolean,
    firstTokenMs: number) => void;
  onError: (message: string, status: number, sawContent: boolean) => void;
}

// 流中错误帧的 onError 状态码哨兵（2026-09-22 自检轮新增）：HTTP 200 已建流、错误以协议
// 事件帧送达（Anthropic type:'error' / Responses error 事件）——此刻响应码尚未落定（唯一
// 写点是流末才 resolve 的 requestInStream Promise，坑19 机制），透 -1 会被「传输层失败」
// 判据误收。同族语义：负值 = 非 HTTP 码；-1 = 传输层无码，-2 = 协议层错误帧。消费方判据
// 只认 -1 为传输层失败 ⇒ 本值天然不参与网络自动重试。唯一产出点 = ChatStreamBase.failStream
export const STREAM_ERROR_STATUS: number = -2;

// 协议流统一接口（OpenAiChatStream/AnthropicChatStream/GeminiChatStream 实现契约）；
// thinking = 思考档位（'' = 不传，方言落点见各协议流 requestBody → RequestCompose）；
// sampling = 助手高级设定采样参数（null = 未配置 = 不带任何采样字段，现状零回归；
// 四协议方言落点在 RequestCompose.composeXXX）
// ★ 2026-09-23 请求日志笔加第 7 参 source = 请求日志的用途标签（省略 = '聊天'，界面行为零
// 变化）——连接能力三项测试的 T2 / T3 流式探针复用同一条流式链，靠该形参把自己与正常发送
// 区分开；标签消费方 = ReqLog 条目列表（默认排序与筛选用途见 common/ReqLog.ets）
export interface ChatStream {
  start(conn: AiConnection, apiKey: string, messages: AiChatMessage[], thinking: string,
    sampling: SamplingParams | null, tools?: AiToolDef[], source?: string): void;
  abort(): void;
  disposeSilent(): void;
}

// 待发附件（2026-08-29 对话页 UI 对齐任务 2 自 dshinhm KimiPromptTypes 同名接口随迁；
// 2026-08-31 附件上传接线）：fileId = 本地引用键（缩略图仓库键 + 唯一序号），localPath =
// 沙箱缓存副本绝对路径（发送时读副本编码，用后即删——不驻留）；kind 事实值
// 'image' | 'text' | 'doc'（classifyByName 全集；video 不支持——非图片非文本非文档在
// 选择入口即拦截。原「'file'」为失效值域，2026-09-13 全码优化笔1 对照真源核正）。
// ★ 2026-09-03 第三批②文档解析扩字段（doc 专属，其余 kind 恒 undefined）：
// parseState 解析态机（idle/parsing/done/failed/toolarge——发送阻断判定见
// DocumentParse.docBlockingReason）/ parsedText 解析产出（随发送进协议 content）/ 
// parseError 失败原因（阻断提示呈报）/ parseTruncated 截断标志（超 120K 字符抽取上限）。
// ★ 2026-09-15 附件 PDF 页渲染一期：pageImages 页图数组（doc 专属，仅扫描件 PDF 渲染产出；
// 元素 = 页序、mime 恒 DocumentParse.PAGE_IMAGE_MIME——data 为**裸 base64**，与图片附件
// 同构，协议层零改动；undefined/空 = 无页图）+ pageCount 全量页数（PDF 专属；页图超上限时
// 供「共 N 页」文案与协议说明行用——非 PDF/未解析恒 undefined）。发送时页图并入
// AttachmentPayload.images 走视觉通道；不落盘、不入库、不随历史轮重发（附件本体仅随当前轮）
// ★ 2026-09-15 附件 OCR 二期：ocrText 识别产出（图片附件与扫描件 PDF 页图两路共用；
// 主模型无视觉时随发送进 protocolAppend——AttachmentUtil.appendOcrBlock 块形，不落盘不
// 入库不随历史轮重发）+ ocrState 识别态机（'idle' 已入列未识别 / 'running' 识别中——
// 发送阻断见 AttachmentUtil.attachBlockingReason / 'done' 成功 / 'failed' 失败——不阻断
// 发送，走一期行为）。引擎与排程在 common/OcrEngine.ets（识别无论成败/超时/异常必落
// done|failed 终态——终态兜底红线，见任务书-附件OCR链路 §3.5）
export interface PendingAttachment {
  fileId: string;
  name: string;
  mediaType: string;
  size: number;
  kind: string; // 'image' | 'text' | 'doc'（AttachmentUtil.classifyByName 全集；'' = 不支持已拦）
  localPath: string;
  parseState?: string;
  parsedText?: string;
  parseError?: string;
  parseTruncated?: boolean;
  pageImages?: AiImagePart[];
  pageCount?: number;
  ocrText?: string;
  ocrState?: string;
}
