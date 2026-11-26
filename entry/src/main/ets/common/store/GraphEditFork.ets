// 编辑消息分叉落库域（初建助手编辑，rik 形态统一笔扩提问编辑）。
// 域定义一句话：**历史消息编辑的原子分叉命令**——单事务完成「建新分支行 + 落无 run 编辑版
// 节点（parent = 被编辑消息的父）+ 分支 head 一次指向编辑节点」，三步不可拆（拆开则中途失败
// 留空分支垃圾：fork 成功而节点落库失败 = 分支列表出现无内容行）。
// · 两角色同命令：assistant 编辑版（origin edit_assistant）与 user 编辑版（origin edit_user）
//   仅 role/origin/失败文案/引用快照四处不同（助手行无引用，user 行随编辑复制 quote_text），
//   校验与事务骨架共用 editForkCore。
// · 为什么新开本件（宪法「反碎片下限」三问）：①职责一句话 = 编辑分叉的原子落库命令；
//   ②无既有同域可并——MessageBranchDb 剔头约 1173 行（软区贴线，本笔增量即破 1200 硬线，
//   技术债务清单既有档「预计拆分时机 = 实质增量笔」）、ChatContextSource 剔头约 1188 行
//   同况、GraphTransfer 职责 = 图数据出库/入库/删分支策略（头注释明载，写命令不属其域）；
//   ③实逻辑非转接壳（路径校验 + 图插入校验 + 单事务的完整实现）。
// · 依赖方向（零环红线，坑50）：本件 → MessageBranchDb（queryBranch/loadConversationNodes/
//   traceAncestorChain/validateGraphInsertion/词表）→ MessageSeqDb（nextRowSeq）→ ChatDb
//   （nextMessageId）单向；库句柄由调用方传入（MessageBranchDb 同款姿势）。
// · 事务纪律（J6）：createTransaction 对象事务（IMMEDIATE）+ runWriteQueued 写串行链，
//   前置校验读段留链外（同 forkBranch 口径）。
// · 与 forkBranch 的关系：forkBranch 只建分支行（head 停 fork 点、无节点落库）；本命令是
//   「fork + 首节点落库」的复合形态——fork 点校验语义同源（沿源 head 上溯可达），节点校验
//   走 J10 唯一口 validateGraphInsertion（fork 点即父，路径可达已证，再过一次关系校验兜底）。
//   fork 点为 null = 被编辑消息是根节点（主动消息开场白形态）——编辑版节点挂根，合法
//（validateGraphInsertion 对 parent=null 即通过）。
import { relationalStore } from '@kit.ArkData';
import { nextMessageId, nextRowCreatedAt, sharedRdbStore } from './ChatDb';
import { nextRowSeq } from './MessageSeqDb';
import { runWriteQueued } from './DbWriteQueue';
import { BranchRow, GraphNodeRef, ORIGIN_EDIT_ASSISTANT, ORIGIN_EDIT_USER, queryBranch,
  loadConversationNodes, traceAncestorChain, validateGraphInsertion } from './MessageBranchDb';

export interface EditAssistantForkInput {
  conversationId: string;
  sourceBranchId: string;
  // 被编辑 assistant 节点的父节点 id（null = 被编辑消息挂根——主动消息开场白）
  editAtNodeId: string | null;
  // 编辑后的回复正文（非空由调用方判据保证；命令层再拒一次防静默空行）
  content: string;
  now: number; // 时钟由调用方注入（隔离库夹具确定性；生产传 nextRowCreatedAt() 单调分配器
  // ——ChatDb 契约「接入点 = 全部产品消息写入点」：本命令写 messages 行，与 forkBranch 只写
  // 分支行不同，裸 Date.now() 会绕开撞毫秒让位）
}

// 提问编辑分叉入参：形状同助手编辑——字段名沿用
// editAtNodeId（= 被编辑提问的父节点），语义与校验完全同源
export interface EditUserForkInput {
  conversationId: string;
  sourceBranchId: string;
  editAtNodeId: string | null;
  content: string;
  // 原提问的引用全文快照（DB v61；'' = 无引用）：引用是「被引用内容的已发事实」，编辑只改
  // 问题正文——不随编辑失效，复制到编辑版节点，气泡引用标注与后续请求的引用前缀才不断链
  quoteText: string;
  now: number;
}

export interface EditAssistantForkResult {
  branchId: string;
  nodeId: string;
}

// 编辑分叉骨架（两角色共 95% 逻辑，仅落库 role/origin
// 与失败文案不同——P2-4 重复两次必须提取）。校验三条——源分支在场且属同会话 / fork 点在源
// 分支路径上（null 豁免）/ 编辑节点过图插入校验；事务内两写：messages 编辑节点 + branches
// 新分支行（headMessageId 直接 = 编辑节点，无中间态无 CAS 需求——分支行为本命令新建，无
// 并发写者可竞争的既有行）。任一失败整体回滚并上抛（P0-1 不静默，调用方呈报）
async function editForkCore(db: relationalStore.RdbStore, input: EditAssistantForkInput,
  role: string, origin: string, failWord: string,
  quoteText: string): Promise<EditAssistantForkResult> {
  const source: BranchRow | null = await queryBranch(db, input.sourceBranchId);
  if (source === null) {
    throw new Error(failWord + '：源分支不存在');
  }
  if (source.conversationId !== input.conversationId) {
    throw new Error(failWord + '：分支归属会话与目标会话不一致');
  }
  if (input.content === '') {
    throw new Error(failWord + '：内容不能为空');
  }
  // J10 唯一校验口：候选节点（同会话 / 父在既有集 / 无环）——校验读段全部留链外
  //（同 forkBranch 口径：校验后窗口内父链不变——head 只前进、图节点无中段
  // 删除原语，事务内不复核）
  const allNodes: Map<string, GraphNodeRef> =
    await loadConversationNodes(db, input.conversationId);
  if (input.editAtNodeId !== null) {
    const chain: string[] = source.headMessageId !== null
      ? traceAncestorChain(source.headMessageId, allNodes, allNodes.size)
      : [];
    if (!chain.includes(input.editAtNodeId)) {
      throw new Error(failWord + '：原消息位置已不在当前分支路径上，请刷新后重试');
    }
  }
  const nodeId: string = nextMessageId('msg');
  const reject: string | null = validateGraphInsertion({
    id: nodeId,
    conversationId: input.conversationId,
    parentMessageId: input.editAtNodeId
  }, allNodes);
  if (reject !== null) {
    throw new Error(failWord + '：' + reject);
  }
  return runWriteQueued('editFork', async (): Promise<EditAssistantForkResult> => {
    const tx: relationalStore.Transaction =
      await db.createTransaction({ transactionType: relationalStore.TransactionType.IMMEDIATE });
    try {
      const nodeBucket: relationalStore.ValuesBucket = {
        'id': nodeId,
        'conversationId': input.conversationId,
        'role': role,
        'content': input.content,
        'reasoning': '',
        'status': 'done',
        'createdAt': input.now,
        'variants': '',
        'variant_active': 0,
        'parentMessageId': input.editAtNodeId,
        'runId': '',
        'ownerAssistantId': '',
        'stepIndex': null,
        // seq = 图会话入链单调序号（事务内铸造 = IMMEDIATE 单写串行化保证单调，同 prepareRun）
        'seq': nextRowSeq(input.conversationId),
        'origin': origin
      };
      // v61 引用全文快照条件写键（同 prepareRun 口径）：'' 不写键 = 列落 NULL = 无引用；
      // 助手编辑与无引用提问均传 ''，行为逐字零变化
      if (quoteText !== '') {
        nodeBucket['quote_text'] = quoteText;
      }
      await tx.insert('messages', nodeBucket);
      const branchId: string = nextMessageId('br');
      const branchBucket: relationalStore.ValuesBucket = {
        'id': branchId,
        'conversationId': input.conversationId,
        'parentBranchId': input.sourceBranchId,
        'headMessageId': nodeId,
        'name': '',
        'createdAt': input.now
      };
      await tx.insert('branches', branchBucket);
      await tx.commit();
      return { branchId: branchId, nodeId: nodeId };
    } catch (e) {
      await tx.rollback();
      throw e as Error;
    }
  });
}

// 编辑助手分叉落库（命令入口）：骨架 + 助手角色
export async function editAssistantFork(db: relationalStore.RdbStore,
  input: EditAssistantForkInput): Promise<EditAssistantForkResult> {
  return editForkCore(db, input, 'assistant', ORIGIN_EDIT_ASSISTANT, '编辑失败', '');
}

// 编辑提问分叉落库（命令入口）：骨架 + user 角色——编辑版
// 提问节点挂被编辑提问的父，成为其兄弟（提问变体）；不建 run、不触发生成
export async function editUserFork(db: relationalStore.RdbStore,
  input: EditUserForkInput): Promise<EditAssistantForkResult> {
  // ArkTS 禁结构化类型（arkts-no-structural-typing）：形参形状虽同，须显式逐字段转成
  // 骨架入参类型
  const core: EditAssistantForkInput = {
    conversationId: input.conversationId,
    sourceBranchId: input.sourceBranchId,
    editAtNodeId: input.editAtNodeId,
    content: input.content,
    now: input.now
  };
  return editForkCore(db, core, 'user', ORIGIN_EDIT_USER, '编辑提问失败', input.quoteText);
}

// 生产入口（自取句柄，同 GraphTransfer.deleteBranchLineageProd 姿势——组件编排层不持库句柄；
// 句柄版 editAssistantFork 保留为隔离库证据面入口）
export async function editAssistantForkProd(conversationId: string, sourceBranchId: string,
  editAtNodeId: string | null, content: string): Promise<EditAssistantForkResult> {
  return editAssistantFork(sharedRdbStore(), {
    conversationId: conversationId,
    sourceBranchId: sourceBranchId,
    editAtNodeId: editAtNodeId,
    content: content,
    now: nextRowCreatedAt()
  });
}

// 提问编辑生产入口：形制同 editAssistantForkProd
export async function editUserForkProd(conversationId: string, sourceBranchId: string,
  editAtNodeId: string | null, content: string,
  quoteText: string): Promise<EditAssistantForkResult> {
  return editUserFork(sharedRdbStore(), {
    conversationId: conversationId,
    sourceBranchId: sourceBranchId,
    editAtNodeId: editAtNodeId,
    content: content,
    quoteText: quoteText,
    now: nextRowCreatedAt()
  });
}
