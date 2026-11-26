// 会话级排队状态机与派发域（施工总案 docs/方案-进会话体验统一与排队插队施工总案-20261017.md）：
// **会话级排队状态机与派发**——busy 期入队排队的状态机（迁移表 T1~T12）+ 派发闸（G1~G8）+
// dispatchLatch + 微任务出队 + 出队原子语义 + 插队豁免 + 20 上限；零 UI、零 ArkUI 依赖、
// 零 import——纯逻辑域件（断言直跑零桩）。
// · 为何不能并入（反碎片下限②）：排队是新功能域；ChatSendCtrl 是发送编排宿主（并入 = 重越
//   1200 硬线）；ChatAutoRetryCtrl 是网络自愈域（零产出重发），职责缝不同。
// · 依赖方向（防循环依赖）：本件只持宿主接口 ChatSendQueueHost 闭包集，禁 import
//   ChatSendCtrl 任何符号（含类型）；common 层零 import 队列域（边沿观察者经 refs 壳注入）。
// ── 机制索引（详注随各方法，机理单源在此）──
// ①状态机：T1/T1e 入队与上限、T2/T3 暂停恢复、T4/T4a/T4b/T4c 派发四态、T5 收尾推进、T6 插队、
//   T7 编辑占位、T8/T9 删除清空、T10 拖拽互斥（dragHeld，事件面 U2 接）、T11 恢复装载
//   （hydrate）、T12 运行态销毁清理。②边沿观察者：构造经宿主口 attachSendingEdge 注册（真沿/
//   下降沿都上报）、disposeSilent 注销（成对释放红线；reclaim 链经宿主 disposeSilent 连带到达）。
// ③推进点（★全案最关键设计）：下降沿 → scheduleDispatch，出队体恒微任务（releaseRun 必已
//   完成——全部 setSending(false) 写点与配对归还同同步块），禁观察者回调内同步直派（同步派发
//   时占用未还必撞闸）；★自检修复中1：真沿**不清 dispatchLatch 也不摘项**（机理见
//   onSendingEdge——闩的终局清理收敛到 beginSend 回执与 T4b/T4c）；dispatchNext 入口再验
//   sending 让位（单活跃 run 红线9）。
// ④dispatchLatch（G4）：派发置位、回执/T4b/T4c 终局清——防组装窗口双发（beginRunAcquire
//   在异步组装之前、setSending(true) 在 dispatchSend 才置位，窗口内 sendingFlag=false 而占用
//   已持，再次 dispatchNext 恒撞）。回执/回滚均按 queueItemId 匹配（禁按「第一个 IN_FLIGHT」
//   猜——abort 反向插入时猜错项）。
// ⑤出队原子语义：send() 返回 true ≠ 已投递——派发开始置 IN_FLIGHT（内存闩不落库）→ 载荷化
//   send；同步拒绝（false）→ T4b（回 QUEUED 原位 + PAUSED('delivery')，不自动重试、永不丢）；
//   受理后组装失败（无 setSending 写的出口）→ T4c onDispatchAbandoned 回滚链（回队头 + 清闩
//   + 行不删 + PAUSED('delivery')）；投递确认 = beginSend 事务提交回执。失败回滚链永不静默丢。
// ⑥插队（裁定丙-4）：jumpSend = 项提队首 + JUMP_PENDING + 清暂停位（「立即发送 = 插队 +
//   恢复发送」）；sending → 既有 abort 链零改动（防重复 abort 位；markUserStop 最先等顺序红线
//   不动）→ 收尾下降沿微任务优先派发；!sending → 直接派发（撞占用闸走 T4b）。JUMP_PENDING
//   豁免 G1 暂停位与 G7 惰性终态门（否则「立即发送」变「只落暂停」）；abort 在途删除 jump 项
//   = 标记随项消亡；在途编辑保存 = jump 标记保留（只改文本）。
// ⑦惰性终态门 G7（裁定丙-5）：读内存终态快照 lastSettleCause（真值面挂 ChatSessionRuntime，
//   经宿主只读口）；禁直查 DB（终态落库在收尾异步链之后，假沿时必陈旧——error 轮永不暂停/
//   上轮 error 本轮 done 误暂停）。终态 ∈ {error, stopped, interrupted} → 不派发（视同暂停、
//   永不丢、单次提示——暂停后 G1 拦死，重复下降沿不再进本门）；done/ok/未知 → 派发；
//   awaiting_input 放行（占用面若在则撞闸走 T4b 兜底）；T3 恢复的派发试探越过本门
//   （forceResume 位——chatbox 教益4）。
// ⑧20 条上限（chatbox 同款，裁定丙-10）+ 满队 toast；域件再守文本 only（带附件由入口层
//   sendEntry 首拦；enqueue 签名只收文本，空文本拒）。
// ⑨通知面 addOnQueueChange/removeOnQueueChange（count/paused 双参，U1 入口条与 U2 面板
//   消费——注册注销成对，寿命匹配红线）。⑩拖拽互斥 dragHeld（裁定丙-7）。⑪无定时器（暂停
//   = 惰性发现无重试定时）→ disposeSilent 清观察者/EDITING 占位/闩。
// ⑫派发口载荷化四参（text/designateId/queueItemId/autoDispatch——queueItemId 贯通 beginSend
//   供事务删行，autoDispatch 供拽底判读）；入队点改判与附件拒绝在宿主 sendEntry；M1「运行中
//   不插话」被本域取代（用户入口 busy/队列非空即入队）。
// ⑬Q3 持久化：写穿经宿主 persistence 口注入（实现位 ChatSendEntryGate，行读写单源
//   ChatSendQueueDb；本件零 import 零桩直跑）——①入队先内存（persisted=false，派发闸不选
//   未落库项）后 INSERT，成功才置 persisted 并补派发试探；失败 = 回滚条目 + 归还文本 + toast
//  （永不静默丢）；无行会话 insert 返 false = 内存暂存，后续派发试探/队列操作重试 flush（不产
//   孤儿行）。②编辑/删除/清空/换序 = 先改内存后落库（失败 toast，下次 hydrate 以库为准）。
//   ③构造期 hydrate 重建全 QUEUED 条目（v58 起恢复库内暂停位）+ 内存条目按 id 去重合并（DB
//   行在前）；装载失败 = 保持空集**零回写零 notify**，库内条目与暂停位原样留存待重装（禁降级
//   空集——空集会被读成「队列真空」而把库内 PAUSED 归一 ACTIVE）。④出队删行**不在本件**：
//   搭车 beginSend/prepareRun 单事务（库中永无 inFlight 歧义行）。⑤删会话级联不回调本件，
//   内存镜像随下次 hydrate/5s 回收对齐（无用户面危害）。
// ⑭v58 暂停位落库（决明报障「暂停后重启重进，排队消息直接发出去」）：①运行态单出口
//   setRunState（内存 + fire-and-forget 落库，失败只 toast），禁再散写决定性
//   runState/pauseReason（hydrate 初始装载直写除外）；②hydrate 串行两段 + stateTouched 竞态
//   守卫（内存优先）+ 脏值只认 'PAUSED' + 空队列强制回 ACTIVE 并回写；③语义 = 暂停的仍暂停
//   （重启 / 5s 空闲回收两路径同修），没暂停的照旧续发。
// T12 边界：items 随运行态亡（不主动清——随 ChatSendCtrl 一族被 reclaim 整体回收）。
export type QueueItemState = 'QUEUED' | 'EDITING' | 'IN_FLIGHT' | 'JUMP_PENDING';
// 暂停因枚举（§4.1 pauseReason：'user' 手动 | 'error' 上轮失败 | 'stopped' 停止连带
// （缺省①）| 'delivery' 派发失败；'' 与 ACTIVE 态配对无意义）
export type QueuePauseReason = 'user' | 'error' | 'stopped' | 'delivery';

// 条目级实体（用户消息快照——文本 only 无附件；conversationId = G6 会话锚点校验位；persisted
// = 写穿落库标志〔false = 内存暂存——派发闸不选未落库项，防「行未落就派发」→ 事务删行 0 命中
// + 复活成孤儿行〕）
export interface QueueItem {
  id: string;
  conversationId: string;
  text: string;
  designateId: string;
  queuedAt: number;
  state: QueueItemState;
  persisted: boolean;
}

// 会话级运行态载荷（v58 暂停位落库）：save/load 对称的搬运结构，字段与内存真值同形——
// runState 值域 'ACTIVE' | 'PAUSED'；pauseReason 值域同 QueuePauseReason 加 ''。
export interface QueueRunState {
  runState: string;
  pauseReason: string;
}

// 持久化口（写穿——实现位 = ChatSendEntryGate，行读写单源 = ChatSendQueueDb；本件只消费
// 接口零 import）。属性式函数类型（arkts-no-untyped-obj-literals）：
// · insert 返 false = 会话行未出生（内存暂存后续 flush 重试）；抛错 = 真失败（回滚条目 +
//   归还输入 + toast）；其余写口失败只 toast（内存态保持，下次 hydrate 以库为准）。
// ★ loadState/saveState **必填**不是可选——设为可选会让「适配位漏接线」静默退化成「暂停位
// 不落库」原样复发；loadState 失败由调用方降级 ACTIVE，saveState 失败只 toast。
export interface ChatSendQueuePersistence {
  load: () => Promise<QueueItem[]>;
  insert: (item: QueueItem, sortOrder: number) => Promise<boolean>;
  updateText: (item: QueueItem) => Promise<void>;
  remove: (id: string) => Promise<void>;
  removeAll: (conversationId: string) => Promise<void>;
  reorder: (items: QueueItem[]) => Promise<void>;
  loadState: () => Promise<QueueRunState>;
  saveState: (state: QueueRunState) => Promise<void>;
}

// 宿主接口（ChatSendCtrl 构造闭包集实现；属性式函数类型纪律〔arkts-no-untyped-obj-literals〕；
// 箭头闭包持宿主态现读，本件不缓存任何宿主态）
export interface ChatSendQueueHost {
  // G5：生成中真值（refs.sending() 真值面直读——不经页面 @State 镜像）
  sending: () => boolean;
  // 就绪门（自检修复高2）：dbReady + conn 解析 + 历史装载三件全真才允许派发——未就绪只让位
  //（不置 IN_FLIGHT、不暂停、不消费恢复意图），防 hydrate 首派发撞 T4b 假暂停 + 误 toast +
  // 重启不自动续发；可选位 = 直跑夹具缺省视为就绪，生产实现位 = ChatSendCtrl.queueDispatchReady
  dispatchReady?: () => boolean;
  // G6：会话锚点（运行态会话 id 现读）
  conversationId: () => string;
  // 满队/派发失败/惰性门暂停/写穿失败提示出口（面向用户文案已过写作规约）
  toast: (message: string) => void;
  // 写穿失败归还文本（条目回滚、文本回输入条——输入不丢；排队恒无附件故只还文本）
  restoreInput: (text: string) => void;
  // Q3 持久化口（构造期 hydrate + 入队/编辑/删除/清空/换序写穿——实现位 ChatSendEntryGate）
  persistence: ChatSendQueuePersistence;
  // G7：轮终态内存快照读口（lastSettleCause 真值面挂 ChatSessionRuntime 运行态）
  lastSettleCause: () => string;
  // T4 载荷化派发口（四参：text/designateId/queueItemId/autoDispatch——queueItemId 贯通
  // beginSend 供事务删行；autoDispatch = 自动连发〔非「立即发送」〕拽底判读用）：true =
  // 已交编排（≠已投递——T4a/T4c 收口）；false = 同步拒绝走 T4b——宿主不再另 toast，暂停
  // 提示由本域单源下发（防双 toast）
  dispatchQueued: (text: string, designateId: string, queueItemId: string,
    autoDispatch: boolean) => boolean;
  // T6 插队停止口（既有 abort 链零改动——markUserStop 最先等顺序红线不动）
  abortActive: () => void;
  // 边沿观察者注册/注销（refs 壳可注销观察者列表——成对，构造 attach / disposeSilent detach）
  attachSendingEdge: (watcher: (sending: boolean) => void) => void;
  detachSendingEdge: (watcher: (sending: boolean) => void) => void;
}

// 队列上限（chatbox 同款 MAX_QUEUED_MESSAGES，裁定丙-10）
const QUEUE_MAX_ITEMS: number = 20;

export class ChatSendQueueCtrl {
  private host: ChatSendQueueHost;
  // 条目表（FIFO 序：队首 = 下一条待发；内存态——Q3 落库后 hydrate 重建）
  private items: QueueItem[] = [];
  // 会话级运行态（§4.1 QueueRun：'ACTIVE' 自动派发开 / 'PAUSED' 惰性暂停；空队列无状态）
  private runState: string = 'ACTIVE';
  private pauseReason: string = '';
  // hydrate 竞态守卫：构造后用户已改过运行态（暂停/恢复/插队），晚到库值不覆写（内存优先
  //——DB 是下一拍的持久镜像）
  private stateTouched: boolean = false;
  // G4 组装窗口双发防线（派发置位、回执/T4b/T4c 终局清——真沿不清，自检修复中1）
  private dispatchLatch: boolean = false;
  // G3 拖拽排序锁（T10：排序中锁派发不丢弃，落定解锁补一次派发试探）
  private dragHeld: boolean = false;
  // T6 防重复 abort 位（连续「立即发送」只发起一次 abort；下降沿复位——可再次 abort 的时刻）
  private abortRequested: boolean = false;
  // T3 恢复越过惰性门的一次性意图位（resume 置位，派发尝试时消费——chatbox 教益4）
  private forceResumePending: boolean = false;
  // 微任务去重位（一次沿/入队多次 schedule 只排一个微任务；dispatchNext 出口复位）
  private microtaskScheduled: boolean = false;
  // 条目 id 铸造序号（配合时间戳保进程内唯一——照 ChatRunScope 形态）
  private idSeq: number = 0;
  // 通知面（count/paused 双参回调列表——U1 入口条/U2 面板注册消费；注册注销成对）
  private listeners: ((count: number, paused: boolean) => void)[] = [];
  // Q3：销毁闸（异步写穿/装载回调落地时运行态可能已回收——命中即弃，禁触已亡域件）
  private disposed: boolean = false;
  // Q3：落库在途条目 id 集（flush 去重——同一条目并发两次 insert 会撞主键；写链 FIFO 只保序）
  private persistingIds: Set<string> = new Set<string>();

  // 观察者回调（构造时注册 refs 壳——箭头成员免 bind）：回调内禁同步直派
  private onSendingEdge = (sending: boolean): void => {
    if (sending) {
      // 真沿不清闩也不摘项（自检修复中1）：setSending(true) 先于 beginSend 事务——此刻清闩
      // 会在「abort 落提交窗口 + 另有跳队项」时双派发；摘项同理会让 T4c 找不到在途项。终局
      // 收口 = onDispatchCommitted（回执）/ T4b / T4c
      return;
    } else {
      // 下降沿 = 轮收尾：复位防重复 abort 位（可再次 abort 的时刻）+ 推进（T5）；出队体恒
      // 微任务，禁此处直派
      this.abortRequested = false;
      this.scheduleDispatch();
    }
  };

  constructor(host: ChatSendQueueHost) {
    this.host = host;
    // attach 时注册（成对释放红线：disposeSilent 注销——reclaim 链经宿主 disposeSilent 到达）
    host.attachSendingEdge(this.onSendingEdge);
    // 构造期装载（会话 acquire 同时机）：读表重建全 QUEUED 条目 + 恢复库内暂停位（v58——
    // 重启/5s 回收后重进保持暂停，不再自动续发）；异步落地后 notify + 派发试探
    this.hydrateFromDb();
  }

  // ── 启动装载（会话 acquire 时 hydrate）：串行两段——先读运行态（独立 catch 降级 ACTIVE，
  // 状态读失败不击穿条目装载）再读条目；PAUSED 恢复后 scheduleDispatch 照常调（G1 按
  // runState 拦，空转零副作用）。守卫：①stateTouched 内存优先；②脏值只认 'PAUSED'（防脏行
  // 锁死队列）；③空队列强制回 ACTIVE 并回写（不留 PAUSED+0 行）；④不按「rows 为空即早退」
  //——否则空表无法清残留暂停位、也无法上行刷新面板
  private hydrateFromDb(): void {
    const before: number = this.items.length;
    const pausedBefore: boolean = this.runState === 'PAUSED';
    this.host.persistence.loadState()
      .catch((): QueueRunState => {
        const fallback: QueueRunState = { runState: 'ACTIVE', pauseReason: '' };
        return fallback;
      })
      .then((st: QueueRunState): Promise<QueueItem[]> => {
        if (!this.disposed && !this.stateTouched) {
          this.runState = st.runState === 'PAUSED' ? 'PAUSED' : 'ACTIVE';
          this.pauseReason = this.runState === 'PAUSED' ? st.pauseReason : '';
        }
        return this.host.persistence.load();
      })
      .then((rows: QueueItem[]): void => {
        if (this.disposed) {
          return;
        }
        // 合并：DB 行在前（先入队者先派发）、构造期已入队的内存条目在后；按 id 去重
        //（装载查询与在途入队插入交错的防御）
        const known: Set<string> = new Set<string>();
        const merged: QueueItem[] = [];
        for (const row of rows) {
          if (!known.has(row.id)) {
            known.add(row.id);
            merged.push(row);
          }
        }
        for (const item of this.items) {
          if (!known.has(item.id)) {
            known.add(item.id);
            merged.push(item);
          }
        }
        if (merged.length > 0) {
          this.items = merged;
        }
        const pausedNow: boolean = this.runState === 'PAUSED';
        // 空队列无状态：合并后仍空却有 PAUSED 残留 → 回 ACTIVE 并回写（不留 PAUSED+0 行）
        if (this.items.length === 0) {
          if (pausedNow && !this.stateTouched) {
            this.setRunState('ACTIVE', '');
            this.notify();
          }
          return;
        }
        // 集与态都无变化才零动作（原「集相同即早退」会让暂停位恢复漏上行——面板副行不刷新）
        if (merged.length !== before || pausedNow !== pausedBefore) {
          this.notify();
        }
        // G1 自会按 runState 拦（PAUSED 时本拍空转，等 resume 的显式派发）
        this.scheduleDispatch();
      })
      .catch((_e: Object): void => {
        // 装载失败（DB 未就绪/读抛错）= 保持空集、**零回写零 notify**：库内条目与暂停位原样
        // 留存待重装。禁归一 ACTIVE——那会把「读不成」误判成「队列真空」覆盖库内 PAUSED
      });
  }

  // 就绪补派发（宿主在 conn 解析完成/历史装载收尾时调用）：未就绪期让位的派发在此补一次
  //（空队列零动作；是否真派发由 dispatchReady 与 G1~G8 自判）
  notifyReadyChange(): void {
    if (this.disposed || this.items.length === 0) {
      return;
    }
    this.scheduleDispatch();
  }

  // ── 只读面（U1 入口条 / U2 面板消费）──
  itemCount(): number {
    return this.items.length;
  }

  isPaused(): boolean {
    return this.runState === 'PAUSED';
  }

  pauseReasonOf(): string {
    return this.pauseReason;
  }

  // 条目快照（浅拷贝数组——面板自持有读取；条目对象为可变实体，键恒含 id）
  snapshotItems(): QueueItem[] {
    return this.items.slice();
  }

  // ── 通知面（T1/T2/T3 等状态变化后上行——count/paused 双参）──
  addOnQueueChange(listener: (count: number, paused: boolean) => void): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  removeOnQueueChange(listener: (count: number, paused: boolean) => void): void {
    this.listeners = this.listeners.filter((l: (count: number, paused: boolean) => void): boolean =>
      l !== listener);
  }

  // ── T1/T1e 入队（sending 与否均可；dbReady/墓碑守卫在入口层 send 守卫链——不在本件）──
  enqueue(text: string, designateId: string): boolean {
    // 域件再守文本 only（带附件由入口层首拦）+ 空文本不入队
    if (text === '') {
      return false;
    }
    // T1e 上限 20：满队 toast + 拒绝（调用方保留输入——chatbox 上限口径）
    if (this.items.length >= QUEUE_MAX_ITEMS) {
      this.host.toast('排队消息已达 20 条上限');
      return false;
    }
    this.idSeq++;
    const item: QueueItem = {
      id: 'queue_' + Date.now() + '_' + this.idSeq,
      conversationId: this.host.conversationId(),
      text: text,
      designateId: designateId,
      queuedAt: Date.now(),
      state: 'QUEUED',
      // Q3 写穿：先内存后落库；落库成功才允许派发（persisted=false 时派发闸让位）
      persisted: false
    };
    this.items.push(item);
    this.notify();
    // Q3 写穿落库（异步；成功置 persisted + 补派发试探；失败回滚条目 + 归还输入 + toast）
    this.persistItem(item);
    // rikkahub「无条件入队 + 尝试派发」竞态免疫：入队即派发试探（微任务；G1~G8 闸内自判
    //——任一不满足自然空转，等下一个沿或写穿落地）
    this.scheduleDispatch();
    return true;
  }

  // ── 写穿：单条落库（入队/无行会话暂存重试共用；persistingIds 去重）──
  private persistItem(item: QueueItem): void {
    if (this.disposed || item.persisted || this.persistingIds.has(item.id)) {
      return;
    }
    const order: number = this.items.indexOf(item);
    if (order < 0) {
      return; // 已离队（删除/清空）——不落库
    }
    this.persistingIds.add(item.id);
    this.host.persistence.insert(item, order).then((stored: boolean): void => {
      this.persistingIds.delete(item.id);
      if (this.disposed) {
        return;
      }
      // false = 会话行未出生：保持内存暂存，等 flush 重试（文件头⑬①——不产孤儿行不丢消息）
      if (!stored || this.items.indexOf(item) < 0) {
        return;
      }
      item.persisted = true;
      this.scheduleDispatch();
    }).catch((_e: Object): void => {
      this.persistingIds.delete(item.id);
      if (this.disposed) {
        return;
      }
      // 写穿失败回滚（chatbox 教益1）：条目移除（永不静默丢）+ 文本归还输入条 + toast；条目
      // 已被删除/清空时静默收口（不把已删消息还回输入条）
      const at: number = this.items.indexOf(item);
      if (at < 0) {
        return;
      }
      this.items.splice(at, 1);
      this.notify();
      this.host.restoreInput(item.text);
      this.host.toast('排队消息保存失败，请重试');
    });
  }

  // 暂存 flush（无行会话条目在派发试探时重试落库——会话行出生后即成功）
  private flushUnpersisted(): void {
    for (const item of this.items) {
      if (!item.persisted) {
        this.persistItem(item);
      }
    }
  }

  // ── T2 手动暂停（三处 UI 同步由 notify 承接；v58 暂停位写穿落库——重启/5s 回收后重进
  // 保持暂停）。空队列无状态 → 零动作（UI 已按空队列禁用，此处为域件最后一道防线）──
  pause(): void {
    if (this.items.length === 0) {
      return;
    }
    this.setRunState('PAUSED', 'user');
    this.notify();
  }

  // ── T3 手动恢复：清暂停 + 立即派发试探（forceResume 越过 error/delivery/stopped 惰性门
  //——chatbox 教益4）──
  resume(): void {
    this.setRunState('ACTIVE', '');
    this.forceResumePending = true;
    this.notify();
    this.scheduleDispatch();
  }

  // ── T6 立即发送（插队，机理见文件头⑥）──
  jumpSend(id: string): void {
    const idx: number = this.items.findIndex((i: QueueItem): boolean => i.id === id);
    if (idx < 0) {
      return; // T8 删除竞态：标记随项消亡
    }
    const item: QueueItem = this.items[idx];
    if (item.state === 'IN_FLIGHT') {
      return; // 派发中项不可再插队（自家在飞——等真沿/T4b/T4c 收口）
    }
    this.items.splice(idx, 1);
    this.items.unshift(item);
    item.state = 'JUMP_PENDING';
    // 清暂停位（「立即发送 = 插队 + 恢复发送」语义）；同步落库
    this.setRunState('ACTIVE', '');
    this.notify();
    if (this.host.sending()) {
      if (!this.abortRequested) {
        this.abortRequested = true;
        this.host.abortActive();
      }
      return; // 收尾 false 下降沿 → 微任务优先派发本项（JUMP_PENDING 豁免 G1/G7）
    }
    this.scheduleDispatch();
  }

  // ── T7 编辑占位（U3 半模态消费）：置位（G2 拦派发——队头占位防队头卡死）。仅 QUEUED 可
  // 置位（自检修复中2——面板已按状态门控，JUMP_PENDING/IN_FLIGHT 不会到本口）──
  markEditing(id: string): void {
    const item: QueueItem | undefined = this.items.find((i: QueueItem): boolean => i.id === id);
    if (item !== undefined && item.state === 'QUEUED') {
      item.state = 'EDITING';
      this.notify();
    }
  }

  // 编辑保存/取消/onWillDismiss 三路释放之一（+ disposeSilent 兜底——配对释放）
  clearEditing(id: string): void {
    const item: QueueItem | undefined = this.items.find((i: QueueItem): boolean => i.id === id);
    if (item !== undefined && item.state === 'EDITING') {
      item.state = 'QUEUED';
      this.notify();
      // 队头占位解除——补派发试探（防队头永久卡死）
      this.scheduleDispatch();
    }
  }

  // 编辑保存（T7）：只改文本（附件与 designateId 随条目原样）；同步落库（失败只 toast，
  // 内存态保持——下次 hydrate 以库为准）
  updateItemText(id: string, text: string): void {
    const item: QueueItem | undefined = this.items.find((i: QueueItem): boolean => i.id === id);
    if (item !== undefined && text !== '') {
      item.text = text;
      this.notify();
      this.host.persistence.updateText(item).catch((_e: Object): void => {
        this.host.toast('排队消息保存失败，请重试');
      });
    }
  }

  // ── T8 删除单项：jump 标记随项消亡（abort 在途删除 → 收尾后按常规门走）；行删除同步落库
  //（失败只 toast——内存已移除，重进以库为准）──
  deleteItem(id: string): void {
    const idx: number = this.items.findIndex((i: QueueItem): boolean => i.id === id);
    if (idx >= 0 && this.items[idx].state !== 'IN_FLIGHT') {
      this.items.splice(idx, 1);
      // 空队列无状态：删末项回 ACTIVE 并写穿——防暂停位残留致下一条意外入队即停
      if (this.items.length === 0) {
        this.setRunState('ACTIVE', '');
      }
      this.notify();
      this.host.persistence.remove(id).catch((_e: Object): void => {
        this.host.toast('排队消息删除失败，请重试');
      });
    }
  }

  // ── T9 清空（二次确认在 U2 调用方）：空队列回缺省态并写穿；在飞项随本清空离队——其库行
  // 由 beginSend 事务删，两不相干（闩终局清见文件头④）。会话全量行删除同步落库 ──
  clearAll(): void {
    this.items = [];
    // 空队列无状态：回 ACTIVE 并写穿——清空后重启不残留暂停位
    this.setRunState('ACTIVE', '');
    this.notify();
    this.host.persistence.removeAll(this.host.conversationId()).catch((_e: Object): void => {
      this.host.toast('排队消息清空失败，请重试');
    });
  }

  // ── T10 落定换序（U2 onMove 落定调用）：orderedIds = 整组替换后的 id 全序（键 = item.id
  // 恒定，序号派生不入键——坑44/80 键纪律由整表重建承接）。非法序（长度/成员/重复不符）
  // 整笔拒绝零动作（防拖拽事件乱序数据源）；整组 sortOrder 重写落库 ──
  applyOrder(orderedIds: string[]): void {
    if (orderedIds.length !== this.items.length) {
      return;
    }
    const next: QueueItem[] = [];
    for (const id of orderedIds) {
      const item: QueueItem | undefined =
        this.items.find((i: QueueItem): boolean => i.id === id);
      if (item === undefined || next.includes(item)) {
        return; // 未知 id / 重复 id —— 整笔拒绝
      }
      next.push(item);
    }
    this.items = next;
    this.notify();
    this.host.persistence.reorder(this.items).catch((_e: Object): void => {
      this.host.toast('排队顺序保存失败，请重试');
    });
  }

  // ── T10 拖拽互斥（裁定丙-7，事件面 U2 接）：排序中锁派发（G3 拦不丢弃）；落定解锁补一次
  // 派发试探（整组替换与换序持久化在 U2）──
  setDragHeld(held: boolean): void {
    this.dragHeld = held;
    if (!held) {
      this.scheduleDispatch();
    }
  }

  // ── T4a 投递确认（beginSend 事务提交回执——queueItemId 非空的事务已把排队行与 user 行 +
  // run 行同笔提交）：IN_FLIGHT 项正式出队 + 清闩；非队列路径（queueItemId 空/项已回滚）零
  // 动作（清闩仅为幂等）──
  onDispatchCommitted(queueItemId: string): void {
    if (queueItemId === '') {
      return; // 非队列派发（手动/重试）：不拥有闩——禁误清队列派发在途的闩
    }
    // 闩只在本回执清（真沿不清——自检修复中1）
    this.dispatchLatch = false;
    const idx: number = this.items.findIndex((i: QueueItem): boolean =>
      i.id === queueItemId && i.state === 'IN_FLIGHT');
    if (idx >= 0) {
      this.items.splice(idx, 1);
      // 空队列无状态：末项随事务提交出队即回 ACTIVE 并写穿——否则「暂停中在飞项提交」留
      // PAUSED+0 行脏状态，重启后新消息入队被 G1 拦住
      if (this.items.length === 0) {
        this.setRunState('ACTIVE', '');
      }
      this.notify();
    }
    // 清闩后补一次派发试探（本轮仍在生成时首行 sending 守卫自然让位；已收尾则立即续派
    // 不等沿；跳队项等闩场景借此续上）
    this.scheduleDispatch();
  }

  // ── T4c 受理后组装失败回滚链（宿主在「send 已返回 true 但无 setSending 真沿」的失败出口
  // 各一行接线到达此处）：按 queueItemId 匹配回队头 + 清闩 + 排队行不删（事务从未发起）+
  // PAUSED('delivery') + toast，永不静默丢消息。入参身份必带——abort 反向插入时「第一个
  // IN_FLIGHT」可能已不是本派发项，按状态猜会回滚错项（且派发项成幽灵项）──
  onDispatchAbandoned(queueItemId: string): void {
    if (queueItemId === '') {
      // 非队列派发（用户手动发送/重试）组装失败——不拥有闩：零动作（禁误清队列派发的闩 /
      // 误 PAUSED / 误 toast；T4c 只认自家 IN_FLIGHT 项）
      return;
    }
    // 闩只在本回滚清（真沿不清）
    this.dispatchLatch = false;
    const idx: number = this.items.findIndex((i: QueueItem): boolean =>
      i.id === queueItemId && i.state === 'IN_FLIGHT');
    if (idx < 0) {
      return; // 项已不在飞（清空 / 已被收口）——只清闩，不误伤其他项
    }
    const item: QueueItem = this.items[idx];
    item.state = 'QUEUED';
    this.items.splice(idx, 1);
    this.items.unshift(item);
    this.pauseFor('delivery', '发送未成功，队列已暂停');
    this.notify();
  }

  // ── T12 运行态销毁清理（reclaim 链经 ChatSendCtrl.disposeSilent 连带到达）──
  disposeSilent(): void {
    this.disposed = true;
    this.host.detachSendingEdge(this.onSendingEdge);
    for (const item of this.items) {
      if (item.state === 'EDITING') {
        item.state = 'QUEUED';
      }
    }
    this.persistingIds.clear();
    this.dispatchLatch = false;
    this.forceResumePending = false;
    this.abortRequested = false;
    this.microtaskScheduled = false;
    this.listeners = [];
  }

  // ── 推进调度（微任务单出口——T1/T3/T5/T6/T10 全部经此；去重防同拍多排）──
  private scheduleDispatch(): void {
    if (this.microtaskScheduled) {
      return;
    }
    this.microtaskScheduled = true;
    // 出队体恒微任务：全部 setSending(false) 写点与配对归还同同步块，微任务在调用栈清空后
    // 执行 → releaseRun 必已完成，顺序恒「收尾写 → 下一轮 beginSend」
    Promise.resolve().then((): void => {
      this.microtaskScheduled = false;
      this.dispatchNext();
    });
  }

  // ── T4/T5 派发（G1~G8 逐闸；T5 = 下降沿微任务进来、G7 惰性门在列）──
  private dispatchNext(): void {
    // 就绪门（自检修复高2，判据见宿主 dispatchReady 注释）：未就绪只让位（不置 IN_FLIGHT、
    // 不清恢复意图、不暂停），由宿主就绪点经 notifyReadyChange 补——防 hydrate 首派发撞 T4b
    // 假暂停 + 误 toast
    const ready: (() => boolean) | undefined = this.host.dispatchReady;
    if (ready !== undefined && !ready()) {
      return;
    }
    // 入口再验（单活跃 run 红线9，G5 真值面直读）：微任务排队期间用户已手动起轮 → 让位
    //（该轮收尾下降沿再推进）
    if (this.host.sending()) {
      return;
    }
    // G3 排序中锁派发（T10）
    if (this.dragHeld) {
      return;
    }
    // G4 组装窗口双发防线
    if (this.dispatchLatch) {
      return;
    }
    // 选中派发项：JUMP_PENDING 优先（T5/T6——豁免 G1 暂停位与 G7 终态门）；否则队头
    let idx: number = this.items.findIndex((i: QueueItem): boolean => i.state === 'JUMP_PENDING');
    const jump: boolean = idx >= 0;
    if (!jump) {
      // G1 队列非空 && ACTIVE && !paused（JUMP_PENDING 项豁免本门——裁定丙-4）
      if (this.items.length === 0 || this.runState !== 'ACTIVE') {
        return;
      }
      idx = 0;
      // G2 队头非 EDITING 占位（rikkahub 三重门之一——占位泄漏防队头卡死）
      if (this.items[idx].state === 'EDITING') {
        return;
      }
    }
    const item: QueueItem = this.items[idx];
    // 选中项统一再验 EDITING 占位（跳队分支也复核——G2 只拦非跳队分支；UI 已门控，此处为
    // 域件最后一道防线）
    if (item.state === 'EDITING') {
      return;
    }
    // 写穿闸：选中项未落库（入队写穿在途/无行会话暂存）→ 不让位整队，先补落库并让位本拍
    //（成功回调补派发试探；防「行未落就派发」→ 事务删行 0 命中 + 复活成孤儿行）
    if (!item.persisted) {
      this.flushUnpersisted();
      return;
    }
    // G6 会话锚点校验（防御：级联删行后内存镜像随 hydrate/回收对齐；不符跳过不派发）
    if (item.conversationId !== this.host.conversationId()) {
      return;
    }
    // G7 惰性终态门（裁定丙-5；黑名单处置见文件头⑦，JUMP_PENDING 与 T3 恢复豁免）。
    // lastSettleCause 值域 = finishStream 入口 roundStatusAtFinish（'done'/'stopped'/'error'，
    // interrupted 已映射 'stopped'）+ 缺省 'ok'（工具重发为常态成功路径）
    if (!jump && !this.forceResumePending) {
      const cause: string = this.host.lastSettleCause();
      if (cause === 'error' || cause === 'stopped' || cause === 'interrupted') {
        this.pauseFor(cause === 'error' ? 'error' : 'stopped',
          cause === 'error' ? '上一条回复出错，队列已暂停' : '当前回复已停止，队列已暂停');
        // 暂停态上行（入口条/面板同步；T2/T4b/T4c 同走 notify——G7 自动暂停不得静默）
        this.notify();
        return;
      }
    }
    // T4 派发：置闩 + item 置 IN_FLIGHT（内存闩，不落库）→ 载荷化 send。G8 守卫重验失败面
    //（dbReady/conn/墓碑）不预检——交 send() 返回 false → T4b 统一处置（防双 toast）；
    // forceResume 意图在真实派发尝试时消费
    this.forceResumePending = false;
    this.dispatchLatch = true;
    item.state = 'IN_FLIGHT';
    // 载荷化四参：queueItemId 贯通 beginSend（事务删行）；autoDispatch 仅自动连发为真——
    //「立即发送」（JUMP_PENDING）属用户动作恒拽底
    const autoDispatch: boolean = !jump;
    const accepted: boolean = this.host.dispatchQueued(item.text, item.designateId, item.id,
      autoDispatch);
    if (!accepted) {
      // T4b 同步拒绝：item 回 QUEUED 原位（派发未摘除——原位即头位）+ PAUSED('delivery')
      // + toast；不自动重试、永不丢（撞占用闸统一处置）
      item.state = 'QUEUED';
      this.dispatchLatch = false;
      this.pauseFor('delivery', '发送未成功，队列已暂停');
      this.notify();
    }
    // 受理（true）：保持 IN_FLIGHT + 闩——beginSend 事务提交回执确认出队（T4a，
    // onDispatchCommitted）或失败通知回滚（T4c）收口
  }

  // 暂停转移单出口（T4b/T4c/G7 共用）：置 PAUSED(因) + 单次提示；同步写穿
  private pauseFor(reason: QueuePauseReason, message: string): void {
    this.setRunState('PAUSED', reason);
    this.host.toast(message);
  }

  // ── 运行态决定单出口（内存 + 落库；决定性写点经此，禁再散写——hydrate 初始装载直写除外，
  // 见 hydrateFromDb 的 stateTouched 守卫）──
  private setRunState(state: string, reason: string): void {
    this.runState = state;
    this.pauseReason = reason;
    this.stateTouched = true;
    this.persistRunState();
  }

  // 暂停位写穿（fire-and-forget：内存已生效，失败只 toast——与删除/清空/换序同口径，
  //「重进以库为准」属如实语义；disposed 后不写不提示，禁触已亡域件）
  private persistRunState(): void {
    if (this.disposed) {
      return;
    }
    const state: QueueRunState = { runState: this.runState, pauseReason: this.pauseReason };
    this.host.persistence.saveState(state).catch((_e: Object): void => {
      if (this.disposed) {
        return;
      }
      this.host.toast('排队状态保存失败，请重试');
    });
  }

  private notify(): void {
    const count: number = this.items.length;
    const paused: boolean = this.runState === 'PAUSED';
    // slice 遍历（回调内注销自身不改遍历面）
    this.listeners.slice().forEach((l: (count: number, paused: boolean) => void): void => {
      l(count, paused);
    });
  }
}
