// 沙箱网络桥——跨线程机制件（2026-10-06 代码工作台笔E——沙箱网络，任务书 §3.1）。
// 职责一句话 = 「把一次同步网络请求投给 ArkTS 主线程并等回填」：worker 侧
// SandboxHttpRequest 登记待办并阻塞等待（有界），主线程侧 TSFN 回调触发 dispatcher、
// resolveHttpCall 回填唤醒。
// · 零 JSVM 依赖（jsvm.h 一概不引）：本件是 napi 面 + 标准库机制件，与 sandbox_codec.*
//   同级（纯数据/机制件）——jsvm_runner 的取消判据由调用方（sandbox_hostapi 的
//   HostHttpGet 受理前查 JsvmCancelRequested）在进入本件**之前**完成，本函数零取消
//   知识、不设第二层判据（单层判据定案，任务书 §9-7）。
// · 限额纪律（照 sandbox_fs.h 同款）：等待上限 waitMs 一律由 ArkTS 侧经
//   ScriptRunOptions.httpWaitMs 下传，**本文件禁出现任何限额字面值**；响应体上限在
//   ArkTS 传输层（HTTP_MAX_LIMIT_BYTES 2MB 单源），字节经回填三跳拷贝各自独立。
// · 线程模型（任务书 §3.6 必答节，落码与此一致）：脚本跑在 napi async work 线程、
//   ArkTS 主线程事件循环空闲——TSFN 回调与 HTTP promise 续体由它承接；两条通道 =
//   worker→主线程（官方 TSFN，非阻塞投递）+ 主线程→worker（resolveHttpCall 查表写
//   结果 + notify_all）；唯一一把互斥量（待办表），wait_for 由 CV 自动释放——无 ABBA
//   面，将来加锁必须在本件登记锁序。
// · ★ 引擎预留红线（照 CMakeLists 引擎红线与笔A 同款）：本件落在 codeexec 目标内；
//   笔F 的 QuickJS 引擎须在其自有目标内实现等价件（禁与本目标 target_link_libraries、
//   禁引用本目标源文件与符号——可在其头注释引用本件的形态与协议作对照，禁代码级共享）。
//   ★ 笔F 接续点（本笔只预留零实现，任务书 §3.5-2）：①中断唤醒位 = 等待循环谓词侧
//   （wait_for 的 pred 增查中断标记）+ 中断置位侧（引擎中断路调 cv.notify_all）；
//   ②桥的运行上下文三接线（enter/abandon/exit）随竞速编排上移——收养义务见任务书
//   §3.2-6 末条，F 施工笔须并办登记。
// · TSFN 生命周期：进程级单例、无销毁路径（计数不降到 0），进程退出由系统回收——与
//   忙锁（codeexec.cpp gBusy）同姿态。
#ifndef CODEEXEC_SANDBOX_HTTP_H
#define CODEEXEC_SANDBOX_HTTP_H

#include <cstdint>
#include <string>

#include "napi/native_api.h"

// 单次桥调用结果：ok = true 时按 kind 取 text（UTF-8 字节——native 不解码，构串由
// JSVM CreateStringUtf8 替换语义承担，与 fs.read 同源）或 bytes（原始字节，std::string
// 承载字节流与 sandbox_fs 同姿势）；ok = false 时仅 errorText 有效（中文原因——来自
// ArkTS 侧回填或本层固定超时句）
struct SandboxHttpOutcome {
    bool ok = false;
    std::string kind;      // "text" | "bytes"（ok 时有效）
    std::string text;      // kind == "text" 时的正文（UTF-8 字节）
    std::string bytes;     // kind == "bytes" 时的原始字节
    std::string errorText; // ok == false 时的中文原因
};

// 投递一次请求并阻塞等待（worker 线程调；三出口全有界——回填 / 等待到点 / 投递失败，
// 出口必注销待办，禁留悬挂条目）。url / optsJson 原样透传 ArkTS 侧（native 不做语义
// 校验——参数闸与域名闸单源在 ArkTS 桥件）；runKey = 本 run 取消目标键（★ 2026-10-20
// 并发笔：随载荷透传 ArkTS dispatcher 第四参，桥按它取 per-run 槽——本层零取消知识不变）
SandboxHttpOutcome SandboxHttpRequest(const std::string& url, const std::string& optsJson,
    int64_t waitMs, const std::string& runKey);

// napi 面（codeexec.cpp 的两导出转发到这里；主线程调）：
// 注册 dispatcher（幂等——已注册回 false，桥侧以布尔守卫只装一次；返回 true = 本次
// 注册成功）。dispatcher 形态 = (callId: string, url: string, optsJson: string,
// runKey: string) 的 async 函数（投递即返回，await 链在内部——主线程永不阻塞；
// ★ 2026-10-20 并发笔：第四参 runKey = 桥侧 per-run 槽键）
bool SandboxHttpInstallDispatcher(napi_env env, napi_value dispatcherFn);

// 回填一次待办（主线程调；callId 未命中或已放弃 = 静默丢弃——迟到回填不污染任何状态）。
// resultJson 内层形态（本层最小解析，只认三形态）：{"kind":"text"} / {"kind":"bytes"} /
// {"error":"<中文原因>"}；bytesOrUndefined = 响应原始字节（ArrayBuffer，无字节体传
// undefined）——入口即拷进 std::string，拷走即断引用（JS 值不跨线程）
void SandboxHttpResolve(napi_env env, const std::string& callId, const std::string& resultJson,
    napi_value bytesOrUndefined);

#endif // CODEEXEC_SANDBOX_HTTP_H
