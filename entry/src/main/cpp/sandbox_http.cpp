// 沙箱网络桥——跨线程机制件实现（头注释见 sandbox_http.h；2026-10-06 代码工作台笔E）。
// · 官方范式 =《Native侧子线程与UI主线程通信》指南示例（func 传 nullptr + call_js_cb
//   经 napi_ref 取函数再调用——官方逐字演示形态）+ FAQ「线程安全函数使用问题汇总」
//   （非创建线程 call 前 acquire、用毕 release；nonblocking 队列满返 napi_queue_full
//   绝不阻塞）；全部签名以本机 SDK node_api.h 实读为准（NAPI_VERSION 8）。
// · 锁纪律：全件唯一一把互斥量（待办表 gPendingMutex）——将来加锁必须在本件登记锁序。
// · 无销毁路径：TSFN 与 napi_ref 均进程级单例，initial_thread_count = 1（创建线程
//   持有）且永不 release 到 0，进程退出由系统回收（与 codeexec.cpp 忙锁同姿态）。
#include "sandbox_http.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <mutex>
#include <unordered_map>

#include "hilog/log.h"

namespace {

// ── 待办表（worker 登记 → 主线程回填 / worker 超时注销；唯一一把锁保护）──
struct PendingCall {
    bool done = false;          // 主线程回填置位（resultJson / bytes 就绪）
    std::string resultJson;
    std::string bytes;
};

std::mutex gPendingMutex;
std::condition_variable gPendingCv;
std::unordered_map<std::string, PendingCall> gPendingCalls;

// callId 递增序号（进程内唯一；前缀 h 防与日志域 id 形态混淆）
std::atomic<uint64_t> gCallSeq(0);

// TSFN 单例与 dispatcher 强引用（InstallDispatcher 首次成功后恒非空；幂等守卫判 tsfn）
napi_threadsafe_function gDispatcherTsfn = nullptr;
napi_ref gDispatcherRef = nullptr;

// 投递载荷（堆分配，call_js_cb 消费即 delete——若投递失败由投递方 delete，两个出口
// 都有唯一属主，无泄漏路径）。★ 2026-10-20 并发笔：第四串 runKey 随载荷透传（桥侧
// per-run 槽键——ArkTS dispatcher 第四参的 native 半）
struct BridgeCall {
    std::string callId;
    std::string url;
    std::string optsJson;
    std::string runKey;
};

// callId 载荷标失败并唤醒（call_js_cb 内 napi 调用失败的防御支——主线程侧任何失败都
// 必须回填，绝不让 worker 等满上限：静态 P0 纪律）
void failPendingCall(const std::string& callId, const std::string& reason)
{
    std::lock_guard<std::mutex> lock(gPendingMutex);
    auto it = gPendingCalls.find(callId);
    if (it == gPendingCalls.end()) {
        return; // 未登记（含已超时注销出表——迟到回填静默丢弃由出表独自达成）——静默
    }
    it->second.resultJson = "{\"error\":\"" + reason + "\"}";
    it->second.done = true;
    gPendingCv.notify_all();
}

// 主线程执行（TSFN 回调）：经 napi_ref 取 dispatcher 函数值，四参调用（callId / url /
// optsJson / runKey 串——★ 2026-10-20 并发笔加第四参）——dispatcher 是 async 函数，返回的
// Promise 不消费（回填走 resolveHttpCall）
void DispatcherCallJs(napi_env env, napi_value jsCb, void* context, void* data)
{
    (void)jsCb;    // func 传 nullptr 形态——函数值自 ref 取（官方指南示例同款）
    (void)context;
    BridgeCall* call = static_cast<BridgeCall*>(data);
    if (call == nullptr) {
        return; // 不可达防御（data 恒非空——投递方保证）
    }
    napi_value fn = nullptr;
    if (gDispatcherRef == nullptr ||
        napi_get_reference_value(env, gDispatcherRef, &fn) != napi_ok || fn == nullptr) {
        OH_LOG_ERROR(LOG_APP, "sandbox http dispatcher ref unavailable");
        failPendingCall(call->callId, "网络请求未能交给应用发送。请稍后重试。");
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
    // dispatcher 内部全程 try/catch（桥件纪律）——异常不会外逸到本回调；此处再包一层
    // 状态核查（任一串创建失败即回填失败，防 worker 等满）
    if (argv[0] == nullptr || argv[1] == nullptr || argv[2] == nullptr ||
        argv[3] == nullptr ||
        napi_call_function(env, global, fn, 4, argv, &result) != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "sandbox http dispatcher invoke failed");
        failPendingCall(call->callId, "网络请求未能交给应用发送。请稍后重试。");
    }
    delete call;
}

// ── resultJson 最小解析（只认三形态：{"kind":"text"} / {"kind":"bytes"} /
//    {"error":"..."}；error 值支持 JSON.stringify 的常见转义）──

// \uXXXX → UTF-8 追加（单 code unit——代理对按 WTF-8 原样落字节，JSVM 侧 CreateStringUtf8
// 遇非法序列替换 U+FFFD 兜底；错误文案为固定中文句 + host，实际不可达路径）
void appendCodeUnitUtf8(std::string& out, uint32_t cp)
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

int hexValue(char c)
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

// 解析结果：kind 非空 = 成功形态；error 非空 = 失败；两者皆空 = 形态不可识别（调用方
// 按内部异常句处理，不静默）
void parseBridgeResult(const std::string& json, std::string& kind, std::string& error)
{
    // 键定位（对象根、至多一个键的固定小形态——不引 JSON 库，找 "kind" / "error" 键名）
    const size_t kindPos = json.find("\"kind\"");
    const size_t errPos = json.find("\"error\"");
    const size_t valueStart = kindPos != std::string::npos ?
        json.find(':', kindPos + 6) : json.find(':', errPos + 7);
    if (valueStart == std::string::npos) {
        return;
    }
    const size_t strStart = json.find('"', valueStart + 1);
    if (strStart == std::string::npos) {
        return;
    }
    // 值串解转义（\" \\ \/ \n \r \t \b \f \uXXXX；裸控制字符原样透传）
    std::string value;
    for (size_t i = strStart + 1; i < json.size(); i++) {
        char c = json[i];
        if (c == '"') {
            break; // 值串终止
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
                    int h1 = hexValue(json[i + 1]);
                    int h2 = hexValue(json[i + 2]);
                    int h3 = hexValue(json[i + 3]);
                    int h4 = hexValue(json[i + 4]);
                    if (h1 >= 0 && h2 >= 0 && h3 >= 0 && h4 >= 0) {
                        appendCodeUnitUtf8(value,
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
        kind = value; // "text" / "bytes"
    } else if (errPos != std::string::npos && kindPos == std::string::npos) {
        error = value;
    }
    // 两键同现（桥不会产出）→ 两值皆空，调用方按不可识别处理
}

} // namespace

SandboxHttpOutcome SandboxHttpRequest(const std::string& url, const std::string& optsJson,
    int64_t waitMs, const std::string& runKey)
{
    SandboxHttpOutcome out;
    // callId = 序号 + 时间戳（进程内唯一）。★ 并发下必须用 fetch_add 的返回值取本次序号
    //（返回自增前旧值，+1 即本次唯一序号；2026-10-20 并发自检修复）：两 worker 交错时
    // fetch_add 后另起 load 重读可读到同一终值，callId 撞键会致待办互覆与响应串包
    const uint64_t seq = gCallSeq.fetch_add(1) + 1;
    const std::string callId = "h" + std::to_string(seq) + "-" +
        std::to_string(std::chrono::steady_clock::now().time_since_epoch().count());
    {
        std::lock_guard<std::mutex> lock(gPendingMutex);
        gPendingCalls[callId] = PendingCall();
    }
    // 投递（worker 侧 acquire → nonblocking call → release 成对；官方线程计数约定——
    // async work 由线程池调度，跨 run 不保证同线程）。K 路并发在途 ≤K，
    // napi_queue_full 属异常防御面
    if (gDispatcherTsfn == nullptr) {
        // dispatcher 未装（理论不可达——引擎进入运行即装；防绕过路径的防御支）
        std::lock_guard<std::mutex> lock(gPendingMutex);
        gPendingCalls.erase(callId);
        out.errorText = "网络请求未能交给应用发送。请稍后重试。";
        return out;
    }
    BridgeCall* call = new BridgeCall();
    call->callId = callId;
    call->url = url;
    call->optsJson = optsJson;
    call->runKey = runKey;
    napi_status acquired = napi_acquire_threadsafe_function(gDispatcherTsfn);
    napi_status posted = acquired == napi_ok ?
        napi_call_threadsafe_function(gDispatcherTsfn, call, napi_tsfn_nonblocking) :
        acquired;
    if (acquired == napi_ok) {
        napi_release_threadsafe_function(gDispatcherTsfn, napi_tsfn_release);
    }
    if (posted != napi_ok) {
        delete call; // 投递失败——载荷属主回到投递方（call_js_cb 未消费）
        std::lock_guard<std::mutex> lock(gPendingMutex);
        gPendingCalls.erase(callId);
        out.errorText = "网络请求未能交给应用发送。请稍后重试。";
        return out;
    }
    // 有界等待（三出口之①②）：回填（done）或到点；waitMs 由 ArkTS 侧下传（本层零字面值）
    std::unique_lock<std::mutex> lock(gPendingMutex);
    const bool filled = gPendingCv.wait_for(lock, std::chrono::milliseconds(waitMs),
        [&callId]() {
            auto it = gPendingCalls.find(callId);
            return it != gPendingCalls.end() && it->second.done;
        });
    if (!filled) {
        // 出口②等待到点：注销出表——迟到回填经 find 不命中静默丢弃（不回写不通知；
        // 置位与出表同临界区，无独立 abandoned 标记的必要）
        gPendingCalls.erase(callId);
        out.errorText = "网络请求等待超时，没有收到结果。请稍后重试，或改用 http_request 工具发送该请求。";
        return out;
    }
    // 出口①回填：取结果并注销（记录本体归表内，注销即出表——回填与超时的竞争由锁串行化）
    PendingCall entry = std::move(gPendingCalls[callId]);
    gPendingCalls.erase(callId);
    lock.unlock();
    std::string kind;
    std::string error;
    parseBridgeResult(entry.resultJson, kind, error);
    if (kind == "text") {
        out.ok = true;
        out.kind = "text";
        out.text = std::move(entry.bytes);
    } else if (kind == "bytes") {
        out.ok = true;
        out.kind = "bytes";
        out.bytes = std::move(entry.bytes);
    } else {
        out.errorText = error.empty() ? "脚本网络桥没有可用的会话上下文，请求没有发出。请重新运行脚本。" :
            error;
    }
    return out;
}

bool SandboxHttpInstallDispatcher(napi_env env, napi_value dispatcherFn)
{
    if (gDispatcherTsfn != nullptr) {
        return false; // 已注册（幂等——桥侧布尔守卫只装一次，本返回值不构成失败信号）
    }
    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "sandboxHttpDispatch", NAPI_AUTO_LENGTH, &resourceName);
    // max_queue_size = 8（★ 2026-10-20 并发笔 4→8：K 路并发在途 ≤K——打满即 nonblocking
    // 投递走「投递失败」防御支，并发 httpGet 失败率上升）+ initial_thread_count = 1（创建线程
    // 持有、永不 release 到 0 → 无销毁路径，进程退出由系统回收）
    napi_status created = napi_create_threadsafe_function(env, dispatcherFn, nullptr,
        resourceName, 8, 1, nullptr, nullptr, nullptr, DispatcherCallJs, &gDispatcherTsfn);
    if (created != napi_ok || gDispatcherTsfn == nullptr) {
        gDispatcherTsfn = nullptr;
        OH_LOG_ERROR(LOG_APP, "sandbox http tsfn create failed: %{public}d",
            static_cast<int>(created));
        return false;
    }
    // dispatcher 函数值的强引用（call_js_cb 里经它取函数——func 形参传 nullptr 的官方形态
    // 配套；ref 与 TSFN 同寿命，无删除路径）
    if (napi_create_reference(env, dispatcherFn, 1, &gDispatcherRef) != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "sandbox http dispatcher ref create failed");
        napi_release_threadsafe_function(gDispatcherTsfn, napi_tsfn_release);
        gDispatcherTsfn = nullptr;
        return false;
    }
    return true;
}

void SandboxHttpResolve(napi_env env, const std::string& callId, const std::string& resultJson,
    napi_value bytesOrUndefined)
{
    // 字节即拷即断引用（JS 值不跨线程）：入口先把 ArrayBuffer 拷进 std::string
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
    std::lock_guard<std::mutex> lock(gPendingMutex);
    auto it = gPendingCalls.find(callId);
    if (it == gPendingCalls.end() || it->second.done) {
        return; // 未命中（含已超时注销出表）/ 重复回填——静默丢弃（晚到回填不污染任何状态）
    }
    it->second.resultJson = resultJson;
    it->second.bytes = std::move(bytes);
    it->second.done = true;
    gPendingCv.notify_all();
}
