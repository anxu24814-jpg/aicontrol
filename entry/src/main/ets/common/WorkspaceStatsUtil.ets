// 工作区数据统计纯函数域：管理页标题栏「更多」→「数据总览」半模态的类型分类与聚合单源
// ——五类（文本 / 表格 / 图片 / 文档 / 其他）固定序、总数恒等于五行相加（口径红线同上下文
// 用量面板「各行相加能对上总数」）。
// 域职责一句话：给定文件行集（工作区侧）或扫盘简报集（临时侧），产出「总件数 / 总大小 /
// 附加计数（文件夹数或会话数）/ 五类明细」的载荷——零 IO、零 DB、零 UI。
// · 单开新件不并入 WorkspaceUtil（彼件已越 1200 硬线在案续期），且统计口径是独立职责缝
//  （分类复用既有 classifyWorkspaceName，聚合与固定序成组）。
// · 依赖纪律：唯一 import = WorkspaceUtil（WorkspaceFileRow 类型 + classifyWorkspaceName /
//   extOfWorkspaceName / isWorkspaceDirRow 三值，全局单源不设第二份抄写）；零 kit、零 store、
//   零工具域。断言直跑 = assert-workspace-domain 303 组复制本件为 .tmp 副本
//  （interface 导入行剥除 + 值导入改指 .tmp 副本）。
// · 消费方：WorkspaceManagePage（工作区侧现派生：负荷载 = 内存行集）与 WorkspaceDbTmp
//   .scanWorkspaceTmpOverview（临时侧现扫盘：一次扫全，简报映射后过本件聚合）。
// · 统计分类与文件分类（kind）的关系：kind 四档是「可预览性」分类（xlsx 归 doc、csv 归
//   text），统计面按用户语义把 xlsx / xls / csv 单列「表格」——判定先于 classify 特判，
//   其余三档与 classify 同源（详见 workspaceStatCategoryOf）。
import { WorkspaceFileRow } from './WorkspaceUtil';
import { classifyWorkspaceName, extOfWorkspaceName, isWorkspaceDirRow } from './WorkspaceUtil';

// ── 类别键（五值单源；UI 行标签经 workspaceStatCategoryLabel 派生，禁散写中文字面量）──
export const WS_STAT_TEXT: string = 'text';
export const WS_STAT_SHEET: string = 'sheet';
export const WS_STAT_IMAGE: string = 'image';
export const WS_STAT_DOC: string = 'doc';
export const WS_STAT_OTHER: string = 'other';

// 表格扩展名（统计专档）：xlsx / xls 在文件分类档归 doc（可系统预览）、csv 归 text（可读），
// 统计面按用户语义单列「表格」；本表只服务统计分类，勿与 WorkspaceUtil 白名单互替
const SHEET_EXTS: string[] = ['xlsx', 'xls', 'csv'];

// 行序单源（面板恒按本序渲染，零值行补齐——行序稳定不跳动）
export const WS_STAT_ORDER: string[] = [WS_STAT_TEXT, WS_STAT_SHEET, WS_STAT_IMAGE,
  WS_STAT_DOC, WS_STAT_OTHER];

// 统计输入行最小面（{名, 大小}——工作区行集与临时区简报皆可映射传入；本件不持行类型依赖）
export interface WorkspaceStatFile {
  name: string;
  size: number;
}

// 单类统计（count / bytes 逐类累计；五行相加 = 总件数与总大小）
export interface WorkspaceTypeStat {
  category: string;
  count: number;
  bytes: number;
}

// 面板载荷（subCount 语义随侧：工作区侧 = 文件夹数〔目录行数〕，临时侧 = 会话数〔非空会话
// 目录数〕；两侧 UI 文案经消费方按侧派生）
export interface WorkspaceDataStats {
  fileCount: number;
  bytes: number;
  subCount: number;
  types: WorkspaceTypeStat[];
}

// 统计分类（单一判据）：表格特判先行（见文件头注释），其余复用文件分类——image / text /
// doc 各归其位，白名单外与无扩展名（classify 回 ''）落「其他」；大小写经 extOf 归一
export function workspaceStatCategoryOf(name: string): string {
  const ext: string = extOfWorkspaceName(name);
  if (SHEET_EXTS.indexOf(ext) >= 0) {
    return WS_STAT_SHEET;
  }
  const kind: string = classifyWorkspaceName(name);
  if (kind === 'image') {
    return WS_STAT_IMAGE;
  }
  if (kind === 'text') {
    return WS_STAT_TEXT;
  }
  if (kind === 'doc') {
    return WS_STAT_DOC;
  }
  return WS_STAT_OTHER;
}

// 类别中文名（面板行标签；未知键回「其他」——不谎报）
export function workspaceStatCategoryLabel(category: string): string {
  if (category === WS_STAT_TEXT) {
    return '文本';
  }
  if (category === WS_STAT_SHEET) {
    return '表格';
  }
  if (category === WS_STAT_IMAGE) {
    return '图片';
  }
  if (category === WS_STAT_DOC) {
    return '文档';
  }
  return '其他';
}

// 五类固定序聚合（零值行补齐；总数与总大小 = 五行相加——单一出口，消费方禁自行求和
// 作第二口径）。核心导出：两侧载荷函数（含行集过滤）都收敛到本函数，断言直跑钉行序与归位
export function deriveWorkspaceDataStats(files: WorkspaceStatFile[],
  subCount: number): WorkspaceDataStats {
  const map: Map<string, WorkspaceTypeStat> = new Map<string, WorkspaceTypeStat>();
  for (const category of WS_STAT_ORDER) {
    map.set(category, { category: category, count: 0, bytes: 0 });
  }
  for (const file of files) {
    const hit: WorkspaceTypeStat | undefined = map.get(workspaceStatCategoryOf(file.name));
    if (hit !== undefined) {
      hit.count++;
      hit.bytes += file.size;
    }
  }
  const types: WorkspaceTypeStat[] = [];
  let fileCount: number = 0;
  let bytes: number = 0;
  for (const category of WS_STAT_ORDER) {
    const row: WorkspaceTypeStat | undefined = map.get(category);
    if (row === undefined) {
      continue;
    }
    types.push(row);
    fileCount += row.count;
    bytes += row.bytes;
  }
  return { fileCount: fileCount, bytes: bytes, subCount: subCount, types: types };
}

// 工作区侧载荷（输入 = 页面全表行集）：目录行排除件数与容量、单数文件夹数——与
// queryWorkspaceTotal「文件夹不计件数不占容量」口径同源；行集有界（文件行 ≤ 件数闸），
// 全量派生无截断面
export function buildWorkspaceDataStats(rows: WorkspaceFileRow[]): WorkspaceDataStats {
  const files: WorkspaceStatFile[] = [];
  let folders: number = 0;
  for (const row of rows) {
    if (isWorkspaceDirRow(row)) {
      folders++;
      continue;
    }
    files.push({ name: row.name, size: row.size });
  }
  return deriveWorkspaceDataStats(files, folders);
}

// 临时区侧载荷（输入 = 扫盘简报集 + 非空会话目录数；同一扫盘一次取全，零二次扫描）
export function buildTmpDataStats(files: WorkspaceStatFile[],
  conversations: number): WorkspaceDataStats {
  return deriveWorkspaceDataStats(files, conversations);
}
