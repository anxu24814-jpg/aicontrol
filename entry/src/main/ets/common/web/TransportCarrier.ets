// 传输载体抽象——**动态面消息收发的载体无关接口**：上层（中枢/路由/镜像器）只面向 connId
// 与文本信封，不感知底下是官方 WebSocketServer 还是 TCP 手写件。本抽象是为「同进程双栈共存
// 无先例」风险买的保险：任一真机冒烟失败可整体换实现（SSE 备胎）而不动消费方——替换边界
// 到此接口为止。
// ★ 该替换面已启用（真机 WS 服务端四种绑定形态一律 2302999，WsGateway 转备用件不接线）：
// 动态面载体 = SseStreamHub（会话/鉴权/下行）+ TcpHttpStaticCarrier 的 /events 与 /api/msg
// 两路由（HTTP/SSE 编解码），单端口 8800 一栈到底，本接口与上层信封/路由零改。
// 零环红线：本域（common/web/）禁 import 任何 UI 件与聊天域件；只引 @kit 网络与系统能力。
// 连接簿记有界（各实现件自持 Map + 上限常量，宪法「数据有界」）。连接身份：connId 由各实现
// 件自合成（WS = clientIP:clientPort；TCP 件短连接 = 'tcp-N'、SSE 会话 = 'ip:port'）——上层
// 不感知载体原生连接对象（webSocket.WebSocketConnection 不出本域）。

// 载体启动配置（WebServiceManager 组装下发；两栈同形——TCP 面用 port 与 bindAddress，
// wsPortHint 供 /__cfg 传输配置端点返回）
export interface CarrierConfig {
  // 绑定地址：本机 WLAN 具体点分 IP（局域网档，resolveBindAddress 单源解析）或 '127.0.0.1'
  //（仅本机档 = 免鉴权档）。★ 不用 '0.0.0.0' 通配——真机底层拒 wildcard（WS 面 2302999 /
  // TCP 面 address not available），见该函数注记
  readonly bindAddress: string;
  // 本载体监听端口（TCP = 8800 / WS = 8801，由 manager 派生下发）
  readonly port: number;
  // WS 面端口提示（/__cfg 端点返回体数据源——传输配置非业务数据；SSE 档下前端不消费）
  readonly wsPortHint: number;
}

// 载体事件回调（上行面；由 manager/上层注入，回调内异常不炸载体——各实现件 try/catch 留痕）
export interface CarrierEvents {
  onConnect(connId: string): void;
  onMessage(connId: string, text: string): void;
  onDisconnect(connId: string): void;
  onError(code: number, message: string): void;
}

// 首消息口令鉴权钩（connId = 实现件自合成的 'ip:port'；首消息文本由载体上抛判定）。
// WsGateway 与 SseStreamHub 两载体共用同一钩形（类型从 WsGateway 下沉到此），
// WebAuthValidator 装配面（buildWebServiceAuthValidator）不依赖任一实现件。
export type CarrierAuthValidator = (connId: string, firstMessageText: string) => boolean;

// ── SSE 备胎传输面（真机 WS 服务端起不来后的替换件接口）──
// 分工：**HTTP/SSE 编解码归静态面载体（TcpHttpStaticCarrier），业务会话表归 SseStreamHub**
//——静态面把 /events 与 /api/msg 两路由的语义委托给本接口，自己只管字节与 socket；中枢只
// 管会话/鉴权/下行投递——两边各自零感知对方实现（替换边界仍在本文件）。
// 下行流写入口（静态面实现：把 payload 包成 SSE data 帧 + chunked 片写入该连接）
export interface HttpStreamChannel {
  // 写一条业务帧（payload = 一整个 JSON 信封文本；换行转义由信封自身保证，此处不切分）
  write(payload: string): boolean;
  // 关流（静态面发终止片后关连接；幂等）
  close(): void;
}

// 流接入面（静态面调；sink = SseStreamHub）
export interface HttpStreamSink {
  // 客户端建立下行流：cid = 客户端自生成的连接标识，connId = 静态面自合成 'ip:port'，
  // channel = 静态面为本连接构造的下行写入口。回 false = 拒收（连接数满 / cid 非法 / 服务
  // 未运行）——静态面据此回 503 不建流（禁「接了流再静默丢弃」）
  openStream(cid: string, connId: string, channel: HttpStreamChannel): boolean;
  // 上行消息（POST 体；鉴权首消息与业务信封同一入口，由中枢判定）
  onUpstream(cid: string, text: string): void;
  // 下行流断开（对端断连 / 写失败 / 静态面停服）——中枢据此成对清会话
  onStreamClosed(connId: string): void;
}

// 传输载体接口：start/stop、sendTo、broadcast、closeConn + 回调四件
export interface TransportCarrier {
  // 载体标识（'ws' / 'tcp-http'——日志与错误归因用）
  readonly carrierKind: string;
  // 启动监听：resolve = 成功（实际端口 == cfg.port 已核验）；reject = 失败（bind 失败/
  // 端口被占/端口核验不符——manager 据此整体回滚，禁自动换口）
  start(cfg: CarrierConfig, events: CarrierEvents): Promise<void>;
  // 停止：关全部连接 + 释放监听端口 + 清簿记与定时器（幂等——重复调用零副作用）
  stop(): Promise<void>;
  // 定向发送（未鉴权/不存在连接回 false；发送失败即断连——快照语义兜底）
  sendTo(connId: string, text: string): Promise<boolean>;
  // 广播（回送达数；仅动态面载体有效，静态面回 0）
  broadcast(text: string): Promise<number>;
  // 关单连接（与整服 stop 分离）
  closeConn(connId: string): void;
  // 当前连接数（有界监控面）
  connectionCount(): number;
}
