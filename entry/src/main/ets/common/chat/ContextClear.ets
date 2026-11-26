// 上下文清空边界域：**清空边界行的写入、撤销与清空读口**——清空 = 会话里新增一条 role='clear'
// 边界行 + 分支 head 前移 + summary_bindings 同拍，消息一条不删（非破坏式分界）。
// 依赖方向（零环红线，坑50）：本件 → ChatDb（句柄/铸号/会话态）/ MessageBranchDb（分支
// 命令与类型）/ MessageSeqDb（入链号）/ CompressDb（采用在途登记 + 清空行探针）/
// ChatBranchPolicy（墓碑短句单源）/ ChatContextSource 的 isNodeOnActivePath（路径核验单一
// 实现）单向；**ChatContextSource 不 import 本件**，无环。
// 与摘要边界的关系（同一套边界家族，两类节点）：摘要（role='summary'，带正文）走
// ChatGraphCommandSource.adoptGraphSummary；清空（role='clear'，正文恒空）走本件
// adoptGraphClear。两者共用 summary_bindings 作为**边界绑定**真源（表名沿历史不改）与
//「最新边界胜出」读序。
import { relationalStore } from '@kit.ArkData';
import { MessageRow, nextMessageId, nextRowCreatedAt, queryConversationActiveBranch,
  queryConversationMigrateState, sharedRdbStore } from '../store/ChatDb';
import { nextRowSeq } from '../store/MessageSeqDb';
import { runWriteQueued } from '../store/DbWriteQueue';
import { BranchRow, CONV_STATE_GRAPH, queryBranch } from '../store/MessageBranchDb';
import { isAdoptInflight, markAdopt, queryLatestClear } from '../store/CompressDb';
import { TOMBSTONE_TOAST_TEXT } from './ChatBranchPolicy';
import { isNodeOnActivePath, findPathSummaryRow } from './ChatContextSource';

// 清空采用：与 ChatGraphCommandSource.adoptGraphSummary 同骨（三道前置守卫 + 路径核验 + 事务内
// head 读取 + CAS 前移 + binding 同拍），差异两处——①role='clear'、content 恒空（清空不带
// 正文，boundary 是唯一载荷）；②不涉及任何模型调用（清空是纯本地动作，零请求零计费）。
// boundarySeq 由调用方给（= 清空点：当前活跃路径物理序最后一条**可证**消息的 seq——取库
// 行不取屏幕行，图会话读窗有上限）。
// 语义（决明拍板）：边界行之前的消息不再进请求，但**一条不删**——仍在会话流可见可回看；
// 请求侧按「物理序最后一条边界行胜出」裁段且不置顶摘要条（summaryText 空）；压缩侧选段
// 从本边界之后开始（旧摘要一律作废，防清空内容以摘要形式回流）。
export async function adoptGraphClear(conversationId: string, branchId: string,
  boundarySeq: number, boundaryNodeId: string): Promise<string> {
  if (conversationId === '') {
    throw new Error('无持久会话，不能清空上下文');
  }
  const state: string = await queryConversationMigrateState(conversationId);
  if (state !== CONV_STATE_GRAPH) {
    throw new Error(TOMBSTONE_TOAST_TEXT);
  }
  if (isAdoptInflight(conversationId)) {
    throw new Error('上一次操作还在进行，请稍等');
  }
  markAdopt(conversationId, true);
  try {
    const onPath: boolean = await isNodeOnActivePath(conversationId, branchId, boundaryNodeId);
    if (!onPath) {
      throw new Error('会话路径已变化，请重新清空');
    }
    const db: relationalStore.RdbStore = sharedRdbStore();
    const branch: BranchRow | null = await queryBranch(db, branchId);
    if (branch === null) {
      throw new Error('分支不存在，清空失败');
    }
    // D1 铸造纪律：号在写事务首条语句前取齐（同 adoptGraphSummary 口径）
    const clearId: string = nextMessageId('clr');
    const seq: number = nextRowSeq(conversationId);
    const createdAt: number = nextRowCreatedAt();
    // 写串行链入链（同 adoptGraphSummary：前置读段留链外）
    return await runWriteQueued('adoptGraphClear', async (): Promise<string> => {
      db.beginTransaction();
      try {
        // head 读取在事务内（同 adoptGraphSummary F-3① 修复口径：事务外读 + 事务内无条件前移
        // 会覆盖并发写者推进的 head，把那条消息摘出路径）
        const headResult: relationalStore.ResultSet = await db.querySql(
          'SELECT headMessageId FROM branches WHERE id = ?', [branchId]);
        let head: string | null = null;
        try {
          if (!headResult.goToNextRow()) {
            throw new Error('分支不存在，清空失败');
          }
          const headIdx: number = headResult.getColumnIndex('headMessageId');
          head = headResult.isColumnNull(headIdx) ? null : headResult.getString(headIdx);
        } finally {
          headResult.close();
        }
        await db.insert('messages', {
          'id': clearId,
          'conversationId': conversationId,
          'role': 'clear',
          'content': '',
          'reasoning': '',
          'status': 'done',
          'createdAt': createdAt,
          'variants': '',
          'variant_active': 0,
          'seq': seq,
          'parentMessageId': head,
          'runId': '',
          'ownerAssistantId': '',
          'stepIndex': null,
          'origin': ''
        });
        const headBucket: relationalStore.ValuesBucket = { 'headMessageId': clearId };
        const headPredicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('branches');
        headPredicates.equalTo('id', branchId);
        if (head === null) {
          headPredicates.isNull('headMessageId');
        } else {
          headPredicates.equalTo('headMessageId', head);
        }
        const affected: number = await db.update(headBucket, headPredicates);
        if (affected !== 1) {
          throw new Error('会话路径已变化，这次清空没有保存，请重试');
        }
        await db.insert('summary_bindings', {
          'id': nextMessageId('sbd'),
          'conversationId': conversationId,
          'summaryMessageId': clearId,
          'coversFromSeq': null,
          'coversToSeq': boundarySeq,
          'dependsOnBindingId': '',
          'createdAt': createdAt
        });
        db.commit();
        return clearId;
      } catch (e) {
        db.rollBack();
        throw e as Error;
      }
    });
  } finally {
    markAdopt(conversationId, false);
  }
}

// 撤销清空（面板「撤销清空」键）：**软删**——只删该边界行的 binding，文本行留档（同
// deleteGraphSummary 的 S2 口径）。撤销后回到清空前的边界状态（更早的摘要或清空若还在
// 路径上且绑定未失效，按「最后一条边界胜出」自然重新生效）——「撤销 = 回到清空前」，
// 不是「回到全文」。
// ★ 撤销门槛（决明拍板）：清空后已发新内容（head 已前移，含发消息 / 再清空 / 采用压缩）
// 一律拒撤——那些新回复是模型在看不到清空前内容的状态下生成的，撤销会把两段互相不知情
// 的对话焊接成连续历史。判据 = isClearAtHead（本件单源）；此处是域级最后一道，面板隐藏键
// 与控制器守卫之外的防误调兜底。
// 幂等：传入 id 不在当前路径（他分支/已撤销）回空集不报错；返回 [clearId] 供宿主移除流内
// 分隔条（若该行已非生效边界，分隔条本就不渲染，移除无害）
export async function revokeGraphClear(conversationId: string,
  clearId: string): Promise<string[]> {
  const branchId: string = await queryConversationActiveBranch(conversationId);
  if (branchId === '') {
    throw new Error(TOMBSTONE_TOAST_TEXT);
  }
  const db: relationalStore.RdbStore = sharedRdbStore();
  const branch: BranchRow | null = await queryBranch(db, branchId);
  if (branch === null) {
    throw new Error('分支不存在，撤销失败');
  }
  const onPath: boolean = await isNodeOnActivePath(conversationId, branchId, clearId);
  if (!onPath) {
    return []; // 幂等：不在路径即无可撤
  }
  // 写串行链入链 + 撤销门槛链内复核（同 adoptGraphClear 先例：前置读段留链外，head 读取
  // 移入链内——链外判过的门槛会被并发写者〔发新消息/再清空/采用压缩都前移 head〕搞失真，
  // 把「已发新内容不可撤」的会话撤掉。单条 DELETE 原子不开显式事务——adoptGraphClear 开
  // 事务是三条写需原子，此处单写无此需）
  return await runWriteQueued('revokeGraphClear', async (): Promise<string[]> => {
    const headResult: relationalStore.ResultSet = await db.querySql(
      'SELECT headMessageId FROM branches WHERE id = ?', [branchId]);
    let head: string | null = null;
    try {
      if (!headResult.goToNextRow()) {
        throw new Error('分支不存在，撤销失败');
      }
      const headIdx: number = headResult.getColumnIndex('headMessageId');
      head = headResult.isColumnNull(headIdx) ? null : headResult.getString(headIdx);
    } finally {
      headResult.close();
    }
    if (head !== clearId) {
      throw new Error('清空后已发送新消息，无法撤销');
    }
    await db.executeSql('DELETE FROM summary_bindings WHERE conversationId = ? AND ' +
      'summaryMessageId = ?', [conversationId, clearId]);
    return [clearId];
  });
}

// 撤销可行性判据：清空行是否仍是活跃分支 head——head 停在清空行上 = 清空后没有任何追加
//（发消息、再清空、采用压缩都会前移 head），此刻撤销才是纯「后悔取消」；head 已前移即
// 不可撤。面板撤销键显隐与控制器守卫共用本口，语义单源（revokeGraphClear 的同判据随入链
// 改为链内重读 head 复核——链外已读行不经链会过期，不再复用）
export async function isClearAtHead(conversationId: string, clearId: string): Promise<boolean> {
  const branchId: string = await queryConversationActiveBranch(conversationId);
  if (branchId === '') {
    return false;
  }
  const branch: BranchRow | null = await queryBranch(sharedRdbStore(), branchId);
  return branch !== null && branch.headMessageId === clearId;
}

// 最新清空边界行（清空卡状态行用）：路径感知（同 ChatContextSource.readLatestSummaryRow
// 三段守卫——全局 seq 取到的行可能属已弃用分支；无清空 = null）；廉价前置探针
//（queryLatestClear）避免无清空的长会话每次都走完整路径上溯。边界定位（沿 parent 链上溯
// 取第一条有绑定者）复用 ChatContextSource.findPathSummaryRow（wantRole='clear'）——单一
// 实现，本件不复制第二份路径上溯
export async function readLatestClearRow(conversationId: string): Promise<MessageRow | null> {
  const probe: MessageRow | null = await queryLatestClear(conversationId);
  if (probe === null) {
    return null;
  }
  const branchId: string = await queryConversationActiveBranch(conversationId);
  if (branchId === '') {
    return null;
  }
  const db: relationalStore.RdbStore = sharedRdbStore();
  const branch: BranchRow | null = await queryBranch(db, branchId);
  if (branch === null) {
    return null; // 图态而无分支行 = 坏库：不按全局 seq 兜底（同 readLatestSummaryRow）
  }
  return findPathSummaryRow(db, branch.headMessageId, 'clear');
}
