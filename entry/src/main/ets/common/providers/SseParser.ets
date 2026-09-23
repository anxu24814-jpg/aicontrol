// SSE 攒帧解析（2026-08-29 任务书 M1 新增；2026-08-30 三协议扩展）：OpenAI 兼容流式的
// 分帧 + data 载荷提取 + 增量字段解析，及 Anthropic/Gemini 两原生协议的载荷解析纯函数。
// ★ 本文件零 import、只用 erasable TS 语法（无 enum/namespace/装饰器）——scripts/sse-assert.mjs
// 把本文件复制为 .ts 由 node 类型剥离直跑，断言的就是线上同一实现（禁双实现漂移）。
// 2026-09-06 token 用量采集：AiUsageDelta 归一类型 + mergeUsage 流内 take-max 合并 +
// 四 parse 各自提取 usage 统计帧（chat 尾帧 / anthropic message_start·message_delta /
// gemini usageMetadata / responses completed 自带；形态与官方依据见各接口注释）。
// 2026-09-10 缓存命中：AiUsageDelta + cachedTokens 可选字段（全量输入中命中缓存的部分，
// >0 才挂键）；chat 三级兜底（OpenAI 嵌套 → Moonshot 顶层 → DeepSeek 专有）+ anthropic
// 全量加法修正（input_tokens 不含 cache 两桶，prompt 升格全量输入）——依据与拍板见
// docs/方案-缓存命中输入用量显示-20260910.md §二/§六。
// 攒帧语义（SSE 规范 + OpenAI 兼容方言实测惯例）：
// · 事件 = 若干 data: 行 + 空行收尾；多 data 行以 \n 合并（OpenAI 实际单行，合并兜底）；
// · 行结尾兼容 \n 与 \r\n；':' 开头为注释/心跳行，忽略；event:/id:/retry: 字段用不上，忽略
//   （Anthropic 的 event: 行同理忽略——事件类型在 data JSON 的 type 字段里，帧路由不看 event: 行）；
// · 跨 TCP 分片的半截行攒在 tail，下片补齐再判；finish() 冲刷流尾无换行收尾的末行与未决事件。

// 单帧解析产物：正文增量与思考链增量（DeepSeek 风格 delta.reasoning_content 事实标准，
// vLLM/DeepInfra 等同款；无该字段的 provider 天然为空串，调用方据此隐藏思考块）。
// 2026-09-02 工具调用：+ toolCalls 可选（流式工具调用增量——四协议方言在此归一为同一
// 形态，聚合在 ChatSendCtrl.ToolCallAccumulator；无工具调用的帧不设键 = 存量行为零回归）
// 2026-09-06 token 用量采集：+ usage 可选（usage 统计帧归一形态，见 AiUsageDelta——
// 挂在「无增量」帧上不触发正文回调，消费方在流层经 absorbUsage 累积）
// 2026-09-06 Responses 修复：+ reasoningItems 可选（Responses reasoning 输出项捕获——
// id + encrypted_content 保真回传料，OpenAI 官方 reasoning 模型工具轮要求；仅 responses
// 路径设置，其余三协议恒无键零回归）
// ★ 2026-09-23 输出上限治理笔 2：+ truncated 可选（**仅真截断时挂键**——输出被输出上限
// 掐断的标记帧；无键 = 存量行为逐字节零回归，同上两可选键先例）。四协议标记位置：
// openai chat `choices[0].finish_reason === 'length'` / anthropic `message_delta` 帧的
// `delta.stop_reason === 'max_tokens'` / gemini `candidates[0].finishReason === 'MAX_TOKENS'` /
// responses `response.incomplete` + `incomplete_details.reason === 'max_output_tokens'`。
// 依据 = 「思考 token 与正文共享同一输出上限」的平台事实（四家一致，见任务书 §0.1）——
// 打满即正文空/半截，故该标记是回答质量信号而非错误信号（kind 语义不变，照 usage 同路
// 由流层吸收）；完整取证与判据收窄依据（过滤类不挂键）见任务书 §0.4/§3.2.1
export interface SseDelta {
  content: string;
  reasoningContent: string;
  toolCalls?: SseToolDelta[];
  usage?: AiUsageDelta;
  reasoningItems?: AiReasoningItem[];
  truncated?: boolean;
}

// Responses reasoning 输出项捕获形态（2026-09-06）：OpenAI 官方 stateless 模式要求工具轮
// 的 function_call item 回传时携带其配对 reasoning item（官方 Reasoning 指南「must retain
// reasoning items across turns」；缺失/乱序 = 400 "provided without its required 'reasoning
// item"——Cline/Codex/Agents SDK 生态实锤）。保真回传须 encrypted_content（裸 reasoning 文本
// 不构成合法 item），故捕获条件 = item 带 id 且带 encrypted_content。定义在本文件
//（SseDelta 引用 + 零 import 断言面），AiTypes re-export 供上层消费（AiUsageDelta 先例）
export interface AiReasoningItem {
  id: string;
  encryptedContent: string;
}

// token 用量归一形态（2026-09-06 用量采集；四协议方言在此归一——openai chat
// usage.prompt_tokens/completion_tokens、responses usage.input_tokens/output_tokens、
// anthropic message_start/delta 两帧、gemini usageMetadata 两计数字段）。定义在本文件
// （SseDelta 引用它 + 零 import 断言面），AiTypes re-export 供上层消费
//（SamplingParams 先例同款姿势）。字段语义 = 本帧所见瞬时值，跨帧/跨流合并在
// mergeUsage（流内 take-max）与 ChatSendCtrl 轮次累积器（跨流求和）
// 2026-09-10 缓存命中：+ cachedTokens 可选（全量输入中命中缓存的部分，>0 才挂键——
// 无缓存协议/短对话不出现该键，旧构造点零改动）；promptTokens 语义升格「全量输入」
//（chat/responses/gemini 现状已含命中不动，anthropic 侧改为 input+cache_read+
// cache_creation 三桶相加——官方 input_tokens 不含 cache 两桶，只取首桶会显示偏小）
export interface AiUsageDelta {
  promptTokens: number;
  completionTokens: number;
  cachedTokens?: number;
}

// 流内多帧 usage 合并（2026-09-06；Cube 01 卷 A3 mergeStreamUsage take-max 口径）：
// 同一流内 usage 可能分帧出现（anthropic message_start 给 input、message_delta 给累积
// output；gemini 部分网关每帧带累积 usageMetadata）——各字段**取大**合并（累积值后帧
// ≥ 前帧；openai chat 尾帧单帧全量天然兼容）。任一方 null 回另一方；双方 null 回 null。
// 2026-09-10 缓存命中：cachedTokens 同走 take-max（anthropic 首帧一次性给值、后帧
// undefined；gemini 累积——取大保住已见值，任一方 >0 即带键）
// 零依赖纯函数 = sse-assert 断言面（㉚/56 组），传输层 ChatStreamBase.absorbUsage 消费
export function mergeUsage(base: AiUsageDelta | null, incoming: AiUsageDelta | null): AiUsageDelta | null {
  if (base === null) {
    return incoming;
  }
  if (incoming === null) {
    return base;
  }
  const merged: AiUsageDelta = {
    promptTokens: base.promptTokens > incoming.promptTokens ? base.promptTokens : incoming.promptTokens,
    completionTokens: base.completionTokens > incoming.completionTokens ?
      base.completionTokens : incoming.completionTokens
  };
  const baseCached: number = base.cachedTokens ?? 0;
  const incomingCached: number = incoming.cachedTokens ?? 0;
  if (baseCached > 0 || incomingCached > 0) {
    merged.cachedTokens = baseCached > incomingCached ? baseCached : incomingCached;
  }
  return merged;
}

// 工具调用增量（2026-09-02 工具调用底层；四协议归一形态）：
// · index = 流内序位（openai tool_calls.index / anthropic content block index / responses
//   output_index；gemini functionCall 无序位概念恒 -1——调用方按「整调用追加」处理）；
// · id = 调用 id（openai 首帧携带 / anthropic content_block_start / responses call_id；
//   gemini 无——聚合器自生成）；name/nameFull = 函数名；argsDelta/argsFull = 参数；
// · ★ name/nameFull 两型（2026-09-06 修复「search_helpsearch_help」重名循环）：name =
//   分片拼接式（openai chat 事实形态——首帧片段续片累拼，聚合器 +=）；nameFull = 全量
//   替换式（responses added/done 两事件各携带完整名，聚合器 += 会拼出「search_help」
//   ×2 重名 → 命不中本轮声明集 →「未在本轮启用」错误 → 模型重试 → 循环至轮上限——
//   真机 bugtest 转录实锤）；argsDelta = 参数 JSON 串增量（拼接式：openai
//   function.arguments / anthropic partial_json / responses function_call_arguments.delta）；
//   argsFull = 参数 JSON 串全量（替换式：gemini functionCall.args / responses
//   output_item.done 的完整 arguments——聚合器以它覆盖并标记整调用完成）
export interface SseToolDelta {
  index: number;
  id?: string;
  name?: string;
  nameFull?: string;
  argsDelta?: string;
  argsFull?: string;
}

// chat/completions 流式帧结构（只声明消费的字段，其余忽略——JSON.parse 强转兜底）
export interface ChatChunkDelta {
  content?: string;
  reasoning_content?: string;
  role?: string;
  tool_calls?: ChatChunkToolCall[]; // 工具调用增量（2026-09-02；按 index 聚合在调用方）
}

// 工具调用增量块（只声明消费的字段——name/arguments 可能分片，聚合在调用方）
export interface ChatChunkToolCall {
  index?: number;
  id?: string;
  function?: ChatChunkToolFunction;
}

export interface ChatChunkToolFunction {
  name?: string;
  arguments?: string;
}

export interface ChatChunkChoice {
  delta?: ChatChunkDelta;
  index?: number;
  finish_reason?: string;
}

// usage 统计块（2026-09-06 用量采集；流被中断则收不到）。携带形态两家：OpenAI 式 =
// include_usage 开启后流末追加独立统计帧（choices 恒空数组）；DeepSeek 式 = 官方文档明示
// 无独立 usage-only 帧，统计挂末条内容帧同帧携带（choices 恰 1 元素、无新内容、
// finish_reason 非空）——两形态解析同收（2026-09-06 深夜修复前 DS 形态被丢，见
// parseChatDelta 头注释）
// 2026-09-10 缓存命中：+ 三个方言变体字段（prompt_tokens 已含命中部分——OpenAI 官方
// 语义，cached 只是其中标注）——OpenAI 嵌套 prompt_tokens_details.cached_tokens /
// Moonshot 顶层 cached_tokens / DeepSeek 专有 prompt_cache_hit_tokens，提取走
// chatCachedTokens 三级兜底（只认嵌套时后两家恒 0——RikkaHub #1576/#1584 实锤）
export interface ChatChunkUsage {
  prompt_tokens?: number;
  completion_tokens?: number;
  prompt_tokens_details?: ChatPromptTokensDetails;
  cached_tokens?: number;
  prompt_cache_hit_tokens?: number;
}

// OpenAI chat 官方嵌套命中标注块（2026-09-10）
export interface ChatPromptTokensDetails {
  cached_tokens?: number;
}

export interface ChatChunk {
  choices?: ChatChunkChoice[];
  usage?: ChatChunkUsage; // 统计帧载荷（其余帧 usage:null = typeof 非 number 忽略）
}

// OpenAI 兼容错误信封（非 200 响应体：{"error":{"message":...}}）
export interface ChatErrorEnvelope {
  error?: ChatErrorBody;
}

export interface ChatErrorBody {
  message?: string;
  type?: string;
  code?: string;
}

export class SseParser {
  private tail: string = ''; // 未凑够一行的残余（跨分片半截行）
  private dataParts: string[] = []; // 当前事件已收 data 行（空行收尾时合并派发）

  // 喂入一段已解码文本，返回本段凑齐的事件载荷序列（每个元素 = 一个 data: 事件的完整载荷）
  feed(chunk: string): string[] {
    const out: string[] = [];
    this.tail += chunk;
    let nl: number = this.tail.indexOf('\n');
    while (nl >= 0) {
      const line: string = this.tail.substring(0, nl);
      this.tail = this.tail.substring(nl + 1);
      this.consumeLine(line, out);
      nl = this.tail.indexOf('\n');
    }
    return out;
  }

  // 流收尾冲刷：末行无换行也算一行；未决事件（缺空行收尾）同样派发——
  // 截断帧在此暴露为「不完整载荷」，由 parseChatDelta 容错判废
  finish(): string[] {
    const out: string[] = [];
    if (this.tail !== '') {
      const line: string = this.tail;
      this.tail = '';
      this.consumeLine(line, out);
    }
    if (this.dataParts.length > 0) {
      out.push(this.dataParts.join('\n'));
      this.dataParts = [];
    }
    return out;
  }

  private consumeLine(line: string, out: string[]): void {
    let text: string = line;
    if (text.endsWith('\r')) {
      text = text.substring(0, text.length - 1);
    }
    if (text === '') {
      // 空行 = 事件收尾：有 data 才派发（连续空行/纯注释段不产生空载荷）
      if (this.dataParts.length > 0) {
        out.push(this.dataParts.join('\n'));
        this.dataParts = [];
      }
      return;
    }
    if (text.startsWith(':')) {
      return; // 注释/心跳行
    }
    if (text.startsWith('data:')) {
      let payload: string = text.substring(5);
      if (payload.startsWith(' ')) {
        payload = payload.substring(1); // SSE 规范：data: 后最多剥一个空格
      }
      this.dataParts.push(payload);
    }
  }
}

// usage 数字对守卫归一（2026-09-06 四方言共用）：任一字段非 number 视为缺（补 0——
// take-max 与求和口径下 0 无害）；两值全缺 = 无 usage 回 undefined。坏值容错照既有
// 坏帧口径（typeof 守卫，不炸不静默成错误值）
// 2026-09-10 缓存命中：+ 第三可选参 cached（>0 才归入返回值）；判废条件改「三值全缺」
//（可选参 = 既有 4 调用点与断言面零破坏）
export function usageFrameOf(prompt: number | undefined, completion: number | undefined,
  cached?: number): AiUsageDelta | undefined {
  const p: number = typeof prompt === 'number' && Number.isFinite(prompt) && prompt > 0 ? prompt : 0;
  const c: number = typeof completion === 'number' && Number.isFinite(completion) && completion > 0 ?
    completion : 0;
  const k: number = typeof cached === 'number' && Number.isFinite(cached) && cached > 0 ? cached : 0;
  if (p === 0 && c === 0 && k === 0) {
    return undefined;
  }
  const frame: AiUsageDelta = { promptTokens: p, completionTokens: c };
  if (k > 0) {
    frame.cachedTokens = k;
  }
  return frame;
}

// chat 方言缓存命中三级兜底（2026-09-10）：OpenAI 嵌套 → Moonshot 顶层 → DeepSeek
// 专有——同一 dialect 内的厂商字段拼写差异用一个兜底链收完（不 per-provider 分支，
// 坑 18「只适配协议规格不逐厂商特判」同构；RikkaHub #1576 只认嵌套时 Moonshot/DeepSeek
// 用户恒 0，PR #1584 加兜底才修好）。非空 number 才认，脏值由 usageFrameOf 守卫兜
function chatCachedTokens(usage: ChatChunkUsage): number | undefined {
  const nested: ChatPromptTokensDetails | undefined = usage.prompt_tokens_details;
  if (nested !== undefined && nested !== null && typeof nested.cached_tokens === 'number') {
    return nested.cached_tokens;
  }
  if (typeof usage.cached_tokens === 'number') {
    return usage.cached_tokens;
  }
  if (typeof usage.prompt_cache_hit_tokens === 'number') {
    return usage.prompt_cache_hit_tokens;
  }
  return undefined;
}

// 单帧载荷 → 增量。坏帧容错：JSON 截断/非法帧返回 null（上游计数跳过，不阻断流）；
// [DONE] 由调用方先判，不进本函数。
// 2026-09-06 用量采集：任一帧的 usage 数字字段提取归一 AiUsageDelta（数据帧 usage:null
// 天然不挂键）；usage 两形态同收——独立统计帧（choices 空，OpenAI 式）走 empty 兜底带回，
// 挂末条内容帧（choices 非空，DeepSeek 官方形态）随 result 带回。★ 同日深夜修复：后者
// 此前被 result 分支丢弃 = ds/comp「completion 无用量」真根因（km/comp 发独立统计帧故
// 一直正常；「端侧不回传」初判经 DS 官方文档复核推翻）
export function parseChatDelta(payload: string): SseDelta | null {
  let chunk: ChatChunk;
  try {
    chunk = JSON.parse(payload) as ChatChunk;
  } catch (e) {
    return null;
  }
  const empty: SseDelta = { content: '', reasoningContent: '' };
  const frameUsage: AiUsageDelta | undefined = chunk.usage !== undefined && chunk.usage !== null ?
    usageFrameOf(chunk.usage.prompt_tokens, chunk.usage.completion_tokens,
      chatCachedTokens(chunk.usage)) : undefined;
  if (frameUsage !== undefined) {
    empty.usage = frameUsage;
  }
  const choices: ChatChunkChoice[] | undefined = chunk.choices;
  // null 守卫（2026-09-06 自检轮）：个别代理发 "choices":null——JSON null 过 !== undefined 判
  // 后 .length 即抛；按无 choices 合法帧收（usage 批 usage:null 同族守卫先例）
  if (choices === undefined || choices === null || choices.length === 0) {
    return empty; // 首帧仅 role / Usage 统计帧等无 choices 形态，合法但无增量
  }
  // 截断标记（2026-09-23 输出上限治理笔 2）：finish_reason='length' = 输出被 max_tokens 打满
  //（思考 + 正文共享预算，见文件头与任务书 §0.1）。★ 两出口都要覆盖——该帧的 delta 常为 {}
  // 或缺失（走下方早返回），故在 choices 非空后即判并同时挂 empty
  const truncated: boolean = choices[0].finish_reason === 'length';
  if (truncated) {
    empty.truncated = true;
  }
  const delta: ChatChunkDelta | undefined = choices[0].delta;
  if (delta === undefined || delta === null) {
    return empty;
  }
  const result: SseDelta = {
    content: typeof delta.content === 'string' ? delta.content : '',
    reasoningContent: typeof delta.reasoning_content === 'string' ? delta.reasoning_content : ''
  };
  if (truncated) {
    result.truncated = true; // 正常出口同样带出（同帧既有内容又有 finish_reason 的方言）
  }
  // usage 挂末条内容帧形态（DeepSeek 官方文档：无独立 usage-only 帧，统计随末帧同帧
  // 携带）——2026-09-06 深夜修复前本分支丢 frameUsage，ds/comp 全程收不到用量
  if (frameUsage !== undefined) {
    result.usage = frameUsage;
  }
  // 工具调用增量（2026-09-02）：delta.tool_calls 逐项归一 SseToolDelta（index 缺省 0——
  // 单工具流部分 provider 不带 index；id/name/argsDelta 有值才带键）
  const rawTools: ChatChunkToolCall[] | undefined = delta.tool_calls;
  if (rawTools !== undefined && rawTools.length > 0) {
    const tools: SseToolDelta[] = [];
    for (const tc of rawTools) {
      const item: SseToolDelta = { index: typeof tc.index === 'number' ? tc.index : 0 };
      if (typeof tc.id === 'string' && tc.id !== '') {
        item.id = tc.id;
      }
      if (tc.function !== undefined) {
        if (typeof tc.function.name === 'string' && tc.function.name !== '') {
          item.name = tc.function.name;
        }
        if (typeof tc.function.arguments === 'string' && tc.function.arguments !== '') {
          item.argsDelta = tc.function.arguments;
        }
      }
      tools.push(item);
    }
    result.toolCalls = tools;
  }
  return result;
}

// 非 200 响应体提取 error.message（提取失败/无该字段返回空串，调用方回退展示原文）。
// Anthropic/Gemini 的错误体同为 {"error":{"message":...}} 信封——三协议共用
export function extractApiError(text: string): string {
  try {
    const envelope: ChatErrorEnvelope = JSON.parse(text) as ChatErrorEnvelope;
    const body: ChatErrorBody | undefined = envelope.error;
    if (body !== undefined && body !== null && typeof body.message === 'string' &&
      body.message !== '') {
      return body.message;
    }
    return '';
  } catch (e) {
    return '';
  }
}

// ── Anthropic Messages 流式载荷（2026-08-30 三协议；样例即规格，断言在
// scripts/sse-assert.mjs ⑨）──
// data 载荷自带 type 字段路由（event: 行可忽略）：
// · content_block_delta 且 delta.type=text_delta → delta.text = 正文增量；
//   delta.type=thinking_delta → delta.thinking = 思考链增量（扩展思考未开启不出现）；
// · message_stop → 终止标记（OpenAI [DONE] 的等价物）；
// · error → 流中错误帧（errorMessage 取 error.message）；
// · message_start / content_block_stop / message_delta / ping / 其他 delta 子类 →
//   合法无增量帧；content_block_start(tool_use) 与 input_json_delta = 工具调用增量
//   （2026-09-02 工具调用底层，SseToolDelta 归一形态见文件头）

export interface AnthropicDeltaBody {
  type?: string;
  text?: string;
  thinking?: string;
  partial_json?: string; // 工具入参增量（input_json_delta，2026-09-02）
  stop_reason?: string; // 终止理由（2026-09-23：message_delta 帧携带，'max_tokens' = 截断）
}

// content_block_start 的块头（2026-09-02 工具调用：type='tool_use' 携带 id/name——
// text/thinking 块同样走此结构但无消费字段，kind='other' 不变）
export interface AnthropicBlockStart {
  type?: string;
  id?: string;
  name?: string;
}

// message_start 帧的 message 块（2026-09-06 用量采集：usage.input_tokens = 本轮输入
// 消耗，官方规格；output_tokens 初始值存在但被 take-max 归一覆盖，不单列）
export interface AnthropicMessageStart {
  usage?: AnthropicUsageBlock;
}

// usage 数字块（2026-09-06；message_start.message.usage 与 message_delta.usage 同构消费
// ——message_delta 的 output_tokens 官方语义 = 整条消息累积总量，合并在 mergeUsage 取大）
// 2026-09-10 缓存命中：+ cache_read_input_tokens（命中读，0.1× 计费）与
// cache_creation_input_tokens（写入，1.25× 计费）——官方语义两桶均**不在 input_tokens
// 内**，故 promptTokens 须三桶相加（anthropicPromptTotal）、cachedTokens 只记 read
export interface AnthropicUsageBlock {
  input_tokens?: number;
  output_tokens?: number;
  cache_read_input_tokens?: number;
  cache_creation_input_tokens?: number;
}

export interface AnthropicStreamEvent {
  type?: string;
  index?: number; // content block 序位（工具聚合按此对位）
  delta?: AnthropicDeltaBody;
  content_block?: AnthropicBlockStart;
  message?: AnthropicMessageStart; // message_start 帧载荷（2026-09-06 用量采集）
  usage?: AnthropicUsageBlock; // message_delta 帧 usage（2026-09-06 用量采集）
  error?: ChatErrorBody;
}

// 载荷处置结果：kind = 'delta'（有增量）/ 'stop'（终止标记）/ 'error'（流中错误帧）/
// 'other'（合法无增量）；null = 坏帧（截断/垃圾 JSON——上游计数跳过不阻断）
export interface AnthropicPayload {
  kind: string;
  delta: SseDelta;
  errorMessage: string;
}

// Anthropic 输入全量加法（2026-09-10 口径修正）：官方 input_tokens = 未缓存输入，cache
// 两桶另列——promptTokens 语义 = 全量输入，须 input + cache_read + cache_creation 三桶
// 相加（只取首桶 = 开提示缓存后「输入」显示偏小的存量缺陷，本笔修正；RikkaHub 同款
// 加法）。非 number 按 0 计（JSON null/缺席兜底）
function anthropicPromptTotal(u: AnthropicUsageBlock | undefined): number {
  if (u === undefined || u === null) {
    return 0;
  }
  const base: number = typeof u.input_tokens === 'number' ? u.input_tokens : 0;
  const read: number = typeof u.cache_read_input_tokens === 'number' ? u.cache_read_input_tokens : 0;
  const creation: number =
    typeof u.cache_creation_input_tokens === 'number' ? u.cache_creation_input_tokens : 0;
  return base + read + creation;
}

export function parseAnthropicPayload(payload: string): AnthropicPayload | null {
  let event: AnthropicStreamEvent;
  try {
    event = JSON.parse(payload) as AnthropicStreamEvent;
  } catch (e) {
    return null;
  }
  const empty: SseDelta = { content: '', reasoningContent: '' };
  // 用量提取（2026-09-06）：message_start 走 message.usage（input_tokens 为主）、
  // message_delta 走顶层 usage（output_tokens = 整条消息累积量，mergeUsage 取大合并）——
  // 两帧现链路均落 kind='other' 合法无增量，挂 usage 不变 kind（消费方经 delta.usage 收）。
  // 2026-09-10 缓存命中：两帧同式全量加法（prompt = 三桶和、cached 只记 read）；个别
  // 代理在 message_delta 帧重复给 cache 值——take-max 天然吸收
  if (event.type === 'message_start' && event.message !== undefined && event.message !== null) {
    const u: AiUsageDelta | undefined =
      usageFrameOf(anthropicPromptTotal(event.message.usage), event.message.usage?.output_tokens,
        event.message.usage?.cache_read_input_tokens);
    if (u !== undefined) {
      empty.usage = u;
    }
  }
  if (event.type === 'message_delta' && event.usage !== undefined && event.usage !== null) {
    const u: AiUsageDelta | undefined =
      usageFrameOf(anthropicPromptTotal(event.usage), event.usage.output_tokens,
        event.usage.cache_read_input_tokens);
    if (u !== undefined) {
      empty.usage = u;
    }
  }
  // 截断标记（2026-09-23 输出上限治理笔 2）：message_delta 帧的 delta.stop_reason =
  // 'max_tokens' ⇒ 输出被上限打满（官方规格值；思考 + 正文共享预算，见文件头）。★ 判据
  // 独立于上方 usage 分支——该帧缺 usage 时同样要认，勿并进 usage 守卫里（否则网关省字段
  // 即丢信号）。该帧仍返回 kind='other'（usage 与 kind 语义原样不变）
  if (event.type === 'message_delta' && event.delta !== undefined && event.delta !== null &&
    event.delta.stop_reason === 'max_tokens') {
    empty.truncated = true;
  }
  const type: string = event.type !== undefined ? event.type : '';
  if (type === 'message_stop') {
    return { kind: 'stop', delta: empty, errorMessage: '' };
  }
  if (type === 'error') {
    const body: ChatErrorBody | undefined = event.error;
    const msg: string = body !== undefined && typeof body.message === 'string' ? body.message : '';
    return { kind: 'error', delta: empty, errorMessage: msg };
  }
  if (type === 'content_block_delta') {
    const body: AnthropicDeltaBody | undefined = event.delta;
    const subtype: string =
      body !== undefined && body !== null && body.type !== undefined ? body.type : '';
    if (subtype === 'text_delta') {
      return {
        kind: 'delta',
        delta: { content: body !== undefined && typeof body.text === 'string' ? body.text : '', reasoningContent: '' },
        errorMessage: ''
      };
    }
    if (subtype === 'thinking_delta') {
      return {
        kind: 'delta',
        delta: { content: '', reasoningContent: body !== undefined && typeof body.thinking === 'string' ? body.thinking : '' },
        errorMessage: ''
      };
    }
    if (subtype === 'input_json_delta') {
      // 工具入参增量（2026-09-02）：partial_json 拼接式——index 对位 content_block_start
      const partial: string =
        body !== undefined && typeof body.partial_json === 'string' ? body.partial_json : '';
      return {
        kind: 'delta',
        delta: {
          content: '',
          reasoningContent: '',
          toolCalls: [{ index: typeof event.index === 'number' ? event.index : 0, argsDelta: partial }]
        },
        errorMessage: ''
      };
    }
  }
  if (type === 'content_block_start') {
    // 工具调用块开始（2026-09-02）：type='tool_use' 携带 id/name；文本/思考块 start 走
    // 下方 kind='other' 兜底不变
    const block: AnthropicBlockStart | undefined = event.content_block;
    if (block !== undefined && block !== null && block.type === 'tool_use') {
      const item: SseToolDelta = { index: typeof event.index === 'number' ? event.index : 0 };
      if (typeof block.id === 'string' && block.id !== '') {
        item.id = block.id;
      }
      if (typeof block.name === 'string' && block.name !== '') {
        item.name = block.name;
      }
      return {
        kind: 'delta',
        delta: { content: '', reasoningContent: '', toolCalls: [item] },
        errorMessage: ''
      };
    }
  }
  return { kind: 'other', delta: empty, errorMessage: '' };
}

// ── Gemini streamGenerateContent?alt=sse 流式载荷（2026-08-30 三协议；断言在
// scripts/sse-assert.mjs ⑩）──
// 增量 = candidates[0].content.parts 各段 text 合并（官方流式多 part 并存）；无 candidates
// 的帧（usageMetadata 统计尾帧等）= 合法无增量。Gemini 无终止标记帧——流即体，dataEnd
// 收尾即完成（协议流层 requireDoneMarker=false 分支）。思考摘要段（2026-08-31 A2 自检
// 缺口修复）：请求带 includeThoughts 时思考摘要以 parts[].thought=true 回传（官方
// generateContent 参考 Part.thought 字段）——路由进 reasoningContent（思考块显示），
// 不再混入正文；未开启思考的模型无该标记，行为不变（⑩ 组既有样例零回归）

// Gemini 函数调用段（2026-09-02 工具调用：无增量概念——整帧 {name, args} 即完整调用，
// 归一为 argsFull 替换式 SseToolDelta；index 恒 -1 = 调用方「整调用追加」语义）
export interface GeminiFunctionCall {
  name?: string;
  args?: object;
}

export interface GeminiPart {
  text?: string;
  thought?: boolean;
  functionCall?: GeminiFunctionCall;
}

export interface GeminiContent {
  parts?: GeminiPart[];
}

export interface GeminiCandidate {
  content?: GeminiContent;
  finishReason?: string; // 终止理由（2026-09-23：'MAX_TOKENS' = 输出被上限打满）
}

// usageMetadata 统计块（2026-09-06 用量采集：官方 GenerateContentResponse 规格字段——
// 流式一般在末帧；部分网关每帧携带累积值，mergeUsage 取大归一）
// 2026-09-10 缓存命中：+ cachedContentTokenCount（promptTokenCount 已含命中部分——
// Gemini 官方语义，cached 只是其中标注）
export interface GeminiUsageMetadata {
  promptTokenCount?: number;
  candidatesTokenCount?: number;
  cachedContentTokenCount?: number;
}

export interface GeminiChunk {
  candidates?: GeminiCandidate[];
  usageMetadata?: GeminiUsageMetadata; // 统计尾帧无 candidates（合法无增量帧）
}

// 载荷 → 增量。坏帧容错与 parseChatDelta 同契约：JSON 截断/非法返回 null（上游计数跳过）。
// 2026-09-06 用量采集：usageMetadata 两计数提取（统计尾帧无 candidates 走 empty 兜底带
// usage；数据帧若同带统计块也提取，累积值由 mergeUsage 取大）
export function parseGeminiDelta(payload: string): SseDelta | null {
  let chunk: GeminiChunk;
  try {
    chunk = JSON.parse(payload) as GeminiChunk;
  } catch (e) {
    return null;
  }
  const empty: SseDelta = { content: '', reasoningContent: '' };
  // null 守卫（2026-09-06 自检轮）：同 chat choices:null 家族——成员为 JSON null 时按缺席收
  if (chunk.usageMetadata !== undefined && chunk.usageMetadata !== null) {
    const u: AiUsageDelta | undefined = usageFrameOf(chunk.usageMetadata.promptTokenCount,
      chunk.usageMetadata.candidatesTokenCount, chunk.usageMetadata.cachedContentTokenCount);
    if (u !== undefined) {
      empty.usage = u;
    }
  }
  const candidates: GeminiCandidate[] | undefined = chunk.candidates;
  if (candidates === undefined || candidates === null || candidates.length === 0) {
    return empty; // usage-only 尾帧等，合法但无增量
  }
  // 截断标记（2026-09-23 输出上限治理笔 2）：finishReason='MAX_TOKENS' = 输出被 maxOutputTokens
  // 打满（官方规格值；思考 + 正文共享预算，见文件头与任务书 §0.1）。★ 两出口都要覆盖——该
  // 帧常无 content.parts（走下方早返回），故在 candidates 非空后即判并同时挂 empty
  const truncated: boolean = candidates[0].finishReason === 'MAX_TOKENS';
  if (truncated) {
    empty.truncated = true;
  }
  const content: GeminiContent | undefined = candidates[0].content;
  const parts: GeminiPart[] | undefined =
    content !== undefined && content !== null ? content.parts : undefined;
  if (parts === undefined || parts === null) {
    return empty;
  }
  let text: string = '';
  let thought: string = '';
  const toolCalls: SseToolDelta[] = [];
  for (const part of parts) {
    if (typeof part.text === 'string') {
      if (part.thought === true) {
        thought += part.text; // 思考摘要段：进思考链（thinking 块），不混正文
      } else {
        text += part.text;
      }
    }
    // 函数调用段（2026-09-02）：整调用无序位——index=-1、argsFull 全量（args 缺省 {}）
    if (part.functionCall !== undefined && typeof part.functionCall.name === 'string' &&
      part.functionCall.name !== '') {
      toolCalls.push({
        index: -1,
        name: part.functionCall.name,
        argsFull: part.functionCall.args !== undefined ?
          JSON.stringify(part.functionCall.args) : '{}'
      });
    }
  }
  const result: SseDelta = { content: text, reasoningContent: thought };
  if (truncated) {
    result.truncated = true; // 正常出口同样带出（同帧既有内容又有 finishReason 的方言）
  }
  if (empty.usage !== undefined) {
    result.usage = empty.usage; // 数据帧同带 usageMetadata 时转移（2026-09-06）
  }
  if (toolCalls.length > 0) {
    result.toolCalls = toolCalls;
  }
  return result;
}

// ── OpenAI Responses API 流式载荷（2026-08-30 Responses 适配；断言在
// scripts/sse-assert.mjs ⑬）──
// data JSON 自带 type 字段路由（event: 行同 Anthropic 忽略——feed 只取 data: 行）：
// · response.output_text.delta → delta（裸字符串）= 正文增量（★ 2026-09-06 修复：
//   官方 delta 为裸串非 {text} 对象——原对象形态解析恒空串，responses 文本流自适配起
//   从未真机验证过；双形态兼容 {text} 兜底）；
// · response.reasoning_text.delta / response.reasoning_summary_text.delta → delta（裸
//   字符串）= 思考链增量（推理模型两事件官方均存在——兼容收；无该增量时 thinking 块
//   自然隐藏）；
// · response.completed / response.incomplete → 终止标记（★ 2026-09-06 修复：incomplete
//   = 输出截断的合法终止事件，RikkaHub 同款双终止——漏收会误判「连接中断」假错误；
//   两事件均携带 response.usage 供用量提取）；
// · response.failed / 裸 error → 流中错误帧（errorMessage 取 error.message）；
// · response.output_item.added/done（item.type='reasoning' 且带 id+encrypted_content）
//   → reasoning 输出项捕获（2026-09-06：官方 stateless 工具轮回传保真要求）；
// · response.created / in_progress / content_part.added / output_item(message) 等 →
//   合法无增量帧

export interface ResponsesDeltaBody {
  text?: string;
}

// function_call 输出项（2026-09-02 工具调用：output_item.added/done 且 item.type=
// 'function_call' 时携带 call_id/name/arguments——聚合按 output_index 对位）。
// 2026-09-06 Responses 修复：+ id/encrypted_content（reasoning 输出项捕获字段——added/done
// 且 item.type='reasoning' 时携带，保真回传料见 AiReasoningItem）
export interface ResponsesOutputItem {
  type?: string;
  call_id?: string;
  name?: string;
  arguments?: string;
  id?: string;
  encrypted_content?: string;
}

// usage 统计块（2026-09-06 用量采集：Responses 自带 usage 无需 stream_options——官方
// 规格，随 response.completed/incomplete 终止事件到达；字段名 input_tokens/output_tokens
// 与 chat 方言不同）
// 2026-09-10 缓存命中：+ input_tokens_details.cached_tokens（OpenAI 官方嵌套形态，
// input_tokens 已含命中部分——无 chat 式兜底链，Responses 无厂商变体）
export interface ResponsesUsageBlock {
  input_tokens?: number;
  output_tokens?: number;
  input_tokens_details?: ResponsesInputTokensDetails;
}

// OpenAI Responses 官方嵌套命中标注块（2026-09-10）
export interface ResponsesInputTokensDetails {
  cached_tokens?: number;
}

// 终止事件（completed/incomplete）的 response 块（2026-09-06 用量采集：只声明消费的
// usage 字段；DeepSeek 文档明示 incomplete 同样携带完整 response 含 usage）
// ★ 2026-09-23 输出上限治理笔 2：+ incomplete_details（截断理由——判据收窄见
// parseResponsesPayload 内注释）
export interface ResponsesIncompleteDetails {
  reason?: string;
}

export interface ResponsesCompletedResponse {
  usage?: ResponsesUsageBlock;
  incomplete_details?: ResponsesIncompleteDetails;
}

export interface ResponsesEvent {
  type?: string;
  // ★ delta 形态（2026-09-06 修正注释）：文本族事件官方为**裸字符串**（微软 Foundry 示例
  // / RikkaHub 解码器 / DeepSeek 指南同款）；function_call_arguments.delta 同为裸串。
  // {text} 对象形态仅为个别翻译层网关旧形态——消费侧双形态判别（裸串优先）
  delta?: Object;
  item?: ResponsesOutputItem;
  output_index?: number;
  arguments?: string; // function_call_arguments.done 的完整参数串
  response?: ResponsesCompletedResponse; // completed/incomplete 载荷（2026-09-06）
  error?: ChatErrorBody;
}

// 载荷处置结果（kind 语义与 AnthropicPayload 同构）：'delta'（有增量）/ 'stop'（终止标记）/
// 'error'（流中错误帧）/ 'other'（合法无增量）；null = 坏帧（截断/垃圾/缺 type——
// 上游计数跳过不阻断）
export interface ResponsesPayload {
  kind: string;
  delta: SseDelta;
  errorMessage: string;
}

export function parseResponsesPayload(payload: string): ResponsesPayload | null {
  let event: ResponsesEvent;
  try {
    event = JSON.parse(payload) as ResponsesEvent;
  } catch (e) {
    return null;
  }
  const empty: SseDelta = { content: '', reasoningContent: '' };
  const type: string = event.type !== undefined ? event.type : '';
  if (type === '') {
    return null; // 缺 type = 非 Responses 事件帧（坏帧判定——同 Anthropic 断帧容错）
  }
  // ★ 2026-09-06 修复：completed 与 incomplete 双终止（官方流式两终止事件——incomplete =
  // 输出被截断〔max_output_tokens 等〕，RikkaHub 解码器同款双终止；漏收 incomplete 会把
  // 正常截断流误判「连接中断：响应不完整」假错误）；usage 提取对两终止事件同构（DeepSeek
  // 文档：incomplete 同样携带完整 response 含 usage）
  if (type === 'response.completed' || type === 'response.incomplete') {
    if (event.response !== undefined && event.response !== null &&
      event.response.usage !== undefined && event.response.usage !== null) {
      const u: AiUsageDelta | undefined = usageFrameOf(event.response.usage.input_tokens,
        event.response.usage.output_tokens, event.response.usage.input_tokens_details?.cached_tokens);
      if (u !== undefined) {
        empty.usage = u;
      }
    }
    // 截断标记（2026-09-23 输出上限治理笔 2）：★ 判据必须是 reason 细值而非 incomplete 事件
    // 本身——incomplete 的另一理由 content_filter 是「被内容过滤掐断」，标成「被上限截断」
    // 并建议「提高上限或降低档位」属误导（对照证据：kimi-code 的 FinishReason 分类把
    // truncated〔Responses = max_output_tokens〕与 filtered 分列两类）。其余理由不挂键 =
    // 保持现状 kind='stop' 零回归；过滤类是否上屏另立任务书 §8 待观测项
    if (type === 'response.incomplete' && event.response !== undefined &&
      event.response !== null && event.response.incomplete_details !== undefined &&
      event.response.incomplete_details !== null &&
      event.response.incomplete_details.reason === 'max_output_tokens') {
      empty.truncated = true;
    }
    return { kind: 'stop', delta: empty, errorMessage: '' };
  }
  if (type === 'response.failed') {
    const body: ChatErrorBody | undefined = event.error;
    const msg: string =
      body !== undefined && body !== null && typeof body.message === 'string' ? body.message : '';
    return { kind: 'error', delta: empty, errorMessage: msg };
  }
  // 裸 error 事件（2026-09-06：官方流中错误另一形态——顶层无 response 包裹；RikkaHub
  // 解码器同款收）
  if (type === 'error') {
    const body: ChatErrorBody | undefined = event.error;
    const msg: string =
      body !== undefined && body !== null && typeof body.message === 'string' ? body.message : '';
    return { kind: 'error', delta: empty, errorMessage: msg };
  }
  if (type === 'response.output_text.delta' || type === 'response.reasoning_text.delta' ||
    type === 'response.reasoning_summary_text.delta') {
    // ★ 2026-09-06 修复（真机实锤报错主根因）：官方 delta 为**裸字符串**（微软 Foundry
    // 示例 print(event.delta) / RikkaHub 解码器 payload["delta"].jsonPrimitive.content /
    // DeepSeek Responses 指南同款）——原实现按 {text} 对象解析恒得空串，responses 协议
    // 文本流自 08-30 适配起从未显示过。双形态兼容：裸串优先（官方），{text} 对象兜底
    // （个别翻译层网关旧形态，防御保留）
    const raw: Object | undefined = event.delta;
    let text: string = '';
    if (typeof raw === 'string') {
      text = raw;
    } else if (raw !== undefined && raw !== null) {
      // null 守卫（2026-09-06 自检轮）：JSON null 的 typeof 是 'object' 且 null !== undefined，
      // 不守则 body.text 取值抛 TypeError——坏帧容错契约（跳过不炸流）破坏
      const body: ResponsesDeltaBody | undefined = raw as ResponsesDeltaBody;
      if (typeof body.text === 'string') {
        text = body.text;
      }
    }
    if (type === 'response.output_text.delta') {
      return { kind: 'delta', delta: { content: text, reasoningContent: '' }, errorMessage: '' };
    }
    return { kind: 'delta', delta: { content: '', reasoningContent: text }, errorMessage: '' };
  }
  // ── 工具调用事件族（2026-09-02）──
  if (type === 'response.output_item.added' || type === 'response.output_item.done') {
    const item: ResponsesOutputItem | undefined = event.item;
    if (item !== undefined && item !== null && item.type === 'function_call') {
      const tool: SseToolDelta =
        { index: typeof event.output_index === 'number' ? event.output_index : 0 };
      if (typeof item.call_id === 'string' && item.call_id !== '') {
        tool.id = item.call_id;
      }
      // nameFull 替换式（2026-09-06 修复重名循环）：added/done 两事件各带完整名，聚合器
      // += 拼接会得「search_helpsearch_help」重名（真机转录实锤）——走 name 全量覆盖语义
      if (typeof item.name === 'string' && item.name !== '') {
        tool.nameFull = item.name;
      }
      if (type === 'response.output_item.done' && typeof item.arguments === 'string' &&
        item.arguments !== '') {
        tool.argsFull = item.arguments; // done = 完整参数替换式
      }
      return {
        kind: 'delta',
        delta: { content: '', reasoningContent: '', toolCalls: [tool] },
        errorMessage: ''
      };
    }
    // reasoning 输出项捕获（2026-09-06）：added/done 均可能携带 encrypted_content（终值
    // 在 done，added 时常空——同 id 后到覆盖先到，聚合在 ChatSendCtrl）；缺 id 或缺
    // encrypted_content 不构成可回传 item，不捕获。kind='delta'（空文本 + 捕获载荷）——
    // 走 deliverDelta 投递路径（门控按 reasoningItems 放行）
    if (item !== undefined && item !== null && item.type === 'reasoning' &&
      typeof item.id === 'string' && item.id !== '' &&
      typeof item.encrypted_content === 'string' && item.encrypted_content !== '') {
      return {
        kind: 'delta',
        delta: { content: '', reasoningContent: '',
          reasoningItems: [{ id: item.id, encryptedContent: item.encrypted_content }] },
        errorMessage: ''
      };
    }
    return { kind: 'other', delta: empty, errorMessage: '' };
  }
  if (type === 'response.function_call_arguments.delta') {
    const partial: string = typeof event.delta === 'string' ? event.delta : '';
    return {
      kind: 'delta',
      delta: {
        content: '',
        reasoningContent: '',
        toolCalls: [{ index: typeof event.output_index === 'number' ? event.output_index : 0,
          argsDelta: partial }]
      },
      errorMessage: ''
    };
  }
  return { kind: 'other', delta: empty, errorMessage: '' };
}
