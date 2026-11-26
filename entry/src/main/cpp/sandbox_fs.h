// 沙箱文件 API——纯 C++ 文件域（2026-10-05 端侧代码工作台笔，任务书 §3.4；★ 2026-10-06
// 代码工作台笔A 补 append 与二进制能力说明；★ 2026-10-06 代码工作台笔F 注释澄清：本件为
// codeexec 与 qjsengine 两目标的**共享源**〔各自编入、运行期互相独立——CMakeLists 二进制
// 独立口径〕，行为契约单源；两引擎对 fs 的用户可见语义必须一致——回执等价的前提）。
// · 职责：会话临时区（fsRoot）上的 list / read / write / append / exists / save 与溢出件
//   写入——名称闸五拒 + 写入侧清洗与 ArkTS 侧 WorkspaceUtil.ets 逐条对齐（两处实现必须逐条
//   对齐：ArkTS 侧断言钉既有实现，native 侧靠真机逃逸样本验收，任务书 §3.4-2）。
// · 二进制能力（笔A 起）：本域全部以原始字节读写（std::string 承载字节流）；字符串 ↔
//   UTF-8 的编码语义在 jsvm 侧（fs.read 的文本解码 = CreateStringUtf8 替换语义；fs.write
//   认形与 TypedArray 字节直写在 sandbox_hostapi.cpp / qjs_hostapi.cpp）。
// · 限额纪律（A4）：单件 / 总量两闸数值一律由 ArkTS 侧经 ScriptRunOptions 下传，
//   **本文件禁出现任何限额字面值**（1048576 之类的数字禁出现——断言 316 组与 326 组守）。
// · 本文件不碰 JSVM / QuickJS（与两引擎宿主回调层的职责缝：这里出纯 C++ 结果结构，
//   那边转 JS 值与 JS 异常）。
#ifndef CODEEXEC_SANDBOX_FS_H
#define CODEEXEC_SANDBOX_FS_H

#include <cstddef>
#include <string>

// 下传闸值（ArkTS 侧 WorkspaceTmpUtil.ets 两闸的运行时载体）
struct SandboxFsLimits {
  size_t maxFileBytes;
  size_t maxTotalBytes;
};

// fs.* 操作结果：reason 非空 = FenceError 语义（jsvm_runner 转 name=FenceError 的 JS
// 异常，message 即 reason——中文闸原因，含当前值与上限）
struct SandboxFsResult {
  bool ok;
  std::string text;
  std::string reason;
};

// 名称闸（五拒，判据与 WorkspaceUtil.workspaceNameRejectReason 逐条对齐；80 字符上限按
// UTF-8 码点数近似——ArkTS 侧按 UTF-16 码元，增面字符两侧有一字符级误差，闸目的是防
// 超长非精确计长，登记变更记录；纯空白判定按 JS trim 的 Unicode 空白全集与 ArkTS 同集
//〔2026-10-06 自检轮修复——原 ASCII isspace 族对全角空格 U+3000、NBSP U+00A0 判定漂移〕）
std::string sandboxNameRejectReason(const std::string& name);

// 写入侧清洗（与 WorkspaceUtil.sanitizeWorkspaceName 同口径：非法字符替换 _、连续点
// 折叠、首尾去空白〔JS trim 同集〕、空名兜底、超 80 截断不劈 UTF-8 序列）
std::string sandboxSanitizeName(const std::string& name);

// fs.list()：临时区平铺清单（每行「名 · N 字节」+ 首行数量摘要；空目录一句话；越上限
// 截断并尾行注明——真机验收 §5.2-10「列举截断」面）
SandboxFsResult sandboxFsList(const std::string& root);

// fs.read(name)：读文件全文返回**原始字节**（无转码；文本解码发生在 jsvm 侧
// CreateStringUtf8——fs.read 字符串路径的 U+FFFD 替换在彼，fs.readBytes 走本函数字节直出）
SandboxFsResult sandboxFsRead(const std::string& root, const std::string& name);

// fs.write(name, text)：闸（拒/清洗）→ 单件闸 → 总量闸 → 符号链接拒 → 写盘（truncate）
//——成功 text = 清洗后名（回执报清洗后名，与 workspace_write 落码行为一致）
SandboxFsResult sandboxFsWrite(const std::string& root, const std::string& name,
    const std::string& text, const SandboxFsLimits& limits);

// fs.append(name, data)（2026-10-06 笔A 新增）：追加写（"ab"，不存在即创建）——闸序与
// write 同构，单件闸按**追加后大小**（existing + data）、总量闸按**追加量**（既有内容已
// 计入现占；write 是覆盖写故先卸同名件再计，两者口径差异有别）；成功 text = 清洗后名
SandboxFsResult sandboxFsAppend(const std::string& root, const std::string& name,
    const std::string& data, const SandboxFsLimits& limits);

// fs.exists(name)：闸名（非法名同抛闸原因——真机逃逸样本逐条试全部中文拒绝的口径）
SandboxFsResult sandboxFsExists(const std::string& root, const std::string& name);

// fs.save(name)：闸名 + 在场核验（转正登记进 savedNames——落库编排在 ArkTS 侧，
// native 只登记，任务书 §3.4-7）
SandboxFsResult sandboxFsSave(const std::string& root, const std::string& name);

// 目录现占字节（总量闸求值——每次写入现扫，临时区有界〔单件闸 × 列举上限〕，毫秒级）
size_t sandboxDirTotalBytes(const std::string& root);

// 溢出件写入（完整输出落临时区；受单件闸——写满即止〔★ 2026-10-06 二轮自检修复：截点
// 回退 UTF-8 序列头，尾部不劈多字节字符〕，writtenBytes 回实际写入量供 flags 判
// output-truncated；写失败自清半截产物并回 false）。文件名由 ArkTS 侧生成并过闸下发，
// 本函数不自造名。
bool sandboxSpillOutput(const std::string& root, const std::string& fileName,
    const std::string& fullText, size_t maxFileBytes, size_t& writtenBytes);

// 头尾预览（各约 1KB，UTF-8 序列边界对齐——截点落在多字节序列中间时回退到序列头）
std::string sandboxUtf8Head(const std::string& text, size_t maxBytes);
std::string sandboxUtf8Tail(const std::string& text, size_t maxBytes);

// UTF-8 安全截断（码点边界；maxBytes 为字节上限）
std::string sandboxUtf8Truncate(const std::string& text, size_t maxBytes);

#endif // CODEEXEC_SANDBOX_FS_H
