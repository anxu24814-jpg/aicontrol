// 消息展示投影域（★ chart_display 成功调用**离开过程段**、单独成「图表」展示项——分组判据
// 新增一类断点，展示项第三类 = 图表独立项（kind = DISPLAY_KIND_CHART）；★ 2026-11-04 任务②
// 再增第四类 = 会话改动清单项（kind = DISPLAY_KIND_FILE_CHANGES，轮末合成卡，装配段见
// buildDisplayItems 后处理遍））。
// 域定义一句话：**源消息序列 → 展示项序列（正文独立项 / 过程段独立项 / 图表独立项 / 会话
// 改动清单项）的分组、轮事实归属标记与展示模式派生**——把「一条消息一行」升级为「正文一行、
// 连续过程步骤一段」，把轮语义（运行中 / 终态 / 等待用户处理）沉淀为可直跑的纯函数与纯派生入口。
// ★ 收束轮中间正文（2026-11-04）：轮已收束且无在途/等待步骤时，最后一条**非空** assistant
// 才是最终正文、仍独立成项；同轮其余非空 assistant 入相邻过程段（与思考/工具共用段级折叠）。
// 运行中正文、无终稿轮的正文一律不迁移——迁移门 = scan.settled && !scan.pendingStep。
// · 为什么新开本件（宪法「反碎片下限」三问）：①职责一句话 = 源消息→展示项的分组与身份映射；
//   ②不并入既有件——ChatMessageProjection 是「库行 → 视图消息」的映射（行→消息），本件是
//   「视图消息 → 展示项」的映射（消息→展示单元），两级各在一处不重叠；ChatDataSource 是容器
//   （tail/游标/通知/轮事实登记），分组与派生规则若塞进去会与容器语义互缠；③实逻辑非转接壳。
// · 依赖方向：本件 → ChatMessageCompose（视图模型 + 轮状态类型）与两个叶子域件
//  （ToolIds 工具名常量 / ToolChart 图表判据纯函数）单向；不 import 任何组件，
//   故可被断言脚本剥注解直跑（纯函数直跑面：updateSegmentPresentation / computeOpsHostIds /
//   buildDisplayItems / chartSpecOfMessage / alignRoundStartTimes / applyRoundModelLabels
//   ——后两条 = 轮级载荷（轮起始时刻/模型名）落到消息的写规则；chartSpecOfMessage = 图表
//   提升判据收口）。
// · 与 ChatDataSource 的分工：数据源持有展示项数组与轮事实表，每次结构变更后调用本件重建
//   （buildDisplayItems）、点击改意愿后调用本件重派生（updateSegmentPresentation）；本件
//   零状态（输入消息数组 + 旧展示项数组 + 轮事实表 → 新展示项数组）。
// · ★ 三条身份不得混用：回复轮（一次用户输入及其后续自动工具循环，id =
//   conversationId|runId）/ 过程段（轮内视觉连续的思考/工具/收束后中间正文步骤序列）/ 步骤
//   （一条可展示思考、工具或中间正文，持源消息身份）。轮事实由登记侧（实时
//   beginDisplayRound / 历史装配装配两路）写入
//   数据源，本件只消费，**不发明新 ID 当事实**；展示项身份由源消息 id 派生并在重建时复用对象，
//   键不随折叠/文本版本变化。
import { ChatMessage, DisplayRoundStatus, isStepAwaitingUser, isStepKind } from './ChatMessageCompose';
import { TOOL_CHART_DISPLAY } from '../../common/providers/ToolIds';
import { ChartSpecData, chartDisplaySpec } from '../../common/providers/ToolChart';
import { RoundFileChanges, deriveRoundFileChanges } from './ChatFileChangesModel';

// 展示项种类（渲染分派用；字符串常量单源，禁第二份字面量）
export const DISPLAY_KIND_MSG: string = 'msg';
export const DISPLAY_KIND_SEGMENT: string = 'segment';
// 图表独立项：chart_display 成功调用——载体 = 源工具消息引用，
// 渲染件 = ChatToolChartCard（正文流内），数据 = 装配期解析的 item.chartSpec
export const DISPLAY_KIND_CHART: string = 'chart';
// 会话改动清单项（任务②）：轮末合成卡——**无源消息载体（msg 恒 null）**，数据 = 装配期一次
// 算成的 item.fileChanges（deriveRoundFileChanges）；渲染件 = ChatFileChangesCard（U3）。
// 出卡门 = scan.settled（中断轮 error/stopped 自动出卡）；键 = 'fc-' + 轮 id
export const DISPLAY_KIND_FILE_CHANGES: string = 'fileChanges';
// 段键前缀（新建段的键 = 前缀 + 首步 id；复用段保留原键，键稳定优先于键语义）
const SEGMENT_KEY_PREFIX: string = 'seg-';
// 键冲突确定性后缀（候选键被占则依次尝试 ~1 / ~2……；禁随机数、时间或下标）
const SEGMENT_KEY_SUFFIX_SEP: string = '~';
// 折叠态保留的尾部步骤名额（默认仅显示最后两步）
export const SEGMENT_TAIL_VISIBLE: number = 2;

// ── 段展示模式三值（单源常量；渲染层的控制行/可见集合/摘要文案都由模式派生）──
// preview = 运行中默认（末两步 ∪ 等待项）；expanded = 手动展开（全部）；summary = 已收束
// 默认（只留等待项，其余折叠——「思考完成 / 处理完成」摘要条）
export const SEGMENT_MODE_PREVIEW: string = 'preview';
export const SEGMENT_MODE_EXPANDED: string = 'expanded';
export const SEGMENT_MODE_SUMMARY: string = 'summary';

// ── 轮事实（数据源登记与历史读缓存装配的公共形状）──
// id = conversationId + '|' + runId（整轮稳定身份，ChatSendCtrl.beginRunAcquire 所造）；
// status = 轮终态（running 只由本页已登记实时轮持有；历史读取的 finished/failed 映射
// done/error，其它一切值降级 unknown）；inputAnchorId = **已证明的输入身份**（实时首发 =
// user 内存 id，历史/精确重试 = 已解析图锚，缺省 ''）——它不是「凭列表最近 user 猜出的恢复
// 目标」，任何图操作仍走原 node 身份/解析链，禁把本字段直接传给 DB。
// ★ durationMs = 本轮**可信耗时**（毫秒）——由可信度纯函数
//（ChatAnswerChoice.trustedRoundDurationMs）判定后才写入；缺省 undefined =
// 无可信结束事实（显示面完全隐藏，不以 0 秒占位）。历史索引与实时回填两路同形
// ★ startMs = 本轮**起始时刻**（毫秒；口径 = 拍板「助手头时间 = 轮开始时刻」）：
// 来源 = generation_runs.createdAt（起轮时铸：prepareRun 普通轮
// = 派发 now〔与 user 行同值〕/ prepareRetryRun 重试轮 = 重试时刻〔与实时承载行同语义，
// 重试轮无归属自己的 user 行，故 user 行时刻方案覆盖不到、run 行才是各轮型统一事实〕/
// 主动消息轮 = 生成派发时刻）。undefined = 无 run 事实（缺行/索引未装）——回放侧保持库行
// 时刻（fail-open 不归一）。消费方 = 数据源安装口的 alignRoundStartTimes
export interface DisplayRoundFacts {
  id: string;
  status: DisplayRoundStatus;
  inputAnchorId: string;
  durationMs?: number;
  startMs?: number;
}

// ── 展示项（渲染单元）──
// kind = DISPLAY_KIND_MSG：单条非步骤消息（user / assistant 正文 / notice / summary / clear
// 等），msg = 源消息引用（**不复制文本为第二真源**）。
// kind = DISPLAY_KIND_SEGMENT：一个过程段，steps = 段内步骤源消息引用（顺序 = 消息顺序）；
// roundId / roundStatus = 段所属轮的展示事实（空 id / 无事实 = unknown）；manualExpanded =
// 段级手动意愿（页面内寿命：换会话/重进即由新数据源重建归零，不落库）；mode / visibleIndices /
// hiddenCount = 展示派生（唯一写点 updateSegmentPresentation，渲染件只消费）。
// kind = DISPLAY_KIND_CHART：正文图表项，msg = 源工具消息引用（kind =
// 'tool'、工具名 chart_display），chartSpec = 装配期按 chartSpecOfMessage 解析的图表视图
//（非空恒成立——判据不成立的消息不产本类项；渲染件直接消费，**不在构建函数内重解析**）。
// 重建（buildDisplayItems）复用旧展示项对象 ⇒ key 与 manualExpanded 一并延续：同段增量、
// 翻页补全、多旧段合并、旧段分裂都不会换键重置（任务书 §3.3-3/4/5）——图表项按源消息 id
// 同形复用（段成员与图表项类别不同即不复用，键随新对象）。
@Observed
export class ChatDisplayItem {
  key: string = '';
  kind: string = '';
  msg: ChatMessage | null = null;
  steps: ChatMessage[] = [];
  manualExpanded: boolean = false;
  roundId: string = '';
  roundStatus: DisplayRoundStatus = 'unknown';
  // 图表视图（仅 DISPLAY_KIND_CHART 消费；装配期一次算成——见 buildDisplayItems 装配段）
  chartSpec: ChartSpecData | null = null;
  // 会话改动清单（仅 DISPLAY_KIND_FILE_CHANGES 消费；装配期一次算成——轮内工具行内存现算，
  // 渲染件只消费，卡侧零聚合零缓存；统计口径单源 = ChatFileChangesModel 头注释）
  fileChanges: RoundFileChanges | null = null;
  // 清单卡展开意愿（页面内寿命：复用旧项延续、进会话新对象回默认 true——manualExpanded 同
  // 机制；经 @Observed 属性赋值驱动刷新，不进 LazyForEach 键）
  changesExpanded: boolean = true;
  // 本轮可信耗时（毫秒；undefined = 无可信值——摘要条不附耗时）。
  // ★ 真机报障修复：只在本轮**最后一个过程段**上给出（一轮一次；同轮其余过程段
  // 恒 undefined——重复同值会被读成每段各耗时）
  roundDurationMs: number | undefined = undefined;
  mode: string = SEGMENT_MODE_SUMMARY;
  visibleIndices: number[] = [];
  hiddenCount: number = 0;
  // 轮首标记：true = 本条（过程段）是本轮**首个上屏项**——
  // 轮头行（头像 + 模型名 + 时间）挂段顶渲染。与正文载体（ChatMessage.headHost）互斥：
  // 一轮只授位一处；值同不写（照 opsHost 同款全表刷新口径）。
  head: boolean = false;
}

// ── 展示模式与可见集合派生（纯入口，可直接直跑）──
// 模式优先级固定：manualExpanded → expanded；否则 roundStatus=running → preview；其它 → summary。
// 可见集合固定：expanded 全步骤；preview 为末两步并所有等待用户处理的步骤；summary 只保留等待
// 项。去重、按原序（下标升序遍历天然去重），hiddenCount = steps.length − visibleIndices.length。
// 组件点击只改 item.manualExpanded 后调用本入口重算，**不扫描业务活跃态**（等待判据单源 =
// isStepAwaitingUser）。
export function updateSegmentPresentation(item: ChatDisplayItem): void {
  let mode: string = SEGMENT_MODE_SUMMARY;
  if (item.manualExpanded) {
    mode = SEGMENT_MODE_EXPANDED;
  } else if (item.roundStatus === 'running') {
    mode = SEGMENT_MODE_PREVIEW;
  }
  const count: number = item.steps.length;
  const visible: number[] = [];
  if (mode === SEGMENT_MODE_EXPANDED) {
    for (let i = 0; i < count; i++) {
      visible.push(i);
    }
  } else {
    const tailStart: number = count - SEGMENT_TAIL_VISIBLE > 0 ?
      count - SEGMENT_TAIL_VISIBLE : 0;
    for (let i = 0; i < count; i++) {
      const awaiting: boolean = isStepAwaitingUser(item.steps[i]);
      if (mode === SEGMENT_MODE_SUMMARY) {
        if (awaiting) {
          visible.push(i);
        }
      } else if (awaiting || i >= tailStart) {
        visible.push(i);
      }
    }
  }
  item.mode = mode;
  item.visibleIndices = visible;
  item.hiddenCount = count - visible.length;
}

// ── 轮事实表规则（纯函数，可直接直跑；数据源持表并在调用处加销毁闸与通知）──
// 登记：非空 id 且尚未登记才建 running（同 id 重复调用**不把终态重置 running**——工具续轮
// 与异常路径会对同一轮多次「开始」，终态必须留得住）。inputAnchorId 为已证明的输入身份
//（实时首发 = user 内存 id；历史/精确重试 = 已解析图锚；无 = ''）。
export function registerDisplayRound(rounds: Map<string, DisplayRoundFacts>, roundId: string,
  inputAnchorId: string): void {
  if (roundId === '' || rounds.has(roundId)) {
    return;
  }
  const facts: DisplayRoundFacts = { id: roundId, status: 'running',
    inputAnchorId: inputAnchorId };
  rounds.set(roundId, facts);
}

// 结算：只允许**已登记且 running** 的轮转 done/error/stopped；空 id / 未登记 id / 已终态
// 一律不改（R1 迟到 settle 不会改写已终态，也不会碰 R2；历史批的 unknown 不被改写）。
export function settleDisplayRoundFacts(rounds: Map<string, DisplayRoundFacts>, roundId: string,
  status: string): void {
  if (roundId === '' || (status !== 'done' && status !== 'error' && status !== 'stopped')) {
    return;
  }
  const facts: DisplayRoundFacts | undefined = rounds.get(roundId);
  if (facts === undefined || facts.status !== 'running') {
    return;
  }
  facts.status = status as DisplayRoundStatus;
}

// 安装（历史装配批）：已存在项不覆盖——本页已装配的实时 running/终态优先于历史缓存
//（旧 running/unknown 不得覆盖 live 终态）；历史批之间同 id 重复（翻页与前批重叠）亦取先装者。
// ★ 已存在项仍不覆盖 status/inputAnchorId，
// 但耗时字段按保守规则补——仅当旧 facts 已终态（done/error/stopped）、旧 durationMs 缺失、
// 入参 durationMs 合法时才补该字段（running/unknown 不因历史安装得到耗时；已有合法值不覆盖，
// 防旧批反写）
export function installDisplayRoundFacts(rounds: Map<string, DisplayRoundFacts>,
  facts: DisplayRoundFacts[]): void {
  for (const fact of facts) {
    if (fact.id === '') {
      continue;
    }
    const existing: DisplayRoundFacts | undefined = rounds.get(fact.id);
    if (existing === undefined) {
      rounds.set(fact.id, fact);
      continue;
    }
    const terminal: boolean = existing.status === 'done' || existing.status === 'error' ||
      existing.status === 'stopped';
    const incomingOk: boolean = fact.durationMs !== undefined &&
      Number.isFinite(fact.durationMs) && (fact.durationMs as number) >= 0;
    if (terminal && existing.durationMs === undefined && incomingOk) {
      existing.durationMs = fact.durationMs;
    }
  }
}

// ── 回放轮起始时刻归一（纯函数可直接直跑）──
// 口径：回放侧助手侧消息（assistant/thinking/tool）的 createdAt 归一为**本轮起始时刻**
//（轮事实 startMs = generation_runs.createdAt）——与实时链同语义（占位行/思考行/工具行都在
// 派发时铸轮起始时刻）。不归一的三类：①user 行（自身库行时刻即其语义——用户时间行显示的
// 就是发送时刻；重试轮 user 行留原轮时刻亦正确：显示「你何时说的」）；②live 行（实时链自铸
// 即轮起始，归一意图只针对回放，显式跳过 = 意图声明）；③无 startMs 的轮（缺 run 事实）
// 保持库行时刻（= 节点提交时刻 ≈ 轮结束——fail-open，口径同修复前）。值同不写（防对已稳定
// 行发多余 @Observed 通知）。调用时机 = 数据源两安装口（rebuild/prepend），刷新投影之前
//——已上屏消息的归一在下次安装时同步补正（跨界轮：user 行随更早页到达、其已加载部分一并归一）。
// 连带面（injectTimeReminders）：归一后「距上一条消息」的游标基准由行提交时刻（≈轮结束）变
// 轮开始，与实时链（派发时刻即轮起始）同基准——仅影响「上一条为助手消息」时的间隔数值，
// 插入与否只在阈值边界带可能变化，语义 = 按真实活动时刻算，方向更准。
export function alignRoundStartTimes(msgs: ChatMessage[],
  rounds: Map<string, DisplayRoundFacts>): void {
  for (const m of msgs) {
    if (m.live === true || m.displayRoundId === '') {
      continue;
    }
    // serverstep（DS 服务端步骤行，S2⑤）属助手侧步骤——轮起始时刻归一同 thinking/tool
    if (m.kind !== 'assistant' && m.kind !== 'thinking' && m.kind !== 'tool' &&
      m.kind !== 'serverstep') {
      continue;
    }
    const facts: DisplayRoundFacts | undefined = rounds.get(m.displayRoundId);
    if (facts === undefined || facts.startMs === undefined) {
      continue;
    }
    if (m.createdAt === facts.startMs) {
      continue; // 值同不写
    }
    m.createdAt = facts.startMs;
  }
}

// ── 轮级模型名回填（两消费方 = 首载写全
// attachUsageMeta / 翻页补缺 backfillOlderRoundLabels）──
// 账本 modelId → 轮 id 映射（调用方组装）落到助手侧三类消息的 modelLabel（轮头行载荷——
// 轮首项可能落任一类载体上，故写全）。onlyMissing = true 只补空值（翻页补缺不得覆盖实时链
// 自铸值与前批已写值；首载 msgs 全新恒等价写全）。值同不写（同 alignRoundStartTimes）。
// 空映射零开销
export function applyRoundModelLabels(msgs: ChatMessage[], roundModel: Map<string, string>,
  onlyMissing: boolean): void {
  if (roundModel.size === 0) {
    return;
  }
  for (const m of msgs) {
    // serverstep 属助手侧步骤——轮级模型名回填同 thinking/tool（S2⑤ 行种随形）
    if (m.kind !== 'assistant' && m.kind !== 'thinking' && m.kind !== 'tool' &&
      m.kind !== 'serverstep') {
      continue;
    }
    if (onlyMissing && m.modelLabel !== undefined && m.modelLabel !== '') {
      continue;
    }
    const label: string = roundModel.get(m.displayRoundId) ?? '';
    if (label === '' || m.modelLabel === label) {
      continue; // 无归属轮 / 值同不写
    }
    m.modelLabel = label;
  }
}

// ── 轮区段扫描（内部单源；操作栏判据与「异常轮空正文状态尾项」判据同源）──
// 轮 = 一次用户输入及其后续自动工具循环（以 user 消息为起点；窗口首段不足一轮的「残缺前缀」
// 自成一个前缀轮，不猜归到最近 user）。区段判据：轮内消息的 displayRoundId（首条非空即轮身份，
// 同轮成员同 id）+ 数据源轮事实表。
// 收束判据（settled）三档：
//  · 有轮事实：running → 不收束（「生成中不把暂时最后一行认作最终回答」= 轮事实承载，含
//    全 streaming=false、无 tool 的暂空窗口）；终态（done/error/stopped）→ 收束；
//  · 无轮事实但含实时行（live）：保守不授操作资格（任务书 §3.3 末段——live 缺轮事实不得
//    伪造 done，接线缺失由断言暴露）；
//  · 无轮事实且全历史行：沿既有扫描判据（流式行在场或工具执行中/等待用户处理 → 不收束
//    ——历史 unknown 按「最后非空正文」选择承载，实际编辑/重试仍由 nodeId 与
//    ChatBranchPolicy 守卫）。
interface RoundScan {
  start: number;
  end: number;
  status: DisplayRoundStatus;
  settled: boolean;
  // 轮内存在等待用户处理或正在执行的工具步骤。终态事实分支只判 !streaming，故迁移中间正文
  // 须另查本字段（settled 单独不足以证明「无在途步骤」），computeOpsHostIds 语义不受影响。
  pendingStep: boolean;
  lastAssistantIndex: number;
  lastBodyId: string;
}

function scanRounds(msgs: ChatMessage[], awaiting: (m: ChatMessage) => boolean,
  rounds: Map<string, DisplayRoundFacts>): RoundScan[] {
  const out: RoundScan[] = [];
  const n: number = msgs.length;
  let start: number = 0;
  for (let i = 0; i <= n; i++) {
    if (i < n && msgs[i].kind !== 'user') {
      continue;
    }
    const scan: RoundScan = { start: start, end: i, status: 'unknown', settled: true,
      pendingStep: false, lastAssistantIndex: -1, lastBodyId: '' };
    let roundId: string = '';
    let hasLive: boolean = false;
    let streaming: boolean = false;
    for (let k = start; k < i; k++) {
      const m: ChatMessage = msgs[k];
      if (roundId === '' && m.displayRoundId !== '') {
        roundId = m.displayRoundId;
      }
      if (m.live === true) {
        hasLive = true;
      }
      if (m.streaming === true) {
        streaming = true;
      }
      // 未完成的工具步骤不判收束：等待用户处理（awaiting 回调）与**正在执行**（toolState 恒
      // 'running'）两态同拦（「生成中、等待工具/用户操作 → 不开放编辑/重试」）
      if (m.kind === 'tool' && (awaiting(m) || m.toolState === 'running')) {
        scan.pendingStep = true;
      }
      if (m.kind === 'assistant') {
        scan.lastAssistantIndex = k;
        if (m.text.trim() !== '') {
          scan.lastBodyId = m.id;
        }
      }
    }
    const facts: DisplayRoundFacts | undefined =
      roundId !== '' ? rounds.get(roundId) : undefined;
    if (facts !== undefined && facts.status === 'running') {
      scan.status = 'running';
      scan.settled = false;
    } else if (facts !== undefined) {
      scan.status = facts.status;
      scan.settled = !streaming;
    } else if (hasLive) {
      scan.settled = false;
    } else {
      scan.settled = !streaming && !scan.pendingStep;
    }
    out.push(scan);
    start = i + 1;
  }
  return out;
}

// ── 轮归属与最终正文标记（纯函数，可直接直跑）──
// 收束轮的最终正文 = 轮内**最后一条非空正文 assistant 行**（中途正文因此天然不获标记）；
// 收束轮的**空正文异常轮**（error/stopped）另授轮内最后一条 assistant 行承载恢复入口
// （非末条 = 轻量状态项 + 既有「更多」菜单 retryAt 链；末条 tail 行自带轻量尾部承载，
// 两者不重复——tail 行不在此授位）。返回需要挂消息级操作栏的消息 id 列表。
// awaiting 入参 = 过程步骤等待判据（调用方传 isStepAwaitingUser 结果），保持本函数零依赖。
export function computeOpsHostIds(msgs: ChatMessage[], awaiting: (m: ChatMessage) => boolean,
  rounds: Map<string, DisplayRoundFacts>): string[] {
  const out: string[] = [];
  const scans: RoundScan[] = scanRounds(msgs, awaiting, rounds);
  for (const scan of scans) {
    if (!scan.settled) {
      continue;
    }
    if (scan.lastBodyId !== '') {
      out.push(scan.lastBodyId);
      continue;
    }
    if (scan.lastAssistantIndex >= 0 && (scan.status === 'error' || scan.status === 'stopped')) {
      const last: ChatMessage = msgs[scan.lastAssistantIndex];
      if (last.tail !== true) {
        out.push(last.id);
      }
    }
  }
  return out;
}

// 展示序装订单元（buildDisplayItems 内部两用：段候选 / 单条消息项）；chart / chartSpec =
// 图表候选（仅 tool 行可命中——见 chartSpecOfMessage；命中即断段，装配阶段出图表独立项）
interface DisplayToken {
  segment: boolean;
  steps: ChatMessage[];
  msg: ChatMessage | null;
  chart: boolean;
  chartSpec: ChartSpecData | null;
}

// ── 图表提升判据（纯函数，可直接直跑）──
// 竞品同构（只采信机制）：消息分组器把「工具名为 chart_display 且
// 已执行成功」的工具调用**原地替换为正文图表卡并切断所在过程段**——数据源 = 工具入参 JSON
//（随消息落库，历史回放重解析重绘零迁移）。本函数 = 该判据的收口：行种（tool）+ 工具名
//（TOOL_CHART_DISPLAY）+ 就绪判据（回执 success ∧ 入参成图，本体单源 = ToolChart
// .chartDisplaySpec——与工具卡同一份 JSON 判法，禁第二处实现）。
// 返回 = 图表视图（非空即提升）；null = 留在过程段照常渲染步骤卡（失败调用留错误回执与原始
// 面板，不画半截图）。两问：合法调整判据内部实现不红（行为直跑守）；漏判（失败调用上屏成图 /
// 成功调用仍被折叠进段）红。
export function chartSpecOfMessage(msg: ChatMessage): ChartSpecData | null {
  if (msg.kind !== 'tool' || msg.toolName !== TOOL_CHART_DISPLAY) {
    return null;
  }
  return chartDisplaySpec(msg.toolInputJson ?? '', msg.toolOutputJson ?? '');
}

// ── 展示项重建（消息序列 + 旧展示项 + 轮事实表 → 新展示项）──
// 分组：连续步骤行（thinking/tool，及收束轮的中间正文 assistant）合成一个过程段——**步骤轮
// id 改变即断段**（含已知↔未知边界，防未知步骤吃到相邻轮状态；全未知连续步骤允许成段，状态
// 恒 unknown）；其余可展示消息各自成项。最终正文恒独立，运行中的正文恒独立。
// 可展示判据：**空正文且已收束的 assistant 行不进展示流**（「空正文不制造
// 步骤或断线」——它在请求历史与内存流中保留，仅不上屏）；流式中的空占位保留（生成中占位与
// 自动重试状态行的承载面）。★ 两处例外照进展示流：①**轮尾（tail 真）空正文行**——失败/中止
// 且本轮无正文时它是本轮唯一恢复入口的承载（ChatMessageItem 轻量状态尾部「提示 + 重试」）；
// ②**异常轮（error/stopped）最后一条空正文助手行**——历史较早轮失败时该行是「轻量状态项 +
// 更多菜单 retryAt 链」的唯一承载（按同一轮最后 assistant 保留一个状态尾项）。
// 身份与意愿（顺序固定）：
// 1. 先整体定格旧段快照（对象引用 / 键 / 成员 / manualExpanded / 旧序），禁边改旧段边算交集；
// 2. 生成候选分组（断段规则如上）；
// 3. 每个候选对**全部**有成员交集的旧段取 manualExpanded 的 OR（分裂的各子段都从同一份旧
//    快照继承意愿，不因第一子段消费旧对象而让第二段失忆）；
// 4. 对象复用另算：按新段顺序，取交集旧段中**旧序最早且尚未复用**的对象；旧对象最多用于
//    一个新段（合并不共用对象）；
// 5. 键：预先保留全部旧展示 key；新段候选键 = 前缀 + 首步 id，冲突则依次加确定性后缀直到
//    未占用；复用对象保留旧 key（不因状态/文案/首成员变化改键）；
// 6. 最后才写各对象 steps / roundId / roundStatus / manualExpanded，再调
//    updateSegmentPresentation 重算展示派生；没有已知 facts 时 roundStatus = unknown。
// ★ windowAtTop（缺省 false = 保守态）：窗口已知含会话起点
//（数据源 olderExhausted）——窗口首段非 user 起时也**不是**残缺前缀轮，轮首正常授位
//（主动消息会话首轮 = 首条即 assistant 的无 user 行轮，见下方轮首目标段注释）
export function buildDisplayItems(msgs: ChatMessage[], prev: ChatDisplayItem[],
  rounds: Map<string, DisplayRoundFacts>, windowAtTop: boolean = false): ChatDisplayItem[] {
  const awaiting = (m: ChatMessage): boolean => isStepAwaitingUser(m);
  // ── 1. 旧段快照与保留键集 ──
  const prevSegments: ChatDisplayItem[] = [];
  const prevByMemberId: Map<string, ChatDisplayItem> = new Map();
  // 旧清单卡按 key 入复用表（FILE_CHANGES 项 msg 恒 null，不入 prevByMemberId 两支——
  // 复用保 changesExpanded，见下方后处理遍）
  const prevFileChanges: Map<string, ChatDisplayItem> = new Map();
  const reservedKeys: Set<string> = new Set();
  for (const oldItem of prev) {
    reservedKeys.add(oldItem.key);
    if (oldItem.kind === DISPLAY_KIND_SEGMENT) {
      prevSegments.push(oldItem);
      for (const step of oldItem.steps) {
        prevByMemberId.set(step.id, oldItem);
      }
    } else if (oldItem.kind === DISPLAY_KIND_FILE_CHANGES) {
      prevFileChanges.set(oldItem.key, oldItem);
    } else if (oldItem.msg !== null) {
      prevByMemberId.set(oldItem.msg.id, oldItem);
    }
  }
  // ── 轮扫描（空正文异常轮的尾项判据与操作栏判据同源）──
  const scans: RoundScan[] = scanRounds(msgs, awaiting, rounds);
  // 中间正文 id 集（仅本次投影用，不写回消息、不落库、不进全局缓存）：只认「已收束且轮内
  // 无在途/等待步骤」的轮，且以最后一条非空 assistant 为最终正文；lastBodyId 为空的轮不折
  // 任何正文（无终稿时全部正文仍上屏，空正文状态行语义不变）。流式正文跳位与渲染器切换皆
  // 由该双闸挡住，运行中、工具在途、等待审批或作答时中间集恒不含本轮正文。
  const intermediateBodyIds: Set<string> = new Set();
  for (const scan of scans) {
    if (!scan.settled || scan.pendingStep || scan.lastBodyId === '') {
      continue;
    }
    for (let k = scan.start; k < scan.end; k++) {
      const m: ChatMessage = msgs[k];
      if (m.kind === 'assistant' && m.text.trim() !== '' && m.id !== scan.lastBodyId) {
        intermediateBodyIds.add(m.id);
      }
    }
  }
  const statusTailIds: Set<string> = new Set();
  for (const scan of scans) {
    if (scan.lastAssistantIndex >= 0 && scan.lastBodyId === '' &&
      (scan.status === 'error' || scan.status === 'stopped')) {
      statusTailIds.add(msgs[scan.lastAssistantIndex].id);
    }
  }
  // ── 轮首目标 ──
  // 每轮**首个上屏项**的源消息 id——「上屏判据」与下方 token 装配逐字同源（空正文已收束行
  // 不上屏；轮尾行与异常轮尾项行例外），且只认助手侧载荷（user/notice/summary/clear 不作
  // 轮首）。窗口首段不足一轮的残缺前缀轮不授位——其真正轮首在更早窗口，随翻页补全自然
  // 获得；loaded 窗以 user 起时首段扫描为空轮，无载荷天然跳过。
  // ★ 自检轮修复：残缺判据必须并上「窗口未到顶（windowAtTop 假）」——首元素非 user 仅是
  // **代理信号**，主动消息会话首条即 assistant（无 user 行），到顶全量窗首段是**完整轮**
  // 而非残缺前缀；只看元素 kind 会把它的轮首误判成残缺而永不授位。windowAtTop 缺省 false =
  // 保守不授位（未知态维持历史行为，防在真残缺窗上误授）
  const prefixScan: boolean = !windowAtTop && msgs.length > 0 && msgs[0].kind !== 'user';
  const headIds: Set<string> = new Set();
  for (let s = 0; s < scans.length; s++) {
    if (s === 0 && prefixScan) {
      continue;
    }
    const scan: RoundScan = scans[s];
    for (let k = scan.start; k < scan.end; k++) {
      const m: ChatMessage = msgs[k];
      // serverstep 属助手侧步骤——轮首候选同 thinking/tool（S2⑤ 行种随形）
      if (m.kind !== 'assistant' && m.kind !== 'thinking' && m.kind !== 'tool' &&
        m.kind !== 'serverstep') {
        continue;
      }
      if (m.kind === 'assistant' && m.streaming !== true && m.text.trim() === '' &&
        m.tail !== true && !statusTailIds.has(m.id)) {
        continue; // 与 token 装配同源：空正文已收束行不上屏（不占轮首）
      }
      headIds.add(m.id);
      break;
    }
  }
  // ── 2. 候选分组（沿原断段规则 + 步骤轮 id 改变即断段 + 图表提升断段）与展示序装订 ──
  // tokens 按消息序装订：段候选（连续步骤，含收束轮中间正文）与消息项、图表项交错，装配阶段
  // 照序消费。中间正文沿用源消息 id 作步骤身份，段键与复用链零改动。
  const tokens: DisplayToken[] = [];
  let pending: ChatMessage[] = [];
  let pendingRound: string = '';
  const flushSteps = (): void => {
    if (pending.length === 0) {
      return;
    }
    tokens.push({ segment: true, steps: pending, msg: null, chart: false, chartSpec: null });
    pending = [];
  };
  for (const msg of msgs) {
    // 空正文已收束行不上屏（不制造步骤、不断段）；轮尾行与异常轮尾项行例外
    if (msg.kind === 'assistant' && msg.streaming !== true && msg.text.trim() === '' &&
      msg.tail !== true && !statusTailIds.has(msg.id)) {
      continue;
    }
    if (isStepKind(msg.kind) || intermediateBodyIds.has(msg.id)) {
      // 图表提升：就绪的 chart_display 调用**断段**单独成项——先
      // flushSteps（前后步骤各成段，段内不再含本步 ⇒ 不双份），本消息不走 pending。
      // 中间正文非 tool 行，chartSpecOfMessage 恒回 null，仍走下面同一套 pending 分组。
      const spec: ChartSpecData | null = chartSpecOfMessage(msg);
      if (spec !== null) {
        flushSteps(); // 前后步骤各成段（pending 已空，后续步骤从新段开始）
        tokens.push({ segment: false, steps: [], msg: msg, chart: true, chartSpec: spec });
        continue;
      }
      const rid: string = msg.displayRoundId;
      if (pending.length > 0 && rid !== pendingRound) {
        flushSteps(); // 步骤轮 id 改变即断段（含已知↔未知边界）
      }
      pendingRound = rid;
      pending.push(msg);
      continue;
    }
    flushSteps(); // 非步骤行断段（空正文已收束行已在上面跳过——不断线）
    tokens.push({ segment: false, steps: [], msg: msg, chart: false, chartSpec: null });
  }
  flushSteps();
  // ── 3~6. 展示项装配（段、消息与图表三类按原序交错输出）──
  const consumed: Set<ChatDisplayItem> = new Set();
  const out: ChatDisplayItem[] = [];
  for (const token of tokens) {
    if (token.segment) {
      const steps: ChatMessage[] = token.steps;
      let manualExpanded: boolean = false;
      let reuseTarget: ChatDisplayItem | null = null;
      for (const oldSeg of prevSegments) {
        let hit: boolean = false;
        for (const step of steps) {
          if (prevByMemberId.get(step.id) === oldSeg) {
            hit = true;
            break;
          }
        }
        if (!hit) {
          continue;
        }
        if (oldSeg.manualExpanded) {
          manualExpanded = true; // 意愿 OR（全量交集面，任务书 §3.3-3）
        }
        if (reuseTarget === null && !consumed.has(oldSeg)) {
          reuseTarget = oldSeg; // 旧序最早且未复用（任务书 §3.3-4）
        }
      }
      let item: ChatDisplayItem;
      if (reuseTarget !== null) {
        consumed.add(reuseTarget);
        item = reuseTarget;
        item.manualExpanded = manualExpanded;
      } else {
        item = new ChatDisplayItem();
        item.kind = DISPLAY_KIND_SEGMENT;
        item.key = claimSegmentKey(SEGMENT_KEY_PREFIX + steps[0].id, reservedKeys);
        item.manualExpanded = manualExpanded;
      }
      item.steps = steps;
      item.roundId = steps[0].displayRoundId;
      const facts: DisplayRoundFacts | undefined =
        item.roundId !== '' ? rounds.get(item.roundId) : undefined;
      item.roundStatus = facts !== undefined ? facts.status : 'unknown';
      // 段级耗时先恒清空（复用对象残留防御；running/unknown 不因历史安装得到耗时）——
      // 本轮的耗时值在装配完成后**只回填本轮最后一个过程段**（单源见下方回填段）
      item.roundDurationMs = undefined;
      updateSegmentPresentation(item);
      out.push(item);
      continue;
    }
    // 图表项：与消息项同装配形（键 = 源消息 id、按 id 复用旧对象）；
    // 类别参与复用匹配——判据翻转（重放缺成功回执 / 本轮重发换参）时旧段成员或旧消息项不
    // 复用，键随新对象（段键前缀与消息 id 空间不同，不撞）
    if (token.chart) {
      const chartMsg: ChatMessage = token.msg as ChatMessage;
      const spec: ChartSpecData = token.chartSpec as ChartSpecData;
      let reusedChart: ChatDisplayItem | null = null;
      const chartHit: ChatDisplayItem | undefined = prevByMemberId.get(chartMsg.id);
      if (chartHit !== undefined && chartHit.kind === DISPLAY_KIND_CHART &&
        !consumed.has(chartHit)) {
        reusedChart = chartHit;
        consumed.add(chartHit);
      }
      if (reusedChart !== null) {
        reusedChart.msg = chartMsg;
        reusedChart.chartSpec = spec;
        out.push(reusedChart);
      } else {
        const item: ChatDisplayItem = new ChatDisplayItem();
        item.kind = DISPLAY_KIND_CHART;
        item.key = chartMsg.id;
        reservedKeys.add(item.key);
        item.msg = chartMsg;
        item.chartSpec = spec;
        out.push(item);
      }
      continue;
    }
    // 消息项：按 id 复用旧对象（键与顺序位置稳定）
    const msg: ChatMessage = token.msg as ChatMessage;
    let reusedMsg: ChatDisplayItem | null = null;
    const hit: ChatDisplayItem | undefined = prevByMemberId.get(msg.id);
    if (hit !== undefined && hit.kind === DISPLAY_KIND_MSG && !consumed.has(hit)) {
      reusedMsg = hit;
      consumed.add(hit);
    }
    if (reusedMsg !== null) {
      reusedMsg.msg = msg;
      out.push(reusedMsg);
    } else {
      const item: ChatDisplayItem = new ChatDisplayItem();
      item.kind = DISPLAY_KIND_MSG;
      item.key = msg.id;
      reservedKeys.add(item.key);
      item.msg = msg;
      out.push(item);
    }
  }
  // 轮耗时回填（唯一显示点 = 本轮**最后一个过程段**；真机报障改判——原实现同轮多段会重复
  // 渲染同一个数字，被读成「每段都花了这么多」。耗时属轮不属段：一轮只在本轮末尾那段摘要条
  // 上出现一次，其余段恒 undefined。判据 = 展示序（消息序）中该轮 id 最后一次出现的段项——
  // 窗口只含轮的后半时仍命中最末段，不发明第二处时间事实）
  const lastSegmentOfRound: Map<string, ChatDisplayItem> = new Map();
  for (const item of out) {
    if (item.kind === DISPLAY_KIND_SEGMENT && item.roundId !== '') {
      lastSegmentOfRound.set(item.roundId, item);
    }
  }
  lastSegmentOfRound.forEach((item: ChatDisplayItem, roundId: string): void => {
    const facts: DisplayRoundFacts | undefined = rounds.get(roundId);
    item.roundDurationMs = facts !== undefined ? facts.durationMs : undefined;
  });
  // ── 会话改动清单卡装配（任务② U2；轮末一张合成项，采 out 后处理遍、非 token 锚表装订）──
  // 出卡门 = scan.settled 统一判据：running / awaiting / tool 在途轮（settled=false）无卡；
  // 轮 settle——含 error/stopped 中断轮——出卡（中断前已执行完的工具改动是既成事实，settled
  // 终态判据自动覆盖，零新逻辑）。残缺前缀轮（s === 0 && prefixScan）不产卡——触顶翻页补全
  // 后自动产出。数据 = 装配期一次算成（deriveRoundFileChanges，卡侧零聚合零缓存）；null
  // （零改动轮 / 重试剔行后空轮）跳过——key 失配旧项不复用自动消失。插入位 = out 中该轮
  // **最后一个展示项**之后（判据 = item.roundId === rid〔segment / 前轮清单卡〕或
  // item.msg.displayRoundId === rid〔msg / chart〕）；rid 为空（无轮身份，空值会误配所有
  // 未挂轮项）或找不到该轮任何展示项 = 防御跳过。复用 = 键 'fc-' + rid 命中旧清单卡
  // （保 changesExpanded——manualExpanded 同机制，进会话新对象回默认）；键认领走
  // claimSegmentKey 防撞。U3 分派未落时本项为空壳行零高零渲染（下标参与索引，中间态）。
  for (let s = 0; s < scans.length; s++) {
    const scan: RoundScan = scans[s];
    if ((s === 0 && prefixScan) || !scan.settled) {
      continue;
    }
    let roundId: string = '';
    const roundToolRows: ChatMessage[] = [];
    for (let k = scan.start; k < scan.end; k++) {
      const m: ChatMessage = msgs[k];
      if (roundId === '' && m.displayRoundId !== '') {
        roundId = m.displayRoundId;
      }
      if (m.kind === 'tool') {
        roundToolRows.push(m);
      }
    }
    if (roundId === '') {
      continue;
    }
    const changes: RoundFileChanges | null = deriveRoundFileChanges(roundId, roundToolRows);
    if (changes === null) {
      continue;
    }
    let lastIdx: number = -1;
    for (let i = out.length - 1; i >= 0; i--) {
      const item: ChatDisplayItem = out[i];
      if (item.roundId === roundId ||
        (item.msg !== null && item.msg.displayRoundId === roundId)) {
        lastIdx = i;
        break;
      }
    }
    if (lastIdx < 0) {
      continue;
    }
    const baseFcKey: string = 'fc-' + roundId;
    const oldFc: ChatDisplayItem | undefined = prevFileChanges.get(baseFcKey);
    let fcItem: ChatDisplayItem;
    if (oldFc !== undefined && !consumed.has(oldFc)) {
      consumed.add(oldFc);
      fcItem = oldFc; // 复用旧对象：键与 changesExpanded 一并延续（新建对象回默认 true）
    } else {
      fcItem = new ChatDisplayItem();
      fcItem.kind = DISPLAY_KIND_FILE_CHANGES;
      fcItem.key = claimSegmentKey(baseFcKey, reservedKeys);
    }
    fcItem.msg = null;
    fcItem.roundId = roundId;
    fcItem.fileChanges = changes;
    out.splice(lastIdx + 1, 0, fcItem);
  }
  // 轮归属标记全表刷新（写入唯一处；值同不写——防对已稳定行发多余 @Observed 通知）
  const hostIds: string[] = computeOpsHostIds(msgs, awaiting, rounds);
  for (const msg of msgs) {
    const shouldHost: boolean = hostIds.indexOf(msg.id) >= 0;
    if ((msg.opsHost === true) !== shouldHost) {
      msg.opsHost = shouldHost;
    }
  }
  // 空轮性质标记全表刷新（写入唯一处；值同不写）——只标「会渲染
  // 轻量状态行」的行（空正文 + 已收束 + tail/opsHost，与 ChatMessageItem.statusLineVisible 同形；
  // 收束判据同源 scan.settled，防生成中暂空窗口被误标）。判据看**承接物**不看空不空：
  // 轮内有过程步骤且轮正常收束 = 'no-text'（工具有产出、只是没写正文——中性陈述）；
  // 异常轮（error/stopped）或整轮零产出 = 'no-reply'（沿用「没有产生回复」口径）。
  // 非状态行恒 ''（清旧值——上轮流式态写入的标记不跨收束残留）
  const emptyKindById: Map<string, string> = new Map();
  for (const scan of scans) {
    if (scan.lastAssistantIndex < 0 || !scan.settled) {
      continue;
    }
    const row: ChatMessage = msgs[scan.lastAssistantIndex];
    if (row.kind !== 'assistant' || row.streaming === true || row.text.trim() !== '' ||
      (row.tail !== true && row.opsHost !== true)) {
      continue;
    }
    let hasStep: boolean = false;
    for (let k = scan.start; k < scan.end; k++) {
      if (isStepKind(msgs[k].kind)) {
        hasStep = true;
        break;
      }
    }
    const abnormal: boolean = scan.status === 'error' || scan.status === 'stopped';
    emptyKindById.set(row.id, (!abnormal && hasStep) ? 'no-text' : 'no-reply');
  }
  for (const msg of msgs) {
    const emptyKind: string = emptyKindById.get(msg.id) ?? '';
    if ((msg.emptyRoundKind ?? '') !== emptyKind) {
      msg.emptyRoundKind = emptyKind;
    }
  }
  // 轮首标记全表刷新（写入唯一处；值同不写）——三个载体互斥：
  // 轮首项为步骤（其所在首段 steps[0]，含收束后中间正文）时写 item.head，为正文/状态行/图表项
  // （后两类持源消息引用，2026-10-15 U8c 期二图表项同走本支）时写 msg.headHost；渲染侧正文
  // 载体 = ChatMessageItem、图表载体 = ChatPageContent 图表分支，两处都按 head 标记挂轮头行。
  // 中间正文已由段承载，其源消息不得再持独立行 headHost（否则一轮两处轮头）
  for (const item of out) {
    let shouldHead: boolean = false;
    if (item.kind === DISPLAY_KIND_SEGMENT) {
      shouldHead = item.steps.length > 0 && headIds.has(item.steps[0].id);
    } else if (item.msg !== null) {
      shouldHead = headIds.has(item.msg.id);
    }
    if (item.head !== shouldHead) {
      item.head = shouldHead;
    }
  }
  for (const msg of msgs) {
    const shouldHead: boolean = headIds.has(msg.id) && msg.kind === 'assistant' &&
      !intermediateBodyIds.has(msg.id);
    if ((msg.headHost === true) !== shouldHead) {
      msg.headHost = shouldHead;
    }
  }
  return out;
}

// 段键认领（冲突则依次加确定性后缀 ~1 / ~2……直到未占用；对照旧 key 来源 id 恰好相等的
// 分裂段形态——另一段已复用旧对象保有原键，本段必需换键不撞）
function claimSegmentKey(base: string, used: Set<string>): string {
  if (!used.has(base)) {
    used.add(base);
    return base;
  }
  let n: number = 1;
  while (used.has(base + SEGMENT_KEY_SUFFIX_SEP + n)) {
    n++;
  }
  const key: string = base + SEGMENT_KEY_SUFFIX_SEP + n;
  used.add(key);
  return key;
}

// 段内等待标记（渲染侧判据兜底面——渲染件按 item.visibleIndices 直接消费，本函数供
// 需要逐项等待态的消费方/断言直读；与 updateSegmentPresentation 同源判据）
export function segmentAwaitingFlags(steps: ChatMessage[]): boolean[] {
  const flags: boolean[] = [];
  for (const step of steps) {
    flags.push(isStepAwaitingUser(step));
  }
  return flags;
}
