// HTTP 工具域·单请求执行链域（自 ToolHttp.ets 域级拆分，沿革见 docs/变更记录.md）。
// 职责 = 「把已解析的单请求参数跑完整闸序并组装回执」：executeFlow（body 互斥 / 上行闸 /
// 上传源 / 出站治理四闸 / 限速熔断 / 条件缓存 / 凭据注入 / Cookie 回带 / 传输分流 / 回执
// 组装）+ streamReceipt（流式窗口路回执）+ 出站治理三实例工厂（hostGate / validatorCache /
// cookieJar——进程级单例，惰性构造防断言副本装载即炸，坑50 家族）+ toRequestMethod 翻译层。
// HttpFlowOutcome.fullBody = 响应完整文本正文（管道占位符提取的数据面，与回执分页无关），
// 非文本路恒 ''。
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { httpHostIntervalMs, httpTimeoutCeilingMs } from '../AppPreferences';
import { REQ_LOG_REDACT_MIN, REQ_LOG_SOURCE_HTTP, REQ_LOG_SOURCE_SCRIPT } from '../ReqLog';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { HTTP_KIT_CODE_TIMEOUT } from './WebSearchParse';
import { resolveTaskTimeoutMs } from './HttpTaskTable';
import { HttpCacheValidators, HttpHostGate, HttpValidatorCache, httpHostOfUrl,
  httpNetworkRetriable, httpStatusRetriable, parseRetryAfterSeconds } from './HttpOutboundGuard';
import { CredReplaceOutcome, credRefMisplacedErrorText, credRefsOutsideAllowedPlaces,
  credentialNameGroups, credentialValuesOf, EnvCredGroups, EnvCredItem, extractCredRefs,
  makeCredResolver, missingCredErrorText, replaceCredRefsInText,
  splitUrlQuery } from './HttpCredentials';
import { HTTP_CRED_OWNER_GLOBAL } from '../store/KeyStore';
import { hostAllowedByWhitelist, isCloudMetadataHost, metadataBlockedErrorText,
  scanCredentialPlaintext, sentinelBlockedErrorText, urlHasEmbeddedUserInfo,
  userInfoBlockedErrorText, whitelistBlockedErrorText } from './HttpPolicy';
import { httpAllowedHosts, normalizeHttpPolicyHost } from '../AppPreferencesHttp';
// 高效档下域名准入白名单不设限（决明 2026-11-09 拍板）：档位现读一次，与确认链同一生效时点
import { effectivePermissionMode, PERMISSION_MODE_FULL } from '../chat/PermissionMode';
import { clipResultText, enrichHttpReceipt, fitHttpResult, HTTP_RESULT_CONTENT_TYPE_MAX,
  isTextContentType, maskResponseHeaders, readHeader, resolveHttpTimeoutMs } from './HttpReceipt';
import { buildMultiFormData, HTTP_DOWNLOAD_MAX_LIMIT_BYTES,
  HTTP_UPLOAD_FILE_MAX_BYTES, matchUploadSource, MultipartBuildOutcome,
  MultipartFieldInput, MultipartFileInput, readUploadSourceAsBuffer,
  saveDownloadToWorkspace, UploadSourceMatch } from './HttpBinary';
import { aggregateEventsText, HTTP_STREAM_ERROR_CODE, HTTP_STREAM_IDLE_MS,
  HTTP_STREAM_WINDOW_BYTES_MAX, resolveStreamMaxEvents, resolveStreamWindowMs } from './HttpSse';
import { HttpCookieJar } from './HttpCookieJar';
import { ATTACHMENT_MATCH_WINDOW_MAX } from './ToolLimits';
import { httpRequestRaw, httpRequestStream, HttpSendPayload,
  HttpStreamWindow, HttpRawOutcome, HttpStreamOutcome } from './HttpTransport';
import { queryAttachmentsByConversation, queryWorkspaceFiles } from '../store/ChatDb';
import { AttachmentListRow } from '../store/AttachmentDb';
import { WorkspaceFileRow, WORKSPACE_ROWS_READ_MAX } from '../WorkspaceUtil';
import { workspaceFilesDir } from '../store/WorkspaceDb';

// ── 常量（HTTP_ARGS_MAX_CHARS 在 ToolHttp.execute，HTTP_REQUEST_METHODS 在 HttpPipeline）──
// 上行闸：请求体字符上限（按字符计，与响应侧 max_length 同口径；防大 body 灌进请求日志、
// 内存与每轮重发的历史）
const HTTP_BODY_MAX_CHARS: number = 20000;

// 分页默认与钳制（抄 MCP fetch 语义：默认 5000，钳 5000~8000）
export const HTTP_MAX_LENGTH_DEFAULT: number = 5000;
const HTTP_MAX_LENGTH_MIN: number = 5000;
const HTTP_MAX_LENGTH_MAX: number = 8000;

// URL 长度上限（字符）：url 键不可被预算回缩（fitHttpResult 只回缩 body），不设上限会
// 突破终态预算、外层 clipToolResult 硬切出坏 JSON——2048 收口保「终态整串 ≤8192」
export const HTTP_URL_MAX_CHARS: number = 2048;

// ── 出站治理实例（实现在叶子 HttpOutboundGuard）──
// 限速与熔断按域名跨 run 有效（同一会话两次工具轮共享节奏——这正是「同一域名被连续打」
// 要拦的形态）；校验缓存与 Cookie jar 按会话清（ensureSession）。
// ★ 惰性构造（不在模块顶层 new）：断言副本剥 import 后这些类是自由名，顶层求值当场
// ReferenceError、副本载入即炸（装载期不得求值跨件绑定，坑50 家族）
let httpHostGateInstance: HttpHostGate | null = null;
let httpValidatorCacheInstance: HttpValidatorCache | null = null;
let httpCookieJarInstance: HttpCookieJar | null = null;

function hostGate(): HttpHostGate {
  if (httpHostGateInstance === null) {
    httpHostGateInstance = new HttpHostGate();
  }
  return httpHostGateInstance;
}

function validatorCache(): HttpValidatorCache {
  if (httpValidatorCacheInstance === null) {
    httpValidatorCacheInstance = new HttpValidatorCache();
  }
  return httpValidatorCacheInstance;
}

function cookieJar(): HttpCookieJar {
  if (httpCookieJarInstance === null) {
    httpCookieJarInstance = new HttpCookieJar();
  }
  return httpCookieJarInstance;
}

// ── 执行链入参包（execute 解析产物；同步路与 async 后台链共用 executeFlow 零第二实现）──
export interface HttpFlowArgs {
  url: string;
  method: string;
  body: string;
  maxLength: number;
  startIndex: number;
  timeoutMsArg: number;
  wantDownload: boolean;
  fileArg: string;
  multipartArg: Record<string, Object> | null;
  headers: Record<string, string>;
  streamMsArg: number;
  maxEventsArg: number;
  wantStream: boolean;
  // 脚本联网桥路标记：true = 正文按原始字节随 outcome 外传（bytes 字段）、传输走
  // ARRAY_BUFFER 档、日志标「脚本联网」、不挂条件缓存头（脚本要的是正文本身，命中 304
  // 无正文可给——download 路同款判据）。既有调用方恒 false
  wantBytes: boolean;
}

// 执行链结果：json = 回执串；timedOut = 网络层超时、cancelled = 用户掐断（异步任务据此落
// 对应终态，同步调用方不消费——cancelled 必须外传，否则状态机六值的 cancelled 不可达）；
// fullBody = 响应完整文本正文（占位符提取的数据面，与回执分页无关），非文本路恒 ''；
// bytes = wantBytes 路的响应原始字节（仅桥路 2xx 非空，错误与文本路恒 null，桥按
// contentType 分派文本/字节形态）
export interface HttpFlowOutcome {
  json: string;
  timedOut: boolean;
  cancelled: boolean;
  fullBody: string;
  bytes: ArrayBuffer | null;
}

// ── 执行链（async 后台链与同步调用共用零第二实现；taskId = '' 同步路 / 非 '' 后台任务路，
// 仅用于超时语义与 timedOut 标记）──
export async function executeFlow(args: HttpFlowArgs, ctx: ToolExecutionContext,
  taskId: string): Promise<HttpFlowOutcome> {
  const flowFail = (json: string): HttpFlowOutcome =>
    ({ json: json, timedOut: false, cancelled: false, fullBody: '', bytes: null });
  const url: string = args.url;
  const method: string = args.method;
  const body: string = args.body;
  const headers: Record<string, string> = args.headers;
  // 互斥闸：body / file / multipart 至多其一，同传两个及以上点名冲突参数（P0-1 不静默取
  // 先者）——白名单 / URL / 长度 / stream×download 四闸已上移 execute，此处自 body 互斥起
  const requestModeCount: number = (body !== '' ? 1 : 0) + (args.fileArg !== '' ? 1 : 0) +
    (args.multipartArg !== null ? 1 : 0);
  if (requestModeCount > 1) {
    return flowFail(JSON.stringify({
      error: 'body、file 与 multipart 不能同时使用，请只保留一种请求体形式' }));
  }
  // GET/HEAD 不接受请求体（含 file 直传与 multipart——回执指引改 POST）；其余方法按提供发送
  if (requestModeCount > 0 && (method === 'GET' || method === 'HEAD')) {
    return flowFail(JSON.stringify({
      error: 'GET/HEAD 不接受请求体。如需提交数据请用 POST' }));
  }
  // 上行闸：请求体字符上限——超限中文报错，禁静默截断（P0-1）
  if (body.length > HTTP_BODY_MAX_CHARS) {
    return flowFail(JSON.stringify({
      error: '请求体过长，上限 ' + HTTP_BODY_MAX_CHARS + ' 字符。请精简正文后重试' }));
  }
  // ── 上传源匹配与闸（匹配报错在出站治理之前给出）──
  // 两段式：会话附件优先 → 工作区兜底（决明拍板）；匹配纯函数入参含 / 或 .. 按未命中。
  // 两域行一次性取回——file 直传与 multipart 逐件匹配共用同一份
  let uploadMatch: UploadSourceMatch | null = null;
  let matchConvRows: AttachmentListRow[] = [];
  let matchWsRows: WorkspaceFileRow[] = [];
  if (args.fileArg !== '' || args.multipartArg !== null) {
    // 会话附件匹配窗口单源（调窗只改 ToolLimits.ets，禁两处各写）
    matchConvRows = await queryAttachmentsByConversation(ctx.conversationId,
      ATTACHMENT_MATCH_WINDOW_MAX, 0);
    // 行集读取上限单源 = WORKSPACE_ROWS_READ_MAX（全仓读取实参单源钉守，禁裸字面量）
    matchWsRows = await queryWorkspaceFiles(WORKSPACE_ROWS_READ_MAX);
    uploadMatch = matchUploadSource(args.fileArg, matchConvRows, matchWsRows);
    if (args.fileArg !== '') {
      if (uploadMatch.state === 'none') {
        return flowFail(JSON.stringify({
          error: '没有找到名为「' + args.fileArg + '」的文件。会话附件看对话中的「[附件]」标注，也可以用文件工作区里的文件' }));
      }
      if (uploadMatch.state === 'multi') {
        return flowFail(JSON.stringify({
          error: '有多个名为「' + args.fileArg + '」的附件，暂不支持区分，请先删除多余同名附件' }));
      }
      // 工作区跨目录同名歧义态：与会话域 'multi' 防线分流，报错给可行解法；无此分支该态
      // 会坠落 size 闸后按空路径读源
      if (uploadMatch.state === 'ws-multi') {
        return flowFail(JSON.stringify({
          error: '工作区里有多个名为「' + args.fileArg + '」的文件，无法确定要上传哪一个。请重命名其中一份后重试' }));
      }
      if (uploadMatch.size > HTTP_UPLOAD_FILE_MAX_BYTES) {
        return flowFail(JSON.stringify({
          error: '文件「' + uploadMatch.displayName + '」超过 ' +
            (HTTP_UPLOAD_FILE_MAX_BYTES / (1024 * 1024)) + 'MB 的上传上限，无法发送' }));
      }
    }
  }
  // multipart 入参组装（匹配域同上两段式；件数/字段/单件闸在纯函数内）。
  // ★ 字段值是模型生成文本——出站哨兵扫描与凭据记号位置白名单两个防泄露面都必须覆盖
  //（只扫 URL/body/头值 = 字段值可绕过拦截原样外发）；值在下方字段解析时顺手收集，扫描
  // 与拦截两点共用。「上传文件内容豁免」拍板不变（文件是用户数据非模型生成，HttpBinary
  // 头注释口径）
  const multipartFieldTexts: string[] = [];
  let multiFormData: http.MultiFormData[] | null = null;
  if (args.multipartArg !== null) {
    const fieldsRaw: Object | undefined = args.multipartArg['fields'];
    const fields: MultipartFieldInput[] = [];
    if (typeof fieldsRaw === 'object' && fieldsRaw !== null && !Array.isArray(fieldsRaw)) {
      const fieldsRec = fieldsRaw as Record<string, Object>;
      for (const key of Object.keys(fieldsRec)) {
        const v: Object = fieldsRec[key];
        if (typeof v !== 'string') {
          // 非串值点名报错：不 String() 收编也不静默丢弃（静默丢字段 = 表单缺字段照发，
          // 模型与用户均无感知 = P0-1 静默失败）
          return flowFail(JSON.stringify({
            error: 'multipart 字段 ' + key + ' 的值必须是字符串。请修正后重试' }));
        }
        fields.push({ name: key, value: v });
        multipartFieldTexts.push(v);
      }
    }
    const filesRaw: Object | undefined = args.multipartArg['files'];
    if (!Array.isArray(filesRaw)) {
      return flowFail(JSON.stringify({
        error: 'multipart 的 files 必须是数组，每项含 attachment 附件名' }));
    }
    // 匹配域行复用上文一次性取回的一份（本支进入即 fileArg 为空，行已在段首取过）
    const files: MultipartFileInput[] = [];
    for (const item of filesRaw as Object[]) {
      if (typeof item !== 'object' || item === null || Array.isArray(item)) {
        continue;
      }
      const rec = item as Record<string, Object>;
      const attRaw: Object | undefined = rec['attachment'];
      if (typeof attRaw !== 'string' || attRaw.trim() === '') {
        return flowFail(JSON.stringify({
          error: 'multipart 的每个文件项都必须给 attachment 附件名' }));
      }
      const nameRaw: Object | undefined = rec['name'];
      const partMatch = matchUploadSource(attRaw.trim(), matchConvRows, matchWsRows);
      if (partMatch.state === 'none') {
        return flowFail(JSON.stringify({
          error: '没有找到名为「' + attRaw.trim() + '」的文件。会话附件看对话中的「[附件]」标注，也可以用文件工作区里的文件' }));
      }
      if (partMatch.state === 'multi') {
        return flowFail(JSON.stringify({
          error: '有多个名为「' + attRaw.trim() + '」的附件，暂不支持区分，请先删除多余同名附件' }));
      }
      // 同 file 直传路的工作区跨目录同名歧义态（文案规约两态分句式）
      if (partMatch.state === 'ws-multi') {
        return flowFail(JSON.stringify({
          error: '工作区里有多个名为「' + attRaw.trim() + '」的文件，无法确定要上传哪一个。请重命名其中一份后重试' }));
      }
      const filesDirWs: string = workspaceFilesDir();
      if (filesDirWs === '') {
        return flowFail(JSON.stringify({ error: '文件目录未就绪，无法上传' }));
      }
      files.push({
        fieldName: typeof nameRaw === 'string' ? nameRaw : '',
        attachment: partMatch.displayName, kind: partMatch.kind, mime: partMatch.mime,
        size: partMatch.size, filePath: filesDirWs + '/' + partMatch.localPath });
    }
    const outcome: MultipartBuildOutcome = buildMultiFormData(fields, files);
    if (!outcome.ok) {
      return flowFail(JSON.stringify({ error: outcome.errorText }));
    }
    multiFormData = outcome.data;
  }
  // 分页钳制：max_length 钳 5000~8000；start_index 负数归零（上界在拿到全文后钳）
  let maxChars: number = Math.round(args.maxLength);
  if (maxChars < HTTP_MAX_LENGTH_MIN) {
    maxChars = HTTP_MAX_LENGTH_MIN;
  }
  if (maxChars > HTTP_MAX_LENGTH_MAX) {
    maxChars = HTTP_MAX_LENGTH_MAX;
  }
  let start: number = Math.round(args.startIndex);
  if (start < 0) {
    start = 0;
  }
  // 非 ASCII URL 先做最小转义（官方：URL 含非 ASCII 抛 2300003）。逐段 encodeURIComponent
  // 只转义非 ASCII 与 URL 非法 ASCII（控制字符 / 空格 / " < > \ ^ ` | [ ]）——花括号必须
  // 保留 = 凭据记号 {{名称}} 语法锚点（encodeURI 会编花括号，凭据链消费的是本处已编码串，
  // 记号必失配、占位符静默原样发出）；既有 %XX 段 / 裸 % / 字面 %25 三形态零改写。与
  // WebSearch.fetchUrlContent 的 encodeURI 互指「改则同改」已解除——抓取域无凭据链、
  // 花括号编码无害，WebSearch 侧维持原状。正则集本身即触发条件（纯 ASCII 且无转义集
  // 字符时零命中零改写）。
  // ★ {{…}} 记号段豁免分支（交替优先吃掉完整记号原样保留，只对记号外段转义）——否则
  // 记号内非 ASCII / 空格被编成 %XX，extractCredRefs 提取乱码名与真名失配，query 位宽名 /
  // 含空格名凭据恒 missing。判据 = 分支 2 命中段首字符必在转义集（{ 不在集内），
  // startsWith('{{') 即分支 1 无歧义；不完整记号（无闭合）两分支均不命中原样保留，与
  // extractCredRefs 的未闭合不产出判据一致。
  // 已知边界（★ 决明拍板维持现形不修）：[ ] 在转义集内，纯 ASCII IPv6 字面量 URL（http://
  // [::1]:8080/）的 host 段会被编码不可解析——触发面极窄（IPv6 字面量直连仅本机调试，
  // 127.0.0.1/localhost/域名等价绕行）且失败可感知（结构化回执可换写法重试，无静默损坏）；
  // 修法均有实代价（转义集去 [ ] 会把 path/query 位裸括号改为原样发出，host 段豁免须解析
  // authority 段，违背范围克制）。重新评估触发 = 真实需求出现再议
  const requestUrl: string = url.replace(
    /\{\{[^{}]*\}\}|[\u0000-\u001F\u007F-\uFFFF "<>\\^`|\[\]]+/g,
    (seg: string): string => seg.startsWith('{{') ? seg : encodeURIComponent(seg));
  const enumMethod: http.RequestMethod = toRequestMethod(method);
  // 生效超时：同步路 = 模型传值经钳制收进 [5 秒, 用户上限档]；后台任务路 = 任务总时长上限
  //（resolveTaskTimeoutMs，兼作 readTimeout——触发即 timed_out）
  const timeoutMs: number = taskId !== '' ? resolveTaskTimeoutMs(args.timeoutMsArg) :
    resolveHttpTimeoutMs(args.timeoutMsArg, httpTimeoutCeilingMs());
  // ── 出站治理 ──
  // ①每域名出站闸：限速（用户档位现读）+ 熔断（上游 Retry-After 驱动的冷却）——被拒调用
  // 直接回结构化回执、真实请求不发出（保护对方服务，也不烧一次真实往返）
  const host: string = httpHostOfUrl(requestUrl);
  // ── 准入与防泄露（闸序在限速熔断之前——被拒请求不消耗节奏位，也不进请求日志）──
  // ①scheme 硬化：URL 内嵌 user:pass@ 恒拒（明文凭据会落请求日志、代理与对方访问日志多处；
  // query 里的 @ 不在 authority 段不误伤）
  if (urlHasEmbeddedUserInfo(requestUrl)) {
    return flowFail(JSON.stringify({ error: userInfoBlockedErrorText() }));
  }
  // ②云元数据地址恒拒（卫生性兜底——「内网不拦截」口径不变；host 归一小写去端口后比对，
  // 归一单源 AppPreferencesHttp）
  const policyHost: string = normalizeHttpPolicyHost(host);
  if (isCloudMetadataHost(policyHost)) {
    return flowFail(JSON.stringify({ error: metadataBlockedErrorText() }));
  }
  // ③域名白名单（用户主动收紧面；留空 = 不限。只约束首跳——kit 自动跟跳不逐跳校验，
  // 帮助条目写明该边界）。★ 高效档不设限（决明 2026-11-09 拍板「完全权限时不设限」）：
  // 档位与确认链同点现读，切换即时生效；谨慎 / 标准档照旧按名单收紧
  if (effectivePermissionMode() !== PERMISSION_MODE_FULL &&
    !hostAllowedByWhitelist(policyHost, httpAllowedHosts())) {
    return flowFail(JSON.stringify({ error: whitelistBlockedErrorText(policyHost) }));
  }
  // ④出站哨兵：模型直接贴值 = 绕过引用语法——URL、body、请求头值与 multipart 文本字段值
  // 里扫凭据库明文，命中即拦并指路改用 {{名称}}（凭据为零时只读一次元数据计数零开销；
  // 最小长度同源 REQ_LOG_REDACT_MIN，过短串误伤正常正文）。schema 的 headers 说明、帮助
  // 条目与工具描述均声称「直接粘贴会被拦下」——扫描面含头值与字段值该声称才成立
  const credGroups: EnvCredGroups = credentialNameGroups(ctx.assistantId);
  if (credGroups.assistant.length + credGroups.global.length > 0) {
    // 同名两命名空间先全局后助手装配——助手级后 set 覆盖同名键，与注入侧 makeCredResolver
    //「同名助手级优先」同序；反序则同名时助手级值明文躲过扫描
    const sentinelValues: Map<string, string> = new Map<string, string>();
    (await credentialValuesOf(HTTP_CRED_OWNER_GLOBAL)).forEach((v: string, k: string): void => {
      sentinelValues.set(k, v);
    });
    if (ctx.assistantId !== '') {
      (await credentialValuesOf(ctx.assistantId)).forEach((v: string, k: string): void => {
        sentinelValues.set(k, v);
      });
    }
    const headerTexts: string[] = Object.keys(headers).map((k: string): string => headers[k]);
    const scanTexts: string[] = [requestUrl, body].concat(headerTexts)
      .concat(multipartFieldTexts);
    const hitNames: string[] = scanCredentialPlaintext(
      scanTexts, sentinelValues, REQ_LOG_REDACT_MIN);
    if (hitNames.length > 0) {
      return flowFail(JSON.stringify({ error: sentinelBlockedErrorText(hitNames) }));
    }
  }
  const waitMs: number = hostGate().admit(host, Date.now(), httpHostIntervalMs());
  if (waitMs > 0) {
    // 等待秒数向上取整且至少 1（毫秒级残量报「0 秒」等于没给指令）
    const waitSeconds: number = Math.max(1, Math.ceil(waitMs / 1000));
    const recWait: Record<string, Object> = {};
    recWait['error'] = '为避免过于频繁地请求同一域名，本次调用已暂缓。请在约 ' + waitSeconds +
      ' 秒后重试';
    recWait['retriable'] = true;
    recWait['retry_after_seconds'] = waitSeconds;
    return flowFail(JSON.stringify(recWait));
  }
  // ②会话内验证器缓存（条件请求去重）：GET 且从头读（start_index = 0）时才挂条件头——
  // 续读 / download / 流式窗口路同判据（都要正文本身，命中 304 拿不到产物——续读拿不到
  // 续读段、下载零产物、事件流空窗口）；用户显式给了同名头时以用户为准（不覆盖）
  const verCache: HttpValidatorCache = validatorCache();
  verCache.ensureSession(ctx.conversationId);
  // Cookie jar 会话对齐（jar 分桶后本调用只触达本会话桶——并发会话各持各表）
  cookieJar().ensureSession(ctx.conversationId);
  let conditionalSent: boolean = false;
  if (enumMethod === http.RequestMethod.GET && start === 0 && !args.wantDownload &&
    !args.wantStream && !args.wantBytes) {
    const validators: HttpCacheValidators | undefined = verCache.lookup(requestUrl);
    if (validators !== undefined) {
      if (validators.etag !== '' && readHeader(headers, 'if-none-match') === '') {
        headers['If-None-Match'] = validators.etag;
        conditionalSent = true;
      }
      if (validators.lastModified !== '' && readHeader(headers, 'if-modified-since') === '') {
        headers['If-Modified-Since'] = validators.lastModified;
        conditionalSent = true;
      }
    }
  }
  // ── 凭据注入（记号语法与纯函数单源在 HttpCredentials；顺序在条件缓存头之后——条件头值
  // 来自响应头不含记号，随发送面整体替换无害）──
  // 位置白名单 → 两级解析（ctx 助手命名空间优先于 global）→ query 段与头值替换定稿
  // **发送面**；违规/缺失在执行器层拦下给中文回执，传输层零凭据知识。无记号请求零开销
  // 直通（不读 Asset 缓存不复制 headers）
  const misplacedNames: string[] = credRefsOutsideAllowedPlaces(requestUrl, body);
  // ★ multipart 字段值与 body 同语义（决明拍板）：{{名称}} 记号不在注入面（注入只走
  // query 段与头值），字面记号原样发给服务器 = 模型以为用上了凭据、实际发出占位符（静默
  // 降级）；纳入位置白名单违规点名拦截，与 body 走同一中文回执
  for (const fieldText of multipartFieldTexts) {
    for (const refName of extractCredRefs(fieldText)) {
      if (!misplacedNames.includes(refName)) {
        misplacedNames.push(refName);
      }
    }
  }
  if (misplacedNames.length > 0) {
    return flowFail(JSON.stringify({ error: credRefMisplacedErrorText(misplacedNames) }));
  }
  const queryRefs: string[] = extractCredRefs(splitUrlQuery(requestUrl)[1]);
  let headerRefsPresent: boolean = false;
  for (const headerKey of Object.keys(headers)) {
    if (extractCredRefs(headers[headerKey]).length > 0) {
      headerRefsPresent = true;
      break;
    }
  }
  let sendUrl: string = requestUrl;
  let sendHeaders: Record<string, string> = headers;
  if (queryRefs.length > 0 || headerRefsPresent) {
    const assistantOwned: Map<string, string> = ctx.assistantId === '' ?
      new Map<string, string>() : await credentialValuesOf(ctx.assistantId);
    const globalOwned: Map<string, string> = await credentialValuesOf(HTTP_CRED_OWNER_GLOBAL);
    const resolveCred = makeCredResolver(assistantOwned, globalOwned);
      // query 路凭据值经 encodeURIComponent 编码后进 query——值含 &/=/#/空格等保留字符时
      // 保持「字面值即参数值」语义（不编码会把值拆进别的参数，base64 padding 的 = 即真实
      // 场景）；未知名的 null 透传，missing 语义不变。头值无编码概念，沿用 resolveCred 不套编码
    const resolveQueryCred = (name: string): string | null => {
      const v: string | null = resolveCred(name);
      return v === null ? null : encodeURIComponent(v);
    };
    const missingNames: string[] = [];
    const urlParts: string[] = splitUrlQuery(requestUrl);
    if (urlParts[1] !== '') {
      const qOutcome: CredReplaceOutcome = replaceCredRefsInText(urlParts[1], resolveQueryCred);
      sendUrl = urlParts[0] + '?' + qOutcome.text;
      for (const n of qOutcome.missing) {
        if (!missingNames.includes(n)) {
          missingNames.push(n);
        }
      }
    }
    const replacedHeaders: Record<string, string> = {};
    for (const headerKey of Object.keys(headers)) {
      const hOutcome: CredReplaceOutcome = replaceCredRefsInText(headers[headerKey], resolveCred);
      replacedHeaders[headerKey] = hOutcome.text;
      for (const n of hOutcome.missing) {
        if (!missingNames.includes(n)) {
          missingNames.push(n);
        }
      }
    }
    // 缺失拦下（附可用名称清单——省一轮 env_list 往返；清单只含名称，值级信息零出现，
    // 不附用途——救急场景不需要）
    if (missingNames.length > 0) {
      const groups: EnvCredGroups = credentialNameGroups(ctx.assistantId);
      return flowFail(JSON.stringify({
        error: missingCredErrorText(missingNames,
          groups.assistant.map((e: EnvCredItem): string => e.name),
          groups.global.map((e: EnvCredItem): string => e.name)) }));
    }
    // 替换后长度重验（真值可能远长于记号——2048 上限对发送面 URL 依然成立）
    if (sendUrl.length > HTTP_URL_MAX_CHARS) {
      return flowFail(JSON.stringify({
        error: '凭据替换后 URL 超过 ' + HTTP_URL_MAX_CHARS +
          ' 字符上限。请减少查询参数或把凭据改放请求头' }));
    }
    sendHeaders = replacedHeaders;
  }
  // ── 发送面组装（凭据注入后：读源 + Content-Type 补设——补在发送面副本上，无记号场景
  // headers 与 sendHeaders 同引用，先复制再补防污染日志面原始入参）──
  let binaryBody: ArrayBuffer | null = null;
  if (args.fileArg !== '') {
    const filesDirWs: string = workspaceFilesDir();
    if (filesDirWs === '') {
      return flowFail(JSON.stringify({ error: '文件目录未就绪，无法上传' }));
    }
    try {
      binaryBody = readUploadSourceAsBuffer(filesDirWs + '/' + uploadMatch!.localPath);
    } catch (e) {
      return flowFail(JSON.stringify({
        error: '文件「' + uploadMatch!.displayName + '」读取失败：' + (e as Error).message }));
    }
  }
  if (binaryBody !== null || multiFormData !== null) {
    if (sendHeaders === headers) {
      const copy: Record<string, string> = {};
      for (const k of Object.keys(headers)) {
        copy[k] = headers[k];
      }
      sendHeaders = copy;
    }
    if (readHeader(sendHeaders, 'content-type') === '') {
      sendHeaders['Content-Type'] = multiFormData !== null ? 'multipart/form-data' :
        (uploadMatch!.mime !== '' ? uploadMatch!.mime : 'application/octet-stream');
    }
  }
  // ── Cookie 回带（发送面只补缺——用户显式 Cookie 头恒优先；jar 该会话有该 host 的
  // cookie 才注入，无则零开销零改动；会话键闭包原值直传不依赖 ensureSession 当前态，
  // 并发安全；★ 回带头只进发送面副本，日志面 headers 零回带头——凭据同一红线，守卫钉守）──
  const cookieValue: string = cookieJar().cookieHeaderFor(ctx.conversationId, policyHost);
  if (cookieValue !== '' && readHeader(sendHeaders, 'cookie') === '') {
    if (sendHeaders === headers) {
      const copy2: Record<string, string> = {};
      for (const k of Object.keys(headers)) {
        copy2[k] = headers[k];
      }
      sendHeaders = copy2;
    }
    sendHeaders['Cookie'] = cookieValue;
  }
  const payload: HttpSendPayload = {
    textBody: body !== '' ? body : null,
    binaryBody: binaryBody,
    multiFormData: multiFormData,
    asDownload: args.wantDownload,
    asBytes: args.wantBytes
  };
  const startedAt: number = Date.now();
  // 请求日志来源分派：桥路（wantBytes）标「脚本联网」；两常量单源在 ReqLog（读写两侧同引）
  const logSource: string = args.wantBytes ? REQ_LOG_SOURCE_SCRIPT : REQ_LOG_SOURCE_HTTP;
  // ── 传输分流：wantStream = 流式窗口路（text/event-stream 分帧聚合；非 SSE 照常收整包，
  // 窗口闸只兜挂死流）；否则同步整包路（download 含在内）
  if (args.wantStream) {
    const windowArg: HttpStreamWindow = {
      windowMs: resolveStreamWindowMs(args.streamMsArg),
      // 未传 max_events 也过钳制（未传 → 默认 200）——desc/schema 均声明「不填默认 200」（P2-5）
      maxEvents: resolveStreamMaxEvents(args.maxEventsArg),
      windowBytes: HTTP_STREAM_WINDOW_BYTES_MAX
    };
    const stream: HttpStreamOutcome = await httpRequestStream(enumMethod, method, sendUrl,
      sendHeaders, payload, ctx.runId, timeoutMs, windowArg, requestUrl, headers, logSource);
    // 熔断登记对齐同步路：429/503 冷却该域（重试放大面同在；Retry-After 自 headersReceive
    // 已收的响应头取）
    if (stream.statusOk && (stream.status === 429 || stream.status === 503)) {
      hostGate().noteRetryAfter(host, parseRetryAfterSeconds(
        readHeader(stream.header, 'retry-after'), Date.now()), Date.now());
    }
    return streamReceipt(url, stream, startedAt, maxChars, start);
  }
  return httpRequestRaw(enumMethod, method, sendUrl, sendHeaders,
    payload, ctx.runId, timeoutMs, requestUrl, headers, logSource)
    .then(async (out: HttpRawOutcome): Promise<HttpFlowOutcome> => {
      if (out.resp === null) {
        // 网络层失败：错误句原样透传（拍板设计：底层报文不美化），retriable 由 kit 码分类
        //（证书 / 策略 / 重定向上限 / 接收超限等确定性失败报 false）
        const recErr: Record<string, Object> = {};
        recErr['error'] = out.errorText;
        recErr['retriable'] = httpNetworkRetriable(out.errorCode);
        return { json: JSON.stringify(recErr), timedOut: out.errorCode === HTTP_KIT_CODE_TIMEOUT,
          cancelled: out.cancelled, fullBody: '', bytes: null };
      }
      const resp: http.HttpResponse = out.resp;
      const status: number = resp.responseCode;
      const contentType: string = readHeader(resp.header, 'content-type');
      const durationMs: number = Date.now() - startedAt;
      // 熔断登记：429 / 503 带回 Retry-After 时把该域名冷却——窗口内同域调用直接回执
      //（尊重对方限流信号，不让重试放大压力）；无头 / 不可解析时解析层返 0、零动作
      if (status === 429 || status === 503) {
        hostGate().noteRetryAfter(host,
          parseRetryAfterSeconds(readHeader(resp.header, 'retry-after'), Date.now()),
          Date.now());
      }
      // 条件请求命中（304）：正文未变、不重发——回「未变」短回执。仅在确实挂过条件头时
      // 走本支（没挂验证器却收到 304 = 对方异常，照普通响应走，不误报「未变」）
      if (status === 304 && conditionalSent) {
        const recNm: Record<string, Object> = {};
        recNm['url'] = url;
        recNm['status'] = status;
        recNm['notModified'] = true;
        // body 恒空串：fitHttpResult 的预算回缩以 body 为回缩量（无此键则回缩路径取不到类型）
        recNm['body'] = '';
        recNm['note'] = '资源自上次请求后未变化，未重发正文';
        enrichHttpReceipt(recNm, resp, durationMs);
        return flowFail(fitHttpResult(recNm, 0));
      }
      // 验证器入库（GET 200 且对方给了 ETag / Last-Modified；存请求串与下次 lookup 同键，
      // 续读照存——同一 URL 的验证器同源）
      if (enumMethod === http.RequestMethod.GET && status === 200) {
        verCache.store(requestUrl, readHeader(resp.header, 'etag'),
          readHeader(resp.header, 'last-modified'));
      }
      // ── Cookie 收割（官方 resp.cookies 聚合串）：仅非重定向响应收（redirectCount = 0
      //——kit 自动跟跳拿不到每跳 host，跳后域的 set-cookie 按首跳 host 落表 = 跨域错配，
      // 宁缺勿错，边界见 HttpCookieJar 文件头④）；host 按归一 policyHost 与回带侧同键；
      // 会话键闭包原值直传（并发会话各自落各自桶）
      const respExtra: http.ConnectionExtraInfo | undefined = resp.connectionExtraInfo;
      const redirectCount: number = respExtra !== undefined ? respExtra.redirectCount : 0;
      if (redirectCount === 0) {
        const rawCookies: string = resp.cookies;
        if (rawCookies !== '') {
          cookieJar().storeFromResponse(ctx.conversationId, policyHost, rawCookies);
        }
      }
      // ── 下载落盘（download 时正文不进对话，产物入工作区 source='download'；304 未变
      // 分支已在上方短路——无新正文可落；分页参数在 download 下自然不消费）──
      if (args.wantDownload) {
        if (status < 200 || status >= 300) {
          const recDlErr: Record<string, Object> = {};
          recDlErr['url'] = url;
          recDlErr['status'] = status;
          recDlErr['error'] = '下载失败，状态码 ' + status + '，未保存文件';
          enrichHttpReceipt(recDlErr, resp, durationMs);
          return flowFail(JSON.stringify(recDlErr));
        }
        // content-length 预检：超 20MB 先中文拦，无头由 maxLimit 兜底抛 2300063 走
        // 网络层失败回执
        const dlLenText: string = readHeader(resp.header, 'content-length');
        const dlLength: number = parseInt(dlLenText, 10);
        if (Number.isFinite(dlLength) && dlLength > HTTP_DOWNLOAD_MAX_LIMIT_BYTES) {
          const recBig: Record<string, Object> = {};
          recBig['url'] = url;
          recBig['status'] = status;
          recBig['error'] = '文件过大，上限 ' + (HTTP_DOWNLOAD_MAX_LIMIT_BYTES / (1024 * 1024)) +
            'MB，未保存';
          enrichHttpReceipt(recBig, resp, durationMs);
          return flowFail(JSON.stringify(recBig));
        }
        // 契约外结果形态防御（ARRAY_BUFFER 档应为 ArrayBuffer）：非 ArrayBuffer 响亮失败，
        // 不落 0 字节文件冒充成功（静默错值）；真无内容场景（如 204）由状态码语义承接
        if (!(resp.result instanceof ArrayBuffer)) {
          const recBad: Record<string, Object> = {};
          recBad['url'] = url;
          recBad['status'] = status;
          recBad['error'] = '下载内容异常，响应正文不是二进制，未保存文件';
          enrichHttpReceipt(recBad, resp, durationMs);
          return flowFail(JSON.stringify(recBad));
        }
        const bytes: ArrayBuffer = resp.result as ArrayBuffer;
        try {
          const saved = await saveDownloadToWorkspace(bytes, url, contentType,
            ctx.conversationId, ctx.assistantId);
          if (!saved.ok) {
            const recSv: Record<string, Object> = {};
            recSv['url'] = url;
            recSv['status'] = status;
            recSv['error'] = saved.errorText;
            enrichHttpReceipt(recSv, resp, durationMs);
            return flowFail(JSON.stringify(recSv));
          }
          const recSaved: Record<string, Object> = {};
          recSaved['url'] = url;
          recSaved['status'] = status;
          const savedRec: Record<string, Object> = {};
          savedRec['id'] = saved.fileId;
          savedRec['name'] = saved.name;
          savedRec['kind'] = saved.kind;
          savedRec['size'] = saved.size;
          savedRec['path'] = saved.path;
          recSaved['saved'] = savedRec;
          recSaved['note'] = '已存入文件工作区「' + saved.name + '」，正文不进入对话。可在 设置 → 文件工作区 查看';
          enrichHttpReceipt(recSaved, resp, durationMs);
          // 回执天然短串不走 fitHttpResult（书 §3.1——回执无 body 键）
          return flowFail(JSON.stringify(recSaved));
        } catch (e) {
          const recIo: Record<string, Object> = {};
          recIo['url'] = url;
          recIo['status'] = status;
          recIo['error'] = '文件保存失败：' + (e as Error).message;
          enrichHttpReceipt(recIo, resp, durationMs);
          return flowFail(JSON.stringify(recIo));
        }
      }
      // ── 脚本联网桥路回执支（wantBytes）：正文不进回执、原始字节随 outcome.bytes 外传
      //（桥按 contentType 分派文本/字节形态——文本解码单源在 native 侧 CreateStringUtf8，
      // 本链不做第二套解码）。非 2xx 的 error 文案由本链拼好（status 在本链手上），桥只
      // 透传 error 键。分页参数（maxLength / startIndex）对桥路无意义——脚本拿整包，不消费
      if (args.wantBytes) {
        if (status < 200 || status >= 300) {
          const recBsErr: Record<string, Object> = {};
          recBsErr['url'] = url;
          recBsErr['status'] = status;
          let head: string = '';
          if (resp.result instanceof ArrayBuffer) {
            // 错误正文开头（前 200 字符；字节预切 1200 再解码——UTF-8 每字符 ≤4 字节，
            // 1200 字节恒覆盖 200 字符，避免整包解码 2MB 错误页）
            head = new util.TextDecoder('utf-8').decodeToString(
              new Uint8Array(resp.result).subarray(0, 1200)).substring(0, 200);
          }
          recBsErr['error'] = '请求失败，HTTP 状态码 ' + status + '。响应正文开头如下。\n' + head;
          enrichHttpReceipt(recBsErr, resp, durationMs);
          return flowFail(JSON.stringify(recBsErr));
        }
        // 契约外结果形态防御（同 download 路）：响亮失败不替它猜空包（空响应体 =
        // 长度 0 的 ArrayBuffer，是合法形态）
        if (!(resp.result instanceof ArrayBuffer)) {
          const recBsBad: Record<string, Object> = {};
          recBsBad['url'] = url;
          recBsBad['status'] = status;
          recBsBad['error'] = '响应正文不是二进制，请求结果不可用';
          enrichHttpReceipt(recBsBad, resp, durationMs);
          return flowFail(JSON.stringify(recBsBad));
        }
        const recBytes: Record<string, Object> = {};
        recBytes['url'] = url;
        recBytes['status'] = status;
        recBytes['contentType'] = clipResultText(contentType, HTTP_RESULT_CONTENT_TYPE_MAX);
        const bytesOutcome: HttpFlowOutcome = flowFail(JSON.stringify(recBytes));
        bytesOutcome.bytes = resp.result as ArrayBuffer;
        return bytesOutcome;
      }
      if (!isTextContentType(contentType)) {
        // 二进制：只回元信息（绝不把二进制按文本硬塞）；公共字段走 enrichHttpReceipt，
        // 与文本分支同源——两分支字段集一致
        const lenText: string = readHeader(resp.header, 'content-length');
        const contentLength: number = parseInt(lenText, 10);
        const recBin: Record<string, Object> = {};
        recBin['url'] = url;
        recBin['status'] = status;
        recBin['contentType'] = clipResultText(contentType, HTTP_RESULT_CONTENT_TYPE_MAX);
        recBin['contentLength'] = Number.isFinite(contentLength) ? contentLength : 0;
        enrichHttpReceipt(recBin, resp, durationMs);
        recBin['note'] = '二进制内容，不返回正文';
        return flowFail(JSON.stringify(recBin));
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
      rec['contentType'] = clipResultText(contentType, HTTP_RESULT_CONTENT_TYPE_MAX);
      rec['body'] = piece;
      rec['totalLength'] = total;
      rec['truncated'] = truncated;
      rec['nextStartIndex'] = end;
      if (truncated) {
        rec['note'] = '正文已截断，用 start_index 续读';
      }
      // 公共字段（耗时 / 脱敏响应头 / 连接信息组）走 enrichHttpReceipt——内含四维有界与
      // 8192 预算的收口口径，见其头注释
      enrichHttpReceipt(rec, resp, durationMs);
      const textOutcome: HttpFlowOutcome = flowFail(fitHttpResult(rec, start));
      // 完整正文随 outcome 外传（管道占位符提取的数据面，与回执分页无关）
      textOutcome.fullBody = full;
      return textOutcome;
    });
}

// 流式回执组装（窗口读取路）：idle = 硬中止专用错误（code / idleMs / timeoutMs 三字段）；
// 取消 / 网络失败照同步路面；event-stream 分帧聚合回执（body = 事件 data 空行连接 +
// eventCount + truncated——窗口到量软停止是正常结果）；非 SSE 照普通文本分页形态（窗口闸
// 截断时注明正文可能不完整）。流式链无 HttpResponse——公共字段手工组（durationMs +
// maskResponseHeaders(outcome.header)），connectionExtraInfo 组（跳数 / 协议 / TLS）不回
//（desc 已注明该例外）。取消分支以 cancelled 外传（后台长任务据此落 cancelled 终态）；
// 非 2xx 补 retriable / retry_after_seconds——desc 承诺对窗口路同样成立。fullBody 随事件流 /
// 普通文本两成功分支外传（聚合全文 / stream.text），供管道占位符提取
export function streamReceipt(url: string, stream: HttpStreamOutcome, startedAt: number,
  maxChars: number, startIndex: number): HttpFlowOutcome {
  const out = (json: string, cancelled: boolean = false, fullBody: string = ''): HttpFlowOutcome =>
    ({ json: json, timedOut: false, cancelled: cancelled, fullBody: fullBody, bytes: null });
  if (stream.terminalReason === 'cancelled') {
    // 用户掐断——与同步路取消同形（模型轮已停此串大多不消费，口径一致性优先）
    return out(JSON.stringify({ error: '请求已取消' }), true);
  }
  if (stream.terminalReason === 'idle') {
    const recIdle: Record<string, Object> = {};
    recIdle['error'] = '事件流读取中止，服务端连续 ' + Math.round(HTTP_STREAM_IDLE_MS / 1000) +
      ' 秒未发送新数据';
    recIdle['code'] = HTTP_STREAM_ERROR_CODE;
    recIdle['idleMs'] = stream.idleElapsedMs;
    recIdle['timeoutMs'] = HTTP_STREAM_IDLE_MS;
    return out(JSON.stringify(recIdle));
  }
  // 软停三态（window/events/bytes）是正常结果面——statusOk 在传输层已自 status-line 补
  // 真值；此处防御 status-line 缺失的降级形态（头已收但码不可知），不让已收数据掉进
  // 网络失败分支被吞
  const softStop: boolean = stream.terminalReason === 'window' ||
    stream.terminalReason === 'events' || stream.terminalReason === 'bytes';
  if (!stream.statusOk && !softStop) {
    const recErr: Record<string, Object> = {}; // 网络失败（'error'）——与同步路同形
    recErr['error'] = stream.errorText;
    recErr['retriable'] = httpNetworkRetriable(stream.errorCode);
    return { json: JSON.stringify(recErr), timedOut: stream.errorCode === HTTP_KIT_CODE_TIMEOUT,
      cancelled: false, fullBody: '', bytes: null };
  }
  const status: number = stream.status;
  const contentType: string = stream.headerSeen ?
    readHeader(stream.header, 'content-type') : '';
  const durationMs: number = Date.now() - startedAt;
  if (status < 200 || status >= 300) {
    const recSt: Record<string, Object> = {};
    recSt['url'] = url;
    recSt['status'] = status;
    // status = 0 = 响应头缺状态行真值的降级形态（软停防御路保留——吞掉已收数据是更大的
    // 错），「状态码 0」不可读，给专用句
    recSt['error'] = status === 0 ? '请求失败，响应未提供状态码' : '请求失败，状态码 ' + status;
    recSt['durationMs'] = durationMs;
    recSt['headers'] = maskResponseHeaders(stream.header);
    // 与同步路 enrichHttpReceipt 失败语义同源（非 2xx 补 retriable；Retry-After 自响应头取）
    if (status >= 400) {
      recSt['retriable'] = httpStatusRetriable(status);
      const retryAfter: number = parseRetryAfterSeconds(
        readHeader(stream.header, 'retry-after'), Date.now());
      if (retryAfter > 0) {
        recSt['retry_after_seconds'] = retryAfter;
      }
    }
    return out(JSON.stringify(recSt));
  }
  const rec: Record<string, Object> = {};
  rec['url'] = url;
  rec['status'] = status;
  rec['contentType'] = clipResultText(contentType, HTTP_RESULT_CONTENT_TYPE_MAX);
  rec['durationMs'] = durationMs;
  rec['headers'] = maskResponseHeaders(stream.header);
  if (stream.isEventStream) {
    // 事件流回执：聚合文本按分页参数钳切（max_length 语义照守），fitHttpResult 兜底终态预算
    //（红线：新字段不把正文挤空——eventCount / truncated 均小字段）
    const full: string = aggregateEventsText(stream.events);
    const total: number = full.length;
    let pieceStart: number = Math.max(0, startIndex);
    if (pieceStart > total) {
      pieceStart = total;
    }
    const end: number = Math.min(total, pieceStart + maxChars);
    rec['body'] = full.substring(pieceStart, end);
    rec['eventCount'] = stream.events.length;
    const truncated: boolean = stream.terminalReason !== 'completed' || end < total;
    rec['truncated'] = truncated;
    if (truncated) {
      rec['note'] = stream.terminalReason === 'completed' ?
        '事件文本超过 max_length 已截断' : '事件流读取在窗口处停止，之后的事件未读取';
    }
    return out(fitHttpResult(rec, pieceStart), false, full);
  }
  // 非 SSE（窗口参数对普通响应只是挂死流兜底闸）：二进制照同步路只回元信息（解码是乱码）
  if (!isTextContentType(contentType)) {
    rec['contentLength'] = stream.bytes;
    rec['note'] = '二进制内容，不返回正文';
    return out(JSON.stringify(rec));
  }
  // 普通文本：照分页形态（窗口闸截断时注明正文可能不完整）
  const full: string = stream.text;
  const total: number = full.length;
  let start: number = Math.max(0, startIndex);
  if (start > total) {
    start = total;
  }
  const end: number = Math.min(total, start + maxChars);
  rec['body'] = full.substring(start, end);
  rec['totalLength'] = total;
  rec['truncated'] = end < total || stream.terminalReason !== 'completed';
  rec['nextStartIndex'] = end;
  if (stream.terminalReason !== 'completed') {
    rec['note'] = '流式读取在窗口处停止，正文可能不完整';
  } else if (end < total) {
    rec['note'] = '正文已截断，用 start_index 续读';
  }
  return out(fitHttpResult(rec, start), false, full);
}

// 方法名 → 官方枚举（白名单判定后的翻译层——静态映射不查表，见 HttpPreflight 文件头安全
// 口径；入参已在白名单内，default 分支理论不可达的防御）
export function toRequestMethod(method: string): http.RequestMethod {
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
