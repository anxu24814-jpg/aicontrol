// 传输层（★ 2026-10-22 SSE 备胎笔新建）——浏览器与手机 Web 服务之间的字节通道。
// 职责一句话：**把「一条双向消息流」抽象成 Transport 接口**，本文件给 SSE 实现（下行
// EventSource / 上行 fetch POST）；client.ts 只认接口，信封层与状态机零感知载体。
// 为何不是 WebSocket：真机 createWebSocketServer 起不来（2302999 内部错误，四种绑定形态
// 全灭），服务端改 SSE（TcpHttpStaticCarrier 的 /events + /api/msg）。协议信封两边逐字一致，
// 换的只是传输。
// 契约：
// · 下行 GET /events?cid=<cid> → text/event-stream，每条 `data: <JSON>\n\n`；
// · 上行 POST /api/msg?cid=<cid>，body = 一整条 JSON 信封，服务端回 200 即弃（业务回执走下行）；
// · cid = 本次连接标识（[A-Za-z0-9_-]），服务端按它把上行系到下行流上。
// 断线语义：**浏览器 EventSource 自带自动重连，本端一律关掉**（close 后不再自连）——重连
// 决策单源在 client.ts 的指数退避，两套重连并存会互相打架（本端刚退避，EventSource 已抢连）。
// 因此 onerror 一律转成 onClose 交给上层。

// 下行流路径（服务端 TCP_SSE_PATH 单源）
export const STREAM_PATH = '/events';
// 上行收件路径（服务端 TCP_UPSTREAM_PATH 单源）
export const UPSTREAM_PATH = '/api/msg';

export interface TransportHandlers {
  // 流已建立（服务端 200 响应头到达）——鉴权首消息在此之后才发
  onOpen(): void;
  // 一条下行信封（原始 JSON 文本）
  onMessage(text: string): void;
  // 流已断（对端关流 / 网络断 / 写失败）——上层据此走退避重连
  onClose(): void;
}

export interface Transport {
  // 发一条上行信封；false = 未连接（上层按「尚未连接手机」处理）
  send(text: string): boolean;
  // 发一条上行信封并等「服务端已收下」（200）——**只给鉴权首消息用**：上行是独立 POST，
  // 两条并发 POST 到达顺序不保证；探针必须先于鉴权消息之后到达，否则服务端会把探针当首消息
  // 判鉴权失败并断流。false = 发送失败或链路已断
  sendAndConfirm(text: string): Promise<boolean>;
  // 主动关流（幂等；关后不再触发 onClose）
  close(): void;
}

// 连接标识：优先 crypto.randomUUID（去掉连字符——服务端 cid 字符集不含 '-' 以外的都收，
// 去连字符只为观感与缩短）；无 randomUUID 的旧 WebView 回落到时间戳 + 随机串
function newCid(): string {
  const c: Crypto | undefined = typeof globalThis.crypto === 'undefined' ? undefined : globalThis.crypto;
  if (c !== undefined && typeof c.randomUUID === 'function') {
    return c.randomUUID().replace(/-/g, '');
  }
  return `c${Date.now().toString(36)}${Math.random().toString(36).slice(2, 10)}`;
}

export class SseTransport implements Transport {
  private es: EventSource | null = null;
  private readonly cid: string = newCid();
  private closed: boolean = false;
  private opened: boolean = false;
  private readonly handlers: TransportHandlers;

  constructor(handlers: TransportHandlers) {
    this.handlers = handlers;
    let es: EventSource;
    try {
      es = new EventSource(`${STREAM_PATH}?cid=${this.cid}`);
    } catch {
      // 构造即失败（极旧浏览器无 EventSource）：按断流上报，交给上层退避并给出可读原因
      window.setTimeout((): void => {
        if (!this.closed) {
          this.closed = true;
          this.handlers.onClose();
        }
      }, 0);
      return;
    }
    this.es = es;
    es.onopen = (): void => {
      if (this.closed) {
        return;
      }
      this.opened = true;
      this.handlers.onOpen();
    };
    es.onmessage = (event: MessageEvent): void => {
      if (this.closed) {
        return;
      }
      const data = typeof event.data === 'string' ? event.data : '';
      if (data !== '') {
        this.handlers.onMessage(data);
      }
    };
    es.onerror = (): void => {
      if (this.closed) {
        return;
      }
      // 关掉 EventSource 的自连接（重连单源在 client.ts），再上报断流
      this.closed = true;
      try {
        es.close();
      } catch {
        // 已关即忽略
      }
      this.es = null;
      this.opened = false;
      this.handlers.onClose();
    };
  }

  // 上行串行链：一条连接的所有 POST 按调用顺序发出（HTTP 层对独立连接不保证到达序，
  // 「发送 → 停止」「两条连发消息」都可能被重排；串行链把顺序钉在客户端）
  private tail: Promise<void> = Promise.resolve();

  send(text: string): boolean {
    if (this.closed || !this.opened) {
      return false;
    }
    this.tail = this.tail.then(async (): Promise<void> => {
      await this.post(text);
    }).catch((): void => {
    });
    return true;
  }

  // 上行 + 等 200（鉴权首消息专用；见接口注释）。同样进串行链，保证它排在已发出的消息之后
  async sendAndConfirm(text: string): Promise<boolean> {
    if (this.closed || !this.opened) {
      return false;
    }
    const job: Promise<boolean> = this.tail.then((): Promise<boolean> => this.post(text));
    this.tail = job.then((): void => {
    }).catch((): void => {
    });
    return job;
  }

  // 单条上行（不带 keepalive——Fetch 规范对 keepalive 请求体有 64KB 上限，长消息会被浏览器
  // 直接拒发；本通道寿命由页面在线保证，无需为 unload 场景留信标能力）。
  // 服务端明确拒收（413 体超限 / 405 路径不符）按断流处理，让上层重连取回一致态
  private async post(text: string): Promise<boolean> {
    if (this.closed || !this.opened) {
      return false;
    }
    try {
      const response = await fetch(`${UPSTREAM_PATH}?cid=${this.cid}`, {
        method: 'POST',
        headers: { 'Content-Type': 'text/plain;charset=UTF-8' },
        body: text,
      });
      if (!response.ok) {
        this.failLink();
        return false;
      }
      return true;
    } catch {
      this.failLink();
      return false;
    }
  }

  // 链路判死（关流 + 上报；幂等）
  private failLink(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    const es = this.es;
    this.es = null;
    this.opened = false;
    if (es !== null) {
      try {
        es.close();
      } catch {
        // 已关即忽略
      }
    }
    this.handlers.onClose();
  }

  close(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    const es = this.es;
    this.es = null;
    this.opened = false;
    if (es !== null) {
      try {
        es.close();
      } catch {
        // 已关即忽略
      }
    }
  }
}
