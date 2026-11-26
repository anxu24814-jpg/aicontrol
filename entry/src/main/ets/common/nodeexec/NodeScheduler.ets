// Node 执行调度器（2026-11-23 鸿蒙 Node 运行时门 2 U3b 笔，任务书-鸿蒙Node运行时门2-20261123
// §3.4「准备期取消落点」/ §0 代决表 / §4 S3-3；2026-11-24 门 3 U3 S2 拆分笔，任务书-鸿蒙Node
// 运行时门3 U3-binrunner-20261124 §5 S2）：全局串行 lane + 会话取消代次 + 终态槽位释放。
// ★ 准备位置按 **§0 代决表**：运行区落位与 Node 启动在 lane 外单飞准备，只有用户代码执行进
// lane（§4 S3-3「准备在 lane 内」与代决表冲突，施工步骤让位代决表——2026-11-23 指挥裁定）。
//
// 本件职责（exec 域三面；U4 只调 executeNodeCode / cancelNodeForConversation / queryNodeStatus /
// dropNodeForConversation，门 3 U2 另调 installNodePackages，门 3 U3 加 executeNodeBin——禁在工具
// 层另写排队、代次、槽位或互斥逻辑）。拆分后共享基元在 NodeSchedulerCore.ets（准备单飞 / 会话
// 代次表 / 在跑登记两表 / 宽限等待），install 单飞域在 NodeInstallScheduler.ets（本件只转出出口
// 与类型，不在本件实现）；待重启守卫旗在 NodeAdmin.ets（门 4：管理页清空 / 重建后置位，两执行
// 入口在参数校验后、lane 准入前拒，见各入口处注释）：
// ① lane 队列：全局执行位 NODE_LANE_MAX_CONCURRENT = 1，占位者 = 一轮在跑 exec（准备不占位）。
//    空闲且队列空 → 直接占位；否则按 FIFO 进等待队列（上限 NODE_LANE_QUEUE_MAX_WAITING = 3），
//    第 4 个等待者当场拒绝（不静默排队）；等待超 NODE_LANE_QUEUE_WAIT_MAX_MS = 30 s 未获位
//    = 「等待执行位超时」不执行——排队上限只被在跑执行占用，不被准备等待吃掉。
//    占位者结算即把执行位直接转交队首（releaseLaneSlot），零空转。
// ② 会话取消代次：每 conversationId 一份 { generation, inFlight }（NodeConversationState，表在
//    Core）；代次快照在调用进入时取。cancelNodeForConversation 只递增代次（并把在跑请求转给
//    bootstrap cancel 终止），不 await、不占 lane。四处复检 = 进入初查、lane 外准备返回后、占位
//    后、受理回调返回后（= 发 exec 前）：任一已变立即回 {ok:false, cancelled:true} 且不执行、
//    不写 data；准备期取消只放弃等待，不中断共享准备（其他会话可能正等它），也不趁机进 lane；
//    排队中的取消者由 denyWaitersForConversation 当场出队。代次表只在飞（inFlight 归零即删），
//    无界增长防线。
// ③ 槽位释放：exec 的 Promise 一结算就走 finally 释放——成功回执、终态回执（cancelled/timeout/
//    crashed/dropped/terminated-background）、桥接失败、宽限到点皆同。bootstrap 只在 worker
//    terminate settle 之后才回终态，故「回执到达 = Node 侧真已释放」，不等宽限。宽限起算 = 占位
//    时刻（覆盖受理回调与执行段，**不覆盖 lane 外的 prepare 等待**）= 执行超时 +
//    NODE_LANE_GRACE_EXTRA_MS，到点按「等待超过上限仍未结束」判 lane 未执行并释放槽位。宽限后
//    Node 侧可能仍在跑，下一笔会撞 bootstrap 的 busy 护栏如实失败——那是任务书 §3.2 的既定口径
//    （释放优先，不让队列被单笔拖死）。
//
// 执行顺序：①代次初查 → ②await prepare（lane 外，不占槽位 / 不占等待位 / 不计 30 s 排队）→
// ③代次复查 → ④申请 lane（并发 1 / 等待位 3 / 30 s）→ ⑤占位后代次复查 → ⑥onLaneAdmitted
// （U4 写 data 并给 cwd）→ ⑦发 exec 前代次复查 → ⑧结算即 releaseLaneSlot。准备单飞 =
// ensureNodeRuntimePlacement + startNodeRuntime 合成一个共享 promise（实现移入 Core），并发调用
// 只跑一趟、不重复启动；exec 的 timeoutMs 自 Node 侧受理才计时，故准备再慢也不吃用户代码超时。
//
// 非目标（P2-4）：本件不碰数据库、不建临时区、不写 node-input 数据文件（WorkspaceDbTmp 与 data
// 落件归 U4，经 onLaneAdmitted 回调注入 cwd）；不改 rawfile、不定义工具卡与 desc；token 只经
// NodeBridge 的 endpoint 传递，本件零 token 日志零回显。
// ArkTS 不可本机执行：三面行为（队列 / 代次 / 宽限）待真机与 U4 断言覆盖，本笔只证源码结构可核
// 与构建绿，禁宣称已行为验证。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NodeBridgeEndpoint, NodeBridgeMemory, NodeBridgePrepareStats, NodeBridgeReply,
  NodeBridgeRequestFields, requestNodeBridge } from './NodeBridge';
import { isNodeProcessStarted, peekNodeEndpoint, NodeRuntimeStartOutcome } from './NodeRuntime';
// 待重启守卫（门 4）：管理页清空安装包 / 重建运行区后置位，重启前 exec 与 run_bin 一律拒在
// 参数校验之后、lane 准入之前——不占位、不排队、不碰运行区
import { nodeNeedsRestart, nodeRestartGuardText } from './NodeAdmin';
import { NodeConversationState, NODE_SESSION_ID_MAX_LENGTH, NodeReplyWait,
  activeSessionTargets, awaitReplyWithGrace, bindActiveSession, conversationStateOf,
  ensureConversationState, errorMessageOf, prepareRuntimeOnce, releaseConversationState,
  unbindActiveSession } from './NodeSchedulerCore';
// install 单飞域出口与类型（实现与依赖在 NodeInstallScheduler.ets，单向 Scheduler → Install）：
// import 后再出口，照 MemoryGen「单源再出口」判例——消费方（ToolNodeExec / 探针页）历史路径
// 不变，断言夹具的 import 图复制也能跟到新件
import { installNodePackages, NODE_INSTALL_DEFAULT_TIMEOUT_MS, NODE_INSTALL_MAX_TIMEOUT_MS,
  NodeInstallErrorKind, NodeInstallReceipt, NodeInstallRequest } from './NodeInstallScheduler';

// ── 执行限额（本件单源；U4 写 `exec_node` 的 desc/schema 时引用这三项，禁在工具层另写字面量）──
export const NODE_EXEC_DEFAULT_TIMEOUT_MS: number = 120000;
export const NODE_EXEC_MIN_TIMEOUT_S: number = 1;
export const NODE_EXEC_MAX_TIMEOUT_S: number = 300;
// bin 运行参数上限（门 3 U3；传输层 bootstrap 同值兜底，工具面 desc/schema 由这两项拼接）
export const NODE_BIN_ARGS_MAX: number = 16;
export const NODE_BIN_ARG_MAX_LENGTH: number = 200;

// ── lane 规格（任务书 §0 执行限额代决：全局并发 1 / 等待位 3 / 排队上限 30 s / 宽限 +15 s）──
export const NODE_LANE_MAX_CONCURRENT: number = 1;
export const NODE_LANE_QUEUE_MAX_WAITING: number = 3;
export const NODE_LANE_QUEUE_WAIT_MAX_MS: number = 30000;
export const NODE_LANE_GRACE_EXTRA_MS: number = 15000;

// 控制面动作（cancel / drop / status）的响应上限——即时动作，超时即报桥接不可用
const NODE_CONTROL_RESPONSE_TIMEOUT_MS: number = 15000;
// 调度层日志位（只记失败事实，不含 token / 代码内容）
const NODE_SCHED_LOG_DOMAIN: number = 0xD5A0;
const NODE_SCHED_LOG_TAG: string = 'NodeScheduler';

// 调度层失败分类（U4 按 kind 选文案；Node 回执透传时 receipt.errorKind 缺省，error 是 bootstrap 错误码）
export type NodeExecErrorKind = 'no-session' | 'invalid-request' | 'runtime-unavailable'
  | 'lane-rejected' | 'bridge-unreachable' | 'workspace-unavailable' | 'cancelled'
  | 'internal-error';

// 受理回调上下文（U4 在拿到 lane 之后、发 exec 之前写 node-input 数据文件并给出 cwd；
// dataPath 供 U4 自己组织回执尾注，本件只消费 cwd——缺 cwd 直接判未执行，不猜默认目录）
export interface NodeLaneAdmitContext {
  cwd?: string;
  dataPath?: string;
}

// executeNodeCode 入参（conversationId/sessionId/code 必填；无会话标识 = 顶层错误回执，
// 不启动运行时、不进 lane、不建目录）
export interface NodeExecRequest {
  conversationId: string;
  sessionId: string;
  code: string;
  timeoutMs?: number;
  onLaneAdmitted?: () => Promise<NodeLaneAdmitContext>;
}

// executeNodeBin 入参（门 3 U3）：bin 必填、args 可选（≤ 16 条每条 ≤ 200 字符，工具面预检）；
// 其余语义与 exec 同 —— 同一 lane、同一取消代次、同一准备单飞，不进 install 单飞
export interface NodeBinRequest {
  conversationId: string;
  sessionId: string;
  bin: string;
  args?: string[];
  timeoutMs?: number;
  onLaneAdmitted?: () => Promise<NodeLaneAdmitContext>;
}

// 轮种载荷（exec 与 run_bin 共用同一套 lane / 代次 / 槽位机；两轮种不合并执行体，只合并编排）
interface NodeRoundSpec {
  kind: 'exec' | 'run_bin';
  code: string;
  bin: string;
  args: string[];
  onLaneAdmitted?: () => Promise<NodeLaneAdmitContext>;
}

// 执行回执（U4 只按这一套字段渲染；调度层失败时数据字段全为空默认值）
export interface NodeExecReceipt {
  ok: boolean;
  /** 调度层失败分类；Node 回执透传时缺省（此时 error 是 bootstrap 错误码） */
  errorKind?: NodeExecErrorKind;
  /** 失败文案（调度层）或 bootstrap 错误码透传（cancelled/timeout/crashed/dropped/
   *  terminated-background/script-error/busy 等） */
  error?: string;
  /** 取消：调度层准备期取消，或 Node 侧 cancelled/dropped 终态 */
  cancelled?: boolean;
  stdout: string;
  stderr: string;
  stdoutTruncated: boolean;
  stderrTruncated: boolean;
  elapsedMs: number;
  workerStartMs: number;
  sessionReset: string;
  evictedSessionIds: string[];
  savedNames: string[];
  events: string[];
  eventsKept: number;
  eventsTotal: number;
  eventsNote: string;
  backgroundOps: number;
  nodeVersion: string;
  platform: string;
  cwd: string;
  cwdRestored: boolean;
  memory?: NodeBridgeMemory;
  /** bin 运行面（门 3 U3；exec 轮缺省）：命令名 / 退出码 / 入口提供方 / 是否同名覆盖 */
  bin?: string;
  exitCode?: number;
  binPackage?: string;
  binReplaced?: boolean;
}

// 状态回执（U4 探针与诊断入口；只读，不启动运行时、不进 lane）
export interface NodeStatusReceipt {
  ok: boolean;
  error?: string;
  channel?: string;
  nodeVersion?: string;
  npmVersion?: string;
  prepare?: string;
  prepareError?: string;
  prepareStats?: NodeBridgePrepareStats;
  workers?: number;
  memory?: NodeBridgeMemory;
}

// drop 回执（删除会话/助手级联用；stopped = 是否有在跑 exec 被 settle）
export interface NodeDropReceipt {
  ok: boolean;
  error?: string;
  stopped: boolean;
  workerTerminated: boolean;
}

// 占位结果（admitted=false 时 cancelled 区分「被取消」与「队列拒绝」）
interface NodeLaneAdmission {
  admitted: boolean;
  cancelled: boolean;
  error: string;
}

// 排队条目（settled 后从队列摘除；waitTimerId 只在等待期有效）
interface NodeLaneWaiter {
  conversationId: string;
  resolve: (admission: NodeLaneAdmission) => void;
  waitTimerId: number;
  settled: boolean;
}

// ── 模块状态（ArkTS 主线程单线程：状态迁移无竞态，唯一异步边界是 promise settle）──
// 代次表 / 在跑登记两表 / 准备单飞移入 NodeSchedulerCore；本件只持 lane 状态
let laneActiveCount: number = 0;
const laneWaiters: NodeLaneWaiter[] = [];

// ── lane（单点：占位 / 结算释放 / 等待队列推进）──

function hasFreeLaneSlot(): boolean {
  return laneActiveCount < NODE_LANE_MAX_CONCURRENT && laneWaiters.length === 0;
}

function clearWaiterTimer(waiter: NodeLaneWaiter): void {
  if (waiter.waitTimerId >= 0) {
    clearTimeout(waiter.waitTimerId);
    waiter.waitTimerId = -1;
  }
}

function removeWaiter(waiter: NodeLaneWaiter): void {
  const index: number = laneWaiters.indexOf(waiter);
  if (index >= 0) {
    laneWaiters.splice(index, 1);
  }
}

// 结算排队条目（唯一出口：清计时、摘队、resolve；settled 幂等）
function settleWaiter(waiter: NodeLaneWaiter, admission: NodeLaneAdmission): void {
  if (waiter.settled) {
    return;
  }
  waiter.settled = true;
  clearWaiterTimer(waiter);
  removeWaiter(waiter);
  waiter.resolve(admission);
}

// 占位或入队（P0-1：队列满与等待超时都明确拒绝，不静默排队）
function admitOrQueue(conversationId: string): Promise<NodeLaneAdmission> {
  return new Promise<NodeLaneAdmission>((resolve: (value: NodeLaneAdmission) => void): void => {
    if (hasFreeLaneSlot()) {
      laneActiveCount++;
      resolve({ admitted: true, cancelled: false, error: '' });
      return;
    }
    if (laneWaiters.length >= NODE_LANE_QUEUE_MAX_WAITING) {
      resolve({ admitted: false, cancelled: false, error: '执行位已满，请稍后重试' });
      return;
    }
    const waiter: NodeLaneWaiter = {
      conversationId: conversationId,
      resolve: resolve,
      waitTimerId: -1,
      settled: false
    };
    waiter.waitTimerId = setTimeout((): void => {
      settleWaiter(waiter, {
        admitted: false,
        cancelled: false,
        error: '等待执行位超过 ' + (NODE_LANE_QUEUE_WAIT_MAX_MS / 1000) + ' 秒，未执行'
      });
    }, NODE_LANE_QUEUE_WAIT_MAX_MS);
    laneWaiters.push(waiter);
  });
}

// 取队首活条目（已结算的顺手摘掉——防御位）
function takeFirstWaiter(): NodeLaneWaiter | null {
  while (laneWaiters.length > 0) {
    const head: NodeLaneWaiter = laneWaiters.shift() as NodeLaneWaiter;
    if (!head.settled) {
      return head;
    }
    clearWaiterTimer(head);
  }
  return null;
}

// 释放执行位（单点）：先还位，再按 FIFO 把空位直接转交队首——占位者结算后调用，零空转
function releaseLaneSlot(): void {
  if (laneActiveCount > 0) {
    laneActiveCount--;
  }
  while (laneActiveCount < NODE_LANE_MAX_CONCURRENT) {
    const next: NodeLaneWaiter | null = takeFirstWaiter();
    if (next === null) {
      break;
    }
    next.settled = true;
    clearWaiterTimer(next);
    laneActiveCount++;
    next.resolve({ admitted: true, cancelled: false, error: '' });
  }
}

// 取消命中排队者：当场出队回 cancelled（代次已变，不再等 lane）
function denyWaitersForConversation(conversationId: string): void {
  const hits: NodeLaneWaiter[] = [];
  for (let i: number = 0; i < laneWaiters.length; i++) {
    if (laneWaiters[i].conversationId === conversationId) {
      hits.push(laneWaiters[i]);
    }
  }
  for (let i: number = 0; i < hits.length; i++) {
    settleWaiter(hits[i], { admitted: false, cancelled: true, error: '' });
  }
}

// ── 回执骨架与映射 ──

function emptyExecReceipt(): NodeExecReceipt {
  return {
    ok: false,
    stdout: '',
    stderr: '',
    stdoutTruncated: false,
    stderrTruncated: false,
    elapsedMs: 0,
    workerStartMs: 0,
    sessionReset: '',
    evictedSessionIds: [],
    savedNames: [],
    events: [],
    eventsKept: 0,
    eventsTotal: 0,
    eventsNote: '',
    backgroundOps: 0,
    nodeVersion: '',
    platform: '',
    cwd: '',
    cwdRestored: true
  };
}

function schedulerFailure(kind: NodeExecErrorKind, message: string): NodeExecReceipt {
  const receipt: NodeExecReceipt = emptyExecReceipt();
  receipt.errorKind = kind;
  receipt.error = message;
  return receipt;
}

// 调度层判取消（准备期 / 排队期）：不执行、不写 data、不产生产物
function cancelledReceipt(): NodeExecReceipt {
  const receipt: NodeExecReceipt = emptyExecReceipt();
  receipt.errorKind = 'cancelled';
  receipt.error = '已取消';
  receipt.cancelled = true;
  return receipt;
}

// Node 回执透传（字段一个一个带，缺字段保默认值——终态回执不带输出与 savedNames）
function receiptFromReply(reply: NodeBridgeReply): NodeExecReceipt {
  const receipt: NodeExecReceipt = emptyExecReceipt();
  receipt.ok = reply.ok;
  if (reply.error !== undefined && reply.error !== '') {
    receipt.error = reply.error;
    receipt.cancelled = reply.error === 'cancelled' || reply.error === 'dropped';
  }
  if (reply.stdout !== undefined) {
    receipt.stdout = reply.stdout;
  }
  if (reply.stderr !== undefined) {
    receipt.stderr = reply.stderr;
  }
  if (reply.stdoutTruncated !== undefined) {
    receipt.stdoutTruncated = reply.stdoutTruncated;
  }
  if (reply.stderrTruncated !== undefined) {
    receipt.stderrTruncated = reply.stderrTruncated;
  }
  if (reply.elapsedMs !== undefined) {
    receipt.elapsedMs = reply.elapsedMs;
  }
  if (reply.workerStartMs !== undefined) {
    receipt.workerStartMs = reply.workerStartMs;
  }
  if (reply.sessionReset !== undefined) {
    receipt.sessionReset = reply.sessionReset;
  }
  if (reply.evictedSessionIds !== undefined) {
    receipt.evictedSessionIds = reply.evictedSessionIds;
  }
  if (reply.savedNames !== undefined) {
    receipt.savedNames = reply.savedNames;
  }
  if (reply.events !== undefined) {
    receipt.events = reply.events;
  }
  if (reply.eventsKept !== undefined) {
    receipt.eventsKept = reply.eventsKept;
  }
  if (reply.eventsTotal !== undefined) {
    receipt.eventsTotal = reply.eventsTotal;
  }
  if (reply.eventsNote !== undefined) {
    receipt.eventsNote = reply.eventsNote;
  }
  if (reply.backgroundOps !== undefined) {
    receipt.backgroundOps = reply.backgroundOps;
  }
  if (reply.nodeVersion !== undefined) {
    receipt.nodeVersion = reply.nodeVersion;
  }
  if (reply.platform !== undefined) {
    receipt.platform = reply.platform;
  }
  if (reply.cwd !== undefined) {
    receipt.cwd = reply.cwd;
  }
  if (reply.cwdRestored !== undefined) {
    receipt.cwdRestored = reply.cwdRestored;
  }
  if (reply.memory !== undefined) {
    receipt.memory = reply.memory;
  }
  if (reply.bin !== undefined) {
    receipt.bin = reply.bin;
  }
  if (reply.exitCode !== undefined) {
    receipt.exitCode = reply.exitCode;
  }
  if (reply.binPackage !== undefined) {
    receipt.binPackage = reply.binPackage;
  }
  if (reply.binReplaced !== undefined) {
    receipt.binReplaced = reply.binReplaced;
  }
  return receipt;
}

// ── 对外入口 ──

// 超时取值（exec 与 run_bin 同一口径：缺省 = 120 s；给定必须是 1~300 s 内整数毫秒，
// 越界与非法一律拒绝，不静默夹取）
interface NodeTimeoutDecision {
  ok: boolean;
  timeoutMs: number;
  error: string;
}

function resolveNodeTimeout(requested: number | undefined): NodeTimeoutDecision {
  if (requested === undefined) {
    return { ok: true, timeoutMs: NODE_EXEC_DEFAULT_TIMEOUT_MS, error: '' };
  }
  const minMs: number = NODE_EXEC_MIN_TIMEOUT_S * 1000;
  const maxMs: number = NODE_EXEC_MAX_TIMEOUT_S * 1000;
  if (Math.round(requested) !== requested || requested < minMs || requested > maxMs) {
    return {
      ok: false,
      timeoutMs: NODE_EXEC_DEFAULT_TIMEOUT_MS,
      error: '超时取值需在 ' + NODE_EXEC_MIN_TIMEOUT_S + ' 至 ' + NODE_EXEC_MAX_TIMEOUT_S
        + ' 秒之间，未执行'
    };
  }
  return { ok: true, timeoutMs: requested, error: '' };
}

// 执行一段用户代码（唯一执行进口）：校验 → 准备单飞（lane 外）→ 占位/排队 → 受理回调 →
// exec → 终态释放（顺序细节见 runOutsideLaneThenInLane 头注释）。
// 无 conversationId/sessionId/code = 顶层错误回执，不启动运行时、不进 lane。
export async function executeNodeCode(req: NodeExecRequest): Promise<NodeExecReceipt> {
  const conversationId: string = typeof req.conversationId === 'string' ? req.conversationId : '';
  const sessionId: string = typeof req.sessionId === 'string' ? req.sessionId : '';
  const code: string = typeof req.code === 'string' ? req.code : '';
  if (conversationId === '') {
    return schedulerFailure('no-session', '缺少会话标识 conversationId，未启动 Node 运行时');
  }
  if (sessionId === '') {
    return schedulerFailure('no-session', '缺少会话标识 sessionId，未启动 Node 运行时');
  }
  if (sessionId.length > NODE_SESSION_ID_MAX_LENGTH) {
    return schedulerFailure('invalid-request', '会话标识超长，未启动 Node 运行时');
  }
  if (code === '') {
    return schedulerFailure('invalid-request', '代码内容为空，未启动 Node 运行时');
  }
  const timeout: NodeTimeoutDecision = resolveNodeTimeout(req.timeoutMs);
  if (!timeout.ok) {
    return schedulerFailure('invalid-request', timeout.error);
  }
  if (nodeNeedsRestart()) {
    return schedulerFailure('runtime-unavailable', nodeRestartGuardText());
  }
  const spec: NodeRoundSpec = {
    kind: 'exec',
    code: code,
    bin: '',
    args: [],
    onLaneAdmitted: req.onLaneAdmitted
  };
  return await startScheduledRound(conversationId, sessionId, timeout.timeoutMs, spec);
}

// 跑一个已装包的命令行入口（门 3 U3）。lane / 代次 / 准备单飞 / 槽位释放与 exec 完全共用；
// 不并进 install 单飞（install 是安装区写者，bin 只是既有包的读者）。无会话直拒（2252 判据）。
export async function executeNodeBin(req: NodeBinRequest): Promise<NodeExecReceipt> {
  const conversationId: string = typeof req.conversationId === 'string' ? req.conversationId : '';
  const sessionId: string = typeof req.sessionId === 'string' ? req.sessionId : '';
  const binName: string = typeof req.bin === 'string' ? req.bin : '';
  if (conversationId === '') {
    return schedulerFailure('no-session', '缺少会话标识 conversationId，未启动 Node 运行时');
  }
  if (sessionId === '') {
    return schedulerFailure('no-session', '缺少会话标识 sessionId，未启动 Node 运行时');
  }
  if (sessionId.length > NODE_SESSION_ID_MAX_LENGTH) {
    return schedulerFailure('invalid-request', '会话标识超长，未启动 Node 运行时');
  }
  if (binName === '') {
    return schedulerFailure('invalid-request', '命令名为空，未执行');
  }
  const args: string[] = [];
  if (req.args !== undefined) {
    for (let i: number = 0; i < req.args.length; i++) {
      const item: string = req.args[i];
      if (typeof item !== 'string' || item.length > NODE_BIN_ARG_MAX_LENGTH
        || args.length >= NODE_BIN_ARGS_MAX) {
        return schedulerFailure('invalid-request', '命令参数超限，未执行');
      }
      args.push(item);
    }
  }
  const timeout: NodeTimeoutDecision = resolveNodeTimeout(req.timeoutMs);
  if (!timeout.ok) {
    return schedulerFailure('invalid-request', timeout.error);
  }
  if (nodeNeedsRestart()) {
    return schedulerFailure('runtime-unavailable', nodeRestartGuardText());
  }
  const spec: NodeRoundSpec = {
    kind: 'run_bin',
    code: '',
    bin: binName,
    args: args,
    onLaneAdmitted: req.onLaneAdmitted
  };
  return await startScheduledRound(conversationId, sessionId, timeout.timeoutMs, spec);
}

// 两轮种共用的编排尾段（在飞登记 + 代次快照 + 异常收口 + 状态释放）
async function startScheduledRound(conversationId: string, sessionId: string, timeoutMs: number,
  spec: NodeRoundSpec): Promise<NodeExecReceipt> {
  const state: NodeConversationState = ensureConversationState(conversationId);
  state.inFlight++;
  const generation: number = state.generation;
  try {
    return await runOutsideLaneThenInLane(spec, conversationId, sessionId, timeoutMs, state,
      generation);
  } catch (e) {
    return schedulerFailure('internal-error', 'Node 执行调度异常，' + errorMessageOf(e as Error));
  } finally {
    releaseConversationState(conversationId, state);
  }
}

// ①代次初查 → ②lane 外准备单飞 → ③代次复查 → ④申请 lane → ⑤~⑧ lane 内执行（槽位释放的
// 单一出口在 lane 段的 finally，见 runWithLane 调用处）
async function runOutsideLaneThenInLane(spec: NodeRoundSpec, conversationId: string,
  sessionId: string, timeoutMs: number, state: NodeConversationState,
  generation: number): Promise<NodeExecReceipt> {
  if (state.generation !== generation) {
    return cancelledReceipt(); // ① 初查（同步段内不会变，留作契约锚点）
  }
  // ② 准备单飞在 lane 外：等待准备不占执行位、不占等待位、不计入 30 s 排队上限；首次解包
  //    再慢也只拖本次调用，不吃后来者的排队名额（§0 代决表）
  let prepared: NodeRuntimeStartOutcome;
  try {
    prepared = await prepareRuntimeOnce();
  } catch (e) {
    return schedulerFailure('runtime-unavailable',
      'Node 运行区准备失败，' + errorMessageOf(e as Error));
  }
  // ③ 准备期间被取消：只放弃等待，不中断共享准备，也不趁机进 lane
  if (state.generation !== generation) {
    return cancelledReceipt();
  }
  const admission: NodeLaneAdmission = await admitOrQueue(conversationId); // ④
  if (!admission.admitted) {
    if (admission.cancelled) {
      return cancelledReceipt();
    }
    return schedulerFailure('lane-rejected', admission.error);
  }
  try {
    return await runWithLane(spec, conversationId, sessionId, timeoutMs, prepared, state,
      generation);
  } finally {
    releaseLaneSlot(); // ⑧ 槽位唯一释放点：终态回执 / 失败 / 宽限到点皆同
  }
}

// lane 内本体：⑤占位后代次复查 → ⑥受理回调 → ⑦发请求前复查 → 执行
async function runWithLane(spec: NodeRoundSpec, conversationId: string, sessionId: string,
  timeoutMs: number, prepared: NodeRuntimeStartOutcome,
  state: NodeConversationState, generation: number): Promise<NodeExecReceipt> {
  if (state.generation !== generation) {
    return cancelledReceipt(); // ⑤
  }
  // 宽限起算 = 占位时刻（覆盖受理回调与执行段，不覆盖 lane 外的准备等待）
  const graceDeadlineMs: number = Date.now() + timeoutMs + NODE_LANE_GRACE_EXTRA_MS;
  let cwd: string = '';
  if (spec.onLaneAdmitted !== undefined) {
    let admittedContext: NodeLaneAdmitContext;
    try {
      admittedContext = await spec.onLaneAdmitted(); // ⑥
    } catch (e) {
      return schedulerFailure('workspace-unavailable',
        '执行前准备失败，' + errorMessageOf(e as Error));
    }
    if (admittedContext.cwd !== undefined) {
      cwd = admittedContext.cwd;
    }
  }
  if (cwd === '') {
    return schedulerFailure('workspace-unavailable', '未提供工作目录，未执行 Node 代码');
  }
  // ⑦ 受理回调期间取消：仍不执行（data 件由 U4 的临时区生命周期收口）
  if (state.generation !== generation) {
    return cancelledReceipt();
  }
  const remainingGraceMs: number = graceDeadlineMs - Date.now();
  if (remainingGraceMs <= 0) {
    return schedulerFailure('lane-rejected', '等待执行超过上限仍未结束，已释放执行位');
  }
  // 在跑登记（cancel 转调 bootstrap 的会话目标；exec 与 install 分表在 Core，见其文件头）
  bindActiveSession('exec', conversationId, sessionId);
  try {
    const fields: NodeBridgeRequestFields = {
      sessionId: sessionId,
      cwd: cwd,
      timeoutMs: timeoutMs
    };
    if (spec.kind === 'run_bin') {
      fields.bin = spec.bin;
      fields.args = spec.args;
    } else {
      fields.code = spec.code;
    }
    const action: string = spec.kind === 'run_bin' ? 'run_bin' : 'exec';
    const pending: Promise<NodeBridgeReply> =
      requestNodeBridge(prepared.endpoint, action, fields, remainingGraceMs);
    const waited: NodeReplyWait = await awaitReplyWithGrace(pending, remainingGraceMs);
    if (waited.timedOut) {
      return schedulerFailure('lane-rejected', '等待执行超过上限仍未结束，已释放执行位');
    }
    if (waited.failure !== '') {
      return schedulerFailure('bridge-unreachable', 'Node 桥接不可用，' + waited.failure);
    }
    if (waited.reply === null) {
      return schedulerFailure('bridge-unreachable', 'Node 桥接未返回回执');
    }
    return receiptFromReply(waited.reply);
  } finally {
    unbindActiveSession('exec', conversationId, sessionId);
  }
}

// 会话取消（挂 ToolRuntime.cancelAllPending 停链单点）：只递增代次 + 把在跑请求转给 bootstrap
// cancel；不 await、不占 lane。排队者当场出队；准备期调用在准备返回后自行回 cancelled。
export function cancelNodeForConversation(conversationId: string): void {
  if (conversationId === '') {
    return; // 空 id fail-safe（照 ToolRuntime.cancelAllPending 既有口径）
  }
  const state: NodeConversationState | undefined = conversationStateOf(conversationId);
  if (state === undefined) {
    return; // 无在飞调用 = 没有可取消的东西
  }
  state.generation++;
  denyWaitersForConversation(conversationId);
  // 两表都查（exec 与 install 可并存，同 sessionId 只发一次 cancel）；目标集由 Core 统一给
  const targets: string[] = activeSessionTargets(conversationId);
  if (targets.length === 0) {
    return; // 还在排队或准备期：代次已变，调用方自会回 cancelled，无需动 Node
  }
  for (const target of targets) {
    notifyBootstrapCancel(target);
  }
}

// 在跑请求的 bootstrap 终止（一请求一连接，直达控制面；失败只记日志，用户侧仍会拿到终态回执）
function notifyBootstrapCancel(sessionId: string): void {
  const endpoint: NodeBridgeEndpoint | null = peekNodeEndpoint();
  if (endpoint === null) {
    return; // 运行时未启动 = 没有在跑请求
  }
  const fields: NodeBridgeRequestFields = { sessionId: sessionId };
  requestNodeBridge(endpoint, 'cancel', fields, NODE_CONTROL_RESPONSE_TIMEOUT_MS)
    .then((reply: NodeBridgeReply): void => {
      if (!reply.ok) {
        hilog.warn(NODE_SCHED_LOG_DOMAIN, NODE_SCHED_LOG_TAG, 'cancel 回执失败 %{public}s',
          reply.error !== undefined ? reply.error : 'unknown');
      }
    })
    .catch((e: Error): void => {
      hilog.warn(NODE_SCHED_LOG_DOMAIN, NODE_SCHED_LOG_TAG, 'cancel 请求失败 %{public}s',
        errorMessageOf(e));
    });
}

// 会话/助手删除的 drop 接入点（任务书 §3.3 删除矩阵）：先撤回排队（代次递增），再直达 bootstrap
// 摘 worker（不经 lane）；运行时未启动按无害空操作回。
export async function dropNodeForConversation(conversationId: string,
  sessionId: string): Promise<NodeDropReceipt> {
  if (conversationId === '' || sessionId === '') {
    return { ok: false, error: '缺少会话标识，未发送 drop', stopped: false, workerTerminated: false };
  }
  const state: NodeConversationState | undefined = conversationStateOf(conversationId);
  if (state !== undefined) {
    state.generation++;
    denyWaitersForConversation(conversationId);
  }
  unbindActiveSession('exec', conversationId, sessionId);
  unbindActiveSession('install', conversationId, sessionId);
  const endpoint: NodeBridgeEndpoint | null = peekNodeEndpoint();
  if (endpoint === null) {
    return { ok: true, stopped: false, workerTerminated: false };
  }
  const fields: NodeBridgeRequestFields = { sessionId: sessionId };
  try {
    const reply: NodeBridgeReply =
      await requestNodeBridge(endpoint, 'drop', fields, NODE_CONTROL_RESPONSE_TIMEOUT_MS);
    if (!reply.ok) {
      return {
        ok: false,
        error: reply.error !== undefined && reply.error !== '' ? reply.error : 'drop 请求失败',
        stopped: false,
        workerTerminated: false
      };
    }
    return {
      ok: true,
      stopped: reply.stopped === true,
      workerTerminated: reply.dropped === true
    };
  } catch (e) {
    return {
      ok: false,
      error: 'Node 桥接不可用，' + errorMessageOf(e as Error),
      stopped: false,
      workerTerminated: false
    };
  }
}

// 状态查询（U4 探针与诊断入口）：只读 endpoint 与状态回执，不启动运行时、不进 lane。
export async function queryNodeStatus(): Promise<NodeStatusReceipt> {
  const endpoint: NodeBridgeEndpoint | null = peekNodeEndpoint();
  if (endpoint === null) {
    const notReady: NodeStatusReceipt = {
      ok: false,
      error: isNodeProcessStarted() ? '运行中端点丢失，请重启应用' : '运行时未启动'
    };
    return notReady;
  }
  const fields: NodeBridgeRequestFields = {};
  try {
    const reply: NodeBridgeReply =
      await requestNodeBridge(endpoint, 'status', fields, NODE_CONTROL_RESPONSE_TIMEOUT_MS);
    const receipt: NodeStatusReceipt = { ok: reply.ok };
    if (!reply.ok) {
      receipt.error = reply.error !== undefined && reply.error !== '' ? reply.error
        : 'status 请求失败';
      return receipt;
    }
    if (reply.channel !== undefined) {
      receipt.channel = reply.channel;
    }
    if (reply.nodeVersion !== undefined) {
      receipt.nodeVersion = reply.nodeVersion;
    }
    if (reply.npmVersion !== undefined) {
      receipt.npmVersion = reply.npmVersion;
    }
    if (reply.prepare !== undefined) {
      receipt.prepare = reply.prepare;
    }
    if (reply.prepareError !== undefined) {
      receipt.prepareError = reply.prepareError;
    }
    if (reply.prepareStats !== undefined) {
      receipt.prepareStats = reply.prepareStats;
    }
    if (reply.workers !== undefined) {
      receipt.workers = reply.workers;
    }
    if (reply.memory !== undefined) {
      receipt.memory = reply.memory;
    }
    return receipt;
  } catch (e) {
    return { ok: false, error: 'Node 桥接不可用，' + errorMessageOf(e as Error) };
  }
}

// install 单飞域出口与类型从本件再出口（import 后再出口，见文件头 import 段注释）
export { installNodePackages, NODE_INSTALL_DEFAULT_TIMEOUT_MS, NODE_INSTALL_MAX_TIMEOUT_MS,
  NodeInstallErrorKind, NodeInstallReceipt, NodeInstallRequest };
