// Node.js 运行时引擎（nodeengine）——ArkTS 侧类型声明（2026-11-23 鸿蒙 Node 运行时门 1 笔，
// 任务书-鸿蒙Node运行时门1-20261121 U3）。契约同步两处：本文件与
// pages/NodeRuntimeProbePage.ets 的消费面同构（改名/加字段须两处同步——照 libcodeexec
// 「契约同步」纪律）。
// · start(homeDir) 受理即返回四值：started / already-started / invalid-home / thread-error；
//   启动序列六步（SIGSYS shim → 崩溃处理器 → 两 setenv → dlopen → dlsym → node::Start）
//   在线程内异步推进，进度用 status() 读。node::Start 一进程只能调一次——重复 start 返回
//   already-started 不重入；崩溃恢复口径 = 重启应用。
// · status() 返回 JSON 串（NodeEngineStatus 形态）：threadAlive / shimInstalled /
//   crashHandlerInstalled / envSet / dlopened / dlerror / startSymbol / nodeStarted /
//   shimHits（SIGSYS shim 命中计数）。dlerror 为空串 = 未出错。
export interface NodeEngineStatus {
  threadAlive: boolean;
  shimInstalled: boolean;
  crashHandlerInstalled: boolean;
  envSet: boolean;
  dlopened: boolean;
  dlerror: string;
  startSymbol: boolean;
  nodeStarted: boolean;
  shimHits: number;
}

export const start: (homeDir: string) => string;
export const status: () => string;
