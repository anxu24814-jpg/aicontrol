// Node.js 运行时引擎 napi 入口（2026-11-23 鸿蒙 Node 运行时门 1 笔，任务书-鸿蒙Node运行时
// 门1-20261121 U3）：进程内嵌 libnode.so（门 0 冻结产物，entry/libs/arm64-v8a/libnode.so，
// GitHub Actions 交叉编译产出）——**dlopen 形态**，与 pyengine 链 libpython 不同：本目标
// 不链 libnode、CMake 无 -L libs 行（DT_NEEDED 只 libc++_shared.so + libc.so，由系统 linker
// 从应用 lib 目录解析）。
// · 两入口（同步，契约同 types/libnodeengine/index.d.ts）：
//   start(homeDir) 受理即返回 started / already-started / invalid-home / thread-error，
//   启动序列在线程内异步推进；status() 返回 JSON 串（threadAlive / shimInstalled /
//   crashHandlerInstalled / envSet / dlopened / dlerror / startSymbol / nodeStarted）。
//   eval 不经 native——探针页经本地回环直连 bootstrap 起的 server（任务书 §1）。
// · 启动序列六步（顺序错即崩，调研档 §3.4 实证；各步一行 hilog 里程碑）：
//   ① SIGSYS shim（io_uring trap → 返回值正好 -1，非 -ENOSYS——libuv 守卫只认 -1）
//   ② 崩溃处理器（SIGSEGV/SIGABRT/SIGBUS/SIGILL/SIGTRAP 尽力 backtrace + hilog）
//   ③ setenv("UV_USE_IO_URING","0",1) ④ setenv("HOME", homeDir, 1)
//   ⑤ dlopen 绝对路径 ⑥ dlsym `_ZN4node5StartEiPPc` → node::Start(argc, argv)
// · dlopen 路径 = dladdr 反查 nodeengine 自身 so 所在目录拼 libnode.so（PyEngine dladdr
//   先例，不写死）；禁裸名 dlopen（裸名搜索不含应用 lib 目录，2132 真机实锤）；NULL 必查
//   dlerror 并 hilog ERROR + status 透出——静默失败是六约束②的头号误诊形态。
// · 线程形态（2242 笔 / 调研档 §3.4-1）：detached 常驻线程，node::Start 不返回、join 永不
//   可达，detached 防 joinable 线程析构 terminate；线程对象故意 new 不释放（与进程同寿命，
//   照 PyEngine EnsurePyThread 先例）。
// · 单次启动约束：node::Start 一进程只能调一次（二次命中源码断言崩，调研档 §3.2-⑥）——
//   gStarted 原子门，重复 start 返回 already-started 不触 Start；崩溃恢复口径 = 重启应用。
// · 与 codeexec/qjsengine/pyengine 二进制独立红线：不互相 target_link_libraries、禁 dlopen
//   互载——本目标只链 napi/hilog，libnode 经 dlopen 自持。
// · jitless 定夺（任务书 §6）：构建期常量 NODE_JITLESS_ENABLED 默认 0（首跑不带 --jitless；
//   崩溃处理器捕到 SIGTRAP 且日志对上 W^X 形态才翻 1 重编，argv 插 --jitless --no-verify-heap，
//   并记录设备型号进 BLOCKED 清单第 4 项）。禁默认加。
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <dlfcn.h>
#include <execinfo.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/types.h>
#include <ucontext.h>
#include <unistd.h>

#include "hilog/log.h"
#include "napi/native_api.h"

// ── node::Start 最小声明（任务书 §1「include 头消费」行的备选路径，指挥复核裁定 2026-11-23）
// 门 0 产出的 include 树已随仓落位（cpp/nodeengine/include/，src + deps/v8 + deps/uv 三树），
// 但**本目标不 include node.h**：Node 自带 node_api.h / js_native_api.h 与 OHOS SDK 的
// napi/native_api.h 对同名函数与类型双份声明，SDK clang 实编报 conflicting types
// （napi_adjust_external_memory / napi_set_instance_data / napi_env 等十余处），两套 NAPI
// 头不可同文件共存。本目标只经 dlsym 消费一个符号，手写最小声明即够（PyEngine.cpp
// CPython 最小声明集先例）；dlsym 函数指针类型由 decltype 取，防手抄签名漂移。
// 门 2 若需更多 node C++ API（如 Environment 面），另立不引 OHOS napi 头的编译单元消费
// include 树，本单元保持现状。
namespace node {
int Start(int argc, char* const argv[]);
}

// jitless 旗标（构建期常量，任务书 §6；默认关——禁默认加）
#ifndef NODE_JITLESS_ENABLED
#define NODE_JITLESS_ENABLED 0
#endif

// heap 上限旗标（构建期常量，门 2 §4 S1-2；0 = 不生效——禁默认改堆上限，A/B 读数轮经
// 构建命令传 NODE_MAX_OLD_SPACE_SIZE_MB=512 之类，验证后复位 0 交付）
#ifndef NODE_MAX_OLD_SPACE_SIZE_MB
#define NODE_MAX_OLD_SPACE_SIZE_MB 0
#endif

// node::Start 函数指针类型（node.h 声明 int Start(int argc, char* const argv[])）
typedef decltype(&node::Start) NodeStartFn;

// ── 进程级状态（各步置位供 status() 读；写在线程内、读在 JS 线程——原子 + 互斥保护串）──
static std::atomic<bool> gStarted(false);               // start 受理门（防 node::Start 二调）
static std::atomic<bool> gThreadAlive(false);
static std::atomic<bool> gShimInstalled(false);
static std::atomic<bool> gCrashHandlerInstalled(false);
static std::atomic<bool> gEnvSet(false);
static std::atomic<bool> gDlopened(false);
static std::atomic<bool> gStartSymbol(false);
static std::atomic<bool> gNodeStarted(false);
static std::mutex gErrorMutex;                          // 保护 gDlError（写线程写、JS 线程读）
static std::string gDlError;
// SIGSYS shim 命中计数（handler 内累加；限次打 hilog 防 io_uring 密集重试刷屏）
static std::atomic<uint64_t> gShimHits(0);
// 崩溃日志目录（装信号处理器前写入；handler 内 async-signal-safe 直接用）
static char gCrashHomeDir[512] = { 0 };
// 宿主人参 homeDir（start 受理时写入，线程组 argv 与 setenv 用；受理后只读）
static std::string gHomeDir;

static void SetDlError(const std::string& message)
{
    std::lock_guard<std::mutex> lk(gErrorMutex);
    gDlError = message;
}

// ── ① SIGSYS shim（调研档 §3.2-④）：io_uring 被 seccomp 拦截时内核投递 SIGSYS——
// 返回 -ENOSYS 是已知错误形态（libuv 守卫只认 -1），aarch64 上直接改 ucontext 让返回值
// 正好 -1。pc 不动：svc 异常保存的返回地址本就是 svc 的下一条指令（Linux v5.10
// arch/arm64/kernel/syscall.c 全程不改 pc），处理函数看到的 pc 已在 svc 之后；再 +4 会
// 多跳一条指令（2250 真机实锤：跳过 libc syscall() 末尾的 ret，执行流滑进相邻的
// __dlvsym 带垃圾参数查符号，strlen 段错误）。命中计数供 status 与 hilog 判读；该 libuv
// 构建在循环初始化处无条件发起 io_uring_setup（反汇编实测不读 UV_USE_IO_URING），
// 沙箱拦截下命中数大于 0 属预期。
static void SigSysHandler(int sig, siginfo_t* info, void* uctxRaw)
{
    (void)sig;
    (void)info;
    ucontext_t* uctx = static_cast<ucontext_t*>(uctxRaw);
    if (uctx == nullptr) {
        return;
    }
    uctx->uc_mcontext.regs[0] = static_cast<greg_t>(-1);
    const uint64_t hits = gShimHits.fetch_add(1) + 1;
    if (hits <= 10) {
        OH_LOG_INFO(LOG_APP, "nodeengine SIGSYS shim hit=%{public}llu",
            static_cast<unsigned long long>(hits));
    }
}

// ── ② 崩溃处理器：五信号尽力落背栈到 <homeDir>/crash-<ts>.log + hilog 一行；不拦截崩溃
// 语义（记录后恢复默认处理再重发，进程照常死——Node 域崩溃恢复口径 = 重启应用）。
// SIGTRAP 是本处理器最关键的判读对象：jitless 定夺（任务书 §6）依赖其留痕。
static void CrashHandler(int sig, siginfo_t* info, void* uctxRaw)
{
    (void)uctxRaw;
    void* frames[32];
    const int frameCount = backtrace(frames, 32);
    const long long ts = static_cast<long long>(time(nullptr));
    if (gCrashHomeDir[0] != '\0') {
        char path[600];
        snprintf(path, sizeof(path), "%s/crash-%lld.log", gCrashHomeDir, ts);
        const int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (fd >= 0) {
            char buf[128];
            int len = snprintf(buf, sizeof(buf), "signal %d addr %p frames %d\n", sig,
                info != nullptr ? info->si_addr : nullptr, frameCount);
            if (len > 0) {
                (void)write(fd, buf, static_cast<size_t>(len));
            }
            for (int i = 0; i < frameCount; ++i) {
                len = snprintf(buf, sizeof(buf), "frame[%d] %p\n", i, frames[i]);
                if (len > 0) {
                    (void)write(fd, buf, static_cast<size_t>(len));
                }
            }
            (void)close(fd);
        }
    }
    OH_LOG_ERROR(LOG_APP, "nodeengine crash signal=%{public}d addr=%{public}p frames=%{public}d",
        sig, info != nullptr ? info->si_addr : nullptr, frameCount);
    // 恢复默认处理并重发——不吞信号、不改崩溃语义
    signal(sig, SIG_DFL);
    raise(sig);
}

// naPi 取串（两段式：先取长再取内容——照 PyEngine napiReadString 同款）
static bool NapiReadString(napi_env env, napi_value v, std::string& out)
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

// JSON 串转义（status 的 dlerror 字段用；只处理控制字符与引号反斜杠）
static std::string JsonEscape(const std::string& s)
{
    std::string out;
    out.reserve(s.size() + 8);
    for (char c : s) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (static_cast<unsigned char>(c) < 0x20) {
                    char buf[8];
                    snprintf(buf, sizeof(buf), "\\u%04x", static_cast<unsigned char>(c));
                    out += buf;
                } else {
                    out.push_back(c);
                }
        }
    }
    return out;
}

// dladdr 反查本 so 所在目录（应用 lib 目录绝对路径，真机形态 /data/app/.../libs/arm64）
static std::string SelfLibDir()
{
    Dl_info info;
    if (dladdr(reinterpret_cast<void*>(&SelfLibDir), &info) == 0 || info.dli_fname == nullptr) {
        return "";
    }
    std::string libPath(info.dli_fname);
    const size_t slash = libPath.find_last_of('/');
    if (slash == std::string::npos || slash == 0) {
        return "";
    }
    return libPath.substr(0, slash);
}

// ── 启动序列六步（detached 常驻线程内依序执行；任一步失败记录并停在该步）──
static void NodeThreadLoopBody()
{
    OH_LOG_INFO(LOG_APP, "nodeengine thread started");

    // ① SIGSYS shim
    {
        struct sigaction sa;
        memset(&sa, 0, sizeof(sa));
        sa.sa_sigaction = SigSysHandler;
        sa.sa_flags = SA_SIGINFO | SA_RESTART;
        sigemptyset(&sa.sa_mask);
        if (sigaction(SIGSYS, &sa, nullptr) != 0) {
            SetDlError("SIGSYS shim 安装失败");
            OH_LOG_ERROR(LOG_APP, "nodeengine step1 sigaction(SIGSYS) failed");
            return;
        }
        gShimInstalled.store(true);
        OH_LOG_INFO(LOG_APP, "nodeengine step1 SIGSYS shim installed");
    }

    // ② 崩溃处理器（五信号；崩溃日志目录先落进全局 char 缓冲）
    {
        const size_t homeLen = gHomeDir.size();
        if (homeLen > 0 && homeLen < sizeof(gCrashHomeDir) - 1) {
            memcpy(gCrashHomeDir, gHomeDir.c_str(), homeLen);
            gCrashHomeDir[homeLen] = '\0';
        }
        struct sigaction sa;
        memset(&sa, 0, sizeof(sa));
        sa.sa_sigaction = CrashHandler;
        sa.sa_flags = SA_SIGINFO;
        sigemptyset(&sa.sa_mask);
        const int crashSignals[5] = { SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGTRAP };
        bool allInstalled = true;
        for (int sig : crashSignals) {
            if (sigaction(sig, &sa, nullptr) != 0) {
                allInstalled = false;
                OH_LOG_WARN(LOG_APP, "nodeengine step2 sigaction(%{public}d) failed", sig);
            }
        }
        gCrashHandlerInstalled.store(allInstalled);
        OH_LOG_INFO(LOG_APP, "nodeengine step2 crash handler installed=%{public}d",
            allInstalled ? 1 : 0);
    }

    // ③④ setenv 两键
    setenv("UV_USE_IO_URING", "0", 1);
    setenv("HOME", gHomeDir.c_str(), 1);
    gEnvSet.store(true);
    OH_LOG_INFO(LOG_APP, "nodeengine step3/4 env set HOME=%{public}s", gHomeDir.c_str());

    // ⑤ dlopen 绝对路径（禁裸名——裸名搜索不含应用 lib 目录）
    const std::string libDir = SelfLibDir();
    if (libDir.empty()) {
        SetDlError("nodeengine 自身 so 路径反查失败");
        OH_LOG_ERROR(LOG_APP, "nodeengine step5 dladdr self failed");
        return;
    }
    const std::string libPath = libDir + "/libnode.so";
    void* handle = dlopen(libPath.c_str(), RTLD_NOW);
    if (handle == nullptr) {
        const char* err = dlerror();
        const std::string message = std::string("dlopen libnode.so 失败，")
            + (err != nullptr ? err : "dlerror 为空");
        SetDlError(message);
        OH_LOG_ERROR(LOG_APP, "nodeengine step5 dlopen failed path=%{public}s err=%{public}s",
            libPath.c_str(), err != nullptr ? err : "(null)");
        return;
    }
    gDlopened.store(true);
    OH_LOG_INFO(LOG_APP, "nodeengine step5 dlopen ok path=%{public}s", libPath.c_str());

    // ⑥ dlsym node::Start（符号名门 0 产物实测：_ZN4node5StartEiPPc）
    const char* const kStartSymbol = "_ZN4node5StartEiPPc";
    void* sym = dlsym(handle, kStartSymbol);
    if (sym == nullptr) {
        const char* err = dlerror();
        SetDlError(std::string("dlsym node::Start 失败，") + (err != nullptr ? err : "dlerror 为空"));
        OH_LOG_ERROR(LOG_APP, "nodeengine step6 dlsym failed symbol=%{public}s", kStartSymbol);
        return;
    }
    gStartSymbol.store(true);
    NodeStartFn startFn = reinterpret_cast<NodeStartFn>(sym);
    OH_LOG_INFO(LOG_APP, "nodeengine step6 dlsym ok symbol=%{public}s", kStartSymbol);

    // argv 组装（任务书 §1「argv 与哨兵」行）：argc 绝不计入末尾 nullptr 哨兵——多算一个
    // Node 拿 NULL 参数 5 毫秒内段错误；逐项 hilog 打印，出现 (null) 即红。
    // static 存储：Start 不返回时栈帧不弹，但若事件循环已死返回后指针失效前不再使用。
    static std::vector<std::string> argStore;
    argStore.clear();
    argStore.push_back("node");
#if NODE_JITLESS_ENABLED
    argStore.push_back("--jitless");
    argStore.push_back("--no-verify-heap");
#endif
#if NODE_MAX_OLD_SPACE_SIZE_MB > 0
    // heap 上限（门 2 A/B 读数旗标）：仅显式非 0 构建才插参，交付值恒 0 不生效
    argStore.push_back("--max-old-space-size=" + std::to_string(NODE_MAX_OLD_SPACE_SIZE_MB));
#endif
    argStore.push_back(gHomeDir + "/bootstrap.js");
    const int argc = static_cast<int>(argStore.size());
    static std::vector<char*> argvStore;
    argvStore.clear();
    for (std::string& arg : argStore) {
        argvStore.push_back(&arg[0]);
    }
    argvStore.push_back(nullptr); // 哨兵：不计入 argc
    for (int i = 0; i < argc; ++i) {
        if (argvStore[i] == nullptr) {
            OH_LOG_ERROR(LOG_APP, "nodeengine argv[%{public}d] is null (哨兵多算)", i);
            SetDlError("argv 组装异常");
            return;
        }
        OH_LOG_INFO(LOG_APP, "nodeengine argv[%{public}d]=%{public}s", i, argvStore[i]);
    }

    gNodeStarted.store(true);
    OH_LOG_INFO(LOG_APP, "nodeengine step6 node::Start argc=%{public}d", argc);
    const int rc = startFn(argc, argvStore.data());
    // 理论不返回；返回 = 事件循环已死
    OH_LOG_ERROR(LOG_APP, "nodeengine node::Start returned rc=%{public}d", rc);
    gNodeStarted.store(false);
    SetDlError("node::Start 已返回（事件循环结束）");
}

// threadAlive 真实存活判据（门 2 修正，任务书 §2 第 2 条）：原实现在线程入口只置位不复位
// （:213），任一启动步失败（shim/dlopen/dlsym/argv 异常）或 node::Start 意外返回后仍显
// 「线程在」。包一层总闸——body 的所有退出路径（六步早期 return / Start 返回）都经此处
// 复位：true = 线程循环仍在跑；false = 启动失败或事件循环已结束。
static void NodeThreadLoop()
{
    gThreadAlive.store(true);
    NodeThreadLoopBody();
    gThreadAlive.store(false);
}

// start 受理本体（napi 线程调用；六步投给常驻线程异步推进）
static std::string StartRuntime(const std::string& homeDir)
{
    if (homeDir.empty() || homeDir.size() > 400 || access(homeDir.c_str(), W_OK) != 0) {
        return "invalid-home";
    }
    bool expected = false;
    if (!gStarted.compare_exchange_strong(expected, true)) {
        return "already-started";
    }
    gHomeDir = homeDir;
    try {
        static std::once_flag threadOnce;
        std::call_once(threadOnce, []() { (void)new std::thread(NodeThreadLoop); });
    } catch (...) {
        // 线程创建失败（如 EAGAIN）：call_once 未标记完成，下一次 start 可重试
        gStarted.store(false);
        OH_LOG_ERROR(LOG_APP, "nodeengine create thread failed");
        return "thread-error";
    }
    return "started";
}

// start(homeDir) → string（started / already-started / invalid-home / thread-error）
static napi_value StartEntry(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = { nullptr };
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 1) {
        napi_throw_type_error(env, nullptr, "start 需要一个 homeDir 字符串参数");
        return nullptr;
    }
    std::string homeDir;
    if (!NapiReadString(env, argv[0], homeDir)) {
        napi_throw_type_error(env, nullptr, "start 的 homeDir 必须是字符串");
        return nullptr;
    }
    std::string result;
    try {
        result = StartRuntime(homeDir);
    } catch (...) {
        OH_LOG_ERROR(LOG_APP, "nodeengine start threw");
        result = "thread-error";
    }
    napi_value out = nullptr;
    napi_create_string_utf8(env, result.c_str(), result.size(), &out);
    return out;
}

// status() → JSON 串（字段名与 types/libnodeengine/index.d.ts 契约同步）
static napi_value StatusEntry(napi_env env, napi_callback_info info)
{
    (void)info;
    std::string dlerror;
    {
        std::lock_guard<std::mutex> lk(gErrorMutex);
        dlerror = gDlError;
    }
    const auto boolStr = [](bool v) { return v ? "true" : "false"; };
    std::string json = "{\"threadAlive\":";
    json += boolStr(gThreadAlive.load());
    json += ",\"shimInstalled\":";
    json += boolStr(gShimInstalled.load());
    json += ",\"crashHandlerInstalled\":";
    json += boolStr(gCrashHandlerInstalled.load());
    json += ",\"envSet\":";
    json += boolStr(gEnvSet.load());
    json += ",\"dlopened\":";
    json += boolStr(gDlopened.load());
    json += ",\"dlerror\":\"";
    json += JsonEscape(dlerror);
    json += "\",\"startSymbol\":";
    json += boolStr(gStartSymbol.load());
    json += ",\"nodeStarted\":";
    json += boolStr(gNodeStarted.load());
    json += ",\"shimHits\":";
    json += std::to_string(gShimHits.load());
    json += "}";
    napi_value out = nullptr;
    napi_create_string_utf8(env, json.c_str(), json.size(), &out);
    return out;
}

// 模块注册（官方范式：constructor 自动注册——照 pyengine 同款）
EXTERN_C_START
static napi_value InitModule(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "start", nullptr, StartEntry, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "status", nullptr, StatusEntry, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module nodeengineModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = InitModule,
    .nm_modname = "nodeengine",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterNodeengineModule(void)
{
    napi_module_register(&nodeengineModule);
}
