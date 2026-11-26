// 图写命令族与摘要两写口（自 ChatContextSource.ets 拆出）。
// 域定义：graph 会话的**写侧命令编排单点**——发送起轮 / 工具事实推进 / 轮输出提交 / run 收口 /
// 账本落库 / 重试起轮与锚点上溯的图命令组装 + 摘要采用与删除两个写口。
// 依赖方向（零环红线，坑50）：本件 → ChatContextSource（唯一边：isNodeOnActivePath 路径
// 核验口，主件零 import 本件）+ ChatDb / MessageBranchDb / CompressDb / DbWriteQueue /
// AttachmentDb / ChatBranchPolicy 单向；**store 侧零件反向 import 本件**；组件层只 import
// 本件，不经本件触达冻结命令层（对接面收敛）。
// 模块顶层零求值纪律（坑50 家族）：顶层零求值，禁顶层 new / 跨件函数调用 / AppStorage 读
//（函数体内读不受限）。
// SUMMARY_PATH_STEPS_MAX 随 deleteGraphSummary 同件（断言锚「两锚同件」）；主件另有同名
// 常量一份（主件禁 import 本件）——**改值时两处同改**。
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { insertAttachments, MessageAttachmentRow } from '../store/AttachmentDb';
import { isAdoptInflight, markAdopt } from '../store/CompressDb';
import { nextMessageId, nextRowCreatedAt, queryConversationActiveBranch,
  queryConversationMigrateState, setConversationActiveBranch,
  sharedRdbStore } from '../store/ChatDb';
import { CONV_STATE_GRAPH, BranchRow,
  CommitUnitInput, CommitUnitOutput, FinishRunInput,
  PrepareRetryRunInput, PrepareRunInput, PreparedRun, RUN_STATUS_AWAITING_INPUT,
  RUN_STATUS_FAILED,
  RUN_STATUS_FINISHED, RUN_STATUS_RUNNING, MSG_STATUS_STREAMING, ToolFactInput, UsageEventInput,
  TOOL_FACT_PREPARED, TOOL_FACT_DISPATCH_INTENT,
  commitRunUnit, finishRun, forkBranch, prepareRetryRun, prepareRun,
  queryBranch, recordToolFact, recordUsageEvent, updateStreamingNodeCheckpoint }
  from '../store/MessageBranchDb';
import { nextRowSeq } from '../store/MessageSeqDb';
import { runWriteQueued } from '../store/DbWriteQueue';
// 等待单元读口的意图事实定位按工具名过滤（ask 停留态专属）
import { TOOL_ASK_USER } from '../providers/ToolIds';
// 判据叶子（零依赖件）：墓碑文案单源——本件只做写编排，判据归彼件
import { TOMBSTONE_TOAST_TEXT } from './ChatBranchPolicy';
// 主件单向取读侧核验口（isNodeOnActivePath 留主件，采用核验不另起第二套判据）
import { isNodeOnActivePath } from './ChatContextSource';

const DOMAIN: number = 0x71C6;
const TAG: string = 'ChatGraphCommandSource';

// ── 写侧：图命令编排 ──

// 运行句柄（发送/重试轮的图侧进度——宿主持有，提交成功后由宿主推进 revision）
export interface GraphRunHandle {
  runId: string;
  branchId: string;
  revision: number;
}

// 图节点引用（库身份 + 入链号）：压缩选段边界与请求裁剪判据依赖 rowSeq、摘要采用核验锚
//（isNodeOnActivePath）依赖节点 id，缺则图会话未离页时压缩不可用、采用必报「路径已变化」
//——宿主在图提交回读后回填内存行。seq = -1 = 读不到号（防御，按「无号」处理不动原值）
export interface GraphNodeRef {
  nodeId: string;
  seq: number;
}

// 发送起轮产物（句柄 + user 节点引用——宿主在开流前回填 user 消息的 rowSeq/nodeId）
export interface GraphSendStart {
  handle: GraphRunHandle;
  userNode: GraphNodeRef;
}

// 发送起轮（K5：先提交 user 事实再开流）：prepareRun（原子：user 节点 + head 前移 + run 行
// prepared）→ 附件 refs 建链（K4：graph 资源行 messageId = '' 占位；元数据行由调用方随 user
// 行落，本函数只落 refs）。crash 窗口已知边界：prepareRun 提交后、refs 落库前终止会留「有
// 节点无 refs」附件行——capability≥2 下按不可达被清理器回收，毫秒级窗口
export async function graphBeginSend(input: PrepareRunInput,
  attachRows: MessageAttachmentRow[]): Promise<GraphSendStart> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const prepared: PreparedRun = await prepareRun(db, input);
  // fail-closed（防未来回退）：有附件却无 user 节点（userNodeId=''）= 写 nodeId='' 悬引用
  //（启动收敛按不可达判删行 + 文件）。当前发送链闸使该组合不可达，此处显式拒绝而非赌上游
  if (prepared.userNodeId === '' && attachRows.length > 0) {
    throw new Error('有附件但无用户节点，拒绝建悬引用');
  }
  // 附件占位行落库（K4：graph 资源行 messageId = ''）+ 逐行建 refs 挂 user 节点
  if (attachRows.length > 0) {
    await insertAttachments(db, attachRows);
  }
  await insertAttachmentRefs(db, input.conversationId, attachRows, prepared.userNodeId);
  // user 节点号回读（live 链 rowSeq 回填来源——压缩选段边界与请求裁剪判据依赖它；读不到按 -1）
  const userSeq: number = await queryNodeSeq(db, prepared.userNodeId);
  return {
    handle: { runId: prepared.runId, branchId: input.branchId, revision: prepared.revision },
    userNode: { nodeId: prepared.userNodeId, seq: userSeq }
  };
}

// 附件 refs 建链（K4：资源行逐条挂节点；空集零开销）
async function insertAttachmentRefs(db: relationalStore.RdbStore, conversationId: string,
  attachRows: MessageAttachmentRow[], nodeId: string): Promise<void> {
  if (attachRows.length === 0) {
    return;
  }
  const now: number = Date.now();
  for (const row of attachRows) {
    const attachmentId: string = row.id;
    await db.insert('attachment_refs', {
      'id': nextMessageId('ref'),
      'conversationId': conversationId,
      'attachmentId': attachmentId,
      'nodeId': nodeId,
      'createdAt': now
    });
  }
}

// 工具事实推进（J10 意图先行：派发前 prepared→dispatch_intent 两写；结果确认/失败各一写）。
// factId 空 = 新建 prepared 并连转 toState；非空 = 既有事实推进。非法迁移由命令层查表抛错
export async function graphToolFactAdvance(factId: string, runId: string, attemptId: string,
  name: string, toState: string, payload: string, result: string): Promise<string> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const input: ToolFactInput = {
    factId: factId,
    runId: runId,
    attemptId: attemptId,
    name: name,
    toState: toState,
    payload: payload,
    result: result,
    now: Date.now()
  };
  return recordToolFact(db, input);
}

// 新建工具事实并直接推进到 dispatch_intent（派发前唯一调用形态——prepared 落行与意图推进
// 两写合一个编排口，宿主 lane 内零状态）
export async function graphToolFactDispatchIntent(runId: string, attemptId: string,
  name: string, payload: string): Promise<string> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const factId: string = await recordToolFact(db, {
    factId: '', runId: runId, attemptId: attemptId, name: name,
    toState: TOOL_FACT_PREPARED, payload: payload, result: '', now: Date.now()
  });
  await recordToolFact(db, {
    factId: factId, runId: runId, attemptId: attemptId, name: name,
    toState: TOOL_FACT_DISPATCH_INTENT, payload: '', result: '', now: Date.now()
  });
  return factId;
}

// 轮输出提交（assistant 中间轮 / tool 结果节点 / 终答共用）：commitRunUnit CAS——revision
// 冲突（并发写者）返回 null 由宿主呈报不静默；成功由宿主推进 handle.revision。
// 返回值 = 本次落库的输出节点 id（commitRunUnit 只回 boolean〔冻结签名〕，按 **runId 定位**
// 补得——账本挂靠与建议锚需要真库身份，内存占位 id 与节点 id 不同源）；失败回 null。
// ★ 回读禁按分支 head（修复 F-3②）：提交与回读间并发写者推进 head 会读到**别人的**节点；
// 本 run 的 seq 最大节点即本次提交产物（run 内节点 seq 单调，用户节点 seq 恒小于输出节点）。
// origin 入参 = 输出节点来源登记值（ORIGIN_SEND / ORIGIN_RESEND），由调用方给、列值不硬编码。
// 三可选参（默认值 = 既有调用逐字零变化）：nodeStatus（'streaming' = 流中占位行落库）；
// updateNodeId（非空 = 终态收口走「更新既有占位行」路径，不插行不前移 head，谓词防迟到复活）；
// runStatusOnCommit（等待行落库传 RUN_STATUS_AWAITING_INPUT——插行与 run 停留态同一 CAS
// 事务原子落定）
export async function graphCommitNode(handle: GraphRunHandle, role: string, content: string,
  reasoning: string, stepIndex: number, now: number, origin: string,
  nodeStatus: string = 'done', updateNodeId: string = '',
  runStatusOnCommit: string = RUN_STATUS_RUNNING): Promise<GraphNodeRef | null> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const output: CommitUnitOutput = {
    content: content, reasoning: reasoning, role: role, stepIndex: stepIndex,
    nodeStatus: nodeStatus, updateNodeId: updateNodeId, runStatus: runStatusOnCommit
  };
  const input: CommitUnitInput = {
    runId: handle.runId,
    expectedRevision: handle.revision,
    checkpoint: '',
    output: output,
    now: now,
    origin: origin
  };
  const ok: boolean = await commitRunUnit(db, input);
  if (!ok) {
    return null;
  }
  handle.revision = handle.revision + 1;
  // 更新路径的回读锚 = 占位行自身（UPDATE 不改 seq，它仍是本 run 的 seq 最大节点——
  // 收口前无插行；直接沿用「seq 最大回读」保持单一回读实现）
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT id, seq FROM messages WHERE runId = ? ORDER BY seq DESC LIMIT 1', [handle.runId]);
  try {
    if (!result.goToNextRow()) {
      return null; // 本 run 无节点（理论不达——提交刚成功）
    }
    const nodeId: string = result.getString(result.getColumnIndex('id'));
    // 节点号回读（live 链 rowSeq/nodeId 回填来源——宿主提交后就地回填内存行，图会话未离页
    // 时压缩与采用核验随之可用）；读不到按 -1（防御）
    const seqIdx: number = result.getColumnIndex('seq');
    const seq: number = result.isColumnNull(seqIdx) ? -1 : result.getLong(seqIdx);
    return { nodeId: nodeId, seq: seq };
  } finally {
    result.close();
  }
}

// 流中占位行 checkpoint 编排口：单行覆写 + 防迟到复活守卫（命令层谓词）——false = 行已终态，
// 调用方丢弃快照不重试。不推 revision 不动 run 状态（CAS 推进只随插行/收口走；latest-wins
// 排水在 ChatStreamCheckpoint 域件，本口只做库侧命令组装）
export async function graphCheckpointNode(nodeId: string,
  content: string, reasoning: string): Promise<boolean> {
  return updateStreamingNodeCheckpoint(sharedRdbStore(),
    { nodeId: nodeId, content: content, reasoning: reasoning });
}

// run 终态收口（K6：done → finished；失败 → failed 带诊断）。幂等——重复收尾（finishStream
// 与 disposeSilent 竞态）由 finishRun 终态守卫吸收。第四参 finalStatus = 显式终态
//（RUN_STATUS_* 终态值）；缺省 '' 沿用 ok 布尔推导（finished/failed）；停止路径传
// RUN_STATUS_STOPPED 使「手动停止」与「真失败」在 run 层区分（display 侧 mapTraceRunStatus
// 按值分流）
export async function graphFinishRun(handle: GraphRunHandle, ok: boolean,
  diagnosticContent: string, finalStatus: string = ''): Promise<void> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const input: FinishRunInput = {
    runId: handle.runId,
    finalStatus: finalStatus !== '' ? finalStatus : (ok ? RUN_STATUS_FINISHED : RUN_STATUS_FAILED),
    diagnosticContent: diagnosticContent,
    now: Date.now()
  };
  await finishRun(db, input);
}

// 账本落库（K6 去重接线：requestId = 运行级流序号派生，重复回调幂等跳过——去重规则冻结
// 只认 requestId，禁按 run/attempt）
export async function graphRecordUsage(event: UsageEventInput): Promise<boolean> {
  return recordUsageEvent(sharedRdbStore(), event);
}

// 末轮重试起轮（K5/P4：建替代分支，旧路径不删）：沿目标答案节点上溯找最近 user 锚 →
// forkBranch（新分支 head = 锚点）→ prepareRetryRun（不新增 user 节点）→ 切 activeBranchId。
// 返回新句柄；分支切换失败（理论不达——CAS 无此路径）上抛由调用方呈报。
// anchorNodeId 由调用方经 walkRetryAnchor 求得（读侧职责与本编排分离，便于直跑验证）
export async function graphBeginRetry(input: PrepareRetryRunInput): Promise<GraphRunHandle> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const forked = await forkBranch(db, {
    conversationId: input.conversationId,
    sourceBranchId: input.branchId,
    forkAtNodeId: input.anchorNodeId,
    name: '',
    now: input.now
  });
  const retryInput: PrepareRetryRunInput = {
    runId: input.runId,
    conversationId: input.conversationId,
    branchId: forked.branchId,
    assistantId: input.assistantId,
    anchorNodeId: input.anchorNodeId,
    now: input.now
  };
  await prepareRetryRun(db, retryInput);
  await setConversationActiveBranch(input.conversationId, forked.branchId);
  hilog.info(DOMAIN, TAG, '重试替代分支已建 %{public}s（锚 %{public}s）',
    forked.branchId, input.anchorNodeId);
  return { runId: input.runId, branchId: forked.branchId, revision: 0 };
}

// 续写重开节点（二期 S4 #10）：把已收尾答案节点状态置回 streaming——commitRunUnit 的
// 更新路径谓词要求 status='streaming'（防迟到复活），续写收尾才能走「同一节点原地覆写」。
// 只动 status 一列（content/reasoning 保留存值，续写流以它为首值继续累积）；affected=0 =
// 节点不存在或已在流式态（幂等失败），调用方按起轮失败呈报。
export async function graphReopenNode(nodeId: string): Promise<boolean> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const bucket: relationalStore.ValuesBucket = { 'status': MSG_STATUS_STREAMING };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('messages');
  predicates.equalTo('id', nodeId);
  const affected: number = await db.update(bucket, predicates);
  return affected === 1;
}

// 续写起轮（二期 S4 #10）：**不 fork 分支**——在当前分支上为本轮建新 run 行，输入锚点 =
// 目标 assistant 节点自身（分支 head 即它；prepareRetryRun 的 head 一致性校验天然校验
// 「只能在末条答案上续写」）。handle.runId 是新的 ⇒ finishRound 的账本 requestId 去重不
// 会吞本轮（续写消耗照常落账），节点提交走 updateNodeId = 目标节点 = 同一 messageId 原地
// 追加。forkBranch 不参与 = 版本计数不新增（续写不是新版本）。
export async function graphBeginContinue(input: PrepareRetryRunInput): Promise<GraphRunHandle> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  await prepareRetryRun(db, input);
  hilog.info(DOMAIN, TAG, '续写轮已建 run %{public}s（锚 %{public}s）',
    input.runId, input.anchorNodeId);
  return { runId: input.runId, branchId: input.branchId, revision: 0 };
}

// 重试锚点上溯（读侧：沿目标节点 parent 链找最近 role='user' 祖先——重试 = 从该锚点重新
// 生成；找不到（坏链防御）返回 null 由调用方降级呈报。按节点 id 全库定位（messages.id
// 全局唯一、路径无关），不受会话约束）
export async function walkRetryAnchor(nodeId: string): Promise<string | null> {
  return walkAncestorUser(sharedRdbStore(), nodeId);
}

// 末轮锚点回退（live 链身份不同源）：从当前分支 head 上溯找最近 user 祖先——目标 id 是
// 内存 id（live 链消息 id 与图节点 id 不同源）时按 id 查不到行，按「末轮重试 = 末条答案所在
// 轮的 user 锚」语义回退（目标恒为已收尾答案、其轮 user 锚唯一，两法同解；离页重进走回放链
// id = 节点 id，仍走 walkRetryAnchor 精确解）
export async function walkLatestUserAnchor(branchId: string): Promise<string | null> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const branch: BranchRow | null = await queryBranch(db, branchId);
  if (branch === null || branch.headMessageId === null) {
    return null;
  }
  return walkAncestorUser(db, branch.headMessageId);
}

// 祖先链 user 定位（两读口共用；步数上界 512 防坏链）
async function walkAncestorUser(db: relationalStore.RdbStore,
  nodeId: string): Promise<string | null> {
  let cursor: string | null = nodeId;
  let steps: number = 0;
  while (cursor !== null && cursor !== '' && steps < 512) {
    const result: relationalStore.ResultSet = await db.querySql(
      'SELECT role, parentMessageId FROM messages WHERE id = ?', [cursor]);
    let role: string = '';
    let parent: string | null = null;
    try {
      if (!result.goToNextRow()) {
        return null;
      }
      role = result.getString(result.getColumnIndex('role'));
      const parentIdx: number = result.getColumnIndex('parentMessageId');
      parent = result.isColumnNull(parentIdx) ? null : result.getString(parentIdx);
    } finally {
      result.close();
    }
    if (role === 'user') {
      return cursor;
    }
    cursor = parent;
    steps++;
  }
  return null;
}

// 节点入链号回读（图提交/起轮回填内存行 rowSeq 用——压缩选段边界与请求裁剪判据依赖；
// 读不到（行缺失/seq 为 NULL）回 -1，调用方按「无号」不动原值）
async function queryNodeSeq(db: relationalStore.RdbStore, nodeId: string): Promise<number> {
  const result: relationalStore.ResultSet =
    await db.querySql('SELECT seq FROM messages WHERE id = ?', [nodeId]);
  try {
    if (result.goToNextRow()) {
      const seqIdx: number = result.getColumnIndex('seq');
      if (!result.isColumnNull(seqIdx)) {
        return result.getLong(seqIdx);
      }
    }
    return -1;
  } finally {
    result.close();
  }
}

// ── 提问等待单元读口（续答与放弃两路消费；本口只取库材料，callId 匹配与载荷解析在
//    ChatAskResumeCtrl 纯函数）──

// 等待单元候选行（一个 awaiting_input run × 其 streaming 工具行；调用方按行载荷 toolCallId
// 匹配目标 callId）。runRevision = 该 run 当前 revision（续答回填 CAS 的 expectedRevision）；
// maxStepIndex = 该 run 现有节点最大 stepIndex（-1 = 无；续答接管步序据此续号，防同 run 内
// 步序重号）；factId = 最近一枚 dispatch_intent 的 ask 意图事实（'' = 无在场意图，确认静默
// 跳过——与既有口径同）
export interface AwaitingAskCandidate {
  runId: string;
  branchId: string;
  runRevision: number;
  attemptEpoch: number;
  inputAnchorMessageId: string;
  waitNodeId: string;
  waitContent: string;
  maxStepIndex: number;
  factId: string;
}

// 会话内全部等待单元候选（awaiting_input run 的 streaming tool 行全取——等待行是 run 属
// 节点，run 无行退出/被清扫后自然缺席 = 无候选；量级 = 等待中会话的 run 数十位，逐 run 三查）。
// 调用方按载荷 toolCallId 匹配；匹配不到 = 该卡已答/已中止（静默吞，与 resolveAsk 同口径）。
// 'awaiting_input' 字面 = MessageBranchDb RUN_STATUS_AWAITING_INPUT 词表值（显式字面 + 回指，
// 避免与 RUN_STATUS_* 导入组混淆）
export async function graphAwaitingAskCandidates(
  conversationId: string): Promise<AwaitingAskCandidate[]> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const runResult: relationalStore.ResultSet = await db.querySql(
    'SELECT id, branchId, revision, attemptEpoch, inputAnchorMessageId FROM generation_runs ' +
    'WHERE conversationId = ? AND status = ?', [conversationId, 'awaiting_input']);
  const runs: string[][] = [];
  try {
    while (runResult.goToNextRow()) {
      runs.push([
        runResult.getString(runResult.getColumnIndex('id')),
        runResult.getString(runResult.getColumnIndex('branchId')),
        '' + runResult.getLong(runResult.getColumnIndex('revision')),
        '' + runResult.getLong(runResult.getColumnIndex('attemptEpoch')),
        runResult.getString(runResult.getColumnIndex('inputAnchorMessageId'))
      ]);
    }
  } finally {
    runResult.close();
  }
  const out: AwaitingAskCandidate[] = [];
  for (const run of runs) {
    const runId: string = run[0];
    const rowsResult: relationalStore.ResultSet = await db.querySql(
      "SELECT id, content FROM messages WHERE runId = ? AND role = 'tool' AND status = 'streaming'",
      [runId]);
    const waitRows: string[][] = [];
    try {
      while (rowsResult.goToNextRow()) {
        waitRows.push([rowsResult.getString(rowsResult.getColumnIndex('id')),
          rowsResult.getString(rowsResult.getColumnIndex('content'))]);
      }
    } finally {
      rowsResult.close();
    }
    if (waitRows.length === 0) {
      continue; // 无等待行 = 非等待单元（异常残留由 sweep 兜底段收口）
    }
    const maxResult: relationalStore.ResultSet = await db.querySql(
      'SELECT MAX(stepIndex) AS m FROM messages WHERE runId = ?', [runId]);
    let maxStepIndex: number = -1;
    try {
      if (maxResult.goToNextRow()) {
        const mIdx: number = maxResult.getColumnIndex('m');
        if (!maxResult.isColumnNull(mIdx)) {
          maxStepIndex = maxResult.getLong(mIdx);
        }
      }
    } finally {
      maxResult.close();
    }
    const factResult: relationalStore.ResultSet = await db.querySql(
      // rowid 降序 = 最近落成的意图事实（物理插入序即创建序；窗口序键字面有意回避，语义与
      // createdAt 降序等价，断言组守「旧序口径」字面）
      'SELECT id FROM tool_facts WHERE runId = ? AND name = ? AND state = ? ' +
      'ORDER BY rowid DESC LIMIT 1', [runId, TOOL_ASK_USER, TOOL_FACT_DISPATCH_INTENT]);
    let factId: string = '';
    try {
      if (factResult.goToNextRow()) {
        factId = factResult.getString(factResult.getColumnIndex('id'));
      }
    } finally {
      factResult.close();
    }
    for (const row of waitRows) {
      out.push({
        runId: runId,
        branchId: run[1],
        runRevision: Number.parseInt(run[2], 10),
        attemptEpoch: Number.parseInt(run[3], 10),
        inputAnchorMessageId: run[4],
        waitNodeId: row[0],
        waitContent: row[1],
        maxStepIndex: maxStepIndex,
        factId: factId
      });
    }
  }
  return out;
}

// 重启恢复待答会话集：全库 awaiting_input 且**有等待行**的会话 id 去重集——会话列表「生成中」
// 标记的跨重启重建源（列表标记是进程内存态、重启即灭；消费 = ChatSessionRuntime.
// primeRestoredAwaiting 或集判据）。判据与 graphAwaitingAskCandidates 同源（run 停留态 +
// streaming tool 等待行）：无等待行的异常 run 不产标记（防「无可作答卡却挂假转圈」）。
// 调用点 = EntryAbility 启动组合（本件禁 import 运行时件防环，坑50）
export async function graphAwaitingConversationIds(): Promise<string[]> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT DISTINCT r.conversationId AS conversationId FROM generation_runs r ' +
    "WHERE r.status = ? AND EXISTS (SELECT 1 FROM messages m WHERE m.runId = r.id " +
    "AND m.role = 'tool' AND m.status = 'streaming')", ['awaiting_input']);
  const ids: string[] = [];
  try {
    while (result.goToNextRow()) {
      ids.push(result.getString(result.getColumnIndex('conversationId')));
    }
  } finally {
    result.close();
  }
  return ids;
}

// ── 摘要写口（图侧采用/删除；路径核验 isNodeOnActivePath 留主件，本件单向 import）──

// 图采用（K9 采用事务 + K4 coversToSeq↔binding 切写同拍）：单事务插摘要节点（parent =
// 当前分支 head，摘要物理位置挂尾）→ head 前移 → 摘要绑定写入。**旧摘要节点不删**（图路径
// 删中段节点需重链接，无此原语且无必要——旧 binding 保留、请求组装「末摘要胜出」= 新摘要
// 生效，旧摘要文本留作可读档案）。采用前核预览范围在当前路径有效（切分支/编辑后过时摘要
// 不能裁新路径），失效抛错由面板呈报（草稿保留可重试）。coversFromSeq 落 null（裁剪判据
// 只消费 coversToSeq 上界）。
// ★ 三道前置守卫：空白会话 id 拒写；非 graph 态拒写（非 graph 即墓碑一律拒，仅图路一条）；
// 同会话采用在途拒写（登记件在 CompressDb；置位/复位在本函数内成对）。
// head 读取移进事务 + 前移带旧 head 谓词（CAS）
export async function adoptGraphSummary(conversationId: string, branchId: string,
  content: string, boundarySeq: number, boundaryNodeId: string): Promise<string> {
  if (conversationId === '') {
    throw new Error('无持久会话，不能保存摘要');
  }
  const state: string = await queryConversationMigrateState(conversationId);
  if (state !== CONV_STATE_GRAPH) {
    // 非 graph 即墓碑（迁移机制退役后不存在锁定态），文案单源在 ChatBranchPolicy
    throw new Error(TOMBSTONE_TOAST_TEXT);
  }
  if (isAdoptInflight(conversationId)) {
    throw new Error('上一次采用还在进行，请稍等');
  }
  markAdopt(conversationId, true);
  try {
    const onPath: boolean = await isNodeOnActivePath(conversationId, branchId, boundaryNodeId);
    if (!onPath) {
      throw new Error('会话路径已变化，这次摘要是旧范围的。请重新压缩后再采用');
    }
    const db: relationalStore.RdbStore = sharedRdbStore();
    const branch: BranchRow | null = await queryBranch(db, branchId);
    if (branch === null) {
      throw new Error('分支不存在，采用失败');
    }
    // D1 铸造纪律：号在写事务首条语句前取齐（写事务内单写串行化保证单调）
    const summaryId: string = nextMessageId('sum');
    const seq: number = nextRowSeq(conversationId);
    const createdAt: number = nextRowCreatedAt();
    // 写串行链入链（前置读段留链外；head 复核与 CAS 本就在事务内）
    return await runWriteQueued('adoptGraphSummary', async (): Promise<string> => {
      db.beginTransaction();
      try {
        // head 读取**在事务内**（事务外读 + 事务内无条件前移：两读之间的并发写者（同分支
        // 另一次采用/发送）会把 head 推走，无条件 UPDATE 再把它覆盖 = 该写者的节点被摘出
        // 路径，那条消息从会话消失）
        const headResult: relationalStore.ResultSet = await db.querySql(
          'SELECT headMessageId FROM branches WHERE id = ?', [branchId]);
        let head: string | null = null;
        try {
          if (!headResult.goToNextRow()) {
            throw new Error('分支不存在，采用失败');
          }
          const headIdx: number = headResult.getColumnIndex('headMessageId');
          head = headResult.isColumnNull(headIdx) ? null : headResult.getString(headIdx);
        } finally {
          headResult.close();
        }
        await db.insert('messages', {
          'id': summaryId,
          'conversationId': conversationId,
          'role': 'summary',
          'content': content,
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
        // CAS 前移（affected 精确校验，同 MessageBranchDb 命令层口径）：只在前移前 head 未被
        // 并发写者改动时命中；失配即回滚上抛（面板呈报，草稿保留可重试）
        const headBucket: relationalStore.ValuesBucket = { 'headMessageId': summaryId };
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
          throw new Error('会话路径已变化，这次摘要没有保存，请重新压缩后再采用');
        }
        await db.insert('summary_bindings', {
          'id': nextMessageId('sbd'),
          'conversationId': conversationId,
          'summaryMessageId': summaryId,
          'coversFromSeq': null,
          'coversToSeq': boundarySeq,
          'dependsOnBindingId': '',
          'createdAt': createdAt
        });
        db.commit();
        return summaryId;
      } catch (e) {
        db.rollBack();
        throw e as Error;
      }
    });
  } finally {
    // 成败两路都释放（成对纪律：置位在本函数内，复位也必须在本函数内）
    markAdopt(conversationId, false);
  }
}

// 图摘要删除（用量面板「删除摘要」键的图形态）——**软删：binding 删、文本行留**，口径 =
//「回到全文」真语义：沿当前分支 head 上溯收集路径上**全部** summary 节点，一并失效其
// binding（单条 DELETE 原子，无中段删链原语需要——文本行保留作档案可读，binding 删即不
// 生效，读口跳过无绑定 summary、请求侧与面板随之回到全文。★ 共享前缀上的摘要节点被批
// 失效时，共享该节点的其他分支同失效，属预期——两分支共享同一节点即共享同一状态）。
// 返回失效 summary id 集（宿主据以清流内全部提示行；传入 id 不在路径集 = 面板状态已过期，
// 幂等返回空集不报错）
export async function deleteGraphSummary(conversationId: string,
  summaryId: string): Promise<string[]> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const branchId: string = await queryConversationActiveBranch(conversationId);
  if (branchId === '') {
    throw new Error('会话不在图形态，无法执行图侧摘要删除');
  }
  const branch: BranchRow | null = await queryBranch(db, branchId);
  if (branch === null) {
    throw new Error('分支不存在，删除失败');
  }
  // 路径上全部 summary 节点收集（沿 parent 链上溯；步数上界同 findPathSummaryRow 家族）
  const summaryIds: string[] = [];
  let cursor: string | null = branch.headMessageId;
  let steps: number = 0;
  while (cursor !== null && cursor !== '' && steps < SUMMARY_PATH_STEPS_MAX) {
    const probe: relationalStore.ResultSet = await db.querySql(
      'SELECT role, parentMessageId FROM messages WHERE id = ?', [cursor]);
    let role: string = '';
    let parent: string | null = null;
    try {
      if (!probe.goToNextRow()) {
        break; // 悬边（坏链）——已收节点仍有效
      }
      role = probe.getString(probe.getColumnIndex('role'));
      const parentIdx: number = probe.getColumnIndex('parentMessageId');
      parent = probe.isColumnNull(parentIdx) ? null : probe.getString(parentIdx);
    } finally {
      probe.close();
    }
    if (role === 'summary') {
      summaryIds.push(cursor);
    }
    cursor = parent;
    steps++;
  }
  if (summaryIds.indexOf(summaryId) < 0) {
    return []; // 传入行已不在当前路径（他分支/已删过）——幂等返回
  }
  // 写串行链入链（同 adoptGraphSummary 先例：前置读段留链外）——binding 批删裸写绕链，
  // 飞行写事务在场时直接报 14800024。不动 head 无需 CAS 复核；单条 DELETE 原子不开显式事务
  await runWriteQueued('deleteGraphSummary', async (): Promise<void> => {
    await db.executeSql('DELETE FROM summary_bindings WHERE conversationId = ? AND ' +
      'summaryMessageId IN (' + summaryIds.map((_id: string): string => '?').join(',') + ')',
      [conversationId].concat(summaryIds));
  });
  return summaryIds;
}

// 路径链上溯步数上界（防坏链；摘要节点恒靠头，实读远小于此）。
// ★ 随 deleteGraphSummary 同件（断言锚「两锚同件」要求）；主件另有同名常量一份（主件禁
// import 本件）——**改值时两处同改**
const SUMMARY_PATH_STEPS_MAX: number = 512;
