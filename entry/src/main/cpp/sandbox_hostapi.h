// 沙箱宿主 API 回调层共享载体（2026-10-06 代码工作台笔A——二进制与基座，任务书 §3.0 拆分：
// 自 jsvm_runner.cpp 域级最小拆出——本件 = 宿主回调与 JSVM 值互转层；主流程与异常三件
// 回填留存 jsvm_runner.cpp）。
// · 头文件依赖单向（坑50 无环）：本件引 jsvm_runner.h（取 JsvmRunOptions）与
//   sandbox_fs.h（取 SandboxFsLimits）；jsvm_runner.h 不引本件。
// · CallbackStruct 生命周期硬规则：全部内嵌 RunState——state 在执行函数栈上，函数返回前
//   先 DestroyEnv，恒安全（先例注释随迁）。
// · 跨 TU 导出：valueToUtf8 / serializeJsValue 去静态导出——jsvm_runner.cpp 留存面
//   （fillExceptionFields / 主流程取值 / Promise 捕获回调）跨 TU 消费。
#ifndef CODEEXEC_SANDBOX_HOSTAPI_H
#define CODEEXEC_SANDBOX_HOSTAPI_H

#include <string>
#include <vector>

#include "ark_runtime/jsvm.h"
#include "jsvm_runner.h"

// 每次执行的运行态（CallbackStruct 全部内嵌——生命周期长于 Env 的硬规则达成形态）
struct RunState {
    explicit RunState(const JsvmRunOptions& o) : opts(o) {}

    const JsvmRunOptions& opts;
    std::string resultValue;    // result(v) 序列化快照（覆盖式，最后一次生效）
    bool resultSet = false;
    std::vector<std::string> logs;
    size_t logsBudget = 0;      // 剩余日志预算（字节）
    size_t logsMaxLines = 0;    // 日志条数上限（下传；0 = 不限——字节预算仍兜底。
                                // ★ 2026-10-06 溢出修复笔：原硬字面量 200 与收集面
                                // 扩容后「完整输出落盘」契约冲突，改下传）
    bool logsTruncated = false;
    bool heapLimitHit = false;  // SetHeapThresholdCallback 记志（不中断——A9 同族语义）
    std::vector<std::string> savedNames; // fs.save 登记（落库编排在 ArkTS 侧）

    // ★ 2026-10-20 并发笔（方案 §R U2）：per-run 取消块（非拥有——codeexec.cpp 建/注销，
    // jsvm_runner 挂载；HostHttpGet 受理前检查与收尾消费读本块；空 = 裸调形态按不可取消）
    JsvmCancelBlock* cancelBlock = nullptr;

    // Promise 末值捕获态（§3.7：promiseRegistered = 末值是原生 Promise 且已注册回调；
    // promiseSettled / promiseRejected 与三件文本由回调在微任务排空中回填）
    bool promiseRegistered = false;
    bool promiseSettled = false;
    bool promiseRejected = false;
    std::string promiseValueText;
    std::string promiseRejectName;
    std::string promiseRejectMessage;
    std::string promiseRejectStack;

    // 宿主回调描述子（CreateFunction 消费——内嵌本结构，见头注释生命周期论证）
    JSVM_CallbackStruct cbConsoleLog { nullptr, this };
    JSVM_CallbackStruct cbConsoleWarn { nullptr, this };
    JSVM_CallbackStruct cbConsoleError { nullptr, this };
    JSVM_CallbackStruct cbResult { nullptr, this };
    JSVM_CallbackStruct cbFsList { nullptr, this };
    JSVM_CallbackStruct cbFsRead { nullptr, this };
    JSVM_CallbackStruct cbFsReadBytes { nullptr, this };
    JSVM_CallbackStruct cbFsWrite { nullptr, this };
    JSVM_CallbackStruct cbFsAppend { nullptr, this };
    JSVM_CallbackStruct cbFsExists { nullptr, this };
    JSVM_CallbackStruct cbFsSave { nullptr, this };
    JSVM_CallbackStruct cbZlibCompress { nullptr, this };
    JSVM_CallbackStruct cbZlibDecompress { nullptr, this };
    JSVM_CallbackStruct cbMd5 { nullptr, this };
    JSVM_CallbackStruct cbSha1 { nullptr, this };
    JSVM_CallbackStruct cbSha256 { nullptr, this };
    JSVM_CallbackStruct cbHttpGet { nullptr, this };
    JSVM_CallbackStruct cbPromiseFulfilled { nullptr, this };
    JSVM_CallbackStruct cbPromiseRejected { nullptr, this };
};

// JSVM_Value(string) → std::string（两段式取长；跨 TU 导出——fillExceptionFields 与
// Promise 拒绝回填消费）
std::string valueToUtf8(JSVM_Env env, JSVM_Value v);

// 值序列化（§3.2-5）：string 原样；undefined / null 特值；其余 JSON.stringify（失败清异常
// 降级 CoerceToString；跨 TU 导出——fillExceptionFields 兜底与 Promise 回调消费）
std::string serializeJsValue(JSVM_Env env, JSVM_Value v);

// 宿主面安装（console.log/warn/error + result + fs 七方法 + zlib 与摘要五桥 + httpGet
// 网络桥〔★ 2026-10-06 代码工作台笔E——沙箱网络唯一入口，同步语义经 sandbox_http.*
// 投递 ArkTS 主线程〕；随后删 WebAssembly 全局在 jsvm_runner 主流程，§3.4-2）
void InstallSandboxHostApi(JSVM_Env env, RunState& state);

// Promise 末值捕获注册（§3.7：fulfilled / rejected 两回调经 RunState 字段回传结果；
// 返回的新 Promise 不消费——jsvm_runner 排空微任务后读 RunState 判三态）
void RegisterPromiseCapture(JSVM_Env env, JSVM_Value promise, RunState& state);

#endif // CODEEXEC_SANDBOX_HOSTAPI_H
