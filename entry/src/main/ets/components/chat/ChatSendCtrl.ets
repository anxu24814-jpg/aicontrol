// 发送编排域（2026-08-29 自 ChatPage 拆出——超 400 红线域级最小拆分）。★ 收发链路承 M1
// 语义（回归红线）：发送 → 协议流（工厂按 protocol 分发）→ ChatAppendThrottle 帧合并 →
// ChatDataSource（LazyForEach）渲染；思考增量进 thinking kind；流式增量只进内存，完成/
// 停止/出错一次性 finalizeMessage 落库（禁逐帧写库）；页面销毁 disposeSilent 静默中止；
// ★ 流式重试口径（2026-09-22 自动重试笔改写，原文「流式不自动重试」已被部分推翻）：换 Key
// 重发与自动退避重发都在本域编排——后者只在「网络层失败且本轮零产出」时触发（见
// ChatAutoRetryCtrl），中途断流与持 HTTP 状态码的失败仍不自动重发。
// ★ 2026-08-30 多 Key 池轮次：发送取「下一支 key」；401/403/429 = key 级
// 失败换下一启用 key 重发同消息（一轮内不重用；网络错误/手动停止不切）；全失败才 notice
// 落库；key 明文不进日志/toast。★ 2026-09-17 取钥方式：起始位由服务商配置决定（DB v32
// key_pick_mode——rotate 轮转〔原行为〕/ random 随机），分派单一来源 nextPickStart；
// **只影响起始位**：环绕尝试序、失败切换阶梯、协议请求字节全不变。节流：assistantFull/
// thinkingFull 累积串唯一真源，flush
// 全量覆盖（增量即全部，drop 未刷增量防二次拼接）。★ 2026-08-31 附件：载荷前置组装
//（失败降级纯文本），附件仅随本轮。★ 2026-09-09 附件落盘第一轮：发送成功附件文件
// 常驻 filesDir（选择侧已直写、发送零迁移），元数据行随 user 消息落库
//（message_attachments），条件清理三分支见 dispatchSend 头注释。★ 2026-09-15 预览笔：
// 条件清理改单分支（仅载荷失败全清，隐私会话不再发送即删——留盘供会话内预览，回收点
// 后移到离页 sweepAttachDir）；user 消息随发送装配附件简报 attachBriefs（气泡渲染面，
// 隐私会话同样装配）。★ 思考档位：refs 注入 → supportsThinking 门控 →
// 随轮次下发（'' = 不带字段）。★ 2026-09-01 会话绑定：助手覆盖/有效绑定在 ChatPromptState。
// ★ 2026-09-01 高级设定：助手采样/上下文参数（ChatPromptState.advancedParams 解析缓存）
// ——contextCount 注入前尾部截取（clipHistoryTail，身份注入不丢）+ 采样五字段随轮次下发
//（null = 未配置零字段；roundSampling 快照随 key 失败切换重发同参数）。
// ★ 2026-09-02 工具调用底层（RikkaHub GenerationHandler + CubeAgent executeToolCallLoop
// 调研定稿）：发送轮完成若聚合出工具调用 → 串行执行（ask_user 挂交互桥）→ 结果以
// role='tool' 追加历史 → while 式续轮（每轮新 assistant 占位行 + 落库）；轮数上限防死
// 循环（★ 2026-09-09 上限可设置：值 = 归属助手 toolStepLimit 列，0 = 不限制走 256 硬顶；
// ★ 2026-09-09 A2 让位轮：首次触顶不直接收尾——被丢弃的调用以合成工具结果回传模型、再
// 开一轮让它自己组织收尾话术，治空气泡；让位只给一次）；
// 工具卡 kind='tool' 上屏 + role='tool' 行落库（回放单一真源，
// ChatHistoryBuilder 据此重建工具方言）。key 失败切换语义不变（轮内切 key 重发同消息）。
// ★ 2026-09-02 Cube 移植试验副本·双引擎分流：偏好页「流式引擎（试验）」开关
//（AppPreferences.PREF_STREAM_ENGINE_KEY）分两态——false = 自研引擎（对照基线，永不
// 动）/ true = 试验引擎（Cube 移植）。分流落点两处（2026-09-18 起随本域迁 chat/cube/
// CubeEngineCtrl）：cube.feed = 节流/动效（阶段 2 已接：实验态走 cube/ 三频道打字机——
// displaySync 30fps 逐字 + 首块独立通道 + 揭示指针语义；原生走 ChatAppendThrottle 分档
// 节流不变）；cube.createStream = 传输+解析（阶段 3 落点，两分支暂同走原生协议流工厂）。
// 实验态快照在 dispatchSend 锁定（cube.rebuild 现读开关一次，轮内行为不随开关中途切换；
// 工具轮每轮重建）。
// ★ 2026-09-04 隐私会话零落库：refs.privateMode = true 时本域五个写库点（dispatchSend
// 双行入库 / beginToolRound 与 finishStream 的 finalizeMessage / executeToolCalls 工具行 /
// startNextAssistantRound 占位行）全部旁路——会话行与消息行都不建，消息流纯内存；流式/
// 失败切换/工具轮编排与普通模式共用一套（不落库不影响内存链路），离页清数据源在页面侧
//（ChatPage aboutToDisappear）。调研依据 docs/调研-隐私会话-RikkaHub与Cube同类实现-20260904.md。
// ★ 2026-09-15 撤链笔（决明「删掉链路，只占位，后续再做」）：末轮重试真链（retryLast
// 就地替换 + 残留工具行删库）整条退役——底栏重试键改占位 toast（ChatPage 侧）。
// ★ 2026-09-20 重试真链复活并升级多版本（决明「执行方案，拍板按推荐来」——方案档
// docs/方案-消息重新生成-20260920.md，方案文本随本笔落档）：retryLast 从撤链前实现取回（取回点 = 撤链前
// commit 44e89bc 链路 + 4953e99 尾巴缝修复），在其上升级「多版本保留 + 切换键」——
// messages 表 DB v36 双列（variants 全量真源 + variant_active 选中下标；content 列恒存
// 选中版 = 现役全部读方零改动的投影设计）。旧回答不再被覆盖丢弃（撤链待决①消解）：
// 重试开始旧答案即封存 variants[0] 写库保底，收尾新答案 append 为新版并选中，底栏出
// ‹ i/N › 切换键可切回（仅末条，ChatMessageItem）。补撤链后世界的三处缝：推荐问题
// 清空重算（clearConversationSuggestions + done 后同 msgId 重算）/ deleteMessagesBy
// 复活（尾巴缝）/ finalizeMessageVariant 五列收尾（finishStream 与工具轮中间收尾
// settleRoundAssistant 两点——本域写库点随之五 → 六）。
// ★ 同笔域级最小拆分两件（宪法 1200 硬线：本笔新增重试域一律先拆 + Key 池候选缝兑现）：
// 重试编排域（retryLast/切换/版本组装/版本态）整域外迁 **ChatRetryCtrl.ets**，本件留薄
// 委托与 ChatRetryHost 实现位（beginRetryStreaming 复位段 / launchRetryRound 组装段——
// 宿主私有态集中地）；Key 池轮次域（轮次五成员 + startRound/attemptCurrent/tryNextKey）
// 整域外迁 **ChatKeyRoundCtrl.ets**（照 ChatToolRoundCtrl/CubeEngineCtrl 先例），本件留
// ChatKeyRoundHost 实现位与 attemptCurrent/roundHistoryRef 接口薄委托。存储读写口同步
// 外迁 common/store/MessageVariantDb.ets（域件，sharedRdbStore 句柄——ChatDb 回软区）。账本口径拍板 = 重试消耗照常
// 落账（账本与消息生命周期解耦，统计页全量求和；帮助中心有说明句）。首版边界：
// 仅末条（tail 判据）、历史轮分支不做；有工具轮的重试其旧答案保底在 variants 不丢，
// 但切换入口首版只覆盖无工具轮的单行形态（终态在新行）。
// ★ 2026-09-08 工具轮域拆分（A1 前置，优化建议档 C2）：beginToolRound/executeToolCalls/
// startNextAssistantRound 与轮次态（roundTools/toolAccumulator/toolStep/roundReasoningItems）
// 迁 ChatToolRoundCtrl（宿主接口 ChatToolRoundHost 薄直通回接）——上列五写库点中工具域
// 三点随迁，守卫语义不变；本文件剩余 = 发送派发/流回调/Key 池轮次/双引擎分流/收尾。
// ★ 2026-09-13 技能层笔 1（方案-技能层-20260913）：system 注入链多一层——技能清单
//（appendSystemSkills，稳定块）插在提示词注入之后、记忆块（易变块）之前；工具声明链多
// 一件模式驱动工具 use_skill（助手启用集 ∩ 库内现存非空才声明，与清单同一次计算同闸）。
// 清单组装与上限全在纯函数 SkillText，本域只做两行级接线（读库 + 传值）。
// ★ 2026-09-16 单条消息指定技能（任务书-单条消息指定技能-20260916）：本轮可指定一件技能
//（页面发送漏斗 setSkillDesignate 写入，'' = 无指定）——①并入清单与 use_skill 声明（同
// 一次计算同闸：启用集 ∪ 指定、去重）；②指定正文块随本轮 **user 消息**注入（protocolText
// 首段——「技能正文永不进 system」的不变量原样成立，assembleRound 注入链零改动）；③标注句
//（〔本条指定技能：X〕）进显示面，用户零文本时以它代位进协议面（保 user 内容非空）；④发完
// 由页面清态、零落库零历史轮。
// ★ 2026-09-18 域级最小拆分（Cube 实验引擎域独立成件；决明「报告说有文件超限，可否合理拆，
// 不要为拆而拆」）：本件剔头 1202 行贴 1200 硬线，取边界最清晰的一域——双引擎分流（传输/
// 解析分流点 + 节流/动效分流点，阶段 3 落点）与三频道打字机动效态（flushers 快照/揭示指针/
// 流末收口）——整域迁 chat/cube/CubeEngineCtrl（照 ChatToolRoundCtrl〔2026-09-08〕与
// ChatContextUsageCalc〔2026-09-17〕先例：方法体逐字搬迁，宿主直引收敛为 CubeEngineHost
// 接口，本件 implements 回接）。语义零变化：分流判据（开关现读 + UIContext 可达）、快照时机
// （dispatchSend 轮首 / 工具轮每轮）、收口路径（finishStream 吐完 / disposeSilent 静默）全不
// 变；ChatToolRoundHost 的 settleCubeFlushers / rebuildCubeFlushers 两法保留为薄委托（工具轮
// 域与其断言桩零牵连）。本文件剩余 = 发送派发 / 流回调 / Key 池轮次 / 收尾 / 宿主委托。
// ★ 2026-09-22 聊天自动重试笔（新增功能域，宪法「新增功能域不论行数一律先拆」）：自动重试
// 判据与调度整域新建 chat/ChatAutoRetryCtrl.ets，本件只留接线（onStreamError 接管点 /
// abort 与 disposeSilent 取消 / 三处轮次复位 / onStreamDelta 状态行让位 / 失败文案装饰）与
// ChatAutoRetryHost 实现位；传输层 onError 加第三参 sawContent 供判据（AiTypes + ChatStreamBase
// 同笔改，两个消费点跟改）。本件仍留软引导区（剔头 < 1200）。
import { AiChatMessage, AiConnection, AiToolCall, AiToolDef, AiUsageDelta,
  AssistantAdvancedParams, ChatStream, PendingAttachment, SamplingParams } from '../../common/providers/AiTypes';
// 轮次参数解析域（2026-09-23 域级最小拆分外迁——档位归一 / 采样组装 / 上限联动；原 import
// 的 legalThinkingTier / connectionOffEnabled / supportsThinking / THINKING_OPTIONS 四符号随迁）
import { RoundParams, resolveRoundParams } from '../../common/providers/RoundParams';
import { TOOL_SEARCH_WEB, toolRuntime } from '../../common/providers/ToolTypes';
import { httpAbortAll } from '../../common/providers/ToolHttp';
import { CHAT_ACTIVE_CONV_KEY } from '../../common/providers/ToolChatSearch';
import { ChatToolRoundCtrl, ChatToolRoundHost, MessageVariantPayload } from './ChatToolRoundCtrl';
import { ChatKeyRoundCtrl, ChatKeyRoundHost } from './ChatKeyRoundCtrl';
import { ChatRetryCtrl, ChatRetryHost, VariantFinalizePayload } from './ChatRetryCtrl';
import { ChatUsageRoundCtrl, RoundUsageValues } from './ChatUsageRoundCtrl';
import { ChatAutoRetryCtrl, ChatAutoRetryHost } from './ChatAutoRetryCtrl';
import { ChatSnapshotCtrl, SkillSendContext } from './ChatSnapshotCtrl';
import { ChatContextUsageCalc, ContextSkillSnapshot, ContextUsage, toolDefsJsonOf } from './ChatContextUsage';
import { createChatStream } from '../../common/providers/ChatStreamFactory';
import { isAutoRetryEnabled as isAutoRetryPrefEnabled, isSearchServiceEnabled } from '../../common/AppPreferences';
import { CHAT_SEARCH_COUNT_KEY } from '../../common/search/SearchLimits';
import { UIContext } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CubeEngineCtrl, CubeEngineHost } from './cube/CubeEngineCtrl';
import { PromptInjectConfig, clipHistoryKeepingSummary, composeSendMessages, appendSystemMemory,
  appendSystemSkills } from '../../common/providers/RequestInject';
import { composeSkillDesignateMark, joinNonEmptyParts } from '../../common/SkillText';
// isMemoryToolReadMode = buildMemoryBlock 的按需读取守卫（工具声明侧同名判据已随链迁
// ChatContextUsageCalc，各自就近 import 不算双源——判据函数单源在 MemoryGen）
import { MEMORY_EXEC_ASSISTANT_KEY } from '../../common/MemoryGen';
import { KNOWLEDGE_EXEC_ASSISTANT_KEY } from '../../common/providers/ToolKnowledge';
import { MEMORY_SCOPE_ASSISTANT } from '../../common/store/MemoryDb';
import { SseDelta } from '../../common/providers/SseParser';
import { AttachmentPayload, buildAttachmentPayload, buildAttachmentRows,
  briefsFromPending } from '../../common/AttachmentUtil';
import { ConversationOverride, finalizeMessage, insertMessage,
  MessageRow, nextMessageId, nextRowCreatedAt } from '../../common/store/ChatDb';
import { nextRowSeq } from '../../common/store/MessageSeqDb';
import { finalizeMessageVariant } from '../../common/store/MessageVariantDb';
import { MessageAttachmentRow } from '../../common/store/AttachmentDb';
import { insertUsageEvent } from '../../common/store/UsageStatsDb';
import { ChatAppendThrottle } from './ChatAppendThrottle';
import { ChatFollowController } from './ChatFollowController';
import { ChatDataSource } from './ChatDataSource';
import { buildRequestHistory } from './ChatHistoryBuilder';
import { ChatMessage, newChatMessage } from './ChatMessageCompose';
import { ChatPromptState } from './ChatPromptState';
import { cleanupAttachments, releaseAttachmentThumbs } from './AttachmentPickCtrl';
import { CONN_RESOLVE_TICK_KEY } from '../../common/store/ProviderDb';
import { generateTitleForConversation, upgradeTitlePlaceholder } from '../../common/TitleGen';
import { clearConversationSuggestions, generateSuggestForMessage } from '../../common/SuggestGen';

// 轮次请求组装产物（2026-09-14 消息底栏笔自 dispatchSend 抽出成段——抽段本身保留；
// ★ 2026-09-20 重试真链复活：第二消费方 retryLast 回归）：截尾后注入链终态历史 + 思考档位 + 采样 + 工具声明
interface RoundRequest {
  history: AiChatMessage[];
  thinking: string;
  sampling: SamplingParams | null;
  tools: AiToolDef[];
}

// 页面侧读写集（箭头闭包持页面 this 延迟求值——dshinhm ChatCtrlAssembly refs 同款姿势；
// @State 写必须回页面经回调，普通引用（数据源/跟随器）直持有）
export interface ChatSendRefs {
  // 消息流（页面 @State 持有的数据源——容器操作经直引用，通知机制在源内）
  dataSource: ChatDataSource;
  // 流式滚动跟随（页面持有，与列表 scroller 同源）
  follow: ChatFollowController;
  conversationId: () => string;
  dbReady: () => boolean;
  // 隐私会话模式（2026-09-04）：true = 本会话零落库——五个写库点全旁路（守卫点见文件头
  // 注释）；页面 isPrivate 经闭包注入，普通模式恒 false 零回归
  privateMode: () => boolean;
  conn: () => AiConnection | null;
  sending: () => boolean;
  // 思考档位（页面 @State thinkingValue——会话级不落库，照 conn/attachments 先例经 refs 入；
  // '' = 默认不传；协议能力门控在 resolveRoundParams（2026-09-23 起在 common/providers/
  // RoundParams——不支持 = 不传零回归））
  thinking: () => string;
  // 会话联网开关（2026-09-03 领导指令；★ 2026-09-10 联网开关归位笔改语义：不再是独立的
  // 「会话级」开关，而是**归属助手启用清单的镜像**（页面 load 解析后写入）——发送组装时
  // 按此过滤 search_web 声明，现与 enabledToolIds 同源）
  webSearchOn: () => boolean;
  // 无行会话的会话级覆盖（2026-09-10 会话级覆盖层笔）：首条消息落行时随 insertMessage
  // 写入 conversations 覆盖三列（先例：conversations.promptId 的面板覆盖随首发落行）；
  // 有行会话恒 null（覆盖已在库、由用户在会话内的后续操作直接 UPDATE）
  sessionOverride: () => ConversationOverride | null;
  setSending: (sending: boolean) => void;
  // 发送前置守卫通过后的错误态清空（页面 errorText 覆盖层）
  clearError: () => void;
  toast: (message: string) => void;
  // 页面 UIContext（2026-09-02 阶段 2：Cube 打字机 displaySync.start 须 runScopedTask 包裹，
  // 须页面侧注入；ChatPage 挂载后闭包恒可达——空值仅防御性类型）
  cubeUiContext: () => UIContext | null;
  // 轮次收尾通知（2026-09-17 会话上下文用量，可选钩子）：done/error 两路都在 finishStream
  // 触发——页面据此重算上下文圆环（方案 §3.6「真值到达 = 最准时刻」；生成中不刷、收尾即刷）。
  // 无消费方时零开销（活算在 ChatContextUsageCalc）
  onRoundSettled?: () => void;
}

// 失败切换资格的 HTTP 状态码（拍板：401/403/429 = key 级失败；网络错误无状态码不切）
const RETRY_STATUSES: number[] = [401, 403, 429];
// 工具调用轮上限与轮次态在 ChatToolRoundCtrl（2026-09-08 域级最小拆分，A1 前置）；
// ★ 2026-09-09 上限可设置：上限值改为助手级配置（assistants.toolStepLimit 列 → 本轮
// stepLimit 经 resetForNewSend 第二参传入，0 = 不限制换算为内置硬顶 256，换算单源
// ToolLimits）；触顶 notice 的数字经 toolRound.roundLimit() 取用，与实际闸门同源

export class ChatSendCtrl implements ChatToolRoundHost, CubeEngineHost, ChatRetryHost,
  ChatKeyRoundHost, ChatAutoRetryHost {
  private refs: ChatSendRefs;
  private appendThrottle: ChatAppendThrottle | null = null;
  private activeStream: ChatStream | null = null;
  // 流式权威全量累积（本回合进行中消息）
  private assistantFull: string = '';
  private thinkingFull: string = '';
  private liveAssistantId: string = '';
  private liveThinkingId: string = '';
  // ── Key 池轮次域（2026-09-20 域级最小拆分迁 ChatKeyRoundCtrl——候选缝兑现；轮次五成员
  // 与 startRound/attemptCurrent/tryNextKey 全在彼件，本件经此引用消费）──
  private keyRound: ChatKeyRoundCtrl;
  // ── 工具调用轮次态（2026-09-02；roundTools/roundKeyIds 同为「一轮」快照——失败切换
  // 重发同声明）：2026-09-08 域级最小拆分迁 ChatToolRoundCtrl（A1 前置），经
  // this.toolRound 消费，重发同声明语义不变 ──
  private toolRound: ChatToolRoundCtrl;
  private disposed: boolean = false; // 页面销毁闸（异步取钥中途销毁守卫）
  // ── 轮级用量与诊断标记域（2026-09-23 首字耗时笔域级最小拆分迁 ChatUsageRoundCtrl——
  // 剔头贴 1200 硬线后的候选缝兑现）：跨流用量求和 / 截断末流胜出 / 首字首个胜出三条口径
  // 与全部成员全在彼件，本件只留三条接线 = 轮首 reset + 流末 accumulate + 收尾 values ──
  private usageRound: ChatUsageRoundCtrl = new ChatUsageRoundCtrl();
  // ── Cube 实验引擎域（2026-09-02 阶段 2 接入；2026-09-18 域级最小拆分独立成件）──
  // 三频道动效态（flushers 快照 / 揭示指针）与双引擎分流点（传输-解析 / 节流-动效两落点）
  // 全在 cube/CubeEngineCtrl；本文件只留调用接线（轮首 rebuild / 增量 feed / 收口 settle /
  // 造流 createStream），宿主直引经 CubeEngineHost 接口回接（实现位见文件末宿主委托节）
  private cube: CubeEngineCtrl;
  // 提示词注入解析域（2026-08-31 拆出）：load 预载 → send 组装读取；2026-09-01 起兼管
  // 会话级助手绑定（覆盖值/有效绑定——语义见 ChatPromptState 头注释）
  private promptState: ChatPromptState = new ChatPromptState();
  // 会话上下文用量域（2026-09-17 拆出 ChatContextUsageCalc：估算/锚点/校准/活算编排，闭包持 refs 延迟求值）
  private ctxCalc: ChatContextUsageCalc;
  // 本轮指定技能 id（2026-09-16 单条消息指定技能）：页面在发送前经 setSkillDesignate
  // 写入（'' = 无指定）；每次发送恒写（漏斗首行——无残留态）；纯内存、不跨轮、不落库。
  // ★ 本字段只在 send() 入口被**快照**一次（见该处注释）——buildSkillContext 禁直读本
  // 字段：载荷/记忆/技能三链是异步串行，组装期间页面可再改指定（下一轮或再指定），
  // 晚读会把「后改的值」注进「先发的那条消息」（静默串轮）
  private designateId: string = '';
  // ── 发送前快照域（2026-09-20 域级最小拆分迁 ChatSnapshotCtrl——记忆块与技能上下文
  // 两块 system 注入材料的读取与组装；快照取值口径注释随方法体在彼件）──
  private snapshot: ChatSnapshotCtrl;


  // ── 重试编排域（2026-09-20 消息重新生成·多版本；retryLast/switchVariant/版本组装全在
  // ChatRetryCtrl，本件持引用 + 薄委托——ChatRetryHost 实现位见本文件）──
  private retry: ChatRetryCtrl;

  // ── 网络层失败自动重试域（2026-09-22 笔；判据/退避调度/状态行全在 ChatAutoRetryCtrl，
  // 本件持引用 + 接线——ChatAutoRetryHost 实现位见本文件）。分工：本域只管「请求尚未产出
  // 任何内容」的网络失败重发；用户主导的整轮重生成仍走 ChatRetryCtrl ──
  private autoRetry: ChatAutoRetryCtrl;

  constructor(refs: ChatSendRefs) {
    this.refs = refs;
    this.toolRound = new ChatToolRoundCtrl(this);
    // Key 池轮次域与重试编排域（2026-09-20 两笔域级拆分件）：宿主实例直传（本类 implements
    // 两接口；ctxCalc 构造闭包引用 keyRound 为箭头延迟求值，构造序无碍）
    this.keyRound = new ChatKeyRoundCtrl(this);
    this.retry = new ChatRetryCtrl(refs, this);
    // 网络层失败自动重试域（2026-09-22 笔）：宿主实例直传（本类 implements ChatAutoRetryHost）
    this.autoRetry = new ChatAutoRetryCtrl(this);
    // 快照域（2026-09-20 拆分件）：promptState 解析缓存 + 隐私闭包直传
    this.snapshot = new ChatSnapshotCtrl(this.promptState, { privateMode: () => refs.privateMode() });
    // Cube 实验引擎域（2026-09-18 拆分件）：宿主实例直传（本类 implements CubeEngineHost）
    this.cube = new CubeEngineCtrl(this);
    // 上下文用量域闭包（延迟求值——构造期 refs 先就位再建；箭头持 this，调用时恒可达）
    this.ctxCalc = new ChatContextUsageCalc({
      conn: (): AiConnection | null => this.refs.conn(),
      privateMode: (): boolean => this.refs.privateMode(),
      webDomainAllowed: (): boolean => this.webDomainAllowed(),
      memoryParticipates: (): boolean => this.snapshot.memoryParticipates(),
      buildMemoryBlock: (): Promise<string> => this.snapshot.buildMemoryBlock(),
      // 活算无「本轮指定技能」（指定属下一轮发送面，方案 §3.4 段 8 口径）——收窄视图由
      // 本侧显式构造（ArkTS 禁同构双接口互传）
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
      allMessages: (): ChatMessage[] => this.refs.dataSource.allMessages(),
      // 会话级缓存命中的账本聚合键（2026-09-18 增量笔）——与用量落库点同一取值口
      conversationId: (): string => this.refs.conversationId(),
      roundConn: (): AiConnection | null => this.keyRound.currentConn(),
      roundHistory: (): AiChatMessage[] => this.keyRound.currentHistory()
    });
  }

  // 节流器懒构造（flush 回调需绑 this——属性初始化期 this 时序不作假设，首用即建）
  private throttle(): ChatAppendThrottle {
    if (this.appendThrottle === null) {
      this.appendThrottle = new ChatAppendThrottle(
        (frameId: string, delta: string): number => this.flushFrame(frameId, delta));
    }
    return this.appendThrottle;
  }

  // 节流缓冲复位（★ 2026-09-11 笔 3 接线）：全量重建链（ChatPageLoad.loadHistory →
  // dataSource.rebuildFromHistory）前清缓冲 + 档位回快档——否则旧窗口增量在新数据源上
  // 空转（frameId 查不到）且慢档惯性带进下一次首刷。**懒构造不因复位建实例**（null =
  // 本页从未流过流，无缓冲可清）。会话切换不走本方法：会话 = 新页面实例，节流器随
  // ChatPage 重建（见 ChatAppendThrottle 类头注释）
  resetAppendBuffer(): void {
    if (this.appendThrottle !== null) {
      this.appendThrottle.reset();
    }
  }

  // 提示词注入预载（打开会话调一次 + 面板选择后刷新）——解析域在 ChatPromptState；
  // 返回 Promise 供页面链后置（2026-09-03：load 完成后写「联网可用」广播键）
  loadPromptState(conversationId: string): Promise<void> {
    return this.promptState.load(conversationId);
  }
  // 面板助手覆盖透传 + 有效绑定读取（2026-09-01 会话绑定：逻辑在 ChatPromptState）
  setBoundOverride(assistantId: string): void {
    this.promptState.setBoundOverride(assistantId);
    // 广播解析输入变化（2026-09-05 自检轮观察项销项：方案 a 同族补口）——无行会话的
    // 有效归属 = 面板覆盖 ?? 当前助手 ?? 默认，覆盖变化即②级输入变化，切回直接发送
    // 须重解析（原两写点漏此路径）
    AppStorage.setOrCreate<number>(CONN_RESOLVE_TICK_KEY,
      (AppStorage.get<number>(CONN_RESOLVE_TICK_KEY) ?? 0) + 1);
  }
  // 有效归属读取（ChatPromptSheet 助手卡显示态：面板覆盖 ?? 当前助手 ?? 内置默认助手；
  // ★2026-09-04 归属与注入解耦——不再受提示词覆盖影响）
  boundAssistantId(): string {
    return this.promptState.effectiveAssistantId();
  }
  // 归属助手启用工具 id 清单（2026-09-10 联网开关归位笔：chip 反查/改写用——解析缓存现读，
  // 与发送组装 dispatchSend 同一份真源；★ 同日第二阶段起只读：chip 改会话级覆盖，不再写回
  // 本清单，消费方余发送组装与页面「能不能联网」判定）
  enabledToolIds(): string[] {
    return this.promptState.enabledToolIds();
  }
  // 面板提示词引用覆盖透传 + 当前覆盖读取（2026-09-04 隐私会话开放提示词选择：无行
  // 会话的引用覆盖纯内存持有，解析优先级见 ChatPromptState.promptOverride 注释）
  setPromptOverride(promptId: string): void {
    this.promptState.setPromptOverride(promptId);
  }
  promptOverrideId(): string {
    return this.promptState.promptOverrideId();
  }
  // ── 上下文压缩供给（2026-09-23）：ChatPage 压缩面板/用量卡 refs 薄取值口（promptState
  // 私有经此透传。★ 同日输出上限治理笔删 assistantAdvancedParams——压缩上限已脱挂会话助手）──
  assistantClipLimit(): number { return this.promptState.advancedParams()?.contextCount ?? 0; }
  // 本轮指定技能写入（2026-09-16 单条消息指定技能）：页面发送漏斗（ChatPage.
  // sendWithAttachments）首行调——两个发送入口（输入栏/全屏输入面板）与视觉确认路径共用
  // 同一漏斗，挂漏斗一处即全覆盖；每次发送恒写（'' = 无指定，无残留）
  setSkillDesignate(id: string): void {
    this.designateId = id;
  }
  // 联网开关可用性（2026-09-03 领导指令）：当前助手启用清单是否含 search_web = **能不能联网
  // 的能力上限**（页面 refreshWebSearchFlag 据此写闸键；★ 2026-09-10 会话级覆盖层笔第二阶段
  // 起 chip 不再写回清单，本方法纯读）
  webSearchAllowed(): boolean {
    return this.promptState.enabledToolIds().includes(TOOL_SEARCH_WEB);
  }

  // 联网域可用性（2026-09-11 单向绑定唯一判定源，B 案行为补齐）：助手启用清单含
  // search_web（能力上限）∩ 本会话联网开关（会话级临时关）∩ 全局总开关，三源合取。
  // false = 模型收不到联网域两件声明——「读取网页」不单列开关，随域可用性：用户
  // 「我不想联网」的口径覆盖它（竞品同向——RikkaHub 抓取工具随搜索服务存在与否注册，
  // 见 docs/调研-联网搜索全链路-20260909/01；执行器侧另有全局总开关兜底守卫，会话级/
  // 助手级两维执行器无上下文可读，由本声明层负责）
  private webDomainAllowed(): boolean {
    return this.webSearchAllowed() && this.refs.webSearchOn() && isSearchServiceEnabled();
  }

  // 会话上下文用量活算（2026-09-17 方案-会话上下文用量）：面板打开/轮完成/切模型三处调用
  //（方案 §3.6——打字与生成中不刷）；编排与口径在 ChatContextUsageCalc（域级拆分件），
  // 本方法只是宿主门面（页面不直接持 calc）。★ 2026-09-23 活算纳入待发附件笔：待发附件数组
  // 与 hasVision 随参带入（页面当场值）——图片张数不再由页面另算（原 draftImageCount 已删，
  // 分流判据单源在 AttachmentUtil.pendingAttachFootprint）
  computeContextUsage(draftText: string, attachments: PendingAttachment[],
    hasVision: boolean): Promise<ContextUsage> {
    return this.ctxCalc.computeLive(draftText, attachments, hasVision);
  }

  // 发送（M1 doSend 原样搬迁 + 轮次启动收尾；2026-08-31 附件载荷前置）：守卫 → 附件组装
  //（异步：图片重采样编码 + 文本读取——失败降级纯文本不阻断）→ 历史快照 → 系统提示词
  // 注入 → 占位气泡 → 入库 → 池轮次。守卫首条：空文本且无附件不发（附件可独立成文）。
  // ★ 返回值契约（2026-09-15 发送链收口笔）：true = 守卫全过、消息已交编排（后续异步组装
  // 照旧，失败降级不回头）；false = 任一守卫拦下、本次未投递——**附件不在守卫里清理**：
  // 调用方（ChatPage.dispatchSend）按 false 保留输入条文字与附件，文件仍被输入条引用，
  // 就地清理反成悬空引用（原 2026-09-11「守卫早退即清附件」随本笔退役，理由见调用方注释）；
  // 唯一的投递后清理点 = 下方 disposed 分支（那时调用方已按 true 把附件清出输入条）。
  // ★ hasVision 形参（2026-09-15 附件 OCR 二期）：主模型有无视觉理解——载荷组装分流用
  //（无视觉且有识别文本 → 识别文本进 protocolAppend、图停发，AttachmentUtil §3.6）
  send(text: string, attachments: PendingAttachment[], hasVision: boolean): boolean {
    // 本轮指定技能快照（2026-09-16 单条消息指定技能，自检轮 F1）：下方三链异步串行
    //（附件载荷 → 记忆块 → 技能上下文），组装期间页面仍可改指定（用户清条 / 再指定 / 下一条
    // 消息已在下一次发送里写了新值）——晚读会把「后改的值」注进「先发的那条消息」。故在**投递
    // 入口一次取值**随链下传，与 text/attachments 同口径（两者也是入口值参）
    const designateId: string = this.designateId;
    if (text === '' && attachments.length === 0) {
      return false;
    }
    if (this.refs.sending()) {
      // 流式中不插话（M1 红线）：本次未投递，文字与附件原样留输入条
      return false;
    }
    if (!this.refs.dbReady()) {
      this.refs.toast('数据库未就绪，请稍候再试');
      return false;
    }
    const conn: AiConnection | null = this.refs.conn();
    if (conn === null) {
      // 2026-08-30 服务商管理域改版：连接 = 当前服务商 + 当前模型（无可用服务商/无对话
      // 模型/key 池无启用条目均解析为 null——设置页三字段表单已退役）
      this.refs.toast('请先在「设置 > 服务商管理」完善服务商（接口地址、密钥与模型）');
      return false;
    }
    this.refs.clearError();

    // 附件载荷组装（异步）→ 完成后派发；失败降级空载荷（toast 呈报，文本不陪葬）。
    // 组装期间输入条已被清空（canSend 当场为 false）、销毁闸拦住派发并清删副本。
    // ★ 自检轮订正：sending 闸在 dispatchSend 才置位（:539），故「组装窗口内用户重新打字
    // 再点发送」并非物理不可达（本条链成立时 sending 仍是 false）——窗口长度 = 载荷组装
    // 耗时（纯文本几十毫秒、大图重采样可达秒级）。本链的入参（text/attachments/
    // designateId）全部在入口快照，故并发第二笔不会污染第一笔；残余面 = 两条消息同时在飞
    //（历史快照/占位气泡各写各的），属**存量**行为，另行登记观察项，本笔不动
    // 记忆块快照在派发前现读（2026-09-08 记忆域：DB 单一真源不缓存；组装期间用户可
    // 能在记忆页增删条目——发送一刻取当下值）
    buildAttachmentPayload(attachments, hasVision)
      .catch((e: Object): AttachmentPayload => {
        this.refs.toast('附件处理失败：' + (e as Error).message + '（已按纯文本发送）');
        return { annotate: '', protocolAppend: '', images: [] };
      })
      .then((payload: AttachmentPayload): Promise<void> => this.snapshot.buildMemoryBlock()
        .then((memoryBlock: string): Promise<void> => this.snapshot.buildSkillContext(designateId)
          .then((skillCtx: SkillSendContext): void => {
            if (this.disposed) {
              cleanupAttachments(attachments);
              return;
            }
            this.dispatchSend(conn, text, attachments, payload, memoryBlock, skillCtx);
          })));
    // 守卫全过 = 已投递（后续异步组装不再回头；调用方据此清输入条）
    return true;
  }

  // 派发发送（附件载荷已就绪）：条件清理 → 双文本合成（展示 = 文本+附件标注+指定标注，
  // DB/气泡/历史均此形态；协议 = 指定正文块+文本+文本附件内容，仅当前轮——正文与附件本体
  // 仅随本轮请求，历史轮不重发）→ 历史快照 → 注入 → 占位气泡 → 入库（附件元数据行随
  // user 行）→ 池轮次。
  // memoryBlock = 记忆注入块快照（send 链派发前现读；'' = 不注入）
  // skillCtx = 技能上下文快照（清单 + 是否声明 use_skill + 本轮指定正文块与名；manifest ''
  // + false + 两空 = 不注入不声明——2026-09-16 单条消息指定技能扩两字段）
  private dispatchSend(conn: AiConnection, text: string, attachments: PendingAttachment[],
    payload: AttachmentPayload, memoryBlock: string, skillCtx: SkillSendContext): void {
    // 条件清理（★ 2026-09-15 预览笔拍板 1 收口：隐私会话不再发送即删——文件留盘供会话内
    // 预览，回收点后移到离页整目录清扫 ChatPage.aboutToDisappear sweepAttachDir）：仅载荷
    // 组装失败（判定 = 有附件但标注空——buildAttachmentPayload 对非空附件恒产出非空
    // annotate，失败降级时附件未随消息发送）→ 全清（缩略图 + 文件，「未随消息发送的附件
    // 不驻留」）；其余（普通/加密/隐私会话且载荷成功）→ 仅释放缩略图，文件留盘
    //（常驻区 filesDir 供历史气泡与预览消费；隐私区 cacheDir 离页整目录清）
    if (attachments.length > 0 && payload.annotate === '') {
      cleanupAttachments(attachments);
    } else {
      releaseAttachmentThumbs(attachments);
    }
    // 附件已随消息发送（载荷成功且有附件）——入库侧据此构建元数据行（失败/隐私恒空数组）
    const attachSent: boolean = attachments.length > 0 && payload.annotate !== '';
    const annotate: string = payload.annotate;
    // 本轮指定技能标注（2026-09-16 单条消息指定技能）：显示面恒带（气泡/DB/历史 = 「本条
    // 用了哪件技能」的可见痕迹）；协议面只在「用户零文本」时代位（正文块自带技能名，
    // 不重复）；零指定 = '' 零开销
    const designateMark: string = composeSkillDesignateMark(skillCtx.designatedName);
    // 展示/DB/气泡：用户文本 + 指定标注 + 附件标注——三值经 joinNonEmptyParts 单入口拼接，
    // 零指定时逐字等于旧两值式（空段过滤语义与旧三目逐例等价）。
    // ★ 2026-09-20 自检轮改序（原序 = 用户文本 + 附件标注 + 指定标注）：附件标注必须留在
    // **尾部**——气泡渲染靠 hideAttachAnnotate 的「尾部逐字吻合」才剥得掉它（AttachmentUtil
    // 拍板 5：库内不改写、只在气泡渲染时隐去；纯附件消息剥到空串还是「气泡整只不渲染」的
    // 判定前提），而指定标注按设计恒带显示面。原序在「附件 + 指定」同现时把附件标注挤离
    // 尾部 → 剥不掉 → 用户气泡漏出「[附件] 名单」行（只附件无指定时无此现象）。改序后两种
    // 组合气泡都只剩「用户文本 + 指定标注」，附件仍以卡片呈现。
    const displayText: string = joinNonEmptyParts([text, designateMark, annotate]);
    // 纯附件发送且载荷组装全失败 → 无可发内容：notice 提示不发空请求（有文本不进此支）
    // ★ 只指定不打字也发得出：displayText = 标注句非空 → 过此守卫（竞品「空消息 400」防法）
    if (displayText === '' && payload.images.length === 0) {
      this.refs.dataSource.push(newChatMessage(nextMessageId('notice'), 'notice', '附件处理失败，消息未发送'));
      return;
    }
    const append: string = payload.protocolAppend;
    // 协议（仅本轮）：指定技能正文块在最前（说明书先于任务——附件属「材料」放用户话之后，
    // 技能正文属「做法指令」放用户话之前）→ 用户原话（零文本时以标注句代位：「本轮就用
    // 这件技能」的最小指令，且保证 user 内容非空）→ 附件内容在最后。零指定时逐字等于
    // 旧两值式（负向钉）
    const protocolText: string = joinNonEmptyParts([skillCtx.designatedBlock,
      text !== '' ? text : designateMark, append]);
    // 请求历史：已落屏的 user/assistant 消息（空内容跳过；notice 不入协议）+ 本条提问。
    // 组装域在 ChatHistoryBuilder（2026-09-01 拆分——本文件加「回传历史思考」后超 400 红线；
    // reasoning 配对逻辑与回传口径见该文件与 RequestCompose 注释）
    const history: AiChatMessage[] = buildRequestHistory(this.refs.dataSource.allMessages());
    const userReq: AiChatMessage = { role: 'user', content: protocolText };
    if (payload.images.length > 0) {
      userReq.images = payload.images;
    }
    history.push(userReq);
    const req: RoundRequest = this.assembleRound(conn, history, memoryBlock, skillCtx);
    this.toolRound.resetForNewSend(req.tools, this.promptState.toolStepLimit());
    // 搜索条数中转键（2026-09-10 搜索条数助手级可调）：搜索执行器接口 execute(argsJson) 无
    // 上下文、读不到助手行，故值经进程级键中转到搜索编排（SearchEngineRegistry.dispatchSearch
    // 读回填引擎运行时 ctx）。★ 写点选在**发送时**而非进页时——与上面 toolStepLimit 同一次
    // 解析、同一助手，天然对位；也避免「页面存活期间助手被改」的错配窗口（比 chip 键的进页
    // 写点更强）。键由本链每次发送覆写，读侧恒取当下值
    AppStorage.setOrCreate<number>(CHAT_SEARCH_COUNT_KEY, this.promptState.searchResultCount());
    // 当前会话中转键（2026-09-13 跨会话检索）：search_chats 执行器无上下文读不到会话态，
    // 当前会话 id 经本键到达（检索排除当前会话——「其他会话」语义，当前会话内容本就在
    // 上下文返回只是噪声）；写点与搜索条数键同位同理由（发送时现写，读侧恒取当下值）
    AppStorage.setOrCreate<string>(CHAT_ACTIVE_CONV_KEY, this.refs.conversationId());
    // 记忆作用域中转键（v35，2026-09-20 助手级记忆）：search_memory/manage_memory 执行器
    // 无上下文读不到助手行——执行者助手 id 经本键到达（'' = 全局库 / 非空 = 该助手自己的
    // 库，两执行器按同一判据选库与定位，跨库操作天然隔离）。写点与上两键同位同理由
    //（发送时现写——值源 = promptState 同链解析缓存，与本轮 toolStepLimit/searchResultCount
    // 同一次解析同一助手，天然对位）
    AppStorage.setOrCreate<string>(MEMORY_EXEC_ASSISTANT_KEY,
      this.promptState.memoryScope() === MEMORY_SCOPE_ASSISTANT ?
        this.promptState.ownerAssistantId() : '');
    // 知识库执行者中转键（v38，2026-09-21 世界书知识库首版）：search_knowledge 执行器无
    // 上下文读不到助手行——执行者助手 id 经本键到达，执行器据此读该助手的 knowledge 启用集。
    // ★ 值 = **无条件取 ownerAssistantId()**（不随记忆作用域置空——知识库启用与记忆作用域
    // 是两个独立维度，勿照抄上一行的三元表达式）；写点与上三键同位同理由（发送时现写）
    AppStorage.setOrCreate<string>(KNOWLEDGE_EXEC_ASSISTANT_KEY,
      this.promptState.ownerAssistantId());
    // 整轮用量累积器清零（2026-09-06；轮首唯一清零点——工具轮间不清，见 ChatUsageRoundCtrl
    // 域头注释）；重试版本态与自动重试域同点清零（2026-09-22 后半：计数与停止标记归零、
    // 在途退避取消）
    this.usageRound.reset();
    this.retry.resetRound();
    this.autoRetry.resetForRound();

    // 行时间走单调分配器（★ 2026-09-21 消息存储机制改造笔 2 债务②收口：原写裸 Date.now() 与
    // now + 1 让位——并列风险靠启动修复清扫与查询决胜键双兜底，本笔接入后从源头消灭；附件行
    // 时间同取本值 = 与 user 行同刻，附件非 messages 行不铸 seq）
    const now: number = nextRowCreatedAt();
    const userMsg: ChatMessage = newChatMessage(nextMessageId('msg'), 'user', displayText);
    // 附件简报装配（2026-09-15 预览第三轮）：已随消息发送（载荷成功且有附件）即装——
    // 普通与隐私会话同样装配（隐私无库行但内存态齐备，这是隐私会话附件泡可点开预览的
    // 前提）；push 前赋值使首帧即带简报
    if (attachSent) {
      userMsg.attachBriefs = briefsFromPending(attachments);
    }
    const assistantMsg: ChatMessage = newChatMessage(nextMessageId('msg'), 'assistant', '');
    // 流式运行时标记（2026-09-14 消息底栏）：占位起底栏不现（拍板 1a），finishStream /
    // 工具轮中间行收尾置 false；tail 由数据源 push 维护
    assistantMsg.streaming = true;
    this.refs.dataSource.push(userMsg);
    this.refs.dataSource.push(assistantMsg);
    this.liveAssistantId = assistantMsg.id;
    this.liveThinkingId = '';
    this.assistantFull = '';
    this.thinkingFull = '';
    // 实验引擎三频道快照（阶段 2）：开关现读 + UIContext 可达才建（轮次锁定）；揭示指针清零
    //（2026-09-18 拆分后 = cube.rebuild 单一入口——工具轮每轮的同款三行同走此方法）
    this.cube.rebuild();
    this.refs.setSending(true);
    this.refs.follow.forceToBottom();

    // 发送即入库（user done / assistant streaming——中断恢复口径；失败切换不重复入库）；
    // 首条消息落行写入会话归属助手（2026-09-01 会话绑定：有效绑定 = 面板覆盖 ?? 当前助手）。
    // 隐私会话整块旁路（2026-09-04）——会话行与消息行都不建（比「空会话无痕」懒建更强：
    // 全程无行）
    if (!this.refs.privateMode()) {
      const convId: string = this.refs.conversationId();
      // seq 与 createdAt 同址铸造（★ 2026-09-21 消息存储机制改造笔 2 D1 红线：同一同步块内、
      // 行对象构造当场取号——禁 await 后补铸）；两行按构造序连铸（user 先 assistant 后）
      const nowRow: MessageRow = {
        id: userMsg.id, conversationId: convId, role: 'user',
        content: displayText, reasoning: '', status: 'done', createdAt: now,
        seq: nextRowSeq(convId)
      };
      const assistantRow: MessageRow = {
        id: assistantMsg.id, conversationId: convId, role: 'assistant',
        content: '', reasoning: '', status: 'streaming', createdAt: nextRowCreatedAt(),
        seq: nextRowSeq(convId)
      };
      userMsg.rowSeq = nowRow.seq;
      assistantMsg.rowSeq = assistantRow.seq; // 压缩选段判据（理由全文 = ChatMessage.rowSeq 注释）
      // 建行绑定值（★2026-09-04 晚定稿）：assistantId = 有效归属实体值（面板覆盖 ?? 当前
      // 助手 ?? 默认助手——恒非 ''，「跟随当前」已撤销不落空串行）；promptId = 面板提示词
      // 覆盖（'' = 未启用注入 = 用归属助手提示词）——两值同落一致态互不清零，无行会话的
      // 内存覆盖随首发持久化，续轮次 load() 行查询接手，选择跨消息稳定生效
      const promptBound: string = this.promptState.promptOverrideId();
      const assistantBound: string = this.promptState.effectiveAssistantId();
      // 附件元数据行（2026-09-09 附件落盘第一轮）：仅载荷成功且有附件时构建（localPath =
      // 相对 filesDir 路径，纯函数 buildAttachmentRows）；隐私会话整块旁路不进此分支
      const attachRows: MessageAttachmentRow[] = attachSent ?
        buildAttachmentRows(attachments, userMsg.id, this.refs.conversationId(), now) : [];
      // 会话级覆盖随首发落行（2026-09-10 会话级覆盖层笔）：无行会话在会话内改过的模型/
      // 联网开关只存页面内存，本处补写入行；有行会话恒 null（覆盖已在库、无需重写）
      insertMessage(nowRow, assistantBound, promptBound, attachRows, this.refs.sessionOverride())
        .then((): Promise<void> => insertMessage(assistantRow))
        .then((): void => {
          // 首条占位标题升级（2026-09-05 任务 7）：user 行落库后会话行必已建——把「新对话」
          // 升级为首条文本截断占位（≤20 字符，纯附件跳过；条件 UPDATE 原子闸在 ChatDb，
          // 不动 updatedAt 时间序）。fire-and-forget，失败 hilog 不打扰发送链
          upgradeTitlePlaceholder(this.refs.conversationId(), text);
          // 会话建议清空（2026-09-19 推荐问题功能，upgradeTitlePlaceholder 调用同位）：
          // 发送即清空写 '' + 广播——中断场景关键兜底（第二轮回复失败或手动停止时，上一轮
          // 旧建议已在发送瞬间清掉，不会错挂在失败轮下面；UI 层 busy 隐藏为第二道保险）。
          // in-flight 期同时作废在途旧轮生成（SuggestGen 代纪元）。fire-and-forget
          clearConversationSuggestions(this.refs.conversationId());
        })
        .catch((e: Object): void => {
          this.refs.toast('消息入库失败：' + (e as Error).message);
        });
    }

    this.keyRound.startRound(conn, req.history, req.thinking, req.sampling);
  }

  // 末轮重试入口（薄委托——重试编排域 2026-09-20 整域外迁 ChatRetryCtrl，行为面全在彼件；
  // 沿革与拍板口径见 ChatRetryCtrl 头注释）：守卫/清理复位/版本基线保底/组装发起全链
  retryLast(msgId: string): void {
    this.retry.retryLast(msgId);
  }

  // 版本切换入口（薄委托——底栏 ‹ i/N › 切换键上行 ChatPage → 此处 → ChatRetryCtrl
  // .switchVariant：读行/越界守卫/三列换版/内存原地改全链）
  switchMessageVariant(msgId: string, target: number): void {
    this.retry.switchVariant(msgId, target);
  }

  // ── 重试域宿主实现位（ChatRetryHost，2026-09-20 拆分件——本域私有态集中地；isDisposed
  // 与工具轮域实现位共用一处实现〔接口同名同义，类内单实现双满足〕）──

  // 重试流式复位段（ChatRetryHost.beginRetryStreaming）：直发状态复位照 dispatchSend 轮首
  // 同款（liveThinkingId 清空配合 cleanRoundResidue——本轮派生行〔旧思考块/工具卡/中间行〕
  // 已随整轮清扫移出；★ 2026-09-20 修复笔：msgId 为**本轮版本承载行**——无工具轮形态 =
  // 重试目标行自身，工具轮形态 = 新建承载行）+ 三频道重建
  //（retry 走 cube 单一入口与两发送路径同款）+ 发送态置真 + 直达底部
  beginRetryStreaming(msgId: string): void {
    this.liveAssistantId = msgId;
    this.liveThinkingId = '';
    this.assistantFull = '';
    this.thinkingFull = '';
    this.cube.rebuild();
    this.refs.setSending(true);
    this.refs.follow.forceToBottom();
  }

  // 重试组装段（ChatRetryHost.launchRetryRound）：记忆块 → 技能上下文（'' = 重试不重指定
  // ——指定随首答 user 消息已注入历史文本）→ assembleRound → 工具轮重置 → 三中转键 →
  // 轮次用量清零 → Key 池发起。**与 dispatchSend 尾段同序列（禁第二条请求链）**——两消费
  // 方恰 2 处（assert-app-domain 95 组钉）；守卫销毁闸/发送闸在段首（重试基线写库完成才到这）
  launchRetryRound(conn: AiConnection): void {
    this.snapshot.buildMemoryBlock()
      .then((memoryBlock: string): Promise<void> => this.snapshot.buildSkillContext('')
        .then((skillCtx: SkillSendContext): void => {
          if (this.disposed || !this.refs.sending()) {
            return;
          }
          const history: AiChatMessage[] = buildRequestHistory(this.refs.dataSource.allMessages());
          const req: RoundRequest = this.assembleRound(conn, history, memoryBlock, skillCtx);
          this.toolRound.resetForNewSend(req.tools, this.promptState.toolStepLimit());
          AppStorage.setOrCreate<number>(CHAT_SEARCH_COUNT_KEY, this.promptState.searchResultCount());
          AppStorage.setOrCreate<string>(CHAT_ACTIVE_CONV_KEY, this.refs.conversationId());
          // 记忆作用域中转键（v35 缝补：重试轮工具执行器选库同发送语义）
          AppStorage.setOrCreate<string>(MEMORY_EXEC_ASSISTANT_KEY,
            this.promptState.memoryScope() === MEMORY_SCOPE_ASSISTANT ?
              this.promptState.ownerAssistantId() : '');
          // 知识库执行者中转键（v38 缝补：重试轮 search_knowledge 同发送语义；取值口径与
          // 初发点一致——无条件取 ownerAssistantId）
          AppStorage.setOrCreate<string>(KNOWLEDGE_EXEC_ASSISTANT_KEY,
            this.promptState.ownerAssistantId());
          this.usageRound.reset();
          // 自动重试域复位（2026-09-22）：重试轮同为新轮——计数与停止标记归零、在途退避取消
          this.autoRetry.resetForRound();
          this.keyRound.startRound(conn, req.history, req.thinking, req.sampling);
        }));
  }

  // 轮次请求组装（2026-09-14 消息底栏笔自 dispatchSend 抽出成段——抽段本身保留；
  // ★ 2026-09-20 重试真链复活：两消费方 = dispatchSend + launchRetryRound〔重试组装段，
  // ChatRetryHost 回接〕——禁第二条请求链的锚点）：上下文截尾 → 提示词注入（变量替换随
  // 每次组装取当下时刻）→ 技能清单/记忆块（两条顺序红线见原注释）→ 思考档位门控 →
  // 采样五字段 → 工具声明全链（联网三级过滤 + 模式驱动两件 + 跨会话隐私闸）。
  // history 入口 = 落屏历史 + 本条 userReq（发送）或纯落屏流（重试——目标行 text 已清空，
  // 空内容跳过自然截断到该轮 user）
  private assembleRound(conn: AiConnection, history: AiChatMessage[], memoryBlock: string,
    skillCtx: SkillSendContext): RoundRequest {
    // 上下文消息数截取（2026-09-01 高级设定）：助手参数 contextCount > 0 时发送序列保
    // 尾部 N 条（★ 计数含本条 user）；截取在注入之前——system 头注与深度注入基于截后
    // 序列计算，身份注入永不丢（首条历史被截 = 「只发最近 N 条」预期语义）
    const advanced: AssistantAdvancedParams | null = this.promptState.advancedParams();
    const clipLimit: number =
      advanced !== null && advanced.contextCount !== undefined ? advanced.contextCount : 0;
    const clipped: AiChatMessage[] = clipHistoryKeepingSummary(history, clipLimit);
    // 提示词注入（2026-08-30：promptState 非空 → 按配置组装（身份/位置/深度，协议
    // 交替守卫在组装层；目标 user 带图时 images 随行）；null = 原样——默认行为不变；
    // 协议方言翻译在各协议层，断言保护 ⑪⑭⑮⑰ 组。
    // 2026-09-01 助手域；★2026-09-04 归属与注入解耦：解析优先级 = 会话提示词 > 助手提示词
    // > 系统提示词（ChatPromptState——归属恒在，提示词注入开关只换注入源）；
    // applyVariables 发送前做 {{date}}/{{char}} 等变量替换（每次发送取当下时刻，任意注入
    // 源统一生效——PromptVariables 调研定论：应用层替换，无需工具调用）。applied 单独持变量
    //（2026-09-17 会话上下文用量）：注入内容同时是上下文估算的「提示词」段输入
    const applied: PromptInjectConfig | null =
      this.promptState.applyVariables(this.promptState.config(), conn.model);
    const finalHistory: AiChatMessage[] = composeSendMessages(clipped, applied);
    // 技能清单注入（2026-09-13 技能层笔 1，方案 §2.4）：★ 两条顺序红线——①必须在
    // composeSendMessages **之后**（该函数 system 分支遇「历史已含 system」会整体跳过，
    // 提前调用会把会话/助手/系统提示词吞掉）；②必须在 appendSystemMemory **之前**
    //（稳定块〔技能清单〕在前、易变块〔记忆〕在后——两块同住一条 system 消息，顺序即
    // 前缀缓存命中段长度）。判据与先例注释见 appendSystemSkills 头注释；manifest 空 =
    // 原样零回归（负向钉：零启用技能 = 请求逐字节同无技能版）
    const skillHistory: AiChatMessage[] =
      appendSystemSkills(finalHistory, skillCtx.manifest);
    // 记忆注入（2026-09-08 记忆域）：★ 必须在 composeSendMessages **之后**——该函数的
    // system 分支遇「历史已含 system」会整体跳过，提前调用会把会话/助手/系统提示词吞掉
    // （顺序红线，sse-assert 断言 + appendSystemMemory 注释互证）；block 空 = 原样零回归。
    // ★ 2026-09-13 技能层笔补：还在技能清单 appendSystemSkills **之后**（稳定块在前）
    const sentHistory: AiChatMessage[] = appendSystemMemory(skillHistory, memoryBlock);
    // 思考档位 + 采样五字段 + 上限联动（2026-09-23 输出上限与超时治理笔 2 域级最小拆分：
    // 该段整域迁 common/providers/RoundParams，判据链与沿革注释随迁彼件——本处只留取值）
    const rp: RoundParams = resolveRoundParams(conn, this.refs.thinking(), advanced);
    const thinking: string = rp.thinking;
    const sampling: SamplingParams | null = rp.sampling;

    // 工具声明（2026-09-02 工具调用底层）：声明随轮次复用（失败切换同参）。★ 2026-09-17
    // 会话上下文用量笔迁 ChatContextUsageCalc.collectTools 单源（判据逐句等价搬迁）——发送
    // 组装与面板活算同一链，两处漂移即「面板与实发不一致」；三级过滤（联网域收敛进
    // webDomainAllowed 单判据）+ 模式驱动两件（记忆按需读取/技能加载）+ 跨会话隐私闸的
    // 完整判据链见 calc 注释。空清单 = []（请求体不带 tools 字段零回归）
    const roundTools: AiToolDef[] = this.ctxCalc.collectTools({
      manifest: skillCtx.manifest,
      useSkillNames: skillCtx.hasEnabled ? skillCtx.skillNames : []
    });
    // 上下文估算定格（2026-09-17 会话上下文用量）：注入侧快照 + 截尾后最终序列——k 校准
    // 的分母侧与本轮实发同链同源（方案 §六-2：截尾后的才是真发送序列）；每次起流前
    // refreshEstimate 对齐本流（工具轮续轮历史已长）
    this.ctxCalc.beginRound({
      systemText: applied !== null ? applied.content : '',
      skillManifest: skillCtx.manifest,
      memoryBlock: memoryBlock,
      toolDefsJson: toolDefsJsonOf(roundTools),
      maxOutput: advanced !== null && advanced.maxOutput !== undefined ? advanced.maxOutput : 0
    }, sentHistory);
    return { history: sentHistory, thinking: thinking, sampling: sampling, tools: roundTools };
  }

  // 中止（M1 onStop 语义）：取钥间隙/工具轮执行期无活跃流时直接收尾（防间隙续传——用户已
  // 明确停止）。★ 2026-09-09 工具层自检修复：工具轮执行期 activeStream 曾指向已收尾的流
  // 对象，abort() 走 `activeStream.abort()` → ChatStreamBase.fail 的 finished 首行守卫
  // 静默空转 = 停止键在工具执行期间失效（联网工具 5~20s 窗口内点停止无任何反应，模型继续
  // 续轮扣费）。修法 = onStreamDone 收尾即置 null（流已终态，引用不再有用）——停止键落
  // 下方 failRound 分支，工具轮 lane 的停止守卫接住（卡片补已中止、不落库不续轮）。
  abort(): void {
    // ★ 2026-09-22 自动重试笔：置轮内停止标记 + 取消在途退避（域件 markUserStop，两句一体），
    // **必须早于下方任何收尾**——「已手动停止」与网络错误同为 -1，判据只靠该标记区分；漏置
    // 则退避到点会把用户已停止的请求又发出去
    this.autoRetry.markUserStop();
    // 在途 http_request 立即掐断（2026-09-19 HTTP 请求工具笔）：destroy 在途 request →
    // promise 以错误结算 → 工具轮 lane 收尾守卫把卡转「已中止」（30s 读超时兜底口径见
    // ToolHttp.httpAbortAll 注释）
    httpAbortAll();
    // 退避期的 activeStream 已被自动重试分支置空（见 onStreamError），故停止键落 else 分支
    // 即时收尾（notice 行 + 输入栏回可发送态）——不是「点了没反应」
    if (this.activeStream !== null) {
      this.activeStream.abort();
    } else if (this.refs.sending()) {
      this.failRound('已手动停止');
    }
  }

  // ask_user 答案上行（2026-09-02；ChatPage 交互卡提交 → 执行域挂起续跑）
  resolveAsk(callId: string, answerJson: string): void {
    toolRuntime.resolveAsk(callId, answerJson);
  }

  // browse_act 高危确认上行（2026-09-18 内置浏览器 P2·B 单元；ChatPage 确认卡作答 →
  // 工具轮域挂起续跑——薄委托，形制同 resolveAsk）
  resolveBrowseConfirm(callId: string, approved: boolean): void {
    toolRuntime.resolveBrowseConfirm(callId, approved);
  }

  // 页面销毁静默中止（红线：解绑回调防销毁后触 UI）；销毁闸拦住异步取钥续传（DB 残留
  // streaming 态由下次启动 markStreamingAsError 兜底转 error）
  disposeSilent(): void {
    this.disposed = true;
    // 自动重试域取消（2026-09-22）：在途退避定时器成对释放（创建点 takeOver）——防销毁后
    // 定时器到点重发（守卫拦得住，但定时器本身不该悬着）
    this.autoRetry.cancelBackoff();
    toolRuntime.cancelAllPending(); // 挂起交互兜底取消（防销毁后悬挂 Promise）
    httpAbortAll(); // 在途 http_request 同步掐断（同 abort 口径——离页不留悬挂网络请求）
    this.cube.settle(false); // 实验态 cancel 路径 dispose（硬约束 3：防后台 30Hz 烧帧；静默不吐）
    if (this.activeStream !== null) {
      this.activeStream.disposeSilent();
      this.activeStream = null;
    }
  }

  // ── Key 池轮次域宿主实现位（ChatKeyRoundHost，2026-09-20 拆分件）＋接口薄委托 ──

  // 当前 key 尝试薄委托（ChatToolRoundHost 接口实现位——工具轮续轮 startNextAssistantRound
  // 经宿主接口消费；域实现在 ChatKeyRoundCtrl）
  attemptCurrent(): void {
    this.keyRound.attemptCurrent();
  }

  // 起流前估算刷新（ctxCalc.refreshEstimate——k 校准分母侧与实际请求对齐）
  refreshEstimateFor(history: AiChatMessage[]): void {
    this.ctxCalc.refreshEstimate(history);
  }

  // 传输流构造（双引擎分流点 cube.createStream——CubeEngineHost.createNativeStream 的姊妹口）
  createStreamFor(conn: AiConnection): ChatStream {
    return this.cube.createStream(conn);
  }

  // 活跃流引用登记（Key 池域起流/切换清引用——abort 停止键消费面在本件）
  setActiveStream(stream: ChatStream): void {
    this.activeStream = stream;
  }

  // 本轮工具声明（Key 池起流随请求下发——toolRound.declarations 单源）
  toolDeclarations(): AiToolDef[] {
    return this.toolRound.declarations();
  }

  // ── 原生协议流构造（2026-09-18 拆分后仍留本域：原生引擎 = 发送域自身引擎；cube 分流点
  // 经 CubeEngineHost.createNativeStream 回接此处。方法体自拆分前逐字不变，仅可见性放宽）──

  // 原生协议流构造（三协议工厂分发；回调统一回本域出口）。onDone 四参（2026-09-06 用量
  // 采集改签名；2026-09-23 输出上限治理笔 2 加第三参截断标记；2026-09-23 首字耗时笔加第四
  // 参首字耗时）：usage = 本流归一用量（流内已 take-max；null = 无 usage 帧/失败流）、
  // truncated = 本流是否被输出上限截断、firstTokenMs = 本流首字耗时毫秒（0 = 未产出正文/
  // 思考增量，口径见 AiTypes.AiStreamHandlers 第四参注释）
  createNativeStream(conn: AiConnection): ChatStream {
    return createChatStream(conn.protocol, conn.endpoint, {
      onDelta: (delta: SseDelta): void => this.onStreamDelta(delta),
      onDone: (usage: AiUsageDelta | null, durationMs: number, truncated: boolean,
        firstTokenMs: number): void =>
        this.onStreamDone(usage, durationMs, truncated, firstTokenMs),
      onError: (message: string, status: number, sawContent: boolean): void =>
        this.onStreamError(message, status, sawContent)
    });
  }

  // 最终失败呈报（M1 语义：notice 气泡可见 + 落库 error，不静默）；工具挂起交互一并
  // 兜底取消（ask_user 挂起等答时的停止/失败路径防悬挂）。★ 2026-09-20 起兼
  // ChatKeyRoundHost.failRound 实现位（Key 池域迁出后可见性放宽，语义零变化）
  failRound(message: string): void {
    toolRuntime.cancelAllPending();
    const notice: ChatMessage = newChatMessage(nextMessageId('notice'), 'notice', message, '', '', 'error');
    this.refs.dataSource.push(notice);
    this.finishStream('error');
  }

  private onStreamDelta(delta: SseDelta): void {
    // 自动重试状态行让位（2026-09-22）：有内容上屏即撤下状态行——它只属于「还没有任何产出」
    // 那段窗口。短路在域件内（本轮没写过状态行时零查表开销）
    this.autoRetry.clearHintIfShown();
    // 工具调用增量喂聚合器（与正文/思考增量互不干扰；无工具帧零开销）——聚合域在
    // ChatToolRoundCtrl（2026-09-08 域级拆分）
    if (delta.toolCalls !== undefined && delta.toolCalls.length > 0) {
      this.toolRound.feedToolCalls(delta.toolCalls);
    }
    // reasoning item 捕获（2026-09-06 Responses 修复）：同 id 后到覆盖（done 终值盖 added）
    if (delta.reasoningItems !== undefined) {
      this.toolRound.captureReasoningItems(delta.reasoningItems);
    }
    if (delta.reasoningContent !== '') {
      this.thinkingFull += delta.reasoningContent;
      if (this.liveThinkingId === '') {
        // 思考块懒创建（无 reasoning_content 的 provider 永不创建 = 自动隐藏），
        // 插在助手占位气泡之前（思考在回答上方）；★ 2026-09-01 回传契约：
        // linkId = liveAssistantId（发送组装时依此把思考并回 assistant 消息的 reasoning）
        const thinkingMsg: ChatMessage = newChatMessage(nextMessageId('think'), 'thinking', '');
        thinkingMsg.linkId = this.liveAssistantId;
        // 生成中标记（2026-09-16 三态收口）：思考折叠块的「折叠显 3 行预览」态判据——
        // 与正文行的 streaming 同字段两 kind 共用（口径见 ChatMessageCompose 字段注释）；
        // 建行即置真（插入前落值，首帧就是折叠高，不闪 0 高再撑开）
        thinkingMsg.streaming = true;
        this.refs.dataSource.insertBefore(this.liveAssistantId, thinkingMsg);
        this.liveThinkingId = thinkingMsg.id;
        // 同泡化标记（2026-09-16 思考块收入气泡）：正文泡上缘切直角与思考半泡拼接——
        // 建思考行处成对置位（回放/翻页两链同款，见 ChatMessageCompose.thinkAbove 注释）
        const bodyMsg: ChatMessage | null = this.refs.dataSource.findMessage(this.liveAssistantId);
        if (bodyMsg !== null) {
          bodyMsg.thinkAbove = true;
        }
      }
      this.cube.feed(this.liveThinkingId, delta.reasoningContent);
    }
    if (delta.content !== '') {
      this.assistantFull += delta.content;
      this.cube.feed(this.liveAssistantId, delta.content);
    }
    this.refs.follow.maybeFollow();
  }

  private onStreamDone(usage: AiUsageDelta | null, durationMs: number, truncated: boolean,
    firstTokenMs: number): void {
    // ★ 2026-09-09 工具层自检修复：流已终态——引用即刻置空（工具轮执行期 abort() 才落到
    // failRound 分支；旧实现留着 finished 流对象使停止键静默失效，详见 abort() 头注释）
    this.activeStream = null;
    // 轮级累积（2026-09-23 首字耗时笔域级最小拆分后 = 本件唯一接线点）：用量四值跨流求和 /
    // 截断末流胜出 / 首字首个非 0 胜出——三条口径与理由全在 ChatUsageRoundCtrl 域头注释
    //（禁在本件重写口径）
    this.usageRound.accumulateStream(usage, durationMs, truncated, firstTokenMs);
    if (usage !== null) {
      // ★ 上下文锚点与 k 校准（2026-09-17 方案-会话上下文用量）——**两口径并存**（Open
      // WebUI #29064「有意求和」先例，禁后人「统一」）：上方整轮累积器 = 工具轮 N 流跨流
      // 求和（计费口径——N 轮工具后约为真实规模的 N 倍，拿它当上下文规模必放大显示）；
      // 锚点 = 本流 promptTokens（含全部历史 + 提示词 + 工具定义 + 工具结果 = 当前上下文
      // 规模的真度量），工具轮多次 onStreamDone 后者覆盖前者 = **最后一次流胜出**；只认
      // input 侧字段（totalTokens 不可靠）；k = 锚点 ÷ 本流估算（refreshEstimate 已对齐），
      // 钳制后按模型落偏好键
      const anchorConn: AiConnection | null = this.keyRound.currentConn();
      if (usage.promptTokens > 0 && anchorConn !== null) {
        this.ctxCalc.recordAnchor(usage.promptTokens, anchorConn);
      }
    } else {
      // 用量诊断（2026-09-06 completion 无用量排查笔）：流正常结束但全程未收到 usage 帧——
      // 官方直连四方言均应有（仅 completion 需端侧响应 stream_options.include_usage；中转
      // 网关静默忽略该键即此形态）。warn 只带协议/模型，不含内容与密钥。
      // ★ 同日晚三更结案：诊断 toast 随真机验证完成撤除（warn 留档不撤）。当夜复核翻盘
      // 「端侧不回传」初判——真根因 = SseParser.parseChatDelta 丢「usage 挂末内容帧」形态
      //（DeepSeek 官方文档明示无独立统计帧），已修；warn 转作端侧确不回传场景的留档
      const diagConn: AiConnection | null = this.keyRound.currentConn();
      hilog.warn(0x0001, 'ChatSend', '用量诊断：本流未收到 usage 帧（协议 %{public}s，模型 %{public}s）',
        diagConn !== null ? diagConn.protocol : 'unknown',
        diagConn !== null ? diagConn.model : 'unknown');
    }
    // 工具调用轮判定（2026-09-02）：聚合出完整调用且本轮带工具声明且未到轮上限 → 进入
    // 工具执行轮（结果回传后续请求）；否则按既有单轮收尾。到上限后的多余调用不静默吞：
    // ★ 2026-09-06 触顶可见化：notice 一行说明「为何停」（上限存在但不可见 = 真机 responses
    // 工具循环反馈的伴随问题）；★ 2026-09-09 A2 让位轮：首次触顶给模型一轮「知情收尾」
    //（被丢弃的调用以合成工具结果回传，见 grantLimitGrace），让位轮后仍触顶才直接收尾
    const calls: AiToolCall[] = this.toolRound.pendingCalls();
    if (calls.length > 0 && this.toolRound.hasDeclarations() && this.toolRound.hasBudget()) {
      this.toolRound.beginToolRound(calls);
      return;
    }
    if (calls.length > 0 && this.toolRound.hasDeclarations() &&
      this.toolRound.canGrantLimitGrace()) {
      // notice 只落首次触顶（让位轮后仍触顶 = 说明已在屏上，不重复落行）；数字取本轮
      // 生效上限（助手级配置——0 = 不限制时即内置硬顶 256，与实际闸门同源）
      this.refs.dataSource.push(newChatMessage(nextMessageId('notice'), 'notice',
        '工具调用已达 ' + this.toolRound.roundLimit() + ' 轮上限，已停止执行后续调用'));
      this.toolRound.grantLimitGrace(calls);
      return;
    }
    this.finishStream('done');
  }

  private onStreamError(message: string, status: number, sawContent: boolean): void {
    // key 级失败（401/403/429）且池内还有未试 key → 静默切换重发（本条错误不上屏）；
    // 网络错误/手动停止（-1）与其余状态码 = 最终失败。重发必然零增量（非 200 无流，
    // 状态码先于 body），占位气泡与库行原样复用
    if (RETRY_STATUSES.includes(status) && this.keyRound.tryNextKey(message)) {
      return;
    }
    // ★ 2026-09-22 自动重试域接管点（判据与退避调度全在 ChatAutoRetryCtrl，本处只接线）：
    // 网络层失败（-1）且本流零产出且非用户停止且开关开且次数未尽 → 退避重发同请求，本条失败
    // 不上屏、不 failRound（notice 行与收尾都留给最终失败）
    if (this.autoRetry.takeOver(status, sawContent)) {
      // ★★ 本笔最易漏且后果最重的一句（任务书 U7-2a）：退避期必须置空流引用。漏做 = 用户在这
      // 几秒点停止会落进 abort() 的 activeStream.abort() 分支，而该流已 finished（fail 首行
      // 守卫吞掉调用）→ 停止键死键、轮次既不收尾也不重发（与 2026-09-09 已修的「工具轮执行期
      // 停止键失效」同族）。照 onStreamDone 与 tryNextKey 同法（流已终态，引用不再有用）
      this.activeStream = null;
      return;
    }
    this.failRound(this.autoRetry.decorateFinalMessage(message));
  }

  // 流式收尾（done/error 统一）：未刷增量丢弃 + 全量覆盖 + 一次性落库 + 状态复位（含
  // 轮次态清空防陈旧续传）
  private finishStream(status: string): void {
    // 快照命名 assistantMsgId（2026-09-04 观察项改名，语义同 beginToolRound）——消息 id
    // 与助手归属 id 断名
    const assistantMsgId: string = this.liveAssistantId;
    // 用量快照（2026-09-06；★ 五值全部局部快照——①roundConn 在下方收尾区置 null，归属
    // 快照必须前置（照 assistantMsgId 快照先例）；②finalizeMessage 异步完成后才落
    // 账本，彼时用户可能已开新一轮发送（成员累积器被清零重计）——局部值杜绝错位）
    const settleConn: AiConnection | null = this.keyRound.currentConn();
    const usageProviderId: string = settleConn !== null ? settleConn.providerId : '';
    const usageModelId: string = settleConn !== null ? settleConn.model : '';
    // 轮级用量快照（2026-09-23 域级最小拆分后取自 ChatUsageRoundCtrl.values）；★ 本地快照
    // 必须前置——①roundConn 在下方收尾区置 null，归属快照先行（照 assistantMsgId 快照先例）；
    // ②finalizeMessage 异步完成后才落账本，彼时用户可能已开新一轮发送（累积器被清零重计）
    // ——局部值杜绝错位（快照语义见该件 values 注释）
    const roundUsage: RoundUsageValues = this.usageRound.values();
    const usagePrompt: number = roundUsage.prompt;
    const usageCompletion: number = roundUsage.completion;
    const usageDurationMs: number = roundUsage.durationMs;
    const usageCached: number = roundUsage.cached;
    const usageFirstTokenMs: number = roundUsage.firstTokenMs;
    // 实验态打字机收口（硬约束 3/4）：先同步吐完剩余揭示 → 释放 displaySync；随后既有
    // 全量覆盖逻辑零改动衔接（msg.text 落全量、落库 authority 在 assistantFull）
    this.cube.settle(true);
    this.throttle().drop(assistantMsgId);
    if (this.liveThinkingId !== '') {
      this.throttle().drop(this.liveThinkingId);
    }
    const assistantMsg: ChatMessage | null = this.refs.dataSource.findMessage(assistantMsgId);
    if (assistantMsg !== null) {
      assistantMsg.text = this.assistantFull;
      // 底栏两判据收口（2026-09-14 消息气泡底栏；done/error 两路都经此——失败与手动停止
      // 轮同样获得底栏，拍板 2a）：streaming 置假出底栏；tail 置真出重试键（failRound 的
      // notice 行先 push 清过 tail，此处置回——本条终为末条助手消息）
      assistantMsg.streaming = false;
      assistantMsg.tail = true;
      // 截断尾注挂载（2026-09-23 输出上限治理笔 2）：与 streaming/tail 同段（同属「本轮收口
      // 态」）。★ 隐私会话**同样挂**——与下方 usage 四值的 !privateMode 旁路不同：usage 旁路
      // 的口径是「全程零留痕，meta 也不显示」（指向库），而截断提示是**回答质量状态**（同类
      // 先例 = retryHint 状态行同样无隐私判据，ChatMessageItem 只查字段非空），且隐私会话的
      // 消息正文本身就在屏上——零留痕指向库，不指向屏。勿照 usage 补 !privateMode 守卫
      assistantMsg.truncated = roundUsage.truncated;
      // 用量 meta 行数据挂载（2026-09-06；2026-09-20 口径变更：中断轮也挂——账本 error 轮
      // 同落〔同笔拍板〕，回放链 attachUsageMeta 按 messageId 命中即挂、无从区分中断轮，
      // 实时不挂重启即显，两链必须同口径）。存量/工具轮中间行天然无（中间行走
      // beginToolRound 收尾不经此；字段 undefined 即不渲染）。隐私会话旁路（口径：全程
      // 零留痕，meta 也不显示）
      if (!this.refs.privateMode() &&
        (usagePrompt > 0 || usageCompletion > 0)) {
        assistantMsg.usageTokens = usagePrompt + usageCompletion;
        assistantMsg.usageCompletionTokens = usageCompletion;
        assistantMsg.usageDurationMs = usageDurationMs;
        // 首字耗时（2026-09-23 首字耗时笔）：>0 才挂（undefined 即不渲染——与缓存段同款
        // 零噪声口径：本流无正文/思考产出、空响应、纯工具调用轮天然无此行）。★ 与 usage
        // 四值同块 ⇒ 同受「隐私会话旁路」与「usage > 0」两道守卫：无 usage 帧的流连「用时」
        // 都不显示，首字同族不单飞
        if (usageFirstTokenMs > 0) {
          assistantMsg.usageFirstTokenMs = usageFirstTokenMs;
        }
        // 缓存命中段（2026-09-10）：>0 才挂（undefined 即不渲染——无缓存协议/短对话
        // 零噪声；输入数已含命中部分，段只是标注）
        if (usageCached > 0) {
          assistantMsg.usageCachedTokens = usageCached;
        }
      }
    }
    if (this.liveThinkingId !== '') {
      const thinkingMsg: ChatMessage | null = this.refs.dataSource.findMessage(this.liveThinkingId);
      if (thinkingMsg !== null) {
        thinkingMsg.text = this.thinkingFull;
        // 思考行收口（2026-09-16 三态收口）：流结束 = 本条已完成——折叠态收拢为 0（组件侧
        // 见 streaming 真→假的 @Watch）；done/error 两路都经此（停止与失败轮同按已结束处理）
        thinkingMsg.streaming = false;
      }
    }
    const content: string = this.assistantFull;
    const reasoning: string = this.thinkingFull;
    this.refs.setSending(false);
    this.activeStream = null;
    this.keyRound.resetForSettle();
    this.toolRound.resetForNewSend([]);
    // 自动重试域收尾复位（2026-09-22）：计数与停止标记归零 + 状态行抹掉（done/error 两路都经
    // 此 = 兜底清空；途中已随首帧让位的再清一次，防任何路径残留到下一轮）
    this.autoRetry.resetForRound();
    // ★ 2026-09-20 切换键不显修复笔（七百九十五节）：重试域版本态**不在此复位簇清零**——
    // 本簇下方还有五列收尾（applyFinalVariant 要读版本基线判「终版落哪行、列表共几版」），
    // 簇内提前清零会让判据读到空（793 判据 roundVariantId / 794 判据 baseVariants 同被这
    // 一次清零抹掉）→ 五列永不落库、内存 variantCount 恒 1 → 底栏 ‹ i/N › 恒不显（真机
    // 报障「不显示回放切换键」）。清零改挂收尾块**之后**（见 finishStream 末），复位簇只
    // 清轮次态三件
    // 轮次收尾通知（2026-09-17 会话上下文用量）：done/error 两路都经此——页面重算上下文
    // 圆环（方案 §3.6「真值到达 = 最准时刻」；可选钩子无消费方零开销）
    if (this.refs.onRoundSettled !== undefined) {
      this.refs.onRoundSettled();
    }
    // 收尾落库——隐私会话旁路（2026-09-04，本域第五个也是最后一个写库点）。★ 2026-09-20
    // 多版本收尾（DB v36）：重试轮 → 终版并入版本基线走 finalizeMessageVariant 五列落库
    //（content 投影 + 全量真源 + 选中下标同条 UPDATE，防中间态），底栏切换键随新答案出现
    //（variantCount/active 原地改）；非重试轮/基线缺失回 null 走原三列。★ 同日真机修复笔：
    // 判据由「终态行 = 重试目标行」放宽为「版本基线非空」——工具轮形态终态行是**新建承载
    // 行**（重试目标行已整轮作废删除），放宽后终版恒落末条（tail 恒真）→ 切换键可达。
    // 版本态清零不在此处（须先让本块消费——位置约束见复位簇注释与块末清零点）
    if (!this.refs.privateMode() && assistantMsgId !== '' && this.refs.dbReady()) {
      // 终版组装委托重试域（applyFinalVariant：终版并入 variants 返回五列落库载荷并清
      // 版本态；工具轮形态/普通轮回 null 走三列——判据与推进逻辑在 ChatRetryCtrl）
      const variantFinal: VariantFinalizePayload | null = this.retry.applyFinalVariant(
        assistantMsgId, content, reasoning,
        { prompt: usagePrompt, completion: usageCompletion,
          durationMs: usageDurationMs, cached: usageCached,
          firstTokenMs: usageFirstTokenMs });
      const finalizePromise: Promise<void> = variantFinal !== null ?
        finalizeMessageVariant(assistantMsgId, content, reasoning, status, variantFinal.variants,
          variantFinal.active) :
        finalizeMessage(assistantMsgId, content, reasoning, status);
      if (variantFinal !== null && assistantMsg !== null) {
        assistantMsg.variantCount = variantFinal.count;
        assistantMsg.variantActive = variantFinal.active;
      }
      finalizePromise
        .then((): void => {
          // AI 标题生成触发（2026-09-05 任务 6）：落库完成后 fire-and-forget——保证
          // 生成链 queryRecentMessages 能读到刚完成的 assistant 正文；此处为唯一最终
          // 收尾点（单轮与工具轮最终 done 均恰收敛于此一次，beginToolRound 中间态不经
          // 此）；失败/未配置在 TitleGen 内静默放弃，不打扰对话链
          if (status === 'done') {
            generateTitleForConversation(this.refs.conversationId());
            // 推荐问题生成触发（2026-09-19 推荐问题功能，generateTitleForConversation 调用
            // 同位）：落库完成后 fire-and-forget——该点是单轮与工具轮最终 done 恰收敛一次
            // 的唯一收尾点，失败/停止/工具轮中间态天然不进（标题生成既有判据）；隐私会话
            // 由外层 !privateMode 块过滤（SuggestGen 无从判隐私态，TitleGen 同口径）；
            // 未配置/开关关在 SuggestGen 守卫序内静默放弃，不打扰对话链
            generateSuggestForMessage(this.refs.conversationId(), assistantMsgId);
          }
          // 用量账本落库（2026-09-06；2026-09-20 决明拍板口径变更：error 轮也落——中断轮
          // 内已完整收尾的流是真实消耗，照计入（LibreChat abortMiddleware「中断轮照常
          // 持久化」同款；原 done-only 形态 = AI SDK 家 vercel/ai #7628 的框架层限制，
          // 非设计优势）。被停的那条流 usage 帧在流末、fail 路径无 onDone，天然不进累积
          // 器，零虚记；页面销毁走 disposeSilent 静默不经此处。purpose 恒 'chat' 与完成
          // 轮同码——账本无 status 维度，消费方（统计页/费用页/两工具/会话统计/模型使用
          // 检测）零改动，按实际消耗如实计入；锚点与 k 校准不随放，仍只认 onStreamDone
          // 完整流（assert-ctx-usage 121 组 A 段）。Key 失败切换重试天然只记成功流。归属
          // = 流前快照，数值 = 局部快照（防连发错位，见方法头注释）；conversationId 取
          // 当下值与标题生成同点同姿势。账本失败不影响对话链——hilog 留痕可观测
          if (usagePrompt > 0 || usageCompletion > 0) {
            insertUsageEvent(this.refs.conversationId(), assistantMsgId, usageProviderId,
              usageModelId, usagePrompt, usageCompletion, usageCached, usageDurationMs,
              usageFirstTokenMs, 'chat')
              .catch((e: Object): void => {
                hilog.warn(0x0001, 'ChatSend', '用量账本落库失败：%{public}s',
                  (e as Error).message);
              });
          }
        })
        .catch((e: Object): void => {
          this.refs.toast('消息落库失败：' + (e as Error).message);
        });
    }
    // 版本态收尾清零（★ 位置 = 硬约束：必须在五列收尾**消费之后**——见复位簇注释；提前回
    // 簇内 = applyFinalVariant 判据恒空、底栏切换键恒不显）。落此处覆盖收尾块全旁路（隐私
    // 会话 / 占位 id 空 / 库未就绪 / 降级无版本模式），防重试态漂到下一轮；新发送轮在
    // dispatchSend 轮首另双清
    this.retry.resetRound();
  }

  // 节流 flush：全量覆盖（delta 参数只作触发与计数，内容以本域累积串为准）
  private flushFrame(frameId: string, delta: string): number {
    const msg: ChatMessage | null = this.refs.dataSource.findMessage(frameId);
    if (msg === null) {
      return 0;
    }
    msg.text = frameId === this.liveAssistantId ? this.assistantFull : this.thinkingFull;
    return msg.text.length;
  }

  // ── 自动重试域宿主接口实现位（ChatAutoRetryHost，2026-09-22 笔）——薄直通；isDisposed /
  // isSending 与工具轮域、attemptCurrent 与 Key 池轮次域各共用一处实现，故本节只落两件 ──

  // 自动重试开关现读（判据④；单一来源 AppPreferences.isAutoRetryEnabled——别名导入防同名遮蔽；
  // 开关值轮首现读一次、轮内锁定，域件只在接管当刻读取）
  isAutoRetryEnabled(): boolean {
    return isAutoRetryPrefEnabled();
  }

  // 状态行写入（域件在「接管」与「让位」两点调用）：改**当前占位气泡**运行时字段，@Observed
  // 原地改即刷（不走 renderEpoch）；消息不在（理论不可达）静默跳过，勿新建消息行（D7 红线）
  setRetryHint(text: string): void {
    const msg: ChatMessage | null = this.refs.dataSource.findMessage(this.liveAssistantId);
    if (msg === null) {
      return;
    }
    msg.retryHint = text === '' ? undefined : text;
  }

  // ── 工具轮域宿主接口实现位（ChatToolRoundHost，2026-09-08 拆分）——可见性因接口放宽
  // 或薄包装，语义零变化 ──

  isDisposed(): boolean {
    return this.disposed;
  }

  isSending(): boolean {
    return this.refs.sending();
  }

  isPrivateMode(): boolean {
    return this.refs.privateMode();
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

  maybeFollow(): void {
    this.refs.follow.maybeFollow();
  }

  getLiveAssistantId(): string {
    return this.liveAssistantId;
  }

  setLiveAssistantId(id: string): void {
    this.liveAssistantId = id;
  }

  getLiveThinkingId(): string {
    return this.liveThinkingId;
  }

  setLiveThinkingId(id: string): void {
    this.liveThinkingId = id;
  }

  getAssistantFull(): string {
    return this.assistantFull;
  }

  setAssistantFull(value: string): void {
    this.assistantFull = value;
  }

  getThinkingFull(): string {
    return this.thinkingFull;
  }

  setThinkingFull(value: string): void {
    this.thinkingFull = value;
  }

  roundHistoryRef(): AiChatMessage[] {
    return this.keyRound.currentHistory();
  }

  dropThrottle(frameId: string): void {
    this.throttle().drop(frameId);
  }

  rebuildCubeFlushers(): void {
    // 实验态新一轮（startNextAssistantRound 轮开动作整体薄包装）：三频道重建 + 揭示指针
    // 清零——2026-09-18 拆分后与 dispatchSend 轮首同走 cube.rebuild 单一入口（两处同款
    // 三行不再各写一遍）
    this.cube.rebuild();
  }

  // ── 多版本（DB v36，2026-09-20 消息重新生成；ChatToolRoundHost 实现位）──
  // 工具轮中间收尾取版本载荷：重试目标行的 settle → 半截版（content/reasoning 为 settle
  // 侧已快照的本轮值、usage 取本轮跨流累积——settle 时第一流 done 已计入）并入数组并
  // 组装五列落库载荷；**同时推进内部基线**（半截版已入数组——后续路径不会重复并入）。
  // 普通轮/工具轮续行回 null（settle 侧走三列落库）
  takeVariantPayloadFor(msgId: string, content: string,
    reasoning: string): MessageVariantPayload | null {
    // 组装逻辑在重试域（ChatRetryCtrl）——此处补传本轮跨流累积快照（settle 时第一流
    // done 已计入；重试轮起轮时已清零，普通轮恒 0 不参与）。★ 五值**逐字段显式列举**：
    // ArkTS 禁结构类型（结构类型传参直接编译不过，arkts-no-structural-typing 实锤于本次
    // 构建），且快照多出的 truncated 也不许自动忽略——多一值少一值都在此显式决定
    const snap: RoundUsageValues = this.usageRound.values();
    return this.retry.takeVariantPayloadFor(msgId, content, reasoning, {
      prompt: snap.prompt, completion: snap.completion, durationMs: snap.durationMs,
      cached: snap.cached, firstTokenMs: snap.firstTokenMs });
  }

  // ── Cube 实验引擎域宿主接口实现位（CubeEngineHost，2026-09-18 拆分）——与上节同姿势：
  // 可见性因接口放宽或薄包装，语义零变化；其中 dataSource/maybeFollow/getLiveAssistantId/
  // getLiveThinkingId/getAssistantFull/getThinkingFull 六件与 ChatToolRoundHost 同实现共用 ──

  // 实验态流末打字机收口（ChatToolRoundHost.settleCubeFlushers 实现位；2026-09-18 拆分后
  // 薄委托 cube.settle——两条收口路径仍在：finishStream 吐完 true / disposeSilent 静默 false）
  settleCubeFlushers(flush: boolean): void {
    this.cube.settle(flush);
  }

  // 页面 UIContext（cube 三频道 displaySync 须 runScopedTask 包裹，构造点经此取）
  uiContext(): UIContext | null {
    return this.refs.cubeUiContext();
  }

  // 原生分档节流入口（cube 分流点原生支薄包装 this.throttle().enqueue）
  enqueueThrottle(frameId: string, delta: string): void {
    this.throttle().enqueue(frameId, delta);
  }
}
