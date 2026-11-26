// Python 解释器引擎 napi 入口（2026-11-06 鸿蒙Python运行时门1笔，任务书-鸿蒙Python运行时
// 门0门1-20261106 U4）：进程内嵌 CPython 3.13.18（产物 = entry/libs/arm64-v8a 的
// libpython3.13.so + C 扩展全家，GitHub Actions 交叉编译产出）+ rawfile 三件 zip
// （python313.zip / site-packages.zip / extras.zip，门 2 起；PYTHONPATH 四层见下方 init 段）。
// · 四入口：init(homeDir) 初始化解释器（幂等）/ exec(code, timeoutMs, sessionKey?, cwd?)
//   异步执行并捕获 stdout/stderr / cancel() 协作式取消 / dropNamespaces(keys) 释放会话
//   命名空间。字段契约与 types/libpyengine/index.d.ts、common/pyexec/PyRuntime.ets
//   三处同步（照 libcodeexec「契约同步」纪律）。
// · 生命周期（方案档 §2.4 单解释器口径）：解释器进程级单例，init 幂等（已初始化直接返回
//   版本串）；不做 Py_FinalizeEx 调用路径——解释器一旦初始化随进程存续（重建/清包策略 =
//   管理页置不可用 + 提示重启应用，方案 §2.4 行为矩阵）。
// · 互斥（方案档 §2.4 Python 全局串行）：init 与 exec 与 dropNamespaces 共用 gExecMutex
//   ——init 串行初始化（CPython 初始化非线程安全，并发 init = UB），exec 同一时刻仅一个
//   在跑、后续调用在锁上排队（napi async work 的 Execute 天然并发，lock_guard 排队而非拒绝）。
// · 执行线程（2242 笔 A1 形态）：全部 Python 工作（init/exec/drop）跑在进程内唯一常驻线程
//   （PyThreadLoop）上，不落在 napi async work 的 libuv 线程池里。根因 = 线程池复用同一 OS
//   线程时，PyGILState_Release 计数归零会让 CPython 删除该线程态，而 pybind11 系扩展
//   （matplotlib ft2font / contourpy 等）在 internals.tstate_key 的 TSS 里缓存过这个指针
//   ——下一发再用它调 PyEval_AcquireThread 即 UAF 崩（2026-11-16「生成 PPT」崩溃栈实证：
//   gil_scoped_acquire → PyEval_AcquireThread → take_gil 段；本地产物反汇编对位
//   ft2font+0x4b900/0x5d1b0 与 libpython 0x30b2a4 区）。形态 = 专用线程持有 Py_InitializeEx
//   建的主线程态（gilstate_counter 恒 ≥1），每发 PyEval_RestoreThread/SaveThread 往返复用
//   同一 tstate、永不删除 ⇒ pybind11 的缓存长期有效。看门狗与 cancel 仍从任意线程经
//   PyGILState_Ensure 投递中断——那些线程不跑 pybind11，用完即删的线程态无缓存风险。
// · 会话命名空间（门 4，方案 §2.4「单解释器 + 按会话顶层全局命名空间 + 串行执行」）：
//   gNamespaces 按 sessionKey（= 会话 id）各持一个 globals dict，用户变量与已加载模块的
//   模块级状态按会话分家；sys.modules、C 扩展静态状态等进程级配置不随命名空间分家（方案
//   行为矩阵明示不承诺会话隔离）。exec 用 PyRun_String(userCode, globals=dict) 落 dict；
//   save() 登记函数与 _pySaved 登记表随 dict 首用注入并跨轮驻留（同会话续算）。dict 总数
//   上限 PY_NS_MAX（数据有界红线）：超限淘汰最久未用（LRU）——被淘汰会话的内存变量失效，
//   与「应用重启后内存变量不恢复」同族口径。dropNamespaces 由会话删除级联调用（best-effort）。
// · 超时/取消 = 协作式（方案档 §2.4 口径）：PyThreadState_SetAsyncExc 对 exec 线程设
//   异常、由该线程在解释器检查点自查消费——不承诺强杀，脚本停在原生调用（如 C 扩展阻塞）
//   时不能立即中断，对外文案禁出现「可中断」「随时停止」类表述。过期请求（对应 exec 已
//   结束）由代次号 + 线程号双比对丢弃；exec 收尾显式清 async_exc 防残留污染下次执行。
//   ★ 通道选型（2026-11-06 双环境实证，2120 节）：Py_AddPendingCall 的回调只被主解释器
//   线程消费（官方文档「from the main interpreter thread」；3.13 Actions 与 3.14 桌面
//   双复现「worker 跑满不中断」），本进程主线程 = ArkTS UI 线程永不进 Python 检查点 ⇒
//   pending 永远滞留 = 取消/超时静默失效（真机闸① 实锤 tick 0-19 跑满），滞留回调在
//   错误上下文冒出还会段错误（3.13 Actions exit 139）；SetAsyncExc 通道 3.13.18 实证
//   生效（KeyboardInterrupt@tick3，半秒检查点粒度）。
// · stdout/stderr 捕获：exec 前引导串把 sys.stdout/sys.stderr 换成 io.StringIO（解释器
//   全局替换、串行执行下无双跑竞争），跑完在会话 dict 内读回；Python 层异常的 traceback
//   由 PyErr_Print 渲染进捕获的 stderr（PyRun_String 不自印异常，须显式渲染 + 清除）。
//   收集段带上限 PY_STREAM_CAP_CHARS（2171 修）：保头截尾 + 溢出标记行——上限前的全量
//   回传链（StringIO → getvalue → C++ string → napi → JS 四份拷贝）无界，巨型 print 可达
//   百 MB 级；脚本运行期 StringIO 本体不设闸（与脚本自建大对象同族，不承诺内存上限）。
// · exec 收尾守卫 PyExecShutdownGuard（2171 修）：GIL 块内 C++ 分配抛出（bad_alloc）时
//   栈展开曾跳过放锁与看门狗 join——GIL 永久持死 + joinable 线程析构 = std::terminate
//   整进程崩；守卫析构兜异常路径（放锁前同款清理，join 恒在放锁之后，防死锁面）。
// · 安全审计钩（门 4 文件/网络减险，方案 §5.5「审计钩只能减险不能防御」）：init 装
//   sys.addaudithook，只记录不改写行为——写模式 open、socket.connect/getaddrinfo、
//   subprocess.Popen、os.system、ctypes.dlopen 五类事件进 __main__._pyAudit（上限 50 条，
//   只保留尾部）；每次 exec 收尾读回清空、随结果返回（ArkTS 拼安全记录行进回执）。钩内
//   全包 try/except（钩抛异常会打穿用户代码）；**这是可观测性减险，不是边界**——desc 与
//   帮助不得写成沙箱承诺（拍板口径）。
// · init 附带 setenv 两项（闸②③ 真机发现，2165 节）：①MPLCONFIGDIR 指向 homeDir 内可写
//   目录（默认路径 /storage/Users/currentUser 只读，每跑两条 warning——matplotlib 自建该
//   目录）；②SSL_CERT_FILE / SSL_CERT_DIR 按候选探测——**随包 extras/cert.pem 优先**（2243
//   笔起由工厂投放：源自 pip 内置 certifi 的 Mozilla CA bundle，约 230KB），次选运行区根
//   homeDir/cert.pem（既有投放点，保留兼容），再退系统 CA 目录 /system/etc/security/cacerts
//   （OHOS 侧命名与可读性各版本不一，只作兜底）。access 判在场才设，不存在的路径不写进
//   env——P0-1 不假装就绪；三者全落空打 WARN（原实现静默，真机证书错无诊断痕）。
//   根因备忘：_ssl 的 openssl_cafile 固化在 Actions 构建机路径（门 0 OPENSSLDIR 泄漏），
//   设 env 是宿主侧唯一覆盖通道。
// · 与 codeexec/qjsengine 二进制独立红线无关（不互相链接、不 dlopen 互载）——本目标只
//   链 napi/hilog 与 libpython3.13（-L 指向 entry/libs/arm64-v8a，符号在加载期由系统
//   linker 从同目录解析）。
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <exception>
#include <functional>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <dlfcn.h>
#include <unistd.h>

#include "hilog/log.h"
#include "napi/native_api.h"

// ── CPython 最小声明集（extern "C"，防 C++ mangle 链接失败）──
// libpython 无头文件随包（门 0 产物只含 .so 与 stdlib zip）；本文件只用少量稳定 C API，
// 在此手写最小声明，完整头随门 2 工厂产出补（产出 prefix/include 后替换本段）。
// 声明依据 = CPython 3.13 稳定 ABI 文档（docs.python.org/3.13/c-api/）。
extern "C" {
typedef struct _object PyObject;
typedef long Py_ssize_t; // aarch64 LP64：long 与 Py_ssize_t 同宽
typedef int PyGILState_STATE;
typedef struct _ts PyThreadState;
void Py_InitializeEx(int initsigs);
int Py_IsInitialized(void);
int Py_FinalizeEx(int status);
int PyRun_SimpleString(const char* command);
// 门 4 会话命名空间主通道：globals/locals 传会话 dict；start 恒 Py_file_input（语句体）
PyObject* PyRun_String(const char* str, int start, PyObject* globals, PyObject* locals);
PyGILState_STATE PyGILState_Ensure(void);
void PyGILState_Release(PyGILState_STATE);
PyThreadState* PyEval_SaveThread(void);
// 专用线程挂回同一线程态（与 SaveThread 成对——不建新态、不删除既有态，2242 笔 A1 核心 API）
void PyEval_RestoreThread(PyThreadState* tstate);
// 线程 ID 形态（unsigned long）——SetAsyncExc 按 tstate->thread_id 比对，非 tstate 指针
unsigned long PyThread_get_thread_ident(void);
// 持 GIL 调用；返回被改线程数（1=成功 / 0=ID 无匹配）；exc=nullptr 为清除形态（2120 通道）
int PyThreadState_SetAsyncExc(unsigned long id, PyObject* exc);
void PyErr_Clear(void);
void PyErr_Print(void); // 渲染当前异常到 sys.stderr 并清除（PyRun_String 失败路径用）
extern PyObject* PyExc_KeyboardInterrupt;
const char* Py_GetVersion(void);
PyObject* PyImport_AddModule(const char* name);
PyObject* PyObject_GetAttrString(PyObject* o, const char* attr);
const char* PyUnicode_AsUTF8(PyObject* unicode);
void Py_DecRef(PyObject* o);
// 命名空间 dict 与读回面（门 4）
PyObject* PyDict_New(void);
PyObject* PyDict_GetItemString(PyObject* dp, const char* key); // 借用引用
int PyDict_SetItemString(PyObject* dp, const char* key, PyObject* item);
PyObject* PyEval_GetBuiltins(void); // 借用引用（__builtins__ 种子）
Py_ssize_t PyList_Size(PyObject* list);
PyObject* PyList_GetItem(PyObject* list, Py_ssize_t index); // 借用引用
int PyList_SetSlice(PyObject* list, Py_ssize_t low, Py_ssize_t high, PyObject* item); // 清空形态 item=nullptr
}

// PyRun_String 的 start 常量（ceval.h Py_file_input = 257——语句体可含 import/def）
static const int PY_FILE_INPUT = 257;

// ── 进程级状态 ──
// exec 互斥锁（Python 全局串行：同一时刻仅一个 exec 持锁在跑，后续排队）
static std::mutex gExecMutex;
// exec 代次号：每次持锁递增；中断请求携带发起时的代次，执行时与当前值不符 = 过期请求
// （对应 exec 已结束），静默丢弃——防「超时/取消请求迟到，下次执行开头被莫名打断」
static std::atomic<uint64_t> gExecGeneration(0);
// exec 线程号（GIL 内登记、出 GIL 前清零）：SetAsyncExc 的投递目标。线程号与代次号
// 双比对后才投递，防过期请求命中下一发 exec 或残留挂到空闲线程态上。2242 起投递目标恒为
// 专用 Python 线程（同一号），双比对语义不变
static std::atomic<unsigned long> gExecThreadId(0);
// 取消旗标（cancel() 置位；exec 持锁后清零——排队期收到的过期旗标不得带进本次执行，
// 清零时序见 RunPythonLocked 内注释；结果标注 Canceled 用——中断动作本体由
// SetAsyncExc 承担）
static std::atomic<bool> gCancelRequested(false);

// ── 专用 Python 线程与任务队列（2242 笔 A1；根因与形态见文件头「执行线程」条）──
// 三条不变量：① 初始化、主线程态创建与每一发 exec/drop 全部落在同一线程（PyThreadLoop）；
// ② 主线程态 gMainTstate 跨轮复用、永不删除——每发 RestoreThread 挂回、收尾 SaveThread
// 摘下，指针恒不变（pybind11 的 TSS 缓存因此长期有效）；③ gExecMutex 保留（命名空间表与
// 串行口径的既有守卫），但真正的排队点是本队列。
struct PyTask {
    std::function<void()> run;
    std::mutex mtx;
    std::condition_variable cv;
    bool done = false;
    // 任务体内 C++ 异常转交等待方（线程循环绝不吞异常——吞掉即回执空错，吞进线程循环
    // 更会让后续全部调用永久挂起）
    std::exception_ptr err;
};

static std::deque<PyTask*> gTaskQueue;
static std::mutex gQueueMutex;
static std::condition_variable gQueueCv;
// 专用线程的主线程态（init 里 PyEval_SaveThread 的返回值；进程存续期内不复建不删除）
static PyThreadState* gMainTstate = nullptr;
// 线程只起一次（std::call_once：起线程抛异常（如 EAGAIN）时下一次调用可重试，不留半启动面）
static std::once_flag gPyThreadOnce;

static void PyThreadLoop()
{
    OH_LOG_INFO(LOG_APP, "pyengine python thread started tid=%{public}lu",
        PyThread_get_thread_ident());
    for (;;) {
        PyTask* task = nullptr;
        {
            std::unique_lock<std::mutex> lk(gQueueMutex);
            gQueueCv.wait(lk, [] { return !gTaskQueue.empty(); });
            task = gTaskQueue.front();
            gTaskQueue.pop_front();
        }
        try {
            task->run();
        } catch (...) {
            task->err = std::current_exception();
        }
        {
            std::lock_guard<std::mutex> lk(task->mtx);
            task->done = true;
        }
        task->cv.notify_all();
    }
}

// 起线程（幂等）。线程对象故意 new 后不释放：静态 std::thread 析构时 joinable = std::terminate，
// 而本线程与解释器同为进程生命周期（方案 §2.4「随进程存续」口径，成对释放红线豁免面）
static void EnsurePyThread()
{
    std::call_once(gPyThreadOnce, []() { (void)new std::thread(PyThreadLoop); });
}

// 投递并等同（调用面 = napi async work 的 Execute 线程；全程不持 GIL，可安全阻塞等结果）
static void RunTaskSync(PyTask* task)
{
    EnsurePyThread();
    {
        std::lock_guard<std::mutex> lk(gQueueMutex);
        gTaskQueue.push_back(task);
    }
    gQueueCv.notify_one();
    std::unique_lock<std::mutex> lk(task->mtx);
    task->cv.wait(lk, [task] { return task->done; });
    if (task->err) {
        std::rethrow_exception(task->err);
    }
}

// 会话命名空间登记项（dict 的引用由本表持有；lastUse 供 LRU 淘汰比较）
struct PyNamespaceRec {
    PyObject* dict;
    uint64_t lastUse;
};
// 命名空间表（sessionKey → dict）。访问恒在 gExecMutex + GIL 双持下（exec/drop 双通道
// 都先锁 gExecMutex 再进 GIL，无竞争窗口）
static std::map<std::string, PyNamespaceRec> gNamespaces;
// 命名空间 LRU 计数器（单调递增；越大越新）
static uint64_t gNsUseCounter = 0;
// 命名空间总数上限（数据有界红线：会话不设上限但登记表有界——超限淘汰最久未用 dict，
// 被淘汰会话内存变量失效与「应用重启不恢复」同族口径，非静默数据损坏面）
static const size_t PY_NS_MAX = 32;

// stdout/stderr 收集上限（2171 修，自检轮 P2-9 报告处置）：字符数（Python len 口径，str
// 切片无 UTF-8 截点问题）。值量级依据：回执预算 5000 字符的 200 倍，覆盖任何 sane 分析输出
// （约 200 页 exec_output_read）；最坏 UTF-8 膨胀 4 字节/字符 = 4MB，恒低于溢出件单件写入
// 门 10MB（WorkspaceTmpUtil.WORKSPACE_TMP_MAX_FILE_BYTES——超门写入直接抛、落盘退化不完整），
// 该安全关系由 assert-py-runtime 2171-2 钉守。
static const int64_t PY_STREAM_CAP_CHARS = 1048576;

// 提交协作式中断（watchdog 与 cancel 共用）。持 GIL 调 SetAsyncExc（pystate.c 要求）：
// 专用 Python 线程正持 GIL 跑脚本，这里 Ensure 等 GIL——脚本按 switch interval（默认 5ms）
// 周期让出，毫秒级拿到；原生调用死握 GIL 时等不到（协作式边界，与「不承诺强杀」同口径）。
// 本路径的临时线程态不在专用线程上（2242 起），用完即删、无 pybind11 缓存面
static void SubmitInterrupt(uint64_t gen)
{
    if (Py_IsInitialized() == 0) {
        return;
    }
    if (gen != gExecGeneration.load()) {
        return; // 过期请求，静默丢弃
    }
    const unsigned long tid = gExecThreadId.load();
    if (tid == 0) {
        return; // 无在跑 exec（竞态窗口内刚结束）
    }
    const PyGILState_STATE gil = PyGILState_Ensure();
    const int rc = PyThreadState_SetAsyncExc(tid, PyExc_KeyboardInterrupt);
    PyGILState_Release(gil);
    if (rc != 1) {
        // rc=0 线程号无匹配（迟到窗口）；-1 内部异常（已清指示）——记录不阻断
        OH_LOG_WARN(LOG_APP, "pyengine SetAsyncExc rc=%{public}d (gen=%{public}llu tid=%{public}lu)",
            rc, static_cast<unsigned long long>(gen), tid);
    }
}

// ── 超时看门狗（每次 exec 一个；等结束信号或到点提交中断——条件变量等待，非轮询）──
struct PyWatchdogState {
    std::mutex mtx;
    std::condition_variable cv;
    bool done = false;             // 仅在锁内读写
    std::atomic<bool> timedOut{false}; // watchdog 线程写、exec 线程读——原子防数据竞争
};

static void WatchdogLoop(PyWatchdogState* state, int64_t timeoutMs, uint64_t gen)
{
    std::unique_lock<std::mutex> lk(state->mtx);
    const bool finished = state->cv.wait_for(lk, std::chrono::milliseconds(timeoutMs),
        [state] { return state->done; });
    lk.unlock();
    if (!finished) {
        state->timedOut = true;
        SubmitInterrupt(gen);
        OH_LOG_WARN(LOG_APP, "pyengine exec timeout, cooperative interrupt submitted (gen=%{public}llu)",
            static_cast<unsigned long long>(gen));
    }
}

// ── exec 收尾守卫（2171 修，自检轮 P1′ 报告处置；2242 笔随 A1 换放锁形态）──
// GIL 块内多处 C++ 分配可抛（巨型 stdout 拷贝的 bad_alloc 最现实）：栈展开会跳过块尾
// 放锁与函数尾看门狗 join——专用线程的主线程态永久滞留挂载态 + joinable 线程析构 =
// std::terminate 整进程崩（OnExecute 的 catch 兜不住：unwinding 先于 catch 杀进程）。守卫
// 析构兜异常路径：仍持 GIL 时先做与正常路径同款收尾清理（清悬挂异常 + 清 async_exc +
// 撤线程号）再放锁（SaveThread），然后置 done + join——join 必须收在放锁之后（watchdog 的
// SubmitInterrupt 持 GIL 调 SetAsyncExc，持 GIL join 等它 = 死锁面）。正常路径块尾显式
// 放锁并清 gilHeld，守卫只兜 join（正常/异常两路径单一 join 点，防双 join / 双释放）。
struct PyExecShutdownGuard {
    bool gilHeld = false;      // true = 主线程态仍挂在本线程（块尾或守卫析构负责摘下）
    unsigned long selfTid = 0; // GIL 内登记的投递目标（守卫兜清理用；0 = 登记前抛出）
    PyWatchdogState* watchdog = nullptr;
    std::thread* watchdogThread = nullptr;
    ~PyExecShutdownGuard()
    {
        if (gilHeld) {
            PyErr_Clear();
            if (selfTid != 0) {
                PyThreadState_SetAsyncExc(selfTid, nullptr);
            }
            gExecThreadId.store(0);
            gMainTstate = PyEval_SaveThread();
            gilHeld = false;
            OH_LOG_ERROR(LOG_APP, "pyengine exec unwound, guard released GIL");
        }
        if (watchdogThread != nullptr && watchdogThread->joinable()) {
            {
                std::lock_guard<std::mutex> lk(watchdog->mtx);
                watchdog->done = true;
            }
            watchdog->cv.notify_all();
            watchdogThread->join();
        }
    }
};

// ── 结果形态（与 d.ts / PyRuntime.ets 契约同步）──
struct PyInitOutcome {
    bool ok = false;
    std::string version;
    std::string error;
    int64_t elapsedMs = 0;
};

struct PyExecOutcome {
    bool ok = false;
    std::string stdoutText;
    std::string stderrText;
    std::string error; // 空 = 成功；PythonError/TimeoutError/Canceled = 脚本层失败；其余 = native 层中文句
    int64_t elapsedMs = 0;
    std::vector<std::string> savedNames; // save() 登记的待转存文件名（每轮读回即清）
    std::vector<std::string> audit;      // 本轮审计事件（__main__._pyAudit 读回即清）
};

// napi 取串（两段式：先取长再取内容——照 codeexec.cpp 同款）
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

// Python 字面量转义（路径嵌入引导串用：只处理反斜杠与双引号，其余字节原样——路径为
// UTF-8，PYTHONUTF8=1 下解释器按 UTF-8 源码解析）
static std::string EscapePyLiteral(const std::string& s)
{
    std::string out = "\"";
    for (char c : s) {
        if (c == '\\' || c == '"') {
            out.push_back('\\');
        }
        out.push_back(c);
    }
    out.push_back('"');
    return out;
}

// 取或建会话命名空间（调用面：gExecMutex + GIL 双持内）。返回借用引用（表持有所有权）。
// 空串键归 "default"（探针页两参调用形态）；新建时种 __builtins__（PyRun_String 虽会在
// globals 缺 __builtins__ 时自动补，显式种子消除对解释器内部行为的依赖）并注入 save()
// 登记函数；超 PY_NS_MAX 淘汰最久未用（淘汰即 DecRef，被淘汰会话变量失效）。
static PyObject* GetOrCreateNamespace(const std::string& sessionKeyRaw)
{
    const std::string key = sessionKeyRaw.empty() ? "default" : sessionKeyRaw;
    auto it = gNamespaces.find(key);
    if (it != gNamespaces.end()) {
        it->second.lastUse = ++gNsUseCounter;
        return it->second.dict;
    }
    PyObject* dict = PyDict_New();
    if (dict == nullptr) {
        PyErr_Clear();
        return nullptr;
    }
    PyObject* builtins = PyEval_GetBuiltins();
    if (builtins != nullptr) {
        PyDict_SetItemString(dict, "__builtins__", builtins); // 失败不致命（PyRun_String 会补）
        PyErr_Clear();
    }
    gNamespaces[key] = PyNamespaceRec{ dict, ++gNsUseCounter };
    if (gNamespaces.size() > PY_NS_MAX) {
        // LRU 淘汰：找 lastUse 最小的条目（新建项刚拿了最新计数，不会选中自己）
        auto victim = gNamespaces.begin();
        for (auto i = gNamespaces.begin(); i != gNamespaces.end(); ++i) {
            if (i->second.lastUse < victim->second.lastUse) {
                victim = i;
            }
        }
        OH_LOG_INFO(LOG_APP, "pyengine namespace LRU evict key=%{public}s", victim->first.c_str());
        Py_DecRef(victim->second.dict);
        gNamespaces.erase(victim);
    }
    return dict;
}

// ── init：解释器初始化（幂等）──
// 启动参数全套照 Guncat 实证（commander-notes「U4 pyengine 施工弹药」）：
// PYTHONHOME=homeDir、PYTHONUTF8=1、PYTHONDONTWRITEBYTECODE=1、PYTHONNOUSERSITE=1；
// libDir 由 dladdr(Py_InitializeEx) 反查 libpython 落点取得，不写死。
// ★ PYTHONPATH 五层（门 2 起四层，门 5 增 py-site 第五层；Guncat 铁则——纯 py 层永远在
//   lib 目录之前，否则 import 命中 lib 目录里只有 .so 的空壳目录）：
//   python313.zip : site-packages.zip : extras(真实目录) : py-site(自装包目录) : libDir
//   extras 由 PyRuntime.ets 首用解压（sitecustomize.py 的兜底 finder 把 libDir 里同名
//   子树接进扩展模块搜索路径——C 扩展包 .py 在 extras、.so 在 libDir 的双层合体）。
//   py-site（门 5 自装包层，PyPackages.ets）放纯 py 层末位 = 优先级最低不遮蔽预置包；
//   init 时目录可不存在（sys.path 对不存在目录无害），装包后同进程 import 即见（前提 =
//   安装器收尾 importlib.invalidate_caches——CPython 对不存在目录缓存 None finder 且不自愈）。
static PyInitOutcome InitializeInterpreter(const std::string& homeDir)
{
    // init 与 exec 共用互斥（串行初始化）：CPython 初始化非线程安全，并发 init 双双通过
    // Py_IsInitialized 检查后并发 Py_InitializeEx = UB；幂等快路径也在锁内复查（锁开销可忽略）
    std::lock_guard<std::mutex> initLock(gExecMutex);
    PyInitOutcome out;
    const auto started = std::chrono::steady_clock::now();
    out.elapsedMs = 0; // 结束时统一回填
    if (Py_IsInitialized() != 0) {
        out.ok = true;
        out.version = Py_GetVersion();
        return out;
    }
    // dladdr 反查 libpython 所在目录（应用 lib 目录绝对路径，真机形态 /data/app/.../libs/arm64）
    Dl_info info;
    std::string libDir;
    if (dladdr(reinterpret_cast<void*>(&Py_InitializeEx), &info) == 0 || info.dli_fname == nullptr) {
        out.error = "libpython 落点反查失败";
        return out;
    }
    std::string libPath(info.dli_fname);
    const size_t slash = libPath.find_last_of('/');
    if (slash == std::string::npos || slash == 0) {
        out.error = "libpython 落点路径异常";
        return out;
    }
    libDir = libPath.substr(0, slash);
    setenv("PYTHONHOME", homeDir.c_str(), 1);
    setenv("PYTHONPATH",
        (homeDir + "/python313.zip:" + homeDir + "/site-packages.zip:" + homeDir + "/extras:"
            + homeDir + "/py-site:" + libDir).c_str(), 1);
    setenv("PYTHONUTF8", "1", 1);
    setenv("PYTHONDONTWRITEBYTECODE", "1", 1);
    setenv("PYTHONNOUSERSITE", "1", 1);
    // 门 4 setenv 两项（闸②③ 真机发现，见文件头注释）
    setenv("MPLCONFIGDIR", (homeDir + "/mplconfig").c_str(), 1);
    // 证书候选序（2243 笔）：extras 随包 → 运行区根（兼容旧投放点）→ 系统目录。只设第一条
    // 命中的，三条全落空才 WARN；日志带实际命中路径，真机 ssl 报错可直接对 hilog。
    const std::string caCandidates[2] = {homeDir + "/extras/cert.pem", homeDir + "/cert.pem"};
    bool sslCaSet = false;
    for (const std::string& candidate : caCandidates) {
        if (access(candidate.c_str(), R_OK) == 0) {
            setenv("SSL_CERT_FILE", candidate.c_str(), 1);
            OH_LOG_INFO(LOG_APP, "pyengine SSL_CERT_FILE=%{public}s", candidate.c_str());
            sslCaSet = true;
            break;
        }
    }
    if (!sslCaSet) {
        if (access("/system/etc/security/cacerts", R_OK) == 0) {
            setenv("SSL_CERT_DIR", "/system/etc/security/cacerts", 1);
            OH_LOG_INFO(LOG_APP, "pyengine SSL_CERT_DIR=system");
        } else {
            OH_LOG_WARN(LOG_APP,
                "pyengine SSL env unset (no extras/cert.pem, no home cert.pem, no system cacerts)");
        }
    }
    OH_LOG_INFO(LOG_APP, "pyengine init home=%{public}s libdir=%{public}s", homeDir.c_str(), libDir.c_str());
    // Py_InitializeEx(0) = 不装信号处理（嵌入式宿主标准形态）。初始化失败时 CPython 走
    // Py_FatalError 直接终止进程（官方行为，无返回值可查——Guncat 同款裸调，不做防御）
    Py_InitializeEx(0);
    // 安全审计钩（减险可观测，方案 §5.5）：装在 __main__、事件进 _pyAudit（上限 50 条）。
    // 只记录不拦截——写模式 open / 网络五类事件；钩内全包 except 防打穿用户代码。
    // addaudithook 不可撤销且随进程存续（与解释器同生命周期，成对释放红线豁免面）。
    // 装在放锁之前：初始化后当前线程隐式持 GIL，不必再经 PyGILState 二次进出（2242 笔 A1）
    {
        const int rc = PyRun_SimpleString(
            "import sys as _pysys\n"
            "_pyAudit = []\n"
            "def _pyAuditHook(event, args):\n"
            "    try:\n"
            "        if event == 'open':\n"
            "            mode = args[1] if len(args) > 1 else ''\n"
            "            if isinstance(mode, str) and any(c in mode for c in ('w', 'a', 'x', '+')):\n"
            "                _pyAudit.append('write ' + repr(args[0])[:160])\n"
            "        elif event in ('socket.connect', 'socket.getaddrinfo', 'subprocess.Popen',"
            " 'os.system', 'ctypes.dlopen'):\n"
            "            _pyAudit.append(event + ' ' + repr(args)[:160])\n"
            "        if len(_pyAudit) > 50:\n"
            "            del _pyAudit[:-50]\n"
            "    except Exception:\n"
            "        pass\n"
            "_pysys.addaudithook(_pyAuditHook)\n");
        if (rc != 0) {
            PyErr_Clear(); // 审计钩失败不阻断解释器可用性（减险面降级 = 无安全记录，如实留痕）
            OH_LOG_WARN(LOG_APP, "pyengine audit hook install failed");
        }
    }
    // 放锁并挂起主线程态：gMainTstate 是专用线程的常驻线程态，此后每发 exec/drop 以
    // PyEval_RestoreThread/SaveThread 往返复用它（不建新态、不删除 ⇒ pybind11 在
    // internals.tstate_key 的缓存恒有效，见文件头「执行线程」条）。version 读取收在放锁
    // 之后（2171 修）：Py_GetVersion 只读静态串不需 GIL，而 std::string 构造可抛——持 GIL
    // 抛出 = 栈展开跳过 SaveThread、线程态永久挂载（exec 收尾守卫同族防线）
    gMainTstate = PyEval_SaveThread();
    out.version = Py_GetVersion();
    out.ok = true;
    out.elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - started).count();
    return out;
}

// 在会话 dict 内执行语句体（成功返回 true；结果引用即弃——PyRun_String 成功恒返新引用，
// 不 DecRef 会每发漏一枚引用；异常渲染与清除由调用方决定：引导失败印系统 stderr、用户
// 代码与收集失败印捕获 stderr）
static bool RunInNs(const std::string& code, PyObject* dict)
{
    PyObject* r = PyRun_String(code.c_str(), PY_FILE_INPUT, dict, dict);
    if (r == nullptr) {
        return false;
    }
    Py_DecRef(r);
    return true;
}

// 列表读回为 string vector（条目非 str 跳过——防御乱用；读完不改动原表）
static std::vector<std::string> ReadStringList(PyObject* list)
{
    std::vector<std::string> out;
    if (list == nullptr) {
        return out;
    }
    const Py_ssize_t n = PyList_Size(list);
    for (Py_ssize_t i = 0; i < n; ++i) {
        PyObject* item = PyList_GetItem(list, i); // 借用引用
        if (item == nullptr) {
            PyErr_Clear();
            continue;
        }
        const char* s = PyUnicode_AsUTF8(item);
        if (s != nullptr) {
            out.push_back(s);
        } else {
            PyErr_Clear();
        }
    }
    return out;
}

// ── exec：专用线程上执行（队列串行 + 会话命名空间 + 主线程态复用 + StringIO 捕获 + 看门狗）──
static PyExecOutcome RunPythonLocked(const std::string& code, int64_t timeoutMs,
    const std::string& sessionKey, const std::string& cwd)
{
    PyExecOutcome out;
    if (Py_IsInitialized() == 0) {
        out.error = "解释器未初始化";
        return out;
    }
    const auto started = std::chrono::steady_clock::now();
    // 真正的排队点在本函数外（RunTaskSync 的任务队列）；本锁保留作命名空间表与串行口径的
    // 守卫（三个入口都在专用线程上跑，锁恒无争用）
    std::unique_lock<std::mutex> execLock(gExecMutex);
    // 旗标清零必须在持锁后、取号前：排队期间用户 cancel 意图取消的是持锁中的前一发；
    // 若清零在拿锁前，本发排队时已把清零消费掉、持锁后带着过期旗标执行，会把自身的
    // PythonError 错标为 Canceled
    gCancelRequested.store(false);
    const uint64_t gen = gExecGeneration.fetch_add(1) + 1;
    // 看门狗在任务体内启动（排队时间不计入超时预算）
    PyWatchdogState watchdog;
    std::thread watchdogThread;
    if (timeoutMs > 0) {
        watchdogThread = std::thread(WatchdogLoop, &watchdog, timeoutMs, gen);
    }
    // 收尾守卫（2171 修）：GIL 释放与看门狗 join 的异常路径兜底（见结构体注释）；正常路径
    // 由块尾显式放锁 + 清 gilHeld 让守卫只兜 join
    PyExecShutdownGuard guard;
    guard.watchdog = &watchdog;
    guard.watchdogThread = &watchdogThread;
    {
        // 挂回专用线程的常驻主线程态（同一 tstate 跨轮复用，GIL 在此获取——见文件头
        // 「执行线程」条；不再用 PyGILState_Ensure 建临时态，那正是崩溃根因）
        PyEval_RestoreThread(gMainTstate);
        guard.gilHeld = true;
        // 登记本发线程号（SetAsyncExc 投递目标）+ 清开场残留：上一发 exec 结束后迟到的
        // 中断请求可能已把 async_exc 挂到本线程态（专用线程跨轮复用同一 tstate，残留指示器
        // 跟着复用），不清会开场即莫名 KeyboardInterrupt；exc=nullptr 为 API 的清除形态
        const unsigned long selfTid = PyThread_get_thread_ident();
        guard.selfTid = selfTid;
        PyThreadState_SetAsyncExc(selfTid, nullptr);
        gExecThreadId.store(selfTid);
        // 会话命名空间取建（LRU 命中刷新 lastUse；建失败 = 内存耗尽面，fail-fast）
        PyObject* nsDict = GetOrCreateNamespace(sessionKey);
        int bootRc = -1;
        int runRc = -1;
        int collectRc = -1;
        if (nsDict != nullptr) {
            // 引导串（全会话 dict 内执行）：捕获器换装 + save() 登记函数首用注入（'save'
            // not in globals() 判存——已注入的会话跨轮复用同一函数与登记表）
            const std::string boot =
                "import sys, io, os\n"
                "if 'save' not in globals():\n"
                "    _pySaved = []\n"
                "    def save(name):\n"
                "        _pySaved.append(os.path.basename(str(name)))\n"
                "_pyCapOut = io.StringIO()\n"
                "_pyCapErr = io.StringIO()\n"
                "sys.stdout = _pyCapOut\n"
                "sys.stderr = _pyCapErr\n";
            if (RunInNs(boot, nsDict)) {
                bootRc = 0;
            } else {
                PyErr_Print(); // 引导失败 = 环境损坏面，印系统 stderr 留诊断痕并清除
            }
        }
        // 工作目录显式设定（方案 §2.5：每轮执行前把 cwd 设为该次会话临时区——不依赖上轮
        // 进程 cwd 残留；cwd 空串 = 不动〔探针页形态〕）。chdir 失败 = 环境异常，如实报错
        if (bootRc == 0 && !cwd.empty()) {
            const std::string chdirCode = "import os\nos.chdir(" + EscapePyLiteral(cwd) + ")\n";
            if (!RunInNs(chdirCode, nsDict)) {
                PyErr_Print(); // 渲染进捕获 stderr（失败原因随回执可见）
                bootRc = -1;
            }
        }
        if (bootRc == 0) {
            if (RunInNs(code, nsDict)) {
                runRc = 0;
            } else {
                // 用户代码异常：渲染 traceback 进捕获 stderr 并清除（PyRun_String 不自印）
                PyErr_Print();
                runRc = -1;
            }
        }
        // 收集串：读回两个 StringIO 的值到会话 dict（异常残留已随 PyErr_Print 清除；中断
        // 落在收集串时 collectRc 非 0，输出丢失面由错误分类兜底）。带上限 PY_STREAM_CAP_CHARS
        // （2171 修）：保头截尾 + 溢出标记行（含总量与上限，模型可自判读回范围与是否需改用
        // 文件输出）；标记句内 len() 在赋值前求值 = 原始总量。
        if (bootRc == 0) {
            const std::string capStr = std::to_string(PY_STREAM_CAP_CHARS);
            const std::string collect =
                "_pyOut = sys.stdout.getvalue()\n"
                "if len(_pyOut) > " + capStr + ":\n"
                "    _pyOut = _pyOut[:" + capStr + "] + '\\n[stdout 共 ' + str(len(_pyOut)) +"
                " ' 字符，超过上限 " + capStr + "，只保留开头部分。]'\n"
                "_pyErr = sys.stderr.getvalue()\n"
                "if len(_pyErr) > " + capStr + ":\n"
                "    _pyErr = _pyErr[:" + capStr + "] + '\\n[stderr 共 ' + str(len(_pyErr)) +"
                " ' 字符，超过上限 " + capStr + "，只保留开头部分。]'\n";
            if (RunInNs(collect, nsDict)) {
                collectRc = 0;
            } else {
                PyErr_Print();
            }
        }
        // 会话 dict 取回输出与登记表（GetItemString 借用引用，不 DecRef）
        if (collectRc == 0 && nsDict != nullptr) {
            PyObject* outObj = PyDict_GetItemString(nsDict, "_pyOut");
            if (outObj != nullptr) {
                const char* s = PyUnicode_AsUTF8(outObj);
                if (s != nullptr) {
                    out.stdoutText = s;
                }
            }
            PyObject* errObj = PyDict_GetItemString(nsDict, "_pyErr");
            if (errObj != nullptr) {
                const char* s = PyUnicode_AsUTF8(errObj);
                if (s != nullptr) {
                    out.stderrText = s;
                }
            }
            PyErr_Clear(); // 取回异常清掉，不留悬挂
            // save() 登记表读回即清（下一轮从空表重新累计——跨轮不重复转存）
            PyObject* savedObj = PyDict_GetItemString(nsDict, "_pySaved");
            if (savedObj != nullptr) {
                out.savedNames = ReadStringList(savedObj);
                PyList_SetSlice(savedObj, 0, PyList_Size(savedObj), nullptr);
                PyErr_Clear();
            }
        }
        // 审计事件读回即清（__main__ 全局表——钩装在 __main__，与命名空间分家）
        PyObject* mainMod = PyImport_AddModule("__main__");
        if (mainMod != nullptr) {
            PyObject* auditObj = PyObject_GetAttrString(mainMod, "_pyAudit");
            if (auditObj != nullptr) {
                out.audit = ReadStringList(auditObj);
                PyList_SetSlice(auditObj, 0, PyList_Size(auditObj), nullptr);
                Py_DecRef(auditObj); // GetAttrString 新引用，用毕 DecRef
            }
            PyErr_Clear();
        }
        // 出 GIL 区前无条件清悬挂（覆盖各失败路径的残留异常）：任何悬挂异常带出 GIL 区会
        // 污染下次进入（专用线程跨轮复用同一线程态，残留异常指示器跟着复用）
        PyErr_Clear();
        // 收尾清 async_exc + 撤线程号（顺序固定）：watchdog 的整个生命周期在本发锁内
        // （放锁前 join），其迟到的 SetAsyncExc 落在本线程空闲态上不伤下一发；cancel 路
        // 径的 gen 比对取「当前代次」恒指正在跑的一发——两头的残留都由下一发开场清除兜底
        PyThreadState_SetAsyncExc(selfTid, nullptr);
        gExecThreadId.store(0);
        gMainTstate = PyEval_SaveThread();
        guard.gilHeld = false; // 正常路径已放锁，守卫只兜 join（不清 = 析构双释放）
        out.ok = (bootRc == 0) && (runRc == 0) && (collectRc == 0);
        if (!out.ok) {
            // 分类优先级 = 中断证据优先（2170 自检轮修）：超时/取消的协作中断若恰好落在
            // boot/chdir/collect 段，旧序会把它误报成「引导脚本失败/输出收集失败」，模型
            // 与用户都看不到超时与取消语义。timedOut 与 gCancelRequested 是本轮中断的
            // 直接证据，机械失败（boot/collect）只在无中断证据时才认。
            if (watchdog.timedOut.load()) {
                out.error = "TimeoutError";
            } else if (gCancelRequested.load()) {
                out.error = "Canceled";
            } else if (bootRc != 0) {
                out.error = "引导脚本失败";
            } else if (collectRc != 0 && runRc == 0) {
                out.error = "输出收集失败";
            } else {
                out.error = "PythonError"; // 脚本层失败，traceback 在 stderrText
            }
        }
    }
    // 看门狗 join 收进收尾守卫析构（2171 修：正常/异常两路径同一 join 点，序恒在放 GIL
    // 之后；先置 done 再 join——超时已发生的迟到通知无害）
    out.elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - started).count();
    return out;
}

// ── napi async work 载荷与回调 ──
struct PyWorkData {
    napi_deferred deferred = nullptr;
    napi_async_work work = nullptr;
    bool isInit = false;
    bool isDrop = false;
    std::string code;       // init: homeDir / exec: code
    std::string sessionKey; // exec 第三参（可空）
    std::string cwd;        // exec 第四参（可空）
    std::vector<std::string> dropKeys; // dropNamespaces 入参
    int64_t timeoutMs = 0;
    PyInitOutcome initOutcome;
    PyExecOutcome execOutcome;
};

static void OnExecute(napi_env env, void* data)
{
    PyWorkData* wd = static_cast<PyWorkData*>(data);
    (void)env;
    // C++ 异常屏障（照 codeexec 同款契约）：异常穿 napi 的 C 回调边界即 terminate。
    // 三入口都是「组任务 → 投递专用线程 → 等同」；任务内的 C++ 异常经 exception_ptr 回抛
    // 到这里统一折成中文回执（2242 笔 A1——本函数所在线程不再碰 Python 状态）
    try {
        if (wd->isInit) {
            PyTask task;
            task.run = [wd]() {
                wd->initOutcome = InitializeInterpreter(wd->code); // code 复用为 homeDir 载体
            };
            RunTaskSync(&task);
        } else if (wd->isDrop) {
            // 会话删除级联：释放命名空间引用（互斥 + 主线程态；键不存在 = 空操作）。
            // 解释器未初始化时任务体空转——不为此起解释器（与旧形态同口径）
            PyTask task;
            task.run = [wd]() {
                std::lock_guard<std::mutex> lk(gExecMutex);
                if (Py_IsInitialized() == 0) {
                    return;
                }
                PyEval_RestoreThread(gMainTstate);
                for (const std::string& key : wd->dropKeys) {
                    auto it = gNamespaces.find(key);
                    if (it != gNamespaces.end()) {
                        Py_DecRef(it->second.dict);
                        gNamespaces.erase(it);
                    }
                }
                PyErr_Clear();
                gMainTstate = PyEval_SaveThread();
            };
            RunTaskSync(&task);
        } else {
            PyTask task;
            task.run = [wd]() {
                wd->execOutcome =
                    RunPythonLocked(wd->code, wd->timeoutMs, wd->sessionKey, wd->cwd);
            };
            RunTaskSync(&task);
        }
    } catch (...) {
        OH_LOG_ERROR(LOG_APP, "pyengine work threw, fallback to error receipt");
        if (wd->isInit) {
            wd->initOutcome.error = "执行内存不足";
        } else if (!wd->isDrop) {
            wd->execOutcome.error = "执行内存不足";
        }
    }
}

static void OnComplete(napi_env env, napi_status status, void* data)
{
    PyWorkData* wd = static_cast<PyWorkData*>(data);
    napi_value result = nullptr;
    napi_create_object(env, &result);
    auto setBool = [&](const char* key, bool v) {
        napi_value val = nullptr;
        napi_get_boolean(env, v, &val);
        napi_set_named_property(env, result, key, val);
    };
    auto setString = [&](const char* key, const std::string& v) {
        napi_value val = nullptr;
        napi_create_string_utf8(env, v.c_str(), v.size(), &val);
        napi_set_named_property(env, result, key, val);
    };
    auto setInt64 = [&](const char* key, int64_t v) {
        napi_value val = nullptr;
        napi_create_int64(env, v, &val);
        napi_set_named_property(env, result, key, val);
    };
    auto setStringArray = [&](const char* key, const std::vector<std::string>& v) {
        napi_value arr = nullptr;
        napi_create_array_with_length(env, v.size(), &arr);
        for (size_t i = 0; i < v.size(); ++i) {
            napi_value item = nullptr;
            napi_create_string_utf8(env, v[i].c_str(), v[i].size(), &item);
            napi_set_element(env, arr, i, item);
        }
        napi_set_named_property(env, result, key, arr);
    };
    if (wd->isInit) {
        setBool("ok", wd->initOutcome.ok);
        setString("version", wd->initOutcome.version);
        setString("error", wd->initOutcome.error);
        setInt64("elapsedMs", wd->initOutcome.elapsedMs);
    } else if (wd->isDrop) {
        setBool("ok", true);
    } else {
        setBool("ok", wd->execOutcome.ok);
        setString("stdout", wd->execOutcome.stdoutText);
        setString("stderr", wd->execOutcome.stderrText);
        setString("error", wd->execOutcome.error);
        setInt64("elapsedMs", wd->execOutcome.elapsedMs);
        setStringArray("savedNames", wd->execOutcome.savedNames);
        setStringArray("audit", wd->execOutcome.audit);
    }
    if (status == napi_ok) {
        napi_resolve_deferred(env, wd->deferred, result);
    } else {
        napi_value undefined = nullptr;
        napi_get_undefined(env, &undefined);
        napi_reject_deferred(env, wd->deferred, undefined);
    }
    napi_delete_async_work(env, wd->work);
    delete wd;
}

// init(homeDir) / exec(code, timeoutMs, sessionKey?, cwd?)（异步——返回 Promise）
static napi_value StartWork(napi_env env, napi_callback_info info, bool isInit)
{
    size_t argc = 4;
    napi_value argv[4] = { nullptr };
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok ||
        argc < (isInit ? 1u : 2u)) {
        napi_throw_type_error(env, nullptr,
            isInit ? "init 需要一个 homeDir 字符串参数" : "exec 需要 code 与 timeoutMs 两个参数");
        return nullptr;
    }
    std::string code;
    std::string sessionKey;
    std::string cwd;
    double timeoutRaw = 0;
    // 主线程异常屏障（照 codeexec 同款：分配可抛 bad_alloc，转 napi 抛错而非崩溃）
    try {
        if (!napiReadString(env, argv[0], code)) {
            napi_throw_type_error(env, nullptr,
                isInit ? "init 的 homeDir 必须是字符串" : "exec 的 code 必须是字符串");
            return nullptr;
        }
        if (!isInit) {
            if (napi_get_value_double(env, argv[1], &timeoutRaw) != napi_ok || timeoutRaw < 0) {
                napi_throw_type_error(env, nullptr, "exec 的 timeoutMs 必须是非负数");
                return nullptr;
            }
            // 第三/四参可选（探针页两参调用形态兼容）；给了就必须是字符串
            if (argc >= 3 && !napiReadString(env, argv[2], sessionKey)) {
                napi_throw_type_error(env, nullptr, "exec 的 sessionKey 必须是字符串");
                return nullptr;
            }
            if (argc >= 4 && !napiReadString(env, argv[3], cwd)) {
                napi_throw_type_error(env, nullptr, "exec 的 cwd 必须是字符串");
                return nullptr;
            }
        }
    } catch (...) {
        OH_LOG_ERROR(LOG_APP, "pyengine start work threw (parsing)");
        napi_throw_error(env, nullptr, "内存不足，无法发起请求");
        return nullptr;
    }
    napi_deferred deferred = nullptr;
    napi_value promise = nullptr;
    napi_create_promise(env, &deferred, &promise);
    PyWorkData* wd = nullptr;
    try {
        wd = new PyWorkData();
        wd->deferred = deferred;
        wd->isInit = isInit;
        wd->code = std::move(code);
        wd->sessionKey = std::move(sessionKey);
        wd->cwd = std::move(cwd);
        wd->timeoutMs = static_cast<int64_t>(timeoutRaw);
    } catch (...) {
        OH_LOG_ERROR(LOG_APP, "pyengine start work threw (alloc)");
        delete wd;
        napi_throw_error(env, nullptr, "内存不足，无法发起请求");
        return nullptr;
    }
    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, isInit ? "pyengineInit" : "pyengineExec", NAPI_AUTO_LENGTH,
        &resourceName);
    if (napi_create_async_work(env, nullptr, resourceName, OnExecute, OnComplete, wd,
        &wd->work) != napi_ok ||
        napi_queue_async_work(env, wd->work) != napi_ok) {
        // 创建/排队失败兜底（照 codeexec 同款：resolve 失败形态 + 清理，禁 deferred 悬挂）
        OH_LOG_ERROR(LOG_APP, "pyengine create/queue async work failed");
        napi_value fallback = nullptr;
        napi_create_object(env, &fallback);
        napi_value errVal = nullptr;
        napi_value okVal = nullptr;
        napi_value emptyVal = nullptr;
        napi_value elapsedVal = nullptr;
        napi_value emptyArr = nullptr;
        napi_get_boolean(env, false, &okVal);
        napi_create_string_utf8(env, "异步任务创建失败", NAPI_AUTO_LENGTH, &errVal);
        napi_create_string_utf8(env, "", NAPI_AUTO_LENGTH, &emptyVal);
        napi_create_int64(env, 0, &elapsedVal);
        napi_create_array(env, &emptyArr);
        napi_set_named_property(env, fallback, "ok", okVal);
        napi_set_named_property(env, fallback, isInit ? "version" : "stdout", emptyVal);
        // 契约补齐（2170 自检轮修）：PyInitResult/PyExecResult 均含 elapsedMs；exec 形态还含
        // stderr 与 savedNames/audit——缺项会让 ArkTS 侧读 undefined（promote 链 / audit 展开抛）
        napi_set_named_property(env, fallback, "elapsedMs", elapsedVal);
        if (!isInit) {
            napi_set_named_property(env, fallback, "stderr", emptyVal);
            napi_set_named_property(env, fallback, "savedNames", emptyArr);
            napi_set_named_property(env, fallback, "audit", emptyArr);
        }
        napi_set_named_property(env, fallback, "error", errVal);
        napi_resolve_deferred(env, deferred, fallback);
        if (wd->work != nullptr) {
            napi_delete_async_work(env, wd->work);
        }
        delete wd;
        return promise;
    }
    return promise;
}

// dropNamespaces(keys)（异步——返回 Promise<ok>；会话删除级联 best-effort 调用）
static napi_value DropNamespacesEntry(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = { nullptr };
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 1) {
        napi_throw_type_error(env, nullptr, "dropNamespaces 需要一个字符串数组参数");
        return nullptr;
    }
    bool isArray = false;
    std::vector<std::string> keys;
    if (napi_is_array(env, argv[0], &isArray) != napi_ok || !isArray) {
        napi_throw_type_error(env, nullptr, "dropNamespaces 的参数必须是字符串数组");
        return nullptr;
    }
    uint32_t len = 0;
    napi_get_array_length(env, argv[0], &len);
    for (uint32_t i = 0; i < len; ++i) {
        napi_value item = nullptr;
        std::string key;
        if (napi_get_element(env, argv[0], i, &item) == napi_ok && napiReadString(env, item, key)) {
            keys.push_back(std::move(key));
        }
    }
    napi_deferred deferred = nullptr;
    napi_value promise = nullptr;
    napi_create_promise(env, &deferred, &promise);
    PyWorkData* wd = nullptr;
    try {
        wd = new PyWorkData();
        wd->deferred = deferred;
        wd->isDrop = true;
        wd->dropKeys = std::move(keys);
    } catch (...) {
        OH_LOG_ERROR(LOG_APP, "pyengine drop alloc threw");
        delete wd;
        napi_throw_error(env, nullptr, "内存不足，无法发起请求");
        return nullptr;
    }
    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "pyengineDrop", NAPI_AUTO_LENGTH, &resourceName);
    if (napi_create_async_work(env, nullptr, resourceName, OnExecute, OnComplete, wd,
        &wd->work) != napi_ok ||
        napi_queue_async_work(env, wd->work) != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "pyengine drop create/queue async work failed");
        napi_value fallback = nullptr;
        napi_create_object(env, &fallback);
        napi_value okVal = nullptr;
        napi_get_boolean(env, true, &okVal); // 释放失败不影响删除会话主流程（best-effort）
        napi_set_named_property(env, fallback, "ok", okVal);
        napi_resolve_deferred(env, deferred, fallback);
        if (wd->work != nullptr) {
            napi_delete_async_work(env, wd->work);
        }
        delete wd;
        return promise;
    }
    return promise;
}

static napi_value InitInterpreterEntry(napi_env env, napi_callback_info info)
{
    return StartWork(env, info, true);
}

static napi_value ExecEntry(napi_env env, napi_callback_info info)
{
    return StartWork(env, info, false);
}

// cancel()（协作式：置旗标 + 对当前代次投递 SetAsyncExc；无 exec 在跑时线程号为 0、
// gen/tid 比对落空自然丢弃——不承诺中断正在跑的原生调用）
static napi_value CancelEntry(napi_env env, napi_callback_info info)
{
    (void)info;
    gCancelRequested.store(true);
    const uint64_t gen = gExecGeneration.load();
    SubmitInterrupt(gen);
    OH_LOG_INFO(LOG_APP, "pyengine cancel requested (gen=%{public}llu)",
        static_cast<unsigned long long>(gen));
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

// 模块注册（官方范式：constructor 自动注册——照 codeexec.cpp 同款）
EXTERN_C_START
static napi_value InitModule(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "init", nullptr, InitInterpreterEntry, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "exec", nullptr, ExecEntry, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "cancel", nullptr, CancelEntry, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "dropNamespaces", nullptr, DropNamespacesEntry, nullptr, nullptr, nullptr, napi_default,
            nullptr }
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module pyengineModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = InitModule,
    .nm_modname = "pyengine",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterPyengineModule(void)
{
    napi_module_register(&pyengineModule);
}
