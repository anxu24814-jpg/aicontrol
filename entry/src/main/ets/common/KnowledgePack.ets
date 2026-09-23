// 知识库文件导入导出盘面域（2026-09-22 知识库导入导出笔，方案-知识库导入导出-20260922 §3.4）：
// 职责一句话 = 知识库文件与条目的盘面 I/O（写沙箱导出件 / fd 链拷贝读入 / **上传件直读**
// / 临时件清理）。
// · ★ 上传件直读（2026-09-23 知识库文件笔）：readPickedKnowledgeFileText = 条目附件上传链的
//   读取端（选择器 URI → 直读 fd → 字节粗拦 → UTF-8 强解 + 乱码判拒 → 剥 BOM）；本域因此
//   多引一个技能域的零 import 纯函数（isGarbledText，编码判据单源，理由见该函数注释）。
// 格式构造 / 解析 / 逐条分派在 KnowledgeText（零 import 纯函数域），本域单向 import 它、
// 无环——与 SkillPack 对 SkillText 的域界线同构（纯函数域 | 存储域 | 打包域 | 页面）。
// · 导出：serializeKnowledgeBook → filesDir 暂存 → 返回绝对路径，调用方 systemShare 分享
//   （面板自带「另存为文件」）；写后清历史同类件（数据有界——「先写后清」：先清后写在写入
//   失败时连旧文件一起损失，SkillPack.cleanOldMdExports 同款口径）。
// · 通用格式导出（2026-09-22 第三步）：serializeKnowledgeBookCompat → 同一 filesDir 暂存 +
//   同一前缀清理（两种导出件共守一套「只留最近一份」的口径，文件名以「-通用」中段区分）。
// · 导入：选择器 URI → **fd 链拷贝**到 cacheDir 临时件 → 读文本（剥 BOM）→ parseKnowledgeBook
//   → finally 清临时件（无论成败）。★ URI 字符串不得直传 fs 路径面（2026-08-20 真机实锤
//   「路径或文件不存在」，DataSyncPage 与 SkillPack.copyFileByUri 头注释同记）——统一
//   「openSync(uri) 取 fd → 读 → 写目标」三步。
// · 读取大小上限：合法文件最坏 100 条 × 6000 字 × UTF-8 3 字节 ≈ 1.9MB，留一倍余量取 4MB
//   ——超此值必不是知识库文件，读前早拒省内存（照 SkillPack.MAX_PICKED_BYTES 口径）。
// · 不做导出到系统保存面板（DocumentViewPicker.save）——分享面板已含「另存为文件」，且与
//   技能导出链一致（一处学一处，方案 §5）。
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { isGarbledText } from './SkillText';
import {
  knowledgeFileName, KnowledgeCompatExport, KnowledgeEntryItem, parseKnowledgeBook,
  KnowledgeFileRead, serializeKnowledgeBook, serializeKnowledgeBookCompat
} from './KnowledgeText';

const DOMAIN: number = 0x0001;
const TAG: string = 'KnowledgePack';

// 读取前的字节粗拦（readText 按 size 申请等长 ArrayBuffer——大件先拒，主线程不白吃一次分配）
const MAX_PICKED_BYTES: number = 4 * 1024 * 1024;
// 上传件的字节粗拦（2026-09-23 知识库文件笔）：单件字符上限 KNOWLEDGE_FILE_CONTENT_MAX 8000
// 对应 UTF-8 至多约 24KB（BMP 中文 3 字节/字），留 10 倍余量取 256KB——超此线必过不了字符
// 校验，一个超限大件不读进内存（SkillPack 上传链为 1MB 同款早拒、更松；两域各自持有）
const MAX_PICKED_FILE_BYTES: number = 256 * 1024;
// 导出件名前缀（历史清理的匹配面；与技能域 aicontrol-skill- 前缀不互噬。★ 自家格式与通用格式
// 两个导出件**同用此前缀**——历史清理才有一套口径可守，否则两种件各活各的、越清越漏）
const KNOWLEDGE_EXPORT_PREFIX: string = 'aicontrol-knowledge-';
// 通用格式导出件的中段标记（两种导出件在**文件名上**可区分：只差内容的话，用户在系统文件管理器
// 里看不出该把哪一个发给别人。用界面上的词「通用」而不是格式名，用户不认识后者）
const KNOWLEDGE_COMPAT_MARK: string = '-通用';

// 通用格式导出结果（盘面面：落盘路径 + 纯函数域带回的两个计数——页面 toast 用）
export interface KnowledgeCompatWrite {
  path: string;
  exported: number;
  dropped: number;
}

// 导出：写 ctx.filesDir 沙箱件，返回绝对路径（调用方 systemShare 用）；失败上抛（中文由调用
// 方 toast，P0-1 不静默）。文件名 = 前缀 + knowledgeFileName(书名)清洗 + 秒级时间戳——同秒
// 重名靠写入 TRUNC 覆盖，同源内容无害；空库（0 条）允许导出（结构合法，entries 为空数组）
export function exportKnowledgeBook(ctx: common.Context, name: string,
  entries: KnowledgeEntryItem[], sources: string[]): string {
  const fileName: string = KNOWLEDGE_EXPORT_PREFIX + knowledgeFileName(name) + '-' +
    packStamp() + '.json';
  const path: string = ctx.filesDir + '/' + fileName;
  writeText(path, serializeKnowledgeBook(name, entries, sources));
  cleanOldExports(ctx, path);
  return path;
}

// 通用格式导出（2026-09-22 第三步）：序列化在纯函数域（serializeKnowledgeBookCompat），本域只
// 落盘与清理——与上方自家格式导出同构。返回值把 exported / dropped 一并带回页面（页面据此决定
// 是否补一句「N 条没有关键词的条目未导出」的 toast，文案在 composeKnowledgeCompatExportTip）
export function exportKnowledgeBookCompat(ctx: common.Context, name: string,
  entries: KnowledgeEntryItem[]): KnowledgeCompatWrite {
  const built: KnowledgeCompatExport = serializeKnowledgeBookCompat(name, entries);
  const fileName: string = KNOWLEDGE_EXPORT_PREFIX + knowledgeFileName(name) +
    KNOWLEDGE_COMPAT_MARK + '-' + packStamp() + '.json';
  const path: string = ctx.filesDir + '/' + fileName;
  writeText(path, built.json);
  cleanOldExports(ctx, path);
  return { path: path, exported: built.exported, dropped: built.dropped };
}

// 导入：URI → fd 链拷贝 → 读文本 → parseKnowledgeBook（**带文件名兜底书名**——外部世界书常无
// 书名字段，ST 格式压根没有 name 概念，照 RikkaHub「导入时用文件名当书名」先例；自家格式不看它）；
// 临时件 finally 必清（无论成败）。错误一律中文 error 不抛（拷贝/读取失败与解析失败同走 error 面）
export function readPickedKnowledgeFile(ctx: common.Context, uri: string): KnowledgeFileRead {
  const tempPath: string = ctx.cacheDir + '/knowledge_import.json';
  try {
    copyFileByUri(uri, tempPath);
    let text: string = readText(tempPath);
    if (text.charCodeAt(0) === 0xFEFF) {
      text = text.substring(1); // BOM（Windows 记事本另存常见）
    }
    return parseKnowledgeBook(text, stripExtension(pickedKnowledgeName(uri)));
  } catch (e) {
    return { ok: false, name: '', entries: [], notice: '',
      error: '文件读取失败：' + (e as Error).message };
  } finally {
    removeFile(tempPath);
  }
}

// 上传链读取（2026-09-23 知识库文件笔）：选择器 URI → **直读 fd**（不落临时件——上传是
// 「读进来、用户过目、再存库」路径，没有中途文件产物）+ 字节粗拦 → UTF-8 强解 → 乱码判拒
// → 剥 BOM。形制照 SkillPack.readPickedSkillFile（技能附件上传链），差异只在字节线与文案。
// ★ 乱码判据 isGarbledText **单源复用技能纯函数域**：该件是零 import 叶子，本域引它不构成
// 模块环；「读出来是乱码」这个判定只该有一份（2026-09-16 编码检测笔的阈值调优不该两处各跟
// 一遍），本域零 import 约束只对 KnowledgeText 成立、不涉本件
export function readPickedKnowledgeFileText(uri: string): string {
  const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
  try {
    const stat: fs.Stat = fs.statSync(file.fd);
    if (stat.size > MAX_PICKED_FILE_BYTES) {
      throw new Error('文件过大（' + Math.round(stat.size / 1024) + 'KB），知识库附件只支持纯文本');
    }
    const ab: ArrayBuffer = new ArrayBuffer(stat.size);
    const readLen: number = fs.readSync(file.fd, ab);
    let text: string = util.TextDecoder.create('utf-8')
      .decodeToString(new Uint8Array(ab).subarray(0, readLen));
    if (isGarbledText(text)) {
      throw new Error('文件不是 UTF-8 编码文本，请另存为 UTF-8 后重试');
    }
    if (text.charCodeAt(0) === 0xFEFF) {
      text = text.substring(1); // BOM（Windows 记事本另存常见）
    }
    return text;
  } finally {
    fs.closeSync(file);
  }
}

// 扩展名分派：尾段文件名（去 query）的小写扩展名（无扩展名 / 尾点返 ''）；与 KNOWLEDGE_FILE_EXT
// 的比对和中文兜底提示在页面链（UI 面不进本域）
export function knowledgeFileExt(uri: string): string {
  const tail: string = pickedKnowledgeName(uri);
  const dot: number = tail.lastIndexOf('.');
  if (dot < 0 || dot === tail.length - 1) {
    return '';
  }
  return tail.substring(dot + 1).toLowerCase();
}

// URI 尾段文件名（去 query + percent-decode）——扩展名分派与兜底书名两处共用（取尾逻辑重复两次
// 即提子程序，P2-4）。★ decode 不是可选装饰：选择器 uri 的尾段是百分号编码形态（同域先例
// SkillPack.pickedFileName 与 AttachmentPickCtrl.pickerFileName 均 decode，dshinhm
// KimiAttachmentCtrl 同款）——不 decode 时中文名会以 `%E4%B9%A6` 形态落进**导入后的书名**（本
// 函数的主要消费点正是外部件无书名字段时的文件名兜底）。非法编码序列（文件名含裸 `%`）走原串
// 兜底，同先例的 try/catch 姿势；URI 取不到尾段（以 `/` 结尾）返 ''，调用方各自兜底：扩展名空
// 走中文提示、书名空落名称拒
export function pickedKnowledgeName(uri: string): string {
  const cut: number = uri.indexOf('?');
  const bare: string = cut >= 0 ? uri.substring(0, cut) : uri;
  const slash: number = bare.lastIndexOf('/');
  const tail: string = slash >= 0 ? bare.substring(slash + 1) : bare;
  if (tail === '') {
    return '';
  }
  try {
    return decodeURIComponent(tail);
  } catch (e) {
    return tail;
  }
}

// 去最后一个扩展名（`a.json` → `a`；无扩展名与点开头的隐藏名原样返回）
function stripExtension(fileName: string): string {
  const dot: number = fileName.lastIndexOf('.');
  return dot > 0 ? fileName.substring(0, dot) : fileName;
}

// ── 内部件 ──

function packStamp(): string {
  const d: Date = new Date();
  const pad = (n: number): string => n < 10 ? '0' + n : '' + n;
  return '' + d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate()) + '-' +
    pad(d.getHours()) + pad(d.getMinutes()) + pad(d.getSeconds());
}

function writeText(path: string, content: string): void {
  const file: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE |
    fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, content);
  } finally {
    fs.closeSync(file);
  }
}

function readText(path: string): string {
  const stat: fs.Stat = fs.statSync(path);
  const ab: ArrayBuffer = new ArrayBuffer(stat.size);
  const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    const len: number = fs.readSync(file.fd, ab);
    return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(ab).subarray(0, len));
  } finally {
    fs.closeSync(file);
  }
}

// 选择器 URI → 沙箱临时件（fd 链 BYTE 级拷贝；大小粗拦在此——超上限早拒省得白拷大文件）
function copyFileByUri(uri: string, dest: string): void {
  const src: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
  try {
    const stat: fs.Stat = fs.statSync(src.fd);
    if (stat.size > MAX_PICKED_BYTES) {
      throw new Error('文件过大（' + Math.round(stat.size / 1024) + 'KB），不是有效的知识库文件');
    }
    const ab: ArrayBuffer = new ArrayBuffer(stat.size);
    const len: number = fs.readSync(src.fd, ab);
    const out: fs.File = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE |
      fs.OpenMode.TRUNC);
    try {
      fs.writeSync(out.fd, ab, { length: len });
    } finally {
      fs.closeSync(out);
    }
  } finally {
    fs.closeSync(src);
  }
}

// 历史导出件清理（数据有界：前缀 + .json，保留本次；清理失败只记不阻断导出——照
// SkillPack.cleanOldMdExports 口径）
function cleanOldExports(ctx: common.Context, keepPath: string): void {
  try {
    for (const name of fs.listFileSync(ctx.filesDir)) {
      if (!name.startsWith(KNOWLEDGE_EXPORT_PREFIX) || !name.endsWith('.json')) {
        continue;
      }
      const path: string = ctx.filesDir + '/' + name;
      if (path !== keepPath) {
        fs.unlinkSync(path);
      }
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, '清理历史知识库导出文件失败（不影响本次导出）：%{public}s',
      (e as Error).message);
  }
}

function removeFile(path: string): void {
  try {
    fs.unlinkSync(path);
  } catch (e) {
    // 不存在 = 目标状态
  }
}
