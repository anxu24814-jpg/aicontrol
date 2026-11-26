// 代码工作台执行回执装配纯函数。
// · 职责：从 ScriptRunResult 既有字段派生 status / failureKind（**native 零新增分类字段
//   ——装配层是唯一判据来源**）+ 固定中文文案（稳定句，模型靠它判因，不得改写成同义句）
//   + 溢出信封组装 + 自预算收口（回执含信封恒 < 8192 字符，保证通用截断器〔ToolClip.
//   clipToolResult 默认 8192〕永不介入、结构永不被拦腰截断）。超时句族为毫秒入参 +
//   timeout 钳制说明句（超时/取消短路的尾注拼接见 ToolCodeExec）。
// · import 面：只引 ScriptEngine（零 import 叶子）与 ScriptLimits（纯数值域）——零 @kit，
//   供断言直跑；不引 ToolTypes（环事故红线）。
// · 为何不并入 ScriptEngine.ets / ToolCodeExec.ets：前者零 import 叶子纪律，后者执行器
//   混居（反碎片下限②）。
// · 不做「重试」自动化——失败交模型判断。
import { ScriptRunResult } from './ScriptEngine';
import { SCRIPT_TIMEOUT_MIN_SECONDS } from './ScriptLimits';

// ── 回执状态与失败分类值族（status 六值 / failureKind 七值——模型须能判「我的代码
//    错了」还是「环境掐了」；代决默认值，可翻）──
export const SCRIPT_STATUS_SUCCESS: string = 'success';
export const SCRIPT_STATUS_FAILED: string = 'failed';
export const SCRIPT_STATUS_TIMEOUT: string = 'timeout';
export const SCRIPT_STATUS_CANCELED: string = 'canceled';
export const SCRIPT_STATUS_BUSY: string = 'busy';
export const SCRIPT_STATUS_ENGINE_ERROR: string = 'engine-error';

export const SCRIPT_KIND_SYNTAX: string = 'syntax';
export const SCRIPT_KIND_RUNTIME: string = 'runtime';
export const SCRIPT_KIND_TIMEOUT: string = 'timeout';
export const SCRIPT_KIND_HEAP: string = 'heap';
export const SCRIPT_KIND_CANCELED: string = 'canceled';
export const SCRIPT_KIND_ENGINE: string = 'engine';
export const SCRIPT_KIND_FS_GATE: string = 'fs-gate';
// 网络类失败：域名闸拒 / 非 2xx / 网络失败 / 超限 / 桥等待到点 / 投递失败 / 放弃态 /
// 上下文缺失——网络与授权类失败 ≠ 脚本代码错，模型据此一次判对方向（不追加「脚本代码
// 自身报错」类指引句——原因句自带下一步）
export const SCRIPT_KIND_NETWORK: string = 'network';

// 忙锁错误名（native 忙锁在时同步回的 errorName——忙锁与真失败的区分位）
export const SCRIPT_ERROR_BUSY: string = 'BusyError';
// fs 闸错误名（native 侧闸拒绝抛的 JS 异常 name；message 为中文闸原因含当前值与上限。
// 判据双保险：name 主判 + message 前缀「临时区限制」兜底——native 设 name 失败时兜底
// 判据仍可达）
export const SCRIPT_ERROR_FENCE: string = 'FenceError';
export const FENCE_MESSAGE_PREFIX: string = '临时区限制';
// 沙箱网络错误名（HostHttpGet 一切网络面失败抛的 JS 异常 name——判据主位；TypeError
// 参数形态错仍归 runtime）
export const SCRIPT_ERROR_HTTP: string = 'HttpError';

// ── 固定中文文案（稳定句，不得改写成同义句——模型靠固定句判因）──
export const SCRIPT_BUSY_TEXT: string = '上一个脚本仍在运行，请稍后重试。';
export const SCRIPT_CANCELED_TEXT: string = '本次运行已取消，结果作废。';
export const SCRIPT_ENGINE_ERROR_TEXT: string = '脚本引擎异常，本次调用没有执行。';
// 环境类失败指引（heap / engine 类随原生 message 附带）
export const SCRIPT_ENV_GUIDE_TEXT: string = '这是执行环境原因，重跑同一段脚本不会成功。';
// 脚本类失败指引（syntax / runtime 类随原生 name/message 附带）
export const SCRIPT_CODE_GUIDE_TEXT: string = '脚本代码自身报错，按错误信息修改后再试。';

// 秒数文案（至多一位小数——等待时长与生效时限两处共用同一格式化，防口径漂移）
function scriptSecondsText(ms: number): string {
  return String(Math.round(ms / 100) / 10);
}

// 超时固定句（秒数 = 生效超时毫秒——缺省路径 = 档位时限、timeout 参数路径 = 钳制后值；
// 秒数文案单源 scriptSecondsText）
export function scriptTimeoutText(timeoutMs: number): string {
  return '脚本运行超过 ' + scriptSecondsText(timeoutMs) +
    ' 秒仍未结束，已停止等待，本次结果作废。正在运行的脚本不保证被中断。';
}

// ── 状态判定（装配层唯一判据顺序，自上而下首个命中即定；序 2 / 3〔计时器先到 / 取消〕
//    由调用侧短路——竞速计时与取消标记在 ScriptScheduler，先于本函数判）──
export interface ScriptRunClass {
  status: string;
  failureKind: string;
}

export function classifyScriptRun(result: ScriptRunResult): ScriptRunClass {
  if (result.errorName === SCRIPT_ERROR_BUSY) {
    return { status: SCRIPT_STATUS_BUSY, failureKind: '' };
  }
  if (!result.ok && result.errorName === '' &&
    result.flags.indexOf('js-exception') < 0) {
    // 引擎侧异常 / 未正常返回（非 JS 异常形态：ok=false 且无 JS 错误名且 native 未报告
    // 脚本自身异常。坑：脚本 throw 原始值〔如 throw 5〕时 name/message 皆空但 native 带
    // flags 'js-exception'——须摘出归 runtime，见下支，否则归因错位）
    return { status: SCRIPT_STATUS_ENGINE_ERROR, failureKind: SCRIPT_KIND_ENGINE };
  }
  // heap 旗标只在失败运行时判类：JSVM 堆阈值回调取上限 7/8 只记标不中断〔jsvm_runner.cpp〕，
  // 触及后 GC 回收、脚本正常跑完的场景 ok=true 且旗标在场——不看 ok 会误判 heap 失败、成功
  // 结果被丢弃还附假指引。对齐 QuickJS「真 OOM 才记 heap-limit 且必伴随失败」语义：ok=true
  // 时旗标只在 flags 保留（装配层不删值纪律），不改变判定。
  if (!result.ok && result.flags.indexOf('heap-limit') >= 0) {
    return { status: SCRIPT_STATUS_FAILED, failureKind: SCRIPT_KIND_HEAP };
  }
  if (result.errorName === 'SyntaxError') {
    return { status: SCRIPT_STATUS_FAILED, failureKind: SCRIPT_KIND_SYNTAX };
  }
  if (result.errorName === SCRIPT_ERROR_FENCE ||
    result.errorMessage.indexOf(FENCE_MESSAGE_PREFIX) === 0) {
    return { status: SCRIPT_STATUS_FAILED, failureKind: SCRIPT_KIND_FS_GATE };
  }
  // 沙箱网络失败支（插在 fs-gate 之后、runtime 之前——HttpError 直落 network，模型判
  // 「是网络/授权面，不是我的语法」）
  if (result.errorName === SCRIPT_ERROR_HTTP) {
    return { status: SCRIPT_STATUS_FAILED, failureKind: SCRIPT_KIND_NETWORK };
  }
  if (result.errorName !== '' || result.flags.indexOf('js-exception') >= 0) {
    // 脚本自身错误（有名异常直落；throw 原始值经 js-exception 标志归入——回执给
    // 「（无错误信息）」+ 序列化抛出值〔native 侧兜底〕，指引句导向改代码）
    return { status: SCRIPT_STATUS_FAILED, failureKind: SCRIPT_KIND_RUNTIME };
  }
  return { status: SCRIPT_STATUS_SUCCESS, failureKind: '' };
}

// ── 信封与截断（§3.3-5）──
// 单行截断长度（超长单行按此截断并追加标记；Kimi 原文标记）
const SCRIPT_LINE_CLIP: number = 2000;
const SCRIPT_LINE_CLIP_TAIL: string = '[...truncated]';
// 回执硬顶（自预算铁律：回执含信封恒 < 8192——与 WORKSPACE_REPLY_BUDGET 同纪律，留 1 字符
// 余量保证严格小于）
const SCRIPT_REPLY_HARD_CAP: number = 8191;
// 头尾预览截断（native 已给约 1KB 预览，装配侧再收口到 1024 字符防 napi 侧超量）
const SCRIPT_PREVIEW_CLIP: number = 1024;

// 单行截断（> 2000 字符截断 + 尾标；UTF-16 码元口径与 ArkTS string.length 一致）
function clipSingleLine(line: string): string {
  if (line.length <= SCRIPT_LINE_CLIP) {
    return line;
  }
  return line.substring(0, SCRIPT_LINE_CLIP) + SCRIPT_LINE_CLIP_TAIL;
}

// 多行文本逐行截断（value 与 logs 每条都过——超长行不劈整段结构）
function clipLines(text: string): string {
  const lines: string[] = text.split('\n');
  for (let i = 0; i < lines.length; i++) {
    lines[i] = clipSingleLine(lines[i]);
  }
  return lines.join('\n');
}

// 预算内截断（尾部加省略标记；预算 ≤ 0 回省略标记占位——调用侧保证不走到）
function trimToBudget(text: string, budget: number): string {
  if (text.length <= budget) {
    return text;
  }
  if (budget <= 1) {
    return '…';
  }
  return text.substring(0, budget - 1) + '…';
}

// 溢出信封段（有溢出件时追加：文件名 + 总字节 + 头尾预览 + 可执行指引——指针真实可达，
// 读回工具 exec_output_read 同批落地，禁出现「用 workspace_read 捞回」的假指引）。
// 顶闸变体——flags 含 output-truncated（落盘写满单件闸）或 log-truncated（收集闸顶满）时，
// 「完整输出」承诺不再成立，信封如实降格为「仅保留前段」，共 N 字节同改报文件实写量；
// 非顶闸路径文案逐字保持既有形态（断言直跑判据依赖）
function composeEnvelope(result: ScriptRunResult): string {
  const head: string = trimToBudget(clipLines(result.outputHead), SCRIPT_PREVIEW_CLIP);
  const tail: string = trimToBudget(clipLines(result.outputTail), SCRIPT_PREVIEW_CLIP);
  const capHit: boolean = result.flags.indexOf('output-truncated') >= 0 ||
    result.flags.indexOf('log-truncated') >= 0;
  const lead: string = capHit ?
    '输出超过回执上限，已存为临时文件 ' + result.outputFileName + '，共 ' +
    result.outputBytes + ' 字节，超过临时文件上限仅保留前段。' :
    '输出超过回执上限，完整输出已存为临时文件 ' + result.outputFileName +
    '，共 ' + result.outputBytes + ' 字节。';
  return lead + '\n开头：\n' + head + '\n结尾：\n' + tail + '\n' +
    '继续查看用 exec_output_read，name 传文件名，offset 从 1 起分段读。';
}

// 成功段（结果值 + 日志；动态预算分配——固定头与信封与尾注先占，余量给 value 与 logs，
// value 优先；预算单源 SCRIPT_REPLY_HARD_CAP，档位数值不参与回执组装）
function composeSuccessBody(result: ScriptRunResult, budget: number): string {
  const parts: string[] = [];
  let used: number = 0;
  const valueClipped: string = clipLines(result.value);
  const logsClipped: string[] = [];
  for (const log of result.logs) {
    logsClipped.push(clipSingleLine(log));
  }
  if (valueClipped !== '') {
    const seg: string = '结果：\n' + valueClipped;
    const shown: string = trimToBudget(seg, budget - used);
    parts.push(shown);
    used += shown.length + 1;
  }
  // push 门槛 used < budget 的不变量：value 段打满（shown = budget）时 used = budget + 1
  // 自然关闸；开闸时 logs 预算 = budget - used，『…』占位（预算 ≤ 1）占 1 字符恰等于
  // 预算——join 分隔 1 + 段长 ≤ 预算，body 合计恒 ≤ budget（断言钉 value 打满 + 日志
  // 用例守此不变量）
  if (logsClipped.length > 0 && used < budget) {
    const seg: string = '日志：\n' + logsClipped.join('\n');
    parts.push(trimToBudget(seg, budget - used));
  }
  return parts.join('\n');
}

// 失败段（原生 name / message / stack 不改写 + 按类附指引句；fs-gate 与 network 只留中文
// 原因——闸原因与网络原因句本就是给模型读的中文句、自带下一步指引，追加「脚本代码自身
// 报错」类指引句反而误导方向）
function composeFailureBody(result: ScriptRunResult, kind: string, budget: number): string {
  if (kind === SCRIPT_KIND_FS_GATE || kind === SCRIPT_KIND_NETWORK) {
    return trimToBudget(result.errorMessage, budget);
  }
  const guide: string = kind === SCRIPT_KIND_HEAP || kind === SCRIPT_KIND_ENGINE ?
    SCRIPT_ENV_GUIDE_TEXT : SCRIPT_CODE_GUIDE_TEXT;
  let seg: string = result.errorName !== '' ? result.errorName + ': ' : '';
  seg += result.errorMessage !== '' ? result.errorMessage : '（无错误信息）';
  if (result.errorStack !== '') {
    seg += '\n' + result.errorStack;
  }
  return trimToBudget(clipLines(seg), Math.max(budget - guide.length - 1, 1)) + '\n' + guide;
}

// ── 回执组装（唯一入口；调用方 = ToolCodeExec）──
// tail = 转正结果尾注（promoteSavedNames 产出，fs.save 每件一行），计入自预算——若不占
// 8191 预算，「输出打满 + fs.save 转存」组合下回执总长可越 8192，通用截断器会把信封尾部
// 的 exec_output_read 读回指引截掉；尾注先按 SCRIPT_TAIL_CLIP 压短、再计入 fixed，
// value/logs 预算相应缩水，主体与尾注合计恒 < 8192。
// 忙锁 / 引擎错两短路同样拼尾注：两态下脚本未执行、savedNames 恒空，但 data 落件句与
// timeout 钳制句在执行前产生——丢尾注会让模型不知道输入已存件、重试再带 data 会重复落件。
// 尾注上限 1024：转存件数多时压尾注保主体（value 是主结果，不被大量转正行挤占预算）。
// 溢出暂存写失败（native flags 'spill-write-failed'）在成功路径如实告知「输出不完整」
//（禁静默截断，违 P0 禁静默失败精神）。
const SCRIPT_TAIL_CLIP: number = 1024;

// 溢出暂存失败告知句（spill-write-failed 在场且无信封时替代信封位）
const SCRIPT_SPILL_FAILED_TEXT: string =
  '输出超过回执上限，暂存临时区失败，以下内容不完整。';

// 引擎错详情（原生文本原样透传不美化——errorMessage 优先，空则退 errorName、再退 flags；
// 详情随固定句下行后同类失败在回执即自述、无需二次排查；详情为空时回退为原单句形态，
// 契约向后兼容）
function engineErrorDetailOf(result: ScriptRunResult): string {
  if (result.errorMessage !== '') {
    return result.errorMessage;
  }
  if (result.errorName !== '') {
    return result.errorName;
  }
  if (result.flags.length > 0) {
    return result.flags.join('、');
  }
  return '';
}

export function composeScriptReceipt(result: ScriptRunResult, tail: string = ''): string {
  const cls: ScriptRunClass = classifyScriptRun(result);
  // 尾注先行压短：busy 与引擎错两短路同样拼尾注——tail 为空串时两短路回执与原形态逐字一致
  const tailText: string = trimToBudget(tail, SCRIPT_TAIL_CLIP);
  const tailPart: string = tailText !== '' ? '\n' + tailText : '';
  if (cls.status === SCRIPT_STATUS_BUSY) {
    // 忙锁句短（19 字符），尾注直接拼不涉预算代数
    return SCRIPT_BUSY_TEXT + tailPart;
  }
  if (cls.status === SCRIPT_STATUS_ENGINE_ERROR) {
    // 固定句在前（模型判因锚，不得改写）+ 原生详情随后（详情为空时回退为原单句形态，
    // 契约向后兼容）。详情同受自预算铁律：napi 调用异常的 message 理论上可长，逐行截断 +
    // 按「硬顶 − 固定句长 − 尾注长 − 1」收口——本分支（连同忙锁短路）不走下方 body
    // 预算代数，收口须自带，保证「回执含信封恒 < 8192」无条件成立。
    const detail: string = trimToBudget(clipLines(engineErrorDetailOf(result)),
      SCRIPT_REPLY_HARD_CAP - SCRIPT_ENGINE_ERROR_TEXT.length - tailPart.length - 1);
    const body: string = detail !== '' ?
      SCRIPT_ENGINE_ERROR_TEXT + '\n' + detail : SCRIPT_ENGINE_ERROR_TEXT;
    return body + tailPart;
  }
  if (cls.status === SCRIPT_STATUS_SUCCESS) {
    const head: string = '运行完成（' + result.durationMs + ' 毫秒）。';
    const spillFailed: boolean =
      result.outputFileName === '' && result.flags.indexOf('spill-write-failed') >= 0;
    const envelope: string = result.outputFileName !== '' ? '\n' + composeEnvelope(result) :
      (spillFailed ? '\n' + SCRIPT_SPILL_FAILED_TEXT : '');
    const fixed: number = head.length + 1 + envelope.length + tailPart.length;
    const body: string = composeSuccessBody(result,
      SCRIPT_REPLY_HARD_CAP - fixed);
    return head + '\n' + body + envelope + tailPart;
  }
  // failed（heap / syntax / fs-gate / runtime——失败路径不呈现输出，暂存失败无信息
  // 损失，不设告知句）
  const head: string = '运行失败。';
  const body: string = composeFailureBody(result, cls.failureKind,
    SCRIPT_REPLY_HARD_CAP - head.length - 1 - tailPart.length);
  return head + '\n' + body + tailPart;
}

// 超时回执（调用侧计时器先到时短路用；timeoutMs = 生效时限、waitedMs = 实际等待——两处
// 秒数同源格式化；固定句完整出现〔模型判因〕+ 前缀状态与等待时长；native 结果后到即丢弃）
export function composeTimeoutReceipt(timeoutMs: number, waitedMs: number): string {
  return '运行失败（等待了 ' + scriptSecondsText(waitedMs) + ' 秒）。' +
    scriptTimeoutText(timeoutMs);
}

// timeout 参数钳制说明句（参数越界被钳时随回执尾注告知；未越界回空串。只缩不扩——
// 上限恒为生效档位时限）
export function scriptTimeoutClampText(clampedLow: boolean, clampedHigh: boolean,
  tierLimitMs: number): string {
  if (clampedHigh) {
    return 'timeout 超过当前档位上限 ' + scriptSecondsText(tierLimitMs) + ' 秒，本次按上限执行。';
  }
  if (clampedLow) {
    return 'timeout 小于 ' + SCRIPT_TIMEOUT_MIN_SECONDS + ' 秒，本次按 ' +
      SCRIPT_TIMEOUT_MIN_SECONDS + ' 秒执行。';
  }
  return '';
}

// 取消回执（取消标记在时短路用）
export function composeCanceledReceipt(): string {
  return SCRIPT_CANCELED_TEXT;
}
