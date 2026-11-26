// 库页搜索过滤纯函数层：提示词库 / 技能库 / 知识库三页常显搜索框共用同一套「关键词归一 +
// 多字段任一命中」口径——三页只差**参与命中的字段**（按域名册见下），归一与匹配逻辑单源
// 在此，禁各页另写一份。
//
// · 空词 = 不过滤、返全量**副本**（与会话搜索页 / 设置搜索页「空词返空」有意相反：那两处是
//   提交式搜索，本族是常显实时框——空词返空会让用户清空输入后列表空掉 = 换不回全量）。
// · 命中 = 任一字段的子串包含；关键词先 trim、双侧 toLowerCase（大小写不敏感）。
// · **不是「只搜正文」**（本层立档的缘由，照记忆库「只匹 content」的口径有意放宽）：
//   提示词 = 名称 + 正文；技能 = 名称 + 触发描述 + 正文；知识库 = 书名（其书内条目命中是
//   **另一路**，由 countEntryHitsByBook 一条 SQL 出命中集，再从 filterBooksByKeyword 第三参进来）。
// · 关键词归一（trim + toLowerCase）用在内存侧匹配；SQL 侧不做大小写折叠（SQLite LIKE 对 ASCII
//   本身不区分大小写），只做通配符转义，见 buildLikePattern。
//
// 零 import 叶子件（同 MemoryText / KnowledgeText 范式）：node 侧断言可 copyFileSync 直跑线上
// 同一实现，不需剥桩。
export interface PromptSearchItem {
  name: string;
  content: string;
}

export interface SkillSearchItem {
  name: string;
  description: string;
  content: string;
}

export interface BookSearchItem {
  id: string;
  name: string;
}

// 关键词归一（空串判据的唯一来源——三个过滤函数与页面侧的空态分派都以「trim 后是否为空」为准）
export function normalizeSearchKeyword(keyword: string): string {
  return keyword.trim().toLowerCase();
}

// 多字段任一命中（字段面由各域过滤函数给；字段值可能为空串，空串恒不命中非空关键词）
function matchesAnyField(keyword: string, fields: string[]): boolean {
  for (const field of fields) {
    if (field.toLowerCase().includes(keyword)) {
      return true;
    }
  }
  return false;
}

// 提示词：名称 + 正文（行卡显示名称与正文摘要，两处都能被搜到——摘要本身是正文的前缀）
export function filterPromptsByKeyword<T extends PromptSearchItem>(items: T[],
  keyword: string): T[] {
  const kw: string = normalizeSearchKeyword(keyword);
  if (kw === '') {
    return items.slice();
  }
  const out: T[] = [];
  for (const item of items) {
    if (matchesAnyField(kw, [item.name, item.content])) {
      out.push(item);
    }
  }
  return out;
}

// 技能：名称 + 触发描述 + 正文（描述是行卡副行、正文只在编辑页可见——正文一并参与，才能按
// 「这件技能正文里写了什么」搜到，代价为零：全量技能已在内存，库上限 50 件）
export function filterSkillsByKeyword<T extends SkillSearchItem>(items: T[],
  keyword: string): T[] {
  const kw: string = normalizeSearchKeyword(keyword);
  if (kw === '') {
    return items.slice();
  }
  const out: T[] = [];
  for (const item of items) {
    if (matchesAnyField(kw, [item.name, item.description, item.content])) {
      out.push(item);
    }
  }
  return out;
}

// 知识库：书名 或 书内条目命中（entryHits 的键 = 有命中条目的书 id，值 = 命中条数——由
// countEntryHitsByBook 一条 SQL 出，传 Map 而非数组：调用方本就要用它的值渲染副行，避免每次
// 按键再转一次键集）。空词 = 全显（调用方据此跳过 SQL，不查库）
export function filterBooksByKeyword<T extends BookSearchItem>(books: T[], keyword: string,
  entryHits: Map<string, number>): T[] {
  const kw: string = normalizeSearchKeyword(keyword);
  if (kw === '') {
    return books.slice();
  }
  const out: T[] = [];
  for (const book of books) {
    if (book.name.toLowerCase().includes(kw) || entryHits.has(book.id)) {
      out.push(book);
    }
  }
  return out;
}

// SQL LIKE 模式构造（知识库「条目命中」那一路的唯一模式来源）：关键词内 % _ \ 前缀反斜杠，
// 再两端包 % ——用户把 % 当普通字符敲进来时不得退化成「匹配全部」；配对 SQL 恒写 ESCAPE '\'。
// ★ 关键词先 trim：纯空白与空串同义（调用方对空词本就不查库，此处是第二道）；不做 toLowerCase
// （SQLite LIKE 对 ASCII 本身不区分大小写）。仓内同形先例两处（ToolChatSearch.escapeChatLikeToken /
// ChatDb 检索链），本处为第三处——存量两处不追改（存量不溯及，禁顺手重构）
export function buildLikePattern(keyword: string): string {
  return '%' + keyword.trim().replace(/[%_\\]/g, '\\$&') + '%';
}
