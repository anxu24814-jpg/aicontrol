// 协议流传输基类（2026-08-30 三协议改造自 OpenAiCompatApi 抽出）：@ohos.net.http
// requestInStream + dataReceive 自攒帧的完整状态机——HTTP 响应码竞态处理 / SSE 攒帧派发 /
// 坏帧容错 / 三错误路径中文提示 / 终态闸与成对释放。OpenAI/Anthropic/Gemini 三协议流
// 共用本基类（宪 P2-4：同一状态机三份复制 = 腐化第一来源），子类只覆写四个协议钩子：
// endpoint（拼 URL）/ requestHeaders（认证头族）/ requestBody（方言请求体）/
// consumePayload（data 载荷 → 增量路由，返回 true = 见终止标记）+ requireDoneMarker
//（完成语义：OpenAI [DONE] 与 Anthropic message_stop 需标记；Gemini 无标记，dataEnd 即完成）。
// 自定义请求头（providers.headers）在 start 统一逐条追加，允许覆盖内置头含认证头
//（中转站场景拍板）——三协议单一落点。
// 红线（承 M1 OpenAiCompatApi，行为保持）：
// · 三错误路径全中文：HTTP 非 200（解析 error.message）/ 网络失败（BusinessError code）/
//   JSON 截断（未收终止标记即流尾 = 连接中断；单帧坏帧跳过容错不阻断）；
// · 增量只回调不进库（落库由页面层在 done/error 一次性完成）；
// · 坑 80 规避：显式 Content-Type: application/json + 非空 body；
// · 资源成对：on('dataReceive'/'dataEnd') ↔ off + destroy() 在 release() 单点成对释放；
//   流式层不自行重试；重试编排在 ChatSendCtrl 与自动重试域——Key 池失败切换 + 网络层零产出
//   退避重试（见任务书 D2），本层只透出错误与产出判据；
//   「停止」= abort() → 统一走 onError(-1) 收尾；
// · 请求日志（2026-09-23 请求日志笔）：start / complete / fail / disposeSilent 四处埋点，把
//   本次请求的 URL、最终请求头（已掩码）与最终请求体（已截断）连同响应码 / 耗时 / 错误体尾部
//   记进 ReqLog 内存环形缓冲（开关默认关，关态 reqLogBegin 首行早退 = 零开销）；
//   disposeSilent 是零回调路径，故必须单独补一行，否则页面销毁取消的流永远停在「进行中」；
//   取消两路（abort 与 disposeSilent）的日志状态走取消哨兵而非 -1——用户主动中止不是网络
//   故障（同日自检轮分家，见 common/ReqLog.ets 头「-1 与 -3 的分家」），fail 因此多一个
//   可选 logStatus 形参，**只作用于日志**，onError 的状态码一字节未动；
// · 首字耗时（2026-09-23 首字耗时笔）：本类**常开**的第二个时间戳——首个正文/思考增量到达
//   时刻 − streamStartMs，随 onDone 第四参透出（与 usage / durationMs / truncated 同链）。
//   零点与 durationMs 同源（streamStartMs 在 start 首行无条件打，组装与守卫都在其后），
//   故恒有 firstTokenMs ≤ durationMs。★ 不随任何开关——请求日志开关管的是「留不留原始
//   报文」（URL/头/体），不是「测不测时间」；耗时数字不含对话内容，与「用时」（同日族、
//   自 2026-09-06 起就常开且落库）同级。与请求日志「首字节」的分野见字段 firstTokenMs 注释
// · onError 透出 HTTP 状态码（AiStreamHandlers 第二参；-1 = 无状态码场景）——
//   失败切换据此判 401/403/429；第三参 sawContent = 本流是否已上屏过内容（正文/思考/
//   工具四选一；空保活帧与纯 usage 帧不计）——自动重试的「本轮零产出」判据据此判，
//   语义与取值点见 AiTypes.AiStreamHandlers 与下方 deliverDelta。
// ★ 坑19 修复（2026-09-01，乐观分发）：netstack 源码实锤 requestInStream 的 Promise 在
// 整个传输完成后才 resolve（communication_netstack http_exec.cpp——HandleCurlData 收
// CURLMSG_DONE〔传输完成〕才排队 resolve 回调），而 dataReceive/headersReceive 在传输中
// 即时触发。故数据路由与状态码解耦：chunk 一到即喂 SseParser 派发增量（非 200 错误体无
// data: 行——零事件零坏帧无害），errorBody 尾部有界同步累积供流末呈报；Promise 状态码
// 只用于 decideEnd 的完成/错误判定与失败切换（401/403/429）。endReceived 分支保留：
// dataEnd 先于 Promise 落定（即常态序）时挂起待 then 补判。
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AiChatMessage, AiConnection, AiStreamHandlers, AiToolDef, HeaderPair,
  SamplingParams, STREAM_ERROR_STATUS } from './AiTypes';
import { AiUsageDelta, extractApiError, mergeUsage, SseParser, SseDelta } from './SseParser';
import { reqLogBegin, reqLogEnd, reqLogMarkFirstByte, reqLogSetResponseHeaders,
  REQ_LOG_STATUS_CANCELED } from '../ReqLog';

const DOMAIN: number = 0x0001;
const TAG: string = 'ChatStream';
const CONNECT_TIMEOUT_MS: number = 30000;
// 流式读超时 = 两次增量间隔上限（思考模型长时间停顿时不被掐断）；档位 = 10 分钟（同 ZCode
// DEFAULT_MODEL_STREAM_IDLE_TIMEOUT_MS 默认值，其语义亦为「每次读重置的 idle 上限」——
// 2026-09-23 输出上限治理笔 2 自 2 分钟档上调；旧「对齐 Kelivo 10 分钟」系误引，见任务书
// §0.4 第 1 条），低于 Cherry 的 30 分钟 idle 档。
// ★ 语义（间隔 vs 整笔总时长）待真机定死：官方 API 参考该字段只写「读取超时时间。单位为
// 毫秒（ms），默认为 60000ms……设置为 0 表示不会出现超时情况」，未区分二者。若实测为**总
// 时长**语义 ⇒ 须改「0 = 不超时 + 自建空闲看门狗」形态（回改条件①，实测法见任务书 §7⑤）。
// 调参位，真机观测后再调
const READ_TIMEOUT_MS: number = 600000;
// 非 200 响应原文只留尾部（数据有界红线——错误体不可控，防无界增长）
const ERROR_BODY_MAX_CHARS: number = 500;

export class ChatStreamBase {
  protected handlers: AiStreamHandlers;
  private request: http.HttpRequest = http.createHttp();
  private parser: SseParser = new SseParser();
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
  private finished: boolean = false; // 终态闸：done/error/abort 后置真，后续回调全吞
  private statusCode: number = -1; // -1 = 响应码未落定
  private endReceived: boolean = false; // dataEnd 先于状态码到达的竞态标记（坑19 后即常态序）
  private errorBody: string = ''; // 响应原文尾部（乐观分发期同步累积，有界——流末非 200 呈报用）
  private sawDone: boolean = false; // 终止标记已见（[DONE] / message_stop；Gemini 恒 false）
  protected sawValidFrame: boolean = false;
  // ★ 2026-09-22 自动重试笔：本流是否收到过**真正上屏的内容**（deliverDelta 的 onDelta 门控内
  // 置真——正文/思考/工具调用/reasoning item 四选一）。与 sawValidFrame 的区别 = 后者在
  // 方法首行无条件置真（含空保活帧与纯 usage 帧），拿它判「本轮零产出」会把「一个字都没
  // 显示」判成有产出而不重试。每流独立（每次尝试一个新流实例）；只读透出（fail 第三参）
  private sawContent: boolean = false;
  // ★ 2026-09-23 输出上限治理笔 2：本流是否被输出上限截断（四协议标记帧经 absorbTruncated
  // 置真）。与 usage 同族「无增量帧」信号——截断帧（finish_reason / finishReason /
  // stop_reason / incomplete_details）通常不带增量，走不了 deliverDelta 的门控，故独立成
  // 字段；每流独立（每次尝试一个新流实例），只读透出（complete 第三参）
  private sawTruncated: boolean = false;
  protected badFrames: number = 0;
  // ── 用量采集（2026-09-06）──
  // 流内 usage 累积（mergeUsage take-max：anthropic/gemini 累积值分帧递增、openai 尾帧
  // 单帧全量、responses 终止帧单帧全量——四方言归一）；fail 路径不消费（error 流无统计）
  private usageAccum: AiUsageDelta | null = null;
  private streamStartMs: number = 0; // start() 墙钟锚（complete 时算本流纯流式时长）
  // 请求日志条目 id（2026-09-23 请求日志笔；start 赋、三终态回填；'' = 本次未开启或未走到
  // 埋点——reqLogEnd 见空 id 一律短路）
  private reqLogId: string = '';
  // 首字节是否已打戳（2026-09-23 扩充笔）：本流首个数据块到达时置真并上报一次。★ 挡在
  // onChunk 最前面的意义 = 热路径成本——onChunk 每片都跑，reqLogMarkFirstByte 内部要线扫
  // 缓冲表，逐片调用属无谓开销（日志是傍路，不该拖慢流）
  private firstByteLogged: boolean = false;
  // 首字耗时（2026-09-23 首字耗时笔）：本流首个**正文或思考**增量到达时刻 − streamStartMs
  //（毫秒；0 = 本流未产出过正文/思考增量，如空响应、纯工具调用轮、失败流）。三条口径：
  // ①零点与 durationMs 同源（同一 streamStartMs，start 首行无条件打）⇒ 恒有本值 ≤ durationMs；
  // ②只认正文与思考增量——工具调用帧与 reasoning item 帧是程序产物，不是用户读到的第一个字；
  // ③每流独立、首个为准（后续增量不覆盖）。
  // ★ 与请求日志的「首字节」（firstByteLogged，首个数据块，含空保活帧与纯 usage 帧）是两个
  // 指标，勿混：那个是网络层诊断口径、**只在日志开关打开时测**；本字段是体感口径、**常开**
  //（与 durationMs 同族，不随任何开关）。消费链 = onDone 第四参 → ChatUsageRoundCtrl 轮级累积
  //（首个非 0 胜出）→ 账本 token_usage_events.firstTokenMs → 气泡用量弹层与用量面板
  private firstTokenMs: number = 0;

  constructor(handlers: AiStreamHandlers) {
    this.handlers = handlers;
  }

  // ── 子类协议钩子（子类必须覆写；基类兜底抛错防静默错协议）──

  // 请求端点全 URL（baseUrl 去尾斜杠归一后拼协议路径）
  protected endpoint(conn: AiConnection): string {
    throw new Error('协议端点未实现');
  }

  // 内置请求头族（认证头随协议：Bearer / x-api-key / x-goog-api-key）
  protected requestHeaders(conn: AiConnection, apiKey: string): Record<string, string> {
    throw new Error('协议请求头未实现');
  }

  // 请求体 JSON 串（方言转换在各协议子类；thinking = 思考档位（'' = 不传），方言落点在各
  // compose 纯函数——2026-08-31 任务 B；sampling = 助手采样参数（null = 不带任何采样
  // 字段，2026-09-01 高级设定），方言落点同在 compose；tools = 工具声明（2026-09-02
  // 工具调用底层；缺省 [] = 不带 tools 字段请求体零回归），方言落点同在 compose）
  protected requestBody(conn: AiConnection, messages: AiChatMessage[], thinking: string,
    sampling: SamplingParams | null, tools: AiToolDef[] = []): string {
    throw new Error('协议请求体未实现');
  }

  // 处置一帧 data 载荷：deliverDelta 送增量；流中错误帧可调 this.failStream；
  // 返回 true = 本载荷为终止标记（基类置 sawDone）
  protected consumePayload(payload: string): boolean {
    return false;
  }

  // true = 需终止标记才判完成（未收标记但有过有效帧 = 连接中断错误）；
  // false = dataEnd 即完成（Gemini 无终止标记）
  protected requireDoneMarker(): boolean {
    return true;
  }

  // 增量投递（子类 consumePayload 消费）：标记有效帧 + 空增量不回调（工具调用增量同理
  // 有效帧——2026-09-02；reasoning item 捕获帧同理——2026-09-06 Responses 修复：解析器
  // 以 kind='delta' + 空文本携带捕获载荷，无此门控会被空增量过滤吞掉）
  protected deliverDelta(delta: SseDelta): void {
    this.sawValidFrame = true;
    const hasTools: boolean = delta.toolCalls !== undefined && delta.toolCalls.length > 0;
    const hasReasoningItems: boolean =
      delta.reasoningItems !== undefined && delta.reasoningItems.length > 0;
    if (delta.content !== '' || delta.reasoningContent !== '' || hasTools || hasReasoningItems) {
      // 自动重试判据源（★ 2026-09-22）：置真点必须在门控**内**——门控前会被零增量帧喂真
      this.sawContent = true;
      // 首字打戳（2026-09-23 首字耗时笔）：三个条件缺一不可——①门控**内**（门控外会被空
      // 保活帧与纯 usage 帧误打）；②只认正文/思考（工具调用帧与 reasoning item 帧不是「字」，
      // 故不并进门控条件；工具轮先出工具调用时首字留给后续产出正文的那条流）；③首个为准
      //（后面的增量不覆盖）。打戳在 onDelta 之前 = 该增量的到达时刻（同步差可忽略）
      if ((delta.content !== '' || delta.reasoningContent !== '') && this.firstTokenMs === 0) {
        this.firstTokenMs = Date.now() - this.streamStartMs;
      }
      this.handlers.onDelta(delta);
    }
  }

  // 坏帧计数 + 日志（子类 consumePayload 判废时调——M1 坏帧容错可观测性保持）
  protected noteBadFrame(): void {
    this.badFrames++;
    hilog.warn(DOMAIN, TAG, '坏帧跳过，累计 %{public}d', this.badFrames);
  }

  // 流内 usage 累积单点（2026-09-06；子类 consumePayload 从解析产物摘 usage 后调）——
  // take-max 合并在 SseParser.mergeUsage 纯函数（断言面 ㉚ 组），基类只持累积态
  protected absorbUsage(usage: AiUsageDelta | undefined): void {
    if (usage === undefined) {
      return;
    }
    this.usageAccum = mergeUsage(this.usageAccum, usage);
  }

  // 截断标记吸收单点（2026-09-23 输出上限治理笔 2；子类 consumePayload 摘 delta.truncated
  // 后调，位置与 absorbUsage 同级——都必须在 deliverDelta 之前，截断帧无增量会被门控吞）。
  // 只认 true（undefined / 假值零介入——无截断是常态，零开销）
  protected absorbTruncated(flag: boolean | undefined): void {
    if (flag === true) {
      this.sawTruncated = true;
    }
  }

  // 流中错误帧路径（如 Anthropic error 帧；终态语义与 fail 同源）
  // ★ 2026-09-22 自检轮改判：此处 statusCode **必然仍是 -1**——错误帧在流内到达，而状态码
  // 唯一写点 = 流末才 resolve 的 requestInStream Promise（坑19 机制）。透 -1 会被聊天自动
  // 重试判据当成网络层失败而重发（把过载/限流/配置类协议错误也重发 3 次并显示「网络异常」，
  // 与「不做 429·5xx 自动重试」红线相抵）。故**响应码未落定时透专属哨兵**；响应码已落定
  // （尾冲刷帧，decideEnd 的 parser.finish() 路径）仍照原样透真码
  protected failStream(message: string): void {
    this.fail(message, this.statusCode === -1 ? STREAM_ERROR_STATUS : this.statusCode);
  }

  // source = 请求日志用途标签（2026-09-23 请求日志笔，第 7 形参；省略 = '聊天'——正常发送
  // 路径不传即逐字零回归，连接能力测试的 T2/T3 流式探针显式传 '连通性测试' 以便日志分辨）
  start(conn: AiConnection, apiKey: string, messages: AiChatMessage[], thinking: string,
    sampling: SamplingParams | null, tools: AiToolDef[] = [], source: string = '聊天'): void {
    // 流式时长锚（2026-09-06 用量采集：durationMs = 本流 start→onDone 墙钟——任务书口径
    // 「纯流式时间」，网络等待计入、工具执行等待不在流内天然不计）
    this.streamStartMs = Date.now();
    // ★ 2026-09-23 发送面守卫成段（自检轮观察项②收口）：start 是**异步终态契约**——成功 / 失败
    // 一律经 onDone / onError 回来，故**同步抛出 = 本轮既无终态回调、请求日志条目又永停「进行
    // 中」**，界面停在生成态等一个永不到来的回调。此前只有 requestInStream 一句在 try 内，其余
    // 整段裸奔（调用方各自的 catch 兜得住不崩，但会误归因——如 ChatKeyRoundCtrl 把它记成「Key
    // 读取失败」）。现按**成因分两段**各设守卫，两段都落回统一收尾 fail()：①组装段——请求还没
    // 交给系统，属本端问题（协议钩子 / 自定义头 / 覆盖表 / 端点拼接，含 conn 的行型外边界）；
    // ②传输段——交给系统之后，含三句事件订阅（SDK 面，抛错即静默悬停）。
    // ★ reqLogBegin 刻意留在两段守卫之外：它是傍路，自带全程 try（见 ReqLog.ets 头），纳入守卫
    // 会把「日志侧异常」升级成「正常发送被判死」，与该件「不得反噬主链」的取向相抵
    let header: Record<string, string> = {};
    let bodyText: string = '';
    let url: string = '';
    try {
      // 内置头 → 自定义头逐条追加（后者可覆盖前者含认证头；空 k 行守一道）
      header = this.requestHeaders(conn, apiKey);
      for (const pair of conn.headers) {
        if (pair.k !== '') {
          header[pair.k] = pair.v;
        }
      }
      // 请求体先成局部量再进 options：请求日志要记的就是这串最终产物（含 bodyOverrides 合并
      // 结果），事后从 options.extraData 反取会撞联合类型（string | Object | ArrayBuffer）
      bodyText = mergeBodyOverrides(
        this.requestBody(conn, messages, thinking, sampling, tools), conn.bodyOverrides);
      url = this.endpoint(conn);
    } catch (e) {
      // 组装失败是本端问题，不是网络故障——照实说，否则用户会去查网络。日志同理：URL 与请求
      // 体都没成型，本路径零条目（条目本就建在组装之后）
      this.fail('请求组装失败：' + describeNetError(e as Object), -1);
      return;
    }
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: header,
      extraData: bodyText,
      usingCache: false,
      connectTimeout: CONNECT_TIMEOUT_MS,
      readTimeout: READ_TIMEOUT_MS
    };
    // 请求日志埋点（ReqLog.ets）：URL / 最终头（内部掩码）/ 最终体（内部截断）此刻全部就位
    // ——四协议共用本处，故一处埋点覆盖全部聊天流式链。未开启时返回空 id，后续回填自动短路。
    // 模型名（2026-09-23 扩充笔）取自连接：多模型 / 多中转站下 URL 一模一样，没有它列表行
    // 看不出这条是谁发的
    this.reqLogId = reqLogBegin({
      source: source, model: conn.model, method: 'POST', url: url, headers: header,
      body: bodyText
    });
    // 订阅三句与起流同守卫（观察项②）：on 目前无已知抛错路径，但它是 SDK 面、订阅成败直接
    // 决定本轮能否收回调——异常外泄即静默悬停，故与起流一并落回统一收尾
    try {
      this.request.on('dataReceive', (chunk: ArrayBuffer): void => this.onChunk(chunk));
      this.request.on('dataEnd', (): void => this.onEnd());
      // 响应头（2026-09-23 扩充笔）：流式链拿不到 HttpResponse（requestInStream 只回状态码），
      // 白名单头只能走事件订阅；★ 与另两个订阅同点注册、在 release() 单点成对注销
      this.request.on('headersReceive', (header: Object): void => this.onHeaders(header));
      this.request.requestInStream(url, options)
        .then((code: number): void => {
          // Promise 流末落定（坑19——netstack 实锤）：此处只收状态码与补判收尾；数据路由
          // 已在 dataReceive 乐观分发完毕（见头注释）
          this.statusCode = code;
          if (this.endReceived) {
            this.decideEnd(); // dataEnd 先于 Promise 落定（常态序）——补判收尾
          }
        })
        .catch((e: Object): void => {
          this.fail('网络错误：' + describeNetError(e), -1);
        });
    } catch (e) {
      this.fail('网络错误：' + describeNetError(e as Object), -1);
    }
  }

  // 停止 = 中止请求 + 走 error 终态（任务书口径：落库 error 态；统一收尾路径防回调分叉）
  // 第三参 = 请求日志侧的状态：用户主动停止不是「传输层失败」，日志记专属取消哨兵以免列表把
  // 它显示成网络故障（2026-09-23 自检轮，见 common/ReqLog.ets 头「-1 与 -3 的分家」）；
  // 透给 onError 的状态码仍是 -1，自动重试域判据零影响
  abort(): void {
    this.fail('已手动停止', -1, REQ_LOG_STATUS_CANCELED);
  }

  // 静默释放（页面销毁路径专用）：中止且不触发任何回调——防销毁后回调再触 UI（任务书
  // 「页面 aboutToDisappear 中止进行中流式并解绑回调」红线；DB 侧残留 streaming 态由
  // 下次启动 markStreamingAsError 兜底转 error）
  disposeSilent(): void {
    if (this.finished) {
      return;
    }
    this.finished = true;
    this.release();
    // 本路径零回调（见上注释），故请求日志在此单独收尾——否则页面销毁取消的流会永远停在
    // 「进行中」（2026-09-23 请求日志笔）。状态记**取消哨兵**而非 -1：页面销毁是用户动作，
    // 不是网络故障（自检轮同日分家，见 common/ReqLog.ets 头「-1 与 -3 的分家」）
    reqLogEnd(this.reqLogId, REQ_LOG_STATUS_CANCELED, Date.now() - this.streamStartMs,
      '页面已关闭，请求已取消', '');
  }

  private onChunk(chunk: ArrayBuffer): void {
    if (this.finished) {
      return;
    }
    // 首字节打戳（2026-09-23 扩充笔）：整条流只上报一次——布尔位挡在最前面，逐片调
    // reqLogMarkFirstByte 属无谓热路径开销（见 firstByteLogged 声明处）
    if (!this.firstByteLogged) {
      this.firstByteLogged = true;
      reqLogMarkFirstByte(this.reqLogId);
    }
    // decodeToString stream 模式：UTF-8 多字节字符跨分片不撕裂（残余字节留内部缓冲待下片；
    // decodeWithStream 已废弃，官方 @useinstead 指向本方法）
    const text: string = this.decoder.decodeToString(new Uint8Array(chunk), { stream: true });
    this.routeText(text);
  }

  // 响应头回调（2026-09-23 扩充笔）：白名单过滤与脱敏都在 ReqLog 内部完成，本层只透传——
  // 未开启时 reqLogId 为空串，内部零副作用；全程内部 try，异常不得打断正在进行的流
  private onHeaders(header: Object): void {
    reqLogSetResponseHeaders(this.reqLogId, header);
  }

  // 乐观分发（坑19 修复）：不等状态码（其唯一来源 = 流末才落定的 Promise，见头注释）——
  // 全部喂解析器即时派发；非 200 错误体无 data: 行 = 零事件零坏帧无害。errorBody 同步
  // 尾部累积（流末非 200 时 extractApiError 呈报用）。
  private routeText(text: string): void {
    const payloads: string[] = this.parser.feed(text);
    for (const payload of payloads) {
      if (this.finished) {
        return; // 流中错误帧已 fail 的余帧全吞
      }
      this.dispatchPayload(payload);
    }
    this.errorBody = (this.errorBody + text).slice(-ERROR_BODY_MAX_CHARS);
  }

  private dispatchPayload(payload: string): void {
    if (this.consumePayload(payload)) {
      this.sawDone = true;
    }
  }

  private onEnd(): void {
    if (this.finished) {
      return;
    }
    if (this.statusCode === -1) {
      this.endReceived = true; // 状态码未落定，待 then 落定后补判
      return;
    }
    this.decideEnd();
  }

  private decideEnd(): void {
    // 解析器尾冲刷：无换行收尾的末行/未决事件在此派发（截断帧将被判废）
    const rest: string[] = this.parser.finish();
    for (const payload of rest) {
      if (this.finished) {
        return;
      }
      this.dispatchPayload(payload);
    }
    if (this.statusCode !== 200) {
      const detail: string = extractApiError(this.errorBody);
      const suffix: string = detail !== '' ? '：' + detail :
        (this.errorBody !== '' ? '：' + this.errorBody : '，响应无内容');
      this.fail('请求失败(HTTP ' + this.statusCode + ')' + suffix, this.statusCode);
      return;
    }
    if (this.sawDone) {
      this.complete();
      return;
    }
    if (!this.requireDoneMarker() && this.sawValidFrame) {
      this.complete(); // Gemini：无终止标记方言，dataEnd 即完成
      return;
    }
    if (this.sawValidFrame) {
      this.fail('连接中断：响应不完整（未收到结束标记），已收内容可能截断', this.statusCode);
      return;
    }
    this.fail('响应为空或数据格式无法识别', this.statusCode);
  }

  private complete(): void {
    if (this.finished) {
      return;
    }
    this.finished = true;
    this.release();
    // 请求日志成功终态（2026-09-23 请求日志笔）：本路径时长 = 整轮流式墙钟（含末帧到 dataEnd
    // 的收尾），比竞品在响应头到达时就落笔的「首字节耗时」更贴近用户体感
    reqLogEnd(this.reqLogId, this.statusCode, Date.now() - this.streamStartMs, '', '');
    // 用量、时长、截断标记与首字耗时随完成带出（2026-09-06 / 2026-09-23 两笔；首字第四参
    // 见 firstTokenMs 字段注释——0 = 本流未产出正文/思考增量）；fail 路径 onError 不变
    //（error 流无统计，也没有「被上限掐断」语义——截断是**正常完成**的流：模型把上限烧完
    // 即收尾，故走本路径而非 fail）
    this.handlers.onDone(this.usageAccum, Date.now() - this.streamStartMs, this.sawTruncated,
      this.firstTokenMs);
  }

  // logStatus = 请求日志侧的状态（省略 = 与 status 同值）。仅取消类路径（abort）分家传取消
  // 哨兵——透给 onError 的 status 必须原样（自动重试域判据挂在那上面，勿牵连；2026-09-23
  // 自检轮，见 common/ReqLog.ets 头「-1 与 -3 的分家」）
  private fail(message: string, status: number, logStatus?: number): void {
    if (this.finished) {
      return;
    }
    this.finished = true;
    this.release();
    // 请求日志失败终态（2026-09-23 请求日志笔）：status 原样透出（-1 传输层 / -2 协议错误帧 /
    // 真码），错误体尾部是 errorBody——非 200 场景它由 routeText 有界累积（≤500 字符），
    // 排障时它往往就是「对方到底说了什么」的唯一证据
    reqLogEnd(this.reqLogId, logStatus === undefined ? status : logStatus,
      Date.now() - this.streamStartMs, message, this.errorBody);
    this.handlers.onError(message, status, this.sawContent);
  }

  // 成对释放单点：off 全部事件 + destroy（on/off 对称，创建即绑定的两事件在此解除）。
  // ★ 2026-09-02 独立加固（chatcube HttpService streamPost cleanupHttpRequest 姿势，
  // Cube 移植随行）：每动作独立 try——单个 off 抛错不得跳过后续 off/destroy（否则
  // native 句柄泄漏，多轮工具调用场景逐轮累积；幂等性由 finished 闸保证 release 单次执行）
  private release(): void {
    try {
      this.request.off('dataReceive');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'off dataReceive 异常（忽略）：%{public}s', (e as Error).message);
    }
    try {
      this.request.off('dataEnd');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'off dataEnd 异常（忽略）：%{public}s', (e as Error).message);
    }
    try {
      this.request.off('headersReceive');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'off headersReceive 异常（忽略）：%{public}s', (e as Error).message);
    }
    try {
      this.request.destroy();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'destroy 异常（忽略）：%{public}s', (e as Error).message);
    }
  }
}

// 自定义 Body 覆盖 merge（2026-09-02 DB v13；RikkaHub 自定义请求体对齐）：把服务商级
// [{k, v=JSON 值文本}] 逐键覆盖/追加到组装完成的请求体根对象——四协议统一在此一层处理
//（协议无关：openai/responses/anthropic/gemini 顶层键各自规格，用户自担与服务商规格的
// 兼容性——超限未知字段由服务商 400 自答走既有回显链，不逐协议特判）。
// · 空覆盖表 = 原串原样返回（逐字节零回归）；坏 JSON 根对象（理论不可达——compose 产物）
//   也原样返回不发请求体半成品；单条 v 非法 JSON = 跳过该键 + 日志（入库侧已校验，此为
//   发送层兜底，P0-1 不静默中断请求）；
// · 同键覆盖内置键（与 headers「允许覆盖认证头」同语义拍板）。
// ★ RequestCompose 保持零 import 纯函数区不动——merge 属传输层组装后处理，sse-assert
// 断言样本（无覆盖路径）逐字节不变。
// ★ 2026-09-21 导出（连接能力三项测试笔）：T1 自组非流式请求须自己合 Body 覆盖（该探测
// 不走流式链，故拿不到 start 内建的合并）——导出即线上同一实现，禁为探针另写一份。
export function mergeBodyOverrides(body: string, overrides: HeaderPair[] | undefined): string {
  if (overrides === undefined || overrides.length === 0) {
    return body;
  }
  let root: Record<string, Object> | null = null;
  try {
    const parsed: object = JSON.parse(body);
    root = parsed as Record<string, Object>;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, '自定义 Body merge 失败：请求体解析异常，本次按原样发送');
    return body;
  }
  for (const pair of overrides) {
    if (pair.k === '' || pair.v === '') {
      continue;
    }
    try {
      root[pair.k] = JSON.parse(pair.v) as Object;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, '自定义 Body 键 %{public}s 值非法 JSON，已跳过', pair.k);
    }
  }
  return JSON.stringify(root);
}

// 网络层错误描述：BusinessError 判定用 typeof code（坑 59 ②——禁 in 运算）
function describeNetError(e: Object): string {
  const biz = e as BusinessError;
  if (typeof biz.code === 'number') {
    const msg: string = typeof biz.message === 'string' && biz.message !== '' ? '，' + biz.message : '';
    return '无法连接服务器(code ' + biz.code + ')' + msg;
  }
  return (e as Error).message !== undefined ? (e as Error).message : '未知错误';
}
