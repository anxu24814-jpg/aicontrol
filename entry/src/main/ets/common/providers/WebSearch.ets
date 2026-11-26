// 联网搜索域：Bing local 免 Key 引擎 + 网页本地抓取（源自 cubeagent-stream-test MIT 快照
// 裁剪移植）。解析纯函数在 WebSearchParse.ets（零 import 可断言）；本文件只管 HTTP 传输
// 与结果组装。多引擎一期起本文件收窄为「Bing local 引擎实现 + 本地抓取 + 多引擎共用件」
//（WebSearchOutcome 契约 / httpGet / buildSearchContentForAI 引文串组装）；API 引擎实现与
// 注册表分发表在 common/search/（SearchEngineRegistry + ApiSearchEngines）——★ 新增引擎
// 在 search/ 注册表加描述符与 handler，不在本文件加处理函数。
// 工具注册与执行器壳在 ToolTypes（避免循环 import）。
import { http } from '@kit.NetworkKit';
import { httpKitErrorText, httpStatusFailureText, BingResultItem, HtmlContent, isValidUrl,
  parseBingSearchResults, parseHtmlContent, SCRAPE_TOTAL_MAX_CHARS } from './WebSearchParse';
import { SEARCH_RESULT_COUNT_DEFAULT, SEARCH_TIMEOUT_SECONDS_DEFAULT,
  resolveSearchTimeoutSeconds } from '../search/SearchLimits';
import { PREF_SEARCH_TIMEOUT_SEC_KEY } from '../AppPreferences';
import { reqLogBegin, reqLogEnd, reqLogSetResponseHeaders } from '../ReqLog';

// 联网请求超时（默认 20s = 旧常量同值零回归；P1-3 口径 = 兜底上限非固定延时）。覆盖本域
// 两条链（Bing local / scrape_web）+ ApiSearchEngines 三引擎（自本件 import 复用零双源）。
// ★ 与条数的通道刻意不同：条数走执行上下文快照（承载助手/会话归属沿革），超时是纯全局值
//——改值下一个请求生效；键与值域单源 = AppPreferences / common/search/SearchLimits。
// ★ 用法契约（治「计时与文案撕裂」）：取值点 = 请求入口各取一次（searchBing /
// fetchUrlContent / API 三引擎），经形参下传至 httpGet——计时与失败文案都吃这一份快照，
// 在途请求不受改值影响（禁消费件在 catch 里二读）。
// 失败文案「请求超时（N 秒）」与计时共用的唯一取值点：脏值经 resolve 收口 5~60，
// Math.max(1, ...) 零秒防御兜底（与 ToolHttp / BrowseWeb 同族防御）
export function searchTimeoutSeconds(): number {
  const stored: number | undefined = AppStorage.get<number>(PREF_SEARCH_TIMEOUT_SEC_KEY);
  return Math.max(1, resolveSearchTimeoutSeconds(stored ?? SEARCH_TIMEOUT_SECONDS_DEFAULT));
}
// 抓取失败指引句：scrape_web 是静态抓取，失败不等于页面不存在（真机实证：同一地址抓取
// 超时而浏览器通道正常）——指引模型换通路复核，两处失败分支同用
const FETCH_FALLBACK_HINT: string = '。可改用 browse_open 打开该地址复核';
// ★ 秒数导出给 common/search/ApiSearchEngines 复用（三家引擎失败句与抓取侧同一取句
// 口径）——单一来源，消费件禁自算秒数；常量形态已退役，改由上方 searchTimeoutSeconds()
// 取（零秒防御随之在该函数内）。
// ★ 条数同理退役单源常量 SEARCH_RESULT_COUNT(=5)：改用户配置（全局偏好键
// prefSearchResultCount），值域/换算单源 = common/search/SearchLimits，本文件只在入参
// 缺省时引用默认值（零回归：缺省仍是 5）
// 摘要单条截断（引文卡与 contentForAI 同源口径）
const SNIPPET_MAX: number = 200;
// ★ 抓取浏览器 UA（全局请求标识 UA 例外链）：网页抓取与 Bing local 搜索恒带浏览器身份
//（串照 RikkaHub 同族取，勿自造），**不随「网络设置」的全局 UA 变化**——抓网页需要
// 浏览器身份，吃全局自定义值反而更易被拒；本件刻意零引用 RequestIdentity 的取值/兜底函数
const BROWSER_UA: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) ' +
  'Chrome/131.0.0.0 Safari/537.36';

// 搜索结果（references 供引文卡，contentForAI 供模型回传）
export interface WebSearchOutcome {
  success: boolean;
  query: string;
  searchEngine: string;
  references: BingResultItem[];
  contentForAI: string;
  errorMessage: string;
}

// 抓取结果（单条结果以 results[1] 形态进引文卡）。★ searchEngine = 来源标识——本地恒
// 'url_fetch'，引擎抓取由 handler 填如 'deepseek_fetch'；执行器据此写载荷，引文卡回放
// 只读 title/url/snippet 不受影响
export interface WebFetchOutcome {
  success: boolean;
  url: string;
  title: string;
  content: string;
  searchEngine: string;
  errorMessage: string;
}

// HTTP GET 一建一销（成对释放红线；P1-2 单请求非轮询）。非 200 抛错（调用方转失败结果），
// 响应体按字符串取（expectDataType STRING——HTML/文本域）。★ usingCache 必须显式 false
//——http kit 本选项官方 d.ts 明载默认 true（「优先读缓存」）：命中进程缓存会返旧内容
//（搜索/抓取必须现取），且该缓存落点官方未公开（cacheSize 口径只含 cacheDir），落在
// cacheDir 之外即成存储页统计不到也清理不到的隐性占用（破坏「清理范围 = 统计范围」不变量）。
// ★ 请求日志落点 = 本函数一处，覆盖两条链（Bing local / scrape_web），source 形参区分
// 来源标签。终态收敛用一个 logged 位：非 2xx 与网络异常两条路各记**恰一次**（reqLogEnd
// 按 id 覆写，漏分家会把已记的状态码覆写成 -1）
async function httpGet(url: string, headers: Record<string, string>,
  source: string, timeoutSec: number): Promise<string> {
  const req: http.HttpRequest = http.createHttp();
  const startedAt: number = Date.now();
  // 计时取调用方快照（秒 → 毫秒；取值点与失败文案同一处，见文件头「用法契约」）
  const timeoutMs: number = timeoutSec * 1000;
  const logId: string = reqLogBegin({
    source: source, model: '', method: 'GET', url: url, headers: headers, body: ''
  });
  let logged: boolean = false;
  try {
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: timeoutMs,
      readTimeout: timeoutMs,
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
      // 未走到响应（网络层/超时）——记传输层失败；已记过的走上面自己的终态
      reqLogEnd(logId, -1, Date.now() - startedAt, httpKitErrorText(e, timeoutSec), '');
    }
    // 原样上抛（ArkTS 严格模式：throw 不接受任意类型值，须断言——arkts-limited-throw）
    throw e as Error;
  } finally {
    // destroy 包 try：裸 destroy 抛错会从 finally 穿出，把已拿到的结果改写成一次失败
    //（调用方 catch 到的是 destroy 的错，与真实成败无关）
    try {
      req.destroy();
    } catch (e) {
    }
  }
}

// Bing 反指纹请求头（鸿蒙 http kit 对 brotli 解码不稳，显式压到 gzip/deflate；Referer+
// Cookie 过基础机检；UA 恒浏览器身份不吃全局值）
function bingHeaders(): Record<string, string> {
  const headers: Record<string, string> = {};
  headers['User-Agent'] = BROWSER_UA;
  headers['Referer'] = 'https://www.bing.com/';
  headers['Cookie'] = 'SRCHHPGUSR=ULSR=1';
  headers['Accept-Encoding'] = 'gzip, deflate';
  headers['Accept-Charset'] = 'utf-8';
  return headers;
}

// 引文模型回传串组装（contentForAI：编号 + 标题 + URL + 摘要，编号与引文卡 index 对齐；
// 模型据 description 里的引用规范以 Markdown 链接引用）。★ 导出：API 引擎
//（ApiSearchEngines）与 Bing local 共用同一组装口径，零双源
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

// Bing 搜索（主域失败或零结果重试 cn.bing.com 备用入口；两入口都解析失败返回主域失败
// 结果，错误信息进 errorMessage 不静默）。baseUrl 可选参：不传/空串 = www/cn 双入口
// 零回归；传入 = 用户自定义单入口（国内中转逃生门——失败不回落官方域，改址即全量改道）。
// maxCount 参：调用方（ApiSearchEngines.bingLocalSearch）传本次生效条数（来源 = 全局键
// prefSearchResultCount）；不传 = 默认 5（非会话路径调用零回归）
export async function searchBing(query: string, baseUrl?: string,
  maxCount: number = SEARCH_RESULT_COUNT_DEFAULT): Promise<WebSearchOutcome> {
  const encoded: string = encodeURIComponent(query);
  const custom: string = baseUrl !== undefined ? baseUrl.trim().replace(/\/+$/, '') : '';
  // 本次调用（含两入口）的超时快照——计时与失败文案同吃这一份（见文件头「用法契约」）
  const timeoutSec: number = searchTimeoutSeconds();
  if (custom !== '') {
    // 自定义入口失败不回落官方域（改址语义 = 全量改道；失败原样上报）
    try {
      return await bingSearchByUrl(`${custom}/search?q=${encoded}`, query, maxCount, timeoutSec);
    } catch (e) {
      return failedSearch(query, httpKitErrorText(e, timeoutSec));
    }
  }
  try {
    const primary: WebSearchOutcome =
      await bingSearchByUrl(`https://www.bing.com/search?q=${encoded}&setlang=zh-hans`, query,
        maxCount, timeoutSec);
    if (primary.success && primary.references.length > 0) {
      return primary;
    }
    const fallback: WebSearchOutcome =
      await bingSearchByUrl(`https://cn.bing.com/search?q=${encoded}`, query, maxCount, timeoutSec);
    if (fallback.success && fallback.references.length > 0) {
      return fallback;
    }
    return primary.success ? primary : fallback;
  } catch (e) {
    return failedSearch(query, httpKitErrorText(e, timeoutSec));
  }
}

// 单入口执行：请求 + 解析（非 200 由 httpGet 抛错转失败——不静默）
async function bingSearchByUrl(searchUrl: string, query: string,
  maxCount: number, timeoutSec: number): Promise<WebSearchOutcome> {
  let html: string = '';
  try {
    html = await httpGet(searchUrl, bingHeaders(), '联网搜索', timeoutSec);
  } catch (e) {
    return failedSearch(query, httpKitErrorText(e, timeoutSec));
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

// 网页本地抓取（Bing 模式无 API 抓取引擎，恒走本地 HTML 解析；正文总量上限走解析层形参，
// 2026-11-01 分页续读笔起传 SCRAPE_TOTAL_MAX_CHARS=32768——旧 8000 截断使长文贴溢出线
// 触发落盘，改由执行器分页承接；缺省 8000 保留给未来其他调用方）。
// ★ 本函数仍是抓取终态兜底（免费零配置），入口由注册表 dispatchScrape 按偏好选择引擎；
// 四条返回路径全部标 searchEngine = 'url_fetch'
export async function fetchUrlContent(rawUrl: string): Promise<WebFetchOutcome> {
  const url: string =
    rawUrl.startsWith('http://') || rawUrl.startsWith('https://') ? rawUrl : 'https://' + rawUrl;
  if (!isValidUrl(url)) {
    return { success: false, url: url, title: '', content: '', searchEngine: 'url_fetch',
      errorMessage: 'URL 格式无效' + FETCH_FALLBACK_HINT };
  }
  let html: string = '';
  // 本次抓取的超时快照（见文件头「用法契约」）
  const timeoutSec: number = searchTimeoutSeconds();
  try {
    // 请求 URL 编码（B7）：仅含非 ASCII 才 encodeURI；展示面 out.url 保持原串。★ encodeURI
    // 对既有 %XX 段的 `%` 二次转义（→ %25）以 .replace(/%25/g, '%') 还原（对 %20 / 裸 %
    // / 字面 %25 三形态实测零改写）；与 providers/ToolHttp 同口径（注释互指，改则同改）
    const requestUrl: string = /[^\x00-\x7F]/.test(url) ? encodeURI(url).replace(/%25/g, '%') : url;
    // 头表带浏览器 UA（恒浏览器身份不吃全局值，见 BROWSER_UA 注释）
    html = await httpGet(requestUrl, { 'User-Agent': BROWSER_UA }, '网页抓取', timeoutSec);
  } catch (e) {
    return { success: false, url: url, title: '', content: '', searchEngine: 'url_fetch',
      errorMessage: httpKitErrorText(e, timeoutSec) + FETCH_FALLBACK_HINT };
  }
  const parsed: HtmlContent = parseHtmlContent(html, SCRAPE_TOTAL_MAX_CHARS);
  if (parsed.content.trim() === '') {
    return { success: false, url: url, title: parsed.title, content: '',
      searchEngine: 'url_fetch', errorMessage: '未提取到网页正文' };
  }
  return { success: true, url: url, title: parsed.title, content: parsed.content,
    searchEngine: 'url_fetch', errorMessage: '' };
}
