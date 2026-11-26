// 文件工作区多选域件（WorkspaceManagePage 越 1200 硬线后按宪法先拆域再改；拆分轴 = 两库页多选笔
// 「多选独立成域」同款，批量条形态与勾选圈渲染复用既有共用件，不在本域重造）。
// 职责 =「工作区多选批量删除的纯函数域——选中集反查、删除量统计、确认弹窗文案」（文件夹段 +
// 临时段两套）。多选态状态（@State）与执行编排（确认弹窗 / ChatDb 委托口调用 / toast / 重载）归壳
// WorkspaceManagePage；本件零 IO 零组件（纯函数，断言脚本剥 import 后 node 可直跑）。
// · 生效范围：文件夹段 + **临时段**（组列表选会话组 / 下探选文件，两级各自成套；临时段为扫盘驱动
//   视图，选中行经 WorkspaceTmpSelectRow 载荷上行桥接，见本件末段）；会话段不接入（卡片无行菜单、
//   须下探到会话内文件才有单条操作——当前层级多选无附着面），标题栏「更多」菜单「多选」项在该段
//   置灰（弹时快照，判据在壳侧 menuCallbacks）。
// · 选中键 = workspaceEntryKey 基础键（与 LazyForEach 行键同源单值）——多选态勾选位后缀由壳侧键
//   生成器并入（MemoryLibraryRows「键含勾选位 + 数据源 refresh」先例），本件只认基础键。
import { WorkspaceListEntry } from './WorkspaceListRows';
import { WorkspaceFileRow, WorkspaceFolderStats, deriveWorkspaceSubtreeStats,
  formatWorkspaceSize, workspaceParentDir } from '../../common/WorkspaceUtil';

// 选中键集 → 当前列表条目集（批量删除执行前反查单源，勿在别处重造）：键在 entries 中缺失 =
// 陈旧选中（可见集已换而兜底清洗未跑的窗口），静默跳过——targets 只含真实在场的条目
export function workspaceMultiselectTargets(entries: WorkspaceListEntry[],
  selectedKeys: string[]): WorkspaceListEntry[] {
  const targets: WorkspaceListEntry[] = [];
  for (const key of selectedKeys) {
    for (const entry of entries) {
      if (entry.key === key) {
        targets.push(entry);
        break;
      }
    }
  }
  return targets;
}

// 多选删除量统计（确认弹窗文案的唯一输入；文件夹子树逐个取 deriveWorkspaceSubtreeStats——单删文件夹确认
// 同源，嵌套子树整棵计入；散文件直接累行 size）
export interface WorkspaceMultiselectStats {
  folderCount: number;    // 选中文件夹数
  fileCount: number;      // 选中散文件数（不含文件夹内部）
  innerFileCount: number; // 文件夹内部文件总数（含嵌套；folderCount === 0 恒 0）
  totalBytes: number;     // 删除总量字节 = 选中散文件 + 文件夹子树全部
}

export function collectWorkspaceMultiselectStats(rows: WorkspaceFileRow[],
  targets: WorkspaceListEntry[]): WorkspaceMultiselectStats {
  const stats: WorkspaceMultiselectStats =
    { folderCount: 0, fileCount: 0, innerFileCount: 0, totalBytes: 0 };
  for (const entry of targets) {
    if (entry.kind === 'folder') {
      stats.folderCount++;
      const sub: WorkspaceFolderStats =
        deriveWorkspaceSubtreeStats(rows, workspaceParentDir(entry.dirPath), entry.dirName);
      stats.innerFileCount += sub.fileCount;
      stats.totalBytes += sub.bytes;
      continue;
    }
    const row: WorkspaceFileRow | null = entry.row;
    if (row !== null) {
      stats.fileCount++;
      stats.totalBytes += row.size;
    }
  }
  return stats;
}

// 批量删除确认文案（三态分支单源；守「面向用户文案写作规约」——并列分句用句号、无冒号分号括号
// 连环）：纯文件报件数；含文件夹按两类分报，文件夹内部非空追加子树合计句；删除总量非零才报合计
export function workspaceMultiselectMessage(stats: WorkspaceMultiselectStats): string {
  let who: string;
  if (stats.folderCount > 0 && stats.fileCount > 0) {
    who = stats.folderCount + ' 个文件夹和 ' + stats.fileCount + ' 个文件';
  } else if (stats.folderCount > 0) {
    who = stats.folderCount + ' 个文件夹';
  } else {
    who = stats.fileCount + ' 个文件';
  }
  let message: string = '将删除选中的 ' + who;
  if (stats.innerFileCount > 0) {
    message += '，连同文件夹里的内容共 ' + stats.innerFileCount + ' 个文件';
  }
  if (stats.totalBytes > 0) {
    message += '，合计 ' + formatWorkspaceSize(stats.totalBytes);
  }
  return message + '。删除后无法恢复。';
}

// 临时段多选（扫盘驱动视图，数据不进父页 entries）
// 选中行载荷：经 onSelectRows 上行给壳——壳的可见集/全选/反查/统计全吃「当前层行集」，folder 段走
// WorkspaceListEntry、临时段走本载荷。key = 行基础键（与 WorkspaceTmpView LazyForEach 键的基础段同源单值）；
// name 组行恒 ''（整组清理按 conversationId 定位）、文件行 = 文件名；size 组行 = 组占用字节、文件行 = 文件字节
export interface WorkspaceTmpSelectRow {
  key: string;
  conversationId: string;
  name: string;
  size: number;
  isGroup: boolean;
}

// 选中键集 → 当前临时行集（批量删除执行前反查单源，勿在别处重造）：键缺失 = 陈旧选中，静默跳过（同前口径）
export function workspaceTmpMultiselectTargets(rows: WorkspaceTmpSelectRow[],
  selectedKeys: string[]): WorkspaceTmpSelectRow[] {
  const targets: WorkspaceTmpSelectRow[] = [];
  for (const key of selectedKeys) {
    for (const row of rows) {
      if (row.key === key) {
        targets.push(row);
        break;
      }
    }
  }
  return targets;
}

// 临时段批量删除确认文案（组级/文件级两态单源；守「面向用户文案写作规约」）：组级报会话组数（每组
// 的临时文件整组清理）、文件级报件数；合计非零才报。空集返回空串（调用方首行守卫，理论不可达）
export function workspaceTmpMultiselectMessage(targets: WorkspaceTmpSelectRow[]): string {
  if (targets.length === 0) {
    return '';
  }
  let bytes: number = 0;
  for (const row of targets) {
    bytes += row.size;
  }
  const who: string = targets[0].isGroup
    ? targets.length + ' 个会话的临时文件' : targets.length + ' 个临时文件';
  let message: string = '将删除选中的 ' + who;
  if (bytes > 0) {
    message += '，合计 ' + formatWorkspaceSize(bytes);
  }
  return message + '。删除后无法恢复。';
}
