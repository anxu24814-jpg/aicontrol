// Python 解释器引擎（pyengine）——ArkTS 侧类型声明（2026-11-06 鸿蒙Python运行时门1笔，
// 任务书 U4；门 4 扩 exec 签名与两新字段）。契约同步两处：本文件与 common/pyexec/
// PyRuntime.ets 的 interface 同构，改名/加字段须两处同步（照 libcodeexec「契约同步」纪律）。
// · init(homeDir) 幂等初始化（已初始化直接返回版本串）；version = Py_GetVersion 原文
//   （含平台与编译器串，原文照显不受文案规约约束——技术内容）；附带 setenv 两项
//   （MPLCONFIGDIR 指可写目录；SSL_CERT_FILE/DIR 按候选探测在场才设——闸②③ 真机发现）
// · exec(code, timeoutMs, sessionKey?, cwd?) 会话命名空间执行：sessionKey（= 会话 id）
//   分家顶层全局变量，空串归 "default"（探针页两参调用形态）；cwd 每轮显式设为会话临时区
//   （空串不动）。savedNames = save() 登记的待转存文件名（读回即清）；audit = 本轮安全
//   审计事件（写模式 open / socket / subprocess / os.system / ctypes.dlopen——只记录非
//   边界，读回即清）。超时与取消均为协作式中断（不承诺强杀——原生调用阻塞时不能立即
//   中断）；error 值域：空 = 成功 / PythonError = 脚本层失败（traceback 在 stderr）/
//   TimeoutError = 超时中断 / Canceled = 主动取消 / 其余 = native 层中文错误句
// · cancel() 置中断旗标——无 exec 在跑时为空操作（过期请求由代次号静默丢弃）
// · dropNamespaces(keys) 释放会话命名空间引用（会话删除级联 best-effort；键不存在 = 空操作）
export interface PyInitResult {
  ok: boolean;
  version: string;
  error: string;
  elapsedMs: number;
}

export interface PyExecResult {
  ok: boolean;
  stdout: string;
  stderr: string;
  error: string;
  elapsedMs: number;
  savedNames: string[];
  audit: string[];
}

export const init: (homeDir: string) => Promise<PyInitResult>;
export const exec: (code: string, timeoutMs: number, sessionKey?: string, cwd?: string) => Promise<PyExecResult>;
export const cancel: () => void;
export const dropNamespaces: (sessionKeys: string[]) => Promise<{ ok: boolean }>;
