// Node 运行环境管理域件（2026-11-24 鸿蒙 Node 运行时门 4，任务书-鸿蒙Node运行时门4产品面与发布
// -20261124 §6 S1）：管理页（components/settings/NodeRuntimePage.ets）的域逻辑单源 + 待重启
// 守卫旗。页面只做用户面编排，路径、占用、清单与删除判定全在本件。形制对齐 pyexec/PyPackages.ets
//（Python 域「自装包」管理的域件先例）。
// · 两处落点（跨语言同源，改一处须同改 Node 侧）：
//   - 运行区 = filesDir/node-24.22.3-g1/，路径读口沿用 NodeRuntime.nodeRuntimeHomePath（本件不
//     另存 context，上下文未注入时与它同样回空串）。
//   - 安装区 = filesDir/node/，由运行区路径的父级派生——与 bootstrap.js 的
//     `path.join(path.dirname(homeDir), 'node')` 同构（跨语言同源关系，勿改成各存一份 filesDir）。
// · 占用统计一律异步（照 PyRuntime.ets dirSizeBytesAsync 形制：listFile + 每层并行 stat + 单件
//   失败跳过）。★ 禁写同步版——数千件递归 stat 放在进页转场帧上会卡 UI（Python 管理页 2026-11-14
//   决明实测进页卡顿的根因，同步版已撤）。PyRuntime 的那份是模块私有且不在本笔白名单，故此处
//   同形自持一份。
// · 清空 / 重建是用户数据操作：先置待重启旗再删——删除期间与删除之后的新请求立即被拒，不会
//   落在半删的安装区上；成败由删后复读判定（清空 = 安装区剩余占用，重建 = 运行区目录是否仍在），
//   单件删失败不在中途断，也不静默当成功。
// · 待重启旗是进程内单例（照 PyPackages.pyCleanedFlag 先例），不落盘、不引偏好——重启本身就是
//   「重新启用」动作，持久化只会造出「重启后仍锁死」的第二真相；进程重启自然复位。
// · 依赖方向（模块环零）：本件只引 NodeRuntime 与 pyexec/PyRuntime；NodeScheduler /
//   NodeInstallScheduler / ToolNodeExec 引本件。★ 本件禁 import NodeInstallScheduler（会成环），
//   「安装是否在飞」的读口在 NodeInstallScheduler 自己出。
// ArkTS 不可本机执行：删除与占用行为面待真机与断言覆盖，本笔只证源码结构可核与构建绿。
import { fileIo as fs } from '@kit.CoreFileKit';
import { nodeRuntimeHomePath } from './NodeRuntime';
import { removeTreeAsync } from '../pyexec/PyRuntime';

// 安装区目录名（filesDir 下一级；bootstrap.js 的 installRootDir 同名）
const NODE_INSTALL_DIR_NAME: string = 'node';
// 安装区内的清单与台账文件名（与 npm-worker.js / npm-scan.js 的常量同名；node_modules 与 cache 是目录）
const NODE_INSTALL_LOCK_NAME: string = 'package-lock.json';
// 清空动作要删的六个子项——顺序即删除顺序，最大的 node_modules 排最前。
// ★ 清空范围是拍板定案：只删这六项、保留 node 根目录；新增落安装区的文件须在此登记，漏一项 = 留脏账
const NODE_INSTALL_AREA_ENTRIES: string[] = [
  'node_modules', 'cache', 'package.json', 'package-lock.json', 'install-log.jsonl', 'bin-ledger.json'
];
// 清空后的残留容忍（删后复读安装区占用，超过它判「部分文件未能删除」）
const NODE_CLEAR_RESIDUE_TOLERANCE_BYTES: number = 1024 * 1024;
// lock 文件 packages 表的顶层键前缀（嵌套依赖的键会再出现一次该前缀，管理页只列第一层）
const NODE_MODULES_PREFIX: string = 'node_modules/';

// 最小错误形态（只取 message 拼中文提示——照 NodeRuntime / PyRuntime 同款姿势，不引全量类型）
interface ErrorLike {
  message: string;
}

// 件是否存在（纯读探查，命中与否都不写盘）
function pathExists(path: string): boolean {
  try {
    return fs.accessSync(path);
  } catch (e) {
    return false;
  }
}

// 安装区容量上限（字节）。★ 与 npm-install-core.js 的 INSTALL_QUOTA_BYTES 单源同值：那是安装时的
// 硬闸（Node 侧），本常量是管理页显示上限用的展示镜像——一致性由 assert-node-runtime.mjs 2284 组
// 钉守（解析两侧表达式比对），页面直接引用本常量，禁另写字面量
export const NODE_INSTALL_QUOTA_BYTES: number = 512 * 1024 * 1024;

// ── 待重启守卫旗（进程内单例；清空 / 重建置位，重启自然复位）──

// 守卫文案（调度层与工具面回执用；= 清空 / 重建各自置位时写入）
const NODE_RESTART_GUARD_CLEARED: string = '已清空安装包，请重启应用后继续使用。';
const NODE_RESTART_GUARD_REBUILT: string = '运行区已重建，请重启应用后继续使用。';
// 管理页提示行文案（置位后管理页显示；残留句在删后复读判不完整时覆盖成功句）
const NODE_PAGE_NOTE_CLEARED: string = '已清理，重启应用后生效';
const NODE_PAGE_NOTE_REBUILT: string = '已重建，重启应用后生效';
const NODE_PAGE_NOTE_RESIDUE: string = '部分文件未能删除，重启应用后可重试';

let needsRestartFlag: boolean = false;
let restartGuardTextValue: string = '';
// 管理页提示（与旗同寿命：动作在删除途中页面已退场时仍要落下来，重进页读得到同一句）
let restartPageNoteValue: string = '';

export function nodeNeedsRestart(): boolean {
  return needsRestartFlag;
}

// 守卫文案读口（调度层三入口与工具面预检取它拼回执；未置位回空串）
export function nodeRestartGuardText(): string {
  return restartGuardTextValue;
}

// 管理页提示读口（置位后管理页显示这一句；未置位回空串）
export function nodeRestartPageNote(): string {
  return restartPageNoteValue;
}

export function nodeMarkNeedsRestart(text: string): void {
  needsRestartFlag = true;
  restartGuardTextValue = text;
  restartPageNoteValue = '';
}

// ── 路径与占用 ──

// 安装区根目录绝对路径（filesDir/node；上下文未注入回空串——调用方判空，禁拿空串去删）
export function nodeInstallRootPath(): string {
  const home: string = nodeRuntimeHomePath();
  if (home === '') {
    return '';
  }
  return home.substring(0, home.lastIndexOf('/')) + '/' + NODE_INSTALL_DIR_NAME;
}

// 目录异步递归求和（PyRuntime.ets dirSizeBytesAsync 同形；目录不存在与单件读失败按 0 跳过——
// 统计不中断不造数）
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

// 单件求和（目录递归取子树、文件取 size；失败跳过回 0）
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

// 运行区占用字节数（异步；上下文未注入回 -1 = 未知，调用方如实展示；运行区尚未落位回 0）
export async function nodeRuntimeUsageBytesAsync(): Promise<number> {
  const home: string = nodeRuntimeHomePath();
  if (home === '') {
    return -1;
  }
  return dirSizeBytesAsync(home);
}

// 安装区占用字节数（异步；上下文未注入回 -1；尚未装过包回 0）
export async function nodeInstallUsageBytesAsync(): Promise<number> {
  const root: string = nodeInstallRootPath();
  if (root === '') {
    return -1;
  }
  return dirSizeBytesAsync(root);
}

// ── 已装包清单 ──

// 已装包条目（管理页列表行 = name@version）
export interface NodeInstalledPackage {
  name: string;
  version: string;
}

// 已装包清单读数（packages 按包名排序；parseError 非空 = 清单读不出，此时 packages 为空）
export interface NodeInstalledList {
  packages: NodeInstalledPackage[];
  parseError: string;
}

function comparePackageName(a: NodeInstalledPackage, b: NodeInstalledPackage): number {
  if (a.name < b.name) {
    return -1;
  }
  return a.name > b.name ? 1 : 0;
}

// 已装包清单（只读安装区 package-lock.json——权威清单；不遍历 node_modules）。
// 只取 packages 表里第一层的包：键以 node_modules/ 开头、且去掉前缀后不再出现第二个 node_modules/
//（嵌套依赖与它顶层的同名包重复列出会让人误以为装了两份）。文件缺失（从未装过包）回空清单且
// parseError 为空；读失败或解析失败回空清单并附 parseError——不猜、不把读不出说成「没装包」。
// 单文件读 + JSON 解析，量级与 Python 管理页读 installed.json 同级，可在进页同步调用
export function nodeInstalledPackages(): NodeInstalledList {
  const result: NodeInstalledList = { packages: [], parseError: '' };
  const root: string = nodeInstallRootPath();
  if (root === '') {
    result.parseError = '应用上下文未注入，无法读取已安装的包';
    return result;
  }
  const lockPath: string = root + '/' + NODE_INSTALL_LOCK_NAME;
  if (!pathExists(lockPath)) {
    return result; // 清单文件缺失 = 从未装过包，空清单不是错误
  }
  let text: string = '';
  try {
    text = fs.readTextSync(lockPath);
  } catch (e) {
    const readError = e as ErrorLike;
    result.parseError = '读取安装清单失败，' + (readError.message || '未知错误');
    return result;
  }
  try {
    const lock = JSON.parse(text) as Record<string, Object>;
    const table: Object | undefined = lock['packages'];
    if (typeof table !== 'object') {
      result.parseError = '安装清单格式不正确';
      return result;
    }
    const packages: Record<string, Object> = table as Record<string, Object>;
    for (const key of Object.keys(packages)) {
      if (!key.startsWith(NODE_MODULES_PREFIX)) {
        continue;
      }
      const name: string = key.substring(NODE_MODULES_PREFIX.length);
      if (name === '' || name.indexOf(NODE_MODULES_PREFIX) >= 0) {
        continue;
      }
      const entry: Record<string, Object> = packages[key] as Record<string, Object>;
      const version: Object | undefined = entry['version'];
      if (typeof version !== 'string' || version === '') {
        continue; // link 条目等项目根占位没有版本，不是已装的包
      }
      result.packages.push({ name: name, version: version });
    }
  } catch (e) {
    result.packages = [];
    result.parseError = '安装清单解析失败';
  }
  result.packages.sort(comparePackageName);
  return result;
}

// ── 清空安装区 / 重建运行区 ──

// 清空结果（freedBytes = 删前减删后的安装区占用；remainingBytes = 删后复读；
// note 非空 = 删除不完整的说明）
export interface NodeClearResult {
  ok: boolean;
  freedBytes: number;
  remainingBytes: number;
  note: string;
}

// 重建结果（note 非空 = 删除不完整的说明）
export interface NodeRebuildResult {
  ok: boolean;
  note: string;
}

// 删单件（lstat 判类型：真实目录走 removeTreeAsync，文件与符号链接只 unlink 自身——链接
// 绝不下降；不存在 = 目标态；删失败不在此中断——成败由调用方的删后复读统一定）
async function removeEntryQuiet(path: string): Promise<void> {
  let isDirectory: boolean = false;
  try {
    // ★ 用 lstat 不用 stat（2026-11-24 两千二百八十七节）：六项之一若是符号链接（含指向
    // 目录的链接），stat 会跟随目标判成目录并递归删到安装区外；lstat 只看链接本身，
    // 判为非目录 → 走下面的 unlink 只删链接
    isDirectory = (await fs.lstat(path)).isDirectory();
  } catch (e) {
    return; // 不存在 = 目标态
  }
  if (isDirectory) {
    await removeTreeAsync(path);
    return;
  }
  try {
    await fs.unlink(path);
  } catch (e) {
    // 删不掉的文件留在盘上，由删后复读占用判出来
  }
}

// 清空安装包：删安装区六个子项（保留 node 根目录），不动安装区以外的任何东西——会话内容与
// 文件工作区不在删除面内。先置旗再删；删后复读安装区占用，超过容忍值判不完整。
// 无论成败旗都保持置位：重启前 exec / run_bin / install 一律被拒
export async function nodeClearInstallArea(): Promise<NodeClearResult> {
  const root: string = nodeInstallRootPath();
  if (root === '') {
    return { ok: false, freedBytes: 0, remainingBytes: -1, note: '应用上下文未注入，无法清空安装包' };
  }
  nodeMarkNeedsRestart(NODE_RESTART_GUARD_CLEARED);
  const before: number = await nodeInstallUsageBytesAsync();
  for (const name of NODE_INSTALL_AREA_ENTRIES) {
    await removeEntryQuiet(root + '/' + name);
  }
  const remaining: number = await nodeInstallUsageBytesAsync();
  const cleared: boolean = remaining >= 0 && remaining <= NODE_CLEAR_RESIDUE_TOLERANCE_BYTES;
  restartPageNoteValue = cleared ? NODE_PAGE_NOTE_CLEARED : NODE_PAGE_NOTE_RESIDUE;
  return {
    ok: cleared,
    freedBytes: before > remaining ? before - remaining : 0,
    remainingBytes: remaining,
    note: cleared ? '' : NODE_PAGE_NOTE_RESIDUE
  };
}

// 重建运行区：删运行区整目录，不动安装区（已装的包保留）；下次冷启由运行区落位重新释放。
// 先置旗再删；删后目录仍在判不完整（运行中的 Node 仍可能握着个别文件）。
// 无论成败旗都保持置位：重启前 exec / run_bin / install 一律被拒
export async function nodeRebuildRuntimeArea(): Promise<NodeRebuildResult> {
  const home: string = nodeRuntimeHomePath();
  if (home === '') {
    return { ok: false, note: '应用上下文未注入，无法重建运行区' };
  }
  nodeMarkNeedsRestart(NODE_RESTART_GUARD_REBUILT);
  await removeTreeAsync(home);
  // 复查：目录仍在 = 有文件没删掉（运行中的 Node 仍可能握着个别文件），不静默当成功
  const remains: boolean = pathExists(home);
  restartPageNoteValue = remains ? NODE_PAGE_NOTE_RESIDUE : NODE_PAGE_NOTE_REBUILT;
  return remains ? { ok: false, note: NODE_PAGE_NOTE_RESIDUE } : { ok: true, note: '' };
}
