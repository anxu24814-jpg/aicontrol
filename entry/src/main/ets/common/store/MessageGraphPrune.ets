// 图删除与清理存活判定域（自 MessageBranchDb.ets 域级最小拆分——该件剔头贴 1200 硬线，
// 按宪法「对越线邻域件的实质改动先拆改动所属域」落独立件；方法体自主件原样搬迁零行为变化）。
// 域定义一句话：**图删除与清理的存活判定纯函数域**——删子树存活集（computeSurvivingNodes）、
// 分支谱系删除 cut 集（lineageBranchIds / computeLineageCutIds）、附件资源存活裁定
// （computeAttachmentSurvivors），三者同属「删除/清理决策的判据核心」（删除谱系、删除
// 子树、清理附件共享「谁还活着」这一判据面）。
// · 为何不能并入既有件（宪法「反碎片下限」三问）：①职责一句话见上；②无既有同域可并
//   ——母件 MessageBranchDb 是分支图命令层单源且本笔拆分动因（剔头贴硬线，宪法禁再塞）；
//   ChatDbSweep 是启动清扫域（消费判定不承载判定）；GraphTransfer 是消费方（谱系删除
//   编排，判据与编排分属两件防两份漂移）；③实逻辑非转接壳（三个完整判定算法）。
// · 依赖方向（零环红线，坑50）：本件 → MessageBranchDb 单向（GraphNodeRef 类型 /
//   traceAncestorChain / GRAPH_LEVEL_ENABLED——母件不 import 本件）；顶层零外部绑定
//   求值（纯函数段——断言脚本剥 import 后可拼接直跑，见 scripts/graph-fixture.mjs 与
//   assert-attach-domain 182 组）。
// · 调用点：GraphTransfer.ets（谱系删除 + 附件判定）、ChatBranchSheet.ets（面板摘要
//   lineageBranchIds）；AttachmentDb.ets / ChatGraphCommandSource.ets 仅注释提及。断言
//   消费面 = graph-fixture.mjs、assert-attach-domain 182 组、assert-store-consistency
//   262/277 组（正文形态钉锚 GraphTransfer 正文，不受 import 迁移影响）。
import { GraphNodeRef, traceAncestorChain, GRAPH_LEVEL_ENABLED } from './MessageBranchDb';

// ── 删除子树存活集（自 MessageBranchDb 原样搬迁，注释随行）──

// 删除子树后的存活节点集（纯函数——J7 可达性删除的核心判定）：cut 集合中的节点与其全部
// 后代（祖先链经过任一 cut 节点的节点）不存活，其余存活。O(N·depth)——单会话节点数百
// 量级、删除低频，量级可接受（性能不许愿红线：实测卡顿前不优化）。
// 契约：cutIds 中不存在的 id 无害忽略；返回集恒不与 cutIds 相交。
export function computeSurvivingNodes(allNodes: Map<string, GraphNodeRef>,
  cutIds: Set<string>): Set<string> {
  const surviving: Set<string> = new Set<string>();
  const maxDepth: number = allNodes.size;
  for (const id of allNodes.keys()) {
    if (cutIds.has(id)) {
      continue;
    }
    const chain: string[] = traceAncestorChain(id, allNodes, maxDepth);
    let cut: boolean = false;
    for (const ancestor of chain) {
      if (cutIds.has(ancestor)) {
        cut = true;
        break;
      }
    }
    if (!cut) {
      surviving.add(id);
    }
  }
  return surviving;
}

// ── 谱系删除判定（LB-2/D12 登记项的语义改判，见 GraphTransfer
//    deleteBranchLineage 注释）──

// 分支谱系轻行（谱系子树收集输入面；库行与面板摘要两路同形适配）
export interface BranchLineageRow {
  id: string;
  parentBranchId: string | null;
}

// 谱系子树收集（纯函数——删除语义「删一条分支 = 连同它之后衍生的全部分支一起删」的判据
// 核心）：返回 rootId 及其全部谱系后代（沿 parentBranchId 向下闭包）。**防环有界**——每轮
// 只收未见者、轮数上限 = 行数，脏数据带环也必然终止；rootId 不在行集内时返回 {rootId}
// （调用方守卫兜底，收集器不替调用方抛错——它同时是面板预演的公开输入面）。
export function lineageBranchIds(rows: BranchLineageRow[], rootId: string): Set<string> {
  const collected: Set<string> = new Set<string>([rootId]);
  let changed: boolean = true;
  let rounds: number = 0;
  while (changed && rounds <= rows.length) {
    changed = false;
    rounds++;
    for (const row of rows) {
      if (row.parentBranchId !== null && collected.has(row.parentBranchId) &&
        !collected.has(row.id)) {
        collected.add(row.id);
        changed = true;
      }
    }
  }
  return collected;
}

// 分支 head 轻行（cut 集计算输入面）
export interface BranchHeadRow {
  branchId: string;
  headMessageId: string | null;
}

// 谱系删除的 cut 集（纯函数——「本分支独占路径段」判据，D12 老实现两处越界的整代替换）：
// cut = 「被删集内分支可达」且「任何幸存分支都不可达」的节点集。三条性质：
// ①共享前缀恒保留——幸存分支可达即不入 cut；②被删分支的独占段全额入选；③不越界到父属
// 内容——老实现拿共享 fork 点或父分支 head 当 cut 锚（连删父分支内容，登记为数据丢失级），
// 新判据的 cut 成员恒满足「只被删集可达」，父分支路径节点不可能入选。
// 交 computeSurvivingNodes 求后代闭包 = 最终被删集：被删分支的编辑弃稿与诊断节点不在任何
// head 链上（可达性判据抓不到），但父链经过 cut 成员，随闭包一并删除。
// 空 head 分支可达集为空（空分支只删行不删节点）。
export function computeLineageCutIds(rows: BranchHeadRow[], deleteSet: Set<string>,
  allNodes: Map<string, GraphNodeRef>): Set<string> {
  const maxDepth: number = allNodes.size;
  const survivorReachable: Set<string> = new Set<string>();
  for (const row of rows) {
    if (deleteSet.has(row.branchId) || row.headMessageId === null) {
      continue;
    }
    for (const id of traceAncestorChain(row.headMessageId, allNodes, maxDepth)) {
      survivorReachable.add(id);
    }
  }
  const cut: Set<string> = new Set<string>();
  for (const row of rows) {
    if (!deleteSet.has(row.branchId) || row.headMessageId === null) {
      continue;
    }
    for (const id of traceAncestorChain(row.headMessageId, allNodes, maxDepth)) {
      if (!survivorReachable.has(id)) {
        cut.add(id);
      }
    }
  }
  return cut;
}

// ── 附件存活集判定（J7 冻结——「清理存活集 = legacy 旧归属可达根 ∪ graph refs 可达根」+
//    图能力判据先行）：返回每条附件资源的存活裁定与理由（统一可调用接口，W8/W18 验证面）。
//    规则（总纲§5 闸二同源：只有图能力在场且资源归类为 graph 时才按 refs 判归属）：
//    · 图能力判据先行——capabilityLevel < GRAPH_LEVEL_ENABLED 或标记不可得（< 0）时，
//      **空串 messageId 资源一律保护不删**（空串不表达归属，J7）；**refs 不认**（refs 归属
//      判定挂图能力条件）；legacy 可达照常判定。
//    · legacy 可达 = messageId ∈ survivingMessageIds（message 行存活）。
//    · graph 可达 = 图能力在场 且 该附件在 refs 中有任一 nodeId ∈ survivingNodeIds。
//    · 存活 = legacy ∪ graph；两者皆不达 = 可清。──

export interface AttachmentSurvivorRow {
  attachmentId: string;
  messageId: string; // message_attachments.messageId 原值（'' = graph 占位）
}
export interface GraphRefRow {
  attachmentId: string;
  nodeId: string;
}
export interface AttachmentSurvivorVerdict {
  attachmentId: string;
  survive: boolean;
  reason: string; // 'legacy-reachable' | 'graph-ref-reachable' | 'protected-blank-owner' | 'unreachable'
}

export function computeAttachmentSurvivors(rows: AttachmentSurvivorRow[],
  refs: GraphRefRow[], capabilityLevel: number,
  survivingMessageIds: Set<string>, survivingNodeIds: Set<string>): AttachmentSurvivorVerdict[] {
  // refs 按附件聚合（一次遍历建索引——判据消费面）
  const refsByAttachment: Map<string, string[]> = new Map<string, string[]>();
  for (const ref of refs) {
    const held: string[] | undefined = refsByAttachment.get(ref.attachmentId);
    if (held === undefined) {
      refsByAttachment.set(ref.attachmentId, [ref.nodeId]);
    } else {
      held.push(ref.nodeId);
    }
  }
  const graphCapable: boolean = capabilityLevel >= GRAPH_LEVEL_ENABLED;
  const out: AttachmentSurvivorVerdict[] = [];
  for (const row of rows) {
    const legacyReachable: boolean = row.messageId !== '' &&
      survivingMessageIds.has(row.messageId);
    if (legacyReachable) {
      out.push({ attachmentId: row.attachmentId, survive: true, reason: 'legacy-reachable' });
      continue;
    }
    const refNodes: string[] | undefined = refsByAttachment.get(row.attachmentId);
    // refs 归属判定挂图能力条件（总纲§5 闸二：无图能力时不按 refs 判归属——
    // 防能力不足的构建依据它读不懂的图态做删除裁决）
    const graphReachable: boolean = graphCapable && refNodes !== undefined && refNodes.some(
      (nodeId: string): boolean => survivingNodeIds.has(nodeId));
    if (graphReachable) {
      out.push({ attachmentId: row.attachmentId, survive: true, reason: 'graph-ref-reachable' });
      continue;
    }
    if (!graphCapable && row.messageId === '') {
      // 无图能力时不得依据空串认定无归属（J7）——保护不删
      out.push({ attachmentId: row.attachmentId, survive: true,
        reason: 'protected-blank-owner' });
      continue;
    }
    out.push({ attachmentId: row.attachmentId, survive: false, reason: 'unreachable' });
  }
  return out;
}
