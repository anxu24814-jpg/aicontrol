// 会话生成运行时：**按会话登记的生成运行态账本**——Map<conversationId, 运行态>，运行态持有
// 「消息数据源实例 + refs 壳（sendCtrl 一族共享）+ ChatSendCtrl 一族（sendCtrl 为族根，
// flow/keyRound/toolRound 三件直达）」，页面只是运行态的取用者与订阅者（进页 acquire /
// 退页 release）。核心语义：**退页不断流 + 重进重挂 + 空闲回收**（生成寿命账本，非页面寿命账本）。
// 职责：newDataSource（实例创建单一入口）；acquire（取或建 + 入园绑定，引用计数 +1、
//   撤销空闲回收）；bindUi/detachUi（refs 壳页面面改写，同一 refs 对象原地改写零重建）；
//   get/isGenerating（只读现读与生成中判据）；release（计数 −1，★ **只解绑不掐流**——
//   解绑后生成照常跑在运行时权威态；归零且非生成 → 空闲回收）；生成收尾钩子（运行态粘滞写
//   + 广播列表刷新 + 评估回收）；重启恢复待答集（启动期 prime / 提交期 clear，不喂活跃计数）；
//   活跃计数挂短时任务（setSending 每笔写后现算 activeRunCount 同步 chatBgReply，0→≥1 申请、
//   ≥1→0 取消）；超时兜底收口（构造期绑 chatBgReply 超时回调 → 逐活跃会话 interrupted 收口，
//   本件对 chatBgReply 单向依赖零回边）。
// 互斥分工：同会话单活跃 run 互斥仍在 ChatSendCtrl 内部 chatRunScope 承担，本件零第二套锁。
// setSending 边沿观察者（prev≠next 上报，回调注入防反向依赖队列域）+ lastSettleCause 轮终态
//   内存快照真值面（写方 finishStream 入口、读方队列域，均经 refs 壳读写口）。
// uiBinding 单槽不覆写（web 无头宿主走独立槽 headlessBinding）+ roundOrigin 轮发起端标记
//   （缺省 'local'，web 宿主发送前置 'web'，setSending(false) 终态复位；读点 = ChatLiveHub
//   三挂点发布信封 origin）。
// ★ 寿命匹配红线：运行态跨页存活后不得持页面对象引用（长期持短寿命 = ArkTS 最常见泄漏形态），
//   detachUi 解绑即页面对象可达性归还。
// 分层申报（common → components 反向 import）：值引 ChatDataSource + 类型引五件（全数
//   type-only 编译期擦除）；本件对 components 侧单向零回边（无环）。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AiConnection, PendingAttachment } from '../providers/AiTypes';
import { ConversationOverride } from '../store/ChatDb';
import { SESSION_LIST_RELOAD_KEY } from '../AppBroadcastKeys';
import { chatBgReply } from './ChatBgReply';
import { ChatListAnchorJudge } from './ChatListAnchorJudge';
import { ChatDataSource } from '../../components/chat/ChatDataSource';
import { ChatSendCtrl, ChatSendRefs } from '../../components/chat/ChatSendCtrl';
import { ChatSendQueueCtrl } from '../../components/chat/ChatSendQueueCtrl';
import { ChatStreamFlowCtrl } from '../../components/chat/ChatStreamFlowCtrl';
import { ChatKeyRoundCtrl } from '../../components/chat/ChatKeyRoundCtrl';
import { ChatToolRoundCtrl } from '../../components/chat/ChatToolRoundCtrl';
import { ChatFollowController } from '../../components/chat/ChatFollowController';

// 空闲回收时限（ms）。生成中永不回收：回收只由收尾钩子/退页两路评估，且评估恒查 sendingFlag。
export const IDLE_RECLAIM_MS: number = 5000;

// 建族告知观察者上限（生产链只有直播中枢一枚，留余量；有界硬线兼作误用探针）
const ACQUIRE_WATCHER_LIMIT: number = 8;

// 轮发起端标记值域：chat 域自持字符串字面量类型——**禁引 web 域类型**（零环红线：web 域 →
// chat 域单向）。唯一写方 = 无头宿主发送前置 'web'（轮终态由 setSending(false) 复位 'local'），
// 页面链不写即缺省 'local'；读点 = ChatLiveHub 发布信封按同值域读。
export type ChatRuntimeRoundOrigin = 'local' | 'web';

// 运行态创建片（页面侧工厂产物）：sendCtrl 一族四件直达引用登记（flow/keyRound/toolRound
// 本就私有在 sendCtrl 内，零第二写口）
export interface ChatRuntimeSeed {
  readonly sendCtrl: ChatSendCtrl;
  readonly flow: ChatStreamFlowCtrl;
  readonly keyRound: ChatKeyRoundCtrl;
  readonly toolRound: ChatToolRoundCtrl;
  // 排队域随族入园：入口条/半模态消费方经运行态只读到达面取引用（页面不反向 import 队列域
  // 实现；写面全在队列域）
  readonly queueCtrl: ChatSendQueueCtrl;
}

// 页面 UI 绑定（进页/重进时由 ChatPageLifecycle 装入 refs 壳）：全部为页面侧实现。
// ★ 本接口同时是 ChatPageLifecycleHost 的超集面（宿主 extends 直传——组件侧零胶水）。
export interface ChatRuntimeUiBinding {
  // 流式滚动跟随（页面持有，与列表 scroller 同源）
  follow: ChatFollowController;
  // 消息 List 锚态判定器（页面 @State 直引用）
  anchorJudge: ChatListAnchorJudge;
  conn: () => AiConnection | null;
  thinking: () => string;
  webSearchOn: () => boolean;
  // 无行会话的会话级覆盖（首条消息落行时写入 conversations 覆盖三列）
  sessionOverride: () => ConversationOverride | null;
  // 发送态镜像（页面 @State sending——运行态真值另存 sendingFlag，本回调只驱动 UI）
  setSending: (sending: boolean) => void;
  clearError: () => void;
  toast: (message: string) => void;
  // 轮次收尾通知（done/error 两路——页面据此重算上下文圆环 + 编辑引用回挂）
  onRoundSettled: () => void;
  // 当前分支路径视图重载（重试域消费；false = 视图未换源）
  reloadBranchPath: () => Promise<boolean>;
  // 拒发归还输入
  restoreSendInput: (text: string, attachments: PendingAttachment[]) => void;
  // 待发引用读口：宿主回页面 pendingQuote 现值（'' = 无引用，dispatchSend 入口快照消费）；
  // 真源挂页面 @State、@Link 链下行（宿主闭包可达性所迫的挂点形态）
  pendingQuote: () => string;
  // 待发引用清口（beginSend resolve 冻结比对清空消费——发送成功才清，失败保留）
  clearPendingQuote: () => void;
}

// 解绑冻结片（退页时由 ChatPageLifecycle 从当页取值）：两实例（惰性跟随器/锚判定器）+
// 四枚冻结读值——页面对象经此完整脱钩（读口只留值，回调只留空实现）。
export interface ChatRuntimeDetachedUi {
  follow: ChatFollowController;
  anchorJudge: ChatListAnchorJudge;
  conn: AiConnection | null;
  thinking: string;
  webSearchOn: boolean;
  sessionOverride: ConversationOverride | null;
}

// 运行态（按会话一条）：消息数据源实例 + refs 壳 + 发送控制器一族（族根 + 三件直达）
export interface ChatRuntimeState {
  readonly conversationId: string;
  // 消息数据源（创建入口 = 运行时工厂、运行态登记持有；页面 @State 与各域 refs 消费同一
  // 实例；寿命释放挂运行时回收点 reclaim）
  readonly dataSource: ChatDataSource;
  // refs 壳：sendCtrl 一族各域件与本件共享的同一对象——绑定/解绑 = 改写本对象成员（零重建，
  // 各持有方即时可见）；dataSource/conversationId/sending/setSending/dbReady/onRoundSettled
  // 六员为运行态自有（跨页粘滞），其余为页面面（bindUi/detachUi 改写）
  readonly refs: ChatSendRefs;
  // 发送控制器（族根——含流回调/工具轮/Key 池/重试/自动重试全部子域）
  readonly sendCtrl: ChatSendCtrl;
  // 族三件直达（只读引用）
  readonly flow: ChatStreamFlowCtrl;
  readonly keyRound: ChatKeyRoundCtrl;
  readonly toolRound: ChatToolRoundCtrl;
  // 排队域直达（只读到达面；生命周期随 sendCtrl 一族回收）
  readonly queueCtrl: ChatSendQueueCtrl;
  // 在列页面数（引用计数：acquire +1 / release −1；归零且非生成才可回收）
  attached: number;
  // 生成中真值（setSending 写；页面 @State 只是镜像）——空闲回收免疫判据 + 会话列表 loading 判据
  sendingFlag: boolean;
  // 轮发起端标记：'local' 缺省 = 页面发起；'web' = web 无头宿主发起（写口 setRoundOrigin）。
  // 载体选 state 非 refs：ChatSendRefs 在 ChatSendCtrl.ets（零触碰门禁），加员即触碰且 send
  // 入口无 origin 参数链。并发面 = 同会话 chatRunScope 进程级串行保证「置位 → 起轮 → 读」
  // 无并发覆盖，跨会话各 state 独立
  roundOrigin: ChatRuntimeRoundOrigin;
  // 无头宿主 UI 绑定槽：离屏绑定独立存放——uiBinding 单槽只归页面（双端同屏不覆写页面活
  // 绑定）；页面不在场时本槽回装 refs 页面面（离屏发送链读口可达）；releaseHeadless 清槽
  headlessBinding: ChatRuntimeUiBinding | null;
  // 库就绪粘滞位（页面 whenReady 结果回写；跨页保持——finishStream/工具轮提交门读它，
  // 重进窗口读页面新初始值会误跳提交）
  dbReadyFlag: boolean;
  // 空闲回收定时器句柄（-1 = 未挂）；挂表唯一入口 scheduleIdleReclaim
  reclaimTimer: number;
  // 当前页面 UI 绑定（bindUi 装 / detachUi 清；setSending/onRoundSettled/toast 三枚运行态
  // 包装经它转发——离页期 null 即三枚自然空转）
  uiBinding: ChatRuntimeUiBinding | null;
  // 解绑冻结连接（detachUi 存；重进 rebind 期 conn 读口以「当页连接 ?? 冻结值」合成——
  // 重进瞬间当页连接未解析时，在途工具轮的工具图挂载判据仍见真连接）
  frozenConn: AiConnection | null;
  // 轮终态内存快照（G7 惰性终态门真值面）：写方 = finishStream 入口（经 refs.setLastSettleCause
  // 写口），读方 = 队列域（经 refs.lastSettleCause 只读口），两域不经 host 互调。缺省 'ok' =
  // 无失败记录（工具重发为常态成功路径，按成功语义放行）。禁直查 DB：终态落库在收尾异步链
  // 之后，假沿时必陈旧
  lastSettleCause: string;
  // sending 边沿观察者集：prev≠next 才上报（true 真沿 = 队列投递确认 / false 下降沿 =
  // 队列推进入口）；队列域 attach 注册 / disposeSilent 注销成对（reclaim 链连带）；
  // 回调注入防反向依赖（本件零 import 队列域）
  sendingEdgeWatchers: Set<(sending: boolean) => void>;
}

export class ChatSessionRuntime {
  // 会话 id → 运行态（进程内存态，不落库；acquire 建 / reclaim 删）
  private states: Map<string, ChatRuntimeState> = new Map<string, ChatRuntimeState>();
  // 重启恢复待答集：跨重启保全的 awaiting_input 会话 id 集（列表「生成中」标记是进程内存态
  // 零持久化，重启后靠本集重建）；isGenerating 的或集判据面，启动期一次性 prime（有界查询，
  // 稳态空集零成本），销点 = 续答/放弃落库提交回调（run 离开 awaiting 即清）。
  // **不喂 activeRunCount / 超时收口**（无在途网络工作，不占短时任务）
  private restoredAwaiting: Set<string> = new Set<string>();
  // 构造期观察者暂存：队列域在 create 内 attach 早于账目登记（states 尚无账目），先暂存、
  // 账目登记后回灌；detach 同清两处（成对释放不因时序失配漏注销）
  private pendingSendingEdgeWatchers: Map<string, Set<(sending: boolean) => void>> =
    new Map<string, Set<(sending: boolean) => void>>();
  // 建族告知观察者集（acquire 新建账目时回调）：web 先开会话、手机后建族的时序下，直播中枢
  // 在账目建成一刻补挂 wire（否则手机发起的轮镜不到已打开的 web 会话）。超限拒绝返回 false
  // 由调用方检查（禁静默）；回调异常隔离留痕不破建族主链。进程级单例 + 进程级观察者同寿命
  private acquireWatchers: Set<(state: ChatRuntimeState) => void> =
    new Set<(state: ChatRuntimeState) => void>();

  constructor() {
    // 超时兜底收口绑定：短时任务超时回调经 chatBgReply 转发——逐活跃会话 interrupted 收口
    //（收口链在发送控制器一族；本件不持计时器/任务句柄）
    chatBgReply.bindTimeoutInterrupt((): void => {
      this.interruptActiveForTimeout();
    });
  }

  // 数据源实例工厂：实例创建单一入口（页面字段初始化位经此取件；重进重挂复用运行态既有实例）
  newDataSource(): ChatDataSource {
    return new ChatDataSource();
  }

  // 取或建 + 入园绑定（进页唯一入口）：已有 = 复用（计数 +1、撤销空闲回收、refs 页面面重绑
  // 当页实现）；无 = 以传入数据源登记，refs 壳就位后交页面工厂构造 ChatSendCtrl 一族
  //（create 回调——构造权在页面侧，本件不 new 控制器）。
  // headless 形参（缺省 false 页面链零改动）：web 无头宿主传 true——已有账目只进离屏槽
  // 不碰 uiBinding/页面活绑定；新建账目 refs 壳由离屏绑定首装、uiBinding 留 null（页面后进
  // bindUi 接管）
  acquire(conversationId: string, dataSource: ChatDataSource,
    binding: ChatRuntimeUiBinding,
    create: (dataSource: ChatDataSource, refs: ChatSendRefs) => ChatRuntimeSeed,
    headless: boolean = false): ChatRuntimeState {
    const existing: ChatRuntimeState | undefined = this.states.get(conversationId);
    if (existing !== undefined) {
      existing.attached++;
      this.cancelIdleReclaim(existing);
      if (headless) {
        this.bindHeadless(existing, binding);
      } else {
        this.bindUi(existing, binding);
      }
      return existing;
    }
    const refs: ChatSendRefs = this.buildShellRefs(conversationId, dataSource, binding);
    let seed: ChatRuntimeSeed;
    try {
      seed = create(dataSource, refs);
    } catch (e) {
      // 工厂抛错 = 本账目不成立：清掉构造期暂存观察者（防长寿命表持短寿命队列——寿命匹配红线）
      this.pendingSendingEdgeWatchers.delete(conversationId);
      throw (e as Error);
    }
    const state: ChatRuntimeState = {
      conversationId: conversationId,
      dataSource: dataSource,
      refs: refs,
      sendCtrl: seed.sendCtrl,
      flow: seed.flow,
      keyRound: seed.keyRound,
      toolRound: seed.toolRound,
      queueCtrl: seed.queueCtrl,
      attached: 1,
      sendingFlag: false,
      // 缺省 'local' = UI 发起语义（页面链不写即此值；web 无头宿主发送前置 'web'）
      roundOrigin: 'local',
      dbReadyFlag: false,
      reclaimTimer: -1,
      uiBinding: null,
      headlessBinding: null,
      frozenConn: null,
      lastSettleCause: 'ok',
      sendingEdgeWatchers: new Set<(sending: boolean) => void>()
    };
    this.states.set(conversationId, state);
    // 构造期观察者回灌：账目已就位，一次性并入
    const pendingEdges: Set<(sending: boolean) => void> | undefined =
      this.pendingSendingEdgeWatchers.get(conversationId);
    if (pendingEdges !== undefined) {
      pendingEdges.forEach((watcher: (sending: boolean) => void): void => {
        state.sendingEdgeWatchers.add(watcher);
      });
      this.pendingSendingEdgeWatchers.delete(conversationId);
    }
    if (headless) {
      // buildShellRefs 已按离屏绑定首装 refs；此处只登记离屏槽（uiBinding 留 null）
      state.headlessBinding = binding;
    } else {
      this.bindUi(state, binding);
    }
    // 建族告知（仅新建账目；复用不重复报）：观察者按关切补挂 wire（直播中枢）
    this.notifyAcquireWatchers(state);
    return state;
  }

  // 建族告知观察者注册（满员拒绝返回 false 由调用方检查，禁静默）
  attachAcquireWatcher(watcher: (state: ChatRuntimeState) => void): boolean {
    if (this.acquireWatchers.size >= ACQUIRE_WATCHER_LIMIT && !this.acquireWatchers.has(watcher)) {
      return false;
    }
    this.acquireWatchers.add(watcher);
    return true;
  }

  // 建族告知观察者注销（成对；幂等）
  detachAcquireWatcher(watcher: (state: ChatRuntimeState) => void): void {
    this.acquireWatchers.delete(watcher);
  }

  // 建族回调扇出（快照遍历；单观察者异常不破建族主链——直播面降级，页面/发送照常）
  private notifyAcquireWatchers(state: ChatRuntimeState): void {
    if (this.acquireWatchers.size === 0) {
      return;
    }
    const snapshot: ((state: ChatRuntimeState) => void)[] = [];
    this.acquireWatchers.forEach((watcher: (state: ChatRuntimeState) => void): void => {
      snapshot.push(watcher);
    });
    for (const watcher of snapshot) {
      try {
        watcher(state);
      } catch (e) {
        hilog.warn(0xD5A0, 'ChatSessionRuntime', '建族观察者回调异常（%{public}s）',
          (e as Error).message);
      }
    }
  }

  // 运行态只读现读（无 = null；重进取回与叠页判据经此）
  get(conversationId: string): ChatRuntimeState | null {
    const state: ChatRuntimeState | undefined = this.states.get(conversationId);
    return state !== undefined ? state : null;
  }

  // 生成中判据（会话列表 loading 面消费）：sendingFlag 真值面 或 恢复待答集（跨重启保全的
  // awaiting 会话，同一界面语义面）；空闲存活窗口（5 秒回收期内）不算生成中
  isGenerating(conversationId: string): boolean {
    const state: ChatRuntimeState | undefined = this.states.get(conversationId);
    if (state !== undefined && state.sendingFlag) {
      return true;
    }
    return this.restoredAwaiting.has(conversationId);
  }

  // 恢复待答集写入（启动期唯一写点，EntryAbility 查库后调用——本件不 import 库读件防环，
  // 坑50）；非空才广播列表重拉（列表首帧可能先于本调用读完库，重置键兜时序——坑3 一次性
  // 计数器口径同 onRoundSettled）
  primeRestoredAwaiting(conversationIds: string[]): void {
    if (conversationIds.length === 0) {
      return;
    }
    for (const id of conversationIds) {
      this.restoredAwaiting.add(id);
    }
    AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
      (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
  }

  // 恢复待答集清标：续答/放弃落库提交回调调用（run 离开 awaiting_input 即清）；幂等
  clearRestoredAwaiting(conversationId: string): void {
    this.restoredAwaiting.delete(conversationId);
  }

  // 活跃 run 计数：每次 setSending 写后现算全量（不维护增量计数，自纠偏零漂移）；消费 =
  // chatBgReply.syncActiveRuns（有活跃 run 即申请短时任务、全停即取消；遍历 forEach 为仓内
  // Map 迭代统一姿势）
  private activeRunCount(): number {
    let count: number = 0;
    this.states.forEach((state: ChatRuntimeState): void => {
      if (state.sendingFlag) {
        count++;
      }
    });
    return count;
  }

  // 活跃会话 id 枚举（只读，零新增状态）：消费方 = web 侧 snapshot 活跃 run 列表（经
  // ChatLiveHub 到达）；只交出 id 快照，不动 states private 结构
  activeSessions(): string[] {
    const ids: string[] = [];
    this.states.forEach((state: ChatRuntimeState): void => {
      if (state.sendingFlag) {
        ids.push(state.conversationId);
      }
    });
    return ids;
  }

  // 超时兜底收口：短时任务超时前约 6 秒回调落点——逐活跃会话发 interrupted 收口指令
  //（收口本体 = ChatSendLifecycleCtrl.timeoutInterrupt 终态链）
  interruptActiveForTimeout(): void {
    this.states.forEach((state: ChatRuntimeState): void => {
      if (state.sendingFlag) {
        state.sendCtrl.interruptForTimeout();
      }
    });
  }

  // 库就绪粘滞位回写（ChatPageLifecycle 进页 whenReady 结果落点——见 dbReadyFlag 字段注释）
  markDbReady(state: ChatRuntimeState, ok: boolean): void {
    if (this.states.get(state.conversationId) === state) {
      state.dbReadyFlag = ok;
    }
  }

  // 轮发起端写入：web 无头宿主发送前置 'web'；终态复位 'local' 由 setSending(false) 边沿
  // 承担——复位点在 round_end 信封发布之后，终态信封仍保真值。身份复验（账目已换新态不误写）
  setRoundOrigin(state: ChatRuntimeState, origin: ChatRuntimeRoundOrigin): void {
    if (this.states.get(state.conversationId) !== state) {
      return;
    }
    state.roundOrigin = origin;
  }

  // 页面 UI 绑定（进页/重进 rebind 单点）：refs 壳页面面原地改写为当页实现 + uiBinding 落位
  //（同一 refs 对象，sendCtrl 一族各域件零重建即生效）
  bindUi(state: ChatRuntimeState, binding: ChatRuntimeUiBinding): void {
    if (this.states.get(state.conversationId) !== state) {
      return;
    }
    this.applyRefsBinding(state, binding);
    state.uiBinding = binding;
  }

  // 无头宿主绑定：离屏绑定只进 headlessBinding 槽（**页面活绑定零覆写**——uiBinding 与 refs
  // 页面面均不动）；仅页面不在场时回装 refs 页面面（web 单独在场的发送链读口可达）。
  // 页面后进 bindUi 接管、退页 detachUi 回装本槽——两向时序均不丢
  private bindHeadless(state: ChatRuntimeState, binding: ChatRuntimeUiBinding): void {
    if (this.states.get(state.conversationId) !== state) {
      return;
    }
    state.headlessBinding = binding;
    if (state.uiBinding === null) {
      this.applyRefsBinding(state, binding);
    }
  }

  // 转发目标：页面绑定优先，页面不在场退无头宿主绑定（web 单端场景三枚包装也有离屏消费者
  // no-op，「生成中置真却无页面绑定」探针不再把正常 web 轮误报为断点）
  private uiForwardOf(state: ChatRuntimeState): ChatRuntimeUiBinding | null {
    return state.uiBinding !== null ? state.uiBinding : state.headlessBinding;
  }

  // refs 页面面安装（bindUi/bindHeadless/detachUi 三路共用体）：同一 refs 对象原地改写，
  // uiBinding 槽位由调用方自行落位（离屏路径不占页面槽）
  private applyRefsBinding(state: ChatRuntimeState, binding: ChatRuntimeUiBinding): void {
    const refs: ChatSendRefs = state.refs;
    refs.follow = binding.follow;
    refs.anchorJudge = binding.anchorJudge;
    // 连接合成读口（重进瞬间当页连接未解析 → 退回冻结值——在途工具轮的挂载判据不因重进
    // 窗口丢真值；两值皆无 = null 照旧）
    refs.conn = (): AiConnection | null => binding.conn() ?? state.frozenConn;
    refs.thinking = binding.thinking;
    refs.webSearchOn = binding.webSearchOn;
    refs.sessionOverride = binding.sessionOverride;
    refs.clearError = binding.clearError;
    refs.reloadBranchPath = binding.reloadBranchPath;
    refs.restoreSendInput = binding.restoreSendInput;
    // 待发引用两闭包位真实绑定（进页/重进改写为当页实现；detachUi 重置回安全缺省，成对在位）
    refs.pendingQuote = binding.pendingQuote;
    refs.clearPendingQuote = binding.clearPendingQuote;
  }

  // 页面闭包解绑（退页——寿命匹配红线落点）：refs 壳页面面改写为解绑安全实现——两实例
  //（惰性跟随器/锚判定器）+ 四枚冻结读值（只留值不留闭包）+ 四枚空实现回调（reloadBranchPath
  // 判败 = 换源面安全侧）；运行态自有六员不动（跨页粘滞）；uiBinding 清 null（三枚转发自然空转）
  detachUi(state: ChatRuntimeState, detached: ChatRuntimeDetachedUi): void {
    if (this.states.get(state.conversationId) !== state) {
      return;
    }
    const refs: ChatSendRefs = state.refs;
    state.frozenConn = detached.conn;
    refs.follow = detached.follow;
    refs.anchorJudge = detached.anchorJudge;
    const frozenConn: AiConnection | null = detached.conn;
    const frozenThinking: string = detached.thinking;
    const frozenWeb: boolean = detached.webSearchOn;
    const frozenOverride: ConversationOverride | null = detached.sessionOverride;
    refs.conn = (): AiConnection | null => frozenConn;
    refs.thinking = (): string => frozenThinking;
    refs.webSearchOn = (): boolean => frozenWeb;
    refs.sessionOverride = (): ConversationOverride | null => frozenOverride;
    refs.clearError = (): void => {
    };
    refs.restoreSendInput = (): void => {
    };
    // 待发引用解绑重置（照 restoreSendInput 先例）：读口恒 ''（页面内存态随页面消亡，不冻结
    // 续带——在途轮次读引用只应读「无」）、清口零动作；寿命匹配红线
    refs.pendingQuote = (): string => '';
    refs.clearPendingQuote = (): void => {
    };
    refs.reloadBranchPath = (): Promise<boolean> => Promise.resolve(false);
    state.uiBinding = null;
    // 无头槽在场 → refs 页面面回装离屏实现（页面退场后 web 会话照常可发）；离屏绑定属进程级
    // 无头宿主（非页面短寿命对象）——寿命匹配红线不破
    const headless: ChatRuntimeUiBinding | null = state.headlessBinding;
    if (headless !== null) {
      this.applyRefsBinding(state, headless);
    }
  }

  // 退页（引用计数 −1）——只解绑不掐流：不调 sendCtrl 任何销毁动作（掐流/收尾/占用归还全
  // 不退），生成照常跑在运行时权威态；归零且非生成挂空闲回收。身份匹配（账目已换新态不误减）
  // + 幂等。★ 解绑（detachUi）必须先于本方法（页面对象可达性先归还再计数）
  release(state: ChatRuntimeState): void {
    if (this.states.get(state.conversationId) !== state) {
      return;
    }
    if (state.attached > 0) {
      state.attached--;
    }
    this.scheduleIdleReclaim(state);
  }

  // 无头宿主退场：清离屏槽（页面 detach 不再回装已关会话的绑定）→ 计数 −1 → 回收评估。
  // 不清 refs 页面面：在途轮照跑（闭包属进程级无头宿主，零页面可达性；账目回收时随 state
  // 消亡）。WebHeadlessHost 关闭会话时先 unsubscribe 再调本方法（与 release 同成对纪律）
  releaseHeadless(state: ChatRuntimeState): void {
    if (this.states.get(state.conversationId) !== state) {
      return;
    }
    state.headlessBinding = null;
    if (state.attached > 0) {
      state.attached--;
    }
    this.scheduleIdleReclaim(state);
  }

  // ── 空闲回收（唯一挂表入口）──：引用归零且非生成才挂定时；已挂则保留到点再查
  //（生成中永不回收：收尾钩子/退页两路评估，收尾后自然满足）
  private scheduleIdleReclaim(state: ChatRuntimeState): void {
    if (state.attached > 0 || state.sendingFlag || state.reclaimTimer >= 0) {
      return;
    }
    state.reclaimTimer = setTimeout((): void => {
      state.reclaimTimer = -1;
      this.reclaim(state);
    }, IDLE_RECLAIM_MS);
  }

  private cancelIdleReclaim(state: ChatRuntimeState): void {
    if (state.reclaimTimer >= 0) {
      clearTimeout(state.reclaimTimer);
      state.reclaimTimer = -1;
    }
  }

  // 回收落点（到点）：身份匹配 + 双条件复查（acquire 会取消定时器，此处双保险）→ 账本除名
  // → 静默销毁整链（不触发 finishStream；此刻无在途——被 sendingFlag 拦在门外）+ 数据源
  // 展示态释放
  private reclaim(state: ChatRuntimeState): void {
    if (this.states.get(state.conversationId) !== state) {
      return;
    }
    if (state.attached > 0 || state.sendingFlag) {
      return;
    }
    this.states.delete(state.conversationId);
    state.sendCtrl.disposeSilent();
    state.dataSource.disposeDisplayState();
  }

  // refs 壳构造：运行态自有六员粘滞实现（setSending 写 sendingFlag 并转发页面镜像 + 收尾
  // 评估回收；onRoundSettled 转发页面 + 广播列表刷新 + 评估回收）+ 页面面直接装当页实现
  private buildShellRefs(conversationId: string, dataSource: ChatDataSource,
    binding: ChatRuntimeUiBinding): ChatSendRefs {
    const refs: ChatSendRefs = {
      dataSource: dataSource,
      follow: binding.follow,
      anchorJudge: binding.anchorJudge,
      conversationId: (): string => conversationId,
      dbReady: (): boolean => {
        const st: ChatRuntimeState | undefined = this.states.get(conversationId);
        return st !== undefined && st.dbReadyFlag;
      },
      conn: (): AiConnection | null => null,
      sending: (): boolean => {
        const st: ChatRuntimeState | undefined = this.states.get(conversationId);
        return st !== undefined && st.sendingFlag;
      },
      thinking: (): string => '',
      webSearchOn: (): boolean => false,
      sessionOverride: (): ConversationOverride | null => null,
      // 待发引用两闭包位解绑态安全缺省：读口恒 ''、清口零动作（真实绑定经 bindUi 接当页实现）
      pendingQuote: (): string => '',
      clearPendingQuote: (): void => {
      },
      setSending: (sending: boolean): void => {
        const st: ChatRuntimeState | undefined = this.states.get(conversationId);
        if (st === undefined) {
          return;
        }
        const prevSending: boolean = st.sendingFlag;
        st.sendingFlag = sending;
        const ui: ChatRuntimeUiBinding | null = this.uiForwardOf(st);
        if (ui !== null) {
          ui.setSending(sending);
        } else if (sending) {
          // ★ 真机探针：起轮置真却无页面绑定 = 链上剩余唯一静默断点——真机再现「生成中但
          // 按键不翻」时，本行日志区分「未转发」（有本行）与「转发未达」（无本行）
          hilog.warn(0xD5A0, 'ChatSessionRuntime', '生成中置真但无页面绑定（%{public}s）',
            conversationId);
        }
        // 每笔写后同步短时任务账本（申请/取消转场单源在 chatBgReply.syncActiveRuns，本处只报数）
        chatBgReply.syncActiveRuns(this.activeRunCount());
        if (!sending) {
          // 轮终态复位轮发起端标记（'web' → 'local'）：round_end 挂点在收尾入口发布、先于本
          // 边沿，终态信封仍保真值。队列紧随的 web 连发归 local（origin 属诊断/防回环标记，
          // V1 队列续轮不追标记）
          st.roundOrigin = 'local';
          this.scheduleIdleReclaim(st);
        }
        // 边沿观察者：prev≠next 才上报（观察者回调内禁同步直派——出队体在队列域恒微任务）；
        // 同值写不通知（重复 false 不触发伪下降沿）。真沿同拍清终态快照：不经 finishStream
        // 的路径起轮即回 'ok'，下降沿不被上一轮陈旧 error/stopped 误拦
        if (prevSending !== sending) {
          if (sending) {
            st.lastSettleCause = 'ok';
          }
          if (st.sendingEdgeWatchers.size > 0) {
            st.sendingEdgeWatchers.forEach((watcher: (sending: boolean) => void): void => {
              watcher(sending);
            });
          }
        }
      },
      clearError: (): void => {
      },
      toast: (message: string): void => {
        const st: ChatRuntimeState | undefined = this.states.get(conversationId);
        const ui: ChatRuntimeUiBinding | null = st !== undefined ? this.uiForwardOf(st) : null;
        if (ui !== null) {
          ui.toast(message);
        }
      },
      onRoundSettled: (): void => {
        const st: ChatRuntimeState | undefined = this.states.get(conversationId);
        if (st === undefined) {
          return;
        }
        const ui: ChatRuntimeUiBinding | null = this.uiForwardOf(st);
        if (ui !== null) {
          ui.onRoundSettled();
        }
        // 生成收尾 → 会话列表 loading 刷新广播（一次性计数器形态，坑3 口径）
        AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
          (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
        this.scheduleIdleReclaim(st);
      },
      reloadBranchPath: (): Promise<boolean> => Promise.resolve(false),
      restoreSendInput: (): void => {
      },
      // ── 排队域边沿观察者 + 终态快照四员（refs 构造点恒实现；真值面挂运行态，账目已回收
      // 时空转/回缺省）──
      attachSendingEdge: (watcher: (sending: boolean) => void): void => {
        const st: ChatRuntimeState | undefined = this.states.get(conversationId);
        if (st !== undefined) {
          st.sendingEdgeWatchers.add(watcher);
          return;
        }
        // 构造期时序（队列域 attach 早于账目登记）：暂存待 acquire 回灌
        let pending: Set<(sending: boolean) => void> | undefined =
          this.pendingSendingEdgeWatchers.get(conversationId);
        if (pending === undefined) {
          pending = new Set<(sending: boolean) => void>();
          this.pendingSendingEdgeWatchers.set(conversationId, pending);
        }
        pending.add(watcher);
      },
      detachSendingEdge: (watcher: (sending: boolean) => void): void => {
        // 账目不在 = 观察者随 state 对象整体回收，空转无害；暂存表同清（成对）
        const st: ChatRuntimeState | undefined = this.states.get(conversationId);
        if (st !== undefined) {
          st.sendingEdgeWatchers.delete(watcher);
        }
        const pending: Set<(sending: boolean) => void> | undefined =
          this.pendingSendingEdgeWatchers.get(conversationId);
        if (pending !== undefined) {
          pending.delete(watcher);
          if (pending.size === 0) {
            this.pendingSendingEdgeWatchers.delete(conversationId);
          }
        }
      },
      lastSettleCause: (): string => {
        const st: ChatRuntimeState | undefined = this.states.get(conversationId);
        return st !== undefined ? st.lastSettleCause : 'ok';
      },
      setLastSettleCause: (cause: string): void => {
        const st: ChatRuntimeState | undefined = this.states.get(conversationId);
        if (st !== undefined) {
          st.lastSettleCause = cause;
        }
      }
    };
    return refs;
  }
}

// 进程级单例（跨页面实例共享——同会话运行态唯一真源）
export const chatSessionRuntime: ChatSessionRuntime = new ChatSessionRuntime();
