// SSE 攒帧解析：OpenAI 兼容流式的分帧 + data 载荷提取 + 增量字段解析，及 Anthropic/Gemini
// 两原生协议的载荷解析纯函数。★ 本文件零 import、只用 erasable TS 语法（无 enum/
// namespace/装饰器）——scripts/sse-assert.mjs 把本文件复制为 .ts 由 node 类型剥离直跑，
// 断言的就是线上同一实现（禁双实现漂移）。token 用量与缓存命中：AiUsageDelta 归一类型 +
// mergeUsage 流内 take-max 合并 + 四 parse 各自提取 usage 统计帧（chat 三级兜底 /
// anthropic 三桶相加，形态与官方依据见各接口注释）。
// 攒帧语义（SSE 规范 + OpenAI 兼容方言实测惯例）：
// · 事件 = 若干 data: 行 + 空行收尾；多 data 行以 \n 合并（OpenAI 实际单行，合并兜底）；
// · 行结尾兼容 \n 与 \r\n；':' 开头为注释/心跳行，忽略；event:/id:/retry: 字段用不上，
//   忽略（Anthropic 的 event: 行同理——事件类型在 data JSON 的 type 字段里，帧路由不看
//   event: 行）；
// · 跨 TCP 分片的半截行攒在 tail，下片补齐再判；finish() 冲刷流尾无换行收尾的末行与
//   未决事件；
// · 首帧 BOM 剥除：首个非空 chunk 开头的 \uFEFF 剥一次（依据与空 chunk 语义见 bomPending）。

// 单帧解析产物：正文增量与思考链增量（delta.reasoning_content 事实标准，无该字段的
// provider 天然空串，调用方据此隐藏思考块）。可选键均「有值才挂、存量零回归」：
// toolCalls = 流式工具调用增量（四协议方言归一，聚合在 ToolCallAccumulator
//〔ToolStream.ets〕）；usage = 统计帧归一形态（挂「无增量」帧不触发正文回调，流层经
// absorbUsage 累积）；reasoningItems = Responses 保真回传料（仅 responses 路径设置）；
// truncated = **仅真截断时挂键**（输出被上限掐断的标记；四协议标记位置：chat
// finish_reason='length' / anthropic stop_reason='max_tokens' / gemini finishReason=
// 'MAX_TOKENS' / responses incomplete+reason='max_output_tokens'；依据 = 思考与正文
// 共享同一输出上限〔四家一致〕，打满即正文空/半截——回答质量信号而非错误信号，kind
// 语义不变照 usage 同路由流层吸收）；errorMessage = chat 方言流中错误帧文案（仅错误帧
// 挂键；此前 chat 是四方言唯一缺口——错误帧被 choices 守卫当合法空帧吞掉，流末误报
//「连接中断」而真实原因丢失；消费方 = OpenAIChatStream.consumePayload 判非空即
// failStream，形制照 Anthropic 分支）
// DeepSeek 服务端工具事件（DS 全家桶接入批 S2③，2026-11-14；§0「流式形态」官方明示）：
// server_tool_event 是 choices[0] 上与 delta 并列的字段（不在 delta 内、不是 SSE event 行；
// 一 chunk 至多一事件）。三型 = step_reasoning_done{step} / call_started{step, call} /
// call_completed{step, call}（call 带 status 与 sources/page 或 error，不带 signature）。
// 归一形态：type 原样；step = 官方数字步序（非 number 不挂）；callJson = call 对象
// JSON.stringify 原样串（保真——S2⑤ 流域据它合成 serverstep 行，S2⑥ 部分结构组装料）
export interface SseServerToolEvent {
  type: string;
  step?: number;
  callJson?: string; // 仅 call_started/call_completed 携带（JSON.stringify(call) 保真）
  // Responses 专用：官方 output item 原样串（web_search_call item——落库 items 用；CC 无此键）
  itemJson?: string;
}

export interface SseDelta {
  content: string;
  reasoningContent: string;
  toolCalls?: SseToolDelta[];
  usage?: AiUsageDelta;
  reasoningItems?: AiReasoningItem[];
  truncated?: boolean;
  errorMessage?: string;
  // ── DeepSeek 服务端工具三字段（S2③）：serverToolEvent = choices[0].server_tool_event
  // 归一（提取点在 delta 早返回**之前**——事件帧的 delta 常缺失，落早返回即被吞，同
  // truncated 两出口先例）；serverToolCallsJson/annotationsJson = 末帧 delta 的
  // server_tool_calls / annotations 两字段原样 stringify（官方明示完整两字段只发一次、在带
  // finish_reason 的末帧 delta 内）。三键均有值才挂 = 非 DS 流零回归
  serverToolEvent?: SseServerToolEvent;
  serverToolCallsJson?: string;
  annotationsJson?: string;
  // ── DS 官方标题与图片拦截（二期 #4 / #6）：title = 末 chunk delta.title（会话标题，不一定有）；
  // refusal = delta.refusal（**图片**未过审说明——与「回答被安全审核撤下」是两回事，见
  // ChatChunkDelta 注释）。有值才挂键 = 非 DS 流零回归
  title?: string;
  refusal?: string;
  // 输出侧拒答标记（finish_reason='content_filter'——回答被内容安全过滤；四方言里只有 chat
  // 与 responses 有该信号）。置真即撤正文改显拒答文案、按失败轮落库（S2/#6 拒答链）
  contentFiltered?: boolean;
  // Responses 专用：终止事件里 response.output 的完整 items 数组（原样 JSON 串）——落库回传
  // 与回放合成同源（官方「把上一轮整个 output 原样放回 input」）；CC/Anthropic/Gemini 不产
  responsesOutputJson?: string;
}

// Responses reasoning 输出项捕获形态：OpenAI 官方 stateless 模式要求工具轮回传配对
// reasoning item（缺失/乱序 = 400，生态实锤）；保真回传须 encrypted_content（裸 reasoning
// 文本不构成合法 item），故捕获条件 = 带 id 且带 encrypted_content。定义在本文件（零
// import 断言面），AiTypes re-export 供上层消费
export interface AiReasoningItem {
  id: string;
  encryptedContent: string;
}

// token 用量归一形态（四协议方言在此归一，形态见各接口注释）。定义在本文件（零 import
// 断言面），AiTypes re-export 供上层消费。字段语义 = 本帧所见瞬时值，跨帧/跨流合并在
// mergeUsage（流内 take-max）与 ChatSendCtrl 轮次累积器（跨流求和）。cachedTokens 可选
//（全量输入中命中缓存的部分，>0 才挂键——无缓存协议/短对话不出现该键）；promptTokens
// 语义升格「全量输入」——anthropic 侧为 input+cache_read+cache_creation 三桶相加（官方
// input_tokens 不含 cache 两桶，只取首桶会显示偏小），其余三方言现状已含命中
export interface AiUsageDelta {
  promptTokens: number;
  completionTokens: number;
  cachedTokens?: number;
  // ── DS 官方扩展用量（二期 S2/#7）──
  // safetyTokens = 内容安全审核消耗的输出 token（官方归在 completion_tokens 内，本应用
  // **只采集不单列**——单列会造成「输出 100 其中审核 20」的重复感，仅随账本留存）；
  // serverToolUse = 服务端工具计次（官方 usage 顶层子对象 server_tool_use，与
  // completion_tokens_details 并列；三键全零时官方整对象省略，读侧按可选防御）
  safetyTokens?: number;
  serverToolUse?: AiServerToolUse;
}

// 服务端工具计次（官方三键；tool_search 官方注明「计费的搜索次数，不含图片搜索」）
export interface AiServerToolUse {
  search: number;
  fetch: number;
  image: number;
}

// 计次 → 账本列串（v65 serverToolsUsage 列；入参 undefined = 无计次回 ''——不写键/写空串
// 同义）。零依赖纯函数 = 断言直跑面；消费方 = ChatGraphWriteCtrl 组 GraphFinishInput 时
export function serverToolUseJsonOf(use: AiServerToolUse | undefined): string {
  if (use === undefined) {
    return '';
  }
  if (use.search <= 0 && use.fetch <= 0 && use.image <= 0) {
    return '';
  }
  return JSON.stringify({ search: use.search, fetch: use.fetch, image: use.image });
}

// 两轮计次相加（续写跨轮显示口径，决明 2026-11-14 拍板「两轮和」）：同一 messageId 两行
// 账本（每轮一行，费用不重复），气泡计次三行取两轮合计。base 缺席按 0 起算；纯函数直跑面
export function addServerToolUse(base: AiServerToolUse | undefined,
  extra: AiServerToolUse): AiServerToolUse {
  const from: AiServerToolUse = base ?? { search: 0, fetch: 0, image: 0 };
  return { search: from.search + extra.search, fetch: from.fetch + extra.fetch,
    image: from.image + extra.image };
}

// 账本列串 → 计次（回放消费：ChatPageLoad.applyUsageEvents 填 msg.serverToolUse）。坏串 /
// 空串 / 全零 → undefined（不挂键 = 气泡不出三行，零噪声口径与缓存段同源）
export function parseServerToolUseJson(text: string): AiServerToolUse | undefined {
  if (text === '') {
    return undefined;
  }
  try {
    const rec: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
    const pick = (key: string): number => {
      const value: Object | undefined = rec[key];
      if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
        return 0;
      }
      return Math.floor(value);
    };
    const use: AiServerToolUse = { search: pick('search'), fetch: pick('fetch'),
      image: pick('image') };
    if (use.search === 0 && use.fetch === 0 && use.image === 0) {
      return undefined;
    }
    return use;
  } catch (e) {
    return undefined;
  }
}

// 账本列串版本的两轮相加（回放链用）：空串/坏串按 0 计，合计全零回 ''——与上面两纯函数
// 同口径（不写键与写空串同义）
export function addServerToolUseJson(left: string, right: string): string {
  return serverToolUseJsonOf(addServerToolUse(parseServerToolUseJson(left),
    parseServerToolUseJson(right) ?? { search: 0, fetch: 0, image: 0 }));
}

// 流内多帧 usage 合并（take-max 口径）：同一流内 usage 分帧出现（anthropic 两帧各给一半、
// gemini 部分网关每帧带累积值）——各字段**取大**合并（累积值后帧 ≥ 前帧；chat 尾帧单帧
// 全量天然兼容）；任一方 null 回另一方，双方 null 回 null；cachedTokens 同走 take-max
//（任一方 >0 即带键）。零依赖纯函数 = sse-assert 断言面（㉚/56 组），传输层
// ChatStreamBase.absorbUsage 消费
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
  // ★ 二期 S2/#7：serverToolUse 必须同步合并（逐子键取大）——漏改 = 多帧 usage 合并时
  // 计次被丢（DS 常把 usage 挂末条内容帧，与统计帧并存时两帧合并是主路径）
  const baseSafety: number = base.safetyTokens ?? 0;
  const incomingSafety: number = incoming.safetyTokens ?? 0;
  if (baseSafety > 0 || incomingSafety > 0) {
    merged.safetyTokens = baseSafety > incomingSafety ? baseSafety : incomingSafety;
  }
  const baseUse: AiServerToolUse | undefined = base.serverToolUse;
  const incomingUse: AiServerToolUse | undefined = incoming.serverToolUse;
  if (baseUse !== undefined || incomingUse !== undefined) {
    const b: AiServerToolUse = baseUse ?? { search: 0, fetch: 0, image: 0 };
    const i: AiServerToolUse = incomingUse ?? { search: 0, fetch: 0, image: 0 };
    merged.serverToolUse = {
      search: b.search > i.search ? b.search : i.search,
      fetch: b.fetch > i.fetch ? b.fetch : i.fetch,
      image: b.image > i.image ? b.image : i.image
    };
  }
  return merged;
}

// 工具调用增量（四协议归一形态）：
// · index = 流内序位（openai tool_calls.index / anthropic content block index / responses
//   output_index；gemini functionCall 无序位概念恒 -1——调用方按「整调用追加」处理）；
// · id = 调用 id（openai 首帧携带 / anthropic content_block_start / responses call_id；
//   gemini 无——聚合器自生成）；name/nameFull = 函数名；argsDelta/argsFull = 参数；
// · ★ name/nameFull 两型（修复「search_helpsearch_help」重名循环）：name = 分片拼接式
//   （openai chat 事实形态——首帧片段续片累拼，聚合器 +=）；nameFull = 全量替换式
//   （responses added/done 两事件各携带完整名，聚合器 += 会拼出重名 → 命不中本轮声明集
//   →「未在本轮启用」→ 模型重试循环至轮上限，真机实锤）；argsDelta = 参数 JSON 串增量
//   （拼接式：openai function.arguments / anthropic partial_json / responses
//   function_call_arguments.delta）；argsFull = 参数 JSON 串全量（替换式：gemini
//   functionCall.args / responses output_item.done 的完整 arguments——聚合器以它覆盖
//   并标记整调用完成）
export interface SseToolDelta {
  index: number;
  id?: string;
  name?: string;
  nameFull?: string;
  argsDelta?: string;
  argsFull?: string;
}

// chat/completions 流式帧结构（只声明消费的字段，其余忽略——JSON.parse 强转兜底）。
// ★ server_tool_calls / annotations（S2③，DS 官方末帧 delta 两字段——原样 stringify 保真，
// 只声明存在性不做结构展开，结构消费方 = 流域落库串与回传链）
export interface ChatChunkDelta {
  content?: string;
  reasoning_content?: string;
  role?: string;
  tool_calls?: ChatChunkToolCall[]; // 工具调用增量（按 index 聚合在调用方）
  server_tool_calls?: Object; // 官方末帧：服务端工具完整调用记录（原样透传）
  annotations?: Object; // 官方末帧：url_citation 引用标注数组（原样透传）
  // DS 官方标题与图片拦截（二期 #4 / #6）：title = 模型顺带生成的会话标题（末 chunk 携带，
  // 不一定有）；refusal = **图片**未过审的说明（官方原文语义，不是「回答被撤」——输出侧
  // 拒答看 finish_reason=content_filter，两者文案分开）
  title?: string;
  refusal?: string;
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

// DeepSeek 服务端工具事件载荷（choices[0] 级字段——不在 delta 内，见 SseServerToolEvent 注释）
export interface ChatChunkServerToolEvent {
  type?: string;
  step?: number;
  call?: Object;
}

export interface ChatChunkChoice {
  delta?: ChatChunkDelta;
  index?: number;
  finish_reason?: string;
  server_tool_event?: ChatChunkServerToolEvent; // DS 官方流式事件（与 delta 并列，S2③）
}

// usage 统计块（流被中断则收不到）。携带形态两家：OpenAI 式 = include_usage 开启后流末
// 追加独立统计帧（choices 恒空数组）；DeepSeek 式 = 官方无独立 usage-only 帧，统计挂末条
// 内容帧同帧携带——两形态解析同收。缓存命中三方言变体（prompt_tokens 已含命中部分——
// OpenAI 官方语义）：OpenAI 嵌套 prompt_tokens_details.cached_tokens / Moonshot 顶层
// cached_tokens / DeepSeek 专有 prompt_cache_hit_tokens，提取走 chatCachedTokens 三级兜底
//（只认嵌套时后两家恒 0）
export interface ChatChunkUsage {
  prompt_tokens?: number;
  completion_tokens?: number;
  prompt_tokens_details?: ChatPromptTokensDetails;
  cached_tokens?: number;
  prompt_cache_hit_tokens?: number;
  // 二期 S2/#7：服务端工具计次（usage 顶层子对象，与 completion_tokens_details 并列）
  server_tool_use?: ChatServerToolUse;
  // 内容安全审核 token（completion_tokens 的子项；采集不单列）
  completion_tokens_details?: ChatCompletionTokensDetails;
}

export interface ChatServerToolUse {
  tool_search?: number;
  tool_fetch?: number;
  tool_image_search?: number;
}

export interface ChatCompletionTokensDetails {
  safety_tokens?: number;
}

// OpenAI chat 官方嵌套命中标注块
export interface ChatPromptTokensDetails {
  cached_tokens?: number;
}

export interface ChatChunk {
  choices?: ChatChunkChoice[];
  usage?: ChatChunkUsage; // 统计帧载荷（其余帧 usage:null = typeof 非 number 忽略）
  // 流中错误帧：chat 方言 {"error":...} 帧载荷——信封对象或裸串两形态（运行时也可能是
  // null，提取侧同 choices 的 null 守卫家族兜）；提取见 parseChatDelta
  error?: ChatErrorBody | string;
}

// OpenAI 兼容错误信封（非 200 响应体 {"error":{"message":...}}）。★ 兜底链：error 亦可
// 为裸串（{"error":"..."}）；顶层另有 message/detail/description 三信封（{"message":...}
// 裸形态 / FastAPI 式 {"detail":...} 等，网关常见）——提取链 = error.message →
// error.detail → error 裸串 → 顶层三键，见 extractApiError
export interface ChatErrorEnvelope {
  error?: ChatErrorBody | string;
  message?: string;
  detail?: string;
  description?: string;
}

export interface ChatErrorBody {
  message?: string;
  type?: string;
  code?: string;
  detail?: string; // FastAPI 式 {"error":{"detail":...}}
}

// ── SSE 接收侧输入预算（上限数值决明拍板采纳）──超限 = 显式失败（流层 fail 中文提示，
// 禁静默截断后继续）；本文件只产类型化超限信号（档位标识 + 实测值，不含面向用户文案——
// 文案在 ChatStreamBase），常量 export 供 sse-assert 直跑断言 import 构造边界样本（禁值
// 抄本）。单行上限须同时容纳两种合法极端：个别网关把整段回答并成一帧（最大输出 131072
// tokens ⇒ 中文约 13 万字符量级）与单条工具参数 100000 字符 + JSON 转义膨胀——取
// 256 KiB 量级，两形态各留 ≥1.3 倍余量
export const SSE_LINE_MAX_CHARS: number = 262144;
// 单事件（多 data 行合帧）合计上限：合法上限远小于单行上限之和（多行合帧是 SSE 规范兜底
// 形态，OpenAI 实际单行），取 1 MiB
export const SSE_EVENT_MAX_CHARS: number = 1048576;

// 超限信号：kind = 'line'（单行）/ 'event'（单事件 dataParts 合计）；actual = 实测字符数。
// 流层见非空信号即经既有 fail 通道显式失败（STREAM_ERROR_STATUS），feed/finish 后续调用
// 一律空返回（不得静默截断或丢数据后继续）
export interface SseLimitBreach {
  kind: string;
  actual: number;
}

export class SseParser {
  private tail: string = ''; // 未凑够一行的残余（跨分片半截行）
  private dataParts: string[] = []; // 当前事件已收 data 行（空行收尾时合并派发）
  // 当前事件已收 data 行字符数累计（单事件合计预算判定，与 dataParts 同拍重置）
  private dataPartsChars: number = 0;
  // 超限信号：非空 = 已判超限，此后的 feed/finish 一律空返回（流层已 fail，终态闸吞后续
  // 回调；防御性短路 + 供流层与断言面读取的信号位）
  limitBreach: SseLimitBreach | null = null;
  // 首帧 BOM 剥除标记：util.TextDecoder 的 ignoreBOM 默认 false（解码结果**含** BOM），
  // ChatStreamBase 的 decodeToString stream 模式不剥 BOM ⇒ 服务端首帧带 \uFEFF 时首行成
  //「\uFEFFdata:」不匹配前缀、整帧被丢。首个**非空** chunk 到达时剥开头 \uFEFF 一次后置
  // false——空 chunk 不消费机会（BOM 可能在更晚的分片）；中间帧再出现 BOM 不特殊处理
  //（坏帧容错已兜）
  private bomPending: boolean = true;

  // 喂入一段已解码文本，返回本段凑齐的事件载荷序列（每个元素 = 一个 data: 事件的完整载荷）
  feed(chunk: string): string[] {
    if (this.limitBreach !== null) {
      return []; // 已超限不再摄入（禁静默截断后继续）
    }
    const out: string[] = [];
    let text: string = chunk;
    if (this.bomPending && text !== '') {
      this.bomPending = false;
      if (text.startsWith('\uFEFF')) {
        text = text.substring(1);
      }
    }
    this.tail += text;
    let nl: number = this.tail.indexOf('\n');
    while (nl >= 0) {
      const line: string = this.tail.substring(0, nl);
      this.tail = this.tail.substring(nl + 1);
      this.consumeLine(line, out);
      if (this.limitBreach !== null) {
        return out; // 行判处判废（单行/单事件超限）即止，后续行不再处理
      }
      nl = this.tail.indexOf('\n');
    }
    // 单行预算：判定点在切行循环**之后**——此刻 tail 才是单个未闭合行（不含换行；循环前
    // 判会把一次喂入的多行整段误判成单行超限）。残余超限即该行必然超限（不可能再变短）
    //——置信号 + 清内部状态
    if (this.tail.length > SSE_LINE_MAX_CHARS) {
      this.limitBreach = { kind: 'line', actual: this.tail.length };
      this.tail = '';
      this.dataParts = [];
      this.dataPartsChars = 0;
    }
    return out;
  }

  // 流收尾冲刷：末行无换行也算一行；未决事件（缺空行收尾）同样派发——
  // 截断帧在此暴露为「不完整载荷」，由 parseChatDelta 容错判废
  finish(): string[] {
    if (this.limitBreach !== null) {
      return []; // 已超限不再摄入
    }
    const out: string[] = [];
    if (this.tail !== '') {
      const line: string = this.tail;
      this.tail = '';
      this.consumeLine(line, out);
      if (this.limitBreach !== null) {
        return out;
      }
    }
    if (this.dataParts.length > 0) {
      // 单事件预算（join 点）：与 push 点同判据（dataPartsChars 单源），防御性复判
      if (this.dataPartsChars > SSE_EVENT_MAX_CHARS) {
        this.limitBreach = { kind: 'event', actual: this.dataPartsChars };
        this.dataParts = [];
        this.dataPartsChars = 0;
        return out;
      }
      out.push(this.dataParts.join('\n'));
      this.dataParts = [];
      this.dataPartsChars = 0;
    }
    return out;
  }

  private consumeLine(line: string, out: string[]): void {
    let text: string = line;
    if (text.endsWith('\r')) {
      text = text.substring(0, text.length - 1);
    }
    // 单行预算（行判处）：完整行超限即置信号（feed 的 tail 判定覆盖未闭合残余，本处覆盖
    // 已切出的完整行——\r 剥除后口径）
    if (text.length > SSE_LINE_MAX_CHARS) {
      this.limitBreach = { kind: 'line', actual: text.length };
      this.dataParts = [];
      this.dataPartsChars = 0;
      return;
    }
    if (text === '') {
      // 空行 = 事件收尾：有 data 才派发（连续空行/纯注释段不产生空载荷）
      if (this.dataParts.length > 0) {
        out.push(this.dataParts.join('\n'));
        this.dataParts = [];
        this.dataPartsChars = 0;
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
      // 单事件预算（push 点）：多 data 行合计超限即置信号（本次 push 已计入但不派发——
      // 超限即失败，无「截断后继续」形态）
      this.dataPartsChars += payload.length;
      if (this.dataPartsChars > SSE_EVENT_MAX_CHARS) {
        this.limitBreach = { kind: 'event', actual: this.dataPartsChars };
        this.dataParts = [];
        this.dataPartsChars = 0;
      }
    }
  }
}

// 根形状守卫：JSON.parse 产物非「对象」（null / 数组 / 标量）= 服务端坏形状——四解码
// 入口在字段访问前统一判废 return null，与 JSON 语法失败逐字同路（下游 noteBadFrame
// 计数 + 流继续；此前此类载荷的异常会越过 consumePayload 边界落进事件回调未捕获）。
// 守卫只拦「解引用会抛」的根与元素，不改变合法帧解析行为（kind 语义逐字不变）；typeof /
// Array.isArray 判别，零 import + erasable TS 契约不受影响
export function isJsonObject(v: Object | null): boolean {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

// usage 数字对守卫归一（四方言共用）：任一字段非 number 视为缺（补 0——take-max 与求和
// 口径下 0 无害）；三值全缺 = 无 usage 回 undefined，坏值容错照既有坏帧口径（typeof 守卫，
// 不炸不静默成错误值）。cached 第三可选参（>0 才归入）——既有调用点与断言面零破坏
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

// chat 方言缓存命中三级兜底：OpenAI 嵌套 → Moonshot 顶层 → DeepSeek 专有——同一
// dialect 内的厂商字段拼写差异用一个兜底链收完（不 per-provider 分支，坑 18「只适配协议
// 规格不逐厂商特判」同构；只认嵌套时 Moonshot/DeepSeek 恒 0）。非空 number 才认，
// 脏值由 usageFrameOf 守卫兜
// chat usage 帧归一（二期 S2/#7）：token 三桶 + 审核 token + 服务端工具计次。只有计次或
// 审核 token 的帧（token 全零）也要出帧——否则「这一轮搜了几次」丢在解析层
function chatUsageOf(usage: ChatChunkUsage): AiUsageDelta | undefined {
  const base: AiUsageDelta | undefined = usageFrameOf(usage.prompt_tokens,
    usage.completion_tokens, chatCachedTokens(usage));
  const use: AiServerToolUse | undefined = serverToolUseOf(usage.server_tool_use);
  const details: ChatCompletionTokensDetails | undefined = usage.completion_tokens_details;
  const safety: number = details !== undefined && details !== null &&
    typeof details.safety_tokens === 'number' && Number.isFinite(details.safety_tokens) &&
    details.safety_tokens > 0 ? details.safety_tokens : 0;
  if (base === undefined && use === undefined && safety === 0) {
    return undefined;
  }
  const frame: AiUsageDelta = base ?? { promptTokens: 0, completionTokens: 0 };
  if (use !== undefined) {
    frame.serverToolUse = use;
  }
  if (safety > 0) {
    frame.safetyTokens = safety;
  }
  return frame;
}

// 服务端工具计次归一（官方三键 → 本应用三桶；缺省/非数/负值按 0，全零回 undefined
// = 不挂键）
export function serverToolUseOf(raw: ChatServerToolUse | undefined): AiServerToolUse | undefined {
  if (raw === undefined || raw === null) {
    return undefined;
  }
  const pick = (v: number | undefined): number =>
    typeof v === 'number' && Number.isFinite(v) && v > 0 ? Math.floor(v) : 0;
  const use: AiServerToolUse = {
    search: pick(raw.tool_search),
    fetch: pick(raw.tool_fetch),
    image: pick(raw.tool_image_search)
  };
  if (use.search === 0 && use.fetch === 0 && use.image === 0) {
    return undefined;
  }
  return use;
}

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
// [DONE] 由调用方先判。usage 两形态同收——独立统计帧（choices 空，OpenAI 式）走 empty
// 兜底带回；挂末条内容帧（choices 非空，DeepSeek 官方形态——修复前被 result 分支丢弃
// = ds/comp「completion 无用量」真根因）随 result 带回。流中错误帧提取（chunk.error →
// delta.errorMessage）——此前该类帧被 choices 守卫当合法空帧吞掉，流末误报「连接中断」
// 而真实原因丢失；消费方 = OpenAIChatStream.consumePayload 判非空即 failStream
export function parseChatDelta(payload: string): SseDelta | null {
  let chunk: ChatChunk;
  try {
    chunk = JSON.parse(payload) as ChatChunk;
  } catch (e) {
    return null;
  }
  // 根形状校验：载荷 null/数组/标量 → 坏帧同路（原在 chunk.error 解引用抛出）
  if (!isJsonObject(chunk)) {
    return null;
  }
  const empty: SseDelta = { content: '', reasoningContent: '' };
  // 流中错误帧提取：必须在 choices 守卫**之前**——错误帧通常无 choices，落到守卫即被当
  // 合法空帧吞掉。error 为裸串直取、信封对象取 message（JSON null 落 typeof object
  // 分支，照 choices:null 家族补 null 判）；空串不挂键 = 正常帧零回归
  const rawError: ChatErrorBody | string | undefined = chunk.error;
  let streamError: string = '';
  if (typeof rawError === 'string') {
    streamError = rawError;
  } else if (rawError !== undefined && rawError !== null &&
    typeof rawError.message === 'string') {
    streamError = rawError.message;
  }
  if (streamError !== '') {
    empty.errorMessage = streamError;
  }
  const frameUsage: AiUsageDelta | undefined = chunk.usage !== undefined && chunk.usage !== null ?
    chatUsageOf(chunk.usage) : undefined;
  if (frameUsage !== undefined) {
    empty.usage = frameUsage;
  }
  const choices: ChatChunkChoice[] | undefined = chunk.choices;
  // null 守卫：个别代理发 "choices":null——JSON null 过 !== undefined 判后 .length 即抛；
  // 按无 choices 合法帧收（usage:null 同族守卫先例）
  if (choices === undefined || choices === null || choices.length === 0) {
    return empty; // 首帧仅 role / Usage 统计帧等无 choices 形态，合法但无增量
  }
  // 元素形状校验：choices[0] 运行时可为 null/标量（如 {"choices":[null]}）——非对象即
  // 整帧判废，防 finish_reason 解引用抛出
  if (!isJsonObject(choices[0] ?? null)) {
    return null;
  }
  // 截断标记：finish_reason='length' = 输出被 max_tokens 打满（思考 + 正文共享预算，
  // 见文件头）。★ 两出口都要覆盖——该帧的 delta 常为 {} 或缺失（走下方早返回），故在
  // choices 非空后即判并同时挂 empty
  const truncated: boolean = choices[0].finish_reason === 'length';
  if (truncated) {
    empty.truncated = true;
  }
  // 输出侧拒答：回答被内容安全过滤（正文可能已流式下发完毕，收尾由 ChatDsStreamExtrasCtrl
  // 撤正文改显拒答文案——官方要求「删除已展示的回答」）
  if (choices[0].finish_reason === 'content_filter') {
    empty.contentFiltered = true;
  }
  // ── DeepSeek 服务端工具提取（S2③）——必须在 delta 早返回**之前**（同 truncated 两出口
  // 先例）：①server_tool_event 挂 choices[0]（与 delta 并列，官方明示），事件帧的 delta 常
  // 缺失，落早返回即整帧被当合法空帧吞掉；②末帧 delta 的 server_tool_calls / annotations
  // 两字段原样 stringify（官方明示完整两字段只发一次、在带 finish_reason 的末帧 delta 内）。
  // 两形态均挂 empty——delta 缺失帧走早返回照样带出，delta 在场帧由下方 result 转移
  //（usage 同款）；有值才挂键 = 非 DS 流零回归
  const rawServerEvent: ChatChunkServerToolEvent | undefined = choices[0].server_tool_event;
  if (rawServerEvent !== undefined && rawServerEvent !== null &&
    typeof rawServerEvent.type === 'string' && rawServerEvent.type !== '') {
    const ev: SseServerToolEvent = { type: rawServerEvent.type };
    if (typeof rawServerEvent.step === 'number') {
      ev.step = rawServerEvent.step;
    }
    if (rawServerEvent.call !== undefined && rawServerEvent.call !== null) {
      ev.callJson = JSON.stringify(rawServerEvent.call); // call 对象保真——禁截断禁重排
    }
    empty.serverToolEvent = ev;
  }
  if (choices[0].delta !== undefined && choices[0].delta !== null) {
    const tailDelta: ChatChunkDelta = choices[0].delta;
    if (tailDelta.server_tool_calls !== undefined && tailDelta.server_tool_calls !== null) {
      empty.serverToolCallsJson = JSON.stringify(tailDelta.server_tool_calls);
    }
    if (tailDelta.annotations !== undefined && tailDelta.annotations !== null) {
      empty.annotationsJson = JSON.stringify(tailDelta.annotations);
    }
  }
  const delta: ChatChunkDelta | undefined = choices[0].delta;
  if (delta === undefined || delta === null) {
    return empty;
  }
  const result: SseDelta = {
    content: typeof delta.content === 'string' ? delta.content : '',
    reasoningContent: typeof delta.reasoning_content === 'string' ? delta.reasoning_content : ''
  };
  // DS 标题与图片拦截（二期 #4 / #6）：只在有值时挂键（非 DS 流零回归）
  if (typeof delta.title === 'string' && delta.title !== '') {
    result.title = delta.title;
  }
  if (typeof delta.refusal === 'string' && delta.refusal !== '') {
    result.refusal = delta.refusal;
  }
  if (empty.contentFiltered === true) {
    result.contentFiltered = true;
  }
  if (truncated) {
    result.truncated = true; // 正常出口同样带出（同帧既有内容又有 finish_reason 的方言）
  }
  if (streamError !== '') {
    result.errorMessage = streamError; // 错误与增量同帧的防御出口（正常错误帧无 choices 早退）
  }
  // usage 挂末条内容帧形态（DeepSeek 官方：统计随末帧同帧携带）——修复前本分支丢
  // frameUsage，ds/comp 全程收不到用量
  if (frameUsage !== undefined) {
    result.usage = frameUsage;
  }
  // 服务端工具三字段转移（S2③：早返回前提取进 empty 的载水分两出口带出——usage 同款）；
  // 有值才挂键 = 非 DS 流零回归
  if (empty.serverToolEvent !== undefined) {
    result.serverToolEvent = empty.serverToolEvent;
  }
  if (empty.serverToolCallsJson !== undefined) {
    result.serverToolCallsJson = empty.serverToolCallsJson;
  }
  if (empty.annotationsJson !== undefined) {
    result.annotationsJson = empty.annotationsJson;
  }
  // 工具调用增量：delta.tool_calls 逐项归一 SseToolDelta（index 缺省 0——单工具流部分
  // provider 不带 index；id/name/argsDelta 有值才带键）
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

// 非 200 响应体提取人话错误文案（提取失败/无命中返回空串，调用方回退展示原文）。
// Anthropic/Gemini 的错误体同为 {"error":{"message":...}} 信封——三协议共用。
// ★ 兜底链（RikkaHub ErrorParser 同向）：单一信封之外的常见网关形态此前落空串 →
// ChatStreamBase 把原始 JSON 体整段拼上屏——现按链提取 = ①error.message（OpenAI 官方）→
// ②error.detail（FastAPI 式）→ ③error 裸串直取 → ④顶层 message / detail / description
//（网关裸形态）；空串/缺席不命中即落下一级，全链空才回 ''（typeof 守卫全覆盖，坏体
// 不炸；BalanceApi/ModelListApi 两处同名独立成份未随改）。
// ★ ②③级入口守卫用 `typeof body === 'object' && body !== null` 而非
// `body !== undefined && body !== null`——旧守卫漏防「空串字面量」：string 收窄的否定
// 分支里排除不了 ''，`.message` 访问即编译报错（dev 报障 10505001）；对象判别一次排除
// 空串/undefined/null 三态（typeof null === 'object' 故 null 单列），全链取值行为等价
export function extractApiError(text: string): string {
  try {
    const envelope: ChatErrorEnvelope = JSON.parse(text) as ChatErrorEnvelope;
    const body: ChatErrorBody | string | undefined = envelope.error;
    if (typeof body === 'string' && body !== '') {
      return body; // 裸串信封 {"error":"..."}
    }
    if (typeof body === 'object' && body !== null) {
      if (typeof body.message === 'string' && body.message !== '') {
        return body.message;
      }
      if (typeof body.detail === 'string' && body.detail !== '') {
        return body.detail;
      }
    }
    if (typeof envelope.message === 'string' && envelope.message !== '') {
      return envelope.message;
    }
    if (typeof envelope.detail === 'string' && envelope.detail !== '') {
      return envelope.detail;
    }
    if (typeof envelope.description === 'string' && envelope.description !== '') {
      return envelope.description;
    }
    return '';
  } catch (e) {
    return '';
  }
}

// ── Anthropic Messages 流式载荷（样例即规格，断言在 scripts/sse-assert.mjs ⑨）──
// data 载荷自带 type 字段路由（event: 行可忽略）：
// · content_block_delta 且 delta.type=text_delta → delta.text = 正文增量；
//   delta.type=thinking_delta → delta.thinking = 思考链增量（未开启扩展思考不出现）；
// · message_stop → 终止标记（OpenAI [DONE] 的等价物）；error → 流中错误帧
//  （errorMessage 取 error.message）；
// · message_start / content_block_stop / message_delta / ping / 其他 delta 子类 →
//   合法无增量帧；content_block_start(tool_use) 与 input_json_delta = 工具调用增量
//  （SseToolDelta 归一形态见文件头）

export interface AnthropicDeltaBody {
  type?: string;
  text?: string;
  thinking?: string;
  partial_json?: string; // 工具入参增量（input_json_delta）
  stop_reason?: string; // 终止理由（message_delta 帧携带，'max_tokens' = 截断）
}

// content_block_start 的块头（type='tool_use' 携带 id/name——text/thinking 块同样走此
// 结构但无消费字段，kind='other' 不变）
export interface AnthropicBlockStart {
  type?: string;
  id?: string;
  name?: string;
}

// message_start 帧的 message 块（usage.input_tokens = 本轮输入消耗，官方规格；
// output_tokens 初始值存在但被 take-max 归一覆盖，不单列）
export interface AnthropicMessageStart {
  usage?: AnthropicUsageBlock;
}

// usage 数字块（message_start.message.usage 与 message_delta.usage 同构消费——后者的
// output_tokens 官方语义 = 整条消息累积总量，合并在 mergeUsage 取大）。缓存命中两桶：
// cache_read（读，0.1× 计费）与 cache_creation（写，1.25× 计费）——官方语义两桶均**不在
// input_tokens 内**，故 promptTokens 须三桶相加（anthropicPromptTotal）、cachedTokens 只记 read
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
  message?: AnthropicMessageStart; // message_start 帧载荷
  usage?: AnthropicUsageBlock; // message_delta 帧 usage
  error?: ChatErrorBody;
}

// 载荷处置结果：kind = 'delta'（有增量）/ 'stop'（终止标记）/ 'error'（流中错误帧）/
// 'other'（合法无增量）；null = 坏帧（截断/垃圾 JSON——上游计数跳过不阻断）
export interface AnthropicPayload {
  kind: string;
  delta: SseDelta;
  errorMessage: string;
}

// Anthropic 输入全量加法：官方 input_tokens = 未缓存输入，cache 两桶另列——promptTokens
// 语义 = 全量输入，须 input + cache_read + cache_creation 三桶相加（只取首桶 = 开提示缓存
// 后「输入」显示偏小的存量缺陷，RikkaHub 同款加法）。非 number 按 0 计（JSON null/缺席兜底）
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
  // 根形状校验：载荷 null/数组/标量 → 坏帧同路（原在 event.type 解引用抛出）；本入口
  // 无顶层数组消费，只守根（范围克制——不为四方言同形加无消费面的校验）
  if (!isJsonObject(event)) {
    return null;
  }
  const empty: SseDelta = { content: '', reasoningContent: '' };
  // 用量提取：message_start 走 message.usage（input 为主）、message_delta 走顶层 usage
  //（output = 整条消息累积量，mergeUsage 取大合并）——两帧均落 kind='other' 合法无增量，
  // 挂 usage 不变 kind（消费方经 delta.usage 收）。两帧同式全量加法（prompt = 三桶和、
  // cached 只记 read）；个别代理在 message_delta 帧重复给 cache 值——take-max 天然吸收
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
  // 截断标记：message_delta 帧的 delta.stop_reason = 'max_tokens' ⇒ 输出被上限打满
  //（官方规格值；思考 + 正文共享预算，见文件头）。★ 判据独立于上方 usage 分支——该帧
  // 缺 usage 时同样要认，勿并进 usage 守卫里（否则网关省字段即丢信号）。该帧仍返回
  // kind='other'（usage 与 kind 语义原样不变）
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
      // 工具入参增量：partial_json 拼接式——index 对位 content_block_start
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
    // 工具调用块开始：type='tool_use' 携带 id/name；文本/思考块 start 走下方
    // kind='other' 兜底不变
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

// ── Gemini streamGenerateContent?alt=sse 流式载荷（断言在 scripts/sse-assert.mjs ⑩）──
// 增量 = candidates[0].content.parts 各段 text 合并（官方流式多 part 并存）；无 candidates
// 的帧（usageMetadata 统计尾帧等）= 合法无增量。Gemini 无终止标记帧——流即体，dataEnd
// 收尾即完成（协议流层 requireDoneMarker=false 分支）。思考摘要段：请求带 includeThoughts
// 时思考摘要以 parts[].thought=true 回传（官方 Part.thought 字段）——路由进
// reasoningContent（思考块显示）不混正文；未开启思考的模型无该标记，行为不变（⑩ 组零回归）

// Gemini 函数调用段（无增量概念——整帧 {name, args} 即完整调用，归一为 argsFull 替换式
// SseToolDelta；index 恒 -1 = 调用方「整调用追加」语义）
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
  finishReason?: string; // 终止理由（'MAX_TOKENS' = 输出被上限打满）
}

// usageMetadata 统计块（官方 GenerateContentResponse 规格字段——流式一般在末帧；部分
// 网关每帧携带累积值，mergeUsage 取大归一）。cachedContentTokenCount
//（promptTokenCount 已含命中部分——Gemini 官方语义，cached 只是其中标注）
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
// usageMetadata 两计数提取（统计尾帧无 candidates 走 empty 兜底带 usage；数据帧若同带
// 统计块也提取，累积值由 mergeUsage 取大）
export function parseGeminiDelta(payload: string): SseDelta | null {
  let chunk: GeminiChunk;
  try {
    chunk = JSON.parse(payload) as GeminiChunk;
  } catch (e) {
    return null;
  }
  // 根形状校验：载荷 null/数组/标量 → 坏帧同路（原在 chunk.usageMetadata 解引用抛出）
  if (!isJsonObject(chunk)) {
    return null;
  }
  const empty: SseDelta = { content: '', reasoningContent: '' };
  // null 守卫：同 chat choices:null 家族——成员为 JSON null 时按缺席收
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
  // 元素形状校验：candidates[0] 运行时可为 null/标量（如 {"candidates":[null]}）——非对象
  // 即整帧判废，防 finishReason 解引用抛出
  if (!isJsonObject(candidates[0] ?? null)) {
    return null;
  }
  // 截断标记：finishReason='MAX_TOKENS' = 输出被 maxOutputTokens 打满（官方规格值；
  // 思考 + 正文共享预算，见文件头）。★ 两出口都要覆盖——该帧常无 content.parts（走下方
  // 早返回），故在 candidates 非空后即判并同时挂 empty
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
  // parts 形状校验：非数组（如 {"content":{"parts":{}}}）时 for..of 抛 TypeError——判废
  // 同路；parts 缺席/null 仍走上方合法无增量（截断标记帧形态，语义不变）
  if (!Array.isArray(parts)) {
    return null;
  }
  let text: string = '';
  let thought: string = '';
  const toolCalls: SseToolDelta[] = [];
  for (const part of parts) {
    // 元素形状校验：parts 含 null/标量元素（如 {"parts":[null]}）即整帧判废——
    // part.text / part.functionCall 解引用抛出点
    if (!isJsonObject(part ?? null)) {
      return null;
    }
    if (typeof part.text === 'string') {
      if (part.thought === true) {
        thought += part.text; // 思考摘要段：进思考链（thinking 块），不混正文
      } else {
        text += part.text;
      }
    }
    // 函数调用段：整调用无序位——index=-1、argsFull 全量（args 缺省 {}）
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
    result.usage = empty.usage; // 数据帧同带 usageMetadata 时转移
  }
  if (toolCalls.length > 0) {
    result.toolCalls = toolCalls;
  }
  return result;
}
