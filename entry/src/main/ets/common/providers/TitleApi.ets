// 标题生成非流式通道（2026-09-05 AI 会话标题自动生成任务 4）：一次 http.request() 拿全
// 响应的小请求通道——标题生成是后台一次性小任务，不走聊天流式体系（requestInStream +
// SseParser 攒帧），照 ModelListApi / BalanceApi 非流式先例（expectDataType STRING、
// 三错误路径中文、request 用完即毁无事件绑定）。
// · 请求体方向（★ RequestCompose 零改动红线——断言组样本逐字节不变）：复用四协议 compose
//   纯函数产物再做传输层后处理——openai chat / responses / anthropic 三方产物硬编码
//   stream:true，JSON.parse 后置 stream:false + **剔除 stream_options** 再 stringify
//   （等价于非流式请求体；★ stream_options 是流式专属键、compose 恒带 include_usage，
//   残留会被服务端 400 拒——2026-09-08 沙箱日志实锤「stream_options should be set along
//   with stream = true」，标题与记忆两链曾因此全灭）；gemini 产物无 stream 键（SSE 由
//   URL alt=sse 开启，非流式 = 端点不带查询参），原样发送。
//   参数：thinking='' / tools=[]（不带思考与工具字段）、温度 0.3 + maxOutput 由调用方给
//   （2026-09-08 参数化；★ 2026-09-20 标题/推荐两链同改 0 = 不发 max_tokens 字段 = 模型按
//   自身上限输出〔真机账本实锤：思考模型标题请求 123 笔 106 笔打满 100、思考段烧满正文
//   恒空，照记忆链 2026-09-08 同款拍板——不设思考预算上限，正文靠提示词约束〕；
//   anthropic max_tokens 必填经 maxOutput 三态满足）。
// · 端点/认证头随协议方言（ChatStreamFactory 同款口径）：openai chat =
//   {base}/chat/completions（Bearer）/ responses = {base}/responses（Bearer）/
//   anthropic = {base}/v1/messages（x-api-key + anthropic-version）/ gemini =
//   {base}/v1beta/models/{model}:generateContent（x-goog-api-key，无 alt=sse）。
//   Accept 用 application/json（非 SSE——ModelListApi 同款）。
// · ★ 不消费服务商扩展：自定义 headers 与 body_overrides 不追加（小任务不背中转站扩展，
//   任务书拍板）；提示缓存不传（cache 参缺省零回归）；unknown 协议按 openai chat 兜底
//   （工厂同款保守路径）。
// · 响应正文提取（各协议非流式面，别用流式解析器硬套）：openai chat =
//   choices[0].message.content（reasoning_content 不取）/ responses = output 数组
//   type='message' 项的 content 内 type='output_text' 段文本（REST 原生响应无 SDK 的
//   output_text 聚合字段，须自遍历）/ anthropic = content 数组 type='text' 块文本 /
//   gemini = candidates[0].content.parts 各段 text 合并（thought:true 段防御性剔除——
//   title 请求无 thinking 配置，正常不出现）。
// · 返回 TitleRequestResult：ok=false 时 errorMessage 中文 + status 透出（-1 = 网络错误
//   无状态码）——重试分类（网络/5xx/429 可退避重试，401/403/400 配置鉴权类不重试）在
//   调用方 TitleGen，本层只报事实不决策；truncated = 输出被上限截断（2026-09-23 输出
//   上限治理笔，四协议标记见 extractTitleTruncated）——「缺正文」与「被截断」两种病分开报。
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AiChatMessage, ENDPOINT_RESPONSES, PROTOCOL_ANTHROPIC, PROTOCOL_GEMINI,
  SamplingParams } from './AiTypes';
import { composeAnthropicBody, composeGeminiBody, composeOpenAiBody,
  composeOpenAiResponsesBody } from './RequestCompose';
import { extractApiError } from './SseParser';
import { reqLogBegin, reqLogEnd, reqLogSetResponseHeaders,
  REQ_LOG_STATUS_CANCELED } from '../ReqLog';

const DOMAIN: number = 0x71C6;
const TAG: string = 'TitleApi';

// 标题小请求参数（温度 0.3 低温稳标题沿用 Cube AITaskService；★ 2026-09-20 输出上限
// 100 → 0〔决明拍板照记忆链同口径——思考模型思考段烧满固定 max_tokens 致正文恒空，
// 真机账本 86% 打满率 = 标题不生成主因〕；thinking/tools 恒空不带）
const TITLE_TEMPERATURE: number = 0.3;
const TITLE_MAX_OUTPUT: number = 0;
const CONNECT_TIMEOUT_MS: number = 15000;
// 读超时 30s 级——标题小请求非流式一次性响应，不照聊天流式档（思考模型长停顿场景）
const READ_TIMEOUT_MS: number = 30000;

export interface TitleRequestResult {
  ok: boolean;
  text: string; // ok=true：清洗前原始正文（清洗在 TitleGen）
  errorMessage: string; // ok=false：中文错误描述（含 HTTP 状态与服务商 error.message）
  status: number; // HTTP 状态码；-1 = 网络错误无状态码（TitleGen 据此分类重试）
  // 输出是否被上限截断（2026-09-23 输出上限与超时治理笔；四协议非流式标记见
  // extractTitleTruncated——「思考 + 正文共享输出上限」打满即正文空/半截，与「没按格式
  // 输出」是两种病）；网络错误/坏 JSON 恒 false（无从判定）
  truncated: boolean;
  // 用量三值（2026-09-10 费用估计；各协议非流式 usage 字段提取，缺失/失败回 0——调用方
  // logTaskUsage 按全零不落库守卫；ok=false 的 200 形态〔缺正文〕也如实带回：token 已消耗）
  promptTokens: number;
  completionTokens: number;
  cachedTokens: number;
}

// ── 各协议非流式响应体（只声明消费的字段——ArkTS 对象字面量须挂显式接口，坑 59 ①）──

// openai chat/completions 非流式
interface OpenAiTitleMessage { content?: string }

interface OpenAiTitleChoice { message?: OpenAiTitleMessage; finish_reason?: string }

interface OpenAiTitleUsageDetails { cached_tokens?: number }

interface OpenAiTitleUsage { prompt_tokens?: number; completion_tokens?: number;
  prompt_tokens_details?: OpenAiTitleUsageDetails }

interface OpenAiTitleResponse { choices?: OpenAiTitleChoice[]; usage?: OpenAiTitleUsage }

// openai responses 非流式（output 数组混合形态——message 项的 content 段）
interface ResponsesTitleContentPart { type?: string; text?: string }

interface ResponsesTitleItem { type?: string; content?: ResponsesTitleContentPart[] }

interface ResponsesTitleUsageDetails { cached_tokens?: number }

interface ResponsesTitleUsage { input_tokens?: number; output_tokens?: number;
  input_tokens_details?: ResponsesTitleUsageDetails }

interface ResponsesTitleResponse { output?: ResponsesTitleItem[]; usage?: ResponsesTitleUsage;
  status?: string }

// anthropic messages 非流式（content 块数组；usage 全量加法口径与 SseParser v26 一致——
// 官方 input_tokens 不含 cache 两桶，prompt = input+read+creation、cached 只记 read）
interface AnthropicTitleBlock { type?: string; text?: string }

interface AnthropicTitleUsage { input_tokens?: number; output_tokens?: number;
  cache_read_input_tokens?: number; cache_creation_input_tokens?: number }

interface AnthropicTitleResponse { content?: AnthropicTitleBlock[]; usage?: AnthropicTitleUsage;
  stop_reason?: string }

// gemini generateContent 非流式
interface GeminiTitlePart { text?: string; thought?: boolean }

interface GeminiTitleContent { parts?: GeminiTitlePart[] }

interface GeminiTitleCandidate { content?: GeminiTitleContent; finishReason?: string }

interface GeminiTitleUsageMetadata { promptTokenCount?: number; candidatesTokenCount?: number;
  cachedContentTokenCount?: number }

interface GeminiTitleResponse { candidates?: GeminiTitleCandidate[];
  usageMetadata?: GeminiTitleUsageMetadata }

// 非流式用量提取结果（三值缺失回 0；TitleRequestResult 同名字段直填）。★ 2026-09-15 附件
// OCR 二期起导出 = OcrVisionApi 同款四协议提取复用（导出零行为变化不牵断言——
// resolveTitleEndpoint 同款先例）
export interface TitleUsageFrame {
  promptTokens: number;
  completionTokens: number;
  cachedTokens: number;
}

// 网络层错误描述（ChatStreamBase/ModelListApi 同款口径，独立成份避免为一行复用引互引）
function describeNetError(e: Object): string {
  const biz = e as BusinessError;
  if (typeof biz.code === 'number') {
    const msg: string = typeof biz.message === 'string' && biz.message !== '' ? '，' + biz.message : '';
    return '无法连接服务器(code ' + biz.code + ')' + msg;
  }
  return (e as Error).message !== undefined ? (e as Error).message : '未知错误';
}

// compose 产物 → 非流式请求体：三方硬编码 stream:true 的置 false 并剔除 stream_options
// （流式专属键，残留即被服务端 400 拒——见文件头注）；gemini 无 stream 键原样
// （后处理属传输层组装，RequestCompose 保持零改动——断言样本逐字节不变）。
// ★ 2026-09-08 导出 = 断言资产消费（sse-assert ㉜ 组回归断言「非流式产物不含
// stream_options」——本函数是 400 实锤的修复点，纯函数可直接喂 compose 产物验证）
export function toNonStream(body: string, hasStreamKey: boolean): string {
  if (!hasStreamKey) {
    return body;
  }
  const root: Record<string, Object> = JSON.parse(body) as Record<string, Object>;
  root['stream'] = false as Object;
  // 剔除 stream_options（ArkTS 不支持 delete——重建对象，其余键序不变）
  const cleaned: Record<string, Object> = {};
  for (const key of Object.keys(root)) {
    if (key !== 'stream_options') {
      cleaned[key] = root[key];
    }
  }
  return JSON.stringify(cleaned);
}

// 请求体组装（协议方言分流；消息恒单条 user = 渲染好的提示词全文——RikkaHub 同构）
function buildTitleBody(protocol: string, endpoint: string, model: string, prompt: string,
  maxOutput: number): string {
  const messages: AiChatMessage[] = [{ role: 'user', content: prompt }];
  const sampling: SamplingParams = { temperature: TITLE_TEMPERATURE, maxOutput: maxOutput };
  if (protocol === PROTOCOL_ANTHROPIC) {
    return toNonStream(composeAnthropicBody(model, messages, '', false, sampling), true);
  }
  if (protocol === PROTOCOL_GEMINI) {
    return toNonStream(composeGeminiBody(messages, '', sampling), false);
  }
  if (endpoint === ENDPOINT_RESPONSES) {
    return toNonStream(composeOpenAiResponsesBody(model, messages, '', sampling), true);
  }
  return toNonStream(composeOpenAiBody(model, messages, '', false, sampling), true);
}

// 各协议非流式正文提取；'' = 结构不符/无正文（调用方按错误处理）。★ 2026-09-15 附件 OCR
// 二期起导出 = OcrVisionApi 视觉引擎同款提取复用（零改动导出）
export function extractTitleText(protocol: string, endpoint: string, body: string): string {
  if (protocol === PROTOCOL_ANTHROPIC) {
    const parsed: AnthropicTitleResponse = JSON.parse(body) as AnthropicTitleResponse;
    if (parsed.content === undefined || !Array.isArray(parsed.content)) {
      return '';
    }
    let text: string = '';
    for (const block of parsed.content) {
      if (block.type === 'text' && typeof block.text === 'string') {
        text += block.text;
      }
    }
    return text;
  }
  if (protocol === PROTOCOL_GEMINI) {
    const parsed: GeminiTitleResponse = JSON.parse(body) as GeminiTitleResponse;
    if (parsed.candidates === undefined || !Array.isArray(parsed.candidates) ||
      parsed.candidates.length === 0) {
      return '';
    }
    const content: GeminiTitleContent | undefined = parsed.candidates[0].content;
    if (content === undefined || content.parts === undefined || !Array.isArray(content.parts)) {
      return '';
    }
    let text: string = '';
    for (const part of content.parts) {
      // thought:true = 思考摘要段（title 请求未开思考，防御性剔除不进标题）
      if (part.thought !== true && typeof part.text === 'string') {
        text += part.text;
      }
    }
    return text;
  }
  if (endpoint === ENDPOINT_RESPONSES) {
    // REST 原生响应无 SDK 聚合的 output_text 字段——自遍历 output 数组（官方语义：
    // type='message' 项的 content 段内 type='output_text' 文本）
    const parsed: ResponsesTitleResponse = JSON.parse(body) as ResponsesTitleResponse;
    if (parsed.output === undefined || !Array.isArray(parsed.output)) {
      return '';
    }
    let text: string = '';
    for (const item of parsed.output) {
      if (item.type !== 'message' || item.content === undefined) {
        continue;
      }
      for (const part of item.content) {
        if (part.type === 'output_text' && typeof part.text === 'string') {
          text += part.text;
        }
      }
    }
    return text;
  }
  const parsed: OpenAiTitleResponse = JSON.parse(body) as OpenAiTitleResponse;
  if (parsed.choices === undefined || !Array.isArray(parsed.choices) || parsed.choices.length === 0) {
    return '';
  }
  const message: OpenAiTitleMessage | undefined = parsed.choices[0].message;
  if (message === undefined || typeof message.content !== 'string') {
    return '';
  }
  return message.content;
}

// 各协议非流式用量提取（2026-09-10 费用估计；与正文提取同层同风格）；结构不符/字段缺失
// 回全零（调用方守卫不落库）；anthropic 走全量加法口径（见上方接口注释）。
// ★ 2026-09-15 附件 OCR 二期起导出 = OcrVisionApi 视觉引擎同款提取复用（零改动导出）
export function extractTitleUsage(protocol: string, endpoint: string, body: string): TitleUsageFrame {
  const zero: TitleUsageFrame = { promptTokens: 0, completionTokens: 0, cachedTokens: 0 };
  if (protocol === PROTOCOL_ANTHROPIC) {
    const parsed: AnthropicTitleResponse = JSON.parse(body) as AnthropicTitleResponse;
    const u: AnthropicTitleUsage | undefined = parsed.usage;
    if (u === undefined) {
      return zero;
    }
    const read: number = typeof u.cache_read_input_tokens === 'number' ?
      u.cache_read_input_tokens : 0;
    const creation: number = typeof u.cache_creation_input_tokens === 'number' ?
      u.cache_creation_input_tokens : 0;
    const input: number = typeof u.input_tokens === 'number' ? u.input_tokens : 0;
    return {
      promptTokens: input + read + creation,
      completionTokens: typeof u.output_tokens === 'number' ? u.output_tokens : 0,
      cachedTokens: read
    };
  }
  if (protocol === PROTOCOL_GEMINI) {
    const parsed: GeminiTitleResponse = JSON.parse(body) as GeminiTitleResponse;
    const u: GeminiTitleUsageMetadata | undefined = parsed.usageMetadata;
    if (u === undefined) {
      return zero;
    }
    return {
      promptTokens: typeof u.promptTokenCount === 'number' ? u.promptTokenCount : 0,
      completionTokens: typeof u.candidatesTokenCount === 'number' ? u.candidatesTokenCount : 0,
      cachedTokens: typeof u.cachedContentTokenCount === 'number' ? u.cachedContentTokenCount : 0
    };
  }
  if (endpoint === ENDPOINT_RESPONSES) {
    const parsed: ResponsesTitleResponse = JSON.parse(body) as ResponsesTitleResponse;
    const u: ResponsesTitleUsage | undefined = parsed.usage;
    if (u === undefined) {
      return zero;
    }
    const details: ResponsesTitleUsageDetails | undefined = u.input_tokens_details;
    return {
      promptTokens: typeof u.input_tokens === 'number' ? u.input_tokens : 0,
      completionTokens: typeof u.output_tokens === 'number' ? u.output_tokens : 0,
      cachedTokens: details !== undefined && typeof details.cached_tokens === 'number' ?
        details.cached_tokens : 0
    };
  }
  const parsed: OpenAiTitleResponse = JSON.parse(body) as OpenAiTitleResponse;
  const u: OpenAiTitleUsage | undefined = parsed.usage;
  if (u === undefined) {
    return zero;
  }
  const details: OpenAiTitleUsageDetails | undefined = u.prompt_tokens_details;
  return {
    promptTokens: typeof u.prompt_tokens === 'number' ? u.prompt_tokens : 0,
    completionTokens: typeof u.completion_tokens === 'number' ? u.completion_tokens : 0,
    cachedTokens: details !== undefined && typeof details.cached_tokens === 'number' ?
      details.cached_tokens : 0
  };
}

// 各协议非流式截断判据（2026-09-23 输出上限与超时治理笔）：输出被 max_tokens 类上限掐断
// 时四协议各自的非流式标记——openai chat choices[0].finish_reason 'length' / anthropic
// stop_reason 'max_tokens' / gemini candidates[0].finishReason 'MAX_TOKENS' / responses
// status 'incomplete'（思考 token 计入输出上限，打满即正文空/半截）。★ 宽容式：结构不符/
// 字段缺失/JSON 解析失败一律 false 不抛错——它服务于错误归因，不能自己成为新错误源。
// ★ 导出 = 断言直跑消费（组 174 真值表）+ OcrVisionApi 同构复用预留
export function extractTitleTruncated(protocol: string, endpoint: string, body: string): boolean {
  try {
    if (protocol === PROTOCOL_ANTHROPIC) {
      const parsed: AnthropicTitleResponse = JSON.parse(body) as AnthropicTitleResponse;
      return parsed.stop_reason === 'max_tokens';
    }
    if (protocol === PROTOCOL_GEMINI) {
      const parsed: GeminiTitleResponse = JSON.parse(body) as GeminiTitleResponse;
      return parsed.candidates !== undefined && parsed.candidates.length > 0 &&
        parsed.candidates[0].finishReason === 'MAX_TOKENS';
    }
    if (endpoint === ENDPOINT_RESPONSES) {
      const parsed: ResponsesTitleResponse = JSON.parse(body) as ResponsesTitleResponse;
      return parsed.status === 'incomplete';
    }
    const parsed: OpenAiTitleResponse = JSON.parse(body) as OpenAiTitleResponse;
    return parsed.choices !== undefined && parsed.choices.length > 0 &&
      parsed.choices[0].finish_reason === 'length';
  } catch (e) {
    return false;
  }
}

// 非流式端点与认证头（四协议方言，2026-09-15 附件 OCR 二期自 requestTitleText 抽出共享
// ——OcrVisionApi 同一口径消费；本件与该件共用单一来源，改方言只动这里）
export interface NonStreamEndpoint {
  url: string;
  header: Record<string, string>;
}

export function resolveNonStreamEndpoint(baseUrl: string, model: string, protocol: string,
  endpoint: string, apiKey: string): NonStreamEndpoint {
  const base: string = baseUrl.trim().replace(/\/+$/, '');
  let url: string = base + '/chat/completions';
  let header: Record<string, string> = {
    'Authorization': 'Bearer ' + apiKey,
    'Content-Type': 'application/json',
    'Accept': 'application/json'
  };
  if (protocol === PROTOCOL_ANTHROPIC) {
    url = base + '/v1/messages';
    header = {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };
  } else if (protocol === PROTOCOL_GEMINI) {
    // model 名进路径段（官方 models/{model}:generateContent 形态）——encodeURIComponent
    // 防特殊字符破路径；':' 是分隔符留在 encode 外；无 alt=sse 即非流式
    url = base + '/v1beta/models/' + encodeURIComponent(model) + ':generateContent';
    header = {
      'x-goog-api-key': apiKey,
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };
  } else if (endpoint === ENDPOINT_RESPONSES) {
    url = base + '/responses';
  }
  return { url: url, header: header };
}

// 发起小任务请求（非流式一次响应）。maxOutput = 输出上限（省略 = 标题链 TITLE_MAX_OUTPUT；
// 0 = 不发 max_tokens 字段 = 模型按自身上限输出——标题/记忆/推荐/主动消息四链现行同口径，
// 见文件头参数注）；readTimeoutMs = 读超时（省略 = READ_TIMEOUT_MS 30s；2026-09-23 上下文
// 压缩笔加——压缩请求传长超时照 OcrVisionApi 先例，其余六条辅助链零回归；同日输出上限
// 治理笔放宽为 5 分钟档，值见 CompressGen.COMPRESS_READ_MS）；onRequest = 请求句柄回传
// （2026-09-23 修复笔加，可选——上下文压缩链借它登记句柄，用户中断时 destroy 真停；其余
// 六链不传，行为零变化）。★ 2026-09-23 自检轮加**第二形参 onCanceled**：调用方 destroy 时
// 调它一次，本条请求日志即落取消终态（-3）而不会被后续结算记成「网络失败」，悬着的 promise
// 同时落定；不销毁句柄的调用方无感（形参可忽略）；taskLabel = 失败文案用途前缀（2026-09-23 输出上限治理笔加，
// 省略 = '标题'——六条辅助链不传即逐字零回归；压缩链传 '压缩'，治「压缩失败却报标题
// 响应缺少正文」的错名）。★ 2026-09-23 请求日志笔起它**兼作请求日志的来源标签**（ReqLog
// 条目 source），故六条辅助链自本笔起也都显式传中文短名（记忆 / 记忆优化 / 记忆导入 /
// 推荐问题 / 主动消息）——错名同批治掉。失败不抛错——ok=false + 中文 errorMessage + status
// 事实返回（P0-1 由调用方留痕呈报，本层不 toast）
export function requestTitleText(baseUrl: string, model: string, protocol: string,
  endpoint: string, apiKey: string, prompt: string,
  maxOutput: number = TITLE_MAX_OUTPUT,
  readTimeoutMs: number = READ_TIMEOUT_MS,
  onRequest?: (req: http.HttpRequest, onCanceled: () => void) => void,
  taskLabel: string = '标题'): Promise<TitleRequestResult> {
  return new Promise<TitleRequestResult>((resolve) => {
    const auth: NonStreamEndpoint =
      resolveNonStreamEndpoint(baseUrl, model, protocol, endpoint, apiKey);
    const request: http.HttpRequest = http.createHttp();
    const bodyText: string = buildTitleBody(protocol, endpoint, model, prompt, maxOutput);
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: auth.header,
      extraData: bodyText,
      usingCache: false,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: CONNECT_TIMEOUT_MS,
      readTimeout: readTimeoutMs
    };
    // 请求日志埋点（ReqLog.ets，2026-09-23 请求日志笔）：**一处覆盖七条小任务链**（标题 /
    // 记忆 / 记忆优化 / 记忆导入 / 压缩 / 推荐问题 / 主动消息）——来源标签复用 taskLabel 形参
    // （各链显式传中文短名，顺带治好「记忆失败却报标题」的错名）。五条 resolve 路径共用
    // finish 收尾：逐条手写必漏，漏一处该条日志就永远停在「进行中」
    const startedAt: number = Date.now();
    const logId: string = reqLogBegin({
      source: taskLabel, model: model, method: 'POST', url: auth.url, headers: auth.header,
      body: bodyText
    });
    // 取消收尾（2026-09-23 自检轮加，独立复核 F1）：调用方 destroy 句柄后旧 promise 何时
    // settle 不由本层掌控（CompressGen 头注释），若走 reject 分支会把用户主动中断记成
    // -1「网络失败」（与聊天链 -3 分家同族，见 common/ReqLog.ets 头）。故由调用方在 destroy
    // 时显式调本回调一次 ⇒ 日志落取消终态、悬着的 promise 也一并落定；**已取消后到达的结算
    // 一律丢弃**（否则 -3 会被覆写回 -1，日志又指错方向）
    let canceled: boolean = false;
    const onCanceled = (): void => {
      if (canceled) {
        return;
      }
      canceled = true;
      reqLogEnd(logId, REQ_LOG_STATUS_CANCELED, Date.now() - startedAt, taskLabel + '已中断', '');
      resolve({ ok: false, text: '', errorMessage: taskLabel + '已中断',
        status: REQ_LOG_STATUS_CANCELED, truncated: false,
        promptTokens: 0, completionTokens: 0, cachedTokens: 0 });
    };
    if (onRequest !== undefined) {
      onRequest(request, onCanceled);
    }
    const finish = (result: TitleRequestResult, responseTail: string): void => {
      if (canceled) {
        return; // 取消后到达的结算丢弃（见上）
      }
      reqLogEnd(logId, result.status, Date.now() - startedAt,
        result.ok ? '' : result.errorMessage, responseTail);
      resolve(result);
    };
    request.request(auth.url, options)
      .then((resp: http.HttpResponse): void => {
        // 响应头回填（2026-09-23 扩充笔）：非流式链已拿到 HttpResponse，白名单头直接取用
        //（「200 却返回网页」这条归因就靠这里的 content-type）。★ 须在 finish 之前——凭据
        // 明细在 reqLogEnd 时即删，顺序颠倒会少一层值级替换（白名单外的头本就不记）
        reqLogSetResponseHeaders(logId, resp.header);
        if (resp.responseCode !== 200) {
          const body: string = typeof resp.result === 'string' ? resp.result : '';
          const detail: string = extractApiError(body);
          const suffix: string = detail !== '' ? '：' + detail :
            (body !== '' ? '：' + body.slice(0, 200) : '，响应无内容');
          finish({ ok: false, text: '',
            errorMessage: taskLabel + '请求失败(HTTP ' + resp.responseCode + ')' + suffix,
            status: resp.responseCode, truncated: false,
            promptTokens: 0, completionTokens: 0, cachedTokens: 0 }, body);
          return;
        }
        const body: string = typeof resp.result === 'string' ? resp.result : '';
        let text: string = '';
        let usage: TitleUsageFrame = { promptTokens: 0, completionTokens: 0, cachedTokens: 0 };
        let truncated: boolean = false;
        try {
          text = extractTitleText(protocol, endpoint, body);
          usage = extractTitleUsage(protocol, endpoint, body);
          truncated = extractTitleTruncated(protocol, endpoint, body);
        } catch (e) {
          finish({ ok: false, text: '', errorMessage: taskLabel + '响应不是有效 JSON', status: 200,
            truncated: false, promptTokens: 0, completionTokens: 0, cachedTokens: 0 }, body);
          return;
        }
        if (text === '') {
          // 缺正文但 token 可能已消耗——用量如实带回（200 形态）；响应体同带进请求日志
          //（协议层异常时它往往就是「对方到底回了什么」的唯一证据）
          finish({ ok: false, text: '', errorMessage: taskLabel + '响应缺少正文', status: 200,
            truncated: truncated,
            promptTokens: usage.promptTokens, completionTokens: usage.completionTokens,
            cachedTokens: usage.cachedTokens }, body);
          return;
        }
        // 成功不记响应正文（本功能边界：只记错误侧响应体，见 ReqLog.ets 头注释）
        finish({ ok: true, text: text, errorMessage: '', status: 200,
          truncated: truncated,
          promptTokens: usage.promptTokens, completionTokens: usage.completionTokens,
          cachedTokens: usage.cachedTokens }, '');
      })
      .catch((e: Object): void => {
        finish({ ok: false, text: '', errorMessage: '网络错误：' + describeNetError(e),
          status: -1, truncated: false, promptTokens: 0, completionTokens: 0, cachedTokens: 0 }, '');
      })
      .finally((): void => {
        // destroy 包 try：句柄可能已由调用方中断销毁（压缩链 cancelCompressDraft）——二次
        // destroy 异常不得抛进 finally；幂等释放是 best-effort（ChatStreamBase.release 同款）
        try {
          request.destroy();
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'destroy 异常（忽略）：%{public}s', (e as Error).message);
        }
      });
  });
}
