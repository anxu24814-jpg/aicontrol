// SessionTraceDb.ets — 会话轨迹域读口（任务书-会话轨迹视图-20261007 §4.1）
// 职责一句话：会话轨迹视图的取数面——消息尾窗（沿活跃分支 parent 链尾部翻页）、run 编年、
// 工具事实（含 v54 finishedAt）、轮级用量（purpose='chat'）、诊断节点反查；全件零写口。
// ★ 反碎片申报（变更记录同笔）：为何不并入 MessageBranchDb——该件剔头 1181、并入即破 1200
// 硬线（宪法「>1200 对它的实质改动须先拆本次改动所属功能域」+「新增功能域一律先拆」）；本件为
// 真读函数非转接壳；并入 ChatContextSource 同不可（该件贴线），GraphTransfer 职责 = 进出库。
// ★ 对任务书两处执行期增补（实读依据）：
//   ① 消息行必须用图侧读投影原样（含 runId/stepIndex/origin）——readRecentRows 返回的
//      MessageRow 经 adaptPathRows 只搬 8 字段，runId/stepIndex 在适配中丢失，无法按 run 分组；
//   ② 诊断节点不在 head 读路径上（MessageBranchDb.finishRun 头注释 LB-4③ 订正：诊断节点挂
//      输入锚、与终答互为兄弟），只能按 run.diagnosticMessageId 反查——故有 queryTraceMessagesByIds。
// ★ 用量读口按窗口 run 集合收窄（任务书作「按会话」）——数据有界红线：长会话全量用量行无需装载。
// 读纪律：ResultSet 在本层 close；SQL 字面量注释约束同 ChatDbSchema（注释置声明前、串内禁嵌引号词）。
import { relationalStore } from '@kit.ArkData';
import { sharedRdbStore, queryConversationActiveBranch } from './ChatDb';
import { GraphPathRow, readPathPage } from './MessageBranchDb';
import { TraceRowIn, TraceRunIn, TraceFactIn, TraceUsageIn } from '../chat/SessionTraceModel';

// 消息尾窗装载上限（任务书 §4.3 数据有界红线：200 条、尾部优先；超限截断由页面呈报）
export const TRACE_TAIL_LIMIT: number = 200;
// readPathPage 单页上限（库层契约 limit ≤ 50——会话轨迹固定单页 50 翻页）
const TRACE_PAGE_LIMIT: number = 50;

export interface TraceMessageWindow {
  rows: TraceRowIn[];
  truncated: boolean;
}

// 消息尾窗（尾部优先沿活跃分支 parent 链翻页；无活动分支会话回空——含无行会话与旧格式墓碑，
// 判据分层由页面按 conversationHasRow / conversationWritableRoute 先行，见任务书 §2.5）
export async function readTraceMessageWindow(conversationId: string,
  limit: number): Promise<TraceMessageWindow> {
  const branchId: string = await queryConversationActiveBranch(conversationId);
  if (branchId === '') {
    return { rows: [], truncated: false };
  }
  const db: relationalStore.RdbStore = sharedRdbStore();
  const budget: number = limit + 1; // 多取一行探测截断（有第 limit+1 行 = 超限）
  const pages: GraphPathRow[][] = [];
  let cursor: string | null = null;
  let total: number = 0;
  while (total < budget) {
    const take: number = Math.min(TRACE_PAGE_LIMIT, budget - total);
    const page: GraphPathRow[] = await readPathPage(db, branchId, cursor, take);
    if (page.length === 0) {
      break;
    }
    pages.unshift(page); // 页序反着收（后取页更早），展开即根 → 起点升序
    total += page.length;
    cursor = page[0].id; // 游标 = 本页最早节点（readPathPage 翻页语义：不含自身）
    if (page.length < take) {
      break; // 已到根（链完整读完）
    }
  }
  const flat: TraceRowIn[] = [];
  for (const page of pages) {
    for (const p of page) {
      flat.push({ id: p.id, role: p.role, content: p.content, createdAt: p.createdAt,
        runId: p.runId, stepIndex: p.stepIndex });
    }
  }
  let truncated: boolean = false;
  if (flat.length > limit) {
    flat.splice(0, flat.length - limit); // 尾部优先：丢最早的多取行
    truncated = true;
  }
  return { rows: flat, truncated: truncated };
}

// run 编年（会话全量，升序；窗口外旧轮仍占轮号——轮号 = 本序 1 起序号）
export async function queryRunRowsByConversation(conversationId: string): Promise<TraceRunIn[]> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT id, status, diagnosticMessageId, createdAt, updatedAt FROM generation_runs ' +
    'WHERE conversationId = ? ORDER BY createdAt ASC, id ASC', [conversationId]);
  const rows: TraceRunIn[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        id: result.getString(result.getColumnIndex('id')),
        status: result.getString(result.getColumnIndex('status')),
        diagnosticMessageId: result.getString(result.getColumnIndex('diagnosticMessageId')),
        createdAt: result.getLong(result.getColumnIndex('createdAt')),
        updatedAt: result.getLong(result.getColumnIndex('updatedAt'))
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// 单 run 精确读（任务书 §7.2）：SELECT 与全会话读口
// 同五列，WHERE conversationId + id 双条件；找不到回 null、查询异常原样 reject、ResultSet
// finally close。用途 = 实时链「本轮耗时」读回（一条 run 一次，不为读一轮调全会话读口）
export async function queryRunRowById(conversationId: string,
  runId: string): Promise<TraceRunIn | null> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT id, status, diagnosticMessageId, createdAt, updatedAt FROM generation_runs ' +
    'WHERE conversationId = ? AND id = ?', [conversationId, runId]);
  try {
    if (!result.goToNextRow()) {
      return null;
    }
    return {
      id: result.getString(result.getColumnIndex('id')),
      status: result.getString(result.getColumnIndex('status')),
      diagnosticMessageId: result.getString(result.getColumnIndex('diagnosticMessageId')),
      createdAt: result.getLong(result.getColumnIndex('createdAt')),
      updatedAt: result.getLong(result.getColumnIndex('updatedAt'))
    };
  } finally {
    result.close();
  }
}

// 工具事实（按 run 集合；rowid 次序 = 插入序 = 派发调用序——配对序锚）
export async function queryToolFactsByRunIds(runIds: string[]): Promise<TraceFactIn[]> {
  if (runIds.length === 0) {
    return [];
  }
  const db: relationalStore.RdbStore = sharedRdbStore();
  const marks: string = runIds.map((_v: string): string => '?').join(',');
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT id, runId, state, payload, result, createdAt, finishedAt FROM tool_facts ' +
    'WHERE runId IN (' + marks + ') ORDER BY createdAt ASC, rowid ASC', runIds);
  const rows: TraceFactIn[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        id: result.getString(result.getColumnIndex('id')),
        runId: result.getString(result.getColumnIndex('runId')),
        state: result.getString(result.getColumnIndex('state')),
        payload: result.getString(result.getColumnIndex('payload')),
        result: result.getString(result.getColumnIndex('result')),
        createdAt: result.getLong(result.getColumnIndex('createdAt')),
        finishedAt: result.getLong(result.getColumnIndex('finishedAt'))
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// 轮级用量（按 run 集合取 purpose='chat' 行——旁路调用（标题/记忆/建议/OCR/探针/主动消息）
// 自带各自 purpose，天然不进；一轮恰一行由写侧 requestId=runId 去重保证）
export async function queryChatUsageByRunIds(runIds: string[]): Promise<TraceUsageIn[]> {
  if (runIds.length === 0) {
    return [];
  }
  const db: relationalStore.RdbStore = sharedRdbStore();
  const marks: string = runIds.map((_v: string): string => '?').join(',');
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT runId, promptTokens, cachedTokens, completionTokens, totalTokens, durationMs, ' +
    'firstTokenMs FROM token_usage_events WHERE runId IN (' + marks + ') AND purpose = \'chat\' ' +
    'ORDER BY createdAt ASC', runIds);
  const rows: TraceUsageIn[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        runId: result.getString(result.getColumnIndex('runId')),
        promptTokens: result.getLong(result.getColumnIndex('promptTokens')),
        cachedTokens: result.getLong(result.getColumnIndex('cachedTokens')),
        completionTokens: result.getLong(result.getColumnIndex('completionTokens')),
        totalTokens: result.getLong(result.getColumnIndex('totalTokens')),
        durationMs: result.getLong(result.getColumnIndex('durationMs')),
        firstTokenMs: result.getLong(result.getColumnIndex('firstTokenMs'))
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// 诊断节点反查（按 id 集合；失败/中止轮的 notice 行不在 head 读路径上，经
// run.diagnosticMessageId 反查补入——见件头①/②申报）
export async function queryTraceMessagesByIds(ids: string[]): Promise<TraceRowIn[]> {
  if (ids.length === 0) {
    return [];
  }
  const db: relationalStore.RdbStore = sharedRdbStore();
  const marks: string = ids.map((_v: string): string => '?').join(',');
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT id, role, content, createdAt, runId, stepIndex FROM messages WHERE id IN (' +
    marks + ')', ids);
  const rows: TraceRowIn[] = [];
  try {
    while (result.goToNextRow()) {
      const stepIdx: number = result.getColumnIndex('stepIndex');
      rows.push({
        id: result.getString(result.getColumnIndex('id')),
        role: result.getString(result.getColumnIndex('role')),
        content: result.getString(result.getColumnIndex('content')),
        createdAt: result.getLong(result.getColumnIndex('createdAt')),
        runId: result.getString(result.getColumnIndex('runId')),
        stepIndex: result.isColumnNull(stepIdx) ? null : result.getLong(stepIdx)
      });
    }
  } finally {
    result.close();
  }
  return rows;
}
