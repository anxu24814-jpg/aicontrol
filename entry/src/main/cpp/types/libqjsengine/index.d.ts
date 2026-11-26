// 代码工作台 QuickJS 桥——ArkTS 侧类型声明（★ 2026-10-06 代码工作台笔F：字段与
// types/libcodeexec/index.d.ts **集合全等**〔断言关系钉守〕；与 common/codeexec/
// ScriptEngine.ets 同构，改名须同步三处：本文件 / ScriptEngine.ets / QuickJsEngine.ets）。
// flags 值域以 ScriptEngine.ets 注释为枚举源；本引擎差异：wasm-removed 恒不出现
//（QuickJS 天然无 WebAssembly，任务书 §3.7-3 差异申报）。
// 字段语义与单源（与 libcodeexec 同款）：
// · workspaceRoot ← WorkspaceTmpUtil.workspaceTmpConversationDir（会话临时区绝对路径）
// · timeoutMs / maxHeapBytes / maxOutputChars ← ScriptLimits.ets 档位映射（本引擎
//   timeoutMs 兼任 interrupt handler 本地 deadline 兜底判据）
// · tmpMaxFileBytes / tmpMaxTotalBytes ← WorkspaceTmpUtil.ets 两闸（C++ 禁抄值）
// · outputFileName ← ArkTS 生成并过名称闸后下发（native 禁自造名）
// · httpWaitMs ← 沙箱网络桥等待上限（算式单源 ScriptHttpBridge.ets；必填）
// · runKey ← ★ 2026-10-20 并发笔（方案 §R U1）：native per-run 取消目标键——调度器
//   注入，调用方不填；区别于 httpCtx.runId（会话运行轮 id，同轮并行 exec 会撞键，
//   不得复用）；native 侧宽容缺省空串（与 libcodeexec 同款）
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
// 被标记取消；无命中回 false 不置位（per-run 取消块无全局标记可滞留；libcodeexec 同款）
export const cancelRunning: (runKey: string) => boolean;
// 沙箱网络桥 ArkTS ↔ native 契约（自有 TSFN 安装点——笔F 书 §3.7-5；语义与
// libcodeexec 两导出逐字同款，ArkTS 侧同一 ScriptHttpBridge dispatcher 双装）。
// ★ 2026-10-20 并发笔（方案 §R U5）：dispatcher 第四参 runKey——桥按它取 per-run 槽
export const setHttpDispatcher: (dispatcher: (callId: string, url: string,
  optsJson: string, runKey: string) => Promise<void>) => boolean;
export const resolveHttpCall: (callId: string, resultJson: string,
  bytes?: ArrayBuffer) => void;
