// exec_python 工具（门 4，方案 §2.4/§2.5）：真实 CPython 3.13 会话内执行器 + desc / schema
// / 确认预检 + 自注册面（照 ToolMount 自注册先例——组标签同居本件，ToolTypes 只接线）。
// · 与 exec_code 的关系：另一执行域，不进 exec_code 模式枚举与「脚本引擎」开关（拍板）；
//   复用同一临时区（会话目录即 Python cwd）、同一溢出件命名面与 exec_output_read 读回口、
//   同一 promote 转正链（save() 登记 → savedNames → promoteSavedNames）。
// · 确认链（拍板「首版走执行确认卡，支持本会话内允许」）：预检经 routeConfirmPrompt 归一
//   （写档；高效档放行 / 标准档审批 / 谨慎档人工卡——三档既有语义，零新轴）。
// · 超时与取消 = 协作式（native 看门狗 + lane 宽限竞速），desc 与回执禁「可中断/强杀」表述；
//   安全面口径 = 应用沙箱内 + 审计可观测（audit 事件行进回执），不承诺网络与文件强边界。
// · import 面：契约自 ToolContracts / ConfirmRouting / AppPreferences（预检三件）；
//   执行编排走 pyexec 域件（PyRuntime 落位与 init、PyScheduler 串行 lane）；临时区 IO 面
//   在 store 侧 WorkspaceDbTmp（IO 面单源纪律）；回执复用件自 ToolCodeExec 导出面。
import { ConfirmPrompt, CONFIRM_LEVEL_WRITE, ToolExecutor, toolArgsParseErrorText,
  toolErrorText } from './ToolContracts';
import { routeConfirmPrompt } from './ConfirmRouting';
import { dataApproveMode } from '../AppPreferences';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { PyExecOutcome, ensurePyRuntime, execPySession, initPyRuntime } from '../pyexec/PyRuntime';
import { pyCleanedNeedsRestart } from '../pyexec/PyPackages';
import { PyLaneResult, runPyBounded } from '../pyexec/PyScheduler';
import { ensureWorkspaceTmpConversationDir, writeWorkspaceTmpTextFile } from '../store/WorkspaceDbTmp';
import { nextSpillFileName, promoteSavedNames } from './ToolCodeExec';

// 工具 id（常量归口 ToolIds，此处引回注册）
import { TOOL_EXEC_PYTHON } from './ToolIds';
import { toolRegistry } from './ToolRegistry';

// ── 限额常量（数值单源本件；desc 与 schema 的数字句为字面联动，翻常量须同笔手改）──
// 缺省等待上限（数据分析首跑含解释器与包装载余量；实测后可调）
export const PY_EXEC_DEFAULT_TIMEOUT_MS: number = 120000;
// 等待上限硬顶（timeout 参数只缩不扩的「扩」上限）
export const PY_EXEC_MAX_TIMEOUT_MS: number = 300000;
// 等待下限（秒级毫秒——与 exec_code 同族）
const PY_EXEC_MIN_TIMEOUT_MS: number = 1000;
// stdout 回执预算（超出整段落盘溢出件，回执只留头尾预览；总回执恒 < 8191 与 JS 同铁律）
const PY_EXEC_STDOUT_BUDGET: number = 5000;
// stderr 回执预算（成功路径的警告与提示截断；失败路径 traceback 走整段预算）
const PY_EXEC_STDERR_BUDGET: number = 1200;
// 回执硬顶（自预算铁律：含信封恒 < 8192，留 1 字符余量）
const PY_REPLY_HARD_CAP: number = 8191;
// 头尾预览截断（溢出信封内）
const PY_PREVIEW_CLIP: number = 1024;
// 安全记录行上限（audit 全量 native 侧已限 50 条，回执只显头 10 行防挤占输出预算）
const PY_AUDIT_MAX_LINES: number = 10;

// ── desc（请求侧 description。★ 并发与限额数字为字面联动：串行/3 等待位/30 秒 ↔
//    PyScheduler 常量、120 秒与 300 秒 ↔ 本件限额常量、临时文件上限 ↔
//    WORKSPACE_TMP_MAX_FILE_BYTES——翻常量须同笔手改）──
export const EXEC_PYTHON_DESC: string =
  '需要在手机上真实运行 Python 做数据分析、表格处理或批量计算时用。这是完整的 CPython ' +
  '3.13 解释器，预置 numpy、pandas、matplotlib、pillow、openpyxl、lxml、regex、cryptography ' +
  '等 28 个包，import 即用。code 是完整可运行的 Python 源码。同一会话里变量跨轮保留，上一轮' +
  '算出的变量这一轮直接可用；换会话或删除会话后失效，应用重启后也不恢复。每轮运行的当前目录' +
  '是本会话的临时区，用 open 读写文件、用 matplotlib 的 savefig 存图都落在这里。要把产物长期' +
  '保留进文件工作区，在代码里调 save(文件名)，执行结束后自动转存并在回执里说明。data 可选，' +
  '传入的文本会先存成临时区文件，文件名以 py-input 开头并随回执给出，脚本里用 open 读取，' +
  '长数据走这里传，不必嵌进 code。timeout 可选，单位秒，最短 1 秒，上限 300 秒，不传按 120 秒。' +
  '超时与取消是协作式的，脚本停在原生调用中时不能立即停下，不要用无限循环测试取消。Python ' +
  '一次只跑一段代码，后续调用排队，等待位 3 个，排队超过 30 秒会放弃并报错。输出过长会存成' +
  '临时文件并用 exec_output_read 分页读取，与脚本工作台共用该工具。要注意 Python 运行在应用' +
    '沙箱内，没有网络与文件的强隔离，网络访问会经 urllib 或 requests 类库直连。有安全事件时' +
    '回执末尾带安全记录行，列出这一轮的文件写入与网络访问事件。';

// ── schema（code 必填 + data 与 timeout 可选——与 exec_code 同族形制）──
export const EXEC_PYTHON_SCHEMA: string = '{"type":"object","properties":{' +
  '"code":{"type":"string","description":"完整可运行的 Python 源码。当前目录是本会话临时区，' +
  'open 与 savefig 直接写在这里。变量在同一会话内跨轮保留。调 save(文件名) 把产物登记转存进' +
  '文件工作区。"},' +
  '"data":{"type":"string","description":"可选的文本数据。会先存成临时区文件，文件名以 ' +
  'py-input 开头并随回执给出，脚本里用 open 读取。长数据走这里传，不传则不创建文件。"},' +
  '"timeout":{"type":"number","description":"可选的本次等待秒数。最短 1 秒，上限 300 秒，' +
  '超出范围自动钳制并在回执里说明。不传按 120 秒。超时中断是协作式的，脚本停在原生调用中时' +
  '不能立即生效。"}},' +
  '"required":["code"]}';

// 确认卡主因句（拍板口径：如实写边界，不承诺沙箱）
const PY_CONFIRM_TEXT: string =
  '运行 Python 代码。代码在应用沙箱内执行，未设网络与文件强边界。';

// args 取串小件（工具域惯用私有形态）
function argsString(parsed: Record<string, Object>, key: string): string {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'string' ? raw : '';
}

// 预算内截断（尾部省略号；预算 ≤ 1 回占位）
function trimToBudget(text: string, budget: number): string {
  if (text.length <= budget) {
    return text;
  }
  if (budget <= 1) {
    return '…';
  }
  return text.substring(0, budget - 1) + '…';
}

// 未执行/异常形态的合成结果（字段齐全——PyExecOutcome 契约不缺项）
function syntheticPyOutcome(errorText: string): PyExecOutcome {
  return { ok: false, stdout: '', stderr: '', error: errorText, elapsedMs: 0,
    savedNames: [], audit: [] };
}

// 确认预检（fail-closed：解析失败不返 null，给保守卡让用户核对代码开头）
export async function execPythonNeedsConfirm(argsJson: string,
  _ctx: ToolExecutionContext): Promise<ConfirmPrompt | null> {
  let codeHead: string = '';
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    const code: string = argsString(parsed, 'code');
    const compact: string = code.replace(/\s+/g, ' ').trim();
    codeHead = compact.length > 300 ? compact.substring(0, 300) + '…' : compact;
  } catch (e) {
    codeHead = '';
  }
  try {
    let prompt: ConfirmPrompt = { text: PY_CONFIRM_TEXT, level: CONFIRM_LEVEL_WRITE };
    if (codeHead !== '') {
      prompt = { text: PY_CONFIRM_TEXT, level: CONFIRM_LEVEL_WRITE, detail: codeHead };
    }
    return routeConfirmPrompt(prompt, dataApproveMode());
  } catch (e) {
    return { text: PY_CONFIRM_TEXT, level: CONFIRM_LEVEL_WRITE };
  }
}

// ── exec_python 执行器 ──
export class ExecPythonExecutor implements ToolExecutor {
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const code: string = argsString(parsed, 'code');
    if (code.trim() === '') {
      return JSON.stringify({ error: 'code 不能为空，请传入完整可运行的 Python 源码。' });
    }
    if (ctx.conversationId === '') {
      return JSON.stringify({ error: 'Python 只在会话中可用，当前执行上下文没有会话。' });
    }
    // 清理待重启闸（门 5，方案 §2.4 行为矩阵）：清自装包/重建运行区后置位，重启前一律拒
    // ——运行区可能已删，静默跑会落在一半残缺的资产上；提示重启即恢复
    if (pyCleanedNeedsRestart()) {
      return JSON.stringify({ error: 'Python 运行环境已清理，请重启应用后再使用 Python 功能。' });
    }
    // data / timeout 类型硬检（P0-1 禁静默兜底）
    const dataRaw: Object | undefined = parsed['data'];
    if (dataRaw !== undefined && typeof dataRaw !== 'string') {
      return JSON.stringify({ error: 'data 只支持字符串，当前收到的是 ' + typeof dataRaw + '。' });
    }
    const dataText: string = typeof dataRaw === 'string' ? dataRaw : '';
    const timeoutRaw: Object | undefined = parsed['timeout'];
    if (timeoutRaw !== undefined && typeof timeoutRaw !== 'number') {
      return JSON.stringify({ error: 'timeout 只支持数值，单位秒，当前收到的是 ' + typeof timeoutRaw + '。' });
    }
    // timeout 钳制 [1s, 300s]，缺省 120s；越钳说明句随尾注（字面联动限额常量）
    let timeoutMs: number = PY_EXEC_DEFAULT_TIMEOUT_MS;
    let clampNote: string = '';
    if (timeoutRaw !== undefined) {
      const reqMs: number = Math.round((timeoutRaw as number) * 1000);
      if (reqMs < PY_EXEC_MIN_TIMEOUT_MS) {
        timeoutMs = PY_EXEC_MIN_TIMEOUT_MS;
        clampNote = 'timeout 小于 1 秒，本次按 1 秒执行。';
      } else if (!(reqMs <= PY_EXEC_MAX_TIMEOUT_MS)) {
        timeoutMs = PY_EXEC_MAX_TIMEOUT_MS;
        clampNote = 'timeout 超过上限 300 秒，本次按上限执行。';
      } else {
        timeoutMs = reqMs;
      }
    }
    // 会话临时区就绪（本轮 cwd；ensure 懒建容 EEXIST）
    let workspaceRoot: string = '';
    try {
      workspaceRoot = ensureWorkspaceTmpConversationDir(ctx.conversationId);
    } catch (e) {
      return JSON.stringify({ error: '临时区目录未就绪：' + toolErrorText(e) });
    }
    // data 落件（空串视同未提供；失败 = 错误回执且脚本不执行）
    let dataNote: string = '';
    if (dataText !== '') {
      const inputName: string = nextPyInputFileName();
      let savedName: string = '';
      try {
        savedName = writeWorkspaceTmpTextFile(ctx.conversationId, inputName, dataText);
      } catch (e) {
        return JSON.stringify({ error: toolErrorText(e) });
      }
      dataNote = '输入数据已存入临时区文件 ' + savedName + '，脚本里用 open 读取，路径直接传文件名。';
    }
    const noteText: string = clampNote !== '' ?
      (dataNote !== '' ? dataNote + '\n' + clampNote : clampNote) : dataNote;
    // 串行 lane 执行（落位 + init + 会话 exec 全在 execFn 内编排；异常转合成结果保中文句）
    const execFn = async (): Promise<PyExecOutcome> => {
      try {
        const homeDir: string = await ensurePyRuntime();
        const init = await initPyRuntime(homeDir);
        if (!init.ok) {
          return syntheticPyOutcome('Python 初始化失败，' + init.error);
        }
        return await execPySession(code, timeoutMs, ctx.conversationId, workspaceRoot);
      } catch (e) {
        return syntheticPyOutcome('Python 运行环境未就绪，' + toolErrorText(e));
      }
    };
    const lane: PyLaneResult = await runPyBounded(ctx.conversationId, timeoutMs, execFn);
    // 未执行短路（busy / 排队取消 / 等待超时）与宽限超时形态：laneNote 即回执主体
    if (!lane.ran || lane.outcome === null) {
      const note: string = lane.laneNote + (noteText === '' ? '' : '\n' + noteText);
      return JSON.stringify({ error: note });
    }
    const outcome: PyExecOutcome = lane.outcome;
    // save() 登记转正（promote 链复用——成功行/失败原因行拼尾注）
    const promoteTail: string = await promoteSavedNames(outcome.savedNames, ctx.conversationId);
    // 安全记录行（audit 头 10 行 + 溢出计数；无事件不出行——减险可观测，非边界承诺）
    let auditTail: string = '';
    if (outcome.audit.length > 0) {
      const shown: string[] = outcome.audit.slice(0, PY_AUDIT_MAX_LINES);
      const moreCount: number = outcome.audit.length - shown.length;
      const lines: string = shown.join('\n') + (moreCount > 0 ? '\n另有 ' + moreCount + ' 条未显示。' : '');
      auditTail = '安全记录（只记录不拦截）：\n' + lines + '\n';
    }
    return composePythonReceipt(outcome, ctx.conversationId, noteText, promoteTail, auditTail);
  }
}

// data 落件名唯一段（py-input-<段>.txt——与 exec-input 家族并行，Python 专属前缀防混读）
let pyInputSeq: number = 0;

function nextPyInputFileName(): string {
  pyInputSeq += 1;
  return 'py-input-' + Date.now() + '-' + pyInputSeq + '.txt';
}

// ── 回执组装（唯一入口；自预算铁律：含信封恒 < 8192）──
// 成功：运行完成（毫秒）+ 输出段（预算内全量 / 超预算溢出信封）+ stderr 警告段 + 尾注三件
//（参数注记 / 转正行 / 安全记录）；失败：固定句 + stderr traceback + 尾注
function composePythonReceipt(outcome: PyExecOutcome, conversationId: string, noteText: string,
  promoteTail: string, auditTail: string): string {
  // 尾注合计先压短（与 JS 同 1024 上限防转正行挤占输出预算）
  const tailText: string = trimToBudget(
    noteText + (noteText !== '' && promoteTail !== '' ? '\n' : '') + promoteTail, 1024);
  const tailPart: string = tailText !== '' ? '\n' + tailText : '';
  const auditPart: string = auditTail !== '' ? '\n' + trimToBudget(auditTail, 1600) : '';
  const head: string = '运行完成（' + outcome.elapsedMs + ' 毫秒）。';
  if (!outcome.ok) {
    if (outcome.error === 'TimeoutError') {
      return trimToBudget('运行失败（等待超时）。已请求中断，中断是协作式的，脚本停在原生调用中时' +
        '不能立即生效，后续 Python 调用会继续排队。', PY_REPLY_HARD_CAP) + tailPart + auditPart;
    }
    if (outcome.error === 'Canceled') {
      return '运行失败（已取消）。' + tailPart;
    }
    if (outcome.error === 'PythonError') {
      // traceback 在 stderr（native PyErr_Print 渲染）；失败路径不呈现 stdout
      const body: string = '运行失败。\n' + (outcome.stderr !== '' ? outcome.stderr : '（无错误信息）');
      return trimToBudget(body, PY_REPLY_HARD_CAP - tailPart.length - auditPart.length - 1) +
        tailPart + auditPart;
    }
    // native 层中文错误句（初始化失败/引导失败/输出收集失败等）
    return trimToBudget('运行失败。\n' + outcome.error,
      PY_REPLY_HARD_CAP - tailPart.length - auditPart.length - 1) + tailPart + auditPart;
  }
  // 成功路径：stdout 预算内直出，超预算落溢出件 + 头尾预览信封
  let outputSeg: string = '';
  let envelope: string = '';
  if (outcome.stdout.length <= PY_EXEC_STDOUT_BUDGET) {
    outputSeg = outcome.stdout;
  } else {
    const spillName: string = nextSpillFileName();
    let spillSaved: string = '';
    try {
      spillSaved = writeWorkspaceTmpTextFile(conversationId, spillName, outcome.stdout);
    } catch (e) {
      spillSaved = '';
    }
    if (spillSaved !== '') {
      // 「已存为」不写「完整输出」：native 收集带上限（PY_STREAM_CAP_CHARS，超限保头截尾 +
      // 溢出标记行），截断发生时文件内是截断后内容——句义恒真（2171 修）
      envelope = '\n输出超过回执上限，已存为临时文件 ' + spillSaved + '，共 ' +
        outcome.stdout.length + ' 字符。\n开头：\n' + trimToBudget(outcome.stdout.substring(0, 2048),
        PY_PREVIEW_CLIP) + '\n结尾：\n' + trimToBudget(outcome.stdout.substring(
        outcome.stdout.length - 2048), PY_PREVIEW_CLIP) +
        '\n继续查看用 exec_output_read，name 传文件名，offset 从 1 起分段读。';
    } else {
      envelope = '\n输出超过回执上限，暂存临时区失败，以下内容不完整。';
      outputSeg = trimToBudget(outcome.stdout, PY_EXEC_STDOUT_BUDGET);
    }
  }
  let body: string = '输出：\n' + (outputSeg !== '' ? outputSeg : '（无输出）');
  if (outcome.stderr !== '') {
    body += '\n提示与警告：\n' + trimToBudget(outcome.stderr, PY_EXEC_STDERR_BUDGET);
  }
  const fixed: number = head.length + 1 + envelope.length + tailPart.length + auditPart.length;
  return head + '\n' + trimToBudget(body, Math.max(PY_REPLY_HARD_CAP - fixed - 1, 1)) +
    envelope + tailPart + auditPart;
}

// ── 自注册面（照 ToolMount 先例：组标签同居本件，ToolTypes 引回入组序 + 调用注册）──
// 组标题（助手工具页独立「Python 运行」卡——拍板：默认关、紧邻脚本工作台、两卡互不联动）
export const TOOL_GROUP_PYTHON: string = 'Python 运行';

export function registerPyTools(): void {
  toolRegistry.register({
    name: TOOL_EXEC_PYTHON,
    group: TOOL_GROUP_PYTHON,
    title: '运行 Python',
    desc: EXEC_PYTHON_DESC,
    parametersJson: EXEC_PYTHON_SCHEMA,
    defaultEnabled: false,
    executor: new ExecPythonExecutor(),
    preflight: execPythonNeedsConfirm
  });
}
