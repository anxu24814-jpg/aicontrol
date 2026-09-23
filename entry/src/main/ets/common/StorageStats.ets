// 本机存储占用统计与清理执行域（2026-09-09 附件全量落盘第二轮·存储管理页，任务书-存储
// 管理页-20260909）：官方三值取数 + 自扫四项 + 六分类口径 + 可清理预览/执行 + 字节格式化。
// 零 UI——页面（components/settings/StoragePage.ets）只消费本文件的类型与函数。
// 为何独立成文件（反碎片下限②「并入既有同域文件优先」的例外理由）：职责一句话 = 「本机
// 存储占用统计与清理执行」；不能并入 AttachmentDb（附件元数据域，管表行与收敛，不管
// cacheDir/壁纸/DB 体积），也不能并入 ExportImport（导入导出域）——属独立职责缝。
// 官方口径（《存储空间使用与文件生命周期管理》V1 + 《应用及文件系统空间统计》，本文件为落点）：
// · 总占用 = appSize + dataSize（dataSize 已含 cacheSize，**不得再叠加**——官方【应当】）；
// · 六分类互斥且和恒等于总占用：应用本体 appSize / 对话附件 / 数据库 / 壁纸 / 缓存 cacheSize
//   / 其他（= dataSize − 附件 − 数据库 − 壁纸 − **cacheSize**，钳位 ≥ 0）。
//   ★ 减数必须含 cacheSize：dataSize 已包含它，漏减 = 双重计数、六段之和大于总数（真机立刻
//   可见）；负差 = 某分类扫描口径与系统不一致，属取证线索——warn 留痕不静默（§2.1 坑 1）；
// · 运行日志目录 = hilog.getOutputDir() 动态取（@since 26）：官方文档记 el2/log/hiapplog，
//   真机实测（2026-09-21）返回应用级 files 下 hiapplog——两者矛盾正是禁硬编码的理由，以
//   API 返回值为准；实测落点在 files 下即属 dataSize 口径（计入卡1「其他」），2026-09-21
//   起做有界清理（保留最近 3 份，cleanSandboxLogs——此前只增不减）；
// · 清理范围 = 统计范围（官方【应当】）：卡面各行（卡2 三行 + 卡4）出数与实删走同一判定
//   （scanCleanables / clean* / scanSandboxLogBytes 同源，残留附件走 AttachmentDb.
//   collectOrphanFiles 单源）；卡2 清官方 cacheSize 口径的 el2 两份（应用级 + 模块级）
//   + tempDir，★ 其中应用级 cache 下的 web 子目录**跳过**（那是浏览器数据，归卡4 独立
//   入口，见 cleanWebData；漏跳 = 「清理」连带删掉 Cookie/站点数据，越出「可安全清理」
//   的用户可见承诺）；卡4 清浏览器数据根 base/cache/web 三官方 API——el1 两份不做：
//   真机实测 el1 无缓存目录，且取 el1 路径须临时改写 Context.area（官方 FAQ 示例改后
//   未恢复，有副作用），与收益不成比例。
// ★ 浏览器数据目录出处与「显示 = 实删」（2026-09-21 浏览器数据口径修正笔，决明真机报障
//   「点清除有 toast 说已清理，但卡内数字与总占用都不变」）：官方 FAQ《Web组件如何清除缓存
//   信息》指认 Web 数据根 = 应用级 cache 下 web 子目录（removeCache→web/Cache、
//   removeAllCache→web、clearAllCookiesSync→web/Cookies）。此前卡4 统计的是 files 下
//   `__arkweb`（另一处内核目录，名字与作用官方文档未载、真机 0700 读不到内容），而清除动作
//   落在 cache/web——统计与清除根本不在同一目录，两侧各自自洽、合起来数字永不动：
//   这正是官方【应当】「清理范围与统计范围一致」的反面，故本笔把卡4 的显示与清除一并钉到
//   cache/web 上（不硬删目录：官方 FAQ 明确「建议使用 Web 提供接口触发清除缓存，不建议
//   使用手动删除目录方式」）。
// 依赖方向：本文件 → AttachmentDb（collectOrphanFiles 判定单源；AttachmentDb 不 import 本
// 文件，无环）；扫描全部有界（目录列举 + 一次全表查询），进页一次调用，非轮询无缓存层。
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { fileIo as fs, storageStatistics } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { collectOrphanFiles } from './store/AttachmentDb';

const DOMAIN: number = 0xDACC;
const TAG: string = 'StorageStats';
// 常驻附件区目录名（与 AttachmentUtil.ATTACH_DIR / AttachmentDb.ATTACH_DIR_NAME 同值——
// 三处互不 import 拼接，sse-assert 断言钉一致）
const ATTACH_DIR_NAME: string = 'attachments';
// 壁纸文件前缀（ImageEditUtil 生成 page_background_<t>.jpg / _clean_ / _src_ 三类，天然全覆盖）
const WALLPAPER_PREFIX: string = 'page_background_';
// 沙箱运行日志保留份数（卡2「运行日志」清理后保留最近 N 份——排障通常只看当前进程日志，
// 该目录是排障取证资产，只清旧份不全清）
const LOG_KEEP_COUNT: number = 3;
// 浏览器数据目录名（ArkWeb 数据根，位于应用级 cache 下）。出处 = 官方 FAQ《Web组件如何清除
// 缓存信息》三处指认：removeCache 清 `base/cache/web/Cache`、removeAllCache 清 `base/cache/web`、
// clearAllCookiesSync 对应 `base/cache/web/Cookies`——缓存、Cookie 与站点数据全在应用级 cache
// 的 web 子目录下，不在 files。扫描一律容错，不存在/不可读按 0 计，不得阻塞页面。
const WEB_DATA_DIR_NAME: string = 'web';

// ── 六分类元数据（key/label/序）──
// ArkTS 禁 build 内匿名对象字面量数组（10605038），故走类型化返回方法；恒 6 项，序 = 占比
// 段序 = 明细行序（三处同源，勿在页面另写顺序表）
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
  // 出数单源 = otherBytes 纯函数（★ 2026-09-09 自检轮修复：此前此处内联同式，断言只测
  // 纯函数、实现改错不报警——实测「实现漏减 cacheSize」753 断言全绿零红；改调用后纯函数
  // 断言即覆盖真实出数路径，另有源码在位断言防回潮）；负差留痕用扫描合计与 dataSize 之差
  // （otherBytes 已钳位，不能反推原值）
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

// ── 可清理预览与执行（范围 = 统计范围：应用临时文件 + 残留附件文件 + 运行日志旧份 +
//    浏览器数据〔占用口径，清除走卡4 独立入口〕）──
export interface CleanPreview {
  cacheBytes: number;
  orphanBytes: number;
  orphanCount: number;
  logBytes: number; // 可清理的运行日志字节（保留 LOG_KEEP_COUNT 份之外的余量，「清理」键覆盖）
  logCount: number; // 可清理份数（确认框文案用）
  webBytes: number; // 浏览器数据占用（非可清量）——清除走卡4 独立入口全量执行，该域
  //                  「显示 = 实删」表现为「占用 = 清除范围」
}

// 清理结果（bytes = 实际释放字节；failed = 失败项数——best-effort 下 > 0 时调用方 toast 带
// 失败计数，不静默）
export interface CleanResult {
  bytes: number;
  failed: number;
}

// 目录遍历（预览与实删唯一入口——remove=false 只累计字节、true 边累计边删；「显示 = 实删」
// 由同一遍历口径保证；目录本身保留，best-effort 单项失败跳过继续，与 removeAttachmentFiles
// 同口径）。skipName = 本级要跳过的子目录名（空串 = 不跳；只在传参那一级生效，递归不再传，
// 免得把更深处同名目录一并跳过）——用途见 cleanCache / scanCleanables 对 web 子目录的跳过
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

// 应用级 cache 目录（官方 cacheSize 口径含应用级 base/cache，而 UIAbilityContext 的
// cacheDir 只到模块级 base/haps/<模块>/cache，够不着；ApplicationContext.cacheDir 才是
// 应用级。取法 = Context 实例方法 getApplicationContext〔@since 9〕，不用
// application.createModuleContext——官方 NOTE 标注其涉及资源查询与初始化、可能耗时，
// 避免频繁调用。失败返回空串 = 调用方跳过该份）
function appCacheDirOf(ctx: common.Context): string {
  try {
    return ctx.getApplicationContext().cacheDir;
  } catch {
    return '';
  }
}

// 沙箱运行日志目录（hilog.getOutputDir 动态取，@since 26，禁硬编码——官方文档与真机实测
// 落点矛盾，以 API 返回值为准；hilog 输出类型为 DEFAULT 时返回空串 = 该项按无日志处理）
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
// 「显示 = 实删」的结构保证；stat 单项失败按 0 计——扫描不因单点异常失真到抛错）
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

// 浏览器数据目录绝对路径（应用级 **cache** 下的 web 子目录——官方 FAQ 三处指认的 Web 数据根；
// 取不到应用级 cache 时返回空串 = 调用方按 0 跳过、清除照常走 API 不受影响）
function webDataDir(ctx: common.Context): string {
  const base: string = appCacheDirOf(ctx);
  return base === '' ? '' : base + '/' + WEB_DATA_DIR_NAME;
}

// 临时缓存清理：覆盖官方 cacheSize 口径的 el2 两份（应用级 + 模块级）+ tempDir，★ 应用级
// cache 下的 web 子目录**跳过**（浏览器数据归卡4；「清理」的用户可见承诺是「不影响已发送的
// 消息」且不登出各网站，连带删 Cookie 即违背——2026-09-21 口径修正笔收口）；el1 两份不做
// （真机实测 el1 无缓存目录，取 el1 须改写 Context.area 有副作用，与收益不成比例）。
// ★ 隐私会话临时附件（cacheDir/attachments）同样被清，语义 = 临时缓存——隐私附件本就
// 「退出会话即删」，且进入本页必然离开会话页；勿当 bug 修。不动应用级 files（运行日志在
// 其下，由 cleanSandboxLogs 单独负责）、数据库与偏好目录。
// ★ ArkWeb 内核缓存不在此处清：removeAllCache 随浏览器数据一并归到卡4（cleanWebData）——
// 官方 FAQ 指认它清的正是 cache/web，与这里的跳过同域；放两处会出现「卡2 清了浏览器缓存、
// 数字却记在卡4」的错位。
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

// 运行日志旧份清理（保留最近 LOG_KEEP_COUNT 份；先 flush 再删——LogPage.clearSandboxLogs
// 同源教训：残留缓冲在删除后回写会造成「清空后又出现」的假象。该目录是排障取证资产，故只清
// 旧份不全清；当前进程正在写的日志 mtime 最新，天然落在保留份内。返回 bytes = 实删字节、
// failed = 失败项数）
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

// 运行日志可清理量（= 保留份数之外的字节和）。与 cleanSandboxLogs 走同一 logCleanables
// 判定，「显示 = 实删」；单项 stat 失败按 0 计——扫描不因单点异常失真到抛错
export function scanSandboxLogBytes(): number {
  return logCleanables().bytes;
}

// 浏览器数据清理（三官方同步 API 全量，均在本地 d.ts 核实：WebviewController.removeAllCache
// 〔@since 18，官方 FAQ 明示「Web 组件未初始化时也可调用」，清 base/cache/web 下缓存文件〕+
// WebStorage.deleteAllData〔@since 9，清 LocalStorage/IndexedDB/Web SQL 等站点数据；★ d.ts
// 类注要求「Web 组件已加载」才生效，未加载时可能空转——故本函数的清除能力不依赖它单点：
// removeAllCache 与 clearAllCookiesSync 不设此前提〕+ WebCookieManager.clearAllCookiesSync
// 〔@since 11，清 Cookie〕）。不硬删目录——官方 FAQ 原文「建议使用 Web 提供接口触发清除缓存，
// 不建议使用手动删除目录方式」。三 API 各 try/catch，失败 failed++ 后继续，best-effort 不
// 上抛。★ 只在卡4 独立入口调用，禁止并入「清理」主键（用户点「清理」不预期各网站登录态消失）
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

// 浏览器数据占用（应用级 cache 下 web 递归字节和，限深 3——该目录下 Cache/Cookies/
// Local Storage 等十余个子目录、层级不深，限深是「有界扫描」红线的落点）。★ 目录口径 = 官方
// FAQ 指认的 Web 数据根，与 cleanWebData 的清除范围同域（「显示 = 实删」的结构保证；此前测
// files 下 `__arkweb` 与清除范围分家，数字永不动）。目录缺失/不可读按 0
export function scanWebDataBytes(ctx: common.Context): number {
  const dir: string = webDataDir(ctx);
  return dir === '' ? 0 : sumTreeBytes(dir, 3);
}

// 可清理预览（卡面各行出数；与 clean* / scan* 同源判定——官方【应当】「清理范围与统计
// 范围一致」；四项数据一次扫描返回，避免调用方两处各扫一遍）
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
    logCount: logCleanable.paths.length,
    webBytes: scanWebDataBytes(ctx)
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
