// 独立会话 fork 复制编排域：**把源会话的一条图路径前缀物化成独立新会话**（copyConversationPrefix）
// ——跨资源复制编排（冻结校验 / 映射表 / 附件资源文件准备 / 单事务发布 / 失败收敛，五段一体）。
// 职责与 MessageBranchDb（分支持久命令域）不同，无同域可并、非转接壳（反碎片三问已答，不并 ChatDb
// / ExportImport——后者 M11 禁把备份往返冒充 fork 复制）。
// · 依赖方向（零环红线，坑50）：本件 → ChatDb（id 铸造 / 库句柄 / 格式态读写单点；词表两值
//   graph/legacy）+ MessageBranchDb（词表常量 / 图插入校验 / 祖先链纯函数）+ AttachmentDb（资源行
//   与文件面）+ MessageSeqDb（seq 铸造）单向，四件不反向 import 本件；库句柄经 sharedRdbStore
//   （生产唯一库）。
// · 不变量锚（M 表，逐条对应本件落点）：M2 前缀完整与源冻结（同一读时点快照 + 发布前复核）；
//   M3 身份新铸与单一映射表（范围外引用一律不带入）；M4 历史 run 终态不可执行（status 恒
//   finished、checkpoint 不复制、来源标识不落库）；M5 资源事务（先文件后元数据、元数据与 refs
//   同一发布事务）；M6 摘要 binding 可重映射才复制（不可证 → 边界置空 = 禁裁剪，不引用源摘要）；
//   M7 零网络零执行零计费（不触网络、不调账本写口）；M8 源删除后独立（副本零引用源行与源文件）；
//   M9 路由（非 graph 一律拒绝——仓储侧 fail-closed）；M10 配置口径（有效配置快照随行，标题 =
//   composeCopyTitle 前缀版——副本不再与源同名；favorite 取新会话默认值、suggestions
//   不复制）；M11 冻结契约（不改词表 / 命令签名 / schema / 迁移 / 备份格式）；M12 失败与残留收敛
//   （文件准备失败即清新文件，不发布半会话、不损源）。
// · 事务纪律（J6）：全部多写在同一 createTransaction(IMMEDIATE) 事务内（会话 / 分支 / 节点 / run /
//   工具事实 / 摘要绑定 / 附件行 / refs）；文件准备在事务之前（M5 两段式），失败即回滚 + 清新文件。
//   快照读一律走 createTransaction(DEFERRED) 事务对象查询（tx.querySql），不用 store 直查——
//   连接池下防读出两个时点。
// · 禁 mock：纯函数段（截断 / 映射 / 收敛 / 重映射）另有 node 直跑断言面（assert-store-consistency
//   组），DB 命令段属真库/真机项。
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MessageAttachmentRow, copyAttachmentResource, removeAttachmentFiles } from './AttachmentDb';
import { nextMessageId, queryConversationActiveBranch, queryConversationMigrateState,
  sharedRdbStore } from './ChatDb';
import { CONV_STATE_GRAPH, GraphNodeRef, ORIGIN_FORK, RUN_STATUS_FINISHED,
  TOOL_FACT_FAILED, TOOL_FACT_RESULT_CONFIRMED, traceAncestorChain } from './MessageBranchDb';
import { nextRowSeq } from './MessageSeqDb';
import { runWriteQueued } from './DbWriteQueue';
import { TOMBSTONE_TOAST_TEXT } from '../chat/ChatBranchPolicy';

const DOMAIN: number = 0xD5A6;
const TAG: string = 'ConversationForkCopy';

// ── 值域与口径常量 ──

// 附件目录名（与 AttachmentDb.ATTACH_DIR_NAME / AttachmentUtil.ATTACH_DIR 同值；三处互不
// import，靠断言钉一致——本件只用于拼计划里的新相对路径，文件写入仍交 AttachmentDb 文件面）
const ATTACH_DIR_NAME: string = 'attachments';
// 路径链上溯步数上限（坏链防御；正常会话节点数百量级）
const CHAIN_MAX_STEPS: number = 4096;

// ── 纯函数段（映射与收敛——断言直跑面；顶层零外部绑定求值，坑50 纪律）──

// 前缀行（messages 投影 + seq）：比 GraphPathRow 多 seq（摘要边界重映射要用旧 seq 定位节点）、
// 少 variants/variant_active（K3 档案化列，图读写不用）
export interface CopyPrefixRow {
  id: string;
  role: string;
  content: string;
  reasoning: string;
  status: string;
  createdAt: number;
  parentMessageId: string | null;
  runId: string;
  ownerAssistantId: string;
  stepIndex: number | null;
  origin: string;
  seq: number; // -1 = 无号（NULL）
  quoteText: string; // '' = 无引用（DB v61 引用全文快照——fork 副本保真带引用，漏 = 静默语义损失）
  // v64 服务端工具快照（2026-11-14 DS 全家桶接入批 S2，assistant 行专用）：'' = 无服务端步骤
  serverTools: string;
}

// 源 run 行（generation_runs 投影；只取复制所需列）
export interface CopyRunRow {
  id: string;
  branchId: string;
  attemptEpoch: number;
  inputAnchorMessageId: string;
  revision: number;
  status: string;
  diagnosticMessageId: string;
  createdAt: number;
  updatedAt: number;
}

// 源工具事实行（tool_facts 投影）
export interface CopyFactRow {
  id: string;
  runId: string;
  attemptId: string;
  name: string;
  state: string;
  payload: string;
  result: string;
  createdAt: number;
  finishedAt: number; // v54 终态时刻（0 = 无终态时刻；原值透传，不随态收敛补戳）
}

// 源摘要绑定行（summary_bindings 投影）
export interface CopyBindingRow {
  id: string;
  summaryMessageId: string;
  coversFromSeq: number | null;
  coversToSeq: number | null;
  dependsOnBindingId: string;
  createdAt: number;
}

// 源附件引用行（attachment_refs 投影——归属真源）
export interface CopyAttachmentRefRow {
  attachmentId: string;
  nodeId: string;
}

// 复制计划输入（源快照 + 铸造器注入：id 与 seq 两类铸造均由调用方绑定——纯函数不触全局）。
// ★ 原 now 字段为死参数（行时间落在 publishCopy 侧，取 CopyPrefixInput.now）——已删，勿回落
export interface CopyPlanInput {
  newConversationId: string;
  newBranchId: string;
  boundaryNodeId: string;
  // 沿活动路径的祖先链（根 → 源 head 升序；本函数按边界截断）
  chainRows: CopyPrefixRow[];
  runs: CopyRunRow[];
  facts: CopyFactRow[];
  bindings: CopyBindingRow[];
  attachmentRows: MessageAttachmentRow[];
  attachmentRefs: CopyAttachmentRefRow[];
  mintId: (prefix: string) => string;
  mintSeq: () => number;
}

// 计划产物：可直接入库的行形状（字段名与库列同名，装配层零映射）
export interface CopyPlanNode {
  id: string;
  conversationId: string;
  role: string;
  content: string;
  reasoning: string;
  status: string;
  createdAt: number;
  parentMessageId: string | null;
  runId: string;
  ownerAssistantId: string;
  stepIndex: number | null;
  origin: string;
  seq: number;
  quoteText: string; // '' = 不写 quote_text 键（列落 NULL）
  // v64 服务端工具快照（2026-11-14 DS 全家桶接入批 S2，assistant 行专用——fork 副本保真带
  // 官方步骤数据，漏 = fork 后步骤行/来源卡消失 + 官方档续聊回传缺料（静默语义损失））
  serverTools: string; // '' = 不写 server_tools 键（列落 NULL）
}

export interface CopyPlanRun {
  id: string;
  conversationId: string;
  branchId: string;
  attemptEpoch: number;
  inputAnchorMessageId: string;
  revision: number;
  status: string;
  checkpoint: string;
  diagnosticMessageId: string;
  createdAt: number;
  updatedAt: number;
}

export interface CopyPlanFact {
  id: string;
  runId: string;
  attemptId: string;
  name: string;
  state: string;
  payload: string;
  result: string;
  createdAt: number;
  finishedAt: number;
}

export interface CopyPlanBinding {
  id: string;
  conversationId: string;
  summaryMessageId: string;
  coversFromSeq: number | null;
  coversToSeq: number | null;
  dependsOnBindingId: string;
  createdAt: number;
}

// 附件资源计划（分类镜像：legacy 归类写重映射后的 messageId、graph 归类写空串占位 + 建 refs）
export interface CopyPlanAttachment {
  sourceLocalPath: string;
  newAttachmentId: string;
  newFileName: string; // <新 id><源扩展名>
  messageId: string;   // '' = graph 归类（占位不表达归属，归属走 refs）
  nodeIds: string[];   // graph 归类需建 refs 的新节点集
  kind: string;
  name: string;
  mime: string;
  size: number;
  parsedText: string;
  createdAt: number;
}

export interface ConversationCopyPlan {
  nodes: CopyPlanNode[];
  runs: CopyPlanRun[];
  facts: CopyPlanFact[];
  bindings: CopyPlanBinding[];
  attachments: CopyPlanAttachment[];
  // 未随副本复制的 run（锚点不在前缀内 / 行缺失——范围外引用不带入 M3）：登记用，非错误
  droppedRunIds: string[];
}

// 路径截断（M2：复制内容 = 所选边界（含）之前沿活动路径的完整前缀，无后续泄漏）：
// chainRows 须为「根 → head」升序（上游沿 parent 链上溯后反转）；返回 根→边界（含）；
// 边界不在链上（或链空）回 null——调用方按明确文案拒绝，不猜不截近邻
export function truncatePrefixPath(chainRows: CopyPrefixRow[],
  boundaryNodeId: string): CopyPrefixRow[] | null {
  if (boundaryNodeId === '') {
    return null;
  }
  const out: CopyPrefixRow[] = [];
  for (const row of chainRows) {
    out.push(row);
    if (row.id === boundaryNodeId) {
      return out;
    }
  }
  return null;
}

// run 终态收敛（M4）：副本内 run 一律终态、不可执行——源终态值不改变「不可执行」语义，
// 故恒返 finished（在途/未知不呈现；M7「零重放」的可见面）
export function convergeRunStatus(_srcStatus: string): string {
  return RUN_STATUS_FINISHED;
}

// 工具事实终态收敛（M4/M7）：已确认结果与明确失败原样保留（历史事实）；其余态
//（prepared / dispatch_intent——含「执行结果未知」）一律收敛为明确失败——副本里不得出现
// 在途态（那是假警报），也不得改写成 result_confirmed（伪造未发生的结果）
export function convergeToolFactState(srcState: string): string {
  if (srcState === TOOL_FACT_RESULT_CONFIRMED || srcState === TOOL_FACT_FAILED) {
    return srcState;
  }
  return TOOL_FACT_FAILED;
}

// attemptId 重映射（M3：attemptId 由 runId + '#a' + attemptEpoch 派生，不独立铸造）：
// 源 attemptId 形如 <源 runId>#a<epoch>——前缀匹配则换新 runId，否则按 run 的 epoch 派生兜底
export function remapAttemptId(srcAttemptId: string, srcRunId: string, newRunId: string,
  epoch: number): string {
  const mark: string = '#a';
  const idx: number = srcAttemptId.indexOf(mark);
  if (idx >= 0 && srcAttemptId.substring(0, idx) === srcRunId) {
    return newRunId + srcAttemptId.substring(idx);
  }
  return newRunId + mark + epoch.toString();
}

// 源相对路径的扩展名（含点；无扩展名回 ''）——新文件名 = <新 id><ext>，与既有落盘命名
// （<fileId>.<ext>）同族。取最后一个点，且点须在最后一个 '/' 之后（目录名里的点不算）
export function extOfLocalPath(localPath: string): string {
  const cut: number = localPath.lastIndexOf('.');
  if (cut < 0 || cut < localPath.lastIndexOf('/')) {
    return '';
  }
  return localPath.substring(cut);
}

// 复制计划（S1③「先算后写」+ M3 单一映射表）：一次算出四张映射表（节点 / 分支 / run / 附件
// 资源）与全部入库行——映射表只在本函数构造，装配层照抄不另算。
// 契约：
// · 边界不在链上 → null（调用方拒绝，不出半计划）；
// · **范围外引用一律不带入**：父链断点归 null（根语义）、节点 runId 指向前缀外的 run 归 ''、
//   诊断节点引用不在前缀内归 ''、attachment refs 只挂前缀内节点、摘要 binding 的依赖不在
//   副本内归 ''；
// · 未随副本复制的 run 记入 droppedRunIds（锚点不在前缀内或行缺失——不静默：调用方登记）；
// · seq 按路径序自 mintSeq 铸造（新会话 0 基连续；文档序 = 图路径序，与既有写入点同源口径）
export function planConversationCopy(input: CopyPlanInput): ConversationCopyPlan | null {
  const prefix: CopyPrefixRow[] | null =
    truncatePrefixPath(input.chainRows, input.boundaryNodeId);
  if (prefix === null || prefix.length === 0) {
    return null;
  }
  const prefixIds: Set<string> = new Set<string>();
  for (const row of prefix) {
    prefixIds.add(row.id);
  }
  // ① 节点映射（前缀内一一对应）
  const nodeMap: Map<string, string> = new Map<string, string>();
  for (const row of prefix) {
    nodeMap.set(row.id, input.mintId('msg'));
  }
  // ② run 映射（只收「输入锚点在前缀内」者——锚在前缀外的 run 不可在副本内自洽）
  const runMap: Map<string, string> = new Map<string, string>();
  const dropped: string[] = [];
  const seenRun: Set<string> = new Set<string>();
  for (const row of prefix) {
    if (row.runId === '' || seenRun.has(row.runId)) {
      continue;
    }
    seenRun.add(row.runId);
    let src: CopyRunRow | null = null;
    for (const run of input.runs) {
      if (run.id === row.runId) {
        src = run;
        break;
      }
    }
    if (src === null || src.inputAnchorMessageId === '' ||
      !prefixIds.has(src.inputAnchorMessageId)) {
      dropped.push(row.runId);
      continue;
    }
    runMap.set(row.runId, input.mintId('run'));
  }
  // ③ 节点行（父链重映射 + seq 重建 + origin 标来源语义）
  const oldSeqToNew: Map<number, number> = new Map<number, number>();
  const nodes: CopyPlanNode[] = [];
  for (const row of prefix) {
    const seq: number = input.mintSeq();
    if (row.seq >= 0) {
      oldSeqToNew.set(row.seq, seq);
    }
    const parent: string | null = row.parentMessageId;
    nodes.push({
      id: nodeMap.get(row.id) as string,
      conversationId: input.newConversationId,
      role: row.role,
      content: row.content,
      reasoning: row.reasoning,
      status: row.status,
      createdAt: row.createdAt,
      parentMessageId: parent === null ? null : (nodeMap.get(parent) ?? null),
      runId: runMap.get(row.runId) ?? '',
      ownerAssistantId: row.ownerAssistantId,
      stepIndex: row.stepIndex,
      origin: ORIGIN_FORK,
      seq: seq,
      quoteText: row.quoteText,
      serverTools: row.serverTools
    });
  }
  // ④ run 行（终态、不可执行；checkpoint 不复制执行中间态）
  const runs: CopyPlanRun[] = [];
  for (const src of input.runs) {
    const newId: string | undefined = runMap.get(src.id);
    if (newId === undefined) {
      continue;
    }
    const anchor: string | undefined = nodeMap.get(src.inputAnchorMessageId);
    runs.push({
      id: newId,
      conversationId: input.newConversationId,
      branchId: input.newBranchId,
      attemptEpoch: src.attemptEpoch,
      inputAnchorMessageId: anchor ?? '',
      revision: src.revision,
      status: convergeRunStatus(src.status),
      checkpoint: '',
      diagnosticMessageId: nodeMap.get(src.diagnosticMessageId) ?? '',
      createdAt: src.createdAt,
      updatedAt: src.updatedAt
    });
  }
  // ⑤ 工具事实行（归属副本 run；态收敛；结果/参数原文随行 = 历史事实）
  const facts: CopyPlanFact[] = [];
  for (const fact of input.facts) {
    const newRunId: string | undefined = runMap.get(fact.runId);
    if (newRunId === undefined) {
      continue;
    }
    let epoch: number = 1;
    for (const run of input.runs) {
      if (run.id === fact.runId) {
        epoch = run.attemptEpoch;
        break;
      }
    }
    facts.push({
      id: input.mintId('tf'),
      runId: newRunId,
      attemptId: remapAttemptId(fact.attemptId, fact.runId, newRunId, epoch),
      name: fact.name,
      state: convergeToolFactState(fact.state),
      payload: fact.payload,
      result: fact.result,
      createdAt: fact.createdAt,
      finishedAt: fact.finishedAt
    });
  }
  // ⑥ 摘要 binding（M6：覆盖与依赖完全在前缀内且可重映射者才复制；不可证 → 边界置空 = 禁自动
  // 裁剪）。两步：先铸 binding id 映射表（依赖重映射要用），再装配行——依赖指向副本外者置空
  const bindingIdMap: Map<string, string> = new Map<string, string>();
  for (const b of input.bindings) {
    if (prefixIds.has(b.summaryMessageId)) {
      bindingIdMap.set(b.id, input.mintId('sbd'));
    }
  }
  const bindings: CopyPlanBinding[] = [];
  for (const b of input.bindings) {
    const newSummary: string | undefined = nodeMap.get(b.summaryMessageId);
    const newId: string | undefined = bindingIdMap.get(b.id);
    if (newSummary === undefined || newId === undefined) {
      continue;
    }
    const fromSeq: number | null = b.coversFromSeq === null ? null
      : (oldSeqToNew.get(b.coversFromSeq) ?? null);
    const toSeq: number | null = b.coversToSeq === null ? null
      : (oldSeqToNew.get(b.coversToSeq) ?? null);
    bindings.push({
      id: newId,
      conversationId: input.newConversationId,
      summaryMessageId: newSummary,
      coversFromSeq: fromSeq,
      coversToSeq: toSeq,
      dependsOnBindingId: bindingIdMap.get(b.dependsOnBindingId) ?? '',
      createdAt: b.createdAt
    });
  }
  // ⑦ 附件资源（分类镜像：源行 messageId 非空 = legacy 归类 → 写重映射后节点 id；空串 = graph
  // 归类 → 保持空串占位 + 建 refs。禁把空串占位规则用到 legacy 资源、也禁把 legacy 改写成 refs
  // 单源——两源联合读口按源分类各自生效）。先算可达集（M2：只复制前缀可达资源）
  const refsByAttachment: Map<string, string[]> = new Map<string, string[]>();
  const reachable: Set<string> = new Set<string>();
  for (const row of input.attachmentRows) {
    if (row.messageId !== '' && prefixIds.has(row.messageId)) {
      reachable.add(row.id);
    }
  }
  for (const ref of input.attachmentRefs) {
    const newOwner: string | undefined = nodeMap.get(ref.nodeId);
    if (newOwner === undefined) {
      continue; // 前缀外引用不带入
    }
    reachable.add(ref.attachmentId);
    const held: string[] | undefined = refsByAttachment.get(ref.attachmentId);
    if (held === undefined) {
      refsByAttachment.set(ref.attachmentId, [newOwner]);
    } else if (!held.includes(newOwner)) {
      held.push(newOwner);
    }
  }
  const attachments: CopyPlanAttachment[] = [];
  const seenAttachment: Set<string> = new Set<string>();
  for (const row of input.attachmentRows) {
    if (seenAttachment.has(row.id) || !reachable.has(row.id)) {
      continue;
    }
    seenAttachment.add(row.id);
    const newId: string = input.mintId('att');
    const legacyOwner: string = row.messageId !== '' ? (nodeMap.get(row.messageId) ?? '') : '';
    attachments.push({
      sourceLocalPath: row.localPath,
      newAttachmentId: newId,
      newFileName: newId + extOfLocalPath(row.localPath),
      messageId: legacyOwner,
      nodeIds: refsByAttachment.get(row.id) ?? [],
      kind: row.kind,
      name: row.name,
      mime: row.mime,
      size: row.size,
      parsedText: row.parsedText,
      createdAt: row.createdAt
    });
  }
  return { nodes: nodes, runs: runs, facts: facts, bindings: bindings,
    attachments: attachments, droppedRunIds: dropped };
}

// 副本标题前缀词形（「（副本N）」全角括号半角数字；基题剥离与族计数共用同一 regex，
// 禁第二份手写匹配——两处漂移即同族误判）
const COPY_TITLE_MARK_RE: RegExp = /^（副本(\d+)）/;

// 副本标题（M10：副本不再与源同名——「（副本N）」+ 基题）。基题 = 源标题剥去自身已有前缀
// （副本的副本不叠层）；N = 同基题族（「恰等于基题」或「（副本M）+基题」的行，源行占基题位
// 不占号）最大序号 + 1，无同类 N=1。守卫：源标题真空（含纯空白）/ 剥前缀后基题为空 → 原样
// 返回不加前缀。★ 自检轮改判：守卫只认真空题、不看 titleSource（占位截断题与主动消息题都是
// 非空标题 + titleSource 空，若放过则副本与源永久同名，违背 M10）；占位题同加前缀，副本
// titleSource 照旧随源为空，TitleGen 链照常可改名。快照语义无谱系（M4 来源不落库）：链式与
// 兄弟式编号一致。可接受边界（无库内序号源，不加库列）：用户改名致序号重复；跨页并发复制
// 读同一份快照可撞号（同页连点被 copying 在途位拦）。词形边界：前缀只剥一层；半角括号不识别。
export function composeCopyTitle(sourceTitle: string, existingTitles: string[]): string {
  if (sourceTitle.trim() === '') {
    return sourceTitle;
  }
  let base: string = sourceTitle;
  const selfMark: RegExpMatchArray | null = sourceTitle.match(COPY_TITLE_MARK_RE);
  if (selfMark !== null) {
    base = sourceTitle.substring(selfMark[0].length);
  }
  if (base === '') {
    return sourceTitle;
  }
  let maxSeq: number = 0;
  for (const title of existingTitles) {
    const mark: RegExpMatchArray | null = title.match(COPY_TITLE_MARK_RE);
    const candidate: string = mark === null ? title : title.substring(mark[0].length);
    if (candidate !== base) {
      continue;
    }
    if (mark !== null) {
      const seq: number = parseInt(mark[1], 10);
      if (seq > maxSeq) {
        maxSeq = seq;
      }
    }
  }
  return '（副本' + (maxSeq + 1).toString() + '）' + base;
}

// ── DB 命令层（编排口；句柄经 sharedRdbStore——生产唯一库）──

// 源会话配置快照（M10：复制当前有效配置与显示标题；favorite 不在此列——取新会话默认值）
export interface CopySourceConfig {
  title: string;
  titleSource: string;
  providerId: string;
  assistantId: string;
  promptId: string;
  modelProviderId: string;
  modelId: string;
  webSearchOverride: string;
  updatedAt: number;
}

// 源快照（同一读时点取全——M2；titles = 全表标题列同事务读，副本标题族计数用）
interface CopySourceSnapshot {
  config: CopySourceConfig;
  branchHead: string | null;
  chainRows: CopyPrefixRow[]; // 根 → head 升序（含 head）
  runs: CopyRunRow[];
  facts: CopyFactRow[];
  bindings: CopyBindingRow[];
  attachmentRows: MessageAttachmentRow[];
  attachmentRefs: CopyAttachmentRefRow[];
  titles: string[];
}

export interface CopyPrefixInput {
  conversationId: string;
  branchId: string;
  boundaryNodeId: string;
  now: number;
}

export interface CopiedConversation {
  conversationId: string;
  branchId: string;
  nodeCount: number;
  runCount: number;
  factCount: number;
  bindingCount: number;
  attachmentCount: number;
  droppedRunCount: number;
}

// 复制前缀为独立新会话（S1/S2 五段一体；失败即抛错 + 已备文件清理，源零改动）：
// ①路由 ②同一读时点快照 ③规划（纯函数） ④附件资源文件准备（M5①）
// ⑤源冻结复核（M2） ⑥单事务发布（M5②③） ⑦列表刷新由调用方（UI 层）负责
export async function copyConversationPrefix(input: CopyPrefixInput):
  Promise<CopiedConversation> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  // ① 格式态路由（M9；单点口判定，禁直查 migrateState 列——T-1 口径；判据 M4 单源：
  // **非 graph 即墓碑**，文案单源 = ChatBranchPolicy）
  const state: string = await queryConversationMigrateState(input.conversationId);
  if (state !== CONV_STATE_GRAPH) {
    throw new Error(TOMBSTONE_TOAST_TEXT);
  }
  const activeBranch: string = await queryConversationActiveBranch(input.conversationId);
  if (activeBranch === '' || activeBranch !== input.branchId) {
    throw new Error('会话的当前分支已变化，请重新选择复制位置');
  }
  // ② 同一读时点快照
  const snap: CopySourceSnapshot = await readCopySnapshot(db, input);
  // ③ 规划（铸造器绑定：id 走 ChatDb 全局铸造、seq 走 MessageSeqDb 分配器——D1 单一口）
  const newConversationId: string = nextMessageId('conv');
  const newBranchId: string = nextMessageId('br');
  const plan: ConversationCopyPlan | null = planConversationCopy({
    newConversationId: newConversationId,
    newBranchId: newBranchId,
    boundaryNodeId: input.boundaryNodeId,
    chainRows: snap.chainRows,
    runs: snap.runs,
    facts: snap.facts,
    bindings: snap.bindings,
    attachmentRows: snap.attachmentRows,
    attachmentRefs: snap.attachmentRefs,
    mintId: (prefix: string): string => nextMessageId(prefix),
    mintSeq: (): number => nextRowSeq(newConversationId)
  });
  if (plan === null) {
    throw new Error('所选消息不在当前分支路径上，请重新选择');
  }
  // ④ 附件资源文件准备（M5①：先文件后元数据；准备期新文件落既有附件目录，mtime 晚于本进程
  // 启动时刻 ⇒ 天然受在途保护闸保护，不被启动收敛/存储页清理判孤儿）
  const preparedPaths: string[] = [];
  try {
    for (const att of plan.attachments) {
      try {
        const rel: string = copyAttachmentResource(att.sourceLocalPath, att.newFileName);
        preparedPaths.push(rel);
      } catch (e) {
        // M12⑤/Z8：源附件缺失或损坏 → 阻止本次完整 fork 并指出缺件（不悄悄交付残缺副本）
        throw new Error('附件「' + att.name + '」复制失败：' + (e as Error).message);
      }
    }
    // ⑤ 单事务发布（标题 = composeCopyTitle 产出，M10）。源冻结复核已移入 publishCopy 链节
    // 首句（M2 拒绝窗覆盖排队期）
    const copyTitle: string = composeCopyTitle(snap.config.title, snap.titles);
    await publishCopy(db, plan, snap, newConversationId, newBranchId, input, copyTitle);
  } catch (e) {
    // M12：失败不发布半会话、不损源——已备新文件清理（best-effort；清理失败者由启动收敛
    // 按孤儿文件回收，见 AttachmentDb 头注释「行在文件不在/文件无行」两分叉）
    removeAttachmentFiles(preparedPaths);
    throw e as Error;
  }
  hilog.info(DOMAIN, TAG, '前缀复制完成：源 %{public}s → 新会话 %{public}s（节点 %{public}d · run %{public}d · 附件 %{public}d）',
    input.conversationId, newConversationId, plan.nodes.length, plan.runs.length,
    plan.attachments.length);
  return {
    conversationId: newConversationId,
    branchId: newBranchId,
    nodeCount: plan.nodes.length,
    runCount: plan.runs.length,
    factCount: plan.facts.length,
    bindingCount: plan.bindings.length,
    attachmentCount: plan.attachments.length,
    droppedRunCount: plan.droppedRunIds.length
  };
}

// 同一读时点快照：DEFERRED 事务对象查询，全部读走 tx.querySql（连接池下 store 直查可能落在
// 事务外）；全读按 conversationId 单键（有索引），前缀裁剪在内存（性能不许愿红线）
async function readCopySnapshot(db: relationalStore.RdbStore,
  input: CopyPrefixInput): Promise<CopySourceSnapshot> {
  const tx: relationalStore.Transaction =
    await db.createTransaction({ transactionType: relationalStore.TransactionType.DEFERRED });
  try {
    const cfgResult: relationalStore.ResultSet = await tx.querySql(
      'SELECT title, titleSource, providerId, assistantId, promptId, modelProviderId, modelId, ' +
      'webSearchOverride, updatedAt FROM conversations WHERE id = ?', [input.conversationId]);
    let config: CopySourceConfig | null = null;
    try {
      if (cfgResult.goToNextRow()) {
        config = {
          title: cfgResult.getString(cfgResult.getColumnIndex('title')),
          titleSource: cfgResult.getString(cfgResult.getColumnIndex('titleSource')),
          providerId: cfgResult.getString(cfgResult.getColumnIndex('providerId')),
          assistantId: cfgResult.getString(cfgResult.getColumnIndex('assistantId')),
          promptId: cfgResult.getString(cfgResult.getColumnIndex('promptId')),
          modelProviderId: cfgResult.getString(cfgResult.getColumnIndex('modelProviderId')),
          modelId: cfgResult.getString(cfgResult.getColumnIndex('modelId')),
          webSearchOverride: cfgResult.getString(cfgResult.getColumnIndex('webSearchOverride')),
          updatedAt: cfgResult.getLong(cfgResult.getColumnIndex('updatedAt'))
        };
      }
    } finally {
      cfgResult.close();
    }
    if (config === null) {
      throw new Error('源会话不存在，无法复制');
    }
    // 源分支行（head 冻结基准 + 归属校验）
    const brResult: relationalStore.ResultSet = await tx.querySql(
      'SELECT id, conversationId, headMessageId FROM branches WHERE id = ?', [input.branchId]);
    let branchHead: string | null = null;
    let branchOwner: string = '';
    try {
      if (brResult.goToNextRow()) {
        const headIdx: number = brResult.getColumnIndex('headMessageId');
        branchHead = brResult.isColumnNull(headIdx) ? null : brResult.getString(headIdx);
        branchOwner = brResult.getString(brResult.getColumnIndex('conversationId'));
      }
    } finally {
      brResult.close();
    }
    if (branchOwner !== input.conversationId) {
      throw new Error('源分支不属于该会话，无法复制');
    }
    // 会话全部节点一次读全（前缀由祖先链裁剪）。quote_text（v61 引用全文快照）同 SELECT 带回
    // ——fork 副本保真带引用，漏 = 引用条消失 + 重试轮模型看不到引用（静默语义损失）。
    // server_tools（v64 服务端工具快照）同 SELECT 零额外往返——fork 副本保真带官方步骤
    const nodeResult: relationalStore.ResultSet = await tx.querySql(
      'SELECT id, role, content, reasoning, status, createdAt, parentMessageId, runId, ' +
      'ownerAssistantId, stepIndex, origin, seq, quote_text, server_tools FROM messages ' +
      'WHERE conversationId = ?',
      [input.conversationId]);
    const allRows: CopyPrefixRow[] = [];
    const nodeRefs: Map<string, GraphNodeRef> = new Map<string, GraphNodeRef>();
    try {
      while (nodeResult.goToNextRow()) {
        const parentIdx: number = nodeResult.getColumnIndex('parentMessageId');
        const stepIdx: number = nodeResult.getColumnIndex('stepIndex');
        const seqIdx: number = nodeResult.getColumnIndex('seq');
        const quoteIdx: number = nodeResult.getColumnIndex('quote_text');
        const stIdx: number = nodeResult.getColumnIndex('server_tools');
        const id: string = nodeResult.getString(nodeResult.getColumnIndex('id'));
        const parent: string | null = nodeResult.isColumnNull(parentIdx) ? null
          : nodeResult.getString(parentIdx);
        allRows.push({
          id: id,
          role: nodeResult.getString(nodeResult.getColumnIndex('role')),
          content: nodeResult.getString(nodeResult.getColumnIndex('content')),
          reasoning: nodeResult.getString(nodeResult.getColumnIndex('reasoning')),
          status: nodeResult.getString(nodeResult.getColumnIndex('status')),
          createdAt: nodeResult.getLong(nodeResult.getColumnIndex('createdAt')),
          parentMessageId: parent,
          runId: nodeResult.getString(nodeResult.getColumnIndex('runId')),
          ownerAssistantId: nodeResult.getString(nodeResult.getColumnIndex('ownerAssistantId')),
          stepIndex: nodeResult.isColumnNull(stepIdx) ? null : nodeResult.getLong(stepIdx),
          origin: nodeResult.getString(nodeResult.getColumnIndex('origin')),
          seq: nodeResult.isColumnNull(seqIdx) ? -1 : nodeResult.getLong(seqIdx),
          quoteText: nodeResult.isColumnNull(quoteIdx) ? ''
            : nodeResult.getString(quoteIdx),
          serverTools: nodeResult.isColumnNull(stIdx) ? ''
            : nodeResult.getString(stIdx)
        });
        nodeRefs.set(id, { id: id, conversationId: input.conversationId,
          parentMessageId: parent });
      }
    } finally {
      nodeResult.close();
    }
    const chain: CopyPrefixRow[] = chainToBoundary(allRows, nodeRefs, branchHead);
    // 源 run 行（整会话一次读；只复制前缀引用到的那部分）
    const runResult: relationalStore.ResultSet = await tx.querySql(
      'SELECT id, branchId, attemptEpoch, inputAnchorMessageId, revision, status, ' +
      'diagnosticMessageId, createdAt, updatedAt FROM generation_runs WHERE conversationId = ?',
      [input.conversationId]);
    const runs: CopyRunRow[] = [];
    try {
      while (runResult.goToNextRow()) {
        runs.push({
          id: runResult.getString(runResult.getColumnIndex('id')),
          branchId: runResult.getString(runResult.getColumnIndex('branchId')),
          attemptEpoch: runResult.getLong(runResult.getColumnIndex('attemptEpoch')),
          inputAnchorMessageId: runResult.getString(
            runResult.getColumnIndex('inputAnchorMessageId')),
          revision: runResult.getLong(runResult.getColumnIndex('revision')),
          status: runResult.getString(runResult.getColumnIndex('status')),
          diagnosticMessageId: runResult.getString(
            runResult.getColumnIndex('diagnosticMessageId')),
          createdAt: runResult.getLong(runResult.getColumnIndex('createdAt')),
          updatedAt: runResult.getLong(runResult.getColumnIndex('updatedAt'))
        });
      }
    } finally {
      runResult.close();
    }
    // 工具事实（按 run 反连接——一查询取全，无动态 IN 绑定）
    const factResult: relationalStore.ResultSet = await tx.querySql(
      'SELECT id, runId, attemptId, name, state, payload, result, createdAt, finishedAt ' +
      'FROM tool_facts ' +
      'WHERE runId IN (SELECT id FROM generation_runs WHERE conversationId = ?)',
      [input.conversationId]);
    const facts: CopyFactRow[] = [];
    try {
      while (factResult.goToNextRow()) {
        facts.push({
          id: factResult.getString(factResult.getColumnIndex('id')),
          runId: factResult.getString(factResult.getColumnIndex('runId')),
          attemptId: factResult.getString(factResult.getColumnIndex('attemptId')),
          name: factResult.getString(factResult.getColumnIndex('name')),
          state: factResult.getString(factResult.getColumnIndex('state')),
          payload: factResult.getString(factResult.getColumnIndex('payload')),
          result: factResult.getString(factResult.getColumnIndex('result')),
          createdAt: factResult.getLong(factResult.getColumnIndex('createdAt')),
          finishedAt: factResult.getLong(factResult.getColumnIndex('finishedAt'))
        });
      }
    } finally {
      factResult.close();
    }
    // 摘要绑定（整会话一次读；只复制摘要节点在前缀内者）
    const bindResult: relationalStore.ResultSet = await tx.querySql(
      'SELECT id, summaryMessageId, coversFromSeq, coversToSeq, dependsOnBindingId, createdAt ' +
      'FROM summary_bindings WHERE conversationId = ?', [input.conversationId]);
    const bindings: CopyBindingRow[] = [];
    try {
      while (bindResult.goToNextRow()) {
        const fromIdx: number = bindResult.getColumnIndex('coversFromSeq');
        const toIdx: number = bindResult.getColumnIndex('coversToSeq');
        bindings.push({
          id: bindResult.getString(bindResult.getColumnIndex('id')),
          summaryMessageId: bindResult.getString(
            bindResult.getColumnIndex('summaryMessageId')),
          coversFromSeq: bindResult.isColumnNull(fromIdx) ? null
            : bindResult.getLong(fromIdx),
          coversToSeq: bindResult.isColumnNull(toIdx) ? null : bindResult.getLong(toIdx),
          dependsOnBindingId: bindResult.getString(
            bindResult.getColumnIndex('dependsOnBindingId')),
          createdAt: bindResult.getLong(bindResult.getColumnIndex('createdAt'))
        });
      }
    } finally {
      bindResult.close();
    }
    // 附件资源行与引用（各一次读全，按前缀节点集在内存过滤——同理无动态 IN 绑定）
    const attResult: relationalStore.ResultSet = await tx.querySql(
      'SELECT id, messageId, conversationId, kind, name, mime, size, localPath, parsedText, ' +
      'createdAt FROM message_attachments WHERE conversationId = ?', [input.conversationId]);
    const attachmentRows: MessageAttachmentRow[] = [];
    try {
      while (attResult.goToNextRow()) {
        attachmentRows.push({
          id: attResult.getString(attResult.getColumnIndex('id')),
          messageId: attResult.getString(attResult.getColumnIndex('messageId')),
          conversationId: attResult.getString(attResult.getColumnIndex('conversationId')),
          kind: attResult.getString(attResult.getColumnIndex('kind')),
          name: attResult.getString(attResult.getColumnIndex('name')),
          mime: attResult.getString(attResult.getColumnIndex('mime')),
          size: attResult.getLong(attResult.getColumnIndex('size')),
          localPath: attResult.getString(attResult.getColumnIndex('localPath')),
          parsedText: attResult.getString(attResult.getColumnIndex('parsedText')),
          createdAt: attResult.getLong(attResult.getColumnIndex('createdAt'))
        });
      }
    } finally {
      attResult.close();
    }
    const refResult: relationalStore.ResultSet = await tx.querySql(
      'SELECT attachmentId, nodeId FROM attachment_refs WHERE conversationId = ?',
      [input.conversationId]);
    const attachmentRefs: CopyAttachmentRefRow[] = [];
    try {
      while (refResult.goToNextRow()) {
        attachmentRefs.push({
          attachmentId: refResult.getString(refResult.getColumnIndex('attachmentId')),
          nodeId: refResult.getString(refResult.getColumnIndex('nodeId'))
        });
      }
    } finally {
      refResult.close();
    }
    // 全表标题列（副本标题族计数——单列单查询，数百行量级内存匹配，性能红线口径）
    const titleResult: relationalStore.ResultSet = await tx.querySql(
      'SELECT title FROM conversations', []);
    const titles: string[] = [];
    try {
      while (titleResult.goToNextRow()) {
        titles.push(titleResult.getString(titleResult.getColumnIndex('title')));
      }
    } finally {
      titleResult.close();
    }
    await tx.commit();
    return {
      config: config,
      branchHead: branchHead,
      chainRows: chain,
      runs: runs,
      facts: facts,
      bindings: bindings,
      attachmentRows: attachmentRows,
      attachmentRefs: attachmentRefs,
      titles: titles
    };
  } catch (e) {
    await tx.rollback();
    throw e as Error;
  }
}

// 祖先链重建（复用 MessageBranchDb.traceAncestorChain 的语义：沿 parent 链上溯含自身；
// 坏链有界截断）。返回「根 → head」升序——上游读全后在内存裁剪，避免逐节点点查
function chainToBoundary(allRows: CopyPrefixRow[], nodeRefs: Map<string, GraphNodeRef>,
  headNodeId: string | null): CopyPrefixRow[] {
  if (headNodeId === null || headNodeId === '') {
    return []; // 空分支（head 可空合法）——无前缀可复制，由调用方按边界不在链上拒绝
  }
  const byId: Map<string, CopyPrefixRow> = new Map<string, CopyPrefixRow>();
  for (const row of allRows) {
    byId.set(row.id, row);
  }
  const chain: string[] = traceAncestorChain(headNodeId, nodeRefs,
    Math.min(nodeRefs.size + 1, CHAIN_MAX_STEPS));
  const out: CopyPrefixRow[] = [];
  for (const id of chain) {
    const row: CopyPrefixRow | undefined = byId.get(id);
    if (row !== undefined) {
      out.push(row);
    }
  }
  out.reverse(); // 根 → head
  return out;
}

// 源冻结复核（M2：快照与发布时点间源变化 → 拒绝；只认分支 head 与会话 updatedAt 两枚基准。
// 覆盖面声明：updatedAt 只由消息行写入与建行触碰（改名 / 配置覆盖均不动它），故标题改名与
// 配置变更不被本复核拒绝——窗口内改名时副本取改名前快照，账目可接受边界）
async function assertSourceFrozen(db: relationalStore.RdbStore, input: CopyPrefixInput,
  snap: CopySourceSnapshot): Promise<void> {
  const brResult: relationalStore.ResultSet = await db.querySql(
    'SELECT headMessageId FROM branches WHERE id = ?', [input.branchId]);
  let head: string | null = null;
  try {
    if (brResult.goToNextRow()) {
      const idx: number = brResult.getColumnIndex('headMessageId');
      head = brResult.isColumnNull(idx) ? null : brResult.getString(idx);
    }
  } finally {
    brResult.close();
  }
  const cfgResult: relationalStore.ResultSet = await db.querySql(
    'SELECT updatedAt FROM conversations WHERE id = ?', [input.conversationId]);
  let updatedAt: number = -1;
  try {
    if (cfgResult.goToNextRow()) {
      updatedAt = cfgResult.getLong(cfgResult.getColumnIndex('updatedAt'));
    }
  } finally {
    cfgResult.close();
  }
  if (head !== snap.branchHead || updatedAt !== snap.config.updatedAt) {
    throw new Error('会话在复制过程中有了新变化，请重新复制');
  }
}

// 单事务发布（M5②③：全部元数据行与 refs 同一提交单元；提交成功即副本成立——列表刷新失败
// 不回滚、不重复制）。copyTitle = composeCopyTitle 产出（源标题为空时 = 源标题原样，见该函数守卫）
async function publishCopy(db: relationalStore.RdbStore, plan: ConversationCopyPlan,
  snap: CopySourceSnapshot, newConversationId: string, newBranchId: string,
  input: CopyPrefixInput, copyTitle: string): Promise<void> {
  // ★ 源冻结复核在链节首句（而非调用方）：入链后「快照→发布」隔了排队时长，复核留链外会把
  // M2 拒绝窗从微秒级放宽到排队期；入链后排队期源变化也能在开事务前被拒。复核为两枚点查纯读
  await runWriteQueued('publishCopy', async (): Promise<void> => {
    await assertSourceFrozen(db, input, snap);
    const tx: relationalStore.Transaction =
      await db.createTransaction({ transactionType: relationalStore.TransactionType.IMMEDIATE });
    try {
      // 会话行（M10：有效配置快照随行、标题取 composeCopyTitle 前缀版；id/时间/默认分支为新值；
      // favorite 取新会话默认值、suggestions 不复制；migrateState 与 activeBranchId 显式
      // 落 graph 态——T-5：副本是图会话，createConversation 族不写这两列，须在建行处显式落）
      await tx.insert('conversations', {
        'id': newConversationId,
        'title': copyTitle,
        'providerId': snap.config.providerId,
        'createdAt': input.now,
        'updatedAt': input.now,
        'promptId': snap.config.promptId,
        'assistantId': snap.config.assistantId,
        'titleSource': snap.config.titleSource,
        'favorite': 0,
        'modelProviderId': snap.config.modelProviderId,
        'modelId': snap.config.modelId,
        'webSearchOverride': snap.config.webSearchOverride,
        'suggestions': '',
        'activeBranchId': newBranchId,
        'migrateState': CONV_STATE_GRAPH
      });
      // 分支行（parentBranchId 归 null = 范围外引用不带入——副本自有分支树根；
      // head = 前缀末节点（所选边界）的重映射 id）
      let headMessageId: string | null = null;
      if (plan.nodes.length > 0) {
        headMessageId = plan.nodes[plan.nodes.length - 1].id;
      }
      await tx.insert('branches', {
        'id': newBranchId,
        'conversationId': newConversationId,
        'parentBranchId': null,
        'headMessageId': headMessageId,
        'name': '',
        'createdAt': input.now
      });
      for (const node of plan.nodes) {
        await tx.insert('messages', {
          'id': node.id,
          'conversationId': node.conversationId,
          'role': node.role,
          'content': node.content,
          'reasoning': node.reasoning,
          'status': node.status,
          'createdAt': node.createdAt,
          'variants': '',
          'variant_active': 0,
          'parentMessageId': node.parentMessageId,
          'runId': node.runId,
          'ownerAssistantId': node.ownerAssistantId,
          'stepIndex': node.stepIndex,
          'origin': node.origin,
          'seq': node.seq,
          // v61 引用全文快照（fork 保真）：'' = 不写键（列落 NULL = 无引用）。
          // v64 服务端工具快照（fork 保真）：'' = 不写键（列落 NULL = 无官方步骤）
          'quote_text': node.quoteText !== '' ? node.quoteText : null,
          'server_tools': node.serverTools !== '' ? node.serverTools : null
        });
      }
      for (const run of plan.runs) {
        await tx.insert('generation_runs', {
          'id': run.id,
          'conversationId': run.conversationId,
          'branchId': run.branchId,
          'attemptEpoch': run.attemptEpoch,
          'inputAnchorMessageId': run.inputAnchorMessageId,
          'revision': run.revision,
          'status': run.status,
          'checkpoint': run.checkpoint,
          'diagnosticMessageId': run.diagnosticMessageId,
          'createdAt': run.createdAt,
          'updatedAt': run.updatedAt
        });
      }
      for (const fact of plan.facts) {
        await tx.insert('tool_facts', {
          'id': fact.id,
          'runId': fact.runId,
          'attemptId': fact.attemptId,
          'name': fact.name,
          'state': fact.state,
          'payload': fact.payload,
          'result': fact.result,
          'createdAt': fact.createdAt,
          'finishedAt': fact.finishedAt
        });
      }
      for (const binding of plan.bindings) {
        await tx.insert('summary_bindings', {
          'id': binding.id,
          'conversationId': binding.conversationId,
          'summaryMessageId': binding.summaryMessageId,
          'coversFromSeq': binding.coversFromSeq,
          'coversToSeq': binding.coversToSeq,
          'dependsOnBindingId': binding.dependsOnBindingId,
          'createdAt': binding.createdAt
        });
      }
      // 附件行（M7 零计费/零执行：只搬元数据与文件，不产生账本事件）与 refs——同一事务内
      // 直写（不经 AttachmentDb.insertAttachments：彼口收 RdbStore，事务对象与之不同型，
      // 且 M5② 要求元数据与 refs 与其余行同一提交单元）
      for (const att of plan.attachments) {
        await tx.insert('message_attachments', {
          'id': att.newAttachmentId,
          'messageId': att.messageId,
          'conversationId': newConversationId,
          'kind': att.kind,
          'name': att.name,
          'mime': att.mime,
          'size': att.size,
          'localPath': ATTACH_DIR_NAME + '/' + att.newFileName,
          'parsedText': att.parsedText,
          'createdAt': att.createdAt
        });
      }
      for (const att of plan.attachments) {
        for (const nodeId of att.nodeIds) {
          await tx.insert('attachment_refs', {
            'id': nextMessageId('ref'),
            'conversationId': newConversationId,
            'attachmentId': att.newAttachmentId,
            'nodeId': nodeId,
            'createdAt': input.now
          });
        }
      }
      await tx.commit();
    } catch (e) {
      await tx.rollback();
      throw e as Error;
    }
  });
}
