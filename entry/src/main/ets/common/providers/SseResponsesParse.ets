// OpenAI Responses 协议流式载荷解析域（DS 全家桶二期 S3 自 SseParser 域级最小拆分迁出）。
// 一句话职责 =「Responses SSE data 载荷 → 归一 SseDelta / 终止标记 / 错误帧」——纯函数面，
// 零 kit 依赖（isJsonObject / usageFrameOf / serverToolUseOf 等共用叶子自 SseParser 引）。
// · 拆出理由（宪法 1200 硬线）：S3 新增官方联网事件族（web_search_call 三态 / output_item
//   携带 sources·page / annotation.added）后 SseParser 剔头超线；按域级最小拆分把整个
//   Responses 解析段外迁，CC/Anthropic/Gemini 三段一行未动。
// · 断言装载：sse-assert / assert-app-domain / assert-feature-domain 直跑副本把本件剥 import
//   后**拼接**到 SseParser.ts 尾部（同文件内共享 isJsonObject/usageFrameOf 等叶子；无重名导出）。

// 共用叶子（SseParser 导出；直跑副本拼接时这些 import 被剥掉，同文件内定义已在前）
import {
  AiReasoningItem, AiServerToolUse, AiUsageDelta, ChatErrorBody, ChatServerToolUse,
  ChatCompletionTokensDetails, isJsonObject, serverToolUseOf, SseDelta, SseServerToolEvent,
  SseToolDelta, usageFrameOf
} from './SseParser';

// ── OpenAI Responses API 流式载荷（断言在 scripts/sse-assert.mjs ⑬）──
// data JSON 自带 type 字段路由（event: 行同 Anthropic 忽略——feed 只取 data: 行）：
// · response.output_text.delta → delta（裸字符串）= 正文增量（★ 官方 delta 为裸串非
//   {text} 对象——原对象形态解析恒空串，responses 文本流自适配起从未真机验证过；
//   双形态兼容 {text} 兜底）；
// · response.reasoning_text.delta / response.reasoning_summary_text.delta → delta（裸
//   字符串）= 思考链增量（推理模型两事件官方均存在——兼容收；无该增量时 thinking 块
//   自然隐藏）；
// · response.completed / response.incomplete → 终止标记（★ incomplete = 输出截断的合法
//   终止事件，RikkaHub 同款双终止——漏收会误判「连接中断」假错误；两事件均携带
//   response.usage 供用量提取）；
// · response.failed / 裸 error → 流中错误帧（errorMessage 取 error.message）；
// · response.output_item.added/done（item.type='reasoning' 且带 id+encrypted_content）
//   → reasoning 输出项捕获（官方 stateless 工具轮回传保真要求）；
// · response.created / in_progress / content_part.added / output_item(message) 等 →
//   合法无增量帧

export interface ResponsesDeltaBody {
  text?: string;
}

// function_call 输出项（output_item.added/done 且 item.type='function_call' 时携带
// call_id/name/arguments——聚合按 output_index 对位）；id/encrypted_content = reasoning
// 输出项捕获字段（item.type='reasoning' 时携带，保真回传料见 AiReasoningItem）
export interface ResponsesOutputItem {
  type?: string;
  call_id?: string;
  name?: string;
  arguments?: string;
  id?: string;
  encrypted_content?: string;
  // ── 二期 S3：DS 官方联网 output item（web_search_call）──
  // type='web_search_call' 时携带：kind（search / deep_search / image_search / read_link 等）、
  // status（in_progress / searching / completed / failed）、action（{type,queries|url|pattern}）、
  // sources（搜索结果数组）、page（读链接/打开网页的页面信息）与 error。signature **不读**
  // （方案档 §4.1 拍板：展示零贡献、只在官方端点原样回传时才生效，本批不存）
  kind?: string;
  status?: string;
  action?: Object;
  sources?: Object[];
  page?: Object;
  error?: Object;
  // message item 的图片拦截说明（方案档 §4.5：Responses 侧 refusal 在 output 内 message item
  // ——官方原文语义 = 「请求中的图片未通过审核」，不撤正文，单独呈报）
  refusal?: string;
}

// usage 统计块（Responses 自带 usage 无需 stream_options——官方规格，随
// response.completed/incomplete 终止事件到达；字段名 input_tokens/output_tokens 与
// chat 方言不同）。缓存命中 = input_tokens_details.cached_tokens（OpenAI 官方嵌套形态，
// input_tokens 已含命中部分——Responses 无厂商变体，不走 chat 式兜底链）
export interface ResponsesUsageBlock {
  input_tokens?: number;
  output_tokens?: number;
  input_tokens_details?: ResponsesInputTokensDetails;
  // 二期 #7：服务端工具计次（usage 顶层子对象）与审核 token（completion 子项）
  server_tool_use?: ChatServerToolUse;
  completion_tokens_details?: ChatCompletionTokensDetails;
}

// OpenAI Responses 官方嵌套命中标注块
export interface ResponsesInputTokensDetails {
  cached_tokens?: number;
}

// 终止事件（completed/incomplete）的 response 块（只声明消费的 usage 字段；DeepSeek 文档
// 明示 incomplete 同样携带完整 response 含 usage）；incomplete_details = 截断理由
//（判据收窄见 parseResponsesPayload 内注释）
export interface ResponsesIncompleteDetails {
  reason?: string;
}

export interface ResponsesCompletedResponse {
  usage?: ResponsesUsageBlock;
  incomplete_details?: ResponsesIncompleteDetails;
  // 二期 #4：会话标题（官方 conversation_title 页逐字表：流式在结束事件的 response.title）
  title?: string;
  // 二期 S3：完整输出 items（官方「把上一轮整个 output 原样放回 input」的取数面）
  output?: Object[];
}

export interface ResponsesEvent {
  type?: string;
  // ★ delta 形态：文本族事件官方为**裸字符串**（微软 Foundry 示例 / RikkaHub 解码器 /
  // DeepSeek 指南同款）；function_call_arguments.delta 同为裸串。{text} 对象形态仅为
  // 个别翻译层网关旧形态——消费侧双形态判别（裸串优先）
  delta?: Object;
  item?: ResponsesOutputItem;
  output_index?: number;
  item_id?: string; // web_search_call.* 状态事件的 item 身份
  arguments?: string; // function_call_arguments.done 的完整参数串
  response?: ResponsesCompletedResponse; // completed/incomplete 载荷
  error?: ChatErrorBody;
  // output_text.annotation.added 的引用标注（url_citation；回放从 output items 内提取，
  // 流内不单列——本字段只作形态声明，保持事件可解析）
  annotation?: Object;
}

// 载荷处置结果（kind 语义与 AnthropicPayload 同构）：'delta'（有增量）/ 'stop'（终止标记）/
// 'error'（流中错误帧）/ 'other'（合法无增量）；null = 坏帧（截断/垃圾/缺 type——
// 上游计数跳过不阻断）
export interface ResponsesPayload {
  kind: string;
  delta: SseDelta;
  errorMessage: string;
}

// Responses usage → 归一用量（二期 #7）：token 三桶 + 审核 token + 服务端计次。只有计次/审核
// 的帧也出（否则「这一轮搜了几次」丢在解析层——与 chat 侧 chatUsageOf 同口径）
function responsesUsageOf(block: ResponsesUsageBlock): AiUsageDelta | undefined {
  const base: AiUsageDelta | undefined = usageFrameOf(block.input_tokens, block.output_tokens,
    block.input_tokens_details !== undefined && block.input_tokens_details !== null ?
      block.input_tokens_details.cached_tokens : undefined);
  const use: AiServerToolUse | undefined = serverToolUseOf(block.server_tool_use);
  const details: ChatCompletionTokensDetails | undefined = block.completion_tokens_details;
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

// web_search_call item → 归一 call（显示面三纯函数吃 type/kind/action/status/sources/page；
// 官方 item 字段直搬，signature 不读）。缺 action 时按 item.kind 兜底空动作，保证步骤行有标题
function responsesCallOf(item: ResponsesOutputItem): string {
  const kind: string = typeof item.kind === 'string' ? item.kind : '';
  const call: Record<string, Object> = {};
  call['type'] = kind === 'read_link' ? 'deepseek_read_url' : 'deepseek_web_search';
  if (kind !== '') {
    call['kind'] = kind;
  }
  if (item.action !== undefined && item.action !== null) {
    call['action'] = item.action;
  }
  if (typeof item.status === 'string' && item.status !== '') {
    // 三态原样透传（自检轮修）：searching / in_progress 必须保留——首版非 failed 一律写
    // completed，渲染面 serverStepStateOf 随之把「进行中」当「已完成」
    call['status'] = item.status;
  }
  if (item.sources !== undefined && item.sources !== null && Array.isArray(item.sources)) {
    call['sources'] = item.sources;
  }
  if (item.page !== undefined && item.page !== null) {
    call['page'] = item.page;
  }
  if (typeof item.id === 'string' && item.id !== '') {
    call['id'] = item.id;
  }
  return JSON.stringify(call);
}

// web_search_call 事件 → 流内步骤行事件（call_started / call_completed 两型；itemJson 原样
// 随行供落库 items）。searching / in_progress 帧只当「已在场」的状态更新（已有行 → completed
// 前不改名；无行 → 建行显示进行中）
function responsesSearchEventOf(type: string, item: ResponsesOutputItem,
  outputIndex: number): SseServerToolEvent {
  const ev: SseServerToolEvent = {
    type: type === 'response.output_item.done' || type === 'response.web_search_call.completed' ?
      'call_completed' : 'call_started',
    step: outputIndex
  };
  ev.callJson = responsesCallOf(item);
  // itemJson：added 也记一份（自检轮补——中止/失败轮只有 added、done 永不到达；首版只认
  // done，rawItems 为空时兜底快照取不到进行中的调用，重进会话步骤行缺行）。同 output_index
  // 由 done 后到覆盖，终态仍以 done 为准；三态事件合成项无 action 不记，避免盖掉 added
  if (type === 'response.output_item.added' || type === 'response.output_item.done') {
    ev.itemJson = JSON.stringify(item);
  }
  return ev;
}

export function parseResponsesPayload(payload: string): ResponsesPayload | null {
  let event: ResponsesEvent;
  try {
    event = JSON.parse(payload) as ResponsesEvent;
  } catch (e) {
    return null;
  }
  // 根形状校验：载荷 null/数组/标量 → 坏帧同路（原在 event.type 解引用抛出）；本入口
  // 无顶层数组消费，只守根（同 Anthropic——范围克制）
  if (!isJsonObject(event)) {
    return null;
  }
  const empty: SseDelta = { content: '', reasoningContent: '' };
  const type: string = event.type !== undefined ? event.type : '';
  if (type === '') {
    return null; // 缺 type = 非 Responses 事件帧（坏帧判定——同 Anthropic 断帧容错）
  }
  // ★ completed 与 incomplete 双终止（官方流式两终止事件——incomplete = 输出被截断
  //〔max_output_tokens 等〕，漏收会把正常截断流误判「连接中断：响应不完整」假错误）；
  // usage 提取对两终止事件同构（incomplete 同样携带完整 response 含 usage）
  if (type === 'response.completed' || type === 'response.incomplete') {
    if (event.response !== undefined && event.response !== null &&
      event.response.usage !== undefined && event.response.usage !== null) {
      const u: AiUsageDelta | undefined = responsesUsageOf(event.response.usage);
      if (u !== undefined) {
        empty.usage = u;
      }
    }
    // 会话标题（二期 #4）：官方逐字表 = 结束事件的 response.title；空/缺省不挂键（回落
    // TitleGen 兜底）
    if (event.response !== undefined && event.response !== null &&
      typeof event.response.title === 'string' && event.response.title !== '') {
      empty.title = event.response.title;
    }
    // 完整输出 items（二期 S3）：原样串落库 + 回传；缺省不挂键
    if (event.response !== undefined && event.response !== null &&
      event.response.output !== undefined && event.response.output !== null &&
      Array.isArray(event.response.output)) {
      empty.responsesOutputJson = JSON.stringify(event.response.output);
    }
    // 截断标记：★ 判据必须是 reason 细值而非 incomplete 事件本身——incomplete 的另一
    // 理由 content_filter 是「被内容过滤掐断」，标成「被上限截断」并建议「提高上限」属
    // 误导（truncated〔= max_output_tokens〕与 filtered 应分列两类）。其余理由不挂键 =
    // 保持现状 kind='stop' 零回归；过滤类是否上屏另立任务书待观测
    if (type === 'response.incomplete' && event.response !== undefined &&
      event.response !== null && event.response.incomplete_details !== undefined &&
      event.response.incomplete_details !== null &&
      event.response.incomplete_details.reason === 'max_output_tokens') {
      empty.truncated = true;
    }
    // 输出侧拒答（二期 #6）：reason='content_filter' = 回答被内容安全过滤（与截断分列两类；
    // 收尾由 ChatDsStreamExtrasCtrl 撤正文改显拒答文案）
    if (type === 'response.incomplete' && event.response !== undefined &&
      event.response !== null && event.response.incomplete_details !== undefined &&
      event.response.incomplete_details !== null &&
      event.response.incomplete_details.reason === 'content_filter') {
      empty.contentFiltered = true;
    }
    return { kind: 'stop', delta: empty, errorMessage: '' };
  }
  if (type === 'response.failed') {
    const body: ChatErrorBody | undefined = event.error;
    const msg: string =
      body !== undefined && body !== null && typeof body.message === 'string' ? body.message : '';
    return { kind: 'error', delta: empty, errorMessage: msg };
  }
  // 裸 error 事件（官方流中错误另一形态——顶层无 response 包裹）
  if (type === 'error') {
    const body: ChatErrorBody | undefined = event.error;
    const msg: string =
      body !== undefined && body !== null && typeof body.message === 'string' ? body.message : '';
    return { kind: 'error', delta: empty, errorMessage: msg };
  }
  if (type === 'response.output_text.delta' || type === 'response.reasoning_text.delta' ||
    type === 'response.reasoning_summary_text.delta') {
    // ★ 官方 delta 为**裸字符串**（微软 Foundry 示例 / RikkaHub 解码器 / DeepSeek
    // Responses 指南同款）——原实现按 {text} 对象解析恒得空串，responses 文本流从未
    // 显示过（真机实锤报错主根因）。双形态兼容：裸串优先（官方），{text} 对象兜底
    // （个别翻译层网关旧形态，防御保留）
    const raw: Object | undefined = event.delta;
    let text: string = '';
    if (typeof raw === 'string') {
      text = raw;
    } else if (raw !== undefined && raw !== null) {
      // null 守卫：JSON null 的 typeof 是 'object' 且 null !== undefined，不守则
      // body.text 取值抛 TypeError——坏帧容错契约（跳过不炸流）破坏
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
  // ── 官方联网三态事件（二期 S3）：in_progress / searching / completed ──
  // 与 output_item.added 同源的两型信号：added 建行（带 action 与 kind），三态事件只推进
  // 状态（缺 added 时也能建行——defensive，标题按 type 兜底「联网操作」）
  if (type === 'response.web_search_call.in_progress' ||
    type === 'response.web_search_call.searching' ||
    type === 'response.web_search_call.completed') {
    const state: ResponsesOutputItem = { type: 'web_search_call' };
    state.status = type === 'response.web_search_call.completed' ? 'completed' : 'in_progress';
    if (typeof event.item_id === 'string' && event.item_id !== '') {
      state.id = event.item_id;
    }
    return {
      kind: 'delta',
      delta: { content: '', reasoningContent: '',
        serverToolEvent: responsesSearchEventOf(type, state,
          typeof event.output_index === 'number' ? event.output_index : 0) },
      errorMessage: ''
    };
  }
  // ── 工具调用事件族 ──
  if (type === 'response.output_item.added' || type === 'response.output_item.done') {
    const item: ResponsesOutputItem | undefined = event.item;
    // 官方联网 output item（web_search_call）：added 带完整 action → 行即出；done 带
    // sources/page → 行终态与来源卡料（itemJson 原样随行落库）
    if (item !== undefined && item !== null && item.type === 'web_search_call') {
      return {
        kind: 'delta',
        delta: { content: '', reasoningContent: '',
          serverToolEvent: responsesSearchEventOf(type, item,
            typeof event.output_index === 'number' ? event.output_index : 0) },
        errorMessage: ''
      };
    }
    if (item !== undefined && item !== null && item.type === 'function_call') {
      const tool: SseToolDelta =
        { index: typeof event.output_index === 'number' ? event.output_index : 0 };
      if (typeof item.call_id === 'string' && item.call_id !== '') {
        tool.id = item.call_id;
      }
      // nameFull 替换式（修复重名循环）：added/done 两事件各带完整名，聚合器 += 拼接
      // 会得「search_helpsearch_help」重名（真机实锤）——走全量覆盖语义
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
    // message item 的图片拦截说明（自检轮补，方案档 §4.5「output 内 message.refusal」）：
    // 只取非空串，投给 ChatDsStreamExtrasCtrl 的图片拒答通道（不撤正文，单独一行提示）
    if (item !== undefined && item !== null && item.type === 'message' &&
      typeof item.refusal === 'string' && item.refusal !== '') {
      return {
        kind: 'delta',
        delta: { content: '', reasoningContent: '', refusal: item.refusal },
        errorMessage: ''
      };
    }
    // reasoning 输出项捕获：added/done 均可能携带 encrypted_content（终值在 done，added
    // 时常空——同 id 后到覆盖先到，聚合在 ChatSendCtrl）；缺 id 或缺 encrypted_content
    // 不构成可回传 item，不捕获。kind='delta'（空文本 + 捕获载荷）——走 deliverDelta
    // 投递路径（门控按 reasoningItems 放行）
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
