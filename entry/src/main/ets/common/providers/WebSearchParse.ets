// 联网搜索·解析纯函数层（2026-09-03 Cube 吸收第三批①；零 import 可 node 直跑——
// SseParser/ModelRegistry 同款先例，断言脚本 scripts/sse-assert.mjs ㉖/㊿ 组直跑消费）。
// 源自 cubeagent-stream-test（chatcube MIT 快照）services/WebSearchService.ets:1977-2261
// 逐行裁剪移植：Bing 结果页 HTML 双策略解析（b_algo 块正则 → h2 标题链接兜底）+ URL 去重
// + Bing 内部链接过滤 + 本地网页正文抽取（剥 script/style/nav/footer/header 后取 p/h/li/
// td/th/span 块）。传输层在 WebSearch.ets（本文件不含任何网络/API 依赖）。
// ★ 2026-09-21 八百三十八节线性化：块扫描与剥体一律走「线性标签扫描助手」（indexOf 逐段
// 推进，惰性量词零残留）——原惰性正则在未闭合标签连排的脏页上二次方（实测见该节注释）。
// ★ 2026-09-21 八百三十九节自检轮收口：838 的线性化只覆盖「短 head」形态——「同名开标签连排
// 且长距离无 `>`」（每个候选重建整段头）与「长段 `<` 之间无 `>`」（剥标签正则 `/<[^>]+>/g`，
// 838 撤除的 64 KB 窗口原是该路径唯一屏障）仍有二次方；本件剥标签与标题提取一并改逐段推进、
// class 判据回旧口径（详见该节 F1~F4）。**本件解析面全部扫描路径实测曲线线性**（含 5 MB 同形）。
// ★ 2026-09-10 多引擎一期扩面：博查/秘塔/Serper 三家 JSON 响应解析 + 秘塔内嵌错误提取
//（§ 多引擎 JSON 解析节）——传输侧在 common/search/ApiSearchEngines.ets，本文件仍是纯函数。
// ★ 2026-09-21 任务书-联网三件错误语义-20260921 笔 A：本件兼载网络层错误文案（HTTP 请求
// 与联网抓取共用一张 http kit 错误码表——见「网络层错误文案」节）。

// 单条搜索结果（index 从 1 起供引文卡编号与模型引用对齐——Cube SearchResultItem 同构；
// id = ref_ 前缀 + 时间戳由执行器生成，解析层不管 id）
export interface BingResultItem {
  index: number;
  id: string;
  title: string;
  url: string;
  snippet: string;
}

// ── 线性标签扫描助手（2026-09-21 八百三十八节线性化）──
// 动机：本件原解析正则一律「惰性量词 + 未闭合起头」找闭合标签，脏页/敌意页（未闭合 <style/
// <p（真实脏页常见形态）/<h2/<li 连排）下按每个起点回溯到串尾 ⇒ 实测二次方：改前剥体
// 400 KB → 2.5 s、正文块 400 KB → 0.9 s、`<li class="b_algo">` 928 KB → 2.5 s、`<h2>`
// 586 KB → 6.1 s、块内 <h2> 600 KB → 16.6 s。输入来自远端站点（http kit 默认 maxLimit
// 5 MB）而本件跑在工具链主线程 ⇒ 无界时最坏分钟级冻结。改用 indexOf 逐段推进：每个候选
// 要么命中（游标跳过整段）要么**终局**（同名更晚候选的闭合标签必然更靠后 ⇒ 同样没有）⇒
// 全串线性。口径与旧正则对齐：开标签取首个 `>`（同旧 `[^>]*` 边界）、闭合标签须 `>` 紧邻、
// `href`/`class` 取开标签内最后一个合法值（同旧正则贪婪回溯结果）。唯一偏离 = **引号值内含
// `>` 的 href**（旧 `([^"']+)` 可跨过该 `>` 取全值，新按首个 `>` 切断 ⇒ 读不到该 href、跳过
// 该候选）；差分对拍 5528 例仅此一类不同，真实页面零差异——见变更记录八百三十八节。

const CHAR_CODE_LT: number = 60;
const CHAR_CODE_GT: number = 62;
const CHAR_CODE_DQUOTE: number = 34;
const CHAR_CODE_SQUOTE: number = 39;

// ASCII 大写折小写（标签名与属性名只有 ASCII；非 A-Z 原样返回）
function foldAsciiLower(code: number): number {
  return code >= 65 && code <= 90 ? code + 32 : code;
}

// 大小写不敏感 indexOf（needle 须已小写）。首字符 `<` 走原生 indexOf 跳跃——本件全部标签
// 查找都是 `<…` 形；逐位折半比较只用于短开标签内的 `href=`/`class=`（长度有界）。
function indexOfIgnoreCase(text: string, lowerNeedle: string, from: number): number {
  const n: number = text.length;
  const m: number = lowerNeedle.length;
  let i: number = from > 0 ? from : 0;
  if (m === 0) {
    return i <= n ? i : -1;
  }
  const head: number = lowerNeedle.charCodeAt(0);
  const jump: boolean = head === CHAR_CODE_LT;
  while (i + m <= n) {
    if (jump) {
      i = text.indexOf('<', i);
      if (i < 0 || i + m > n) {
        return -1;
      }
    } else if (foldAsciiLower(text.charCodeAt(i)) !== head) {
      i++;
      continue;
    }
    let k: number = 1;
    while (k < m && foldAsciiLower(text.charCodeAt(i + k)) === lowerNeedle.charCodeAt(k)) {
      k++;
    }
    if (k === m) {
      return i;
    }
    i++;
  }
  return -1;
}

// `</name` 之后紧邻 `>` 的位置（等价旧正则字面量 `<\/name>`：`</namex>` 不算）；-1 = 其后无
function findCloseTagEnd(text: string, lowerClosePrefix: string, from: number): number {
  let at: number = indexOfIgnoreCase(text, lowerClosePrefix, from);
  while (at >= 0) {
    const end: number = at + lowerClosePrefix.length;
    if (text.charCodeAt(end) === CHAR_CODE_GT) {
      return end;
    }
    at = indexOfIgnoreCase(text, lowerClosePrefix, end);
  }
  return -1;
}

// 标签块命中：开标签文本 / 块体（等价旧正则 group 1）/ 闭合标签 `>`（下次扫描从 tagEnd + 1
// 起，同旧正则 lastIndex 口径）
interface TagBlock {
  start: number;
  head: string;
  body: string;
  tagEnd: number;
}

// 下一处 `<name …>…</name>` 块（headOk 非空时开标签须使其为真，假则只跳该候选）。返回 null
// = 终局：其后没有该开标签、开标签无收尾 `>`、或其后无该闭合标签——三者任一都意味着更晚的
// 同名候选同样不成 match，调用方据此结束循环即可（这是线性的根据）。
function nextTagBlock(text: string, lowerName: string, from: number,
  headOk: ((head: string) => boolean) | null): TagBlock | null {
  const open: string = '<' + lowerName;
  const close: string = '</' + lowerName;
  let cursor: number = from;
  while (true) {
    const start: number = indexOfIgnoreCase(text, open, cursor);
    if (start < 0) {
      return null;
    }
    const headEnd: number = text.indexOf('>', start + open.length);
    if (headEnd < 0) {
      return null;
    }
    const head: string = text.substring(start, headEnd + 1);
    if (headOk !== null && !headOk(head)) {
      // 跳过头区间内的同名候选（★ 八百三十九节自检轮补：原为 `start + open.length` 逐个重扫，
      // 该头区间内每个候选都要重建整段头并重跑 headOk ⇒ 「同名开标签连排且长距离无 `>`」时
      // 二次方，实测 `<li class="x"` 连排 508 KB → 26 s）。可跳的根据 = 这些候选的开标签头与
      // 本头**共用一个收尾 `>`**（区间内无 `>`）⇒ 其头是本头的后缀子串；而 class 判据是
      // 「存在含 token 的合法值」，随头收缩单调不增 ⇒ 本头判假则它们必假。跳过点取
      // `headEnd - open.length + 1`（第一个可能越过该 `>` 的起点，不越界者一个不漏）。
      cursor = headEnd - open.length + 1;
      continue;
    }
    const tailEnd: number = findCloseTagEnd(text, close, headEnd + 1);
    if (tailEnd < 0) {
      return null;
    }
    return { start: start, head: head, body: text.substring(headEnd + 1, tailEnd - close.length),
      tagEnd: tailEnd };
  }
}

// 剥 `<name …>…</name>` 整体（含首尾标签），等价 /<name[^>]*>[\s\S]*?<\/name>/gi 但线性
function stripTagPairs(text: string, lowerName: string): string {
  const open: string = '<' + lowerName;
  const close: string = '</' + lowerName;
  let kept: string = '';
  let cursor: number = 0;
  while (true) {
    const start: number = indexOfIgnoreCase(text, open, cursor);
    if (start < 0) {
      break;
    }
    const headEnd: number = text.indexOf('>', start + open.length);
    if (headEnd < 0) {
      break;
    }
    const tailEnd: number = findCloseTagEnd(text, close, headEnd + 1);
    if (tailEnd < 0) {
      break;
    }
    kept += text.substring(cursor, start);
    cursor = tailEnd + 1;
  }
  return cursor === 0 ? text : kept + text.substring(cursor);
}

// 正文块标签名（旧正则 `<(p|h[1-6]|li|td|th|span)` 的捕获名集合；彼此无前缀冲突，顺序不影响
// 结果）。`<` 后无词边界——`<piano>` 按 `p` 收，与旧正则同。
const CONTENT_TAG_NAMES: string[] = ['p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'td', 'th', 'span'];

// `lt` 处（`<`）之后的名单标签名（'' = 非名单标签）
function contentTagNameAt(html: string, lt: number): string {
  for (const name of CONTENT_TAG_NAMES) {
    const end: number = lt + 1 + name.length;
    if (end > html.length) {
      continue;
    }
    let hit: boolean = true;
    for (let k: number = 0; k < name.length; k++) {
      if (foldAsciiLower(html.charCodeAt(lt + 1 + k)) !== name.charCodeAt(k)) {
        hit = false;
        break;
      }
    }
    if (hit) {
      return name;
    }
  }
  return '';
}

// 正文块整段收集（含首尾标签——下游 stripHtmlTags 同源，等价旧正则全量 match）。逐 `<` 候选：
// 名单名命中 → 找同名闭合标签；某名字已确认「此后无闭合」（noCloseFrom 标记）时跳过后续同名
// 前缀候选 ⇒ 每个名字最多一次全串失败扫描，整体线性。
function collectContentSegments(html: string): string[] {
  const segments: string[] = [];
  const noCloseFrom: Map<string, number> = new Map();
  // ★ 八百三十九节自检轮补：`>` 位置缓存——同一「无 `>` 区间」内的后续候选直接复用该位置，
  // 免去每个候选再扫一遍到远处的那个 `>`（原为逐候选 `indexOf('>', …)`：「同名开标签连排且
  // 长距离无 `>`」时二次方，实测 `<p` 连排 78 KB → 24 ms，同形外推 5 MB 已到百秒级）。
  // 可复用条件 = 本次查询起点不早于上次查询起点、且不越过上次结果（⇒ 该区间内无 `>`）。
  let gtAt: number = -1;
  let gtFrom: number = 0;
  let cursor: number = 0;
  while (cursor < html.length) {
    const lt: number = html.indexOf('<', cursor);
    if (lt < 0) {
      break;
    }
    const name: string = contentTagNameAt(html, lt);
    if (name === '') {
      cursor = lt + 1;
      continue;
    }
    const queryAt: number = lt + 1 + name.length;
    let headEnd: number = -1;
    if (gtAt >= 0 && queryAt >= gtFrom && queryAt <= gtAt) {
      headEnd = gtAt;
    } else {
      headEnd = html.indexOf('>', queryAt);
      gtAt = headEnd;
      gtFrom = queryAt;
    }
    if (headEnd < 0) {
      break;
    }
    const scannedFrom: number | undefined = noCloseFrom.get(name);
    if (scannedFrom !== undefined && scannedFrom <= headEnd + 1) {
      cursor = lt + 1;
      continue;
    }
    const tailEnd: number = findCloseTagEnd(html, '</' + name, headEnd + 1);
    if (tailEnd < 0) {
      noCloseFrom.set(name, headEnd + 1);
      cursor = lt + 1;
      continue;
    }
    segments.push(html.substring(lt, tailEnd + 1));
    cursor = tailEnd + 1;
  }
  return segments;
}

// 首个引号（任一）位置（旧模式 `[^"']+` 的收尾口径）；-1 = 无
function findQuoteEnd(text: string, from: number): number {
  for (let i: number = from; i < text.length; i++) {
    const code: number = text.charCodeAt(i);
    if (code === CHAR_CODE_DQUOTE || code === CHAR_CODE_SQUOTE) {
      return i;
    }
  }
  return -1;
}

// 开标签内 `href=` 的最后一个合法引号值（'' = 无）。等价旧正则 `<a[^>]*href=["']([^"']+)["']`
// ——贪婪 `[^>]*` 回溯 = 取最右一个可成立的 `href=`（浏览器口径是取第一个，此处沿用 Cube 原样，
// 不为线性化顺手改语义）；值取到其后的首个引号且不可为空（`[^"']+` 口径）。
function readHrefValue(head: string): string {
  let value: string = '';
  let at: number = indexOfIgnoreCase(head, 'href=', 0);
  while (at >= 0) {
    const quoteAt: number = at + 5;
    const code: number = head.charCodeAt(quoteAt);
    if (code === CHAR_CODE_DQUOTE || code === CHAR_CODE_SQUOTE) {
      const end: number = findQuoteEnd(head, quoteAt + 1);
      if (end > quoteAt + 1) {
        value = head.substring(quoteAt + 1, end);
      }
    }
    at = indexOfIgnoreCase(head, 'href=', at + 5);
  }
  return value;
}

// 开标签含合法 href（`<a …>` 候选过滤用）
function headHasHref(head: string): boolean {
  return readHrefValue(head) !== '';
}

// 开标签 class 属性值含 token（大小写不敏感——旧模式 `[^"']*token[^"']*` 的「值内包含」口径）。
// ★ 八百三十九节自检轮修正：命中判据 = **任一**合法 class= 的值内含 token（旧正则 `[^>]*class=…`
// 的贪婪回溯是「存在」语义——先试最右一个、不成立再回溯到更早的）。原实现每轮覆盖 `hit`，
// 变成「只看最后一个」：末位 class= 不含 token 而更早的含时（如 `class="b_algo" class="other"`）
// 旧真新假，与「逐段对齐」声明分歧（差分对拍 12 例实锤，见该节 F2）。
function headHasClassToken(head: string, lowerToken: string): boolean {
  let hit: boolean = false;
  let at: number = indexOfIgnoreCase(head, 'class=', 0);
  while (at >= 0) {
    const quoteAt: number = at + 6;
    const code: number = head.charCodeAt(quoteAt);
    if (code === CHAR_CODE_DQUOTE || code === CHAR_CODE_SQUOTE) {
      const end: number = findQuoteEnd(head, quoteAt + 1);
      if (end > quoteAt + 1 &&
        head.substring(quoteAt + 1, end).toLowerCase().includes(lowerToken)) {
        hit = true;
      }
    }
    at = indexOfIgnoreCase(head, 'class=', at + 6);
  }
  return hit;
}

function headHasBAlgoClass(head: string): boolean {
  return headHasClassToken(head, 'b_algo');
}

function headHasBCaptionClass(head: string): boolean {
  return headHasClassToken(head, 'b_caption');
}

// Bing 结果页解析（多策略：b_algo 块优先，不足 maxCount 用 h2 链接兜底补齐；
// 全程 URL 去重。Cube parseBingSearchResults:1978-1988 同构）
export function parseBingSearchResults(html: string, maxCount: number): BingResultItem[] {
  const results: BingResultItem[] = [];
  const seenUrls: Map<string, boolean> = new Map();
  collectResultsFromBAlgoBlocks(html, maxCount, results, seenUrls);
  if (results.length < maxCount) {
    collectResultsFromHeadingLinks(html, maxCount, results, seenUrls);
  }
  return results;
}

// 策略一：b_algo 结果块（Cube collectResultsFromBAlgoBlocks:1990-2011 逐行移植；
// ★ 八百三十八节线性化：原惰性正则逐块扫描，未闭合 b_algo 开标签连排时二次方）
function collectResultsFromBAlgoBlocks(html: string, maxCount: number,
  output: BingResultItem[], seenUrls: Map<string, boolean>): void {
  let cursor: number = 0;
  while (output.length < maxCount) {
    const hit: TagBlock | null = nextTagBlock(html, 'li', cursor, headHasBAlgoClass);
    if (hit === null) {
      break;
    }
    cursor = hit.tagEnd + 1;
    const parsed: BingResultItem | null = parseResultFromBlock(hit.body, output.length + 1);
    if (parsed !== null && !seenUrls.has(parsed.url.trim())) {
      seenUrls.set(parsed.url.trim(), true);
      output.push(parsed);
    }
  }
}

// 策略二：h2 标题链接兜底（Cube collectResultsFromHeadingLinks:2013-2037；摘要取命中
// 位置附近 1000 字符内首个 p 块）。★ 八百三十八节线性化：原惰性正则遇未闭合 <h2 连排
// 二次方。口径按旧正则逐段对齐（链接不受 h2 边界约束、闭合 `</h2>` 取链接之后首个；两处
// 取不到都是终局——更晚候选的链接与其闭合必然更靠后，同旧正则同样不成 match）。
function collectResultsFromHeadingLinks(html: string, maxCount: number,
  output: BingResultItem[], seenUrls: Map<string, boolean>): void {
  const h2OpenLen: number = 3;
  let cursor: number = 0;
  while (output.length < maxCount) {
    const h2Start: number = indexOfIgnoreCase(html, '<h2', cursor);
    if (h2Start < 0) {
      break;
    }
    const h2HeadEnd: number = html.indexOf('>', h2Start + h2OpenLen);
    if (h2HeadEnd < 0) {
      break;
    }
    const link: TagBlock | null = nextTagBlock(html, 'a', h2HeadEnd + 1, headHasHref);
    if (link === null) {
      break;
    }
    const h2End: number = findCloseTagEnd(html, '</h2', link.tagEnd + 1);
    if (h2End < 0) {
      break;
    }
    cursor = h2End + 1;
    const url: string = readHrefValue(link.head);
    const title: string = stripHtmlTags(link.body).trim();
    if (title !== '' && !isBingInternalUrl(url) && !seenUrls.has(url.trim())) {
      seenUrls.set(url.trim(), true);
      output.push({
        index: output.length + 1, id: '', title: title, url: url.trim(),
        snippet: extractSnippetNearMatch(html, h2Start)
      });
    }
  }
}

// 单块解析：h2 内 a 链接 = 标题 + URL，b_caption p / 任意 p = 摘要
//（Cube parseResultFromBlock:2039-2064 同构；★ 八百三十八节线性化，摘要段口径注 =
// 「b_caption 之后的 p」须在该 div 内，旧正则可取到 div 外的 p，真实结果页两口径一致）
function parseResultFromBlock(block: string, index: number): BingResultItem | null {
  const heading: TagBlock | null = nextTagBlock(block, 'h2', 0, null);
  if (heading === null) {
    return null;
  }
  const link: TagBlock | null = nextTagBlock(heading.body, 'a', 0, headHasHref);
  if (link === null) {
    return null;
  }
  const url: string = readHrefValue(link.head);
  const title: string = stripHtmlTags(link.body).trim();
  if (title === '' || isBingInternalUrl(url)) {
    return null;
  }
  const caption: TagBlock | null = nextTagBlock(block, 'div', 0, headHasBCaptionClass);
  // 摘要 p 的搜索起点 = caption 开标签之后（旧正则 `[\s\S]*?<p…>` 不受 div 边界约束，此处同）
  const captionP: TagBlock | null = caption !== null ?
    nextTagBlock(block, 'p', caption.start + caption.head.length, null) : null;
  if (captionP !== null) {
    const snippet: string = stripHtmlTags(captionP.body).trim();
    return { index: index, id: '', title: title, url: url.trim(), snippet: snippet };
  }
  const anyP: TagBlock | null = nextTagBlock(block, 'p', 0, null);
  const snippet: string = anyP !== null ? stripHtmlTags(anyP.body).trim() : '';
  return { index: index, id: '', title: title, url: url.trim(), snippet: snippet };
}

function extractSnippetNearMatch(html: string, startIndex: number): string {
  const safeStart: number = startIndex >= 0 ? startIndex : 0;
  const segment: string = html.substring(safeStart, Math.min(html.length, safeStart + 1000));
  const snippetP: TagBlock | null = nextTagBlock(segment, 'p', 0, null);
  if (snippetP === null) {
    return '';
  }
  return normalizeSnippet(stripHtmlTags(snippetP.body).trim());
}

// 摘要归一（压空白）；URL 拼接类残留 snipp 无害由展示层截断——保持 Cube 原样仅压缩
function normalizeSnippet(text: string): string {
  return text.replace(/\s+/g, ' ').trim();
}

// Bing 内部链接过滤（搜索页自身的跳转/设置链接不进结果——Cube :2077-2080）
function isBingInternalUrl(url: string): boolean {
  const lower: string = url.toLowerCase();
  return lower.includes('bing.com') || lower.startsWith('/search') || lower.startsWith('/?');
}

// `<…>` 段整体删除（等价旧 `/<[^>]+>/g`，改逐段推进：`<` 之后到首个 `>` 之间**至少 1 字符**
// 才删，空体 `<>` 原样保留——旧 `[^>]+` 要求至少 1 字符）。★ 八百三十九节自检轮补：原正则在
// 「长段 `<` 而其间无 `>`」的输入上按每个起点回溯到串尾 ⇒ 二次方（实测 195 KB → 7.8 s、
// 586 KB → 24 s；该形态经错误页片段链在八百三十八节撤除 64 KB 窗口后**无界**可达 5 MB ⇒
// 分钟级冻结——窗口原是把这条链挡在 64 KB 内的唯一屏障，见该节 F1）。
function stripAngleBracketChunks(text: string): string {
  let kept: string = '';
  let cursor: number = 0;
  while (true) {
    const lt: number = text.indexOf('<', cursor);
    if (lt < 0) {
      break;
    }
    const gt: number = text.indexOf('>', lt + 1);
    if (gt < 0) {
      break;
    }
    kept += gt > lt + 1 ? text.substring(cursor, lt) : text.substring(cursor, gt + 1);
    cursor = gt + 1;
  }
  return cursor === 0 ? text : kept + text.substring(cursor);
}

// HTML 标签剥除 + 实体反转义（Cube stripHtmlTags:2083-2094 移植；★ 2026-09-03 技能
// 实测轮修复：&amp; 挪到最后一次替换——原序（&amp; 在前）会把双重转义串链式解两层
//（&amp;lt; → &lt; → <，实测实锤）；&amp; 收尾 = 双重转义只解一层，单转义行为不变
//〔&amp; 单独出现仍解为 &、&lt; 仍解为 <〕，与 Cube 此处系同源瑕疵的有意偏离。
// ★ 八百三十九节自检轮：标签剥除改走 `stripAngleBracketChunks`（线性；口径逐字对齐旧正则））
export function stripHtmlTags(text: string): string {
  return stripAngleBracketChunks(text)
    .replace(/&nbsp;/g, ' ')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, '&')
    .replace(/\s+/g, ' ')
    .trim();
}

// ── 网页正文抽取（scrape_web 本地抓取的解析侧；Cube parseHtmlContent:2191-2236）──

export interface HtmlContent {
  title: string;
  content: string;
}

// 剥 script/style/nav/footer/header 后取 p/h1-6/li/td/th/span 块文本，>10 字符或含
// 数值/单位特征才收（Cube 同过滤）；全量 8000 字符截断（有界红线）。
// ★ 八百三十八节线性化：剥体与正文块收集改走本件线性扫描助手（原 6 条惰性正则在未闭合
// <style/<p 连排的脏页上二次方）；截尾代价沿用原样（本函数产物本就是「头部正文」）。
const STRIP_PAIR_TAGS: string[] = ['script', 'style', 'nav', 'footer', 'header'];

// 页面标题（等价旧 `/<title[^>]*>([^<]+)<\/title>/i`，改逐段推进）。口径逐条对齐：取首个能配成
// 「`<title…>` + 文本 + `</title>`」的候选（开标签取首个 `>`，同旧 `[^>]*` 边界；文本非空且不含
// `<`，闭合标签须紧邻该 `<` 且 `>` 收尾，同旧 `([^<]+)` 与 `<\/title>`）。null = 未命中，由调用方
// 回落「未知标题」（旧 `([^<]+)` 允许全空白文本 ⇒ 空白标题原样返回空串，故空串与未命中不并档）。
// ★ 八百三十九节自检轮：原正则在「大量 `<title` 连排且长距离无 `>`」时按每个起点回溯到串尾
// ⇒ 二次方（实测 234 KB → 2.6 s），本件输入来自远端站点无界，同法改线性。
function readHtmlTitle(html: string): string | null {
  let at: number = indexOfIgnoreCase(html, '<title', 0);
  while (at >= 0) {
    const headEnd: number = html.indexOf('>', at + 6);
    if (headEnd < 0) {
      return null;
    }
    const textStart: number = headEnd + 1;
    const textEnd: number = html.indexOf('<', textStart);
    if (textEnd < 0) {
      return null;
    }
    if (textEnd > textStart && indexOfIgnoreCase(html, '</title', textEnd) === textEnd &&
      html.charCodeAt(textEnd + 7) === CHAR_CODE_GT) {
      return html.substring(textStart, textEnd).trim();
    }
    at = indexOfIgnoreCase(html, '<title', at + 6);
  }
  return null;
}

export function parseHtmlContent(html: string): HtmlContent {
  const rawTitle: string | null = readHtmlTitle(html);
  const title: string = rawTitle !== null ? rawTitle : '未知标题';

  let cleanHtml: string = html;
  for (const tag of STRIP_PAIR_TAGS) {
    cleanHtml = stripTagPairs(cleanHtml, tag);
  }
  cleanHtml = cleanHtml.replace(/<br\s*\/?>/gi, '\n');

  const parts: string[] = [];
  for (const segment of collectContentSegments(cleanHtml)) {
    const text: string = stripHtmlTags(segment)
      .replace(/\n+/g, '\n')
      .trim();
    if (text.length > 10 || /(℃|°|AQI|PM2\.5|\d+\s*-\s*\d+)/i.test(text)) {
      parts.push(text);
    }
  }
  let content: string = parts.join('\n');
  if (content.length > 8000) {
    content = content.substring(0, 8000) + '...';
  }
  return { title: title, content: content };
}

// URL 格式校验（Cube isValidUrl:2239-2242 原样；★ 2026-09-21 笔 A：path/query 起放行 `%`
// 与非 ASCII——原字符类无 `%` 也无 `\u0080-\uFFFF`，已编码串（/a%20b）与含中文路径·查询串
// 的地址一律被判无效；host 段（[\w\-.]+）仍限 ASCII（IDN 中文域名仍拒——encodeURI 不
// punycode 主机名，放行只会把失败推到更深处）。非 ASCII 编码在请求前做，见 WebSearch）
export function isValidUrl(text: string): boolean {
  const urlPattern: RegExp =
    /^https?:\/\/[\w\-.]+(:\d+)?(\/[\w\-._~:/?#[\]@!$&'()*+,;=%\u0080-\uFFFF]*)?$|^[\w\-.]+(:\d+)?(\/[\w\-._~:/?#[\]@!$&'()*+,;=%\u0080-\uFFFF]*)?$/;
  return urlPattern.test(text.trim());
}

// ── 网络层错误文案（2026-09-21 任务书-联网三件错误语义-20260921 笔 A）──
// 本件原 = 联网搜索解析纯函数（零 import 叶子）。本笔起兼载「http kit 错误码 → 中文原因」：
// 消费方 = providers/ToolHttp（HTTP 请求域）与 providers/WebSearch（联网抓取）——两域共用
// 一张表，禁各写一份（单一来源）；引本件零环风险（本件零 import，坑50）。

// http kit 错误码 → 中文原因（纯函数；未列码返 ''，由 httpKitErrorText 兜底）。
// 码源 = 本地 SDK d.ts `@ohos.net.http.d.ts` 各 request 重载的 @throws 清单。
// timeoutSeconds 只服务 2300028 一句——两消费方超时值不同（HTTP 请求 30s / 抓取 20s），
// 故参数化，禁硬编单值。
export function httpKitErrorMessage(code: number, timeoutSeconds: number = 30): string {
  if (code === 2300001) {
    return '不支持的协议，仅支持 http 与 https 地址';
  }
  if (code === 2300003) {
    return '网址格式无效，无法发出请求';
  }
  if (code === 2300005) {
    return '代理服务器解析失败，请检查代理设置';
  }
  if (code === 2300006) {
    return '域名解析失败，可能是网址拼写有误或当前网络不可用';
  }
  if (code === 2300007) {
    return '无法连接到服务器，可能是对方未响应或网络受限';
  }
  if (code === 2300028) {
    return '请求超时（' + timeoutSeconds + ' 秒）';
  }
  if (code === 2300047) {
    return '重定向次数超过上限，已停止跟随跳转';
  }
  if (code === 2300063) {
    return '响应超过接收上限，未取回正文。可缩小范围后重试';
  }
  if (code === 2300997) {
    return '明文传输被系统策略阻止，该地址不能使用 http 访问';
  }
  if (code === 2300998) {
    return '系统策略不允许访问该域名';
  }
  return '';
}

// 网络层异常 → 中文句（纯函数；四级取句 + 已成型句直返（前置）——①码表命中走表句 ②有码未列
// 有 message 拼码与原因 ③有码未列无 message 只报码 ④无码有 message 拼原因、无 message 只报
// 「网络请求失败」；另见下方「已成型句直返」分支）。
// ★ 本函数的存在理由 = 真机实证缺陷：BusinessError 在 SDK 里是 `interface BusinessError
// extends Error`（@ohos.base.d.ts:129，接口非类），运行时非真 Error 实例 ⇒ 旧实现
// `String(e)` 产出 '[object Object]'、回执成 {"error":"[object Object]"}。此后一律经本函数取句。
export function httpKitErrorText(e: Object, timeoutSeconds: number = 30): string {
  let code: number = -1;
  let msg: string = '';
  if (typeof e === 'object' && e !== null) {
    const rec = e as Record<string, Object>;
    const codeRaw: Object = rec['code'];
    if (typeof codeRaw === 'number') {
      code = codeRaw as number;
    }
    const msgRaw: Object = rec['message'];
    if (typeof msgRaw === 'string' && msgRaw !== '') {
      msg = msgRaw as string;
    }
  } else if (typeof e === 'string') {
    msg = e as string;
  }
  // 非 2xx 句已成型（由本件 httpStatusFailureText 产出，格式首段见 HTTP_STATUS_SENTENCE_PREFIX）
  //——它描述的是「站点已响应但拒绝」，不是网络层异常：套码表或套「网络请求失败：」前缀都错，
  // 故原样返回。识别依据是本件自有常量而非字符串字面量（单源）。
  if (msg.startsWith(HTTP_STATUS_SENTENCE_PREFIX)) {
    return msg;
  }
  if (code >= 0) {
    const mapped: string = httpKitErrorMessage(code, timeoutSeconds);
    if (mapped !== '') {
      return mapped;
    }
    return msg !== '' ? '网络请求失败（码 ' + code + '）：' + msg : '网络请求失败（码 ' + code + '）';
  }
  return msg !== '' ? '网络请求失败：' + msg : '网络请求失败';
}

// 非 2xx 失败句（纯函数）：状态码 + 去标签正文片段（空白归一、截 HTTP_FAILURE_EXCERPT_MAX）。
// 原实现只抛 'HTTP 403'，错误页正文里的原因（拦截/限流/需登录）被丢掉；
// ★ 2026-09-21 C 类清账笔：片段先剥 script/style 正文再剥标签（见下方 stripScriptStyleBodies）。
export const HTTP_FAILURE_EXCERPT_MAX: number = 200;

// 非 2xx 句前缀（单源：本常量既用于组装（httpStatusFailureText），也用于取句侧识别
//（httpKitErrorText 的「已成型句直返」分支）——两处必须是同一个常量，禁各自字面量）
export const HTTP_STATUS_SENTENCE_PREFIX: string = '站点返回 HTTP ';

// 剥 script/style 正文（与上方 parseHtmlContent 的剥体同源，走本件线性助手）：错误页的 CSS 与
// 页面脚本正文通常位于真因**之前**（`<style>` 在 head、脚本常在正文前部），不剥则片段被它们从
// 头部吃掉预算——真因被挤到中段或直接挤出（实测 403 页曾输出「…：p{color:red}Forbiddenvar a=1;」）。
// ★ 只服务错误页片段抽取，**不改 stripHtmlTags 本体**——其标题与摘要五个消费者要保留原语义。
// ★ 八百三十八节：改用线性剥体助手，原 64 KB 扫描窗口随之撤除——那窗口只是「惰性量词遇大量
// 未闭合起头会二次方」的权宜（实测该形态 200 KB→0.54 s / 800 KB→9.0 s），代价是「真因深藏
// 64 KB 之后取不到」；线性化后无窗口也线性（5 MB 同形输入实测 ~30 ms），语义回到「全串找真因」。
function stripScriptStyleBodies(text: string): string {
  return stripTagPairs(stripTagPairs(text, 'script'), 'style');
}

export function httpStatusFailureText(status: number, body: string): string {
  const text: string = stripHtmlTags(stripScriptStyleBodies(body)).replace(/\s+/g, ' ').trim();
  const excerpt: string = text.length > HTTP_FAILURE_EXCERPT_MAX ?
    text.substring(0, HTTP_FAILURE_EXCERPT_MAX) + '…' : text;
  return HTTP_STATUS_SENTENCE_PREFIX + status + (excerpt !== '' ? '：' + excerpt : '');
}

// ── 多引擎 JSON 解析（2026-09-10 多引擎一期；传输侧在 common/search/ApiSearchEngines，
//   本节只做纯解析——样本即规格，断言在 scripts/sse-assert.mjs ㊿ 组）──
// 三家响应结构来源：①调研档 04 卷 §3.6~3.8（官方文档 + 教程交叉）；②2026-09-10 端点
// 实测（无 key 探针拿到的错误形态）；③秘塔 webpages[] 字段名 = Cube 快照
// WebSearchService.parseMetasoSearchResults:777-800 逐字对照（MIT）。

// 从任意 JSON 对象安全读字符串（引擎字段缺省/类型漂移回 ''——多引擎一期统一防御）
function readString(rec: Record<string, Object>, key: string): string {
  const raw: Object | undefined = rec[key];
  return typeof raw === 'string' ? (raw as string).trim() : '';
}

// 逐条收编（title/url 缺一跳过 + 全程 URL 去重——Bing 双策略同款口径，三家共用）
function collectJsonResults(list: object[], maxCount: number,
  titleKey: string, urlKey: string, snippetKeys: string[]): BingResultItem[] {
  const results: BingResultItem[] = [];
  const seenUrls: Map<string, boolean> = new Map();
  for (const item of list) {
    if (results.length >= maxCount) {
      break;
    }
    const rec: Record<string, Object> = item as Record<string, Object>;
    const title: string = readString(rec, titleKey);
    const url: string = readString(rec, urlKey);
    if (title === '' || url === '' || seenUrls.has(url)) {
      continue;
    }
    let snippet: string = '';
    for (const key of snippetKeys) {
      snippet = readString(rec, key);
      if (snippet !== '') {
        break;
      }
    }
    seenUrls.set(url, true);
    results.push({ index: results.length + 1, id: '', title: title, url: url,
      snippet: normalizeSnippet(snippet) });
  }
  return results;
}

// 博查响应解析（Bing 兼容形态：data.webPages.value[]，标题键 name、摘要 snippet 优先
// summary 兜底——官方 AI Search 文档与 LazyLLM 官方 cookbook 请求体对照，调研档 04 §3.8）
export function parseBochaResults(json: string, maxCount: number): BingResultItem[] {
  if (json === '') {
    return [];
  }
  try {
    const parsed = JSON.parse(json) as Record<string, Object>;
    const data: Object | undefined = parsed['data'];
    if (data === undefined || typeof data !== 'object') {
      return [];
    }
    const webPages: Object | undefined = (data as Record<string, Object>)['webPages'];
    if (webPages === undefined || typeof webPages !== 'object') {
      return [];
    }
    const value: Object | undefined = (webPages as Record<string, Object>)['value'];
    if (!Array.isArray(value)) {
      return [];
    }
    return collectJsonResults(value as object[], maxCount, 'name', 'url', ['snippet', 'summary']);
  } catch (e) {
    return [];
  }
}

// 秘塔响应错误提取：★ 秘塔无 key/配额错返回 HTTP 200 + 内嵌 {errCode, errMsg}（2026-09-10
// 端点实测：无 key → 200 + errCode 2005「API密钥无效」）——传输层按非 2xx 抛错抓不到，
// 必须在 200 响应体里先验错误再解析（「HTTP 200 + 内嵌错误」坑，调研档 04 §4.2-6 同族）
export function metasoErrorMessage(json: string): string {
  if (json === '') {
    return '';
  }
  try {
    const parsed = JSON.parse(json) as Record<string, Object>;
    const errCode: Object | undefined = parsed['errCode'];
    if (errCode === undefined) {
      return '';
    }
    const errMsg: string = readString(parsed, 'errMsg');
    return errMsg !== '' ? `秘塔接口错误 ${String(errCode)}：${errMsg}` :
      `秘塔接口错误 ${String(errCode)}`;
  } catch (e) {
    return '';
  }
}

// 秘塔响应解析（webpages[]，标题 title、链接 link、摘要 snippet——Cube 快照 :777-800
// 逐字对照；errCode 形态先经 metasoErrorMessage 排除，正常载荷无该键）
export function parseMetasoResults(json: string, maxCount: number): BingResultItem[] {
  if (json === '') {
    return [];
  }
  try {
    const parsed = JSON.parse(json) as Record<string, Object>;
    const webpages: Object | undefined = parsed['webpages'];
    if (!Array.isArray(webpages)) {
      return [];
    }
    return collectJsonResults(webpages as object[], maxCount, 'title', 'link', ['snippet']);
  } catch (e) {
    return [];
  }
}

// Serper 响应解析（organic[]，标题 title、链接 link、摘要 snippet——官方首页 playground
// 响应示例逐字段核对，调研档 04 §3.6；knowledgeGraph/peopleAlsoAsk 等旁路块不进引文）
export function parseSerperResults(json: string, maxCount: number): BingResultItem[] {
  if (json === '') {
    return [];
  }
  try {
    const parsed = JSON.parse(json) as Record<string, Object>;
    const organic: Object | undefined = parsed['organic'];
    if (!Array.isArray(organic)) {
      return [];
    }
    return collectJsonResults(organic as object[], maxCount, 'title', 'link', ['snippet']);
  } catch (e) {
    return [];
  }
}

// URL 提取与旧 web_search 兼容工具强绑定（Cube extractUrl 仅被 LegacyWebSearchExecutor
// 消费）——aicontrol 无历史包袱不移植旧工具，本函数随旧工具一并裁除（死代码清查结论）。
