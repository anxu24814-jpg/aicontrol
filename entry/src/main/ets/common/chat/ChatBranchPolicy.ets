// 会话内分支与历史编辑判据域：**分支/历史编辑四类入口的能力判据与图边界定位纯函数**——
// 零 UI 零 DB import 的叶子件（UI 菜单可见性、控制器编排、断言直跑三方共用；并入
// ChatContextSource 会让 UI 层反向依赖 DB 层）。
// 依赖纪律（零环红线，坑50）：本件不 import 任何其它模块——会话两值词表（graph/legacy）以
// 本地常量**镜像**存储侧真源（MessageBranchDb.CONV_STATE_*），两处取值由断言逐字比对（改名
// 或改值即红）；边界定位只在调用方给的轻行集上走（判据在纯函数，权威校验仍在仓储命令内）。
// 四判据与 tail 的关系（L6 红线）：**不得以 tail 同时代替四种权限**——tail 只说明「其后无
// 任何消息」（末条重试键的既有判据），能否重试/编辑/建分支/切路径各由四函数独立判定（中途
// 整轮重试正是「tail=false 也可重试」的兑现面）。
// 格式态词表已收缩为**两值**（graph/legacy，migrating 随迁移机制退役删除）：本件判据只认
//「graph 可写」，其余态一律 fail-closed（legacy 支 = 墓碑短句，未知态 = 状态未就绪）。
export const SESSION_LEGACY: string = 'legacy';
export const SESSION_GRAPH: string = 'graph';

// 消息类别（与 ChatMessage.kind 同值域；本件只认这三类，其余一律不开放新入口）
export const KIND_USER: string = 'user';
export const KIND_ASSISTANT: string = 'assistant';

// 目标消息事实（调用方从视图消息与其所在数据源摘取——本件不依赖组件层类型）
export interface BranchTargetFacts {
  kind: string;            // ChatMessage.kind
  streaming: boolean;      // 正在流式产出（未收尾）
  roundOpen: boolean;      // 该行之后**同一轮**仍有后续（工具卡 / 中间轮）——轮未收尾
  graphIdentity: boolean;  // 图身份在场（nodeId 有值，或回放链 id 即节点 id）
  session: string;         // SESSION_*
  running: boolean;        // 本会话有活跃 run
}

// 判据结果（reason 单源 = 面向用户的禁用/拒绝文案；文案守宪法「面向用户文案写作规约」）
export interface BranchAllow {
  allowed: boolean;
  reason: string;
}

// ── 三道共闸（会话态 / 占用 / 图身份）──

// 会话态闸：只有 graph 态开放新入口——legacy（旧格式墓碑）给墓碑短句；其余未知态一律
// fail-closed 给状态未就绪句（宁缺勿错：判据不可靠时不放行）
export function sessionGate(f: BranchTargetFacts): string {
  if (f.session === SESSION_LEGACY) {
    return TOMBSTONE_TOAST_TEXT;
  }
  if (f.session !== SESSION_GRAPH) {
    return '会话状态未就绪，暂不可用';
  }
  return '';
}

// 占用闸（L7：运行中要求先停止——不偷偷中止、不另开并发 run）
export function runningGate(f: BranchTargetFacts): string {
  return f.running ? '请先停止当前回复' : '';
}

// ── 旧格式墓碑文案（迁移机制全量退役后，非 graph 态会话的唯一用户面表述；两条文案本件
//    单源，各消费点禁自抄）──
// 覆盖层句（消费点 = ChatPageLoadCtrl → ChatDataSource.blockedNotice → ChatPageContent
// 覆盖层）：说明现状 + 数据仍在 + 唯一出口长按删除，无重试键（迁移不再发生，重试是欺骗）。
// 动作短句（消费点 = 一切写入口）：一句告知，不解释机制。
// 文案守宪法「面向用户文案写作规约」。
export const TOMBSTONE_NOTICE_TEXT: string =
  '这条会话是旧格式，本版本不再支持打开。数据还在本机，长按会话可删除';
export const TOMBSTONE_TOAST_TEXT: string = '这条会话是旧格式，暂不可用';

// 图身份闸（Y10：新入口一律以节点身份为锚；live 链未回填的中间行按不可用降级——
// 宁缺勿错：拿内存 id 当锚会落到别处，不猜）
export function identityGate(f: BranchTargetFacts): string {
  return f.graphIdentity ? '' : '这条消息的位置信息还没就绪，暂不可用';
}

// 收尾闸（流式中与未收尾轮不开放——L6：tool 中间/待审批/不完整交换不开放；不伪造完整输出）
export function settledGate(f: BranchTargetFacts): string {
  if (f.streaming) {
    return '这条消息还在生成中，暂不可用';
  }
  if (f.roundOpen) {
    return '这一轮的步骤还没走完，暂不可用';
  }
  return '';
}

function gate(f: BranchTargetFacts): string {
  const s: string = sessionGate(f);
  if (s !== '') {
    return s;
  }
  const r: string = runningGate(f);
  if (r !== '') {
    return r;
  }
  const i: string = identityGate(f);
  if (i !== '') {
    return i;
  }
  return settledGate(f);
}

function allow(reason: string): BranchAllow {
  return { allowed: reason === '', reason: reason };
}

// 切路径（会话级操作：目标无关，只要会话处于图态且没有活跃轮次）
export function canSwitchPath(f: BranchTargetFacts): BranchAllow {
  const s: string = sessionGate(f);
  if (s !== '') {
    return allow(s);
  }
  return allow(runningGate(f));
}

// 中途整轮重试（L1：从目标所属 run 的完整输入锚点生成替代路径）：目标恒为 assistant——
// 失败/取消的轮次照旧可重试（L6：不因不是 completed 一概丢弃既有重试能力），判据只问
// 「轮是否收尾 + 锚可否定位」
export function canRetryAt(f: BranchTargetFacts): BranchAllow {
  if (f.kind !== KIND_ASSISTANT) {
    return allow('');
  }
  return allow(gate(f));
}

// 历史 user 编辑（L2：同 parent 建新 user 节点）：目标恒为 user 消息
export function canEditUser(f: BranchTargetFacts): BranchAllow {
  if (f.kind !== KIND_USER) {
    return allow('');
  }
  return allow(gate(f));
}

// 历史助手编辑（分叉落编辑版节点，旧回复留原路径）：目标恒为 assistant 消息——收尾闸天然
// 覆盖「限已收尾答案行」拍板：工具中间轮的 assistant 过渡行 roundOpen=true 即拒，只有轮
// 收尾的最终答案行可编辑
export function canEditAssistant(f: BranchTargetFacts): BranchAllow {
  if (f.kind !== KIND_ASSISTANT) {
    return allow('');
  }
  return allow(gate(f));
}

// 会话内 fork（L5：从合法边界建分支）：合法边界 = user 节点 或 已收尾的 assistant 运行边界
export function canForkAt(f: BranchTargetFacts): BranchAllow {
  if (f.kind !== KIND_USER && f.kind !== KIND_ASSISTANT) {
    return allow('');
  }
  return allow(gate(f));
}

// 消息删除：谱系剪枝删除（目标节点及其全部后代闭包，跨一切分支）——目标 = user 与
// assistant 两角色（user 行删除连带其回答；assistant 轮尾行删除连带其后续）。★ 裁定 H：
// **不加「阅读分支拒删」判据**——删除入口恒在当前路径，每条可见消息都在「当前显示」，
// 拒删等于助手回复整体不可删且与「user 连带删同一回答」不自洽；若日后改判拒删口径，后备
// 判据 = 编排层 deleteAllow 内加「目标为活动分支 head 且 kind=assistant 时拒」+ 复用
// ChatAnswerCtrl「请先切换到其他回答，再删除这一版」文案（预留不实现）。四闸全复用 gate()
//（零新文案零新判据：生成中 runningGate 拦、流式/未收尾 settledGate 拦）
export function canDeleteAt(f: BranchTargetFacts): BranchAllow {
  if (f.kind !== KIND_USER && f.kind !== KIND_ASSISTANT) {
    return allow('');
  }
  return allow(gate(f));
}

// 入口是否结构性适用（菜单项渲染判据：不适用 = 整项隐藏，不渲染成灰项；可用性另由上面
// 四判据经点击呈报给出原因）。tool/thinking/notice/summary 行没有任何新入口
export function hasAnyEntry(f: BranchTargetFacts): boolean {
  if (f.kind !== KIND_USER && f.kind !== KIND_ASSISTANT) {
    return false;
  }
  return true;
}

// ── 图边界定位（纯函数：调用方给轻行集，本件只走链）──

// 目标节点图身份解析（判据单源，纯函数——断言直跑面）：回填值优先；实时行（live）与
// 流式行一律不给 id 回退（内存 id ≠ 节点 id = 伪锚——发送准备失败残留行永不回填 nodeId，
// 旧判据的 id 回退会把它当节点身份用，四处入口的空锚守卫因伪锚「非空」而不触发）；仅回放
// 行（窗口即路径窗口、其 id 即节点 id）允许回退。返回 '' = 不可锚（上层按拒绝文案呈现，禁猜）。
// 消费方 = ChatBranchCtrl.nodeIdOf（唯一委托，禁第二份判据）；本件零 import，只收基本类型
export function resolveNodeIdOf(stampedId: string, live: boolean, streaming: boolean,
  pathWindow: boolean, memId: string): string {
  if (stampedId !== '') {
    return stampedId;
  }
  if (live || streaming) {
    return '';
  }
  return pathWindow ? memId : '';
}

// 图节点轻行（只取定位所需三列——与 MessageBranchDb.GraphNodeRef 同形但另有 role；
// 不复用彼件类型是为了零 import 纪律，字段名与库列同名便于核对）
export interface BranchAnchorRow {
  id: string;
  parentMessageId: string | null;
  role: string;
}

// 目标所属 run 的完整输入锚点（L1 定位纯函数）：从目标节点沿父链上溯找最近 role='user'
// 祖先——图会话里一个 run 的输入锚点即该轮的 user 节点（工具轮中间行的父链必经它），故
// 「最近 user 祖先」与「run.inputAnchorMessageId」同解（仓储侧 walkRetryAnchor 同语义；
// 本函数供 UI 判据与断言直跑，生产起轮仍走仓储读口）。坏链/上界耗尽回 null（宁缺勿错）
export function resolveRunInputAnchor(startId: string,
  nodes: Map<string, BranchAnchorRow>): string | null {
  let cursor: string | null = startId;
  let steps: number = 0;
  const bound: number = nodes.size + 1;
  while (cursor !== null && cursor !== '' && steps <= bound) {
    const row: BranchAnchorRow | undefined = nodes.get(cursor);
    if (row === undefined) {
      return null;
    }
    if (row.role === KIND_USER) {
      return cursor;
    }
    cursor = row.parentMessageId;
    steps++;
  }
  return null;
}

// 边界合法性（与 MessageBranchDb.validateGraphInsertion 语义同族：悬边 / 跨会话 / 环——
// 本函数只做「该点在链上是否可达根」的轻判，会话归属与环由仓储命令权威校验）。返回 null
// = 合法；返回中文原因 = 拒绝（调用方原样呈报）
export function validateBoundaryReachable(nodeId: string, conversationNodes: Map<string,
  BranchAnchorRow>): string | null {
  if (nodeId === '') {
    return null; // 空 head（从根 fork）无链可查，合法
  }
  let cursor: string | null = nodeId;
  let steps: number = 0;
  const bound: number = conversationNodes.size + 1;
  while (cursor !== null && cursor !== '') {
    if (!conversationNodes.has(cursor)) {
      return '目标节点不在本会话的图里，无法创建分支';
    }
    const row: BranchAnchorRow = conversationNodes.get(cursor) as BranchAnchorRow;
    steps++;
    if (steps > bound) {
      return '父链步数超过节点集规模，图已损坏，拒绝操作';
    }
    cursor = row.parentMessageId;
  }
  return null;
}
