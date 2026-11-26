// 直播中枢：**会话轮次直播事件的进程级扇出点**——生成链三挂点（轮开始/增量/终态）旁路喂
// 事件进来，本件扇出给订阅者（会话分桶 + 全局桶），对上层载体零感知（WS 网关/直播镜像器/
// SSE 备胎全是下游的事——传输抽象纪律）。
// 架构位：web 端直播要「手机生成过程单向外发」，但会话编排链不能 import web 域（零环红线）
//——三挂点旁路喂数（流控件不 import 本件，经 ChatStreamLiveTap 接口注入；流回调直写区
// 只加旁路，揭示/冻结/排空语义零变化）；订阅者来去不动生成链一行。
// 事件信封 v1：{v, seq, type, conversationId, origin, payload}；四事件 = round_begin /
// round_delta（payload = 当前轮已揭示全文——整段替换模型，不预付 diff 优化）/ round_end
//（payload.status 四态 done/error/stopped/interrupted，finishStream 入口语义）/
// conv_invalidate（终态落库后会话列表失效信号）；origin 由运行态 roundOrigin 单源供给
//（三挂点发布时现读——UI 缺省 'local' / web 无头宿主置 'web'，web 前端防回环双写 +
// 审计区分发起端）。
// 订阅模型：Map<conversationId|null, Set<订阅者>> 会话分桶 + 全局桶（null 桶收全部会话事件
//——**全会话广播已拍板**，不做会话级窄播，web 前端按信封 conversationId 自行过滤渲染）；
// 订阅者多订阅广播（已拍板，禁轻量案）；订阅者接口最小面 {onEvent(ev)}，身份 = 对象本身。
// 数据有界（红线）：零事件暂存纯扇出（零缓存——重连/迟订正解 = snapshot，事件不回放）；
// 订阅者每桶有上限（超限拒绝返回 false，禁静默）；wire 登记随会话桶生命周期天然有界。
// 生命周期（寿命匹配红线）：进程级单例，不得长持短寿命对象——订阅者必须可注销
//（unsubscribe 完整清理桶与 wire）；watcher 与 tap 由 lazy attach 装配、unwire 摘除（成对）。
// 依赖纪律（零环，坑50）：本件 → chatSessionRuntime 与 ChatStreamLiveTap（type-only）单向
//——流控件与运行时零回边（不 import 本件）；轮开始 watcher 经 refs 壳可选员位
// attachSendingEdge 挂接（生产 refs 恒实现；直跑夹具 refs 未接时 undefined 空转）。
// 挂点时序契约：wire 驱动方 = 消费侧——subscribe 非空桶自动尝试 + 显式 ensureSessionWired /
// retainSessionWire；账目不在场 = 本轮不挂返回 false（事件不回放，等消费侧下次调用）；
// 幂等 + 账目身份复验（账目空闲回收重建时 stale 登记自动清旧挂新）。
// ★ wire 租约（retain/releaseSessionWire）：只补 wire 不订阅的消费侧（泵浏览开会话）必须
// 有成对释放面，否则 wire 强持空闲回收后的运行态且摘线无触发点；租约计数与订阅桶双条件
// 共同决定 unwire，任一持有方在场即保线。
// ★ 建族告知（onRuntimeAcquired）：web 先开会话、手机后建族的时序下 wire 不能在开会话那
// 一刻挂上，账目建成时按「桶或租约有关切」即时补挂（否则手机发起的轮镜不到 web）。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { chatSessionRuntime, ChatRuntimeState } from './ChatSessionRuntime';
import { ChatStreamLiveTap } from '../../components/chat/ChatStreamFlowCtrl';
import { registerChatLivePublish } from './ChatLiveSink';

// 订阅者每桶上限（web 侧单镜像器 + 诊断面足够；超限拒绝注册非静默）
const LIVE_MAX_SUBSCRIBERS_PER_TOPIC: number = 16;

// 事件信封版本（v1——信封演进位）
const LIVE_ENVELOPE_VERSION: number = 1;

// 事件来源标记：'web' 由无头宿主注入，缺省 'local'
export type ChatLiveOrigin = 'local' | 'web';

// 四事件类型（snapshot/server_paused/ping 族属传输与读域信封，非本件扇出面）
export type ChatLiveEventType = 'round_begin' | 'round_delta' | 'round_end' | 'conv_invalidate';

// 事件负载（四事件统一结构、未用字段空串——负载自足）：text/reasoning = 当前轮权威累积
// 正文/思考全文（整段替换模型要求全文随行；reasoning web 端按需取舍）；status 仅
// round_end 有值（done/error/stopped/interrupted 四态）
export interface ChatLivePayload {
  readonly text: string;
  readonly reasoning: string;
  readonly status: string;
}

// 事件信封 v1
export interface ChatLiveEvent {
  readonly v: number;
  readonly seq: number;
  readonly type: ChatLiveEventType;
  readonly conversationId: string;
  readonly origin: ChatLiveOrigin;
  readonly payload: ChatLivePayload;
}

// 订阅者接口（最小面 {onEvent(ev)}；身份 = 对象本身，注销交回同一对象）
export interface ChatLiveSubscriber {
  onEvent(event: ChatLiveEvent): void;
}

// wire 登记（每已挂会话一条）：轮开始 watcher（sendingEdge 真沿）+ 增量/终态 tap（装配
// 适配器）+ 挂靠账目身份（空闲回收重建后的 stale 复验面）
interface ChatLiveWireEntry {
  readonly conversationId: string;
  readonly watcher: (sending: boolean) => void;
  readonly tap: ChatStreamLiveTap;
  readonly stateAtWire: ChatRuntimeState;
}

export class ChatLiveHub {
  // 主题桶表：conversationId → 订阅者集（null 键 = 全局桶，收全部会话事件）
  private topics: Map<string | null, Set<ChatLiveSubscriber>> =
    new Map<string | null, Set<ChatLiveSubscriber>>();
  // wire 登记表（lazy attach 成果；条目随会话桶——桶空即 unwire 删条目，天然有界）
  private wires: Map<string, ChatLiveWireEntry> = new Map<string, ChatLiveWireEntry>();
  // ★ wire 租约表（conversationId → 持有数）：只补 wire 不订阅的消费侧成对取用——与订阅桶
  // 共同构成 wire 的两类持有方；条目随释放归零删除（天然有界）
  private wireLeases: Map<string, number> = new Map<string, number>();
  // 进程内事件序号（单源单调递增；零订阅者不产事件不前进——kill-switch 语义的零行为增量）
  private seq: number = 0;

  // 订阅者注册（conversationId = null 即全局桶）：桶满拒绝返回 false（调用方必须检查，禁
  // 静默）；同对象重复注册幂等；非空桶注册后自动尝试 wire（账目不在场不视为失败，消费侧
  // 建族后 ensureSessionWired 自愈）
  subscribe(conversationId: string | null, subscriber: ChatLiveSubscriber): boolean {
    let bucket: Set<ChatLiveSubscriber> | undefined = this.topics.get(conversationId);
    if (bucket === undefined) {
      bucket = new Set<ChatLiveSubscriber>();
      this.topics.set(conversationId, bucket);
    }
    if (bucket.size >= LIVE_MAX_SUBSCRIBERS_PER_TOPIC && !bucket.has(subscriber)) {
      return false;
    }
    bucket.add(subscriber);
    if (conversationId !== null) {
      this.ensureSessionWired(conversationId);
    }
    return true;
  }

  // 订阅者注销（幂等；成对释放面）：会话桶空 = 订阅持有方离场——**租约仍可能在场**（泵可能
  // 打开着该会话），只走双条件判定 unwireIfUnused（桶空即摘线会把泵仍在浏览的会话线摘掉）；
  // 账目已回收 = 各步幂等空转无害（watcher 随 state 整体消亡）
  unsubscribe(conversationId: string | null, subscriber: ChatLiveSubscriber): void {
    const bucket: Set<ChatLiveSubscriber> | undefined = this.topics.get(conversationId);
    if (bucket === undefined) {
      return;
    }
    bucket.delete(subscriber);
    if (bucket.size === 0) {
      this.topics.delete(conversationId);
      if (conversationId !== null) {
        this.unwireIfUnused(conversationId);
      }
    }
  }

  // ★ wire 租约取用（只补 wire 不订阅的消费侧，如泵浏览开会话）：账目在场即挂线并计数；
  // 不在场也计数（消费侧关切仍在，建族告知会补挂）——返回本次是否已挂上线（false 不代表
  // 租约失败，调用方仍须成对 releaseSessionWire）
  retainSessionWire(conversationId: string): boolean {
    if (conversationId === '') {
      return false;
    }
    const prev: number = this.wireLeases.get(conversationId) ?? 0;
    this.wireLeases.set(conversationId, prev + 1);
    return this.ensureSessionWired(conversationId);
  }

  // ★ wire 租约释放（幂等；成对）：计数归零且无订阅桶才摘线——订阅方与租约方任一在场即保线
  releaseSessionWire(conversationId: string): void {
    const prev: number = this.wireLeases.get(conversationId) ?? 0;
    if (prev <= 0) {
      return;
    }
    if (prev === 1) {
      this.wireLeases.delete(conversationId);
    } else {
      this.wireLeases.set(conversationId, prev - 1);
    }
    this.unwireIfUnused(conversationId);
  }

  // ★ 建族告知（运行态 acquire 新账目回调）：web 先开会话、手机后建族的时序下，开会话那
  // 一刻账目不在场无法挂线——账目建成时按「订阅桶非空或租约在场」补挂；无关切会话零动作
  onRuntimeAcquired(state: ChatRuntimeState): void {
    const conversationId: string = state.conversationId;
    const bucket: Set<ChatLiveSubscriber> | undefined = this.topics.get(conversationId);
    const leased: boolean = (this.wireLeases.get(conversationId) ?? 0) > 0;
    if (leased || (bucket !== undefined && bucket.size > 0)) {
      this.ensureSessionWired(conversationId);
    }
  }

  // 双条件摘线（私有）：无订阅桶且无租约 → unwire；任一在场保线
  private unwireIfUnused(conversationId: string): void {
    const bucket: Set<ChatLiveSubscriber> | undefined = this.topics.get(conversationId);
    const leased: number = this.wireLeases.get(conversationId) ?? 0;
    if ((bucket === undefined || bucket.size === 0) && leased === 0) {
      this.unwire(conversationId);
    }
  }

  // 会话接线（幂等 + 身份复验）：账目在场 → 挂轮开始 watcher（refs 壳可选员位）+ 注入
  // 增量/终态 tap；已挂且账目身份未变 → 直接过；登记 stale（账目回收重建）→ 清旧挂新；
  // 账目不在场 → false（消费侧下次调用，事件不回放）
  ensureSessionWired(conversationId: string): boolean {
    const state: ChatRuntimeState | null = chatSessionRuntime.get(conversationId);
    const wired: ChatLiveWireEntry | undefined = this.wires.get(conversationId);
    if (wired !== undefined && state !== null && wired.stateAtWire === state) {
      return true;
    }
    if (wired !== undefined) {
      this.unwire(conversationId);
    }
    if (state === null) {
      return false;
    }
    // 轮开始 = sendingEdge 真沿（false 下降沿无事件——终态由 finishStream 入口挂点发
    // round_end，队列推进等下降沿语义不属直播面）
    const watcher: (sending: boolean) => void = (sending: boolean): void => {
      if (sending) {
        this.publishRoundBegin(conversationId, this.originOf(conversationId));
      }
    };
    // 增量/终态旁路（ChatStreamLiveTap 为方法语法接口，ArkTS 对象字面量规则
    // arkts-no-untyped-obj-literals 拒收对象字面量实现——以类实现；类于方法体内定义
    // （局部类）使直跑夹具（只切类块注入）无需额外注入名）
    const tapHub: ChatLiveHub = this;
    class LiveTap implements ChatStreamLiveTap {
      private readonly owner: ChatLiveHub;
      private readonly conversationId: string;

      constructor(owner: ChatLiveHub, cid: string) {
        this.owner = owner;
        this.conversationId = cid;
      }

      onLiveDelta(fullText: string, reasoning: string): void {
        this.owner.publishRoundDelta(this.conversationId,
          this.owner.originOf(this.conversationId), fullText, reasoning);
      }

      onLiveRoundEnd(status: string, fullText: string, reasoning: string): void {
        this.owner.publishRoundEnd(this.conversationId, this.owner.originOf(this.conversationId),
          status, fullText, reasoning);
      }
    }
    const tap: ChatStreamLiveTap = new LiveTap(tapHub, conversationId);
    const entry: ChatLiveWireEntry = {
      conversationId: conversationId,
      watcher: watcher,
      tap: tap,
      stateAtWire: state
    };
    if (state.refs.attachSendingEdge !== undefined) {
      state.refs.attachSendingEdge(entry.watcher);
    }
    state.flow.setLiveTap(entry.tap);
    this.wires.set(conversationId, entry);
    return true;
  }

  // 轮发起端现读：三挂点发布时取当会话 state.roundOrigin——单源 = 运行态标记（UI 缺省
  // local / web 无头宿主置 web，轮终态由 setSending(false) 复位）；账目不在场或未标 =
  // local 缺省
  originOf(conversationId: string): ChatLiveOrigin {
    const state: ChatRuntimeState | null = chatSessionRuntime.get(conversationId);
    return state !== null && state.roundOrigin === 'web' ? 'web' : 'local';
  }

  // 会话摘线（unwire 成对释放）：摘 watcher + 摘 tap + 删登记，全幂等（旧 state 残员的
  // 摘除调用对已回收对象无害）
  private unwire(conversationId: string): void {
    const wired: ChatLiveWireEntry | undefined = this.wires.get(conversationId);
    if (wired === undefined) {
      return;
    }
    if (wired.stateAtWire.refs.detachSendingEdge !== undefined) {
      wired.stateAtWire.refs.detachSendingEdge(wired.watcher);
    }
    wired.stateAtWire.flow.setLiveTap(null);
    this.wires.delete(conversationId);
  }

  // ── 发布面（seq 单源在此；零订阅者不产事件不进序——kill-switch 语义零行为增量；origin
  // 由内部挂点经 originOf 现读运行态 roundOrigin 供给）──

  publishRoundBegin(conversationId: string, origin: ChatLiveOrigin): void {
    this.dispatch('round_begin', conversationId, origin, '', '', '');
  }

  publishRoundDelta(conversationId: string, origin: ChatLiveOrigin,
    text: string, reasoning: string): void {
    this.dispatch('round_delta', conversationId, origin, text, reasoning, '');
  }

  publishRoundEnd(conversationId: string, origin: ChatLiveOrigin, status: string,
    text: string, reasoning: string): void {
    this.dispatch('round_end', conversationId, origin, text, reasoning, status);
  }

  // 会话失效（终态落库后发布、刷 web 会话列表）
  publishConvInvalidate(conversationId: string, origin: ChatLiveOrigin): void {
    this.dispatch('conv_invalidate', conversationId, origin, '', '', '');
  }

  // 扇出（私有核心）：会话桶 + 全局桶订阅者全收（全会话广播裁定——会话 id 在信封上，
  // 过滤是消费侧的事）；快照遍历（订阅者在回调内注销自己或他人不破本次扇出）；单订阅
  // 者回调异常不破全桶（try/catch 留痕 hilog 后继续——诊断信息不带正文）
  private dispatch(type: ChatLiveEventType, conversationId: string, origin: ChatLiveOrigin,
    text: string, reasoning: string, status: string): void {
    const convBucket: Set<ChatLiveSubscriber> | undefined = this.topics.get(conversationId);
    const globalBucket: Set<ChatLiveSubscriber> | undefined = this.topics.get(null);
    const convCount: number = convBucket !== undefined ? convBucket.size : 0;
    const globalCount: number = globalBucket !== undefined ? globalBucket.size : 0;
    if (convCount + globalCount === 0) {
      return;
    }
    this.seq++;
    const event: ChatLiveEvent = {
      v: LIVE_ENVELOPE_VERSION,
      seq: this.seq,
      type: type,
      conversationId: conversationId,
      origin: origin,
      payload: { text: text, reasoning: reasoning, status: status }
    };
    const targets: ChatLiveSubscriber[] = [];
    if (convBucket !== undefined) {
      convBucket.forEach((s: ChatLiveSubscriber): void => {
        targets.push(s);
      });
    }
    if (globalBucket !== undefined) {
      globalBucket.forEach((s: ChatLiveSubscriber): void => {
        targets.push(s);
      });
    }
    for (const subscriber of targets) {
      try {
        subscriber.onEvent(event);
      } catch (e) {
        hilog.warn(0xD5A0, 'ChatLiveHub', '订阅者回调异常，跳过该订阅者（%{public}s）',
          (e as Error).message);
      }
    }
  }
}

// 进程级单例（web 直播镜像器与无头宿主经此同一实例订阅/发布）
export const chatLiveHub: ChatLiveHub = new ChatLiveHub();

// ★ 会话失效信号发布登记（ChatLiveSink 叶子承接——收尾域不 import 本件，防反向依赖）：
// 终态落库后由 ChatStreamFlowCtrl 调 publishChatLiveInvalidate → 此实现发布 conv_invalidate。
// origin 落库时轮已收尾复位 = local（列表信号不驱动前端回环，真发起端以 round_end 信封为准）。
registerChatLivePublish((conversationId: string): void => {
  chatLiveHub.publishConvInvalidate(conversationId, chatLiveHub.originOf(conversationId));
});

// ★ 建族告知登记（运行态 acquire 新账目 → 本件按关切补 wire；web 先开会话、手机后建族的
// 时序断链修复）。回调只做 Map 查询 + 幂等挂线；中枢与运行态均进程级单例同寿命，无注销需求
//（替换/测试口在 ChatSessionRuntime 侧）。注册失败（槽满）不静默留 error——直播面降级，
// 读/写面照常
if (!chatSessionRuntime.attachAcquireWatcher((state: ChatRuntimeState): void => {
  chatLiveHub.onRuntimeAcquired(state);
})) {
  hilog.error(0xD5A0, 'ChatLiveHub',
    '建族告知注册失败（观察者槽满），手机后建族会话的直播镜像将依赖消费侧重试');
}
