// 「运行日志」页数据层（2026-08-21 自 LogPage.ets 拆出，拆分规则见 LogPage.ets 头注释）：
// 只负责日志的「获取与导出」——崩溃事件订阅注册与拉取、hilog 沙箱报错日志读取过滤、
// 系统保存对话框导出写文件。纯工具函数：参数进、返回值/异常出，不持有任何 UI 状态，
// 不发 toast（提示统一由 LogPage 发，沉浸光感材质参数只在 UI 层解析）。
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hiAppEvent, hilog } from '@kit.PerformanceAnalysisKit';

// 刷新时读取的日志时间窗（秒）：7 天内的沙箱日志文件（系统按文件分片轮转）
export const LOG_WINDOW_SECONDS: number = 7 * 24 * 3600;
// 报错日志最大显示行数：只取尾部 N 行防长文本渲染卡顿（2026-08-21 决明要求 200 → 500）
export const MAX_ERROR_LINES: number = 500;
// 沙箱日志存储上限（字节）：2MB（2026-09-04 决明定稿——落盘自当日起进程级常开
//（EntryAbility.onCreate），日常量级小（静态盘点：INFO 点位稀疏、流式路径无高频日志），
// 2MB 仍远低于沙箱压力；防堆积 = 启动 + 进日志页两次自检修剪（pruneLogFiles）——系统
// 分片轮转未证实配额/物理删除，应用自管上限）
export const MAX_LOG_STORAGE_BYTES: number = 1024 * 1024 * 2;
// hilog 落盘行级别过滤：警告 WARN(W)/错误 ERROR(E)/致命 FATAL(F) 单字母独立 token
// （hilog 行格式级别为独立列，前后空格分隔；2026-08-21 决明要求警告也算「报错」）
const ERROR_LINE_RE: RegExp = / (E|F|W) /;
// 崩溃事件观察者名（d.ts 仅声明 name 唯一、未承诺同名重复注册覆盖——调用方须保证
// 注册/注销成对或幂等守卫，见 LogPage.aboutToAppear 的判空防御，2026-08-22 审查订正）
const CRASH_WATCHER_NAME: string = 'logPageCrashWatcher';

// 崩溃订阅（2026-08-21 自检补成对释放）：watcher 是 addWatcher 入参对象（removeWatcher 需要
// 同一对象，官方 removeWatcher(watcher: Watcher) 签名——只保留 holder 无法注销，每次进入
// 日志页会累积进程级 watcher（无界增长））；holder 是事件拉取句柄（takeNext）
export interface CrashSubscription {
  watcher: hiAppEvent.Watcher;
  holder: hiAppEvent.AppEventPackageHolder;
}

// 注册崩溃事件订阅（进程级；幂等由调用方保证——LogPage.aboutToAppear 判空防御）：
// APP_CRASH/APP_FREEZE 是系统事件、系统自动记录，进程启动后即可取到历史崩溃（含上次
// 运行崩溃，官方姿势：延时重试 takeNext）
export function registerCrashWatcher(): CrashSubscription {
  const watcher: hiAppEvent.Watcher = {
    name: CRASH_WATCHER_NAME,
    appEventFilters: [{
      domain: hiAppEvent.domain.OS,
      names: [hiAppEvent.event.APP_CRASH, hiAppEvent.event.APP_FREEZE]
    }]
  };
  const holder: hiAppEvent.AppEventPackageHolder = hiAppEvent.addWatcher(watcher);
  return { watcher: watcher, holder: holder };
}

// 注销崩溃事件订阅（与 registerCrashWatcher 成对——AGENTS.md「成对释放」红线：
// addWatcher↔removeWatcher）
export function unregisterCrashWatcher(sub: CrashSubscription | null): void {
  if (sub === null) {
    return;
  }
  hiAppEvent.removeWatcher(sub.watcher);
}

// ── 进程级订阅单例（2026-08-29 M3 拍板 6：注册点自 dshinhm 的 LogPage 页面级上移
// EntryAbility onCreate / onDestroy——页面级注册的隐患 = 未成对时进程级订阅随页面进出
// 累积（坑33 成对铁律）；进程级注册天然一次注册一次注销，且崩溃事件在进程全程被订阅
// 捕获，日志页刷新时经共享 holder takeNext 拉取）──
// 模块级唯一订阅（EntryAbility onCreate 建 / onDestroy 销；hiAppEvent 是全局 API 不依赖
// UI 上下文，onCreate 时机可用）
let sharedCrashSub: CrashSubscription | null = null;

// 注册（幂等：已注册跳过）；EntryAbility.onCreate 调用
export function ensureCrashWatcher(): void {
  if (sharedCrashSub === null) {
    sharedCrashSub = registerCrashWatcher();
  }
}

// 注销（与 ensureCrashWatcher 成对）；EntryAbility.onDestroy 调用——进程即将销毁，注销后
// holder 引用一并置空（防迟到的日志页刷新拿到悬空句柄；刷新侧判 null 走空数据路径）
export function teardownCrashWatcher(): void {
  unregisterCrashWatcher(sharedCrashSub);
  sharedCrashSub = null;
}

// 共享订阅的事件拉取句柄（LogPage.refreshLogs 消费；未注册返回 null = 刷新时崩溃区为空）
export function getCrashHolder(): hiAppEvent.AppEventPackageHolder | null {
  return sharedCrashSub !== null ? sharedCrashSub.holder : null;
}

// 拉取崩溃记录：takeNext 逐包取空订阅队列（data = 事件 JSON 数组，含崩溃原因/堆栈全文）。
// 官方注意：崩溃事件系统生成需 30s~2min，崩溃后立刻刷新可能为空
export function fetchCrashLogs(holder: hiAppEvent.AppEventPackageHolder | null): string[] {
  const crashLines: string[] = [];
  if (holder === null) {
    return crashLines;
  }
  let pkg: hiAppEvent.AppEventPackage | null = holder.takeNext();
  while (pkg !== null) {
    for (const eventJson of pkg.data) {
      crashLines.push(eventJson);
    }
    pkg = holder.takeNext();
  }
  return crashLines;
}

// 读取报错日志：flush 强制落盘 → 取时间窗内**全部**日志文件（getLogFile 新在前）→
// 逆序合并成时间顺序 → 按行过滤 W/E/F 级别 → 只留尾部 MAX_ERROR_LINES 行（防长文本
// 渲染卡顿）。
// ★ 2026-09-04 修正：只读 files[0]（最新文件）会漏掉落在较早轮转分片里的错误——系统按
// 大小轮转多文件，事件与刷新时刻错开时错误可能在旧文件；合并读总量 ≤ 2MB 修剪上限，
// 性能安全。无日志文件返回空数组；读文件异常上抛
export function fetchErrorLogLines(): string[] {
  hilog.flush();
  const files: string[] = hilog.getLogFile(LOG_WINDOW_SECONDS);
  if (files.length === 0) {
    return [];
  }
  const dir: string = hilog.getOutputDir();
  const pathOf = (f: string): string => f.startsWith('/') ? f : dir + f;
  // 逆序遍历（新在前 → 旧在前的时间顺序，尾部 slice 取到的是最新行）；
  // 不用 spread 展开（ArkTS 限制），逐行 push
  const allLines: string[] = [];
  for (let i = files.length - 1; i >= 0; i--) {
    const content: string = fs.readTextSync(pathOf(files[i]));
    const lines: string[] = content.split('\n');
    for (const line of lines) {
      allLines.push(line);
    }
  }
  return allLines.filter((line: string) => ERROR_LINE_RE.test(line))
    .slice(-MAX_ERROR_LINES);
}

// 修剪沙箱日志至存储上限（2026-08-22 新增）：flush 强制落盘 → 时间窗内文件列表（新在前）
// → 统计总大小 → 从最旧（尾部）起逐个删，直至总计 ≤ MAX_LOG_STORAGE_BYTES；删除失败仅
// 日志不阻断（下轮修剪自愈）。
// 调用点（2026-09-04 落盘常开后）：EntryAbility.onCreate（启动自检）+ LogPage.aboutToAppear
//（进页二次自检，兜底启动后累积）——事件驱动单次自检，非轮询（P1-2/P1-3）
export function pruneLogFiles(): void {
  hilog.flush();
  const files: string[] = hilog.getLogFile(LOG_WINDOW_SECONDS);
  if (files.length === 0) {
    return;
  }
  const dir: string = hilog.getOutputDir();
  const pathOf = (f: string): string => f.startsWith('/') ? f : dir + f;
  let total: number = 0;
  for (const f of files) {
    try {
      total += fs.statSync(pathOf(f)).size;
    } catch (err) {
      console.error('stat log file failed: ' + JSON.stringify(err));
    }
  }
  for (let i = files.length - 1; i >= 0 && total > MAX_LOG_STORAGE_BYTES; i--) {
    try {
      const size: number = fs.statSync(pathOf(files[i])).size;
      fs.unlinkSync(pathOf(files[i]));
      total -= size;
    } catch (err) {
      console.error('prune log file failed: ' + JSON.stringify(err));
    }
  }
}

// 导出日志为沙箱 TXT（2026-08-22 由 exportTextToFile 改写：原「DocumentViewPicker.save 系统
// 保存对话框」改为官方分享面板（systemShare，另存为/分享由面板接棒）——分享面板需要 APP
// file URI，须先把内容写入应用沙箱（filesDir，唯一名时间戳）。写前清理历史导出文件（前缀
// 「日志-」，数据有界红线：每次导出留文件会无界增长；清理失败仅记录不阻断导出）；失败异常
// 上抛（提示由调用方发）
export function exportLogsToSandbox(context: common.Context, content: string): string {
  const now: Date = new Date();
  const pad = (n: number): string => (n < 10 ? '0' + n : String(n));
  const stamp: string = pad(now.getFullYear()) + pad(now.getMonth() + 1) + pad(now.getDate()) +
    '-' + pad(now.getHours()) + pad(now.getMinutes()) + pad(now.getSeconds());
  const fileName: string = '日志-' + stamp + '.txt';
  const dir: string = context.filesDir;
  const path: string = dir + '/' + fileName;
  // 数据有界：清理历史导出文件（保留本次）
  try {
    for (const f of fs.listFileSync(dir)) {
      if (f.startsWith('日志-') && f !== fileName) {
        fs.unlinkSync(dir + '/' + f);
      }
    }
  } catch (err) {
    console.error('clean old export files failed: ' + JSON.stringify(err));
  }
  // 写文件成对释放：写入异常也要关 fd（try/finally，防 fd 泄漏——自检 2026-08-22 加固）；
  // TRUNC（2026-08-22 检查补：文件名时间戳仅秒级，同秒二次导出会同名——不截断会残留旧尾部）
  const file: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, content);
  } finally {
    fs.closeSync(file);
  }
  return path;
}
