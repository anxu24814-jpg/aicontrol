// 发送入口守卫与排队路由域（自 ChatSendCtrl.ets 域级最小拆分迁出——守卫链与入队路由是
// 同一职责（守卫改判全部是「何时入队」），母件越 1200 硬线按宪法拆出）。
// 域定义一句话：**发送入口的守卫链与排队路由**——判断哪一笔发送被拒绝、哪一笔入队、哪一笔
// 进入异步组装；持有会话级队列实例（ChatSendQueueCtrl）与宿主闭包接线（入队/自动派发/
// T4b/T4c 回滚/销毁连带）；兼排队持久化适配位（构造期 hydrate / 入队写穿 / 编辑删除清空
// 换序落库；行读写单源 common/store/ChatSendQueueDb）与排队运行态适配位（loadState/
// saveState——暂停位落库，会话级一行）。
// · 反碎片申报（为何不并入）：ChatSendQueueCtrl 是纯逻辑状态机（零 import 直跑纪律），
//   本件承载守卫语义与宿主接线，并入破坏其零依赖；ChatSendAssembly 是守卫全过之后的
//   异步组装链，本件是它之前的分流器——两个相位不可混。
// · 依赖方向（防循环依赖）：本件禁 import ChatSendCtrl 的任何符号（含类型——chat 域既有
//   环不增员）；宿主态（页面 refs 现读 / 图写侧路由 / 占用接纳 / 组装派发 / 队列边沿
//   观察者）一律经 ChatSendEntryGateHost 闭包现读到达，禁在本件缓存任何宿主态；
//   ChatSendQueueCtrl 为无依赖域件，直注。
import { AiConnection, PendingAttachment } from '../../common/providers/AiTypes';
import { ROUTE_BLOCKED } from '../../common/chat/ChatContextSource';
import { TOMBSTONE_TOAST_TEXT } from '../../common/chat/ChatBranchPolicy';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { relationalStore } from '@kit.ArkData';
import { sharedRdbStore, whenReady } from '../../common/store/ChatDb';
import { ChatSendQueueCtrl, ChatSendQueuePersistence, QueueItem,
  QueueRunState } from './ChatSendQueueCtrl';
import { decodeQueueRow, deleteQueueItem, deleteQueueItemsByConversation,
  insertQueueItem, queryQueueItems, queryQueueState, reorderQueueItems, serializeQueuePayload,
  updateQueueItemPayload, upsertQueueState, SendQueueStateRow } from '../../common/store/ChatSendQueueDb';

const DOMAIN: number = 0x0001;
const TAG: string = 'ChatSendEntryGate';

// 宿主面（照 ChatSendAssemblyHost 形制：属性式函数类型——ArkTS 对象字面量须对应属性式
// 接口；闭包持宿主态现读）
export interface ChatSendEntryGateHost {
  // 可当下修复的三守卫真值（T1f：dbReady / 连接 / 墓碑维持 toast + false，不入队）
  dbReady: () => boolean;
  conn: () => AiConnection | null;
  toast: (message: string) => void;
  // 生成中真值（Q2 入队改判与 G5 真值面同源）
  sending: () => boolean;
  // 队列派发就绪门：dbReady + conn 解析 + 历史装载三件全真（实现位 = 宿主
  // queueDispatchReady；未就绪只让位不派发，见 ChatSendQueueCtrl）
  dispatchReady: () => boolean;
  // 队列 G6 会话锚点
  conversationId: () => string;
  // 队列 G7 轮终态内存快照读口
  lastSettleCause: () => string;
  // 旧格式墓碑会话判据（守卫镜像）与自愈装载
  routeState: () => string;
  ensureGraphRoute: () => Promise<void>;
  // 运行占用接纳（V1/V9 单活跃 run；Q2 失败改判入队）
  beginRunAcquire: () => boolean;
  // 错误态清空（页面 errorText 覆盖层）
  clearError: () => void;
  // 守卫全过后的异步组装派发入口（ChatSendAssembly.assembleAndDispatch 值参镜像）
  assembleAndDispatch: (conn: AiConnection, text: string, attachments: PendingAttachment[],
    hasVision: boolean, designateId: string, queueItemId: string,
    autoDispatch: boolean) => void;
  // 队列宿主面：插队停止口 / 边沿观察者注册注销（成对，构造 attach / disposeSilent detach）
  abortActive: () => void;
  attachSendingEdge: (watcher: (sending: boolean) => void) => void;
  detachSendingEdge: (watcher: (sending: boolean) => void) => void;
  // Q3 写穿失败归还文本（队列条目落库失败 → 文本回输入条，输入不丢；附件不参与排队）
  restoreSendInput: (text: string) => void;
}

export class ChatSendEntryGate {
  private host: ChatSendEntryGateHost;
  // ── 会话级排队域（T1~T12/G1~G8/latch/微任务/插队/20 上限全在 ChatSendQueueCtrl——
  // 本件只留实例与闭包宿主接线，观察者构造期注册、disposeSilent 注销）──
  private queue: ChatSendQueueCtrl;

  constructor(host: ChatSendEntryGateHost) {
    this.host = host;
    // 八闭包回接宿主既有面；Q3 增写穿持久化口与失败归还文本口
    this.queue = new ChatSendQueueCtrl({
      sending: (): boolean => this.host.sending(),
      // 就绪门由宿主合成——未就绪的 hydrate 首派发只让位，不撞 T4b 假暂停
      dispatchReady: (): boolean => this.host.dispatchReady(),
      conversationId: (): string => this.host.conversationId(),
      toast: (message: string): void => this.host.toast(message),
      restoreInput: (text: string): void => this.host.restoreSendInput(text),
      persistence: this.buildQueuePersistence(),
      lastSettleCause: (): string => this.host.lastSettleCause(),
      // Q2 载荷化派发（四参显式随参——绕过输入条快照；queueItemId 贯通至 beginSend 供
      // 事务删行；autoDispatch = 自动连发旗标，「立即发送」= 用户动作恒拽底）
      dispatchQueued: (text: string, designateId: string, queueItemId: string,
        autoDispatch: boolean): boolean =>
        this.sendQueued(text, designateId, queueItemId, autoDispatch),
      abortActive: (): void => this.host.abortActive(),
      attachSendingEdge: (watcher: (sending: boolean) => void): void =>
        this.host.attachSendingEdge(watcher),
      detachSendingEdge: (watcher: (sending: boolean) => void): void =>
        this.host.detachSendingEdge(watcher)
    });
  }

  // ── Q3 排队持久化适配（实现位 = 本件：队列域零 import 直跑纪律的注入面）──
  // 就绪等待经 whenReady（构造期 acquire 早于 EntryAbility 初始化完成）；行读写单源 =
  // ChatSendQueueDb。写穿失败语义：insert 抛错 → 回滚条目 + 归还输入 + toast；其余写口
  // 抛错 → toast（内存已生效，重进以库为准）
  private buildQueuePersistence(): ChatSendQueuePersistence {
    return {
      load: (): Promise<QueueItem[]> => this.loadQueueFromDb(),
      insert: (item: QueueItem, sortOrder: number): Promise<boolean> =>
        this.insertQueueRow(item, sortOrder),
      updateText: (item: QueueItem): Promise<void> => this.updateQueueRowText(item),
      remove: (id: string): Promise<void> =>
        this.withQueueDb((db: relationalStore.RdbStore): Promise<void> =>
          deleteQueueItem(db, id)),
      removeAll: (conversationId: string): Promise<void> =>
        this.withQueueDb((db: relationalStore.RdbStore): Promise<void> =>
          deleteQueueItemsByConversation(db, conversationId)),
      reorder: (items: QueueItem[]): Promise<void> => this.reorderQueueRows(items),
      // v58 暂停位（会话级一行；必填——可选化会让漏接线静默退化成「暂停位不落库」）
      loadState: (): Promise<QueueRunState> => this.loadQueueStateFromDb(),
      saveState: (state: QueueRunState): Promise<void> => this.saveQueueStateToDb(state)
    };
  }

  // DB 就绪后执行（未就绪 = reject → 队列域按写失败处置）
  private withQueueDb<T>(work: (db: relationalStore.RdbStore) => Promise<T>): Promise<T> {
    return whenReady().then((ok: boolean): Promise<T> => {
      if (!ok) {
        return Promise.reject(new Error('数据库未就绪'));
      }
      return work(sharedRdbStore());
    });
  }

  // 装载（全 QUEUED；坏载荷行由 decodeQueueRow 跳过并 hilog 留痕）。
  // ★ 读不成 ≠ 没有：未就绪与读抛错一律 reject，禁降级空集——返 [] 与「队列真空」在队列
  //   域不可区分，hydrate 见空集会连库内 PAUSED 归一 ACTIVE 并回写（暂停位真值丢失 =
  //   重启/退页回收后暂停消息自动发出）。reject 落队列域末端 catch = 空集、零回写、
  //   零 notify，库内条目与暂停位原样留存下次进会话重装
  private loadQueueFromDb(): Promise<QueueItem[]> {
    const conversationId: string = this.host.conversationId();
    return whenReady().then((ok: boolean): Promise<QueueItem[]> => {
      if (!ok) {
        return Promise.reject(new Error('数据库未就绪，排队装载让位'));
      }
      return queryQueueItems(sharedRdbStore(), conversationId).then(
        (rows): QueueItem[] => {
          const items: QueueItem[] = [];
          for (const row of rows) {
            const payload = decodeQueueRow(row);
            if (payload === null) {
              continue;
            }
            items.push({
              id: row.id,
              conversationId: row.conversationId,
              text: payload.text,
              designateId: payload.designateId,
              queuedAt: payload.queuedAt,
              state: 'QUEUED',
              persisted: true
            });
          }
          return items;
        });
    }).catch((e: Object): Promise<QueueItem[]> => {
      hilog.warn(DOMAIN, TAG, '排队装载失败，队列保持空集待下次进会话重装：%{public}s', String(e));
      return Promise.reject(e);
    });
  }

  // 运行态装载（v58）：DB 未就绪 / 读失败一律返 ACTIVE 缺省，**不 reject**——降级不得击穿
  // 条目装载（hydrate 里 loadState 与 load 是两条链，本口自己吞错，队列域再兜一层 catch）
  private loadQueueStateFromDb(): Promise<QueueRunState> {
    const fallback: QueueRunState = { runState: 'ACTIVE', pauseReason: '' };
    const conversationId: string = this.host.conversationId();
    return whenReady().then((ok: boolean): Promise<QueueRunState> => {
      if (!ok) {
        return Promise.resolve(fallback);
      }
      return queryQueueState(sharedRdbStore(), conversationId).then(
        (row: SendQueueStateRow | null): QueueRunState => {
          if (row === null) {
            return fallback;
          }
          const state: QueueRunState = { runState: row.runState, pauseReason: row.pauseReason };
          return state;
        });
    }).catch((_e: Object): QueueRunState => fallback);
  }

  // 运行态写穿（v58）：会话行未出生 → 零写（ChatSendQueueDb.upsertQueueState 内守卫）——
  // 不产生孤儿行，会话行出生后下一次状态变更自然补写
  private saveQueueStateToDb(state: QueueRunState): Promise<void> {
    const row: SendQueueStateRow = {
      conversationId: this.host.conversationId(),
      runState: state.runState,
      pauseReason: state.pauseReason,
      updatedAt: Date.now()
    };
    return this.withQueueDb((db: relationalStore.RdbStore): Promise<void> =>
      upsertQueueState(db, row));
  }

  private insertQueueRow(item: QueueItem, sortOrder: number): Promise<boolean> {
    return this.withQueueDb((db: relationalStore.RdbStore): Promise<boolean> =>
      insertQueueItem(db, {
        id: item.id,
        conversationId: item.conversationId,
        sortOrder: sortOrder,
        payload: serializeQueuePayload({
          text: item.text,
          designateId: item.designateId,
          queuedAt: item.queuedAt
        }),
        createdAt: item.queuedAt,
        updatedAt: Date.now()
      }));
  }

  private updateQueueRowText(item: QueueItem): Promise<void> {
    return this.withQueueDb((db: relationalStore.RdbStore): Promise<void> =>
      updateQueueItemPayload(db, item.id, serializeQueuePayload({
        text: item.text,
        designateId: item.designateId,
        queuedAt: item.queuedAt
      }), Date.now()));
  }

  private reorderQueueRows(items: QueueItem[]): Promise<void> {
    const ids: string[] = items.map((item: QueueItem): string => item.id);
    return this.withQueueDb((db: relationalStore.RdbStore): Promise<void> =>
      reorderQueueItems(db, this.host.conversationId(), ids));
  }

  // 发送（UI 入口；守卫与派发单源在 sendEntry）。
  // ★ 返回值契约：true = 守卫全过、消息已交编排（后续异步失败降级不回头）；false = 任一
  //   守卫拦下或入队被拒、本次未投递——**附件不在守卫里清理**：调用方（ChatPage.
  //   dispatchSend）按 false 保留输入条文字与附件，就地清理反成悬空引用；唯一的投递后
  //   清理点 = 组装链 disposed 分支。
  // ★ Q2 入队契约：生成中或队列非空时文本入队也算投递（返回 true，调用方清输入条）；带
  //   附件且需排队时拒绝入队返回 false（输入保留）；满 20 由队列域 toast 后返回 false。
  // ★ designateId 由调用方在投递入口快照后值参传入（异步组装期间页面可改指定——晚读会把
  //   「后改的值」注进「先发的那条消息」，快照纪律见母件 send 注释）。
  send(text: string, attachments: PendingAttachment[], hasVision: boolean,
    designateId: string): boolean {
    return this.sendEntry(text, attachments, hasVision, designateId, '', false);
  }

  // 排队派发入口（供 ChatSendQueueCtrl T4 消费的载荷化变体，四参随参——绕过输入条快照，
  // 不读不回写输入条/页面指定态；queueItemId 贯通至 beginSend 接事务删行）。
  // 返回 false = 同步拒绝，交 T4b 统一处置（回队 + PAUSED('delivery') + toast——本路径
  // 不再另 toast 防双报）
  sendQueued(text: string, designateId: string, queueItemId: string,
    autoDispatch: boolean): boolean {
    return this.sendEntry(text, [], false, designateId, queueItemId, autoDispatch);
  }

  // 发送守卫与派发单入口（send 与 sendQueued 共用；fromQueue = queueItemId 非空——队列
  // 条目 id 恒非空，无需另设布尔参）
  private sendEntry(text: string, attachments: PendingAttachment[], hasVision: boolean,
    designateId: string, queueItemId: string, autoDispatch: boolean): boolean {
    if (text === '' && attachments.length === 0) {
      return false;
    }
    // 可当下修复的错误不入队（T1f）：dbReady / 连接 / 墓碑三守卫维持 toast + false。
    // 队列派发到达者不另 toast——返回 false 由 T4b 统一呈报（G8 防双 toast）
    const fromQueue: boolean = queueItemId !== '';
    if (!this.host.dbReady()) {
      if (!fromQueue) {
        this.host.toast('数据库未就绪，请稍候再试');
      }
      return false;
    }
    const conn: AiConnection | null = this.host.conn();
    if (conn === null) {
      // 连接 = 当前服务商 + 当前模型（无可用服务商/无对话模型/无启用 key 均解析为 null）
      if (!fromQueue) {
        this.host.toast('请先在「设置 > 服务商管理」完善服务商（接口地址、密钥与模型）');
      }
      return false;
    }
    // 旧格式墓碑会话拒发（blocked 判定前移——若只在下游客判，send 已按 true 交页面、草稿
    // 与附件被清，拒发即白打字）：镜像 = 上次路由装载结果（routeState）；此处顺手
    // ensureGraphRoute 自愈（会话态已变时异步转新态——不刷新则陈旧 blocked 会把本会话发送
    // 锁到页面重开）。下游既有早退保留为二道闸；返 false = 本次未投递，页面保留草稿与
    // 附件。文案单源 ChatBranchPolicy（墓碑短句）
    if (this.host.routeState() === ROUTE_BLOCKED) {
      this.host.ensureGraphRoute().catch((): void => undefined);
      if (!fromQueue) {
        this.host.toast(TOMBSTONE_TOAST_TEXT);
      }
      return false;
    }
    // ★ Q2 入队改判：用户入口（send）生成中**或队列非空**（FIFO 尾插，含暂停态——防暂停
    // 期直发插队与停止在途窗口 idle 错觉直发撞闸）→ 文本入队并 return true（入队也算
    // 投递）；带附件拒绝入队 + toast（文本 only，输入保留）。队列派发（sendQueued）生成中 =
    // 同步拒绝交 T4b（回队 + PAUSED('delivery') + toast，永不丢），不再另 toast 防双报
    if (fromQueue) {
      if (this.host.sending()) {
        return false;
      }
    } else if (this.host.sending() || this.queue.itemCount() > 0) {
      return this.enqueueFromEntry(text, attachments, designateId);
    }
    // 运行占用接纳（S2）：同步建立占用——组装窗口内第二笔发送在本点被拒（sending 置位前
    // 的双发窗口消灭，V1）；分栏态同会话另一控制器发送同样被拒（单活跃 run，I2/V9）。
    // Q2：用户入口失败同样改判入队（组装窗口内第二笔不再白打字）；队列派发失败交 T4b
    //（不再另 toast）
    if (!this.host.beginRunAcquire()) {
      if (fromQueue) {
        return false;
      }
      return this.enqueueFromEntry(text, attachments, designateId);
    }
    this.host.clearError();

    // 发送前异步组装 + 派发：附件载荷（失败降级纯文本）→ 转图并行下载 → 记忆/技能/知识
    // 三快照 → 图路由装载 → 路径摘要直查 → dispatchSend 派发——组装链与判据在
    // ChatSendAssembly.assembleAndDispatch（见彼件）；入参全部为上方入口快照，组装期间
    // 宿主改态不污染本链；queueItemId / autoDispatch 随链贯通（载荷化派发与拽底判读）
    this.host.assembleAndDispatch(conn, text, attachments, hasVision, designateId,
      queueItemId, autoDispatch);
    // 守卫全过 = 已投递（后续异步组装不再回头；调用方据此清输入条）
    return true;
  }

  // 用户入口入队落点（busy / 队列非空时改判入队）——排队文本 only：带附件（含纯附件
  // 消息）拒绝入队 + toast（调用方保留输入）；满 20 由队列域 toast + false（T1e，输入
  // 保留）；空文本已在第一守卫拦下（附件可独立成文，但排队不支持附件故同走本支）
  private enqueueFromEntry(text: string, attachments: PendingAttachment[],
    designateId: string): boolean {
    if (attachments.length > 0) {
      this.host.toast('排队暂只支持文字消息，附件消息请等待当前回复结束后再发送');
      return false;
    }
    return this.queue.enqueue(text, designateId);
  }

  // 排队域到达面（ChatRuntimeSeed/入口条等消费方经此只读到达，写面全在队列域意图方法）
  queueCtrl(): ChatSendQueueCtrl {
    return this.queue;
  }

  // 受理后组装失败回滚链入口（组装链各失败出口转发——T4c：按 queueItemId 回队头 + 清闩 +
  // PAUSED('delivery')；queueItemId 空 / 项已不在飞 = 非队列派发，时空转只清闩）
  onDispatchAbandoned(queueItemId: string): void {
    this.queue.onDispatchAbandoned(queueItemId);
  }

  // 投递确认回执入口（T4a）：beginSend resolve = 排队行已在 prepareRun 事务内与 user 行 +
  // run 行同笔删除——条目正式出队 + 清闩
  onDispatchCommitted(queueItemId: string): void {
    this.queue.onDispatchCommitted(queueItemId);
  }

  // 运行态销毁清理（成对释放：观察者注销与队列清理，宿主 disposeSilent 连带到达）
  disposeSilent(): void {
    this.queue.disposeSilent();
  }
}
