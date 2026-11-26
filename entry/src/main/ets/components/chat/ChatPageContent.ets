// 聊天页内容区组件（自 dshinhm ChatPageContent 去 kap 改造；拆分形态先例 LogPage/LogPageContent
//——主文件留 @State/生命周期/网络调度，本组件管 UI 布局与展示，数据经 @Prop/@ObjectLink 入、
// 事件经回调出）。布局（dshinhm 定稿）= Stack 底对齐多层叠加：
// ① 消息流层（List + LazyForEach，List 恒全高；阅读线只由「底带」表达，止于输入胶囊上沿上方呼吸量）：
//    · ★ List 常驻挂载（坑63）：空态/错误态改覆盖层而非互斥分支——Scroller 全程绑定，
//      空态下 scrollToEnd 不再抛 BusinessError 闪退；
//    · 顶部留白用官方 contentStartOffset（内容起始静止位置下移 topPad、滚动时可滚入标题栏
//      蒙层透出——与「padding 固定视口内缩」语义不同，勿改回 padding）；底带 = 宿主实测高 −
//      阅读高 + CHAT_TAIL_BREATH 呼吸量（宿主/胶囊实测同源、同帧落值于
//      ChatReadingViewport.bandOf，禁第二处独立测量推带；呼吸量只在单源落点加性一项），
//      contentEndOffset 与跟随 endInset 同挂底带恒等（违反即复发「终点与可读线不一致」）；
//      List 本体不裁高度（视口裁剪形态已退役——直角切线/滑不到底/不透出渐隐同源根因）；
//      ★ 键盘态底带红线：底带对输入栏几何实测即时——键盘/多行/展开/收起一律逐帧跟随，
//      **禁再上冻结/钳位/展开期扣减项**（「展开期扣实测增量」旧口径已撤——真机收键盘不失焦
//      时 hold 长期驻留，该扣减把末条底边恒压在展开态胶囊上沿下方 32vp〔「键盘抬起态发送
//      锚点下移」报障根源〕；现口径 = 任何形态末条底边停在输入栏上沿上方呼吸量，展开/收起时
//      内容随输入栏平滑上/下移，勿再回填扣减项）；
//    · 边缘回弹官方默认（撤 alwaysEnabled：不满一屏期不可滚不可弹，S4 回弹冻结同根消失；
//      细判与坑76 倒退说明见 build 内 .edgeEffect 注释）；
//    · ★ 底锚双态：stackFromEnd 开 = 贴底交给布局（末条底边恒 = 底锚，内容增长无跨帧补偿）、
//      ChatFollowController 弹簧补偿链短路（模式位随锚态同拍同步——reevaluateAnchor，勿再退
//      回按常量一次落位的恒喂形态）；关 = 弹簧补偿链旧路径——单常量切态见
//      Theme.CHAT_STACK_FROM_END_ENABLED，真机核验点与 fallback 见方案档 §4；
// ①b 空态/错误态/受限态覆盖层（三分支互斥，判据与推演见 build 内注释）；★ 底部渐变蒙层已取消
//    （2026-10-24 决明拍板「取消输入框附近的灰白蒙层」——撤销后消息滑入输入区由胶囊官方实底
//    直接遮挡，无渐隐，勿无拍板回填）；
// ② 「更多」菜单隐形锚点层（openMenu TargetInfo 定位目标；HitTestMode.None 穿透触摸）；
// ③ 底部浮层（输入栏 ChatInputBar）：悬浮消息流之上，容器全透明（材质在输入栏内部）；胶囊
//    本体上沿独立实测（浮层/键盘/多行几何变化经底带单源逐帧跟随，含展开/收起）；
// ④ 附件查看器 = 导航栈内二级页（pushPathByName 入栈，页面 = AttachmentViewerPage）：本组件
//    只留「分派 + 开页」两件事——分派单点按件型分三路（文档直走系统预览窗 / 图片 / 文本），
//    开页经共享件 AttachmentUtil.openAttachmentViewer（内含连点防重入与 animated=false）；
//    共享元素广播键 ATTACH_SHARED_ID_KEY 在开页前写（图片 = 命中件 id；文本写空串清残留；
//    写点清单见 AttachmentUtil 常量注释）；本组件不持有查看器状态（无「值参跨
//    PageShell.content 冻结」的坑16 面）；两入口（onPreviewAttach / onPreviewAttachment）
//    都在本组件内接线分派。
// 触顶翻页链：头部提示行（加载更早/已到顶）+ onReachStart 触发 + 锚点恢复——编排域在
// ChatOlderCtrl，查询/前插在 ChatPageLoadCtrl.loadOlder，状态乘 ChatDataSource @Track。
// 流式跟随：本层转发 List 纵向来源与触摸生命周期，控制权和主动回底事实单源在 Follow。
// 失败轮重试动作行组件已随 rik 形态统一笔整链退役（见文件尾注）。内容区帧原语（阅读边界
// 合帧器 + 进页减载空闲帧）整域在 ChatContentFrames——本件只持引用。
import { UIContext } from '@kit.ArkUI';
import { ChatReadingFrame } from './ChatContentFrames';
import { ChatReadingViewport } from '../../common/chat/ChatReadingViewport';
import { ChatListAnchorJudge } from '../../common/chat/ChatListAnchorJudge';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { cardDescColor, CARD_SPACING, CHAT_LAYOUT_DEBUG, CHAT_STACK_FROM_END_ENABLED, MORE_MENU_ANCHOR_RIGHT,
  MORE_MENU_BUTTON_BOTTOM_INSET, TITLE_BAR_MASK_EXTRA_HEIGHT } from '../../common/Theme';
// 内容区几何单源（首帧兜底/呼吸量两常量与顶侧让位算式整域在 ChatContentGeometry；本件只消费）
import { CHAT_TAIL_BREATH, CHAT_TAIL_BREATH_NO_BUBBLE, chatContentTopPad, INPUT_BAND_HEIGHT } from './ChatContentGeometry';
import { AttachmentBrief, briefsFromPending, isSystemPreviewKind, openAttachmentViewer,
  openSystemPreview, ATTACH_SHARED_ID_KEY } from '../../common/AttachmentUtil';
import { PendingAttachment } from '../../common/providers/AiTypes';
import { ChatDataSource } from './ChatDataSource';
import { ChatMessage } from './ChatMessageCompose';
import { ChatAskDock } from './ChatAskDock';
import { ChatAskDockClaimCtrl } from './ChatAskDockClaim';
import { ChatDisplayItem, DISPLAY_KIND_CHART, DISPLAY_KIND_FILE_CHANGES, DISPLAY_KIND_SEGMENT } from './ChatDisplayProjection';
import { ChatMessageItem } from './ChatMessageItem';
import { ChatChartRow } from './ChatToolChartCard';
import { ChatFileChangesCard } from './ChatFileChangesCard';
import { FileChangeEntry } from './ChatFileChangesModel';
import { markdownDisplayItemKey } from './ChatMarkdownState';
import { nextMarkdownBindingId } from '../../common/markdown/MarkdownDocumentModel';
import { markdownScrollToAnchorInViewport } from './markdown/MarkdownAnchorScroll';
import { MermaidRenderHost } from './markdown/MermaidRenderHost';
import { ChatProcessSegment } from './ChatProcessSegment';
import { ChatFollowController, ChatFollowLayout } from './ChatFollowController';
import { ChatOlderCtrl, ChatOlderRow } from './ChatOlderCtrl';
import { ChatLoadingOverlay } from './ChatLoadingOverlay';
import { ChatPageEmptyLayer } from './ChatPageEmptyLayer';
import { ChatInputBar } from './ChatInputBar';
import { CHAT_MORE_MENU_ANCHOR_ID } from './ChatMoreMenu';
import { MessageCopySheet } from './MessageCopySheet';
import { clampQuoteText } from '../../common/chat/QuoteCompose';
import { ChatAnswerSheet } from './ChatAnswerSheet';
import { ChatAnswerCtrl, ChatAnswerView, ANSWER_VERSIONS_DIRTY_TICK_KEY } from './ChatAnswerCtrl';
import { TemplateResendDialog } from './TemplateResendDialog';
import { parseResendPrefill } from './ChatToolResendCtrl';
import { parseTemplateParams, templateIdOfSlug } from '../../common/providers/HttpTemplate';
import { HttpTemplateRow, queryHttpTemplateById } from '../../common/store/HttpTemplateDb';
import { overlayMaterial } from '../../common/ImmersiveLevel';
import { ChatLongRevealCtrl, LIST_CACHED_ENTRY } from './ChatLongReveal';
import { sheetPanelOptions } from './KimiSheetCommon';
import { parseSuggestPayload, SUGGEST_PAYLOAD_KEY, SuggestPayload } from '../../common/SuggestGen';
import { isAssistantBubbleVisible, PREF_STREAM_FOLLOW_KEY } from '../../common/AppPreferences';
import { ROUTE_NETWORK_PAGE, ROUTE_PROVIDER_PAGE } from '../../common/RouteNames';

// 改参数重发的执行目标快照（开窗一刻定档 msgId + slug——确认回调取用，防窗口期消息变动
// 错配；显式接口承载——arkts-no-obj-literals-as-types）
interface ResendTarget {
  msgId: string;
  slug: string;
}

// 首帧兜底 INPUT_BAND_HEIGHT 与呼吸量常量单源在 ChatContentGeometry——本件 import 消费

// 进页预创建行数三档窗口（0 = 进页首帧不预建；1 = 揭示在途期保留一行——占位形态下预建成本
// 低、快滑不空窗；5 = 稳态快滑预建保障；机制见 ChatLongReveal LIST_CACHED_* 注释）：本件只持
// @State，决策与恢复时序在 ChatLongRevealCtrl

@Component
export struct ChatPageContent {
  // 消息数据源（ChatPage @State 持有的 @Observed 实例；@ObjectLink 订阅其 @Track
  // messageCount 驱动空态/错误态分支，LazyForEach 经同一引用订阅 IDataSource 增量通知）。
  // ★ 2128 重进恢复：不再靠列表项挂载副作用单点认领——进页生命周期先扫一次（复用运行态
  // 时数据已就绪），全量读库路径由列表项挂载钩子补位；复用对象的 dockOwned 由数据源
  // resetLongMessageExpansion 在换源同拍清零
  @ObjectLink dataSource: ChatDataSource;
  // 列表滚动控制器（父组件持有同一引用，新消息 scrollToEnd 用；普通成员不驱动 UI）
  listScroller: Scroller = new Scroller();
  // 每个宿主独立锚点视口身份，不按会话业务ID复用；仅点击时读取其窗口位置。
  private markdownViewportId: string = 'chat-markdown-viewport-' + nextMarkdownBindingId();
  private listViewportHeight: number = 0;
  // 流式滚动跟随控制器（父组件构造传入——状态与滚动逻辑见该类；本组件只喂手势/到达事件）
  followCtrl: ChatFollowController = new ChatFollowController(this.listScroller);
  // U4 双态判定器：@ObjectLink 订阅 @Track anchored 直驱 stackFromEnd（复位 = ChatPageLoad 重建链）
  @ObjectLink anchorJudge: ChatListAnchorJudge;
  // 触顶翻页编排域（触顶触发/锚点定格与恢复）：箭头闭包延迟求值，声明序在 listScroller/
  // onLoadOlder 之后即安全；busy 升 @Link（重启续答冻结修复）；进页定位与用户真实滚动两参
  // 现读闭包（第五/第六守卫见 ChatOlderCtrl）
  private olderCtrl: ChatOlderCtrl = new ChatOlderCtrl(
    (): ChatDataSource => this.dataSource,
    (): Scroller => this.listScroller,
    (): Promise<void> => this.onLoadOlder(),
    (): boolean => this.busy,
    (): boolean => this.followCtrl.isEntryAlignActive(),
    (): boolean => this.followCtrl.userHoldsReadingPosition());
  // 顶部留白（标题栏蒙层下沿 = 状态栏 + TITLE_BAR_MINI_HEIGHT + TITLE_BAR_MASK_EXTRA_HEIGHT）
  // / 底部留白（系统导航条高）。★ @Prop（2026-11-17 真机回归修）：drawer 主区冷启动时
  // statusBarHeight / navBarHeight 由 Index 异步实测下发，晚到值必须穿透本层——普通成员只在
  // 构造期取一次，会把「更多」菜单隐形锚点的 margin（contentTopPad 派生）与输入栏底距冻结在
  // 首帧 0 状态栏口径（真机「新进应用更多菜单偏上、切一次会话后正常」即本缺口：重建才拿到
  // 晚到真值）。二级页形态来源（PageMapBuilder 注入）恒定，@Prop 更新面天然零变化。
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 排队入口条状态：@Link 三级链（页面 @State → 本层 → 让位算式），坑16 正解通道
  @Link queueBandActive: boolean;
  @Link queueCount: number;
  @Link queuePaused: boolean;
  onOpenQueue: () => void = (): void => {
  };
  // 会话运行中（透传输入栏：true = 发送键变停止键）。★ @Link 归正——原 @Prop 经
  // PageShell.content（@BuilderParam）断点，重启后作答续流时冻结在首帧 false（坑16 同族实锤
  // 复发，处置照自检报告 O1「同族通道升 @Link」口径，先例 thinkingHold/thinkingValue）
  @Link busy: boolean;
  @StorageProp(PREF_STREAM_FOLLOW_KEY) @Watch('onFollowPreferenceChanged') private streamFollow: boolean = true;
  // DB 就绪（透传输入栏：占位符切换 + 发送键禁点——M1 行为）
  @Prop dbReady: boolean = true;
  // 初始加载失败提示（'' = 无；与 messageCount 联合判定错误态——覆盖层含「重试」）
  @Prop errorText: string = '';
  // 待发附件（透传输入栏；父组件 @State 持有，选择入列后非空即渲染附件条，点开预览经
  // onPreviewAttachment 在本组件分派）。@Prop 传数组仅靠父整组赋值刷新——现状消费面与该
  // 语义一致，坑16 家族若现冻结症状再按规范 §3 换 @Link 通道
  @Prop attachments: PendingAttachment[] = [];
  // 思考强度（透传输入栏 chip；随请求下发，'' = 默认不传）。@Link 归正——本组件居
  // PageShell.content（@BuilderParam）内，@Prop 不随父 @State 刷新（坑16）；菜单选项集不透传
  //——chip 行 @StorageProp 自订阅广播键（坑16 同款正解）
  @Link thinkingValue: string;
  // 单条消息指定技能（id+名双链：id 喂状态键换色判据与 canSend、名喂技能条显示——名链
  // 2026-11-02 技能条笔随新条复建）。@Link 通道理由同 thinkingValue——本组件居
  // PageShell.content 内，@Prop 不随父刷新（坑16）
  @Link designatedSkillId: string;
  @Link designatedSkillName: string;
  // 技能条 × 键上行：取消指定（链回页面清两值；命名避开 onClearDesignate 子串——104 组负向钉）
  onRemoveSkillDesignate: () => void = () => {
  };
  // 状态 chip 点击上行（透传输入栏 → ChatPage sheetCtrl 拉起会话状态半模态）
  onOpenStatus: () => void = () => {
  };
  // 待发引用：null/'' = 无引用。挂点 = 页面 @State 经 @Link 下行（ChatPage @State 是发送链
  // refs 读口的可达真源；本组件居 PageShell.content 内 @Prop 会冻结〔坑16〕）；会话页内存态，
  // 不持久化、不进草稿链；切会话 = 新页面实例天然归 null（同会话翻页/进出子页不清——
  // conversationId 不变即不清）
  @Link pendingQuote: string | null;
  // 档位选择回调上行（父组件落值回显；消费方 = 回退路径输入栏 chip——HDS 路径思考入口已迁
  // 标题栏「思考」热区，其菜单在 ChatPage 内直写 thinkingValue）
  onPickThinking: (option: string) => void = () => {
  };
  // 标题栏思考键交互期（按压或菜单开着——输入栏收起守卫第三源；@Link 归正通道同
  // thinkingValue〔坑16〕）
  @Link thinkingHold: boolean;
  // 当前模型名（透传输入栏工具行显示，只显示不可点；'' = 未解析到连接 → 输入栏显示「未选择」
  // 灰字）。@Link 归正通道（坑16 同 thinkingValue）
  @Link modelLabel: string;
  // 上下文用量圆环值：-1 = 未知/无数据（仅底环）；0~100 占比。@Link 三级链第二跳（坑16 正解
  // 通道同 modelLabel）；点击回调上行开面板（带草稿文本）
  @Link ctxRingPct: number;
  onOpenContext: (text: string) => void = () => {
  };
  // 全屏输入（透传输入栏）：回写命令（父 @State → @Prop——cmd tick 驱动覆盖）
  @Prop fullInputDraft: string = '';
  @Prop fullInputCmd: number = 0;
  // 点输入框选择菜单「全屏输入」项上行（当前输入框文本 → 父暂存为面板初值；2026-10-31 自
  // 工具行图标键迁入选择菜单，透传链不变）
  onFullscreen: (text: string) => void = () => {
  };
  // 草稿文本上行转发：ChatInputBar @Watch → 本层 → ChatPage draftTextLive——每键一次的普通
  // 成员赋值，无渲染
  onDraftTextChange: (text: string) => void = () => {
  };
  // 推荐问题广播载荷：SuggestGen 写回/清空时 tick 递增 + 本键覆写 JSON 串 {msgId, items}——
  // @Watch 命中后按 msgId 在自身 dataSource 找消息原地挂 suggestions 字段（@Observed 对象级
  // 观察驱动渲染）。会话 id 不经 ChatPage 传入本组件（ChatPage 硬线零改动），故订阅「载荷键」
  // 而非「tick 后读会话行」——msgId 全局唯一，他会话广播在本页 dataSource 查不到 = 天然
  // no-op，跨会话无串扰（tick 键同步递增供时序观察，本组件不订阅）
  @StorageProp(SUGGEST_PAYLOAD_KEY) @Watch('onSuggestPayload') suggestPayload: string = '';
  // ── 回答版本步进重算 tick ──
  // ChatStreamFlowCtrl 在轮落库回填（stampNodeRef）后递增本键——重试完成的轮此刻才可算
  //「多版本」；@Watch 消费后调 answerCtrl 全表重算（行内步进器数据面）。订阅在本组件 =
  // answerCtrl 成员在此且 ChatPage 越硬线净减笔不加上行（载荷键同款先例）；跨页消费无害：
  // 各页按自身会话重算，值同不写
  @StorageProp(ANSWER_VERSIONS_DIRTY_TICK_KEY) @Watch('onAnswerVersionsDirty')
  private answerVersionsTick: number = 0;
  // ── 推荐语回填命令 ──：chip 点击恒在本组件内发命令（「点击推荐语填入输入框」偏好已退役，
  // 行为固化为不可关闭，不再有直接发送分支）
  //（draft + tick 递增）——tick 驱动 ChatInputBar @Watch 覆盖文本并聚焦自身 TextArea（展开
  // 卡 + 弹键盘由输入栏既有 onFocus 链接管）。★ 命令源在本组件（chip 上行链头），不走
  // ChatPage（硬线零改动，同载荷键口径）；与父页 fullInput 通道刻意独立（那是面板关闭/发送
  // 清空的静默覆盖不聚焦；本通道 = 填入并进入编辑态）。只写于命令时点，正常打字不改本对，无输入回环
  @State private suggestFillDraft: string = '';
  @State private suggestFillCmd: number = 0;
  // ═══ 事件回调（纯展示组件不触网，全部上行 ChatPage） ═══
  // 发送上行（返回值 = 「已投递或已进入确认流程」——输入栏按它决定清不清草稿；契约全解见
  // ChatPage.sendWithAttachments 头注释）
  onSend: (text: string, attachments: PendingAttachment[]) => boolean = (): boolean => false;
  onAbort: () => void = () => {
  };
  // 「+」点击（附件与提示词面板入口——上行父组件开 ChatPromptSheet 半模态）
  onAddFile: () => void = () => {
  };
  // 附件行删除（index 上行）
  onRemoveAttachment: (index: number) => void = () => {
  };
  // 长文本粘贴转附件：粘贴文本上行转附件；settle = 转换结果回报（必调恰一次，收口判据由
  // ChatInputBar 侧单源执行）——本组件只透传。★ 默认实现 = settle(false) 而非空体：输入栏
  // 已拦下原生插入，空体 = 长文本静默消失；settle(false) 退化为「不转附件、原文照常落框」
  onPasteLongText: (text: string, settle: (converted: boolean) => void) => void =
    (_text: string, settle: (converted: boolean) => void): void => {
      settle(false);
    };
  // 错误态「重试」（重拉历史 + 重读连接——aicontrol 语义，接 ChatPage 既有方法）
  onRetry: () => void = () => {
  };
  // ── 消息气泡底栏透传（普通成员通道——页级恒定无坑16 风险）──
  // 底栏重试键上行（msgId；ChatPage 委托菜单域 retryFromBubble 单链——末条与历史答案行同形；
  // 原 kind='retry' 占位行与失败轮重试上行链已随退役笔删除）
  onRetryMsg: (msgId: string) => void = () => {
  };
  // 回答版本步进上行（步进器箭头切版本 / 计数位开面板——透传 ChatPage → ChatAnswerCtrl，
  // 本组件零业务）
  onAnswerStep: (msgId: string, direction: number) => void = () => {
  };
  onAnswerPanel: (msgId: string) => void = () => {
  };
  // 提问版本步进上行（user 行箭头——透传 ChatPage → ChatAnswerCtrl.stepVersion，零业务）
  onQuestionStep: (msgId: string, direction: number) => void = () => {
  };
  // 底栏「更多」键上行（msgId；ChatPage 经 ChatMessageMenuHost 按锚点弹出消息菜单）
  onMoreMenu: (msgId: string) => void = () => {
  };
  // 摘要提示行整行点击上行（ChatMessageItem kind='summary' 分支 → ChatPage.openContextSheet
  // 开用量面板；本组件透传零业务）
  onOpenUsage: () => void = () => {
  };
  // ask_user 答案上行（ChatPage 构造处注入 → ToolRuntime.resolveAsk）
  onAskSubmit: (callId: string, answerJson: string) => void = (callId: string,
    answerJson: string): void => {
  };
  // browse_act 高危确认上行（ChatPage 构造处注入 → ToolRuntime.resolveBrowseConfirm；同
  // onAskSubmit 形制）
  onBrowseConfirm: (callId: string, approved: boolean) => void = (callId: string,
    approved: boolean): void => {
  };
  // 输入位接管（2026-11-08）：等待卡到达即接管底部输入位，输入栏与托管位互斥。dockMsg 是
  // 普通成员（消息自观察），dockVisible 才是驱动 UI 的 @State；认领判定整域在 ChatAskDockClaimCtrl。
  @State private dockVisible: boolean = false;
  private dockMsg: ChatMessage | null = null;
  private dockClaim: ChatAskDockClaimCtrl = new ChatAskDockClaimCtrl();
  // 会话改动清单卡文件行点击上行（ChatPage 覆写开详情半模态，U5 接线）
  onOpenFileDetail: (entry: FileChangeEntry) => void = (entry: FileChangeEntry): void => {
  };
  // 模板工具卡重发执行上行（ChatPage 构造处注入 → ChatSendCtrl 重发编排。改参数重发在本
  // 组件开编辑对话框、确认后以收集值走同一回调——执行入口单点）
  onResendTool: (msgId: string, toolName: string, argsJson: string) => void = (msgId: string,
    toolName: string, argsJson: string): void => {
  };
  // ── 改参数重发编辑对话框（本组件闭环——模板行现查与开窗全在此层，ChatPage 硬线零改动；
  // 动态构造照 CustomDialogController 组件成员位先例，坑7）──
  private resendCtrl: CustomDialogController | null = null;
  // 对话框确认后的执行目标（开窗一刻快照——确认回调取用）
  private resendTarget: ResendTarget | null = null;
  // 触顶翻页上行（ChatOlderCtrl 触发后回页面 → ChatPageLoadCtrl.loadOlder 游标前查 + 头部
  // 前插；Promise——resolve/reject 决定锚点恢复，见 ChatOlderCtrl）
  onLoadOlder: () => Promise<void> = () => Promise.resolve();
  // 助手气泡档位：进页读一次存普通成员——重进会话生效（流式期间重跑 build 不换档），只有
  // 组件重建（退页再进）才重读；普通成员不驱动 UI，故不用 @State
  private bubbleVisible: boolean = isAssistantBubbleVisible();
  private readingViewport: ChatReadingViewport = new ChatReadingViewport();
  private readingFrame: ChatReadingFrame | null = null;
  private readingAlive: boolean = false;
  // 长消息揭示的页面级联动域（进页预创建行数三档窗口 / 展开阅读期底锚冻结 / 滚动暂停揭示
  //——机制与生命周期见 ChatLongReveal 头注释；本件只持 @State 与两条回调接线：applyCachedRows
  // 写 listCachedCount；onHoldChanged 同步 List 判据与 followCtrl 模式位）
  private longReveal: ChatLongRevealCtrl = new ChatLongRevealCtrl({
    alive: (): boolean => this.readingAlive,
    dataSource: (): ChatDataSource => this.dataSource,
    ui: (): UIContext => this.getUIContext(),
    applyCachedRows: (rows: number): void => {
      if (this.listCachedCount !== rows) {
        this.listCachedCount = rows;
      }
    },
    onHoldChanged: (_suspended: boolean): void => {
      this.followCtrl.setStackAnchored(this.stackAnchored());
    }
  });
  // 底带 = 宿主实测高 − 阅读高（bandOf 同帧同源）：contentEndOffset 与跟随 endInset 同挂本值
  // 恒等——末条静止位 = 输入栏胶囊上沿上方呼吸量（按气泡档位取值，无泡态 22 见几何件）
  @State private readingBand: number = INPUT_BAND_HEIGHT +
    (this.bubbleVisible ? CHAT_TAIL_BREATH : CHAT_TAIL_BREATH_NO_BUBBLE);
  // 列表预创建行数现读（★ 先导笔）：进页初值 = 窗口值，首帧空闲回调恢复稳态（见常量注释）
  @State private listCachedCount: number = LIST_CACHED_ENTRY;
  // ── 消息全文面板（长按气泡 → 面板内自由选择复制）──
  // 宿主 = 本组件根 Stack（规范-半模态 §1 三级挂点「分支根」，非 ForEach 行内、存活期不随
  // 数据销毁）；不挂 ChatPage 页面根是行数预算决策，本面板全链在本组件闭环
  @State @Watch('onSheetVisibleChanged') private copySheetShow: boolean = false;
  // 面板文本快照（长按一刻的 msg.text 拷入——流式增量不跟进，面板职责是复制定稿文字）
  @State private copySheetText: string = '';
  // 助手消息（true = 面板显示 AI 标识行）
  @State private copySheetFromAssistant: boolean = false;
  // ── 关闭-再开协调（机制与官方依据单源 = KimiSheetCommon.sheetPanelOptions 第四参注释）──：
  // 关闭后离场动效在途期内再长按另一条消息，直接写下的可见性 true 会被吞或被框架收尾回写
  // 压回——在途期只记开意图，等离场动效结束再补开
  private sheetClosing: boolean = false;
  private pendingOpen: boolean = false;
  // ── 面板内容形态分派 ──
  // 'copy' = 消息全文（既有行为）/ 'answers' = 其他回答：同一 bindSheet 挂载点、同一关闭
  // 协调与关闭链三件；关闭恒不复位本值（下次开启由待开载荷改写——关闭动画期内容树恒在）
  @State private contentSheetKind: string = 'copy';
  // 回答面板视图快照（控制器 publish 整体替换；@Link 直链进 ChatAnswerSheet——同一事实源）
  @State private answerView: ChatAnswerView = {
    loading: false, switching: false, errorText: '', needsReload: false,
    selectedAnswerId: '', choices: []
  };
  // 待开载荷（携带内容形态与正文快照——已有面板离场完成后 applyOpen 才安装新载荷，禁止
  // 关闭动画中直接切换已显示树；回答类载荷的目标代次由控制器代次门承担：publish/open 恒同
  // 代同拍，单槽覆盖 = 新目标恒胜）
  private pendingKind: string = 'copy';
  private pendingCopyText: string = '';
  private pendingCopyAssistant: boolean = false;
  // 回答控制器（页面装配处注入的普通恒定成员——控制器页面寿命；本组件只在自身存活期
  // attach 视图接收端、销毁时 detach，不让页面控制器长持已销毁组件）
  answerCtrl: ChatAnswerCtrl | null = null;
  // ★ 2026-11-05 菜单笔：原 messageMenuCtrl 注入（仅为把 openBodySnapshot 绑到 setBodyViewer）
  // 随 body 场景整条退役——本组件与消息菜单控制器现已无接口；菜单的 open/retryFromBubble 由
  // 页面侧直接驱动。
  // ── 附件查看器（导航栈内二级页）：查看器状态不在本组件（数据随路由参数生命周期），本层
  // 只持路由栈引用与两入口分派；打开经共享件 openAttachmentViewer ──
  // 路由栈（普通成员——页面装配处注入；开查看器二级页用）
  pathStack: NavPathStack = new NavPathStack();

  // ── 生命周期：回答面板视图接收端绑定 ──
  // 出现时 attach（publish 落本组件 @State；open/close 走本组件面板可见性协调）/ 销毁时
  // detach（控制器不长持已销毁组件——sink 至多一个）
  aboutToAppear(): void {
    this.readingAlive = true;
    this.followCtrl.attach(this.getUIContext(), (): ChatFollowLayout => {
      // ★ 末条下标改喂 lastContentIndex() 单源口（原内联式收编进数据源读口，与 jumpToBottomAt
      // 两调用点同口径；行为逐字等价）
      return { epoch: this.dataSource.pathEpoch(), lastIndex: this.dataSource.lastContentIndex(),
        viewportHeight: this.listViewportHeight, endInset: this.readingBand,
        olderLoading: this.dataSource.olderLoading };
    });
    // 底锚模式位初值（随锚态动态；展开阅读期由 longReveal.isSuspended 冻结——见
    // stackAnchored 单源）：总开关关 = 恒旧路径；开 = 随 anchored（贴顶期补偿链武装但天然
    // 空转：内容不满屏时 remaining 恒 0 零位移）
    this.followCtrl.setStackAnchored(this.stackAnchored());
    // 转场静默接线：把本组件帧驱动（阅读帧）接到静默位（静默位单源在 FollowCtrl——页面
    // 转场静默时停拍；销毁成对解绑见 aboutToDisappear）
    this.followCtrl.setSilenceListener((silenced: boolean): void => {
      if (silenced) {
        this.silenceFrames();
      } else {
        this.resumeFrames();
      }
    });
    const ctrl: ChatAnswerCtrl | null = this.answerCtrl;
    if (ctrl !== null) {
      ctrl.attachView({
        publish: (view: ChatAnswerView): void => {
          this.answerView = view;
        },
        open: (): void => {
          this.pendingKind = 'answers';
          this.requestOpen();
        },
        close: (): void => {
          this.requestClose();
        }
      });
    }
    // 进页首扫：重进复用运行态时数据源已就绪（不读库、不重建），观察通道不会补发首帧——
    // 必须在生命周期里认领一次，否则等待卡要等下一次数据变化才回到托管位
    this.syncAskDock();
    // 进页首帧减载：首帧渲染任务结束后按揭示队列判档恢复预创建行数——三档窗口、空闲订阅
    // 与 fail-safe 见 ChatLongReveal 注释
    this.longReveal.armEntryCacheFrame();
  }

  // 内容区顶留白：排队入口条在场 → 带底 + 28；隐藏 → topPad 原样。与
  // PageShell.titleBarBottomHidden 同一 queueBandActive 同源（防「带隐藏了让位还在」错位）；
  // 算式本体单源 = ChatContentGeometry.chatContentTopPad（复用 searchBandContentTop）
  private contentTopPad(): number {
    return chatContentTopPad(this.topPad, this.queueBandActive);
  }

  // 展开局部钉顶开关（listIndex < 0 = 释放）：几何位在跟随控制器（起钉实测屏位 + 有界校正），
  // 渲染位在判定器 rowPin（@Track 直驱 stackFromEnd）——两处同拍同写
  private applyRowPin(listIndex: number): void {
    this.followCtrl.beginRowPin(listIndex);
    this.anchorJudge.rowPin = this.followCtrl.isRowPinned();
    this.followCtrl.setStackAnchored(this.stackAnchored());
  }

  // 认领上行（ChatToolCard 双钩子 → 本口）：判定整域在 ChatAskDockClaimCtrl，本件只镜像
  private claimAskDock(msg: ChatMessage): void {
    this.dockMsg = this.dockClaim.claim(this.dataSource, msg);
    this.dockVisible = this.dockMsg !== null;
  }

  // 释放单入口：作答同帧调，@Watch 见终态与换源兜底也走这里；不回写库、不动协议
  private dismissAskDock(): void {
    this.dockClaim.dismiss();
    this.dockVisible = false;
    this.dockMsg = null;
  }

  // 进页同步：终态/孤儿释放 + 清复用残留标记 + 最靠后等待卡主动认领（重进恢复点）
  private syncAskDock(): void {
    this.dockMsg = this.dockClaim.sync(this.dataSource);
    this.dockVisible = this.dockMsg !== null;
  }

  // 发送 = 阅读动作结束：清展开阅读期底锚冻结、恢复贴底（发送后新消息按惯例吸底）。输入栏
  // 与推荐语直发两条发送路径共用本口
  private sendWithHoldRelease(text: string, attachments: PendingAttachment[]): boolean {
    this.longReveal.release();
    this.applyRowPin(-1); // 发送 = 阅读动作结束：局部钉顶一并解除（新消息按惯例吸底）
    return this.onSend(text, attachments);
  }

  private onFollowPreferenceChanged(): void {
    this.followCtrl.onFollowPreferenceChanged();
  }

  // U4 锚重评（只挂既有事件）：守卫（开关/单向/持阅读位推迟 + hold 收紧为「仅内容仍不满屏
  // 时推迟」——细则见判定器件 evaluate 注释）与判据全在判定器件内。
  // ★ 锚态升格红线（F2）：viaRowHeight = 仅内容行高真变化（新/旧 Area.height 不等）的回报
  // 才允许行高累积跨幅升格——几何瞬变（键盘压缩视口、收键盘回落帧的行位移回报）**不伪升格**；
  // List 视口 / 底带帧 / 终停三路传 false（只喂条数闸快路）
  private reevaluateAnchor(viaRowHeight: boolean = false): void {
    this.anchorJudge.evaluate(this.dataSource.displayCount(), this.listViewportHeight, this.readingBand,
      this.contentTopPad(), this.followCtrl.isHold(), this.followCtrl.userHoldsReadingPosition(), viaRowHeight);
    // 模式位随锚态同拍同步（U4×笔二模式位失配根修）：与 List .stackFromEnd 表达式同源
    //（stackAnchored 单源）——升格拍补偿链即刻短路（布局接管钉底）；reset 降格拍重新武装
    //（贴顶期 remaining=0 天然空转、无代价，判据迟到窗由弹簧链兜住）。只经既有事件驱动，
    // 不新增观察通道
    this.followCtrl.setStackAnchored(this.stackAnchored());
  }

  // 底锚判据单源：List .stackFromEnd、模式位初值/重评同步、局部钉顶同步三处共用——展开是
  // 阅读动作，冻结期与钉顶期都不钉底（不拖向内容末尾、也不把被点行推走）；清位（回底/发送/
  // 换源）自然恢复
  private stackAnchored(): boolean {
    return CHAT_STACK_FROM_END_ENABLED && this.anchorJudge.anchored &&
      !this.longReveal.isSuspended() && !this.anchorJudge.rowPin;
  }

  private scheduleReadingViewport(): void {
    // 转场静默期停排（静默只停帧驱动——解冻 resumeFrames 补调度回正）
    if (!this.readingAlive || this.followCtrl.isSilenced() || this.readingFrame !== null) { return; }
    const frame: ChatReadingFrame = new ChatReadingFrame((): void => {
      if (this.readingFrame !== frame) { return; }
      this.readingFrame = null;
      // 底带单源落点（contentEndOffset / 跟随 endInset / 锚态阅读跨度同挂本值恒等）：
      // 宿主实测高 − 阅读高（bandOf，实测即时）+ 呼吸量（按气泡档位取值，见 chatTailBreath）
      this.readingBand = this.readingViewport.bandOf(INPUT_BAND_HEIGHT) +
        (this.bubbleVisible ? CHAT_TAIL_BREATH : CHAT_TAIL_BREATH_NO_BUBBLE);
      // List 恒全高后 List.onAreaChange 不再反映输入带变化，底带变化须经内容位移钩子驱动
      // 重钉（跟随在位合并下一帧 / 进页校正链活则重对齐；两者皆无零动作不吸底）
      this.followCtrl.onContentShift();
      this.reevaluateAnchor(); // U4：阅读带变化重评锚态（守卫期推迟的重评点之一）
    });
    this.readingFrame = frame;
    try { this.getUIContext().postFrameCallback(frame); }
    catch (error) {
      frame.cancel();
      this.readingFrame = null;
      hilog.warn(0xD5A0, 'ChatPageContent', '阅读边界更新不可用：%{public}s', (error as Error).message);
    }
  }

  aboutToDisappear(): void {
    hilog.info(0xD5A0, 'ChatEnterProbe', 'teardown abs=%{public}d', Date.now()); // ★ U0 观测：旧页销毁绝对时点（独立行不入 tap 差分轴，不写 probe 模块状态）
    this.readingAlive = false;
    this.readingFrame?.cancel();
    this.readingFrame = null;
    // 揭示联动域成对释放（帧 cancel + 空闲订阅释放；展域件注释）
    this.longReveal.dispose();
    // 静默接线成对解绑（★ R1-a U16：控制器不长持已销毁组件——先于 detach 清监听）
    this.followCtrl.setSilenceListener(null);
    this.followCtrl.detach();
    // 清待开意图（离场不再补开）+ 解绑接收端（控制器不再回调已销毁组件）
    this.pendingOpen = false;
    // 托管位清位（不回写 dockOwned：重进时消息由库重建、新对象天然 undefined）
    this.dockVisible = false;
    this.dockMsg = null;
    const ctrl: ChatAnswerCtrl | null = this.answerCtrl;
    if (ctrl !== null) {
      ctrl.detachView();
    }
  }

  // ── 转场前静默入口：只停帧驱动与动画，**不解绑不释放**——禁以 followCtrl.detach() 替代
  //（订阅/ownership 原样保留，转场取消由 resumeFrames 原样恢复）。经 FollowCtrl 静默回调
  // 接线（setSilenceListener 注册）──
  silenceFrames(): void {
    this.readingFrame?.cancel();
    this.readingFrame = null;
  }

  // 解冻（静默位已清后由回调转发）：静默期错过的底带重算在此补一帧（转场窗口内一般无新
  // 几何事件；补调度保证解冻后底带及时回正）
  resumeFrames(): void {
    this.scheduleReadingViewport();
  }

  // Markdown 锚点滚动（最终正文与段内中间正文共用）：用户主动读锚点，先停既有跟随/进页
  // 校正；不改业务滚动控制或持久状态。两条渲染路径只上行消息 id 之外的锚点串到本口。
  private scrollToMarkdownAnchor(id: string): void {
    this.followCtrl.onUserScrollUp();
    markdownScrollToAnchorInViewport(this.getUIContext(), this.listScroller,
      id, this.markdownViewportId, this.contentTopPad() + 8);
  }

  // ★ 2026-11-05 菜单笔：原「中间正文『查看正文』」入口 openBodySnapshot 随 body 场景整条
  // 退役（其唯一调用方 = 菜单 body 分支）；流式快照经 liveBodyTextOf 只读口取权威累积全文的
  // 机制一并删除——长按全文面板在 openMsgCopySheet 内自守「流式中不弹」，不需要该口。

  // 打开查看器（分派单点收敛）：共享广播键在 push 前写入（图片 = 命中件 id——气泡/输入栏
  // 缩略图先行绑定为共享元素 out 侧；文本 = 空串清除残留绑定）；push 与连点防重入在共享件
  // AttachmentUtil.openAttachmentViewer 内（多宿主共用，禁裸字符串路由）。animated=false：
  // 本宿主有缩略图共享元素绑定，飞行让位不变
  private openViewer(items: AttachmentBrief[], startIndex: number, sharedId: string): void {
    AppStorage.setOrCreate<string>(ATTACH_SHARED_ID_KEY, sharedId);
    openAttachmentViewer(this.pathStack, items, startIndex, false);
  }

  // 错误 notice 跳转（ChatMessageItem.onNoticeAction 上行到本组件实现——ChatPage 剔头越硬线
  // 零改动，本组件自持 pathStack 直推）：'provider' = 密钥失效类 → 服务商管理页、'network' =
  // 传输层失败类 → 网络设置页。pushPathByName 两参无回调直推、param 传 null（无回传语义不挂
  // onPop；现役带回调先例 = 本组件推附件查看器）；未知动作值静默忽略（P2-4 零额外分支）
  private openNoticeTarget(action: string): void {
    if (action === 'provider') {
      this.pathStack.pushPathByName(ROUTE_PROVIDER_PAGE, null);
    } else if (action === 'network') {
      this.pathStack.pushPathByName(ROUTE_NETWORK_PAGE, null);
    }
  }

  // 改参数重发编辑对话框（ChatToolCard.onEditResendTool 上行到本组件闭环——模板行现查
  //（改名改参即时生效）→ 开窗；确认后以收集值走 onResendTool 执行。查无模板 = 已删除，
  // toast 指引不静默（P0-1））
  private openResendEditor(msgId: string, slug: string, argsJson: string): void {
    queryHttpTemplateById(templateIdOfSlug(slug)).then((row: HttpTemplateRow | null): void => {
      if (row === null) {
        this.getUIContext().getPromptAction().showToast({ message: '该请求模板已删除，无法重发' });
        return;
      }
      const params = parseTemplateParams(row.paramsJson);
      if (params.length === 0) {
        return; // 零参数模板不出编辑键（卡侧判据已挡）——防御性静默
      }
      this.resendTarget = { msgId: msgId, slug: slug } as ResendTarget;
      this.resendCtrl = new CustomDialogController({
        systemMaterial: overlayMaterial(),
        builder: TemplateResendDialog({
          title: '修改参数重发',
          templateName: row.name,
          params: params,
          initial: parseResendPrefill(argsJson),
          onConfirm: (values: Record<string, string>): void => {
            if (this.resendTarget !== null) {
              this.onResendTool(this.resendTarget.msgId, this.resendTarget.slug,
                JSON.stringify(values));
            }
          }
        }),
        autoCancel: true,
        alignment: DialogAlignment.Center
      });
      this.resendCtrl.open();
    }).catch((_e: Object): void => {
      this.getUIContext().getPromptAction().showToast({ message: '模板读取失败，请稍后再试' });
    });
  }

  // ── 入口一：消息流附件泡（ChatMessageItem 上行；与 ChatMessageItem 同名契约）──
  onPreviewAttach(msgId: string, briefId: string): void {
    const msg: ChatMessage | null = this.dataSource.findMessage(msgId);
    if (msg === null) {
      // 未命中守卫（P0-1 禁静默吞）：消息在点开前被重载冲掉——理论不可达
      hilog.warn(0xD5A0, 'ChatPageContent', '附件泡点击未命中消息：%{public}s', msgId);
      return;
    }
    const briefs: AttachmentBrief[] = msg.attachBriefs ?? [];
    const hit: AttachmentBrief | undefined =
      briefs.find((b: AttachmentBrief): boolean => b.id === briefId);
    if (hit === undefined) {
      hilog.warn(0xD5A0, 'ChatPageContent', '附件泡点击未命中简报：%{public}s', briefId);
      return;
    }
    if (hit.kind === 'image') {
      // 图片滑切范围 = 当前已加载消息窗口内全部图片简报（按消息时序展开——书 §6-1；
      // 更早未加载的不参与，翻页后可滑到）
      const scope: AttachmentBrief[] = [];
      const all: ChatMessage[] = this.dataSource.allMessages();
      for (const m of all) {
        if (m.kind === 'user' && m.attachBriefs !== undefined) {
          for (const b of m.attachBriefs) {
            if (b.kind === 'image') {
              scope.push(b);
            }
          }
        }
      }
      this.dispatchPreview(hit, scope);
    } else {
      this.dispatchPreview(hit, []);
    }
  }

  // ── 入口二：输入栏附件条（ChatInputBar 上行；待发附件点开预览，拍板 4）──
  private onPreviewAttachment(fileId: string): void {
    const briefs: AttachmentBrief[] = briefsFromPending(this.attachments);
    const hit: AttachmentBrief | undefined =
      briefs.find((b: AttachmentBrief): boolean => b.id === fileId);
    if (hit === undefined) {
      hilog.warn(0xD5A0, 'ChatPageContent', '输入栏附件点击未命中：%{public}s', fileId);
      return;
    }
    // 图片可滑切（待发附件内同 kind 集合）；文本单件；文档走系统预览
    const scope: AttachmentBrief[] = hit.kind === 'image' ?
      briefs.filter((b: AttachmentBrief): boolean => b.kind === 'image') : [];
    this.dispatchPreview(hit, scope);
  }

  // 预览分派单点（两入口共用）：点击前统一文件存在性检查（单次 syscall，非轮询——天然
  // 避 TOCTOU）→ 文档类走系统预览窗（无查看器）→ 图片按 scope 定位进查看器（按 briefId
  // 匹配定下标，禁下标算术）→ 文本单件进查看器
  private dispatchPreview(hit: AttachmentBrief, imageScope: AttachmentBrief[]): void {
    // 键盘态先收键盘（查看器全屏盖住输入区，键盘悬着观感割裂；clearFocus 官方姿势 =
    // TextArea 失焦 → 系统收起输入法——UIContext.d.ts FocusController）
    this.getUIContext().getFocusController().clearFocus();
    if (!fs.accessSync(hit.absPath)) {
      // 「行在文件不在」（拍板语义）：点击时现检 + 中文提示，不做灰态
      this.getUIContext().getPromptAction().showToast({ message: '文件已不在本机' });
      return;
    }
    if (isSystemPreviewKind(hit.name)) {
      // 文档类系统预览：分派共享件（uri 必转 / mimeType 空串 / 1 秒防重入闸 / ctx 判空 /
      // 失败中文 toast 全在件内；附件管理列表页与本组件两消费方共用）
      openSystemPreview(this.getUIContext(), hit.name, hit.absPath);
      return;
    }
    if (hit.kind === 'image') {
      const idx: number =
        imageScope.findIndex((b: AttachmentBrief): boolean => b.id === hit.id);
      if (idx < 0) {
        hilog.warn(0xD5A0, 'ChatPageContent', '图片滑切集合未命中点击件：%{public}s', hit.id);
        return;
      }
      this.openViewer(imageScope, idx, hit.id);
    } else {
      // 文本模式键写空串（统一「每次打开必写键」不变量：清掉上一轮图片预览遗留的绑定，空串
      // = 官方「清除绑定」语义——防御性不变量保留，不承担跨页自愈职责）
      this.openViewer([hit], 0, '');
    }
  }

  // ── 消息全文面板 ──
  // 长按解析开面板（ChatMessageItem.onCopyText 上行）：findMessage 解析 + 两守卫（流式生成中
  // 不弹〔判据同 ChatMessageItem 主守卫〕+ 空文本无可复制——主守卫在
  // ChatMessageItem.requestCopySheet，此处兜第二道）。快照语义：开面板一刻拷 text，流式增量
  // 不跟进（MessageCopySheet 头注释）
  private openMsgCopySheet(msgId: string): void {
    const msg: ChatMessage | null = this.dataSource.findMessage(msgId);
    if (msg === null || msg.streaming === true || msg.text === '') {
      hilog.warn(0xD5A0, 'ChatPageContent', '长按复制未命中消息或无文本：%{public}s', msgId);
      return;
    }
    // 内容形态与正文快照进待开载荷（applyOpen 才安装——关闭动画中不切换已显示树）
    this.pendingKind = 'copy';
    this.pendingCopyText = msg.text;
    this.pendingCopyAssistant = msg.kind === 'assistant';
    this.requestOpen();
  }

  // 引用挂载（MessageCopySheet.onQuote 上行——「引用」菜单项动作）：入口截断单源
  // clampQuoteText（超 8000 字符截断 + Toast 显式呈报，上限常量单源 QuoteCompose.
  // QUOTE_MAX_CHARS）；Toast 走 UIContext 形态。面板关闭由调用处 onQuote 闭包随行（引用
  // 动作即完成动作，面板让位给输入侧引用条）
  private acceptQuote(sel: string): void {
    // 纯空白守卫：选区 trim 后为空 = 无可引用内容，静默拦截不挂条不 Toast（菜单项点了没
    // 反应可接受，最克制；面板关闭由调用处 onQuote 闭包随行，不受本守卫影响）。
    if (sel.trim() === '') {
      return;
    }
    const clamped: string = clampQuoteText(sel);
    if (clamped !== sel) {
      this.getUIContext().getPromptAction().showToast({ message: '引用内容过长，已截断' });
    }
    this.pendingQuote = clamped;
  }

  // 面板内容分派（坑51 红线：bindSheet builder 位挂组件内 @Builder 方法）：kind=copy 实例化
  // 既有消息全文面板；kind=answers 实例化其他回答面板——同一挂载点、同一关闭协调
  @Builder
  CopySheetBuilder() {
    if (this.contentSheetKind === 'answers') {
      ChatAnswerSheet({
        view: $answerView,
        onChoose: (answerNodeId: string): void => {
          this.answerCtrl?.choose(answerNodeId);
        },
        onRetry: (): void => {
          this.answerCtrl?.reloadChoices();
        },
        // 删除此版本上行（2026-10-25 分支语义收敛笔；二次确认在面板件内完成）
        onDeleteAnswer: (answerNodeId: string): void => {
          this.answerCtrl?.deleteAnswer(answerNodeId);
        },
        onClose: (): void => {
          this.requestClose();
        },
        bottomInset: this.bottomPad
      })
    } else {
      MessageCopySheet({
        text: this.copySheetText,
        fromAssistant: this.copySheetFromAssistant,
        onClose: (): void => {
          this.requestClose();
        },
        // 引用上行（2026-10-21 引用功能笔）：挂待发引用后走既有关闭链让位输入侧引用条
        //（requestClose 单入口——本回调属用户完成动作，非程序化关闭旁路）
        onQuote: (sel: string): void => {
          this.acceptQuote(sel);
          this.requestClose();
        },
        bottomInset: this.bottomPad
      })
    }
  }

  // ── 回答面板接线（本组件只剩面板宿主侧两件：answerView / CopySheetBuilder 的 answers 形态）──

  // ── 关闭-再开协调（机制说明见字段注释；与会话轨迹页/请求日志页同配方）──
  // 开意图落定 → 动效在途挂起 / 否则即开（applyOpen 单入口，补开两路共用；内容快照与形态
  // 已在各入口落定待开载荷，补开只进可见性与形态安装）
  private requestOpen(): void {
    this.pendingOpen = true;
    if (this.sheetClosing) {
      return; // 动效在途：待补开
    }
    if (this.copySheetShow && this.pendingKind !== this.contentSheetKind) {
      // 面板在显示而新载荷要换内容形态：内部收起（只改关闭态、不经用户取消入口——
      // 不清刚登记的开意图），离场动效结束后由 onSheetGone → applyOpen 安装新载荷
      this.sheetClosing = true;
      this.copySheetShow = false;
      return;
    }
    this.applyOpen();
  }

  private applyOpen(): void {
    if (!this.pendingOpen) {
      return;
    }
    this.contentSheetKind = this.pendingKind;
    if (this.pendingKind === 'copy') {
      this.copySheetText = this.pendingCopyText;
      this.copySheetFromAssistant = this.pendingCopyAssistant;
    }
    this.copySheetShow = true;
  }

  // 离场动效结束（sheetPanelOptions 第四参——d.ts：动画结束后回调）：清在途位 + 按开意图补开
  private onSheetGone(): void {
    this.sheetClosing = false;
    if (!this.copySheetShow) {
      this.applyOpen();
    }
  }

  // 可见性变化兜底（@Watch）：框架 `$$` 收尾回写把可见性压回 false 时按开意图补一次；
  // 用户关闭必经 requestClose（先清开意图再写 false），不会误触本支
  private onSheetVisibleChanged(): void {
    if (!this.copySheetShow) {
      this.applyOpen();
    }
  }

  // 关闭单入口（xmark / 手势两路同调）：先作废回答在途查询 + 清开意图 + 置离场动效在途位，
  // 再写可见性（任务书 §5.5：序不可倒置——先写 false 会让兜底补开误触）
  private requestClose(): void {
    const ctrl: ChatAnswerCtrl | null = this.answerCtrl;
    if (ctrl !== null) {
      ctrl.cancelView();
    }
    this.pendingOpen = false;
    this.sheetClosing = true;
    this.copySheetShow = false;
  }

  // 推荐问题广播消费（@Watch onSuggestPayload）：载荷解析 → 按 msgId 命中本页消息（全局
  // 唯一 id——他会话广播天然无命中）→ 原地挂/清 suggestions 字段。写回广播 items 非空 =
  // 挂载；发送清空广播 msgId='' 无命中即结束（UI 收起由 busy 隐藏 + tail 清空两道既有结构
  // 承载，内存字段随该消息失去 tail 后不再可见）
  private onSuggestPayload(): void {
    const payload: SuggestPayload | null = parseSuggestPayload(this.suggestPayload);
    if (payload === null || payload.msgId === '') {
      return;
    }
    const msg: ChatMessage | null = this.dataSource.findMessage(payload.msgId);
    if (msg === null || msg.kind !== 'assistant') {
      return;
    }
    msg.suggestions = payload.items.length > 0 ? payload.items : undefined;
  }

  // 版本步进重算 tick 消费（★ 2026-10-25 rik 形态统一笔）：轮落库回填后全表重算——
  // 重算编排在 answerCtrl（图快照 + 逐轮归组 + 值同不写），本组件只做订阅转发
  private onAnswerVersionsDirty(): void {
    this.answerCtrl?.recomputeRowVersions();
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // ── ① 消息流层（完整正文在真实阅读视口内原生滚动）──
      // ★ List 常驻挂载（坑63）：空态/错误态是覆盖层而非互斥分支，Scroller 全程绑定。
      // ★ **每行自持上距**模型：space 恒 0，行间距全部由各展示项自己的上距承担
      //（`.margin({ top: CARD_SPACING })`，各分支落点见 ChatMessageItem / ChatProcessSegment；
      // 过程段与正文各自独立恒 CARD_SPACING，无链内贴合例外）。纪律：新行型落 ListItem
      // 必须自带上距（漏挂 = 与前一行贴合出零间距）。
      List({ space: 0, scroller: this.listScroller }) {
        // ── 触顶翻页头部提示行（LazyForEach 之前 = 列表头部；两态 UI 件 = ChatOlderRow，
        //    此处只判挂载：加载中 / 已到顶（到底 + 触达过顶部 + 有消息——短会话预判到底但
        //    行等首次触达再亮，不进页常驻）──
        if (this.dataSource.olderLoading ||
          (this.dataSource.olderExhausted && this.dataSource.olderAttempted &&
            this.dataSource.messageCount > 0)) {
          ListItem() {
            ChatOlderRow({
              loading: this.dataSource.olderLoading,
              exhausted: this.dataSource.olderExhausted
            })
          }
        }
        LazyForEach(this.dataSource, (item: ChatDisplayItem) => {
          ListItem() {
            // ★ 列表项 = **展示项**：过程段（思考/工具/收束后中间正文步骤）走段容器，图表与清单卡独立分流，其余消息走单条渲染件
            if (item.kind === DISPLAY_KIND_SEGMENT) {
              ChatProcessSegment({
                item: item,
                // 展示意愿变更前置：先解进页校正，再起局部钉顶（被点行上沿不动）
                onPresentationChange: (msgId: string): void => {
                  this.followCtrl.cancelAlign();
                  this.applyRowPin(this.dataSource.listIndexForMessage(msgId));
                },
                onAskSubmit: (callId: string, answerJson: string): void => {
                  this.onAskSubmit(callId, answerJson);
                },
                onBrowseConfirm: (callId: string, approved: boolean): void => {
                  this.onBrowseConfirm(callId, approved);
                },
                onAwaitingStep: (msg: ChatMessage): void => {
                  this.claimAskDock(msg);
                },
                onResendTool: (msgId: string, toolName: string, argsJson: string): void => {
                  this.onResendTool(msgId, toolName, argsJson);
                },
                onEditResendTool: (msgId: string, toolName: string, argsJson: string): void => {
                  this.openResendEditor(msgId, toolName, argsJson);
                },
                onMarkdownAnchor: (id: string): void => {
                  this.scrollToMarkdownAnchor(id);
                },
                onCopyText: (msgId: string): void => {
                  this.openMsgCopySheet(msgId);
                }
              })
            } else if (item.kind === DISPLAY_KIND_CHART) {
              // 正文图表行：卡体壳与图表卡挂载全在 ChatChartRow（本组件只分派，见该件注释）
              ChatChartRow({ item: item })
            } else if (item.kind === DISPLAY_KIND_FILE_CHANGES) {
              ChatFileChangesCard({ item: item, onOpenDetail: this.onOpenFileDetail })
            } else if (item.msg !== null) {
              ChatMessageItem({
                msg: item.msg,
                bubbleVisible: this.bubbleVisible,
                onMarkdownAnchor: (id: string): void => {
                  this.scrollToMarkdownAnchor(id);
                },
                onPresentationChange: (msgId: string): void => { // 来源卡开合钉顶，同段容器口
                  this.followCtrl.cancelAlign();
                  this.applyRowPin(this.dataSource.listIndexForMessage(msgId));
                },
                // 长消息展开 = 阅读动作：停跟随、冻结底锚、滚到视口顶；正文在占位层背后分帧建块后一次显现
                onLongMessageExpand: (msgId: string): void => {
                  this.followCtrl.onUserScrollUp();
                  this.longReveal.hold();
                  const displayIndex: number = this.dataSource.displayIndexOfMessage(msgId);
                  if (displayIndex >= 0) {
                    this.listScroller.scrollToIndex(this.dataSource.listIndexForDisplay(displayIndex), true,
                      ScrollAlign.START);
                  }
                },
                onRetryMsg: (msgId: string): void => {
                  this.onRetryMsg(msgId);
                },
                // 回答版本步进：箭头切版本 / 计数位开面板
                onAnswerStep: (msgId: string, direction: number): void => {
                  this.onAnswerStep(msgId, direction);
                },
                onAnswerPanel: (msgId: string): void => {
                  this.onAnswerPanel(msgId);
                },
                onQuestionStep: (msgId: string, direction: number): void => {
                  this.onQuestionStep(msgId, direction);
                },
                onMoreMenu: (msgId: string): void => {
                  this.onMoreMenu(msgId);
                },
                  // 摘要提示行点击开上下文用量面板（三级同名链：prop → 本组件 → ChatPage 注入）
                  onOpenUsage: (): void => {
                    this.onOpenUsage();
                  },
                  // 错误 notice 跳转：链头在本组件闭环 openNoticeTarget，不走 ChatPage（行数预算同 copySheet）
                  onNoticeAction: (action: string): void => {
                    this.openNoticeTarget(action);
                  },
                  // 附件泡点击派发（三级同名链：prop → 本组件 → 分派单点 dispatchPreview）
                  onPreviewAttach: (msgId: string, briefId: string): void => {
                    this.onPreviewAttach(msgId, briefId);
                  },
                  // 长按气泡开消息全文面板（本组件闭环 openMsgCopySheet，不走 ChatPage；段内中间正文同口）
                  onCopyText: (msgId: string): void => {
                    this.openMsgCopySheet(msgId);
                  },
                  // 推荐问题 chip 点击：建议点按恒填入输入框——偏好键已退役、行为固化为不可关闭，
                  // 不再存在「直接发送」分支；输入栏覆盖草稿并聚焦后由用户发出，ChatPage 硬线零改动
                  onSuggestTap: (text: string): void => {
                    this.suggestFillDraft = text;
                    this.suggestFillCmd++;
                  }
                })
            }
          }
          // 项级实测上报：展示项高度变化喂 followCtrl（0.5vp 去抖在其内部）——末条原地长高时
          // onScrollIndex 无回调，本通道是进页校正链的精确触发源；身份键 = 展示项 key
          .onAreaChange((oldArea: Area, newArea: Area) => {
            // 布局诊断日志（构建期开关，交付恒关——Theme.ets CHAT_LAYOUT_DEBUG）：逐项实测
            // 行高，与各行根容器描边配合定位「板块间空白」
            if (CHAT_LAYOUT_DEBUG) {
              hilog.info(0xD5A0, 'ChatLayoutDebug', 'row kind=%{public}s h=%{public}f id=%{public}s',
                item.kind, newArea.height as number, item.key);
            }
            // ★ 占位揭示期静默：用户点「展开全文」或滚动中挂载的长正文，占位构建期行高会连续
            // 增长——展开是阅读动作，不能让行高回报把视口拽到底部或把锚态升格翻成底锚。揭示
            // 完成由正文链回调清位后恢复正常回报（组件回收也会清，无残留）
            const revealing: boolean = item.msg !== null && item.msg !== undefined &&
              item.msg.bodyPlaceholder === true;
            if (!revealing) {
              this.followCtrl.onItemAreaChange(item.key, newArea.height as number, oldArea.height as number);
              // U4：行实测喂判定器 + 同回调重评（crossing 挂点 = 触发改拍的同一行高回调）；
              // ★ F2 红线：跨幅升格只认「高度真变化」——纯位置变化（键盘压缩/回落帧的行位移
              // 回报）不计（见 reevaluateAnchor 注释）
              this.anchorJudge.onRowHeight(item.key, newArea.height as number);
              this.reevaluateAnchor((newArea.height as number) !== (oldArea.height as number));
            }
          })
        // 正文键含显式绑定（换源释放旧渲染器、帧增长不换键）；过程段键保持 item.key 原语义，正文修订不扩散为列表重建
        }, (item: ChatDisplayItem) => markdownDisplayItemKey(item))
      }
      .id(this.markdownViewportId)
      // 进场渐显：内容就绪（首屏就绪信号或已有消息）且页面已显示（shellArrived——错峰同帧：
      // 与壁纸渐显同经页面壳 onShown 链同回调栈起播：就绪早于显示 = 同帧，就绪晚 = 就绪即播
      // 后于壁纸）前消息区零渲染位、就绪后 300ms 渐显；纯渲染位不碰布局/滚动/命中；pop 返回/
      // 生成中重进（shellArrived 保持 true）直显不重播。判据纯响应式三条件防悬挂卡隐、不挂
      // 换源/重试事件（挂事件 = 中途换源闪透）；★ animation 紧随 opacity 且先于
      // contentStartOffset 等状态驱动属性——只辖 opacity，底带逐帧跟随零动画污染（键盘域红线）
      .opacity(this.dataSource.shellArrived && (this.dataSource.entryFirstScreenReady || this.dataSource.messageCount > 0) ? 1 : 0)
      .animation({ duration: 300, curve: Curve.EaseOut })
      .width('100%')
      // List 恒全高：不裁 List 高度——阅读线只由 contentEndOffset 与跟随 endInset 表达
      //（视口裁剪形态退役：直角切线/滑不到底/不透出渐隐同源根因）
      .height('100%')
      .layoutGravity(LocalizedAlignment.TOP_START)
      .onAreaChange((_oldArea: Area, newArea: Area): void => {
        this.listViewportHeight = newArea.height as number;
        this.followCtrl.onContentShift();
        // U4：视口/键盘变化重评（非增长事件——只喂条数闸快路，跨幅升格要行高真变化）
        this.reevaluateAnchor();
      })
      // 列表顶对齐红线（Scroll/List 通用属性 align 默认 Center，短列表会居中——坑18 同族）
      .align(Alignment.TopStart)
      .padding({ left: 12, right: 12 })
      // 顶部/底部留白 = 官方内容起始/结束偏移（随滚动滚走，消息滑入顶部蒙层透出；勿改
      // padding——padding 是固定视口内缩，语义见头注释①）。顶留白吃 contentTopPad()——排队
      // 入口条在场时让出带高 + 间距，隐藏时归 topPad
      .contentStartOffset(this.contentTopPad())
      // 底带 = 宿主高 − 阅读高 + 呼吸量，与跟随 endInset 同挂 readingBand 同帧同值（恒等
      // 不变式）：末条静止位 = 输入栏胶囊上沿上方 CHAT_TAIL_BREATH（任何形态含展开态）；
      // 键盘/多行/展开/收起一律实测逐帧跟随（★ 禁再上冻结/钳位/展开期扣减项，勿回填）
      .contentEndOffset(this.readingBand)
      // 边缘回弹官方默认（撤 alwaysEnabled）：不满一屏期回到官方默认「无回弹且不可滚」
      //（list.d.ts:1018-1028、FAQ 443），S4 的不满屏回弹 + 拖拽冻结从根消失（无 DRAG 事件 →
      // 无 >2vp travel → follow 不退 → 内容持续揭示，stackFromEnd 底锚继续吸收增长）；满屏期
      // 照常滚动+回弹。坑76 引入动机（短内容可拖可弹防死列表）在本列表倒退一处，全仓其余
      // ~110 处同款惯例不动；真机不满意单独回退本笔即恢复
      .edgeEffect(EdgeEffect.Spring)
      // 预创建行数三档窗口：进页首帧 = 0（不预建屏外行），揭示在途期 = 1，稳态 = 5（快滑
      // 预建收益保留；机制见 ChatLongReveal）
      .cachedCount(this.listCachedCount)
      // 底锚双态：开 = 布局从底端起算（官方聊天列表范式 stackFromEnd，API 19+，FAQ 1519），
      // 贴底交给布局、补偿链短路（模式位与本式同源喂入——stackAnchored() 单源：aboutToAppear
      // 初值 / reevaluateAnchor 每拍 / 冻结与钉顶变化）；关 = 补偿链武装，判据迟到窗由弹簧链
      // 兜住。总开关 false 恒旁路 = 旧路径
      .stackFromEnd(this.stackAnchored())
      // 触顶触发翻页（防抖守卫在 ChatOlderCtrl——加载中闸/到底停）
      .onReachStart(() => {
        this.olderCtrl.tryLoadOlder();
      })
      // 第一个可见项下标跟踪（翻页锚点记录用）+ 末个可见项下标喂 followCtrl 进页定位校正链
      //（rebuild 同帧 scrollToIndex 估算落点偏上的逼近校正，事件驱动零定时器，详见
      // ChatFollowController.onScrollIndex）。★ 不在此判在底——end 语义是「末项进入可视区」
      // 非真正滚到底，缓存只会记住误判；同回调仍喂 olderCtrl 锚点
      .onScrollIndex((first: number, end: number) => {
        this.olderCtrl.onScrollIndex(first);
        this.followCtrl.onScrollIndex(end);
      })
      .onReachEnd(() => {
        this.followCtrl.onReachEnd();
        // 用户回到底部 = 阅读动作结束：解除展开阅读期冻结与局部钉顶，恢复贴底（清位三路 =
        // 回底 / 发送 / 换源身份失效）
        this.longReveal.release();
        this.applyRowPin(-1);
      })
      .onWillScroll((offset: number, state: ScrollState, source: ScrollSource): ScrollResult => {
        if (source === ScrollSource.DRAG && offset > 0) { this.olderCtrl.cancelAnchor(); }
        return this.followCtrl.onWillScroll(offset, state, source);
      })
      .onDidScroll((offset: number, state: ScrollState): void => {
        this.followCtrl.onDidScroll(offset, state);
      })
      .onDidStopDragging((willFling: boolean): void => {
        this.followCtrl.onDidStopDragging(willFling);
      })
      .onDidStopFling((): void => {
        this.followCtrl.onDidStopFling();
      })
      // 滚动暂停揭示：滚动期间全局揭示调度器停派发——建块成本不与滚动争帧，滚动中挂载的
      // 长行先出骨架；停止后 resume 续跑（kill switch 在
      // MarkdownDocumentView.MARKDOWN_REVEAL_PAUSE_ON_SCROLL_ENABLED）
      .onScrollStart((): void => {
        this.longReveal.onScrollStart();
      })
      .onScrollStop((): void => {
        this.longReveal.onScrollStop();
        this.followCtrl.onUserScrollStop();
        this.reevaluateAnchor(); // U4：终停 = U1 释放点重评（守卫期推迟的释放后续上）
      })
      // 子控件横滚不产生List纵向意图；触摸只暂停程序任务，末指离屏才释放触摸闸。
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down && event.touches.length > 0) {
          this.followCtrl.onListTouchStart();
        } else if (event.type === TouchType.Cancel ||
          (event.type === TouchType.Up && event.touches.every((point: TouchObject): boolean =>
            event.changedTouches.some((changed: TouchObject): boolean => changed.id === point.id)))) {
          this.followCtrl.onListTouchEnd(event.type === TouchType.Cancel);
        }
      })
      .scrollBar(BarState.Off)

      // ── ①b 空态/错误态/受限态覆盖层（仅无消息时显示，盖住空 List；三态互斥判据与视觉
      //    在 ChatPageEmptyLayer）──
      ChatPageEmptyLayer({
        dataSource: this.dataSource,
        errorText: this.errorText,
        // 空态层不参与排队让位：排队非空 ⇒ 已有发送 ⇒ messageCount > 0 ⇒ 本层隐藏，共存不可达
        topPad: this.topPad,
        onRetry: this.onRetry
      })

      // ── 加载蒙层（进会话历史加载期间的淡蒙层 + 加载动画）：形制与双时间参数（最短延迟
      //    出现防快加载/转场闪现 + 最短显示时间防亮起即灭）单源在独立件 ChatLoadingOverlay
      //（拆域笔：蒙层整域内联会越 1200 硬线，按宪法硬线条款先拆独立文件）。空闲 = 空 Stack
      //    零尺寸零命中；覆盖层序 = ①b 三分支之上——加载完成的快场景短暂压住空态引导层后
      //    渐隐露出 ──
      ChatLoadingOverlay({
        dataSource: this.dataSource,
        // 进页装载起手批次号（2026-11-17 加载相锚点后移笔）：build 期读 @Track 传 @Prop——
        // 自增驱动蒙层起拍；判据门控在 ChatLoadingOverlay.loadingPhase（0 = DB 等待期不亮）
        entryLoadEpoch: this.dataSource.entryLoadEpoch,
        errorText: this.errorText
      })

      // ── ①b 底部渐变蒙层已取消（2026-10-24 决明拍板「取消输入框附近的灰白蒙层」）：撤销后
      //    消息滑入输入区由胶囊官方实底（ChatInputBar）直接遮挡，无渐隐；历史实验结论留档
      //    备查，勿无拍板回填 ──

      // ── ② 「更多」菜单隐形锚点层（openMenu TargetInfo；几何常量与 LogPageContent 同源）──
      // 全高层 + HitTestMode.None：自身与子孙都不参与命中测试，触摸穿透到下层消息列表；
      // 内层 Top 对齐 Stack 复刻 LogPageContent 锚点定位（其外层 Stack 是顶对齐，本层是底对齐）
      Stack({ alignContent: Alignment.Top }) {
        Row() {
          Blank()
          Column()
            .width(1)
            .height(1)
            .id(CHAT_MORE_MENU_ANCHOR_ID)
        }
        .width('100%')
        .padding({ right: MORE_MENU_ANCHOR_RIGHT })
        // 锚点顶 = 「更多」按钮下沿（勿写成标题栏下沿，差 8vp 菜单偏低——LogPageContent
        // 踩坑①）
        .margin({ top: Math.max(this.contentTopPad() - TITLE_BAR_MASK_EXTRA_HEIGHT - MORE_MENU_BUTTON_BOTTOM_INSET, 0) })
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)

      // ── ③ 底部浮层：输入栏（容器全透明，材质在 ChatInputBar 内部） ──
      Column() {
        ChatInputBar({
          // 流式态 @Link 二级链（链第 2→3 层，同 thinkingHold）
          busy: $busy,
          dbReady: this.dbReady,
          bottomPad: this.bottomPad,
          attachments: this.attachments,
          thinkingValue: $thinkingValue,
          modelLabel: $modelLabel,
          // 上下文用量圆环：值 @Link 下发 + 点击上行（链第 2→3 层）
          ctxRingPct: $ctxRingPct,
          onOpenContext: this.onOpenContext,
          onReadingTop: (top: number): void => {
            // 隐藏期禁上报：Visibility.None 后 onAreaChange 可能报 0/旧值，会把底带塌到 0
            if (this.dockVisible) { return; }
            this.readingViewport.input(top);
            this.scheduleReadingViewport();
          },
          // 输入交互期暂停跟随链拽底（贴顶态防拽、读历史不被拖）；★ 底带几何一律实测即时
          //（见 scheduleReadingViewport 底带单源），展开/收起同键盘/多行逐帧跟随
          onExpandState: (expanded: boolean): void => {
            this.followCtrl.setHold(expanded);
            this.scheduleReadingViewport();
          },
          onPickThinking: this.onPickThinking,
          thinkingHold: $thinkingHold,
          // 单条消息指定技能（id+名双链：id 喂状态裸图标键换色判据、名喂技能条显示——链第
          // 2→3 层）+ 技能条 × 键上行取消指定 + 状态键点击上行（开会话状态半模态）
          designatedSkillId: $designatedSkillId,
          designatedSkillName: $designatedSkillName,
          onRemoveSkillDesignate: this.onRemoveSkillDesignate,
          onOpenStatus: this.onOpenStatus,
          // 待发引用：值 @Link 下行 + × 键上行清空（链第 2→3 层）
          quoteText: $pendingQuote,
          onDismissQuote: (): void => {
            this.pendingQuote = null;
          },
          // 发送 = 阅读动作结束：先解展开阅读期底锚冻结再走上行（与推荐语直发共用
          // sendWithHoldRelease 单口）
          onSend: (text: string, attachments: PendingAttachment[]): boolean =>
            this.sendWithHoldRelease(text, attachments),
          onAbort: this.onAbort,
          onAddFile: this.onAddFile,
          onRemoveAttachment: this.onRemoveAttachment,
          // 长文本粘贴转附件：原样透传（收口闭包由 ChatInputBar 自持，本组件与页面都不
          // reinterpret 它）
          onPasteLongText: this.onPasteLongText,
          // 已选未发附件点开预览（同域同形入口，同一查看器/系统预览分派复用）
          onPreviewAttachment: (fileId: string): void => {
            this.onPreviewAttachment(fileId);
          },
          fullInputDraft: this.fullInputDraft,
          fullInputCmd: this.fullInputCmd,
          // 推荐语回填命令：tick + 文本下行（本组件 @State → 直接子组件 @Prop 常规父子绑定
          // 随本组件刷新；命令由本组件 chip 分支发出，见 suggestFillDraft 字段注释）
          suggestFillDraft: this.suggestFillDraft,
          suggestFillCmd: this.suggestFillCmd,
          onFullscreen: this.onFullscreen,
          onDraftTextChange: this.onDraftTextChange
        })
      }
      .width('100%')
      // 输入位接管期隐藏而不卸载：ChatInputBar 持 TextArea / 展开态 / 附件条 / 键盘模式 /
      // 草稿焦点一整套局部状态，条件渲染会让每次作答后重挂（展开态与焦点必丢）
      .visibility(this.dockVisible ? Visibility.None : Visibility.Visible)
      // ★ 决明拍板「改回去，不让渡」：bottomPad−8 的避让让渡已撤销（恢复全量避让——全屏下
      // 输入栏不压手势条；让渡版经真机确认有贴手势条风险后弃用）。底部留白移交 ChatInputBar：
      // 键盘态需置 0（键盘已盖住底部系统区），而键盘状态只有该组件持有——本层只透传
      // bottomPad，不再自挂 padding（胶囊实测上沿已包含该留白的布局影响）

      // ── ③b 输入位托管：等待用户拍板的提问卡/确认卡接管底部输入位（细条 ⇄ 面板两态自持） ──
      if (this.dockVisible && this.dockMsg !== null) {
        ChatAskDock({
          msg: this.dockMsg as ChatMessage,
          dockKey: (this.dockMsg as ChatMessage).id,
          bottomPad: this.bottomPad,
          onAskSubmit: this.onAskSubmit,
          onBrowseConfirm: this.onBrowseConfirm,
          onDismiss: (): void => {
            this.dismissAskDock();
          },
          onReadingTop: (top: number): void => {
            this.readingViewport.input(top);
            this.scheduleReadingViewport();
          }
        })
      }

      // ── ④ 附件查看器 = 导航栈内二级页 pushPathByName（页面 = AttachmentViewerPage），本层
      //    不再挂任何弹层/模态——文档类不进查看器，分派点直走系统预览窗 ──

      // ── ★ ⑤ mermaid 内联渲染宿主：整页唯一 1×1 隐藏 Web，由服务信号按需挂/拆（空闲
      //    60 秒或页面离场拆除）。**必须挂 Stack 顶层**：ArkWeb 对被内容遮挡的 Web 会判定
      //    不可见并节流渲染管线，异步位图解码回调随之永不触发（真机实测：压在消息流下层时
      //    <img> 既不 onload 也不 onerror，图恒不出）。1×1 + 0.01 透明不遮挡阅读，
      //    hitTestBehavior None 让点击穿透。实现在 markdown/MermaidRenderHost.ets，本页只做
      //    挂载接线 ──
      MermaidRenderHost()
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.readingViewport.host(newArea.globalPosition.y as number, newArea.height as number);
      this.scheduleReadingViewport();
    })
    // ── 消息全文半模态：分支根挂点（规范-半模态 §1 判据三条全过，见 copySheetShow 字段
    // 注释）；[MEDIUM, LARGE] 半屏起双停靠 = §4 选型表「信息查看类」档位。关闭链：可见性
    // `$$` 双向 + onWillDismiss 内 action.dismiss() 放行（官方契约）；本面板零暂存吃缺省
    // 口径（下拉直达关闭、不回弹）；关闭走 requestClose 单入口 + 第四参 onDisappear 补开
    //（关闭-再开协调，见字段注释）──
    .bindSheet($$this.copySheetShow, this.CopySheetBuilder(), sheetPanelOptions(
      (action: DismissSheetAction): void => {
        action.dismiss();
        this.requestClose();
      },
      [SheetSize.MEDIUM, SheetSize.LARGE], undefined,
      (): void => {
        this.onSheetGone();
      }))
  }
}

// ═══ 失败轮重试动作行（kind='retry'）已随 rik 形态统一笔整链退役（防回游）：该 kind 全仓
// 无产生方，专属渲染件、视图模型接口、失败轮重试上行链与占位文案常量同批删除；失败轮恢复
// 入口 = 空正文状态行「重试」键与操作栏重试图标键（单链上行 → retryAt）。
