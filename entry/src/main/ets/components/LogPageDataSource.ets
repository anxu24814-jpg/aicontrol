// 「运行日志」页数据层（2026-08-21 自 LogPage.ets 拆出，拆分规则见 LogPage.ets 头注释）：
// 只负责日志与系统事件的「获取、分类、有界、导出」——系统事件订阅与拉取、hilog 沙箱报错
// 日志读取过滤、沙箱日志占用统计与修剪、导出写文件。纯工具函数：参数进、返回值/异常出，
// 不持有任何 UI 状态，不发 toast（提示统一由 LogPage 发，沉浸光感材质参数只在 UI 层解析）。
//
// ★ 2026-09-27 系统事件族扩展笔（决明拍板）：
// · **订阅面**由「崩溃 + 冻屏」两类扩为 7 类系统事件（分类表 SYS_EVENT_SPECS 单源）：崩溃 /
//   冻屏 / 冻屏告警 / 应用终止 / 主线程卡顿 / 资源超限 / 任务超时。官方 14 类系统事件里挑出
//   排障可用、零权限、零额外配置的 7 类（未纳入者：启动耗时属开发期性能工程面、滑动丢帧
//   信息弱或无场景、音频卡顿与功耗统计非故障排障面、地址越界与 CPU 高负载对纯 ArkTS 前台
//   应用命中率极低）。
// · **必须分流**：原 fetchCrashLogs 把订阅队列里所有事件一律当「崩溃记录」返回。只扩 names
//   不改取数，新事件会静默混进崩溃桶、还会被条数上限把真崩溃挤出去。现在按事件名查分类表，
//   未登记的事件名一律跳过（不落任何桶）——该负向判据由本域断言第 272 组守。
// · **进程内缓存**：takeNext 是消费式（官方 d.ts 与 API 参考双证：取尽返回 null），叠加页面
//   「退出即清显示」的既有语义 ⇒ 同一次运行里刷一次就再也看不到崩溃记录。现在拉到的记录进
//   进程级有界缓存（每类最多 EVENT_KEEP_PER_KIND 条），页面显示与导出都读缓存；缓存随进程
//   退出消失、**不落盘**（事件负载含堆栈与日志片段，落盘会扩大备份/导出链的隐私暴露面——
//   与 hilog 侧「落盘常开」是两套有意不同的取舍）。
// · **有界三层**：每类条数上限（缓存裁剪）+ 单条文本上限（写缓存时截断）+ 页面显示上限
//   （显示时再截一刀；导出写完整缓存文本）——第三层对应竞品「页面预览尾片段、导出含完整
//   留存」的口径，我们在报错日志侧同笔对齐（页面 500 行 / 导出全量）。
// · **文案事实修订**：原空态与注释写「崩溃事件系统生成需 30 秒~2 分钟」「系统侧每类型 10 条
//   上限」——逐页检索官方文档均无出处；官方口径是崩溃后需重新启动应用才能取到、未回调事件
//   在下次 addWatcher 后回调。两处说法已改（页面空态 + 本文件注释），改判后的判据见断言
//   第 272 组。
//
// 取数路径（页面刷新与导出前各调一次，均在用户动作上、非轮询——P1-2/P1-3）：
// fetchSystemEvents（消费订阅队列 → 分流 → 入缓存）→ sysEventBlocks（按分类表出块）→
// fetchErrorLogLines（读沙箱文件过滤 W/E/F）。
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hiAppEvent, hilog } from '@kit.PerformanceAnalysisKit';

// 刷新时读取的日志时间窗（秒）：7 天内的沙箱日志文件（系统按文件分片轮转）
export const LOG_WINDOW_SECONDS: number = 7 * 24 * 3600;
// 报错日志的页面显示上限（只取尾部 N 行防长文本渲染卡顿，2026-08-21 决明要求 200 → 500）。
// ★ 2026-09-27 起**导出不再受它约束**：导出走 fetchErrorLogLines(0) 取全量留存（500 行只是
// 页面预览口径）。改前导出与预览同源 = 用户发给开发者的日志被静默截断在 500 行。
export const MAX_ERROR_LINES: number = 500;
// 沙箱日志存储上限（字节）：2MB（2026-09-04 决明定稿——落盘自当日起进程级常开
//（EntryAbility.onCreate），日常量级小，2MB 仍远低于沙箱压力；防堆积 = 启动 + 进日志页
// 两次自检修剪（pruneLogFiles）——系统分片轮转未证实配额/物理删除，应用自管上限）
export const MAX_LOG_STORAGE_BYTES: number = 1024 * 1024 * 2;
// 每类系统事件的缓存条数上限（有界红线的落点之一；事件负载单条可达数十 KB，见下条）
export const EVENT_KEEP_PER_KIND: number = 5;
// 单条事件文本的缓存上限（字符）：崩溃/冻屏/任务超时类事件含 threads[] 全量线程栈与
// hilog[] 日志片段，不设上限缓存会无界（单条可到数十 KB × 7 类 × N 条）
export const EVENT_TEXT_MAX_CHARS: number = 12000;
// 单条事件文本的**页面显示**上限（字符）：页面只显示头部片段，导出写完整缓存文本
//（有界三层的最外一层，见头注释）
const EVENT_DISPLAY_MAX_CHARS: number = 3000;
// hilog 落盘行级别过滤：警告 WARN(W)/错误 ERROR(E)/致命 FATAL(F) 单字母独立 token
// （hilog 行格式级别为独立列；决明要求警告也算「报错」）
const ERROR_LINE_RE: RegExp = / (E|F|W) /;
// 系统事件观察者名。★ 名沿用 logPageCrashWatcher（语义已扩为 7 类系统事件：改名会牵动
// EntryAbility 两侧调用与断言「ensure↔teardown 成对」钉，故保留并在各处注明；d.ts 仅承诺
// name 唯一标识不同观察者，未承诺同名重复注册覆盖——注册/注销成对性由调用方保证，见单例段）
const CRASH_WATCHER_NAME: string = 'logPageCrashWatcher';

// ── 顶部档位（页面胶囊、显示过滤、导出过滤三处单源）──
// 0 全部 / 1 崩溃 / 2 异常 / 3 报错（由三档扩为四档：新七类事件需独立档位承载；档位判据
// 收敛为常量 + 判据函数，不再散在页面各写一份硬编码）
export const LOG_TAB_ALL: number = 0;
export const LOG_TAB_CRASH: number = 1;
export const LOG_TAB_ABNORMAL: number = 2;
export const LOG_TAB_ERROR: number = 3;

// ── 系统事件分类表（**单源**：订阅 names 由它派生 / 区块标题 / 缓存分组 / 档位过滤）──

export const SYS_EVENT_GROUP_CRASH: string = 'crash';
export const SYS_EVENT_GROUP_ABNORMAL: string = 'abnormal';

// 一类系统事件的登记（name = hiAppEvent.event.* 常量；key = 稳定短键，断言与区块身份用；
// summaryKeys = 写缓存时的摘要优先字段）。★ summaryKeys 只列**官方文档确证存在**的字段
//（崩溃 crash_type / 终止 reason / 资源超限 resource_type，另有通用的 time 由代码单独取）：
// 取不到就只显示 JSON——摘要缺失是无害的，字段名写错会静默显示空值，故不猜字段名。
export interface SysEventSpec {
  name: string;
  key: string;
  title: string;
  group: string;
  summaryKeys: string[];
}

export const SYS_EVENT_SPECS: SysEventSpec[] = [
  { name: hiAppEvent.event.APP_CRASH, key: 'crash', title: '崩溃记录',
    group: SYS_EVENT_GROUP_CRASH, summaryKeys: ['crash_type'] },
  { name: hiAppEvent.event.APP_FREEZE, key: 'freeze', title: '冻屏记录',
    group: SYS_EVENT_GROUP_CRASH, summaryKeys: [] },
  { name: hiAppEvent.event.appFreezeWarning, key: 'freezeWarning', title: '冻屏告警',
    group: SYS_EVENT_GROUP_CRASH, summaryKeys: [] },
  { name: hiAppEvent.event.APP_KILLED, key: 'killed', title: '应用终止',
    group: SYS_EVENT_GROUP_ABNORMAL, summaryKeys: ['reason'] },
  { name: hiAppEvent.event.MAIN_THREAD_JANK, key: 'jank', title: '主线程卡顿',
    group: SYS_EVENT_GROUP_ABNORMAL, summaryKeys: [] },
  { name: hiAppEvent.event.RESOURCE_OVERLIMIT, key: 'overlimit', title: '资源超限',
    group: SYS_EVENT_GROUP_ABNORMAL, summaryKeys: ['resource_type'] },
  { name: hiAppEvent.event.APP_HICOLLIE, key: 'hicollie', title: '任务超时',
    group: SYS_EVENT_GROUP_ABNORMAL, summaryKeys: [] }
];

// 订阅用的事件名清单（由分类表派生——另抄一份名字必与表漂移）
export function sysEventNames(): string[] {
  const out: string[] = [];
  for (const spec of SYS_EVENT_SPECS) {
    out.push(spec.name);
  }
  return out;
}

// 分类查找（未登记事件名返回 undefined = 调用点跳过，见 fetchSystemEvents 的防混桶判据）
function findSpec(name: string): SysEventSpec | undefined {
  for (const spec of SYS_EVENT_SPECS) {
    if (spec.name === name) {
      return spec;
    }
  }
  return undefined;
}

// 崩溃订阅（成对释放）：watcher 是 addWatcher 入参对象（removeWatcher 需要同一对象，只保留
// holder 无法注销——每次进日志页会累积进程级 watcher，无界增长）；holder 是事件拉取句柄
//（takeNext）
export interface CrashSubscription {
  watcher: hiAppEvent.Watcher;
  holder: hiAppEvent.AppEventPackageHolder;
}

// 注册系统事件订阅（进程级；幂等由调用方保证——LogPage.aboutToAppear 判空防御）：
// 一个 filter 带全部事件名（官方 AppEventFilter.names 即「需要订阅的事件名称集合」）。
// APP_CRASH/APP_FREEZE 等是系统事件、系统自动记录，进程启动后即可取到历史事件（含上次
// 运行崩溃，官方姿势：延时重试 takeNext）。★ 刻意不做 setEventConfig / configEventPolicy
// 配置——保持官方默认规格，不为排障引入额外采样开销（主线程超时事件默认上报频次低，是
// 取向非缺陷）
export function registerCrashWatcher(): CrashSubscription {
  const watcher: hiAppEvent.Watcher = {
    name: CRASH_WATCHER_NAME,
    appEventFilters: [{
      domain: hiAppEvent.domain.OS,
      names: sysEventNames()
    }]
  };
  const holder: hiAppEvent.AppEventPackageHolder = hiAppEvent.addWatcher(watcher);
  return { watcher: watcher, holder: holder };
}

// 注销系统事件订阅（与 registerCrashWatcher 成对——AGENTS.md「成对释放」红线：
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

// 共享订阅的事件拉取句柄（LogPage.refreshLogs 消费；未注册返回 null = 刷新时事件区为空）
export function getCrashHolder(): hiAppEvent.AppEventPackageHolder | null {
  return sharedCrashSub !== null ? sharedCrashSub.holder : null;
}

// ── 系统事件缓存（进程级、有界、不落盘）──

// 事件记录（缓存单元）：text = 摘要行 + 参数 JSON（写缓存时按 EVENT_TEXT_MAX_CHARS 截断）；
// at = 事件触发时间（官方 params.time，单位 ms）。取不到 time 记 0，显示层据此省略时间行
export interface SysEventRecord {
  name: string;
  at: number;
  text: string;
}

// 显示/导出区块（页面与导出共用单源：页面按 EVENT_DISPLAY_MAX_CHARS 再截一刀，导出写
// 完整缓存文本——两层口径的差别只在 display 这个形参）
export interface SysEventBlock {
  key: string;
  title: string;
  group: string;
  text: string;
  count: number;
}

// 事件缓存（模块级单例；新条目头插 = 天然按取到时间倒序）
let eventRecords: SysEventRecord[] = [];

// 拉取并分类系统事件（页面刷新与导出前各调一次）：消费 holder 队列 → 逐条按事件名查分类表
// → **未登记事件名跳过**（防混桶：早先实现把队列里所有事件当崩溃记录返回）→ 入缓存 →
// 按每类上限裁剪。holder 为 null（订阅未建）时零动作；异常不外抛（页面刷新失败由页面侧
// toast 兜底，日志域不得反噬主链）
export function fetchSystemEvents(holder: hiAppEvent.AppEventPackageHolder | null): void {
  if (holder === null) {
    return;
  }
  let pkg: hiAppEvent.AppEventPackage | null = holder.takeNext();
  while (pkg !== null) {
    for (const info of pkg.appEventInfos) {
      const spec: SysEventSpec | undefined = findSpec(info.name);
      if (spec !== undefined) {
        eventRecords.unshift(buildEventRecord(info, spec));
      }
    }
    pkg = holder.takeNext();
  }
  trimEventCache();
}

// 单条记录组装（摘要行 + 参数 JSON；时间取 params.time，非 number 记 0）
function buildEventRecord(info: hiAppEvent.AppEventInfo, spec: SysEventSpec): SysEventRecord {
  const params: Record<string, Object> = info.params as Record<string, Object>;
  const rawTime: Object | undefined = params['time'];
  const at: number = typeof rawTime === 'number' ? rawTime : 0;
  const summary: string = summaryText(params, spec.summaryKeys);
  const json: string = clipText(jsonText(params), EVENT_TEXT_MAX_CHARS);
  return { name: spec.name, at: at, text: summary === '' ? json : summary + '\n' + json };
}

// 摘要行（取值型字段的值串，顿号连接；字段缺失或空值即省略——只显示值不显示键名，值在
// 对应区块标题下已有语义，例如「应用终止」下的「UserRequest」）
function summaryText(params: Record<string, Object>, keys: string[]): string {
  const parts: string[] = [];
  for (const key of keys) {
    const value: string = paramText(params, key);
    if (value !== '') {
      parts.push(value);
    }
  }
  return parts.join(' · ');
}

// 参数取值成串（字符串原样；数字与布尔转字面量；对象与数组走 JSON）。类型判定用 typeof
//（AppPreferences.classifyPrefValue 同款姿态），不做深解析——事件负载由系统定义，不猜结构
function paramText(params: Record<string, Object>, key: string): string {
  const v: Object | undefined = params[key];
  if (v === undefined || v === null) {
    return '';
  }
  if (typeof v === 'string') {
    return v;
  }
  if (typeof v === 'number' || typeof v === 'boolean') {
    return String(v);
  }
  return jsonText(v);
}

// JSON 成串（容错：stringify 失败返回空串——日志是傍路，不得反噬调用方）
function jsonText(value: Object): string {
  try {
    return JSON.stringify(value);
  } catch (e) {
    return '';
  }
}

// 缓存裁剪（每类只留最近的 EVENT_KEEP_PER_KIND 条；缓存新在前，故从前往后数、超出即丢）
function trimEventCache(): void {
  const counts: Record<string, number> = {};
  const kept: SysEventRecord[] = [];
  for (const rec of eventRecords) {
    const seen: number = counts[rec.name] === undefined ? 0 : counts[rec.name];
    if (seen < EVENT_KEEP_PER_KIND) {
      counts[rec.name] = seen + 1;
      kept.push(rec);
    }
  }
  eventRecords = kept;
}

// 区块（页面显示与导出共用单源）：按分类表顺序出块，空类跳过；display = true 时单条按页面
// 显示上限再截一刀（导出传 false = 完整缓存文本）。每条前置事件时间行（取不到则不前置）
export function sysEventBlocks(display: boolean): SysEventBlock[] {
  const out: SysEventBlock[] = [];
  for (const spec of SYS_EVENT_SPECS) {
    const lines: string[] = [];
    for (const rec of eventRecords) {
      if (rec.name !== spec.name) {
        continue;
      }
      const time: string = eventTimeText(rec.at);
      const body: string = display ? clipText(rec.text, EVENT_DISPLAY_MAX_CHARS) : rec.text;
      lines.push(time === '' ? body : time + '\n' + body);
    }
    if (lines.length > 0) {
      out.push({ key: spec.key, title: spec.title, group: spec.group, text: lines.join('\n\n'),
        count: lines.length });
    }
  }
  return out;
}

// 分组条数（页面统计行用；按缓存现算，不另存计数——单源零漂移）
export interface SysEventCounts {
  crash: number;
  abnormal: number;
}

export function sysEventCounts(): SysEventCounts {
  const out: SysEventCounts = { crash: 0, abnormal: 0 };
  for (const rec of eventRecords) {
    const spec: SysEventSpec | undefined = findSpec(rec.name);
    if (spec === undefined) {
      continue;
    }
    if (spec.group === SYS_EVENT_GROUP_CRASH) {
      out.crash++;
    } else {
      out.abnormal++;
    }
  }
  return out;
}

// 清空事件缓存（页面「清除运行日志」动作调用；进程退出本就会清，这是用户主动清的路径）
export function clearSystemEventCache(): void {
  eventRecords = [];
}

// 档位过滤（页面显示与导出共用单源——两套判据必漂移，坑26 家族）
export function blockShownInTab(group: string, tab: number): boolean {
  if (tab === LOG_TAB_CRASH) {
    return group === SYS_EVENT_GROUP_CRASH;
  }
  if (tab === LOG_TAB_ABNORMAL) {
    return group === SYS_EVENT_GROUP_ABNORMAL;
  }
  if (tab === LOG_TAB_ERROR) {
    return false;
  }
  return true;
}

// 报错区块是否显示（0 全部 / 3 报错显示；1 崩溃与 2 异常两档下不显示）
export function errorShownInTab(tab: number): boolean {
  return tab !== LOG_TAB_CRASH && tab !== LOG_TAB_ABNORMAL;
}

// 事件时间文案（at <= 0 = 未取到时间，返回空串由调用方省略该行；本地时区完整时刻）
function eventTimeText(at: number): string {
  if (at <= 0) {
    return '';
  }
  const d: Date = new Date(at);
  return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + ' ' +
    pad2(d.getHours()) + ':' + pad2(d.getMinutes()) + ':' + pad2(d.getSeconds());
}

function pad2(n: number): string {
  return n < 10 ? '0' + n : '' + n;
}

// ── 沙箱报错日志（hilog 落盘）──

// 读取报错日志：flush 强制落盘 → 取时间窗内**全部**日志文件（getLogFile 新在前）→
// 逆序合并成时间顺序 → 按行过滤 W/E/F 级别 → 尾部截断。
// limit > 0 = 页面预览口径（只留尾部 limit 行，防长文本渲染卡顿）；limit <= 0 = **全量**
//（导出用；总量受 2MB 修剪上限约束，仍在有界内）。无日志文件返回空数组；读文件异常上抛。
// ★ 只读 files[0]（最新文件）是错的——系统按大小轮转多文件，事件与刷新时刻错开时错误可能
// 在旧分片；合并读总量 ≤ 2MB 修剪上限，性能安全
export function fetchErrorLogLines(limit: number): string[] {
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
  const filtered: string[] = allLines.filter((line: string) => ERROR_LINE_RE.test(line));
  return limit > 0 ? filtered.slice(-limit) : filtered;
}

// ── 沙箱日志占用与修剪 ──

// 占用概览（页面统计行）：fileCount 件数 / totalBytes 合计（stat 失败不计入）/
// deletedCount 与 deletedBytes = 本次修剪实删（只统计不删除的路径恒 0）
export interface LogUsage {
  fileCount: number;
  totalBytes: number;
  deletedCount: number;
  deletedBytes: number;
}

// 扫描结果（内部态：文件清单与逐件大小同序，修剪按索引取大小——避免删除时二次 stat）
interface LogScan {
  files: string[];
  sizes: number[];
  totalBytes: number;
}

// 扫一遍沙箱日志文件：flush 落盘 → 时间窗内文件清单（新在前）→ 逐件取大小。stat 失败按
// -1 记（不参与合计、也不阻断——修剪与统计都是 best-effort，单项异常不放大到整页）
function scanLogFiles(): LogScan {
  hilog.flush();
  const files: string[] = hilog.getLogFile(LOG_WINDOW_SECONDS);
  const out: LogScan = { files: files, sizes: [], totalBytes: 0 };
  if (files.length === 0) {
    return out;
  }
  const dir: string = hilog.getOutputDir();
  const pathOf = (f: string): string => f.startsWith('/') ? f : dir + f;
  for (const f of files) {
    let size: number = -1;
    try {
      size = fs.statSync(pathOf(f)).size;
    } catch (err) {
      hilog.error(0xD5A0, 'LogPageDataSource', 'stat log file failed: %{public}s', JSON.stringify(err));
    }
    out.sizes.push(size);
    if (size > 0) {
      out.totalBytes += size;
    }
  }
  return out;
}

// 修剪沙箱日志至存储上限：从最旧（尾部）起逐个删，直至总计 ≤ MAX_LOG_STORAGE_BYTES；
// 删除失败仅记录不阻断（下轮修剪自愈）；返回修剪结果与修剪后占用（供页面统计行显示
//「已用多少、清了多少」）。调用点 = EntryAbility.onCreate（启动自检）+ LogPage.
// aboutToAppear（进页二次自检）——事件驱动单次自检，非轮询（P1-2/P1-3）
export function pruneLogFiles(): LogUsage {
  const scan: LogScan = scanLogFiles();
  const usage: LogUsage = { fileCount: scan.files.length, totalBytes: scan.totalBytes,
    deletedCount: 0, deletedBytes: 0 };
  const files: string[] = scan.files;
  const dir: string = hilog.getOutputDir();
  const pathOf = (f: string): string => f.startsWith('/') ? f : dir + f;
  let total: number = usage.totalBytes;
  for (let i = files.length - 1; i >= 0 && total > MAX_LOG_STORAGE_BYTES; i--) {
    try {
      fs.unlinkSync(pathOf(files[i]));
      const size: number = scan.sizes[i] > 0 ? scan.sizes[i] : 0;
      total -= size;
      usage.deletedCount++;
      usage.deletedBytes += size;
    } catch (err) {
      hilog.error(0xD5A0, 'LogPageDataSource', 'prune log file failed: %{public}s', JSON.stringify(err));
    }
  }
  usage.totalBytes = total;
  return usage;
}

// 只统计不删除（刷新时更新占用行；修剪只在进页做一次，刷新不做删除动作）
export function sandboxLogUsage(): LogUsage {
  const scan: LogScan = scanLogFiles();
  return { fileCount: scan.files.length, totalBytes: scan.totalBytes, deletedCount: 0,
    deletedBytes: 0 };
}

// 占用文案（页面说明行单源）：占用 + 件数 + 上限；本次修剪真删过文件才追加一句（否则不提，
// 免得每次进页都报一句「本次已清理 0 个」）
export function logUsageText(usage: LogUsage): string {
  let text: string = '运行日志已占用 ' + byteSizeText(usage.totalBytes) + '，共 ' +
    usage.fileCount + ' 个文件，上限 ' + (MAX_LOG_STORAGE_BYTES / (1024 * 1024)) + ' MB';
  if (usage.deletedCount > 0) {
    text += '。本次已自动清理最旧 ' + usage.deletedCount + ' 个文件';
  }
  return text;
}

// 字节文案（不足 1 MB 用 KB 取整，否则 MB 一位小数）
function byteSizeText(bytes: number): string {
  if (bytes < 1024 * 1024) {
    return Math.round(bytes / 1024) + ' KB';
  }
  return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}

// 有界截断单点（超限加省略号；调用方给上限）
function clipText(text: string, maxChars: number): string {
  return text.length > maxChars ? text.substring(0, maxChars) + '…' : text;
}

// 导出日志为沙箱 TXT（由 exportTextToFile 改写：原「DocumentViewPicker.save 系统保存对话框」
// 改为官方分享面板 systemShare，另存为/分享由面板接棒——分享面板需要 APP file URI，须先把
// 内容写入应用沙箱 filesDir，唯一名时间戳）。写前清理历史导出文件（前缀「日志-」，数据有界
// 红线；清理失败仅记录不阻断导出）；失败异常上抛（提示由调用方发）
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
    hilog.error(0xD5A0, 'LogPageDataSource', 'clean old export files failed: %{public}s', JSON.stringify(err));
  }
  // 写文件成对释放：写入异常也要关 fd（try/finally，防 fd 泄漏）；TRUNC（文件名时间戳仅
  // 秒级，同秒二次导出会同名——不截断会残留旧尾部）
  const file: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, content);
  } finally {
    fs.closeSync(file);
  }
  return path;
}
