// 请求日志（照竞品 RikkaHub「Logs」形制）：把真机实际发出的 HTTP 请求记下来——请求头（掩码
// 后）、请求体（截断后）、响应码 / 耗时 / 错误响应体尾部，供「连不上 / 发不出 / 用不了」类
// 问题在应用内自查，不必连电脑看 DevEco。
//
// 三条设计取舍（逐条对照竞品实况）：
// · 存储 = **纯内存环形缓冲**（REQ_LOG_MAX 条，新头插超限丢尾；进程退出即清、不落盘不导出）
//   ——「数据有界」红线落点：日志含对话内容与整份请求头，落盘会把隐私面扩大到备份 / 导出
//   链，收益只是「重启后还看得到」；
// · 开关 = AppStorage 持久键现读（PREF_REQ_LOG_KEY，默认关）：关态 reqLogBegin 返空 id、
//   reqLogEnd 短路——**关态零记录零开销**；默认关是刻意取向（默认开等于无声扩大隐私面）；
// · **密钥脱敏是硬红线**（KeyStore「明文不进 DB / 日志 / toast」）：头值按键名模糊匹配打码、
//   URL query 的 key / token 参数与 userinfo 口令同规则——竞品只掩 Proxy-Authorization
//  （`Authorization: Bearer sk-…` 与 `x-api-key` 明文进列表），不照抄该缺陷。★ 另一层**值级
//   脱敏**：错误信息与响应体来自服务商、可把我方头值原样回显（如 401 文案回显 sk-…），这两串
//   无键名可判——写入侧按「本条实际发出的凭据值」逐值**等长**替换（不缩短——截断提示判据比
//   长度，缩短会造假「已截断」；清单见 collectSecretValues，与名称判据两层互补）。
// · 诊断面：模型名单列一栏（多模型 / 多中转站 URL 相同，列表行要能看出谁发的）；首字节与整轮
//   总时长两个口径都记（各答一半诊断问题；首字节只在流式链可测，非流式记 0 = 不适用）；响应
//   侧白名单头（content-type / retry-after / *-request-id 排障三问——白名单制因响应头由服务
//   商任填黑名单列不全，set-cookie 一类一个不该进；成功响应正文仍不记）。
// · 掩码痕 = **事实字段**（ReqLogEntry.masked，三源写时置位）——「字段含 •」符号判据双向失真
//   （见 reqLogHasMask）；reqLogBegin 全程 try——日志是傍路绝不反噬主链（回填函数同规格）。
//
// 状态码语义（与 AiTypes.STREAM_ERROR_STATUS / ASSEMBLY_FAIL_STATUS / ChatStreamBase 同源，
// 勿另立一套）：0 = 进行中（请求已发出、响应未落定）；正数 = HTTP 响应码；-1 = 传输层失败；
// -2 = 协议层错误帧哨兵；-3 = 用户主动中止（停止键 / 页面销毁取消）；-4 = 请求组装失败
//（本端问题非网络故障）。
// ★ -1 与 -3 的分家（坑75 家族）：「走不到响应码」在链上有四种成因——真网络错、用户点停止
//  （abort）、页面销毁（disposeSilent）、请求组装失败（记 -4）；早把后几类一并记成 -1，列表
//   显示成「网络失败」会把排障往错方向指，故各记专属哨兵（判据本体不变，语义各归各位）。
// ★ 该分家**只作用于日志**：ChatStreamBase.fail 透给 handlers.onError 的状态码仍是 -1——
//   自动重试域的判据挂在那（ChatSendCtrl / ChatAutoRetryCtrl），勿牵连。
//
// 埋点 = **全部出站 HTTP 链**在册（十一处基础 + 七处扩面，全链清单见变更记录对应笔条目）：
// · ChatStreamBase.start / complete / fail / disposeSilent —— 聊天流式四协议全链，含连接
//   能力 T2 / T3 流式探针（start 的 source 形参区分来源）；
// · TitleApi.requestTitleText —— 标题 / 记忆 / 记忆优化 / 记忆导入 / 压缩 / 推荐问题 /
//   主动消息七条小任务链（taskLabel 形参复用为来源标签）；
// · KeyConnectTester.probeText（T1 非流式探针）+ ModelListApi.fetchModelIds /
//   probeAnthropicMessages（拉模型清单与 anthropic 探针）；
// · ToolHttp.httpRequestRaw —— 控制台 http_request 工具全部调用（含掐断路径「已取消」终态
//   与「destroy 结算不得覆写」守卫，见该件 canceledLogIds）；
// · WebSearch.httpGet（local 搜索与 scrape_web 抓取）+ ApiSearchEngines.httpPostJson（博查 /
//   秘塔 / Serper，列表行以 URL 区分）+ OcrVisionApi.requestOcrBatch（多图分批每批一条）
//   + BalanceApi.fetchBalance + WebDavApi.davRequest / ensureDir（PUT / GET / DELETE /
//   OPTIONS 四方法 + MKCOL 逐段建目录，后者的 405「已存在」如实记 405）+
//   FeedbackMeow.sendFeedbackPush。
// ★ 状态码仍是 HTTP 码（不变量）：业务层失败只进 error 文案、列表不标红——四处登记在册
//  （反馈推送业务码〔HTTP 恒 200〕、秘塔 200 + 内嵌 errCode、余额与文字识别的「响应非 JSON /
//   缺正文」）；反方向同族 = MKCOL 405 正常流程却按非 2xx 标红。完整口径见变更记录技术债务
//   清单同条。
//
// ★ 本件刻意零 import（同 AppPreferences 的叶子姿态）：全部导出函数被
//   scripts/assert-reqlog-domain.mjs 剥 TS 后由 node 直跑（**线上同一实现**，不断言副本），
//   开关值走 AppStorage 桩注入。引任何模块都会让直跑副本断在未定义符号上——故此开关的键
//   常量定义在本件，AppPreferences 的两张备份分域表用字面量登记（键名单一来源 = 本文件）。

// 请求日志开关（持久键；语义与排除表理由见 AppPreferences 中 'prefReqLog' 条目）
export const PREF_REQ_LOG_KEY: string = 'prefReqLog';
// 环形缓冲容量：「数据有界」红线落点——50 条足以覆盖最近数轮对话的全部链路（含辅助链），
// 单条各字段全有上限（含 URL）：**载荷**最坏 ≈ 50 × 9KB ≈ 450KB，实测堆占用约 1MB 量级
//（50 条顶格 heapUsed +1.06MB）——仍是有界常数，别把 450KB 当堆占用读
export const REQ_LOG_MAX: number = 50;
// 单条各字段截断上限（**入栈前**就截断）：带 base64 图片的请求体可达 MB 级，不截断会把
// 图片整段驻留内存（竞品拦截器无截断的实测风险点）
export const REQ_LOG_BODY_MAX_CHARS: number = 4000;
export const REQ_LOG_HEADERS_MAX_CHARS: number = 2000;
export const REQ_LOG_TAIL_MAX_CHARS: number = 500;
// URL 上限：URL = 用户填的 baseUrl + 固定路径，baseUrl 输入框无长度校验 ⇒「单条有界」必须
// 由代码给而非靠用户输入自律；2000 与内置头段同量级，足以显示任何正常端点
export const REQ_LOG_URL_MAX_CHARS: number = 2000;
// 值级脱敏的最小长度（低于它的值不参与逐值替换——过短串会误伤正常文本）。★ 回显面的已知
// 缺口如实登记：凭据短于 8 字符 + 服务商回显时，清单装不下它、那两串又无键名可判 ⇒ 明文
// 进日志（见技术债务清单）
export const REQ_LOG_REDACT_MIN: number = 8;
// 进行中哨兵（真实 HTTP 码恒 ≥ 100，故 0 不与之撞）
export const REQ_LOG_STATUS_PENDING: number = 0;
// 用户主动中止哨兵（停止键 / 页面销毁取消；与 -1 传输层失败分家，见文件头「-1 与 -3 的分家」）
export const REQ_LOG_STATUS_CANCELED: number = -3;
// 模型名上限（服务商模型名是用户手填、输入框无长度校验，同 URL 的理由）
export const REQ_LOG_MODEL_MAX_CHARS: number = 200;
// 列表筛选档（页面 chips 与判据单源）：三档 = 全部 / 只看失败 / 只看 HTTP 请求。不单列
//「进行中」一档——在途条目瞬时即逝，真正要看的是「哪几条报错了」。「只看 HTTP 请求」=
// 出站记录入口退役后的承接档（HTTP 工具审计用法在本页按来源档完成，不再单开入口）
export const REQ_LOG_FILTER_ALL: string = 'all';
export const REQ_LOG_FILTER_FAIL: string = 'fail';
export const REQ_LOG_FILTER_HTTP: string = 'http';
// HTTP 请求工具家族的来源标签（**单一来源**：HttpTransport 两处 reqLogBegin 实参与本件来源
// 档判据同引本常量——将来改标签只改这里，筛选档不会静默失配）
export const REQ_LOG_SOURCE_HTTP: string = 'HTTP 请求';
// 脚本联网来源标签：沙箱 httpGet 发出的出站记录——复用 HTTP 工具域全链（出站治理 / Cookie /
// 凭据注入都在链内），但来源独立可辨（脚本的请求与工具直发的请求可分）。与
// REQ_LOG_SOURCE_HTTP 同属 HTTP 工具族——「只看 HTTP 请求」筛档判据为族判据，本来源可见
export const REQ_LOG_SOURCE_SCRIPT: string = '脚本联网';
// 图链下载来源标签：消息文本 Markdown 图链发送期下载的出站记录——用户贴链的用户意图行为，
// 独立轻量下载不走 HTTP 工具域，与 REQ_LOG_SOURCE_HTTP 刻意分族；「只看 HTTP 请求」只认
// HTTP 工具族，本来源只在「全部 / 只看失败」两档可见
export const REQ_LOG_SOURCE_TEXT_IMAGE: string = '图链下载';
// Python 自装包下载来源标签：管理页安装动作从 files.pythonhosted.org 拉 wheel 的出站记录
//（门 5）——同图链下载分族逻辑：用户显式安装动作、固定官方域名直连，不走 HTTP 工具域；
//「只看 HTTP 请求」筛档不认本来源，只在「全部 / 只看失败」两档可见
export const REQ_LOG_SOURCE_PY_INSTALL: string = 'Python 安装';

// 请求记录条目（列表与详情面板的数据源；status 语义见文件头）
export interface ReqLogEntry {
  id: string;
  at: number;
  source: string;
  model: string;
  method: string;
  url: string;
  status: number;
  durationMs: number;
  // 首字节相对起点的毫秒数（0 = 未记 / 不适用：非流式链记不了，见文件头扩充笔第二条）
  firstByteMs: number;
  headersText: string;
  bodyText: string;
  bodyLength: number;
  // 响应头（白名单过滤后的文本；空串 = 对方没回白名单内的头，或本链未接线）
  respHeadersText: string;
  // 掩码痕（**写时定论的事实**，供详情面板「密钥等敏感内容已自动打码」提示行；三源 =
  // URL 掩码产物 / 头部掩码 hit / 值级替换 hit——符号痕迹反推必错，见 reqLogHasMask）
  masked: boolean;
  error: string;
  responseTail: string;
}

// 发起记录入参（调用点按各自作用域填充；headers 传原始头表、body 传最终请求体串）。
// model = 本次请求用的模型名（拉模型清单这类不针对某个模型的请求传空串）
export interface ReqLogBeginArgs {
  source: string;
  model: string;
  method: string;
  url: string;
  headers: Record<string, string>;
  body: string;
}

// 空条目（页面 @State 初值与面板默认形参单源——两处各写一份十六字段字面量必漂移）
export function emptyReqLogEntry(): ReqLogEntry {
  return {
    id: '', at: 0, source: '', model: '', method: '', url: '',
    status: REQ_LOG_STATUS_PENDING, durationMs: 0, firstByteMs: 0, headersText: '',
    bodyText: '', bodyLength: 0, respHeadersText: '', masked: false, error: '', responseTail: ''
  };
}

// 环形缓冲（模块级单例；新条目头插 = 列表天然按时间倒序）
const logEntries: ReqLogEntry[] = [];
// 逐条待脱敏明细（**值级脱敏**用）：错误文本与响应体没有键名可判，只能按已知值替换。表仅
// 内存、与条目**三处成对增删**（begin 建 / end 用后即删 / 环形挤出与清空随删；成对性由本
// 域断言钉守）——无清理遗漏即无增长
const secretValues: Map<string, string[]> = new Map<string, string[]>();
let logSeq: number = 0;

// 开关现读（AppStorage 每次现读 = 切换即时生效，下一个请求按新值）
export function reqLogEnabled(): boolean {
  return AppStorage.get<boolean>(PREF_REQ_LOG_KEY) === true;
}

// 记一条请求（返回条目 id 供 reqLogEnd 回填；**未开启时返回空 id**，调用点无需自己判开关）
// 全程 try 包裹（与两个回填函数同规格）：本函数跑在**发送链**上（流式 start 与非流式链的
// 组装段），抛错外泄会把一次正常发送变成失败——日志是傍路，绝不反噬主链。内部异常被吞 =
// 本条日志缺档，比消息发不出去轻（发现职责由本域行为直跑钉承担）
export function reqLogBegin(args: ReqLogBeginArgs): string {
  try {
    if (!reqLogEnabled()) {
      return '';
    }
    logSeq++;
    const id: string = 'rl' + logSeq;
    // URL 一次解析出两件：掩码后的串（入库）与其中的明文凭据（进值级脱敏清单）——同一次
    // 解析两处消费，防两套判据漂移
    const urlMask: UrlMaskResult = maskUrlWithSecrets(args.url);
    const secrets: string[] = collectSecretValues(args.headers, urlMask.secrets);
    // 头与体各过两层：名称判据（掩码）+ 值级替换（脱敏）。体先脱敏后截断——值若跨截断边界，
    // 先截会把密钥切成半截而漏配；等长替换不改长度，故截断语义与顺序无关
    const headMask: MaskHeadersResult = maskHeadersText(args.headers);
    const headRedact: RedactResult = redactSecrets(headMask.text, secrets);
    const bodyRedact: RedactResult = redactSecrets(args.body, secrets);
    const entry: ReqLogEntry = {
      id: id,
      at: Date.now(),
      source: args.source,
      model: clipText(args.model, REQ_LOG_MODEL_MAX_CHARS),
      method: args.method,
      url: clipText(urlMask.masked, REQ_LOG_URL_MAX_CHARS),
      status: REQ_LOG_STATUS_PENDING,
      durationMs: 0,
      firstByteMs: 0, // 流式链由 reqLogMarkFirstByte 回填（非流式链恒 0 = 不适用）
      headersText: clipText(headRedact.text, REQ_LOG_HEADERS_MAX_CHARS),
      bodyText: clipText(bodyRedact.text, REQ_LOG_BODY_MAX_CHARS),
      bodyLength: args.body.length,
      respHeadersText: '', // 响应到达后由 reqLogSetResponseHeaders 回填（白名单）
      // 掩码痕三源并行判（任一为真即真，见 ReqLogEntry.masked）：都用掩码函数自己的产物，
      // 不另立一套判据（两套必漂移）
      masked: urlMask.masked !== args.url || headMask.hit || headRedact.hit || bodyRedact.hit,
      error: '',
      responseTail: ''
    };
    logEntries.unshift(entry);
    if (logEntries.length > REQ_LOG_MAX) {
      const dropped: ReqLogEntry | undefined = logEntries.pop(); // 环形语义：只留最近 REQ_LOG_MAX 条
      if (dropped !== undefined) {
        secretValues.delete(dropped.id); // 明细随条目成对清（否则该表会无界增长）
      }
    }
    if (secrets.length > 0) {
      secretValues.set(id, secrets);
    }
    return id;
  } catch (e) {
    return '';
  }
}

// 回填终态（空 id 短路 = 本次未开启或已被环形挤出，静默返回不是失败）。四条终态路径都收敛
// 到这里：HTTP 非 200 / 正常完成 / 网络与协议失败 / 页面销毁取消
export function reqLogEnd(id: string, status: number, durationMs: number, error: string,
  responseTail: string): void {
  if (id === '') {
    return;
  }
  // 值级脱敏（本条的凭据明细）：这两串来自服务商原文，是唯一没有键名可判、又可能回显我方
  // 凭据的字段（401 文案「Invalid API Key = sk-…」一类）——写入前逐值替换
  const secrets: string[] | undefined = secretValues.get(id);
  const list: string[] = secrets === undefined ? [] : secrets;
  const errRedact: RedactResult = redactSecrets(error, list);
  const tailRedact: RedactResult = redactSecrets(responseTail, list);
  const tailHit: boolean = errRedact.hit || tailRedact.hit;
  for (const item of logEntries) {
    if (item.id === id) {
      item.status = status;
      item.durationMs = durationMs;
      item.error = clipText(errRedact.text, REQ_LOG_TAIL_MAX_CHARS);
      item.responseTail = clipText(tailRedact.text, REQ_LOG_TAIL_MAX_CHARS);
      // 掩码痕向上合并（本条终态文案也可能新引入掩码——服务商回显凭据只在失败时才出现）
      if (tailHit) {
        item.masked = true;
      }
      break;
    }
  }
  // 用后即删（条目可能已被环形挤出，故删除在循环之外——两种情形都要清）
  secretValues.delete(id);
}

// 首字节打戳：流式链在**首个数据块**到达时调一次。幂等——已记则忽略（调用点另用布尔位挡在
// 热路径上，见 ChatStreamBase.onChunk）。记**相对起点**的毫秒数而非墙钟时刻：直接复用
// reqLogDurationText 出文案，条目自足不依赖 at
// ★ 全程 try 包裹：本函数跑在数据回调的热路径上——任何内部异常都不得外抛打断正在进行的流
//（同 reqLogSetResponseHeaders）
export function reqLogMarkFirstByte(id: string): void {
  if (id === '') {
    return;
  }
  try {
    const now: number = Date.now();
    for (const item of logEntries) {
      if (item.id === id) {
        if (item.firstByteMs === 0) {
          item.firstByteMs = now - item.at;
        }
        break;
      }
    }
  } catch (e) {
  }
}

// 响应头回填：四条链各自拿到响应后调一次。★ **必须在 reqLogEnd 之前**调——凭据明细清单
// 在 end 时即删；万一顺序颠倒，本函数退化为「白名单单层」（白名单外的头本就不记录，泄露面
// 不扩大，只是少了值级替换这层保险）。空 id / 无白名单头命中时零副作用
// ★ 全程 try 包裹：调用点在请求链的 then 回调里，异常外抛会把一次成功请求变成失败（日志与
// 统计不得反噬主链）
export function reqLogSetResponseHeaders(id: string, raw: Object): void {
  if (id === '') {
    return;
  }
  try {
    const picked: string = pickResponseHeaders(raw);
    if (picked === '') {
      return;
    }
    const secrets: string[] | undefined = secretValues.get(id);
    const list: string[] = secrets === undefined ? [] : secrets;
    const red: RedactResult = redactSecrets(picked, list);
    for (const item of logEntries) {
      if (item.id === id) {
        item.respHeadersText = clipText(red.text, REQ_LOG_HEADERS_MAX_CHARS);
        // 掩码痕（值级替换真发生过才置位；同 reqLogEnd 的合并语义）
        if (red.hit) {
          item.masked = true;
        }
        break;
      }
    }
  } catch (e) {
  }
}

// 清空（页面菜单触发；逐条 pop 而非重赋新数组——本数组是模块级 const 绑定，只改内容不改绑定）
export function reqLogClear(): void {
  while (logEntries.length > 0) {
    logEntries.pop();
  }
  secretValues.clear(); // 明细与条目同寿命（见 secretValues 声明处）
}


// 快照（深拷贝出栈：调用方改不动内部缓冲，且「进行中」条目在页面上停留期间不会随后续
// 回填突变）
export function reqLogSnapshot(): ReqLogEntry[] {
  const out: ReqLogEntry[] = [];
  for (const item of logEntries) {
    out.push({
      id: item.id, at: item.at, source: item.source, model: item.model, method: item.method,
      url: item.url, status: item.status, durationMs: item.durationMs,
      firstByteMs: item.firstByteMs, headersText: item.headersText, bodyText: item.bodyText,
      bodyLength: item.bodyLength, respHeadersText: item.respHeadersText, masked: item.masked,
      error: item.error, responseTail: item.responseTail
    });
  }
  return out;
}

// ── 响应头白名单（**记哪些**响应头——与截断同为「有界」的落点）──

// 进日志的响应头（精确名）：content-type 判「200 却返回网页」、retry-after 判限流等多久、
// server 与 cf-ray 判对方是直连还是过 CDN 与网关
const RESP_HEADER_EXACT: string[] = ['content-type', 'retry-after', 'server', 'cf-ray'];

// 白名单判据（三条：精确名 / *-request-id 尾缀 / x-ratelimit 前缀）。★ 取向与脱敏词根表相反
// ——那边宁可过掩，这边宁可少记：响应头由服务商任填，set-cookie 与各类会话票据一个都不该进
// （按名排除比按值识别可靠）
function isWantedResponseHeader(name: string): boolean {
  const flat: string = name.toLowerCase();
  if (RESP_HEADER_EXACT.includes(flat)) {
    return true;
  }
  return flat === 'request-id' || flat.endsWith('-request-id') || flat.startsWith('x-ratelimit');
}

// 白名单过滤成文本（每行「键: 值」——与请求头同形，详情面板按行渲染）。无命中返回空串
// （空串即「本条没记响应头」，面板据此不渲染该卡）
export function pickResponseHeaders(raw: Object): string {
  const table: Record<string, string> = raw as Record<string, string>;
  const lines: string[] = [];
  for (const key of Object.keys(table)) {
    if (isWantedResponseHeader(key)) {
      lines.push(key + ': ' + table[key]);
    }
  }
  return lines.join('\n');
}

// ── 脱敏（硬红线：密钥不进日志）──

// 敏感键名词根（**模糊匹配**而非固定键名——provider 自定义头可覆盖内置认证头，只认固定名
// 会漏；归一化去 - 与 _ 后比对）
// ★ 'auth' 一词覆盖 authorization / auth / x-auth 全族：用户在中转站场景自命名这类验证头时
//   若漏掩，明文会随「复制」键流到第三方——帮助文案承诺「密钥等敏感内容会自动打码」。词根
//   判据取向**宁过掩不漏掩**：过掩只损失一条诊断信息，漏掩是红线 breach
// ★ 不列 'xgoog'：x-goog-* 一族只有 x-goog-api-key 是凭据，按前缀整体打码等于把排查素材
//   （x-goog-api-client 等）也抹掉——由下面的尾缀 key 族覆盖
// ★ 扩三族（只报未报的）：'pass'（含 password/passwd）· 'pwd' · 'credential'
//（x-amz-credential / x-credentials）· 'session'（会话票据——与响应头白名单排除
//   set-cookie 同一取向：票据不进日志）· 'sign'（签名族）。代价如实登记 = X-Session-* 这类
//   诊断头也一并掩值（宁过掩取向）
const SENSITIVE_NAME_ROOTS: string[] = ['auth', 'token', 'secret', 'cookie', 'pass', 'pwd',
  'credential', 'session', 'sign'];

export function isSensitiveName(name: string): boolean {
  const flat: string = name.toLowerCase().replace(/-/g, '').replace(/_/g, '');
  // 尾缀 key 族：key / api-key / x-api-key / x-goog-api-key / secret-key / accesskey……独立成
  // 一条而非并入词根表——`includes('key')` 会误伤 keyword 这类普通参数名（首跑实测钉抓到
  // `?key=sk-…` 未被掩，正是缺这一条）
  if (flat === 'key' || flat.endsWith('key')) {
    return true;
  }
  for (const root of SENSITIVE_NAME_ROOTS) {
    if (flat.includes(root)) {
      return true;
    }
  }
  return false;
}

// 值掩码（前 3 后 4；≤8 字符全掩——过短键不全露，防泄露整钥）。
// ★ 与 components/settings/ProviderKeyRowItem.maskKey 同形不同源：那件是密钥管理**展示**形制，
// 本件是请求头 / URL 脱敏，判据不同（前者无条件掩、后者按键名判定）；且 maskKey 在 UI 层，
// common 引它会反向依赖（assert-app-domain 环检测红）。统一另立一笔，不跨域私改（技术债务
// 清单已登记）
export function maskSecret(plain: string): string {
  if (plain.length <= 8) {
    return '••••';
  }
  return plain.substring(0, 3) + '••••' + plain.substring(plain.length - 4);
}

// 请求头整段成文本（已掩码；每行「键: 值」——详情面板按行渲染）。同时报**有没有掩过**（hit）
// ——掩码痕三源之一。hit 与掩码动作**同分支产出**（不另设一套判据：两套必漂移，坑26 家族）
export interface MaskHeadersResult {
  text: string;
  hit: boolean;
}

export function maskHeadersText(headers: Record<string, string>): MaskHeadersResult {
  const lines: string[] = [];
  let hit: boolean = false;
  for (const key of Object.keys(headers)) {
    const value: string = headers[key];
    const sensitive: boolean = isSensitiveName(key);
    if (sensitive) {
      hit = true;
    }
    lines.push(key + ': ' + (sensitive ? maskSecret(value) : value));
  }
  return { text: clipText(lines.join('\n'), REQ_LOG_HEADERS_MAX_CHARS), hit: hit };
}

// URL 掩码产物（掩码串 + 其中的明文凭据清单——后者是值级脱敏的清单来源之一；一次解析两处
// 消费，防两套判据漂移）
export interface UrlMaskResult {
  masked: string;
  secrets: string[];
}

// URL 的两处凭据槽位打码：①**userinfo 口令**（`https://user:pass@host`——Base URL 允许带
// 凭据，保存校验只认 http(s):// 头，用户粘带口令的地址该口令就会随 URL 进日志）
// ②**query 密钥参数**（部分中转站 / 网关把 key 放 query 而非头，如 ?key=sk-…）。其余原样。
// ★ query 后带 `#fragment` 时（`?key=SECRET#a`）须先按 `#` 截断 query 段再取值——否则进
// 清单的值是复合串，服务商回显 `SECRET` 时匹配不上 ⇒ 明文残留（fragment 原样留在尾部）
export function maskUrlWithSecrets(url: string): UrlMaskResult {
  const secrets: string[] = [];
  const withUser: string = maskUrlUserInfo(url, secrets);
  const mark: number = withUser.indexOf('?');
  if (mark < 0) {
    return { masked: withUser, secrets: secrets };
  }
  const rest: string = withUser.substring(mark + 1);
  const hash: number = rest.indexOf('#');
  const query: string = hash < 0 ? rest : rest.substring(0, hash);
  const fragment: string = hash < 0 ? '' : rest.substring(hash);
  const parts: string[] = query.split('&');
  const out: string[] = [];
  for (const part of parts) {
    const eq: number = part.indexOf('=');
    if (eq < 0) {
      out.push(part);
      continue;
    }
    const name: string = part.substring(0, eq);
    const value: string = part.substring(eq + 1);
    if (isSensitiveName(name)) {
      pushSecretParts(secrets, value);
      out.push(name + '=' + maskSecret(value));
    } else {
      out.push(part);
    }
  }
  return { masked: withUser.substring(0, mark + 1) + out.join('&') + fragment, secrets: secrets };
}

// 旧名保留（页面与断言按它调，行为逐字不变——内部走同一次解析）
export function maskUrlSecrets(url: string): string {
  return maskUrlWithSecrets(url).masked;
}

// userinfo 口令打码：只认**授权段**里的第一个 @（`//` 之后、首个 `/` 之前），且要有 `:` 才
// 算带口令（`https://token@host` 这种无冒号形态不掩——它按名无从判断是不是凭据，如实留原样）
function maskUrlUserInfo(url: string, secrets: string[]): string {
  const at: number = url.indexOf('@');
  if (at < 0) {
    return url;
  }
  const scheme: number = url.indexOf('//');
  if (scheme < 0 || at < scheme + 2) {
    return url;
  }
  const hostEnd: number = url.indexOf('/', scheme + 2);
  if (hostEnd >= 0 && at > hostEnd) {
    return url; // @ 落在路径里（如 https://host/v1/a@b），不是 userinfo
  }
  const colon: number = url.lastIndexOf(':', at);
  if (colon < scheme + 2) {
    return url; // 只有用户名没有口令
  }
  const pass: string = url.substring(colon + 1, at);
  pushSecretParts(secrets, pass);
  return url.substring(0, colon + 1) + maskSecret(pass) + url.substring(at);
}

// 本条请求实际发出的凭据明文（值级脱敏清单）：来源 = 敏感头值（含按空白拆出的 token 段——
// `Authorization: Bearer sk-…` 被服务商回显的多半只是 token 本身）+ URL 两处槽位的值
export function collectSecretValues(headers: Record<string, string>,
  urlSecrets: string[]): string[] {
  const out: string[] = [];
  for (const key of Object.keys(headers)) {
    if (isSensitiveName(key)) {
      pushSecretParts(out, headers[key]);
    }
  }
  for (const value of urlSecrets) {
    pushSecretParts(out, value);
  }
  return out;
}

// 收一个值进清单（整值 + 按空白拆出的各段，均过长度门槛并去重）
function pushSecretParts(out: string[], value: string): void {
  for (const part of value.split(' ')) {
    if (part.length >= REQ_LOG_REDACT_MIN && !out.includes(part)) {
      out.push(part);
    }
  }
  if (value.includes(' ') && value.length >= REQ_LOG_REDACT_MIN && !out.includes(value)) {
    out.push(value);
  }
}

// 值级替换（命中即整段换成**等长**占位，不缩短——理由见文件头；清单为空或未命中时原样
// 返回）。返回 {text, hit}：hit = 是否真发生过替换，即**掩码痕的事实来源**（见
// ReqLogEntry.masked）——「这一条被掩过吗」只能在替换发生的当口判定，事后按符号痕迹反推必错
export interface RedactResult {
  text: string;
  hit: boolean;
}

export function redactSecrets(text: string, values: string[]): RedactResult {
  let out: string = text;
  let hit: boolean = false;
  for (const value of values) {
    if (value !== '' && out.includes(value)) {
      out = out.split(value).join(maskOfLength(value.length));
      hit = true;
    }
  }
  return { text: out, hit: hit };
}

// 等长掩码（• × 长度；不用 String.repeat，逐字符拼——兼容性与显式性都更好）
function maskOfLength(len: number): string {
  let out: string = '';
  for (let i = 0; i < len; i++) {
    out += '•';
  }
  return out;
}

// 有界截断单点（超限加省略号；调用方给上限）
export function clipText(text: string, maxChars: number): string {
  return text.length > maxChars ? text.substring(0, maxChars) + '…' : text;
}

// ── 展示文案纯函数（列表与详情面板共用单源，不进 UI 组件）──

// 状态文案：0 进行中 / 正数 HTTP 码 / -1 网络失败 / -2 协议错误 / -3 已取消 / -4 组装失败
export function reqLogStatusText(status: number): string {
  if (status === REQ_LOG_STATUS_PENDING) {
    return '进行中';
  }
  if (status > 0) {
    return 'HTTP ' + status;
  }
  if (status === REQ_LOG_STATUS_CANCELED) {
    return '已取消';
  }
  if (status === -2) {
    return '协议错误';
  }
  // 与 AiTypes.ASSEMBLY_FAIL_STATUS 同值（本件零 import，字面量在案——头注「同源勿另立」口径）
  if (status === -4) {
    return '组装失败';
  }
  return '网络失败';
}

// 成功判据（2xx）
export function reqLogOk(status: number): boolean {
  return status >= 200 && status < 300;
}

// 失败判据（列表状态色分档：错误色只给真失败——2xx、在途与用户主动取消都不算。取消是用户
// 动作、在途尚未有结论，两者标红都等于把非故障说成故障；坑75 家族，见文件头「-1 与 -3 的
// 分家」）
export function reqLogIsFailure(status: number): boolean {
  return !reqLogOk(status) && status !== REQ_LOG_STATUS_CANCELED &&
    status !== REQ_LOG_STATUS_PENDING;
}

// 列表筛选判据（★ 含来源档）：与着色同一根 reqLogIsFailure——「只看失败」下取消与在途也不
// 出现（那不是故障，理由同着色）；「只看 HTTP 请求」按来源**族判据**（HTTP 工具族含脚本联网
// ——审计面要看全部发出过的，不看状态，取消与在途的 HTTP 工具条目仍属该来源）；「图链下载」
// 不在族内、只在「全部 / 只看失败」两档可见
export function reqLogMatchFilter(status: number, source: string, filter: string): boolean {
  if (filter === REQ_LOG_FILTER_FAIL) {
    return reqLogIsFailure(status);
  }
  if (filter === REQ_LOG_FILTER_HTTP) {
    return source === REQ_LOG_SOURCE_HTTP || source === REQ_LOG_SOURCE_SCRIPT;
  }
  return true;
}

// 有无打码痕（详情面板「密钥等敏感内容已自动打码」提示行的判据）：读**写时定论的事实字段**
//（原「三处字段含 •」符号判据双向失真：①正文自带项目符号 • 时假阳性；②只掩 URL 查询参数
// 时反而不提示——三处字段里没有 URL。改判后判据落在写入侧三源，将来新增掩码面只需在写点
// 置位，本函数零改动）
export function reqLogHasMask(entry: ReqLogEntry): boolean {
  return entry.masked;
}

// 排查建议：按状态码给一句「下一步查什么」。抓包工具不做这类提示（假设使用者懂 HTTP），本页
// 面向的却是把 key 粘进来的普通用户——一句归因能省掉一整轮来回。无建议（2xx 正常、已取消、
// 在途）返回空串，面板按空串不渲染
export function reqLogAdvice(status: number, respHeadersText: string): string {
  // 200 也可能不是成功：中转站或网关把错误页以 200 顶回来时正文是 HTML，用户看到的只是
  // 「模型答非所问」——这条靠响应头 content-type 判，是本页最值钱的一条归因
  if (reqLogOk(status) && respHeadersText.toLowerCase().includes('content-type: text/html')) {
    return '返回的是网页而不是接口数据，这个地址可能被网关或错误页拦下了';
  }
  // 取消是用户自己的动作、在途尚无结论——两者都不是「出错」，不给建议（着色判据同此口径）
  if (status === REQ_LOG_STATUS_CANCELED || status === REQ_LOG_STATUS_PENDING) {
    return '';
  }
  if (status === 400) {
    return '请求被拒绝，检查模型名与自定义 Body 覆盖是否符合该服务商的要求';
  }
  if (status === 401) {
    return '检查密钥是否有效，以及所选协议与服务商是否匹配';
  }
  if (status === 403) {
    return '密钥没有权限，或请求被服务商按地区与内容策略拦下了';
  }
  if (status === 404) {
    return '检查接口地址是否写对，常见是路径里少了或多写了 /v1';
  }
  if (status === 408) {
    return '请求超时，稍后重试或换一个渠道';
  }
  if (status === 413) {
    return '请求内容过大，多为对话历史或图片太多';
  }
  if (status === 422) {
    return '请求格式被拒绝，检查自定义 Body 覆盖里的字段';
  }
  if (status === 429) {
    return '请求过于频繁被限流，稍后重试或换一个渠道';
  }
  if (status >= 500) {
    return '服务商或中转站故障，稍后重试';
  }
  if (status === -2) {
    return '响应不是有效的流式数据，该地址可能返回的不是流式内容';
  }
  // 组装失败（与 AiTypes.ASSEMBLY_FAIL_STATUS 同值）：本端问题，不给网络方向的建议
  if (status === -4) {
    return '请求在本端组装阶段就失败了，检查接口地址写法与自定义请求头、Body 覆盖的格式';
  }
  if (status < 0) {
    return '检查网络是否可用，以及接口地址能否访问';
  }
  return '';
}

// 耗时文案（<60 秒一位小数、≥60 秒「M 分 SS 秒」；口径照 SessionStatsSheet.durationText
// 既有形制，本件下沉 common 后为本页面单源）
export function reqLogDurationText(ms: number): string {
  if (ms <= 0) {
    return '';
  }
  if (ms < 60000) {
    return (ms / 1000).toFixed(1) + ' 秒';
  }
  const total: number = Math.floor(ms / 1000);
  const rest: number = total % 60;
  return Math.floor(total / 60) + ' 分 ' + (rest < 10 ? '0' + rest : '' + rest) + ' 秒';
}

// 列表行时间（HH:mm:ss——缓冲只存进程内最近 50 条，日内时刻足够定位）
export function reqLogClockText(at: number): string {
  const d: Date = new Date(at);
  return pad2(d.getHours()) + ':' + pad2(d.getMinutes()) + ':' + pad2(d.getSeconds());
}

// 详情面板时间（YYYY-MM-DD HH:mm:ss，本地时区）
export function reqLogFullTimeText(at: number): string {
  const d: Date = new Date(at);
  return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + ' ' +
    pad2(d.getHours()) + ':' + pad2(d.getMinutes()) + ':' + pad2(d.getSeconds());
}

function pad2(n: number): string {
  return n < 10 ? '0' + n : '' + n;
}
