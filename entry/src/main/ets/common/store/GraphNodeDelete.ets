// 节点级谱系剪枝删除命令域（长程三任务单元3；方案 = docs/方案-长程流水线三任务-20261029.md
// 单元3 件 2）。语义 = 「删一条消息 = 该节点及其全部后代闭包一起删」（跨一切分支——后代里
// 含其他分支上的内容，确认框文案如实告知）。
// · 职责一句话 = **节点级谱系剪枝删除命令**——与 deleteBranchLineage（分支级：删分支谱系
//   与其独占路径段）/ 删会话（会话级）同族不同粒度，三者语义分立：本命令**不删任何分支行**
//   （分支壳保留，head 回退后可继续在其上发消息），deleteBranchLineage 删分支行但不动共享
//   前缀，互不替代。
// · 为何不能并入既有件（反碎片下限三问）：①职责一句话见上；②GraphTransfer 剔头 1115 软
//   引导区禁再塞（并入必破 1200 硬线，宪法「禁先堆后拆」）/ MessageBranchDb 剔头 1157
//   同禁 / MessageGraphPrune 是零绑定纯函数判据域（断言直跑面）禁入 DB 命令；③实逻辑非
//   转接壳 = 完整事务命令（七面级联 + head 回退 + 附件可达性判定）。
// · 依赖方向（零环红线，坑50）：本件 → ChatDb（句柄）/ DbWriteQueue / ChatDbMigrate（能力
//   读）/ MessageBranchDb（单源读口）/ MessageGraphPrune（判据单源）单向；分批器
//   forEachLineageBatch 自 GraphTransfer export 复用（裁定 F：禁复制第二份）。
import { relationalStore } from '@kit.ArkData';
import { sharedRdbStore } from './ChatDb';
import { runWriteQueued } from './DbWriteQueue';
import { readGraphCapabilityLevel } from './ChatDbMigrate';
import { GraphNodeRef, loadConversationNodes, loadConversationBranches } from './MessageBranchDb';
import { AttachmentSurvivorRow, AttachmentSurvivorVerdict, GraphRefRow,
  computeSurvivingNodes, computeAttachmentSurvivors } from './MessageGraphPrune';
import { forEachLineageBatch } from './GraphTransfer';

// 删除结果（编排层消费）：deletedNodeIds = 被删节点闭包；rewoundBranchIds = head 命中被删集
// 而被回退的分支（全会话全部分支，不限活跃）；invalidatedLocalPaths = 失去归属的附件文件
// 相对路径（行删在事务内，文件由调用方 commit 后删——回滚不得已删文件红线）
export interface NodeLineageDeleteResult {
  deletedNodeIds: string[];
  rewoundBranchIds: string[];
  invalidatedLocalPaths: string[];
}

export async function deleteNodeLineage(db: relationalStore.RdbStore,
  conversationId: string, nodeId: string): Promise<NodeLineageDeleteResult> {
  // ── 读段（链外，照 deleteBranchLineage「范围判定留链外」既有形制）──
  // 目标节点轻行现读（含 role——GraphNodeRef 不带 role，role 校验是命令层第二道防线：
  // 判据域 canDeleteAt 只认 user/assistant，库侧再拦一次防伪锚直插命令层）
  let targetRole: string = '';
  let parentNodeId: string | null = null;
  const targetResult: relationalStore.ResultSet = await db.querySql(
    'SELECT id, conversationId, role, parentMessageId FROM messages WHERE id = ?', [nodeId]);
  try {
    if (targetResult.goToNextRow()) {
      const convIdx: number = targetResult.getColumnIndex('conversationId');
      if (targetResult.getString(convIdx) !== conversationId) {
        // 跨会话伪锚（内存 id 撞库内他话节点）——拒绝，不猜
        throw new Error('deleteNodeLineage 失败：节点 ' + nodeId + ' 不属于会话 ' + conversationId);
      }
      targetRole = targetResult.getString(targetResult.getColumnIndex('role'));
      const parentIdx: number = targetResult.getColumnIndex('parentMessageId');
      parentNodeId = targetResult.isColumnNull(parentIdx) ? null
        : targetResult.getString(parentIdx);
    }
  } finally {
    targetResult.close();
  }
  if (targetRole === '') {
    // 无行 = 重复删除 / 伪锚防线（P0-1 拒绝非静默放行）
    throw new Error('deleteNodeLineage 失败：节点 ' + nodeId + ' 不存在');
  }
  if (targetRole !== 'user' && targetRole !== 'assistant') {
    throw new Error('deleteNodeLineage 失败：只支持删除用户与助手消息，收到 ' + targetRole);
  }
  const allNodes: Map<string, GraphNodeRef> = await loadConversationNodes(db, conversationId);
  // cut 闭包 = {nodeId} 交 computeSurvivingNodes：surviving = 祖先链不经过目标的全部节点
  //（可达性判据单源——为什么用「从根可达」而非「从 head 可达」：同轮早段的祖先工具行从根
  // 可达但可能已不在任何 head 链上，按 head 判会把它们误删；少删优于多删，孤儿行只占库容
  // 不上屏〔readPathPage 从 head 沿 parent 上行收集，后代不进路径〕，删会话时一并清）
  const surviving: Set<string> = computeSurvivingNodes(allNodes, new Set<string>([nodeId]));
  const deletedNodeIds: string[] = [];
  for (const id of allNodes.keys()) {
    if (!surviving.has(id)) {
      deletedNodeIds.push(id);
    }
  }
  // head 回退面（裁定 D = D6 修正③）：**全会话全部分支**，非仅活跃分支——任一分支 head
  // 命中被删集即回退，否则该分支留下指向已删节点的悬挂 head（再发消息 parent 落已删 id，
  // 链断裂）。回退落点 = parentNodeId：被删 head 的祖先链上目标与 head 之间全为后代全删，
  // 第一个存活祖先恒 = parentNodeId；parentNodeId 为 null（删的是根分支首节点）⇒ 置空回
  // 空分支态（branches.headMessageId 列类型 string|null，空分支是既有合法形态——
  // prepareRun 空分支首 run 即 null 语义，MessageBranchDb「head 可空」注释在案）
  const branchRows = await loadConversationBranches(db, conversationId);
  const rewoundBranchIds: string[] = [];
  for (const row of branchRows) {
    if (row.headMessageId !== null && !surviving.has(row.headMessageId)) {
      rewoundBranchIds.push(row.id);
    }
  }
  // 能力级（空串占位行作废判据：能力不在场时 refs 不认、空串行一律保护不删——同
  // deleteBranchLineage 口径，判据在 computeAttachmentSurvivors 内）
  const capabilityLevel: number = await readGraphCapabilityLevel(db);
  // ★ 写串行链入链（范围判定与能力读留链外）
  return runWriteQueued('deleteNodeLineage', async (): Promise<NodeLineageDeleteResult> => {
    const tx: relationalStore.Transaction =
      await db.createTransaction({ transactionType: relationalStore.TransactionType.IMMEDIATE });
    try {
      // ── ① head 回退（多分支命中同 head 亦合法——forkBranch 一 head 多分支先例；置 null
      //    经 ValuesBucket 传 null，ValueType 含 null（SDK 26 d.ts :224）＝空分支态）──
      await forEachLineageBatch(rewoundBranchIds, async (chunk: string[], _marks: string):
        Promise<void> => {
        const headBucket: relationalStore.ValuesBucket = { 'headMessageId': parentNodeId };
        const headPredicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('branches');
        headPredicates.in('id', chunk);
        await tx.update(headBucket, headPredicates);
      });
      // ── ② 附件：统一可达性判定（判据单源 computeAttachmentSurvivors，禁另写选集 SQL——
      //    1193 已判数据丢失级）：删除后不再可达者行删 + 路径回传；判定输入 = 「删除后」
      //    存活节点集（messageId 与 refs 两源同集）──
      const attachRows: AttachmentSurvivorRow[] = [];
      const attachResult: relationalStore.ResultSet = await tx.querySql(
        'SELECT id, messageId FROM message_attachments WHERE conversationId = ?',
        [conversationId]);
      try {
        while (attachResult.goToNextRow()) {
          attachRows.push({
            attachmentId: attachResult.getString(attachResult.getColumnIndex('id')),
            messageId: attachResult.getString(attachResult.getColumnIndex('messageId'))
          });
        }
      } finally {
        attachResult.close();
      }
      const attachRefs: GraphRefRow[] = [];
      const refResult: relationalStore.ResultSet = await tx.querySql(
        'SELECT attachmentId, nodeId FROM attachment_refs WHERE conversationId = ?',
        [conversationId]);
      try {
        while (refResult.goToNextRow()) {
          attachRefs.push({
            attachmentId: refResult.getString(refResult.getColumnIndex('attachmentId')),
            nodeId: refResult.getString(refResult.getColumnIndex('nodeId'))
          });
        }
      } finally {
        refResult.close();
      }
      const verdicts: AttachmentSurvivorVerdict[] = computeAttachmentSurvivors(attachRows,
        attachRefs, capabilityLevel, surviving, surviving);
      const droppedAttachmentIds: string[] = [];
      for (const verdict of verdicts) {
        if (!verdict.survive) {
          droppedAttachmentIds.push(verdict.attachmentId);
        }
      }
      // ── ③ 被删节点 refs 必删（引用指向已删节点即悬挂，与资源是否存活无关）──
      await forEachLineageBatch(deletedNodeIds, async (chunk: string[], marks: string):
        Promise<void> => {
        await tx.execute('DELETE FROM attachment_refs WHERE nodeId IN (' + marks + ')', chunk);
      });
      // ── ④ 账本事件：被删消息的消耗随内容同删（会话级事件的 messageId 为空串不在判据内）──
      await forEachLineageBatch(deletedNodeIds, async (chunk: string[], marks: string):
        Promise<void> => {
        const usageArgs: Array<string | number> = [conversationId];
        for (const id of chunk) {
          usageArgs.push(id);
        }
        await tx.execute('DELETE FROM token_usage_events WHERE conversationId = ? ' +
          'AND messageId IN (' + marks + ')', usageArgs);
      });
      // ── ⑤ 摘要绑定：被删节点里的摘要节点绑定随事务生死（判据跟着节点走）──
      await forEachLineageBatch(deletedNodeIds, async (chunk: string[], marks: string):
        Promise<void> => {
        await tx.execute('DELETE FROM summary_bindings WHERE summaryMessageId IN (' + marks +
          ')', chunk);
      });
      // ── ⑥ 运行行与工具事实——**仅锚判据**（裁定 C）：run 按输入锚（该轮 user 节点）删；
      //    锚存活而输出被剪的 run 保留（少删优于多删——存活工具行的 runId 仍可解析；
      //    残留 run 不产幻影版本的安全垫 = 回答分组只收非空正文末正文行，空正文工具行
      //    进不了候选，方案档 §3.5 已订正机理并随档传达）──
      await forEachLineageBatch(deletedNodeIds, async (chunk: string[], marks: string):
        Promise<void> => {
        await tx.execute('DELETE FROM tool_facts WHERE runId IN (SELECT id FROM ' +
          'generation_runs WHERE inputAnchorMessageId IN (' + marks + '))', chunk);
        await tx.execute('DELETE FROM generation_runs WHERE inputAnchorMessageId IN (' +
          marks + ')', chunk);
      });
      // ── ⑦ 消息行（节点闭包）──
      await forEachLineageBatch(deletedNodeIds, async (chunk: string[], _marks: string):
        Promise<void> => {
        const msgPredicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('messages');
        msgPredicates.in('id', chunk);
        await tx.delete(msgPredicates);
      });
      // ── ⑧ 附件资源行（先取路径后删行——路径回传交调用方 commit 后删文件）+ 清其全部
      //    refs（行没了不留孤儿引用）──
      const invalidatedPaths: string[] = [];
      await forEachLineageBatch(droppedAttachmentIds, async (chunk: string[], marks: string):
        Promise<void> => {
        const pathResult: relationalStore.ResultSet = await tx.querySql(
          'SELECT localPath FROM message_attachments WHERE id IN (' + marks + ')', chunk);
        try {
          while (pathResult.goToNextRow()) {
            invalidatedPaths.push(pathResult.getString(pathResult.getColumnIndex('localPath')));
          }
        } finally {
          pathResult.close();
        }
        await tx.execute('DELETE FROM attachment_refs WHERE attachmentId IN (' + marks + ')',
          chunk);
        const dropPredicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('message_attachments');
        dropPredicates.in('id', chunk);
        await tx.delete(dropPredicates);
      });
      // ── ⑨ 分支行不删（语义分立：分支壳保留，head 已回退；删分支行是 deleteBranchLineage
      //    的语义，混入会把「删一条消息」升格成「删掉整条分支及其谱系」）──
      await tx.commit();
      return {
        deletedNodeIds: deletedNodeIds,
        rewoundBranchIds: rewoundBranchIds,
        invalidatedLocalPaths: invalidatedPaths
      };
    } catch (e) {
      await tx.rollback();
      throw e as Error;
    }
  });
}

// 生产入口（无句柄封装——components 层直调单点，照 deleteBranchLineageProd 姿势；
// 句柄版 deleteNodeLineage 供隔离库验证面直跑，两形态同一实现）
export async function deleteNodeLineageProd(conversationId: string,
  nodeId: string): Promise<NodeLineageDeleteResult> {
  return deleteNodeLineage(sharedRdbStore(), conversationId, nodeId);
}
