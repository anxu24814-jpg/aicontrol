// 流回调与轮次收尾域（域级最小拆分自 ChatSendCtrl，沿革见 ChatSendCtrl 头注释）。
// 域定义一句话：**协议流三类事件（增量/完成/失败）的处理与轮次收尾**——增量渲染（思考块
// 懒创建 / 节流有界前缀揭示）、工具轮判定与续转、轮级用量累积与上下文锚点、图会话终答
// 收尾落库与标题/建议触发。
// ★ 有界前缀平滑揭示（方案档 §0/§5，产品语义）：SSE 权威累积（assistantFull / thinkingFull）
//   与显示文本分离，发布侧每拍取有界前缀——单帧揭示量 ≤ 1.5 × 上帧、收尾 400ms 预算排空、
//   间隔 ≥ 67ms（ChatAppendThrottle 域钳制）；**终态 upsert 无条件立即全量对齐，不受平滑限制**。
// ★ 发布层冻结门（方案档 §6）：用户持阅读位（上滑退跟，判据经
//   refs.follow.userHoldsReadingPosition 只读透传自 ChatScrollOwnership 单源）期间抑制发布拍
//   ——权威累积照走、throttle 时钟照常调度；冻结时长有界（每满 FREEZE_FORCED_REVEAL_MS
//   强制一拍有界揭示）；终态 upsert 无条件穿透冻结。
// · 流式态五成员（activeStream / assistantFull / thinkingFull / liveAssistantId /
//   liveThinkingId）全数 private，写权限单源本域——域外只经意图方法（beginStreamRound /
//   clearRoundAccumulation / bindLiveAssistant / attachStream）与只读面（settlement 快照 +
//   get 前缀四法），五字段赋值形状只存在于本文件。
// · 宿主面 ChatFlowHost 六成员与五个域件引用（toolRound / keyRound / usageRound / autoRetry /
//   ctxCalc）构造期直注，引用恒就位。依赖纪律（零环红线，坑50）：本件禁 import ChatSendCtrl
//   的运行时符号——唯一例外 = ChatSendRefs 类型随形（type-only，编译期擦除无运行时环）。
// · 消费方 = ChatSendCtrl（唯一）；failRound / createNativeStream 经宿主同名薄委托转接。
// · 停止键语义红线：onStreamDone 收尾即置空 activeStream 与退避期置空（onStreamError）两处
//   口径不变——停止键落 abortActiveStream 的 else 分支即时收尾，无「点了没反应」死键窗口；
//   收尾排空窗口（done 已到、drain 在途）内点停止按排空语义收尾（轮落 done），不落 error。
import { AiChatMessage, AiConnection, AiToolCall, AiUsageDelta, ChatStream,
  ENDPOINT_RESPONSES } from '../../common/providers/AiTypes';
import { addServerToolUse, SseDelta, SseServerToolEvent } from '../../common/providers/SseParser';
import { createChatStream } from '../../common/providers/ChatStreamFactory';
import { hilog } from '@kit.PerformanceAnalysisKit';
// DS 服务端工具流域判据（S2⑤：步骤行名/态提取与 serverstep 合成单源——禁散写协议字面量）
import { isDsInputRiskMessage, isDsToolConflictMessage, serverCallKeyOf,
  serverStepNameOf, serverStepStateOf } from '../../common/providers/DsServerTools';
import { nextMessageId } from '../../common/store/ChatDb';
import { queryRunRowById } from '../../common/store/SessionTraceDb';
import { TraceRunIn } from '../../common/chat/SessionTraceModel';
import { trustedRoundDurationMs } from '../../common/chat/ChatAnswerChoice';
import { ANSWER_VERSIONS_DIRTY_TICK_KEY } from './ChatAnswerCtrl';
import { CHAT_STREAM_TRACE_ENABLED, ChatStreamTrace } from './ChatStreamTrace';
// 二期 S3 拆分件：服务端工具步骤域（serverstep 行 + 列载荷快照 + Responses item 累积）
import { ChatServerStepCtrl } from './ChatServerStepCtrl';
import { DisplayRoundFacts } from './ChatDisplayProjection';
import { ChatDataSource } from './ChatDataSource';
import { ChatMessage, newChatMessage, noticeActionOf } from './ChatMessageCompose';
import { ChatAppendThrottle } from './ChatAppendThrottle';
import { ChatDisplayBudget } from '../../common/chat/ChatDisplayBudget';
import { ChatSendRefs } from './ChatSendCtrl';
import { ChatKeyRoundCtrl } from './ChatKeyRoundCtrl';
import { ChatToolRoundCtrl } from './ChatToolRoundCtrl';
import { ChatUsageRoundCtrl, RoundUsageValues } from './ChatUsageRoundCtrl';
import { ChatAutoRetryCtrl } from './ChatAutoRetryCtrl';
import { ChatContextUsageCalc } from './ChatContextUsage';
import { ChatStreamCheckpoint, CheckpointSnapshot } from './ChatStreamCheckpoint';
// 后台回复通知账本（finishStream 终态上报——完成/中断/停止三类各走各的通知语义；零环）
import { chatBgReply } from '../../common/chat/ChatBgReply';
import { GraphRunHandle, GraphNodeRef } from '../../common/chat/ChatGraphCommandSource';
import { ChatGraphWriteCtrl, GraphFinishInput } from './ChatGraphWriteCtrl';
// 二期 S2：DS 流式扩展字段收尾消费（标题写库 + 拒答处置）——新域独立成件，本件只薄接线
import {
  ChatDsStreamExtrasCtrl, DS_IMAGE_REFUSAL_TEXT, DS_INPUT_RISK_TEXT, DS_REFUSAL_TEXT,
  DS_TOOL_DROP_TEXT
} from './ChatDsStreamExtrasCtrl';
// 二期 S4 #11：file_id 失效自愈域（整轮附件重传 + 同 key 重发；本件只留分流两行）
import { ChatFileRetryCtrl } from './ChatFileRetryCtrl';
// 二期 #10：续写端点不可用一次判定（叶子件；404/端点不存在即隐藏键，不做长期探测）
import { CONTINUE_UNREACHABLE_TEXT, isContinueUnsupportedError,
  markContinueUnsupported } from '../../common/chat/ChatContinueSupport';
// run 终态常量（finishStream 三态分流——值域单源在 MessageBranchDb 词表）
import { RUN_STATUS_FINISHED, RUN_STATUS_FAILED, RUN_STATUS_STOPPED,
  RUN_STATUS_INTERRUPTED } from '../../common/store/MessageBranchDb';
import { generateTitleForConversation } from '../../common/TitleGen';
import { generateSuggestForMessage } from '../../common/SuggestGen';
// web 会话列表失效旁路（叶子登记钩——零 import 中枢防模块环；未登记/零订阅者 no-op）
import { publishChatLiveInvalidate } from '../../common/chat/ChatLiveSink';

// 失败切换资格的 HTTP 状态码：401/403/429 = key 级失败；网络错误无状态码不切、5xx 不切
//（服务端失败换 key 无益，归自动重试域同 key 重发）
const RETRY_STATUSES: number[] = [401, 403, 429];

// ── 有界前缀揭示参数（方案 §5；档位值参照竞品 KEL 实测）──
// 界公式三条（§0）：①单帧揭示量 ≤ 1.5 × 上帧（移动平均防单拍跳变）；②收尾 drain 400ms
// 预算排空（不一次性甩出，显示滞留硬上限）；③揭示间隔 ≥ 67ms（ChatAppendThrottle 域钳制）。
// 终态 upsert 无条件立即全量对齐，不受平滑限制。
const REVEAL_MIN_CHARS: number = 2;        // 单拍揭示量下限（防阶梯自锁停滞）
const REVEAL_BASE_CHARS: number = 40;      // 基准步长初值（由 ChatDisplayBudget.stepHint 速率调节）
const REVEAL_MAX_CHARS: number = 240;      // 基准步长上界（解析成本极低时封顶）
const REVEAL_GROWTH_FACTOR: number = 1.5;  // 单帧揭示量硬上界系数（≤ 1.5 × 上拍揭示量）
// 无预算通道行（思考行）基准步长：纯 Text 零解析成本，取与揭示域上界同档的固定值——与
// REVEAL_MAX_CHARS 无联动义务（上调上界时本值无须跟随，字面两处 240 非手工同步关系），外层
// Math.min(REVEAL_MAX_CHARS,·) 恒钳安全向（有预算通道的 assistant 行不取此值——成本反馈
// 缺席即无反馈可等的单一判别源）
const THINKING_REVEAL_BASE_CHARS: number = 240;
const REVEAL_DRAIN_BUDGET_MS: number = 400; // 收尾排空时间预算（预算尽强制终态全量对齐）
const FREEZE_FORCED_REVEAL_MS: number = 5000; // 冻结强制揭示周期：连续冻结每满此界强制一拍
// 有界揭示并重置计时——防长回看 + 长生成叠加后解冻时一次性大揭示

// 宿主面（流回调域拆分件接口）：运行隔离态与图写侧的到达口
export interface ChatFlowHost {
  // 宿主销毁闸（isRoundAlive 消费——与 ChatRetryHost.isDisposed 同源同值）
  isDisposed(): boolean;
  // 当前 run 身份令牌（createNativeStream 发起一刻快照——V2/V3 迟到回调拦截）
  currentRunToken(): string;
  // 当前 attemptId（createNativeStream 快照 + finishStream 账本归属快照）
  currentAttemptId(): string;
  // 释放运行占用（finishStream 轮收尾——先失效后释放的「释放」点）
  releaseRun(): void;
  // 图会话写侧句柄快照（finishStream 收尾身份——releaseRun 清空前取值）
  graphHandleSnapshot(): GraphRunHandle | null;
  // 图轮收尾委托（终答节点提交 + run 终态 + 账本一体——编排体在 ChatGraphWriteCtrl）
  graphFinishRound(input: GraphFinishInput): Promise<GraphNodeRef | null>;
  // 占位行两到达口（薄委托 ChatGraphWriteCtrl，照 graphFinishRound 同形——本件不直持写侧）
  commitStreamPlaceholder(content: string, reasoning: string): Promise<string>;
  checkpointStreamPlaceholder(nodeId: string, content: string,
    reasoning: string): Promise<boolean>;
}

// ★ U1 web 直播中枢旁路契约（施工总案 §2.3）：本件**不 import 中枢**（防反向依赖零环）——
// 旁路出口以本接口注入（ChatLiveHub lazy attach 装配 / setLiveTap(null) 摘除成对释放）；
// null = 零订阅者全程 no-op。负载 = 权威累积全文（整段替换模型）+ 四态终态语义
//（done/stopped/error/interrupted）
export interface ChatStreamLiveTap {
  // 增量旁路：当前轮权威累积全文一跳（发布时点 = 增量回调出口，身份快照已滤旧轮）
  onLiveDelta(fullText: string, reasoning: string): void;
  // 终态旁路：轮终态语义 + 最终全文（发布时点 = finishStream 入口快照区）
  onLiveRoundEnd(status: string, fullText: string, reasoning: string): void;
}

// 轮次结算快照：settleRoundAssistant 等收尾消费方一次取齐六值，只读结构（值拷贝语义，
// 禁当写通道）。checkpointNodeId = 本轮流中占位行节点 id（'' = 无占位行——零增量轮/
// 开关关闭/落行失败）；工具轮中间行收口经它走「更新既有占位行」路径。
// serverToolsJson = 本 assistant 轮的 DeepSeek 服务端工具原样串（S2⑥——末帧合体串或以
// 已到事件组装的部分结构；'' = 本轮无服务端步骤），中间轮收口挂 assistantMsg.serverToolsJson
export interface StreamSettlement {
  liveAssistantId: string;
  liveThinkingId: string;
  assistantFull: string;
  thinkingFull: string;
  checkpointNodeId: string;
  serverToolsJson: string;
}

export class ChatStreamFlowCtrl {
  private refs: ChatSendRefs;
  private host: ChatFlowHost;
  // 五个域件引用（构造期直注——宿主构造序末位创建本件，调用时刻恒已就位）
  private toolRound: ChatToolRoundCtrl;
  private keyRound: ChatKeyRoundCtrl;
  private usageRound: ChatUsageRoundCtrl;
  private autoRetry: ChatAutoRetryCtrl;
  private ctxCalc: ChatContextUsageCalc;
  // DS 流式扩展字段收尾消费（二期 S2；标题与拒答两件合成一件，见该件头注释）
  private dsExtras: ChatDsStreamExtrasCtrl = new ChatDsStreamExtrasCtrl();
  // file_id 自愈（二期 #11；懒构造——闭包读本件 refs/keyRound，构造期 this 时序不作假设）
  private fileRetry: ChatFileRetryCtrl | null = null;
  // ── 流式运行时态（全数 private，写权限单源本域，域外只经下方意图方法与只读面到达）──
  private activeStream: ChatStream | null = null;
  // 流式权威全量累积（本回合进行中消息）
  private assistantFull: string = '';
  private thinkingFull: string = '';
  private liveAssistantId: string = '';
  private liveThinkingId: string = '';
  private appendThrottle: ChatAppendThrottle | null = null;
  // ── 服务端工具步骤域（二期 S3 拆分件：DS serverstep 行与列载荷快照整体在彼件）──
  private serverStep: ChatServerStepCtrl = new ChatServerStepCtrl();
  // 续写轮承载节点 id（二期 S4 #10；'' = 非续写轮）。非空 = 收尾提交走「更新既有答案节点」
  // 路径（同一 messageId 原地追加，不插新行），与占位行 settle 的节点 id 二选一
  private continueNodeId: string = '';
  // ── 有界前缀揭示状态──显示文本 = 权威累积的有界前缀，每 frameId 一组三值（已揭示长度 /
  // 上拍揭示量 / 基准步长移动平均），正文与思考行同口径、同一发布路径（flushFrame），不另开
  // 第二套。清理点 = 轮首 / 续轮 / 真全量重建（全经 resetAppendBuffer 同拍清）+ 终态 drop
  // 单行清 + 运行态回收点整面清，防跨轮残留；★ U9 起「离页」清点退役——退页不断流，三 Map
  // 保留值即重进重挂的续流初值（读口 = getRevealLen；重进不跳变不重播的判据面）──
  private revealLen: Map<string, number> = new Map();
  private revealLastStep: Map<string, number> = new Map();
  private revealBase: Map<string, number> = new Map();
  private drainDeadline: number = -1;     // 收尾排空预算期限（Date.now() 绝对值；-1 = 不在排空中）
  private drainFinishStatus: string = ''; // 排空完成后落终态的语义标签（现仅 'done' 路径排空）
  // 冻结期计时：本冻结期首拍时刻（-1 = 不在冻结期）；解冻与揭示状态整面清同点复位——
  // 连续冻结「每满 FREEZE_FORCED_REVEAL_MS 强制一拍」的周期锚
  private freezeStartAt: number = -1;
  // 流式 DB checkpoint 域：250ms latest-wins 占位行落库与增量排水——与上方 appendThrottle
  //（UI 揭示节流）互不合并各自独立；宿主面三口经本类闭包实现（snapshot 现读权威串 / 落行
  // 与增量写经 host 薄委托 ChatGraphWriteCtrl）
  private checkpoint: ChatStreamCheckpoint;
  // 直播中枢旁路出口（null = 零订阅者 no-op；见 ChatStreamLiveTap 契约注释；零 import 中枢）
  private liveTap: ChatStreamLiveTap | null = null;

  constructor(refs: ChatSendRefs, host: ChatFlowHost, toolRound: ChatToolRoundCtrl,
    keyRound: ChatKeyRoundCtrl, usageRound: ChatUsageRoundCtrl, autoRetry: ChatAutoRetryCtrl,
    ctxCalc: ChatContextUsageCalc) {
    this.refs = refs;
    this.host = host;
    this.toolRound = toolRound;
    this.keyRound = keyRound;
    this.usageRound = usageRound;
    this.autoRetry = autoRetry;
    this.ctxCalc = ctxCalc;
    this.checkpoint = new ChatStreamCheckpoint(
      (): CheckpointSnapshot => ({ content: this.assistantFull, reasoning: this.thinkingFull }),
      (content: string, reasoning: string): Promise<string> =>
        this.host.commitStreamPlaceholder(content, reasoning),
      (nodeId: string, content: string, reasoning: string): Promise<boolean> =>
        this.host.checkpointStreamPlaceholder(nodeId, content, reasoning));
  }

  // file_id 自愈域懒构造（照节流器先例）
  private fileRetryCtrl(): ChatFileRetryCtrl {
    if (this.fileRetry === null) {
      this.fileRetry = new ChatFileRetryCtrl({
        conversationId: (): string => this.refs.conversationId(),
        liveConn: (): AiConnection | null => this.keyRound.currentConn(),
        roundHistory: (): AiChatMessage[] => this.keyRound.currentHistory(),
        attemptCurrent: (): void => this.keyRound.attemptCurrent(),
        failRound: (message: string, status: number): void => this.failRound(message, status),
        toast: (message: string): void => this.refs.toast(message)
      });
    }
    return this.fileRetry;
  }

  // 节流器懒构造（flush 回调需绑 this——属性初始化期 this 时序不作假设，首用即建）。
  // 公开 = ChatHostAccess throttleDrop 闭包经此消费（工具轮 drop 通道）；步长自由度由
  // flushFrame 直接读 msg.displayBudget.stepHint；返回值 = 权威累积长度（供节流分档）
  throttle(): ChatAppendThrottle {
    if (this.appendThrottle === null) {
      this.appendThrottle = new ChatAppendThrottle(
        (frameId: string, delta: string): number => this.flushFrame(frameId, delta));
    }
    return this.appendThrottle;
  }

  // 节流缓冲复位：全量重建链（ChatPageLoad.loadHistory → dataSource.rebuildFromHistory）前
  // 清缓冲 + 档位回快档——否则旧窗口增量在新数据源上空转且慢档惯性带进下一次首刷。
  // **懒构造不因复位建实例**（null = 本页从未流过流，无缓冲可清）。会话切换不走本方法：
  // 会话 = 新页面实例，节流器随 ChatPage 重建（见 ChatAppendThrottle 类头注释）。
  // 揭示状态整面清挂本点——轮首 / 续轮 / 全量重建三点全经此处同拍清。★ U9 清理契约：
  // **「离页」清点退役**——退页不断流（运行时空闲回收是 disposeActiveStream 唯一到达口），
  // 页面侧重挂路径（ChatPageLoadCtrl.remountLive）刻意绕开本方法——三 Map 保留值即重挂
  // 续流初值（重进不跳变〔全量揭示〕不重播〔从零揭示〕）
  resetAppendBuffer(): void {
    this.clearRevealState();
    if (this.appendThrottle !== null) {
      this.appendThrottle.reset();
    }
  }

  // ── 流式态意图级操作与只读面（写面全集 = 下面四个意图方法，域外禁直写字段——ArkTS
  // private 编译错兜底）──

  // 开始一轮流式（初发与重试共用）：绑定承载行 id 并同拍清思考行 id 与两全量累积串——
  //「绑新 id 必同拍清」配对约束由本方法体实现；同拍复位 checkpoint 域（上一轮占位行登记
  // 作废，本轮占位行待首笔增量经 250ms 节流落库）
  beginStreamRound(liveAssistantId: string): void {
    this.resetAppendBuffer();
    this.checkpoint.beginRound();
    this.liveAssistantId = liveAssistantId;
    if (CHAT_STREAM_TRACE_ENABLED) {
      ChatStreamTrace.begin(this.refs.dataSource.findMessage(liveAssistantId)?.bodyBindingId ?? '');
    }
    this.liveThinkingId = '';
    this.assistantFull = '';
    this.thinkingFull = '';
    this.continueNodeId = '';
    this.clearServerToolState();
    // 自愈次数随轮复位（「绑新轮必同拍清」配对约束：上一轮重传计数不带进新一轮）
    if (this.fileRetry !== null) {
      this.fileRetry.reset();
    }
  }

  // 续写轮起点（二期 #10）：绑既有答案行 + **以已展示正文为累积初值**（新内容接在尾部，
  // 收尾全量覆盖即「原地追加」）；承载节点 id 同时登记给收尾提交路径。与 beginStreamRound
  // 同一套清点，只在末步回填两值
  beginContinueRound(msgId: string, prefixText: string, nodeId: string): void {
    this.beginStreamRound(msgId);
    // ★ 承载行置 streaming 真（自检轮修）：flushFrame 以 msg.streaming 为投递闸，首版只有
    // 发送/重试/续轮路径置真——续写窗正文整段不上屏（气泡冻结在前缀，收尾一次性跳变）。
    // 置真点放本处而非 ChatSendCtrl：本件无硬线压力，宿主件只许减行
    const target: ChatMessage | null = this.refs.dataSource.findMessage(msgId);
    if (target !== null) {
      target.streaming = true;
    }
    this.assistantFull = prefixText;
    this.continueNodeId = nodeId;
  }

  // 续写轮判据（收尾/错误分支用：'' = 非续写轮）
  continueNode(): string {
    return this.continueNodeId;
  }

  // 工具续轮受控动作一（startNextAssistantRound 轮首）：清两全量累积串与思考行 id——
  // 正文行 id 不在此清（占位行 push 后才经 bindLiveAssistant 绑新 id，时序冻结）。
  // S2⑤：服务端工具流域态同拍清（续轮 = 新 assistant 轮，服务端步骤按轮归属——中间轮
  // 已由 settleRoundAssistant 快照落列，终态不再串写）
  clearRoundAccumulation(): void {
    this.resetAppendBuffer();
    this.assistantFull = '';
    this.thinkingFull = '';
    this.liveThinkingId = '';
    this.clearServerToolState();
  }

  // 工具续轮受控动作二：绑定续轮占位行 id（在占位行入数据源之后调用）。续轮换承载行 =
  // 新占位行周期——同拍复位 checkpoint 域（上一中间轮占位行已由 settleRoundAssistant 收口）
  bindLiveAssistant(id: string): void {
    this.checkpoint.beginRound();
    this.liveAssistantId = id;
    if (CHAT_STREAM_TRACE_ENABLED) {
      ChatStreamTrace.begin(this.refs.dataSource.findMessage(id)?.bodyBindingId ?? '');
    }
  }

  // 资源交接（Key 池域起流登记 / 切 key 清引用——null = 流终态清引用，语义红线见
  // ChatKeyRoundCtrl 头注释）。流域内终态置空四点（onStreamDone / onStreamError 接管 /
  // finishStream / disposeActiveStream）不经此，保持原样
  attachStream(stream: ChatStream | null): void {
    this.activeStream = stream;
  }

  // 直播中枢旁路注入口：tap 装配/摘除由 ChatLiveHub lazy attach 与 unwire 成对驱动，
  // 本域零装配逻辑；注入后增量/终态两挂点随增量逐跳发布，null 期全程 no-op
  setLiveTap(tap: ChatStreamLiveTap | null): void {
    this.liveTap = tap;
  }

  // 只读结算快照（settleRoundAssistant 消费）：方法开头一次取齐六值（收尾方法内无中途
  // 写点，快照时机不引入语义差）；checkpointNodeId 同拍取；serverToolsJson = 服务端工具
  // 快照（末帧合体串或部分结构，'' = 本轮无——S2⑥）
  settlement(): StreamSettlement {
    return {
      liveAssistantId: this.liveAssistantId,
      liveThinkingId: this.liveThinkingId,
      assistantFull: this.assistantFull,
      thinkingFull: this.thinkingFull,
      checkpointNodeId: this.checkpoint.currentNodeId(),
      serverToolsJson: this.serverToolsSnapshot()
    };
  }

  // ── DeepSeek 服务端工具流域处理（S2⑤⑥，写权限单源本域）──

  // 流域态清点（beginStreamRound 轮首 / clearRoundAccumulation 续轮两处同拍调——「绑新轮
  // 必同拍清」配对约束，与两全量累积串同纪律；实现在 ChatServerStepCtrl.reset）
  private clearServerToolState(): void {
    this.serverStep.reset();
  }

  // 服务端工具快照（薄委托：组装与部分结构全在 ChatServerStepCtrl）
  private serverToolsSnapshot(): string {
    const connAtSnapshot: AiConnection | null = this.keyRound.currentConn();
    return this.serverStep.snapshot(connAtSnapshot !== null &&
      connAtSnapshot.endpoint === ENDPOINT_RESPONSES);
  }

  // 服务端工具事件与末帧（薄委托：行合成/更新与列载荷组装全在 ChatServerStepCtrl）
  private onServerToolEvent(ev: SseServerToolEvent): void {
    this.serverStep.noteEvent(ev, this.liveAssistantId, this.refs.dataSource);
  }

  private onServerToolTail(callsJson: string | undefined, annotationsJson: string | undefined): void {
    this.serverStep.noteTail(callsJson, annotationsJson);
  }

  // 只读 getter 四法（单值读点消费——ChatHostAccess 闭包与 setRetryHint 取占位行 id）
  getLiveAssistantId(): string {
    return this.liveAssistantId;
  }

  // 揭示长度公开读口（U9 新增）：某 frameId 的已揭示长度（无记录 = 0）。语义面 =
  //「重进不清 reveal」契约的可观测断言口（三 Map 保留值即续流初值；本口供域外读证
  // 初值对齐，写面仍私有）
  getRevealLen(frameId: string): number {
    return this.revealLen.get(frameId) ?? 0;
  }

  getLiveThinkingId(): string {
    return this.liveThinkingId;
  }

  getAssistantFull(): string {
    return this.assistantFull;
  }

  getThinkingFull(): string {
    return this.thinkingFull;
  }

  // ── 原生协议流构造（唯一流工厂；三协议工厂分发，回调统一回本域出口）──
  // onDone 四参：usage = 本流归一用量（流内已 take-max；null = 无 usage 帧/失败流）、
  // truncated = 本流是否被输出上限截断、firstTokenMs = 本流首字耗时毫秒（0 = 未产出正文/
  // 思考增量，口径见 AiTypes.AiStreamHandlers 第四参注释）
  createNativeStream(conn: AiConnection): ChatStream {
    // 身份快照随流闭包：发起一刻的 (run 令牌, attempt 身份)——回调到达时与当前活跃比对
    //（isRoundAlive）：旧 run 迟到回调不借新轮 sending 通过（V2），同 run 旧 attempt 迟到
    // 不切 key 不重发不收尾（V3）。停止主路径不在本口失效：abort 不预释放，收尾
    //（failRound → finishStream）先于释放完成，token 在场放行
    const roundToken: string = this.host.currentRunToken();
    const attemptId: string = this.host.currentAttemptId();
    return createChatStream(conn.protocol, conn.endpoint, {
      onDelta: (delta: SseDelta): void => {
        if (!this.isRoundAlive(roundToken, attemptId)) {
          return;
        }
        this.onStreamDelta(delta);
        // 直播旁路（增量挂点）：onStreamDelta 后权威累积已含本帧，旁路一跳喂当前累积全文
        //（整段替换模型）；纯旁路不改既有控制流，null = no-op
        const liveTap: ChatStreamLiveTap | null = this.liveTap;
        if (liveTap !== null) {
          liveTap.onLiveDelta(this.assistantFull, this.thinkingFull);
        }
      },
      onDone: (usage: AiUsageDelta | null, durationMs: number, truncated: boolean,
        firstTokenMs: number): void => {
        if (!this.isRoundAlive(roundToken, attemptId)) {
          return;
        }
        this.onStreamDone(usage, durationMs, truncated, firstTokenMs);
      },
      onError: (message: string, status: number, sawContent: boolean): void => {
        if (!this.isRoundAlive(roundToken, attemptId)) {
          return;
        }
        this.onStreamError(message, status, sawContent);
      }
    });
  }

  // 流回调身份核验（V2/V3）：回调闭包发起时快照与当前活跃比对——旧 run 迟到回调不借新轮
  // sending 通过；同 run 旧 attempt 迟到不切 key 不重发不收尾
  private isRoundAlive(token: string, attemptId: string): boolean {
    return !this.host.isDisposed() && token !== '' && token === this.host.currentRunToken() &&
      attemptId !== '' && attemptId === this.host.currentAttemptId();
  }

  // 最终失败呈报（notice 气泡可见 + 落库 error，不静默）；工具挂起交互一并兜底取消
  //（ask_user 挂起等答时的停止/失败路径防悬挂）；兼 ChatKeyRoundHost.failRound 实现体与
  // 中止卡落库漏斗（时机约束见 abortRoundPending 头注释）。status 分类单源 noticeActionOf：
  // 401/403 挂 'provider'（跳服务商管理页）、-1 挂 'network'（跳网络设置页）、其余（429/5xx/
  // -2/0）不设字段 notice 保持纯文本不可点。取值表：Key 池打尽传 roundLastStatus、手动停止
  // 传 0 **禁传 -1**（手动停止不是网络失败，传 -1 会误挂跳网络设置页动作）
  failRound(message: string, status: number): void {
    // 轮终清掉自愈退避定时器（自检轮补）：退避窗内停止/最终失败后不再跑旧轮重传链
    //（链路自身 attemptCurrent 有令牌闸，这里省的是白跑的上传 IO）
    if (this.fileRetry !== null) {
      this.fileRetry.reset();
    }
    this.toolRound.abortRoundPending(this.refs.conversationId());
    const notice: ChatMessage = newChatMessage(nextMessageId('notice'), 'notice', message, '', '', 'error');
    const action: string = noticeActionOf(status);
    if (action !== '') {
      notice.noticeAction = action;
    }
    this.refs.dataSource.push(notice);
    this.finishStream('error');
  }

  // 停止键的流侧支（宿主保留 markUserStop / httpAbortRun 前两段，流侧判段在此）：退避期的
  // activeStream 已被自动重试分支置空（见 onStreamError），故停止键落 else 分支即时收尾
  //（notice 行 + 输入栏回可发送态）——不是「点了没反应」
  abortActiveStream(): void {
    if (this.activeStream !== null) {
      this.activeStream.abort();
    } else if (this.refs.sending()) {
      // ★ 红队二轮缺陷1：收尾排空窗口（done 已到、drain 在途——activeStream 已置空而
      // sending 仍真）点停止——流已成功、权威累积已完整，按排空语义即时收尾：轮落 done
      //（落库诊断空、标题与建议照常触发），不推「已手动停止」notice。判据 = 排空态在场
      //（drainDeadline ≥ 0）；非 drain 窗口的停止语义不变（下方 failRound 原样）
      if (this.drainDeadline >= 0 && this.drainFinishStatus !== '') {
        const status: string = this.drainFinishStatus;
        this.drainDeadline = -1;
        this.drainFinishStatus = '';
        this.finishStream(status);
        return;
      }
      // 第二参传 0（无码哨值——notice 纯文本；★ 禁传 -1：手动停止不是网络失败，传 -1 会
      // 误挂跳网络设置页动作）
      this.failRound('已手动停止', 0);
    }
  }

  // 运行态回收点的流侧收尾（红线：解绑回调防销毁后触 UI）。唯一调用方 = 运行时空闲回收
  //（ChatSessionRuntime.reclaim，此刻恒无在途生成），退页不再到达本方法。DB 残留 streaming
  // 占位行由 sweepStaleGraphRuns 清算接管：run→interrupted + 占位行→done（半截成终答）
  // + 诊断合成料，重进以「已中断 + 半截内容」呈现
  disposeActiveStream(): void {
    this.resetAppendBuffer();
    this.checkpoint.beginRound(); // 停 checkpoint 排水（在途写由命令层守卫丢弃）；占位行留库待清算
    if (this.activeStream !== null) {
      this.activeStream.disposeSilent();
      this.activeStream = null;
    }
  }

  // 后台超时兜底收口（短时任务超时前约 6 秒系统回调触发，链路 = chatBgReply.onTimeout →
  // 运行时 interruptActiveForTimeout → 本口）：只走已在库的收口链——checkpoint 半截已在库
  //（250ms）+ 本轮终态 interrupted + 诊断 notice，不另开落库路径。排空窗口按排空语义即时
  // 收尾（流已成功落 done，照 abortActiveStream 同款判据）；在途流静默掐断（disposeSilent
  // 不触发回调，回调本也会被 finishStream 的 releaseRun 令牌失效拦下）
  interruptForTimeout(): void {
    if (this.drainDeadline >= 0 && this.drainFinishStatus !== '') {
      const status: string = this.drainFinishStatus;
      this.drainDeadline = -1;
      this.drainFinishStatus = '';
      this.finishStream(status);
      return;
    }
    if (this.activeStream !== null) {
      this.activeStream.disposeSilent();
      this.activeStream = null;
    }
    this.finishStream('interrupted');
  }

  private onStreamDelta(delta: SseDelta): void {
    ChatStreamTrace.recv(delta.content.length);
    // DS 扩展字段记录（一期 S2 薄接线①）：标题 / 拒答 / 图片拦截三键——只记录不写库，
    // 收尾统一消费；非 DS 流三键缺席 = 本行零开销
    this.dsExtras.noteDelta(delta);
    // Responses 完整 output 快照（二期 S3）：终止事件携带，后到覆盖（唯一来源 = 最后一条
    // completed/incomplete 帧）
    if (delta.responsesOutputJson !== undefined && delta.responsesOutputJson !== '') {
      this.serverStep.noteResponsesOutput(delta.responsesOutputJson);
    }
    // 自动重试状态行让位：有内容上屏即撤下状态行——它只属于「还没有任何产出」那段窗口
    this.autoRetry.clearHintIfShown();
    // 工具调用增量喂聚合器（与正文/思考增量互不干扰；无工具帧零开销——聚合域在 ChatToolRoundCtrl）
    if (delta.toolCalls !== undefined && delta.toolCalls.length > 0) {
      this.toolRound.feedToolCalls(delta.toolCalls);
    }
    // reasoning item 捕获：同 id 后到覆盖（done 终值盖 added）
    if (delta.reasoningItems !== undefined) {
      this.toolRound.captureReasoningItems(delta.reasoningItems);
    }
    // DeepSeek 服务端工具路由（S2⑤）：事件 → serverstep 行合成/更新；末帧两字段 → 流域态
    // 与合体串（两者与正文/思考增量互不干扰；非 DS 流字段缺席零开销）
    if (delta.serverToolEvent !== undefined) {
      this.onServerToolEvent(delta.serverToolEvent);
    }
    if (delta.serverToolCallsJson !== undefined || delta.annotationsJson !== undefined) {
      this.onServerToolTail(delta.serverToolCallsJson, delta.annotationsJson);
    }
    if (delta.reasoningContent !== '') {
      this.thinkingFull += delta.reasoningContent;
      if (this.liveThinkingId === '') {
        // 思考块懒创建（无 reasoning_content 的 provider 永不创建 = 自动隐藏），插在助手
        // 占位气泡之前（思考在回答上方）；★ 回传契约：linkId = liveAssistantId（发送组装
        // 时依此把思考并回 assistant 消息的 reasoning）
        const thinkingMsg: ChatMessage = newChatMessage(nextMessageId('think'), 'thinking', '');
        thinkingMsg.linkId = this.liveAssistantId;
        // 思考行继承精确 owner（当前正文占位行）的轮归属——插入前落值，首帧即属本轮
        //（段分组按轮 id 断段，缺此则思考与相邻轮步骤混段）
        this.refs.dataSource.bindDisplayMember(thinkingMsg, this.liveAssistantId);
        // 生成中标记（思考折叠块的「折叠显 3 行预览」态判据，与正文行 streaming 同字段两
        // kind 共用）：建行即置真（插入前落值，首帧就是折叠高，不闪 0 高再撑开）
        thinkingMsg.streaming = true;
        // 轮级载荷继承（轮起始时刻与轮级模型名）：思考行是轮内首个上屏项时轮头行取本行
        // 载荷——两值都从本轮正文占位行现读（同轮同刻）。模型名漏写即轮头行落到会话级
        // 兜底，切换模型后旧轮头会漂成新模型
        const ownerMsg: ChatMessage | null = this.refs.dataSource.findMessage(this.liveAssistantId);
        if (ownerMsg !== null) {
          if (ownerMsg.createdAt !== undefined) {
            thinkingMsg.createdAt = ownerMsg.createdAt;
          }
          if (ownerMsg.modelLabel !== undefined) {
            thinkingMsg.modelLabel = ownerMsg.modelLabel;
          }
        }
        // 思考行与正文行的邻接关系由展示投影按消息顺序分组；插入点仍为「正文行之前」
        //（insertBefore 触发展示项重建）
        this.refs.dataSource.insertBefore(this.liveAssistantId, thinkingMsg);
        this.liveThinkingId = thinkingMsg.id;
      }
      this.throttle().enqueue(this.liveThinkingId, delta.reasoningContent);
      // DB checkpoint 登记（同步栈只置脏起定时——恒零 DB；250ms 后 latest-wins 排水）
      this.checkpoint.markDirty();
    }
    if (delta.content !== '') {
      this.assistantFull += delta.content;
      this.throttle().enqueue(this.liveAssistantId, delta.content);
      this.checkpoint.markDirty();
    }
  }

  private onStreamDone(usage: AiUsageDelta | null, durationMs: number, truncated: boolean,
    firstTokenMs: number): void {
    // 流已终态——引用即刻置空（旧实现留着 finished 流对象使工具轮执行期停止键静默失效）
    this.activeStream = null;
    // 轮级累积（本域唯一接线点）：用量四值跨流求和 / 截断末流胜出 / 首字首个非 0 胜出——
    // 三条口径全在 ChatUsageRoundCtrl 域头注释（禁在本域重写口径）
    this.usageRound.accumulateStream(usage, durationMs, truncated, firstTokenMs);
    if (usage !== null) {
      // ★ 上下文锚点与 k 校准——**两口径并存**（Open WebUI #29064「有意求和」先例，禁后人
      //「统一」）：上方整轮累积器 = 工具轮 N 流跨流求和（计费口径——N 轮工具后约为真实规模
      // 的 N 倍，拿它当上下文规模必放大显示）；锚点 = 本流 promptTokens（含全部历史 + 提示词
      // + 工具定义 + 工具结果 = 当前上下文规模的真度量），工具轮多次 onStreamDone 后者覆盖
      // 前者 = **最后一次流胜出**；只认 input 侧字段（totalTokens 不可靠）；k = 锚点 ÷ 本流
      // 估算，钳制后按模型落偏好键
      const anchorConn: AiConnection | null = this.keyRound.currentConn();
      if (usage.promptTokens > 0 && anchorConn !== null) {
        this.ctxCalc.recordAnchor(usage.promptTokens, anchorConn);
      }
    } else {
      // 用量诊断留档：流正常结束但全程未收到 usage 帧——官方直连四方言均应有（仅
      // completion 需端侧响应 stream_options.include_usage；中转网关静默忽略该键即此形态；
      // 已修形态「usage 挂末内容帧」见 SseParser）。warn 只带协议/模型，不含内容与密钥
      const diagConn: AiConnection | null = this.keyRound.currentConn();
      hilog.warn(0x0001, 'ChatSend', '用量诊断：本流未收到 usage 帧（协议 %{public}s，模型 %{public}s）',
        diagConn !== null ? diagConn.protocol : 'unknown',
        diagConn !== null ? diagConn.model : 'unknown');
    }
    // 工具调用轮判定：聚合出完整调用且本轮带工具声明且未到轮上限 → 进入工具执行轮（结果
    // 回传后续请求）；否则按既有单轮收尾。到上限后的多余调用不静默吞：notice 一行说明
    //「为何停」；首次触顶给模型一轮「知情收尾」（被丢弃的调用以合成工具结果回传，见
    // grantLimitGrace），让位轮后仍触顶才直接收尾
    const calls: AiToolCall[] = this.toolRound.pendingCalls();
    if (calls.length > 0 && this.toolRound.hasDeclarations() && this.toolRound.hasBudget()) {
      this.toolRound.beginToolRound(calls);
      return;
    }
    if (calls.length > 0 && this.toolRound.hasDeclarations() &&
      this.toolRound.canGrantLimitGrace()) {
      // notice 只落首次触顶（让位轮后仍触顶 = 说明已在屏上，不重复落行）；数字取本轮
      // 生效上限（0 = 不限制时即内置硬顶 256，与实际闸门同源）
      this.refs.dataSource.push(newChatMessage(nextMessageId('notice'), 'notice',
        '工具调用已达 ' + this.toolRound.roundLimit() + ' 轮上限，已停止执行后续调用'));
      this.toolRound.grantLimitGrace(calls);
      return;
    }
    this.toolRound.noticeForUndeclaredCalls(calls); // 幻觉调用兜底（零声明落 notice，不续轮）
    // DS 输出侧拒答（二期 #6）：回答被内容安全过滤 → 走 error 收尾（撤正文、改显拒答文案、
    // 落失败轮可重试），与续写判据互斥。不走排空（正文将被撤下，排空无意义）
    if (this.dsExtras.isFiltered()) {
      this.finishStream('error');
      return;
    }
    // 收尾排空（方案 §5.5）：有揭示积压时沿节流时钟多跑几拍有界揭示再落终态（入口最多
    // 后移 REVEAL_DRAIN_BUDGET_MS）；无积压立即收尾。工具轮 / 让位轮两 return 路径不经此
    //——中间行走 settleRoundAssistant 即时全量
    if (!this.beginDisplayDrain('done')) {
      this.finishStream('done');
    }
  }

  private onStreamError(message: string, status: number, sawContent: boolean): void {
    // key 级失败（401/403/429）且池内还有未试 key → 静默切换重发（本条错误不上屏）；
    // 其余失败归下方自动重试域判（状态码族 -1/5xx ∪ 瞬态文案面），不接管的 = 最终失败。
    // 重发必然零增量（非 200 无流，状态码先于 body），占位气泡与库行原样复用
    if (RETRY_STATUSES.includes(status) && this.keyRound.tryNextKey(message, status)) {
      return;
    }
    // DS 工具共存自适应（二期 S3 / §1-7）：400 + 本流零产出 + 错误体提到工具冲突 → 剔除
    // 客户端 function 工具同 key 重发一次（只一次；仍失败原样透传走下面的失败收尾）。
    // ★ 自检轮补：任务书要求「在该轮标注工具已停用」——首版只剔不标，用户看本轮回复时
    // 不知道客户端工具当轮失效；notice 一次性（clientToolsDropped 单次闸保证不重复）
    if (status === 400 && !sawContent && isDsToolConflictMessage(message) &&
      this.keyRound.retryWithoutClientTools()) {
      this.refs.dataSource.push(newChatMessage(nextMessageId('notice'), 'notice',
        DS_TOOL_DROP_TEXT));
      this.activeStream = null;
      return;
    }
    // DS 输入侧内容安全拦截（二期 #6 / §6-S2 验收⑤）：400 Content Exists Risk = 输入被拦，
    // 不当网络失败、不切 key、不自动重试（输入不改重试必然同错）。只出一条可改可重发的
    // 提示行，轮次照常收尾（输入框与附件由发送链既有草稿态保留，失败路径不清待发引用）
    if (status === 400 && !sawContent && isDsInputRiskMessage(message)) {
      this.failRound(DS_INPUT_RISK_TEXT, 400);
      return;
    }
    // DS file_id 失效自愈（二期 #11）：400 + 零产出 + 错误体说文件失效 → 整轮附件重传后
    // 同 key 重发（上限 2 次；期间本条失败不上屏，超限/重传失败原样透传走下方最终失败）
    if (this.fileRetryCtrl().takeOver(status, sawContent, message)) {
      this.activeStream = null;
      return;
    }
    // 自动重试域接管点（判据与退避调度全在 ChatAutoRetryCtrl，本处只接线）：传输层失败
    //（-1）、服务端 5xx 或瞬态文案命中且本流零产出且非用户停止且开关开且次数未尽 → 退避
    // 重发同请求，本条失败不上屏、不 failRound（notice 行与收尾都留给最终失败）
    if (this.autoRetry.takeOver(status, sawContent, message)) {
      // ★★ 退避期必须置空流引用（最易漏且后果最重）：漏做 = 用户在这几秒点停止会落进
      // abortActiveStream 分支，而该流已 finished（fail 首行守卫吞掉调用）→ 停止键死键、
      // 轮次既不收尾也不重发。照 onStreamDone 与 tryNextKey 同法（流已终态，引用不再有用）
      this.activeStream = null;
      return;
    }
    // 续写端点不可用（二期 #10）：404/405/端点不存在 → 一次判定即隐藏键并提示，照常失败
    // 收尾（承载节点已重开为 streaming，收尾写回前缀正文，不丢已展示内容）
    if (this.continueNodeId !== '' && isContinueUnsupportedError(status, message)) {
      markContinueUnsupported();
      this.refs.toast(CONTINUE_UNREACHABLE_TEXT);
    }
    // 生成中点停止的主路径 = ChatSendCtrl.abort → 流内 onError('已手动停止', -1) 到达本函数
    //——与「网络失败」同码，noticeActionOf 按 -1 会误挂跳网络设置页动作（「手动停止传 0
    // 禁传 -1」哨值补上主路径）。非停止轮照传 status——真传输层 -1 挂 network 动作仍是正确语义
    this.failRound(this.autoRetry.decorateFinalMessage(message),
      this.autoRetry.isUserStopped() ? 0 : status);
  }

  // 流式收尾（done/error/interrupted 统一）：未刷增量丢弃 + 全量覆盖 + 一次性落库 + 状态复位
  private finishStream(status: string): void {
    const assistantMsgId: string = this.liveAssistantId;
    // 轮身份与终态分类在**入口快照**：roundId 取 currentRunToken（此时 releaseRun 未跑、
    // token 在场；禁按 liveAssistantId 反查——它可能已被工具续答换过）；停止标记须在
    // resetForRound（清标记）之前读。'interrupted' 入参 = 后台超时兜底专属（非用户停止、非
    // 失败，roundStatusAtFinish 类同 stopped 归「已停止」面：显示轮事实只有 done/stopped/
    // error 三值域，run 层走 RUN_STATUS_INTERRUPTED，重进按 interrupted→stopped 映射显示）
    // DS 输出侧拒答（二期 #6）：撤正文 + 改显拒答文案 + 落库正文空（失败轮）。判据来源 =
    // 本轮流内 finish_reason=content_filter（ChatDsStreamExtrasCtrl 记录）
    const refused: boolean = this.dsExtras.isFiltered();
    const roundIdAtFinish: string = this.host.currentRunToken();
    const roundStatusAtFinish: string =
      status === 'done' ? 'done' : (status === 'interrupted' ? 'stopped' :
        (this.autoRetry.isUserStopped() ? 'stopped' : 'error'));
    // 直播旁路（终态挂点）：入口快照区一跳 publish round_end——信封四态保真（done/interrupted
    // 直取入参；error 路径按用户停止分流 stopped/error，区别于显示口径「interrupted 归
    // stopped」，信封保 interrupted 真值）。纯旁路不改既有语句与时序；null = no-op
    const liveTap: ChatStreamLiveTap | null = this.liveTap;
    if (liveTap !== null) {
      liveTap.onLiveRoundEnd(
        status === 'done' ? 'done' : (status === 'interrupted' ? 'interrupted' :
          (this.autoRetry.isUserStopped() ? 'stopped' : 'error')),
        this.assistantFull, this.thinkingFull);
    }
    // 终态入口快照回写运行态内存（lastSettleCause 真值面挂 ChatSessionRuntime——队列惰性
    // 终态门读内存快照、禁直查 DB：终态落库在下方异步链之后，假沿时必陈旧；写口可选位——
    // 直跑夹具 refs 未接时空转）
    if (this.refs.setLastSettleCause !== undefined) {
      this.refs.setLastSettleCause(roundStatusAtFinish);
    }
    // 用量快照（五值全部局部快照前置：①roundConn 在下方收尾区置 null；②收尾落库异步完成
    // 后才落账本，彼时用户可能已开新一轮发送（累积器被清零重计）——局部值杜绝错位）
    const settleConn: AiConnection | null = this.keyRound.currentConn();
    const usageProviderId: string = settleConn !== null ? settleConn.providerId : '';
    const usageModelId: string = settleConn !== null ? settleConn.model : '';
    // 轮级用量快照取自 ChatUsageRoundCtrl.values（快照语义见该件注释）
    const roundUsage: RoundUsageValues = this.usageRound.values();
    const usagePrompt: number = roundUsage.prompt;
    const usageCompletion: number = roundUsage.completion;
    const usageDurationMs: number = roundUsage.durationMs;
    const usageCached: number = roundUsage.cached;
    const usageFirstTokenMs: number = roundUsage.firstTokenMs;
    this.throttle().drop(assistantMsgId);
    this.dropRevealFrame(assistantMsgId);
    if (this.liveThinkingId !== '') {
      this.throttle().drop(this.liveThinkingId);
      this.dropRevealFrame(this.liveThinkingId);
    }
    // 排空态与冻结计时随终态落定一并清除（终态写无条件全量对齐不受排空/平滑限制——§5.6
    // 红线；冻结计时属揭示派生态，终态落定即复位）
    this.drainDeadline = -1;
    this.drainFinishStatus = '';
    this.freezeStartAt = -1;
    const assistantMsg: ChatMessage | null = this.refs.dataSource.findMessage(assistantMsgId);
    // ★ 工具轮间隙重复提交防线（方案 §2.3 修复）：工具轮间隙（本轮 assistant 行已经
    // settleRoundAssistant 结算落库，clearRoundAccumulation 只在 startNextAssistantRound 才清）
    // 停止/失败时，assistantFull 仍持上一轮全文，finishStream 会把它再提交一个终答节点
    //（形态 user → A1 → T1(中止) → A1'，重进该轮正文显示两遍）。判据 = 承载行已非流式
    //（settle 是唯一在 finishStream 前置 streaming=false 的写点）——命中则终答节点提交空
    // 内容（run 终态与账本照常收口；空正文节点投影不渲染，上文已由工具轮收尾保全）
    const settledInToolGap: boolean = assistantMsg !== null && assistantMsg.streaming !== true;
    // 服务端工具快照（S2⑥）：末帧合体串或以已到事件组装的部分结构（失败/中止轮屏显与库
    // 一致——任务书 S2⑥）；'' = 本轮无服务端步骤。工具轮间隙轮（承载行已结算）不重写——
    // 中间轮快照已随 settleRoundAssistant 落列，本拍写会覆盖错轮数据
    const serverToolsAtFinish: string = settledInToolGap ? '' : this.serverToolsSnapshot();
    // 工具窗占位行收口：停止/失败落于工具执行窗时（承载行已 settle = 工具轮间隙终态），
    // 提前 push 的下一轮占位行仍在场——整行弹出（removeMessageIds，防「置假保留」的双
    // 状态行）。正常续轮/终轮路径占位行已被 startNextAssistantRound 复用（字段已清），
    // 此调用幂等零动作。工具报错不收轮（error 回执照常续轮复用），不经此处
    if (settledInToolGap) {
      this.toolRound.retractPendingPlaceholder();
    }
    // 占位行收口交接：停 checkpoint 排水并取占位行节点 id（'' = 无占位行——零增量轮/开关
    // 关闭，收口走插行老路）；工具轮间隙形态下旧占位行已随 settleRoundAssistant 收口，settle
    // 可能仍返回旧行 id——更新路径会因守卫谓词落空被拒，故该形态显式取 '' 走空内容节点提交路
    const placeholderSettled: string = this.checkpoint.settle();
    // 续写轮优先：提交目标 = 既有答案节点（同一 messageId 原地追加）；否则照占位行口径
    const placeholderAtFinish: string = this.continueNodeId !== '' ? this.continueNodeId
      : (settledInToolGap ? '' : placeholderSettled);
    if (assistantMsg !== null) {
      // 拒答轮：撤下已流式展示的正文，改显拒答文案（官方要求「删除已展示的回答」）；
      // 正常运行轮照旧全量对齐
      assistantMsg.text = refused ? DS_REFUSAL_TEXT : this.assistantFull;
      // 底栏两判据收口（done/error 两路都经此——失败与手动停止轮同样获得底栏，拍板 2a）：
      // streaming 置假出底栏；tail 置真出重试键（failRound 的 notice 行先 push 清过 tail，
      // 此处置回——本条终为末条助手消息）
      assistantMsg.streaming = false;
      assistantMsg.tail = true;
      // 服务端工具原样串挂载（S2⑥，与 streaming/tail 同段「本轮收口态」）：非空才挂
      //（undefined = 非官方档轮/无服务端步骤——零噪声口径）；失败/中止轮同挂部分结构
      if (serverToolsAtFinish !== '') {
        assistantMsg.serverToolsJson = serverToolsAtFinish;
      }
      // 截断尾注挂载：与 streaming/tail 同段（同属「本轮收口态」）
      assistantMsg.truncated = roundUsage.truncated;
      // 用量 meta 行数据挂载（中断轮也挂——账本 error 轮同落，回放链按 messageId 命中即挂、
      // 无从区分中断轮，实时不挂重启即显，两链必须同口径）。工具轮中间行天然无（中间行走
      // beginToolRound 收尾不经此；字段 undefined 即不渲染）
      if (usagePrompt > 0 || usageCompletion > 0) {
        // 续写跨轮「两轮和」（决明 2026-11-14 拍板，2164 节）：同一 messageId 的第二段用量
        // 与既有展示值相加——账本仍是每轮一行（费用两笔不重复），气泡显示整条答案的合计；
        // 首字耗时是时点量不累加（保留第一段的值）
        const continuing: boolean = this.continueNodeId !== '';
        const baseTokens: number = continuing ? (assistantMsg.usageTokens ?? 0) : 0;
        const baseCompletion: number = continuing ? (assistantMsg.usageCompletionTokens ?? 0) : 0;
        const baseCached: number = continuing ? (assistantMsg.usageCachedTokens ?? 0) : 0;
        const baseDuration: number = continuing ? (assistantMsg.usageDurationMs ?? 0) : 0;
        assistantMsg.usageTokens = baseTokens + usagePrompt + usageCompletion;
        assistantMsg.usageCompletionTokens = baseCompletion + usageCompletion;
        assistantMsg.usageDurationMs = baseDuration + usageDurationMs;
        // 首字耗时：>0 才挂（undefined 即不渲染——零噪声口径）。与 usage 四值同块 ⇒ 同受
        //「usage > 0」守卫：无 usage 帧的流连「用时」都不显示，首字同族不单飞
        if (usageFirstTokenMs > 0 &&
          (!continuing || assistantMsg.usageFirstTokenMs === undefined)) {
          assistantMsg.usageFirstTokenMs = usageFirstTokenMs;
        }
        // 缓存命中段：>0 才挂（undefined 即不渲染——无缓存协议/短对话零噪声；输入数已含
        // 命中部分，段只是标注）；续写轮与既有值相加
        if (usageCached > 0) {
          assistantMsg.usageCachedTokens = baseCached + usageCached;
        }
      }
      // 官方服务端工具计次（二期 #7）：本轮有计次才挂（undefined = 非 DS 轮/未用工具，
      // 用量气泡三行不出现）；同值随 GraphFinishInput 进账本（重进会话靠账本重建）。
      // 续写轮与既有计次相加（两轮和口径，与 token 同族）
      if (roundUsage.serverToolUse !== undefined) {
        assistantMsg.serverToolUse = this.continueNodeId !== '' ?
          addServerToolUse(assistantMsg.serverToolUse, roundUsage.serverToolUse) :
          roundUsage.serverToolUse;
      }
    }
    if (this.liveThinkingId !== '') {
      const thinkingMsg: ChatMessage | null = this.refs.dataSource.findMessage(this.liveThinkingId);
      if (thinkingMsg !== null) {
        thinkingMsg.text = this.thinkingFull;
        // 思考行收口：流结束 = 本条已完成——折叠态收拢（组件侧见 streaming 真→假的 @Watch）；
        // done/error 两路都经此（停止与失败轮同按已结束处理）
        thinkingMsg.streaming = false;
      }
    }
    // 轮事实结算——位次 = 各收尾字段写完之后、refresh 之前（settle 自身不 reload，由紧随的
    // refresh 统一重算展示派生与操作栏）；也在 setSending(false)/releaseRun/resetForRound
    // 之前（token 与停止标记在场的最后窗口）
    this.refs.dataSource.settleDisplayRound(roundIdAtFinish, roundStatusAtFinish);
    // 轮收尾字段写完后刷新展示投影——本轮最终正文的轮操作栏标记、空正文占位行的去留都按
    // 写后状态重算（本方法是 done/error 两路唯一收口点）
    this.refs.dataSource.refreshDisplay();
    if (assistantMsg !== null) { ChatStreamTrace.publish(assistantMsg.text.length, assistantMsg.bodyBindingId); }
    ChatStreamTrace.finish(status);
    this.refs.follow.maybeFollow();
    // 收尾保持窗（方案 §7）：finish 信号后 450ms 内迟到 Δh（终态 replace 重解析一次大布局 /
    //「可信本轮耗时」行异步加入）由布局完成事件重锚承接——done/error/stop 三路共用；窗只
    // 影响跟随锚定，不延迟落库与轮收尾时序；底锚开态下 scheduleFollow 入口短路 = 窗自然空转
    this.refs.follow.holdFinishAnchor();
    // 拒答轮落库正文空（展示面文案只是运行时态——重进会话按「空正文异常轮」显示状态行 +
    // 重试键，与其它失败轮同形）
    const content: string = refused ? '' : this.assistantFull;
    const reasoning: string = refused ? '' : this.thinkingFull;
    // graph 收尾身份快照：账本 attemptId/runId 归属——releaseRun 清空 activeRun 后
    // currentAttemptId 归零，必须在其前取值
    const graphRunAtFinish: GraphRunHandle | null = this.host.graphHandleSnapshot();
    const attemptIdAtFinish: string = this.host.currentAttemptId();
    // 耗时读回的归属快照——数据源引用 / 会话 / 路径视图代次 / 本轮 runId，全部在 releaseRun
    // 之前取得；读回只认这组快照（R1 迟到可补 R1，绝不以「当前 activeRun」判断时间归属 = 不写 R2）
    const dsAtFinish: ChatDataSource = this.refs.dataSource;
    const cidAtFinish: string = this.refs.conversationId();
    const epochAtFinish: number = dsAtFinish.pathEpoch();
    const runIdAtFinish: string = graphRunAtFinish !== null ? graphRunAtFinish.runId : '';
    this.refs.setSending(false);
    // 后台回复通知终态上报（判据与闸门全在 chatBgReply）：语义映射 done→「回复完成」、
    // interrupted/failed→「回复已中断」、stopped→撤销通知；与后续落库链零耦合（通知是增益
    // 非必需——上报失败静默降级不阻断收口）
    chatBgReply.onReplySettled(roundStatusAtFinish === 'done' ? 'done' :
      (status === 'interrupted' ? 'interrupted' :
        (roundStatusAtFinish === 'stopped' ? 'cancelled' : 'failed')));
    this.host.releaseRun(); // 轮收尾即释放占用（在途流回调经闭包快照拦截，V10）
    this.activeStream = null;
    this.keyRound.resetForSettle();
    this.toolRound.resetForNewSend([]);
    // 自动重试域收尾复位：计数与停止标记归零 + 状态行抹掉（done/error 两路都经此 = 兜底清空）
    this.autoRetry.resetForRound();
    // 轮次收尾通知（done/error 两路都经此）：页面重算上下文圆环（真值到达 = 最准时刻；
    // 可选钩子无消费方零开销）
    if (this.refs.onRoundSettled !== undefined) {
      this.refs.onRoundSettled();
    }
    // 收尾落库（图路径，S1 K5/K6）：graph 会话 = 终答节点提交（commitRunUnit CAS）→ run
    // 终态（finished/failed 带诊断，幂等）→ 账本 recordUsageEvent（requestId = runId，重复
    // 回调幂等跳过）。graphRun 为空（准备失败早亡）= 无库行可收尾，零动作
    if (assistantMsgId !== '' && this.refs.dbReady() &&
      graphRunAtFinish !== null) {
      const okFinal: boolean = status === 'done';
      // run 层终态三态：从入口轮事实快照分流（同判据同源——此时 autoRetry.resetForRound
      // 已把停止标记清零，禁现读）——done→finished、手动停止→stopped、其余→failed；
      // interrupted 入参直取 RUN_STATUS_INTERRUPTED（finishRun 白名单含 interrupted；
      // roundStatusAtFinish 的「类 stopped」只落显示轮事实面，run 层保真值）
      const runFinalStatus: string = status === 'interrupted' ? RUN_STATUS_INTERRUPTED :
        (roundStatusAtFinish === 'done' ? RUN_STATUS_FINISHED :
          (roundStatusAtFinish === 'stopped' ? RUN_STATUS_STOPPED : RUN_STATUS_FAILED));
      // §2.3 修复随形：工具轮间隙结算过的轮，终答节点不重复提交正文（空内容收口）
      const commitContent: string = settledInToolGap ? '' : content;
      const commitReasoning: string = settledInToolGap ? '' : reasoning;
      // 图轮收尾整段委托域件（节点提交 + run 终态 + 账本一体——本域只组参数与后续触发，
      // 主路径保持零裸时间戳）
      const finishInput: GraphFinishInput = {
        content: commitContent, reasoning: commitReasoning, runFinalStatus: runFinalStatus,
        placeholderNodeId: placeholderAtFinish,
        // DeepSeek 服务端工具原样串（S2⑥——终答节点 server_tools 列载荷；间隙轮空 = 中间
        // 轮快照已落列不重写）
        serverTools: serverToolsAtFinish,
        // 服务端工具计次（二期 #7）：随账本行落库（漏这处 = 值永远进不了账本，重进会话
        // 读不到）
        serverToolUse: roundUsage.serverToolUse,
        // 拒答轮诊断 = 拒答文案（该轮发生在案且原因可见）；其余照旧按终态分档
        diagnostic: refused ? DS_REFUSAL_TEXT : (okFinal ? ''
          : (status === 'interrupted' ?
            (content !== '' ? '后台运行超时，已保留部分内容' : '后台运行超时，生成未完成') :
            (roundStatusAtFinish === 'stopped' ?
              (content !== '' ? '已手动停止，已保留部分内容' : '已手动停止') :
              (content !== '' ? '生成未完成，已保留部分内容' : '生成未完成')))),
        conversationId: this.refs.conversationId(),
        providerId: usageProviderId, modelId: usageModelId,
        attemptId: attemptIdAtFinish,
        promptTokens: usagePrompt, completionTokens: usageCompletion,
        durationMs: usageDurationMs, firstTokenMs: usageFirstTokenMs,
        cachedTokens: usageCached
      };
      // 二期 #4 时序红线：DS 官方标题先 await 落库，再发起图轮收尾——轮末
      // generateTitleForConversation 见到已有标题即不再发一次 TitleApi 请求（writeTitle
      // 内部吞错，标题失败不影响本轮收尾）
      this.dsExtras.writeTitle(cidAtFinish)
        .catch((): void => undefined)
        .then((): void => {
          this.host.graphFinishRound(finishInput)
        .then((ref: GraphNodeRef | null): void => {
          // 内存行库身份回填（终答行 rowSeq/nodeId——无此项则「采用摘要后请求仍带原文」；
          // 实现见 ChatGraphWriteCtrl.stampNodeRef）
          ChatGraphWriteCtrl.stampNodeRef(assistantMsg, ref);
          // 版本步进重算广播：终答行身份回填后发 tick——重试完成的轮此刻才可算「多版本」
          //（新答案已落库）；ChatPageContent @Watch 消费后调 ChatAnswerCtrl.recomputeRowVersions。
          // 零订阅页 = no-op
          AppStorage.setOrCreate<number>(ANSWER_VERSIONS_DIRTY_TICK_KEY,
            (AppStorage.get<number>(ANSWER_VERSIONS_DIRTY_TICK_KEY) ?? 0) + 1);
          // 标题与建议触发（done 收敛点唯一；建议锚用内存 id——generateSuggestForMessage
          // 只按会话读窗口，与消息 id 无关）
          if (okFinal) {
            generateTitleForConversation(this.refs.conversationId());
            generateSuggestForMessage(this.refs.conversationId(), assistantMsgId);
          }
          // 持久化成功（ref 非空）后单 run 读回本轮可信耗时——一次查询、独立 catch（不把
          // 时间增强读取失败误报成「消息保存失败」；失败只 toast 一行提示，无自动循环）
          if (ref !== null && runIdAtFinish !== '' && roundIdAtFinish !== '') {
            this.readBackRoundDuration(dsAtFinish, cidAtFinish, epochAtFinish,
              roundIdAtFinish, runIdAtFinish);
          }
          // conv_invalidate 挂点：本 then = 终答节点提交 + run 终态 + 账本一体的落库链完成
          //（catch 路径不发布），此后一跳发会话列表失效信号——web 列表刷新；手机侧沿用既有
          // SESSION_LIST_RELOAD 广播。发布口未登记/零订阅者 = no-op
          publishChatLiveInvalidate(cidAtFinish);
        })
        .catch((e: Object): void => {
          this.refs.toast('消息保存失败：' + (e as Error).message);
        });
        });
    }
    // 图片未过审呈报（二期 #6 第二条链）：不撤正文，单独一行提示（与输出侧拒答文案分开——
    // 官方语义是「指出被拦截的图片」而非「回答被撤」）
    if (this.dsExtras.hasImageRefusal() && refused !== true) {
      this.refs.dataSource.push(newChatMessage(nextMessageId('notice'), 'notice',
        DS_IMAGE_REFUSAL_TEXT));
    }
  }

  // 本轮耗时读回：单 run 精确读一次（queryRunRowById）→ 同一组存活守卫（数据源未销毁 /
  // 会话与数据源引用未变 / 路径视图代次未换源）→ 该轮事实仍在且终态、可信度纯函数判过 →
  // setter 成功才 refreshDisplay 一次。读失败 hilog 留痕 + 页面仍有效时提示一次；一切不可证
  // 情形保持隐藏（宁缺不伪造）
  private readBackRoundDuration(ds: ChatDataSource, cid: string, epoch: number,
    roundId: string, runId: string): void {
    queryRunRowById(cid, runId)
      .then((run: TraceRunIn | null): void => {
        if (run === null || run.id !== runId) {
          return; // run 不在 / 身份不符——保持隐藏
        }
        if (ds.isDisplayDisposed() || this.refs.dataSource !== ds ||
          this.refs.conversationId() !== cid || ds.pathEpoch() !== epoch) {
          return; // 离页 / 换源 / 会话变——迟到结果不再回填
        }
        const facts: DisplayRoundFacts | null = ds.displayRoundFactsOf(roundId);
        if (facts === null) {
          return;
        }
        const durationMs: number | undefined = trustedRoundDurationMs({
          status: run.status,
          diagnosticMessageId: run.diagnosticMessageId,
          createdAt: run.createdAt,
          updatedAt: run.updatedAt
        });
        if (durationMs === undefined) {
          return; // 不可信（failed 无诊断 / 时间非法）——保持隐藏
        }
        if (ds.setDisplayRoundDuration(roundId, durationMs)) {
          ds.refreshDisplay(); // 成功才刷新一次（已有合法值 / 非终态由 setter 拒绝）
        }
      })
      .catch((e: Object): void => {
        hilog.warn(0xD5A0, 'ChatStreamFlowCtrl', '本轮耗时读取失败：%{public}s',
          (e as Error).message);
        if (!ds.isDisplayDisposed() && this.refs.dataSource === ds &&
          this.refs.conversationId() === cid) {
          this.refs.toast('本轮耗时读取失败，可刷新重试');
        }
      });
  }

  // 节流 flush：有界前缀揭示（delta 参数只作触发与计数，内容以本域累积串为准）。每拍揭示量
  // 见 revealStepFor；msg.text 仍每拍全量覆盖（@Observed 渲染链结构不变），变的只是取值 =
  // 权威累积串的有界前缀（只增不缩，MarkdownDisplayBinding 头尾采样校验天然命中，不放大
  // 解析成本）。返回值 = 该行**权威累积长度**——供节流档位分档（揭示前缀滞后会低估规模，
  // **禁以前缀分档**）。
  // ★ 冻结门（方案 §6）：用户持阅读位（上滑退跟）期间抑制本拍发布——不写 msg.text、不
  // maybeFollow；权威累积与 throttle 时钟照常不受影响（抑制的是发布执行非时钟），恢复跟随
  // 后下一拍自然续上，无补发逻辑、零新恢复路径（恢复仍走 ownership.release() 既有语义）
  private flushFrame(frameId: string, delta: string): number {
    const msg: ChatMessage | null = this.refs.dataSource.findMessage(frameId);
    if (msg === null) {
      return 0;
    }
    const authority: string = frameId === this.liveAssistantId ? this.assistantFull : this.thinkingFull;
    // 终态守卫：行已收口（终态写已全量对齐）后的迟到残余拍不再回写前缀——终态不变式
    if (msg.streaming !== true) {
      return authority.length;
    }
    if (msg.kind === 'assistant' && msg.displayBudget === undefined) {
      msg.displayBudget = new ChatDisplayBudget();
    }
    // 转场前静默停拍（pop 转场期静默位单源 = FollowCtrl，经 refs.follow 只读透传）：不写揭示
    // 前缀、不请求跟随，**发布链与终态对齐不动**（只冻结跟随/揭示帧驱动）——权威累积与
    // 节流时钟照走；排空继续（预算尽/无积压即落 finishStream 无条件全量对齐，静默不悬挂
    // 收尾）；解冻后积压按 ≤1.5× 阶梯续上，无一次性甩出
    if (this.refs.follow.isSilenced()) {
      this.advanceDrain(frameId);
      return authority.length;
    }
    if (this.refs.follow.userHoldsReadingPosition()) {
      this.publishUnderFreeze(frameId, msg, authority);
      return authority.length;
    }
    this.freezeStartAt = -1; // 解冻复位冻结计时（下一冻结期重起算）
    this.advanceReveal(frameId, msg, authority, delta.length);
    if (msg.kind === 'assistant') { ChatStreamTrace.publish(msg.text.length, msg.bodyBindingId); }
    this.refs.follow.maybeFollow();
    this.advanceDrain(frameId);
    return authority.length;
  }

  // 冻结期发布处置（四约束的落点）：④ 冻结时长有界——连续冻结每满 FREEZE_FORCED_REVEAL_MS
  // 强制执行一拍有界揭示（走同一阶梯上界，禁一次性甩全量），计时重置；③ 停更判据只认权威
  // 累积长度**严格大于**已揭示长度（冻结静默 ≠ 流结束，禁「距上次发布时间」类启发式误报）；
  // ① 终态穿透——排空期照常推进 advanceDrain（throttle 时钟经其再入列保持存活），预算尽落
  // finishStream 的权威写不受冻结拦截（② 触摸死区在判据上游：ownership.drag 的 2vp slop）
  private publishUnderFreeze(frameId: string, msg: ChatMessage, authority: string): void {
    if (this.freezeStartAt < 0) {
      this.freezeStartAt = Date.now();
    } else if (Date.now() - this.freezeStartAt >= FREEZE_FORCED_REVEAL_MS) {
      this.freezeStartAt = Date.now();
      if ((this.revealLen.get(frameId) ?? 0) < authority.length) {
        this.advanceReveal(frameId, msg, authority, authority.length - (this.revealLen.get(frameId) ?? 0));
        if (msg.kind === 'assistant') { ChatStreamTrace.publish(msg.text.length, msg.bodyBindingId); }
      }
    }
    this.advanceDrain(frameId);
  }

  // 揭示前移一拍（正常发布拍与冻结强制拍共用同一阶梯）：msg.text 全量覆盖，值 = 权威累积
  // 的有界前缀（只增不缩）
  private advanceReveal(frameId: string, msg: ChatMessage, authority: string, pendingUnits: number): void {
    const revealed: number = this.revealLen.get(frameId) ?? 0;
    if (revealed >= authority.length) {
      return;
    }
    const nextLen: number = Math.min(revealed + this.revealStepFor(frameId, msg, pendingUnits),
      authority.length);
    this.revealLen.set(frameId, nextLen);
    this.revealLastStep.set(frameId, nextLen - revealed);
    msg.text = authority.substring(0, nextLen);
  }

  // 本拍揭示量：基准步长移动平均（ChatDisplayBudget.stepHint 速率调节）钳入
  // [REVEAL_MIN_CHARS, REVEAL_MAX_CHARS]，再受 1.5 × 上拍揭示量硬上界（floor 取整保界
  // 不破）；下限兜底防阶梯自锁停滞。无预算通道行（displayBudget 缺席 = 思考行）基线分源至
  // THINKING_REVEAL_BASE_CHARS——预算器缺席即无成本反馈的单一判别源
  private revealStepFor(frameId: string, msg: ChatMessage, pendingUnits: number): number {
    const hint: number = msg.displayBudget !== undefined ?
      msg.displayBudget.stepHint(msg.bodyBindingId, msg.text.length, pendingUnits, Date.now()) : -1;
    if (hint > 0) {
      // 离群极值先钳入揭示域上界再进移动平均（不钳会毒化平均）
      const clampedHint: number = Math.min(hint, REVEAL_MAX_CHARS);
      const avg: number = this.revealBase.get(frameId) ?? REVEAL_BASE_CHARS;
      this.revealBase.set(frameId, avg * 0.75 + clampedHint * 0.25);
    }
    // 兜底分源判据 = 预算器缺席（非 kind 字面量——budget 创建门已按 kind 判一次，两处判
    // kind 会造第二判据漂移面）；assistant 行进本函数前必有 budget，新分支对其不可达
    const base: number = Math.min(REVEAL_MAX_CHARS,
      Math.max(REVEAL_MIN_CHARS, this.revealBase.get(frameId) ??
        (msg.displayBudget === undefined ? THINKING_REVEAL_BASE_CHARS : REVEAL_BASE_CHARS)));
    const bound: number = Math.floor(REVEAL_GROWTH_FACTOR *
      (this.revealLastStep.get(frameId) ?? REVEAL_BASE_CHARS));
    return Math.max(REVEAL_MIN_CHARS, Math.min(base, bound));
  }

  // 收尾排空启动（方案 §5.5）：onStreamDone 判定完毕、落 finishStream 前调用——有揭示积压
  // 时沿既有节流时钟多跑几拍同一阶梯的有界揭示（不引入第二定时器、不一次性甩出），排空或
  // 预算尽才落终态；无积压返回 false 由调用方立即收尾。异常路（stop/error/换轮/离页）不经
  // 此——终态写直接全量对齐
  private beginDisplayDrain(status: string): boolean {
    if (!this.hasRevealBacklog()) {
      return false;
    }
    this.drainDeadline = Date.now() + REVEAL_DRAIN_BUDGET_MS;
    this.drainFinishStatus = status;
    // 空 delta 只作节流触发（flushFrame 内容恒以权威串取值）
    this.throttle().enqueue(this.liveAssistantId, '');
    if (this.revealBacklogOf(this.liveThinkingId, this.thinkingFull)) {
      this.throttle().enqueue(this.liveThinkingId, '');
    }
    return true;
  }

  // 揭示积压判定：任一在流式的行已揭示长度 < 权威累积长度（终态行已全量对齐不算积压）
  private hasRevealBacklog(): boolean {
    return this.revealBacklogOf(this.liveAssistantId, this.assistantFull) ||
      this.revealBacklogOf(this.liveThinkingId, this.thinkingFull);
  }

  private revealBacklogOf(frameId: string, authority: string): boolean {
    if (frameId === '') {
      return false;
    }
    const msg: ChatMessage | null = this.refs.dataSource.findMessage(frameId);
    return msg !== null && msg.streaming === true &&
      (this.revealLen.get(frameId) ?? 0) < authority.length;
  }

  // 排空驱动（每拍 flush 末尾调用，仅排空中进入）：仍有积压且预算内 → 沿节流时钟排下一拍；
  // 排空或预算尽 → 立即落终态（终态写无条件全量对齐 = 显示滞留硬上限，§0 界公式②）
  private advanceDrain(frameId: string): void {
    if (this.drainDeadline < 0) {
      return;
    }
    if (this.hasRevealBacklog() && Date.now() < this.drainDeadline) {
      this.throttle().enqueue(frameId, '');
      if (frameId !== this.liveThinkingId &&
        this.revealBacklogOf(this.liveThinkingId, this.thinkingFull)) {
        this.throttle().enqueue(this.liveThinkingId, '');
      }
      return;
    }
    const status: string = this.drainFinishStatus;
    this.drainDeadline = -1;
    this.drainFinishStatus = '';
    this.finishStream(status);
  }

  // 离页兑付在途收尾排空（§5.6 异常路「离页」）：不等预算立即落终态（含落库与轮收尾）。
  // ★ U9 起退页不再到达本方法（退页不断流——排空沿节流时钟自然跑完）；保留为运行时空闲
  // 回收点的兜底（此刻无排空态恒零动作）。调用序约束：须在 releaseRun 清运行身份**之前**
  // 调用（清后 token 失效、图收尾句柄不可达）。无在途排空时零动作
  finishPendingDrain(): void {
    if (this.drainDeadline < 0 || this.drainFinishStatus === '') {
      return;
    }
    const status: string = this.drainFinishStatus;
    this.drainDeadline = -1;
    this.drainFinishStatus = '';
    this.finishStream(status);
  }

  // 单行揭示状态随终态 drop 同拍清（防跨轮残留；整面清走 resetAppendBuffer）
  private dropRevealFrame(frameId: string): void {
    this.revealLen.delete(frameId);
    this.revealLastStep.delete(frameId);
    this.revealBase.delete(frameId);
  }

  // 揭示状态整面清（含排空态与冻结计时）——轮首 / 续轮 / 真全量重建三点同拍清；「离页」
  // 点已退役（退页不断流，见 resetAppendBuffer 注释），运行态回收点的 disposeActiveStream
  // 仍经此清
  private clearRevealState(): void {
    this.revealLen.clear();
    this.revealLastStep.clear();
    this.revealBase.clear();
    this.drainDeadline = -1;
    this.drainFinishStatus = '';
    this.freezeStartAt = -1;
  }
}
