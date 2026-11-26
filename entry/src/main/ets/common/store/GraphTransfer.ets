// 图级转移与删除策略域（自 MessageBranchDb.ets 域级最小拆分——图导入导出 + 可达性删除
// 策略整块外迁，方法体逐字搬迁）：图快照导出/导入（J8 隔离库证据级）+ 分支谱系删除
//（J7 命令；deleteBranchLineage 按登记改判重写，整代替换老 deleteBranchSubtree）。
// · 职责一句话 = 图数据的出库/入库/删分支策略；分支图身份与原子命令仍在 MessageBranchDb。
// · 生产备份图域分域落位本件（collectGraphDomain / importGraphDomain——ExportImport
//   格式 3 的 graph.json 采集与导入后处理）。
// · 依赖方向（零环红线，坑50）：本件 → MessageBranchDb（类型/常量/纯函数/查询口）→
//   ChatDb 单向；库句柄由调用方传入。生产调用面：collectGraphDomain /
//   importGraphDomain 由 ExportImport 格式 3 备份链调用，deleteBranchLineageProd 由
//   ChatBranchCtrl 分支面板删除入口调用（sharedRdbStore 只为该 Prod 入口引入——生产入口
//   自取句柄，同 ConversationForkCopy 姿势；纯函数段仍可在 node 侧剥 import 直跑，坑50
//   纪律不破）；其余命令仍只在隔离库验证（W14~W20）。
// · importGraphDomain 补两条拒写闸（staging 库内消息行在场核验 + 写事务内逐行 affected
//   复核）与失败可见出参；导入替换面作废「失去全部 refs 的空串占位附件行」并把文件清单
//   交调用方 commit 后删；deleteBranchLineage 事务内同拍清 summary_bindings 与空串占位
//   附件行（J7 空串保护）；末尾图侧清理判定面 buildAttachmentGraphCleanup（依赖倒置
//  ——AttachmentDb 禁 import 图域件的注入源，理由见彼件头注释）
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { nextMessageId, sharedRdbStore } from './ChatDb';
import { runWriteQueued } from './DbWriteQueue';
import { readGraphCapabilityLevel, writeGraphCapabilityLevel } from './ChatDbMigrate';
import { BranchRow, GraphRunRow, ToolFactRow, GraphPathRow, GraphNodeRef,
  CONV_STATE_GRAPH, ORIGIN_IMPORT, validateGraphInsertion, GRAPH_LEVEL_ENABLED,
  queryBranch, loadConversationNodes, loadConversationBranches,
  graphPathRowFromResult } from './MessageBranchDb';
// 删除/清理存活判定三族纯函数自 MessageBranchDb 迁出拆分件（判据与编排分属两件防两份
// 漂移——见彼件头注释；GRAPH_LEVEL_ENABLED 是值域词表常量仍留母件）
import { BranchLineageRow, BranchHeadRow,
  AttachmentSurvivorRow, AttachmentSurvivorVerdict, GraphRefRow,
  computeSurvivingNodes, lineageBranchIds, computeLineageCutIds, computeAttachmentSurvivors }
  from './MessageGraphPrune';
// 图侧清理注入面的类型（S8；只取类型不取值——AttachmentDb 不回头 import 本件，零环）
import { AttachmentGraphCleanup, AttachmentBlankOwnerRow,
  AttachmentGraphRefRow } from './AttachmentDb';

// ── 图导入导出（笔2 落笔时为 J8 隔离库证据级形态；生产接线见头注释「生产调用面」条）──

export interface ConversationGraphSnapshot {
  conversationId: string;
  branchRows: BranchRow[];
  nodeRows: GraphPathRow[];
  runRows: GraphRunRow[];
  toolFactRows: ToolFactRow[];
  attachmentRefRows: AttachmentRefRow[];
  exportedAt: number;
  // v61 引用全文快照旁路：节点 id → quote_text（NULL 不入 Map）。GraphPathRow 冻结签名
  //（K12）不加列，本件内自加读取；可选 = 旧快照/夹具不带时导入按「无引用」处理
  quoteTextByNode?: Map<string, string>;
  // v64 服务端工具快照旁路（2026-11-14 DS 全家桶接入批 S2）：节点 id → server_tools 原样
  // JSON 串（NULL 不入 Map）。同 quoteTextByNode 形制——GraphPathRow 冻结签名不加列，
  // 本件内自加读取；可选 = 旧快照/夹具不带时导入按「无服务端步骤」处理
  serverToolsByNode?: Map<string, string>;
}

export interface AttachmentRefRow {
  id: string;
  conversationId: string;
  attachmentId: string;
  nodeId: string;
  createdAt: number;
}

// 导出一致快照（W16——图会话数据与附件元数据同一读时点）：DEFERRED 读事务包裹全部读
// （事务对象查询在事务内执行，commit 释放——同读时点契约由事务隔离承载）。
export async function exportConversationGraph(db: relationalStore.RdbStore,
  conversationId: string): Promise<ConversationGraphSnapshot> {
  const tx: relationalStore.Transaction =
    await db.createTransaction({ transactionType: relationalStore.TransactionType.DEFERRED });
  try {
    const branchRows: BranchRow[] = [];
    const branchResult: relationalStore.ResultSet = await tx.querySql(
      'SELECT id, conversationId, parentBranchId, headMessageId, name, createdAt ' +
      'FROM branches WHERE conversationId = ? ORDER BY createdAt ASC', [conversationId]);
    try {
      while (branchResult.goToNextRow()) {
        const parentIdx: number = branchResult.getColumnIndex('parentBranchId');
        const headIdx: number = branchResult.getColumnIndex('headMessageId');
        branchRows.push({
          id: branchResult.getString(branchResult.getColumnIndex('id')),
          conversationId: branchResult.getString(branchResult.getColumnIndex('conversationId')),
          parentBranchId: branchResult.isColumnNull(parentIdx) ? null
            : branchResult.getString(parentIdx),
          headMessageId: branchResult.isColumnNull(headIdx) ? null
            : branchResult.getString(headIdx),
          name: branchResult.getString(branchResult.getColumnIndex('name')),
          createdAt: branchResult.getLong(branchResult.getColumnIndex('createdAt'))
        });
      }
    } finally {
      branchResult.close();
    }
    const nodeRows: GraphPathRow[] = [];
    // v61 引用全文快照旁路 Map（GraphPathRow 冻结——SELECT 带 quote_text 列、
    // graphPathRowFromResult 只映射冻结字段，本处自加读取；NULL 不入 Map = 无引用）。
    // v64：server_tools 同查询顺路带回（同 SELECT 零额外往返；NULL 不入 Map = 无服务端步骤）
    const quoteBy: Map<string, string> = new Map<string, string>();
    const serverToolsBy: Map<string, string> = new Map<string, string>();
    const nodeResult: relationalStore.ResultSet = await tx.querySql(
      'SELECT id, conversationId, role, content, reasoning, status, createdAt, ' +
      'parentMessageId, runId, ownerAssistantId, stepIndex, origin, quote_text, server_tools ' +
      'FROM messages WHERE conversationId = ? ORDER BY createdAt ASC, rowid ASC', [conversationId]);
    try {
      while (nodeResult.goToNextRow()) {
        const row: GraphPathRow = graphPathRowFromResult(nodeResult);
        nodeRows.push(row);
        const quoteIdx: number = nodeResult.getColumnIndex('quote_text');
        if (!nodeResult.isColumnNull(quoteIdx)) {
          quoteBy.set(row.id, nodeResult.getString(quoteIdx));
        }
        const stIdx: number = nodeResult.getColumnIndex('server_tools');
        if (!nodeResult.isColumnNull(stIdx)) {
          serverToolsBy.set(row.id, nodeResult.getString(stIdx));
        }
      }
    } finally {
      nodeResult.close();
    }
    const runRows: GraphRunRow[] = [];
    const runResult: relationalStore.ResultSet = await tx.querySql(
      'SELECT id, conversationId, branchId, attemptEpoch, inputAnchorMessageId, revision, ' +
      'status, checkpoint, diagnosticMessageId, createdAt, updatedAt FROM generation_runs ' +
      'WHERE conversationId = ? ORDER BY createdAt ASC', [conversationId]);
    try {
      while (runResult.goToNextRow()) {
        runRows.push({
          id: runResult.getString(runResult.getColumnIndex('id')),
          conversationId: runResult.getString(runResult.getColumnIndex('conversationId')),
          branchId: runResult.getString(runResult.getColumnIndex('branchId')),
          attemptEpoch: runResult.getLong(runResult.getColumnIndex('attemptEpoch')),
          inputAnchorMessageId: runResult.getString(runResult.getColumnIndex('inputAnchorMessageId')),
          revision: runResult.getLong(runResult.getColumnIndex('revision')),
          status: runResult.getString(runResult.getColumnIndex('status')),
          checkpoint: runResult.getString(runResult.getColumnIndex('checkpoint')),
          diagnosticMessageId: runResult.getString(runResult.getColumnIndex('diagnosticMessageId')),
          createdAt: runResult.getLong(runResult.getColumnIndex('createdAt')),
          updatedAt: runResult.getLong(runResult.getColumnIndex('updatedAt'))
        });
      }
    } finally {
      runResult.close();
    }
    const toolFactRows: ToolFactRow[] = [];
    const factResult: relationalStore.ResultSet = await tx.querySql(
      'SELECT tf.id, tf.runId, tf.attemptId, tf.name, tf.state, tf.payload, tf.result, ' +
      'tf.createdAt, tf.finishedAt FROM tool_facts tf JOIN generation_runs gr ON tf.runId = gr.id ' +
      'WHERE gr.conversationId = ? ORDER BY tf.createdAt ASC', [conversationId]);
    try {
      while (factResult.goToNextRow()) {
        toolFactRows.push({
          id: factResult.getString(factResult.getColumnIndex('id')),
          runId: factResult.getString(factResult.getColumnIndex('runId')),
          attemptId: factResult.getString(factResult.getColumnIndex('attemptId')),
          name: factResult.getString(factResult.getColumnIndex('name')),
          state: factResult.getString(factResult.getColumnIndex('state')),
          payload: factResult.getString(factResult.getColumnIndex('payload')),
          result: factResult.getString(factResult.getColumnIndex('result')),
          createdAt: factResult.getLong(factResult.getColumnIndex('createdAt')),
          finishedAt: factResult.getLong(factResult.getColumnIndex('finishedAt'))
        });
      }
    } finally {
      factResult.close();
    }
    const attachmentRefRows: AttachmentRefRow[] = [];
    const refResult: relationalStore.ResultSet = await tx.querySql(
      'SELECT id, conversationId, attachmentId, nodeId, createdAt FROM attachment_refs ' +
      'WHERE conversationId = ? ORDER BY createdAt ASC', [conversationId]);
    try {
      while (refResult.goToNextRow()) {
        attachmentRefRows.push({
          id: refResult.getString(refResult.getColumnIndex('id')),
          conversationId: refResult.getString(refResult.getColumnIndex('conversationId')),
          attachmentId: refResult.getString(refResult.getColumnIndex('attachmentId')),
          nodeId: refResult.getString(refResult.getColumnIndex('nodeId')),
          createdAt: refResult.getLong(refResult.getColumnIndex('createdAt'))
        });
      }
    } finally {
      refResult.close();
    }
    await tx.commit();
    return {
      conversationId: conversationId,
      branchRows: branchRows,
      nodeRows: nodeRows,
      runRows: runRows,
      toolFactRows: toolFactRows,
      attachmentRefRows: attachmentRefRows,
      exportedAt: Date.now(),
      quoteTextByNode: quoteBy,
      serverToolsByNode: serverToolsBy
    };
  } catch (e) {
    await tx.rollback();
    throw e as Error;
  }
}

// 导入图快照（W17/W20——staging 验证后发布；skip/overwrite 图级冲突规则）：先全量校验
//（图插入校验逐节点 + 归属一致性 + run 归属 + refs 指向），校验失败抛错**零发布**（不暴露
// 半导入会话）；skip = 目标会话已 graph 态整体跳过返 false；overwrite = 事务内删目标会话
// 全部图侧行（branches/nodes 图列清空/runs/facts/refs）整批重插——**禁逐行混拼同 id**
//（会话图作为整体冲突处理，J8 冻结规则）。导入节点 origin 一律 ORIGIN_IMPORT。
export interface ImportGraphResult {
  applied: boolean;
  reason: string; // 'applied' | 'skipped-graph-exists' | 'replaced'
}

export async function importConversationGraph(db: relationalStore.RdbStore,
  snapshot: ConversationGraphSnapshot, strategy: string): Promise<ImportGraphResult> {
  if (strategy !== 'skip' && strategy !== 'overwrite') {
    throw new Error('导入策略只允许 skip/overwrite，收到 ' + strategy);
  }
  // ── staging 校验（零写入）──
  // 全量快照节点集（★ LB-5②：父存在性校验用全量集——顺序无关，任何排列的合法快照都过
  // 校验；原「循环内增量集」隐含父先于子的顺序契约，顺序被打破即误判悬边整批拒收）
  const nodeMap: Map<string, GraphNodeRef> = new Map<string, GraphNodeRef>();
  for (const node of snapshot.nodeRows) {
    nodeMap.set(node.id, {
      id: node.id, conversationId: node.conversationId,
      parentMessageId: node.parentMessageId
    });
  }
  // 快照节点 id 集（分支 head 与附件 refs 校验的取值面——「引用必须在快照内」语义，逐节点
  // 累积即可。★ run 归属不在其列：run.branchId 是 'br-' 前缀分支 id，判据 = branchRows
  // some——旧「inserted.has(branchId) ∥」死支已删）
  const inserted: Map<string, GraphNodeRef> = new Map<string, GraphNodeRef>();
  for (const node of snapshot.nodeRows) {
    const err: string | null = validateGraphInsertion({
      id: node.id, conversationId: node.conversationId,
      parentMessageId: node.parentMessageId
    }, nodeMap);
    if (err !== null) {
      throw new Error('图快照校验失败（节点 ' + node.id + '）:' + err);
    }
    if (node.conversationId !== snapshot.conversationId) {
      throw new Error('图快照校验失败：节点 ' + node.id + ' 归属会话 ' +
        node.conversationId + ' 与快照会话 ' + snapshot.conversationId + ' 不一致');
    }
    inserted.set(node.id, nodeMap.get(node.id) as GraphNodeRef);
  }
  for (const run of snapshot.runRows) {
    if (run.conversationId !== snapshot.conversationId) {
      throw new Error('图快照校验失败：run ' + run.id + ' 归属会话不一致');
    }
    if (!snapshot.branchRows.some((b: BranchRow): boolean => b.id === run.branchId)) {
      throw new Error('图快照校验失败：run ' + run.id + ' 引用的分支 ' + run.branchId +
        ' 不在快照中（悬引用）');
    }
  }
  const nodeIds: Set<string> = new Set<string>(inserted.keys());
  for (const ref of snapshot.attachmentRefRows) {
    if (!nodeIds.has(ref.nodeId)) {
      throw new Error('图快照校验失败：附件引用 ' + ref.attachmentId + ' 挂载节点 ' +
        ref.nodeId + ' 不在快照中（悬引用）');
    }
  }
  for (const branch of snapshot.branchRows) {
    if (branch.conversationId !== snapshot.conversationId) {
      throw new Error('图快照校验失败：分支 ' + branch.id + ' 归属会话不一致');
    }
    if (branch.headMessageId !== null && !nodeIds.has(branch.headMessageId)) {
      throw new Error('图快照校验失败：分支 ' + branch.id + ' head 指向节点不在快照中');
    }
  }
  // ── 冲突策略（图级）──
  const stateResult: relationalStore.ResultSet = await db.querySql(
    'SELECT migrateState FROM conversations WHERE id = ?', [snapshot.conversationId]);
  let targetState: string = '';
  try {
    if (stateResult.goToNextRow()) {
      targetState = stateResult.getString(stateResult.getColumnIndex('migrateState'));
    }
  } finally {
    stateResult.close();
  }
  if (targetState === CONV_STATE_GRAPH && strategy === 'skip') {
    return { applied: false, reason: 'skipped-graph-exists' };
  }
  // ★ 写串行链入链（冲突策略读段留链外；快照校验也在链外）
  return runWriteQueued('importConversationGraph', async (): Promise<ImportGraphResult> => {
    const tx: relationalStore.Transaction =
      await db.createTransaction({ transactionType: relationalStore.TransactionType.IMMEDIATE });
    try {
      if (targetState === CONV_STATE_GRAPH && strategy === 'overwrite') {
        // 整批替换（禁逐行混拼）：删旧图侧行 → 重插。runs/facts/refs/branches 全删；
        // 节点行本体删除（快照含全量节点行——restore 语义，非增量）
        await tx.execute('DELETE FROM attachment_refs WHERE conversationId = ?',
          [snapshot.conversationId]);
        await tx.execute('DELETE FROM tool_facts WHERE runId IN ' +
          '(SELECT id FROM generation_runs WHERE conversationId = ?)', [snapshot.conversationId]);
        await tx.execute('DELETE FROM generation_runs WHERE conversationId = ?',
          [snapshot.conversationId]);
        await tx.execute('DELETE FROM branches WHERE conversationId = ?',
          [snapshot.conversationId]);
        await tx.execute('DELETE FROM messages WHERE conversationId = ?',
          [snapshot.conversationId]);
      }
      for (const branch of snapshot.branchRows) {
        const bucket: relationalStore.ValuesBucket = {
          'id': branch.id, 'conversationId': branch.conversationId,
          'parentBranchId': branch.parentBranchId, 'headMessageId': branch.headMessageId,
          'name': branch.name, 'createdAt': branch.createdAt
        };
        await tx.insert('branches', bucket);
      }
      for (const node of snapshot.nodeRows) {
        const bucket: relationalStore.ValuesBucket = {
          'id': node.id, 'conversationId': node.conversationId, 'role': node.role,
          'content': node.content, 'reasoning': node.reasoning, 'status': node.status,
          'createdAt': node.createdAt, 'variants': '', 'variant_active': 0,
          'parentMessageId': node.parentMessageId, 'runId': node.runId,
          'ownerAssistantId': node.ownerAssistantId, 'stepIndex': node.stepIndex,
          'origin': ORIGIN_IMPORT
        };
        // v61 引用快照（图快照保真）：旁路 Map 命中才写键（不写键 = 列落 DEFAULT NULL；
        // 旧快照/夹具不带 Map 时按无引用导入）。v64：server_tools 同款条件写键（原样串保真）
        if (snapshot.quoteTextByNode !== undefined) {
          const quote: string | undefined = snapshot.quoteTextByNode.get(node.id);
          if (quote !== undefined && quote !== '') {
            bucket['quote_text'] = quote;
          }
        }
        if (snapshot.serverToolsByNode !== undefined) {
          const st: string | undefined = snapshot.serverToolsByNode.get(node.id);
          if (st !== undefined && st !== '') {
            bucket['server_tools'] = st;
          }
        }
        await tx.insert('messages', bucket);
      }
      for (const run of snapshot.runRows) {
        const bucket: relationalStore.ValuesBucket = {
          'id': run.id, 'conversationId': run.conversationId, 'branchId': run.branchId,
          'attemptEpoch': run.attemptEpoch, 'inputAnchorMessageId': run.inputAnchorMessageId,
          'revision': run.revision, 'status': run.status, 'checkpoint': run.checkpoint,
          'diagnosticMessageId': run.diagnosticMessageId, 'createdAt': run.createdAt,
          'updatedAt': run.updatedAt
        };
        await tx.insert('generation_runs', bucket);
      }
      for (const fact of snapshot.toolFactRows) {
        const bucket: relationalStore.ValuesBucket = {
          'id': fact.id, 'runId': fact.runId, 'attemptId': fact.attemptId,
          'name': fact.name, 'state': fact.state, 'payload': fact.payload,
          'result': fact.result, 'createdAt': fact.createdAt,
          'finishedAt': fact.finishedAt
        };
        await tx.insert('tool_facts', bucket);
      }
      for (const ref of snapshot.attachmentRefRows) {
        const bucket: relationalStore.ValuesBucket = {
          'id': ref.id, 'conversationId': ref.conversationId, 'attachmentId': ref.attachmentId,
          'nodeId': ref.nodeId, 'createdAt': ref.createdAt
        };
        await tx.insert('attachment_refs', bucket);
      }
      // 快照不含 legacy 列（variants 等）——导入面是图域证据级，非全量备份恢复（生产备份
      // 图域分域走本件 collectGraphDomain / importGraphDomain）
      await tx.commit();
      return { applied: true, reason: targetState === CONV_STATE_GRAPH ? 'replaced' : 'applied' };
    } catch (e) {
      await tx.rollback();
      throw e as Error;
    }
  });
}

// deleteBranchLineage（J7 删除命令——按登记改判重写，整代替换老 deleteBranchSubtree；老
// 实现两处越界〔连删共享 fork 点 / 整删把父分支 head 当锚〕属数据丢失级）：语义 =「删一条
// 分支 = 连同它之后衍生的全部分支一起删」（决明拍板），范围由 lineageBranchIds（谱系子树
// 收集）× computeLineageCutIds（本分支独占路径段）两纯函数判定——共享前缀与父分支内容恒
// 不入选。
// 事务内一次完成级联：账本事件 / 附件（判据单源 computeAttachmentSurvivors 统一判定——
// 删除后不可达者行删并回传路径；共享引用在存活节点仍可达时保留，老实现按 messageId 无脑
// 删行致 refs 悬空属数据丢失级登记项）/ 摘要绑定 / 运行行与工具事实（分支归属 ∪ 输入锚双
// 判据——老实现只按输入锚删，重试链的 run 锚在共享前缀时会漏成悬挂）/ 消息行 / 分支行
//（谱系全集）；活跃分支若在被删集，同事务切到所删分支的父分支（不留指向已删分支的指针）。
// 返回失去归属的附件行路径（文件由调用方 commit 后删）+ 被删分支/节点集与切换落点。
export interface BranchLineageDeleteResult {
  deletedBranchIds: string[];
  deletedNodeIds: string[];
  invalidatedLocalPaths: string[];
  activeBranchSwitched: boolean;
  fallbackBranchId: string;
}

// 删除批次（同 ChatDb.CLEAR_CONV_BATCH 口径：单批展开 ≤2 处 × 200 参数，稳低于
// SQLITE_MAX_VARIABLE_NUMBER 下限 999）。★ export 化后节点级剪枝命令 GraphNodeDelete
// 复用同一分批口径——判据单源（裁定 F：走 export 复用，禁复制第二份）
export const LINEAGE_DEL_BATCH: number = 200;

// 分批遍历（切片 + 占位串生成一次成形；删除命令各语句共用——语义不受分批影响）
export async function forEachLineageBatch(ids: string[],
  work: (chunk: string[], marks: string) => Promise<void>): Promise<void> {
  for (let i = 0; i < ids.length; i += LINEAGE_DEL_BATCH) {
    const chunk: string[] = ids.slice(i, i + LINEAGE_DEL_BATCH);
    const marks: string = chunk.map((_id: string): string => '?').join(',');
    await work(chunk, marks);
  }
}

export async function deleteBranchLineage(db: relationalStore.RdbStore,
  branchId: string): Promise<BranchLineageDeleteResult> {
  const branch: BranchRow | null = await queryBranch(db, branchId);
  if (branch === null) {
    throw new Error('deleteBranchLineage 失败：分支 ' + branchId + ' 不存在');
  }
  const parentBranchId: string | null = branch.parentBranchId;
  if (parentBranchId === null) {
    // 根分支不可删（删它 = 清空整会话内容，那是删会话的语义）：面板不渲染删除键 + 本层
    // 显式拒绝双防线（Ctrl 层只拦空 id 不判根，防删根不依赖它）；P0-1 拒绝非静默放行
    throw new Error('deleteBranchLineage 失败：根分支不可删，请删除整个会话');
  }
  const conversationId: string = branch.conversationId;
  // 删除范围判定（读段留链外——「事务段入链」既有形制）
  const rows: BranchRow[] = await loadConversationBranches(db, conversationId);
  const lineageRows: BranchLineageRow[] = [];
  const headRows: BranchHeadRow[] = [];
  for (const row of rows) {
    lineageRows.push({ id: row.id, parentBranchId: row.parentBranchId });
    headRows.push({ branchId: row.id, headMessageId: row.headMessageId });
  }
  const deleteSet: Set<string> = lineageBranchIds(lineageRows, branchId);
  const deletedBranchIds: string[] = [];
  for (const id of deleteSet) {
    deletedBranchIds.push(id);
  }
  const allNodes: Map<string, GraphNodeRef> = await loadConversationNodes(db, conversationId);
  const cutIds: Set<string> = computeLineageCutIds(headRows, deleteSet, allNodes);
  const surviving: Set<string> = computeSurvivingNodes(allNodes, cutIds);
  const deletedNodeIds: string[] = [];
  for (const id of allNodes.keys()) {
    if (!surviving.has(id)) {
      deletedNodeIds.push(id);
    }
  }
  // 能力级（空串占位行作废判据：J7 空串保护——能力不在场时 refs 不认、空串行一律保护不删，
  // 由启动收敛在能力恢复后处理；readGraphCapabilityLevel 对读失败自吞返 0 = fail-safe 方向）
  const capabilityLevel: number = await readGraphCapabilityLevel(db);
  // ★ 写串行链入链（范围判定与能力读留链外）
  return runWriteQueued('deleteBranchLineage', async (): Promise<BranchLineageDeleteResult> => {
    const tx: relationalStore.Transaction =
      await db.createTransaction({ transactionType: relationalStore.TransactionType.IMMEDIATE });
    try {
      const invalidatedPaths: string[] = [];
      // ── 活跃分支修正（事务内现读；删除与切换同一提交单元，不留指向已删分支的指针）──
      let activeBranchSwitched: boolean = false;
      const activeResult: relationalStore.ResultSet = await tx.querySql(
        'SELECT activeBranchId FROM conversations WHERE id = ?', [conversationId]);
      let activeBranch: string = '';
      try {
        if (activeResult.goToNextRow()) {
          const activeIdx: number = activeResult.getColumnIndex('activeBranchId');
          activeBranch = activeResult.isColumnNull(activeIdx) ? ''
            : activeResult.getString(activeIdx);
        }
      } finally {
        activeResult.close();
      }
      if (activeBranch !== '' && deleteSet.has(activeBranch)) {
        // 落点 = 所删分支的谱系父（恒不在删集——它是所删分支的祖先）
        const activeBucket: relationalStore.ValuesBucket = { 'activeBranchId': parentBranchId };
        const convPredicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('conversations');
        convPredicates.equalTo('id', conversationId);
        await tx.update(activeBucket, convPredicates);
        activeBranchSwitched = true;
      }
      // ── 附件：统一可达性判定（判据单源 computeAttachmentSurvivors，不另写选集 SQL）：
      //    删除后不再可达者行删 + 路径回传（文件由调用方 commit 后删）。与老实现三处差异：
      //    ①共享引用（编辑保留后一资源挂多节点）在存活节点仍可达时保留——老实现按
      //    messageId 无脑删行致存活节点 refs 悬空（数据丢失级）；②被删节点 refs 无论资源
      //    存活与否必删（指向已删节点即悬挂）；③能力不在场时空串行一律保护（J7 判据在
      //    computeAttachmentSurvivors 内）
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
      // 判定输入 = 「删除后」存活节点集（messageId 与 refs 两源同集——graph 会话空串行的
      // 归属只经 refs，legacy 行的归属经 messageId）
      const verdicts: AttachmentSurvivorVerdict[] = computeAttachmentSurvivors(attachRows,
        attachRefs, capabilityLevel, surviving, surviving);
      const droppedAttachmentIds: string[] = [];
      for (const verdict of verdicts) {
        if (!verdict.survive) {
          droppedAttachmentIds.push(verdict.attachmentId);
        }
      }
      // 被删节点 refs（必删：引用指向已删节点即悬挂；与资源是否存活无关）
      await forEachLineageBatch(deletedNodeIds, async (chunk: string[], marks: string):
        Promise<void> => {
        await tx.execute('DELETE FROM attachment_refs WHERE nodeId IN (' + marks + ')', chunk);
      });
      // ── 账本事件：被删消息的消耗随内容同删（与删会话九表级联同口径；会话级事件的
      //    messageId 为空串，不在判据内）──
      await forEachLineageBatch(deletedNodeIds, async (chunk: string[], marks: string):
        Promise<void> => {
        const usageArgs: Array<string | number> = [conversationId];
        for (const id of chunk) {
          usageArgs.push(id);
        }
        await tx.execute('DELETE FROM token_usage_events WHERE conversationId = ? ' +
          'AND messageId IN (' + marks + ')', usageArgs);
      });
      // ── 摘要绑定：被删节点里的摘要节点绑定随事务生死（共享前缀上的摘要节点若存活则其
      //    绑定保留——判据跟着节点走）──
      await forEachLineageBatch(deletedNodeIds, async (chunk: string[], marks: string):
        Promise<void> => {
        await tx.execute('DELETE FROM summary_bindings WHERE summaryMessageId IN (' + marks +
          ')', chunk);
      });
      // ── 运行行与工具事实：分支归属 ∪ 输入锚双判据（见函数头注释）──
      await forEachLineageBatch(deletedBranchIds, async (chunk: string[], marks: string):
        Promise<void> => {
        await tx.execute('DELETE FROM tool_facts WHERE runId IN (SELECT id FROM ' +
          'generation_runs WHERE branchId IN (' + marks + '))', chunk);
        await tx.execute('DELETE FROM generation_runs WHERE branchId IN (' + marks + ')', chunk);
      });
      await forEachLineageBatch(deletedNodeIds, async (chunk: string[], marks: string):
        Promise<void> => {
        await tx.execute('DELETE FROM tool_facts WHERE runId IN (SELECT id FROM ' +
          'generation_runs WHERE inputAnchorMessageId IN (' + marks + '))', chunk);
        await tx.execute('DELETE FROM generation_runs WHERE inputAnchorMessageId IN (' +
          marks + ')', chunk);
      });
      // ── 消息行──
      await forEachLineageBatch(deletedNodeIds, async (chunk: string[], _marks: string):
        Promise<void> => {
        const msgPredicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('messages');
        msgPredicates.in('id', chunk);
        await tx.delete(msgPredicates);
      });
      // ── 附件：不可达资源行删（先取路径后删行——路径回传交调用方 commit 后删文件）+
      //    清其全部 refs（行没了不留孤儿引用）──
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
      // ── 分支行（谱系全集）──
      await forEachLineageBatch(deletedBranchIds, async (chunk: string[], _marks: string):
        Promise<void> => {
        const branchPredicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('branches');
        branchPredicates.in('id', chunk);
        await tx.delete(branchPredicates);
      });
      await tx.commit();
      return {
        deletedBranchIds: deletedBranchIds,
        deletedNodeIds: deletedNodeIds,
        invalidatedLocalPaths: invalidatedPaths,
        activeBranchSwitched: activeBranchSwitched,
        fallbackBranchId: parentBranchId
      };
    } catch (e) {
      await tx.rollback();
      throw e as Error;
    }
  });
}

// 生产入口（无句柄封装——components 层直调单点；句柄版 deleteBranchLineage 仍是隔离库
// 证据面与 node 直跑入口，两形态同一实现）
export async function deleteBranchLineageProd(branchId: string):
  Promise<BranchLineageDeleteResult> {
  return deleteBranchLineage(sharedRdbStore(), branchId);
}

// ── 图域备份分域（2026-09-26 笔3 S4/K10；自 ExportImport 域级拆分迁入，见头注释）──

const GT_DOMAIN: number = 0x0001;
const GT_TAG: string = 'GraphTransfer';

// 图域分域行形状（可空字段 JSON null 保真——线性 SELECT * 归一会毁根语义）
export interface GraphBackupNode {
  id: string;
  seq: number | null;
  stepIndex: number | null;
  origin: string;
  runId: string;
  ownerAssistantId: string;
  parentMessageId: string | null;
  coversToSeq: number | null;
}

export interface GraphBackupBranch {
  id: string;
  parentBranchId: string | null;
  headMessageId: string | null;
  name: string;
  createdAt: number;
}

export interface GraphBackupBinding {
  id: string;
  summaryMessageId: string;
  coversFromSeq: number | null;
  coversToSeq: number | null;
  dependsOnBindingId: string;
  createdAt: number;
}

export interface GraphBackupConversation {
  conversationId: string;
  activeBranchId: string;
  branches: GraphBackupBranch[];
  nodes: GraphBackupNode[];
  runs: Record<string, Object>[];
  facts: Record<string, Object>[];
  bindings: GraphBackupBinding[];
  refs: Record<string, Object>[];
}

// 行单元格文本（JSON 行值域 Object；非字符串按空处理）
function gtRowText(v: Object | undefined): string {
  return typeof v === 'string' ? v as string : '';
}

// 绑定值归一（Record 取值 Object → ValueType；图侧小表仅 string/number 两型）
function bindArg(v: Object | undefined): relationalStore.ValueType {
  if (typeof v === 'string') {
    return v;
  }
  if (typeof v === 'number') {
    return v;
  }
  return '';
}

function nullableLong(rs: relationalStore.ResultSet, col: string): number | null {
  const idx: number = rs.getColumnIndex(col);
  return rs.isColumnNull(idx) ? null : rs.getLong(idx);
}

function nullableString(rs: relationalStore.ResultSet, col: string): string | null {
  const idx: number = rs.getColumnIndex(col);
  return rs.isColumnNull(idx) ? null : rs.getString(idx);
}

function nullableOf(v: Object | undefined): number | null {
  if (v === null || v === undefined) {
    return null;
  }
  return typeof v === 'number' ? v as number : null;
}

// 通用行读取（全非空列小表——runs/facts/refs；列型分派 getColumnSync）
async function readRows(rdb: relationalStore.RdbStore, sql: string,
  args: Array<string | number>): Promise<Record<string, Object>[]> {
  const rows: Record<string, Object>[] = [];
  const rs: relationalStore.ResultSet = await rdb.querySql(sql, args);
  try {
    while (rs.goToNextRow()) {
      const row: Record<string, Object> = {};
      for (let i = 0; i < rs.columnNames.length; i++) {
        const name: string = rs.columnNames[i];
        if (rs.isColumnNull(i)) {
          row[name] = 0;
        } else {
          const t: relationalStore.ColumnType = rs.getColumnTypeSync(i);
          if (t === relationalStore.ColumnType.INTEGER) {
            row[name] = rs.getLong(i);
          } else if (t === relationalStore.ColumnType.REAL) {
            row[name] = rs.getDouble(i);
          } else {
            row[name] = rs.getString(i);
          }
        }
      }
      rows.push(row);
    }
  } finally {
    rs.close();
  }
  return rows;
}

// 图域采集（导出侧）：graph 会话逐会话装配（ExportImport.exportAllData 格式 3 消费）
export async function collectGraphDomain(rdb: relationalStore.RdbStore): Promise<GraphBackupConversation[]> {
  const out: GraphBackupConversation[] = [];
  const convRs: relationalStore.ResultSet = await rdb.querySql(
    "SELECT id, activeBranchId FROM conversations WHERE migrateState = 'graph' " +
    'ORDER BY createdAt ASC');
  const convIds: string[] = [];
  const activeBy: Map<string, string> = new Map<string, string>();
  try {
    while (convRs.goToNextRow()) {
      const cid: string = convRs.getString(convRs.getColumnIndex('id'));
      convIds.push(cid);
      activeBy.set(cid, convRs.getString(convRs.getColumnIndex('activeBranchId')));
    }
  } finally {
    convRs.close();
  }
  for (const cid of convIds) {
    const nodes: GraphBackupNode[] = [];
    const nodeRs: relationalStore.ResultSet = await rdb.querySql(
      'SELECT id, seq, stepIndex, origin, runId, ownerAssistantId, parentMessageId, ' +
      'coversToSeq FROM messages WHERE conversationId = ? ORDER BY createdAt ASC, rowid ASC',
      [cid]);
    try {
      while (nodeRs.goToNextRow()) {
        nodes.push({
          id: nodeRs.getString(nodeRs.getColumnIndex('id')),
          seq: nullableLong(nodeRs, 'seq'),
          stepIndex: nullableLong(nodeRs, 'stepIndex'),
          origin: nodeRs.getString(nodeRs.getColumnIndex('origin')),
          runId: nodeRs.getString(nodeRs.getColumnIndex('runId')),
          ownerAssistantId: nodeRs.getString(nodeRs.getColumnIndex('ownerAssistantId')),
          parentMessageId: nullableString(nodeRs, 'parentMessageId'),
          coversToSeq: nullableLong(nodeRs, 'coversToSeq')
        });
      }
    } finally {
      nodeRs.close();
    }
    const branches: GraphBackupBranch[] = [];
    const branchRs: relationalStore.ResultSet = await rdb.querySql(
      'SELECT id, parentBranchId, headMessageId, name, createdAt FROM branches ' +
      'WHERE conversationId = ? ORDER BY createdAt ASC', [cid]);
    try {
      while (branchRs.goToNextRow()) {
        branches.push({
          id: branchRs.getString(branchRs.getColumnIndex('id')),
          parentBranchId: nullableString(branchRs, 'parentBranchId'),
          headMessageId: nullableString(branchRs, 'headMessageId'),
          name: branchRs.getString(branchRs.getColumnIndex('name')),
          createdAt: branchRs.getLong(branchRs.getColumnIndex('createdAt'))
        });
      }
    } finally {
      branchRs.close();
    }
    const runs: Record<string, Object>[] = await readRows(rdb,
      'SELECT id, conversationId, branchId, attemptEpoch, inputAnchorMessageId, revision, ' +
      'status, checkpoint, diagnosticMessageId, createdAt, updatedAt FROM generation_runs ' +
      'WHERE conversationId = ? ORDER BY createdAt ASC', [cid]);
    const facts: Record<string, Object>[] = await readRows(rdb,
      'SELECT tf.id, tf.runId, tf.attemptId, tf.name, tf.state, tf.payload, tf.result, ' +
      'tf.createdAt, tf.finishedAt FROM tool_facts tf JOIN generation_runs gr ON tf.runId = gr.id ' +
      'WHERE gr.conversationId = ? ORDER BY tf.createdAt ASC', [cid]);
    const bindingsRaw: Record<string, Object>[] = await readRows(rdb,
      'SELECT id, summaryMessageId, coversFromSeq, coversToSeq, dependsOnBindingId, ' +
      'createdAt FROM summary_bindings WHERE conversationId = ? ORDER BY createdAt ASC', [cid]);
    const bindings: GraphBackupBinding[] = [];
    for (const b of bindingsRaw) {
      bindings.push({
        id: gtRowText(b['id']),
        summaryMessageId: gtRowText(b['summaryMessageId']),
        coversFromSeq: nullableOf(b['coversFromSeq']),
        coversToSeq: nullableOf(b['coversToSeq']),
        dependsOnBindingId: gtRowText(b['dependsOnBindingId']),
        createdAt: typeof b['createdAt'] === 'number' ? b['createdAt'] as number : 0
      });
    }
    const refs: Record<string, Object>[] = await readRows(rdb,
      'SELECT id, conversationId, attachmentId, nodeId, createdAt FROM attachment_refs ' +
      'WHERE conversationId = ? ORDER BY createdAt ASC', [cid]);
    out.push({
      conversationId: cid,
      activeBranchId: activeBy.get(cid) ?? '',
      branches: branches,
      nodes: nodes,
      runs: runs,
      facts: facts,
      bindings: bindings,
      refs: refs
    });
  }
  return out;
}

// 图域导入后处理（ExportImport.importFromZip 格式 3 消费）：逐会话「校验 → 单事务重建图
// 侧」。skip 态下目标已 graph 的会话整体跳过（图级冲突规则，J8 同源：整批处理禁逐行混拼
//——本函数以会话为单元天然满足）；单会话失败跳过留痕不炸整批；capability 写 2 前置
//（K2：图态落库先于或同于能力标记）。★ S6 两条拒写闸 + 失败可见——①staging 段核验
//「快照节点在库消息行在场」；②写事务内逐行 affected 复核；③失败会话说得清
//（GraphImportOutcome.failed）
export interface GraphImportOutcome {
  applied: number;
  failed: number;
  // 本段作废的附件相对路径（S8② 导入替换面）——调用方在**全部导入完成后**删文件
  //（回滚不得已删文件红线：事务内只删行，commit 才交出文件清单）
  invalidatedLocalPaths: string[];
}

// 空串占位附件行旧态（S8② 采集形状：id 与 localPath——localPath 是返回值里的文件清单来源）
interface PriorBlankOwnerRow {
  id: string;
  localPath: string;
}

export async function importGraphDomain(rdb: relationalStore.RdbStore,
  graphConvs: GraphBackupConversation[], strategy: string): Promise<GraphImportOutcome> {
  await writeGraphCapabilityLevel(rdb, 2);
  let applied: number = 0;
  let failed: number = 0;
  const invalidatedLocalPaths: string[] = [];
  for (const conv of graphConvs) {
    try {
      const stateRs: relationalStore.ResultSet = await rdb.querySql(
        'SELECT migrateState FROM conversations WHERE id = ?', [conv.conversationId]);
      let targetState: string = '';
      try {
        if (stateRs.goToNextRow()) {
          targetState = stateRs.getString(stateRs.getColumnIndex('migrateState'));
        }
      } finally {
        stateRs.close();
      }
      // ★ 墓碑笔：原「migrating 锁定态拒收」闸随迁移机制整件退役——「备份恢复」是本函数
      // 的正当写面：本地行无论现态如何，图域导入成功即发布 graph（migrateState +
      // activeBranchId 同事务落定，见下方事务体）。★ 实测订正（260-F 契约真值表抓出）：
      // 曾试改判「目标态非 graph 一律拒收」，直接把「本地旧格式行 + overwrite 恢复图备份
      //→ 发布 graph」的正路挡死（applied 1 → 0），故不采用；墓碑判据（M4：非 graph 即
      // 墓碑）只管**读**路由，不管导入发布。
      if (targetState === CONV_STATE_GRAPH && strategy === 'skip') {
        // ★ S5 判据修正（治「空库＋skip 导入有标无图」）：skip 语义 =「本机已有该会话数据
        // 不动」，但目标行的 graph 态可能正是本次表循环刚 INSERT 的（空库恢复新格式备份：
        // conversations 行自带 migrateState='graph' 而图侧五行尚未导入）——此时 skip 会造出
        //「有标无图」（图态读路径空，整段对话消失）。故 skip 只认「本机确有图侧数据」
        //（branches 行在场）；空图侧 = 本次新增面，完整导入
        const branchRs2: relationalStore.ResultSet = await rdb.querySql(
          'SELECT id FROM branches WHERE conversationId = ? LIMIT 1', [conv.conversationId]);
        let hasGraphRows: boolean = false;
        try {
          hasGraphRows = branchRs2.goToNextRow();
        } finally {
          branchRs2.close();
        }
        if (hasGraphRows) {
          continue;
        }
      }
      // staging 校验（零写入）：图插入校验逐节点 + **库内消息行在场** + 分支 head 归属 +
      // refs 指向。★ S6①：「库内消息行在场」核验——图域导入只回写 messages 的图列，行本体
      // 由 ExportImport 表循环按同 id 恢复；若该会话消息行不在库（messages.json 缺失或损坏、
      // 单行插入失败、包与库会话不对应），原实现的 UPDATE 零行命中仍静默通过，会话被标
      // graph 而节点集是空的（半导入：图态会话读出空路径，整段对话消失）。核验源 =
      // loadConversationNodes（存活集/校验读口同源），快照任一节点不在库内即抛——由下方
      // catch 留痕跳过该会话，库保持原态零写入。
      const dbNodes: Map<string, GraphNodeRef> =
        await loadConversationNodes(rdb, conv.conversationId);
      for (const node of conv.nodes) {
        if (!dbNodes.has(node.id)) {
          throw new Error('图域校验失败：节点 ' + node.id +
            ' 在库中不存在（消息行未随表循环恢复，禁止半导入）');
        }
      }
      // 全量快照节点集（★ LB-5②：校验顺序无关——同上 importConversationGraph 处口径；
      // **不可复用 dbNodes**——那是库内节点集，语义不同）
      const snapshotNodes: Map<string, GraphNodeRef> = new Map<string, GraphNodeRef>();
      for (const node of conv.nodes) {
        snapshotNodes.set(node.id, {
          id: node.id, conversationId: conv.conversationId,
          parentMessageId: node.parentMessageId
        });
      }
      // 快照节点 id 集（分支 head / refs 校验的取值面——「引用必须在快照内」语义）
      const inserted: Map<string, GraphNodeRef> = new Map<string, GraphNodeRef>();
      for (const node of conv.nodes) {
        const err: string | null = validateGraphInsertion({
          id: node.id, conversationId: conv.conversationId,
          parentMessageId: node.parentMessageId
        }, snapshotNodes);
        if (err !== null) {
          throw new Error('图域校验失败（节点 ' + node.id + '）:' + err);
        }
        inserted.set(node.id, {
          id: node.id, conversationId: conv.conversationId,
          parentMessageId: node.parentMessageId
        });
      }
      for (const branch of conv.branches) {
        if (branch.headMessageId !== null && !inserted.has(branch.headMessageId)) {
          throw new Error('图域校验失败：分支 ' + branch.id + ' head 不在节点集');
        }
      }
      for (const ref of conv.refs) {
        const nodeId: string = gtRowText(ref['nodeId']);
        if (!inserted.has(nodeId)) {
          throw new Error('图域校验失败：附件引用 ' + gtRowText(ref['id']) + ' 悬挂');
        }
      }
      // 单事务重建图侧（替换语义：删旧图侧行 + 节点图列回写 + 重插；消息行本体已由
      // ExportImport 表循环按同 id 恢复——「替换消息＋附件元数据作废」同批由表循环
      // replacedIds 链承接）
      // ★ 写串行链入链（staging 校验读段留链外；commit 后文件清单并入时序不变）
      await runWriteQueued('importGraphDomain', async (): Promise<void> => {
        rdb.beginTransaction();
        try {
          // ★ S8② 导入替换面：空串占位附件行的旧态与快照 refs 集**必须在删 refs 之前**读
          //——旧 refs 被整批替换（DELETE → 按快照重插），空串行（K4：graph 资源行
          // messageId = ''，归属恒经 refs）若不在新 refs 集里就永久失去归属。作废集 = 旧
          // 空串行 − 快照 refs 集：事务内删行，localPath 随返回值交调用方在 commit 之后删
          // 文件（回滚不得已删文件红线）。
          // ★ 口径收窄（相对方案原文的「(旧 refs ∪ 空串行) − 新集」）：**只作废空串占位行**
          //——messageId 非空的行其归属另有 legacy 列表达，computeAttachmentSurvivors 判据
          // 面把「messageId ∈ 现存消息」算作可达而存活——删它会把活消息上还看得见的附件行
          // 与文件真删掉（判据面与写入面自相矛盾）。这类行另有既有链兜：被覆盖消息走
          // ExportImport.replacedIds → deleteAttachmentsForMessages，消息已亡的走导入尾部
          // reconcileAttachments 孤儿行段。
          const priorBlankRows: PriorBlankOwnerRow[] = [];
          const priorResult: relationalStore.ResultSet = await rdb.querySql(
            'SELECT id, localPath FROM message_attachments WHERE conversationId = ? ' +
            'AND LENGTH(messageId) = 0', [conv.conversationId]);
          try {
            while (priorResult.goToNextRow()) {
              priorBlankRows.push({
                id: priorResult.getString(priorResult.getColumnIndex('id')),
                localPath: priorResult.getString(priorResult.getColumnIndex('localPath'))
              });
            }
          } finally {
            priorResult.close();
          }
          const snapshotRefIds: Set<string> = new Set<string>();
          for (const ref of conv.refs) {
            const refAttachId: string = gtRowText(ref['attachmentId']);
            if (refAttachId !== '') {
              snapshotRefIds.add(refAttachId);
            }
          }
          await rdb.executeSql('DELETE FROM attachment_refs WHERE conversationId = ?',
            [conv.conversationId]);
          await rdb.executeSql('DELETE FROM tool_facts WHERE runId IN (SELECT id FROM ' +
            'generation_runs WHERE conversationId = ?)', [conv.conversationId]);
          await rdb.executeSql('DELETE FROM generation_runs WHERE conversationId = ?',
            [conv.conversationId]);
          await rdb.executeSql('DELETE FROM summary_bindings WHERE conversationId = ?',
            [conv.conversationId]);
          await rdb.executeSql('DELETE FROM branches WHERE conversationId = ?',
            [conv.conversationId]);
          // ★ S6② 二道闸：节点图列回写改 rdb.update + 谓词并逐行校验 affected 行数——
          // staging 核验与本段之间仍有并发删除窗口（两者之间隔着若干 await，非同一快照），
          // 零行/多行命中都说明该会话图侧写歪（节点缺失或 id 撞车）；原退 executeSql 不看
          // 命中数，会把图列写到零行上照样 commit。命中数非 1 即抛，由内层 catch 回滚整个
          // 会话（不产生图态半成品）。
          for (const node of conv.nodes) {
            const nodeBucket: relationalStore.ValuesBucket = {
              'parentMessageId': node.parentMessageId, 'runId': node.runId,
              'ownerAssistantId': node.ownerAssistantId, 'stepIndex': node.stepIndex,
              'origin': node.origin, 'seq': node.seq, 'coversToSeq': node.coversToSeq
            };
            const nodePredicates: relationalStore.RdbPredicates =
              new relationalStore.RdbPredicates('messages');
            nodePredicates.equalTo('conversationId', conv.conversationId);
            nodePredicates.equalTo('id', node.id);
            const nodeAffected: number = await rdb.update(nodeBucket, nodePredicates);
            if (nodeAffected !== 1) {
              throw new Error('图域导入失败：节点 ' + node.id + ' 行更新命中 ' + nodeAffected +
                ' 行（应为 1），已回滚该会话');
            }
          }
          for (const branch of conv.branches) {
            await rdb.executeSql(
              'INSERT INTO branches (id, conversationId, parentBranchId, headMessageId, ' +
              'name, createdAt) VALUES (?, ?, ?, ?, ?, ?)',
              [branch.id, conv.conversationId, branch.parentBranchId, branch.headMessageId,
                branch.name, branch.createdAt]);
          }
          for (const run of conv.runs) {
            await rdb.executeSql(
              'INSERT INTO generation_runs (id, conversationId, branchId, attemptEpoch, ' +
              'inputAnchorMessageId, revision, status, checkpoint, diagnosticMessageId, ' +
              'createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
              [bindArg(run['id']), bindArg(run['conversationId']), bindArg(run['branchId']),
                bindArg(run['attemptEpoch']), bindArg(run['inputAnchorMessageId']),
                bindArg(run['revision']), bindArg(run['status']), bindArg(run['checkpoint']),
                bindArg(run['diagnosticMessageId']), bindArg(run['createdAt']),
                bindArg(run['updatedAt'])]);
          }
          for (const fact of conv.facts) {
            // v54 随形加 finishedAt 列；旧格式备份（v54 前）无该键——bindArg 对缺键回 ''
            // 不适用 INTEGER 列，故本列单独判型，缺键落 0 =「无终态时刻」存量语义
            const factFinishedAt: number =
              typeof fact['finishedAt'] === 'number' ? fact['finishedAt'] as number : 0;
            await rdb.executeSql(
              'INSERT INTO tool_facts (id, runId, attemptId, name, state, payload, result, ' +
              'createdAt, finishedAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
              [bindArg(fact['id']), bindArg(fact['runId']), bindArg(fact['attemptId']),
                bindArg(fact['name']), bindArg(fact['state']), bindArg(fact['payload']),
                bindArg(fact['result']), bindArg(fact['createdAt']), factFinishedAt]);
          }
          for (const binding of conv.bindings) {
            await rdb.executeSql(
              'INSERT INTO summary_bindings (id, conversationId, summaryMessageId, ' +
              'coversFromSeq, coversToSeq, dependsOnBindingId, createdAt) ' +
              'VALUES (?, ?, ?, ?, ?, ?, ?)',
              [binding.id, conv.conversationId, binding.summaryMessageId,
                binding.coversFromSeq, binding.coversToSeq, binding.dependsOnBindingId,
                binding.createdAt]);
          }
          for (const ref of conv.refs) {
            await rdb.executeSql(
              'INSERT INTO attachment_refs (id, conversationId, attachmentId, nodeId, ' +
              'createdAt) VALUES (?, ?, ?, ?, ?)',
              [bindArg(ref['id']), bindArg(ref['conversationId']), bindArg(ref['attachmentId']),
                bindArg(ref['nodeId']), bindArg(ref['createdAt'])]);
          }
          // 作废空串占位行（不在快照 refs 集内 = 恢复后零归属；行删在事务内，文件清单交
          // commit 之后）——与 ①staging 核验、②affected 复核同属 S6/S8 两笔拒写闸面
          const staleIds: string[] = [];
          const stalePaths: string[] = [];
          for (const row of priorBlankRows) {
            if (!snapshotRefIds.has(row.id)) {
              staleIds.push(row.id);
              stalePaths.push(row.localPath);
            }
          }
          if (staleIds.length > 0) {
            const stalePredicates: relationalStore.RdbPredicates =
              new relationalStore.RdbPredicates('message_attachments');
            stalePredicates.in('id', staleIds);
            await rdb.delete(stalePredicates);
          }
          // 发布写复核（★ LB-3）：命中数 ≠ 1 = conversations 行不在库（备份缺该行 / 表循环
          // 插入失败）——原 executeSql 不看命中数，图侧五表会提交给一个不存在的会话成孤儿
          // 行，且 branches 非 OR REPLACE，再导同一会话即永久撞主键。改 predicates 形态与
          // 同函数消息行回写的 affected 复核（S6②）同口径，失败走内层 catch 回滚整会话
          const pubPredicates: relationalStore.RdbPredicates =
            new relationalStore.RdbPredicates('conversations');
          pubPredicates.equalTo('id', conv.conversationId);
          const pubAffected: number = await rdb.update({
            'migrateState': 'graph',
            'activeBranchId': conv.activeBranchId
          }, pubPredicates);
          if (pubAffected !== 1) {
            throw new Error('图域导入发布失败：会话行不存在（' + conv.conversationId + '）');
          }
          rdb.commit();
          applied++;
          // 文件删除清单**在 commit 之后**并入返回值（回滚不得已删文件；上面 stalePaths 只
          // 是候选，事务没提交就一个也不交出去）
          for (const p of stalePaths) {
            invalidatedLocalPaths.push(p);
          }
        } catch (e) {
          rdb.rollBack();
          throw e as Error;
        }
      });
    } catch (e) {
      failed++;
      hilog.warn(GT_DOMAIN, GT_TAG, '图域导入跳过会话 %{public}s：%{public}s',
        conv.conversationId, (e as Error).message);
    }
  }
  return { applied: applied, failed: failed, invalidatedLocalPaths: invalidatedLocalPaths };
}

// ── 图侧清理判定面（2026-09-26 自检位C S8① 接线；依赖倒置，理由见 AttachmentDb 头注释）──

// 判定面构造（AttachmentDb.reconcileAttachments 第三参的注入源）：capability ≥ 2 才给判定
// 函数，否则回 null = 空串占位行保护不删（J7 现状；能力不在场时调用方零查询零删除）。
// capability 读失败由 readGraphCapabilityLevel 自吞返 0 ⇒ 落 null——fail-safe = 不删
//（与「无能力不认 refs」同一取向）。
export async function buildAttachmentGraphCleanup(db: relationalStore.RdbStore):
  Promise<AttachmentGraphCleanup | null> {
  let level: number = 0;
  try {
    level = await readGraphCapabilityLevel(db);
  } catch (e) {
    // 能力读异常 = 判定面不可得 ⇒ null（fail-safe = 空串行保护不删；P0-1 留痕不静默）。
    // 本函数对调用方**恒 resolve**（调用点在做 fire-and-forget 收敛，不能把「数据已恢复」
    // 的导入收尾变成抛错）
    hilog.warn(GT_DOMAIN, GT_TAG, '图能力读失败，本次清理跳过图侧空串行回收：%{public}s',
      (e as Error).message);
    return null;
  }
  if (level < GRAPH_LEVEL_ENABLED) {
    return null;
  }
  return { pickUnreachable: pickUnreachableBlankOwners };
}

// 空串占位行的不可达挑选（判定单源 = computeAttachmentSurvivors——J7 规则不在本件复制第二
// 份，本函数只做形状适配）：survivingMessageIds 传空集（空串行的 legacy 判据恒不成立，可达
// 性只可能由 refs 给出）；图能力参数传 GRAPH_LEVEL_ENABLED（本函数只在 capability ≥ 2 时
// 被构造，此处语义就是「图能力在场」）。两处形状适配是**跨域类型转换**，逐字段对照，两侧
// 任一改名都在编译期报错。
function pickUnreachableBlankOwners(blankRows: AttachmentBlankOwnerRow[],
  refs: AttachmentGraphRefRow[], survivingNodeIds: Set<string>): string[] {
  const survivorRows: AttachmentSurvivorRow[] = [];
  for (const row of blankRows) {
    survivorRows.push({ attachmentId: row.attachmentId, messageId: row.messageId });
  }
  const survivorRefs: GraphRefRow[] = [];
  for (const ref of refs) {
    survivorRefs.push({ attachmentId: ref.attachmentId, nodeId: ref.nodeId });
  }
  const verdicts: AttachmentSurvivorVerdict[] = computeAttachmentSurvivors(survivorRows,
    survivorRefs, GRAPH_LEVEL_ENABLED, new Set<string>(), survivingNodeIds);
  const unreachable: string[] = [];
  for (const verdict of verdicts) {
    if (!verdict.survive) {
      unreachable.push(verdict.attachmentId);
    }
  }
  return unreachable;
}
