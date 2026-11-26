// Python 运行时装配件（2026-11-06 鸿蒙Python运行时门1笔，任务书-鸿蒙Python运行时门0门1
// -20261106 U4）：stdlib zip 首用落位 + libpyengine.so 入口封装。门 4 起接正式链
//（exec_python 工具 + 设置管理页；探针页与正式链共用本件，门 4 前的「探针页唯一消费面」
// 限制解除——2026-11-14 闲 3 门 4 笔）。
// · 布局（照 Guncat 同构，commander-notes「U4 pyengine 施工弹药」）：filesDir 下
//   python-3.13.18-g7/ 目录 = PYTHONHOME；rawfile python/python313.zip 首次拷入该目录后
//   **保持 zip 形态 zipimport 直读**（zip 全 Stored 存储，不解开——Guncat 铁则）；.ready
//   标记文件（内容 = 版本串）作为「落位完成」判据，同版本已在场即跳过重拷。
// · 门 2 扩展（2026-11-07 闲 1）：rawfile 追加 python/site-packages.zip（纯 py 15 件，
//   同为 Stored 直读）与 python/extras.zip（C 扩展包 .py 部分 + sitecustomize + 数据件）——
//   extras **必须解压成真实目录**（zipimport 下 os.path.exists 对 zip 虚拟路径恒 False，
//   docx/pptx 模板与 tzdata 数据件会找不到；Guncat 2.11 真机实锤），解压成功后删 zip 省
//   沙箱空间；目录名随版本串换新（-g2 尾缀），旧目录由启动清扫回收（sweepLegacyPyRuntimeDirs，
//   2026-11-14 起——每套 ~115MB 不可见残留曾致存储页暴涨，勿再回「遗留不清理」口径）。
//   PYTHONPATH 四层 =
//   python313.zip : site-packages.zip : extras : libs，纯 py 层永远在 libs 之前（Guncat
//   铁则：否则 import 命中 libs 里只有 .so 的空壳目录）——拼接在 PyEngine.cpp native 侧。
// · rawfile 读取先例 = OcrPaddle.ets:90（resourceManager.getRawFileContent——rawfile 的
//   fd 不是文件系统 fd，故走字节流拷贝）；落盘先例 = SkillPack.ets（writeSync +
//   mkdirSync EEXIST 容错——mkdirSync(path, true) 目标已存在仍抛 13900015，真机实测口径）。
// · extras 解压先例 = SkillPack.ets:145（zlib.decompressFile(zip, dir, {})）。
// · P0-1 防线：三件各自下限（stdlib >10MB / site-packages >1MB / extras zip >100KB）+
//   拷完字节数与落盘 stat 一致 + extras 解压哨兵 + .ready 版本串比对；任一不满足即抛中文
//   错误或判未就绪重落位，不降级宣称就绪。
// · 契约同步：本文件 interface 与 types/libpyengine/index.d.ts 同构（改名/加字段两处同步）。
import { common } from '@kit.AbilityKit';
import { zlib } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import pyEngine from 'libpyengine.so';

// 运行区目录名（filesDir 下一级；版本化——升版本换目录名即可重落位；-g9 = 中文绘图字体 +
// 随包 CA 形态〔extras 增 matplotlib/mpl-data/fonts/ttf 的 Noto Serif SC 子集与
// matplotlibrc 三条，根部增 cert.pem（Mozilla CA，PyEngine 第一候选）〕；叠 g8 = BLAS 接线 +
// mpl_toolkits 补收形态〔numpy 接 OpenBLAS（_multiarray_umath DT_NEEDED libopenblas.so）
// 与 mpl_toolkits 随 extras 三层补收（3D 投影可用）；叠 g7 门 3 修复：libz.so.1 供给入
// libs + extras 剔 pyi-only 存根目录 + libpdfium.so 走 bundle lib 目录 + bindings 按
// sys.path 逆序解析绝对路径装载（files 目录 .so 不可 dlopen 且裸名搜索不含应用 lib
// 目录，W^X/命名空间实锤）〕，与 g2~g8 产物不共存混装。★ 尾缀必须与 PY_RUNTIME_VERSION
// 同步升——2124 待办第 4 项双判据，只升版本串会让新包沿用旧目录重落位）
const PY_HOME_DIR_NAME = 'python-3.13.18-g9';
// 运行区目录名前缀（filesDir 下专属命名段——旧版本目录清扫判据；升 Python 大版本换
// 3.13.18 段后旧目录名不同仍命中前缀）
const PY_HOME_DIR_PREFIX = 'python-';
// rawfile 内 stdlib zip 路径（门 0 产物，全 Stored 存储）
const PY_STDLIB_RAW_PATH = 'python/python313.zip';
// rawfile 内纯 py 包 zip 与 extras zip 路径（门 2 包构建产物，Stored 存储）
const PY_SITEPKGS_RAW_PATH = 'python/site-packages.zip';
const PY_EXTRAS_RAW_PATH = 'python/extras.zip';
// 落位完成标记文件名（内容 = PY_RUNTIME_VERSION 版本串）
const PY_READY_MARKER_NAME = '.ready';
// stdlib zip 最小体积分界（正常产物 >10MB；低于 = 拷贝残缺，P0-1 拒绝宣称就绪）
const PY_STDLIB_MIN_BYTES = 10000000;
// site-packages zip 最小体积分界（15 件纯 py 包正常 >1MB；低于 = 残缺拒就绪）
const PY_SITEPKGS_MIN_BYTES = 1000000;
// extras 解压后必在文件（双层布局合体 finder——缺失 = 解压残缺，P0-1 拒就绪）
const PY_EXTRAS_SENTINEL = 'sitecustomize.py';
// 运行区版本串（.ready 标记内容——判重落位用）
const PY_RUNTIME_VERSION = '3.13.18-g9';
// 落位后 zip 文件名（native 侧 PYTHONPATH 按约定取 homeDir/ 下同名文件）
const PY_STDLIB_FILE_NAME = 'python313.zip';
const PY_SITEPKGS_FILE_NAME = 'site-packages.zip';
const PY_EXTRAS_ZIP_FILE_NAME = 'extras.zip';
// extras 解压目标目录名（homeDir 下一级；PYTHONPATH 第三层，真实目录非 zip）
const PY_EXTRAS_DIR_NAME = 'extras';

// 探针入口构建期开关（照 BrowseWeb.BROWSE_DEBUG 族先例：常态 false 不进产物；真机验证轮
// 临时翻 true 重构建，回证后随闸①回证笔复位 false。true 时「设置 → 工具调用」页列表尾出
// 一行临时入口）。★ 闸① 九项已于 2026-11-06 验毕全过（2121 节，Agent 经 hdc/uitest 代验）
// ——门 2 验证轮需要时再临时翻 true
export const PY_PROBE_ENABLED: boolean = false;

// 门 1 临时入口行文案（探针页标题与入口共用单源——改文案两处自动一致）
export const PY_PROBE_TITLE: string = 'Python 运行验证';

// 探针页固定诊断脚本（任务书 U4-4：解释器版本、平台、math/zlib/json 三模块验证）
export const PY_PROBE_SCRIPT: string = [
  'import sys, math, zlib, json, platform',
  'print(sys.version)',
  'print(platform.machine())',
  'print(math.sqrt(2))',
  'print(zlib.crc32(b\'ohos\'))',
  'print(json.dumps({\'ok\': 1}))'
].join('\n');

// 长时脚本（2119 笔：验取消与超时两项——固定诊断秒完成无触发面）。20 拍 × 0.5s ≈ 10 秒，
// 探针页超时上限 8s ⇒ 放任到点验 TimeoutError（约第 15 拍断）；中途点取消在下一检查点
// （≤0.5s）验 Canceled。time 为 CPython 内置模块（非 lib-dynload 扩展），不依赖 dlopen 面
export const PY_PROBE_SCRIPT_LONG: string = [
  'import time',
  'for i in range(20):',
  '    print("tick", i)',
  '    time.sleep(0.5)'
].join('\n');

// 门 3 验证脚本一（Rust 三件，2131 清单第 1 项；期望输出 =
// "rust-trio OK 2026.9.1 2.50.4 50.0.2"）。探针页固定键触发（2132 补——此前手输脚本
// 摩擦大且易抄错；AESGCM 12 字节 nonce 与工厂侧 probe 同值）
export const PY_PROBE_SCRIPT_RUST: string = [
  'import rpds',
  'import pydantic_core',
  'from importlib.metadata import version',
  'from cryptography.hazmat.primitives.ciphers.aead import AESGCM',
  'assert rpds.HashTrieMap(a=1)[\'a\'] == 1',
  'k = AESGCM.generate_key(bit_length=256)',
  'ct = AESGCM(k).encrypt(b\'0123456789ab\', b\'smoke\', b\'ad\')',
  'assert AESGCM(k).decrypt(b\'0123456789ab\', ct, b\'ad\') == b\'smoke\'',
  'print(\'rust-trio OK\', version(\'rpds-py\'), version(\'pydantic-core\'), version(\'cryptography\'))'
].join('\n');

// 门 3 验证脚本二（pypdfium2 + 自编 PDFium，2131 清单第 2 项；期望输出 =
// "pdfium OK pages 1"——新建空文档加一页，ctypes 装 .so + 版本面全走通）
export const PY_PROBE_SCRIPT_PDF: string = [
  'import pypdfium2 as p',
  'pdf = p.PdfDocument.new()',
  'pdf.new_page(200, 100)',
  'assert len(pdf) == 1',
  'print(\'pdfium OK pages\', len(pdf))'
].join('\n');

// init 结果（契约同构：types/libpyengine/index.d.ts）
export interface PyInitOutcome {
  ok: boolean;
  version: string;
  error: string;
  elapsedMs: number;
}

// exec 结果（契约同构：types/libpyengine/index.d.ts；error 值域见该文件注释）
export interface PyExecOutcome {
  ok: boolean;
  stdout: string;
  stderr: string;
  error: string;
  elapsedMs: number;
  // save() 登记的待转存文件名（native 每轮读回即清——跨轮不重复转存）
  savedNames: string[];
  // 本轮安全审计事件（写模式 open / socket / subprocess / os.system / ctypes.dlopen；
  // 只记录非边界——desc 与帮助禁写成沙箱承诺）
  audit: string[];
}

// 预置包清单（门 0 冻结 28 项；唯一冻结源 = scripts/python-runtime/manifest.json，
// 本常量是其在代码侧的展示镜像——增删包只发生在工厂重建轮，届时两处同步）
export const PY_PRESET_PACKAGES: string[] = [
  'pip 26.3', 'setuptools 84.2.1', 'wheel 0.48.0', 'flit-core 4.2.0', 'packaging 26.3',
  'pyparsing 3.3.3', 'six 1.17.0', 'et-xmlfile 2.0.0', 'openpyxl 3.1.5',
  'python-dateutil 4.0.0', 'typing-extensions 4.16.0', 'tzdata 2026.6',
  'fonttools 4.68.0', 'cycler 0.12.1', 'pycparser 3.12', 'cffi 2.1.1',
  'contourpy 1.4.0', 'kiwisolver 1.5.1', 'lxml 6.1.3', 'matplotlib 3.11.2',
  'numpy 2.5.4', 'pandas 3.1.1', 'pillow 13.0.0', 'regex 2026.9.29',
  'cryptography 50.0.2', 'pydantic-core 2.50.4', 'rpds-py 2026.9.1',
  'pypdfium2 5.14.0'
];

// 建目录（目标已存在静默——mkdirSync(path, true) 仍抛 EEXIST 13900015，SkillPack 先例）
function mkdirIfExistsTolerant(path: string): void {
  try {
    fs.mkdirSync(path, true);
  } catch (e) {
    const err = e as BusinessErrorLike;
    if (err.code !== 13900015) {
      throw e as Error;
    }
  }
}

// 最小错误形态（只取 code 判 EEXIST——不引 BasicServicesKit 全量类型，同 SkillPack 姿势）
interface BusinessErrorLike {
  code: number;
  message: string;
}

// 整件字节落盘（READ_WRITE|CREATE|TRUNC + writeSync；先例 = KnowledgePack 二进制写回）
function writeAllBytes(path: string, bytes: Uint8Array): void {
  const file: fs.File = fs.openSync(path,
    fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, bytes.buffer, { length: bytes.byteLength });
  } finally {
    fs.closeSync(file);
  }
}

// 小文本落盘（.ready 标记用；TextEncoder 编码——版本串纯 ASCII，编码面无歧义）
function writeAllText(path: string, text: string): void {
  writeAllBytes(path, util.TextEncoder.create('utf-8').encodeInto(text));
}

// 运行区是否已就绪（.ready 在场且三件完整——stdlib/site-packages 体积分界 + extras 哨兵）
function pyRuntimeReady(homeDir: string): boolean {
  try {
    const readyPath: string = homeDir + '/' + PY_READY_MARKER_NAME;
    // .ready 内容必须与本版产物一致——只判文件在场会让同目录名的旧包跳过重落位
    // （2123 笔换过 stdlib zip 内容；门 3 换包同理）。读失败或不符均落 catch 判未就绪。
    const readyVersion: string = fs.readTextSync(readyPath).trim();
    const zipStat: fs.Stat = fs.statSync(homeDir + '/' + PY_STDLIB_FILE_NAME);
    const siteStat: fs.Stat = fs.statSync(homeDir + '/' + PY_SITEPKGS_FILE_NAME);
    const extrasSentinel: string =
      homeDir + '/' + PY_EXTRAS_DIR_NAME + '/' + PY_EXTRAS_SENTINEL;
    return readyVersion === PY_RUNTIME_VERSION && zipStat.size > PY_STDLIB_MIN_BYTES
      && siteStat.size > PY_SITEPKGS_MIN_BYTES && fs.accessSync(extrasSentinel);
  } catch (e) {
    return false;
  }
}

// 在飞落位单飞缓存：并发调 ensurePyRuntime（init pending 期间退出探针页重进再点 = 新实例
// 再发起）会双写同一 zip 交错损坏且照写 .ready——ArkTS 事件循环不救（getRawFileContent
// 的 await 就是交错点）；在飞期间后续调用一律共享同一 promise
let ensurePyRuntimePending: Promise<string> | null = null;

// 首用落位本体（幂等）：filesDir/<PY_HOME_DIR_NAME>/ 就绪后返回该目录路径（= PYTHONHOME）。
// 失败一律抛中文错误（调用方展示），禁静默降级；并发单飞由 ensurePyRuntime 外壳承担
// 三件落位：①stdlib zip（保持 zip 直读）②site-packages zip（同）③extras zip 拷贝 →
// zlib 解压成真实目录 → 删 zip（数据件路径语义；解压失败/哨兵缺失即抛错不写 .ready）
async function placePyRuntime(ctx: common.Context): Promise<string> {
  const homeDir: string = ctx.filesDir + '/' + PY_HOME_DIR_NAME;
  if (pyRuntimeReady(homeDir)) {
    return homeDir;
  }
  mkdirIfExistsTolerant(homeDir);
  await placeZipAsset(ctx, homeDir, PY_STDLIB_RAW_PATH, PY_STDLIB_FILE_NAME, PY_STDLIB_MIN_BYTES,
    'Python 标准库');
  await placeZipAsset(ctx, homeDir, PY_SITEPKGS_RAW_PATH, PY_SITEPKGS_FILE_NAME,
    PY_SITEPKGS_MIN_BYTES, 'Python 预置包层');
  // extras：拷 zip → 解压成真实目录 → 删 zip
  const extrasZipPath: string = homeDir + '/' + PY_EXTRAS_ZIP_FILE_NAME;
  await placeZipAsset(ctx, homeDir, PY_EXTRAS_RAW_PATH, PY_EXTRAS_ZIP_FILE_NAME, 100000, 'Python 扩展包层');
  const extrasDir: string = homeDir + '/' + PY_EXTRAS_DIR_NAME;
  try {
    mkdirIfExistsTolerant(extrasDir);
    await zlib.decompressFile(extrasZipPath, extrasDir, {});
  } catch (e) {
    throw new Error('解压 Python 扩展包层失败：' + (e as Error).message);
  }
  // P0-1 防线：解压哨兵（sitecustomize.py 必在——缺失 = 解压残缺/zip 损坏，拒就绪）
  if (!fs.accessSync(extrasDir + '/' + PY_EXTRAS_SENTINEL)) {
    throw new Error('Python 扩展包层解压不完整（缺 ' + PY_EXTRAS_SENTINEL + '），已停止落位');
  }
  fs.unlinkSync(extrasZipPath); // 解压成功后删 zip 省沙箱空间（Guncat 同口径）
  writeAllText(homeDir + '/' + PY_READY_MARKER_NAME, PY_RUNTIME_VERSION);
  return homeDir;
}

// 单件 zip 资产落位（rawfile → homeDir/<fileName>；读/写/校验三段 P0-1，label 进错误文案）
async function placeZipAsset(ctx: common.Context, homeDir: string, rawPath: string,
  fileName: string, minBytes: number, label: string): Promise<void> {
  let bytes: Uint8Array;
  try {
    bytes = await ctx.resourceManager.getRawFileContent(rawPath);
  } catch (e) {
    throw new Error('读取内置' + label + '失败：' + (e as Error).message);
  }
  if (bytes.byteLength <= minBytes) {
    throw new Error('内置' + label + '体积异常（' + bytes.byteLength + ' B），已停止落位');
  }
  const zipPath: string = homeDir + '/' + fileName;
  try {
    writeAllBytes(zipPath, bytes);
  } catch (e) {
    throw new Error('写入' + label + '失败：' + (e as Error).message);
  }
  const writtenSize: number = fs.statSync(zipPath).size;
  if (writtenSize !== bytes.byteLength) {
    throw new Error(label + '落盘不完整（' + writtenSize + '/' + bytes.byteLength + ' B）');
  }
}

// 首用落位入口（单飞外壳）：在飞期间并发调用共享同一 promise（防双写 zip，缓存说明见上）；
// 发起者 settle 后清缓存——失败后下次调用重新落位重试（半成品 zip 无 .ready，
// pyRuntimeReady 判 false 重拷）。ctx 可选——门 4 起工具链与设置页经 initPyRuntimeStore
// 捕获的上下文调用（EntryAbility onCreate 注入）；探针页显式传 UI 上下文（同源同值）
export async function ensurePyRuntime(ctx?: common.Context): Promise<string> {
  if (ensurePyRuntimePending !== null) {
    return ensurePyRuntimePending;
  }
  const effCtx: common.Context | undefined = ctx !== undefined ? ctx : pyStoreCtx;
  if (effCtx === undefined) {
    throw new Error('应用上下文未注入，无法准备 Python 运行环境');
  }
  const task: Promise<string> = placePyRuntime(effCtx);
  ensurePyRuntimePending = task;
  try {
    return await task;
  } finally {
    ensurePyRuntimePending = null;
  }
}

// ── libpyengine.so 直通封装（消费面 = 探针页 + exec_python 工具链 + 设置管理页）──

// 应用上下文捕获（照 WorkspaceDbTmp.initWorkspaceTmpStore 先例：EntryAbility onCreate
// 调一次；此后工具执行器与设置页无 UIContext 也能发起落位）
let pyStoreCtx: common.Context | undefined = undefined;

export function initPyRuntimeStore(ctx: common.Context): void {
  pyStoreCtx = ctx;
}

// 运行区目录绝对路径（管理页状态读取用；ctx 未注入回空串——调用方判空展示未就绪）
export function pyRuntimeHomePath(): string {
  if (pyStoreCtx === undefined) {
    return '';
  }
  return pyStoreCtx.filesDir + '/' + PY_HOME_DIR_NAME;
}

// 运行区就绪态（.ready 三件判据非落位形态，纯读；未就绪回 false 不抛）
export function pyRuntimePlaced(): boolean {
  const home: string = pyRuntimeHomePath();
  return home !== '' && pyRuntimeReady(home);
}

// 运行区占用字节数（异步递归求和，只统计本运行区目录；ctx 未注入回 -1 = 未知，调用方
// 如实展示；目录或单件读失败按 0 跳过——统计不中断不造数，两调用方均先有 placed 判定）。
// 2026-11-14 起唯一占用面——原同步版（listFileSync/statSync 逐件遍历数千文件）在管理页
// aboutToAppear 转场关键帧执行会阻塞 UI 线程（决明实测进页卡顿），已撤
export async function pyRuntimeUsageBytesAsync(): Promise<number> {
  const home: string = pyRuntimeHomePath();
  if (home === '') {
    return -1;
  }
  return dirSizeBytesAsync(home);
}

// 目录异步递归求和（fs 异步面；每层并行 stat——同步版数百 ms 的活若逐件 await 串行会
// 放大到秒级；容错单件失败跳过——统计值不因个别不可读件中断）
async function dirSizeBytesAsync(path: string): Promise<number> {
  let names: string[] = [];
  try {
    names = await fs.listFile(path);
  } catch (e) {
    return 0;
  }
  const sizes: number[] = await Promise.all(
    names.map((name: string): Promise<number> => dirEntryBytesAsync(path + '/' + name)));
  let total: number = 0;
  for (const size of sizes) {
    total += size;
  }
  return total;
}

// 单件求和（目录递归取子树、文件取 size；失败跳过回 0——统计不中断）
async function dirEntryBytesAsync(child: string): Promise<number> {
  try {
    const stat: fs.Stat = await fs.stat(child);
    if (stat.isDirectory()) {
      return await dirSizeBytesAsync(child);
    }
    return stat.size;
  } catch (e) {
    return 0;
  }
}

// 旧版本运行区清扫（2026-11-14 存储暴涨修复：目录名随版本串换新，门 3 验证轮 g2~g6 每
// 轮侧载遗留一套 ~115MB 且存储页/快速清理/占用统计均不可见——启动时列 filesDir，凡
// PY_HOME_DIR_PREFIX 前缀且非当前 PY_HOME_DIR_NAME 一律递归删。启动一次非轮询；filesDir
// 读失败按干净态兜底不抛；单目录失败跳过有界自愈，下次启动再清）
export async function sweepLegacyPyRuntimeDirs(ctx: common.Context): Promise<void> {
  let names: string[] = [];
  try {
    names = await fs.listFile(ctx.filesDir);
  } catch (e) {
    return; // filesDir 读失败 = 兜底放弃本轮，不抛
  }
  for (const name of names) {
    if (!name.startsWith(PY_HOME_DIR_PREFIX) || name === PY_HOME_DIR_NAME) {
      continue;
    }
    await removeTreeAsync(ctx.filesDir + '/' + name);
  }
}

// 异步递归删树（后序——官方 rmdir 删非空目录抛 13900032〔d.ts @throws 实核，与
// WorkspaceDb.removeWorkspaceTree 真机实锤同口径〕，先删内容再删目录本体；单件失败跳过
// 继续；每层并行删防数千件串行放大）。独立异步版而非复用同步先例——启动清扫数千次删 IO
// 若同步跑会阻塞主线程拖慢首屏。门 5 起导出（pyexec 域共用：启动清扫 + PyPackages 清包/
// 重建/回滚；目录不存在时静默返回 = 幂等，传文件路径无效——listFile 抛错即 return）。
// ★ 符号链接一律不下降（2026-11-24 两千二百八十七节）：lstat 判链接本身、命中只 unlink
// 链接，与 npm-scan.js 的扫描口径一致——防安装区/运行区被链接带到区外递归删除
export async function removeTreeAsync(absDir: string): Promise<void> {
  // 根自身先判链接：启动清扫的目录名来自 listFile，Node 清空六项之一也可能被替换成链接——
  // listFile 会跟随链接下降，不先拦就会顺着根链接删到目标目录
  try {
    const rootStat: fs.Stat = await fs.lstat(absDir);
    if (rootStat.isSymbolicLink()) {
      try {
        await fs.unlink(absDir);
      } catch (e) {
        // 链接删不掉留给调用方的删后复读判定——绝不下降
      }
      return;
    }
  } catch (e) {
    return; // 不存在 = 目标状态；传文件路径会由下方 listFile 抛错后静默返回
  }
  await removeTreeDirAsync(absDir);
}

// 删真实目录本体（后序；调用方已用 lstat 确认不是符号链接）
async function removeTreeDirAsync(absDir: string): Promise<void> {
  let names: string[] = [];
  try {
    names = await fs.listFile(absDir);
  } catch (e) {
    return; // 目录不存在 = 目标状态
  }
  await Promise.all(
    names.map((name: string): Promise<void> => removeTreeEntryAsync(absDir + '/' + name)));
  try {
    await fs.rmdir(absDir);
  } catch (e) {
    // 根目录本体删不掉（仍有存活句柄等）跳过——内容已尽力清
  }
}

// 删单件（lstat 判类型：真实目录递归删子树；文件与符号链接都只 unlink 自身——链接绝不
// 下降；失败跳过——有界自愈）
async function removeTreeEntryAsync(child: string): Promise<void> {
  try {
    const stat: fs.Stat = await fs.lstat(child);
    if (stat.isDirectory()) {
      await removeTreeDirAsync(child);
    } else {
      await fs.unlink(child);
    }
  } catch (e) {
    // 单件失败跳过——下次启动再清（有界自愈）
  }
}

// 初始化解释器（幂等；homeDir = ensurePyRuntime 返回值）
export function initPyRuntime(homeDir: string): Promise<PyInitOutcome> {
  return pyEngine.init(homeDir);
}

// 执行代码串（Python 全局串行：同一时刻仅一个 exec 在跑，后续排队）
export function execPyCode(code: string, timeoutMs: number): Promise<PyExecOutcome> {
  return pyEngine.exec(code, timeoutMs);
}

// 会话命名空间执行（门 4 主通道：sessionKey = 会话 id 分家顶层变量；cwd = 该次会话临时区
// 绝对路径，native 每轮显式 os.chdir——方案 §2.5 不依赖进程 cwd 残留）
export function execPySession(code: string, timeoutMs: number, sessionKey: string,
  cwd: string): Promise<PyExecOutcome> {
  return pyEngine.exec(code, timeoutMs, sessionKey, cwd);
}

// 协作式取消（不承诺强杀——原生调用阻塞时不能立即中断）
export function cancelPyRun(): void {
  try {
    pyEngine.cancel();
  } catch (e) {
    // native 侧标记失败不阻断（结果兜底带 Canceled 标志——照 JsvmEngine.cancel 同款姿势）
  }
}

// 会话命名空间释放（会话删除级联 best-effort：失败不回滚不阻断删除主流程；解释器未
// 初始化或键不存在时 native 空操作）
export function dropPyNamespacesQuiet(sessionKeys: string[]): void {
  if (sessionKeys.length === 0) {
    return;
  }
  try {
    pyEngine.dropNamespaces(sessionKeys).catch((): void => {
      // best-effort：失败留 hilog 可查、不影响删除主流程
    });
  } catch (e) {
    // 同上——静默不承诺（命名空间余量由 LRU 上限与进程重启兜底回收）
  }
}
