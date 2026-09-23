// 请求体组装纯函数（2026-08-30 新增；四协议 requestBody 方言单一落点——行为自各协议流
// 原样抽取，逐字节一致；样本即规格 = scripts/sse-assert.mjs 断言组）。零 import（照
// SseParser「node 直跑同源」约束——断言脚本复制本文件为 .ts 直跑），messages 类型自持
// 本地接口（与 AiChatMessage 同构；AiTypes 反向依赖 SseParser，引入即破零 import）。
// ★ 2026-08-30 注入配置版：composeSendMessages 注入身份/位置/深度三重配置 + 协议交替
// 守卫 mergeConsecutiveSameRole + Gemini 末条 model 降级守卫。适配口径 = 只适配协议规格
// 不逐厂商特判；user 注入 = 拼接式（不产生新消息，交替约束与缓存断点天然规避，
// RikkaHub #1101 教训反向实现）；assistant 注入 = 独立消息 + 连续同角色 merge 守卫。

// ▲ 2026-08-31 附件上传（多模态）：ComposeChatMessage + images 可选字段（仅 user 消息），
// 四协议 content part 方言在此适配（官方查证：OpenAI chat = image_url{url:dataURI} /
// Responses = input_image 直串 dataURI / Anthropic = image{source{base64}} / Gemini REST =
// inline_data{mime_type,data} 蛇形键）；无 images 路径逐字节不变（⑰ 组断言双向保护）。

// ▲ 2026-08-31 思考档位（任务 B）：四 compose 增可选 thinking 参（'' = 不传 = 现状逐字节
// 回归；非空 = 各协议方言落点，官方查证 2026-08-31：OpenAI chat 顶层 reasoning_effort /
// Responses 顶层 reasoning{effort} / Anthropic 顶层 output_config{effort}（现行规格，
// low/medium/high/xhigh/max 随模型而异——旧 thinking.budget_tokens 新模型已弃用）/
// Gemini generationConfig.thinkingConfig{thinkingBudget,includeThoughts}（thinkingLevel 仅
// Gemini 3+ 且旧模型传之报错，不用）。枚举档位 low/high/max 三协议族均官方合法 → 透传；
// Gemini 预算映射 geminiThinkingBudget（全 2.5 系范围内）。注入组装域已拆 RequestInject.ets
//（本文件加思考方言超 400 红线的域级最小拆分，⑭⑮ 断言组随迁该文件同源直跑）。

// ▲ 2026-09-01 回传历史思考（RikkaHub includeHistoryReasoning 口径）：ComposeChatMessage
// + reasoning（仅 assistant）；**仅 OpenAI chat 路径回传**（assistant 消息带
// reasoning_content——DeepSeek/豆包/智谱/Kimi 等 OpenAI 兼容思考模式事实标准，DeepSeek
// 官方文档「思考模式必须回传（工具调用后），无工具轮次回传无害」）。★ 未回传路径与
// 原因：Anthropic（thinking 块须 signature 保真——未提取存储，官方 400 Invalid signature
// 实锤）、Gemini（thought 段回传非官方要求）——均维持现状零回归，需独立专项
//（signature 保真提取存储）。
// ★ 2026-09-17 回传缺陷修复（真机 HTTP 400 报障「The `reasoning_text` in the thinking
// mode must be passed back to the API.」——工具轮续轮必失败，两处补齐）。校验文案为服务商
// 跨方言通用（chat 方言的 reasoning_content 与 Responses 方言的 reasoning_text 共用同一句，
// 生态实证：OpenAI chat / Responses 两条链的同类修复报告收到的是同一文案）：
// ① **Responses 路径补齐明文回传**（此前恒不回传）：09-06 保真链只认 id+encrypted_content
//    （OpenAI 官方端点规格，第三方恒不参与）——而 DeepSeek 等第三方 Responses 端点官方明示
//    「输入 reasoning item 支持明文 content；summary 与 encrypted_content 不支持」，故捕获项
//    缺席时改挂明文 reasoning item（content:[{type:'reasoning_text',text}]，官方 Create
//    Response 规格），序 = reasoning item 先于 message/function_call item（官方输入即输出序，
//    服务端实测校验序）；
// ② **空思考不再丢载体**：模型未产出思考文本、但会话已在思考模式（本请求已有 assistant 轮
//    带思考）时，带工具轮的 reasoning 载体仍须在场——补单空格占位（缺键与空串都被判「未
//    回传」；生态同类修复同款姿势）。零思考会话（普通模型 / 未开思考）恒不产额外字段。

// ▲ 2026-09-01 助手高级设定·采样参数：四 compose 增可选 sampling 参（null/缺省 = 逐字节
// 零回归；官方 API 文档查证 2026-09-01）。方言落点与适配口径（只适配协议规格不逐厂商
// 特判——锁参新模型〔GPT-5/Opus 4.7+〕发采样参数可能被拒，错误体走既有回显链）：
// · openai chat：顶层 temperature / top_p / presence_penalty / frequency_penalty /
//   max_tokens（键名拍板 = 兼容面优先——第三方「OpenAI 兼容」中转事实标准，官方虽标
//   废弃 max_tokens 仍接受；范围 温度 0~2 / top_p 0~1 / 双惩罚 -2~2）；
// · responses：顶层 temperature / top_p / max_output_tokens（★ 官方 Responses 接口无
//   presence/frequency penalty 字段——不发）；
// · anthropic：顶层 temperature（官方域 0~1，组装层 clamp min(v,1)）/ top_p（官方无
//   penalties——不发）；max_tokens 三态：未配置 = 8192 现状 / 显式 0〔不限制〕= 兜底
//   131072（128K，RikkaHub 同款实战值）/ 正数 = 用值；
// · gemini：generationConfig.temperature / topP / presencePenalty / frequencyPenalty /
//   maxOutputTokens（惩罚 Gemini 2.0+ 支持，范围同 openai -2~2）；与 thinkingConfig
//   共存合入同一 generationConfig。
// maxOutput 通用规则（非 anthropic）：undefined/0 = 不发字段（由模型按自身上限输出）。

// ▲ 2026-09-01 Anthropic 提示缓存（任务书-Anthropic提示缓存cache_control；官方
// platform.claude.com/docs prompt-caching 查证）：composeAnthropicBody 增可选 cache 参
//（undefined/缺省 = 逐字节零回归；仅 anthropic 消费，开关存服务商行 DB v12）。
// cache_control = { type:'ephemeral' }（默认 TTL 5m——官方「省略 ttl 键即 5m」，显式
// '1h' 才带 ttl 键）；断点落点（官方允许的块，禁区口径）：
// ① system：**块数组形态** [{type:'text', text, cache_control}]（官方 system 接受 string
//   或 block 数组两形态——打缓存必须数组化，关缓存保持 string 形态零回归）；
// ② 倒数第二条 user 消息最后 content 块（09-02 起工具轮回传使「user」语义含工具结果
// 消息——命中时末块就地挂 control 不损字段，见实现处分支注释；不足两条 user 不插——官方「断点前内容
//   必须前缀稳定」语义；aicontrol 无 tool_result 型 user，无需排除支）；content 字符串
//   形态数组化为 [{type:'text',...}]，块数组形态改末块（图前文后序——末块 = text 或 image
//   均官方合法挂点）；
// ③ tools 数组最后一项：官方允许挂点——2026-09-02 起请求可带 tools，但工具集小（≤数条）
// 缓存收益低，暂不产末位挂点（ Anthropic compose 内 tools 注入处有依据注释，需要时补）。
// ★ 请求顶层 cache_control 不发：官方 Messages 规格的 cache_control 只存在于**内容块**
// （system/tool/message 块），根对象无此字段——RikkaHub 顶层键属其自有扩展姿势，非官方
// 规格（严格端点未知字段有 400 风险）；显式块断点已覆盖官方文档全部场景，依据记录在此。
// ★ TTL 顺序约束（官方：同请求内 1h 断点必须在 5m 断点之前）：aicontrol 全部断点共用
// 服务商级单 TTL 配置 → 天然同 TTL 恒满足，无需排序逻辑。

// 对话消息（与 AiTypes.AiChatMessage 同构：role 事实值 'system' | 'user' | 'assistant' |
// 'tool'——原三态列举漏 tool，2026-09-13 全码优化笔1 对照实现核正；tool 行的方言翻译
// 见各 compose 函数 role='tool' 分支）。
// 零 import 约束下本地自持——协议流侧 AiChatMessage[] 结构兼容，直接传入。
// 2026-09-01 回传历史思考：+ reasoning（仅 assistant，OpenAI 方言落点；Anthropic/Gemini
// 不回传——见 ai 级 AiChatMessage 同字段注释）
interface ComposeChatMessage {
  role: string;
  content: string;
  images?: ComposeImagePart[];
  reasoning?: string;
  // 工具调用（2026-09-02；与 AiTypes.AiToolCall 同构）：toolCalls 仅 assistant 携带；
  // role='tool' 的结果消息携带 toolCallId+toolName（toolName 仅 Gemini functionResponse
  // 必需——官方要求与 functionCall.name 配对，其余协议不消费）
  toolCalls?: AiToolCall[];
  toolCallId?: string;
  toolName?: string;
  // Responses reasoning 输出项（2026-09-06；与 AiTypes.AiReasoningItem 同构）：仅 assistant
  // 工具轮携带，仅 composeOpenAiResponsesBody 消费（type:'reasoning' item 先于 function_call
  // 回传——OpenAI 官方 stateless 保真要求）
  reasoningItems?: ComposeReasoningItem[];
}

// reasoning 输出项（与 AiTypes.AiReasoningItem / SseParser.AiReasoningItem 同构；零 import
// 自持——AiTypes 反向依赖 SseParser，引入即破零 import，InjectChatMessage 先例同款姿势）
interface ComposeReasoningItem { id: string; encryptedContent: string }

// 图片部件（与 AiTypes.AiImagePart 同构）：mimeType 如 'image/jpeg'；data 裸 base64（前缀在 compose 内拼）
interface ComposeImagePart { mimeType: string; data: string }

// 采样参数（发送侧单一来源——ArkTS 禁结构化类型〔arkts-no-structural-typing 实锤：
// 双接口同构互传即编译错〕，故定义在本零 import 文件 export，AiTypes re-export 消费
// 〔与 AiTypes import SseParser.SseDelta 同款姿势，无循环〕；sse-assert 直跑同源）：
// 全可选 = 关闭该项不发送；maxOutput 三态 = undefined 未配置 / 0 显式不限制 / 正数按值
//（协议分流见文件头 ▲ 2026-09-01 注释）
export interface SamplingParams {
  temperature?: number;
  topP?: number;
  presencePenalty?: number;
  frequencyPenalty?: number;
  maxOutput?: number;
}

// ▲ 2026-09-02 工具调用底层（RikkaHub 三协议方言 + CubeAgent OpenAI 实现调研定稿；
// 官方查证：OpenAI chat tools=[{type:'function',function:{name,description,parameters}}] /
// Responses tools=[{type:'function',name,description,parameters}] 扁平 / Anthropic
// tools=[{name,description,input_schema}] / Gemini tools=[{functionDeclarations:[...]}]；
// 工具结果回传：openai role:'tool'+tool_call_id / Responses function_call_output item /
// Anthropic user 块 tool_result / Gemini user part functionResponse）：
// 工具定义（ArkTS 禁结构化类型——与 SamplingParams 同款单一来源在本文件定义 export、
// AiTypes re-export；parametersJson = JSON Schema 原串，注册表侧校验，compose 内
// JSON.parse 成 schema 对象入请求体——失败跳过该工具不炸请求）
export interface AiToolDef {
  name: string;
  description: string;
  parametersJson: string;
}

// 助手侧工具调用（历史轮回传：assistant 消息携带 toolCalls / role='tool' 消息携带
// toolCallId+toolName——AiChatMessage 同名字段消费本类型）
export interface AiToolCall {
  id: string;
  name: string;
  argsJson: string;
}

// JSON Schema 原串 → 对象（compose 内 dialect 落点共用；坏串回 null = 调用侧跳过该工具
// ——注册表受控不会发生，防御兜底不炸请求）。空对象常量：argsJson 坏串时 tool_use.input /
// functionCall.args 的兜底（ArkTS 禁字面量空对象——arkts-no-untyped-obj-literals）
const EMPTY_SCHEMA_OBJ: Object = JSON.parse('{}') as Object;

function parseToolSchema(parametersJson: string): Object | null {
  try {
    const parsed: object = JSON.parse(parametersJson);
    return parsed !== null && typeof parsed === 'object' ? parsed : null;
  } catch (e) {
    return null;
  }
}

// 思考回传占位（2026-09-17）：模型未产出思考文本、但服务商要求带工具轮的思考载体在场时的
// 填充值——**单空格而非空串**（生态实测口径：缺键与空串都被判「未回传」，非空占位可过校验）
const REASONING_REPLAY_PLACEHOLDER: string = ' ';

// 会话思考在场判定（2026-09-17 空值回传守卫；chat 与 Responses 两 compose 共用）：本请求
// 已有任一 assistant 轮带思考（文本或保真项）⇒ 该会话处于思考模式 ⇒ 带工具轮的思考载体
// 不可缺。零思考会话（普通模型 / 未开思考）恒 false = 不给请求注入额外字段（零回归红线：
// 对不认 reasoning 字段的端点，凭空多出的键是风险，故只在「确实在思考会话里」才补）
function hasReasoningInHistory(messages: ComposeChatMessage[]): boolean {
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

// OpenAI chat/completions 请求体（对象字面量挂显式接口——坑59①）。
// 多模态：content 数组（图片块 image_url{url:dataURI} + 文本块 text，图前文后）；无图 = 纯字符串
interface OpenAiImageUrl { url: string }

interface OpenAiContentPart {
  type: string;
  text?: string;
  image_url?: OpenAiImageUrl;
}

interface OpenAiMessageItem {
  role: string;
  content: string | OpenAiContentPart[];
  reasoning_content?: string; // 历史思考回传（2026-09-01：仅 assistant 且 reasoning 非空才带；
  // DeepSeek/豆包/智谱等 OpenAI 兼容思考模式事实标准字段——官方文档「思考模式要求回传」，
  // RikkaHub includeHistoryReasoning 同口径；无工具调用的轮次回传无害，DeepSeek 文档明示
  //「无工具轮次回传则会被忽略」）
  tool_calls?: OpenAiToolCallItem[]; // assistant 工具调用回传（2026-09-02）
  tool_call_id?: string; // role='tool' 结果消息（2026-09-02；官方要求与 tool_calls.id 配对）
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

// 请求体 tools 声明（2026-09-02；官方 Chat Completions 形态）
interface OpenAiToolItem {
  type: string;
  function: OpenAiToolFunctionItem;
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
  // 用量统计帧开关（2026-09-06 用量采集）：官方 stream_options.include_usage——开启后
  // 流末追加一个 choices 空数组的 usage 统计帧；仅本方言需要（responses 自带、anthropic/
  // gemini 帧内自带，四方言其余三 compose 零改动）。个别中转站不认此键报 400 = 用户
  // body_overrides 自救通道覆盖（不加代码开关，任务书拍板）
  stream_options?: OpenAiStreamOptions;
  tools?: OpenAiToolItem[]; // 工具声明（2026-09-02；空 = 不发键零回归；tool_choice 缺省 auto）
  reasoning_effort?: string; // 思考档位（非空才带——官方枚举 low/high/max 随模型而异，透传）
  thinking?: OpenAiThinking; // 思考模式开关（开关方言画像域关闭思考专用 type:disabled——DeepSeek/GLM/Kimi 官方域同形，2026-09-06 两家官方文档查证）
  temperature?: number; // 采样覆盖（2026-09-01 高级设定；undefined = 不发送）
  top_p?: number;
  presence_penalty?: number;
  frequency_penalty?: number;
  max_tokens?: number; // 最大输出（>0 才发送；0 = 不限制 = 不发字段）
}

// stream_options 载荷（2026-09-06；官方唯一键 include_usage）
interface OpenAiStreamOptions {
  include_usage: boolean;
}

// 思考模式开关载体（DeepSeek 官方 Thinking Mode 文档 OpenAI 格式，GLM/Kimi 官方同形——
// 2026-09-06 两家官方文档查证；OpenAI 官方无此字段——仅 supportsThinkingOff 画像域传，见 AiTypes）
interface OpenAiThinking {
  type: string;
}

// Anthropic Messages 请求体（system 可选 = 无 system 消息时省略；键序：字面量建对象后
// 条件赋值 = JSON 尾部键）。多模态：content 块数组（image{source{base64}} + text）；无图 = 纯字符串
interface AnthropicImageSource { type: string; media_type: string; data: string }

// cache_control 载荷（官方 prompt-caching 规格：type 恒 'ephemeral'；ttl 省略 = 默认 5m，
// 显式 '1h' 才带键——2026-09-01 提示缓存）
interface AnthropicCacheControl {
  type: string;
  ttl?: string;
}

interface AnthropicContentBlock {
  type: string;
  text?: string;
  source?: AnthropicImageSource;
  cache_control?: AnthropicCacheControl; // 提示缓存断点挂点（2026-09-01：仅显式断点位设置）
  // 工具调用块（2026-09-02）：assistant 侧 tool_use / user 侧 tool_result
  id?: string; // tool_use：调用 id
  name?: string; // tool_use：函数名
  input?: Object; // tool_use：入参对象（官方要求 object 非字符串）
  tool_use_id?: string; // tool_result：配对的 tool_use.id
  content?: string; // tool_result：结果文本（官方接受 string 或块数组——本端仅 string）
}

// system 块形态（官方 system 接受 string | block 数组——打缓存的 system 断点须数组化，
// 末块挂 cache_control；2026-09-01 提示缓存）
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
  tools?: AnthropicToolItem[]; // 工具声明（2026-09-02；官方形态 input_schema）
  output_config?: AnthropicOutputConfig;
  reasoning?: AnthropicReasoning; // 思考模式开关（DeepSeek 官方域关闭思考专用：effort:none）
  temperature?: number; // 采样覆盖（官方域 0~1——组装层 clamp；undefined = 不发送）
  top_p?: number;
}

// 工具声明项（2026-09-02；官方 Messages tools 形态——input_schema 为 JSON Schema 对象）
interface AnthropicToolItem {
  name: string;
  description: string;
  input_schema: Object;
}

// 提示缓存参数（2026-09-01；唯一消费方 AnthropicChatStream.requestBody——AiConnection
// promptCache* 两字段映射至此；undefined = 不启用 = 请求体逐字节零回归）
export interface AnthropicCacheParam {
  enabled: boolean;
  ttlHour: boolean; // true = 显式 ttl '1h'；false = 默认 5m（省略 ttl 键——官方语义）
}

// 思考档位载体（官方现行规格 output_config.effort；与 OpenAI/Gemini 各自形态勿互抄）
interface AnthropicOutputConfig { effort: string }

// 思考模式开关载体（DeepSeek 官方 Thinking Mode 文档 Anthropic 格式；Anthropic 官方无此
// 字段——仅 supportsThinkingOff 域传，见 AiTypes）
interface AnthropicReasoning { effort: string }

// max_tokens 两档常量：未配置 = 8192 现状（恒定回落值）；显式 0〔不限制〕= 兜底 131072
//（128K，RikkaHub 同款实战值——上限较小的老模型可能 400，错误体走既有回显链不特判）
const ANTHROPIC_MAX_TOKENS: number = 8192;
const ANTHROPIC_MAX_TOKENS_UNLIMITED: number = 131072;

// Gemini GenerateContent 请求体（systemInstruction 可选；键序同 Anthropic = 尾部；role 事实值
// user/model）。多模态：parts 增 inline_data 段（官方 REST 文档蛇形键 inline_data/mime_type）
interface GeminiInlineData { mime_type: string; data: string }

interface GeminiPartItem {
  text?: string;
  inline_data?: GeminiInlineData;
  // 函数调用（2026-09-02）：model 侧 functionCall / user 侧 functionResponse（官方要求
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

interface GeminiFunctionResponseItem {
  name: string;
  response: GeminiFunctionResponseResult;
}

// 工具声明项（2026-09-02；官方 functionDeclarations 形态）
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
  tools?: GeminiToolItem[]; // 工具声明（2026-09-02；官方顶层 tools 数组）
}

// 思考档位载体（官方 generateContent REST：thinkingBudget 整数预算 + includeThoughts 才回传
// 思考摘要段；thinkingLevel 仅 Gemini 3+ 且旧模型传之报错——不用）
interface GeminiThinkingConfig {
  thinkingBudget: number;
  includeThoughts: boolean;
}

// 采样与思考共存（2026-09-01 高级设定）：全字段可选——仅开启项入 config（未开启不发键）
interface GeminiGenerationConfig {
  temperature?: number;
  topP?: number;
  presencePenalty?: number;
  frequencyPenalty?: number;
  maxOutputTokens?: number; // >0 才发送；0 = 不限制 = 不发字段
  thinkingConfig?: GeminiThinkingConfig;
}

// OpenAI：messages 原样进 body（system 是 messages 数组普通成员，不提取），stream 恒 true；
// thinking 非空 → 顶层 reasoning_effort（官方枚举透传）；★ 2026-08-31 关闭档（offEnabled
// = supportsThinkingOff 域）：off → 顶层 thinking{type:'disabled'}——与 reasoning_effort
// 互斥（官方 400「thinking options type cannot be disabled when reasoning_effort」，CSDN
// 实锤），分支排他；off 且非支持域 = 不产生任何字段（零回归）
export function composeOpenAiBody(model: string, messages: ComposeChatMessage[],
  thinking: string = '', offEnabled: boolean = false,
  sampling: SamplingParams | null = null, tools: AiToolDef[] = []): string {
  const items: OpenAiMessageItem[] = [];
  const sessionThinking: boolean = hasReasoningInHistory(messages); // 思考会话判据（见函数注释）
  for (const m of messages) {
    // role='tool' 结果消息（2026-09-02）：官方形态 {role:'tool', tool_call_id, content}
    if (m.role === 'tool') {
      items.push({ role: 'tool', content: m.content, tool_call_id: m.toolCallId ?? '' });
      continue;
    }
    const item: OpenAiMessageItem = { role: m.role, content: m.content };
    if (m.images !== undefined && m.images.length > 0) {
      // 带图：content = [image_url 块（data URI）..., text 块（content 非空才带）]
      const parts: OpenAiContentPart[] = [];
      for (const img of m.images) {
        parts.push({ type: 'image_url', image_url: { url: 'data:' + img.mimeType + ';base64,' + img.data } });
      }
      if (m.content !== '') { parts.push({ type: 'text', text: m.content }); }
      item.content = parts;
    }
    // 历史思考回传（2026-09-01 建；2026-09-17 补空值形态——见文件头 ②）：非空按原文挂
    // reasoning_content；空值但**本轮带工具声明 + 该轮有工具调用 + 会话已出现思考**时补
    // 占位（DeepSeek 校验口径 = 「带 tools 的请求后续必须完整回传 reasoning_content」，
    // 缺键与空串同被拒；三条件合取保证零思考会话与无工具轮零额外字段）
    if (m.role === 'assistant') {
      const reasoningText: string = m.reasoning !== undefined ? m.reasoning : '';
      if (reasoningText !== '') {
        item.reasoning_content = reasoningText;
      } else if (tools.length > 0 && sessionThinking &&
        m.toolCalls !== undefined && m.toolCalls.length > 0) {
        item.reasoning_content = REASONING_REPLAY_PLACEHOLDER;
      }
    }
    // assistant 工具调用回传（2026-09-02）：官方 tool_calls 数组（arguments 原串透传）
    if (m.role === 'assistant' && m.toolCalls !== undefined && m.toolCalls.length > 0) {
      const calls: OpenAiToolCallItem[] = [];
      for (const tc of m.toolCalls) {
        calls.push({ id: tc.id, type: 'function',
          function: { name: tc.name, arguments: tc.argsJson } });
      }
      item.tool_calls = calls;
    }
    items.push(item);
  }
  const reqBody: OpenAiChatRequest = {
    model: model,
    messages: items,
    stream: true,
    // 用量统计帧（2026-09-06 用量采集，恒开——统计为无开关功能；键序在 stream 后 =
    // JSON 尾部追加，sse-assert ⑪ 组产物断言随本笔同步扩）
    stream_options: { include_usage: true }
  };
  // 工具声明（2026-09-02）：官方 tools 数组；schema 坏串工具跳过（防御，注册表受控不达）
  if (tools.length > 0) {
    const apiTools: OpenAiToolItem[] = [];
    for (const t of tools) {
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
  return JSON.stringify(reqBody);
}

// Anthropic：system 消息提出为顶层 system 字段（多条以 \n\n 连接——官方非流式/流式同款
// 语义），其余消息 role 原样（user/assistant）；max_tokens 必填，三态见下方实现处注释
//（未配置 8192 现状 / 显式 0〔不限制〕兜底 131072 / 正数用值——原「恒 8192」为 2026-09-01
// 采样参数笔前的旧口径残留，2026-09-13 全码优化笔1 核正）；stream 恒 true；
// 无 system 消息时省略 system 字段。★ 2026-08-31 关闭档（offEnabled = supportsThinkingOff
// 域）：off → 顶层 reasoning{effort:'none'}（DeepSeek 官方 Thinking Mode 文档 Anthropic
// 格式；Anthropic 官方端点不认此字段——非支持域不产字段零回归）；与 output_config
// 分支排他（关闭与力度不同时给）
export function composeAnthropicBody(model: string, messages: ComposeChatMessage[],
  thinking: string = '', offEnabled: boolean = false,
  sampling: SamplingParams | null = null, cache?: AnthropicCacheParam,
  tools: AiToolDef[] = []): string {
  // system 提取（system 不进 messages 数组，走顶层字段）；user/assistant 原样；
  // role='tool' 结果消息（2026-09-02）= 连续段并成一条 user 消息，content 为 tool_result
  // 块数组（官方工具结果以 user 角色回传；连续多条并一消息满足交替约束）
  const chatItems: AnthropicMessageItem[] = [];
  const systemParts: string[] = [];
  let pendingToolResults: AnthropicContentBlock[] | null = null;
  const flushToolResults = (): void => {
    if (pendingToolResults !== null) {
      chatItems.push({ role: 'user', content: pendingToolResults });
      pendingToolResults = null;
    }
  };
  for (const m of messages) {
    if (m.role === 'system') {
      flushToolResults();
      systemParts.push(m.content);
    } else if (m.role === 'tool') {
      if (pendingToolResults === null) {
        pendingToolResults = [];
      }
      pendingToolResults.push({ type: 'tool_result', tool_use_id: m.toolCallId ?? '',
        content: m.content });
    } else if (m.role === 'assistant' && m.toolCalls !== undefined && m.toolCalls.length > 0) {
      // assistant 工具调用轮（2026-09-02）：content 块数组 = 文本块（非空才带）+ tool_use 块族
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
      // 带图：content = [image 块（source{base64,media_type,data}）..., text 块（非空才带）]
      flushToolResults();
      const blocks: AnthropicContentBlock[] = [];
      for (const img of m.images) {
        blocks.push({ type: 'image', source: { type: 'base64', media_type: img.mimeType, data: img.data } });
      }
      if (m.content !== '') { blocks.push({ type: 'text', text: m.content }); }
      chatItems.push({ role: m.role, content: blocks });
    } else {
      flushToolResults();
      chatItems.push({ role: m.role, content: m.content });
    }
  }
  flushToolResults();
  // 提示缓存（2026-09-01；undefined/未启用 = 全支跳过 = 请求体逐字节零回归）：
  // 落点① system 块数组末块 + ② 倒数第二条 user 末块；TTL 单值恒满足官方顺序约束
  //（依据与无 tools 说明见文件头 ▲ 注释）
  const cacheCtrl: AnthropicCacheControl | undefined = cache !== undefined && cache.enabled ?
    (cache.ttlHour ? { type: 'ephemeral', ttl: '1h' } : { type: 'ephemeral' }) : undefined;
  if (cacheCtrl !== undefined) {
    // ② messages 断点：倒数第二条 user（09-02 起工具轮回传 = role='tool' 结果行并入
    // user + tool_result 块数组，「user」语义已含工具结果消息——命中时断点落其末块，
    // 就地挂 cache_control 不损字段，见下方分支注释；不足两条 = 不插）。
    // content 字符串 → 数组化 [{type:'text',...}]；块数组 → 末块挂点
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
        // ★ 就地挂 cache_control（2026-09-14 全面自检第3轮笔1 修复，64 组断言）：原为重建
        // 对象 { type, text, source, cache_control }——09-02 起工具轮回传使「user 消息」
        // 语义扩为含工具结果行（role='tool' 连续段并成 user + tool_result 块数组），倒二
        // user 命中工具结果消息时末块 = tool_result 块，重建丢 tool_use_id 与 content，
        // 官方 400「tool_result 块缺 tool_use_id」（历史含 ≥2 段工具循环后每轮请求必触发，
        // 该会话在开缓存的 anthropic 连接下不可用）。块字段全可选就地赋值零拷贝，任意块
        // 类型（text/image/tool_result）字段零丢失
        const blocks: AnthropicContentBlock[] = item.content;
        blocks[blocks.length - 1].cache_control = cacheCtrl;
      }
    }
  }
  // max_tokens 三态（必填字段）：未配置 = 8192 现状；显式 0〔不限制〕= 兜底 131072；
  // 正数 = 用值
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
    if (cacheCtrl !== undefined) {
      // ① system 断点：块数组形态末块挂 cache_control（官方 system 双形态——数组化仅
      // 在打缓存时发生，关缓存保持 string 形态逐字节零回归）
      const sysBlocks: AnthropicSystemBlock[] = [];
      for (const part of systemParts) {
        sysBlocks.push({ type: 'text', text: part });
      }
      sysBlocks[sysBlocks.length - 1] = { type: 'text',
        text: sysBlocks[sysBlocks.length - 1].text, cache_control: cacheCtrl };
      req.system = sysBlocks;
    } else {
      req.system = systemParts.join('\n\n');
    }
  }
  // 工具声明（2026-09-02）：官方 tools 数组（input_schema 为 JSON Schema 对象）；schema
  // 坏串工具跳过。★ 提示缓存 tools 断点（官方允许末工具挂 cache_control）暂不产——
  // aicontrol 工具集小（≤数条）缓存收益低，需要时在此补末位挂点（依据记录在此）
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
// 提为 systemInstruction.parts（官方顶层字段）；role 映射 assistant → model（Gemini 方言，
// user 原样）；内容统一 parts[{text}] 包装；无 stream 字段（SSE 由 alt=sse 查询参开启）
export function composeGeminiBody(messages: ComposeChatMessage[], thinking: string = '',
  sampling: SamplingParams | null = null, tools: AiToolDef[] = []): string {
  // role 映射：assistant → model（Gemini 方言）；system 提为 systemInstruction；
  // role='tool' 结果消息（2026-09-02）= 连续段并成一条 user content，parts 为
  // functionResponse 段族（官方以 user 角色回传函数结果）
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
    if (m.role === 'system') {
      flushToolParts();
      systemParts.push({ text: m.content });
    } else if (m.role === 'tool') {
      if (pendingToolParts === null) {
        pendingToolParts = [];
      }
      pendingToolParts.push({ functionResponse: { name: m.toolName ?? '',
        response: { result: m.content } } });
    } else if (m.role === 'assistant' && m.toolCalls !== undefined && m.toolCalls.length > 0) {
      // model 函数调用轮（2026-09-02）：parts = 文本段（非空才带）+ functionCall 段族
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
      // 带图：parts = [inline_data 段..., text 段（content 非空才带）]
      flushToolParts();
      const parts: GeminiPartItem[] = [];
      for (const img of m.images) {
        parts.push({ inline_data: { mime_type: img.mimeType, data: img.data } });
      }
      if (m.content !== '') { parts.push({ text: m.content }); }
      contents.push({ role: m.role === 'assistant' ? 'model' : m.role, parts: parts });
    } else {
      flushToolParts();
      contents.push({
        role: m.role === 'assistant' ? 'model' : m.role,
        parts: [{ text: m.content }]
      });
    }
  }
  flushToolParts();
  // ★ Gemini 末条降级守卫：官方要求末条必须 user（末条非 user = 400）。正常对话守卫空转；
  // 仅防御异常序列（历史末条 assistant 死数据 + assistant 注入成为末条等）：结尾连续 model
  // 段并入最后一条 user（'\n\n'）并移除（P2-5：降级语义写入本注释）。全 model 无 user 的
  // 畸形序列保留原样（不伪造 user；协议层显式报错）。
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
      const tails: string[] = [];
      for (let i = lastUser + 1; i < contents.length; i++) {
        tails.push(contents[i].parts.map((p: GeminiPartItem): string => p.text ?? '').join('\n\n'));
      }
      contents[lastUser] = {
        role: 'user',
        parts: [{
          text: contents[lastUser].parts.map((p: GeminiPartItem): string => p.text ?? '').join('\n\n') +
            '\n\n' + tails.join('\n\n')
        }]
      };
      contents.splice(lastUser + 1);
    }
  }
  const req: GeminiGenerateRequest = { contents: contents };
  if (systemParts.length > 0) {
    req.systemInstruction = { parts: systemParts };
  }
  // 工具声明（2026-09-02）：官方 tools=[{functionDeclarations}]；schema 坏串工具跳过
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
  // generationConfig：思考档位与采样覆盖共存合入（任一开启才建；键序 = 采样在前
  // thinkingConfig 尾部——无采样路径与原结构逐字段一致，既有断言零回归）
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

// OpenAI Responses API 请求体（2026-08-30 Responses 适配）：/v1/responses（stream=true）——
// 官方 input 兼容 [{role,content}] 形态（system 不进 input——instructions 是顶层指导位）；
// system 消息多条 \n\n 连接提为顶层 instructions（无 system 省略字段，照 Anthropic 先例）；
// ★ 显式 store: false——官方默认 store:true（服务端存储上下文），项目「本地管理上下文」
// 原则显式关闭（隐私红线）。键序照 Anthropic 先例：字面量建对象后条件赋值 = 尾部键
interface OpenAiResponsesRequest {
  model: string;
  input: ResponsesMessageItem[];
  instructions?: string;
  stream: boolean;
  store: boolean;
  tools?: ResponsesToolItem[]; // 工具声明（2026-09-02；官方扁平形态 name/parameters 直挂）
  reasoning?: OpenAiResponsesReasoning;
  // encrypted reasoning 保真开关（2026-09-06 Responses 修复）：true = 请求带
  // include:['reasoning.encrypted_content']——官方 stateless 工具轮要求（reasoning item
  // 回传须 encrypted_content 保真）；仅 OpenAI 官方端点开（AiTypes.isOfficialOpenAiBaseUrl
  // 判定，第三方网关不支持此 include）
  include?: string[];
  temperature?: number; // 采样覆盖（官方 Responses 无 penalties 字段——不发）
  top_p?: number;
  max_output_tokens?: number; // >0 才发送；0 = 不限制 = 不发字段
}

// 工具声明项（2026-09-02；官方 Responses tools 扁平形态——与 chat 的嵌套 function 不同）
interface ResponsesToolItem {
  type: string;
  name: string;
  description: string;
  parameters: Object;
}

// 思考档位载体（Responses 接口 reasoning 对象形态——与 chat 的顶层 reasoning_effort 不同）
interface OpenAiResponsesReasoning { effort: string }

// Responses 多模态 content part：input_image 的 image_url 为**直串 data URI**（与 chat 的
// 嵌套 {url} 形态不同——官方两接口各自形态，勿互抄）；文本块 input_text
// ★ 2026-09-17：reasoning item 的明文内容块复用本形态（type='reasoning_text' + text——
// 与官方 Create Response 规格同构，不再单开同构接口以免 ArkTS 结构化类型禁令触雷）
interface ResponsesContentPart {
  type: string;
  text?: string;
  image_url?: string;
}

interface ResponsesMessageItem {
  role?: string;
  content?: string | ResponsesContentPart[];
  // 工具调用 item（2026-09-02）：官方 input 数组混合形态——function_call（assistant 轮）
  // / function_call_output（工具结果），两者皆无 role（type 自别）
  type?: string;
  call_id?: string;
  name?: string;
  arguments?: string;
  output?: string;
  // reasoning item（2026-09-06 Responses 修复）：stateless 工具轮回传保真——id +
  // encrypted_content 原样（官方「must retain reasoning items」；裸 reasoning 文本不合法）
  id?: string;
  encrypted_content?: string;
}

export function composeOpenAiResponsesBody(model: string, messages: ComposeChatMessage[],
  thinking: string = '', sampling: SamplingParams | null = null,
  tools: AiToolDef[] = [], reasoningInclude: boolean = false): string {
  // system 提取（system 走 instructions，不进 input 数组）；user/assistant 原样；
  // assistant 工具调用轮（2026-09-02）= message item（文本非空才带）+ function_call item 族；
  // role='tool' = function_call_output item（官方要求全部 function_call 先于其 output）。
  // ★ reasoning item 回传（2026-09-06 建 / 2026-09-17 补明文形态）：官方端点 stateless 工具轮
  // 要求 function_call 前有其配对 reasoning item（缺失 400 实锤；第三方端点同要求，只是载体
  // 形态为明文）——回放序 = reasoning item 先于 message/function_call（RikkaHub
  // addAssistantItems 同序），载体二选一与占位规则见下方分支注释与文件头 ▲ 2026-09-17
  const input: ResponsesMessageItem[] = [];
  const systemParts: string[] = [];
  const sessionThinking: boolean = hasReasoningInHistory(messages); // 思考会话判据（见函数注释）
  for (const m of messages) {
    if (m.role === 'system') {
      systemParts.push(m.content);
      continue;
    }
    if (m.role === 'tool') {
      input.push({ type: 'function_call_output', call_id: m.toolCallId ?? '', output: m.content });
      continue;
    }
    if (m.role === 'assistant' && m.toolCalls !== undefined && m.toolCalls.length > 0) {
      // reasoning item 回放（★ 序红线 = 先于 message item 与 function_call item——官方输入
      // 序即输出序；服务端实测校验该序，反序同样 400）：
      // ① 捕获到官方保真项（id+encrypted_content，仅 OpenAI 官方端点有）→ 原样回传
      //    （09-06 形态逐字节不变）；
      // ② 未捕获但会话在思考模式 → 明文 reasoning item（2026-09-17 修复：DeepSeek 等第三方
      //    Responses 端点官方输入规格 = content 为 reasoning_text 块列表；此前恒不回传 =
      //    工具轮续轮必 400「must be passed back」）；思考文本空 = 补占位（载体缺席即被拒）
      if (m.reasoningItems !== undefined && m.reasoningItems.length > 0) {
        for (const ri of m.reasoningItems) {
          input.push({ type: 'reasoning', id: ri.id, encrypted_content: ri.encryptedContent });
        }
      } else if (sessionThinking) {
        const reasoningText: string = m.reasoning !== undefined && m.reasoning !== '' ?
          m.reasoning : REASONING_REPLAY_PLACEHOLDER;
        input.push({ type: 'reasoning',
          content: [{ type: 'reasoning_text', text: reasoningText }] });
      }
      if (m.content !== '') {
        input.push({ role: 'assistant', content: m.content });
      }
      for (const tc of m.toolCalls) {
        input.push({ type: 'function_call', call_id: tc.id, name: tc.name, arguments: tc.argsJson });
      }
      continue;
    }
    if (m.images !== undefined && m.images.length > 0) {
      // 带图：content = [input_image 块..., input_text 块（非空才带）]
      const parts: ResponsesContentPart[] = [];
      for (const img of m.images) {
        parts.push({ type: 'input_image', image_url: 'data:' + img.mimeType + ';base64,' + img.data });
      }
      if (m.content !== '') { parts.push({ type: 'input_text', text: m.content }); }
      input.push({ role: m.role, content: parts });
    } else {
      input.push({ role: m.role, content: m.content });
    }
  }
  const req: OpenAiResponsesRequest = {
    model: model,
    input: input,
    stream: true,
    store: false
  };
  // 工具声明（2026-09-02）：官方扁平 tools 数组；schema 坏串工具跳过
  if (tools.length > 0) {
    const apiTools: ResponsesToolItem[] = [];
    for (const t of tools) {
      const schema: Object | null = parseToolSchema(t.parametersJson);
      if (schema === null) {
        continue;
      }
      apiTools.push({ type: 'function', name: t.name, description: t.description,
        parameters: schema });
    }
    if (apiTools.length > 0) {
      req.tools = apiTools;
      // encrypted reasoning 请求开关（2026-09-06）：官方 stateless 工具轮回传保真的前置——
      // 无 include 则流中 reasoning item 不带 encrypted_content，回传链无从谈起；与工具
      // 声明同门（无工具 = 无工具轮 = 无回传面，不发）
      if (reasoningInclude) {
        req.include = ['reasoning.encrypted_content'];
      }
    }
  }
  if (systemParts.length > 0) {
    req.instructions = systemParts.join('\n\n');
  }
  if (thinking !== '') {
    req.reasoning = { effort: thinking };
  }
  // 采样覆盖（官方 Responses 接口无 presence/frequency penalty 字段——不发；
  // maxOutput 0 = 不限制 = 不发字段）
  if (sampling !== null) {
    if (sampling.temperature !== undefined) {
      req.temperature = sampling.temperature;
    }
    if (sampling.topP !== undefined) {
      req.top_p = sampling.topP;
    }
    if (sampling.maxOutput !== undefined && sampling.maxOutput > 0) {
      req.max_output_tokens = sampling.maxOutput;
    }
  }
  return JSON.stringify(req);
}

// Gemini 思考预算映射（档位 → thinkingBudget 整数）：取值在全 2.5 系合法范围内——
// 1024 ≥ flash-lite 下限 512 / 24576 ≤ 全系上限（Pro 上限 32768 但取全系交集）；'' 不经此
// （compose 侧已守卫）；脏值兜底 max 档（UI 选项集固定四值，脏值不可达）
export function geminiThinkingBudget(tier: string): number {
  if (tier === 'low') {
    return 1024;
  }
  if (tier === 'high') {
    return 8192;
  }
  return 24576; // 'max'
}

