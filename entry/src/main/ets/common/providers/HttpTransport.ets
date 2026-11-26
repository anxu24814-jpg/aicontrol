// HTTP 工具域·传输层与在途掐断域（自 ToolHttp.ets 域级最小拆分）。职责一句话 =「把请求发
// 出去、把响应拿回来」——同步整包（httpRequestRaw）与流式窗口（httpRequestStream）两条传输
// 路 + 在途登记与两掐断入口。方法体自 ToolHttp 原样搬迁零行为变化；掐断链随传输层同迁——
// 在途登记的就是传输层的 req，登记与销毁必须同居一域。ToolHttp 以 import 后再 export 转出
// 两掐断入口，ChatSendCtrl 存量 import 零改动。
// · 代理接线：两条传输路的 options 构造后、发起前统一调 applyEffectiveProxy——网络设置代理
//   三档对工具请求生效（消费面锚点 = 本函数内、request 调用前，与 BalanceApi / ChatStreamBase
//   等八链同姿势）。system 档零介入 = 与接线前行为逐字一致。
// · 流式窗口读取：requestInStream + dataReceive/dataEnd/headersReceive 三回调自攒
//  （ChatStreamBase 真机实锤同款范式；坑19——dataEnd 与 Promise 落定两序都可能，完成判定 =
//   两者齐）。窗口参数常量与 SSE 分帧在叶子 HttpSse（本件只做传输与计时）；收口强度分流：
//   窗口到量（时长 / 条数 / 字节）= 软停止（正常结果形态）；idle 8 秒无新数据 = 硬中止（回执
//   带专用错误）；取消恒优先——计时器回调先查 canceledLogIds，用户掐断永不误报成超时（坑75
//   家族「先记取消终态再 destroy」同源纪律）。
// · 成对释放：on 三件 ↔ off 三件 + destroy + 清计时器统一 finalize 单点（主动软停先注销订阅
//   再 destroy——防窗口到量后回调继续灌；注销与 destroy 均包 try，任何一处抛错不得吃掉已收
//   结果）。
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { reqLogBegin, reqLogEnd, reqLogSetResponseHeaders,
  REQ_LOG_SOURCE_HTTP, REQ_LOG_STATUS_CANCELED } from '../ReqLog';
import { httpKitErrorCode, httpKitErrorText } from './WebSearchParse';
import { applyEffectiveProxy } from './RequestIdentity';
import { HTTP_STREAM_IDLE_MS, SseFrameParser } from './HttpSse';
import { HTTP_DOWNLOAD_MAX_LIMIT_BYTES } from './HttpBinary';
import { readHeader } from './HttpReceipt';

// 重定向上限：官方默认 30 跳，收紧到 5——正常 API 跳转链 1~3 跳足够，防长跳转链拖长请求；
// 超限官方抛 2300047（码表已收）。export 为后补（McpClient 按已导出前提 import），值与语义
// 零变化
export const HTTP_MAX_REDIRECTS: number = 5;
// 接收上限（字节；自 ToolHttp 原样迁入——传输层常量随传输域走，防「叶子反向引消费件」环）：
// 官方 maxLimit 默认 5MB 上限 100MB，超限抛 2300063；2MB 对文本 API 响应足够且防大响应内存
// 翻倍（download 路 20MB 档单源 HttpBinary）
export const HTTP_MAX_LIMIT_BYTES: number = 2 * 1024 * 1024;

// ── 在途登记与掐断（自 ToolHttp 原样迁入）──
// 在途项 = 请求句柄 + 该请求的日志条目 id（掐断时按 id 记「已取消」终态，id 必须与句柄同行
// 登记——分作两个数组必漂移）；runId = 请求所属运行——按 run 定向取消的登记维度
interface HttpInFlight {
  req: http.HttpRequest;
  logId: string;
  runId: string;
}

// 模块级在途请求表：请求发出前 push、finalize 移除（与 destroy 同点，成对释放）
const httpInFlight: HttpInFlight[] = [];
// 掐断已按取消收尾的日志 id（catch 据此**跳过二次改写**；该处消费即删，无清理遗漏即无增长；
// 流式路径的计时器回调以 indexOf 只读探查——消费权仍在 catch）。push 在掐断路径、splice 在
// 取消分支（成对）
const canceledLogIds: string[] = [];

// 掐断全部在途请求（★ 现役消费路径已改为定向入口 httpAbortRun——ChatSendCtrl.abort /
// disposeSilent 不再走本入口；本入口保留为全进程退出的独立明确入口、现无调用方，勿删）：
// destroy 在途 request → promise 以错误结算 → lane 收尾守卫把卡转「已中止」。若真机实测
// destroy 在途不结算 promise，30s readTimeout 是终态兜底。
// ★ 请求日志：**先记「已取消」终态再 destroy**（顺序不可换——destroy 触发结算，晚记会被
// catch 的 -1 抢先覆写成「网络失败」）。★ 循环内两处各自包 try：条目已 pop 出表，循环体内
// 任何一处抛错都会**静默放弃剩余在途请求**（停止键看着按了、剩下几条照跑满超时）——日志侧
// 与 destroy 侧同为傍路，任何异常都不得吃掉主职责
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

// 按 run 定向取消：单页停止/销毁只掐断**本 run** 发起的在途请求——分栏态他会话（或本会话
// 新 run）的在途不受连带（原 ChatSendCtrl 无条件 httpAbortAll 会误伤 B 会话，真机实锤）。
// 匹配集为空 = 本 run 无在途，零动作零开销。消费方：ChatSendCtrl.abort / disposeSilent
export function httpAbortRun(runId: string): void {
  if (runId === '') {
    return; // 空身份不掐任何请求（fail-safe 不越界）
  }
  const hits: HttpInFlight[] = [];
  httpInFlight.forEach((item: HttpInFlight): void => {
    if (item.runId === runId) {
      hits.push(item);
    }
  });
  for (const item of hits) {
    const idx: number = httpInFlight.indexOf(item);
    if (idx >= 0) {
      httpInFlight.splice(idx, 1);
    }
    try {
      if (item.logId !== '') {
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

// ── 传输层（照 WebSearch.httpGet 范式：一建一销 + finally destroy）──
// 失败不再上抛：原实现 catch 里 throw 中文句，异常对象里的 kit 码（retriable 分类的唯一依据）
// 在抛出行即丢——本层返回**结果二元**（resp 或 码 + 句），由执行器组装结构化失败回执。中文
// 句与码同出叶子 WebSearchParse（httpKitErrorText / httpKitErrorCode 同源一份码表，与联网
// 抓取共用）。
// body = null 表示不带请求体（GET/HEAD/OPTIONS 与未提供 body 的写方法）。
// 发送面形态：textBody 照旧；binaryBody = file 直传路（ArrayBuffer 进 options.body）；
// multiFormData = multipart 路（官方 multiFormDataList 通道，Content-Type 由执行器补、
// boundary 系统生成禁自拼）；asDownload = download 路（ARRAY_BUFFER + maxLimit 20MB，响应
// ArrayBuffer 落工作区）；asBytes = 脚本联网桥路（ARRAY_BUFFER + 2MB 档，不落盘，正文按原始
// 字节回传——文本解码单源在 native 侧，防第二套解码路径）。三态互斥（body/file/multipart
// 模型参数级已拦）。
// 日志面：textBody 原样记；binaryBody / multiFormData 的文件内容**零进日志**（文件是用户
// 数据非模型生成，reqLogBegin 只收模型原始输入面）
export interface HttpSendPayload {
  textBody: string | null;
  binaryBody: ArrayBuffer | null;
  multiFormData: http.MultiFormData[] | null;
  asDownload: boolean;
  asBytes: boolean;
}
// methodName 形参 = 方法名字符串（日志用）：枚举 → 名字的第二套判据不做（toRequestMethod
// 的反查必与白名单漂移），由调用方把它已有的字符串一并传入。timeoutMs 形参 = 生效超时
//（执行器经 resolveHttpTimeoutMs 解析后传入），连接与读取同值 + 错误文案秒数同源
// ★ 日志面/发送面分离：url/headers = 发送面（凭据注入后的真值——由执行器替换定稿后传入）；
// logUrl/logHeaders = 日志面（模型原始输入，{{名称}} 记号形态）。reqLogBegin 只收日志面——
// **凭据明文零进请求日志**（红线）。条件缓存头〔If-None-Match 等〕的写入点在执行器侧、
// 先于日志面入参定稿，故随发送面走**且同进日志面**——验证器是对方下发的非敏感值，进日志
// 利于 304 排障。Cookie 回带头同守此线——回带头只进发送面（传输 options），日志面零回带头
//（守卫钉见 assert-tool-domain）。无凭据场景两套同引用，行为与拆分前逐字一致
export interface HttpRawOutcome {
  // 响应（网络层成功拿到响应即非空；4xx/5xx 也是响应，不属失败面）
  resp: http.HttpResponse | null;
  // 网络层失败的 kit 码（-1 = 无码；仅 resp === null 时有意义）
  errorCode: number;
  // 网络层失败的中文句（仅 resp === null 时有意义）
  errorText: string;
  // 本次失败是否为用户掐断（掐断链凭据 canceledLogIds 命中即 true）——后台长任务据此落
  // cancelled 终态（此前取消被当普通网络失败，状态机 cancelled 不可达）
  cancelled: boolean;
}

export async function httpRequestRaw(method: http.RequestMethod, methodName: string, url: string,
  headers: Record<string, string>, payload: HttpSendPayload, runId: string,
  timeoutMs: number, logUrl: string, logHeaders: Record<string, string>,
  logSource: string = REQ_LOG_SOURCE_HTTP): Promise<HttpRawOutcome> {
  const req: http.HttpRequest = http.createHttp();
  const startedAt: number = Date.now();
  // 日志条目在**请求发出前**建（排障要看到「发出了什么」，含最终会超时的那些）；model 恒空串
  //（本链是模型发起的工具调用，但请求不针对任何 AI 模型）。日志面收 logUrl/logHeaders（模型
  // 原始输入——凭据真值不进日志；条件缓存头同进日志，见 HttpRawOutcome 前注释）。来源标签 =
  // logSource 形参（缺省 REQ_LOG_SOURCE_HTTP，脚本联网桥路传 REQ_LOG_SOURCE_SCRIPT——单一
  // 来源仍在 ReqLog，标签改名不会造出「筛不到」的静默失配）
  const logId: string = reqLogBegin({
    source: logSource, model: '', method: methodName, url: logUrl, headers: logHeaders,
    body: payload.textBody === null ? '' : payload.textBody
  });
  httpInFlight.push({ req: req, logId: logId, runId: runId });
  try {
    const options: http.HttpRequestOptions = {
      method: method,
      header: headers,
      connectTimeout: timeoutMs,
      readTimeout: timeoutMs,
      // 重定向上限收紧（官方默认 30——超限抛 2300047 且回执含跳数）
      maxRedirects: HTTP_MAX_REDIRECTS,
      usingCache: false,
      // download / asBytes 路取二进制正文（ArrayBuffer）；asBytes 上限与文本路同走 2MB
      //（HTTP_MAX_LIMIT_BYTES 单源复用，不新立常量）
      expectDataType: (payload.asDownload || payload.asBytes) ?
        http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING,
      maxLimit: payload.asDownload ? HTTP_DOWNLOAD_MAX_LIMIT_BYTES : HTTP_MAX_LIMIT_BYTES
    };
    if (payload.textBody !== null) {
      options.extraData = payload.textBody;
    }
    if (payload.binaryBody !== null) {
      options.body = payload.binaryBody;
    }
    if (payload.multiFormData !== null) {
      options.multiFormDataList = payload.multiFormData;
    }
    // 代理兜底写入（消费面锚点在本函数内、request 调用前；system 档零介入 = options 原样）
    applyEffectiveProxy(options);
    const resp: http.HttpResponse = await req.request(url, options);
    // 响应头回填须在 reqLogEnd 之前（凭据明细在 end 时即删，顺序颠倒少一层值级替换）
    reqLogSetResponseHeaders(logId, resp.header);
    // 终态：任何 HTTP 码都走这里（本层不抛非 2xx——由 execute 层按 status 组织回执）。
    // 成功不记响应正文（本功能边界：只记错误侧响应体），错误侧记尾部供归因
    const okCode: boolean = resp.responseCode >= 200 && resp.responseCode < 300;
    const tail: string = okCode ? '' :
      (typeof resp.result === 'string' ? resp.result : '');
    reqLogEnd(logId, resp.responseCode, Date.now() - startedAt, '', tail);
    const outcome: HttpRawOutcome = { resp: resp, errorCode: -1, errorText: '', cancelled: false };
    return outcome;
  } catch (e) {
    // 网络层异常 → 中文原因（叶子 httpKitErrorText）：旧实现 throw e instanceof Error 对
    // BusinessError（接口非类）落到 String(e)，真机实证产出 {"error":"[object Object]"}——
    // 本行即该缺陷的收口点。★ 零秒防御：生效超时若降到 500ms 以下，Math.round 得 0 ⇒ 码表
    // 2300028 报「请求超时（0 秒）」；下限钳 1 秒（钳制下限 5 秒使其理论不可达，防御保留）
    const netMsg: string = httpKitErrorText(e, Math.max(1, Math.round(timeoutMs / 1000)));
    // 码随句一起带走（retriable 分类的输入；与取句同件同源）
    const netCode: number = httpKitErrorCode(e);
    // 取消与真网络错分家（坑75 家族）：掐断路径已记过「已取消」终态，此处**跳过**（reqLogEnd
    // 是按 id 覆写，再记就把取消改写成网络失败）；该 id 消费即删（成对）。取消判定随
    // cancelled 字段外传（后台长任务终态归类消费）
    const cancelIdx: number = canceledLogIds.indexOf(logId);
    const cancelHit: boolean = logId !== '' && cancelIdx >= 0;
    if (cancelHit) {
      canceledLogIds.splice(cancelIdx, 1);
    } else {
      reqLogEnd(logId, -1, Date.now() - startedAt, netMsg, '');
    }
    const failed: HttpRawOutcome = { resp: null, errorCode: netCode, errorText: netMsg,
      cancelled: cancelHit };
    return failed;
  } finally {
    const idx: number = httpInFlight.findIndex((item: HttpInFlight): boolean =>
      item.req === req);
    if (idx >= 0) {
      httpInFlight.splice(idx, 1);
    }
    // destroy 包 try（同 ModelListApi / TitleApi 等先例）：裸 destroy 抛错会从 finally 穿出，
    // 把**已拿到的响应**改写成失败（本仓自检轮实锤过同类；本工具是调用最密的一条链）
    try {
      req.destroy();
    } catch (e) {
    }
  }
}

// ── 流式窗口传输（同步路 httpRequestRaw 之上的第二条传输路）──
// 窗口闸形态：windowMs = 总窗口（自首字节起算，到点软停止——首字节前的等待由 kit readTimeout
// 承担不双计）；maxEvents = 事件条数上限（仅 event-stream 生效，非 SSE 传 0）；windowBytes =
// 收集字节硬顶（恒生效）。三闸任一先到 = 软停止 + terminalReason 标记；idle 超时 = 硬中止
export interface HttpStreamWindow {
  windowMs: number;
  maxEvents: number;
  windowBytes: number;
}

// 流式传输结果。terminalReason 收口归类：'' = 未收口（异常态，不该被 resolve）/ 'completed'
//（dataEnd 自然收尾）/ 'window' / 'events' / 'bytes'（软停止，返回已收内容是正常结果）/
// 'idle' = 硬中止（调用方组专用错误回执）；'cancelled' = 用户掐断；'error' = 网络层失败
//（失败即终局，无后续数据可等）。★ 流式链拿不到 HttpResponse（requestInStream 只回状态码）
// ——响应头走 headersReceive 事件回传，公共回执字段由执行器自本 outcome 组装，
// connectionExtraInfo 组（跳数 / 协议 / TLS）流式链不回
export interface HttpStreamOutcome {
  settled: boolean; // requestInStream Promise 已落定（true 才 resolve——完成判定 = 落定 + 收口两者齐，坑19）
  statusOk: boolean; // Promise 正常 resolve（拿到状态码）
  status: number; // HTTP 状态码（statusOk 时有效）
  errorCode: number; // 网络层失败 kit 码（!statusOk 且非取消时有效）
  errorText: string;
  header: Object; // headersReceive 最后一次回传的响应头（最终响应的头——逐跳覆盖）
  headerSeen: boolean;
  text: string; // 已收文本（decode stream 模式增量拼接，窗口闸内）
  bytes: number;
  events: string[]; // event-stream 时已收事件 data 净值序（非 SSE 恒空）
  isEventStream: boolean;
  terminalReason: string;
  idleElapsedMs: number; // idle 硬中止时已停顿时长（回执 idleMs 字段值；非 idle 恒 0）
}

export function httpRequestStream(method: http.RequestMethod, methodName: string, url: string,
  headers: Record<string, string>, payload: HttpSendPayload, runId: string,
  timeoutMs: number, window: HttpStreamWindow, logUrl: string,
  logHeaders: Record<string, string>,
  logSource: string = REQ_LOG_SOURCE_HTTP): Promise<HttpStreamOutcome> {
  return new Promise<HttpStreamOutcome>((resolve: (out: HttpStreamOutcome) => void) => {
    const req: http.HttpRequest = http.createHttp();
    const startedAt: number = Date.now();
    // 日志口径与 httpRequestRaw 同源（请求发出前建条目；日志面收模型原始输入——凭据与
    // Cookie 回带头零进日志）。logSource 形参化同 httpRequestRaw（桥路现不走流式，但两路
    // 口径同形，防将来新调用方漏传时无处收口）
    const logId: string = reqLogBegin({
      source: logSource, model: '', method: methodName, url: logUrl, headers: logHeaders,
      body: payload.textBody === null ? '' : payload.textBody
    });
    httpInFlight.push({ req: req, logId: logId, runId: runId });
    // ── 收口状态（坑19 双标志：完成判定 = Promise 落定 + 收口归类两者齐）──
    let settled: boolean = false;
    let statusOk: boolean = false;
    let status: number = 0;
    let errorCode: number = -1;
    let errorText: string = '';
    let header: Record<string, string> = {};
    let headerSeen: boolean = false;
    let text: string = '';
    let bytes: number = 0;
    const events: string[] = [];
    let isEventStream: boolean = false;
    let terminalReason: string = '';
    let idleElapsedMs: number = 0;
    let firstByteAt: number = 0;
    let finished: boolean = false;
    // ★ status-line 里的状态码真值——requestInStream 的 Promise 流末才落定（坑19，netstack
    // 实锤），窗口软停在流中途 destroy 强拆后状态码只能从 headersReceive 已收的 status-line
    // 取（"HTTP/1.1 200 OK" 形态第二段）；逐跳覆盖与 header 同序（最终响应的码为准）
    let statusLineCode: number = 0;
    const parser: SseFrameParser = new SseFrameParser();
    const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
    let windowTimer: number = -1;
    let idleTimer: number = -1;
    const outcome: HttpStreamOutcome = {
      settled: false, statusOk: false, status: 0, errorCode: -1, errorText: '',
      header: header, headerSeen: false, text: '', bytes: 0, events: events,
      isEventStream: false, terminalReason: '', idleElapsedMs: 0
    };

    const clearTimers = (): void => {
      if (windowTimer >= 0) {
        clearTimeout(windowTimer);
        windowTimer = -1;
      }
      if (idleTimer >= 0) {
        clearTimeout(idleTimer);
        idleTimer = -1;
      }
    };
    // 统一收尾单点：清计时器 → off 三件（幂等，包 try）→ destroy（包 try）→ 在途表移除
    // → 回填 outcome → resolve。任何路径（软停 / idle / 取消 / dataEnd / 网络失败）的收尾
    // 全走这里——off / destroy / 清计时器与 resolve 的成对性由单点保证（机制吸收第 3 条）
    const finalize = (): void => {
      if (finished) {
        return;
      }
      finished = true;
      clearTimers();
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
      const idx: number = httpInFlight.findIndex((item: HttpInFlight): boolean =>
        item.req === req);
      if (idx >= 0) {
        httpInFlight.splice(idx, 1);
      }
      outcome.settled = settled;
      outcome.statusOk = statusOk;
      outcome.status = status;
      outcome.errorCode = errorCode;
      outcome.errorText = errorText;
      outcome.header = header;
      outcome.headerSeen = headerSeen;
      outcome.text = text;
      outcome.bytes = bytes;
      outcome.isEventStream = isEventStream;
      outcome.terminalReason = terminalReason;
      outcome.idleElapsedMs = idleElapsedMs;
      // 请求日志终态（与 httpRequestRaw 同序口径）：取消路径已记「已取消」——跳过防二次改写；
      // 其余按状态码 / 网络失败记（成功不记正文，同同步路边界）。★ 非 2xx 错误体进日志：
      // statusOk 且非 2xx 时第五参取已收 text 尾部（原恒空 = 流式路比同步路少一层可归因信息）；
      // 截断与凭据脱敏由 ReqLog.reqLogEnd 承担
      if (terminalReason !== 'cancelled') {
        const okCode: boolean = statusOk && status >= 200 && status < 300;
        const tail: string = statusOk && !okCode ? text : '';
        reqLogEnd(logId, statusOk ? status : -1, Date.now() - startedAt,
          okCode ? '' : (statusOk ? '' : errorText), tail);
      }
      resolve(outcome);
    };
    // 完成判定：Promise 落定 + 收口归类齐才收尾（dataEnd 先于 Promise 是常态序〔坑19〕，
    // 软停 / idle / 取消路径主动 destroy 后由 Promise 落定补齐另一半）
    const maybeSettle = (): void => {
      if (finished || !settled || terminalReason === '') {
        return;
      }
      finalize();
    };
    // 主动收口（软停三态 / idle 硬中止）：先归类 → 补齐双标志（settled + statusOk/status
    // 自 status-line 真值）→ 清计时器 → off + destroy（防窗口到量后回调继续灌）→
    // maybeSettle 立即收尾。★ 不等 Promise 落定补齐另一半——坑19 实锤 Promise 流末才落定，
    // 软停 destroy 强拆后只会走 reject 分支把 statusOk 压成 false，成功读到的窗口数据被误报
    // 成网络失败（「主动 fail 不等 Promise」先例同款）；主动收口 = 结果已定格，迟到的
    // then/catch 只改局部标志——outcome 已拷贝、finished 已闸，零副作用；也不再赌「destroy
    // 必然结算 promise」。已有归类不覆盖（首个收口原因为准——取消恒优先由探查闸保证，见下）
    const stopStream = (reason: string): void => {
      if (finished || terminalReason !== '') {
        return;
      }
      terminalReason = reason;
      settled = true;
      if (statusLineCode > 0) {
        statusOk = true;
        status = statusLineCode;
      }
      clearTimers();
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
      maybeSettle();
    };
    // 计时器回调的取消探查闸（用户取消恒优先归类为取消，禁误报超时）：canceledLogIds 只读
    // 探查（indexOf 不 splice——消费权在 catch 分支），命中 = 掐断在途，归类权让给 catch
    const cancelInFlight = (): boolean => canceledLogIds.indexOf(logId) >= 0;
    const onWindowTimer = (): void => {
      if (finished || terminalReason !== '' || cancelInFlight()) {
        return;
      }
      stopStream('window');
    };
    const onIdleTimer = (): void => {
      if (finished || terminalReason !== '' || cancelInFlight()) {
        return;
      }
      idleElapsedMs = HTTP_STREAM_IDLE_MS;
      stopStream('idle');
    };

    // ── 三回调订阅与起流（同守卫段——SDK 面抛错即静默悬停，ChatStreamBase 同款纪律）──
    try {
      req.on('headersReceive', (h: Object): void => {
        if (finished) {
          return;
        }
        // 逐跳覆盖（最终响应的头决定分流）；SSE 识别按 content-type 含子串判——带
        // charset 参数形态照认（isTextContentType 的 text/ 前缀同款宽容）
        header = h as Record<string, string>;
        headerSeen = true;
        const contentType: string = readHeader(h, 'content-type');
        isEventStream = contentType.toLowerCase().includes('text/event-stream');
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
        if (finished || terminalReason !== '') {
          return;
        }
        if (firstByteAt === 0) {
          // 首字节：窗口计时自此起算（「读多久」的语义起点）+ idle 计时启动
          firstByteAt = Date.now();
          windowTimer = setTimeout(onWindowTimer, window.windowMs) as number;
          idleTimer = setTimeout(onIdleTimer, HTTP_STREAM_IDLE_MS) as number;
        } else {
          // 每收到数据重置 idle（机制吸收「每次收到数据即重置」）
          if (idleTimer >= 0) {
            clearTimeout(idleTimer);
          }
          idleTimer = setTimeout(onIdleTimer, HTTP_STREAM_IDLE_MS) as number;
        }
        bytes += chunk.byteLength;
        if (bytes > window.windowBytes) {
          stopStream('bytes');
          return;
        }
        // decodeToString stream 模式：UTF-8 多字节跨分片不撕裂（ChatStreamBase 同款；
        // decodeWithStream 已废弃，官方 @useinstead 指向本方法）
        const piece: string = decoder.decodeToString(new Uint8Array(chunk), { stream: true });
        text += piece;
        if (isEventStream) {
          const fresh: string[] = [];
          const parsed = parser.feed(piece);
          for (const ev of parsed) {
            fresh.push(ev.data);
          }
          for (const data of fresh) {
            events.push(data);
            if (window.maxEvents > 0 && events.length >= window.maxEvents) {
              stopStream('events');
              return;
            }
          }
        }
        if (firstByteAt > 0 && Date.now() - firstByteAt >= window.windowMs) {
          stopStream('window');
        }
      });
      req.on('dataEnd', (): void => {
        if (finished || terminalReason !== '') {
          return;
        }
        // 自然收尾：残留当末帧补出（机制吸收「结束 flush 补尾字节、残留当末帧」——末帧
        // 无空行形态）；软停止路径不 flush（残留是不完整事件，不该派发）
        if (isEventStream) {
          const tail = parser.flush();
          for (const ev of tail) {
            events.push(ev.data);
          }
        }
        terminalReason = 'completed';
        maybeSettle();
      });
      // options 与 httpRequestRaw 同源（少 expectDataType / maxLimit——inStream 模式数据
      // 走回调，ChatStreamBase 实锤形态；总量闸由 windowBytes 承担）
      const options: http.HttpRequestOptions = {
        method: method,
        header: headers,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        maxRedirects: HTTP_MAX_REDIRECTS,
        usingCache: false
      };
      if (payload.textBody !== null) {
        options.extraData = payload.textBody;
      }
      if (payload.binaryBody !== null) {
        options.body = payload.binaryBody;
      }
      if (payload.multiFormData !== null) {
        options.multiFormDataList = payload.multiFormData;
      }
      // 代理兜底写入（两条传输路同源，见文件头代理段）
      applyEffectiveProxy(options);
      req.requestInStream(url, options)
        .then((code: number): void => {
          settled = true;
          statusOk = true;
          status = code;
          maybeSettle(); // dataEnd 先到的常态序在此补判（坑19）
        })
        .catch((e: Object): void => {
          settled = true;
          statusOk = false;
          errorCode = httpKitErrorCode(e);
          errorText = httpKitErrorText(e, Math.max(1, Math.round(timeoutMs / 1000)));
          // 取消归类（坑75 家族）：掐断链已 destroy → promise reject 到此——canceledLogIds
          // 命中（消费即删，成对）= 用户取消，归类覆盖错误面；先于此的软停 / idle 归类
          // 不覆盖（terminalReason 已设时保持原归类）
          const cancelIdx: number = canceledLogIds.indexOf(logId);
          if (cancelIdx >= 0) {
            canceledLogIds.splice(cancelIdx, 1);
            if (terminalReason === '') {
              terminalReason = 'cancelled';
            }
          } else if (terminalReason === 'completed' && statusLineCode > 0) {
            // ★ 迟到 reject 压掉已收完的流：dataEnd 已自然收尾而 Promise 迟到 reject（与
            // readTimeout 计时的竞态）——流已完整收到，信 dataEnd 的事实自 status-line 真值
            // 回填状态码（软停路同源先例），防已收数据被 !statusOk 分支吞掉；错误面一并清零
            //（防迟到 reject 的错误信息残留在 outcome 里误注）
            statusOk = true;
            status = statusLineCode;
            errorCode = -1;
            errorText = '';
          } else if (terminalReason === '') {
            // 非取消失败即终局（无后续数据可等）——归类 'error' 使 maybeSettle 放行
            terminalReason = 'error';
          }
          maybeSettle();
        });
    } catch (e) {
      // 订阅 / 起流同步抛错：传输未成立，按网络失败收口（不走 stopStream——req 可能未
      // 就绪；finalize 的 off / destroy 均包 try，安全幂等）
      settled = true;
      statusOk = false;
      errorCode = -1;
      errorText = '请求发起失败：' + (e as Error).message;
      terminalReason = '';
      // 收口归类空 = maybeSettle 闸不过——失败态直接终局收尾（错误已是终态，无后续回调）
      finalize();
    }
  });
}
