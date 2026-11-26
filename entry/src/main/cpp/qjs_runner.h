// QuickJS 执行层——生命周期与中断契约（2026-10-06 代码工作台笔F——QuickJS 第二引擎，
// 任务书-代码工作台笔F-QuickJS第二引擎-20261006 §3.1）。
// · vendor 记录：QuickJS 官方 2026-06-04（Fabrice Bellard 等，MIT；来源
//   bellard.org/quickjs 主 tar，pin 见任务书 §8-7）——裁剪落 cpp/quickjs/：只收
//   quickjs.c/.h、quickjs-atom.h、quickjs-opcode.h、libregexp.*、libunicode.*
//   （含 table）、cutils.*、dtoa.*、list.h、LICENSE、VERSION、Changelog；
//   **不收 quickjs-libc.c/.h、qjs.c、qjsc.c、repl.js、测试件**（★P0 任务书 §0.0：
//   std/os 模块编译期禁用——沙箱文件闸与网络闸的唯一防线，vendor 物理不含即无从注册；
//   全工程零 js_init_module_std / js_init_module_os / JS_SetModuleLoaderFunc 调用）。
//   官方源逐字保留（禁改），版本升级另立项（变更记录登记选型理由与常驻体积实测）。
// · 与 jsvm_runner 的关系：**形态对照件**——两引擎二进制独立（互不链互不载，任务书
//   §8-2 拍板），本目标自足实现同构执行序列（宿主注入 / 输出流水线 / 回执字段），
//   禁 include jsvm_runner.* / sandbox_hostapi.* / codeexec.* / sandbox_http.*；
//   可共享的只有编译副本（sandbox_fs / sandbox_codec）与数据头（sandbox_prelude.h）。
// · 差异申报（任务书 §3.7-3，回执等价前提下的引擎从属差异，变更记录登记）：
//   ①WebAssembly 两引擎本都无——JSVM 侧是「删了才有」记 wasm-removed，QuickJS 天然
//   无、不记该 flag；②堆上限语义 = JS_SetMemoryLimit（全 runtime 分配硬限，OOM 才报
//   heap-limit）vs JSVM 阈值回调（7/8 即记标不中断——GC 回收后脚本成功跑完的场景
//   旗标仍在场：成功运行也可能带 heap-limit；装配层 classifyScriptRun 已按 !ok 前置
//   对齐——成功结果的旗标只在 flags 保留、不改判失败，2026-10-07 全域自检修复笔）；
//   ③中断能力不对等（本引擎可被真实中断，JSVM 不可——对外文案两引擎同句不外溢差异）。
#ifndef CODEEXEC_QJS_RUNNER_H
#define CODEEXEC_QJS_RUNNER_H

#include <atomic>
#include <cstdint>
#include <string>
#include <vector>

#include "sandbox_fs.h"

// 执行选项（qjs_engine.cpp 自 napi 对象解析——字段与 JsvmRunOptions 全等；数值全部
// 来自 ArkTS 侧下传，native 侧禁抄任何限额字面值）
struct QjsRunOptions {
    std::string workspaceRoot;
    int64_t timeoutMs = 0; // 记录用 + ★interrupt handler 本地 deadline 兜底判据
                           //（任务书 §1.5-4：ArkTS 侧 cancel 因故未达时，到点仍中断
                           //  释放忙锁——与 JSVM「超时只交回执、忙锁保持」的能力差异位）
    size_t maxHeapBytes = 0;    // → JS_SetMemoryLimit（>0 时设）
    size_t maxOutputChars = 0;  // 内联与日志回执预算（照 jsvm 侧口径）
    size_t maxLogLines = 0;     // 日志收集条数上限（0 = 不限；下传口径同 jsvm 侧）
    SandboxFsLimits fsLimits;   // 临时区两闸（下传）
    std::string outputFileName; // 溢出件名（ArkTS 生成过闸下发，native 禁自造名）
    int64_t httpWaitMs = 0;     // 沙箱网络桥等待上限毫秒（qjs_http 阻塞等待上界）
    // ★ 2026-10-20 并发笔（方案 §R U1）：per-run 取消目标键（调度器注入；宽容缺省
    // 空串——网络桥投递载荷随带、取消注册表键、QjsRunState.runKey 源）
    std::string runKey;
};

// 执行结果（qjs_engine.cpp 组装回 ArkTS ScriptRunResult；字段与 JsvmRunOutcome 全等
// 逐字同构——回执装配 ScriptReceipt 单源消费两引擎，A14）
struct QjsRunOutcome {
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

// ★ 2026-10-20 并发笔（方案 §R U3）：per-run 取消控制块——定义在本头（qjs_hostapi.h
// 经本头取用，QjsRunState 只持指针）；生命周期 = async work 全程：qjs_engine.cpp
// QjsRunScriptNapi 主线程 new + 注册表插入，OnComplete 注销 + delete（成对释放红线，
// 形态照 U2 JsvmCancelBlock）
struct QjsCancelBlock {
    std::atomic<bool> requested{false};
};

// 同步执行（worker 线程调；忙锁由 qjs_engine.cpp 的 napi 层管，本函数不查锁）。
// ★ 2026-10-20 并发笔（方案 §R U3）：取消/到点双标记与运行态全部 per-run 化——
// 取消块经参数传入（注册表在 qjs_engine.cpp），到点标记内嵌 InterruptState，运行态经
// JS_SetContextOpaque 挂 ctx（gQjsCurrentState 全局指针退役）。
// 执行序列（对齐 A11 每次新建、用完销毁）：JS_NewRuntime → JS_SetMemoryLimit →
// JS_NewContext → RunState 构造 + 挂 ctx opaque → JS_SetInterruptHandler（双判据：
// cancel 块 ∨ 本地 deadline，先到者赢）→ 宿主面安装（qjs_hostapi：console/result/
// fs 七方法/五 codec 桥/httpGet——回调经 ctx opaque 取态）→ 预置执行（sandbox_prelude.h
// A+B 两块一次编译运行，失败走 prelude-failed）→ JS_Eval(用户码, JS_EVAL_TYPE_GLOBAL
// ——import 为语法错、动态 import 无 loader 失败，对齐 JSVM 禁模块语义) → 微任务排空 →
// Promise 末值三态 / result 优先 / 普通末值 → 输出流水线（溢出落盘/头尾预览/内联截断，
// 逐条对照 jsvm_runner）→ 逆序释放（JS_FreeValue 纪律 → JS_FreeContext →
// JS_FreeRuntime；opaque 随 ctx 销毁，栈局部 state 存活期完整覆盖 ctx 存活期）
QjsRunOutcome QjsRunScript(const std::string& code, const QjsRunOptions& opts,
    QjsCancelBlock* cancelBlock);

#endif // CODEEXEC_QJS_RUNNER_H
