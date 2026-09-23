// 附件元数据存储域（2026-09-09 附件全量落盘第一轮·数据域，任务书-附件落盘-20260909）：
// message_attachments 表行读写 + 级联删除 + 库盘一致性收敛。
// · 依赖方向红线：本文件不 import ChatDb——store 句柄由调用方传入（防 ChatDb →
//   AttachmentDb → ChatDb 循环；ChatDb/AssistantDb/ExportImport 持句柄调用）；亦不 import
//   AttachmentUtil（AttachmentUtil 反向 import 本文件的 MessageAttachmentRow 类型——
//   行构建纯函数在 common 层，依赖单向 AttachmentUtil → AttachmentDb）。目录名
//   ATTACH_DIR_NAME 与 AttachmentUtil.ATTACH_DIR 同值，两文件互不 import，断言钉一致。
// · 级联删除铁律：任何新增「删 messages」路径，必须在同函数同事务内删附件行——本域
//   建立时全仓删 messages 落点 = ChatDb.deleteConversations + AssistantDb.
//   deleteAssistantCascade 两处；行删先 SELECT 收集 localPath、文件 I/O 在事务 commit
//   之后（回滚不得已删文件）。
// · 一致性收敛（reconcileAttachments）：孤儿行（messageId 不在 messages 表）删行；孤儿
//   文件（filesDir/attachments 下不在现存行 localPath 集**且修改时刻早于本进程启动者**）
//   删文件——在途保护闸（2026-09-09 第二轮存储管理页引入：手动清理键上线后「输入栏挂着
//   未发附件 → 进存储页点清理」会删在途文件，故本进程内新建的文件一律保护）；判定单源 =
//   collectOrphanFiles（收敛与存储页清理预览/实删共用，卡面显示数与实删数必然一致）。
//   「行在文件不在」**不删行**（决明拍板——元数据不轻易丢弃，第三轮预览显示「文件已不在
//   本机」；与 RikkaHub syncFolder 对该形态删行的策略相反，是本项目有意分叉）。
// · I/O 口径：删文件 best-effort（单文件失败静默，启动收敛/下次操作自愈）；启动收敛
//   一次有界全表查询 + 一次目录列举，非轮询；★ 2026-09-15 预览第三轮新增只读查询面
//   queryAttachmentsForMessages（展示装配用，入参恒 ≤ 窗口内 user 消息数——有界）；
//   ★ 2026-09-15 附件管理列表笔再增三个分页只读面（queryAttachmentGroups /
//   queryAttachmentsByConversation / queryAttachmentTotal——全部 LIMIT 分页 + 不取
//   parsedText，见各自函数头注释）。
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xDACC;
const TAG: string = 'AttachmentDb';
// 常驻区目录名（与 AttachmentUtil.ATTACH_DIR 同值——见头注释依赖方向红线）
const ATTACH_DIR_NAME: string = 'attachments';

// 模块级 ctx 捕获（initAttachmentStore——EntryAbility onCreate 调一次）：removeAttachmentFiles
// 等无 ctx 入参的文件操作用（localPath 是相对 filesDir 路径，删文件须拼绝对路径）
let attachCtx: common.UIAbilityContext | null = null;
// 本进程启动时刻（毫秒，initAttachmentStore 赋值）：孤儿文件判定的在途保护闸——mtime 早于
// 它才算孤儿（本进程内新建的「已选未发/发送中」附件一律保护，第二轮存储管理页手动清理键
// 引入）。0 = 未就位，此时不删任何文件（无保护窗口信息不冒险，P0-1）
let attachProcStartMs: number = 0;

// 附件元数据行（v23 表；localPath 相对 filesDir——attachments/<id>.<ext>，禁绝对路径）
export interface MessageAttachmentRow {
  id: string; // = 附件 fileId（与文件名同源）
  messageId: string;
  conversationId: string; // 冗余列（级联删/按会话统计免 join；值不可变）
  kind: string; // 'image' | 'text' | 'doc'（classifyByName 全集）
  name: string; // 显示名（原始文件名）
  mime: string;
  size: number;
  localPath: string;
  parsedText: string; // 文档解析产出（仅 kind='doc' 有值；≤120K 字符解析侧截断）
  createdAt: number;
}

// 收敛摘要（hilog 留痕用）
export interface ReconcileSummary {
  rowsRemoved: number;
  filesRemoved: number;
}

// ── 附件管理列表只读面（2026-09-15 附件管理列表笔，任务书-附件管理列表-20260915 §2.1）──
// 三个分页查询成组（一级按会话聚合 / 二级按会话列行 / 全局合计），并入本域消费
// （反碎片下限②：并入既有同域文件，不新开数据件）。★ 列表类查询一律**不取 parsedText**
// （文档解析大字段，展示用不着，取它就是无界拖慢）——二级行类型 AttachmentListRow 连字段
// 都不带，类型级封死，比「取了不读」更难回潮。
// 会话分组行（一级聚合）：title 取 conversations LEFT JOIN 且 SQL 侧 IFNULL 兜空串
//（会话行缺失/未命名都回 ''，页面侧再兜显示名）
export interface AttachmentGroupRow {
  conversationId: string;
  title: string;
  count: number;
  bytes: number;
}

// 列表展示行（二级列行）= MessageAttachmentRow 去掉 parsedText 列（见上口径）
export interface AttachmentListRow {
  id: string;
  messageId: string;
  conversationId: string;
  kind: string;
  name: string;
  mime: string;
  size: number;
  localPath: string;
  createdAt: number;
}

// 全局合计（管理页顶部常显）
export interface AttachmentTotalRow {
  count: number;
  bytes: number;
}

// ctx 捕获 + 进程启动时刻记录（EntryAbility onCreate 调用，先于任何附件文件操作）
export function initAttachmentStore(ctx: common.UIAbilityContext): void {
  attachCtx = ctx;
  attachProcStartMs = Date.now();
}

// 附件行批量写入（消息落库后随行——ChatDb.insertMessage 第四参透传；逐条插入，单行失败
// 上抛由调用方决定留痕口径）
export async function insertAttachments(db: relationalStore.RdbStore,
  rows: MessageAttachmentRow[]): Promise<void> {
  for (const row of rows) {
    const bucket: relationalStore.ValuesBucket = {
      'id': row.id,
      'messageId': row.messageId,
      'conversationId': row.conversationId,
      'kind': row.kind,
      'name': row.name,
      'mime': row.mime,
      'size': row.size,
      'localPath': row.localPath,
      'parsedText': row.parsedText,
      'createdAt': row.createdAt
    };
    await db.insert('message_attachments', bucket);
  }
}

// 谓词两用：先按谓词收集 localPath 集，再按同款谓词删行（谓词是只读条件容器，query 不
// 变异、复用安全）；返回相对路径集供调用方在 commit 后删文件
async function deleteAndCollect(db: relationalStore.RdbStore,
  predicates: relationalStore.RdbPredicates): Promise<string[]> {
  const paths: string[] = [];
  const result: relationalStore.ResultSet = await db.query(predicates, ['localPath']);
  try {
    while (result.goToNextRow()) {
      paths.push(result.getString(result.getColumnIndex('localPath')));
    }
  } finally {
    result.close();
  }
  await db.delete(predicates);
  return paths;
}

// 按会话集删附件行（删会话/删助手两入口事务内调用；入参须纯数组——坑6 族，两调用方均自建
// 拷贝数组）；空集短路（in() 空数组「条件失效落全表」，d.ts:2388）
export async function deleteAttachmentsForConversations(db: relationalStore.RdbStore,
  convIds: string[]): Promise<string[]> {
  if (convIds.length === 0) {
    return [];
  }
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('message_attachments');
  predicates.in('conversationId', convIds);
  return deleteAndCollect(db, predicates);
}

// 按消息集删附件行（导入覆盖路径用——被覆盖消息回到备份当时状态，本机附件行随之作废；
// 空集短路同上）
export async function deleteAttachmentsForMessages(db: relationalStore.RdbStore,
  messageIds: string[]): Promise<string[]> {
  if (messageIds.length === 0) {
    return [];
  }
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('message_attachments');
  predicates.in('messageId', messageIds);
  return deleteAndCollect(db, predicates);
}

// 按附件行 id 删单件（2026-09-15 附件管理列表笔）：与按消息集删分开——一条消息可挂多件
// 附件，按 messageId 删会连带误伤同消息其余件（管理页单件语义要求只删点击的那一件）。
// 空集短路同上（in() 空数组「条件失效落全表」，d.ts:2388）
export async function deleteAttachmentsByIds(db: relationalStore.RdbStore,
  ids: string[]): Promise<string[]> {
  if (ids.length === 0) {
    return [];
  }
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('message_attachments');
  predicates.in('id', ids);
  return deleteAndCollect(db, predicates);
}

// 按消息集查附件行（2026-09-15 预览第三轮新增——本域首个展示用只读面，历史回放装配
// brief 用；经 ChatDb 同名委托入口消费，句柄由其 requireStore 传入）。空集短路（in()
// 空数组「条件失效落全表」，deleteAttachmentsForConversations 同款先例）；ORDER BY rowid
// 保插入序 = annotate 名单序 = 显示次序（§2.5 标注逐字匹配与简报序的前提——createdAt 同
// 一发送毫秒级同值不可分辨，rowid 是唯一稳定插入序）
export async function queryAttachmentsForMessages(db: relationalStore.RdbStore,
  messageIds: string[]): Promise<MessageAttachmentRow[]> {
  if (messageIds.length === 0) {
    return [];
  }
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('message_attachments');
  predicates.in('messageId', messageIds);
  predicates.orderByAsc('rowid');
  const result: relationalStore.ResultSet = await db.query(predicates);
  const rows: MessageAttachmentRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        id: result.getString(result.getColumnIndex('id')),
        messageId: result.getString(result.getColumnIndex('messageId')),
        conversationId: result.getString(result.getColumnIndex('conversationId')),
        kind: result.getString(result.getColumnIndex('kind')),
        name: result.getString(result.getColumnIndex('name')),
        mime: result.getString(result.getColumnIndex('mime')),
        size: result.getLong(result.getColumnIndex('size')),
        localPath: result.getString(result.getColumnIndex('localPath')),
        parsedText: result.getString(result.getColumnIndex('parsedText')),
        createdAt: result.getLong(result.getColumnIndex('createdAt'))
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// 一级：按会话聚合分页（2026-09-15 附件管理列表笔）。排序 = 体积倒序，第二键 conversationId
// ——同体积组跨页不重复不遗漏（单一排序键在等值处次序不定，分页游标会漂）。聚合成败由
// idx_message_attachments_conv 索引支撑（本笔零 DB 变更）。limit ≤ 0 空集短路（调用方勿传
// 0 探底——与 in() 空数组落全表同族的防线形态）
export async function queryAttachmentGroups(db: relationalStore.RdbStore,
  limit: number, offset: number): Promise<AttachmentGroupRow[]> {
  if (limit <= 0) {
    return [];
  }
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT a.conversationId AS conversationId, COUNT(*) AS cnt, IFNULL(SUM(a.size), 0) AS bytes, ' +
    'IFNULL(c.title, \'\') AS title FROM message_attachments a ' +
    'LEFT JOIN conversations c ON c.id = a.conversationId ' +
    'GROUP BY a.conversationId ORDER BY bytes DESC, a.conversationId ASC LIMIT ? OFFSET ?',
    [limit, offset]);
  const rows: AttachmentGroupRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        conversationId: result.getString(result.getColumnIndex('conversationId')),
        title: result.getString(result.getColumnIndex('title')),
        count: result.getLong(result.getColumnIndex('cnt')),
        bytes: result.getLong(result.getColumnIndex('bytes'))
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// 二级：按会话列行分页（同会话内最近发的在前 = rowid DESC；展开某组时才查——未展开的组
// 零查询零渲染，有界红线）。limit ≤ 0 空集短路同上
export async function queryAttachmentsByConversation(db: relationalStore.RdbStore,
  conversationId: string, limit: number, offset: number): Promise<AttachmentListRow[]> {
  if (limit <= 0) {
    return [];
  }
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT id, messageId, conversationId, kind, name, mime, size, localPath, createdAt ' +
    'FROM message_attachments WHERE conversationId = ? ORDER BY rowid DESC LIMIT ? OFFSET ?',
    [conversationId, limit, offset]);
  const rows: AttachmentListRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        id: result.getString(result.getColumnIndex('id')),
        messageId: result.getString(result.getColumnIndex('messageId')),
        conversationId: result.getString(result.getColumnIndex('conversationId')),
        kind: result.getString(result.getColumnIndex('kind')),
        name: result.getString(result.getColumnIndex('name')),
        mime: result.getString(result.getColumnIndex('mime')),
        size: result.getLong(result.getColumnIndex('size')),
        localPath: result.getString(result.getColumnIndex('localPath')),
        createdAt: result.getLong(result.getColumnIndex('createdAt'))
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// 全局合计（管理页进页取一次，删除后本地递减不重算——一行聚合，无 GROUP BY 开销）
export async function queryAttachmentTotal(db: relationalStore.RdbStore):
  Promise<AttachmentTotalRow> {
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT COUNT(*) AS cnt, IFNULL(SUM(size), 0) AS bytes FROM message_attachments');
  const total: AttachmentTotalRow = { count: 0, bytes: 0 };
  try {
    if (result.goToNextRow()) {
      total.count = result.getLong(result.getColumnIndex('cnt'));
      total.bytes = result.getLong(result.getColumnIndex('bytes'));
    }
  } finally {
    result.close();
  }
  return total;
}

// 按会话附件计数（2026-09-19 会话统计半模态笔，会话统计卡「附件数」行——conversationId
// 冗余列免 join 即本表建列时预留的「按会话统计」用途；单行聚合有界）。查询失败上抛由
// 调用方降级
export async function countAttachmentsByConversation(db: relationalStore.RdbStore,
  conversationId: string): Promise<number> {
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT COUNT(*) AS cnt FROM message_attachments WHERE conversationId = ?',
    [conversationId]);
  let count: number = 0;
  try {
    if (result.goToNextRow()) {
      count = result.getLong(result.getColumnIndex('cnt'));
    }
  } finally {
    result.close();
  }
  return count;
}

// 按相对路径集删常驻区文件（事务 commit 成功后调用；best-effort——文件不存在 = 目标状态、
// 失败留启动收敛自愈，不回滚库也不打扰用户）
export function removeAttachmentFiles(paths: string[]): void {
  if (attachCtx === null) {
    hilog.warn(DOMAIN, TAG, '附件 ctx 未捕获（initAttachmentStore 未调用），跳过文件删除');
    return;
  }
  for (const p of paths) {
    try {
      fs.unlinkSync(attachCtx.filesDir + '/' + p);
    } catch {
      // 文件不存在 = 目标状态，静默
    }
  }
}

// 孤儿文件判定单源（reconcileAttachments 与 StorageStats.scanCleanables/cleanOrphanAttachments
// 共用——存储页卡面显示数与实删数由此必然一致）：存活行 localPath 全集 → 目录内不在集者，
// 再过在途保护闸 = 修改时刻早于本进程启动（本进程内新建的已选未发/发送中附件一律保护）。
// 返回相对 filesDir 路径集（attachments/<name>，与 localPath 同形）。进程启动时刻未就位
// （initAttachmentStore 未调用）返回空集——无保护窗口信息就不删，warn 留痕（P0-1 不静默）
export async function collectOrphanFiles(ctx: common.Context,
  db: relationalStore.RdbStore): Promise<string[]> {
  if (attachProcStartMs <= 0) {
    hilog.warn(DOMAIN, TAG, '进程启动时刻未就位（initAttachmentStore 未调用），跳过孤儿文件判定');
    return [];
  }
  const livePaths: Set<string> = new Set<string>();
  const liveResult: relationalStore.ResultSet =
    await db.querySql('SELECT localPath FROM message_attachments');
  try {
    while (liveResult.goToNextRow()) {
      livePaths.add(liveResult.getString(liveResult.getColumnIndex('localPath')));
    }
  } finally {
    liveResult.close();
  }
  const orphans: string[] = [];
  const dir: string = ctx.filesDir + '/' + ATTACH_DIR_NAME;
  try {
    const names: string[] = fs.listFileSync(dir);
    for (const name of names) {
      const rel: string = ATTACH_DIR_NAME + '/' + name;
      if (livePaths.has(rel)) {
        continue;
      }
      try {
        // mtime 单位 = 秒（@ohos.file.fs.d.ts Stat.mtime 实锤），换算毫秒与启动时刻比；
        // 秒级粒度下「与启动同秒」按不早于启动处理（保守方向 = 保护，不误删）
        if (fs.statSync(dir + '/' + name).mtime * 1000 + 1000 <= attachProcStartMs) {
          orphans.push(rel);
        }
      } catch {
        // stat 失败（并发删除等）跳过——下次收敛再判
      }
    }
  } catch {
    // 目录不存在 = 干净，目标状态
  }
  return orphans;
}

// 库盘一致性收敛（EntryAbility 启动 + 导入成功两处调用；fire-and-forget 不阻塞调用链）：
// ①孤儿行 = messageId 已不在 messages 表（删消息未级联/写行失败等异常兜底）→ 删行；其文件
// 在②中随「不在存活集」一并清掉（先删行后算存活集，顺序即清理链）。②孤儿文件 = 判定单源
// collectOrphanFiles（选后未发崩溃残留 / 行删后文件残留；含在途保护闸）→ 删文件。「行在
// 文件不在」不动（见头注释分叉说明）。失败上抛由调用方留痕，不阻断启动
export async function reconcileAttachments(ctx: common.Context,
  db: relationalStore.RdbStore): Promise<ReconcileSummary> {
  const summary: ReconcileSummary = { rowsRemoved: 0, filesRemoved: 0 };
  // ① 孤儿行（NOT IN 反连接一条 SQL——RdbPredicates 无子查询能力，querySql 直写；
  // sweepEmptyConversations 同款姿势）。★ 子查询带 `id IS NOT NULL`（2026-09-22 自检轮族
  // 收口）：反连接的 NULL 语义坑——子查询里只要出现一个 NULL，`messageId NOT IN (...)` 对
  // 所有未匹配行就不是真（三值逻辑）⇒ 孤儿行一条也选不出（行与文件双双静默留存，本函数
  // 作为「库盘一致性」兜底整体失效）；而这类 NULL id 由同族数据引入（见 MessageSeqDb 头
  // 注释 856 条）。排除 NULL 不误删：id 为 NULL 的 messages 行本就不可能被任何字符串
  // messageId 指向，故「指向它的附件行」不存在于正常数据
  const orphanResult: relationalStore.ResultSet = await db.querySql(
    'SELECT id FROM message_attachments ' +
    'WHERE messageId NOT IN (SELECT id FROM messages WHERE id IS NOT NULL)');
  const orphanIds: string[] = [];
  try {
    while (orphanResult.goToNextRow()) {
      orphanIds.push(orphanResult.getString(orphanResult.getColumnIndex('id')));
    }
  } finally {
    orphanResult.close();
  }
  if (orphanIds.length > 0) {
    const rowPredicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('message_attachments');
    rowPredicates.in('id', orphanIds);
    await db.delete(rowPredicates);
    summary.rowsRemoved = orphanIds.length;
  }
  // ② 孤儿文件（判定单源 = collectOrphanFiles；①已先行删行，孤儿行原指向的文件不在存活
  // 集内，一并被清）
  const orphans: string[] = await collectOrphanFiles(ctx, db);
  for (const rel of orphans) {
    try {
      fs.unlinkSync(ctx.filesDir + '/' + rel);
      summary.filesRemoved++;
    } catch {
      // 单文件失败跳过——下次启动再清（有界自愈）
    }
  }
  hilog.info(DOMAIN, TAG, '附件一致性收敛完成：删孤儿行 %{public}d、删孤儿文件 %{public}d',
    summary.rowsRemoved, summary.filesRemoved);
  return summary;
}
