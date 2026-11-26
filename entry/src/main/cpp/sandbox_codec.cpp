// 沙箱纯数据编解码桥实现（头注释见 sandbox_codec.h；zlib.h / crypto_digest.h 签名以
// 本机 SDK sysroot 实读为准——zlib 1.3.1，CryptoArchitectureKit @since 12）
#include "sandbox_codec.h"

#include <zlib.h>
#include <CryptoArchitectureKit/crypto_common.h>
#include <CryptoArchitectureKit/crypto_digest.h>

#include <cstdint>
#include <cstring>

// 闸值格式化（与 sandbox_fs 的 byteSizeText 同句式——两处各自 static，职责缝独立不共享）
static std::string byteText(size_t bytes)
{
    return std::to_string(bytes) + " 字节";
}

SandboxCodecResult sandboxZlibCompress(const std::string& input, size_t maxInBytes,
    const char* funcName)
{
    SandboxCodecResult result;
    if (input.size() > maxInBytes) {
        result.errorKind = SANDBOX_CODEC_ERR_LIMIT;
        result.reason = std::string("临时区限制：") + funcName + " 的输入 " +
            byteText(input.size()) + " 超过单件上限 " + byteText(maxInBytes);
        return result;
    }
    // 目标缓冲按 compressBound 预留（输入已受闸 → 峰值有界）
    const uLongf bound = compressBound(static_cast<uLong>(input.size()));
    std::string out(static_cast<size_t>(bound), '\0');
    uLongf destLen = bound;
    const int zr = compress2(reinterpret_cast<Bytef*>(&out[0]), &destLen,
        reinterpret_cast<const Bytef*>(input.data()), static_cast<uLong>(input.size()),
        Z_DEFAULT_COMPRESSION);
    if (zr == Z_OK) {
        out.resize(destLen);
        result.ok = true;
        result.data = std::move(out);
        return result;
    }
    result.errorKind = (zr == Z_MEM_ERROR) ? SANDBOX_CODEC_ERR_INTERNAL :
        SANDBOX_CODEC_ERR_DATA;
    result.reason = std::string(funcName) + " 失败：内部错误";
    return result;
}

SandboxCodecResult sandboxZlibDecompress(const std::string& input, size_t maxInBytes,
    size_t maxOutBytes, const char* funcName)
{
    SandboxCodecResult result;
    if (input.size() > maxInBytes) {
        result.errorKind = SANDBOX_CODEC_ERR_LIMIT;
        result.reason = std::string("临时区限制：") + funcName + " 的输入 " +
            byteText(input.size()) + " 超过单件上限 " + byteText(maxInBytes);
        return result;
    }
    z_stream strm;
    std::memset(&strm, 0, sizeof(strm));
    strm.next_in = reinterpret_cast<Bytef*>(const_cast<char*>(input.data()));
    strm.avail_in = static_cast<uInt>(input.size());
    if (inflateInit(&strm) != Z_OK) {
        result.errorKind = SANDBOX_CODEC_ERR_INTERNAL;
        result.reason = std::string(funcName) + " 失败：内部错误";
        return result;
    }
    // 输出缓冲翻倍增长，每次增长前查上限（上限 = 单件闸下传值，§4.5）
    size_t cap = 64 * 1024 > maxOutBytes ? maxOutBytes : 64 * 1024;
    if (cap == 0) {
        cap = 1;
    }
    std::string out(cap, '\0');
    size_t used = 0;
    bool done = false;
    while (true) {
        strm.next_out = reinterpret_cast<Bytef*>(&out[used]);
        strm.avail_out = static_cast<uInt>(cap - used);
        const int zr = inflate(&strm, Z_NO_FLUSH);
        used = cap - strm.avail_out;
        if (zr == Z_STREAM_END) {
            done = true;
            break;
        }
        if (zr == Z_OK || zr == Z_BUF_ERROR) {
            if (strm.avail_out == 0) {
                // 输出空间耗尽——扩容前查上限；已到顶即限额类
                if (cap >= maxOutBytes) {
                    inflateEnd(&strm);
                    result.errorKind = SANDBOX_CODEC_ERR_LIMIT;
                    result.reason = "临时区限制：解压结果超过单件上限 " +
                        byteText(maxOutBytes);
                    return result;
                }
                size_t next = cap * 2;
                if (next > maxOutBytes || next < cap) {
                    next = maxOutBytes;
                }
                cap = next;
                out.resize(cap);
                continue;
            }
            if (strm.avail_in == 0) {
                // 输入耗尽仍未见流尾——截断 / 非法的压缩内容（Z_BUF_ERROR 无进展）
                break;
            }
            continue;
        }
        // Z_DATA_ERROR（内容非法）与其余（Z_MEM_ERROR 等）
        inflateEnd(&strm);
        result.errorKind = (zr == Z_DATA_ERROR) ? SANDBOX_CODEC_ERR_DATA :
            SANDBOX_CODEC_ERR_INTERNAL;
        result.reason = (zr == Z_DATA_ERROR) ?
            std::string(funcName) + " 失败：数据不是有效的压缩内容" :
            std::string(funcName) + " 失败：内部错误";
        return result;
    }
    inflateEnd(&strm);
    if (!done) {
        result.errorKind = SANDBOX_CODEC_ERR_DATA;
        result.reason = std::string(funcName) + " 失败：数据不是有效的压缩内容";
        return result;
    }
    out.resize(used);
    result.ok = true;
    result.data = std::move(out);
    return result;
}

// 官方 NDK 算法名映射（★ 2026-10-06 真机缺陷修复，P1）：CryptoArchitectureKit 的
// MD_ABILITY_SET 表只有大写条目（"MD5" / "SHA1" / "SHA256"），FindAbility 用 strcmp
// **大小写敏感**精确匹配（security_crypto_framework 源码实读，6.0-Release 分支同）——
// 传脚本函数名小写恒 CRYPTO_INVALID_PARAMS（原实装小写直传，三桥必然全灭且误报「内部
// 错误」诱导模型怀疑脚本）。对外函数名保持小写（脚本调用面），本函数是算法名与函数名的
// 唯一分离点；错误句仍用小写函数名（模型按调用名对号）。
static const char* digestOfficialName(const char* funcName)
{
    if (std::strcmp(funcName, "md5") == 0) {
        return "MD5";
    }
    if (std::strcmp(funcName, "sha1") == 0) {
        return "SHA1";
    }
    if (std::strcmp(funcName, "sha256") == 0) {
        return "SHA256";
    }
    return funcName; // 理论不可达（三桥调用点全表，无第四名）
}

SandboxCodecResult sandboxDigestHex(const char* algoName, const std::string& input,
    size_t maxInBytes)
{
    SandboxCodecResult result;
    if (input.size() > maxInBytes) {
        result.errorKind = SANDBOX_CODEC_ERR_LIMIT;
        result.reason = std::string("临时区限制：") + algoName + " 的输入 " +
            byteText(input.size()) + " 超过单件上限 " + byteText(maxInBytes);
        return result;
    }
    OH_CryptoDigest* ctx = nullptr;
    if (OH_CryptoDigest_Create(digestOfficialName(algoName), &ctx) != CRYPTO_SUCCESS ||
        ctx == nullptr) {
        result.reason = std::string(algoName) + " 失败：内部错误";
        return result;
    }
    // 空输入：跳过 Update 直取 Final（★ 2026-10-06 真机缺陷修复，P1——HcfIsBlobValid 要求
    // data 非空且 len > 0（源码实读），len=0 的 Update 恒 CRYPTO_INVALID_PARAMS；零更新
    // 上下文的 Final 即空消息摘要，与官方语义等价。原「哑字节 + len 0」防 NULL 写法被实测
    // 证伪：真正被拒的是 len 不是指针）
    if (!input.empty()) {
        Crypto_DataBlob inBlob;
        inBlob.data = reinterpret_cast<uint8_t*>(const_cast<char*>(input.data()));
        inBlob.len = input.size();
        if (OH_CryptoDigest_Update(ctx, &inBlob) != CRYPTO_SUCCESS) {
            OH_DigestCrypto_Destroy(ctx);
            result.reason = std::string(algoName) + " 失败：内部错误";
            return result;
        }
    }
    Crypto_DataBlob outBlob;
    outBlob.data = nullptr;
    outBlob.len = 0;
    if (OH_CryptoDigest_Final(ctx, &outBlob) != CRYPTO_SUCCESS) {
        OH_DigestCrypto_Destroy(ctx);
        result.reason = std::string(algoName) + " 失败：内部错误";
        return result;
    }
    static const char* HEX_CHARS = "0123456789abcdef";
    std::string hex(outBlob.len * 2, '0');
    for (size_t i = 0; i < outBlob.len; i++) {
        hex[i * 2] = HEX_CHARS[outBlob.data[i] >> 4];
        hex[i * 2 + 1] = HEX_CHARS[outBlob.data[i] & 0x0F];
    }
    OH_Crypto_FreeDataBlob(&outBlob);
    OH_DigestCrypto_Destroy(ctx);
    result.ok = true;
    result.data = std::move(hex);
    return result;
}
