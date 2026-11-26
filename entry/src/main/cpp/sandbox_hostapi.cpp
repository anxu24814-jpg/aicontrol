// 沙箱宿主 API 回调层实现（头注释见 sandbox_hostapi.h；2026-10-06 代码工作台笔A——
// 二进制与基座：自 jsvm_runner.cpp 域级最小拆出〔方法体逐字原样〕+ 本笔新增面〔认形 /
// readBytes / append / zlib 与摘要桥 / Promise 捕获〕）。
// · 官方范式 =《使用 JSVM-API 实现 JS 与 C/C++ 语言交互开发流程》+《JSVM-API 使用规范》
//   ——全部签名以本机 SDK jsvm.h 实读为准。
// · 沙箱两条不软化（A9/A16）：不承诺中断任意脚本；网络能力自笔E 起经 httpGet 单通道
//   （宿主函数，默认 GET、写方法需全局开关开启、预授权域名——治理单源在 ArkTS 桥件 ScriptHttpBridge），fetch /
//   XMLHttpRequest 仍恒不注入（负向钉判据不变）。
#include "sandbox_hostapi.h"

#include <algorithm>
#include <cstring>

#include "hilog/log.h"
#include "sandbox_codec.h"
#include "sandbox_fs.h"
#include "sandbox_http.h"

// ── 取串 / 序列化小件（valueToUtf8 / serializeJsValue 跨 TU 导出——jsvm_runner.cpp
//    留存面消费，其余 static 本件私有）──

// JSVM_Value(string) → std::string（两段式取长；NUL 终止由 API 写在 buf 尾，std::string
// 预留一位容它再 resize 回真实长度）
std::string valueToUtf8(JSVM_Env env, JSVM_Value v)
{
    size_t len = 0;
    if (OH_JSVM_GetValueStringUtf8(env, v, nullptr, 0, &len) != JSVM_OK || len == 0) {
        return "";
    }
    std::string buf(len + 1, '\0');
    size_t written = 0;
    if (OH_JSVM_GetValueStringUtf8(env, v, &buf[0], buf.size(), &written) != JSVM_OK) {
        return "";
    }
    buf.resize(written);
    return buf;
}

// console 单条截断（512 字符口径）于 2026-10-06 溢出修复笔移除：收集面改存原行——溢出
// 落盘契约要求文件承载完整产出，单行截断会让「大 JSON 一行」类输出在收集端就被削；
// 回执面单行截断由装配层 clipLines（2000/行 + 尾标）承担，预算收口不变

// 值序列化（§3.2-5）：string 原样；undefined / null 特值；其余 JSON.stringify（失败清异常
// 降级 CoerceToString）
std::string serializeJsValue(JSVM_Env env, JSVM_Value v)
{
    JSVM_ValueType type = JSVM_UNDEFINED;
    if (OH_JSVM_Typeof(env, v, &type) != JSVM_OK) {
        return "";
    }
    if (type == JSVM_STRING) {
        return valueToUtf8(env, v);
    }
    if (type == JSVM_UNDEFINED) {
        return "undefined";
    }
    if (type == JSVM_NULL) {
        return "null";
    }
    JSVM_Value json = nullptr;
    JSVM_Status st = OH_JSVM_JsonStringify(env, v, &json);
    if (st == JSVM_OK && json != nullptr) {
        JSVM_ValueType jsonType = JSVM_UNDEFINED;
        OH_JSVM_Typeof(env, json, &jsonType);
        if (jsonType == JSVM_STRING) {
            return valueToUtf8(env, json);
        }
    } else if (st == JSVM_PENDING_EXCEPTION) {
        // 循环引用等 stringify 异常——清掉再走降级（不清会污染后续调用）
        JSVM_Value exc = nullptr;
        OH_JSVM_GetAndClearLastException(env, &exc);
    }
    JSVM_Value coerced = nullptr;
    if (OH_JSVM_CoerceToString(env, v, &coerced) == JSVM_OK && coerced != nullptr) {
        return valueToUtf8(env, coerced);
    }
    // 降级路径的异常清理（同 HostConsoleCommon——CoerceToString 挂起的异常不清会污染调用方
    // 的后续 JSVM 调用；★ 2026-10-06 自检轮修复）
    JSVM_Value stale = nullptr;
    OH_JSVM_GetAndClearLastException(env, &stale);
    return "";
}

// fs 闸拒绝 → JS 异常（name=FenceError + 中文 message；ScriptReceipt 判据主位）
static void throwFenceError(JSVM_Env env, const std::string& reason)
{
    JSVM_Value msg = nullptr;
    OH_JSVM_CreateStringUtf8(env, reason.c_str(), reason.size(), &msg);
    JSVM_Value err = nullptr;
    OH_JSVM_CreateError(env, nullptr, msg, &err);
    if (err != nullptr) {
        JSVM_Value nameVal = nullptr;
        OH_JSVM_CreateStringUtf8(env, "FenceError", 10, &nameVal);
        OH_JSVM_SetNamedProperty(env, err, "name", nameVal);
        OH_JSVM_Throw(env, err);
    }
}

// 指定错误名的 JS 异常（TypeError / ZlibError / DigestError 共用形制——与 throwFenceError
// 同构、后者为既有稳定面保持原样不动）
static void throwNamedError(JSVM_Env env, const char* name, const std::string& message)
{
    JSVM_Value msg = nullptr;
    OH_JSVM_CreateStringUtf8(env, message.c_str(), message.size(), &msg);
    JSVM_Value err = nullptr;
    OH_JSVM_CreateError(env, nullptr, msg, &err);
    if (err != nullptr) {
        JSVM_Value nameVal = nullptr;
        OH_JSVM_CreateStringUtf8(env, name, std::strlen(name), &nameVal);
        OH_JSVM_SetNamedProperty(env, err, "name", nameVal);
        OH_JSVM_Throw(env, err);
    }
}

static JSVM_Value undefinedValue(JSVM_Env env)
{
    JSVM_Value undefined = nullptr;
    OH_JSVM_GetUndefined(env, &undefined);
    return undefined;
}

// ── 认形与字节互转小件（§3.1 / §3.2；fs 两写与五桥统一）──

// 类型名（OH_JSVM_Typeof 结果 → 模型可读名，错误句自述用）
static const char* typeNameOfValue(JSVM_Env env, JSVM_Value v)
{
    JSVM_ValueType t = JSVM_UNDEFINED;
    if (OH_JSVM_Typeof(env, v, &t) != JSVM_OK) {
        return "unknown";
    }
    switch (t) {
        case JSVM_NUMBER: return "number";
        case JSVM_STRING: return "string";
        case JSVM_BOOLEAN: return "boolean";
        case JSVM_UNDEFINED: return "undefined";
        case JSVM_NULL: return "null";
        case JSVM_FUNCTION: return "function";
        case JSVM_SYMBOL: return "symbol";
        case JSVM_BIGINT: return "bigint";
        default: return "object";
    }
}

// 数据参数认形（§4.3 统一）：string → UTF-8；TypedArray → 底层字节（GetTypedarrayInfo 的
// data 已按 byteOffset 调整、字节数 = length × 元素尺寸）；其余（含 ArrayBuffer / DataView）
// → false + 中文 errText（调用方拼函数名前缀后抛 TypeError——给 new Uint8Array(buf) 指引）
static bool sandboxValueToBytes(JSVM_Env env, JSVM_Value v, std::string& out, std::string& errText)
{
    JSVM_ValueType type = JSVM_UNDEFINED;
    if (OH_JSVM_Typeof(env, v, &type) == JSVM_OK && type == JSVM_STRING) {
        out = valueToUtf8(env, v);
        return true;
    }
    bool isTypedarray = false;
    if (OH_JSVM_IsTypedarray(env, v, &isTypedarray) == JSVM_OK && isTypedarray) {
        JSVM_TypedarrayType taType = JSVM_UINT8_ARRAY;
        size_t length = 0;
        void* data = nullptr;
        if (OH_JSVM_GetTypedarrayInfo(env, v, &taType, &length, &data, nullptr, nullptr) ==
            JSVM_OK) {
            size_t elemSize = 0;
            switch (taType) {
                case JSVM_INT8_ARRAY:
                case JSVM_UINT8_ARRAY:
                case JSVM_UINT8_CLAMPED_ARRAY:
                    elemSize = 1;
                    break;
                case JSVM_INT16_ARRAY:
                case JSVM_UINT16_ARRAY:
                    elemSize = 2;
                    break;
                case JSVM_INT32_ARRAY:
                case JSVM_UINT32_ARRAY:
                case JSVM_FLOAT32_ARRAY:
                    elemSize = 4;
                    break;
                case JSVM_FLOAT64_ARRAY:
                case JSVM_BIGINT64_ARRAY:
                case JSVM_BIGUINT64_ARRAY:
                    elemSize = 8;
                    break;
                default: // 理论不可达（枚举全覆盖）——按认形失败如实报
                    errText = std::string(" 的内容只支持字符串或 TypedArray，例如 Uint8Array，") +
                        "当前收到的是 " + typeNameOfValue(env, v) + "。";
                    return false;
            }
            const size_t byteCount = length * elemSize;
            if (byteCount > 0 && data != nullptr) {
                out.assign(static_cast<const char*>(data), byteCount);
            } else {
                out.clear();
            }
            return true;
        }
    }
    errText = std::string(" 的内容只支持字符串或 TypedArray，例如 Uint8Array，当前收到的是 ") +
        typeNameOfValue(env, v) + "。二进制内容可以先用 new TextEncoder().encode(文本) 转成 " +
        "Uint8Array，或从 fs.readBytes 读取。";
    return false;
}

// 字节 → Uint8Array（CreateArraybuffer + memcpy + CreateTypedarray 三步；长度 0 跳过
// memcpy——data 可能为 NULL）
static JSVM_Value sandboxBytesToUint8Array(JSVM_Env env, const std::string& bytes)
{
    void* dataPtr = nullptr;
    JSVM_Value arraybuffer = nullptr;
    const size_t len = bytes.size();
    if (OH_JSVM_CreateArraybuffer(env, len, &dataPtr, &arraybuffer) != JSVM_OK ||
        arraybuffer == nullptr) {
        return nullptr;
    }
    if (len > 0 && dataPtr != nullptr) {
        std::memcpy(dataPtr, bytes.data(), len);
    }
    JSVM_Value result = nullptr;
    if (OH_JSVM_CreateTypedarray(env, JSVM_UINT8_ARRAY, len, arraybuffer, 0, &result) !=
        JSVM_OK) {
        return nullptr;
    }
    return result;
}

// name 参数取串（六方法统一，§1.5-2：非字符串 → 中文 TypeError——消灭「静默转空串后报
// 文件名不能为空」的归因含糊；空串 / 纯空白仍走名称闸不变）
static bool requireNameString(JSVM_Env env, JSVM_Value v, const char* method, std::string& out)
{
    JSVM_ValueType type = JSVM_UNDEFINED;
    if (OH_JSVM_Typeof(env, v, &type) == JSVM_OK && type == JSVM_STRING) {
        out = valueToUtf8(env, v);
        return true;
    }
    throwNamedError(env, "TypeError", std::string(method) + " 的第一个参数需要文件名（字符串），" +
        "收到的是 " + typeNameOfValue(env, v) + "。");
    return false;
}

// ── 宿主回调实现（§3.3-1 沙箱 API 面；同步语义——native 直接做，不经事件循环）──

static RunState* stateOf(void* data)
{
    return static_cast<RunState*>(data);
}

static void pushLog(RunState* state, const std::string& line)
{
    // 条数上限（下传 maxLogLines，0 = 不限）+ 总量预算（超即止并记截断标——§3.2-9；
    // ★ 2026-10-06 溢出修复笔：收集预算扩至落盘单件闸、条数防线同步下传、单行不再
    // 预截——原硬字面量 200 与 512 字单行截断都会在长输出场景先于字节预算截断，
    // 破坏「完整输出落盘」契约）
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

static JSVM_Value HostConsoleCommon(JSVM_Env env, JSVM_CallbackInfo info, const char* level)
{
    void* data = nullptr;
    size_t argc = 8;
    JSVM_Value args[8] = { nullptr };
    OH_JSVM_GetCbInfo(env, info, &argc, args, nullptr, &data);
    RunState* state = stateOf(data);
    std::string joined;
    for (size_t i = 0; i < argc; i++) {
        JSVM_Value str = nullptr;
        if (OH_JSVM_CoerceToString(env, args[i], &str) == JSVM_OK && str != nullptr) {
            if (i > 0) {
                joined += " ";
            }
            joined += valueToUtf8(env, str);
        } else {
            // CoerceToString 对带抛异常 toString 的对象会挂起 JS 异常——不清会污染本次
            // 后续全部 JSVM 调用（RunScript 直接失败归因错位）；清掉按「该参数跳过」处理
            //（★ 2026-10-06 自检轮修复）
            JSVM_Value stale = nullptr;
            OH_JSVM_GetAndClearLastException(env, &stale);
        }
    }
    pushLog(state, joined);
    OH_LOG_INFO(LOG_APP, "console.%{public}s: %{public}s", level, joined.c_str());
    return undefinedValue(env);
}

static JSVM_Value HostConsoleLog(JSVM_Env env, JSVM_CallbackInfo info)
{
    return HostConsoleCommon(env, info, "log");
}

static JSVM_Value HostConsoleWarn(JSVM_Env env, JSVM_CallbackInfo info)
{
    return HostConsoleCommon(env, info, "warn");
}

static JSVM_Value HostConsoleError(JSVM_Env env, JSVM_CallbackInfo info)
{
    return HostConsoleCommon(env, info, "error");
}

static JSVM_Value HostResult(JSVM_Env env, JSVM_CallbackInfo info)
{
    void* data = nullptr;
    size_t argc = 1;
    JSVM_Value args[1] = { nullptr };
    OH_JSVM_GetCbInfo(env, info, &argc, args, nullptr, &data);
    RunState* state = stateOf(data);
    if (argc > 0) {
        state->resultValue = serializeJsValue(env, args[0]);
        state->resultSet = true;
    }
    return undefinedValue(env);
}

static JSVM_Value HostFsList(JSVM_Env env, JSVM_CallbackInfo info)
{
    void* data = nullptr;
    size_t argc = 0;
    OH_JSVM_GetCbInfo(env, info, &argc, nullptr, nullptr, &data);
    RunState* state = stateOf(data);
    SandboxFsResult r = sandboxFsList(state->opts.workspaceRoot);
    if (!r.ok) {
        throwFenceError(env, r.reason);
        return nullptr;
    }
    JSVM_Value out = nullptr;
    OH_JSVM_CreateStringUtf8(env, r.text.c_str(), r.text.size(), &out);
    return out;
}

static JSVM_Value HostFsRead(JSVM_Env env, JSVM_CallbackInfo info)
{
    void* data = nullptr;
    size_t argc = 1;
    JSVM_Value args[1] = { nullptr };
    OH_JSVM_GetCbInfo(env, info, &argc, args, nullptr, &data);
    RunState* state = stateOf(data);
    if (argc < 1) {
        throwFenceError(env, "临时区限制：fs.read 需要文件名参数");
        return nullptr;
    }
    std::string name;
    if (!requireNameString(env, args[0], "fs.read", name)) {
        return nullptr;
    }
    SandboxFsResult r = sandboxFsRead(state->opts.workspaceRoot, name);
    if (!r.ok) {
        throwFenceError(env, r.reason);
        return nullptr;
    }
    JSVM_Value out = nullptr;
    OH_JSVM_CreateStringUtf8(env, r.text.c_str(), r.text.size(), &out);
    return out;
}

// fs.readBytes(name)：字节原样直出（复用 sandboxFsRead 的原始字节面；与 fs.read 同源
// 同址，差异只在输出形态——§4.6-1）
static JSVM_Value HostFsReadBytes(JSVM_Env env, JSVM_CallbackInfo info)
{
    void* data = nullptr;
    size_t argc = 1;
    JSVM_Value args[1] = { nullptr };
    OH_JSVM_GetCbInfo(env, info, &argc, args, nullptr, &data);
    RunState* state = stateOf(data);
    if (argc < 1) {
        throwFenceError(env, "临时区限制：fs.readBytes 需要文件名参数");
        return nullptr;
    }
    std::string name;
    if (!requireNameString(env, args[0], "fs.readBytes", name)) {
        return nullptr;
    }
    SandboxFsResult r = sandboxFsRead(state->opts.workspaceRoot, name);
    if (!r.ok) {
        throwFenceError(env, r.reason);
        return nullptr;
    }
    JSVM_Value out = sandboxBytesToUint8Array(env, r.text);
    if (out == nullptr) {
        // 极端失败（创建字节容器）——清挂起异常再抛可读错误，不静默
        JSVM_Value stale = nullptr;
        OH_JSVM_GetAndClearLastException(env, &stale);
        const char* failText = "字节数组创建失败";
        JSVM_Value msg = nullptr;
        OH_JSVM_CreateStringUtf8(env, failText, std::strlen(failText), &msg);
        JSVM_Value err = nullptr;
        OH_JSVM_CreateError(env, nullptr, msg, &err);
        if (err != nullptr) {
            OH_JSVM_Throw(env, err);
        }
    }
    return out;
}

static JSVM_Value HostFsWrite(JSVM_Env env, JSVM_CallbackInfo info)
{
    void* data = nullptr;
    size_t argc = 2;
    JSVM_Value args[2] = { nullptr };
    OH_JSVM_GetCbInfo(env, info, &argc, args, nullptr, &data);
    RunState* state = stateOf(data);
    if (argc < 2) {
        throwFenceError(env, "临时区限制：fs.write 需要文件名与内容两个参数");
        return nullptr;
    }
    std::string name;
    if (!requireNameString(env, args[0], "fs.write", name)) {
        return nullptr;
    }
    // 认形（§3.1：string 照旧 UTF-8、TypedArray 取字节直写、其余中文 TypeError——消灭
    // 非字符串内容静默写 0 字节的 P0 缺陷；空内容仍为合法 0 字节写入）
    std::string bytes;
    std::string errText;
    if (!sandboxValueToBytes(env, args[1], bytes, errText)) {
        throwNamedError(env, "TypeError", std::string("fs.write") + errText);
        return nullptr;
    }
    SandboxFsResult r = sandboxFsWrite(state->opts.workspaceRoot, name, bytes, state->opts.fsLimits);
    if (!r.ok) {
        throwFenceError(env, r.reason);
        return nullptr;
    }
    JSVM_Value out = nullptr;
    OH_JSVM_CreateStringUtf8(env, r.text.c_str(), r.text.size(), &out);
    return out;
}

// fs.append(name, data)：追加写（不存在即创建；两闸按追加后大小，§3.3）
static JSVM_Value HostFsAppend(JSVM_Env env, JSVM_CallbackInfo info)
{
    void* data = nullptr;
    size_t argc = 2;
    JSVM_Value args[2] = { nullptr };
    OH_JSVM_GetCbInfo(env, info, &argc, args, nullptr, &data);
    RunState* state = stateOf(data);
    if (argc < 2) {
        throwFenceError(env, "临时区限制：fs.append 需要文件名与内容两个参数");
        return nullptr;
    }
    std::string name;
    if (!requireNameString(env, args[0], "fs.append", name)) {
        return nullptr;
    }
    std::string bytes;
    std::string errText;
    if (!sandboxValueToBytes(env, args[1], bytes, errText)) {
        throwNamedError(env, "TypeError", std::string("fs.append") + errText);
        return nullptr;
    }
    SandboxFsResult r = sandboxFsAppend(state->opts.workspaceRoot, name, bytes, state->opts.fsLimits);
    if (!r.ok) {
        throwFenceError(env, r.reason);
        return nullptr;
    }
    JSVM_Value out = nullptr;
    OH_JSVM_CreateStringUtf8(env, r.text.c_str(), r.text.size(), &out);
    return out;
}

static JSVM_Value HostFsExists(JSVM_Env env, JSVM_CallbackInfo info)
{
    void* data = nullptr;
    size_t argc = 1;
    JSVM_Value args[1] = { nullptr };
    OH_JSVM_GetCbInfo(env, info, &argc, args, nullptr, &data);
    RunState* state = stateOf(data);
    if (argc < 1) {
        throwFenceError(env, "临时区限制：fs.exists 需要文件名参数");
        return nullptr;
    }
    std::string name;
    if (!requireNameString(env, args[0], "fs.exists", name)) {
        return nullptr;
    }
    SandboxFsResult r = sandboxFsExists(state->opts.workspaceRoot, name);
    if (!r.ok) {
        throwFenceError(env, r.reason);
        return nullptr;
    }
    JSVM_Value out = nullptr;
    OH_JSVM_GetBoolean(env, r.text == "true", &out);
    return out;
}

static JSVM_Value HostFsSave(JSVM_Env env, JSVM_CallbackInfo info)
{
    void* data = nullptr;
    size_t argc = 1;
    JSVM_Value args[1] = { nullptr };
    OH_JSVM_GetCbInfo(env, info, &argc, args, nullptr, &data);
    RunState* state = stateOf(data);
    if (argc < 1) {
        throwFenceError(env, "临时区限制：fs.save 需要文件名参数");
        return nullptr;
    }
    std::string name;
    if (!requireNameString(env, args[0], "fs.save", name)) {
        return nullptr;
    }
    SandboxFsResult r = sandboxFsSave(state->opts.workspaceRoot, name);
    if (!r.ok) {
        throwFenceError(env, r.reason);
        return nullptr;
    }
    // 在场核验过 → 登记待转正（落库编排在 ArkTS 侧，§3.4-7）
    state->savedNames.push_back(name);
    JSVM_Value out = nullptr;
    OH_JSVM_GetBoolean(env, true, &out);
    return out;
}

// ── zlib 与摘要桥回调（§3.5 / §3.6；认形与闸同 §4.3/§4.5 统一——桥输入与解压输出
//    上限 = 下传单件闸，codec 侧零限额字面值）──

static JSVM_Value HostZlibCommon(JSVM_Env env, JSVM_CallbackInfo info, bool compress,
    const char* funcName)
{
    void* data = nullptr;
    size_t argc = 1;
    JSVM_Value args[1] = { nullptr };
    OH_JSVM_GetCbInfo(env, info, &argc, args, nullptr, &data);
    RunState* state = stateOf(data);
    if (argc < 1) {
        throwNamedError(env, "TypeError",
            std::string(funcName) + " 需要一个数据参数（字符串或 Uint8Array 等字节数组）。");
        return nullptr;
    }
    std::string bytes;
    std::string errText;
    if (!sandboxValueToBytes(env, args[0], bytes, errText)) {
        throwNamedError(env, "TypeError", std::string(funcName) + errText);
        return nullptr;
    }
    SandboxCodecResult r = compress ?
        sandboxZlibCompress(bytes, state->opts.fsLimits.maxFileBytes, funcName) :
        sandboxZlibDecompress(bytes, state->opts.fsLimits.maxFileBytes,
            state->opts.fsLimits.maxFileBytes, funcName);
    if (!r.ok) {
        if (r.errorKind == SANDBOX_CODEC_ERR_LIMIT) {
            throwFenceError(env, r.reason);
        } else {
            throwNamedError(env, "ZlibError", r.reason);
        }
        return nullptr;
    }
    JSVM_Value out = sandboxBytesToUint8Array(env, r.data);
    if (out == nullptr) {
        JSVM_Value stale = nullptr;
        OH_JSVM_GetAndClearLastException(env, &stale);
        throwNamedError(env, "ZlibError", std::string(funcName) + " 失败：内部错误");
    }
    return out;
}

static JSVM_Value HostZlibCompress(JSVM_Env env, JSVM_CallbackInfo info)
{
    return HostZlibCommon(env, info, true, "zlibCompress");
}

static JSVM_Value HostZlibDecompress(JSVM_Env env, JSVM_CallbackInfo info)
{
    return HostZlibCommon(env, info, false, "zlibDecompress");
}

// algoName = 宿主函数名小写 md5/sha1/sha256——官方大写算法名由 sandbox_codec.cpp 的
// digestOfficialName 映射，闸错误句直接用小写调用名自述
static JSVM_Value HostDigestCommon(JSVM_Env env, JSVM_CallbackInfo info, const char* algoName)
{
    void* data = nullptr;
    size_t argc = 1;
    JSVM_Value args[1] = { nullptr };
    OH_JSVM_GetCbInfo(env, info, &argc, args, nullptr, &data);
    RunState* state = stateOf(data);
    if (argc < 1) {
        throwNamedError(env, "TypeError",
            std::string(algoName) + " 需要一个数据参数（字符串或 Uint8Array 等字节数组）。");
        return nullptr;
    }
    std::string bytes;
    std::string errText;
    if (!sandboxValueToBytes(env, args[0], bytes, errText)) {
        throwNamedError(env, "TypeError", std::string(algoName) + errText);
        return nullptr;
    }
    SandboxCodecResult r = sandboxDigestHex(algoName, bytes, state->opts.fsLimits.maxFileBytes);
    if (!r.ok) {
        if (r.errorKind == SANDBOX_CODEC_ERR_LIMIT) {
            throwFenceError(env, r.reason);
        } else {
            throwNamedError(env, "DigestError", r.reason);
        }
        return nullptr;
    }
    JSVM_Value out = nullptr;
    OH_JSVM_CreateStringUtf8(env, r.data.c_str(), r.data.size(), &out);
    return out;
}

static JSVM_Value HostMd5(JSVM_Env env, JSVM_CallbackInfo info)
{
    return HostDigestCommon(env, info, "md5");
}

static JSVM_Value HostSha1(JSVM_Env env, JSVM_CallbackInfo info)
{
    return HostDigestCommon(env, info, "sha1");
}

static JSVM_Value HostSha256(JSVM_Env env, JSVM_CallbackInfo info)
{
    return HostDigestCommon(env, info, "sha256");
}

// httpGet(url, opts?)（★ 2026-10-06 代码工作台笔E——沙箱网络唯一入口，任务书 §3.1-6）：
// 同步语义——经 sandbox_http.* 投递 ArkTS 主线程走既有 HTTP 链并阻塞等待（有界）。
// 本层只做认形与受理前取消检查（单层判据，任务书 §9-7）；语义校验（键白名单 / 值类型 /
// 域名闸 / 超时钳制）单源在 ArkTS 桥件——opts 原样 JSON 透传，native 不做第二套。
// 返回：文本响应 → string（CreateStringUtf8 替换语义，与 fs.read 同源）；二进制 →
// Uint8Array（sandboxBytesToUint8Array，空响应体 = 长度 0）；失败抛 name=HttpError
static JSVM_Value HostHttpGet(JSVM_Env env, JSVM_CallbackInfo info)
{
    void* data = nullptr;
    size_t argc = 2;
    JSVM_Value args[2] = { nullptr };
    OH_JSVM_GetCbInfo(env, info, &argc, args, nullptr, &data);
    RunState* state = stateOf(data);
    if (argc < 1) {
        throwNamedError(env, "TypeError", "httpGet 的第一个参数需要网址字符串。");
        return nullptr;
    }
    JSVM_ValueType urlType = JSVM_UNDEFINED;
    OH_JSVM_Typeof(env, args[0], &urlType);
    if (urlType != JSVM_STRING) {
        throwNamedError(env, "TypeError",
            std::string("httpGet 的第一个参数需要网址字符串，收到的是 ") +
            typeNameOfValue(env, args[0]) + "。");
        return nullptr;
    }
    const std::string url = valueToUtf8(env, args[0]);
    // opts 形态收口：undefined / null = 无可选项（optsJson = "{}"）；对象（非数组）→ JSON
    // 序列化透传；其余形态就地 TypeError。序列化挂起异常要清（防污染后续 JSVM 调用）
    std::string optsJson = "{}";
    if (argc >= 2) {
        JSVM_ValueType optType = JSVM_UNDEFINED;
        OH_JSVM_Typeof(env, args[1], &optType);
        if (optType != JSVM_UNDEFINED && optType != JSVM_NULL) {
            bool isArray = false;
            OH_JSVM_IsArray(env, args[1], &isArray);
            if (optType != JSVM_OBJECT || isArray) {
                throwNamedError(env, "TypeError",
                    std::string("httpGet 的第二个参数需要是对象，收到的是 ") +
                    (isArray ? "array" : typeNameOfValue(env, args[1])) + "。");
                return nullptr;
            }
            JSVM_Value json = nullptr;
            JSVM_Status st = OH_JSVM_JsonStringify(env, args[1], &json);
            if (st == JSVM_PENDING_EXCEPTION) {
                // 循环引用等序列化异常——清掉再就地报（对象含函数值属此态）
                JSVM_Value exc = nullptr;
                OH_JSVM_GetAndClearLastException(env, &exc);
            }
            if (st == JSVM_OK && json != nullptr) {
                JSVM_ValueType jsonType = JSVM_UNDEFINED;
                OH_JSVM_Typeof(env, json, &jsonType);
                if (jsonType == JSVM_STRING) {
                    optsJson = valueToUtf8(env, json);
                }
            }
        }
    }
    // 受理前取消检查（唯一一层判据，任务书 §3.5-3）：置位后的调用当场报错、不投递
    //（★ 2026-10-20 并发笔：改读本 run 的取消块——按 runKey 定向，他路取消不拦本路）
    if (state->cancelBlock != nullptr && state->cancelBlock->requested.load()) {
        throwNamedError(env, "HttpError", "本次运行已取消，不再发起新的网络请求。");
        return nullptr;
    }
    SandboxHttpOutcome r = SandboxHttpRequest(url, optsJson, state->opts.httpWaitMs,
        state->opts.runKey);
    if (!r.ok) {
        throwNamedError(env, "HttpError", r.errorText);
        return nullptr;
    }
    if (r.kind == "bytes") {
        JSVM_Value out = sandboxBytesToUint8Array(env, r.bytes);
        if (out == nullptr) {
            JSVM_Value stale = nullptr;
            OH_JSVM_GetAndClearLastException(env, &stale);
            throwNamedError(env, "HttpError", "httpGet 失败：字节数组创建失败。");
        }
        return out;
    }
    JSVM_Value out = nullptr;
    OH_JSVM_CreateStringUtf8(env, r.text.c_str(), r.text.size(), &out);
    return out;
}

// ── Promise 末值捕获（§3.7；编排与三态判定在 jsvm_runner 主流程——回调只回填
//    RunState 字段，微任务排空使它们执行）──

static JSVM_Value PromiseOnFulfilled(JSVM_Env env, JSVM_CallbackInfo info)
{
    void* data = nullptr;
    size_t argc = 1;
    JSVM_Value args[1] = { nullptr };
    OH_JSVM_GetCbInfo(env, info, &argc, args, nullptr, &data);
    RunState* state = stateOf(data);
    state->promiseValueText = argc > 0 ? serializeJsValue(env, args[0]) : "undefined";
    state->promiseSettled = true;
    return undefinedValue(env);
}

// 拒绝值按「异常三件」抽取（照 fillExceptionFields 形制与 D11 两道修复：throw 原始值时
// name/message 皆空 → 序列化拒绝值本身进 message；js-exception 标志由主流程统一处理）
static JSVM_Value PromiseOnRejected(JSVM_Env env, JSVM_CallbackInfo info)
{
    void* data = nullptr;
    size_t argc = 1;
    JSVM_Value args[1] = { nullptr };
    OH_JSVM_GetCbInfo(env, info, &argc, args, nullptr, &data);
    RunState* state = stateOf(data);
    if (argc > 0) {
        JSVM_Value v = args[0];
        JSVM_Value field = nullptr;
        if (OH_JSVM_GetNamedProperty(env, v, "name", &field) == JSVM_OK && field != nullptr) {
            JSVM_ValueType t = JSVM_UNDEFINED;
            OH_JSVM_Typeof(env, field, &t);
            if (t == JSVM_STRING) {
                state->promiseRejectName = valueToUtf8(env, field);
            }
        }
        if (OH_JSVM_GetNamedProperty(env, v, "message", &field) == JSVM_OK && field != nullptr) {
            JSVM_ValueType t = JSVM_UNDEFINED;
            OH_JSVM_Typeof(env, field, &t);
            if (t == JSVM_STRING) {
                state->promiseRejectMessage = valueToUtf8(env, field);
            }
        }
        if (OH_JSVM_GetNamedProperty(env, v, "stack", &field) == JSVM_OK && field != nullptr) {
            JSVM_ValueType t = JSVM_UNDEFINED;
            OH_JSVM_Typeof(env, field, &t);
            if (t == JSVM_STRING) {
                state->promiseRejectStack = valueToUtf8(env, field);
            }
        }
        if (state->promiseRejectName.empty() && state->promiseRejectMessage.empty()) {
            state->promiseRejectMessage = serializeJsValue(env, v);
        }
    } else {
        state->promiseRejectMessage = "undefined";
    }
    state->promiseRejected = true;
    state->promiseSettled = true;
    return undefinedValue(env);
}

void RegisterPromiseCapture(JSVM_Env env, JSVM_Value promise, RunState& state)
{
    state.cbPromiseFulfilled.callback = PromiseOnFulfilled;
    state.cbPromiseRejected.callback = PromiseOnRejected;
    state.promiseRegistered = true;
    // handler 形参是 JSVM_Value 函数对象（jsvm.h:2557 实读）——先从 CallbackStruct 创建
    JSVM_Value onFulfilled = nullptr;
    OH_JSVM_CreateFunction(env, "onFulfilled", 11, &state.cbPromiseFulfilled, &onFulfilled);
    JSVM_Value onRejected = nullptr;
    OH_JSVM_CreateFunction(env, "onRejected", 10, &state.cbPromiseRejected, &onRejected);
    JSVM_Value chained = nullptr;
    JSVM_Status st = OH_JSVM_PromiseRegisterHandler(env, promise, onFulfilled, onRejected,
        &chained);
    if (st != JSVM_OK) {
        // 注册失败（理论不可达——promise 刚验过原生）：清挂起异常防污染，排空后按未完成
        // 如实报 PendingPromiseError，不静默
        JSVM_Value stale = nullptr;
        OH_JSVM_GetAndClearLastException(env, &stale);
        OH_LOG_WARN(LOG_APP, "promise capture register failed: %{public}d", static_cast<int>(st));
    }
}

// ── 宿主面安装（console.log/warn/error + result + fs 七方法 + 五桥全局函数）──

void InstallSandboxHostApi(JSVM_Env env, RunState& state)
{
    state.cbConsoleLog.callback = HostConsoleLog;
    state.cbConsoleWarn.callback = HostConsoleWarn;
    state.cbConsoleError.callback = HostConsoleError;
    state.cbResult.callback = HostResult;
    state.cbFsList.callback = HostFsList;
    state.cbFsRead.callback = HostFsRead;
    state.cbFsReadBytes.callback = HostFsReadBytes;
    state.cbFsWrite.callback = HostFsWrite;
    state.cbFsAppend.callback = HostFsAppend;
    state.cbFsExists.callback = HostFsExists;
    state.cbFsSave.callback = HostFsSave;
    state.cbZlibCompress.callback = HostZlibCompress;
    state.cbZlibDecompress.callback = HostZlibDecompress;
    state.cbMd5.callback = HostMd5;
    state.cbSha1.callback = HostSha1;
    state.cbSha256.callback = HostSha256;
    state.cbHttpGet.callback = HostHttpGet;

    JSVM_Value global = nullptr;
    OH_JSVM_GetGlobal(env, &global);

    // console 对象
    JSVM_Value consoleObj = nullptr;
    OH_JSVM_CreateObject(env, &consoleObj);
    struct { const char* name; JSVM_CallbackStruct* cb; } consoleMembers[] = {
        { "log", &state.cbConsoleLog },
        { "warn", &state.cbConsoleWarn },
        { "error", &state.cbConsoleError }
    };
    for (auto& member : consoleMembers) {
        JSVM_Value fn = nullptr;
        OH_JSVM_CreateFunction(env, member.name, std::string(member.name).size(), member.cb, &fn);
        OH_JSVM_SetNamedProperty(env, consoleObj, member.name, fn);
    }
    OH_JSVM_SetNamedProperty(env, global, "console", consoleObj);

    // result(v)
    JSVM_Value resultFn = nullptr;
    OH_JSVM_CreateFunction(env, "result", 6, &state.cbResult, &resultFn);
    OH_JSVM_SetNamedProperty(env, global, "result", resultFn);

    // fs 对象（七方法：list / read / readBytes / write / append / exists / save）
    JSVM_Value fsObj = nullptr;
    OH_JSVM_CreateObject(env, &fsObj);
    struct { const char* name; JSVM_CallbackStruct* cb; } fsMembers[] = {
        { "list", &state.cbFsList },
        { "read", &state.cbFsRead },
        { "readBytes", &state.cbFsReadBytes },
        { "write", &state.cbFsWrite },
        { "append", &state.cbFsAppend },
        { "exists", &state.cbFsExists },
        { "save", &state.cbFsSave }
    };
    for (auto& member : fsMembers) {
        JSVM_Value fn = nullptr;
        OH_JSVM_CreateFunction(env, member.name, std::string(member.name).size(), member.cb, &fn);
        OH_JSVM_SetNamedProperty(env, fsObj, member.name, fn);
    }
    OH_JSVM_SetNamedProperty(env, global, "fs", fsObj);

    // zlib 与摘要桥 + 网络桥（全局函数——与 result 同段，非 fs 成员，§3.5-1；★ 笔E 起
    // httpGet 并排注册——沙箱网络唯一入口）
    struct { const char* name; JSVM_CallbackStruct* cb; } bridgeMembers[] = {
        { "zlibCompress", &state.cbZlibCompress },
        { "zlibDecompress", &state.cbZlibDecompress },
        { "md5", &state.cbMd5 },
        { "sha1", &state.cbSha1 },
        { "sha256", &state.cbSha256 },
        { "httpGet", &state.cbHttpGet }
    };
    for (auto& member : bridgeMembers) {
        JSVM_Value fn = nullptr;
        OH_JSVM_CreateFunction(env, member.name, std::string(member.name).size(), member.cb, &fn);
        OH_JSVM_SetNamedProperty(env, global, member.name, fn);
    }

    // 不注入面（§3.3-3）：fetch / XMLHttpRequest / require / import（引擎里本就没有）/
    // setTimeout（无宏任务循环，明确不提供——写进 desc 与帮助条目）。★ 笔E 订正：网络
    // 能力经 httpGet 单通道提供（默认 GET、写方法需全局开关开启、预授权域名），fetch /
    // XMLHttpRequest 仍恒不注入
}
