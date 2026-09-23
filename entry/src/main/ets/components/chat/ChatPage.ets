// 聊天页装配（2026-08-29 M1 建页；同日 UI 对齐换装——内容区 ChatPageContent / 发送
// ChatSendCtrl / 加载刷新 ChatPageLoad / 附件 AttachmentPickCtrl，本页留 @State/壳/面板开关）：
// · 壳（任务 4 拍板）：自包 PageShell（标题栏覆盖层/标题栏菜单/半模态 bindSheet 须页面自持
//   ——PageMap 壳无法回传；转场透明坑38 由 PageShell 体系接管）；PageMapBuilder 薄构造。
// · 标题栏：HDS 路径 = 返回键右侧「模型」胶囊 + 右上角合并胶囊【＋ 新建会话｜⋯ 更多】
//   （两件都在覆盖层 TitleBarContent，各占一个热区）；回退路径 = 官方菜单三键（新建会话/
//   模型/更多，无 stackBuilder 机制画不了胶囊）。
//   ★ 2026-09-09 二百二十七（决明「加号与更多合并成一个胶囊，左侧加号右侧更多，各有热区」）：
//   右上角原官方菜单数组双键退役——官方 menu 数组每项只渲染一个独立圆钮、无自定义 builder
//   位（d.ts 实查），合并只能自绘于官方标题栏自定义区（stackBuilder）；两热区各自 onClick，
//   功能与图标不变。
//   ★ 2026-09-09 决明指令「取消会话内显示标题」——本页不再显示会话标题（标题生成链与
//   历史列表显示不变，仅取消会话内展示）；同日模型入口两次换位（标题栏模型名点击 →
//   三键中键〔一百八十二〕→ 返回键右侧「模型」胶囊〔二百一十六〕）。
//   「新建会话」= 本地生成会话 id + replacePath 跳转（坑57 同分支复用防；懒创建：首条消息
//   发送时才落会话行——2026-09-01 会话绑定：落行写入归属助手 = ChatPromptState 有效绑定）；
//   「更多」= openMenu。
// · 全屏输入（dshinhm 二一一改语义）：KimiFullInputSheet 半模态挂页面根 bindSheet（坑64
//   姿势）；init/draft/cmd/live 四通道见各字段注释。
// · 收发链路（M1 回归红线）：发送/停止经 ChatSendCtrl 薄委托；页面销毁 disposeSilent。
// · 附件（2026-08-31 接线；★ 2026-09-09 附件落盘第一轮）：+ 键开「附件与提示词」半模态
//   （ChatPromptSheet）→ AttachmentPickCtrl（选择器→沙箱→入列，目录按 isPrivate 分流
//   filesDir 常驻 / cacheDir 临时）；发送随文本交 ChatSendCtrl（载荷成功文件一律留盘 +
//   元数据落库 + 简报装配，仅载荷失败即删——条件清理在 ChatSendCtrl.dispatchSend）；页面
//   销毁清删未发送附件（cleanupAttachments，不驻留）。★ 2026-09-15 预览笔：附件独立
//   气泡与查看器状态在 ChatPageContent（坑16 正解）；★ 同日预览升级笔：查看器改全屏模态
//   （bindContentCover 挂 ChatPageContent 根 Stack），系统返回键由模态 onWillDismiss 承接
//   （原 PageShell.onBackPressed 拦截链退役——查看器不再占用页面级返回键通道）；★ 同日
//   二级页化笔再改：查看器承载全量移出本域（导航栈内二级页，页面 =
//   components/chat/AttachmentViewerPage.ets），本页只把 pathStack 注入 ChatPageContent
//   （开页用），模态与查看器状态均已删净。
// · 提示语义：加载失败 → errorText 覆盖层（含重试）；动作错误 → toast；流式 → notice 条。
// · 隐私会话（2026-09-04，更多菜单「隐私会话」进入）：isPrivate 模式——标题栏常显标记
//   「隐私会话」+ 进页一次性提示；纯内存会话零落库（发送链写库点旁路 = ChatSendCtrl
//   privateMode 守卫，本页做入口/提示/离页即焚）；★ 同日开放附件与提示词选择（决明指令
//   「开放提示词选择与附件上传发送，保持退出后完全删除」）：附件走三防线（★ 2026-09-15
//   预览笔改口径：发送不再即删——留盘供会话内预览；离页整目录清扫 sweepAttachDir +
//   未发送附件 cleanupAttachments + 启动 sweepAttachDir 兜底），提示词与助手选择走无行
//   内存覆盖
//   （ChatPromptState.promptOverride/boundOverride，零写库）；路由链 activePrivate 见
//   HomeNavigation 注释
// ★ 2026-09-01 反碎片并回：ChatTitleOverlay.ets（标题栏覆盖层）+ ChatTitleMenu.ets（标题
// 栏菜单工厂）并入——两件均本页单消费方、同域「聊天页标题栏装配」，原拆分动因 =
// 行数搬运，宪法修订（600 软引导 / 1000 硬线 + 反碎片下限）后复归。
// ★ 2026-09-09 决明指令「取消会话内显示标题链路，不留死代码」：原 ChatTitleOverlay 组件
// （会话标题单行显示 + 隐私标记）随标题显示一并退役；标题生成链（TitleGen）与历史列表
// （ChatSessionList）显示零改动。★ 同日模型入口再换位：三键中键 → 返回键右侧「模型」胶囊
// （@Builder TitleBarContent，二百一十六）——标题栏只剩双键菜单 + 覆盖层胶囊/隐私标记。
// ★ 同日二百二十七：右上角双键（官方菜单数组）合并为覆盖层内的一个胶囊两热区，HDS 菜单
// 数组退役（键件 = 共用件 TitleBarKeys.TitleBarActionCapsule，2026-09-11 迁移）；回退路径菜单三键照旧。
import { UIContext, uiMaterial, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AiConnection, PendingAttachment, THINKING_OPTIONS, connectionOffEnabled, legalThinkingTier } from '../../common/providers/AiTypes';
import { DEFAULT_CONVERSATION_ID, nextMessageId, whenReady } from '../../common/store/ChatDb';
import {
  ConversationOverride, queryConversationOverride, updateConversationModelOverride,
  updateConversationWebSearchOverride
} from '../../common/store/ChatDb';
import { CONN_RESOLVE_TICK_KEY, ActiveConnectionInfo } from '../../common/store/ProviderDb';
import { isKeepScreenOnEnabled } from '../../common/AppPreferences';
import { PageShell } from '../../common/PageShell';
import { IMMERSIVE_LEVEL_KEY, resolveEffectiveLevel,
  resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { ROUTE_CHAT_PAGE, ROUTE_SKILL_DESIGNATE_PAGE } from '../../common/RouteNames';
import {
  SkillDesignateParam, SkillDesignateResult
} from '../assistants/AssistantSkillPage';
import { ChatDataSource } from './ChatDataSource';
import { ChatFollowController } from './ChatFollowController';
import { ChatPageContent } from './ChatPageContent';
import { ChatSendCtrl } from './ChatSendCtrl';
import { ContextUsage, contextPct } from './ChatContextUsage';
import { ChatPageLoadCtrl } from './ChatPageLoad';
import { AttachmentPickCtrl, cleanupAttachments, removePendingAttachment, restoreDraftText, FilePickKind } from './AttachmentPickCtrl';
import { attachBlockingReason, sweepAttachDir, hasVisionCap, willSendImages } from '../../common/AttachmentUtil';
import { ocrRelease } from '../../common/OcrEngine';
import { visionConfirmOptions } from './ChatVisionConfirm';
import { DocParserHost, docParser } from '../../common/DocumentParse';
import { BrowseHost } from '../../common/BrowseWeb';
import { sinkMemoryForConversation } from '../../common/MemoryGen';
import { SESSION_LIST_RELOAD_KEY } from './ChatSessionList';
import { ChatMoreMenuCallbacks, ChatMoreMenuHost, ChatMessageMenuCallbacks,
  ChatMessageMenuHost, notifyWebOff, WebSearchMenu, webSearchEnabledNow } from './ChatMoreMenu';
import { CHAT_OFF_SUPPORTED_KEY, CHAT_THINKING_OPTIONS_KEY,
  CHAT_WEBSEARCH_ALLOWED_KEY, CHAT_WEBSEARCH_ON_KEY, ThinkingMenu } from './ChatParamChipBar';
import { KimiFullInputSheet } from './KimiFullInputSheet';
import { ModelPickerSheet } from './ModelPickerSheet';
import { ChatPromptSheet } from './ChatPromptSheet';
import { ContextUsageSheet } from './ContextUsageSheet';
import { CompressPreviewSheet } from './CompressPreviewSheet';
import { ChatCompressCtrl } from './ChatCompressCtrl';
import { ChatMessage } from './ChatMessageCompose';
import { SessionStatsSheet } from './SessionStatsSheet';
import { MODEL_ENTRY_HEIGHT, MODEL_ENTRY_LABEL, MODEL_ENTRY_PAD_H,
  MODEL_ENTRY_RADIUS, PRIVATE_SESSION_LABEL, THINKING_ENTRY_LABEL, chatTitleMenuNav
 } from './ChatTitleMenuFactory';
import { sheetPanelOptions, DETENTS_FULL } from './KimiSheetCommon';
// 标题栏自绘键共用件（★ 2026-09-11 迁移笔：本页右上角合并胶囊改消费共用件——原内联
// TitleActionCapsule builder 与 TITLE_ACTION_* 四常量已删，几何/双态单源在此）
import { TITLE_BAR_EDGE_INSET, TitleBarActionCapsule } from '../TitleBarKeys';
import { PROACTIVE_UNREAD_CONV_KEY } from '../../common/ProactiveGen';

// 失败轮重试占位文案（2026-09-15 撤链笔单源；★ 2026-09-20 重试真链复活：底栏重试键已
// 接回真链（onRetryMsg → sendCtrl.retryLast），本常量唯一消费方 = 失败轮重试行 onRetryTurn
// 占位（重发原文另立项）——单源常量保留，消费面 2 → 1）
const RETRY_PLACEHOLDER_TEXT: string = '重试暂未开放';
// ★ 2026-09-17 会话上下文用量笔：标题栏菜单工厂与入口胶囊常量域（隐私标记/模型思考
// 标签/胶囊几何/回退菜单工厂）外迁 ChatTitleMenuFactory.ets——本文件剔头越 1200 硬线的
// 先拆项，方法体原样搬迁；宽度预算沿革注释随常量迁走（见该件）
// 右上角合并胶囊（＋ 新建会话 / ⋯ 更多，各占一个热区）：键件与几何/双态口径 = 共用件
// `components/TitleBarKeys.ets`（TitleBarActionCapsule——形制演进史与该件的抽取缘由见该件
// 头注释；★ 2026-09-11 迁移笔：本页原持内联键件与四枚 TITLE_ACTION_* 常量，已改消费共用件，
// 行为一字未变）。
// ★ 宽度预算（决明「注意宽度」；二百二十七随右上角胶囊重算、二百二十八/二百二十九/二百三十一
// 随长度与等长复核、二百三十六/二百三十七随字号调整复核）仍归本页：标题栏可用宽 = 屏宽基线
// 360 − 左避让 64 − 右避让 TITLE_BAR_EDGE_INSET(16) − 右上角胶囊 92(共用件 TITLE_CAPSULE_WIDTH)
// = 188vp；非隐私态左组 = 92vp（富余 96vp）；**隐私态**左组 = 92 + 间距 8 + 隐私标记 ≈81 =
// 181vp ≤ 188vp（余 7vp）。等长上限即由该预算定：胶囊宽 W 须满足 W + 8 + 81 ≤ 360 − 64 − 16 − W
// → W ≤ 95.5vp，取 92 且四热区同宽（96 即溢出 1vp，勿再加大——改共用件热区宽时须同步本预算）。

// 标题栏菜单工厂与沿革注释已随常量域外迁 ChatTitleMenuFactory.ets（2026-09-17）；
// HDS 路径 menuHds 传 null（二百二十七退役口径不变，见该件头注释）

@Component
export struct ChatPage {
  // 目标会话 id（PageMapBuilder 注入：push 链路 = HomeNavigation.activeConvId、新建会话
  // replacePath = 路由 param；普通成员——构造后不变，坑30 口径）
  conversationId: string = DEFAULT_CONVERSATION_ID;
  // 隐私会话模式（2026-09-04，PageMapBuilder 注入 activePrivate；普通成员——构造后不变，
  // 坑30 口径）：true = 纯内存会话——标题固定不查会话行、发送链五写库点全旁路（ChatSendCtrl
  // privateMode 守卫）、离页即焚（aboutToDisappear 清数据源 + cleanupAttachments 清未发送
  // 附件）；附件与提示词选择开放（2026-09-04 决明指令）——附件沙箱副本由发送即删/离页
  // 清删/启动清扫三防线收口，提示词/助手选择走无行内存覆盖零写库；进程被杀时消息流随
  // 进程消亡、附件残留由启动清扫兜底；调研依据 docs/调研-隐私会话-RikkaHub与Cube同类实现-20260904.md
  isPrivate: boolean = false;
  // 顶部留白（标题栏蒙层下沿，PageMapBuilder 注入——内容起始避让，滚动时可滚入蒙层）
  @Prop topPad: number = 0;
  // 页面底部留白（vp，PageMapBuilder 注入 = 底部避让区高——全屏窗口下输入栏不压手势条；
  // @Prop：navBarHeight 异步实测，须状态驱动重渲染，坑57 同族）
  @Prop bottomPad: number = 0;
  // 官方路由栈（PageMapBuilder 注入：新建会话 replacePath 跳转用；普通成员不驱动 UI）
  pathStack: NavPathStack = new NavPathStack();
  // 消息流（@State 持有 @Observed 数据源；LazyForEach 经 IDataSource 契约消费，
  // @Track messageCount 驱动空态分支）
  @State private dataSource: ChatDataSource = new ChatDataSource();
  @State private sending: boolean = false;
  @State private dbReady: boolean = false;
  // 初始加载失败提示（'' = 无；仅覆盖层语义——与 messageCount 联合判定，动作时错误走 toast）
  @State private errorText: string = '';
  // 思考档位（2026-08-31 任务 B 起进请求：菜单选择落值经 refs 下发 ChatSendCtrl →
  // 协议方言落点；会话级 @State 不落库；'' = 默认不传）。★ 二百二十九起选择入口 = 标题栏
  // 「思考」热区（原输入栏 chip 退役，落值点见 ThinkingMenuBuilder）
  @State private thinkingValue: string = '';
  // 思考菜单选项集 / 「关闭」档可用（广播键自订阅——写点 = 本页 setConnInfo，按当前连接
  // 收窄选项集与 off 支持；二百二十九前消费方是输入栏 chip 行，chip 退役后由标题栏思考键
  // 的菜单消费，键契约不变）
  @StorageProp(CHAT_THINKING_OPTIONS_KEY) thinkingOptions: string[] = [''];
  @StorageProp(CHAT_OFF_SUPPORTED_KEY) offOk: boolean = false;
  // 标题栏思考键交互期（按压或菜单开着）：输入栏收起守卫第三源——原 chip 的 chipMenuOpen/
  // chipTouchActive 只覆盖输入栏 chip，思考入口迁标题栏后由本页上报（经 @Link 三级链下发
  // ChatInputBar，同 modelLabel 通道先例）；Down 置位 / Up·Cancel 复位、菜单 onAppear/
  // onDisappear 接续（见 ThinkingMenuBuilder 与 bindMenu 注释）
  @State private thinkingHold: boolean = false;
  // 联网开关状态（★ 2026-09-10 联网开关归位笔：由「会话级 @State，默认开、不落库」改为
  // **归属助手启用清单的镜像**——值 = assistants.tools 是否含 search_web，提示词态解析完成后
  // 写入；@StorageProp 自订阅该键（页面既是写点也是读点，CHAT_OFF_SUPPORTED_KEY 同款姿势）。
  // 发送组装经 refs.webSearchOn 读用）
  // ★ 2026-09-10 会话级覆盖层笔第二阶段定稿：本键 = **本会话生效值**（助手清单 ∩ 本会话
  // 未关），写点见 refreshWebSearchFlag。★ 2026-09-19 联网开关迁入标题栏「更多」菜单
  //（决明指令，原输入框 chip 退役）：消费方 = 更多菜单「联网」项（弹出一刻快照进
  // ChatMoreMenuCallbacks）；可用性两键不设页面订阅——不驱动 UI（状态最小化），弹出时由
  // ChatMoreMenu.webSearchEnabledNow 现读
  @StorageProp(CHAT_WEBSEARCH_ON_KEY) webSearchOn: boolean = true;
  // 当前模型名（2026-09-09 输入框工具行显示；只显示不可点——模型切换入口在标题栏「切换
  // 模型」键）。与 CHAT_OFF_SUPPORTED_KEY / CHAT_THINKING_OPTIONS_KEY 两广播同点写入
  //（setConnInfo），经 @Link 三级链下发 ChatInputBar（禁 @Prop——坑16：本链居
  // PageShell.content（@BuilderParam）内，@Prop 不随父刷新会冻结在首帧）
  @State private modelLabel: string = '';
  // 待发附件（2026-08-31 接线：AttachmentPickCtrl 入列填充、附件条渲染、发送随文本上送）
  @State private attachments: PendingAttachment[] = [];
  // 单条消息指定技能（2026-09-16 单条消息指定技能）：本轮指定的技能 id 与名（'' = 未指定）——
  // 纯内存态随页面存活（隐私会话同口径，不落库不跨会话）；写入链 = 技能选择页 pop 回填；
  // 消费链 = 发送漏斗首行写 ChatSendCtrl + 待发条渲染（经 @Link 三链下发 ChatInputBar）；
  // 清态 = 真投递后（dispatchSend 的 delivered 块，与附件同口径）
  @State private designatedSkillId: string = '';
  @State private designatedSkillName: string = '';
  // 半模态面板开关（dshinhm KimiChatPage 同款单面板 + sheetKind 分支——坑64 姿势：
  // bindSheet 复用页面根唯一挂载点，不新增）：'none' 关 / 'input' 全屏输入 /
  // 'model' 模型选择 / 'prompt' 附件与提示词（+ 键入口）/ 'context' 上下文用量
  // （2026-09-17 会话上下文用量——输入条工具行圆环键入口）/ 'stats' 会话统计
  // （2026-09-19——标题栏更多菜单入口）
  @State private sheetKind: string = 'none';
  // ── 上下文用量供给（2026-09-17 会话上下文用量，方案 §3.6）──
  // 圆环值：-1 = 窗口未知或无数据（仅底环，拍板 P4）/ 0~100 = 已用占比（@Link 三级链下
  // 发 ChatInputBar）；面板数据 = 最近一次活算产物（ContextUsageSheet @Link 读，重算落地
  // 自动刷新——重算进行中保留旧值不清空，Cline #3861 假低值反面）；seq = 并发守卫
  //（ChatPromptState.loadSeq 同款——旧结果不覆盖新结果）
  @State private ctxRingPct: number = -1;
  @State private ctxUsage: ContextUsage | null = null;
  private ctxUsageSeq: number = 0;
  // 全屏输入（dshinhm 二一一改语义随迁）：init = 面板初值快照（点全屏键时胶囊文本）；
  // draft/cmd = 回写胶囊的命令通道（cmd tick 驱动 ChatInputBar @Watch 覆盖——正常打字
  // 父不改无回环）；live = 面板实时草稿（onChange 上行——任何关闭路径均回写，未发送
  // 编辑不丢）
  @State private fullInputInit: string = '';
  @State private fullInputDraft: string = '';
  @State private fullInputCmd: number = 0;
  @State private fullInputLive: string = '';
  private conn: AiConnection | null = null;
  // 当前连接生效能力串（2026-09-15 附件 PDF 页渲染一期）：视觉门控的唯一输入——与 conn
  // 同写点（setConnInfo）、同更新时机（切模型 reloadConn 后自动跟随）。普通成员：不进
  // UI 渲染（只在发送前置读一次），故无需 @State
  private connCaps: string = '';
  // 视觉能力二次确认弹窗控制器（2026-09-15 页渲染一期）：**组件成员位**构造（坑7 正当
  // 形态——生命周期随组件，先例 ChatSessionList.confirmCtrl）；禁 showAlertDialog
  // （TabContent 槽内真机不弹，坑64 族 / ConfirmDialog.ets 头注释实证）
  private visionConfirmCtrl: CustomDialogController | null = null;
  // 会话级覆盖（2026-09-10 会话级覆盖层笔）：本会话内改过的模型选择——**无行会话**
  //（新建未发送/隐私会话）没有行可落，只存内存（首发落行时随 insertMessage 写入、
  // 隐私会话恒不落库）；有行会话以 DB 为真源（本值与之双写同值，reloadConn 只作无行兜底）。
  // 普通成员：不进 UI 渲染（生效路径 = reloadConn 读 → conn → 输入栏模型名），故无需 @State
  private memoryOverride: ConversationOverride | null = null;
  // 连接解析输入变化广播（2026-09-05 方案 a，自检轮 P2 闭环）：助手改绑/全局默认修改
  // tick 递增 → @Watch 重解析——修「页签切换不销毁重建，切回直接发送走旧 conn 缓存」
  // 缺口；tick 递增语义与写点清册见 ProviderDb.CONN_RESOLVE_TICK_KEY 键注释。进页初值
  // 不触发 @Watch（仅变化触发），回调时 loadCtrl 已构造
  @StorageProp(CONN_RESOLVE_TICK_KEY) @Watch('onConnResolveTick') connResolveTick: number = 0;
  // 官方 HDS 导航可用性（与 HomeNavigation 根容器同一能力位，两条路径必然一致）
  private hdsAvailable: boolean = canIUse('SystemCapability.UIDesign.HDSComponent.Core');
  // 声明顺序即初始化顺序：listScroller 必先于 follow（follow 构造吃 scroller 引用）
  private listScroller: Scroller = new Scroller();
  private follow: ChatFollowController = new ChatFollowController(this.listScroller);
  // 发送编排（M1 链路原样搬迁域；refs 闭包延迟求值——sending 等状态读总是当时值）
  private sendCtrl: ChatSendCtrl = new ChatSendCtrl({
    dataSource: this.dataSource,
    follow: this.follow,
    conversationId: (): string => this.conversationId,
    dbReady: (): boolean => this.dbReady,
    // 隐私会话（2026-09-04）：发送链写库点旁路开关——true = 零落库（守卫点见 ChatSendCtrl）
    privateMode: (): boolean => this.isPrivate,
    conn: (): AiConnection | null => this.conn,
    sending: (): boolean => this.sending,
    thinking: (): string => this.thinkingValue,
    // 联网开关（★ 2026-09-10 会话级覆盖层笔第二阶段：值 = 本会话生效值 = 助手启用清单 ∩
    // 本会话未关，@StorageProp 现读——写点见 refreshWebSearchFlag）
    webSearchOn: (): boolean => this.webSearchOn,
    // 无行会话的会话级覆盖（首条消息落行时写入 conversations 覆盖三列，见 ChatSendRefs 注释）
    sessionOverride: (): ConversationOverride | null => this.memoryOverride,
    setSending: (sending: boolean): void => {
      this.sending = sending;
    },
    clearError: (): void => {
      this.errorText = '';
    },
    toast: (message: string): void => {
      this.getUIContext().getPromptAction().showToast({ message: message });
    },
    // 页面 UIContext（2026-09-02 阶段 2：Cube 打字机 displaySync 通道注入；闭包延迟求值
    // ——调用时页面必已挂载，getUIContext 恒可达）
    cubeUiContext: (): UIContext | null => this.getUIContext(),
    // 轮次收尾刷新圆环（2026-09-17 会话上下文用量，方案 §3.6「真值到达 = 最准时刻」）；
    // done/error 两路都触发（失败轮后圆环照旧可用）
    onRoundSettled: (): void => {
      this.refreshCtxUsage();
    }
  });
  // 上下文压缩接线域（2026-09-23 修复笔自本页外迁——开面板/采用收口/删除收口/关闭确认四事
  // 在 ChatCompressCtrl；本页经 ChatCompressHost 七方法薄口回接，refs 同款闭包延迟求值）
  private compressCtrl: ChatCompressCtrl = new ChatCompressCtrl({
    conversationId: (): string => this.conversationId,
    allMessages: (): ChatMessage[] => this.dataSource.allMessages(),
    removeMessages: (ids: string[]): void => {
      this.dataSource.removeMessageIds(ids);
    },
    pushMessage: (message: ChatMessage): void => {
      this.dataSource.push(message);
    },
    setSheetKind: (kind: string): void => {
      this.sheetKind = kind;
    },
    refreshUsage: (): void => {
      this.refreshCtxUsage();
    },
    ui: (): UIContext => this.getUIContext()
  });
  // 加载与刷新编排域（2026-08-31 自本页拆出——行为不变；refs 同款闭包注入）
  private loadCtrl: ChatPageLoadCtrl = new ChatPageLoadCtrl({
    dataSource: this.dataSource,
    follow: this.follow,
    dbReady: (): boolean => this.dbReady,
    conversationId: (): string => this.conversationId,
    setConnInfo: (info: ActiveConnectionInfo | null): void => {
      this.conn = info !== null ? info.conn : null;
      // 生效能力串同写点（2026-09-15 页渲染一期）：视觉门控读它；与 conn 同生命周期、
      // 切模型/切会话随 reloadConn 自动更新
      this.connCaps = info !== null ? info.caps : '';
      // 当前模型名回写（输入栏工具行显示源；连接解析失败 = '' → 显示「未选择」）。换模型/
      // 换会话 → reloadConn 重解析 → 本点写入 → @Link 链自动刷新，无需额外广播
      this.modelLabel = info !== null ? info.conn.model : '';
      // 关闭可用广播 + 思考菜单选项集广播（@BuilderParam 内容 @Prop 不传播——坑16；chip
      // @StorageProp 自订阅写即刷新；只写不删无坑15 竞态）——2026-09-06 模型级精化：
      // 两值读 conn 填充字段（resolveActiveConnection 画像行模型级判定/派生；
      // connectionOffEnabled 含解析链外构造回落）；选项集 conn 空/未填充兜底全量
      // THINKING_OPTIONS。档位合法性回退（legalThinkingTier 单一源）：切禁 off 域/模型
      // → 默认；画像行选项集收窄后存量非法档位同归默认（注入层双保险在 ChatSendCtrl）
      const offOk: boolean = this.conn !== null && connectionOffEnabled(this.conn);
      AppStorage.setOrCreate<boolean>(CHAT_OFF_SUPPORTED_KEY, offOk);
      const options: string[] = this.conn !== null && this.conn.reasoningMenuOptions !== undefined ?
        this.conn.reasoningMenuOptions : THINKING_OPTIONS;
      AppStorage.setOrCreate<string[]>(CHAT_THINKING_OPTIONS_KEY, options);
      this.thinkingValue = legalThinkingTier(this.thinkingValue, offOk, options);
      // 上下文圆环随连接重算（2026-09-17 会话上下文用量：切模型/切会话 → reloadConn →
      // 本点——分母跟当前生效模型走，§3.5 矩阵）
      this.refreshCtxUsage();
    },
    // 历史加载收尾补算（2026-09-18 自检轮）：进页初算与本点（setConnInfo）都可能早于
    // loadHistory 重建完成——reloadConn/loadHistory/初算三条异步链并发无先后保证，缺此点
    // 长会话进页圆环停在仅固定开销的小值且无后续刷新点（onShown 首显被 dbReady 守卫跳过）
    onHistorySettled: (): void => {
      this.refreshCtxUsage();
    },
    setError: (text: string): void => {
      this.errorText = text;
    },
    // 动作时错误提示（loadOlder 查询失败走 toast——消息流在场不适用 errorText 覆盖层）
    toast: (message: string): void => this.getUIContext().getPromptAction().showToast({ message: message }),
    // 会话有效归属助手（2026-09-05 四级兜底链②级输入——转发发送域解析缓存，与注入链
    // 同源；reloadConn 无行会话分支消费）
    effectiveAssistantId: (): string => this.sendCtrl.boundAssistantId(),
    // 无行会话的会话级覆盖兜底（2026-09-10 会话级覆盖层笔：DB 查不到行时用页面内存值）
    memoryOverride: (): ConversationOverride | null => this.memoryOverride,
    // 流式追加缓冲复位（2026-09-11 笔 3：转发发送域，见 ChatPageLoadRefs 注释）
    resetAppendBuffer: (): void => this.sendCtrl.resetAppendBuffer(),
    // 沙箱 filesDir（2026-09-15 预览第三轮：附件简报装配拼绝对路径；闭包现读 host
    // context——loadCtrl 各方法调用时页面必已挂载）
    filesDir: (): string => (this.getUIContext().getHostContext() as common.UIAbilityContext).filesDir
  });
  // 附件选择编排域（2026-08-31 附件上传：三入口选择器→沙箱缓存→缩略图→入列）
  private attachCtrl: AttachmentPickCtrl = new AttachmentPickCtrl({
    getHostContext: (): common.UIAbilityContext | undefined =>
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined,
    getAttachments: (): PendingAttachment[] => this.attachments,
    setAttachments: (attachments: PendingAttachment[]): void => {
      this.attachments = attachments;
    },
    // 隐私会话附件目录分流（2026-09-09 附件落盘第一轮）：true = 附件落 cacheDir 临时区
    //（退出即删零落库）；false = filesDir 常驻区（pick 时读取，见 AttachmentPickRefs 注释）
    isPrivate: (): boolean => this.isPrivate,
    toast: (text: string): void => {
      this.getUIContext().getPromptAction().showToast({ message: text });
    }
  });
  // 「更多」菜单节点宿主（init / 弹出前重建 / dispose 成对，见 ChatMoreMenu.ets 注释）
  private moreMenu: ChatMoreMenuHost = new ChatMoreMenuHost();
  // 消息「更多」菜单节点宿主（2026-09-14 消息气泡底栏；生命周期同上成对，锚点在列表项内
  // ——锚点三态为真机验证项，见 ChatMoreMenu.ets 文末段注释）
  private messageMenu: ChatMessageMenuHost = new ChatMessageMenuHost();
  // 沉浸光感档位（「更多」菜单材质解析用；AppStorage 自订阅）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;

  aboutToAppear(): void {
    // DB 就绪等待（EntryAbility 异步初始化；未就绪禁发送并提示——禁同步等库）。
    // 2026-08-30 竞态修复：标题查询与连接解析原在守卫外直查，冷启动 DB 未就绪时与
    // 会话列表同族竞态；一并挪入就绪分支（见 ChatPageLoad 注释）
    whenReady().then((ok: boolean): void => {
      this.dbReady = ok;
      if (!ok) {
        this.errorText = '数据库初始化失败，发送功能已禁用';
        return;
      }
      if (this.isPrivate) {
        // 隐私会话：不查会话行（库中无行查询必空）+ 进页一次性提示；历史查询保留（空表回放
        // 复位翻页标志，只读零写入）。duration 3000 = 决明拍板「进/出提示停留略长」（官方
        // 默认 1500ms，取值域 [1500,10000]，d.ts 实锤）。标题栏标记由 isPrivate 直接驱动
        // （TitleBarContent，无状态可查）
        this.getUIContext().getPromptAction().showToast({ message: '已进入隐私会话，离开即删除记录', duration: 3000 });
      }
      this.loadCtrl.reloadConn();
      this.loadCtrl.loadHistory();
      // 提示词注入预载（会话引用/系统提示词解析缓存，面板选择后经 onPromptChanged 刷新；
      // 完成后写联网两键——chip 可点判定 + 生效值，2026-09-03 联网开关）
      this.refreshWebSearchFlag();
      // 上下文圆环初算（2026-09-17；reloadConn 完成后 setConnInfo 会再刷一次——本处覆盖
      // 「连接解析失败仍可算固定开销段」的场景；历史就绪后的确定性重算在 onHistorySettled
      // 收尾点，2026-09-18 自检轮增——初算与本点都不等 loadHistory 重建完成）
      this.refreshCtxUsage();
    });
    this.moreMenu.init(this.getUIContext(), this.moreCallbacks());
    // 消息菜单首建（callbacks 占位空实现——open 前重建换真值，首建只为节点就绪）
    this.messageMenu.init(this.getUIContext(), this.messageMenuCallbacks());
    // 会话页屏幕常亮（2026-09-04 偏好设置页第 5 项）：按偏好设置开——默认关 = 系统息屏
    // 零回归；成对复位见 aboutToDisappear
    this.applyKeepScreenOn(isKeepScreenOnEnabled());
  }

  aboutToDisappear(): void {
    // 会话页屏幕常亮复位（成对：aboutToAppear 按偏好设置开，此处无条件关——窗口属性
    // 进程级不随组件销毁复原，不复位则常亮态泄漏到列表/设置等其他页面）
    this.applyKeepScreenOn(false);
    // 页面销毁静默中止进行中流式（任务书红线：解绑回调防销毁后触 UI）——先停写者
    this.sendCtrl.disposeSilent();
    // 隐私会话离页即焚（2026-09-04）：流式已停（写者先停）再清内存消息流——组件随之
    // 销毁，显式清 = 不等 GC 立即生效；全程零写库零文件无残留面。销毁 toast 决明拍板
    // 加反馈（UIContext 为窗口级对象，页面销毁链调用仍可达；duration 同进页 3000）
    if (this.isPrivate) {
      this.dataSource.clear();
      // 隐私会话已发送附件随离页清删（★ 2026-09-15 预览笔拍板 1：发送不再即删，回收点
      // 后移到此——会话存续期间留盘供附件泡点开预览）。顺序：先 dataSource.clear 再清扫
      // 再 toast（消息流先清，清扫不受 UI 影响）；整目录清扫 = sweepAttachDir
      //（cacheDir/attachments 全清、目录保留）——隐私会话文件只此一处来源，整目录语义
      // 安全且免维护清单。ctx 取不到 = warn 留痕不静默（P0-1）；下方
      // cleanupAttachments(this.attachments) 再清未发送附件的缩略图（文件已被整目录
      // 清扫覆盖，幂等零副作用）
      const sweepCtx: common.UIAbilityContext | undefined =
        this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (sweepCtx !== undefined) {
        sweepAttachDir(sweepCtx);
      } else {
        hilog.warn(0xD5A0, 'ChatPage', '离页清扫未执行：host context 不可达（隐私附件文件由启动清扫兜底）');
      }
      this.getUIContext().getPromptAction().showToast({ message: '隐私会话已销毁', duration: 3000 });
    }
    // 文档解析兜底取消（2026-09-03 第三批②：宿主 Web 随页面销毁，进行中解析停止）
    docParser.cancelCurrentParse();
    // 系统识别引擎释放（2026-09-15 附件 OCR 二期：与 OcrEngine 懒 init 成对——建立与
    // 释放在「消费方页面生命周期」一对事件上，任务书红线 3）
    ocrRelease();
    // 未发送附件清删（缩略图 + 沙箱副本——附件不跨页面驻留；发送路径的清理在 ChatSendCtrl）
    cleanupAttachments(this.attachments);
    // 菜单节点成对释放（与 aboutToAppear init 成对——ComponentContent 不释放即泄漏）
    this.moreMenu.dispose();
    this.messageMenu.dispose();
    // 会话列表重拉广播（pop/replace 均触发：返回列表刷新时间序/新建行入列；AppStorage
    // 一次性计数器，坑3 口径——与组件树层级无关）。隐私会话豁免（2026-09-04，五笔自检
    // 观5 条件化）：全程零落库，会话列表不可能变化——广播只会多余一次列表重拉查询
    if (!this.isPrivate) {
      AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
        (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
      // 记忆沉淀（2026-09-08 记忆域）：退出会话 fire-and-forget 一次——隐私会话由本处
      // 调用侧过滤不触发（与标题生成同口径）；内部守卫序〔总开关/自动整理/加密/助手
      // 沉淀开关/模型键〕全在 MemoryGen，全链不 toast 不打扰
      sinkMemoryForConversation(this.conversationId);
    }
  }

  // 会话页屏幕常亮开关（2026-09-04 偏好设置页第 5 项）：窗口级属性 setWindowKeepScreenOn
  //（@ohos.window d.ts @since 9，无需权限）。姿态同 ChatInputBar 键盘监听：getLastWindow
  // 单窗口恒同实例；失败只打日志不静默（P0-1）——降级 = 照常系统息屏，与现状一致
  private applyKeepScreenOn(on: boolean): void {
    const hostContext: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (!hostContext) {
      return;
    }
    window.getLastWindow(hostContext).then((win: window.Window): Promise<void> => {
      return win.setWindowKeepScreenOn(on);
    }).catch((err: Error) => {
      console.error('setKeepScreenOn failed: ' + JSON.stringify(err));
    });
  }

  // 新建会话（标题栏「+」键与「更多」菜单动作，拍板 5；2026-08-29 改懒创建——领导指令
  // 「空会话不进历史」）：本地生成会话 id 直接 replacePath 同路由替换（坑57 同分支复用防，
  // 新实例读新会话 id；返回键直接回会话列表），不落库——首条消息发送时 ChatDb 才建行
  //（insertMessage 内 ensureConversation），新建不发消息 = 历史无痕
  private newConversation(): void {
    this.pathStack.replacePathByName(ROUTE_CHAT_PAGE, nextMessageId('conv'));
  }

  // 联网开关镜像刷新（2026-09-03 领导指令；★ 2026-09-10 会话级覆盖层笔第二阶段定稿；
  // ★ 2026-09-16 会话级技能启用笔曾扩为两族键同链，「单条消息指定技能」笔随覆盖退役回
  // 单族——函数名不动，改名撞 4 处既有断言钉锚〔assert-feature-domain 51/53 组〕）：
  // 联网两键——闸键 CHAT_WEBSEARCH_ALLOWED_KEY = 助手启用清单是否含 search_web（能力
  // 上限，chip 据此判可点/置灰）；值键 CHAT_WEBSEARCH_ON_KEY = 生效值 = 上限 **且** 本会话
  // 未关（webSearchOverride !== '0'）。
  // 调用四时点不变（打开会话 / 面板换助手 / 页面重新显示〔onShown〕/ 写覆盖后回灌），
  // load 异步，完成时机只有本链知道——load 返回 Promise。
  // 覆盖读法同 reloadConn：行在 = DB 为准，无行（新建未发送/隐私会话）= 页面内存覆盖。
  // ★ 失败口径：覆盖读失败或 load 失败 → **不写键**（镜像保持上一次解析结果）——与既有
  // 「读失败不静默翻转为默认」同一姿势，勿改成「catch 里写回默认值」（那会把一次读失败
  // 放大成"联网被关"的可见错误行为）
  private refreshWebSearchFlag(): void {
    const cid: string = this.conversationId;
    queryConversationOverride(cid)
      .then((row: ConversationOverride | null): Promise<void> => {
        const ov: ConversationOverride | null = row !== null ? row : this.memoryOverride;
        const sessionOff: boolean = ov !== null && ov.webSearchOverride === '0';
        return this.sendCtrl.loadPromptState(cid).then((): void => {
          const allowed: boolean = this.sendCtrl.webSearchAllowed();
          AppStorage.setOrCreate<boolean>(CHAT_WEBSEARCH_ALLOWED_KEY, allowed);
          AppStorage.setOrCreate<boolean>(CHAT_WEBSEARCH_ON_KEY, allowed && !sessionOff);
        });
      })
      .catch((): void => {
        // 覆盖读失败 / 提示词态 load 失败：两键保持上一次解析结果（见上条口径注释）
      });
  }

  // 联网开关选择落覆盖（★ 2026-09-10 会话级覆盖层笔第二阶段定稿语义 = 决明拍板第 2 种）。
  // 写的是**本会话**：点「关闭」= 写 webSearchOverride '0'（只影响这条会话），点「开启」=
  // 清覆盖 ''（跟随助手的启用清单）。★ 上一笔「chip 写回 assistants.tools」整条撤回——
  // 助手配置不再被会话内操作改动，助手未启用联网时 chip 根本不可点（硬闸在 chip 侧）。
  // 落库分两态同 onPickModel：会话已有行 = UPDATE；无行（新建未发送/隐私会话）= 只存内存，
  // 首发落行时随 insertMessage 写入。失败 toast 不静默（P0-1），随后照常重解析（有行会话
  // 以 DB 为真源、无行会话按内存值生效）
  private onPickWebSearch(on: boolean): void {
    const prev: ConversationOverride | null = this.memoryOverride;
    const value: string = on ? '' : '0';
    // 内存覆盖与 DB 双写同值（无行会话的内存是唯一载体，有行会话保证两条读法一致）；
    // ★ 模型两列**原样保留**——覆盖是「三值一对象」，重建时只换本次改的那一值，勿写成
    // 三值全传（那会在无行会话里顺手清掉模型覆盖）
    this.memoryOverride = {
      modelProviderId: prev !== null ? prev.modelProviderId : '',
      modelId: prev !== null ? prev.modelId : '',
      webSearchOverride: value
    } as ConversationOverride;
    updateConversationWebSearchOverride(this.conversationId, value)
      .then((): void => {
        this.refreshWebSearchFlag(); // 有行：以 DB 重读收口；无行：0 行不报错，按内存值生效
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({
          message: '联网开关保存失败：' + (e as Error).message
        });
        this.refreshWebSearchFlag();
      });
  }

  // ═══ 上下文用量供给（2026-09-17 会话上下文用量，方案 §3.6）═══
  // 刷新点收敛六处：进页 / 切模型（setConnInfo 同点）/ 历史加载收尾（onHistorySettled
  // ——进页三链竞态的确定性收口，2026-09-18 自检轮增）/ 页面重显（onShown——子页改提示
  // 词、技能、助手返回即刷，§六-6）/ 轮次收尾（onRoundSettled——真值到达 = 最准时刻）/
  // 开面板（带草稿）。打字与生成中不刷（§3.6）。★ 重算进行中与失败均保留旧值不清空（Cline
  // #3861 新数据未就绪计数先掉假低值的反面）；seq 守卫防旧结果覆盖新结果
  // ★ 2026-09-23 活算纳入待发附件笔：待发附件数组与 hasVision（判据同发送链视觉门控
  // :610/:627 两处，禁另立口径）随参下传——图片张数与文本侧构成的计算收归域件单源
  //（AttachmentUtil.pendingAttachFootprint），本页不再自算
  private refreshCtxUsage(draftText: string = ''): void {
    const seq: number = ++this.ctxUsageSeq;
    const hasVision: boolean = this.conn !== null && hasVisionCap(this.connCaps);
    this.sendCtrl.computeContextUsage(draftText, this.attachments, hasVision)
      .then((usage: ContextUsage): void => {
        if (seq !== this.ctxUsageSeq) {
          return;
        }
        this.ctxUsage = usage;
        this.ctxRingPct = contextPct(usage);
      })
      .catch((): void => {
        // 活算失败保持旧值（不静默翻转为空环——refreshWebSearchFlag 同姿势）
      });
  }

  // 圆环点击开上下文用量面板（2026-09-17）：带当前草稿文本（面板「本轮输入」段打开时取
  // 一次，方案 §3.4 段 8——胶囊文本经回调带出，onFullscreen 先例）；「计算中保留旧值」由
  // refreshCtxUsage 承担（首开 ctxUsage 为 null = 面板占位「正在统计」）
  private openContextSheet(draft: string): void {
    this.sheetKind = 'context';
    this.refreshCtxUsage(draft);
  }

  // 更多菜单开「会话统计」面板（2026-09-19 会话统计半模态笔）：不带草稿（面板无「本轮
  // 输入」段）；刷新一次活算——「上轮实际 / Token 用量」两卡与上下文面板同源 $ctxUsage，
  // 真值到达 = 最准时刻（轮次收尾已有刷新点，此处兜「久置后直开」的间隔）
  private openStatsSheet(): void {
    this.sheetKind = 'stats';
    this.refreshCtxUsage();
  }

  // ═══ 上下文压缩（2026-09-23 上下文压缩；域体四件 = CompressPreviewSheet〔三态面板〕/
  //     CompressGen〔生成〕/ CompressDb〔落库〕/ ChatCompressCtrl〔页面接线〕——本页只留
  //     compressCtrl 实例与本段薄接线。★ 2026-09-23 修复笔：按技术债务清单「下次实质
  //     改动前先拆其一再动手」把压缩接线域（开面板/采用收口/删除收口/关闭确认四事）整体
  //     外迁 ChatCompressCtrl，本页 SheetHost 内改调该实例）═══

  // 发送统一入口（胶囊与全屏输入两路收敛）：附件阻断前置（2026-09-15 附件 OCR 二期：
  // doc 解析阻断 + OCR 识别中——attachBlockingReason 单源，未识别完不发）→ 视觉能力
  // 门控（2026-09-15 页渲染一期，见下）→ 快照附件 → 清页面态（与文本同语义：
  // 点发送即清，成败不再回收）→ 交发送编排。
  // ★ 返回值契约（2026-09-15 发送链收口笔，替代原 void 隐含契约「调用即已投递」）：
  // true = 已投递或已进入确认流程（调用方可按「发送成功」清草稿）；false = 本次未投递
  // （解析/识别阻断 / 发送守卫拦下）——调用方**保留输入条文字**，附件与页面态亦原样保留
  private sendWithAttachments(text: string): boolean {
    // 本轮指定写入（2026-09-16 单条消息指定技能，★ 自检轮 F2 更正：挂漏斗而非输入栏 onSend）
    // ——两个发送入口（输入栏 :onSend / 全屏输入面板）与视觉确认路径共用本漏斗，首行恒写
    //（'' = 无指定）一处即全覆盖
    this.sendCtrl.setSkillDesignate(this.designatedSkillId);
    const blocking: string = attachBlockingReason(this.attachments);
    if (blocking !== '') {
      this.getUIContext().getPromptAction().showToast({ message: blocking });
      return false;
    }
    // 视觉门控（拍板③：不再是硬阻断——无视觉能力时弹二次确认，确认后照发）：
    // 判据 = 本轮**真的**带图（图片附件或扫描件页图；渲染失败无页图则不弹，判据取实际产物；
    // ★ OCR 二期：已分流走识别文本的件不算「带图」——hasVision 传入分流判据单源）
    // ★ 前提必须有连接：conn === null 时 caps 恒空，缺此判会让「未配置服务商」的用户先看到
    //   「模型不支持视觉理解」的错提示（照发后附件还会被 send() 守卫清掉）——无连接交给
    //   ChatSendCtrl.send 既有守卫呈报「请先在设置 > 服务商管理完善服务商」，本闸不参与
    const hasVision: boolean = this.conn !== null && hasVisionCap(this.connCaps);
    if (this.conn !== null && !hasVision && willSendImages(this.attachments, hasVision)) {
      this.openVisionConfirm(text);
      // 已进入确认流程 = 契约里的 true：附件与页面态保留到确认路径（见 dispatchSend）；
      // 两路调用方按 true 清草稿，取消三路由 restoreDraftText 还回
      return true;
    }
    return this.dispatchSend(text);
  }

  // 实际投递（门控直通与确认两路共用）：交发送编排 → **真投递才清页面态**（2026-09-15
  // 收口笔：原「先清再投」在守卫拦下时把附件一起吞掉——现在 false 时文字与附件都留输入条，
  // 用户配好服务商/等解析完可直接重发）
  private dispatchSend(text: string): boolean {
    const atts: PendingAttachment[] = this.attachments;
    // hasVision 单源现读（与 sendWithAttachments 同判据 hasVisionCap(connCaps)——载荷组装
    // 分流用；确认路径经此二次计算，两次之间连接不变〔确认弹窗期间无法切模型〕）
    const hasVision: boolean = this.conn !== null && hasVisionCap(this.connCaps);
    const delivered: boolean = this.sendCtrl.send(text, atts, hasVision);
    if (delivered) {
      this.attachments = [];
      // 指定清态（2026-09-16 单条消息指定技能）：真投递才清（与附件同口径——视觉确认被
      // 取消时指定不丢，用户可在同一轮重发）；只此一轮 = 清掉即下一条消息重新选
      this.designatedSkillId = '';
      this.designatedSkillName = '';
    }
    return delivered;
  }

  // 无视觉能力二次确认（2026-09-15 页渲染一期）：确认 = 走原发送体；取消/遮罩/返回 =
  // 不发、附件原样留条上、**输入的文字也还给用户**（restoreDraftText）。控制器在组件
  // 成员位构造（坑7 正当形态，先例 ChatSessionList.confirmCtrl）；弹窗走 ConfirmDialog
  // 官方自定义对话框，禁 showAlertDialog（TabContent 槽内真机不弹，坑64 族）。
  // ★ 2026-09-22 域级最小拆分：弹窗 options（文案 + 遮罩/返回键桥接 + 弹层族材质）迁
  // ChatVisionConfirm.ets（本页越 1200 硬线，先拆后改、本页净减行）；本方法只留 controller
  // 构造与打开——builder 需要组件上下文，不随迁。
  private openVisionConfirm(text: string): void {
    this.visionConfirmCtrl = new CustomDialogController(visionConfirmOptions({
      onConfirm: (): void => {
        this.dispatchSend(text); // 确认路径草稿保持已清态（文字已随消息发出）
      },
      onCancel: (): void => {
        // 取消把这段文字还给用户（回写通道 = applyFullInputDraft 覆盖式重写，理由见
        // AttachmentPickCtrl.restoreDraftText 注释）
        restoreDraftText((t: string): void => this.applyFullInputDraft(t), text);
      }
    }));
    this.visionConfirmCtrl.open();
  }

  // 附件半模态三卡入口（拍照/照片/系统文件——面板保持打开，dshinhm FileSheet 同款）
  private onPickAttachment(kind: FilePickKind): void {
    this.attachCtrl.pick(kind);
  }

  // 隐私会话刷新（2026-09-04 自检修复）：只清错误态 + 重读连接，不走 refreshPage——其
  // loadHistory 对消息流整表重建，隐私会话 DB 无行，重建即清空会话中消息（违反「会话内
  // 不丢数据」）；「更多·刷新」与错误覆盖层「重试」两入口收敛此方法
  private refreshPrivateConn(): void {
    this.errorText = '';
    this.loadCtrl.reloadConn();
  }

  // 「更多」菜单回调簇（init/open 各传一次——open 每次弹出前重建节点取当前深浅色）
  private moreCallbacks(): ChatMoreMenuCallbacks {
    // 联网快照（弹出一刻的生效值——open 前重建取真值，refreshDisabled 同款；webSubMenu 闭包捕获同一份）
    const webOn: boolean = this.webSearchOn;
    return {
      // ★ 2026-09-15 流式禁用（决明指令「在流式禁用吧」；存量观察项销账）：弹出一刻的
      // 流式态快照——刷新项据此置灰（sending 现读；init 时恒 false 无妨，open 前重建取真值）
      refreshDisabled: this.sending,
      onRefresh: (): void => {
        // 流式兜底守卫（照发送链 sending 守卫先例——理论不可达：置灰项点击由系统拦截不派发；
        // 防御性呈报不静默，防时序窗口）。★ 刷新链曾无 sending 守卫（流式中整表 rebuild
        // 走查自愈：同 id 重挂 + assistantFull 权威串在域），按指令收口为「流式中不可用」
        if (this.sending) {
          this.getUIContext().getPromptAction().showToast({ message: '请等待当前回复结束再刷新' });
          return;
        }
        if (this.isPrivate) {
          this.refreshPrivateConn();
          return;
        }
        this.loadCtrl.refreshPage();
      },
      onNewSession: (): void => {
        this.newConversation();
      },
      // ★ 2026-09-19 联网开关迁入：动作 + 子菜单 builder（坑51/62 形态见 ChatMoreMenu
      // 头注释；弹出一刻的生效值经 webOn 闭包捕获传 WebSearchMenu.on——菜单打勾快照走
      // 该通道，2026-09-20 D6-1 清除零消费的 webSearchOn 字段与注入）
      webSearchEnabled: webSearchEnabledNow(),
      onPickWebSearch: (on: boolean): void => {
        this.onPickWebSearch(on);
      },
      onWebSearchDenied: (): void => {
        notifyWebOff(this.getUIContext());
      },
      webSubMenu: (): void => {
        this.WebSearchSubMenu(webOn);
      },
      // ★ 2026-09-19 会话统计项：可见性快照（隐私会话隐藏——零落库统计恒全零，注释见
      // ChatMoreMenu.callbacks）+ 点击开面板
      statsEnabled: !this.isPrivate,
      onOpenStats: (): void => {
        this.openStatsSheet();
      }
      // ★ 2026-09-23 上下文用量菜单项撤回（决明口径「只留输入框环形入口」）：原
      // usageEnabled/onOpenUsage 两参随菜单项删；面板入口 = 输入条圆环（下一行族）
      // 与摘要轻提示行（内容区 onOpenUsage，见下方 content 侧同名回调）
    };
  }

  // 弹出「更多」官方菜单（材质 REGULAR 基准随沉浸光感总档，宿主内解析）
  private openMoreMenu(): void {
    this.moreMenu.open(this.getUIContext(), this.moreCallbacks(), this.immersiveLevel);
  }

  // 消息菜单回调（2026-09-14 消息气泡底栏；两项占位——点击 toast 暂未开放，照 onRetryTurn
  // 占位先例；真实现各属独立任务：分支独立立项、删除独立一笔）
  private messageMenuCallbacks(): ChatMessageMenuCallbacks {
    return {
      onBranch: (): void => {
        this.getUIContext().getPromptAction().showToast({ message: '分支功能暂未开放' });
      },
      onDeleteMsg: (): void => {
        this.getUIContext().getPromptAction().showToast({ message: '删除功能暂未开放' });
      }
    };
  }

  // 弹出消息「更多」菜单（msgId = 锚点消息；隐私会话不可达——底栏整栏不显示，
  // 防御性早退不弹菜单）
  private openMessageMenu(msgId: string): void {
    if (this.isPrivate) {
      return;
    }
    this.messageMenu.open(this.getUIContext(), this.messageMenuCallbacks(), msgId,
      this.immersiveLevel);
  }
  // ═══ 全屏输入面板通道（dshinhm 二一一改语义随迁） ═══

  // 全屏输入入口：initial 快照 = 胶囊当前文本；live 同步初值（面板 aboutToAppear 会再
  // 上行一次，幂等）
  private openFullInput(initial: string): void {
    this.fullInputInit = initial;
    this.fullInputLive = initial;
    this.sheetKind = 'input';
  }

  // 模型选择面板入口（标题栏返回键右侧「模型」胶囊 / 回退路径菜单项，两处同一回调）：面板
  // 选中 → 写当前服务商/模型两键（持久）→ 重读连接（发送链路即时换模型）→ 关面板。
  // ★ 2026-09-09 两次换入口：原「标题栏模型名点击」作废 → 三键中键（一百八十二）→ 返回键
  // 右侧胶囊（二百一十六）；半模态本体零改动（顶部「当前选择」行承担原模型名的展示职责）
  private openModelSheet(): void {
    this.sheetKind = 'model';
  }

  // 标题栏键材质档（沉浸光感总档 → 生效档位；与 hdsTitleBarOptions 同一 resolveEffectiveLevel，
  // -1 = 「无」档 = 纯色圆底，与返回键/官方菜单键同款）——「模型|思考」文字胶囊专用
  //（★ 2026-09-11 迁移笔：右上角合并胶囊改消费共用件、档位在件内解析，本方法消费方
  // 由两处回到一处；原名 modelEntryLevel 的改名史见二百二十七）
  private titleBarKeyLevel(): number {
    return resolveEffectiveLevel(this.immersiveLevel);
  }

  // 会话内选模型（★ 2026-09-10 会话级覆盖层笔改语义）：面板选择 = **本会话覆盖**，不是
  // 「全局当前模型」——只影响这条会话，新会话/其他会话照旧走「助手绑定 → 全局默认 →
  // 首个启用」。落库分两态：会话已有行 = 直接 UPDATE 覆盖列；**无行会话（新建未发送/
  // 隐私会话）= 只存内存**（memoryOverride，首发落行时随 insertMessage 写入——先例
  // conversations.promptId 的面板覆盖），退出即丢（决明拍板语义：空会话里改的东西不保存）。
  // 失败 toast 不静默（P0-1）；内存值不回滚——无行会话本次停留内仍生效（内存是唯一载体），
  // **有行会话则落回解析链 ②③④ 级**（行存在时 DB 为准，写失败 ⇒ 读出旧值），详见 catch 注释
  private onPickModel(providerId: string, modelId: string): void {
    // 内存覆盖（无行会话的唯一载体；有行会话与 DB 同值，双写保证 reloadConn 两种读法一致）；
    // ★ 联网覆盖列**原样保留**——覆盖是「三值一对象」，重建时只换本次改的模型两值，勿把
    // webSearchOverride 一并写成 ''（那会在无行会话里顺手清掉本会话的联网关闭态）
    const prev: ConversationOverride | null = this.memoryOverride;
    this.memoryOverride = {
      modelProviderId: providerId, modelId: modelId,
      webSearchOverride: prev !== null ? prev.webSearchOverride : ''
    } as ConversationOverride;
    updateConversationModelOverride(this.conversationId, providerId, modelId)
      .then((): void => {
        this.loadCtrl.reloadConn(); // 有行：落库后重解析取 DB 值；无行：0 行不报错，走内存值
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({
          message: '模型选择保存失败：' + (e as Error).message
        });
        // ★ 2026-09-10 会话级覆盖层笔自检更正：原注释写「本次停留内仍按内存覆盖生效」——
        // **对无行会话成立，对有行会话不成立**（reloadConn 里行存在时以 DB 为准，行写失败
        // ⇒ 读出旧值，内存覆盖不参与）。实际行为 = 落回解析链的 ②③④ 级；此处照常重解析
        // 只为把 conn 收敛到与 DB 一致（写失败不静默已由上面 toast 承担）
        this.loadCtrl.reloadConn();
      });
    this.sheetKind = 'none';
  }

  // 技能选择页入口（2026-09-16 单条消息指定技能，半模态「技能」卡单入口）：先关面板再 push
  //（本工程「半模态起二级页」链先例 = 647 笔首用，本笔沿用同一转场链）；param = 当前指定
  //（'' = 未指定）；onPop = 指定页统一带 SkillDesignateResult 回传（点行即返回：点非当前行
  // = 指定、点当前行 = 取消——PopInfo.result 本地 SDK 实锤 navigation.d.ts:349-371，本工程
  // 首次使用 payload 形态见 647 笔注释，真机验取值，取不到即按方案 §4.3 退路改面板内切形态）。
  // res undefined = 异常路径（无载荷）→ 不动现值
  private openSkillDesignatePage(): void {
    this.sheetKind = 'none';
    const param: SkillDesignateParam = { skillId: this.designatedSkillId };
    this.pathStack.pushPathByName(ROUTE_SKILL_DESIGNATE_PAGE, param, (popInfo: PopInfo): void => {
      const res: SkillDesignateResult = popInfo.result as SkillDesignateResult;
      if (res === undefined) {
        return; // 无载荷 = 不动现值
      }
      this.designatedSkillId = res.skillId; // '' = 取消指定
      this.designatedSkillName = res.skillName;
    });
  }

  // 解析输入变化回调（方案 a 读点）：助手改绑/改全局默认后重解析——页签切换无重解析点
  // 的缺口闭环；解析只读，多触发无害（★ 2026-09-10 会话级覆盖层笔：原①级回写两键的
  // 副作用已随键退役，本回调纯读）
  private onConnResolveTick(): void {
    this.loadCtrl.reloadConn();
  }

  // 页面重新显示回调（2026-09-08 决明拍板修自检发现 3 / 报告 §四）：助手绑定值随会话页
  // 存活期固化的缺口——重载提示词态（幂等只读：注入源 / 启用工具清单 / 记忆注入开关 /
  // 高级参数同链刷新，助手记忆页改「注入」后返回本页发送即按新值；坑25 定稿「onShown 是
  // 可靠姿势，每次页面显示触发，含 pop 返回」，栈下层收不到 @StorageProp 广播时的兜底）。
  // dbReady 守卫：冷启动 onShown 可能早于库就绪，跳过——进页 whenReady 链会加载；否则
  // 未就绪失败会把 loadSeq 抬高、连带作废正常 load 的结果（ChatPromptState 序号守卫语义）
  private onPageShown(): void {
    // 清主动消息未读（2026-09-12 主动消息第二笔：进入该会话即清——含 pop 返回重显场景；
    // 纯 AppStorage 写不依赖库就绪，故置于 dbReady 守卫之前；清空路径全仓唯一〔写侧 =
    // ProactiveGen 落库覆盖，清除侧 = 本处〕）
    if ((AppStorage.get<string>(PROACTIVE_UNREAD_CONV_KEY) ?? '') === this.conversationId) {
      AppStorage.setOrCreate<string>(PROACTIVE_UNREAD_CONV_KEY, '');
    }
    if (!this.dbReady) {
      return;
    }
    this.refreshWebSearchFlag();
    // 上下文圆环随页面重显重算（2026-09-17：子页改提示词/技能/助手后返回即刷——组装输入
    // 变了，方案 §六-6；onShown 是坑25 定稿的可靠姿势）
    this.refreshCtxUsage();
  }

  // 回写胶囊命令（tick 强制触发——@Watch 对同值不触发，tick 递增保证每次命令都覆盖；
  // 覆盖含空串（发送后清空/面板清空关闭）——与「无命令」区分 = 命令只在两时点发出）
  private applyFullInputDraft(text: string): void {
    this.fullInputDraft = text;
    this.fullInputCmd++;
  }

  // 思考档位菜单（bindMenu builder 位——菜单体 = 共享 ThinkingMenu 组件，与助手「模型设置」
  // 页同款，选项集/关闭档可用性走广播键自订阅，写点 = 本页 setConnInfo）。★ 二百二十九：
  // 入口随「思考」热区迁入标题栏（原输入栏 chip 的 ThinkingMenuBuilder 退役）；选择落值
  // 驱动 thinkingValue → 经 refs 进请求（ChatSendCtrl）
  @Builder
  ThinkingMenuBuilder() {
    ThinkingMenu({ value: $thinkingValue, options: this.thinkingOptions, offOk: this.offOk,
      onPick: (option: string): void => {
        this.thinkingValue = option;
      }
    })
  }

  // 联网二级菜单挂点（★ 2026-09-19 迁入笔）：坑51/62 形态——CustomBuilder 位必须挂组件内
  // @Builder 方法，本页只留壳，菜单本体 = ChatMoreMenu.WebSearchMenu（联网域 UI 面随更多
  // 菜单域件收拢——ChatPage 越 1200 硬线的本笔拆分项）；onPick 落本会话覆盖，on 为弹出一刻
  // 快照（节点弹出前重建，@Builder 按值传递无刷新需求——refreshDisabled 同款）
  @Builder
  WebSearchSubMenu(on: boolean) {
    WebSearchMenu({ on: on, onPick: (v: boolean): void => {
      this.onPickWebSearch(v);
    } })
  }

  // 标题栏覆盖层内容（坑51/62 红线：CustomBuilder 位必须挂组件内 @Builder 方法——lambda
  // 直调全局 @Builder 运行时闪退；先例 = SearchPage.TitleBarSearch）。内容 = 左组（返回键
  // 右侧的模型|思考双热区胶囊〔★ 2026-09-09 决明指令「模型切换胶囊移到返回键右侧，改模型
  // 二字，注意宽度」→ 同日二百二十九「不改变键高度，长度再增大一点，键内右侧放思考二字，
  // 各自热区」〕+ 隐私会话常显标记〔2026-09-04 定稿的隐私态提示，非会话标题〕）+ 右组
  //（右上角合并胶囊，二百二十七）。
  // 仅 HDS 路径经 titleBarStack 挂载（回退路径无 stackBuilder 机制：模型入口与两键都在官方
  // 菜单、隐私标记由 PageShell.title 承载；回退路径的思考档位仍在输入栏 chip 行，见
  // ChatParamChipBar 注释——两条路径菜单可达性等价）；隐私态构造后不变（isPrivate 普通成员，
  // 坑30 口径）。
  @Builder
  TitleBarContent() {
    Row() {
      // ── 左组：模型|思考双热区胶囊 + 隐私会话标记（恒居左；宽度自适应内容，Row 内
      // flexShrink 默认 0）──
      Row({ space: 8 }) {
        // 模型|思考 双热区胶囊（★ 二百二十九，决明「标题栏模型键，不改变键高度，长度再增大
        // 一点，键内右侧放思考二字，各自热区」；★ 二百三十一内距 12 → 9 = 92vp，与右上角
        // 胶囊等长；★ 二百三十六决明「字号大一点点、不改变胶囊形状、模型二字字重大一点、
        // 思考改占位符灰」——字号 14 → 15fp、内距 9 → 8；★ 二百三十七决明「真机效果可以，
        // 保持胶囊不变，字号再大一点点」——字号 15 → 16fp、内距 8 → 7（胶囊恒 92vp）；模型
        // = Medium 主色、思考 = font_secondary 灰（系统语义色，深浅色自动反色，与输入栏
        // 占位符同族））：一壳体两热区（形制同右上角合并胶囊）——左热区开模型选择面板、
        // 右热区开思考档位菜单；键高 40 不变、宽度随两个两字标签自适应（92vp，预算见常量注释）。
        // ★ 光感双态（二百一十七「应接入光感，同标题栏
        // 其他键」延续）：材质档随沉浸光感总档（resolveEffectiveLevel 与 hdsTitleBarOptions
        // 同一解析；2026-09-12 分项退役前随沉浸光感总档）——材质档 = 壳体走官方 THIN 材质（按压形变/触点光效，标题栏是材质生效区）
        // + 两热区透明底、关原生按压（坑58）；「无」档 = 壳体无材质无底色，两热区各垫官方
        // 纯色底（comp_background_tertiary，左半/右半拼出整胶囊——同右上角胶囊口径，**不可**
        // 壳体与热区同时垫同色，该语义色带透明度会叠出内圈色块）+ 保留原生按压
        Row() {
          // 左热区：模型（点开模型选择面板；主色 + Medium——二百三十六决明「模型二字字重
          // 大一点」，与「思考」的占位符灰形成主次）
          Button() {
            Text(MODEL_ENTRY_LABEL)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
          }
          .type(ButtonType.Normal)
          .height(MODEL_ENTRY_HEIGHT)
          .padding({ left: MODEL_ENTRY_PAD_H, right: MODEL_ENTRY_PAD_H })
          .borderRadius({ topLeft: MODEL_ENTRY_RADIUS, bottomLeft: MODEL_ENTRY_RADIUS })
          .backgroundColor(this.titleBarKeyLevel() < 0 ?
            $r('sys.color.comp_background_tertiary') : Color.Transparent)
          .stateEffect(this.titleBarKeyLevel() < 0)
          .onClick((): void => {
            this.openModelSheet();
          })
          // 右热区：思考（点开档位菜单；按压期与菜单期上报 thinkingHold——输入栏收起守卫。
          // ★ 二百三十六决明「思考二字改成灰色，类似输入框里的『输入消息』提示，注意反色」
          // ——font_secondary 系统语义色 = 占位符同族灰，深浅色自动反色）
          Button() {
            Text(THINKING_ENTRY_LABEL)
              .fontSize(16)
              .fontColor($r('sys.color.font_secondary'))
          }
          .type(ButtonType.Normal)
          .height(MODEL_ENTRY_HEIGHT)
          .padding({ left: MODEL_ENTRY_PAD_H, right: MODEL_ENTRY_PAD_H })
          .borderRadius({ topRight: MODEL_ENTRY_RADIUS, bottomRight: MODEL_ENTRY_RADIUS })
          .backgroundColor(this.titleBarKeyLevel() < 0 ?
            $r('sys.color.comp_background_tertiary') : Color.Transparent)
          .stateEffect(this.titleBarKeyLevel() < 0)
          .bindMenu(this.ThinkingMenuBuilder, {
            // 标题栏在屏顶，菜单向下展开（输入栏 chip 时代在屏底用 TopLeft）；材质 REGULAR
            // 弹窗基准随沉浸光感总档（弹窗豁免区，与 chip 菜单同口径）
            placement: Placement.BottomLeft,
            // ★ 第三参 true = 交互形变 + 触点流光（2026-09-18 菜单光感笔；官方最佳实践口径，勿回改 false）
            systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
              this.immersiveLevel, true),
            // 菜单开合上报（输入栏收起守卫：菜单弹窗取焦致 TextArea 失焦，不收——同 chip 口径）
            onAppear: (): void => {
              this.thinkingHold = true;
            },
            onDisappear: (): void => {
              this.thinkingHold = false;
            }
          })
          // 按压期即置守卫（Down→Up 之间失焦可能先到，150ms 收起计时器须被拦；Up 后菜单
          // onAppear 接续，交互全程守卫不断——同输入栏 chip 的 chipTouchActive 语义）
          .onTouch((event: TouchEvent): void => {
            if (event.type === TouchType.Down) {
              this.thinkingHold = true;
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.thinkingHold = false;
            }
          })
        }
        .height(MODEL_ENTRY_HEIGHT)
        .borderRadius(MODEL_ENTRY_RADIUS)
        .clip(true)
        .systemMaterial(resolvedUiMaterial(uiMaterial.ImmersiveStyle.THIN,
          this.immersiveLevel, true))
        if (this.isPrivate) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.eye_slash'))
              .fontSize(13)
              .fontColor([$r('sys.color.font_primary')])
            Text(PRIVATE_SESSION_LABEL)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
          }
        }
      }
      .alignItems(VerticalAlign.Center)
      // Blank 撑开左右两组：右组恒贴右端（合并胶囊右缘 = 屏宽 − TITLE_BAR_EDGE_INSET）。
      // 命中测试 None（二百二十八自检补）：纯布局占位件不参与命中——覆盖层靠父 Row 的
      // Transparent 让标题栏空白带拖动穿到消息流，占位件若按默认档参与命中徒增不确定
      Blank()
        .hitTestBehavior(HitTestMode.None)
      // ── 右组：右上角合并胶囊（＋ 新建会话 / ⋯ 更多，各占一个热区）——
      // 键件 = 共用件 TitleBarKeys.TitleBarActionCapsule（＋|⋯ 两热区、图标与无障碍文案
      // 由本页传入；★ 2026-09-11 迁移笔消费共用件，原自绘 @Builder 退役）──
      TitleBarActionCapsule({
        leftIcon: $r('sys.symbol.plus'),
        leftLabel: '新建会话',
        rightIcon: $r('sys.symbol.dot_grid_2x2'),
        rightLabel: '更多',
        immersiveLevel: this.immersiveLevel,
        onLeftTap: (): void => {
          this.newConversation();
        },
        onRightTap: (): void => {
          this.openMoreMenu();
        }
      })
    }
    .width('100%')
    .height('100%')
    .alignItems(VerticalAlign.Center)
    // 左端 64vp = 返回键避让（16 + 40 + 8）；右端 TITLE_BAR_EDGE_INSET(16) = 官方标题栏 end
    // padding——★ 二百二十七前为 104（避让官方菜单双键：16 + 2×40 + 1×8，出处 = dshinhm
    // docs/页面标题栏与转场规范.md §6），菜单数组退役后右上角键由本覆盖层自持，避让位取消
    .padding({ left: 64, right: TITLE_BAR_EDGE_INSET })
    // 命中测试 Transparent（SearchPage 同款）：覆盖层整栏铺在返回键上方，空白区不拦截触摸、
    // 返回键保持可点（胶囊自身是 Button，独立命中）
    .hitTestBehavior(HitTestMode.Transparent)
  }

  // 内容区（坑39 红线：@BuilderParam content 不能 lambda 直写 UI——组件内 @Builder 方法
  // 承载；布局与参数语义见 ChatPageContent）
  @Builder
  Content() {
    // 文档解析隐式宿主（2026-09-03 第三批②：1×1 透明离屏 Web——桥四引擎解析器载荷；
    // 与消息流同域 sibling，无布局影响）
    DocParserHost()
    // 内置浏览器隐形宿主（2026-09-16 内置浏览器 P1；2026-09-18 形态 B）：满视口透明 +
    // 命中穿透——视口语义（isInViewport / 懒加载）依赖真实视口尺寸；声明序在消息流之前 =
    // 被实体 UI 盖住（官方「被遮挡不终止行为」档，非屏幕外降级档，形态细节见 BrowseWeb
    // 头注释）；isPrivate 透传 = 隐私会话走 Web 隐私模式（Cookie 与缓存不落盘，宿主销毁
    // 即清）；与 DocParserHost 同域 sibling 无布局影响（勿挂别处——页面根/别的 @Builder
    // 会引入生命周期差异）
    BrowseHost({ isPrivate: this.isPrivate })
    ChatPageContent({
      dataSource: this.dataSource,
      listScroller: this.listScroller,
      followCtrl: this.follow,
      topPad: this.topPad,
      bottomPad: this.bottomPad,
      // 路由栈注入（2026-09-15 二级页化笔：附件查看器改导航栈内二级页，开页需 pushPathByName）
      pathStack: this.pathStack,
      busy: this.sending,
      dbReady: this.dbReady,
      errorText: this.errorText,
      attachments: this.attachments,
      // 单条消息指定技能（2026-09-16）：两值经 @Link 三链下发待发条渲染（父 @State →
      // ChatPageContent @Link → ChatInputBar @Link，坑16 正解通道——先例 thinkingValue）；
      // 清除回调 = 待发条 × 键（本地清两态，发送漏斗下次恒写）
      designatedSkillId: $designatedSkillId,
      designatedSkillName: $designatedSkillName,
      onClearDesignate: (): void => {
        this.designatedSkillId = '';
        this.designatedSkillName = '';
      },
      thinkingValue: $thinkingValue,
      // 标题栏思考键交互期（二百二十九）：输入栏收起守卫第三源（HDS 路径思考 chip 已退役）
      thinkingHold: $thinkingHold,
      modelLabel: $modelLabel,
      // 上下文用量圆环（2026-09-17）：值 @Link 下发（链第 1→2 层）+ 点击上行开面板
      ctxRingPct: $ctxRingPct,
      onOpenContext: (text: string): void => {
        this.openContextSheet(text);
      },
      fullInputDraft: this.fullInputDraft,
      fullInputCmd: this.fullInputCmd,
      onFullscreen: (text: string): void => {
        this.openFullInput(text);
      },
      onPickThinking: (option: string): void => {
        this.thinkingValue = option; // 选择落值驱动 chip 回显 + 经 refs 进请求（任务 B）
      },
      onSend: (text: string, attachments: PendingAttachment[]): boolean => {
        // 返回值原样透传（2026-09-15 发送链收口笔）：输入栏据此决定清不清草稿
        return this.sendWithAttachments(text);
      },
      onAbort: (): void => {
        this.sendCtrl.abort();
      },
      onAddFile: (): void => {
        // 附件与提示词面板入口（2026-09-04 隐私会话开放——决明指令「开放提示词选择与
        // 附件上传发送」：附件清理走既有防线（发送即删 + 离页 cleanupAttachments），
        // 提示词/助手选择无行会话走内存覆盖零写库；隐私语义「退出即全部删除」不变）
        this.sheetKind = 'prompt';
      },
      // 长文本粘贴转附件（2026-09-23 起；2026-09-24 扩到全屏面板——两处输入面同形）：转成即入列
      // 并 settle(true)，未入列 settle(false)。输入框文本的对齐由输入面按 settlePastedText 单源
      // 判据做（本处不碰草稿）；catch 兜底 = addPastedText 契约「永不 reject」万一破了也让收口跑到
      onPasteLongText: (text: string, settle: (converted: boolean) => void): void => {
        this.attachCtrl.addPastedText(text).then(settle).catch((): void => settle(false));
      },
      // 附件行删除（实现见 AttachmentPickCtrl.removePendingAttachment——缩略图释放、沙箱副本
      // 删除与数组去项三件成对，本地状态独占无网络副作用）
      onRemoveAttachment: (index: number): void => {
        this.attachments = removePendingAttachment(this.attachments, index);
      },
      onRetry: (): void => {
        if (this.isPrivate) {
          this.refreshPrivateConn(); // 同刷新：重建即清空，隐私会话只重读连接
          return;
        }
        this.loadCtrl.refreshPage();
      },
      onRetryTurn: (turnId: string): void => {
        // 失败轮重试占位（待接入清单第 6 件——将来接重发原文；文案与底栏重试键同源
        // RETRY_PLACEHOLDER_TEXT）
        this.getUIContext().getPromptAction().showToast({ message: RETRY_PLACEHOLDER_TEXT });
      },
      // ── 消息气泡底栏（2026-09-14；★ 2026-09-20 重试真链复活：接回 ChatSendCtrl.retryLast
      // 就地重答多版本保留——撤链笔 44e89bc/4953e99 取回点已兑现）──
      onRetryMsg: (msgId: string): void => {
        this.sendCtrl.retryLast(msgId);
      },
      // 版本切换键（2026-09-20 消息重新生成·多版本）：编排域在 ChatRetryCtrl.switchVariant
      //（读行全量 variants → 越界守卫 → 三列换版 → 内存原地改），经 sendCtrl 薄委托到达
      onVariantSwitch: (msgId: string, target: number): void => {
        this.sendCtrl.switchMessageVariant(msgId, target);
      },
      onMoreMenu: (msgId: string): void => {
        this.openMessageMenu(msgId);
      },
      privateSession: this.isPrivate,
      // ask_user 答案上行（2026-09-02 工具调用底层）：交互卡提交 → 执行轮挂起续跑
      onAskSubmit: (callId: string, answerJson: string): void => {
        this.sendCtrl.resolveAsk(callId, answerJson);
      },
      // browse_act 高危确认上行（2026-09-18 P2·B 单元）：确认卡作答 → 执行轮挂起续跑
      onBrowseConfirm: (callId: string, approved: boolean): void => {
        this.sendCtrl.resolveBrowseConfirm(callId, approved);
      },
      // 摘要提示行点击开上下文用量面板（2026-09-23 上下文压缩；三级链末端注入——
      // ChatMessageItem.onOpenUsage → ChatPageContent 透传 → 本方法）
      onOpenUsage: (): void => {
        this.openContextSheet('');
      },
      // 触顶翻页（2026-08-31 任务 D）：内容区触顶 → 游标前查 + 头部前插；锚点恢复在 ctrl 侧
      onLoadOlder: (): Promise<void> => this.loadCtrl.loadOlder()
    })
  }

  // 半模态面板内容（坑51 红线：bindSheet builder 位挂组件内 @Builder——if/else 分支链，
  // sheetKind 单面板多形态：全屏输入 / 模型选择 / 附件与提示词；组件直挂参数绑定自动
  // 刷新——坑75 族按值传参不刷新的正解）
  @Builder
  SheetHost() {
    if (this.sheetKind === 'model') {
      ModelPickerSheet({
        // 打勾/使用中徽章 = **本会话当前生效值**（conn 即解析链结果：会话覆盖 ?? 助手绑定 ??
        // 全局默认 ?? 首个启用）——★ 2026-09-10 会话级覆盖层笔：原面板读全局 active 两键，
        // 那正是「会话内选择被写成全局默认」的根因通道，已随键退役改直传
        selProviderId: this.conn !== null ? this.conn.providerId : '',
        selModelId: this.conn !== null ? this.conn.model : '',
        onPick: (providerId: string, modelId: string): void => {
          this.onPickModel(providerId, modelId);
        },
        onClose: (): void => {
          this.sheetKind = 'none';
        },
        bottomInset: this.bottomPad
      })
    } else if (this.sheetKind === 'prompt') { // 附件与提示词半模态（2026-08-30）
      ChatPromptSheet({ conversationId: this.conversationId, bottomInset: this.bottomPad,
        assistantBound: this.sendCtrl.boundAssistantId(),
        promptBound: this.sendCtrl.promptOverrideId(),
        // 「技能」卡显示态（2026-09-16 单条消息指定技能）：当前指定名 = 卡面「下一条消息：X」
        designateName: this.designatedSkillName,
        onPick: (kind: FilePickKind): void => { this.onPickAttachment(kind); },
        onOpenSkillPage: (): void => {
          // 第四卡点击（零参上行——组参由本页算）：关面板 → push 技能选择页
          this.openSkillDesignatePage();
        },
        onPromptChanged: (promptId: string, assistantId: string): void => {
          // 归属与注入并存（★2026-09-04 解耦）：两覆盖各自独立——选提示词不清助手归属、
          // 选助手不清提示词注入（有行会话面板侧另有落库，两态并存一致）
          this.sendCtrl.setBoundOverride(assistantId);
          this.sendCtrl.setPromptOverride(promptId);
          this.refreshWebSearchFlag(); // 换助手 = 联网上限可能变（换提示词不动上限，多刷一次无害）
        },
        onClose: (): void => { this.sheetKind = 'none'; } }) // 同 bindSheet 内切换选词
    } else if (this.sheetKind === 'context') {
      // 上下文用量（2026-09-17 会话上下文用量：输入条工具行圆环键入口；数据经 $ctxUsage
      // 绑定——活算落地自动刷新，重算中保留旧值不清空。★ 2026-09-23 上下文压缩：面板加
      // 压缩卡——refs 闭包供给消息流/截尾限/流式态（压缩域宿主接线薄层，域体在
      // CompressPreviewSheet / CompressGen / CompressDb）
      ContextUsageSheet({
        usage: $ctxUsage,
        conversationId: this.isPrivate ? '' : this.conversationId, // '' = 隐私会话，不渲染压缩卡
        allMessages: (): ChatMessage[] => this.dataSource.allMessages(),
        clipLimit: (): number => this.sendCtrl.assistantClipLimit(),
        sending: (): boolean => this.sending,
        onCompress: (): void => {
          this.compressCtrl.open();
        },
        onSummaryDeleted: (summaryId: string): void => {
          this.compressCtrl.summaryDeleted(summaryId);
        },
        onClose: (): void => { this.sheetKind = 'none'; },
        bottomInset: this.bottomPad
      })
    } else if (this.sheetKind === 'compress') {
      // 压缩预览（2026-09-23 上下文压缩：用量面板压缩卡入口；三态与落库见
      // CompressPreviewSheet——采用上行与关闭确认都交 compressCtrl）
      CompressPreviewSheet({
        refs: {
          conversationId: (): string => this.conversationId,
          allMessages: (): ChatMessage[] => this.dataSource.allMessages(),
          conn: (): AiConnection | null => this.conn
        },
        onRequestClose: (): void => {
          this.compressCtrl.requestClose();
        },
        onDraftState: (hasDraft: boolean): void => {
          this.compressCtrl.setDraftState(hasDraft);
        },
        onAdopted: (rowId: string, summaryText: string, coversToSeq: number): void => {
          this.compressCtrl.adopt(rowId, summaryText, coversToSeq);
        },
        bottomInset: this.bottomPad
      })
    } else if (this.sheetKind === 'stats') {
      // 会话统计（2026-09-19：标题栏更多菜单入口；usage 同 $ctxUsage 链——「上轮实际 /
      // Token 用量」两卡与上下文面板同源，消息/附件统计面板自装载）
      SessionStatsSheet({
        usage: $ctxUsage,
        conversationId: this.conversationId,
        onClose: (): void => { this.sheetKind = 'none'; },
        bottomInset: this.bottomPad
      })
    } else {
      KimiFullInputSheet({
        initial: this.fullInputInit,
        attachCount: this.attachments.length,
        bottomInset: this.bottomPad,
        onDraftChange: (text: string): void => {
          this.fullInputLive = text;
        },
        // 长文本粘贴转附件（面板侧，2026-09-24）：判定与收口判据与胶囊同源，见 refs 处同段注释
        onPasteLongText: (text: string, settle: (converted: boolean) => void): void => {
          this.attachCtrl.addPastedText(text).then(settle).catch((): void => settle(false));
        },
        onSend: (text: string): void => {
          // 面板发送 = 面板文本 + 胶囊当前已选附件；发送后胶囊经命令清空。
          // busy 守卫（2026-09-11 自检 P1）：面板发送键只知 canSend 不知 busy——流式中发送
          // 会被 send() 首守卫静默吞掉而下方草稿照清，用户误以为已发出。照键盘路径同款
          // toast、保留草稿与面板（ChatInputBar.onKeyboardSend 同语义）
          if (this.sending) {
            this.getUIContext().getPromptAction().showToast({ message: '当前请求进行中，发送已暂停' });
            return;
          }
          // ★ 2026-09-15 收口笔：清草稿与关面板按返回值收尾——未投递（解析阻断 / 无服务商
          // 等守卫拦下）时面板与文本原样留着（面板文本是面板自身 @State，不关就不丢）
          if (!this.sendWithAttachments(text)) {
            return;
          }
          this.applyFullInputDraft('');
          this.fullInputLive = '';
          this.sheetKind = 'none';
        },
        onClose: (): void => {
          // 「保存」/xmark：关闭即回写胶囊（live 实时上行，未发送编辑不丢）
          this.applyFullInputDraft(this.fullInputLive);
          this.sheetKind = 'none';
        }
      })
    }
  }

  build() {
    PageShell({
      // 标题栏无会话标题（2026-09-09 决明指令「取消会话内显示标题」——本页不显示会话标题，
      // 生成链与历史列表显示不变）；回退路径无覆盖层机制，隐私标记只能由标题文字承载
      title: this.isPrivate ? PRIVATE_SESSION_LABEL : '',
      // 会话页背景标记（2026-09-05「背景仅用于会话页」开关）：本页即对话页，开关开启
      // 时仍显示自定义背景（PageBackground suppressCustomBg 组合判定）
      bgSessionPage: true,
      // 页面重新显示重载助手绑定值（2026-09-08 P1-3 修复——语义与守卫见 onPageShown 注释）
      onShown: (): void => {
        this.onPageShown();
      },
      // 标题栏覆盖层（HDS 路径恒挂：模型胶囊 + 隐私标记 + 右上角合并胶囊——传入即主标题置空，
      // 本页标题恒空；回退路径无 stackBuilder 机制，模型入口与两键在菜单、隐私标记走标题文字，
      // 见 title 注释）
      titleBarStack: this.hdsAvailable ? (): void => {
        this.TitleBarContent();
      } : null,
      // 标题栏菜单（工厂在本文件——回退路径 menuNav 三键；★ 二百二十七：HDS 菜单数组退役
      //〔两键并入覆盖层合并胶囊 = 共用件 TitleBarKeys.TitleBarActionCapsule〕，menuHds 传 null）
      menuHds: null,
      menuNav: chatTitleMenuNav(
        (): void => {
          this.newConversation();
        },
        (): void => {
          this.openModelSheet();
        },
        (): void => {
          this.openMoreMenu();
        }),
      content: (): void => {
        this.Content();
      }
    })
      // 半模态面板（坑64 姿势 + 坑73 手势关闭收口）：model/input=LARGE 全屏单挡位 /
      // prompt/context=[MEDIUM, LARGE] 半屏起双停靠（context = 信息展示类非选择类，方案
      // §4.4 取半屏起可上拉）。★ 2026-09-15 两笔：①model 原吃 sheetPanelOptions 默认
      // [MEDIUM, LARGE]，按决明指令改 DETENTS_FULL（默认展开全屏 + 取消半屏态 + 下拉直接
      // 收起）；②prompt 原 [FIT_CONTENT, LARGE]（旧项目 FileSheet 同款——内容自适应包住
      // 卡片），按决明指令「改默认半屏、仍支持拉全屏」改 [MEDIUM, LARGE]（FIT_CONTENT 档位
      // 自此在本仓零在役消费者，档位选项本身仍可用，见规范-半模态 §4）；★ 2026-09-17 上下文
      // 用量笔：+context 同 prompt 档位（半屏起双停靠）
      .bindSheet(this.sheetKind !== 'none', this.SheetHost(), sheetPanelOptions(
        (action: DismissSheetAction): void => {
          // 手势关闭（下滑/遮罩/侧滑/三键 back）：压缩面板交压缩接线域统一确认——生成在途
          // 先问「停止本次压缩？」（确认即真中断），预览有草稿先问「放弃这次生成的摘要？」；
          // 确认未过时本回调不置 none，面板保持打开（官方：注册 onWillDismiss 后关闭由
          // 开发者在回调内决定）。其余分支直接收口（全屏输入回写胶囊 = 与面板 onClose 路
          // 同语句同效，未发送编辑不丢；模型选择无草稿）
          if (this.sheetKind === 'compress') {
            this.compressCtrl.requestClose();
            return;
          }
          if (this.sheetKind === 'input') {
            this.applyFullInputDraft(this.fullInputLive);
          }
          this.sheetKind = 'none';
        }, this.sheetKind === 'model' || this.sheetKind === 'input' ? DETENTS_FULL :
          (this.sheetKind === 'prompt' || this.sheetKind === 'context' ?
            [SheetSize.MEDIUM, SheetSize.LARGE] : DETENTS_FULL)))
  }
}
