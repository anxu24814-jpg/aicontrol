// 排队消息存储域：send_queue_items 表（v57）行读写单源——会话队列装载（hydrate）/ 入队增行 /
// 编辑文本回写 / 换序整组重写 / 单条删行 / 会话清空；send_queue_state 表（v58，一行一会话的
// 运行态：queryQueueState / upsertQueueState）同件承载（同域、同会话锚点、同两处级联删，
// 反碎片②并入优先）。两表语义与列义单源 = ChatDbSchema 两建表串注释。
// · 反碎片申报②：无同域既有件可并——队列是独立新功能域的持久面（ChatDb 是线性/图主域且
//   软区贴线），照 MountDb/WorkspaceDb「新表行读写单源新件」纪律。
// · 依赖方向红线（照 MountDb 同款）：①本文件不 import ChatDb——store 句柄由调用方传入
//   （级联删行在 ChatDb/AssistantDb 两事务内 SQL 直写，零环）；②写事务全入写串行链
//   （DbWriteQueue.runWriteQueued，与既有写者同链 FIFO，「入队插入 vs 出队删行 vs 清空」
//   次序天然确定）。
// · 出队删行**不在本件裸删**——删行必须与 user 消息行 + run 行同一事务提交，实现位在
//   MessageBranchDb.prepareRun，唯一共享物 = 本件导出的 SQL_DELETE_SEND_QUEUE_ITEM（单源，
//   禁各处自拼写）；本件 deleteQueueItem 只服务用户删除/清空（与出队是两条事务语义）。
// · 无行会话守卫（Q3-7）：入队行只在会话行已出生时落库（INSERT 前同链查 conversations）——
//   未出生由调用方保持内存暂存、会话行出生后派发试探重试本口；不落库 = 无孤儿排队行。
// · ★ 不进 EXPORT_TABLES：排队是发送意图非资产事实（price_templates/folder_mounts/
//   memory_snapshots 先例，恢复语义无需定义）。
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { runWriteQueued } from './DbWriteQueue';

const DOMAIN: number = 0x0001;
const TAG: string = 'ChatSendQueueDb';

// 排队行（列义见 ChatDbSchema.SQL_CREATE_SEND_QUEUE_ITEMS 注释）
export interface SendQueueItemRow {
  id: string;
  conversationId: string;
  sortOrder: number;
  payload: string;
  createdAt: number;
  updatedAt: number;
}

// 载荷结构（文本 only 无附件序列化面——带附件由 Q2 入口层拒绝入队，裁定丙-8）
export interface SendQueuePayload {
  text: string;
  designateId: string;
  queuedAt: number;
}

// 事务内删行唯一 SQL（出队消费方 = MessageBranchDb.prepareRun——与 user 行/run 行同事务；
// 本件 deleteQueueItem 亦复用它，防两处自拼写漂移）
export const SQL_DELETE_SEND_QUEUE_ITEM: string = 'DELETE FROM send_queue_items WHERE id = ?';

const QUEUE_COLUMNS: string = 'id, conversationId, sortOrder, payload, createdAt, updatedAt';

// ── 纯函数（断言直跑面；顶层零外部绑定求值——坑50）──

// 载荷序列化（键序固定 = text/designateId/queuedAt，人读与断言面稳定）
export function serializeQueuePayload(payload: SendQueuePayload): string {
  return JSON.stringify({
    'text': payload.text,
    'designateId': payload.designateId,
    'queuedAt': payload.queuedAt
  });
}

// 载荷解析（坏 JSON / 缺键 / 空文本 / 非数值 queuedAt → null，调用方跳过该行并留痕——
// P0-1 不静默；空文本条目在入队层已被拒，落库行理论不达，此处按防御性坏形处理）
export function parseQueuePayload(raw: string): SendQueuePayload | null {
  let parsed: Object;
  try {
    parsed = JSON.parse(raw) as Object;
  } catch (e) {
    return null;
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return null;
  }
  const rec: Record<string, Object> = parsed as Record<string, Object>;
  const text: Object | undefined = rec['text'];
  if (typeof text !== 'string' || text === '') {
    return null;
  }
  const designateId: Object | undefined = rec['designateId'];
  if (designateId !== undefined && typeof designateId !== 'string') {
    return null;
  }
  const queuedAt: Object | undefined = rec['queuedAt'];
  if (typeof queuedAt !== 'number') {
    return null;
  }
  const payload: SendQueuePayload = {
    text: text,
    designateId: typeof designateId === 'string' ? designateId : '',
    queuedAt: queuedAt
  };
  return payload;
}

// ── 行读写（句柄由调用方传入，零 import ChatDb——零环）──

// 会话队列装载（顺序真源 = sortOrder → createdAt → id 三重决胜；行轻且单会话 ≤20 行，
// 全量取回不设 LIMIT——引擎层上限守门，读口不截断防丢条）
export async function queryQueueItems(db: relationalStore.RdbStore,
  conversationId: string): Promise<SendQueueItemRow[]> {
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT ' + QUEUE_COLUMNS + ' FROM send_queue_items WHERE conversationId = ? ' +
    'ORDER BY sortOrder ASC, createdAt ASC, id ASC', [conversationId]);
  const rows: SendQueueItemRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        id: result.getString(result.getColumnIndex('id')),
        conversationId: result.getString(result.getColumnIndex('conversationId')),
        sortOrder: result.getLong(result.getColumnIndex('sortOrder')),
        payload: result.getString(result.getColumnIndex('payload')),
        createdAt: result.getLong(result.getColumnIndex('createdAt')),
        updatedAt: result.getLong(result.getColumnIndex('updatedAt'))
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// 会话行在场判据（无行会话守卫——与 INSERT 同段排队，无检查/写入窗口）
async function conversationRowExists(db: relationalStore.RdbStore,
  conversationId: string): Promise<boolean> {
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT id FROM conversations WHERE id = ? LIMIT 1', [conversationId]);
  try {
    return result.rowCount > 0;
  } finally {
    result.close();
  }
}

// 入队增行：返回 true = 已落库；false = 会话行未出生（调用方保持内存暂存，待派发试探重试
// ——总案 Q3-7 无行会话边界，不产生孤儿排队行）。INSERT OR REPLACE：同 id 重试幂等（幂等
// 重投场景；正常路径 id 进程内唯一）。整段（查会话行 + 写）同一写链节，无 TOCTOU
export function insertQueueItem(db: relationalStore.RdbStore,
  row: SendQueueItemRow): Promise<boolean> {
  return runWriteQueued('insertSendQueueItem', async (): Promise<boolean> => {
    if (!(await conversationRowExists(db, row.conversationId))) {
      return false;
    }
    await db.executeSql('INSERT OR REPLACE INTO send_queue_items ' +
      '(id, conversationId, sortOrder, payload, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?)',
      [row.id, row.conversationId, row.sortOrder, row.payload, row.createdAt, row.updatedAt]);
    return true;
  });
}

// 编辑保存（只改 payload——文本与 designateId 随条目快照重序列化；queuedAt 不变）
export function updateQueueItemPayload(db: relationalStore.RdbStore, id: string,
  payload: string, updatedAt: number): Promise<void> {
  return runWriteQueued('updateSendQueueItemPayload', async (): Promise<void> => {
    await db.executeSql('UPDATE send_queue_items SET payload = ?, updatedAt = ? WHERE id = ?',
      [payload, updatedAt, id]);
  });
}

// 换序持久化（总案 Q3-8 缺省 = 整组序号重写，≤20 行 trivial）：orderedIds 为内存队列当前
// 全序，逐行 UPDATE sortOrder = 下标；未落库的暂存项 0 行命中（其入队插入按插入时下标写）
export function reorderQueueItems(db: relationalStore.RdbStore, conversationId: string,
  orderedIds: string[]): Promise<void> {
  return runWriteQueued('reorderSendQueueItems', async (): Promise<void> => {
    const now: number = Date.now();
    for (let i = 0; i < orderedIds.length; i++) {
      await db.executeSql('UPDATE send_queue_items SET sortOrder = ?, updatedAt = ? ' +
        'WHERE id = ? AND conversationId = ?', [i, now, orderedIds[i], conversationId]);
    }
  });
}

// 单条删行（用户删除；出队删行走 prepareRun 事务口，不经本函数）
export function deleteQueueItem(db: relationalStore.RdbStore, id: string): Promise<void> {
  return runWriteQueued('deleteSendQueueItem', async (): Promise<void> => {
    await db.executeSql(SQL_DELETE_SEND_QUEUE_ITEM, [id]);
  });
}

// 会话清空（用户「清空队列」；级联删行走 ChatDb/AssistantDb 两事务，不经本函数）
export function deleteQueueItemsByConversation(db: relationalStore.RdbStore,
  conversationId: string): Promise<void> {
  return runWriteQueued('deleteSendQueueItemsByConversation', async (): Promise<void> => {
    await db.executeSql('DELETE FROM send_queue_items WHERE conversationId = ?',
      [conversationId]);
  });
}

// 行解码（hydrate 单点：坏载荷跳过并留痕——队列行是用户消息，坏形不静默吞）
export function decodeQueueRow(row: SendQueueItemRow): SendQueuePayload | null {
  const payload: SendQueuePayload | null = parseQueuePayload(row.payload);
  if (payload === null) {
    hilog.warn(DOMAIN, TAG, '排队行载荷无法解析，已跳过：%{public}s', row.id);
  }
  return payload;
}

// ── 会话级运行态行（v58；列义见 ChatDbSchema.SQL_CREATE_SEND_QUEUE_STATE 注释）──

// 运行态行（列义同建表串）
export interface SendQueueStateRow {
  conversationId: string;
  runState: string;
  pauseReason: string;
  updatedAt: number;
}

// 运行态装载：无行返回 null（= 从未写过 = ACTIVE，调用方按缺省处理）；只搬数据不做值域
// 归一（'PAUSED' 之外的脏值由队列域归一为 ACTIVE——归一判据单源在域件，本口不重复）
export async function queryQueueState(db: relationalStore.RdbStore,
  conversationId: string): Promise<SendQueueStateRow | null> {
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT conversationId, runState, pauseReason, updatedAt FROM send_queue_state ' +
    'WHERE conversationId = ? LIMIT 1', [conversationId]);
  try {
    if (!result.goToNextRow()) {
      return null;
    }
    const row: SendQueueStateRow = {
      conversationId: result.getString(result.getColumnIndex('conversationId')),
      runState: result.getString(result.getColumnIndex('runState')),
      pauseReason: result.getString(result.getColumnIndex('pauseReason')),
      updatedAt: result.getLong(result.getColumnIndex('updatedAt'))
    };
    return row;
  } finally {
    result.close();
  }
}

// 运行态写穿（UPSERT：一会话一行，暂停/恢复/回落 ACTIVE 全走同一句）。会话行未出生 →
// 零写返回（与入队行同款无行会话守卫，不产生孤儿行；会话行出生后下一次状态变更自然补写）。
// 整段（查会话行 + 写）同一写链节，与入队/出队删行同链 FIFO——pause → resume 快连不乱序
export function upsertQueueState(db: relationalStore.RdbStore,
  row: SendQueueStateRow): Promise<void> {
  return runWriteQueued('upsertSendQueueState', async (): Promise<void> => {
    if (!(await conversationRowExists(db, row.conversationId))) {
      return;
    }
    await db.executeSql('INSERT OR REPLACE INTO send_queue_state ' +
      '(conversationId, runState, pauseReason, updatedAt) VALUES (?, ?, ?, ?)',
      [row.conversationId, row.runState, row.pauseReason, row.updatedAt]);
  });
}
