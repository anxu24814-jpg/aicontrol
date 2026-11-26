// 沙箱网络桥——ArkTS 半。职责一句话 = 「把 native 的待办请求转成对既有 HTTP 链的一次
// 完整调用，并把结果回填」+ 运行上下文单槽与放弃态。
// · 出口唯一：本桥只调 executeFlow——出站治理（哨兵 / 限速 / 熔断 / 白名单）/ 请求日志 /
//   Cookie / 凭据注入全在链内照常生效，禁绕过、禁另起裁决链；第三参 taskId 恒 ''（同步路
//   ——传非空即切后台超时链，照 ToolHttp 先例）。
// · 线程纪律：dispatch 必须全程 async（投递即返回、await 链在内部——主线程永不等待
//   worker）；任何抛出都转回填失败（绝不让 worker 等满上限）。
// · 上下文与放弃态 per-run 化（K 路并发打破原进程级单槽——B 路进入会覆写 A 路上下文，
//   A 的 httpGet 会拿 B 的会话凭据域发请求）：runKey 键控 Map 槽；enter 建槽清放弃态、
//   exit 删槽（迟到 dispatch 走「上下文缺失」失败支，不发请求）；槽上界 = K + 极短窗口
//   的已 settle 未删防御（数据有界红线满足）。
// · 放弃态（超时 / 取消后停发）：一次性置位，置位后 dispatch 第一判据立即失败、发出零
//   请求；阻塞中的那一次不被打断（等其自然收敛）。
// · 写授权闸（决明改向：授权为**全局单开关**，不按助手区分）：写方法（POST/PUT/DELETE/
//   PATCH）须「允许脚本发写请求」开关开（每请求现读、fail-closed），GET 不受开关影响；
//   闸位 = 域名闸后、生效超时前（先去目的地合法性、后动作合法性）；拒即不发零日志条目。
// · import 环纪律（坑50）：桥只引叶子与既有域件，禁引 JsvmEngine / ScriptEnginePick /
//   ToolTypes / ToolCodeExec（引擎在上方引桥，反向即环）。
// · 双引擎双装：两引擎各有自有 native TSFN 待办池（libcodeexec.so / libqjsengine.so），
//   同一 dispatcher 函数装进两个 so（各自幂等布尔守卫）；回填双发——callId 只在拥有
//   它的池命中，另一侧 native 对未命中 callId 静默丢弃（两 so 运行期互不可见，callId
//   池各自键控无歧义）。
import codeExec from 'libcodeexec.so';
import qjsExec from 'libqjsengine.so';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { httpTimeoutCeilingMs } from '../AppPreferences';
import { codeHttpHostsAllowAny, codeHttpHostsFor, isCodeHttpWriteEnabled, normalizeHttpPolicyHost } from '../AppPreferencesHttp';
import { executeFlow, HttpFlowArgs, HTTP_MAX_LENGTH_DEFAULT,
  HTTP_URL_MAX_CHARS } from '../providers/HttpFlow';
import { isScriptWriteMethod, SCRIPT_HTTP_METHODS, scriptHostAllowed,
  scriptHostBlockedErrorText, scriptHostNoneGrantedErrorText, scriptMethodUnknownErrorText,
  scriptWriteDeniedErrorText } from '../providers/HttpPolicy';
import { httpHostOfUrl } from '../providers/HttpOutboundGuard';
import { HTTP_TIMEOUT_MS_DEFAULT, isTextContentType,
  resolveHttpTimeoutMs } from '../providers/HttpReceipt';
import { isHttpUrl } from '../providers/ToolBrowse';

// 等待上限构造余量（毫秒，单源本件——官方 readTimeout 触发到 promise 落定之间的调度
// 余量；httpWaitMs = min(用户上限档, 档位时限) + 本值）
const SCRIPT_HTTP_WAIT_MARGIN_MS: number = 5000;

// ── 运行上下文单槽与放弃态 ──

// 桥运行上下文（调度域进入运行时置、引擎 settle 时清；scope 透传原执行上下文值——快照
// 组装忠实原值，防将来链内新增 scope 判据时桥给错值）
export interface ScriptHttpRunContext {
  scope: string;
  conversationId: string; // 入链（凭据 / Cookie / 校验缓存按会话分桶）
  assistantId: string;    // 域名清单归属 + 凭据命名空间
  runId: string;          // 在途登记（httpAbortRun 定向掐断面；只进上下文快照，不进 taskId 位）
  tierTimeoutMs: number;  // 档位时限（生效超时封顶 + 等待上限构造）
}

// per-run 槽（ctx + 放弃态两域合一，键 = runKey——调度器注入）
interface BridgeRunSlot {
  ctx: ScriptHttpRunContext;
  abandoned: boolean;
  abandonReason: string;
}

let scriptHttpRunSlots: Map<string, BridgeRunSlot> = new Map();
let scriptHttpDispatcherInstalled: boolean = false;
let scriptHttpQjsDispatcherInstalled: boolean = false;

// 进入运行（ScriptScheduler.startEntry 调）：建槽清放弃态；首次调用顺带装双 dispatcher
//（d.ts 契约返 boolean——true 才置位；false = native TSFN 创建失败，不置位下次进入重试；
// 未装期间 httpGet 统一报「未能交给应用发送」）。两枚幂等安装布尔进程级共享但并发安全
//（幂等、无 per-run 语义，K=2 下第一路装第二路跳过——不需改，禁误改）
export function enterScriptHttpRun(ctx: ScriptHttpRunContext, runKey: string): void {
  const slot: BridgeRunSlot = { ctx: ctx, abandoned: false, abandonReason: '' };
  scriptHttpRunSlots.set(runKey, slot);
  if (!scriptHttpDispatcherInstalled) {
    try {
      if (codeExec.setHttpDispatcher(scriptHttpDispatch)) {
        scriptHttpDispatcherInstalled = true;
      }
    } catch (e) {
      // 安装失败不阻断运行（无网脚本不受影响）——桥路 httpGet 由 native 侧未装防御支
      // 统一中文报错；下轮进入重试安装
    }
  }
  if (!scriptHttpQjsDispatcherInstalled) {
    try {
      if (qjsExec.setHttpDispatcher(scriptHttpDispatch)) {
        scriptHttpQjsDispatcherInstalled = true;
      }
    } catch (e) {
      // 同上（QuickJS 侧自有 TSFN 安装点——装失败该引擎桥路报「未能交给应用发送」）
    }
  }
}

// 置放弃态（调度域计时器胜出 / cancelForConversation 调——只置该路槽，他路不受扰；
// 值域 'timeout' | 'canceled'，两态文案在 dispatch 第①判据分选）；置位后新请求零发出，
// 阻塞中的那一次等自然收敛（不打断）
export function abandonScriptHttpRun(runKey: string, reason: string): void {
  const slot: BridgeRunSlot | undefined = scriptHttpRunSlots.get(runKey);
  if (slot === undefined) {
    return; // 槽已删（settle 后迟到的放弃置位）——no-op
  }
  slot.abandoned = true;
  slot.abandonReason = reason;
}

// 退出运行（调度域在引擎 settle 时调——onEngineSettle 的 running 守卫内，每条目恰一次
// 且先于下一条目 enter；计时器先到路径 settle 到点补清，期间放弃态兜住零请求。删槽后
// 迟到 dispatch 走上下文缺失失败支，不发请求）
export function exitScriptHttpRun(runKey: string): void {
  scriptHttpRunSlots.delete(runKey);
}

// 等待上限构造（算式单源本函数，禁在执行器重写）：min(用户上限档, 档位时限) + 余量
export function scriptHttpWaitMs(tierTimeoutMs: number): number {
  return Math.min(httpTimeoutCeilingMs(), tierTimeoutMs) + SCRIPT_HTTP_WAIT_MARGIN_MS;
}

// ── 回填小件（双发：两池各调一次——callId 只在拥有它的池命中，另一侧 native
//    对未命中 callId 静默丢弃〔两 so 待办表互不可见〕）──

// 失败回填（错误文本经 JSON.stringify 组装——文案含引号也恒合法）
function resolveFailure(callId: string, errorText: string): void {
  try {
    codeExec.resolveHttpCall(callId, JSON.stringify({ error: errorText }));
  } catch (e) {
    // 回填本身失败（理论不可达）——native 侧等待到点兜底
  }
  try {
    qjsExec.resolveHttpCall(callId, JSON.stringify({ error: errorText }));
  } catch (e) {
    // 同上（QuickJS 池）
  }
}

// 成功回填（kind 定死两形态；bytes 缓冲原样交 native——入口即拷，引用即断）
function resolveSuccess(callId: string, kind: string, bytes: ArrayBuffer): void {
  try {
    codeExec.resolveHttpCall(callId, '{"kind":"' + kind + '"}', bytes);
  } catch (e) {
    // 同上
  }
  try {
    qjsExec.resolveHttpCall(callId, '{"kind":"' + kind + '"}', bytes);
  } catch (e) {
    resolveFailure(callId, '脚本网络桥没有可用的会话上下文，请求没有发出。请重新运行脚本。');
  }
}

// ── dispatcher 主体（TSFN 回调调——单次请求全链十步闸序；第四参 runKey：①②判据按它
//    取 per-run 槽，其余闸序零变化）──

async function scriptHttpDispatch(callId: string, url: string,
  optsJson: string, runKey: string): Promise<void> {
  try {
    // per-run 槽取用（①②判据合一取位：槽缺 = 迟到 dispatch 或未 enter——上下文缺失支）
    const slot: BridgeRunSlot | undefined = scriptHttpRunSlots.get(runKey);
    // ①放弃态检查（第一判据）：已放弃的运行不再发新请求（回执已作废，不产生外部副作用）
    if (slot !== undefined && slot.abandoned) {
      resolveFailure(callId, slot.abandonReason === 'canceled' ?
        '本次运行已取消，不再发起新的网络请求。' :
        '本次运行已经超时放弃，不再发起新的网络请求。结果已作废，请重新运行脚本。');
      return;
    }
    // ②上下文缺失（运行已结束的迟到 dispatch / 未知 runKey——失败支，不发请求）
    if (slot === undefined) {
      resolveFailure(callId, '脚本网络桥没有可用的会话上下文，请求没有发出。请重新运行脚本。');
      return;
    }
    const runCtx: ScriptHttpRunContext = slot.ctx;
    // ③opts 解析（语义校验单源在此——native 只透传：headers 值必须字符串、timeoutMs 有限
    // 数、method 五值域内、body 必须字符串、未知键点名报错——防静默忽略让模型以为参数生效）
    const headers: Record<string, string> = {};
    let timeoutMsArg: number = 0;
    let effectiveMethod: string = 'GET';
    let effectiveBody: string = '';
    if (optsJson !== '' && optsJson !== '{}') {
      let parsedOpts: Object;
      try {
        parsedOpts = JSON.parse(optsJson) as Object;
      } catch (e) {
        resolveFailure(callId, 'httpGet 的 opts 参数无法解析为对象，请修正后重试。');
        return;
      }
      if (typeof parsedOpts !== 'object' || parsedOpts === null || Array.isArray(parsedOpts)) {
        resolveFailure(callId, 'httpGet 的第二个参数需要是对象，请修正后重试。');
        return;
      }
      const optsRec = parsedOpts as Record<string, Object>;
      for (const key of Object.keys(optsRec)) {
        if (key === 'headers') {
          const rawHeaders: Object = optsRec[key];
          if (typeof rawHeaders !== 'object' || rawHeaders === null ||
            Array.isArray(rawHeaders)) {
            resolveFailure(callId, 'httpGet 的 opts 里 headers 需要是对象，请修正后重试。');
            return;
          }
          const headersRec = rawHeaders as Record<string, Object>;
          for (const headerKey of Object.keys(headersRec)) {
            const headerValue: Object = headersRec[headerKey];
            if (typeof headerValue !== 'string') {
              resolveFailure(callId, 'httpGet 的 opts 里 headers 的 ' + headerKey +
                ' 值必须是字符串，请修正后重试。');
              return;
            }
            headers[headerKey] = headerValue;
          }
        } else if (key === 'timeoutMs') {
          const rawTimeout: Object = optsRec[key];
          if (typeof rawTimeout !== 'number' || !Number.isFinite(rawTimeout as number)) {
            resolveFailure(callId, 'httpGet 的 opts 里 timeoutMs 需要是数值，请修正后重试。');
            return;
          }
          timeoutMsArg = rawTimeout as number;
        } else if (key === 'method') {
          // 方法值域校验（五值单源 SCRIPT_HTTP_METHODS；大小写敏感——不代做归一，越界即点名句）
          const rawMethod: Object = optsRec[key];
          if (typeof rawMethod !== 'string') {
            resolveFailure(callId, 'httpGet 的 opts 里 method 需要是字符串，请修正后重试。');
            return;
          }
          effectiveMethod = rawMethod;
          if (!SCRIPT_HTTP_METHODS.includes(effectiveMethod)) {
            resolveFailure(callId, scriptMethodUnknownErrorText(effectiveMethod));
            return;
          }
        } else if (key === 'body') {
          // 请求体（仅字符串；与 method 的组合合法性交链内既有闸——GET/HEAD 带体拒句单源
          // 在 HttpFlow，本桥不预判）
          const rawBody: Object = optsRec[key];
          if (typeof rawBody !== 'string') {
            resolveFailure(callId, 'httpGet 的 opts 里 body 需要是字符串，请修正后重试。');
            return;
          }
          effectiveBody = rawBody;
        } else {
          resolveFailure(callId, 'httpGet 的 opts 里有不认识的参数 ' + key +
            '。只支持 headers、timeoutMs、method 与 body。');
          return;
        }
      }
    }
    // ④URL 闸（协议白名单单源 ToolBrowse.isHttpUrl——禁另写正则；长度闸单源 HTTP_URL_MAX_CHARS）
    if (!isHttpUrl(url)) {
      resolveFailure(callId, 'httpGet 只支持 http 与 https 地址。');
      return;
    }
    if (url.length > HTTP_URL_MAX_CHARS) {
      resolveFailure(callId, '网址过长，上限 ' + HTTP_URL_MAX_CHARS + ' 字符，请缩短后重试。');
      return;
    }
    // ⑤域名闸（主闸，fail-closed）：预授权清单并集（助手名单 ∪ 全局名单，codeHttpHostsFor
    // 单源——两段全空 = 全禁）——链外先判（拒则不发出不进请求日志，与工具侧「被拒请求不
    // 消耗节奏位」同口径）；链内仍有全局域名准入白名单与哨兵 / 限速闸（两道域名闸都过才
    // 发出）。域名请求模式 any 时本闸短路放行（读口每请求现读，运行中切模式对后续请求
    // 即时生效——与⑤′写授权闸同款）
    const host: string = normalizeHttpPolicyHost(httpHostOfUrl(url));
    const hosts: string[] = codeHttpHostsFor(runCtx.assistantId);
    if (!codeHttpHostsAllowAny() && !scriptHostAllowed(host, hosts)) {
      resolveFailure(callId, hosts.length === 0 ? scriptHostNoneGrantedErrorText() :
        scriptHostBlockedErrorText(host));
      return;
    }
    // ⑤′写方法 × 授权（fail-closed，闸位 = 域名闸后、生效超时前——预授权域名管「能去哪」，
    // 写授权开关管「能做什么动作」，先去目的地合法性、后动作合法性）：GET 不受开关影响；
    // 写方法须全局单开关开（每请求现读；缺省/脏值 = 关，不按助手区分）；拒即不发
    //（零请求、零日志条目——与域名闸同口径）
    if (isScriptWriteMethod(effectiveMethod) && !isCodeHttpWriteEnabled()) {
      resolveFailure(callId, scriptWriteDeniedErrorText(effectiveMethod));
      return;
    }
    // ⑥生效超时（单次请求超时受档位时限封顶）：resolveHttpTimeoutMs 钳制单源（下限 5 秒
    // 与「档位时限封顶」两条同时成立）
    const wantedMs: number = timeoutMsArg > 0 ? timeoutMsArg : HTTP_TIMEOUT_MS_DEFAULT;
    const effectiveTimeoutMs: number = resolveHttpTimeoutMs(
      Math.min(wantedMs, runCtx.tierTimeoutMs),
      Math.min(httpTimeoutCeilingMs(), runCtx.tierTimeoutMs));
    // ⑦组执行链入参（方法按 opts 透传、缺省 GET；wantBytes 档——正文按原始字节回传、
    // 日志来源「脚本联网」）
    const flowArgs: HttpFlowArgs = {
      url: url, method: effectiveMethod, body: effectiveBody,
      maxLength: HTTP_MAX_LENGTH_DEFAULT,
      startIndex: 0, timeoutMsArg: effectiveTimeoutMs, wantDownload: false,
      fileArg: '', multipartArg: null, headers: headers, streamMsArg: 0, maxEventsArg: 0,
      wantStream: false, wantBytes: true
    };
    // 上下文快照（照 ToolHttp 后台任务先例剥组件闭包：isRunActive 恒 true、图收集两缝
    // 恒 false 防御位——桥不经工作区图片路；runId 进快照供在途登记与定向掐断，不进 taskId 位）
    const bgCtx: ToolExecutionContext = {
      scope: runCtx.scope, conversationId: runCtx.conversationId, runId: runCtx.runId,
      attemptId: '', assistantId: runCtx.assistantId, memoryScopeAssistantId: '',
      knowledgeAssistantId: '', searchResultCount: 0,
      isRunActive: (_runId: string): boolean => true,
      hasVision: false,
      collectImage: (_mimeType: string, _data: string): boolean => false,
      collectPageImage: (_mimeType: string, _data: string): boolean => false,
      // 预检便签：桥只跑 HTTP 流、不经工具预检→执行信道，恒空串（与上方两图缝防御位同款）
      preflightMemo: ''
    };
    // ⑧执行链（第三参 taskId 恒 ''——同步路）与回执解析
    const flow = await executeFlow(flowArgs, bgCtx, '');
    let receipt: Record<string, Object>;
    try {
      receipt = JSON.parse(flow.json) as Record<string, Object>;
    } catch (e) {
      // 回执解析失败（理论不可达——json 恒为链内 JSON.stringify 产物）：请求已发出且
      // 完成，文案须与②上下文缺失支区分（彼支才是「没有发出」）
      resolveFailure(callId, '请求已完成但回执解析失败。');
      return;
    }
    const errorText: Object | undefined = receipt['error'];
    if (typeof errorText === 'string') {
      // 链内闸拒 / 网络失败 / 非 2xx——底层中文句原样透传（拍板：不美化）；含
      // retry_after_seconds 时追加等待指引，两道衔接守卫：限速支 error 已自带「请在约
      // X 秒后重试」指引，再追加即双重指引——已含「秒后重试」则跳过；句尾无终止符时先补
      // 句号（非 2xx 句尾是响应正文片段，直接追加会连字）
      let text: string = errorText;
      const retryAfter: Object | undefined = receipt['retry_after_seconds'];
      if (typeof retryAfter === 'number' && retryAfter > 0 &&
        text.indexOf('秒后重试') < 0) {
        const tail: string = text.charAt(text.length - 1);
        if (tail !== '。' && tail !== '！' && tail !== '？' && tail !== '\n' &&
          tail !== '.' && tail !== '!' && tail !== '?') {
          text += '。';
        }
        text += '约 ' + Math.ceil(retryAfter) + ' 秒后可重试。';
      }
      resolveFailure(callId, text);
      return;
    }
    const statusRaw: Object | undefined = receipt['status'];
    const status: number = typeof statusRaw === 'number' ? statusRaw : 0;
    if (status < 200 || status >= 300) {
      // 2xx 外兜底（非 2xx 的 error 文案已由链内组好——本支理论不可达，防御不静默）
      resolveFailure(callId, '请求失败，HTTP 状态码 ' + status + '。');
      return;
    }
    const bytes: ArrayBuffer | null = flow.bytes;
    if (bytes === null) {
      // 2xx 成功后仅字节面缺失（理论不可达——wantBytes 成功路恒带 bytes）：请求已成功，
      // 文案须与②上下文缺失支区分
      resolveFailure(callId, '请求成功但响应字节不可用。');
      return;
    }
    // 文本 / 二进制分派（判据单源 isTextContentType——与 http_request 工具同判据；解码
    // 单源在 native 侧 CreateStringUtf8，与本桥无关）
    const contentTypeRaw: Object | undefined = receipt['contentType'];
    const contentType: string = typeof contentTypeRaw === 'string' ? contentTypeRaw : '';
    resolveSuccess(callId, isTextContentType(contentType) ? 'text' : 'bytes', bytes);
  } catch (e) {
    // ⑨全程兜底（P0——绝不能让异常逃逸导致 worker 等满上限）：异常点可在请求发出前
    // 或后的任意环节，发出与否不可断言——文案如实中性，不引导重复发请求
    resolveFailure(callId, '请求处理中断，无法确定请求是否已发出。');
  }
}
