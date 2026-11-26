// 协议流传输基类：@ohos.net.http requestInStream + dataReceive 自攒帧的完整状态机——HTTP
// 响应码竞态 / SSE 攒帧派发 / 坏帧容错 / 三错误路径中文提示 / 终态闸与成对释放。
// OpenAI/Anthropic/Gemini 三协议共用（宪 P2-4：同一状态机三份复制 = 腐化第一来源），子类只
// 覆写协议钩子：endpoint（拼 URL）/ requestHeaders（认证头族）/ requestBody（方言请求体）/
// consumePayload（data 载荷 → 增量路由，返回 true = 见终止标记）+ requireDoneMarker（OpenAI
// [DONE] 与 Anthropic message_stop 需标记；Gemini 无标记，dataEnd 即完成）。自定义请求头
// （providers.headers）在 start 统一追加，允许覆盖内置头含认证头（中转站场景拍板）。
// 红线（承 M1，行为保持）：
// · 三错误路径全中文：HTTP 非 200（解析 error.message）/ 网络失败（BusinessError code）/
//   JSON 截断（未收终止标记即流尾 = 连接中断；单帧坏帧跳过容错不阻断）；
// · 增量只回调不进库（落库由页面层在 done/error 一次性完成）；
// · 坑 80 规避：显式 Content-Type: application/json + 非空 body；
// · 资源成对：on('dataReceive'/'dataEnd') ↔ off + destroy() 在 release() 单点成对释放；流式
//   层不自行重试（重试编排在 ChatSendCtrl 与 ChatAutoRetryCtrl——Key 池失败切换 + 传输层/
//   5xx/瞬态文案零产出退避重试），本层只透出错误与产出判据；「停止」= abort() 统一走
//   onError(-1) 收尾；
// · 请求日志：start / complete / fail / disposeSilent 四处埋点记进 ReqLog 内存环形缓冲（开关
//   默认关 = 零开销；disposeSilent 零回调须单独收尾；取消两路日志记取消哨兵而非 -1、fail 的
//   logStatus 形参只作用于日志——分家口径见 common/ReqLog.ets 头与各埋点注释）；
// · 首字耗时常开不随开关（与 durationMs 同族），随 onDone 第四参透出，细则见字段
//   firstTokenMs 注释；
// · onError 透出 HTTP 状态码（-1/-2/-4 = 传输层失败/协议错误帧/组装失败哨值，语义见
//   AiTypes.AiStreamHandlers）——失败切换据此判 401/403/429；第三参 sawContent = 本流是否已
//   上屏过内容（空保活帧与纯 usage 帧不计），自动重试「本轮零产出」判据此判；
// ★ 坑19（乐观分发）：requestInStream 的 Promise 在
//   整个传输完成后才 resolve（netstack http_exec.cpp——HandleCurlData 收 CURLMSG_DONE 才
//   排队 resolve 回调），而 dataReceive/headersReceive 在传输中即时触发——数据路由与状态码
//   解耦：chunk 一到即喂 SseParser 派发增量（非 200 错误体无 data: 行，零事件零坏帧无害），
//   errorBody 尾部有界累积供流末呈报；Promise 状态码只用于 decideEnd 判定与失败切换（401/
//   403/429）；dataEnd 先于 Promise 落定（常态序）时挂起待 then 补判。
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AiChatMessage, AiConnection, AiStreamHandlers, AiToolDef, ASSEMBLY_FAIL_STATUS,
  DsStreamExtrasLike, HeaderPair, SamplingParams, STREAM_ERROR_STATUS } from './AiTypes';
import { applyDefaultUserAgent, applyEffectiveProxy, setHeaderCaseInsensitive } from './RequestIdentity';
import { netReadTimeoutMinutes } from '../AppPreferences';
import { AiUsageDelta, extractApiError, mergeUsage, SseLimitBreach, SseParser, SseDelta,
  SSE_EVENT_MAX_CHARS, SSE_LINE_MAX_CHARS } from './SseParser';
import { httpKitErrorMessage } from './WebSearchParse';
import { reqLogBegin, reqLogEnd, reqLogMarkFirstByte, reqLogSetResponseHeaders,
  REQ_LOG_STATUS_CANCELED } from '../ReqLog';

const DOMAIN: number = 0x0001;
const TAG: string = 'ChatStream';
const CONNECT_TIMEOUT_MS: number = 30000;
// 流式读超时 = 两次增量间隔上限（官方参考未区分「间隔」与「整笔总时长」，真机验收实测定死
// = 间隔上限，长思考流不被掐断）。现「请求读超时」档位现读（5/10/20 分钟默认 10，单源
// AppPreferences.netReadTimeoutMinutes，已环自查无环）；只作用于聊天流式链——小任务/搜索/
// WebDAV 链各自分档刻意不吃本档
// 非 200 响应原文只留尾部（数据有界红线——错误体不可控，防无界增长）
const ERROR_BODY_MAX_CHARS: number = 500;
// 单次响应累计接收上限（2026-11-01 决明拍板 8 MiB：最大输出 131072 tokens 中文正文
// ≈0.13~0.5 MB，留 ≈16 倍余量；同族闸 = ToolHttp 的 HTTP_MAX_LIMIT_BYTES 2 MiB 与 SSE
// 行/帧 256K/1M 字符档）。耗尽分两路（onBudgetExhausted）：有内容且无工具调用 = 截断收尾
// ——与「模型烧完 max_tokens」同语义（sawTruncated 标记 + 气泡截断尾注 + 请求日志记实际
// 字节数，半截内容保留、不报错不中止）；零内容（垃圾流/非 200 大错误体，无产可留）与本流
// 出现过工具调用（防把截断当正常完成后续轮派发残缺调用）= 显式失败（fail 中文提示带实际
// 字节数，STREAM_ERROR_STATUS——不进自动重试面、不挂跳转动作）。禁静默截断：截断收尾必须
// 带 sawTruncated 标记与请求日志备注
const STREAM_RECEIVED_MAX_BYTES: number = 8388608;

// DS 扩展字段两布尔（二期 S2）：起流咽喉点（ChatKeyRoundCtrl）算好随 start 下传——
// RequestCompose 是零 import 纯函数、ChatStreamFactory 在直跑断言面，两者都不许查 DB /
// 读 AppStorage，故只吃这两个布尔。缺省 null = 既有调用零变化（非 DS 请求体逐字节不变）。
// 类型单源在 AiTypes（底层叶子），本件只做别名（域内读口用这个更顺）
export type DsStreamExtras = DsStreamExtrasLike;

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
  // 本流是否收到过**真正上屏的内容**（deliverDelta 的 onDelta 门控内置真——正文/思考/
  // 工具调用/reasoning item 四选一）。与 sawValidFrame 的区别 = 后者含空保活帧与纯 usage 帧，
  // 拿它判「本轮零产出」会把一个字都没显示判成有产出而不重试。每流独立；只读透出（fail 第三参）
  private sawContent: boolean = false;
  // 本流是否出现过工具调用增量（deliverDelta hasTools 处置真，与 sawContent 同门控）——
  // 接收预算耗尽分路判据之一：含工具调用的流超预算维持显式失败，防把截断当正常完成后
  // 续轮派发残缺调用
  private sawToolCall: boolean = false;
  // 本流是否被截断（两个置真点：四协议输出上限标记帧经 absorbTruncated——截断帧通常不带
  // 增量、走不了 deliverDelta 的门控，故独立成字段；接收预算耗尽经 onBudgetExhausted）。
  // 每流独立，只读透出（complete 第三参）
  private sawTruncated: boolean = false;
  protected badFrames: number = 0;
  // 流内 usage 累积（mergeUsage take-max：四方言归一）；fail 路径不消费（error 流无统计）
  private usageAccum: AiUsageDelta | null = null;
  private streamStartMs: number = 0; // start() 墙钟锚（complete 时算本流纯流式时长）
  // 请求日志条目 id（start 赋、三终态回填；'' = 未开启或未走到埋点——reqLogEnd 见空 id 短路）
  private reqLogId: string = '';
  // 首字节是否已打戳：首个数据块上报一次。布尔位挡在 onChunk 最前面 = 热路径成本——
  // reqLogMarkFirstByte 内部要线扫缓冲表，逐片调用属无谓开销（日志是傍路不拖慢流）
  private firstByteLogged: boolean = false;
  // 首字耗时：本流首个**正文或思考**增量到达时刻 − streamStartMs（0 = 未产出过，如空响应、
  // 纯工具调用轮、失败流）。三条口径：①零点与 durationMs 同源（同一 streamStartMs）⇒ 恒有
  // 本值 ≤ durationMs；②只认正文与思考——工具调用帧与 reasoning item 帧是程序产物，不是
  // 用户读到的第一个字；③每流独立、首个为准。★ 与请求日志的「首字节」（firstByteLogged，
  // 含空保活帧，只在日志开关打开时测）是两个指标勿混——本字段是体感口径**常开**。消费链 =
  // onDone 第四参 → ChatUsageRoundCtrl 轮级累积（首个非 0 胜出）→ 账本
  // token_usage_events.firstTokenMs → 气泡用量弹层与用量面板
  private firstTokenMs: number = 0;
  // 单次响应累计接收字节数：onChunk 首句累加并判上限（先于 decode——超限分片不进解码与
  // 解析）；每流独立
  private receivedBytes: number = 0;
  // DS 扩展字段（二期 S2；null = 非 DS 轮/未开启——子类 requestBody 读它，基类零消费）
  protected dsExtras: DsStreamExtras | null = null;

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

  // 请求体 JSON 串（方言转换在各协议子类 compose 纯函数）：thinking = 思考档位（'' = 不传）；
  // sampling = 助手采样参数（null = 不带任何采样字段）；tools = 工具声明（缺省 [] = 不带
  // tools 字段请求体零回归）
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

  // 增量投递（子类 consumePayload 消费）：标记有效帧 + 空增量不回调（工具调用增量同理有效；
  // reasoning item 捕获帧以 kind='delta' + 空文本携带载荷，无此门控会被空增量过滤吞掉；
  // DeepSeek 服务端工具两族载荷同理——事件帧常无 delta 文本、末帧可无正文，S2④ 放行）
  protected deliverDelta(delta: SseDelta): void {
    this.sawValidFrame = true;
    const hasTools: boolean = delta.toolCalls !== undefined && delta.toolCalls.length > 0;
    const hasReasoningItems: boolean =
      delta.reasoningItems !== undefined && delta.reasoningItems.length > 0;
    // DS 服务端工具两判据（S2④，照 reasoningItems 放行先例）：①事件（choices[0] 级，帧常
    // 无 delta 文本）；②末帧两字段（server_tool_calls/annotations——正文与两字段可不同帧）。
    // 空文本帧不吞；计入 sawContent（serverstep 行是上屏产出——预算耗尽分路「有产出收尾」
    // 口径一致；不计 sawToolCall——服务端调用无客户端派发面，残缺调用问题不存在）
    const hasServerToolEvent: boolean = delta.serverToolEvent !== undefined;
    const hasServerTailPayload: boolean = delta.serverToolCallsJson !== undefined ||
      delta.annotationsJson !== undefined;
    // DS 扩展字段帧（二期 S2/S3）：标题 / 拒答 / 拒答标记 / Responses output 快照——这些帧常无
    // 正文增量，门控外会被吞（title 尾帧、content_filter 空帧、completed 帧的 output）
    const hasDsExtrasPayload: boolean = delta.title !== undefined || delta.refusal !== undefined ||
      delta.contentFiltered === true || delta.responsesOutputJson !== undefined;
    if (delta.content !== '' || delta.reasoningContent !== '' || hasTools || hasReasoningItems ||
      hasServerToolEvent || hasServerTailPayload || hasDsExtrasPayload) {
      // 自动重试判据源（★ 2026-09-22）：置真点必须在门控**内**——门控前会被零增量帧喂真
      this.sawContent = true;
      if (hasTools) {
        this.sawToolCall = true;
      }
      // 首字打戳三条件缺一不可：①门控内（门控外会被空保活帧与纯 usage 帧误打）；②只认
      // 正文/思考（工具帧不是「字」，工具轮先出工具调用时首字留给后续产出正文的那条流）；
      // ③首个为准（后面的增量不覆盖）。打戳在 onDelta 之前 = 该增量的到达时刻
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

  // 流内 usage 累积单点（子类 consumePayload 从解析产物摘 usage 后调）；take-max 合并在
  // SseParser.mergeUsage 纯函数，基类只持累积态
  protected absorbUsage(usage: AiUsageDelta | undefined): void {
    if (usage === undefined) {
      return;
    }
    this.usageAccum = mergeUsage(this.usageAccum, usage);
  }

  // 截断标记吸收单点（子类 consumePayload 摘 delta.truncated 后调；须在 deliverDelta 之前
  // ——截断帧无增量会被门控吞）。只认 true（无截断是常态，零介入）
  protected absorbTruncated(flag: boolean | undefined): void {
    if (flag === true) {
      this.sawTruncated = true;
    }
  }

  // 流中错误帧路径（如 Anthropic error 帧；终态语义与 fail 同源）。此处 statusCode 必然仍是
  // -1——错误帧在流内到达，而状态码唯一写点 = 流末才 resolve 的 requestInStream Promise
  //（坑19 机制），透 -1 会把协议层错误误归因为传输层失败，故响应码未落定时透专属哨兵；
  // 已落定（尾冲刷帧，decideEnd 的 parser.finish() 路径）仍照原样透真码
  protected failStream(message: string): void {
    this.fail(message, this.statusCode === -1 ? STREAM_ERROR_STATUS : this.statusCode);
  }

  // source = 请求日志用途标签（省略 = '聊天'，正常发送不传即零回归；连接能力测试 T2/T3
  // 流式探针显式传 '连通性测试' 以便日志分辨）
  start(conn: AiConnection, apiKey: string, messages: AiChatMessage[], thinking: string,
    sampling: SamplingParams | null, tools: AiToolDef[] = [], source: string = '聊天',
    dsExtras: DsStreamExtras | null = null): void {
    // DS 扩展字段先落字段（requestBody 读它）——缺省 null = 既有调用零变化
    this.dsExtras = dsExtras;
    // 流式时长锚（durationMs = 本流 start→onDone 墙钟，口径「纯流式时间」——网络等待计入、
    // 工具执行等待不在流内天然不计）
    this.streamStartMs = Date.now();
    // ★ start 是**异步终态契约**——成功/失败一律经 onDone/onError 回来，同步抛出 = 本轮既无
    // 终态回调、日志条目又永停「进行中」，界面停在生成态等一个永不到来的回调（调用方各自的
    // catch 兜得住不崩，但会误归因）。故按成因分两段各设守卫、都落回统一收尾 fail()：①组装段
    // ——请求还没交给系统，属本端问题（协议钩子/自定义头/覆盖表/端点拼接）；②传输段——交给
    // 系统之后，含三句事件订阅（SDK 面，抛错即静默悬停）。★ reqLogBegin 刻意留在两段守卫之
    // 外：它是傍路，自带全程 try（见 ReqLog.ets 头），纳入守卫会把日志侧异常升级成「正常发送
    // 被判死」
    let header: Record<string, string> = {};
    let bodyText: string = '';
    let url: string = '';
    try {
      // 内置头 → 全局 UA 兜底 → 自定义头逐条追加（可覆盖前者含认证头；空 k 行守一道；
      // 大小写不敏感写入——自定义头仍可覆盖全局 UA）
      header = this.requestHeaders(conn, apiKey);
      applyDefaultUserAgent(header);
      for (const pair of conn.headers) {
        if (pair.k !== '') {
          setHeaderCaseInsensitive(header, pair.k, pair.v);
        }
      }
      // 请求体先成局部量再进 options：日志要记的就是这串最终产物（含 bodyOverrides 合并
      // 结果），事后从 options.extraData 反取会撞联合类型（string | Object | ArrayBuffer）
      bodyText = mergeBodyOverrides(
        this.requestBody(conn, messages, thinking, sampling, tools), conn.bodyOverrides);
      url = this.endpoint(conn);
    } catch (e) {
      // 组装失败是本端问题不是网络故障——照实说，否则用户会去查网络。状态码照实透组装哨兵
      //（透 -1 会被 notice 分类误挂跳网络设置页动作，见 AiTypes.ASSEMBLY_FAIL_STATUS）；URL
      // 与请求体都没成型，本路径零日志条目（条目本就建在组装之后）
      this.fail('请求组装失败：' + describeNetError(e as Object), ASSEMBLY_FAIL_STATUS);
      return;
    }
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: header,
      extraData: bodyText,
      usingCache: false,
      connectTimeout: CONNECT_TIMEOUT_MS,
      readTimeout: netReadTimeoutMinutes() * 60000
    };
    // 代理兜底（applyDefaultUserAgent 同形注入族姿势）：system 档（与 custom 档解析失败钳回）
    // 零介入 = options 原样；direct/custom 档才写 usingProxy 字段
    applyEffectiveProxy(options);
    // 请求日志埋点：URL / 最终头（内部掩码）/ 最终体（内部截断）此刻全部就位——四协议共用
    // 本处，一处埋点覆盖全部聊天流式链；未开启返回空 id，后续回填自动短路。模型名取自连接
    //（多模型/多中转站下 URL 一模一样，没它列表行分不出这条是谁发的）
    this.reqLogId = reqLogBegin({
      source: source, model: conn.model, method: 'POST', url: url, headers: header,
      body: bodyText
    });
    // 订阅三句与起流同守卫：on 无已知抛错路径，但它是 SDK 面、订阅成败决定本轮能否收回调
    // ——异常外泄即静默悬停，故一并落回统一收尾
    try {
      this.request.on('dataReceive', (chunk: ArrayBuffer): void => this.onChunk(chunk));
      this.request.on('dataEnd', (): void => this.onEnd());
      // 响应头：流式链拿不到 HttpResponse（requestInStream 只回状态码），白名单头只能走
      // 事件订阅；★ 与另两个订阅同点注册、在 release() 单点成对注销
      this.request.on('headersReceive', (header: Object): void => this.onHeaders(header));
      this.request.requestInStream(url, options)
        .then((code: number): void => {
          // Promise 流末落定（坑19）：此处只收状态码与补判收尾；数据路由已在 dataReceive
          // 乐观分发完毕（见头注释）
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

  // 停止 = 中止请求 + 走 error 终态（统一收尾路径防回调分叉）。日志记取消哨兵而非 -1（用户
  // 主动停止不是传输层失败，见 common/ReqLog.ets 头分家）；透给 onError 的状态码仍是 -1，
  // 自动重试域判据零影响
  abort(): void {
    this.fail('已手动停止', -1, REQ_LOG_STATUS_CANCELED);
  }

  // 静默释放（页面销毁路径专用）：中止且不触发任何回调——防销毁后回调再触 UI（红线「页面
  // aboutToDisappear 中止进行中流式并解绑回调」；DB 残留 streaming 态由下次启动
  // markStreamingAsError 兜底转 error）
  disposeSilent(): void {
    if (this.finished) {
      return;
    }
    this.finished = true;
    this.release();
    // 零回调路径故日志在此单独收尾；状态记取消哨兵而非 -1（页面销毁是用户动作，不是网络故障）
    reqLogEnd(this.reqLogId, REQ_LOG_STATUS_CANCELED, Date.now() - this.streamStartMs,
      '页面已关闭，请求已取消', '');
  }

  private onChunk(chunk: ArrayBuffer): void {
    if (this.finished) {
      return;
    }
    // 累计接收预算：先于 decode 与首字节打戳——超限的分片不进解码与解析；耗尽统一走
    // onBudgetExhausted 分路收口（截断收尾 / 显式失败，判据见该法注释）
    this.receivedBytes += chunk.byteLength;
    if (this.receivedBytes > STREAM_RECEIVED_MAX_BYTES) {
      this.onBudgetExhausted();
      return;
    }
    // 首字节打戳整条流只上报一次（布尔位挡热路径，见 firstByteLogged 声明处）
    if (!this.firstByteLogged) {
      this.firstByteLogged = true;
      reqLogMarkFirstByte(this.reqLogId);
    }
    // decodeToString stream 模式：UTF-8 多字节字符跨分片不撕裂（decodeWithStream 已废弃）
    const text: string = this.decoder.decodeToString(new Uint8Array(chunk), { stream: true });
    this.routeText(text);
  }

  // 响应头回调：白名单过滤与脱敏都在 ReqLog 内部完成，本层只透传（未开启时零副作用；内部
  // 全程 try，异常不得打断正在进行的流）
  private onHeaders(header: Object): void {
    reqLogSetResponseHeaders(this.reqLogId, header);
  }

  // 乐观分发（坑19）：不等状态码（唯一来源 = 流末才落定的 Promise，见头注释）全部喂解析器
  // 即时派发；errorBody 同步尾部有界累积（流末非 200 时 extractApiError 呈报用）。
  private routeText(text: string): void {
    const payloads: string[] = this.parser.feed(text);
    // 单行/单事件预算超限：信号非空即显式失败——已凑齐的合法载荷一并放弃（流已失败，终态
    // 闸吞后续回调），无「截断后继续」形态
    if (this.parser.limitBreach !== null) {
      this.failSseLimitBreach();
      return;
    }
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

  // SSE 单行/单事件超限的失败收口：按解析器信号分档出中文提示（数字取常量现读，防「改了
  // 上限提示仍写旧数」）；状态码用 STREAM_ERROR_STATUS（数据层明确拒绝，同 failStream 归因）
  private failSseLimitBreach(): void {
    const breach: SseLimitBreach | null = this.parser.limitBreach;
    if (breach === null) {
      return;
    }
    if (breach.kind === 'line') {
      this.fail('接收到的数据单行超长，已停止接收。单行上限 ' + SSE_LINE_MAX_CHARS + ' 字符',
        STREAM_ERROR_STATUS);
      return;
    }
    this.fail('接收到的数据单帧超长，已停止接收。单帧上限 ' + SSE_EVENT_MAX_CHARS + ' 字符',
      STREAM_ERROR_STATUS);
  }

  // 接收预算耗尽分路收口（判据与拍板记录见常量注释）：有内容且无工具调用 = 截断收尾——
  // 置截断标记后走 complete()（onDone truncated=true 全链：用量轮累积截断末流胜出 → 气泡
  // 截断尾注，半截内容保留、run 正常收尾、不报错）；零内容（垃圾流/非 200 大错误体，无产
  // 可留）或出现过工具调用（防把截断当正常完成后续轮派发残缺调用）= 显式失败，文案带实际
  // 字节数。终态安全：finished 闸吞尽后续回调——流末 Promise resolve/catch（坑19）与残余
  // dataReceive/dataEnd 均无害，release 内 destroy 中止传输
  private onBudgetExhausted(): void {
    if (this.sawContent && !this.sawToolCall) {
      this.sawTruncated = true;
      this.complete('接收预算耗尽已截断收尾，已接收 ' + this.receivedBytes +
        ' 字节，上限 ' + STREAM_RECEIVED_MAX_BYTES + ' 字节');
      return;
    }
    this.fail('本次响应数据总量超出上限，已停止接收。已接收 ' + this.receivedBytes +
      ' 字节，上限 ' + STREAM_RECEIVED_MAX_BYTES + ' 字节', STREAM_ERROR_STATUS);
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
    // 尾冲刷阶段的单行/单事件超限同理：尾行/未决事件判超限即显式失败（rest 放弃）
    if (this.parser.limitBreach !== null) {
      this.failSseLimitBreach();
      return;
    }
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

  // logNote = 请求日志备注（省略 = ''，常规完成零回归）；截断收尾路径传说明含实际接收
  // 字节数——状态码照原样透（流中截断时 -1 未落定，坑19 机制，如实记录，备注列解释）
  private complete(logNote: string = ''): void {
    if (this.finished) {
      return;
    }
    this.finished = true;
    this.release();
    // 请求日志成功终态：本路径时长 = 整轮流式墙钟（含末帧到 dataEnd 的收尾），贴近用户体感
    reqLogEnd(this.reqLogId, this.statusCode, Date.now() - this.streamStartMs, logNote, '');
    // 用量、时长、截断标记与首字耗时随完成带出（首字 0 = 未产出正文/思考增量，见字段注释）；
    // fail 路径 onError 不变——error 流无统计，也没有「被上限掐断」语义（截断是正常完成的流：
    // 模型把上限烧完即收尾，故走本路径而非 fail）
    this.handlers.onDone(this.usageAccum, Date.now() - this.streamStartMs, this.sawTruncated,
      this.firstTokenMs);
  }

  // logStatus = 请求日志侧的状态（省略 = 与 status 同值），仅取消类路径（abort）分家传取消
  // 哨兵；透给 onError 的 status 必须原样（自动重试域判据挂在那上面，勿牵连）
  private fail(message: string, status: number, logStatus?: number): void {
    if (this.finished) {
      return;
    }
    this.finished = true;
    this.release();
    // 请求日志失败终态：status 原样透出（-1 传输层 / -2 协议错误帧 / 真码）；errorBody 是
    // 非 200 场景排障时「对方到底说了什么」的唯一证据（routeText 有界累积 ≤500 字符）
    reqLogEnd(this.reqLogId, logStatus === undefined ? status : logStatus,
      Date.now() - this.streamStartMs, message, this.errorBody);
    this.handlers.onError(message, status, this.sawContent);
  }

  // 成对释放单点：off 全部事件 + destroy。每动作独立 try——单个 off 抛错不得跳过后续
  // off/destroy（否则 native 句柄泄漏，多轮工具调用逐轮累积）；幂等由 finished 闸保证单次执行
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

// 自定义 Body 覆盖 merge（RikkaHub 自定义请求体对齐）：把服务商级 [{k, v=JSON 值文本}]
// 逐键覆盖/追加到组装完成的请求体根对象——四协议统一在此一层处理（协议无关：顶层键各协议
// 各自规格，用户自担与服务商规格的兼容性——超限未知字段由服务商 400 自答走既有回显链，
// 不逐协议特判）。空覆盖表 = 原串原样返回（逐字节零回归）；坏 JSON 根对象（理论不可达）
// 也原样返回不发半成品；单条 v 非法 JSON = 跳过该键 + 日志（入库侧已校验，此为发送层
// 兜底，不静默中断请求）；同键覆盖内置键（与 headers「允许覆盖认证头」同语义拍板）。
// ★ 导出供连接能力 T1 自组非流式请求复用（不走流式链拿不到 start 内建的合并）——导出即
// 线上同一实现，禁为探针另写一份。
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

// 网络层错误描述：BusinessError 判定用 typeof code（坑 59 ②——禁 in 运算）。有码先查
// httpKit 错误码表（httpKitErrorMessage——中文错误文案事实单源）命中用中文人话，未列码走
// 原兜底句（拼码 + message）。timeoutSeconds 现读当前档位（netReadTimeoutMinutes × 60）：
// 2300028 在连接超时与读超时两档下都可能触发，文案按读档给（拍板禁吃码表默认值 30）
function describeNetError(e: Object): string {
  const biz = e as BusinessError;
  if (typeof biz.code === 'number') {
    const mapped: string = httpKitErrorMessage(biz.code, netReadTimeoutMinutes() * 60);
    if (mapped !== '') {
      return mapped;
    }
    const msg: string = typeof biz.message === 'string' && biz.message !== '' ? '，' + biz.message : '';
    return '无法连接服务器(code ' + biz.code + ')' + msg;
  }
  return (e as Error).message !== undefined ? (e as Error).message : '未知错误';
}
