// JSVM 执行层——生命周期与宿主桥（2026-10-05 端侧代码工作台笔，任务书 §3.2/§3.3）。
// · 执行序列（A11：每次执行新建 VM+Env、执行完销毁；不做快照 / Code Cache）：Init（进程
//   内一次，std::once_flag 护栏——重复调用返回 GENERIC_FAILURE 语义即「已初始化」）→
//   CreateVM（堆上限 = 下传 maxHeapBytes；young = maxOld / 4 档位派生关系〔64/16、32/8，
//   A3/A10——不落字面值〕）→ SetHeapThresholdCallback（@since 26，每 VM 一次，记标志
//   不中断）→ OpenVMScope → CreateEnv → OpenEnvScope / OpenHandleScope → 注入宿主面
//   （★ 2026-10-06 笔E：宿主函数含网络桥 httpGet——同步语义经 sandbox_http.* 投递
//   ArkTS 主线程并阻塞等待，出站治理 / 请求日志 / Cookie 全在既有 HTTP 链内）→ 删
//   WebAssembly → 预置执行（★ 2026-10-06 笔A §3.4：sandbox_prelude.h 的 Web API 预置
//   JS 编译运行一次，失败走 prelude-failed 通道）→ CompileScript → RunScript → Promise
//   捕获注册（★ 笔A §3.7：末值为原生 Promise 且未显式 result 时）→ PerformMicrotaskCheckpoint
//   → 取结果（三态：result 优先 / Promise 完成值或拒绝 / 普通末值序列化）→ 逆序关全部
//   Scope → DestroyEnv / DestroyVM。宿主回调层自本笔起在 sandbox_hostapi.*（§3.0 拆分）。
// · Scope 纪律（官方《JSVM-API 使用规范》硬规则）：JSVM_Value 必须在 HandleScope 内创建；
//   Scope 逆序关闭；DestroyEnv 后禁调任何 JSVM-API；宿主回调的 JSVM_CallbackStruct
//   生命周期必须长于 Env（本实现的 CallbackStruct 全部内嵌在 RunState——state 在执行
//   函数栈上，函数返回前先 DestroyEnv，恒安全）。
// · 错误路径：CompileScript / RunScript 失败取 JS 异常（GetAndClearLastException +
//   name / message / stack）；fs 闸拒绝抛 name=FenceError 的 JS 异常（中文 message），
//   脚本可 try / catch。
// · ★ 2026-10-20 并发笔（方案 §R U2）：取消 per-run 化——原进程级单标记 gCancelRequested
//   拆为每 run 一块 JsvmCancelBlock（生命周期 = async work 全程，codeexec.cpp 建/注销）；
//   K 路并发下 B 路不再被 A 路的取消误标、孤儿标记形态结构性消灭（每 run 新块天然干净）。
#ifndef CODEEXEC_JSVM_RUNNER_H
#define CODEEXEC_JSVM_RUNNER_H

#include <atomic>
#include <cstdint>
#include <string>
#include <vector>

#include "sandbox_fs.h"

// 执行选项（codeexec.cpp 自 napi 对象解析——数值全部来自 ArkTS 侧下传）
struct JsvmRunOptions {
    std::string workspaceRoot;
    int64_t timeoutMs = 0; // 记录用（到点判定在 ArkTS 侧计时器——A9）
    size_t maxHeapBytes = 0;
    size_t maxOutputChars = 0;
    // 日志收集条数上限（下传；0 = 不限条数、字节预算仍兜底——防病态超短行撑大 logs
    // vector 的元数据面。★ 2026-10-06 溢出修复笔：收集面与回执面分离的伴生字段）
    size_t maxLogLines = 0;
    SandboxFsLimits fsLimits;
    std::string outputFileName;
    // 沙箱网络桥等待上限毫秒（★ 2026-10-06 代码工作台笔E——ArkTS 侧算好下传〔档位时限
    // 与用户上限档取小 + 余量，算式单源 ScriptHttpBridge.ets〕，native 零字面值；HostHttpGet
    // 阻塞等待的上界）
    int64_t httpWaitMs = 0;
    // ★ 2026-10-20 并发笔（方案 §R U1）：per-run 取消目标键（调度器注入；宽容缺省
    // 空串——见 codeexec.cpp parseOptions）。网络桥投递载荷随带（桥侧 per-run 槽键）
    std::string runKey;
};

// 执行结果（codeexec.cpp 组装回 ArkTS ScriptRunResult；status / failureKind 不在此——
// 装配层 ScriptReceipt 从下列字段派生，A14）
struct JsvmRunOutcome {
    bool ok = false;
    std::string value;
    std::vector<std::string> logs;
    std::string errorName;
    std::string errorMessage;
    std::string errorStack;
    int64_t durationMs = 0;
    std::vector<std::string> flags;
    std::vector<std::string> savedNames;
    std::string outputFileName;
    int64_t outputBytes = 0;
    std::string outputHead;
    std::string outputTail;
};

// ★ 2026-10-20 并发笔（方案 §R U2）：per-run 取消控制块——每 run 一块（非拥有指针经
// RunState 与 work data 流转）；生命周期 = async work 全程：codeexec.cpp RunScript 主
// 线程 new + 注册表插入，OnComplete 主线程注销 + delete（成对释放红线：OnComplete 是
// 块生命周期唯一终点，napi 保证晚于 Execute——CancelRunning 主线程持锁查表拿指针，块
// 存活横跨整个 async work，无悬垂写竞态；requested 为原子，主线程置位 / worker 读取）
struct JsvmCancelBlock {
    std::atomic<bool> requested{false};
};

// 同步执行（worker 线程调；忙锁由 codeexec.cpp 的 napi 层管，本函数不查锁；cancelBlock
// = 本 run 的取消块〔非拥有，codeexec.cpp 注册后经 work data 传入〕）
JsvmRunOutcome JsvmRunScript(const std::string& code, const JsvmRunOptions& opts,
    JsvmCancelBlock* cancelBlock);

// ── per-run 取消注册表（定义在 jsvm_runner.cpp；主线程调——RunScript 插入 /
//    OnComplete 与提前失败路径注销 / CancelRunning 查表置位）──

// 插入注册表（runKey → 块指针；同 key 重复插入时 hilog 留痕并覆盖——调度器唯一注入后
// 理论不可达，防御位）
void JsvmRegisterCancelBlock(const std::string& runKey, JsvmCancelBlock* block);

// 注销（runKey 不在表时静默 no-op——提前失败路径与 OnComplete 双调形态安全）
void JsvmUnregisterCancelBlock(const std::string& runKey);

// 按 runKey 定向置位（★ 2026-10-20 并发笔 U1 新契约）：命中置 requested 返 true、
// 未命中返 false 不置任何标记（D4「无命中不置位」契约保持——原 gBusy.load() 忙判断
// 缩窗被注册表命中天然替代）
bool JsvmCancelRunByKey(const std::string& runKey);

#endif // CODEEXEC_JSVM_RUNNER_H
