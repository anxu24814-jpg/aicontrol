// JSVM 引擎实现：import 系统自带 libjsvm 的 napi 桥（libcodeexec.so）。
// · 引擎能力与语义（不得被任何文案或实现软化）：本平台 JSVM 无中断 API（jsvm.h 实读零
//   Terminate 类导出）⇒ 超时后忙锁保持（native Promise 真正 settle 时才释放）；取消仅
//   协作标记。正在运行的脚本不保证被中断——对外文案与帮助条目禁出现「可中断」「随时
//   停止」类表述。超时竞速与取消编排已上移调度域 ScriptScheduler（跨引擎单点，含沙箱
//   网络桥三接线）；本件只留引擎本体 run 直通 + cancel + 单例。native 忙锁（进程级原子
//   布尔）保留为纵深防线——绕过调度器的直调仍被防；本引擎超时后忙锁保持到脚本自然结束
//  （QuickJS 侧可真中断，如实差异——分派按档位见 ScriptEnginePick）。
// · 取消：cancel(runKey) 调 native cancelRunning（按 runKey 查注册表命中才置位——无命中
//   不置位返 false）。桥放弃态由调度域统一置。不做跨线程强杀（无此能力，勿发明）。
// · VM 生命周期：每次执行 native 侧新建 VM+Env、执行完销毁（jsvm_runner.cpp），本类不持
//   VM 状态——失败后再执行正确性由该设计承担。
// · native 侧新增面（二进制读写 / 预置环境 / zlib 与哈希桥 / Promise 末值）对 ArkTS 消费
//   面零影响——同一 run(code, opts) 契约；新增 flags 值（'promise-pending' /
//   'prelude-failed'）装配层原样保留不消费。
import codeExec from 'libcodeexec.so';
import { ScriptEngine, ScriptRunOptions, ScriptRunResult } from './ScriptEngine';

// 引擎单例（进程级一份——与 native 并发计数锁同进程域，照 K 池形制）
let engineSingleton: JsvmEngine | null = null;

export function jsvmEngine(): JsvmEngine {
  if (engineSingleton === null) {
    engineSingleton = new JsvmEngine();
  }
  return engineSingleton;
}

export class JsvmEngine implements ScriptEngine {
  // 接口直通（裸调用，无竞速——编排面统一走 ScriptScheduler；断言与探针可用本口）
  run(code: string, opts: ScriptRunOptions): Promise<ScriptRunResult> {
    return codeExec.runScript(code, opts);
  }

  // 取消请求（幂等——重复调无害；携 runKey 定向）：调 native cancelRunning（查注册表
  // 命中才置位——无命中窗口的取消请求不滞留）。桥放弃态由调度域统一置（编排面单点，
  // 本件不重复置）
  cancel(runKey: string): void {
    try {
      codeExec.cancelRunning(runKey);
    } catch (e) {
      // native 侧标记失败不阻断（消费位在调度器，结果兜底带 canceled 标志）
    }
  }
}
