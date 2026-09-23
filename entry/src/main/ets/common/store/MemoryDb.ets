// 记忆存储域（2026-09-08 记忆域新建，照 PromptTemplateDb 域拆先例）：memories 表行读写。
// 表结构/迁移在 ChatDbMigrate.ets（v20），语义：
// · 一行一条稳定事实；source 'auto' = 退出会话自动整理（MemoryGen）/ 'manual' = 记忆页
//   手动添加（经记忆编辑页保存）；assistantId = 沉淀来源助手（'' = 无归属，仅展示用——
//   删助手级联置空 clearMemoryAssistantRef，不删行）；conversationId = 来源会话（仅追溯，
//   删会话不级联——记忆是跨会话资产）；
// · 有界红线（宪法「数据有界」）：库内 ≤ MEMORY_MAX_TOTAL 条（自动整理达上限跳过新增
//   + hilog；手动添加超限由记忆页「＋」新建键 push 前拦截提示）、单条 ≤ 500 字
//   （MEMORY_CONTENT_MAX，解析侧截断 + 记忆编辑页 maxLength 同源）；
// · 导出导入 = ExportImport EXPORT_TABLES 含 memories（列过滤天然跨版本兼容）；
// · 记忆优化批量应用 = applyMemoryOptChanges（2026-09-11 记忆优化模型，一个事务内改内容 +
//   删被并入行；校验在纯函数层 buildMemoryOptPlan，本层只落库）；
// · 纪元键 MEMORY_LIST_TICK_KEY：写点 = MemoryGen 整理成功（自动/手动两链同走
//   runMemorySinking，收口一处）；读点 = MemoryPage @StorageProp @Watch（CONV_TITLE_TICK
//   同款先例）。记忆页增删改不走广播——写点在同页（删）或子页（增改），onPop 重拉即达。
// · 助手级记忆域（2026-09-20 助手级记忆，v35）：assistant_memories 表——assistant_id =
//   **归属语义**（与 memories.assistantId 的「沉淀来源标注」语义刻意分离，两库不混注）；
//   行 id 由 nextMessageId('asmem') 生成，形态 `asmem-<时间戳>-<序号>`（全局 `mem-` 同形）
//   ——前缀只供人读，**跨库隔离的真实机制 = 定位集锁本库**（管理与检索面一律先按作用域
//   查目标库，命中集合只在本库内；全仓无任何按 id 前缀判库的代码）。作用域
//   二选一常量 MEMORY_SCOPE_*（助手列 assistants.memoryScope，'global' = 全局库 = memories
//   表路径零改动）。上限同口径库级独立计数（MEMORY_MAX_TOTAL / MEMORY_CONTENT_MAX 复用）。
import { relationalStore } from '@kit.ArkData';
import { nextMessageId, sharedRdbStore } from './ChatDb';
import { MemoryOptChange } from '../MemoryText';

// 库内总条数上限（宪法数据有界；达上限自动整理跳过新增、手动添加拦截）
export const MEMORY_MAX_TOTAL: number = 200;

// 记忆列表刷新广播键（AppStorage tick 递增；写点 = 记忆页写操作收口处，读点 = 记忆页
// @StorageProp @Watch 重拉——退页自动整理回页可见）
export const MEMORY_LIST_TICK_KEY: string = 'memoryListTick';

// 助手记忆作用域枚举（assistants.memoryScope 列值域；'global' 默认 = 存量行为原样）。
// 消费全集 = 注入选库（ChatSendCtrl/ProactiveGen）/ 沉淀落库（MemoryGen）/ 工具检索
// （SearchMemoryExecutor、ToolMemoryManage）/ UI 分段胶囊（AssistantMemoryPage）
export const MEMORY_SCOPE_GLOBAL: string = 'global';
export const MEMORY_SCOPE_ASSISTANT: string = 'assistant';

export interface MemoryRow {
  id: string;
  content: string;
  source: string; // 'auto' | 'manual' | 'import'（建表无 CHECK 约束，值域靠写入侧与 memorySourceLabel 映射）
  assistantId: string;
  conversationId: string;
  createdAt: number;
  updatedAt: number;
  sortOrder: number; // 卡片自定义序（v29；存量 0 = createdAt/content 兜底序）
}

// 新增入参（id/时间戳本域生成；MemoryGen 与记忆页「＋」新建共用）
export interface MemoryInsertInput {
  content: string;
  source: string;
  assistantId: string;
  conversationId: string;
}

function requireStore(): relationalStore.RdbStore {
  return sharedRdbStore();
}

// 全量记忆（卡片序 = 列表序 + 注入选取序 + 注入块排列序 + 优化序号基准，四路消费同源；
// 三键排序：sortOrder 升序 → createdAt 升序 → content 升序——第二三键 = 并列条目确定性
// 兜底，与旧 compareMemoryOrder 的 tiebreak 同口径，是「存量 sortOrder 全 0 时注入块字符串
// 零漂移」的成立前提〔只双键时 SQL 对并列键返回序不定〕；上限 200 条自然有界无翻页）
export async function queryMemories(): Promise<MemoryRow[]> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('memories');
  predicates.orderByAsc('sortOrder');
  predicates.orderByAsc('createdAt');
  predicates.orderByAsc('content');
  const columns: string[] = ['id', 'content', 'source', 'assistantId', 'conversationId',
    'createdAt', 'updatedAt', 'sortOrder'];
  const result: relationalStore.ResultSet = await requireStore().query(predicates, columns);
  const rows: MemoryRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        id: result.getString(result.getColumnIndex('id')),
        content: result.getString(result.getColumnIndex('content')),
        source: result.getString(result.getColumnIndex('source')),
        assistantId: result.getString(result.getColumnIndex('assistantId')),
        conversationId: result.getString(result.getColumnIndex('conversationId')),
        createdAt: result.getLong(result.getColumnIndex('createdAt')),
        updatedAt: result.getLong(result.getColumnIndex('updatedAt')),
        sortOrder: result.getLong(result.getColumnIndex('sortOrder'))
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// 库内总条数（上限守卫用；COUNT 直查不拉行）
export async function countMemories(): Promise<number> {
  const result: relationalStore.ResultSet =
    await requireStore().querySql('SELECT COUNT(*) AS n FROM memories');
  try {
    if (result.goToNextRow()) {
      return result.getLong(result.getColumnIndex('n'));
    }
    return 0;
  } finally {
    result.close();
  }
}

// 单条记忆（记忆编辑页回填用；查不到返回 null——调用方按新增兜底提示，queryTemplate 同款）
export async function queryMemory(id: string): Promise<MemoryRow | null> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('memories');
  predicates.equalTo('id', id);
  const columns: string[] = ['id', 'content', 'source', 'assistantId', 'conversationId',
    'createdAt', 'updatedAt', 'sortOrder'];
  const result: relationalStore.ResultSet = await requireStore().query(predicates, columns);
  try {
    if (result.goToNextRow()) {
      return {
        id: result.getString(result.getColumnIndex('id')),
        content: result.getString(result.getColumnIndex('content')),
        source: result.getString(result.getColumnIndex('source')),
        assistantId: result.getString(result.getColumnIndex('assistantId')),
        conversationId: result.getString(result.getColumnIndex('conversationId')),
        createdAt: result.getLong(result.getColumnIndex('createdAt')),
        updatedAt: result.getLong(result.getColumnIndex('updatedAt')),
        sortOrder: result.getLong(result.getColumnIndex('sortOrder'))
      };
    }
    return null;
  } finally {
    result.close();
  }
}

// 新增单条（上限守卫在调用方——自动链 MemoryGen 跳过 + 留痕、手动链记忆页「＋」新建键拦截 + toast）；
// sortOrder = 当前 max + 1（落卡底——与用户新建/自动整理一致；查后即写非事务，与
// insertProvider 的 max+1 同款窗口：并发插入极端下并列 sortOrder 由 createdAt/content
// 兜底序收敛，不破坏确定性）。★ COALESCE 显式兜底空表（2026-09-12 复盘轮：MAX 空表
// 返回一行 NULL，值读取对 NULL 的行为官方无文档——不赌未文档化行为，SQL 层显式归 0）
export async function insertMemory(row: MemoryInsertInput): Promise<MemoryRow> {
  const now: number = Date.now();
  const maxResult: relationalStore.ResultSet =
    await requireStore().querySql('SELECT COALESCE(MAX(sortOrder), 0) AS m FROM memories');
  let nextOrder: number = 0;
  try {
    if (maxResult.goToNextRow()) {
      nextOrder = maxResult.getLong(maxResult.getColumnIndex('m')) + 1;
    }
  } finally {
    maxResult.close();
  }
  const full: MemoryRow = {
    id: nextMessageId('mem'),
    content: row.content,
    source: row.source,
    assistantId: row.assistantId,
    conversationId: row.conversationId,
    createdAt: now,
    updatedAt: now,
    sortOrder: nextOrder
  };
  const bucket: relationalStore.ValuesBucket = {
    'id': full.id, 'content': full.content, 'source': full.source,
    'assistantId': full.assistantId, 'conversationId': full.conversationId,
    'createdAt': full.createdAt, 'updatedAt': full.updatedAt, 'sortOrder': full.sortOrder
  };
  await requireStore().insert('memories', bucket);
  return full;
}

// 持久化卡片序（排序页拖拽落定后整表回写 sortOrder = 数组下标——saveProviderOrder 同形制；
// 全表 ≤ 200 行逐行 UPDATE 开销可忽略）
export async function saveMemoryOrder(ids: string[]): Promise<void> {
  for (let i = 0; i < ids.length; i++) {
    const bucket: relationalStore.ValuesBucket = { 'sortOrder': i };
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('memories');
    predicates.equalTo('id', ids[i]);
    await requireStore().update(bucket, predicates);
  }
}

// 编辑条目内容（记忆编辑页保存；卡序下编辑原地不动——updatedAt 仅刷新为数据字段与
// 「来源 · 更新时间」展示用，不再有列表重排序语义）
export async function updateMemoryContent(id: string, content: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'content': content, 'updatedAt': Date.now() };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('memories');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标记忆行不存在（已被删除），保存未生效');
  }
}

// 删除单条（记忆页删除键 → 确认弹窗后）
export async function deleteMemory(id: string): Promise<void> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('memories');
  predicates.equalTo('id', id);
  await requireStore().delete(predicates);
}

// 删助手级联置空（AssistantDb.deleteAssistantCascade 事务内调用——clearAssistantBinding
// 同款口径）：该助手沉淀的记忆保留、assistantId 归空（来源标注消失，内容是跨会话资产
// 不随助手删）
export async function clearMemoryAssistantRef(assistantId: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'assistantId': '' };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('memories');
  predicates.equalTo('assistantId', assistantId);
  await requireStore().update(bucket, predicates);
}

// 列表刷新广播（tick 递增——@Watch 对同值不触发，递增保证每次触发）
export function broadcastMemoryList(): void {
  AppStorage.setOrCreate<number>(MEMORY_LIST_TICK_KEY,
    (AppStorage.get<number>(MEMORY_LIST_TICK_KEY) ?? 0) + 1);
}

// ── 记忆优化批量应用（2026-09-11 记忆优化模型，方案-记忆整理优化-20260911 §6.5「事务」防线）──
// 一次优化 = 若干条改动，每条 = 改写保留行内容（rewrite 的自身行 / merge 的首序号行）+
// 删除被并入行（merge 的其余行）。全部打包进一个 RDB 事务：任一步失败 rollBack 整体回滚，
// 中止即零改动，不产生「合并做了一半」的半成品库（deleteAssistantCascade 同款三件套）。
// ★ 上限与内容校验已在纯函数层完成（buildMemoryOptPlan：≤500 字 / 敏感过滤 / 去重键不撞车
// / 改动量闸门），本层只落库不二次判定——两处判定 = 两处漂移面。
// ★ 保留行缺失即抛错回滚（与 updateMemoryContent 的「affected === 0 抛错」同口径）：确认弹窗
// 打开期间库可能被别处改动（自动整理落库 / 用户在别的入口删条目），若保留行已不在，继续执行
// 就会「删掉被并入行却没人接住内容」= 静默丢数据；抛错 → rollBack → 整批零改动。
// ★ 卡序语义（v29）：改写保留行**原位不动**（sortOrder 不写）；删除被并入行后按改动后的
// 查询序把剩余条目重排为 0..n-1 连续（同事务收尾）——相对次序不变仅去空洞，防删出空洞后
// 并列 sortOrder 退化到 createdAt/content 兜底产生行为漂移（新插入的 max+1 也随之连续）。
// 旧「优化后集中在注入序前段」假设（方案 R7）随卡序退役——注入窗口跟卡片序走
// ★ 2026-09-22 记忆优化历史：第二参 snapshotNote = 历史页给人看的改动摘要（如「改写 3 条 ·
// 合并 2 组」），事务**第一步**先整库存档（archiveBeforeOptInTx）。拍快照与改动同生同死——
// 事务外先拍 = 优化失败会留下一份「什么都没变」的幽灵快照，白占一个名额；内联则优化成功
// ⟺ 快照存在。早退不变：空改动不入库也不写快照
export async function applyMemoryOptChanges(changes: MemoryOptChange[],
  snapshotNote: string): Promise<void> {
  if (changes.length === 0) {
    return;
  }
  const db: relationalStore.RdbStore = requireStore();
  const now: number = Date.now();
  db.beginTransaction();
  try {
    await archiveBeforeOptInTx(db, MEMORY_SCOPE_GLOBAL, snapshotNote, MEMORY_SNAPSHOT_KIND_OPT);
    for (const change of changes) {
      const bucket: relationalStore.ValuesBucket = { 'content': change.text, 'updatedAt': now };
      const keepPredicates: relationalStore.RdbPredicates =
        new relationalStore.RdbPredicates('memories');
      keepPredicates.equalTo('id', change.keepId);
      const affected: number = await db.update(bucket, keepPredicates);
      if (affected === 0) {
        throw new Error('待改写的记忆行不存在（已被删除），优化未应用');
      }
      for (const id of change.deleteIds) {
        const dropPredicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('memories');
        dropPredicates.equalTo('id', id);
        await db.delete(dropPredicates);
      }
    }
    // 剩余条目去空洞重排（改动后的查询序 = 卡片序；sortOrder = 新数组下标）
    const remainResult: relationalStore.ResultSet = await db.querySql(
      'SELECT id FROM memories ORDER BY sortOrder ASC, createdAt ASC, content ASC');
    const remainIds: string[] = [];
    try {
      while (remainResult.goToNextRow()) {
        remainIds.push(remainResult.getString(remainResult.getColumnIndex('id')));
      }
    } finally {
      remainResult.close();
    }
    for (let i = 0; i < remainIds.length; i++) {
      const bucket: relationalStore.ValuesBucket = { 'sortOrder': i };
      const predicates: relationalStore.RdbPredicates =
        new relationalStore.RdbPredicates('memories');
      predicates.equalTo('id', remainIds[i]);
      await db.update(bucket, predicates);
    }
    db.commit();
  } catch (e) {
    db.rollBack();
    throw e as Error;
  }
}

// ── 助手级记忆域（2026-09-20 助手级记忆，v35）：assistant_memories 表 CRUD，全部与全局
// memories 函数同构——差异只有三处：查询带 assistantId 归属条件、行 id 前缀 'asmem-'
// （连字符形态，仅供人读，非判库判据）、优化重排限定单助手库。行类型复用 MemoryRow
// （列形状完全一致，UI 与纯函数两域零适配直吃）。
// 上限守卫仍在调用方（自动链 MemoryGen / 手动链库管理页「＋」拦截），本层不二次判定
// ── 与全局同口径：两处判定 = 两处漂移面

const ASSISTANT_MEMORY_COLUMNS: string[] = ['id', 'assistantId', 'content', 'source',
  'conversationId', 'createdAt', 'updatedAt', 'sortOrder'];

function readAssistantMemoryRow(result: relationalStore.ResultSet): MemoryRow {
  return {
    id: result.getString(result.getColumnIndex('id')),
    content: result.getString(result.getColumnIndex('content')),
    source: result.getString(result.getColumnIndex('source')),
    assistantId: result.getString(result.getColumnIndex('assistantId')),
    conversationId: result.getString(result.getColumnIndex('conversationId')),
    createdAt: result.getLong(result.getColumnIndex('createdAt')),
    updatedAt: result.getLong(result.getColumnIndex('updatedAt')),
    sortOrder: result.getLong(result.getColumnIndex('sortOrder'))
  };
}

// 该助手库全量（排序三键与全局 queryMemories 同口径——sortOrder 升序 → createdAt 升序 →
// content 升序，注入块字符串确定性的同款前提；上限 200 条自然有界无翻页）
export async function queryAssistantMemories(assistantId: string): Promise<MemoryRow[]> {
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('assistant_memories');
  predicates.equalTo('assistantId', assistantId);
  predicates.orderByAsc('sortOrder');
  predicates.orderByAsc('createdAt');
  predicates.orderByAsc('content');
  const result: relationalStore.ResultSet =
    await requireStore().query(predicates, ASSISTANT_MEMORY_COLUMNS);
  const rows: MemoryRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push(readAssistantMemoryRow(result));
    }
  } finally {
    result.close();
  }
  return rows;
}

// 该助手库条数（库管理页摘要 + 上限守卫；COUNT 直查不拉行，countMemories 同构）
export async function countAssistantMemories(assistantId: string): Promise<number> {
  const result: relationalStore.ResultSet = await requireStore().querySql(
    'SELECT COUNT(*) AS n FROM assistant_memories WHERE assistantId = ?', [assistantId]);
  try {
    if (result.goToNextRow()) {
      return result.getLong(result.getColumnIndex('n'));
    }
    return 0;
  } finally {
    result.close();
  }
}

// 单条（编辑页回填；查不到返回 null——queryMemory 同款兜底口径）
export async function queryAssistantMemory(id: string): Promise<MemoryRow | null> {
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('assistant_memories');
  predicates.equalTo('id', id);
  const result: relationalStore.ResultSet =
    await requireStore().query(predicates, ASSISTANT_MEMORY_COLUMNS);
  try {
    if (result.goToNextRow()) {
      return readAssistantMemoryRow(result);
    }
    return null;
  } finally {
    result.close();
  }
}

// 新增单条（source='auto' 沉淀 / 'manual' 手动；sortOrder = **该助手库内** max + 1 落卡底，
// 与全局同款查后即写非事务窗口——并发极端下并列由 createdAt/content 兜底序收敛）；
// assistantId 归属由调用方传入（沉淀链 = 会话归属助手 / 手动链 = 库上下文）
export async function insertAssistantMemory(assistantId: string, content: string,
  source: string, conversationId: string): Promise<MemoryRow> {
  const now: number = Date.now();
  const maxResult: relationalStore.ResultSet = await requireStore().querySql(
    'SELECT COALESCE(MAX(sortOrder), 0) AS m FROM assistant_memories WHERE assistantId = ?',
    [assistantId]);
  let nextOrder: number = 0;
  try {
    if (maxResult.goToNextRow()) {
      nextOrder = maxResult.getLong(maxResult.getColumnIndex('m')) + 1;
    }
  } finally {
    maxResult.close();
  }
  const full: MemoryRow = {
    id: nextMessageId('asmem'),
    content: content,
    source: source,
    assistantId: assistantId,
    conversationId: conversationId,
    createdAt: now,
    updatedAt: now,
    sortOrder: nextOrder
  };
  const bucket: relationalStore.ValuesBucket = {
    'id': full.id, 'assistantId': full.assistantId, 'content': full.content,
    'source': full.source, 'conversationId': full.conversationId,
    'createdAt': full.createdAt, 'updatedAt': full.updatedAt, 'sortOrder': full.sortOrder
  };
  await requireStore().insert('assistant_memories', bucket);
  return full;
}

// 持久化该助手库卡片序（排序页整库回写 sortOrder = 数组下标；ids = 该助手库全量 id——
// saveMemoryOrder 同形制，全库 ≤ 200 行逐行 UPDATE 开销可忽略）
export async function saveAssistantMemoryOrder(ids: string[]): Promise<void> {
  for (let i = 0; i < ids.length; i++) {
    const bucket: relationalStore.ValuesBucket = { 'sortOrder': i };
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('assistant_memories');
    predicates.equalTo('id', ids[i]);
    await requireStore().update(bucket, predicates);
  }
}

// 编辑条目内容（updateMemoryContent 同构；affected === 0 抛错同口径）
export async function updateAssistantMemoryContent(id: string, content: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'content': content, 'updatedAt': Date.now() };
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('assistant_memories');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标记忆行不存在（已被删除），保存未生效');
  }
}

// 删除单条（库管理页删除键 → 确认弹窗后）
export async function deleteAssistantMemory(id: string): Promise<void> {
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('assistant_memories');
  predicates.equalTo('id', id);
  await requireStore().delete(predicates);
}

// 删助手级联删其助手记忆库（AssistantDb.deleteAssistantCascade 事务内调用——与「openers
// 随助手行生命周期级联删」同口径：库跟着人走，不置空保留）
export async function deleteAssistantMemoriesOfAssistant(assistantId: string): Promise<void> {
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('assistant_memories');
  predicates.equalTo('assistantId', assistantId);
  await requireStore().delete(predicates);
}

// 助手记忆列表刷新广播键（tick 递增语义同 MEMORY_LIST_TICK_KEY；读点 = 库管理页助手库态
// @StorageProp @Watch——退页自动整理落助手库后回页可见）
export const ASSISTANT_MEMORY_LIST_TICK_KEY: string = 'assistantMemoryListTick';

// 助手记忆列表刷新广播（MEMORY_LIST_TICK 同款 tick 递增——@Watch 对同值不触发，递增保证
// 每次触发）
export function broadcastAssistantMemoryList(): void {
  AppStorage.setOrCreate<number>(ASSISTANT_MEMORY_LIST_TICK_KEY,
    (AppStorage.get<number>(ASSISTANT_MEMORY_LIST_TICK_KEY) ?? 0) + 1);
}

// ── 助手库优化批量应用（applyMemoryOptChanges 同构事务；差异 = 重排限定该助手库——
// changes 里的 id 全部属于该库〔调用方按库出计划〕，去空洞重排的 SELECT 带 assistantId
// 条件防跨库行被误重排）。校验在纯函数层 buildMemoryOptPlan，本层只落库——同款两处判定
// = 两处漂移面纪律；保留行缺失即抛错回滚同口径。
// ★ 2026-09-22 记忆优化历史：第三参 snapshotNote 语义同 applyMemoryOptChanges（历史页摘要）；
// 事务**第一步**存档的库 = 本助手库（archiveBeforeOptInTx 按 libraryId 判库）
export async function applyAssistantMemoryOptChanges(assistantId: string,
  changes: MemoryOptChange[], snapshotNote: string): Promise<void> {
  if (changes.length === 0) {
    return;
  }
  const db: relationalStore.RdbStore = requireStore();
  const now: number = Date.now();
  db.beginTransaction();
  try {
    await archiveBeforeOptInTx(db, assistantId, snapshotNote, MEMORY_SNAPSHOT_KIND_OPT);
    for (const change of changes) {
      const bucket: relationalStore.ValuesBucket = { 'content': change.text, 'updatedAt': now };
      const keepPredicates: relationalStore.RdbPredicates =
        new relationalStore.RdbPredicates('assistant_memories');
      keepPredicates.equalTo('id', change.keepId);
      const affected: number = await db.update(bucket, keepPredicates);
      if (affected === 0) {
        throw new Error('待改写的记忆行不存在（已被删除），优化未应用');
      }
      for (const id of change.deleteIds) {
        const dropPredicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('assistant_memories');
        dropPredicates.equalTo('id', id);
        await db.delete(dropPredicates);
      }
    }
    // 该助手库剩余条目去空洞重排（带归属条件——只重排本库，不触碰其他助手库行）
    const remainResult: relationalStore.ResultSet = await db.querySql(
      'SELECT id FROM assistant_memories WHERE assistantId = ? ' +
      'ORDER BY sortOrder ASC, createdAt ASC, content ASC', [assistantId]);
    const remainIds: string[] = [];
    try {
      while (remainResult.goToNextRow()) {
        remainIds.push(remainResult.getString(remainResult.getColumnIndex('id')));
      }
    } finally {
      remainResult.close();
    }
    for (let i = 0; i < remainIds.length; i++) {
      const bucket: relationalStore.ValuesBucket = { 'sortOrder': i };
      const predicates: relationalStore.RdbPredicates =
        new relationalStore.RdbPredicates('assistant_memories');
      predicates.equalTo('id', remainIds[i]);
      await db.update(bucket, predicates);
    }
    db.commit();
  } catch (e) {
    db.rollBack();
    throw e as Error;
  }
}

// ── 记忆优化历史（2026-09-22，方案-记忆优化历史-20260922 §5）：memory_snapshots 表读写——
// 把「优化记忆不可撤销」变成「可回退」：每次优化落库前在**同事务内**先存一份整库快照，
// 历史页可看、行卡可整库回退，恢复前又自动存一份「恢复前兜底」让恢复本身也可撤销。
// ★ 2026-09-22 记忆导入笔：存档函数泛化为「非兜底槽」共用——kind 由调用方传（before_opt
// 由两条优化链传 / before_import 由导入链传），历史页标签三态随之。
// 三条保留规则（防堆积的全部逻辑，勿增勿减）：
// ①写任一非兜底槽时同事务清掉本库兜底槽——新一轮改动开始，上一轮的撤销窗口关闭；
// ②**非兜底槽合计**每库 ≤ MEMORY_SNAPSHOT_KEEP 份（优化与导入共用同一配额，超出按 createdAt
//   升序淘汰最旧）——若按 kind 各留一份，导入会出现「永不清理的快照」，即无界增长；
// ③before_restore 每库 ≤1 份，写入前先删本库旧兜底行（覆盖写）。
// 故总量恒为每库 3 + 1（不论两种非兜底槽各占多少），不存在无界增长；恢复动作也不会挤掉
// 真正的历史。
// ★ 须知的既有副作用（沿用优化链同口径，非导入笔引入）：规则①的清兜底槽意味着「任何一次
// 非兜底存档都会作废上一次整库回退的撤销窗口」——用户刚做过一次恢复、随后又优化或导入，
// 那次恢复就无法再撤销。这是存档函数的既有行为，本笔沿用不另改；后笔勿当 bug 顺手修
//（要改须先想清「撤销窗口只覆盖最近一次破坏性动作」这一语义是否有意为之）。
// ★ 库选择统一走 libraryId === MEMORY_SCOPE_GLOBAL 判据（与全库同源；**禁按 id 前缀判库**
//   ——前缀只供人读，见文件头注释）。
// ★ 快照不进 EXPORT_TABLES（D8：本地后悔药不是跨设备资产）；删助手时其助手库快照级联删
//   （deleteAssistantCascade 事务内调用）。
export const MEMORY_SNAPSHOT_KEEP: number = 3;
export const MEMORY_SNAPSHOT_KIND_OPT: string = 'before_opt';
export const MEMORY_SNAPSHOT_KIND_RESTORE: string = 'before_restore';
// 导入前存档（2026-09-22 记忆导入笔）：与 before_opt 同属非兜底槽，共用规则①②的配额与
// 裁剪；历史页标签映射见 MemoryHistoryPage.snapshotKindLabel
export const MEMORY_SNAPSHOT_KIND_IMPORT: string = 'before_import';

export interface MemorySnapshotRow {
  id: string;
  libraryId: string;
  kind: string;
  note: string;
  itemCount: number;
  createdAt: number;
  payload: string;
}

const SNAPSHOT_COLUMNS: string[] = ['id', 'libraryId', 'kind', 'note', 'itemCount',
  'createdAt', 'payload'];

function readSnapshotRow(result: relationalStore.ResultSet): MemorySnapshotRow {
  return {
    id: result.getString(result.getColumnIndex('id')),
    libraryId: result.getString(result.getColumnIndex('libraryId')),
    kind: result.getString(result.getColumnIndex('kind')),
    note: result.getString(result.getColumnIndex('note')),
    itemCount: result.getLong(result.getColumnIndex('itemCount')),
    createdAt: result.getLong(result.getColumnIndex('createdAt')),
    payload: result.getString(result.getColumnIndex('payload'))
  };
}

// 该库全部快照，createdAt 降序（最新在上——兜底槽必然排最前，因为它恒是最新写入的一份）。
// **不解析 payload**：列表只需 itemCount（payload 是整库存量文本，列表页逐行解析是白烧）。
export async function queryMemorySnapshots(libraryId: string): Promise<MemorySnapshotRow[]> {
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('memory_snapshots');
  predicates.equalTo('libraryId', libraryId);
  predicates.orderByDesc('createdAt');
  const result: relationalStore.ResultSet = await requireStore().query(predicates, SNAPSHOT_COLUMNS);
  const rows: MemorySnapshotRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push(readSnapshotRow(result));
    }
  } finally {
    result.close();
  }
  return rows;
}

// 单份快照（恢复用；查不到返回 null——调用方兜底提示，queryMemory 同款口径）
export async function queryMemorySnapshot(id: string): Promise<MemorySnapshotRow | null> {
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('memory_snapshots');
  predicates.equalTo('id', id);
  const result: relationalStore.ResultSet = await requireStore().query(predicates, SNAPSHOT_COLUMNS);
  try {
    if (result.goToNextRow()) {
      return readSnapshotRow(result);
    }
    return null;
  } finally {
    result.close();
  }
}

// payload 反序列化（方案 §4.2 容错规则）：顶层必须是数组，元素逐字段取值、缺失字段落默认值
// （旧版快照将来加列时导回不炸）。**失败一律抛中文错误，禁静默返回空数组**（P0-1）——恢复是
// 破坏性动作，解析不出来还照做 = 把整库清空成空库。
function parseSnapshotPayload(payload: string): MemoryRow[] {
  let parsed: Object;
  try {
    parsed = JSON.parse(payload) as Object;
  } catch (e) {
    throw new Error('快照内容无法解析，恢复未执行');
  }
  if (!Array.isArray(parsed)) {
    throw new Error('快照内容格式异常，恢复未执行');
  }
  const rows: MemoryRow[] = [];
  for (const item of parsed as Object[]) {
    if (item === null || typeof item !== 'object' || Array.isArray(item)) {
      throw new Error('快照条目格式异常，恢复未执行');
    }
    const rec: Record<string, Object> = item as Record<string, Object>;
    const id: Object | undefined = rec['id'];
    if (typeof id !== 'string' || id === '') {
      // id 缺失无法落库（主键），且容忍它只会把坏数据写进库——响亮抛错优于静默
      throw new Error('快照条目缺少标识，恢复未执行');
    }
    const content: Object | undefined = rec['content'];
    const source: Object | undefined = rec['source'];
    const assistantId: Object | undefined = rec['assistantId'];
    const conversationId: Object | undefined = rec['conversationId'];
    const createdAt: Object | undefined = rec['createdAt'];
    const updatedAt: Object | undefined = rec['updatedAt'];
    const sortOrder: Object | undefined = rec['sortOrder'];
    rows.push({
      id: id,
      content: typeof content === 'string' ? content : '',
      source: typeof source === 'string' ? source : 'auto',
      assistantId: typeof assistantId === 'string' ? assistantId : '',
      conversationId: typeof conversationId === 'string' ? conversationId : '',
      createdAt: typeof createdAt === 'number' ? createdAt : 0,
      updatedAt: typeof updatedAt === 'number' ? updatedAt : 0,
      sortOrder: typeof sortOrder === 'number' ? sortOrder : 0
    });
  }
  return rows;
}

// 单份快照的条目（快照详情页只读列表用——payload 解析口径单源 = parseSnapshotPayload，
// **禁在页面侧再写一份 JSON.parse**：两处解析 = 两处漂移面，且页面对坏数据无兜底义务）。
// 查不到即抛中文错误（调用方 toast 原文，P0-1 不静默）；解析失败同由 parseSnapshotPayload 抛。
export async function queryMemorySnapshotItems(id: string): Promise<MemoryRow[]> {
  const snapshot: MemorySnapshotRow | null = await queryMemorySnapshot(id);
  if (snapshot === null) {
    throw new Error('快照不存在（可能已被清理）');
  }
  return parseSnapshotPayload(snapshot.payload);
}

// 事务内插一份快照（id 形态 `msnap-<时间戳>-<序号>`，与 mem-/asmem- 同形；前缀只供人读）
async function insertSnapshotInTx(db: relationalStore.RdbStore, libraryId: string, kind: string,
  note: string, rows: MemoryRow[]): Promise<void> {
  const bucket: relationalStore.ValuesBucket = {
    'id': nextMessageId('msnap'), 'libraryId': libraryId, 'kind': kind, 'note': note,
    'itemCount': rows.length, 'createdAt': Date.now(), 'payload': JSON.stringify(rows)
  };
  await db.insert('memory_snapshots', bucket);
}

// 非兜底槽统一裁剪（兜底槽不占配额、由「覆盖写」自管）：按 createdAt 升序数，超出 keep
// 的最旧若干份逐个 DELETE。keep 由调用方以**常量引用**传入（MEMORY_SNAPSHOT_KEEP），判断
// 口径单源在常量，禁在调用点写字面量。
// ★ 判据 = `kind != 兜底槽` 而非 `kind = before_opt`（2026-09-22 记忆导入笔）：导入槽与优化槽
// 共用同一配额——按 kind 各裁一份会让 before_import 永不清理 = 无界增长（宪法「数据有界」）；
// 改成否定式后，未来再加非兜底 kind 也自动纳入配额，不必回来改本函数
async function trimSnapshotsInTx(db: relationalStore.RdbStore, libraryId: string,
  keep: number): Promise<void> {
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT id FROM memory_snapshots WHERE libraryId = ? AND kind != ? ' +
    'ORDER BY createdAt ASC, rowid ASC', [libraryId, MEMORY_SNAPSHOT_KIND_RESTORE]);
  const ids: string[] = [];
  try {
    while (result.goToNextRow()) {
      ids.push(result.getString(result.getColumnIndex('id')));
    }
  } finally {
    result.close();
  }
  const excess: number = ids.length - keep;
  for (let i = 0; i < excess; i++) {
    await db.executeSql('DELETE FROM memory_snapshots WHERE id = ?', [ids[i]]);
  }
}

// 改动前存档（★ 调用点 = 优化两条链与导入链，各自事务的 **第一步**；函数名里的 Opt 是历史
// 名字——2026-09-22 导入笔已泛化为「非兜底槽共用」，改名牵动三处调用与断言收益为零，故留）：
// 读当前库全量 → 写一份调用方指定 kind 的快照 → 清本库兜底槽（规则①）→ 裁剪配额（规则②）。
// ★ 读必须在事务内（调用方已开）：事务外先读再开事务，两次操作之间库可能被别处改动
// （自动整理落库），存下的就不是「被这次操作改掉的那一版」。
// ★ kind 由调用方传（MEMORY_SNAPSHOT_KIND_OPT / MEMORY_SNAPSHOT_KIND_IMPORT），**禁写死
// before_opt**：写死会让导入存出的快照顶着「优化前」标签上屏（历史页说的是另一件事）。
export async function archiveBeforeOptInTx(db: relationalStore.RdbStore, libraryId: string,
  note: string, kind: string): Promise<void> {
  const rows: MemoryRow[] = libraryId === MEMORY_SCOPE_GLOBAL ?
    await queryMemories() : await queryAssistantMemories(libraryId);
  await insertSnapshotInTx(db, libraryId, kind, note, rows);
  await db.executeSql('DELETE FROM memory_snapshots WHERE libraryId = ? AND kind = ?',
    [libraryId, MEMORY_SNAPSHOT_KIND_RESTORE]);
  await trimSnapshotsInTx(db, libraryId, MEMORY_SNAPSHOT_KEEP);
}

// 恢复时写回单行（restoreMemorySnapshot 的写回步——两库分支唯二差异是表名与 assistantId
// 取值，提为子程序防两处漂移；★ 三时间字段恒取**快照行原值**，见调用方 ★★ 注释）
async function insertRestoredRowInTx(db: relationalStore.RdbStore, libraryId: string,
  row: MemoryRow): Promise<void> {
  if (libraryId === MEMORY_SCOPE_GLOBAL) {
    const bucket: relationalStore.ValuesBucket = {
      'id': row.id, 'content': row.content, 'source': row.source,
      'assistantId': row.assistantId, 'conversationId': row.conversationId,
      'createdAt': row.createdAt, 'updatedAt': row.updatedAt, 'sortOrder': row.sortOrder
    };
    await db.insert('memories', bucket);
    return;
  }
  // assistantId 取归属库值而非快照行值：助手库里该列是**归属语义**，恒等于 libraryId
  //（快照本就取自本库）；全局表里的 assistantId 是「沉淀来源标注」，故上行必须原样保留
  const bucket: relationalStore.ValuesBucket = {
    'id': row.id, 'assistantId': libraryId, 'content': row.content,
    'source': row.source, 'conversationId': row.conversationId,
    'createdAt': row.createdAt, 'updatedAt': row.updatedAt, 'sortOrder': row.sortOrder
  };
  await db.insert('assistant_memories', bucket);
}

// 整库恢复（方案 §5.4，本域最关键的一段）：把库内容整体换回某份快照，一个事务内完成——
// ①读当前库（事务内）②覆盖写兜底槽（恢复前状态，让「撤销这次恢复」仍可用）③清空本库
// ④逐行写回快照条目。任一步失败 rollBack，中止即零改动（优化落库同款三件套）。
// ★★ 恢复必须**原样写回 sortOrder / createdAt / updatedAt**，一个都不能刷成 Date.now()：
//  · sortOrder 决定注入块内容与顺序（注入窗口按序贪心取前 30 条 / 2000 字，排序一变被截掉
//    的就是另一批）；
//  · createdAt（+ content）是排序并列兜底键，是「注入块字符串零漂移」的成立前提；
//  · updatedAt 被 search_memory 工具的相关度并列排序消费（新者优先）。
//  任一被重写，「整库替换」就名不副实——恢复出来的注入块和当时看到的不是一回事。
// ★ 清空必须用 executeSql 裸 DML，**禁用 RdbPredicates 空条件**：in() 传空数组是「条件失效
// 落全表」（官方 d.ts 原文），是全仓已知的危险区；带 assistantId 的条件虽是非空谓词，仍统一
// 走 executeSql 保持写法一致。
// ★ 从兜底槽恢复（= 撤销一次恢复）无需特判：步骤①已把目标快照读进内存，步骤②覆盖兜底槽
// 不会破坏本次恢复；恢复完成后兜底槽 = 这次操作的前态，语义自洽。
// ★ 事务是**单句柄全局的**（sharedRdbStore）：本函数不得在别处事务已开启时调用（嵌套
// beginTransaction 会抛）。它自己开事务，且**只被 UI 直接调用**，不在任何既有事务内调用。
export async function restoreMemorySnapshot(snapshotId: string): Promise<void> {
  const snapshot: MemorySnapshotRow | null = await queryMemorySnapshot(snapshotId);
  if (snapshot === null) {
    throw new Error('快照不存在（可能已被清理），恢复未执行');
  }
  const target: MemoryRow[] = parseSnapshotPayload(snapshot.payload);
  const libraryId: string = snapshot.libraryId;
  const db: relationalStore.RdbStore = requireStore();
  db.beginTransaction();
  try {
    const current: MemoryRow[] = libraryId === MEMORY_SCOPE_GLOBAL ?
      await queryMemories() : await queryAssistantMemories(libraryId);
    // 覆盖写兜底槽（规则③：先删本库旧兜底行再插，每库恒 ≤1 份）
    await db.executeSql('DELETE FROM memory_snapshots WHERE libraryId = ? AND kind = ?',
      [libraryId, MEMORY_SNAPSHOT_KIND_RESTORE]);
    await insertSnapshotInTx(db, libraryId, MEMORY_SNAPSHOT_KIND_RESTORE, '', current);
    // 清空本库（全局 = 整表；助手库 = 该归属行）
    if (libraryId === MEMORY_SCOPE_GLOBAL) {
      await db.executeSql('DELETE FROM memories');
    } else {
      await db.executeSql('DELETE FROM assistant_memories WHERE assistantId = ?', [libraryId]);
    }
    // 逐行写回（含 id 与三时间字段原样——见上方 ★★）
    for (const row of target) {
      await insertRestoredRowInTx(db, libraryId, row);
    }
    db.commit();
  } catch (e) {
    db.rollBack();
    throw e as Error;
  }
  // 广播（对应库列表刷新；事务已提交，广播在提交后）
  if (libraryId === MEMORY_SCOPE_GLOBAL) {
    broadcastMemoryList();
  } else {
    broadcastAssistantMemoryList();
  }
}

// 删助手级联删其快照（AssistantDb.deleteAssistantCascade 事务内调用——与
// deleteAssistantMemoriesOfAssistant 同口径：快照跟着助手走，不置空保留，防孤儿行无界堆积）
export async function deleteMemorySnapshotsOfAssistant(assistantId: string): Promise<void> {
  await requireStore().executeSql('DELETE FROM memory_snapshots WHERE libraryId = ?',
    [assistantId]);
}
