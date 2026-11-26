// QuickJS 引擎 napi 入口（2026-10-06 代码工作台笔F——QuickJS 第二引擎，任务书 §3.3；
// 形态对照件 = codeexec.cpp，自足另立不共享源——桥绑死各引擎结果结构与忙锁实例，
// 共享需抽公共件反侵入 codeexec，范围膨胀）。
// · ArkTS ↔ native 合同：runScript(code, options) 异步执行（napi_create_async_work，
//   worker 线程跑 QuickJS）+ cancelRunning(runKey) 按 runKey 定向置取消标记（★ 2026-10-20
//   并发笔：命中置位 + 定向唤醒该 runKey 的网络桥等待）+ setHttpDispatcher /
//   resolveHttpCall（自有 TSFN 安装点——笔F 书 §3.7-5）。
// · 并发计数锁（进程级 K 路上限，本 so 独立一份）：满时新调用立即 resolve BusyError
//   形态（两层字面一致排障面——装配层 composeScriptReceipt 判 errorName 短路，不消费
//   native message）；释放时机 = async work 完成回调（★本引擎差异：QuickJS 可真中断，
//   超时后计数秒级释放——调度器的排队推进由此受益）。
// · 结果组装（OnComplete 主线程）：QjsRunOutcome → napi 对象（字段清单与
//   types/libqjsengine/index.d.ts / ScriptEngine.ets 同构——三处同步红线）。
#include <atomic>
#include <cstring>
#include <mutex>
#include <string>
#include <unordered_map>

#include "hilog/log.h"
#include "napi/native_api.h"
#include "qjs_http.h"
#include "qjs_runner.h"

// 进程级并发计数锁（★ 2026-10-20 并发笔〔方案 §R U3〕：原单布尔 gQjsBusy 改 K 路计数
// ——本 so 独立一份，与 libcodeexec.so 的 gActiveRuns 互不可见；跨引擎编排由 ArkTS 侧
// ScriptScheduler 唯一进口保证，两道防线纵深；上限与 ArkTS SCRIPT_MAX_CONCURRENT 同值
// K=2〔注释声明不落第二处逻辑〕）
static std::atomic<int32_t> gQjsActiveRuns(0);
static constexpr int32_t QJS_NATIVE_MAX_CONCURRENT_RUNS = 2;

// ── per-run 取消注册表（★ 2026-10-20 并发笔——原全局取消标记退役，形态照 U2
//    jsvm_runner.cpp；主线程单线程读写，互斥量防御多线程 napi 形态）──
static std::mutex gQjsCancelRegistryMutex;
static std::unordered_map<std::string, QjsCancelBlock*> gQjsCancelRegistry;

static void QjsRegisterCancelBlock(const std::string& runKey, QjsCancelBlock* block)
{
    std::lock_guard<std::mutex> lock(gQjsCancelRegistryMutex);
    auto it = gQjsCancelRegistry.find(runKey);
    if (it != gQjsCancelRegistry.end()) {
        // 同 key 重复插入 = 调度器外冒出第二注入源（理论不可达）——hilog 留痕覆盖
        OH_LOG_WARN(LOG_APP, "qjs cancel block runKey collision: %{public}s", runKey.c_str());
    }
    gQjsCancelRegistry[runKey] = block;
}

static void QjsUnregisterCancelBlock(const std::string& runKey)
{
    std::lock_guard<std::mutex> lock(gQjsCancelRegistryMutex);
    gQjsCancelRegistry.erase(runKey);
}

// napi 取串（两段式：先取长再取内容）
static bool qjsNapiReadString(napi_env env, napi_value v, std::string& out)
{
    size_t len = 0;
    if (napi_get_value_string_utf8(env, v, nullptr, 0, &len) != napi_ok) {
        return false;
    }
    out.assign(len, '\0');
    size_t written = 0;
    if (len > 0 && napi_get_value_string_utf8(env, v, &out[0], len + 1, &written) != napi_ok) {
        return false;
    }
    out.resize(written);
    return true;
}

// options 对象逐字段解析（字段与 parseOptions 同清单；数值字段全 double 通道再转整）
static bool qjsParseOptions(napi_env env, napi_value obj, QjsRunOptions& opts)
{
    napi_value field = nullptr;
    auto readString = [&](const char* key, std::string& target) -> bool {
        if (napi_get_named_property(env, obj, key, &field) != napi_ok || field == nullptr) {
            return false;
        }
        return qjsNapiReadString(env, field, target);
    };
    auto readNumber = [&](const char* key, double& target) -> bool {
        if (napi_get_named_property(env, obj, key, &field) != napi_ok || field == nullptr) {
            return false;
        }
        return napi_get_value_double(env, field, &target) == napi_ok;
    };
    double timeoutMs = 0;
    double maxHeap = 0;
    double maxOutput = 0;
    double maxFile = 0;
    double maxTotal = 0;
    double maxLogLines = 0;
    double httpWaitMs = 0;
    if (!readString("workspaceRoot", opts.workspaceRoot) ||
        !readNumber("timeoutMs", timeoutMs) ||
        !readNumber("maxHeapBytes", maxHeap) ||
        !readNumber("maxOutputChars", maxOutput) ||
        !readNumber("tmpMaxFileBytes", maxFile) ||
        !readNumber("tmpMaxTotalBytes", maxTotal) ||
        !readString("outputFileName", opts.outputFileName) ||
        !readNumber("httpWaitMs", httpWaitMs)) {
        return false;
    }
    // maxLogLines 宽容缺省（0 = 不限条数——与 libcodeexec 同款）
    (void)readNumber("maxLogLines", maxLogLines);
    // runKey 宽容缺省（空串——★ 2026-10-20 并发笔：调度器注入的 per-run 取消目标键，
    // 调用方不填不炸；与 libcodeexec 同款）
    (void)readString("runKey", opts.runKey);
    opts.timeoutMs = static_cast<int64_t>(timeoutMs);
    opts.maxHeapBytes = static_cast<size_t>(maxHeap);
    opts.maxOutputChars = static_cast<size_t>(maxOutput);
    opts.maxLogLines = static_cast<size_t>(maxLogLines);
    opts.fsLimits.maxFileBytes = static_cast<size_t>(maxFile);
    opts.fsLimits.maxTotalBytes = static_cast<size_t>(maxTotal);
    opts.httpWaitMs = static_cast<int64_t>(httpWaitMs);
    return true;
}

// 异步工作载荷（Execute 与 OnComplete 之间共享；OnComplete 尾删除）。cancelBlock =
// 本 run 取消块（★ 2026-10-20 并发笔：QjsRunScriptNapi 主线程 new + 注册，OnComplete
// 注销 + delete——块生命周期唯一终点，worker 读取 requested 全程块存活，无悬垂）
struct QjsRunWorkData {
    napi_deferred deferred = nullptr;
    napi_async_work work = nullptr;
    std::string code;
    QjsRunOptions opts;
    QjsRunOutcome outcome;
    QjsCancelBlock* cancelBlock = nullptr;
};

// 字符串数组 → napi 数组（logs / savedNames / flags）
static napi_value qjsStringArrayToNapi(napi_env env, const std::vector<std::string>& items)
{
    napi_value arr = nullptr;
    napi_create_array(env, &arr);
    for (size_t i = 0; i < items.size(); i++) {
        napi_value elem = nullptr;
        napi_create_string_utf8(env, items[i].c_str(), items[i].size(), &elem);
        napi_set_element(env, arr, static_cast<uint32_t>(i), elem);
    }
    return arr;
}

// QjsRunOutcome → napi 结果对象（字段清单三处同步：libqjsengine/index.d.ts /
// ScriptEngine.ets——与 libcodeexec 字段级同构）
static napi_value qjsOutcomeToNapi(napi_env env, const QjsRunOutcome& out)
{
    napi_value obj = nullptr;
    napi_create_object(env, &obj);
    auto setBool = [&](const char* key, bool v) {
        napi_value val = nullptr;
        napi_get_boolean(env, v, &val);
        napi_set_named_property(env, obj, key, val);
    };
    auto setString = [&](const char* key, const std::string& v) {
        napi_value val = nullptr;
        napi_create_string_utf8(env, v.c_str(), v.size(), &val);
        napi_set_named_property(env, obj, key, val);
    };
    auto setInt64 = [&](const char* key, int64_t v) {
        napi_value val = nullptr;
        napi_create_int64(env, v, &val);
        napi_set_named_property(env, obj, key, val);
    };
    setBool("ok", out.ok);
    setString("value", out.value);
    napi_value logsArr = qjsStringArrayToNapi(env, out.logs);
    napi_set_named_property(env, obj, "logs", logsArr);
    setString("errorName", out.errorName);
    setString("errorMessage", out.errorMessage);
    setString("errorStack", out.errorStack);
    setInt64("durationMs", out.durationMs);
    napi_value flagsArr = qjsStringArrayToNapi(env, out.flags);
    napi_set_named_property(env, obj, "flags", flagsArr);
    napi_value savedArr = qjsStringArrayToNapi(env, out.savedNames);
    napi_set_named_property(env, obj, "savedNames", savedArr);
    setString("outputFileName", out.outputFileName);
    setInt64("outputBytes", out.outputBytes);
    setString("outputHead", out.outputHead);
    setString("outputTail", out.outputTail);
    return obj;
}

// worker 线程执行（纯计算 + 文件闸——不碰 napi）。★ C++ 异常屏障（2026-10-07 修复，
// codeexec.cpp OnExecute 同款）：内存极端紧张时 QjsRunScript 内大分配可抛 std::bad_alloc
// ——异常穿 napi 的 C 回调边界即 std::terminate 进 cppcrash，此置 ok=false + 中文句形态
// （装配层判定表 engine-error 分支承接，不静默）；Host* 宿主回调在本调用栈内一并罩住。
static void QjsOnExecute(napi_env env, void* data)
{
    QjsRunWorkData* wd = static_cast<QjsRunWorkData*>(data);
    (void)env;
    try {
        wd->outcome = QjsRunScript(wd->code, wd->opts, wd->cancelBlock);
    } catch (...) {
        OH_LOG_ERROR(LOG_APP, "qjs run threw, fallback to engine-error receipt");
        wd->outcome = QjsRunOutcome();
        wd->outcome.errorMessage = "执行内存不足";
    }
}

// 主线程完成：组装结果 resolve + 释放并发位 + 注销取消块 + 清理
static void QjsOnComplete(napi_env env, napi_status status, void* data)
{
    QjsRunWorkData* wd = static_cast<QjsRunWorkData*>(data);
    napi_value result = qjsOutcomeToNapi(env, wd->outcome);
    if (status == napi_ok) {
        napi_resolve_deferred(env, wd->deferred, result);
    } else {
        napi_value undefined = nullptr;
        napi_get_undefined(env, &undefined);
        napi_reject_deferred(env, wd->deferred, undefined);
    }
    napi_delete_async_work(env, wd->work);
    // 取消块注销 + 释放（★ 2026-10-20 并发笔：成对释放红线——OnComplete 是块生命周期
    // 唯一终点；本引擎：超时经 interrupt handler 真中断 → native settle 秒级 → 此处
    // 释放即时；JSVM 侧须等脚本自然结束——能力差异的工程体现）
    QjsUnregisterCancelBlock(wd->opts.runKey);
    delete wd->cancelBlock;
    delete wd;
    gQjsActiveRuns.fetch_sub(1);
}

// runScript(code, options)（异步——返回 Promise）
static napi_value QjsRunScriptNapi(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2] = { nullptr };
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 2) {
        napi_throw_type_error(env, nullptr, "runScript 需要 code 与 options 两个参数");
        return nullptr;
    }
    std::string code;
    QjsRunOptions opts;
    // ★ 主线程异常屏障（2026-10-07 增量，codeexec.cpp 同款）：取串与 options 解析内的
    // std::string 分配可抛 std::bad_alloc——转 napi 抛错而非崩溃。锁未占、promise 未建。
    try {
        if (!qjsNapiReadString(env, argv[0], code)) {
            napi_throw_type_error(env, nullptr, "code 必须是字符串");
            return nullptr;
        }
        if (!qjsParseOptions(env, argv[1], opts)) {
            napi_throw_type_error(env, nullptr, "options 字段缺失或类型不符");
            return nullptr;
        }
    } catch (...) {
        OH_LOG_ERROR(LOG_APP, "qjs runScript alloc threw (parsing)");
        napi_throw_error(env, nullptr, "内存不足，无法发起脚本执行");
        return nullptr;
    }

    napi_deferred deferred = nullptr;
    napi_value promise = nullptr;
    napi_create_promise(env, &deferred, &promise);

    // 并发位占位（fetch_add 原子递增判上限——计数已达上限时立即 resolve BusyError 形态
    // 不建 work；占位路径回滚自身递减：计数属在跑的 work，本路径无权多占）
    if (gQjsActiveRuns.fetch_add(1) >= QJS_NATIVE_MAX_CONCURRENT_RUNS) {
        gQjsActiveRuns.fetch_sub(1);
        QjsRunOutcome busy;
        busy.errorName = "BusyError";
        busy.errorMessage = "上一个脚本仍在运行，请稍后重试。";
        napi_resolve_deferred(env, deferred, qjsOutcomeToNapi(env, busy));
        return promise;
    }

    // 载荷构建（★屏障段：new 与注册表插入可抛——此刻并发位已占，catch 必须复位计数并
    // 注销释放已建的取消块）
    QjsRunWorkData* wd = nullptr;
    QjsCancelBlock* cancelBlock = nullptr;
    try {
        wd = new QjsRunWorkData();
        cancelBlock = new QjsCancelBlock();
        QjsRegisterCancelBlock(opts.runKey, cancelBlock);
        wd->deferred = deferred;
        wd->code = std::move(code);
        wd->opts = opts;
        wd->cancelBlock = cancelBlock;
    } catch (...) {
        OH_LOG_ERROR(LOG_APP, "qjs runScript alloc threw (busy held)");
        delete wd;
        if (cancelBlock != nullptr) {
            QjsUnregisterCancelBlock(opts.runKey);
            delete cancelBlock;
        }
        gQjsActiveRuns.fetch_sub(1);
        napi_throw_error(env, nullptr, "内存不足，无法发起脚本执行");
        return nullptr;
    }
    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "qjsEngineRunScript", NAPI_AUTO_LENGTH, &resourceName);
    napi_status created = napi_create_async_work(env, nullptr, resourceName, QjsOnExecute,
        QjsOnComplete, wd, &wd->work);
    if (created != napi_ok) {
        QjsRunOutcome failed;
        failed.errorMessage = "异步任务创建失败";
        napi_resolve_deferred(env, deferred, qjsOutcomeToNapi(env, failed));
        QjsUnregisterCancelBlock(wd->opts.runKey);
        delete wd->cancelBlock;
        delete wd;
        gQjsActiveRuns.fetch_sub(1);
        return promise;
    }
    // ★ 排队失败兜底（2026-10-07 修复）：原返回值丢弃——排队失败时
    // OnExecute/OnComplete 永不执行，deferred 永不 settle、并发位恒占、取消块泄漏、
    // settle 驱动永久卡死且零日志。照「异步任务创建失败」同款兜底：resolve 失败形态 +
    // 删已建成的 work + 注销取消块 + 复位计数 + hilog 留痕。
    if (napi_queue_async_work(env, wd->work) != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "qjs queue async work failed");
        QjsRunOutcome failed;
        failed.errorMessage = "异步任务排队失败";
        napi_resolve_deferred(env, deferred, qjsOutcomeToNapi(env, failed));
        napi_delete_async_work(env, wd->work);
        QjsUnregisterCancelBlock(wd->opts.runKey);
        delete wd->cancelBlock;
        delete wd;
        gQjsActiveRuns.fetch_sub(1);
        return promise;
    }
    return promise;
}

// cancelRunning(runKey)（★ 2026-10-20 并发笔〔方案 §R U3〕：按 runKey 定向置位——查
// per-run 取消注册表，命中置 requested + 定向唤醒该 runKey 阻塞中的网络桥等待
// 〔QjsHttpAbortWaits 一口承担，他路在途请求不受扰〕返 true、未命中返 false 不置任何
// 标记〔D4 契约保持〕；计数快查只是免查表的短路位）
static napi_value QjsCancelRunning(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = { nullptr };
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 1) {
        napi_throw_type_error(env, nullptr, "cancelRunning 需要一个 runKey 字符串参数");
        return nullptr;
    }
    // ★ 主线程异常屏障（取串分配可抛——照 QjsRunScriptNapi 同款转 napi 抛错而非崩溃）
    bool accepted = false;
    std::string runKey;
    try {
        if (!qjsNapiReadString(env, argv[0], runKey)) {
            napi_throw_type_error(env, nullptr, "cancelRunning 的 runKey 必须是字符串");
            return nullptr;
        }
        if (gQjsActiveRuns.load() > 0) {
            std::lock_guard<std::mutex> lock(gQjsCancelRegistryMutex);
            auto it = gQjsCancelRegistry.find(runKey);
            if (it != gQjsCancelRegistry.end()) {
                it->second->requested.store(true);
                accepted = true;
            }
        }
    } catch (...) {
        OH_LOG_ERROR(LOG_APP, "qjs cancelRunning threw");
        napi_throw_error(env, nullptr, "内存不足，取消未完成");
        return nullptr;
    }
    // 定向唤醒（锁外调——置位与唤醒非原子无害：晚到的置败对已 done 条目静默丢弃）
    if (accepted) {
        QjsHttpAbortWaits(runKey);
    }
    napi_value result = nullptr;
    napi_get_boolean(env, accepted, &result);
    return result;
}

// setHttpDispatcher(dispatcher)（自有 TSFN 安装点——笔F 书 §3.7-5；幂等）
static napi_value QjsSetHttpDispatcher(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = { nullptr };
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 1) {
        napi_throw_type_error(env, nullptr, "setHttpDispatcher 需要一个函数参数");
        return nullptr;
    }
    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, argv[0], &type) != napi_ok || type != napi_function) {
        napi_throw_type_error(env, nullptr, "setHttpDispatcher 的参数必须是函数");
        return nullptr;
    }
    const bool installed = QjsHttpInstallDispatcher(env, argv[0]);
    napi_value result = nullptr;
    napi_get_boolean(env, installed, &result);
    return result;
}

// resolveHttpCall(callId, resultJson, bytes?)（回填一次桥待办；未命中静默丢弃）
static napi_value QjsResolveHttpCall(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value argv[3] = { nullptr, nullptr, nullptr };
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 2) {
        napi_throw_type_error(env, nullptr, "resolveHttpCall 需要 callId 与 resultJson 两个参数");
        return nullptr;
    }
    std::string callId;
    std::string resultJson;
    // ★ 主线程异常屏障（2026-10-07 增量，codeexec.cpp 同款）：取串与回填内的 std::string
    // 分配可抛 std::bad_alloc——转 napi 抛错而非崩溃；QjsHttpResolve 锁内赋值有强异常
    // 保证，catch 时待办表状态不被污染。
    try {
        if (!qjsNapiReadString(env, argv[0], callId) ||
            !qjsNapiReadString(env, argv[1], resultJson)) {
            napi_throw_type_error(env, nullptr, "resolveHttpCall 的 callId 与 resultJson 必须是字符串");
            return nullptr;
        }
        napi_value bytesArg = argc >= 3 ? argv[2] : nullptr;
        QjsHttpResolve(env, callId, resultJson, bytesArg);
    } catch (...) {
        OH_LOG_ERROR(LOG_APP, "qjs resolveHttpCall threw");
        napi_throw_error(env, nullptr, "内存不足，回填未完成");
        return nullptr;
    }
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

// 模块注册（官方范式：constructor 自动注册；nm_modname = qjsengine → libqjsengine.so）
EXTERN_C_START
static napi_value QjsInit(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "runScript", nullptr, QjsRunScriptNapi, nullptr, nullptr, nullptr, napi_default,
          nullptr },
        { "cancelRunning", nullptr, QjsCancelRunning, nullptr, nullptr, nullptr, napi_default,
          nullptr },
        { "setHttpDispatcher", nullptr, QjsSetHttpDispatcher, nullptr, nullptr, nullptr,
          napi_default, nullptr },
        { "resolveHttpCall", nullptr, QjsResolveHttpCall, nullptr, nullptr, nullptr,
          napi_default, nullptr }
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module qjsEngineModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = QjsInit,
    .nm_modname = "qjsengine",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterQjsEngineModule(void)
{
    napi_module_register(&qjsEngineModule);
}
