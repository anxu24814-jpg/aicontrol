// TCP 手写 HTTP/1.1 静态托管 + SSE 动态面载体（官方无 HTTP 服务端 API，FAQ faqs-network-87
// 背书的手写形态；真机 WS 服务端起不来后的 SSE 备胎件）。
// 职责一句话：**只出字节、只收字节**——静态托管（rawfile/webui + SPA fallback）、传输配置
// 端点（/__cfg）、SSE 下行流（/events）与上行收件（/api/msg）的 HTTP 编解码。业务语义（会话
// 表/鉴权/下行投递）在 SseStreamHub，本件经 TransportCarrier 接口委托——两件互不 import。
// 连接三形态：①静态短连接（close-delimited，Connection: close）；②SSE 长连（GET
// /events?cid=…，chunked，keep-alive，不主动关；保活注释帧 20s 一发）；③上行短连接（POST
// /api/msg?cid=…，读 Content-Length 体，200 即弃）。
// 四约束（亲读 d.ts 取证）：
// ① 同一连接**串行写队列**——每连接一条 writeChain Promise 链，await 前一条 send 再发下一条，
//   防交错分片；
// ② **背压有界**——TCPSocketConnection 无 drain 事件、慢消费者积压内核缓冲不报错，应用层记
//   pendingBytes（**正在 send 未完成**的字节），超 TCP_PENDING_BYTES_LIMIT 主动 close（宪法
//   「数据有界」红线）。★ pendingBytes 必须在写链内、入 send 之前才累加——若在 enqueue 时就
//   预记整包字节，> 256KB 的静态资源（主 JS 446KB）会在首片执行前整包被判超限，一个字节都
//   发不出（WebUI 白屏）；
// ③ **粘包自解析**——on('message') 按到达块触发无消息边界，自缓冲 + '\r\n\r\n' **字节级**切头
//   （头按 ASCII 解，体按字节累积、整包完成后一次 UTF-8 解码——字符级解会在多字节汉字被切块
//   时产出替换符，POST 长中文消息必损）；
// ④ 大块静态按 TCP_CHUNK_BYTES 分片 send；SSE 帧同样分片（分片只切 HTTP chunk 段，SSE 帧的
//   `data:` 行在字节流上仍连续，客户端无感）。
// 响应定界 = 静态与上行 close-delimited（Connection: close + Content-Length）；SSE 长连用
// chunked（不许关连接，HTTP/1.1 只剩这一条合法定界）。
// FAQ 108 教训落码：server 级 connect/error 订阅**单次到底不 off 不重订**（停服重启 =
// close → listen，订阅原样复用）；close() since 20 只释放监听端口不关既有连接——stop 逐连接
// close 后再 server.close()。
// listen 端口核验：bind 失败系统会**随机分配端口不报错**（d.ts 明文），listen 成功后必
// getLocalAddress 核验实际端口 == 配置端口，不等即 close + 报错不开——禁自动换口。
// 内存防线：连接 Map 有界；每连接超时定时器与事件订阅在连接关闭时全清；POST 体有上限（超限
// 413 且不占内存）；SSE 保活由全局单定时器统一发；stop 全清簿记。
// 依赖纪律（零环）：只引 @kit 网络与系统能力 + 本域 TransportCarrier 接口，禁 import UI 件与
// 聊天域件；context 经 attachWebStaticContext 由组合根（EntryAbility.onCreate）注入。
import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  CarrierConfig,
  CarrierEvents,
  HttpStreamChannel,
  HttpStreamSink,
  TransportCarrier,
} from './TransportCarrier';

const TCP_LOG_DOMAIN: number = 0xD5A0;
const TCP_LOG_TAG: string = 'TcpHttpStatic';

// 连接数上限（静态短连接 + SSE 长连同占名额；流被拒时前端按断线退避重试）
export const TCP_MAX_CONNECTIONS: number = 8;
// 背压上限（字节，sendBufferSize 上限校准）——**在途未完成**字节超此值 = 慢消费者，主动断连
//（断言以源内常量现读为锚，禁抄值）
export const TCP_PENDING_BYTES_LIMIT: number = 262144;
// 大块静态分片（约束④）
export const TCP_CHUNK_BYTES: number = 16384;
// 请求头缓冲上限（字节级）：完整请求头远小于此，超限即恶意/非 HTTP 客户端
export const TCP_REQUEST_HEAD_LIMIT: number = 16384;
// 上行请求体上限（字节）：长文消息留足余量，把单请求内存钉在可控量级（宪法「数据有界」）
export const TCP_REQUEST_BODY_LIMIT: number = 4 * 1024 * 1024;
// 请求头读取超时：连上不发请求的占位连接到时断（成对 clearTimeout）。SSE 长连切流后清除此
// 定时器（长连不设读超时）
export const TCP_REQUEST_TIMEOUT_MS: number = 10000;
// SSE 保活间隔：注释帧 `: ping` 走同一写链——写失败即判死链清会话（本值只影响半开连接回收时延）
export const TCP_STREAM_PING_MS: number = 20000;
// 静态资源 rawfile 根（产物目录 = rawfile/webui/）
const TCP_RAWFILE_ROOT: string = 'webui';
// SPA 兜底资源（未命中路径回落 index.html——BrowserRouter 路由由前端接管）
const TCP_SPA_FALLBACK: string = '/index.html';
// GET 精确路由表（表驱动，扩路由只动此表与消费分支；/events 走独立的流分支不进表）
export const TCP_EXACT_ROUTES: string[] = ['/__cfg'];
// SSE 下行流路径（流分支判据，不进路由表）；上行收件路径（POST only）
export const TCP_SSE_PATH: string = '/events';
export const TCP_UPSTREAM_PATH: string = '/api/msg';

// ── 纯函数面（零 @kit 依赖，断言脚本剥 import 直跑；判据禁抄值——常量现读）──

// 请求行最小解析（请求头首行）：'GET /path HTTP/1.1' → 三段齐且方法大写字母、版本 HTTP/ 前缀
// 才过；畸形回 null（→400）
export interface HttpRequestLine {
  readonly method: string;
  readonly target: string;
  readonly version: string;
}

export function httpParseRequestLine(head: string): HttpRequestLine | null {
  const lineEnd: number = head.indexOf('\r\n');
  const firstLine: string = lineEnd >= 0 ? head.substring(0, lineEnd) : head;
  const parts: string[] = firstLine.split(' ');
  if (parts.length !== 3) {
    return null;
  }
  const method: string = parts[0];
  const target: string = parts[1];
  const version: string = parts[2];
  if (!/^[A-Z]+$/.test(method) || !target.startsWith('/') || !version.startsWith('HTTP/')) {
    return null;
  }
  const parsed: HttpRequestLine = { method: method, target: target, version: version };
  return parsed;
}

// 请求目标 → 路径段（剥查询串与锚点；不净化——穿越/控制字符仍归 httpSanitizeTarget 判）。
// 流/上行两路由要在净化前取 cid（查询串会被净化剥掉），故单独一档
export function httpTargetPath(target: string): string {
  let path: string = target;
  const qIdx: number = path.indexOf('?');
  if (qIdx >= 0) {
    path = path.substring(0, qIdx);
  }
  const hIdx: number = path.indexOf('#');
  if (hIdx >= 0) {
    path = path.substring(0, hIdx);
  }
  return path;
}

// 查询串单参提取（'?cid=abc&x=1' → key='cid' → 'abc'；缺失回 ''）。不做 URL 解码——cid 字符集
// 已由 sseCidValid 收窄到 [A-Za-z0-9_-]，无转义需求；其余参数本版无人消费
export function httpQueryParam(target: string, key: string): string {
  const qIdx: number = target.indexOf('?');
  if (qIdx < 0) {
    return '';
  }
  let query: string = target.substring(qIdx + 1);
  const hIdx: number = query.indexOf('#');
  if (hIdx >= 0) {
    query = query.substring(0, hIdx);
  }
  const pairs: string[] = query.split('&');
  for (const pair of pairs) {
    const eq: number = pair.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    if (pair.substring(0, eq) === key) {
      return pair.substring(eq + 1);
    }
  }
  return '';
}

// 请求头字段读取（大小写不敏感；缺失回 ''）。head 不含尾部空行（'\r\n\r\n' 已被切掉）；
// 传入名先归一为小写再比——调用方写 'Content-Length' 或 'content-length' 都可
export function httpHeaderValue(head: string, lowerName: string): string {
  const key: string = lowerName.toLowerCase();
  const lines: string[] = head.split('\r\n');
  for (let i = 1; i < lines.length; i++) {
    const line: string = lines[i];
    const colon: number = line.indexOf(':');
    if (colon <= 0) {
      continue;
    }
    const name: string = line.substring(0, colon).trim().toLowerCase();
    if (name === key) {
      return line.substring(colon + 1).trim();
    }
  }
  return '';
}

// Content-Length 解析（缺失或非法回 -1——POST 无长度无法定界，按 411 拒）
export function httpContentLength(head: string): number {
  const raw: string = httpHeaderValue(head, 'content-length');
  if (raw === '' || !/^[0-9]+$/.test(raw)) {
    return -1;
  }
  const value: number = Number.parseInt(raw, 10);
  if (!Number.isInteger(value) || value < 0) {
    return -1;
  }
  return value;
}

// 字节级切头：找 '\r\n\r\n'（13,10,13,10）的起始下标；未找到回 -1。逐字节扫描而非字符解码——
// 到达块可能把多字节字符切两半，先解码再找分隔符会漏
export function httpFindHeadEnd(bytes: Uint8Array): number {
  for (let i = 0; i + 3 < bytes.byteLength; i++) {
    if (bytes[i] === 13 && bytes[i + 1] === 10 && bytes[i + 2] === 13 && bytes[i + 3] === 10) {
      return i;
    }
  }
  return -1;
}

// 两段字节拼接（切头后的余量转体；ArrayBuffer.slice 复制避免共享底层缓冲的越界写）
export function bytesConcat(a: Uint8Array, b: Uint8Array): Uint8Array {
  if (a.byteLength === 0) {
    return b;
  }
  if (b.byteLength === 0) {
    return a;
  }
  const out: Uint8Array = new Uint8Array(a.byteLength + b.byteLength);
  out.set(a, 0);
  out.set(b, a.byteLength);
  return out;
}

// SSE 数据帧组装：一条业务信封 = 一帧 `data: <payload>\n\n`。payload 含裸 CR/LF 时回 ''（拒发）
// ——客户端只认单行 data，裸换行会把一帧截成两帧（前半截成脏 JSON，后半截成无字段帧）。
// JSON 序列化天然把正文换行转义成 \n 两字符，故正常信封恒单行
export function sseFrameOf(payload: string): string {
  if (payload.includes('\n') || payload.includes('\r')) {
    return '';
  }
  return 'data: ' + payload + '\n\n';
}

// SSE 保活注释帧（注释行以 ':' 开头，客户端解析器直接跳过；只用于让 TCP 有字节可写以探死链）
export function ssePingFrame(): string {
  return ': ping\n\n';
}

// 请求目标净化（路径穿越防 '../'）：剥查询串/锚点、拒 '..' 段、拒控制字符与反斜杠、根路径
// 落 SPA 首页；非法回 ''（→400/404 由调用方定）
export function httpSanitizeTarget(target: string): string {
  let path: string = target;
  const qIdx: number = path.indexOf('?');
  if (qIdx >= 0) {
    path = path.substring(0, qIdx);
  }
  const hIdx: number = path.indexOf('#');
  if (hIdx >= 0) {
    path = path.substring(0, hIdx);
  }
  if (path === '' || !path.startsWith('/')) {
    return '';
  }
  if (path.includes('\\') || path.includes('..')) {
    return '';
  }
  // 控制字符拒收（charset 白名单的粗闸——V1 静态面只应出现可见 ASCII 资源名）
  if (/[\x00-\x1f\x7f]/.test(path)) {
    return '';
  }
  if (path === '/') {
    return TCP_SPA_FALLBACK;
  }
  return path;
}

// 扩展名 → Content-Type（未命中回通用二进制流）
export function httpContentTypeFor(path: string): string {
  const dotIdx: number = path.lastIndexOf('.');
  const ext: string = dotIdx >= 0 ? path.substring(dotIdx + 1).toLowerCase() : '';
  if (ext === 'html' || ext === 'htm') {
    return 'text/html; charset=utf-8';
  }
  if (ext === 'js' || ext === 'mjs') {
    return 'text/javascript; charset=utf-8';
  }
  if (ext === 'css') {
    return 'text/css; charset=utf-8';
  }
  if (ext === 'json') {
    return 'application/json; charset=utf-8';
  }
  if (ext === 'svg') {
    return 'image/svg+xml';
  }
  if (ext === 'png') {
    return 'image/png';
  }
  if (ext === 'jpg' || ext === 'jpeg') {
    return 'image/jpeg';
  }
  if (ext === 'gif') {
    return 'image/gif';
  }
  if (ext === 'webp') {
    return 'image/webp';
  }
  if (ext === 'ico') {
    return 'image/x-icon';
  }
  if (ext === 'wasm') {
    return 'application/wasm';
  }
  if (ext === 'txt') {
    return 'text/plain; charset=utf-8';
  }
  if (ext === 'map') {
    return 'application/json; charset=utf-8';
  }
  if (ext === 'woff2') {
    return 'font/woff2';
  }
  return 'application/octet-stream';
}

// 状态行 reason 短语（本件只用到 200/400/404/405/408/411/413/500；未知回空串由调用方兜底）
export function httpStatusReason(status: number): string {
  if (status === 200) {
    return 'OK';
  }
  if (status === 400) {
    return 'Bad Request';
  }
  if (status === 404) {
    return 'Not Found';
  }
  if (status === 405) {
    return 'Method Not Allowed';
  }
  if (status === 408) {
    return 'Request Timeout';
  }
  if (status === 411) {
    return 'Length Required';
  }
  if (status === 413) {
    return 'Payload Too Large';
  }
  if (status === 500) {
    return 'Internal Server Error';
  }
  if (status === 503) {
    return 'Service Unavailable';
  }
  return '';
}

// close-delimited 响应头组装（Content-Length + Connection: close，无 Transfer-Encoding/chunked）；
// 405 附 Allow: GET
export function httpBuildResponseHead(status: number, contentType: string, length: number): string {
  const reason: string = httpStatusReason(status);
  let head: string = 'HTTP/1.1 ' + status.toString() + ' ' + (reason !== '' ? reason : 'Status') + '\r\n' +
    'Content-Type: ' + contentType + '\r\n' +
    'Content-Length: ' + length.toString() + '\r\n';
  if (status === 405) {
    head += 'Allow: GET\r\n';
  }
  head += 'Connection: close\r\n\r\n';
  return head;
}

// SSE 流响应头（chunked + keep-alive；Cache-Control/no-cache 防浏览器缓存事件流，
// X-Accel-Buffering 对反向代理关缓冲——本场景无代理，留作部署变体兜底）
export function httpBuildStreamHead(): string {
  return 'HTTP/1.1 200 OK\r\n' +
    'Content-Type: text/event-stream; charset=utf-8\r\n' +
    'Cache-Control: no-cache\r\n' +
    'Connection: keep-alive\r\n' +
    'Transfer-Encoding: chunked\r\n' +
    'X-Accel-Buffering: no\r\n\r\n';
}

// chunked 分段头（十六进制字节数 + CRLF；断言钉「长度按字节不按字符」）
export function httpChunkHeadOf(byteLength: number): string {
  return byteLength.toString(16) + '\r\n';
}

// 背压判定（约束②判据单源：关系钉——超限才真，恰界不真；上限值以 TCP_PENDING_BYTES_LIMIT
// 现读为准，断言禁抄 262144）
export function tcpPendingOverflows(pendingBytes: number): boolean {
  return pendingBytes > TCP_PENDING_BYTES_LIMIT;
}

// 请求路由决策（纯函数单源：请求行解析 + GET-only + 路径净化三闸在此收口，dispatchRequest
// 只按决策执行副作用）：200 = 可服务（path 已净化，查询串已剥、根路径落 SPA 首页）/
// 405 = 非 GET / 400 = 请求行畸形 / 404 = 路径非法（穿越/控制字符——按不存在处理不探因）
export interface HttpRouteDecision {
  readonly status: number;
  readonly path: string;
}

export function httpRouteRequestLine(head: string): HttpRouteDecision {
  const parsed: HttpRequestLine | null = httpParseRequestLine(head);
  if (parsed === null) {
    const bad: HttpRouteDecision = { status: 400, path: '' };
    return bad;
  }
  if (parsed.method !== 'GET') {
    const rejected: HttpRouteDecision = { status: 405, path: '' };
    return rejected;
  }
  const path: string = httpSanitizeTarget(parsed.target);
  if (path === '') {
    const missing: HttpRouteDecision = { status: 404, path: '' };
    return missing;
  }
  const ok: HttpRouteDecision = { status: 200, path: path };
  return ok;
}

// ── 上下文注入（组合根 EntryAbility.onCreate 调用；ShellScript.ets 同款先例）──

let webStaticContext: common.Context | null = null;

export function attachWebStaticContext(ctx: common.Context): void {
  webStaticContext = ctx;
}

// ── 连接簿记（有界：上限 TCP_MAX_CONNECTIONS；connId 自合成 'tcp-<序号>'——短连接身份
// 仅供日志与回调对齐；SSE 长连另合成 'ip:port' 作会话键，见 openSseStream）──

interface TcpConnEntry {
  readonly conn: socket.TCPSocketConnection;
  readonly connId: string;
  // 未切头前的字节累积（字节级——多字节字符可能被到达块切两半）
  headBytes: Uint8Array;
  headDone: boolean;
  pendingBytes: number;
  writeChain: Promise<void>;
  timeoutId: number;
  closed: boolean;
  // SSE 长连态（'' / false = 非流连接）
  streamCid: string;
  streaming: boolean;
  // 流会话键（= 中枢 openStream 登记的 'ip:port'，'' = 非流连接）。收尾回调必须用本字段，
  // 用 connId('tcp-N') 会在中枢/无头/直播三件键不命中而漏释放（详见 cleanupConnection 注释）
  sessionConnId: string;
  // 上行请求体累积（bodyNeed ≥ 0 表示正在等体；-1 = 非上行请求）
  bodyNeed: number;
  bodyChunks: Uint8Array[];
  // 上行请求的 cid（体读完才上抛；解析时先存）
  upstreamCid: string;
}

// SSE 下行写入口实现（中枢持它往连接里塞信封；socket 与分片细节全在本件）
class SseConnChannel implements HttpStreamChannel {
  private readonly carrier: TcpHttpStaticCarrier;
  private readonly entry: TcpConnEntry;

  constructor(carrier: TcpHttpStaticCarrier, entry: TcpConnEntry) {
    this.carrier = carrier;
    this.entry = entry;
  }

  write(payload: string): boolean {
    return this.carrier.writeSsePayload(this.entry, payload);
  }

  close(): void {
    this.carrier.closeStream(this.entry);
  }
}

export class TcpHttpStaticCarrier implements TransportCarrier {
  readonly carrierKind: string = 'tcp-http';
  // server 对象进程内惰性构造一次、订阅单次到底（FAQ 108）；close→listen 重启复用同一订阅
  private server: socket.TCPSocketServer | null = null;
  private subscribed: boolean = false;
  private conns: Map<string, TcpConnEntry> = new Map<string, TcpConnEntry>();
  private nextConnSeq: number = 0;
  private events: CarrierEvents | null = null;
  private running: boolean = false;
  private boundPort: number = 0;
  private wsPortHint: number = 0;
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
  private encoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  // SSE 下行语义委托面（manager 注入 sseStreamHub；null = 流路由回 503）
  private streamSink: HttpStreamSink | null = null;
  // 保活全局单定时器（不每连接建——成对 clearInterval 在 stop）
  private streamPingTimerId: number = 0;

  // 流接入面注入（manager.start 装配；null = 摘除，流路由回 503）
  setStreamSink(sink: HttpStreamSink | null): void {
    this.streamSink = sink;
  }

  async start(cfg: CarrierConfig, events: CarrierEvents): Promise<void> {
    if (webStaticContext === null) {
      throw new Error('Web 静态资源上下文未注入（须 EntryAbility 调 attachWebStaticContext）');
    }
    this.events = events;
    this.wsPortHint = cfg.wsPortHint;
    if (this.server === null) {
      this.server = socket.constructTCPSocketServerInstance();
    }
    this.ensureSubscribed();
    try {
      const addr: socket.NetAddress = { address: cfg.bindAddress, port: cfg.port };
      await this.server.listen(addr);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      throw new Error('TCP 监听失败，地址 ' + cfg.bindAddress + ':' + cfg.port + '，错误码 ' +
        err.code + '，原因 ' + err.message);
    }
    // ★ 端口核验（裁定 9）：bind 失败系统随机分配端口不报错——实际端口 ≠ 配置端口即
    // close + 抛错，禁换口直开
    let actualPort: number = 0;
    try {
      const local: socket.NetAddress = await this.server.getLocalAddress();
      actualPort = local.port ?? 0;
    } catch (e) {
      await this.releaseListener();
      throw new Error('TCP 端口核验失败（getLocalAddress 异常：' + (e as Error).message + '）');
    }
    if (actualPort !== cfg.port) {
      await this.releaseListener();
      throw new Error('TCP 端口核验不符，配置 ' + cfg.port + ' 实际 ' + actualPort +
        '，疑似被占用后随机分配，请换端口');
    }
    this.boundPort = actualPort;
    this.running = true;
    this.startStreamPing();
    hilog.info(TCP_LOG_DOMAIN, TCP_LOG_TAG, '静态面监听就绪 %{public}s:%{public}d',
      cfg.bindAddress, actualPort);
  }

  // server 级订阅（单次到底——FAQ 108：off 后重 on 在未重新 listen 时不生效，正解即不 off）
  private ensureSubscribed(): void {
    if (this.subscribed || this.server === null) {
      return;
    }
    this.server.on('connect', (conn: socket.TCPSocketConnection): void => {
      this.acceptConnection(conn);
    });
    this.server.on('error', (err: BusinessError): void => {
      hilog.error(TCP_LOG_DOMAIN, TCP_LOG_TAG, 'server error %{public}d：%{public}s',
        err.code, err.message);
      if (this.events !== null) {
        this.events.onError(err.code, err.message);
      }
    });
    this.subscribed = true;
  }

  private acceptConnection(conn: socket.TCPSocketConnection): void {
    if (!this.running) {
      // 停服瞬间已 accept 的连接不能悬挂到对端超时——尽力 close 后拒
      conn.close().catch((e: Object): void => {
        hilog.warn(TCP_LOG_DOMAIN, TCP_LOG_TAG, '停服期拒连 close 失败（%{public}s）',
          (e as Error).message);
      });
      return;
    }
    // 有界闸：超上限直接拒（静态短连接先到先得；SSE 长连同样占名额）
    if (this.conns.size >= TCP_MAX_CONNECTIONS) {
      hilog.warn(TCP_LOG_DOMAIN, TCP_LOG_TAG, '连接数达上限 %{public}d，拒新连接',
        TCP_MAX_CONNECTIONS);
      conn.close().catch((e: Object): void => {
        hilog.warn(TCP_LOG_DOMAIN, TCP_LOG_TAG, '拒连 close 失败（%{public}s）',
          (e as Error).message);
      });
      return;
    }
    this.nextConnSeq++;
    const connId: string = 'tcp-' + this.nextConnSeq.toString();
    const entry: TcpConnEntry = {
      conn: conn,
      connId: connId,
      headBytes: new Uint8Array(0),
      headDone: false,
      pendingBytes: 0,
      writeChain: Promise.resolve(),
      timeoutId: 0,
      closed: false,
      streamCid: '',
      streaming: false,
      sessionConnId: '',
      bodyNeed: -1,
      bodyChunks: [],
      upstreamCid: ''
    };
    // 读请求头超时（~10s）：到时未凑齐完整请求头即断（占位连接不占着有界名额）
    entry.timeoutId = setTimeout((): void => {
      hilog.info(TCP_LOG_DOMAIN, TCP_LOG_TAG, '请求头超时断连 %{public}s', connId);
      this.cleanupConnection(connId, 408);
    }, TCP_REQUEST_TIMEOUT_MS);
    this.conns.set(connId, entry);
    conn.on('message', (info: socket.SocketMessageInfo): void => {
      this.onConnMessage(connId, info.message);
    });
    conn.on('close', (): void => {
      this.cleanupConnection(connId, 0);
    });
    conn.on('error', (err: BusinessError): void => {
      hilog.warn(TCP_LOG_DOMAIN, TCP_LOG_TAG, '连接 %{public}s 异常 %{public}d',
        connId, err.code);
      this.cleanupConnection(connId, 0);
    });
  }

  // 粘包自解析（约束③，字节级）：未切头 → 累积找 '\r\n\r\n'；已切头且在上行收体 → 续体；
  // 其余（静态已响应 / SSE 长连）忽略后续到达
  private onConnMessage(connId: string, data: ArrayBuffer): void {
    const entry: TcpConnEntry | undefined = this.conns.get(connId);
    if (entry === undefined || entry.closed) {
      return;
    }
    const chunk: Uint8Array = new Uint8Array(data);
    if (!entry.headDone) {
      entry.headBytes = bytesConcat(entry.headBytes, chunk);
      const headEnd: number = httpFindHeadEnd(entry.headBytes);
      if (headEnd < 0) {
        // ★ 超限闸只能在「找不到头尾分隔符」的支里判——到达块可能把请求头与首段请求体合并
        // 投递（一次 read 可跨 TCP 段），此时 headBytes 里已含体字节、长度天然超过
        // TCP_REQUEST_HEAD_LIMIT，先判长度会把合法的 POST 长消息误杀成 400。体量上界由
        // TCP_REQUEST_BODY_LIMIT 在 routeRequest 与 appendBody 两处独立把关
        if (entry.headBytes.byteLength > TCP_REQUEST_HEAD_LIMIT) {
          this.cleanupConnection(connId, 400);
        }
        return;
      }
      entry.headDone = true;
      clearTimeout(entry.timeoutId);
      entry.timeoutId = 0;
      let head: string = '';
      try {
        head = this.decoder.decodeToString(entry.headBytes.subarray(0, headEnd));
      } catch (e) {
        this.cleanupConnection(connId, 400);
        return;
      }
      const rest: Uint8Array = entry.headBytes.slice(headEnd + 4);
      entry.headBytes = new Uint8Array(0);
      this.routeRequest(entry, head, rest);
      return;
    }
    if (entry.bodyNeed >= 0) {
      this.appendBody(entry, chunk);
    }
  }

  // 请求分流（三形态：SSE 流 / 上行 POST / 静态 GET）
  private routeRequest(entry: TcpConnEntry, head: string, rest: Uint8Array): void {
    const parsed: HttpRequestLine | null = httpParseRequestLine(head);
    if (parsed === null) {
      this.respondAndClose(entry, 400, 'text/plain; charset=utf-8', 'bad request');
      return;
    }
    const path: string = httpTargetPath(parsed.target);
    if (parsed.method === 'POST') {
      if (path !== TCP_UPSTREAM_PATH) {
        this.respondAndClose(entry, 405, 'text/plain; charset=utf-8', 'GET only');
        return;
      }
      const length: number = httpContentLength(head);
      if (length < 0) {
        this.respondAndClose(entry, 411, 'text/plain; charset=utf-8', 'length required');
        return;
      }
      if (length > TCP_REQUEST_BODY_LIMIT) {
        this.respondAndClose(entry, 413, 'text/plain; charset=utf-8', 'payload too large');
        return;
      }
      entry.upstreamCid = httpQueryParam(parsed.target, 'cid');
      entry.bodyNeed = length;
      entry.bodyChunks = [];
      if (rest.byteLength > 0) {
        this.appendBody(entry, rest);
      }
      if (entry.bodyNeed === 0 && !entry.closed) {
        this.dispatchUpstream(entry);
      }
      return;
    }
    if (path === TCP_SSE_PATH) {
      // 流入口只认 GET（头注释契约）——POST 已在上面分支按上行收件判掉，其余方法若放行会
      // 白占一个会话名额并留下一条永不鉴权的流
      if (parsed.method !== 'GET') {
        this.respondAndClose(entry, 405, 'text/plain; charset=utf-8', 'GET only');
        return;
      }
      this.openSseStream(entry, parsed.target);
      return;
    }
    // 路由决策纯函数单源（解析 + GET-only + 净化三闸收口），本方法只执行副作用
    const decision: HttpRouteDecision = httpRouteRequestLine(head);
    if (decision.status !== 200) {
      const body: string = decision.status === 405 ? 'GET only' :
        (decision.status === 400 ? 'bad request' : 'not found');
      this.respondAndClose(entry, decision.status, 'text/plain; charset=utf-8', body);
      return;
    }
    const safePath: string = decision.path;
    // GET 精确路由表（exact 段；表驱动——扩路由只动 TCP_EXACT_ROUTES 与本分支）
    if (TCP_EXACT_ROUTES.includes(safePath)) {
      const body: string = '{"transport":"sse","wsPort":' + this.wsPortHint.toString() + '}';
      this.respondAndClose(entry, 200, 'application/json; charset=utf-8', body);
      return;
    }
    // 静态面异步读盘的失败兜底（读盘异常自身已内部消化，此处只兜意外路径——P0-1 禁静默）
    this.serveStatic(entry, safePath).catch((e: Object): void => {
      hilog.error(TCP_LOG_DOMAIN, TCP_LOG_TAG, '静态响应意外失败（%{public}s）',
        (e as Error).message);
      this.respondAndClose(entry, 500, 'text/plain; charset=utf-8', 'internal error');
    });
  }

  // 上行体累积（有界：超 TCP_REQUEST_BODY_LIMIT 立即 413 断连，不继续吃内存）。只取体所需
  // 字节——多出来的部分（同连接流水化下一请求）本版不处理，越界即畸形
  private appendBody(entry: TcpConnEntry, chunk: Uint8Array): void {
    if (entry.bodyNeed < 0 || entry.closed) {
      return;
    }
    const need: number = entry.bodyNeed;
    if (chunk.byteLength > need) {
      this.respondAndClose(entry, 413, 'text/plain; charset=utf-8', 'payload too large');
      return;
    }
    entry.bodyChunks.push(chunk);
    entry.bodyNeed = need - chunk.byteLength;
    if (entry.bodyNeed > 0) {
      return;
    }
    this.dispatchUpstream(entry);
  }

  // 上行体读完 → 先回 200（客户端不等体处理结果，回执走 SSE 下行）→ 再上抛中枢
  private dispatchUpstream(entry: TcpConnEntry): void {
    let text: string = '';
    try {
      const body: Uint8Array = this.joinBody(entry);
      text = this.decoder.decodeToString(body);
    } catch (e) {
      this.respondAndClose(entry, 400, 'text/plain; charset=utf-8', 'bad request');
      return;
    }
    const cid: string = entry.upstreamCid;
    entry.bodyNeed = -1;
    entry.bodyChunks = [];
    this.respondAndClose(entry, 200, 'application/json; charset=utf-8', '{"ok":true}');
    const sink: HttpStreamSink | null = this.streamSink;
    if (sink !== null && cid !== '') {
      sink.onUpstream(cid, text);
    }
  }

  private joinBody(entry: TcpConnEntry): Uint8Array {
    let total: number = 0;
    for (const chunk of entry.bodyChunks) {
      total += chunk.byteLength;
    }
    const out: Uint8Array = new Uint8Array(total);
    let offset: number = 0;
    for (const chunk of entry.bodyChunks) {
      out.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return out;
  }

  // SSE 流建立：取对端 'ip:port' 作会话键（鉴权按 IP 口径复用 WebAuthValidator 的解析）→
  // 写流响应头（裸写）→ 交中枢登记（拒收则关流）→ 切流态（清读超时、停收后续字节）
  private openSseStream(entry: TcpConnEntry, target: string): void {
    const cid: string = httpQueryParam(target, 'cid');
    const sink: HttpStreamSink | null = this.streamSink;
    if (sink === null) {
      this.respondAndClose(entry, 503, 'text/plain; charset=utf-8', 'stream unavailable');
      return;
    }
    this.peerKeyOf(entry).then((peerKey: string): void => {
      if (entry.closed) {
        return;
      }
      // 顺序硬约束：**先写流响应头与 retry 提示，再交中枢登记**——中枢登记后可能立刻下发
      // auth_required/首帧，那些数据帧必须排在 200 响应头之后（否则浏览器按畸形响应丢弃）
      entry.streamCid = cid;
      entry.streaming = true;
      // 会话键落档：收尾回调（cleanupConnection → onStreamClosed/onDisconnect）用它，
      // 与本处 openStream 的实参同一值（成对口径单源）
      entry.sessionConnId = peerKey;
      // ★ 响应头走**裸写**（enqueueFrame，不加 chunked 段头）——状态行/头字段不是 chunk 体的
      // 一部分，若被 `httpChunkHeadOf` 包一层，浏览器读到的第一条就是非法状态行，整条流作废
      this.enqueueFrame(entry, this.encoder.encodeInto(httpBuildStreamHead()));
      this.enqueueStreamSegment(entry, this.encoder.encodeInto('retry: 3000\n\n'));
      const channel: HttpStreamChannel = new SseConnChannel(this, entry);
      if (!sink.openStream(cid, peerKey, channel)) {
        // 拒收（名额满 / cid 非法 / 服务未起）：头已发，只能走关流（前端见断流按退避重连）
        hilog.warn(TCP_LOG_DOMAIN, TCP_LOG_TAG, '流登记被拒，关流（%{public}s）', cid);
        this.closeStream(entry);
      }
    }).catch((e: Object): void => {
      hilog.warn(TCP_LOG_DOMAIN, TCP_LOG_TAG, '流建立取对端地址失败（%{public}s）',
        (e as Error).message);
      this.respondAndClose(entry, 500, 'text/plain; charset=utf-8', 'internal error');
    });
  }

  // 对端 'ip:port'（鉴权/限速按 IP 口径的键；取不到回 '0.0.0.0:0'——鉴权侧按非回环处理，
  // 即仅本机档下会被拒，方向安全）
  private async peerKeyOf(entry: TcpConnEntry): Promise<string> {
    try {
      const remote: socket.NetAddress = await entry.conn.getRemoteAddress();
      const host: string = remote.address ?? '0.0.0.0';
      const port: number = remote.port ?? 0;
      return host + ':' + port.toString();
    } catch (e) {
      return '0.0.0.0:0';
    }
  }

  // 中枢下行写入口（SseConnChannel.write 的实现）：信封 → SSE 帧 → chunked 分段入写链
  writeSsePayload(entry: TcpConnEntry, payload: string): boolean {
    if (entry.closed || !entry.streaming) {
      return false;
    }
    const frame: string = sseFrameOf(payload);
    if (frame === '') {
      hilog.warn(TCP_LOG_DOMAIN, TCP_LOG_TAG, '下行信封含裸换行拒发（%{public}d 字符）',
        payload.length);
      return false;
    }
    this.enqueueStreamSegment(entry, this.encoder.encodeInto(frame));
    return true;
  }

  // 分段入写链（约束①④）：一段 ≤ TCP_CHUNK_BYTES，各段独立 chunked 头——字节流连续，
  // 客户端看到的是一整条 SSE 帧；在途积分按段记（背压闸判据不变）
  private enqueueStreamSegment(entry: TcpConnEntry, bytes: Uint8Array): void {
    if (entry.closed) {
      return;
    }
    const total: number = bytes.byteLength;
    let offset: number = 0;
    while (offset < total) {
      const end: number = Math.min(offset + TCP_CHUNK_BYTES, total);
      const piece: Uint8Array = bytes.slice(offset, end);
      const headBytes: Uint8Array = this.encoder.encodeInto(httpChunkHeadOf(piece.byteLength));
      const tailBytes: Uint8Array = this.encoder.encodeInto('\r\n');
      const framed: Uint8Array = bytesConcat(bytesConcat(headBytes, piece), tailBytes);
      this.enqueueFrame(entry, framed);
      offset = end;
    }
  }

  private enqueueFrame(entry: TcpConnEntry, framed: Uint8Array): void {
    const size: number = framed.byteLength;
    const buffer: ArrayBuffer = framed.buffer.slice(framed.byteOffset,
      framed.byteOffset + framed.byteLength);
    entry.writeChain = entry.writeChain.then(async (): Promise<void> => {
      if (entry.closed) {
        return;
      }
      // 背压闸（约束②）：只判「本段之前仍在途」的字节
      if (tcpPendingOverflows(entry.pendingBytes)) {
        throw new Error('pending ' + entry.pendingBytes.toString() + 'B 超限断连');
      }
      entry.pendingBytes += size;
      try {
        const opts: socket.TCPSendOptions = { data: buffer };
        await entry.conn.send(opts);
      } finally {
        entry.pendingBytes -= size;
      }
    }).catch((e: Object): void => {
      hilog.warn(TCP_LOG_DOMAIN, TCP_LOG_TAG, '连接 %{public}s 写链中断（%{public}s）',
        entry.connId, (e as Error).message);
      this.cleanupConnection(entry.connId, 0);
    });
  }

  // 关流（中枢 closeConn/停服/写失败三路都到此处）：尽力发终止片 0\r\n\r\n 再断（等写链
  // 排空再关——立刻 close 会把终止片吞掉，客户端只能按异常断线重连）；幂等
  closeStream(entry: TcpConnEntry): void {
    if (entry.closed) {
      return;
    }
    if (entry.streaming) {
      this.enqueueFrame(entry, this.encoder.encodeInto('0\r\n\r\n'));
      entry.writeChain.then((): Promise<void> => {
        return this.cleanupConnection(entry.connId, 0);
      }).catch((): void => {
        this.cleanupConnection(entry.connId, 0);
      });
      return;
    }
    this.cleanupConnection(entry.connId, 0);
  }

  // SSE 保活（全局单定时器）：注释帧走同一写链——写失败即清会话（半开连接回收）
  private startStreamPing(): void {
    if (this.streamPingTimerId !== 0) {
      return;
    }
    this.streamPingTimerId = setInterval((): void => {
      if (!this.running) {
        return;
      }
      const streams: TcpConnEntry[] = [];
      this.conns.forEach((entry: TcpConnEntry): void => {
        if (entry.streaming && !entry.closed) {
          streams.push(entry);
        }
      });
      for (const entry of streams) {
        this.enqueueStreamSegment(entry, this.encoder.encodeInto(ssePingFrame()));
      }
    }, TCP_STREAM_PING_MS);
  }

  // 静态托管：rawfile/webui 命中 → 200；未命中 → SPA fallback index.html；再未命中 → 404。
  // Content-Type 按**实际命中文件**取（回退 index.html 时按 html，不按原请求扩展名）
  private async serveStatic(entry: TcpConnEntry, path: string): Promise<void> {
    const ctx: common.Context | null = webStaticContext;
    if (ctx === null || entry.closed) {
      return;
    }
    let bytes: Uint8Array | null = null;
    let servedPath: string = path;
    try {
      bytes = await ctx.resourceManager.getRawFileContent(TCP_RAWFILE_ROOT + path);
    } catch (e) {
      bytes = null;
    }
    if (bytes === null && path !== TCP_SPA_FALLBACK) {
      try {
        bytes = await ctx.resourceManager.getRawFileContent(TCP_RAWFILE_ROOT + TCP_SPA_FALLBACK);
        servedPath = TCP_SPA_FALLBACK;
      } catch (e) {
        bytes = null;
      }
    }
    if (bytes === null) {
      this.respondAndClose(entry, 404, 'text/plain; charset=utf-8', 'not found');
      return;
    }
    this.respondAndClose(entry, 200, httpContentTypeFor(servedPath), bytes);
  }

  // 响应组装与串行分片发送（约束①④ + close-delimited）
  private respondAndClose(entry: TcpConnEntry, status: number, contentType: string,
    body: string | Uint8Array): void {
    if (entry.closed) {
      return;
    }
    const bodyBytes: Uint8Array = typeof body === 'string' ? this.encoder.encodeInto(body) : body;
    const head: string = httpBuildResponseHead(status, contentType, bodyBytes.byteLength);
    const headBytes: Uint8Array = this.encoder.encodeInto(head);
    const full: Uint8Array = new Uint8Array(headBytes.byteLength + bodyBytes.byteLength);
    full.set(headBytes, 0);
    full.set(bodyBytes, headBytes.byteLength);
    // 分片串行入链：每片 await 前一片完成才发（约束①）；在途积压（仅 send 未完成字节）
    // 超限即断（约束②——记账在写链内，不预记整包）
    for (let offset = 0; offset < full.byteLength; offset += TCP_CHUNK_BYTES) {
      const end: number = Math.min(offset + TCP_CHUNK_BYTES, full.byteLength);
      const view: Uint8Array = full.subarray(offset, end);
      const chunk: ArrayBuffer = view.buffer.slice(view.byteOffset, view.byteOffset + view.byteLength);
      this.enqueueChunk(entry, chunk);
    }
    // 响应排空后主动 close（close-delimited；不等客户端）
    entry.writeChain.then((): Promise<void> => {
      return this.cleanupConnection(entry.connId, 0);
    }).catch((): void => {
      this.cleanupConnection(entry.connId, 0);
    });
  }

  private enqueueChunk(entry: TcpConnEntry, chunk: ArrayBuffer): void {
    if (entry.closed) {
      return;
    }
    const size: number = chunk.byteLength;
    entry.writeChain = entry.writeChain.then(async (): Promise<void> => {
      if (entry.closed) {
        return;
      }
      // 背压闸（约束②）：只判「本片之前仍在途」的字节——串行链上一片 await 完成才轮到本片，
      // 因此积压恒 ≤ 单片刻度；整包 > 上限的静态资源按片流过，不被整包预记账误杀
      if (tcpPendingOverflows(entry.pendingBytes)) {
        throw new Error('pending ' + entry.pendingBytes.toString() + 'B 超限断连');
      }
      entry.pendingBytes += size;
      try {
        const opts: socket.TCPSendOptions = { data: chunk };
        await entry.conn.send(opts);
      } finally {
        entry.pendingBytes -= size;
      }
    }).catch((e: Object): void => {
      hilog.warn(TCP_LOG_DOMAIN, TCP_LOG_TAG, '连接 %{public}s 写链中断（%{public}s）',
        entry.connId, (e as Error).message);
      this.cleanupConnection(entry.connId, 0);
    });
  }

  // 连接收尾（成对释放：超时定时器 clearTimeout + 连接级事件 off + close + 簿记删除；幂等）。
  // SSE 长连在此向中枢回调 onStreamClosed（会话成对释放的唯一出口）
  private async cleanupConnection(connId: string, statusWhenOpen: number): Promise<void> {
    const entry: TcpConnEntry | undefined = this.conns.get(connId);
    if (entry === undefined) {
      return;
    }
    this.conns.delete(connId);
    if (entry.closed) {
      return;
    }
    entry.closed = true;
    clearTimeout(entry.timeoutId);
    entry.timeoutId = 0;
    entry.conn.off('message');
    entry.conn.off('close');
    entry.conn.off('error');
    if (statusWhenOpen > 0 && !entry.headDone) {
      // 还没回过响应的占位/异常连接：尽力补一条极短响应再断（408/400 路径）
      try {
        const opts: socket.TCPSendOptions = {
          data: this.httpAbortBody(statusWhenOpen)
        };
        await entry.conn.send(opts);
      } catch (e) {
        // 对端已断即静默（连接将 close，不追账）
      }
    }
    try {
      await entry.conn.close();
    } catch (e) {
      // 幂等收尾：已断连接 close 报错不追
    }
    // ★ 收尾回调必须用**会话键**——中枢（SseStreamHub.byConn）、无头宿主（sessions[].conns）、
    // 直播泵（clients）三件的簿记键都是 openStream 登记的 'ip:port'，而本件 entry.connId 是
    // 'tcp-N'。传 connId 会三件键不命中 ⇒ SSE 会话名额（16）+ 直播客户端与 wire 租约（32）+
    // 无头会话（16）**永不释放**（刷新页面 16 次后 openStream 恒 false）。静态短连接无会话键
    //（streaming = false）回落 connId，等效零动作
    const sessionKey: string = entry.streaming ? entry.sessionConnId : connId;
    const sink: HttpStreamSink | null = this.streamSink;
    if (sink !== null) {
      sink.onStreamClosed(sessionKey);
    }
    if (this.events !== null) {
      this.events.onDisconnect(sessionKey);
    }
  }

  // 占位连接的极短补发体（不进 writeChain——本连接已判定终结，一次尽力发送即可）
  private httpAbortBody(status: number): string {
    return httpBuildResponseHead(status, 'text/plain; charset=utf-8', 0);
  }

  // 释放监听端口（close 只停 listen 不关既有连接——既有连接由 stop 逐个清）
  private async releaseListener(): Promise<void> {
    if (this.server !== null) {
      try {
        await this.server.close();
      } catch (e) {
        hilog.warn(TCP_LOG_DOMAIN, TCP_LOG_TAG, 'server close 异常（%{public}s）',
          (e as Error).message);
      }
    }
    this.running = false;
  }

  async stop(): Promise<void> {
    if (this.streamPingTimerId !== 0) {
      clearInterval(this.streamPingTimerId);
      this.streamPingTimerId = 0;
    }
    const ids: string[] = [];
    this.conns.forEach((entry: TcpConnEntry): void => {
      ids.push(entry.connId);
    });
    for (const id of ids) {
      await this.cleanupConnection(id, 0);
    }
    this.conns.clear();
    await this.releaseListener();
    this.events = null;
    hilog.info(TCP_LOG_DOMAIN, TCP_LOG_TAG, '静态面停止（原端口 %{public}d）', this.boundPort);
  }

  // ── 动态面空实现（SSE 备胎形态：动态面语义归 SseStreamHub，manager 直接持中枢引用投递；
  // 本件不代理转投——单向依赖（静态面 → 中枢 sink）已足够，反向转发会形成纯转接壳）──

  sendTo(_connId: string, _text: string): Promise<boolean> {
    return Promise.resolve(false);
  }

  broadcast(_text: string): Promise<number> {
    return Promise.resolve(0);
  }

  closeConn(_connId: string): void {
    // 静态短连接无长连簿记语义（cleanupConnection 即时收尾）；SSE 长连的关流归中枢 closeConn
  }

  connectionCount(): number {
    return this.conns.size;
  }
}
