// AI 协议层公共类型：连接配置与 chat/completions 请求侧模型。分层约定：本文件属
// common/providers（最底层），只许被 components/pages 单向 import，禁止反向 import 上层。
// SSE 帧解析相关类型在 SseParser.ets（该文件零 import，保 node 断言脚本同源直跑）。
// 协议常量表（全工程禁裸字符串协议值——DB/工厂/UI/解析一律引本表）、自定义请求头模型、
// 流式回调与流接口（三协议共用）收敛在此。
import { SseDelta, AiUsageDelta, AiReasoningItem } from './SseParser';
// 采样参数单一来源在 RequestCompose（零 import 约束 + ArkTS 禁结构化类型——双接口同构
// 互传即编译错）：定义在那边 export、此处 re-export 供全工程从 AiTypes 门面消费（无循环依赖）
import { SamplingParams, AiToolDef, AiToolCall } from './RequestCompose';
// 模型能力注册表门面：单一定义在 ModelRegistry（零 import 纯逻辑域 + sse-assert 复制直跑），
// 本处 re-export 供全工程从 AiTypes 消费（SamplingParams 同款姿势）：能力派生查询 / 思考
// 策略解析 / 思考开关方言画像判定 / 思考菜单选项集派生 / effectiveCaps 派生覆盖语义 /
// 上下文窗口参考值查询（lookupContextBaseline——消费方 = ProviderDb.effectiveContextWindow
// 与编辑模型页，禁各处直 import 注册表）。值域与语义见 ModelRegistry 头注释。
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

// ── 协议能力表（第一版只声明已实测能力；能力键——system = 系统提示词注入落点〔openai
// 原样进 messages / anthropic 提顶层 system / gemini 提 systemInstruction / responses 落
// instructions，组装见 RequestCompose〕；reason = 思考增量解析；vision = 图片多模态〔真机
// 验收待装机，见 BLOCKED.md〕；thinking = 思考档位〔四协议方言已落 RequestCompose〕；
// tools = 工具调用。openaiResponses 键是接口形态值域非协议族，仅 OpenAI 官方端点支持
//（第三方「OpenAI 兼容」中转不实现 /v1/responses）。docs/协议能力支持矩阵.md 为纯展示，
// 唯一真实源在此。ArkTS 禁无显式接口的对象字面量挂 Record——坑59① 同族，故以显式接口承载）──
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
// 协议不支持 = 不传零回归）；openai 族按接口形态分流到 openaiResponses 键
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

// 思考档位菜单选项集全量缺省（''=默认不传 / off=关闭思考〔开关方言画像域暴露，判定见
// supportsThinkingOff〕/ low / high / max；Gemini 预算映射在 RequestCompose.geminiThinkingBudget；
// 菜单序 off 紧挨默认 = 思考开关语义分组）。★ 本常量 = 「未命中画像行的连接」的缺省全集，
// 画像行显式 menuOptions 时收窄（派生见 ModelRegistry.thinkingOptionsFor）；★ 并非「任意
// 模型都合法」——原「三档枚举四协议官方均合法」已证伪（GLM-4.5/4.6 官方无 reasoning_effort、
// GLM-5.3 仅收 max/high/low 等），逐模型的合法集与等价冗余一律查画像行（判据见
// ModelRegistry 的 menuOptions 字段注释），勿以本常量为合法性依据
export const THINKING_OPTIONS: string[] = ['', 'off', 'low', 'high', 'max'];

// ── 「关闭思考」域判定 ──
// 判定单一来源 = ModelRegistry 开关画像（baseUrl + 模型 id 二维行命中）：关闭思考 = 服务商
// 官方规格差异项——DeepSeek 官方（thinking{type:enabled/disabled} / reasoning{effort:none}）
// 与 GLM/Kimi 官方（openai 形态 thinking{type:disabled} 同形）；GLM 强制系与 kimi-k3 /
// k2.7-code 等恒思考关不掉 → 行级 supportOff=false 摘档（实测实锤：K3 不收 thinking 参数
// 静默忽略、k2.7-code 传 disabled 必 400）；OpenAI/Anthropic 官方与 Gemini 原生均无（传
// none 有 400 实锤）。「支持非思考的模型」= 画像内的官方域 + 模型，非逐厂商散落特判——将来
// 扩展生态 = 画像表加行，勿在业务层散落特判。原 THINKING_OFF_DOMAINS 域名表已退役（画像行
// 等价承接，实现改查 supportsDeepSeekProfile〔历史命名，语义 = 开关方言画像命中且行级未禁
// off〕，等价性由 sse-assert 断言组钉死）。modelId 缺省 '' = 模型级行不命中，退化 provider
// 级旧行为
export function supportsThinkingOff(baseUrl: string, modelId: string = ''): boolean {
  return supportsDeepSeekProfile(baseUrl, modelId);
}

// 连接「关闭思考」生效判定：协议流 requestBody offEnabled 实参与 ChatSendCtrl 发送守卫的
// 单一判定源。首选 conn.reasoningOffSupported（resolveActiveConnection 唯一填充 = 画像行
// 模型级判定，「与协议形态无关」——anthropic 形态 DeepSeek 的 reasoning{effort:none} 同样
// 支持 off）；undefined（解析链外构造的连接）回落 supportsThinkingOff(baseUrl, model) 二维
// 判定。旧快速分支（strategy === deepseek_thinking 直返 true）已退役——模型级禁 off 行
//（GLM 强制系）strategy 仍标 deepseek_thinking，直返会把禁 off 行放行 = 回归
export function connectionOffEnabled(conn: AiConnection): boolean {
  if (conn.reasoningOffSupported !== undefined) {
    return conn.reasoningOffSupported;
  }
  return supportsThinkingOff(conn.baseUrl, conn.model);
}

// 思考档位合法性归一（三处消费同款逻辑提取，P2-4——ChatPage 回退 / 绑定守卫 / 发送双保险）：
// '' 恒合法；'off' 须 offSupported 且选项集含 off（行级禁用与收窄同源）；其余档位看选项集
// 包含（画像行收窄后存量非法档位归 '' = 默认不传，静默零字段——防「收窄前选中值 + 收窄后
// 漏网」）
export function legalThinkingTier(tier: string, offSupported: boolean, options: string[]): string {
  if (tier === '') {
    return '';
  }
  if (tier === 'off') {
    return offSupported && options.includes('off') ? 'off' : '';
  }
  return options.includes(tier) ? tier : '';
}

// OpenAI 官方域判定：baseUrl 以 https://api.openai.com 开头 = 官方端点。消费面 = Responses
// 工具轮 reasoning item 保真链（include: ['reasoning.encrypted_content'] 请求 + 捕获回传）
// ——该 include 仅官方端点规格内（第三方网关/国产无状态实现不支持，DeepSeek 文档明示不
// 支持）。★ scheme 锚定 + 域边界非子串包含：`xx-api.openai.com.proxy.xx` 类前缀代理域与
// `https://api.openai.com.evil.com` 类后缀伪装域都不得误命中（仅查 startsWith 会被同前缀
// 异域串误判官方）；误发 include 给不支持的中转可 400 且 body_overrides 只能覆盖键不能删键
// 无自救通道；漏判方向安全（不发 include = 维持现状零回归）
export function isOfficialOpenAiBaseUrl(baseUrl: string): boolean {
  return baseUrl === 'https://api.openai.com' || baseUrl.startsWith('https://api.openai.com/');
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

// ── 助手高级设定参数（DB v11 assistants.advancedParams 列）──
// SamplingParams（发送侧采样参数——compose 消费，四协议方言落点在 RequestCompose；全
// 可选 = 关闭该项不发送，请求体零回归）**定义在 RequestCompose 并由本文件 re-export**。
// maxOutput 三态：undefined = 未配置（anthropic 维持 8192 现状，其余协议不发字段）/ 0 =
// 显式不限制（anthropic 兜底 131072，其余协议不发字段）/ 正数 = 按值发送

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
// 不落键；全默认〔六键全 undefined〕回 '' = 库列默认形态 = 未配置，anthropic max_tokens 走
// 8192 现状——「显式 0」与「未配置」靠键存在性区分，UI 层决定键集合：上下文页保存恒写
// contextCount/maxOutput 两键）
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

// 连接配置（M1 拍板：聊天页内置极简「连接设置」，运行时写入 Asset，不进代码/git）。
// protocol（协议分发）/ headers（自定义请求头）/ providerId（key 池归属——发送编排按池
// 轮询取钥）随多 Key 池 + 三协议扩展加入；apiKey 字段退役——密钥改为发送时经
// ChatStream.start(conn, apiKey, messages) 按次注入（获取模型/余额的兜底取钥走池首）；
// endpoint = OpenAI 族接口形态（工厂按 protocol+endpoint 分发，a/g 恒 ENDPOINT_CHAT）
export interface AiConnection {
  baseUrl: string; // 如 https://api.deepseek.com/v1（末尾斜杠容忍，协议层归一化）
  model: string;
  protocol: string; // PROTOCOL_VALUES 之一（见常量表）
  endpoint: string; // ENDPOINT_VALUES 之一（仅 openai 有意义；默认 chat）
  headers: HeaderPair[]; // 自定义请求头（空数组 = 无）
  providerId: string; // 所属服务商（key 池轮询/失败切换归属；遗留迁移路径可 ''）
  // Anthropic 提示缓存（DB v12 providers 两列随解析填充；undefined = 关 = composeAnthropicBody
  // 不带 cache 参零回归；仅 anthropic 协议消费——AnthropicChatStream.requestBody，TTL 值域
  // '5m' | '1h'）
  promptCacheEnabled?: boolean;
  promptCacheTtl?: string;
  // 取钥方式（DB v32 providers.key_pick_mode；值域 KEY_PICK_ROTATE 'rotate' 默认 |
  // KEY_PICK_RANDOM 'random'，常量表在 store/ProviderKeyDb.ets）。消费方唯一 =
  // ChatSendCtrl 轮次启动的起始位选择；undefined = 解析链外构造的连接（按 rotate 兜底）。
  // 协议层零消费（compose/stream 不看本字段，请求字节与升级前逐字节一致）
  keyPickMode?: string;
  // 自定义 Body 覆盖（DB v13 providers.body_overrides；空数组 = 无覆盖 = 请求体逐字节零
  // 回归）。元素复用 HeaderPair 形态：k = 请求体顶层键名，v = 合法 JSON 值文本（入库侧已
  // 校验）；发送时 ChatStreamBase.start 统一 merge 到根对象——协议无关单一落点，同键覆盖
  // 内置键（与 headers 覆盖语义一致拍板）
  bodyOverrides?: HeaderPair[];
  // 思考策略：resolveActiveConnection 唯一填充点（协议+接口形态+baseUrl+模型 id 二维画像
  // 解析，ModelRegistry.resolveReasoningStrategy——DB 无列不落库）。值域 'none' |
  // 'openai_effort' | 'deepseek_thinking' | 'anthropic_effort' | 'google_thinking'
  //（STRATEGY_* 常量）。本期消费 = off 生效判定（connectionOffEnabled）；将来「策略 + 档位
  // → 方言」策略化 compose 在此字段扩展。undefined = 解析链外构造（兜底 supportsThinkingOff）
  reasoningStrategy?: string;
  // 「关闭思考」支持：与 reasoningStrategy 同填充点同源判定
  //（ModelRegistry.supportsDeepSeekProfile——模型级禁 off 行 = false）。消费 =
  // connectionOffEnabled 首选 / ChatPage offOk 广播；undefined 同上防御态回落
  reasoningOffSupported?: boolean;
  // 思考菜单选项集（同填充点，ModelRegistry.thinkingOptionsFor 派生——画像行 menuOptions
  // 收窄或全量缺省）。消费 = ChatPage chip 菜单选项 / ChatSendCtrl 发送档位合法性双保险
  reasoningMenuOptions?: string[];
  // 生效能力串（随连接走的 caps 快照）：resolveActiveConnection 唯一填充点，与
  // ActiveConnectionInfo.caps 同源同值一次计算（effectiveCaps：用户改过则原样、否则按模型
  // 名派生）。消费 = ChatSendCtrl 工具执行上下文 hasVision 快照（发送链视觉门控同判据）；
  // undefined = 解析链外构造（按无能力兜底）。协议层零消费，请求字节零变化
  caps?: string;
}

// role 事实值 'system' | 'user' | 'assistant' | 'tool'（tool = 工具结果回传消息，携带
// toolCallId/toolName；Anthropic/Gemini 的 role 映射——assistant→model、system 提顶层——
// 在各协议层做）。images 仅 user 消息携带（附件仅随当前轮发送，历史轮图片不重发，语义见
// AttachmentUtil 头注释）。reasoning 仅 assistant 携带（历史思考块经 ChatSendCtrl 组装回传；
// 方言落点 = OpenAI chat reasoning_content / Responses reasoning 字符串——后者非官方规范
// 字段、第三方兼容面窄；★ Anthropic/Gemini 不回传——Anthropic 思考块须 signature 保真
// 尚未提取存储、Gemini thought 段回传非官方要求，维持现状零回归）
export interface AiChatMessage {
  role: string;
  content: string;
  // 续写前缀标记（二期 S4 #10）：仅 OpenAI 兼容 CC 末条 assistant 携带——官方
  // chat_prefix_completion 要求 role=assistant + prefix:true + base_url 带 /beta；
  // 其余协议/其余位置不消费（compose 三方言显式忽略 = 零回归）
  prefix?: boolean;
  // user 消息附件；role='tool' 亦携带工具结果附件（mime 值域 image/* 与 application/pdf，
  // 消费方 = RequestCompose 四 compose 的工具行附件分派）
  images?: AiImagePart[];
  reasoning?: string;
  // 工具调用：toolCalls 仅 assistant 携带（历史轮回传，方言落点在 RequestCompose）；
  // role='tool' 结果消息携带 toolCallId（+toolName，Gemini functionResponse 配对必需）
  toolCalls?: AiToolCall[];
  toolCallId?: string;
  toolName?: string;
  // Responses reasoning 输出项：仅 assistant 携带、且仅 OpenAI 官方端点工具轮产生（捕获链
  // = SseParser parseResponsesPayload → ChatSendCtrl 轮内累积 → 本字段 →
  // composeOpenAiResponsesBody 回传，保真要求见 AiReasoningItem 注释）；跨发送历史重建不
  // 持久化（DB 无列——回放轮不带，跨发送工具轮回传缺口登记 BLOCKED 独立专项）
  reasoningItems?: AiReasoningItem[];
  // DeepSeek 服务端工具回传串（DS 全家桶接入批 S2，2026-11-14）：仅 assistant 携带——
  // 历史轮官方档回传料（ChatMessage.serverToolsJson 列值直读挂值，live 轮由流域
  // serverToolsFull 快照随行），消费方 = composeOpenAiBody 仅官方档轮输出 server_tool_calls。
  // 原样 JSON 串透传禁截断（任务书 §5 回传保真）
  serverToolCallsJson?: string;
  // volatile 时间变量标记：提示词注入内容含 {{time}}/{{datetime}} 时为 true——**仅发送
  // 组装期内存字段，序列化层不输出**（各协议 compose 显式构造请求项，天然不带出）；消费方
  // = composeAnthropicBody 的缓存断点降级。生成点 ChatPromptState.applyVariables（替换前
  // 检测——替换后 token 文本已消失无从检测），随 composeSendMessages 产物透传
  volatileTime?: boolean;
  // 波动 system 尾段字符数：>0 = content 末尾 N 字符属波动尾段（知识命中块——逐轮随对话
  // 内容变），仅 composeAnthropicBody 消费（system 拆稳定块 + 尾块，缓存断点只挂稳定块）；
  // 0/缺省 = 无尾段。**仅发送组装期内存字段，序列化层不输出**；设置点唯一 =
  // appendSystemKnowledge，merge 重建与两 append 重建随行带（同 volatileTime 防丢族）
  systemTailChars?: number;
  // 消息创建时刻：来源 = messages.createdAt 库列（ChatMessage.createdAt 回放/落库回填）经
  // ChatHistoryBuilder 映射透传，供 RequestInject.injectTimeReminders 的间隔判定；**序列化
  // 层不输出**。仅 user/assistant 行携带；undefined = 无值可判（fail-open）
  createdAt?: number;
}

// 图片部件（多模态请求侧）：mimeType 如 'image/jpeg'；data 为裸 base64（无 data: 前缀，
// 协议方言前缀在 compose 层拼——四协议前缀形态各不同）
export interface AiImagePart {
  mimeType: string;
  data: string;
  // DeepSeek 文档服务端解析件标记（DS 全家桶接入批 S4 落生产链——本批 S2 提前落位可选位，
  // 供 collectTools 的「本轮 user 是否带服务端解析件」提示参防御扫描）：非空 = 该部件是
  // 已上传取回 file_id 的服务端解析件（S4 上传链写入；S2 期无生产者恒 undefined = 判 false）。
  // 消费面 = ChatRoundAssembly.assembleRound / ChatContextUsage.computeLive 扫描 + S4 的
  // composeOpenAiBody file 部件分流
  remoteFileId?: string;
  // 附件行身份（DS 全家桶二期 S4 #11 file_id 自愈）：= PendingAttachment.fileId（message_
  // attachments.id）。file_id 失效时按它把重传回执的新 id 精确写回对应部件（多图轮不串位）。
  // 历史回放构造的部件无此值（消费方必须按空值跳过，禁按位置猜）
  attachId?: string;
}

// chat/completions 请求体（ArkTS 严格模式：对象字面量必须挂显式接口——坑 59 ①）
export interface ChatCompletionRequest {
  model: string;
  messages: AiChatMessage[];
  stream: boolean;
}

// ── 流式回调与流接口（三协议共用；原 OpenAiCompatApi 导出处于 2026-08-30 三协议改造
// 时收敛至此——工厂 ChatStreamFactory 与 ChatSendCtrl 消费）──

// onError 第二参 status = HTTP 状态码（-1 = 传输层失败/手动停止等无码场景，-2/-4 = 专属
// 哨兵见下方两常量）——Key 池失败切换据此判 401/403/429。★ -1 的语义收窄为「传输层失败」
//（连接失败 / 手动停止），不含「流中错误帧」——后者走 STREAM_ERROR_STATUS 哨兵：HTTP 200
// 已建流、错误以协议事件帧送达（Anthropic 的 overloaded/rate_limit、Responses 的 error
// 事件），不是传输层失败，透 -1 会误归因。第三参 sawContent = 本流是否已收到过**真正上屏
// 的内容**（正文/思考/工具调用四选一；空保活帧与纯 usage 帧不算；与 ChatStreamBase.
// sawValidFrame 的区别 = 后者含空帧，不可拿它判零产出）——消费方 = ChatSendCtrl 自动重试
// 判据（重试面 = -1 ∪ RETRYABLE_5XX ∪ 瞬态文案词表，且本流零产出才退避重发，见
// ChatAutoRetryCtrl）。
// onDone：usage = 本流归一用量（流内多帧已 take-max 合并；null = 未收到任何 usage 帧——
// 含全部失败路径，fail 不带 usage）；durationMs = 本流 start→onDone 墙钟毫秒（纯流式
// 时间，工具执行等待不在流内）；truncated = 本流是否被输出上限截断（四协议标记位置见
// SseParser.SseDelta.truncated）——只在本流**正常完成**的路径带出（截断是模型把上限烧完的
// 正常收尾不是错误），消费方按「末流胜出」轮级累积（见 ChatUsageRoundCtrl）；firstTokenMs
// = 首个**正文或思考**增量到达时刻 − start 锚的墙钟毫秒（0 = 未产出；只认正文/思考，工具
// 帧与 reasoning item 帧不算「字」；**常开**不随请求日志开关——与日志「首字节」是两个口径，
// 见 ChatStreamBase 字段注释；轮级取**首个非 0 值**，与 truncated 的末流胜出相反），落库进
// token_usage_events.firstTokenMs。
export interface AiStreamHandlers {
  onDelta: (delta: SseDelta) => void;
  onDone: (usage: AiUsageDelta | null, durationMs: number, truncated: boolean,
    firstTokenMs: number) => void;
  onError: (message: string, status: number, sawContent: boolean) => void;
}

// 流中错误帧的 onError 状态码哨兵：HTTP 200 已建流、错误以协议事件帧送达（Anthropic
// type:'error' / Responses error 事件）——此刻响应码尚未落定（唯一写点 = 流末才 resolve 的
// requestInStream Promise，坑19 机制），透 -1 会被「传输层失败」判据误收。同族语义：负值 =
// 非 HTTP 码；-1 = 传输层无码，-2 = 协议层错误帧，-4 = 本端组装失败（-3 已被 ReqLog 取消
// 哨兵占用，日志域专用）。自动重试的状态码面不认本值（overloaded 类错误帧由瞬态文案面按
// 词表另行接管）；notice 跳转分类同样不含本值 = 纯文本不可点。唯一产出点 =
// ChatStreamBase.failStream
export const STREAM_ERROR_STATUS: number = -2;

// 请求组装失败的 onError 状态码哨兵：start 组装段守卫捕获的异常（协议钩子 / 自定义头 /
// 端点拼接等本端问题）此前透 -1，notice 分类会误挂跳网络设置页动作——组装失败不是网络
// 故障，独立哨兵使其既不进自动重试面也不挂跳转动作（同 STREAM_ERROR_STATUS 先例）。唯一
// 产出点 = ChatStreamBase.start 组装段守卫；错误文案出自本端固定句式与 describeNetError，
// 不含瞬态词，不会被自动重试的文案面误收
export const ASSEMBLY_FAIL_STATUS: number = -4;

// DS 扩展字段（二期 S2；ChatStreamBase.DsStreamExtras 的接口同形镜像——AiTypes 是底层类型
// 叶子，禁反向 import ChatStreamBase 形成环；两处字段逐一对齐由断言钉守）
export interface DsStreamExtrasLike {
  title: boolean;
  safety: boolean;
}

// 协议流统一接口（OpenAiChatStream/AnthropicChatStream/GeminiChatStream 实现契约）；
// thinking = 思考档位（'' = 不传，方言落点见各协议流 requestBody → RequestCompose）；
// sampling = 助手高级设定采样参数（null = 未配置 = 不带任何采样字段，零回归）。第 7 参
// source = 请求日志用途标签（省略 = '聊天'）——连接能力测试 T2/T3 流式探针复用同一条流式
// 链，靠该形参与正常发送区分；标签消费方 = ReqLog 条目列表
export interface ChatStream {
  // 第 8 参 dsExtras = DS 扩展字段两布尔（二期 S2；省略 = null = 既有调用零变化）——形态定义
  // 在 ChatStreamBase.DsStreamExtras（此处只留 Object 形状以避 providers 内互相引接口）
  start(conn: AiConnection, apiKey: string, messages: AiChatMessage[], thinking: string,
    sampling: SamplingParams | null, tools?: AiToolDef[], source?: string,
    dsExtras?: DsStreamExtrasLike | null): void;
  abort(): void;
  disposeSilent(): void;
}

// 待发附件：fileId = 本地引用键（缩略图仓库键 + 唯一序号），localPath = 沙箱缓存副本绝对
// 路径（发送时读副本编码，用后即删——不驻留），kind 事实值 'image' | 'text' | 'doc'
//（classifyByName 全集；video 不支持——非图片非文本非文档在选择入口即拦；原 'file' 为
// 失效值域已核正）。
// ★ doc 专属解析字段（其余 kind 恒 undefined）：parseState 解析态机（idle/parsing/done/
// failed/toolarge——发送阻断判定见 DocumentParse.docBlockingReason）/ parsedText 解析产出
//（随发送进协议 content）/ parseError 失败原因 / parseTruncated 截断标志（超 120K 字符
// 抽取上限）。
// ★ PDF 页渲染一期：pageImages 页图数组（仅扫描件 PDF 渲染产出，元素 = 页序、mime 恒
// DocumentParse.PAGE_IMAGE_MIME，data 为**裸 base64** 与图片附件同构，协议层零改动；
// undefined/空 = 无页图）+ pageCount 全量页数（PDF 专属；页图超上限时供「共 N 页」文案与
// 协议说明行用）。发送时页图并入 AttachmentPayload.images 走视觉通道；不落盘、不入库、不随
// 历史轮重发（附件本体仅随当前轮）。
// ★ OCR 二期：ocrText 识别产出（图片附件与扫描件 PDF 页图两路共用；主模型无视觉时随发送
// 进 protocolAppend——AttachmentUtil.appendOcrBlock 块形，不落盘不入库不随历史轮重发）+
// ocrState 识别态机（'idle' 已入列未识别 / 'running' 识别中——发送阻断见
// AttachmentUtil.attachBlockingReason / 'done' 成功 / 'failed' 失败——不阻断发送）。引擎与
// 排程在 common/OcrEngine.ets（识别无论成败/超时/异常必落 done|failed 终态——兜底红线）
// ★ 重发大文档叠加式降级（2026-10-31）：guideWorkspacePath 非空 = 该件的全文副本已在工作区，
// 发送时协议侧只组「开头部分 + 工作区路径指引」（AttachmentUtil.attachTextBlocksOf 指引支），
// 不再是全量内联截断文本——叠加式：头部分正文照留，只把「读全文」这件事交给工作区工具。
// 只有重发入列链（addCopiedFromFile）的截断件会置位，普通选择器/粘贴/分享件恒 undefined。
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
  // 工作区全文路径（文件工作区相对路径；仅重发入列链的截断件置位——见类型头注释）
  guideWorkspacePath?: string;
  // DeepSeek 文档服务端解析件标记（DS 全家桶接入批 S4 落生产链——本批 S2 提前落位可选位，
  // 供面板活算的「待发附件是否带服务端解析件」提示参防御扫描）：非空 = 该件已上传取回
  // file_id（S4 上传链写入；S2 期无生产者恒 undefined = 判 false）；非 DS 连接或开关关恒
  // undefined（本地解析路径）
  remoteFileId?: string;
  // 官方档上传中标记（附件官方标记笔）：true = 该件正走 DS 服务端上传链（入列置位；done/
  // failed 终态清除）——让附件条副行把「上传中」与本地解析的「解析中」区分开；值变化与
  // parseState 严格同拍（parsing→done/failed），键纪律由附件条键的 parseState 段承接
  remotePending?: boolean;
}
