// QuickJS 沙箱宿主 API 回调层实现（头注释见 qjs_hostapi.h；2026-10-06 代码工作台
// 笔F——形态对照件 = sandbox_hostapi.cpp，方法语义与中文错误句逐字对齐——同一沙箱的
// 能力不随档位分叉，回执等价的前提）。
// · 共享面经编译副本消费：文件闸 sandbox_fs.*、编解码 sandbox_codec.*、网络桥 qjs_http.*
//   （本引擎自有 TSFN 副本，形态对照 sandbox_http.*——禁代码级共享）。
// · 沙箱两条不软化（A9/A16 同款）：不承诺中断任意脚本（对外口径）；网络能力经 httpGet
//   单通道（默认 GET、写方法需全局开关开启、预授权域名——治理单源在 ArkTS 桥件 ScriptHttpBridge），fetch /
//   XMLHttpRequest 恒不注入。
// · QuickJS 引用计数纪律：JS_ToCString ↔ JS_FreeCString、异常值 JS_GetException 后
//   JS_FreeValue、构造值用毕释放——全部失败路径同样成立（内存防线）。
#include "qjs_hostapi.h"

#include <algorithm>
#include <cstring>

#include "hilog/log.h"
#include "qjs_http.h"
#include "sandbox_codec.h"
#include "sandbox_fs.h"

// ── 运行态取用（★ 2026-10-20 并发笔，方案 §R U3：gQjsCurrentState 全局指针退役）──
// per-run 载体 = ctx opaque（qjs_runner 在 NewContext 后挂入、随 ctx 销毁）——K 路并发
// 各 ctx 各态互不可见；回调本就收 ctx，纯取换。

static QjsRunState* QjsStateOf(JSContext* ctx)
{
    return static_cast<QjsRunState*>(JS_GetContextOpaque(ctx));
}

// ── 取串 / 序列化小件 ──

// 清当前挂起异常（探测失败 / 序列化失败等「有意吞异常」路径统一走此）。JS_GetException
// 返回的异常值是持有引用，弃置不释放会让对象型异常（内建 TypeError 等）永驻 gc_obj_list，
// JS_FreeRuntime 的 gc_obj_list 断言 SIGABRT（quickjs.c:2464，真机实锤形态）——故必须
// 配对 JS_FreeValue，本文件全部吞异常点不得再写裸 `JS_GetException(ctx);`
static void qjsClearPendingException(JSContext* ctx)
{
    JSValue exc = JS_GetException(ctx);
    JS_FreeValue(ctx, exc);
}

std::string qjsValueToUtf8(JSContext* ctx, JSValueConst v)
{
    size_t len = 0;
    const char* s = JS_ToCStringLen(ctx, &len, v);
    if (s == nullptr) {
        // 转换挂起异常（带抛异常 toString 的对象等）——清掉防污染后续 API 调用
        qjsClearPendingException(ctx);
        return "";
    }
    std::string out(s, len);
    JS_FreeCString(ctx, s);
    return out;
}

std::string qjsSerializeJsValue(JSContext* ctx, JSValueConst v)
{
    if (JS_IsString(v)) {
        return qjsValueToUtf8(ctx, v);
    }
    if (JS_IsUndefined(v)) {
        return "undefined";
    }
    if (JS_IsNull(v)) {
        return "null";
    }
    JSValue json = JS_JSONStringify(ctx, v, JS_UNDEFINED, JS_UNDEFINED);
    if (JS_IsException(json)) {
        // 循环引用等序列化异常——清掉再走降级（不清会污染后续调用，照 jsvm 侧同段）
        qjsClearPendingException(ctx);
    } else {
        if (JS_IsString(json)) {
            std::string out = qjsValueToUtf8(ctx, json);
            JS_FreeValue(ctx, json);
            return out;
        }
        JS_FreeValue(ctx, json);
    }
    return qjsValueToUtf8(ctx, v); // 降级 ToCString（内部 ToString；异常自清返空串）
}

// ── 抛错小件（与 jsvm 侧 throwFenceError / throwNamedError 同形）──

// fs 闸拒绝 → JS 异常（name=FenceError + 中文 message；ScriptReceipt 判据主位）
static void qjsThrowFenceError(JSContext* ctx, const std::string& reason)
{
    JSValue err = JS_NewError(ctx);
    JS_SetPropertyStr(ctx, err, "message",
        JS_NewStringLen(ctx, reason.c_str(), reason.size()));
    JS_SetPropertyStr(ctx, err, "name", JS_NewStringLen(ctx, "FenceError", 10));
    JS_Throw(ctx, err); // 调用方一律 return JS_EXCEPTION
}

// 指定错误名的 JS 异常（TypeError / ZlibError / DigestError / HttpError 共用形制）
static void qjsThrowNamedError(JSContext* ctx, const char* name, const std::string& message)
{
    JSValue err = JS_NewError(ctx);
    JS_SetPropertyStr(ctx, err, "message",
        JS_NewStringLen(ctx, message.c_str(), message.size()));
    JS_SetPropertyStr(ctx, err, "name", JS_NewStringLen(ctx, name, std::strlen(name)));
    JS_Throw(ctx, err);
}

// ── 认形与字节互转小件（与 jsvm 侧 sandboxValueToBytes / typeNameOfValue 同语义）──

static const char* qjsTypeNameOfValue(JSContext* ctx, JSValueConst v)
{
    if (JS_IsNumber(v)) {
        return "number";
    }
    if (JS_IsString(v)) {
        return "string";
    }
    if (JS_IsBool(v)) {
        return "boolean";
    }
    if (JS_IsUndefined(v)) {
        return "undefined";
    }
    if (JS_IsNull(v)) {
        return "null";
    }
    if (JS_IsFunction(ctx, v)) {
        return "function";
    }
    if (JS_IsSymbol(v)) {
        return "symbol";
    }
    if (JS_IsBigInt(ctx, v)) {
        return "bigint";
    }
    return "object";
}

// 数据参数认形：string → UTF-8；TypedArray → 底层字节（byteOffset 已含）；其余（含
// ArrayBuffer / DataView）→ false + 中文 errText（调用方拼函数名前缀后抛 TypeError）
static bool qjsValueToBytes(JSContext* ctx, JSValueConst v, std::string& out,
    std::string& errText)
{
    if (JS_IsString(v)) {
        out = qjsValueToUtf8(ctx, v);
        return true;
    }
    size_t byteOffset = 0;
    size_t byteLength = 0;
    size_t bytesPerElement = 0;
    JSValue buf = JS_GetTypedArrayBuffer(ctx, v, &byteOffset, &byteLength, &bytesPerElement);
    if (JS_IsException(buf)) {
        qjsClearPendingException(ctx); // 非 TypedArray 的探测失败——探测必创建一个 TypeError 异常对象，必须配对释放
        errText = std::string(" 的内容只支持字符串或 TypedArray，例如 Uint8Array，当前收到的是 ") +
            qjsTypeNameOfValue(ctx, v) + "。二进制内容可以先用 new TextEncoder().encode(文本) 转成 " +
            "Uint8Array，或从 fs.readBytes 读取。";
        return false;
    }
    size_t abLen = 0;
    uint8_t* abData = JS_GetArrayBuffer(ctx, &abLen, buf);
    if (abData != nullptr && byteLength > 0) {
        out.assign(reinterpret_cast<const char*>(abData + byteOffset), byteLength);
    } else {
        out.clear();
    }
    JS_FreeValue(ctx, buf);
    return true;
}

// 字节 → Uint8Array（ArrayBuffer 拷贝 + 全局 Uint8Array 构造器两步；QuickJS 头文件无
// 直建辅助——JS_CallConstructor 官方口）
static JSValue qjsBytesToUint8Array(JSContext* ctx, const std::string& bytes)
{
    JSValue ab = JS_NewArrayBufferCopy(ctx,
        reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size());
    if (JS_IsException(ab)) {
        return JS_EXCEPTION;
    }
    // 引用纪律：JS_GetGlobalObject 返回新引用，必须配对 JS_FreeValue——残留强引用会让
    // JS_FreeRuntime 的 gc_obj_list 断言崩（quickjs.c:2464，真机 SIGABRT 实锤）
    JSValue global = JS_GetGlobalObject(ctx);
    JSValue ctor = JS_GetPropertyStr(ctx, global, "Uint8Array");
    JS_FreeValue(ctx, global);
    if (JS_IsException(ctor)) {
        JS_FreeValue(ctx, ab);
        return JS_EXCEPTION;
    }
    JSValue argv[1] = { ab };
    JSValue out = JS_CallConstructor(ctx, ctor, 1, argv);
    JS_FreeValue(ctx, ctor);
    JS_FreeValue(ctx, ab);
    return out;
}

// name 参数取串（与 jsvm 侧 requireNameString 同句：非字符串 → 中文 TypeError）
static bool qjsRequireNameString(JSContext* ctx, JSValueConst v, const char* method,
    std::string& out)
{
    if (JS_IsString(v)) {
        out = qjsValueToUtf8(ctx, v);
        return true;
    }
    qjsThrowNamedError(ctx, "TypeError",
        std::string(method) + " 的第一个参数需要文件名（字符串），收到的是 " +
        qjsTypeNameOfValue(ctx, v) + "。");
    return false;
}

// ── 日志收集（与 jsvm 侧 pushLog 同口径：条数上限下传 + 字节预算超即止记截断标）──

static void qjsPushLog(QjsRunState* state, const std::string& line)
{
    if (state->logsMaxLines > 0 &&
        (state->logs.size() >= state->logsMaxLines || state->logsTruncated)) {
        if (!state->logsTruncated) {
            state->logsTruncated = true;
        }
        return;
    }
    std::string clipped = line;
    if (clipped.size() > state->logsBudget) {
        clipped = sandboxUtf8Truncate(clipped, state->logsBudget);
        state->logsTruncated = true;
    }
    if (clipped.empty() && state->logsTruncated) {
        return;
    }
    state->logsBudget -= std::min(state->logsBudget, clipped.size());
    state->logs.push_back(clipped);
}

// ── 宿主回调实现（同步语义——native 直接做，不经事件循环；与 jsvm 侧逐方法对照）──

static JSValue HostConsoleCommon(JSContext* ctx, int argc, JSValueConst* argv,
    const char* level)
{
    QjsRunState* state = QjsStateOf(ctx);
    std::string joined;
    for (int i = 0; i < argc; i++) {
        // ToCString 内部 ToString——带抛异常 toString 的对象回 NULL，清异常按跳参处理
        size_t len = 0;
        const char* s = JS_ToCStringLen(ctx, &len, argv[i]);
        if (s != nullptr) {
            if (i > 0) {
                joined += " ";
            }
            joined.append(s, len);
            JS_FreeCString(ctx, s);
        } else {
            qjsClearPendingException(ctx);
        }
    }
    if (state != nullptr) {
        qjsPushLog(state, joined);
    }
    OH_LOG_INFO(LOG_APP, "console.%{public}s: %{public}s", level, joined.c_str());
    return JS_UNDEFINED;
}

static JSValue HostConsoleLog(JSContext* ctx, JSValueConst this_val, int argc,
    JSValueConst* argv)
{
    (void)this_val;
    return HostConsoleCommon(ctx, argc, argv, "log");
}

static JSValue HostConsoleWarn(JSContext* ctx, JSValueConst this_val, int argc,
    JSValueConst* argv)
{
    (void)this_val;
    return HostConsoleCommon(ctx, argc, argv, "warn");
}

static JSValue HostConsoleError(JSContext* ctx, JSValueConst this_val, int argc,
    JSValueConst* argv)
{
    (void)this_val;
    return HostConsoleCommon(ctx, argc, argv, "error");
}

static JSValue HostResult(JSContext* ctx, JSValueConst this_val, int argc,
    JSValueConst* argv)
{
    (void)this_val;
    QjsRunState* state = QjsStateOf(ctx);
    if (state != nullptr && argc > 0) {
        state->resultValue = qjsSerializeJsValue(ctx, argv[0]);
        state->resultSet = true;
    }
    return JS_UNDEFINED;
}

static JSValue HostFsList(JSContext* ctx, JSValueConst this_val, int argc,
    JSValueConst* argv)
{
    (void)this_val;
    (void)argc;
    (void)argv;
    QjsRunState* state = QjsStateOf(ctx);
    if (state == nullptr) {
        return JS_UNDEFINED;
    }
    SandboxFsResult r = sandboxFsList(state->opts.workspaceRoot);
    if (!r.ok) {
        qjsThrowFenceError(ctx, r.reason);
        return JS_EXCEPTION;
    }
    return JS_NewStringLen(ctx, r.text.c_str(), r.text.size());
}

static JSValue HostFsRead(JSContext* ctx, JSValueConst this_val, int argc,
    JSValueConst* argv)
{
    (void)this_val;
    QjsRunState* state = QjsStateOf(ctx);
    if (state == nullptr || argc < 1) {
        qjsThrowFenceError(ctx, "临时区限制：fs.read 需要文件名参数");
        return JS_EXCEPTION;
    }
    std::string name;
    if (!qjsRequireNameString(ctx, argv[0], "fs.read", name)) {
        return JS_EXCEPTION;
    }
    SandboxFsResult r = sandboxFsRead(state->opts.workspaceRoot, name);
    if (!r.ok) {
        qjsThrowFenceError(ctx, r.reason);
        return JS_EXCEPTION;
    }
    return JS_NewStringLen(ctx, r.text.c_str(), r.text.size());
}

// fs.readBytes(name)：字节原样直出（复用 sandboxFsRead 原始字节面；文本解码语义在
// fs.read 的字符串路径——两引擎同源）
static JSValue HostFsReadBytes(JSContext* ctx, JSValueConst this_val, int argc,
    JSValueConst* argv)
{
    (void)this_val;
    QjsRunState* state = QjsStateOf(ctx);
    if (state == nullptr || argc < 1) {
        qjsThrowFenceError(ctx, "临时区限制：fs.readBytes 需要文件名参数");
        return JS_EXCEPTION;
    }
    std::string name;
    if (!qjsRequireNameString(ctx, argv[0], "fs.readBytes", name)) {
        return JS_EXCEPTION;
    }
    SandboxFsResult r = sandboxFsRead(state->opts.workspaceRoot, name);
    if (!r.ok) {
        qjsThrowFenceError(ctx, r.reason);
        return JS_EXCEPTION;
    }
    JSValue out = qjsBytesToUint8Array(ctx, r.text);
    if (JS_IsException(out)) {
        qjsClearPendingException(ctx); // 清创建挂起异常再报可读错误，不静默
        qjsThrowNamedError(ctx, "Error", "字节数组创建失败");
        return JS_EXCEPTION;
    }
    return out;
}

static JSValue HostFsWrite(JSContext* ctx, JSValueConst this_val, int argc,
    JSValueConst* argv)
{
    (void)this_val;
    QjsRunState* state = QjsStateOf(ctx);
    if (state == nullptr || argc < 2) {
        qjsThrowFenceError(ctx, "临时区限制：fs.write 需要文件名与内容两个参数");
        return JS_EXCEPTION;
    }
    std::string name;
    if (!qjsRequireNameString(ctx, argv[0], "fs.write", name)) {
        return JS_EXCEPTION;
    }
    std::string bytes;
    std::string errText;
    if (!qjsValueToBytes(ctx, argv[1], bytes, errText)) {
        qjsThrowNamedError(ctx, "TypeError", std::string("fs.write") + errText);
        return JS_EXCEPTION;
    }
    SandboxFsResult r = sandboxFsWrite(state->opts.workspaceRoot, name, bytes,
        state->opts.fsLimits);
    if (!r.ok) {
        qjsThrowFenceError(ctx, r.reason);
        return JS_EXCEPTION;
    }
    return JS_NewStringLen(ctx, r.text.c_str(), r.text.size());
}

static JSValue HostFsAppend(JSContext* ctx, JSValueConst this_val, int argc,
    JSValueConst* argv)
{
    (void)this_val;
    QjsRunState* state = QjsStateOf(ctx);
    if (state == nullptr || argc < 2) {
        qjsThrowFenceError(ctx, "临时区限制：fs.append 需要文件名与内容两个参数");
        return JS_EXCEPTION;
    }
    std::string name;
    if (!qjsRequireNameString(ctx, argv[0], "fs.append", name)) {
        return JS_EXCEPTION;
    }
    std::string bytes;
    std::string errText;
    if (!qjsValueToBytes(ctx, argv[1], bytes, errText)) {
        qjsThrowNamedError(ctx, "TypeError", std::string("fs.append") + errText);
        return JS_EXCEPTION;
    }
    SandboxFsResult r = sandboxFsAppend(state->opts.workspaceRoot, name, bytes,
        state->opts.fsLimits);
    if (!r.ok) {
        qjsThrowFenceError(ctx, r.reason);
        return JS_EXCEPTION;
    }
    return JS_NewStringLen(ctx, r.text.c_str(), r.text.size());
}

static JSValue HostFsExists(JSContext* ctx, JSValueConst this_val, int argc,
    JSValueConst* argv)
{
    (void)this_val;
    QjsRunState* state = QjsStateOf(ctx);
    if (state == nullptr || argc < 1) {
        qjsThrowFenceError(ctx, "临时区限制：fs.exists 需要文件名参数");
        return JS_EXCEPTION;
    }
    std::string name;
    if (!qjsRequireNameString(ctx, argv[0], "fs.exists", name)) {
        return JS_EXCEPTION;
    }
    SandboxFsResult r = sandboxFsExists(state->opts.workspaceRoot, name);
    if (!r.ok) {
        qjsThrowFenceError(ctx, r.reason);
        return JS_EXCEPTION;
    }
    return JS_NewBool(ctx, r.text == "true");
}

static JSValue HostFsSave(JSContext* ctx, JSValueConst this_val, int argc,
    JSValueConst* argv)
{
    (void)this_val;
    QjsRunState* state = QjsStateOf(ctx);
    if (state == nullptr || argc < 1) {
        qjsThrowFenceError(ctx, "临时区限制：fs.save 需要文件名参数");
        return JS_EXCEPTION;
    }
    std::string name;
    if (!qjsRequireNameString(ctx, argv[0], "fs.save", name)) {
        return JS_EXCEPTION;
    }
    SandboxFsResult r = sandboxFsSave(state->opts.workspaceRoot, name);
    if (!r.ok) {
        qjsThrowFenceError(ctx, r.reason);
        return JS_EXCEPTION;
    }
    // 在场核验过 → 登记待转正（落库编排在 ArkTS 侧）
    state->savedNames.push_back(name);
    return JS_NewBool(ctx, true);
}

// ── zlib 与摘要桥回调（共享编译副本 sandbox_codec.*；限额类 → FenceError、数据类 /
//    内部类 → ZlibError / DigestError——映射与 jsvm 侧同表）──

static JSValue HostZlibCommon(JSContext* ctx, int argc, JSValueConst* argv, bool compress,
    const char* funcName)
{
    QjsRunState* state = QjsStateOf(ctx);
    if (state == nullptr || argc < 1) {
        qjsThrowNamedError(ctx, "TypeError",
            std::string(funcName) + " 需要一个数据参数（字符串或 Uint8Array 等字节数组）。");
        return JS_EXCEPTION;
    }
    std::string bytes;
    std::string errText;
    if (!qjsValueToBytes(ctx, argv[0], bytes, errText)) {
        qjsThrowNamedError(ctx, "TypeError", std::string(funcName) + errText);
        return JS_EXCEPTION;
    }
    SandboxCodecResult r = compress ?
        sandboxZlibCompress(bytes, state->opts.fsLimits.maxFileBytes, funcName) :
        sandboxZlibDecompress(bytes, state->opts.fsLimits.maxFileBytes,
            state->opts.fsLimits.maxFileBytes, funcName);
    if (!r.ok) {
        if (r.errorKind == SANDBOX_CODEC_ERR_LIMIT) {
            qjsThrowFenceError(ctx, r.reason);
        } else {
            qjsThrowNamedError(ctx, "ZlibError", r.reason);
        }
        return JS_EXCEPTION;
    }
    JSValue out = qjsBytesToUint8Array(ctx, r.data);
    if (JS_IsException(out)) {
        qjsClearPendingException(ctx);
        qjsThrowNamedError(ctx, "ZlibError", std::string(funcName) + " 失败：内部错误");
        return JS_EXCEPTION;
    }
    return out;
}

static JSValue HostZlibCompress(JSContext* ctx, JSValueConst this_val, int argc,
    JSValueConst* argv)
{
    (void)this_val;
    return HostZlibCommon(ctx, argc, argv, true, "zlibCompress");
}

static JSValue HostZlibDecompress(JSContext* ctx, JSValueConst this_val, int argc,
    JSValueConst* argv)
{
    (void)this_val;
    return HostZlibCommon(ctx, argc, argv, false, "zlibDecompress");
}

static JSValue HostDigestCommon(JSContext* ctx, int argc, JSValueConst* argv,
    const char* algoName)
{
    QjsRunState* state = QjsStateOf(ctx);
    if (state == nullptr || argc < 1) {
        qjsThrowNamedError(ctx, "TypeError",
            std::string(algoName) + " 需要一个数据参数（字符串或 Uint8Array 等字节数组）。");
        return JS_EXCEPTION;
    }
    std::string bytes;
    std::string errText;
    if (!qjsValueToBytes(ctx, argv[0], bytes, errText)) {
        qjsThrowNamedError(ctx, "TypeError", std::string(algoName) + errText);
        return JS_EXCEPTION;
    }
    SandboxCodecResult r = sandboxDigestHex(algoName, bytes,
        state->opts.fsLimits.maxFileBytes);
    if (!r.ok) {
        if (r.errorKind == SANDBOX_CODEC_ERR_LIMIT) {
            qjsThrowFenceError(ctx, r.reason);
        } else {
            qjsThrowNamedError(ctx, "DigestError", r.reason);
        }
        return JS_EXCEPTION;
    }
    return JS_NewStringLen(ctx, r.data.c_str(), r.data.size());
}

static JSValue HostMd5(JSContext* ctx, JSValueConst this_val, int argc, JSValueConst* argv)
{
    (void)this_val;
    return HostDigestCommon(ctx, argc, argv, "md5");
}

static JSValue HostSha1(JSContext* ctx, JSValueConst this_val, int argc, JSValueConst* argv)
{
    (void)this_val;
    return HostDigestCommon(ctx, argc, argv, "sha1");
}

static JSValue HostSha256(JSContext* ctx, JSValueConst this_val, int argc,
    JSValueConst* argv)
{
    (void)this_val;
    return HostDigestCommon(ctx, argc, argv, "sha256");
}

// httpGet(url, opts?)——沙箱网络唯一入口（笔E 面、笔F 等价副本；语义校验单源在 ArkTS
// 桥件——opts 原样 JSON 透传，native 不做第二套）：同步语义——经 qjs_http.* 投递
// ArkTS 主线程走既有 HTTP 链并阻塞等待（有界 + 取消唤醒）。返回：文本 → string；
// 二进制 → Uint8Array（空响应体 = 长度 0）；失败抛 name=HttpError
static JSValue HostHttpGet(JSContext* ctx, JSValueConst this_val, int argc,
    JSValueConst* argv)
{
    (void)this_val;
    QjsRunState* state = QjsStateOf(ctx);
    if (state == nullptr || argc < 1) {
        qjsThrowNamedError(ctx, "TypeError", "httpGet 的第一个参数需要网址字符串。");
        return JS_EXCEPTION;
    }
    if (!JS_IsString(argv[0])) {
        qjsThrowNamedError(ctx, "TypeError",
            std::string("httpGet 的第一个参数需要网址字符串，收到的是 ") +
            qjsTypeNameOfValue(ctx, argv[0]) + "。");
        return JS_EXCEPTION;
    }
    const std::string url = qjsValueToUtf8(ctx, argv[0]);
    // opts 形态收口（与 jsvm 侧同句）：undefined / null = 无可选项（"{}"）；对象（非
    // 数组）→ JSON 序列化透传；其余形态就地 TypeError
    std::string optsJson = "{}";
    if (argc >= 2 && !JS_IsUndefined(argv[1]) && !JS_IsNull(argv[1])) {
        const bool isArray = JS_IsArray(ctx, argv[1]);
        if (!JS_IsObject(argv[1]) || isArray) {
            qjsThrowNamedError(ctx, "TypeError",
                std::string("httpGet 的第二个参数需要是对象，收到的是 ") +
                (isArray ? "array" : qjsTypeNameOfValue(ctx, argv[1])) + "。");
            return JS_EXCEPTION;
        }
        JSValue json = JS_JSONStringify(ctx, argv[1], JS_UNDEFINED, JS_UNDEFINED);
        if (JS_IsException(json)) {
            qjsClearPendingException(ctx); // 循环引用等序列化异常——清掉按 "{}" 透传
        } else {
            if (JS_IsString(json)) {
                optsJson = qjsValueToUtf8(ctx, json);
            }
            JS_FreeValue(ctx, json);
        }
    }
    // 受理前取消检查（唯一一层判据，照 jsvm 侧同位同句）：置位后的调用当场报错、不投递
    //（★ 2026-10-20 并发笔：定向化删粘性全局标记后此拦截为新请求闭合法——cancel 置位与
    // interrupt 生效之间进入的请求不再等满 httpWaitMs，改读本 run 取消块，他路取消不拦本路）
    if (state->cancelBlock != nullptr && state->cancelBlock->requested.load()) {
        qjsThrowNamedError(ctx, "HttpError", "本次运行已取消，不再发起新的网络请求。");
        return JS_EXCEPTION;
    }
    QjsHttpOutcome r = QjsHttpRequest(url, optsJson, state->opts.httpWaitMs, state->runKey);
    if (!r.ok) {
        qjsThrowNamedError(ctx, "HttpError", r.errorText);
        return JS_EXCEPTION;
    }
    if (r.kind == "bytes") {
        JSValue out = qjsBytesToUint8Array(ctx, r.bytes);
        if (JS_IsException(out)) {
            qjsClearPendingException(ctx);
            qjsThrowNamedError(ctx, "HttpError", "httpGet 失败：字节数组创建失败。");
            return JS_EXCEPTION;
        }
        return out;
    }
    return JS_NewStringLen(ctx, r.text.c_str(), r.text.size());
}

// ── 宿主面安装（注入名集合与 jsvm 侧 InstallSandboxHostApi 全等——断言关系钉守）──

void QjsInstallHostApi(JSContext* ctx)
{
    JSValue global = JS_GetGlobalObject(ctx);

    // console 对象（三成员）
    JSValue consoleObj = JS_NewObject(ctx);
    struct { const char* name; JSCFunction* fn; } consoleMembers[] = {
        { "log", HostConsoleLog },
        { "warn", HostConsoleWarn },
        { "error", HostConsoleError }
    };
    for (auto& member : consoleMembers) {
        JS_SetPropertyStr(ctx, consoleObj, member.name,
            JS_NewCFunction(ctx, member.fn, member.name, 8));
    }
    JS_SetPropertyStr(ctx, global, "console", consoleObj);

    // result(v)
    JS_SetPropertyStr(ctx, global, "result", JS_NewCFunction(ctx, HostResult, "result", 1));

    // fs 对象（七方法：list / read / readBytes / write / append / exists / save——len 位
    // = 形参数量，与 jsvm 侧 CreateFunction 的名长实参语义无关紧要、取真实形参数）
    JSValue fsObj = JS_NewObject(ctx);
    struct { const char* name; JSCFunction* fn; int len; } fsMembers[] = {
        { "list", HostFsList, 0 },
        { "read", HostFsRead, 1 },
        { "readBytes", HostFsReadBytes, 1 },
        { "write", HostFsWrite, 2 },
        { "append", HostFsAppend, 2 },
        { "exists", HostFsExists, 1 },
        { "save", HostFsSave, 1 }
    };
    for (auto& member : fsMembers) {
        JS_SetPropertyStr(ctx, fsObj, member.name,
            JS_NewCFunction(ctx, member.fn, member.name, member.len));
    }
    JS_SetPropertyStr(ctx, global, "fs", fsObj);

    // 六全局桥函数（五 codec 桥 + 网络桥 httpGet——与 jsvm 侧 bridgeMembers 同集合）
    struct { const char* name; JSCFunction* fn; } bridgeMembers[] = {
        { "zlibCompress", HostZlibCompress },
        { "zlibDecompress", HostZlibDecompress },
        { "md5", HostMd5 },
        { "sha1", HostSha1 },
        { "sha256", HostSha256 },
        { "httpGet", HostHttpGet }
    };
    for (auto& member : bridgeMembers) {
        JS_SetPropertyStr(ctx, global, member.name,
            JS_NewCFunction(ctx, member.fn, member.name, 1));
    }
    JS_FreeValue(ctx, global);

    // 不注入面（与 jsvm 侧同款声明）：fetch / XMLHttpRequest / require / setTimeout /
    // import（引擎无模块语义）；WebAssembly 天然无（差异申报——不记 wasm-removed）
}
