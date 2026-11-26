// MCP 协议层·报文构造与解译纯函数域：JSON-RPC 2.0 四动作报文构造（initialize /
// notifications/initialized / tools/list / tools/call）+ 响应解译（result/error 分路、按 id
// 匹配滤无 id 通知类事件）+ tools/list 结果映射 + tools/call content 文本化。**零 import 纯
// 函数约束**（坑50：McpClient / McpTools / 断言脚本均引本件，本件不引任何件；
// scripts/assert-tool-domain.mjs 复制本文件为 .ts 直跑）。HTTP 传输面（短连 POST / 会话头 /
// 自愈）在 McpClient.ets，不在本域。
//
// ★★ MCP 官方规范查证结论（联网查证 modelcontextprotocol.io——本件一切字段以查证为准）：
//
// 1. 版本锚：现行版 = 2026-07-28。**本件实现「经典兼容形态」**（2025-03-26~2025-11-25 线：
//    initialize 握手 + notifications/initialized + Mcp-Session-Id 会话头）——2026-07-28 传输篇
//    Backward Compatibility 节明示「需与旧版对端互操作的服务器与客户端按对应版本实现行为」，
//    经典形态是对外互通的正门；仅支持 2026-07-28 新形态（binding / 请求无状态自包含 / 逐请求
//    元数据头 Mcp-Method·Mcp-Name·_meta）的服务器会对本客户端回 400
//    UnsupportedProtocolVersionError，属二期互通差异清单。
//
// 2. JSON-RPC 2.0 三形态：请求 {jsonrpc,id,method,params?}——id 必为 string 或整数、禁 null、
//    同会话内禁复用（本件进程级单调自增计数器天然满足）；响应 {jsonrpc,id,result|error}——
//    result 与 error 恰设其一、error 必含 code 整数 + message；通知 {jsonrpc,method,params?}——
//    禁带 id。
//
// 3. initialize 握手：请求 params = {protocolVersion, capabilities, clientInfo{name,version}}——
//    客户端能力集可为空对象 {}（本客户端不声明 roots/sampling/elicitation 任何能力）；版本
//    协商 = 客户端发己方支持版本，服务器支持则同值回显、否则回己方版本，客户端不支持服务器
//    回版时 SHOULD 断开——本实现宽容接受并把协商值记入会话（McpClient 后续请求
//    MCP-Protocol-Version 头携带）。握手成功后客户端 MUST 发 notifications/initialized 通知
//    （无 id 无 params）。
//
// 4. tools/list：请求 params = {cursor?}（首拉无游标可整个省略 params）；result = {tools:[{name,
//    description?, inputSchema}], nextCursor?}——name 服务器内唯一、inputSchema 为 JSON Schema
//    对象（无 $schema 字段时缺省 2020-12）；分页语义 = nextCursor 非空则携该 cursor 续拉，
//    直至无 nextCursor（分页循环与上限闸在 McpClient，本件 mapToolsPage 只做单页映射）。
//
// 5. tools/call：请求 params = {name, arguments}——arguments 为对象；result = {content:[…],
//    isError?}——content 项五型：text{text} / image{data,mimeType} / audio{data,mimeType} /
//    resource_link{uri} / resource{resource{uri,text?}}；isError=true = **工具执行错误**（执行期
//    失败 / 入参校验失败——含模型可自纠的可操作反馈，与 JSON-RPC 协议错误是两个报告面，规范
//    明示客户端 SHOULD 透传给模型）——本实现转错误回执（Error 上抛，ToolRuntime 包装
//    {"error":...}，模型可感知自纠）。structuredContent（2025-06-18 起）规范要求服务器同时附
//    序列化 text 块，故 content 空而 structuredContent 在场时本实现回退序列化该对象兜底。
//
// 6. 传输面语义（Streamable HTTP；报文形态归本件、HTTP 行为归 McpClient）：每条 JSON-RPC
//    消息 = 一个独立 HTTP POST；Accept 头须同时列 application/json 与 text/event-stream；
//    请求的响应双形态——Content-Type application/json（单 JSON 对象）或 text/event-stream
//    （SSE 流，data 载 JSON-RPC 报文，响应前可夹服务器通知与请求，流随响应后终止）；通知
//    （notifications/initialized）被接受 = HTTP 202 Accepted 无 body。Mcp-Session-Id 由服务器
//    在 initialize 响应头下发（可见 ASCII 0x21~0x7E），客户端后续请求必带；**会话失效判别 =
//    带 Mcp-Session-Id 的请求收到 HTTP 404 → 客户端 MUST 不带会话头重新 initialize**（自愈
//    触发判据，McpClient 落实）。
//
// ★补 7. MCP-Protocol-Version 头（2025-11-25 起 MUST）：initialize 之后的所有 HTTP 请求须带
//    MCP-Protocol-Version: <协商版本> 头；服务器收不到该头时 SHOULD 假定 2025-03-26——即
//    带上对旧服务器无害、对新服务器必需。本实现 initialize 请求即带广告值、之后带协商值
//    （单一代码路径，注释在此说明与规范措辞「subsequent」的取舍）。
//
// ★补 8. JSON-RPC 错误码面：-32700 解析错 / -32600 非法请求 / -32601 方法不存在 / -32602
//    非法参数 / -32603 内部错误 / -32000~-32099 MCP 服务器保留段。错误转中文句时保留官方
//    code 与 message 原文（模型与用户排障需要官方语义，不吞不改）。
//
// 9. 广告版本取值：MCP_PROTOCOL_VERSION_OFFERED = '2025-06-18'——本实现严格复刻的经典线内
//    版本（streamable HTTP 自 2025-03-26 定形、2025-06-18 为生态存量主流），服务器可协商回
//    更早或更晚版本，协商值由 McpClient 记用（mcpNegotiatedVersionOf 提取）。
// ★补 10. 版本广告可参数化：MCP_VERSIONS_LEGAL = 官方 /llms.txt 目录六档（2024-11-05 /
//    2025-03-26 / 2025-06-18 / 2025-11-25 / 2026-07-28 / draft）去掉 2024-11-05 与 draft 后的
//    四个稳定版，编辑页下拉与保存闸单源；MCP_VERSION_AUTO = '' 表示自动协商（广告值恒
//    MCP_PROTOCOL_VERSION_OFFERED）。强制档只升级握手广告值与 MCP-Protocol-Version 头，报文
//    仍是经典握手线——对「只认 2026-07-28 新形态报文」的服务器无解（编辑页说明小字如实
//    交代，验收不设「2026 必通」项）。

// ── 常量族 ──
export const MCP_JSONRPC_VERSION: string = '2.0';
// 广告协议版本（头注释第 9 条取值论证）
export const MCP_PROTOCOL_VERSION_OFFERED: string = '2025-06-18';
// 自动协商档（mcp_servers.protocolVersion 列默认值 ''；广告值回退 OFFERED）
export const MCP_VERSION_AUTO: string = '';
// 强制档合法版本集（头注释第 10 条；顺序即编辑页下拉展示序——由早到晚）
export const MCP_VERSIONS_LEGAL: string[] = ['2025-03-26', '2025-06-18', '2025-11-25',
  '2026-07-28'];
// clientInfo 标识（显示用途，非应用版本联动——零 import 件读不到应用版本，刻意解耦）
export const MCP_CLIENT_INFO_NAME: string = 'aicontrol';
export const MCP_CLIENT_INFO_VERSION: string = '1.0.0';

// ── 请求 id 自增（进程级单调计数器；规范「同会话内禁复用」由进程级永不回退天然满足——
// 跨会话复用不受限，且重握手是全新会话）──
let rpcIdSeq: number = 1;

export function mcpNextRequestId(): number {
  const id: number = rpcIdSeq;
  rpcIdSeq += 1;
  return id;
}

// 协议版本合法判据（'' = 自动协商档合法；否则必须落在 MCP_VERSIONS_LEGAL）。消费面 =
// 编辑页保存闸与断言直跑；数据层不二次判定（与 url 校验同判据：两处判定 = 两处漂移面，
// 绕过 UI 手改库的脏值在握手期由服务器拒绝，错误句可归因）
export function isValidMcpProtocolVersion(version: string): boolean {
  if (version === MCP_VERSION_AUTO) {
    return true;
  }
  return MCP_VERSIONS_LEGAL.includes(version);
}

// ── 报文构造（四动作；返回可直接 POST 的 JSON 串）──
// initialize 请求：能力集空对象（本客户端不声明任何可选能力）；clientInfo 仅 name+version
// （title/icons 等为可选扩展，缺省合法）。offeredVersion 为第二默认参：'' = 自动协商档，
// 回退 MCP_PROTOCOL_VERSION_OFFERED——既有单参调用行为逐字节不变（assert-mcp-domain
// 394 组零修订的验收面）；非空 = 强制广告该版本
export function buildInitializeRequest(id: number, offeredVersion: string = ''): string {
  const advertised: string = offeredVersion !== '' ? offeredVersion
    : MCP_PROTOCOL_VERSION_OFFERED;
  return '{"jsonrpc":"' + MCP_JSONRPC_VERSION + '","id":' + id + ',"method":"initialize"'
    + ',"params":{"protocolVersion":' + JSON.stringify(advertised)
    + ',"capabilities":{},"clientInfo":{"name":' + JSON.stringify(MCP_CLIENT_INFO_NAME)
    + ',"version":' + JSON.stringify(MCP_CLIENT_INFO_VERSION) + '}}}';
}

// initialized 通知：无 id 无 params（规范定形报文，禁画蛇添足）
export function buildInitializedNotification(): string {
  return '{"jsonrpc":"' + MCP_JSONRPC_VERSION + '","method":"notifications/initialized"}';
}

// tools/list 请求：cursor 为空 = 首拉，整个 params 省略（规范 params 可选——取省略形态
// 与官方示例一致）；续拉携游标
export function buildToolsListRequest(id: number, cursor: string): string {
  const base: string = '{"jsonrpc":"' + MCP_JSONRPC_VERSION + '","id":' + id
    + ',"method":"tools/list"';
  if (cursor === '') {
    return base + '}';
  }
  return base + ',"params":{"cursor":' + JSON.stringify(cursor) + '}}';
}

// tools/call 请求：arguments 原串透传（B6 executor 的 argsJson 不解析不重编码——大整数与
// 浮点字面量按原文上送，防 parse/stringify 往返改写数值精度）；入参先探合法 JSON，非法即抛
// 中文错（防拼出畸形信封让服务器报解析错，错误面留在本端更可归因）
export function buildToolsCallRequest(id: number, toolName: string, argsJson: string): string {
  try {
    JSON.parse(argsJson);
  } catch (e) {
    throw new Error('工具参数不是合法 JSON，无法发送');
  }
  return '{"jsonrpc":"' + MCP_JSONRPC_VERSION + '","id":' + id
    + ',"method":"tools/call","params":{"name":' + JSON.stringify(toolName)
    + ',"arguments":' + argsJson + '}}';
}

// ── 响应解译 ──
// 单条 JSON-RPC 报文的解译产物：method 非空 = 通知或服务器请求（非响应，按 id 匹配天然滤除
//——SSE 流上 ping/progress 类通知 data 照常产出，靠 isResponseFor 过滤）；idNumber 仅在 id
// 为数字时有效（本客户端只发数字 id，字符串 id 的报文永不可能匹配本端请求）
export interface McpRpcResponse {
  method: string;
  hasId: boolean;
  idNumber: number;
  isError: boolean;
  errorCode: number;
  errorMessage: string;
  hasResult: boolean;
  resultJson: string;
}

// 解析单条报文（JSON body 整串或 SSE 事件 data）：坏 JSON / 非对象（数组、字符串字面量等）
// 返回 null（调用方按「流内噪声帧容忍、命中帧必判」处理——SSE 流上偶发注释类事件不炸链）
export function parseMcpResponse(data: string): McpRpcResponse | null {
  let rec: Record<string, Object> | null = null;
  try {
    const parsed: object = JSON.parse(data);
    if (typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)) {
      rec = parsed as Record<string, Object>;
    }
  } catch (e) {
    return null;
  }
  if (rec === null) {
    return null;
  }
  const methodVal: Object | undefined = rec['method'];
  const idVal: Object | undefined = rec['id'];
  // narrowing 须在表达式内联做（经中间布尔变量传递会丢失 typeof 收窄）；两次判定含 id=0 边界
  const hasId: boolean = typeof idVal === 'number';
  const idNum: number = typeof idVal === 'number' ? idVal : 0;
  const errVal: Object | undefined = rec['error'];
  let isError: boolean = false;
  let errorCode: number = 0;
  let errorMessage: string = '';
  if (errVal !== undefined && errVal !== null && typeof errVal === 'object'
    && !Array.isArray(errVal)) {
    const errRec: Record<string, Object> = errVal as Record<string, Object>;
    const codeVal: Object | undefined = errRec['code'];
    if (typeof codeVal === 'number') {
      isError = true;
      errorCode = codeVal;
      const msgVal: Object | undefined = errRec['message'];
      errorMessage = typeof msgVal === 'string' ? msgVal : '';
    }
  }
  const resultVal: Object | undefined = rec['result'];
  const hasResult: boolean = resultVal !== undefined && resultVal !== null
    && typeof resultVal === 'object' && !Array.isArray(resultVal);
  const resp: McpRpcResponse = {
    method: typeof methodVal === 'string' ? methodVal : '',
    hasId: hasId,
    idNumber: idNum,
    isError: isError,
    errorCode: errorCode,
    errorMessage: errorMessage,
    hasResult: hasResult,
    resultJson: hasResult ? JSON.stringify(resultVal) : ''
  };
  return resp;
}

// 响应匹配判据：非通知/非请求（无 method）+ id 数字相等 + result/error 恰一在场
export function isResponseFor(resp: McpRpcResponse, id: number): boolean {
  return resp.method === '' && resp.hasId && resp.idNumber === id
    && (resp.hasResult || resp.isError);
}

// 响应收口：error 形抛中文错（保留官方 code 与 message 原文，头注释第 8 条）；缺 result 的
// 畸形响应同样抛错（不静默）
export function mcpEnsureResult(resp: McpRpcResponse): string {
  if (resp.isError) {
    throw new Error(mcpRpcErrorText(resp.errorCode, resp.errorMessage));
  }
  if (!resp.hasResult) {
    throw new Error('响应缺少 result 字段，无法解析');
  }
  return resp.resultJson;
}

// JSON-RPC 错误 → 中文句（官方 code 与 message 原文透传——lastError 摘要与模型回执两用的
// 单一来源）
export function mcpRpcErrorText(code: number, message: string): string {
  const detail: string = message !== '' ? message : '服务器未提供错误说明';
  return '服务器返回错误 ' + code + '：' + detail;
}

// HTTP 状态码 → 中文句（传输层非 2xx 收口；404 在 McpClient 另有会话自愈分支先行截获，
// 走到本句的 404 = 端点本身不存在）
export function mcpHttpStatusErrorText(status: number): string {
  if (status === 401 || status === 403) {
    return '服务器鉴权失败（HTTP ' + status + '），请检查请求头配置';
  }
  if (status === 404) {
    return '服务器端点不存在（HTTP 404），请检查地址';
  }
  if (status >= 500) {
    return '服务器内部错误（HTTP ' + status + '）';
  }
  return '服务器返回异常状态 HTTP ' + status;
}

// initialize result → 协商协议版本（MCP-Protocol-Version 头值来源；缺省回 ''，调用方回退
// 广告值——旧版服务器可能不回该字段）
export function mcpNegotiatedVersionOf(resultJson: string): string {
  try {
    const parsed: object = JSON.parse(resultJson);
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
      return '';
    }
    const rec: Record<string, Object> = parsed as Record<string, Object>;
    const versionVal: Object | undefined = rec['protocolVersion'];
    return typeof versionVal === 'string' ? versionVal : '';
  } catch (e) {
    return '';
  }
}

// ── tools/list 单页映射（分页循环在 McpClient；缓存项三字段与 common/McpText.ets
// McpToolCacheItem 同构——两件均零 import 叶子，接口刻意各持一份，字段序一致保证
// JSON 序列化产物可直接互认）──
export interface McpListedTool {
  name: string;
  description: string;
  inputSchema: string;
}

export interface McpToolsPage {
  tools: McpListedTool[];
  nextCursor: string;
}

// result → 单页映射：tools 缺失/非数组、条目非对象、条目缺 name、页内重名 = 抛中文错（P0-1
// 不静默——半份清单不造假象）；description 缺省 ''；inputSchema 对象序列化为串（$ref 展开在
// 消费侧接入，缓存恒存展开态的展开动作不在本件），非对象容 '' 透传（注册面兜底）；
// nextCursor 缺省 ''
export function mapToolsPage(resultJson: string): McpToolsPage {
  let rec: Record<string, Object> | null = null;
  try {
    const parsed: object = JSON.parse(resultJson);
    if (typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)) {
      rec = parsed as Record<string, Object>;
    }
  } catch (e) {
    rec = null;
  }
  if (rec === null) {
    throw new Error('工具清单结果格式异常，无法解析');
  }
  const toolsVal: Object | undefined = rec['tools'];
  if (toolsVal === undefined || toolsVal === null || !Array.isArray(toolsVal)) {
    throw new Error('工具清单缺少 tools 数组，无法解析');
  }
  const arr: object[] = toolsVal as object[];
  const tools: McpListedTool[] = [];
  for (let i: number = 0; i < arr.length; i++) {
    const item: object = arr[i];
    if (item === null || typeof item !== 'object' || Array.isArray(item)) {
      throw new Error('工具清单第 ' + (i + 1) + ' 项不是对象，无法解析');
    }
    const itemRec: Record<string, Object> = item as Record<string, Object>;
    const nameVal: Object | undefined = itemRec['name'];
    if (typeof nameVal !== 'string' || nameVal === '') {
      throw new Error('工具清单第 ' + (i + 1) + ' 项缺少名称，无法解析');
    }
    for (const existing of tools) {
      if (existing.name === nameVal) {
        throw new Error('工具清单存在重名工具：' + nameVal);
      }
    }
    const descVal: Object | undefined = itemRec['description'];
    const schemaVal: Object | undefined = itemRec['inputSchema'];
    const schemaOk: boolean = schemaVal !== undefined && schemaVal !== null
      && typeof schemaVal === 'object' && !Array.isArray(schemaVal);
    tools.push({
      name: nameVal,
      description: typeof descVal === 'string' ? descVal : '',
      inputSchema: schemaOk ? JSON.stringify(schemaVal) : ''
    });
  }
  const cursorVal: Object | undefined = rec['nextCursor'];
  const page: McpToolsPage = {
    tools: tools,
    nextCursor: typeof cursorVal === 'string' ? cursorVal : ''
  };
  return page;
}

// ── tools/call content 文本化（头注释第 5 条口径）──
export interface McpCallText {
  isError: boolean;
  text: string;
}

// result → { isError, text }：content 数组拼文本——text 项取原文；resource 项取内嵌 text、
// 无则记 uri；resource_link 记 uri；image/audio 只记占位说明（二进制 data 不外发——模型侧
// 无消费面也无必要放大体积）；未知类型记占位。content 空而 structuredContent 在场时回退序
// 列化该对象（2025-06-18+ 结构化结果兜底，头注释第 5 条）
export function mcpCallResultToText(resultJson: string): McpCallText {
  let rec: Record<string, Object> | null = null;
  try {
    const parsed: object = JSON.parse(resultJson);
    if (typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)) {
      rec = parsed as Record<string, Object>;
    }
  } catch (e) {
    rec = null;
  }
  if (rec === null) {
    // 防御态：坏 result 不该到达本函数（mcpEnsureResult 前置闸已挡 error/缺 result，但
    // result 内容畸形仍可能）——不炸链，按空文本回（isError=false，调用方按空回执处理）
    const empty: McpCallText = { isError: false, text: '' };
    return empty;
  }
  const isError: boolean = rec['isError'] === true;
  const parts: string[] = [];
  const contentVal: Object | undefined = rec['content'];
  if (contentVal !== undefined && contentVal !== null && Array.isArray(contentVal)) {
    const arr: object[] = contentVal as object[];
    for (const item of arr) {
      if (item === null || typeof item !== 'object' || Array.isArray(item)) {
        continue;
      }
      const itemRec: Record<string, Object> = item as Record<string, Object>;
      const typeVal: Object | undefined = itemRec['type'];
      const typeStr: string = typeof typeVal === 'string' ? typeVal : '';
      if (typeStr === 'text') {
        const textVal: Object | undefined = itemRec['text'];
        if (typeof textVal === 'string' && textVal !== '') {
          parts.push(textVal);
        }
      } else if (typeStr === 'resource') {
        const resVal: Object | undefined = itemRec['resource'];
        let handled: boolean = false;
        if (resVal !== undefined && resVal !== null && typeof resVal === 'object'
          && !Array.isArray(resVal)) {
          const resRec: Record<string, Object> = resVal as Record<string, Object>;
          const resText: Object | undefined = resRec['text'];
          if (typeof resText === 'string' && resText !== '') {
            parts.push(resText);
            handled = true;
          } else {
            const uriVal: Object | undefined = resRec['uri'];
            if (typeof uriVal === 'string' && uriVal !== '') {
              parts.push('[资源 ' + uriVal + ']');
              handled = true;
            }
          }
        }
        if (!handled) {
          parts.push('[资源内容]');
        }
      } else if (typeStr === 'resource_link') {
        const uriVal: Object | undefined = itemRec['uri'];
        parts.push(typeof uriVal === 'string' && uriVal !== ''
          ? '[资源链接 ' + uriVal + ']' : '[资源链接]');
      } else if (typeStr === 'image') {
        parts.push('[图片内容]');
      } else if (typeStr === 'audio') {
        parts.push('[音频内容]');
      } else {
        parts.push(typeStr !== '' ? '[不支持的内容类型 ' + typeStr + ']' : '[未知内容项]');
      }
    }
  }
  let text: string = parts.join('\n');
  if (text === '') {
    const structuredVal: Object | undefined = rec['structuredContent'];
    if (structuredVal !== undefined && structuredVal !== null && typeof structuredVal === 'object'
      && !Array.isArray(structuredVal)) {
      text = JSON.stringify(structuredVal);
    }
  }
  const outcome: McpCallText = { isError: isError, text: text };
  return outcome;
}
