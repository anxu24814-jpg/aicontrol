// 会话页生命周期编排与运行时面持有域件（自 ChatPage.ets 域级最小拆分——宪法 1200 硬线：
// ChatPage 剔头 1317 越线，进页加载链 / 退页释放链 / 重显刷新链与运行时 acquire/release
// 挂点整域外迁本件；方法体原样搬迁零行为变化）。
// 域定义一句话：**会话页宿主编排与运行时面取用**——进页 / 退页 / 重显三链编排（含屏幕
// 常亮、连接解析重触发与上下文用量供应）+ 生成运行态的取用（进页 acquire / 退页 release；
// sendCtrl 一族与数据源实例的持在 ChatSessionRuntime，页面侧经 getter 转发零改动）。
// ★ 退页不断流（行为口径）：
//   ① 进页 = 入园绑定（ensureRuntimeState）：acquire 取或建 + 运行态 refs 壳页面面绑定
//     （宿主即 ChatRuntimeUiBinding 实现）；复用既有运行态（重进重挂）时页面 @State 数据源
//     **换源**到运行态实例 + 发送态初值同步（busy 镜像运行态真值）；
//   ② 退页 = 只解绑不掐流（releaseRuntimeState）：refs 壳页面面改写为解绑安全实现（detachUi
//     ——惰性跟随器/锚判定器 + 冻结读值 + 空实现；**寿命匹配红线**：运行态跨页存活不得持
//     本页闭包）+ 引用计数递减（归零且非生成 → 运行时空闲回收）；展示态释放不挂本链（重进
//     重挂窗口内展示态必须存活）；
//   ③ 装载分叉：重进重挂 → loadCtrl.remountLive（不重建历史）；全新运行态 → loadHistory。
// ★ 换源时点红线（白屏实锤教训，勿再犯）：**重进换源必须发生在本页内容区首次构建之前**。
//   ChatPageContent 居 PageShell.content（@BuilderParam）冻结面（坑16 家族），其 @ObjectLink
//   dataSource 实例绑定创建期定死——首建用占位实例后，运行态实例换源写回不可达内容区
//  （实例替换非订阅通道）→ 快退快进白屏不恢复。曾把换源推迟到首帧后 post-frame 回调即
//   白屏，已回退；后续再攻首帧成本只走「不换实例」形态（如官方分帧渲染：数据源在场、
//   逐帧放量），勿再动换源时点。
// · 为何不能并入既有件（反碎片下限②申报）：无同域既有件可并——ChatPageLoadCtrl 是加载 /
//   刷新编排体（本件是它的消费侧，并回即自指）；ChatSheetCtrl / ChatSessionOverrideCtrl
//   各司面板开关与会话覆盖域。新开理由 = 本件自 ChatPage 的整体拆分（同批偿还该页硬线债）。
// · 页面侧留存边界：菜单宿主 init / dispose 与消息菜单 init 留 ChatPage（95 组菜单接线
//   契约；成对同侧可读性）；进页链的菜单首建不经本件。
// · 参数面 = 宿主回接接口（refs 闭包延迟求值；控制器一族按实例直传）；sendCtrl 的 refs 映射
//   = 宿主即 ChatRuntimeUiBinding 实现（running 期直传运行态 acquire），逐项同名同源。
import { FrameCallback, UIContext, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AiConnection, PendingAttachment } from '../../common/providers/AiTypes';
import { whenReady } from '../../common/store/ChatDb';
import { queryConversationAssistantId, historyFilterIds, ACTIVE_ASSISTANT_KEY,
  ASSISTANT_DEFAULT_ID } from '../../common/store/AssistantDb';
import { isKeepScreenOnEnabled } from '../../common/AppPreferences';
import { CHAT_LAUNCH_HANDOFF_KEY, SESSION_LIST_RELOAD_KEY, PROACTIVE_UNREAD_CONV_KEY }
  from '../../common/AppBroadcastKeys';
import { sinkMemoryForConversation } from '../../common/MemoryGen';
import { docParser } from '../../common/DocumentParse';
import { ocrRelease } from '../../common/OcrEngine';
import { ChatListAnchorJudge } from '../../common/chat/ChatListAnchorJudge';
import { consumePendingShareInto, cleanupAttachments, AttachmentPickCtrl } from './AttachmentPickCtrl';
// 会话草稿仓库（保存/恢复/归属门/剔死件单源在彼件）
import { NEW_DRAFT_KEY, DraftEntry, getDraft, hasDraft, saveDraftSnapshot,
  pruneDeadAttachments } from './ChatDraftStore';
import { refreshChatHeadInfo } from './ChatMessageHeader';
import { ContextUsage, contextPct } from './ChatContextUsage';
import { ChatDataSource } from './ChatDataSource';
import { ChatFollowController } from './ChatFollowController';
import { ChatSendCtrl, ChatSendRefs } from './ChatSendCtrl';
import { ChatSendQueueCtrl } from './ChatSendQueueCtrl';
import { ChatPageLoadCtrl } from './ChatPageLoad';
import { ChatSessionOverrideCtrl } from './ChatSessionOverrideCtrl';
import { ChatBranchCtrl } from './ChatBranchCtrl';
import { ChatAnswerCtrl } from './ChatAnswerCtrl';
// 进页打点（观测面，见 ChatEnterProbe）
import { markEnterProbe } from './ChatEnterProbe';
// 进页转场窗信号（掉帧修复刀②④：持让窗内置位、尾窗释放；正文解析与用量/上下文估算错峰）
import { scheduleChatTransitionHold, cancelChatTransition, chatTransitionDefer }
  from './ChatTransitionHold';
// ★ 运行时抽取 / 退页不断流：运行态账本单例（sendCtrl 一族与数据源实例的持在运行时；
// 页面面绑定/解绑经 bindUi/detachUi——见彼件头注释）
import { chatSessionRuntime, ChatRuntimeSeed, ChatRuntimeState, ChatRuntimeUiBinding,
  ChatRuntimeDetachedUi } from '../../common/chat/ChatSessionRuntime';

// ── 会话列表重拉去抖（数值型 kill 开关）──
// 为什么：leave() 落在 pop 转场窗内，SESSION_LIST_RELOAD_KEY 自增即刻触发列表全量重查 +
// 逐行比对，与返回转场竞争主线程；去抖把它挪出转场窗并合并快速连续退出为一次重拉。
// **只动 leave 这一处写点的「何时发」**——其余十余处 bump 写点与消费端两道缓冲（比对相等
// 跳过 / 在途闩）逐字保留。语义红线 = 最终一致不丢：尾沿去抖，静默期后必然发一次。
// 数值型 kill：0 = 立即同步自增直通（回退形态）；> 0 = 去抖窗毫秒数。★ 2026-11-15 掉帧修复
// 刀⑤开启 400：pop 转场约 300ms + 余量——列表重查挪出返回转场窗（消费端 R2-a 比对跳过 +
// R2-b 在途闩两道缓冲在案，最终一致不丢）；快速连续退出合并为一次重拉。真机列表刷新延迟
// 可感再调值。
const LEAVE_RELOAD_DEBOUNCE_MS: number = 400;
// 去抖挂起句柄（模块级单句柄 = 数据有界：任意时刻至多一个挂起计时器，-1 = 无挂起）。
// 先清后挂成对无泄漏；setTimeout 回调只写 AppStorage（不依赖页面存活）且零页面引用
//（闭包不持短寿命对象）
let leaveReloadDebounceHandle: number = -1;

// 会话列表重拉广播自增（去抖延迟路径单源；直通路径保留 leave 段内字面写点——assert-
// feature-domain 136 组钉锚定离页段内字面形态，两路写语句须逐字同——坑3 一次性计数器口径）
function bumpSessionListReloadKey(): void {
  AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
    (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
}

// 宿主回接接口（refs 闭包延迟求值——dbReady 等状态读总是当时值；控制器一族实例直传；
// extends ChatRuntimeUiBinding = 运行态 refs 壳的页面面整包直传，十二员逐项同名同源
//（成员清单见彼接口），acquire 直收本宿主）
export interface ChatPageLifecycleHost extends ChatRuntimeUiBinding {
  // 会话 id（控制台预绑定消费 / 未读清除判据 / 离页记忆沉淀）
  conversationId: () => string;
  // 系统分享路由 tick（本页创建时对应的分享桥批次号——重显消费判据，0 = 非分享拉起）
  shareTick: () => number;
  // UIContext（屏幕常亮窗口取用）
  ui: () => UIContext;
  setDbReady: (ok: boolean) => void;
  setErrorText: (text: string) => void;
  dbReady: () => boolean;
  // 本地新造会话进入标记（2026-11-18 乐观空态笔）：true = 本页会话 id 由本地 nextMessageId
  // 生成（无行、必然空）——enter 把它回写数据源 freshEntry，空态层不等读库回执即成立。
  // 普通成员入参（构造后不变），重进已有会话时恒 false = 自动清残留
  freshSession: () => boolean;
  attachments: () => PendingAttachment[];
  modelLabel: () => string;
  // 视觉能力现读（用量初算判据——与发送链同源 hasVisionCap(connCaps)，页面侧闭包承载）
  hasVisionNow: () => boolean;
  // 用量落地（usage + 占比一次写——@State 每项恰一次刷新）
  setUsagePct: (usage: ContextUsage | null, pct: number) => void;
  // 输入回写命令（分享文本进输入框——页面 applyFullInputDraft 覆盖式重写）
  applyFullInputDraft: (text: string) => void;
  // ── 数据源取用面（直引改闭包——重进重挂换源后一律现读）──
  // 消息数据源现读（实例归属运行时——经运行时工厂创建（ChatPage 字段初始化位）、acquire
  // 入园登记；本页生命周期内恒同一实例，重进重挂时换源为运行态既有实例；IDataSource/
  // LazyForEach 消费契约留页面侧，展示态释放挂运行时回收点）
  dataSource: () => ChatDataSource;
  // 数据源换源（重进重挂：页面 @State 置为运行态实例——@State 写必须回页面）
  replaceDataSource: (ds: ChatDataSource) => void;
  // ── 会话草稿 ──：draftKey = 本页草稿 key（restoreDraft 每页一次判定存页面普通成员，
  // 保存/恢复共用）；draftTextInput / draftQuoteText = 草稿文本与待发引用现读（同源同刻，
  // 保存链一次快照）；restoreDraftInput = 恢复写回（文本走 applyFullInputDraft 命令通道 +
  // 附件 @State 整组赋值 + 第三参回写页面 pendingQuote，照 restoreSendInput 形制）
  draftKey: () => string;
  // restoreDraft 的 key 判定写回（页面普通成员——保存/恢复/dispatchSend 修正三方共用同一份）
  setDraftKey: (key: string) => void;
  draftTextInput: () => string;
  draftQuoteText: () => string;
  restoreDraftInput: (text: string, attachments: PendingAttachment[], quoteText: string) => void;
  // ── 控制器一族（实例直传）──
  loadCtrl: ChatPageLoadCtrl;
  overrideCtrl: ChatSessionOverrideCtrl;
  attachCtrl: AttachmentPickCtrl;
  branchCtrl: ChatBranchCtrl;
  answerCtrl: ChatAnswerCtrl;
}

// 进页打点帧任务（换源已在内容区首建前完成，本回调 = 换源后首帧末尾——「内容第一眼」读数
// 口径。继承官方 FrameCallback 只重写 onIdle——「下一帧渲染任务结束后执行」，至少一帧完整
// 渲染后才回调，必达）。一次性（取走即清，迟到重复驱动自然免疫）。
// ★ 红线（换源白屏教训）：本回调只准承载观测面动作（打点）与**数据暴露面**动作（数据侧
//   状态不换实例）——换源/装载类功能面动作禁入（建面后回调内换源不可达内容区，见件头）
class ChatEnterFrame extends FrameCallback {
  private action: (() => void) | null;

  constructor(action: () => void) { super(); this.action = action; }

  onIdle(_timeLeftInNano: number): void {
    const action: (() => void) | null = this.action;
    this.action = null;
    if (action !== null) {
      action();
    }
  }
}

export class ChatPageLifecycle {
  private host: ChatPageLifecycleHost;
  // ── 生成运行态（sendCtrl 一族的构造与持在 ChatSessionRuntime）──本件只持本页绑定的
  //    运行态引用，sendCtrl 经下方 getter 转发（页面侧调用点零改动）。★ 退页 release 后
  //    本字段**刻意不置 null**：迟到的页面链（whenReady 链 / 异步收尾回调）与拆分前同语义
  //    ——恒达同一已 dispose 的 sendCtrl 实例（守卫吞掉），且不因置空触发重建僵尸账目；
  //    字段随页面对象一并消亡（账目真源在运行时 Map，release 时已除名，本引用只是残影）
  private runtimeState: ChatRuntimeState | null = null;
  // 退页已释出闸（release 计入引用计数——防 leave 重复调用双递减；字段不置 null 的僵尸
  // 账目防复用口径不变：迟到达经 sendCtrl getter 恒取同一运行态，不再 acquire）
  private released: boolean = false;
  // 已退页标志（1712 销毁守卫，2026-11-15 自检观察④修）：leave 首行置位——转场持让 defer
  // 回调（ctxUsage 初算）与 cancel 后 whenReady 迟到链的 defer 立即执行支首行判它跳过，省
  // computeContextUsage 白做段与向已销毁页面的迟到 @State 写。置位后不复位：本实例随页面
  // 退页后不再进入（重进 = 新页新实例；onReShown 是未 leave 的重显路径，恒见 false）
  private departed: boolean = false;
  // 本页所持转场持让窗代次（0 = 未开窗初值，schedule 自 1 起递增）：enter 开窗取代、leave
  // 按代丢弃——本页 pop 销毁收尾晚于下一页 push 置位时（框架销毁推迟，窗口交叠），代次已翻
  // ⇒ cancel 只丢本页代残留、不动新窗的 held 与兜底定时器（2026-11-15「立即重进空气泡」修）
  private transitionGen: number = 0;
  // 重进重挂标记（acquire 复用既有运行态且其数据源非本页占位实例 = 重挂——装载分叉与
  // 发送态初值同步读它）
  private remounted: boolean = false;
  // 解绑惰性跟随器（退页后 refs.follow 的落点——未 attach 的实例各入口早退；本页一次构造、
  // 随页面对象一并消亡，不跨页复用）
  private detachedFollow: ChatFollowController | null = null;
  // 用量重算并发守卫（旧结果不覆盖新结果；唯一写者 = refreshCtxUsage）
  private ctxUsageSeq: number = 0;

  constructor(host: ChatPageLifecycleHost) {
    this.host = host;
  }

  // 发送控制器到达面（运行态转发）。取建幂等：首取通常在 enter()；构造后 enter 前的任何
  // 到达（如 @Watch 早触发链）也恒见运行态实例（与拆分前「构造期即存在 sendCtrl」的可达
  // 语义对齐），未达即建
  get sendCtrl(): ChatSendCtrl {
    return this.ensureRuntimeState().sendCtrl;
  }

  // 排队域到达面（入口条注册/注销与排队半模态消费——随运行态种子入园，照 sendCtrl 形制；
  // 取建幂等同上方 getter，页面零反向 import 队列域实现）
  get queueCtrl(): ChatSendQueueCtrl {
    return this.ensureRuntimeState().queueCtrl;
  }

  // 运行态取建（幂等：已绑定直返；未绑定 = acquire 取或建——数据源实例由页面字段初始化位
  // 经运行时工厂创建、此处入园登记；★ 重进重挂：复用既有运行态时**同步换源**（页面 @State
  // 置为运行态实例——原占位实例弃用）。★ 换源时点红线（白屏实锤）：本方法由 enter
  //（aboutToAppear 链）同步调用，换源写回先于内容区首建——禁再推迟，机制见件头）
  private ensureRuntimeState(): ChatRuntimeState {
    const bound: ChatRuntimeState | null = this.runtimeState;
    if (bound !== null) {
      return bound;
    }
    const pageDs: ChatDataSource = this.host.dataSource();
    const state: ChatRuntimeState =
      chatSessionRuntime.acquire(this.host.conversationId(), pageDs, this.host,
        (dataSource: ChatDataSource, refs: ChatSendRefs): ChatRuntimeSeed => {
          // 一族装配（构造吃运行态 refs 壳——本件为宿主适配层；三件经一族到达面取出）
          const sendCtrl: ChatSendCtrl = new ChatSendCtrl(refs);
          return { sendCtrl: sendCtrl, flow: sendCtrl.flowCtrl(),
            keyRound: sendCtrl.keyRoundCtrl(), toolRound: sendCtrl.toolRoundCtrl(),
            queueCtrl: sendCtrl.queueCtrl() };
        });
    // ★ 锚初值 acquire 后无条件一次（2026-11-25 侧栏点卡漏帧与新会话滑不动笔，缺陷 B 根治
    //   面；原 2026-10-17 S1「换源分支前移」上提改判）：reset 自换源分支提到 acquire 之后、
    //   换源 if 之前——首建与换源同拍出锚 ⇒ 所有会话页 List 首建即 stackFromEnd(true)，流式
    //   期零翻档；并顺带消掉「冷进已有会话在 loadHistory 装完时翻真」的同族翻档。仍在本同步
    //   段、内容区首建之前（换源时点红线不破）。实参必须喂**全量口径** totalItemCount()——
    //   窗口化读口 totalCount()/displayCount() 回窗口值，窗口值 < COUNT_GATE 会把 anchored
    //   降格回 false 恰毁锚初值（该窗口域已退役，Theme.ets 进页窗口退役段有档，理由保留）
    this.host.anchorJudge.reset(state.dataSource.totalItemCount());
    if (state.dataSource !== pageDs) {
      // ★ 重进重挂换源（@State 写回页面——ChatPageContent @ObjectLink 与各闭包现读面随之
      // 切换）。锚 reset 已前移到 acquire 后无条件一次（见上方注释），本分支只剩 swap 打点
      // 与换源写回——全在本同步段、内容区首建之前（数据面动作非实例绑定写回，不破换源
      // 时点红线）
      this.remounted = true;
      // ★ 打点②：换源时刻
      markEnterProbe('swap');
      // ★ 进页折叠态复位：运行态复用跨页不清展开意愿会让长行整棵重建——必须在换源写回前
      // 清回默认收起（首建即在收起态）
      state.dataSource.resetLongMessageExpansion();
      this.host.replaceDataSource(state.dataSource);
    }
    this.runtimeState = state;
    return state;
  }

  // 运行态退页（只解绑不掐流）：refs 壳页面面先解绑（detachUi——页面对象可达性归还，
  // 寿命匹配红线）再引用计数递减（归零且非生成 → 运行时空闲回收）。幂等闸 released
  //（leave 内唯一调用点；字段不置 null 的僵尸账目防复用口径不变）
  private releaseRuntimeState(): void {
    const state: ChatRuntimeState | null = this.runtimeState;
    if (state === null || this.released) {
      return;
    }
    this.released = true;
    chatSessionRuntime.detachUi(state, this.buildDetachedUi());
    chatSessionRuntime.release(state);
  }

  // 解绑冻结片（退页时从当页取值——refs 壳页面面不改写自持页面闭包，只留值；见运行时
  // detachUi 注释。惰性跟随器：未 attach 的 ChatFollowController——ui/readLayout 恒 null，
  // 各入口早退，forceToBottom 的滚动调用落坑63 族静默）
  private buildDetachedUi(): ChatRuntimeDetachedUi {
    return {
      follow: this.detachedFollowNow(),
      anchorJudge: new ChatListAnchorJudge(),
      conn: this.host.conn(),
      thinking: this.host.thinking(),
      webSearchOn: this.host.webSearchOn(),
      sessionOverride: this.host.sessionOverride()
    };
  }

  private detachedFollowNow(): ChatFollowController {
    if (this.detachedFollow === null) {
      this.detachedFollow = new ChatFollowController(new Scroller());
    }
    return this.detachedFollow;
  }

  // ── 进页链（原 ChatPage.aboutToAppear 体；菜单首建两行留页面，见件头「页面侧留存边界」）──
  enter(): void {
    // ★ 打点①：壳面到达（进页链入口——tap→shell 段 = 路由推入）；携当页 follow 实例登记
    // 本窗 owner（打点件 anchor 只认本页跟随器——旧页销毁收尾的残存落位事件不入本窗，
    // 机制见 ChatEnterProbe 头注释）
    markEnterProbe('shell', this.host.follow);
    // ★ 掉帧修复刀②：转场持让窗开窗（进页即起算，尾窗 400ms 兜底释放——见 ChatTransitionHold
    // 件头）。必须在一切内容挂载之前：可见行 ChatMarkdownBody 首挂据此推迟解析+建块
    this.transitionGen = scheduleChatTransitionHold();
    // 运行态 acquire（取或建本会话运行态 + 入园绑定 + 复用路径**同步换源**——换源在本同步
    // 段、先于内容区首建，白屏实锤见件头）
    const state: ChatRuntimeState = this.ensureRuntimeState();
    // ★ 乐观空态标记回写（2026-11-18）：本页是否以「本地新造会话」进入——写进当页数据源，
    // 空态/蒙层判据经既有 @ObjectLink 通道消费（零新增订阅面）。必须在换源之后现读
    // host.dataSource()（重进重挂时页面 @State 已切到运行态实例）；每次进页按入参覆盖，
    // 重进已有会话自动归 false——这就是清残留的唯一机制，无需退页额外复位
    this.host.dataSource().freshEntry = this.host.freshSession();
    // ★ 启动衔接标记一次性消费（2026-11-24 启动页衔接笔）：只认 HomeNavigation「启动落点 =
    // 会话页」判定置位的本次进程首个会话页——读后清位，运行期点卡/新建进页恒 false（转场中
    // 不闪图标）。写进数据源经既有 @ObjectLink 通道驱动空态层首帧图标（零新增订阅面）
    const launchHandoff: boolean = AppStorage.get<boolean>(CHAT_LAUNCH_HANDOFF_KEY) === true;
    if (launchHandoff) {
      AppStorage.setOrCreate<boolean>(CHAT_LAUNCH_HANDOFF_KEY, false);
    }
    this.host.dataSource().launchHandoff = launchHandoff;
    if (this.remounted) {
      // ★ 打点③：换源后首帧帧回调（content = 内容第一眼口径）。打点属观测面：注册失败
      // 静默（不影响功能面，不呈报不打扰）；未武装时内部零动作直通现行行为
      try {
        this.host.ui().postFrameCallback(new ChatEnterFrame((): void => {
          markEnterProbe('content');
        }));
      } catch (error) {
        // 观测面静默（不影响功能面，不呈报不打扰）
      }
    }
    // 展示态释放回调登记（直引改闭包后必须晚于换源——登记到页面终态数据源上）
    this.host.loadCtrl.attachDisplayState();
    // 发送态初值同步（重进重挂：运行态仍在生成 → 输入栏 busy 镜像即真——运行态
    // sendingFlag 为跨页真值，页面 @State 只是镜像）
    this.host.setSending(state.sendingFlag);
    // DB 就绪等待（EntryAbility 异步初始化；未就绪禁发送并提示——禁同步等库）。标题查询与
    // 连接解析原在守卫外直查，冷启动 DB 未就绪时与会话列表同族竞态——一并挪入就绪分支
    //（见 ChatPageLoad 注释）
    whenReady().then((ok: boolean): void => {
      this.host.setDbReady(ok);
      // 库就绪粘滞位回写（运行态跨页保持——finishStream 提交门与工具轮提交门读它，重进
      // 窗口读页面新初始值会误跳提交，见运行时 dbReadyFlag 字段注释）
      chatSessionRuntime.markDbReady(state, ok);
      if (!ok) {
        this.host.setErrorText('数据库初始化失败，发送功能已禁用');
        return;
      }
      //（原「询问控制台助手」预绑定段已随控制台合并退役；新会话走 effectiveAssistantId 兜底）
      this.host.loadCtrl.reloadConn();
      // ★ 装载分叉：重进且**仍在生成** → remountLive（不重建历史：运行态数据源即屏上真源
      //   ——退页不断流的功能本体）；其余（含空闲重进）→ loadHistory 全量读库。原「流结束
      //   后 5 秒内重进不读库直接重挂」捷径已退役（把全量物化搬进退页转场首帧，是历史
      //  「重进更慢」的直接元凶）；单一路径与冷进行为一致、无分裂
      if (this.remounted && state.sendingFlag) {
        this.host.loadCtrl.remountLive();
      } else {
        this.host.loadCtrl.loadHistory();
      }
      // 提示词注入预载（会话引用/系统提示词解析缓存，面板选择后经 onPromptChanged 刷新；
      // 完成后写联网两键——chip 可点判定 + 生效值）
      this.host.overrideCtrl.refreshWebSearchFlag();
      // 草稿恢复（★时机红线 = 必在 whenReady 异步链内、不能在 aboutToAppear 同步段——
      // ChatInputBar 晚于宿主创建，同步段恢复会被子组件初值创建吞掉（坑16 家族）；每页实例
      // 恰一次，onShown 重复触发会覆写用户已改文本故不用）
      this.restoreDraft();
      // 上下文圆环初算（reloadConn 完成后 setConnInfo 会再刷一次——本处覆盖「连接解析失败
      // 仍可算固定开销段」的场景；历史就绪后的确定性重算在 onHistorySettled 收尾点）。
      // ★ 掉帧修复刀④：computeLive 全历史组装 + token 估算的 JS 段错峰出转场窗（重算中圆环
      // 保留旧值不清空——契约在案，晚到不可见）。首行 departed 判（1712，2026-11-15 自检
      // 观察④修）：窗内退出被退页丢弃天然跳过；cancel 后 whenReady 迟到 resolve 的立即
      // 执行支靠本判跳过——省白做段与向已销毁页面的迟到 @State 写
      chatTransitionDefer((): void => {
        if (this.departed) {
          return;
        }
        this.refreshCtxUsage();
      });
    });
    // 会话页屏幕常亮：按偏好设置开——默认关 = 系统息屏零回归；成对复位见 leave()
    this.applyKeepScreenOn(isKeepScreenOnEnabled());
  }

  // ── 退页释放链（原 ChatPage.aboutToDisappear 体；菜单 dispose 两行留页面成对）──
  leave(): void {
    // 已退页标志置位（1712）：先于一切——下方转场持让丢弃后，whenReady 迟到链再注册的
    // defer 回调（立即执行支）靠它跳过（见 departed 字段注释）
    this.departed = true;
    // 页面存活标记置位：先置位，其后到达的刷新链一律不写广播键（域件 markDeparted，
    // 见彼件字段注释）
    this.host.overrideCtrl.markDeparted();
    // ★ 掉帧修复刀②：转场持让退页按代丢弃（幂等；**丢弃 pending 不执行**——白做段直接省，
    // 不依赖取消闸开关〔默认关恒 false，执行式释放的守卫跳过不成立〕；各注册者销毁兜底
    // 自清位，如 ChatMarkdownBody 的骨架位直调）。★ 代次守卫（2026-11-15 P0 回归修）：本页
    // 销毁收尾晚于下一页 push 置位时，cancel 只丢本页代残留——不得清新窗的兜底定时器与
    // pending（误清 = 新窗首屏 defer 行永卡骨架 =「立即重进空气泡」）；同代正常全清（清定时器
    // 防迟到释放落在下一页窗口内）。持让回调表寿命就此封顶（见 ChatTransitionHold 件头）
    cancelChatTransition(this.transitionGen);
    // ★ 装载链退出取消闸·置闸点 B（兜底完备位）：程序化 pop/replace 等不经返回键的退出路径
    // 由本点兜住（与置闸点 A 幂等双保险）。框架销毁推迟期装载残余链仍在跑：本闸令其检查点
    // 早退省掉白做段；kill 开关默认关零行为；闸语义单源见 ChatPageLoadCtrl 头部取消闸注释；
    // sinkMemoryForConversation（本链末段）不纳入闸（记忆域功能链，动它属跨域）
    this.host.loadCtrl.cancelHistoryLoad();
    // 蒙层首屏兜底定时器成对取消（★ 2026-11-18 D3 修复，与上方置闸并列：1s 内退页防旧页
    // 兜底定时器把 entryFirstScreenReady=true 迟到写进仍被新页蒙层消费的运行态数据源；
    // 幂等；不并入 cancelHistoryLoad——彼方法有 kill 门控默认关会吞掉清理，方案档 §8-12）
    this.host.loadCtrl.cancelEntryReadyFallbackTimer();
    // 会话页屏幕常亮复位（成对：进页按偏好设置开，此处无条件关——窗口属性进程级不随组件
    // 销毁复原，不复位则常亮态泄漏到列表/设置等其他页面）
    this.applyKeepScreenOn(false);
    // 退页不断流：生成寿命动作不掐流——页面面解绑（detachUi）与引用计数递减在
    // releaseRuntimeState（运行态生成照常，回调目标本就非页面）；数据源展示态释放也不挂
    // 本链（归运行态回收点——重进重挂窗口内展示态必须存活）
    this.releaseRuntimeState();
    // 文档解析兜底取消（宿主 Web 随页面销毁，进行中解析停止）
    docParser.cancelCurrentParse();
    // 系统识别引擎释放（与 OcrEngine 懒 init 成对——建立与释放在「消费方页面生命周期」
    // 一对事件上）
    ocrRelease();
    // 草稿快照保存（★顺序契约 = 必须先于下方附件清删——「有草稿跳删」依赖保存已发生
    //（先删文件后保存 = 草稿引用死件）；且天然先于本链末段的列表重拉广播，同一同步序保证
    // 列表 reload 重查时读到新草稿）
    this.saveDraftFromHost();
    // 未发送附件清删（缩略图 + 沙箱副本——附件不跨页面驻留；发送路径的清理在 ChatSendCtrl）。
    // ★ 有草稿时跳删：上方保存已发生，条目在场即「有草稿」——缩略图留仓、副本留盘供恢复
    // 引用；draftKey='' 窗口（DB 未就绪）一律照删（'__new__' 槽可能是他助手旧条目）；归属
    // 命中同助手子情形同样照删（快照已入 '__new__' 文本保留，恢复时剔死件只恢复文本）——
    // 仅极端组合（DB 未就绪 + 附件 + 退出）受损，登记接受
    const keepForDraft: boolean = this.host.draftKey() !== '' && hasDraft(this.host.draftKey());
    if (!keepForDraft) {
      cleanupAttachments(this.host.attachments());
    }
    // 回答控制器页面寿命释放：清 sink / 读结果 / 待办身份，在途读按代次作废（先于数据源
    // 销毁声明——控制器不持已销毁页面引用）
    this.host.answerCtrl.dispose();
    // 会话列表重拉广播（pop/replace 均触发；AppStorage 一次性计数器，坑3 口径——与组件树
    // 层级无关）。★ 重拉出窗去抖：= 0 立即同步自增 = 现行逐字同；> 0 尾沿去抖（连续退出只
    // 重置窗口，静默期后必然发一次，最终一致不丢）。与 R2-b 闩正交（去抖减 tick 次数，闩兜
    // 同帧并发）
    if (LEAVE_RELOAD_DEBOUNCE_MS <= 0) {
      // kill 关（默认）：立即同步自增——写语句与现行逐字同
      AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
        (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
    } else {
      // kill 开：先清旧句柄再挂新计时器（尾沿去抖）。回调只写 AppStorage 零页面引用
      //（内存红线）；回调首句复位句柄归位 -1——保「-1 = 无挂起」契约恒真
      clearTimeout(leaveReloadDebounceHandle);
      leaveReloadDebounceHandle = setTimeout((): void => {
        leaveReloadDebounceHandle = -1;
        bumpSessionListReloadKey();
      }, LEAVE_RELOAD_DEBOUNCE_MS);
    }
    // 记忆沉淀：退出会话 fire-and-forget 一次（内部守卫序〔总开关/自动整理/助手沉淀开关/
    // 模型键〕全在 MemoryGen，全链不 toast 不打扰）
    sinkMemoryForConversation(this.host.conversationId());
  }

  // ── 会话草稿保存（leave 保存与新会话动作点保存双触发共用，幂等——后到者保存同值或
  //     空快照转清）──
  // 归属助手现读（与 ensureConversation 落行绑定同源：发送域绑定 ?? 当前助手 ?? 默认）
  private resolveDraftAssistantId(): string {
    const bound: string = this.sendCtrl.boundAssistantId();
    if (bound !== '') {
      return bound;
    }
    return AppStorage.get<string>(ACTIVE_ASSISTANT_KEY) ?? ASSISTANT_DEFAULT_ID;
  }

  saveDraftFromHost(): void {
    const key: string = this.host.draftKey();
    const text: string = this.host.draftTextInput();
    // 待发引用随草稿保存：与文本同刻快照——纯引用（文本空）也是草稿内容，非空判据与
    // 空快照转清均在 ChatDraftStore 单源
    const quote: string = this.host.draftQuoteText();
    if (key === '') {
      // ★ draftKey='' 窗口兜底（DB 未就绪窗口内输入并退出）：该窗口进不了既有会话（进既有
      // 会话必经列表、列表本身等 DB；现实路径 = 冷启动直进新会话/分享拉起），故「内容非空 →
      // 存 '__new__' 槽」语义恒正确；空内容零动作
      if (text.trim() !== '' || this.host.attachments().length > 0 || quote.trim() !== '') {
        saveDraftSnapshot(NEW_DRAFT_KEY, text, this.host.attachments(),
          this.resolveDraftAssistantId(), quote);
      }
      return;
    }
    saveDraftSnapshot(key, text, this.host.attachments(), this.resolveDraftAssistantId(), quote);
  }

  // 草稿恢复（挂 enter 的 whenReady 链——时机红线见调用点注释；保存/恢复共用 host.draftKey，
  // 本方法每页实例恰一次完成 key 判定）
  private restoreDraft(): void {
    const conversationId: string = this.host.conversationId();
    queryConversationAssistantId(conversationId).then((owner: string | null): void => {
      // ① key 判定 = DB 行存在性（客观事实判据——'' 未显式绑定也是行在 → 会话键；比「最近
      // 新建 id 登记」稳：叠栈/重复进出会让标记漂移误判）；单行主键查询毫秒级
      const key: string = owner === null ? NEW_DRAFT_KEY : conversationId;
      this.host.setDraftKey(key);
      // ② 无条目零动作（不覆写、不恢复）
      const entry: DraftEntry | undefined = getDraft(key);
      if (entry === undefined) {
        return;
      }
      // ③ 归属门（仅 '__new__' 槽）：他助手的新会话草稿不恢复——条目保留，切回该助手仍可用
      //（会话键不设门：会话身份自证）
      if (key === NEW_DRAFT_KEY
        && !historyFilterIds(this.resolveDraftAssistantId()).includes(entry.assistantId)) {
        return;
      }
      // ④ 剔死件：fs.accessSync 逐件校验元数据引用，恢复的引用全部真实可达
      const atts: PendingAttachment[] = pruneDeadAttachments(entry.attachments);
      // ⑤ 恢复 = 复用 restoreSendInput 通道形制（文本经 applyFullInputDraft 命令通道覆盖
      //（@Watch 顺带回写 draftTextLive）+ 附件 @State 整组赋值，与选择入列同链）；引用经
      // 第三参回写页面 pendingQuote——输入侧引用条随恢复重现
      this.host.restoreDraftInput(entry.text, atts, entry.quoteText);
      // ⑥ 恢复不删 Map 条目：本页编辑期间条目为上次快照，leave/newSession 覆盖保存
    }).catch((): void => {
      // 行存在性查询失败：draftKey 留 ''——leave 保存走 '__new__' 窗口兜底（内容非空不丢）
      hilog.warn(0xD5A0, 'ChatPageLifecycle', '草稿 key 判定查询失败，按新会话口径兜底');
    });
  }

  // ── 转场前静默 ──
  // 链路头（页面 onWillDisappear 接线直调）：pop 转场开始即停跟随帧驱动与揭示节拍——静默位
  // 落页面共持的 FollowCtrl（内容件经 setSilenceListener 停/启自身帧驱动，发布层揭示停拍经
  // refs.follow.isSilenced 只读透传）；**只停驱动不解绑不释放**（静默≠销毁）。解冻 =
  // onReShown 首行 resume（坑25 可靠姿势：每次页面显示触发，转场取消/回显必须解冻）；真
  // pop 走完由退页链 detachUi 换挂惰性跟随器天然脱离静默位，无残留冻结
  silenceForTransition(): void {
    // 本点只停跟随帧驱动
    this.host.follow.silence();
  }

  // ── 装载链退出取消闸·置闸点 A（交互层及时位）──
  // 官方返回键/系统侧滑退出在转场开始前置闸（ChatPage 经 PageShell.onBackPressed 接线；
  // 恒返 false = 不拦截官方返回照常 pop）。置位点不能只挂 leave/aboutToDisappear：框架
  // 销毁推迟落新窗，白做段会先跑完闸才置位——本点才是及时位。
  // ★ 不在 onWillDisappear/silenceForTransition 置闸：该钩子被子页 push 覆盖也触发，直接
  //   置闸会误杀「进会话→立即开子页」场景的装载链；onBackPressed 只在真返回时触发无此面。
  //   置闸点 B（兜底）在 leave()；复位点在 onReShown 首部；闸语义单源见 ChatPageLoadCtrl
  onBackPressedExitGate(): boolean {
    this.host.loadCtrl.cancelHistoryLoad();
    return false;
  }

  // ── 重显刷新链（原 ChatPage.onPageShown 体；页面 onShown 接线直调本方法）──
  onReShown(): void {
    // 转场静默解冻：必须在任何早退支之前——转场取消/后台回显即解冻，跟随原样恢复（静默期
    // 未清跟随意图；未静默时本行自守零动作）
    this.host.follow.resume();
    // 错峰同帧置位：消息区渐显与壁纸同帧起播——本链与 PageShell onShown 内 bumpBgShownEpoch
    // 同回调栈，dataSource.shellArrived 经 @Track 与壁纸 bgRevealed 同帧翻转；置位放 dbReady
    // 分支之前保必达（onShown 官方显示必回调 = 置位必达；pop 返回/重挂复用实例保持 true 直显
    // 不重播）。★「同帧起播」仅当内容就绪早于本次显示；装载慢时消息区等就绪即播（后于壁纸）
    //——壁纸先行内容后到是数据到达顺序使然，非缺陷（见 ChatDataSource 注释）
    this.host.dataSource().shellArrived = true;
    // ★ 装载链退出取消闸·复位点：转场取消回显（侧滑中途反悔）时闸已置但页面仍存活——
    // 复位闸 + 被截断的 fresh 装载重发（判据与重发单源在 loadCtrl.resumeHistoryLoadIfCancelled；
    // 闸未置 = 正常首显/子页返回，内部零动作直通）
    this.host.loadCtrl.resumeHistoryLoadIfCancelled();
    // 清主动消息未读（进入该会话即清——含 pop 返回重显场景；纯 AppStorage 写不依赖库就绪，
    // 故置于 dbReady 守卫之前；清空路径全仓唯一〔写侧 = ProactiveGen 落库覆盖，清除侧 = 本处〕）
    if ((AppStorage.get<string>(PROACTIVE_UNREAD_CONV_KEY) ?? '') === this.host.conversationId()) {
      AppStorage.setOrCreate<string>(PROACTIVE_UNREAD_CONV_KEY, '');
    }
    // 系统分享接收：待发分享件一次性消费（文件件入列 / 文本件进输入框）——判据与入列全在
    // AttachmentPickCtrl.consumePendingShareInto 域函数单源。挂重显时点而非进页：
    // fullInputCmd @Watch 首次不触发（ChatInputBar 注释），build 前经 applyFullInputDraft 写
    // 输入框不上屏；重复 onShown 幂等（消费即清桥 + tick 匹配判据，域函数内守）
    consumePendingShareInto(this.host.shareTick(), this.host.attachCtrl,
      (text: string): void => this.host.applyFullInputDraft(text));
    if (!this.host.dbReady()) {
      return;
    }
    this.host.overrideCtrl.refreshWebSearchFlag();
    // 消息时间头·助手名与头像补刷：子页改助手（改名/换头像）返回即新值——reloadConn 之外
    // 的第二触发点（等价 onShown 对提示词态的兜底语义）
    refreshChatHeadInfo((): string => this.sendCtrl.boundAssistantId(), this.host.modelLabel());
    // 上下文圆环随页面重显重算（子页改提示词/技能/助手后返回即刷——组装输入变了；
    // onShown 是坑25 定稿的可靠姿势）
    this.refreshCtxUsage();
  }

  // 连接解析重触发（原 ChatPage.onConnResolveTick @Watch 体；页面 @Watch 薄委托到家）
  onConnResolved(): void {
    this.host.loadCtrl.reloadConn();
  }

  // 屏幕常亮开关（窗口级属性 setWindowKeepScreenOn，@ohos.window @since 9，无需权限）。
  // getLastWindow 单窗口恒同实例；失败只打日志不静默（P0-1）——降级 = 照常系统息屏
  applyKeepScreenOn(on: boolean): void {
    const hostContext: common.UIAbilityContext | undefined =
      this.host.ui().getHostContext() as common.UIAbilityContext | undefined;
    if (!hostContext) {
      return;
    }
    window.getLastWindow(hostContext).then((win: window.Window): Promise<void> => {
      return win.setWindowKeepScreenOn(on);
    }).catch((err: Error) => {
      hilog.error(0xD5A0, 'ChatPageLifecycle', 'setKeepScreenOn failed: %{public}s', JSON.stringify(err));
    });
  }

  // ═══ 上下文用量供应 ═══
  // 刷新点收敛：进页 / 切模型（setConnInfo 同点）/ 历史加载收尾（onHistorySettled——进页
  // 三链竞态的确定性收口）/ 页面重显（onReShown——子页改提示词、技能、助手返回即刷）/
  // 轮次收尾（onRoundSettled——真值到达 = 最准时刻）/ 开面板（带草稿，ChatSheetCtrl →
  // 页面代理）。打字与生成中不刷。★ 重算进行中与失败均保留旧值不清空（防新数据未就绪
  // 计数先掉假低值）；seq 守卫防旧结果覆盖新结果。
  // 待发附件数组与 hasVision（判据同发送链视觉门控，禁另立口径）随参下传——计算收归域件
  // 单源（AttachmentUtil.pendingAttachFootprint），本件不再自算
  refreshCtxUsage(draftText: string = ''): void {
    const seq: number = ++this.ctxUsageSeq;
    const hasVision: boolean = this.host.hasVisionNow();
    this.sendCtrl.computeContextUsage(draftText, this.host.attachments(), hasVision)
      .then((usage: ContextUsage): void => {
        if (seq !== this.ctxUsageSeq) {
          return;
        }
        this.host.setUsagePct(usage, contextPct(usage));
      })
      .catch((): void => {
        // 活算失败保持旧值（不静默翻转为空环——refreshWebSearchFlag 同姿势）
      });
  }
}
