// zip 容器纯解析核：EOCD 尾扫定位 + 中央目录遍历产出条目表 + 四闸安全判定 + 解压吸入
// 布局映射。★ 本文件零 import、只用 erasable TS 语法（无 enum/namespace/装饰器/参数属性）
// ——scripts/assert-zip-office-domain.mjs 把本文件复制为 .ts 由 node 类型剥离直跑，断言的
// 就是线上同一实现（禁双实现漂移——照 SseParser 直跑纪律）。kit IO 面（fs 读字节 / zlib
// 解压 / 落库编排）全在壳层 providers/ToolZip.ets，本件零 IO。
// · 字节读取 = Uint8Array 下标 + 手写 readU16LE/readU32LE 小函数——DataView 仓内 .ets 零
//   先例、未过官方查证，不用（node/ArkTS 双侧同码直跑的前提）。
// · 格式依据 = PKWARE APPNOTE.TXT 6.3.10：EOCD §4.3.16（22B 固定头 + comment ≤65535 变长
//   ——存在 comment 时 EOCD 不在文件末 22 字节，须从尾倒扫且 commentLen 与实际尾距一致才
//   认，防数据区伪签名）；中央目录头 §4.3.12（46B 固定头 + 变长名/extra/comment，条目名 =
//   相对目录路径）；GP flag §4.4.4（bit0 加密 / bit3 数据描述符——**中央目录的 size 字段恒
//   为真值**，bit3 只影响 local 头，list/预检走中央目录天然免疫 §4.3.9 / bit11 = EFS
//   UTF-8 名）；zip64 §4.4.1.4（条目数 0xFFFF 或 size/offset 0xFFFFFFFF 占位 → 拒）。
// · 非 UTF-8 名（GBK 中文名包通常 bit11 未设，APPENDIX D）：按 UTF-8 宽容解码，非法序列
//   置换 U+FFFD——壳层以 bit11 未设且名含非 ASCII 判「可能乱码」标注；文件名首译不做
//   GBK 码页转换（平台解压侧官方口径同为「可能乱码」，@ohos.zlib d.ts 明示）。

// 中央目录条目表行（list 回执与四闸判定的数据面）
export interface ZipEntryInfo {
  name: string;             // 条目名（相对路径，'/' 分隔；目录条目尾带 '/'）
  method: number;           // 0 = stored、8 = deflate（其余 = 平台解压侧拒绝面）
  originalSize: number;     // 声明原始大小（中央目录恒真值——数据描述符不影响本字段）
  compressedSize: number;   // 声明压缩后大小
  isEncrypted: boolean;     // GP flag bit0
  flagsUtf8Name: boolean;   // GP flag bit11（EFS）
  isDir: boolean;           // 名尾 '/'
}

// 四闸限额（调用方自 WorkspaceUtil 常量组构筑传入——本件不 import 常量，断言侧经参数
// 传值做关系判据，禁抄常量值进判据）
export interface ZipGateLimits {
  maxEntries: number;
  maxTotalBytes: number;
  maxMemberBytes: number;
}

// 实测文件行（壳层 fs walk 产物——size 供容量折算与实测值执法，本件 plan 只消费 relPath）
export interface ZipMeasuredFile {
  relPath: string;          // 相对解压根的 '/' 分隔路径（fs walk 实测）
  size: number;             // 实测字节
}

// 解压吸入映射产物：目录段集（拓扑序）+ 文件行计划（路径分解）
export interface ZipFilePlan {
  dir: string;              // 相对产物根的逻辑目录（'' = 产物根）
  baseName: string;         // 显示名（恒单段）
}

export interface ZipExtractLayout {
  dirSegments: string[];    // 全部目录段全路径，拓扑序（父先于子，同深按字典序）
  filePlans: ZipFilePlan[];
}

// 小端读（无 DataView——见头注释）
function readU16LE(b: Uint8Array, off: number): number {
  return b[off] | (b[off + 1] << 8);
}

function readU32LE(b: Uint8Array, off: number): number {
  return (b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24)) >>> 0;
}

// UTF-8 宽容解码（非法/截断序列置换 U+FFFD；过长编码与代理区按非法处理——GBK 名在此
// 产出「可能乱码」形态，壳层按 bit11 缺席 + 非 ASCII 标注）
function decodeUtf8Loose(bytes: Uint8Array, start: number, end: number): string {
  let out: string = '';
  let i: number = start;
  while (i < end) {
    const b0: number = bytes[i];
    if (b0 < 0x80) {
      out += String.fromCharCode(b0);
      i++;
      continue;
    }
    const width: number = b0 >= 0xF0 ? 4 : (b0 >= 0xE0 ? 3 : (b0 >= 0xC0 ? 2 : 0));
    if (width === 0 || i + width > end) {
      out += '\uFFFD';
      i++;
      continue;
    }
    let cp: number = b0 & (0xFF >>> (width + 1));
    let ok: boolean = true;
    for (let k: number = 1; k < width; k++) {
      const bk: number = bytes[i + k];
      if ((bk & 0xC0) !== 0x80) {
        ok = false;
        break;
      }
      cp = (cp << 6) | (bk & 0x3F);
    }
    if (!ok || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) ||
      (width === 2 && cp < 0x80) || (width === 3 && cp < 0x800) ||
      (width === 4 && cp < 0x10000)) {
      out += '\uFFFD';
      i++;
      continue;
    }
    if (cp > 0xFFFF) {
      const v: number = cp - 0x10000;
      out += String.fromCharCode(0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF));
    } else {
      out += String.fromCharCode(cp);
    }
    i += width;
  }
  return out;
}

// EOCD 尾扫（§4.3.16）：固定头 22B，comment ≤65535 变长须从尾倒扫；commentLen 与实际尾距
// 一致才认（伪签名防线）。找不到回 -1。
function locateEocd(bytes: Uint8Array): number {
  const minPos: number = Math.max(0, bytes.length - 22 - 65535);
  for (let i: number = bytes.length - 22; i >= minPos; i--) {
    if (readU32LE(bytes, i) !== 0x06054b50) {
      continue;
    }
    const commentLen: number = readU16LE(bytes, i + 20);
    if (i + 22 + commentLen === bytes.length) {
      return i;
    }
  }
  return -1;
}

// 中央目录解析：EOCD 尾扫 → 条目数与 CD 偏移 → 46B 固定头逐条遍历。坏包（无 EOCD / 坏
// 签名 / 截断 / 0 条目）与 zip64 占位抛中文 Error（文案与任务书 §6.2 文案总表同文）。
export function parseZipCentralDir(bytes: Uint8Array): ZipEntryInfo[] {
  const eocd: number = locateEocd(bytes);
  if (eocd < 0) {
    throw new Error('压缩包损坏或不是有效的 zip 格式。');
  }
  const entryCount: number = readU16LE(bytes, eocd + 10);
  if (entryCount === 0xFFFF) {
    throw new Error('暂不支持 zip64 格式的超大压缩包。');
  }
  if (entryCount === 0) {
    throw new Error('压缩包损坏或不是有效的 zip 格式。');
  }
  const cdOffset: number = readU32LE(bytes, eocd + 16);
  if (cdOffset === 0xFFFFFFFF) {
    throw new Error('暂不支持 zip64 格式的超大压缩包。');
  }
  const entries: ZipEntryInfo[] = [];
  let p: number = cdOffset;
  for (let i: number = 0; i < entryCount; i++) {
    if (p + 46 > bytes.length || readU32LE(bytes, p) !== 0x02014b50) {
      throw new Error('压缩包损坏或不是有效的 zip 格式。');
    }
    const flags: number = readU16LE(bytes, p + 8);
    const compressedSize: number = readU32LE(bytes, p + 20);
    const originalSize: number = readU32LE(bytes, p + 24);
    const nameLen: number = readU16LE(bytes, p + 28);
    const extraLen: number = readU16LE(bytes, p + 30);
    const commentLen: number = readU16LE(bytes, p + 32);
    const localOffset: number = readU32LE(bytes, p + 42);
    if (originalSize === 0xFFFFFFFF || compressedSize === 0xFFFFFFFF ||
      localOffset === 0xFFFFFFFF) {
      throw new Error('暂不支持 zip64 格式的超大压缩包。');
    }
    if (p + 46 + nameLen > bytes.length) {
      throw new Error('压缩包损坏或不是有效的 zip 格式。');
    }
    const name: string = decodeUtf8Loose(bytes, p + 46, p + 46 + nameLen);
    entries.push({
      name: name,
      method: readU16LE(bytes, p + 10),
      originalSize: originalSize,
      compressedSize: compressedSize,
      isEncrypted: (flags & 0x0001) !== 0,
      flagsUtf8Name: (flags & 0x0800) !== 0,
      isDir: name.length > 0 && name.charAt(name.length - 1) === '/'
    });
    p += 46 + nameLen + extraLen + commentLen;
  }
  return entries;
}

// 条目名路径安全判（穿越闸内部判据）：含 '\' / '\0' / 前导 '/' / 盘符 / 控制字符
//（<0x20 或 0x7F）/ '..' 或 '.' 段——判据严于平台（平台 zlib 只拦字面 ../ 报 900003，
// 前导 / 与反斜杠无官方口径），全拒在前。
function zipEntryPathUnsafe(name: string): boolean {
  if (name.indexOf('\\') >= 0 || name.indexOf('\0') >= 0 || name.startsWith('/')) {
    return true;
  }
  if (name.length >= 2 && name.charAt(1) === ':') {
    return true; // 盘符形态（§4.4.17.1 条目路径禁）
  }
  for (let i: number = 0; i < name.length; i++) {
    const code: number = name.charCodeAt(i);
    if (code < 0x20 || code === 0x7F) {
      return true;
    }
  }
  const segs: string[] = name.split('/');
  for (const seg of segs) {
    if (seg === '..' || seg === '.') {
      return true;
    }
  }
  return false;
}

// 四闸纯函数（返回中文原因串数组、空 = 放行）：① 穿越 ② 加密 ③ 重复（zlib 解压同名直接
// 覆盖，必须挡在前）④ 规模（条目数 / 声明展开总量 / 声明单件——声明值可伪造，实测是壳层
// 的第二道闸）。每闸至多记一条原因（首个命中），防超大包原因串爆炸。
export function zipEntrySafetyReasons(entries: ZipEntryInfo[],
  limits: ZipGateLimits): string[] {
  const reasons: string[] = [];
  for (const entry of entries) {
    if (zipEntryPathUnsafe(entry.name)) {
      reasons.push('压缩包内条目「' + entry.name + '」的名称不安全。已拒绝解压。');
      break;
    }
  }
  let encrypted: boolean = false;
  for (const entry of entries) {
    if (entry.isEncrypted) {
      encrypted = true;
      break;
    }
  }
  if (encrypted) {
    reasons.push('压缩包已加密。暂不支持解压加密压缩包。');
  }
  const seen: Set<string> = new Set<string>();
  for (const entry of entries) {
    if (seen.has(entry.name)) {
      reasons.push('压缩包内有同名条目。为避免覆盖已拒绝解压。');
      break;
    }
    seen.add(entry.name);
  }
  if (entries.length > limits.maxEntries) {
    reasons.push('压缩包条目数或展开总量超过上限。已拒绝。');
  } else {
    let total: number = 0;
    let memberOver: boolean = false;
    for (const entry of entries) {
      total += entry.originalSize;
      if (entry.originalSize > limits.maxMemberBytes) {
        memberOver = true;
      }
    }
    if (total > limits.maxTotalBytes) {
      reasons.push('压缩包条目数或展开总量超过上限。已拒绝。');
    }
    if (memberOver) {
      reasons.push('压缩包内单件超过大小上限。已拒绝解压。');
    }
  }
  return reasons;
}

// 空目录条目清单（★ 2026-10-31「重发大文档叠加降级与两小修」笔 #6）：目录条目（名尾 '/'）
// 且其下无任何文件条目——判据 = 无文件条目以该目录全路径为前缀。平台解压侧对「压缩空文件夹」
// 产出的包报错（@ohos.zlib d.ts compressFile 原文：The folder to compress cannot be empty.
// Otherwise, an error will be reported when decompressFile is used to decompress the folder），
// 而 Windows「右键压缩含空子目录」正产这种包——解压必败，回执却落在平台的通用错误/「损坏」
// 话术上，误导用户以为包坏了。壳层据本清单提前拒绝并给准确文案（真损坏包文案不动）。
// 返回命中的目录条目名（原样带尾 '/'，保持与条目表同形）。
export function zipEmptyDirEntries(entries: ZipEntryInfo[]): string[] {
  // 有文件落入的目录全路径集（尾带 '/'，与目录条目名同形）——逐文件条目向上登记各级祖先
  const filled: Set<string> = new Set<string>();
  for (const entry of entries) {
    if (entry.isDir) {
      continue;
    }
    let slash: number = entry.name.lastIndexOf('/');
    while (slash >= 0) {
      filled.add(entry.name.substring(0, slash + 1));
      slash = entry.name.lastIndexOf('/', slash - 1);
    }
  }
  const empties: string[] = [];
  for (const entry of entries) {
    if (entry.isDir && !filled.has(entry.name)) {
      empties.push(entry.name);
    }
  }
  return empties;
}

// 吸入映射纯函数：实测枚举的文件清单 → 目录段集（拓扑序——父先于子，铸行按序即自然分层）
// + 文件行计划（路径分解：dir = 逻辑目录、baseName = 单段显示名）。显示名清洗 / 同目录
// dedupe / kind 分类由壳层消费 WorkspaceUtil 既有纯函数（同值行为已有 202 族直跑钉守）。
export function planZipExtractLayout(files: ZipMeasuredFile[]): ZipExtractLayout {
  const dirSet: Set<string> = new Set<string>();
  const filePlans: ZipFilePlan[] = [];
  for (const file of files) {
    const path: string = file.relPath;
    if (path === '') {
      continue; // 空路径防御位
    }
    const slash: number = path.lastIndexOf('/');
    const dir: string = slash < 0 ? '' : path.substring(0, slash);
    const baseName: string = slash < 0 ? path : path.substring(slash + 1);
    // 目录段链全登记（含各级祖先）——先于文件行判：尾斜杠目录条目（'a/' 形态，walk 实测
    // 不产、防御位）不产文件行但其目录段照登记
    let seg: string = dir;
    while (seg !== '') {
      dirSet.add(seg);
      const up: number = seg.lastIndexOf('/');
      seg = up < 0 ? '' : seg.substring(0, up);
    }
    if (baseName === '') {
      continue; // 尾斜杠目录条目与 'a//' 退化形态不产文件行
    }
    filePlans.push({ dir: dir, baseName: baseName });
  }
  const dirSegments: string[] = [];
  dirSet.forEach((d: string): void => {
    dirSegments.push(d);
  });
  dirSegments.sort((a: string, b: string): number => {
    const da: number = a.split('/').length;
    const db: number = b.split('/').length;
    if (da !== db) {
      return da - db;
    }
    return a < b ? -1 : (a > b ? 1 : 0);
  });
  return { dirSegments: dirSegments, filePlans: filePlans };
}
