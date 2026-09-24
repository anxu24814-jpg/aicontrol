// 联网搜索域（2026-09-03 Cube 吸收第三批①）：Bing local 免 Key 引擎 + 网页本地抓取——
// 源自 cubeagent-stream-test（chatcube MIT 快照）services/WebSearchService.ets 裁剪移植
//（bingSearchInternal:1898-1938 / bingSearchByUrl:1940-1975 / fetchUrlContentInternal:
// 2143-2181 + normalizeContentUrl/isValidUrl）。解析纯函数在 WebSearchParse.ets（零 import
// 可断言）；本文件只管 HTTP 传输与结果组装。★ 2026-09-10 多引擎一期：本文件收窄为
// 「Bing local 引擎实现 + 本地抓取 + 多引擎共用件」（WebSearchOutcome 契约 / httpGet /
// buildSearchContentForAI 引文串组装）；API 引擎实现与注册表分发表在 common/search/
//（SearchEngineRegistry + ApiSearchEngines）——新增引擎在 search/ 注册表加描述符与
// handler，不在本文件加处理函数。
// 工具注册与执行器壳在 ToolTypes（GetTimeInfoExecutor 同款域布局——避免循环 import）。
import { http } from '@kit.NetworkKit';
import { httpKitErrorText, httpStatusFailureText, BingResultItem, HtmlContent, isValidUrl,
  parseBingSearchResults, parseHtmlContent } from './WebSearchParse';
import { SEARCH_RESULT_COUNT_DEFAULT } from '../search/SearchLimits';
import { reqLogBegin, reqLogEnd, reqLogSetResponseHeaders } from '../ReqLog';

// 请求超时（Cube 319-321 注释：境外 API 国内连通差统一抬 20s——Bing 主域国内可达，
// 沿用 20s 保守值；P1-3 零冗余等待口径 = 兜底上限非固定延时）。★ 多引擎一期起导出：
// common/search/ApiSearchEngines 三家 API 引擎共用同一超时，零双源
export const SEARCH_TIMEOUT_MS: number = 20000;
// 抓取失败指引句（★ 2026-09-21 任务书-联网三件错误语义-20260921 笔 A）：scrape_web 是静态
// 抓取，失败不等于页面不存在——真机实证：同一地址抓取超时而浏览器通道正常。指引模型换通路
// 复核，两处失败分支同用（URL 校验失败 + 请求失败）
const FETCH_FALLBACK_HINT: string = '。可改用 browse_open 打开该地址复核';
// 抓取侧超时秒数（拼 2300028 文案用；与 SEARCH_TIMEOUT_MS 同源换算，禁另写数）。
// ★ 2026-09-21 任务书-联网搜索API引擎失败语义-20260921：导出给 common/search/ApiSearchEngines
// 复用（三家引擎失败句与抓取侧同一取句口径）——单一来源，消费件禁自算秒数
// ★ 零秒防御（2026-09-21 八百三十八节，与 BrowseWeb 笔 B 同形）：常量降到 500 ms 以下时
// Math.round 得 0 ⇒ 文案报「请求超时（0 秒）」；下限钳 1 秒。
export const SEARCH_TIMEOUT_SECONDS: number = Math.max(1, Math.round(SEARCH_TIMEOUT_MS / 1000));
// ★ 2026-09-10 搜索结果条数助手级可调：原单源常量 SEARCH_RESULT_COUNT(=5) 退役——条数改为
// 助手级配置（assistants.searchResultCount），值域/换算/中转键单源 = common/search/
// SearchLimits，本文件只在其 Bing 链入参缺省时引用默认值（零回归：缺省仍是 5）
// 摘要单条截断（引文卡与 contentForAI 同源口径）
const SNIPPET_MAX: number = 200;

// 搜索结果（Cube SearchResult:13-36 裁剪——references 供引文卡，contentForAI 供模型回传）
export interface WebSearchOutcome {
  success: boolean;
  query: string;
  searchEngine: string;
  references: BingResultItem[];
  contentForAI: string;
  errorMessage: string;
}

// 抓取结果（Cube WebSearchResult 裁剪——单条结果以 results[1] 形态进引文卡）
export interface WebFetchOutcome {
  success: boolean;
  url: string;
  title: string;
  content: string;
  errorMessage: string;
}

// HTTP GET 一建一销（成对释放红线；P1-2 单请求非轮询）。非 200 抛错（调用方转失败结果），
// 响应体按字符串取（expectDataType STRING——HTML/文本域）。★ 2026-09-10 自检轮补
// usingCache: false——http kit 本选项官方 d.ts 明载默认 true（「优先读缓存」），本域漏设
// 而工程其余 HTTP 调用点均显式关（TitleApi/BalanceApi/ChatStreamBase/ModelListApi/
// FeedbackMeow）。不关的两重代价：①搜索结果与网页抓取正文必须现取，命中进程缓存会返旧
// 内容；②该缓存落点官方未公开（cacheSize 官方口径只含 cacheDir），若落在 cacheDir 之外
// 即成存储页统计不到、也清理不到的隐性占用，破坏存储页「清理范围 = 统计范围」不变量
// ★ 请求日志（2026-09-24 扩面笔）：落点 = 本函数一处，覆盖两条链（Bing local 搜索 /
// scrape_web 网页抓取），由 source 形参区分来源标签。终态收敛用一个 logged 位：非 2xx 与
// 网络异常两条路都各记**恰一次**（reqLogEnd 是按 id 覆写，漏分家会把已记的状态码覆写成 -1）
async function httpGet(url: string, headers: Record<string, string>,
  source: string): Promise<string> {
  const req: http.HttpRequest = http.createHttp();
  const startedAt: number = Date.now();
  const logId: string = reqLogBegin({
    source: source, model: '', method: 'GET', url: url, headers: headers, body: ''
  });
  let logged: boolean = false;
  try {
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: headers,
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
      // 未走到响应（网络层/超时）——记传输层失败；已记过的那条走上面自己的终态
      reqLogEnd(logId, -1, Date.now() - startedAt,
        httpKitErrorText(e, SEARCH_TIMEOUT_SECONDS), '');
    }
    // 原样上抛（ArkTS 严格模式：throw 不接受任意类型值，须断言——arkts-limited-throw）
    throw e as Error;
  } finally {
    // destroy 包 try（2026-09-24 自检轮补，同 ModelListApi / TitleApi / KeyConnectTester /
    // WebDavApi 四处先例）：裸 destroy 抛错会从 finally 穿出，把已拿到的搜索结果 / 网页正文
    // 改写成一次失败（调用方 catch 到的是 destroy 的错，与真实成败无关）
    try {
      req.destroy();
    } catch (e) {
    }
  }
}

// Bing 反指纹请求头（Cube bingSearchByUrl:1952-1958 逐行移植——鸿蒙 http kit 对
// brotli 解码不稳，显式压到 gzip/deflate；Referer+Cookie 过基础机检）
function bingHeaders(): Record<string, string> {
  const headers: Record<string, string> = {};
  headers['Referer'] = 'https://www.bing.com/';
  headers['Cookie'] = 'SRCHHPGUSR=ULSR=1';
  headers['Accept-Encoding'] = 'gzip, deflate';
  headers['Accept-Charset'] = 'utf-8';
  return headers;
}

// 引文模型回传串组装（contentForAI：编号 + 标题 + URL + 摘要——模型据 description 里的
// 引用规范以 Markdown 链接引用；编号与引文卡 index 对齐）。★ 2026-09-10 多引擎一期起
// 导出：API 引擎（ApiSearchEngines）与 Bing local 共用同一组装口径，零双源
export function buildSearchContentForAI(refs: BingResultItem[]): string {
  const lines: string[] = [];
  for (const ref of refs) {
    const snippet: string = ref.snippet.length > SNIPPET_MAX ?
      ref.snippet.substring(0, SNIPPET_MAX) + '...' : ref.snippet;
    lines.push(`[${ref.index}] ${ref.title}\n${ref.url}\n${snippet}`);
  }
  return lines.join('\n\n');
}

function failedSearch(query: string, message: string): WebSearchOutcome {
  return { success: false, query: query, searchEngine: 'bing_local',
    references: [], contentForAI: '', errorMessage: message };
}

// Bing 搜索（主域失败或零结果重试 cn.bing.com 备用入口——Cube bingSearchInternal 同构；
// 两入口都解析失败返回主域失败结果，错误信息进 errorMessage 不静默）。
// ★ 2026-09-10 多引擎一期加 baseUrl 可选参：不传/空串 = 现状 www/cn 双入口逐字节零回归；
// 传入 = 用户自定义单入口（国内中转逃生门——走单入口不回落官方域，改址即全量改道）
// ★ 2026-09-10 搜索结果条数助手级可调加 maxCount 参：调用方（ApiSearchEngines.bingLocalSearch）
// 传助手级生效条数；不传 = 默认 5（旧常量同值，非会话路径调用零回归）
export async function searchBing(query: string, baseUrl?: string,
  maxCount: number = SEARCH_RESULT_COUNT_DEFAULT): Promise<WebSearchOutcome> {
  const encoded: string = encodeURIComponent(query);
  const custom: string = baseUrl !== undefined ? baseUrl.trim().replace(/\/+$/, '') : '';
  if (custom !== '') {
    // 自定义入口失败不回落官方域（用户改址的语义 = 全量改道；失败原样上报）
    try {
      return await bingSearchByUrl(`${custom}/search?q=${encoded}`, query, maxCount);
    } catch (e) {
      return failedSearch(query, httpKitErrorText(e, SEARCH_TIMEOUT_SECONDS));
    }
  }
  try {
    const primary: WebSearchOutcome =
      await bingSearchByUrl(`https://www.bing.com/search?q=${encoded}&setlang=zh-hans`, query,
        maxCount);
    if (primary.success && primary.references.length > 0) {
      return primary;
    }
    const fallback: WebSearchOutcome =
      await bingSearchByUrl(`https://cn.bing.com/search?q=${encoded}`, query, maxCount);
    if (fallback.success && fallback.references.length > 0) {
      return fallback;
    }
    return primary.success ? primary : fallback;
  } catch (e) {
    return failedSearch(query, httpKitErrorText(e, SEARCH_TIMEOUT_SECONDS));
  }
}

// 单入口执行：请求 + 解析（非 200 由 httpGet 抛错转失败——不静默）
async function bingSearchByUrl(searchUrl: string, query: string,
  maxCount: number): Promise<WebSearchOutcome> {
  let html: string = '';
  try {
    html = await httpGet(searchUrl, bingHeaders(), '联网搜索');
  } catch (e) {
    return failedSearch(query, httpKitErrorText(e, SEARCH_TIMEOUT_SECONDS));
  }
  const refs: BingResultItem[] = parseBingSearchResults(html, maxCount);
  // id 兜底（解析层不管 id——执行器侧统一 ref_ 前缀 + 时间戳序）
  const stamp: number = Date.now();
  for (let i = 0; i < refs.length; i++) {
    refs[i].id = `ref_${stamp}_${i + 1}`;
  }
  return { success: true, query: query, searchEngine: 'bing_local',
    references: refs, contentForAI: buildSearchContentForAI(refs), errorMessage: '' };
}

// 网页本地抓取（Cube fetchUrlContentInternal 裁剪——Bing 模式无 API 抓取引擎，
// 恒走本地 HTML 解析；正文 8000 截断在解析层）
export async function fetchUrlContent(rawUrl: string): Promise<WebFetchOutcome> {
  const url: string =
    rawUrl.startsWith('http://') || rawUrl.startsWith('https://') ? rawUrl : 'https://' + rawUrl;
  if (!isValidUrl(url)) {
    return { success: false, url: url, title: '', content: '',
      errorMessage: 'URL 格式无效' + FETCH_FALLBACK_HINT };
  }
  let html: string = '';
  try {
    // 请求 URL 编码（B7）：仅含非 ASCII 才 encodeURI；展示面 out.url 保持原串。
    // ★ 已收口（2026-09-21 B-14）：encodeURI 对串内既有 %XX 段的 `%` 二次转义（→ %25）以
    //   .replace(/%25/g, '%') 还原——对既有 %20 段 / 裸 % / 字面 %25 三形态实测零改写，
    //   等价于「仅对非 ASCII 段编码」；与 providers/ToolHttp 同口径（两域注释互指，改则同改）
    const requestUrl: string = /[^\x00-\x7F]/.test(url) ? encodeURI(url).replace(/%25/g, '%') : url;
    html = await httpGet(requestUrl, {}, '网页抓取');
  } catch (e) {
    return { success: false, url: url, title: '', content: '',
      errorMessage: httpKitErrorText(e, SEARCH_TIMEOUT_SECONDS) + FETCH_FALLBACK_HINT };
  }
  const parsed: HtmlContent = parseHtmlContent(html);
  if (parsed.content.trim() === '') {
    return { success: false, url: url, title: parsed.title, content: '',
      errorMessage: '未提取到网页正文' };
  }
  return { success: true, url: url, title: parsed.title, content: parsed.content,
    errorMessage: '' };
}
