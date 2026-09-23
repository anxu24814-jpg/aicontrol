// 压缩摘要存储域（2026-09-23 上下文压缩，任务书-上下文压缩-20260923 §2.1）：messages 表
// role='summary' 行（coversToSeq = 覆盖边界）的读写与边界查询收拢本文件。
// · 为什么新开本件而不并入 ChatDb.ets（宪法「反碎片下限」三问）：①职责一句话 = 压缩摘要行
//   的读写与边界查询，有独立职责缝；②无既有同域可并——MessageVariantDb 管多版本、
//   MessageSeqDb 管序号，各为别表主域，ChatDb.ets 剔头 1192 本笔 +50 量级会越 1200 硬线；
//   ③实逻辑非转接壳。
// · 依赖方向（零环红线，坑50）：本件 → ChatDb（sharedRdbStore / nextMessageId /
//   nextRowCreatedAt / deleteMessagesBy）+ MessageSeqDb（nextRowSeq）+ AttachmentDb
//   （deleteAttachmentsForMessages——级联铁律件）；**禁反向**（ChatDb 不 import 本件）。
// · ★ D1 红线（MessageSeqDb 头注释，09-19 与 D4-1 两次真机实锤）：摘要行的 seq 必须由
//   **写入侧分配器**在构造行对象的同一同步块内铸造（nextRowSeq），禁 SQL 侧 MAX(seq)+1、
//   禁 await 之后再补铸——本域全部写函数的铸造都在函数体首个 await 之前。
// · 摘要行的其余列恒定值：status='done'、reasoning=''、variants=''（单版语义）；
//   content = **纯摘要正文**（不含包装语——包装语是组装时常量，见 RequestInject）。
// · 每会话至多一条生效摘要（采用新摘要时同事务删旧行，见 adoptCompressSummary）；
//   更早的摘要行在请求组装侧被自然吞掉（seq <= boundary 一律不进请求）。
import { relationalStore } from '@kit.ArkData';
import { deleteAttachmentsForMessages } from './AttachmentDb';
import { MessageRow, deleteMessagesBy, nextMessageId, nextRowCreatedAt,
  sharedRdbStore } from './ChatDb';
import { nextRowSeq } from './MessageSeqDb';

// 摘要行 id 前缀（nextMessageId 用；仅供人读，跨库拦截不靠前缀）
const SUMMARY_ID_PREFIX: string = 'sum';

// 最新生效摘要行（按 seq DESC 取第一条 role='summary'；无摘要 = null）。投影带 coversToSeq
// ——面板状态行与请求组装的边界判据都从本函数来（单一读取口，两消费方不各写查询）
export async function queryLatestSummary(conversationId: string): Promise<MessageRow | null> {
  const result: relationalStore.ResultSet = await sharedRdbStore().querySql(
    'SELECT id, conversationId, role, content, reasoning, status, createdAt, rowid, seq, ' +
    'variants, variant_active, coversToSeq FROM messages ' +
    'WHERE conversationId = ? AND role = \'summary\' ORDER BY seq DESC LIMIT 1',
    [conversationId]);
  try {
    if (result.goToNextRow()) {
      const row: MessageRow = {
        id: result.getString(result.getColumnIndex('id')),
        conversationId: result.getString(result.getColumnIndex('conversationId')),
        role: 'summary',
        content: result.getString(result.getColumnIndex('content')),
        reasoning: '',
        status: result.getString(result.getColumnIndex('status')),
        createdAt: result.getLong(result.getColumnIndex('createdAt')),
        rowid: result.getLong(result.getColumnIndex('rowid')),
        seq: result.getLong(result.getColumnIndex('seq')),
        variants: '',
        variantActive: 0
      };
      const coversIdx: number = result.getColumnIndex('coversToSeq');
      if (!result.isColumnNull(coversIdx)) {
        row.coversToSeq = result.getLong(coversIdx);
      }
      return row;
    }
    return null;
  } finally {
    result.close();
  }
}

// 摘要行插入（自持 INSERT，四值一次写全：id / seq / createdAt / coversToSeq）。
// ★ 禁改走 ChatDb.insertMessage——它的 bucket 是白名单键（id/conversationId/role/content/
// reasoning/status/createdAt + 条件 seq），**不带 coversToSeq**，走它会静默落 NULL =
// 边界丢失、压缩整个不生效。铸造（nextRowSeq/nextRowCreatedAt）在函数体首个 await 之前
// （D1 红线）；本函数不开事务——独立调用（面板无此形态）与 adoptCompressSummary 事务内
// 调用两用（db.insert 在外层事务内天然参与该事务）
export async function insertSummaryMessage(conversationId: string, content: string,
  coversToSeq: number): Promise<string> {
  const id: string = nextMessageId(SUMMARY_ID_PREFIX);
  const seq: number = nextRowSeq(conversationId);
  const createdAt: number = nextRowCreatedAt();
  const bucket: relationalStore.ValuesBucket = {
    'id': id,
    'conversationId': conversationId,
    'role': 'summary',
    'content': content,
    'reasoning': '',
    'status': 'done',
    'createdAt': createdAt,
    'variants': '',
    'variant_active': 0,
    'seq': seq,
    'coversToSeq': coversToSeq
  };
  await sharedRdbStore().insert('messages', bucket);
  return id;
}

// 边界时间查询（面板状态行「覆盖 … 之前的内容」的时间来源）：取该 seq 行的 createdAt，
// 缺行回 0（边界行已被用户删除——面板据此退化为不带时间的形态，别为凑时间造第二个时钟源）
export async function queryBoundaryCreatedAt(conversationId: string,
  seq: number): Promise<number> {
  const result: relationalStore.ResultSet = await sharedRdbStore().querySql(
    'SELECT createdAt FROM messages WHERE conversationId = ? AND seq = ? LIMIT 1',
    [conversationId, seq]);
  try {
    if (result.goToNextRow()) {
      return result.getLong(result.getColumnIndex('createdAt'));
    }
    return 0;
  } finally {
    result.close();
  }
}

// 采用摘要（唯一落库写点，一次事务）：插入新摘要行 + 删除被它吞掉的旧摘要行（若有——
// 「库里只留一条生效摘要，流里不会出现多条失效提示」）。返回新行 id。★ 旧摘要行删除不借
// ChatDb.deleteMessagesBy——它自开事务，嵌套 beginTransaction 会抛「嵌套」错（applyMemoryImport
// 同款取舍：事务内逐件调用不开事务的底层件）；级联铁律仍守（删 messages 路径同事务删附件行
// ——摘要行理论无附件，deleteAttachmentsForMessages 为铁律兜底）
export async function adoptCompressSummary(conversationId: string, content: string,
  coversToSeq: number): Promise<string> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  db.beginTransaction();
  try {
    // 旧摘要行收集（事务内读——读到的是与写入同一快照）
    const oldResult: relationalStore.ResultSet = await db.querySql(
      'SELECT id FROM messages WHERE conversationId = ? AND role = \'summary\'',
      [conversationId]);
    const oldIds: string[] = [];
    try {
      while (oldResult.goToNextRow()) {
        oldIds.push(oldResult.getString(oldResult.getColumnIndex('id')));
      }
    } finally {
      oldResult.close();
    }
    if (oldIds.length > 0) {
      const attachPaths: string[] = await deleteAttachmentsForMessages(db, oldIds);
      const predicates: relationalStore.RdbPredicates =
        new relationalStore.RdbPredicates('messages');
      predicates.in('id', oldIds);
      await db.delete(predicates);
    }
    const newId: string = await insertSummaryMessage(conversationId, content, coversToSeq);
    db.commit();
    return newId;
  } catch (e) {
    db.rollBack();
    throw e as Error;
  }
}

// 删除摘要（面板「删除摘要」键落点）：复用既有批删（事务 + 附件级联，勿另写）。
// 空集 0 直接返回
export function deleteSummaryRows(ids: string[]): Promise<number> {
  return deleteMessagesBy(ids);
}
