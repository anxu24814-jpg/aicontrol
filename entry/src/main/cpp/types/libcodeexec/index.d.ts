// 代码工作台 JSVM 桥——ArkTS 侧类型声明（契约单一来源；与 common/codeexec/ScriptEngine.ets
// 同构，改名须同步三处：本文件 / ScriptEngine.ets / JsvmEngine.ets——任务书 §3.1-4）。
// ★ 2026-10-06 代码工作台笔A：新增沙箱内能力（fs 七方法 / 预置 Web API / zlib 与哈希桥 /
// Promise 末值）为沙箱内 JS 面、不跨 napi 边界，本文件字段与 ScriptEngine.ets 恒同构；
// flags 值域以 ScriptEngine.ets 注释为枚举源。
// 字段语义与单源：
// · workspaceRoot ← WorkspaceTmpUtil.workspaceTmpConversationDir（会话临时区绝对路径）
// · timeoutMs / maxHeapBytes / maxOutputChars ← ScriptLimits.ets 档位映射
// · tmpMaxFileBytes / tmpMaxTotalBytes ← WorkspaceTmpUtil.ets 两闸（C++ 禁抄值）
// · outputFileName ← ArkTS 生成并过名称闸后下发（native 禁自造名）
// · httpWaitMs ← 沙箱网络桥等待上限（★ 2026-10-06 代码工作台笔E——ArkTS 侧算好下传
//   〔算式单源 ScriptHttpBridge.ets 的 scriptHttpWaitMs〕，native 零字面值；必填）
// · runKey ← ★ 2026-10-20 并发笔（方案 §R U1）：native per-run 取消目标键——调度器
//   注入，调用方不填；区别于 httpCtx.runId（会话运行轮 id，同轮并行 exec 会撞键，
//   不得复用）；native 侧宽容缺省空串
export interface ScriptRunOptions {
  workspaceRoot: string;
  timeoutMs: number;
  maxHeapBytes: number;
  maxOutputChars: number;
  maxLogLines: number;
  tmpMaxFileBytes: number;
  tmpMaxTotalBytes: number;
  outputFileName: string;
  httpWaitMs: number;
  runKey?: string;
}

export interface ScriptRunResult {
  ok: boolean;
  value: string;
  logs: string[];
  errorName: string;
  errorMessage: string;
  errorStack: string;
  durationMs: number;
  flags: string[];
  savedNames: string[];
  outputFileName: string;
  outputBytes: number;
  outputHead: string;
  outputTail: string;
}

export const runScript: (code: string, options: ScriptRunOptions) => Promise<ScriptRunResult>;
// ★ 2026-10-20 并发笔（方案 §R U1）：取消按 runKey 定向——返值 = 是否有**该目标**在跑脚本
// 被标记取消；无命中回 false 不置位（per-run 取消块无全局标记可滞留，原 2026-10-06 二轮
// 自检「防取消标记滞留」精神由注册表命中判定承接）
export const cancelRunning: (runKey: string) => boolean;
// ★ 2026-10-06 代码工作台笔E（沙箱网络桥 ArkTS ↔ native 契约）：
// setHttpDispatcher = 注册 dispatcher（幂等，返回 false = 已注册或注册失败——桥以布尔
// 守卫只装一次）；resolveHttpCall = 回填一次待办（未命中 / 已放弃静默丢弃）。dispatcher
// 必须 async（投递即返回、await 链在内部——主线程永不阻塞）；resultJson 三形态
// {"kind":"text"} / {"kind":"bytes"} / {"error":"..."}（native 最小解析）。
// ★ 2026-10-20 并发笔（方案 §R U5）：dispatcher 第四参 runKey——桥按它取 per-run 槽
// （放弃态与会话上下文），callId 键控待办回填与 runKey 无关
export const setHttpDispatcher: (dispatcher: (callId: string, url: string,
  optsJson: string, runKey: string) => Promise<void>) => boolean;
export const resolveHttpCall: (callId: string, resultJson: string,
  bytes?: ArrayBuffer) => void;
