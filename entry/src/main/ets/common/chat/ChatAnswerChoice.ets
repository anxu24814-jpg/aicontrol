// 回答与提问归组、轮耗时可信度纯函数叶子。
// 域定义：**从「限定会话的单次图快照」求同一提问轮的可选回答、同一 parent 下的提问变体、
// 以及轮耗时的可信判据**——父链校验 / 同轮归组 / 代表分支选择 / 预览截断 / 时间可信度全在
// 此，零 I/O 零平台依赖。
// 依赖纪律（零环红线，坑50）：本件零 import，类型与实现自持（纯叶子，禁反向依赖组件层）。
// 失败口径：空候选是**合法业务结果**（无最近 user 时 userNodeId=''、choices=[]）；读失败、
// 坏图、目标不在屏幕路径、当前勾不可证一律抛中文 Error，不能混为 []（面板与服务端据此分流）。
// 本件只吃「图快照」与两个 id（loadedBranchId / targetNodeId），不读屏幕消息对象——屏幕身份
// 由 ChatDataSource.loadedBranch() 给，节点身份由 ChatBranchPolicy.resolveNodeIdOf 单源给。
// ★ 口径声明：本件实现的是「**保存路径中的回答**」——分支从轮内中间正文处截断且该正文
// run 已终态时也算一个保存的回答候选；未终态 run 的截断前缀不入选。不得在两种口径
//（「每 run 恰一条最终文本」与「保存路径中的答案」）间自行切换。

// 角色与终态词表（与库列同值域；本件零 import 故以本地常量镜像——取值与 store 侧同源，
// 由断言逐字比对）
export const ROLE_USER: string = 'user';
export const ROLE_ASSISTANT: string = 'assistant';
// generation_runs.status 终态两值（失败与停止都归 failed，历史无法恢复 stopped）
const RUN_STATUS_FINISHED: string = 'finished';
const RUN_STATUS_FAILED: string = 'failed';
// 无 run 候选的唯一合法来源（人工编辑助手正文：origin=edit_assistant 且节点 status=done）。
// ★ 2026-11-14 DS 导入真保真笔：**导入节点同样无 run**（DsHistoryImportApply 落 runId=''，
// origin='import'）——不加此支则导入的多版本回答全部被终态过滤剔除（步进器恒不出），
// 与「导入多版本走现有步进器」拍板相反。导入节点只收 status=done（错误轮不进候选）。
const ORIGIN_EDIT_ASSISTANT: string = 'edit_assistant';
const ORIGIN_IMPORT: string = 'import';
const NODE_STATUS_DONE: string = 'done';
// 预览截断（Unicode 码点口径——emoji 等增补平面字符 1 码点 2 码元，禁按 length 截）
const PREVIEW_MAX_POINTS: number = 80;
// 耗时短档分界（小于 60 秒一位小数秒，否则整数秒）
const DURATION_SHORT_MS: number = 60000;

// 坏图拒绝文案（重复 id / 跨会话记录 / 缺父 / 环 / 空非 null 父——任一命中即整次查询失败，
// 不把坏分支静默跳过后显示「暂无其他回答」）
const BAD_GRAPH_TEXT: string = '回答数据异常，请刷新会话后重试';
// 事实不满足拒绝文案（目标不在屏幕路径 / 点击行不是该轮当前末正文 / 当前勾不可证——宁缺勿错）
const STALE_TEXT: string = '这条回复的位置信息已变化，请刷新会话后重试';

// ── 图快照类型（读口产物形状；读侧 = ChatBranchSource.queryAnswerGraphSnapshot）──

// 消息节点（只读必要列：身份 / 父链 / 正文 / run 归属 / 来源 / 状态 / 时间——不读 reasoning、
// 工具事实、用量/诊断全文）
export interface AnswerGraphNode {
  id: string;
  conversationId: string;
  parentMessageId: string | null;
  role: string;
  content: string;
  runId: string;
  origin: string;
  status: string;
  createdAt: number;
}

// 分支行（空 head 是合法态 = 空分支）
export interface AnswerGraphBranch {
  branchId: string;
  conversationId: string;
  headMessageId: string | null;
  createdAt: number;
}

// 运行行（只取归组判据所需四列）
export interface AnswerGraphRun {
  id: string;
  conversationId: string;
  branchId: string;
  status: string;
}

// 图快照（一次请求寿命：调用方读完即用、用完释放——不长持、不跨打开缓存）
export interface AnswerGraphSnapshot {
  conversationId: string;
  defaultBranchId: string;
  nodes: AnswerGraphNode[];
  branches: AnswerGraphBranch[];
  runs: AnswerGraphRun[];
}

// 一条可选回答（answerNodeId = 该回答的答案节点；branchId = 代表分支——切换即切到它；
// preview 是短预览不是复制正文数据源）
export interface ChatAnswerChoice {
  answerNodeId: string;
  branchId: string;
  runId: string;
  preview: string;
  createdAt: number;
  incomplete: boolean;
}

// 归组结果（selectedAnswerId = 当前屏幕勾【loadedBranchId 在该 U 区间的末正文】，不是库
// 默认分支的 A；loadedBranchId = 本次**生效**的屏幕身份——入参空时按 §3.2 限定规则用库默认
// 证明后回填，调用方据此补记 markLoadedBranch；无最近 user 时 userNodeId='' 且 choices=[]）
export interface ChatAnswerChoices {
  userNodeId: string;
  selectedAnswerId: string;
  loadedBranchId: string;
  defaultBranchId: string;
  choices: ChatAnswerChoice[];
}

// ── 轮耗时可信度（与答案候选判据分立——只用运行行的既有时间列）──

// 运行行的时间可信度输入（status / 诊断载荷 / 两时间列；TraceRunIn 的子集形状）
export interface RoundTimingInput {
  status: string;
  diagnosticMessageId: string;
  createdAt: number;
  updatedAt: number;
}

// 可信时长（毫秒；undefined = 不可信——宁缺不伪造）。可信度顺序：
// ①status 只收 finished/failed，failed 还须 diagnosticMessageId 非空（证明经带诊断的真实
// 终结，排除启动清扫 ChatDbSweep.sweepStaleGraphRuns 把残留 prepared/running 改 failed 并把
// updatedAt 写成启动时刻的伪长耗时）；②createdAt/updatedAt 须有限、createdAt>0、
// updatedAt>createdAt；③结果 = updatedAt − createdAt（不减工具等待/审批，不读
// usageDurationMs，不用消息 createdAt 极值相减）。
export function trustedRoundDurationMs(run: RoundTimingInput): number | undefined {
  if (run.status !== RUN_STATUS_FINISHED && run.status !== RUN_STATUS_FAILED) {
    return undefined;
  }
  if (run.status === RUN_STATUS_FAILED && run.diagnosticMessageId === '') {
    return undefined;
  }
  if (!Number.isFinite(run.createdAt) || !Number.isFinite(run.updatedAt)) {
    return undefined;
  }
  if (!(run.createdAt > 0) || !(run.updatedAt > run.createdAt)) {
    return undefined;
  }
  const durationMs: number = run.updatedAt - run.createdAt;
  if (!Number.isFinite(durationMs)) {
    return undefined;
  }
  return durationMs;
}

// 过程摘要尾缀（空值返 ''；合法返「 · 本轮耗时 X 秒」——小于 60 秒一位小数、否则整数秒；
// 正值极小可按一位小数显示 0.0 秒，这与缺失值不同，不得为防 0.0 伪增原始毫秒）
export function roundDurationSuffix(durationMs: number | undefined): string {
  if (durationMs === undefined || !Number.isFinite(durationMs)) {
    return '';
  }
  if (durationMs < DURATION_SHORT_MS) {
    return ' · 本轮耗时 ' + (durationMs / 1000).toFixed(1) + ' 秒';
  }
  return ' · 本轮耗时 ' + Math.round(durationMs / 1000).toString() + ' 秒';
}

// 预览单行化：连续空白压一个空格 + trim，再取前 80 个 Unicode 码点，有剩余补省略号。
// 不剥 Markdown——预览不是正文真源
export function answerPreviewOf(content: string): string {
  const line: string = content.replace(/\s+/g, ' ').trim();
  const points: string[] = Array.from(line);
  if (points.length <= PREVIEW_MAX_POINTS) {
    return points.join('');
  }
  return points.slice(0, PREVIEW_MAX_POINTS).join('') + '…';
}

// ── 归组主函数（执行顺序固定）──

export function buildAnswerChoices(snapshot: AnswerGraphSnapshot,
  loadedBranchId: string, targetNodeId: string): ChatAnswerChoices {
  // 1. 建索引：重复 id / 记录 conversationId 与请求会话不符 = 坏图拒绝
  const nodes: Map<string, AnswerGraphNode> = new Map();
  for (const node of snapshot.nodes) {
    if (nodes.has(node.id) || node.conversationId !== snapshot.conversationId) {
      throw new Error(BAD_GRAPH_TEXT);
    }
    nodes.set(node.id, node);
  }
  const branches: Map<string, AnswerGraphBranch> = new Map();
  for (const branch of snapshot.branches) {
    if (branches.has(branch.branchId) ||
      branch.conversationId !== snapshot.conversationId) {
      throw new Error(BAD_GRAPH_TEXT);
    }
    branches.set(branch.branchId, branch);
  }
  const runs: Map<string, AnswerGraphRun> = new Map();
  for (const run of snapshot.runs) {
    if (runs.has(run.id) || run.conversationId !== snapshot.conversationId) {
      throw new Error(BAD_GRAPH_TEXT);
    }
    runs.set(run.id, run);
  }
  // 2. 目标必须存在且为非空 assistant，再沿父链上溯找最近 role=user 的 U
  const target: AnswerGraphNode | undefined = nodes.get(targetNodeId);
  if (target === undefined || target.role !== ROLE_ASSISTANT ||
    target.content.trim() === '') {
    throw new Error(STALE_TEXT);
  }
  const user: AnswerGraphNode | null = nearestUserAncestor(nodes, target);
  if (user === null) {
    // 无最近 user = 没有可切换的提问轮（合法业务结果，非失败）
    return { userNodeId: '', selectedAnswerId: '', loadedBranchId: loadedBranchId,
      defaultBranchId: snapshot.defaultBranchId, choices: [] };
  }
  // 3. 屏幕身份与目标校验：已知 loadedBranchId 时验证目标在其路径上；屏幕身份尚空时按
  //    §3.2 限定规则用库默认分支尝试建立（路径包含目标 + 该 U 末正文恰为点击节点），
  //    验证失败不猜
  let effectiveLoaded: string = loadedBranchId;
  if (effectiveLoaded === '') {
    const fallback: string = snapshot.defaultBranchId;
    if (fallback === '' || !branches.has(fallback)) {
      throw new Error(STALE_TEXT);
    }
    const fallbackPath: AnswerGraphNode[] =
      branchPathOf(nodes, (branches.get(fallback) as AnswerGraphBranch).headMessageId);
    let containsTarget: boolean = false;
    for (const node of fallbackPath) {
      if (node.id === targetNodeId) {
        containsTarget = true;
        break;
      }
    }
    if (!containsTarget || regionAnswerIdOf(fallbackPath, user.id) !== targetNodeId) {
      throw new Error(STALE_TEXT);
    }
    effectiveLoaded = fallback;
  }
  const loadedBranch: AnswerGraphBranch | undefined = branches.get(effectiveLoaded);
  if (loadedBranch === undefined) {
    throw new Error(STALE_TEXT);
  }
  const loadedPath: AnswerGraphNode[] = branchPathOf(nodes, loadedBranch.headMessageId);
  let targetOnLoaded: boolean = false;
  for (const node of loadedPath) {
    if (node.id === targetNodeId) {
      targetOnLoaded = true;
      break;
    }
  }
  if (!targetOnLoaded) {
    throw new Error(STALE_TEXT);
  }
  // 4. 每个合法分支从 head 还原路径，求「U 之后到下一 user 之前」区间的末正文（不含 U 的
  //    分支不参加；空 head = 合法空分支跳过；坏图即抛）
  const branchList: AnswerGraphBranch[] = snapshot.branches;
  const regionAOf: Map<string, string> = new Map();
  for (const branch of branchList) {
    const path: AnswerGraphNode[] = branchPathOf(nodes, branch.headMessageId);
    regionAOf.set(branch.branchId, regionAnswerIdOf(path, user.id));
  }
  // 11（前置）：当前勾 = 屏幕分支在该 U 区间的末正文；点击行必须仍是该轮当前末正文
  const currentA: string = regionAOf.get(effectiveLoaded) ?? '';
  if (currentA === '' || currentA !== targetNodeId) {
    throw new Error(STALE_TEXT);
  }
  // 5-7. 候选 = 各分支区间末正文按 A.id 去重（同文不同 A.id 保留两项；人工编辑的新 A 独立）
  const producersOf: Map<string, string[]> = new Map();
  for (const branch of branchList) {
    const aId: string = regionAOf.get(branch.branchId) ?? '';
    if (aId === '') {
      continue;
    }
    const list: string[] = producersOf.get(aId) ?? [];
    list.push(branch.branchId);
    producersOf.set(aId, list);
  }
  const choices: ChatAnswerChoice[] = [];
  producersOf.forEach((producerIds: string[], aId: string): void => {
    const node: AnswerGraphNode | undefined = nodes.get(aId);
    if (node === undefined) {
      return;
    }
    // 6. 终态过滤：A.runId 非空 → run 必须存在、同会话、finished/failed（failed 标未完成）；
    //    runId 空 → 只收 origin=edit_assistant 且 status=done（普通无 run 主动消息不混入）
    let eligible: boolean = false;
    let incomplete: boolean = false;
    if (node.runId !== '') {
      const run: AnswerGraphRun | undefined = runs.get(node.runId);
      if (run !== undefined && run.conversationId === snapshot.conversationId &&
        (run.status === RUN_STATUS_FINISHED || run.status === RUN_STATUS_FAILED)) {
        eligible = true;
        incomplete = run.status === RUN_STATUS_FAILED;
      }
    } else if ((node.origin === ORIGIN_EDIT_ASSISTANT || node.origin === ORIGIN_IMPORT) &&
      node.status === NODE_STATUS_DONE) {
      eligible = true;
    }
    if (!eligible) {
      return;
    }
    // 8. 代表分支固定优先级：当前区间末正文 → run 分支（须存在且该分支该 U 区间末正文仍为 A）
    //    → 真产出该 A 的分支集合内按 createdAt 升序、branchId 升序取第一条
    let representative: string = '';
    if (aId === currentA) {
      representative = effectiveLoaded;
    } else {
      let runBranch: string = '';
      if (node.runId !== '') {
        const run: AnswerGraphRun | undefined = runs.get(node.runId);
        if (run !== undefined) {
          runBranch = run.branchId;
        }
      }
      if (runBranch !== '' && branches.has(runBranch) &&
        (regionAOf.get(runBranch) ?? '') === aId) {
        representative = runBranch;
      } else {
        let best: string = '';
        let bestCreated: number = 0;
        for (const branchId of producerIds) {
          const branch: AnswerGraphBranch | undefined = branches.get(branchId);
          if (branch === undefined) {
            continue;
          }
          if (best === '' || branch.createdAt < bestCreated ||
            (branch.createdAt === bestCreated && branchId < best)) {
            best = branchId;
            bestCreated = branch.createdAt;
          }
        }
        representative = best;
      }
    }
    if (representative === '') {
      return; // 代表不可证——宁缺勿错（不拿 run.branchId 当无校验的代表）
    }
    choices.push({
      answerNodeId: aId,
      branchId: representative,
      runId: node.runId,
      preview: answerPreviewOf(node.content),
      createdAt: node.createdAt,
      incomplete: incomplete
    });
  });
  // 9. 候选按 A.createdAt 升序、A.id 字符串升序（展示序号「回答 N」不入库）
  choices.sort((a: ChatAnswerChoice, b: ChatAnswerChoice): number => {
    if (a.createdAt !== b.createdAt) {
      return a.createdAt - b.createdAt;
    }
    if (a.answerNodeId < b.answerNodeId) {
      return -1;
    }
    return a.answerNodeId > b.answerNodeId ? 1 : 0;
  });
  // 11. 当前 A 必须在候选集中（不在 = 事实不满足可切换条件——拒绝打开，不伪造「回答 0」）
  let selected: string = '';
  for (const choice of choices) {
    if (choice.answerNodeId === currentA) {
      selected = choice.answerNodeId;
      break;
    }
  }
  if (selected === '') {
    throw new Error(STALE_TEXT);
  }
  return { userNodeId: user.id, selectedAnswerId: selected, loadedBranchId: effectiveLoaded,
    defaultBranchId: snapshot.defaultBranchId, choices: choices };
}

// ── 提问版本归组（user 行 ◀x/y▶ 步进器的数据面）──

// 一条可选的提问变体（userNodeId = 该提问节点；branchId = 代表分支——切换即切到它；
// preview 是短预览）
export interface ChatQuestionChoice {
  userNodeId: string;
  branchId: string;
  preview: string;
  createdAt: number;
}

// 归组结果（selectedUserNodeId = 当前屏幕路径上的那个提问变体；零兄弟时 choices 仅一项
// ——调用方按 ≥2 才出步进器）
export interface ChatQuestionChoices {
  parentNodeId: string | null;
  selectedUserNodeId: string;
  loadedBranchId: string;
  choices: ChatQuestionChoice[];
}

// 同一 parent 下的 user 兄弟节点 = 提问变体（历史提问编辑产出：编辑版挂原提问的父）。
// 排序按 createdAt 升序、id 升序（与回答归组同口径）；代表分支优先级 = 屏幕已加载分支 →
// head 即该提问的分支（编辑版自身分支）→ 其余按 createdAt 升序、branchId 升序。
// 目标须在 loadedBranch 路径上（与回答归组同纪律：宁缺勿错）；失败抛中文 Error。
export function buildQuestionChoices(snapshot: AnswerGraphSnapshot, loadedBranchId: string,
  targetNodeId: string): ChatQuestionChoices {
  const nodes: Map<string, AnswerGraphNode> = new Map();
  for (const node of snapshot.nodes) {
    if (nodes.has(node.id) || node.conversationId !== snapshot.conversationId) {
      throw new Error(BAD_GRAPH_TEXT);
    }
    nodes.set(node.id, node);
  }
  const branches: Map<string, AnswerGraphBranch> = new Map();
  for (const branch of snapshot.branches) {
    if (branches.has(branch.branchId) ||
      branch.conversationId !== snapshot.conversationId) {
      throw new Error(BAD_GRAPH_TEXT);
    }
    branches.set(branch.branchId, branch);
  }
  const target: AnswerGraphNode | undefined = nodes.get(targetNodeId);
  if (target === undefined || target.role !== ROLE_USER) {
    throw new Error(STALE_TEXT);
  }
  const effectiveLoaded: string = loadedBranchId !== '' ? loadedBranchId :
    snapshot.defaultBranchId;
  const loadedBranch: AnswerGraphBranch | undefined = branches.get(effectiveLoaded);
  if (loadedBranch === undefined) {
    throw new Error(STALE_TEXT);
  }
  const loadedPath: AnswerGraphNode[] = branchPathOf(nodes, loadedBranch.headMessageId);
  let targetOnLoaded: boolean = false;
  for (const node of loadedPath) {
    if (node.id === targetNodeId) {
      targetOnLoaded = true;
      break;
    }
  }
  if (!targetOnLoaded) {
    throw new Error(STALE_TEXT);
  }
  const parentId: string | null = target.parentMessageId;
  const choices: ChatQuestionChoice[] = [];
  for (const sibling of snapshot.nodes) {
    if (sibling.role !== ROLE_USER || sibling.parentMessageId !== parentId) {
      continue;
    }
    // 代表分支：rank 0 = 屏幕已加载分支 / 1 = head 即该提问（编辑版分支）/ 2 = 其余
    let representative: string = '';
    let bestRank: number = 9;
    let bestCreated: number = 0;
    for (const branch of snapshot.branches) {
      const path: AnswerGraphNode[] = branchPathOf(nodes, branch.headMessageId);
      let contains: boolean = false;
      for (const node of path) {
        if (node.id === sibling.id) {
          contains = true;
          break;
        }
      }
      if (!contains) {
        continue;
      }
      const rank: number = branch.branchId === effectiveLoaded ? 0 :
        (branch.headMessageId === sibling.id ? 1 : 2);
      const better: boolean = rank < bestRank ||
        (rank === bestRank && rank === 2 && branch.createdAt < bestCreated);
      if (better) {
        representative = branch.branchId;
        bestRank = rank;
        bestCreated = branch.createdAt;
      }
    }
    if (representative === '') {
      continue; // 代表不可证——宁缺勿错
    }
    choices.push({
      userNodeId: sibling.id,
      branchId: representative,
      preview: answerPreviewOf(sibling.content),
      createdAt: sibling.createdAt
    });
  }
  choices.sort((a: ChatQuestionChoice, b: ChatQuestionChoice): number => {
    if (a.createdAt !== b.createdAt) {
      return a.createdAt - b.createdAt;
    }
    if (a.userNodeId < b.userNodeId) {
      return -1;
    }
    return a.userNodeId > b.userNodeId ? 1 : 0;
  });
  return {
    parentNodeId: parentId,
    selectedUserNodeId: targetNodeId,
    loadedBranchId: effectiveLoaded,
    choices: choices
  };
}

// 中间正文「重新生成本轮」的宿主解析已退役整段删除（唯一消费方消息菜单中间正文重生链
// 退役）——该轮重试改由轮尾操作栏重试键承载（目标行自身即宿主），勿为此链重建宿主解析。

// 最近 user 祖先（自 target 的父开始上溯）：null = 到合法根仍无 user；空非 null 父 / 缺父 /
// 环 = 坏图拒绝。每个节点至多访问一次（visited），访问次数天然不超过 nodes.size
function nearestUserAncestor(nodes: Map<string, AnswerGraphNode>,
  target: AnswerGraphNode): AnswerGraphNode | null {
  const visited: Set<string> = new Set();
  let cursor: string | null = target.parentMessageId;
  while (cursor !== null) {
    if (cursor === '' || visited.has(cursor) || visited.size >= nodes.size) {
      throw new Error(BAD_GRAPH_TEXT);
    }
    const node: AnswerGraphNode | undefined = nodes.get(cursor);
    if (node === undefined) {
      throw new Error(BAD_GRAPH_TEXT);
    }
    visited.add(cursor);
    if (node.role === ROLE_USER) {
      return node;
    }
    cursor = node.parentMessageId;
  }
  return null;
}

// 分支路径还原（root→head 链序；空 head = 合法空分支回空表；缺父/环 = 坏图拒绝）
function branchPathOf(nodes: Map<string, AnswerGraphNode>,
  headId: string | null): AnswerGraphNode[] {
  const up: AnswerGraphNode[] = [];
  if (headId === null || headId === '') {
    return up;
  }
  const visited: Set<string> = new Set();
  let cursor: string | null = headId;
  while (cursor !== null) {
    if (cursor === '' || visited.has(cursor)) {
      throw new Error(BAD_GRAPH_TEXT);
    }
    const node: AnswerGraphNode | undefined = nodes.get(cursor);
    if (node === undefined) {
      throw new Error(BAD_GRAPH_TEXT);
    }
    visited.add(cursor);
    up.push(node);
    cursor = node.parentMessageId;
  }
  const out: AnswerGraphNode[] = [];
  for (let i: number = up.length - 1; i >= 0; i--) {
    out.push(up[i]);
  }
  return out;
}

// 区间末正文（该 U 之后、下一条 user 之前的最后一个 trim 非空 assistant 节点；'' = 无候选
// ——notice / tool / 空 assistant 都不是末正文；不含该 U 的路径回 '' 不参加归组）
function regionAnswerIdOf(path: AnswerGraphNode[], userId: string): string {
  let idx: number = -1;
  for (let i: number = 0; i < path.length; i++) {
    if (path[i].id === userId) {
      idx = i;
      break;
    }
  }
  if (idx < 0) {
    return '';
  }
  let answerId: string = '';
  for (let i: number = idx + 1; i < path.length; i++) {
    const node: AnswerGraphNode = path[i];
    if (node.role === ROLE_USER) {
      break; // 下一 user 不含
    }
    if (node.role === ROLE_ASSISTANT && node.content.trim() !== '') {
      answerId = node.id; // 末者胜出
    }
  }
  return answerId;
}
