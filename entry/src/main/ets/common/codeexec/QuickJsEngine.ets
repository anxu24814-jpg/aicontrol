// QuickJS 引擎实现（与瘦身后的 JsvmEngine 严格对称：run 直通 + cancel + 单例——竞速 /
// 取消标记 / 超时合成不在本件，编排面统一在 ScriptScheduler）。
// · 引擎能力差异（写明不外溢）：本引擎可被真实中断（超时 / 取消发生在 native 侧
//   interrupt handler——对外文案口径不变，超时句仍含「正在运行的脚本不保证被中断」
//   保守承诺，两引擎逐字一致，不软化）。
// · import 面：唯一 .so 装配在 ScriptEnginePick（本件是引擎本体）；types 契约 =
//   cpp/types/libqjsengine/index.d.ts（与 libcodeexec 字段级同构）。
import qjsExec from 'libqjsengine.so';
import { ScriptEngine, ScriptRunOptions, ScriptRunResult } from './ScriptEngine';

// 引擎单例（进程级一份——与 native 并发计数锁同进程域，照 JsvmEngine 形制）
let engineSingleton: QuickJsEngine | null = null;

export function quickJsEngine(): QuickJsEngine {
  if (engineSingleton === null) {
    engineSingleton = new QuickJsEngine();
  }
  return engineSingleton;
}

export class QuickJsEngine implements ScriptEngine {
  // 接口直通（裸调用，无竞速——编排面统一走调度器）
  run(code: string, opts: ScriptRunOptions): Promise<ScriptRunResult> {
    return qjsExec.runScript(code, opts);
  }

  // 取消请求（幂等；携 runKey 定向）：转发 native 标记（按 runKey 置位 + 定向唤醒该
  // runKey 阻塞中的网络桥等待——QjsRequestCancel 一口承担，他路在途请求不受扰）。
  // native 侧标记失败不阻断（调用方调度器兜底补 canceled 标志——照 JsvmEngine 先例的
  // 双标记容错语义）
  cancel(runKey: string): void {
    try {
      qjsExec.cancelRunning(runKey);
    } catch (e) {
      // native 侧标记失败不阻断调度器取消链（条目级标记仍在，结果兜底带 canceled）
    }
  }
}
