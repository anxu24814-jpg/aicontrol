// 联网搜索·API 引擎实现层（2026-09-10 多引擎一期）：博查 / 秘塔 / Serper 三家 JSON
// 搜索 API 的 handler 实现 + Bing local 包装 + 分发表注册。骨架 = Cube 快照
// WebSearchService 分发表模式（声明式注册 + Map 分发，cube调研 02 §⑦）；能力二分
//（canSearch/canScrape + 能力级 requiresApiKey）= CherryStudio 预设表思想（调研档 03
// §1.1.1）；端点/鉴权/请求体/响应结构 = 2026-09-10 官方查证 + 端点实测（见各 handler
// 注释与 WebSearchParse.ets 多引擎节头注释；禁凭记忆改端点）。
// 分层：本文件只管「一个引擎怎么搜」；注册表/偏好解析/fallback 链/取钥分发编排在
// SearchEngineRegistry.ets（本文件被其 import——禁反向 import 防环）；解析纯函数在
// WebSearchParse.ets（零 import 可断言）。
// 失败语义：三家失败句与抓取侧同源（叶子 httpKitErrorText + httpStatusFailureText），
// 禁在本件自建取句或码表
import { http } from '@kit.NetworkKit';
import { SEARCH_TIMEOUT_MS, SEARCH_TIMEOUT_SECONDS, WebSearchOutcome,
  buildSearchContentForAI, searchBing } from '../providers/WebSearch';
import { BingResultItem, httpKitErrorText, httpStatusFailureText, metasoErrorMessage,
  parseBochaResults, parseMetasoResults, parseSerperResults } from '../providers/WebSearchParse';
import { reqLogBegin, reqLogEnd, reqLogSetResponseHeaders } from '../ReqLog';

// 引擎运行时入参（由注册表编排层组装）：apiKey = Asset 明文（免 key 引擎恒 ''）；
// baseUrl = 用户自定义入口（'' = 官方默认）；resultCount = 本次返回条数上限（2026-09-10
// 搜索条数助手级可调——值经发送链中转键到达编排层，换算与来源见 SearchLimits 头注释；
// 请求体条数字段与解析上限同源消费本字段，不再各读全局常量）
export interface SearchEngineRuntime {
  apiKey: string;
  baseUrl: string;
  resultCount: number;
}

// 引擎 handler 契约（分发表值类型；产出复用 WebSearchOutcome——引文卡与 contentForAI
// 组装口径与 Bing local 同源）
export type SearchHandler =
  (query: string, ctx: SearchEngineRuntime) => Promise<WebSearchOutcome>;

// HTTP POST JSON 一建一销（WebSearch.httpGet 同款范式；非 200 抛错转失败结果，响应体按
// 字符串取——三家均为 JSON 文本域）。抛出的句子已含状态码与正文片段（httpStatusFailureText
// 成型），取句侧经 httpKitErrorText 的「已成型句直返」分支原样返回，不再套前缀。
// ★ 2026-09-10 自检轮补 usingCache: false（同
// WebSearch.httpGet 注释：d.ts 默认 true + 与工程其余调用点一致 + 免隐性缓存占用）
// ★ 2026-09-21 执行笔补 extraData（全工程统一姿势，不跟 API 26 新字段 body）：原实现把
// 请求体算出并传参、options 里却漏设 extraData ⇒ 三家 POST 恒为空体（query 从未离开设备、
// 成功路径从未真正可用）；形参改 reqBody 与响应体局部名 body 区分（禁同名遮蔽）
// ★ 请求日志（2026-09-24 扩面笔）：落点 = 本函数一处，覆盖三家 API 引擎（博查 / 秘塔 /
// Serper）——三家仅 URL 与请求体不同，列表行以 URL 区分；来源标签固定「联网搜索」。终态
// 收敛用 logged 位（同 WebSearch.httpGet：非 2xx 与网络异常各记恰一次，防覆写）
async function httpPostJson(url: string, reqBody: string,
  headers: Record<string, string>): Promise<string> {
  const req: http.HttpRequest = http.createHttp();
  const startedAt: number = Date.now();
  const logId: string = reqLogBegin({
    source: '联网搜索', model: '', method: 'POST', url: url, headers: headers, body: reqBody
  });
  let logged: boolean = false;
  try {
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: reqBody,
      connectTimeout: SEARCH_TIMEOUT_MS,
      readTimeout: SEARCH_TIMEOUT_MS,
      usingCache: false,
      expectDataType: http.HttpDataType.STRING
    };
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
      reqLogEnd(logId, -1, Date.now() - startedAt,
        httpKitErrorText(e, SEARCH_TIMEOUT_SECONDS), '');
    }
    // 原样上抛（ArkTS 严格模式：throw 不接受任意类型值，须断言——arkts-limited-throw）
    throw e as Error;
  } finally {
    // destroy 包 try（2026-09-24 自检轮补，同 ModelListApi / TitleApi / KeyConnectTester /
    // WebDavApi 四处先例）：裸 destroy 抛错会从 finally 穿出，把已拿到的搜索结果改写成失败
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

// 失败结果组装（engineId 填真实 id——终态语义文案由调用方在 errorMessage 里给足）
function failedOutcome(query: string, engineId: string, message: string): WebSearchOutcome {
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
// count（LazyLLM 官方 cookbook 请求体逐字对照 + 调研档 04 §3.8）；无 key 实测 401
// {code, message}。keyHint = sk- 开头（官方 MCP README 配置示例）。
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
  try {
    const json: string = await httpPostJson(
      joinBase(ctx.baseUrl, 'https://api.bochaai.com') + '/v1/web-search', body, headers);
    const refs: BingResultItem[] = parseBochaResults(json, ctx.resultCount);
    return assembleOutcome(query, engineId, refs);
  } catch (e) {
    return failedOutcome(query, engineId, '博查搜索失败: ' + httpKitErrorText(e, SEARCH_TIMEOUT_SECONDS));
  }
}

// ── 秘塔（metaso.cn，国内可达 + 中文索引）──
// 端点 POST /api/v1/search；鉴权 Authorization: Bearer（key mk- 开头）；请求体
// q/scope/size/includeSummary = Cube 快照 metasoSearchEnhanced:717-768 逐字对照（MIT）。
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
  try {
    const json: string = await httpPostJson(
      joinBase(ctx.baseUrl, 'https://metaso.cn') + '/api/v1/search', body, headers);
    const embedded: string = metasoErrorMessage(json);
    if (embedded !== '') {
      return failedOutcome(query, engineId, '秘塔搜索失败: ' + embedded);
    }
    const refs: BingResultItem[] = parseMetasoResults(json, ctx.resultCount);
    return assembleOutcome(query, engineId, refs);
  } catch (e) {
    return failedOutcome(query, engineId, '秘塔搜索失败: ' + httpKitErrorText(e, SEARCH_TIMEOUT_SECONDS));
  }
}

// ── Serper（google.serper.dev，Google 结果代理）──
// 端点 POST /search；鉴权 X-API-KEY 头（无效 key 实测 403 Unauthorized；社区惯例经官方
// playground 与 LangChain/CrewAI 官方集成交叉核对，调研档 04 §3.6）；请求体 q/num/gl/hl
//（gl=cn + hl=zh-cn = 中文用户默认地域语言）；响应 organic[]{title,link,snippet,position}
// = 官方首页 playground 示例逐字段核对。
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
  try {
    const json: string = await httpPostJson(
      joinBase(ctx.baseUrl, 'https://google.serper.dev') + '/search', body, headers);
    const refs: BingResultItem[] = parseSerperResults(json, ctx.resultCount);
    return assembleOutcome(query, engineId, refs);
  } catch (e) {
    return failedOutcome(query, engineId, 'Serper 搜索失败: ' + httpKitErrorText(e, SEARCH_TIMEOUT_SECONDS));
  }
}
