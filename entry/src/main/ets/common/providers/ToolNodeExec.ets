// exec_node 工具（2026-11-23 鸿蒙 Node 运行时门 2 U4a 笔，任务书-鸿蒙Node运行时门2-20261123
// §3.4 全文 + §4 S4-1）：真实 Node.js 会话内执行器 + desc / schema / 确认预检 + 自注册面
//（照 ToolPyExec 母版——组标签同居本件，ToolTypes 只接线）。
// · 与 exec_python / exec_code 的关系：另一执行域，不进 exec_code 模式枚举、不并入
//   exec_python；复用同一临时区（会话目录即 Node cwd）、同一溢出件命名面（nextSpillFileName）、
//   同一 promote 转正链（save() 登记 → savedNames → promoteSavedNames）。三卡互不联动。
// · 执行只走 nodeexec 域的 executeNodeCode（lane / 代次 / 槽位释放单点在 NodeScheduler，
//   本件零排队逻辑）；data 落件在 onLaneAdmitted 回调内（排队拒绝与取消不提前落文件）；
//   cancel 挂 ToolRuntime.cancelAllPending（cancelNodeForConversation），删除级联走
//   dropNodeForConversation（ChatDb / AssistantDb 两处）。
// · read_output 动作：不启动 Node、不经 lane、不弹执行确认——复用 readWorkspaceTmpFileText +
//   composeWorkspaceReadReply（与 exec_output_read 同语义，只读本会话临时区）。
// · install 动作（门 3 U2，方案档 ②④⑦）：spec 闸本层预检 + Node 侧兜底双守；预检不可逆档
//   直回人工卡（不经 routeConfirmPrompt——高效档全直通对不可逆安装不适用）；执行走
//   NodeScheduler.installNodePackages 单飞路径（sessionId = conversationId 归属键）；容量闸
//   与安装台账在 Node 侧 npm-worker（quota-exceeded 等错误码由回执文案映射）。
// · run_bin 动作（门 3 U3，任务书代决表第 2 项）：运行已装包提供的命令行工具——本层只做参数
//   互斥与上限预检（bin 无空白、args ≤16 条每条 ≤200 字符、timeout 同 exec），执行走
//   NodeScheduler.executeNodeBin（同 lane 同取消代次同会话隔离）；确认档 = write（与 exec
//   同档，不新增不可逆档）。回执如实报退出码与提供方；CJS-only 由 Node 侧 bin-runner 判定。
// · 待重启守卫（门 4，旗在 nodeexec/NodeAdmin）：管理页清空安装包 / 重建运行区后、应用重启前，
//   exec / install / run_bin 三动作一律拒——确认预检不构造卡（返 null 直通到执行器），执行器在
//   会话校验后直接回与调度层同形的拒绝文案；不进 lane、不发请求。read_output 只读临时区，不受守卫。
// · 产物口径（任务书 §0 代决表）：只在拿到 Node 回执且 savedNames 非空时 promote——脚本
//   错误前已 save 的照常转正；超时 / 取消 / lane 未执行不转正（回执侧也不带 savedNames）。
// · 安全面口径：应用沙箱内执行，未设网络与文件强边界；审计事件只作可观测，不是安全边界。
//   崩溃（process.abort / V8 原生崩溃）可能拖垮应用，desc 与帮助写明需重启应用恢复。
// · import 面：契约自 ToolContracts / ConfirmRouting / AppPreferences（预检三件）；执行编排
//   走 nodeexec/NodeScheduler；临时区 IO 面在 store 侧 WorkspaceDbTmp；回执复用件自
//   ToolCodeExec 导出面（溢出命名与 promote 单源）。
import { ConfirmPrompt, CONFIRM_LEVEL_IRREVERSIBLE, CONFIRM_LEVEL_WRITE,
  CONFIRM_ROUTE_HUMAN, ToolExecutor, toolArgsParseErrorText,
  toolErrorText } from './ToolContracts';
import { routeConfirmPrompt } from './ConfirmRouting';
import { dataApproveMode } from '../AppPreferences';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { executeNodeBin, executeNodeCode, installNodePackages, NODE_BIN_ARG_MAX_LENGTH,
  NODE_BIN_ARGS_MAX, NODE_EXEC_DEFAULT_TIMEOUT_MS, NODE_EXEC_MAX_TIMEOUT_S, NODE_EXEC_MIN_TIMEOUT_S,
  NODE_LANE_QUEUE_MAX_WAITING, NODE_LANE_QUEUE_WAIT_MAX_MS, NodeBinRequest, NodeExecReceipt,
  NodeExecRequest, NodeInstallReceipt, NodeLaneAdmitContext } from '../nodeexec/NodeScheduler';
import { nodeNeedsRestart, nodeRestartGuardText } from '../nodeexec/NodeAdmin';
import { ensureWorkspaceTmpConversationDir, readWorkspaceTmpFileText,
  writeWorkspaceTmpTextFile } from '../store/WorkspaceDbTmp';
import { composeWorkspaceReadReply } from '../WorkspaceReply';
import { workspaceNameRejectReason } from '../WorkspaceUtil';
import { nextSpillFileName, promoteSavedNames } from './ToolCodeExec';

// 工具 id（常量归口 ToolIds，此处引回注册）
import { TOOL_EXEC_NODE } from './ToolIds';
import { toolRegistry } from './ToolRegistry';

// ── 限额常量（默认超时与 1~300 秒区间单源 = NodeScheduler；本件只用不另写数值）──
// stdout 回执预算（超出整段落盘溢出件，回执只留头尾预览；总回执恒 < 8191 与 Python / JS 同铁律）
const NODE_EXEC_STDOUT_BUDGET: number = 5000;
// stderr 回执预算（成功路径的提示与警告截断；失败路径走整段预算）
const NODE_EXEC_STDERR_BUDGET: number = 1200;
// 回执硬顶（含信封恒 < 8192，留 1 字符余量）
const NODE_REPLY_HARD_CAP: number = 8191;
// 头尾预览截断（溢出信封内）
const NODE_PREVIEW_CLIP: number = 1024;
// 安全记录行上限（审计 events 最多保留 50 条，回执只显头 10 行防挤占输出预算）
const NODE_AUDIT_MAX_LINES: number = 10;
// 确认卡代码摘要上限（压缩空白后取开头；与 ToolPyExec 同 300 字口径）
const NODE_CONFIRM_DETAIL_MAX: number = 300;
// 尾注合计上限（与 JS / Python 同 1024——防转正行挤占输出预算）
const NODE_TAIL_BUDGET: number = 1024;
// 安全记录段上限（照 Python 1600）
const NODE_AUDIT_BUDGET: number = 1600;
// 顶层 {error} 回执的正文预算（JSON 信封 {"error":"…"} 约 12 字符 + 转义余量，整体仍 < 8192）
const NODE_ERROR_TEXT_BUDGET: number = 8000;

// 动作值（唯一四值；schema enum 同字面量）
const NODE_ACTION_EXEC: string = 'exec';
const NODE_ACTION_READ_OUTPUT: string = 'read_output';
const NODE_ACTION_INSTALL: string = 'install';
const NODE_ACTION_RUN_BIN: string = 'run_bin';

// ── desc（请求侧 description。★ 前 120 字固定四件：真实 Node.js / 同会话变量保留 /
//    取消或超时重置当前会话 / npm 安装经确认可用；后段写 npm install 开放面、require 写法与
//    执行边界、cwd、save、data、timeout、串行队列、read_output、异步限制、非强隔离、崩溃
//    重启。数字句由上方常量拼接——改常量即同步）──
export const EXEC_NODE_DESC: string =
  '需要在手机上真实运行 Node.js 代码时用。这是完整的 Node.js 24.22.3 运行时，同一会话变量' +
  '跨轮保留，取消或超时只重置当前会话，其他会话不受影响。npm 安装经确认后可用，action 传 ' +
  'install 并在 specs 里逐条给出 name@精确版本，每次安装都会先弹确认卡，允许后才执行。' +
  '只装纯 JS 包，安装时不执行包自带的脚本，装好的 CommonJS 包在同一会话里直接 require 可用。' +
  '装好的包如果带命令行工具，action 传 run_bin、bin 传命令名、args 传参数数组，可以在当轮跑一次，' +
  '退出码随回执给出，只支持 CommonJS 入口，跑完会重建运行环境，之前 exec 里的变量不再保留。' +
  'npx 与 npm run 暂未开放。' +
  'code 是完整可运行的 Node.js 源码，可 require 内置模块。没有 result()，结果用 console.log ' +
  '或 print 输出，最后一行表达式不会自动显示。按 CommonJS 执行，顶层 await、ESM 与动态 ' +
  'import 不可用。子进程执行未开放。全局 crypto 是 WebCrypto，哈希走 require(\'crypto\')。' +
  '每次运行的当前目录是本会话的临时区，先 require(\'fs\') 再读写相对路径的文件都落在这里，' +
  '这只是默认目录，不是文件沙箱。要把产物长期保留进文件工作区，在代码里调 save(文件名)，' +
  '执行结束后自动转存并在回执里说明。data 可选，传入的文本会先存成临时区文件，文件名以 ' +
  'node-input 开头并随回执给出，代码里先 require(\'fs\') 再读取，长数据走这里传，不必嵌进 ' +
  'code。timeout 可选，单位秒，最短 ' + NODE_EXEC_MIN_TIMEOUT_S + ' 秒，' +
  '上限 ' + NODE_EXEC_MAX_TIMEOUT_S + ' 秒，不传按 ' + (NODE_EXEC_DEFAULT_TIMEOUT_MS / 1000) +
  ' 秒。Node 一次只跑一段代码，后续调用排队，等待位 ' + NODE_LANE_QUEUE_MAX_WAITING +
  ' 个，排队超过 ' + (NODE_LANE_QUEUE_WAIT_MAX_MS / 1000) + ' 秒会放弃并报错。输出过长会存成' +
  '临时文件，用本工具的 read_output 动作分页读取，action 传 read_output，name 传文件名，' +
  'offset 从 1 起分段读。同一会话里重复声明同名 let 或 const 会报错，改用赋值即可。后台任务' +
  '要在当轮 await 完成，没 await 的网络或文件操作会让本轮按后台残留处理并重置当前会话，跨' +
  '会话的相对路径落点不保证；本轮新建的定时器会在轮末清掉。Node 运行在应用沙箱内，没有网络' +
  '与文件的强隔离。如果代码让 Node 进程崩溃，需要重启应用才能恢复。';

// ── schema（action 可选，缺省 exec；现有校验器不处理条件 required，故 code 与 name 与
//    specs 的条件必填由执行器 fail-closed 兜底——exec 要求非空 code，read_output 要求合法
//    name，install 要求逐条合法 specs）──
export const EXEC_NODE_SCHEMA: string = '{"type":"object","properties":{' +
  '"action":{"type":"string","enum":["exec","read_output","install","run_bin"],"description":"可选的动作。exec ' +
  '是缺省，运行 code。read_output 读取本会话临时区里的文件，此时只需 name 与可选的行级定位。' +
  'install 从 npm 官方源安装纯 JS 包，此时只需 specs。run_bin 运行已装包提供的命令行工具，' +
  '此时只需 bin 与可选 args。四种动作的参数不能混用。"},' +
  '"code":{"type":"string","description":"完整可运行的 Node.js 源码，action 为 exec 时必填。' +
  '当前目录是本会话临时区，相对路径读写落在这里。变量在同一会话内跨轮保留。调 save(文件名)' +
  '把产物登记转存进文件工作区。"},' +
  '"data":{"type":"string","description":"可选的文本数据，只在 exec 时可用。会先存成临时区' +
  '文件，文件名以 node-input 开头并随回执给出，代码里先 require(\'fs\') 再读取。长数据走' +
  '这里传，不传则不创建文件。"},' +
  '"timeout":{"type":"number","description":"可选的本次等待秒数，只在 exec 时可用。最短 ' +
  NODE_EXEC_MIN_TIMEOUT_S + ' 秒，上限 ' + NODE_EXEC_MAX_TIMEOUT_S + ' 秒，超出范围自动' +
  '钳制并在回执里说明。不传按 ' + (NODE_EXEC_DEFAULT_TIMEOUT_MS / 1000) + ' 秒。"},' +
  '"name":{"type":"string","description":"本会话临时区里的文件名，action 为 read_output 时' +
  '必填。取自 exec_node 回执给出的输出文件名，以 exec-output 或 node-input 开头。"},' +
  '"offset":{"type":"number","description":"起始行号，从 1 起，不传则从第 1 行读。只在 ' +
  'read_output 时可用。"},' +
  '"limit":{"type":"number","description":"本次最多读取的行数，不传则读到长度上限。只在 ' +
  'read_output 时可用。"},' +
  '"col":{"type":"number","description":"行内起始字符位置，从 1 起，不传则从行首读。继续 ' +
  '读取被截断的超长行时用。只在 read_output 时可用。"},' +
  '"specs":{"type":"array","items":{"type":"string"},"description":"安装清单，action 为 ' +
  'install 时必填。逐条 name@精确版本，例如 semver@7.6.3。只支持纯 JS 包，范围版本、' +
  '标签、git 与网址一律拒绝。每次安装都要先经用户确认。"},' +
  '"bin":{"type":"string","description":"命令行工具名，action 为 run_bin 时必填。取自装好的包' +
  '提供的命令，例如安装 semver 后传 semver。"},' +
  '"args":{"type":"array","items":{"type":"string"},"description":"可选参数列表，只在 run_bin ' +
  '时可用，最多 ' + NODE_BIN_ARGS_MAX + ' 条，每条不超过 ' + NODE_BIN_ARG_MAX_LENGTH + ' 字符。' +
  '例如 semver 传 7.8.5，回执输出这个版本。"}}}';

// 确认卡主因句（拍板口径：如实写边界，不承诺沙箱与进程隔离）
const NODE_CONFIRM_TEXT: string =
  '运行 Node.js 代码。代码在应用沙箱内执行，未设网络与文件强边界。';

// install 确认卡主因句（门 3 U2：如实写下载与落点，不承诺沙箱）
const NODE_INSTALL_CONFIRM_TEXT: string =
  '安装 npm 包。从 npm 官方源下载纯 JS 包，写入应用数据目录，安装时不执行包自带的脚本。';

// install 确认卡的 registry 固定来源行（与 npm-worker 参数钉死集同源事实；卡面单源常量）
const NODE_INSTALL_REGISTRY_TEXT: string = '来源 registry.npmjs.org';

// args 取串小件（工具域惯用私有形态）
function argsString(parsed: Record<string, Object>, key: string): string {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'string' ? raw : '';
}

// args 取数（缺省 / 非数值回 NaN——composeWorkspaceReadReply 按缺省处理）
function argsNumber(parsed: Record<string, Object>, key: string): number {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'number' ? raw : Number.NaN;
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

// 受理回调产出的注记载体（ArkTS 闭包不回写外部 let 更稳；cwd 由调度器消费，数据件名给回执）
interface NodeAdmittedInfo {
  dataName: string;
}

// action 值归一（缺省与空串 = exec；其余非法值回空串由调用方报参数错误）
function resolveActionValue(parsed: Record<string, Object>): string {
  const raw: Object | undefined = parsed['action'];
  if (raw === undefined) {
    return NODE_ACTION_EXEC;
  }
  if (typeof raw !== 'string') {
    return '';
  }
  const text: string = raw.trim();
  if (text === '' || text === NODE_ACTION_EXEC) {
    return NODE_ACTION_EXEC;
  }
  if (text === NODE_ACTION_READ_OUTPUT) {
    return NODE_ACTION_READ_OUTPUT;
  }
  if (text === NODE_ACTION_INSTALL) {
    return NODE_ACTION_INSTALL;
  }
  if (text === NODE_ACTION_RUN_BIN) {
    return NODE_ACTION_RUN_BIN;
  }
  return '';
}

// read_output 的动作参数互斥（fail-closed：exec / install / run_bin 专属字段在只读动作里出现即报错）
function readOutputConflictText(parsed: Record<string, Object>): string {
  if (parsed['code'] !== undefined || parsed['data'] !== undefined
    || parsed['timeout'] !== undefined || parsed['specs'] !== undefined
    || parsed['bin'] !== undefined || parsed['args'] !== undefined) {
    return 'action 为 read_output 时不接受 code、data、timeout、specs、bin 与 args，只读 name 与 offset、limit、col。';
  }
  return '';
}

// exec 的动作参数互斥（只读四级定位字段、安装清单与 bin 参数不得混入执行请求）
function execConflictText(parsed: Record<string, Object>): string {
  if (parsed['name'] !== undefined || parsed['offset'] !== undefined
    || parsed['limit'] !== undefined || parsed['col'] !== undefined
    || parsed['specs'] !== undefined || parsed['bin'] !== undefined
    || parsed['args'] !== undefined) {
    return 'action 为 exec 时不接受 name、offset、limit、col、specs、bin 与 args，这些字段只在 read_output、install 或 run_bin 时可用。';
  }
  return '';
}

// install 的动作参数互斥（fail-closed：其余动作专属字段在安装请求里出现即报错，安装只收 specs）
function installConflictText(parsed: Record<string, Object>): string {
  const bannedKeys: string[] = ['code', 'data', 'timeout', 'name', 'offset', 'limit', 'col',
    'bin', 'args'];
  for (const key of bannedKeys) {
    if (parsed[key] !== undefined) {
      return 'action 为 install 时不接受 code、data、timeout、name、offset、limit、col、bin 与 args，' +
        '安装只需 specs 清单。';
    }
  }
  return '';
}

// run_bin 的动作参数互斥（fail-closed：run_bin 只收 bin 与 args，timeout 可选）
function runBinConflictText(parsed: Record<string, Object>): string {
  const bannedKeys: string[] = ['code', 'data', 'name', 'offset', 'limit', 'col', 'specs'];
  for (const key of bannedKeys) {
    if (parsed[key] !== undefined) {
      return 'action 为 run_bin 时不接受 code、data、name、offset、limit、col 与 specs，' +
        '只收 bin、args 与可选的 timeout。';
    }
  }
  return '';
}

// install 的 spec 语法（与 npm-worker specRejectReason 同语义的 ArkTS 预检——Node 侧兜底仍在）
const NODE_SPEC_PLAIN_NAME_RE: RegExp = /^[a-zA-Z0-9][a-zA-Z0-9._-]*$/;
const NODE_SPEC_SCOPED_NAME_RE: RegExp = /^[a-zA-Z0-9][a-zA-Z0-9._-]*\/[a-zA-Z0-9][a-zA-Z0-9._-]*$/;
const NODE_SPEC_EXACT_VERSION_RE: RegExp =
  /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;
// 单次 install 的 spec 数上限（与 npm-worker MAX_SPECS 同值；只防无界载荷）
const NODE_INSTALL_MAX_SPECS: number = 20;

// 单条 spec 拒因（空串 = 通过；只收 name@精确版本，含 @scope 与预发布号）
function nodeSpecRejectReason(spec: string): string {
  if (spec === '') {
    return '安装清单里有空的条目。';
  }
  if (/\s/.test(spec)) {
    return '安装清单里的 ' + spec + ' 含空白字符。';
  }
  const nonRegistryMarkers: string[] =
    ['git+', 'git:', 'github:', 'file:', 'dir:', 'link:', 'http://', 'https://'];
  for (const marker of nonRegistryMarkers) {
    if (spec.indexOf(marker) >= 0) {
      return '安装清单里的 ' + spec + ' 带 ' + marker + ' 源，只支持 npm 官方源的精确版本。';
    }
  }
  const at: number = spec.lastIndexOf('@');
  if (at <= 0) {
    return '安装清单里的 ' + spec + ' 缺精确版本号，格式是 name@精确版本，例如 semver@7.6.3。';
  }
  const pkgName: string = spec.substring(0, at);
  const version: string = spec.substring(at + 1);
  const nameOk: boolean = pkgName.startsWith('@')
    ? NODE_SPEC_SCOPED_NAME_RE.test(pkgName.substring(1))
    : NODE_SPEC_PLAIN_NAME_RE.test(pkgName);
  if (!nameOk) {
    return '安装清单里的 ' + spec + ' 包名不合法。';
  }
  if (!NODE_SPEC_EXACT_VERSION_RE.test(version)) {
    return '安装清单里的 ' + spec + ' 版本必须是精确三段式，范围、标签与别名一律不支持。';
  }
  return '';
}

// specs 数组校验（非空 + 条数上限 + 逐条语法；返回空串 = 全过）
function nodeInstallSpecsRejectReason(specs: string[]): string {
  if (specs.length === 0) {
    return 'action 为 install 时 specs 不能为空，请传入逐条 name@精确版本的安装清单。';
  }
  if (specs.length > NODE_INSTALL_MAX_SPECS) {
    return '单次最多安装 ' + NODE_INSTALL_MAX_SPECS + ' 个包，当前收到 ' + specs.length + ' 个。';
  }
  for (const spec of specs) {
    const reason: string = nodeSpecRejectReason(spec);
    if (reason !== '') {
      return reason;
    }
  }
  return '';
}

// 行级定位三字段类型硬检（非数值一律错参——P0-1 禁静默兜底；NaN 是「未提供」的合法值）
function numberFieldErrorText(parsed: Record<string, Object>, key: string): string {
  const raw: Object | undefined = parsed[key];
  if (raw !== undefined && typeof raw !== 'number') {
    return key + ' 只支持数值，当前收到的是 ' + typeof raw + '。';
  }
  return '';
}

// 超时解析（exec 与 run_bin 同口径：缺省 = 120 秒；显式值钳制到 1~300 秒并在回执尾注说明；
// 类型错直接拒——数值单源 = NodeScheduler 三常量）
interface NodeTimeoutDecision {
  timeoutMs: number;
  clampNote: string;
  error: string;
}

function resolveNodeToolTimeout(parsed: Record<string, Object>): NodeTimeoutDecision {
  const raw: Object | undefined = parsed['timeout'];
  if (raw !== undefined && typeof raw !== 'number') {
    return {
      timeoutMs: NODE_EXEC_DEFAULT_TIMEOUT_MS,
      clampNote: '',
      error: 'timeout 只支持数值，单位秒，当前收到的是 ' + typeof raw + '。'
    };
  }
  if (raw === undefined) {
    return { timeoutMs: NODE_EXEC_DEFAULT_TIMEOUT_MS, clampNote: '', error: '' };
  }
  const minMs: number = NODE_EXEC_MIN_TIMEOUT_S * 1000;
  const maxMs: number = NODE_EXEC_MAX_TIMEOUT_S * 1000;
  const reqMs: number = Math.round((raw as number) * 1000);
  if (reqMs < minMs) {
    return {
      timeoutMs: minMs,
      clampNote: 'timeout 小于 ' + NODE_EXEC_MIN_TIMEOUT_S + ' 秒，本次按 ' + NODE_EXEC_MIN_TIMEOUT_S +
        ' 秒执行。',
      error: ''
    };
  }
  if (!(reqMs <= maxMs)) {
    return {
      timeoutMs: maxMs,
      clampNote: 'timeout 超过上限 ' + NODE_EXEC_MAX_TIMEOUT_S + ' 秒，本次按上限执行。',
      error: ''
    };
  }
  return { timeoutMs: reqMs, clampNote: '', error: '' };
}

// read_output 分支：不启动 Node、不经 lane、不弹执行确认；只读本会话临时区
function runReadOutput(parsed: Record<string, Object>, ctx: ToolExecutionContext): string {
  const conflict: string = readOutputConflictText(parsed);
  if (conflict !== '') {
    return JSON.stringify({ error: conflict });
  }
  const name: string = argsString(parsed, 'name');
  const reject: string = workspaceNameRejectReason(name);
  if (reject !== '') {
    return JSON.stringify({ error: reject });
  }
  const pagingKeys: string[] = ['offset', 'limit', 'col'];
  for (const key of pagingKeys) {
    const fieldError: string = numberFieldErrorText(parsed, key);
    if (fieldError !== '') {
      return JSON.stringify({ error: fieldError });
    }
  }
  let content: string = '';
  try {
    content = readWorkspaceTmpFileText(ctx.conversationId, name);
  } catch (e) {
    return JSON.stringify({ error: '临时文件「' + name + '」不存在或读取失败：' + toolErrorText(e) });
  }
  return composeWorkspaceReadReply(name, content, argsNumber(parsed, 'offset'),
    argsNumber(parsed, 'limit'), '', argsNumber(parsed, 'col'));
}

// install 分支（门 3 U2）：参数互斥 fail-closed → specs 逐条校验 → 调度器 install 单飞
//（sessionId = conversationId 归属键，超时用调度器单源默认 10 分钟，本层不传覆写）→ 终态回执
async function runInstallPackages(parsed: Record<string, Object>,
  ctx: ToolExecutionContext): Promise<string> {
  const conflict: string = installConflictText(parsed);
  if (conflict !== '') {
    return JSON.stringify({ error: conflict });
  }
  const specsRaw: Object | undefined = parsed['specs'];
  if (!Array.isArray(specsRaw)) {
    return JSON.stringify({ error: 'action 为 install 时 specs 必须是字符串数组。' });
  }
  const specs: string[] = [];
  const items: Object[] = specsRaw as Object[];
  for (const item of items) {
    if (typeof item !== 'string') {
      return JSON.stringify({ error: 'specs 里只能有字符串，当前收到的条目是 ' + typeof item + '。' });
    }
    specs.push(item);
  }
  const reject: string = nodeInstallSpecsRejectReason(specs);
  if (reject !== '') {
    return JSON.stringify({ error: reject });
  }
  let receipt: NodeInstallReceipt;
  try {
    receipt = await installNodePackages({
      conversationId: ctx.conversationId,
      sessionId: ctx.conversationId,
      specs: specs
    });
  } catch (e) {
    return JSON.stringify({ error: 'npm 安装调度异常。' + toolErrorText(e) });
  }
  return composeInstallReceipt(receipt);
}

// bin 参数的展示串（确认卡 detail 与回执附注共用；参数过多只列前几条）
const NODE_BIN_CONFIRM_ARGS_MAX: number = 8;

function binArgumentSummary(args: string[]): string {
  if (args.length === 0) {
    return '无参数';
  }
  const shown: string[] = args.length > NODE_BIN_CONFIRM_ARGS_MAX
    ? args.slice(0, NODE_BIN_CONFIRM_ARGS_MAX) : args;
  const suffix: string = args.length > shown.length ? ' 等 ' + args.length + ' 条参数' : '';
  return '参数 ' + shown.join(' ') + suffix;
}

// run_bin 分支（门 3 U3）：互斥 → 命令名与参数校验 → 调度器 executeNodeBin（同 lane 同代次同取消）
async function runBinTool(parsed: Record<string, Object>,
  ctx: ToolExecutionContext): Promise<string> {
  const conflict: string = runBinConflictText(parsed);
  if (conflict !== '') {
    return JSON.stringify({ error: conflict });
  }
  const binName: string = argsString(parsed, 'bin').trim();
  if (binName === '') {
    return JSON.stringify({ error: 'action 为 run_bin 时 bin 不能为空，请传入已装包提供的命令名。' });
  }
  if (/[\s\\/]/.test(binName)) {
    return JSON.stringify({ error: '命令名里不能有空白或路径分隔符，只传命令本身。' });
  }
  const args: string[] = [];
  const argsRaw: Object | undefined = parsed['args'];
  if (argsRaw !== undefined) {
    if (!Array.isArray(argsRaw)) {
      return JSON.stringify({ error: 'args 只支持字符串数组。' });
    }
    const items: Object[] = argsRaw as Object[];
    if (items.length > NODE_BIN_ARGS_MAX) {
      return JSON.stringify({ error: 'args 最多 ' + NODE_BIN_ARGS_MAX + ' 条。' });
    }
    for (const item of items) {
      if (typeof item !== 'string') {
        return JSON.stringify({ error: 'args 里只能有字符串，当前收到的条目是 ' + typeof item + '。' });
      }
      if (item.length > NODE_BIN_ARG_MAX_LENGTH) {
        return JSON.stringify({ error: 'args 里每条不能超过 ' + NODE_BIN_ARG_MAX_LENGTH + ' 字符。' });
      }
      args.push(item);
    }
  }
  const timeout: NodeTimeoutDecision = resolveNodeToolTimeout(parsed);
  if (timeout.error !== '') {
    return JSON.stringify({ error: timeout.error });
  }
  const req: NodeBinRequest = {
    conversationId: ctx.conversationId,
    sessionId: ctx.conversationId,
    bin: binName,
    args: args,
    timeoutMs: timeout.timeoutMs,
    onLaneAdmitted: async (): Promise<NodeLaneAdmitContext> => {
      return { cwd: ensureWorkspaceTmpConversationDir(ctx.conversationId) };
    }
  };
  let receipt: NodeExecReceipt;
  try {
    receipt = await executeNodeBin(req);
  } catch (e) {
    return JSON.stringify({ error: '命令运行调度异常。' + toolErrorText(e) });
  }
  if (receipt.errorKind !== undefined) {
    const text: string = schedulerFailureText(receipt) +
      (timeout.clampNote === '' ? '' : '\n' + timeout.clampNote);
    return JSON.stringify({ error: trimToBudget(text, NODE_ERROR_TEXT_BUDGET) });
  }
  return composeBinReceipt(receipt, ctx.conversationId, timeout.clampNote);
}

// data 落件名唯一段（node-input-<毫秒时间戳>-<序号>.txt——与 py-input / exec-input 家族并行，
// Node 专属前缀防混读；清洗保证落临时区的名恒过闸）
let nodeInputSeq: number = 0;

function nextNodeInputFileName(): string {
  nodeInputSeq += 1;
  return 'node-input-' + Date.now() + '-' + nodeInputSeq + '.txt';
}

// 安全记录段（events 头 10 行 + 未显示计数 + 可观测声明；无事件不出行）
function composeAuditTail(receipt: NodeExecReceipt): string {
  if (receipt.events.length === 0) {
    return '';
  }
  const shown: string[] = receipt.events.slice(0, NODE_AUDIT_MAX_LINES);
  const total: number = receipt.eventsTotal > receipt.events.length ?
    receipt.eventsTotal : receipt.events.length;
  const moreCount: number = total - shown.length;
  let text: string = '安全记录（只记录不拦截）：\n' + shown.join('\n');
  if (moreCount > 0) {
    text += '\n另有 ' + moreCount + ' 条未显示。';
  }
  if (receipt.eventsNote !== '') {
    text += '\n' + receipt.eventsNote;
  }
  return text;
}

// 调度层失败文案（errorKind 分类；no-session / invalid-request / runtime-unavailable /
// workspace-unavailable / lane-rejected / bridge-unreachable / cancelled / internal-error）
function schedulerFailureText(receipt: NodeExecReceipt): string {
  const kind: string = receipt.errorKind !== undefined ? receipt.errorKind : '';
  const detail: string = receipt.error !== undefined ? receipt.error : '';
  if (kind === 'cancelled') {
    return '运行已取消，当前会话的 Node 环境已重置，下一轮从干净环境开始。';
  }
  if (kind === 'lane-rejected') {
    return detail !== '' ? detail + '。' : '未能获得执行位，本次没有执行。';
  }
  if (kind === 'runtime-unavailable') {
    return 'Node 运行区不可用。' + detail;
  }
  if (kind === 'bridge-unreachable') {
    return 'Node 桥接不可用。' + detail;
  }
  if (kind === 'workspace-unavailable') {
    return detail !== '' ? detail : '执行前准备失败，本次没有执行。';
  }
  if (kind === 'no-session' || kind === 'invalid-request' || kind === 'internal-error') {
    return detail !== '' ? detail : '本次调用参数不正确，未执行。';
  }
  return detail !== '' ? detail : '本次调用未执行。';
}

// Node 回执失败文案（bootstrap 错误码：script-error / timeout / cancelled / crashed /
// terminated-background / busy / not-ready / prepare-failed 等；终态回执不带输出与 savedNames）
function bootstrapFailureText(receipt: NodeExecReceipt): string {
  const code: string = receipt.error !== undefined ? receipt.error : '';
  if (code === 'timeout') {
    return '运行失败（等待超时，当前会话已重置）。下一轮从干净环境开始，上一轮的变量不再保留。';
  }
  if (code === 'cancelled' || code === 'dropped') {
    return '运行失败（已取消，当前会话已重置）。其他会话的变量不受影响。';
  }
  if (code === 'crashed') {
    return '运行失败（脚本结束或进程异常，当前会话已重置）。如果整个应用异常退出，请重启应用恢复。';
  }
  if (code === 'terminated-background') {
    return '运行失败（本轮结束时仍有未完成的后台操作，当前会话已重置）。把网络请求与文件操作在当轮 ' +
      'await 完成后再继续。';
  }
  if (code === 'busy') {
    return '运行失败（上一轮代码仍在运行）。请稍后重试。';
  }
  if (code === 'not-ready' || code === 'prepare-failed') {
    return '运行失败（Node 运行区未就绪）。准备失败后需要重启应用再试。';
  }
  if (code === 'script-error') {
    return '运行失败。';
  }
  return '运行失败（错误码 ' + (code !== '' ? code : '未知') + '）。';
}

// 脚本错误详情（stderr 优先给 traceback；stdout 已产出的部分一并如实呈现）
function scriptErrorDetail(receipt: NodeExecReceipt, budget: number): string {
  let body: string = '';
  if (receipt.stdout !== '') {
    body += '输出：\n' + trimToBudget(receipt.stdout, NODE_EXEC_STDOUT_BUDGET) + '\n';
  }
  body += receipt.stderr !== '' ? '错误详情：\n' + receipt.stderr : '（无错误信息）';
  return trimToBudget(body, Math.max(budget, 1));
}

// 输出段载荷（text = 回执内直出段；envelope = 溢出信封）
interface NodeOutputSegment {
  text: string;
  envelope: string;
}

// 成功路径输出段与溢出信封（> 5000 字符整段落盘；截断如实说明，禁写「完整输出」）
function composeOutputSegment(receipt: NodeExecReceipt,
  conversationId: string): NodeOutputSegment {
  const segment: NodeOutputSegment = { text: '', envelope: '' };
  if (receipt.stdout.length <= NODE_EXEC_STDOUT_BUDGET) {
    segment.text = receipt.stdout;
    return segment;
  }
  const spillName: string = nextSpillFileName();
  let spillSaved: string = '';
  try {
    spillSaved = writeWorkspaceTmpTextFile(conversationId, spillName, receipt.stdout);
  } catch (e) {
    spillSaved = '';
  }
  if (spillSaved === '') {
    segment.envelope = '\n输出超过回执上限，暂存临时区失败，以下内容不完整。';
    segment.text = trimToBudget(receipt.stdout, NODE_EXEC_STDOUT_BUDGET);
    return segment;
  }
  let envelope: string = '\n输出超过回执上限，已存为临时文件 ' + spillSaved + '，共 ' +
    receipt.stdout.length + ' 字符。';
  if (receipt.stdoutTruncated) {
    envelope += '\n运行输出超过单轮保留上限，临时文件里是保留开头与结尾后的内容，不是完整输出。';
  }
  envelope += '\n开头：\n' + trimToBudget(receipt.stdout.substring(0, 2048), NODE_PREVIEW_CLIP) +
    '\n结尾：\n' + trimToBudget(receipt.stdout.substring(receipt.stdout.length - 2048),
      NODE_PREVIEW_CLIP) +
    '\n继续查看用 exec_node，action 传 read_output，name 传 ' + spillSaved +
    '，offset 从 1 起分段读。';
  segment.envelope = envelope;
  return segment;
}

// ── 回执组装（唯一入口；自预算铁律：含信封恒 < 8192）──
// 成功：运行完成（毫秒）+ 输出段（预算内全量 / 超预算溢出信封）+ stderr 提示段 + 尾注三件
//（参数注记 / 转正行 / 安全记录）；失败：终态固定句或 traceback + 尾注
function composeNodeReceipt(receipt: NodeExecReceipt, conversationId: string,
  noteText: string, promoteTail: string, auditTail: string): string {
  const tailText: string = trimToBudget(
    noteText + (noteText !== '' && promoteTail !== '' ? '\n' : '') + promoteTail, NODE_TAIL_BUDGET);
  const tailPart: string = tailText !== '' ? '\n' + tailText : '';
  const auditPart: string = auditTail !== '' ? '\n' + trimToBudget(auditTail, NODE_AUDIT_BUDGET) : '';
  const reserved: number = tailPart.length + auditPart.length + 1;
  const head: string = '运行完成（' + receipt.elapsedMs + ' 毫秒）。';
  if (!receipt.ok) {
    const failHead: string = bootstrapFailureText(receipt);
    if ((receipt.error !== undefined ? receipt.error : '') === 'script-error') {
      return trimToBudget(failHead + '\n' + scriptErrorDetail(receipt,
        NODE_REPLY_HARD_CAP - reserved - failHead.length), NODE_REPLY_HARD_CAP - reserved) +
        tailPart + auditPart;
    }
    return trimToBudget(failHead, NODE_REPLY_HARD_CAP - reserved) + tailPart + auditPart;
  }
  const segment: NodeOutputSegment = composeOutputSegment(receipt, conversationId);
  let body: string = '输出：\n' + (segment.text !== '' ? segment.text : '（无输出）');
  if (receipt.stderr !== '') {
    body += '\n提示与警告：\n' + trimToBudget(receipt.stderr, NODE_EXEC_STDERR_BUDGET);
  }
  const fixed: number = head.length + 1 + segment.envelope.length + reserved;
  return head + '\n' + trimToBudget(body, Math.max(NODE_REPLY_HARD_CAP - fixed, 1)) +
    segment.envelope + tailPart + auditPart;
}

// ── install 回执组装（门 3 U2；自预算铁律同 exec：恒 < 8192）──
// install 日志尾预算（失败路径给尾部日志行；行数与单行字符双限）
const NODE_INSTALL_LOG_LINES: number = 24;
const NODE_INSTALL_LOG_LINE_MAX: number = 160;
// install 失败详情预算（errorDetail / errorCode 拼进失败文案的上限）
const NODE_INSTALL_DETAIL_BUDGET: number = 600;
// 回滚未成功项的展示条数与其单条路径预算（回执侧已 ≤10 条，这里再兜一次）
const NODE_INSTALL_VIOLATION_LINES: number = 10;
const NODE_INSTALL_VIOLATION_LINE_MAX: number = 120;

// 安装阶段中文名（npm-worker 心跳四值；未知值原样给出，不猜）
function installStageText(stage: string): string {
  if (stage === 'resolve') {
    return '解析依赖';
  }
  if (stage === 'fetch') {
    return '下载';
  }
  if (stage === 'extract') {
    return '解包';
  }
  if (stage === 'verify') {
    return '校验';
  }
  return stage;
}

// 阶段附注（超时 / 取消文案用：本次最后停在哪个阶段）
function installStageNote(receipt: NodeInstallReceipt): string {
  const stage: string = receipt.stage;
  return stage !== '' ? '最后停在' + installStageText(stage) + '阶段。' : '';
}

// 英文错误码判定（Node 回执透传的 error 是 bad-request 这类 ASCII 码；调度层 error 是中文文案）
// ——透传码不得直出给用户，中文详情在 errorDetail 里，两者都不在时才用兜底句
function isAsciiErrorCode(text: string): boolean {
  if (text === '') {
    return false;
  }
  for (let i: number = 0; i < text.length; i++) {
    if (text.charCodeAt(i) > 127) {
      return false;
    }
  }
  return true;
}

// install 失败文案（errorKind 在场 = 调度层分类，error 是中文细节；errorKind 缺省 = Node
// 回执透传码 quota-exceeded / binary-rejected / install-failed / crashed / internal-error 等）
function installFailureText(receipt: NodeInstallReceipt): string {
  const kind: string = receipt.errorKind !== undefined ? receipt.errorKind : '';
  const errorTextValue: string = receipt.error !== undefined ? receipt.error : '';
  const detail: string = receipt.errorDetail !== undefined ? receipt.errorDetail : '';
  const stageNote: string = installStageNote(receipt);
  if (receipt.cancelled === true || kind === 'cancelled') {
    return '安装未完成，已取消或被终止。' + stageNote +
      '磁盘上的残留会由下次安装自动整理，已装好的包不受影响。';
  }
  if (kind === 'install-running') {
    return '已有一个安装正在进行，等它结束后再试。';
  }
  if (kind === 'timeout') {
    return '等待 npm 安装超时，本次安装没有完成。' + stageNote;
  }
  // 运行区 / 桥接两条：调度层 failure 传的是中文原因短语（准备失败原因、连接失败原因），Node
  // 侧回执则是英文透传码（not-ready / prepare-failed）+ 中文 detail。统一 detail 优先、英文码
  // 一律不直出，避免「Node 运行区不可用，本次安装没有执行。prepare-failed」这类机器值泄漏；
  // 调度层只给原因短语，不在 error 里重复「不可用」前缀（否则拼出来同一句说两遍）
  const runtimeDetail: string = detail !== ''
    ? trimToBudget(detail, NODE_INSTALL_DETAIL_BUDGET)
    : (isAsciiErrorCode(errorTextValue) ? '' : errorTextValue);
  if (kind === 'runtime-unavailable') {
    return 'Node 运行区不可用，本次安装没有执行。' + runtimeDetail;
  }
  if (kind === 'bridge-unreachable') {
    return 'Node 桥接不可用，本次安装没有执行。' + runtimeDetail;
  }
  if (kind === 'invalid-request' || kind === 'no-session' || kind === 'internal-error') {
    // 中文化单点：优先用中文详情（Node 侧 bad-request / internal-error 都带详情），调度层
    // 失败则用其中文文案；都不在时才兜底一句——禁把英文错误码漏给用户
    if (detail !== '') {
      return trimToBudget(detail, NODE_INSTALL_DETAIL_BUDGET);
    }
    const text: string = isAsciiErrorCode(errorTextValue) ? '' : errorTextValue;
    return text !== '' ? text : '本次安装没有执行。';
  }
  const code: string = errorTextValue;
  if (code === 'quota-exceeded') {
    return '安装被拒绝。' + trimToBudget(detail, NODE_INSTALL_DETAIL_BUDGET);
  }
  if (code === 'binary-rejected') {
    if (receipt.rolledBack === true) {
      return '安装被拒绝。扫描发现要装的包含二进制文件，已回滚，本次新增的包没有留在磁盘上。';
    }
    // 回滚没完全成功（删除 / 修复重装 / 复扫任一步失败）：如实列出没处理掉的项，不说过头话
    const leftovers: string[] = receipt.violations !== undefined ? receipt.violations : [];
    let text: string = '安装被拒绝。扫描发现要装的包含二进制文件，回滚没有完全成功。';
    if (leftovers.length > 0) {
      const shown: string[] = [];
      const limit: number = leftovers.length > NODE_INSTALL_VIOLATION_LINES
        ? NODE_INSTALL_VIOLATION_LINES : leftovers.length;
      for (let i: number = 0; i < limit; i++) {
        shown.push(trimToBudget(leftovers[i], NODE_INSTALL_VIOLATION_LINE_MAX));
      }
      text += '没有处理掉的项有 ' + shown.join('、') + '。';
    }
    return text;
  }
  if (code === 'install-failed') {
    const errorCode: string = receipt.errorCode !== undefined ? receipt.errorCode : '';
    return '安装失败，退出码 ' + receipt.exitCode + '。' + trimToBudget(
      (errorCode !== '' ? errorCode + '：' : '') + detail, NODE_INSTALL_DETAIL_BUDGET);
  }
  if (code === 'crashed') {
    return '安装失败，npm 进程异常退出。';
  }
  if (code === 'internal-error') {
    // Node 侧内部异常的中文详情同样不得丢（旧实现落进末行兜底，只剩「错误码 internal-error」）
    return detail !== '' ? '安装没有执行。' + trimToBudget(detail, NODE_INSTALL_DETAIL_BUDGET)
      : '安装没有执行，Node 侧内部异常。';
  }
  return '安装失败，错误码 ' + (code !== '' ? code : '未知') + '。';
}

// install 终态回执（成功 = 耗时 + 每包摘要行 + 截断标注 + wasm 提示 + require 可用句；
// 失败 = 失败文案 + 有界日志尾）
function composeInstallReceipt(receipt: NodeInstallReceipt): string {
  if (receipt.ok) {
    const total: number = receipt.packagesTotal > 0 ? receipt.packagesTotal
      : receipt.packages.length;
    const lines: string[] = ['安装完成，耗时 ' + receipt.elapsedMs + ' 毫秒，共 ' + total + ' 个包。'];
    for (const line of receipt.packages) {
      lines.push(line);
    }
    if (receipt.packagesTruncated && receipt.packagesTotal > receipt.packages.length) {
      lines.push('另有 ' + (receipt.packagesTotal - receipt.packages.length) + ' 个包未列出。');
    }
    if (receipt.wasmNote !== '') {
      lines.push(receipt.wasmNote + '。');
    }
    // 清理附注（安装前清扫历史残留等）：成功路径也如实报，别让「静默清理」变成看不见的副作用
    const cleanupNote: string = receipt.cleanupNote !== undefined ? receipt.cleanupNote : '';
    if (cleanupNote !== '') {
      lines.push(cleanupNote);
    }
    lines.push('装好的 CommonJS 包在同一会话里直接 require 可用。');
    return trimToBudget(lines.join('\n'), NODE_REPLY_HARD_CAP);
  }
  const logLines: string[] = receipt.logTail.slice(-NODE_INSTALL_LOG_LINES);
  const logText: string = logLines.length > 0 ? '\n日志尾部：\n' + logLines
    .map((line: string): string => trimToBudget(line, NODE_INSTALL_LOG_LINE_MAX))
    .join('\n') : '';
  const failCleanupNote: string = receipt.cleanupNote !== undefined ? receipt.cleanupNote : '';
  const failNote: string = failCleanupNote !== '' ? '\n' + failCleanupNote : '';
  return trimToBudget(installFailureText(receipt) + failNote + logText,
    NODE_REPLY_HARD_CAP);
}

// ── bin 回执组装（门 3 U3；自预算铁律同 exec：恒 < 8192）──
// 失败文案（error 两族：bin-runner 的 bin-missing / bin-esm-unsupported / bin-error；bootstrap
// 的 timeout / cancelled / crashed / busy / not-ready / prepare-failed / bad-request / bad-cwd）
function binFailureText(receipt: NodeExecReceipt, binName: string): string {
  const code: string = receipt.error !== undefined ? receipt.error : '';
  const label: string = binName === '' ? '命令' : '命令 ' + binName;
  if (code === 'bin-missing') {
    return label + ' 不在安装记录里，或它对应的包已经不在安装区。先安装提供它的包再试。';
  }
  if (code === 'bin-esm-unsupported') {
    return label + ' 只支持 CommonJS 入口，这个包提供的是 ES 模块入口，暂不能运行。';
  }
  if (code === 'bin-error') {
    // 与 exec 的 scriptErrorDetail 同形（2026-11-24 补正）：命令常见「先打印进度再抛错」，只看
    // stderr 会把抛错前的诊断输出整段丢掉
    let body: string = '';
    if (receipt.stdout !== '') {
      body += '输出：\n' + trimToBudget(receipt.stdout, NODE_EXEC_STDOUT_BUDGET) + '\n';
    }
    const detail: string = receipt.stderr.trim();
    body += detail !== '' ? '错误详情：\n' + detail : '（无错误信息）';
    return label + ' 运行出错。\n' + trimToBudget(body, NODE_REPLY_HARD_CAP - 80);
  }
  if (code === 'timeout') {
    return label + ' 等待超时，当前会话已重置。下一轮从干净环境开始。';
  }
  if (code === 'cancelled' || code === 'dropped') {
    return label + ' 已取消，当前会话已重置。其他会话不受影响。';
  }
  if (code === 'crashed') {
    return label + ' 运行期间进程异常，当前会话已重置。如果整个应用异常退出，请重启应用恢复。';
  }
  if (code === 'terminated-background') {
    return label + ' 结束时仍有未完成的后台操作，当前会话已重置。把网络请求与文件操作在当轮结束时完成再继续。';
  }
  if (code === 'busy') {
    return '上一轮代码仍在运行，' + label + ' 没有执行。请稍后重试。';
  }
  if (code === 'not-ready' || code === 'prepare-failed') {
    return label + ' 没有执行，Node 运行区未就绪。准备失败后需要重启应用再试。';
  }
  if (code === 'bad-request') {
    return '命令请求参数不正确，' + label + ' 没有执行。';
  }
  if (code === 'bad-cwd') {
    return '会话临时区不可用，' + label + ' 没有执行。';
  }
  return label + ' 运行失败（错误码 ' + (code !== '' ? code : '未知') + '）。';
}

// bin 终态回执（成功 = 命令 + 耗时 + 退出码 + 输出段 + 提供方附注；非零退出仍算跑完，如实报码）
function composeBinReceipt(receipt: NodeExecReceipt, conversationId: string,
  clampNote: string): string {
  const binName: string = receipt.bin !== undefined && receipt.bin !== '' ? receipt.bin : '';
  if (!receipt.ok) {
    return trimToBudget(binFailureText(receipt, binName), NODE_REPLY_HARD_CAP);
  }
  const exitCode: number = receipt.exitCode !== undefined ? receipt.exitCode : 0;
  const head: string = '命令 ' + binName + ' 运行完成（' + receipt.elapsedMs + ' 毫秒），退出码 ' +
    exitCode + '。';
  const segment: NodeOutputSegment = composeOutputSegment(receipt, conversationId);
  let body: string = '输出：\n' + (segment.text !== '' ? segment.text : '（无输出）');
  if (receipt.stderr !== '') {
    body += '\n错误输出：\n' + trimToBudget(receipt.stderr, NODE_EXEC_STDERR_BUDGET);
  }
  let tail: string = clampNote;
  const provider: string = receipt.binPackage !== undefined ? receipt.binPackage : '';
  if (provider !== '') {
    const providerNote: string = receipt.binReplaced === true
      ? '这个命令由多个包提供，本次运行的是包 ' + provider + ' 的入口。'
      : '本次运行的是包 ' + provider + ' 提供的入口。';
    tail = tail === '' ? providerNote : tail + '\n' + providerNote;
  }
  const tailPart: string = tail !== '' ? '\n' + tail : '';
  const fixed: number = head.length + 1 + segment.envelope.length + tailPart.length;
  return head + '\n' + trimToBudget(body, Math.max(NODE_REPLY_HARD_CAP - fixed, 1)) +
    segment.envelope + tailPart;
}

// 参数注记（data 落件句 / timeout 钳制句，'\n' 分隔——调度层失败与执行回执共用）
function composeNoteText(admitted: NodeAdmittedInfo, clampNote: string): string {
  const parts: string[] = [];
  if (admitted.dataName !== '') {
    parts.push('输入数据已存入临时区文件 ' + admitted.dataName + '，代码里先 require(\'fs\') 再读取，路径直接传文件名。');
  }
  if (clampNote !== '') {
    parts.push(clampNote);
  }
  return parts.join('\n');
}

// install 确认预检产卡（specs 逐行 + registry 来源行进 detail，流内专属卡与 dock 托管通用卡
// 的「查看请求详情」折叠块同源消费；格式错照实提示，不猜不裁）
function installConfirmPrompt(argsJson: string): ConfirmPrompt {
  const lines: string[] = [];
  let listOk: boolean = false;
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    const raw: Object | undefined = parsed['specs'];
    if (Array.isArray(raw)) {
      const items: Object[] = raw as Object[];
      for (const item of items) {
        if (typeof item === 'string') {
          lines.push(item);
        }
      }
      listOk = lines.length > 0;
    }
  } catch (e) {
    listOk = false;
  }
  const detail: string = (listOk ? lines.join('\n') :
    '安装清单缺失或格式不正确，请核对原始入参。') + '\n' + NODE_INSTALL_REGISTRY_TEXT;
  return { text: NODE_INSTALL_CONFIRM_TEXT, level: CONFIRM_LEVEL_IRREVERSIBLE,
    route: CONFIRM_ROUTE_HUMAN, detail: detail };
}

// bin 确认卡主因句（门 3 U3：与 exec 同档 write，如实写沙箱边界）
const NODE_BIN_CONFIRM_TEXT: string =
  '运行已安装包提供的命令行工具。它和代码执行一样在应用沙箱内运行，未设网络与文件强边界。';

// run_bin 预检产卡（write 档，与 exec 同观感；detail = 命令与参数，流内专属卡与 dock 托管通用卡
// 的「查看请求详情」折叠块同源消费；格式错照实提示，不猜不裁）
function binConfirmPrompt(argsJson: string): ConfirmPrompt {
  let detail: string = '命令缺失或格式不正确，请核对原始入参。';
  let args: string[] = [];
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    const binName: string = argsString(parsed, 'bin').trim();
    const argsRaw: Object | undefined = parsed['args'];
    if (Array.isArray(argsRaw)) {
      const items: Object[] = argsRaw as Object[];
      for (const item of items) {
        if (typeof item === 'string') {
          args.push(item);
        }
      }
    }
    if (binName !== '') {
      detail = '命令 ' + binName + '，' + binArgumentSummary(args) + '。';
    }
  } catch (e) {
    detail = '命令缺失或格式不正确，请核对原始入参。';
  }
  return { text: NODE_BIN_CONFIRM_TEXT, level: CONFIRM_LEVEL_WRITE, detail: detail };
}

// 确认预检（fail-closed：解析失败不返 null，给保守卡让用户核对代码开头；read_output 是
// 只读取回，不弹执行确认）
export async function execNodeNeedsConfirm(argsJson: string,
  _ctx: ToolExecutionContext): Promise<ConfirmPrompt | null> {
  let action: string = NODE_ACTION_EXEC;
  let parsedOk: boolean = true;
  let codeHead: string = '';
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    action = resolveActionValue(parsed);
    if (action === '') {
      action = NODE_ACTION_EXEC;
    }
    const code: string = argsString(parsed, 'code');
    const compact: string = code.replace(/\s+/g, ' ').trim();
    codeHead = compact.length > NODE_CONFIRM_DETAIL_MAX ?
      compact.substring(0, NODE_CONFIRM_DETAIL_MAX) + '…' : compact;
  } catch (e) {
    parsedOk = false;
    action = NODE_ACTION_EXEC;
    codeHead = '';
  }
  if (parsedOk && action === NODE_ACTION_READ_OUTPUT) {
    return null;
  }
  // 待重启守卫（门 4）：运行区已清空 / 重建、应用未重启——三动作执行器必回拒绝回执，这里不构造
  // 确认卡（返 null = 直通到执行器，由它给出重启提示），不让用户点了允许才被告知不可用
  if (nodeNeedsRestart()) {
    return null;
  }
  // install（门 3 U2，方案档 ④ 三防线）：不可逆档 + 预检直回人工卡——不经 routeConfirmPrompt
  //（高效档全直通对不可逆安装不适用）；与 exec 同工具名，档位若落 WRITE 会被已授予的会话级
  // 允许放行（sessionAllowHit 判据只认工具名与非不可逆档）。specs 格式错也出卡（fail-closed，
  // 用户允许后执行器仍会拒绝）；JSON 解析失败按 exec 保守卡兜底（执行器会报参数错误）
  if (parsedOk && action === NODE_ACTION_INSTALL) {
    return installConfirmPrompt(argsJson);
  }
  // run_bin（门 3 U3）：write 档，与 exec 同档同判序（高效档直通，代决表第 2 项）
  if (parsedOk && action === NODE_ACTION_RUN_BIN) {
    try {
      return routeConfirmPrompt(binConfirmPrompt(argsJson), dataApproveMode());
    } catch (e) {
      return binConfirmPrompt(argsJson);
    }
  }
  try {
    let prompt: ConfirmPrompt = { text: NODE_CONFIRM_TEXT, level: CONFIRM_LEVEL_WRITE };
    if (codeHead !== '') {
      prompt = { text: NODE_CONFIRM_TEXT, level: CONFIRM_LEVEL_WRITE, detail: codeHead };
    }
    return routeConfirmPrompt(prompt, dataApproveMode());
  } catch (e) {
    return { text: NODE_CONFIRM_TEXT, level: CONFIRM_LEVEL_WRITE };
  }
}

// ── exec_node 执行器 ──
export class ExecNodeExecutor implements ToolExecutor {
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const action: string = resolveActionValue(parsed);
    if (action === '') {
      return JSON.stringify({ error: 'action 只支持 exec、read_output、install 与 run_bin，当前收到的是 ' +
        argsString(parsed, 'action') + '。' });
    }
    if (ctx.conversationId === '') {
      return JSON.stringify({ error: 'Node 只在会话中可用，当前执行上下文没有会话。' });
    }
    if (action === NODE_ACTION_READ_OUTPUT) {
      return runReadOutput(parsed, ctx);
    }
    // 待重启守卫（门 4）：与调度层 schedulerFailureText / installFailureText 的 runtime-unavailable
    // 分支同形——无论哪一层拦下，模型看到的都是同一句
    if (nodeNeedsRestart()) {
      const guardText: string = nodeRestartGuardText();
      return JSON.stringify({ error: action === NODE_ACTION_INSTALL
        ? 'Node 运行区不可用，本次安装没有执行。' + guardText
        : 'Node 运行区不可用。' + guardText });
    }
    if (action === NODE_ACTION_INSTALL) {
      return await runInstallPackages(parsed, ctx);
    }
    if (action === NODE_ACTION_RUN_BIN) {
      return await runBinTool(parsed, ctx);
    }
    // ── exec 分支 ──
    const conflict: string = execConflictText(parsed);
    if (conflict !== '') {
      return JSON.stringify({ error: conflict });
    }
    const code: string = argsString(parsed, 'code');
    if (code.trim() === '') {
      return JSON.stringify({ error: 'action 为 exec 时 code 不能为空，请传入完整可运行的 Node.js 源码。' });
    }
    const dataRaw: Object | undefined = parsed['data'];
    if (dataRaw !== undefined && typeof dataRaw !== 'string') {
      return JSON.stringify({ error: 'data 只支持字符串，当前收到的是 ' + typeof dataRaw + '。' });
    }
    const dataText: string = typeof dataRaw === 'string' ? dataRaw : '';
    // timeout 只支持数值（类型错直接拒）；钳制 [1s, 300s]，缺省 120s，越钳说明句随尾注
    const timeout: NodeTimeoutDecision = resolveNodeToolTimeout(parsed);
    if (timeout.error !== '') {
      return JSON.stringify({ error: timeout.error });
    }
    const timeoutMs: number = timeout.timeoutMs;
    const clampNote: string = timeout.clampNote;
    // 受理回调产出的注记（data 落件只在拿到 lane 之后——排队拒绝与取消不提前落文件）
    const admitted: NodeAdmittedInfo = { dataName: '' };
    const req: NodeExecRequest = {
      // sessionId = conversationId：bootstrap 每 sessionId 一个长期 worker，会话即隔离单位
      conversationId: ctx.conversationId,
      sessionId: ctx.conversationId,
      code: code,
      timeoutMs: timeoutMs,
      onLaneAdmitted: async (): Promise<NodeLaneAdmitContext> => {
        const cwd: string = ensureWorkspaceTmpConversationDir(ctx.conversationId);
        if (dataText !== '') {
          const inputName: string = nextNodeInputFileName();
          admitted.dataName = writeWorkspaceTmpTextFile(ctx.conversationId, inputName, dataText);
        }
        return { cwd: cwd };
      }
    };
    let receipt: NodeExecReceipt;
    try {
      receipt = await executeNodeCode(req);
    } catch (e) {
      return JSON.stringify({ error: 'Node 执行调度异常。' + toolErrorText(e) });
    }
    const noteText: string = composeNoteText(admitted, clampNote);
    if (receipt.errorKind !== undefined) {
      const text: string = schedulerFailureText(receipt) +
        (noteText === '' ? '' : '\n' + noteText);
      return JSON.stringify({ error: trimToBudget(text, NODE_ERROR_TEXT_BUDGET) });
    }
    // save() 登记转正（脚本错误前已 save 的也转正；超时 / 取消 / 崩溃回执不带 savedNames）
    const promoteTail: string = await promoteSavedNames(receipt.savedNames, ctx.conversationId);
    const auditTail: string = composeAuditTail(receipt);
    return composeNodeReceipt(receipt, ctx.conversationId, noteText, promoteTail, auditTail);
  }
}

// ── 自注册面（照 ToolPyExec 先例：组标签同居本件，ToolTypes 引回入组序 + 调用注册）──
// 组标题（助手工具页独立「Node 运行」卡——默认关、紧随「Python 运行」，三卡互不联动）
export const TOOL_GROUP_NODE: string = 'Node 运行';

export function registerNodeTools(): void {
  toolRegistry.register({
    name: TOOL_EXEC_NODE,
    group: TOOL_GROUP_NODE,
    title: '运行 Node',
    desc: EXEC_NODE_DESC,
    parametersJson: EXEC_NODE_SCHEMA,
    defaultEnabled: false,
    executor: new ExecNodeExecutor(),
    preflight: execNodeNeedsConfirm
  });
}
