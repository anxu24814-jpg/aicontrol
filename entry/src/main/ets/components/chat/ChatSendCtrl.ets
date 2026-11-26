// 发送编排域（自 ChatPage 拆出）。★ 收发链路承 M1 语义（回归红线）：发送 → 协议流（工厂按
// protocol 分发）→ ChatAppendThrottle 帧合并 → ChatDataSource（LazyForEach）渲染；思考增量进
// thinking kind；流式增量只进内存，完成/停止/出错一次性收尾落库（图会话 = 终答节点提交，禁
// 逐帧写库）；★ U9 起退页不断流——页面销毁只解绑（disposeSilent 调用面改运行时空闲回收点，见
// ChatSessionRuntime）。
// ★ 流式重试口径：换 Key 重发与自动退避重发都在本域编排——后者在「传输层失败、服务端 5xx
// 或瞬态文案命中且本轮零产出」时触发（见 ChatAutoRetryCtrl）；中途断流与未入面失败不自动重发。
// ★ 多 Key 池轮次：发送取「下一支 key」；401/403/429 = key 级失败换下一启用 key 重发同消息
//（一轮内不重用；网络错误/手动停止不切）；全失败才 notice 落库；key 明文不进日志/toast。取钥
// 起始位由服务商配置决定（key_pick_mode：rotate 轮转 / random 随机，分派单一来源
// nextPickStart）——**只影响起始位**：环绕尝试序、失败切换阶梯、协议请求字节全不变。节流：
// assistantFull/thinkingFull 累积串唯一真源，flush 全量覆盖（增量即全部，drop 未刷增量防二次拼接）。
// ★ 附件：载荷前置组装（失败降级纯文本），附件仅随本轮。图链转图：send 链附件组装并行一步
// fetchTextImages——消息文本 Markdown 图链下载编码后并入 payload.images 走附件同一通道；全静默
//（无视觉/失败/超限留作文本），原文全程保留，编排与判据单源在 common/TextImageFetch.ets。
// 发送成功附件文件常驻 filesDir，元数据行随 user 消息落库；条件清理 = 单分支（仅载荷失败全清，
// 留盘供会话内预览，回收点 = 离页 sweepAttachDir）；user 消息随发送装配附件简报 attachBriefs。
// ★ 思考档位：refs 注入 → supportsThinking 门控 → 随轮次下发（'' = 不带字段）。
// ★ 会话绑定：助手覆盖/有效绑定在 ChatPromptState。高级设定：助手采样/上下文参数
//（ChatPromptState.advancedParams 解析缓存）——contextCount 注入前尾部截取（clipHistoryTail，
// 身份注入不丢）+ 采样五字段随轮次下发（null = 未配置零字段；roundSampling 快照随 key 失败切换
// 重发同参数）。
// ★ 工具调用底层：发送轮完成若聚合出工具调用 → 串行执行（ask_user 挂交互桥）→ 结果以
// role='tool' 追加历史 → while 式续轮（每轮新 assistant 占位行 + 落库）；轮数上限防死循环
//（值 = 归属助手 toolStepLimit 列，0 = 不限制走 256 硬顶；A2 让位轮：首次触顶不直接收尾——被
// 丢弃的调用以合成工具结果回传模型、再开一轮让它自己组织收尾话术，治空气泡；让位只给一次）；
// 工具卡 kind='tool' 上屏 + role='tool' 行落库（回放单一真源，ChatHistoryBuilder 据此重建工具
// 方言）；key 失败切换语义不变（轮内切 key 重发同消息）。
// ★ 退役史（防回游）：Cube 双引擎分流/三频道打字机、隐私会话零落库旁路面均已整域退役——揭示
// 只剩原生路（ChatAppendThrottle 分档节流 → ChatStreamFlowCtrl 全量覆盖），渲染由 ChatMarkdownBody
// 唯一承接（偏好键不回收，存量持久值无害）。末轮重试真链曾「撤链→复活为多版本保留链（variants
// 双列 + ‹ i/N › 切换键 + ChatSendPersist 双行入库编排）」，后随 legacy 退役整域删除——现役发送/
// 收尾唯一路径 = 图命令（prepareRun 提交 / finishStream 终答节点提交），重试编排域（retryAt 图重试）
// = ChatRetryCtrl，Key 池轮次域 = ChatKeyRoundCtrl，本件留两域宿主实现位与薄委托。账本口径拍板 =
// 重试消耗照常落账（账本与消息生命周期解耦，统计页全量求和）。
// ★ 技能层：system 注入链多一层——技能清单（appendSystemSkills，稳定块）插在提示词注入之后、
// 记忆块（易变块）之前；工具声明链多一件模式驱动工具 use_skill（助手启用集 ∩ 库内现存非空才
// 声明，与清单同一次计算同闸）；清单组装与上限全在纯函数 SkillText，本域只做两行级接线。
// ★ 单条消息指定技能：本轮可指定一件技能（setSkillDesignate 写入，'' = 无指定）——①并入清单与
// use_skill 声明（同一次计算同闸：启用集 ∪ 指定、去重）；②指定正文块随本轮 **user 消息**注入
//（「技能正文永不进 system」的不变量原样成立）；③标注句进显示面，用户零文本时以它代位进协议面
//（保 user 内容非空）；④发完由页面清态、零落库零历史轮。
// ★ 工具卡接线：failRound/disposeSilent 两漏斗都调 toolRound.abortRoundPending（D 会话隔离传 id +
// B 中止落库）；onStreamDone 接线幻觉 notice（判据与 push 在域件 noticeForUndeclaredCalls，
// 零声明不续轮）。
// ★ 本件越 1200 硬线（在册存量债）：后续任何实质改动须先把所属域拆出再动手。
// ★ 旧会话墓碑：send/dispatchSend 的 blocked 早退只余一句墓碑短句；判据单源 =
// ChatGraphWriteCtrl 路由镜像（'blocked' = 旧格式墓碑）。
// ★ 流回调与轮次收尾域在 ChatStreamFlowCtrl（流回调三口 / finishStream / flushFrame /
// createNativeStream / failRound / 节流器 / 流式运行时态五成员——五成员 private，本件经意图方法与
// 只读面消费）；ChatFlowHost 实现位在 ChatFlowHostBridge；宿主接口薄直通整段在 ChatHostDelegates。
// ★ 轮次请求组装域（assembleRound）在 ChatRoundAssembly——「禁第二条请求链」锚点 = assembleRound
// 全件唯一调用字面在 assembleFittedRound（见该方法注释）。生命周期收尾域（abort/disposeSilent
// 编排）在 ChatSendLifecycleCtrl（本件薄委托）；flow/keyRound/toolRound 三件经只读访问器供
// ChatSessionRuntime 持有——写面全在意图方法与宿主面，禁新增第二写口。
// ★ 排队插队（总案）：发送入口在「生成中或队列非空（含暂停态）」时文本入队并 return true
//（M1「运行中不插话」红线取代旧「运行中拒绝」；带附件 busy 拒绝入队 + toast，文本 only）；守卫链/
// 入队路由/队列状态机在 ChatSendEntryGate/ChatSendQueueCtrl，发送前异步组装链（附件/图链/记忆/
// 技能/知识三快照/图路由装载/路径摘要直查）在 ChatSendAssembly，本件只留引用与薄直通。
// ★ T4c（永不静默丢消息）：任何「受理后失败且无 setSending 写」的出口必须 onDispatchAbandoned
// 通知队列回滚（IN_FLIGHT 项回队 + 清闩 + PAUSED）；beginSend resolve = 投递确认回执
// onDispatchCommitted（事务已同笔删排队行）；写穿失败经 restoreSendInput 归还文本。本件零 DB 面。
// ★ 自动出队（autoDispatch）拽底条件化：用户持阅读位时跳过 forceToBottom（跨重启空洞维持现状
// 语义——重启后待答期可发新消息直接开新轮，恢复的队列行排其后由下降沿派发）；手动发送与
//「立即发送」恒拽底。
import { AiChatMessage, AiConnection, AssistantAdvancedParams, ChatStream,
  PendingAttachment, SamplingParams } from '../../common/providers/AiTypes';
// 二期 S4 / §1-8：轮次组装与起流域外迁（本件 1200 硬线只许减行；起流咽喉点仍唯一）
import { ChatRoundLauncher } from './ChatRoundLauncher';
// 二期 S4 #10：续写编排域（本件只留三个薄委托与一跳 handler 登记）
import { ChatContinueCtrl } from './ChatContinueCtrl';
import { registerContinueHandler } from '../../common/chat/ChatContinueSupport';
import { ChatToolMediaCtrl } from './ChatToolMediaCtrl';
import { TOOL_SEARCH_WEB } from '../../common/providers/ToolIds';
import { toolRuntime } from '../../common/providers/ToolRuntime';
import { chatRunScope } from './ChatRunScope';
import { RunIdentity, ToolExecutionContext, TOOL_SCOPE_CHAT } from '../../common/chat/MessageContracts';
import { ChatListAnchorJudge } from '../../common/chat/ChatListAnchorJudge';
import { composeQuotedContent } from '../../common/chat/QuoteCompose';
import { ChatToolRoundCtrl, ToolEventRecord } from './ChatToolRoundCtrl';
import { ChatToolResendCtrl, ChatResendHost } from './ChatToolResendCtrl';
import { ChatAskResumeBridge, ChatAskResumeCtrl } from './ChatAskResumeCtrl';
import { ChatKeyRoundCtrl } from './ChatKeyRoundCtrl';
import { ChatSendLifecycleCtrl } from './ChatSendLifecycleCtrl';
import { ChatRetryCtrl, ChatRetryHost } from './ChatRetryCtrl';
import { ChatUsageRoundCtrl } from './ChatUsageRoundCtrl';
import { ChatAutoRetryCtrl } from './ChatAutoRetryCtrl';
import { ChatHostDelegates } from './ChatHostDelegates';
import { ChatStreamFlowCtrl, StreamSettlement } from './ChatStreamFlowCtrl';
import { ChatFlowHostBridge } from './ChatFlowHostBridge'; // 域②：ChatFlowHost 实现位外迁件
import { ChatSnapshotCtrl, SkillSendContext } from './ChatSnapshotCtrl';
// 轮次请求组装域件（组装链整段在彼件，RoundRequest 为彼件导出类型）
import { ChatRoundAssembly, RoundRequest } from './ChatRoundAssembly';
// toolDefsJsonOf = fitTokens 估算分母侧工具声明序列化（assembleFittedRound 消费）
import { ChatContextUsageCalc, ContextSkillSnapshot, ContextUsage, toolDefsJsonOf } from './ChatContextUsage';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PromptInjectConfig, KnowledgeInjectPlan } from '../../common/providers/RequestInject';
import { composeSkillDesignateMark, joinNonEmptyParts } from '../../common/SkillText';
// 同名判据各自就近 import 不算双源——判据函数单源在 MemoryGen
import { MEMORY_SCOPE_ASSISTANT } from '../../common/store/MemoryDb';
// 组装链 / 守卫与队列宿主接线 / 排队状态机全在彼三件，本件只留引用与薄直通
import { ChatSendAssembly } from './ChatSendAssembly';
import { ChatSendEntryGate } from './ChatSendEntryGate';
import { ChatSendQueueCtrl } from './ChatSendQueueCtrl';
import { AttachmentPayload, buildAttachmentRows,
  briefsFromPending, hasVisionCap } from '../../common/AttachmentUtil';
import { ConversationOverride,
  nextMessageId, nextRowCreatedAt } from '../../common/store/ChatDb';
import { MessageAttachmentRow } from '../../common/store/AttachmentDb';
import { ChatFollowController } from './ChatFollowController';
import { ChatDataSource } from './ChatDataSource';
import { buildRequestHistory } from './ChatHistoryBuilder';
import { ChatMessage, newChatMessage } from './ChatMessageCompose';
import { ChatPromptState, ChatStatusSource } from '../../common/chat/ChatPromptState';
import { cleanupAttachments, releaseAttachmentThumbs } from './AttachmentPickCtrl';
// contextWindowForConnection = token 双闸窗口值来源（发送/重试两链与用量面板同源）
import { CONN_RESOLVE_TICK_KEY, contextWindowForConnection } from '../../common/store/ProviderDb';
import { composePendingKeyNote, getPendingKey } from '../../common/store/KeyStore';
import { TOOL_MANAGE_PROVIDERS } from '../../common/providers/ToolIds';
// 图会话读写路径域：发送/重试/收尾的图命令编排单点（运行句柄与 revision 在本域；图写命令族
// 取自 ChatGraphCommandSource，请求侧摘要注入留 ChatContextSource；D 组冻结命令层不经本件直触）
import { GraphSendStart, GraphNodeRef }
  from '../../common/chat/ChatGraphCommandSource';
import { RequestSummaryInput,
  ROUTE_BLOCKED, readPathSummaryInput } from '../../common/chat/ChatContextSource';
import { ORIGIN_SEND, PrepareRunInput } from '../../common/store/MessageBranchDb';
import { ChatGraphWriteCtrl } from './ChatGraphWriteCtrl';
import { TOMBSTONE_TOAST_TEXT } from '../../common/chat/ChatBranchPolicy';
import { upgradeTitlePlaceholder } from '../../common/TitleGen';
import { clearConversationSuggestions } from '../../common/SuggestGen';
// 请求历史按「助手上下文条数 + 模型窗口 token」双闸从库独立读取（发送/重试两链经编排件，
// 用量面板/压缩选段直调读口与预算函数——五处同源）；kill 开关 = Theme 常量一行回旧链
import { ChatRequestHistoryCtrl, RequestHistoryResult, TokenFitResult }
  from './ChatRequestHistoryCtrl';
import { resolveTokenBudget } from '../../common/chat/RequestHistoryBudget';
import { REQUEST_HISTORY_DECOUPLE_ENABLED } from '../../common/Theme';

// 页面侧读写集（箭头闭包持页面 this 延迟求值；@State 写必须回页面经回调，普通引用直持有）
export interface ChatSendRefs {
  // 消息流（页面 @State 持有的数据源——容器操作经直引用）
  dataSource: ChatDataSource;
  // 流式滚动跟随（页面持有，与列表 scroller 同源）
  follow: ChatFollowController;
  // 消息 List 锚态判定器：重试域消费——末轮重试后按条数闸复位锚态（与 ChatPageLoad 重建链
  // reset 同规则，见 ChatRetryCtrl.retryGraph）
  anchorJudge: ChatListAnchorJudge;
  conversationId: () => string;
  dbReady: () => boolean;
  conn: () => AiConnection | null;
  sending: () => boolean;
  // 思考档位（页面 @State，'' = 默认不传；能力门控在 resolveRoundParams——不支持 = 不传零回归）
  thinking: () => string;
  // 会话联网开关 = **归属助手启用清单的镜像**（页面 load 解析后写入）——发送组装按此过滤
  // search_web 声明，与 enabledToolIds 同源
  webSearchOn: () => boolean;
  // 无行会话的会话级覆盖：首条消息落行时随建行写入 conversations 覆盖三列（实现位 =
  // bornGraphConversation 的 ensureOverride 入参）；有行会话恒 null（覆盖已在库，由用户在
  // 会话内的后续操作直接 UPDATE）
  sessionOverride: () => ConversationOverride | null;
  // ── 待发引用（照 sessionOverride/restoreSendInput 页面闭包先例——页面 @State
  // pendingQuote 的读写口，绑定态缺省恒 ''/零动作）──
  // 读口：'' = 无待发引用。dispatchSend 入口快照一次（quoteSnapshot），异步窗口改值不串轮
  //（照 designateId 快照口径）；autoDispatch 出队派发强制不消费（护栏见 dispatchSend 头）
  pendingQuote: () => string;
  // 清空口：**唯一合法调用点 = beginSend resolve（user 行已落库、引用已持久化进 quote_text）
  // 后的冻结比对**——pendingQuote() === quoteSnapshot 才清（异步窗口用户改过则不清）；
  // 失败路径一律不清（不清空即保留，语义细则见 dispatchSend 清空点注释）
  clearPendingQuote: () => void;
  setSending: (sending: boolean) => void;
  // 发送前置守卫通过后的错误态清空（页面 errorText 覆盖层）
  clearError: () => void;
  toast: (message: string) => void;
  // 轮次收尾通知（可选钩子）：done/error 两路都在 finishStream 触发——页面据此重算上下文
  // 圆环（生成中不刷、收尾即刷）；无消费方时零开销（活算在 ChatContextUsageCalc）
  onRoundSettled?: () => void;
  // 当前分支路径视图重载（实现由页面注入 = ChatPageLoadCtrl.runHistoryLoad 的 Promise 面；
  // 中途整轮重试切到替代分支后须先换源再推承载行，见 ChatRetryCtrl.retryAtGraph）。
  // **本件零逻辑**：声明能力口。返 false = 态读异常/历史读取失败（视图未换源），调用须中止
  reloadBranchPath: () => Promise<boolean>;
  // 拒发归还输入（发送已按 true 交页面、输入条与附件条均已清态，之后才在派发点读到「真
  // blocked」时把这一笔原样还给用户——文字回输入条、附件回附件条，免白打字）。
  // **本件零逻辑**：声明能力口，实现由页面注入（applyFullInputDraft 覆盖式重写 + 附件回填）
  restoreSendInput: (text: string, attachments: PendingAttachment[]) => void;
  // ── 排队域（边沿观察者 + 终态快照；可选位，生产 refs 恒实现）——attach/detach 成对，
  // prev≠next 才上报；G7 读内存快照禁查 DB ──
  attachSendingEdge?: (watcher: (sending: boolean) => void) => void;
  detachSendingEdge?: (watcher: (sending: boolean) => void) => void;
  lastSettleCause?: () => string;
  setLastSettleCause?: (cause: string) => void;
}

// RETRY_STATUSES 常量在 ChatStreamFlowCtrl（onStreamError 唯一消费方）；工具轮上限与轮次态
// 在 ChatToolRoundCtrl（上限值链与实际闸门同源，见彼件注释）

// ChatFlowHost 实现位整体在外迁件 ChatFlowHostBridge.ets（图写侧四口 + 运行隔离态三法闭包回接）
export class ChatSendCtrl implements ChatRetryHost, ChatResendHost {
  private refs: ChatSendRefs;
  // ── 宿主接口实现位域：工具轮/Key 池/自动重试三接口薄直通与薄包装在 ChatHostDelegates
  //（access 闭包集回接宿主态与组件引用；沿革见该件头注释）──
  private delegates: ChatHostDelegates;
  // ── 生命周期收尾域（ChatSendLifecycleCtrl）：abort/disposeSilent 两终止路径编排在彼件，
  // 本件留两行薄委托与构造序末位接线 ──
  private sendLifecycle: ChatSendLifecycleCtrl;
  // ── 流回调与轮次收尾域（ChatStreamFlowCtrl）：流回调三口 / finishStream / flushFrame /
  // createNativeStream / failRound / 节流器 / 流式运行时态五成员整域在彼件——五成员 private，
  // 本件只经意图方法（beginStreamRound 等）与只读面到达，并实现其宿主面 ChatFlowHost ──
  private flow: ChatStreamFlowCtrl;
  // ── Key 池轮次域（ChatKeyRoundCtrl）：轮次五成员与 startRound/attemptCurrent/tryNextKey
  // 全在彼件，本件经此引用消费 ──
  private keyRound: ChatKeyRoundCtrl;
  // ── 工具调用轮次态（ChatToolRoundCtrl）：roundTools/roundKeyIds 同为「一轮」快照——
  // 失败切换重发同声明 ──
  private toolRound: ChatToolRoundCtrl;
  // ── 工具卡重发编排域（ChatToolResendCtrl）：本件留 ChatResendHost 实现位（self
  // implements 经 this 回接）──
  private resend: ChatToolResendCtrl;
  private disposed: boolean = false; // 页面销毁闸（异步取钥中途销毁守卫）
  // ── 运行隔离（I2/I5/I8/I11）：本控制器当前活跃 run 与其执行上下文。beginRunAcquire 在
  // 发送/重试守卫段同步接纳（消灭组装窗口双发；同会话双控制器单活跃 run）；release 统一挂
  // finishStream 收尾与 disposeSilent（先失效后释放——收尾前旧身份回调凭 token 快照拦截，
  // 收尾后探测面全 false）──
  private activeRun: RunIdentity | null = null;
  // 当前 run 的身份令牌（conversationId|runId；'' = 无活跃轮）——流回调三口经闭包快照比对
  private runToken: string = '';
  // 本轮工具执行上下文（轮首构造快照；执行器经 host.executionContext() 消费）
  private runCtx: ToolExecutionContext | null = null;
  // ── 工具产出附件挂载缝域（ChatToolMediaCtrl）：collectImage/collectPageImage 两闭包本体与
  // 计数成员整域在彼件 ──
  private toolMedia: ChatToolMediaCtrl;
  // ── 图会话写侧编排域（ChatGraphWriteCtrl）：状态句柄与命令编排在彼件，本域留薄委托与
  // 轮次收尾组装 ──
  private graphWrite: ChatGraphWriteCtrl = new ChatGraphWriteCtrl();
  // 流回调域宿主面桥接件（声明位在 graphWrite 之后保证引用就位）
  private flowHostBridge: ChatFlowHostBridge = new ChatFlowHostBridge(this.graphWrite,
    (): boolean => this.disposed, (): string => this.currentRunToken(),
    (): string => this.currentAttemptId(), (): void => { this.releaseRun(); });
  // ── 轮级用量与诊断标记域（ChatUsageRoundCtrl）：跨流用量求和/截断末流胜出/首字首个胜出
  // 三条口径全在彼件，本件只留三条接线 = 轮首 reset + 流末 accumulate + 收尾 values ──
  private usageRound: ChatUsageRoundCtrl = new ChatUsageRoundCtrl();
  // 提示词注入解析域（ChatPromptState）：load 预载 → send 组装读取；兼管会话级助手绑定
  //（覆盖值/有效绑定——语义见 ChatPromptState 头注释）
  private promptState: ChatPromptState = new ChatPromptState();
  // 会话上下文用量域（ChatContextUsageCalc）：估算/锚点/校准/活算编排，闭包持 refs 延迟求值
  private ctxCalc: ChatContextUsageCalc;
  // 本轮指定技能 id（页面在发送前经 setSkillDesignate 写入，'' = 无指定；纯内存、不跨轮、
  // 不落库）。★ 本字段只在 send() 入口被**快照**一次——buildSkillContext 禁直读本字段：
  // 载荷/记忆/技能三链异步串行，组装期间页面可再改指定，晚读会把「后改的值」注进「先发的
  // 那条消息」（静默串轮）
  private designateId: string = '';
  // ── 发送前快照域（ChatSnapshotCtrl）：记忆块与技能上下文两块 system 注入材料的读取与组装 ──
  private snapshot: ChatSnapshotCtrl;
  // ── 轮次请求组装域（ChatRoundAssembly）：本件持引用 + 调用点在 assembleFittedRound
  //（「禁第二条请求链」锚点见该方法注释）──
  private roundAsm: ChatRoundAssembly;

  // ── 请求历史编排域（ChatRequestHistoryCtrl）：读库 → 组装 → 降级与 token 双闸的编排件
  //（发送/重试两链消费；读口与预算函数五处同源）──
  private reqHist: ChatRequestHistoryCtrl = new ChatRequestHistoryCtrl();

  // ── 发送前异步组装域（ChatSendAssembly）：send() 守卫段之后的组装链（附件载荷/图链转图/
  // 三快照/图路由装载/路径摘要直查/派发回调）在彼件，本件经此引用一行调用；宿主面闭包集
  //（销毁闸/占用释放/图路由/会话 id/消息全量/toast/派发口），snapshot 直注 ──
  private sendAssembly: ChatSendAssembly;

  // ── 发送入口守卫与排队路由域（ChatSendEntryGate）：守卫链/入队路由/队列实例与八闭包宿主
  // 面在彼件；本件只留引用与三处薄直通 ──
  private sendGate: ChatSendEntryGate;

  // ── 重试编排域（ChatRetryCtrl）：现役 = 图重试入口 retryAt，本件持引用 + ChatRetryHost
  // 实现位 ──
  private retry: ChatRetryCtrl;
  private askResume: ChatAskResumeCtrl; // 提问等待与跨重启续答域（★ U11 域⑤）

  // ── 网络层失败自动重试域（ChatAutoRetryCtrl）：本域只管「请求尚未产出任何内容」的网络
  // 失败重发；用户主导的整轮重生成仍走 ChatRetryCtrl ──
  private autoRetry: ChatAutoRetryCtrl;
  // 轮次组装与起流域（二期 S4 拆分件）：launchRetryRound / retryRoundFromDb 两段整域外迁，
  // 本件只持引用 + 薄委托 + 构造期闭包注入（禁第二条请求链）
  private roundLauncher: ChatRoundLauncher;
  private continueCtrl: ChatContinueCtrl;

  // 构造序末位依赖的就绪位（L-E-5 防御）：this.flow 在构造序末位才赋值，access 闭包一律经
  // flowRef() 取流域——构造期误调即给明确失败，而非 undefined 解引用的隐晦报错
  private flowReady: boolean = false;

  private flowRef(): ChatStreamFlowCtrl {
    if (!this.flowReady) {
      throw new Error('构造序缺陷：流域尚未就绪（access 闭包在构造期被调用）');
    }
    return this.flow;
  }

  constructor(refs: ChatSendRefs) {
    this.refs = refs;
    // 宿主接口实现位域：access 闭包集先行——箭头延迟求值（下方域件晚于本件创建，调用时刻
    // 恒已就位），域件构造实参一律 delegates
    this.delegates = new ChatHostDelegates({
      isDisposed: (): boolean => this.disposed,
      isSending: (): boolean => this.refs.sending(),
      isDbReady: (): boolean => this.refs.dbReady(),
      conversationId: (): string => this.refs.conversationId(),
      toast: (message: string): void => this.refs.toast(message),
      dataSource: (): ChatDataSource => this.refs.dataSource,
      maybeFollow: (): void => this.refs.follow.maybeFollow(),
      // 流式运行时态只读闭包：五成员 private——改指流域只读 getter 与结算快照，写面只剩
      // 流域意图方法三闭包（clearRoundAccumulation/bindLiveAssistant/attachStream）；一律经
      // flowRef() 取流域（L-E-5：构造期误调给明确失败）
      liveAssistantId: (): string => this.flowRef().getLiveAssistantId(),
      liveThinkingId: (): string => this.flowRef().getLiveThinkingId(),
      assistantFull: (): string => this.flowRef().getAssistantFull(),
      thinkingFull: (): string => this.flowRef().getThinkingFull(),
      settlement: (): StreamSettlement => this.flowRef().settlement(),
      clearRoundAccumulation: (): void => this.flowRef().clearRoundAccumulation(),
      bindLiveAssistant: (id: string): void => this.flowRef().bindLiveAssistant(id),
      keyRound: (): ChatKeyRoundCtrl => this.keyRound,
      toolRound: (): ChatToolRoundCtrl => this.toolRound,
      retry: (): ChatRetryCtrl => this.retry,
      usageRound: (): ChatUsageRoundCtrl => this.usageRound,
      runToken: (): string => this.currentRunToken(),
      nextAttempt: (): void => this.nextAttempt(),
      executionContext: (): ToolExecutionContext => {
        if (this.runCtx === null) {
          // I9：轮首未构造上下文即有工具执行 = 调用序缺陷，明确失败不静默兜底
          throw new Error('本轮工具执行上下文尚未构造（runCtx 为空）');
        }
        return this.runCtx;
      },
      // 工具结果附件缝（域件 ChatToolMediaCtrl：collectToolImage 三段挂载 + toolResultMedia
      // 判据单源消费）
      collectToolImage: (callId: string, mimeType: string, data: string): boolean =>
        this.toolMedia.collectToolImage(callId, mimeType, data),
      toolResultMedia: (): boolean => this.toolMedia.toolResultMedia(),
      // 图会话写侧（2026-09-26 笔3 S1——工具轮域经 delegates 发意图/提交节点）
      isGraphMode: (): boolean => this.graphWrite.isMode(),
      graphCommitRoundAssistant: (content: string, reasoning: string, stepIndex: number,
        stampTarget: ChatMessage | null, placeholderNodeId: string): Promise<boolean> =>
        this.graphCommitRoundAssistant(content, reasoning, stepIndex, stampTarget,
          placeholderNodeId),
      graphCommitToolNode: (record, stepIndex: number): Promise<boolean> =>
        this.graphCommitToolNode(record, stepIndex),
      graphToolFactDispatch: (name: string, argsJson: string): Promise<string> =>
        this.graphToolFactDispatch(name, argsJson),
      graphToolFactConfirm: (factId: string, result: string,
        failed: boolean): Promise<void> => this.graphToolFactConfirm(factId, result, failed),
      refreshEstimate: (history: AiChatMessage[]): void => this.ctxCalc.refreshEstimate(history),
      setActiveStream: (stream: ChatStream | null): void => {
        // Key 池域起流/清引用经资源交接方法（attachStream），不再字段写
        this.flowRef().attachStream(stream);
      },
      throttleDrop: (frameId: string): void => this.flowRef().throttle().drop(frameId),
      // 两接口方法回接口（failRound/createNativeStream——实现体在 ChatStreamFlowCtrl，本件薄委托）
      failRound: (message: string, status: number): void => this.failRound(message, status),
      createNativeStream: (conn: AiConnection): ChatStream => this.createNativeStream(conn)
    });
    this.askResume = new ChatAskResumeCtrl(refs, new ChatAskResumeBridge(refs, this, this.graphWrite));
    this.toolRound = new ChatToolRoundCtrl(this.delegates, this.askResume);
    // 附件挂载缝域：三闭包箭头延迟求值；attachCallMedia 回接工具轮 record 登记、conn 回接
    // 页面连接现读（能力判据逐请求现读）
    this.toolMedia = new ChatToolMediaCtrl({
      roundHistory: (): AiChatMessage[] => this.keyRound.currentHistory(),
      conn: (): AiConnection | null => this.refs.conn(),
      attachCallMedia: (callId: string, mimeType: string, data: string): boolean =>
        this.toolRound.attachCallMedia(callId, mimeType, data)
    });
    this.resend = new ChatToolResendCtrl(this);
    // Key 池域实参 = delegates；重试域实参 = this（ChatRetryHost 编排位留本件）；闭包箭头
    // 延迟求值，构造序无碍
    this.keyRound = new ChatKeyRoundCtrl(this.delegates);
    this.retry = new ChatRetryCtrl(refs, this);
    // 续写域：宿主面 = this（六方法已公开），行内键经叶子件事件口一跳到达
    this.continueCtrl = new ChatContinueCtrl(refs, this);
    registerContinueHandler((msgId: string): void => this.continueCtrl.continueAt(msgId));
    // 自动重试域实参 = delegates
    this.autoRetry = new ChatAutoRetryCtrl(this.delegates);
    // 快照域：promptState 解析缓存
    this.snapshot = new ChatSnapshotCtrl(this.promptState);
    // 轮次起流域闭包注入（全部箭头延迟求值；读口/组装/起流仍回本件既有私有域件）
    this.roundLauncher = new ChatRoundLauncher({
      buildMemoryBlock: (): Promise<string> => this.snapshot.buildMemoryBlock(),
      buildSkillContext: (designate: string): Promise<SkillSendContext> =>
        this.snapshot.buildSkillContext(designate),
      buildKnowledgeBlock: (draftText: string,
        window: ChatMessage[]): Promise<KnowledgeInjectPlan> =>
        this.snapshot.buildKnowledgeBlock(draftText, window),
      allMessages: (): ChatMessage[] => this.refs.dataSource.allMessages(),
      conversationId: (): string => this.refs.conversationId(),
      isDisposed: (): boolean => this.disposed,
      isSending: (): boolean => this.refs.sending(),
      runToken: (): string => this.runToken,
      isRunActive: (run: RunIdentity): boolean => this.activeRun === run,
      toast: (message: string): void => this.refs.toast(message),
      releaseRun: (): void => this.releaseRun(),
      failRound: (message: string, status: number): void => this.failRound(message, status),
      branch: (): string => this.graphWrite.branch(),
      contextCount: (): number => {
        const advanced: AssistantAdvancedParams | null = this.promptState.advancedParams();
        return advanced !== null && advanced.contextCount !== undefined ? advanced.contextCount : 0;
      },
      assembleFittedRound: (conn: AiConnection, history: AiChatMessage[], memoryBlock: string,
        skillCtx: SkillSendContext, knowledge: KnowledgeInjectPlan, tokenBudget: number,
        windowTokens: number): RoundRequest =>
        this.assembleFittedRound(conn, history, memoryBlock, skillCtx, knowledge,
          tokenBudget, windowTokens),
      loadHistory: (conversationId: string, branchId: string, contextCount: number,
        pathSummary: RequestSummaryInput | null, windowSnapshot: ChatMessage[],
        userReq: AiChatMessage | null, excludeNodeId: string | null): Promise<RequestHistoryResult> =>
        this.reqHist.load(conversationId, branchId, contextCount, pathSummary,
          windowSnapshot, userReq, excludeNodeId),
      startRound: (conn: AiConnection, history: AiChatMessage[], thinking: string,
        sampling: SamplingParams | null): void =>
        this.keyRound.startRound(conn, history, thinking, sampling)
    });
    // 上下文用量域闭包（延迟求值——构造期 refs 先就位再建；箭头持 this，调用时恒可达）
    this.ctxCalc = new ChatContextUsageCalc({
      conn: (): AiConnection | null => this.refs.conn(),
      webDomainAllowed: (): boolean => this.webDomainAllowed(),
      memoryParticipates: (): boolean => this.snapshot.memoryParticipates(),
      buildMemoryBlock: (): Promise<string> => this.snapshot.buildMemoryBlock(),
      // 知识注入计划闭包：面板与实发共用同一 buildKnowledgeBlock——内部绑
      // dataSource.allMessages()（与发送/重试两链同源），对外只露 draftText
      buildKnowledgeBlock: (draftText: string): Promise<KnowledgeInjectPlan> =>
        this.snapshot.buildKnowledgeBlock(draftText, this.refs.dataSource.allMessages()),
      // 活算无「本轮指定技能」（指定属下一轮发送面）——收窄视图由本侧显式构造
      //（ArkTS 禁同构双接口互传）
      buildSkillSnapshot: (): Promise<ContextSkillSnapshot> => this.snapshot.buildSkillContext('').then(
        (c: SkillSendContext): ContextSkillSnapshot => {
          const view: ContextSkillSnapshot = {
            manifest: c.manifest,
            useSkillNames: c.hasEnabled ? c.skillNames : []
          };
          return view;
        }),
      promptSystemText: (model: string): string => {
        const cfg: PromptInjectConfig | null =
          this.promptState.applyVariables(this.promptState.config(), model);
        return cfg !== null ? cfg.content : '';
      },
      advancedParams: (): AssistantAdvancedParams | null => this.promptState.advancedParams(),
      enabledToolIds: (): string[] => this.promptState.enabledToolIds(),
      // MCP 绑定：值源 = promptState 解析缓存——enabledToolIds 注入同形
      mcpServerIds: (): string[] => this.promptState.mcpServerIds(),
      allMessages: (): ChatMessage[] => this.refs.dataSource.allMessages(),
      // 会话级缓存命中的账本聚合键——与用量落库点同一取值口
      conversationId: (): string => this.refs.conversationId(),
      roundConn: (): AiConnection | null => this.keyRound.currentConn(),
      roundHistory: (): AiChatMessage[] => this.keyRound.currentHistory()
    });
    // 轮次请求组装域：实参 = 思考档位读数闭包（refs 延迟求值）+ promptState/ctxCalc 两引用
    //（同构造序先建后注，组装时刻恒已就位）
    this.roundAsm = new ChatRoundAssembly({ thinking: (): string => this.refs.thinking() },
      this.promptState, this.ctxCalc);
    // 发送前异步组装域：snapshot 直注；七闭包箭头延迟求值——dispatchAssembled 回接本件
    // dispatchSend（组装完成即派发），其余闭包均回接本件既有面
    this.sendAssembly = new ChatSendAssembly({
      isDisposed: (): boolean => this.disposed,
      releaseRun: (): void => this.releaseRun(),
      ensureGraphRoute: (): Promise<void> => this.ensureGraphRoute(),
      conversationId: (): string => this.refs.conversationId(),
      allMessages: (): ChatMessage[] => this.refs.dataSource.allMessages(),
      toast: (message: string): void => this.refs.toast(message),
      // 受理后组装失败通知（T4c——转发队列域回滚；按 queueItemId 精确回滚，防 abort 反向
      // 插入时误回滚其他在队项）
      onDispatchAbandoned: (queueItemId: string): void =>
        this.sendGate.onDispatchAbandoned(queueItemId),
      dispatchAssembled: (conn: AiConnection, text: string, attachments: PendingAttachment[],
        payload: AttachmentPayload, memoryBlock: string, skillCtx: SkillSendContext,
        knowledge: KnowledgeInjectPlan, pathSummary: RequestSummaryInput | null,
        queueItemId: string, autoDispatch: boolean): void => {
        this.dispatchSend(conn, text, attachments, payload, memoryBlock, skillCtx,
          knowledge, pathSummary, queueItemId, autoDispatch);
      }
    }, this.snapshot);
    // 发送入口守卫与排队路由域：宿主闭包集回接本件既有面；队列实例与观察者注册随域件构造
    //（attach 成对，disposeSilent 连带注销）
    this.sendGate = new ChatSendEntryGate({
      dbReady: (): boolean => this.refs.dbReady(),
      conn: (): AiConnection | null => this.refs.conn(),
      toast: (message: string): void => this.refs.toast(message),
      sending: (): boolean => this.refs.sending(),
      // 队列派发就绪门（dbReady + conn + 历史装载）
      dispatchReady: (): boolean => this.queueDispatchReady(),
      conversationId: (): string => this.refs.conversationId(),
      lastSettleCause: (): string => this.refs.lastSettleCause?.() ?? 'ok',
      routeState: (): string => this.graphWrite.routeState(),
      ensureGraphRoute: (): Promise<void> => this.ensureGraphRoute(),
      beginRunAcquire: (): boolean => this.beginRunAcquire(),
      clearError: (): void => this.refs.clearError(),
      assembleAndDispatch: (conn: AiConnection, text: string, attachments: PendingAttachment[],
        hasVision: boolean, designateId: string, queueItemId: string,
        autoDispatch: boolean): void =>
        this.sendAssembly.assembleAndDispatch(conn, text, attachments, hasVision, designateId,
          queueItemId, autoDispatch),
      abortActive: (): void => this.abort(),
      attachSendingEdge: (watcher: (sending: boolean) => void): void =>
        this.refs.attachSendingEdge?.(watcher),
      detachSendingEdge: (watcher: (sending: boolean) => void): void =>
        this.refs.detachSendingEdge?.(watcher),
      // ★ Q3 写穿失败归还文本（排队条目落库失败 → 文本回输入条；排队不收附件故空数组）
      restoreSendInput: (text: string): void => this.refs.restoreSendInput(text, [])
    });
    // 流回调与轮次收尾域：构造序末位——六域件引用直注，宿主面经桥接件注入；上方流式态闭包
    // 箭头延迟求值，调用时刻恒已就位
    this.flow = new ChatStreamFlowCtrl(refs, this.flowHostBridge, this.toolRound, this.keyRound,
      this.usageRound, this.autoRetry, this.ctxCalc);
    this.flowReady = true; // 置位即就绪契约（L-E-5）：与赋值成对，此后 flowRef() 才放行
    // 生命周期收尾域接线：构造序末位直注——四域件此刻全数就位，四闭包逐项对应本件既有字段
    this.sendLifecycle = new ChatSendLifecycleCtrl({
      conversationId: (): string => this.refs.conversationId(),
      activeRun: (): RunIdentity | null => this.activeRun,
      markDisposed: (): void => {
        this.disposed = true;
      },
      releaseRun: (): void => this.releaseRun(),
      autoRetry: this.autoRetry,
      resend: this.resend,
      toolRound: this.toolRound,
      flow: this.flow
    });
  }

  // ── 一族到达面：flow/keyRound/toolRound 三私有件经此只读到达（ChatSessionRuntime 持有面；
  // 写面仍全在意图方法与宿主面，禁新增第二写口）。flowRef() 守卫沿用（构造期误调给明确失败）──
  flowCtrl(): ChatStreamFlowCtrl {
    return this.flowRef();
  }

  keyRoundCtrl(): ChatKeyRoundCtrl {
    return this.keyRound;
  }

  toolRoundCtrl(): ChatToolRoundCtrl {
    return this.toolRound;
  }

  // 排队域到达面（Q2b 起实现位在 ChatSendEntryGate——本件薄直通；写面全在队列域意图方法）
  queueCtrl(): ChatSendQueueCtrl {
    return this.sendGate.queueCtrl();
  }

  // 队列派发就绪门：dbReady + conn 解析 + 历史装载三件全真——重启/5s 回收后的 hydrate 首派发
  // 早于进页链就绪，未就绪只让位（不暂停不误 toast，见 ChatSendQueueCtrl.dispatchNext）
  private queueDispatchReady(): boolean {
    return this.refs.dbReady() && this.refs.conn() !== null && this.refs.dataSource.historyLoaded;
  }

  // ── 运行隔离域 ──

  // 接纳（同步）：无活跃 run 才建立占用（ChatRunScope 按会话互斥——双控制器同会话第二活跃
  // run 在此被拒）。false = 调用方以中文提示拒单。adoptRunId 非空 = 接管库内既有 run
  //（ask 等待跨重启续跑；缺省 '' 走原铸造路）
  beginRunAcquire(adoptRunId: string = '', attemptEpoch: number = 1): boolean {
    if (this.activeRun !== null) {
      return false;
    }
    const run: RunIdentity | null =
      chatRunScope.acquire(this.refs.conversationId(), adoptRunId, attemptEpoch);
    if (run === null) {
      return false;
    }
    this.activeRun = run;
    this.runToken = run.conversationId + '|' + run.runId;
    return true;
  }

  // 释放（先失效后释放的「失效」点 = 表删除；幂等）。收尾（finishStream）与销毁
  //（disposeSilent）两路调用；abort 不在此释放——停止收尾仍要经流 onError 回来走
  // failRound（token 在场才放行），释放点提前会把停止主路径的收尾拦死
  releaseRun(): void {
    const run: RunIdentity | null = this.activeRun;
    if (run === null) {
      return;
    }
    this.activeRun = null;
    this.runToken = '';
    this.runCtx = null;
    chatRunScope.release(run.conversationId, run.runId);
  }

  // attempt 换代（Key 池失败切换 / 自动重试重发；工具续轮不调——I5）：推进 ChatRunScope
  // 内 attemptEpoch；activeRun 持同一 identity 引用，attemptId 自动同步
  nextAttempt(): void {
    const run: RunIdentity | null = this.activeRun;
    if (run === null) {
      return;
    }
    chatRunScope.nextAttempt(run.conversationId, run.runId);
  }

  // 当前 attemptId（createNativeStream 身份快照与 finishStream 账本归属快照消费）
  currentAttemptId(): string {
    return this.activeRun !== null ? this.activeRun.attemptId : '';
  }

  // 流回调身份核验（isRoundAlive）在 ChatStreamFlowCtrl（createNativeStream 唯一消费方；
  // 核验面经宿主面 isDisposed/currentRunToken/currentAttemptId 到达）

  // 执行上下文构造（轮首一次快照；值源 = promptState 解析缓存与活跃 run，值随链下传执行器
  // 零中转）。assistantId 回填活跃 run（I8 契约字段）
  private buildExecutionContext(): ToolExecutionContext {
    const run: RunIdentity | null = this.activeRun;
    const assistantId: string = this.promptState.effectiveAssistantId();
    if (run !== null) {
      chatRunScope.bindAssistant(run.conversationId, run.runId, assistantId);
    }
    // 工具图计数清零（本方法 = 发送/重试轮首唯一构造点——计数器与构造同拍归零，单发送有界
    // 语义由本点保证；实现在 ChatToolMediaCtrl.resetForRound）
    this.toolMedia.resetForRound();
    const convId: string = this.refs.conversationId();
    // 视觉门控快照：判据 = 发送链同款 hasVisionCap，值源 = 当前连接随行 caps
    //（resolveActiveConnection 唯一填充点，与页面视觉门控同源同值）；无连接或 caps
    // undefined → 恒 false
    const caps: string = this.refs.conn()?.caps ?? '';
    const ctx: ToolExecutionContext = {
      scope: TOOL_SCOPE_CHAT,
      conversationId: convId,
      runId: run !== null ? run.runId : '',
      // ★ 口径登记：attemptId = 接纳时快照，换代（nextAttempt）后**不刷新**——消费方须现读
      // live 值（activeRun.attemptId / 宿主 currentAttemptId），禁以 ctx.attemptId 当「当前
      // attempt」判据（全仓当前零消费，纯口径登记）
      attemptId: run !== null ? run.attemptId : '',
      // 归属助手本体 id：HTTP 凭据按助手命名空间解析的 owner——与上面 bindAssistant 同值
      // 同源（effectiveAssistantId），非 memoryScope/knowledge 两特化语义
      assistantId: assistantId,
      memoryScopeAssistantId: this.promptState.memoryScope() === MEMORY_SCOPE_ASSISTANT ?
        this.promptState.ownerAssistantId() : '',
      knowledgeAssistantId: this.promptState.ownerAssistantId(),
      searchResultCount: this.promptState.searchResultCount(),
      isRunActive: (runId: string): boolean => {
        const cur: RunIdentity | null = this.activeRun;
        return cur !== null && cur.runId === runId && !this.disposed &&
          chatRunScope.isActive(convId, runId);
      },
      // 工具图挂载接缝：两闭包本体在 ChatToolMediaCtrl，此处薄壳委托（挂载逻辑/预算闸/
      // 不计数口径全在彼件；字段契约见 MessageContracts）
      hasVision: caps !== '' && hasVisionCap(caps),
      collectImage: (mimeType: string, data: string): boolean =>
        this.toolMedia.collectImage(mimeType, data),
      collectPageImage: (mimeType: string, data: string): boolean =>
        this.toolMedia.collectPageImage(mimeType, data),
      // 预检便签基础值（copy_in TOCTOU 笔）：轮内由预检循环在派生件上写、执行器读同对象
      //（信道见 MessageContracts 字段注释）——基础上下文恒空串是本处纪律（在基础件上写值
      // 会跨调用串写）
      preflightMemo: ''
    };
    return ctx;
  }

  // 重试域宿主面（ChatRetryHost）：重试轮与发送轮同走占用闸（方法名带 current 前缀——与
  // 字段 runToken 区分，ArkTS 禁成员同名）
  currentRunToken(): string {
    return this.runToken;
  }

  // ChatRetryHost.acquireRun 实现位（薄直通——重试域接口名与内部方法名对齐）
  acquireRun(): boolean {
    return this.beginRunAcquire();
  }

  // ── 图会话写侧宿主委托位（编排体在 ChatGraphWriteCtrl——ChatRetryHost 扩展与
  // ChatHostAccess 消费的薄直通）──

  // ChatToolRoundHost：图态判据（工具轮持久化分流——blocked 早退后轮内恒 graph，
  // 防御性保留判据）
  isGraphMode(): boolean {
    return this.graphWrite.isMode();
  }

  // ChatRetryHost：路由二值读取（retryAt 拒写判据——与 dispatchSend 的 blocked 早退同源；
  // 判据与呈报在重试域，本件薄直通，早退本体在 ChatRetryCtrl）
  routeState(): string {
    return this.graphWrite.routeState();
  }

  // 写侧路由镜像探针上行（实现位在 ChatGraphWriteCtrl——页面加载链读到的路由经此同步进
  // 写侧镜像，发送入口的同步闸才有真值可读，见彼件注释）
  publishRouteProbe(route: string): void {
    this.graphWrite.publishRouteProbe(route);
  }

  // ChatRetryHost：路由装载（重试轮首；写入口语义——读路由 + 读分支，无行则出生即 graph）。
  // sessionOverride 透传（S11：发送首条建行时落覆盖三列；重试轮行必已在 = 恒 null 零开销）
  ensureGraphRoute(): Promise<void> {
    return this.graphWrite.loadRoute(this.refs.conversationId(),
      this.promptState.effectiveAssistantId(), this.promptState.promptOverrideId(),
      this.refs.sessionOverride());
  }

  // 活跃 runId（beginGraphRetry → 图域 prepareRetryRun 身份）
  currentRunId(): string {
    return this.activeRun !== null ? this.activeRun.runId : '';
  }

  // ChatRetryHost：释放占用（重试图分支守卫失败归还）
  releaseRunWithGuard(): void {
    this.releaseRun();
  }

  // 重试图分支起轮（薄委托——编排体在域件；onBranchSwitched 回调切数据源路径锚）
  beginGraphRetry(targetMsgId: string): Promise<boolean> {
    return this.graphWrite.beginRetry(this.refs.conversationId(), this.currentRunId(),
      this.promptState.effectiveAssistantId(), targetMsgId,
      (branchId: string): void => {
        this.refs.dataSource.reanchorBranch(branchId);
      });
  }

  // 中间轮 assistant 节点提交（ChatToolRoundHost 消费，经 delegates；域② placeholderNodeId
  // 透传写侧「更新既有占位行」收口）
  private graphCommitRoundAssistant(content: string, reasoning: string, stepIndex: number,
    stampTarget: ChatMessage | null, placeholderNodeId: string): Promise<boolean> {
    return this.graphWrite.commitRoundAssistant(content, reasoning, stepIndex, stampTarget,
      placeholderNodeId);
  }

  // 工具结果节点提交（ChatToolRoundHost 消费，经 delegates）
  private graphCommitToolNode(record: ToolEventRecord, stepIndex: number): Promise<boolean> {
    return this.graphWrite.commitToolNode(record, stepIndex);
  }

  // 工具事实：派发前意图（活跃运行身份随链）
  private graphToolFactDispatch(name: string, argsJson: string): Promise<string> {
    const run: RunIdentity | null = this.activeRun;
    if (run === null) {
      return Promise.reject(new Error('活跃运行缺失，无法登记工具意图'));
    }
    return this.graphWrite.toolFactDispatch(run.runId, run.attemptId, name, argsJson);
  }

  // 工具事实：结果确认 / 失败终态（factId 空 = 意图未落成，静默跳过）
  private graphToolFactConfirm(factId: string, result: string, failed: boolean): Promise<void> {
    const run: RunIdentity | null = this.activeRun;
    return this.graphWrite.toolFactConfirm(factId, run !== null ? run.runId : '',
      run !== null ? run.attemptId : '', result, failed);
  }

  // ── 工具卡重发域宿主实现位（ChatResendHost——全部薄直通，编排体在 ChatToolResendCtrl）──

  isSending(): boolean {
    return this.refs.sending();
  }

  isDbReady(): boolean {
    return this.refs.dbReady();
  }

  conversationId(): string {
    return this.refs.conversationId();
  }

  toast(message: string): void {
    this.refs.toast(message);
  }

  dataSource(): ChatDataSource {
    return this.refs.dataSource;
  }

  setSending(sending: boolean): void {
    this.refs.setSending(sending);
  }

  followToBottom(): void {
    this.refs.follow.forceToBottom();
  }

  // 重发占用接纳（beginRunAcquire 成功后 activeRun 即重发身份——随返回值带出）
  acquireResendRun(): RunIdentity | null {
    return this.beginRunAcquire() ? this.activeRun : null;
  }

  releaseResendRun(): void {
    this.releaseRun();
  }

  // 重发执行上下文（接纳后调用 buildExecutionContext 即产出重发 run 身份的 ctx，禁第二份构造）
  buildResendContext(): ToolExecutionContext {
    return this.buildExecutionContext();
  }

  effectiveAssistantId(): string {
    return this.promptState.effectiveAssistantId();
  }

  graphBranch(): string {
    return this.graphWrite.branch();
  }

  // 重发公共入口（ChatPage 注入回调落点——msgId 仅日志面用途，执行以 slug + argsJson 为准）
  resendTool(msgId: string, slug: string, argsJson: string): void {
    this.resend.startResend(msgId, slug, argsJson);
  }

  // ── 流回调域宿主面（ChatFlowHost）——isDisposed/currentRunToken/releaseRun 三法由既有
  // 宿主位同口径复用；实现位整体在 ChatFlowHostBridge ──

  // 失败呈报薄委托（实现体在 ChatStreamFlowCtrl.failRound）
  failRound(message: string, status: number): void {
    this.flow.failRound(message, status);
  }

  // 原生流构造薄委托（唯一流工厂——原 Cube 分流姊妹口已随退役笔删除）
  createNativeStream(conn: AiConnection): ChatStream {
    return this.flow.createNativeStream(conn);
  }

  // 节流缓冲复位薄委托（节流器域在 ChatStreamFlowCtrl，语义见彼件同名方法）
  resetAppendBuffer(): void {
    this.flow.resetAppendBuffer();
  }

  // 流式正文权威只读口已于 2026-11-05 菜单笔退役：唯一调用方 = 消息菜单 body 场景的
  // 「查看正文」（经 ChatPage → ChatPageContent.openBodySnapshot）；该场景随两处省略号入口
  // 一并删除后，长按全文面板在 openMsgCopySheet 内自守「流式中不弹」，不再需要本口。

  // 提示词注入预载（打开会话调一次 + 面板选择后刷新；load 完成后写「联网可用」广播键）
  loadPromptState(conversationId: string): Promise<void> {
    return this.promptState.load(conversationId);
  }
  // 面板助手覆盖透传 + 有效绑定读取（逻辑在 ChatPromptState）
  setBoundOverride(assistantId: string): void {
    this.promptState.setBoundOverride(assistantId);
    // 广播解析输入变化——无行会话的有效归属 = 面板覆盖 ?? 当前助手 ?? 默认，覆盖变化即②级
    // 输入变化，切回直接发送须重解析
    AppStorage.setOrCreate<number>(CONN_RESOLVE_TICK_KEY,
      (AppStorage.get<number>(CONN_RESOLVE_TICK_KEY) ?? 0) + 1);
  }
  // 有效归属读取（ChatPromptSheet 助手卡显示态：面板覆盖 ?? 当前助手 ?? 内置默认；归属与
  // 注入解耦，不受提示词覆盖影响）
  boundAssistantId(): string {
    return this.promptState.effectiveAssistantId();
  }
  // 归属助手启用工具 id 清单（解析缓存现读，与发送组装 dispatchSend 同一份真源；只读——
  // chip 改会话级覆盖，不写回本清单）
  enabledToolIds(): string[] {
    return this.promptState.enabledToolIds();
  }
  // 会话归属助手是否启用 AI 配置域任一件（原 isConsoleOwner 判据改挂 AI 配置域启用位——
  // 安全输入 chip 与暂存条显隐的解析源）
  aiAdminToolsEnabled(): boolean {
    return this.promptState.aiAdminToolsEnabled();
  }
  // 面板提示词引用覆盖透传 + 当前覆盖读取（无行会话的引用覆盖纯内存持有，解析优先级见
  // ChatPromptState.promptOverride 注释）
  setPromptOverride(promptId: string): void {
    this.promptState.setPromptOverride(promptId);
  }
  promptOverrideId(): string {
    return this.promptState.promptOverrideId();
  }
  // 会话状态快照：「会话状态」半模态「请求注入」卡取数单源——组装与判别全在
  // ChatPromptState.statusSource（本处一枚薄口，照 boundAssistantId 先例）
  statusSource(): ChatStatusSource {
    return this.promptState.statusSource();
  }
  // ── 上下文压缩供给：ChatPage 压缩面板/用量卡 refs 薄取值口（promptState 私有经此透传）──
  assistantClipLimit(): number { return this.promptState.advancedParams()?.contextCount ?? 0; }
  // 本轮指定技能写入：页面发送漏斗（ChatPage.sendWithAttachments）首行调——两发送入口与
  // 视觉确认路径共用同一漏斗，挂一处即全覆盖；每次发送恒写（'' = 无指定，无残留）
  setSkillDesignate(id: string): void {
    this.designateId = id;
  }
  // 联网开关可用性：当前助手启用清单是否含 search_web = **能不能联网的能力上限**（页面
  // refreshWebSearchFlag 据此写闸键；本方法纯读）
  webSearchAllowed(): boolean {
    return this.promptState.enabledToolIds().includes(TOOL_SEARCH_WEB);
  }

  // 联网域可用性（单向绑定唯一判定源）：助手启用清单含 search_web（能力上限）∩ 本会话联网
  // 开关（会话级临时关），两源合取（全局总开关已退役恒开——见 AppPreferences 联网域注释）。
  // false = 模型收不到联网域两件声明——「读取网页」不单列开关，随域可用性：用户「我不想
  // 联网」的口径覆盖它（会话级/助手级两维声明层全责，竞品同向）
  private webDomainAllowed(): boolean {
    return this.webSearchAllowed() && this.refs.webSearchOn();
  }

  // 会话上下文用量活算：面板打开/轮完成/切模型三处调用（打字与生成中不刷）；编排与口径在
  // ChatContextUsageCalc，本方法只是宿主门面（页面不直接持 calc）。待发附件数组与 hasVision
  // 随参带入（页面当场值）——图片张数分流判据单源在 AttachmentUtil.pendingAttachFootprint
  computeContextUsage(draftText: string, attachments: PendingAttachment[],
    hasVision: boolean): Promise<ContextUsage> {
    return this.ctxCalc.computeLive(draftText, attachments, hasVision);
  }

  // 发送三参入口（守卫与排队路由在 ChatSendEntryGate——true = 已投递或已入队，false = 未投递/
  // 入队拒绝；入队语义见彼件 send/sendEntry 注释）
  send(text: string, attachments: PendingAttachment[], hasVision: boolean): boolean {
    // 本轮指定技能快照：组装链异步串行，组装期间页面仍可改指定——晚读会把「后改的值」注进
    //「先发的那条消息」（静默串轮）。故在投递入口一次取值随链下传，与 text/attachments 同口径
    const designateId: string = this.designateId;
    return this.sendGate.send(text, attachments, hasVision, designateId);
  }

  // 派发发送（附件载荷已就绪）：条件清理 → 双文本合成（展示 = 文本+附件标注+指定标注，
  // DB/气泡均此形态；协议 = 指定正文块+引用块+文本+文本附件内容，仅当前轮——正文与附件
  // 本体仅随本轮请求，历史轮不重发；引用块由 composeQuotedContent 单源拼装且不落库，
  // 引用全文独立存 quote_text 列、历史轮经 ChatHistoryBuilder 重建同形态）→ 历史快照 →
  // 注入 → 占位气泡 → 入库（附件元数据行随 user 行）→ 池轮次。
  // memoryBlock = 记忆注入块快照（send 链派发前现读；'' = 不注入）
  // skillCtx = 技能上下文快照（清单 + 是否声明 use_skill + 本轮指定正文块与名；manifest ''
  // + false + 两空 = 不注入不声明）
  // knowledge = 知识注入计划快照（send 链派发前现读；空 plan = 不注入零回归）
  // ★ queueItemId = 队列条目 id（'' = 手动/重试路径；非空随 beginSend 贯通，事务删行消费）；
  // autoDispatch = 自动出队（非「立即发送」）——拽底判读用
  private dispatchSend(conn: AiConnection, text: string, attachments: PendingAttachment[],
    payload: AttachmentPayload, memoryBlock: string, skillCtx: SkillSendContext,
    knowledge: KnowledgeInjectPlan, pathSummary: RequestSummaryInput | null,
    queueItemId: string, autoDispatch: boolean): void {
    // 待发引用快照 + 排队护栏：手动/立即发送在此一次快照，后续协议组装/实时行挂值/落库全用
    // 本快照（异步窗口页面改挂引用不串轮——照 designateId 入口快照口径）；**autoDispatch（队列
    // 出队自动派发）强制置空一行护栏**——入队消息的文字先于引用挂载，出队时读「当前」
    // pendingQuote 会把窗口期挂上的下一条引用错配给本条并误清（双害）：排队消息只发文字，
    // 窗口期新挂引用留给下一条（方案档 §3.2 裁定加；真机清单 13）
    const quoteSnapshot: string = autoDispatch ? '' : this.refs.pendingQuote();
    // 旧格式墓碑会话拒发：位次 = **一切破坏性动作之前**——占位气泡未 push、轮次态未改，
    // 尤其**先于附件清理**（本轮未发送，文字与附件经 restoreSendInput 原样还给用户——闸若在
    // 附件清理之后，缩略图已释放、页面侧两列表已清，归还失能）。判据 = 装载后的真值（镜像未
    // 装载不判 blocked，见 ChatGraphWriteCtrl），故此处拒发即真拒发；文案收编为单句墓碑短句
    if (this.graphWrite.routeState() === ROUTE_BLOCKED) {
      this.refs.restoreSendInput(text, attachments);
      this.refs.toast(TOMBSTONE_TOAST_TEXT);
      // ★ 总案 Q1 T4c：受理后无 setSending 写的失败出口——队列 IN_FLIGHT 项回滚
      //（非队列派发 queueItemId = '' 时零动作）
      this.sendGate.onDispatchAbandoned(queueItemId);
      this.releaseRun();
      return;
    }
    // 条件清理（拍板：发送不再即删——文件留盘供会话内预览）：仅载荷组装失败（判定 = 有附件
    // 但标注空——失败降级时附件未随消息发送）→ 全清（缩略图 + 文件，「未随消息发送的附件
    // 不驻留」）；其余 → 仅释放缩略图，文件留盘（filesDir 常驻，供历史气泡与预览消费）
    if (attachments.length > 0 && payload.annotate === '') {
      cleanupAttachments(attachments);
    } else {
      releaseAttachmentThumbs(attachments);
    }
    // 附件已随消息发送（载荷成功且有附件）——入库侧据此构建元数据行（失败恒空数组）
    const attachSent: boolean = attachments.length > 0 && payload.annotate !== '';
    const annotate: string = payload.annotate;
    // 本轮指定技能标注：显示面恒带（气泡/DB/历史 = 「本条用了哪件技能」的可见痕迹）；协议面
    // 只在「用户零文本」时代位（正文块自带技能名，不重复）；零指定 = '' 零开销
    const designateMark: string = composeSkillDesignateMark(skillCtx.designatedName);
    // 展示/DB/气泡：用户文本 + 指定标注 + 附件标注——三值经 joinNonEmptyParts 单入口拼接，
    // 零指定时逐字等于旧两值式（空段过滤语义与旧三目逐例等价）。★ 附件标注必须留在**尾部**
    //——气泡渲染靠 hideAttachAnnotate 的「尾部逐字吻合」才剥得掉它（库内不改写、只在气泡
    // 渲染时隐去；纯附件消息剥到空串还是「气泡整只不渲染」的判定前提），指定标注按设计恒带
    // 显示面。顺序错在「附件 + 指定」同现时会把附件标注挤离尾部 → 剥不掉 → 用户气泡漏出
    //「[附件] 名单」行（只附件无指定时无此现象）；改序后两种组合气泡都只剩「用户文本 +
    // 指定标注」，附件仍以卡片呈现。
    const displayText: string = joinNonEmptyParts([text, designateMark, annotate]);
    // 纯附件发送且载荷组装全失败 → 无可发内容：notice 提示不发空请求（有文本不进此支）
    // ★ 只指定不打字也发得出：displayText = 标注句非空 → 过此守卫（竞品「空消息 400」防法）
    if (displayText === '' && payload.images.length === 0) {
      this.refs.dataSource.push(newChatMessage(nextMessageId('notice'), 'notice', '附件处理失败，消息未发送'));
      // ★ T4c：同上——受理后无 setSending 写的失败出口（防 IN_FLIGHT 死项）
      this.sendGate.onDispatchAbandoned(queueItemId);
      this.releaseRun(); // 未起轮早退——归还占用（失败准备也归还）
      return;
    }
    const append: string = payload.protocolAppend;
    // 暂存密钥提示段：暂存槽非空**且归属助手启用清单含 manage_providers**时才随本轮 user
    // 协议文本尾段——句内教的 assign_key 动作必须真实可用，防「模型被喂不拥有的能力声明」
    //（幻觉调用不存在的工具 / 无关会话被噪声）。判据走 enabledToolIds() 解析缓存（load 未
    // 解析完的窄窗口 = 清单空 = 不注入，良性向）；KeyStore 单源，句内只带尾号掩码零明文；
    // displayText 不拼（气泡/DB/历史不带），仅本轮随请求（同附件语义，历史轮不重发）
    const pendingNote: string = this.enabledToolIds().includes(TOOL_MANAGE_PROVIDERS) ?
      composePendingKeyNote(getPendingKey()) : '';
    // 协议（仅本轮）：指定技能正文块在最前（技能正文属「做法指令」放用户话之前，附件属
    //「材料」放用户话之后）→ 引用块+用户原话（composeQuotedContent 单源拼 blockquote 前缀
    //——与历史重建（ChatHistoryBuilder 调用点②）同函数，首发与重试轮逐字一致；无引用
    //（quoteSnapshot = ''）时函数原样返回，零文本时以标注句代位：「本轮就用这件技能」的
    // 最小指令，且保证 user 内容非空）→ 附件内容 → 暂存密钥提示段。零指定且槽空且无引用时
    // 逐字等于旧两值式（负向钉——引用块不落库：content 恒存原文、引用独立存 quote_text，
    // 历史轮经组装层重建同形态）
    const protocolText: string = joinNonEmptyParts([skillCtx.designatedBlock,
      composeQuotedContent(quoteSnapshot, text !== '' ? text : designateMark),
      append, pendingNote]);
    // 行时间走单调分配器（消灭裸 Date.now() 与 now+1 让位的并列风险；附件行时间同取本值 =
    // 与 user 行同刻，附件非 messages 行不铸 seq）；本轮 user 协议消息要带同一时刻（见下方
    // userReq）。assistantNow 分支外先取：与落库行同源同值共用（细则见 ChatMessage.createdAt 注释）
    const now: number = nextRowCreatedAt();
    const assistantNow: number = nextRowCreatedAt();
    // 请求历史来源：解耦开（默认）= 历史按「助手上下文条数 + 模型窗口 token」双闸从库独立
    // 读取，组装与开流后移到 beginSend 回执之后（用户气泡先上屏、读库后台完成——历史条数
    // 不再取决于页面窗口装了多少）；解耦关 = 旧链（窗口 allMessages + push 本条 + 组装内二次
    // 截取）逐字节保留（Theme.REQUEST_HISTORY_DECOUPLE_ENABLED 一行回退）。组装域在
    // ChatHistoryBuilder（reasoning 配对与回传口径见该文件与 RequestCompose）。
    // pathSummary：图摘要滑出读窗时的库直查注入值（send 链路由装载后取得）
    const userReq: AiChatMessage = { role: 'user', content: protocolText, createdAt: now }; // 与落库行同源同值（间隔提醒的触发判定读消息自身 createdAt，缺它 = 本轮恒不提醒）
    if (payload.images.length > 0) {
      userReq.images = payload.images;
    }
    // 降级快照（解耦链）：必须在 push 两行**之前**取——push 之后取会把本条 user 重复带入
    //（读库失败时以此组装——唯一硬坑）；旧链不消费（窗口现读）
    const windowSnapshot: ChatMessage[] = this.refs.dataSource.allMessages().slice();
    // 旧链（解耦关）：窗口组装 + 组装轮 + 复位组全在同步段（assembleFittedRound 预算传 0 =
    // fitTokens 原引用直通；assemble 与复位仍先于 push，startRound 仍在 beginSend 回执）
    let legacyReq: RoundRequest | null = null;
    if (!REQUEST_HISTORY_DECOUPLE_ENABLED) {
      const legacyHistory: AiChatMessage[] =
        buildRequestHistory(this.refs.dataSource.allMessages(), pathSummary);
      legacyHistory.push(userReq);
      legacyReq = this.assembleFittedRound(conn, legacyHistory, memoryBlock, skillCtx, knowledge, 0);
    }

    const userMsg: ChatMessage = newChatMessage(nextMessageId('msg'), 'user', displayText);
    // 附件简报装配：已随消息发送（载荷成功且有附件）即装；push 前赋值使首帧即带简报
    if (attachSent) {
      userMsg.attachBriefs = briefsFromPending(attachments);
    }
    // 待发引用实时行挂值：快照非空即挂——回放/实时同址纪律（回放挂值在 chatMessagesFromRows，
    // 库列真源 quote_text；与 attachBriefs 同通道同先例：@Observed 对象级观察驱动渲染，U-E
    // 摘要条消费）；push 前赋值使首帧即带
    if (quoteSnapshot !== '') {
      userMsg.quoteText = quoteSnapshot;
    }
    const assistantMsg: ChatMessage = newChatMessage(nextMessageId('msg'), 'assistant', '');
    userMsg.createdAt = now;
    assistantMsg.createdAt = assistantNow;
    // 轮级模型名同址写：本轮轮头行模型名的实时真值（重进会话由账本回填覆盖同语义，见
    // ChatPageLoad.attachUsageMeta）
    assistantMsg.modelLabel = conn.model;
    // 实时行标记（A3）：两行 id 均为内存 id，图身份只认后续 stampNodeRef 回填（live 注释）
    userMsg.live = true;
    // 流式运行时标记：占位起底栏不现（拍板 1a），finishStream/工具轮中间行收尾置 false；
    // tail 由数据源 push 维护
    assistantMsg.streaming = true;
    assistantMsg.live = true;
    // 展示轮登记：整轮稳定身份 = currentRunToken()（conversationId|runId，attempt 切换不换
    // run），输入锚 = userMsg 内存 id，holder = 占位行。位次 = 两行构造标记完成后、首次 push
    // 之前——不晚于 holder 上屏（段分组与操作栏都读它）、不早于 userMsg 存在（输入锚）、不等
    // setSending(true)（dispatchSend 全程在整轮内）。准备失败且未产生 holder 的路径不登记
    //（failRound 前的 run/branch 守卫早退不动旧轮）
    this.refs.dataSource.beginDisplayRound(this.currentRunToken(), userMsg.id, assistantMsg);
    this.refs.dataSource.push(userMsg);
    this.refs.dataSource.push(assistantMsg);
    // 流式轮开始：绑 id 并同拍清思考 id 与两累积串（流域意图方法，配对约束在流域方法体）
    this.flow.beginStreamRound(assistantMsg.id);
    this.refs.setSending(true);
    // ★ 拽底判读：自动出队路径在用户持阅读位时跳过拽底——新消息按既有「用户滚开不打扰」
    // 机制呈现；跟随态照常拽底。手动发送与「立即发送」恒拽底（autoDispatch = false：UI 入口
    // 与 JUMP_PENDING 派发都是用户动作口径）
    if (!autoDispatch || !this.refs.follow.userHoldsReadingPosition()) {
      this.refs.follow.forceToBottom();
    }

    // 发送即入库（user done / assistant streaming——中断恢复口径；失败切换不重复入库）；首条
    // 消息落行写入会话归属助手（有效绑定 = 面板覆盖 ?? 当前助手）。图路径（K5：发送先提交
    // user 事实再开流——prepareRun 失败不具备开流资格）；legacy 双行入库编排已随线性写路径
    // 退役——上方 blocked 早退后路由只剩 graph，本段即唯一入库路径。图前置缺失（理论不达：
    // blocked 已拦非 graph 态，graph 态经 F3 保证分支非空）时 fail-closed 不起轮
    const run: RunIdentity | null = this.activeRun;
    const convIdGraph: string = this.refs.conversationId();
    if (run === null || this.graphWrite.branch() === '') {
      // ★ T4c 补口：本支在 setSending(true) 之后（sending 真→假为真下降沿，但队列 IN_FLIGHT
      // 项 + dispatchLatch 不因沿自然收口——latch 由派发失败路径显式清）
      this.sendGate.onDispatchAbandoned(queueItemId);
      this.failRound('消息保存失败，未开始生成', 0);
      return;
    }
    // K4 空串占位：graph 附件资源行 messageId = ''（归属恒经 refs，J7）；行与 refs 随
    // graphBeginSend 落库（附件行落库在域件内）
    const attachRows: MessageAttachmentRow[] = attachSent ?
      buildAttachmentRows(attachments, '', convIdGraph, now) : [];
    const beginInput: PrepareRunInput = {
      runId: run.runId,
      conversationId: convIdGraph,
      branchId: this.graphWrite.branch(),
      assistantId: this.promptState.effectiveAssistantId(),
      userContent: displayText,
      // 待发引用独立落 quote_text 列——content 恒存原文（displayText 不含引用块），
      // undefined = 无引用列落 NULL
      quoteText: quoteSnapshot !== '' ? quoteSnapshot : undefined,
      origin: ORIGIN_SEND,
      now: now
    };
    this.graphWrite.beginSend(beginInput, attachRows, queueItemId)
      .then((start: GraphSendStart): void => {
        // ★ T4a：beginSend resolve = 排队行已在 prepareRun 事务内与 user 行 + run 行同笔删除
        //——队列条目投递确认（出队 + 清闩）。先于 disposed 分支摘除：事务已提交，条目出队属
        // 事实收口（非队列派发 queueItemId = '' 时零动作）
        this.sendGate.onDispatchCommitted(queueItemId);
        // 待发引用清空点：beginSend resolve = user 行已落库、引用已持久化进 quote_text——此刻
        // 清待发态才安全（事实收口，先于 disposed 分支同上理）。**冻结比对**：pendingQuote()
        // === quoteSnapshot 才清——异步窗口内用户改挂了别的引用则不清（清了会吞新引用）。失败
        // 路径一律不清（「不清空即保留」天然成立）：墓碑拒发 / 空守卫 / 图前置缺失 / beginSend
        // reject（事务原子回滚 user 事实未落，清空会丢引用）；排队入队不是「发送成功」（出队
        // 走 autoDispatch 护栏不消费）；中途停止/流式失败与内存态无关（引用已在 quote_text，
        // 重试轮经历史重建天然带引用）
        if (quoteSnapshot !== '' && this.refs.pendingQuote() === quoteSnapshot) {
          this.refs.clearPendingQuote();
        }
        if (this.disposed) {
          this.releaseRun();
          return;
        }
        // ★ 迟到回执守卫：提交窗口内发生 abort / 立即发送时本轮 run 已被 finishStream 释放
        //（activeRun 已换人或为空）——迟到回执不得在新轮身份下开流（两请求/串轮风险），也不
        // 得误释放他人 run
        if (this.activeRun !== run) {
          return;
        }
        // 内存行库身份回填（实现与理由见 ChatGraphWriteCtrl.stampNodeRef）
        ChatGraphWriteCtrl.stampNodeRef(userMsg, start.userNode);
        upgradeTitlePlaceholder(this.refs.conversationId(), text);
        clearConversationSuggestions(this.refs.conversationId());
        // 开流分叉：解耦开 = 轮后段（读库 → 组装 → token 双闸 → 复位 → 开流——读库沿本条
        // user 节点为排除游标，prepareRun 已把 head 前移到它；失败走 failRound 错误卡，不撤
        // 气泡不还原输入）；解耦关 = 旧链同步段产物直接开流（reset 组已在同步段随
        // assembleFittedRound 跑完）
        if (REQUEST_HISTORY_DECOUPLE_ENABLED) {
          this.roundLauncher.launchSendRound(conn, run, start.userNode.nodeId, windowSnapshot,
            userReq, memoryBlock, skillCtx, knowledge, pathSummary)
            .catch((e: Object): void => {
              hilog.error(0x0001, 'ChatSend', '解耦轮后段失败：%{public}s', (e as Error).message);
              this.failRound('请求组装失败，本轮未生成', 0);
            });
        } else if (legacyReq !== null) {
          // P2 小窗前置拦截（旧链窗口传 0 = 不判，blockReason 恒空——kill 回退态语义，判语句
          // 保留与解耦链同构）
          if (legacyReq.blockReason !== undefined && legacyReq.blockReason !== '') {
            this.failRound(legacyReq.blockReason, 0);
            return;
          }
          this.keyRound.startRound(conn, legacyReq.history, legacyReq.thinking, legacyReq.sampling);
        }
      })
      .catch((e: Object): void => {
        hilog.error(0x0001, 'ChatSend', '图发送准备失败：%{public}s', (e as Error).message);
        // ★ T4c：prepareRun 事务失败 = 排队行未删、user 事实未落（数据库层原子回滚）——交
        // 队列回滚链（按 queueItemId 回队头 + 清闩 + PAUSED('delivery') + toast；非队列派发
        // 零动作），本轮由 failRound 收尾呈报；不接则 IN_FLIGHT 死项 + latch 恒真 = 队列停摆
        this.sendGate.onDispatchAbandoned(queueItemId);
        this.failRound('消息保存失败，未开始生成', 0);
      });
  }

  // 组装 + token 双闸 + 复位 共用后段（发送轮后段 / 发送旧链同步段 / 重试组装段三消费方
  // 单源——「禁第二条请求链」锚点：assembleRound 全件唯一调用字面在此，历史来源三态
  //〔库读 / 窗口快照 / 窗口旧链〕都在调用方成形）。tokenBudget ≤ 0（无窗口参考值 / kill
  // 旧链）= fitTokens 原引用直通 = 与旧序零差异。复位组（工具轮 / 执行上下文 / 轮次用量 /
  // 自动重试）与旧序同位：紧跟组装、先于开流。
  private assembleFittedRound(conn: AiConnection, history: AiChatMessage[],
    memoryBlock: string, skillCtx: SkillSendContext, knowledge: KnowledgeInjectPlan,
    tokenBudget: number, windowTokens: number = 0): RoundRequest {
    // windowTokens = 小窗前置检查的窗口原值（tokenBudget 是裁剪预算 ≠ 窗口）；0 = 旧链/不判
    const req: RoundRequest =
      this.roundAsm.assembleRound(conn, history, memoryBlock, skillCtx, knowledge, windowTokens);
    const fit: TokenFitResult = this.reqHist.fitTokens(req.history, toolDefsJsonOf(req.tools),
      tokenBudget, { providerId: conn.providerId, model: conn.model });
    this.toolRound.resetForNewSend(req.tools, this.promptState.toolStepLimit());
    // 执行上下文构造：值在接纳后一次快照随链下传（值源 = promptState 同链解析缓存，与
    // 本轮 toolStepLimit 同一次解析同一助手）
    this.runCtx = this.buildExecutionContext();
    // 整轮用量累积器清零（轮首唯一清零点）+ 自动重试域同点清零
    this.usageRound.reset();
    this.autoRetry.resetForRound();
    if (fit.clipped) {
      hilog.info(0x0001, 'ChatSend', 'token 双闸裁剪生效（估算 %{public}d）', fit.estimatedTokens);
      return { history: fit.history, thinking: req.thinking, sampling: req.sampling, tools: req.tools };
    }
    return req;
  }

  // 重试唯一入口（薄委托——行为面全在 ChatRetryCtrl；retryLast 末轮专用链已随 rik 形态统一
  // 退役，本口目标为任意已收尾 assistant 轮（含末轮），nodeId = 该消息的图身份；锚点定位与
  // 路径换源全在 ChatRetryCtrl.retryAt）
  retryAt(nodeId: string): void {
    this.retry.retryAt(nodeId);
  }

  // ── 续写域宿主实现位（ChatContinueHost——编排体在 ChatContinueCtrl）──
  continueAt(msgId: string): void {
    this.continueCtrl.continueAt(msgId);
  }

  beginContinueRun(nodeId: string): Promise<boolean> {
    // 起 run（同分支新 run 行）+ 目标节点回流式态（提交路径谓词要求 status='streaming'）
    return this.graphWrite.beginContinue(this.refs.conversationId(), this.currentRunId(),
      this.promptState.effectiveAssistantId(), nodeId)
      .then((ok: boolean): Promise<boolean> =>
        ok ? this.graphWrite.reopenNode(nodeId) : Promise.resolve(false));
  }

  beginContinueStreaming(msgId: string, prefixText: string, nodeId: string): void {
    this.flow.beginContinueRound(msgId, prefixText, nodeId);
    this.refs.setSending(true);
    this.refs.follow.forceToBottom();
  }

  launchContinueRound(conn: AiConnection, roundToken: string, history: AiChatMessage[]): void {
    this.roundLauncher.launchContinueRound(conn, roundToken, history);
  }

  // ── 重试域宿主实现位（ChatRetryHost——本域私有态集中地）──
  // 销毁闸（工具轮侧同名实现已迁 ChatHostDelegates，本件为 ChatRetryHost 自留同义实现）

  isDisposed(): boolean {
    return this.disposed;
  }

  // 重试流式复位段（ChatRetryHost.beginRetryStreaming）：直发状态复位照 dispatchSend 轮首
  // 同款（liveThinkingId 清空配合路径换源重载——旧答案与其派生行〔思考块/工具卡/中间行〕
  // 已随换源整表重建移出；msgId 为**本轮承载行**——无工具轮形态 = 重试目标行自身，工具轮
  // 形态 = 新建承载行）+ 发送态置真 + 直达底部
  beginRetryStreaming(msgId: string): void {
    // 流式轮开始：与 dispatchSend 轮首同走流域意图方法——绑承载行 id 并同拍清三值
    this.flow.beginStreamRound(msgId);
    this.refs.setSending(true);
    this.refs.follow.forceToBottom();
  }

  // 重试组装段（二期 S4 域级最小拆分：整链外迁 ChatRoundLauncher，本件只留薄委托——
  // 行为逐字节零变化；起流咽喉点仍 Key 池 startRound，禁第二条请求链）
  launchRetryRound(conn: AiConnection, roundToken: string): void {
    this.roundLauncher.launchRetryRound(conn, roundToken);
  }

  // 中止（M1 onStop 语义）：编排整段在 ChatSendLifecycleCtrl（含停止键语义红线/后台任务连带
  // 口径/离页排空兑付沿革——彼件头注释与同名两法）；本件薄委托，调用点/时序/语义零变化
  //（★ U9 起退页不断流——disposeSilent 调用面在运行时空闲回收点；disposeDisplayState 挂
  // 页面侧 leave()，紧随 release 之后的 host.dataSource.disposeDisplayState() 直调）
  abort(): void {
    this.sendLifecycle.abort();
  }

  // ask_user 答案上行（ChatPage 交互卡提交 → 执行域挂起续跑；U11 域⑤ 起转续答域统一入口）
  resolveAsk(callId: string, answerJson: string): void {
    this.askResume.resolveAsk(callId, answerJson);
  }

  // browse_act 高危确认上行（ChatPage 确认卡作答 → 工具轮域挂起续跑——形制同 resolveAsk）。
  // 2128 起补无桥分流：重进后的确认卡没有内存挂起，走库侧回填续答（确认等待行已落库，
  // 判定与回填整域在续答件），否则点键静默无效
  resolveBrowseConfirm(callId: string, approved: boolean): void {
    if (toolRuntime.hasPendingConfirm(callId)) {
      toolRuntime.resolveBrowseConfirm(callId, approved);
      return;
    }
    this.askResume.resumeConfirm(callId, approved);
  }

  // 后台超时中断收口：短时任务超时回调链经运行态遍历逐活跃会话调用
  //（ChatSessionRuntime.interruptActiveForTimeout）——薄委托生命周期收尾域第三条终止路径
  //（跨域分发见 ChatSendLifecycleCtrl.timeoutInterrupt）
  interruptForTimeout(): void {
    this.sendLifecycle.timeoutInterrupt();
  }

  // 页面销毁静默中止（红线：解绑回调防销毁后触 UI；DB 残留 streaming 态由下次启动
  // markStreamingAsError 兜底转 error）。方法体整段在 ChatSendLifecycleCtrl；disposeDisplayState
  // 不随本链——挂页面侧 leave()（紧随 release 之后 host.dataSource 直调，位次不变）。
  disposeSilent(): void {
    // Q1 成对释放：先注销队列观察者/清占位与闩，再走既有销毁链
    this.sendGate.disposeSilent();
    this.sendLifecycle.disposeSilent();
  }

  // ── 迁移指针：Key 池/工具轮/自动重试三接口宿主实现位在 ChatHostDelegates；流回调三口
  //（onStreamDelta/Done/Error）、finishStream、flushFrame、failRound、createNativeStream 与
  // RETRY_STATUSES 全在 ChatStreamFlowCtrl（key 级切换/自动重试接管/最终呈报三分支判据
  // 零变化；图收尾身份经宿主面 graphHandleSnapshot/graphFinishRound 回接，快照次序
  //〔releaseRun 前取值〕与「144 组钉同守」口径随迁不变）──
}
