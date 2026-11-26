// 图会话读写路径域：会话在 graph / 旧格式墓碑两态下的**读写路径单点**——读侧（尾部窗口/
// 翻页/摘要绑定视图，旁路读者与页面加载共用）＋写侧（图命令编排，已迁 ChatGraphCommandSource）
// ＋路由判据（conversationWritableRoute 纯读口 + bornGraphConversation 出生原语）。
// 迁移机制（迁移器/启动强迁/失败黑名单/migrating 锁定态）已整件退役——旧格式会话不再迁移，
// 呈墓碑由用户自行删除。
// 依赖方向（零环红线，坑50）：本件 → ChatDb（路由读口/句柄/窗口常量）+ MessageBranchDb
//（读页/分支读口与类型）+ ChatBranchPolicy（判据叶子：父链轻行类型）单向；**store 侧零件
// 反向 import 本件**；ChatGraphCommandSource/ChatBranchSource 两新件单向 import 本件（本件
// 零 import 新件）；组件层只 import 本件或两新件，不经它们触达冻结命令层（对接面收敛）。
// seq 列语义登记：graph 会话节点的 messages.seq = 节点入链单调序号（写入侧分配器随提交
// 铸造），**不是图路径的排序真源**（图排序真源 = parent 链）；它承载 summary_bindings 的
// seq 区间裁剪语义（K4/K9）与账本等既有消费面。
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { queryLatestBoundary, queryLatestSummary } from '../store/CompressDb';
import { QUERY_TAIL_LIMIT, MessageRow, ConversationOverride, ensureConversation,
  nextMessageId, queryConversationActiveBranch,
  queryConversationMigrateState, sharedRdbStore } from '../store/ChatDb';
import { readGraphCapabilityLevel, writeGraphCapabilityLevel } from '../store/ChatDbMigrate';
import { CONV_STATE_GRAPH, BranchRow, GraphPathRow,
  readPathPage, queryBranch } from '../store/MessageBranchDb';
import { runWriteQueued } from '../store/DbWriteQueue';
// 判据叶子（零依赖件）：父链轻行类型单源——本件只做读写组装，判据归彼件
//（★ 2026-10-06 拆分笔：墓碑文案消费随 adoptGraphSummary 迁 ChatGraphCommandSource）
import { BranchAnchorRow } from './ChatBranchPolicy';

const DOMAIN: number = 0x71C6;
const TAG: string = 'ChatContextSource';

// ── 读侧：路由窗口（路由二值化后非 graph 态恒回空/拒写按墓碑走）──

// 路径翻页锚：branchId 防切分支后旧锚跨分支误用；oldestNodeId = 当前窗口最早节点。
// 切分支后调用方 reanchor（ChatDataSource.reanchorBranch）
export interface PathAnchorCursor {
  branchId: string;
  oldestNodeId: string;
}

// 会话态轻判（页面/读者路由用；'' = 非图态）。经 ChatDb 单点口，禁直查列
export async function conversationGraphBranch(conversationId: string): Promise<string> {
  return queryConversationActiveBranch(conversationId);
}

export async function conversationMigrateState(conversationId: string): Promise<string> {
  return queryConversationMigrateState(conversationId);
}

// 尾部窗口路由读（旁路读者与页面加载共用：graph = 沿当前分支 parent 链读一页，同形返回
// MessageRow[]——消费方零改动换口）。legacy 支已随线性读路径退役——无分支（未出生/旧格式
// 墓碑/坏库）回空数组 fail-closed，旁路读者（标题/建议/记忆）按无内容静默放弃
export async function readRecentRows(conversationId: string,
  limit: number = QUERY_TAIL_LIMIT): Promise<MessageRow[]> {
  const branchId: string = await queryConversationActiveBranch(conversationId);
  if (branchId === '') {
    return [];
  }
  return readPathPageRows(conversationId, branchId, null, limit);
}

// 路径翻页（graph）：cursorNodeId = 上一页最早节点（readPathPage 翻页语义：不含自身）。
// 读出后统一过 adaptPathRows 补 seq 与摘要绑定投影
export async function readPathPageRows(conversationId: string, branchId: string,
  cursorNodeId: string | null, limit: number): Promise<MessageRow[]> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const pathRows: GraphPathRow[] = await readPathPage(db, branchId, cursorNodeId, limit);
  return adaptPathRows(db, conversationId, pathRows);
}

// GraphPathRow → MessageRow 适配（读侧单点）：补三块图侧投影——
// ①seq：readPathPage 冻结投影不带 seq（K12 禁改签名），按页内节点 id 一次 IN 查询合并
//  （页有界；NULL 防御 fail-open）；②quote_text（v61 引用快照）与 server_tools（v64 DS 服务端
//   工具原样串，S3.0 随形）同查询顺路补投影（NULL = 无引用/无服务端步骤不挂）；③摘要绑定：
//   graph 摘要行 coversToSeq **列恒 NULL（K3 档案化）**，边界
//   真源 = summary_bindings 行——绑定边界并进投影 coversToSeq，既有裁剪判据（buildRequestHistory
//   末摘要胜出 + rowSeq ≤ boundary）零改动生效；绑定缺失或值 NULL（不可证态）→ 不投影 =
//   不裁剪（fail-open，「保留可读文本禁裁剪」天然成立）。
// 生效**边界**行唯一投影选择（★ 修复 A-2 纯函数面，直跑断言可验；边界家族 = summary〔摘要〕|
//   clear〔清空〕，函数名沿历史不改）：rows 序 = 最早在前（readPathPage 升序契约），
//   **末次**命中有绑定边界行 = 距 head 最近的有绑定者 = 当前路径生效边界——与
//   findPathSummaryRow「head 上溯第一条有绑定即生效」同源同解。返回 '' = 页内无绑定边界行
//   （生效边界在窗口外滑出态）。绑定值 NULL 也算「有绑定」：生效性看绑定在不在，可证性
//   只影响投不投影，两判据分离
export function effectiveSummaryIdOf(rows: MessageRow[],
  bindings: Map<string, number | null>): string {
  let effective: string = '';
  for (const r of rows) {
    if ((r.role === 'summary' || r.role === 'clear') && bindings.has(r.id)) {
      effective = r.id;
    }
  }
  return effective;
}

async function adaptPathRows(db: relationalStore.RdbStore, conversationId: string,
  pathRows: GraphPathRow[]): Promise<MessageRow[]> {
  const rows: MessageRow[] = [];
  for (const p of pathRows) {
    rows.push({
      id: p.id,
      conversationId: p.conversationId,
      role: p.role,
      content: p.content,
      reasoning: p.reasoning,
      status: p.status,
      createdAt: p.createdAt,
      variants: '',
      variantActive: 0
    });
  }
  if (rows.length === 0) {
    return rows;
  }
  // ①seq 合并（一次 IN 查询）——quote_text（v61 引用全文快照）与 server_tools（v64 DS 服务端
  // 工具原样串，S3.0 投影随形）同查询顺路补投影（NULL = 无引用/无服务端步骤不挂）。本查询是
  // 页面回放与请求历史两条读链的唯一上游 SELECT（readPathPageRows 单点），列随形在此一处
  const ids: string[] = [];
  for (const r of rows) {
    ids.push(r.id);
  }
  const seqResult: relationalStore.ResultSet = await db.querySql(
    'SELECT id, seq, quote_text, server_tools FROM messages WHERE conversationId = ? AND id IN (' +
    ids.map((_id: string): string => '?').join(',') + ')',
    [conversationId].concat(ids));
  const seqBy: Map<string, number> = new Map<string, number>();
  const quoteBy: Map<string, string> = new Map<string, string>();
  const serverToolsBy: Map<string, string> = new Map<string, string>();
  try {
    while (seqResult.goToNextRow()) {
      const seqIdx: number = seqResult.getColumnIndex('seq');
      if (!seqResult.isColumnNull(seqIdx)) {
        seqBy.set(seqResult.getString(seqResult.getColumnIndex('id')),
          seqResult.getLong(seqIdx));
      }
      const quoteIdx: number = seqResult.getColumnIndex('quote_text');
      if (!seqResult.isColumnNull(quoteIdx)) {
        quoteBy.set(seqResult.getString(seqResult.getColumnIndex('id')),
          seqResult.getString(quoteIdx));
      }
      const stIdx: number = seqResult.getColumnIndex('server_tools');
      if (!seqResult.isColumnNull(stIdx)) {
        serverToolsBy.set(seqResult.getString(seqResult.getColumnIndex('id')),
          seqResult.getString(stIdx));
      }
    }
  } finally {
    seqResult.close();
  }
  // ②摘要绑定合并（会话级一次取全；每会话摘要行个位数，量级可忽略）
  const bindings: Map<string, number | null> = new Map<string, number | null>();
  const bindResult: relationalStore.ResultSet = await db.querySql(
    'SELECT summaryMessageId, coversToSeq FROM summary_bindings WHERE conversationId = ?',
    [conversationId]);
  try {
    while (bindResult.goToNextRow()) {
      const toIdx: number = bindResult.getColumnIndex('coversToSeq');
      bindings.set(bindResult.getString(bindResult.getColumnIndex('summaryMessageId')),
        bindResult.isColumnNull(toIdx) ? null : bindResult.getLong(toIdx));
    }
  } finally {
    bindResult.close();
  }
  // 生效摘要唯一投影（★ 修复 A-2）：S2 采用语义下旧绑定摘要行是档案（采用不删旧 binding），
  // 若页内任何有绑定者都投影，重复压缩后的会话重进会渲染多条「上下文已压缩」提示行、且旧
  // 边界照旧参与请求裁剪——与请求侧 findPathSummaryRow 只认生效摘要两侧分叉。现只对距 head
  // 最近的有绑定者投影（判据 effectiveSummaryIdOf），档案行不投影 = 不渲染不裁剪，屏/面板/
  // 请求三方同源
  const effectiveId: string = effectiveSummaryIdOf(rows, bindings);
  for (const r of rows) {
    const seq: number | undefined = seqBy.get(r.id);
    if (seq !== undefined) {
      r.seq = seq;
    }
    // v61 引用全文快照投影（user 行有意义；NULL = 无引用不挂）
    const quote: string | undefined = quoteBy.get(r.id);
    if (quote !== undefined) {
      r.quoteText = quote;
    }
    // v64 服务端工具原样串投影（assistant 行有意义；NULL = 非官方档轮不挂——S3.0 投影随形，
    // 消费方 = chatMessagesFromRows 行投影 → 回传与渲染）
    const serverTools: string | undefined = serverToolsBy.get(r.id);
    if (serverTools !== undefined) {
      r.serverTools = serverTools;
    }
    if ((r.role === 'summary' || r.role === 'clear') && r.id === effectiveId) {
      const boundary: number | null = bindings.get(r.id) ?? null;
      if (boundary !== null) {
        r.coversToSeq = boundary;
      }
    }
  }
  return rows;
}

// ── 可达路径（跨会话读面的图路径过滤单点）──

// 可达节点 id 链序表（纯函数，断言直跑可验）：从 headId 沿 parentMessageId 上行标记可达，
// 返回**链序 root→head**（读窗口切片序 = 最早在前）。步数上界 512 防坏链死循环；悬边
//（parent 不在锚集 = 坏链/跨会话脏数据）即停——已收节点都是真路径节点，不猜补。
// headId null/'' → 空表
export function reachableIdsOf(headId: string | null,
  anchors: Map<string, BranchAnchorRow>): string[] {
  const up: string[] = [];
  let cursor: string | null = headId;
  let steps: number = 0;
  while (cursor !== null && cursor !== '' && steps < 512) {
    const row: BranchAnchorRow | undefined = anchors.get(cursor);
    if (row === undefined) {
      break; // 悬边防御：路径到此为止（已收节点仍有效）
    }
    up.push(cursor);
    cursor = row.parentMessageId;
    steps++;
  }
  const out: string[] = [];
  for (let i: number = up.length - 1; i >= 0; i--) {
    out.push(up[i]);
  }
  return out;
}

// 会话可达节点链序表（读口：一次轻行集 + 内存上行，无逐行查库）。
// ★ 空表语义（非 graph 态与坏库态一律回空集——本版本不读旧格式的线性行）：**两消费方各自
// 处置，语义不统一**——①get_chats 读取面按「不可读」呈报墓碑句；②search_chats 检索面
// **空表不过滤**（原样放行命中，见 ToolChatSearch.filterHitsByReachablePaths 注释）。②的
// 放行语义与墓碑口径是否一致属**待拍板项**（止损口径：搜索仍依赖旧会话数据 → 呈报不改）
export async function readReachableNodeIds(conversationId: string): Promise<string[]> {
  const branchId: string = await queryConversationActiveBranch(conversationId);
  if (branchId === '') {
    return [];
  }
  const db: relationalStore.RdbStore = sharedRdbStore();
  const branch: BranchRow | null = await queryBranch(db, branchId);
  if (branch === null) {
    return [];
  }
  const anchors: Map<string, BranchAnchorRow> = await readBranchAnchors(conversationId);
  return reachableIdsOf(branch.headMessageId, anchors);
}

// 图写命令族已整段迁 ChatGraphCommandSource.ets（发送起轮/工具事实两写/轮提交/收尾/账本/
// 重试起轮等）——本件留读侧、采用核验口（isNodeOnActivePath）与下方 queryNodeRow。

// 目标答案节点行（重试前读锚点与旧内容用；坏 id 回 null）。留本件不迁：findPathSummaryRow
//（边界读域）消费它，迁出会成主件↔新件反向依赖。列枚举含 quote_text（导出面防御性完整——
// 消费方 summary 行无引用语义，NULL = 不挂）
export async function queryNodeRow(nodeId: string): Promise<MessageRow | null> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT id, conversationId, role, content, reasoning, status, createdAt, seq, quote_text ' +
    'FROM messages WHERE id = ?', [nodeId]);
  try {
    if (!result.goToNextRow()) {
      return null;
    }
    const row: MessageRow = {
      id: result.getString(result.getColumnIndex('id')),
      conversationId: result.getString(result.getColumnIndex('conversationId')),
      role: result.getString(result.getColumnIndex('role')),
      content: result.getString(result.getColumnIndex('content')),
      reasoning: result.getString(result.getColumnIndex('reasoning')),
      status: result.getString(result.getColumnIndex('status')),
      createdAt: result.getLong(result.getColumnIndex('createdAt'))
    };
    const seqIdx: number = result.getColumnIndex('seq');
    if (!result.isColumnNull(seqIdx)) {
      row.seq = result.getLong(seqIdx);
    }
    const quoteIdx: number = result.getColumnIndex('quote_text');
    if (!result.isColumnNull(quoteIdx)) {
      row.quoteText = result.getString(quoteIdx);
    }
    return row;
  } finally {
    result.close();
  }
}

// ── 压缩收口 ──

// 边界节点路径有效性核验（采用事务核预览范围须在当前路径有效）：从分支 head 沿 parent 链
// 上溯找边界节点——命中 = 预览范围仍在当前路径（切分支后共享前缀上的边界仍有效）；走尽
// 未命中 = 路径已变化，过时摘要不得裁新路径。步数上界 1024 防坏链
export async function isNodeOnActivePath(conversationId: string, branchId: string,
  nodeId: string): Promise<boolean> {
  if (nodeId === '') {
    return false;
  }
  const db: relationalStore.RdbStore = sharedRdbStore();
  const branch: BranchRow | null = await queryBranch(db, branchId);
  if (branch === null || branch.headMessageId === null) {
    return false;
  }
  let cursor: string | null = branch.headMessageId;
  let steps: number = 0;
  while (cursor !== null && steps < 1024) {
    if (cursor === nodeId) {
      return true;
    }
    const result: relationalStore.ResultSet = await db.querySql(
      'SELECT parentMessageId FROM messages WHERE id = ?', [cursor]);
    try {
      if (!result.goToNextRow()) {
        return false; // 悬边防御
      }
      const parentIdx: number = result.getColumnIndex('parentMessageId');
      cursor = result.isColumnNull(parentIdx) ? null : result.getString(parentIdx);
    } finally {
      result.close();
    }
    steps++;
  }
  return false;
}

// 摘要两写口 adoptGraphSummary/deleteGraphSummary 已迁 ChatGraphCommandSource.ets。

// ── 边界读口（S9 路径感知；对 summary/clear 两类边界同权）──

// 路径链上溯步数上界（防坏链；摘要节点恒靠头，实读远小于此）。
// ★ 同名常量在 ChatGraphCommandSource.ets 另有一份（断言锚「两锚同件」要求）——**改值时两处同改**
const SUMMARY_PATH_STEPS_MAX: number = 512;

// 摘要绑定探针（三态）：bound=false = 该摘要行无绑定（档案行，非生效摘要）；bound=true 且
// provable=false = 绑定在但边界值 NULL（不可证摘要，读侧不裁剪）；provable=true = 可证边界
interface SummaryBindingProbe {
  bound: boolean;
  provable: boolean;
  coversToSeq: number;
}

// 摘要绑定读（graph 边界真源 = summary_bindings 行）：排序键 = createdAt DESC + rowid DESC
// 决胜（同毫秒多 binding 的确定性；summary_bindings 非消息时间线，不受「消息窗口禁
// createdAt 序」钉管辖——该钉保护对象 = messages 窗口）
async function readSummaryBinding(db: relationalStore.RdbStore,
  summaryMessageId: string): Promise<SummaryBindingProbe> {
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT coversToSeq FROM summary_bindings WHERE summaryMessageId = ? ' +
    'ORDER BY createdAt DESC, rowid DESC LIMIT 1', [summaryMessageId]);
  try {
    if (!result.goToNextRow()) {
      const miss: SummaryBindingProbe = { bound: false, provable: false, coversToSeq: 0 };
      return miss;
    }
    const toIdx: number = result.getColumnIndex('coversToSeq');
    if (result.isColumnNull(toIdx)) {
      const unprovable: SummaryBindingProbe = { bound: true, provable: false, coversToSeq: 0 };
      return unprovable;
    }
    const hit: SummaryBindingProbe = { bound: true, provable: true,
      coversToSeq: result.getLong(toIdx) };
    return hit;
  } finally {
    result.close();
  }
}

// 路径链生效**边界**定位（graph）：从分支 head 沿 parentMessageId 上溯，第一条**有绑定**的
// 边界节点（summary〔摘要〕| clear〔清空〕，wantRole='' 两类都要、各取一类可指定）即当前
// 路径的生效边界；无绑定的边界行是档案（S2 语义下不再生效），跳过续溯；走尽 = null（无
// 边界——请求侧回全文，与「删全部 binding 即回全文」自洽）。坏链（节点行缺失）回 null
// 不猜。★ clear 行 content 恒空——判「无正文」不回 null，边界值本身成立。
// ContextClear.readLatestClearRow 复用本上溯
export async function findPathSummaryRow(db: relationalStore.RdbStore,
  headMessageId: string | null, wantRole: string = ''): Promise<MessageRow | null> {
  let cursor: string | null = headMessageId;
  let steps: number = 0;
  while (cursor !== null && cursor !== '' && steps < SUMMARY_PATH_STEPS_MAX) {
    const probe: relationalStore.ResultSet = await db.querySql(
      'SELECT role, parentMessageId FROM messages WHERE id = ?', [cursor]);
    let role: string = '';
    let parent: string | null = null;
    try {
      if (!probe.goToNextRow()) {
        return null; // 悬边（父链指向不存在的行）
      }
      role = probe.getString(probe.getColumnIndex('role'));
      const parentIdx: number = probe.getColumnIndex('parentMessageId');
      parent = probe.isColumnNull(parentIdx) ? null : probe.getString(parentIdx);
    } finally {
      probe.close();
    }
    if ((role === 'summary' || role === 'clear') && (wantRole === '' || role === wantRole)) {
      const binding: SummaryBindingProbe = await readSummaryBinding(db, cursor);
      if (binding.bound) {
        const node: MessageRow | null = await queryNodeRow(cursor);
        if (node === null) {
          return null; // 半条链不猜（同悬边防御）
        }
        // 绑定值为 NULL（不可证摘要，P3 污染库迁移产物）→ 投影 undefined = 不裁剪；
        // 摘要行列值不可信（图身份迁移不维护 coversToSeq 列），一律以绑定为准
        node.coversToSeq = binding.provable ? binding.coversToSeq : undefined;
        return node;
      }
    }
    cursor = parent;
    steps++;
  }
  return null;
}

// 最新摘要行（绑定感知路由读）：graph 会话按**当前分支路径链**定位生效摘要——全局 seq DESC
// 取到的行可能属已弃用分支（切分支后旧分支摘要 seq 更大即被当生效摘要，而请求侧按路径
// 不裁剪 ⇒ 面板说「已压缩」实际没压）。legacy 直通支已退役——无分支即无可证摘要，回 null
// fail-closed（未出生会话本就无摘要行已早退；旧格式墓碑/坏库不按全局 seq 兜底——那正是
// 本函数要治的口径）。面板状态行与「未定界」判定两消费方零改动换口
export async function readLatestSummaryRow(conversationId: string): Promise<MessageRow | null> {
  const row: MessageRow | null = await queryLatestSummary(conversationId);
  if (row === null) {
    return null;
  }
  const branchId: string = await queryConversationActiveBranch(conversationId);
  if (branchId === '') {
    return null;
  }
  const db: relationalStore.RdbStore = sharedRdbStore();
  const branch: BranchRow | null = await queryBranch(db, branchId);
  if (branch === null) {
    return null; // 图态而无分支行 = 坏库：不按全局 seq 兜底（那正是本函数要治的口径）
  }
  return findPathSummaryRow(db, branch.headMessageId, 'summary');
}

// ── 请求侧摘要注入 ──

// 请求预扫的注入形态（buildRequestHistory 兼容入参——boundary ≤ 0 = 无注入）。
// kind='summary' 时 summaryText = 摘要正文；kind='clear' 时恒 ''（清空不带正文，boundary
// 是唯一载荷）；消费方判据 =「boundary > 0」。类型名沿历史不改
export interface RequestSummaryInput {
  kind: string;        // 'summary' | 'clear'
  summaryText: string; // clear 恒 ''
  boundary: number;
}

// 路径生效**边界**的请求侧读口：图摘要节点滑出尾部读窗后内存窗口无 summary 行 ⇒ 请求既无
// 摘要也无裁剪，而面板按库直查仍报「已压缩」——两侧口径分叉，本口把库直查（findPathSummaryRow
// 路径感知）供给请求组装侧。边界两类同权返回（kind 随行）；clear 行 content 恒空**不算不可
// 注入**（原判据「content === ''→null」只对摘要成立——清空的载荷是 boundary）。调用序 =
// 窗口预扫为主、本口只补窗口落空者；空会话 id 与读失败均回 null：fail-open 走无注入
//（窗口预扫兜底），不阻断发送
export async function readPathSummaryInput(
  conversationId: string): Promise<RequestSummaryInput | null> {
  if (conversationId === '') {
    return null;
  }
  try {
    const probe: MessageRow | null = await queryLatestBoundary(conversationId);
    if (probe === null) {
      return null; // 会话内一条边界行都没有——零上溯（省查形状同旧实现）
    }
    const branchId: string = await queryConversationActiveBranch(conversationId);
    if (branchId === '') {
      return null;
    }
    const db: relationalStore.RdbStore = sharedRdbStore();
    const branch: BranchRow | null = await queryBranch(db, branchId);
    if (branch === null) {
      return null;
    }
    const row: MessageRow | null = await findPathSummaryRow(db, branch.headMessageId, '');
    if (row === null) {
      return null; // 边界行都在已弃用分支上（当前路径无边界）
    }
    const boundary: number = row.coversToSeq ?? 0;
    if (boundary <= 0) {
      return null; // 不可证边界（绑定值 NULL）→ 不裁剪不注入（fail-open，与读侧同判）
    }
    if (row.role === 'summary' && row.content === '') {
      return null; // 摘要行却无正文 = 异常行，不注入（原判据照留；清空行不受此判）
    }
    const input: RequestSummaryInput = { kind: row.role,
      summaryText: row.role === 'summary' ? row.content : '', boundary: boundary };
    return input;
  } catch (e) {
    // 读失败留痕（★ 修复 A-8：静默 null 会让面板照报「已压缩」而请求按全文发，两侧口径
    // 静默分叉且无可查痕迹）
    hilog.warn(DOMAIN, TAG, '路径边界读取失败，本轮按无注入发送：%{public}s',
      (e as Error).message);
    return null;
  }
}

// 分支域已整段迁 ChatBranchSource.ets（分支列表读/切分支/建分支/附件回挂/父链定位）。

// 会话父链轻行集（中途整轮重试的锚点预校验输入面）：一次取全会话节点 id/parentMessageId/
// role——ChatBranchPolicy.resolveRunInputAnchor 与 validateBoundaryReachable 的输入（纯函数
// 直跑面与生产预检共用同一形状）。属地属分支域但**留本件**：本件读侧 readReachableNodeIds
// 消费它（迁出会成主件↔新件反向依赖环）；分支新件零 import 本件，消费方 ChatRetryCtrl
// 照旧从本件取。节点数百量级、锚预检低频（用户点一次重试一次），不分页（性能不许愿红线）
export async function readBranchAnchors(conversationId: string):
  Promise<Map<string, BranchAnchorRow>> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT id, parentMessageId, role FROM messages WHERE conversationId = ?',
    [conversationId]);
  const out: Map<string, BranchAnchorRow> = new Map<string, BranchAnchorRow>();
  try {
    while (result.goToNextRow()) {
      const parentIdx: number = result.getColumnIndex('parentMessageId');
      const id: string = result.getString(result.getColumnIndex('id'));
      out.set(id, {
        id: id,
        parentMessageId: result.isColumnNull(parentIdx) ? null : result.getString(parentIdx),
        role: result.getString(result.getColumnIndex('role'))
      });
    }
  } finally {
    result.close();
  }
  return out;
}

// ★ 行存在性读口：true = 会话已落行（已出生）；false = 懒建中转未落行——首开链据此直接
// 渲染空历史（无行即无格式态可判，不调路由口）
export async function conversationHasRow(conversationId: string): Promise<boolean> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', conversationId);
  const row: relationalStore.ResultSet = await db.query(predicates, ['id']);
  const hasRow: boolean = row.rowCount > 0;
  row.close();
  return hasRow;
}

// ── 会话可写路由二值（**纯读口**：只判「能不能写」，出生移到写入装载点
// ChatGraphWriteCtrl.loadRoute）──
// 'graph' = 会话可走图读写；'blocked' = 不可写（旧格式墓碑/历史 migrating 残值/脏值/
// graph 态空分支/态读异常），调用方须**停止写入**（fail-closed）。blocked 会话数据仍在
// messages 表——页面侧由墓碑覆盖层显式呈报（ChatPageContent），长按会话由删除链清掉
export const ROUTE_GRAPH: string = 'graph';
export const ROUTE_BLOCKED: string = 'blocked';

// 路由事实纯函数 + 融合装载口：fresh 进页链原对同一 conversations 行串行往返 5 次（存在 1 +
// 路由口内部 3 + 分支 1），融合口一次读 {migrateState, activeBranchId} 两列收 1 次；判据
// 单源经 routeFromFacts（conversationWritableRoute + conversationLoadRoute 两消费方共享，
// 防两口径漂移）

// 路由事实纯函数：无行 → ROUTE_GRAPH；state ≠ graph → ROUTE_BLOCKED（「非 graph 即墓碑」
// 单源判据）；空分支 → ROUTE_BLOCKED；否则 ROUTE_GRAPH。判据顺序 = 先行存在性后态
//（无行就是未出生——按「态读口无行回 legacy」判墓碑会把全新会话误判成墓碑）
export function routeFromFacts(hasRow: boolean, state: string, branchId: string): string {
  if (!hasRow) {
    return ROUTE_GRAPH;
  }
  if (state !== CONV_STATE_GRAPH) {
    return ROUTE_BLOCKED;
  }
  return branchId === '' ? ROUTE_BLOCKED : ROUTE_GRAPH;
}

// 融合装载路由读口（纯读零副作用）：一次 query 出 hasRow / route / branchId 三件；无行 →
// {false, ROUTE_GRAPH, ''}。branchId **钳位读**（state === 'graph' ? rawBranch : ''，对齐
// queryConversationActiveBranch 钳位语义）——禁直读列原值：非 graph 行残留 activeBranchId
// 时不钳则 route=BLOCKED 而 branchId≠''，消费方 readPathPageRows 会真执行。查询异常**上抛**
//（P0-1 不静默吞），调用方 catch 各自 fail-closed
export interface ConversationLoadRoute {
  hasRow: boolean;
  route: string;
  branchId: string;
}

export async function conversationLoadRoute(cid: string): Promise<ConversationLoadRoute> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', cid);
  const row: relationalStore.ResultSet = await db.query(predicates,
    ['migrateState', 'activeBranchId']);
  try {
    if (row.rowCount === 0) {
      const unborn: ConversationLoadRoute = { hasRow: false, route: ROUTE_GRAPH, branchId: '' };
      return unborn;
    }
    row.goToNextRow();
    const state: string = row.getString(row.getColumnIndex('migrateState'));
    const rawBranch: string = row.getString(row.getColumnIndex('activeBranchId'));
    const plan: ConversationLoadRoute = {
      hasRow: true,
      route: routeFromFacts(true, state, rawBranch),
      branchId: state === CONV_STATE_GRAPH ? rawBranch : ''
    };
    return plan;
  } finally {
    row.close();
  }
}

// 会话可写路由读口（**纯读零副作用**）：返值推导经 routeFromFacts 单源——无行 → GRAPH
//（未出生 = 可写；出生在写入时由 bornGraphConversation 一步完成）；graph 且有活跃分支 →
// GRAPH；graph 空分支（导入残迹/坏库）→ BLOCKED（fail-closed）；其余态（legacy 墓碑/
// migrating 残值/任何脏值）→ BLOCKED（**非 graph 即墓碑**，不逐值特判）。查询序保持逐级
// 早退（非 graph 态不查分支）；态读异常上抛，调用方各自 fail-closed（P0-1 不静默吞）。
export async function conversationWritableRoute(conversationId: string): Promise<string> {
  const hasRow: boolean = await conversationHasRow(conversationId);
  if (!hasRow) {
    return routeFromFacts(false, '', '');
  }
  const state: string = await queryConversationMigrateState(conversationId);
  if (state !== CONV_STATE_GRAPH) {
    return routeFromFacts(true, state, '');
  }
  const branchId: string = await queryConversationActiveBranch(conversationId);
  return routeFromFacts(true, state, branchId);
}

// ★ 出生即 graph 原语（**单事务**）：无行会话首写时一步建行（含归属助手/提示词/覆盖三列
//——ensureConversation 单源，与 insertMessage 同款）+ branches 空分支（head null 是合法
// 态）+ 置 migrateState='graph' 与 activeBranchId，三写同事务（P0-1 不半建）。
// 返回值 = 活跃分支 id（'' = 出生未发生或失败——并发他口已出生〔事务内复核让位〕或事务
// 失败；调用方一律 fail-closed 拒写，下一次装载按库态自愈重判）。override 落值语义 =
// ensureConversation 覆盖三列。
// capability 写 2 随出生进行（K2 时点契约的图侧半边：图会话在场 ⇒ 能力级必须 ≥2，附件
// 收敛器的图侧判据读它——buildAttachmentGraphCleanup）。
// ★ 签名与返回值不变（ProactiveGen 主动消息链依赖）。
export async function bornGraphConversation(conversationId: string,
  ensureAssistantId: string, ensurePromptId: string,
  ensureOverride: ConversationOverride | null): Promise<string> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const branchId: string = nextMessageId('br');
  const now: number = Date.now();
  // ★ 事务段入写串行链（capability 写 2 为幂等单语句写留链外）
  return runWriteQueued('bornGraphConversation', async (): Promise<string> => {
    db.beginTransaction();
    try {
      // 行存在性复核**在事务内**（并发他口已出生 → 让位返回 ''，不覆盖既有格态节点）
      const predicates: relationalStore.RdbPredicates =
        new relationalStore.RdbPredicates('conversations');
      predicates.equalTo('id', conversationId);
      const probe: relationalStore.ResultSet = await db.query(predicates, ['id']);
      let hasRow: boolean = false;
      try {
        hasRow = probe.rowCount > 0;
      } finally {
        probe.close();
      }
      if (hasRow) {
        db.rollBack();
        return '';
      }
      await ensureConversation(conversationId, ensureAssistantId, ensurePromptId,
        ensureOverride);
      await db.insert('branches', {
        'id': branchId,
        'conversationId': conversationId,
        'parentBranchId': null,
        'headMessageId': null,
        'name': '',
        'createdAt': now
      });
      await db.executeSql('UPDATE conversations SET migrateState = ?, activeBranchId = ? ' +
        'WHERE id = ?', [CONV_STATE_GRAPH, branchId, conversationId]);
      db.commit();
    } catch (e) {
      db.rollBack();
      throw e as Error;
    }
    return branchId;
  }).then(async (bornBranchId: string): Promise<string> => {
    // K2 时点：capability 写 2（幂等——已在 2 零写）。★ 让位支（''，并发他口已出生）也执行
    // 本写 = **有意扩展而非原语义**：让位即图会话已在他口出生，K2 契约「图会话在场 ⇒ 能力级
    // ≥2」仍应满足，且幂等单调无观察方依赖「让位不写」。事务失败支 then 不落地跳过
    const level: number = await readGraphCapabilityLevel(db);
    if (level < 2) {
      await writeGraphCapabilityLevel(db, 2);
    }
    return bornBranchId;
  });
}

