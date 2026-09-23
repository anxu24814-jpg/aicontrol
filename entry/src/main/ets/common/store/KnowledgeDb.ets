// 知识库存储域（2026-09-21 世界书知识库首版，任务书-世界书知识库-20260921 执行）：三张表
// 的行读写——knowledge_books（库本体，一行一本）与 knowledge_entries（条目，一行一条）与
// knowledge_files（条目附件，见下「条目附件」条）。
// 表结构/迁移在 ChatDbMigrate.ets（v43）。**用户可见名一律「知识库」**，「世界书 / World
// Book / Lorebook」只出现在文档与代码注释里，不上屏。
//
// 语义：
// · 绑定粒度 = 全局库 + 助手引用：库与条目都存全局（本域三表），助手只存「启用了哪几本」的
//   id 集合（assistants.knowledge 列，解析/序列化在 KnowledgeText）。一本书可被多个助手复用。
// · 条目三字段 = 名称 title + 关键词 keywords（可选）+ 正文 content（v39 另加来源标签
//   source：'user' 用户写 / 'assistant' 助手写，只在 create 时定；UI 只标非默认行）。关键词
//   **只参与检索加权与展示，不接触发逻辑**——本版姿态是工具化检索（模型经 search_knowledge
//   按需查阅），没有关键词自动注入；字段先备好，将来若做关键词触发姿态免二次迁移。
// · ★ 条目附件（2026-09-23 知识库文件笔）：knowledge_files 第三张表，**一行一个条目的纯文本
//   附件**（挂条目不挂库，与技能附件挂技能行同构；件名条目内唯一，是模型取件的唯一定位键）。
//   三条边界与建表 SQL 注释互指：只存文本 / 不进检索索引与注入块 / 归属用 entryId。级联两路
//   都同事务：deleteEntry（单条）与 deleteBookCascade（整库，先预取条目 id 再 IN 删件）。
// · 写入口两路（2026-09-21 知识库第二笔下本起）：条目编辑页（source='user'）与
//   manage_knowledge 工具（source='assistant'）——两路共用下列原语，**本层不判权限也不判
//   上限**（页面与工具各自拦，见「上限与校验一律在调用方」条）。附件同理：写口 = 文件编辑页
//   与上传链（均在设置页），工具面只读（read_file）。
// · 本层只存取，**上限与内容校验一律在调用方**（页面拦新建、工具侧不判）——两处判定 =
//   两处漂移面，是既有域件（MemoryDb/SkillDb）已立的注释纪律。★ 例外 = 附件写入侧的两道硬拒
//  （件名查重 + 件数上限）：件名唯一是「模型按名取件」的正确性前提，不能靠调用方自觉
//  （SkillDb.insertSkillFile 同款口径）。
// · 删库级联：deleteBookCascade 在**一个事务**内删该书全部条目 + 其附件 + 清各助手 knowledge
//   列的引用 + 删书行（clearKnowledgeRefInAssistants 是模块内私有件、带 db 句柄、**不另起事务**
//   ——照 SkillDb.clearSkillRefInAssistants 形态；嵌套事务语义不赌）。
// · 纪元键 KNOWLEDGE_LIST_TICK_KEY：写点 = 本域各写函数收口处（增删改保存后广播）；
//   读点 = 库页 @StorageProp @Watch 重拉（SKILL_LIST_TICK_KEY 同款先例）。
import { relationalStore } from '@kit.ArkData';
import { nextMessageId, sharedRdbStore } from './ChatDb';
import { KNOWLEDGE_FILE_MAX_COUNT, KnowledgeBookItem, KnowledgeEntryItem,
  parseEnabledKnowledgeIds,
  serializeEnabledKnowledgeIds } from '../KnowledgeText';

// 库总数上限（宪法「数据有界」；库页「＋」新建键 push 前拦截 + 中文提示）
export const KNOWLEDGE_BOOK_MAX: number = 20;
// 单库条目数上限（书详情页「＋」拦截；100 × 单条 6000 字 = 单库正文上界 60 万字符——正文
// 上限 2026-09-21 第二笔放宽至 6000 后的随形口径）
export const KNOWLEDGE_ENTRY_MAX: number = 100;
// 单助手可启用知识库数上限（启用页第 11 个开关面直接拒；照 SKILL_ENABLED_MAX 口径）
export const KNOWLEDGE_ENABLED_MAX: number = 10;

// 知识库列表刷新广播键（AppStorage tick 递增；@Watch 对同值不触发故递增——MemoryDb/
// SkillDb 同款。读点 = 知识库库页 + 书详情页）
export const KNOWLEDGE_LIST_TICK_KEY: string = 'knowledgeListTick';

export interface KnowledgeBookRow {
  id: string;
  name: string;
  createdAt: number;
  updatedAt: number;
  sortOrder: number; // 卡片自定义序（列表序单一来源，新条目落 max+1 卡底）
}

export interface KnowledgeEntryRow {
  id: string;
  bookId: string; // 归属知识库（随库删除同事务级联删行）
  title: string;
  keywords: string; // 可选；'' = 只按名称与正文检索
  content: string;
  // 来源标签（v39，2026-09-21 知识库第二笔下本）：'user' = 用户写 / 'assistant' = 助手写。
  // ★ 只在 create 时定（insertEntry 第三形参），update 不改（来源不随后续编辑翻转——技能库
  // skills.source 同口径）。★ 本列**只活在行层与 UI 层**：纯函数域的 KnowledgeEntryItem
  // 刻意不带它（那是检索打分与拼装的最小形态，来源字段与打分无关），故 toEntryItem 不透传
  source: string;
  createdAt: number;
  updatedAt: number;
  sortOrder: number;
}

// 条目写入入参（id/时间戳/归属由本域生成或调用方传入；title 必填由页面校验——本层不判）
export interface KnowledgeEntryInput {
  title: string;
  keywords: string;
  content: string;
}

// ── 纯函数域形态适配（知识库文本域是零 import 域——不引 DB 类型是它的可测性前提，而 ArkTS
//    禁结构类型（arkts-no-structural-typing）故行不能直喂纯函数；本组 = 单点适配，
//    ToolMemoryManage.toManageItems / SkillBriefItem 同款口径）──
export function toEntryItem(row: KnowledgeEntryRow): KnowledgeEntryItem {
  return {
    id: row.id, bookId: row.bookId, title: row.title, keywords: row.keywords,
    content: row.content, createdAt: row.createdAt, sortOrder: row.sortOrder
  };
}

export function toEntryItems(rows: KnowledgeEntryRow[]): KnowledgeEntryItem[] {
  const items: KnowledgeEntryItem[] = [];
  for (const row of rows) {
    items.push(toEntryItem(row));
  }
  return items;
}

export function toBookItems(rows: KnowledgeBookRow[]): KnowledgeBookItem[] {
  const items: KnowledgeBookItem[] = [];
  for (const row of rows) {
    items.push({ id: row.id, name: row.name });
  }
  return items;
}

const BOOK_COLUMNS: string[] = ['id', 'name', 'createdAt', 'updatedAt', 'sortOrder'];
const ENTRY_COLUMNS: string[] = ['id', 'bookId', 'title', 'keywords', 'content', 'source',
  'createdAt', 'updatedAt', 'sortOrder'];

function requireStore(): relationalStore.RdbStore {
  return sharedRdbStore();
}

function readBookRow(result: relationalStore.ResultSet): KnowledgeBookRow {
  return {
    id: result.getString(result.getColumnIndex('id')),
    name: result.getString(result.getColumnIndex('name')),
    createdAt: result.getLong(result.getColumnIndex('createdAt')),
    updatedAt: result.getLong(result.getColumnIndex('updatedAt')),
    sortOrder: result.getLong(result.getColumnIndex('sortOrder'))
  };
}

function readEntryRow(result: relationalStore.ResultSet): KnowledgeEntryRow {
  return {
    id: result.getString(result.getColumnIndex('id')),
    bookId: result.getString(result.getColumnIndex('bookId')),
    title: result.getString(result.getColumnIndex('title')),
    keywords: result.getString(result.getColumnIndex('keywords')),
    content: result.getString(result.getColumnIndex('content')),
    source: result.getString(result.getColumnIndex('source')),
    createdAt: result.getLong(result.getColumnIndex('createdAt')),
    updatedAt: result.getLong(result.getColumnIndex('updatedAt')),
    sortOrder: result.getLong(result.getColumnIndex('sortOrder'))
  };
}

// ── 库本体 ──

// 全量知识库（库页渲染源；三键排序 sortOrder → createdAt → id——第二三键 = 并列项确定性
// 兜底，不赌 SQL 对并列键的返回序，MemoryDb.queryMemories 同精神；上限 20 条自然有界）
export async function queryBooks(): Promise<KnowledgeBookRow[]> {
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('knowledge_books');
  predicates.orderByAsc('sortOrder');
  predicates.orderByAsc('createdAt');
  predicates.orderByAsc('id');
  const result: relationalStore.ResultSet = await requireStore().query(predicates, BOOK_COLUMNS);
  const rows: KnowledgeBookRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push(readBookRow(result));
    }
  } finally {
    result.close();
  }
  return rows;
}

// 库总数（上限守卫用；COUNT 直查不拉行）
export async function countBooks(): Promise<number> {
  const result: relationalStore.ResultSet =
    await requireStore().querySql('SELECT COUNT(*) AS n FROM knowledge_books');
  try {
    if (result.goToNextRow()) {
      return result.getLong(result.getColumnIndex('n'));
    }
    return 0;
  } finally {
    result.close();
  }
}

// 单本知识库（书详情页取书名、编辑链回填；查不到返回 null——调用方 toast 后返回上一页）
export async function queryBook(id: string): Promise<KnowledgeBookRow | null> {
  if (id === '') {
    return null;
  }
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('knowledge_books');
  predicates.equalTo('id', id);
  const result: relationalStore.ResultSet = await requireStore().query(predicates, BOOK_COLUMNS);
  try {
    if (result.goToNextRow()) {
      return readBookRow(result);
    }
    return null;
  } finally {
    result.close();
  }
}

// 新建知识库（库页「＋」→ 命名弹窗保存；上限守卫与名称非空校验在调用方——本层不判）。
// sortOrder = 当前 max + 1 落卡底（★ COALESCE 显式兜底空表：MAX 空表返回一行 NULL，
// 值读取对 NULL 行为官方无文档——不赌未文档化行为，SQL 层显式归 0，insertMemory 同款）
export async function insertBook(name: string): Promise<KnowledgeBookRow> {
  const now: number = Date.now();
  const maxResult: relationalStore.ResultSet = await requireStore().querySql(
    'SELECT COALESCE(MAX(sortOrder), 0) AS m FROM knowledge_books');
  let nextOrder: number = 0;
  try {
    if (maxResult.goToNextRow()) {
      nextOrder = maxResult.getLong(maxResult.getColumnIndex('m')) + 1;
    }
  } finally {
    maxResult.close();
  }
  const full: KnowledgeBookRow = {
    id: nextMessageId('kbook'),
    name: name,
    createdAt: now,
    updatedAt: now,
    sortOrder: nextOrder
  };
  const bucket: relationalStore.ValuesBucket = {
    'id': full.id, 'name': full.name, 'createdAt': full.createdAt,
    'updatedAt': full.updatedAt, 'sortOrder': full.sortOrder
  };
  await requireStore().insert('knowledge_books', bucket);
  return full;
}

// 改书名（库页行菜单「重命名」→ 弹窗保存）。0 行 affected 抛中文错 = P0-1 假成功防御
//（目标行已被删时调用方 toast「已重命名」= 撒谎；updateMemoryContent 同款）
export async function renameBook(id: string, name: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'name': name, 'updatedAt': Date.now() };
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('knowledge_books');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标知识库不存在（已被删除），重命名未生效');
  }
}

// 删除知识库并级联（库页行菜单「删除」→ 确认弹窗后）：同一事务内 = 删该书全部条目 + 其
// 附件（knowledge_files，2026-09-23 文件笔接线）+ 清各助手 knowledge 列对该书的引用 + 删书行，
// 保证「库与其条目、附件同生共死」不产生半删状态（deleteSkill 事务三件套同款）。留着引用 id
// 会让启用页的计数指着不存在的东西——清列是主通道，读取侧「启用 ∩ 现存」过滤是第二道保险。
// ★ 附件删除走「先预取条目 id（事务外一次只读）→ 事务内 in('entryId', ids) 删」：谓词层没有
// JOIN，两段式是既有先例（AssistantDb.deleteAssistantCascade 同款形态）；条目 id 数量上界 =
// 单库 100 条，IN 列表代价可忽略
export async function deleteBookCascade(id: string): Promise<void> {
  const db: relationalStore.RdbStore = requireStore();
  const entryPredicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('knowledge_entries');
  entryPredicates.equalTo('bookId', id);
  const entryResult: relationalStore.ResultSet = await db.query(entryPredicates, ['id']);
  const entryIds: string[] = [];
  try {
    while (entryResult.goToNextRow()) {
      entryIds.push(entryResult.getString(entryResult.getColumnIndex('id')));
    }
  } finally {
    entryResult.close();
  }
  db.beginTransaction();
  try {
    if (entryIds.length > 0) {
      const filePredicates: relationalStore.RdbPredicates =
        new relationalStore.RdbPredicates('knowledge_files');
      filePredicates.in('entryId', entryIds);
      await db.delete(filePredicates);
    }
    const entryDeletePredicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('knowledge_entries');
    entryDeletePredicates.equalTo('bookId', id);
    await db.delete(entryDeletePredicates);
    const bookPredicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('knowledge_books');
    bookPredicates.equalTo('id', id);
    await db.delete(bookPredicates);
    await clearKnowledgeRefInAssistants(db, id);
    db.commit();
  } catch (e) {
    db.rollBack();
    throw e as Error;
  }
}

// ── 条目 ──

// 某库全部条目（书详情页渲染源；三键排序 sortOrder → createdAt → id，并列确定性兜底同
// queryBooks；单库 ≤100 条自然有界无翻页）
export async function queryEntries(bookId: string): Promise<KnowledgeEntryRow[]> {
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('knowledge_entries');
  predicates.equalTo('bookId', bookId);
  predicates.orderByAsc('sortOrder');
  predicates.orderByAsc('createdAt');
  predicates.orderByAsc('id');
  const result: relationalStore.ResultSet = await requireStore().query(predicates, ENTRY_COLUMNS);
  const rows: KnowledgeEntryRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push(readEntryRow(result));
    }
  } finally {
    result.close();
  }
  return rows;
}

// 该库条数（书详情页「＋」上限守卫 + 列表副行说明；COUNT 直查不拉行）
export async function countEntries(bookId: string): Promise<number> {
  const result: relationalStore.ResultSet = await requireStore().querySql(
    'SELECT COUNT(*) AS n FROM knowledge_entries WHERE bookId = ?', [bookId]);
  try {
    if (result.goToNextRow()) {
      return result.getLong(result.getColumnIndex('n'));
    }
    return 0;
  } finally {
    result.close();
  }
}

// 多库各自条数（**两处行副行**用：知识库库页行「N 条条目」+ 助手知识库页行副标题；一次
// GROUP BY 查回，**禁逐库查**——P1-2 轻量检测纪律）。入参空数组直接返回空表（禁拼 IN ()
// ——非法 SQL，同 queryEntriesByBookIds）。返回 Map<bookId, count>：查不到 = 该库 0 条
//（调用方按 0 兜底）。★ 工具 list 动作**不消费本函数**（头行「共 M 条条目」的 M = 条目池
// 行数，逐库明细只印书名与标题——2026-09-21 自检轮订正原注释的错挂消费方）
export async function countEntriesOfBooks(bookIds: string[]): Promise<Map<string, number>> {
  const counts: Map<string, number> = new Map<string, number>();
  if (bookIds.length === 0) {
    return counts;
  }
  const placeholders: string = bookIds.map((item: string): string => '?').join(',');
  const result: relationalStore.ResultSet = await requireStore().querySql(
    'SELECT bookId, COUNT(*) AS n FROM knowledge_entries WHERE bookId IN (' + placeholders +
    ') GROUP BY bookId', bookIds);
  try {
    while (result.goToNextRow()) {
      counts.set(result.getString(result.getColumnIndex('bookId')),
        result.getLong(result.getColumnIndex('n')));
    }
  } finally {
    result.close();
  }
  return counts;
}

// 单条条目（条目编辑页回填；查不到返回 null——调用方按新增兜底提示，queryMemory 同款）
export async function queryEntry(id: string): Promise<KnowledgeEntryRow | null> {
  if (id === '') {
    return null;
  }
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('knowledge_entries');
  predicates.equalTo('id', id);
  const result: relationalStore.ResultSet = await requireStore().query(predicates, ENTRY_COLUMNS);
  try {
    if (result.goToNextRow()) {
      return readEntryRow(result);
    }
    return null;
  } finally {
    result.close();
  }
}

// 多库条目池（工具检索面：一次 SQL 取启用知识库的全部条目——**禁逐库查**，P1-2）。
// 排序三键与 queryEntries 同源（打分并列项要按卡序稳定）。★ 入参空数组直接返回空表：
// 空 IN 列表在 SQL 层是**非法语句**会抛错，而「未启用任何知识库」是正常态（调用方另有
// 引导串），不能让它变成异常路径
export async function queryEntriesByBookIds(bookIds: string[]): Promise<KnowledgeEntryRow[]> {
  if (bookIds.length === 0) {
    return [];
  }
  const placeholders: string = bookIds.map((item: string): string => '?').join(',');
  const result: relationalStore.ResultSet = await requireStore().querySql(
    'SELECT id, bookId, title, keywords, content, source, createdAt, updatedAt, sortOrder ' +
    'FROM knowledge_entries WHERE bookId IN (' + placeholders + ') ' +
    'ORDER BY sortOrder ASC, createdAt ASC, id ASC', bookIds);
  const rows: KnowledgeEntryRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push(readEntryRow(result));
    }
  } finally {
    result.close();
  }
  return rows;
}

// 新增条目（条目编辑页保存新增态，与 manage_knowledge 工具 create 共用本原语）：
// sortOrder = **该库内** max + 1 落卡底（同 insertMemory 的 COALESCE 兜底与查后即写非事务
// 窗口——并发极端下并列由三键兜底序收敛）。★ source 为第三形参**必传**（'user' = 用户在
// 编辑页写 / 'assistant' = 助手经工具写）：不给默认值 = 每个调用点都必须显式表态来源，
// 防新人加调用点时静默落一个错来源（取值面与语义见 KnowledgeEntryRow.source 注释）
export async function insertEntry(bookId: string, input: KnowledgeEntryInput,
  source: string): Promise<KnowledgeEntryRow> {
  const now: number = Date.now();
  const maxResult: relationalStore.ResultSet = await requireStore().querySql(
    'SELECT COALESCE(MAX(sortOrder), 0) AS m FROM knowledge_entries WHERE bookId = ?', [bookId]);
  let nextOrder: number = 0;
  try {
    if (maxResult.goToNextRow()) {
      nextOrder = maxResult.getLong(maxResult.getColumnIndex('m')) + 1;
    }
  } finally {
    maxResult.close();
  }
  const full: KnowledgeEntryRow = {
    id: nextMessageId('kentry'),
    bookId: bookId,
    title: input.title,
    keywords: input.keywords,
    content: input.content,
    source: source,
    createdAt: now,
    updatedAt: now,
    sortOrder: nextOrder
  };
  const bucket: relationalStore.ValuesBucket = {
    'id': full.id, 'bookId': full.bookId, 'title': full.title, 'keywords': full.keywords,
    'content': full.content, 'source': full.source, 'createdAt': full.createdAt,
    'updatedAt': full.updatedAt, 'sortOrder': full.sortOrder
  };
  await requireStore().insert('knowledge_entries', bucket);
  return full;
}

// 修改条目（条目编辑页保存编辑态，与 manage_knowledge 工具 update 共用本原语；卡序下编辑
// 原地不动——sortOrder 不写，updatedAt 仅刷新为数据字段）。★ **不写 source**（bucket 恰四键
// ——来源标签只在 create 时定，编辑不翻转；技能库 updateSkill 同款）。0 行 affected 抛中文错
// = P0-1 假成功防御（updateMemoryContent 同款）
export async function updateEntry(id: string, input: KnowledgeEntryInput): Promise<void> {
  const bucket: relationalStore.ValuesBucket = {
    'title': input.title, 'keywords': input.keywords, 'content': input.content,
    'updatedAt': Date.now()
  };
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('knowledge_entries');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标条目不存在（已被删除），保存未生效');
  }
}

// 删除单条条目（书详情页行菜单「删除」→ 确认弹窗后；manage_knowledge 的 delete 动作同用）：
// 同一事务内 = 删该条目的附件（knowledge_files 级联，2026-09-23 文件笔接线）+ 删条目行——
// 条目没了附件就是孤儿（既不进任何清单，也再没有取件入口：件名定位要先定位到条目），
// 与删技能级联删附件同款语义
export async function deleteEntry(id: string): Promise<void> {
  const db: relationalStore.RdbStore = requireStore();
  const filePredicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('knowledge_files');
  filePredicates.equalTo('entryId', id);
  const entryPredicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('knowledge_entries');
  entryPredicates.equalTo('id', id);
  db.beginTransaction();
  try {
    await db.delete(filePredicates);
    await db.delete(entryPredicates);
    db.commit();
  } catch (e) {
    db.rollBack();
    throw e as Error;
  }
}

// ── 条目附件文件（knowledge_files，2026-09-23 知识库文件笔）──
// 一行一个条目的纯文本附件。写入口 = 文件编辑页（新建/上传两条路都经它保存）；**工具面只读**
// （manage_knowledge 的 read_file）。与技能附件族（SkillDb 附件节）刻意各持一份：形态同、
// 域不同（件名查重的范围是「本条目内」，上限常量、行形状、级联点都各自一套）。
// 上限 KNOWLEDGE_FILE_MAX_COUNT / 内容 KNOWLEDGE_FILE_CONTENT_MAX 同 KnowledgeText 常量单源。

export const KNOWLEDGE_FILE_FULL_TIP: string = '每个条目最多附 ' + KNOWLEDGE_FILE_MAX_COUNT +
  ' 个文件，请先删除不再需要的文件。';

export interface KnowledgeFileRow {
  id: string;
  entryId: string;
  name: string;
  content: string;
  sortOrder: number;
  createdAt: number;
}

const KNOWLEDGE_FILE_COLUMNS: string[] = ['id', 'entryId', 'name', 'content', 'sortOrder',
  'createdAt'];

function readKnowledgeFileRow(result: relationalStore.ResultSet): KnowledgeFileRow {
  return {
    id: result.getString(result.getColumnIndex('id')),
    entryId: result.getString(result.getColumnIndex('entryId')),
    name: result.getString(result.getColumnIndex('name')),
    content: result.getString(result.getColumnIndex('content')),
    sortOrder: result.getLong(result.getColumnIndex('sortOrder')),
    createdAt: result.getLong(result.getColumnIndex('createdAt'))
  };
}

// 某条目的全部附件（文件卡行序 + 工具 get 回执件名序 + read_file 定位面**三处同源**，故两键
// 确定性排序：sortOrder → name；每条目 ≤10 件自然有界无翻页）
export async function queryEntryFiles(entryId: string): Promise<KnowledgeFileRow[]> {
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('knowledge_files');
  predicates.equalTo('entryId', entryId);
  predicates.orderByAsc('sortOrder');
  predicates.orderByAsc('name');
  const result: relationalStore.ResultSet =
    await requireStore().query(predicates, KNOWLEDGE_FILE_COLUMNS);
  const rows: KnowledgeFileRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push(readKnowledgeFileRow(result));
    }
  } finally {
    result.close();
  }
  return rows;
}

// 单件附件（文件编辑页回填用；查不到返回 null——调用方按不存在兜底提示）
export async function queryEntryFile(id: string): Promise<KnowledgeFileRow | null> {
  if (id === '') {
    return null;
  }
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('knowledge_files');
  predicates.equalTo('id', id);
  const result: relationalStore.ResultSet =
    await requireStore().query(predicates, KNOWLEDGE_FILE_COLUMNS);
  try {
    if (result.goToNextRow()) {
      return readKnowledgeFileRow(result);
    }
    return null;
  } finally {
    result.close();
  }
}

// 件数（上限守卫 + 文件卡计数用；COUNT 直查不拉行）
export async function countEntryFiles(entryId: string): Promise<number> {
  const result: relationalStore.ResultSet = await requireStore().querySql(
    'SELECT COUNT(*) AS n FROM knowledge_files WHERE entryId = ?', [entryId]);
  try {
    if (result.goToNextRow()) {
      return result.getLong(result.getColumnIndex('n'));
    }
    return 0;
  } finally {
    result.close();
  }
}

// 新增附件（文件编辑页「新建文件」保存 /「上传文件」入库）：先校验父条目仍在 → 查同名
//（excludeId='' = 不排除自己）→ 件数上限 → sortOrder = 卡底。三处拒绝都抛中文错，调用方
// toast（P0-1 不静默）。
// ★ 父条目校验（2026-09-23 自检补）：条目可能在文件编辑页打开期间被别处删掉（工具轮
// manage_knowledge 的 delete 等，页内栈挡不住），此时写入会落一行无父的悬空附件行——删条目与
// 删库都只按「现存条目 id」清件，这行此后没有任何删除链能清掉，故宁可在写入前拒。
// ★ 另两道硬拒放在本层而不在页面：件名是本条目内「模型按名取件」的唯一定位键，同名两件会让
// 「取到哪一份」不可预期（SkillDb.insertSkillFile 同款理由）；页面只做入口拦截与文案提示
export async function insertEntryFile(entryId: string, name: string,
  content: string): Promise<KnowledgeFileRow> {
  const owner: KnowledgeEntryRow | null = await queryEntry(entryId);
  if (owner === null) {
    throw new Error('条目不存在或已删除，保存未生效');
  }
  await assertEntryFileNameFree(entryId, name, '');
  const count: number = await countEntryFiles(entryId);
  if (count >= KNOWLEDGE_FILE_MAX_COUNT) {
    throw new Error(KNOWLEDGE_FILE_FULL_TIP);
  }
  const now: number = Date.now();
  const maxResult: relationalStore.ResultSet = await requireStore().querySql(
    'SELECT COALESCE(MAX(sortOrder), 0) AS m FROM knowledge_files WHERE entryId = ?', [entryId]);
  let nextOrder: number = 0;
  try {
    if (maxResult.goToNextRow()) {
      nextOrder = maxResult.getLong(maxResult.getColumnIndex('m')) + 1;
    }
  } finally {
    maxResult.close();
  }
  const row: KnowledgeFileRow = {
    id: nextMessageId('kfile'),
    entryId: entryId,
    name: name,
    content: content,
    sortOrder: nextOrder,
    createdAt: now
  };
  const bucket: relationalStore.ValuesBucket = {
    'id': row.id, 'entryId': row.entryId, 'name': row.name, 'content': row.content,
    'sortOrder': row.sortOrder, 'createdAt': row.createdAt
  };
  await requireStore().insert('knowledge_files', bucket);
  return row;
}

// 修改附件（文件编辑页保存；改内容或改名——改名同样查重，排除自己这条）。
// 0 行 throw = P0-1 假成功防御（同 updateEntry）
export async function updateEntryFile(id: string, entryId: string, name: string,
  content: string): Promise<void> {
  await assertEntryFileNameFree(entryId, name, id);
  const bucket: relationalStore.ValuesBucket = { 'name': name, 'content': content };
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('knowledge_files');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标文件不存在（已被删除），保存未生效');
  }
}

// 删除附件（文件卡行内删除键 / 文件编辑页底部删除键）：只删这一行——条目本身与助手启用集
// 都不受影响（文件不在任何启用语义内）
export async function deleteEntryFile(id: string): Promise<void> {
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('knowledge_files');
  predicates.equalTo('id', id);
  await requireStore().delete(predicates);
}

// 同名件拒绝（写入侧硬约束；excludeId 用于「改名时排除自己」）：命中即抛中文错带件名——
// 用户知道该改哪一个，模型也永远拿不到歧义清单
async function assertEntryFileNameFree(entryId: string, name: string,
  excludeId: string): Promise<void> {
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('knowledge_files');
  predicates.equalTo('entryId', entryId);
  predicates.equalTo('name', name);
  const result: relationalStore.ResultSet = await requireStore().query(predicates, ['id']);
  let hit: boolean = false;
  try {
    while (result.goToNextRow()) {
      if (result.getString(result.getColumnIndex('id')) !== excludeId) {
        hit = true;
        break;
      }
    }
  } finally {
    result.close();
  }
  if (hit) {
    throw new Error('已存在名为「' + name + '」的文件，换一个文件名再试。');
  }
}

// 清助手引用（调用方须在事务内调——本函数不自开事务，便于与删库同一原子单位；
// SkillDb.clearSkillRefInAssistants 同款形态）：全表读 assistants 的 (id, knowledge) →
// 逐行解析剔除目标 id → **仅命中行**回写（未命中不写：删库不该动没启用过它的助手行）。
// JSON 列无法用 SQL 谓词下推「是否含该 id」，故只能全表遍历——助手数是用户手建小数据集
//（个位到十位），代价可忽略
async function clearKnowledgeRefInAssistants(db: relationalStore.RdbStore,
  bookId: string): Promise<void> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  const result: relationalStore.ResultSet = await db.query(predicates, ['id', 'knowledge']);
  const targetIds: string[] = [];
  const targetValues: string[] = [];
  try {
    while (result.goToNextRow()) {
      const raw: string = result.getString(result.getColumnIndex('knowledge'));
      const ids: string[] = parseEnabledKnowledgeIds(raw);
      if (!ids.includes(bookId)) {
        continue;
      }
      targetIds.push(result.getString(result.getColumnIndex('id')));
      targetValues.push(serializeEnabledKnowledgeIds(ids.filter((item: string): boolean =>
        item !== bookId)));
    }
  } finally {
    result.close();
  }
  for (let i: number = 0; i < targetIds.length; i++) {
    const bucket: relationalStore.ValuesBucket = { 'knowledge': targetValues[i] };
    const update: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
    update.equalTo('id', targetIds[i]);
    await db.update(bucket, update);
  }
}

// 列表刷新广播（tick 递增——@Watch 对同值不触发，递增保证每次触发）
export function broadcastKnowledgeList(): void {
  AppStorage.setOrCreate<number>(KNOWLEDGE_LIST_TICK_KEY,
    (AppStorage.get<number>(KNOWLEDGE_LIST_TICK_KEY) ?? 0) + 1);
}
