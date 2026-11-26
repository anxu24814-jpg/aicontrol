// 直播镜像器——web 端直播流的唯一下行面。消费直播中枢（ChatLiveHub）的全会话扇出，按客户端
// 已打开会话集窄播、按 150ms 拍频合并增量、连接/重连/新开会话首条推 snapshot、退后台经 pause
// 钩广播 server_paused，全部帧经下行通道下发。
// 为什么存在（架构位）：中枢是纯扇出、零暂存（重连/迟订正解 = snapshot），本件就是 snapshot
// 的组装者与拍频的承担者；同时把「全会话广播」的带宽成本收窄到客户端真正打开的会话（窄播判据
// 在消费侧，中枢零改动）。
// 依赖纪律（零环，坑50）：web 域 → chat 域与读 API 单向——只 import 中枢（订阅接口与事件类
// 型）、会话运行时（activeSessions 只读枚举）、读 API（dispatchWebApi 与 DTO/常量）；禁
// import 载体件（WsGateway/WebServiceManager）与任何 UI 件/页面件——下行通道由 manager 以
// WebLiveDownlink 窄接口注入，SSE 备胎换载体时本件零改。
// 订阅策略：中枢全局桶（null 桶）一条订阅收全部会话事件，收到后按「哪个连接打开了哪场会话」
// 决定转发（窄播矩阵在 forwardEvent）；例外 = conv_invalidate 属列表级失效信号，投全部客户端
//（含未打开该会话的列表页）；round_begin/round_delta/round_end 才走会话窄播。
// wire 补全：客户端打开某会话时调 hub.retainSessionWire——账目在场但无头宿主/页面订阅尚未挂线
// 时补上增量与终态 tap，并持一条租约（成对释放：断连/打开集逐出/停泵三路 release）；账目不在场
//（无人建族）返回 false = 无在途轮可镜像，snapshot 走读 API 的落库态；手机后建族由中枢建族告知
// 补挂。★ 租约即为此补的成对面——只补线不释放会把浏览过的会话各留一条 wire 强持运行态（空闲
// 回收后不可回收）。
// snapshot 泵：连接/重连/每次首开会话各推一条 snapshot——①会话历史 = 经 WebReadApi.
// dispatchWebApi 现读 read_messages（落库态真值，尾部窗口 50 条，读 API 侧 300k 字符预算保
// ≤1MB 量级）；②在途轮当前全文 = 本件缓存「每活跃轮最新一条 round_delta」（整段替换语义天然
// 使最新 delta = 当前全文，round_end 即释放；不碰 dataSource/flowCtrl 私有面）；③snapshot 完
// 成后增量自然衔接（全文替换模型下错过的中间拍无需回放）。重连即全量快照、不用 Last-Event-ID。
// snapshot 在途期间该会话的 round_end/conv_invalidate 暂存到「待补终态」小队列（有界 4 条），
// snapshot 落帧后按序补发；round_delta 不补（snapshot 的缓存字段已含最新全文）。
// 拍频：round_delta 每会话 150ms 合并（窗口内只留最新全文），终态/轮起始/失效事件立即冲刷挂起
// 帧再下发；150ms 常量单源 LIVE_THROTTLE_MS（真机观感可调 100~200 带内）。
// 下行信封：{type:'live', seq, conversationId, origin, liveType, payload}；liveType ∈
// round_begin/round_delta/round_end/conv_invalidate/snapshot；seq 为**连接内**自计数（与中枢
// seq 无关，单调不保证连续——丢帧留空洞是全文模型的自然代价）；连接级 snapshot（会话列表/活跃
// run 引导）conversationId = ''。server_paused 是传输控制信封（{type:'server_paused'}，不进
// live 族、不占 seq），由 manager 的 pause 回调位触发全已鉴权连接广播（WsGateway.broadcast
// 只发已鉴权连接），先于 close 触发、close 容忍发送失败。
// 有界防线（红线「数据有界」）：每连接挂起帧队列 256 条（超限丢 round_delta/round_begin 保
// snapshot 与终态，终态恒不丢——全文整段模型下丢中间帧无损）；客户端集 ≤32；每连接打开会话集
// ≤8（超出逐出最早，浏览翻页只保留近场）；轮缓存 ≤32；待冲刷会话表 ≤32；待补终态 ≤4。断连即
// 删客户端与全部计时器（成对释放）。寿命匹配：进程级单例；只持连接 id 字符串与事件负载（不持
// UI 对象/页面组件）；所有 setTimeout 句柄成对 clearTimeout；start↔stop 与 hub 订阅、manager
// pause 钩同生共死。
// 本件零 SQL、零 DB 直连、零 UI import；断言直跑见 scripts/assert-web-domain.mjs U6 钉。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { chatLiveHub, ChatLiveEvent, ChatLiveOrigin, ChatLiveSubscriber } from '../chat/ChatLiveHub';
import { chatSessionRuntime } from '../chat/ChatSessionRuntime';
import { dispatchWebApi, WebApiEnvelope, WebApiSender, WebHistoryData, WebMessageDto,
  WEB_API_METHOD_READ, WEB_API_REQUEST_TYPE, WEB_MSG_LIMIT_DEFAULT } from './WebReadApi';

const WEB_LOG_DOMAIN: number = 0xD5A0;
const WEB_LOG_TAG: string = 'WebLivePump';

// ── 下行契约常量（单源；断言源内现读，禁抄值）──

// live 族信封 type（与传输控制 ping/pong/auth、读 API api/api_result、写路由 send/stop 错开）
export const WEB_LIVE_ENVELOPE_TYPE: string = 'live';
// 退后台暂停广播（先广播后 close；不带 seq 的传输控制信封）
export const WEB_LIVE_SERVER_PAUSED_TEXT: string = '{"type":"server_paused"}';
// 拍频窗口（150ms，100~200 带内；终态/轮起始立即冲刷不节流）
export const LIVE_THROTTLE_MS: number = 150;
// 每连接挂起帧上限（超限丢中间增量保终态）
export const LIVE_MAX_FRAMES_PER_CLIENT: number = 256;
// 客户端集上限（WsGateway 连接上限 16 的防御冗余——载体簿记先于本件拒新）
export const LIVE_MAX_CLIENTS: number = 32;
// 每连接打开会话集上限（窄播判据的边界；超出逐出最早打开的会话）
export const LIVE_MAX_CONVERSATIONS_PER_CLIENT: number = 8;
// 活跃轮最新 delta 缓存上限（每会话一条；并发轮数上界）
export const LIVE_MAX_ROUND_CACHE: number = 32;
// 待冲刷增量表上限（有订阅者的会话数上界）
export const LIVE_MAX_PENDING_CONVERSATIONS: number = 32;
// snapshot 在途期待补终态上限（round_end/conv_invalidate 各至多一条量级）
export const LIVE_MAX_SNAPSHOT_TERMINALS: number = 4;
// snapshot 读 API 超时（读口挂起时降级发空历史快照，防 snapshotInFlight 永久吞增量）
export const LIVE_SNAPSHOT_TIMEOUT_MS: number = 5000;
// snapshot 请求 reqId（读 API 信封配对键；连接外无意义）
export const LIVE_SNAPSHOT_REQ_ID: string = 'live_snapshot';

// ── 纯值类型（下行信封与快照负载）──

export type WebLiveFrameType = 'round_begin' | 'round_delta' | 'round_end' |
  'conv_invalidate' | 'snapshot';

// 负载（四事件统一外框 + snapshot 附加面；未用字段省略——JSON.stringify 自动略 undefined）。
// round_*：text/reasoning = 当前轮权威全文；status 仅 round_end 有值；roundActive 表示该会话
// 是否有在途轮。snapshot：messages/nextCursor = 读 API 落库态尾部窗口；historyOk = 读口是否
// 成功（false = 降级空历史，客户端可重试 api 读）；activeRuns 仅连接级 snapshot 携带。
export interface WebLivePayload {
  text: string;
  reasoning: string;
  status: string;
  roundActive: boolean;
  messages?: WebMessageDto[];
  nextCursor?: string;
  historyOk?: boolean;
  activeRuns?: string[];
}

export interface WebLiveEnvelope {
  type: string;
  seq: number;
  conversationId: string;
  origin: string;
  liveType: string;
  payload: WebLivePayload;
}

// 连接内帧（已序列化；liveType 供有界队列的丢弃策略判别）
interface WebLiveFrame {
  readonly liveType: string;
  readonly text: string;
}

// 读 API 快照结果（落库态尾部窗口）
export interface WebLiveHistorySnapshot {
  readonly messages: WebMessageDto[];
  readonly nextCursor: string;
}

// 下行通道窄接口（manager 以 WsGateway 适配注入；SSE 备胎换载体时只换适配器）
export interface WebLiveDownlink {
  sendTo(connId: string, text: string): Promise<boolean>;
  broadcast(text: string): Promise<number>;
}

// 计时器注入面（缺省系统实现；断言直跑用假时钟精确控制 150ms 窗口与超时）
export interface WebLiveTimers {
  setTimeout(fn: () => void, ms: number): number;
  clearTimeout(id: number): void;
}

// 快照来源（缺省 = 读 API 现读；断言直跑可注入固定历史）
export interface WebLiveSnapshotSource {
  read(conversationId: string): Promise<WebLiveHistorySnapshot | null>;
}

// 客户端消息提示（轻量预读：只回答「这条消息是否意味着打开了某会话」）
export interface WebLiveClientHint {
  readonly conversationId: string;
}

// ── 纯函数面（零 @kit 依赖，断言剥 import 直跑）──

// 客户端打开会话判据：send 信封（conversationId）或 api 信封 read_messages（params.
// conversationId）才视为打开；list_conversations/active_runs/坏 JSON/非对象根一律 ''。
// 不重复读 API 的严格解析——这里只做旁路判据，真正的信封校验仍归读 API/写路由。
export function parseWebLiveClientHint(text: string): WebLiveClientHint {
  const empty: WebLiveClientHint = { conversationId: '' };
  let raw: Object;
  try {
    raw = JSON.parse(text) as Object;
  } catch (e) {
    return empty;
  }
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
    return empty;
  }
  const rec: Record<string, Object> = raw as Record<string, Object>;
  const typeObj: Object | undefined = rec['type'];
  if (typeof typeObj !== 'string') {
    return empty;
  }
  if (typeObj === 'send') {
    const cid: Object | undefined = rec['conversationId'];
    const hint: WebLiveClientHint = { conversationId: typeof cid === 'string' ? cid : '' };
    return hint;
  }
  if (typeObj === WEB_API_REQUEST_TYPE) {
    const method: Object | undefined = rec['method'];
    const paramsObj: Object | undefined = rec['params'];
    if (method !== WEB_API_METHOD_READ || paramsObj === undefined || paramsObj === null ||
      typeof paramsObj !== 'object' || Array.isArray(paramsObj)) {
      return empty;
    }
    const params: Record<string, Object> = paramsObj as Record<string, Object>;
    const cid: Object | undefined = params['conversationId'];
    const hint: WebLiveClientHint = { conversationId: typeof cid === 'string' ? cid : '' };
    return hint;
  }
  return empty;
}

// 读 API 快照回信解析（api_result 信封 → 历史窗口；坏 JSON/ok=false/坏 data 全 null = 降级）
export function parseWebLiveSnapshotReply(text: string): WebLiveHistorySnapshot | null {
  let raw: Object;
  try {
    raw = JSON.parse(text) as Object;
  } catch (e) {
    return null;
  }
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
    return null;
  }
  const env: WebApiEnvelope = raw as WebApiEnvelope;
  if (!env.ok || env.data === undefined || env.data === null || typeof env.data !== 'object') {
    return null;
  }
  const data: WebHistoryData = env.data as WebHistoryData;
  const msgs: WebMessageDto[] = data.messages;
  if (!Array.isArray(msgs)) {
    return null;
  }
  const messages: WebMessageDto[] = [];
  for (const m of msgs) {
    if (m !== null && typeof m === 'object') {
      messages.push(m);
    }
  }
  const cursor: string = typeof data.nextCursor === 'string' ? data.nextCursor : '';
  const snapshot: WebLiveHistorySnapshot = { messages: messages, nextCursor: cursor };
  return snapshot;
}

// 轮缓存条目（每活跃轮最新一条 delta；round_end 释放）
interface WebLiveRoundCache {
  text: string;
  reasoning: string;
  origin: ChatLiveOrigin;
}

// 待冲刷增量（每会话一条；窗口内新事件覆盖 event 引用，timerId 只挂一次）
interface WebLivePendingDelta {
  event: ChatLiveEvent;
  timerId: number;
}

// 待补终态（snapshot 在途期暂存，落帧后按序补发）
interface WebLiveTerminalFrame {
  readonly liveType: string;
  readonly origin: ChatLiveOrigin;
  readonly payload: WebLivePayload;
}

// 连接内会话状态（首开才 snapshot；snapshot 在途期增量只更新轮缓存、终态入待补队列）
interface WebLiveClientConv {
  snapshotInFlight: boolean;
  snapshotToken: number;
  snapshotTimerId: number;
  pendingTerminals: WebLiveTerminalFrame[];
  // ★ 本连接为该会话持有的 hub wire 租约（true = 待 releaseSessionWire，成对释放面）
  wireLeased: boolean;
}

// 客户端条目（连接内 seq 自计数 + 有界下行队列 + 已打开会话集）
interface WebLiveClient {
  readonly connId: string;
  seq: number;
  queue: WebLiveFrame[];
  draining: boolean;
  dropped: number;
  readonly convs: Map<string, WebLiveClientConv>;
}

// 依赖窄接口（类实现由单例提供；断言直跑以桩对象代入——避免直跑副本拉入中枢/运行时的
// 构造链，同时不让本件 import 具体类导致 static 面耦合）
export interface ChatLiveHubRef {
  subscribe(conversationId: string | null, subscriber: ChatLiveSubscriber): boolean;
  unsubscribe(conversationId: string | null, subscriber: ChatLiveSubscriber): void;
  retainSessionWire(conversationId: string): boolean;
  releaseSessionWire(conversationId: string): void;
}

export interface ChatSessionRuntimeRef {
  activeSessions(): string[];
}

// 系统计时器（缺省实现；注入面见 WebLiveTimers）
class SystemLiveTimers implements WebLiveTimers {
  setTimeout(fn: () => void, ms: number): number {
    return setTimeout(fn, ms);
  }

  clearTimeout(id: number): void {
    clearTimeout(id);
  }
}

// 读 API 快照回信捕获（dispatchWebApi 的 sender 注入面——请求-响应一次配对）
class SnapshotReplySender implements WebApiSender {
  private readonly settle: (snapshot: WebLiveHistorySnapshot | null) => void;
  private done: boolean = false;

  constructor(settle: (snapshot: WebLiveHistorySnapshot | null) => void) {
    this.settle = settle;
  }

  send(_connId: string, text: string): Promise<boolean> {
    if (!this.done) {
      this.done = true;
      this.settle(parseWebLiveSnapshotReply(text));
    }
    return Promise.resolve(true);
  }
}

// 读 API 快照来源（缺省）：本地构造 api 信封 → dispatchWebApi → 捕获 api_result。
// 读口异常/超时由本件上层兜底（LIVE_SNAPSHOT_TIMEOUT_MS 降级发空历史）。
class ReadApiSnapshotSource implements WebLiveSnapshotSource {
  read(conversationId: string): Promise<WebLiveHistorySnapshot | null> {
    return new Promise<WebLiveHistorySnapshot | null>(
      (resolve: (snapshot: WebLiveHistorySnapshot | null) => void): void => {
        const sender: SnapshotReplySender = new SnapshotReplySender(resolve);
        const params: Record<string, Object> = {
          'conversationId': conversationId,
          'limit': WEB_MSG_LIMIT_DEFAULT
        };
        const request: Record<string, Object> = {
          'type': WEB_API_REQUEST_TYPE,
          'reqId': LIVE_SNAPSHOT_REQ_ID,
          'method': WEB_API_METHOD_READ,
          'params': params
        };
        try {
          // connId 对读 API 无意义（捕获型 sender 不区分来源）；空串防误投
          dispatchWebApi('', JSON.stringify(request), sender);
        } catch (e) {
          resolve(null);
        }
      });
  }
}

// ── 镜像器主体 ──

export class WebLivePump implements ChatLiveSubscriber {
  private readonly hub: ChatLiveHubRef;
  private readonly runtime: ChatSessionRuntimeRef;
  private readonly snapshotSource: WebLiveSnapshotSource;
  private readonly timers: WebLiveTimers;
  private downlink: WebLiveDownlink | null = null;
  private running: boolean = false;
  // 客户端表（connId → 条目；上限 LIVE_MAX_CLIENTS）
  private clients: Map<string, WebLiveClient> = new Map<string, WebLiveClient>();
  // 活跃轮最新 delta（conversationId → 条目；round_end 删；上限 LIVE_MAX_ROUND_CACHE）
  private rounds: Map<string, WebLiveRoundCache> = new Map<string, WebLiveRoundCache>();
  // 待冲刷增量（conversationId → 条目；150ms 窗口）
  private pending: Map<string, WebLivePendingDelta> = new Map<string, WebLivePendingDelta>();
  // snapshot 令牌（全局自增；超时/迟到结果身份判别）
  private snapshotTokenSeq: number = 0;

  constructor(hub: ChatLiveHubRef = chatLiveHub,
    runtime: ChatSessionRuntimeRef = chatSessionRuntime,
    snapshotSource: WebLiveSnapshotSource = new ReadApiSnapshotSource(),
    timers: WebLiveTimers = new SystemLiveTimers()) {
    this.hub = hub;
    this.runtime = runtime;
    this.snapshotSource = snapshotSource;
    this.timers = timers;
  }

  // ── 生命周期（start↔stop / subscribe↔unsubscribe 成对）──

  // 起泵：挂全局桶订阅（null 桶 = 全会话广播裁定）+ 记下下行通道；已在跑 = 只换通道。
  // 返回 false = 中枢订阅桶满（调用方须检查并留痕，禁静默半态）
  start(downlink: WebLiveDownlink): boolean {
    this.downlink = downlink;
    if (this.running) {
      this.kickAllDrains();
      return true;
    }
    const ok: boolean = this.hub.subscribe(null, this);
    if (!ok) {
      this.downlink = null;
      hilog.error(WEB_LOG_DOMAIN, WEB_LOG_TAG, '中枢全局桶订阅失败（桶满），直播下行不可用');
      return false;
    }
    this.running = true;
    hilog.info(WEB_LOG_DOMAIN, WEB_LOG_TAG, '直播泵启动（全局桶订阅在场）');
    this.kickAllDrains();
    return true;
  }

  // 停泵：退订 + 清客户端/计时器/缓存（幂等；stop 后 start 可重入）
  stop(): void {
    if (this.running) {
      this.hub.unsubscribe(null, this);
      this.running = false;
    }
    this.downlink = null;
    this.pending.forEach((p: WebLivePendingDelta): void => {
      if (p.timerId !== 0) {
        this.timers.clearTimeout(p.timerId);
        p.timerId = 0;
      }
    });
    this.pending.clear();
    this.rounds.clear();
    this.clients.forEach((client: WebLiveClient): void => {
      this.clearClientTimers(client);
      this.releaseClientWires(client);
      client.queue = [];
      client.convs.clear();
    });
    this.clients.clear();
    hilog.info(WEB_LOG_DOMAIN, WEB_LOG_TAG, '直播泵停止（订阅与帧队列全清）');
  }

  // 连接断开（manager onDisconnect 调用）：删客户端 + 成对清计时器与 wire 租约
  //（队列随条目消亡）
  releaseConn(connId: string): void {
    const client: WebLiveClient | undefined = this.clients.get(connId);
    if (client === undefined) {
      return;
    }
    this.clearClientTimers(client);
    this.releaseClientWires(client);
    client.queue = [];
    client.convs.clear();
    this.clients.delete(connId);
  }

  // 退后台暂停广播（manager pause 钩调用）：先于 close 触发，全已鉴权连接收
  // {type:'server_paused'}；返回 Promise——pause 钩 await 本调用后才关栈（fire-and-forget
  // 在多连接串行 send 下会被 close 抢跑，后发连接收不到暂停帧）；发送失败由载体件断连兜底
  //（close 容忍），本处只留痕不抛
  async broadcastServerPaused(): Promise<void> {
    const downlink: WebLiveDownlink | null = this.downlink;
    if (downlink === null) {
      return;
    }
    try {
      await downlink.broadcast(WEB_LIVE_SERVER_PAUSED_TEXT);
    } catch (e) {
      hilog.warn(WEB_LOG_DOMAIN, WEB_LOG_TAG, 'server_paused 广播失败（%{public}s）',
        (e as Error).message);
    }
  }

  // ── 中枢订阅回调（全局桶；事件按客户端打开集窄播）──

  onEvent(event: ChatLiveEvent): void {
    if (!this.running) {
      return;
    }
    const conversationId: string = event.conversationId;
    if (event.type === 'round_delta') {
      this.cacheRound(event);
      if (this.hasReadyClient(conversationId)) {
        this.scheduleDelta(event);
      }
      return;
    }
    // 非增量事件立即冲刷该会话挂起帧（尾部 flush）再下发
    this.flushPendingDelta(conversationId);
    if (event.type === 'round_begin') {
      this.cacheRound(event);
      this.forwardEvent(conversationId, 'round_begin', event.origin,
        this.payloadOf(event, true));
      return;
    }
    if (event.type === 'round_end') {
      this.forwardEvent(conversationId, 'round_end', event.origin,
        this.payloadOf(event, false));
      // 终态即释放轮缓存（快照只取「在途轮」最新全文）
      this.rounds.delete(conversationId);
      return;
    }
    if (event.type === 'conv_invalidate') {
      this.forwardEvent(conversationId, 'conv_invalidate', event.origin,
        this.payloadOf(event, false));
    }
  }

  // ── 客户端消息旁路（manager 在路由前调用）──

  // 任何已鉴权业务消息 = 连接活着：首次登记即发连接级 snapshot（活跃 run 引导）；
  // 消息若意味着打开某会话（send / read_messages）则补会话 snapshot 与 wire。
  // 旁路自兜底：本方法异常不得上抛吞掉 manager 的业务路由（直播面降级，读写面照常）
  observeClientMessage(connId: string, text: string): void {
    if (!this.running) {
      return;
    }
    try {
      const client: WebLiveClient | null = this.ensureClient(connId);
      if (client === null) {
        return;
      }
      const hint: WebLiveClientHint = parseWebLiveClientHint(text);
      if (hint.conversationId !== '') {
        this.noteConversationOpen(connId, hint.conversationId);
      }
    } catch (e) {
      hilog.warn(WEB_LOG_DOMAIN, WEB_LOG_TAG, '直播旁路异常，跳过本次登记（%{public}s）',
        (e as Error).message);
    }
  }

  // 打开会话（首开才 snapshot；重复 read_messages 翻页不重发）：登记窄播集 → hub 补 wire
  // → 读 API 现读落库态 + 轮缓存组 snapshot。打开集有界 8（超出逐出最早，浏览只保留近场）
  noteConversationOpen(connId: string, conversationId: string): void {
    if (!this.running || conversationId === '') {
      return;
    }
    const client: WebLiveClient | undefined = this.clients.get(connId);
    if (client === undefined) {
      return;
    }
    if (client.convs.has(conversationId)) {
      return;
    }
    this.evictConversationIfNeeded(client);
    const conv: WebLiveClientConv = {
      snapshotInFlight: true,
      snapshotToken: 0,
      snapshotTimerId: 0,
      pendingTerminals: [],
      wireLeased: true
    };
    client.convs.set(conversationId, conv);
    // wire 租约（只补线不订阅的成对持有面）：账目在场则挂增量/终态 tap；不在场 =
    // 无在途轮可镜像（返回 false 无害）——租约照记，手机后建族由中枢建族告知补挂，
    // 断连/逐出/停泵三路 release。异常不得把会话卡在 snapshotInFlight（兜底后照发快照）
    try {
      this.hub.retainSessionWire(conversationId);
    } catch (e) {
      hilog.warn(WEB_LOG_DOMAIN, WEB_LOG_TAG, 'wire 租用异常（%{public}s）',
        (e as Error).message);
    }
    try {
      this.requestSnapshot(client, conversationId, conv);
    } catch (e) {
      // 快照起不来 = 本会话退化为纯增量面（不许永久吞事件）
      conv.snapshotInFlight = false;
      hilog.warn(WEB_LOG_DOMAIN, WEB_LOG_TAG, 'snapshot 请求异常（%{public}s）',
        (e as Error).message);
    }
  }

  // ── 诊断面（有界性自证口；断言消费）──

  clientCount(): number {
    return this.clients.size;
  }

  queueDepth(connId: string): number {
    const client: WebLiveClient | undefined = this.clients.get(connId);
    return client !== undefined ? client.queue.length : 0;
  }

  droppedFrames(connId: string): number {
    const client: WebLiveClient | undefined = this.clients.get(connId);
    return client !== undefined ? client.dropped : 0;
  }

  // ── 客户端登记与连接级 snapshot ──

  private ensureClient(connId: string): WebLiveClient | null {
    const existing: WebLiveClient | undefined = this.clients.get(connId);
    if (existing !== undefined) {
      return existing;
    }
    if (this.clients.size >= LIVE_MAX_CLIENTS) {
      hilog.warn(WEB_LOG_DOMAIN, WEB_LOG_TAG, '客户端上限拒登（%{public}s，全量 %{public}d）',
        connId, this.clients.size);
      return null;
    }
    const client: WebLiveClient = {
      connId: connId,
      seq: 0,
      queue: [],
      draining: false,
      dropped: 0,
      convs: new Map<string, WebLiveClientConv>()
    };
    this.clients.set(connId, client);
    // 连接/重连首条：活跃 run 引导（不携带会话历史——会话历史随首开会话的 snapshot 给）
    const payload: WebLivePayload = {
      text: '',
      reasoning: '',
      status: '',
      roundActive: false,
      messages: [],
      nextCursor: '',
      historyOk: true,
      activeRuns: this.runtime.activeSessions()
    };
    this.enqueue(client, this.buildFrame(client, 'snapshot', '', 'local', payload));
    return client;
  }

  private evictConversationIfNeeded(client: WebLiveClient): void {
    if (client.convs.size < LIVE_MAX_CONVERSATIONS_PER_CLIENT) {
      return;
    }
    let oldestKey: string = '';
    client.convs.forEach((_conv: WebLiveClientConv, key: string): void => {
      if (oldestKey === '') {
        oldestKey = key;
      }
    });
    if (oldestKey === '') {
      return;
    }
    const victim: WebLiveClientConv | undefined = client.convs.get(oldestKey);
    if (victim !== undefined) {
      if (victim.snapshotTimerId !== 0) {
        this.timers.clearTimeout(victim.snapshotTimerId);
        victim.snapshotTimerId = 0;
      }
      // 令牌作废：迟到 snapshot 结果身份不符即丢弃
      victim.snapshotToken = -1;
      // ★ 租约成对释放：逐出的打开会话不再需要 wire（另一持有方在场则中枢保线）
      if (victim.wireLeased) {
        victim.wireLeased = false;
        this.hub.releaseSessionWire(oldestKey);
      }
    }
    client.convs.delete(oldestKey);
  }

  // 客户端打开集全量释放 wire 租约（★ U8；断连与停泵两路共用——convs 清空前调用）
  private releaseClientWires(client: WebLiveClient): void {
    client.convs.forEach((conv: WebLiveClientConv, conversationId: string): void => {
      if (conv.wireLeased) {
        conv.wireLeased = false;
        this.hub.releaseSessionWire(conversationId);
      }
    });
  }

  // ── snapshot 请求与落帧 ──

  private requestSnapshot(client: WebLiveClient, conversationId: string,
    conv: WebLiveClientConv): void {
    this.snapshotTokenSeq++;
    conv.snapshotToken = this.snapshotTokenSeq;
    const token: number = conv.snapshotToken;
    // 超时降级：读口挂起不能永久吞掉该会话增量（发空历史快照，客户端可重试 api 读）
    conv.snapshotTimerId = this.timers.setTimeout((): void => {
      this.finishSnapshot(client, conversationId, conv, token, null);
    }, LIVE_SNAPSHOT_TIMEOUT_MS);
    this.snapshotSource.read(conversationId).then(
      (snapshot: WebLiveHistorySnapshot | null): void => {
        this.finishSnapshot(client, conversationId, conv, token, snapshot);
      }).catch((e: Error): void => {
      hilog.warn(WEB_LOG_DOMAIN, WEB_LOG_TAG, 'snapshot 读口异常（%{public}s）', e.message);
      this.finishSnapshot(client, conversationId, conv, token, null);
    });
  }

  private finishSnapshot(client: WebLiveClient, conversationId: string,
    conv: WebLiveClientConv, token: number, snapshot: WebLiveHistorySnapshot | null): void {
    if (this.clients.get(client.connId) !== client) {
      return;
    }
    if (client.convs.get(conversationId) !== conv || conv.snapshotToken !== token) {
      return;
    }
    if (conv.snapshotTimerId !== 0) {
      this.timers.clearTimeout(conv.snapshotTimerId);
      conv.snapshotTimerId = 0;
    }
    if (!conv.snapshotInFlight) {
      return;
    }
    conv.snapshotInFlight = false;
    const cached: WebLiveRoundCache | undefined = this.rounds.get(conversationId);
    // 轮已在 snapshot 读口返回前收尾（缓存已释放）：以暂存终态的全文补齐快照正文——
    // 读 API 的落库态可能早于终态提交，终态负载是此刻最权威的全文
    let text: string = cached !== undefined ? cached.text : '';
    let reasoning: string = cached !== undefined ? cached.reasoning : '';
    if (text === '') {
      for (const terminal of conv.pendingTerminals) {
        if (terminal.liveType === 'round_end' && terminal.payload.text !== '') {
          text = terminal.payload.text;
          reasoning = terminal.payload.reasoning;
          break;
        }
      }
    }
    const activeRuns: string[] = this.runtime.activeSessions();
    const payload: WebLivePayload = {
      text: text,
      reasoning: reasoning,
      status: '',
      roundActive: activeRuns.includes(conversationId),
      messages: snapshot !== null ? snapshot.messages : [],
      nextCursor: snapshot !== null ? snapshot.nextCursor : '',
      historyOk: snapshot !== null
    };
    // ★ 会话快照 origin 取轮缓存真实发起端（此前恒 'local'，web 自发在途轮经快照校正时首帧
    // 误标「手机发起」；无缓存轮才回落 local）
    this.enqueue(client, this.buildFrame(client, 'snapshot', conversationId,
      cached !== undefined ? cached.origin : 'local', payload));
    // 待补终态（snapshot 在途期错过的 round_end/conv_invalidate）按序补发
    const terminals: WebLiveTerminalFrame[] = conv.pendingTerminals;
    conv.pendingTerminals = [];
    for (const terminal of terminals) {
      this.enqueue(client, this.buildFrame(client, terminal.liveType, conversationId,
        terminal.origin, terminal.payload));
    }
  }

  // ── 增量拍频（150ms 合并 + 终态/轮起始立即冲刷）──

  private cacheRound(event: ChatLiveEvent): void {
    this.rounds.set(event.conversationId, {
      text: event.payload.text,
      reasoning: event.payload.reasoning,
      origin: event.origin
    });
    if (this.rounds.size > LIVE_MAX_ROUND_CACHE) {
      let oldestKey: string = '';
      this.rounds.forEach((_round: WebLiveRoundCache, key: string): void => {
        if (oldestKey === '') {
          oldestKey = key;
        }
      });
      if (oldestKey !== '') {
        this.rounds.delete(oldestKey);
      }
    }
  }

  private scheduleDelta(event: ChatLiveEvent): void {
    const conversationId: string = event.conversationId;
    const pending: WebLivePendingDelta | undefined = this.pending.get(conversationId);
    if (pending !== undefined) {
      // 窗口内新事件覆盖（同轮全文整段替换：只留最新）
      pending.event = event;
      return;
    }
    const entry: WebLivePendingDelta = { event: event, timerId: 0 };
    this.pending.set(conversationId, entry);
    this.trimPending();
    entry.timerId = this.timers.setTimeout((): void => {
      this.flushPendingDelta(conversationId);
    }, LIVE_THROTTLE_MS);
  }

  private trimPending(): void {
    while (this.pending.size > LIVE_MAX_PENDING_CONVERSATIONS) {
      let oldestKey: string = '';
      this.pending.forEach((_p: WebLivePendingDelta, key: string): void => {
        if (oldestKey === '') {
          oldestKey = key;
        }
      });
      const victim: WebLivePendingDelta | undefined = this.pending.get(oldestKey);
      if (victim === undefined) {
        return;
      }
      if (victim.timerId !== 0) {
        this.timers.clearTimeout(victim.timerId);
      }
      this.pending.delete(oldestKey);
    }
  }

  private flushPendingDelta(conversationId: string): void {
    const pending: WebLivePendingDelta | undefined = this.pending.get(conversationId);
    if (pending === undefined) {
      return;
    }
    this.pending.delete(conversationId);
    if (pending.timerId !== 0) {
      this.timers.clearTimeout(pending.timerId);
      pending.timerId = 0;
    }
    const cached: WebLiveRoundCache | undefined = this.rounds.get(conversationId);
    const payload: WebLivePayload = {
      text: cached !== undefined ? cached.text : pending.event.payload.text,
      reasoning: cached !== undefined ? cached.reasoning : pending.event.payload.reasoning,
      status: '',
      roundActive: true
    };
    this.forwardEvent(conversationId, 'round_delta', pending.event.origin, payload);
  }

  // ── 窄播与帧入队 ──

  private hasReadyClient(conversationId: string): boolean {
    let ready: boolean = false;
    this.clients.forEach((client: WebLiveClient): void => {
      if (ready) {
        return;
      }
      const conv: WebLiveClientConv | undefined = client.convs.get(conversationId);
      if (conv !== undefined && !conv.snapshotInFlight) {
        ready = true;
      }
    });
    return ready;
  }

  // 事件转发矩阵：round_* 只投「已打开该会话」的连接（窄播）；conv_invalidate 是**列表级**
  // 失效信号——投全部客户端，未打开该会话的列表页也能刷新。snapshot 在途的连接不投增量
  //（快照缓存已含最新全文），终态/失效暂存待 snapshot 落帧后补（有界 4，超出丢最早）
  private forwardEvent(conversationId: string, liveType: string, origin: ChatLiveOrigin,
    payload: WebLivePayload): void {
    this.clients.forEach((client: WebLiveClient): void => {
      const conv: WebLiveClientConv | undefined = client.convs.get(conversationId);
      if (conv === undefined && liveType !== 'conv_invalidate') {
        return;
      }
      if (conv !== undefined && conv.snapshotInFlight) {
        if (liveType === 'round_end' || liveType === 'conv_invalidate') {
          conv.pendingTerminals.push({
            liveType: liveType,
            origin: origin,
            payload: payload
          });
          if (conv.pendingTerminals.length > LIVE_MAX_SNAPSHOT_TERMINALS) {
            conv.pendingTerminals.shift();
          }
        }
        return;
      }
      this.enqueue(client, this.buildFrame(client, liveType, conversationId, origin, payload));
    });
  }

  private payloadOf(event: ChatLiveEvent, roundActive: boolean): WebLivePayload {
    const payload: WebLivePayload = {
      text: event.payload.text,
      reasoning: event.payload.reasoning,
      status: event.payload.status,
      roundActive: roundActive
    };
    return payload;
  }

  // 帧构造（连接内 seq 自增；与中枢 seq 无关）
  private buildFrame(client: WebLiveClient, liveType: string, conversationId: string,
    origin: ChatLiveOrigin, payload: WebLivePayload): WebLiveFrame {
    client.seq++;
    const envelope: WebLiveEnvelope = {
      type: WEB_LIVE_ENVELOPE_TYPE,
      seq: client.seq,
      conversationId: conversationId,
      origin: origin,
      liveType: liveType,
      payload: payload
    };
    const frame: WebLiveFrame = { liveType: liveType, text: JSON.stringify(envelope) };
    return frame;
  }

  // 有界入队：满 256 时增量优先丢（全文模型无损），snapshot/终态恒保——为终态腾位按
  // round_delta → round_begin → 最旧帧 的优先级逐出
  private enqueue(client: WebLiveClient, frame: WebLiveFrame): void {
    if (client.queue.length >= LIVE_MAX_FRAMES_PER_CLIENT) {
      if (frame.liveType === 'round_delta') {
        client.dropped++;
        return;
      }
      this.makeRoom(client);
    }
    client.queue.push(frame);
    this.drain(client);
  }

  private makeRoom(client: WebLiveClient): void {
    let victim: number = -1;
    for (let i: number = 0; i < client.queue.length; i++) {
      if (client.queue[i].liveType === 'round_delta') {
        victim = i;
        break;
      }
    }
    if (victim < 0) {
      for (let i: number = 0; i < client.queue.length; i++) {
        if (client.queue[i].liveType === 'round_begin') {
          victim = i;
          break;
        }
      }
    }
    if (victim < 0 && client.queue.length > 0) {
      victim = 0;
    }
    if (victim >= 0) {
      client.queue.splice(victim, 1);
      client.dropped++;
    }
  }

  // 单连接串行下发（WsGateway 无背压 API——顺序由本队列保证；发送失败即清队列等断连）
  private drain(client: WebLiveClient): void {
    if (client.draining) {
      return;
    }
    const downlink: WebLiveDownlink | null = this.downlink;
    if (downlink === null) {
      return;
    }
    client.draining = true;
    const step: () => void = (): void => {
      if (this.clients.get(client.connId) !== client) {
        client.draining = false;
        return;
      }
      const frame: WebLiveFrame | undefined = client.queue.shift();
      if (frame === undefined) {
        client.draining = false;
        return;
      }
      downlink.sendTo(client.connId, frame.text).then((ok: boolean): void => {
        if (!ok) {
          // 未鉴权/失联/发送失败：载体件已断连，队列清空等 onDisconnect
          client.queue = [];
          client.draining = false;
          return;
        }
        step();
      }).catch((): void => {
        client.queue = [];
        client.draining = false;
      });
    };
    step();
  }

  private kickAllDrains(): void {
    this.clients.forEach((client: WebLiveClient): void => {
      this.drain(client);
    });
  }

  private clearClientTimers(client: WebLiveClient): void {
    client.convs.forEach((conv: WebLiveClientConv): void => {
      if (conv.snapshotTimerId !== 0) {
        this.timers.clearTimeout(conv.snapshotTimerId);
        conv.snapshotTimerId = 0;
      }
      conv.snapshotToken = -1;
    });
  }
}

// 进程级单例（模块级单例形制——chatLiveHub/webServiceManager 先例；manager 启动/停止与
// pause 钩经此同一实例）
export const webLivePump: WebLivePump = new WebLivePump();
