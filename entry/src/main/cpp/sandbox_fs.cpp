// 沙箱文件 API 实现（头注释见 sandbox_fs.h；任务书 §3.4——闸判据与 ArkTS 侧
// WorkspaceUtil.ets 逐条对齐，改动须两侧同改；★ 2026-10-06 代码工作台笔F：本件为
// codeexec 与 qjsengine 两目标的共享编译副本，行为零改动——两引擎 fs 语义单源）
#include "sandbox_fs.h"

#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <cstdio>

// 脚本侧列举上限（真机验收 §5.2-10「列举截断」面）：与 store 侧
// WorkspaceTmpUtil.WORKSPACE_TMP_LIST_MAX 同值的独立上界——两处语义独立（store 侧管
// 管理页下探、本处管沙箱回执），非下传字段（契约无此位），对齐义务走真机验收；
// 登记变更记录本笔条目。这不是限额闸（A4 两闸字节值恒下传），属列举条数上界。
static const size_t SANDBOX_LIST_MAX = 500;

// 名称字符上限（与 WorkspaceUtil.WORKSPACE_NAME_MAX_CHARS 同值——同上登记口径）
static const size_t SANDBOX_NAME_MAX_CHARS = 80;

// 空名兜底（与 sanitizeWorkspaceName 兜底名一致）
static const char* SANDBOX_FALLBACK_NAME = "未命名文件.txt";

// 字节量格式化（千分位不做——闸回执里的当前值与上限直接报字节数，中文句）
static std::string byteSizeText(size_t bytes)
{
    return std::to_string(bytes) + " 字节";
}

// 码点计数（UTF-8 序列数——名称闸长度判据的近似口径，见头注释）
static size_t utf8CodePointCount(const std::string& text)
{
    size_t count = 0;
    for (unsigned char ch : text) {
        if ((ch & 0xC0) != 0x80) {
            count++;
        }
    }
    return count;
}

// 空白字符判定（★ 2026-10-06 自检轮修复：原先只认 ASCII 空白族，而 ArkTS 侧
// workspaceNameRejectReason / sanitizeWorkspaceName 走 JS trim 的 Unicode 空白全集——
// 全角空格 U+3000（中文输入高频）、NBSP U+00A0（网页复制常见）等在两侧判定不同：全空白名
// ArkTS 拒「不能为空」而 native 放行、清洗首尾 ArkTS 去掉而 native 保留，违「两处实现
// 逐条对齐」纪律。现按 ECMA WhiteSpace + LineTerminator 全集（25 个代码点，★ 二轮自检
// 订正：首轮注释写 26，实数逐点重数为 25——6 单字节 + NBSP + U+1680 + U+2000~U+200A
// 十一个 + U+2028/U+2029/U+202F + U+205F + U+3000 + U+FEFF）逐个 UTF-8 匹配，与 ArkTS
// trim 精确同集。返回该字符的字节长度，非空白返回 0）
static size_t utf8BlankLen(const std::string& s, size_t i)
{
    unsigned char b = static_cast<unsigned char>(s[i]);
    if (b == ' ' || b == '\t' || b == '\n' || b == '\r' || b == '\v' || b == '\f') {
        return 1;
    }
    const size_t remain = s.size() - i;
    if (b == 0xC2 && remain >= 2 && static_cast<unsigned char>(s[i + 1]) == 0xA0) {
        return 2; // U+00A0 NBSP
    }
    if (b == 0xE1 && remain >= 3 && static_cast<unsigned char>(s[i + 1]) == 0x9A &&
        static_cast<unsigned char>(s[i + 2]) == 0x80) {
        return 3; // U+1680
    }
    if (b == 0xE2 && remain >= 3 && static_cast<unsigned char>(s[i + 1]) == 0x80) {
        unsigned char c = static_cast<unsigned char>(s[i + 2]);
        if ((c >= 0x80 && c <= 0x8A) || c == 0xA8 || c == 0xA9 || c == 0xAF) {
            return 3; // U+2000~U+200A、U+2028、U+2029、U+202F（U+200B 等零宽格非 JS 空白，不收）
        }
    }
    if (b == 0xE2 && remain >= 3 && static_cast<unsigned char>(s[i + 1]) == 0x81 &&
        static_cast<unsigned char>(s[i + 2]) == 0x9F) {
        return 3; // U+205F
    }
    if (b == 0xE3 && remain >= 3 && static_cast<unsigned char>(s[i + 1]) == 0x80 &&
        static_cast<unsigned char>(s[i + 2]) == 0x80) {
        return 3; // U+3000 全角空格
    }
    if (b == 0xEF && remain >= 3 && static_cast<unsigned char>(s[i + 1]) == 0xBB &&
        static_cast<unsigned char>(s[i + 2]) == 0xBF) {
        return 3; // U+FEFF
    }
    return 0;
}

std::string sandboxUtf8Truncate(const std::string& text, size_t maxBytes)
{
    if (text.size() <= maxBytes) {
        return text;
    }
    size_t cut = maxBytes;
    // 截点落在多字节序列中间时回退到序列头（0x80~0xBF 是续字节——前移到非续字节位）
    while (cut > 0 && (static_cast<unsigned char>(text[cut]) & 0xC0) == 0x80) {
        cut--;
    }
    return text.substr(0, cut);
}

std::string sandboxUtf8Head(const std::string& text, size_t maxBytes)
{
    return sandboxUtf8Truncate(text, maxBytes);
}

std::string sandboxUtf8Tail(const std::string& text, size_t maxBytes)
{
    if (text.size() <= maxBytes) {
        return text;
    }
    size_t start = text.size() - maxBytes;
    // 起点落在多字节序列中间时前移到序列头
    while (start < text.size() && (static_cast<unsigned char>(text[start]) & 0xC0) == 0x80) {
        start++;
    }
    return text.substr(start);
}

// 按码点数截断（对齐 ArkTS 侧 substring 的码元口径——普通字符一码点一码元，截点退到
// UTF-8 序列头防劈半个字符）
static std::string truncateByCodePoints(const std::string& text, size_t maxPoints)
{
    size_t points = 0;
    size_t cut = text.size();
    for (size_t i = 0; i < text.size();) {
        if (points >= maxPoints) {
            cut = i;
            break;
        }
        unsigned char ch = static_cast<unsigned char>(text[i]);
        size_t seqLen = 1;
        if ((ch & 0xE0) == 0xC0) {
            seqLen = 2;
        } else if ((ch & 0xF0) == 0xE0) {
            seqLen = 3;
        } else if ((ch & 0xF8) == 0xF0) {
            seqLen = 4;
        }
        i += std::min(seqLen, text.size() - i);
        points++;
    }
    return text.substr(0, std::min(cut, text.size()));
}

std::string sandboxNameRejectReason(const std::string& name)
{
    // 五拒（顺序与判据逐条对齐 WorkspaceUtil.workspaceNameRejectReason）
    if (name.find('/') != std::string::npos || name.find('\\') != std::string::npos) {
        return "文件名不能包含 / 或 \\";
    }
    if (name.find("..") != std::string::npos) {
        return "文件名不能包含 ..";
    }
    if (name.find('\0') != std::string::npos) {
        return "文件名包含非法字符";
    }
    // 纯空白判定（JS trim 同集——utf8BlankLen，对齐 ArkTS name.trim() === ''）
    bool allBlank = true;
    for (size_t i = 0; i < name.size();) {
        size_t adv = utf8BlankLen(name, i);
        if (adv == 0) {
            allBlank = false;
            break;
        }
        i += adv;
    }
    if (allBlank) {
        return "文件名不能为空";
    }
    if (utf8CodePointCount(name) > SANDBOX_NAME_MAX_CHARS) {
        return "文件名超过 " + std::to_string(SANDBOX_NAME_MAX_CHARS) + " 个字符的上限";
    }
    return "";
}

std::string sandboxSanitizeName(const std::string& name)
{
    std::string cleaned;
    cleaned.reserve(name.size());
    for (char raw : name) {
        unsigned char ch = static_cast<unsigned char>(raw);
        // 非法字符集与控制符（对齐 sanitizeWorkspaceName：\/:*?\"<>| 与 <0x20 / 0x7F）
        if (std::string("\\/:*?\"<>|").find(raw) != std::string::npos || ch < 0x20 || ch == 0x7F) {
            cleaned += '_';
        } else {
            cleaned += raw;
        }
    }
    // 连续点折叠（2 个以上连续点归 1——对齐 sanitizeWorkspaceName 同规则）
    std::string folded;
    size_t i = 0;
    while (i < cleaned.size()) {
        if (cleaned[i] == '.') {
            size_t run = 1;
            while (i + run < cleaned.size() && cleaned[i + run] == '.') {
                run++;
            }
            folded += run >= 2 ? "." : std::string(run, '.');
            i += run;
        } else {
            folded += cleaned[i];
            i++;
        }
    }
    // 首尾去空白（JS trim 同集——utf8BlankLen，对齐 ArkTS sanitize 的 cleaned.trim()）
    size_t begin = 0;
    while (begin < folded.size() && utf8BlankLen(folded, begin) > 0) {
        begin += utf8BlankLen(folded, begin);
    }
    size_t end = begin;
    for (size_t i = begin; i < folded.size();) {
        if (utf8BlankLen(folded, i) > 0) {
            i += utf8BlankLen(folded, i);
        } else {
            i += 1;
            end = i;
        }
    }
    std::string trimmed = (end == begin) ? "" : folded.substr(begin, end - begin);
    if (trimmed.empty()) {
        return SANDBOX_FALLBACK_NAME;
    }
    return truncateByCodePoints(trimmed, SANDBOX_NAME_MAX_CHARS);
}

// 拼绝对路径 + 符号链接拒（名称闸已拒分隔符——symlink 是剩余唯一逃逸向量，lstat 拒之；
// 与任务书 §3.4-2「realpath 归一后必须仍在临时区根内」等价达成且更严：链接本体即拒）
static bool pathForSandbox(const std::string& root, const std::string& name,
    std::string& outPath, std::string& outReason)
{
    outPath = root + "/" + name;
    struct stat st;
    if (lstat(outPath.c_str(), &st) == 0 && S_ISLNK(st.st_mode)) {
        outReason = "临时区限制：文件名不能是符号链接";
        return false;
    }
    return true;
}

SandboxFsResult sandboxFsList(const std::string& root)
{
    DIR* dir = opendir(root.c_str());
    if (dir == nullptr) {
        // 目录不在场 = 视为空（首写按需建目录是 ArkTS 侧职责——ScriptRunOptions 组装时
        // ensure；此处只读不建）
        SandboxFsResult result;
        result.ok = true;
        result.text = "临时区为空。";
        return result;
    }
    struct dirent* entry = nullptr;
    size_t total = 0;
    size_t listed = 0;
    std::string body;
    while ((entry = readdir(dir)) != nullptr) {
        std::string nm(entry->d_name);
        if (nm == "." || nm == "..") {
            continue;
        }
        total++;
        if (listed < SANDBOX_LIST_MAX) {
            struct stat st;
            size_t size = 0;
            if (lstat((root + "/" + nm).c_str(), &st) == 0 && !S_ISLNK(st.st_mode)) {
                size = static_cast<size_t>(st.st_size);
            }
            body += nm + " · " + byteSizeText(size) + "\n";
            listed++;
        }
    }
    closedir(dir);
    SandboxFsResult result;
    result.ok = true;
    if (total == 0) {
        result.text = "临时区为空。";
        return result;
    }
    std::string head = "临时区共 " + std::to_string(total) + " 个文件。\n";
    if (total > listed) {
        result.text = head + body + "……仅列出前 " + std::to_string(listed) +
            " 个，其余 " + std::to_string(total - listed) + " 个已省略。";
    } else {
        result.text = head + body;
    }
    return result;
}

SandboxFsResult sandboxFsRead(const std::string& root, const std::string& name)
{
    SandboxFsResult result;
    std::string reject = sandboxNameRejectReason(name);
    if (!reject.empty()) {
        result.reason = "临时区限制：" + reject;
        return result;
    }
    std::string path;
    if (!pathForSandbox(root, name, path, result.reason)) {
        return result;
    }
    struct stat st;
    if (stat(path.c_str(), &st) != 0) {
        result.reason = "临时区限制：文件「" + name + "」不存在";
        return result;
    }
    std::FILE* fp = std::fopen(path.c_str(), "rb");
    if (fp == nullptr) {
        result.reason = "临时区限制：文件「" + name + "」读取失败";
        return result;
    }
    std::string content;
    content.resize(static_cast<size_t>(st.st_size));
    size_t got = content.empty() ? 0 : std::fread(&content[0], 1, content.size(), fp);
    std::fclose(fp);
    content.resize(got);
    result.ok = true;
    result.text = content;
    return result;
}

SandboxFsResult sandboxFsWrite(const std::string& root, const std::string& name,
    const std::string& text, const SandboxFsLimits& limits)
{
    SandboxFsResult result;
    std::string reject = sandboxNameRejectReason(name);
    if (!reject.empty()) {
        result.reason = "临时区限制：" + reject;
        return result;
    }
    const std::string cleaned = sandboxSanitizeName(name);
    // 单件闸（text 字节量；覆盖写时按新内容计——旧内容先卸再计的差额由总量闸统一判）
    if (text.size() > limits.maxFileBytes) {
        result.reason = "临时区限制：单次写入 " + byteSizeText(text.size()) +
            " 超过单件上限 " + byteSizeText(limits.maxFileBytes);
        return result;
    }
    std::string path;
    if (!pathForSandbox(root, cleaned, path, result.reason)) {
        return result;
    }
    // 总量闸（现占 - 既有同名件 + 新内容；现扫有界见头注释）
    size_t total = sandboxDirTotalBytes(root);
    struct stat st;
    if (stat(path.c_str(), &st) == 0) {
        total = (total >= static_cast<size_t>(st.st_size)) ?
            total - static_cast<size_t>(st.st_size) : 0;
    }
    if (total + text.size() > limits.maxTotalBytes) {
        result.reason = "临时区限制：写入后总量将达 " + byteSizeText(total + text.size()) +
            " 超过总量上限 " + byteSizeText(limits.maxTotalBytes);
        return result;
    }
    std::FILE* fp = std::fopen(path.c_str(), "wb");
    if (fp == nullptr) {
        result.reason = "临时区限制：文件「" + cleaned + "」写入失败";
        return result;
    }
    size_t put = text.empty() ? 0 : std::fwrite(text.data(), 1, text.size(), fp);
    bool ok = std::fclose(fp) == 0 && put == text.size();
    if (!ok) {
        result.reason = "临时区限制：文件「" + cleaned + "」写入失败";
        return result;
    }
    result.ok = true;
    result.text = cleaned;
    return result;
}

// fs.append：追加写（"ab" 不存在即创建）——闸序与 write 同构，两闸口径按追加语义（单件
// 闸判追加后大小、总量闸按追加量——既有内容已计入现占；2026-10-06 代码工作台笔A §3.3）
SandboxFsResult sandboxFsAppend(const std::string& root, const std::string& name,
    const std::string& data, const SandboxFsLimits& limits)
{
    SandboxFsResult result;
    std::string reject = sandboxNameRejectReason(name);
    if (!reject.empty()) {
        result.reason = "临时区限制：" + reject;
        return result;
    }
    const std::string cleaned = sandboxSanitizeName(name);
    // 单件闸按追加后大小（existingSize 取 stat 失败按 0——不存在即创建路径）
    size_t existingSize = 0;
    struct stat st;
    if (stat((root + "/" + cleaned).c_str(), &st) == 0) {
        existingSize = static_cast<size_t>(st.st_size);
    }
    if (existingSize + data.size() > limits.maxFileBytes) {
        result.reason = "临时区限制：追加后 " + byteSizeText(existingSize + data.size()) +
            " 超过单件上限 " + byteSizeText(limits.maxFileBytes);
        return result;
    }
    std::string path;
    if (!pathForSandbox(root, cleaned, path, result.reason)) {
        return result;
    }
    // 总量闸按追加量（既有同名件已在现占里——与 write 的「先卸再计」不同）
    size_t total = sandboxDirTotalBytes(root);
    if (total + data.size() > limits.maxTotalBytes) {
        result.reason = "临时区限制：追加后总量将达 " + byteSizeText(total + data.size()) +
            " 超过总量上限 " + byteSizeText(limits.maxTotalBytes);
        return result;
    }
    std::FILE* fp = std::fopen(path.c_str(), "ab");
    if (fp == nullptr) {
        result.reason = "临时区限制：文件「" + cleaned + "」写入失败";
        return result;
    }
    size_t put = data.empty() ? 0 : std::fwrite(data.data(), 1, data.size(), fp);
    bool ok = std::fclose(fp) == 0 && put == data.size();
    if (!ok) {
        result.reason = "临时区限制：文件「" + cleaned + "」写入失败";
        return result;
    }
    result.ok = true;
    result.text = cleaned;
    return result;
}

SandboxFsResult sandboxFsExists(const std::string& root, const std::string& name)
{
    SandboxFsResult result;
    std::string reject = sandboxNameRejectReason(name);
    if (!reject.empty()) {
        result.reason = "临时区限制：" + reject;
        return result;
    }
    std::string path;
    if (!pathForSandbox(root, name, path, result.reason)) {
        return result;
    }
    struct stat st;
    result.ok = true;
    result.text = stat(path.c_str(), &st) == 0 ? "true" : "false";
    return result;
}

SandboxFsResult sandboxFsSave(const std::string& root, const std::string& name)
{
    SandboxFsResult result;
    std::string reject = sandboxNameRejectReason(name);
    if (!reject.empty()) {
        result.reason = "临时区限制：" + reject;
        return result;
    }
    std::string path;
    if (!pathForSandbox(root, name, path, result.reason)) {
        return result;
    }
    struct stat st;
    if (stat(path.c_str(), &st) != 0) {
        result.reason = "临时区限制：文件「" + name + "」不存在，无法转存";
        return result;
    }
    // 转正登记（savedNames 在 jsvm_runner 侧收集——native 只回执在场核验，落库编排
    // 在 ArkTS 侧复用 promoteWorkspaceTmpFile 链，任务书 §3.4-7）
    result.ok = true;
    result.text = "true";
    return result;
}

size_t sandboxDirTotalBytes(const std::string& root)
{
    DIR* dir = opendir(root.c_str());
    if (dir == nullptr) {
        return 0;
    }
    struct dirent* entry = nullptr;
    size_t total = 0;
    while ((entry = readdir(dir)) != nullptr) {
        std::string nm(entry->d_name);
        if (nm == "." || nm == "..") {
            continue;
        }
        struct stat st;
        if (lstat((root + "/" + nm).c_str(), &st) == 0 && !S_ISLNK(st.st_mode)) {
            total += static_cast<size_t>(st.st_size);
        }
    }
    closedir(dir);
    return total;
}

bool sandboxSpillOutput(const std::string& root, const std::string& fileName,
    const std::string& fullText, size_t maxFileBytes, size_t& writtenBytes)
{
    std::string path = root + "/" + fileName;
    std::FILE* fp = std::fopen(path.c_str(), "wb");
    if (fp == nullptr) {
        return false;
    }
    size_t budget = std::min(fullText.size(), maxFileBytes);
    if (budget < fullText.size()) {
        // ★ 2026-10-06 二轮自检修复（首轮观察 D7 转修复）：写满即止的截点回退到 UTF-8
        // 序列头——否则尾部可能切在多字节序列中间，exec_output_read 读回侧 decodeWithStream
        // 见半截序列即出替换符（读回内容与原文有差的观感缺陷）。fullText 恒为合法 UTF-8
        //（JS 字符串经 valueToUtf8 产出、logs 同源，拼接只加 \n），回退至多 3 字节；极端
        // 退化到 0 也安全（写 0 字节，written < size 走 output-truncated）
        while (budget > 0 && (static_cast<unsigned char>(fullText[budget]) & 0xC0) == 0x80) {
            budget--;
        }
    }
    size_t put = fullText.empty() ? 0 : std::fwrite(fullText.data(), 1, budget, fp);
    bool ok = std::fclose(fp) == 0 && put == budget;
    if (!ok) {
        // ★ 2026-10-06 二轮自检修复（P-13 失败半成品面）："wb" 已截断目标、部分写入的
        // 半截文件对 fs.list/read 可见且占总量闸额度，而回执无信封指引（写失败即无
        // outputFileName）——自清半截产物（照 WorkspaceDbTmp 拷贝失败自清先例；
        // remove 失败留残留由管理页临时段「清理」兜底，不吞原始失败）
        std::remove(path.c_str());
    }
    writtenBytes = put;
    return ok;
}
