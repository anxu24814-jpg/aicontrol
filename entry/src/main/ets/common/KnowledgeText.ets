// 知识库文本纯函数域（2026-09-21 世界书知识库首版，任务书-世界书知识库-20260921 §4.3）：
// 知识库层的全部纯逻辑——启用清单解析/序列化 / 检索切词 / 打分 / 相关度排序 / 检索结果
// 拼装 / 清单拼装 / 列表副行摘要 / **管理面（重名判定与工具回执，2026-09-21 知识库第二笔
// 下本加）** / **条目附件件的校验与读回回执（2026-09-23 知识库文件笔加）**。**零 import
// 纯函数约束**（照 SkillText.ets / MemoryText.ets
// ——断言脚本复制本文件为 .ts 直跑，是本域可测性的根基；IO 编排〔DB 读写〕在 KnowledgeDb /
// ToolKnowledge / 各页面，不在本域）。
//
// ★ 与相邻两列的语义分界（本域最易被后人按错口径改坏的一点）：assistants.knowledge 的 ''
// = **空集合**（默认不启用任何知识库），与 assistants.skills 同义、与 assistants.tools 的
// 「'' = 默认集合」**相反**。故 parseEnabledKnowledgeIds 与 parseEnabledSkillIds 形态相同但
// **域不同，禁跨域合并复用**（各留一份 = 有意为之的两处，不是重复代码——技能域已立此纪律）；
// 与 parseEnabledToolIds 更是语义相反。
//
// ★ 首版姿态 = 工具化检索（条目不自动注入，模型经 search_knowledge 按需查阅）：keywords
// 字段**只参与检索加权与展示，不接触发逻辑**——这不是遗漏，是本笔的姿态边界（关键词自动
// 注入属另一姿态，见 docs/方案-世界书关键词触发-20260921.md）；字段先备好，将来换姿态免
// 二次迁移。

// ── 上限常量族（任务书 §4.3 拍板值）──
// 条目名称上限（编辑页 TextInput maxLength 与本域同源）。★ 2026-09-22 自检轮起**两处同用**：
// 条目名称 + **知识库名称**（库页命名对话框 maxLength 亦取本常量；manage_knowledge 的
// create_book 校验同源）——改本值即三处同动，禁在工具面另写数字
export const KNOWLEDGE_TITLE_MAX: number = 50;
// 关键词上限（纯检索加权与展示字段，不进任何触发判定）
export const KNOWLEDGE_KEYWORDS_MAX: number = 100;
// 条目正文上限（纯文本；< clipToolResult 8192 保证单条不被下游截断）
export const KNOWLEDGE_CONTENT_MAX: number = 6000;
// 工具返回双封顶（宪法「数据有界」：5 条 / 12000 字覆盖典型问询，超出由尾行引导收窄关键词）。
// ★ 2026-09-21 知识库第二笔下本把总档 4000 → 12000（与正文上限同为 6000 量级：一次能回两条
// 满条）：依据 = 工程估算口径 CJK 1.0 token/字（TokenEstimate.ets），12000 字 ≈ 12000 token，
// 是联网检索结果档 BROWSE_RESULT_MAX_CHARS 8192 的 1.5 倍，且工具结果留历史逐轮重发——
// 取 12000 而非更高的档是决明「可适当减少」授权下的收窄取舍。
// ★ **实际生效上限 8192**（言行一致，勿误解本档）：工具结果出管线前一律过
// clipToolResult(raw)（默认 maxChars 8192，ChatToolRoundCtrl 两处调用点）⇒ 合计超 8K 的多条
// 结果仍会被管线尾部截断并带「…[结果过长已截断]」尾标。本档是**检索侧预算**（决定哪几条进
// 结果），不是模型面硬顶；单条 6000 字 + 头行恒在管线线内 ⇒ 单条恒完整送达（本笔核心诉求）
export const KNOWLEDGE_TOOL_RESULT_MAX_COUNT: number = 5;
export const KNOWLEDGE_TOOL_RESULT_MAX_CHARS: number = 12000;
// 单条正文字符上限（工具结果里单条正文的截断档）。★ 2026-09-21 知识库第二笔下本 1200 →
// 6000（**与正文上限 KNOWLEDGE_CONTENT_MAX 同值** ⇒ 单条恒完整送达——原「用户写 2000 字、
// 模型只读到 1200 字」的静默缩水由此消除；旧注释的「5 × 1200 = 6000 > 4000 总预算」推理
// 随之作废）。保留本档的理由 = 将来再调正文上限时，仍有一道「一条不得独占整份结果」的闸
export const KNOWLEDGE_ENTRY_CLIP: number = 6000;
// 列表副行摘要的截断档（知识库页 / 助手启用页的行副行，单行显示）
const KNOWLEDGE_SUMMARY_MAX: number = 20;

// ── list 回执分页两档 + 页内字数软顶（2026-09-22 O1 笔；决明「可补 o1」拍板）──
// 本族存在的理由：本域两处 list 回执原为**一次性全量输出**——条目行最坏 = 2 + 50（书名）+
// 2 + 50（标题）+ 2 + 100（关键词）≈ 208 字，单库满 100 条 ≈ 20.8K、检索侧多库合计更大，
// 双双越过工具结果管线 clipToolResult 8192 钳位线 ⇒ 大库回执被尾部截断，模型看不到末段且
// **无翻页手段**（与技能域立 SKILL_MANAGE_LIST_* 时同一类缺陷，故形制照两先例：位次分页 +
// 页内软顶收窄 + 尾行翻页指引）。
// 30 的依据（本域实数推算）：30 行 × 208 字 ≈ 6.2K < 8192，留头尾行与余量；全量 100 条
// ≈ 20.8K 必被截尾，故封顶 30 + 分页兜底
export const KNOWLEDGE_LIST_DEFAULT_COUNT: number = 20;
export const KNOWLEDGE_LIST_MAX_COUNT: number = 30;
// 页内总字数软顶（超则自动收窄本页条数至少 1 条，防 clipToolResult 硬顶截尾丢翻页提示；
// MAX_COUNT 内最坏 6.2K 不触发此线——它是 MAX_COUNT 将来调大时的结构性兜底，双条件姿势
// 与两先例一致）
export const KNOWLEDGE_LIST_PAGE_SOFT_CHARS: number = 6000;

// 命中权重（标题 3 / 关键词 2 / 正文 1——同一 token 在多个字段命中**取最高权重不累加**，
// 不同 token 累加；标题命中是意图最强的信号）
const KNOWLEDGE_WEIGHT_TITLE: number = 3;
const KNOWLEDGE_WEIGHT_KEYWORDS: number = 2;
const KNOWLEDGE_WEIGHT_CONTENT: number = 1;

// 触上限尾行（照 CHAT_SEARCH_CAP_NOTE 同族形态）
const KNOWLEDGE_SEARCH_CAP_NOTE: string = '已达返回上限，可用更具体的关键词再检索。';
// 书名缺失兜底（某命中的 bookId 在书名单表里查不到 = 删库与查询之间的竞态）——**禁让
// undefined / null 字面量上屏**，模型看到它只会困惑
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
}

export interface KnowledgeBookItem {
  id: string;
  name: string;
}

// 启用集解析（assistants.knowledge 列 JSON 串 → id 数组）：
// '' / 坏 JSON / 非数组 → **空数组**（= 不启用任何知识库，与 skills 列同义、与 tools 列相反）；
// 只收非空字符串项；去重（重复 id 会让「已启用 N 个」与第 11 个拒绝的门槛失真）
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

// id 数组 → assistants.knowledge 列 JSON 串：空集合落 ''（库列默认形态 = 不启用，新装/新建
// 助手零配置零写入——与 skills 列的落库形态相同，与 tools 列含义相反）
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

// ══ 文件导入导出纯函数（2026-09-22 知识库导入导出笔，方案-知识库导入导出-20260922 §3）══
// 自家书级交换格式（三步路线第一步）：三层信封 version / type / data 与竞品同形（RikkaHub
// ExportData 同构）——第二步通用格式兼容时信封解析可直接复用，只多一个 type 分派分支。
// **零 import 约束不变**：盘面 I/O（选择器 / fd 拷贝 / 沙箱件 / 分享）在 KnowledgePack，
// 本域只有格式构造 / 解析 / 逐条分派 / 预览拼装——断言脚本复制本件为 .ts 直跑的根基不许破。

// ── 文件格式常量（§3.2）──
// 信封 type（第二步按 type 分派格式；本串只认自家，负向钉守全仓零第二处字面量）
export const KNOWLEDGE_FILE_TYPE: string = 'aicontrol_knowledge_book';
// 信封 version（留升级位）。★ 写侧恒写本值、**解析侧恒不校验**（自家链只认 type，版本号写什么
// 都照读——「只认存在、不比大小」的旧注释与实现不符，2026-09-22 自检轮订正）；格式语义变化时
// 才递增本值，届时如需拒读新版再在 parseOwnKnowledgeBook 补一道显式闸
export const KNOWLEDGE_FILE_VERSION: number = 1;
// 自家格式的扩展名（小写归一，照 SkillText.skillFileExt 口径；页面扩展名分派用）
export const KNOWLEDGE_FILE_EXT: string = 'json';

// ── 通用格式常量（2026-09-22 第二步/第三步，方案-知识库导入导出-20260922 §10.1 / §12.1）──
// 竞品信封 type：RikkaHub 与 Kelivo 的世界书格式（Kelivo 的导出函数名即 _toRikkaHubExportJson
// ——两家同形同字段，故对外只需写**一种**格式）。写侧恒用此值；读侧按「有无 entries」分派
// （见 parseWorldBookFile）。**字面量单源**：消费一律走常量，全仓禁第二处手写
export const KNOWLEDGE_COMPAT_TYPE: string = 'lorebook';
// 通用格式里关键词的切分符：**只按顿号与逗号**——条目编辑页明写的分隔约定（用户看得见），
// 不猜空格（空格可能是关键词本身的一部分，如 machine learning，切了就破坏原意）。
// ★ 与 splitKnowledgeQuery 的宽分隔符族是两回事：那个切的是**检索输入**（用户随手打字，宁宽），
//   这个切的是**已保存的关键词字段**（用户按 UI 约定写下，宁准）——两处取向相反，勿互抄
const KNOWLEDGE_KEYWORD_SEP = /[、,，]+/;

// 文件里的单条条目：恰四字段。id 与 createdAt / updatedAt **不进文件**——导入恒生成新 id 与
// 新时间戳（与两家竞品「导入必重生 ID」同口径，也避免与库内既有 id 相撞）；条目序 = 数组序。
// keywords 存**原串**不拆数组（本域检索语义是整串子串匹配，拆开拼回会漂——自家往返保真
// 是本格式存在的第一理由）；source 白名单两值（解析侧归一，非 'assistant' 一律落 'user'，
// 防手改文件造出非法值脏数据）
export interface KnowledgeFileEntry {
  title: string;
  keywords: string;
  content: string;
  source: string;
}

// 解析结果（ok = false 时 error 为整份级中文原因；entries 为原始条目，逐条分派在
// screenKnowledgeEntries——「整份拒」与「逐条说明」两级校验的分界）。
// notice = 外部世界书导入时的附注（已停用条数 / 注入设置未导入），自家格式恒 ''；
// 由 parseKnowledgeBook 组装、审阅弹窗原样呈现（**不在这里做取舍判断**——本域只描述事实）
export interface KnowledgeFileRead {
  ok: boolean;
  name: string;
  entries: KnowledgeFileEntry[];
  error: string;
  notice: string;
}

// 逐条分派结果：importable = 可导入条目（关键词已截到上限）；skipped = 未导入逐条中文原因；
// clippedKeywords = 因超长被截断关键词的条数（不拒收——关键词只是辅助索引，正文不丢）
export interface KnowledgeScreenResult {
  importable: KnowledgeFileEntry[];
  skipped: string[];
  clippedKeywords: number;
}

// 信封与数据层形态（序列化构造用；解析侧同一形态做非受检视图 + 逐字段 typeof 守卫）
interface KnowledgeFileEnvelope {
  version: number;
  type: string;
  data: KnowledgeFileBookData;
}

interface KnowledgeFileBookData {
  name: string;
  entries: KnowledgeFileEntry[];
}

function rejectKnowledgeFile(error: string): KnowledgeFileRead {
  return { ok: false, name: '', entries: [], error: error, notice: '' };
}

// 书名字长收口（2026-09-22 自检轮补）。★ 为什么必须有这道闸：书名的 50 字上限原本由**三个建书
// 面**各自把关——库页命名对话框 `maxLength: KNOWLEDGE_TITLE_MAX`、工具 create_book 显式长度
// 校验（869 笔补，理由正是「工具面能造出 UI 造不出的超限数据」）。**导入是第四个建书面**，
// 而外部件的 `data.name` 与文件名兜底都不受我方 UI 约束 ⇒ 唯一无闸的入口（自检轮实测：3000
// 字书名原样落库，且预览弹窗首行被撑到 3097 字——弹窗 message 是无上限 Text，两键会被顶出屏）。
// · 截断而不拒收：书名只是容器标签，且**审阅弹窗展示的就是最终落库名**（用户可见即非静默）；
//   拒收会让「文件名偏长的世界书」整本导不进来，而库里本就有重命名键兜底
// · 与导出侧文件名同款收口姿势（knowledgeFileName 截 40 + safeKnowledgeCut 代理对防护）
function capBookName(name: string): string {
  if (name.length <= KNOWLEDGE_TITLE_MAX) {
    return name;
  }
  return name.substring(0, safeKnowledgeCut(name, KNOWLEDGE_TITLE_MAX)).trim();
}

// 导出序列化（§3.1 逐字）：name + 条目四字段。source 如实导出（DB 侧只产 'user' /
// 'assistant' 两值，白名单外归 'user' 是防御——导出件不携带非法值，与导入侧同款两端口径）
export function serializeKnowledgeBook(name: string, entries: KnowledgeEntryItem[],
  sources: string[]): string {
  // sources 与 entries 同序（源标签不走 KnowledgeEntryItem——该形态刻意不带 source，
  // 见 KnowledgeDb 的 KnowledgeEntryRow.source 注释）
  const list: KnowledgeFileEntry[] = [];
  for (let i: number = 0; i < entries.length; i++) {
    list.push({
      title: entries[i].title,
      keywords: entries[i].keywords,
      content: entries[i].content,
      source: sources[i] === 'assistant' ? 'assistant' : 'user'
    });
  }
  const file: KnowledgeFileEnvelope = {
    version: KNOWLEDGE_FILE_VERSION,
    type: KNOWLEDGE_FILE_TYPE,
    data: { name: name, entries: list }
  };
  return JSON.stringify(file);
}

// ── 通用格式导出（2026-09-22 第三步，方案 §12.1）──
// 写 **RikkaHub 信封 + 最小写入**：RikkaHub 读它是自家格式（LorebookSerializer.tryImportNative）；
// Kelivo 读它走「只认 data 键、连 type 都不校验」的宽容解析。只写有对应物的三个字段（条目名 /
// 正文 / 关键词），其余（id / position / role / priority / injectDepth / scanDepth / useRegex /
// caseSensitive / constantActive / enabled）**一律省略**——两家模型每个字段都带默认值（RikkaHub
// 的 Kotlin 默认、Kelivo 的 `?? 默认`），省略即由对方补**它自己的**默认：零编造、零语义债，且
// 顺带绕开两家在 position 枚举大小写上的人为不一致（Kelivo 写大写、RikkaHub 声明小写且全仓无
// 宽容开关——那是**竞品互读**的坑，我们省略字段即完全不经那条路）。条目层不写 `type`：对方
// entries 的声明类型是**具体子类**而非 sealed 父类，不需要判别符
interface KnowledgeCompatEntry {
  name: string;
  content: string;
  keywords: string[];
}

interface KnowledgeCompatBookData {
  name: string;
  entries: KnowledgeCompatEntry[];
}

interface KnowledgeCompatEnvelope {
  version: number;
  type: string;
  data: KnowledgeCompatBookData;
}

export interface KnowledgeCompatExport {
  json: string;
  exported: number; // 写进文件的条数
  dropped: number;  // 无关键词被排除的条数
}

// 关键词整串 → 数组（**只按顿号与逗号**切——见 KNOWLEDGE_KEYWORD_SEP 注释；去空段与首尾空白）。
// 与导入侧 joinKeywordField 是同一份 UI 约定的两个方向（那边按顿号合、这边按顿号逗号切）
export function splitKnowledgeKeywords(keywords: string): string[] {
  const parts: string[] = [];
  for (const raw of keywords.split(KNOWLEDGE_KEYWORD_SEP)) {
    const part: string = raw.trim();
    if (part !== '') {
      parts.push(part);
    }
  }
  return parts;
}

// 通用格式序列化。★ **无关键词的条目不出**（方案 §14-5 口径 C）：对方的生效机制是关键词命中
// （`constantActive` 默认 false），无关键词的条目在那边**永不生效**——与其产出一个死条目，不如
// 不写并在结果里明示原因（合「不静默丢件」口径）。本应用里关键词留空是**合法常态**（条目编辑页
// 明写「留空则只按名称与正文检索」），故这条不是边角情形，必须在 UI 面讲清不可静默略过
export function serializeKnowledgeBookCompat(name: string,
  entries: KnowledgeEntryItem[]): KnowledgeCompatExport {
  const list: KnowledgeCompatEntry[] = [];
  let dropped: number = 0;
  for (const entry of entries) {
    const keywords: string[] = splitKnowledgeKeywords(entry.keywords);
    if (keywords.length === 0) {
      dropped++;
      continue;
    }
    list.push({ name: entry.title, content: entry.content, keywords: keywords });
  }
  const file: KnowledgeCompatEnvelope = {
    version: KNOWLEDGE_FILE_VERSION,
    type: KNOWLEDGE_COMPAT_TYPE,
    data: { name: name, entries: list }
  };
  return { json: JSON.stringify(file), exported: list.length, dropped: dropped };
}

// 导出结果提示（**仅在有条目被排除时非空**——没有要交代的事就不打扰，页面据此决定 toast 与否）。
// 入参取两个计数而不取整个 KnowledgeCompatExport：盘面域带回的正是这两个数，页面不必为凑参数
// 造一个假的 json 字段
export function composeKnowledgeCompatExportTip(exported: number, dropped: number): string {
  if (dropped === 0) {
    return '';
  }
  return '已导出 ' + exported + ' 条，' + dropped +
    ' 条没有关键词的条目未导出。通用格式按关键词触发，没有关键词的条目在别的应用里不会生效。';
}

// 导入整份级校验（§4.2 结构拒，文案逐字定死——页面 toast 与断言的契约面）；逐条内容校验在
// screenKnowledgeEntries。解析侧对未知字段**容忍**（只读白名单四字段，多余字段不拒收——
// 格式长期包袱的缓解口径）；条目数超 KNOWLEDGE_ENTRY_MAX 的闸在页面链（常量单源在
// KnowledgeDb，本域零 import 拿不到，不为它破零 import 纪律）。
// ★ 2026-09-22 第二步起本函数只做**分派**：自家 type → 原链（抽出为 parseOwnKnowledgeBook，
// 判据与文案一字未动）；其余一律交 parseWorldBookFile（RikkaHub/Kelivo 信封 / SillyTavern
// World Info / Kelivo 裸形态）。fallbackName = 选择器取到的**文件名**（去扩展名）——外部世界书
// 常无书名字段（ST 格式压根没有 name 概念），照 RikkaHub「导入时用文件名当书名」先例兜底；
// 自家格式恒不看它（自家书名必填、缺失即拒，那份严格性是自家往返保真的契约面，不外溢到外部件）
export function parseKnowledgeBook(text: string, fallbackName: string = ''): KnowledgeFileRead {
  let parsed: object | null = null;
  try {
    parsed = JSON.parse(text) as object | null;
  } catch (e) {
    return rejectKnowledgeFile('文件不是有效 JSON，未导入。');
  }
  // ★ 顶层 null 必须先过闸：`null` 是合法 JSON 值（`JSON.parse('null')` 返 null），而
  // `env.type` 读 null 属性会抛 TypeError——抛出去会被盘面域兜成「文件读取失败：Cannot read
  // properties of null…」英文原文，与「整份拒给中文原因」的契约不符（自检轮直跑实锤）。
  // 其余原始值（数字 / 字符串 / 布尔 / 数组）不在此拦：它们走世界书链后同落「不是知识库文件」
  const env: KnowledgeFileEnvelope | null = parsed as KnowledgeFileEnvelope | null;
  if (env === null) {
    return rejectKnowledgeFile('这个文件不是知识库文件，未导入。');
  }
  if (env.type === KNOWLEDGE_FILE_TYPE) {
    return parseOwnKnowledgeBook(env);
  }
  return parseWorldBookFile(env, fallbackName);
}

// 自家格式链：§4.2 四拒逐字（坏 JSON 一拒在分派层）+ 四字段白名单 + source 两值归一。
// 第二步重构时整体抽出，行为与文案与第一步逐字一致
function parseOwnKnowledgeBook(env: KnowledgeFileEnvelope): KnowledgeFileRead {
  const data: KnowledgeFileBookData | null = env.data ?? null;
  if (data === null || typeof data !== 'object') {
    // data 缺失或非对象 ⇒ 名称必缺，落名称拒
    return rejectKnowledgeFile('文件里没有知识库名称，未导入。');
  }
  const ownName: string = (typeof data.name === 'string' ? data.name : '').trim();
  if (ownName === '') {
    return rejectKnowledgeFile('文件里没有知识库名称，未导入。');
  }
  const name: string = capBookName(ownName);
  if (!Array.isArray(data.entries)) {
    return rejectKnowledgeFile('文件里没有条目清单，未导入。');
  }
  const entries: KnowledgeFileEntry[] = [];
  const rawItems: object[] = data.entries as object[];
  for (let i: number = 0; i < rawItems.length; i++) {
    const rec: KnowledgeFileEntry | null = rawItems[i] as KnowledgeFileEntry | null;
    // 数组里塞了 null（手改件）⇒ 落空条目交逐条分派按「无标题」说明；★ 禁在解析层抛
    //（`null.title` 会抛 TypeError，被盘面域兜成「文件读取失败：…」英文原文——与「条目级
    // 问题逐条说明、不升级成整份拒」的口径相反）
    if (rec === null) {
      entries.push({ title: '', keywords: '', content: '', source: 'user' });
      continue;
    }
    // 逐字段 typeof 守卫：非对象项 / 缺字段的条目落默认值，交逐条分派按「无标题」说明
    // （条目级问题逐条说明，不在解析层升级成整份拒）
    entries.push({
      title: typeof rec.title === 'string' ? rec.title : '',
      keywords: typeof rec.keywords === 'string' ? rec.keywords : '',
      content: typeof rec.content === 'string' ? rec.content : '',
      source: rec.source === 'assistant' ? 'assistant' : 'user'
    });
  }
  return { ok: true, name: name, entries: entries, error: '', notice: '' };
}

// ── 外部世界书链（2026-09-22 第二步）──
// 收件面 = 三种：① RikkaHub / Kelivo 信封（`{version, type:'lorebook', data:{name, entries[]}}`）
// ② SillyTavern World Info v2（无信封，顶层 entries 是**以 uid 字符串为键的 Map**）
// ③ Kelivo 裸形态（无信封，顶层 entries 为数组——Kelivo 的解析只看 data 键或 entries 键、连
//    type 都不校验，故它写出的边角形态也要吃）。**不读的字段一律不读**：注入位置 / 深度 /
//    角色 / 优先级 / 正则 / 大小写 / 常驻 / 扫描深度在本应用全无对应物（本应用按模型检索，
//    不自动注入），原样忽略并在弹窗附注里明说（方案 §10 映射表）
interface KnowledgeWorldHolder {
  name?: string;
  entries?: object;
}

interface KnowledgeWorldEntry {
  name?: string;
  comment?: string;
  key?: string[] | string;
  keywords?: string[] | string;
  content?: string;
  enabled?: boolean;
  disable?: boolean;
}

// 关键词字段归一（三形态容错）：数组 → 逐项 trim 去空后 join('、')（**方向与我们导出侧相反**：
// 那边按顿号逗号切、这边按顿号合，两边同一份 UI 约定）；字符串 → 原样（ST 的 key 单串形态与
// 手写件容错）；缺字段 → ''。★ 数组元素仍逐项过 typeof（手改件里塞数字/布尔不罕见）——
// 入参声明为联合类型而非 object，故 typeof 收窄落在 string 上而非 never
//（ArkTS 下 object 与 string 不相交，按 object 收窄会编译报 `trim does not exist on never`）
function joinKeywordField(value: string[] | string | undefined): string {
  if (typeof value === 'string') {
    return value;
  }
  if (value === undefined) {
    return '';
  }
  // 运行期兜底：字段塞了对象等不可迭代值（手改件）⇒ 视为缺失返空串。类型面本支恒假（联合类型
  // 已收窄到 string[]），留着是因为 JSON 不守类型——真喂进来时 `for…of` 会抛 TypeError，抛出去
  // 被盘面域兜成「文件读取失败：…」英文原文，与「逐条说明」口径不符（自检轮直跑实锤）
  if (!Array.isArray(value)) {
    return '';
  }
  const parts: string[] = [];
  for (const item of value) {
    if (typeof item === 'string' && item.trim() !== '') {
      parts.push(item.trim());
    }
  }
  return parts.join('、');
}

// 首个关键词（ST 条目标题在 comment 为空时取它——RikkaHub ST 导入同口径）
function firstWorldKeyword(value: string[] | string | undefined): string {
  if (typeof value === 'string') {
    return value.trim();
  }
  if (value === undefined) {
    return '';
  }
  // 运行期兜底（同 joinKeywordField）：不可迭代值视为缺失（ST 件里 key 塞对象时不留英文抛错面）
  if (!Array.isArray(value)) {
    return '';
  }
  for (const item of value) {
    if (typeof item === 'string' && item.trim() !== '') {
      return item.trim();
    }
  }
  return '';
}

// ST Map 键的排序位次（键是条目 uid 的数字串；非数字键排在所有数字键之后，同段按原序保持稳定
// ——确定性优先，禁依赖对象键的枚举序，同一文件在不同引擎上序会漂）
function worldEntryRank(key: string): number {
  const n: number = Number.parseInt(key, 10);
  return Number.isNaN(n) ? 2147483647 : n;
}

// 外部世界书附注（弹窗原文呈现，方案 §10 表两行）：已停用条数 + 注入设置未导入。恒含第二句
// （它解释的是「为什么导入后行为与源应用不同」，是用户看到条目变少之外最需要知道的一件事）；
// 停用句按实际计数出现。★ 措辞守「面向用户文案写作规约」：分句用句号、无括号连环
function composeWorldNotice(disabled: number): string {
  const parts: string[] = [];
  if (disabled > 0) {
    parts.push('源文件里已停用的 ' + disabled + ' 条未导入');
  }
  parts.push('源文件的注入位置、触发深度与常驻等设置未导入，本应用由助手按需检索，不自动注入');
  return parts.join('。') + '。';
}

function parseWorldBookFile(env: KnowledgeFileEnvelope, fallbackName: string): KnowledgeFileRead {
  const raw: object | null = env.data ?? null;
  const holder: KnowledgeWorldHolder =
    (raw !== null && typeof raw === 'object' ? raw : env as object) as KnowledgeWorldHolder;
  const entries: object | null = holder.entries ?? null;
  if (entries === null || typeof entries !== 'object') {
    // 拿不出条目清单 ⇒ 不是世界书件。★ 本拒**取代**第一步的「错 type 拒」：原判据只认自家
    // type，第二步要收外部件（它们常无 type 或 type 各异），判据由「type 是否为我方」推广为
    // 「能否拿出条目清单」——同信封不同实体的件（RikkaHub 的 mode_injection 导出等）在此照拒，
    // 「不是知识库文件」的语义不弱化，只是不再拿 type 当唯一凭据
    return rejectKnowledgeFile('这个文件不是知识库文件，未导入。');
  }
  const own: string = (typeof holder.name === 'string' ? holder.name : '').trim();
  const picked: string = own !== '' ? own : fallbackName.trim();
  if (picked === '') {
    return rejectKnowledgeFile('文件里没有知识库名称，未导入。');
  }
  // 书名字长收口（见 capBookName）：外部件的 name 字段与文件名兜底都可能超长，两者同过一闸
  const name: string = capBookName(picked);
  if (Array.isArray(entries)) {
    return readWorldArray(name, entries as object[]);
  }
  return readWorldMap(name, entries as object);
}

// 数组形态（RikkaHub / Kelivo）：条目序 = 数组序；`enabled === false` 的条目不导入（如实计数
// ——源应用里它本就不生效，搬过来反而会让用户以为它一直可用）
function readWorldArray(name: string, items: object[]): KnowledgeFileRead {
  const entries: KnowledgeFileEntry[] = [];
  let disabled: number = 0;
  for (const item of items) {
    const rec: KnowledgeWorldEntry | null = item as KnowledgeWorldEntry | null;
    // 数组里塞了 null（手改件）⇒ 落空条目交逐条分派按「无标题」说明；★ 禁在解析层抛
    //（`null.enabled` 会抛 TypeError，被盘面域兜成「文件读取失败：…」英文原文）
    if (rec === null) {
      entries.push({ title: '', keywords: '', content: '', source: 'user' });
      continue;
    }
    if (rec.enabled === false) {
      disabled++;
      continue;
    }
    entries.push({
      title: typeof rec.name === 'string' ? rec.name : '',
      keywords: joinKeywordField(rec.keywords),
      content: typeof rec.content === 'string' ? rec.content : '',
      source: 'user'
    });
  }
  return { ok: true, name: name, entries: entries, error: '',
    notice: composeWorldNotice(disabled) };
}

// Map 形态（SillyTavern World Info v2）：标题 = comment，空则取首个关键词；停用标是 `disable`
// （与竞品 `enabled` 相反极——两家各一极，此处是 ST 侧）；键序按 worldEntryRank
function readWorldMap(name: string, map: object): KnowledgeFileRead {
  const rec: Record<string, object> = map as Record<string, object>;
  const keys: string[] = Object.keys(rec);
  const order: number[] = [];
  for (let i: number = 0; i < keys.length; i++) {
    order.push(i);
  }
  order.sort((a: number, b: number): number => {
    const ra: number = worldEntryRank(keys[a]);
    const rb: number = worldEntryRank(keys[b]);
    return ra !== rb ? ra - rb : a - b;
  });
  const entries: KnowledgeFileEntry[] = [];
  let disabled: number = 0;
  for (const idx of order) {
    // 退化项（Map 里塞了 null / 非对象）不特判字段：落空条目 ⇒ 走逐条分派的「无标题」说明。
    // 这与自家格式「条目级问题不在解析层升级成整份拒」同一口径，也避开了对接口类型做 typeof
    // 收窄（ArkTS 下会落 never）。★ 但 **null 必须先过闸**：「字段读为 undefined」只对非 null
    // 的值成立，`null.disable` 会抛 TypeError（被盘面域兜成英文原文）。强转先例 = 上方自家链
    const item: KnowledgeWorldEntry | null = rec[keys[idx]] as KnowledgeWorldEntry | null;
    if (item === null) {
      entries.push({ title: '', keywords: '', content: '', source: 'user' });
      continue;
    }
    if (item.disable === true) {
      disabled++;
      continue;
    }
    const comment: string = typeof item.comment === 'string' ? item.comment.trim() : '';
    entries.push({
      title: comment !== '' ? comment : firstWorldKeyword(item.key),
      keywords: joinKeywordField(item.key),
      content: typeof item.content === 'string' ? item.content : '',
      source: 'user'
    });
  }
  return { ok: true, name: name, entries: entries, error: '',
    notice: composeWorldNotice(disabled) };
}

// 定长截断的安全切点（代理对防护——emoji 等增补平面字符占两码元，硬切会留孤立代理字符，
// 它进文件名是非法名、进请求体是非法 Unicode；照 SkillText.safeCutIndex 口径本地一份——
// 本域零 import 拿不到对方，同 parseEnabledKnowledgeIds 两域同形不同源的既有纪律）
function safeKnowledgeCut(text: string, max: number): number {
  if (text.length <= max) {
    return text.length;
  }
  const last: number = text.charCodeAt(max - 1);
  return (last >= 0xD800 && last <= 0xDBFF) ? max - 1 : max;
}

function clipImportText(text: string, max: number): string {
  return text.length > max ? text.substring(0, safeKnowledgeCut(text, max)) : text;
}

// 逐条分派（§4.3 真值表）：三类「跳过」与一类「截断」的分野——跳过 = 原样保不住的，宁可不导
// （标题是检索权重最高字段、正文是原文，截断即悄悄改命中行为与内容）；截断 = 辅助字段且已明示。
// 重名判定复用 knowledgeTitleTaken（导入目标恒为新库 ⇒ 只需文件内自查：与已收条目撞名即跳过）
export function screenKnowledgeEntries(raw: KnowledgeFileEntry[]): KnowledgeScreenResult {
  const importable: KnowledgeFileEntry[] = [];
  const skipped: string[] = [];
  const accepted: KnowledgeEntryItem[] = []; // 文件内前序已收集（合成 id 防自撞语义误用）
  let clippedKeywords: number = 0;
  for (let i: number = 0; i < raw.length; i++) {
    const title: string = raw[i].title.trim();
    if (title === '') {
      skipped.push('第 ' + (i + 1) + ' 条（无标题）：条目名为空');
      continue;
    }
    if (title.length > KNOWLEDGE_TITLE_MAX) {
      skipped.push('『' + clipImportText(title, KNOWLEDGE_IMPORT_NAME_MAX) +
        '…』：条目名超过 ' + KNOWLEDGE_TITLE_MAX + ' 字');
      continue;
    }
    if (raw[i].content.length > KNOWLEDGE_CONTENT_MAX) {
      skipped.push('『' + title + '』：正文 ' + raw[i].content.length + ' 字，超过 ' +
        KNOWLEDGE_CONTENT_MAX + ' 字上限');
      continue;
    }
    if (knowledgeTitleTaken(accepted, title, '')) {
      skipped.push('『' + title + '』：文件里有重名条目');
      continue;
    }
    let keywords: string = raw[i].keywords;
    if (keywords.length > KNOWLEDGE_KEYWORDS_MAX) {
      keywords = keywords.substring(0, safeKnowledgeCut(keywords, KNOWLEDGE_KEYWORDS_MAX));
      clippedKeywords++;
    }
    importable.push({ title: title, keywords: keywords, content: raw[i].content,
      source: raw[i].source === 'assistant' ? 'assistant' : 'user' });
    accepted.push({ id: 'f' + i, bookId: '', title: title, keywords: keywords,
      content: raw[i].content, createdAt: 0, sortOrder: 0 });
  }
  return { importable: importable, skipped: skipped, clippedKeywords: clippedKeywords };
}

// 导出文件名清洗（非法字符 → _、截 40、去首尾点与空格、空名与纯点段兜底「知识库」；照
// SkillText.skillPackDirName 形制加首尾点剥离）。★ 单源：导出侧文件名与导入侧失败提示共用，
// 禁两处各写一套
export function knowledgeFileName(bookName: string): string {
  const safe: string = bookName.replace(/[\\/:*?"<>|]/g, '_').replace(/^[.\s]+|[.\s]+$/g, '');
  const cut: string = safe.substring(0, safeKnowledgeCut(safe, 40));
  return cut === '' ? '知识库' : cut;
}

// ── 审阅弹窗文案（§3.3）──
// ★ 结构上界是硬要求（照 SkillText.composeBatchImportPreview——弹窗 message 是无上限 Text，
// 长清单会把「导入 / 取消」两键顶出屏，技能笔真机预演实锤过一次）：条目名封顶 8 项（余下
// 「等 N 条」）、未导入封顶 3 条（余下计数）、每项截断。封顶档与技能域同值但**各域自持**
// （零 import 域拿不到对方常量，同款纪律同款理由）
const KNOWLEDGE_IMPORT_LIST_MAX: number = 8;
const KNOWLEDGE_IMPORT_SKIP_LIST_MAX: number = 3;
const KNOWLEDGE_IMPORT_NAME_MAX: number = 20;
const KNOWLEDGE_IMPORT_WARN_MAX: number = 40;
const KNOWLEDGE_IMPORT_WARN_NAME_MAX: number = 20;
// 安全提示句（导入弹窗恒末句——条目会进检索结果发给模型，导入前用户该过目）
const KNOWLEDGE_IMPORT_SAFETY_LINE: string =
  '条目内容会在助手检索知识库时发给模型，请确认内容可信后再导入。';

// 导入说明单条裁剪（名段压窄、原因保留——照 SkillText.clipImportWarning 同款两段式）
function clipKnowledgeWarn(warning: string): string {
  const sep: number = warning.indexOf('：');
  if (sep < 0) {
    return clipImportText(warning, KNOWLEDGE_IMPORT_WARN_MAX);
  }
  const name: string = warning.substring(0, sep);
  const reason: string = warning.substring(sep + 1);
  const shown: string = name.length > KNOWLEDGE_IMPORT_WARN_NAME_MAX ?
    clipImportText(name, KNOWLEDGE_IMPORT_WARN_NAME_MAX) : name;
  return clipImportText(shown + '：' + reason, KNOWLEDGE_IMPORT_WARN_MAX);
}

// 审阅弹窗文案：书名 + 条数 / 条目名清单 / 未导入逐条 / 截断计数 / **外部件附注** / 安全行恒末。
// notice 来自 parseKnowledgeBook（外部世界书链恒非空、自家格式恒空），**原样呈现**——本函数不做
// 取舍判断，只负责把它排在「截断计数」之后、安全行之前（安全行恒末是结构契约，钉在断言里）
export function composeKnowledgeImportPreview(name: string,
  screen: KnowledgeScreenResult, notice: string = ''): string {
  const parts: string[] = [];
  const total: number = screen.importable.length;
  const limit: number = Math.min(KNOWLEDGE_IMPORT_LIST_MAX, total);
  const lines: string[] = [];
  for (let i: number = 0; i < limit; i++) {
    lines.push((i + 1).toString() + '. ' + clipImportText(screen.importable[i].title,
      KNOWLEDGE_IMPORT_NAME_MAX));
  }
  if (total > limit) {
    lines[limit - 1] = lines[limit - 1] + ' 等 ' + total + ' 条';
  }
  parts.push('将新建知识库「' + name + '」，导入 ' + total + ' 条条目\n' + lines.join('\n'));
  if (screen.skipped.length > 0) {
    const shown: string[] = [];
    const keep: number = Math.min(KNOWLEDGE_IMPORT_SKIP_LIST_MAX, screen.skipped.length);
    for (let i: number = 0; i < keep; i++) {
      shown.push(clipKnowledgeWarn(screen.skipped[i]));
    }
    const more: string = screen.skipped.length > keep ?
      ' 等 ' + screen.skipped.length + ' 项' : '';
    parts.push(screen.skipped.length + ' 条未导入：\n- ' + shown.join('\n- ') + more);
  }
  if (screen.clippedKeywords > 0) {
    parts.push(screen.clippedKeywords + ' 条的关键词过长已截断');
  }
  if (notice !== '') {
    parts.push(notice);
  }
  parts.push(KNOWLEDGE_IMPORT_SAFETY_LINE);
  return parts.join('\n\n');
}
