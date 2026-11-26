// HTTP 工具域·回执组装纯函数域：readHeader / isTextContentType / fitHttpResult /
// resolveHttpTimeoutMs / clipResultText / maskResponseHeaders / formatTlsVersion /
// enrichHttpReceipt 八个纯函数与回执侧配套常量——职责一句话 = 把 HttpResponse 组装成有界
// 回执 JSON 的纯计算。零 import 工具域（坑50）：仅依赖 NetworkKit 类型位与 HttpOutboundGuard
//（retriable 分类）/ ReqLog（敏感头判据）/ AppPreferences（超时上限默认值）三叶子——
// 四者均不引本域，无环。
import { http } from '@kit.NetworkKit';
import { httpStatusRetriable, parseRetryAfterSeconds } from './HttpOutboundGuard';
import { isSensitiveName } from '../ReqLog';
import { HTTP_TIMEOUT_CEILING_MS_DEFAULT } from '../AppPreferences';

// ── 回执侧常量（传输层与入参闸常量留 ToolHttp）──
// 超时默认与下限（连接与读取同值）：默认 30 秒（放开可配前常量同值，行为零回归）；下限
// 5 秒 = 安全边界（官方 readTimeout 为 0 时**不超时**，钳制挡住 0 与过小值）。★ 导出：管道
// 总时长闸钳步内超时需要「未传档」真值（ToolHttp executePipeline 消费），与
// resolveHttpTimeoutMs 内部同源——禁第三处抄值
export const HTTP_TIMEOUT_MS_DEFAULT: number = 30000;
const HTTP_TIMEOUT_MS_MIN: number = 5000;
// 回执响应头闸：头个数 / 单键名 / 单值 / 总字符四维同时有界——防大响应头把 8192 结果预算
// 的 body 位挤空（fitHttpResult 只回缩 body，头必须在进预算前先有界；只封个数值长时服务端
// 用超长**键名**或 20 条长头即可把 body 顶空，外层 clipToolResult 对非搜索载荷是 substring
// 硬切 → 产出坏 JSON）。四条合计使头部分恒 ≈2.1K
const HTTP_RESULT_HEADERS_MAX: number = 20;
const HTTP_RESULT_HEADER_KEY_MAX: number = 64;
const HTTP_RESULT_HEADER_VALUE_MAX: number = 200;
const HTTP_RESULT_HEADERS_MAX_CHARS: number = 2048;
// 回执 content-type 长度上限（同属「回执 ≤8192」不变量）：取自响应头、服务端可任填，且
// fitHttpResult 只回缩 body 碰不到它——不封则一个超长 content-type 独自把终态顶过 8192
//（实测 4 万字符头 → 回执 40149 字符）。120 对合法值（含 charset 等参数）足够富余
export const HTTP_RESULT_CONTENT_TYPE_MAX: number = 120;
// 结果预算（终态整串 ≤ 此值——外层 clipToolResult 兜底永不触发的自控目标）
const HTTP_RESULT_MAX_CHARS: number = 8192;
// 预算回缩：转义膨胀余量（每轮回缩多收此量吸收 \n→\\n 等膨胀）与轮数上限（收敛保险）
const HTTP_BUDGET_ESCAPE_MARGIN: number = 512;
const HTTP_BUDGET_ROUNDS_MAX: number = 64;

// 响应头取值（键名按小写归一匹配——官方返回头键大小写不保证、native 侧按服务器原样保存
// 无归一化契约）。原「先小写直查再原名直查」在 name 恒小写时退化为重复查找、混合形态键
//（如 'Content-Type'）读空致文本分型整体失效——改遍历键 toLowerCase 对比，任一大小写形态
// 都命中。导出供直跑副本执行级验证
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
// 导出供直跑副本执行级验证
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

// 结果预算回缩：整串超预算时 body 按溢出量 +512 余量回缩重序列化，循环至收敛（≤64 轮）
// 或 body 耗尽（置 truncated 与中文说明）。pieceStart = 本次切片在全文中的起点——回缩同步
// 回退 nextStartIndex，续读连续性不破（照 ToolBrowse.fitResultBudget 同款语义）。导出供
// 直跑副本执行级验证
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
  // body 耗尽（或轮数保险触顶）仍超：正文置空 + 终态说明，元信息照回——url 已另行收口，
  // 本分支为轮数保险的不可达兜底
  rec['body'] = '';
  rec['truncated'] = true;
  rec['nextStartIndex'] = pieceStart;
  rec['note'] = '正文已截断，用 start_index 续读';
  return JSON.stringify(rec);
}

// 生效超时解析（纯函数，导出供断言直跑）：requestedMs ≤ 0（未传/非法）= min(默认 30 秒,
// 用户上限)；否则 clamp(传值, 5 秒, 用户上限)；ceilingMs ≤ 0（脏值防御）= 默认档 1 分钟。
// ★ 下限不可去掉——官方 readTimeout 为 0 时不超时（d.ts 明载），0 与过小值必须被挡住。
// ★ 非有限值守卫：NaN 会同时穿透 `NaN <= 0` 与 `NaN > 0` 两条分支原样返回 NaN ⇒ 双超时
// 落 NaN（官方契约要求 uint32；被解释为 0 即「不超时」，恰是本函数要挡的方向）。承诺 =
// 恒返回 [5 秒, 上限] 内的有限值；生产路径调用方已过滤，此处防后续新增调用点
export function resolveHttpTimeoutMs(requestedMs: number, ceilingMs: number): number {
  const ceiling: number = Number.isFinite(ceilingMs) && ceilingMs > 0 ?
    ceilingMs : HTTP_TIMEOUT_CEILING_MS_DEFAULT;
  const wanted: number = Number.isFinite(requestedMs) ? requestedMs : 0;
  if (wanted <= 0) {
    return Math.min(HTTP_TIMEOUT_MS_DEFAULT, ceiling);
  }
  return Math.max(Math.min(wanted, ceiling), HTTP_TIMEOUT_MS_MIN);
}

// 回执文本有界（纯函数，导出供断言直跑）：响应头键名 / 头值 / content-type 三处同用——
// 超限截尾加省略号。三处共用 = 三处后果相同（服务端任填的文本突破 8192 终态预算 ⇒ 外层
// clipToolResult 硬切出坏 JSON）
export function clipResultText(text: string, max: number): string {
  return text.length > max ? text.substring(0, max) + '…' : text;
}

// 响应头脱敏（纯函数，导出供断言直跑）：凭据类头值替换为「[已隐藏]」，个数 / 键名 / 单值 /
// 总量四维有界。★ 敏感判据 = ReqLog.isSensitiveName 单一来源：请求头脱敏与本处共用同一套
// 词根（auth / token / secret / cookie / pass / pwd / credential / session / sign 与 *key
// 尾缀），取向承该件「宁过掩不漏掩：过掩只损失一条诊断信息，漏掩是红线 breach」（响应头
// 里的会话票据会明文进回执、随会话落库并发给服务商）；两套判据并存必漂移（坑26 家族），
// 故并入既有判据而非扩写本地表
export function maskResponseHeaders(headers: Object): Record<string, string> {
  const out: Record<string, string> = {};
  const rec = headers as Record<string, Object>;
  let count: number = 0;
  let used: number = 0;
  for (const key of Object.keys(rec)) {
    if (count >= HTTP_RESULT_HEADERS_MAX) {
      break;
    }
    const value: Object = rec[key];
    // 非文本值防御：官方 header 为 Object 无归一化契约，d.ts 明示「数值型字段可达、上限
    // int64」——string/number/boolean 文本化保真；其余形态（普通对象等）String() 会产出
    //「[object Object]」触碰回执红线（本仓曾实证同款字样进回执），落「[非文本值]」占位，
    // 与敏感头「[已隐藏]」同形制
    const text: string = typeof value === 'string' || typeof value === 'number' ||
      typeof value === 'boolean' ? String(value) : '[非文本值]';
    const outKey: string = clipResultText(key, HTTP_RESULT_HEADER_KEY_MAX);
    const outValue: string = isSensitiveName(key) ? '[已隐藏]' :
      clipResultText(text, HTTP_RESULT_HEADER_VALUE_MAX);
    // 总量闸：键名与值各自封顶后仍可 20 条叠乘 ≈8.1K 独自顶掉整个预算——按「键 + 值 +
    // 引号冒号开销」累计，到线即停（与 20 键同口径的静默丢弃）
    const cost: number = outKey.length + outValue.length + 4;
    if (used + cost > HTTP_RESULT_HEADERS_MAX_CHARS) {
      break;
    }
    out[outKey] = outValue;
    used += cost;
    count++;
  }
  return out;
}

// TLS 版本枚举 → 文本（纯函数，导出供断言直跑）：官方 TlsVersion（d.ts @since 18）=
// 4/5/6/7 → TLSv1.0~1.3；明文 http 或未使用 TLS 时官方不给值，返 '' 由调用方决定是否回传
//（空值不占回执预算）
export function formatTlsVersion(version: number): string {
  if (version === 4) {
    return 'TLSv1.0';
  }
  if (version === 5) {
    return 'TLSv1.1';
  }
  if (version === 6) {
    return 'TLSv1.2';
  }
  if (version === 7) {
    return 'TLSv1.3';
  }
  return '';
}

// 回执公共字段（两分支共用）：耗时 / 响应头（脱敏 + 四维有界）/ 跳数 / 协议版本 / TLS
// 版本（仅 TLS 时回）/ 连接复用位。文本与二进制两分支同调——desc 写明 each response also
// carries headers, durationMs and redirectCount，只挂文本分支即与该承诺不符（P2-5 言行
// 一致）。字段与 body 同受 8192 终态预算：头先在 maskResponseHeaders 内有界，再与 body
// 一起进 fitHttpResult 自然回缩（新字段不得把 body 挤空）。失败语义（非 2xx 补
// retriable / retry_after_seconds，见下）随载，且导出供直跑副本执行级验证——「2xx 零新增
// 字段 / 4xx 不可重试 / 429 带等待秒数」三态都是行为面，源码形态钉守不住
export function enrichHttpReceipt(rec: Record<string, Object>, resp: http.HttpResponse,
  durationMs: number): void {
  rec['durationMs'] = durationMs;
  rec['headers'] = maskResponseHeaders(resp.header);
  // 失败语义：非 2xx 补 retriable 与 retry_after_seconds——模型据此判断「重发是否有意义、
  // 等多久再试」，不必从状态码与正文里猜。2xx/3xx 一律不加字段（成功路径观感零改动）；
  // 304 属 3xx 不落此处（未变回执另有 notModified 面，见执行器）
  const status: number = resp.responseCode;
  if (status >= 400) {
    rec['retriable'] = httpStatusRetriable(status);
    const retryAfter: number = parseRetryAfterSeconds(readHeader(resp.header, 'retry-after'),
      Date.now());
    if (retryAfter > 0) {
      rec['retry_after_seconds'] = retryAfter;
    }
  }
  // 连接信息组：官方把协议版本 / TLS / 复用位 / 跳数收在 connectionExtraInfo（@since 24，
  // 可选字段）——逐字段自 HttpResponse 直取编译不过（10505001 实锤：这些字段不在
  // HttpResponse 上），须经该字段取；未提供时整组不回
  const extra: http.ConnectionExtraInfo | undefined = resp.connectionExtraInfo;
  if (extra !== undefined) {
    rec['redirectCount'] = extra.redirectCount;
    rec['protocol'] = extra.networkProtocolName;
    const tlsText: string = extra.tlsVersion === undefined ? '' :
      formatTlsVersion(extra.tlsVersion as number);
    if (tlsText !== '') {
      rec['tls'] = tlsText;
    }
    // 连接复用位：官方 d.ts 语义 = true 复用（★ 官方网页 API 参考同字段说明与 d.ts 相反，
    // 疑为译误——以 d.ts 为准；真机验证项已随笔 4 登记）
    rec['connectionReused'] = extra.isReusedConnection;
  }
}
