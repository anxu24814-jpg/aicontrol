// 附件元数据存储域：message_attachments 表行读写 + 级联删除 + 库盘一致性收敛。
// · 依赖方向红线：本文件不 import ChatDb（store 句柄由调用方传入，防 ChatDb → 本件 →
//   ChatDb 环；ChatDb/AssistantDb/ExportImport 持句柄调用）；亦不 import AttachmentUtil
//（AttachmentUtil 反向 import 本件的 MessageAttachmentRow，依赖单向）；ATTACH_DIR_NAME 与
//   AttachmentUtil.ATTACH_DIR 同值，两文件互不 import，断言钉一致。图侧判定面同理**不
//   import 图域件**——本件 → MessageBranchDb → ChatDb 与 ChatDb → 本件 成双向边（ArkTS
//   类型检查器在环上崩坏，坑50），故 computeAttachmentSurvivors 走注入
//（AttachmentGraphCleanup，构造 = GraphTransfer.buildAttachmentGraphCleanup；传入 =
//   EntryAbility / ExportImport），本件只读行与删行。
// · 级联删除铁律：任何新增「删 messages」路径，必须在同函数同事务内删附件行——全仓删
//   messages 落点 = ChatDb.deleteConversations + AssistantDb.deleteAssistantCascade 两处；
//   行删先 SELECT 收集 localPath、文件 I/O 在 commit 之后（回滚不得已删文件）。
// · 一致性收敛（reconcileAttachments）：孤儿行（messageId 不在 messages 表）删行；图侧
//   不可达空串行（图能力 ≥2 才跑，否则保护不删）删行；孤儿文件（filesDir/attachments 下
//   不在现存行 localPath 集**且 mtime 早于本进程启动**——在途保护闸，防误删「输入栏挂着
//   未发的附件」）删文件；判定单源 = collectOrphanFiles（收敛与存储页清理预览/实删共用，
//   显示数与实删数必然一致）。「行在文件不在」**不删行**（决明拍板——元数据不轻易丢弃；
//   与 RikkaHub syncFolder 删行策略的有意分叉）。
// · I/O 口径：删文件 best-effort（失败静默自愈，启动收敛非轮询）；查询面全部有界分页、
//   列表类**不取 parsedText** 大字段。
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
// 按时间批量删除入链（deleteAttachmentsByCutoff 走 runWriteQueued 与全仓写事务互斥——
// 14800024 收口口径）。依赖无环：DbWriteQueue 零本地 import，本件 → DbWriteQueue 单向
import { runWriteQueued } from './DbWriteQueue';

const DOMAIN: number = 0xDACC;
const TAG: string = 'AttachmentDb';
// 常驻区目录名（与 AttachmentUtil.ATTACH_DIR 同值——见头注释依赖方向红线）
const ATTACH_DIR_NAME: string = 'attachments';

// 模块级 ctx 捕获（initAttachmentStore——EntryAbility onCreate 调一次）：无 ctx 入参的
// 文件操作用（localPath 是相对 filesDir 路径，删文件须拼绝对路径）
let attachCtx: common.UIAbilityContext | null = null;
// 进程启动时刻（initAttachmentStore 赋值）：孤儿判定在途保护闸——mtime 早于它才算孤儿
//（本进程内新建附件一律保护）。0 = 未就位，此时不删任何文件（P0-1 不冒险）
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
  // ①b 图侧不可达空串行删行数（与孤儿行分栏：孤儿行 = messageId 指向不存在的消息；本栏 =
  // 空串占位行且图判定不可达）
  graphRowsRemoved: number;
}

// ── 图侧清理判定注入面（依赖倒置，见头注释红线）──
// 判定面由**调用方注入**（构造 = GraphTransfer.buildAttachmentGraphCleanup，传入 =
// EntryAbility 启动收敛 / ExportImport 导入收敛）——本件只做「读行 → 交判定 → 按判定删行」，
// 判定规则不在本件复制第二份。pickUnreachable：入参 = 空串占位行（id + messageId）+ 全库
// 附件引用 + 现存节点全集，返回判定不可达（可清）的附件行 id 集（与 MessageBranchDb 判定面
// 入参逐字段同形，两处改名即编译期报错）。graphCleanup 传 null = 图能力不在场
//（capability < 2）：本件零查询零删除，空串行维持保护不删。
export interface AttachmentBlankOwnerRow {
  attachmentId: string;
  messageId: string;
}

export interface AttachmentGraphRefRow {
  attachmentId: string;
  nodeId: string;
}

export interface AttachmentGraphCleanup {
  pickUnreachable: (blankRows: AttachmentBlankOwnerRow[],
    refs: AttachmentGraphRefRow[], survivingNodeIds: Set<string>) => string[];
}

// ── 附件管理列表只读面 ──
// 三个分页查询成组（一级按会话聚合 / 二级按会话列行 / 全局合计）。★ 列表类查询一律**不取
// parsedText**（文档解析大字段）——AttachmentListRow 连字段都不带，类型级封死比「取了
// 不读」更难回潮。会话分组行（一级聚合）：title 取 conversations LEFT JOIN 且 SQL 侧
// IFNULL 兜空串（会话行缺失/未命名都回 ''）
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

// ctx 的沙箱目录读出口（deleteAssistantCascade 级联删头像需要 filesDir——复用本件既有
// ctx 捕获零新设施）。未捕获返回 ''——消费方按「无路径信息不删文件」处理
export function attachmentFilesDir(): string {
  return attachCtx !== null ? attachCtx.filesDir : '';
}

// 附件行批量写入（消息落库后随行；逐条插入，单行失败上抛由调用方决定留痕）
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

// 谓词两用：先按谓词收集 localPath 集，再按同款谓词删行（谓词是只读条件容器，复用安全）；
// 返回相对路径集供调用方在 commit 后删文件
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

// 按会话集删附件行（删会话/删助手两入口事务内调用；入参须纯数组——坑6 族）；空集短路
//（in() 空数组「条件失效落全表」，d.ts:2388）
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

// 按消息集删附件行（导入覆盖路径用——被覆盖消息回到备份当时状态，本机附件行随之作废）；
// 空集短路同上
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

// 按附件行 id 删单件：与按消息集删分开——一条消息可挂多件附件，按 messageId 删会连带误伤
// 同消息其余件（管理页单件语义）。空集短路同上（in() 空数组落全表）
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

// 按消息集查附件行（历史回放装配 brief 用，经 ChatDb 同名委托入口消费）。空集短路同上；
// ORDER BY rowid 保插入序 = annotate 名单序 = 显示次序前提（createdAt 同毫秒级同值不可
// 分辨，rowid 是唯一稳定插入序）。
// ★ K4 归属两源联合：graph 会话附件行用空串占位归属（messageId 列不表达归属，真源 =
// attachment_refs.nodeId）——原单源查询读不到这类行，重进会话附件卡整批消失。第二源查询
// 把 refs 归属**投影回 messageId 列**（值 = 节点 id）：消费方零改动；两源同 id 行去重
export async function queryAttachmentsForMessages(db: relationalStore.RdbStore,
  messageIds: string[]): Promise<MessageAttachmentRow[]> {
  if (messageIds.length === 0) {
    return [];
  }
  const marks: string = messageIds.map((_id: string): string => '?').join(',');
  const rows: MessageAttachmentRow[] = [];
  const seen: Set<string> = new Set<string>();
  // 源一：legacy 归属（messageId 列直配）
  await collectAttachmentRows(db, rows, seen,
    'SELECT id, messageId, conversationId, kind, name, mime, size, localPath, parsedText, createdAt ' +
    'FROM message_attachments WHERE messageId IN (' + marks + ') ORDER BY rowid', messageIds);
  // 源二：graph 归属（refs 反查；每源单独绑定 id 列表——不用 OR 单查形态，避免参数数翻倍）
  await collectAttachmentRows(db, rows, seen,
    'SELECT a.id AS id, r.nodeId AS messageId, a.conversationId AS conversationId, a.kind AS kind, ' +
    'a.name AS name, a.mime AS mime, a.size AS size, a.localPath AS localPath, ' +
    'a.parsedText AS parsedText, a.createdAt AS createdAt ' +
    'FROM message_attachments a JOIN attachment_refs r ON r.attachmentId = a.id ' +
    'WHERE r.nodeId IN (' + marks + ') ORDER BY a.rowid', messageIds);
  return rows;
}

// 附件行收集（queryAttachmentsForMessages 两源共用；同 id 去重保首见）
async function collectAttachmentRows(db: relationalStore.RdbStore, out: MessageAttachmentRow[],
  seen: Set<string>, sql: string, bind: string[]): Promise<void> {
  const result: relationalStore.ResultSet = await db.querySql(sql, bind);
  try {
    while (result.goToNextRow()) {
      const id: string = result.getString(result.getColumnIndex('id'));
      if (seen.has(id)) {
        continue;
      }
      seen.add(id);
      out.push({
        id: id,
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
}

// 一级：按会话聚合分页。排序 = 体积倒序 + conversationId 第二键——同体积组跨页不重复不
// 遗漏（单一排序键在等值处次序不定，分页游标会漂）。limit ≤ 0 空集短路（勿传 0 探底——
// 与 in() 空数组落全表同族防线）
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

// 二级：按会话列行分页（rowid DESC 最近发在前；展开某组才查，有界）。limit ≤ 0 空集短路同上
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

// 全局合计（管理页进页取一次，删除后本地递减不重算——一行聚合无 GROUP BY 开销）
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

// ── 按时间批量清理（存储管理页「清理聊天附件」面板）──
// 读数与删除两面的 SQL 与事务编排在本件，档位派生与确认文案单源在 StorageStats；清理只
// 作用于聊天附件（message_attachments 行 + attachment_refs 成对 + filesDir/attachments
// 文件），不含工作区、壁纸、缓存、日志等其他分类
// 时间谓词单源：cutoffMs 非 null → ' WHERE createdAt < ' + 毫秒数值（number 直拼无注入面；
// 谓词语义 = 保留窗口，严格 <，恰等界线保留）；null → ''（全部档）。读数 SELECT 与删行
// 收集 SELECT **同引本函数**——「显示 = 实删」同源落法（assert-attach-domain 97 组同源钉
// 守两消费点）。★ SQL 字面量形态约束（同 154 组口径）：本组 SQL 一律单引号字面量、字面量
// 间不夹注释——抽出器逐段读连续单引号串
function attachCutoffWhere(cutoffMs: number | null): string {
  return cutoffMs === null ? '' : ' WHERE createdAt < ' + cutoffMs;
}

// 按时间界线读数（清理面板行尾「N 个 X」）：与 queryAttachmentTotal 同口径仅多谓词段；
// createdAt 无索引（个人应用千行级毫秒级）——开面板现读非轮询（有界）
export async function readAttachmentCleanPreview(db: relationalStore.RdbStore,
  cutoffMs: number | null): Promise<AttachmentTotalRow> {
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT COUNT(*) AS cnt, IFNULL(SUM(size), 0) AS bytes FROM message_attachments' +
    attachCutoffWhere(cutoffMs));
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

// 按时间清理每批条数（仅约束 in() 绑定参数规模）：2 条 SQL × 批宽展开 N 绑定参数，批 300
// ⇒ 600，稳低于 SQLite 变量数下限 999（deleteConversations 把 id 集展开到十一处谓词 ≈11N
// 乘数，本函数无此乘数故批宽可取数百）
const ATTACH_DEL_BATCH: number = 300;

// 按时间界线批量删（与 readAttachmentCleanPreview 同引谓词——「显示 = 实删」）。步骤照
// deleteConversations 八步范本裁剪：①链外读段收集 id + localPath（纯数组坑6 族），空集
// 短路返回 0；②runWriteQueued 入链（与全仓写事务互斥，14800024 收口口径；不复用未入链
// 旧路）分批短事务收窄撞锁窗口；③每批一个短事务：先删 attachment_refs（成对清，legacy 行
// 无 refs 空删幂等，悬挂 refs 禁留）→ 再删 message_attachments 行 → commit；④文件删除恒
// 在该批 commit **之后**（回滚不得已删文件），best-effort 失败留自愈；⑤某批失败 rollBack
// 该批并上抛——已提交批次不回滚，无「行在文件不在」新制造；⑥返回实删行数合计。
// ★ graph 两形态：现行发送链新写入已全量 graph 空串形态（真归属 = attachment_refs），
// legacy 非空 messageId 行来自历史存量与 fork 镜像——createdAt 同表不分形态，一条谓词
// 覆盖两形态，refs 级联按筛出 id 集删即成对覆盖
export async function deleteAttachmentsByCutoff(db: relationalStore.RdbStore,
  cutoffMs: number | null): Promise<number> {
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT id, localPath FROM message_attachments' + attachCutoffWhere(cutoffMs));
  const ids: string[] = [];
  const paths: string[] = [];
  try {
    while (result.goToNextRow()) {
      ids.push(result.getString(result.getColumnIndex('id')));
      paths.push(result.getString(result.getColumnIndex('localPath')));
    }
  } finally {
    result.close();
  }
  if (ids.length === 0) {
    return 0;
  }
  let removed: number = 0;
  await runWriteQueued('deleteAttachmentsByCutoff', async (): Promise<void> => {
    for (let i = 0; i < ids.length; i += ATTACH_DEL_BATCH) {
      const batchIds: string[] = ids.slice(i, i + ATTACH_DEL_BATCH);
      const batchPaths: string[] = paths.slice(i, i + ATTACH_DEL_BATCH);
      db.beginTransaction();
      try {
        const refPredicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('attachment_refs');
        refPredicates.in('attachmentId', batchIds);
        await db.delete(refPredicates);
        const rowPredicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('message_attachments');
        rowPredicates.in('id', batchIds);
        const deleted: number = await db.delete(rowPredicates);
        db.commit();
        removed += deleted;
        removeAttachmentFiles(batchPaths);
      } catch (e) {
        db.rollBack();
        throw e as Error;
      }
    }
  });
  return removed;
}

// 按会话附件计数（会话统计卡「附件数」行——冗余列免 join）。查询失败上抛由调用方降级
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

// 按相对路径集删常驻区文件（commit 成功后调用；best-effort——失败留自愈，不回滚不打扰）
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

// 附件资源文件复制（fork「先准备新资源文件」的文件面单点）：把源资源复制成**新文件名**
//（<新 attachmentId><源扩展名>），返回新相对路径（与 localPath 同形，调用方直接入库）。
// **只新建文件、不写任何库行**——元数据行与 refs 由调用方在同一发布事务里写。
// · fail-closed（P0-1 不静默）：ctx 未捕获 / 源文件不存在 / 源文件为空 → 抛错，调用方按
//   附件显示名呈报缺件（缺件必须阻止本次 fork 并指出缺件）。
// · 在途保护：新文件落常驻目录、mtime 晚于本进程启动 ⇒ 天然落 collectOrphanFiles 保护闸，
//   准备期与失败残留期不会被误删；真正无主残留由下次启动按孤儿回收。
// · 复制姿势 = openSync(READ_ONLY) → openSync(CREATE|READ_WRITE) → copyFileSync(fd, fd)
//   → 成对 closeSync（镜像 ImageEditUtil.copyFileExact 三步 fd 法；不 import 该件——store
//   层引图像域 kit 依赖会污染断言夹具模块可达图）。
// · 失败自清：目标文件「本次创建」时复制中途抛错由本函数兜底删半截目标（原实现失败路径
//   半截文件无人清、成常驻目录孤儿）；既有同名文件不归本函数清；自清失败吞异常不吞原始错误。
export function copyAttachmentResource(sourceLocalPath: string,
  newFileName: string): string {
  if (attachCtx === null) {
    throw new Error('附件目录未就绪，无法复制附件文件');
  }
  const srcAbs: string = attachCtx.filesDir + '/' + sourceLocalPath;
  if (!fs.accessSync(srcAbs)) {
    throw new Error('源文件在本机已找不到');
  }
  if (fs.statSync(srcAbs).size <= 0) {
    throw new Error('源文件内容为空，已损坏');
  }
  const newRel: string = ATTACH_DIR_NAME + '/' + newFileName;
  const destAbs: string = attachCtx.filesDir + '/' + newRel;
  // 自清归属判据前置：目标原不存在 ⇒ 本次创建 ⇒ 失败归本函数清（新名由新 id 铸造同名理论
  // 不达，此闸只为不误伤既有文件）
  const destExisted: boolean = fs.accessSync(destAbs);
  const srcFile: fs.File = fs.openSync(srcAbs, fs.OpenMode.READ_ONLY);
  try {
    const destFile: fs.File = fs.openSync(destAbs,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    try {
      fs.copyFileSync(srcFile.fd, destFile.fd);
    } finally {
      fs.closeSync(destFile);
    }
  } catch (e) {
    if (!destExisted) {
      try {
        fs.unlinkSync(destAbs);
      } catch (cleanupErr) {
        // 删不掉（占用/权限）留残留：启动孤儿收敛兜底，不吞原始错误
      }
    }
    throw e as Error;
  } finally {
    fs.closeSync(srcFile);
  }
  return newRel;
}

// 孤儿文件判定单源（reconcileAttachments 与 StorageStats.scanCleanables/cleanOrphan
// Attachments 共用——存储页显示数与实删数必然一致）：存活行 localPath 全集 → 目录内不在
// 集者，再过在途保护闸（mtime 早于本进程启动）。返回相对 filesDir 路径集。进程启动时刻
// 未就位返回空集——无保护窗口信息不删，warn 留痕（P0-1 不静默）
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
        // mtime 单位 = 秒（fs.d.ts Stat.mtime 实锤）换算毫秒比；秒级粒度下「与启动同秒」按
        // 不早于启动处理（保守方向 = 保护，不误删）
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

// 图侧不可达空串行清理（判定面注入，规则单源 = computeAttachmentSurvivors）：空串占位行 →
// 全库 refs → 现存节点全集（messages.id）→ 注入判定面挑不可达 → 按 id 集一次谓词删行
//（删行先于 ②collectOrphanFiles，其存活集随之收缩，被删行原指向的文件自然落入孤儿文件
// 一并清——文件面零改动）。查询有界：三次全表，启动一次非轮询。graphCleanup 为 null
//（图能力不在场）= 零查询零删除：空串行保护不删（空串不表达归属，无能力时不据它认定无主）
async function removeUnreachableBlankOwners(db: relationalStore.RdbStore,
  graphCleanup: AttachmentGraphCleanup | null): Promise<number> {
  if (graphCleanup === null) {
    return 0;
  }
  const blankRows: AttachmentBlankOwnerRow[] = [];
  const blankResult: relationalStore.ResultSet = await db.querySql(
    'SELECT id AS attachmentId, messageId FROM message_attachments ' +
    'WHERE LENGTH(messageId) = 0');
  try {
    while (blankResult.goToNextRow()) {
      blankRows.push({
        attachmentId: blankResult.getString(blankResult.getColumnIndex('attachmentId')),
        messageId: blankResult.getString(blankResult.getColumnIndex('messageId'))
      });
    }
  } finally {
    blankResult.close();
  }
  if (blankRows.length === 0) {
    return 0; // 无空串行 = 无图侧归属，零后续查询
  }
  const refs: AttachmentGraphRefRow[] = [];
  const refResult: relationalStore.ResultSet =
    await db.querySql('SELECT attachmentId, nodeId FROM attachment_refs');
  try {
    while (refResult.goToNextRow()) {
      refs.push({
        attachmentId: refResult.getString(refResult.getColumnIndex('attachmentId')),
        nodeId: refResult.getString(refResult.getColumnIndex('nodeId'))
      });
    }
  } finally {
    refResult.close();
  }
  // 存活集 = 现存节点全集（图节点与线性消息同表，删消息即删节点）
  const survivingNodeIds: Set<string> = new Set<string>();
  const nodeResult: relationalStore.ResultSet = await db.querySql('SELECT id FROM messages');
  try {
    while (nodeResult.goToNextRow()) {
      survivingNodeIds.add(nodeResult.getString(nodeResult.getColumnIndex('id')));
    }
  } finally {
    nodeResult.close();
  }
  const unreachableIds: string[] = graphCleanup.pickUnreachable(blankRows, refs,
    survivingNodeIds);
  if (unreachableIds.length === 0) {
    return 0;
  }
  const rowPredicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('message_attachments');
  rowPredicates.in('id', unreachableIds);
  await db.delete(rowPredicates);
  return unreachableIds.length;
}

// 库盘一致性收敛（EntryAbility 启动 + 导入成功两处调用，fire-and-forget 不阻塞调用链）：
// ①孤儿行删行（其文件在②随「不在存活集」一并清——先删行后算存活集，顺序即清理链）；
// ①b 图侧不可达空串行（graphCleanup 由调用方注入，null = 图能力不在场则整段跳过）；②孤儿
// 文件判定单源 = collectOrphanFiles（含在途保护闸）→ 删文件。「行在文件不在」不动（头注释
// 分叉说明）。失败上抛由调用方留痕，不阻断启动
export async function reconcileAttachments(ctx: common.Context,
  db: relationalStore.RdbStore,
  graphCleanup: AttachmentGraphCleanup | null): Promise<ReconcileSummary> {
  const summary: ReconcileSummary = { rowsRemoved: 0, filesRemoved: 0, graphRowsRemoved: 0 };
  // ① 孤儿行（NOT IN 反连接一条 SQL——RdbPredicates 无子查询能力）。★ 子查询带 `id IS
  // NOT NULL`：反连接的 NULL 语义坑——子查询里只要出现一个 NULL，`messageId NOT IN (...)`
  // 对所有未匹配行就不是真（三值逻辑）⇒ 孤儿行一条也选不出（行与文件双双静默留存，本函数
  // 作为兜底整体失效）；排除 NULL 不误删。★ 谓词再加 `LENGTH(messageId) > 0`（K4）：
  // graph 会话附件行用**空串占位**（归属恒经 attachment_refs.nodeId，messageId 列不表达
  // 归属），空串恒不命中任何 messages.id ⇒ 原谓词把每条 graph 附件行都判孤儿 = 用户附件
  // 真实丢失；本段恒保护空串行，其回收交给 ①b removeUnreachableBlankOwners——图能力 ≥2
  // 时按判定面裁定，能力不在场则照旧保护不删。★ SQL 字面量形态约束（改写法前先看
  // assert-store-consistency 154 组）：该组从本处抽 SQL 直跑真值表，抽出器逐段读**单引号
  // 字面量**——双引号串或字面量间夹注释都会截断，故空串行保护取 LENGTH 形态（等价
  // messageId <> ''，内含引号数为零）
  const orphanResult: relationalStore.ResultSet = await db.querySql(
    'SELECT id FROM message_attachments ' +
    'WHERE LENGTH(messageId) > 0 AND messageId NOT IN ' +
    '(SELECT id FROM messages WHERE id IS NOT NULL)');
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
  // ①b 图侧不可达空串行（capability < 2 时 graphCleanup null = 零查询零删除）。必须在 ②
  // 之前——行先删，其文件才随存活集收缩被 ② 一并清
  summary.graphRowsRemoved = await removeUnreachableBlankOwners(db, graphCleanup);
  // ② 孤儿文件（判定单源 = collectOrphanFiles；①/①b 已先行删行，其文件不在存活集一并被清）
  const orphans: string[] = await collectOrphanFiles(ctx, db);
  for (const rel of orphans) {
    try {
      fs.unlinkSync(ctx.filesDir + '/' + rel);
      summary.filesRemoved++;
    } catch {
      // 单文件失败跳过——下次启动再清（有界自愈）
    }
  }
  hilog.info(DOMAIN, TAG,
    '附件一致性收敛完成：删孤儿行 %{public}d、删图侧空串行 %{public}d、删孤儿文件 %{public}d',
    summary.rowsRemoved, summary.graphRowsRemoved, summary.filesRemoved);
  return summary;
}
