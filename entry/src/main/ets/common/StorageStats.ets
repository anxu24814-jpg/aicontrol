// 本机存储占用统计与清理执行域：官方三值取数 + 自扫四项 + 六分类口径 + 可清理预览/执行 +
// 字节格式化。零 UI——页面（components/settings/StoragePage.ets）只消费本文件的类型与函数。
// 独立成件理由（反碎片下限②例外）：职责一句话 =「本机存储占用统计与清理执行」，不能并入
// AttachmentDb（附件元数据域，不管 cacheDir/壁纸/DB 体积）也不能并入 ExportImport（导入
// 导出域）——独立职责缝。
// 官方口径（《存储空间使用与文件生命周期管理》V1 + 《应用及文件系统空间统计》）：
// · 总占用 = appSize + dataSize（dataSize 已含 cacheSize，**不得再叠加**——官方【应当】）；
// · 六分类互斥且和恒等于总占用：应用本体 appSize / 对话附件 / 数据库 / 壁纸 / 缓存 cacheSize
//   / 其他（= dataSize − 附件 − 数据库 − 壁纸 − **cacheSize**，钳位 ≥ 0）。★ 减数必须含
//   cacheSize：dataSize 已包含它，漏减 = 双重计数、六段之和大于总数；负差 = 扫描口径与系统
//   不一致（取证线索），warn 留痕不静默；
// · 运行日志目录 = hilog.getOutputDir() 动态取（@since 26）——官方文档记 el2/log/hiapplog、
//   真机实测返回应用级 files 下 hiapplog，两者矛盾正是禁硬编码的理由，以 API 返回值为准
//  （实测落点计入卡1「其他」）；做有界清理（保留最近 3 份，cleanSandboxLogs）；
// · 清理范围 = 统计范围（官方【应当】）：出数与实删走同一判定（scanCleanables / clean* /
//   scanSandboxLogBytes 同源，残留附件走 AttachmentDb.collectOrphanFiles 单源）；卡2 清官方
//   cacheSize 口径的 el2 两份（应用级 + 模块级）+ tempDir，★ 应用级 cache 下的 web 子目录
//   **跳过**（那是浏览器数据，归快速清理页独立入口 cleanWebData；漏跳 = 「清理」连带删
//   Cookie/站点数据，越出「可安全清理」承诺）；浏览器数据入口唯一在快速清理页（存储页原
//   卡4 已撤除）；el1 两份不做：真机实测 el1 无缓存目录，且取 el1 路径须临时改写
//   Context.area（官方 FAQ 示例改后未恢复，有副作用）；
// ★ 浏览器数据目录出处与「显示 = 实删」（决明真机报障「toast 说已清理但数字不动」驱动）：
//   官方 FAQ《Web组件如何清除缓存信息》指认 Web 数据根 = 应用级 cache 下 web 子目录
//  （removeCache→web/Cache、removeAllCache→web、clearAllCookiesSync→web/Cookies）。修正前
//   统计的是 files 下 `__arkweb`（另一处内核目录，真机 0700 读不到）而清除落在 cache/web——
//   统计与清除不在同一目录，两侧各自自洽、合起来数字永不动；故把显示与清除一并钉到
//   cache/web（不硬删目录——官方 FAQ 明确「建议使用 Web 提供接口触发清除缓存，不建议
//   使用手动删除目录方式」）。
// · categoryRowsBySize（分类明细按占用降序，组卡行序单源）+ categoryHasManageEntry（分类
//   是否带独立管理页入口，现仅对话附件）——纯函数，断言直跑，页面不另写分支清单。
// 依赖方向：本文件 → AttachmentDb / UsageStatsCalc（单向无环）；扫描全部有界，进页一次
// 调用，非轮询无缓存层。
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { fileIo as fs, storageStatistics } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { AttachmentTotalRow, collectOrphanFiles } from './store/AttachmentDb';
// 按时间清理档位的时间锚点：dayStartMs = 本地自然日零点纯函数（本件 → UsageStatsCalc
// 单向无环）——「近 N 天」= 含今天的最近 N 个本地自然日（用量统计页既有口径）
import { dayStartMs } from './store/UsageStatsCalc';

const DOMAIN: number = 0xDACC;
const TAG: string = 'StorageStats';
// 常驻附件区目录名（与 AttachmentUtil.ATTACH_DIR / AttachmentDb.ATTACH_DIR_NAME 同值——
// 三处互不 import，断言钉一致）
const ATTACH_DIR_NAME: string = 'attachments';
// 壁纸文件前缀（ImageEditUtil 生成 page_background_<t>.jpg / _clean_ / _src_ 三类，天然全覆盖）
const WALLPAPER_PREFIX: string = 'page_background_';
// 沙箱运行日志保留份数（该目录是排障取证资产，只清旧份不全清）
const LOG_KEEP_COUNT: number = 3;
// 浏览器数据目录名（ArkWeb 数据根 = 应用级 cache 下 web 子目录，出处见文件头官方 FAQ 条；
// 扫描一律容错，不存在/不可读按 0 计，不得阻塞页面）
const WEB_DATA_DIR_NAME: string = 'web';

// ── 六分类元数据（key/label/序）──
// ArkTS 禁 build 内匿名字面量数组（10605038），故走类型化返回方法；恒 6 项，序三处同源
//（占比段 = 明细行序），勿在页面另写顺序表
export interface StorageCategory {
  key: string;
  label: string;
}

export function storageCategories(): StorageCategory[] {
  return [
    { key: 'app', label: '应用本体' },
    { key: 'attachments', label: '对话附件' },
    { key: 'database', label: '数据库' },
    { key: 'wallpaper', label: '壁纸' },
    { key: 'cache', label: '缓存' },
    { key: 'other', label: '其他' }
  ];
}

// 依赖官方接口的分类 key（官方三值取不到时这三项显「—」；自扫四项照常显示——官方【应当】
// 「不得把自行扫描的部分目录冒充完整存储占用」的反向兜底：官方值缺位时如实留白不猜测）
export function officialDependentKeys(): string[] {
  return ['app', 'cache', 'other'];
}

// ── 分类行序与入口判据 ──
// 分类是否带独立管理/清理入口（true = 行尾出箭头进独立页；现仅「对话附件」）。判据单源在
// 本函数——页面不另写分支清单；同一动作不设两处入口。分类键与 storageCategories 同源
export function categoryHasManageEntry(key: string): boolean {
  return key === 'attachments';
}

// 组卡行数据：分类明细按占用降序（行序 = 值序）。同值保持分类原序（显式下标 tiebreak——
// 不依赖引擎排序稳定性，ForEach 行序确定不跳动）；官方值缺位的三项按 0 参与排序、显示侧
// 另行留白（「—」在页面组装）
export interface StorageCategoryValue {
  key: string;
  label: string;
  bytes: number;
}

interface IndexedCategoryValue {
  index: number;
  bytes: number;
}

export function categoryRowsBySize(b: StorageBreakdown): StorageCategoryValue[] {
  const categories: StorageCategory[] = storageCategories();
  const values: number[] = categoryBytes(b);
  const indexed: IndexedCategoryValue[] = [];
  for (let i = 0; i < categories.length; i++) {
    indexed.push({ index: i, bytes: values[i] });
  }
  indexed.sort((a: IndexedCategoryValue, b2: IndexedCategoryValue): number =>
    b2.bytes !== a.bytes ? b2.bytes - a.bytes : a.index - b2.index);
  const rows: StorageCategoryValue[] = [];
  for (const item of indexed) {
    rows.push({ key: categories[item.index].key, label: categories[item.index].label,
      bytes: item.bytes });
  }
  return rows;
}

// ── 统计出数 ──
export interface StorageBreakdown {
  appSize: number; // 官方接口（应用安装文件）
  cacheSize: number; // 官方接口（应用缓存）
  dataSize: number; // 官方接口（应用其他数据）
  attachments: number; // 自扫 filesDir/attachments
  database: number; // 自扫 databaseDir（递归）
  wallpaper: number; // 自扫 filesDir 顶层 page_background_* 前缀
  other: number; // 派生余量（构成未知）
  total: number; // appSize + dataSize
  officialOk: boolean; // 官方三值是否取到（false = 三项显「—」，自扫四项照常）
}

// 「其他」余量（纯函数——sse-assert 直跑）：减数含 cacheSize（dataSize 已含它）；钳位 ≥ 0
export function otherBytes(dataSize: number, attachments: number, database: number,
  wallpaper: number, cacheSize: number): number {
  const rest: number = dataSize - attachments - database - wallpaper - cacheSize;
  return rest > 0 ? rest : 0;
}

// 总占用（纯函数）：appSize + dataSize——dataSize 已含缓存，勿再叠加 cacheSize
export function totalBytes(appSize: number, dataSize: number): number {
  return appSize + dataSize;
}

// 六分类值（序 = storageCategories 序；占比段/明细行/自洽校验三处同源）
export function categoryBytes(b: StorageBreakdown): number[] {
  return [b.appSize, b.attachments, b.database, b.wallpaper, b.cacheSize, b.other];
}

// 目录内文件字节和（平铺，可选前缀过滤；目录不存在/单项失败按 0 计——统计不因单点异常整页失败）
function sumDirBytes(dir: string, prefix: string): number {
  let sum: number = 0;
  try {
    const names: string[] = fs.listFileSync(dir);
    for (const name of names) {
      if (prefix !== '' && !name.startsWith(prefix)) {
        continue;
      }
      try {
        const stat: fs.Stat = fs.statSync(dir + '/' + name);
        if (!stat.isDirectory()) {
          sum += stat.size;
        }
      } catch {
        // 单项失败跳过（并发删除等），按 0 计
      }
    }
  } catch {
    // 目录不存在 = 0（目标状态）
  }
  return sum;
}

// 目录递归字节和（depth 限深——databaseDir 只需一层：rdb 子目录 + 顶层 -wal/-shm；有界防深递归）
function sumTreeBytes(dir: string, depth: number): number {
  let sum: number = 0;
  try {
    const names: string[] = fs.listFileSync(dir);
    for (const name of names) {
      const path: string = dir + '/' + name;
      try {
        const stat: fs.Stat = fs.statSync(path);
        if (stat.isDirectory()) {
          if (depth > 0) {
            sum += sumTreeBytes(path, depth - 1);
          }
        } else {
          sum += stat.size;
        }
      } catch {
        // 单项失败跳过
      }
    }
  } catch {
    // 目录不存在 = 0
  }
  return sum;
}

// 六分类统计（进页一次调用；全部有界扫描——三处目录列举 + 一次官方接口调用，无全表查询）
export async function readStorageBreakdown(ctx: common.Context): Promise<StorageBreakdown> {
  const attachments: number = sumDirBytes(ctx.filesDir + '/' + ATTACH_DIR_NAME, '');
  const database: number = sumTreeBytes(ctx.databaseDir, 1);
  const wallpaper: number = sumDirBytes(ctx.filesDir, WALLPAPER_PREFIX);
  let appSize: number = 0;
  let cacheSize: number = 0;
  let dataSize: number = 0;
  let officialOk: boolean = true;
  try {
    const stats: storageStatistics.BundleStats = await storageStatistics.getCurrentBundleStats();
    appSize = stats.appSize;
    cacheSize = stats.cacheSize;
    dataSize = stats.dataSize;
  } catch (e) {
    // 官方值缺位不拖垮整页：三项显「—」、自扫四项照常（P0-1 不静默、不假装成功）
    officialOk = false;
    hilog.error(DOMAIN, TAG, '官方存储统计读取失败（应用本体/缓存/其他显「—」）：%{public}s',
      (e as Error).message);
  }
  // 出数单源 = otherBytes 纯函数（★ 此处曾内联同式，断言只测纯函数、实现漏减 cacheSize 时
  // 全绿零红；改调用后纯函数断言即覆盖真实出数路径，另有源码在位断言防回潮）；负差留痕用
  // 扫描合计与 dataSize 之差（otherBytes 已钳位，不能反推原值）
  const scanned: number = attachments + database + wallpaper + cacheSize;
  if (officialOk && scanned > dataSize) {
    // 负差 = 某分类扫描口径与系统不一致（取证线索，不静默；钳位后按 0 处理）
    hilog.warn(DOMAIN, TAG, '分类扫描合计超出 dataSize %{public}d 字节（钳位为 0，口径待查）',
      scanned - dataSize);
  }
  return {
    appSize: appSize,
    cacheSize: cacheSize,
    dataSize: dataSize,
    attachments: attachments,
    database: database,
    wallpaper: wallpaper,
    other: officialOk ? otherBytes(dataSize, attachments, database, wallpaper, cacheSize) : 0,
    total: officialOk ? totalBytes(appSize, dataSize) : 0,
    officialOk: officialOk
  };
}

// ── 可清理预览与执行（范围 = 统计范围：应用临时文件 + 残留附件文件 + 运行日志旧份）──
// ★ 浏览器数据**不进本预览**：它是「占用」而非「可清量」，清除走快速清理页独立入口全量
// 执行，占用读数由 QuickClean 经 scanWebDataBytes 现取
export interface CleanPreview {
  cacheBytes: number;
  orphanBytes: number;
  orphanCount: number;
  logBytes: number; // 可清理的运行日志字节（保留 LOG_KEEP_COUNT 份之外的余量，「清理」键覆盖）
  logCount: number; // 可清理份数（确认框文案用）
}

// 清理结果（bytes = 实际释放字节；failed = 失败项数——best-effort 下 > 0 时调用方 toast 带
// 失败计数，不静默）
export interface CleanResult {
  bytes: number;
  failed: number;
}

// 目录遍历（预览与实删唯一入口——remove=false 只累计、true 边累计边删；「显示 = 实删」由
// 同一遍历口径保证；目录本身保留，best-effort 单项失败跳过继续）。skipName = 本级要跳过的
// 子目录名（空串 = 不跳；只在传参那一级生效，递归不再传——免得把更深处同名目录一并跳过；
// 用途 = cleanCache / scanCleanables 对 web 子目录的跳过）
function walkDir(dir: string, remove: boolean, acc: CleanResult, skipName: string = ''): void {
  try {
    const names: string[] = fs.listFileSync(dir);
    for (const name of names) {
      if (skipName !== '' && name === skipName) {
        continue;
      }
      const path: string = dir + '/' + name;
      try {
        const stat: fs.Stat = fs.statSync(path);
        if (stat.isDirectory()) {
          walkDir(path, remove, acc);
          if (remove) {
            fs.rmdirSync(path);
          }
        } else {
          if (remove) {
            fs.unlinkSync(path);
          }
          acc.bytes += stat.size;
        }
      } catch {
        acc.failed++;
      }
    }
  } catch {
    // 目录不存在 = 干净（目标状态）
  }
}

// 应用级 cache 目录（官方 cacheSize 口径含应用级 base/cache，而 UIAbilityContext.cacheDir
// 只到模块级 base/haps/<模块>/cache，够不着；ApplicationContext.cacheDir 才是应用级——取法 =
// Context 实例方法 getApplicationContext〔@since 9〕，不用 application.createModuleContext
//（官方 NOTE 标注其涉及资源查询与初始化、可能耗时）。失败返回空串 = 调用方跳过该份）
function appCacheDirOf(ctx: common.Context): string {
  try {
    return ctx.getApplicationContext().cacheDir;
  } catch {
    return '';
  }
}

// 沙箱运行日志目录（hilog.getOutputDir 动态取 @since 26，禁硬编码理由见文件头；返回空串 =
// 该项按无日志处理）
function sandboxLogDir(): string {
  try {
    return hilog.getOutputDir();
  } catch {
    return '';
  }
}

// 沙箱日志文件条目（列目录用；mtime 单位秒——AttachmentDb 在途保护闸同口径）
interface LogFileEntry {
  path: string;
  mtime: number;
}

// 沙箱日志文件清单（mtime 降序新的在前）。只收平铺文件、子目录跳过（真机实测该目录无子目录，
// 不递归防误删）；列目录失败返回空数组
function listLogFiles(): string[] {
  const dir: string = sandboxLogDir();
  if (dir === '') {
    return [];
  }
  const entries: LogFileEntry[] = [];
  try {
    const names: string[] = fs.listFileSync(dir);
    for (const name of names) {
      const filePath: string = dir + '/' + name;
      try {
        const stat: fs.Stat = fs.statSync(filePath);
        if (!stat.isDirectory()) {
          entries.push({ path: filePath, mtime: stat.mtime });
        }
      } catch {
        // 单项失败跳过
      }
    }
  } catch {
    return [];
  }
  entries.sort((a: LogFileEntry, b: LogFileEntry): number => b.mtime - a.mtime);
  return entries.map((e: LogFileEntry): string => e.path);
}

// 可清理日志（保留份数之外的旧份）清单 + 字节合计，一次列出算出（预览出数与实删清单同源，
//「显示 = 实删」的结构保证；stat 单项失败按 0 计）
interface LogCleanable {
  paths: string[];
  bytes: number;
}

function logCleanables(): LogCleanable {
  const logs: string[] = listLogFiles();
  const paths: string[] = [];
  let bytes: number = 0;
  for (let i = LOG_KEEP_COUNT; i < logs.length; i++) {
    paths.push(logs[i]);
    try {
      bytes += fs.statSync(logs[i]).size;
    } catch {
      // 单项失败按 0 计
    }
  }
  return { paths: paths, bytes: bytes };
}

// 浏览器数据目录绝对路径（应用级 cache 下 web 子目录，出处见文件头；取不到应用级 cache
// 时返回空串 = 调用方按 0 跳过，清除照常走 API 不受影响）
function webDataDir(ctx: common.Context): string {
  const base: string = appCacheDirOf(ctx);
  return base === '' ? '' : base + '/' + WEB_DATA_DIR_NAME;
}

// 临时缓存清理：覆盖官方 cacheSize 口径的 el2 两份（应用级 + 模块级）+ tempDir，web 子目录
// 跳过与 el1 不做的口径见文件头。★ 隐私会话临时附件（cacheDir/attachments）同样被清，
// 语义 = 临时缓存——隐私附件本就「退出会话即删」，且进入本页必然离开会话页；勿当 bug 修。
// 不动应用级 files（运行日志在其下，由 cleanSandboxLogs 单独负责）、数据库与偏好目录。
// ★ ArkWeb 内核缓存不在此处清：removeAllCache 随浏览器数据一并归快速清理页（cleanWebData）
//——官方 FAQ 指认它清的正是 cache/web，与这里的跳过同域；放两处会出现「卡2 清了浏览器
// 缓存、数字却记在别处」的错位
export async function cleanCache(ctx: common.Context): Promise<CleanResult> {
  const acc: CleanResult = { bytes: 0, failed: 0 };
  walkDir(ctx.cacheDir, true, acc);
  walkDir(ctx.tempDir, true, acc);
  const appCache: string = appCacheDirOf(ctx);
  if (appCache !== '' && appCache !== ctx.cacheDir) {
    walkDir(appCache, true, acc, WEB_DATA_DIR_NAME);
  }
  return acc;
}

// 残留附件文件清理：判定单源 = AttachmentDb.collectOrphanFiles（含在途保护闸——本进程内
// 新建的已选未发/发送中附件一律保护），故卡面显示数与实删数必然一致
export async function cleanOrphanAttachments(ctx: common.Context,
  db: relationalStore.RdbStore): Promise<CleanResult> {
  const acc: CleanResult = { bytes: 0, failed: 0 };
  const orphans: string[] = await collectOrphanFiles(ctx, db);
  for (const rel of orphans) {
    const path: string = ctx.filesDir + '/' + rel;
    try {
      const size: number = fs.statSync(path).size;
      fs.unlinkSync(path);
      acc.bytes += size;
    } catch {
      // 单文件失败跳过——下次启动收敛自愈（有界）
      acc.failed++;
    }
  }
  return acc;
}

// 运行日志旧份清理（保留最近 LOG_KEEP_COUNT 份；先 flush 再删——残留缓冲在删除后回写会
// 造成「清空后又出现」的假象。当前进程正在写的日志 mtime 最新，天然落在保留份内。返回
// bytes = 实删字节、failed = 失败项数）
export function cleanSandboxLogs(): CleanResult {
  const acc: CleanResult = { bytes: 0, failed: 0 };
  try {
    hilog.flush();
  } catch {
    // flush 失败不中断删除（best-effort）
  }
  const cleanable: LogCleanable = logCleanables();
  for (const path of cleanable.paths) {
    try {
      const size: number = fs.statSync(path).size;
      fs.unlinkSync(path);
      acc.bytes += size;
    } catch {
      // 单文件失败跳过——下次清理再试（有界）
      acc.failed++;
    }
  }
  return acc;
}

// 运行日志可清理量（保留份数之外的字节和；与 cleanSandboxLogs 走同一 logCleanables 判定，
//「显示 = 实删」）
export function scanSandboxLogBytes(): number {
  return logCleanables().bytes;
}

// 浏览器数据清理（三官方同步 API，均在本地 d.ts 核实：WebviewController.removeAllCache
//〔@since 18，官方 FAQ 明示「Web 组件未初始化时也可调用」，清 base/cache/web 下缓存〕+
// WebStorage.deleteAllData〔@since 9，清 LocalStorage/IndexedDB/Web SQL 等站点数据；★ d.ts
// 类注要求「Web 组件已加载」才生效，未加载时可能空转——故清除能力不依赖它单点：removeAllCache
// 与 clearAllCookiesSync 不设此前提〕+ WebCookieManager.clearAllCookiesSync〔@since 11，清
// Cookie〕）。不硬删目录——官方 FAQ 原文「建议使用 Web 提供接口触发清除缓存，不建议使用
// 手动删除目录方式」。三 API 各 try/catch，失败 failed++ 后继续，best-effort 不上抛。
// ★ 只在快速清理页「清除浏览器数据」项调用（唯一调用点，存储页原卡4 已撤除），禁止并入
//「清理」主键（用户点「清理」不预期各网站登录态消失）
export function cleanWebData(): CleanResult {
  const acc: CleanResult = { bytes: 0, failed: 0 };
  try {
    webview.WebviewController.removeAllCache(true);
  } catch {
    acc.failed++;
  }
  try {
    webview.WebStorage.deleteAllData();
  } catch {
    acc.failed++;
  }
  try {
    webview.WebCookieManager.clearAllCookiesSync();
  } catch {
    acc.failed++;
  }
  return acc;
}

// 浏览器数据占用（应用级 cache 下 web 递归字节和，限深 3——该目录下十余个子目录、层级
// 不深，限深是「有界扫描」红线的落点）。★ 目录口径与 cleanWebData 的清除范围同域（「显示 =
// 实删」的结构保证）。目录缺失/不可读按 0
export function scanWebDataBytes(ctx: common.Context): number {
  const dir: string = webDataDir(ctx);
  return dir === '' ? 0 : sumTreeBytes(dir, 3);
}

// 可清理预览（卡面各行出数；与 clean*/scan* 同源判定——官方【应当】「清理范围与统计范围
// 一致」；一次扫描返回，避免调用方两处各扫一遍）
export async function scanCleanables(ctx: common.Context,
  db: relationalStore.RdbStore): Promise<CleanPreview> {
  const cacheAcc: CleanResult = { bytes: 0, failed: 0 };
  walkDir(ctx.cacheDir, false, cacheAcc);
  walkDir(ctx.tempDir, false, cacheAcc);
  const appCache: string = appCacheDirOf(ctx);
  if (appCache !== '' && appCache !== ctx.cacheDir) {
    // 与 cleanCache 同一跳过口径（「显示 = 实删」：预览不把浏览器数据算进卡2，实删也不碰它）
    walkDir(appCache, false, cacheAcc, WEB_DATA_DIR_NAME);
  }
  const orphans: string[] = await collectOrphanFiles(ctx, db);
  let orphanBytes: number = 0;
  for (const rel of orphans) {
    try {
      orphanBytes += fs.statSync(ctx.filesDir + '/' + rel).size;
    } catch {
      // 单项失败按 0 计（实删侧同样 best-effort）
    }
  }
  const logCleanable: LogCleanable = logCleanables();
  return {
    cacheBytes: cacheAcc.bytes,
    orphanBytes: orphanBytes,
    orphanCount: orphans.length,
    logBytes: logCleanable.bytes,
    logCount: logCleanable.paths.length
  };
}

// 字节格式化（B / KB / MB / GB，一位小数；<1KB 显 B；0 显 0 B；负值/NaN 按 0 B 兜底）
export function formatBytes(bytes: number): string {
  if (!(bytes >= 1)) {
    return '0 B';
  }
  if (bytes < 1024) {
    return bytes + ' B';
  }
  const kb: number = bytes / 1024;
  if (kb < 1024) {
    return kb.toFixed(1) + ' KB';
  }
  const mb: number = kb / 1024;
  if (mb < 1024) {
    return mb.toFixed(1) + ' MB';
  }
  return (mb / 1024).toFixed(1) + ' GB';
}

// ── 聊天附件按时间清理·档位单源（档位语义与文案归本域，SQL 与事务在 AttachmentDb，
//    页面零自拼）──
// 档位 key（禁裸字符串；页面行卡、cutoff 派生、确认文案三处同引）
export const ATTACH_CLEAN_TODAY: string = 'today';
export const ATTACH_CLEAN_7D: string = 'd7';
export const ATTACH_CLEAN_30D: string = 'd30';
export const ATTACH_CLEAN_ALL: string = 'all';

// 档位条目（ArkTS 禁 build 内匿名字面量数组——类型化返回方法）。★ 档位语义 = **保留窗口**
//（「今天」= 保留今天的、删除今天 0 点以前的——Telegram「保留媒体」同款惯例）；行序 =
// 今天 → 近7天 → 近30天 → 全部（保留窗口从短到长递进、「全部」零保留破坏性最大垫底）
//——序 = 面板行序，勿在页面另写顺序表
export interface AttachCleanItem {
  key: string;
  label: string;
  desc: string;
}

export function attachCleanItems(): AttachCleanItem[] {
  return [
    { key: ATTACH_CLEAN_TODAY, label: '今天',
      desc: '保留今天的附件，删除今天 0 点以前的全部附件。' },
    { key: ATTACH_CLEAN_7D, label: '近7天',
      desc: '保留最近 7 天的附件，删除 7 天以前的全部附件。' },
    { key: ATTACH_CLEAN_30D, label: '近30天',
      desc: '保留最近 30 天的附件，删除 30 天以前的全部附件。' },
    { key: ATTACH_CLEAN_ALL, label: '全部',
      desc: '删除本机全部聊天附件，不区分时间。' }
  ];
}

// 档位 → 时间界线（纯函数，assert-attach-domain 关系钉直跑）：today → dayStartMs(now, 0)
// / d7 → dayStartMs(now, 6)（含今天共 7 个自然日）/ d30 → dayStartMs(now, 29)（含今天共
// 30 个自然日）/ all → null（无谓词全表）。返回值 = 预览与实删共用的 cutoffMs（谓词 <
// cutoff 即「早于界线」被删——严格小于，恰等界线保留）。非法 key 抛错（静默返 null 会把
// 误传键当「全部档」全删，P0-1 不静默）
export function attachCleanCutoffMs(key: string, nowMs: number): number | null {
  if (key === ATTACH_CLEAN_TODAY) {
    return dayStartMs(nowMs, 0);
  }
  if (key === ATTACH_CLEAN_7D) {
    return dayStartMs(nowMs, 6);
  }
  if (key === ATTACH_CLEAN_30D) {
    return dayStartMs(nowMs, 29);
  }
  if (key === ATTACH_CLEAN_ALL) {
    return null;
  }
  throw new Error('未知的清理档位：' + key);
}

// 清理确认文案单源（纯函数——页面不得自拼；preview = 开面板时同一 cutoff 的读数快照，
//「将删除 N 个」即实删数）。结构 = 范围句（预告删多少与保留多少）+ 四档共用的后果块（附件
// 条消失形态 + 在途会话观感 + 不可逆句）。全部档额外预告生成中的会话一并清理（不引入状态
// 排除判据）
export function attachCleanConfirmMessage(key: string, preview: AttachmentTotalRow): string {
  const sizeText: string = formatBytes(preview.bytes);
  const aftermath: string = '删除后消息里的附件条不再显示，文字里的附件标注保留。' +
    '当前打开的会话里附件条仍在，点开会提示文件已不在本机。删除后无法恢复。';
  if (key === ATTACH_CLEAN_TODAY) {
    return '将删除今天 0 点以前的 ' + preview.count + ' 个聊天附件，共 ' + sizeText +
      '。今天的附件保留。' + aftermath;
  }
  if (key === ATTACH_CLEAN_7D) {
    return '将删除 7 天以前的 ' + preview.count + ' 个聊天附件，共 ' + sizeText +
      '。最近 7 天的保留。' + aftermath;
  }
  if (key === ATTACH_CLEAN_30D) {
    return '将删除 30 天以前的 ' + preview.count + ' 个聊天附件，共 ' + sizeText +
      '。最近 30 天的保留。' + aftermath;
  }
  if (key === ATTACH_CLEAN_ALL) {
    return '将删除本机全部 ' + preview.count + ' 个聊天附件，共 ' + sizeText +
      '。生成中的会话也会一并清理。' + aftermath;
  }
  throw new Error('未知的清理档位：' + key);
}
