// Node 执行域共享基元（2026-11-24 鸿蒙 Node 运行时门 3 U3 S2 拆分笔，任务书-鸿蒙Node运行时门3
// U3-binrunner-20261124 §5 S2）：从 NodeScheduler.ets 原样迁出的三件共享基元——运行区准备单飞
// （ensureNodeRuntimePlacement + startNodeRuntime 合成一个共享 promise）、会话代次表（含在跑
// 登记 exec / install 分域两表）、回执宽限等待（awaitReplyWithGrace）。exec lane 域与 install
// 单飞域都引本件，本件不引任一方（模块环零：Core ← Install ← Scheduler）。
// · 准备单飞（lane 外）：并发调用只跑一趟、不重复启动；settle 即清，失败后下次重试。准备
//   不占执行位、不占等待位、不计 30 s 排队上限（§0 代决表）。
// · 会话代次：每 conversationId 一份 { generation, inFlight }；代次快照在调用进入时取。
//   cancelNodeForConversation 只递增代次（并把在跑请求转给 bootstrap cancel），不 await、
//   不占 lane。表只在飞（inFlight 归零即删），无界增长防线。
// · 在跑登记分域两表（Y1 修正）：exec 与 install 允许同会话并存（方案档 ⑥），旧实现把两者
//   都写进同一张 conversationId → sessionId 表、按「值相等」清理——先结束者会把后结束者的
//   登记摘掉，后者点停止就只递增代次、不发 bootstrap cancel（install / exec 继续跑完并按成功
//   回执）。分表后各摘各的；cancel 两表都查，同 sessionId 只发一次 cancel。
// · 宽限（awaitReplyWithGrace）：宽限先到即结算（timedOut = true），迟到回执由桥接侧 cleanup
//   丢弃；failure 非空 = 桥接层失败；reply 非空 = 真回执。
// · 非目标（P2-4）：本件不碰数据库、不建临时区、不写文件、不定义工具卡与 desc；token 只经
//   NodeBridge 的 endpoint 传递，本件零 token 日志零回显。
// ArkTS 不可本机执行：三面行为（准备单飞 / 代次 / 宽限）待真机与断言覆盖，本笔只证源码结构
// 可核与构建绿，禁宣称已行为验证。
import { NodeBridgeReply } from './NodeBridge';
import { ensureNodeRuntimePlacement, startNodeRuntime,
  NodeRuntimeStartOutcome } from './NodeRuntime';

// sessionId 长度上限（与 bootstrap SESSION_ID_MAX_LENGTH 同源：只防无界 map 键）
export const NODE_SESSION_ID_MAX_LENGTH: number = 200;

// 在跑登记域（exec 与 install 分表；cancel 两表都查）
export type NodeActiveDomain = 'exec' | 'install';

// 会话 lane 状态（代次 + 在飞计数；在飞归零即从表里删，见文件头）
export interface NodeConversationState {
  generation: number;
  inFlight: number;
}

// 回执等待结果（timedOut = 宽限先到；failure 非空 = 桥接层失败；reply 非空 = 真回执）
export interface NodeReplyWait {
  reply: NodeBridgeReply | null;
  timedOut: boolean;
  failure: string;
}

// ── 模块状态（ArkTS 主线程单线程：状态迁移无竞态，唯一异步边界是 promise settle）──

const conversationStates: Map<string, NodeConversationState> =
  new Map<string, NodeConversationState>();
// 在跑登记分域两表（Y1 修正，见文件头）：exec 与 install 各摘各的
const activeExecSession: Map<string, string> = new Map<string, string>();
const activeInstallSession: Map<string, string> = new Map<string, string>();
let prepareFlight: Promise<NodeRuntimeStartOutcome> | null = null;

// ── 小工具 ──

export function errorMessageOf(e: Error): string {
  const message: string | undefined = (e as Error).message;
  return message !== undefined && message !== '' ? message : '未知错误';
}

// ── 会话代次表 ──

export function ensureConversationState(conversationId: string): NodeConversationState {
  const existing: NodeConversationState | undefined = conversationStates.get(conversationId);
  if (existing !== undefined) {
    return existing;
  }
  const created: NodeConversationState = { generation: 0, inFlight: 0 };
  conversationStates.set(conversationId, created);
  return created;
}

// 只读取表（cancel / drop 用；不动引用计数）
export function conversationStateOf(conversationId: string): NodeConversationState | undefined {
  return conversationStates.get(conversationId);
}

// 结算一份在飞（inFlight 归零且表项仍是自己才删——防删掉后来者的新表项）
export function releaseConversationState(conversationId: string,
  state: NodeConversationState): void {
  state.inFlight--;
  if (state.inFlight <= 0 && conversationStates.get(conversationId) === state) {
    conversationStates.delete(conversationId);
  }
}

// ── 在跑登记（exec / install 分域两表）──

export function bindActiveSession(domain: NodeActiveDomain, conversationId: string,
  sessionId: string): void {
  if (domain === 'exec') {
    activeExecSession.set(conversationId, sessionId);
  } else {
    activeInstallSession.set(conversationId, sessionId);
  }
}

// 按域摘除（幂等：值不等说明已被后来者改写，不动）
export function unbindActiveSession(domain: NodeActiveDomain, conversationId: string,
  sessionId: string): void {
  const table: Map<string, string> = domain === 'exec' ? activeExecSession : activeInstallSession;
  if (table.get(conversationId) === sessionId) {
    table.delete(conversationId);
  }
}

// cancel 的终止目标集（exec 先、install 后，同 sessionId 只留一次）
export function activeSessionTargets(conversationId: string): string[] {
  const targets: string[] = [];
  const execSession: string | undefined = activeExecSession.get(conversationId);
  if (execSession !== undefined) {
    targets.push(execSession);
  }
  const installSession: string | undefined = activeInstallSession.get(conversationId);
  if (installSession !== undefined && targets.indexOf(installSession) < 0) {
    targets.push(installSession);
  }
  return targets;
}

// ── 准备单飞（落位 + 启动合成一个共享 promise；settle 即清，失败后下次重试）──

async function prepareRuntimeInner(): Promise<NodeRuntimeStartOutcome> {
  await ensureNodeRuntimePlacement();
  return startNodeRuntime();
}

export async function prepareRuntimeOnce(): Promise<NodeRuntimeStartOutcome> {
  if (prepareFlight !== null) {
    return prepareFlight;
  }
  const task: Promise<NodeRuntimeStartOutcome> = prepareRuntimeInner();
  prepareFlight = task;
  try {
    return await task;
  } finally {
    if (prepareFlight === task) {
      prepareFlight = null;
    }
  }
}

// ── 回执宽限（单点：宽限先到即结算，迟到回执由桥接侧 cleanup 丢弃）──

export function awaitReplyWithGrace(pending: Promise<NodeBridgeReply>,
  graceMs: number): Promise<NodeReplyWait> {
  return new Promise<NodeReplyWait>((resolve: (value: NodeReplyWait) => void): void => {
    let settled: boolean = false;
    let timerId: number = -1;
    const finish = (outcome: NodeReplyWait): void => {
      if (settled) {
        return;
      }
      settled = true;
      if (timerId >= 0) {
        clearTimeout(timerId);
        timerId = -1;
      }
      resolve(outcome);
    };
    timerId = setTimeout((): void => {
      timerId = -1;
      finish({ reply: null, timedOut: true, failure: '' });
    }, graceMs);
    pending.then((reply: NodeBridgeReply): void => {
      finish({ reply: reply, timedOut: false, failure: '' });
    }).catch((e: Error): void => {
      finish({ reply: null, timedOut: false, failure: errorMessageOf(e) });
    });
  });
}
