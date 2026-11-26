// HTTP 工具域·请求管道纯函数域。职责一句话 = 「管道入参结构单源：规格校验 + 跨步占位符
// 提取替换的纯计算」。零 import（坑50 域件零依赖可直跑，全部导出供 assert-tool-domain
// 直跑副本执行级验证；HTTP_REQUEST_METHODS 自 ToolHttp 迁址本件 = 步骤 method 校验判据
// 随结构单源走，ToolHttp 以 re-export 保持存量消费方零改动）。
// · 语法定案：模型单次调用传 requests 数组、第一版纯顺序执行、不可存模板；字段提取 =
//   简化点路径（如 body.data.token 或 body.items.0.id——数字段 = 数组索引；零依赖纯
//   函数，非 JSONPath 子集）。占位符形态 {{步骤下标.点路径}}（如 {{0.body.data.token}}），
//   可出现在后续步骤的 url / 请求头值 / body 三个字符串域；首段非数字的 {{...}} 不属
//   管道语法（凭据 {{名称}} 记号同框共存——替换时原样保留，两语法互不侵犯）。
// · 上限定案：步数 8 / 管道总时长 120 秒（防一轮工具被无限编排拖死）；每步超时由执行链
//   按 timeout_ms 口径钳制，本件不管。
// · 中间步溢出落盘阈（照「大结果落工作区」口径复用下载链）：中间步响应正文超 2000 字符
//   落工作区保全文，终态摘要给 200 字符预览 + savedFile 路径；不超阈零落盘。落盘动作在
//   执行器循环（await I/O），本件只出常量。
// · 跨步提取的数据面：每步响应的完整文本正文（HttpFlowOutcome.fullBody）JSON.parse 后
//   存入步骤正文表——占位符基于完整正文提取，与回执分页（max_length 截断）无关；正文
//   非合法 JSON 的步骤不可被引用（引用即中文报错，禁静默替换空串——P0-1）。

// 方法全集（7 种 = schema enum 同源）——集外方法在 validatePipelineSpec 即拦、不进执行
// 链；集外静默放行会击穿写确认红线，禁 http.RequestMethod[名字] 动态查表
export const HTTP_REQUEST_METHODS: string[] = ['GET', 'HEAD', 'OPTIONS', 'POST', 'PUT',
  'DELETE', 'PATCH'];

// 管道步数上限：编排场景现实量级是个位数，8 已覆盖；意义 = 防一轮工具被无限编排拖死
export const HTTP_PIPELINE_MAX_STEPS: number = 8;
// 管道总时长上限：每步超时各自由 timeout_ms 钳（默认 30 秒档），本闸是整条管道硬兜底
//——最坏 8 步 × 大超时远超单请求轮的等待预期，120 秒封顶
export const HTTP_PIPELINE_TOTAL_MS_MAX: number = 120000;
// 中间步正文溢落盘阈（字符）：超阈落工作区保全文，终态给预览 + 路径
export const HTTP_PIPELINE_STEP_SAVE_CHARS: number = 2000;
// 中间步正文预览长度（字符）：8 步摘要合计 + 最后一步完整回执仍在 8192 终态预算内
//（fitHttpResult 只回缩 body 键，steps 摘要必须自行有界）
export const HTTP_PIPELINE_STEP_PREVIEW_MAX: number = 200;
// 摘要与失败回执内步骤 URL 的截断位（字符）：替换后的 URL 可能极长，不截则一个 URL
// 独自把 8192 终态预算顶穿
export const HTTP_PIPELINE_STEP_URL_MAX: number = 200;
// 步骤项禁键（顶层专属参数）：出现在步骤项即点名报错——静默忽略会让 download: true
// 之类请求被无声降级
export const HTTP_PIPELINE_STEP_FORBIDDEN_KEYS: string[] = ['download', 'file', 'multipart',
  'stream_ms', 'max_events', 'async', 'task_id', 'wait_ms', 'max_length', 'start_index'];
// 管道失败回执 error 字段截断位（字符）：失败回执不走 fitHttpResult（无 body 键可回缩），
// error 内嵌模型可控 {{...}} 记号原文（受入参总闸 100000 约束），不封则一个巨型占位符
// 即可顶穿 8192 终态预算、被外层 clipToolResult 硬切成坏 JSON；2000 + 8 步摘要（各截断
// 有界）合计仍在 8192 内且留转义膨胀余量
export const HTTP_PIPELINE_FAILURE_ERROR_MAX: number = 2000;

// 点路径提取结果（ok = value 可用；!ok = errorText 中文原因）
export interface PipelineExtractOutcome {
  ok: boolean;
  value: string;
  errorText: string;
}

// 点路径提取（简化点路径，非 JSONPath 子集）：path = 点分段（键名段或非负整数索引段），
// root = 某步响应正文 JSON.parse 产物；空路径 = 根本身。四类失败形态：非法路径形态（空
// 段）/ 越界索引 / 类型不符（对数组段取键名、对对象段取索引、中间段落在标量上）/ 空值
//（末端 null）。提取值字符串化收口：string 原样、number 与 boolean → String()；
// object / array 拒绝——串接进 URL 或请求头只会产出 [object Object] 垃圾，模型须改引用
// 叶子字段（P0-1 禁静默产出坏值）
export function extractByPath(root: Object, path: string): PipelineExtractOutcome {
  let cursor: Object = root;
  if (path !== '') {
    const segments: string[] = path.split('.');
    for (let s: number = 0; s < segments.length; s++) {
      const seg: string = segments[s];
      if (seg === '') {
        return { ok: false, value: '', errorText: '路径含空段（连续点号或首尾点号）' };
      }
      if (Array.isArray(cursor)) {
        const arr = cursor as Object[];
        if (!/^\d+$/.test(seg)) {
          return { ok: false, value: '', errorText: '路径段「' + seg + '」位于数组上，必须是数字索引' };
        }
        const idx: number = parseInt(seg, 10);
        if (idx >= arr.length) {
          return { ok: false, value: '', errorText: '数组索引 ' + idx + ' 越界，该数组长度 ' +
            arr.length };
        }
        cursor = arr[idx];
      } else if (typeof cursor === 'object' && cursor !== null) {
        const rec = cursor as Record<string, Object>;
        // JSON.parse 产物无原型链值，undefined 判缺失安全（JSON 无 undefined 值形态）
        const next: Object | undefined = rec[seg];
        if (typeof next === 'undefined') {
          return { ok: false, value: '', errorText: '对象没有字段「' + seg + '」' };
        }
        cursor = next;
      } else {
        return { ok: false, value: '', errorText: '路径段「' + seg + '」的上游值不是对象或数组，无法继续取' };
      }
    }
  }
  if (cursor === null || typeof cursor === 'undefined') {
    return { ok: false, value: '', errorText: '字段值为 null，无可提取内容' };
  }
  const kind: string = typeof cursor;
  if (kind === 'string') {
    return { ok: true, value: cursor as string, errorText: '' };
  }
  if (kind === 'number' || kind === 'boolean') {
    return { ok: true, value: String(cursor), errorText: '' };
  }
  return { ok: false, value: '', errorText: '字段值是' + (Array.isArray(cursor) ? '数组' : '对象') +
    '，只能提取字符串、数字或布尔值' };
}

// 占位符替换结果（ok = text 可用；!ok = errorText 中文原因，调用方组装「第 N 步」上下文）
export interface PipelineReplaceOutcome {
  ok: boolean;
  text: string;
  errorText: string;
}

// 占位符替换（纯函数，直跑断言）：扫描 text 中 {{N.path}} 形态占位符（N = 步骤下标），
// 逐个经 extractByPath 提取并替换。bodies[i] = 第 i 步响应正文的 JSON.parse 产物或 null
//（该步正文非合法 JSON）。判序：首段非纯数字 = 凭据 {{名称}} 记号 → 原样保留；无闭合
// '{{' → 余下原文保留（孤 '{{' 可合法存在）；N ≥ currentStep → 前向引用报错（纯顺序
// 执行，未来步无结果）；bodies[N] === null → 报错点名哪步不可引用；提取失败 → 原因
// 透传。任一占位符失败即整串失败——部分替换的请求发出去才是更大的错（P0-1）
export function replaceStepRefs(text: string, bodies: (Object | null)[],
  currentStep: number): PipelineReplaceOutcome {
  let out: string = '';
  let i: number = 0;
  while (i < text.length) {
    const open: number = text.indexOf('{{', i);
    if (open < 0) {
      out += text.substring(i);
      break;
    }
    const close: number = text.indexOf('}}', open + 2);
    if (close < 0) {
      out += text.substring(i);
      break;
    }
    const inner: string = text.substring(open + 2, close);
    const firstDot: number = inner.indexOf('.');
    const stepText: string = firstDot < 0 ? inner : inner.substring(0, firstDot);
    if (!/^\d+$/.test(stepText)) {
      out += text.substring(i, close + 2);
      i = close + 2;
      continue;
    }
    const stepIndex: number = parseInt(stepText, 10);
    if (stepIndex >= currentStep) {
      return { ok: false, text: '', errorText: '占位符 {{' + inner + '}} 的步骤下标越界，只能引用之前的步骤（0 起）' };
    }
    if (stepIndex >= bodies.length) {
      return { ok: false, text: '', errorText: '占位符 {{' + inner + '}} 引用的第 ' + stepIndex +
        ' 步响应正文不是合法 JSON，无法提取字段' };
    }
    const stepBody: Object | null = bodies[stepIndex];
    if (stepBody === null) {
      return { ok: false, text: '', errorText: '占位符 {{' + inner + '}} 引用的第 ' + stepIndex +
        ' 步响应正文不是合法 JSON，无法提取字段' };
    }
    const path: string = firstDot < 0 ? '' : inner.substring(firstDot + 1);
    const extract: PipelineExtractOutcome = extractByPath(stepBody, path);
    if (!extract.ok) {
      return { ok: false, text: '', errorText: '占位符 {{' + inner + '}} 提取失败：' + extract.errorText };
    }
    out += text.substring(i, open) + extract.value;
    i = close + 2;
  }
  return { ok: true, text: out, errorText: '' };
}

// 步号引用扫描（执行器起跑前预扫，纯函数可直跑）：把 text 中 {{N.path}} 的 N 收进 refs
//（去重）；扫描语义镜像 replaceStepRefs 的开闭配对（凭据记号不收，两语法互不侵犯）。
// ★ stepCount 上界过滤：无界巨型步号（{{99999.x}} 类记号）不收集——refs 值域被步数上限
// 封死，includes 去重的线性扫恒短，对抗性万级占位符下预扫保持线性、不退化 O(N²) 跑 UI 线程
export function collectStepRefs(text: string, refs: number[], stepCount: number): void {
  let idx: number = 0;
  while (idx < text.length) {
    const open: number = text.indexOf('{{', idx);
    if (open < 0) {
      return;
    }
    const close: number = text.indexOf('}}', open + 2);
    if (close < 0) {
      return;
    }
    const inner: string = text.substring(open + 2, close);
    const firstDot: number = inner.indexOf('.');
    const stepText: string = firstDot < 0 ? inner : inner.substring(0, firstDot);
    if (/^\d+$/.test(stepText)) {
      const stepIndex: number = parseInt(stepText, 10);
      if (stepIndex >= 0 && stepIndex < stepCount && !refs.includes(stepIndex)) {
        refs.push(stepIndex);
      }
    }
    idx = close + 2;
  }
}

// 最后引用者表（执行器内存收口的释放判序，纯函数可直跑）：lastReaderOf[j] = 引用第 j 步
// 的最大步下标（-1 = 无人引用）。只弃「最后引用者替换完成后」的位——若每个引用步替换完
// 即弃，多步复用同一步（登录 → 列表 → 详情 token 形态）的后续引用步会假失败且误报
//「响应正文不是合法 JSON」（错误归因相反：正文合法，被内存优化过早丢弃）
export function lastReaderIndices(refsOf: number[][], stepCount: number): number[] {
  const lastReaderOf: number[] = new Array<number>(stepCount).fill(-1);
  for (let s: number = 0; s < refsOf.length; s++) {
    const refs: number[] = refsOf[s];
    for (const refIdx of refs) {
      if (refIdx >= 0 && refIdx < stepCount) {
        lastReaderOf[refIdx] = s;
      }
    }
  }
  return lastReaderOf;
}

// 管道步骤规格（validatePipelineSpec 产物；timeoutMsArg = 0 未传，执行链钳制落默认档）
export interface PipelineStepSpec {
  method: string;
  url: string;
  headers: Record<string, string>;
  body: string;
  timeoutMsArg: number;
}

// 规格校验结果（ok = steps 可用；!ok = errorText 中文原因）
export interface PipelineSpecOutcome {
  ok: boolean;
  errorText: string;
  steps: PipelineStepSpec[];
}

// 管道规格校验（纯函数，直跑断言）：requests 数组逐项结构校验——数组形态 / 非空 / 步数
// 上限 / 每项对象 / 禁键 / url 必填 / method 归一白名单（缺省 GET）/ headers 值全字符串
//（非串点名报错，不 String() 收编不静默丢弃）/ body 字符串 / timeout_ms 有限数字。错误
// 信息恒带「第 N 个请求」定位（「中途失败给出第几个失败」在校验层同样成立）。互斥闸
//（requests × 顶层单请求参数）与 method 白名单的执行链兜底在执行器，本件只管数组内结构
export function validatePipelineSpec(raw: Object): PipelineSpecOutcome {
  if (!Array.isArray(raw)) {
    return { ok: false, errorText: 'requests 必须是请求数组', steps: [] };
  }
  const items: Object[] = raw as Object[];
  if (items.length === 0) {
    return { ok: false, errorText: 'requests 不能为空数组', steps: [] };
  }
  if (items.length > HTTP_PIPELINE_MAX_STEPS) {
    return { ok: false, errorText: 'requests 最多 ' + HTTP_PIPELINE_MAX_STEPS + ' 个请求，收到 ' +
      items.length + ' 个', steps: [] };
  }
  const steps: PipelineStepSpec[] = [];
  for (let i: number = 0; i < items.length; i++) {
    const item: Object = items[i];
    const label: string = '第 ' + (i + 1) + ' 个请求';
    if (typeof item !== 'object' || item === null || Array.isArray(item)) {
      return { ok: false, errorText: label + '必须是对象', steps: [] };
    }
    const rec = item as Record<string, Object>;
    for (const key of HTTP_PIPELINE_STEP_FORBIDDEN_KEYS) {
      if (typeof rec[key] !== 'undefined') {
        return { ok: false, errorText: label + '不支持 ' + key + ' 参数。该参数只在单请求调用可用', steps: [] };
      }
    }
    const urlRaw: Object = rec['url'];
    if (typeof urlRaw !== 'string' || urlRaw.trim() === '') {
      return { ok: false, errorText: label + '缺少 url，或 url 不是非空字符串', steps: [] };
    }
    let method: string = 'GET';
    const methodRaw: Object = rec['method'];
    if (typeof methodRaw === 'string' && methodRaw.trim() !== '') {
      method = methodRaw.trim().toUpperCase();
    } else if (typeof methodRaw !== 'undefined') {
      return { ok: false, errorText: label + '的 method 必须是字符串', steps: [] };
    }
    if (!HTTP_REQUEST_METHODS.includes(method)) {
      return { ok: false, errorText: label + '的 method 只支持 GET、HEAD、OPTIONS、POST、PUT、DELETE、PATCH', steps: [] };
    }
    const headers: Record<string, string> = {};
    const headersRaw: Object = rec['headers'];
    if (typeof headersRaw === 'object' && headersRaw !== null && !Array.isArray(headersRaw)) {
      const hRec = headersRaw as Record<string, Object>;
      for (const hKey of Object.keys(hRec)) {
        const v: Object = hRec[hKey];
        if (typeof v !== 'string') {
          return { ok: false, errorText: label + '的请求头 ' + hKey + ' 的值必须是字符串', steps: [] };
        }
        headers[hKey] = v;
      }
    } else if (typeof headersRaw !== 'undefined') {
      return { ok: false, errorText: label + '的 headers 必须是对象', steps: [] };
    }
    let body: string = '';
    const bodyRaw: Object = rec['body'];
    if (typeof bodyRaw === 'string') {
      body = bodyRaw;
    } else if (typeof bodyRaw !== 'undefined') {
      return { ok: false, errorText: label + '的 body 必须是字符串', steps: [] };
    }
    let timeoutMsArg: number = 0;
    const timeoutRaw: Object = rec['timeout_ms'];
    if (typeof timeoutRaw === 'number' && Number.isFinite(timeoutRaw)) {
      timeoutMsArg = Math.round(timeoutRaw);
    } else if (typeof timeoutRaw !== 'undefined') {
      return { ok: false, errorText: label + '的 timeout_ms 必须是数字', steps: [] };
    }
    steps.push({ method: method, url: urlRaw.trim(), headers: headers, body: body,
      timeoutMsArg: timeoutMsArg });
  }
  return { ok: true, errorText: '', steps: steps };
}
