// 协议流工厂 + 四协议方言子类（2026-09-01 反碎片并回：原 OpenAiCompatApi.ets /
// AnthropicChatStream.ets / GeminiChatStream.ets / ResponsesChatStream.ets 四件薄方言文件
// 并入本文件——四者均 ChatStreamFactory 单消费方、同域「协议方言钩子」，原拆分动因 =
// 每件独立成文件的搬运成本，宪法修订〔600 软引导 / 1000 硬线 + 反碎片下限〕后按「并入
// 既有同域文件优先」复归。传输状态机（HTTP 竞态 / SSE 攒帧 / 坏帧容错 / 三错误路径中文
// 提示 / 终态闸 / 成对释放）全部在 ChatStreamBase.ets——本文件 = 工厂分发 + 四协议各自
// 覆写四个钩子：endpoint（拼 URL）/ requestHeaders（认证头族）/ requestBody（方言请求体，
// 纯函数在 RequestCompose）/ consumePayload（data 载荷 → 增量路由）+ requireDoneMarker。
// openai 路径行为不变——回归红线；sse-assert 断言的解析层（SseParser）零改动）。
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
  AnthropicCacheParam, composeAnthropicBody, composeGeminiBody, composeOpenAiBody,
  composeOpenAiResponsesBody
} from './RequestCompose';
import {
  AnthropicPayload, parseAnthropicPayload, parseChatDelta, parseGeminiDelta,
  parseResponsesPayload, ResponsesPayload, SseDelta
} from './SseParser';

export function createChatStream(protocol: string, endpoint: string,
  handlers: AiStreamHandlers): ChatStream {
  if (protocol === PROTOCOL_ANTHROPIC) {
    return new AnthropicChatStream(handlers);
  }
  if (protocol === PROTOCOL_GEMINI) {
    return new GeminiChatStream(handlers);
  }
  // openai 族按接口形态分发：responses → /v1/responses（OpenAI 官方新接口，仅官方端点
  // 支持——第三方「OpenAI 兼容」中转不实现）；其余（chat 与未知值）回落 OpenAI 兼容
  if (endpoint === ENDPOINT_RESPONSES) {
    return new ResponsesChatStream(handlers);
  }
  return new OpenAiChatStream(handlers);
}

// ═══ OpenAI 兼容协议流（2026-08-29 任务书 M1 新增；2026-08-30 三协议改造瘦身为协议钩子层；
// 2026-09-01 自 OpenAiCompatApi.ets 并回）：POST {baseUrl}/chat/completions（stream=true）
// ——认证头 Authorization: Bearer；载荷路由 = [DONE] 终止标记 + parseChatDelta 增量；坏帧
//（JSON 截断/垃圾）计数跳过不阻断（容错照先例）═══
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
    // ★ 2026-08-31 关闭档：offEnabled = DeepSeek 官方域才产 thinking.disabled（openai-关闭
    // 思考互斥见 compose 注释）；2026-09-03 Cube 吸收 A2：改 connectionOffEnabled(conn)
    //（reasoningStrategy deepseek 策略快速分支 + 画像命中回落——单一判定源见 AiTypes，
    // 全矩阵与旧 supportsThinkingOff(baseUrl) 等价零回归）；
    // 2026-09-01 采样：sampling 透传（null = 零字段零回归，断言 ㉒ 组）
    return composeOpenAiBody(conn.model, messages, thinking, connectionOffEnabled(conn),
      sampling, tools);
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
    this.absorbUsage(delta.usage); // usage 两形态吸收（独立统计尾帧 / DS 式末内容帧挂载，2026-09-06）
    this.absorbTruncated(delta.truncated); // 截断标记（2026-09-23）：finish_reason=length
    this.deliverDelta(delta);
    return false;
  }
}

// ═══ Anthropic Messages 协议流（2026-08-30 三协议新增）：POST {baseUrl}/v1/messages
//（stream=true）——认证头 x-api-key（非 Bearer）+ anthropic-version: 2023-06-01（官方版本
// 协商头，固定值照规格）；请求体 system 提顶层（多条空行连接）/ max_tokens 三态
//（未配置 8192 / 显式 0 兜底 131072 / 正数用值——原「恒 8192」为采样参数笔前旧口径，
// 2026-09-13 全码优化笔1 核正，实现见 RequestCompose.composeAnthropicBody）；
// 载荷路由 = parseAnthropicPayload（type 字段路由：text_delta/thinking_delta 增量、
// message_stop 终止标记、error 流中错误帧、其余合法无增量帧）。端点规格：官方 baseUrl
// 模板 https://api.anthropic.com（拼 /v1/messages）═══
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
    // system 提顶层多条 \n\n 连接 / max_tokens 三态〔未配置 8192/显式 0 兜底 131072/正数
    // 用值〕/ 无 system 省略字段）；★ 2026-08-31 关闭档：DeepSeek/anthropic 域才产
    // reasoning{effort:none}（官方 Anthropic 端点不认，非域零字段）；2026-09-03 Cube 吸收
    // A2：改 connectionOffEnabled(conn)（单一判定源见 AiTypes——anthropic 形态 DeepSeek
    // 域 off 语义经画像命中回落保留，零回归）；2026-09-01 采样透传（temperature 官方域
    // 0~1 clamp 在 compose）；★ 2026-09-01 提示缓存（DB v12）：连接 promptCache* 两字段
    // → cache 参（undefined/关 = 零回归；TTL 映射 '1h' → ttlHour，断点落点在 compose）
    const cache: AnthropicCacheParam | undefined = conn.promptCacheEnabled === true ?
      { enabled: true, ttlHour: conn.promptCacheTtl === '1h' } : undefined;
    return composeAnthropicBody(conn.model, messages, thinking, connectionOffEnabled(conn),
      sampling, cache, tools);
  }

  protected consumePayload(payload: string): boolean {
    const result: AnthropicPayload | null = parseAnthropicPayload(payload);
    if (result === null) {
      this.noteBadFrame(); // 坏帧容错：跳过不阻断（截断/垃圾帧，照 OpenAI 先例）
      return false;
    }
    this.absorbUsage(result.delta.usage); // message_start·message_delta 两帧（2026-09-06）
    this.absorbTruncated(result.delta.truncated); // 截断标记（2026-09-23）：stop_reason=max_tokens
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

// ═══ Gemini streamGenerateContent 协议流（2026-08-30 三协议新增）：
// POST {baseUrl}/v1beta/models/{model}:streamGenerateContent?alt=sse——认证头
// x-goog-api-key（非 Bearer、非 query 参数——规格拍板形态）；请求体 system 提为
// systemInstruction.parts、role 映射 assistant → model、无 stream 字段（SSE 由 alt=sse
// 查询参开启）；完成语义 requireDoneMarker = false——Gemini 流无终止标记帧，dataEnd
// 收尾即完成；载荷路由 = parseGeminiDelta（candidates[0].content.parts 各段 text 合并）。
// 端点规格：官方 baseUrl 模板 https://generativelanguage.googleapis.com═══
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
    // systemInstruction.parts 包装 / assistant→model / 无 stream 字段；模型名在 URL 不进
    // body）；2026-09-01 采样透传（generationConfig 与 thinkingConfig 共存在 compose）
    return composeGeminiBody(messages, thinking, sampling, tools);
  }

  protected consumePayload(payload: string): boolean {
    const delta: SseDelta | null = parseGeminiDelta(payload);
    if (delta === null) {
      this.noteBadFrame(); // 坏帧容错：跳过不阻断（截断/垃圾帧，照 OpenAI 先例）
      return false;
    }
    this.absorbUsage(delta.usage); // usageMetadata 统计帧/块（2026-09-06）
    this.absorbTruncated(delta.truncated); // 截断标记（2026-09-23）：finishReason=MAX_TOKENS
    this.deliverDelta(delta);
    return false; // Gemini 无终止标记帧——恒 false
  }

  protected requireDoneMarker(): boolean {
    return false; // dataEnd 即完成（见类头「完成语义」）
  }
}

// ═══ OpenAI Responses 协议流（2026-08-30 Responses 适配）：POST {baseUrl}/responses
//（stream=true）——认证头 Authorization: Bearer（同 OpenAI 兼容）；请求体 =
// composeOpenAiResponsesBody（system → 顶层 instructions；input 兼容 messages 形态；显式
// store:false——官方默认服务端存储，项目本地管理上下文原则）；载荷路由 =
// parseResponsesPayload（output_text.delta 正文 / reasoning 两事件思考 / response.completed
// 终止标记、response.failed 错误帧、其余合法无增量帧）；requireDoneMarker = true——
// completed 未收到即连接中断（responses 流无 [DONE] 帧）。端点规格：官方推荐新项目用
// Responses 且仅 OpenAI 官方端点支持——第三方中转不实现（能力矩阵与配置页文案明示）═══
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
    // 2026-09-01 采样透传（官方 Responses 无 penalties 字段——compose 内裁剪）；
    // 2026-09-06 Responses 修复：官方端点 + 带工具时请求 include:['reasoning.encrypted_content']
    //（stateless 工具轮 reasoning item 保真回传前置——第三方网关不支持此 include，仅官方域开）
    return composeOpenAiResponsesBody(conn.model, messages, thinking, sampling, tools,
      tools.length > 0 && isOfficialOpenAiBaseUrl(conn.baseUrl));
  }

  protected consumePayload(payload: string): boolean {
    // [DONE] 兼容终止（2026-09-06 Responses 修复）：官方流以 response.completed 收尾无
    // [DONE]，但个别翻译层网关在终止事件后追加 OpenAI chat 风格 [DONE]——判终止防
    // 「连接中断」假错误（RikkaHub 解码器同款收）
    if (payload === '[DONE]') {
      return true;
    }
    const result: ResponsesPayload | null = parseResponsesPayload(payload);
    if (result === null) {
      this.noteBadFrame(); // 坏帧容错：跳过不阻断（截断/垃圾帧，照 OpenAI 先例）
      return false;
    }
    this.absorbUsage(result.delta.usage); // completed/incomplete 自带 usage（2026-09-06）
    this.absorbTruncated(result.delta.truncated); // 截断标记（2026-09-23）：incomplete+max_output_tokens
    if (result.kind === 'stop') {
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
