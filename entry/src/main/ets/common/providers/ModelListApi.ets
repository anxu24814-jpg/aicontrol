// 模型目录 API：按协议拉取服务商模型 id 清单（本层只取数，合并落库归调用方）——openai
// GET {base}/models（Bearer）/ anthropic GET {base}/v1/models（x-api-key + anthropic-
// version）/ gemini GET {base}/v1beta/models（x-goog-api-key）；非流式单请求（聊天流式
// 才用 requestInStream 族）。响应形态：openai/anthropic 为 { data: [{ id }] }；gemini 为
// { models: [{ name: "models/<id>" }] }（剥前缀取 id）。
// ★ 探针 probeAnthropicMessages：第三方 anthro 兼容层（DeepSeek/Kimi 的 /anthropic 端点）
// 普遍只实现 POST /v1/messages、不实现 GET /v1/models——测试连接走列模型必 404；改发
// max_tokens=1 最小 messages 请求（与对话链路同端点，测「能不能对话」）。
// 红线同 ChatStreamBase：三错误路径全中文提示（HTTP 非 200 解析 error.message / 网络失败 /
// JSON 结构不符）；坑 59 规避（显式接口、错误重包 Error、禁 in 运算）；request 用完即毁。
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PROTOCOL_ANTHROPIC, PROTOCOL_GEMINI } from './AiTypes';
import { applyDefaultUserAgent, applyEffectiveProxy } from './RequestIdentity';
import { reqLogBegin, reqLogEnd, reqLogSetResponseHeaders } from '../ReqLog';

const CONNECT_TIMEOUT_MS: number = 10000;
const READ_TIMEOUT_MS: number = 15000;

// /models 响应体（openai/anthropic 同形态；只声明消费字段，坑 59 ①）
interface ModelEntry {
  id: string;
}

interface ModelListResponse {
  data: ModelEntry[];
}

// gemini /v1beta/models 响应体
interface GeminiModelEntry {
  name: string;
}

interface GeminiModelListResponse {
  models: GeminiModelEntry[];
}

// anthro 探针请求体（max_tokens=1 最小消耗，坑 59 ①）
interface AnthropicProbeMessage {
  role: string;
  content: string;
}

interface AnthropicProbeBody {
  model: string;
  max_tokens: number;
  messages: AnthropicProbeMessage[];
}

// 探针响应 usage（加法口径与 SseParser / TitleApi 一致：prompt = input+read+creation、
// cached 只记 read；缺失回 0）
interface AnthropicProbeUsage {
  input_tokens?: number;
  output_tokens?: number;
  cache_read_input_tokens?: number;
  cache_creation_input_tokens?: number;
}

interface AnthropicProbeResponse {
  usage?: AnthropicProbeUsage;
}

// 探针结果（200 即连通；usage 三值供调用方落用途账本，全零守卫在 logTaskUsage）
export interface AnthropicProbeResult {
  promptTokens: number;
  completionTokens: number;
  cachedTokens: number;
}

// 网络层错误描述（与 ChatStreamBase.describeNetError 同款口径；此处独立成份——避免
// 为一行复用引两文件互引）
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

// 拉取模型 id 清单（去重 + 字典序升序——展示序稳定）；失败 reject Error 中文提示（调用方
// toast 呈现，P0-1 不静默）。未知协议按 openai 兜底（工厂同款保守路径）
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
    // 全局 UA 兜底：落 options 前写入，请求日志同见
    applyDefaultUserAgent(header);
    const request: http.HttpRequest = http.createHttp();
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: header,
      usingCache: false,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: CONNECT_TIMEOUT_MS,
      readTimeout: READ_TIMEOUT_MS
    };
    // 代理兜底：system 档零介入（options 原样）；direct/custom 档写 usingProxy
    applyEffectiveProxy(options);
    // 请求日志埋点：本链是添加服务商时最常见失败点（分辨网不通 / key 不对 / 端点方言）
    const startedAt: number = Date.now();
    const logId: string = reqLogBegin({
      // 不针对具体模型，model 传空串（列表行显示「—」）
      source: '模型清单', model: '', method: 'GET', url: url, headers: header, body: ''
    });
    let httpStatus: number = -1;
    // 失败收尾单点（五条 reject 路径共用——漏一处该条日志就永远停在「进行中」）
    const failLog = (message: string, responseTail: string): void => {
      reqLogEnd(logId, httpStatus, Date.now() - startedAt, message, responseTail);
      reject(new Error(message));
    };
    request.request(url, options)
      .then((resp: http.HttpResponse): void => {
        httpStatus = resp.responseCode;
        // 响应头回填：须在 failLog 之前——凭据明细在 reqLogEnd 时即删
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
              // 剥 models/ 前缀入库。★ 先 typeof 守卫再取值：守卫前求值 startsWith 在
              // 条目缺 name 时抛 TypeError，被 catch 误报「响应不是有效 JSON」
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
            // 裸 reject 会让「200 + 非 JSON」出口的日志永远停在「进行中」——必须过
            // failLog 单点收尾（Gemini 分支同 catch 已收口），文案逐字不变
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
        // destroy 包 try：裸 destroy 抛错会从 finally 穿出，把已成功 resolve 的结果改写
        // 成 rejected（成功请求显示成失败）；异常已拦在本层，静默忽略
        try {
          request.destroy();
        } catch (e) {
        }
      });
  });
}

// Anthropic 连接测试探针（背景见文件头★）：HTTP 200 即连通+鉴权通过，usage 三值供费用
// 账本（结构不符回全零，TitleApi 同款兜底）；失败 reject Error 中文提示，三错误路径与
// fetchModelIds 同口径
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
    // 全局 UA 兜底：落 options 前写入
    applyDefaultUserAgent(header);
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
    // 代理兜底：同 fetchModelIds 口径
    applyEffectiveProxy(options);
    // 请求日志埋点（来源标签同 fetchModelIds）
    const startedAt: number = Date.now();
    const logId: string = reqLogBegin({
      source: '模型清单', model: modelId, method: 'POST', url: url, headers: header,
      body: bodyText
    });
    let httpStatus: number = -1;
    request.request(url, options)
      .then((resp: http.HttpResponse): void => {
        httpStatus = resp.responseCode;
        // 响应头回填：须在两处 reqLogEnd 之前（凭据明细在 end 时即删）
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
        // 用量提取：坏 JSON 回全零不失败——连通判定只看 200，用量是附带面
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
          // 坏 JSON 不影响连通判定（成功判据只是 200，与 fetchModelIds 严格校验语义不同）
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
        // destroy 包 try（同 fetchModelIds：裸抛会把已 resolve 的结果改写成 rejected）
        try {
          request.destroy();
        } catch (e) {
        }
      });
  });
}
