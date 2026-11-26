// 联网搜索·API 引擎实现层：博查 / 秘塔 / Serper 三家 JSON 搜索 API 的 handler 实现 +
// Bing local 包装 + 分发表注册。骨架 = Cube 快照 WebSearchService 分发表模式（声明式注册
// + Map 分发）；能力二分（canSearch/canScrape + 能力级 requiresApiKey）= CherryStudio
// 预设表思想；端点/鉴权/请求体/响应结构 = 官方查证 + 端点实测（见各 handler 注释与
// WebSearchParse.ets 多引擎节头注释；禁凭记忆改端点）。
// 分层：本文件只管「一个引擎怎么搜」；注册表/偏好解析/fallback 链/取钥分发编排在
// SearchEngineRegistry.ets（本文件被其 import——禁反向 import 防环）；解析纯函数在
// WebSearchParse.ets（零 import 可断言）。
// 失败语义：三家失败句与抓取侧同源（叶子 httpKitErrorText + httpStatusFailureText），
// 禁在本件自建取句或码表
import { http } from '@kit.NetworkKit';
import { applyDefaultUserAgent, applyEffectiveProxy } from '../providers/RequestIdentity';
import { searchTimeoutSeconds, WebSearchOutcome, WebFetchOutcome,
  buildSearchContentForAI, searchBing } from '../providers/WebSearch';
import { BingResultItem, httpKitErrorText, httpStatusFailureText, metasoErrorMessage,
  parseBochaResults, parseDeepseekFetch, parseDeepseekResults, parseMetasoResults,
  parseSerperResults, parseZhipuResults } from '../providers/WebSearchParse';
import { reqLogBegin, reqLogEnd, reqLogSetResponseHeaders } from '../ReqLog';

// 引擎运行时入参（由注册表编排层组装）：apiKey = Asset 明文（免 key 引擎恒 ''）；
// baseUrl = 用户自定义入口（'' = 官方默认）；resultCount = 本次返回条数上限（值由发送链
// 在接纳时快照、经 ToolExecutionContext.searchResultCount 随链携带到编排层，来源 = 全局键
// prefSearchResultCount，换算见 SearchLimits 头注释；请求体条数字段与解析上限同源消费本
// 字段，不再各读全局常量）
export interface SearchEngineRuntime {
  apiKey: string;
  baseUrl: string;
  resultCount: number;
  // 子引擎编码：仅有多引擎概念的引擎消费（智谱 search_engine 参数，值域见描述符
  // variants），无子引擎概念的引擎恒 ''；注册表编排层从引擎配置 JSON 的 variant 字段
  // 取值、空则回落描述符 defaultVariant
  variant: string;
}

// 引擎 handler 契约（分发表值类型；产出复用 WebSearchOutcome——引文卡与 contentForAI
// 组装口径与 Bing local 同源）
export type SearchHandler =
  (query: string, ctx: SearchEngineRuntime) => Promise<WebSearchOutcome>;

// HTTP POST JSON 一建一销（WebSearch.httpGet 同款范式；非 200 抛错转失败结果，响应体按
// 字符串取——三家均为 JSON 文本域）。抛出的句子已含状态码与正文片段（httpStatusFailureText
// 成型），取句侧经 httpKitErrorText 的「已成型句直返」分支原样返回，不再套前缀。
// 坑（已修勿回游）：请求体须走 extraData——原实现漏设 ⇒ 三家 POST 恒空体、成功路径从未
// 真正可用（形参 reqBody 与响应体局部名 body 区分，禁同名遮蔽）；usingCache: false
//（d.ts 默认 true，免隐性缓存占用）。请求日志落点 = 本函数一处，覆盖三家 API 引擎（仅
// URL 与请求体不同，列表行以 URL 区分；来源标签固定「联网搜索」）；终态收敛用 logged 位
//（非 2xx 与网络异常各记恰一次，防覆写）
async function httpPostJson(url: string, reqBody: string,
  headers: Record<string, string>, timeoutSec: number): Promise<string> {
  const req: http.HttpRequest = http.createHttp();
  const startedAt: number = Date.now();
  // 本请求计时取调用方快照（秒 → 毫秒；读全局键 prefSearchTimeoutSec，引擎入口取一次 +
  // 形参下传——计时与失败文案同源，禁在此二读，同 WebSearch.httpGet 用法契约）
  const timeoutMs: number = timeoutSec * 1000;
  // 全局 UA 兜底：先于日志埋点写入——本函数一处覆盖三家（日志记到的是实际发送的头，
  // 引擎头内无 UA，恒生效）
  applyDefaultUserAgent(headers);
  const logId: string = reqLogBegin({
    source: '联网搜索', model: '', method: 'POST', url: url, headers: headers, body: reqBody
  });
  let logged: boolean = false;
  try {
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: reqBody,
      connectTimeout: timeoutMs,
      readTimeout: timeoutMs,
      usingCache: false,
      expectDataType: http.HttpDataType.STRING
    };
    // 代理兜底写入：system 档零介入 = options 原样；direct/custom 档写 usingProxy。
    // 本函数一处覆盖三家；读超时保持搜索自档不吃全局档
    applyEffectiveProxy(options);
    const resp: http.HttpResponse = await req.request(url, options);
    // 响应头回填须在 reqLogEnd 之前（凭据明细在 end 时即删）
    reqLogSetResponseHeaders(logId, resp.header);
    const body: string = typeof resp.result === 'string' ? resp.result : String(resp.result);
    if (resp.responseCode < 200 || resp.responseCode >= 300) {
      // 非 2xx 带状态码与错误页正文片段（原文案只有 'HTTP 403'，正文里的原因被丢掉）
      const failText: string = httpStatusFailureText(resp.responseCode, body);
      reqLogEnd(logId, resp.responseCode, Date.now() - startedAt, failText, body);
      logged = true;
      throw new Error(failText);
    }
    reqLogEnd(logId, resp.responseCode, Date.now() - startedAt, '', '');
    logged = true;
    return body;
  } catch (e) {
    if (!logged) {
      reqLogEnd(logId, -1, Date.now() - startedAt, httpKitErrorText(e, timeoutSec), '');
    }
    // 原样上抛（ArkTS 严格模式：throw 不接受任意类型值，须断言——arkts-limited-throw）
    throw e as Error;
  } finally {
    // destroy 包 try：裸 destroy 抛错会从 finally 穿出，把已拿到的搜索结果改写成失败
    try {
      req.destroy();
    } catch (e) {
    }
  }
}

// 入口归一（自定义 baseUrl 去尾斜杠；空 = 默认官方端点）
function joinBase(custom: string, fallback: string): string {
  const trimmed: string = custom.trim().replace(/\/+$/, '');
  return trimmed !== '' ? trimmed : fallback;
}

// 成功结果组装（三家用同一形态：解析条数 + ref_ 前缀 id 兜底 + contentForAI 与 Bing
// local 同源组装——searchEngine 填真实引擎 id，引文卡按工具名回放不受影响）
function assembleOutcome(query: string, engineId: string,
  refs: BingResultItem[]): WebSearchOutcome {
  const stamp: number = Date.now();
  for (let i = 0; i < refs.length; i++) {
    refs[i].id = `ref_${stamp}_${i + 1}`;
  }
  return { success: true, query: query, searchEngine: engineId,
    references: refs, contentForAI: buildSearchContentForAI(refs), errorMessage: '' };
}

// 失败结果组装（engineId 填真实 id——终态语义文案由调用方在 errorMessage 里给足）。
// ★ 单源导出：SearchEngineRegistry 编排面（dispatchSearch 失败路）同引本函数，禁再持
// 本地副本——两份逐字同形是漂移面；依赖方向 Registry→本件既有，不生环
export function failedOutcome(query: string, engineId: string, message: string): WebSearchOutcome {
  return { success: false, query: query, searchEngine: engineId,
    references: [], contentForAI: '', errorMessage: message };
}

// ── Bing local 包装（免 key；baseUrl 可配走单入口、条数随 ctx 传入，见 searchBing 注释）──
export async function bingLocalSearch(query: string,
  ctx: SearchEngineRuntime): Promise<WebSearchOutcome> {
  return searchBing(query, ctx.baseUrl, ctx.resultCount);
}

// ── 博查（api.bochaai.com，国内可达 + 人民币计价 + Bing 兼容响应）──
// 端点 POST /v1/web-search；鉴权 Authorization: Bearer；请求体 query/freshness/summary/
// count（LazyLLM 官方 cookbook 请求体逐字对照）；无 key 实测 401 {code, message}。
// keyHint = sk- 开头（官方 MCP README 配置示例）。
export async function bochaSearch(query: string,
  ctx: SearchEngineRuntime): Promise<WebSearchOutcome> {
  const engineId: string = 'bocha';
  if (ctx.apiKey === '') {
    return failedOutcome(query, engineId, '博查 API Key 未配置');
  }
  const body: string = JSON.stringify({
    query: query, freshness: 'noLimit', summary: true, count: ctx.resultCount
  });
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${ctx.apiKey}`
  };
  // 本次搜索的超时快照——计时与失败文案同吃这一份（WebSearch 文件头「用法契约」）
  const timeoutSec: number = searchTimeoutSeconds();
  try {
    const json: string = await httpPostJson(
      joinBase(ctx.baseUrl, 'https://api.bochaai.com') + '/v1/web-search', body, headers, timeoutSec);
    const refs: BingResultItem[] = parseBochaResults(json, ctx.resultCount);
    return assembleOutcome(query, engineId, refs);
  } catch (e) {
    return failedOutcome(query, engineId, '博查搜索失败: ' + httpKitErrorText(e, timeoutSec));
  }
}

// ── 秘塔（metaso.cn，国内可达 + 中文索引）──
// 端点 POST /api/v1/search；鉴权 Authorization: Bearer（key mk- 开头）；请求体
// q/scope/size/includeSummary = Cube 快照 metasoSearchEnhanced 逐字对照（MIT）。
// ★ 无 key 实测返回 HTTP 200 + {errCode:2005, errMsg:"API密钥无效"}——必须先验内嵌错误
// 再解析（WebSearchParse.metasoErrorMessage，非 2xx 抛错路径抓不到这个形态）。
export async function metasoSearch(query: string,
  ctx: SearchEngineRuntime): Promise<WebSearchOutcome> {
  const engineId: string = 'metaso';
  if (ctx.apiKey === '') {
    return failedOutcome(query, engineId, '秘塔 API Key 未配置');
  }
  const body: string = JSON.stringify({
    q: query, scope: 'webpage', size: ctx.resultCount, includeSummary: false
  });
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Authorization': `Bearer ${ctx.apiKey}`
  };
  // 本次搜索的超时快照（同博查）
  const timeoutSec: number = searchTimeoutSeconds();
  try {
    const json: string = await httpPostJson(
      joinBase(ctx.baseUrl, 'https://metaso.cn') + '/api/v1/search', body, headers, timeoutSec);
    const embedded: string = metasoErrorMessage(json);
    if (embedded !== '') {
      return failedOutcome(query, engineId, '秘塔搜索失败: ' + embedded);
    }
    const refs: BingResultItem[] = parseMetasoResults(json, ctx.resultCount);
    return assembleOutcome(query, engineId, refs);
  } catch (e) {
    return failedOutcome(query, engineId, '秘塔搜索失败: ' + httpKitErrorText(e, timeoutSec));
  }
}

// ── Serper（google.serper.dev，Google 结果代理）──
// 端点 POST /search；鉴权 X-API-KEY 头（无效 key 实测 403 Unauthorized；经官方 playground
// 与 LangChain/CrewAI 官方集成交叉核对）；请求体 q/num/gl/hl（gl=cn + hl=zh-cn = 中文
// 用户默认地域语言）；响应 organic[]{title,link,snippet,position} = 官方首页 playground
// 示例逐字段核对。
export async function serperSearch(query: string,
  ctx: SearchEngineRuntime): Promise<WebSearchOutcome> {
  const engineId: string = 'serper';
  if (ctx.apiKey === '') {
    return failedOutcome(query, engineId, 'Serper API Key 未配置');
  }
  const body: string = JSON.stringify({
    q: query, num: ctx.resultCount, gl: 'cn', hl: 'zh-cn'
  });
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'X-API-KEY': ctx.apiKey
  };
  // 本次搜索的超时快照（同博查）
  const timeoutSec: number = searchTimeoutSeconds();
  try {
    const json: string = await httpPostJson(
      joinBase(ctx.baseUrl, 'https://google.serper.dev') + '/search', body, headers, timeoutSec);
    const refs: BingResultItem[] = parseSerperResults(json, ctx.resultCount);
    return assembleOutcome(query, engineId, refs);
  } catch (e) {
    return failedOutcome(query, engineId, 'Serper 搜索失败: ' + httpKitErrorText(e, timeoutSec));
  }
}

// ── DeepSeek（开放平台自研搜索/抓取 API；搜索与抓取同域同 key）──
// 搜索端点 POST /v1/tools/search；鉴权 Authorization: Bearer（与 DeepSeek 服务商同一把
// API Key）；请求体 query/count/need_content（官方指南逐字段核对：
// https://api-docs.deepseek.com/zh-cn/guides/search，query 1~128 字符——清洗层 100 字截断
// 已满足；need_content=false 时 content 恒空，模型读 summary 长摘要即可）。
// 计费 = 5 元/1000 次成功请求（失败/空结果不计费，与条数无关）；QPS 5/s，超限 429。
export async function deepseekSearch(query: string,
  ctx: SearchEngineRuntime): Promise<WebSearchOutcome> {
  const engineId: string = 'deepseek';
  if (ctx.apiKey === '') {
    return failedOutcome(query, engineId, 'DeepSeek API Key 未配置');
  }
  const body: string = JSON.stringify({
    query: query, count: ctx.resultCount, need_content: false
  });
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${ctx.apiKey}`
  };
  const timeoutSec: number = searchTimeoutSeconds();
  try {
    const json: string = await httpPostJson(
      joinBase(ctx.baseUrl, 'https://api.deepseek.com') + '/v1/tools/search', body, headers,
      timeoutSec);
    const refs: BingResultItem[] = parseDeepseekResults(json, ctx.resultCount);
    return assembleOutcome(query, engineId, refs);
  } catch (e) {
    return failedOutcome(query, engineId, 'DeepSeek 搜索失败: ' + httpKitErrorText(e, timeoutSec));
  }
}

// DeepSeek 网页抓取（scrape_web 的第二条引擎通路；与搜索同批 API）：
// POST /v1/tools/fetch，请求 {url}，响应 {title, content}——content 为 Markdown 正文。
// 计费同搜索（5 元/1000 次成功请求）；404 = 页面不可用/无正文（调用方回落本地抓取）。
// url 缺协议头时补 https://（官方要求含 host 的 HTTP/HTTPS 地址；纯脏串由失败回落本地兜）
export async function deepseekFetch(rawUrl: string,
  ctx: SearchEngineRuntime): Promise<WebFetchOutcome> {
  const engineId: string = 'deepseek_fetch';
  const url: string = rawUrl.startsWith('http://') || rawUrl.startsWith('https://') ?
    rawUrl : 'https://' + rawUrl;
  if (ctx.apiKey === '') {
    return { success: false, url: url, title: '', content: '', searchEngine: engineId,
      errorMessage: 'DeepSeek API Key 未配置' };
  }
  const body: string = JSON.stringify({ url: url });
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${ctx.apiKey}`
  };
  const timeoutSec: number = searchTimeoutSeconds();
  try {
    const json: string = await httpPostJson(
      joinBase(ctx.baseUrl, 'https://api.deepseek.com') + '/v1/tools/fetch', body, headers,
      timeoutSec);
    const parsed = parseDeepseekFetch(json);
    if (parsed.content.trim() === '') {
      return { success: false, url: url, title: parsed.title, content: '',
        searchEngine: engineId, errorMessage: '未提取到网页正文' };
    }
    return { success: true, url: url, title: parsed.title, content: parsed.content,
      searchEngine: engineId, errorMessage: '' };
  } catch (e) {
    return { success: false, url: url, title: '', content: '', searchEngine: engineId,
      errorMessage: 'DeepSeek 抓取失败: ' + httpKitErrorText(e, timeoutSec) };
  }
}

// ── 智谱（BigModel 开放平台 Web Search API）──
// 端点 POST /api/paas/v4/web_search；鉴权 Authorization: Bearer（与智谱服务商同一把 API
// Key）；请求体 search_query/search_engine/search_intent/count/content_size（官方 API
// Reference 逐字段核对：https://docs.bigmodel.cn/api-reference/工具-api/网络搜索）。
// · search_query 上限 70 字符——清洗层 100 字截断后本层再截 70，超长会被拒（400）
// · search_engine = 详情页子引擎选择（ctx.variant），缺省 search_std
// · search_intent=false 跳过意图识别（模型已决定搜索，无需二次判断）
// · content_size=high 取长摘要（信息量更大，计费与 medium 同价）
// 计费按次：search_std 0.01 元 / search_pro 0.03 元 / 搜狗与夸克 0.05 元
const ZHIPU_QUERY_MAX: number = 70;

// 搜狗子引擎的 count 只收 10/20/30/40/50 枚举（官方 API Reference 明载；其余档位会 400）。
// 全局条数上限 25，故上取整后只可能落 10/20/30 三档——搜索质量优先于条数精确
function zhipuCountFor(searchEngine: string, want: number): number {
  if (searchEngine !== 'search_pro_sogou') {
    return want;
  }
  if (want <= 10) {
    return 10;
  }
  if (want <= 20) {
    return 20;
  }
  if (want <= 30) {
    return 30;
  }
  return 50;
}

export async function zhipuSearch(query: string,
  ctx: SearchEngineRuntime): Promise<WebSearchOutcome> {
  const engineId: string = 'zhipu';
  if (ctx.apiKey === '') {
    return failedOutcome(query, engineId, '智谱 API Key 未配置');
  }
  const searchQuery: string = query.length > ZHIPU_QUERY_MAX ?
    query.substring(0, ZHIPU_QUERY_MAX) : query;
  const searchEngine: string = ctx.variant !== '' ? ctx.variant : 'search_std';
  const body: string = JSON.stringify({
    search_query: searchQuery, search_engine: searchEngine, search_intent: false,
    count: zhipuCountFor(searchEngine, ctx.resultCount), content_size: 'high'
  });
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${ctx.apiKey}`
  };
  const timeoutSec: number = searchTimeoutSeconds();
  try {
    const json: string = await httpPostJson(
      joinBase(ctx.baseUrl, 'https://open.bigmodel.cn') + '/api/paas/v4/web_search',
      body, headers, timeoutSec);
    const refs: BingResultItem[] = parseZhipuResults(json, ctx.resultCount);
    return assembleOutcome(query, engineId, refs);
  } catch (e) {
    return failedOutcome(query, engineId, '智谱搜索失败: ' + httpKitErrorText(e, timeoutSec));
  }
}
