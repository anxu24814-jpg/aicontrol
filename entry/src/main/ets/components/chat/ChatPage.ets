// 聊天页装配：内容区 ChatPageContent / 发送 ChatSendCtrl / 加载刷新 ChatPageLoad / 附件
// AttachmentPickCtrl，本页留 @State/壳/面板开关。
// · 壳（任务 4 拍板）：自包 PageShell（标题栏覆盖层/标题栏菜单/半模态 bindSheet 须页面自持
//   ——PageMap 壳无法回传；转场透明坑38 由 PageShell 体系接管）；PageMapBuilder 薄构造。
// · 标题栏（★ 2026-11-15 B 路线两态笔）：覆盖层恒挂官方 stackBuilder，按会话标题文本
//   广播键切两态——无标题新会话 = 中央「模型|思考」加长双热区胶囊（与一级页顶部分段同长、
//   带沉浸光感）；有标题 = 中央两行（主标题 + 「模型 思考」副标题双热区）。右端恒为单圆键
//   〔⋯更多〕，「＋新建会话」收入菜单首项。两态判据与文案 = 会话行 title（本页反查链写
//   CHAT_TITLE_TEXT_KEY；标题生成链与历史列表显示零改动），旧「会话内不显示会话标题」
//   拍板（2026-09-09 二百一十五）自此仅部分复活——只在有标题态显示，新会话仍不显示。
//   「新建会话」= 本地生成会话 id + replacePath 跳转（坑57 同分支复用防；懒创建：首条消息
//   发送时才落会话行，落行写入归属助手 = ChatPromptState 有效绑定）；「更多」= openMenu。
// · 全屏输入（dshinhm 二一一改语义）：KimiFullInputSheet 半模态挂页面根 bindSheet（坑64
//   姿势）；init/draft/cmd/live 四通道见各字段注释。
// · 收发链路（M1 回归红线）：发送/停止经 ChatSendCtrl 薄委托；★ U9 起退页不断流——页面
//   销毁只解绑 UI 订阅（release 计数），生成照常跑在运行时（见 ChatSessionRuntime）。
// · 附件：+ 键开「附件与提示词」半模态（ChatPromptSheet）→ AttachmentPickCtrl（选择器→
//   沙箱→入列，恒 filesDir 常驻区）；发送随文本交 ChatSendCtrl（载荷成功文件一律留盘 +
//   元数据落库 + 简报装配，仅载荷失败即删——条件清理在 ChatSendCtrl.dispatchSend）；页面
//   销毁清删未发送附件（cleanupAttachments，不驻留）。附件查看器已二级页化
//   （AttachmentViewerPage，本页只把 pathStack 注入 ChatPageContent）。
// · 提示语义：加载失败 → errorText 覆盖层（含重试）；动作错误 → toast；流式 → notice 条。
// ★ 2026-09-26 隐私会话功能全链退役（决明拍板直接砍功能不留替代）——isPrivate 路由链、
//   标题栏标记、离页即焚、各控制器 privateMode 旁路整面删除；2026-11-17 加密会话亦整体退役
//   （进入门禁/锁标/生物识别偏好/权限全链撤除，v66 迁移清零 locked），本页进入与消息链零门禁。
// 拆分沿革（沿革详情与选缝评估见各件头注释，此处只留指针）：标题栏覆盖层内容域 →
// **ChatTitleBarOverlay.ets**（2026-09-27，本页留薄 @Builder 挂载 + 三动作回调 + @Link 双向
// 两枚）；标题栏菜单常量 → ChatTitleMenuFactory（09-17）；面板开关与手势关闭路由 →
// **ChatSheetCtrl.ets**（10-04 关闭链统一——半模态族统一件：可见性 `$$` 双向 + onWillDismiss
// 内 action.dismiss() 放行 + 关闭恒不复位内容形态）；会话级覆盖域 → **ChatSessionOverrideCtrl**
//（10-06，本页留内存覆盖真源 memoryOverride 与注入/调用接线）；全屏输入宿主 →
// **ChatFullInputHost**（10-17 排队总案 P2——busy 守卫与投递收口单源在彼件，Q2 起 busy 改判
// 入队）；排队面板族宿主 → **ChatQueueHost**（U3——'queue'/'queueEdit' 按 kind 分派，编辑态/
// 脏态确认/EDITING 占位配对释放单源在 ChatSheetCtrl）；七面板分支族 → **ChatSheetPanelsHost**
//（10-29——装配体与 kind 分派随迁件化非纯转发，写上行编排体留本页闭包经 refs 单口上行）；
// 菜单动作域 → ChatPageMenuCtrl（U1b）。本页 SheetHost 留 queue/queueEdit 与 input 两分支 +
// 七面板 else 挂载块，bindSheet 挂载与档位分发不动（坑64 姿势不变；全屏输入分支由 else 兜底
// 改显式 'input' 判断，sheetKind 值域封闭于 ChatSheetCtrl，行为等价）。
import { UIContext } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ChatEntryReadyFrame } from './ChatContentFrames';
import { AiConnection, ENDPOINT_RESPONSES, PendingAttachment, THINKING_OPTIONS, connectionOffEnabled,
  legalThinkingTier } from '../../common/providers/AiTypes';
// DS 官方档镜像键与判据（★ DS 全家桶接入批 S1，修订版任务书 S1②）：setConnInfo 同点同链
// 写广播键（照 CHAT_OFF_SUPPORTED_KEY 先例），判据单源在 DsServerTools 禁散写
import { CHAT_DS_OFFICIAL_AVAILABLE_KEY, CHAT_DS_RESPONSES_ENDPOINT_KEY,
  DS_SERVER_TOOLS_ENABLED, isDsFlashConnection } from '../../common/providers/DsServerTools';
import { DEFAULT_CONVERSATION_ID } from '../../common/store/ChatDb';
// 覆盖列三条读写口随会话级覆盖域迁 ChatSessionOverrideCtrl；本页余 ConversationOverride
// 类型（两注入点形参）
import { ConversationOverride } from '../../common/store/ChatDb';
import { CONN_RESOLVE_TICK_KEY, ActiveConnectionInfo } from '../../common/store/ProviderDb';
// 会话状态快照类型（状态面板 refs 注入侧整包类型——组装单源在 ChatPromptState.statusSource）
import { ChatStatusSource } from '../../common/chat/ChatPromptState';
import { conversationGraphBranch, conversationMigrateState } from '../../common/chat/ChatContextSource';
import { PageShell } from '../../common/PageShell';
// 材质解析随 2026-09-27 拆分迁 ChatTitleBarOverlay——本页光感档位仍自订阅（「更多」菜单传参用）
import { IMMERSIVE_LEVEL_KEY } from '../../common/ImmersiveLevel';
import { ROUTE_CHAT_PAGE, ROUTE_PHOTO_EDIT_PAGE, ROUTE_SESSION_TRACE_PAGE,
  ROUTE_SESSION_WORKSPACE_PAGE, ROUTE_SETTINGS_PAGE } from '../../common/RouteNames';
import { PhotoEditParam } from '../PhotoEditPage';
import { ChatDataSource } from './ChatDataSource';
import { chatSessionRuntime } from '../../common/chat/ChatSessionRuntime';
import { ChatFollowController } from './ChatFollowController';
import { ChatListAnchorJudge } from '../../common/chat/ChatListAnchorJudge';
import { enterConversation } from '../../common/chat/PermissionMode';
import { ChatPageContent } from './ChatPageContent';
import { ContextUsage } from './ChatContextUsage';
import { ChatPageLifecycle } from './ChatPageLifecycle';
import { ChatPageLoadCtrl } from './ChatPageLoad';
// 标题生成刷新广播（@Watch 转发标题数据供给域；两态判据与文案全在该域件）
import { CONV_TITLE_TICK_KEY } from '../../common/TitleGen';
import { ChatTitleSupplyCtrl } from './ChatPageTitleCtrl';
// 标题栏模型显示名广播键（★ 2026-11-25 五轮：标题栏单热区 + 卡内模型入口共用）
import { CHAT_TITLE_MODEL_KEY } from './ChatTitleMenuFactory';
import { AttachmentPickCtrl, removePendingAttachment, restoreDraftText, FilePickKind } from './AttachmentPickCtrl';
// 二期 S4 #12：附件单件重试通道（事件口登记——不经 InputBar/PageContent 入参面）
import { clearAttachmentRetry, registerAttachmentRetry } from '../../common/chat/AttachmentRetrySupport';
// 续写能力镜像与一次性判定复位（自检轮补：键显隐判据 + 连接切换重判）
import { CHAT_DS_CONTINUE_AVAILABLE_KEY, resetContinueUnsupported }
  from '../../common/chat/ChatContinueSupport';
// 会话草稿（2026-10-20 会话草稿持久化：域件单例——本页只接线，保存/恢复编排在 lifecycle）
import { removeDraft } from './ChatDraftStore';
import { attachBlockingReason, hasVisionCap, PhotoEditOutcome, ReissueGuideContext,
  willSendImages } from '../../common/AttachmentUtil';
import { AttachmentListRow } from '../../common/store/AttachmentDb';
import { TOOL_WORKSPACE_READ } from '../../common/providers/ToolIds';
import { visionConfirmOptions } from './ChatVisionConfirm';
import { DocParserHost } from '../../common/DocumentParse';
import { BrowseHost } from '../../common/BrowseWeb';
import { ChatMessageMenuCtrl } from './ChatMoreMenu';
// 聊天页菜单动作域（U1b 拆缝：更多菜单回调簇 + 菜单宿主生命周期 + 新建会话动作外迁，
// 选缝评估与反碎片申报见该件头注释）
import { ChatPageMenuCtrl } from './ChatPageMenuCtrl';
import { ChatBranchCtrl, BranchSwitchResult } from './ChatBranchCtrl';
// 分支判据结果类型（菜单域 retryAllow 回执——判据单源在 ChatBranchPolicy，本页只透传）
import { BranchAllow } from '../../common/chat/ChatBranchPolicy';
// 回答切换编排域（回答切换与操作优化笔；任务书 §5——本页只构造与传引用）
import { ChatAnswerCtrl } from './ChatAnswerCtrl';
// 四个广播键常量在本页 setConnInfo 写点，消费面在覆盖层与 ChatInputBar chip
import { CHAT_AI_ADMIN_OWNER_KEY, CHAT_OFF_SUPPORTED_KEY, CHAT_THINKING_HOLD_KEY,
  CHAT_THINKING_OPTIONS_KEY, CHAT_THINKING_VALUE_KEY, CHAT_WEBSEARCH_ALLOWED_KEY,
  CHAT_WEBSEARCH_ON_KEY } from './ChatParamChipBar';
// 侧栏主区标题栏命令键（DrawerHomeTitleBar 桥件下行；开抽屉命令消费方在 HomeNavigation）
import { CHAT_HOME_MORE_CMD_KEY, CHAT_HOME_OPEN_MODEL_CMD_KEY } from '../nav/DrawerHomeTitleBar';
// 全屏输入宿主域（P2 拆缝：装配与 onSend/onClose 编排外迁 ChatFullInputHost——本页留四通道
// @State 与宿主回接闭包；选缝评估与 QueueHost 缝弃选理由见该件头注释）
import { ChatFullInputHost } from './ChatFullInputHost';
import { ChatCompressCtrl } from './ChatCompressCtrl';
import { ChatSheetCtrl } from './ChatSheetCtrl';
// 会话级覆盖域（2026-10-06 域级最小拆分外迁——三法整段在彼件，本页留真源与调用点接线）
import { ChatSessionOverrideCtrl } from './ChatSessionOverrideCtrl';
import { ChatMessage } from './ChatMessageCompose';
// 会话助手身份发布（消息时间头笔：域件在 ChatMessageHeader——页面只留两调用点薄接线）
import { refreshChatHeadInfo } from './ChatMessageHeader';
import { ChatQueueHost } from './ChatQueueHost';
// 半模态七面板装配宿主（model/prompt/context/compress/editAssistant/stats/status 分支族
// 外迁——装配编排随迁非纯转发，沿革与判例见该件头注释）
import { ChatSheetPanelsHost } from './ChatSheetPanelsHost';
import { sheetPanelOptions, DETENTS_FULL, confirmSheetClose } from './KimiSheetCommon';
// 会话改动文件详情面板（任务② U5：'fileChanges' 形态——坑64 单挂载点 sheetKind 机新分支，
// 无新 bindSheet 宿主）
import { ChatFileChangesDetailPanel } from './ChatFileChangesDetailPanel';
import { FileChangeEntry } from './ChatFileChangesModel';
import { ChatTitleBarOverlay } from './ChatTitleBarOverlay';
// 排队入口条（★ 2026-10-17 排队插队总案 U1：标题栏下方带；状态 @Link 下行见字段注释）
import { QueueTopBand } from '../QueueTopBand';

// ★ 2026-10-25 rik 形态统一笔：失败轮重试占位链（占位文案 + 重试行上行 + 专属渲染件）已整链
// 删除——kind='retry' 全仓无产生方。
// 标题栏键件走共用件 TitleBarKeys（右端单圆键）；胶囊态中央宽度单源 = Theme.TITLE_CENTER_ZONE_*，
// 有标题态走避让全宽 + 对称内收 64（截断修复笔）；几何账见 ChatTitleBarOverlay 头注释；menuHds 恒传
// null（官方菜单数组无 builder 位）；隐私旧 92vp / 81vp 预算作废勿引用。

@Component
export struct ChatPage {
  // 目标会话 id（PageMapBuilder 注入：push 链路 = HomeNavigation.activeConvId、新建会话
  // replacePath = 路由 param；★ 2026-11-16 双形态笔：侧栏形态主区常驻态 = DrawerMainArea 注入
  // activeConvId 同源值，外层挂 key(conversationId) 驱动换会话销毁重建；普通成员——构造后
  // 不变，坑30 口径）
  conversationId: string = DEFAULT_CONVERSATION_ID;
  // 本地新造会话进入标记（2026-11-18 乐观空态笔）：true = conversationId 由本地
  // nextMessageId 生成（必然空），空态层不等读库回执即成立；两构造点注入、普通成员
  freshSession: boolean = false;
  // ★ 主区常驻态（2026-11-16 首页布局双形态笔，方案档 §2.3）：true = 侧栏形态主区——不走
  // PageShell/NavDestination 壳（★ 2026-11-17 对齐二级对话页笔：标题栏上收官方 HdsNavigation
  // stackBuilder 覆盖层 DrawerHomeTitleBar，本壳只排内容），新建会话经 onHomeNewSession 上抛
  // 换 id（replacePath 不适用）；false = 二级页形态（现状不变）。退页不断流语义两形态同源
  //（chatSessionRuntime 运行时账本）
  homeMode: boolean = false;
  // 主区常驻态：新建会话上行（「更多」菜单首项——菜单域生成的懒创建新 id 经此上抛，
  // DrawerMainArea 换 activeConvId 触发双交替重建即达；二级页形态不消费）
  onHomeNewSession: (newId: string) => void = () => {
  };
  // 顶部留白（标题栏蒙层下沿，PageMapBuilder 注入——内容起始避让，滚动时可滚入蒙层）
  @Prop topPad: number = 0;
  // 页面底部留白（vp，PageMapBuilder 注入 = 底部避让区高——全屏窗口下输入栏不压手势条；
  // @Prop：navBarHeight 异步实测，须状态驱动重渲染，坑57 同族）
  @Prop bottomPad: number = 0;
  // 官方路由栈（PageMapBuilder 注入：新建会话 replacePath 跳转用；普通成员不驱动 UI）
  pathStack: NavPathStack = new NavPathStack();
  // 系统分享路由 tick（PageMapBuilder 注入，普通成员；0 = 非分享拉起）——onShown 按 tick
  // 匹配消费桥内待发分享件，判据与入列全在 AttachmentPickCtrl.consumePendingShareInto（域件单源）
  shareTick: number = 0;
  // 草稿（会话草稿持久化）：draftTextLive = ChatInputBar @Watch 上行镜像（离页保存现读，
  // 非 @State 不驱动 UI）；draftKey = 本页草稿 key（lifecycle.restoreDraft 判定 /
  // dispatchSend 发送后修正；'' = 未判定，保存链走 '__new__' 窗口兜底）
  private draftTextLive: string = '';
  private draftKey: string = '';
  // 消息流（@State 持有 @Observed 数据源；LazyForEach 经 IDataSource 契约消费，@Track
  // messageCount 驱动空态分支）。★ U8 归运行时（工厂取件）；★ U9 重进重挂换源面——复用
  // 运行态实例，各域一律闭包现读（见 ChatPageLifecycle）
  @State private dataSource: ChatDataSource = chatSessionRuntime.newDataSource();
  @State private sending: boolean = false;
  // ── 排队入口条三值（★ 2026-10-17 排队插队总案 U1）：队列域 onChange 上行驱动——count/
  // paused 供条文案，active 同时驱动 titleBarBottomHidden 与内容区让位（同一变量同源，
  // 防「带隐藏了让位还在」错位）。@State 居页面（坑16：禁 @Prop 过 PageShell.content）
  @State private queueCount: number = 0;
  @State private queuePaused: boolean = false;
  @State private queueBandActive: boolean = false;
  @State private dbReady: boolean = false;
  // 初始加载失败提示（'' = 无；仅覆盖层语义——与 messageCount 联合判定，动作时错误走 toast）
  @State private errorText: string = '';
  // 思考档位（会话级 @State 不落库，'' = 默认不传；菜单选择落值经 refs 下发 ChatSendCtrl →
  // 协议方言落点）。选择入口 = 标题栏「思考」热区（二百二十九起，原输入栏 chip 退役，
  // 落值点见 ThinkingMenuBuilder）。★ 2026-11-17 对齐笔：@Watch 镜像发布
  // CHAT_THINKING_VALUE_KEY（drawer 主区标题栏覆盖层在 HomeNavigation 栈层，经桥键同步；
  // 二级页覆盖层 @Link 直连本 @State 不经键，发布面共存无害）
  @State @Watch('onThinkingValueChanged') private thinkingValue: string = '';
  // 镜像回执两枚：思考档位（drawer 覆盖层菜单落值经键下行消费回真源，与发布双端同值守卫
  // 收敛无环）+ 思考键交互期（菜单开合/按压下行；二级页覆盖层与输入栏两来路 @Link 直写不经键）
  @StorageProp(CHAT_THINKING_VALUE_KEY) @Watch('onThinkingValueEcho') private thinkingValueEcho: string = '';
  @StorageProp(CHAT_THINKING_HOLD_KEY) @Watch('onThinkingHoldEcho') private thinkingHoldEcho: boolean = false;
  // 思考菜单选项集 / 「关闭」档可用两 @StorageProp 字段随 2026-09-27 拆分迁
  // ChatTitleBarOverlay 自订阅；本页 setConnInfo 的两键 AppStorage 写点保留，键契约不变
  // 标题栏思考键交互期（按压或菜单开着）：输入栏收起守卫第三源——思考入口迁标题栏后由
  // 本页上报（经 @Link 三级链下发 ChatInputBar，同 modelLabel 通道先例）；Down 置位 /
  // Up·Cancel 复位、菜单 onAppear/onDisappear 接续（见 ThinkingMenuBuilder 注释）
  @State private thinkingHold: boolean = false;
  // 联网开关状态：**本会话生效值**（助手清单 ∩ 本会话未关，写点见 refreshWebSearchFlag；
  // @StorageProp 自订阅该键——页面既是写点也是读点）。消费方 = 发送组装（refs.webSearchOn
  // 读用）。★ 2026-10-30 联网项迁出笔：原「更多菜单联网项弹出一刻快照」消费面随项迁出，
  // 联网 UI 面现落 ChatPromptSheet 联网卡（可用性经 webSearchEnabledNow 现读同判据）
  @StorageProp(CHAT_WEBSEARCH_ON_KEY) webSearchOn: boolean = true;
  // 当前模型名：消费方三——消息时间头兜底（refreshChatHeadInfo）、输入栏「状态」chip「未选
  // 模型」红色档判据（@Link 链）、会话状态面板「模型」行（refs 现读）。切换入口在标题栏
  //「切换模型」键——本值与 CHAT_OFF_SUPPORTED_KEY / CHAT_THINKING_OPTIONS_KEY 两广播同点
  // 写入（setConnInfo），@Link 三级链下发（禁 @Prop——坑16：该链居 PageShell.content
  //（@BuilderParam）内，@Prop 不随父刷新会冻结在首帧）
  @State private modelLabel: string = '';
  // 当前服务商名：会话状态面板「服务商」行取数——与 modelLabel 同一写点（setConnInfo 的
  // info.providerName），只读展示无第二消费方
  @State private providerLabel: string = '';
  // 待发附件（2026-08-31 接线：AttachmentPickCtrl 入列填充、附件条渲染、发送随文本上送）
  @State private attachments: PendingAttachment[] = [];
  // 单条消息指定技能（'' = 未指定；纯内存态随页面存活，不落库不跨会话）：写入链 = 附件与
  // 提示词面板第四子态「选择技能」面板内开关回上（原指定技能页 push/pop 链已退役）；消费链 =
  // 发送漏斗首行写 ChatSendCtrl + 状态面板「本条指定技能」行只读展示 + 输入栏「状态」chip
  // 携带态换色与技能条显示（id+名双链 @Link 三级下传，先例 thinkingValue）；清态 = 真投递后
  //（dispatchSend 的 delivered 块，与附件同口径）与技能条 × 键取消指定两路
  @State private designatedSkillId: string = '';
  @State private designatedSkillName: string = '';
  // 半模态面板双态（坑64 姿势：bindSheet 复用页面根唯一挂载点）：sheetShow = 可见性（独立
  // 布尔挂 `$$` 双向；关闭 = 赋 false，内容形态 sheetKind 恒不复位——关闭动画期内容树恒在）；
  // sheetKind = 内容形态（'none' 仅初始值；十种形态入口与开启写序编排在 ChatSheetCtrl.ets，
  // 形态清单见该件文件头）
  @State @Watch('onSheetVisibleChanged') private sheetShow: boolean = false;
  @State private sheetKind: string = 'none';
  // ── 关闭-再开协调（机制与官方依据单源 = KimiSheetCommon.sheetPanelOptions 第四参注释）──：
  // 关闭后离场动效在途期内再点任一入口，直接写下的可见性 true 会被吞或被框架收尾回写压回
  //——在途期只记开意图，等离场动效结束再补开
  private sheetClosing: boolean = false;
  private pendingOpen: boolean = false;
  // 续写能力连接签名（自检轮补：baseUrl|model|endpoint——变化才复位「续写不支持」一次性标记）
  private continueConnSig: string = '';
  // 编辑助手面板双态（全屏输入四件缩为两件——无草稿回写通道，live 只供关闭确认脏态判读）：
  // init = 面板初值快照（带出原文）；live = 面板实时内容（onChange 上行，面板 aboutToAppear
  // 初开同步一次）
  @State private editAssistantInit: string = '';
  @State private editAssistantLive: string = '';
  // 会话改动文件详情面板载荷（任务② U5：清单卡行点击经 onOpenFileDetail 覆写播种——
  // 先落目标再走 openSheet('fileChanges') 既有机单入口；关闭恒不复位〔下次开启改写〕）
  @State private fileDetail: FileChangeEntry | null = null;
  // ── 上下文用量供给（方案 §3.6）──
  // 圆环值：-1 = 窗口未知或无数据（仅底环，拍板 P4）/ 0~100 = 已用占比（@Link 三级链下发
  // ChatInputBar）；面板数据 = 最近一次活算产物（ContextUsageSheet @Link 读，重算落地自动
  // 刷新——重算进行中保留旧值不清空）；seq 并发守卫随 refreshCtxUsage 迁 ChatPageLifecycle
  //（旧结果不覆盖新结果）
  @State private ctxRingPct: number = -1;
  @State private ctxUsage: ContextUsage | null = null;
  // 页面存活标记随刷新链迁 ChatSessionOverrideCtrl.departed——本页销毁点经
  // sessionOverrideCtrl.markDeparted 置位，迟到写丢弃语义见彼件字段注释
  // 全屏输入（dshinhm 二一一改语义随迁）：init = 面板初值快照（点全屏键时胶囊文本）；
  // draft/cmd = 回写胶囊的命令通道（cmd tick 驱动 ChatInputBar @Watch 覆盖——正常打字
  // 父不改无回环）；live = 面板实时草稿（onChange 上行——任何关闭路径均回写，未发送
  // 编辑不丢）
  @State private fullInputInit: string = '';
  @State private fullInputDraft: string = '';
  @State private fullInputCmd: number = 0;
  @State private fullInputLive: string = '';
  private conn: AiConnection | null = null;
  // 当前连接生效能力串：视觉门控的唯一输入——与 conn 同写点（setConnInfo）、同更新时机
  //（切模型 reloadConn 后自动跟随）。不进 UI 渲染（只在发送前置读一次），无需 @State
  private connCaps: string = '';
  // 视觉能力二次确认弹窗控制器：**组件成员位**构造（坑7 正当形态——生命周期随组件，先例
  // ChatSessionList.confirmCtrl）；禁 showAlertDialog（TabContent 槽内真机不弹，坑64 族 /
  // ConfirmDialog.ets 头注释实证）
  private visionConfirmCtrl: CustomDialogController | null = null;
  // 会话级覆盖（本会话内改过的模型选择）：无行会话（新建未发送）没有行可落，只存内存
  //（首发落行时随 insertMessage 写入）；有行会话以 DB 为真源（本值与之双写同值，
  // reloadConn 只作无行兜底）。不进 UI 渲染（生效路径 = reloadConn 读 → conn → 输入栏
  // 模型名），无需 @State。读写逻辑迁 ChatSessionOverrideCtrl——本页只存真源值，读经彼件
  // currentOverride 单点、写经 writeOverride 闭包
  private memoryOverride: ConversationOverride | null = null;
  // 连接解析输入变化广播：助手改绑/全局默认修改 tick 递增 → @Watch 重解析——修「页签切换
  // 不销毁重建，切回直接发送走旧 conn 缓存」缺口（tick 递增语义与写点清册见
  // ProviderDb.CONN_RESOLVE_TICK_KEY 键注释）；进页初值不触发 @Watch（仅变化触发），
  // 回调时 loadCtrl 已构造
  @StorageProp(CONN_RESOLVE_TICK_KEY) @Watch('onConnResolveTick') connResolveTick: number = 0;
  // drawer 主区标题栏动作命令（DrawerHomeTitleBar 命令键下行）：@Watch 只在变化时触发
  //（计数器初值 0 不触发）；drawer 覆盖层与二级页形态恒不同时在场，无跨形态误触面
  @StorageProp(CHAT_HOME_OPEN_MODEL_CMD_KEY) @Watch('onHomeOpenModelCmd') homeOpenModelCmd: number = 0;
  @StorageProp(CHAT_HOME_MORE_CMD_KEY) @Watch('onHomeMoreCmd') homeMoreCmd: number = 0;
  // 声明顺序即初始化顺序：listScroller 必先于 follow（follow 构造吃 scroller 引用）
  private listScroller: Scroller = new Scroller();
  private follow: ChatFollowController = new ChatFollowController(this.listScroller);
  // U4 双态判定器：判据全在彼件，本页只持引用双向递——refs 递 ChatPageLoad 重建链做复位、
  // Content 经 @ObjectLink 读锚态驱动 stackFromEnd（薄接线）
  @State private anchorJudge: ChatListAnchorJudge = new ChatListAnchorJudge();
  // 会话级覆盖域外迁件实例（三法整段在彼件，本页留内存覆盖真源与九件依赖注入闭包，
  // 拆分沿革见该件头注释）
  private sessionOverrideCtrl: ChatSessionOverrideCtrl = new ChatSessionOverrideCtrl({
    conversationId: (): string => this.conversationId,
    readOverride: (): ConversationOverride | null => this.memoryOverride,
    writeOverride: (ov: ConversationOverride | null): void => {
      this.memoryOverride = ov;
    },
    loadPromptState: (cid: string): Promise<void> => this.lifecycle.sendCtrl.loadPromptState(cid),
    aiAdminToolsEnabled: (): boolean => this.lifecycle.sendCtrl.aiAdminToolsEnabled(),
    webSearchAllowed: (): boolean => this.lifecycle.sendCtrl.webSearchAllowed(),
    reloadConn: (): void => this.loadCtrl.reloadConn(),
    closeSheet: (): void => this.closeSheet(),
    toast: (message: string): void => {
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
  });
  // sendCtrl 一族：★ U8 起构造与持有在运行时——本页经 this.lifecycle.sendCtrl getter 转发
  // 上下文压缩接线域（开面板/采用收口/删除收口/关闭确认四事在 ChatCompressCtrl；本页经
  // 七方法薄口回接，refs 同款闭包延迟求值）
  private compressCtrl: ChatCompressCtrl = new ChatCompressCtrl({
    conversationId: (): string => this.conversationId,
    allMessages: (): ChatMessage[] => this.dataSource.allMessages(),
    removeMessages: (ids: string[]): void => {
      this.dataSource.removeMessageIds(ids);
    },
    pushMessage: (message: ChatMessage): void => {
      this.dataSource.push(message);
    },
    openSheet: (kind: string): void => this.openSheet(kind),
    closeSheet: (action?: DismissSheetAction): void => this.closeSheet(action),
    refreshUsage: (): void => {
      this.lifecycle.refreshCtxUsage();
    },
    ui: (): UIContext => this.getUIContext()
  });
  // 面板开关与手势关闭路由编排域（2026-10-04 关闭链统一笔拆出，域体见 ChatSheetCtrl.ets）
  private sheetCtrl: ChatSheetCtrl = new ChatSheetCtrl({
    kind: (): string => this.sheetKind,
    openSheet: (kind: string): void => this.openSheet(kind),
    closeSheet: (action?: DismissSheetAction): void => this.closeSheet(action),
    ui: (): UIContext => this.getUIContext(),
    refreshContextUsage: (draft: string): void => this.lifecycle.refreshCtxUsage(draft),
    fullInputLive: (): string => this.fullInputLive,
    applyFullInputDraft: (text: string): void => this.applyFullInputDraft(text),
    setFullInputInit: (text: string): void => {
      this.fullInputInit = text;
    },
    setFullInputLive: (text: string): void => {
      this.fullInputLive = text;
    },
    setEditAssistantInit: (text: string): void => {
      this.editAssistantInit = text;
    },
    editAssistantRequestClose: (action?: DismissSheetAction): void => {
      this.editAssistantRequestClose(action);
    },
    compressRequestClose: (action?: DismissSheetAction): void =>
      this.compressCtrl.requestClose(action)
  });

  // 加载与刷新编排域（2026-08-31 自本页拆出——行为不变；refs 同款闭包注入）
  private loadCtrl: ChatPageLoadCtrl = new ChatPageLoadCtrl({
    dataSource: (): ChatDataSource => this.dataSource, // ★ U9 闭包化（重进重挂换源面）
    follow: this.follow,
    anchorJudge: this.anchorJudge,
    dbReady: (): boolean => this.dbReady,
    conversationId: (): string => this.conversationId,
    setConnInfo: (info: ActiveConnectionInfo | null): void => {
      this.conn = info !== null ? info.conn : null;
      // 生效能力串同写点：视觉门控读它；与 conn 同生命周期、切模型/切会话随 reloadConn 自动更新
      this.connCaps = info !== null ? info.caps : '';
      // 当前模型名回写（解析失败 = '' → 显示「未选」；换模型/换会话 → reloadConn 重解析 →
      // 本点写入 → @Link 链自动刷新，无需额外广播）。同行写 providerLabel（状态面板
      //「服务商」行取数——两值同点同寿命，解析失败同归 ''）
      this.modelLabel = info !== null ? info.conn.model : '';
      this.providerLabel = info !== null ? info.providerName : '';
      // 标题栏模型显示名（★ 2026-11-25 五轮）：与上面 modelLabel 同点同寿命——modelLabel 是
      // 模型 ID（消息轮头/状态面板口径），本键是显示名（标题栏与卡内模型入口口径，显示名优先、
      // 取不到回落 ID 的回落已在 buildCandidateConnection 单点完成）；解析失败写 ''，覆盖层
      // modelText 兜底「模型」。只写不删、AppStorage 广播（二级页与侧栏形态共用）。
      AppStorage.setOrCreate<string>(CHAT_TITLE_MODEL_KEY, info !== null ? info.modelName : '');
      // 消息时间头·模型名兜底与助手身份发布（域件 = ChatMessageHeader.refreshChatHeadInfo；
      // 页面只留本调用与重显补刷 lifecycle.onReShown 两处薄接线）
      refreshChatHeadInfo((): string => this.lifecycle.sendCtrl.boundAssistantId(), this.modelLabel);
      // 关闭可用广播 + 思考菜单选项集广播（@BuilderParam 内容 @Prop 不传播——坑16；chip
      // @StorageProp 自订阅写即刷新，只写不删无坑15 竞态）：两值读 conn 填充字段
      //（resolveActiveConnection 模型级判定/派生；connectionOffEnabled 含解析链外构造回落）；
      // 选项集 conn 空/未填充兜底全量 THINKING_OPTIONS。档位合法性回退（legalThinkingTier
      // 单一源）：切禁 off 域/模型 → 默认；画像行选项集收窄后存量非法档位同归默认
      //（注入层双保险在 ChatSendCtrl）
      const offOk: boolean = this.conn !== null && connectionOffEnabled(this.conn);
      AppStorage.setOrCreate<boolean>(CHAT_OFF_SUPPORTED_KEY, offOk);
      const options: string[] = this.conn !== null && this.conn.reasoningMenuOptions !== undefined ?
        this.conn.reasoningMenuOptions : THINKING_OPTIONS;
      AppStorage.setOrCreate<string[]>(CHAT_THINKING_OPTIONS_KEY, options);
      // 「DeepSeek 官方」可用镜像广播（★ DS 全家桶接入批 S1，照上两键同点同链）：kill
      // switch × 连接四合一判据（§0 单源 isDsFlashConnection）。消费方 = ChatPromptSheet
      // 联网菜单官方项显隐、文档解析行卡守卫与卡面官方态（@StorageProp 自订阅）；只写不删
      // 无坑15 竞态
      AppStorage.setOrCreate<boolean>(CHAT_DS_OFFICIAL_AVAILABLE_KEY,
        DS_SERVER_TOOLS_ENABLED && isDsFlashConnection(this.conn));
      // 接口形态镜像（自检轮补）：文档解析在 Responses 连接上可开可传，但 file item 形态
      // 官方未给——发送前由 attachBlockingReason 拦下并提示（键值与官方档判据同点刷新）
      AppStorage.setOrCreate<boolean>(CHAT_DS_RESPONSES_ENDPOINT_KEY,
        this.conn !== null && this.conn.endpoint === ENDPOINT_RESPONSES);
      // 续写能力镜像（自检轮补）：只有 DS 官方 CC 出「续写」入口（2026-11-15 起入口 = 消息「更多」
      // 菜单项；Responses 明确不支持、第三方点了必 400——首版无连接判据任何服务商都出键）
      const continueOk: boolean = this.conn !== null && isDsFlashConnection(this.conn) &&
        this.conn.endpoint === 'chat';
      AppStorage.setOrCreate<boolean>(CHAT_DS_CONTINUE_AVAILABLE_KEY, continueOk);
      // 连接签名变化才复位「续写不支持」标记（自检轮补：一次 404 后入口进程内永不恢复；
      // 同一连接反复刷新不重复复位，避免每次刷新都重试一次失败请求）
      const continueSig: string = this.conn !== null ?
        (this.conn.baseUrl + '|' + this.conn.model + '|' + this.conn.endpoint) : '';
      if (continueSig !== this.continueConnSig) {
        this.continueConnSig = continueSig;
        resetContinueUnsupported();
      }
      this.thinkingValue = legalThinkingTier(this.thinkingValue, offOk, options);
      // 上下文圆环随连接重算（分母跟当前生效模型走，§3.5 矩阵）
      this.lifecycle.refreshCtxUsage();
      this.lifecycle.queueCtrl.notifyReadyChange(); // 就绪门补派发（conn 已解析）
    },
    // 历史加载收尾（2026-09-18 自检轮）：圆环确定性补算 + 版本步进全表重算（初载与换源同源）
    onHistorySettled: (): void => {
      this.lifecycle.refreshCtxUsage();
      this.lifecycle.queueCtrl.notifyReadyChange(); // 就绪门补派发（历史装载已收尾）
      this.answerCtrl.recomputeRowVersions();
      // 标题栏两态收尾确认查（主路径 = 进页早查 refreshIfReady，见 aboutToAppear；
      // 无行新会话保持胶囊态，有行会话切两行标题）
      this.titleCtrl.refresh();
    },
    // 翻页收尾补算（★ 2026-10-25 自检轮补）：前插批行对象须补步进字段
    onOlderLoaded: (): void => {
      this.answerCtrl.recomputeRowVersions();
    },
    setError: (text: string): void => {
      this.errorText = text;
    },
    // 动作时错误提示（loadOlder 查询失败走 toast——消息流在场不适用 errorText 覆盖层）
    toast: (message: string): void => this.getUIContext().getPromptAction().showToast({ message: message }),
    // 会话有效归属助手（四级兜底链②级输入——转发发送域解析缓存，与注入链同源；
    // reloadConn 无行会话分支消费）
    effectiveAssistantId: (): string => this.lifecycle.sendCtrl.boundAssistantId(),
    // 无行会话的会话级覆盖兜底（DB 查不到行时用页面内存值）
    memoryOverride: (): ConversationOverride | null => this.sessionOverrideCtrl.currentOverride(),
    // 流式追加缓冲复位（转发发送域，见 ChatPageLoadRefs 注释）
    resetAppendBuffer: (): void => this.lifecycle.sendCtrl.resetAppendBuffer(),
    // 写侧路由镜像探针（加载链读到的路由转发给写侧——本域零逻辑，语义与理由见
    // ChatPageLoadRefs / ChatGraphWriteCtrl.publishRouteProbe 注释）
    publishRouteProbe: (route: string): void => this.lifecycle.sendCtrl.publishRouteProbe(route),
    // 沙箱 filesDir（附件简报装配拼绝对路径；闭包现读 host context——调用时页面必已挂载）
    filesDir: (): string => (this.getUIContext().getHostContext() as common.UIAbilityContext).filesDir,
    // 蒙层首屏就绪帧（页面侧唯一 UIContext 通道——一次出现笔）：安装提交后排一帧把
    // entryFirstScreenReady 置真；帧注册失败立即直调（fail-safe：信号不得悬挂把蒙层卡死）。
    // 帧类 = ChatEntryReadyFrame（一次性，取消清闭包）
    postEntryFrame: (callback: () => void): void => {
      const frame: ChatEntryReadyFrame = new ChatEntryReadyFrame(callback);
      try {
        this.getUIContext().postFrameCallback(frame);
      } catch (_error) {
        frame.cancel();
        callback();
      }
    }
  });
  // 待发图片裁剪页在途标记（1712 全站纪律）：页销毁后置位，迟到的 onPop 回执按放弃处理，
  // 不回写 attachments。与 attachCtrl 的 editPhoto 闭包成对
  private photoEditDeparted: boolean = false;
  // 附件选择编排域（2026-08-31 附件上传：三入口选择器→沙箱缓存→缩略图→入列）
  private attachCtrl: AttachmentPickCtrl = new AttachmentPickCtrl({
    getHostContext: (): common.UIAbilityContext | undefined =>
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined,
    getAttachments: (): PendingAttachment[] => this.attachments,
    setAttachments: (attachments: PendingAttachment[]): void => {
      this.attachments = attachments;
    },
    toast: (text: string): void => {
      this.getUIContext().getPromptAction().showToast({ message: text });
    },
    // 当前会话连接只读口（附件服务端上传目标解析用——新会话无 DB 行时活连接是唯一真值，
    // 见 AttachmentPickRefs.conn / DsFilesClient.resolveDsUploadTarget；2026-11-14 §4.1 修）
    conn: (): AiConnection | null => this.conn,
    // 待发图片裁剪页跳转（页面 → 控制器单向依赖：控制器只拿 Promise，路由栈留在本页）。
    // onPop 回执 = PhotoEditOutcome（path 三态 + 预解缩略图，见 common/AttachmentUtil 该接口
    // 注释）；异常/未带 result 一律按放弃处理，Promise 永不悬挂（否则 pick 的 await 会卡住
    // 整条添加附件链）
    editPhoto: (srcPath: string): Promise<PhotoEditOutcome> =>
      new Promise<PhotoEditOutcome>((resolve: (outcome: PhotoEditOutcome) => void): void => {
        // ★ push 前先关「会话设置」半模态（2026-11-05 自检轮修，P1）：bindSheet 默认
        // SheetMode.OVERLAY = 当前 UIContext 内顶层显示、恒在所有页面之上（官方 FAQ
        // faqs-arkui-464），页面跳转后半模态不随原页消失（faqs-arkui-583 官方解法 = push 前
        // 显式置 false）——本流程入口就是半模态里的「拍照 / 照片」格，不关就 push 会把编辑页
        // 压在仍开着的面板下面（用户看不到也点不到，还会留下并发的第二次 pick 链）。
        // 必须走 closeSheet 单入口而非直写 sheetShow：直写会被 @Watch onSheetVisibleChanged
        // 按开意图补开回去（见 closeSheet 头注释「关闭放行单源」）。
        // ★ 拍板（决明 2026-11-05「不复开」）：编辑完返回会话后**不复开**面板——本流程只关
        // 不开；`if (this.sheetShow)` 同时兼作「面板已关就不要再调」的闸（多选逐张时会二次
        // 进入本闭包，重复 closeSheet 会把 sheetClosing 挂成 true 且无人再触发 onSheetGone，
        // 之后「＋」就开不出面板了）
        if (this.sheetShow) {
          this.closeSheet();
        }
        const param: PhotoEditParam = { srcPath: srcPath };
        this.pathStack.pushPathByName(ROUTE_PHOTO_EDIT_PAGE, param, (info: PopInfo): void => {
          // 组件异步链销毁守卫（1712 全站纪律）：页已销毁则放弃这张，不回写 @State
          //（回执里的预解缩略图如有也当场释放——接管方已不在，不释放即泄漏）
          if (this.photoEditDeparted) {
            const late: PhotoEditOutcome = info.result as PhotoEditOutcome;
            if (late !== undefined && late !== null && late.thumb !== null) {
              late.thumb.release();
            }
            resolve({ path: '', thumb: null });
            return;
          }
          const result: PhotoEditOutcome = info.result as PhotoEditOutcome;
          resolve(result !== undefined && result !== null ? result : { path: '', thumb: null });
        });
      })
  });
  // 消息「更多」菜单接线域（原内联宿主 + 两方法整域收拢到 ChatMoreMenu.ChatMessageMenuCtrl
  //——动作上行落本页两个控制器）
  private messageMenuCtrl: ChatMessageMenuCtrl = new ChatMessageMenuCtrl({
    dataSource: (): ChatDataSource => this.dataSource,
    ui: (): UIContext => this.getUIContext(),
    immersiveLevel: (): number => this.immersiveLevel,
    // 目标节点图身份判据单源（ChatBranchCtrl.nodeIdOf——本页不另判）
    nodeIdOf: (msg: ChatMessage): string => this.branchCtrl.nodeIdOf(msg),
    // refs 收窄（rik 形态统一笔：「重新生成」三项菜单退役后，过闸与起轮两能力的唯一消费方
    // = 行内重试键 retryFromBubble）
    retryAllow: (msgId: string, nodeId: string): Promise<BranchAllow> =>
      this.branchCtrl.retryAllow(msgId, nodeId),
    retryAt: (nodeId: string): void => {
      this.lifecycle.sendCtrl.retryAt(nodeId);
    },
    onEdit: (msgId: string, nodeId: string): void => {
      // 「编辑」扩两角色（user/assistant 分流在编排域单点——user 走输入框编辑链、
      // assistant 走编辑面板链）
      this.branchCtrl.beginEditDispatch(msgId, nodeId);
    },
    // 独立会话 fork 入口上行（边界 = 该消息节点；判据与落库全在编排域）
    onCopyNew: (nodeId: string): void => {
      this.branchCtrl.copyToNewSession(nodeId);
    },
    // 任务③：删除判据与执行经 refs 上行（判据单源 canDeleteAt，编排与命令在 ChatBranchCtrl）
    deleteAllow: (msgId: string, nodeId: string): Promise<BranchAllow> =>
      this.branchCtrl.deleteAllow(msgId, nodeId),
    deleteAt: (nodeId: string): void => {
      this.branchCtrl.deleteMessage(nodeId);
    },
  });
  // 会话内分支与历史编辑编排域（分支列表/切分支/fork/编辑；起轮能力经 refs 回调上行，
  // 域体在 ChatBranchCtrl）
  private branchCtrl: ChatBranchCtrl = new ChatBranchCtrl({
    conversationId: (): string => this.conversationId,
    dataSource: (): ChatDataSource => this.dataSource,
    dbReady: (): boolean => this.dbReady,
    sending: (): boolean => this.sending,
    toast: (message: string): void => {
      this.getUIContext().getPromptAction().showToast({ message: message });
    },
    migrateState: (): Promise<string> => conversationMigrateState(this.conversationId),
    activeBranch: (): Promise<string> => conversationGraphBranch(this.conversationId),
    reloadBranchPath: (): Promise<boolean> => this.loadCtrl.reloadBranchPath(),
    // 编辑面板开关（两角色共用——initial = 带出原文，开关写序在 ChatSheetCtrl）
    openEditAssistant: (initial: string): void => {
      this.sheetCtrl.openEditAssistant(initial);
    }
  });
  // 待发引用（引用功能笔 U-E；null/'' = 无引用）：发送链 refs 读口的可达真源，@Link 三级链
  // 下行 Content → ChatInputBar → ChatQuoteBar；会话页内存态不持久化，切会话 = 新页面实例
  // 天然归 null（conversationId 不变即不清，方案档 §4.5 判据）
  @State private pendingQuote: string | null = null;
  // 回答切换编排域（任务书 §5）：读图归组、切换编排与视图快照发布全在域件；面板视图经
  // sink 注入 ChatPageContent（本页只构造与传引用）。切换走 branchCtrl.switchToResult
  //（结构化结果：库已写 ≠ 屏幕已换）
  private answerCtrl: ChatAnswerCtrl = new ChatAnswerCtrl({
    conversationId: (): string => this.conversationId,
    dataSource: (): ChatDataSource => this.dataSource,
    dbReady: (): boolean => this.dbReady,
    sending: (): boolean => this.sending,
    nodeIdOf: (msg: ChatMessage): string => this.branchCtrl.nodeIdOf(msg),
    switchTo: (branchId: string, isCurrent: () => boolean): Promise<BranchSwitchResult> =>
      this.branchCtrl.switchToResult(branchId, isCurrent),
    // 删除回答版本（根闸包装在 branchCtrl，能力经 refs 闭包）
    deleteAnswerVersion: (branchId: string): Promise<boolean> =>
      this.branchCtrl.deleteAnswerVersion(branchId),
    toast: (text: string): void => {
      this.getUIContext().getPromptAction().showToast({ message: text });
    }
  });
  // 沉浸光感档位（「更多」菜单材质解析用；AppStorage 自订阅）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 标题写回广播 tick（初值不触发 @Watch；首查由历史装载收尾与 onShown 承接）
  @StorageProp(CONV_TITLE_TICK_KEY) @Watch('onConvTitleTick') titleTick: number = 0;
  // 标题数据供给域（反查/广播/并发与销毁守卫整域在彼件，本页只留调用点）
  private titleCtrl: ChatTitleSupplyCtrl = new ChatTitleSupplyCtrl(
    (): string => this.conversationId);

  // 生命周期编排域件（★ U7：进/退/重显三链与用量供应整域在 ChatPageLifecycle；★ U8 起运行态
  // 取用/释出挂 enter/leave，见该件头注释；refs 闭包延迟求值，控制器实例直传）
  private lifecycle: ChatPageLifecycle = new ChatPageLifecycle({
    conversationId: (): string => this.conversationId,
    shareTick: (): number => this.shareTick,
    ui: (): UIContext => this.getUIContext(),
    setDbReady: (ok: boolean): void => { this.dbReady = ok; },
    setErrorText: (text: string): void => { this.errorText = text; },
    dbReady: (): boolean => this.dbReady,
    freshSession: (): boolean => this.freshSession,
    attachments: (): PendingAttachment[] => this.attachments,
    modelLabel: (): string => this.modelLabel,
    hasVisionNow: (): boolean => this.conn !== null && hasVisionCap(this.connCaps),
    setUsagePct: (usage: ContextUsage | null, pct: number): void => {
      this.ctxUsage = usage;
      this.ctxRingPct = pct;
    },
    applyFullInputDraft: (text: string): void => { this.applyFullInputDraft(text); },
    // ── 运行态 UI 绑定面（★ U9：宿主即 ChatRuntimeUiBinding 实现——acquire 直传；退页由
    // 运行时 detachUi 整体解绑，重进再绑；replaceDataSource 为宿主专有换源写回口）──
    dataSource: (): ChatDataSource => this.dataSource,
    replaceDataSource: (ds: ChatDataSource): void => {
      this.dataSource = ds;
    },
    follow: this.follow,
    anchorJudge: this.anchorJudge,
    conn: (): AiConnection | null => this.conn,
    thinking: (): string => this.thinkingValue,
    webSearchOn: (): boolean => this.webSearchOn,
    // 无行会话的会话级覆盖（U9 绑定面新增——原 buildSendRefs 内联闭包迁此）
    sessionOverride: (): ConversationOverride | null => this.sessionOverrideCtrl.currentOverride(),
    setSending: (sending: boolean): void => { this.sending = sending; },
    clearError: (): void => { this.errorText = ''; },
    toast: (message: string): void => { this.getUIContext().getPromptAction().showToast({ message: message }); },
    // 轮次收尾刷新圆环（方案 §3.6）
    onRoundSettled: (): void => {
      this.lifecycle.refreshCtxUsage();
    },
    reloadBranchPath: (): Promise<boolean> => this.loadCtrl.reloadBranchPath(),
    // 拒发归还输入（文字回输入条、附件回附件条——同视觉确认取消路径的还草稿口径）
    restoreSendInput: (text: string, attachments: PendingAttachment[]): void => {
      this.applyFullInputDraft(text);
      this.attachments = attachments;
    },
    // 待发引用读写口（发送链快照/成功清空两消费点经 refs 到达；dispatchSend 冻结比对
    // 语义见 ChatSendCtrl）
    pendingQuote: (): string => this.pendingQuote ?? '',
    clearPendingQuote: (): void => {
      this.pendingQuote = null;
    },
    // ── 草稿宿主回接（编排与时机在 ChatPageLifecycle）──
    draftKey: (): string => this.draftKey,
    setDraftKey: (key: string): void => { this.draftKey = key; },
    draftTextInput: (): string => this.draftTextLive,
    // 待发引用现读（引用纳入草稿）：草稿保存链与文本同刻取一次——'' = 无引用
    draftQuoteText: (): string => this.pendingQuote ?? '',
    // 恢复写回（第三参 = 引用全文）：text 走命令通道、附件整组赋值、引用回写 pendingQuote
    //（'' → null 清态；输入侧引用条随 @Link 链自动重现）
    restoreDraftInput: (text: string, attachments: PendingAttachment[], quoteText: string): void => {
      this.applyFullInputDraft(text);
      this.attachments = attachments;
      this.pendingQuote = quoteText !== '' ? quoteText : null;
    },
    loadCtrl: this.loadCtrl,
    overrideCtrl: this.sessionOverrideCtrl,
    attachCtrl: this.attachCtrl,
    branchCtrl: this.branchCtrl,
    answerCtrl: this.answerCtrl
  });

  // 聊天页菜单动作域（U1b 拆缝后本页只留构造接线与两挂点，回调簇在 ChatPageMenuCtrl；
  // ★ 2026-10-30 联网项迁出笔：原 webSearchOn/webSubMenu 两装配行随项迁出删除；★ 双形态笔：
  // pathStack 注入撤（新建导航改 newSessionNav 注入——二级页 replacePath / 主区上抛换 id）
  private menuCtrl: ChatPageMenuCtrl = new ChatPageMenuCtrl({
    ui: (): UIContext => this.getUIContext(),
    sheet: this.sheetCtrl,
    // 新建会话导航（双形态分流：二级页 = replacePath 同路由替换〔坑57 防孤儿栈经闭包现读〕；
    // 主区常驻 = 上抛 DrawerMainArea @Link 换 activeConvId，双交替重建即达）
    newSessionNav: (newId: string): void => {
      if (this.homeMode) {
        this.onHomeNewSession(newId);
        return;
      }
      this.pathStack.replacePathByName(ROUTE_CHAT_PAGE, newId);
    },
    // 设置项兜底（★ 双形态真机修复笔）：仅主区常驻态传——侧栏域故障时「更多」菜单保住
    // 进设置页切回底栏形态的逃生门；二级页形态有系统返回不传（undefined = 菜单不挂项）
    onOpenSettings: this.homeMode ? (): void => {
      this.pathStack.pushPathByName(ROUTE_SETTINGS_PAGE, '');
    } : undefined,
    onOpenTrace: (): void => {
      // 菜单进二级页走官方默认 push 转场（2026-10-18 补转场笔：原 animated=false 无理由无动画）
      this.pathStack.pushPathByName(ROUTE_SESSION_TRACE_PAGE, this.conversationId);
    },
    // 会话工作区页（本会话工作区文件清单 + 四动作；conversationId 恒有效——普通成员构造
    // 注入 + PageMapBuilder 兜底 activeConvId）
    onOpenWorkspace: (): void => {
      this.pathStack.pushPathByName(ROUTE_SESSION_WORKSPACE_PAGE, this.conversationId);
    },
    // 草稿保存先行（menuCtrl.newSession 动作点——转发 lifecycle 单保存逻辑，见 refs 注释）
    saveDraftNow: (): void => { this.lifecycle.saveDraftFromHost(); }
  });

  // 队列变更上行（★ U1：count/paused/active 三值同点更新——active 即显隐与让位的同源判据；
  // 箭头成员身份稳定，add/remove 成对不失效）
  private onQueueChanged = (count: number, paused: boolean): void => {
    this.queueCount = count;
    this.queuePaused = paused;
    this.queueBandActive = count > 0;
  };

  aboutToAppear(): void {
    // 标题栏两态：进页采纳预置标题（点卡播种一致 = 首帧即两行态；否则清残留回胶囊）+
    // DB 就绪即早查校正真值（域件与时机见 ChatPageTitleCtrl 头注释）
    this.titleCtrl.adoptPreset();
    this.titleCtrl.refreshIfReady();
    // 附件条失败态重试通道登记（二期 #12）：处理器落在附件控制器，与 #11 流内自愈
    // 互补——前者救「入列时上传失败」，后者救「发送时 file_id 已过期」
    registerAttachmentRetry((fileId: string): void => {
      this.attachCtrl.retryOne(fileId);
    });
    // 会话权限模式换档点（2026-11-09 自检轮）：只有会话 id 变化才换档——退出重进同一会话
    // 保留本次运行内切过的档，换会话回填目标会话自己的档（细节见 PermissionMode 头注释）。
    // 必须早于子件构建，输入栏首帧才读得到正确档位。
    enterConversation(this.conversationId);
    // 思考档位镜像初值发布（@Watch 不触发初值；换会话复位防上一会话档位泄漏）
    AppStorage.setOrCreate<string>(CHAT_THINKING_VALUE_KEY, this.thinkingValue);
    // 进页链整域在 ChatPageLifecycle.enter（whenReady 等待链 + 屏幕常亮）
    this.lifecycle.enter();
    // 排队入口条注册（U1：寿命匹配——长寿命队列域不持页面闭包，入口条在页时订阅；注销见
    // aboutToDisappear）。队列域构造期 hydrate 异步落地后走自身 notify，无需初值重试
    this.lifecycle.queueCtrl.addOnQueueChange(this.onQueueChanged);
    this.onQueueChanged(this.lifecycle.queueCtrl.itemCount(), this.lifecycle.queueCtrl.isPaused());
    // 菜单宿主首建（与 aboutToDisappear 的 dispose 成对；open 前重建换真值，首建只为节点就绪）
    this.menuCtrl.init(this.getUIContext());
    this.messageMenuCtrl.init();
  }

  aboutToDisappear(): void {
    this.titleCtrl.markDeparted();
    // 排队入口条注销（与 aboutToAppear 注册成对——先于退页释放链，防 teardown 期回调写状态）
    this.lifecycle.queueCtrl.removeOnQueueChange(this.onQueueChanged);
    // 待发图片裁剪页在途守卫（与 editPhoto 的 onPop 回执成对）
    this.photoEditDeparted = true;
    // 退页释放链整域在 ChatPageLifecycle.leave（★ U9 退页不断流：只解绑页面闭包 + 引用计数
    // 递减，生成照常跑在运行时；存活标记/解析取消/OCR 释放/附件清删/控制器释放/列表广播/
    // 记忆沉淀等页面寿命动作照旧）
    this.lifecycle.leave();
    // 菜单节点成对释放（与 aboutToAppear init 成对——ComponentContent 不释放即泄漏）
    this.menuCtrl.dispose();
    this.messageMenuCtrl.dispose();
    // 附件重试事件口注销（自检轮补，与 aboutToAppear 登记成对——模块级单例不得持有页面
    // 控制器闭包；重新进页由 aboutToAppear 再登记）
    clearAttachmentRetry();
  }

  // ═══ 上下文用量供给（方案 §3.6）═══ 刷新点与 seq 守卫整域在
  // ChatPageLifecycle.refreshCtxUsage（本页五处调用点：切模型 setConnInfo / 历史收尾
  // onHistorySettled / 轮收尾 onRoundSettled + 压缩与面板两代理）

  // 面板开关机制两写（开关编排在 ChatSheetCtrl；两写同点防漏写一边）。可见性写走
  // requestOpen（关闭-再开协调，见字段注释）
  private openSheet(kind: string): void {
    this.sheetKind = kind; this.requestOpen();
  }

  // ── 关闭-再开协调（机制见字段注释；与会话轨迹页/请求日志页同配方）──
  // 开意图落定 → 动效在途挂起 / 否则即开（applyOpen 单入口，补开两路共用）
  private requestOpen(): void {
    this.pendingOpen = true;
    if (this.sheetClosing) { return; } // 动效在途：待补开
    this.applyOpen();
  }

  private applyOpen(): void {
    if (!this.pendingOpen) {
      return;
    }
    this.sheetShow = true;
  }

  // 离场动效结束（sheetPanelOptions 第四参——d.ts：动画结束后回调）：清在途位 + 按开意图补开
  private onSheetGone(): void {
    this.sheetClosing = false;
    if (!this.sheetShow) {
      this.applyOpen();
    }
  }

  // 可见性变化兜底（@Watch）：框架 `$$` 收尾回写把可见性压回 false 时按开意图补一次；
  // 用户关闭必经 closeSheet（先清开意图再写 false），不会误触本支
  private onSheetVisibleChanged(): void {
    if (!this.sheetShow) {
      this.applyOpen();
    }
  }

  // 关闭放行单源（两路成形）：手势路（action 在场）先官方 dismiss() 放行；自绘键 /
  // 程序化路（action 缺省）直写可见性（`$$` 双向）。关闭恒不复位 sheetKind——内容形态随
  // 下次开启改写（关闭动画期内容树恒在）。放行 = 关闭单入口——先清开意图 + 置离场动效
  // 在途位，再写可见性（关闭-再开协调，见字段注释）
  private closeSheet(action?: DismissSheetAction): void {
    if (action !== undefined) { action.dismiss(); }
    this.pendingOpen = false;
    this.sheetClosing = true;
    this.sheetShow = false;
  }

  // 编辑助手面板关闭请求单入口（标题栏自绘键与 onWillDismiss 手势两路同调）：脏态**现读**
  // 生效值（live 与 initial 比对，非快照），脏 = confirmSheetClose 确认后才放行（确认未过
  // 不 dismiss 不直写，面板保持打开）；不脏直落（零暂存缺省直落不回弹的下拉口径在 bindSheet
  // 第三参按形态分发）。程序化关闭（保存成功）不接本入口——编排回调直写 closeSheet
  private async editAssistantRequestClose(action?: DismissSheetAction): Promise<void> {
    if (this.editAssistantLive !== this.editAssistantInit) {
      const ok: boolean = await confirmSheetClose(this.getUIContext(), {
        title: '放弃修改？',
        message: '尚未保存的修改将丢失',
        cancelLabel: '继续编辑',
        confirmLabel: '放弃修改'
      });
      if (!ok) {
        return;
      }
    }
    this.closeSheet(action);
  }

  // ═══ 上下文压缩（域体四件 = CompressPreviewSheet〔三态面板〕/ CompressGen〔生成〕/
  //     CompressDb〔落库〕/ ChatCompressCtrl〔页面接线〕——接线域已外迁 ChatCompressCtrl，
  //     本页只留 compressCtrl 实例与本段薄接线）═══

  // 发送统一入口（胶囊与全屏输入两路收敛）：附件阻断前置（attachBlockingReason 单源，
  // doc 解析阻断 + OCR 识别中未识别完不发）→ 视觉能力门控（见下）→ 交发送编排（真投递
  // 才清页面态，见 dispatchSend）。
  // ★ 返回值契约：true = 已投递或已进入确认流程（调用方可按「发送成功」清草稿）；false =
  // 本次未投递（解析/识别阻断 / 发送守卫拦下）——调用方**保留输入条文字**，附件与页面态
  // 亦原样保留
  private sendWithAttachments(text: string): boolean {
    // （user 编辑改面板保存整段退役——两个发送入口恒为「新消息发送」语义）
    // 本轮指定写入（自检轮 F2 更正：挂漏斗而非输入栏 onSend）——两个发送入口与视觉确认
    // 路径共用本漏斗，首行恒写（'' = 无指定）一处即全覆盖
    this.lifecycle.sendCtrl.setSkillDesignate(this.designatedSkillId);
    const blocking: string = attachBlockingReason(this.attachments);
    if (blocking !== '') {
      this.getUIContext().getPromptAction().showToast({ message: blocking });
      return false;
    }
    // 视觉门控（拍板③：不再是硬阻断——无视觉能力时弹二次确认，确认后照发）：判据 = 本轮
    // **真的**带图（图片附件或扫描件页图；渲染失败无页图则不弹；OCR 二期：已分流走识别
    // 文本的件不算「带图」——hasVision 传入分流判据单源）。★ 前提必须有连接：conn === null
    // 时 caps 恒空，缺此判会让「未配置服务商」的用户先看到「模型不支持视觉理解」错提示
    //（照发后附件还会被 send() 守卫清掉）——无连接交给 ChatSendCtrl.send 既有守卫呈报，
    // 本闸不参与
    const hasVision: boolean = this.conn !== null && hasVisionCap(this.connCaps);
    if (this.conn !== null && !hasVision && willSendImages(this.attachments, hasVision)) {
      this.openVisionConfirm(text);
      // 已进入确认流程 = 契约里的 true：附件与页面态保留到确认路径（见 dispatchSend）；
      // 两路调用方按 true 清草稿，取消三路由 restoreDraftText 还回
      return true;
    }
    return this.dispatchSend(text);
  }

  // 实际投递（门控直通与确认两路共用）：交发送编排 → **真投递才清页面态**（原「先清再投」
  // 在守卫拦下时把附件一起吞掉——现在 false 时文字与附件都留输入条，用户配好服务商/
  // 等解析完可直接重发）
  private dispatchSend(text: string): boolean {
    const atts: PendingAttachment[] = this.attachments;
    // hasVision 单源现读（与 sendWithAttachments 同判据 hasVisionCap(connCaps)——载荷组装
    // 分流用；确认路径经此二次计算，两次之间连接不变〔确认弹窗期间无法切模型〕）
    const hasVision: boolean = this.conn !== null && hasVisionCap(this.connCaps);
    const delivered: boolean = this.lifecycle.sendCtrl.send(text, atts, hasVision);
    if (delivered) {
      // 草稿清：仅删条目——附件文件已随消息发送被 message_attachments 库行接管（文件留盘
      // 转消息资产），级联删会损坏已发消息（方案 §2.4 禁改 WithFiles）
      removeDraft(this.draftKey);
      // 新会话防串位修正：首条消息已 ensureConversation 建行，本页后续草稿必须落会话 id key
      this.draftKey = this.conversationId;
      this.attachments = [];
      // 指定清态：真投递才清（与附件同口径——视觉确认被取消时指定不丢，可在同一轮重发）；
      // 只此一轮 = 清掉即下一条消息重新选
      this.designatedSkillId = '';
      this.designatedSkillName = '';
    }
    return delivered;
  }

  // 无视觉能力二次确认：确认 = 走原发送体；取消/遮罩/返回 = 不发、附件原样留条上、
  // **输入的文字也还给用户**（restoreDraftText）。控制器在组件成员位构造（坑7 正当形态，
  // 先例 ChatSessionList.confirmCtrl）；禁 showAlertDialog（TabContent 槽内真机不弹，
  // 坑64 族）。弹窗 options 迁 ChatVisionConfirm.ets；本方法只留 controller 构造与打开
  //——builder 需要组件上下文，不随迁
  private openVisionConfirm(text: string): void {
    this.visionConfirmCtrl = new CustomDialogController(visionConfirmOptions({
      onConfirm: (): void => {
        this.dispatchSend(text); // 确认路径草稿保持已清态（文字已随消息发出）
      },
      onCancel: (): void => {
        // 取消把这段文字还给用户（回写通道 = applyFullInputDraft 覆盖式重写，
        // 理由见 AttachmentPickCtrl.restoreDraftText 注释）
        restoreDraftText((t: string): void => this.applyFullInputDraft(t), text);
      }
    }));
    this.visionConfirmCtrl.open();
  }

  // 附件半模态三卡入口（拍照/照片/系统文件——面板保持打开，dshinhm FileSheet 同款）
  private onPickAttachment(kind: FilePickKind): void {
    this.attachCtrl.pick(kind);
  }

  // 重发文件行点击（「会话设置」面板五，★ 2026-10-31 附件重发笔）：复制已发附件或工作区文件
  // 成新副本入列（面板保持打开、累加多选；额度闸/复制失败/入列拒绝的中文 toast 全在控制器
  // 收口，本处只薄转发返回值）。★ 同日重发降级笔：本处补降级上下文三值（会话/助手归属 +
  // workspace_read 是否在生效工具集——发送链同一读口 enabledToolIds，助手 tools 空则默认
  // 集合两态合流已在解析侧收口），控制器据此做截断件导入与未开工具提示
  private onReissuePicked(name: string, srcRelPath: string, workspacePath: string,
    sourceRow: AttachmentListRow | null): Promise<boolean> {
    const guide: ReissueGuideContext = {
      workspacePath: workspacePath,
      sourceRow: sourceRow,
      conversationId: this.conversationId,
      assistantId: this.lifecycle.sendCtrl.boundAssistantId(),
      workspaceToolOn: this.lifecycle.sendCtrl.enabledToolIds().includes(TOOL_WORKSPACE_READ)
    };
    return this.attachCtrl.addCopiedFromFile(name, srcRelPath, guide);
  }

  // 弹出「更多」官方菜单（回调簇与宿主任 ChatPageMenuCtrl；材质档本页现读传入）
  private openMoreMenu(): void { this.menuCtrl.open(this.immersiveLevel); }

  // ── drawer 主区标题栏桥消费（2026-11-17 对齐笔；键语义见 DrawerHomeTitleBar 头注释）──
  // 思考档位双向镜像：发布（真源 → 键）与回执（菜单落值 → 真源），同值守卫收敛无环
  private onThinkingValueChanged(): void {
    if (AppStorage.get<string>(CHAT_THINKING_VALUE_KEY) !== this.thinkingValue) {
      AppStorage.setOrCreate<string>(CHAT_THINKING_VALUE_KEY, this.thinkingValue);
    }
  }

  private onThinkingValueEcho(): void {
    if (this.thinkingValueEcho !== this.thinkingValue) {
      this.thinkingValue = this.thinkingValueEcho;
    }
  }

  // 思考键交互期回执（drawer 覆盖层菜单开合/按压下行；键值即真相）
  private onThinkingHoldEcho(): void {
    this.thinkingHold = this.thinkingHoldEcho;
  }

  // 命令回执两链：开模型面板 / 弹「更多」菜单（openMenu 锚点在 ChatPageContent，与触发键层级无关）
  private onHomeOpenModelCmd(): void { this.sheetCtrl.openModel(); }
  private onHomeMoreCmd(): void { this.openMoreMenu(); }

  // 标题写回广播（占位升级 / AI 标题）：转发标题数据供给域重查，即时从胶囊态切两行标题
  private onConvTitleTick(): void { this.titleCtrl.refresh(); }

  // ★ 技能选择页入口（openSkillDesignatePage）已随「指定技能改半模态」整段退役——技能选择
  // 改附件与提示词面板第四子态（SkillPickPanel，见 SheetHost 'prompt' 分支
  // onSkillDesignated）。负向钉：本文件零 ROUTE_SKILL_DESIGNATE_PAGE / SkillDesignateParam
  // / SkillDesignateResult / openSkillDesignatePage 残留

  // 解析输入变化回调（@Watch；解析只读，多触发无害——编排体在 ChatPageLifecycle.onConnResolved）
  private onConnResolveTick(): void { this.lifecycle.onConnResolved(); }

  // 页面重新显示回调整域在 ChatPageLifecycle.onReShown（onShown 接线直调，见 build 内注释）

  // 回写胶囊命令（tick 强制触发——@Watch 对同值不触发，tick 递增保证每次命令都覆盖；
  // 覆盖含空串（发送后清空/面板清空关闭）——与「无命令」区分 = 命令只在两时点发出）
  private applyFullInputDraft(text: string): void {
    this.fullInputDraft = text;
    this.fullInputCmd++;
  }

  // 思考档位菜单与标题栏键材质档随 2026-09-27 拆分迁 ChatTitleBarOverlay——本页不再自持

  // 标题栏覆盖层（坑51/62：CustomBuilder 位必须挂组件内 @Builder，全局 builder 启动闪退）。
  // 2026-11-15 起 = ChatTitleBarOverlay 两态中央区 + 右端更多单圆键；本页只挂两枚动作回调，
  // 新建会话已收入更多菜单首项；thinkingValue/thinkingHold 双向链不变。★ 2026-11-17 对齐笔：
  // 侧栏形态主区不再走本挂载位（覆盖层上收 HomeNavigation stackBuilder 插槽 DrawerHomeTitleBar，
  // 汉堡键与动作经命令键下行）——本 @Builder 只服务二级页形态，showSidebarKey 恒缺省 false。
  @Builder
  TitleBarContent() {
    ChatTitleBarOverlay({
      thinkingValue: $thinkingValue,
      thinkingHold: $thinkingHold,
      onOpenModel: (): void => {
        this.sheetCtrl.openModel();
      },
      onOpenMoreMenu: (): void => {
        this.openMoreMenu();
      }
    })
  }

  // ★ 2026-10-30 联网项迁出笔：原 WebSearchSubMenu @Builder（坑51/62 挂点）随「联网」项
  // 迁出删除——引擎菜单落 ChatPromptSheet 联网卡（bindMenu 挂组件内 @Builder，写点仍 =
  // sessionOverrideCtrl.pickWebEngine / pickWebSearch(false) 两方法，经面板 refs 上行）

  // 排队入口条：二级页交给官方标题栏下方带；homeMode 用同一组件的悬浮档叠在全高内容上。
  @Builder
  QueueBand(floating: boolean = false) {
    QueueTopBand({
      queueCount: $queueCount,
      queuePaused: $queuePaused,
      floating: floating,
      topPad: this.topPad,
      onOpenQueue: (): void => {
        this.sheetCtrl.openQueue();
      }
    })
  }

  // 内容区（坑39 红线：@BuilderParam content 不能 lambda 直写 UI——组件内 @Builder 方法
  // 承载；布局与参数语义见 ChatPageContent）
  @Builder
  Content() {
    // 文档解析隐式宿主（1×1 透明离屏 Web——桥四引擎解析器载荷；与消息流同域 sibling，
    // 无布局影响）
    DocParserHost()
    // 内置浏览器隐形宿主（满视口透明 + 命中穿透——视口语义〔isInViewport / 懒加载〕依赖
    // 真实视口尺寸）；声明序在消息流之前 = 被实体 UI 盖住（官方「被遮挡不终止行为」档，
    // 形态细节见 BrowseWeb 头注释）；与 DocParserHost 同域 sibling 无布局影响（勿挂别处
    //——页面根/别的 @Builder 会引入生命周期差异）
    BrowseHost()
    ChatPageContent({
      dataSource: this.dataSource,
      listScroller: this.listScroller,
      followCtrl: this.follow,
      anchorJudge: this.anchorJudge,
      // 与二级页同一让位通道：内容恒全高延伸到标题栏背后，由列表 contentStartOffset、
      // 空态层和更多菜单锚点各自消费 topPad；homeMode 外层不得再缩矮整个内容容器。
      topPad: this.topPad,
      bottomPad: this.bottomPad,
      // 排队入口条（★ U1）：显隐/计数/暂停三值 @Link 下行（坑16 正解通道——本件居
      // PageShell.content，@Prop 会冻结）；内容区让位与标题栏带显隐同吃 queueBandActive
      queueBandActive: $queueBandActive,
      queueCount: $queueCount,
      queuePaused: $queuePaused,
      onOpenQueue: (): void => {
        this.sheetCtrl.openQueue();
      },
      // 路由栈注入（2026-09-15 二级页化笔：附件查看器改导航栈内二级页，开页需 pushPathByName）
      pathStack: this.pathStack,
      // 回答切换控制器注入（控制器页面寿命——Content 只在自身存活期 attach 视图接收端）
      answerCtrl: this.answerCtrl,
      busy: $sending, // ★ 2026-10-16 重启续答冻结修复：@Prop 升 @Link（坑16 冻结通道；沿革见 ChatPageContent 声明注释）
      dbReady: this.dbReady,
      errorText: this.errorText,
      attachments: this.attachments,
      // 单条消息指定技能：id+名双链下发（父 @State → ChatPageContent @Link → ChatInputBar
      // @Link → ChatSkillBar，坑16 正解通道——先例 thinkingValue）——id 喂状态键换色与
      // canSend、名喂技能条显示；技能条 × 键上行取消指定（双值同清，同面板关开关口径）；
      // 状态键点击上行（sheetCtrl 拉起会话状态半模态；两值 @State 在页面，面板与技能
      // 半模态直接读）
      designatedSkillId: $designatedSkillId,
      designatedSkillName: $designatedSkillName,
      onRemoveSkillDesignate: (): void => {
        // 取消指定（同技能面板关当前开关 / 发送清态口径——双值同清）
        this.designatedSkillId = '';
        this.designatedSkillName = '';
      },
      onOpenStatus: (): void => {
        this.sheetCtrl.openStatus();
      },
      thinkingValue: $thinkingValue,
      // 标题栏思考键交互期（二百二十九）：输入栏收起守卫第三源（HDS 路径思考 chip 已退役）
      thinkingHold: $thinkingHold,
      modelLabel: $modelLabel,
      // 上下文用量圆环（2026-09-17）：值 @Link 下发（链第 1→2 层）+ 点击上行开面板
      ctxRingPct: $ctxRingPct,
      onOpenContext: (text: string): void => {
        this.sheetCtrl.openContext(text);
      },
      fullInputDraft: this.fullInputDraft,
      fullInputCmd: this.fullInputCmd,
      // 待发引用（引用功能笔 U-E）：@Link 链第 1→2 跳（本页真源 → Content 再转发输入栏
      // 引用条；清空点 = × 键上行与发送链成功清空两路）
      pendingQuote: $pendingQuote,
      onFullscreen: (text: string): void => {
        this.sheetCtrl.openInput(text);
      },
      // 草稿文本上行接收（ChatInputBar @Watch → Content 转发 → 此处，见成员注释）
      onDraftTextChange: (text: string): void => { this.draftTextLive = text; },
      onPickThinking: (option: string): void => {
        this.thinkingValue = option; // 选择落值驱动 chip 回显 + 经 refs 进请求（任务 B）
      },
      onSend: (text: string, attachments: PendingAttachment[]): boolean => {
        // 返回值原样透传（2026-09-15 发送链收口笔）：输入栏据此决定清不清草稿
        return this.sendWithAttachments(text);
      },
      onAbort: (): void => {
        this.lifecycle.sendCtrl.abort();
      },
      onAddFile: (): void => {
      // 附件与提示词面板入口（提示词/助手选择无行会话走内存覆盖零写库；附件清理走既有
      // 防线：发送即删 + 离页 cleanupAttachments）
        this.sheetCtrl.openPrompt();
      },
      // 长文本粘贴转附件（胶囊与全屏面板两处输入面同形）：转成即入列并 settle(true)，未入列
      // settle(false)。输入框文本的对齐由输入面按 settlePastedText 单源判据做（本处不碰
      // 草稿）；catch 兜底防收口悬挂
      onPasteLongText: (text: string, settle: (converted: boolean) => void): void => {
        this.attachCtrl.addPastedText(text).then(settle).catch((): void => settle(false));
      },
      // 附件行删除（缩略图释放、沙箱副本删除与数组去项三件成对，本地状态独占无网络副作用）
      onRemoveAttachment: (index: number): void => {
        this.attachments = removePendingAttachment(this.attachments, index);
      },
      onRetry: (): void => {
        this.loadCtrl.refreshPage();
      },
      // ── 消息气泡底栏（★ rik 形态统一笔：重试唯一入口 = 气泡重试键〔末条底栏 / 历史答案
      // 行 / 空正文状态行三形态共用〕——菜单域过闸后走 ChatRetryCtrl.retryAt 单链；「其他
      // 回答」唯一入口 = 行内步进器计数位〔onAnswerPanel → openFor〕）──
      onRetryMsg: (msgId: string): void => {
        this.messageMenuCtrl.retryFromBubble(msgId);
      },
      // 回答版本步进（箭头切版本 / 计数位开面板——编排全在 answerCtrl）
      onAnswerStep: (msgId: string, direction: number): void => {
        this.answerCtrl.stepVersion(msgId, direction);
      },
      onAnswerPanel: (msgId: string): void => {
        this.answerCtrl.openFor(msgId);
      },
      // 提问版本步进（user 行箭头切提问变体——与回答步进同链，编排全在 answerCtrl）
      onQuestionStep: (msgId: string, direction: number): void => {
        this.answerCtrl.stepVersion(msgId, direction);
      },
      onMoreMenu: (msgId: string): void => {
        this.messageMenuCtrl.open(msgId);
      },
      // ask_user 答案上行（2026-09-02 工具调用底层）：交互卡提交 → 执行轮挂起续跑
      onAskSubmit: (callId: string, answerJson: string): void => {
        this.lifecycle.sendCtrl.resolveAsk(callId, answerJson);
      },
      // browse_act 高危确认上行（2026-09-18 P2·B 单元）：确认卡作答 → 执行轮挂起续跑
      onBrowseConfirm: (callId: string, approved: boolean): void => {
        this.lifecycle.sendCtrl.resolveBrowseConfirm(callId, approved);
      },
      // 模板重发上行（编辑对话框在 ChatPageContent 闭环，执行单点重发域）
      onResendTool: (msgId: string, toolName: string, argsJson: string): void =>
        this.lifecycle.sendCtrl.resendTool(msgId, toolName, argsJson),
      // 摘要提示行点击开上下文用量面板（三级链末端：ChatMessageItem.onOpenUsage →
      // ChatPageContent 透传 → 本方法）
      onOpenUsage: (): void => {
        this.sheetCtrl.openContext('');
      },
      // 触顶翻页（2026-08-31 任务 D）：内容区触顶 → 游标前查 + 头部前插；锚点恢复在 ctrl 侧
      onLoadOlder: (): Promise<void> => this.loadCtrl.loadOlder(),
      // 会话改动清单卡文件行点击（任务② U5）：先播种面板载荷再走既有机单入口开
      // 'fileChanges' 形态（不新开状态机——关闭链五件式全承本页既有机）
      onOpenFileDetail: (entry: FileChangeEntry): void => {
        this.fileDetail = entry;
        this.openSheet('fileChanges');
      }
    })
  }

  // 半模态面板内容（坑51：bindSheet builder 位挂组件内 @Builder；组件直挂参数绑定自动刷新——坑75）
  @Builder
  SheetHost() {
    if (this.sheetKind === 'queue' || this.sheetKind === 'queueEdit') {
      ChatQueueHost({
        kind: this.sheetKind,
        queueCtrl: this.lifecycle.queueCtrl,
        sheetCtrl: this.sheetCtrl,
        bottomInset: this.bottomPad,
        onRequestClose: (): void => { this.closeSheet(); }
      })
    } else if (this.sheetKind === 'input') {
      // 全屏输入宿主域（P2 拆缝：装配与 onSend/onClose 编排整段外迁 ChatFullInputHost——
      // busy 守卫与投递收口单源在彼件〔★ Q2 起 busy 改判入队：原 busy 前置 toast 退役，
      // 面板发送交 send 守卫自动入队，见彼件 onSend 注释〕；init/draft/cmd/live 四通道留
      // 本页多域共享，经值参与宿主回接闭包对接）
      ChatFullInputHost({
        initial: this.fullInputInit,
        attachCount: this.attachments.length,
        bottomInset: this.bottomPad,
        onDraftChange: (text: string): void => {
          this.fullInputLive = text;
        },
        // 长文本粘贴转附件（面板侧）：判定与收口判据与胶囊同源，见 refs 处同段注释
        onPasteLongText: (text: string, settle: (converted: boolean) => void): void => {
          this.attachCtrl.addPastedText(text).then(settle).catch((): void => settle(false));
        },
        deliver: (text: string): boolean => this.sendWithAttachments(text),
        // 投递成功收尾（原 else 块三行原样：清草稿命令 + 清 live + 关面板——状态真相在页面）
        onDelivered: (): void => {
          this.applyFullInputDraft('');
          this.fullInputLive = '';
          this.closeSheet();
        },
        // 「保存」/xmark 关闭（原 onClose 体原样：live 回写胶囊 + 关面板）
        onPanelClose: (): void => {
          this.applyFullInputDraft(this.fullInputLive);
          this.closeSheet();
        }
      })
    } else if (this.sheetKind === 'fileChanges') {
      // 会话改动文件详情（任务② U5）：零暂存零确认（关闭 = 恒放行直落）；「在工作区中查看」
      // 键与定位域已随两千零九十节退役，面板不再持 pathStack
      ChatFileChangesDetailPanel({
        entry: this.fileDetail,
        onClose: (): void => { this.closeSheet(); },
        bottomInset: this.bottomPad
      })
    } else {
      // ★ 硬线拆分笔：model/prompt/context/compress/editAssistant/stats/status 七面板装配
      // 编排整族外迁 ChatSheetPanelsHost（分支族件化，非整段转接——判例沿革见该件头注释）；
      // 本页留 refs 供给与 @Link 转传（读口闭包现读页面 @State/成员，写上行编排体留本页闭包）
      ChatSheetPanelsHost({
        kind: this.sheetKind,
        bottomInset: this.bottomPad,
        usage: $ctxUsage,
        editAssistantInit: this.editAssistantInit,
        compressCtrl: this.compressCtrl,
        refs: {
          conversationId: (): string => this.conversationId,
          conn: (): AiConnection | null => this.conn,
          sending: (): boolean => this.sending,
          modelLabel: (): string => this.modelLabel,
          providerLabel: (): string => this.providerLabel,
          thinkingValue: (): string => this.thinkingValue,
          designatedSkillId: (): string => this.designatedSkillId,
          designatedSkillName: (): string => this.designatedSkillName,
          allMessages: (): ChatMessage[] => this.dataSource.allMessages(),
          clipLimit: (): number => this.lifecycle.sendCtrl.assistantClipLimit(),
          statusSource: (): ChatStatusSource => this.lifecycle.sendCtrl.statusSource(),
          boundAssistantId: (): string => this.lifecycle.sendCtrl.boundAssistantId(),
          promptOverrideId: (): string => this.lifecycle.sendCtrl.promptOverrideId(),
          onPickModel: (providerId: string, modelId: string): void => {
            this.sessionOverrideCtrl.pickModel(providerId, modelId);
          },
          // 归属与注入并存（两覆盖各自独立——选提示词不清助手归属、选助手不清提示词注入；
          // 有行会话面板侧另有落库，两态并存一致）
          onPromptOverride: (promptId: string, assistantId: string): void => {
            this.lifecycle.sendCtrl.setBoundOverride(assistantId);
            this.lifecycle.sendCtrl.setPromptOverride(promptId);
            this.sessionOverrideCtrl.refreshWebSearchFlag(); // 换助手 = 联网上限可能变（换提示词不动上限，多刷一次无害）
          },
          // 面板内开关落点（纯内存态；发送漏斗首行恒写 ChatSendCtrl，投递后自动清——
          // 沿既有链，见 designatedSkillId 字段注释）
          onSkillDesignated: (skillId: string, skillName: string): void => {
            this.designatedSkillId = skillId;
            this.designatedSkillName = skillName;
          },
          onPickAttachment: (kind: FilePickKind): void => { this.onPickAttachment(kind); },
          // 重发文件行点击（面板五）——薄转发控制器复制入列口，返回值回落子面板驱动「已加入」态
          onReissuePicked: (name: string, srcRelPath: string, workspacePath: string,
            sourceRow: AttachmentListRow | null): Promise<boolean> =>
            this.onReissuePicked(name, srcRelPath, workspacePath, sourceRow),
          // 联网卡两动作（★ 2026-10-30 联网项迁出笔，落点同原菜单二级链）：点引擎 =
          // 全局当前引擎 + 本会话联网开；「关闭」= 本会话覆盖 '0'
          onWebEnginePick: (engineId: string): void => {
            this.sessionOverrideCtrl.pickWebEngine(engineId);
          },
          onWebClose: (): void => {
            this.sessionOverrideCtrl.pickWebSearch(false);
          },
          onEditAssistantDraft: (text: string): void => {
            this.editAssistantLive = text;
          },
          onSubmitEditMessage: (text: string): Promise<boolean> => this.branchCtrl.submitEditMessage(text),
          onEditAssistantClose: (): void => {
            this.editAssistantRequestClose();
          },
          onCloseSheet: (): void => { this.closeSheet(); }
        }
      })
    }
  }

  // ★ 2026-11-17 对齐二级对话页笔：主区常驻态自绘标题行（HomeTitleBarRow + homeMode build
  // 覆盖层分支）整域退役——标题栏上收官方 HdsNavigation stackBuilder 插槽（DrawerHomeTitleBar
  // 挂 HomeNavigation，键回官方生效区出材质，动作经命令键下行）。onShown/onWillDisappear 等
  // NavDestination 生命周期本形态无钩子（主区常驻无回栈概念——助手/标题变更经既有广播键驱动
  // 刷新）

  build() {
    if (this.homeMode) {
      // 与二级页同构：内容恒全高铺到标题栏背后，topPad 只在 Content 内消费。外层若再
      // padding，会同时缩矮空态居中视口、下移更多菜单锚点，并截断标题栏渐变区的内容透出。
      // BrowseHost 与消息流仍须 Stack 叠放，避免透明 Web 在纵排中把消息流推出屏外。
      Stack({ alignContent: Alignment.Top }) {
        Stack() {
          this.Content()
        }
        .width('100%')
        .height('100%')
        if (this.queueBandActive) {
          this.QueueBand(true)
        }
      }
      .width('100%')
      .height('100%')
      // ★ 主区显示到达（2026-11-17 真机回归修，P0）：主区常驻无 NavDestination.onShown，
      // 而 dataSource.shellArrived 唯一写点 = lifecycle.onReShown（消息区 opacity 判据）——
      // 不承接即恒 0：历史加载成功、空态层一隐就整片空白。主区恒在显示态，挂载即到达；
      // 换会话重建后新实例再承接。禁挪 aboutToAppear：分享消费须晚于 ChatInputBar 首建。
      .onAppear((): void => {
        this.lifecycle.onReShown();
      })
      // 半模态面板（坑64 姿势与档位分发同 PageShell 版逐字一致）
      .bindSheet($$this.sheetShow, this.SheetHost(), sheetPanelOptions(
        (action: DismissSheetAction): void => {
          this.sheetCtrl.handleGestureClose(action);
        }, this.sheetKind === 'model' || this.sheetKind === 'input' ||
          this.sheetKind === 'editAssistant' || this.sheetKind === 'queueEdit' ? DETENTS_FULL :
          (this.sheetKind === 'prompt' || this.sheetKind === 'context' ||
            this.sheetKind === 'status' || this.sheetKind === 'queue' ||
            this.sheetKind === 'fileChanges' ?
            [SheetSize.MEDIUM, SheetSize.LARGE] : DETENTS_FULL),
        this.sheetKind === 'compress' || this.sheetKind === 'editAssistant' ||
          this.sheetKind === 'queueEdit',
        (): void => {
          this.onSheetGone();
        }))
    } else {
      this.PageShellBuild()
    }
  }

  @Builder
  PageShellBuild() {
    PageShell({
      // 官方主标题恒空（两行由覆盖层自绘，标题文本走广播键；标题生成链与列表显示零改动）
      title: '',
      // 会话页背景标记（「背景仅用于会话页」开关）：本页即对话页，开关开启时仍显示
      // 自定义背景（PageBackground suppressCustomBg 组合判定）
      bgSessionPage: true,
      // 页面重新显示重载助手绑定值（2026-09-08 P1-3 修复——语义与守卫见 ChatPageLifecycle.onReShown）
      onShown: (): void => {
        // 回栈重见按会话 id 复核一次换档，id 不变时空操作（2026-11-09 自检轮）
        enterConversation(this.conversationId);
        this.lifecycle.onReShown();
        // 标题栏两态：上层页可能改过会话名（列表改名 / 标题生成），重显即时重查
        this.titleCtrl.refresh();
      },
      // 转场前静默（★ 2026-10-16 掉帧期3 R1-a）：链体与解冻见 ChatPageLifecycle.silenceForTransition
      onWillDisappear: (): void => {
        this.lifecycle.silenceForTransition();
      },
      // ★ U1 装载链退出取消闸·置闸点 A（链体与不挂 onWillDisappear 理由见 ChatPageLifecycle.onBackPressedExitGate；kill 默认关零行为）
      onBackPressed: (): boolean => this.lifecycle.onBackPressedExitGate(),
      // 标题栏覆盖层恒挂（B 路线两态中央区 + 右端更多单圆键，官方主标题恒空）
      titleBarStack: (): void => {
        this.TitleBarContent();
      },
      // menuHds 恒传 null（官方菜单数组无自定义 builder 位，右端键并入覆盖层）
      menuHds: null,
      // 排队入口条（★ U1）：标题栏下方带承载；有排队才显示、空则收起（titleBarBottomHidden
      // 是 @Prop 运行期收起官方通道——titleBarBottom 普通成员不能动态置空）
      titleBarBottom: (): void => {
        this.QueueBand();
      },
      titleBarBottomHidden: !this.queueBandActive,
      content: (): void => {
        this.Content();
      }
    })
      // 半模态面板（坑64 姿势 + 坑73 手势关闭收口；档位：model/input/editAssistant/queueEdit
      //= DETENTS_FULL / prompt/context/status/queue/fileChanges = [MEDIUM, LARGE]（任务书 A-致1
      // 裁：fileChanges 落半屏起组——漏补则落链尾 DETENTS_FULL 兜底开全高档）/ compress/stats
      // 末段兜底；下拉回弹形态与 `$$` 双向/手势关闭路由见 KimiSheetCommon 与 ChatSheetCtrl）
      .bindSheet($$this.sheetShow, this.SheetHost(), sheetPanelOptions(
        (action: DismissSheetAction): void => {
          this.sheetCtrl.handleGestureClose(action);
        }, this.sheetKind === 'model' || this.sheetKind === 'input' ||
          this.sheetKind === 'editAssistant' || this.sheetKind === 'queueEdit' ? DETENTS_FULL :
          (this.sheetKind === 'prompt' || this.sheetKind === 'context' ||
            this.sheetKind === 'status' || this.sheetKind === 'queue' ||
            this.sheetKind === 'fileChanges' ?
            [SheetSize.MEDIUM, SheetSize.LARGE] : DETENTS_FULL),
        this.sheetKind === 'compress' || this.sheetKind === 'editAssistant' ||
          this.sheetKind === 'queueEdit',
        (): void => {
          this.onSheetGone();
        }))
  }
}
