// 知识库文本纯函数域：知识库层的纯逻辑——启用清单解析/序列化 / 检索切词 / 打分 / 相关度
// 排序 / 检索与清单拼装 / 列表副行摘要 / 管理面（重名判定与工具回执）/ 条目附件件的校验与
// 读回回执。**零 import 纯函数约束**（照 SkillText.ets / MemoryText.ets——断言脚本复制本
// 文件为 .ts 直跑，是本域可测性的根基；IO 编排在 KnowledgeDb / ToolKnowledge / 各页面）。
//
// ★ 文件导入导出域与审阅弹窗文案域已外迁 common/KnowledgeImportText.ets（新件单向 import
// 本件——本件零 import 约束不破，依赖方向恒「新件 → 本件」，断言直跑面照旧；导入导出域
// 的语义与沿革以新件头注释为源）。
//
// ★ 与相邻两列的语义分界（本域最易被后人按错口径改坏的一点）：assistants.knowledge 的 ''
// = **空集合**（默认不启用任何知识库），与 assistants.skills 同义、与 assistants.tools 的
// 「'' = 默认集合」**相反**。故 parseEnabledKnowledgeIds 与 parseEnabledSkillIds 形态相同但
// **域不同，禁跨域合并复用**（各留一份是有意为之，不是重复代码）。
//
// ★ 首版姿态 = 工具化检索（条目不自动注入，模型经 search_knowledge 按需查阅）：keywords
// 字段**只参与检索加权与展示，不接触发逻辑**——姿态边界非遗漏（关键词自动注入属另一姿态）。

// ── 上限常量族 ──
// 条目名称上限（编辑页 maxLength 与本域同源）。★ **两处同用**：条目名称 + 知识库名称
//（库页命名对话框与 create_book 校验同源）——改本值即多处同动，禁在工具面另写数字
export const KNOWLEDGE_TITLE_MAX: number = 50;
// 关键词上限（纯检索加权与展示字段，不进任何触发判定）
export const KNOWLEDGE_KEYWORDS_MAX: number = 100;
// 条目正文上限（纯文本；< clipToolResult 8192 保证单条不被下游截断）
export const KNOWLEDGE_CONTENT_MAX: number = 6000;
// 工具返回双封顶（宪法「数据有界」：5 条 / 12000 字覆盖典型问询，超出由尾行引导收窄）。
// ★ **实际生效上限 8192**（言行一致，勿误解本档）：工具结果出管线前一律过 clipToolResult
//（8192，ChatToolRoundCtrl 调用点）⇒ 合计超 8K 的多条结果仍会被管线尾部截断。本档是**检索
// 侧预算**（决定哪几条进结果），不是模型面硬顶；单条 6000 字 + 头行恒在线内 ⇒ 单条恒完整送达
export const KNOWLEDGE_TOOL_RESULT_MAX_COUNT: number = 5;
export const KNOWLEDGE_TOOL_RESULT_MAX_CHARS: number = 12000;
// 单条正文字符上限（工具结果里单条正文的截断档），**与 KNOWLEDGE_CONTENT_MAX 同值** ⇒
// 单条恒完整送达（「用户写 2000 字、模型只读到 1200 字」的静默缩水由此消除）。保留本档 =
// 将来再调正文上限时仍有一道「一条不得独占整份结果」的闸
export const KNOWLEDGE_ENTRY_CLIP: number = 6000;
// 列表副行摘要的截断档（行副行单行显示）
const KNOWLEDGE_SUMMARY_MAX: number = 20;

// ── 触发精度常量族与归一 ──
// ★ 常量归属：四常量与两归一函数全落本件——KnowledgeMatch.ets **不持任何默认值常量**，只做
//   下界防御，不存在第二份上限；UI 保存链 / DB 写入 / 导入落库三处共用（禁页面自写第二套钳位）
// 优先级上限（0~9999，数值大的先注入，全局跨书）；默认 100 = 「常规」，同值回落原四键
//（存量顺序零变化）；0 留给「最后注入」的显式意图
export const KNOWLEDGE_PRIORITY_MAX: number = 9999;
export const KNOWLEDGE_PRIORITY_DEFAULT: number = 100;
// 扫描窗口条数上下限与默认（1~20；默认 8 与旧常量同值。上限 20 = 匹配是主线程全量扫描，
// 窗口长度直接乘进比较成本；与注入面 KNOWLEDGE_INJECT_MAX_COUNT 不是一回事）
export const KNOWLEDGE_SCAN_MIN: number = 1;
export const KNOWLEDGE_SCAN_MAX: number = 20;
export const KNOWLEDGE_SCAN_DEFAULT: number = 8;

// 优先级归一：非有限数 / 负数 → 默认 100；超上限钳 9999（空输入由调用方 parseInt 产 NaN，
// 同落默认）。纯函数供 UI / DB 写入 / 导入三处共用
export function clampKnowledgePriority(raw: number): number {
  if (!Number.isFinite(raw)) {
    return KNOWLEDGE_PRIORITY_DEFAULT;
  }
  if (raw < 0) {
    return 0;
  }
  return raw > KNOWLEDGE_PRIORITY_MAX ? KNOWLEDGE_PRIORITY_MAX : raw;
}

// 扫描条数归一：非有限数 → 默认 8；<1 钳 1；>20 钳 20（scanDepth=0 会造出空窗口恒不命中，
// 下界 1 是行为红线）
export function clampKnowledgeScan(raw: number): number {
  if (!Number.isFinite(raw)) {
    return KNOWLEDGE_SCAN_DEFAULT;
  }
  if (raw < KNOWLEDGE_SCAN_MIN) {
    return KNOWLEDGE_SCAN_MIN;
  }
  return raw > KNOWLEDGE_SCAN_MAX ? KNOWLEDGE_SCAN_MAX : raw;
}

// ── list 回执分页两档 + 页内字数软顶 ──
// 本族存在的理由：list 回执原为一次性全量输出——条目行最坏 ≈ 208 字，单库满 100 条 ≈ 20.8K，
// 越过工具结果管线 8192 钳位线 ⇒ 大库回执被尾部截断且无翻页手段（形制照技能/记忆域先例：
// 位次分页 + 页内软顶收窄 + 尾行翻页指引）。30 的依据：30 行 × 208 字 ≈ 6.2K < 8192
export const KNOWLEDGE_LIST_DEFAULT_COUNT: number = 20;
export const KNOWLEDGE_LIST_MAX_COUNT: number = 30;
// 页内总字数软顶（超则自动收窄本页条数至少 1 条，防硬顶截尾丢翻页提示；MAX_COUNT 内最坏
// 6.2K 不触发此线——它是 MAX_COUNT 调大时的结构性兜底）
export const KNOWLEDGE_LIST_PAGE_SOFT_CHARS: number = 6000;

// 命中权重（标题 3 / 关键词 2 / 正文 1——同一 token 在多个字段命中**取最高权重不累加**，
// 不同 token 累加；标题命中是意图最强的信号）
const KNOWLEDGE_WEIGHT_TITLE: number = 3;
const KNOWLEDGE_WEIGHT_KEYWORDS: number = 2;
const KNOWLEDGE_WEIGHT_CONTENT: number = 1;

// 触上限尾行（照 CHAT_SEARCH_CAP_NOTE 同族形态）
const KNOWLEDGE_SEARCH_CAP_NOTE: string = '已达返回上限，可用更具体的关键词再检索。';
// 书名缺失兜底（bookId 在书名单表查不到 = 删库与查询间竞态）——**禁让 undefined/null 上屏**
const KNOWLEDGE_UNKNOWN_BOOK: string = '（未知知识库）';

// 零 import 域不引 DB 类型（SkillText.SkillBriefItem / MemoryManageItem 同款取舍）：
// KnowledgeDb 的 KnowledgeEntryRow / KnowledgeBookRow 结构上兼容本域两形态，调用方零适配直传
export interface KnowledgeEntryItem {
  id: string;
  bookId: string;
  title: string;
  keywords: string;
  content: string;
  createdAt: number;
  sortOrder: number;
  // v51 注入三配置与启用开关——本域打分/拼装不消费，透传给清单页角标与条目卡开关；
  // source 仍刻意不带（边界不变）
  injectRole: string;
  injectPosition: string;
  injectDepth: number;
  enabled: number;
  // 触发精度四字段——检索打分不消费，透传给导出链与导入落库；漏这一层会表现成
  // 「编辑页配好了，导出文件里没有」
  matchCase: number;
  matchWhole: number;
  priority: number;
  scanDepth: number;
}

export interface KnowledgeBookItem {
  id: string;
  name: string;
}

// 启用集解析（assistants.knowledge 列 JSON 串 → id 数组）：'' / 坏 JSON / 非数组 → **空数组**
//（与 skills 列同义、与 tools 列相反）；只收非空字符串项；去重（重复 id 会让启用计数失真）
export function parseEnabledKnowledgeIds(json: string): string[] {
  if (json === '') {
    return [];
  }
  let raw: object[] | null = null;
  try {
    const parsed: object = JSON.parse(json);
    raw = Array.isArray(parsed) ? parsed as object[] : null;
  } catch (e) {
    return [];
  }
  if (raw === null) {
    return [];
  }
  const ids: string[] = [];
  for (const item of raw) {
    if (typeof item === 'string' && item !== '' && !ids.includes(item)) {
      ids.push(item);
    }
  }
  return ids;
}

// id 数组 → JSON 串：空集合落 ''（库列默认形态 = 不启用，新装/新建助手零配置零写入）
export function serializeEnabledKnowledgeIds(ids: string[]): string {
  if (ids.length === 0) {
    return '';
  }
  return JSON.stringify(ids);
}

// 检索切词（照 MemoryText.splitMemoryQuery 先例形态：分隔符整族 + trim + 去重）；
// 额外做 toLowerCase（本域打分大小写不敏感，切词处一次归一避免两处各写一遍）
export function splitKnowledgeQuery(query: string): string[] {
  const tokens: string[] = [];
  const seen: Set<string> = new Set<string>();
  const parts: string[] = query.split(/[\s,.;:!?，。、；：？！…—·\-~～()\[\]{}「」『』“”‘’"\/'\\|]+/)
    .map((p: string): string => p.trim().toLowerCase());
  for (const part of parts) {
    if (part !== '' && !seen.has(part)) {
      seen.add(part);
      tokens.push(part);
    }
  }
  return tokens;
}

// 单条打分：逐 token 查三字段，命中即按**最高权重**加一次（if/else 链 = 不累加的实现，
// 标题命中后不再看关键词与正文）；大小写不敏感（两侧 toLowerCase——英文关键词大小写变体
// 不丢分，与 search_memory / search_chats 两工具口径一致；中文 toLowerCase 无变化）
export function scoreKnowledgeEntry(entry: KnowledgeEntryItem, tokens: string[]): number {
  const title: string = entry.title.toLowerCase();
  const keywords: string = entry.keywords.toLowerCase();
  const content: string = entry.content.toLowerCase();
  let score: number = 0;
  for (const token of tokens) {
    const needle: string = token.toLowerCase();
    if (title.includes(needle)) {
      score += KNOWLEDGE_WEIGHT_TITLE;
    } else if (keywords.includes(needle)) {
      score += KNOWLEDGE_WEIGHT_KEYWORDS;
    } else if (content.includes(needle)) {
      score += KNOWLEDGE_WEIGHT_CONTENT;
    }
  }
  return score;
}

// 相关度选取：打分 > 0 的入候选，按 score 降序 → sortOrder 升序 → createdAt 升序排序。
// ★ 第二三键是**确定性兜底**：并列项不能依赖 SQL 返回序（MemoryDb.queryMemories 三键
// 同精神），否则同一查询在不同设备/不同库状态下命中序会漂。
// limit > 0 = 只回前 limit 条（调用方要硬切时用）；limit ≤ 0 = 回全部候选（工具链传 0——
// 让 composeKnowledgeSearchResult 拿到全集才能据实报「已达返回上限」尾行）
export function selectKnowledgeHits(entries: KnowledgeEntryItem[], query: string,
  limit: number): KnowledgeEntryItem[] {
  const tokens: string[] = splitKnowledgeQuery(query);
  if (tokens.length === 0) {
    return [];
  }
  const scored: KnowledgeEntryItem[] = [];
  const scoreOf: number[] = [];
  for (const entry of entries) {
    const score: number = scoreKnowledgeEntry(entry, tokens);
    if (score > 0) {
      scored.push(entry);
      scoreOf.push(score);
    }
  }
  const order: number[] = [];
  for (let i: number = 0; i < scored.length; i++) {
    order.push(i);
  }
  order.sort((a: number, b: number): number => {
    if (scoreOf[a] !== scoreOf[b]) {
      return scoreOf[b] - scoreOf[a];
    }
    if (scored[a].sortOrder !== scored[b].sortOrder) {
      return scored[a].sortOrder - scored[b].sortOrder;
    }
    return scored[a].createdAt - scored[b].createdAt;
  });
  const ranked: KnowledgeEntryItem[] = [];
  const cap: number = limit > 0 && limit < order.length ? limit : order.length;
  for (let i: number = 0; i < cap; i++) {
    ranked.push(scored[order[i]]);
  }
  return ranked;
}

// 单条正文截断（超 KNOWLEDGE_ENTRY_CLIP 尾部截断加省略号）
function clipEntryBody(content: string): string {
  return content.length > KNOWLEDGE_ENTRY_CLIP ?
    content.substring(0, KNOWLEDGE_ENTRY_CLIP) + '…' : content;
}

// 空白压平成单行（列表副行摘要用——正文含换行会把副行撑成多行）
function flattenSpaces(text: string): string {
  return text.replace(/\s+/g, ' ').trim();
}

// 定长截断（超长加省略号）
function clipSummary(text: string): string {
  return text.length > KNOWLEDGE_SUMMARY_MAX ?
    text.substring(0, KNOWLEDGE_SUMMARY_MAX) + '…' : text;
}

// 检索结果文本（模型消费面，简洁中文——用户文案规约不适用于模型面）：
// · 零命中 → 指路 list（模型不必再猜关键词，先看清单是有效退路）
// · 命中 → 计数头行 + 逐条 `【书名】标题` 换行 正文，条目间空行分隔
// · 双封顶（条数与字符）：超限的**整条不进**（保已选条目完整，selectMemoryEntries 同语义），
//   被截时加尾行引导换关键词；首条恒放行（否则极窄预算下会退化成空头行）
// · 入参 = 命中行 + **书名单表**（别再传整个条目池——本函数只做渲染）
export function composeKnowledgeSearchResult(hits: KnowledgeEntryItem[],
  bookNames: Map<string, string>): string {
  if (hits.length === 0) {
    return '未检索到相关条目。可用 action 为 list 查看知识库条目清单。';
  }
  const blocks: string[] = [];
  let used: number = 0;
  for (const hit of hits) {
    if (blocks.length >= KNOWLEDGE_TOOL_RESULT_MAX_COUNT) {
      break;
    }
    const rawName: string = bookNames.get(hit.bookId) ?? '';
    const shownName: string = rawName !== '' ? rawName : KNOWLEDGE_UNKNOWN_BOOK;
    const block: string = '【' + shownName + '】' + hit.title + '\n' + clipEntryBody(hit.content);
    if (used + block.length > KNOWLEDGE_TOOL_RESULT_MAX_CHARS && blocks.length > 0) {
      break;
    }
    blocks.push(block);
    used += block.length;
  }
  let out: string = '检索到 ' + blocks.length + ' 条相关条目：\n' + blocks.join('\n\n');
  if (blocks.length < hits.length) {
    out += '\n' + KNOWLEDGE_SEARCH_CAP_NOTE;
  }
  return out;
}

// ── list 回执分页切窗（三处清单回执共用：检索件 list / 管理件书清单 / 管理件条目清单；
//    2026-09-22 O1 笔新增）──
// 形制照 composeManageSkillListReply / composeMemoryManageList：位次分页（序号自 offset 起算
// 全量连续，翻页不重编号）、offset 越过末条收到末条（模型恒见内容不落空页）、软顶收窄至少
// 1 条（首条恒放行，否则极窄预算下退化成空页）。limit/offset 脏值在本层二次归一（执行器已按
// 整数取值、本层再夹范围 = 双保险，照两先例）
interface KnowledgeListPage {
  total: number; // 全量条数
  start: number; // 本页首条的全量位次（1 基）
  lastShown: number; // 本页末条的全量位次（至少 1 条，故恒 ≥ start）
  lines: string[]; // 本页行（已渲染）
  softCut: boolean; // 因软顶收窄（没到 limit 就停）
}

// 切窗（renderLine 惰性渲染——只渲染真正上屏的行；全量可能上千条，禁先造全数组）
function pageKnowledgeList(total: number, offset: number, limit: number,
  renderLine: (index: number) => string): KnowledgeListPage {
  if (total <= 0) {
    return { total: 0, start: 1, lastShown: 0, lines: [], softCut: false };
  }
  let start: number = offset < 1 ? 1 : offset;
  if (start > total) {
    start = total;
  }
  let count: number = limit < 1 ? KNOWLEDGE_LIST_DEFAULT_COUNT : limit;
  if (count > KNOWLEDGE_LIST_MAX_COUNT) {
    count = KNOWLEDGE_LIST_MAX_COUNT;
  }
  const lines: string[] = [];
  let used: number = 0;
  while (lines.length < count && start - 1 + lines.length < total) {
    const line: string = renderLine(start - 1 + lines.length);
    if (lines.length > 0 && used + line.length > KNOWLEDGE_LIST_PAGE_SOFT_CHARS) {
      break;
    }
    lines.push(line);
    used += line.length;
  }
  const lastShown: number = start - 1 + lines.length;
  return { total: total, start: start, lastShown: lastShown, lines: lines,
    softCut: lines.length < count && lastShown < total };
}

// 分页尾行（单位随域：条目用「条」、书用「个」；三态措辞照两先例逐字 = 收窄提示 / 翻页指引 /
// 已到末尾）
function knowledgePageTail(page: KnowledgeListPage, unit: string): string {
  const parts: string[] = [];
  if (page.softCut) {
    parts.push('本页因长度限制只显示前 ' + page.lines.length + ' ' + unit);
  }
  if (page.lastShown < page.total) {
    parts.push('还有 ' + (page.total - page.lastShown) + ' ' + unit + '，可用 offset=' +
      (page.lastShown + 1) + ' 继续');
  } else {
    parts.push('已到末尾');
  }
  return parts.join('\n');
}

// 清单结果文本（工具 list 动作）：头行「已启用 N 个知识库，共 M 条条目。本页第 a~b 条：」+
// 逐行 `【书名】标题`（关键词非空时后缀 `（关键词）`）+ 分页尾行；无条目回一句直说，不给空
// 头行。★ bookRows = **已启用**的知识库行（调用方按启用集过滤后传入——头行的 N 与所见条目
// 同源，传全库会让 N 虚高）。★ 2026-09-22 O1 笔起带 offset/limit（原为全量输出，大库回执必
// 被工具结果管线截尾——缘由与算式见 KNOWLEDGE_LIST_* 常量区）
export function composeKnowledgeListResult(bookRows: KnowledgeBookItem[],
  entries: KnowledgeEntryItem[], offset: number, limit: number): string {
  if (entries.length === 0) {
    return '知识库暂无条目。';
  }
  const names: Map<string, string> = new Map<string, string>();
  for (const book of bookRows) {
    names.set(book.id, book.name);
  }
  const page: KnowledgeListPage = pageKnowledgeList(entries.length, offset, limit,
    (index: number): string => {
      const entry: KnowledgeEntryItem = entries[index];
      const rawName: string = names.get(entry.bookId) ?? '';
      const shownName: string = rawName !== '' ? rawName : KNOWLEDGE_UNKNOWN_BOOK;
      const keywords: string = flattenSpaces(entry.keywords);
      const suffix: string = keywords !== '' ? '（' + keywords + '）' : '';
      return '【' + shownName + '】' + entry.title + suffix;
    });
  return '已启用 ' + bookRows.length + ' 个知识库，共 ' + entries.length + ' 条条目。本页第 ' +
    page.start + '~' + page.lastShown + ' 条：\n' + page.lines.join('\n') + '\n' +
    knowledgePageTail(page, '条');
}

// 列表副行摘要（知识库书详情页 / 助手启用页的行副行）：关键词非空显示关键词，否则显示
// 正文首段——两条都压平换行并截断到 KNOWLEDGE_SUMMARY_MAX，保证单行
export function knowledgeEntrySummary(entry: KnowledgeEntryItem): string {
  const keywords: string = flattenSpaces(entry.keywords);
  if (keywords !== '') {
    return '关键词：' + clipSummary(keywords);
  }
  return clipSummary(flattenSpaces(entry.content));
}

// ══ 管理面纯函数（2026-09-21 知识库第二笔下本，任务书-知识库写入口与上限放宽-20260921）══
// 两条链共用本组：①重名判定（条目编辑页保存前拦截 + manage_knowledge 的 create/update 双路
// 拦截——**单源**，禁 UI 与工具各写一套比较逻辑）；②manage_knowledge 的模型面回执（工具面
// 文案不受「面向用户文案写作规约」约束，但须准确、可执行；回执全文进工具卡 = 用户审计面）。

// 同书重名判定：存在**同书**条目 title.trim() === title（两侧都 trim——「前后空白等价」，
// 用户看不出的差别不该算两个名字）且 id !== excludeId（编辑/改名态排除自身防自撞；新建态
// 传 ''）。入参 title 由调用方保证已 trim（编辑页与工具都在入口 trim 过，此处不再兜底——
// 二次 trim 会让「调用方没 trim」这类缺陷静默通过）
export function knowledgeTitleTaken(entries: KnowledgeEntryItem[], title: string,
  excludeId: string): boolean {
  for (const entry of entries) {
    if (entry.id !== excludeId && entry.title.trim() === title) {
      return true;
    }
  }
  return false;
}

// 书名重名判定（2026-09-22 八百七十一节新增，与上方条目侧同形同纪律）：存在同名知识库
// （name.trim() 逐字——「前后空白等价」，用户看不出的差别不该算两个名字）且 id !== excludeId
// （重命名态排除自身防自撞；新建态传 ''）。**单源**——UI 库页（新建与重命名两路保存前拦截）
// 与工具侧 create_book 同用，禁任一侧另写一套比较逻辑。入参 name 由调用方保证已 trim（编辑页
// 与工具都在入口 trim 过，二次 trim 会让「调用方没 trim」这类缺陷静默通过）
// · 为何要拦：书名是**单键定位**（写动作只给书名一个参数、无上级键），同名书会让每次写入与
//   定位都歧义（工具侧对存量重名书只能拒歧义回执）；UI 原缺此判 ⇒ 用户可从设置页造出同名书，
//   正是「存量重名书」的来源
export function knowledgeBookNameTaken(books: KnowledgeBookItem[], name: string,
  excludeId: string): boolean {
  for (const book of books) {
    if (book.id !== excludeId && book.name.trim() === name) {
      return true;
    }
  }
  return false;
}

// list 回执（manage_knowledge 的 list 动作；**单函数两形态**——「空态 / 头行 / 逐行 / 尾行」
// 分支两形态共用一套，拆成两函数就多出两处措辞漂移面）：
// · 书清单形态：book 传 ''，用 books + counts（entries 传空数组）——逐行 `【书名】N 条`
// · 条目清单形态：book 传书名，用 entries（books 传空数组、counts 传空 Map）——逐行
//   `【标题】（关键词）`（关键词空则不带后缀）；书不存在由调用方先拦，本函数只管渲染
// · **两形态都按 offset/limit 分页**（2026-09-22 O1 笔：原为全量输出，条目形态单库满 100 条
//   ≈ 20.8K 必被工具结果管线截尾；书形态虽只 20 个库，同参数同语义免得「一处生效一处不生效」）
export function composeKnowledgeManageListReply(book: string, books: KnowledgeBookItem[],
  counts: Map<string, number>, entries: KnowledgeEntryItem[], offset: number,
  limit: number): string {
  if (book === '') {
    if (books.length === 0) {
      return '还没有知识库。可用 action 为 create_book 新建一个。';
    }
    const bookPage: KnowledgeListPage = pageKnowledgeList(books.length, offset, limit,
      (index: number): string => {
        const item: KnowledgeBookItem = books[index];
        return '【' + item.name + '】' + (counts.get(item.id) ?? 0) + ' 条';
      });
    return '共 ' + books.length + ' 个知识库。本页第 ' + bookPage.start + '~' +
      bookPage.lastShown + ' 个：\n' + bookPage.lines.join('\n') + '\n' +
      knowledgePageTail(bookPage, '个');
  }
  if (entries.length === 0) {
    return '知识库「' + book + '」暂无条目。可用 action 为 create 写入一条。';
  }
  const entryPage: KnowledgeListPage = pageKnowledgeList(entries.length, offset, limit,
    (index: number): string => {
      const entry: KnowledgeEntryItem = entries[index];
      const keywords: string = flattenSpaces(entry.keywords);
      const suffix: string = keywords !== '' ? '（' + keywords + '）' : '';
      return '【' + entry.title + '】' + suffix;
    });
  return '知识库「' + book + '」共 ' + entries.length + ' 条。本页第 ' + entryPage.start + '~' +
    entryPage.lastShown + ' 条：\n' + entryPage.lines.join('\n') + '\n' +
    knowledgePageTail(entryPage, '条');
}

// 重名回执（create 与 update 改名两路共用；P0-1 不静默——点名被拒的标题、所属知识库，并列出
// **该书现有标题**让模型下一步能自己换名或改走 update）。existingTitles 为空 = 竞态（判定与
// 取清单之间被删）——不印空段，只给换名指引
export function composeKnowledgeTitleTakenReply(book: string, title: string,
  existingTitles: string[]): string {
  let out: string = '知识库「' + book + '」已有同名条目「' + title + '」，本次未写入。';
  if (existingTitles.length > 0) {
    out += '该书现有标题：\n' + existingTitles.map((item: string): string =>
      '【' + item + '】').join('\n');
  }
  return out + '\n请换一个名称，或用 action 为 update 修改现有条目。';
}

// create_book 成功回执（书名 + 现总数 + **未启用提醒**——决策 3 的必然后果：新建的书默认不被
// 任何助手启用，模型与用户都须知道下一步要去助手编辑页开启，照 manage_skills「创建成功后告知
// 还未被任何助手启用」先例）
export function composeKnowledgeManageCreateReply(book: string, total: number): string {
  return '已创建知识库「' + book + '」（现共 ' + total + ' 个）。它还没有被任何助手启用，' +
    '需要时在对应助手的编辑页「知识库」分区开启。';
}

// create 条目成功回执（书名 + 条目标题 + 该书现条数）
export function composeKnowledgeManageCreateEntryReply(book: string, title: string,
  total: number): string {
  return '已在知识库「' + book + '」新增条目「' + title + '」（该书现共 ' + total + ' 条）。';
}

// update 成功回执（书名 + 原名 → 新名 + 改动字段中文名数组——逐项列出改了什么，防「假成功」
// 回执；改名未发生时只印原名）
export function composeKnowledgeManageUpdateReply(book: string, oldTitle: string,
  newTitle: string, changed: string[]): string {
  const namePart: string = newTitle !== oldTitle ?
    '「' + oldTitle + '」改名为「' + newTitle + '」' : '「' + oldTitle + '」';
  return '已更新知识库「' + book + '」的条目' + namePart +
    '。本次改动：' + changed.join('、') + '。';
}

// delete 成功回执（书名 + 被删标题 + 该书现余条数）
export function composeKnowledgeManageDeleteReply(book: string, title: string,
  remaining: number): string {
  return '已删除知识库「' + book + '」的条目「' + title + '」（该书现余 ' + remaining + ' 条）。';
}

// get 回执（读回单条正文；2026-09-22 决明拍板「读回做」补）：**直读**，不经检索打分——指名
// book + title 即回该条正文，头行给归属（书 + 标题），关键词非空才出一行（空白压平，纯空白
// 归不出此行），正文**原样**（正文上限 KNOWLEDGE_CONTENT_MAX 6000 < 工具结果管线钳位 8192
// ⇒ 单条恒完整送达——与检索面同一不变量的另一条腿；此处刻意不过 clipEntryBody：直读的语义
// 是「给我原文」，截断会与这个语义打架）。
// ★ 不复用 composeKnowledgeSearchResult：那份的头行是「检索到 N 条相关条目」，直读场景下会把
// 「指名读取」误述成「检索命中」（技能域 get 复用装载回执是有那份回执本就同义，本域没有）。
// ★ fileNames 为**可选第五参**（2026-09-23 知识库文件笔）：无文件时恒零输出 ⇒ 存量回执
// 逐字节不变（本笔的不变量，断言守）；有文件才在关键词行后追加一行件名清单（供模型按名发
// read_file 取件）。**只列名不预读内容**（同技能附件清单段口径：附件可能很大，预读进上下文
// 是纯浪费）。长度上界复算：正文 6000 + 件名 10×60 + 分隔符与头行约 300 ≈ 6900 < 8192
// ⇒ 本回执恒不被工具结果管线截断（上限任一上调时须复算本条——见 read_file 回执同款注）
export function composeKnowledgeManageGetReply(book: string, title: string, keywords: string,
  content: string, fileNames: string[] = []): string {
  const shownKeywords: string = flattenSpaces(keywords);
  const keywordLine: string = shownKeywords !== '' ? '关键词：' + shownKeywords + '\n' : '';
  const fileLine: string = fileNames.length > 0 ? '文件：' + fileNames.join('、') + '\n' : '';
  return '知识库「' + book + '」的条目「' + title + '」\n' + keywordLine + fileLine + content;
}

// ══ 条目附件文件族（2026-09-23 知识库文件笔）══
// 一行一条目的**纯文本**附件。**三条边界**（与 ChatDbSchema.SQL_CREATE_KNOWLEDGE_FILES 注释
// 互指，勿在别处另立口径）：①**只存文本**——二进制文档（PDF/Word）要做得另表另链；②**不进
// 检索索引、不进注入块**——selectKnowledgeHits / composeKnowledgeSearchResult / 将来的关键词
// 触发注入三处都不含文件，文件只经 manage_knowledge 的 read_file 按件名取用；③**归属用
// entryId，文件文本不进条目 content**（归属混进正文字段会让「按单元建索引」的向量化升级做不成）。
// 与技能附件族（SkillText / SkillDb / SkillPack）**刻意各持一份**：两域的名称解析、件名查重、
// 上限常量都同形但不共用（域界口径同 skills 与 knowledge 两列的解析函数——禁跨域合并）。

// 每条目附件件数上限（文件卡「新建/上传」入口与 KnowledgeDb 写入侧两处拦；每库上界 =
// 100 条 × 10 件 = 1000 件/库）
export const KNOWLEDGE_FILE_MAX_COUNT: number = 10;
// 单件内容上限（< clipToolResult 8192——保证单件读取回执不被管线截断；余量复算见下方
// composeKnowledgeManageReadFileReply 注释）
export const KNOWLEDGE_FILE_CONTENT_MAX: number = 8000;
// 件名长度上限（含扩展名；文件编辑页 maxLength 与本域校验同源）
export const KNOWLEDGE_FILE_NAME_MAX: number = 60;
// 扩展名白名单（值与技能附件族同表、判据同义：只收无执行语义的纯数据/文档文本格式，
// **拒脚本族与二进制**）。两域各自持有——改一处不动另一处是本域的域界口径
export const KNOWLEDGE_FILE_EXTS: string[] = ['md', 'txt', 'csv', 'json', 'xml', 'yml', 'yaml',
  'toml', 'ini', 'log', 'html', 'htm'];
// 换行类字符族（件名拒收判据；与技能域 LINE_BREAK_CHARS 同族集——名称进的是逐行文本
// 清单与逐字定位键，换行会同时破坏两者）
const KNOWLEDGE_LINE_BREAK_CHARS: string = '\r\n\u000b\u000c\u0085\u2028\u2029';

// 件名扩展名（小写、无点；无扩展名回 ''）。★ **有意自持**不 import SkillText.skillFileExt：
// 本域零 import 约束（断言脚本复制直跑）优先于复用一行小工具——与 SkillText 自持
// AttachmentUtil.extOf 同款取舍
export function knowledgeFileExt(name: string): string {
  const dot: number = name.lastIndexOf('.');
  if (dot < 0 || dot >= name.length - 1) {
    return '';
  }
  return name.substring(dot + 1).toLowerCase();
}

// 含换行类字符否（件名拒收判据；逐字符扫，族集单源见上方常量）
function knowledgeNameHasLineBreak(text: string): boolean {
  for (let i: number = 0; i < text.length; i++) {
    if (KNOWLEDGE_LINE_BREAK_CHARS.indexOf(text.charAt(i)) >= 0) {
      return true;
    }
  }
  return false;
}

// 件名合法性（非空 + 不含换行类字符 + 长度 + 扩展名在白名单内——脚本族与二进制格式在此被拒）。
// 本函数是纯域对外校验面，口径必须与 validateKnowledgeFileArgs 保持一致
export function isKnowledgeFileNameValid(name: string): boolean {
  const trimmed: string = name.trim();
  return trimmed !== '' && !knowledgeNameHasLineBreak(trimmed) &&
    trimmed.length <= KNOWLEDGE_FILE_NAME_MAX &&
    KNOWLEDGE_FILE_EXTS.includes(knowledgeFileExt(trimmed));
}

// 件名校验结果（ok = false 时 error 为中文原因）
export interface KnowledgeFileValidation {
  ok: boolean;
  name: string;
  content: string;
  error: string;
}

function rejectKnowledgeAttachment(error: string): KnowledgeFileValidation {
  return { ok: false, name: '', content: '', error: error };
}

// 附件件校验（入参 = 件名 + 正文；脏值不归位而是**明确拒**——与条目校验同一口径：件名决定
// 模型能否按名取到，静默改名会让「清单里的名字」与「库里的名字」不一致）：
// · 件名空 / 含换行类字符 / 超长 / 扩展名不在白名单（含无扩展名、二进制、脚本族）→ 拒 + 中文原因
// · 正文空 / 超 KNOWLEDGE_FILE_CONTENT_MAX → 拒
export function validateKnowledgeFileArgs(name: string, content: string): KnowledgeFileValidation {
  const trimmedName: string = name.trim();
  const trimmedContent: string = content.trim();
  if (trimmedName === '') {
    return rejectKnowledgeAttachment('文件名不能为空');
  }
  if (knowledgeNameHasLineBreak(trimmedName)) {
    return rejectKnowledgeAttachment('文件名不能包含换行，请改用单行名称');
  }
  if (trimmedName.length > KNOWLEDGE_FILE_NAME_MAX) {
    return rejectKnowledgeAttachment('文件名超过 ' + KNOWLEDGE_FILE_NAME_MAX + ' 字上限，当前 ' +
      trimmedName.length + ' 字');
  }
  const ext: string = knowledgeFileExt(trimmedName);
  if (ext === '') {
    return rejectKnowledgeAttachment('文件名需要带扩展名，支持 ' + KNOWLEDGE_FILE_EXTS.join('、'));
  }
  if (!KNOWLEDGE_FILE_EXTS.includes(ext)) {
    return rejectKnowledgeAttachment('不支持 .' + ext + ' 格式，仅支持纯文本文件 ' +
      KNOWLEDGE_FILE_EXTS.join('、'));
  }
  if (trimmedContent === '') {
    return rejectKnowledgeAttachment('文件内容不能为空');
  }
  if (trimmedContent.length > KNOWLEDGE_FILE_CONTENT_MAX) {
    return rejectKnowledgeAttachment('文件内容超过 ' + KNOWLEDGE_FILE_CONTENT_MAX + ' 字上限，当前 ' +
      trimmedContent.length + ' 字');
  }
  return { ok: true, name: trimmedName, content: trimmedContent, error: '' };
}

// 件名定位三态（工具 read_file 与页面共用口径：trim 后逐字等值；形制照 SkillText 的
// locateSkillFileByName）。★ 写入侧已拒同名件（文件编辑页保存前查重），多命中态是**兜底**：
// 导出备份的恢复链逐表按 id 原样插回已删的旧行、不查件名唯一（见 ExportImport 的导入循环），
// 届时同一条目下会出现同名两件——调用方须如实拒歧义（P0-1 不静默），静默取第一条会让模型
// 拿到的件名对不上它实际读到的那一份。
export interface KnowledgeFileLocateOutcome {
  state: string; // 'unique' | 'none' | 'multi'
  index: number; // state='unique' 时有效，否则 -1
  hits: string[]; // state='multi' 时的逐条清单（'[N] 件名'）
}

export function locateKnowledgeFileByName(names: string[],
  name: string): KnowledgeFileLocateOutcome {
  const target: string = name.trim();
  const hits: string[] = [];
  let index: number = -1;
  for (let i: number = 0; i < names.length; i++) {
    if (names[i].trim() === target) {
      if (index < 0) {
        index = i;
      }
      hits.push('[' + (i + 1).toString() + '] ' + names[i]);
    }
  }
  if (hits.length === 0) {
    return { state: 'none', index: -1, hits: [] };
  }
  if (hits.length > 1) {
    return { state: 'multi', index: -1, hits: hits };
  }
  return { state: 'unique', index: index, hits: [] };
}

// read_file 回执（读回单件附件原文）：头行给归属三件（书 / 条目 / 件名），正文**原样**。
// 长度上界复算：正文 8000 + 头行（书 50 + 标题 50 + 件名 60 + 固定字约 16）≈ 8176 < 8192
// ——**余量仅 16 字**：本回执顶格时仍在线内，但任一上限（书/条目名 50、件名 60、件内容 8000）
// 上调都必须先复算本式，否则管线尾截断会切掉文件尾部（与技能域 SKILL_REPLY_MAX_CHARS 那笔
// 同款教训：正文被切 = 依据丢失，比少列清单严重得多）
export function composeKnowledgeManageReadFileReply(book: string, title: string, name: string,
  content: string): string {
  return '知识库「' + book + '」的条目「' + title + '」的文件「' + name + '」\n' + content;
}
