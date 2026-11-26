// Web 无头宿主——web 会话的离屏取用与发送/停止入口。浏览器发来的 send/stop 信封经本件落到
// 与手机页面同一条发送编排链（ChatSessionRuntime.acquire 的第三个消费者 +
// ChatSendCtrl.send/abort），不抄第二套编排、不建第二套轮锁。
// 为什么走 acquire（而非独立离屏族）：同会话双端拿到同一 state 与同一 sendCtrl——同会话 FIFO
// 由既有 sendGate（生成中入队）与 chatRunScope（进程级同会话互斥）天然承担，跨会话天然并行；
// 引用计数（attached）挡 5 秒空闲回收，web 关闭会话 = releaseHeadless。
// 离屏绑定（ChatRuntimeUiBinding 的离屏实现——ChatHostAccess 是 ChatSendCtrl 构造期由 refs
// 现造的内部闭包集，web 域无法注入，可注入面只有 refs 壳页面面）：
// · dataSource = chatSessionRuntime.newDataSource()（普通对象，收写不挂 UI）；
// · follow = 未 attach 的 ChatFollowController（各入口早退，照 ChatPageLifecycle 解绑态先例）；
//   anchorJudge = 纯值判定器；
// · toast / clearError / restoreSendInput / onRoundSettled / setSending = no-op（无屏，失败
//   回执走 send_result 信封，不占 UI 槽）；isDisposed 服务位不在此面——ChatSendCtrl 内部
//   disposed 字段不可注入，web 关会话只释放引用不静默销毁（在途轮照跑）；
// · conn / webSearchOn = 每次发送前现解析（resolveActiveConnection 四级链 + 会话覆盖联网
//   开关）；thinking = ''（web 不提供思考档选择）；
// · sessionOverride = null（web 只对既有会话发送，覆盖三列已在库）；
// · pendingQuote = ''（web V1 不支持引用）。
// 页面活绑定零覆写：acquire(..., headless=true) 只进 headlessBinding 独立槽——页面先在（双端
// 同屏核心场景）时 refs 页面面与 uiBinding 单槽一字不动；页面退页时运行态回装离屏面，web
// 会话继续可发（两向时序）。
// 会话寿命：按连接登记（session.conns）——同连接重发不重复 acquire；断开（manager
// onDisconnect → releaseConn）或服务停止即 closeSession = 退订中枢 + releaseHeadless。
// 上限（数据有界）：全局 WEB_HEADLESS_MAX_SESSIONS 会话 + 单连接
// WEB_HEADLESS_MAX_SESSIONS_PER_CONN，超限 fail-closed 回错误信封，不静默丢弃。
// 消息信封（与读 API 的 api/api_result 族错开）：
// 请求 send {type:'send', conversationId, text, reqId?} → 回执 {type:'send_result', reqId?,
// ok, error?}（reqId 带则原样透传；ok = 已投递或已入队，与 ChatSendCtrl.send 返回值契约
// 同义）；请求 stop {type:'stop', conversationId} → 走 ChatSendCtrl.abort()（宿主无关停止
// 入口，与手机停止键同一条跨域分发链；回执 V1 不发——停止是幂等控制动作）。
// 历史上下文：请求历史已改从读口独立读取（readRequestHistoryRows），**不依赖页面窗口装载**
// ——web 发送与手机端条数一致（同一读口同一预算）。本件的装载回放（conversationLoadRoute +
// readPathPageRows 尾部一页）只剩两个次要使命：读口失败时的降级快照素材（windowSnapshot =
// allMessages()，未装载则空历史——fail-open 不阻断发送）与直播链轮事实素材；页面已装载
//（historyLoaded）则零动作，页面加载链在途时可能重复回放一次（同源只读，后写者胜——登记为
// 接受的窄窗，维持原行为不动）。
// 依赖纪律（零环，坑50）：web 域 → chat 域单向；chat 域零 import 本域；禁 import UI 组件与
// 页面件（ChatPage/ChatPageLifecycle 族）；不持 UI 组件引用（Scroller 是控制器构造参数，
// 非组件）。成对释放：hub subscribe ↔ unsubscribe、acquire ↔ releaseHeadless、conns 登记
// ↔ 断连清。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AiConnection, PendingAttachment } from '../providers/AiTypes';
import { chatSessionRuntime, ChatRuntimeSeed, ChatRuntimeState,
  ChatRuntimeUiBinding } from '../chat/ChatSessionRuntime';
import { chatLiveHub, ChatLiveEvent, ChatLiveSubscriber } from '../chat/ChatLiveHub';
import { ConversationLoadRoute, conversationLoadRoute, readPathPageRows,
  ROUTE_BLOCKED } from '../chat/ChatContextSource';
import { ChatListAnchorJudge } from '../chat/ChatListAnchorJudge';
import { ChatDataSource } from '../../components/chat/ChatDataSource';
import { ChatFollowController } from '../../components/chat/ChatFollowController';
import { ChatSendCtrl, ChatSendRefs } from '../../components/chat/ChatSendCtrl';
import { ConversationOverride, MessageRow, QUERY_TAIL_LIMIT, queryConversationOverride,
  whenReady } from '../store/ChatDb';
import { ChatReadConvRow, queryConversationRowByIdForRead } from '../store/ChatDbReadSearch';
import { ASSISTANT_DEFAULT_ID, queryConversationAssistantId } from '../store/AssistantDb';
import { ActiveConnectionInfo, resolveActiveConnection } from '../store/ProviderDb';
import { WebApiSender } from './WebReadApi';

const WEB_LOG_DOMAIN: number = 0xD5A0;
const WEB_LOG_TAG: string = 'WebHeadlessHost';

// ── 消息信封（type 值与 WsGateway 传输控制族 ping/pong/auth、中枢 round_* 族、
//    读 API api/api_result 族错开——四方互不抢占）──
export const WEB_SEND_REQUEST_TYPE: string = 'send';
export const WEB_STOP_REQUEST_TYPE: string = 'stop';
export const WEB_SEND_RESULT_TYPE: string = 'send_result';

// 会话上限（数据有界：全局对齐中枢订阅桶 16；单连接对齐 WS_MAX_CONNECTIONS_PER_CLIENT 4
// ——一台设备的多标签页各一条连接，单标签页多会话不属 V1 玩法）
export const WEB_HEADLESS_MAX_SESSIONS: number = 16;
export const WEB_HEADLESS_MAX_SESSIONS_PER_CONN: number = 4;

// 发送错误码（客户端可编程判别；与 HTTP 语义无涉，仅 web 信封内使用）
export const WEB_SEND_ERR_BAD_ENVELOPE: string = 'bad_envelope';
export const WEB_SEND_ERR_EMPTY_TEXT: string = 'empty_text';
export const WEB_SEND_ERR_DB_NOT_READY: string = 'db_not_ready';
export const WEB_SEND_ERR_NOT_FOUND: string = 'not_found';
export const WEB_SEND_ERR_NOT_READABLE: string = 'not_readable';
export const WEB_SEND_ERR_NO_CONNECTION: string = 'no_connection';
export const WEB_SEND_ERR_HISTORY: string = 'history_failed';
export const WEB_SEND_ERR_REJECTED: string = 'send_rejected';
export const WEB_SEND_ERR_TOO_MANY_SESSIONS: string = 'too_many_sessions';
export const WEB_SEND_ERR_INTERNAL: string = 'internal';

// 请求信封（严格解析产物；reqId = '' = 未带，回执省略该字段）
export interface WebSendRequest {
  readonly conversationId: string;
  readonly text: string;
  readonly reqId: string;
}

// 回执错误体（照 WebReadApi 的 {code,message} 二员——每分支一个码，客户端可编程判别）
export interface WebSendErrorBody {
  code: string;
  message: string;
}

// 回执信封（reqId/error 可选——只在有值时落字段，照 WebReadApi 显式错误码风格）
export interface WebSendResultEnvelope {
  type: string;
  reqId?: string;
  ok: boolean;
  error?: WebSendErrorBody;
}

// ── 纯函数面（零 @kit 依赖，断言脚本剥 import 直跑；信封解析与回执序列化）──

// send 信封严格解析：JSON 根对象 + type 恰为 'send' + conversationId/text 非空字符串 +
// reqId 在场时必须是字符串——其余（脏 JSON / 非对象根 / 缺员 / 类型不符）一律 null
export function parseWebSendRequest(text: string): WebSendRequest | null {
  const rec: Record<string, Object> | null = webEnvelopeObject(text, WEB_SEND_REQUEST_TYPE);
  if (rec === null) {
    return null;
  }
  const cid: Object | undefined = rec['conversationId'];
  const body: Object | undefined = rec['text'];
  if (typeof cid !== 'string' || cid === '' || typeof body !== 'string') {
    return null;
  }
  const rawReqId: Object | undefined = rec['reqId'];
  if (rawReqId !== undefined && typeof rawReqId !== 'string') {
    return null;
  }
  const req: WebSendRequest = {
    conversationId: cid,
    text: body,
    reqId: typeof rawReqId === 'string' ? rawReqId : ''
  };
  return req;
}

// stop 信封严格解析：conversationId 非空字符串才回 id（其余回 ''——fail-closed 零动作）
export function parseWebStopRequest(text: string): string {
  const rec: Record<string, Object> | null = webEnvelopeObject(text, WEB_STOP_REQUEST_TYPE);
  if (rec === null) {
    return '';
  }
  const cid: Object | undefined = rec['conversationId'];
  return typeof cid === 'string' ? cid : '';
}

// 回执序列化（reqId 空省略；ok=false 必带 error 二员——码空时回 general 兜底，禁空错误）
export function buildWebSendResult(reqId: string, ok: boolean, code: string,
  message: string): string {
  const env: WebSendResultEnvelope = { type: WEB_SEND_RESULT_TYPE, ok: ok };
  if (reqId !== '') {
    env.reqId = reqId;
  }
  if (!ok) {
    const body: WebSendErrorBody = {
      code: code !== '' ? code : 'send_failed',
      message: message !== '' ? message : '发送失败'
    };
    env.error = body;
  }
  return JSON.stringify(env);
}

// 信封根对象抽取（type 严格相等 + 根为普通对象——两信封共用前置）
function webEnvelopeObject(text: string, expectedType: string): Record<string, Object> | null {
  let raw: Object;
  try {
    raw = JSON.parse(text) as Object;
  } catch (e) {
    return null;
  }
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
    return null;
  }
  const rec: Record<string, Object> = raw as Record<string, Object>;
  const t: Object | undefined = rec['type'];
  if (typeof t !== 'string' || t !== expectedType) {
    return null;
  }
  return rec;
}

// ── 离屏 UI 绑定（ChatRuntimeUiBinding 实现；每会话一个——conn/webSearchOn 随发送刷新）──

class HeadlessSessionBinding implements ChatRuntimeUiBinding {
  // 未 attach 的跟随器（各入口早退；与 ChatPageLifecycle 解绑态同款构造）
  follow: ChatFollowController = new ChatFollowController(new Scroller());
  // 纯值锚判定器（无页面读口）
  anchorJudge: ChatListAnchorJudge = new ChatListAnchorJudge();
  // 当前会话连接（发送前现解析；null = 未解析/解析失败——发送守卫据此拒绝）
  connNow: AiConnection | null = null;
  // 会话级联网开关（助手能力上限 ∩ 本会话未关——与 ChatSessionOverrideCtrl 同口径，
  // 但按被发送会话的覆盖行现算，不读全局广播键：多会话并发时广播键可能属另一会话）
  webSearchOnNow: boolean = true;

  setConn(conn: AiConnection | null): void {
    this.connNow = conn;
  }

  setWebSearchOn(on: boolean): void {
    this.webSearchOnNow = on;
  }

  conn: () => AiConnection | null = (): AiConnection | null => this.connNow;
  thinking: () => string = (): string => '';
  webSearchOn: () => boolean = (): boolean => this.webSearchOnNow;
  sessionOverride: () => ConversationOverride | null = (): ConversationOverride | null => null;
  // 以下为无屏面：写回调 none（setSending 只镜像页面 @State；toast/收尾/错误清理/输入
  // 归还全是 UI 行为——web 侧失败经 send_result 回执，不占页面槽）
  setSending: (sending: boolean) => void = (_sending: boolean): void => {
  };
  clearError: () => void = (): void => {
  };
  toast: (message: string) => void = (_message: string): void => {
  };
  onRoundSettled: () => void = (): void => {
  };
  reloadBranchPath: () => Promise<boolean> = (): Promise<boolean> => Promise.resolve(false);
  restoreSendInput: (text: string, attachments: PendingAttachment[]) => void =
    (_text: string, _attachments: PendingAttachment[]): void => {
    };
  // 待发引用（web V1 不支持引用：读口恒空、清口零动作）
  pendingQuote: () => string = (): string => '';
  clearPendingQuote: () => void = (): void => {
  };
}

// 会话登记（每被 web 打开的会话一条）：运行态 + 离屏绑定 + 持有它的连接集 + 历史装载闩
interface WebHeadlessSession {
  readonly conversationId: string;
  readonly state: ChatRuntimeState;
  readonly binding: HeadlessSessionBinding;
  readonly conns: Set<string>;
  historyTask: Promise<void> | null;
}

export class WebHeadlessHost implements ChatLiveSubscriber {
  private sessions: Map<string, WebHeadlessSession> = new Map<string, WebHeadlessSession>();

  // 中枢订阅回调（本件不消费事件负载——订阅只为驱动 hub 的 lazy wire：round_begin watcher
  // + 增量/终态 tap 在订阅时挂上；注销即摘线成对）
  onEvent(_event: ChatLiveEvent): void {
  }

  // 消息分流入口（manager 的 onMessage 调用）：send/stop 归本件，返回 true = 已接管；
  // false = 不属本件（交读 API 分发）。解析失败也接管——send 回错误回执（reqId 空），
  // stop 静默（无回执语义）
  handleMessage(connId: string, text: string, sender: WebApiSender): boolean {
    if (this.envelopeTypeOf(text) === WEB_SEND_REQUEST_TYPE) {
      this.onSendEnvelope(connId, text, sender);
      return true;
    }
    if (this.envelopeTypeOf(text) === WEB_STOP_REQUEST_TYPE) {
      const cid: string = parseWebStopRequest(text);
      if (cid !== '') {
        this.stopConversation(cid);
      }
      return true;
    }
    return false;
  }

  // 连接断开释放（manager onDisconnect 调用）：摘该连接的会话登记；连接集空即整会话关闭
  releaseConn(connId: string): void {
    const closing: WebHeadlessSession[] = [];
    this.sessions.forEach((session: WebHeadlessSession): void => {
      if (!session.conns.has(connId)) {
        return;
      }
      session.conns.delete(connId);
      if (session.conns.size === 0) {
        closing.push(session);
      }
    });
    for (const session of closing) {
      this.closeSession(session);
    }
  }

  // 服务停止（manager stop 调用；pause 走连接断连链已覆盖）：全部会话成对释放
  closeAll(): void {
    const closing: WebHeadlessSession[] = [];
    this.sessions.forEach((session: WebHeadlessSession): void => {
      closing.push(session);
    });
    for (const session of closing) {
      this.closeSession(session);
    }
  }

  // 会话数现读（诊断/断言面；有界上限的自证口）
  sessionCount(): number {
    return this.sessions.size;
  }

  // ── send 信封处理（异步全链：DB 就绪 → 会话/可读性 → 连接解析 → 历史回放 → 发送）──
  private onSendEnvelope(connId: string, text: string, sender: WebApiSender): void {
    const req: WebSendRequest | null = parseWebSendRequest(text);
    if (req === null) {
      this.reply(sender, connId, buildWebSendResult('', false,
        WEB_SEND_ERR_BAD_ENVELOPE, '消息不是有效的发送信封'));
      return;
    }
    this.sendFromWeb(connId, req, sender).catch((e: Error): void => {
      hilog.warn(WEB_LOG_DOMAIN, WEB_LOG_TAG, 'web 发送链异常（%{public}s）', e.message);
      this.reply(sender, connId, buildWebSendResult(req.reqId, false, WEB_SEND_ERR_INTERNAL,
        e.message));
    });
  }

  private async sendFromWeb(connId: string, req: WebSendRequest,
    sender: WebApiSender): Promise<void> {
    if (req.text === '') {
      this.reply(sender, connId, buildWebSendResult(req.reqId, false, WEB_SEND_ERR_EMPTY_TEXT,
        '消息内容为空'));
      return;
    }
    const dbReady: boolean = await whenReady();
    if (!dbReady) {
      this.reply(sender, connId, buildWebSendResult(req.reqId, false, WEB_SEND_ERR_DB_NOT_READY,
        '数据库未就绪'));
      return;
    }
    // 存在性与可读性（ForRead 口：不存在即不可读）
    const conv: ChatReadConvRow | null = await queryConversationRowByIdForRead(req.conversationId);
    if (conv === null) {
      this.reply(sender, connId, buildWebSendResult(req.reqId, false, WEB_SEND_ERR_NOT_FOUND,
        '会话不存在或不可读'));
      return;
    }
    // 读路由（旧格式墓碑拒发——发送链的 routeState 镜像是页面装载产物，web 侧以此为准）
    const route: ConversationLoadRoute = await conversationLoadRoute(req.conversationId);
    if (route.route === ROUTE_BLOCKED) {
      this.reply(sender, connId, buildWebSendResult(req.reqId, false,
        WEB_SEND_ERR_NOT_READABLE, '会话为旧格式，不可回复'));
      return;
    }
    const session: WebHeadlessSession | null = this.ensureSession(connId, req.conversationId);
    if (session === null) {
      this.reply(sender, connId, buildWebSendResult(req.reqId, false,
        WEB_SEND_ERR_TOO_MANY_SESSIONS, '会话打开失败或数量已达上限'));
      return;
    }
    // 连接解析（四级兜底链：会话覆盖 > 会话所属助手 > 全局默认 > 首个启用——与页面
    // reloadConn 同源；web 无页面内存覆盖，覆盖只认库列）
    const info: ActiveConnectionInfo | null = await this.resolveSessionConnection(session);
    if (info === null) {
      this.reply(sender, connId, buildWebSendResult(req.reqId, false,
        WEB_SEND_ERR_NO_CONNECTION, '没有可用的服务商配置'));
      return;
    }
    // 历史上下文回放（仅未装载时；读路由已取，直接用其 branchId）
    try {
      await this.ensureHistoryLoaded(session, route);
    } catch (e) {
      this.reply(sender, connId, buildWebSendResult(req.reqId, false, WEB_SEND_ERR_HISTORY,
        '历史消息读取失败'));
      return;
    }
    // 提示词/工具/技能/记忆解析缓存（页面进页经 ChatSessionOverrideCtrl.refreshWebSearchFlag
    // 预载；web 无页面链，必须自行预载——否则首轮 enabledToolIds 回缺省集合、注入与记忆
    // 全空。只填本控制器的缓存，不写全局广播键——页面 UI 的联网两键不被 web 轮改写）
    await session.state.sendCtrl.loadPromptState(req.conversationId);
    chatSessionRuntime.markDbReady(session.state, true);
    // ★ 轮发起端标记：只在「本次发送会起新轮」时置 'web'——生成中/队列非空 = 入队，不改写
    // 当前在途轮的 origin（否则会把 UI 发起的在途轮标成 web）；终态复位由运行态
    // setSending(false) 边沿统一承担
    if (!session.state.sendingFlag) {
      chatSessionRuntime.setRoundOrigin(session.state, 'web');
    }
    // 同一条发送编排链（sendGate 排队 / AutoRetry / KeyRound / 工具轮全白拿）；hasVision
    // 传 false（web V1 不带附件）；返回值契约 = 已投递或已入队
    const accepted: boolean = session.state.sendCtrl.send(req.text, [], false);
    if (!accepted) {
      // 未起轮 = 标记无主，复位 local（防下一次 UI 轮被误标）
      chatSessionRuntime.setRoundOrigin(session.state, 'local');
      this.reply(sender, connId, buildWebSendResult(req.reqId, false, WEB_SEND_ERR_REJECTED,
        '发送被拒绝，请检查会话状态'));
      return;
    }
    this.reply(sender, connId, buildWebSendResult(req.reqId, true, '', ''));
  }

  // 停止生成（ChatSendCtrl.abort = 宿主无关停止入口，与手机停止键同一条链；无会话登记/无
  // 在途轮 = 幂等空转）。
  // ★ 无头会话不在场 ≠ 无轮可停——「手机发起、web 观看」的镜像轮只有页面侧运行态账目（web
  // 从未发过消息就没有无头会话），须回落运行态账目走同一 abort 链（页面在页/离页在途两形态
  // 均成立），账目也不在场才幂等空转
  private stopConversation(conversationId: string): void {
    const session: WebHeadlessSession | undefined = this.sessions.get(conversationId);
    if (session !== undefined) {
      session.state.sendCtrl.abort();
      return;
    }
    const state: ChatRuntimeState | null = chatSessionRuntime.get(conversationId);
    if (state !== null) {
      state.sendCtrl.abort();
    }
  }

  // 会话取建（按连接登记；同连接重发零新取用）：新建时 acquire(..., headless=true) +
  // hub 订阅（驱动 wire）——超限/构造失败回 null（调用方回错误信封）
  private ensureSession(connId: string, conversationId: string): WebHeadlessSession | null {
    const existing: WebHeadlessSession | undefined = this.sessions.get(conversationId);
    if (existing !== undefined) {
      existing.conns.add(connId);
      return existing;
    }
    if (this.sessions.size >= WEB_HEADLESS_MAX_SESSIONS ||
      this.connSessionCount(connId) >= WEB_HEADLESS_MAX_SESSIONS_PER_CONN) {
      hilog.warn(WEB_LOG_DOMAIN, WEB_LOG_TAG, '会话上限拒新（%{public}s，全量 %{public}d）',
        conversationId, this.sessions.size);
      return null;
    }
    const binding: HeadlessSessionBinding = new HeadlessSessionBinding();
    const dataSource: ChatDataSource = chatSessionRuntime.newDataSource();
    let state: ChatRuntimeState;
    try {
      state = chatSessionRuntime.acquire(conversationId, dataSource, binding,
        (ds: ChatDataSource, refs: ChatSendRefs): ChatRuntimeSeed => {
          // 种子工厂照 ChatPageLifecycle.ensureRuntimeState:229 同形（消费 ChatSendCtrl
          // 而不编辑它——一族装配后三件到达面取出）
          const sendCtrl: ChatSendCtrl = new ChatSendCtrl(refs);
          const seed: ChatRuntimeSeed = {
            sendCtrl: sendCtrl,
            flow: sendCtrl.flowCtrl(),
            keyRound: sendCtrl.keyRoundCtrl(),
            toolRound: sendCtrl.toolRoundCtrl(),
            queueCtrl: sendCtrl.queueCtrl()
          };
          return seed;
        }, true);
    } catch (e) {
      hilog.warn(WEB_LOG_DOMAIN, WEB_LOG_TAG, '无头会话建族失败（%{public}s）',
        (e as Error).message);
      return null;
    }
    // 订阅驱动 hub lazy wire（round_begin watcher + tap 挂上——直播泵全局订阅者才能收到
    // web 轮事件）；桶满拒绝 = 回滚取用，不静默半态
    if (!chatLiveHub.subscribe(conversationId, this)) {
      chatSessionRuntime.releaseHeadless(state);
      return null;
    }
    const session: WebHeadlessSession = {
      conversationId: conversationId,
      state: state,
      binding: binding,
      conns: new Set<string>(),
      historyTask: null
    };
    session.conns.add(connId);
    this.sessions.set(conversationId, session);
    hilog.info(WEB_LOG_DOMAIN, WEB_LOG_TAG, '无头会话入园（%{public}s，全量 %{public}d）',
      conversationId, this.sessions.size);
    return session;
  }

  // 会话关闭（成对释放）：登记除名 → hub 退订（摘 wire）→ 运行态引用释放（在途轮照跑，
  // 收尾按既有编排链落库；attached 归零 + 非生成即 5s 空闲回收）
  private closeSession(session: WebHeadlessSession): void {
    this.sessions.delete(session.conversationId);
    chatLiveHub.unsubscribe(session.conversationId, this);
    chatSessionRuntime.releaseHeadless(session.state);
    hilog.info(WEB_LOG_DOMAIN, WEB_LOG_TAG, '无头会话退园（%{public}s，全量 %{public}d）',
      session.conversationId, this.sessions.size);
  }

  private connSessionCount(connId: string): number {
    let count: number = 0;
    this.sessions.forEach((session: WebHeadlessSession): void => {
      if (session.conns.has(connId)) {
        count++;
      }
    });
    return count;
  }

  // 连接解析（会话覆盖来自库列；owner 从会话行查，'' = 内置默认助手——与 ChatPageLoad
  // reloadConn 的归属口径一致，页面内存覆盖在 web 侧不存在）
  private async resolveSessionConnection(session: WebHeadlessSession):
    Promise<ActiveConnectionInfo | null> {
    const cid: string = session.conversationId;
    const ov: ConversationOverride | null = await queryConversationOverride(cid);
    const ownerRaw: string | null = await queryConversationAssistantId(cid);
    const ownerId: string = ownerRaw !== null && ownerRaw !== '' ? ownerRaw : ASSISTANT_DEFAULT_ID;
    const info: ActiveConnectionInfo | null = await resolveActiveConnection(ownerId,
      ov !== null ? ov.modelProviderId : '', ov !== null ? ov.modelId : '');
    if (info === null) {
      session.binding.setConn(null);
      return null;
    }
    session.binding.setConn(info.conn);
    // 会话级联网开关（值键口径 = 上限 ∩ 本会话未关；上限在发送链内部按助手启用清单判，
    // 本处只表达会话覆盖「关」）
    session.binding.setWebSearchOn(ov === null || ov.webSearchOverride !== '0');
    return info;
  }

  // 历史装载（幂等 + 单飞：页面已装载零动作；在途任务复用——并发两笔 web 发送不重复回放）
  private ensureHistoryLoaded(session: WebHeadlessSession,
    route: ConversationLoadRoute): Promise<void> {
    if (session.state.dataSource.historyLoaded) {
      return Promise.resolve();
    }
    const pending: Promise<void> | null = session.historyTask;
    if (pending !== null) {
      return pending;
    }
    const task: Promise<void> = this.loadHistoryRows(session, route).then((): void => {
      session.historyTask = null;
    }).catch((e: Error): void => {
      session.historyTask = null;
      throw (e);
    });
    session.historyTask = task;
    return task;
  }

  private async loadHistoryRows(session: WebHeadlessSession,
    route: ConversationLoadRoute): Promise<void> {
    const rows: MessageRow[] = await readPathPageRows(session.conversationId, route.branchId,
      null, QUERY_TAIL_LIMIT);
    // 尾部窗口回放（与手机进页同量级；展示轮事实不投射——web 直播走事件、读面走读 API）
    session.state.dataSource.rebuildFromHistory(rows);
  }

  // 回执发送（发送失败由载体件断连兜底——此处只留痕，不重试不记账）
  private reply(sender: WebApiSender, connId: string, text: string): void {
    sender.send(connId, text).catch((e: Error): void => {
      hilog.warn(WEB_LOG_DOMAIN, WEB_LOG_TAG, '回执发送失败（%{public}s）', e.message);
    });
  }

  // 信封 type 预读（只认根对象 type 字符串；与本域 parse 的前置同判——分流用，容错回 ''）
  private envelopeTypeOf(text: string): string {
    try {
      const raw: Object = JSON.parse(text) as Object;
      if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
        return '';
      }
      const rec: Record<string, Object> = raw as Record<string, Object>;
      const t: Object | undefined = rec['type'];
      return typeof t === 'string' ? t : '';
    } catch (e) {
      return '';
    }
  }
}

// 进程级单例（模块级单例形制——chatSessionRuntime/chatLiveHub/webServiceManager 先例；
// manager 路由与断连释放经此同一实例）
export const webHeadlessHost: WebHeadlessHost = new WebHeadlessHost();
