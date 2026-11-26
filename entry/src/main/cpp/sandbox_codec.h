// 沙箱纯数据编解码桥（2026-10-06 代码工作台笔A——二进制与基座，任务书 §3.5/§3.6）。
// · 职责：zlib 压缩解压 + 摘要 hex 化——**零 JSVM 依赖**（与 sandbox_hostapi.cpp 的职责缝：
//   这里出纯 C++ 结果结构，那边转 JS 值与 JS 异常）。
// · 实现选型（宪法三级选型①官方优先）：压缩解压 = 系统 zlib（libz.so，sysroot 自带
//   1.3.1——官方 NDK 依赖面）；摘要 = CryptoArchitectureKit NDK（libohcrypto.so 的
//   OH_CryptoDigest_*，@since 12）——算法不手写。
// · 限额纪律（A4 同族）：本文件**禁出现任何限额字面值**——桥输入与解压输出上限一律经
//   参数下传（值来自 ScriptRunOptions 的临时区单件闸，§4.5）。
// · 成对释放：inflateInit ↔ inflateEnd、OH_CryptoDigest_Create ↔ OH_DigestCrypto_Destroy、
//   OH_CryptoDigest_Final 输出 ↔ OH_Crypto_FreeDataBlob——三对在全部失败路径同样成立。
#ifndef CODEEXEC_SANDBOX_CODEC_H
#define CODEEXEC_SANDBOX_CODEC_H

#include <cstddef>
#include <string>

// 失败分类（hostapi 侧据此映射错误名：限额类 → FenceError；数据类 / 内部类 → ZlibError
// 或 DigestError——§4.4 错误形态表）
enum SandboxCodecErrKind {
    SANDBOX_CODEC_ERR_LIMIT = 0,    // 限额类（输入或解压输出超下传闸）
    SANDBOX_CODEC_ERR_DATA = 1,     // 数据类（压缩内容非法）
    SANDBOX_CODEC_ERR_INTERNAL = 2  // 内部类（内存 / NDK 调用失败）
};

struct SandboxCodecResult {
    bool ok = false;
    std::string data;    // 成功时：压缩 / 解压后的字节，或摘要的小写 hex
    int errorKind = SANDBOX_CODEC_ERR_INTERNAL; // 失败时生效
    std::string reason;  // 失败时：中文原因（FenceError 前缀「临时区限制」由本层拼好）
};

// zlib 压缩（RFC1950 zlib 包装，级别 Z_DEFAULT_COMPRESSION；funcName 供闸错误句自述）
SandboxCodecResult sandboxZlibCompress(const std::string& input, size_t maxInBytes,
    const char* funcName);

// zlib 解压（流式 inflate，输出缓冲翻倍增长、每次增长前查 maxOutBytes；gzip / raw
// deflate 不支持——只认 zlib 包装，§1.5-5）
SandboxCodecResult sandboxZlibDecompress(const std::string& input, size_t maxInBytes,
    size_t maxOutBytes, const char* funcName);

// 摘要（algoName = 宿主函数名小写 md5/sha1/sha256——内部经 digestOfficialName 映射为官方
// 大写算法名；输出小写 hex。algoName 同时供闸错误句自述——与宿主函数名小写同形）
SandboxCodecResult sandboxDigestHex(const char* algoName, const std::string& input,
    size_t maxInBytes);

#endif // CODEEXEC_SANDBOX_CODEC_H
