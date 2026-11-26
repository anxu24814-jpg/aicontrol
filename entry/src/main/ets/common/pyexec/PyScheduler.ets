// Python 串行执行 lane（门 4，方案 §2.4「Python 执行串行化」ArkTS 侧编排）。
// · 为何需要本件：native gExecMutex 已把 exec 全局串行，但排队若发生在 native 锁上，
//   会话停止无法撤回已排队的执行（cancel 只中断在跑一发）——把排队收在 ArkTS 侧后，
//   入队未跑的条目可按会话整批撤回，在跑的一发走协作式取消。
// · 满拒与等待上限（照 JS ScriptScheduler 同族数值：等待位 3 / 等待上限 30 秒——并发
//   槽恒 1，Python 无双跑）：队满即拒、排队到点放弃，两者都回中文回执原料、本次不执行。
// · 宽限竞速：native 看门狗到点只投递协作式中断，原生调用死握 GIL 时 promise 永不
//   settle（与 JS busy-lock 同族边界）。宽限 = 生效超时 + 15 秒，到点先交「放弃等待」
//   回执；native promise 在后台继续，后续调用照常排队（GIL 死锁极端面下进程内 Python
//   不可再救，重启应用恢复——如实告知，不假装已中断）。
// · import 面：只引 PyRuntime（outcome 契约 + cancelPyRun）；不引 @kit 供断言直跑。
import { PyExecOutcome, cancelPyRun } from './PyRuntime';

// lane 结果：ran=false 表示未进 native（busy / 排队取消 / 等待超时），outcome 为空、
// laneNote 为回执原料句；ran=true 时 outcome 为 native 结果（宽限超时形态 outcome 为空、
// laneNote 说明放弃等待）
export interface PyLaneResult {
  ran: boolean;
  outcome: PyExecOutcome | null;
  laneNote: string;
}

// 等待位上限（同时排队的 exec 数；超限立即拒绝）
export const PY_LANE_MAX_WAITING: number = 3;
// 排队等待上限（毫秒——到点放弃，本次不执行）
export const PY_LANE_WAIT_MAX_MS: number = 30000;
// 宽限余量（毫秒，加在生效超时之上——native 看门狗的协作式中断兜底面）
const PY_LANE_GRACE_MS: number = 15000;

// 队列条目（execFn 由发起方注入——lane 不感知落位/初始化编排，只管串行与撤回）
interface PyQueueEntry {
  conversationId: string;
  execFn: () => Promise<PyExecOutcome>;
  // 本次生效超时（毫秒）——宽限计时 = 它 + PY_LANE_GRACE_MS，只兜 GIL 死握面；
  // 固定 15 秒会把 15s~timeoutMs 之间的合法运行提前判死（2170 自检轮修）
  timeoutMs: number;
  canceled: boolean;
  started: boolean;
  resolve: (r: PyLaneResult) => void;
  waitTimerId: number;
}

// 进程级 lane 状态（模块单例——与 native 解释器同生命周期）
let pyQueue: PyQueueEntry[] = [];
let pyActiveConversation: string = '';
let pyActiveCancel: (() => void) | null = null;

// 推进：无在跑时从队首取条目执行（跳过已被撤回的条目——它们的 promise 已 resolve）
function pumpPyLane(): void {
  if (pyActiveConversation !== '') {
    return;
  }
  while (pyQueue.length > 0 && pyQueue[0].canceled) {
    pyQueue.shift();
  }
  if (pyQueue.length === 0) {
    return;
  }
  const entry: PyQueueEntry = pyQueue.shift() as PyQueueEntry;
  entry.started = true;
  clearTimeout(entry.waitTimerId); // 开跑即清等待计时器（started 守卫本可兜底，对称清防空转）
  pyActiveConversation = entry.conversationId;
  pyActiveCancel = (): void => {
    cancelPyRun();
  };
  const finish = (r: PyLaneResult): void => {
    pyActiveConversation = '';
    pyActiveCancel = null;
    entry.resolve(r);
    pumpPyLane();
  };
  // 宽限竞速：native settle 与宽限计时器赛跑（宽限 = 生效超时 + 15 秒，只兜 GIL 死握面，
  // 正常超时由 native 看门狗先到并回 TimeoutError）
  let graceTimerId: number = -1;
  const gracePromise: Promise<null> = new Promise<null>((resolveGrace): void => {
    graceTimerId = setTimeout((): void => {
      resolveGrace(null);
    }, entry.timeoutMs + PY_LANE_GRACE_MS);
  });
  Promise.race([entry.execFn(), gracePromise]).then((raced: PyExecOutcome | null): void => {
    clearTimeout(graceTimerId);
    if (raced === null) {
      finish({ ran: true, outcome: null,
        laneNote: '等待超过上限仍未结束，已放弃等待本次回执。中断是协作式的，脚本停在原生调用中时不能立即生效，后续 Python 调用会继续排队。' });
      return;
    }
    finish({ ran: true, outcome: raced, laneNote: '' });
  }).catch((): void => {
    clearTimeout(graceTimerId);
    // execFn 自身异常（native reject 等）：回执为「未在宽限内结束」同族的兜底句
    finish({ ran: true, outcome: null, laneNote: '执行异常结束，未取得结果。' });
  });
}

// 串行执行入口（唯一）：发起方注入 execFn（落位/初始化/exec 由调用方编排），lane 负责
// 排队、满拒、等待上限、会话撤回与宽限竞速
export function runPyBounded(conversationId: string, timeoutMs: number,
  execFn: () => Promise<PyExecOutcome>): Promise<PyLaneResult> {
  if (pyQueue.length >= PY_LANE_MAX_WAITING) {
    const busy: PyLaneResult = { ran: false, outcome: null,
      laneNote: 'Python 正在忙，等待位已满，本次调用没有执行，请稍后重新发起。' };
    return Promise.resolve(busy);
  }
  return new Promise<PyLaneResult>((resolve): void => {
    const entry: PyQueueEntry = {
      conversationId: conversationId,
      execFn: execFn,
      timeoutMs: timeoutMs,
      canceled: false,
      started: false,
      resolve: resolve,
      waitTimerId: -1
    };
    entry.waitTimerId = setTimeout((): void => {
      if (entry.started || entry.canceled) {
        return; // 已开跑或已撤回——等待计时器不再有语义
      }
      entry.canceled = true;
      resolve({ ran: false, outcome: null,
        laneNote: '排队等待超过 30 秒已放弃，本次调用没有执行，请稍后重新发起。' });
    }, PY_LANE_WAIT_MAX_MS);
    pyQueue.push(entry);
    pumpPyLane();
  });
}

// 会话级取消（挂 ToolRuntime 停链单点）：排队条目按会话整批撤回；在跑一发若属该会话则
// 协作式取消（结果由 native 回 Canceled，不在此处伪造）
export function cancelPyForConversation(conversationId: string): void {
  for (const entry of pyQueue) {
    if (!entry.canceled && !entry.started && entry.conversationId === conversationId) {
      entry.canceled = true;
      clearTimeout(entry.waitTimerId);
      entry.resolve({ ran: false, outcome: null, laneNote: '已取消，本次调用没有执行。' });
    }
  }
  // 撤回即移出队列（照 ScriptScheduler staying 形态——等待位立即释放；死条目滞留会把
  // 等待位占满，用户停后立即重发吃「等待位已满」满拒，直到在跑 settle 才自愈）
  pyQueue = pyQueue.filter((entry: PyQueueEntry): boolean => entry.started || !entry.canceled);
  if (pyActiveConversation === conversationId && pyActiveCancel !== null) {
    pyActiveCancel();
  }
}
