// QuickJS 执行层实现（头注释见 qjs_runner.h；形态对照件 = jsvm_runner.cpp——执行序
// 列 / 输出流水线 / 异常三件回填逐条对齐，差异位三处均申报：中断机制〔本引擎独有〕/
// 堆上限语义〔硬限 vs 阈值回调〕/ WebAssembly〔天然无〕）。
// · 执行序列：New Runtime → SetMemoryLimit → New Context → RunState 构造 + 挂 ctx
//   opaque（★ 2026-10-20 并发笔：gQjsCurrentState 全局指针退役）→ SetInterruptHandler
//   （双判据先到者赢，cancel 块与 deadline 均 per-run）→ 宿主面安装 → 预置执行
//   （sandbox_prelude.h 共享数据头 A+B 两块）→ JS_Eval(用户码) → 微任务排空 → 结果三态
//   取值 → 输出流水线 → 逆序释放（FreeContext → FreeRuntime）。
// · 引用计数纪律（QuickJS 无自动 GC 边界管理 C 侧引用）：JS_Eval 返回值 / JS_GetException
//   异常值 / PromiseResult 取值——全部路径 JS_FreeValue；ctx/rt 成对建毁含失败路径。
#include "qjs_runner.h"

#include <chrono>

#include "hilog/log.h"
#include "qjs_hostapi.h"
#include "qjs_http.h"
#include "quickjs/quickjs.h"
#include "sandbox_fs.h"
#include "sandbox_prelude.h"

// ── 中断回调（本笔核心机制——QuickJS 执行期周期回调，函数调用 / 回跳等点触发）──
// 返回非零 = 中断执行（引擎抛不可捕获错误，JS_Eval 回 JS_EXCEPTION）；调用频率真机
// 实测记录（任务书 §5-10）。已知风险申报（quickjs-ng #1672 形态，官方版是否复现真机
// 验）：部分 Array 内建 C 循环可能长时不触发——对外「不保证被中断」保守句已兜住。
// ★ 2026-10-20 并发笔（方案 §R U3）：双判据 per-run 化——cancel 位 = 本 run 取消块
// （qjs_engine.cpp 注册表按 runKey 定向，B 路不再被 A 路的取消误中断）；deadline 位 =
// 本结构内嵌字段（原全局 gQjsDeadlineHit 删——归因不再串槽）。
struct QjsInterruptState {
    std::chrono::steady_clock::time_point deadline;
    bool hasDeadline = false;
    QjsCancelBlock* cancel = nullptr; // 本 run 取消块（非拥有；空 = 裸调形态不可取消）
    bool deadlineHit = false;         // 到点标记（worker 单线程读写，无需原子）
};

static int QjsInterruptCheck(JSRuntime* rt, void* opaque)
{
    (void)rt;
    QjsInterruptState* st = static_cast<QjsInterruptState*>(opaque);
    if (st->cancel != nullptr && st->cancel->requested.load()) {
        return 1; // 归因在收尾按块判（cancel 位）
    }
    if (st->hasDeadline && std::chrono::steady_clock::now() >= st->deadline) {
        st->deadlineHit = true;
        return 1;
    }
    return 0;
}

// 异常三件回填（与 jsvm 侧 fillExceptionFields 同语义含 D11 两道：取到即 js-exception 由
// 调用方记、name 与 message 皆空时序列化异常值本身进 message）
static void QjsFillExceptionFields(JSContext* ctx, JSValueConst exc, QjsRunOutcome& out)
{
    JSValue name = JS_GetPropertyStr(ctx, exc, "name");
    if (JS_IsString(name)) {
        out.errorName = qjsValueToUtf8(ctx, name);
    }
    JS_FreeValue(ctx, name);
    JSValue msg = JS_GetPropertyStr(ctx, exc, "message");
    if (JS_IsString(msg)) {
        out.errorMessage = qjsValueToUtf8(ctx, msg);
    }
    JS_FreeValue(ctx, msg);
    JSValue stack = JS_GetPropertyStr(ctx, exc, "stack");
    if (JS_IsString(stack)) {
        out.errorStack = qjsValueToUtf8(ctx, stack);
    }
    JS_FreeValue(ctx, stack);
    if (out.errorName.empty() && out.errorMessage.empty()) {
        out.errorMessage = qjsSerializeJsValue(ctx, exc);
    }
}

static bool QjsHasFlag(const std::vector<std::string>& flags, const char* name)
{
    for (const std::string& f : flags) {
        if (f == name) {
            return true;
        }
    }
    return false;
}

// ── 执行主函数（worker 线程同步调）──

QjsRunOutcome QjsRunScript(const std::string& code, const QjsRunOptions& opts,
    QjsCancelBlock* cancelBlock)
{
    QjsRunOutcome out;
    const auto t0 = std::chrono::steady_clock::now();

    JSRuntime* rt = JS_NewRuntime();
    if (rt == nullptr) {
        out.errorMessage = "JS_NewRuntime 失败";
        return out;
    }
    // 堆上限（差异申报 §3.7-3-5：全 runtime 分配硬限——OOM 才报 heap-limit；JSVM 是
    // 7/8 阈值回调先记标。数值同源档位，语义差异进变更记录）
    if (opts.maxHeapBytes > 0) {
        JS_SetMemoryLimit(rt, opts.maxHeapBytes);
    }

    JSContext* ctx = JS_NewContext(rt);
    if (ctx == nullptr) {
        JS_FreeRuntime(rt);
        out.errorMessage = "JS_NewContext 失败";
        return out;
    }

    QjsRunState state(opts);
    // 收集面预算（照 jsvm 侧同款：有落盘目标时收集上限 = 落盘单件闸，溢出件承载完整
    // 产出；文件名缺省退回回执预算防御）
    state.logsBudget = opts.outputFileName.empty() ?
        opts.maxOutputChars : opts.fsLimits.maxFileBytes;
    state.logsMaxLines = opts.maxLogLines;
    // per-run 取消块与 runKey 挂载（★ 2026-10-20 并发笔：注册表插入在主线程
    // QjsRunScriptNapi，worker Execute 开始即可用；空块 = 裸调形态按不可取消）
    state.cancelBlock = cancelBlock;
    state.runKey = opts.runKey;
    // per-run 状态载体：挂 ctx opaque（先于任何宿主回调可达——安装宿主面在此后；opaque
    // 随 ctx 销毁，栈局部 state 存活期完整覆盖 ctx 存活期，无悬垂窗口）
    JS_SetContextOpaque(ctx, &state);
    // 中断 handler（本地 deadline 兜底判据用下传 timeoutMs——同 B 笔钳制后生效值；
    // cancel 块自 RunState 挂载后可取，仍先于 handler 安装）
    QjsInterruptState interruptState;
    if (opts.timeoutMs > 0) {
        interruptState.hasDeadline = true;
        interruptState.deadline =
            t0 + std::chrono::milliseconds(opts.timeoutMs);
    }
    interruptState.cancel = state.cancelBlock;
    JS_SetInterruptHandler(rt, QjsInterruptCheck, &interruptState);
    QjsInstallHostApi(ctx);

    // —— 以下全部路径必须经统一收尾（opaque 随 ctx 销毁，直接 FreeContext/FreeRuntime）——
    JSValue evalResult = JS_UNDEFINED;
    bool scriptOk = false;
    do {
        // 预置执行（A 块 Web API + B 块小工具，拼接一次编译一次运行——A → B 顺序同
        // jsvm 侧；失败走 prelude-failed 通道〔不设 js-exception、不回填三件〕，中断
        // 命中时归因 deadline / cancel 优先）
        const std::string preludeSource = std::string(SANDBOX_PRELUDE_JS) + "\n" +
            SANDBOX_PRELUDE_TOOLS_JS;
        JSValue pre = JS_Eval(ctx, preludeSource.c_str(), preludeSource.size(),
            "<prelude>", JS_EVAL_TYPE_GLOBAL);
        if (JS_IsException(pre)) {
            JSValue exc = JS_GetException(ctx);
            JS_FreeValue(ctx, exc);
            // 归因序 deadline 优先不变（per-run 字段同序）
            if (interruptState.deadlineHit) {
                out.flags.push_back("deadline-hit");
            } else if (state.cancelBlock != nullptr &&
                state.cancelBlock->requested.load()) {
                out.flags.push_back("canceled");
            } else {
                out.flags.push_back("prelude-failed");
                out.errorMessage = "沙箱预置环境初始化失败";
            }
            break;
        }
        JS_FreeValue(ctx, pre);

        // WebAssembly：QuickJS 天然无此全局——不删不记 flags（差异申报 §3.7-3-1，
        // jsvm 侧的 wasm-removed 为单侧差异，双引擎比对时剔除）

        // 用户码执行（JS_EVAL_TYPE_GLOBAL：import 语句为语法错、动态 import 因未设
        // module loader 失败——对齐 JSVM 侧禁模块语义；★P0 第 3 道闸 = 全程不调
        // JS_SetModuleLoaderFunc）
        evalResult = JS_Eval(ctx, code.c_str(), code.size(), "<exec>", JS_EVAL_TYPE_GLOBAL);
        if (JS_IsException(evalResult)) {
            JSValue exc = JS_GetException(ctx);
            // 中断判定先行（先到者赢，deadline 优先——覆盖普通异常归因；归因序 deadline
            // 先判 cancel 后判的形状在 per-run 字段下同序保留）；归因分支只记
            // flags，异常值统一由段尾单次 JS_FreeValue 释放（分支内提前释放即双重释放下
            // 溢——GetGlobalObject 家族同族 crash 形态）
            if (interruptState.deadlineHit) {
                out.flags.push_back("deadline-hit");
            } else if (state.cancelBlock != nullptr &&
                state.cancelBlock->requested.load()) {
                out.flags.push_back("canceled");
            } else {
                // 普通脚本异常：三件回填 + js-exception（D11 语义）；OOM 判据按异常
                // message 匹配（QuickJS 硬限触发的 InternalError——真机实测校准口径）
                QjsFillExceptionFields(ctx, exc, out);
                out.flags.push_back("js-exception");
                if (out.errorMessage.find("out of memory") != std::string::npos) {
                    out.flags.push_back("heap-limit");
                }
            }
            JS_FreeValue(ctx, exc);
            break;
        }
        scriptOk = true;

        // 微任务排空（对齐 PerformMicrotaskCheckpoint 语义；job 异常取走清掉防污染
        // 后续取值——中断在 job 内触发时异常亦由此清，deadline 收尾兜底归因）
        for (;;) {
            JSContext* jobCtx = nullptr;
            int err = JS_ExecutePendingJob(rt, &jobCtx);
            if (err > 0) {
                continue;
            }
            if (err < 0 && jobCtx != nullptr) {
                JSValue exc = JS_GetException(jobCtx);
                JS_FreeValue(jobCtx, exc);
                continue;
            }
            break;
        }
    } while (false);

    if (scriptOk) {
        if (state.resultSet) {
            // result(v) 显式设值优先
            out.value = state.resultValue;
            out.ok = true;
        } else {
            // Promise 末值三态（JS_PromiseState 对非 Promise 回 -1——判定与取值一体）
            const JSPromiseStateEnum pst = JS_PromiseState(ctx, evalResult);
            if (pst == JS_PROMISE_PENDING) {
                out.errorName = "PendingPromiseError";
                out.errorMessage = "脚本末值是一个未完成的 Promise，排空微任务后仍没有结果。";
                out.flags.push_back("promise-pending");
            } else if (pst == JS_PROMISE_FULFILLED) {
                JSValue pv = JS_PromiseResult(ctx, evalResult);
                out.value = qjsSerializeJsValue(ctx, pv);
                JS_FreeValue(ctx, pv);
                out.ok = true;
            } else if (pst == JS_PROMISE_REJECTED) {
                JSValue rv = JS_PromiseResult(ctx, evalResult);
                QjsFillExceptionFields(ctx, rv, out);
                out.flags.push_back("js-exception");
                JS_FreeValue(ctx, rv);
            } else {
                // 普通末值（序列化口径与 jsvm 侧 serializeJsValue 同语义）
                out.value = qjsSerializeJsValue(ctx, evalResult);
                out.ok = true;
            }
        }
    }
    if (state.logsTruncated) {
        out.flags.push_back("log-truncated");
    }
    out.logs = state.logs;
    out.savedNames = state.savedNames;

    // 溢出落盘 + 头尾预览（逐条对照 jsvm_runner 同段：value + logs 合成全文超内联上限
    // 且有落盘名即写——受单件闸写满即止〔截点回退 UTF-8 序列头〕；实写量回填 outputBytes，
    // 顶闸记 output-truncated；写失败记 spill-write-failed 不静默）
    std::string fullText = out.value;
    for (const std::string& log : out.logs) {
        fullText += "\n";
        fullText += log;
    }
    if (fullText.size() > opts.maxOutputChars && !opts.outputFileName.empty()) {
        size_t written = 0;
        if (sandboxSpillOutput(opts.workspaceRoot, opts.outputFileName, fullText,
            opts.fsLimits.maxFileBytes, written)) {
            out.outputFileName = opts.outputFileName;
            out.outputBytes = static_cast<int64_t>(written);
            out.outputHead = sandboxUtf8Head(fullText, 1024);
            out.outputTail = sandboxUtf8Tail(fullText, 1024);
            if (written < fullText.size()) {
                out.flags.push_back("output-truncated");
            }
        } else {
            OH_LOG_ERROR(LOG_APP, "qjs spill output write failed: %{public}s",
                opts.outputFileName.c_str());
            out.flags.push_back("spill-write-failed");
        }
    }
    // 回执面 logs 掐回（收集面扩容后的 napi 边界防线——只保留回执预算内前缀，全文以
    // 溢出件为准；覆盖落盘成功 / 落盘失败 / 收集闸顶满三形态）
    size_t logsTotal = 0;
    for (const std::string& log : out.logs) {
        logsTotal += log.size();
    }
    if (logsTotal > opts.maxOutputChars) {
        std::vector<std::string> clippedLogs;
        size_t used = 0;
        for (const std::string& log : out.logs) {
            if (used + log.size() > opts.maxOutputChars) {
                break;
            }
            clippedLogs.push_back(log);
            used += log.size();
        }
        out.logs = clippedLogs;
    }
    // 内联截断（value 单项上限）
    out.value = sandboxUtf8Truncate(out.value, opts.maxOutputChars);

    // 取消标记收尾消费（照 jsvm 侧同位：本 run 取消块标记在则结果带 canceled，ArkTS 侧
    // 丢弃）；归因段已记 canceled 时不再重复——flags 契约全枚举无重复值，与下方 deadline
    // 兜底同款守卫（读侧无消费语义，短路不影响）
    if (state.cancelBlock != nullptr && state.cancelBlock->requested.load() &&
        !QjsHasFlag(out.flags, "canceled")) {
        out.flags.push_back("canceled");
    }
    // deadline 收尾兜底（eval 成功路径吃到中断的收口：标记在且尚未归因 deadline /
    // canceled 时补记——例如微任务内触发中断被逐 job 清异常、末值仍取到的形态）
    if (interruptState.deadlineHit && !QjsHasFlag(out.flags, "deadline-hit") &&
        !QjsHasFlag(out.flags, "canceled")) {
        out.flags.push_back("deadline-hit");
        out.ok = false;
    }

    // 逆序释放（opaque 随 ctx 销毁——宿主回调不再可达；随后 FreeContext / FreeRuntime）
    JS_FreeValue(ctx, evalResult);
    JS_FreeContext(ctx);
    JS_FreeRuntime(rt);

    const auto t1 = std::chrono::steady_clock::now();
    out.durationMs =
        std::chrono::duration_cast<std::chrono::milliseconds>(t1 - t0).count();
    return out;
}
