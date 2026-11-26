// QuickJS 沙箱网络桥实现（头注释见 qjs_http.h；形态对照件 = sandbox_http.cpp〔笔E〕
// ——官方 TSFN 范式与三出口纪律照抄其形，差异仅在「取消唤醒」机制位与符号命名）。
#include "qjs_http.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <mutex>
#include <unordered_map>

#include "hilog/log.h"

namespace {

// ── 待办表（worker 登记 → 主线程回填 / worker 超时注销；唯一一把锁保护）──
// runKey 字段（★ 2026-10-20 并发笔）：定向唤醒的匹配键——QjsHttpAbortWaits 按 runKey
// 置败，他 runKey 在途请求不受扰。
struct QjsPendingCall {
    bool done = false;      // 主线程回填置位（resultJson / bytes 就绪；定向取消同点置位）
    std::string runKey;     // 本待办所属 run（登记时自调用方填）
    std::string resultJson;
    std::string bytes;
};

std::mutex gQjsPendingMutex;
std::condition_variable gQjsPendingCv;
std::unordered_map<std::string, QjsPendingCall> gQjsPendingCalls;

// callId 递增序号（进程内唯一；前缀 q 防与其他域 id 形态混淆）
std::atomic<uint64_t> gQjsCallSeq(0);

// TSFN 单例与 dispatcher 强引用（幂等守卫判 tsfn；无销毁路径——进程退出系统回收）
napi_threadsafe_function gQjsDispatcherTsfn = nullptr;
napi_ref gQjsDispatcherRef = nullptr;

// 投递载荷（堆分配，call_js_cb 消费即 delete；投递失败由投递方 delete——两出口都有
// 唯一属主，无泄漏路径）。★ 2026-10-20 并发笔：第四串 runKey 随载荷透传（桥侧
// per-run 槽键——ArkTS dispatcher 第四参的 native 半）
struct QjsBridgeCall {
    std::string callId;
    std::string url;
    std::string optsJson;
    std::string runKey;
};

// callId 载荷标失败并唤醒（call_js_cb 内 napi 调用失败的防御支——主线程侧任何失败都
// 必须回填，绝不让 worker 等满上限）
void qjsFailPendingCall(const std::string& callId, const std::string& reason)
{
    std::lock_guard<std::mutex> lock(gQjsPendingMutex);
    auto it = gQjsPendingCalls.find(callId);
    if (it == gQjsPendingCalls.end()) {
        return; // 未登记（含已收场注销出表——迟到回填静默丢弃由出表独自达成）——静默
    }
    it->second.resultJson = "{\"error\":\"" + reason + "\"}";
    it->second.done = true;
    gQjsPendingCv.notify_all();
}

// 主线程执行（TSFN 回调）：经 napi_ref 取 dispatcher 函数值，四参调用（callId / url /
// optsJson / runKey 串——★ 2026-10-20 并发笔加第四参）——dispatcher 是 async 函数，返回的
// Promise 不消费（回填走 resolveHttpCall）
void QjsDispatcherCallJs(napi_env env, napi_value jsCb, void* context, void* data)
{
    (void)jsCb; // func 传 nullptr 形态——函数值自 ref 取（官方指南示例同款）
    (void)context;
    QjsBridgeCall* call = static_cast<QjsBridgeCall*>(data);
    if (call == nullptr) {
        return; // 不可达防御
    }
    napi_value fn = nullptr;
    if (gQjsDispatcherRef == nullptr ||
        napi_get_reference_value(env, gQjsDispatcherRef, &fn) != napi_ok || fn == nullptr) {
        OH_LOG_ERROR(LOG_APP, "qjs http dispatcher ref unavailable");
        qjsFailPendingCall(call->callId, "网络请求未能交给应用发送。请稍后重试。");
        delete call;
        return;
    }
    napi_value argv[4] = { nullptr };
    napi_create_string_utf8(env, call->callId.c_str(), call->callId.size(), &argv[0]);
    napi_create_string_utf8(env, call->url.c_str(), call->url.size(), &argv[1]);
    napi_create_string_utf8(env, call->optsJson.c_str(), call->optsJson.size(), &argv[2]);
    napi_create_string_utf8(env, call->runKey.c_str(), call->runKey.size(), &argv[3]);
    napi_value global = nullptr;
    napi_get_global(env, &global);
    napi_value result = nullptr;
    // dispatcher 内部全程 try/catch（ArkTS 桥件纪律）；此处再包一层状态核查（任一串
    // 创建失败即回填失败，防 worker 等满）
    if (argv[0] == nullptr || argv[1] == nullptr || argv[2] == nullptr ||
        argv[3] == nullptr ||
        napi_call_function(env, global, fn, 4, argv, &result) != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "qjs http dispatcher invoke failed");
        qjsFailPendingCall(call->callId, "网络请求未能交给应用发送。请稍后重试。");
    }
    delete call;
}

// ── resultJson 最小解析（只认三形态；error 值支持 JSON.stringify 常见转义——与
//    sandbox_http.parseBridgeResult 同形）──

void qjsAppendCodeUnitUtf8(std::string& out, uint32_t cp)
{
    if (cp < 0x80) {
        out.push_back(static_cast<char>(cp));
    } else if (cp < 0x800) {
        out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else if (cp < 0x10000) {
        out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else {
        out.push_back(static_cast<char>(0xF0 | (cp >> 18)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    }
}

int qjsHexValue(char c)
{
    if (c >= '0' && c <= '9') {
        return c - '0';
    }
    if (c >= 'a' && c <= 'f') {
        return c - 'a' + 10;
    }
    if (c >= 'A' && c <= 'F') {
        return c - 'A' + 10;
    }
    return -1;
}

void qjsParseBridgeResult(const std::string& json, std::string& kind, std::string& error)
{
    const size_t kindPos = json.find("\"kind\"");
    const size_t errPos = json.find("\"error\"");
    const size_t valueStart = kindPos != std::string::npos ?
        json.find(':', kindPos + 6) : json.find(':', errPos + 7);
    if (errPos == std::string::npos && kindPos == std::string::npos) {
        return;
    }
    if (valueStart == std::string::npos) {
        return;
    }
    const size_t strStart = json.find('"', valueStart + 1);
    if (strStart == std::string::npos) {
        return;
    }
    std::string value;
    for (size_t i = strStart + 1; i < json.size(); i++) {
        char c = json[i];
        if (c == '"') {
            break;
        }
        if (c != '\\') {
            value.push_back(c);
            continue;
        }
        if (i + 1 >= json.size()) {
            break;
        }
        char esc = json[++i];
        switch (esc) {
            case '"': value.push_back('"'); break;
            case '\\': value.push_back('\\'); break;
            case '/': value.push_back('/'); break;
            case 'n': value.push_back('\n'); break;
            case 'r': value.push_back('\r'); break;
            case 't': value.push_back('\t'); break;
            case 'b': value.push_back('\b'); break;
            case 'f': value.push_back('\f'); break;
            case 'u': {
                if (i + 4 < json.size()) {
                    int h1 = qjsHexValue(json[i + 1]);
                    int h2 = qjsHexValue(json[i + 2]);
                    int h3 = qjsHexValue(json[i + 3]);
                    int h4 = qjsHexValue(json[i + 4]);
                    if (h1 >= 0 && h2 >= 0 && h3 >= 0 && h4 >= 0) {
                        qjsAppendCodeUnitUtf8(value,
                            static_cast<uint32_t>(h1) << 12 | static_cast<uint32_t>(h2) << 8 |
                            static_cast<uint32_t>(h3) << 4 | static_cast<uint32_t>(h4));
                        i += 4;
                        break;
                    }
                }
                value.push_back('u'); // 转义残缺——按字面透传（防御，不静默丢字符）
                break;
            }
            default: value.push_back(esc); break;
        }
    }
    if (kindPos != std::string::npos && errPos == std::string::npos) {
        kind = value;
    } else if (errPos != std::string::npos && kindPos == std::string::npos) {
        error = value;
    }
}

} // namespace

// 定向取消唤醒（★ 2026-10-20 并发笔，方案 §R U3）：对该 runKey 匹配且未 done 的待办
// 逐条置「已取消」resultJson + done（取消句迁 resultJson 走出口①解析承载——句字面与
// 原 gQjsWaitsAborted 三元支逐字相同），锁内一次 notify_all 收尾——他 runKey 等待者被
// 唤醒后谓词不满足继续等（只多唤醒不多置败）。
void QjsHttpAbortWaits(const std::string& runKey)
{
    std::lock_guard<std::mutex> lock(gQjsPendingMutex);
    for (auto& entry : gQjsPendingCalls) {
        if (entry.second.done || entry.second.runKey != runKey) {
            continue;
        }
        entry.second.resultJson = "{\"error\":\"本次运行已取消，不再发起新的网络请求。\"}";
        entry.second.done = true;
    }
    gQjsPendingCv.notify_all();
}

QjsHttpOutcome QjsHttpRequest(const std::string& url, const std::string& optsJson,
    int64_t waitMs, const std::string& runKey)
{
    QjsHttpOutcome out;
    // ★ 并发下必须用 fetch_add 的返回值取本次序号（返回自增前旧值，+1 即本次唯一序号；
    // 2026-10-20 并发自检修复）：两 worker 交错时 fetch_add 后另起 load 重读可读到同一终值，
    // callId 撞键会致待办互覆与响应串包
    const uint64_t seq = gQjsCallSeq.fetch_add(1) + 1;
    const std::string callId = "q" + std::to_string(seq) + "-" +
        std::to_string(std::chrono::steady_clock::now().time_since_epoch().count());
    {
        std::lock_guard<std::mutex> lock(gQjsPendingMutex);
        QjsPendingCall& pending = gQjsPendingCalls[callId];
        pending.runKey = runKey;
    }
    if (gQjsDispatcherTsfn == nullptr) {
        // dispatcher 未装（理论不可达——引擎进入运行即装；防绕过路径的防御支）
        std::lock_guard<std::mutex> lock(gQjsPendingMutex);
        gQjsPendingCalls.erase(callId);
        out.errorText = "网络请求未能交给应用发送。请稍后重试。";
        return out;
    }
    QjsBridgeCall* call = new QjsBridgeCall();
    call->callId = callId;
    call->url = url;
    call->optsJson = optsJson;
    call->runKey = runKey;
    napi_status acquired = napi_acquire_threadsafe_function(gQjsDispatcherTsfn);
    napi_status posted = acquired == napi_ok ?
        napi_call_threadsafe_function(gQjsDispatcherTsfn, call, napi_tsfn_nonblocking) :
        acquired;
    if (acquired == napi_ok) {
        napi_release_threadsafe_function(gQjsDispatcherTsfn, napi_tsfn_release);
    }
    if (posted != napi_ok) {
        delete call; // 投递失败——载荷属主回到投递方
        std::lock_guard<std::mutex> lock(gQjsPendingMutex);
        gQjsPendingCalls.erase(callId);
        out.errorText = "网络请求未能交给应用发送。请稍后重试。";
        return out;
    }
    // 有界等待（出口①回填〔含定向取消置败形态〕/ 出口②等待到点；★ 2026-10-20 并发笔：
    // 谓词只剩 done——原粘性取消标记删除，取消唤醒经 AbortWaits 置 done 走出口①承载）
    std::unique_lock<std::mutex> lock(gQjsPendingMutex);
    gQjsPendingCv.wait_for(lock, std::chrono::milliseconds(waitMs), [&callId]() {
        auto it = gQjsPendingCalls.find(callId);
        return it != gQjsPendingCalls.end() && it->second.done;
    });
    auto entryIt = gQjsPendingCalls.find(callId);
    const bool doneNow = entryIt != gQjsPendingCalls.end() && entryIt->second.done;
    if (!doneNow) {
        // 出口②等待到点：注销出表——迟到回填经 find 不命中静默丢弃
        // （不回写不通知；置位与出表同临界区，无独立 abandoned 标记的必要——
        // 2026-10-07 孪生死代码清理，sandbox_http.cpp 同款）
        if (entryIt != gQjsPendingCalls.end()) {
            gQjsPendingCalls.erase(entryIt);
        }
        out.errorText = "网络请求等待超时，没有收到结果。请稍后重试，或改用 http_request 工具发送该请求。";
        return out;
    }
    // 出口①回填：取结果并注销
    QjsPendingCall entry = std::move(entryIt->second);
    gQjsPendingCalls.erase(entryIt);
    lock.unlock();
    std::string kind;
    std::string error;
    qjsParseBridgeResult(entry.resultJson, kind, error);
    if (kind == "text") {
        out.ok = true;
        out.kind = "text";
        out.text = std::move(entry.bytes);
    } else if (kind == "bytes") {
        out.ok = true;
        out.kind = "bytes";
        out.bytes = std::move(entry.bytes);
    } else {
        out.errorText = error.empty() ?
            "脚本网络桥没有可用的会话上下文，请求没有发出。请重新运行脚本。" : error;
    }
    return out;
}

bool QjsHttpInstallDispatcher(napi_env env, napi_value dispatcherFn)
{
    if (gQjsDispatcherTsfn != nullptr) {
        return false; // 已注册（幂等）
    }
    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "qjsHttpDispatch", NAPI_AUTO_LENGTH, &resourceName);
    // max_queue_size = 8（★ 2026-10-20 并发笔 4→8：K 路并发在途 ≤K——打满即 nonblocking
    // 投递走「投递失败」防御支）+ initial_thread_count = 1（创建线程持有、永不 release 到
    // 0 → 无销毁路径，进程退出由系统回收）
    napi_status created = napi_create_threadsafe_function(env, dispatcherFn, nullptr,
        resourceName, 8, 1, nullptr, nullptr, nullptr, QjsDispatcherCallJs,
        &gQjsDispatcherTsfn);
    if (created != napi_ok || gQjsDispatcherTsfn == nullptr) {
        gQjsDispatcherTsfn = nullptr;
        OH_LOG_ERROR(LOG_APP, "qjs http tsfn create failed: %{public}d",
            static_cast<int>(created));
        return false;
    }
    if (napi_create_reference(env, dispatcherFn, 1, &gQjsDispatcherRef) != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "qjs http dispatcher ref create failed");
        napi_release_threadsafe_function(gQjsDispatcherTsfn, napi_tsfn_release);
        gQjsDispatcherTsfn = nullptr;
        return false;
    }
    return true;
}

void QjsHttpResolve(napi_env env, const std::string& callId, const std::string& resultJson,
    napi_value bytesOrUndefined)
{
    // 字节即拷即断引用（JS 值不跨线程）
    std::string bytes;
    napi_valuetype type = napi_undefined;
    if (bytesOrUndefined != nullptr &&
        napi_typeof(env, bytesOrUndefined, &type) == napi_ok && type == napi_object) {
        bool isArrayBuffer = false;
        if (napi_is_arraybuffer(env, bytesOrUndefined, &isArrayBuffer) == napi_ok &&
            isArrayBuffer) {
            void* data = nullptr;
            size_t length = 0;
            if (napi_get_arraybuffer_info(env, bytesOrUndefined, &data, &length) == napi_ok &&
                length > 0 && data != nullptr) {
                bytes.assign(static_cast<const char*>(data), length);
            }
        }
    }
    std::lock_guard<std::mutex> lock(gQjsPendingMutex);
    auto it = gQjsPendingCalls.find(callId);
    if (it == gQjsPendingCalls.end() || it->second.done) {
        return; // 未命中（含已收场注销出表）/ 重复回填——静默丢弃
    }
    it->second.resultJson = resultJson;
    it->second.bytes = std::move(bytes);
    it->second.done = true;
    gQjsPendingCv.notify_all();
}
