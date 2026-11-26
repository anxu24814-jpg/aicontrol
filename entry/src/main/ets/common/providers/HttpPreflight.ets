// HTTP 工具域·预检与声明面域（自 ToolHttp.ets 域级最小拆分）。职责 = 「工具的模型面契约
// 与确认链预检」——HTTP_REQUEST_DESC / HTTP_REQUEST_SCHEMA（请求侧声明单源）+
// buildHttpConfirmPreview（确认卡结构化预览）+ httpRequestNeedsConfirm（写确认预检）+
// HTTP_WRITE_METHODS（写方法集，预检与执行器两岸共引）。方法体自 ToolHttp 原样搬迁零行为
// 变化。
// ★ 管道声明面：desc/schema 扩 requests 数组 + httpRequestNeedsConfirm 增管道分支——管道内
//   **每个写请求都在同一张确认卡上列出**，一次确认覆盖整条管道、执行链内零逐请求弹卡；
//   管道合并卡与 detail/domain 组装细则见 pipelineConfirm 头注释；规格非法返 null
//   （执行器会报参数错，预检不重复拦截，照既有口径）。
// · 坑50 纪律：本件只引叶子与纯函数域（ToolContracts / ConfirmRouting / AppPreferences /
//   AppPreferencesHttp / HttpOutboundGuard / ReqLog / HttpReceipt / HttpPipeline——均不引
//   本件，无环）；禁引 ToolHttp / ToolTypes / HttpTransport / HttpFlow。HTTP_WRITE_METHODS
//   落本件 = 声明面归属（执行器自本件 import 单向边，反序即环）。
// · 预检契约（全包 try/catch 恒不抛——预检抛错 = 轮内链裸 await 无兜底整轮静默死，实现
//   自防责任见 ToolContracts.ToolEntry.preflight 注释，后来者必读；★ H3-5 起 fail-closed：
//   写方法判定之后的异常返保守人工卡不返 null——写确认预检返 null = 直发，预检挂执行成 =
//   写请求无卡直发；坏形态阶段仍返 null 由执行器参数错误回执拦，见 writeConfirmFallbackPrompt）。
import { ConfirmPrompt, CONFIRM_LEVEL_WRITE, CONFIRM_ROUTE_HUMAN } from './ToolContracts';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { routeConfirmPrompt } from './ConfirmRouting';
import { httpApproveMode } from '../AppPreferences';
import { resolveConfirmMode } from '../chat/PermissionMode';
import { httpHostOfUrl } from './HttpOutboundGuard';
import { isSensitiveName } from '../ReqLog';
import { clipResultText } from './HttpReceipt';
import { PipelineSpecOutcome, PipelineStepSpec, validatePipelineSpec } from './HttpPipeline';

// 写方法集（确认卡弹卡范围——预检 httpRequestNeedsConfirm 的判定源；自 ToolHttp 原样迁入，
// 执行器自本件引）
export const HTTP_WRITE_METHODS: string[] = ['POST', 'PUT', 'DELETE', 'PATCH'];

// 写确认 fail-closed 保守卡（H3-5 拍板）：写确认预检在「已判定写操作」之后的异常不得返
// null 直通（写方法无卡直发 = 确认红线击穿）——改返本卡：档位恒写操作、route 恒人工（不经
// routeConfirmPrompt 裁决，「一律放行」豁免也吃不掉（域名确认档已于 2026-11-11 整卡退役，
// 当年并列的第二道豁免不复存在），与
// pipelineConfirm「目标未知 ≥ ask」保守缺省同语义）；卡面不带 detail/domain（此刻组装产物
// 不可信）、文案不提 URL。模板口（HttpTemplate.templatePreflightFor）共用本构造，禁第二份文案
export function writeConfirmFallbackPrompt(): ConfirmPrompt {
  const prompt: ConfirmPrompt = {
    text: '发送前的确认检查出现异常，本次发送需要你确认。',
    level: CONFIRM_LEVEL_WRITE,
    route: CONFIRM_ROUTE_HUMAN
  };
  return prompt;
}

// 确认串 URL 截断（超长 URL 截尾加省略号，防确认卡被撑爆）
const HTTP_CONFIRM_URL_MAX: number = 200;
// 确认预览闸：预览串各维有界——头行数 / 单值 / 正文开头 / 整串四维封顶，防大 body 或多头
// 入参把确认卡撑爆（预览与回执预算无关，走自有闸）
const HTTP_PREVIEW_HEADER_LINES_MAX: number = 8;
const HTTP_PREVIEW_VALUE_MAX: number = 80;
const HTTP_PREVIEW_BODY_MAX: number = 200;
const HTTP_PREVIEW_MAX_CHARS: number = 1000;
// 管道合并卡明细闸：读步骤行按预算截尾的总字符封顶——8 步 × 长 URL 叠加可把卡撑爆，到线
// 即止并注明省略；写步骤行必保不截（★ 编排常见形态恰是读前写后，尾部写行正是先被吞的；
// 现写行恒列出，仅读行可能省略）
const HTTP_PIPELINE_DETAIL_MAX_CHARS: number = 1600;

// 确认预览串（纯函数，导出供断言直跑）：把「要发什么」拼成卡面可展开的多行明细——首行
// 方法与网址、随后脱敏请求头、末行正文开头。脱敏两处：敏感头值 [已隐藏]（判据 =
// ReqLog.isSensitiveName，与响应头脱敏同源）+ 超长值截尾；凭据引用在模型入参里本就是
// {{名称}} 记号形态，预览原样保留（真值零出现）。四维有界（行数 / 单值 / 正文开头 / 整串）
// 防大入参撑爆确认卡。headers 为空省头段、body 为空省尾行，首行恒在
export function buildHttpConfirmPreview(method: string, url: string,
  headers: Record<string, string>, body: string): string {
  const shownUrl: string = url.length > HTTP_CONFIRM_URL_MAX ?
    url.substring(0, HTTP_CONFIRM_URL_MAX) + '…' : url;
  let out: string = method + ' ' + shownUrl;
  let used: number = out.length;
  const keys: string[] = Object.keys(headers);
  for (let i = 0; i < keys.length && i < HTTP_PREVIEW_HEADER_LINES_MAX; i++) {
    const value: string = isSensitiveName(keys[i]) ? '[已隐藏]' :
      clipResultText(headers[keys[i]], HTTP_PREVIEW_VALUE_MAX);
    const line: string = '\n' + keys[i] + '：' + value;
    if (used + line.length > HTTP_PREVIEW_MAX_CHARS) {
      break;
    }
    out += line;
    used += line.length;
  }
  if (keys.length > HTTP_PREVIEW_HEADER_LINES_MAX) {
    const more: string = '\n…其余 ' + (keys.length - HTTP_PREVIEW_HEADER_LINES_MAX) +
      ' 个请求头省略';
    if (used + more.length <= HTTP_PREVIEW_MAX_CHARS) {
      out += more;
      used += more.length;
    }
  }
  if (body !== '') {
    const flat: string = body.replace(/[\r\n]+/g, ' ');
    const line: string = '\n正文开头：' + clipResultText(flat, HTTP_PREVIEW_BODY_MAX);
    if (used + line.length <= HTTP_PREVIEW_MAX_CHARS) {
      out += line;
    }
  }
  return out;
}

export const HTTP_REQUEST_DESC: string =
  'Send a raw HTTP request to any http(s) URL and return status, content type and body.\n' +
  'Use it for REST API calls, webhooks and JSON endpoints that need a specific method,\n' +
  'custom headers or a request body. For reading normal web page content prefer\n' +
  'scrape_web (static pages) or browse_open (JS-rendered pages): they extract readable\n' +
  'text, this tool does not. POST/PUT/DELETE/PATCH are write operations: by default\n' +
  'each call asks the user for confirmation, so batch what you need and do not retry\n' +
  'on denial. If the user turned confirmations off, write calls are sent directly.\n' +
  'Responses are capped (max_length) and can be paged with start_index. Pass\n' +
  'download: true to save a response as a file in the user\'s workspace (the file\n' +
  'never enters the conversation; pagination is ignored when saving); without it,\n' +
  'binary responses return metadata only. To upload, pass file with the name of an\n' +
  'attachment the user sent in this conversation, or a file from the workspace; or\n' +
  'pass multipart with named files to send a multipart form. Each response also\n' +
  'carries headers, durationMs and\n' +
  'redirectCount. Failed responses carry retriable, and retry_after_seconds when the\n' +
  'server asks you to wait. A repeated GET of an unchanged resource returns\n' +
  'notModified instead of the body again. Calls to the same host are paced; if a call\n' +
  'is deferred, wait the indicated seconds before retrying. For endpoints that need a\n' +
  'secret, reference a stored credential by name as {{name}} inside a header value or a\n' +
  'URL query value; the app fills in the real value before sending, so never paste the\n' +
  'secret itself. The app also scans outgoing requests and rejects any that contain a\n' +
  'stored secret verbatim. The user may restrict which domains this tool may contact;\n' +
  'a blocked call returns an error asking the user to allow that domain. Call env_list\n' +
  'to see available names. Keep request bodies small\n' +
  '(a few KB). Timeouts default to 30 seconds; pass timeout_ms to wait longer when an\n' +
  'endpoint is slow. For streaming endpoints that respond with text/event-stream, pass\n' +
  'stream_ms (and optionally max_events) to read a bounded window instead of waiting\n' +
  'for the stream to close: the tool returns the events received so far and sets\n' +
  'truncated when the window stopped the read. If the stream stalls for more than 8\n' +
  'seconds after data started, the read aborts with a stream_idle_timeout error.\n' +
  'Windowed streaming receipts omit redirectCount. For slow endpoints pass async:\n' +
  'true: the call is accepted immediately with a task_id and keeps running in the\n' +
  'background (bounded by timeout_ms, default 5 minutes). Read the result later by\n' +
  'passing task_id, optionally with wait_ms (up to 10000) to wait briefly; a wait\n' +
  'timeout returns the current status and is not an error. Completed results are kept\n' +
  'for 10 minutes; tasks still running when the app restarted return as lost.\n' +
  'Cookies set by responses are remembered per host within this conversation and\n' +
  'resent automatically to the same host; user-provided Cookie headers always win.\n' +
  'For multi-step API workflows pass a requests array instead of url: the requests\n' +
  'run in order, and each step may reference fields from an earlier JSON response by\n' +
  'writing {{step.path.to.field}} placeholders (step is the 0-based index, e.g.\n' +
  '{{0.body.data.token}}) inside its url, header values or body; they are replaced\n' +
  'before sending. Steps support method, url, headers, body and timeout_ms only.\n' +
  'At most 8 requests and 120 seconds in total; the pipeline stops at the first\n' +
  'failing step and reports which one failed and why. Write operations in a pipeline\n' +
  'are confirmed together on one combined card covering the whole pipeline.';

export const HTTP_REQUEST_SCHEMA: string =
  '{"type":"object","properties":{' +
  '"url":{"type":"string","description":"完整的 http 或 https URL，不含其他协议。"},' +
  '"method":{"type":"string","enum":["GET","POST","PUT","DELETE","PATCH","HEAD","OPTIONS"],' +
  '"description":"HTTP 方法。省略时为 GET。POST PUT DELETE PATCH 属写操作，默认会请求用户确认。用户可在设置里把默认权限改为高效档，改为后不再询问。"},' +
  '"headers":{"type":"object","additionalProperties":{"type":"string"},' +
  '"description":"自定义请求头，键值对。POST JSON 请求应带 Content-Type application/json。不要把密钥放进 URL 查询串，密钥应放请求头。需要密钥时可用 {{凭据名}} 引用已存的凭据，应用会在发送前替换成真实值，可用名称先用 env_list 查询。直接粘贴已存凭据的明文值会被应用拦下。"},' +
  '"body":{"type":"string","description":"请求体文本，仅 POST PUT PATCH 需要。GET HEAD 会忽略并回执提示。与 file 和 multipart 互斥。"},' +
  '"download":{"type":"boolean","description":"把响应内容保存为文件。保存后正文不进入对话，工具卡会显示文件，用户在 设置 → 文件工作区 可以查看和管理。适合图片、文档等用户要拿到的内容。保存时忽略分页参数。"},' +
  '"file":{"type":"string","description":"作为请求体上传的附件文件名。取当前会话中用户发送过的附件名，也可以是文件工作区里的文件名。仅单文件直传场景用，与 body 和 multipart 互斥。"},' +
  '"multipart":{"type":"object","properties":{"fields":{"type":"object","additionalProperties":{"type":"string"},"description":"表单文本字段，键值对，可省略。"},"files":{"type":"array","items":{"type":"object","properties":{"attachment":{"type":"string","description":"附件文件名，取当前会话中用户发送过的附件名，也可以是文件工作区里的文件名。"},"name":{"type":"string","description":"表单字段名，省略时为 file。"}},"required":["attachment"]}}},"required":["files"],"description":"以 multipart 表单发送。表单即请求体，与 body 和 file 互斥。"},' +
  '"max_length":{"type":"integer","description":"返回正文的最大字符数，默认 5000，上限 8000。"},' +
  '"start_index":{"type":"integer","description":"从正文该字符下标开始返回，用于上一次被截断后的分页续读。"},' +
  '"timeout_ms":{"type":"integer","description":"等待响应的最长毫秒数。不填用默认 30000。接口较慢时可加大，上限由用户在设置里配置。async 任务还以它为总运行时长上限，不填默认 300000。"},' +
  '"stream_ms":{"type":"integer","description":"事件流读取窗口毫秒数。响应为 text/event-stream 时读满窗口即返回已收事件并标 truncated。不填默认 10000，上限 60000。"},' +
  '"max_events":{"type":"integer","description":"事件流最多读取的事件条数，读满即停。不填默认 200，上限 1000。"},' +
  '"async":{"type":"boolean","description":"异步发起。true 时立即返回 task_id 并在后台继续执行，适合耗时较长的接口。与 task_id 互斥。"},' +
  '"task_id":{"type":"string","description":"查询此前用 async 发起的任务。运行中返回状态，已完成返回当初的完整结果，应用重启前未完成的返回 lost。"},' +
  '"wait_ms":{"type":"integer","description":"配合 task_id 的有界等待毫秒数，上限 10000。等待期间任务完成立即返回结果，到时返回当前状态，到时不是错误。"},' +
  '"requests":{"type":"array","maxItems":8,"items":{"type":"object","properties":{' +
  '"method":{"type":"string","enum":["GET","POST","PUT","DELETE","PATCH","HEAD","OPTIONS"],"description":"HTTP 方法，省略时为 GET。"},' +
  '"url":{"type":"string","description":"完整的 http 或 https URL，可含 {{步骤.路径}} 占位符。"},' +
  '"headers":{"type":"object","additionalProperties":{"type":"string"},"description":"自定义请求头，键值对，值可含占位符。"},' +
  '"body":{"type":"string","description":"请求体文本，可含占位符。"},' +
  '"timeout_ms":{"type":"integer","description":"本请求等待响应的最长毫秒数。"}},' +
  '"required":["url"]},"description":"请求管道：按顺序执行多个请求，后续请求可在网址、请求头值或正文中用 {{步骤.路径}} 占位符引用之前某步响应 JSON 里的字段，例如 {{0.body.data.token}} 取第 1 步响应的 body.data.token。最多 8 个请求，总时长上限 120 秒，任一步失败即停止并告知第几个失败。步骤只支持 method、url、headers、body、timeout_ms。与 url 参数互斥。包含写操作时合并为一张确认卡一次确认。"}}' +
  '}';

// 确认链预检：返回待确认二元组——null = 直通，非 null = 需弹确认卡，text 即卡面说明、
// level 恒 CONFIRM_LEVEL_WRITE（本件无不可逆档：写方法均可在对方服务器侧留有痕迹但无
// 「删除类」语义，档位恒写操作）。判定 = method（缺省 GET）∈ 写方法集；解析失败也返 null
//（执行器会出参数错误回执，无直发面）。
// ★ fail-closed（H3-5 拍板）：异常处理分两段——写方法判定之前的坏形态阶段（JSON.parse /
//   method 提取）异常返 null（执行器参数错误回执拦下）；写方法判定之后的任何异常返
//   writeConfirmFallbackPrompt 保守人工卡（预检与执行是两个时点，预检挂而执行成 = 写请求
//   无卡直发；与重发链「预检异常按执行失败收口」的 fail-closed 口径对齐）。
// ★ 写确认档早退：旧布尔键 prefHttpWriteAutoApprove 为 true 时首行回 null——不弹卡，写请求
//   与读方法同路直发（三档归一后该键已无设置页写点，只作旧备份恢复后的只读兜底；正常路径由
//   routeConfirmPrompt 的会话权限模式统管）；现读 = 切换即时生效，下一个请求按新值，已弹出的
//   确认卡不受影响仍需作答（照 browseActNeedsConfirm 预检同形制）。
// ★ 串形态：只写方法与网址，不以「助手请求发送网络请求」起头——卡面标题已渲染同一句，
//   跟起头会造成逐字重复。
// ★ 形态：返回类型 ConfirmPrompt | null（非「串（'' = 直通）」）——档位字段供卡面档位徽章
//   渲染，见 ToolContracts.ConfirmPrompt 头注释。
// ★ 返回对象含 detail（结构化预览串，卡面可展开）与 domain（目标 host，只作确认卡说明与
//   等待态回放载荷——2026-11-09 三档归一后卡面已无「始终允许该域名」快捷键；2026-11-11
//   域名确认档整档退役后，写确认只由会话权限模式裁决，本域不再有按域名的确认例外）。
// ★ 管道合并卡组装：管道内每个写请求都在同一张确认卡上列出——text 汇总请求数与写操作数；
//   detail 逐请求一行「方法 网址」写操作标「·写」（写请求恒列出，读请求按明细预算列出——
//   它们同样会被执行，超预算以省略行注明）；domain = 全部请求同域时出该域，跨域管道留空
//   不出快捷键（多域卡不授单域）。目标未知的写步骤（占位符域名）非高效档恒人工卡——见
//   unknownWriteTarget 注释。全读管道返回 null 直通执行
function pipelineConfirm(steps: PipelineStepSpec[], mode: string): ConfirmPrompt | null {
  const allHosts: string[] = [];
  // 写步骤的 host 集（只用于「目标未知」判定；域名确认档退役后不再参与档位裁决）
  const writeHosts: string[] = [];
  let writeCount: number = 0;
  for (const step of steps) {
    const host: string = httpHostOfUrl(step.url);
    allHosts.push(host);
    if (HTTP_WRITE_METHODS.includes(step.method)) {
      writeCount++;
      writeHosts.push(host);
    }
  }
  if (writeCount === 0) {
    return null;
  }
  // detail 明细（★ 契约「每个写请求都在同一张确认卡上列出」：写步骤行恒列出，读步骤行按
  // 预算截尾〔到线止逐行跳过、行序仍 = 管道步序〕，省略行注明跳过的读请求数——编排常见
  // 形态恰是读前写后，写行在尾部先被截断吞掉 = 写请求在用户未见明细行的情况下被确认执行。
  // 有界性：单行 URL 截 HTTP_CONFIRM_URL_MAX、写行 ≤8、读行封 HTTP_PIPELINE_DETAIL_MAX_CHARS
  // ——全写长名极端形态上限 ≈ 8 × 单行 210 字符，卡面仍可控）
  const lines: string[] = [];
  let used: number = 0;
  let omittedReads: number = 0;
  for (let i: number = 0; i < steps.length; i++) {
    const isWrite: boolean = HTTP_WRITE_METHODS.includes(steps[i].method);
    const shownUrl: string = steps[i].url.length > HTTP_CONFIRM_URL_MAX ?
      steps[i].url.substring(0, HTTP_CONFIRM_URL_MAX) + '…' : steps[i].url;
    const line: string = steps[i].method + ' ' + shownUrl + (isWrite ? ' ·写' : '');
    if (!isWrite && used + line.length + 1 > HTTP_PIPELINE_DETAIL_MAX_CHARS) {
      omittedReads++;
      continue;
    }
    lines.push(line);
    used += line.length + 1;
  }
  if (omittedReads > 0) {
    lines.push('…其余 ' + omittedReads + ' 个读请求省略');
  }
  // ★ 目标未知写步骤恒人工卡（非高效档）：占位符替换发生在执行期，卡面只能看到模板串——
  // host 解析为空串（整串占位符无 scheme）或含「{{」（authority 段占位，合法域名不含花括号）
  // ＝真实目的地确认时不可知；此时若按全局档交给审批模型或「一律放行」，等于让模型为一个
  // 替换后可能是任意域名的请求背书。按「目标未知 ≥ ask」保守缺省强制人工卡（读步骤不受
  // 影响——读操作直通是既有语义）。★ 高效档例外：2026-11-09 决明拍板「完全权限时不设限」，
  // 该档下未知目标也直接执行（本判据排在高效档之后）
  let unknownWriteTarget: boolean = false;
  for (const host of writeHosts) {
    if (host === '' || host.includes('{{')) {
      unknownWriteTarget = true;
      break;
    }
  }
  let domain: string = allHosts[0];
  for (const host of allHosts) {
    if (host !== domain) {
      domain = '';
      break;
    }
  }
  const prompt: ConfirmPrompt = {
    text: '将按顺序发送 ' + steps.length + ' 个请求，包含 ' + writeCount + ' 个写操作',
    level: CONFIRM_LEVEL_WRITE,
    detail: lines.join('\n'),
    domain: domain
  };
  if (unknownWriteTarget && resolveConfirmMode(mode) !== null) {
    return { text: prompt.text, level: prompt.level, route: CONFIRM_ROUTE_HUMAN,
      detail: prompt.detail, domain: prompt.domain };
  }
  return routeConfirmPrompt(prompt, mode);
}

export async function httpRequestNeedsConfirm(argsJson: string,
  _ctx: ToolExecutionContext): Promise<ConfirmPrompt | null> {
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    // ★ 管道分支：requests 在场 → 规格归一后合并单卡；规格非法 = 执行器会报参数错，预检
    // 不重复拦截返 null（照既有「解析失败也返 null」口径）；validatePipelineSpec 自身抛错
    // 同返 null——规格坏形态执行器侧同函数拦下，无直发面
    const requestsRaw: Object = parsed['requests'];
    if (typeof requestsRaw !== 'undefined') {
      let spec: PipelineSpecOutcome;
      try {
        spec = validatePipelineSpec(requestsRaw);
      } catch (e) {
        return null;
      }
      if (!spec.ok) {
        return null;
      }
      // ★ fail-closed：规格已合法、写请求构成已知——合并卡组装（host 解析 / 三档归一 /
      // 目标未知判定）异常不得直发整条管道，返保守人工卡
      try {
        const mode: string = httpApproveMode();
        return pipelineConfirm(spec.steps, mode);
      } catch (e) {
        return writeConfirmFallbackPrompt();
      }
    }
    const methodRaw: Object = parsed['method'];
    const urlRaw: Object = parsed['url'];
    const method: string = typeof methodRaw === 'string' && methodRaw.trim() !== '' ?
      methodRaw.trim().toUpperCase() : 'GET';
    if (!HTTP_WRITE_METHODS.includes(method)) {
      return null;
    }
    if (typeof urlRaw !== 'string' || urlRaw.trim() === '') {
      return null; // URL 缺失 = 执行器参数错误回执拦，无直发面
    }
    // ★ fail-closed 区：写方法已判定、URL 已在场——此后 host 解析 / 预览组装 / 档位读取 /
    // 三档归一任何异常都不再返 null（那会把写请求无卡直发），改返保守人工卡
    try {
      const url: string = urlRaw.trim();
      // 结构化预览输入：头只收字符串值（schema 违约形态执行器另有错误回执，预检不重复
      // 拦截）、body 只收字符串——非串形态在预览里按缺省省略，卡面照常出
      const previewHeaders: Record<string, string> = {};
      const headersRaw: Object = parsed['headers'];
      if (typeof headersRaw === 'object' && headersRaw !== null) {
        const rec = headersRaw as Record<string, Object>;
        for (const key of Object.keys(rec)) {
          const value: Object = rec[key];
          if (typeof value === 'string') {
            previewHeaders[key] = value;
          }
        }
      }
      const bodyRaw: Object = parsed['body'];
      const previewBody: string = typeof bodyRaw === 'string' ? bodyRaw : '';
      const host: string = httpHostOfUrl(url);
      // 档位三态（豁免与去向归一在 routeConfirmPrompt 单点）：本域恒写操作档（无不可逆档），
      // auto 豁免面与旧「自动通过」口径一致；ask 直指人工卡、model 交审批闸。域名确认档
      // 2026-11-11 退役后不再有按域名的确认例外，domain 只作卡面说明与回放载荷
      const mode: string = httpApproveMode();
      return routeConfirmPrompt({ text: '将发送 ' + method + ' 请求到 ' +
        (url.length > HTTP_CONFIRM_URL_MAX ?
          url.substring(0, HTTP_CONFIRM_URL_MAX) + '…' : url),
        level: CONFIRM_LEVEL_WRITE,
        detail: buildHttpConfirmPreview(method, url, previewHeaders, previewBody),
        domain: host }, mode);
    } catch (e) {
      return writeConfirmFallbackPrompt();
    }
  } catch (e) {
    // 外层 catch 只覆盖写方法判定之前的坏形态阶段（JSON.parse / method 提取）——该阶段
    // 执行器必然以参数错误回执拦下，无直发面；写方法路径异常已在内层 fail-closed（H3-5）
    return null;
  }
}
