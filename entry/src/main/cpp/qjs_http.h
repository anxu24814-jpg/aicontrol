// QuickJS 沙箱网络桥——跨线程机制件（2026-10-06 代码工作台笔F；形态对照件 =
// sandbox_http.h〔笔E〕——引擎独立红线禁代码级共享，按其「形态与协议对照」实现自有
// TSFN 副本；笔E 书 §8-10 / 笔F 书 §3.7-5 拍板：QuickJS 须提供 httpGet 等价宿主面，
// 出口仍走 ArkTS 侧同一 ScriptHttpBridge → executeFlow，治理 / 日志 / 授权单源不变）。
// · 职责一句话 = 「把一次同步网络请求投给 ArkTS 主线程并等回填」：worker 侧
//   QjsHttpRequest 登记待办并阻塞等待（有界 + 取消唤醒），主线程侧 TSFN 回调触发
//   dispatcher、resolveHttpCall 回填唤醒。
// · ★ 与 sandbox_http 的机制差异（笔E 预留的 F 接续点①，本引擎兑现——★ 2026-10-20
//   并发笔定向化：唤醒按 runKey 定向）：等待谓词 = 回填 done（回填含取消置败形态）；
//   引擎取消路（qjs_engine 的 CancelRunning）按 runKey 调 QjsHttpAbortWaits——对该
//   runKey 在途待办逐条置「已取消」resultJson + done + notify_all，他 runKey 等待者被
//   唤醒后谓词不满足继续等（notify_all 只多唤醒不多置败；置 done 与真回填同锁串行，
//   回填判 done 已 true 静默丢弃，无竞态）——K 路并发下为 A 取参不误杀 B 在途请求。
// · 限额纪律（照 sandbox_fs.h 同款）：等待上限 waitMs 一律经 ScriptRunOptions.httpWaitMs
//   下传，本文件禁出现任何限额字面值。
// · 线程模型与锁纪律照 sandbox_http.*：唯一一把互斥量（待办表），wait_for 由 CV 自动
//   释放；TSFN 进程级单例无销毁路径（initial_thread_count = 1 永不 release 到 0）。
// · ArkTS 半对接：同一 dispatcher 函数装进两个 so 的 TSFN（ScriptHttpBridge 负责）；
//   回填双发（callId 只在本引擎待办表在册时命中，另一侧未命中静默丢弃——两 so 运行
//   期互不可见，callId 键控与 runKey 无关）。
#ifndef CODEEXEC_QJS_HTTP_H
#define CODEEXEC_QJS_HTTP_H

#include <cstdint>
#include <string>

#include "napi/native_api.h"

// 单次桥调用结果（形态与 SandboxHttpOutcome 全等）
struct QjsHttpOutcome {
    bool ok = false;
    std::string kind;      // "text" | "bytes"（ok 时有效）
    std::string text;      // kind == "text" 时的正文（UTF-8 字节）
    std::string bytes;     // kind == "bytes" 时的原始字节
    std::string errorText; // ok == false 时的中文原因
};

// 投递一次请求并阻塞等待（worker 线程调；两出口全有界——回填 / 等待到点，出口必注销
// 待办，禁留悬挂条目）。url / optsJson 原样透传 ArkTS 侧（native 不做语义校验——参数闸
// 与域名闸单源在 ArkTS 桥件）；runKey = 本 run 取消目标键（★ 2026-10-20 并发笔：随载荷
// 透传 ArkTS dispatcher 第四参，并登记进待办条目供定向唤醒匹配）
QjsHttpOutcome QjsHttpRequest(const std::string& url, const std::string& optsJson,
    int64_t waitMs, const std::string& runKey);

// 定向取消唤醒（qjs_engine 的 CancelRunning 按 runKey 调）：对该 runKey 匹配且未 done
// 的待办逐条置「已取消」resultJson + done + notify_all——等待者经出口①解析取消句收败，
// worker 随即回到中断判定结束本次运行（QuickJS 真中断的完整兑现）。幂等；未命中 no-op。
void QjsHttpAbortWaits(const std::string& runKey);

// napi 面（qjs_engine.cpp 两导出转发到这里；主线程调）：
// 注册 dispatcher（幂等——已注册回 false；返回 true = 本次注册成功）
bool QjsHttpInstallDispatcher(napi_env env, napi_value dispatcherFn);

// 回填一次待办（主线程调；callId 未命中或已放弃 = 静默丢弃）。resultJson 三形态
// {"kind":"text"} / {"kind":"bytes"} / {"error":"<中文原因>"}；bytes = ArrayBuffer
void QjsHttpResolve(napi_env env, const std::string& callId, const std::string& resultJson,
    napi_value bytesOrUndefined);

#endif // CODEEXEC_QJS_HTTP_H
