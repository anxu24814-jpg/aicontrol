# 代码工作台 native 模块（2026-10-05 端侧代码工作台笔——工程首例 native 层，
# 任务书-端侧代码工作台-20260914 §3.1）：JSVM 沙箱执行桥。
# · 链接库全部来自系统（libjsvm.so 来自 SDK sysroot、libace_napi.z.so 供 napi、
#   libhilog_ndk.z.so 供日志、libz.so 供 zlib、libohcrypto.so 供 CryptoArchitectureKit
#   摘要 NDK——★ 2026-10-06 代码工作台笔A 扩容后两源，均 sysroot 自带）——不开 JIT
#   （零新权限红线）。★ 2026-11-06 鸿蒙Python运行时门1笔改写「不打包任何自带 .so」
#   旧口径：pyengine 目标运行时依赖 entry/libs/arm64-v8a 的 libpython3.13.so（+49 枚
#   C 扩展与 libz.so，随包分发——Guncat 实证 hvigor 收该目录 .so）；CMake 只取链接
#   期符号（-L 指向该目录），不安装、不收包，自带 .so 落包仍唯一走 entry/libs 目录。
# · 源件分域（笔A 拆分，§3.0）：codeexec.cpp = napi 入口 / jsvm_runner.cpp = 执行主
#   流程 / sandbox_hostapi.cpp = 宿主回调层 / sandbox_fs.cpp = 文件域 / sandbox_codec.cpp
#   = zlib 与摘要桥 / sandbox_http.cpp = 沙箱网络桥（笔E——跨线程机制件，零 JSVM 依赖）。
# · 引擎独立红线（任务书 A8；★ 2026-10-06 代码工作台笔F 按其书 §8-2 拍板澄清为
#   「二进制独立」并兑现）：第二引擎 QuickJS = 下方 qjsengine 目标（独立 so）——两目标
#   禁互相 target_link_libraries、禁 dlopen 互载（运行期互不拖垮）；共享源
#   （sandbox_fs.cpp / sandbox_codec.cpp / sandbox_prelude.h）各自编入各自 so =
#   「编译副本」口径，fs 与编解码语义单源不漂移（回执等价的前提）。
# · ★P0 安全红线（笔F 任务书 §0.0 置顶）：qjsengine 源清单**永不含 quickjs-libc.c 与
#   任何 std/os 模块载体**——不编即不存在；vendor 目录（quickjs/）物理不含该两文件，
#   全工程零 js_init_module_std / js_init_module_os 调用（断言钉守）。
cmake_minimum_required(VERSION 3.5.0)
project(codeexec)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

include_directories(${NATIVERENDER_ROOT_PATH})
# QuickJS 头在 vendor 子目录——qjs 侧 C++ 以 #include "quickjs/quickjs.h" 子目录限定
# 引用（勿把 quickjs/ 加进 include 路径：Windows 大小写不敏感文件系统下标准库 <version>
# 头会误命中 vendor 的 VERSION 文件——实测坑，勿回填 -I 写法）

add_library(codeexec SHARED
    codeexec.cpp
    jsvm_runner.cpp
    sandbox_fs.cpp
    sandbox_codec.cpp
    sandbox_hostapi.cpp
    sandbox_http.cpp)

# 日志宏自目录级下发放缩为目标级（笔F：同目录两目标各自 tag，目录级 add_definitions 会串味）
target_compile_definitions(codeexec PRIVATE "-DLOG_DOMAIN=0x0C0E" "-DLOG_TAG=\"codeexec\"")

target_link_libraries(codeexec PUBLIC libace_napi.z.so libjsvm.so libhilog_ndk.z.so
    libz.so libohcrypto.so)

# ── QuickJS 第二引擎（2026-10-06 代码工作台笔F，任务书-代码工作台笔F-QuickJS第二引擎
#    -20261006 §3.0：严格档执行引擎——可中断超时 + 真取消；独立目标独立 so）──
# 源清单 = 官方 2026-06-04 裁剪版（quickjs/ 五 .c，照官方 Makefile QJS_LIB_OBJS 除
# quickjs-libc 外全收）+ 本工程四件（桥/执行器/宿主层/网络桥）+ 共享编译副本两件；
# 不链 libjsvm（引擎面互不依赖）。CONFIG_VERSION 照官方 Makefile 下传；libm 供
# dtoa/数学符号（sysroot libm.a）。
add_library(qjsengine SHARED
    qjs_engine.cpp
    qjs_runner.cpp
    qjs_hostapi.cpp
    qjs_http.cpp
    sandbox_fs.cpp
    sandbox_codec.cpp
    quickjs/quickjs.c
    quickjs/libregexp.c
    quickjs/libunicode.c
    quickjs/cutils.c
    quickjs/dtoa.c)

target_compile_definitions(qjsengine PRIVATE "-DLOG_DOMAIN=0x0C0E"
    "-DLOG_TAG=\"qjsengine\"" "-D_GNU_SOURCE" "-DCONFIG_VERSION=\"2026-06-04\"")

target_link_libraries(qjsengine PUBLIC libace_napi.z.so libhilog_ndk.z.so
    libz.so libohcrypto.so m)

# ── Python 解释器引擎（2026-11-06 鸿蒙Python运行时门1笔，任务书-鸿蒙Python运行时门0门1
#    -20261106 U4：进程内嵌 CPython 3.13.18——init/exec/cancel 三入口，实现与生命周期
#    口径见 pyengine/PyEngine.cpp 头注释）──
# 二进制独立红线沿用：不与 codeexec/qjsengine 互相 target_link_libraries、禁 dlopen 互载。
# libpython3.13.so 不随 CMake 安装/收包：链接期 -L 指向 entry/libs/arm64-v8a 取符号（目标
# 源树相对路径 cpp → entry 为 ../../../libs/arm64-v8a），运行期由系统 linker 从应用 lib
# 目录解析 DT_NEEDED（产物随 HAP libs/arm64-v8a 分发，见本文件头注释改写立账）。
add_library(pyengine SHARED
    pyengine/PyEngine.cpp)

target_compile_definitions(pyengine PRIVATE "-DLOG_DOMAIN=0x0C0E" "-DLOG_TAG=\"pyengine\"")

target_link_directories(pyengine PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/arm64-v8a)

target_link_libraries(pyengine PUBLIC libace_napi.z.so libhilog_ndk.z.so python3.13)

# ── Node.js 运行时引擎（2026-11-23 鸿蒙Node运行时门1笔，任务书-鸿蒙Node运行时门1-20261121
#    U3：进程内嵌 libnode.so——dlopen 形态，不链 libnode）──
# 二进制独立红线沿用：不与 codeexec/qjsengine/pyengine 互相 target_link_libraries、禁 dlopen
# 互载。与 pyengine 的差异：libpython 走链接期 -L 取符号（DT_NEEDED 由系统 linker 从应用
# lib 目录解析），libnode 走运行期 dlopen（绝对路径 = dladdr 反查自身 so 目录拼 libnode.so，
# 见 NodeEngine.cpp 头注释）——故本目标零 -L libs 行、零 libnode 链接，只链 napi/hilog。
# include 树（cpp/nodeengine/include/，门 0 产物 include-embed 解包 tree，sha256 对
# scripts/node-runtime/manifest.json 的 artifacts.include-embed.tar.gz）随仓 vendored 但
# **当前不进 include 路径**：Node 自带 napi 头与 OHOS SDK napi/native_api.h 冲突，本单元改
# 用最小 extern 声明（NodeEngine.cpp 头注释「node::Start 最小声明」节，指挥复核裁定）；
# 门 2 消费树时另立编译单元按需接三根。
add_library(nodeengine SHARED
    nodeengine/NodeEngine.cpp)

target_compile_definitions(nodeengine PRIVATE "-DLOG_DOMAIN=0x0C0E" "-DLOG_TAG=\"nodeengine\"")

target_link_libraries(nodeengine PUBLIC libace_napi.z.so libhilog_ndk.z.so)
