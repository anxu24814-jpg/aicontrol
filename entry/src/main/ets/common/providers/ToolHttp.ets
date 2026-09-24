// HTTP 请求工具域（2026-09-19 任务书-HTTP请求工具-20260919 执行笔）：内置第 24 件工具
// http_request——通用 HTTP 工具（method + URL + headers + body），模型可向任意 http(s)
// 地址发请求调 REST API、触发 webhook、控局域网设备。本文件 = 传输层 + 执行器 + 确认链
// 预检，注册在 ToolTypes（本文件只供常量与 executor/preflight，照 ToolBrowse 域纪律——
// 契约自叶子 ToolContracts 引，禁自 ToolTypes 引防环；isHttpUrl 自 ToolBrowse 引——
// ToolBrowse → WebSearchParse 单向链无环，坑50）。
// 安全口径（任务书 §1.2 拍板）：
// · GET/HEAD/OPTIONS 直通（读向，风险与 scrape_web 等价）；POST/PUT/DELETE/PATCH 逐次
//   确认（写向——预检 httpRequestNeedsConfirm 返回确认二元组〔说明串＋档位，档位恒写操作〕，
//   工具轮弹确认卡，用户允许才执行；拒绝为终态回执，模型不得重试）。
// · 写确认档（★ 2026-09-20 HTTP 请求独立域笔）：设置 → 工具调用页「HTTP 写操作确认」选
//   「自动通过」时预检首行早退（回 null = 不弹卡），照 ToolBrowseAct 预检同形制；执行器侧
//   无第二道判据（本件不带批准戳，无戳闸），档位现读、切换即时生效。
// · 模型面写确认句（★ 2026-09-20 同笔随修）：desc 与 schema 的写确认表述一律按**默认档**
//   限定（by default / 默认每次都会请求用户确认）并点明用户可切「自动通过」——自动通过档下
//   「每次都会请求用户确认」不再为真，无条件陈述会让模型向用户复述不实描述。工具名与 seed
//   仍零改动。
// · 域归属（★ 2026-09-20 同上笔）：本件不属联网搜索域——不在 ToolTypes.WEB_DOMAIN_TOOLS，
//   联网搜索总开关与会话「联网」开关均不约束本件；启用面 = 助手工具页「HTTP 请求」卡开关
//  （声明层 defsFor 按助手启用清单过滤）。原执行器首行 isSearchServiceEnabled 守底行随域
//   归属一并移除（留着会把「联网搜索关着」翻译成「HTTP 请求不可用」的语义错位）。
// · 方法集白名单常量单源（HTTP_REQUEST_METHODS）——禁 http.RequestMethod[名字] 动态查表
//   （枚举含 TRACE/CONNECT，动态查表 = 集外方法静默放行，击穿写确认红线）。
// · 内网不拦截（端侧打内网 = 用户自有局域网，Home Assistant 类设备控制是正当用途；云元数据
//   面 SSRF 不存在于端侧无服务端架构）。
// 传输口径：一建一销 + finally destroy（成对释放红线）；usingCache 显式 false（坑33——官方
// 默认 true）；超时固定 30s 不给模型参数；maxLimit 2MB 接收闸（官方默认 5MB 的 STRING 解码
// 在 UI 线程内存翻倍且并行叠乘）；URL ≤2048 字符（url 键不可预算回缩，收口终态预算——自检
// P3-3）；请求体走 extraData string（全工程 12 处存量统一姿势）。
// 掐断（任务书 §2.5）：模块级在途登记 httpInFlight + httpAbortAll——ChatSendCtrl.abort 与
// disposeSilent 各调一行，在途 request 被 destroy 即以错误结算，停止键自最长 30s 等待缩至即时。
// ★ 请求日志（2026-09-24 扩面笔）：落点 = 传输层 httpRequestRaw 一处，覆盖本工具的全部调用
// ——掐断路径按 REQ_LOG_STATUS_CANCELED 记「已取消」终态，且**先记终态再 destroy**：destroy
// 引发的 promise 结算不得把它二次改写成「网络失败」（坑75 家族——用户主动中止不是故障，
// 误归因会把排查引向网络）。取消 id 由 canceledLogIds 传递，见 httpAbortAll 注释。
// 结果自控 ≤8192（自实现回缩循环——禁引 ToolBrowse.fitResultBudget，它只认 text/nodes 两键，
// 本域载荷键 body 不命中会原样超限；回缩按溢出量 +512 余量吸收转义膨胀，照 ToolBrowse
// 「\n→\\n 使预算失真」同源教训）。
import { http } from '@kit.NetworkKit';
import { ConfirmPrompt, CONFIRM_LEVEL_WRITE, ToolExecutor } from './ToolContracts';
import { isHttpWriteAutoApproveEnabled } from '../AppPreferences';
import { isHttpUrl } from './ToolBrowse';
import { httpKitErrorText } from './WebSearchParse';
import { reqLogBegin, reqLogEnd, reqLogSetResponseHeaders,
  REQ_LOG_STATUS_CANCELED } from '../ReqLog';

// ── 常量（全大写 ArkTS 规范；模型可见数字与 desc/schema 单源）──
// 方法集白名单（7 种 = schema enum 同源；集外一律 throw——见文件头安全口径）
export const HTTP_REQUEST_METHODS: string[] = ['GET', 'HEAD', 'OPTIONS', 'POST', 'PUT',
  'DELETE', 'PATCH'];
// 写方法集（确认卡弹卡范围——预检 httpRequestNeedsConfirm 的判定源）
export const HTTP_WRITE_METHODS: string[] = ['POST', 'PUT', 'DELETE', 'PATCH'];
// 超时（固定，不给模型参数——连接与读取同值）
const HTTP_TIMEOUT_MS: number = 30000;
// 接收上限（字节）：官方 maxLimit 默认 5MB 上限 100MB，超限抛 2300063；2MB 对文本 API
// 响应足够且防大响应内存翻倍
export const HTTP_MAX_LIMIT_BYTES: number = 2 * 1024 * 1024;
// 入参长度上限（字符）：无上限时模型塞大文本会灌进卡片展示、DB 落库与每轮重发的历史
export const HTTP_ARGS_MAX_CHARS: number = 100000;
// 分页默认与钳制（抄 MCP fetch 语义：默认 5000，钳 5000~8000）
const HTTP_MAX_LENGTH_DEFAULT: number = 5000;
const HTTP_MAX_LENGTH_MIN: number = 5000;
const HTTP_MAX_LENGTH_MAX: number = 8000;
// 结果预算（终态整串 ≤ 此值——外层 clipToolResult 兜底永不触发的自控目标）
const HTTP_RESULT_MAX_CHARS: number = 8192;
// URL 长度上限（字符）：url 键不可被预算回缩（fitHttpResult 只回缩 body），不设上限时
// 极端长 URL（入参上限内可占约 99KB）直接突破终态预算、外层 clipToolResult 对超限非 JSON
// 载荷 substring 硬切出坏 JSON——2048 收口后「终态整串 ≤8192」重新成立
//（2026-09-19 自检 P3-3）
export const HTTP_URL_MAX_CHARS: number = 2048;
// 预算回缩：转义膨胀余量（每轮回缩多收此量吸收 \n→\\n 等膨胀）与轮数上限（收敛保险）
const HTTP_BUDGET_ESCAPE_MARGIN: number = 512;
const HTTP_BUDGET_ROUNDS_MAX: number = 64;
// 确认串 URL 截断（超长 URL 截尾加省略号，防确认卡被撑爆）
const HTTP_CONFIRM_URL_MAX: number = 200;

// ── 在途登记与掐断（任务书 §2.1-3 / §2.5）──
// 在途项 = 请求句柄 + 该请求的日志条目 id（2026-09-24 请求日志扩面笔）：掐断时按 id 记
// 「已取消」终态，故 id 必须与句柄同行登记（分作两个数组必漂移）
interface HttpInFlight {
  req: http.HttpRequest;
  logId: string;
}

// 模块级在途请求表：请求发出前 push、finally 移除（与 destroy 同点，成对释放）
const httpInFlight: HttpInFlight[] = [];
// 掐断已按取消收尾的日志 id（httpRequestRaw 的 catch 据此**跳过二次改写**；该处消费即删，
// 无清理遗漏即无增长）。成对性：push 在 httpAbortAll、splice 在 catch 的取消分支
const canceledLogIds: string[] = [];

// 掐断全部在途请求（ChatSendCtrl.abort / disposeSilent 消费）：destroy 在途 request →
// promise 以错误结算 → lane 收尾守卫把卡转「已中止」。若真机实测 destroy 在途不结算
// promise，30s readTimeout 是终态兜底（任务书 §2.5 兜底口径）
// ★ 请求日志（2026-09-24 扩面笔）：**先记「已取消」终态再 destroy**（顺序不可换——destroy
// 触发结算，晚记会被 catch 的 -1 抢先覆写成「网络失败」）
// ★ 循环内两处各自包 try（2026-09-24 自检轮补）：条目已 pop 出表，循环体内任何一处抛错都会
// **静默放弃剩余在途请求**（停止键看着按了、剩下几条照跑满超时）——日志侧与 destroy 侧同为
// 傍路，任何异常都不得吃掉主职责；destroy 包 try 的理由见 httpRequestRaw 的同名注释
export function httpAbortAll(): void {
  while (httpInFlight.length > 0) {
    const item: HttpInFlight | undefined = httpInFlight.pop();
    if (item !== undefined) {
      try {
        if (item.logId !== '') {
          // 先记终态、再登记分家凭据（顺序对用户可见结果无影响——catch 在微任务里才跑；
          // 但记失败时前者留一条终态（catch 补 -1），后者会把条目钉死在「进行中」）
          reqLogEnd(item.logId, REQ_LOG_STATUS_CANCELED, 0, '', '');
          canceledLogIds.push(item.logId);
        }
      } catch (e) {
      }
      try {
        item.req.destroy();
      } catch (e) {
      }
    }
  }
}

// ── 传输层（照 WebSearch.httpGet 范式：一建一销 + finally destroy）──
// 网络层异常 throw（executeToolCall 统一包 {"error"}）——中文原因经叶子
// WebSearchParse.httpKitErrorText 统一取句（码表见该件 httpKitErrorMessage，与联网抓取
// 共用一份，单一来源）。
// body = null 表示不带请求体（GET/HEAD/OPTIONS 与未提供 body 的写方法）
// methodName 形参 = 方法名字符串（日志用）：枚举 → 名字的第二套判据不做（toRequestMethod
// 的反查必与白名单漂移），由调用方把它已有的字符串一并传入
async function httpRequestRaw(method: http.RequestMethod, methodName: string, url: string,
  headers: Record<string, string>, body: string | null): Promise<http.HttpResponse> {
  const req: http.HttpRequest = http.createHttp();
  const startedAt: number = Date.now();
  // 日志条目在**请求发出前**建（排障要看到「发出了什么」，含最终会超时的那些）；model 恒空串
  // ——本链是模型发起的工具调用，但请求本身不针对任何 AI 模型（同 ModelListApi 拉清单口径）
  const logId: string = reqLogBegin({
    source: 'HTTP 请求', model: '', method: methodName, url: url, headers: headers,
    body: body === null ? '' : body
  });
  httpInFlight.push({ req: req, logId: logId });
  try {
    const options: http.HttpRequestOptions = {
      method: method,
      header: headers,
      connectTimeout: HTTP_TIMEOUT_MS,
      readTimeout: HTTP_TIMEOUT_MS,
      usingCache: false,
      expectDataType: http.HttpDataType.STRING,
      maxLimit: HTTP_MAX_LIMIT_BYTES
    };
    if (body !== null) {
      options.extraData = body;
    }
    const resp: http.HttpResponse = await req.request(url, options);
    // 响应头回填须在 reqLogEnd 之前（凭据明细在 end 时即删，顺序颠倒少一层值级替换）
    reqLogSetResponseHeaders(logId, resp.header);
    // 终态：任何 HTTP 码都走这里（本层不抛非 2xx——由 execute 层按 status 组织回执）。
    // 成功不记响应正文（本功能边界：只记错误侧响应体），错误侧记尾部供归因
    const okCode: boolean = resp.responseCode >= 200 && resp.responseCode < 300;
    const tail: string = okCode ? '' :
      (typeof resp.result === 'string' ? resp.result : '');
    reqLogEnd(logId, resp.responseCode, Date.now() - startedAt, '', tail);
    return resp;
  } catch (e) {
    // 网络层异常 → 中文原因（叶子纯函数 httpKitErrorText）：旧实现
    // `throw e instanceof Error ? e : new Error(String(e))` 对 BusinessError（接口非类）
    // 落到 String(e)，真机实证产出 {"error":"[object Object]"}——本行即该缺陷的收口点
    // ★ 零秒防御（2026-09-21 八百三十八节，与 BrowseWeb 笔 B 同形）：常量若降到 500 ms 以下，
    // Math.round 得 0 ⇒ 码表 2300028 报「请求超时（0 秒）」；下限钳 1 秒。
    const netMsg: string = httpKitErrorText(e, Math.max(1, Math.round(HTTP_TIMEOUT_MS / 1000)));
    // 取消与真网络错分家（2026-09-24 请求日志扩面笔，坑75 家族）：掐断路径已在 httpAbortAll
    // 记过「已取消」终态，此处**跳过**（reqLogEnd 是按 id 覆写，再记就把取消改写成网络失败）；
    // 该 id 消费即删（成对，见 canceledLogIds 声明处）
    const cancelIdx: number = canceledLogIds.indexOf(logId);
    if (logId !== '' && cancelIdx >= 0) {
      canceledLogIds.splice(cancelIdx, 1);
    } else {
      reqLogEnd(logId, -1, Date.now() - startedAt, netMsg, '');
    }
    throw new Error(netMsg);
  } finally {
    const idx: number = httpInFlight.findIndex((item: HttpInFlight): boolean =>
      item.req === req);
    if (idx >= 0) {
      httpInFlight.splice(idx, 1);
    }
    // destroy 包 try（2026-09-24 自检轮补，同 ModelListApi / TitleApi / KeyConnectTester /
    // WebDavApi 四处先例）：裸 destroy 抛错会从 finally 穿出，把**已拿到的响应**改写成失败
    // （本仓 KeyConnectTester 与 ModelListApi 两处自检轮实锤过同类；本工具是调用最密的一条链）
    try {
      req.destroy();
    } catch (e) {
    }
  }
}

// 方法名 → 官方枚举（白名单判定后的翻译层——静态映射不查表，见文件头安全口径；
// 入参已在白名单内，default 分支理论不可达的防御）
function toRequestMethod(method: string): http.RequestMethod {
  switch (method) {
    case 'GET':
      return http.RequestMethod.GET;
    case 'HEAD':
      return http.RequestMethod.HEAD;
    case 'OPTIONS':
      return http.RequestMethod.OPTIONS;
    case 'POST':
      return http.RequestMethod.POST;
    case 'PUT':
      return http.RequestMethod.PUT;
    case 'DELETE':
      return http.RequestMethod.DELETE;
    case 'PATCH':
      return http.RequestMethod.PATCH;
    default:
      throw new Error('method 只支持 GET、HEAD、OPTIONS、POST、PUT、DELETE、PATCH');
  }
}

// 响应头取值（键名按小写归一匹配——官方返回头键大小写不保证，native 侧按服务器原样保存、
// 无归一化契约）。原实现「先小写直查再原名直查」在 name 恒为小写字面量时退化为同键重复
// 查找、混合形态键（如 'Content-Type'）读空致文本分型整体失效——2026-09-19 自检 P2-1
// 修复：遍历键做 toLowerCase 对比，任一大小写形态都命中。导出供 ToolHttp 直跑副本
// 执行级验证（自检 P3-1）
export function readHeader(headers: Object, name: string): string {
  const rec = headers as Record<string, Object>;
  const target: string = name.toLowerCase();
  for (const key of Object.keys(rec)) {
    if (key.toLowerCase() === target) {
      const value: Object = rec[key];
      if (typeof value === 'string') {
        return value;
      }
    }
  }
  return '';
}

// 文本内容型判定（命中才返回正文；其余按二进制只回元信息——绝不把二进制按文本硬塞）。
// 导出供 ToolHttp 直跑副本执行级验证（自检 P3-1）
export function isTextContentType(contentType: string): boolean {
  const lower: string = contentType.toLowerCase().split(';')[0].trim();
  if (lower.startsWith('text/')) {
    return true;
  }
  return lower === 'application/json' || lower.endsWith('+json') ||
    lower === 'application/xml' || lower.endsWith('+xml') ||
    lower === 'application/javascript' ||
    lower === 'application/x-www-form-urlencoded';
}

// 结果预算回缩（任务书 §2.1-9 自实现）：整串超预算时 body 按溢出量 +512 余量回缩重序列化，
// 循环至收敛（≤64 轮）或 body 耗尽（置 truncated 与中文说明）。pieceStart = 本次切片在全文
// 中的起点——回缩同步回退 nextStartIndex，续读连续性不破（照 ToolBrowse.fitResultBudget
// 回缩时同步回退 offset 的同款语义）。导出供 ToolHttp 直跑副本执行级验证（自检 P3-1）
export function fitHttpResult(rec: Record<string, Object>, pieceStart: number): string {
  let json: string = JSON.stringify(rec);
  if (json.length <= HTTP_RESULT_MAX_CHARS) {
    return json;
  }
  const bodyFull: string = rec['body'] as string;
  let keep: number = bodyFull.length;
  for (let round: number = 0; round < HTTP_BUDGET_ROUNDS_MAX && keep > 0; round++) {
    keep = Math.max(0, keep - (json.length - HTTP_RESULT_MAX_CHARS + HTTP_BUDGET_ESCAPE_MARGIN));
    if (keep === 0) {
      break;
    }
    rec['body'] = bodyFull.substring(0, keep);
    rec['truncated'] = true;
    rec['nextStartIndex'] = pieceStart + keep;
    rec['note'] = '正文已截断，用 start_index 续读';
    json = JSON.stringify(rec);
    if (json.length <= HTTP_RESULT_MAX_CHARS) {
      return json;
    }
  }
  // body 耗尽（或轮数保险触顶）仍超：正文置空 + 终态说明，元信息照回——url 已由
  // HTTP_URL_MAX_CHARS 收口（自检 P3-3），本分支为轮数保险的不可达兜底
  rec['body'] = '';
  rec['truncated'] = true;
  rec['nextStartIndex'] = pieceStart;
  rec['note'] = '正文已截断，用 start_index 续读';
  return JSON.stringify(rec);
}

// ── 执行器 ──
export class HttpRequestExecutor implements ToolExecutor {
  execute(argsJson: string): Promise<string> {
    // ★ 2026-09-20 HTTP 请求独立域笔：原「联网总开关守底行」随域归属移除——本件不在
    // WEB_DOMAIN_TOOLS，联网搜索总开关与本件无关；启用面由声明层（defsFor 按助手工具页
    // 「HTTP 请求」卡开关过滤）承担，执行器无会话/清单上下文可判，不设第二道
    if (argsJson.length > HTTP_ARGS_MAX_CHARS) {
      return Promise.resolve(JSON.stringify({ error: '请求参数过长。请减小请求参数后重试' }));
    }
    let url: string = '';
    let method: string = 'GET';
    let body: string = '';
    let maxLength: number = HTTP_MAX_LENGTH_DEFAULT;
    let startIndex: number = 0;
    const headers: Record<string, string> = {};
    try {
      const parsed = JSON.parse(argsJson) as Record<string, Object>;
      const urlRaw: Object = parsed['url'];
      if (typeof urlRaw === 'string') {
        url = urlRaw.trim();
      }
      const methodRaw: Object = parsed['method'];
      if (typeof methodRaw === 'string' && methodRaw.trim() !== '') {
        method = methodRaw.trim().toUpperCase();
      }
      const headersRaw: Object = parsed['headers'];
      if (typeof headersRaw === 'object' && headersRaw !== null) {
        const rec = headersRaw as Record<string, Object>;
        for (const key of Object.keys(rec)) {
          const value: Object = rec[key];
          if (typeof value === 'string') {
            headers[key] = value;
          } else {
            // 非字符串头值 = schema 违约（additionalProperties string），错误回执点名违规键。
            // 收口取舍（2026-09-19 自检 P3-4）：不 String() 收编——对象值会落 '[object Object]'
            // 垃圾头；静默丢弃则请求缺头照发、模型与用户均无感知（P0-1 禁静默失败）
            return Promise.resolve(JSON.stringify({
              error: '请求头 ' + key + ' 的值必须是字符串。请修正后重试' }));
          }
        }
      }
      const bodyRaw: Object = parsed['body'];
      if (typeof bodyRaw === 'string') {
        body = bodyRaw;
      }
      const maxRaw: Object = parsed['max_length'];
      if (typeof maxRaw === 'number' && Number.isFinite(maxRaw)) {
        maxLength = maxRaw;
      }
      const startRaw: Object = parsed['start_index'];
      if (typeof startRaw === 'number' && Number.isFinite(startRaw)) {
        startIndex = startRaw;
      }
    } catch (e) {
      return Promise.resolve(JSON.stringify({ error: '参数解析失败' }));
    }
    // 方法白名单（集外 throw——禁动态查表放行，见文件头安全口径）与 URL 协议白名单
    if (!HTTP_REQUEST_METHODS.includes(method)) {
      throw new Error('method 只支持 GET、HEAD、OPTIONS、POST、PUT、DELETE、PATCH');
    }
    if (url === '' || !isHttpUrl(url)) {
      throw new Error('仅支持 http 与 https 地址');
    }
    // URL 长度上限（自检 P3-3）：url 键无法被预算回缩，超长 URL 会突破 8192 终态预算、
    // 外层 clipToolResult 硬切出坏 JSON——错误回执拦下使终态声明重新成立
    if (url.length > HTTP_URL_MAX_CHARS) {
      return Promise.resolve(JSON.stringify({
        error: 'URL 过长。请缩短 URL 或减少查询参数后重试' }));
    }
    // body 语义：GET/HEAD 不接受请求体（不发请求，回执指引改 POST）；其余方法按提供发送
    if (body !== '' && (method === 'GET' || method === 'HEAD')) {
      return Promise.resolve(JSON.stringify({
        error: 'GET/HEAD 不接受请求体。如需提交数据请用 POST' }));
    }
    // 分页钳制：max_length 钳 5000~8000；start_index 负数归零（上界在拿到全文后钳）
    let maxChars: number = Math.round(maxLength);
    if (maxChars < HTTP_MAX_LENGTH_MIN) {
      maxChars = HTTP_MAX_LENGTH_MIN;
    }
    if (maxChars > HTTP_MAX_LENGTH_MAX) {
      maxChars = HTTP_MAX_LENGTH_MAX;
    }
    let start: number = Math.round(startIndex);
    if (start < 0) {
      start = 0;
    }
    // 非 ASCII URL 先整体编码（官方：URL 含非 ASCII 抛 2300003——模型给中文 query 的 URL
    // 是高频场景）。已收口（2026-09-21 B-14）：encodeURI 对既有 %XX 段的 % 二次转义（→ %25）
    // 以 .replace(/%25/g, '%') 还原——对既有 %20 段 / 裸 % / 字面 %25 三形态实测零改写，
    // 等价于「仅对非 ASCII 段编码」；与 providers/WebSearch.fetchUrlContent 同口径（两域
    // 注释互指，改则同改）
    let requestUrl: string = url;
    if (/[^\x00-\x7F]/.test(requestUrl)) {
      requestUrl = encodeURI(requestUrl).replace(/%25/g, '%');
    }
    const enumMethod: http.RequestMethod = toRequestMethod(method);
    return httpRequestRaw(enumMethod, method, requestUrl, headers,
      body !== '' ? body : null)
      .then((resp: http.HttpResponse): string => {
        const status: number = resp.responseCode;
        const contentType: string = readHeader(resp.header, 'content-type');
        if (!isTextContentType(contentType)) {
          // 二进制：只回元信息（绝不把二进制按文本硬塞）
          const lenText: string = readHeader(resp.header, 'content-length');
          const contentLength: number = parseInt(lenText, 10);
          return JSON.stringify({
            url: url, status: status, contentType: contentType,
            contentLength: Number.isFinite(contentLength) ? contentLength : 0,
            note: '二进制内容，不返回正文' });
        }
        const full: string = typeof resp.result === 'string' ? resp.result : String(resp.result);
        const total: number = full.length;
        if (start > total) {
          start = total;
        }
        const end: number = Math.min(total, start + maxChars);
        const piece: string = full.substring(start, end);
        const truncated: boolean = end < total;
        const rec: Record<string, Object> = {};
        rec['url'] = url;
        rec['status'] = status;
        rec['contentType'] = contentType;
        rec['body'] = piece;
        rec['totalLength'] = total;
        rec['truncated'] = truncated;
        rec['nextStartIndex'] = end;
        if (truncated) {
          rec['note'] = '正文已截断，用 start_index 续读';
        }
        return fitHttpResult(rec, start);
      });
  }
}

// ── 注册面常量与预检（ToolTypes 注册时引用）──

export const HTTP_REQUEST_DESC: string =
  'Send a raw HTTP request to any http(s) URL and return status, content type and body.\n' +
  'Use it for REST API calls, webhooks and JSON endpoints that need a specific method,\n' +
  'custom headers or a request body. For reading normal web page content prefer\n' +
  'scrape_web (static pages) or browse_open (JS-rendered pages): they extract readable\n' +
  'text, this tool does not. POST/PUT/DELETE/PATCH are write operations: by default\n' +
  'each call asks the user for confirmation, so batch what you need and do not retry\n' +
  'on denial. If the user turned confirmations off, write calls are sent directly.\n' +
  'Responses are capped (max_length) and can be paged with start_index. Binary\n' +
  'responses return metadata only. Keep request bodies small (a few KB). Timeouts\n' +
  'are fixed at 30 seconds.';

export const HTTP_REQUEST_SCHEMA: string =
  '{"type":"object","properties":{' +
  '"url":{"type":"string","description":"完整的 http 或 https URL，不含其他协议。"},' +
  '"method":{"type":"string","enum":["GET","POST","PUT","DELETE","PATCH","HEAD","OPTIONS"],' +
  '"description":"HTTP 方法。省略时为 GET。POST PUT DELETE PATCH 属写操作，默认每次都会请求用户确认。用户可在设置里切到自动通过，切到后不再询问。"},' +
  '"headers":{"type":"object","additionalProperties":{"type":"string"},' +
  '"description":"自定义请求头，键值对。POST JSON 请求应带 Content-Type application/json。不要把密钥放进 URL 查询串，密钥应放请求头。"},' +
  '"body":{"type":"string","description":"请求体文本，仅 POST PUT PATCH 需要。GET HEAD 会忽略并回执提示。"},' +
  '"max_length":{"type":"integer","description":"返回正文的最大字符数，默认 5000，上限 8000。"},' +
  '"start_index":{"type":"integer","description":"从正文该字符下标开始返回，用于上一次被截断后的分页续读。"}},' +
  '"required":["url"]}';

// 确认链预检（任务书 §2.1-10）：返回待确认二元组——null = 直通，非 null = 需弹确认卡，
// text 即卡面说明、level 恒 CONFIRM_LEVEL_WRITE（本件无不可逆档：写方法均可在对方服务器
// 侧留有痕迹但无「删除类」语义，档位恒写操作）。★ 全包 try/catch，任何异常一律返 null
//（预检抛错 = beginToolRound 无 catch → 整轮静默死、发送态永挂——照 browseActNeedsConfirm
// 内部多处 catch 的同款防线）。判定 = method（缺省 GET）∈ 写方法集；解析失败也返 null
//（执行器会出参数错误回执）。
// ★ 写确认档早退（2026-09-20 HTTP 请求独立域笔）：设置 → 工具调用页「HTTP 写操作确认」选
// 「自动通过」时首行回 null——不弹卡，写请求与读方法同路直发；现读 = 切换即时生效，下一个
// 请求按新值，已弹出的确认卡不受影响仍需作答（照 browseActNeedsConfirm 预检同形制）
// ★ 串形态（2026-09-20 D1-5 修复）：只写方法与网址，不再以「助手请求发送网络请求」起头——
// 卡面标题已渲染同一句（笔 A 起迁 ChatToolCard.buildConfirmHead），跟起头会造成逐字重复
// ★ 形态变更（2026-09-20 审批卡视觉迁移笔 A）：返回类型自「串（'' = 直通）」改 ConfirmPrompt
// | null——档位字段供卡面档位徽章渲染，见 ToolContracts.ConfirmPrompt 头注释
export async function httpRequestNeedsConfirm(argsJson: string): Promise<ConfirmPrompt | null> {
  try {
    if (isHttpWriteAutoApproveEnabled()) {
      return null;
    }
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    const methodRaw: Object = parsed['method'];
    const urlRaw: Object = parsed['url'];
    const method: string = typeof methodRaw === 'string' && methodRaw.trim() !== '' ?
      methodRaw.trim().toUpperCase() : 'GET';
    if (!HTTP_WRITE_METHODS.includes(method)) {
      return null;
    }
    if (typeof urlRaw !== 'string' || urlRaw.trim() === '') {
      return null;
    }
    const url: string = urlRaw.trim();
    const shown: string = url.length > HTTP_CONFIRM_URL_MAX ?
      url.substring(0, HTTP_CONFIRM_URL_MAX) + '…' : url;
    return { text: '将发送 ' + method + ' 请求到 ' + shown, level: CONFIRM_LEVEL_WRITE };
  } catch (e) {
    return null;
  }
}
