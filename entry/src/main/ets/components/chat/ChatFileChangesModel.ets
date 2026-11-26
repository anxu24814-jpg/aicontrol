// 会话改动清单聚合模型（任务② 会话改动文件清单与 diff 查看，U1）：轮内 role='tool' 行
// 内存现算「本轮改了哪些文件」——纯函数、零 UI 渲染依赖、零 DB 依赖、零缓存（聚合 = 装配期
// 一次算成，调用方 = ChatDisplayProjection.buildDisplayItems 轮末出卡；渲染件只消费产物，
// 卡侧禁再聚合禁缓存——宪法「组件生命周期禁高耗时」与「性能不许愿」双红线）。
// · 为什么单独成件（反碎片三问）：①职责一句话 = 工具行 → 轮级文件改动清单的纯派生；
//   ②不并入 ChatDisplayProjection——投影件管分组与身份，本件管文件域聚合（七件工具名单、
//   alias 归并、红绿统计口径），混装会让投影件膨胀且断言提取面互缠；③实逻辑非转接壳。
// · 统计口径（卡片红绿数字唯一事实源）：edit = argsJson 替换对行数（旧 3 新 5 → +5 −3，
//   勿用回执「行数 A→B」差值——全文净差拆不成两数）；write 覆盖（回执尾行在场）=
//   receiptPairDiffFromOutput（摘录对 = 各侧摘录行数〔≤2000 字符/侧截断，摘录行数 < 全文
//   行数的低估边界为既有 D3 有界拍板语义，明示继承〕、超阈档〔旧文 > 120000 字符〕=
//   oldLines/newLines 全文行数对）；write 新建（无尾行）= deriveToolDiffRows('', content)
//   全绿；import / xlsx / rename / move / delete 恒 null 不贡献。卡头总统计 = 各文件之和。
//   ★ write「新建 vs 覆盖」判别 = 回执尾行在场 → 覆盖档；无尾行 → 新建档全绿（A-致1 裁）。
//   历史旧覆盖行（diff 覆盖批之前无尾行）会被判成新建 → 统计虚高，属已知边界在变更记录
//   申报，不查库（零新增查询红线）。
// · 过滤口径：toolName ∈ 七件工作区写工具**全名**（一律引 ToolIds 常量、禁裸字面量——族
//   前缀省写按字面过滤六件全漏）且 toolState === 'done'——running / error / cancelled 三态
//   一律不计（语义严格覆盖「isError 不计」）。
// · alias 归并（rename/move 旧名链追到现名，一行显现名 = 最终名）：按「当前 dir+name」索引
//   行对象，rename/move 命中即迁移索引与显示名。保守缺省三处：①dir 取 argsJson 原值轻归一
//   （'/' → ''、trim；空串不猜助手默认文件夹——同轮写法一致即命中，跨写法裂行属保守边界）；
//   ②rename/move 目标键撞既有行时索引以后者为准（罕见，模型侧罕见操作面）；③模型对旧名
//   再操作（rename 后又 edit 旧名）按新行处理。
//   ★ ①的下游边界（dir 缺省语义分歧，2026-11-04 修复笔申报）：工具执行侧缺省 dir 会解析为
//   助手默认文件夹（normalizeWorkspaceDirParam——assistants/<id>），本模型只读 argsJson 原
//   值、ChatMessage 行/轮上下文无 assistantId 可复原该解析（回执不带落点、会话级现值非轮
//   执行快照）——故 dir 空的行**落点语义不明**（可能助手默认文件夹、也可能真根目录）。消
//   费面保守口径：清单卡与详情面板 dir 空不显示目录段、详情面板定位键 dir 空不跳转（toast
//   呈报），均不标「根目录」防误导。
// · 数据有界：文件行上限 20（超出进 overflowCount；上限是拍板常数，断言 345 组契约钉）；
//   deleted 态 = 轮内存在成功 delete 命中该文件（含 alias 链）→ true，不查库（轮级口径）。
// · 依赖方向：本件 → ChatMessageCompose（消息模型）/ ToolIds（工具名常量叶子）/
//   ChatToolDiffBlock（diff 派生纯函数——该件头注释红线只约束其内部派生区零跨件 import，
//   本件 import 其导出合法且必须，复用即单源：计数与 U5 面板重派生同源同函数）。
import { ChatMessage } from './ChatMessageCompose';
import { TOOL_WORKSPACE_DELETE, TOOL_WORKSPACE_EDIT, TOOL_WORKSPACE_IMPORT,
  TOOL_WORKSPACE_MOVE, TOOL_WORKSPACE_RENAME, TOOL_WORKSPACE_WRITE,
  TOOL_WORKSPACE_WRITE_XLSX } from '../../common/providers/ToolIds';
import { ToolDiffView, deriveToolDiffRows, parseJsonRecord,
  receiptPairDiffFromOutput, workspaceEditDiffFromInput } from './ChatToolDiffBlock';

// 操作种类（FileChangeOp.kind / FileChangeEntry.lastOpKind 的值域；U3 徽标映射按此判档）
export const OP_EDIT: string = 'edit';
export const OP_WRITE_NEW: string = 'writeNew';
export const OP_WRITE_OVERWRITE: string = 'writeOverwrite';
export const OP_IMPORT: string = 'import';
export const OP_XLSX: string = 'xlsx';
export const OP_RENAME: string = 'rename';
export const OP_MOVE: string = 'move';
export const OP_DELETE: string = 'delete';

// 文件行上限（超出进 overflowCount；「另有 N 个文件」溢出行消费）
export const ROUND_FILE_CHANGES_MAX_FILES: number = 20;

// 单次操作的计数载荷（null = 该操作不贡献红绿：import/xlsx/rename/move/delete 与坏数据档）
interface OpCounts {
  additions: number | null;
  deletions: number | null;
}

// 聚合期行内部状态（出口转 FileChangeEntry；数组保序 = 首次操作消息序——排序保守缺省）
interface RowState {
  displayName: string;
  dir: string;
  deleted: boolean;
  additionsSum: number;
  deletionsSum: number;
  hasStats: boolean;
  ops: FileChangeOp[];
}

// 单文件操作流水（时间序 = 消息序；msg = 源工具行引用——U5 面板开时按此重派生 diff rows）
export interface FileChangeOp {
  kind: string;
  timeMs: number;
  additions: number | null;
  deletions: number | null;
  msg: ChatMessage;
}

// 文件行（清单卡一行 / 详情面板一文件的载荷；additions/deletions = 该文件全部操作之和，
// 三族贡献者才非 null——渲染侧按 null 隐藏红绿）
export interface FileChangeEntry {
  displayName: string;
  dir: string;
  deleted: boolean;
  lastOpKind: string;
  additions: number | null;
  deletions: number | null;
  ops: FileChangeOp[];
}

// 轮级聚合产物（DISPLAY_KIND_FILE_CHANGES 展示项的 fileChanges 字段；装配期一次算成）
export interface RoundFileChanges {
  roundId: string;
  files: FileChangeEntry[];
  overflowCount: number;
  totalAdditions: number;
  totalDeletions: number;
}

// args 取串（ToolWorkspace.argsString 同形；模型侧自持不跨引——该函数未导出）
function argsStringOf(args: Record<string, Object> | null, key: string): string {
  if (args === null) {
    return '';
  }
  const raw: Object | undefined = args[key];
  return typeof raw === 'string' ? raw : '';
}

// dir 轻归一（模型侧保守口径：'/' → ''、trim；空串不猜助手默认文件夹——见头注释保守缺省①）
function normalizeDirKey(raw: string): string {
  const trimmed: string = raw.trim();
  return trimmed === '/' ? '' : trimmed;
}

// 行索引键（dir 与 name 以 \u0000 连接——工作区名禁控制字符，分隔无歧义）
function rowKeyOf(dir: string, name: string): string {
  return dir + '\u0000' + name;
}

// 取或建行（目标 (dir, name) 经当前索引解析——rename/move 迁移后旧名自然失配、新名命中）
function ensureRow(rows: RowState[], byKey: Map<string, RowState>,
  dir: string, name: string): RowState {
  const key: string = rowKeyOf(dir, name);
  const hit: RowState | undefined = byKey.get(key);
  if (hit !== undefined) {
    return hit;
  }
  const state: RowState = { displayName: name, dir: dir, deleted: false,
    additionsSum: 0, deletionsSum: 0, hasStats: false, ops: [] };
  rows.push(state);
  byKey.set(key, state);
  return state;
}

// rename/move 迁移（旧名链 → 新位置）：源行在场则**迁移源对象**（改显示名 + 换索引键），
// 一行显现名恒为最终名；源未首现（rename/move 是该文件本轮首个操作）则以新位置建行。
// 目标键撞既有行时索引以后者为准（保守缺省②，见头注释）。
function migrateRow(rows: RowState[], byKey: Map<string, RowState>,
  fromDir: string, fromName: string, toDir: string, toName: string): RowState {
  const fromKey: string = rowKeyOf(fromDir, fromName);
  const hit: RowState | undefined = byKey.get(fromKey);
  if (hit !== undefined) {
    byKey.delete(fromKey);
    hit.displayName = toName;
    hit.dir = toDir;
    byKey.set(rowKeyOf(toDir, toName), hit);
    return hit;
  }
  return ensureRow(rows, byKey, toDir, toName);
}

// 操作种类判定（write 双档判别 = 回执尾行在场与否，与 opCountsFor 同判据同源）
function opKindOf(tool: string, row: ChatMessage): string {
  if (tool === TOOL_WORKSPACE_WRITE) {
    return receiptPairDiffFromOutput(row.toolOutputJson ?? '', 0, 0) !== null
      ? OP_WRITE_OVERWRITE : OP_WRITE_NEW;
  }
  if (tool === TOOL_WORKSPACE_EDIT) {
    return OP_EDIT;
  }
  if (tool === TOOL_WORKSPACE_IMPORT) {
    return OP_IMPORT;
  }
  if (tool === TOOL_WORKSPACE_WRITE_XLSX) {
    return OP_XLSX;
  }
  if (tool === TOOL_WORKSPACE_RENAME) {
    return OP_RENAME;
  }
  if (tool === TOOL_WORKSPACE_MOVE) {
    return OP_MOVE;
  }
  return OP_DELETE;
}

// 单操作计数（口径单源见头注释统计口径节；maxRows 传 0——只取全文行数计数、不产展示行，
// rows 由 U5 面板开时按 ops[].msg 重派生）
function opCountsFor(tool: string, row: ChatMessage,
  args: Record<string, Object> | null): OpCounts {
  if (tool === TOOL_WORKSPACE_EDIT) {
    const view: ToolDiffView | null = workspaceEditDiffFromInput(row.toolInputJson ?? '', 0, 0);
    if (view === null) {
      return { additions: null, deletions: null };
    }
    return { additions: view.additions, deletions: view.deletions };
  }
  if (tool === TOOL_WORKSPACE_WRITE) {
    // 覆盖判别：回执尾行在场（receiptPairDiffFromOutput 解析得键组）→ 覆盖档统计；
    // 无尾行（新建 / 历史旧覆盖行误判档）→ 新建档全绿（deriveToolDiffRows('', content)）
    const view: ToolDiffView | null = receiptPairDiffFromOutput(row.toolOutputJson ?? '', 0, 0);
    if (view !== null) {
      return { additions: view.additions, deletions: view.deletions };
    }
    const content: string = argsStringOf(args, 'content');
    const fresh: ToolDiffView = deriveToolDiffRows('', content, 0, 0);
    return { additions: fresh.additions, deletions: fresh.deletions };
  }
  return { additions: null, deletions: null };
}

// ── 主入口（纯函数可直接直跑）──
// 入参 = 轮 id + 轮内全部行（调用方常传轮内 kind='tool' 行；函数内再做七件全名 + done 过滤，
// 非名单行静默跳过）；files 为空（零改动轮 / 重试剔行后空轮）回 null——调用方据此不出卡。
export function deriveRoundFileChanges(roundId: string,
  roundToolRows: ChatMessage[]): RoundFileChanges | null {
  const rows: RowState[] = [];
  const byKey: Map<string, RowState> = new Map();
  for (const row of roundToolRows) {
    if (row.toolState !== 'done') {
      continue; // running / error / cancelled 一律不计
    }
    const tool: string = row.toolName;
    if (tool !== TOOL_WORKSPACE_WRITE && tool !== TOOL_WORKSPACE_EDIT &&
      tool !== TOOL_WORKSPACE_IMPORT && tool !== TOOL_WORKSPACE_WRITE_XLSX &&
      tool !== TOOL_WORKSPACE_RENAME && tool !== TOOL_WORKSPACE_MOVE &&
      tool !== TOOL_WORKSPACE_DELETE) {
      continue; // 名单外工具零聚合
    }
    const args: Record<string, Object> | null = parseJsonRecord(row.toolInputJson ?? '');
    const name: string = argsStringOf(args, 'name').trim();
    if (name === '') {
      continue; // 坏 args / 缺名行无法归属文件，防御跳过
    }
    const dir: string = normalizeDirKey(argsStringOf(args, 'dir'));
    if (tool === TOOL_WORKSPACE_RENAME && argsStringOf(args, 'new_name').trim() === '') {
      continue; // rename 缺新名（坏 args 防御）——无法迁移，跳过
    }
    const opKind: string = opKindOf(tool, row);
    const counts: OpCounts = opCountsFor(tool, row, args);
    const state: RowState = tool === TOOL_WORKSPACE_RENAME
      ? migrateRow(rows, byKey, dir, name, dir, argsStringOf(args, 'new_name').trim())
      : (tool === TOOL_WORKSPACE_MOVE
        ? migrateRow(rows, byKey, dir, name, normalizeDirKey(argsStringOf(args, 'to_dir')), name)
        : ensureRow(rows, byKey, dir, name));
    if (tool === TOOL_WORKSPACE_DELETE) {
      state.deleted = true; // 轮级口径：不查库，轮内 delete 命中即标
    }
    state.ops.push({ kind: opKind, timeMs: row.createdAt ?? 0,
      additions: counts.additions, deletions: counts.deletions, msg: row });
    if (counts.additions !== null || counts.deletions !== null) {
      state.hasStats = true;
      state.additionsSum += counts.additions ?? 0;
      state.deletionsSum += counts.deletions ?? 0;
    }
  }
  if (rows.length === 0) {
    return null;
  }
  const files: FileChangeEntry[] = [];
  let totalAdditions: number = 0;
  let totalDeletions: number = 0;
  for (const state of rows) {
    totalAdditions += state.additionsSum;
    totalDeletions += state.deletionsSum;
    if (files.length >= ROUND_FILE_CHANGES_MAX_FILES) {
      continue; // 溢出行不进 files（卡头总统计仍含全部行——轮总口径）
    }
    const ops: FileChangeOp[] = state.ops;
    files.push({ displayName: state.displayName, dir: state.dir,
      deleted: state.deleted, lastOpKind: ops[ops.length - 1].kind,
      additions: state.hasStats ? state.additionsSum : null,
      deletions: state.hasStats ? state.deletionsSum : null, ops: ops });
  }
  return { roundId: roundId, files: files,
    overflowCount: rows.length - files.length,
    totalAdditions: totalAdditions, totalDeletions: totalDeletions };
}
