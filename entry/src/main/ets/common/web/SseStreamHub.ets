// SSE 动态面中枢（WS 服务端起不来后的回退件。取证：真机 createWebSocketServer().start() 在
// 省略 / 0.0.0.0 / 127.0.0.1 / 具体 WLAN IP 四种绑定形态下一律抛 2302999「Internal error」
//〔官方错误码页释义 = 空指针或内存分配异常，处置只写「重启机器重试」；官方开发指南仅客户端
// 篇、无服务端篇〕——判为真机普通应用拿不到 WS 服务端能力；SSE 走 TCPSocketServer（FAQ
// faqs-network-87 官方背书的自建 HTTP 服务端路线）。本段为本域 2302999 结论单源，WsGateway/
// WebServiceManager 头注释短引用此处）。
// 职责一句话：**动态面的会话表与鉴权门**——把「cid 会话 → 连接」的簿记、首消息口令鉴权、
// 下行投递、断连成对释放收在一处；HTTP/SSE 的字节编解码与 socket 归 TcpHttpStaticCarrier，
// 本件零 socket、零 HTTP 解析（替换边界 = TransportCarrier.ets 的 HttpStreamSink 接口）。
// 单端口 8800 一栈到底：静态面 + /events 下行流 + /api/msg 上行，上层信封、读 API、无头
// 宿主、直播泵、前端信封层零改。
// 传输契约（与 WS 版逐字同形，前端信封层因此零改）：
// · 下行 = `GET /events?cid=<cid>`：SSE 流（text/event-stream，chunked），每条业务消息一帧
//   `data: <JSON 信封>\n\n`；
// · 上行 = `POST /api/msg?cid=<cid>`：请求体即一整条 JSON 信封文本，回 200 后即弃；
// · 会话身份 = cid（客户端自生成的一次连接标识，[A-Za-z0-9_-] ≤ 64），connId = 静态面合成
//   的 'ip:port'（流连接的对端）——鉴权与限速沿用按 IP 口径（WebAuthValidator 的 authIpOf
//   单源）；
// · 鉴权 fail-closed 四条与 WS 版等价：①SSE_AUTH_TIMEOUT_MS 内无有效首消息即关流并下发
//   auth_required；②未鉴权连接不进业务路由（sendTo 亦拒发）；③口令空由 validator 判拒；
//   ④validator 未装配 = 一律拒绝（本件缺省态）。
// 有界：会话表上限 SSE_MAX_CONNECTIONS（对齐中枢订阅桶 16），超限 openStream 回 false（静态
// 面回 503 不建流）；每会话鉴权定时器在鉴权成功/关流/停服三处成对 clearTimeout。
// 依赖纪律（零环）：只引本域 TransportCarrier 接口 + @kit 性能分析（日志），禁 import UI 件、
// 聊天域件与任一载体实现件（WsGateway 备用件亦不引——两载体同形但互不知情）。
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  CarrierAuthValidator,
  CarrierConfig,
  CarrierEvents,
  HttpStreamChannel,
  HttpStreamSink,
  TransportCarrier,
} from './TransportCarrier';

const SSE_LOG_DOMAIN: number = 0xD5A0;
const SSE_LOG_TAG: string = 'SseStreamHub';

// 会话上限（对齐 ChatLiveHub 订阅桶 16——单浏览器多标签页 + 诊断面余量；超限拒新流）
export const SSE_MAX_CONNECTIONS: number = 16;
// cid 长度上限（客户端自生成的连接标识；够放 uuid 36 位，防超长键撑爆簿记）
export const SSE_CID_MAX_LEN: number = 64;
// 未鉴权流存活窗（与 WS 版 WS_AUTH_TIMEOUT_MS 同值同语义：fail-closed ①）
export const SSE_AUTH_TIMEOUT_MS: number = 5000;

// 鉴权/断连控制信封（与 WsGateway 的线协议逐字一致——前端信封层单源在 protocol.ts，此处
// 是服务端同族的**独立副本**：两载体互不 import，协议字面量靠断言钉住相等——冻结接口禁改）
const SSE_AUTH_REQUIRED_TEXT: string = '{"type":"auth_required"}';
const SSE_AUTH_FAILED_TEXT: string = '{"type":"auth_failed"}';
const SSE_CLOSE_NOTICE_TEXT: string = '{"type":"close_notice"}';

// ── 纯函数面（零 @kit 依赖，断言脚本剥 import 直跑）──

// cid 合法性：非空、≤ SSE_CID_MAX_LEN、仅 [A-Za-z0-9_-]。用途 = 静态面路由先校验再进中枢
// （非法 cid 走 400，不占会话名额）；字符集收窄同时挡住把 cid 当键注入的各类花招
export function sseCidValid(cid: string): boolean {
  if (cid.length === 0 || cid.length > SSE_CID_MAX_LEN) {
    return false;
  }
  return /^[A-Za-z0-9_-]+$/.test(cid);
}

// 会话条目（channel = 静态面给的下行写入口；authTimerId 成对 clearTimeout）
interface SseStreamEntry {
  readonly cid: string;
  readonly connId: string;
  readonly channel: HttpStreamChannel;
  authenticated: boolean;
  authTimerId: number;
  closed: boolean;
}

export class SseStreamHub implements TransportCarrier, HttpStreamSink {
  readonly carrierKind: string = 'sse';
  // 双索引：connId 是投递主键（上层只认 connId），cid 是上行路由键（POST 只带 cid）
  private byConn: Map<string, SseStreamEntry> = new Map<string, SseStreamEntry>();
  private byCid: Map<string, string> = new Map<string, string>();
  private events: CarrierEvents | null = null;
  private validator: CarrierAuthValidator | null = null;
  private running: boolean = false;

  // 鉴权钩注入（manager.start 每次启服注入最新闭包；null = fail-closed 全拒）
  setAuthValidator(validator: CarrierAuthValidator | null): void {
    this.validator = validator;
  }

  // ── TransportCarrier：SSE 面随静态面同端口，本件不监听任何端口 ──
  // start 只做「接线 + 清态」：真正的 listen 在 TcpHttpStaticCarrier.start（manager 先起静态面
  // 再起本件，故 /events 到达时 running 已为 true）
  start(_cfg: CarrierConfig, events: CarrierEvents): Promise<void> {
    this.events = events;
    this.running = true;
    hilog.info(SSE_LOG_DOMAIN, SSE_LOG_TAG, 'SSE 动态面随静态面就绪（单端口形态）');
    return Promise.resolve();
  }

  async stop(): Promise<void> {
    this.running = false;
    const snapshot: SseStreamEntry[] = [];
    this.byConn.forEach((entry: SseStreamEntry): void => {
      snapshot.push(entry);
    });
    for (const entry of snapshot) {
      // ★ releaseEntry(connId, true) 内部已带 channel.close()——额外直调 entry.channel.close()
      // 会把 chunked 终止片 '0\r\n\r\n' 同步发两遍（entry.closed 由异步 cleanup 置位，两路
      // 都能进 build 前态）
      this.releaseEntry(entry.connId, true);
    }
    this.byConn.clear();
    this.byCid.clear();
    this.events = null;
    hilog.info(SSE_LOG_DOMAIN, SSE_LOG_TAG, 'SSE 动态面停止');
  }

  // 定向下行（fail-closed ②：未鉴权/不存在/已关回 false；写失败即断连——快照语义兜底）
  sendTo(connId: string, text: string): Promise<boolean> {
    const entry: SseStreamEntry | undefined = this.byConn.get(connId);
    if (entry === undefined || entry.closed || !entry.authenticated) {
      return Promise.resolve(false);
    }
    if (!entry.channel.write(text)) {
      hilog.warn(SSE_LOG_DOMAIN, SSE_LOG_TAG, '下行写失败断流 %{public}s', connId);
      this.releaseEntry(connId, true);
      return Promise.resolve(false);
    }
    return Promise.resolve(true);
  }

  broadcast(text: string): Promise<number> {
    let delivered: number = 0;
    const ids: string[] = [];
    this.byConn.forEach((entry: SseStreamEntry): void => {
      if (entry.authenticated && !entry.closed) {
        ids.push(entry.connId);
      }
    });
    for (const connId of ids) {
      const entry: SseStreamEntry | undefined = this.byConn.get(connId);
      if (entry === undefined) {
        continue;
      }
      if (entry.channel.write(text)) {
        delivered++;
      } else {
        hilog.warn(SSE_LOG_DOMAIN, SSE_LOG_TAG, '广播写失败断流 %{public}s', connId);
        this.releaseEntry(connId, true);
      }
    }
    return Promise.resolve(delivered);
  }

  closeConn(connId: string): void {
    const entry: SseStreamEntry | undefined = this.byConn.get(connId);
    if (entry === undefined || entry.closed) {
      return;
    }
    entry.channel.write(SSE_CLOSE_NOTICE_TEXT);
    this.releaseEntry(connId, true);
  }

  connectionCount(): number {
    return this.byConn.size;
  }

  // ── HttpStreamSink：静态面委托面 ──

  // 建流（静态面在 200 响应头写完之后调）：回 false = 拒绝（服务未起 / cid 非法 / 名额满），
  // 静态面据此关连接。同 cid 或同 connId 的旧条目先成对释放（标签页刷新/端口复用窗口）
  openStream(cid: string, connId: string, channel: HttpStreamChannel): boolean {
    if (!this.running || !sseCidValid(cid)) {
      return false;
    }
    const existingByCid: string | undefined = this.byCid.get(cid);
    if (existingByCid !== undefined) {
      this.releaseEntry(existingByCid, true);
    }
    if (this.byConn.has(connId)) {
      this.releaseEntry(connId, true);
    }
    if (this.byConn.size >= SSE_MAX_CONNECTIONS) {
      hilog.warn(SSE_LOG_DOMAIN, SSE_LOG_TAG, '会话数达上限 %{public}d 拒新流（%{public}s）',
        SSE_MAX_CONNECTIONS, cid);
      return false;
    }
    const entry: SseStreamEntry = {
      cid: cid,
      connId: connId,
      channel: channel,
      authenticated: false,
      authTimerId: 0,
      closed: false
    };
    // fail-closed ①：鉴权窗计时，超时未过即关流（下发 auth_required 后关）
    entry.authTimerId = setTimeout((): void => {
      hilog.info(SSE_LOG_DOMAIN, SSE_LOG_TAG, '鉴权超时断流 %{public}s', cid);
      entry.channel.write(SSE_AUTH_REQUIRED_TEXT);
      this.releaseEntry(entry.connId, true);
    }, SSE_AUTH_TIMEOUT_MS);
    this.byConn.set(connId, entry);
    this.byCid.set(cid, connId);
    if (this.events !== null) {
      this.events.onConnect(connId);
    }
    hilog.info(SSE_LOG_DOMAIN, SSE_LOG_TAG, '流建立 %{public}s（%{public}s）', cid, connId);
    return true;
  }

  // 上行（静态面把 POST 体交来）：未鉴权 → 走鉴权判定（该条信封不上抛，与 WS 版同语义）；
  // 已鉴权 → 业务路由。cid 无对应流 = POST 早于建流/流已断，静默丢弃（前端 5s 鉴权窗内会重连）
  onUpstream(cid: string, text: string): void {
    const connId: string | undefined = this.byCid.get(cid);
    if (connId === undefined) {
      hilog.warn(SSE_LOG_DOMAIN, SSE_LOG_TAG, '上行无对应流（%{public}s）', cid);
      return;
    }
    const entry: SseStreamEntry | undefined = this.byConn.get(connId);
    if (entry === undefined || entry.closed) {
      return;
    }
    if (!entry.authenticated) {
      this.handleAuthMessage(entry, text);
      return;
    }
    if (this.events !== null) {
      this.events.onMessage(connId, text);
    }
  }

  // 下行流断开（静态面对端断连/写失败/停服回调）：成对清会话
  onStreamClosed(connId: string): void {
    this.releaseEntry(connId, false);
  }

  // 鉴权判定（fail-closed ③④）：钩未装配/回调异常/判定拒 → 下发 auth_failed 后关流；
  // 通过 → 转已鉴权并撤计时器（此后该 cid 的上行全部进业务路由）
  private handleAuthMessage(entry: SseStreamEntry, text: string): void {
    const validator: CarrierAuthValidator | null = this.validator;
    if (validator === null) {
      entry.channel.write(SSE_AUTH_REQUIRED_TEXT);
      this.releaseEntry(entry.connId, true);
      return;
    }
    let granted: boolean = false;
    try {
      granted = validator(entry.connId, text);
    } catch (e) {
      hilog.warn(SSE_LOG_DOMAIN, SSE_LOG_TAG, '鉴权回调异常按未认证处理（%{public}s）',
        (e as Error).message);
      granted = false;
    }
    if (!granted) {
      entry.channel.write(SSE_AUTH_FAILED_TEXT);
      this.releaseEntry(entry.connId, true);
      return;
    }
    entry.authenticated = true;
    if (entry.authTimerId !== 0) {
      clearTimeout(entry.authTimerId);
      entry.authTimerId = 0;
    }
  }

  // 会话收尾（成对释放：定时器 clearTimeout + 双索引删除 + 可选关流；幂等——close 事件与
  // 主动关流两路都会进本方法）
  private releaseEntry(connId: string, closeChannel: boolean): void {
    const entry: SseStreamEntry | undefined = this.byConn.get(connId);
    if (entry === undefined) {
      return;
    }
    this.byConn.delete(connId);
    if (this.byCid.get(entry.cid) === connId) {
      this.byCid.delete(entry.cid);
    }
    if (entry.authTimerId !== 0) {
      clearTimeout(entry.authTimerId);
      entry.authTimerId = 0;
    }
    if (!entry.closed) {
      entry.closed = true;
      if (closeChannel) {
        entry.channel.close();
      }
    }
    if (this.events !== null) {
      this.events.onDisconnect(connId);
    }
  }
}
