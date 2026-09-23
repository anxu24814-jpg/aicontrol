// 模型目录 API（2026-08-30 服务商管理域新增；同日三协议扩展）：按协议拉取服务商模型 id
// 清单——openai GET {base}/models（Bearer）/ anthropic GET {base}/v1/models（x-api-key +
// anthropic-version）/ gemini GET {base}/v1beta/models（x-goog-api-key）；key 取池首个启用
//（调用方传入）。非流式单请求（requestInStream 族是聊天流式专用，此处用 http.request
// 一次性响应）；模型清单拉回后由调用方合并进 provider_models 表（不直接落库——本层
// 只取数）。响应形态：openai/anthropic 同为 { data: [{ id }] }；gemini 为
// { models: [{ name: "models/<id>" }] }（剥前缀取 id）。
// ★ anthro 连接测试探针 probeAnthropicMessages（2026-09-05）：第三方 anthro 兼容层
//（DeepSeek/Kimi 的 /anthropic 端点）普遍只实现 POST /v1/messages、不实现 GET /v1/models
//——测试连接走列模型必 404；改发 max_tokens=1 最小 messages 请求（与对话链路同端点，
// 测「能不能对话」，Cherry Studio「检查」键同款做法），消耗几个 token 可忽略。
// 红线同 ChatStreamBase：三错误路径全中文提示（HTTP 非 200 解析 error.message / 网络
// 失败 / JSON 结构不符）；坑 59 规避（显式接口、错误重包 Error、禁 in 运算）；资源
// destroy 单点成对（request 用完即毁，无事件绑定）。
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PROTOCOL_ANTHROPIC, PROTOCOL_GEMINI } from './AiTypes';
import { reqLogBegin, reqLogEnd, reqLogSetResponseHeaders } from '../ReqLog';

const CONNECT_TIMEOUT_MS: number = 10000;
const READ_TIMEOUT_MS: number = 15000;

// /models 响应体（openai/anthropic 同形态；只声明消费的字段——ArkTS 对象字面量须挂
// 显式接口，坑 59 ①）
interface ModelEntry {
  id: string;
}

interface ModelListResponse {
  data: ModelEntry[];
}

// gemini /v1beta/models 响应体（name = "models/<id>" 全名形态）
interface GeminiModelEntry {
  name: string;
}

interface GeminiModelListResponse {
  models: GeminiModelEntry[];
}

// anthro 探针请求体（max_tokens=1 最小消耗；对象字面量挂显式接口——坑59 ①）
interface AnthropicProbeMessage {
  role: string;
  content: string;
}

interface AnthropicProbeBody {
  model: string;
  max_tokens: number;
  messages: AnthropicProbeMessage[];
}

// anthro 探针响应 usage（2026-09-10 费用估计起消费——全量加法口径与 SseParser v26 /
// TitleApi 一致：prompt = input+read+creation、cached 只记 read；缺失回 0）
interface AnthropicProbeUsage {
  input_tokens?: number;
  output_tokens?: number;
  cache_read_input_tokens?: number;
  cache_creation_input_tokens?: number;
}

interface AnthropicProbeResponse {
  usage?: AnthropicProbeUsage;
}

// anthro 探针结果（2026-09-10 费用估计：HTTP 200 即连通，usage 三值供调用方落用途账本
// ——探针 max_tokens=1 消耗个位数 token，全零守卫在 logTaskUsage）
export interface AnthropicProbeResult {
  promptTokens: number;
  completionTokens: number;
  cachedTokens: number;
}

// 网络层错误描述（与 ChatStreamBase.describeNetError 同款口径，此处独立成份——两文件
// 零 import 依赖，避免为一行复用引互引；原指针「OpenAiCompatApi」为该文件 2026-09-01
// 并回 ChatStreamFactory/ChatStreamBase 前的旧名，2026-09-13 全码优化笔1 核正）
function describeNetError(e: Object): string {
  const biz = e as BusinessError;
  if (typeof biz.code === 'number') {
    const msg: string = typeof biz.message === 'string' && biz.message !== '' ? '，' + biz.message : '';
    return '无法连接服务器(code ' + biz.code + ')' + msg;
  }
  return (e as Error).message !== undefined ? (e as Error).message : '未知错误';
}

// 非 200 响应取 error.message（OpenAI 兼容方言错误体；缺失回 '' 由调用方拼提示）
function extractApiError(body: string): string {
  try {
    const parsed: Record<string, Object> = JSON.parse(body) as Record<string, Object>;
    const err: Object | undefined = parsed['error'];
    if (err !== undefined) {
      const errMap: Record<string, Object> = err as Record<string, Object>;
      const msg: Object | undefined = errMap['message'];
      if (typeof msg === 'string' && msg !== '') {
        return msg;
      }
    }
  } catch (e) {
    // 非 JSON 错误体：原文截尾提示
  }
  return '';
}

// 拉取模型 id 清单（去重 + 字典序升序——展示序稳定）；失败 reject Error（中文提示，
// 调用方 toast 呈现，P0-1 不静默）。端点与认证头随协议（AiTypes 常量值；未知协议按
// openai 兜底——工厂同款保守路径）
export function fetchModelIds(baseUrl: string, apiKey: string, protocol: string): Promise<string[]> {
  return new Promise<string[]>((resolve, reject) => {
    const base: string = baseUrl.trim().replace(/\/+$/, '');
    let url: string = base + '/models';
    let header: Record<string, string> = {
      'Authorization': 'Bearer ' + apiKey,
      'Accept': 'application/json'
    };
    if (protocol === PROTOCOL_ANTHROPIC) {
      url = base + '/v1/models';
      header = {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'Accept': 'application/json'
      };
    } else if (protocol === PROTOCOL_GEMINI) {
      url = base + '/v1beta/models';
      header = {
        'x-goog-api-key': apiKey,
        'Accept': 'application/json'
      };
    }
    const request: http.HttpRequest = http.createHttp();
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: header,
      usingCache: false,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: CONNECT_TIMEOUT_MS,
      readTimeout: READ_TIMEOUT_MS
    };
    // 请求日志埋点（ReqLog.ets，2026-09-23 请求日志笔）：本链是添加服务商时最常见的失败点，
    // 记下来才能分辨「网不通 / key 不对 / 端点不是这套方言」。GET 无请求体（body 传空串）
    const startedAt: number = Date.now();
    const logId: string = reqLogBegin({
      // 拉清单不针对某个模型，故模型名传空串（列表行显示「—」）
      source: '模型清单', model: '', method: 'GET', url: url, headers: header, body: ''
    });
    let httpStatus: number = -1;
    // 失败收尾单点（五条 reject 路径共用——逐条手写必漏，漏一处该条日志就永远停在「进行中」）
    const failLog = (message: string, responseTail: string): void => {
      reqLogEnd(logId, httpStatus, Date.now() - startedAt, message, responseTail);
      reject(new Error(message));
    };
    request.request(url, options)
      .then((resp: http.HttpResponse): void => {
        httpStatus = resp.responseCode;
        // 响应头回填（2026-09-23 扩充笔）：须在 failLog 之前——凭据明细在 reqLogEnd 时即删
        reqLogSetResponseHeaders(logId, resp.header);
        if (resp.responseCode !== 200) {
          const body: string = typeof resp.result === 'string' ? resp.result : '';
          const detail: string = extractApiError(body);
          const suffix: string = detail !== '' ? '：' + detail :
            (body !== '' ? '：' + body.slice(0, 200) : '，响应无内容');
          failLog('获取模型失败(HTTP ' + resp.responseCode + ')' + suffix, body);
          return;
        }
        const text: string = typeof resp.result === 'string' ? resp.result : '';
        let ids: string[] = [];
        if (protocol === PROTOCOL_GEMINI) {
          try {
            const parsed: GeminiModelListResponse = JSON.parse(text) as GeminiModelListResponse;
            if (parsed.models === undefined || !Array.isArray(parsed.models)) {
              failLog('获取模型失败：响应缺少 models 数组（非 Gemini /v1beta/models 端点）', text);
              return;
            }
            for (const entry of parsed.models) {
              // name = "models/<id>" 全名形态，剥前缀入库（与手填 modelId 同域）。★ 先
              // typeof 守卫再取值（2026-09-14 全面自检第3轮笔1 修复，87 组断言）：原
              // startsWith 在守卫前求值，条目缺 name 字段时抛 TypeError 被 catch 误报
              // 「响应不是有效 JSON」——openai 分支先守卫同序，此处对齐
              if (typeof entry.name !== 'string' || entry.name === '') {
                continue;
              }
              const id: string = entry.name.startsWith('models/') ?
                entry.name.substring('models/'.length) : entry.name;
              if (!ids.includes(id)) {
                ids.push(id);
              }
            }
          } catch (e) {
            failLog('获取模型失败：响应不是有效 JSON', text);
            return;
          }
        } else {
          try {
            const parsed: ModelListResponse = JSON.parse(text) as ModelListResponse;
            if (parsed.data === undefined || !Array.isArray(parsed.data)) {
              failLog('获取模型失败：响应缺少 data 数组（非 OpenAI 兼容 /models 端点）', text);
              return;
            }
            for (const entry of parsed.data) {
              if (typeof entry.id === 'string' && entry.id !== '' && !ids.includes(entry.id)) {
                ids.push(entry.id);
              }
            }
          } catch (e) {
            // ★ 2026-09-23 自检轮修复：此处原为裸 reject——本链六条 reject 出口里唯一没过
            // failLog 单点的（上面 Gemini 分支的同名 catch 已收口），故「200 + 非 JSON」这条
            // 出口的日志条目会永远停在「进行中」。文案逐字不变，只补收尾
            failLog('获取模型失败：响应不是有效 JSON', text);
            return;
          }
        }
        ids.sort((a: string, b: string): number => a.localeCompare(b));
        reqLogEnd(logId, httpStatus, Date.now() - startedAt, '', '');
        resolve(ids);
      })
      .catch((e: Object): void => {
        failLog('获取模型失败：' + describeNetError(e), '');
      })
      .finally((): void => {
        // destroy 包 try（2026-09-23 自检轮补，同 TitleApi / KeyConnectTester 两处先例）：
        // 裸 destroy 抛错会从 finally 穿出，把**已成功 resolve 的结果**改写成 rejected——
        // 调用方于是把一次成功的请求显示成失败。本件无日志设施，故静默忽略（异常已被拦在本层，
        // 不影响已定的结论，不属 P0-1「静默失败」范畴）
        try {
          request.destroy();
        } catch (e) {
        }
      });
  });
}

// Anthropic 连接测试探针（2026-09-05，背景见文件头★）：POST {base}/v1/messages 非流式、
// max_tokens=1 最小消耗——第三方 anthro 兼容层普遍只实现本端点。成功 resolve（HTTP 200
// 即连通+鉴权通过；响应体提取 usage 三值供费用账本——结构不符回全零，TitleApi 同款
// 兜底）；失败 reject Error 中文提示（三错误路径与 fetchModelIds 同口径：HTTP 非 200
// 解析 error.message / 网络失败 describeNetError / request 用完 destroy 成对释放）
export function probeAnthropicMessages(baseUrl: string, apiKey: string,
  modelId: string): Promise<AnthropicProbeResult> {
  return new Promise<AnthropicProbeResult>((resolve, reject) => {
    const base: string = baseUrl.trim().replace(/\/+$/, '');
    const body: AnthropicProbeBody = {
      model: modelId,
      max_tokens: 1,
      messages: [{ role: 'user', content: 'hi' }]
    };
    const request: http.HttpRequest = http.createHttp();
    const url: string = base + '/v1/messages';
    // 请求头提为局部量：请求日志要与发送侧同一份（内联字面量在 options 里取不出来）
    const header: Record<string, string> = {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };
    const bodyText: string = JSON.stringify(body);
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: header,
      extraData: bodyText,
      usingCache: false,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: CONNECT_TIMEOUT_MS,
      readTimeout: READ_TIMEOUT_MS
    };
    // 请求日志埋点（ReqLog.ets，2026-09-23 请求日志笔；来源标签与 fetchModelIds 同域）
    const startedAt: number = Date.now();
    const logId: string = reqLogBegin({
      source: '模型清单', model: modelId, method: 'POST', url: url, headers: header,
      body: bodyText
    });
    let httpStatus: number = -1;
    request.request(url, options)
      .then((resp: http.HttpResponse): void => {
        httpStatus = resp.responseCode;
        // 响应头回填（2026-09-23 扩充笔）：须在两处 reqLogEnd 之前（凭据明细在 end 时即删）
        reqLogSetResponseHeaders(logId, resp.header);
        if (resp.responseCode !== 200) {
          const respBody: string = typeof resp.result === 'string' ? resp.result : '';
          const detail: string = extractApiError(respBody);
          const suffix: string = detail !== '' ? '：' + detail :
            (respBody !== '' ? '：' + respBody.slice(0, 200) : '，响应无内容');
          reqLogEnd(logId, resp.responseCode, Date.now() - startedAt,
            '测试连接失败(HTTP ' + resp.responseCode + ')' + suffix, respBody);
          reject(new Error('测试连接失败(HTTP ' + resp.responseCode + ')' + suffix));
          return;
        }
        // 用量提取（探针 max_tokens=1 消耗如实入账；body 坏 JSON 回全零不失败——连通
        // 判定只看 HTTP 200，用量是附带面）
        let usage: AnthropicProbeResult = { promptTokens: 0, completionTokens: 0, cachedTokens: 0 };
        try {
          const parsed: AnthropicProbeResponse =
            JSON.parse(typeof resp.result === 'string' ? resp.result : '') as AnthropicProbeResponse;
          const u: AnthropicProbeUsage | undefined = parsed.usage;
          if (u !== undefined) {
            const read: number = typeof u.cache_read_input_tokens === 'number' ?
              u.cache_read_input_tokens : 0;
            const creation: number = typeof u.cache_creation_input_tokens === 'number' ?
              u.cache_creation_input_tokens : 0;
            const input: number = typeof u.input_tokens === 'number' ? u.input_tokens : 0;
            usage = {
              promptTokens: input + read + creation,
              completionTokens: typeof u.output_tokens === 'number' ? u.output_tokens : 0,
              cachedTokens: read
            };
          }
        } catch (e) {
          // 坏 JSON 不影响连通判定（与 fetchModelIds 的严格 JSON 校验语义不同——本探针
          // 的成功判据只是 200）
        }
        reqLogEnd(logId, httpStatus, Date.now() - startedAt, '', '');
        resolve(usage);
      })
      .catch((e: Object): void => {
        const message: string = '测试连接失败：' + describeNetError(e);
        reqLogEnd(logId, httpStatus, Date.now() - startedAt, message, '');
        reject(new Error(message));
      })
      .finally((): void => {
        // destroy 包 try（2026-09-23 自检轮补，同 TitleApi / KeyConnectTester 两处先例）：
        // 裸 destroy 抛错会从 finally 穿出，把**已成功 resolve 的结果**改写成 rejected——
        // 调用方于是把一次成功的请求显示成失败。本件无日志设施，故静默忽略（异常已被拦在本层，
        // 不影响已定的结论，不属 P0-1「静默失败」范畴）
        try {
          request.destroy();
        } catch (e) {
        }
      });
  });
}
