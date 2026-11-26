// WebSocket 网关载体（官方 @ohos.net.webSocket createWebSocketServer 封装，底层 libwebsockets）。
// ★★ 本件现为**备用件（当前未接线）**：真机实测 createWebSocketServer 的 start() 在四种绑定
// 形态下一律抛 2302999「Internal error」，判为真机普通应用无 WS 服务端能力（取证全文见
// SseStreamHub 头注释）；动态面改由 SseStreamHub 承担，WebServiceManager 已不再 import 本件。
// **重新启用的前置条件**：①目标机 createWebSocketServer().start() 冒烟通过；②前端 web-ui
// 恢复原生 WebSocket 传输（SSE 版 client.ts 见 git 历史）；③manager 的 dynamicCarrier 指回
// 本件 + /__cfg 回 transport:'ws'。三步之外本件无需改动（接口面与 SSE 中枢同形）。
// 职责一句话：**动态面消息收发的 WS 实现**——实现 TransportCarrier 抽象，向上只暴露 connId
// 与文本，向下管官方 WebSocketServer 的启停、事件订阅、连接簿记与心跳。
// d.ts 硬契约（SDK 26 亲读）：WebSocketServerConfig 三项 serverPort / maxConcurrentClientsNumber
// / maxConnectionsForOneClient **均必填**（官方文档误标可选，以 d.ts 为准显式传全三参——漏传
// 运行时炸）；serverIP? 缺省 0.0.0.0（★ 实际一律省略不传，见 start 注释）；start 返
// Promise<boolean>（false = 失败），端口被占抛 2302007（since 24）；单条 send 上限 5,242,864
// 字节（5×1024×1024−16，lws 协议头预留）；事件四件套 = connect / **messageReceive**
//（非 'message'）/ close / error；连接身份 = webSocket.WebSocketConnection{clientIP, clientPort}
//——**无原生 connId，本件自合成 'ip:port'**；listAllConnections 同步签名与 d.ts 注释矛盾
//——**连接簿记自持 Map 不依赖它**。
// 心跳（FAQ faqs-network-84 方案）：服务端无内建 ping——应用层 30s 间隔发 {"type":"ping"}，
// 连续 WS_HEARTBEAT_MAX_MISSES 次无 pong 断连清簿记；pong 任意时点到达即清零计数。
// 鉴权 fail-closed 四条：①WS_AUTH_TIMEOUT_MS 内未通过首消息校验即 close；②未鉴权连接不进
// 业务路由（sendTo 只对已鉴权连接开放）；③口令空由 validator 判拒；④validator 未装配 = 一律
// 拒绝（本件缺省态）。首条消息经 authValidator 回调判定，通过后该连接后续消息进
// events.onMessage；仅本机档免鉴权由注入的 validator 自行表达（本件不感知档位策略）。
// WS send 无背压 API → 单连接串行交由底层队列 + **发送失败即断连**（快照语义兜底；重连即
// 全量 snapshot 校正归直播泵）。
// 内存防线：连接 Map 有界（WS_MAX_CONNECTIONS 对齐中枢订阅桶 16）；每连接鉴权超时定时器成对
// 清除；心跳 interval 在 stop 清除（成对释放）；stop 全清簿记。生命周期与 TCP 件差异：本件
// 每轮 start 新建 server 对象、stop 时 off 全部事件——整建整弃最简；TCP 件保持「订阅单次到
// 底 + close→listen 重启」形态（见彼件头注释）。
// 依赖纪律（零环）：只引 @kit 网络与系统能力 + 本域 TransportCarrier，禁 import UI 件与聊天域件。
import { webSocket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { isWebServiceLoopbackOnly } from '../AppPreferencesWeb';
import { CarrierAuthValidator, CarrierConfig, CarrierEvents, TransportCarrier } from './TransportCarrier';

const WS_LOG_DOMAIN: number = 0xD5A0;
const WS_LOG_TAG: string = 'WsGateway';

// 连接簿记上限（对齐 ChatLiveHub 订阅桶上限 16——单镜像器 + 诊断面 + 多标签页余量；
// d.ts maxConcurrentClientsNumber 同值显式传，双保险拒新）
export const WS_MAX_CONNECTIONS: number = 16;
// 单客户端（同 IP）连接上限：一台设备多标签页场景 4 条富余，同时限单 IP 连接耗尽攻击面
export const WS_MAX_CONNECTIONS_PER_CLIENT: number = 4;
// 心跳间隔（FAQ faqs-network-84：30s 应用层 ping）
export const WS_HEARTBEAT_INTERVAL_MS: number = 30000;
// 无 pong 容忍次数（拍板：30s×2 ≈ 1 分钟静默即判死链——半开连接回收上限）
export const WS_HEARTBEAT_MAX_MISSES: number = 2;
// 未鉴权连接存活窗（fail-closed ①：5s 内未通过首消息鉴权即 close）
export const WS_AUTH_TIMEOUT_MS: number = 5000;
// 单条消息字节上限（d.ts 明文公式 5×1024×1024−16 = 5242864——lws 协议头预留 16 字节；
// 字面量形态便于断言源内现读锚定）
export const WS_SEND_MAX_BYTES: number = 5242864;

// 心跳与鉴权信封（传输层控制消息——与中枢业务信封不同族，type 值错开）
const WS_PING_TEXT: string = '{"type":"ping"}';
const WS_AUTH_REQUIRED_TEXT: string = '{"type":"auth_required"}';
const WS_AUTH_FAILED_TEXT: string = '{"type":"auth_failed"}';
// 通用断连提示（心跳失联/下行失败等非鉴权原因的主动断——前端收 close 即走指数退避重连，
// 本信封仅诊断用途，不驱动状态机）
const WS_CLOSE_NOTICE_TEXT: string = '{"type":"close_notice"}';

// ── 纯函数面（零 @kit 依赖，断言脚本剥 import 直跑）──

// connId 自合成：官方连接对象只含 {clientIP, clientPort}，'ip:port' 唯一（同客户端重连
// 换源口 = 新 connId，旧条目由 close 事件清）
export function wsConnIdOf(clientIP: string, clientPort: number): string {
  return clientIP + ':' + clientPort.toString();
}

// WS 服务错误码 → 中文文案（2302007 端口占用 → 「端口被占用，请换端口」等；未知码回带码
// 通用句——fail-fast 归 manager，禁自动换口）
export function wsErrorTextOf(code: number): string {
  if (code === 2302007) {
    return '端口被占用，请换端口';
  }
  if (code === 2302004) {
    return '网卡无效，无法监听';
  }
  if (code === 2302002) {
    return '证书不存在';
  }
  if (code === 2302005) {
    return '端口无效';
  }
  if (code === 2302006) {
    return '连接不存在';
  }
  if (code === 2302999) {
    return 'WebSocket 服务内部错误';
  }
  return 'WebSocket 服务错误 ' + code.toString();
}

// 文本消息的 type 域提取（心跳 pong / 首消息 auth 共用判据）：JSON 根对象且 type 为 string
// 才回该值，其余（脏 JSON / 非对象根 / 无 type）回 ''——不抛错（传输层宁可拒不可炸）
export function wsMessageTypeOf(text: string): string {
  try {
    const raw: Object = JSON.parse(text) as Object;
    if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
      return '';
    }
    const rec: Record<string, Object> = raw as Record<string, Object>;
    const t: Object | undefined = rec['type'];
    if (typeof t === 'string') {
      return t;
    }
  } catch (e) {
    return '';
  }
  return '';
}

// 鉴权钩接口位（口令实现在 WebAuthValidator）。★ 类型已下沉 TransportCarrier
//（CarrierAuthValidator），本件保留 WsAuthValidator 别名供既有引用与断言零改。
export type WsAuthValidator = CarrierAuthValidator;

// 连接簿记条目
interface WsConnEntry {
  readonly connection: webSocket.WebSocketConnection;
  readonly connId: string;
  authenticated: boolean;
  pingMisses: number;
  authTimerId: number;
  closed: boolean;
}

export class WsGateway implements TransportCarrier {
  readonly carrierKind: string = 'ws';
  private server: webSocket.WebSocketServer | null = null;
  private conns: Map<string, WsConnEntry> = new Map<string, WsConnEntry>();
  private events: CarrierEvents | null = null;
  private heartbeatTimerId: number = 0;
  private running: boolean = false;
  private authValidator: WsAuthValidator | null = null;
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8');

  // 鉴权钩注入（manager 装配；null = fail-closed 全拒——本件缺省态即无鉴权骨架态）
  setAuthValidator(validator: WsAuthValidator | null): void {
    this.authValidator = validator;
  }

  async start(cfg: CarrierConfig, events: CarrierEvents): Promise<void> {
    this.events = events;
    const server: webSocket.WebSocketServer = webSocket.createWebSocketServer();
    this.server = server;
    this.subscribeServer(server);
    // ★ 必填三项显式传全（d.ts 无 ?；漏传运行时炸）。★ **serverIP 一律省略不传**——真机实测
    // 显式传任何值（0.0.0.0 / 127.0.0.1 / 具体 IP）一律抛 2302999「服务内部错误」（lws 底层对
    // 显式指定绑定地址的路径有问题；文档默认 0.0.0.0 即底层默认路径可用形态）。仅本机档的隔离
    // 不再依赖绑定地址——由 acceptConnection 的来源守卫应用层秒断非回环连接（鉴权层同款判定
    // 的第二道闸）。
    const config: webSocket.WebSocketServerConfig = {
      serverPort: cfg.port,
      maxConcurrentClientsNumber: WS_MAX_CONNECTIONS,
      maxConnectionsForOneClient: WS_MAX_CONNECTIONS_PER_CLIENT
    };
    try {
      const ok: boolean = await server.start(config);
      if (!ok) {
        throw new Error('WS 启动返回失败（端口 ' + cfg.port + '，请换端口）');
      }
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      // 原始错误码随文案透出（★ 此前 wsErrorTextOf 把 code 吃成纯中文，真机排障只能猜——
      // 码随行用户可读回，文案映射保留人话部分）
      const text: string = wsErrorTextOf(err.code) + ' ' + err.code.toString() +
        '（端口 ' + cfg.port + '）';
      await this.stop();
      throw new Error(text);
    }
    // 防御性复检：await 期间若被 stop 打断（manager 已串行化，此处兜未来直调）——server
    // 引用已被换/清则不提交 running、不起心跳，并释放本次新建的监听
    if (this.server !== server) {
      try {
        await server.stop();
      } catch (e) {
        // 已停止即幂等
      }
      throw new Error('WS 启动被停止操作打断');
    }
    this.running = true;
    this.startHeartbeat();
    hilog.info(WS_LOG_DOMAIN, WS_LOG_TAG, 'WS 面监听就绪 %{public}s:%{public}d',
      cfg.bindAddress, cfg.port);
  }

  private subscribeServer(server: webSocket.WebSocketServer): void {
    server.on('connect', (conn: webSocket.WebSocketConnection): void => {
      this.acceptConnection(conn);
    });
    server.on('messageReceive', (msg: webSocket.WebSocketMessage): void => {
      this.onConnMessage(msg);
    });
    server.on('close', (conn: webSocket.WebSocketConnection, reason: webSocket.CloseResult): void => {
      this.cleanupConnection(wsConnIdOf(conn.clientIP, conn.clientPort));
    });
    server.on('error', (err: BusinessError): void => {
      hilog.error(WS_LOG_DOMAIN, WS_LOG_TAG, 'WS server error %{public}d：%{public}s',
        err.code, err.message);
      if (this.events !== null) {
        this.events.onError(err.code, wsErrorTextOf(err.code));
      }
    });
  }

  private acceptConnection(conn: webSocket.WebSocketConnection): void {
    if (!this.running) {
      return;
    }
    // 仅本机档来源守卫（★ WS 面绑定地址一律省略后，档位隔离从绑定层移到应用层——非回环来源
    // 秒断，内核层端口虽全网卡监听但应用层零服务；实时读键，改档位对新连接即刻生效；回环判定
    // 与 WebAuthValidator 同一 IPv4 127.0.0.1 口径）
    if (isWebServiceLoopbackOnly() && conn.clientIP !== '127.0.0.1') {
      hilog.warn(WS_LOG_DOMAIN, WS_LOG_TAG, '仅本机档拒绝非回环连接（%{public}s）', conn.clientIP);
      this.server?.close(conn).catch((): void => {
      });
      return;
    }
    const connId: string = wsConnIdOf(conn.clientIP, conn.clientPort);
    // 同 connId 旧条目在场（源口复用窗口内旧 close 迟到/丢失）：先幂等清旧账——否则 set 覆盖
    // 后旧 authTimer 仍会触发 dropConnection 误断新连接
    if (this.conns.has(connId)) {
      this.cleanupConnection(connId);
    }
    if (this.conns.size >= WS_MAX_CONNECTIONS) {
      hilog.warn(WS_LOG_DOMAIN, WS_LOG_TAG, '连接数达上限 %{public}d 拒新（%{public}s）',
        WS_MAX_CONNECTIONS, connId);
      this.server?.close(conn).catch((): void => {
      });
      return;
    }
    const entry: WsConnEntry = {
      connection: conn,
      connId: connId,
      authenticated: false,
      pingMisses: 0,
      authTimerId: 0,
      closed: false
    };
    // fail-closed ①：鉴权窗计时，超时未过即 close
    entry.authTimerId = setTimeout((): void => {
      hilog.info(WS_LOG_DOMAIN, WS_LOG_TAG, '鉴权超时断连 %{public}s', connId);
      this.dropConnection(entry, WS_AUTH_REQUIRED_TEXT);
    }, WS_AUTH_TIMEOUT_MS);
    this.conns.set(connId, entry);
    if (this.events !== null) {
      this.events.onConnect(connId);
    }
  }

  private onConnMessage(msg: webSocket.WebSocketMessage): void {
    const connId: string = wsConnIdOf(msg.clientConnection.clientIP, msg.clientConnection.clientPort);
    const entry: WsConnEntry | undefined = this.conns.get(connId);
    if (entry === undefined || entry.closed) {
      return;
    }
    let text: string = '';
    if (typeof msg.data === 'string') {
      text = msg.data;
    } else {
      try {
        text = this.decoder.decodeToString(new Uint8Array(msg.data));
      } catch (e) {
        return;
      }
    }
    // 未鉴权：首条消息走鉴权钩（fail-closed ②④——未过/未装配钩都不进业务路由）
    if (!entry.authenticated) {
      this.handleAuthMessage(entry, text);
      return;
    }
    // 心跳 pong：任意时点到达即清零失联计数（type 判据单源 wsMessageTypeOf）
    if (wsMessageTypeOf(text) === 'pong') {
      entry.pingMisses = 0;
      return;
    }
    if (this.events !== null) {
      this.events.onMessage(connId, text);
    }
  }

  private handleAuthMessage(entry: WsConnEntry, text: string): void {
    const validator: WsAuthValidator | null = this.authValidator;
    if (validator === null) {
      // 无鉴权实现（骨架态）= 拒绝全部（fail-closed ④），提示信封后即断
      this.dropConnection(entry, WS_AUTH_REQUIRED_TEXT);
      return;
    }
    let granted: boolean = false;
    try {
      granted = validator(entry.connId, text);
    } catch (e) {
      hilog.warn(WS_LOG_DOMAIN, WS_LOG_TAG, '鉴权回调异常按未认证处理（%{public}s）',
        (e as Error).message);
      granted = false;
    }
    if (!granted) {
      this.dropConnection(entry, WS_AUTH_FAILED_TEXT);
      return;
    }
    entry.authenticated = true;
    clearTimeout(entry.authTimerId);
    entry.authTimerId = 0;
  }

  // 单连接主动断：尽力发一条提示信封后 close，簿记清理由 close 事件回调兜底（此处直清
  // 双保险——幂等）
  private dropConnection(entry: WsConnEntry, noticeText: string): void {
    const server: webSocket.WebSocketServer | null = this.server;
    if (server !== null) {
      server.send(noticeText, entry.connection).catch((): void => {
      }).then((): void => {
        server.close(entry.connection).catch((): void => {
        });
      });
    }
    this.cleanupConnection(entry.connId);
  }

  // 心跳（FAQ 84）：30s 一拍全已鉴权连接发 ping；失联计数超容忍上限即断（半开回收）
  private startHeartbeat(): void {
    this.heartbeatTimerId = setInterval((): void => {
      if (!this.running) {
        return;
      }
      const snapshot: WsConnEntry[] = [];
      this.conns.forEach((entry: WsConnEntry): void => {
        snapshot.push(entry);
      });
      for (const entry of snapshot) {
        if (entry.closed || !entry.authenticated) {
          continue;
        }
        entry.pingMisses++;
        // ★ 判据用 >=——用 > 实际第 3 拍（90s）才断，与「30s×2 ≈ 1 分钟」注释不符；>= 在
        // 第 2 拍（60s）回收半开连接
        if (entry.pingMisses >= WS_HEARTBEAT_MAX_MISSES) {
          hilog.info(WS_LOG_DOMAIN, WS_LOG_TAG, '心跳失联断连 %{public}s（%{public}d 拍无 pong）',
            entry.connId, entry.pingMisses);
          this.dropConnection(entry, WS_CLOSE_NOTICE_TEXT);
          continue;
        }
        const server: webSocket.WebSocketServer | null = this.server;
        if (server !== null) {
          server.send(WS_PING_TEXT, entry.connection).catch((): void => {
            // 发送失败即断连（无背压 API 的快照语义兜底——重连由客户端指数退避）
            this.cleanupConnection(entry.connId);
          });
        }
      }
    }, WS_HEARTBEAT_INTERVAL_MS);
  }

  // 连接收尾（成对释放：鉴权定时器 clearTimeout + 簿记删除；close 事件回调幂等复入安全）
  private cleanupConnection(connId: string): void {
    const entry: WsConnEntry | undefined = this.conns.get(connId);
    if (entry === undefined) {
      return;
    }
    this.conns.delete(connId);
    if (entry.closed) {
      return;
    }
    entry.closed = true;
    if (entry.authTimerId !== 0) {
      clearTimeout(entry.authTimerId);
      entry.authTimerId = 0;
    }
    if (this.events !== null) {
      this.events.onDisconnect(connId);
    }
  }

  async stop(): Promise<void> {
    this.running = false;
    if (this.heartbeatTimerId !== 0) {
      clearInterval(this.heartbeatTimerId);
      this.heartbeatTimerId = 0;
    }
    const server: webSocket.WebSocketServer | null = this.server;
    const snapshot: WsConnEntry[] = [];
    this.conns.forEach((entry: WsConnEntry): void => {
      snapshot.push(entry);
    });
    for (const entry of snapshot) {
      if (server !== null) {
        server.close(entry.connection).catch((): void => {
        });
      }
      this.cleanupConnection(entry.connId);
    }
    this.conns.clear();
    if (server !== null) {
      // 成对释放：事件全 off（本件每轮 start 新建 server，无 TCP 侧重订阅约束）
      server.off('connect');
      server.off('messageReceive');
      server.off('close');
      server.off('error');
      try {
        await server.stop();
      } catch (e) {
        hilog.warn(WS_LOG_DOMAIN, WS_LOG_TAG, 'WS stop 异常（%{public}s）', (e as Error).message);
      }
    }
    this.server = null;
    this.events = null;
    hilog.info(WS_LOG_DOMAIN, WS_LOG_TAG, 'WS 面停止');
  }

  async sendTo(connId: string, text: string): Promise<boolean> {
    const entry: WsConnEntry | undefined = this.conns.get(connId);
    const server: webSocket.WebSocketServer | null = this.server;
    // fail-closed ②：未鉴权/不存在连接不受理下行（鉴权提示与心跳由内部通道发，不经本口）
    if (entry === undefined || entry.closed || !entry.authenticated || server === null) {
      return false;
    }
    // 上限预检（字符数 ≤ 字节数，length 超限必超字节限——粗闸；精确字节限由 API 兜底返错）
    if (text.length > WS_SEND_MAX_BYTES) {
      hilog.warn(WS_LOG_DOMAIN, WS_LOG_TAG, '下行超长拒发（%{public}s，%{public}d 字符）',
        connId, text.length);
      return false;
    }
    try {
      // ★ d.ts 明确 Promise<boolean>，false = 发送失败——忽略返回值会把失败帧当成功（队列
      // 不回退、连接不断，违背「发送失败即断连」头注释）
      const sent: boolean = await server.send(text, entry.connection);
      if (!sent) {
        hilog.warn(WS_LOG_DOMAIN, WS_LOG_TAG, '下行返回失败断连 %{public}s', connId);
        this.dropConnection(entry, WS_CLOSE_NOTICE_TEXT);
        return false;
      }
      return true;
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.warn(WS_LOG_DOMAIN, WS_LOG_TAG, '下行失败断连 %{public}s（%{public}d）',
        connId, err.code);
      this.dropConnection(entry, WS_CLOSE_NOTICE_TEXT);
      return false;
    }
  }

  async broadcast(text: string): Promise<number> {
    let delivered: number = 0;
    const snapshot: string[] = [];
    this.conns.forEach((entry: WsConnEntry): void => {
      if (entry.authenticated && !entry.closed) {
        snapshot.push(entry.connId);
      }
    });
    for (const connId of snapshot) {
      const ok: boolean = await this.sendTo(connId, text);
      if (ok) {
        delivered++;
      }
    }
    return delivered;
  }

  closeConn(connId: string): void {
    const entry: WsConnEntry | undefined = this.conns.get(connId);
    if (entry === undefined) {
      return;
    }
    this.dropConnection(entry, WS_AUTH_REQUIRED_TEXT);
  }

  connectionCount(): number {
    return this.conns.size;
  }
}
