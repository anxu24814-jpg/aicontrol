// npm install 单飞调度域（2026-11-24 鸿蒙 Node 运行时门 3 U3 S2 拆分笔，任务书-鸿蒙Node运行时门3
// U3-binrunner-20261124 §5 S2）：从 NodeScheduler.ets 原样迁出的 install 单飞路径——
// installNodePackages + NodeInstall 三类型 + installReceiptFromReply（约 180 行整体搬迁）。
// 方法体原样搬迁，只把三个共享接缝改引 NodeSchedulerCore（代次表 / 准备单飞 / 宽限等待）。
// · 依赖（模块环零）：只引 Core、NodeBridge / NodeRuntime 与 NodeAdmin，不引 NodeScheduler。
// · lane 外单飞（门 3 U1 任务书 §2.1）：长操作占 30 s 排队上限不合适；同刻恰一个 install
//   （权威互斥在 Node 侧 bootstrap，本件镜像拒绝）；不改 lane 四参与 releaseLaneSlot，
//   install 与 exec 并存无共享临界区。
// · 顺序：①代次初查 → ②互斥镜像 → ③lane 外准备单飞 → ④代次复查 → ⑤install 请求（独立超时
//   + 宽限，经 responseTimeoutMs 覆写 60 s 兜底）→ ⑥终态映射。本函数在飞期间在 Core 的
//   activeInstallSession 登记（与 exec 的 activeExecSession 分表）；cancelNodeForConversation
//   两表都查，命中即递增代次并转调 bootstrap cancel，bootstrap 按 sessionId 命中 install 归属即
//   terminate，请求侧收 cancelled / dropped 终态。
// · 待重启守卫（门 4）：管理页清空安装包 / 重建运行区后旗置位（旗在 NodeAdmin），重启前 install
//   在参数校验之后、互斥镜像之前即拒——不置在飞位、不准备运行区、不发请求。NodeAdmin 不反向引
//   本件（会成环），「安装是否在飞」的只读口 nodeInstallInFlight 由本件出、管理页消费。
// ArkTS 不可本机执行：行为面（准备等待 / 取消 / 超时映射）待真机与断言覆盖，本笔只证源码结构
// 可核与构建绿，禁宣称已行为验证。
import { NodeBridgeMemory, NodeBridgeReply, NodeBridgeRequestFields,
  requestNodeBridge } from './NodeBridge';
import { NodeRuntimeStartOutcome } from './NodeRuntime';
import { nodeNeedsRestart, nodeRestartGuardText } from './NodeAdmin';
import { NodeConversationState, NODE_SESSION_ID_MAX_LENGTH, NodeReplyWait,
  awaitReplyWithGrace, bindActiveSession, ensureConversationState, errorMessageOf,
  prepareRuntimeOnce, releaseConversationState, unbindActiveSession } from './NodeSchedulerCore';

// ── install 规格（门 3 U1 任务书 §2.1：lane 外单飞；同刻恰一个 install（互斥在 Node 侧
// bootstrap，本件镜像拒绝）；响应兜底 = install 超时 + 宽限）──
export const NODE_INSTALL_DEFAULT_TIMEOUT_MS: number = 600000;
export const NODE_INSTALL_MAX_TIMEOUT_MS: number = 1800000;
const NODE_INSTALL_GRACE_EXTRA_MS: number = 15000;

// install 失败分类（U2 按此选文案；Node 回执透传时缺省，error 是 bootstrap 错误码）
export type NodeInstallErrorKind = 'no-session' | 'invalid-request' | 'runtime-unavailable'
  | 'install-running' | 'timeout' | 'bridge-unreachable' | 'cancelled' | 'internal-error';

// install 请求（门 3 U1；conversationId/sessionId = cancel/drop 归属键，specs 逐条 name@精确版本）
export interface NodeInstallRequest {
  conversationId: string;
  sessionId: string;
  specs: string[];
  timeoutMs?: number;
}

// install 回执（终态一请求一响应；packages = 每包摘要行，logTail = 有界日志尾。
// violations = 问题项（装后扫描命中的二进制文件；回滚未全部成功时改为未处理掉的项，≤10 条），
// cleanupNote = 清理附注单字段（安装前 / 终止后清扫计数、回滚失败说明、终止时日志尾部不可得））
export interface NodeInstallReceipt {
  ok: boolean;
  errorKind?: NodeInstallErrorKind;
  error?: string;
  cancelled?: boolean;
  exitCode: number;
  errorCode?: string;
  errorDetail?: string;
  stage: string;
  logTail: string[];
  packages: string[];
  packagesTotal: number;
  packagesTruncated: boolean;
  wasmNote: string;
  rolledBack: boolean;
  violations?: string[];
  cleanupNote?: string;
  elapsedMs: number;
  nodeVersion: string;
  platform: string;
  memory?: NodeBridgeMemory;
}

// install 互斥镜像（同刻恰一个 install；权威互斥在 Node 侧 bootstrap，这里提前拒给调用方即时回执）
let installPending: boolean = false;

// install 是否在飞的只读口（门 4 管理页消费：「清空安装包」在安装进行中不许做——会删到装了一半的
// 安装区）。只读不置位，互斥判定仍只认 installPending
export function nodeInstallInFlight(): boolean {
  return installPending;
}

function emptyInstallReceipt(): NodeInstallReceipt {
  return {
    ok: false,
    exitCode: 1,
    stage: '',
    logTail: [],
    packages: [],
    packagesTotal: 0,
    packagesTruncated: false,
    wasmNote: '',
    rolledBack: false,
    elapsedMs: 0,
    nodeVersion: '',
    platform: ''
  };
}

function installFailure(kind: NodeInstallErrorKind, message: string): NodeInstallReceipt {
  const receipt: NodeInstallReceipt = emptyInstallReceipt();
  receipt.errorKind = kind;
  receipt.error = message;
  return receipt;
}

// Node install 回执透传（缺字段保默认值；error 码映射调度层分类，cancelled/dropped 标取消）
function installReceiptFromReply(reply: NodeBridgeReply): NodeInstallReceipt {
  const receipt: NodeInstallReceipt = emptyInstallReceipt();
  receipt.ok = reply.ok;
  if (reply.error !== undefined && reply.error !== '') {
    receipt.error = reply.error;
    receipt.cancelled = reply.error === 'cancelled' || reply.error === 'dropped';
    if (reply.error === 'not-ready' || reply.error === 'prepare-failed') {
      receipt.errorKind = 'runtime-unavailable';
    } else if (reply.error === 'bad-request') {
      receipt.errorKind = 'invalid-request';
    } else if (reply.error === 'install-running') {
      receipt.errorKind = 'install-running';
    } else if (reply.error === 'timeout') {
      receipt.errorKind = 'timeout';
    }
  }
  if (reply.exitCode !== undefined) {
    receipt.exitCode = reply.exitCode;
  }
  if (reply.errorCode !== undefined) {
    receipt.errorCode = reply.errorCode;
  }
  if (reply.errorDetail !== undefined) {
    receipt.errorDetail = reply.errorDetail;
  }
  if (reply.stage !== undefined) {
    receipt.stage = reply.stage;
  }
  if (reply.logTail !== undefined) {
    receipt.logTail = reply.logTail;
  }
  if (reply.packages !== undefined) {
    receipt.packages = reply.packages;
  }
  if (reply.packagesTotal !== undefined) {
    receipt.packagesTotal = reply.packagesTotal;
  }
  if (reply.packagesTruncated !== undefined) {
    receipt.packagesTruncated = reply.packagesTruncated;
  }
  if (reply.wasmNote !== undefined) {
    receipt.wasmNote = reply.wasmNote;
  }
  if (reply.rolledBack !== undefined) {
    receipt.rolledBack = reply.rolledBack;
  }
  if (reply.violations !== undefined) {
    receipt.violations = reply.violations;
  }
  if (reply.cleanupNote !== undefined) {
    receipt.cleanupNote = reply.cleanupNote;
  }
  if (reply.elapsedMs !== undefined) {
    receipt.elapsedMs = reply.elapsedMs;
  }
  if (reply.nodeVersion !== undefined) {
    receipt.nodeVersion = reply.nodeVersion;
  }
  if (reply.platform !== undefined) {
    receipt.platform = reply.platform;
  }
  if (reply.memory !== undefined) {
    receipt.memory = reply.memory;
  }
  return receipt;
}

// install 唯一进口（U2 工具面消费）：校验 → 互斥 → 准备单飞（lane 外）→ 请求 → 终态回执
export async function installNodePackages(req: NodeInstallRequest): Promise<NodeInstallReceipt> {
  const conversationId: string = typeof req.conversationId === 'string' ? req.conversationId : '';
  const sessionId: string = typeof req.sessionId === 'string' ? req.sessionId : '';
  if (conversationId === '' || sessionId === '') {
    return installFailure('no-session', '缺少会话标识，未启动 npm 安装');
  }
  if (sessionId.length > NODE_SESSION_ID_MAX_LENGTH) {
    return installFailure('invalid-request', '会话标识超长，未启动 npm 安装');
  }
  if (!Array.isArray(req.specs) || req.specs.length === 0) {
    return installFailure('invalid-request', '安装清单为空，未执行 npm 安装');
  }
  let timeoutMs: number = NODE_INSTALL_DEFAULT_TIMEOUT_MS;
  if (req.timeoutMs !== undefined) {
    const requested: number = req.timeoutMs;
    if (Math.round(requested) !== requested || requested <= 0
      || requested > NODE_INSTALL_MAX_TIMEOUT_MS) {
      return installFailure('invalid-request', '安装超时取值需在 1 毫秒至 '
        + (NODE_INSTALL_MAX_TIMEOUT_MS / 60000) + ' 分钟之间，未执行');
    }
    timeoutMs = requested;
  }
  if (nodeNeedsRestart()) {
    return installFailure('runtime-unavailable', nodeRestartGuardText());
  }
  if (installPending) {
    return installFailure('install-running', 'install 进行中，请稍后再试');
  }
  const state: NodeConversationState = ensureConversationState(conversationId);
  state.inFlight++;
  const generation: number = state.generation;
  installPending = true;
  try {
    if (state.generation !== generation) {
      return installFailure('cancelled', '已取消'); // ① 初查（同步段内不会变，契约锚点同 exec）
    }
    // ③ 准备单飞在 lane 外（同 exec ②：不占执行位、不占等待位、不计排队上限）
    let prepared: NodeRuntimeStartOutcome;
    try {
      prepared = await prepareRuntimeOnce();
    } catch (e) {
      return installFailure('runtime-unavailable', errorMessageOf(e as Error));
    }
    if (state.generation !== generation) {
      return installFailure('cancelled', '已取消'); // ④ 准备期取消：不执行
    }
    const graceMs: number = timeoutMs + NODE_INSTALL_GRACE_EXTRA_MS;
    const fields: NodeBridgeRequestFields = {
      sessionId: sessionId,
      specs: req.specs,
      timeoutMs: timeoutMs
    };
    bindActiveSession('install', conversationId, sessionId);
    try {
      const pending: Promise<NodeBridgeReply> =
        requestNodeBridge(prepared.endpoint, 'install', fields, graceMs);
      const waited: NodeReplyWait = await awaitReplyWithGrace(pending, graceMs);
      if (waited.timedOut) {
        return installFailure('timeout', '等待 npm 安装超时，已释放执行位');
      }
      if (waited.failure !== '') {
        return installFailure('bridge-unreachable', waited.failure);
      }
      if (waited.reply === null) {
        return installFailure('bridge-unreachable', '未收到回执');
      }
      return installReceiptFromReply(waited.reply);
    } finally {
      unbindActiveSession('install', conversationId, sessionId);
    }
  } catch (e) {
    return installFailure('internal-error', 'npm 安装调度异常，' + errorMessageOf(e as Error));
  } finally {
    installPending = false;
    releaseConversationState(conversationId, state);
  }
}
