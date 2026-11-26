// mount_write 覆盖写 diff 预读域（2026-10-16 diff 批 U15·U-D3 三期——MEMORY_DETAIL.md:522
// 搁置条款经决明 2026-10-16 指令翻案执行；施工总案《三方案与diff覆盖施工总案-20261016》
// §四 4.3）：mount_write(overwrite) 写前读旧文产回执尾行（oldExcerpt/newExcerpt 摘录对或
// diffSkipped + oldLines/newLines 超阈行数对），供工具卡红绿 diff 块与模型自愈。
// · 为何独立成件（反碎片下限②申报）：非新开不可——本域带 fs/buffer 依赖与读门槛逻辑，
//   MountUtil 刻意零 import 纪律不容（断言复制直跑的前提）；ToolMountDelete 属删除异域；
//   ToolMount 本体剔头上限所剩无几（本域原位放会推越 1200 硬线——mount_delete 2026-10-13
//   拆件同款先例）。职责缝一句话 =「mount_write 覆盖写前的旧文摘录预读与文本性门」。
// · ★ 读序铁律（本域第一性质）：预读必须在调用方 MountWriteExecutor 的 fs.openSync
//   （overwrite ⊇ TRUNC）**之前**调用——open 即毁旧文（先读后开；调用点有对位注释）。
// · 降级纪律：读失败 / 超阈 / 文本性门不过一律返回 ''（无尾行，不阻塞写——读旧文纯增益，
//   写语义零变化）。仅 overwrite 语义接：append / create / 目标不存在（新建）不带。
// · 门槛 = MountUtil.MOUNT_WRITE_MAX_CHARS 同源单引（勿造第二常数——写上限调值时读门槛
//   有意联动）；量纲 = 字节保守比较：字节 ≤ 门槛 ⇒ 字符必 ≤ 门槛（UTF-8 每字符 ≥1 字节），
//   字节超门槛走流式数行（纯 CJK 120K~360K 字节区间被保守跳过 = 预期内，回执走行数对）。
import { fileIo as fs, ReadOptions } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { MOUNT_WRITE_MAX_CHARS, MOUNT_KIND_TEXT, MOUNT_KIND_OTHER,
  mountKindOf } from '../MountUtil';
import { buildReceiptDiffExcerptTail, buildReceiptDiffOversizeTail } from './ToolContracts';
// 行数口径复用编辑域单源（split('\n') 计数——与 workspace_read「共 N 行」/ workspace_edit
// 「行数 A→B」同源，禁第二实现）
import { workspaceEditLineCount } from '../WorkspaceEditUtil';

// 未知扩展文本性采样上限（首 4KB）与可打印率下限（S2 R7 吸收）：文本扩展名白名单直过，
// 未知扩展（含无扩展）采样判文本性——二进制不产摘录（防乱码进 diff 块与模型回执）
const MOUNT_DIFF_SAMPLE_BYTES: number = 4096;
const MOUNT_DIFF_TEXT_PRINTABLE_MIN: number = 0.85;

// 采样判文本性：含 NUL 字节即非文本（与 mount_read 的二进制探测同判据——PNG/PDF/ZIP 等
// 头部必带 NUL）；否则可打印字节占比 ≥ 下限为文本。可打印 = Tab / 换行 / 回车 / 0x20~0x7E /
// 高位字节（UTF-8 多字节文本主体即高位字节——纯 CJK 未知扩展按文本放行）；读失败上抛由
// 调用方降级。返回值 = 判定文本性；single-read 不推进指针问题（只读一轮）
function mountDiffSampleIsText(fullPath: string, sampleLen: number): boolean {
  const ab: ArrayBuffer = new ArrayBuffer(sampleLen);
  let file: fs.File | null = null;
  let got: number = 0;
  try {
    file = fs.openSync(fullPath, fs.OpenMode.READ_ONLY);
    const readOptions: ReadOptions = { offset: 0, length: sampleLen };
    got = fs.readSync(file.fd, ab, readOptions);
  } finally {
    if (file !== null) {
      fs.closeSync(file); // 成对释放：open 同段 close，异常路径同样走到
    }
  }
  if (got <= 0) {
    return true; // 空采样无内容可显——按文本放行（摘录对自然为空侧）
  }
  const bytes: Uint8Array = new Uint8Array(ab, 0, got);
  let printable: number = 0;
  for (let i = 0; i < got; i++) {
    const b: number = bytes[i];
    if (b === 0) {
      return false;
    }
    if (b === 0x09 || b === 0x0A || b === 0x0D || (b >= 0x20 && b <= 0x7E) || b >= 0x80) {
      printable += 1;
    }
  }
  return printable / got >= MOUNT_DIFF_TEXT_PRINTABLE_MIN;
}

// 有界读旧文文本（readLen = 调用方给的 stat 尺寸——调用点已保证 ≤ 门槛；单次读不整载更大
// 文件，并发增大文件也不越界）；截断点落在多字节字符中间时剥除尾残字（readMountTextPrefix
// 同款判据，不把替换字符上屏）。读失败上抛由调用方降级
function readMountBoundedText(fullPath: string, sizeBytes: number): string {
  if (sizeBytes <= 0) {
    return '';
  }
  let file: fs.File | null = null;
  try {
    file = fs.openSync(fullPath, fs.OpenMode.READ_ONLY);
    const ab: ArrayBuffer = new ArrayBuffer(sizeBytes);
    const readOptions: ReadOptions = { offset: 0, length: sizeBytes };
    const got: number = fs.readSync(file.fd, ab, readOptions);
    let text: string = buffer.from(ab, 0, got).toString('utf-8');
    if (got < sizeBytes && text.endsWith('\uFFFD')) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  } finally {
    if (file !== null) {
      fs.closeSync(file); // 成对释放：open 同段 close，异常路径同样走到
    }
  }
}

// 超阈旧文流式数行（有界缓冲 64KB 逐块，不整载任意大的旧文件）：LF 字节数 + 1 = 行数——
// 与 split('\n') 计数口径等值（CRLF 同以 LF 计行），workspace_read / workspace_edit 回执
// 同源可比。读失败上抛由调用方降级；续读不传 ReadOptions.offset（其语义是文件读取起点，
// 使指针不推进——顺序读指针自持，HttpBinary 短读修复同款判据）
const MOUNT_DIFF_LINE_CHUNK_BYTES: number = 65536;

function countMountTextLinesStreamed(fullPath: string, sizeBytes: number): number {
  if (sizeBytes <= 0) {
    return 0;
  }
  const chunk: ArrayBuffer = new ArrayBuffer(MOUNT_DIFF_LINE_CHUNK_BYTES);
  let lfCount: number = 0;
  let file: fs.File | null = null;
  try {
    file = fs.openSync(fullPath, fs.OpenMode.READ_ONLY);
    let got: number = fs.readSync(file.fd, chunk);
    while (got > 0) {
      const bytes: Uint8Array = new Uint8Array(chunk, 0, got);
      for (let i = 0; i < got; i++) {
        if (bytes[i] === 0x0A) {
          lfCount += 1;
        }
      }
      if (got < chunk.byteLength) {
        break;
      }
      got = fs.readSync(file.fd, chunk);
    }
    return lfCount + 1;
  } finally {
    if (file !== null) {
      fs.closeSync(file); // 成对释放：open 同段 close，异常路径同样走到
    }
  }
}

// 预读入口（返回尾行 JSON 串，'' = 无尾行；调用方空串不附加）：stat 定大小 → 文本性门 →
// 门槛分流（≤ 门槛有界读 + 摘录截断；超门槛流式数行对）。全包 try 恒不抛——任何失败都是
// 降级无尾行，写语义零变化
export function readMountWriteDiffTail(fullPath: string, relPath: string,
  content: string): string {
  try {
    let sizeBytes: number = 0;
    try {
      sizeBytes = fs.statSync(fullPath).size;
    } catch {
      return ''; // 目标不在（overwrite 对不存在文件 = 新建语义）——无旧文无尾行
    }
    const kind: string = mountKindOf(relPath);
    if (kind !== MOUNT_KIND_TEXT) {
      if (kind !== MOUNT_KIND_OTHER) {
        return ''; // image / doc 档已知非文本——直拒
      }
      const sampleLen: number = sizeBytes < MOUNT_DIFF_SAMPLE_BYTES ?
        sizeBytes : MOUNT_DIFF_SAMPLE_BYTES;
      if (sampleLen > 0 && !mountDiffSampleIsText(fullPath, sampleLen)) {
        return '';
      }
    }
    if (sizeBytes > MOUNT_WRITE_MAX_CHARS) {
      return buildReceiptDiffOversizeTail(countMountTextLinesStreamed(fullPath, sizeBytes),
        workspaceEditLineCount(content));
    }
    return buildReceiptDiffExcerptTail(readMountBoundedText(fullPath, sizeBytes), content);
  } catch {
    return ''; // 读失败一律降级无尾行——不阻塞写
  }
}
