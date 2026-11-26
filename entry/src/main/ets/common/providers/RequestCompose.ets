// 请求体组装纯函数——四协议 requestBody 方言单一落点（样本即规格 = scripts/sse-assert.mjs
// 断言组，行为逐字节一致）。零 import 约束：断言脚本复制本文件为 .ts 直跑（AiTypes 反向
// 依赖 SseParser，引入即破零 import），类型自持本地同构接口。适配口径 = 只适配协议规格
// 不逐厂商特判；注入组装域（composeSendMessages / mergeConsecutiveSameRole 等）已拆
// RequestInject.ets（⑭⑮ 断言组随迁同源直跑）。

// ▲ 附件（多模态）：ComposeChatMessage + images（仅 user 消息）。四协议 content part
// 方言：OpenAI chat = image_url{url:dataURI} / Responses = input_image 直串 dataURI /
// Anthropic = image{source{base64}} / Gemini = inline_data{mime_type,data} 蛇形键；无
// images 路径逐字节不变（⑰ 组断言双向保护）。

// ▲ 思考档位：thinking 参 '' = 不传逐字节回归，非空 = 各协议方言落点：OpenAI chat 顶层
// reasoning_effort / Responses 顶层 reasoning{effort} / Anthropic 顶层 output_config
// {effort}（现行规格，旧 thinking.budget_tokens 新模型已弃用）/ Gemini
// generationConfig.thinkingConfig{thinkingBudget,includeThoughts}（thinkingLevel 仅
// Gemini 3+ 且旧模型传之报错，不用）。档位 low/high/max 三协议族均官方合法透传；Gemini
// 预算映射 geminiThinkingBudget。

// ▲ 回传历史思考（reasoning 仅 assistant）：仅 OpenAI chat / Responses 两路径回传——
// DeepSeek 等 OpenAI 兼容思考模式事实标准（官方「思考模式必须回传，无工具轮次回传无害」）。
// 未回传原因：Anthropic（thinking 块须 signature 保真，未提取存储，官方 400 实锤）、
// Gemini（thought 段回传非官方要求）——均维持现状，signature 保真提取存储需独立专项。
// ★ 2026-09-17 回传缺陷修复（工具轮续轮必 400「reasoning_text must be passed back」，
// 两处补齐）：① Responses 补明文回传——第三方端点只支持明文 content（id+encrypted_content
// 恒不参与），捕获项缺席时挂明文 reasoning item（content:[{type:'reasoning_text',text}]），
// 序 = reasoning item 先于 message/function_call（服务端实测校验序）；② 思考会话带工具轮
// 而思考文本空时补单空格占位（缺键与空串都被判「未回传」）。零思考会话恒不产额外字段。

// ▲ 采样参数（sampling null/缺省 = 逐字节零回归；锁参新模型发采样参数可能被拒，错误体
// 走既有回显链）。方言落点：openai chat 顶层 temperature / top_p / 双 penalty /
// max_tokens（键名兼容面优先——官方虽标废弃 max_tokens 仍接受）；responses 顶层
// temperature / top_p / max_output_tokens（官方无 penalties 字段不发）；anthropic 顶层
// temperature（官方域 0~1，组装层 clamp min(v,1)）/ top_p（无 penalties 不发），max_tokens
// 三态 = 未配置 8192 / 显式 0 兜底 131072 / 正数用值；gemini generationConfig 全五项
//（惩罚 2.0+ 支持），与 thinkingConfig 合入同一 generationConfig。maxOutput 通用规则
//（非 anthropic）：undefined/0 = 不发字段，由模型按自身上限输出。

// ▲ Anthropic 提示缓存（cache 参 undefined/未启用 = 逐字节零回归；开关存服务商行 DB v12）：
// cache_control = { type:'ephemeral' }（ttl 省略 = 默认 5m，显式 '1h' 才带键）。断点：
// ① system——块数组形态（官方接受 string | block 数组，打缓存必须数组化，挂**稳定段
//   末块**，见下）；② 倒数第二条 user 消息最后 content 块（不足两条 user 不插——官方
//   「断点前内容必须前缀稳定」）；③ tools 数组末项（缓存开启时恒打）。
// ★ volatile 降级（时间感知治理）：本轮注入含 {{time}}/{{datetime}}（volatileTime 标记，
// 透传链见 RequestInject）⇒ system 与 messages 前缀每轮都变，断点①②跳过（白付 1.25×
// 写入费却命中不了）只打 ③——tools 断点的缓存前缀是 tools 段（官方顺序
// tools→system→messages），不受 system 变化影响，是降级后唯一可稳命中的位置；非 volatile
// 时①②行为逐字节不变。
// ★ 2026-10-04 缓存结构笔：system 注入段分两层——稳定段（提示词 + 技能清单 + 记忆块）+
// 波动尾段（知识命中块，逐轮随对话内容变，注入层以 systemTailChars 标记）。断点①挂稳定
// 段末块、尾块排断点后不挂——知识命中逐轮变化不再连带断点失效；标记缺失/越界/末条无
// 标记 = 原末块挂形态零回归。
// ★ 请求顶层 cache_control 不发：官方规格的 cache_control 只存在于内容块（system/tool/
// message 块），根对象无此字段（RikkaHub 顶层键属其自有扩展，严格端点未知字段有 400 风险）。
// ★ TTL 顺序约束（官方：同请求内 1h 断点须在 5m 断点之前）：全部断点共用服务商级单 TTL
// 配置，天然满足，无需排序逻辑。

// 对话消息（与 AiTypes.AiChatMessage 同构——零 import 约束下本地自持，协议流侧
// AiChatMessage[] 结构兼容直接传入；role 事实值 'system'|'user'|'assistant'|'tool'，
// tool 行方言翻译见各 compose 的 role='tool' 分支）。
export interface ComposeChatMessage {
  role: string;
  content: string;
  // 续写前缀（二期 #10；仅 composeOpenAiBody 写 prefix:true，其余方言忽略）
  prefix?: boolean;
  images?: ComposeImagePart[];
  reasoning?: string; // 仅 assistant——OpenAI 方言回传落点（Anthropic/Gemini 不回传）
  // 工具调用：toolCalls 仅 assistant；role='tool' 结果消息携带 toolCallId+toolName
  //（toolName 仅 Gemini functionResponse 必需——官方要求与 functionCall.name 配对）
  toolCalls?: AiToolCall[];
  toolCallId?: string;
  toolName?: string;
  // Responses reasoning 保真项：仅 assistant 工具轮携带，仅 composeOpenAiResponsesBody
  // 消费（type:'reasoning' item 先于 function_call 回传——官方 stateless 保真要求）
  reasoningItems?: ComposeReasoningItem[];
  // DeepSeek 服务端工具原样回传串（DS 全家桶接入批 S2，2026-11-14）：仅 assistant 携带，
  // 仅 composeOpenAiBody 消费——本轮 tools 含 DS server def 时 parse 后原样输出
  // server_tool_calls 字段（历史轮官方档回传；其他协议不消费 = 显式构造请求项天然不带出；
  // 非官方档轮该行按「空 assistant」跳过 = 不发空 content，见 isEmptyAssistantTurn
  // 〔§4.5 修〕）。原样 JSON 串透传，禁任何截断/重排（signature 超限腰斩 = 回传 400，
  // 任务书 §5）
  serverToolCallsJson?: string;
  // volatile 时间变量标记（注入含 {{time}}/{{datetime}} 时 true）：仅发送组装期内存字段，
  // 序列化层不输出（四 compose 显式构造请求项天然不带出）；仅 composeAnthropicBody 消费
  //（volatile 降级缓存断点）
  volatileTime?: boolean;
  // 波动 system 尾段字符数（>0 = content 末尾 N 字符属波动尾段〔知识命中块〕）：仅
  // composeAnthropicBody 消费（system 拆稳定块/尾块，断点只挂稳定块）；组装期内存字段，
  // 序列化层不输出
  systemTailChars?: number;
}

// reasoning 输出项（与 AiTypes.AiReasoningItem 同构——零 import 自持，InjectChatMessage 先例同款）
interface ComposeReasoningItem { id: string; encryptedContent: string }

// 图片部件（与 AiTypes.AiImagePart 同构）：mimeType 如 'image/jpeg'；data 裸 base64（前缀在 compose 内拼）。
// ★ remoteFileId（DS 全家桶接入批 S4）：非空 = DeepSeek 服务端解析件（已上传取回 file_id，
// 无 base64 data——data 空串占位）——OpenAI chat 方言产 {type:'file', file_id} 部件（§0 CC
// 引用扁平形态），其余三方言不消费该形态（isRemoteFilePart 防御性跳过）
export interface ComposeImagePart { mimeType: string; data: string; remoteFileId?: string }

// 服务端解析件判定（compose 分流单源——四处 images 显式构造点共用，禁消费方散写）：
// remoteFileId 非空即 file 引用件。消费面 = composeOpenAiBody（产 file 部件）+
// composeAnthropicBody / composeGeminiBody / composeOpenAiResponsesBody（防御性跳过——
// file_id 是 DeepSeek 专属引用，落进其他端点只会 400，跳过优于产坏部件）
export function isRemoteFilePart(img: ComposeImagePart): boolean {
  return img.remoteFileId !== undefined && img.remoteFileId !== '';
}

// 采样参数（发送侧单一来源——ArkTS 禁结构化类型，故定义在本零 import 文件 export、
// AiTypes re-export 消费，sse-assert 直跑同源）：全可选 = 关闭不发送；maxOutput 三态 =
// undefined 未配置 / 0 显式不限制 / 正数按值（方言分流见文件头 ▲ 注释）
export interface SamplingParams {
  temperature?: number;
  topP?: number;
  presencePenalty?: number;
  frequencyPenalty?: number;
  maxOutput?: number;
}

// 工具定义（ArkTS 禁结构化类型——与 SamplingParams 同款单一来源 export、AiTypes
// re-export 消费；parametersJson = JSON Schema 原串，compose 内 parse 成对象入请求体——
// 坏串跳过该工具不炸请求）。★ serverType（DB 全家桶接入批 S2，2026-11-14）：DeepSeek
// 服务端工具标记——非空 = 该声明是服务端工具（compose 产 {type: serverType} 裸项，非
// function 包裹、无参数；官方 web_tools 形态，任务书 §0「声明」条）；普通客户端工具恒
// undefined = function 形态零回归
export interface AiToolDef {
  name: string;
  description: string;
  parametersJson: string;
  serverType?: string;
}

// 助手侧工具调用（assistant 消息携带 toolCalls / role='tool' 消息携带 toolCallId+toolName）
export interface AiToolCall {
  id: string;
  name: string;
  argsJson: string;
}

// JSON Schema 原串 → 对象（compose 内方言落点共用；坏串回 null = 调用侧跳过该工具，
// 注册表受控不会发生，防御兜底不炸请求）。空对象常量：argsJson 坏串时 tool_use.input /
// functionCall.args 的兜底（ArkTS 禁字面量空对象）
const EMPTY_SCHEMA_OBJ: Object = JSON.parse('{}') as Object;

export function parseToolSchema(parametersJson: string): Object | null {
  try {
    const parsed: object = JSON.parse(parametersJson);
    return parsed !== null && typeof parsed === 'object' ? parsed : null;
  } catch (e) {
    return null;
  }
}

// 思考回传占位：**单空格而非空串**——缺键与空串都被判「未回传」，非空占位可过校验
export const REASONING_REPLAY_PLACEHOLDER: string = ' ';

// 会话思考在场判定（chat 与 Responses 两 compose 共用）：本请求已有任一 assistant 轮带
// 思考（文本或保真项）⇒ 带工具轮的思考载体不可缺；零思考会话恒 false 不注入额外字段
//（零回归红线：对不认 reasoning 字段的端点，凭空多出的键是风险）
export function hasReasoningInHistory(messages: ComposeChatMessage[]): boolean {
  for (const m of messages) {
    if (m.role !== 'assistant') {
      continue;
    }
    if (m.reasoning !== undefined && m.reasoning !== '') {
      return true;
    }
    if (m.reasoningItems !== undefined && m.reasoningItems.length > 0) {
      return true;
    }
  }
  return false;
}

// 空 assistant 轮判定（2026-11-14 自检报告 §4.5 修）：content 空、无图、无客户端工具调用、
// 无思考文本/保真项。历史里唯一的合法空 assistant = 服务端工具轮（正文可能为空）——该行在
// 官方档轮由 server_tool_calls 回传承载（CC），其余方言不消费 server_tools ⇒ 空 model 块
// 上游可能 400，直接跳过；非官方档轮 CC 同样跳过（不发 server_tool_calls 的空行无意义）。
// 带思考的轮不算空（reasoning_content / reasoning item 是有效历史载荷）。
export function isEmptyAssistantTurn(m: ComposeChatMessage): boolean {
  if (m.role !== 'assistant' || m.content !== '') {
    return false;
  }
  if (m.images !== undefined && m.images.length > 0) {
    return false;
  }
  if (m.toolCalls !== undefined && m.toolCalls.length > 0) {
    return false;
  }
  if (m.reasoning !== undefined && m.reasoning !== '') {
    return false;
  }
  if (m.reasoningItems !== undefined && m.reasoningItems.length > 0) {
    return false;
  }
  return true;
}

// OpenAI chat/completions 请求体（对象字面量挂显式接口——坑59①）。
// 多模态：content 数组（图前文后）；无图 = 纯字符串
interface OpenAiImageUrl { url: string }

interface OpenAiContentPart {
  type: string;
  text?: string;
  image_url?: OpenAiImageUrl;
  // DeepSeek 服务端解析件 file 引用（DS 全家桶接入批 S4）：type:'file' 时的 file_id
  //（官方 CC 引用扁平形态 {"type":"file","file_id":"file-api-…"}——任务书 §0「Files」条）
  file_id?: string;
}

interface OpenAiMessageItem {
  role: string;
  content: string | OpenAiContentPart[];
  // 续写前缀标记（官方 chat_prefix_completion：末条 assistant + prefix:true）
  prefix?: boolean;
  reasoning_content?: string; // 历史思考回传（仅 assistant 且 reasoning 非空才带——
  // OpenAI 兼容思考模式事实标准，官方「无工具轮次回传则会被忽略」）
  tool_calls?: OpenAiToolCallItem[]; // assistant 工具调用回传
  tool_call_id?: string; // role='tool' 结果消息（官方要求与 tool_calls.id 配对）
  // DeepSeek 服务端工具回传（DS 全家桶接入批 S2）：仅 assistant 且本轮 tools 含 DS server
  // def 且历史行携带 server_tool_calls 时才带（parse 后原样对象——key 序与串值由
  // JSON.parse→stringify 保真；其他轮/其他协议省略 = 官方明示丢弃合法）
  server_tool_calls?: Object;
}

// assistant 消息的 tool_calls 项（官方形态 id+type:'function'+function{name,arguments}）
interface OpenAiToolCallItem {
  id: string;
  type: string;
  function: OpenAiToolCallFunction;
}

interface OpenAiToolCallFunction {
  name: string;
  arguments: string;
}

// 请求体 tools 声明（官方 Chat Completions 形态）。★ function 可选（DS 全家桶接入批 S2）：
// DeepSeek 服务端工具 = {type} 裸项（无 function 键——官方 web_tools 形态，任务书 §0）；
// 普通客户端工具恒带 function（既有 push 点逐字零变化）
interface OpenAiToolItem {
  type: string;
  function?: OpenAiToolFunctionItem;
}

interface OpenAiToolFunctionItem {
  name: string;
  description: string;
  parameters: Object;
}

interface OpenAiChatRequest {
  model: string;
  messages: OpenAiMessageItem[];
  stream: boolean;
  // 用量统计帧开关：官方 stream_options.include_usage——开启后流末追加 usage 统计帧；
  // 恒开（统计为无开关功能）；个别中转站不认此键报 400 = 用户 body_overrides 自救通道
  // 覆盖（不加代码开关，任务书拍板）
  stream_options?: OpenAiStreamOptions;
  tools?: OpenAiToolItem[]; // 工具声明（空 = 不发键零回归；tool_choice 缺省 auto）
  reasoning_effort?: string; // 思考档位（非空才带——官方枚举透传）
  thinking?: OpenAiThinking; // 思考模式开关（关闭思考专用 type:disabled——DeepSeek/GLM/Kimi 官方域同形）
  temperature?: number; // 采样覆盖（undefined = 不发送）
  top_p?: number;
  presence_penalty?: number;
  frequency_penalty?: number;
  max_tokens?: number; // 最大输出（>0 才发送；0 = 不限制 = 不发字段）
  // DS 官方扩展字段（二期 #4 标题 / #6 安全）：缺省不带 = 请求体逐字节不变
  title?: Record<string, Object>;
  safety_check?: Record<string, Object>;
}

// stream_options 载荷（官方唯一键 include_usage）
interface OpenAiStreamOptions {
  include_usage: boolean;
}

// 思考模式开关载体（DeepSeek/GLM/Kimi 官方 Thinking Mode 同形；OpenAI 官方无此字段——
// 仅 supportsThinkingOff 画像域传，见 AiTypes）
interface OpenAiThinking {
  type: string;
}

// Anthropic Messages 请求体（system 可选 = 无 system 消息时省略；键序：字面量建对象后
// 条件赋值 = JSON 尾部键）。多模态：content 块数组（image{source{base64}} + text）；无图 = 纯字符串
interface AnthropicImageSource { type: string; media_type: string; data: string }

// cache_control 载荷（type 恒 'ephemeral'；ttl 省略 = 默认 5m，显式 '1h' 才带键）
interface AnthropicCacheControl {
  type: string;
  ttl?: string;
}

interface AnthropicContentBlock {
  type: string;
  text?: string;
  source?: AnthropicImageSource;
  cache_control?: AnthropicCacheControl; // 提示缓存断点挂点（仅显式断点位设置）
  // 工具调用块：assistant 侧 tool_use / user 侧 tool_result
  id?: string; // tool_use：调用 id
  name?: string; // tool_use：函数名
  input?: Object; // tool_use：入参对象（官方要求 object 非字符串）
  tool_use_id?: string; // tool_result：配对的 tool_use.id
  // tool_result：结果文本（官方接受 string 或嵌套内容块数组 text/image/document/
  // search_result；★ 工具结果附件启用块数组形态——无附件路径恒 string 逐字节零回归）
  content?: string | AnthropicContentBlock[];
}

// system 块形态（官方 system 接受 string | block 数组——打缓存的 system 断点须数组化）。
// ★ 带波动尾段标记时拆两块 = [稳定块（挂 cache_control）, 尾块（**不挂**）]——尾块排断点
// 之后，其变化不影响缓存前缀命中（见 composeAnthropicBody 内）
interface AnthropicSystemBlock {
  type: string;
  text: string;
  cache_control?: AnthropicCacheControl;
}

interface AnthropicMessageItem {
  role: string;
  content: string | AnthropicContentBlock[];
}

interface AnthropicMessagesRequest {
  model: string;
  system?: string | AnthropicSystemBlock[];
  messages: AnthropicMessageItem[];
  max_tokens: number;
  stream: boolean;
  tools?: AnthropicToolItem[]; // 工具声明（官方形态 input_schema）
  output_config?: AnthropicOutputConfig;
  reasoning?: AnthropicReasoning; // 思考模式开关（DeepSeek 官方域关闭思考专用：effort:none）
  temperature?: number; // 采样覆盖（官方域 0~1——组装层 clamp；undefined = 不发送）
  top_p?: number;
}

// 工具声明项（官方 Messages tools 形态——input_schema 为 JSON Schema 对象）
// cache_control：缓存开启且 apiTools 非空时**末位**工具就地赋值（tools 断点）
interface AnthropicToolItem {
  name: string;
  description: string;
  input_schema: Object;
  cache_control?: AnthropicCacheControl;
}

// 提示缓存参数（唯一消费方 AnthropicChatStream.requestBody——AiConnection promptCache*
// 两字段映射至此；undefined = 不启用 = 请求体逐字节零回归）
export interface AnthropicCacheParam {
  enabled: boolean;
  ttlHour: boolean; // true = 显式 ttl '1h'；false = 默认 5m（省略 ttl 键——官方语义）
}

// 思考档位载体（官方现行规格 output_config.effort；与 OpenAI/Gemini 各自形态勿互抄）
interface AnthropicOutputConfig { effort: string }

// 思考模式开关载体（DeepSeek 官方 Thinking Mode 文档 Anthropic 格式；Anthropic 官方
// 无此字段——仅 supportsThinkingOff 域传，见 AiTypes）
interface AnthropicReasoning { effort: string }

// max_tokens 两档常量：未配置 = 8192 现状（恒定回落值）；显式 0〔不限制〕= 兜底 131072
//（128K，RikkaHub 同款实战值——上限较小的老模型可能 400，走既有回显链不特判）
const ANTHROPIC_MAX_TOKENS: number = 8192;
const ANTHROPIC_MAX_TOKENS_UNLIMITED: number = 131072;

// Gemini GenerateContent 请求体（systemInstruction 可选；键序同 Anthropic = 尾部；role 事实值
// user/model）。多模态：parts 增 inline_data 段（官方 REST 文档蛇形键 inline_data/mime_type）
interface GeminiInlineData { mime_type: string; data: string }

interface GeminiPartItem {
  text?: string;
  inline_data?: GeminiInlineData;
  // 函数调用：model 侧 functionCall / user 侧 functionResponse（官方要求
  // functionResponse.name 与 functionCall.name 配对，response 为 object）
  functionCall?: GeminiFunctionCallItem;
  functionResponse?: GeminiFunctionResponseItem;
}

// functionCall 段（args 为 object——argsJson parse 产物）
interface GeminiFunctionCallItem {
  name: string;
  args: Object;
}

// functionResponse 段（response 包一层 {result} 承载任意文本结果——官方要求 object 形态）
interface GeminiFunctionResponseResult {
  result: string;
}

// ★ parts = functionResponse 的直接子键（与 response 平级——官方 generateContent 形态），
// 仅 Gemini 3+ 支持（判定层 ToolMediaSupport 已挡死 2.x 不产此键；Gemini API 侧仅
// inline_data 合法〔fileData 是 Vertex 专属〕，MIME 白名单 png/jpeg/webp + pdf——本仓
// 编码产物全在内）
interface GeminiFunctionResponseItem {
  name: string;
  response: GeminiFunctionResponseResult;
  parts?: GeminiPartItem[];
}

// 工具声明项（官方 functionDeclarations 形态）
interface GeminiFunctionDeclarationItem {
  name: string;
  description: string;
  parameters: Object;
}

interface GeminiToolItem {
  functionDeclarations: GeminiFunctionDeclarationItem[];
}

interface GeminiContentItem {
  role: string;
  parts: GeminiPartItem[];
}

interface GeminiSystemInstruction {
  parts: GeminiPartItem[];
}

interface GeminiGenerateRequest {
  contents: GeminiContentItem[];
  systemInstruction?: GeminiSystemInstruction;
  generationConfig?: GeminiGenerationConfig;
  tools?: GeminiToolItem[]; // 工具声明（官方顶层 tools 数组）
}

// 思考档位载体（官方 generateContent REST：thinkingBudget 整数预算 + includeThoughts
// 才回传思考摘要段；thinkingLevel 仅 Gemini 3+ 且旧模型传之报错——不用）
interface GeminiThinkingConfig {
  thinkingBudget: number;
  includeThoughts: boolean;
}

// 采样与思考共存：全字段可选——仅开启项入 config（未开启不发键）
interface GeminiGenerationConfig {
  temperature?: number;
  topP?: number;
  presencePenalty?: number;
  frequencyPenalty?: number;
  maxOutputTokens?: number; // >0 才发送；0 = 不限制 = 不发字段
  thinkingConfig?: GeminiThinkingConfig;
}

// OpenAI：messages 原样进 body（system 是 messages 数组普通成员，不提取），stream 恒 true；
// thinking 非空 → 顶层 reasoning_effort 透传；★ 关闭档（offEnabled = supportsThinkingOff
// 域）：off → 顶层 thinking{type:'disabled'}——与 reasoning_effort 互斥（官方 400 实锤），
// 分支排他；off 且非支持域 = 不产生任何字段（零回归）
export function composeOpenAiBody(model: string, messages: ComposeChatMessage[],
  thinking: string = '', offEnabled: boolean = false,
  sampling: SamplingParams | null = null, tools: AiToolDef[] = [],
  dsTitle: boolean = false, dsSafety: boolean = false): string {
  const items: OpenAiMessageItem[] = [];
  const sessionThinking: boolean = hasReasoningInHistory(messages); // 思考会话判据（见函数注释）
  // DeepSeek 服务端回传闸（DS 全家桶接入批 S2）：本轮 tools 含 DS server def（官方档轮）
  // 才回传历史 assistant 的 server_tool_calls——非官方档轮省略该字段（官方明示丢弃合法，
  // 任务书 §0「多轮回传」条）
  const roundHasServerDefs: boolean = tools.some((t: AiToolDef): boolean =>
    t.serverType !== undefined && t.serverType !== '');
  for (const m of messages) {
    // role='tool' 结果消息：官方形态 {role:'tool', tool_call_id, content}。★ 本方言**不消费** m.images（防御性忽略）
    // ——官方规格该 content 无媒体通道，上游判定层（ToolMediaSupport）
    // 已挡死不产工具结果附件；若 images 仍在此出现 = 上游判定出错，忽略而非报错（防线在
    // 判定层——绝不让 base64 灌进文本上下文）
    if (m.role === 'tool') {
      items.push({ role: 'tool', content: m.content, tool_call_id: m.toolCallId ?? '' });
      continue;
    }
    const item: OpenAiMessageItem = { role: m.role, content: m.content };
    // 续写前缀（二期 #10）：只认显式 true（缺省不发键 = 其余请求体逐字节不变）
    if (m.prefix === true) {
      item.prefix = true;
    }
    if (m.images !== undefined && m.images.length > 0) {
      // 带图：content = [image_url 块..., text 块（content 非空才带）]（图前文后）。
      // ★ DS 服务端解析件（S4）：remoteFileId 非空产 {type:'file', file_id} 部件（官方 CC
      // 引用扁平形态——该部件无 base64，禁落 image_url dataURI）；普通图片部件路径逐字
      // 零变化（golden ⑪ 并行守）
      const parts: OpenAiContentPart[] = [];
      for (const img of m.images) {
        if (isRemoteFilePart(img)) {
          parts.push({ type: 'file', file_id: img.remoteFileId });
          continue;
        }
        parts.push({ type: 'image_url', image_url: { url: 'data:' + img.mimeType + ';base64,' + img.data } });
      }
      if (m.content !== '') { parts.push({ type: 'text', text: m.content }); }
      item.content = parts;
    }
    // 历史思考回传：非空按原文挂 reasoning_content；空值但本轮带工具声明 + 该轮有工具
    // 调用 + 会话已出现思考时补占位（DeepSeek 校验口径 = 「带 tools 的请求后续必须完整
    // 回传」，缺键与空串同被拒；三条件合取保证零思考会话与无工具轮零额外字段）
    if (m.role === 'assistant') {
      const reasoningText: string = m.reasoning !== undefined ? m.reasoning : '';
      if (reasoningText !== '') {
        item.reasoning_content = reasoningText;
      } else if (tools.length > 0 && sessionThinking &&
        m.toolCalls !== undefined && m.toolCalls.length > 0) {
        item.reasoning_content = REASONING_REPLAY_PLACEHOLDER;
      }
    }
    // assistant 工具调用回传：官方 tool_calls 数组（arguments 原串透传）
    if (m.role === 'assistant' && m.toolCalls !== undefined && m.toolCalls.length > 0) {
      const calls: OpenAiToolCallItem[] = [];
      for (const tc of m.toolCalls) {
        calls.push({ id: tc.id, type: 'function',
          function: { name: tc.name, arguments: tc.argsJson } });
      }
      item.tool_calls = calls;
    }
    // assistant 服务端工具回传（DS 全家桶接入批 S2）：仅官方档轮（roundHasServerDefs）且
    // 历史行携带原样串——parse 后原样挂 server_tool_calls（key 序与串值 parse→stringify
    // 保真，禁任何截断/重排；**禁走 clipToolResult 8K 口**——signature 超限腰斩 = 回传 400，
    // 任务书 §5）。坏 JSON 防御跳过该字段不炸请求（与 parseToolSchema 防御同族）
    // ★ 2026-11-14 自检轮修：列载荷是**内层信封** {"server_tool_calls":[…steps…],"annotations":[…]}
    // （合体只为同列存两字段，见 ChatStreamFlowCtrl.serverToolsFull），回传必须取信封内层
    // server_tool_calls 段挂到消息同名字段——首版把整个信封挂给 server_tool_calls（数组位收到
    // 对象，下一轮官方档直接 400）。判据 = 官方 web_tools「把 assistant 消息连同
    // server_tool_calls 原样回传」；非数组 = 坏信封跳过（同坏串口径）
    if (m.role === 'assistant' && roundHasServerDefs &&
      m.serverToolCallsJson !== undefined && m.serverToolCallsJson !== '') {
      try {
        const envelope: Record<string, Object> = JSON.parse(m.serverToolCallsJson) as Record<string, Object>;
        const inner: Object | undefined = envelope['server_tool_calls'];
        if (Array.isArray(inner)) {
          item.server_tool_calls = inner;
        }
      } catch (e) {
        // 坏串跳过：字段缺席 = 服务端按「无历史网页上下文」处理（官方合法形态）
      }
    }
    // 空 assistant 行跳过（§4.5 修）：例外 = 本行已挂 server_tool_calls（官方档轮的服务端
    // 工具轮正文可为空，官方要求原样回传——不能丢）
    if (isEmptyAssistantTurn(m) && item.server_tool_calls === undefined) {
      continue;
    }
    items.push(item);
  }
  const reqBody: OpenAiChatRequest = {
    model: model,
    messages: items,
    stream: true,
    // 用量统计帧（恒开；键序在 stream 后 = JSON 尾部追加，sse-assert ⑪ 组产物断言）
    stream_options: { include_usage: true }
  };
  // 工具声明：官方 tools 数组；schema 坏串工具跳过（防御，注册表受控不达）。
  // ★ DS 服务端工具项（S2②）：serverType 非空 = {type} 裸项（无 function 无参数——官方
  // web_tools 形态，任务书 §0「声明」条），不进 schema parse；普通工具路径逐字零变化
  if (tools.length > 0) {
    const apiTools: OpenAiToolItem[] = [];
    for (const t of tools) {
      if (t.serverType !== undefined && t.serverType !== '') {
        apiTools.push({ type: t.serverType });
        continue;
      }
      const schema: Object | null = parseToolSchema(t.parametersJson);
      if (schema === null) {
        continue;
      }
      apiTools.push({ type: 'function',
        function: { name: t.name, description: t.description, parameters: schema } });
    }
    if (apiTools.length > 0) {
      reqBody.tools = apiTools;
    }
  }
  if (thinking === 'off' && offEnabled) {
    reqBody.thinking = { type: 'disabled' };
  } else if (thinking !== '' && thinking !== 'off') {
    reqBody.reasoning_effort = thinking;
  }
  // 采样覆盖（开启才带键；maxOutput 0 = 不限制 = 不发字段——由模型按自身上限输出）
  if (sampling !== null) {
    if (sampling.temperature !== undefined) {
      reqBody.temperature = sampling.temperature;
    }
    if (sampling.topP !== undefined) {
      reqBody.top_p = sampling.topP;
    }
    if (sampling.presencePenalty !== undefined) {
      reqBody.presence_penalty = sampling.presencePenalty;
    }
    if (sampling.frequencyPenalty !== undefined) {
      reqBody.frequency_penalty = sampling.frequencyPenalty;
    }
    if (sampling.maxOutput !== undefined && sampling.maxOutput > 0) {
      reqBody.max_tokens = sampling.maxOutput;
    }
  }
  // DS 官方扩展字段（二期 #4 标题 / #6 安全）：两布尔缺省 false ⇒ 请求体逐字节不变
  //（非 DS golden 全绿守）。官方明示开启后部分采样参数会被服务端忽略，max_tokens 照常生效
  if (dsTitle) {
    reqBody.title = { 'enabled': true };
  }
  if (dsSafety) {
    reqBody.safety_check = { 'level': 'high' };
  }
  return JSON.stringify(reqBody);
}

// Anthropic：system 消息提出为顶层 system 字段（多条以 \n\n 连接），其余消息 role 原样
//（user/assistant）；max_tokens 必填，三态见下方实现处（未配置 8192 / 显式 0〔不限制〕
// 兜底 131072 / 正数用值）；stream 恒 true；无 system 消息时省略 system 字段。
// ★ 关闭档（offEnabled = supportsThinkingOff 域）：off → 顶层 reasoning{effort:'none'}
//（DeepSeek 官方 Thinking Mode 文档 Anthropic 格式；Anthropic 官方端点不认此字段——非
// 支持域不产字段零回归）；与 output_config 分支排他（关闭与力度不同时给）
export function composeAnthropicBody(model: string, messages: ComposeChatMessage[],
  thinking: string = '', offEnabled: boolean = false,
  sampling: SamplingParams | null = null, cache?: AnthropicCacheParam,
  tools: AiToolDef[] = []): string {
  // system 提取（走顶层字段）；user/assistant 原样；role='tool' 结果消息 = 连续段并成
  // 一条 user 消息，content 为 tool_result 块数组（官方工具结果以 user 角色回传；
  // 连续多条并一消息满足交替约束）
  const chatItems: AnthropicMessageItem[] = [];
  const systemParts: string[] = [];
  // 波动尾段标记：逐条 system 赋值——循环走完后 = 最后一条 system 消息的标记生效
  //（多 system 异常序列时仅末条有效；缺省 0 = 无尾段）
  let systemTail: number = 0;
  let pendingToolResults: AnthropicContentBlock[] | null = null;
  const flushToolResults = (): void => {
    if (pendingToolResults !== null) {
      chatItems.push({ role: 'user', content: pendingToolResults });
      pendingToolResults = null;
    }
  };
  for (const m of messages) {
    // 空 assistant 块跳过（§4.5 修）：本方言不消费 server_tools，空 content 块上游可能 400
    if (isEmptyAssistantTurn(m)) {
      continue;
    }
    if (m.role === 'system') {
      flushToolResults();
      systemParts.push(m.content);
      systemTail = m.systemTailChars ?? 0;
    } else if (m.role === 'tool') {
      if (pendingToolResults === null) {
        pendingToolResults = [];
      }
      // ★ 工具结果附件——有图/PDF 时 content 块数组化（官方 tool_result.content 接受
      // 嵌套块数组 text/image/document；无附件路径恒 string 逐字节零回归）。附件块按
      // mime 分派：image/* → image 块、application/pdf → document 块（base64 形态）
      if (m.images !== undefined && m.images.length > 0) {
        const resultBlocks: AnthropicContentBlock[] = [{ type: 'text', text: m.content }];
        for (const img of m.images) {
          if (img.mimeType === 'application/pdf') {
            resultBlocks.push({ type: 'document',
              source: { type: 'base64', media_type: 'application/pdf', data: img.data } });
          } else {
            resultBlocks.push({ type: 'image',
              source: { type: 'base64', media_type: img.mimeType, data: img.data } });
          }
        }
        pendingToolResults.push({ type: 'tool_result', tool_use_id: m.toolCallId ?? '',
          content: resultBlocks });
      } else {
        pendingToolResults.push({ type: 'tool_result', tool_use_id: m.toolCallId ?? '',
          content: m.content });
      }
    } else if (m.role === 'assistant' && m.toolCalls !== undefined && m.toolCalls.length > 0) {
      // assistant 工具调用轮：content 块数组 = 文本块（非空才带）+ tool_use 块族
      flushToolResults();
      const blocks: AnthropicContentBlock[] = [];
      if (m.content !== '') {
        blocks.push({ type: 'text', text: m.content });
      }
      for (const tc of m.toolCalls) {
        blocks.push({ type: 'tool_use', id: tc.id, name: tc.name,
          input: parseToolSchema(tc.argsJson) ?? EMPTY_SCHEMA_OBJ });
      }
      chatItems.push({ role: m.role, content: blocks });
    } else if (m.images !== undefined && m.images.length > 0) {
      // 带图：content = [image 块..., text 块（非空才带）]。★ DS 服务端解析件防御性跳过
      //（isRemoteFilePart——file_id 引用件非本方言消费形态，落 base64 空数据只会 400）；
      // 全部被跳过时回落纯文本形态（与无图分支同形态），防空 blocks 上送
      flushToolResults();
      const visibleImages: ComposeImagePart[] = m.images.filter(
        (img: ComposeImagePart): boolean => !isRemoteFilePart(img));
      if (visibleImages.length > 0) {
        const blocks: AnthropicContentBlock[] = [];
        for (const img of visibleImages) {
          blocks.push({ type: 'image', source: { type: 'base64', media_type: img.mimeType, data: img.data } });
        }
        if (m.content !== '') { blocks.push({ type: 'text', text: m.content }); }
        chatItems.push({ role: m.role, content: blocks });
      } else {
        chatItems.push({ role: m.role, content: m.content });
      }
    } else {
      flushToolResults();
      chatItems.push({ role: m.role, content: m.content });
    }
  }
  flushToolResults();
  // 提示缓存（undefined/未启用 = 全支跳过 = 逐字节零回归）：落点① system（= 稳定段末块）
  // + ② 倒数第二条 user 末块 + ③ tools 末项（依据见文件头 ▲ 注释）
  const cacheCtrl: AnthropicCacheControl | undefined = cache !== undefined && cache.enabled ?
    (cache.ttlHour ? { type: 'ephemeral', ttl: '1h' } : { type: 'ephemeral' }) : undefined;
  // ★ volatile 降级：volatilePrompt = 注入含 {{time}}/{{datetime}}（已实时替换）⇒
  // system 与 messages 前缀每轮都变 ⇒ 断点①②命中不了却仍付 1.25× 缓存写入计费——全
  // 跳过（system 保持 string 形态）只打 ③（无 tools = 本轮零断点）；非 volatile 时①②
  // 行为逐字节不变（唯一行为差 = ③ 恒打，属有意新增非回归）
  const volatilePrompt: boolean =
    messages.some((m: ComposeChatMessage): boolean => m.volatileTime === true);
  if (cacheCtrl !== undefined && !volatilePrompt) {
    // ② messages 断点：倒数第二条 user（工具轮回传使「user」语义含工具结果消息——命中
    // 时断点落其末块就地挂不损字段，见下方分支注释；不足两条 = 不插）。content 字符串 →
    // 数组化 [{type:'text',...}]；块数组 → 末块挂点
    const userIdx: number[] = [];
    for (let i = 0; i < chatItems.length; i++) {
      if (chatItems[i].role === 'user') {
        userIdx.push(i);
      }
    }
    if (userIdx.length >= 2) {
      const target: number = userIdx[userIdx.length - 2];
      const item: AnthropicMessageItem = chatItems[target];
      if (typeof item.content === 'string') {
        chatItems[target] = { role: item.role,
          content: [{ type: 'text', text: item.content, cache_control: cacheCtrl }] };
      } else {
        // ★ 就地挂 cache_control，禁重建对象：工具轮回传使「user 消息」含工具结果行
        //（role='tool' 并成 user + tool_result 块数组），倒二 user 命中工具结果消息时末块
        // = tool_result 块，重建丢 tool_use_id 与 content ⇒ 官方 400（历史含 ≥2 段工具
        // 循环后每轮必触发）。块字段全可选就地赋值零拷贝，任意块类型字段零丢失；末块为
        // image/document 附件块时挂点官方合法，天然覆盖无需特判
        const blocks: AnthropicContentBlock[] = item.content;
        blocks[blocks.length - 1].cache_control = cacheCtrl;
      }
    }
  }
  // max_tokens 三态（必填字段）：未配置 8192；显式 0〔不限制〕= 兜底 131072；正数用值
  let maxTokens: number = ANTHROPIC_MAX_TOKENS;
  if (sampling !== null && sampling.maxOutput !== undefined) {
    maxTokens = sampling.maxOutput > 0 ? sampling.maxOutput : ANTHROPIC_MAX_TOKENS_UNLIMITED;
  }
  const req: AnthropicMessagesRequest = {
    model: model,
    messages: chatItems,
    max_tokens: maxTokens,
    stream: true
  };
  if (systemParts.length > 0) {
    if (cacheCtrl !== undefined && !volatilePrompt) {
      // ① system 断点（★ 边界语义）：systemTailChars 是「波动尾段字符数」= InjectSections
      // dynamic section 边界的倒数编码——stableBoundary = lastPart.length − systemTail
      //（对偶换算见 InjectSections.stableBoundaryOf；'\n\n' 分隔符归稳定段一侧〔改归属 =
      // 请求体差 2 字节〕）。尾段标记有效 ⇔ 边界落在 (0, lastPart.length) 开区间；有效 →
      // 拆 [稳定块（挂 cache_control）, 尾块（不挂）]；边界无效（等长/越界/缺失）一律回
      // 下方末块挂形态，防御性零回归；关缓存/volatile 降级保持 string 形态零回归
      const lastPart: string = systemParts[systemParts.length - 1];
      const stableBoundary: number = lastPart.length - systemTail;
      if (stableBoundary > 0 && stableBoundary < lastPart.length) {
        const stableLen: number = stableBoundary;
        const tailBlocks: AnthropicSystemBlock[] = [];
        for (let i = 0; i < systemParts.length - 1; i++) {
          tailBlocks.push({ type: 'text', text: systemParts[i] });
        }
        tailBlocks.push({ type: 'text', text: lastPart.slice(0, stableLen),
          cache_control: cacheCtrl });
        tailBlocks.push({ type: 'text', text: lastPart.slice(stableLen) });
        req.system = tailBlocks;
      } else {
        const sysBlocks: AnthropicSystemBlock[] = [];
        for (const part of systemParts) {
          sysBlocks.push({ type: 'text', text: part });
        }
        sysBlocks[sysBlocks.length - 1] = { type: 'text',
          text: sysBlocks[sysBlocks.length - 1].text, cache_control: cacheCtrl };
        req.system = sysBlocks;
      }
    } else {
      req.system = systemParts.join('\n\n');
    }
  }
  // 工具声明：官方 tools 数组（input_schema 为 JSON Schema 对象）；schema 坏串跳过。
  // ★ 提示缓存 ③ tools 断点：缓存开启且 apiTools 非空时给**最后一个**工具就地赋
  // cache_control（照块数组就地挂口径——禁重建对象；断点恒打〔volatile 与否都打〕：
  // tools 断点缓存前缀 = tools 段，不受 system 变化影响，是 volatile 降级后唯一可稳
  // 命中的断点位置）
  if (tools.length > 0) {
    const apiTools: AnthropicToolItem[] = [];
    for (const t of tools) {
      const schema: Object | null = parseToolSchema(t.parametersJson);
      if (schema === null) {
        continue;
      }
      apiTools.push({ name: t.name, description: t.description, input_schema: schema });
    }
    if (apiTools.length > 0) {
      if (cacheCtrl !== undefined) {
        apiTools[apiTools.length - 1].cache_control = cacheCtrl;
      }
      req.tools = apiTools;
    }
  }
  if (thinking === 'off' && offEnabled) {
    req.reasoning = { effort: 'none' };
  } else if (thinking !== '' && thinking !== 'off') {
    req.output_config = { effort: thinking };
  }
  // 采样覆盖：temperature 官方域 0~1——clamp min(v,1)（UI 滑块 0~2 全协议统一）；
  // 官方无 penalties 字段——不发
  if (sampling !== null) {
    if (sampling.temperature !== undefined) {
      req.temperature = Math.min(sampling.temperature, 1);
    }
    if (sampling.topP !== undefined) {
      req.top_p = sampling.topP;
    }
  }
  return JSON.stringify(req);
}

// Gemini：模型名在 URL 路径段不进 body（故无 model 参——别照抄对称带参）；system 消息
// 提为 systemInstruction.parts；role 映射 assistant → model；无 stream 字段（SSE 由
// alt=sse 查询参开启）
export function composeGeminiBody(messages: ComposeChatMessage[], thinking: string = '',
  sampling: SamplingParams | null = null, tools: AiToolDef[] = []): string {
  // role 映射：assistant → model；system 提为 systemInstruction；role='tool' 结果消息 =
  // 连续段并成一条 user content，parts 为 functionResponse 段族（官方以 user 角色回传）
  const contents: GeminiContentItem[] = [];
  const systemParts: GeminiPartItem[] = [];
  let pendingToolParts: GeminiPartItem[] | null = null;
  const flushToolParts = (): void => {
    if (pendingToolParts !== null) {
      contents.push({ role: 'user', parts: pendingToolParts });
      pendingToolParts = null;
    }
  };
  for (const m of messages) {
    // 空 assistant 段跳过（§4.5 修）：空 parts 上游可能 400；服务端工具轮在本方言无载体
    if (isEmptyAssistantTurn(m)) {
      continue;
    }
    if (m.role === 'system') {
      flushToolParts();
      systemParts.push({ text: m.content });
    } else if (m.role === 'tool') {
      if (pendingToolParts === null) {
        pendingToolParts = [];
      }
      // ★ 工具结果附件——有图/PDF 时 functionResponse 加 parts 兄弟键（与 response 平级，
      // 非嵌在 response 内——写错即拒）；无附件路径逐字节零回归
      if (m.images !== undefined && m.images.length > 0) {
        const mediaParts: GeminiPartItem[] = [];
        for (const img of m.images) {
          mediaParts.push({ inline_data: { mime_type: img.mimeType, data: img.data } });
        }
        pendingToolParts.push({ functionResponse: { name: m.toolName ?? '',
          response: { result: m.content }, parts: mediaParts } });
      } else {
        pendingToolParts.push({ functionResponse: { name: m.toolName ?? '',
          response: { result: m.content } } });
      }
    } else if (m.role === 'assistant' && m.toolCalls !== undefined && m.toolCalls.length > 0) {
      // model 函数调用轮：parts = 文本段（非空才带）+ functionCall 段族
      flushToolParts();
      const parts: GeminiPartItem[] = [];
      if (m.content !== '') {
        parts.push({ text: m.content });
      }
      for (const tc of m.toolCalls) {
        parts.push({ functionCall: { name: tc.name,
          args: parseToolSchema(tc.argsJson) ?? EMPTY_SCHEMA_OBJ } });
      }
      contents.push({ role: 'model', parts: parts });
    } else if (m.images !== undefined && m.images.length > 0) {
      // 带图：parts = [inline_data 段..., text 段（content 非空才带）]。★ DS 服务端解析件
      // 防御性跳过（isRemoteFilePart——file_id 引用件非本方言消费形态）；全部被跳过时回落
      // 纯文本 parts，空 parts 不上送
      flushToolParts();
      const visibleImages: ComposeImagePart[] = m.images.filter(
        (img: ComposeImagePart): boolean => !isRemoteFilePart(img));
      if (visibleImages.length > 0) {
        const parts: GeminiPartItem[] = [];
        for (const img of visibleImages) {
          parts.push({ inline_data: { mime_type: img.mimeType, data: img.data } });
        }
        if (m.content !== '') { parts.push({ text: m.content }); }
        contents.push({ role: m.role === 'assistant' ? 'model' : m.role, parts: parts });
      } else {
        contents.push({
          role: m.role === 'assistant' ? 'model' : m.role,
          parts: [{ text: m.content }]
        });
      }
    } else {
      flushToolParts();
      contents.push({
        role: m.role === 'assistant' ? 'model' : m.role,
        parts: [{ text: m.content }]
      });
    }
  }
  flushToolParts();
  // ★ Gemini 末条降级守卫：官方要求末条必须 user（非 user = 400）。正常对话守卫空转，仅
  // 防御异常序列（历史末条 assistant 死数据、工具轮中断后 flush 出的 functionResponse
  // 成为末条等）：结尾连续 model 段并入最后一条 user并移除；全 model 无 user 的畸形序列
  // 保留原样（不伪造 user，协议层显式报错）。
  if (contents.length > 0 &&
    contents[contents.length - 1].role === 'model') {
    let lastUser: number = -1;
    for (let i = contents.length - 1; i >= 0; i--) {
      if (contents[i].role === 'user') {
        lastUser = i;
        break;
      }
    }
    if (lastUser >= 0) {
      // ★ 合并禁以 p.text ?? '' 压平整条消息——functionResponse / inline_data /
      // functionCall 等非 text 段无 text 字段，旧实现把 lastUser 恰为 user(functionResponse)
      // 的工具轮中断序列整段压成空文本（工具结果静默丢失）。现按原序遍历 lastUser 及其后
      // 全部 model 段的 parts：文本段就近 '\n\n' 拼接（纯文本场景与旧实现逐字节一致），
      // 非文本段原位保留——官方 user parts 本就允许混排 text 与 functionResponse
      const mergedParts: GeminiPartItem[] = [];
      let textBuffer: string[] = [];
      const flushText = (): void => {
        if (textBuffer.length > 0) {
          mergedParts.push({ text: textBuffer.join('\n\n') });
          textBuffer = [];
        }
      };
      for (let i = lastUser; i < contents.length; i++) {
        for (const p of contents[i].parts) {
          if (p.text === undefined) {
            flushText();
            mergedParts.push(p);
          } else {
            textBuffer.push(p.text);
          }
        }
      }
      flushText();
      contents[lastUser] = { role: 'user', parts: mergedParts };
      contents.splice(lastUser + 1);
    }
  }
  const req: GeminiGenerateRequest = { contents: contents };
  if (systemParts.length > 0) {
    req.systemInstruction = { parts: systemParts };
  }
  // 工具声明：官方 tools=[{functionDeclarations}]；schema 坏串工具跳过
  if (tools.length > 0) {
    const decls: GeminiFunctionDeclarationItem[] = [];
    for (const t of tools) {
      const schema: Object | null = parseToolSchema(t.parametersJson);
      if (schema === null) {
        continue;
      }
      decls.push({ name: t.name, description: t.description, parameters: schema });
    }
    if (decls.length > 0) {
      req.tools = [{ functionDeclarations: decls }];
    }
  }
  // generationConfig：思考档位与采样共存合入（任一开启才建；键序 = 采样在前
  // thinkingConfig 尾部，无采样路径与原结构逐字段一致）
  const samplingOn: boolean = sampling !== null && (
    sampling.temperature !== undefined || sampling.topP !== undefined ||
    sampling.presencePenalty !== undefined || sampling.frequencyPenalty !== undefined ||
    (sampling.maxOutput !== undefined && sampling.maxOutput > 0));
  if (thinking !== '' || samplingOn) {
    const genCfg: GeminiGenerationConfig = {};
    if (sampling !== null) {
      if (sampling.temperature !== undefined) {
        genCfg.temperature = sampling.temperature;
      }
      if (sampling.topP !== undefined) {
        genCfg.topP = sampling.topP;
      }
      if (sampling.presencePenalty !== undefined) {
        genCfg.presencePenalty = sampling.presencePenalty;
      }
      if (sampling.frequencyPenalty !== undefined) {
        genCfg.frequencyPenalty = sampling.frequencyPenalty;
      }
      if (sampling.maxOutput !== undefined && sampling.maxOutput > 0) {
        genCfg.maxOutputTokens = sampling.maxOutput;
      }
    }
    if (thinking !== '') {
      // includeThoughts 必带——官方默认不回传思考摘要段（不带 = 思考发生但 UI 无从显示）
      genCfg.thinkingConfig =
        { thinkingBudget: geminiThinkingBudget(thinking), includeThoughts: true };
    }
    req.generationConfig = genCfg;
  }
  return JSON.stringify(req);
}

// Gemini 思考预算映射（档位 → thinkingBudget 整数）：取值在全 2.5 系合法范围内——
// 1024 ≥ flash-lite 下限 512 / 24576 ≤ 全系上限（Pro 上限 32768 但取全系交集）；'' 不经此
// （compose 侧已守卫）；脏值兜底 max 档
export function geminiThinkingBudget(tier: string): number {
  if (tier === 'low') {
    return 1024;
  }
  if (tier === 'high') {
    return 8192;
  }
  return 24576; // 'max'
}

