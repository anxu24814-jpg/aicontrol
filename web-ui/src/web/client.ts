// 传输客户端与状态机（★ 2026-10-22 Web 服务与 WebUI 施工总案 U7 新建；★ 2026-10-22 SSE
// 备胎笔把传输从原生 WebSocket 换成 SseTransport——信封层、状态机、直播归并全部零改，
// 换的只是 transport.ts 里那层字节通道）。
// 职责一句话：**浏览器与手机 Web 服务之间的唯一通道**——服务可达性探测、首消息口令鉴权、
// 五态状态机（connecting/authing/ready/paused/reconnecting）、读写请求配对、直播帧归并、
// 断线指数退避重连。React 只经 useWebClient 读快照，不直接碰传输层。
// 鉴权语义（亲读 WebAuthValidator.ets + WsGateway.ets）：
// · 首消息 {type:'auth',code} 是唯一配对路径；仅本机档（loopbackOnly）按来源免口令，
//   但客户端仍须在 5s 内发首消息（服务端鉴权窗），所以本端永远先发 auth 信封。
// · 服务端鉴权成功**不回执**——成功 = 连接保持 + 后续业务消息有响应；失败 = 先发
//   auth_failed/auth_required 再 close。本端以首个 api_result 或首个 live 帧作为 ready 证据。
// · 口令空 + 局域网档 = 服务端拒绝全部（fail-closed ③），本端按口令错误展示。
// 直播语义（亲读 WebLivePump.ets）：
// · round_delta 的 payload.text 是**当前轮全文**——前端整段替换，不做 diff、不再节流
//   （服务端已 150ms 合帧）；round_end 带四态 status；snapshot 是连接级与首开会话级两种。
// · conv_invalidate 是列表级失效信号，全部客户端都收；本端刷新列表并重读当前会话。
// 安全：口令只进 sessionStorage（标签页级，关页即清），不进 localStorage。
// 寿命：传输层/定时器全部在 close/重连/停止处成对清理；请求表有超时与拒绝闭环。
import {
  API_ACTIVE_RUNS,
  API_LIST_CONVERSATIONS,
  API_READ_MESSAGES,
  API_RESULT_TYPE,
  API_TYPE,
  AUTH_FAILED_TYPE,
  AUTH_REQUIRED_TYPE,
  AUTH_TYPE,
  CFG_PATH,
  CLOSE_NOTICE_TYPE,
  LIVE_CONV_INVALIDATE,
  LIVE_ROUND_BEGIN,
  LIVE_ROUND_DELTA,
  LIVE_ROUND_END,
  LIVE_SNAPSHOT,
  LIVE_TYPE,
  LIST_LIMIT,
  MESSAGE_LIMIT,
  PING_TYPE,
  PONG_TYPE,
  SEND_RESULT_TYPE,
  SEND_TYPE,
  SERVER_PAUSED_TYPE,
  STOP_TYPE,
  apiErrorText,
} from './protocol';
import type {
  LiveFrame,
  LivePayload,
  WebActiveRunsData,
  WebApiResult,
  WebHistoryData,
  WebListData,
  WebMessageDto,
  WebSendResult,
} from './protocol';
import {
  ApiError,
  INITIAL_STATE,
  dedupeMessages,
  errorText,
  readStoredCode,
  reconcileHistory,
  storeCode,
} from './state';
import type { ClientState, LiveRound, PendingCall, RefreshMode } from './state';
import { SseTransport } from './transport';
import type { Transport } from './transport';

// 状态类型对组件保持从 client 导入的既有路径（内部实现已拆到 state.ts）
export type { ClientPhase, ClientState, LiveRound } from './state';

// 鉴权看门狗（服务端 5s 断连；本端略长一点做兜底）
const AUTH_WATCHDOG_MS = 6000;
// 读写请求超时
const REQUEST_TIMEOUT_MS = 15000;
// round_end 后回读落库态的延迟（等 finishStream 收口提交）
const SETTLED_REFRESH_DELAY_MS = 500;
// 列表失效刷新去抖
const LIST_REFRESH_DEBOUNCE_MS = 300;
// server_paused 后的探测间隔（不重连风暴；手机回前台后自愈）
const PAUSED_PROBE_MS = 15000;
// 断线退避上限（总案 §1.4 客户端 1s/2s/4s…上限 15s）
const RECONNECT_MAX_MS = 15000;

export class WebClient {
  private state: ClientState = { ...INITIAL_STATE };
  private listeners: Set<() => void> = new Set<() => void>();
  private transport: Transport | null = null;
  private code: string = readStoredCode();
  private connecting: boolean = false;
  private suppressReconnect: boolean = false;

  private reconnectAttempt: number = 0;
  private reconnectTimer: number = 0;
  private pausedProbeTimer: number = 0;
  private authWatchdog: number = 0;
  // 握手看门狗（EventSource 半开时 onopen 迟迟不来——★ SSE 备胎笔新增）
  private handshakeTimer: number = 0;
  private listRefreshTimer: number = 0;
  private settledTimer: number = 0;

  private pendingApi: Map<string, PendingCall<WebApiResult>> = new Map();
  private pendingSend: Map<string, PendingCall<WebSendResult>> = new Map();
  private reqSeq: number = 0;

  // 会话代次：切会话/关会话时推进，迟到响应按代次丢弃
  private convGen: number = 0;
  private listGen: number = 0;
  // 当前连接上已向服务端登记（read_messages 首开）的会话 id；新连接重置
  private channelRegistered: string = '';

  constructor() {
    this.state = { ...INITIAL_STATE, hasCode: this.code !== '' };
  }

  // ── React 订阅面（useSyncExternalStore）──
  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return (): void => {
      this.listeners.delete(listener);
    };
  };

  getSnapshot = (): ClientState => this.state;

  private set(patch: Partial<ClientState>): void {
    this.state = { ...this.state, ...patch };
    this.listeners.forEach((listener: () => void): void => listener());
  }

  // ── 用户入口 ──

  // 页面装载时调用：有已存口令才自动连接（无口令 = 停在口令页）
  start(): void {
    if (this.code === '' || this.transport !== null || this.connecting) {
      return;
    }
    this.connect();
  }

  // 口令提交（口令页）：写入 sessionStorage 后立即发起连接
  submitCode(code: string): void {
    const next = code.trim();
    if (next === '') {
      return;
    }
    this.code = next;
    storeCode(next);
    this.clearReconnectTimer();
    this.clearPausedProbe();
    this.closeSocketSilently();
    this.reconnectAttempt = 0;
    this.set({
      hasCode: true,
      phase: 'connecting',
      authError: '',
      connectionError: '',
      reconnectInSec: 0,
      serverPaused: false,
    });
    this.connect();
  }

  // 手动重试（暂停/重连横幅按钮）
  retryNow(): void {
    if (this.code === '') {
      this.set({ phase: 'disconnected', hasCode: false });
      return;
    }
    this.clearReconnectTimer();
    this.clearPausedProbe();
    this.closeSocketSilently();
    this.reconnectAttempt = 0;
    this.set({ phase: 'connecting', connectionError: '', reconnectInSec: 0 });
    this.connect();
  }

  // 打开会话（路由 /c/:id 驱动）：首开登记 + 载入尾部窗口
  openConversation(conversationId: string): void {
    if (this.state.conversationId === conversationId) {
      this.ensureConversationChannel();
      return;
    }
    this.convGen++;
    this.channelRegistered = '';
    this.set({
      conversationId,
      messages: [],
      nextCursor: '',
      messagesLoading: true,
      loadingEarlier: false,
      messagesError: '',
      historyOk: true,
      live: null,
      pendingUsers: [],
    });
    this.ensureConversationChannel();
  }

  closeConversation(): void {
    if (this.state.conversationId === '') {
      return;
    }
    this.convGen++;
    this.channelRegistered = '';
    this.set({
      conversationId: '',
      messages: [],
      nextCursor: '',
      messagesLoading: false,
      loadingEarlier: false,
      messagesError: '',
      historyOk: true,
      live: null,
      pendingUsers: [],
    });
  }

  // 会话内「加载更早」：cursor = 上一页 nextCursor（readPathPage 翻页语义）
  loadEarlier(): void {
    const cid = this.state.conversationId;
    const cursor = this.state.nextCursor;
    if (cid === '' || cursor === '' || this.state.loadingEarlier || this.state.messagesLoading) {
      return;
    }
    void this.loadMessages(cid, cursor, 'earlier');
  }

  retryCurrentConversation(): void {
    const cid = this.state.conversationId;
    if (cid === '') {
      return;
    }
    this.channelRegistered = '';
    this.set({ messagesError: '', messagesLoading: true });
    this.ensureConversationChannel();
  }

  refreshConversations(): void {
    void this.refreshList();
  }

  // 发消息：乐观插入用户消息，send_result 失败则回滚并抛错（Composer 负责还原输入）
  async sendMessage(text: string): Promise<void> {
    const body = text.trim();
    if (body === '') {
      return;
    }
    const cid = this.state.conversationId;
    if (cid === '') {
      throw new Error('未打开会话');
    }
    if (this.state.phase !== 'ready') {
      throw new Error('尚未连接手机');
    }
    const reqId = `send-${++this.reqSeq}`;
    const local: WebMessageDto = {
      id: `local-${reqId}`,
      role: 'user',
      text: body,
      createdAt: Date.now(),
      truncated: false,
    };
    this.set({ pendingUsers: [...this.state.pendingUsers, local] });
    const envelope = {
      type: SEND_TYPE,
      conversationId: cid,
      text: body,
      reqId,
    };
    try {
      const result = await this.callSend(envelope, reqId);
      if (!result.ok) {
        this.removePendingUser(local.id);
        const code = result.error?.code || 'send_failed';
        throw new Error(apiErrorText(code, result.error?.message || '发送失败'));
      }
    } catch (error) {
      this.removePendingUser(local.id);
      throw error;
    }
  }

  // 停止生成（stop 信封无回执；停止是幂等控制动作）
  stopGeneration(): void {
    const cid = this.state.conversationId;
    if (cid === '') {
      return;
    }
    this.sendRaw({ type: STOP_TYPE, conversationId: cid });
  }

  // ── 连接生命周期 ──

  private connect(): void {
    if (this.transport !== null || this.connecting) {
      return;
    }
    this.connecting = true;
    this.set({ phase: this.state.phase === 'paused' ? 'reconnecting' : 'connecting' });
    this.probeService()
      .then((): void => {
        this.connecting = false;
        if (this.code === '') {
          this.set({ phase: 'disconnected', hasCode: false });
          return;
        }
        this.openTransport();
      })
      .catch((error: unknown): void => {
        this.connecting = false;
        this.scheduleReconnect(errorText(error, '无法连接手机服务'));
      });
  }

  // 服务可达性探测：GET /__cfg（同一 HTTP 面）。★ SSE 备胎笔：SSE 流与静态面同源同端口，
  // 不再需要端口发现——这一步只剩「手机服务在不在」与给出可读错误。transport 字段是版本
  // 探针（服务端回报非 sse = 手机端版本不匹配，直说好过用错传输层静默连不上）
  private async probeService(): Promise<void> {
    const controller = new AbortController();
    const timer = window.setTimeout((): void => controller.abort(), 8000);
    let response: Response;
    try {
      response = await fetch(CFG_PATH, { cache: 'no-store', signal: controller.signal });
    } catch (error) {
      if (controller.signal.aborted) {
        throw new Error('连接手机服务超时');
      }
      throw error;
    } finally {
      window.clearTimeout(timer);
    }
    if (!response.ok) {
      throw new Error('未找到手机服务，请确认手机端已开启 Web 服务');
    }
    const cfg = (await response.json()) as { transport?: unknown };
    const kind = typeof cfg.transport === 'string' ? cfg.transport : '';
    if (kind !== '' && kind !== 'sse') {
      throw new Error('手机服务版本不匹配，请更新手机端应用');
    }
  }

  // 建立传输层（SSE：下行 EventSource + 上行 POST；握手看门狗防半开）
  private openTransport(): void {
    this.channelRegistered = '';
    this.clearAuthWatchdog();
    this.clearHandshakeTimer();
    let transport: Transport | null = null;
    try {
      transport = new SseTransport({
        onOpen: (): void => {
          if (this.transport !== transport) {
            return;
          }
          this.handleTransportOpen(transport);
        },
        onMessage: (text: string): void => {
          if (this.transport !== transport) {
            return;
          }
          this.onSocketMessage(text);
        },
        onClose: (): void => {
          if (this.transport !== transport) {
            return;
          }
          this.transport = null;
          this.clearHandshakeTimer();
          this.onSocketClosed();
        },
      });
    } catch {
      this.scheduleReconnect('无法建立连接');
      return;
    }
    this.transport = transport;
    // 握手看门狗：EventSource 卡在半开时 onopen 迟迟不来，超时主动放弃走退避
    this.handshakeTimer = window.setTimeout((): void => {
      this.handshakeTimer = 0;
      if (this.transport !== transport) {
        return;
      }
      this.transport = null;
      if (transport !== null) {
        transport.close();
      }
      this.scheduleReconnect('连接超时，正在重连');
    }, 8000);
  }

  // 流已建立：首消息鉴权 + 鉴权看门狗 + 业务探针（鉴权成功无回执，探针的响应即 ready 证据）
  private handleTransportOpen(transport: Transport | null): void {
    this.clearHandshakeTimer();
    this.set({ phase: 'authing', connectionError: '', reconnectInSec: 0 });
    this.authWatchdog = window.setTimeout((): void => {
      if (this.transport !== transport || this.state.phase !== 'authing') {
        return;
      }
      this.transport = null;
      if (transport !== null) {
        transport.close();
      }
      this.rejectAllPending('鉴权超时');
      this.scheduleReconnect('鉴权超时，正在重连');
    }, AUTH_WATCHDOG_MS);
    void this.authThenProbe(transport);
  }

  // 鉴权首消息 → 等服务端收下 → 再发探针。**顺序是硬约束**：上行是两条独立 POST，到达顺序
  // 不保证；探针若先到，服务端会把它当首消息判鉴权失败并断流（症状 = 偶发登录失败）
  private async authThenProbe(transport: Transport | null): Promise<void> {
    const envelope = JSON.stringify({ type: AUTH_TYPE, code: this.code });
    const delivered = transport === null ? false : await transport.sendAndConfirm(envelope);
    if (this.transport !== transport || this.state.phase !== 'authing') {
      return;
    }
    if (!delivered) {
      this.transport = null;
      if (transport !== null) {
        transport.close();
      }
      this.rejectAllPending('鉴权超时');
      this.scheduleReconnect('无法连接手机服务');
      return;
    }
    void this.authProbe(transport);
  }

  private async authProbe(transport: Transport | null): Promise<void> {
    try {
      const data = await this.callApi<WebActiveRunsData>(API_ACTIVE_RUNS, {});
      if (this.transport !== transport) {
        return;
      }
      this.set({ activeRuns: Array.isArray(data.runs) ? data.runs : [] });
      this.markReady();
    } catch (error) {
      if (this.transport !== transport) {
        return;
      }
      if (error instanceof ApiError) {
        // 有结构化响应 = 已过鉴权（业务错误不影响 ready）
        this.markReady();
        return;
      }
      this.transport = null;
      if (transport !== null) {
        transport.close();
      }
      this.rejectAllPending('鉴权超时');
      this.scheduleReconnect(errorText(error, '鉴权超时，正在重连'));
    }
  }

  private markReady(): void {
    this.clearAuthWatchdog();
    const already = this.state.phase === 'ready';
    this.reconnectAttempt = 0;
    this.set({
      phase: 'ready',
      authError: '',
      connectionError: '',
      serverPaused: false,
      reconnectAttempt: 0,
      reconnectInSec: 0,
    });
    if (already) {
      return;
    }
    // 每次（重）连成功：刷列表 + 重新登记当前会话（新 connId 需要重新 read_messages 触发 snapshot）
    void this.refreshList();
    this.ensureConversationChannel();
  }

  private onSocketClosed(): void {
    this.clearAuthWatchdog();
    this.clearHandshakeTimer();
    this.rejectAllPending('连接已断开');
    if (this.suppressReconnect) {
      this.suppressReconnect = false;
      return;
    }
    if (this.state.phase === 'paused' || this.state.serverPaused) {
      this.set({ phase: 'paused' });
      this.schedulePausedProbe();
      return;
    }
    if (this.state.phase === 'disconnected') {
      return;
    }
    this.scheduleReconnect('连接已断开，正在重连');
  }

  private scheduleReconnect(reason: string): void {
    if (this.suppressReconnect) {
      return;
    }
    // 暂停档：不跑指数退避，按 15s 慢探测（手机回前台后自愈，避免重连风暴）
    if (this.state.serverPaused) {
      this.set({ phase: 'paused', connectionError: reason, reconnectInSec: PAUSED_PROBE_MS / 1000 });
      this.schedulePausedProbe();
      return;
    }
    this.clearReconnectTimer();
    const delay = Math.min(RECONNECT_MAX_MS, 1000 * Math.pow(2, this.reconnectAttempt));
    this.reconnectAttempt++;
    this.set({
      phase: 'reconnecting',
      connectionError: reason,
      reconnectAttempt: this.reconnectAttempt,
      reconnectInSec: Math.max(1, Math.round(delay / 1000)),
    });
    this.reconnectTimer = window.setTimeout((): void => {
      this.reconnectTimer = 0;
      this.connect();
    }, delay);
  }

  private schedulePausedProbe(): void {
    this.clearPausedProbe();
    this.pausedProbeTimer = window.setTimeout((): void => {
      this.pausedProbeTimer = 0;
      if (this.state.phase === 'paused') {
        this.connect();
      }
    }, PAUSED_PROBE_MS);
  }

  private handleServerPaused(): void {
    this.clearReconnectTimer();
    this.set({ phase: 'paused', serverPaused: true, connectionError: '', reconnectInSec: 0 });
    this.schedulePausedProbe();
    // 服务端随后会主动 close；不在这里关，避免抢在 server_paused 帧之后造成多余重连
  }

  private failAuth(message: string, clearCode: boolean): void {
    this.clearReconnectTimer();
    this.clearPausedProbe();
    this.suppressReconnect = true;
    const transport = this.transport;
    this.transport = null;
    if (transport !== null) {
      transport.close();
    }
    this.clearAuthWatchdog();
    this.clearHandshakeTimer();
    this.rejectAllPending('鉴权未通过');
    if (clearCode) {
      this.code = '';
      storeCode('');
    }
    this.set({
      phase: 'disconnected',
      hasCode: this.code !== '',
      authError: message,
      connectionError: '',
      reconnectInSec: 0,
    });
    // onClose 已因传输层置空而早退；suppressReconnect 复位交给下一次连接入口
    this.suppressReconnect = false;
  }

  // ── 消息分派 ──

  private onSocketMessage(text: string): void {
    let raw: unknown;
    try {
      raw = JSON.parse(text);
    } catch {
      return;
    }
    if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
      return;
    }
    const type = (raw as { type?: unknown }).type;
    if (typeof type !== 'string') {
      return;
    }
    if (type === PING_TYPE) {
      // 服务端 30s 应用层心跳；两拍无 pong 即断（WsGateway 心跳策略）
      this.sendRaw({ type: PONG_TYPE });
      return;
    }
    if (type === AUTH_FAILED_TYPE) {
      this.failAuth('口令不正确，请重新输入。', true);
      return;
    }
    if (type === AUTH_REQUIRED_TYPE) {
      this.failAuth('口令验证未通过，请重新输入。', true);
      return;
    }
    if (type === SERVER_PAUSED_TYPE) {
      this.handleServerPaused();
      return;
    }
    if (type === CLOSE_NOTICE_TYPE) {
      // 诊断信封：真实断连由 close 事件驱动
      return;
    }
    if (type === API_RESULT_TYPE) {
      this.handleApiResult(raw as WebApiResult);
      return;
    }
    if (type === SEND_RESULT_TYPE) {
      this.handleSendResult(raw as WebSendResult);
      return;
    }
    if (type === LIVE_TYPE) {
      this.handleLive(raw as LiveFrame);
    }
  }

  private handleApiResult(result: WebApiResult): void {
    // 任何结构化读响应都证明连接已过鉴权（服务端鉴权成功无回执）
    if (this.state.phase === 'authing' || this.state.phase === 'connecting') {
      this.markReady();
    }
    const reqId = typeof result.reqId === 'string' ? result.reqId : '';
    const pending = this.pendingApi.get(reqId);
    if (pending === undefined) {
      return;
    }
    this.pendingApi.delete(reqId);
    window.clearTimeout(pending.timer);
    pending.resolve(result);
  }

  private handleSendResult(result: WebSendResult): void {
    const reqId = typeof result.reqId === 'string' ? result.reqId : '';
    const pending = this.pendingSend.get(reqId);
    if (pending === undefined) {
      return;
    }
    this.pendingSend.delete(reqId);
    window.clearTimeout(pending.timer);
    pending.resolve(result);
  }

  private handleLive(frame: LiveFrame): void {
    const payload: LivePayload = frame.payload || ({} as LivePayload);
    const cid = typeof frame.conversationId === 'string' ? frame.conversationId : '';
    // 连接级 snapshot（conversationId = ''）：activeRuns 引导 + 鉴权成功证据
    if (cid === '') {
      if (this.state.phase === 'authing' || this.state.phase === 'connecting') {
        this.markReady();
      }
      this.set({ activeRuns: Array.isArray(payload.activeRuns) ? payload.activeRuns : [] });
      return;
    }
    // 列表级失效：无论当前打开哪场都刷新列表（WebLivePump 对全部客户端投递）
    if (frame.liveType === LIVE_CONV_INVALIDATE) {
      this.scheduleListRefresh();
      if (cid === this.state.conversationId) {
        this.scheduleSettledRefresh();
      }
      return;
    }
    if (cid !== this.state.conversationId) {
      return;
    }
    if (frame.liveType === LIVE_SNAPSHOT) {
      const raw = Array.isArray(payload.messages) ? payload.messages : [];
      let live: LiveRound | null = null;
      if (payload.roundActive || payload.text !== '' || payload.reasoning !== '') {
        live = {
          text: typeof payload.text === 'string' ? payload.text : '',
          reasoning: typeof payload.reasoning === 'string' ? payload.reasoning : '',
          active: payload.roundActive === true,
          status: typeof payload.status === 'string' ? payload.status : '',
          origin: typeof frame.origin === 'string' ? frame.origin : 'local',
          updatedAt: Date.now(),
        };
      } else if (this.state.live !== null && !this.state.live.active) {
        // 快照未带在途轮信息时保留已收尾的本地终答气泡；落库态含全文时由
        // reconcileHistory 自动清掉（防落库滞后导致终答闪失）
        live = this.state.live;
      }
      const reconciled = reconcileHistory(raw, live);
      this.set({
        messages: reconciled.messages,
        live: reconciled.live,
        nextCursor: typeof payload.nextCursor === 'string' ? payload.nextCursor : this.state.nextCursor,
        messagesLoading: false,
        messagesError: '',
        historyOk: payload.historyOk !== false,
      });
      return;
    }
    if (frame.liveType === LIVE_ROUND_BEGIN) {
      this.set({
        live: {
          text: '',
          reasoning: '',
          active: true,
          status: '',
          origin: typeof frame.origin === 'string' ? frame.origin : 'local',
          updatedAt: Date.now(),
        },
        messagesLoading: false,
      });
      return;
    }
    if (frame.liveType === LIVE_ROUND_DELTA) {
      // 全文整段替换：直接 set，不做 diff、不做前端节流（服务端已 150ms 合帧）
      this.set({
        live: {
          text: typeof payload.text === 'string' ? payload.text : '',
          reasoning: typeof payload.reasoning === 'string' ? payload.reasoning : '',
          active: true,
          status: '',
          origin: typeof frame.origin === 'string'
            ? frame.origin
            : (this.state.live?.origin || 'local'),
          updatedAt: Date.now(),
        },
        messagesLoading: false,
      });
      return;
    }
    if (frame.liveType === LIVE_ROUND_END) {
      this.set({
        live: {
          text: typeof payload.text === 'string' ? payload.text : '',
          reasoning: typeof payload.reasoning === 'string' ? payload.reasoning : '',
          active: false,
          status: typeof payload.status === 'string' ? payload.status : 'done',
          origin: typeof frame.origin === 'string' ? frame.origin : 'local',
          updatedAt: Date.now(),
        },
      });
      // 终态后回读落库态（conv_invalidate 接线在 U8，本端不依赖它）
      this.scheduleSettledRefresh();
      this.scheduleListRefresh();
    }
  }

  // ── 读 API ──

  private ensureConversationChannel(): void {
    const cid = this.state.conversationId;
    if (cid === '' || this.state.phase !== 'ready') {
      return;
    }
    if (this.channelRegistered === cid) {
      return;
    }
    this.channelRegistered = cid;
    void this.loadMessages(cid, '', 'initial');
  }

  private async refreshList(): Promise<void> {
    if (this.state.phase !== 'ready') {
      return;
    }
    const gen = ++this.listGen;
    this.set({ conversationsLoading: true });
    try {
      const data = await this.callApi<WebListData>(API_LIST_CONVERSATIONS, { limit: LIST_LIMIT });
      if (gen !== this.listGen) {
        return;
      }
      const conversations = Array.isArray(data.conversations) ? data.conversations : [];
      this.set({
        conversations,
        conversationsError: '',
        conversationsLoading: false,
      });
    } catch (error) {
      if (gen !== this.listGen) {
        return;
      }
      this.set({
        conversationsError: errorText(error, '会话列表读取失败'),
        conversationsLoading: false,
      });
    }
  }

  private async loadMessages(conversationId: string, cursor: string, mode: RefreshMode): Promise<void> {
    const gen = this.convGen;
    if (mode === 'earlier') {
      this.set({ loadingEarlier: true });
    } else if (mode === 'initial') {
      this.set({ messagesLoading: true, messagesError: '' });
    }
    try {
      const data = await this.callApi<WebHistoryData>(API_READ_MESSAGES, {
        conversationId,
        cursor,
        limit: MESSAGE_LIMIT,
      });
      if (gen !== this.convGen || this.state.conversationId !== conversationId) {
        return;
      }
      const raw = Array.isArray(data.messages) ? data.messages : [];
      const nextCursor = typeof data.nextCursor === 'string' ? data.nextCursor : '';
      if (mode === 'earlier') {
        this.set({
          messages: dedupeMessages([...raw, ...this.state.messages]),
          nextCursor,
          loadingEarlier: false,
          messagesError: '',
        });
        return;
      }
      const reconciled = reconcileHistory(raw, this.state.live);
      // 终态回读：只摘掉已在落库态出现的乐观用户消息；落库滞后时保留，避免消息闪失
      const pendingUsers = mode === 'refresh'
        ? this.state.pendingUsers.filter((pending: WebMessageDto): boolean =>
          !raw.some((m: WebMessageDto): boolean => m.role === 'user' && m.text === pending.text))
        : this.state.pendingUsers;
      this.set({
        messages: reconciled.messages,
        live: reconciled.live,
        nextCursor,
        messagesLoading: false,
        loadingEarlier: false,
        messagesError: '',
        historyOk: true,
        pendingUsers,
      });
    } catch (error) {
      if (gen !== this.convGen || this.state.conversationId !== conversationId) {
        return;
      }
      this.set({
        messagesError: errorText(error, '消息读取失败'),
        messagesLoading: false,
        loadingEarlier: false,
      });
      if (mode === 'initial' && this.channelRegistered === conversationId) {
        this.channelRegistered = '';
      }
    }
  }

  private scheduleListRefresh(): void {
    if (this.listRefreshTimer !== 0) {
      window.clearTimeout(this.listRefreshTimer);
    }
    this.listRefreshTimer = window.setTimeout((): void => {
      this.listRefreshTimer = 0;
      void this.refreshList();
    }, LIST_REFRESH_DEBOUNCE_MS);
  }

  private scheduleSettledRefresh(): void {
    if (this.settledTimer !== 0) {
      window.clearTimeout(this.settledTimer);
    }
    this.settledTimer = window.setTimeout((): void => {
      this.settledTimer = 0;
      const cid = this.state.conversationId;
      if (cid !== '' && this.state.phase === 'ready') {
        void this.loadMessages(cid, '', 'refresh');
      }
    }, SETTLED_REFRESH_DELAY_MS);
  }

  // ── 请求配对 ──

  private callApi<T>(method: string, params: Record<string, unknown>): Promise<T> {
    const reqId = `api-${++this.reqSeq}`;
    return new Promise<T>((resolve, reject) => {
      const sent = this.sendRaw({ type: API_TYPE, reqId, method, params });
      if (!sent) {
        reject(new Error('尚未连接手机'));
        return;
      }
      const timer = window.setTimeout((): void => {
        this.pendingApi.delete(reqId);
        reject(new Error('请求超时，请检查手机与网络'));
      }, REQUEST_TIMEOUT_MS);
      this.pendingApi.set(reqId, {
        timer,
        reject,
        resolve: (result: WebApiResult): void => {
          if (!result.ok) {
            reject(new ApiError(result.error?.code || 'internal',
              result.error?.message || '请求失败'));
            return;
          }
          resolve(result.data as T);
        },
      });
    });
  }

  private callSend(envelope: Record<string, unknown>, reqId: string): Promise<WebSendResult> {
    return new Promise<WebSendResult>((resolve, reject) => {
      const sent = this.sendRaw(envelope);
      if (!sent) {
        reject(new Error('尚未连接手机'));
        return;
      }
      const timer = window.setTimeout((): void => {
        this.pendingSend.delete(reqId);
        reject(new Error('发送超时，请检查手机与网络'));
      }, REQUEST_TIMEOUT_MS);
      this.pendingSend.set(reqId, { timer, reject, resolve });
    });
  }

  private sendRaw(payload: Record<string, unknown>): boolean {
    const transport = this.transport;
    if (transport === null) {
      return false;
    }
    try {
      return transport.send(JSON.stringify(payload));
    } catch {
      return false;
    }
  }

  private removePendingUser(id: string): void {
    this.set({ pendingUsers: this.state.pendingUsers.filter((m: WebMessageDto): boolean => m.id !== id) });
  }

  private rejectAllPending(message: string): void {
    const apiCalls = Array.from(this.pendingApi.values());
    this.pendingApi.clear();
    for (const pending of apiCalls) {
      window.clearTimeout(pending.timer);
      pending.reject(new Error(message));
    }
    const sendCalls = Array.from(this.pendingSend.values());
    this.pendingSend.clear();
    for (const pending of sendCalls) {
      window.clearTimeout(pending.timer);
      pending.reject(new Error(message));
    }
  }

  private closeSocketSilently(): void {
    const transport = this.transport;
    this.transport = null;
    if (transport !== null) {
      transport.close();
    }
    this.clearAuthWatchdog();
    this.clearHandshakeTimer();
    this.rejectAllPending('连接已切换');
  }

  private clearHandshakeTimer(): void {
    if (this.handshakeTimer !== 0) {
      window.clearTimeout(this.handshakeTimer);
      this.handshakeTimer = 0;
    }
  }

  private clearAuthWatchdog(): void {
    if (this.authWatchdog !== 0) {
      window.clearTimeout(this.authWatchdog);
      this.authWatchdog = 0;
    }
  }

  private clearReconnectTimer(): void {
    if (this.reconnectTimer !== 0) {
      window.clearTimeout(this.reconnectTimer);
      this.reconnectTimer = 0;
    }
  }

  private clearPausedProbe(): void {
    if (this.pausedProbeTimer !== 0) {
      window.clearTimeout(this.pausedProbeTimer);
      this.pausedProbeTimer = 0;
    }
  }
}

// 进程内单例（React 任意层经 useWebClient 读取同一连接）
export const webClient = new WebClient();
