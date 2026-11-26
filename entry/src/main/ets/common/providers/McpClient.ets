// MCP 客户端·短连传输与会话域：Streamable HTTP 按需短连——每次 RPC 一个独立 POST、独立
// http.createHttp()，用完按 finalize 单点成对释放（off 三件 + destroy，照 HttpTransport.ets
// finalize 范式，内存防线）。职责 = 「把 McpRpc 的报文发出去、把响应拿回来、把会话记住」
// （报文构造与解译在 McpRpc；DB 与注册面在 McpDb/McpTools——本件不查库，serverId/url/
// headersJson 由调用方参数化传入，防环）。只引 McpRpc + @kit + KeyStore（Asset 现取现用）
// + 代理件 + providers 域三叶子（HttpSse 的 SseFrameParser——复用禁自写第三套 SSE 分帧；
// HttpReceipt 的 readHeader 单源；WebSearchParse 的 httpKitErrorText）+ McpText。不引 chat
// 域、不引 ChatDb/McpDb——无环。
// · 响应双形态合流单管：恒走 requestInStream（不回 HttpResponse，故不按形态分叉两套调用，
//   ChatStreamBase / HttpTransport 在役先例），headersReceive 取 Content-Type 分路——
//   json 形 dataReceive 累积报文、dataEnd 整体直解；event-stream 形 SseFrameParser 增量
//   分帧、dataEnd flush 补尾帧。完成判定 = Promise 落定 + dataEnd 两者齐（坑19）；流上先于
//   响应到达的通知/请求类报文按 id 匹配天然滤除（McpRpc.isResponseFor），**命中响应即可提前
//   收口**——「读到响应完作为止」MCP 口径（服务器 SHOULD 响应后断流，个别实现挂着不断时
//   命中即走，readTimeout 兜底）。
// · 会话：mcpSessions 内存 Map 只存会话标识与协商版本（不存回调/定时器/连接句柄——每次 RPC
//   独立 http 实例，寿命匹配天然合规；条目有界：服务器上限 8 + 删除级联 clearMcpSession
//   清理）。并发首呼可能重复握手（无锁短连设计）——两会话皆有效，幂等无害。
// · 会话失效自愈（判据全文见 McpRpc 头注释第 6 条）：带会话头的请求收到 404 → 清缓存 →
//   重握手 → 重试一次；二次失败即报错回执不再试。
// · 超时：握手与 tools/list 每请求 20s；tools/call 120s。
// · 请求头组装（buildRequestHeaders 单点）：用户自定义头先写（值经 KeyStore 现取现用——
//   明文零落日志/零进任何记录，密钥红线）→ 协议头后写覆盖（Accept 双形态 + Content-Type +
//   MCP-Protocol-Version + Mcp-Session-Id）——协议头语义必须胜出，自定义头不得劫持
//   Accept/Content-Type 等协议面。
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { SseFrameParser, SseEvent } from './HttpSse';
import { applyEffectiveProxy } from './RequestIdentity';
import { readHeader } from './HttpReceipt';
import { HTTP_MAX_REDIRECTS } from './HttpTransport';
import { httpKitErrorText } from './WebSearchParse';
import { loadMcpHeaderValues } from '../store/KeyStore';
import { parseMcpHeaderMeta, MCP_TOOLS_CACHE_MAX } from '../McpText';
import { McpListedTool, McpRpcResponse, MCP_PROTOCOL_VERSION_OFFERED, buildInitializeRequest,
  buildInitializedNotification, buildToolsListRequest, buildToolsCallRequest, mcpNextRequestId,
  parseMcpResponse, isResponseFor, mcpEnsureResult, mapToolsPage, mcpCallResultToText,
  mcpNegotiatedVersionOf, mcpHttpStatusErrorText } from './McpRpc';

// ── 常量族 ──
// Accept 双形态（规范原文：listing both application/json and text/event-stream）
const MCP_ACCEPT_HEADER: string = 'application/json, text/event-stream';
// 超时（头注释数值族论证）
const MCP_TIMEOUT_SHORT_MS: number = 20000;
const MCP_TIMEOUT_CALL_MS: number = 120000;
// tools/list 分页循环硬顶（数据有界红线：恶意/异常服务器无限续游标时不得无限拉；触顶 =
// 同步失败中文错，禁静默缺工具）
const MCP_LIST_PAGES_MAX: number = 64;

// 服务器端点参数（调用方参数化传入——本件不查库；headersJson 为元数据串「名称+hasValue」，
// 值明文恒不在场，Asset 现取；protocolVersion = 广告协议版本，'' = 自动协商〔见 McpRpc 头注释
// 第 10 条〕；headerValues = 显式头值组，可选——仅编辑页「测试连接」表单态新输入值尚未落
// Asset 时提供，优先于 Asset 读取；长度与元数据不必等长，缺位按空值跳过）
export interface McpServerEndpoint {
  serverId: string;
  url: string;
  headersJson: string;
  protocolVersion: string;
  headerValues?: string[];
}

// 会话缓存条目：sessionId '' = 服务器不下发会话头（无会话服务器——后续请求不带该头，规范
// 允许）；protocolVersion = 协商版本（MCP-Protocol-Version 头值；'' = 服务器未回，回退广告值）
interface McpSessionEntry {
  sessionId: string;
  protocolVersion: string;
}

// 进程级会话单例（无常态连接、只存会话标识与协商版本；条目有界——服务器上限 8 + 删除级联清理）
const mcpSessions: Map<string, McpSessionEntry> = new Map();

// 清会话缓存（删除级联与配置变更后重握手两处消费——不清只在 Map 留死条目，数据有界红线）
export function clearMcpSession(serverId: string): void {
  mcpSessions.delete(serverId);
}

// 请求头组装（头注释口径：自定义头先写、协议头后写覆盖）
async function buildRequestHeaders(endpoint: McpServerEndpoint, protocolVersion: string,
  sessionId: string): Promise<Record<string, string>> {
  const headers: Record<string, string> = {};
  const metas = parseMcpHeaderMeta(endpoint.headersJson);
  if (metas.length > 0) {
    // 显式值组（测试连接的表单态）优先于 Asset 现取；缺位按空值跳过（不造空头）
    const values: string[] = endpoint.headerValues !== undefined ? endpoint.headerValues
      : await loadMcpHeaderValues(endpoint.serverId, metas.length);
    for (let i: number = 0; i < metas.length; i++) {
      const value: string = i < values.length ? values[i] : '';
      // 值缺失（备份导入后 / 从未填过）跳过不造空头——鉴权服务器会以 401 拒绝，错误句可归因
      if (value !== '') {
        headers[metas[i].name] = value;
      }
    }
  }
  headers['Accept'] = MCP_ACCEPT_HEADER;
  headers['Content-Type'] = 'application/json';
  headers['MCP-Protocol-Version'] = protocolVersion !== '' ? protocolVersion
    : MCP_PROTOCOL_VERSION_OFFERED;
  if (sessionId !== '') {
    headers['Mcp-Session-Id'] = sessionId;
  }
  return headers;
}

// ── 单次 POST 传输（requestInStream 单管 + headersReceive 分路 + 命中即收）──
interface McpPostOutcome {
  networkOk: boolean;    // 网络层成功拿到响应（含 4xx/5xx——那是响应不是网络失败）
  netErrorText: string;  // 网络层失败中文句（networkOk=false 时有意义）
  status: number;        // HTTP 状态码（Promise 值或 status-line 真值；0 = 命中提前收口且无 status-line）
  sessionId: string;     // 响应头 Mcp-Session-Id（'' = 本次响应未下发——只有 initialize 响应会带）
  isEventStream: boolean;
  bodyText: string;      // json 形累积正文（SSE 形为 ''）
  matched: boolean;      // 是否命中期待 id 的响应（通知类 POST 期待 -1 恒 false）
  matchedJson: string;   // 命中报文原文（SSE 形为命中事件 data；json 形同 bodyText）
}

// 传输成功判（网络成功 + 状态可收）：2xx；或 SSE 命中提前收口且无 status-line 的 0 值宽容——
// 命中报文本身即成功证据（status-line 为文档化字段、常规恒在场，0 值是防御态）
function postAccepted(out: McpPostOutcome): boolean {
  if (!out.networkOk) {
    return false;
  }
  if (out.matched && out.status === 0) {
    return true;
  }
  return out.status >= 200 && out.status < 300;
}

// expectRequestId：期待的请求 id（SSE 形流上命中即提前收口——「读到响应完作为止」）；-1 =
// 通知类 POST（无期待响应，完成判定 = dataEnd + Promise 落定，202 Accepted 无 body 是常态）
function mcpPost(url: string, headers: Record<string, string>, body: string, timeoutMs: number,
  expectRequestId: number): Promise<McpPostOutcome> {
  return new Promise<McpPostOutcome>((resolve: (out: McpPostOutcome) => void) => {
    const req: http.HttpRequest = http.createHttp();
    const outcome: McpPostOutcome = {
      networkOk: false, netErrorText: '', status: 0, sessionId: '', isEventStream: false,
      bodyText: '', matched: false, matchedJson: ''
    };
    // ── 收口状态（坑19 双标志：完成判定 = Promise 落定 + dataEnd 两者齐）──
    let settled: boolean = false;
    let endSeen: boolean = false;
    let finished: boolean = false;
    let statusLineCode: number = 0;
    let sessionHeaderSeen: string = '';
    let isEventStream: boolean = false;
    let jsonText: string = '';
    let pendingNetError: string = '';
    const parser: SseFrameParser = new SseFrameParser();
    const decoder: util.TextDecoder = new util.TextDecoder('utf-8');

    // 统一收尾单点（HttpTransport finalize 范式）：off 三件（幂等包 try）+ destroy → 回填
    // outcome → resolve——任何路径的收尾全走这里，on↔off 成对性由单点保证（内存防线）
    const finalize = (): void => {
      if (finished) {
        return;
      }
      finished = true;
      try {
        req.off('dataReceive');
      } catch (e) {
      }
      try {
        req.off('dataEnd');
      } catch (e) {
      }
      try {
        req.off('headersReceive');
      } catch (e) {
      }
      try {
        req.destroy();
      } catch (e) {
      }
      outcome.networkOk = pendingNetError === '';
      outcome.netErrorText = pendingNetError;
      outcome.status = statusLineCode;
      outcome.sessionId = sessionHeaderSeen;
      outcome.isEventStream = isEventStream;
      outcome.bodyText = jsonText;
      if (!outcome.matched && expectRequestId >= 0 && !isEventStream
        && statusLineCode >= 200 && statusLineCode < 300 && jsonText !== '') {
        // json 形在收尾点整体直解补判一次命中（dataEnd 后路径——与 SSE 逐事件判同源）
        const probe: McpRpcResponse | null = parseMcpResponse(jsonText);
        if (probe !== null && isResponseFor(probe, expectRequestId)) {
          outcome.matched = true;
          outcome.matchedJson = jsonText;
        }
      }
      resolve(outcome);
    };
    const maybeSettle = (): void => {
      if (finished || !settled || !endSeen) {
        return;
      }
      finalize();
    };
    // SSE 流逐事件命中判：命中期待 id 的响应即提前收口（头注释「读到响应完作为止」——个别
    // 实现不断流时命中即走不等 readTimeout）
    const feedEvents = (fresh: SseEvent[]): void => {
      for (const ev of fresh) {
        const data: string = ev.data;
        if (!outcome.matched && expectRequestId >= 0) {
          const probe: McpRpcResponse | null = parseMcpResponse(data);
          if (probe !== null && isResponseFor(probe, expectRequestId)) {
            outcome.matched = true;
            outcome.matchedJson = data;
            settled = true; // 结果已定格，不等 Promise（ChatStreamBase.abort 主动收口同款取向）
            finalize();
            return;
          }
        }
      }
    };

    // ── 三回调订阅与起流（同守卫段——SDK 面抛错即静默悬停，ChatStreamBase 同款纪律）──
    try {
      req.on('headersReceive', (h: Object): void => {
        if (finished) {
          return;
        }
        // 响应头经事件回传（requestInStream 不回 HttpResponse）；逐跳覆盖语义下取最终响应头
        const contentType: string = readHeader(h, 'content-type');
        isEventStream = contentType.toLowerCase().includes('text/event-stream');
        const sessionVal: string = readHeader(h, 'mcp-session-id');
        if (sessionVal !== '') {
          sessionHeaderSeen = sessionVal;
        }
        // status-line 状态码真值（HttpTransport 同款：提前收口/迟到 reject 时唯一的码源）
        const statusLine: string = readHeader(h, 'status-line');
        if (statusLine !== '') {
          const lineParts: string[] = statusLine.split(' ');
          const parsed: number = lineParts.length >= 2 ? parseInt(lineParts[1], 10) : NaN;
          if (Number.isFinite(parsed) && parsed > 0) {
            statusLineCode = parsed;
          }
        }
      });
      req.on('dataReceive', (chunk: ArrayBuffer): void => {
        if (finished) {
          return;
        }
        // decodeToString stream 模式：UTF-8 多字节跨分片不撕裂（HttpTransport 同款）
        const piece: string = decoder.decodeToString(new Uint8Array(chunk), { stream: true });
        if (isEventStream) {
          const fresh = parser.feed(piece);
          feedEvents(fresh);
        } else {
          jsonText += piece;
        }
      });
      req.on('dataEnd', (): void => {
        if (finished) {
          return;
        }
        // 自然收尾：残留当末帧补出（SseFrameParser.flush 语义——末帧无空行形态的兜出）
        if (isEventStream) {
          const tail = parser.flush();
          feedEvents(tail);
          if (finished) {
            return; // 尾帧命中已提前收口
          }
        }
        endSeen = true;
        maybeSettle();
      });
      // options 与 HttpTransport httpRequestStream 同源（inStream 模式数据走回调，无
      // expectDataType / maxLimit 面）
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: body,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        maxRedirects: HTTP_MAX_REDIRECTS,
        usingCache: false
      };
      // 代理兜底写入（工具域请求统一姿势，system 档零介入）
      applyEffectiveProxy(options);
      req.requestInStream(url, options)
        .then((code: number): void => {
          settled = true;
          statusLineCode = code; // Promise 状态码为真值（坑19：流末才落定，晚于 dataEnd 是常态）
          maybeSettle();
        })
        .catch((e: Object): void => {
          settled = true;
          if (endSeen && statusLineCode > 0) {
          // 迟到 reject 不压掉已收完的流（HttpTransport 同源先例）：流已完整收到，信 dataEnd
          // 的事实，错误面保持空
            maybeSettle();
            return;
          }
          // 真网络失败即终局（无后续数据可等）——直接收尾
          pendingNetError = httpKitErrorText(e, Math.max(1, Math.round(timeoutMs / 1000)));
          finalize();
        });
    } catch (e) {
      // 订阅 / 起流同步抛错：传输未成立，按网络失败收口（finalize 的 off/destroy 包 try，安全）
      pendingNetError = '请求发起失败：' + (e as Error).message;
      finalize();
    }
  });
}

// 会话确保：缓存命中直接复用；未缓存 = initialize（不带会话头）→ 记会话与协商版本 →
// notifications/initialized（带会话头，202 期望）→ 全程成功才落缓存（半握手不缓存——下次
// 调用重新走全握手，不留「初始化了但没确认」的中间态）
async function ensureSession(endpoint: McpServerEndpoint): Promise<McpSessionEntry> {
  const cached: McpSessionEntry | undefined = mcpSessions.get(endpoint.serverId);
  if (cached !== undefined) {
    return cached;
  }
  const initId: number = mcpNextRequestId();
  // 强制档（protocolVersion 非空）= initialize 广告该值；自动档 '' 回退 OFFERED（与一期
  // 逐字节等价——McpRpc 头注释第 10 条）
  const offered: string = endpoint.protocolVersion !== '' ? endpoint.protocolVersion
    : MCP_PROTOCOL_VERSION_OFFERED;
  const initHeaders: Record<string, string> = await buildRequestHeaders(endpoint,
    offered, '');
  const initOut: McpPostOutcome = await mcpPost(endpoint.url, initHeaders,
    buildInitializeRequest(initId, endpoint.protocolVersion), MCP_TIMEOUT_SHORT_MS, initId);
  if (!initOut.networkOk) {
    throw new Error(initOut.netErrorText);
  }
  if (!postAccepted(initOut)) {
    throw new Error(mcpHttpStatusErrorText(initOut.status));
  }
  const initRespText: string = initOut.isEventStream ? initOut.matchedJson : initOut.bodyText;
  const initParsed: McpRpcResponse | null = parseMcpResponse(initRespText);
  if (initParsed === null || !isResponseFor(initParsed, initId)) {
    throw new Error('握手响应无法识别，服务器可能不支持 Streamable HTTP 形态');
  }
  const initResultJson: string = mcpEnsureResult(initParsed);
  const entry: McpSessionEntry = {
    sessionId: initOut.sessionId,
    protocolVersion: mcpNegotiatedVersionOf(initResultJson)
  };
  // initialized 通知（版本头带协商值——握手已完成；202 是规范定值，个别实现回 200 也收
  // ——postAccepted 宽容 2xx）
  const version: string = entry.protocolVersion !== '' ? entry.protocolVersion
    : MCP_PROTOCOL_VERSION_OFFERED;
  const notifHeaders: Record<string, string> = await buildRequestHeaders(endpoint, version,
    entry.sessionId);
  const notifOut: McpPostOutcome = await mcpPost(endpoint.url, notifHeaders,
    buildInitializedNotification(), MCP_TIMEOUT_SHORT_MS, -1);
  if (!notifOut.networkOk) {
    throw new Error(notifOut.netErrorText);
  }
  if (!postAccepted(notifOut)) {
    throw new Error(mcpHttpStatusErrorText(notifOut.status));
  }
  mcpSessions.set(endpoint.serverId, entry);
  return entry;
}

// 单次请求 + 会话失效自愈一次（官方判据：带 Mcp-Session-Id 的请求收到 HTTP 404 → MUST 重握手）
async function requestOnce(endpoint: McpServerEndpoint, body: string, timeoutMs: number,
  requestId: number): Promise<McpRpcResponse> {
  const entry: McpSessionEntry = await ensureSession(endpoint);
  const version: string = entry.protocolVersion !== '' ? entry.protocolVersion
    : MCP_PROTOCOL_VERSION_OFFERED;
  let headers: Record<string, string> = await buildRequestHeaders(endpoint, version,
    entry.sessionId);
  let out: McpPostOutcome = await mcpPost(endpoint.url, headers, body, timeoutMs, requestId);
  // 会话失效自愈（仅当本次请求带了会话头且收到 404——无会话服务器的 404 = 端点不存在，走
  // 通用错误句）；重试报文复用同 id：首试 id 消费在旧会话，重握手后是全新会话，规范「同会话
  // 内禁复用」不涉跨会话
  if (out.networkOk && out.status === 404 && entry.sessionId !== '') {
    mcpSessions.delete(endpoint.serverId);
    const entry2: McpSessionEntry = await ensureSession(endpoint);
    const version2: string = entry2.protocolVersion !== '' ? entry2.protocolVersion
      : MCP_PROTOCOL_VERSION_OFFERED;
    headers = await buildRequestHeaders(endpoint, version2, entry2.sessionId);
    out = await mcpPost(endpoint.url, headers, body, timeoutMs, requestId);
    if (out.networkOk && out.status === 404) {
      // 二次失败即报错回执不再试
      throw new Error('会话已失效，重新连接后仍被拒绝（HTTP 404）');
    }
  }
  if (!out.networkOk) {
    throw new Error(out.netErrorText);
  }
  if (!postAccepted(out)) {
    throw new Error(mcpHttpStatusErrorText(out.status));
  }
  const respText: string = out.isEventStream ? out.matchedJson : out.bodyText;
  const parsed: McpRpcResponse | null = parseMcpResponse(respText);
  if (parsed === null || !isResponseFor(parsed, requestId)) {
    throw new Error('服务器响应无法匹配请求');
  }
  return parsed;
}

// ── 公共 API ──
// 工具同步结果（刷新键 / 保存后自动测连消费：拉全后的缓存数组——整表替换回写由调用方落库，
// 本件不查库）
export interface McpSyncOutcome {
  tools: McpListedTool[];
}

// 全量同步：ensureSession（initialize + initialized）→ tools/list 按游标循环拉全 → 32 件上限
// 闸。★ 拉全纪律：按 nextCursor 续拉至无 nextCursor 止；累计超上限即刻抛中文错（防恶意服务器
// 以无限游标拖死同步，数据有界红线）；拉不全（页数触顶）= 同步失败中文报错，禁只取首页静默
// 缺工具（P0-1）。页间重名工具与页内同判抛错。
export async function syncMcpServer(endpoint: McpServerEndpoint): Promise<McpSyncOutcome> {
  const tools: McpListedTool[] = [];
  let cursor: string = '';
  for (let page: number = 0; page < MCP_LIST_PAGES_MAX; page++) {
    const requestId: number = mcpNextRequestId();
    const parsed: McpRpcResponse = await requestOnce(endpoint,
      buildToolsListRequest(requestId, cursor), MCP_TIMEOUT_SHORT_MS, requestId);
    const resultJson: string = mcpEnsureResult(parsed);
    const pageData = mapToolsPage(resultJson);
    for (const tool of pageData.tools) {
      for (const existing of tools) {
        if (existing.name === tool.name) {
          throw new Error('工具清单存在重名工具：' + tool.name);
        }
      }
      tools.push(tool);
    }
    if (tools.length > MCP_TOOLS_CACHE_MAX) {
      throw new Error('工具数超过上限（最多 ' + MCP_TOOLS_CACHE_MAX + ' 件），已取消同步');
    }
    if (pageData.nextCursor === '') {
      const outcome: McpSyncOutcome = { tools: tools };
      return outcome;
    }
    cursor = pageData.nextCursor;
  }
  throw new Error('工具清单分页异常：页数超过上限仍未拉全，已取消同步');
}

// 工具调用（executor 消费）：tools/call（120s）→ content 文本化 → isError 转错误上抛
// （ToolRuntime 包装 {"error":...} 回执，模型可感知自纠——规范「工具执行错误透传模型」口径）
export async function callMcpTool(endpoint: McpServerEndpoint, toolName: string,
  argsJson: string): Promise<string> {
  const requestId: number = mcpNextRequestId();
  const parsed: McpRpcResponse = await requestOnce(endpoint,
    buildToolsCallRequest(requestId, toolName, argsJson), MCP_TIMEOUT_CALL_MS, requestId);
  const resultJson: string = mcpEnsureResult(parsed);
  const callText = mcpCallResultToText(resultJson);
  if (callText.isError) {
    throw new Error(callText.text);
  }
  return callText.text;
}
