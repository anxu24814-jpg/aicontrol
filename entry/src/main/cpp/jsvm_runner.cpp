// JSVM 执行层实现（头注释见 jsvm_runner.h；官方范式 =《使用 JSVM-API 实现 JS 与 C++
// 语言交互开发流程》+《JSVM-API 使用规范》——全部签名以本机 SDK jsvm.h 实读为准）。
// ★ 2026-10-06 代码工作台笔A（二进制与基座）：宿主回调层域级最小拆出 sandbox_hostapi.*
// （RunState 与全部 Host* 回调 + 两导出 helper——本文件经头文件消费）；本文件留存主流程
// 与异常三件回填，新增预置执行位（sandbox_prelude.h）与 Promise 末值捕获编排。
#include "jsvm_runner.h"

#include <atomic>
#include <chrono>
#include <mutex>
#include <unordered_map>

#include "ark_runtime/jsvm.h"
#include "hilog/log.h"
#include "sandbox_hostapi.h"
#include "sandbox_prelude.h"

// ── per-run 取消注册表（★ 2026-10-20 并发笔，方案 §R U2——原进程级单标记退役）──
// runKey → 取消块；主线程单线程读写（RunScript 插入 / OnComplete 注销 / CancelRunning
// 查表置位均在主线程，互斥量只防御多线程 napi 形态）。K 路并发下按 key 定向，B 路不再
// 被 A 路的取消误标；每 run 新块天然干净——原「进入清兜底」防孤儿标记的闸结构性消灭。
static std::mutex gCancelRegistryMutex;
static std::unordered_map<std::string, JsvmCancelBlock*> gCancelRegistry;

void JsvmRegisterCancelBlock(const std::string& runKey, JsvmCancelBlock* block)
{
    std::lock_guard<std::mutex> lock(gCancelRegistryMutex);
    auto it = gCancelRegistry.find(runKey);
    if (it != gCancelRegistry.end()) {
        // 同 key 重复插入 = 调度器外冒出第二注入源（理论不可达）——hilog 留痕覆盖
        OH_LOG_WARN(LOG_APP, "jsvm cancel block runKey collision: %{public}s", runKey.c_str());
    }
    gCancelRegistry[runKey] = block;
}

void JsvmUnregisterCancelBlock(const std::string& runKey)
{
    std::lock_guard<std::mutex> lock(gCancelRegistryMutex);
    gCancelRegistry.erase(runKey);
}

bool JsvmCancelRunByKey(const std::string& runKey)
{
    std::lock_guard<std::mutex> lock(gCancelRegistryMutex);
    auto it = gCancelRegistry.find(runKey);
    if (it == gCancelRegistry.end()) {
        return false; // 无命中不置位（D4 契约——无在跑目标的取消请求不滞留）
    }
    it->second->requested.store(true);
    return true;
}

// ── 堆阈值回调（@since 26；GC 时同步回调——只记标志不中断，A9 同族：无中断能力）──
static void OnHeapThreshold([[maybe_unused]] JSVM_VM vm, [[maybe_unused]] uint64_t threshold,
    void* data)
{
    RunState* state = static_cast<RunState*>(data);
    state->heapLimitHit = true;
    OH_LOG_WARN(LOG_APP, "heap threshold reached, script will fail on OOM path");
}

// 异常三件回填（name / message / stack——均可能 undefined，落空串）。
// ★ 2026-10-06 二轮自检修复（新发现 D11）：脚本 throw 原始值（throw 5 / 'str' / null /
// {}）时异常对象无 name/message 字符串属性——三字段全空，ArkTS 装配层原判据「ok=false 且
// errorName 空 = 引擎侧异常」会把脚本自身的 throw 误报成「脚本引擎异常，本次调用没有
// 执行」（归因错位，模型被引导去怀疑环境而非改代码）。两道修复：①取到异常即 push
// flags 'js-exception'——装配层据此把「有 JS 异常」从引擎错判据中摘出归 runtime；②name
// 与 message 皆空时序列化异常值本身进 message（模型至少看到抛的是什么，如 "5"）。
static void fillExceptionFields(JSVM_Env env, JsvmRunOutcome& out)
{
    JSVM_Value exc = nullptr;
    if (OH_JSVM_GetAndClearLastException(env, &exc) != JSVM_OK || exc == nullptr) {
        return;
    }
    out.flags.push_back("js-exception");
    JSVM_Value field = nullptr;
    if (OH_JSVM_GetNamedProperty(env, exc, "name", &field) == JSVM_OK && field != nullptr) {
        JSVM_ValueType t = JSVM_UNDEFINED;
        OH_JSVM_Typeof(env, field, &t);
        if (t == JSVM_STRING) {
            out.errorName = valueToUtf8(env, field);
        }
    }
    if (OH_JSVM_GetNamedProperty(env, exc, "message", &field) == JSVM_OK && field != nullptr) {
        JSVM_ValueType t = JSVM_UNDEFINED;
        OH_JSVM_Typeof(env, field, &t);
        if (t == JSVM_STRING) {
            out.errorMessage = valueToUtf8(env, field);
        }
    }
    if (OH_JSVM_GetNamedProperty(env, exc, "stack", &field) == JSVM_OK && field != nullptr) {
        JSVM_ValueType t = JSVM_UNDEFINED;
        OH_JSVM_Typeof(env, field, &t);
        if (t == JSVM_STRING) {
            out.errorStack = valueToUtf8(env, field);
        }
    }
    if (out.errorName.empty() && out.errorMessage.empty()) {
        out.errorMessage = serializeJsValue(env, exc);
    }
}

// ── 执行主函数（worker 线程同步调）──

// Init 护栏（进程内只调一次——官方注释：重复调用返回 GENERIC_FAILURE 即「已完成初始化」）
static std::once_flag gInitOnce;

JsvmRunOutcome JsvmRunScript(const std::string& code, const JsvmRunOptions& opts,
    JsvmCancelBlock* cancelBlock)
{
    JsvmRunOutcome out;
    const auto t0 = std::chrono::steady_clock::now();

    std::call_once(gInitOnce, []() {
        JSVM_InitOptions initOptions = { 0 };
        JSVM_Status st = OH_JSVM_Init(&initOptions);
        if (st != JSVM_OK) {
            // 首调即失败才致命；once_flag 已耗——后续调用照走（CreateVM 自会报错走
            // engine-error 路径，不静默：hilog 如实记）
            OH_LOG_ERROR(LOG_APP, "JSVM init failed: %{public}d", static_cast<int>(st));
        }
    });

    RunState state(opts);
    // per-run 取消块挂载（★ 2026-10-20 并发笔：HostHttpGet 受理前检查与收尾消费改读本
    // 块——空指针防御位 = 理论不可达的裸调形态，按不可取消处理）
    state.cancelBlock = cancelBlock;
    // 收集面预算（★ 2026-10-06 溢出修复笔——收集与回执两预算分离）：有落盘目标时收集
    // 上限 = 落盘单件闸（fsLimits.maxFileBytes），溢出件才能承载完整产出（desc 与首版
    // 任务书 §3.2-5 的「完整输出落盘」契约）；原实现收集即掐回执预算（maxOutputChars），
    // 落盘读到的永远是掐过的 8 KB——真机首测实证（6000 行仅存前 110 行）。文件名缺
    // （理论不可达，ToolCodeExec 恒下发）退回回执预算防御：无落盘目标就不必留全量。
    state.logsBudget = opts.outputFileName.empty() ?
        opts.maxOutputChars : opts.fsLimits.maxFileBytes;
    state.logsMaxLines = opts.maxLogLines;

    JSVM_CreateVMOptions vmOpts = { 0 };
    vmOpts.maxOldGenerationSize = opts.maxHeapBytes;
    // young 档位派生关系（A3/A10：64/16 与 32/8——恒四分之一，禁落第二处字面值）
    vmOpts.maxYoungGenerationSize = opts.maxHeapBytes / 4;

    JSVM_VM vm = nullptr;
    if (OH_JSVM_CreateVM(&vmOpts, &vm) != JSVM_OK || vm == nullptr) {
        out.errorMessage = "CreateVM 失败";
        return out;
    }
    JSVM_VMScope vmScope = nullptr;
    if (OH_JSVM_OpenVMScope(vm, &vmScope) != JSVM_OK) {
        OH_JSVM_DestroyVM(vm);
        out.errorMessage = "OpenVMScope 失败";
        return out;
    }
    // 堆阈值回调（每 VM 只能注册一次——多注册返回 INVALID_ARG；阈值取上限的 7/8，失败只
    // hilog 不阻塞：堆上限本身兜底，OOM 表现为 JS 异常走正常错误路径，§3.2-7）
    if (opts.maxHeapBytes > 0) {
        uint64_t threshold = static_cast<uint64_t>(opts.maxHeapBytes -
            opts.maxHeapBytes / 8);
        JSVM_Status st = OH_JSVM_SetHeapThresholdCallback(vm, threshold, OnHeapThreshold, &state);
        if (st != JSVM_OK) {
            OH_LOG_WARN(LOG_APP, "heap threshold callback register failed: %{public}d",
                static_cast<int>(st));
        }
    }

    JSVM_Env env = nullptr;
    bool envCreated = OH_JSVM_CreateEnv(vm, 0, nullptr, &env) == JSVM_OK && env != nullptr;
    if (!envCreated) {
        OH_JSVM_CloseVMScope(vm, vmScope);
        OH_JSVM_DestroyVM(vm);
        out.errorMessage = "CreateEnv 失败";
        return out;
    }
    JSVM_EnvScope envScope = nullptr;
    if (OH_JSVM_OpenEnvScope(env, &envScope) != JSVM_OK) {
        OH_JSVM_DestroyEnv(env);
        OH_JSVM_CloseVMScope(vm, vmScope);
        OH_JSVM_DestroyVM(vm);
        out.errorMessage = "OpenEnvScope 失败";
        return out;
    }
    JSVM_HandleScope handleScope = nullptr;
    if (OH_JSVM_OpenHandleScope(env, &handleScope) != JSVM_OK) {
        OH_JSVM_CloseEnvScope(env, envScope);
        OH_JSVM_DestroyEnv(env);
        OH_JSVM_CloseVMScope(vm, vmScope);
        OH_JSVM_DestroyVM(vm);
        out.errorMessage = "OpenHandleScope 失败";
        return out;
    }

    // —— 以下全部路径必须经 doRun 内收尾（逆序关全部 Scope 再 Destroy），禁提前 return ——
    bool scriptOk = false;
    JSVM_Value scriptResult = nullptr;
    do {
        InstallSandboxHostApi(env, state);

        // 删 WebAssembly 全局（§3.3-2：成功记 wasm-removed；不可行记 wasm-remove-failed
        // ——不静默跳过，flags 如实体现）
        JSVM_Value global = nullptr;
        OH_JSVM_GetGlobal(env, &global);
        JSVM_Value wasmKey = nullptr;
        OH_JSVM_CreateStringUtf8(env, "WebAssembly", 11, &wasmKey);
        bool removed = false;
        if (OH_JSVM_DeleteProperty(env, global, wasmKey, &removed) == JSVM_OK && removed) {
            out.flags.push_back("wasm-removed");
        } else {
            out.flags.push_back("wasm-remove-failed");
        }

        // 预置执行（§3.4-2：宿主面安装与删 WebAssembly 之后、用户代码编译之前编译运行
        // 一次——A 块 = 预置 Web API，B 块 = 通用小工具五枚〔★ 2026-10-06 代码工作台笔B：
        // hexEncode/hexDecode/b64Encode/b64Decode/csvParse，任务书 §3.3〕，A → B 顺序一次
        // 编译一次运行〔拼接中间补换行防两段粘连〕；失败语义见 §3.4-3：flags
        // 'prelude-failed' + ok=false + 中文句，**不设 js-exception、不回填异常三件**〔引擎侧
        // 缺陷不得误导模型怀疑脚本——装配层落 engine-error 固定句〕，失败后不再执行用户代码）
        const std::string preludeSource = std::string(SANDBOX_PRELUDE_JS) + "\n" +
            SANDBOX_PRELUDE_TOOLS_JS;
        JSVM_Value preludeSrc = nullptr;
        JSVM_Script preludeScript = nullptr;
        // ★ 2026-10-06 真机缺陷修复（P0，真机首测实证）：RunScript 的 result 出参**必须非空**
        // ——JSVM 实现首行即 CHECK_ARG(env, result)（arkcompiler_jsvm 源码实读，6.0-Release
        // 同），传 nullptr 恒回 JSVM_INVALID_ARG：预置恒失败 → 每次调用落 prelude-failed →
        // 装配层固定句「脚本引擎异常，本次调用没有执行」。原句「不参与结果取值」被误读为可传
        // nullptr——预置结果依旧不消费，但须给真实槽位。
        JSVM_Value preludeResult = nullptr;
        if (OH_JSVM_CreateStringUtf8(env, preludeSource.c_str(), preludeSource.size(),
            &preludeSrc) != JSVM_OK ||
            OH_JSVM_CompileScript(env, preludeSrc, nullptr, 0, false, nullptr, &preludeScript) !=
                JSVM_OK ||
            preludeScript == nullptr ||
            OH_JSVM_RunScript(env, preludeScript, &preludeResult) != JSVM_OK) {
            JSVM_Value stale = nullptr;
            OH_JSVM_GetAndClearLastException(env, &stale);
            out.flags.push_back("prelude-failed");
            out.errorMessage = "沙箱预置环境初始化失败";
            break;
        }

        JSVM_Value jsSrc = nullptr;
        if (OH_JSVM_CreateStringUtf8(env, code.c_str(), code.size(), &jsSrc) != JSVM_OK) {
            out.errorMessage = "源码字符串创建失败";
            break;
        }
        JSVM_Script script = nullptr;
        if (OH_JSVM_CompileScript(env, jsSrc, nullptr, 0, false, nullptr, &script) != JSVM_OK ||
            script == nullptr) {
            fillExceptionFields(env, out);
            break;
        }
        JSVM_Status runSt = OH_JSVM_RunScript(env, script, &scriptResult);
        if (runSt != JSVM_OK) {
            fillExceptionFields(env, out);
            break;
        }
        scriptOk = true;
        // Promise 末值捕获注册（§3.7-1：RunScript 成功且未显式调 result 且末值是原生
        // Promise；result 显式设值优先——已设值时跳过注册省一次回调。排空微任务使
        // RunState 回填，三态判定在下方取值段）
        if (!state.resultSet) {
            bool isPromise = false;
            if (OH_JSVM_IsPromise(env, scriptResult, &isPromise) == JSVM_OK && isPromise) {
                RegisterPromiseCapture(env, scriptResult, state);
            }
        }
        // 微任务排空（脚本自身 Promise.then 生效——无宏任务循环，仅微任务一次 checkpoint；
        // 异常时清掉防污染后续 API 调用）
        if (OH_JSVM_PerformMicrotaskCheckpoint(vm) != JSVM_OK) {
            JSVM_Value exc = nullptr;
            OH_JSVM_GetAndClearLastException(env, &exc);
        }
    } while (false);

    if (scriptOk) {
        if (state.resultSet) {
            // result(v) 显式设值优先（§3.2-5）
            out.value = state.resultValue;
            out.ok = true;
        } else if (state.promiseRegistered) {
            // Promise 末值三态（§3.7-5：排空后判定——fulfilled 取值覆盖 "{}"；rejected 回
            // 填三件 + js-exception 归 runtime〔与 D11 归因同族〕；永挂起〔沙箱无任何异步
            // 来源〕PendingPromiseError + 固定中文句 + flags 'promise-pending'——装配层由
            // 「非空 errorName」判据落 failed/runtime，ScriptReceipt 零改动）
            if (state.promiseSettled && !state.promiseRejected) {
                out.value = state.promiseValueText;
                out.ok = true;
            } else if (state.promiseSettled && state.promiseRejected) {
                out.errorName = state.promiseRejectName;
                out.errorMessage = state.promiseRejectMessage;
                out.errorStack = state.promiseRejectStack;
                out.flags.push_back("js-exception");
            } else {
                out.errorName = "PendingPromiseError";
                out.errorMessage = "脚本末值是一个未完成的 Promise，排空微任务后仍没有结果。";
                out.flags.push_back("promise-pending");
            }
        } else {
            // 普通末值（§3.2-5）
            out.value = serializeJsValue(env, scriptResult);
            out.ok = true;
        }
    }
    if (state.logsTruncated) {
        out.flags.push_back("log-truncated");
    }
    if (state.heapLimitHit) {
        out.flags.push_back("heap-limit");
    }
    out.logs = state.logs;
    out.savedNames = state.savedNames;

    // 溢出落盘 + 头尾预览（§3.3-5：value + logs 合成全文超内联上限即落盘——A3 合计口径；
    // 受单件闸写满即止；文件名由 ArkTS 侧过闸下发，本层不自造名）
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
            // outputBytes = 文件实写字节数（★ 2026-10-06 溢出修复笔：原报 fullText.size()
            // ——顶闸时大于文件实际大小，模型按「共 N 字节」分页读会读到不存在的行）
            out.outputBytes = static_cast<int64_t>(written);
            out.outputHead = sandboxUtf8Head(fullText, 1024);
            out.outputTail = sandboxUtf8Tail(fullText, 1024);
            if (written < fullText.size()) {
                out.flags.push_back("output-truncated");
            }
        } else {
            OH_LOG_ERROR(LOG_APP, "spill output write failed: %{public}s",
                opts.outputFileName.c_str());
            // ★ 2026-10-06 二轮自检修复（首轮观察 D6 转修复）：写失败不再只留 hilog——
            // flags 如实体现（同 wasm-remove-failed 形制），装配层据此在回执里告知模型
            // 「输出不完整」，否则 value 被内联截断后模型无从知道全文丢失（静默截断）
            out.flags.push_back("spill-write-failed");
        }
    }
    // 回执面 logs 掐回（★ 2026-10-06 溢出修复笔——收集面扩容后的 napi 边界防线）：收集
    // 预算为落盘单件闸量级，超回执预算的 logs 全量原样过 napi 会把可达 10 MB 的串拉过
    // 边界（首版书 §3.2-5 设计红线）。此处只保留回执预算内前缀——信封头尾预览已承载
    // 开头结尾，全文以溢出件为准（覆盖落盘成功、落盘失败、收集闸顶满三形态）。
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
    // 内联截断（value 单项上限；logs 超回执预算部分已由上方掐回，全文在溢出件）
    out.value = sandboxUtf8Truncate(out.value, opts.maxOutputChars);

    // 取消标记收尾消费（★ 2026-10-20 并发笔：改读本 run 的取消块——标记在则结果带
    // canceled，ArkTS 侧丢弃；不做跨线程强杀，§3.2-8）
    if (state.cancelBlock != nullptr && state.cancelBlock->requested.load()) {
        out.flags.push_back("canceled");
    }

    // 逆序关闭 + 销毁（Scope 纪律：HandleScope → EnvScope → DestroyEnv → VMScope →
    // DestroyVM；DestroyEnv 后禁调任何 JSVM-API）
    OH_JSVM_CloseHandleScope(env, handleScope);
    OH_JSVM_CloseEnvScope(env, envScope);
    OH_JSVM_DestroyEnv(env);
    OH_JSVM_CloseVMScope(vm, vmScope);
    OH_JSVM_DestroyVM(vm);

    const auto t1 = std::chrono::steady_clock::now();
    out.durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(t1 - t0).count();
    return out;
}
