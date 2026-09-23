// 技能包（zip 目录）导入导出域（2026-09-13 技能层笔 2，方案 §3.3）：
// · 导出 = 临时目录 <dirName>/SKILL.md + <dirName>/files/* → zlib.compressFile 打包 zip 落
//   cacheDir → 调用方 systemShare 分享（自带「另存为文件」）；临时目录用完即删，zip 由下次
//   导出时按前缀清（writeShareFile 同款「先写后清」）。★ 附件按名落 `files/<件名>`，件名可含
//   路径段（规范包导入的件名是相对路径形态）——写入前须建父目录，且须容「父目录已存在」的
//   EEXIST（2026-09-14 格式兼容笔 + 同日全面自检轮修，理由见 mkdirParents 注释）。
// · 单文件导出 SKILL.md（2026-09-13 入口调整笔自 SkillEditPage 迁入——入口改挂技能库行卡
//   右侧菜单，页面侧只负责调分享面板）：serializeSkillMd → filesDir 暂存 → 返回路径，历史
//   同类件同样按前缀清。两导出同域的理由 = 都是「技能交换文件」的产出（同份序列化件，一个
//   单发一个带附件打包），且共用暂存/清理姿势。
// · 导入（两形态，2026-09-14 格式兼容笔；★ 2026-09-22 多技能包笔扩为「一件或多件」）：zip
//   技能包 → 拷入沙箱临时件 → 解包到 cacheDir 临时目录 → **技能根扫描**（包根有 SKILL.md 即
//   包根；否则扫两级子目录里含 SKILL.md 的目录，判定单源 = SkillText.pickSkillRoots）→
//   逐根 frontmatter 解析（容错三态，方案 §3.3）→ **载荷过技能本体校验**（越界值拒收，
//   2026-09-13 全面自检轮补——见 parseOneSkillRoot 注释）→ 附件**递归全树采集**（从技能根起
//   任意深度，件名取相对路径形态；拿不进来的一律计中文警告）→ 结果由调用方**先给用户审阅再
//   入库**（技能正文是指令注入面，导入须用户过目）→ 无论成败 finally 清临时目录与临时 zip。
//   多件包语义（≥2 个技能根）：逐件解析，坏件计入 skipped 如实呈报、好件照常导入，全坏才拒
//   整包；单件包走原单件链——任何失败即拒整包、文案逐字不变（既有断言的契约面零回归）。
//   单文件 SKILL.md 走 readSkillMdFile 出**同一个**结果形态（恒 1 件、无附件、无跳过），
//   复用同一条审阅/落库链。
// · ★ 2026-09-16 上传编码检测笔（评审 §2.6 收口）：解码链一律 UTF-8 强解且不报错（非 UTF-8
//   字节被替换成 U+FFFD）——GBK 中文文本或二进制伪装件于是「解码成功」却整体乱码，静默进
//   编辑页/落库。三个解码点各接检出（判据纯函数 SkillText.isGarbledText，出现替换字符即拒）：
//   上传与单文件导入（readPickedSkillFile）拒收；zip 内主文件读后拒整包；zip 附件逐件警告跳过。
//   评审只点了上传链，zip 链同族缺口一并收口（残限说明见该函数注释）。
// ★ 「不建常驻文件存储」（方案 §3.3 原文）：解包产物只在 cacheDir 临时目录存活一次调用，
//   出栈即删；被打断（进程被杀）残留的目录由系统 cacheDir 回收，本域不做启动期清扫
//   （与 ExportImport 的 sweepExportTemp 不同——那边是常驻 zip 与导出目录，本域连常驻件
//   都没有；这是笔 2 有意取的最小形态，不是漏做）。
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import zlib from '@ohos.zlib';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { classifySkillPackEntry, foldLineBreaks, hasLineBreak, isGarbledText, parseSkillMd,
  pickSkillRoots, serializeSkillMd,
  skillFileExt, skillPackDirName, SKILL_CONTENT_MAX, SKILL_FILE_CONTENT_MAX, SKILL_FILE_EXTS,
  SKILL_FILE_MAX_COUNT, SKILL_FILE_NAME_MAX, SkillArgsValidation, SkillMdParse,
  validateSkillArgs } from './SkillText';
import { SkillFileRow, SkillRow } from './store/SkillDb';

const DOMAIN: number = 0x0001;
const TAG: string = 'SkillPack';

// 导入 zip 大小上限（技能包是纯文本集合，8MB 已远超「10 件 × 8000 字」的量级；超此值
// 基本可判定不是技能包，早拒省得白解包）
const MAX_PACK_ZIP_BYTES: number = 8 * 1024 * 1024;
// 上传/导入单文件大小上限（读进内存前的粗拦——正文上限 8000 字对应 UTF-8 至多几十 KB，
// 1MB 的文件读出来必然超限，先拒省内存）
const MAX_PICKED_BYTES: number = 1024 * 1024;
// ★ 2026-09-13 全面自检轮：**读取前的字节预检线**（zip 8MB 上限拦不住解压后的大件——一个
// 1MB 的 zip 能解出几百 MB 的纯文本，直接 readText 会按 size 申请等长 ArrayBuffer = 主线程
// 大分配）。正文/单件的字符上限 8000 对应 UTF-8 至多约 24KB（BMP 中文 3 字节/字），留 4 倍
// 余量后仍超的文件不可能通过字符校验——先按字节早拒，一个超限大件不读进内存
const MAX_PACK_MD_BYTES: number = SKILL_CONTENT_MAX * 4 + 4096;
const MAX_PACK_FILE_BYTES: number = SKILL_FILE_CONTENT_MAX * 4;

// 包内主文件名（唯一来源：导出与导入两侧同引用，禁裸字符串）
export const SKILL_PACK_MD_NAME: string = 'SKILL.md';
export const SKILL_PACK_FILES_DIR: string = 'files';

// 导入结果（ok = false 时 error 为中文原因；payloads = 本包可导入件——单技能包与单文件链恒 1 件，
// 多技能包逐件；skipped = 包内未导入件与原因，仅多技能包有值，单技能包的任何失败仍走 error 的
// 整包语义（文案与行为逐字不变）；附件链的容错跳过说明逐件挂各自 payload.warnings，不静默丢件）
export interface SkillPackPayload {
  name: string;
  description: string;
  content: string;
  files: SkillPackFilePayload[];
  warnings: string[];
}

export interface SkillPackFilePayload {
  name: string;
  content: string;
}

export interface SkillPackReadResult {
  ok: boolean;
  payloads: SkillPackPayload[];
  skipped: string[];
  error: string;
}

function emptyPayload(): SkillPackPayload {
  return { name: '', description: '', content: '', files: [], warnings: [] };
}

function rejectPack(error: string): SkillPackReadResult {
  return { ok: false, payloads: [], skipped: [], error: error };
}

function rejectItem(error: string): SkillPackItemParse {
  return { ok: false, payload: emptyPayload(), error: error };
}

// 导出：整目录打包（zlib compressFile 条目名形态未文档化——ExportImport 同款整目录打包，
// 导入侧技能根扫描对「多一层目录」右对齐容错（现为两级下钻，判定见 SkillText.pickSkillRoots）。
// 返回 zip 绝对路径，调用方
// systemShare 用；失败上抛（中文由调用方 toast）
export async function exportSkillPack(ctx: common.Context, skill: SkillRow,
  files: SkillFileRow[]): Promise<string> {
  const stamp: string = packStamp();
  // 目录名走 SkillText.skillPackDirName 单源（★ 复核轮收口：本域原自持一份同名副本，理由
  // 写的是「免 import 循环」，但方向本就正确——SkillText 零 import、本域已 import 它，
  // 不存在环；副本的真实代价 = 清洗规则两处漂移，且安全切点修复够不到文件名）
  const dirName: string = skillPackDirName(skill.name);
  const staging: string = ctx.cacheDir + '/skillpack_' + stamp;
  const root: string = staging + '/' + dirName;
  fs.mkdirSync(root + '/' + SKILL_PACK_FILES_DIR, true);
  try {
    writeText(root + '/' + SKILL_PACK_MD_NAME,
      serializeSkillMd({ name: skill.name, description: skill.description,
        content: skill.content }));
    for (const file of files) {
      const filePath: string = root + '/' + SKILL_PACK_FILES_DIR + '/' + file.name;
      mkdirParents(filePath);
      writeText(filePath, file.content);
    }
    const zipPath: string = ctx.cacheDir + '/aicontrol-skillpack-' + stamp + '.zip';
    await zlib.compressFile(root, zipPath, {});
    cleanupDir(staging);
    cleanOldPacks(ctx, zipPath);
    return zipPath;
  } catch (e) {
    cleanupDir(staging);
    throw e as Error;
  }
}

// 单文件导出：serializeSkillMd（frontmatter + 正文）→ filesDir 沙箱暂存 → 返回 md 绝对路径，
// 调用方 systemShare 用；失败上抛（中文由调用方 toast）。文件名 = 「aicontrol-skill-<目录名>-
// <时间戳>.md」（目录名清洗走 SkillText.skillPackDirName 单源；时间戳为秒级——同秒导出同名，靠写入
// TRUNC 覆盖，同源内容无害，跨秒唯一）；写前不清、写后清历史同类件——先写后清的理由与
// ProviderShare.writeShareFile 一致（先清后写在写入失败时连旧文件一起损失）
export function exportSkillMd(ctx: common.Context, skill: SkillRow): string {
  const fileName: string = 'aicontrol-skill-' + skillPackDirName(skill.name) + '-' + packStamp() + '.md';
  const path: string = ctx.filesDir + '/' + fileName;
  writeText(path, serializeSkillMd({ name: skill.name, description: skill.description,
    content: skill.content }));
  cleanOldMdExports(ctx, path);
  return path;
}

// 导入：zipPath（选择器 URI）→ 沙箱临时 zip → 解包 → 技能根扫描 → 逐件解析 → 返回载荷
// （不入库；入库由调用方在用户过目后执行）。失败一律中文 error，不抛（调用方 toast）
// ★ 2026-09-22 多技能包笔（决明「竞品批量导入我们也要」）：一个压缩包里装多件技能（每件一个
// 目录、各带 SKILL.md——合集包与 GitHub 技能仓库的 zip 下载都是这个形态）时逐件解析，好件进
// payloads、坏件进 skipped 如实呈报（不静默丢件）；单技能包（含包根主文件形态）走原单件链——
// 解析失败即拒整包、文案逐字不变，既有断言的契约面零回归
export async function readSkillPack(ctx: common.Context,
  zipUri: string): Promise<SkillPackReadResult> {
  const stamp: string = packStamp();
  const dir: string = ctx.cacheDir + '/skill_import_' + stamp;
  const tempZip: string = ctx.cacheDir + '/skill_import_' + stamp + '.zip';
  try {
    copyFileByUri(zipUri, tempZip);
    fs.mkdirSync(dir, true);
    await zlib.decompressFile(tempZip, dir, {});
    const roots: string[] = collectSkillRoots(dir);
    if (roots.length === 0) {
      return rejectPack('压缩包里找不到 SKILL.md，不是有效的技能包');
    }
    if (roots.length === 1) {
      const one: SkillPackItemParse = parseOneSkillRoot(roots[0]);
      if (!one.ok) {
        return rejectPack(one.error);
      }
      return { ok: true, payloads: [one.payload], skipped: [], error: '' };
    }
    const payloads: SkillPackPayload[] = [];
    const skipped: string[] = [];
    for (const root of roots) {
      const one: SkillPackItemParse = parseOneSkillRoot(root);
      if (one.ok) {
        payloads.push(one.payload);
      } else {
        skipped.push(rootLabel(dir, root) + '：' + one.error);
      }
    }
    if (payloads.length === 0) {
      return rejectPack('压缩包里的 ' + roots.length + ' 件技能都无法导入，' + skipped[0]);
    }
    return { ok: true, payloads: payloads, skipped: skipped, error: '' };
  } catch (e) {
    return rejectPack('解压失败：' + (e as Error).message);
  } finally {
    cleanupDir(dir);
    removeFile(tempZip);
  }
}

// 读取选择器拿到的文本文件（上传附件用——provider.Share 的 readShareFileText 同款姿势：
// 直接按 URI open，stat 粗拦大小，读完成对 close）。
// ★ 2026-09-14 格式兼容笔：fileWord = 超限句里的对象词，按入口语境给——同一函数被两条链共用
// （附件上传 / 单文件 SKILL.md 导入），而「技能附件只支持纯文本」在单文件链上是误导（导入的
// 是技能本体，不是附件）。默认值保原句逐字不变（附件链零回归）
// ★ 2026-09-16 编码检测笔：解码后先过 isGarbledText——非 UTF-8 件（GBK 中文/二进制伪装）在
// 读取处即抛中文原因拒收，不进编辑页过目链
export function readPickedSkillFile(uri: string, fileWord: string = '技能附件'): string {
  const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
  try {
    const stat: fs.Stat = fs.statSync(file.fd);
    if (stat.size > MAX_PICKED_BYTES) {
      throw new Error('文件过大（' + Math.round(stat.size / 1024) + 'KB），' + fileWord +
        '只支持纯文本');
    }
    const ab: ArrayBuffer = new ArrayBuffer(stat.size);
    const readLen: number = fs.readSync(file.fd, ab);
    let text: string = util.TextDecoder.create('utf-8')
      .decodeToString(new Uint8Array(ab).subarray(0, readLen));
    // 非 UTF-8 件在解码处即拒（强解不报错，乱码靠人眼兜底兜不住——2026-09-16 编码检测笔）
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

// 单文件导入（P2，2026-09-14 格式兼容笔）：选择器拿到的单个 .md（自家 exportSkillMd 产物或
// 别家按规范写的 SKILL.md）→ 沙箱读取（字节预检 + 编码检出 + BOM 剥离）→ frontmatter 解析 → **技能本体
// 校验**（与 zip 链同一份 validateSkillArgs，越界值拒收的理由见 parseOneSkillRoot 注释）→ 出**同一个**
// SkillPackReadResult（payloads 恒 1 件、无附件、skipped 恒空）——调用方拿到的形态与 zip 链完全一致，
// 重名判定 / 审阅弹窗 / 落库链全复用，页面侧零分叉。错误一律中文、不抛（调用方 toast）
export function readSkillMdFile(uri: string): SkillPackReadResult {
  let text: string = '';
  try {
    text = readPickedSkillFile(uri, 'SKILL.md');
  } catch (e) {
    return rejectPack((e as Error).message);
  }
  let parsed: SkillMdParse;
  try {
    parsed = parseSkillMd(text);
  } catch (e) {
    return rejectPack('SKILL.md 读取失败：' + (e as Error).message);
  }
  if (!parsed.ok) {
    return rejectPack('SKILL.md 解析失败：' + parsed.error);
  }
  const check: SkillArgsValidation = validateSkillArgs(parsed.name, parsed.description, '',
    parsed.content);
  if (!check.ok) {
    return rejectPack('不能导入：' + check.error);
  }
  return { ok: true, payloads: [{ name: check.name, description: check.description,
    content: check.content, files: [], warnings: [] }], skipped: [], error: '' };
}

// 选择器 URI 末段文件名（上传时作件名初值；去 query 与 decode；取不到回 ''——调用方兜底）
export function pickedFileName(uri: string): string {
  try {
    const cut: number = uri.indexOf('?');
    const bare: string = cut >= 0 ? uri.substring(0, cut) : uri;
    const slash: number = bare.lastIndexOf('/');
    const tail: string = slash >= 0 ? bare.substring(slash + 1) : bare;
    return tail === '' ? '' : decodeURIComponent(tail);
  } catch (e) {
    return '';
  }
}

// ── 内部件 ──

function packStamp(): string {
  const d: Date = new Date();
  const pad = (n: number): string => n < 10 ? '0' + n : '' + n;
  return '' + d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate()) + '-' +
    pad(d.getHours()) + pad(d.getMinutes()) + pad(d.getSeconds());
}

// 单件技能解析结果（内部件；对偶 readSkillPack 的两条语义分支——单件链把 error 当整包错误，
// 多件链把它计入 skipped 并补件名标签）
interface SkillPackItemParse {
  ok: boolean;
  payload: SkillPackPayload;
  error: string;
}

// 单个技能根解析（原 readSkillPack 的解析段原样搬入，错误文案逐字不变——它是既有断言的契约面）：
// 主文件字节预检 → 读取 → 乱码检出 → frontmatter 解析 → 技能本体校验 → 附件全树采集
function parseOneSkillRoot(root: string): SkillPackItemParse {
  const mdPath: string = root + '/' + SKILL_PACK_MD_NAME;
  if (!fileExists(mdPath)) {
    return rejectItem('压缩包里找不到 SKILL.md，不是有效的技能包');
  }
  if (!fileUnderBytes(mdPath, MAX_PACK_MD_BYTES)) {
    return rejectItem('SKILL.md 过大，正文最多 ' + SKILL_CONTENT_MAX + ' 字');
  }
  let parsed: SkillMdParse;
  try {
    const mdText: string = readText(mdPath);
    // zip 链同族收口（2026-09-16 编码检测笔）：主文件乱码即拒该件，与上传链同一判据
    //（多件包里只坏这一件——其余照常导入，本件原因进 skipped）
    if (isGarbledText(mdText)) {
      return rejectItem('压缩包里的 SKILL.md 不是 UTF-8 编码文本，请另存为 UTF-8 后重新打包');
    }
    parsed = parseSkillMd(mdText);
  } catch (e) {
    return rejectItem('SKILL.md 读取失败：' + (e as Error).message);
  }
  if (!parsed.ok) {
    return rejectItem('SKILL.md 解析失败：' + parsed.error);
  }
  // ★ 2026-09-13 全面自检轮：入库前过一遍**技能本体校验**（编辑页保存链走的那一份
  // validateSkillArgs）——原实现把解析结果直接落库，而导入是本应用唯一收外部手写文件的
  // 入口（「标准格式红利」正是立项目标之一）。越界值的两个真实后果：超 50 字的名称让系统
  // 提示词清单预算失效（首条恒放行 → 整段超长清单常驻每次请求）、超 8000 字的正文会在
  // use_skill 回执处被 clipToolResult 切掉尾部（说明书收尾步骤 = 执行依据，正是 511 笔修过
  // 的那个失败形态）。此处拒 + 说清原因，不静默截断（P0-1）
  const check: SkillArgsValidation = validateSkillArgs(parsed.name, parsed.description, '',
    parsed.content);
  if (!check.ok) {
    return rejectItem('不能导入：' + check.error);
  }
  const files: SkillPackFilePayload[] = [];
  const warnings: string[] = [];
  collectPackFiles(root, files, warnings);
  return { ok: true, payload: { name: check.name, description: check.description,
    content: check.content, files: files, warnings: warnings }, error: '' };
}

// 包内技能根扫描（2026-09-22 多技能包笔）：包根有 SKILL.md 时只报这一条（根主文件已足够定性，
// 不再下钻——规则①的短路判定仍在纯函数里，这里只是省掉整棵树的扫描）；否则扫两级子目录收集
// 全部 SKILL.md 相对路径，交 SkillText.pickSkillRoots 单源判定（规则与理由见该函数注释）。
// 扫描深度与纯函数同界：深于两层的包装不在支持面
function collectSkillRoots(dir: string): string[] {
  const mdPaths: string[] = [];
  if (fileExists(dir + '/' + SKILL_PACK_MD_NAME)) {
    mdPaths.push(SKILL_PACK_MD_NAME);
  } else {
    for (const level1 of listSubDirs(dir)) {
      const p1: string = dir + '/' + level1;
      if (fileExists(p1 + '/' + SKILL_PACK_MD_NAME)) {
        mdPaths.push(level1 + '/' + SKILL_PACK_MD_NAME);
      }
      for (const level2 of listSubDirs(p1)) {
        if (fileExists(p1 + '/' + level2 + '/' + SKILL_PACK_MD_NAME)) {
          mdPaths.push(level1 + '/' + level2 + '/' + SKILL_PACK_MD_NAME);
        }
      }
    }
  }
  const rels: string[] = pickSkillRoots(mdPaths);
  const roots: string[] = [];
  for (const rel of rels) {
    roots.push(rel === '' ? dir : dir + '/' + rel);
  }
  return roots;
}

// 子目录名单（名字升序——同名判定与「哪几件进来」可复现，采集链同款；不可列/单项 stat 失败按
// 空处理，「找不到 SKILL.md」由调用方报中文原因）
function listSubDirs(dir: string): string[] {
  const subs: string[] = [];
  try {
    for (const name of fs.listFileSync(dir)) {
      try {
        if (fs.statSync(dir + '/' + name).isDirectory()) {
          subs.push(name);
        }
      } catch (e) {
        // 单项 stat 失败跳过
      }
    }
  } catch (e) {
    // 目录不可列 = 空名单
  }
  return subs.sort();
}

// 多件链的件名标签 = 技能根相对包根的路径（用户在报告里能对上包内目录）；根形态（rel 为空）
// 在单件链已短路，此处兜底给「包根」。换行类字符折叠——警告行自身不能被拆行（附件链先例）
function rootLabel(dir: string, root: string): string {
  const prefix: string = dir + '/';
  const rel: string = root.startsWith(prefix) ? root.substring(prefix.length) : '';
  return foldLineBreaks(rel === '' ? '包根' : rel);
}

// 附件收集（**递归全树**，2026-09-14 格式兼容笔）：
// 原实现只扫 root/files/ 一层，且有两处静默路径——没有 files 目录时直接 return、files 内的
// 嵌套目录裸 continue；外部规范包（references/ scripts/ assets/）的资源因此被静默丢弃，与
// 「不静默丢件」的立意相抵。现口径：从包根起递归任意深度，件名取**相对路径形态**（归一化
// 规则单源在 SkillText.classifySkillPackEntry，本文件不自持副本），拿不进来的一律计中文警告；
// 以 . 开头的项（.git 等版本控制元数据）跳过并按聚合计数呈报（防元数据挤占 10 件上限）。
// 遍历序 = 同层按名字升序后再递归下钻，保证「哪 10 件进来」可复现、可断言。
// ★ 2026-09-13 全面自检轮：**件数在收集处封顶**并计警告——原实现只由库页落库循环按
// SKILL_FILE_MAX_COUNT 截断，第 11 件起既不入库也不出现在任何提示里（静默丢件）。封顶移到
// 收集处 = 超限件在**审阅弹窗**里就如实列出，用户点「导入」前即知道包里有什么没进来
function collectPackFiles(root: string, files: SkillPackFilePayload[],
  warnings: string[]): void {
  const counters: PackCollectCounters = { dropped: 0, hidden: 0 };
  scanPackDir(root, '', files, warnings, counters);
  if (counters.dropped > 0) {
    warnings.push('另有 ' + counters.dropped + ' 个附件超过每技能 ' + SKILL_FILE_MAX_COUNT +
      ' 个的上限，未导入');
  }
  if (counters.hidden > 0) {
    warnings.push('另有 ' + counters.hidden + ' 个以 . 开头的文件或文件夹未导入');
  }
}

// 采集计数（跨层累积；点开头项与超限件都走聚合尾警告，不逐件刷屏）
interface PackCollectCounters {
  dropped: number; // 超件数上限未采
  hidden: number;  // 以 . 开头被跳过
}

// 递归扫描一层（relDir = 相对包根的路径，包根传 ''）：同层名字升序，目录下钻、文件逐件处理。
// 目录不可列 = 明确警告后放弃该层（原实现此处是静默 return）
function scanPackDir(absDir: string, relDir: string, files: SkillPackFilePayload[],
  warnings: string[], counters: PackCollectCounters): void {
  let names: string[] = [];
  try {
    names = fs.listFileSync(absDir);
  } catch (e) {
    warnings.push(relDir === '' ? '技能包目录读取失败，附件未导入'
      : relDir + '：文件夹读取失败，已跳过');
    return;
  }
  names.sort();
  for (const name of names) {
    if (name.startsWith('.')) {
      counters.hidden++;
      continue;
    }
    if (relDir === '' && name === SKILL_PACK_MD_NAME) {
      continue; // 根 SKILL.md = 主文件（正文与元信息走 readSkillPack 主链），不是附件
    }
    const rel: string = relDir === '' ? name : relDir + '/' + name;
    const abs: string = absDir + '/' + name;
    let isDir: boolean = false;
    try {
      isDir = fs.statSync(abs).isDirectory();
    } catch (e) {
      warnings.push(rel + '：读取失败，已跳过');
      continue;
    }
    if (isDir) {
      scanPackDir(abs, rel, files, warnings, counters);
      continue;
    }
    collectOnePackFile(abs, rel, files, warnings, counters);
  }
}

// 单件处理（判据与顺序照原实现，防文案与断言错位）：件名归一化 → 换行类字符 → 件名长度 →
// 扩展名白名单 → 字节预检 → 读取 → 空内容 → 字符数 → 包内重名。**每条跳过分支都产出中文
// 警告**（P0-1：包里的东西要么进库、要么在审阅弹窗里被列出）
// ★ 2026-09-15 同族收口加换行判（件名含换行类字符 → 跳过）：件名源头是 zip 条目名（任意
// 字节串），解包后经暂存目录遍历进入本函数——**解包是否逐字保留件名未实测**，本判为防御性
// 收口（新来源一律先拒）。换行件名能把附件清单段（逐行、`- 件名`）拆行、让逐字定位键失配；
// 判据与族集同纯域（hasLineBreak / LINE_BREAK_CHARS）。警告里的件名走 foldLineBreaks——
// 警告行自身不能再被换行拆开（审阅弹窗按行/分号排版）
function collectOnePackFile(absPath: string, relPath: string, files: SkillPackFilePayload[],
  warnings: string[], counters: PackCollectCounters): void {
  if (files.length >= SKILL_FILE_MAX_COUNT) {
    counters.dropped++;
    return;
  }
  const name: string = classifySkillPackEntry(relPath).fileName;
  if (hasLineBreak(name)) {
    warnings.push(foldLineBreaks(name) + '：文件名包含换行，已跳过');
    return;
  }
  if (name.length > SKILL_FILE_NAME_MAX) {
    warnings.push(name + '：文件名超过 ' + SKILL_FILE_NAME_MAX + ' 字上限，已跳过');
    return;
  }
  if (!SKILL_FILE_EXTS.includes(skillFileExt(name))) {
    warnings.push(name + '：格式不在支持范围（仅纯文本），已跳过');
    return;
  }
  if (!fileUnderBytes(absPath, MAX_PACK_FILE_BYTES)) {
    warnings.push(name + '：内容超过 ' + SKILL_FILE_CONTENT_MAX + ' 字，已跳过');
    return;
  }
  let text: string = '';
  try {
    text = readText(absPath);
  } catch (e) {
    warnings.push(name + '：读取失败，已跳过');
    return;
  }
  if (isGarbledText(text)) {
    warnings.push(name + '：不是 UTF-8 编码文本，已跳过');
    return;
  }
  if (text.trim() === '') {
    warnings.push(name + '：内容为空，已跳过');
    return;
  }
  if (text.trim().length > SKILL_FILE_CONTENT_MAX) {
    warnings.push(name + '：内容超过 ' + SKILL_FILE_CONTENT_MAX + ' 字，已跳过');
    return;
  }
  for (const kept of files) {
    if (kept.name === name) {
      warnings.push(name + '：与包内另一文件重名，已跳过');
      return;
    }
  }
  files.push({ name: name, content: text.trim() });
}

// 写附件前建父目录：件名可含路径段（规范包导入后件名是相对路径形态，如 references/api.md），
// 只建了 files/ 一级的旧实现对这类件名会抛 ENOENT——导入了却导不出去（2026-09-14 格式兼容笔）。
// ★★ 2026-09-14 全面自检轮修：**目标目录已存在时 `mkdirSync(path, true)` 仍抛 EEXIST
//   (13900015)**，recursion 不豁免（真机实测口径：dshinhm `KimiAttachmentCtrl`「目录已存在时
//   mkdirSync 亦抛 EEXIST——真机实测三入口全短路」+ 本仓 `AttachmentUtil.ensureAttachDir`
//   同款容错）。裸调用的后果不是「建目录失败」而是**整条导出链失败**：平铺件名的父目录恒是
//   本函数上方刚建过的 `files/`、同目录第二个路径件名的父目录同样已存在——带附件的技能一律
//   导不出去（探针 = scripts/.tmp/skill-import-probe/probe-export.mjs，真机语义桩实测）。
//   故 EEXIST = 目标状态静默、其他错误上抛（姿势照 ensureAttachDir 先例）
function mkdirParents(path: string): void {
  const slash: number = path.lastIndexOf('/');
  if (slash <= 0) {
    return;
  }
  try {
    fs.mkdirSync(path.substring(0, slash), true);
  } catch (e) {
    const err = e as BusinessError;
    if (err.code !== 13900015) {
      throw e as Error; // ArkTS 限 throw 仅接受 Error 值（ensureAttachDir 同注）
    }
  }
}

// 读取前字节预检（stat 失败 = 不可读，按不合规处理——调用方各自给中文原因）
function fileUnderBytes(path: string, limit: number): boolean {
  try {
    return fs.statSync(path).size <= limit;
  } catch (e) {
    return false;
  }
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

// 选择器 URI → 沙箱临时件（BYTE 级拷贝；zip 解压只认沙箱路径，不赌 zlib 接受 picker URI）。
// 大小粗拦在此：超上限早拒，省得白拷一遍大文件
function copyFileByUri(uri: string, dest: string): void {
  const src: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
  try {
    const stat: fs.Stat = fs.statSync(src.fd);
    if (stat.size > MAX_PACK_ZIP_BYTES) {
      throw new Error('压缩包过大（' + Math.round(stat.size / 1024) + 'KB）');
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

// 历史导出包清理（数据有界：前缀 + .zip，保留本次；清理失败只记不阻断导出）
function cleanOldPacks(ctx: common.Context, keepPath: string): void {
  try {
    for (const name of fs.listFileSync(ctx.cacheDir)) {
      if (!name.startsWith('aicontrol-skillpack-') || !name.endsWith('.zip')) {
        continue;
      }
      const path: string = ctx.cacheDir + '/' + name;
      if (path !== keepPath) {
        fs.unlinkSync(path);
      }
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, '清理历史技能包失败（不影响本次导出）：%{public}s', (e as Error).message);
  }
}

// 历史导出 md 清理（数据有界：前缀 + .md，保留本次；清理失败只记不阻断导出——cleanOldPacks
// 同款。包 zip 名为 aicontrol-skillpack- 前缀，与 aicontrol-skill- 不互噬）
function cleanOldMdExports(ctx: common.Context, keepPath: string): void {
  try {
    for (const name of fs.listFileSync(ctx.filesDir)) {
      if (!name.startsWith('aicontrol-skill-') || !name.endsWith('.md')) {
        continue;
      }
      const path: string = ctx.filesDir + '/' + name;
      if (path !== keepPath) {
        fs.unlinkSync(path);
      }
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, '清理历史技能导出文件失败（不影响本次导出）：%{public}s', (e as Error).message);
  }
}

function cleanupDir(dir: string): void {
  try {
    for (const name of fs.listFileSync(dir)) {
      const path: string = dir + '/' + name;
      try {
        if (fs.statSync(path).isDirectory()) {
          cleanupDir(path);
        } else {
          fs.unlinkSync(path);
        }
      } catch (e) {
        // 单项失败跳过（临时目录，系统会回收）
      }
    }
    fs.rmdirSync(dir);
  } catch (e) {
    // 目录不存在 = 目标状态
  }
}

function removeFile(path: string): void {
  try {
    fs.unlinkSync(path);
  } catch (e) {
    // 不存在 = 目标状态
  }
}

function fileExists(path: string): boolean {
  try {
    fs.statSync(path);
    return true;
  } catch (e) {
    return false;
  }
}
