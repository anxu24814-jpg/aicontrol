// 联网搜索双执行器域（2026-10-03 任务书-工作区文件编辑工具 S0 前置拆件自 ToolTypes.ets
// 整段外迁）：SearchWebExecutor（联网搜索）+ ScrapeWebExecutor（读取网页）两执行器与
// 搜索类工具结果统一 JSON 载荷两接口（SearchResultItemPayload / SearchResultOutputPayload）。
// · 为什么外迁（宪法 1200 硬线前置拆件）：ToolTypes 剔头 1194 行，workspace_edit 注册面
//   追加必越线——按「对越线文件的实质改动须先把本次改动所属功能域拆到独立件再动手」先拆
//   本域（债务档一千零三十三节既列候选缝）；方法体原样搬迁零改动，行为等价 = 搬迁前后
//   PASS 名全集逐字比对（宪法「脚本例外与拆分触发线」条同口径）。
// · 依赖方向：本件 → 叶子 ToolContracts（ToolExecutor / toolArgsParseErrorText——坑50 纪律，
//   禁从聚合根 ToolTypes 引）+ WebSearch / SearchEngineRegistry / SearchQueryClean 三件
//   （联网域既有实现单源）；ToolTypes 单向引本件两执行器，本件不引 ToolTypes，无环。
// · 消费方：ToolTypes（注册块装配两执行器）+ ChatToolCard（SearchResultItemPayload——
//   引文卡回放解析）。
// ★ 2026-11-01 分页续读笔（方向拍板 = Kelivo fetch_url 同思路）：scrape_web 超长正文不再
//   整体进载荷（转义膨胀常贴溢出线触发「落临时区 + 信封」，而读回工具 exec_output_read
//   默认关 = 多数助手读不回）——改「首段直返 + nextOffset 续读」：schema 加 offset 形参，
//   模型带上一段回执的 nextOffset 翻页；URL 内存缓存使翻页不重抓网络。搜索载荷恒在场由
//   ToolClip.clipSearchPayload 第二级保底承接（同笔）。
import { ToolExecutor, toolArgsParseErrorText } from './ToolContracts';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { WebFetchOutcome, WebSearchOutcome } from './WebSearch';
import { dispatchScrape, dispatchSearch } from '../search/SearchEngineRegistry';
import { cleanSearchQuery, normalizeRelativeTime } from '../search/SearchQueryClean';
import { SCRAPE_TOTAL_MAX_CHARS, ScrapePageSlice, capScrapeContent,
  scrapePageSlice } from './WebSearchParse';

// 搜索类工具结果统一 JSON 载荷（Cube SearchResultOutput 同构——results[].index 供引文卡
// 编号与模型引用对齐，id 供引擎侧去重/对齐；执行结果 role='tool' 行即此串，引文卡回放
// 时按工具名二次解析）
export interface SearchResultItemPayload {
  index: number;
  id: string;
  title: string;
  url: string;
  snippet: string;
}

interface SearchResultOutputPayload {
  query: string;
  searchEngine: string;
  results: SearchResultItemPayload[];
  summary: string;
  // 分页续读笔（scrape_web 专用，search_web 不填）：totalLength = 总量截断后的可读正文
  // 字符数；nextOffset = 下一段起点，缺省 = 已读尽。与 ToolTypes 注册块 desc 教学同笔对应
  totalLength?: number;
  nextOffset?: number;
}

// 联网搜索执行器（2026-09-03 第三批①，Cube BuiltinTools SearchWebExecutor 同构；
// ★ 2026-09-10 多引擎一期改分发）：query 空守卫 → query 加工（cleanSearchQuery 口语前缀
// 清洗 + normalizeRelativeTime 新闻意图相对时间归一，SearchQueryClean.ets 纯函数）→
// dispatchSearch 注册表编排（读偏好 → fallback 解析 → Asset 取钥 → 引擎 handler 分发，
// common/search/SearchEngineRegistry.ets）——执行器壳只管载荷组装与终态语义：
// · 缺 key / 配额错 → error 文案带配置路径（注册表编排层产）+ description 已声明勿重试；
// · 零结果 → results:[] + summary 明确「未返回结果」语义（优化候选 A3 销账，变更记录
//   1304 行在案）——不再静默空载荷让模型猜。
// 引擎与 key 配置 = 设置 → 工具调用 → 联网搜索（SearchEnginePage）；description 引用规范原文不动
class SearchWebExecutor implements ToolExecutor {
  execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let query: string = '';
    try {
      const parsed = JSON.parse(argsJson) as Record<string, Object>;
      const raw = parsed['query'];
      if (typeof raw === 'string') {
        query = raw.trim();
      }
    } catch (e) {
      return Promise.resolve(JSON.stringify({ error: toolArgsParseErrorText(argsJson) }));
    }
    if (query === '') {
      return Promise.resolve(JSON.stringify({ error: '搜索关键词不能为空' }));
    }
    const normalized: string = normalizeRelativeTime(cleanSearchQuery(query), new Date());
    return dispatchSearch(normalized, ctx.searchResultCount).then((out: WebSearchOutcome): string => {
      if (!out.success) {
        return JSON.stringify({ error: out.errorMessage });
      }
      const payload: SearchResultOutputPayload = {
        query: out.query, searchEngine: out.searchEngine,
        results: out.references,
        summary: out.references.length === 0 ?
          '本次搜索未返回任何结果。请更换更具体的关键词或改用自己的知识回答，不要用同一关键词重复搜索。' :
          out.contentForAI
      };
      return JSON.stringify(payload);
    });
  }
}

// ── scrape_web 分页续读（2026-11-01 分页续读笔；Kelivo fetch_url 同思路）──
// · 形制：首段（≤8192 预算）直返 + totalLength + nextOffset，模型带 offset 翻页续读；
//   nextOffset 缺省 = 读尽。offset 越界（超过总量）回明确错误，模型自纠不猜。
// · 段长预算：转义后整载荷 ≤ 8192 为硬线（与 ToolClip.TOOL_RESULT_SPILL_THRESHOLD 同值
//   双写——按既有惯例工具域按线自算不引 ToolClip，改线两处同改）；首选段长 6000 字符，
//   超预算按 95% 收敛，收敛到下限仍超交外层结构化截断兜底（恒 ≤8192）。
// · 缓存：翻页命中不重抓网络（P1-3 零冗余；Kelivo 同思路）。有界三防 = TTL 10 分钟 +
//   容量 4 + 插入时清过期与最旧，无监听器无泄漏面（内存与资源红线自检：成对无、有界有）。
interface ScrapeCacheEntry {
  title: string;
  content: string;
  engine: string;
  cachedAt: number;
}

const SCRAPE_CACHE_TTL_MS: number = 10 * 60 * 1000;
const SCRAPE_CACHE_CAPACITY: number = 4;
const SCRAPE_PAGE_BUDGET_CHARS: number = 6000;
const SCRAPE_PAGE_MIN_CHARS: number = 1000;
// 与 ToolClip.TOOL_RESULT_SPILL_THRESHOLD 同值双写（溢出线；改线两处同改）
const SCRAPE_PAYLOAD_SAFE_CHARS: number = 8192;

const scrapeCache: Map<string, ScrapeCacheEntry> = new Map();

function scrapeCacheGet(key: string): ScrapeCacheEntry | undefined {
  const hit: ScrapeCacheEntry | undefined = scrapeCache.get(key);
  if (hit === undefined) {
    return undefined;
  }
  if (Date.now() - hit.cachedAt > SCRAPE_CACHE_TTL_MS) {
    scrapeCache.delete(key);
    return undefined;
  }
  return hit;
}

function scrapeCachePut(key: string, entry: ScrapeCacheEntry): void {
  const now: number = Date.now();
  for (const k of Array.from(scrapeCache.keys())) {
    const e: ScrapeCacheEntry | undefined = scrapeCache.get(k);
    if (e !== undefined && now - e.cachedAt > SCRAPE_CACHE_TTL_MS) {
      scrapeCache.delete(k);
    }
  }
  while (scrapeCache.size >= SCRAPE_CACHE_CAPACITY) {
    const oldest: string | undefined = Array.from(scrapeCache.keys())[0];
    if (oldest === undefined) {
      break;
    }
    scrapeCache.delete(oldest);
  }
  scrapeCache.set(key, entry);
}

// 结果 id 按 URL 派生（djb2 变体）：同 URL 跨页同 id，引用锚点不漂移（时间戳 id 每次调用
// 都变——旧形制在分页形制下会让同一页的多段拿到不同 id）
function scrapeRefId(url: string): string {
  let hash: number = 5381;
  for (let i = 0; i < url.length; i++) {
    hash = ((hash << 5) + hash + url.charCodeAt(i)) | 0;
  }
  return 'ref_' + (hash >>> 0).toString(36);
}

// 组装单段回执：results[0].snippet 取本段压缩摘要（引文卡数据源），summary = 头部 + 本段
// 正文；nextOffset ≥ 0 才写该字段（读尽不带）
function buildScrapePayload(out: WebFetchOutcome, sliceText: string, totalLength: number,
  nextOffset: number): string {
  const item: SearchResultItemPayload = {
    index: 1, id: scrapeRefId(out.url), title: out.title, url: out.url,
    snippet: sliceText.replace(/\s+/g, ' ').trim().substring(0, 200)
  };
  const payload: SearchResultOutputPayload = {
    query: out.url, searchEngine: out.searchEngine, results: [item],
    summary: `标题: ${out.title}\n来源: ${out.url}\n\n${sliceText}`,
    totalLength: totalLength
  };
  if (nextOffset >= 0) {
    payload.nextOffset = nextOffset;
  }
  return JSON.stringify(payload);
}

// 网页读取执行器（Cube ScrapeWebExecutor 同构；query 兼容键 = 模型传参脏的防御，
// Cube :160 同款）。★ 2026-09-11 单向绑定兜底守卫曾在此兜「轮内切开关」与绕过声明过滤
// 的路径（全局总开关一维）；★ 2026-10-01 总开关退役笔：守卫随键删除——声明过滤仍是
// 唯一闸（会话级/助手级两维，ChatSendCtrl.webDomainAllowed 两源合取），全局维已不存在。
// ★ 2026-10-17 联网引擎二期：抓取改经注册表 dispatchScrape（按偏好选引擎、失败回落本地
// fetchUrlContent）；载荷 searchEngine 用实际来源（本地 'url_fetch'/引擎 'xxx_fetch'）
// ★ 2026-11-01 分页续读笔：正文总量截 32768（SCRAPE_TOTAL_MAX_CHARS；引擎通路 DeepSeek
// fetch 与本地抓取链同界——★ 同日自检修复笔：parseDeepseekFetch 旧 8000 截断系盘点遗漏，
// 已改经 capScrapeContent 同界承接）→ 缓存/抓取 → offset 切页 → 段长预算收敛
class ScrapeWebExecutor implements ToolExecutor {
  execute(argsJson: string, _ctx: ToolExecutionContext): Promise<string> {
    let rawUrl: string = '';
    let offset: number = 0;
    try {
      const parsed = JSON.parse(argsJson) as Record<string, Object>;
      const url = parsed['url'];
      const query = parsed['query'];
      if (typeof url === 'string' && url.trim() !== '') {
        rawUrl = url.trim();
      } else if (typeof query === 'string') {
        rawUrl = query.trim();
      }
      const offRaw: Object = parsed['offset'];
      if (typeof offRaw === 'number' && Number.isFinite(offRaw as number) &&
        (offRaw as number) > 0) {
        offset = Math.floor(offRaw as number);
      }
    } catch (e) {
      return Promise.resolve(JSON.stringify({ error: toolArgsParseErrorText(argsJson) }));
    }
    if (rawUrl === '') {
      return Promise.resolve(JSON.stringify({ error: '网页 URL 不能为空' }));
    }
    // 翻页缓存命中不重抓（key = 执行器入参原串 trim，与续读调用传同一 URL 时天然一致；
    // 模型改写 URL 致 miss 时重新抓取再切片，行为仍正确）
    const cached: ScrapeCacheEntry | undefined = scrapeCacheGet(rawUrl);
    let fetched: Promise<WebFetchOutcome>;
    if (cached !== undefined) {
      const replay: WebFetchOutcome = { success: true, url: rawUrl, title: cached.title,
        content: cached.content, searchEngine: cached.engine, errorMessage: '' };
      fetched = Promise.resolve(replay);
    } else {
      fetched = dispatchScrape(rawUrl).then((out: WebFetchOutcome): WebFetchOutcome => {
        if (out.success) {
          scrapeCachePut(rawUrl, { title: out.title, content: out.content,
            engine: out.searchEngine, cachedAt: Date.now() });
        }
        return out;
      });
    }
    return fetched.then((out: WebFetchOutcome): string => {
      if (!out.success) {
        return JSON.stringify({ error: out.errorMessage });
      }
      const capped: string = capScrapeContent(out.content, SCRAPE_TOTAL_MAX_CHARS);
      if (offset >= capped.length) {
        return JSON.stringify({ error: `续读起始位置超出正文长度（共 ${capped.length} 字），请从 0 或按回执 nextOffset 读取` });
      }
      let pageChars: number = SCRAPE_PAGE_BUDGET_CHARS;
      let slice: ScrapePageSlice = scrapePageSlice(capped, offset, pageChars);
      let json: string = buildScrapePayload(out, slice.text, capped.length, slice.nextOffset);
      while (json.length > SCRAPE_PAYLOAD_SAFE_CHARS &&
        slice.text.length > SCRAPE_PAGE_MIN_CHARS) {
        pageChars = Math.floor(pageChars * 0.95);
        slice = scrapePageSlice(capped, offset, pageChars);
        json = buildScrapePayload(out, slice.text, capped.length, slice.nextOffset);
      }
      return json;
    });
  }
}

export { SearchWebExecutor, ScrapeWebExecutor };
