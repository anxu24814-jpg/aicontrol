// 协议流工厂 + 四协议方言子类（原 OpenAiCompatApi.ets / AnthropicChatStream.ets /
// GeminiChatStream.ets / ResponsesChatStream.ets 四件薄方言文件按「并入既有同域文件优先」
// 并回本文件）。传输状态机（HTTP 竞态 / SSE 攒帧 / 坏帧容错 / 三错误路径中文提示 / 终态
// 闸 / 成对释放）全部在 ChatStreamBase.ets——本文件 = 工厂分发 + 四协议各自覆写四个钩子：
// endpoint（拼 URL）/ requestHeaders（认证头族）/ requestBody（方言请求体，纯函数在
// RequestCompose）/ consumePayload（data 载荷 → 增量路由）+ requireDoneMarker。
// 回归红线：openai 路径行为不变；sse-assert 断言的解析层（SseParser）零改动。
// 工厂分发：按 providers.protocol + providers.endpoint 分发 ChatStream 实现，ChatSendCtrl
// 发送编排唯一消费方。协议值域与兜底语义：仅 anthropic/gemini 走原生实现，其余（含
// openai 与未知值）回落 OpenAI 兼容（存量数据/异常值的保守路径——协议常量表见
// AiTypes.ets）；openai 族内 endpoint=responses → ResponsesChatStream（/v1/responses
// 官方新接口，仅官方端点支持——第三方「OpenAI 兼容」中转不实现），endpoint=chat 与
// 未知值回落 chat/completions。
import {
  AiChatMessage, AiConnection, AiStreamHandlers, AiToolDef, ChatStream, connectionOffEnabled,
  ENDPOINT_RESPONSES, isOfficialOpenAiBaseUrl, PROTOCOL_ANTHROPIC, PROTOCOL_GEMINI,
  SamplingParams
} from './AiTypes';
import { ChatStreamBase } from './ChatStreamBase';
import {
  AnthropicCacheParam, composeAnthropicBody, composeGeminiBody, composeOpenAiBody
} from './RequestCompose';
// 二期 S3 域级最小拆分：Responses 组装与解析各成一件（断言直跑副本按同源拼接装载）
import { composeOpenAiResponsesBody } from './RequestComposeResponses';
import {
  AnthropicPayload, parseAnthropicPayload, parseChatDelta, parseGeminiDelta, SseDelta
} from './SseParser';
import { parseResponsesPayload, ResponsesPayload } from './SseResponsesParse';

export function createChatStream(protocol: string, endpoint: string,
  handlers: AiStreamHandlers): ChatStream {
  if (protocol === PROTOCOL_ANTHROPIC) {
    return new AnthropicChatStream(handlers);
  }
  if (protocol === PROTOCOL_GEMINI) {
    return new GeminiChatStream(handlers);
  }
  // openai 族按接口形态分发（口径见文件头）
  if (endpoint === ENDPOINT_RESPONSES) {
    return new ResponsesChatStream(handlers);
  }
  return new OpenAiChatStream(handlers);
}

// ═══ OpenAI 兼容协议流：POST {baseUrl}/chat/completions（stream=true）——认证头
// Authorization: Bearer；载荷路由 = [DONE] 终止标记 + parseChatDelta 增量 + 流中错误帧
//（delta.errorMessage 非空即 failStream，形制照 Anthropic 分支——否则 {"error":...} 帧
// 被当合法空帧吞掉，错误原因丢失且流末误报「连接中断」）；坏帧（JSON 截断/垃圾）计数
// 跳过不阻断 ═══
class OpenAiChatStream extends ChatStreamBase {
  constructor(handlers: AiStreamHandlers) {
    super(handlers);
  }

  protected endpoint(conn: AiConnection): string {
    return conn.baseUrl.replace(/\/+$/, '') + '/chat/completions';
  }

  protected requestHeaders(conn: AiConnection, apiKey: string): Record<string, string> {
    return {
      'Authorization': 'Bearer ' + apiKey,
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream'
    };
  }

  protected requestBody(conn: AiConnection, messages: AiChatMessage[], thinking: string,
    sampling: SamplingParams | null, tools: AiToolDef[] = []): string {
    // 行为 = 自 RequestCompose，样本即规格（sse-assert ⑪ 组断言落点；逐字节一致）；
    // 关闭档 offEnabled = DeepSeek 官方域才产 thinking.disabled（互斥见 compose 注释），
    // 判定源 connectionOffEnabled(conn)（AiTypes 单源）；sampling 透传（null = 零字段）
    // DS 扩展字段（二期 S2）：两布尔来自基类 dsExtras（起流咽喉点算好，缺省 null = 零变化）
    return composeOpenAiBody(conn.model, messages, thinking, connectionOffEnabled(conn),
      sampling, tools,
      this.dsExtras !== null && this.dsExtras.title,
      this.dsExtras !== null && this.dsExtras.safety);
  }

  protected consumePayload(payload: string): boolean {
    if (payload === '[DONE]') {
      return true;
    }
    const delta: SseDelta | null = parseChatDelta(payload);
    if (delta === null) {
      this.noteBadFrame();
      return false;
    }
    this.absorbUsage(delta.usage); // usage 两形态吸收（独立统计尾帧 / DS 式末内容帧挂载）
    this.absorbTruncated(delta.truncated); // 截断标记：finish_reason=length
    // 流中错误帧：chat 方言 {"error":...} 帧吞掉会丢错误原因且流末误报「连接中断」
    //（背景见类头），形制照下方 Anthropic 分支同款 failStream（错误帧 ≠ 传输层失败）
    if (delta.errorMessage !== undefined && delta.errorMessage !== '') {
      this.failStream('请求失败(流中错误帧)：' + delta.errorMessage);
      return false;
    }
    this.deliverDelta(delta);
    return false;
  }
}

// ═══ Anthropic Messages 协议流：POST {baseUrl}/v1/messages（stream=true）——认证头
// x-api-key（非 Bearer）+ anthropic-version: 2023-06-01（官方版本协商头，固定值照规格）；
// 请求体 system 提顶层（多条空行连接）/ max_tokens 三态（未配置 8192 / 显式 0 兜底
// 131072 / 正数用值——「恒 8192」为采样参数笔前旧口径已核正，实现见
// RequestCompose.composeAnthropicBody）；载荷路由 = parseAnthropicPayload（type 字段路由：
// text_delta/thinking_delta 增量、message_stop 终止标记、error 流中错误帧、其余合法无增量
// 帧）。官方 baseUrl 模板 https://api.anthropic.com ═══
class AnthropicChatStream extends ChatStreamBase {
  constructor(handlers: AiStreamHandlers) {
    super(handlers);
  }

  protected endpoint(conn: AiConnection): string {
    return conn.baseUrl.replace(/\/+$/, '') + '/v1/messages';
  }

  protected requestHeaders(conn: AiConnection, apiKey: string): Record<string, string> {
    return {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream'
    };
  }

  protected requestBody(conn: AiConnection, messages: AiChatMessage[], thinking: string,
    sampling: SamplingParams | null, tools: AiToolDef[] = []): string {
    // 行为 = 自 RequestCompose，样本即规格（sse-assert ⑪ 组断言落点；逐字节一致——
    // system 提顶层多条 \n\n 连接 / max_tokens 三态 / 无 system 省略字段）；关闭档：
    // DeepSeek/anthropic 域才产 reasoning{effort:none}（官方 Anthropic 端点不认，非域零
    // 字段），判定源 connectionOffEnabled(conn)；采样透传（temperature 官方域 0~1 clamp
    // 在 compose）；提示缓存（DB v12）：promptCache* 两字段 → cache 参（TTL 映射 '1h' →
    // ttlHour，断点落点在 compose）
    const cache: AnthropicCacheParam | undefined = conn.promptCacheEnabled === true ?
      { enabled: true, ttlHour: conn.promptCacheTtl === '1h' } : undefined;
    return composeAnthropicBody(conn.model, messages, thinking, connectionOffEnabled(conn),
      sampling, cache, tools);
  }

  protected consumePayload(payload: string): boolean {
    const result: AnthropicPayload | null = parseAnthropicPayload(payload);
    if (result === null) {
      this.noteBadFrame(); // 坏帧容错：跳过不阻断（照 OpenAI 先例）
      return false;
    }
    this.absorbUsage(result.delta.usage); // message_start·message_delta 两帧
    this.absorbTruncated(result.delta.truncated); // 截断标记：stop_reason=max_tokens
    if (result.kind === 'stop') {
      return true; // message_stop = 终止标记（[DONE] 等价物）
    }
    if (result.kind === 'error') {
      const detail: string = result.errorMessage !== '' ? '：' + result.errorMessage : '';
      this.failStream('请求失败(流中错误帧)' + detail);
      return false;
    }
    if (result.kind === 'delta') {
      this.deliverDelta(result.delta);
    }
    return false; // 'other' = 合法无增量帧（message_start/ping 等）
  }
}

// ═══ Gemini streamGenerateContent 协议流：POST {baseUrl}/v1beta/models/{model}:
// streamGenerateContent?alt=sse——认证头 x-goog-api-key（非 Bearer、非 query 参数，规格
// 拍板形态）；请求体 system 提为 systemInstruction.parts、role 映射 assistant → model、
// 无 stream 字段（SSE 由 alt=sse 查询参开启）；完成语义 requireDoneMarker = false——
// Gemini 流无终止标记帧，dataEnd 收尾即完成；载荷路由 = parseGeminiDelta（candidates[0]
// .content.parts 各段 text 合并）。官方 baseUrl 模板
// https://generativelanguage.googleapis.com═══
class GeminiChatStream extends ChatStreamBase {
  constructor(handlers: AiStreamHandlers) {
    super(handlers);
  }

  protected endpoint(conn: AiConnection): string {
    // model 名进入路径段（官方 URL 形态 models/{model}:streamGenerateContent）——
    // encodeURIComponent 防特殊字符破路径；':' 是分隔符留在 encode 外
    return conn.baseUrl.replace(/\/+$/, '') + '/v1beta/models/' +
      encodeURIComponent(conn.model) + ':streamGenerateContent?alt=sse';
  }

  protected requestHeaders(conn: AiConnection, apiKey: string): Record<string, string> {
    return {
      'x-goog-api-key': apiKey,
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream'
    };
  }

  protected requestBody(conn: AiConnection, messages: AiChatMessage[], thinking: string,
    sampling: SamplingParams | null, tools: AiToolDef[] = []): string {
    // 行为 = 自 RequestCompose，样本即规格（sse-assert ⑪ 组断言落点；逐字节一致——
    // systemInstruction.parts 包装 / assistant→model / 无 stream 字段、模型名在 URL 不进
    // body；采样透传，generationConfig 与 thinkingConfig 共存在 compose）
    return composeGeminiBody(messages, thinking, sampling, tools);
  }

  protected consumePayload(payload: string): boolean {
    const delta: SseDelta | null = parseGeminiDelta(payload);
    if (delta === null) {
      this.noteBadFrame(); // 坏帧容错：跳过不阻断（照 OpenAI 先例）
      return false;
    }
    this.absorbUsage(delta.usage); // usageMetadata 统计帧/块
    this.absorbTruncated(delta.truncated); // 截断标记：finishReason=MAX_TOKENS
    this.deliverDelta(delta);
    return false; // Gemini 无终止标记帧——恒 false
  }

  protected requireDoneMarker(): boolean {
    return false; // dataEnd 即完成（见类头「完成语义」）
  }
}

// ═══ OpenAI Responses 协议流：POST {baseUrl}/responses（stream=true）——认证头
// Authorization: Bearer（同 OpenAI 兼容）；请求体 = composeOpenAiResponsesBody（system →
// 顶层 instructions；input 兼容 messages 形态；显式 store:false——官方默认服务端存储，
// 项目本地管理上下文原则）；载荷路由 = parseResponsesPayload（output_text.delta 正文 /
// reasoning 两事件思考 / response.completed 终止标记、response.failed 错误帧、其余合法无
// 增量帧）；requireDoneMarker = true——completed 未收到即连接中断（responses 流无
// [DONE] 帧）。官方推荐新项目用 Responses，且仅 OpenAI 官方端点支持——第三方中转不实现 ═══
class ResponsesChatStream extends ChatStreamBase {
  constructor(handlers: AiStreamHandlers) {
    super(handlers);
  }

  protected endpoint(conn: AiConnection): string {
    return conn.baseUrl.replace(/\/+$/, '') + '/responses';
  }

  protected requestHeaders(conn: AiConnection, apiKey: string): Record<string, string> {
    return {
      'Authorization': 'Bearer ' + apiKey,
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream'
    };
  }

  protected requestBody(conn: AiConnection, messages: AiChatMessage[], thinking: string,
    sampling: SamplingParams | null, tools: AiToolDef[] = []): string {
    // 采样透传（官方 Responses 无 penalties 字段——compose 内裁剪）；官方端点 + 带工具
    // 时请求 include:['reasoning.encrypted_content']（stateless 工具轮 reasoning item
    // 保真回传前置——第三方网关不支持，仅官方域开）
    return composeOpenAiResponsesBody(conn.model, messages, thinking, sampling, tools,
      tools.length > 0 && isOfficialOpenAiBaseUrl(conn.baseUrl),
      this.dsExtras !== null && this.dsExtras.title,
      this.dsExtras !== null && this.dsExtras.safety);
  }

  protected consumePayload(payload: string): boolean {
    // [DONE] 兼容终止：官方流以 response.completed 收尾无 [DONE]，但个别翻译层网关在终止
    // 事件后追加 chat 风格 [DONE]——判终止防「连接中断」假错误
    if (payload === '[DONE]') {
      return true;
    }
    const result: ResponsesPayload | null = parseResponsesPayload(payload);
    if (result === null) {
      this.noteBadFrame(); // 坏帧容错：跳过不阻断（照 OpenAI 先例）
      return false;
    }
    this.absorbUsage(result.delta.usage); // completed/incomplete 自带 usage
    this.absorbTruncated(result.delta.truncated); // 截断标记：incomplete+max_output_tokens
    if (result.kind === 'stop') {
      // 二期 S2/S3：终止事件可携带标题 / 完整 output items / 拒答标记——先投递再收尾
      //（漏投 = 标题丢、落库无 items、拒答不撤正文）
      this.deliverDelta(result.delta);
      return true; // response.completed / incomplete = 终止标记（[DONE] 等价物）
    }
    if (result.kind === 'error') {
      const detail: string = result.errorMessage !== '' ? '：' + result.errorMessage : '';
      this.failStream('请求失败(流中错误帧)' + detail);
      return false;
    }
    if (result.kind === 'delta') {
      this.deliverDelta(result.delta);
    }
    return false; // 'other' = 合法无增量帧（response.created 等）
  }
}
