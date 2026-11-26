// 脚本调度域。职责一句话 = 「跨引擎唯一进口：有界排队 + 会话归属取消 + 超时竞速与到点
// 引擎取消 + settle 驱动队列推进」（竞速与取消编排自 JsvmEngine.runBounded 上移至此，桥的
// 运行上下文三接线与竞速编排同址）。
// · 单槽 → K 槽全局池（SCRIPT_MAX_CONCURRENT = 2，同引擎可并发、会话内/间同池、无按会话
//   配额）；队列原样复用（等待位 3、30s 上限、队满回忙锁句、settle 驱动全不变）；取消与
//   桥上下文按 runKey 定向（startEntry 注入）。
// · ★ 队列推进时机 = native 真实结束（settle 驱动，核心判据）：running 的清空与推进不挂
//   在回执交付上，而挂 enginePromise 的 settle 上——平台事实是 JSVM 超时后 native 忙锁
//   仍被占（超时只提前交付回执），若按「交付即推进」被推进的下一条目会立刻吃 native
//   忙锁的 BusyError 与排队语义矛盾。settle 驱动下：严格档（QuickJS）被真中断 → settle
//   秒级 → 排队者很快轮到；标准档（JSVM）死循环 → 排队者持续等待（不被假忙句打断），
//   直到前脚本 natural 结束或各自等待上限到点。语义分层：回执可早于 native 结束交付
//   （超时 / 取消），槽位释放与推进必须等 settle。
// · 会话归属：条目带 conversationId（自 httpCtx 透传），取消只命中本会话的在跑与排队
//   条目（不误杀他会话）。
// · 并发与正确性：ArkTS 主线程单线程——状态迁移无竞态；唯一异步边界 = native worker
//   结果回主线程（条目状态在回程时重查）。
// · import 面：零 @kit、零 .so（引擎经构造注入；桥函数为普通模块函数——断言直跑时剥
//   import 行后由桩替身承接）。为何不并入 JsvmEngine / ToolCodeExec（反碎片下限②）：前者
//   是引擎实现（调度与引擎实现职责缝不同），后者是工具执行器（并入会把 .so 装配与工具面
//   混居且断言无法直跑）。
import { ScriptEngine, ScriptRunOptions, ScriptRunResult } from './ScriptEngine';
import { ScriptHttpRunContext, enterScriptHttpRun, abandonScriptHttpRun,
  exitScriptHttpRun } from './ScriptHttpBridge';
import { SCRIPT_ERROR_BUSY } from './ScriptReceipt';

// ArkTS 侧标志：计时器先到（自 JsvmEngine 迁入——**唯一来源**，消费位 ToolCodeExec）
export const SCRIPT_FLAG_DEADLINE_HIT: string = 'deadline-hit';

// ★ 并发槽数 K（全局单池、同引擎可并发；代决默认值可翻——真机实测不支持则回 1 止血：
// 改本常量 + desc 并发句随形删，断言判据读本常量推导、K=1 自动退化恒绿）。native 两 so
// 各有同名上限常量作纵深防线（值同源声明，ArkTS 调度器是唯一编排闸）
export const SCRIPT_MAX_CONCURRENT: number = 2;

// 有界等待位上限（不含正在执行者；K 跑 + 3 等 = 系统内最多 K+3 个任务）
export const SCRIPT_QUEUE_MAX_WAITING: number = 3;
// 单等待条目上限毫秒（到点移出并回忙锁句——必须有上限兜底：JSVM 死循环占锁时等待者
// 不无限悬挂；≈ 3 个满编标准档时长）
export const SCRIPT_QUEUE_WAIT_MAX_MS: number = 30 * 1000;

// runKey 序号单源（调度器内自增 + 's' 前缀——防与 callId / runId 形态混淆；区别于
// httpCtx.runId〔会话运行轮 id，同轮并行 exec 会撞键〕——注入 opts.runKey 供 native
// per-run 取消定向）
let runKeySeq: number = 0;

function nextRunKey(): string {
  runKeySeq += 1;
  return 's' + runKeySeq;
}

// 引擎选择注入类型（返回含 cancel() 的引擎接口——分派实现在 ScriptEnginePick）
export type ScriptEnginePicker = (mode: string) => ScriptEngine;

// 空结果骨架（自 JsvmEngine 迁入；合成路径用——字段语义见 ScriptEngine.ets）
function emptyScriptRunResult(): ScriptRunResult {
  return {
    ok: false, value: '', logs: [], errorName: '', errorMessage: '',
    errorStack: '', durationMs: 0, flags: [], savedNames: [],
    outputFileName: '', outputBytes: 0, outputHead: '', outputTail: ''
  };
}

// 队列条目（在跑与排队同构；cancelled 为条目级取消标记——替代旧全局取走式标记，无滞留；
// runKey = 本条目的 per-run 取消目标键，startEntry 置槽前注入）
interface SchedulerEntry {
  code: string;
  opts: ScriptRunOptions;
  mode: string;
  conversationId: string;
  engine: ScriptEngine;
  httpCtx: ScriptHttpRunContext;
  resolve: (r: ScriptRunResult) => void;
  waitTimerId: number; // 排队等待计时器（-1 = 未挂）
  queuedAt: number;    // 入队时刻（Date.now——轮到时超限兜底判定；直跑路径 0 = 不判）
  cancelled: boolean;
  runKey: string;
}

export class ScriptScheduler {
  private readonly engineOf: ScriptEnginePicker;
  // ★ 单槽 → K 槽数组（长度 ≤ SCRIPT_MAX_CONCURRENT；settle 驱动与 FIFO 语义不变——
  // 任一槽 settle 即推进队首）
  private running: SchedulerEntry[] = [];
  private waiting: SchedulerEntry[] = [];
  private advancing: boolean = false; // 单次推进防重（防御位——主线程单线程下理论不可达）

  constructor(engineOf: ScriptEnginePicker) {
    this.engineOf = engineOf;
  }

  // 竞速执行（唯一进口；超时 / 取消 / 失败 / 排队满 / 等待超时五路全返回结构化结果，
  // 不抛给工具轮——照 JsvmEngine.runBounded 原语义扩排队面）
  runBounded(code: string, opts: ScriptRunOptions, mode: string,
    httpCtx: ScriptHttpRunContext): Promise<ScriptRunResult> {
    const engine: ScriptEngine = this.engineOf(mode);
    return new Promise<ScriptRunResult>((resolve: (r: ScriptRunResult) => void) => {
      const entry: SchedulerEntry = {
        code: code, opts: opts, mode: mode,
        conversationId: httpCtx.conversationId, engine: engine, httpCtx: httpCtx,
        resolve: resolve, waitTimerId: -1, queuedAt: 0, cancelled: false, runKey: ''
      };
      if (this.running.length >= SCRIPT_MAX_CONCURRENT || this.waiting.length > 0) {
        if (this.waiting.length >= SCRIPT_QUEUE_MAX_WAITING) {
          // 队列满：立即回忙锁句（BusyError 形态——句由 ScriptReceipt 单源）
          resolve(this.busyResult());
          return;
        }
        // 入队 FIFO + 起等待计时器（到点且仍在队 → 移出回忙锁句）
        entry.queuedAt = Date.now();
        this.waiting.push(entry);
        entry.waitTimerId = setTimeout((): void => {
          const idx: number = this.waiting.indexOf(entry);
          if (idx < 0) {
            return; // 已被取消移出或已出队启动——迟到到点 no-op
          }
          this.waiting.splice(idx, 1);
          resolve(this.busyResult());
        }, SCRIPT_QUEUE_WAIT_MAX_MS);
        return;
      }
      this.startEntry(entry);
    });
  }

  // 会话取消（挂 ToolRuntime.cancelAllPending 停链单点）：命中在跑条目 → 置条目标记 +
  // 桥放弃态 + 引擎 cancel（遍历 K 个在跑槽，本会话的**每条**都定向取消——runKey 各异
  // 互不误伤）；命中排队条目 → 逐条移出回取消结果；均无命中 → no-op 不置任何标记（条目
  // 级归属，无全局取走式标记滞留）
  cancelForConversation(conversationId: string): void {
    if (conversationId === '') {
      return; // 空会话 id fail-safe（照 ToolRuntime.cancelAllPending 口径）
    }
    for (const entry of this.running) {
      if (entry.conversationId === conversationId) {
        entry.cancelled = true;
        abandonScriptHttpRun(entry.runKey, 'canceled');
        entry.engine.cancel(entry.runKey);
      }
    }
    const staying: SchedulerEntry[] = [];
    for (const entry of this.waiting) {
      if (entry.conversationId === conversationId) {
        if (entry.waitTimerId >= 0) {
          clearTimeout(entry.waitTimerId);
          entry.waitTimerId = -1;
        }
        entry.resolve(this.canceledResult());
      } else {
        staying.push(entry);
      }
    }
    this.waiting = staying;
  }

  // ── 内部：启动与推进 ──

  private busyResult(): ScriptRunResult {
    const r: ScriptRunResult = emptyScriptRunResult();
    r.errorName = SCRIPT_ERROR_BUSY;
    return r;
  }

  private canceledResult(): ScriptRunResult {
    const r: ScriptRunResult = emptyScriptRunResult();
    r.flags = ['canceled'];
    return r;
  }

  private startEntry(entry: SchedulerEntry): void {
    if (entry.waitTimerId >= 0) {
      clearTimeout(entry.waitTimerId);
      entry.waitTimerId = -1;
    }
    if (entry.cancelled) {
      entry.resolve(this.canceledResult());
      this.advanceQueue();
      return;
    }
    if (entry.queuedAt > 0 && Date.now() - entry.queuedAt > SCRIPT_QUEUE_WAIT_MAX_MS) {
      // 轮到时等待已超上限（计时器延迟形态的兜底）——回忙锁句不启动
      entry.resolve(this.busyResult());
      this.advanceQueue();
      return;
    }
    // runKey 注入（置槽前生成——本条目的 per-run 取消目标键，随 opts 下传 native 注册表、
    // 随桥 enter 进 per-run 槽）
    entry.runKey = nextRunKey();
    entry.opts.runKey = entry.runKey;
    this.running.push(entry);
    // 桥接线①：进入置上下文（顺带一次性装 dispatcher——先于任何脚本执行；键 = runKey）
    enterScriptHttpRun(entry.httpCtx, entry.runKey);
    const enginePromise: Promise<ScriptRunResult> = entry.engine.run(entry.code, entry.opts)
      .catch((e: Object): ScriptRunResult => {
        // so 调用层异常（加载失败 / napi 抛错）→ 合成 engine-error 形态（恒有 catch 保
        // settle 驱动可达）
        const failed: ScriptRunResult = emptyScriptRunResult();
        const msg: string | undefined = (e as Error).message;
        failed.errorMessage = typeof msg === 'string' && msg !== '' ? msg : 'native 调用异常';
        return failed;
      });
    let timerId: number = -1;
    const timerPromise: Promise<ScriptRunResult> = new Promise<ScriptRunResult>(
      (resolve: (value: ScriptRunResult) => void) => {
        timerId = setTimeout((): void => {
          // 桥接线②：超时置放弃态（超时后脚本再调 httpGet 立即失败零请求——按 runKey 置
          // 本条目的槽，他路不受扰）
          abandonScriptHttpRun(entry.runKey, 'timeout');
          // 到点触发引擎取消：QuickJS 经 interrupt handler 真中断、计数秒级释放；JSVM
          // 照旧协作标记（结果丢弃、忙锁等 natural 结束——如实差异）
          entry.engine.cancel(entry.runKey);
          const hit: ScriptRunResult = emptyScriptRunResult();
          hit.flags = [SCRIPT_FLAG_DEADLINE_HIT];
          resolve(hit);
        }, entry.opts.timeoutMs);
      });
    // settle 驱动（核心判据）：running 清空与队列推进挂 enginePromise 的 settle，不挂
    // 回执交付——见件头注释的语义分层
    enginePromise.then((): void => { this.onEngineSettle(entry); },
      (): void => { this.onEngineSettle(entry); });
    // race 回调只管回执交付（clearTimeout + 取消兜底补标志 + resolve）——桥清理不在
    // 此处：race 由 enginePromise 胜出时本回调按注册序排在 onEngineSettle 之后，若在
    // 这里清槽会把 onEngineSettle→advanceQueue 刚为下一条目置好的上下文清空（排队
    // 条目 httpGet 全灭）。清槽挂 onEngineSettle（桥接线③），时机与语义见彼处注释。
    Promise.race([enginePromise, timerPromise]).then((winner: ScriptRunResult): void => {
      clearTimeout(timerId);
      // 取消兜底：条目被取消过且结果未带 canceled → 补标志（保证取消结果形态单源，
      // ToolCodeExec 只判 flags）
      if (entry.cancelled && winner.flags.indexOf('canceled') < 0) {
        winner.flags = winner.flags.concat(['canceled']);
      }
      entry.resolve(winner);
    });
  }

  private onEngineSettle(entry: SchedulerEntry): void {
    if (this.running.indexOf(entry) < 0) {
      return; // 守卫：非当前在跑条目（防御位——settle 恒一次，此处防错位）
    }
    // 桥接线③：引擎真实结束（settle）时清上下文——running 守卫保证每条目恰一次清槽，
    // 且先于 advanceQueue（排队条目 startEntry 置新上下文前旧槽已清）。防悬垂——迟到
    // dispatch 走「上下文缺失」失败支。计时器先到路径（超时 / 取消后引擎未 settle）槽
    // 暂留但放弃态已兜住零请求，settle 到点在此补清
    exitScriptHttpRun(entry.runKey);
    const idx: number = this.running.indexOf(entry);
    this.running.splice(idx, 1);
    this.advanceQueue();
  }

  private advanceQueue(): void {
    if (this.advancing) {
      return;
    }
    this.advancing = true;
    try {
      while (this.running.length < SCRIPT_MAX_CONCURRENT && this.waiting.length > 0) {
        const next: SchedulerEntry = this.waiting.shift() as SchedulerEntry;
        this.startEntry(next);
        // startEntry 对已取消 / 超限条目直接 resolve 不占槽 → 循环继续下一条
      }
    } finally {
      this.advancing = false;
    }
  }
}
