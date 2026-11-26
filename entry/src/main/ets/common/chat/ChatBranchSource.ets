// 分支域（自 ChatContextSource.ets 拆出——分支列表读、切分支单点、会话内建分支与节点父链定位）。
// 域定义：会话分支的**列表读/切换/创建单点**——面板读侧（BranchSummary 单点，面板不做裸
// 查询）＋ 切默认分支与建分支的唯一写入口（含编辑保留附件的引用级回挂、节点父链三态定位）。
// 依赖方向（零环红线，坑50）：本件 → ChatDb（单点口/句柄/号分配）+ MessageBranchDb（fork
// 命令与类型）单向；**本件零 import 主件 ChatContextSource**；组件层（ChatBranchCtrl/
// ChatBranchSheet/ChatPage）可 import 本件；store 侧零件与主件**零反向 import 本件**。
// 模块顶层零求值纪律（坑50 家族）：顶层零求值，禁顶层 new / 跨件函数调用 / AppStorage 读
//（函数体内读不受限）。
// 边界登记：readBranchAnchors 属地属本域但**留主件**——主件读侧 readReachableNodeIds
// 消费它，迁出会造成主件→本件反向依赖（环）；消费方 ChatRetryCtrl 照旧从主件取。
import { relationalStore } from '@kit.ArkData';
import { nextMessageId, queryConversationActiveBranch,
  setConversationActiveBranch, sharedRdbStore } from '../store/ChatDb';
// 回答图快照类型（纯叶子件——本件只读快照，归组算法在彼件）
import { AnswerGraphBranch, AnswerGraphNode, AnswerGraphRun, AnswerGraphSnapshot }
  from './ChatAnswerChoice';

// ── 分支域：分支列表读、切分支单点、会话内建分支 ──

// 分支摘要行（面板展示用：名称 / head / 所选点预览 / 是否当前 / 谱系父）——读侧单点，面板
// 不做裸查询。parentBranchId '' = 根分支，删除入口据此不渲染（删根分支等于清空整会话，
// 那是删会话的语义）
export interface BranchSummary {
  branchId: string;
  parentBranchId: string;
  name: string;
  headMessageId: string;
  headRole: string;
  headPreview: string;
  createdAt: number;
  isActive: boolean;
}

// head 预览截断长度（面板单行展示；超长截断加省略号，与列表项预览同族克制）
const BRANCH_PREVIEW_MAX: number = 24;

// 会话全部分支摘要（按创建序升序 = 分支树的自然叙述序；isActive 现读单点口）。
// head 节点预览一次 IN 查询合并（分支数单会话个位数量级，量级可忽略）；head 空（空分支）
// 预览留空不查——空 head 是合法态（branches.headMessageId 可空注释）
export async function queryConversationBranches(conversationId: string): Promise<BranchSummary[]> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const activeBranchId: string = await queryConversationActiveBranch(conversationId);
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT id, parentBranchId, headMessageId, name, createdAt FROM branches ' +
    'WHERE conversationId = ? ORDER BY createdAt ASC, rowid ASC', [conversationId]);
  const out: BranchSummary[] = [];
  const headIds: string[] = [];
  try {
    while (result.goToNextRow()) {
      const headIdx: number = result.getColumnIndex('headMessageId');
      const headId: string = result.isColumnNull(headIdx) ? '' :
        result.getString(headIdx);
      const parentIdx: number = result.getColumnIndex('parentBranchId');
      const branchId: string = result.getString(result.getColumnIndex('id'));
      out.push({
        branchId: branchId,
        parentBranchId: result.isColumnNull(parentIdx) ? ''
          : result.getString(parentIdx),
        name: result.getString(result.getColumnIndex('name')),
        headMessageId: headId,
        headRole: '',
        headPreview: '',
        createdAt: result.getLong(result.getColumnIndex('createdAt')),
        isActive: branchId === activeBranchId
      });
      if (headId !== '') {
        headIds.push(headId);
      }
    }
  } finally {
    result.close();
  }
  if (headIds.length === 0) {
    return out;
  }
  const nodeResult: relationalStore.ResultSet = await db.querySql(
    'SELECT id, role, content FROM messages WHERE id IN (' +
    headIds.map((_id: string): string => '?').join(',') + ')', headIds);
  const roleBy: Map<string, string> = new Map<string, string>();
  const previewBy: Map<string, string> = new Map<string, string>();
  try {
    while (nodeResult.goToNextRow()) {
      const id: string = nodeResult.getString(nodeResult.getColumnIndex('id'));
      roleBy.set(id, nodeResult.getString(nodeResult.getColumnIndex('role')));
      previewBy.set(id, previewOf(nodeResult.getString(nodeResult.getColumnIndex('content'))));
    }
  } finally {
    nodeResult.close();
  }
  for (const row of out) {
    if (row.headMessageId !== '') {
      row.headRole = roleBy.get(row.headMessageId) ?? '';
      row.headPreview = previewBy.get(row.headMessageId) ?? '';
    }
  }
  return out;
}

// 预览单行化（空白压一空格 + 超长截断——展示用，不改库内文本）
function previewOf(text: string): string {
  const line: string = text.replace(/\s+/g, ' ').trim();
  return line.length > BRANCH_PREVIEW_MAX ? line.substring(0, BRANCH_PREVIEW_MAX) + '…' : line;
}

// 切默认分支（S2/L4：会话级默认分支选择落既有单点 setConversationActiveBranch——本函数是
// 读侧组件层到存储单点的唯一入口，禁各处直调）。运行中不切由调用方判据先行（L7）
export async function switchActiveBranch(conversationId: string, branchId: string): Promise<void> {
  await setConversationActiveBranch(conversationId, branchId);
}

// ★ createBranchAt（会话内建分支单点）已随旧 user 编辑链退役——现役编辑分叉命令 =
// GraphEditFork.editUserFork / editAssistantFork（同一事务内建分支行 + 落编辑节点 + head
// 指向，无「先建空分支再挂节点」中间态）。分支行只经 forkBranch（仓储校验面）与两编辑
// 分叉命令产生。

// 既有附件资源行的 refs 补挂（编辑保留原附件：把原 user 节点的附件**引用**挂到新节点——
// 复用既有资源行，不复制文件、不删旧引用、不动旧行归属；空集零开销）
export async function insertAttachmentRefsForIds(conversationId: string,
  attachmentIds: string[], nodeId: string): Promise<void> {
  if (attachmentIds.length === 0 || nodeId === '') {
    return;
  }
  const db: relationalStore.RdbStore = sharedRdbStore();
  const now: number = Date.now();
  for (const attachmentId of attachmentIds) {
    await db.insert('attachment_refs', {
      'id': nextMessageId('ref'),
      'conversationId': conversationId,
      'attachmentId': attachmentId,
      'nodeId': nodeId,
      'createdAt': now
    });
  }
}

// 节点父链定位（编辑：取目标 user 节点的 parentMessageId——同 parent 建新节点用）。语义与
// resolveRunInputAnchor 一致但读库，供生产链调用。★ 返回三态区分：`undefined` = **节点行
// 不存在**（伪锚/节点已删，调用方必须拒绝，禁当「父为根」放行——直插空 head 分支会让旧
// 会话从屏上消失）；`null` = 行在而父为根（合法，从根建分支）；字符串 = 父节点 id。
//（唯一调用点 ChatBranchCtrl.beginEdit）
export async function queryNodeParentId(nodeId: string): Promise<string | null | undefined> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT parentMessageId FROM messages WHERE id = ?', [nodeId]);
  try {
    if (!result.goToNextRow()) {
      return undefined;
    }
    const idx: number = result.getColumnIndex('parentMessageId');
    return result.isColumnNull(idx) ? null : result.getString(idx);
  } finally {
    result.close();
  }
}

// ── 回答图快照只读 ──

// 一次性读全本会话的图快照（分支行 / 节点九列 / 运行四列 + 库默认分支）——边界 = **单会话、
// 本次请求寿命**（不是全库、不是固定条数）：不逐分支查父、不按每段查 run、不调
// queryConversationBranches 后重查同一集合；只读必要列，不读 reasoning / 工具事实 / 用量与
// 诊断全文。每次打开或每次提交前最多一套本批读；算法完成即释放原始数组（调用方只留
// choices 的短预览与身份，禁跨打开缓存）。空候选是合法业务结果；读失败原样 reject、坏图由
// 纯函数（ChatAnswerChoice.buildAnswerChoices）抛中文 Error——均不得折成 []。本口不创建
// 会话、不触发迁移、不写任何行
export async function queryAnswerGraphSnapshot(
  conversationId: string): Promise<AnswerGraphSnapshot> {
  const db: relationalStore.RdbStore = sharedRdbStore();
  const defaultBranchId: string = await queryConversationActiveBranch(conversationId);
  const branches: AnswerGraphBranch[] = [];
  const branchResult: relationalStore.ResultSet = await db.querySql(
    'SELECT id, conversationId, headMessageId, createdAt FROM branches WHERE conversationId = ?',
    [conversationId]);
  try {
    while (branchResult.goToNextRow()) {
      const headIdx: number = branchResult.getColumnIndex('headMessageId');
      branches.push({
        branchId: branchResult.getString(branchResult.getColumnIndex('id')),
        conversationId: branchResult.getString(branchResult.getColumnIndex('conversationId')),
        headMessageId: branchResult.isColumnNull(headIdx) ? null
          : branchResult.getString(headIdx),
        createdAt: branchResult.getLong(branchResult.getColumnIndex('createdAt'))
      });
    }
  } finally {
    branchResult.close();
  }
  const nodes: AnswerGraphNode[] = [];
  const nodeResult: relationalStore.ResultSet = await db.querySql(
    'SELECT id, conversationId, parentMessageId, role, content, runId, origin, status, createdAt ' +
    'FROM messages WHERE conversationId = ?', [conversationId]);
  try {
    while (nodeResult.goToNextRow()) {
      const parentIdx: number = nodeResult.getColumnIndex('parentMessageId');
      nodes.push({
        id: nodeResult.getString(nodeResult.getColumnIndex('id')),
        conversationId: nodeResult.getString(nodeResult.getColumnIndex('conversationId')),
        parentMessageId: nodeResult.isColumnNull(parentIdx) ? null
          : nodeResult.getString(parentIdx),
        role: nodeResult.getString(nodeResult.getColumnIndex('role')),
        content: nodeResult.getString(nodeResult.getColumnIndex('content')),
        runId: nodeResult.getString(nodeResult.getColumnIndex('runId')),
        origin: nodeResult.getString(nodeResult.getColumnIndex('origin')),
        status: nodeResult.getString(nodeResult.getColumnIndex('status')),
        createdAt: nodeResult.getLong(nodeResult.getColumnIndex('createdAt'))
      });
    }
  } finally {
    nodeResult.close();
  }
  const runs: AnswerGraphRun[] = [];
  const runResult: relationalStore.ResultSet = await db.querySql(
    'SELECT id, conversationId, branchId, status FROM generation_runs WHERE conversationId = ?',
    [conversationId]);
  try {
    while (runResult.goToNextRow()) {
      runs.push({
        id: runResult.getString(runResult.getColumnIndex('id')),
        conversationId: runResult.getString(runResult.getColumnIndex('conversationId')),
        branchId: runResult.getString(runResult.getColumnIndex('branchId')),
        status: runResult.getString(runResult.getColumnIndex('status'))
      });
    }
  } finally {
    runResult.close();
  }
  return { conversationId: conversationId, defaultBranchId: defaultBranchId,
    nodes: nodes, branches: branches, runs: runs };
}
