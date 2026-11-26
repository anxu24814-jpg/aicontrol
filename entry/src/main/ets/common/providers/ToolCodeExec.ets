// 脚本工作台两工具（exec_code + exec_output_read 同域）：执行器与 desc / schema。
// ★ 2026-11-16 改题：原「代码工作台」→「脚本工作台」（决明拍板；「代码」语义过宽，本域只含
//   JavaScript 与模拟 Shell 两模式，Python 另有 exec_python 独立域）——本件 desc 与回执里的
//   指路句已随之全文替换；符号名、路由名与文件名不变。
// · import 面：契约自 ToolContracts（禁引 ToolTypes——环事故红线）；引擎与装配走
//   common/codeexec 域件；名称闸 / 清洗与读回组装消费 WorkspaceUtil（工具域 → 纯函数域
//   单向，禁反向）；临时区 IO 面（ensure / 读文本 / 转正编排）全在 store 侧
//   WorkspaceDbTmp / ChatDb（IO 面单源纪律）。
// · 溢出件名：ArkTS 生成 exec-output-<唯一段>.log 并过清洗（sanitize）后经
//   ScriptRunOptions 下发（native 禁自造名）；每次运行至多一件。
// · fs.save 转正：native 只登记（savedNames），落库编排在执行器收尾逐件走
//   promoteWorkspaceTmpFileOp（复用既有链：正式区三闸 + 同名追加序号 + 落该会话助手
//   默认文件夹），结果行拼进回执。
// · ScriptReceipt / ScriptLimits 不并入本件：纯函数域与执行器混居（反碎片下限②书面理由）。
import { codeWorkbenchMode } from '../AppPreferences';
import { ToolExecutor, toolArgsParseErrorText, toolErrorText } from './ToolContracts';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { sanitizeWorkspaceName, workspaceNameRejectReason } from '../WorkspaceUtil';
// 回执组装域外迁 WorkspaceReply，exec_output_read 复用口自新件引
import { composeWorkspaceReadReply } from '../WorkspaceReply';
import { WORKSPACE_TMP_MAX_FILE_BYTES, WORKSPACE_TMP_MAX_TOTAL_BYTES } from '../WorkspaceTmpUtil';
import { ensureWorkspaceTmpConversationDir, readWorkspaceTmpFileText,
  writeWorkspaceTmpTextFile } from '../store/WorkspaceDbTmp';
import { promoteWorkspaceTmpFileOp } from '../store/ChatDb';
import { ScriptRunOptions, ScriptRunResult } from '../codeexec/ScriptEngine';
// 现读封装 direct 映射：mode 与 tier 同点快照（执行前一次取全）；timeout 解析面唯一入口
// resolveScriptTimeoutMs（只缩不扩）
import { resolveScriptTimeoutMs, scriptTierValues, ScriptTierValues,
  ScriptTimeoutResolution, SCRIPT_MODE_JS, SCRIPT_MODE_SHELL } from '../codeexec/ScriptLimits';
// 模拟 Shell 资产装配件（资产源 + JSON 字面量注入；用户文本只作数据——P0 主闸，见
// ShellScript.ets 头注释）
import { composeShellCode } from '../codeexec/ShellScript';
// 执行走调度域 scriptScheduler（跨引擎唯一进口——排队 FIFO / 会话归属取消 / settle 驱动
// 推进在其内，本件零引擎感知；取消短路只判 flags canceled——调度器兜底保证取消结果恒带标志）
import { scriptScheduler } from '../codeexec/ScriptEnginePick';
// deadline-hit 判定消费单源常量（单源处更名会静默失配）
import { SCRIPT_FLAG_DEADLINE_HIT } from '../codeexec/ScriptScheduler';
import { ScriptHttpRunContext, scriptHttpWaitMs } from '../codeexec/ScriptHttpBridge';
import { composeCanceledReceipt, composeScriptReceipt, composeTimeoutReceipt,
  scriptTimeoutClampText } from '../codeexec/ScriptReceipt';

// ── desc（请求侧 description，四段：调用时机 / 用法 / 数值自述 / 划界。★ 数值与划界句
//    不得删；方法名与桥名清单不得缺项——317 组关系钉守〔native 源 ↔ desc〕；对外表述：
//    模拟 Shell 语义解释器可用「模拟 Shell」族并明示非系统终端，JS 模式恒「运行脚本」）──
//    ★ 并发契约：并发句三个数字为字面联动、无机制联动——2 ↔ SCRIPT_MAX_CONCURRENT、
//    3 ↔ SCRIPT_QUEUE_MAX_WAITING、30 秒 ↔ SCRIPT_QUEUE_WAIT_MAX_MS；翻常量时须同笔手改
//    并发句（BLOCKED 1770 第 5 项「desc 首句随形删」口径在并发句改长后 = 改写「两个」并删
//    排队段）──
export const EXEC_CODE_DESC: string =
  '需要计算、转换、批量处理文本时用。code 是完整可运行的 JavaScript，不支持模块导入。' +
  '用 httpGet(url, opts) 发网络请求，opts 可带 method 与 body 指定请求方法与请求体，method ' +
  '只支持 GET、POST、PUT、DELETE 与 PATCH 五种，不填时发 GET。写请求需要在 设置 → 工具调用 ' +
  '→ 脚本工作台 里开启后才可用。网络请求的域名范围由用户设置，默认只允许已添加的域名及其' +
  '子域名，清单在助手编辑页的「脚本联网域名」卡与 设置 → 工具调用 → 脚本工作台 → 脚本联网' +
  '域名 里配置，两边一起生效，也可以在该页放开为任何域名。未获允许的域名会当场报错。响应' +
  '是文本时返回字符串，是二进制时返回 ' +
  'Uint8Array。用 console.log 输出过程信息，用 result(值) 返回最终结果。不调用 result 时返回最后' +
  '一行表达式的值，末值是 Promise 时会等它完成再取结果。一个脚本内部是串行执行的。脚本不' +
  '提供 setTimeout、fetch、XMLHttpRequest 与 Worker，httpGet 会阻塞到响应返回后才继续执' +
  '行，循环里发多个请求时只能等前一个返回再发下一个。Promise.then 之类的微任务回调在主代' +
  '码执行期间不会运行，要到主代码跑完后才统一结算，不要用它们调度或等待任务。data 可选，传' +
  '入的文本会先存成临时' +
  '区文件，文件名以 exec-input 开头并随回执给出，脚本里用 fs.read 或 fs.readBytes 读取，要放' +
  '长文本时用它，不必把内容嵌进 code 字符串。timeout 可选，单位秒，给这次运行设更短的等待，' +
  '最短 1 秒，上限是当前档位的时限，不传用档位默认。应用可以同时运行两个脚本，刚超时的脚本' +
  '可能仍占着位置。更多的调用会排队等待。等待位最多 3 个，队列已满时新的调用会立刻被拒绝。' +
  '排队的调用最多等 30 秒，等不到空位就放弃执行。被拒绝或放弃的调用都会收到错误回执，本次' +
  '不会运行，需要重新发起。脚本里的 fs 只能看见本会话的临时' +
  '区，包含 list、read、readBytes、write、append、exists、save，list 返回摘要文本不是数组。' +
  '同一会话里两个脚本同时写同一个文件时，后写的会覆盖先写的。' +
  '文本按 UTF-8 读写，非法字节' +
  '在 read 时会显示为替换符，读原始字节用 readBytes。write 与 append 的内容可以是字符串，也' +
  '可以是 Uint8Array 等字节数组。脚本内置 TextEncoder、TextDecoder、atob、btoa 与 md5、' +
  'sha1、sha256、zlibCompress、zlibDecompress 工具函数，还有 hexEncode、hexDecode、' +
  'b64Encode、b64Decode 与 csvParse 五个小函数。fs.save 把文件转存进文件工作区。单' +
  '次运行上限为标准档 10 秒、内存 64 MB，严格档 5 秒、32 MB。结果与日志在回执里合计约 ' +
  '8 KB，严格档合计 4 KB，超出回执只显示开头与结尾。完整输出存成临时文件，可用 ' +
  'exec_output_read 分页读取，临时文件上限 10 MB，再超出只保留前面部分。当前档位在 ' +
  '设置 → 工具调用 → 脚本工作台 ' +
  '里切换。要读写文件工作区里的正式文件，用 workspace_list / workspace_read / workspace_' +
  'write，脚本的 fs 看不到它们。要把文件工作区里的文件交给脚本处理，用 workspace_' +
  'stage 把它放进临时区。要看脚本输出文件，用 exec_output_read。要上传文件，用 http_request ' +
  '工具。脚本里的 httpGet 默认只发 GET，开启写请求授权后可以发 POST、PUT、DELETE 与 PATCH。' +
  '产物长期保留用 ' +
  'fs.save，或让用户在文件工作区管理页转存。' +
  '需要跑受限的 shell 脚本时，给 mode 传 shell，此时 code 是一段模拟 Shell 脚本，由应用' +
  '内置的受限命令解释器执行，不是系统终端，也不启动任何系统程序。模拟 Shell 支持管道、' +
  '&& 与 ||、单双引号、> 与 >> 重定向、$name 变量与 * 和 ? 通配符，命令限内置注册表，' +
  '传 help 查看全部命令与用法，例如 echo、ls、cat、grep、sort、wc、du。边界：不支持 sed、' +
  'awk、jq，不支持循环与命令替换，未知命令或不支持的语法会整段拒绝且一条命令都不执行，' +
  'grep 固定文字用 -F、正则用 -E，模拟 Shell 不提供网络命令，mkdir、rm 与 mv 暂不支持。模拟 Shell ' +
  '固定 5 秒时限、32 MB 内存与约 4 KB 回执输出，不随运行档位切换变化，超时与取消走同一套机制。';

// ★ desc 含「本会话工具输出」语义——超 8K 工具结果经 ToolResultSpill 落同一临时区（信封
// 指路到本工具），不只服务 exec_code 溢出件
export const EXEC_OUTPUT_READ_DESC: string =
  '分页读取本会话临时区里的文件，主要是 exec_code 超长输出与超长工具结果存下的临时文件。' +
  'name 取自 exec_code 回执给出的输出文件名，或超长工具结果回执给出的文件名。offset 是起始行号，' +
  '从 1 起，limit 是本次最多读取的行数，col 是行内' +
  '起始字符位置，续读被截断的长行时用。返回会注明总行数与继续读取的位置。要读文件工作区里的' +
  '正式文件用 workspace_read，本工具看不到它们。';

// ── schema（JSON Schema 原串——exec_code 四参数〔code 必填 + data 与 timeout 与 mode 可选；
//    timeout 逐调用钳制在 [1, 生效档位时限] 只缩不扩——决明拍板，推翻方案 §3.2 原「不加
//    覆盖位」判据；mode 加 'js' 缺省 / 'shell'，required 仍仅 code——mode 必可选〕；
//    exec_output_read 四参数行级分页与 workspace_read 逐字同源）──
export const EXEC_CODE_SCHEMA: string = '{"type":"object","properties":{' +
  '"code":{"type":"string","description":"完整可运行的 JavaScript 源码。不支持模块导入。用 ' +
  'httpGet(url, opts) 发网络请求取内容，opts 可带 method 与 body，方法限 GET、POST、PUT、' +
  'DELETE 与 PATCH，写请求需在设置里开启。域名范围由用户设置，默认只允许已添加的域名及其' +
  '子域名，也可以放开为任何域名。清单在助手编辑页或 设置 → 工具调用 → 脚本工作台 里配置，' +
  '两边一起生效。未获允许的域名会当场报错。用 console.log 输出' +
  '过程信息，用 result(值) 返回最终结果。mode 传 shell 时，code 是一段模拟 Shell 脚本，' +
  '用 help 查看内置命令。"},' +
  '"data":{"type":"string","description":"可选的文本数据。会先存成临时区文件，文件名以 ' +
  'exec-input 开头并随回执给出，脚本里用 fs.read 或 fs.readBytes 读取。长文本走这里传，' +
  '不传则不创建文件。"},' +
  '"timeout":{"type":"number","description":"可选的本次等待秒数，给这次运行设更短的等待。' +
  '最短 1 秒，上限是当前档位的时限，超出范围自动钳制并在回执里说明。不传用档位默认。"},' +
  '"mode":{"type":"string","enum":["js","shell"],"description":"可选的执行模式。js 是' +
  '缺省，code 按 JavaScript 运行。shell 表示 code 是一段模拟 Shell 脚本，由应用内置的' +
  '受限命令解释器执行，不是系统终端，可用命令传 help 查看。"}},' +
  '"required":["code"]}';

export const EXEC_OUTPUT_READ_SCHEMA: string = '{"type":"object","properties":{' +
  '"name":{"type":"string","description":"本会话临时区里的文件名，取自 exec_code 回执给出的' +
  '输出文件名。"},' +
  '"offset":{"type":"number","description":"起始行号，从 1 起，不传则从第 1 行读。"},' +
  '"limit":{"type":"number","description":"本次最多读取的行数，不传则读到长度上限。"},' +
  '"col":{"type":"number","description":"行内起始字符位置，从 1 起，不传则从行首读。可随时' +
  '主动指定，从该位置起读。继续读取被截断的超长行时，按返回的指引传入。"}},' +
  '"required":["name"]}';

// args 解析取串 / 取数（工具域惯用小件——ToolWorkspace 同款私有形态，3 行取值不跨文件共享）
function argsString(parsed: Record<string, Object>, key: string): string {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'string' ? raw : '';
}

function argsNumber(parsed: Record<string, Object>, key: string): number {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'number' ? raw : Number.NaN;
}

// 总开关拦截句常量已随总开关退役（声明面无此件即无执行面，勿找回）
// 溢出件名唯一段（exec-output-<段>.log——毫秒时间戳 + 自增序号，进程内唯一够用；清洗保证
// 落临时区的名恒过闸）。门 4 起 exec_python 溢出件共用本命名面（同族文件名，消费口同为
// exec_output_read——单源不另开计数器）
let spillSeq: number = 0;

export function nextSpillFileName(): string {
  spillSeq += 1;
  return sanitizeWorkspaceName('exec-output-' + Date.now() + '-' + spillSeq + '.log');
}

// 日志收集条数上限（★ 收集与回执两预算分离——收集字节预算已扩至落盘单件闸 10 MB，条数
// 防线只防病态超短行撑大 logs vector；正常长输出由字节预算与落盘闸承载。唯一消费点 =
// 本件 options 组装）
const SCRIPT_LOG_MAX_LINES: number = 20000;

// data 落件名唯一段（exec-input-<毫秒时间戳>-<自增序号>.txt——与溢出件命名同构；清洗保证
// 落临时区的名恒过闸）
let inputSeq: number = 0;

function nextExecInputFileName(): string {
  inputSeq += 1;
  return sanitizeWorkspaceName('exec-input-' + Date.now() + '-' + inputSeq + '.txt');
}

// fs.save 转正编排（savedNames 逐件过既有链；结果行拼回执——成功给终名，失败如实给原因）。
// 门 4 起 exec_python 的 save() 登记转正共用本编排（同一 promote 链零第二实现）
export async function promoteSavedNames(savedNames: string[], conversationId: string): Promise<string> {
  const lines: string[] = [];
  for (const name of savedNames) {
    try {
      const outcome = await promoteWorkspaceTmpFileOp(conversationId, name);
      if (outcome.ok) {
        lines.push('已转存为文件工作区文件「' + outcome.displayName + '」。');
      } else {
        lines.push('转存「' + name + '」失败。' + outcome.errorText);
      }
    } catch (e) {
      lines.push('转存「' + name + '」失败。' + toolErrorText(e));
    }
  }
  return lines.length > 0 ? '\n' + lines.join('\n') : '';
}

// ── exec_code 执行器 ──
export class ExecCodeExecutor implements ToolExecutor {
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    // 执行模式解析：mode 可选——'js' 缺省 / 'shell'，与用户档位正交（档位快照仍走
    // modeAtRun）；undefined 与空串归缺省 'js'；其余非法值 = 中文错误回执且脚本不执行
    // （P0-1 禁静默回落）；字符串比较走 modeText 窄化防类型擦边
    const modeRaw: Object | undefined = parsed['mode'];
    let execMode: string = SCRIPT_MODE_JS;
    if (modeRaw !== undefined) {
      if (typeof modeRaw !== 'string') {
        return JSON.stringify({ error: 'mode 只支持字符串 js 或 shell，当前收到的是 ' + typeof modeRaw + '。' });
      }
      const modeText: string = modeRaw;
      if (modeText !== '' && modeText !== SCRIPT_MODE_JS && modeText !== SCRIPT_MODE_SHELL) {
        return JSON.stringify({ error: 'mode 只支持 js 与 shell，当前收到的是 ' + modeText + '。' });
      }
      if (modeText !== '') {
        execMode = modeText;
      }
    }
    const code: string = argsString(parsed, 'code');
    if (code.trim() === '') {
      return JSON.stringify({ error: execMode === SCRIPT_MODE_SHELL ?
        'code 不能为空，请传入完整的模拟 Shell 脚本。' :
        'code 不能为空，请传入完整可运行的 JavaScript 源码。' });
    }
    if (ctx.conversationId === '') {
      return JSON.stringify({ error: '脚本工作台只在会话中可用，当前执行上下文没有会话。' });
    }
    // data / timeout 类型检查：纯检查无副作用——类型错即错误回执、脚本不执行（P0-1
    // 禁静默兜底，不照 argsString 惯例吞成空串/NaN）
    const dataRaw: Object | undefined = parsed['data'];
    if (dataRaw !== undefined && typeof dataRaw !== 'string') {
      return JSON.stringify({ error: 'data 只支持字符串，当前收到的是 ' + typeof dataRaw + '。' });
    }
    const dataText: string = typeof dataRaw === 'string' ? dataRaw : '';
    const timeoutRaw: Object | undefined = parsed['timeout'];
    if (timeoutRaw !== undefined && typeof timeoutRaw !== 'number') {
      return JSON.stringify({ error: 'timeout 只支持数值，单位秒，当前收到的是 ' + typeof timeoutRaw + '。' });
    }
    // 临时区就绪 + 拿绝对根（ensure 返回目录路径——目录懒建容已在场，EEXIST 容错在 store 侧）
    let workspaceRoot: string = '';
    try {
      workspaceRoot = ensureWorkspaceTmpConversationDir(ctx.conversationId);
    } catch (e) {
      return JSON.stringify({ error: '临时区目录未就绪：' + toolErrorText(e) });
    }
    // 档位快照一次取全（★ D10 修复实锤：原先 tier 执行前读、mode 执行后再读，两次独立读
    // 之间隔着整个脚本执行——用户在脚本跑的十秒里切档，超时回执会出现「等待了 10 秒」+
    // 「超过 5 秒仍未结束」的自相矛盾文案。现 mode 与 tier 同点快照，超时句秒数与实际等待
    // 恒同档；脚本执行中切档仍只对下一次生效，契约不变）
    const modeAtRun: string = codeWorkbenchMode();
    // JS 模式档位数值组（D10 快照语义不变——js 路径保留此字面调用形态，316 组 D10 钉守）
    let tier: ScriptTierValues = scriptTierValues(modeAtRun);
    // shell 分派键与数值组（与档位快照显式分家——'shell' 不得塞回 modeAtRun〔防档位快照
    // 语义污染〕；shell 恒 QuickJS〔ScriptEnginePick 短路，不消费引擎开关〕+
    // scriptTierValues('shell') = 严格档数值组；两条独立映射调用、禁合并成单点）
    let dispatchKey: string = modeAtRun;
    if (execMode === SCRIPT_MODE_SHELL) {
      dispatchKey = SCRIPT_MODE_SHELL;
      tier = scriptTierValues(dispatchKey);
    }
    // timeout 解析：可选、只缩不扩——档位是用户面安全设置，模型不得绕过；在档位快照之后
    // 解析，不引入新的读档点（D10 快照语义不变）；越钳说明句随尾注
    let timeoutMs: number = tier.timeoutMs;
    let clampNote: string = '';
    if (timeoutRaw !== undefined) {
      const resolved: ScriptTimeoutResolution =
        resolveScriptTimeoutMs(typeof timeoutRaw === 'number' ? timeoutRaw : Number.NaN,
          tier.timeoutMs);
      timeoutMs = resolved.timeoutMs;
      clampNote = scriptTimeoutClampText(resolved.clampedLow, resolved.clampedHigh, tier.timeoutMs);
    }
    // data 落件：空串视同未提供；越限/IO 失败 = 中文错误回执且脚本不执行（P0-1 不给脚本造
    // 「存在但读不回」的死件；闸拒时 toolErrorText 即中文闸句本身）
    let dataNote: string = '';
    if (dataText !== '') {
      const inputName: string = nextExecInputFileName();
      let savedName: string = '';
      try {
        savedName = writeWorkspaceTmpTextFile(ctx.conversationId, inputName, dataText);
      } catch (e) {
        return JSON.stringify({ error: toolErrorText(e) });
      }
      // 读取指引按执行模式分支（模拟 Shell 里没有 fs 全局——原句照 JS 口径写 fs.read，
      // shell 模型照做会吃「不支持命令」拒绝，白费一轮）
      dataNote = execMode === SCRIPT_MODE_SHELL ?
        '输入数据已存入临时区文件 ' + savedName + '，脚本里用 cat 读取。' :
        '输入数据已存入临时区文件 ' + savedName + '，脚本里用 fs.read 或 fs.readBytes 读取。';
    }
    // 参数注记（data 落件句 / timeout 钳制句，'\n' 分隔——超时/取消两短路与成功/失败尾注共用）
    const noteParts: string[] = [];
    if (dataNote !== '') {
      noteParts.push(dataNote);
    }
    if (clampNote !== '') {
      noteParts.push(clampNote);
    }
    const noteText: string = noteParts.join('\n');
    const options: ScriptRunOptions = {
      workspaceRoot: workspaceRoot,
      timeoutMs: timeoutMs,
      maxHeapBytes: tier.maxHeapBytes,
      maxOutputChars: tier.maxOutputChars,
      maxLogLines: SCRIPT_LOG_MAX_LINES,
      tmpMaxFileBytes: WORKSPACE_TMP_MAX_FILE_BYTES,
      tmpMaxTotalBytes: WORKSPACE_TMP_MAX_TOTAL_BYTES,
      outputFileName: nextSpillFileName(),
      // 沙箱网络桥等待上限（算式单源 ScriptHttpBridge.scriptHttpWaitMs——档位时限与用户上限
      // 档取小 + 调度余量；用的是档位时限 tier.timeoutMs 而非本跑生效 timeout——桥等待上界
      // 跟档位走，与 timeout 参数只缩等待无关）
      httpWaitMs: scriptHttpWaitMs(tier.timeoutMs)
    };
    // 沙箱网络桥运行上下文（执行上下文快照 + scope 透传 + 档位时限——桥据此做域名闸归属
    // 与超时封顶；必传，未授权域名由桥给中文错误而非不给函数）
    const httpCtx: ScriptHttpRunContext = {
      scope: ctx.scope,
      conversationId: ctx.conversationId,
      assistantId: ctx.assistantId,
      runId: ctx.runId,
      tierTimeoutMs: tier.timeoutMs
    };
    // 执行码组装：js 模式原样（现状逐字不变）；shell 模式 = 资产源 + JSON 字面量注入——
    // 用户文本只作数据进解释器实参，永不进入可执行位置（P0 主闸）；资产读取失败 = 中文
    // 错误回执且脚本不执行，禁静默降级
    let runCode: string = code;
    if (execMode === SCRIPT_MODE_SHELL) {
      try {
        runCode = await composeShellCode(code);
      } catch (e) {
        // 早退同样携参数注记（E3a-01 同族）：此刻 data 已落件、timeout 可能已被钳制——
        // 不带注记会让模型不知输入已存件、重试再带 data 重复落件
        return JSON.stringify({ error: '模拟 Shell 组件未就绪，本次调用没有执行：' +
          toolErrorText(e) + (noteText === '' ? '' : '\n' + noteText) });
      }
    }
    const result: ScriptRunResult =
      await scriptScheduler().runBounded(runCode, options, dispatchKey, httpCtx);
    // 判定表序 2：计时器先到（native 结果后到即丢弃——秒数句用生效超时，缺省 = 档位快照、
    // timeout 参数 = 钳制后值，两处同值单点；SCRIPT_FLAG_DEADLINE_HIT 单源 = ScriptScheduler）
    if (result.flags.indexOf(SCRIPT_FLAG_DEADLINE_HIT) >= 0) {
      return JSON.stringify({ error: composeTimeoutReceipt(timeoutMs, timeoutMs) +
        (noteText === '' ? '' : '\n' + noteText) });
    }
    // 判定表序 3：取消（调度器保证取消结果恒带 canceled 标志——条目级标记兜底补记）
    if (result.flags.indexOf('canceled') >= 0) {
      return JSON.stringify({ error: composeCanceledReceipt() +
        (noteText === '' ? '' : '\n' + noteText) });
    }
    // 尾注 = 参数注记（data 落件句 / timeout 钳制句）+ fs.save 转正行（noteText 为空时
    // receiptTail === promoteTail——既有行为逐字不变）
    const promoteTail: string = await promoteSavedNames(result.savedNames, ctx.conversationId);
    const receiptTail: string = noteText + promoteTail;
    return composeScriptReceipt(result, receiptTail);
  }
}

// ── exec_output_read 执行器（分页读临时区件——读回组装与 workspace_read 逐字同源：
//    composeWorkspaceReadReply 单源复用，行级 offset / limit / col 语义零第二实现；归一
//    全在该纯函数内收口，本执行器传模型原值不预处理）──
export class ExecOutputReadExecutor implements ToolExecutor {
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const name: string = argsString(parsed, 'name');
    const reject: string = workspaceNameRejectReason(name);
    if (reject !== '') {
      return JSON.stringify({ error: reject });
    }
    if (ctx.conversationId === '') {
      return JSON.stringify({ error: '本工具只在会话中可用，当前执行上下文没有会话。' });
    }
    let content: string = '';
    try {
      content = readWorkspaceTmpFileText(ctx.conversationId, name);
    } catch (e) {
      return JSON.stringify({ error: '临时文件「' + name + '」不存在或读取失败：' +
        toolErrorText(e) });
    }
    return composeWorkspaceReadReply(name, content, argsNumber(parsed, 'offset'),
      argsNumber(parsed, 'limit'), '', argsNumber(parsed, 'col'));
  }
}
