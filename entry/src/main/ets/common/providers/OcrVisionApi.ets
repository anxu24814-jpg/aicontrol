// 视觉引擎非流式通道（2026-09-15 附件 OCR 二期，任务书-附件OCR链路 §3.3）：用用户已配置
// 的一个模型把一批图读成文字——照 TitleApi 非流式小请求通道形制（一次 http.request 拿全
// 响应、复用四协议 compose 纯函数 + toNonStream 传输层后处理、三错误路径中文、request 用
// 完即毁无事件绑定）。端点/密钥解析复用 TitleGen.resolveTitleEndpoint（服务商启用 + 模型
// 为该服务商启用对话模型 + key 池非空——同标题链单级验证，禁走四级链）。
// · 请求体：单条 user 消息 = 生效识别提示词（默认内置，★ 2026-09-17 起用户可定制，见下方
//   提示词节）+ 本批图片（四协议图片部件现成，compose 零改动）；thinking='' / sampling=null
//   / tools=[] / anthropic 不传 cache。
// · 非流式改写（红线 7）：openai chat / responses / anthropic 传 toNonStream(body, true)
//   （剔 stream_options，残留被服务端 400 拒——2026-09-08 沙箱日志实锤）；gemini 传 false。
// · 分批（§7.3）：OCR_VISION_BATCH = 5 张/批逐批串行——单请求体量可控（页图单张裸
//   base64 ≈ 11.7 万字符，5 张 ≈ 58 万字符），批次间文本以 '\n\n' 拼接；批失败即整件
//   失败**不重试**（回退编排归 OcrEngine §3.4，本层只报事实不决策）。
// · 响应清洗：各协议非流式正文提取复用 TitleApi.extractTitleText / extractTitleUsage
//   （导出共享，零改动）；trim 后等于 NO_TEXT 哨兵 → 视作空串（空白图）。
// · 记账（§7.9）：成功路径 logTaskUsage('ocr', '', ...)——conversationId 空串（OCR 与
//   具体会话无绑定，照 KeyConnectTester 探针先例；7 参无 durationMs，照标题链调用形态）。
// · 超时（书内口径 4）：15000 连接 + 60000 读取——比标题链 30s 放宽（多图请求体大、视觉
//   推理慢）；常量单源在本件。
import { http } from '@kit.NetworkKit';
import { AiChatMessage, AiImagePart, ENDPOINT_RESPONSES, PROTOCOL_ANTHROPIC, PROTOCOL_GEMINI } from './AiTypes';
import { composeAnthropicBody, composeGeminiBody, composeOpenAiBody,
  composeOpenAiResponsesBody } from './RequestCompose';
import { extractApiError } from './SseParser';
import { extractTitleText, extractTitleUsage, NonStreamEndpoint, resolveNonStreamEndpoint,
  TitleUsageFrame, toNonStream } from './TitleApi';
import { resolveTitleEndpoint } from '../TitleGen';
import { loadPoolKey } from '../store/KeyStore';
import { logTaskUsage } from '../store/UsageStatsDb';
import { reqLogBegin, reqLogEnd, reqLogSetResponseHeaders } from '../ReqLog';
import { BusinessError } from '@kit.BasicServicesKit';

// 分批上限（§7.3，本件常量单源）
export const OCR_VISION_BATCH: number = 5;
const OCR_VISION_CONNECT_MS: number = 15000;
const OCR_VISION_READ_MS: number = 60000;
// 提示词与哨兵（§7.4；★ 2026-09-17 决明指令开放自定义，形制照 TitleGen 三槽先例）：
// OCR_PROMPT_TEMPLATE = 内置默认（唯一真源）；OCR_PROMPT_KEY（'ocrPrompt' AppStorage 持久
// 键，EntryAbility persistProp 注册）存用户定制覆盖——'' = 未定制 = 生效内置（恢复默认 =
// 清键回退，内置模板后续升级自动跟随）；生效模板单源 = resolveOcrPromptTemplate()，识别链
// 与功能模型页编辑面板共用，无缓存（保存后下次识别立即生效）。
// · 本槽无占位符——提示词不含变量插入点（图片以附件部件随请求发送，不是文本插值），
//   编辑保存不校验占位符（与标题/记忆三槽不同）。
// · 哨兵 NO_TEXT 由内置模板约定（模型无文字可提时回）。用户定制若不再要求输出它，空白图
//   会返回描述性文字被当识别结果——定制即自担；清洗链只认字面哨兵，判定不因定制改变。
export const OCR_PROMPT_TEMPLATE: string =
  '提取图片中的全部文字，保持原有顺序与换行，不要翻译、不要总结、不要添加说明。若图中没有文字，只输出 NO_TEXT。';
// 识别提示词定制键（AppStorage 持久化；'' = 未定制 = 生效内置模板——清删式语义）
export const OCR_PROMPT_KEY: string = 'ocrPrompt';
const NO_TEXT_SENTINEL: string = 'NO_TEXT';

// 生效模板纯选择（custom 非空取 custom，空回退内置——AppStorage 读取在 IO 面，本纯函数
// 可节点直跑断言：内核回退与定制两路）
export function pickOcrPrompt(custom: string): string {
  return custom !== '' ? custom : OCR_PROMPT_TEMPLATE;
}

// 生效模板单源（识别链 + 功能模型页编辑面板共用）：定制非空取定制，空回退内置
export function resolveOcrPromptTemplate(): string {
  return pickOcrPrompt(AppStorage.get<string>(OCR_PROMPT_KEY) ?? '');
}

// 请求结果（TitleRequestResult 同构；status 0 = 配置类失败〔端点解析/密钥缺失〕无 HTTP 码）
export interface OcrVisionResult {
  ok: boolean;
  text: string; // ok=true：批次序拼接全文（哨兵清洗后；全空批 = 空串 = 空白图）
  errorMessage: string; // ok=false：中文错误描述（含 HTTP 状态与服务商 error.message）
  status: number;
  promptTokens: number;
  completionTokens: number;
  cachedTokens: number;
}

// 网络层错误描述（TitleApi 同款口径，独立成份避免为一行复用引互引）
function describeNetError(e: Object): string {
  const biz = e as BusinessError;
  if (typeof biz.code === 'number') {
    const msg: string = typeof biz.message === 'string' && biz.message !== '' ? '，' + biz.message : '';
    return '无法连接服务器(code ' + biz.code + ')' + msg;
  }
  return (e as Error).message !== undefined ? (e as Error).message : '未知错误';
}

// 单批请求体（协议方言分流；消息恒单条 user = 生效提示词全文 + 本批图片。★ 每批现读
// resolveOcrPromptTemplate()——定制后无需重进页面即生效，与三槽口径一致）
function buildOcrBody(protocol: string, endpoint: string, model: string,
  images: AiImagePart[]): string {
  const messages: AiChatMessage[] =
    [{ role: 'user', content: resolveOcrPromptTemplate(), images: images }];
  if (protocol === PROTOCOL_ANTHROPIC) {
    return toNonStream(composeAnthropicBody(model, messages, '', false, null), true);
  }
  if (protocol === PROTOCOL_GEMINI) {
    return toNonStream(composeGeminiBody(messages, '', null), false);
  }
  if (endpoint === ENDPOINT_RESPONSES) {
    return toNonStream(composeOpenAiResponsesBody(model, messages, '', null), true);
  }
  return toNonStream(composeOpenAiBody(model, messages, '', false, null), true);
}

// 单批请求（非流式一次响应；失败不抛错——ok=false + 中文 errorMessage + status 事实返回）
// ★ 请求日志（2026-09-24 扩面笔）：本批**五条**返回路径（非 200 / JSON 解析失败 / 缺正文 /
// 成功 / 网络异常）逐条手写收尾必漏（ModelListApi F1 同族：六条 reject 出口漏一条 ⇒ 该条
// 永远停在「进行中」），故收敛到 settle 一处。多图分批时**每批一条**日志（每批是独立请求，
// 排障要看的是「第几批挂了」）。model = 视觉引擎模型名（本链针对具体模型，同标题链口径）
function requestOcrBatch(auth: NonStreamEndpoint, model: string, body: string, protocol: string,
  endpoint: string): Promise<OcrVisionResult> {
  return new Promise<OcrVisionResult>((resolve) => {
    const request: http.HttpRequest = http.createHttp();
    const startedAt: number = Date.now();
    const logId: string = reqLogBegin({
      source: '文字识别', model: model, method: 'POST', url: auth.url, headers: auth.header,
      body: body
    });
    // 收尾单点（结果与日志同出）：header 非 null 时先回填响应头（须在 reqLogEnd 之前——
    // 凭据明细在 end 时即删）；tail = 错误侧响应体（成功不记正文，见 ReqLog.ets 头注释边界）
    const settle = (result: OcrVisionResult, header: Object | null, tail: string): void => {
      if (header !== null) {
        reqLogSetResponseHeaders(logId, header);
      }
      reqLogEnd(logId, result.status, Date.now() - startedAt,
        result.ok ? '' : result.errorMessage, tail);
      resolve(result);
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: auth.header,
      extraData: body,
      usingCache: false,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: OCR_VISION_CONNECT_MS,
      readTimeout: OCR_VISION_READ_MS
    };
    request.request(auth.url, options)
      .then((resp: http.HttpResponse): void => {
        if (resp.responseCode !== 200) {
          const raw: string = typeof resp.result === 'string' ? resp.result : '';
          const detail: string = extractApiError(raw);
          const suffix: string = detail !== '' ? '：' + detail :
            (raw !== '' ? '：' + raw.slice(0, 200) : '，响应无内容');
          settle({ ok: false, text: '',
            errorMessage: '识别请求失败(HTTP ' + resp.responseCode + ')' + suffix,
            status: resp.responseCode, promptTokens: 0, completionTokens: 0, cachedTokens: 0 },
            resp.header, raw);
          return;
        }
        const raw: string = typeof resp.result === 'string' ? resp.result : '';
        let text: string = '';
        let usage: TitleUsageFrame = { promptTokens: 0, completionTokens: 0, cachedTokens: 0 };
        try {
          text = extractTitleText(protocol, endpoint, raw);
          usage = extractTitleUsage(protocol, endpoint, raw);
        } catch (e) {
          settle({ ok: false, text: '', errorMessage: '识别响应不是有效 JSON', status: 200,
            promptTokens: 0, completionTokens: 0, cachedTokens: 0 }, resp.header, raw);
          return;
        }
        if (text === '') {
          // 缺正文但 token 可能已消耗——用量如实带回（200 形态，TitleApi 同口径）
          settle({ ok: false, text: '', errorMessage: '识别响应缺少正文', status: 200,
            promptTokens: usage.promptTokens, completionTokens: usage.completionTokens,
            cachedTokens: usage.cachedTokens }, resp.header, raw);
          return;
        }
        settle({ ok: true, text: text, errorMessage: '', status: 200,
          promptTokens: usage.promptTokens, completionTokens: usage.completionTokens,
          cachedTokens: usage.cachedTokens }, resp.header, '');
      })
      .catch((e: Object): void => {
        settle({ ok: false, text: '', errorMessage: '网络错误：' + describeNetError(e),
          status: -1, promptTokens: 0, completionTokens: 0, cachedTokens: 0 }, null, '');
      })
      .finally((): void => {
        // destroy 包 try（同 ModelListApi / TitleApi / KeyConnectTester 先例）：裸 destroy 抛错
        // 会从 finally 穿出成未捕获的 promise 拒绝——本层无日志设施，故静默忽略
        try {
          request.destroy();
        } catch (e) {
        }
      });
  });
}

// 视觉引擎整件识别：端点/密钥解析 → 分批串行请求 → 哨兵清洗 → 批次拼接 + 用量求和 →
// 成功路径记账。配置类失败（端点 null / 密钥缺失）status=0 不发任何请求
export async function requestOcrText(providerId: string, modelId: string,
  images: AiImagePart[]): Promise<OcrVisionResult> {
  if (images.length === 0) {
    return { ok: false, text: '', errorMessage: '无图可识别', status: 0,
      promptTokens: 0, completionTokens: 0, cachedTokens: 0 };
  }
  const resolved = await resolveTitleEndpoint(providerId, modelId);
  if (resolved === null) {
    return { ok: false, text: '',
      errorMessage: '视觉引擎模型不可用，请检查服务商与模型配置', status: 0,
      promptTokens: 0, completionTokens: 0, cachedTokens: 0 };
  }
  const apiKey: string = await loadPoolKey(providerId, resolved.keyIds[0]);
  if (apiKey === '') {
    return { ok: false, text: '', errorMessage: '视觉引擎密钥缺失', status: 0,
      promptTokens: 0, completionTokens: 0, cachedTokens: 0 };
  }
  const auth: NonStreamEndpoint = resolveNonStreamEndpoint(resolved.baseUrl, resolved.modelId,
    resolved.protocol, resolved.endpoint, apiKey);
  const parts: string[] = [];
  let promptTokens: number = 0;
  let completionTokens: number = 0;
  let cachedTokens: number = 0;
  for (let i = 0; i < images.length; i += OCR_VISION_BATCH) {
    const batch: AiImagePart[] = images.slice(i, i + OCR_VISION_BATCH);
    const result: OcrVisionResult = await requestOcrBatch(auth, resolved.modelId,
      buildOcrBody(resolved.protocol, resolved.endpoint, resolved.modelId, batch),
      resolved.protocol, resolved.endpoint);
    if (!result.ok) {
      // 批失败即整件失败，不重试（回退编排归 OcrEngine §3.4）
      return result;
    }
    promptTokens += result.promptTokens;
    completionTokens += result.completionTokens;
    cachedTokens += result.cachedTokens;
    // 哨兵清洗（§3.3.7）：trim 后恰等于 NO_TEXT = 空白图，视作空串
    const text: string = result.text.trim() === NO_TEXT_SENTINEL ? '' : result.text.trim();
    if (text !== '') {
      parts.push(text);
    }
  }
  // 用途记账（成功路径；conversationId 空串——OCR 与具体会话无绑定；全零不落 = 无 usage
  // 零污染守卫在 logTaskUsage 内）
  logTaskUsage('ocr', '', providerId, resolved.modelId,
    promptTokens, completionTokens, cachedTokens);
  return { ok: true, text: parts.join('\n\n'), errorMessage: '', status: 200,
    promptTokens: promptTokens, completionTokens: completionTokens, cachedTokens: cachedTokens };
}
