// 分支图仓储命令域：messages 图列（parentMessageId/runId/ownerAssistantId/stepIndex/origin）
// + branches / generation_runs / tool_facts / summary_bindings / attachment_refs /
// graph_capability 六表的命令层单源。消费面 = 图读写全链（ChatContextSource 编排 →
// ChatGraphWriteCtrl / ChatPageLoad / ChatBranchCtrl 组件接线；旧库构图迁移器已随旧会话
// 墓碑笔整件退役）。
// · 职责一句话 = 分支图的身份、原子命令与图级导入导出/删除策略（无既有同域可并——
//   ChatDb.ets 是线性读写主域；实逻辑非转接壳，每个命令都是事务/CAS/校验的完整实现）。
// · 依赖方向（零环红线，坑50）：本件 → ChatDb（nextMessageId——节点 id 与现役消息同族）
//   单向，**ChatDb 不 import 本件**；库句柄一律由调用方作实参传入（MessageSeqDb 同款），
//   本件不读任何模块级库状态——纯函数段可剥 import 直跑（下方「纯函数（断言直跑面）」，
//   顶层零外部绑定求值）。
// · 事务纪律（J6）：全部多写命令走官方**对象事务** createTransaction（IMMEDIATE 写事务，
//   API 26 在场，本地 d.ts :6403/:6486 实读）——**不嵌套** beginTransaction 经典三件套
//  （嵌套抛错；两套事务互斥面 = 同库同时只有一个写事务，d.ts 14800024）。本域命令不含
//   任何网络调用。
// · 身份纪律（J10/J12）：runId 是**外部身份**——由 ChatRunScope 铸造方传入（形制
//   run_<毫秒>_<序号>，attemptId = runId#a<epoch>），本域**不重铸不重编号**；分支/工具
//   事实等图内 id 由本域经 ChatDb.nextMessageId 铸造（前缀 'br'/'tf'——与 'msg'/'sum'
//   同族，仅人读）。
// · 删除子树存活集/谱系删除判定族/附件存活集判定族纯函数已拆 MessageGraphPrune.ets
//  （本件贴 1200 硬线时的域级拆分，搬迁面见彼件头注释）；traceAncestorChain 留本件
//  （forkBranch 路径校验仍消费，新件单向引回）。
// · 禁 mock 纪律：本域可用性证明 = 隔离库真实执行（W 组场景）；mock 返回成功不算通过。
import { relationalStore } from '@kit.ArkData';
import { nextMessageId } from './ChatDb';
import { nextRowSeq } from './MessageSeqDb';
import { runWriteQueued } from './DbWriteQueue';
// v57 排队出队原子：事务内删排队行的 SQL 单源在 ChatSendQueueDb（本件只消费常量——免两处
// 删行口径漂移；彼件零 import 本件，零环）
import { SQL_DELETE_SEND_QUEUE_ITEM } from './ChatSendQueueDb';

// ── 值域常量（词表冻结——笔3/笔4/笔5 按此消费；改名 = 三级止损）──

// run 生命周期（generation_runs.status）。终态扩值：stopped = 用户手动停止的一等终态
//（finishStream 停止路径经 graphFinishRun 落值）；interrupted = 进程退出/启动清扫兜底/
// 后台超时终态。status 列 TEXT 无 CHECK 约束（E1 #14 实证）——扩值零迁移直入；存量 failed
// 历史不回刷（历史停止与失败混存于 failed，读侧维持 error 语义）
export const RUN_STATUS_PREPARED: string = 'prepared';
export const RUN_STATUS_RUNNING: string = 'running';
export const RUN_STATUS_FINISHED: string = 'finished';
export const RUN_STATUS_FAILED: string = 'failed';
export const RUN_STATUS_STOPPED: string = 'stopped';
export const RUN_STATUS_INTERRUPTED: string = 'interrupted';
// ★ 域⑤ 非终态停留态：awaiting_input = run 停在 ask_user 等用户作答（等待行在场，见
// commitRunUnit.runStatus 与 ChatAskResumeCtrl）。**不进终态白名单**（isRunFinalStatus
// 四值不动——本值不经 finishRun 入参；对停留态行的收口走 finishRun 终态谓词天然放行：
// 谓词只排终态四值，awaiting_input 不被排除，收口语义正确）；**sweep 豁免**
//（sweepStaleGraphRuns 候选集仍 prepared/running 两值，本值天然不入选；残留 streaming
// 兜底段对等待行显式豁免——等待用户输入无超时语义，可无限期保留）。显示面登记：
// mapTraceRunStatus / SessionTraceModel.traceRunStatusOf 均映射「进行中」（等待中的轮是
// 活跃轮：可作答、答后续跑同一 run，不伪报中断）。
export const RUN_STATUS_AWAITING_INPUT: string = 'awaiting_input';
// 工具事实四态机（tool_facts.state；J10：派发前先提交意图；恢复无确认结果的
// dispatch_intent =「执行结果未知」——该状态**原地保留**，不自动重放、不自动迁移）
export const TOOL_FACT_PREPARED: string = 'prepared';
export const TOOL_FACT_DISPATCH_INTENT: string = 'dispatch_intent';
export const TOOL_FACT_RESULT_CONFIRMED: string = 'result_confirmed';
export const TOOL_FACT_FAILED: string = 'failed';
// 节点来源语义（messages.origin；'' = legacy/未标）
export const ORIGIN_SEND: string = 'send';
export const ORIGIN_RETRY: string = 'retry';
export const ORIGIN_FORK: string = 'fork';
export const ORIGIN_IMPORT: string = 'import';
export const ORIGIN_FINISH_DIAG: string = 'finish_diag';
// 工具卡重发：重发自持 mini-run（无 user 节点，prepareRun 空输入形态）落 assistant 空正文
// 宿主行 + tool 结果节点两节点。origin 列为纯登记列（消费方 GraphTransfer /
// ConversationForkCopy 只透传无判据），扩值零行为面。★ F1 修复：prepareRun 的 origin 入参
// 只写 user 节点，空输入形态不建 user 节点 ⇒ 登记值死写不落库——CommitUnitInput 增 origin
// 字段（输出节点按调用方语义落列：轮内/主动消息 ORIGIN_SEND，重发 ORIGIN_RESEND），登记
// 面才成立
export const ORIGIN_RESEND: string = 'resend';
// 历史助手编辑：编辑版 assistant 节点（无 run 纯文本，命令 =
// GraphEditFork.editAssistantFork 单事务分叉落库）——纯登记列，扩值零行为面
export const ORIGIN_EDIT_ASSISTANT: string = 'edit_assistant';
// 历史提问编辑：编辑版 user 节点（无 run 纯文本，命令 = GraphEditFork.editUserFork 单事务
// 分叉落库）——纯登记列，扩值零行为面。与助手编辑的分野 = role 不同（提问/回复变体），
// 各自成组切换
export const ORIGIN_EDIT_USER: string = 'edit_user';
// 会话格式态词表（conversations.migrateState；冻结为**两值**）——'graph' = 现值格式（新建
// 即 graph，读写走图路径）；'legacy' = 旧格式**墓碑**（本版本不再支持打开，页面呈墓碑覆盖
// 层，数据留本机由用户长按删除）。词表值 'legacy' 是 DB 态词（C 类不可删——存量旧库全部
// 行都是该值，导入的旧备份行原样携带）。**非 graph 即墓碑**是唯一判据（含历史 'migrating'
// 残值与任何脏值——判读处一律 `!== CONV_STATE_GRAPH`，见
// ChatContextSource.conversationWritableRoute）
export const CONV_STATE_LEGACY: string = 'legacy';
export const CONV_STATE_GRAPH: string = 'graph';
// 图能力级（graph_capability.level；读侧与守卫 = ChatDbMigrate.readGraphCapabilityLevel）
export const GRAPH_LEVEL_NONE: number = 0;
export const GRAPH_LEVEL_SCHEMA_READY: number = 1;
export const GRAPH_LEVEL_ENABLED: number = 2;

// ── 纯函数（断言直跑面；顶层零外部绑定求值——坑50）──

// 图节点引用（校验与可达性计算的轻行；parentMessageId null = 根）
export interface GraphNodeRef {
  id: string;
  conversationId: string;
  parentMessageId: string | null;
}

// 图插入校验（J10 冻结——forkBranch / 图导入 / 任何图侧节点落库前的唯一校验口）：
// ①归属——候选节点 conversationId 必须与父节点一致（跨会话引用拒绝）；②父链——
// parentMessageId 非 null 时父节点必须已在既有集（悬边拒绝）；③环——从候选沿父链上溯
//（有界 = 既有集规模 +1）不得回到候选自身。返回 null = 通过；中文错误串 = 拒绝理由
//（调用方原样上抛，P0-1 不静默）。判据是关系判定非值抄本
export function validateGraphInsertion(candidate: GraphNodeRef,
  existing: Map<string, GraphNodeRef>): string | null {
  if (candidate.parentMessageId === null) {
    return null; // 根节点：无父可校验（环不可能——零边）
  }
  const parent = existing.get(candidate.parentMessageId);
  if (parent === undefined) {
    return '父节点 ' + candidate.parentMessageId + ' 不在既有节点集中（悬边）';
  }
  if (parent.conversationId !== candidate.conversationId) {
    return '跨会话引用：候选属 ' + candidate.conversationId + ' 而父节点属 ' +
      parent.conversationId;
  }
  // 环检测：沿父链上溯，步数上限 = 集合规模 + 1（健康链最多走全集步；若途中回到候选
  // 即成环；超限 = 链中已有环，同样拒绝——带环图任何插入都是污染）
  let cursor: string | null = candidate.parentMessageId;
  let steps: number = 0;
  const bound: number = existing.size + 1;
  while (cursor !== null) {
    if (cursor === candidate.id) {
      return '检测到环：候选节点 ' + candidate.id + ' 出现在自身父链上';
    }
    steps++;
    if (steps > bound) {
      return '父链步数超过节点集规模，既有图已含环，拒绝插入';
    }
    const next = existing.get(cursor);
    cursor = next !== undefined ? next.parentMessageId : null;
    if (next === undefined && cursor === null && steps <= bound) {
      break; // 链到根正常终止
    }
  }
  return null;
}

// 从节点沿父链上溯的祖先链（含自身；有界 = maxDepth——环态防死循环，调用方传既有集
// 规模）。★ 悬边即断（C1）：沿链任一步查不到节点立即停止，**幽灵 id 不入链**——与
// ChatContextSource.reachableIdsOf「查不到即断」同口径（原实现先 push 后查，悬边时幽灵
// id 并入返回链，forkBranch / deleteBranchSubtree 的「fork 点必须在路径上」校验被已删
// 节点 id 通过）。供存活集计算与 forkBranch 复用
export function traceAncestorChain(nodeId: string, nodes: Map<string, GraphNodeRef>,
  maxDepth: number): string[] {
  const chain: string[] = [];
  let cursor: string | null = nodeId;
  let steps: number = 0;
  while (cursor !== null && steps <= maxDepth) {
    const node: GraphNodeRef | undefined = nodes.get(cursor);
    if (node === undefined) {
      break; // 悬边防御：查不到即断（幽灵 id 不入链——先判存在再收）
    }
    chain.push(cursor);
    cursor = node.parentMessageId;
    steps++;
  }
  return chain;
}

// 工具事实四态机合法迁移表（纯函数——J10 冻结）：prepared → dispatch_intent | failed；
// dispatch_intent → result_confirmed | failed；终态恒 false。「恢复无确认结果的
// dispatch_intent = 执行结果未知」落在**不迁移**上：任何向 result_confirmed 的自动迁移
// 都非法（防自动重放副作用）。表是唯一真源——调用方（recordToolFact）机械查表
export function canTransitionToolFact(from: string, to: string): boolean {
  if (from === TOOL_FACT_PREPARED) {
    return to === TOOL_FACT_DISPATCH_INTENT || to === TOOL_FACT_FAILED;
  }
  if (from === TOOL_FACT_DISPATCH_INTENT) {
    return to === TOOL_FACT_RESULT_CONFIRMED || to === TOOL_FACT_FAILED;
  }
  return false;
}

// 会话格式态无三态机（墓碑笔）：原 legacy→migrating→graph 迁移表随迁移发布协议
//（publishConversationMigration）整件退役——新会话出生即 graph
//（ChatContextSource.bornGraphConversation 单事务），旧格式行恒为墓碑，无合法态迁移边。

// ── 行类型（图侧投影）──

export interface BranchRow {
  id: string;
  conversationId: string;
  parentBranchId: string | null;
  headMessageId: string | null;
  name: string;
  createdAt: number;
}

export interface GraphRunRow {
  id: string; // = runId（笔1 词表外部身份）
  conversationId: string;
  branchId: string;
  attemptEpoch: number;
  inputAnchorMessageId: string;
  revision: number;
  status: string;
  checkpoint: string;
  diagnosticMessageId: string;
  createdAt: number;
  updatedAt: number;
}

export interface ToolFactRow {
  id: string;
  runId: string;
  attemptId: string;
  name: string;
  state: string;
  payload: string;
  result: string;
  createdAt: number;
  finishedAt: number; // v54 终态时刻毫秒（0 = 无终态时刻；写点唯一 = recordToolFact）
}

export interface GraphPathRow {
  // messages 行的图侧读投影（正文仍在 messages——readPathPage 沿父链读的就是它）
  id: string;
  conversationId: string;
  role: string;
  content: string;
  reasoning: string;
  status: string;
  createdAt: number;
  parentMessageId: string | null;
  runId: string;
  ownerAssistantId: string;
  stepIndex: number | null;
  origin: string;
}

// ── DB 命令层（句柄入参；短事务对象 IMMEDIATE——见头注释事务纪律）──

// 图节点行读投影构造（readPathPage 与 GraphTransfer.exportConversationGraph 共用——
// 导出防两份行映射漂移）
export function graphPathRowFromResult(result: relationalStore.ResultSet): GraphPathRow {
  const parentIdx: number = result.getColumnIndex('parentMessageId');
  const stepIdx: number = result.getColumnIndex('stepIndex');
  const row: GraphPathRow = {
    id: result.getString(result.getColumnIndex('id')),
    conversationId: result.getString(result.getColumnIndex('conversationId')),
    role: result.getString(result.getColumnIndex('role')),
    content: result.getString(result.getColumnIndex('content')),
    reasoning: result.getString(result.getColumnIndex('reasoning')),
    status: result.getString(result.getColumnIndex('status')),
    createdAt: result.getLong(result.getColumnIndex('createdAt')),
    parentMessageId: result.isColumnNull(parentIdx) ? null
      : result.getString(parentIdx),
    runId: result.getString(result.getColumnIndex('runId')),
    ownerAssistantId: result.getString(result.getColumnIndex('ownerAssistantId')),
    stepIndex: result.isColumnNull(stepIdx) ? null : result.getLong(stepIdx),
    origin: result.getString(result.getColumnIndex('origin'))
  };
  return row;
}

// 取分支行（不存在回 null——调用方守卫）
export async function queryBranch(db: relationalStore.RdbStore,
  branchId: string): Promise<BranchRow | null> {
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT id, conversationId, parentBranchId, headMessageId, name, createdAt ' +
    'FROM branches WHERE id = ?', [branchId]);
  try {
    if (!result.goToNextRow()) {
      return null;
    }
    const parentIdx: number = result.getColumnIndex('parentBranchId');
    const headIdx: number = result.getColumnIndex('headMessageId');
    const row: BranchRow = {
      id: result.getString(result.getColumnIndex('id')),
      conversationId: result.getString(result.getColumnIndex('conversationId')),
      parentBranchId: result.isColumnNull(parentIdx) ? null : result.getString(parentIdx),
      headMessageId: result.isColumnNull(headIdx) ? null : result.getString(headIdx),
      name: result.getString(result.getColumnIndex('name')),
      createdAt: result.getLong(result.getColumnIndex('createdAt'))
    };
    return row;
  } finally {
    result.close();
  }
}

// run 行读口（prepareRun/finishRun 的守卫查询共用——单一投影防两处漂移）
async function queryRunRow(db: relationalStore.RdbStore,
  runId: string): Promise<GraphRunRow | null> {
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT id, conversationId, branchId, attemptEpoch, inputAnchorMessageId, revision, ' +
    'status, checkpoint, diagnosticMessageId, createdAt, updatedAt FROM generation_runs ' +
    'WHERE id = ?', [runId]);
  try {
    if (!result.goToNextRow()) {
      return null;
    }
    const row: GraphRunRow = {
      id: result.getString(result.getColumnIndex('id')),
      conversationId: result.getString(result.getColumnIndex('conversationId')),
      branchId: result.getString(result.getColumnIndex('branchId')),
      attemptEpoch: result.getLong(result.getColumnIndex('attemptEpoch')),
      inputAnchorMessageId: result.getString(result.getColumnIndex('inputAnchorMessageId')),
      revision: result.getLong(result.getColumnIndex('revision')),
      status: result.getString(result.getColumnIndex('status')),
      checkpoint: result.getString(result.getColumnIndex('checkpoint')),
      diagnosticMessageId: result.getString(result.getColumnIndex('diagnosticMessageId')),
      createdAt: result.getLong(result.getColumnIndex('createdAt')),
      updatedAt: result.getLong(result.getColumnIndex('updatedAt'))
    };
    return row;
  } finally {
    result.close();
  }
}

// prepareRun（J6/J10——准备原子保存输入/run，成功才允许发网络；准备失败不具备开流资格
// W10）：IMMEDIATE 对象事务内一次完成——①校验分支在场且属同会话；②插 user 输入锚点
// 节点（parent = 分支当前 head，stepIndex 0）；③分支 head 前移；④插 run 行（prepared，
// revision 0）。任一步失败整体回滚并上抛（不半准备）。runId 由调用方传入（外部身份，
// 见头注释身份纪律），重复 prepare 同一 runId = 主键冲突抛错（天然防重）。
// ★ v57 排队出队原子：queueItemId 非空时**同事务** DELETE send_queue_items WHERE id = ?
//——出队删行与 user 消息行 + run 行同一次提交。崩溃两分支：提交前 = 行在 + user 事实
// 未落 → 重启 hydrate 重投（不丢不重）；提交后 = 行删 + user 事实在 →
// sweepStaleGraphRuns 既有链收口。库中永无 inFlight 歧义行（不预写状态，hydrate 零清标志
//）。'' = 手动/重试路径逐字零变化（本行是唯一出队删行实现点，禁调用方自拼写）
export interface PrepareRunInput {
  runId: string;
  conversationId: string;
  branchId: string;
  assistantId: string;
  userContent: string;
  origin: string;
  now: number; // 时钟由调用方注入（隔离库夹具确定性；生产传 Date.now()）
  // 排队条目 id（★ Q3 新增可选位）：非空 = 本轮由队列出队派发——事务内同删该排队行；
  // 缺省 undefined = 手动/重试/主动消息路径（零删行面）
  queueItemId?: string;
  // 引用全文快照（v61，user 行专用）：非空 = user 节点 bucket 条件写键 quote_text 列；
  // 缺省 undefined 或 '' = 不写键（列落 NULL = 无引用）——既有调用不带本字段，行为逐字零
  // 变化。content 恒存用户原文，引用前缀在组装层拼装
  quoteText?: string;
}

export interface PreparedRun {
  runId: string;
  userNodeId: string;
  revision: number;
}

export async function prepareRun(db: relationalStore.RdbStore,
  input: PrepareRunInput): Promise<PreparedRun> {
  const branch: BranchRow | null = await queryBranch(db, input.branchId);
  if (branch === null) {
    throw new Error('prepareRun 失败：分支 ' + input.branchId + ' 不存在');
  }
  if (branch.conversationId !== input.conversationId) {
    throw new Error('prepareRun 失败：分支归属会话 ' + branch.conversationId +
      ' 与目标会话 ' + input.conversationId + ' 不一致');
  }
  // ★「无用户输入形态」：userContent = '' 时**不建 user 节点、head 不前移**——run 的输入
  //   锚 = 提交时分支 head（空分支首 run 即 null 语义，落 inputAnchorMessageId = ''）。
  //   唯一消费方 = 主动消息（ProactiveGen——会话首条消息是 assistant，无用户提问可锚）。
  //   commitRunUnit 的输出节点 parent 取提交时 head，空 head = 根节点，链形态正确
  // ★ 写串行链入链（14800024 收口）：IMMEDIATE 事务段入全局写队列——与旧式
  // beginTransaction 族同链排队，跨 API 撞锁机制性消失；前置读段（queryBranch）留链外
  return runWriteQueued('prepareRun', async (): Promise<PreparedRun> => {
    const tx: relationalStore.Transaction =
      await db.createTransaction({ transactionType: relationalStore.TransactionType.IMMEDIATE });
    try {
      let userNodeId: string = '';
      if (input.userContent !== '') {
        userNodeId = nextMessageId('msg');
        const nodeBucket: relationalStore.ValuesBucket = {
          'id': userNodeId,
          'conversationId': input.conversationId,
          'role': 'user',
          'content': input.userContent,
          'reasoning': '',
          'status': 'done',
          'createdAt': input.now,
          'variants': '',
          'variant_active': 0,
          'parentMessageId': branch.headMessageId, // 根分支首节点 = null（head 可空语义）
          'runId': input.runId,
          'ownerAssistantId': input.assistantId,
          'stepIndex': 0,
          // seq（K12 登记口径）：图会话节点的会话内入链单调序号——写入侧分配器铸造
          //（与 legacy 写入点同源 MessageSeqDb.nextRowSeq）。不是图路径排序真源（图排序
          // 真源 = parent 链），而是 summary_bindings 的 seq 区间语义与启动补号幂等（有号
          // 不补＝对 graph 会话零触碰）的前提。事务内铸造＝IMMEDIATE 单写串行化保证单调
          'seq': nextRowSeq(input.conversationId),
          'origin': input.origin
        };
        // v61 引用快照条件写键：不写键 = 列落 NULL = 无引用（'' 不落库）
        if (input.quoteText !== undefined && input.quoteText !== '') {
          nodeBucket['quote_text'] = input.quoteText;
        }
        await tx.insert('messages', nodeBucket);
        const headBucket: relationalStore.ValuesBucket = { 'headMessageId': userNodeId };
        const headPredicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('branches');
        headPredicates.equalTo('id', input.branchId);
        await tx.update(headBucket, headPredicates);
      }
      const runBucket: relationalStore.ValuesBucket = {
        'id': input.runId,
        'conversationId': input.conversationId,
        'branchId': input.branchId,
        'attemptEpoch': 1,
        'inputAnchorMessageId': userNodeId,
        'revision': 0,
        'status': RUN_STATUS_PREPARED,
        'checkpoint': '',
        'diagnosticMessageId': '',
        'createdAt': input.now,
        'updatedAt': input.now
      };
      await tx.insert('generation_runs', runBucket);
      // ★ v57 排队出队原子：排队行删除与 user 行 + run 行同事务提交——queueItemId 非空
      // 才删；0 行命中 = 该行已因用户删除/级联删而离场（幂等无害）；位次紧邻 commit（读序清晰）
      const queueItemId: string = input.queueItemId !== undefined ? input.queueItemId : '';
      if (queueItemId !== '') {
        await tx.execute(SQL_DELETE_SEND_QUEUE_ITEM, [queueItemId]);
      }
      await tx.commit();
      return { runId: input.runId, userNodeId: userNodeId, revision: 0 };
    } catch (e) {
      await tx.rollback();
      throw e as Error;
    }
  });
}

// 消息行流式态（messages.status；解耦笔2 新增词表值）：'streaming' = 流中 assistant 占位
// 行（beginStreamRound 轮落库、250ms checkpoint 增量覆写、收口 UPDATE 升级 done）；既有
// 'done'/'error' 字面写点不回刷（词表只约束新写面）。启动清算判据（图态 streaming 行归
// sweepStaleGraphRuns、非图态残行归 markStreamingAsError）以此值为界
export const MSG_STATUS_STREAMING: string = 'streaming';

// commitRunUnit（J6——封存校验 revision 与 affected rows 且幂等；失败/取消只推进完整
// 交换检查点）：CAS 形态——WHERE id = ? AND revision = ? 命中才推进（revision+1），
// affected = 0 即并发冲突（I2 占用拒绝同源）返 false 由调用方处置；命中则原子写新检查点
// 并可选追加本轮输出节点（stepIndex 递增）。
// ★ 占位行机制两字段（解耦笔2）：
// · nodeStatus——插行时 status 落值：'done' = 既有终态语义（工具结果行/中间轮行/重发件，
//   既有调用零变化）；'streaming' = 流中 assistant 占位行（收口经 updateNodeId 路径升级
//   done）。值域外字面由调用方自律（词表 MSG_STATUS_STREAMING / 既有 'done'）。
// · updateNodeId——'' = 插新行（既有语义）；非空 = **更新既有占位行**（终态收口）：不插
//   行、不前移 head（head 已在占位行上），单行 UPDATE 终值 content/reasoning +
//   status='done'，谓词带 status='streaming'（防迟到复活守卫——占位行已收口/被清扫后，
//   迟到收口 affected=0 回滚返 false，与 CAS 冲突同型由调用方处置）。与 CAS 推进同一事务
//  （原子性不降级）。
export interface CommitUnitOutput {
  content: string;
  reasoning: string;
  role: string;
  stepIndex: number;
  nodeStatus: string;
  updateNodeId: string;
  // ★ 域⑤ 可选字段：本次提交后 run 的**停留态**——'' / 缺省 = RUN_STATUS_RUNNING（既有
  // 语义逐字不变：CAS UPDATE 恒写回 running）；非空 = 等待行落库专用值
  // RUN_STATUS_AWAITING_INPUT（ask 挂起时等待行与 run 停留态同一 CAS 事务原子落定，消灭
  //「插行与状态翻转分两写」的中断窗口）。显式传入面 = ChatGraphCommandSource
  // graphCommitNode 第三组可选参（生产调用恒显式）。
  runStatus?: string;
}

export interface CommitUnitInput {
  runId: string;
  expectedRevision: number;
  checkpoint: string;
  output: CommitUnitOutput | null;
  now: number;
  // 输出节点 origin 登记值（★ F1 修复——原列值硬编码 ORIGIN_SEND，空输入形态 run 的
  // origin 入参无处落；字段化后轮内/主动消息传 ORIGIN_SEND 零变化，重发传 ORIGIN_RESEND）
  origin: string;
}

export async function commitRunUnit(db: relationalStore.RdbStore,
  input: CommitUnitInput): Promise<boolean> {
  const run: GraphRunRow | null = await queryRunRow(db, input.runId);
  if (run === null) {
    throw new Error('commitRunUnit 失败：run ' + input.runId + ' 不存在');
  }
  if (run.revision !== input.expectedRevision) {
    return false; // revision 冲突（预期拒绝路径，非异常）
  }
  // ★ 写串行链入链（撞锁当事方之一）；revision 读段留链外，CAS 事务内复核（affected 谓词）
  // 继续兜排队等待期间的推进
  return runWriteQueued('commitRunUnit', async (): Promise<boolean> => {
    const tx: relationalStore.Transaction =
      await db.createTransaction({ transactionType: relationalStore.TransactionType.IMMEDIATE });
    try {
      let outputNodeId: string = '';
      if (input.output !== null && input.output.updateNodeId !== '') {
        // ★ 占位行更新路径（终态收口）：UPDATE 既有 streaming 占位行为终值 done——不插行、
        // 不前移 head、不动 seq/createdAt/origin（占位行落库时已定）。谓词带
        // status='streaming'（防迟到复活守卫，域②）：占位行已收口（前一笔收口/启动清扫）
        // 后迟到收口 affected=0 回滚返 false——半截正文已保全在库里，不双写
        const settleBucket: relationalStore.ValuesBucket = {
          'content': input.output.content,
          'reasoning': input.output.reasoning,
          'status': 'done'
        };
        const settlePredicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('messages');
        settlePredicates.equalTo('id', input.output.updateNodeId);
        settlePredicates.equalTo('status', MSG_STATUS_STREAMING);
        const settled: number = await tx.update(settleBucket, settlePredicates);
        if (settled !== 1) {
          await tx.rollback();
          return false; // 占位行已非 streaming（迟到收口）——与 CAS 冲突同型的预期拒绝路径
        }
        outputNodeId = input.output.updateNodeId;
      } else if (input.output !== null) {
        // ★ K12：输出节点 parent = **提交时刻的分支 head**（事务内读）。prepareRun 已把
        // head 前移到输入锚点 ⇒ 单提交形态与原「parent = 输入锚点」逐字节等价；多轮提交
        // 形态（工具续轮逐次 commitRunUnit）修原实现的结构缺陷——原实现多次提交全部挂输入
        // 锚点成兄弟节点，链上只剩最后一次提交（前几轮输出从 head 不可达 = 退出重进丢中间
        // 轮）。现按 head 链式成链：锚 → A1 → 工具 → A2 → …。签名与返回语义零变化。
        const headResult: relationalStore.ResultSet = await tx.querySql(
          'SELECT headMessageId FROM branches WHERE id = ?', [run.branchId]);
        let parentForOutput: string | null = run.inputAnchorMessageId;
        try {
          if (headResult.goToNextRow()) {
            const headIdx: number = headResult.getColumnIndex('headMessageId');
            parentForOutput = headResult.isColumnNull(headIdx) ? null
              : headResult.getString(headIdx);
          }
        } finally {
          headResult.close();
        }
        outputNodeId = nextMessageId('msg');
        const nodeBucket: relationalStore.ValuesBucket = {
          'id': outputNodeId,
          'conversationId': run.conversationId,
          'role': input.output.role,
          'content': input.output.content,
          'reasoning': input.output.reasoning,
          // ★ 参数化：占位行落 'streaming'（词表 MSG_STATUS_STREAMING），既有调用恒
          // 'done' 零变化——输出行插入点/user 行/诊断 notice 行三处点位中仅此处参数化
          //（另两处维持 done 硬编码，域②协调面）
          'status': input.output.nodeStatus,
          'createdAt': input.now,
          'variants': '',
          'variant_active': 0,
          'parentMessageId': parentForOutput,
          'runId': input.runId,
          'ownerAssistantId': '',
          'stepIndex': input.output.stepIndex,
          // seq 同 prepareRun 用户节点（图会话入链单调序号；事务内铸造＝单写串行化保证单调）
          'seq': nextRowSeq(run.conversationId),
          'origin': input.origin
        };
        await tx.insert('messages', nodeBucket);
        const headBucket: relationalStore.ValuesBucket = { 'headMessageId': outputNodeId };
        const headPredicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('branches');
        headPredicates.equalTo('id', run.branchId);
        await tx.update(headBucket, headPredicates);
      }
      // CAS 推进（affected 校验在事务内复核——读与写之间可能有并发写者，d.ts 14800024
      // 单写事务约束下同库另一 IMMEDIATE 必先被挡，此处二次守卫为 fail-safe）
      // ★ 域⑤：status 写值参数化——缺省 RUN_STATUS_RUNNING（既有语义），等待行落库传
      // RUN_STATUS_AWAITING_INPUT（见 CommitUnitOutput.runStatus 注释）
      const commitRunStatus: string =
        input.output !== null && input.output.runStatus !== undefined &&
          input.output.runStatus !== '' ? input.output.runStatus : RUN_STATUS_RUNNING;
      const updateSql: string = input.output !== null
        ? 'UPDATE generation_runs SET revision = revision + 1, checkpoint = ?, status = ?, ' +
        'updatedAt = ? WHERE id = ? AND revision = ?'
        : 'UPDATE generation_runs SET revision = revision + 1, checkpoint = ?, updatedAt = ? ' +
        'WHERE id = ? AND revision = ?';
      const args: Array<string | number> = input.output !== null
        ? [input.checkpoint, commitRunStatus, input.now, input.runId, input.expectedRevision]
        : [input.checkpoint, input.now, input.runId, input.expectedRevision];
      const affected: number = await tx.execute(updateSql, args) as number;
      if (affected !== 1) {
        await tx.rollback();
        return false;
      }
      await tx.commit();
      return true;
    } catch (e) {
      await tx.rollback();
      throw e as Error;
    }
  });
}

// 流中占位行 checkpoint 单行写（★ 解耦笔2 新增——kelivo 范式 250ms latest-wins 节流的
// 库侧命令）：覆写该行 content/reasoning 全量（单行 UPDATE，写放大可控——先落码后真机
// Profiler 实测，卡顿再调间隔）。**防迟到复活守卫**（域② 核心）：谓词带
// status='streaming'——行已收口 done（finishStream/settle/启动清扫任一先到）后迟到的
// checkpoint 快照 affected=0 返 false，调用方（ChatStreamCheckpoint 域）丢弃不重试——
// 终态行不得被旧快照覆盖复活。latest-wins 串行排水在调用方（域件），本命令不排队不合并；
// 单语句原子不开显式事务；入全局写串行链（与占位行落库/收口同链，防 14800024 撞锁）
export interface StreamCheckpointInput {
  nodeId: string;
  content: string;
  reasoning: string;
}

export async function updateStreamingNodeCheckpoint(db: relationalStore.RdbStore,
  input: StreamCheckpointInput): Promise<boolean> {
  return runWriteQueued('updateStreamingNodeCheckpoint', async (): Promise<boolean> => {
    const bucket: relationalStore.ValuesBucket = {
      'content': input.content,
      'reasoning': input.reasoning
    };
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('messages');
    predicates.equalTo('id', input.nodeId);
    predicates.equalTo('status', MSG_STATUS_STREAMING);
    const affected: number = await db.update(bucket, predicates);
    return affected === 1;
  });
}

// server_tools 列条件写键（DB v64，2026-11-14 DS 全家桶接入批 S2；assistant 行专用——
// DeepSeek 服务端工具原样 JSON 串，列义与消费面见 ChatDbMigrate v64 版本注释 + ChatDbSchema
// 建表串注释）。★ 形态说明（照 prepareRun quoteText bucket 条件写键先例的「图输入条件写键」
// 语义，落点差异如实登记）：user 行的 quote_text 走 prepareRun 插入 bucket；assistant 节点的
// 插入 bucket 在 commitRunUnit，其 CommitUnitOutput 组装点（graphCommitNode，
// ChatGraphCommandSource）不在本批 S2 白名单——故本列走「提交成功后按节点 id 补列 UPDATE」
// 形态：调用点 = ChatGraphWriteCtrl 终答（GraphFinishInput.serverTools）与中间轮（提交口从
// stampTarget.serverToolsJson 读）两处 ref 到达段，CAS 成功才有 ref（冲突/失败天然不写）；
// insert 与「更新既有占位行」两路径统一按 ref.nodeId 补列（UPDATE 不改 seq，回读锚即本节点）。
// '' = 不写键（列落 NULL）；既有调用不带本口，行为逐字零变化。与 touchConversationUpdatedAt
// 同款「提交后伴随写」先例——失败由调用方 hilog 留痕不阻断轮收尾
export interface NodeServerToolsInput {
  nodeId: string;
  serverToolsJson: string; // 原样 JSON 串（回传保真——禁截断禁重排）；'' = 零动作
}

export async function writeNodeServerTools(db: relationalStore.RdbStore,
  input: NodeServerToolsInput): Promise<boolean> {
  if (input.serverToolsJson === '') {
    return false; // 无服务端步骤 = 不写键（列落 NULL），零 DB 往返
  }
  return runWriteQueued('writeNodeServerTools', async (): Promise<boolean> => {
    const bucket: relationalStore.ValuesBucket = { 'server_tools': input.serverToolsJson };
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('messages');
    predicates.equalTo('id', input.nodeId);
    const affected: number = await db.update(bucket, predicates);
    return affected === 1;
  });
}

// recordToolFact（J10 工具事实四态机落库——派发前先提交意图）：状态迁移经
// canTransitionToolFact 机械查表，非法迁移抛错（不静默改写）；已终态行再推进 = 非法
//（防重复确认/重复失败）。新事实（factId 空串）按 prepared 建行。★ v54：finishedAt 打戳
//——新建显式落 0（不靠 DEFAULT，便于断言直视）；终态推进（result_confirmed / failed）
// 同址打 input.now；dispatch_intent 推进不动该列
export interface ToolFactInput {
  factId: string; // '' = 新建（本域铸 id）；非空 = 既有事实状态推进
  runId: string;
  attemptId: string;
  name: string;
  toState: string;
  payload: string; // 新建时落 payload；推进时非空则更新
  result: string;  // 迁往 result_confirmed 时必填（无结果的确认 = 空串合法但须显式传 ''）
  now: number;
}

export async function recordToolFact(db: relationalStore.RdbStore,
  input: ToolFactInput): Promise<string> {
  // ★ 写串行链入链
  return runWriteQueued('recordToolFact', async (): Promise<string> => {
    const tx: relationalStore.Transaction =
      await db.createTransaction({ transactionType: relationalStore.TransactionType.IMMEDIATE });
    try {
      let factId: string = input.factId;
      if (factId === '') {
        // 新建：只允许落到 prepared（意图先于派发——dispatch_intent 必须是第二次写入，
        // 保证「派发前先提交意图」的先写后发次序可审计）
        if (input.toState !== TOOL_FACT_PREPARED) {
          // ★ LB-1：早退支不再先行 rollback——下方 catch 统一回滚（原「先 rollback 再
          // throw」+ catch 再 rollback = 同事务二次回滚；与 commitRunUnit/finishRun 早退
          // 同批收口）
          throw new Error('工具事实新建只允许 prepared 态，收到 ' + input.toState);
        }
        factId = nextMessageId('tf');
        const bucket: relationalStore.ValuesBucket = {
          'id': factId,
          'runId': input.runId,
          'attemptId': input.attemptId,
          'name': input.name,
          'state': TOOL_FACT_PREPARED,
          'payload': input.payload,
          'result': '',
          'createdAt': input.now,
          'finishedAt': 0 // v54：未终态 = 0（显式落值，不靠建表 DEFAULT）
        };
        await tx.insert('tool_facts', bucket);
        await tx.commit();
        return factId;
      }
      // 既有事实推进：读现态 → 查表
      const existing: relationalStore.ResultSet = await tx.querySql(
        'SELECT state FROM tool_facts WHERE id = ?', [factId]);
      let fromState: string = '';
      try {
        if (!existing.goToNextRow()) {
          throw new Error('工具事实 ' + factId + ' 不存在'); // 回滚归下方 catch（LB-1 同批）
        }
        fromState = existing.getString(existing.getColumnIndex('state'));
      } finally {
        existing.close();
      }
      if (!canTransitionToolFact(fromState, input.toState)) {
        throw new Error('工具事实非法迁移：' + fromState + ' → ' + input.toState); // 回滚归 catch
      }
      const bucket: relationalStore.ValuesBucket = { 'state': input.toState };
      if (input.payload !== '') {
        bucket['payload'] = input.payload;
      }
      if (input.toState === TOOL_FACT_RESULT_CONFIRMED || input.toState === TOOL_FACT_FAILED) {
        bucket['result'] = input.result;
        bucket['finishedAt'] = input.now; // v54：终态时刻打戳（dispatch_intent 不动该列）
      }
      const predicates: relationalStore.RdbPredicates =
        new relationalStore.RdbPredicates('tool_facts');
      predicates.equalTo('id', factId);
      await tx.update(bucket, predicates);
      await tx.commit();
      return factId;
    } catch (e) {
      await tx.rollback();
      throw e as Error;
    }
  });
}

// finishRun（J6 幂等终态——W11 重复 finish 不重复节点/账本）：已终态（域① 起四终态
// finished/failed/stopped/interrupted）直接返回 false 零改动（事务外快照）；写事务内以
// 终态谓词复核 affected 兜并发窗口（S10②）——否则事务内置终态 + 可选插诊断节点
//（role='notice'——与现役 notice 提示条同角色，不入统计/检索/请求组装面；origin=
// finish_diag）并挂 diagnosticMessageId；谓词未命中（并发者已终结）回滚返 false。★ 订正
// LB-4③：诊断节点挂输入锚（与终答节点互为兄弟——不在 head 起算的读路径上，'notice' 现无
// 读口消费），实际仅供 run 追溯；进读面与否属产品口径（登记 BLOCKED 待拍板）
export interface FinishRunInput {
  runId: string;
  finalStatus: string; // RUN_STATUS_FINISHED | FAILED | STOPPED | INTERRUPTED（域① 起四终态）
  diagnosticContent: string; // '' = 不插诊断节点
  now: number;
}

// 终态白名单与终态集单源（域① 扩三态后三处消费：入参校验 / 幂等出口 / UPDATE 终态谓词）
function isRunFinalStatus(status: string): boolean {
  return status === RUN_STATUS_FINISHED || status === RUN_STATUS_FAILED ||
    status === RUN_STATUS_STOPPED || status === RUN_STATUS_INTERRUPTED;
}

export async function finishRun(db: relationalStore.RdbStore,
  input: FinishRunInput): Promise<boolean> {
  if (!isRunFinalStatus(input.finalStatus)) {
    throw new Error('finishRun 终态只允许 finished/failed/stopped/interrupted，收到 ' +
      input.finalStatus);
  }
  const run: GraphRunRow | null = await queryRunRow(db, input.runId);
  if (run === null) {
    throw new Error('finishRun 失败：run ' + input.runId + ' 不存在');
  }
  if (isRunFinalStatus(run.status)) {
    return false; // 幂等出口：重复 finish 零改动（域① 起四终态皆终态——stopped 后迟到
    // failed 收口不覆盖、诊断节点不双插）
  }
  // ★ 写串行链入链（终态快照读段留链外，终态谓词复核在事务内兜排队窗口）
  return runWriteQueued('finishRun', async (): Promise<boolean> => {
    const tx: relationalStore.Transaction =
      await db.createTransaction({ transactionType: relationalStore.TransactionType.IMMEDIATE });
    try {
      let diagnosticId: string = run.diagnosticMessageId;
      if (input.diagnosticContent !== '' && diagnosticId === '') {
        diagnosticId = nextMessageId('msg');
        const nodeBucket: relationalStore.ValuesBucket = {
          'id': diagnosticId,
          'conversationId': run.conversationId,
          'role': 'notice',
          'content': input.diagnosticContent,
          'reasoning': '',
          'status': 'done',
          'createdAt': input.now,
          'variants': '',
          'variant_active': 0,
          // ★ LB-4②：空锚 run（无用户输入形态，锚 = ''）父落 NULL——原样写空串 = 非
          // NULL 空悬边（validateGraphInsertion 判悬边拒绝的形态），会让该会话图域备份
          // 导入被整会话拒收
          'parentMessageId': run.inputAnchorMessageId === '' ? null : run.inputAnchorMessageId,
          'runId': input.runId,
          'ownerAssistantId': '',
          'stepIndex': null,
          // ★ LB-4①：补 seq（原为全部图节点写入点唯一一枚不带 seq 的——落 NULL 且
          // graph 会话被启动补号排除 = 永久无号；铸造同 prepareRun/commitRunUnit 口径，
          // 事务内串行单调）
          'seq': nextRowSeq(run.conversationId),
          'origin': ORIGIN_FINISH_DIAG
        };
        await tx.insert('messages', nodeBucket);
      }
      // ★ S10②：终态谓词进 SQL 并复核 affected 行数。上方幂等出口读的是**事务外**快照
      //（queryRunRow），读与写之间另一并发终态调用（finishStream 与 disposeSilent 竞态）
      // 可能已把行置终态；原 UPDATE 无终态谓词，会把已终态行再改一次（终态被覆盖 +
      // revision 虚增 + 诊断节点二次插入）。现 WHERE 加终态排除——命中非 1（并发者已抢先）
      // 即回滚返 false（返回值契约不变，窗口收进事务内，已插诊断节点随回滚消失不双插）。
      // ★ 域①：终态集扩四值——stopped/interrupted 也是终态，迟到异终态收口同样被拒
      //（isRunFinalStatus 单源）
      const updateSql: string = 'UPDATE generation_runs SET status = ?, ' +
        'diagnosticMessageId = ?, revision = revision + 1, updatedAt = ? WHERE id = ? ' +
        'AND status NOT IN (?, ?, ?, ?)';
      const affected: number = await tx.execute(updateSql,
        [input.finalStatus, diagnosticId, input.now, input.runId,
          RUN_STATUS_FINISHED, RUN_STATUS_FAILED, RUN_STATUS_STOPPED,
          RUN_STATUS_INTERRUPTED]) as number;
      if (affected !== 1) {
        await tx.rollback();
        return false;
      }
      await tx.commit();
      return true;
    } catch (e) {
      await tx.rollback();
      throw e as Error;
    }
  });
}

// recordUsageEvent（J10 请求级账本去重冻结实现——去重键 = requestId）：requestId 非空时
// **同一 IMMEDIATE 写事务内**查重，命中即回滚返 false（同一请求重复回调不重复入账；事务内
// 查重 = 并发两条回调不会双双读到「未入账」）；requestId 为空 = 无请求身份（存量兼容形态）
// 不查重直插。**不同请求的真实消耗不因共用 run/attempt 被吞**——去重键只认 requestId，
// 禁按 runId/attemptId 去重。
export interface UsageEventInput {
  conversationId: string;
  messageId: string;
  providerId: string;
  modelId: string;
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
  durationMs: number;
  firstTokenMs: number;
  cachedTokens: number;
  purpose: string;
  runId: string;
  attemptId: string;
  branchId: string;
  requestId: string;
  createdAt: number;
  // 二期 #7（v65）：本轮官方服务端工具计次 JSON 串（'' = 无计次）。两个插入分支共用同一
  // bucket（加一键即两路生效）；小任务链不产计次，列 DEFAULT '' 天然兜底
  serverToolsUsage: string;
}

export async function recordUsageEvent(db: relationalStore.RdbStore,
  input: UsageEventInput): Promise<boolean> {
  // 铸号在写事务首条语句之前（D1 铸造纪律；表主键，事务内插入用）
  const bucket: relationalStore.ValuesBucket = {
    'id': nextMessageId('usage'),
    'conversationId': input.conversationId,
    'messageId': input.messageId,
    'providerId': input.providerId,
    'modelId': input.modelId,
    'promptTokens': input.promptTokens,
    'completionTokens': input.completionTokens,
    'totalTokens': input.totalTokens,
    'durationMs': input.durationMs,
    'firstTokenMs': input.firstTokenMs,
    'cachedTokens': input.cachedTokens,
    'purpose': input.purpose,
    'createdAt': input.createdAt,
    'runId': input.runId,
    'attemptId': input.attemptId,
    'branchId': input.branchId,
    'requestId': input.requestId,
    'serverToolsUsage': input.serverToolsUsage
  };
  if (input.requestId === '') {
    // 无请求身份（存量兼容形态）：不查重直插（原语义——去重键只认 requestId，无键可查）
    await db.insert('token_usage_events', bucket);
    return true;
  }
  // ★ S10③：查重与插入包进同一 IMMEDIATE 写事务。原实现是事务外 SELECT 查重 + 裸
  // insert——同一 requestId 的两条回调链并发时都能读到「未入账」而各插一行，去重键失效
  //（重复计费）。IMMEDIATE 单写事务把「查不到就插」两段串行化（d.ts 14800024）；事务内
  // 查重命中即回滚返 false（幂等出口语义与返回值契约不变）。
  // ★ 写串行链入链（requestId 查重事务段入链；无请求身份的直插支为单语句写留链外——
  // 撞窗毫秒级，透传自愈兜底）
  return runWriteQueued('recordUsageEvent', async (): Promise<boolean> => {
    const tx: relationalStore.Transaction =
      await db.createTransaction({ transactionType: relationalStore.TransactionType.IMMEDIATE });
    try {
      const dup: relationalStore.ResultSet = await tx.querySql(
        'SELECT id FROM token_usage_events WHERE requestId = ? LIMIT 1', [input.requestId]);
      try {
        if (dup.goToNextRow()) {
          await tx.rollback();
          return false; // 幂等跳过（重复回调不重复计费）
        }
      } finally {
        dup.close();
      }
      await tx.insert('token_usage_events', bucket);
      await tx.commit();
      return true;
    } catch (e) {
      await tx.rollback();
      throw e as Error;
    }
  });
}

// readPathPage（J10——沿分支路径读一页）：从起点（cursorNodeId ?? 分支 head）沿 parent 链
// 向根方向收集 limit 个节点，按「根 → 起点」升序返回；cursorNodeId 非空时**不含**该游标
// 自身（游标 = 上一页最早节点，翻页语义与触顶翻页同构）。选型：逐节点沿链点查（每步一
// 查询，有界 limit）——递归 CTE 未在官方 RDB 文档背书前不引入；limit ≤ 50 本地毫秒级。
// 分支不存在抛错。
export async function readPathPage(db: relationalStore.RdbStore, branchId: string,
  cursorNodeId: string | null, limit: number): Promise<GraphPathRow[]> {
  const branch: BranchRow | null = await queryBranch(db, branchId);
  if (branch === null) {
    throw new Error('readPathPage 失败：分支 ' + branchId + ' 不存在');
  }
  const collected: GraphPathRow[] = [];
  let cursor: string | null = cursorNodeId ?? branch.headMessageId;
  let fetched: number = 0;
  while (cursor !== null && fetched < limit) {
    const result: relationalStore.ResultSet = await db.querySql(
      'SELECT id, conversationId, role, content, reasoning, status, createdAt, ' +
      'parentMessageId, runId, ownerAssistantId, stepIndex, origin FROM messages ' +
      'WHERE id = ?', [cursor]);
    let row: GraphPathRow | null = null;
    try {
      if (result.goToNextRow()) {
        row = graphPathRowFromResult(result);
      }
    } finally {
      result.close();
    }
    if (row === null) {
      break; // 悬边防御：链中断即止（已收集部分照返，不假造完整）
    }
    const next: string | null = row.parentMessageId;
    if (row.id === cursorNodeId) {
      // 起点是游标自身：跳过游标（翻页语义——游标 = 上一页最早节点，不含在本页），继续向根
      cursor = next;
      continue;
    }
    cursor = next;
    collected.push(row);
    fetched++;
  }
  collected.reverse(); // 根 → 起点 升序
  return collected;
}

// forkBranch（J10——会话内「从既有分支的某节点分出新分支」的存储原语；独立会话 fork 归
// 笔5 域）：图插入校验 + 新分支行。fork 点必须在源分支路径上（沿源 head 上溯可达）；
// forkAtNodeId = null = 从源 head 延伸。activeBranchId 不动（切分支是读侧/笔4 域——
// 本命令只建分支）。
export interface ForkBranchInput {
  conversationId: string;
  sourceBranchId: string;
  forkAtNodeId: string | null;
  name: string;
  now: number;
}

export interface ForkedBranch {
  branchId: string;
  headMessageId: string | null;
}

export async function forkBranch(db: relationalStore.RdbStore,
  input: ForkBranchInput): Promise<ForkedBranch> {
  const source: BranchRow | null = await queryBranch(db, input.sourceBranchId);
  if (source === null) {
    throw new Error('forkBranch 失败：源分支 ' + input.sourceBranchId + ' 不存在');
  }
  if (source.conversationId !== input.conversationId) {
    throw new Error('forkBranch 失败：源分支归属会话 ' + source.conversationId +
      ' 与目标会话 ' + input.conversationId + ' 不一致');
  }
  const head: string | null = input.forkAtNodeId ?? source.headMessageId;
  if (head !== null) {
    // 路径校验：fork 点必须在源分支路径上（沿源 head 上溯经过 fork 点）
    const allNodes: Map<string, GraphNodeRef> = await loadConversationNodes(db,
      input.conversationId);
    const chain: string[] = source.headMessageId !== null
      ? traceAncestorChain(source.headMessageId, allNodes, allNodes.size)
      : [];
    if (!chain.includes(head)) {
      throw new Error('forkBranch 失败：fork 点 ' + head + ' 不在源分支路径上');
    }
  }
  // ★ 写串行链入链（路径校验读段留链外）
  return runWriteQueued('forkBranch', async (): Promise<ForkedBranch> => {
    const tx: relationalStore.Transaction =
      await db.createTransaction({ transactionType: relationalStore.TransactionType.IMMEDIATE });
    try {
      const branchId: string = nextMessageId('br');
      const bucket: relationalStore.ValuesBucket = {
        'id': branchId,
        'conversationId': input.conversationId,
        'parentBranchId': input.sourceBranchId,
        'headMessageId': head,
        'name': input.name,
        'createdAt': input.now
      };
      await tx.insert('branches', bucket);
      await tx.commit();
      return { branchId: branchId, headMessageId: head };
    } catch (e) {
      await tx.rollback();
      throw e as Error;
    }
  });
}

// prepareRetryRun（笔3 新增——末轮重试图形态的 run 创建原语）：与 prepareRun 的差异 =
// **不插输入节点**。重试的输入锚点是既有 user 节点（P4 拍板值：新分支从输入锚点生成，
// 不新增不复制 user 消息、不拼接旧后续），调用方先 forkBranch 把新分支 head 退到该锚点，
// 本命令只建 run 行（prepared，revision 0，inputAnchor = 既有锚点）。校验三条：分支在场、
// 属同会话、head 非空且与锚点一致（重试必有输入锚；head 即锚 = fork 语义的自证）。重复
// prepare 同一 runId = 主键冲突抛错（天然防重，同 prepareRun）。
export interface PrepareRetryRunInput {
  runId: string;
  conversationId: string;
  branchId: string;
  assistantId: string;
  anchorNodeId: string;
  now: number;
}

export async function prepareRetryRun(db: relationalStore.RdbStore,
  input: PrepareRetryRunInput): Promise<PreparedRun> {
  const branch: BranchRow | null = await queryBranch(db, input.branchId);
  if (branch === null) {
    throw new Error('prepareRetryRun 失败：分支 ' + input.branchId + ' 不存在');
  }
  if (branch.conversationId !== input.conversationId) {
    throw new Error('prepareRetryRun 失败：分支归属会话 ' + branch.conversationId +
      ' 与目标会话 ' + input.conversationId + ' 不一致');
  }
  if (branch.headMessageId === null || branch.headMessageId !== input.anchorNodeId) {
    throw new Error('prepareRetryRun 失败：分支 head 与重试输入锚点不一致（head ' +
      (branch.headMessageId ?? 'null') + '，锚点 ' + input.anchorNodeId + '）');
  }
  // ★ 写串行链入链（head 校验读段留链外）
  return runWriteQueued('prepareRetryRun', async (): Promise<PreparedRun> => {
    const tx: relationalStore.Transaction =
      await db.createTransaction({ transactionType: relationalStore.TransactionType.IMMEDIATE });
    try {
      const runBucket: relationalStore.ValuesBucket = {
        'id': input.runId,
        'conversationId': input.conversationId,
        'branchId': input.branchId,
        'attemptEpoch': 1,
        'inputAnchorMessageId': input.anchorNodeId,
        'revision': 0,
        'status': RUN_STATUS_PREPARED,
        'checkpoint': '',
        'diagnosticMessageId': '',
        'createdAt': input.now,
        'updatedAt': input.now
      };
      await tx.insert('generation_runs', runBucket);
      await tx.commit();
      return { runId: input.runId, userNodeId: input.anchorNodeId, revision: 0 };
    } catch (e) {
      await tx.rollback();
      throw e as Error;
    }
  });
}

// 拉会话全部图节点（refs 轻行——校验/存活集/快照共用；存量 legacy 行 parentMessageId
// 为 NULL 也入集，图语义只在 graph 会话消费）
export async function loadConversationNodes(db: relationalStore.RdbStore,
  conversationId: string): Promise<Map<string, GraphNodeRef>> {
  const nodes: Map<string, GraphNodeRef> = new Map<string, GraphNodeRef>();
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT id, conversationId, parentMessageId FROM messages WHERE conversationId = ?',
    [conversationId]);
  try {
    while (result.goToNextRow()) {
      const parentIdx: number = result.getColumnIndex('parentMessageId');
      nodes.set(result.getString(result.getColumnIndex('id')), {
        id: result.getString(result.getColumnIndex('id')),
        conversationId: result.getString(result.getColumnIndex('conversationId')),
        parentMessageId: result.isColumnNull(parentIdx) ? null : result.getString(parentIdx)
      });
    }
  } finally {
    result.close();
  }
  return nodes;
}

// 全会话分支行（谱系删除的收集输入面；与 loadConversationNodes 同款姿势——行轻、单会话
// 分支数个位数量级，量级可忽略）
export async function loadConversationBranches(db: relationalStore.RdbStore,
  conversationId: string): Promise<BranchRow[]> {
  const rows: BranchRow[] = [];
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT id, conversationId, parentBranchId, headMessageId, name, createdAt ' +
    'FROM branches WHERE conversationId = ? ORDER BY createdAt ASC', [conversationId]);
  try {
    while (result.goToNextRow()) {
      const parentIdx: number = result.getColumnIndex('parentBranchId');
      const headIdx: number = result.getColumnIndex('headMessageId');
      rows.push({
        id: result.getString(result.getColumnIndex('id')),
        conversationId: result.getString(result.getColumnIndex('conversationId')),
        parentBranchId: result.isColumnNull(parentIdx) ? null
          : result.getString(parentIdx),
        headMessageId: result.isColumnNull(headIdx) ? null : result.getString(headIdx),
        name: result.getString(result.getColumnIndex('name')),
        createdAt: result.getLong(result.getColumnIndex('createdAt'))
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// replaceMessageUnit（J6——「替换消息＋旧附件元数据作废」同一提交单元，单条形态；供
// 恢复/导入路径复用）：事务内一次完成——更新消息行（content/reasoning）+ 删旧 refs +
// 删旧 message_attachments 元数据行；返回作废附件的本地路径集，**文件由调用方 commit 后
// 删**（回滚不得已删文件红线——W15 导入中断验证：事务回滚则行与元数据都回滚、文件不动）。
export interface ReplaceMessageInput {
  messageId: string;
  newContent: string;
  newReasoning: string;
  now: number;
}

export interface ReplaceMessageResult {
  invalidatedLocalPaths: string[];
}

export async function replaceMessageUnit(db: relationalStore.RdbStore,
  input: ReplaceMessageInput): Promise<ReplaceMessageResult> {
  // ★ 2026-09-29 写串行链入链
  return runWriteQueued('replaceMessageUnit', async (): Promise<ReplaceMessageResult> => {
    const tx: relationalStore.Transaction =
      await db.createTransaction({ transactionType: relationalStore.TransactionType.IMMEDIATE });
    try {
      // 旧附件收集（事务内读——与写入同一快照）
      const oldResult: relationalStore.ResultSet = await tx.querySql(
        'SELECT id, localPath FROM message_attachments WHERE messageId = ?', [input.messageId]);
      const oldIds: string[] = [];
      const localPaths: string[] = [];
      try {
        while (oldResult.goToNextRow()) {
          oldIds.push(oldResult.getString(oldResult.getColumnIndex('id')));
          localPaths.push(oldResult.getString(oldResult.getColumnIndex('localPath')));
        }
      } finally {
        oldResult.close();
      }
      // 删旧 refs（graph 侧引用随资源行同亡——悬挂 refs 禁留）
      if (oldIds.length > 0) {
        await tx.execute(
          'DELETE FROM attachment_refs WHERE attachmentId IN (' +
          oldIds.map((_id: string): string => '?').join(',') + ')', oldIds);
        const attachPredicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('message_attachments');
        attachPredicates.in('id', oldIds);
        await tx.delete(attachPredicates);
      }
      const msgBucket: relationalStore.ValuesBucket = {
        'content': input.newContent,
        'reasoning': input.newReasoning
      };
      const msgPredicates: relationalStore.RdbPredicates =
        new relationalStore.RdbPredicates('messages');
      msgPredicates.equalTo('id', input.messageId);
      const affected: number = await tx.update(msgBucket, msgPredicates);
      if (affected !== 1) {
        throw new Error('replaceMessageUnit 失败：消息 ' + input.messageId + ' 不存在'); // 回滚归 catch（LB-1 同批）
      }
      await tx.commit();
      return { invalidatedLocalPaths: localPaths };
    } catch (e) {
      await tx.rollback();
      throw e as Error;
    }
  });
}

