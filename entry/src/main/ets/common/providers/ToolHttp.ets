// HTTP 请求工具域：内置第 24 件工具 http_request——通用 HTTP 工具（method + URL + headers +
// body），模型可向任意 http(s) 地址发请求调 REST API、触发 webhook、控局域网设备。本文件 =
// 执行器（解析模型入参、分流〔单请求 / 管道 / 长任务 / 查询〕、过闸序、组装回执），注册在
// ToolTypes（契约自叶子 ToolContracts 引，禁自 ToolTypes 引防环；isHttpUrl 自 ToolBrowse 引
// ——ToolBrowse → WebSearchParse 单向链无环，坑50）。域拆分：传输与掐断 → HttpTransport；
// 预检与声明面 → HttpPreflight；SSE 分帧 → HttpSse；长任务句柄表 → HttpTaskTable；Cookie
// jar → HttpCookieJar；执行链 → HttpFlow；管道纯函数 → HttpPipeline。历史沿革以各域件头注释
// 与 docs/变更记录.md 为源，本头不复述。
// 安全口径速览（细则在各域件）：GET/HEAD/OPTIONS 直通；POST/PUT/DELETE/PATCH 逐次确认
//（档位裁决在 HttpPreflight 预检 + ConfirmRouting 归一；域名确认档已 2026-11-11 整档退役）；内网不拦截 + URL 内嵌凭据
// 恒拒 + 云元数据恒拒 + 域名白名单 + 出站哨兵（HttpPolicy）；限速熔断 + 会话内验证器缓存
//（HttpOutboundGuard）；凭据 {{名称}} 注入（HttpCredentials）；传输层一建一销 + finally
// destroy + 先记取消终态再 destroy（坑75 家族）；日志面恒模型原始输入——凭据真值与 Cookie
// 回带头零进日志（守卫钉守）。
// 功能面（细则在各域件）：①事件流窗口——stream_ms / max_events（钳制与分帧在 HttpSse），
// 窗口到量软停止 + truncated，idle 8 秒硬中止；②长任务句柄——async: true 立即受理回
// task_id、后台跑完整执行链（同链同闸零第二实现），task_id + 可选 wait_ms 查询（到时不是
// 错误），状态机与 TTL / lost 语义在 HttpTaskTable，取消由 httpAbortRun 掐断链同源承接；
// ③Cookie 会话保持——按 host 有界存 jar、后续自动回带同 host（用户显式 Cookie 头恒优先，
// 回带头零进日志），会话切换即清、零持久化；④代理接线——网络设置代理三档对工具请求生效
//（applyEffectiveProxy）；⑤请求管道——单次调用传 requests 数组（至多 8 步 / 总时长 120 秒，
// 纯顺序禁并发），前序响应入正文表，后续步骤经 {{步骤下标.点路径}} 占位符替换 url / 请求头
// 值 / body，每步委托既有执行链走全闸（零豁免），写请求合并单卡确认（预检层一次覆盖），
// 失败即停回「第几个失败、为什么」，每步结果不进对话（终态 = 最后一步完整回执 + 各步摘要），
// 中间步正文超 2000 字符落工作区保全文；管道不可保存为模板。
// 结果自控 ≤8192（fitHttpResult 回缩，单源 HttpReceipt）——流式与长任务回执同走该通道
//（红线：新字段不得把正文挤空）。
import { util } from '@kit.ArkTS';
import { ToolExecutor, toolArgsParseErrorText, toolErrorText } from './ToolContracts';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { isHttpUrl } from './ToolBrowse';
import { getHttpTaskMirrorJson, setHttpTaskMirror } from '../AppPreferencesHttp';
import { HTTP_TASK_MAX_ENTRIES, HTTP_TASK_STATUS_CANCELLED, HTTP_TASK_STATUS_COMPLETED,
  HTTP_TASK_STATUS_FAILED, HTTP_TASK_STATUS_LOST, HTTP_TASK_STATUS_RUNNING,
  HTTP_TASK_STATUS_TIMED_OUT, HTTP_TASK_WAIT_MS_MAX, HttpTaskRecord, HttpTaskTable,
  resolveTaskTimeoutMs } from './HttpTaskTable';
import { saveDownloadToWorkspace } from './HttpBinary';
import { clipResultText, fitHttpResult, HTTP_TIMEOUT_MS_DEFAULT } from './HttpReceipt';
import { executeFlow, HttpFlowArgs, HttpFlowOutcome, HTTP_MAX_LENGTH_DEFAULT,
  HTTP_URL_MAX_CHARS } from './HttpFlow';
import { httpAbortRun } from './HttpTransport';
import { collectStepRefs, HTTP_PIPELINE_FAILURE_ERROR_MAX, HTTP_PIPELINE_STEP_PREVIEW_MAX,
  HTTP_PIPELINE_STEP_SAVE_CHARS, HTTP_PIPELINE_STEP_URL_MAX, HTTP_PIPELINE_TOTAL_MS_MAX,
  HTTP_REQUEST_METHODS, lastReaderIndices, PipelineReplaceOutcome, PipelineStepSpec,
  replaceStepRefs, validatePipelineSpec }
  from './HttpPipeline';

// 掐断入口与声明面转出（域拆分兼容面——消费方存量 import 零改动，新码建议直引各域件；
// HTTP_REQUEST_METHODS 迁址 HttpPipeline〔步骤 method 校验判据随结构单源走〕，此处
// re-export 保存量零改动）
export { httpAbortAll, httpAbortRun } from './HttpTransport';
export { HTTP_REQUEST_DESC, HTTP_REQUEST_SCHEMA, httpRequestNeedsConfirm,
  buildHttpConfirmPreview } from './HttpPreflight';
export { HTTP_REQUEST_METHODS } from './HttpPipeline';

// 入参长度上限（字符）——无上限时模型塞大文本会灌进卡片展示、DB 落库与每轮重发的历史
export const HTTP_ARGS_MAX_CHARS: number = 100000;

// 长任务句柄表实例（实现在 HttpTaskTable）：进程级单例；构造即恢复持久化镜像（重启前仍
// running 的标 lost——语义见 HttpTaskTable 文件头）；镜像读写单源 AppPreferencesHttp
//（本件不直接摸 AppStorage 键）
let httpTaskTableInstance: HttpTaskTable | null = null;
let httpTaskTableRestored: boolean = false;

function taskTable(): HttpTaskTable {
  if (httpTaskTableInstance === null) {
    httpTaskTableInstance = new HttpTaskTable();
  }
  if (!httpTaskTableRestored) {
    httpTaskTableRestored = true;
    httpTaskTableInstance.restore(getHttpTaskMirrorJson(), Date.now());
    setHttpTaskMirror(httpTaskTableInstance.serializeRunning());
  }
  return httpTaskTableInstance;
}

// ★ 停止键连带取消入口（决明拍板）：掐断本会话所有仍在跑的后台长任务。缺口 = 后台任务
// 在途项登记发起轮 runId，发起轮结束后新轮停止键 httpAbortRun(本 run) 匹配不到它。本入口
// 按会话查句柄表、逐任务以各自 initiatorRunId 走既有掐断链精确匹配（归类链零新面）；分栏
// 他会话不在查询结果内不会误伤。currentRunId 豁免 = 当前轮在途由调用方承接、不重复掐。
// 返回取消数（诊断面，主链不消费）
export function httpAbortConversationBackground(conversationId: string,
  currentRunId: string): number {
  if (conversationId === '') {
    return 0; // 空会话身份不掐任何任务（fail-safe 不越界，httpAbortRun 同款口径）
  }
  const runIds: string[] = taskTable().runningRunIdsForConversation(conversationId);
  let aborted: number = 0;
  for (const runId of runIds) {
    if (runId !== currentRunId) {
      httpAbortRun(runId);
      aborted++;
    }
  }
  return aborted;
}

// ── 执行器 ──

export class HttpRequestExecutor implements ToolExecutor {
    // async：凭据注入段需 await 名称→值缓存；return Promise.resolve 形态在 async 内语义不变
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    // 启用面由声明层承担（defsFor 按助手工具页「HTTP 请求」卡开关过滤），执行器无会话/
    // 清单上下文可判、不设第二道
    if (argsJson.length > HTTP_ARGS_MAX_CHARS) {
      return Promise.resolve(JSON.stringify({ error: '请求参数过长。请减小请求参数后重试' }));
    }
    let url: string = '';
    let method: string = 'GET';
    let body: string = '';
    let maxLength: number = HTTP_MAX_LENGTH_DEFAULT;
    let startIndex: number = 0;
    // 模型传入的超时：0 = 未传/非法（由钳制函数落默认档）
    let timeoutMsArg: number = 0;
    // download 落工作区 / file 直传附件名 / multipart 表单
    let wantDownload: boolean = false;
    let fileArg: string = '';
    let multipartArg: Record<string, Object> | null = null;
    // 窗口读取两参：0 = 未传（钳制函数落默认档）
    let streamMsArg: number = 0;
    let maxEventsArg: number = 0;
    // 长任务三参：async 发起 / task_id 查询 / wait_ms 有界等待
    let wantAsync: boolean = false;
    let taskIdArg: string = '';
    let waitMsArg: number = 0;
    // 管道参数：requests 数组原样收（结构校验与步骤规格在 validatePipelineSpec）
    let requestsRaw: Object | undefined = undefined;
    // 顶层单请求参数在场登记（与 requests 同传时点名报错——静默忽略会让模型以为顶层
    // headers/body 作用于所有步骤，步骤带缺省头发出 401 才暴露；P0-1）
    const singleOnlyKeys: string[] = [];
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
        singleOnlyKeys.push('method');
      } else if (typeof methodRaw !== 'undefined') {
        // 非串点名报错——静默保持 GET = 类型违约静默降级（P0-1），与管道路同位判据同款
        return Promise.resolve(JSON.stringify({ error: 'method 必须是字符串。请修正后重试' }));
      }
      const headersRaw: Object = parsed['headers'];
      if (typeof headersRaw === 'object' && headersRaw !== null && !Array.isArray(headersRaw)) {
        singleOnlyKeys.push('headers');
        const rec = headersRaw as Record<string, Object>;
        for (const key of Object.keys(rec)) {
          const value: Object = rec[key];
          if (typeof value === 'string') {
            headers[key] = value;
          } else {
          // 非字符串头值 = schema 违约（additionalProperties string），点名违规键。不
          // String() 收编——对象值会落 '[object Object]' 垃圾头；静默丢弃则缺头照发、模型
          // 与用户均无感知（P0-1 禁静默失败）
            return Promise.resolve(JSON.stringify({
              error: '请求头 ' + key + ' 的值必须是字符串。请修正后重试' }));
          }
        }
      } else if (typeof headersRaw !== 'undefined') {
        // 排数组——Object.keys 会把数组按下标拆成「0/1/2」垃圾请求头静默发出
        return Promise.resolve(JSON.stringify({ error: 'headers 必须是对象。请修正后重试' }));
      }
      const bodyRaw: Object = parsed['body'];
      if (typeof bodyRaw === 'string') {
        body = bodyRaw;
        singleOnlyKeys.push('body');
      } else if (typeof bodyRaw !== 'undefined') {
        // 非串点名报错（静默丢弃 = 请求体无声丢失，同管道路回执）
        return Promise.resolve(JSON.stringify({ error: 'body 必须是字符串。请修正后重试' }));
      }
      const maxRaw: Object = parsed['max_length'];
      if (typeof maxRaw === 'number' && Number.isFinite(maxRaw)) {
        maxLength = maxRaw;
        singleOnlyKeys.push('max_length');
      }
      const startRaw: Object = parsed['start_index'];
      if (typeof startRaw === 'number' && Number.isFinite(startRaw)) {
        startIndex = startRaw;
        singleOnlyKeys.push('start_index');
      }
      const timeoutRaw: Object = parsed['timeout_ms'];
      if (typeof timeoutRaw === 'number' && Number.isFinite(timeoutRaw)) {
        timeoutMsArg = Math.round(timeoutRaw);
        singleOnlyKeys.push('timeout_ms');
      }
      const downloadRaw: Object = parsed['download'];
      if (typeof downloadRaw === 'boolean') {
        wantDownload = downloadRaw;
      }
      const fileRaw: Object = parsed['file'];
      if (typeof fileRaw === 'string') {
        fileArg = fileRaw.trim();
      } else if (typeof fileRaw !== 'undefined') {
        // 非串点名报错（静默丢弃 = 直传附件无声丢失）
        return Promise.resolve(JSON.stringify({ error: 'file 必须是字符串。请修正后重试' }));
      }
      const multipartRaw: Object = parsed['multipart'];
      if (typeof multipartRaw === 'object' && multipartRaw !== null && !Array.isArray(multipartRaw)) {
        multipartArg = multipartRaw as Record<string, Object>;
      } else if (typeof multipartRaw !== 'undefined') {
        // 非对象（含数组）点名报错——静默忽略则违约形态无感知
        return Promise.resolve(JSON.stringify({ error: 'multipart 必须是对象。请修正后重试' }));
      }
      const streamRaw: Object = parsed['stream_ms'];
      if (typeof streamRaw === 'number' && Number.isFinite(streamRaw)) {
        streamMsArg = Math.round(streamRaw);
      }
      const eventsRaw: Object = parsed['max_events'];
      if (typeof eventsRaw === 'number' && Number.isFinite(eventsRaw)) {
        maxEventsArg = Math.round(eventsRaw);
      }
      const asyncRaw: Object = parsed['async'];
      if (typeof asyncRaw === 'boolean') {
        wantAsync = asyncRaw;
      }
      const taskIdRaw: Object = parsed['task_id'];
      if (typeof taskIdRaw === 'string') {
        taskIdArg = taskIdRaw.trim();
      }
      const waitRaw: Object = parsed['wait_ms'];
      if (typeof waitRaw === 'number' && Number.isFinite(waitRaw)) {
        waitMsArg = Math.max(0, Math.round(waitRaw));
      }
      const requestsKey: Object = parsed['requests'];
      if (typeof requestsKey !== 'undefined') {
        requestsRaw = requestsKey;
      }
    } catch (e) {
      return Promise.resolve(JSON.stringify({ error: toolArgsParseErrorText(argsJson) }));
    }
    // 管道互斥闸（在 task_id 查询分流之前——语义冲突先拦、禁静默取先者，P0-1）：requests
    // 与顶层单请求/长任务/流式参数互斥——管道步骤只支持 method、url、headers、body、
    // timeout_ms 五字段（结构校验在 validatePipelineSpec）
    if (typeof requestsRaw !== 'undefined') {
      if (taskIdArg !== '') {
        return Promise.resolve(JSON.stringify({
          error: 'requests 与 task_id 不能同时使用。查询任务传 task_id，编排多请求传 requests' }));
      }
      if (wantAsync) {
        return Promise.resolve(JSON.stringify({
          error: 'requests 与 async 不能同时使用。管道按顺序立即执行，不支持后台发起' }));
      }
      if (streamMsArg > 0 || maxEventsArg > 0 || wantDownload || fileArg !== '' ||
        multipartArg !== null) {
        return Promise.resolve(JSON.stringify({
          error: 'requests 与 download、file、multipart、stream_ms、max_events 不能同时使用。管道步骤只支持 method、url、headers、body、timeout_ms' }));
      }
      // 顶层单请求参数与 requests 同传点名报错——这些参数不作用于管道步骤，静默忽略 =
      // 模型以为生效的鉴权头/请求体无声丢失（P0-1 禁静默降级）
      if (singleOnlyKeys.length > 0) {
        return Promise.resolve(JSON.stringify({
          error: 'requests 与顶层参数 ' + singleOnlyKeys.join('、') +
            ' 不能同时使用。这些参数只作用于单请求调用，管道步骤的参数写在每个步骤项内' }));
      }
      if (url !== '') {
        return Promise.resolve(JSON.stringify({
          error: 'url 与 requests 不能同时使用。单请求传 url，编排多个请求传 requests' }));
      }
      const spec = validatePipelineSpec(requestsRaw);
      if (!spec.ok) {
        return Promise.resolve(JSON.stringify({ error: spec.errorText }));
      }
      return this.executePipeline(spec.steps, ctx);
    }
    // 查询分流（在 URL 校验之前——task_id 查询不要求 url 在场）；async 与 task_id 同传
    // 点名报错（一次调用不能既发起又查询，P0-1 不静默取先者）。查询与单请求/流式/下载参数
    // 同传也点名报错（原实现全部静默忽略 = P0-1 静默降级；wait_ms 豁免 = 查询自带的等待参数）
    if (taskIdArg !== '') {
      if (wantAsync) {
        return Promise.resolve(JSON.stringify({
          error: 'async 与 task_id 不能同时使用。发起新请求传 async，查询已有任务传 task_id' }));
      }
      if (singleOnlyKeys.length > 0) {
        return Promise.resolve(JSON.stringify({
          error: 'task_id 与顶层参数 ' + singleOnlyKeys.join('、') +
            ' 不能同时使用。这些参数只作用于发起新请求，查询任务只认 task_id 与 wait_ms' }));
      }
      if (wantDownload || fileArg !== '' || multipartArg !== null || streamMsArg > 0 ||
        maxEventsArg > 0) {
        return Promise.resolve(JSON.stringify({
          error: 'task_id 与 download、file、multipart、stream_ms、max_events 不能同时使用。这些参数只作用于发起新请求，查询任务只认 task_id 与 wait_ms' }));
      }
      if (url !== '') {
        return Promise.resolve(JSON.stringify({
          error: 'task_id 与 url 不能同时使用。发起新请求传 url，查询已有任务传 task_id' }));
      }
      return this.queryTask(taskIdArg, waitMsArg);
    }
    if (waitMsArg > 0) {
      return Promise.resolve(JSON.stringify({
        error: 'wait_ms 需与 task_id 一起使用，单独传入无效' }));
    }
    // 方法白名单（集外 throw——禁动态查表放行，会击穿写确认红线）与 URL 协议白名单：在
    // 受理分流**之前**——async 受理的应是合法请求，非法参数不当场拦会先占任务表位再后台
    // 失败（同步路 throw 由 executeToolCall 包壳转 error JSON）
    if (!HTTP_REQUEST_METHODS.includes(method)) {
      throw new Error('method 只支持 GET、HEAD、OPTIONS、POST、PUT、DELETE、PATCH');
    }
    if (url === '') {
      throw new Error('url 与 requests 必须提供其一。单请求传 url，编排多个请求传 requests');
    }
    if (!isHttpUrl(url)) {
      throw new Error('仅支持 http 与 https 地址');
    }
    // URL 长度上限：url 键无法被预算回缩，超长会突破 8192 终态预算、被外层 clipToolResult
    // 硬切出坏 JSON——错误回执拦下使终态声明重新成立
    if (url.length > HTTP_URL_MAX_CHARS) {
      return Promise.resolve(JSON.stringify({
        error: 'URL 过长。请缩短 URL 或减少查询参数后重试' }));
    }
    // 互斥闸：窗口读取与 download 互斥（两者都是「正文怎么读」的分流——语义冲突不静默取先者）
    if (streamMsArg > 0 || maxEventsArg > 0) {
      if (wantDownload) {
        return Promise.resolve(JSON.stringify({
          error: 'stream_ms、max_events 与 download 不能同时使用。读事件流传窗口参数，存文件传 download' }));
      }
    }
    const flowArgs: HttpFlowArgs = {
      url: url, method: method, body: body, maxLength: maxLength, startIndex: startIndex,
      timeoutMsArg: timeoutMsArg, wantDownload: wantDownload, fileArg: fileArg,
      multipartArg: multipartArg, headers: headers, streamMsArg: streamMsArg,
      maxEventsArg: maxEventsArg, wantStream: streamMsArg > 0 || maxEventsArg > 0,
      wantBytes: false
    };
    // 异步发起分流（复用 http_request 不新增工具；受理即回、后台跑完整执行链）：登记句柄 →
    // 剥组件闭包的上下文副本（寿命匹配红线——后台任务活过发起轮，不得持有页面组件绑定的
    // isRunActive；取消由 httpAbortRun 掐断链承接，探活闭包对后台任务无语义）→ 不 await 的
    // 执行链（工具轮 Promise 立即结算）
    if (wantAsync) {
      const table: HttpTaskTable = taskTable();
      const taskId: string = util.generateRandomUUID(true);
      const timeoutMs: number = resolveTaskTimeoutMs(flowArgs.timeoutMsArg);
      // 会话维度登记（连带取消按会话查任务，见 httpAbortConversationBackground）
      if (!table.register(taskId, ctx.runId, timeoutMs, Date.now(), ctx.conversationId)) {
        return Promise.resolve(JSON.stringify({
          error: '后台任务已达 ' + HTTP_TASK_MAX_ENTRIES + ' 个上限。请等待既有任务完成后再发起' }));
      }
      setHttpTaskMirror(table.serializeRunning());
      const bgCtx: ToolExecutionContext = {
        scope: ctx.scope, conversationId: ctx.conversationId, runId: ctx.runId,
        attemptId: ctx.attemptId, assistantId: ctx.assistantId,
        memoryScopeAssistantId: ctx.memoryScopeAssistantId,
        knowledgeAssistantId: ctx.knowledgeAssistantId,
        searchResultCount: ctx.searchResultCount,
        isRunActive: (_runId: string): boolean => true,
        // 后台链透传快照 + collectImage 恒 false——后台 flow 不消费工作区图片路
        //（workspace_read 不经 bgCtx 执行），恒 false 是防御位非语义位
        hasVision: ctx.hasVision,
        collectImage: (_mimeType: string, _data: string): boolean => false,
        // 页图缝同款防御位（workspace_read 不经 bgCtx 执行）
        collectPageImage: (_mimeType: string, _data: string): boolean => false,
        // 预检便签：后台链只跑 HTTP 流、不经工具预检→执行信道，恒空串（同上方防御位语义）
        preflightMemo: ''
      };
      executeFlow(flowArgs, bgCtx, taskId)
        .then((flow: HttpFlowOutcome): void => {
          const live: HttpTaskTable = taskTable();
          // 取消归类——掐断链 destroy 后传输层以 cancelled 外传（坑75 家族「判据是状态
          // 字段而非文本哨兵」；缺此分支取消会落 completed + 错误回执）
          if (flow.cancelled) {
            live.finish(taskId, HTTP_TASK_STATUS_CANCELLED, '', '用户取消', Date.now());
          } else {
            live.finish(taskId, flow.timedOut ? HTTP_TASK_STATUS_TIMED_OUT :
              HTTP_TASK_STATUS_COMPLETED, flow.json,
              flow.timedOut ? '任务超时' : '完成', Date.now());
          }
          setHttpTaskMirror(live.serializeRunning());
        })
        .catch((e: Object): void => {
          const live: HttpTaskTable = taskTable();
          live.finish(taskId, HTTP_TASK_STATUS_FAILED, '', toolErrorText(e), Date.now());
          setHttpTaskMirror(live.serializeRunning());
        });
      return Promise.resolve(JSON.stringify({
        taskId: taskId, status: HTTP_TASK_STATUS_RUNNING,
        note: '已受理，请求在后台执行。用 task_id 查询状态与结果，完成后结果保留 10 分钟' }));
    }
    const flow: HttpFlowOutcome = await executeFlow(flowArgs, ctx, '');
    return flow.json;
  }

  // 管道失败回执组装（中途失败 / 取消 / 超总时长共面）：error 带步序与原因 + failedIndex
  // 结构化位 + 已完成步摘要——失败前的成果不丢（模型可从摘要看出已完成的步，重发时可跳过）
  private pipelineFailure(summaries: Record<string, Object>[], stepsTotal: number,
    failedIndex: number, errorText: string): Record<string, Object> {
    const rec: Record<string, Object> = {};
    // errorText 走 clipResultText 收口（上限 HTTP_PIPELINE_FAILURE_ERROR_MAX，单源
    // HttpPipeline）——replaceStepRefs 错误句内嵌模型可控 {{...}} 记号原文（可达数万字符），
    // 原样入 rec 直出会被外层 clipToolResult 8192 硬切成坏 JSON、丢 failedIndex/steps
    // 结构化失败面
    rec['error'] = clipResultText(errorText, HTTP_PIPELINE_FAILURE_ERROR_MAX);
    rec['pipeline'] = true;
    rec['stepsTotal'] = stepsTotal;
    rec['failedIndex'] = failedIndex;
    rec['steps'] = summaries;
    return rec;
  }

  // 步摘要基础五字段（成功步与失败步共面）：URL 与预览两维有界防挤爆 8192 终态预算
  //（fitHttpResult 只回缩 body 键，steps 摘要必须自行收口）
  private stepSummary(index: number, method: string, url: string, status: number,
    fullBody: string): Record<string, Object> {
    const summary: Record<string, Object> = {};
    summary['index'] = index;
    summary['method'] = method;
    summary['url'] = clipResultText(url, HTTP_PIPELINE_STEP_URL_MAX);
    summary['status'] = status;
    summary['bodyPreview'] = clipResultText(fullBody, HTTP_PIPELINE_STEP_PREVIEW_MAX);
    return summary;
  }

  // 管道顺序执行循环：逐请求委托既有执行链走全闸（executeFlow——白名单 / 哨兵 / 限速 /
  // 写方法三档确认 / 审批闸零豁免；写确认已在预检层合并单卡一次覆盖，执行链内不再逐请求
  // 弹卡）；前序响应完整正文入正文表供后续占位符替换；失败即停（error 键或状态码 ≥ 400
  //——后续请求建立在错误响应上无意义）；用户掐断即停；每步结果不进对话（终态 = 最后一步
  // 完整回执 + 各步摘要）；中间步正文超 2000 字符落工作区保全文（落盘失败记进摘要不拦主线）
  private async executePipeline(steps: PipelineStepSpec[],
    ctx: ToolExecutionContext): Promise<string> {
    const startedAt: number = Date.now();
    const bodies: (Object | null)[] = [];
    const summaries: Record<string, Object>[] = [];
    let lastFlow: HttpFlowOutcome | null = null;
    // 管道内存驻留收口：起跑前预扫各步引用（三域），未被引用的步不解析直接落 null（未引用
    // 恒不可达，零语义变化），已引用的步在**最后引用步**替换完成后才弃。refsOf[i] = 第 i 步
    // 引用的步下标集（扫描在 HttpPipeline.collectStepRefs，步号上界过滤）；lastReaderOf[j] =
    // 引用第 j 步的最后引用者下标——释放只认最后引用者（逐引用即弃会让多步复用同一步 token
    // 的编排后续引用步假失败并误报「正文不是合法 JSON」）
    const refsOf: number[][] = [];
    const bodyReferenced: boolean[] = new Array<boolean>(steps.length).fill(false);
    for (let s: number = 0; s < steps.length; s++) {
      const refs: number[] = [];
      collectStepRefs(steps[s].url, refs, steps.length);
      collectStepRefs(steps[s].body, refs, steps.length);
      for (const refKey of Object.keys(steps[s].headers)) {
        collectStepRefs(steps[s].headers[refKey], refs, steps.length);
      }
      refsOf.push(refs);
      for (const refIdx of refs) {
        bodyReferenced[refIdx] = true;
      }
    }
    const lastReaderOf: number[] = lastReaderIndices(refsOf, steps.length);
    for (let i: number = 0; i < steps.length; i++) {
      const step: PipelineStepSpec = steps[i];
      const label: string = '第 ' + (i + 1) + ' 个请求';
      // 步间探活——用户在「上步已完成、下步未起跑」的窗口掐断时无在途请求可被 destroy、
      // flow.cancelled 永不来；不探活则后续步骤照发（写请求发出是不可逆副作用，停止键必须
      // 拦在发送前；探活闭包经执行上下文下发，先例 ToolBrowse 多项循环）。后台路对管道不可
      // 达（async×requests 互斥），ctx 恒为在跑轮真上下文
      if (!ctx.isRunActive(ctx.runId)) {
        return JSON.stringify(this.pipelineFailure(summaries, steps.length, i,
          '管道在' + label + '处被用户停止'));
      }
      // 总时长闸（防一轮工具被无限编排拖死；每步起跑前查，已耗时间含前步传输与落盘）
      if (Date.now() - startedAt > HTTP_PIPELINE_TOTAL_MS_MAX) {
        return JSON.stringify(this.pipelineFailure(summaries, steps.length, i, '管道总时长已超过 ' +
          Math.round(HTTP_PIPELINE_TOTAL_MS_MAX / 1000) + ' 秒上限，在' + label + '处停止'));
      }
      // 步内超时钳到剩余预算——否则闸前起跑的最后一步可在总时长闸之后再跑满一整档，
      // desc/schema 声明的「总时长上限 120 秒」失真（P2-5）。未传档与已传档同钳；钳后经
      // 执行链 5 秒下限托底，残余超出 ≤5 秒
      const remainingMs: number = HTTP_PIPELINE_TOTAL_MS_MAX - (Date.now() - startedAt);
      const stepTimeoutMsArg: number = Math.min(
        step.timeoutMsArg > 0 ? step.timeoutMsArg : HTTP_TIMEOUT_MS_DEFAULT,
        Math.max(remainingMs, 1));
      // 占位符替换（url / 请求头值 / body 三域；失败即停——部分替换的请求发出去是更大的错）
      const urlRep: PipelineReplaceOutcome = replaceStepRefs(step.url, bodies, i);
      if (!urlRep.ok) {
        return JSON.stringify(this.pipelineFailure(summaries, steps.length, i,
          label + '失败：' + urlRep.errorText));
      }
      const stepHeaders: Record<string, string> = {};
      let headerBad: PipelineReplaceOutcome | null = null;
      for (const hKey of Object.keys(step.headers)) {
        const hRep: PipelineReplaceOutcome = replaceStepRefs(step.headers[hKey], bodies, i);
        if (!hRep.ok) {
          headerBad = hRep;
          break;
        }
        stepHeaders[hKey] = hRep.text;
      }
      if (headerBad !== null) {
        return JSON.stringify(this.pipelineFailure(summaries, steps.length, i,
          label + '失败：' + headerBad.errorText));
      }
      const bodyRep: PipelineReplaceOutcome = replaceStepRefs(step.body, bodies, i);
      if (!bodyRep.ok) {
        return JSON.stringify(this.pipelineFailure(summaries, steps.length, i,
          label + '失败：' + bodyRep.errorText));
      }
      // 本步三域替换完成后，被本步引用且本步是**最后引用者**的前序步解析产物即弃（此后无
      // 读取点；仍有后续步要读的位保留），bodies 该位归 null 释放对象图
      for (const refIdx of refsOf[i]) {
        if (lastReaderOf[refIdx] === i) {
          bodies[refIdx] = null;
        }
      }
      // 替换后 URL 重验（scheme 白名单 + 长度闸）——单请求路两闸在 execute() 受理层，管道
      // 路自此处直达执行链，占位符真值可换协议或远长于模板；契约闸前移与单请求路同口径
      //（P0-1 发送前拦；超长 URL 顶穿 8192 预算见 HttpFlow HTTP_URL_MAX_CHARS 注）
      if (!isHttpUrl(urlRep.text)) {
        return JSON.stringify(this.pipelineFailure(summaries, steps.length, i,
          label + '失败：仅支持 http 与 https 地址'));
      }
      if (urlRep.text.length > HTTP_URL_MAX_CHARS) {
        return JSON.stringify(this.pipelineFailure(summaries, steps.length, i,
          label + '失败：URL 过长。请缩短后重试'));
      }
      // 执行链入参组装（管道步骤只支持五字段——分页与下载流式参数均不在面；maxLength 传
      // 缺省档：中间步回执丢弃不消费，fullBody 才是提取面；timeoutMsArg 为剩余预算钳制后
      // 的步内超时，见上方步内钳制注）
      const flowArgs: HttpFlowArgs = {
        url: urlRep.text, method: step.method, body: bodyRep.text,
        maxLength: HTTP_MAX_LENGTH_DEFAULT, startIndex: 0, timeoutMsArg: stepTimeoutMsArg,
        wantDownload: false, fileArg: '', multipartArg: null, headers: stepHeaders,
        streamMsArg: 0, maxEventsArg: 0, wantStream: false, wantBytes: false
      };
      const flow: HttpFlowOutcome = await executeFlow(flowArgs, ctx, '');
      // 用户掐断——管道即停（停止键掐断链，传输层 cancelled 外传；已完成的步照常汇报）
      if (flow.cancelled) {
        return JSON.stringify(this.pipelineFailure(summaries, steps.length, i,
          '管道在' + label + '处被用户停止'));
      }
      // 步结果判定：网络层失败（回执 error 键）或 HTTP 状态 ≥ 400 = 失败即停
      let stepReceipt: Record<string, Object> = {};
      try {
        stepReceipt = JSON.parse(flow.json) as Record<string, Object>;
      } catch (e) {
        // 防御分支：回执恒合法 JSON（executeFlow 各出口恒 JSON.stringify 产物）故当前不可
        // 达；真触发判失败停管道（损坏回执当成功续跑会让后续步骤建立在未知结果上，违背
        // 失败即停），reason 落通用句不让单步异常炸管道
        summaries.push(this.stepSummary(i, step.method, urlRep.text, 0, flow.fullBody));
        return JSON.stringify(this.pipelineFailure(summaries, steps.length, i,
          label + '失败：步骤回执解析失败，无法确认结果'));
      }
      const statusVal: Object = stepReceipt['status'];
      const statusNum: number = typeof statusVal === 'number' ? statusVal : 0;
      const errVal: Object = stepReceipt['error'];
      const hasError: boolean = typeof errVal === 'string';
      if (hasError || statusNum >= 400) {
        const reason: string = hasError ? errVal as string : 'HTTP 状态码 ' + statusNum;
        // 失败步摘要同进 steps（与已完成步同形态）——4xx/5xx body 里的「为什么」随
        // bodyPreview 可自愈，失败原因不再只剩状态码
        summaries.push(this.stepSummary(i, step.method, urlRep.text, statusNum, flow.fullBody));
        return JSON.stringify(this.pipelineFailure(summaries, steps.length, i,
          label + '失败：' + reason));
      }
      // 正文表登记（占位符提取数据面）：完整正文 JSON.parse——非合法 JSON 存 null、后续
      // 引用时报「不是合法 JSON」（P0-1 禁静默替换空串）；未被任何步引用的步不解析落 null
      //（零开销零驻留），最后一步天然不解析
      let parsedBody: Object | null = null;
      if (bodyReferenced[i] && flow.fullBody !== '') {
        try {
          parsedBody = JSON.parse(flow.fullBody) as Object;
        } catch (e) {
          parsedBody = null;
        }
      }
      bodies.push(parsedBody);
      // 中间步摘要（每步结果不进对话只回摘要；有界收口见 stepSummary 注）
      const summary: Record<string, Object> = this.stepSummary(i, step.method, urlRep.text,
        statusNum, flow.fullBody);
      // 中间步溢出落盘（复用下载链保全文，source='download' 产物区同口径；最后一步正文
      // 走终态回执不重复落盘）。落盘失败记进摘要不拦管道主线
      if (i < steps.length - 1 && flow.fullBody.length > HTTP_PIPELINE_STEP_SAVE_CHARS) {
        try {
          const encoder: util.TextEncoder = new util.TextEncoder();
          // 单参 encodeInto 的 d.ts 只承诺返回 Uint8Array 视图、无「视图恰占满底层 buffer」
          // 契约——slice 出精确副本，落盘内容与 size 记账（HttpBinary 按 byteLength 记）
          // 不依赖实现细节（.buffer 直取在视图带偏移/预留时会垃圾字节 + size 双失真）
          const encoded: Uint8Array = encoder.encodeInto(flow.fullBody);
          const bytes: ArrayBuffer = (encoded.buffer as ArrayBuffer).slice(encoded.byteOffset,
            encoded.byteOffset + encoded.byteLength);
          const ctVal: Object = stepReceipt['contentType'];
          const contentType: string = typeof ctVal === 'string' && ctVal !== '' ? ctVal :
            'application/json';
          const saved = await saveDownloadToWorkspace(bytes, urlRep.text, contentType,
            ctx.conversationId, ctx.assistantId);
          if (saved.ok) {
            summary['savedFile'] = saved.name;
          } else {
            summary['saveError'] = saved.errorText;
          }
        } catch (e) {
          summary['saveError'] = toolErrorText(e);
        }
      }
      summaries.push(summary);
      lastFlow = flow;
    }
    // 终态组装 = 最后一步完整回执 + pipeline 标记 + 各步摘要（摘要含最后一步自身——push
    // 在循环尾无条件执行，单步管道 steps 恰一个元素）；fitHttpResult 兜底 8192 预算（body
    // 键为回缩量，非文本终态兜空串保通道可用，见 HttpReceipt 头注释）
    let final: Record<string, Object> = {};
    try {
      final = JSON.parse((lastFlow as HttpFlowOutcome).json) as Record<string, Object>;
    } catch (e) {
      final = {};
    }
    final['pipeline'] = true;
    final['stepsTotal'] = steps.length;
    final['steps'] = summaries;
    if (typeof final['body'] !== 'string') {
      final['body'] = '';
    }
    return fitHttpResult(final, 0);
  }

  // 取结果：wait_ms = 0 非阻塞快照；> 0 有界等待（200ms 轮询，条件满足立即返回，到时返回
  // running 快照——到时不是错误）。终态 completed 原样回当初完整回执（后台链存的同步执行
  // 链产物，预算已收敛）
  private async queryTask(taskId: string, waitMsArg: number): Promise<string> {
    const table: HttpTaskTable = taskTable();
    const waitMs: number = Math.min(Math.max(waitMsArg, 0), HTTP_TASK_WAIT_MS_MAX);
    const deadline: number = Date.now() + waitMs;
    for (;;) {
      const now: number = Date.now();
      const rec: HttpTaskRecord | undefined = table.snapshot(taskId, now);
      if (rec === undefined) {
        return JSON.stringify({
          error: '任务不存在或已过期。完成后结果保留 10 分钟，应用重启后未完成任务标记为 lost' });
      }
      if (rec.status !== HTTP_TASK_STATUS_RUNNING) {
        return this.taskReceipt(taskId, rec);
      }
      if (now >= deadline) {
        return this.taskReceipt(taskId, rec);
      }
      await new Promise<void>((resolve: () => void) => {
        setTimeout(resolve, 200);
      });
    }
  }

  // 任务状态回执（终态 / running 快照共组装点）：completed 原样回当初完整回执；其余状态
  // 回结构化状态面（lost 语义见 HttpTaskTable 文件头）
  private taskReceipt(taskId: string, rec: HttpTaskRecord): string {
    if (rec.status === HTTP_TASK_STATUS_COMPLETED && rec.resultJson !== '') {
      return rec.resultJson;
    }
    const rec2: Record<string, Object> = {};
    rec2['taskId'] = taskId;
    rec2['status'] = rec.status;
    if (rec.status === HTTP_TASK_STATUS_RUNNING) {
      rec2['elapsedMs'] = Math.max(0, Date.now() - rec.startedAtMs);
      rec2['note'] = '任务仍在后台运行。可带 wait_ms 有界等待，或稍后再查';
    } else {
      rec2['error'] = rec.status === HTTP_TASK_STATUS_LOST ?
        '应用重启导致任务中断，结果不可用。请重新发起请求' :
        (rec.status === HTTP_TASK_STATUS_TIMED_OUT ? '任务超时，已停止' :
          (rec.status === HTTP_TASK_STATUS_CANCELLED ? '任务已被用户停止' :
            '任务执行失败：' + rec.endReason));
    }
    return JSON.stringify(rec2);
  }
}
