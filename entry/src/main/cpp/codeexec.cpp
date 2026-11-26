// 代码工作台 napi 入口（2026-10-05 端侧代码工作台笔，任务书 §3.1/§3.2-1）：
// ArkTS ↔ native 合同——runScript(code, options) 异步执行（napi_create_async_work，
// worker 线程跑 JSVM）+ cancelRunning(runKey) 按 runKey 定向置取消标记（★ 2026-10-20
// 并发笔，方案 §R）。
// · 并发计数锁（进程级，K 路上限见下方常量）：满时新调用**立即 resolve** BusyError 形态
//   结果（errorName='BusyError' + 固定中文句——ScriptReceipt 判定表序 1），不排队不阻塞；
//   释放时机 = async work 完成回调（超时后 ArkTS 侧丢弃结果不影响本侧释放——A9 忙锁
//   保持到 native 真正 settle）。
// · 结果组装（OnComplete 主线程）：JsvmRunOutcome → napi 对象（字段清单与
//   types/libcodeexec/index.d.ts / ScriptEngine.ets 同构——三处同步红线）。
// · 本文件不写业务——执行在 jsvm_runner.cpp，文件闸在 sandbox_fs.cpp。
#include <atomic>
#include <cstring>
#include <string>

#include "hilog/log.h"
#include "jsvm_runner.h"
#include "napi/native_api.h"
#include "sandbox_http.h"

// 进程级并发计数锁（★ 2026-10-20 并发笔〔方案 §R U2〕：原单布尔 gBusy 改 K 路计数——
// 计数 ≥ 上限时新调用立即 resolve BusyError 形态〔句逐字不变〕不排队不阻塞；ArkTS 调度器
// SCRIPT_MAX_CONCURRENT 是唯一编排闸，本上限 = 纵深防线位，**与 ArkTS 侧同值 K=2**〔注释
// 声明不落第二处逻辑〕；释放时机 = async work 完成回调〔超时后 ArkTS 侧丢弃结果不影响本侧
// 释放——A9 忙锁保持到 native 真正 settle〕）
static std::atomic<int32_t> gActiveRuns(0);
static constexpr int32_t NATIVE_MAX_CONCURRENT_RUNS = 2;

// napi 取串（两段式：先取长再取内容）
static bool napiReadString(napi_env env, napi_value v, std::string& out)
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

// options 对象逐字段解析（数值字段全 double 通道再转整——napi 数字统一形态）
static bool parseOptions(napi_env env, napi_value obj, JsvmRunOptions& opts)
{
    napi_value field = nullptr;
    auto readString = [&](const char* key, std::string& target) -> bool {
        if (napi_get_named_property(env, obj, key, &field) != napi_ok || field == nullptr) {
            return false;
        }
        return napiReadString(env, field, target);
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
    // maxLogLines 宽容缺省（0 = 不限条数、字节预算仍兜底）——旧调用方不传不炸；
    // ToolCodeExec 组装恒下发（★ 2026-10-06 溢出修复笔）
    (void)readNumber("maxLogLines", maxLogLines);
    // runKey 宽容缺省（空串——★ 2026-10-20 并发笔：调度器注入的 per-run 取消目标键，
    // 调用方不填不炸；空串并发会在取消注册表互覆，调度器唯一注入后封闭）
    (void)readString("runKey", opts.runKey);
    opts.timeoutMs = static_cast<int64_t>(timeoutMs);
    opts.maxHeapBytes = static_cast<size_t>(maxHeap);
    opts.maxOutputChars = static_cast<size_t>(maxOutput);
    opts.maxLogLines = static_cast<size_t>(maxLogLines);
    opts.fsLimits.maxFileBytes = static_cast<size_t>(maxFile);
    opts.fsLimits.maxTotalBytes = static_cast<size_t>(maxTotal);
    // httpWaitMs 必填（★ 2026-10-06 代码工作台笔E——桥等待上限恒由 ArkTS 侧算好下传，
    // 缺字段即失败：防旧调用方静默落 0 使 httpGet 立即等待超时）
    opts.httpWaitMs = static_cast<int64_t>(httpWaitMs);
    return true;
}

// 异步工作载荷（Execute 与 OnComplete 之间共享；OnComplete 尾删除）。cancelBlock =
// 本 run 取消块（★ 2026-10-20 并发笔：RunScript 主线程 new + 注册，OnComplete 主线程
// 注销 + delete——块生命周期唯一终点，napi 保证 OnComplete 晚于 Execute，worker 读取
// requested 全程块存活，无悬垂）
struct RunWorkData {
    napi_deferred deferred = nullptr;
    napi_async_work work = nullptr;
    std::string code;
    JsvmRunOptions opts;
    JsvmRunOutcome outcome;
    JsvmCancelBlock* cancelBlock = nullptr;
};

// 字符串数组 → napi 数组（logs / savedNames / flags）
static napi_value stringArrayToNapi(napi_env env, const std::vector<std::string>& items)
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

// JsvmRunOutcome → napi 结果对象（字段清单三处同步：index.d.ts / ScriptEngine.ets）
static napi_value outcomeToNapi(napi_env env, const JsvmRunOutcome& out)
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
    napi_value logsArr = stringArrayToNapi(env, out.logs);
    napi_set_named_property(env, obj, "logs", logsArr);
    setString("errorName", out.errorName);
    setString("errorMessage", out.errorMessage);
    setString("errorStack", out.errorStack);
    setInt64("durationMs", out.durationMs);
    napi_value flagsArr = stringArrayToNapi(env, out.flags);
    napi_set_named_property(env, obj, "flags", flagsArr);
    napi_value savedArr = stringArrayToNapi(env, out.savedNames);
    napi_set_named_property(env, obj, "savedNames", savedArr);
    setString("outputFileName", out.outputFileName);
    setInt64("outputBytes", out.outputBytes);
    setString("outputHead", out.outputHead);
    setString("outputTail", out.outputTail);
    return obj;
}

// worker 线程执行（纯计算 + 文件闸——不碰 napi）。★ C++ 异常屏障（2026-10-07 修复）：
// 内存极端紧张时 JsvmRunScript 内大分配（全文拼接 / 日志收集 / 文件读回，单件 10 MB 量级）
// 可抛 std::bad_alloc——异常穿 napi 的 C 回调边界即 std::terminate 进 cppcrash，而设计上
// 此刻应走 engine-error 结构化回执（全文件「一切失败皆结构化回执」契约）。此处置 ok=false
// + 空错误名 + 中文句（装配层判定表 engine-error 分支承接，不静默）；Host* 宿主回调在本
// 调用栈内一并罩住。
static void OnExecute(napi_env env, void* data)
{
    RunWorkData* wd = static_cast<RunWorkData*>(data);
    (void)env;
    try {
        wd->outcome = JsvmRunScript(wd->code, wd->opts, wd->cancelBlock);
    } catch (...) {
        OH_LOG_ERROR(LOG_APP, "codeexec run threw, fallback to engine-error receipt");
        wd->outcome = JsvmRunOutcome();
        wd->outcome.errorMessage = "执行内存不足";
    }
}

// 主线程完成：组装结果 resolve + 释放并发位 + 注销取消块 + 清理
static void OnComplete(napi_env env, napi_status status, void* data)
{
    RunWorkData* wd = static_cast<RunWorkData*>(data);
    napi_value result = outcomeToNapi(env, wd->outcome);
    if (status == napi_ok) {
        napi_resolve_deferred(env, wd->deferred, result);
    } else {
        napi_value undefined = nullptr;
        napi_get_undefined(env, &undefined);
        napi_reject_deferred(env, wd->deferred, undefined);
    }
    napi_delete_async_work(env, wd->work);
    // 取消块注销 + 释放（★ 2026-10-20 并发笔：成对释放红线——OnComplete 是块生命周期
    // 唯一终点；此点在计数释放前，注册表条目存在期内计数恒反映在跑）
    JsvmUnregisterCancelBlock(wd->opts.runKey);
    delete wd->cancelBlock;
    delete wd;
    // 并发位释放（A9：超时丢弃不影响本侧——native settle 即释放）
    gActiveRuns.fetch_sub(1);
}

// runScript(code, options)（异步——返回 Promise）
static napi_value RunScript(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2] = { nullptr };
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 2) {
        napi_throw_type_error(env, nullptr, "runScript 需要 code 与 options 两个参数");
        return nullptr;
    }
    std::string code;
    JsvmRunOptions opts;
    // ★ 主线程异常屏障（2026-10-07 增量，OnExecute 同契约）：取串与 options 解析内的
    // std::string 分配可抛 std::bad_alloc，异常穿 napi 回调边界即 std::terminate——
    // 此处转 napi 抛错（中文句）而非崩溃。锁未占、promise 未建，直接抛出安全。
    try {
        if (!napiReadString(env, argv[0], code)) {
            napi_throw_type_error(env, nullptr, "code 必须是字符串");
            return nullptr;
        }
        if (!parseOptions(env, argv[1], opts)) {
            napi_throw_type_error(env, nullptr, "options 字段缺失或类型不符");
            return nullptr;
        }
    } catch (...) {
        OH_LOG_ERROR(LOG_APP, "codeexec runScript alloc threw (parsing)");
        napi_throw_error(env, nullptr, "内存不足，无法发起脚本执行");
        return nullptr;
    }

    napi_deferred deferred = nullptr;
    napi_value promise = nullptr;
    napi_create_promise(env, &deferred, &promise);

    // 并发位占位（fetch_add 原子递增判上限——计数已达上限时立即 resolve BusyError 形态，
    // 不建 work；占位路径回滚自身递减：计数属在跑的 work，本路径无权多占）
    if (gActiveRuns.fetch_add(1) >= NATIVE_MAX_CONCURRENT_RUNS) {
        gActiveRuns.fetch_sub(1);
        JsvmRunOutcome busy;
        busy.errorName = "BusyError";
        busy.errorMessage = "上一个脚本仍在运行，请稍后重试。";
        napi_resolve_deferred(env, deferred, outcomeToNapi(env, busy));
        return promise;
    }

    // 载荷构建（★屏障段：new 与注册表插入可抛——此刻并发位已占，catch 必须复位计数并
    // 注销释放已建的取消块，否则并发位恒占后续全回 BusyError）
    RunWorkData* wd = nullptr;
    JsvmCancelBlock* cancelBlock = nullptr;
    try {
        wd = new RunWorkData();
        cancelBlock = new JsvmCancelBlock();
        JsvmRegisterCancelBlock(opts.runKey, cancelBlock);
        wd->deferred = deferred;
        wd->code = std::move(code);
        wd->opts = opts;
        wd->cancelBlock = cancelBlock;
    } catch (...) {
        OH_LOG_ERROR(LOG_APP, "codeexec runScript alloc threw (busy held)");
        delete wd;
        if (cancelBlock != nullptr) {
            JsvmUnregisterCancelBlock(opts.runKey);
            delete cancelBlock;
        }
        gActiveRuns.fetch_sub(1);
        napi_throw_error(env, nullptr, "内存不足，无法发起脚本执行");
        return nullptr;
    }
    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "codeexecRunScript", NAPI_AUTO_LENGTH, &resourceName);
    napi_status created = napi_create_async_work(env, nullptr, resourceName, OnExecute, OnComplete,
        wd, &wd->work);
    if (created != napi_ok) {
        JsvmRunOutcome failed;
        failed.errorMessage = "异步任务创建失败";
        napi_resolve_deferred(env, deferred, outcomeToNapi(env, failed));
        JsvmUnregisterCancelBlock(wd->opts.runKey);
        delete wd->cancelBlock;
        delete wd;
        gActiveRuns.fetch_sub(1);
        return promise;
    }
    // ★ 排队失败兜底（2026-10-07 修复）：原返回值丢弃——排队失败（env 关闭中等异常态）时
    // OnExecute/OnComplete 永不执行，deferred 永不 settle、并发位恒占（后续全回 BusyError）、
    // 取消块泄漏、调度器 settle 驱动永久卡死且零日志。照「异步任务创建失败」同款兜底：
    // resolve 失败形态 + 删已建成的 work + 注销取消块 + 复位计数 + hilog 留痕。
    if (napi_queue_async_work(env, wd->work) != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "codeexec queue async work failed");
        JsvmRunOutcome failed;
        failed.errorMessage = "异步任务排队失败";
        napi_resolve_deferred(env, deferred, outcomeToNapi(env, failed));
        napi_delete_async_work(env, wd->work);
        JsvmUnregisterCancelBlock(wd->opts.runKey);
        delete wd->cancelBlock;
        delete wd;
        gActiveRuns.fetch_sub(1);
        return promise;
    }
    return promise;
}

// cancelRunning(runKey)（★ 2026-10-20 并发笔〔方案 §R U2〕：按 runKey 定向置位——查
// per-run 取消注册表，命中置 requested 返 true、未命中返 false 不置任何标记（D4「无命中
// 不置位」契约保持，原 gBusy.load() 忙判断缩窗被注册表命中天然替代——计数快查只是免查
// 表的短路位）；结果标 canceled 由 ArkTS 侧丢弃，不承诺中断正在跑的脚本，A9）。
static napi_value CancelRunning(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = { nullptr };
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 1) {
        napi_throw_type_error(env, nullptr, "cancelRunning 需要一个 runKey 字符串参数");
        return nullptr;
    }
    // ★ 主线程异常屏障（取串分配可抛——照 RunScript 同款转 napi 抛错而非崩溃）
    bool accepted = false;
    try {
        std::string runKey;
        if (!napiReadString(env, argv[0], runKey)) {
            napi_throw_type_error(env, nullptr, "cancelRunning 的 runKey 必须是字符串");
            return nullptr;
        }
        if (gActiveRuns.load() > 0) {
            accepted = JsvmCancelRunByKey(runKey);
        }
    } catch (...) {
        OH_LOG_ERROR(LOG_APP, "codeexec cancelRunning threw");
        napi_throw_error(env, nullptr, "内存不足，取消未完成");
        return nullptr;
    }
    napi_value result = nullptr;
    napi_get_boolean(env, accepted, &result);
    return result;
}

// setHttpDispatcher(dispatcher)（★ 2026-10-06 代码工作台笔E）：注册沙箱网络桥的
// ArkTS dispatcher（主线程调；TSFN 单例幂等——桥件以布尔守卫只装一次，返回 false =
// 已注册或注册失败，桥按「已注册」防御，不构成失败信号）
static napi_value SetHttpDispatcher(napi_env env, napi_callback_info info)
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
    const bool installed = SandboxHttpInstallDispatcher(env, argv[0]);
    napi_value result = nullptr;
    napi_get_boolean(env, installed, &result);
    return result;
}

// resolveHttpCall(callId, resultJson, bytes?)（笔E）：回填一次桥待办（主线程调；未命中或
// 已放弃静默丢弃——迟到回填不污染状态）。bytes 可选（ArrayBuffer；无字节体不传）
static napi_value ResolveHttpCall(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value argv[3] = { nullptr, nullptr, nullptr };
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 2) {
        napi_throw_type_error(env, nullptr, "resolveHttpCall 需要 callId 与 resultJson 两个参数");
        return nullptr;
    }
    std::string callId;
    std::string resultJson;
    // ★ 主线程异常屏障（2026-10-07 增量）：取串与回填内的 std::string 分配（resultJson
    // 解析、响应体 bytes 拷贝可达 MB 级）可抛 std::bad_alloc——转 napi 抛错而非崩溃。
    // SandboxHttpResolve 锁内赋值有强异常保证（basic_string::operator= 失败左值不变），
    // catch 时待办表状态不被污染。
    try {
        if (!napiReadString(env, argv[0], callId) || !napiReadString(env, argv[1], resultJson)) {
            napi_throw_type_error(env, nullptr, "resolveHttpCall 的 callId 与 resultJson 必须是字符串");
            return nullptr;
        }
        napi_value bytesArg = argc >= 3 ? argv[2] : nullptr;
        SandboxHttpResolve(env, callId, resultJson, bytesArg);
    } catch (...) {
        OH_LOG_ERROR(LOG_APP, "codeexec resolveHttpCall threw");
        napi_throw_error(env, nullptr, "内存不足，回填未完成");
        return nullptr;
    }
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

// 模块注册（官方范式：constructor 自动注册）
EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "runScript", nullptr, RunScript, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "cancelRunning", nullptr, CancelRunning, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setHttpDispatcher", nullptr, SetHttpDispatcher, nullptr, nullptr, nullptr,
          napi_default, nullptr },
        { "resolveHttpCall", nullptr, ResolveHttpCall, nullptr, nullptr, nullptr,
          napi_default, nullptr }
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module codeexecModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "codeexec",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterCodeexecModule(void)
{
    napi_module_register(&codeexecModule);
}
