// QuickJS 沙箱宿主 API 回调层共享载体（2026-10-06 代码工作台笔F——QuickJS 第二引擎；
// 形态对照件 = sandbox_hostapi.h，二进制独立禁代码级共享，任务书 §8-2）。
// · 注入面契约：与 jsvm 侧**同名同语义**（console.log/warn/error + result + fs 七方法
//   {list/read/readBytes/write/append/exists/save} + 五 codec 桥 {zlibCompress/
//   zlibDecompress/md5/sha1/sha256} + 网络桥 httpGet）——同一沙箱的能力不随档位分叉
//   （任务书 §3.7 尾注），断言关系钉守两引擎注入名集合全等。
// · 状态传递形态（★ 2026-10-20 并发笔，方案 §R U3——原文件级静态指针
//   gQjsCurrentState 退役）：运行态经 **JS_SetContextOpaque 挂在 ctx 上**——K 路并发
//   各 ctx 各态互不可见；qjs_runner 在 NewContext 后、安装宿主面前挂入（opaque 先于
//   任何宿主回调可达），回调经 QjsStateOf(ctx) 取态；微任务路径单 context 下 jobCtx
//   即本 ctx，opaque 同源。
// · 头文件依赖单向（坑50 同款）：本件引 qjs_runner.h 与 sandbox_fs.h / sandbox_codec.h
//   （共享编译副本）；qjs_runner.h 不引本件。
#ifndef CODEEXEC_QJS_HOSTAPI_H
#define CODEEXEC_QJS_HOSTAPI_H

#include <string>
#include <vector>

#include "quickjs/quickjs.h"
#include "qjs_runner.h"

// 每次执行的运行态（宿主回调读写；qjs_runner 主流程消费）
struct QjsRunState {
    explicit QjsRunState(const QjsRunOptions& o) : opts(o) {}

    const QjsRunOptions& opts;
    std::string resultValue;    // result(v) 序列化快照（覆盖式，最后一次生效）
    bool resultSet = false;
    std::vector<std::string> logs;
    size_t logsBudget = 0;      // 剩余日志预算（字节）——收集面口径照 jsvm 侧
    size_t logsMaxLines = 0;    // 日志条数上限（下传；0 = 不限）
    bool logsTruncated = false;
    std::vector<std::string> savedNames; // fs.save 登记（落库编排在 ArkTS 侧）

    // ★ 2026-10-20 并发笔（方案 §R U3）：per-run 取消块（非拥有——qjs_engine.cpp 建/
    // 注销，qjs_runner 挂载；HostHttpGet 受理前检查读本块；空 = 裸调形态按不可取消）
    QjsCancelBlock* cancelBlock = nullptr;
    // 本 run 取消目标键（自 opts；网络桥投递载荷随带——桥侧 per-run 槽键的 native 源）
    std::string runKey;
};

// JSValue(string) → std::string（异常自清返空串）
std::string qjsValueToUtf8(JSContext* ctx, JSValueConst v);

// 值序列化（与 jsvm 侧 serializeJsValue 同语义）：string 原样；undefined / null 特值；
// 其余 JS_JSONStringify（失败清异常降级 JS_ToCString——带抛异常 toString 的对象回空串）
std::string qjsSerializeJsValue(JSContext* ctx, JSValueConst v);

// 宿主面安装（console 三成员 + result + fs 七方法对象 + 六全局桥函数——与 jsvm 侧
// InstallSandboxHostApi 同集合；不注入 fetch/XMLHttpRequest/require/setTimeout，
// import 引擎本就无模块语义——负向钉守）
void QjsInstallHostApi(JSContext* ctx);

#endif // CODEEXEC_QJS_HOSTAPI_H
