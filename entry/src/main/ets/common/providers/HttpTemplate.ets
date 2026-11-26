// HTTP 请求模板域件：用户把常用接口存成有名字的「请求模板」，模型看到的是一组带参数说明
// 的命名工具（slug 注册），填参即调用、不自己拼 URL。四层分工：
// · 纯函数区（文件上半部，**零 import 依赖**，本区禁引用任何 import 绑定——断言副本剥
//   import 后整体直跑）：占位渲染 / 请求组装 / schema 与 desc 生成 / cURL 导入解析 /
//   OpenAPI 摘要解析 / 模板输入校验；
// · 动态注册区：syncTemplateTools 把模板增删改落到注册表（增 = register、删 = unregister
//   ——ToolRegistry 该枚的唯一消费方）；定案①模板工具随 http_request 同进退（modeDriven
//   + 声明追加点在 ChatContextUsage.collectTools）；
// · 执行器 TemplateExecutor：按 slug **现查**模板行（改名/改参即时生效）→ 组装最终请求 →
//   **直接调用 HttpRequestExecutor.execute**（定案⑤：与手写请求同一条执行通道，白名单 /
//   哨兵 / 限速 / 写方法三档确认全闸自动继承，模板层零第二真相）；
// · 预检 templatePreflight：组装后委托 httpRequestNeedsConfirm（写方法确认卡与结构化预览
//   同源）；全包 try/catch 恒不抛（ToolEntry.preflight 契约）——★ H3-5 起 fail-closed，
//   分阶段细则见 templatePreflightFor 头注释。
// 定案③命名两分离：显示名（title，可中文）与注册名 = slug = tpl_<自增 id>（恒定，改名不
// 改 slug、不注销重注册——HttpTemplateDb.insertHttpTemplate 落地）；desc 写显示名。
import { ToolEntry, ToolExecutor, ConfirmPrompt, toolArgsParseErrorText } from './ToolContracts';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { HTTP_WRITE_METHODS, writeConfirmFallbackPrompt } from './HttpPreflight';
import { HttpRequestExecutor, httpRequestNeedsConfirm } from './ToolHttp';
import { TOOL_GROUP_HTTP, toolRegistry } from './ToolTypes';
import { HttpTemplateInput, HttpTemplateRow, queryHttpTemplateById,
  queryHttpTemplates } from '../store/HttpTemplateDb';

// ═══ 纯函数区（零 import 依赖——断言直跑；本区禁引用任何 import 绑定）═══

// 参数位置四值（方案档笔6：Body / Path / Query / Header）
export const TEMPLATE_PARAM_POSITIONS: string[] = ['path', 'query', 'body', 'header'];

// 参数定义（params_json 数组元素）
export interface TemplateParam {
  name: string;
  position: string;
  desc: string;
  required: boolean;
}

// 请求头模板定义（headers_json 数组元素；value 可含 {参数} 占位与 {{凭据}} 引用记号）
export interface TemplateHeader {
  name: string;
  value: string;
}

// 组装产物（ok = false 时仅 error 有义；method 原样透传——白名单闸在下游执行器单源）
export interface TemplateAssembled {
  ok: boolean;
  error: string;
  method: string;
  url: string;
  headers: Record<string, string>;
  body: string;
}

// 位置中文名（模型面 schema description、用户面校验文案与重发编辑对话框三方共用单源，
// 禁第二份映射）
export function positionLabel(position: string): string {
  if (position === 'path') {
    return '路径段';
  }
  if (position === 'query') {
    return '查询参数';
  }
  if (position === 'body') {
    return '请求体';
  }
  return '请求头';
}

// 参数定义解析（params_json → 数组；非法 / 非数组 / 项内缺字段容错跳过。合法形态以
// validateTemplateInput 在保存侧把关，本函数对脏库数据防御性降级）
export function parseTemplateParams(paramsJson: string): TemplateParam[] {
  const out: TemplateParam[] = [];
  if (paramsJson === '') {
    return out;
  }
  let raw: object[] | null = null;
  try {
    const parsed: object = JSON.parse(paramsJson);
    raw = Array.isArray(parsed) ? parsed as object[] : null;
  } catch (e) {
    return out;
  }
  if (raw === null) {
    return out;
  }
  for (const item of raw) {
    const rec = item as Record<string, Object>;
    const name: Object = rec['name'];
    const position: Object = rec['position'];
    if (typeof name !== 'string' || typeof position !== 'string') {
      continue;
    }
    const descRaw: Object = rec['desc'];
    out.push({
      name: name,
      position: position,
      desc: typeof descRaw === 'string' ? descRaw : '',
      required: rec['required'] === true
    });
  }
  return out;
}

// 请求头模板解析（headers_json → 数组；容错同上）
export function parseTemplateHeaders(headersJson: string): TemplateHeader[] {
  const out: TemplateHeader[] = [];
  if (headersJson === '') {
    return out;
  }
  let raw: object[] | null = null;
  try {
    const parsed: object = JSON.parse(headersJson);
    raw = Array.isArray(parsed) ? parsed as object[] : null;
  } catch (e) {
    return out;
  }
  if (raw === null) {
    return out;
  }
  for (const item of raw) {
    const rec = item as Record<string, Object>;
    const name: Object = rec['name'];
    const value: Object = rec['value'];
    if (typeof name === 'string' && typeof value === 'string') {
      out.push({ name: name, value: value });
    }
  }
  return out;
}

// 占位 token 全量提取（{name} 形态；name 限字母数字下划线——与模型面 schema 一致）。
// ★ {{名称}} 双花括号 = 凭据引用记号（语法与注入链单源在 HttpCredentials / HttpFlow，
// 合法 sink = 头值与 URL query 位），不属参数占位——交替正则优先吃掉双花括号形态后丢弃，
// 防内层 {名称} 被误当占位参数化（头值写 {{mytoken}} 若被参数化，渲染会把记号破坏成
// {真值}，注入链按 {{ 字面扫描必失配，凭据永不可注入）。宽字符凭据名（中文等，只禁花括号）
// 在本正则两分支均不命中 = 本域天然豁免原样保留；头值位不经 URL 转义恒闭环，query 位
// 依赖 HttpFlow 转义层 {{…}} 记号段豁免分支成立（见其转义段注释）
function placeholderTokens(text: string): string[] {
  const all: string[] = text.match(/\{\{[a-zA-Z0-9_]+\}\}|\{[a-zA-Z0-9_]+\}/g) ?? [];
  const tokens: string[] = [];
  for (const token of all) {
    if (!token.startsWith('{{')) {
      tokens.push(token);
    }
  }
  return tokens;
}

// 占位名集合（去重）
export function placeholderNames(text: string): string[] {
  const names: string[] = [];
  for (const token of placeholderTokens(text)) {
    const name: string = token.substring(1, token.length - 1);
    if (!names.includes(name)) {
      names.push(name);
    }
  }
  return names;
}

// 模板文本渲染：把 text 中「允许集内的 {name}」替换为对应值；未提供值的占位替换为空串
//（非必填参数缺省语义）。必填判定在组装入口已挡，本函数不做
function renderTemplateText(text: string, values: Record<string, string>,
  allowed: string[]): string {
  let out: string = text;
  for (const token of placeholderTokens(text)) {
    const name: string = token.substring(1, token.length - 1);
    if (!allowed.includes(name)) {
      continue; // 错位占位不替换（保存侧 validateTemplateInput 挡，执行时宽容留原样）
    }
    const value: string | undefined = values[name];
    out = out.split(token).join(value !== undefined ? value : '');
  }
  return out;
}

// query 参数值编码（{{名称}} 记号段豁免编码）：值内 {{…}} 段原样保留——整值编码会把记号
// 编成 %7B%7B，注入链按 {{ 字面扫描必失配，凭据引用静默失效；其余字符段照常编码，「字面
// 值即参数值」主语义不变。豁免段配对切分与 extractCredRefs 的 indexOf 扫描同构，不引入第
// 二套解析；替换后的真值由 HttpFlow 的 resolveQueryCred 编码闭环。无 {{ 的值单次直通零开销
function encodeQueryValue(v: string): string {
  if (!v.includes('{{')) {
    return encodeURIComponent(v);
  }
  let out: string = '';
  let idx: number = 0;
  while (true) {
    const open: number = v.indexOf('{{', idx);
    if (open < 0) {
      out += encodeURIComponent(v.substring(idx));
      break;
    }
    const close: number = v.indexOf('}}', open + 2);
    if (close < 0) {
      out += encodeURIComponent(v.substring(idx));
      break;
    }
    out += encodeURIComponent(v.substring(idx, open)) + v.substring(open, close + 2);
    idx = close + 2;
  }
  return out;
}

// 模板请求组装（纯函数）：params 定义驱动四位置替换——
// · path：URL 模板中 {name} 原样替换（值是否需要编码由模板作者决定；整体非 ASCII 由
//   下游 http_request 执行器的 encodeURI 兜底）；
// · query：不在 URL 模板写占位，由本函数按 encodeURIComponent 追加（值含 &/=/空格不破坏
//   参数结构，与凭据 query 注入同语义；值内 {{名称}} 凭据记号段豁免编码见 encodeQueryValue）；
// · body：body 模板中 {name} 原样替换（JSON 正文请把占位放在引号内，模板作者责任）；
// · header：headers_json 值中 {name} 原样替换。
// 错位占位不替换（保存侧校验挡）；必填参数缺失 = 拦下给中文错误（点名缺的参数）；多余
// 的模型入参忽略。values 键值均须字符串（非串值跳过——schema 已限 string）。
export function assembleTemplateRequest(method: string, urlTemplate: string,
  headersJson: string, bodyTemplate: string, paramsJson: string,
  values: Record<string, string>): TemplateAssembled {
  const params: TemplateParam[] = parseTemplateParams(paramsJson);
  const headers: TemplateHeader[] = parseTemplateHeaders(headersJson);
  const cleanValues: Record<string, string> = {};
  for (const key of Object.keys(values)) {
    const v: Object = values[key];
    if (typeof v === 'string') {
      cleanValues[key] = v;
    }
  }
  // ① 必填缺失拦下（一次点名全部——模型一轮补齐，省往返）
  const missing: string[] = [];
  for (const p of params) {
    if (p.required && cleanValues[p.name] === undefined) {
      missing.push(p.name);
    }
  }
  if (missing.length > 0) {
    const outcome: TemplateAssembled = {
      ok: false, error: '缺少必填参数 ' + missing.join('、') + '。请提供后重试',
      method: method, url: '', headers: {}, body: ''
    };
    return outcome;
  }
  // ② path：URL 模板渲染（仅 path 位置参数可替换）
  const pathNames: string[] = params.filter((p: TemplateParam): boolean => p.position === 'path')
    .map((p: TemplateParam): string => p.name);
  let url: string = renderTemplateText(urlTemplate, cleanValues, pathNames);
  // ③ query：按定义追加（encodeURIComponent 保「字面值即参数值」语义）。可省参数未提供
  // 或空串都跳过——「按空处理」的落点是 URL 上不出现 lang= 这类空参数
  const queryPairs: string[] = [];
  for (const p of params) {
    if (p.position !== 'query') {
      continue;
    }
    const v: string | undefined = cleanValues[p.name];
    if (v === undefined || v === '') {
      continue;
    }
    queryPairs.push(p.name + '=' + encodeQueryValue(v));
  }
  if (queryPairs.length > 0) {
    url = url + (url.includes('?') ? '&' : '?') + queryPairs.join('&');
  }
  // ④ header：值渲染（仅 header 位置参数可替换）
  const headerNames: string[] =
    params.filter((p: TemplateParam): boolean => p.position === 'header')
      .map((p: TemplateParam): string => p.name);
  const outHeaders: Record<string, string> = {};
  for (const h of headers) {
    outHeaders[h.name] = renderTemplateText(h.value, cleanValues, headerNames);
  }
  // ⑤ body：模板渲染（仅 body 位置参数可替换）
  const bodyNames: string[] = params.filter((p: TemplateParam): boolean => p.position === 'body')
    .map((p: TemplateParam): string => p.name);
  const body: string = bodyTemplate !== '' ?
    renderTemplateText(bodyTemplate, cleanValues, bodyNames) : '';
  const done: TemplateAssembled = {
    ok: true, error: '', method: method, url: url, headers: outHeaders, body: body
  };
  return done;
}

// 位置中文说明拼进参数描述（模型面 schema 的 description；零 import 纯函数）
function paramSchemaDescription(p: TemplateParam): string {
  const base: string = p.desc !== '' ? p.desc : '参数 ' + p.name;
  return base + '。位置：' + positionLabel(p.position) + '。' +
    (p.required ? '必填。' : '可省略，省略时按空处理。');
}

// 模型面 schema 生成（纯函数；零参数模板 = 空 object，防 provider 校验空参缺 type）
export function buildTemplateSchema(paramsJson: string): string {
  const params: TemplateParam[] = parseTemplateParams(paramsJson);
  if (params.length === 0) {
    return '{"type":"object","properties":{}}';
  }
  let props: string = '';
  const required: string[] = [];
  for (const p of params) {
    if (props !== '') {
      props += ',';
    }
    props += '"' + JSON.stringify(p.name).substring(1, JSON.stringify(p.name).length - 1) +
      '":{"type":"string","description":"' +
      JSON.stringify(paramSchemaDescription(p))
        .substring(1, JSON.stringify(paramSchemaDescription(p)).length - 1) + '"}';
    if (p.required) {
      required.push(p.name);
    }
  }
  let schema: string = '{"type":"object","properties":{' + props + '}';
  if (required.length > 0) {
    schema += ',"required":[' + required.map((n: string): string => JSON.stringify(n)).join(',') +
      ']';
  }
  return schema + '}';
}

// 模型面 desc 生成（纯函数；英文主体照 http_request / env_list 形态，点明三件事：用户定义
// 的接口模板、参数填什么、走与 http_request 完全相同的闸——写方法照样要确认）
export function buildTemplateToolDesc(displayName: string, method: string, urlTemplate: string,
  paramsJson: string): string {
  const head: string = 'User-defined request template "' + displayName + '". Sends ' + method +
    ' ' + urlTemplate + '. Fill the parameters defined in the schema; the app assembles the ' +
    'final request and sends it through the same pipeline as http_request, so write methods ' +
    'still ask the user for confirmation and domain rules still apply. Do not guess parameter ' +
    'values; ask the user when unclear.';
  const params: TemplateParam[] = parseTemplateParams(paramsJson);
  if (params.length === 0) {
    return head;
  }
  let list: string = ' Parameters:';
  for (const p of params) {
    list += ' ' + p.name + ' (' + positionLabel(p.position) +
      (p.required ? ', required' : ', optional') +
      (p.desc !== '' ? ': ' + p.desc : '') + ');';
  }
  return head + list;
}

// 模板输入校验（纯函数；'' = 合法，否则中文错误——UI 保存/更新前调用，就地拒绝）：
// 名称非空且不超上限、URL 模板 http(s) 开头、参数定义结构合法（数量 / 命名 / 位置 / 重名）、
// 占位与位置匹配（URL 模板占位必须是 path 位参数且 query 位参数不得写进 URL——query 由
// 组装时追加，写在 URL 会双参数；body 模板占位必须是 body 位；头值占位必须是 header 位）。
// method 白名单与「GET 不带 body 模板」由 UI 选择控件承担（选项组非法不可达，不入纯函数
// ——白名单常量单源在 ToolHttp，禁第二份）。
export const TEMPLATE_URL_MAX_CHARS: number = 2048;
// ↑ 与 ToolHttp.HTTP_URL_MAX_CHARS 同值互指（改则同改——纯函数区零 import 禁引工具域
// 常量，分立是避环直跑纪律下的有意识重复，非第二真相：保存侧与执行器拦 2048 必须同步
// 松紧，否则出现「保存过、执行拒」的窗口）

export function validateTemplateInput(name: string, urlTemplate: string, headersJson: string,
  bodyTemplate: string, paramsJson: string, nameMaxChars: number,
  paramsMax: number): string {
  if (name.trim() === '') {
    return '请填写模板名称';
  }
  if (name.length > nameMaxChars) {
    return '模板名称过长，上限 ' + nameMaxChars + ' 字';
  }
  const url: string = urlTemplate.trim();
  if (url === '') {
    return '请填写 URL 模板';
  }
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    return 'URL 模板要以 http:// 或 https:// 开头';
  }
  if (url.length > TEMPLATE_URL_MAX_CHARS) {
    return 'URL 模板过长，上限 ' + TEMPLATE_URL_MAX_CHARS + ' 字符';
  }
  const params: TemplateParam[] = parseTemplateParams(paramsJson);
  if (params.length > paramsMax) {
    return '参数最多 ' + paramsMax + ' 个';
  }
  const seen: string[] = [];
  const pathNames: string[] = [];
  const queryNames: string[] = [];
  const bodyNames: string[] = [];
  const headerNames: string[] = [];
  for (const p of params) {
    if (!/^[a-zA-Z0-9_]+$/.test(p.name)) {
      return '参数名 ' + p.name + ' 只能用字母、数字和下划线';
    }
    if (seen.includes(p.name)) {
      return '参数名 ' + p.name + ' 重复了';
    }
    seen.push(p.name);
    if (!TEMPLATE_PARAM_POSITIONS.includes(p.position)) {
      return '参数 ' + p.name + ' 的位置不正确';
    }
    if (p.position === 'path') {
      pathNames.push(p.name);
    } else if (p.position === 'query') {
      queryNames.push(p.name);
    } else if (p.position === 'body') {
      bodyNames.push(p.name);
    } else {
      headerNames.push(p.name);
    }
  }
  // 占位语法整体合法性（先于逐名匹配）：凡 {…} 形态但名字含合法字符集之外的占位（{x-y}、
  // {城市}）就地拦下——放行会原样发给服务端，用户还以为参数已生效
  const illegal6 = illegalPlaceholderName(url);
  if (illegal6 !== '') {
    return 'URL 里的占位 {' + illegal6 + '} 名字只能用字母、数字和下划线';
  }
  // 占位与位置匹配：URL 模板占位 ∈ path 名单且不得含 query 名（双参数防线）
  for (const n of placeholderNames(url)) {
    if (queryNames.includes(n)) {
      return '查询参数 ' + n + ' 不用写进 URL，保存后调用时会自动追加';
    }
    if (!pathNames.includes(n)) {
      return 'URL 里的占位 {' + n + '} 还没有定义为路径段参数';
    }
  }
  const bodyIllegal: string = illegalPlaceholderName(bodyTemplate);
  if (bodyIllegal !== '') {
    return '正文里的占位 {' + bodyIllegal + '} 名字只能用字母、数字和下划线';
  }
  for (const n of placeholderNames(bodyTemplate)) {
    if (!bodyNames.includes(n)) {
      return '正文里的占位 {' + n + '} 还没有定义为请求体参数';
    }
  }
  const headers: TemplateHeader[] = parseTemplateHeaders(headersJson);
  for (const h of headers) {
    if (h.name.trim() === '') {
      return '请求头名不能为空';
    }
    const hIllegal: string = illegalPlaceholderName(h.value);
    if (hIllegal !== '') {
      return '请求头 ' + h.name + ' 里的占位 {' + hIllegal + '} 名字只能用字母、数字和下划线';
    }
    for (const n of placeholderNames(h.value)) {
      if (!headerNames.includes(n)) {
        return '请求头 ' + h.name + ' 里的占位 {' + n + '} 还没有定义为请求头参数';
      }
    }
  }
  return '';
}

// 花括号片段里的非法占位名（validateTemplateInput 辅助）：返回第一个名字不合法的占位名，
// 全合法返 ''。正则取 {…} 全量 token 再验名字——{x-y}、{城市} 这类被 placeholderNames
// 的合法字符集正则漏掉的拼写错误在此收口。★ {{…}} 凭据引用记号先摘除再扫——凭据名合法
// 集宽于占位名（只禁花括号，中文与连字符名合法），不摘则内层段会被误判非法；摘除配对
// 判据与 extractCredRefs 同为 {{ 开 }} 闭，}} 缺失按普通占位面扫描
function illegalPlaceholderName(text: string): string {
  const stripped: string = text.replace(/\{\{[^{}]*\}\}/g, '');
  const tokens: string[] = stripped.match(/\{[^{}]*\}/g) ?? [];
  for (const token of tokens) {
    const name: string = token.substring(1, token.length - 1);
    if (!/^[a-zA-Z0-9_]+$/.test(name)) {
      return name;
    }
  }
  return '';
}

// cURL 草稿（parseCurlCommand 产物；预填表单用——不落库）
export interface CurlDraft {
  method: string;
  url: string;
  headerNames: string[];
  headerValues: string[];
  body: string;
}

// cURL 命令解析（纯函数；导入面 = -X/--request、-H/--header、-d/--data 族、--url、裸 URL。
// 引号包裹的 token 整体取值；多 -d 按 curl 语义用 & 连接；-d 隐含 POST（无 -X 时）；
// 解析不出 URL = null（UI 提示检查粘贴内容）。行尾反斜杠续行先并成单行。双引号内 \" 与
// \\ 按转义取字符（JSON body 粘贴的高频形态；其余反斜杠字面保留，$ ` 变量展开不支持、
// 原样取字面；单引号内按 bash 语义一切字面）
export function parseCurlCommand(text: string): CurlDraft | null {
  const merged: string = text.replace(/\\\r?\n/g, ' ').trim();
  if (merged === '') {
    return null;
  }
  const tokens: string[] = [];
  let current: string = '';
  let quote: string = '';
  for (let i = 0; i < merged.length; i++) {
    const ch: string = merged[i];
    if (quote !== '') {
      if (quote === '"' && ch === '\\' && i + 1 < merged.length &&
        (merged[i + 1] === '"' || merged[i + 1] === '\\')) {
        current += merged[i + 1];
        i++;
        continue;
      }
      if (ch === quote) {
        quote = '';
      } else {
        current += ch;
      }
      continue;
    }
    if (ch === '\'' || ch === '"') {
      quote = ch;
      continue;
    }
    if (ch === ' ' || ch === '\t') {
      if (current !== '') {
        tokens.push(current);
        current = '';
      }
      continue;
    }
    current += ch;
  }
  if (current !== '') {
    tokens.push(current);
  }
  let method: string = '';
  let url: string = '';
  let body: string = '';
  const headerNames: string[] = [];
  const headerValues: string[] = [];
  const dataParts: string[] = [];
  const dataFlags: string[] = ['-d', '--data', '--data-raw', '--data-binary', '--data-urlencode'];
  const headerFlags: string[] = ['-H', '--header'];
  for (let i = 0; i < tokens.length; i++) {
    const t: string = tokens[i];
    if (t === '-X' || t === '--request') {
      if (i + 1 < tokens.length) {
        method = tokens[i + 1].toUpperCase();
        i++;
      }
    } else if (t === '--url') {
      if (i + 1 < tokens.length) {
        url = tokens[i + 1];
        i++;
      }
    } else if (headerFlags.includes(t)) {
      if (i + 1 < tokens.length) {
        const raw: string = tokens[i + 1];
        const idx: number = raw.indexOf(':');
        if (idx > 0) {
          headerNames.push(raw.substring(0, idx).trim());
          headerValues.push(raw.substring(idx + 1).trim());
        }
        i++;
      }
    } else if (dataFlags.includes(t)) {
      if (i + 1 < tokens.length) {
        dataParts.push(tokens[i + 1]);
        i++;
      }
    } else if (t.startsWith('-')) {
      continue; // 其余 flag（-s -L --compressed 等）忽略——只取发请求必需的字段
    } else if (url === '' && (t.startsWith('http://') || t.startsWith('https://'))) {
      url = t;
    } else if (url === '' && !t.startsWith('-') && t.includes('.')) {
      url = 'https://' + t; // 裸域名兜底（curl 默认协议 https 化——保守取 https）
    }
  }
  if (url === '') {
    return null;
  }
  if (dataParts.length > 0) {
    body = dataParts.join('&');
  }
  if (method === '') {
    method = dataParts.length > 0 ? 'POST' : 'GET';
  }
  const draft: CurlDraft = {
    method: method, url: url, headerNames: headerNames,
    headerValues: headerValues, body: body
  };
  return draft;
}

// OpenAPI 摘要操作（parseOpenApiSummary 产物元素；预填表单草稿用）
export interface OpenApiOperation {
  method: string;
  path: string;
  summary: string;
  pathParams: string[];
  queryParams: string[];
}

// OpenAPI 摘要草稿（parseOpenApiSummary 产物；base = servers[0]，拉取页展示与预填拼 URL 用）
export interface OpenApiDraft {
  base: string;
  ops: OpenApiOperation[];
}

// OpenAPI 摘要解析（纯函数；只支持 JSON 格式文档——YAML 返 null 由 UI 提示。servers[0]
// 为 base；paths × get/post/put/delete/patch 五方法；参数取 operation 级并 pathItem 级的
// in=path/query 项名。ops 上限由入参给（与模板条数上限同源传入，零第二份常量），超限截断）
export function parseOpenApiSummary(jsonText: string, maxOps: number): OpenApiDraft | null {
  let doc: Record<string, Object>;
  try {
    doc = JSON.parse(jsonText) as Record<string, Object>;
  } catch (e) {
    return null;
  }
  const pathsRaw: Object = doc['paths'];
  if (typeof pathsRaw !== 'object' || pathsRaw === null) {
    return null;
  }
  const paths = pathsRaw as Record<string, Object>;
  const methods: string[] = ['get', 'post', 'put', 'delete', 'patch'];
  const ops: OpenApiOperation[] = [];
  for (const path of Object.keys(paths)) {
    const itemRaw: Object = paths[path];
    if (typeof itemRaw !== 'object' || itemRaw === null) {
      continue;
    }
    const item = itemRaw as Record<string, Object>;
    const itemLevel: Object[] = Array.isArray(item['parameters']) ?
      item['parameters'] as Object[] : [];
    for (const m of methods) {
      const opRaw: Object = item[m];
      if (typeof opRaw !== 'object' || opRaw === null) {
        continue;
      }
      const op = opRaw as Record<string, Object>;
      const pathParams: string[] = [];
      const queryParams: string[] = [];
      const opLevel: Object[] = Array.isArray(op['parameters']) ?
        op['parameters'] as Object[] : [];
      for (const holder of opLevel.concat(itemLevel)) {
        const rec = holder as Record<string, Object>;
        const pin: Object = rec['in'];
        const pname: Object = rec['name'];
        if (typeof pin !== 'string' || typeof pname !== 'string') {
          continue;
        }
        if (pin === 'path' && !pathParams.includes(pname)) {
          pathParams.push(pname);
        } else if (pin === 'query' && !queryParams.includes(pname)) {
          queryParams.push(pname);
        }
      }
      const summaryRaw: Object = op['summary'];
      const opIdRaw: Object = op['operationId'];
      const summary: string = typeof summaryRaw === 'string' && summaryRaw !== '' ?
        summaryRaw : (typeof opIdRaw === 'string' ? opIdRaw : '');
      ops.push({ method: m.toUpperCase(), path: path, summary: summary,
        pathParams: pathParams, queryParams: queryParams });
      if (ops.length >= maxOps) {
        return { base: openApiBaseOf(doc), ops: ops };
      }
    }
  }
  if (ops.length === 0) {
    return null;
  }
  return { base: openApiBaseOf(doc), ops: ops };
}

// servers[0].url 取值（解析辅函数；缺省回 ''——草稿预填时 base 空则用户手补）
function openApiBaseOf(doc: Record<string, Object>): string {
  const serversRaw: Object = doc['servers'];
  if (!Array.isArray(serversRaw)) {
    return '';
  }
  const servers: Object[] = serversRaw as Object[];
  if (servers.length === 0) {
    return '';
  }
  const first = servers[0] as Record<string, Object>;
  const url: Object = first['url'];
  return typeof url === 'string' ? url : '';
}

// OpenAPI 操作 → 模板写入形态（纯函数；草稿预填用）：名称 = summary 截 nameMaxChars
//（无 summary 用路径尾段）；URL = base + path（{param} 占位原样 = path 参数天然匹配）；
// path 参数 → path 位必填；query 参数 → query 位可省；body schema 不展开（请求体复杂的
// 接口第一版不带 body 模板，用户导入后自行补）
export function templateInputFromOpenApi(base: string, op: OpenApiOperation,
  nameMaxChars: number): HttpTemplateInput {
  let name: string = op.summary;
  if (name === '') {
    const segs: string[] = op.path.split('/').filter((s: string): boolean => s !== '');
    name = segs.length > 0 ? segs[segs.length - 1] : op.path;
  }
  name = name.replace(/[{}]/g, '');
  if (name.length > nameMaxChars) {
    name = name.substring(0, nameMaxChars);
  }
  const fullUrl: string = base !== '' ? base + op.path : op.path;
  let paramsJson: string = '[]';
  if (op.pathParams.length > 0 || op.queryParams.length > 0) {
    let arr: string = '[';
    for (const p of op.pathParams) {
      if (arr !== '[') {
        arr += ',';
      }
      arr += '{"name":' + JSON.stringify(p) + ',"position":"path","desc":"","required":true}';
    }
    for (const p of op.queryParams) {
      if (arr !== '[') {
        arr += ',';
      }
      arr += '{"name":' + JSON.stringify(p) + ',"position":"query","desc":"","required":false}';
    }
    paramsJson = arr + ']';
  }
  const input: HttpTemplateInput = {
    name: name, method: op.method, urlTemplate: fullUrl, headersJson: '[]',
    bodyTemplate: '', paramsJson: paramsJson
  };
  return input;
}

// 注册名判据（动态域唯一前缀；collectTools 追加面与 sync 注销面共用）
export function isTemplateToolName(name: string): boolean {
  return name.startsWith('tpl_');
}

// slug 派生（定案③：tpl_<自增 id>，恒定——改名不改 slug）
export function templateSlugOf(id: number): string {
  return 'tpl_' + id;
}

// slug 还原 id（slug 恒由 templateSlugOf 派生，逆变换安全；非 tpl_ 形态 = -1 调用方按
// 查无处理。★ 运行时现查走 id 主键而非 slug 列——insert 回填 slug 的两语句窗口可留
// slug='' 残留行，按列查永远查不到；id 恒在，两侧同源。细节见
// HttpTemplateDb.queryHttpTemplateById 注释）
export function templateIdOfSlug(slug: string): number {
  if (!slug.startsWith('tpl_')) {
    return -1;
  }
  const id: number = parseInt(slug.substring(4), 10);
  return Number.isFinite(id) && id > 0 ? id : -1;
}

// ═══ 动态注册与执行域（依赖面在本区；模块顶层零求值——惰性构造纪律，坑50 家族）═══

// 模板执行器：按 slug 现查模板行 → 组装 → 委托 HttpRequestExecutor（同一执行通道，全闸
// 继承——定案⑤）。查无模板 = 已被删除，中文错误回执可观测
class TemplateExecutor implements ToolExecutor {
  private readonly slug: string;

  constructor(slug: string) {
    this.slug = slug;
  }

  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let values: Record<string, string> = {};
    try {
      const parsed = JSON.parse(argsJson) as Record<string, Object>;
      for (const key of Object.keys(parsed)) {
        const v: Object = parsed[key];
        if (typeof v === 'string') {
          values[key] = v;
        }
      }
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    let row: HttpTemplateRow | null = null;
    try {
      row = await queryHttpTemplateById(templateIdOfSlug(this.slug));
    } catch (e) {
      row = null;
    }
    if (row === null) {
      return JSON.stringify({ error: '该请求模板已被删除。本次调用无法执行，也不要重试' });
    }
    const assembled: TemplateAssembled = assembleTemplateRequest(row.method, row.urlTemplate,
      row.headersJson, row.bodyTemplate, row.paramsJson, values);
    if (!assembled.ok) {
      return JSON.stringify({ error: assembled.error });
    }
    const finalArgs: string = JSON.stringify({
      url: assembled.url,
      method: assembled.method,
      headers: assembled.headers,
      body: assembled.body
    });
    return new HttpRequestExecutor().execute(finalArgs, ctx);
  }
}

// 模板工具预检（组装后委托 httpRequestNeedsConfirm——写方法确认卡与结构化预览同源；
// 全包 try/catch 恒不抛，ToolEntry.preflight 契约见 ToolContracts）。
// ★ fail-closed（H3-5 拍板）：异常分阶段处理——
// · 模板行查询异常：method 不可知，而预检与执行是两次独立查询（「预检挂、执行成」=
//   写请求无卡直发的真实窗口）——返 writeConfirmFallbackPrompt 保守人工卡，写读两态
//   都多一道确认（读方法多确认一次是 fail-closed 的代价，方向恒安全）；
// · 已查到行后的组装/委托异常：按行 method 定向——写方法返保守人工卡，读方法返 null；
// · 坏形态阶段（查无模板 / 参数解析失败 / 组装 !ok）返 null——执行器同查询/同解析/同错
//   拦下，无直发面。
// 形态说明：契约只有 argsJson/ctx 两参、无工具名——执行器按「每模板一实例」带 slug，
// 预检按「每模板一闭包」捕 slug（buildTemplatePreflight），共用实现收在
// templatePreflightFor 单点，禁模块级可变中转态（跨调用可变模块态是竞态温床）
async function templatePreflightFor(slug: string, argsJson: string,
  ctx: ToolExecutionContext): Promise<ConfirmPrompt | null> {
  let row: HttpTemplateRow | null = null;
  try {
    row = await queryHttpTemplateById(templateIdOfSlug(slug));
  } catch (e) {
    return writeConfirmFallbackPrompt(); // fail-closed：method 不可知，写方法不得无卡直发
  }
  if (row === null) {
    return null; // 查无 = 已删除，执行器同查询报错拦，无直发面
  }
  let values: Record<string, string> = {};
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    for (const key of Object.keys(parsed)) {
      const v: Object = parsed[key];
      if (typeof v === 'string') {
        values[key] = v;
      }
    }
  } catch (e) {
    return null; // 参数坏形态由执行器给解析错误回执，预检不重复拦截
  }
  let assembled: TemplateAssembled;
  try {
    assembled = assembleTemplateRequest(row.method, row.urlTemplate,
      row.headersJson, row.bodyTemplate, row.paramsJson, values);
  } catch (e) {
    // fail-closed：组装异常（parse 与渲染均自防，理论不抛的防御面）时 method 已知定向
    return HTTP_WRITE_METHODS.includes(row.method) ? writeConfirmFallbackPrompt() : null;
  }
  if (!assembled.ok) {
    return null; // 组装失败执行器同错拦，无直发面
  }
  try {
    return await httpRequestNeedsConfirm(JSON.stringify({
      url: assembled.url, method: assembled.method,
      headers: assembled.headers, body: assembled.body
    }), ctx);
  } catch (e) {
    // 委托自身全包自防（写方法路径异常已在直接口内层 fail-closed），此兜底按 method 定向
    return HTTP_WRITE_METHODS.includes(row.method) ? writeConfirmFallbackPrompt() : null;
  }
}

function buildTemplatePreflight(slug: string): (argsJson: string,
  ctx: ToolExecutionContext) => Promise<ConfirmPrompt | null> {
  return (argsJson: string, ctx: ToolExecutionContext): Promise<ConfirmPrompt | null> =>
    templatePreflightFor(slug, argsJson, ctx);
}

// 行 → 注册条目（sync 注册面；定案①modeDriven 随行不出工具页、group 归 HTTP 域仅满足
// 必填字段——modeDriven 过滤先行，卡面永不出模板行）
function toolEntryOfTemplate(row: HttpTemplateRow): ToolEntry {
  return {
    name: row.slug !== '' ? row.slug : templateSlugOf(row.id),
    title: row.name,
    desc: buildTemplateToolDesc(row.name, row.method, row.urlTemplate, row.paramsJson),
    group: TOOL_GROUP_HTTP,
    parametersJson: buildTemplateSchema(row.paramsJson),
    defaultEnabled: false,
    modeDriven: true,
    executor: new TemplateExecutor(row.slug !== '' ? row.slug : templateSlugOf(row.id)),
    preflight: buildTemplatePreflight(row.slug !== '' ? row.slug : templateSlugOf(row.id))
  };
}

// 动态注册同步（幂等；调用点 = EntryAbility 启动兜底 / 设置页模板增删改后 / 管理页进页）。
// 注册 = 逐件 register（同 slug 覆盖 = desc/schema 刷新）；注销 = 库里已无此 slug 的
// tpl_* 全部 unregister（ToolRegistry 笔6 新增一枚的唯一消费方）。库读失败时零动作
//（注册表保旧态 = 上次已知态，不把瞬时 IO 故障放大成能力消失）
export async function syncTemplateTools(): Promise<void> {
  let rows: HttpTemplateRow[] = [];
  try {
    rows = await queryHttpTemplates();
  } catch (e) {
    return;
  }
  const present: string[] = rows.map((r: HttpTemplateRow): string =>
    r.slug !== '' ? r.slug : templateSlugOf(r.id));
  const stale: string[] = [];
  toolRegistry.all().forEach((entry: ToolEntry): void => {
    if (isTemplateToolName(entry.name) && !present.includes(entry.name)) {
      stale.push(entry.name);
    }
  });
  for (const name of stale) {
    toolRegistry.unregister(name);
  }
  for (const row of rows) {
    toolRegistry.register(toolEntryOfTemplate(row));
  }
}

// 声明追加点用：当前已注册的模板工具条目（同步读注册表——collectTools 同步链；本函数只读
// 不补，同步性由启动兜底与设置页写侧 syncTemplateTools 保证）
export function registeredTemplateEntries(): ToolEntry[] {
  const out: ToolEntry[] = [];
  toolRegistry.all().forEach((entry: ToolEntry): void => {
    if (isTemplateToolName(entry.name)) {
      out.push(entry);
    }
  });
  return out;
}

// 行 → 写入形态（管理页保存用：UI 校验后的字段打包；slug/时间戳/条数闸在 DB 层）
export function templateInputOf(name: string, method: string, urlTemplate: string,
  headersJson: string, bodyTemplate: string, paramsJson: string): HttpTemplateInput {
  const input: HttpTemplateInput = {
    name: name, method: method, urlTemplate: urlTemplate, headersJson: headersJson,
    bodyTemplate: bodyTemplate, paramsJson: paramsJson
  };
  return input;
}
