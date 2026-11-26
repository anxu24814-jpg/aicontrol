// 引擎装配与调度单例出口：全工程唯一的新 .so 装配位（「一行分派」的兑现点）。
// · 分派策略（引擎由用户开关 × 档位共同决定）：开关三值 auto（默认，严格档试验引擎 /
//   标准档系统引擎）/ quickjs（两档试验）/ jsvm（两档系统），脏值归 auto。判据单源 =
//   AppPreferences.codeWorkbenchUsesQuickJsEngine，本件只做单例映射；对外文案禁「可中断」
//   类表述（续守）。shell（模拟 Shell）恒 QuickJS——短路先于二维判定调用行，不消费引擎
//   键与档位。
// · 性能权衡注释（只记录不承诺——宪法「性能不许愿」）：两引擎均无 JIT（「禁第三方 JIT」
//   与「系统 JSVM 默认不开 JIT」双在案），立项原文「解释器比 JIT 慢 1~2 个量级」在鸿蒙
//   不直接适用；真实差以真机实测记录。权衡结论（= auto 默认映射的理由）：高频的标准档
//   留给系统 JSVM（工程优化更充分），低频的严格档换 QuickJS（拿可中断）——解释器开销由
//   「严格档更短时限 + 用户主动选择该档」吸收。
// · import 环纪律（坑50）：本件引两引擎与调度器（装配方向单向）；ScriptScheduler 及
//   下游零 import ToolRuntime / ToolTypes / ToolCodeExec——与现状链等价无新环。
import { ScriptEngine } from './ScriptEngine';
import { jsvmEngine } from './JsvmEngine';
import { quickJsEngine } from './QuickJsEngine';
import { ScriptScheduler } from './ScriptScheduler';
import { codeWorkbenchEngine, codeWorkbenchUsesQuickJsEngine } from '../AppPreferences';
import { SCRIPT_MODE_SHELL } from './ScriptLimits';

// 引擎分派：模拟 Shell 恒 QuickJS——旁路档位与用户引擎开关（shell 不消费引擎键），
// 本短路必须先于二维判定调用行；其余按「引擎开关 × 档位」二维分派（每运行提交时刻
// 现读，切换从下一次运行起生效；两引擎单例各由装配件持有）
function pickScriptEngine(mode: string): ScriptEngine {
  if (mode === SCRIPT_MODE_SHELL) {
    return quickJsEngine();
  }
  return codeWorkbenchUsesQuickJsEngine(mode, codeWorkbenchEngine()) ?
    quickJsEngine() : jsvmEngine();
}

let schedulerSingleton: ScriptScheduler | null = null;

// 调度域单例（进程级一份——与两引擎 native 忙锁的进程级单飞对齐）
export function scriptScheduler(): ScriptScheduler {
  if (schedulerSingleton === null) {
    schedulerSingleton = new ScriptScheduler(pickScriptEngine);
  }
  return schedulerSingleton;
}
