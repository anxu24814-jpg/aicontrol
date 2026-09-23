// Key 连接测试域件（2026-08-31 领导指令新增：密钥池卡「测试连接」键测全池 / 单支 key
// 「更多」菜单测本支）：探针按协议分路——openai/gemini 复用 ModelListApi.fetchModelIds
// 对「列模型」端点发只读请求（openai GET {base}/models Bearer / gemini GET
// {base}/v1beta/models x-goog-api-key），零 token 消耗；anthropic 走
// ModelListApi.probeAnthropicMessages（POST {base}/v1/messages，max_tokens=1）——第三方
// anthro 兼容层（DeepSeek/Kimi 的 /anthropic 端点）不实现 GET /v1/models，列模型探针必
// 404（2026-09-05 实测 bug：对话通但测试报错），改与对话链路同端点测「能不能对话」，
// 探针模型 = 该服务商首个启用模型（无模型提示先添加）。
// ★ 协议注意：baseUrl/protocol 用详情页**当前表单值**（@Link 链直达——未保存也能测，
// 与「获取模型」同语义；用户改协议后立即按新协议验证）。
// ★ 明文面：逐支 loadPoolKey 读取（测试必要读取面，与掩码展示同源）；明文不进日志/toast，
// 失败 detail 为 HTTP/网络层中文提示（ModelListApi 三错误路径，调用方直接呈现）。
// ★ 2026-09-21 能力三项测试笔（决明「做 RikkaHub 那种测试连接，我们现在只有 toast」）：
// 新增**能力面板三探针**——对单支 Key 连发三个真请求（非流式 / 流式 / 工具调用），逐项
// 归态 + 模型回复原文，由 ConnectTestSheet 半模态呈现（入口 = 行菜单「测试连接」）。分工
// 不变：卡头 wifi 键仍走上方既有探针做全池批测（toast、零消耗）；单支行菜单改走本组三项
//（真消耗几个 token，如实记账 purpose='test'）。
// ★ 三探针纪律：**各自独立归态 + 自吞异常 + 一律 resolve**——一项失败不得扩散成三项全失败
//（一个 reject 会被 Promise.all 带塌另两项），故探针内部把一切异常收成结果行。判据纯函数在
// ConnectTestJudge（零 import 叶子件，node 直跑断言同一实现）；四态字与文案归本层与面板层。
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fetchModelIds, probeAnthropicMessages } from '../../common/providers/ModelListApi';
import {
  AiChatMessage, AiConnection, AiStreamHandlers, AiToolDef, AiUsageDelta, ChatStream, HeaderPair,
  connectionOffEnabled, ENDPOINT_RESPONSES, parseHeaderPairs, PROTOCOL_ANTHROPIC,
  PROTOCOL_GEMINI, SamplingParams
} from '../../common/providers/AiTypes';
import { createChatStream } from '../../common/providers/ChatStreamFactory';
import { mergeBodyOverrides } from '../../common/providers/ChatStreamBase';
import { reqLogBegin, reqLogEnd, reqLogSetResponseHeaders } from '../../common/ReqLog';
import {
  composeAnthropicBody, composeGeminiBody, composeOpenAiBody, composeOpenAiResponsesBody
} from '../../common/providers/RequestCompose';
import { extractApiError, SseDelta } from '../../common/providers/SseParser';
import {
  extractTitleText, extractTitleUsage, NonStreamEndpoint, resolveNonStreamEndpoint,
  TitleUsageFrame, toNonStream
} from '../../common/providers/TitleApi';
import {
  judgeStreamProbe, judgeTextProbe, judgeToolProbe, mergeToolCallName, PROBE_FAIL, PROBE_OK
} from '../../common/providers/ConnectTestJudge';
import { loadPoolKey } from '../../common/store/KeyStore';
import { ModelRow, ProviderRow, queryModels, queryProviders } from '../../common/store/ProviderDb';
import { logTaskUsage } from '../../common/store/UsageStatsDb';
import { KeyDisplayRow } from './ProviderKeyRowItem';

// 单支测试结果（ok = 连接与鉴权正常；detail = 「正常(可用模型 N 个)」（openai/gemini）
// 或「正常(对话链路连通)」（anthropic）或失败中文原因）
export interface KeyTestResult {
  label: string;
  ok: boolean;
  detail: string;
}

// 单支测试：明文缺失直接判不可测（Asset 无明文，请求必 401——与发送链「行在明文无」
// 逐支跳过同语义）；openai/gemini 探针成功回报模型数；anthropic 走 messages 探针
//（文件头注释），模型取该服务商首个启用行（无启用模型 = 不可测，提示先添加——P0-1
// 不静默）
export async function testKeyConnection(providerId: string, row: KeyDisplayRow,
  baseUrl: string, protocol: string): Promise<KeyTestResult> {
  try {
    const plain: string = await loadPoolKey(providerId, row.id);
    if (plain === '') {
      return { label: row.label, ok: false, detail: '明文缺失，无法测试' };
    }
    if (protocol === PROTOCOL_ANTHROPIC) {
      const models: ModelRow[] = await queryModels(providerId, '');
      const first: ModelRow | undefined = models.find((m: ModelRow): boolean => m.enabled);
      if (first === undefined) {
        return { label: row.label, ok: false, detail: '请先在模型页签添加模型再测试' };
      }
      const probed = await probeAnthropicMessages(baseUrl, plain, first.modelId);
      // 用途记账（2026-09-10 费用估计）：探针成功即已消耗 token——purpose='test'，
      // conversationId=''（无会话归属，独立行不随任何删除走）；openai/gemini 走列模型
      // GET 零 token 消耗不记账
      logTaskUsage('test', '', providerId, first.modelId,
        probed.promptTokens, probed.completionTokens, probed.cachedTokens);
      return { label: row.label, ok: true, detail: '正常(对话链路连通)' };
    }
    const ids: string[] = await fetchModelIds(baseUrl, plain, protocol);
    return { label: row.label, ok: true, detail: '正常(可用模型 ' + ids.length + ' 个)' };
  } catch (e) {
    return { label: row.label, ok: false, detail: (e as Error).message };
  }
}

// 全池测试（逐支并发探针——池有界 + 低频用户操作）
export async function testPoolKeys(providerId: string, rows: KeyDisplayRow[],
  baseUrl: string, protocol: string): Promise<KeyTestResult[]> {
  const jobs: Promise<KeyTestResult>[] =
    rows.map((row: KeyDisplayRow): Promise<KeyTestResult> =>
      testKeyConnection(providerId, row, baseUrl, protocol));
  return Promise.all(jobs);
}

// 批量聚合文案（单条 toast）：全正常一条报齐；有失败列出失败支 label（定位用，失败原因
// 点该支「更多 → 测试连接」单测查看）
export function summarizeTestResults(results: KeyTestResult[]): string {
  const okCount: number = results.filter((r: KeyTestResult): boolean => r.ok).length;
  const failed: KeyTestResult[] = results.filter((r: KeyTestResult): boolean => !r.ok);
  if (failed.length === 0) {
    return '测试完成：' + okCount + ' 支 Key 全部连接正常';
  }
  let text: string = (okCount > 0 ? okCount + ' 支正常，' : '') + failed.length + ' 支失败：';
  for (let i = 0; i < failed.length; i++) {
    if (i > 0) {
      text += '、';
    }
    text += failed[i].label;
  }
  return text;
}

// ═══ 能力三项测试（2026-09-21 笔）：三探针 + 编排 ═══

// 探针请求参数（D7）：温度 0 + 上限 32 界消耗；提示词英文照竞品同款（题面不面向用户，不受
// 项目 UI 文案规约约束）；超时照 ModelListApi 同值（探针是短请求，不照聊天流式档——后者
// 是 10 分钟 idle 档，见 ChatStreamBase.READ_TIMEOUT_MS）
const PROBE_SAMPLING: SamplingParams = { temperature: 0, maxOutput: 32 };
const PROBE_SYSTEM_PROMPT: string = 'You are a helpful assistant';
const PROBE_USER_PROMPT: string = 'hello';
const PROBE_CONNECT_TIMEOUT_MS: number = 10000;
const PROBE_READ_TIMEOUT_MS: number = 15000;
// dummy 工具（D6）：只进请求体声明、**永不执行**——不注册工具域、无 execute；四协议方言翻译
// 由 RequestCompose 的 tools 形参承担
const DUMMY_TOOL_NAME: string = 'get_current_time';
const DUMMY_TOOL_PROMPT: string = 'Use the get_current_time tool.';
const DUMMY_TOOL: AiToolDef = {
  name: DUMMY_TOOL_NAME,
  description: '获取当前时间',
  parametersJson: '{"type":"object","properties":{}}'
};
// 三行身份与标签（面板固定序：非流式 / 流式 / 工具调用）
export const PROBE_KEY_TEXT: string = 'text';
export const PROBE_KEY_STREAM: string = 'stream';
export const PROBE_KEY_TOOL: string = 'tool';
const LABEL_TEXT: string = '非流式';
const LABEL_STREAM: string = '流式';
const LABEL_TOOL: string = '工具调用';

// 面板结果行（state 取 ConnectTestJudge 四态字；detail = 成功正文原文 / 失败中文原因）
export interface ConnectTestRow {
  key: string;
  label: string;
  state: string;
  detail: string;
}

// 三行初值（传 PROBE_IDLE 未测试 / PROBE_RUNNING 测试中——重跑整组重置即「旧结果作废」）
export function connectTestRows(state: string): ConnectTestRow[] {
  return [
    { key: PROBE_KEY_TEXT, label: LABEL_TEXT, state: state, detail: '' },
    { key: PROBE_KEY_STREAM, label: LABEL_STREAM, state: state, detail: '' },
    { key: PROBE_KEY_TOOL, label: LABEL_TOOL, state: state, detail: '' }
  ];
}

// 结果行构造（三探针共用）
function probeRow(key: string, label: string, state: string, detail: string): ConnectTestRow {
  return { key: key, label: label, state: state, detail: detail };
}

// 单行归位（宿主回调按 key 定位替换——整组替换驱动面板重建）
export function mergeConnectTestRow(rows: ConnectTestRow[],
  row: ConnectTestRow): ConnectTestRow[] {
  return rows.map((item: ConnectTestRow): ConnectTestRow => item.key === row.key ? row : item);
}

// 三探针共享入参（编排一次备齐，探针层不再查库）；conn = 手拼连接，headers/bodyOverrides 取自
// 库（D4——两组 kv 行在高级页签、与测试键跨页签）；reasoning* 三字段缺省 = 解析链外构造的
// 防御态，connectionOffEnabled 回落域名判定兜底不炸
interface ProbeContext {
  providerId: string;
  model: string;
  apiKey: string;
  conn: AiConnection;
}

// 流式观测（判据只吃标量——ConnectTestJudge；本结构是探针内部中转）
interface StreamObserved {
  httpCode: number; // 200 = 流正常收尾；其余 = onError 状态码（-1 = 传输层无状态码，
                    // -2 = 流中错误帧哨兵 STREAM_ERROR_STATUS——本页只判 === 200，两值同归失败）
  hasError: boolean;
  errorText: string;
  sawContent: boolean;
  text: string;
  toolCalls: number;
  toolName: string;
}

// 网络层错误描述（ChatStreamBase / ModelListApi / TitleApi 同款口径的独立成份——项目范式：
// 不为一行复用引互引）
function describeNetError(e: Object): string {
  const biz = e as BusinessError;
  if (typeof biz.code === 'number') {
    return '无法连接服务器(code ' + biz.code + ')' +
      (typeof biz.message === 'string' && biz.message !== '' ? '，' + biz.message : '');
  }
  return (e as Error).message !== undefined ? (e as Error).message : '未知错误';
}

// HTTP 非 200 文案（error.message 优先 / 响应原文截尾 / 无内容兜底——ModelListApi 同款）
function httpFailDetail(code: number, body: string): string {
  const detail: string = extractApiError(body);
  const suffix: string = detail !== '' ? '：' + detail :
    (body !== '' ? '：' + body.slice(0, 200) : '，响应无内容');
  return '测试连接失败(HTTP ' + code + ')' + suffix;
}

// T1 请求体：四协议 composer 产物转非流式（TitleApi.buildTitleBody 同款分支形态，该函数未导出
// 故本件独立成份；★ 参位各不同勿凭记忆——gemini 无 model、responses 无 offEnabled）
function composeTextProbeBody(ctx: ProbeContext): string {
  const messages: AiChatMessage[] = [
    { role: 'system', content: PROBE_SYSTEM_PROMPT },
    { role: 'user', content: PROBE_USER_PROMPT }
  ];
  const off: boolean = connectionOffEnabled(ctx.conn);
  if (ctx.conn.protocol === PROTOCOL_ANTHROPIC) {
    return toNonStream(composeAnthropicBody(ctx.model, messages, '', off, PROBE_SAMPLING), true);
  }
  if (ctx.conn.protocol === PROTOCOL_GEMINI) {
    return toNonStream(composeGeminiBody(messages, '', PROBE_SAMPLING), false);
  }
  if (ctx.conn.endpoint === ENDPOINT_RESPONSES) {
    return toNonStream(composeOpenAiResponsesBody(ctx.model, messages, '', PROBE_SAMPLING), true);
  }
  return toNonStream(composeOpenAiBody(ctx.model, messages, '', off, PROBE_SAMPLING), true);
}

// T1 非流式探针：自组 POST（不走流式链）——端点与认证头走 resolveNonStreamEndpoint 四协议
// 方言；扩展自己合：自定义头逐条追加（空 k 跳过、可覆盖前者含认证头，ChatStreamBase.start
// 同口径）+ body 走 mergeBodyOverrides（线上同一实现）。判据 judgeTextProbe（200 且解出非空
// 正文）；成功 detail = 正文原文，记账用 extractTitleUsage（全零不落库守卫自带）
// 结果行 + 请求日志收尾单点（2026-09-23 请求日志笔）：T1 探针有五条返回路径，逐条手写收尾
// 必漏（漏一处该条日志就永远停在「进行中」）——故收敛到本函数一处。失败时 detail 进日志，
// 成功时不记响应正文（本功能的边界：只记错误侧响应体，见 ReqLog.ets 头注释）
function probeRowLogged(logId: string, status: number, startedAt: number, result: string,
  detail: string, responseTail: string): ConnectTestRow {
  reqLogEnd(logId, status, Date.now() - startedAt, result === PROBE_OK ? '' : detail,
    responseTail);
  return probeRow(PROBE_KEY_TEXT, LABEL_TEXT, result, detail);
}

async function probeText(ctx: ProbeContext): Promise<ConnectTestRow> {
  const providerId: string = ctx.providerId;
  const startedAt: number = Date.now();
  let logId: string = '';
  try {
    const auth: NonStreamEndpoint = resolveNonStreamEndpoint(ctx.conn.baseUrl, ctx.model,
      ctx.conn.protocol, ctx.conn.endpoint, ctx.apiKey);
    for (const pair of ctx.conn.headers) {
      if (pair.k !== '') {
        auth.header[pair.k] = pair.v;
      }
    }
    const request: http.HttpRequest = http.createHttp();
    const probeBody: string = mergeBodyOverrides(composeTextProbeBody(ctx), ctx.conn.bodyOverrides);
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: auth.header,
      extraData: probeBody,
      usingCache: false,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: PROBE_CONNECT_TIMEOUT_MS,
      readTimeout: PROBE_READ_TIMEOUT_MS
    };
    logId = reqLogBegin({
      source: '连通性测试', model: ctx.model, method: 'POST', url: auth.url, headers: auth.header,
      body: probeBody
    });
    try {
      const resp: http.HttpResponse = await request.request(auth.url, options);
      // 响应头回填（2026-09-23 扩充笔）：须在下面各 probeRowLogged（内部 reqLogEnd）之前
      reqLogSetResponseHeaders(logId, resp.header);
      const body: string = typeof resp.result === 'string' ? resp.result : '';
      if (resp.responseCode !== 200) {
        return probeRowLogged(logId, resp.responseCode, startedAt, PROBE_FAIL,
          httpFailDetail(resp.responseCode, body), body);
      }
      let text: string = '';
      let usage: TitleUsageFrame = { promptTokens: 0, completionTokens: 0, cachedTokens: 0 };
      try {
        text = extractTitleText(ctx.conn.protocol, ctx.conn.endpoint, body);
        usage = extractTitleUsage(ctx.conn.protocol, ctx.conn.endpoint, body);
      } catch (e) {
        return probeRowLogged(logId, resp.responseCode, startedAt, PROBE_FAIL,
          '测试连接失败：响应不是有效 JSON', body);
      }
      if (judgeTextProbe(resp.responseCode, text !== '') !== PROBE_OK) {
        return probeRowLogged(logId, resp.responseCode, startedAt, PROBE_FAIL,
          '测试连接失败：响应缺少正文', body);
      }
      logTaskUsage('test', '', providerId, ctx.model,
        usage.promptTokens, usage.completionTokens, usage.cachedTokens);
      return probeRowLogged(logId, resp.responseCode, startedAt, PROBE_OK, text, '');
    } finally {
      // ★ 2026-09-23 自检轮修复：destroy 包 try（同 TitleApi / ChatStreamBase 两处先例的
      // 「二次释放异常不得外抛」）——裸 destroy 抛错会穿出本层落到下方 catch，把已收尾的结果
      // 行与日志条目**二次改写**成「网络失败」（reqLogEnd 是按 id 覆写，不是只写一次），用户
      // 看到的是假的测试结论。本件无日志设施，故静默忽略；异常已被拦在本层，不影响用户可见
      // 结论，不属 P0-1「静默失败」范畴
      try {
        request.destroy();
      } catch (e) {
      }
    }
  } catch (e) {
    return probeRowLogged(logId, -1, startedAt, PROBE_FAIL,
      '测试连接失败：' + describeNetError(e as Object), '');
  }
}

// 流式观测采集（T2/T3 共用一条流式链，差别 = 是否带 dummy 工具声明）：三路回调收成一个观测
// 对象后 resolve。★ 终态自动释放契约：ChatStreamBase 的 onDone 与 fail 在回调前已 release
// ——本层禁再调 disposeSilent、禁 abort（abort 走 fail('已手动停止') 污染判据），让流自然
// 收尾；关闭面板不中止进行中的流（结果由调用方纪元守卫丢弃）。usage 随 onDone 记账
function collectStream(ctx: ProbeContext, withTools: boolean): Promise<StreamObserved> {
  return new Promise<StreamObserved>((resolve) => {
    const providerId: string = ctx.providerId;
    const observed: StreamObserved = {
      httpCode: -1, hasError: false, errorText: '', sawContent: false, text: '',
      toolCalls: 0, toolName: ''
    };
    const names: Map<number, string> = new Map<number, string>();
    const handlers: AiStreamHandlers = {
      onDelta: (delta: SseDelta): void => {
        // 判据只看 content：思考帧（reasoningContent）不算正文（放它过等于假绿灯）
        if (delta.content !== '') {
          observed.sawContent = true;
          observed.text += delta.content;
        }
        if (delta.toolCalls !== undefined && delta.toolCalls.length > 0) {
          observed.toolCalls += delta.toolCalls.length;
          // 工具名两型聚合（name 分片拼接 / nameFull 全量替换——漏一型即重名 bug 家族）
          for (const piece of delta.toolCalls) {
            const merged: string = mergeToolCallName(names.get(piece.index) ?? '',
              piece.name !== undefined ? piece.name : '',
              piece.nameFull !== undefined ? piece.nameFull : '');
            names.set(piece.index, merged);
            if (merged !== '' && observed.toolName === '') {
              observed.toolName = merged;
            }
          }
        }
      },
      // 第三参 truncated（2026-09-23 输出上限治理笔 2 接口扩参）——连接探针不看截断判据，
      // 忽略（探针 PROBE_SAMPLING 上限 32 + thinking 恒 ''，天然不在上限联动生效面内）；
      // 第四参 firstTokenMs（2026-09-23 首字耗时笔接口扩参）——探针同样不看（它不计账、
      // purpose='test' 非聊天链，首字语义不适用；探针的原始耗时由 observed 侧自算）
      onDone: (usage: AiUsageDelta | null, durationMs: number, _truncated: boolean,
        _firstTokenMs: number): void => {
        observed.httpCode = 200;
        logTaskUsage('test', '', providerId, ctx.model,
          usage !== null ? usage.promptTokens : 0,
          usage !== null ? usage.completionTokens : 0,
          usage !== null && usage.cachedTokens !== undefined ? usage.cachedTokens : 0);
        resolve(observed);
      },
      // 第三参 sawContent（2026-09-22 自动重试笔接口扩参）——连接测试不看零产出判据，忽略
      onError: (message: string, status: number, _sawContent: boolean): void => {
        observed.hasError = true;
        observed.errorText = message;
        observed.httpCode = status;
        resolve(observed);
      }
    };
    const stream: ChatStream = createChatStream(ctx.conn.protocol, ctx.conn.endpoint, handlers);
    // 第 7 参 = 请求日志用途标签（2026-09-23 请求日志笔）：探针走的是线上同一条流式链，
    // 不传标签就会在请求日志里与正常对话混为一谈（ReqLog.ets）
    stream.start(ctx.conn, ctx.apiKey, [
      { role: 'system', content: PROBE_SYSTEM_PROMPT },
      { role: 'user', content: withTools ? DUMMY_TOOL_PROMPT : PROBE_USER_PROMPT }
    ], '', PROBE_SAMPLING, withTools ? [DUMMY_TOOL] : [], '连通性测试');
  });
}

// 流式两项展示文案：失败优先呈错误原文（ChatStreamBase 失败消息自带中文语义与状态码），无错误
// 按「未见正文增量」收口；T3 通过档再分「已调用 X」与「连通，但模型未调用工具 + 回复原文」
//（工具名取聚合结果，聚合不到回落 dummy 工具名）
function streamDetail(observed: StreamObserved, withTools: boolean, state: string): string {
  if (state !== PROBE_OK) {
    if (observed.errorText !== '') {
      return observed.errorText;
    }
    return observed.httpCode !== 200 ?
      '测试连接失败(HTTP ' + observed.httpCode + ')，响应无内容' : '测试连接失败：未收到正文增量';
  }
  if (!withTools) {
    return observed.text;
  }
  return observed.toolCalls > 0 ?
    '已调用 ' + (observed.toolName !== '' ? observed.toolName : DUMMY_TOOL_NAME) :
    '连通，但模型未调用工具\n' + observed.text;
}

// T2/T3 流式探针（withTools 分流两项）：自吞一切异常成结果行——一项炸不得带塌另两项
async function probeStream(ctx: ProbeContext, withTools: boolean): Promise<ConnectTestRow> {
  const key: string = withTools ? PROBE_KEY_TOOL : PROBE_KEY_STREAM;
  const label: string = withTools ? LABEL_TOOL : LABEL_STREAM;
  try {
    const observed: StreamObserved = await collectStream(ctx, withTools);
    const state: string = withTools ?
      judgeToolProbe(observed.httpCode, observed.toolCalls) :
      judgeStreamProbe(observed.httpCode, observed.sawContent, observed.hasError);
    return probeRow(key, label, state, streamDetail(observed, withTools, state));
  } catch (e) {
    return probeRow(key, label, PROBE_FAIL, '测试连接失败：' + describeNetError(e as Object));
  }
}

// 前置失败：三行同落失败 + 同一句原因（面板已打开，零请求——D12）
function failAllRows(onRow: (row: ConnectTestRow) => void, detail: string): void {
  for (const row of connectTestRows(PROBE_FAIL)) {
    onRow(probeRow(row.key, row.label, PROBE_FAIL, detail));
  }
}

// 能力三项测试总编排（宿主单支入口调用，打开面板即跑）：前置检查 -> 扩展口径读库 -> 三探针
// 并发逐行上行。
// · 前置三路（baseUrl 空 / 该支明文缺失 / 无启用 chat 模型）任一不过 = 三行直接落失败 +
//   固定文案、零请求（P0-1 不静默）；
// · 结果经 onRow 逐行上行，**纪元守卫在调用方**（宿主每次开面板自增 epoch，回调内比对，不
//   匹配即整包丢弃——防重开面板闪现上一轮结果）；onModel 回传副标题要显示的模型名；
// · 三项并发：探针自吞异常一律 resolve，故 Promise.all 不会 reject（一项失败不外溢）
export async function runConnectTests(providerId: string, keyId: string, baseUrl: string,
  protocol: string, endpoint: string, onModel: (model: string) => void,
  onRow: (row: ConnectTestRow) => void): Promise<void> {
  try {
    if (baseUrl === '') {
      failAllRows(onRow, '请先填写 Base URL 再测试连接');
      return;
    }
    const plain: string = await loadPoolKey(providerId, keyId);
    if (plain === '') {
      failAllRows(onRow, '明文缺失，无法测试');
      return;
    }
    const models: ModelRow[] = await queryModels(providerId, 'chat');
    const first: ModelRow | undefined = models.find((m: ModelRow): boolean => m.enabled);
    if (first === undefined) {
      failAllRows(onRow, '请先在模型页签添加模型再测试');
      return;
    }
    let headers: HeaderPair[] = [];
    let overrides: HeaderPair[] = [];
    const providers: ProviderRow[] = await queryProviders();
    const found: ProviderRow | undefined =
      providers.find((p: ProviderRow): boolean => p.id === providerId);
    if (found !== undefined) {
      headers = parseHeaderPairs(found.headers);
      overrides = parseHeaderPairs(found.bodyOverrides);
    }
    onModel(first.modelId);
    const ctx: ProbeContext = {
      providerId: providerId, model: first.modelId, apiKey: plain,
      conn: {
        baseUrl: baseUrl, model: first.modelId, protocol: protocol, endpoint: endpoint,
        headers: headers, providerId: providerId, bodyOverrides: overrides
      }
    };
    const emit = (probe: Promise<ConnectTestRow>): Promise<void> => {
      return probe.then((row: ConnectTestRow): void => {
        onRow(row);
      });
    };
    await Promise.all([emit(probeText(ctx)), emit(probeStream(ctx, false)),
      emit(probeStream(ctx, true))]);
  } catch (e) {
    failAllRows(onRow, (e as Error).message);
  }
}
