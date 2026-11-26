// 文件夹挂载工具域：本件收 mount_list / mount_read / mount_write / mount_copy_out /
// mount_copy_in 五件 + 注册面（registerMountTools + 组标题 TOOL_GROUP_MOUNT 同居本件
// **文件末位**，ToolTypes 只留一字接线——域件不能反向引聚合根；切片锚约束见末位段注释）。
// mount_delete 在同域件 ToolMountDelete.ets（公共骨架〔公共闸 / args 解析 / 懒激活 / 根路径
// 转换〕仍在本件单源、升导出供外迁件引）；覆盖写旧文摘录预读域在 ToolMountWriteDiff.ets
//（读序铁律见该件头注释）；契约自叶子 ToolContracts 引（坑50：禁从聚合根 ToolTypes 引）。
// · 方向防混：mount_copy_out = 出挂载、进工作区（零确认——拷出源只读、写沙箱、可逆）；
//   mount_copy_in = 出工作区、进挂载（写挂载侧，带模式闸与确认链）。
// · 为什么独立族不并入 workspace_*：工作区绑应用沙箱相对路径根（filesDir + DB 行 + 天然
//   全权），挂载绑外部授权目录（URI + 系统权限位 + 每进程激活时序）——两域根语义互斥；
//   复用面 = DB 惯例 / 有界读范式 / read 回执行级分页（composeWorkspaceReadReply 直引）。
// · 公共前置闸（写在公共入口非逐工具重复）：①路径安全（只收相对路径，.. \ \0 与超长拒
//   ——系统持久权只授到挂载根，应用层再拦一层逃逸）；②挂载存在；③进程内懒激活（缓存 Set，
//   首次用时 activatePermission + await——官方「按需激活」勿盲目全量；缓存键含 id|uri|模式位，
//   授权成分变化即重新激活）；④根路径转换。行级「允许 AI 使用」开关已拆除——访问门收敛为
//   助手工具页组卡开关单层。mount_write 专属第⑤闸 = 模式闸（只读挂载拒写）+ 写方式闸与
//   内容上限闸，在执行器内（不进公共闸）。
// · 路径面：listFile 只吃沙箱路径（d.ts 与 API 参考均未声明 URI 支持），挂载根 URI 先经
//   fileUri.FileUri(dirUri).path 转路径，挂载内路径一律路径形态拼接（不经 URI 拼接——目录
//   列表返回解码后的真实名，直接拼 URI 会带非法字符）。mountRootPathFromUri 单源在本件
//  （转换需 fileUri import，与 MountUtil 零 import 纪律冲突）；拼接 joinMountPath 归 MountUtil。
// · 写面：新建无需 CREATE 权限位（官方「父目录有写权限时无需单独授权」）；RENAME 不可持久
//   授权 ⇒ 挂载内无原子替换，整写 = 原位 TRUNC 后写——部分写入不回滚、回执如实报（写失败
//   两相位分开报，见执行器内相位标志）。确认链：新建/追加 = 写操作档跟数据管理档三档
//  （routeConfirmPrompt + dataApproveMode）；**整写覆盖 = 不可逆档恒问**（覆盖销毁旧内容，
//   与删除类同立意——不可逆档不出「本会话内允许」第三键、「一律放行」档也不豁免）；白名单
//   粒度 = 工具级（ToolRuntime 会话键「会话|工具名」）。mount_copy_out 零确认（拷出可逆）。
// · mount_read 分派三路（闸后 stat → 类型判定）：text/other 走文本路（NUL 探测兜底）、
//   image 走图片路（30MB 闸 → 有视觉附图 / 无视觉当场 OCR 三态，零预识别——挂载无 DB 行）、
//   doc 走文档路（尺寸上限闸 → PDF 原件直传窗 → 解析路；无视觉时扫描件页图即识别）。回执
//   复用工作区单源（composeWorkspaceImageReply 等文案实读不含「工作区」指代 = 域无关直引；
//   文档 OCR 措辞用挂载域版 composeMountDocOcrReply）。
// · 回执口径：成功 = 纯文本（工具卡通用文本渲染），失败 = JSON { error }（全工具统一形态）；
//   文案组装单源 MountUtil。不进 ToolPref 白名单（本域零模型可写设置）；defaultEnabled=false
//   不进任何默认集合。
import { buffer } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs, fileUri, fileShare, ReadOptions } from '@kit.CoreFileKit';
import { ToolExecutor, toolArgsParseErrorText, toolErrorText, ConfirmPrompt,
  CONFIRM_LEVEL_IRREVERSIBLE, CONFIRM_LEVEL_WRITE, CONFIRM_ROUTE_HUMAN } from './ToolContracts';
import { routeConfirmPrompt } from './ConfirmRouting';
import { dataApproveMode } from '../AppPreferences';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { queryFolderMounts, mountCopyToWorkspace, queryWorkspaceFiles,
  queryWorkspaceFilesByName } from '../store/ChatDb';
import { FolderMountRow } from '../store/MountDb';
import { MOUNT_LIST_PAGE_DEFAULT, MOUNT_LIST_PAGE_MAX, MOUNT_READ_MAX_CHARS,
  MOUNT_MODE_READ_WRITE, MOUNT_WRITE_MAX_CHARS, MOUNT_WRITE_MODE_APPEND,
  MOUNT_WRITE_MODE_CREATE, MOUNT_WRITE_MODE_OVERWRITE,
  MOUNT_KIND_IMAGE, MOUNT_KIND_DOC,
  MOUNT_IMAGE_MAX_BYTES, MOUNT_COPY_TO_MOUNT_MAX_BYTES,
  MountBrief, MountListEntry, composeMountInventoryReply, composeMountListReply,
  composeMountCopyOutReply, composeMountWriteReply, composeMountCopyInReply,
  composeMountCopyInPartialReply, composeMountDocOcrReply,
  joinMountPath, mountListOffsetBeyond, mountKindOf,
  mountModeLabel, mountModeMask, mountReadTruncatedMeta, mountRelPathNormalize,
  mountRelPathRejectReason, mountToolGrantErrorText, mountWriteModeLabel } from '../MountUtil';
// 格式化两件与 read 分页等复用工作区纯函数单源（禁第二实现）；图片/文档回执族直引（域无关
// 判据见文件头）；workspaceMimeOf 供挂载域文档 mediaType，workspaceDirRejectReason /
// workspaceNameRejectReason 供 copy_in 源路径闸（工作区侧单源直引，禁新写）
import { formatWorkspaceSize, formatWorkspaceTime,
  workspaceMimeOf, deriveWorkspaceDirListing, isWorkspaceDirRow, workspaceDirRejectReason,
  workspaceNameRejectReason, WORKSPACE_ROWS_READ_MAX, WorkspaceFileRow } from '../WorkspaceUtil';
import { composeWorkspaceReadReply, workspaceOverwriteNote, composeWorkspaceImageReply,
  composeWorkspaceDocNativeReply, workspaceParseErrorReply,
  workspaceDocMetaLine } from '../WorkspaceReply';
// 覆盖写旧文摘录预读域已外迁独立件——本件只引入口；★ 读序铁律见该件头注释：调用必须在
// fs.openSync〔TRUNC〕之前（open 即毁旧文）
import { readMountWriteDiffTail } from './ToolMountWriteDiff';
// 图片与文档两路复用面：编码（附件链同规格）/ OCR 引擎三态 / 文档解析桥 / 工作区物理读口
//（base64 全包返 '' 契约，路径无关可直吃挂载绝对路径）/ PDF 原件直传窗两常量
//（能力判据叶子 ToolMediaSupport 单源）
import { encodeImageBase64 } from '../AttachmentUtil';
import { ocrEnabled, runOcr, OcrImageSource, OcrOutcome } from '../OcrEngine';
import { docParser, docHardLimitBytes, pdfTextThin, DocumentParseResult } from '../DocumentParse';
import { DOC_NATIVE_MIN_BYTES, DOC_NATIVE_MAX_BYTES } from './ToolMediaSupport';
import { PendingAttachment, AiImagePart } from './AiTypes';
import { readWorkspaceFileBase64, workspaceFilesDir } from '../store/WorkspaceDb';
// 注册面自 ToolMountDelete 引删除件四导出——ToolMountDelete → 本件的公共骨架导出引用是零环
// 既有单向边，本件反向引其四枚值绑定只在函数体调用期求值（模块顶层零读取，环内求值序安全）；
// 容器自 ToolRegistry 叶引、id 常量自 ToolIds 叶引（注册面自洽三件，聚合根零依赖）
import { MountDeleteExecutor, mountDeleteNeedsConfirm, MOUNT_DELETE_DESC, MOUNT_DELETE_SCHEMA }
  from './ToolMountDelete';
import { toolRegistry } from './ToolRegistry';
import { TOOL_MOUNT_LIST, TOOL_MOUNT_READ, TOOL_MOUNT_WRITE, TOOL_MOUNT_COPY_OUT,
  TOOL_MOUNT_COPY_IN, TOOL_MOUNT_DELETE } from './ToolIds';

// ── desc（请求侧 description，中文三段式——调用时机 / 用法 / 划界；受「能力单源」红线：
//    何时用本工具的引导只住 desc，系统提示词零改动）──
export const MOUNT_LIST_DESC: string =
  '列出文件夹挂载里某个目录的内容。先不传 mountId 调用一次，回执会给出用户已授权给 AI 的文件夹清单与编号。mountId 是挂载编号，取自清单。path 是挂载内的相对路径，多级用 / 分隔，缺省为挂载根目录。返回该目录下的子文件夹与文件，文件带名称、大小与时间，条目按名称排序。条目较多时用 offset 与 limit 分页，回执会给出继续查看的指引。用户问某个授权文件夹里有什么、或提到授权文件夹里的文件时，先用本工具确认，不要凭记忆回答。';

export const MOUNT_READ_DESC: string =
  '读取文件夹挂载里某个文件的内容，支持文本、图片与常见文档。mountId 是挂载编号，取自 mount_list 回执里的清单。path 是文件在挂载内的相对路径，例如 报告.md 或 资料/notes.md。文本按原文返回，每行前面带行号，可用 offset 与 limit 按行分段读取，单行过长时会截断并给出 col 续读位置。单个文件一次最多读取前 12 万个字符，文件更大时回执开头会说明。图片会直接发送给能看图的模型查看，模型不支持看图时会改用文字识别。文档会解析出文字内容，PDF 在模型能看图时会直接发送原件。图片单个最大 30MB，未知类型的文件会返回说明。';

export const MOUNT_WRITE_DESC: string =
  '在文件夹挂载里写入文本文件。只对读写模式的挂载可用，只读挂载会返回错误。mountId 是挂载编号，取自 mount_list 回执里的清单。path 是目标文件在挂载内的相对路径。mode 是写入方式：create 新建文件，文件已存在时会拒绝；append 追加到文件末尾，文件不存在时自动新建；overwrite 覆盖整个文件，每次执行前都会单独征求用户确认。content 是要写入的文本，一次最多 12 万个字符，更长内容分多次追加写入。写入的是用户授权文件夹里的原文件，修改会直接生效。写入失败时已写入的部分不会回滚，回执会如实说明。';

export const MOUNT_COPY_OUT_DESC: string =
  '把文件夹挂载里的一个文件复制到文件工作区，产生一份副本，原文件不变。适合需要对文件做进一步加工、又不希望改动原文件的场景。mountId 是挂载编号，取自 mount_list 回执里的清单。path 是文件在挂载内的相对路径。dir 是工作区里的目标文件夹，缺省保存到工作区根目录。单个文件最大 30MB，工作区容量不足时会失败并说明。复制的是副本，删除或修改副本不影响挂载里的原文件。';

// copy_in 方向句（防后续维护者按直觉猜反）：出工作区、进挂载——与 MOUNT_COPY_OUT_DESC
// （出挂载、进工作区）互为反向
export const MOUNT_COPY_IN_DESC: string =
  '把文件工作区里的一个文件复制进文件夹挂载，产生一份副本。mountId 是挂载编号，取自 mount_list 回执里的清单。workspacePath 是工作区里的相对路径，多级用 / 分隔，例如 报告.md 或 资料/notes.md。dir 是挂载里的目标文件夹，缺省复制到挂载根目录。name 是新文件名，缺省沿用原文件名。只对读写模式的挂载可用，只读挂载会返回错误。目标已有同名文件时会先征求用户确认，确认后原文件内容会被替换。单个文件最大 30MB。复制的是副本，之后修改挂载里的文件不影响工作区里的原文件。';

// ── schema（JSON Schema 原串——ArkTS 禁无类型对象字面量，全工具同款姿势）──
export const MOUNT_LIST_SCHEMA: string = '{"type":"object","properties":{' +
  '"mountId":{"type":"number","description":"挂载编号，取自不传 mountId 调用时回执里的挂载清单。不传时返回挂载清单本身。"},' +
  '"path":{"type":"string","description":"挂载内的相对路径，多级用 / 分隔，缺省为挂载根目录。"},' +
  '"offset":{"type":"number","description":"起始序号，从 0 起，不传则从第一个条目开始。"},' +
  '"limit":{"type":"number","description":"本次最多返回的条目数，不传则用缺省上限。"}}}';

export const MOUNT_READ_SCHEMA: string = '{"type":"object","properties":{' +
  '"mountId":{"type":"number","description":"挂载编号，取自 mount_list 回执里的挂载清单。"},' +
  '"path":{"type":"string","description":"要读取的文件在挂载内的相对路径，例如 资料/notes.md。"},' +
  '"offset":{"type":"number","description":"起始行号，从 1 起，不传则从第 1 行读。"},' +
  '"limit":{"type":"number","description":"本次最多读取的行数，不传则读到长度上限。"},' +
  '"col":{"type":"number","description":"行内起始字符位置，从 1 起，不传则从行首读。继续读取被截断的超长行时按回执指引传入。"}},' +
  '"required":["mountId","path"]}';

// ★ mode 补 enum：值集单源 = MountUtil 三常量编译期拼出（改常量值即同步改 enum，零第二份
// 值域）；P0 校验器（ToolArgsCheck 第④项 enum 越界）由此立即生效；执行器预检/执行双点守卫
// 不动——纵深防御；坑91 防御 = 拼接产物须合法 JSON（断言钉 parse 验证）。
export const MOUNT_WRITE_SCHEMA: string = '{"type":"object","properties":{' +
  '"mountId":{"type":"number","description":"挂载编号，取自 mount_list 回执里的挂载清单。必须是读写模式的挂载。"},' +
  '"path":{"type":"string","description":"要写入的文件在挂载内的相对路径，例如 资料/笔记.md。父目录必须已存在。"},' +
  '"mode":{"type":"string","enum":["' + MOUNT_WRITE_MODE_CREATE + '","' +
  MOUNT_WRITE_MODE_APPEND + '","' + MOUNT_WRITE_MODE_OVERWRITE + '"],' +
  '"description":"写入方式。create 新建文件，已存在会拒绝。append 追加到文件末尾，不存在时自动新建。overwrite 覆盖整个文件，每次执行前都会单独征求用户确认。"},' +
  '"content":{"type":"string","description":"要写入的文本内容，一次最多 12 万个字符，更长内容分多次追加。"}},' +
  '"required":["mountId","path","mode","content"]}';

export const MOUNT_COPY_OUT_SCHEMA: string = '{"type":"object","properties":{' +
  '"mountId":{"type":"number","description":"挂载编号，取自 mount_list 回执里的挂载清单。"},' +
  '"path":{"type":"string","description":"要复制的文件在挂载内的相对路径，例如 资料/报告.pdf。"},' +
  '"dir":{"type":"string","description":"工作区里的目标文件夹，多级用 / 分隔，缺省保存到工作区根目录。"}},' +
  '"required":["mountId","path"]}';

export const MOUNT_COPY_IN_SCHEMA: string = '{"type":"object","properties":{' +
  '"workspacePath":{"type":"string","description":"要复制的工作区文件相对路径，多级用 / 分隔，例如 报告.md 或 资料/notes.md。"},' +
  '"mountId":{"type":"number","description":"挂载编号，取自 mount_list 回执里的挂载清单。必须是读写模式的挂载。"},' +
  '"dir":{"type":"string","description":"挂载里的目标文件夹，多级用 / 分隔，缺省复制到挂载根目录。"},' +
  '"name":{"type":"string","description":"复制后的新文件名，缺省沿用原文件名。"}},' +
  '"required":["workspacePath","mountId"]}';

// ── args 解析（工具域共用形态：JSON.parse 后按键取；解析失败回执由调用处给。两解析器升
//    导出供外迁域件 ToolMountDelete 引）──
export function argsString(parsed: Record<string, Object>, key: string): string {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'string' ? raw : '';
}

function argsNumber(parsed: Record<string, Object>, key: string): number {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'number' ? raw : Number.NaN;
}

// mountId 取数（number 为主；模型偶发传数字串也收——非数/非正落 0，调用方按 0 走清单模式）
export function argsMountId(parsed: Record<string, Object>, key: string): number {
  const raw: Object | undefined = parsed[key];
  if (typeof raw === 'number') {
    return raw;
  }
  if (typeof raw === 'string') {
    const n: number = Number.parseInt(raw, 10);
    return Number.isFinite(n) ? n : 0;
  }
  return 0;
}

// ── 公共前置闸（①②③④；返回 rejectText '' = 通过）──

// 闸结果（ArkTS 无元组返回形态，用显式接口；rejectText 非空即拒，resolved 各字段仅在通过时
// 可用）。本接口与闸/激活骨架升导出，供外迁域件 ToolMountDelete 引（本域六件共用同一骨架，
// 单源在此不复制）
export interface MountGateOutcome {
  rejectText: string;
  row: FolderMountRow | undefined;
  relPath: string;
  rootPath: string;
}

// 已激活授权缓存（进程内懒激活——官方「按需激活」；键含行 id / 目录 URI / 模式位掩码三授权
// 成分：切模式或重新授权换址后缓存未命中即重新激活，授权位已变而按旧激活态放行不可能发生。
// 进程死亡自然重置——缓存不落任何持久面）
const activatedGrantKeys: Set<string> = new Set();

function grantKeyOf(row: FolderMountRow): string {
  return row.id + '|' + row.dirUri + '|' + mountModeMask(row.mode);
}

// 懒激活（第③闸本体；失败上抛由调用方映射文案——不吞错不给假绿。升导出供外迁域件
// ToolMountDelete 的确认预检探测前复用）
export async function ensureMountActivated(row: FolderMountRow): Promise<void> {
  const key: string = grantKeyOf(row);
  if (activatedGrantKeys.has(key)) {
    return;
  }
  const policy: fileShare.PolicyInfo = { uri: row.dirUri, operationMode: mountModeMask(row.mode) };
  await fileShare.activatePermission([policy]);
  activatedGrantKeys.add(key);
}

// 挂载根 URI → 文件系统路径（官方指名转换法；尾斜杠剥除防拼接出双斜杠）。导出单源与浏览页
//（用户面）共用，禁两份并存；落本件而非 MountUtil = 转换需 fileUri import，与 MountUtil 的
// 零 import 纪律冲突；路径拼接 joinMountPath 纯字符串操作，归 MountUtil
export function mountRootPathFromUri(dirUri: string): string {
  const converted: string = new fileUri.FileUri(dirUri).path;
  return converted.endsWith('/') ? converted.substring(0, converted.length - 1) : converted;
}

// per-uri 原因码（err.code 13900001 + data[0].code；形态照 MountManagePage.firstPolicyCode）
function policyCodeOf(e: Object): number {
  const err: BusinessError<Array<fileShare.PolicyErrorResult>> =
    e as BusinessError<Array<fileShare.PolicyErrorResult>>;
  if (err.code === 13900001 && err.data !== undefined && err.data.length > 0) {
    return err.data[0].code;
  }
  return 0;
}

// 公共闸：①路径闸 ②查行（不存在 / 空清单逐态给指引）③懒激活 ④根路径转换。
// 顺序纪律：路径闸在最前（不触库不触系统），激活在查行之后（对不存在的挂载不做系统调用），
// 根转换在激活之后（激活失败先报授权文案，不给路径解析误导）。「允许 AI 使用」行级开关已
// 拆除（单层门 = 助手工具页组卡开关——本闸不查行级访问位）。升导出（外迁域件
// ToolMountDelete 引同一骨架，禁第二实现）
export async function mountGate(mountId: number, relRaw: string): Promise<MountGateOutcome> {
  const reject: string = mountRelPathRejectReason(relRaw);
  if (reject !== '') {
    return { rejectText: reject, row: undefined, relPath: '', rootPath: '' };
  }
  const relPath: string = mountRelPathNormalize(relRaw);
  let rows: FolderMountRow[];
  try {
    rows = await queryFolderMounts();
  } catch (e) {
    return { rejectText: '挂载清单读取失败：' + toolErrorText(e), row: undefined, relPath: relPath,
      rootPath: '' };
  }
  if (rows.length === 0) {
    return { rejectText: '还没有已授权的文件夹。请让用户在 设置 → 文件夹挂载 中添加。',
      row: undefined, relPath: relPath, rootPath: '' };
  }
  let row: FolderMountRow | undefined = undefined;
  for (const candidate of rows) {
    if (candidate.id === mountId) {
      row = candidate;
      break;
    }
  }
  if (row === undefined) {
    return { rejectText: '没有编号为 ' + mountId + ' 的挂载。请先调用 mount_list 查看挂载清单。',
      row: undefined, relPath: relPath, rootPath: '' };
  }
  try {
    await ensureMountActivated(row);
  } catch (e) {
    return { rejectText: mountToolGrantErrorText(policyCodeOf(e)), row: row, relPath: relPath,
      rootPath: '' };
  }
  let rootPath: string = '';
  try {
    rootPath = mountRootPathFromUri(row.dirUri);
  } catch (e) {
    return { rejectText: '「' + row.name + '」的目录路径无法解析。请让用户在' +
      ' 设置 → 文件夹挂载 中检查这个挂载。', row: row, relPath: relPath, rootPath: '' };
  }
  return { rejectText: '', row: row, relPath: relPath, rootPath: rootPath };
}

// fs 失败 → 模型面文案（13900002 未找到走各执行器专属指引；13900012 / 13900001 授权类归
// 重新授权指引；其余附 code 透传——底层报错不美化）
function mountFsFailText(e: Object, missingText: string): string {
  const code: number = (e as BusinessError).code;
  if (code === 13900002) {
    return missingText;
  }
  if (code === 13900012 || code === 13900001) {
    return mountToolGrantErrorText(policyCodeOf(e));
  }
  const tail: string = typeof code === 'number' && code !== 0 ? '（code ' + code + '）' : '';
  return '操作失败' + tail + '：' + toolErrorText(e);
}

// 挂载不再存在（根路径未找到——目录被改名/删除）时的指引（根与子路径两态）
function mountGoneText(mountName: string, relPath: string): string {
  if (relPath === '') {
    return '找不到「' + mountName + '」对应的文件夹，它可能已被移动、改名或删除。' +
      '请让用户到 设置 → 文件夹挂载 中重新授权。';
  }
  return '挂载「' + mountName + '」里没有「' + relPath + '」这个位置。' +
    '请先从根目录开始用 mount_list 逐级查看。';
}

// ── mount_list：清单模式（无 mountId）+ 目录模式（有 mountId）──
export class MountListExecutor implements ToolExecutor {
  async execute(argsJson: string, _ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const mountId: number = argsMountId(parsed, 'mountId');
    if (!(mountId > 0)) {
      return listMountInventory();
    }
    const gate: MountGateOutcome = await mountGate(mountId, argsString(parsed, 'path'));
    if (gate.rejectText !== '') {
      return JSON.stringify({ error: gate.rejectText });
    }
    const row: FolderMountRow = gate.row as FolderMountRow; // 闸通过后 row 必在场（闸内各拒态均早退）
    const dirPath: string = joinMountPath(gate.rootPath, gate.relPath);
    let names: string[];
    try {
      // listFile 只吃沙箱路径（见文件头路径面注）——根已转路径，此处路径形态
      names = fs.listFileSync(dirPath);
    } catch (e) {
      return JSON.stringify({ error: mountFsFailText(e, mountGoneText(row.name, gate.relPath)) });
    }
    names.sort();
    const total: number = names.length;
    const offset: number = normalizeListOffset(argsNumber(parsed, 'offset'));
    const limit: number = normalizeListLimit(argsNumber(parsed, 'limit'));
    // 越界判定经纯函数单源：空目录（total=0）恒不越界——空态消息由 composeMountListReply 承载
    //（原内联判据对空目录 0 >= 0 恒真致误报越界）
    if (mountListOffsetBeyond(total, offset)) {
      return JSON.stringify({ error: '挂载「' + row.name + '」共 ' + total +
        ' 个条目，请求的起始序号已超出末尾。可用 offset=0 从第一个条目查看。' });
    }
    const pageNames: string[] = names.slice(offset, Math.min(offset + limit, total));
    const entries: MountListEntry[] = [];
    for (const name of pageNames) {
      entries.push(statMountEntry(joinMountPath(gate.rootPath, gate.relPath), name));
    }
    return composeMountListReply(row.name, gate.relPath, total, offset, entries);
  }
}

// 清单模式（mount_list 无 mountId）：读行 → 真实清单回执（模型据此拿 mountId）
async function listMountInventory(): Promise<string> {
  try {
    const rows: FolderMountRow[] = await queryFolderMounts();
    const briefs: MountBrief[] = [];
    for (const row of rows) {
      briefs.push({ id: row.id, name: row.name, mode: row.mode });
    }
    return composeMountInventoryReply(briefs);
  } catch (e) {
    return JSON.stringify({ error: '挂载清单读取失败：' + toolErrorText(e) });
  }
}

// 分页参数归一（offset 缺省/负数/非数落 0；limit 缺省/非正落缺省页、超页上限钳制）
function normalizeListOffset(raw: number): number {
  return Number.isFinite(raw) && raw > 0 ? Math.floor(raw) : 0;
}

function normalizeListLimit(raw: number): number {
  if (!Number.isFinite(raw) || raw <= 0) {
    return MOUNT_LIST_PAGE_DEFAULT;
  }
  const n: number = Math.floor(raw);
  return n > MOUNT_LIST_PAGE_MAX ? MOUNT_LIST_PAGE_MAX : n;
}

// 单条目属性（stat 现读；失败落「无法读取属性」行——不阻断整页。★ 坑32：Stat.mtime 单位是
// 秒，×1000 转毫秒与全仓时间戳口径一致）
function statMountEntry(dirPath: string, name: string): MountListEntry {
  try {
    const st: fs.Stat = fs.statSync(dirPath + '/' + name);
    return { name: name, isDir: st.isDirectory(), sizeText: formatWorkspaceSize(st.size),
      timeText: formatWorkspaceTime(st.mtime * 1000) };
  } catch (e) {
    return { name: name, isDir: false, sizeText: '', timeText: '' };
  }
}

// ── mount_read：有界读挂载内文本文件 ──

// 有界读切片（binary = 二进制探测命中）
interface MountTextSlice {
  text: string;
  truncated: boolean;
  binary: boolean;
}

// 有界读上限（字节；↔ 附件域 readAttachmentText 同构：UTF-8 单字符至多 4 字节，多读 8 字节
// 避开边界，再按字符裁到 MOUNT_READ_MAX_CHARS）
const MOUNT_READ_MAX_BYTES: number = MOUNT_READ_MAX_CHARS * 4 + 8;

// 有界读（镜像附件域 readAttachmentText 的字节数快路径 + 超限按字节读两段式；差异 = 本路
// 需二进制探测——解码文本含 NUL 即判非文本；读失败上抛由调用方映射文案，不给半截假文本）
function readMountTextPrefix(fullPath: string, sizeBytes: number): MountTextSlice {
  const full: boolean = sizeBytes <= MOUNT_READ_MAX_BYTES;
  const readLen: number = full ? sizeBytes : MOUNT_READ_MAX_BYTES;
  let file: fs.File | null = null;
  try {
    file = fs.openSync(fullPath, fs.OpenMode.READ_ONLY);
    const ab: ArrayBuffer = new ArrayBuffer(readLen);
    const readOptions: ReadOptions = { offset: 0, length: readLen };
    const got: number = readLen > 0 ? fs.readSync(file.fd, ab, readOptions) : 0;
    let text: string = buffer.from(ab, 0, got).toString('utf-8');
    if (!full && text.endsWith('\uFFFD')) {
      // 截断点落在多字节字符中间（残字节解成替换字符）——去掉残字，不把 � 上屏
      text = text.substring(0, text.length - 1);
    }
    if (text.indexOf('\u0000') >= 0) {
      return { text: '', truncated: false, binary: true };
    }
    if (text.length > MOUNT_READ_MAX_CHARS) {
      return { text: text.substring(0, MOUNT_READ_MAX_CHARS), truncated: true, binary: false };
    }
    return { text: text, truncated: !full, binary: false };
  } finally {
    if (file !== null) {
      fs.closeSync(file); // 成对释放：open 同段 close，异常路径同样走到
    }
  }
}

// ── mount_read 图片路：镜像 ToolWorkspace 工作区图片路，差异两处：①大小闸（挂载域新增
//    30MB，防大图顶穿读盘与编码——工作区路无此闸）②零预识别（预识别是工作区 DB 行配套
//    机制，挂载无行——无视觉恒当场 OCR）。回执直引 composeWorkspaceImageReply（文案域无关）──
async function readMountImageReply(relPath: string, fullPath: string, sizeBytes: number,
  ctx: ToolExecutionContext): Promise<string> {
  const name: string = relPath.substring(relPath.lastIndexOf('/') + 1);
  if (sizeBytes > MOUNT_IMAGE_MAX_BYTES) {
    return JSON.stringify({ error: '图片「' + name + '」超过 ' +
      (MOUNT_IMAGE_MAX_BYTES / (1024 * 1024)) + 'MB，暂不支持读取。' });
  }
  if (ctx.hasVision) {
    const imgAtt: PendingAttachment = { fileId: relPath, name: name,
      mediaType: workspaceMimeOf(name), size: sizeBytes, kind: 'image', localPath: fullPath };
    let part: AiImagePart;
    try {
      part = await encodeImageBase64(imgAtt); // 附件链同规格：2048 长边缩边 + JPEG q85
    } catch (e) {
      return JSON.stringify({ error: '「' + name + '」图片读取失败：' + (e as Error).message +
        '。请让用户在应用内查看该图片。' });
    }
    if (!ctx.collectImage(part.mimeType, part.data)) {
      // 挂载失败 = 本轮 user 消息不可达（重发链）或超单发送图数上限（TOOL_IMAGE_ATTACH_MAX）
      return composeWorkspaceImageReply(name, 'attach_failed');
    }
    return composeWorkspaceImageReply(name, 'attached');
  }
  // 无视觉：OCR 三态（关 → 指引；跑 → 引擎名 + 文字 / 无文字 / 失败——回执单源承载）
  if (!ocrEnabled()) {
    return composeWorkspaceImageReply(name, 'ocr_disabled');
  }
  const sources: OcrImageSource[] = [{ kind: 'path', data: fullPath }];
  const ocr: OcrOutcome = await runOcr(sources, (_msg: string): void => {
    // 回退 toast 通道空实现（工具路告知由回执引擎名承载——工作区图片路同款）
  });
  if (!ocr.ok) {
    return composeWorkspaceImageReply(name, 'ocr_failed');
  }
  if (ocr.text === '') {
    return composeWorkspaceImageReply(name, 'ocr_empty');
  }
  return composeWorkspaceImageReply(name, 'ocr_text', ocr.text, ocr.engine);
}

// ── mount_read 文档路：镜像 ToolWorkspace 工作区 doc 路三段——尺寸上限闸 → PDF 原件直传窗
//    → 解析路。挂载域差异两处：①无视觉分支 = 「有页图（扫描件）即识别」（识别文本回执用
//    文档措辞版 composeMountDocOcrReply）②零预识别与零校对回写（绑工作区 DB 行，挂载无行）──
async function readMountDocReply(relPath: string, fullPath: string, sizeBytes: number,
  offset: number, limit: number, col: number, ctx: ToolExecutionContext): Promise<string> {
  const name: string = relPath.substring(relPath.lastIndexOf('/') + 1);
  // 最小 PendingAttachment：解析桥只读 localPath 字节用 name/mediaType/size（实读
  // parseBase64/readBase64 消费面），fileId 无消费方取路径代填
  const att: PendingAttachment = { fileId: relPath, name: name,
    mediaType: workspaceMimeOf(name), size: sizeBytes, kind: 'doc', localPath: fullPath };
  const hardLimit: number = docHardLimitBytes(att);
  const limitText: string = formatWorkspaceSize(hardLimit);
  if (hardLimit > 0 && sizeBytes > hardLimit) {
    return JSON.stringify({ error: workspaceParseErrorReply(name, 'file_too_large', limitText) });
  }
  // PDF 原件直传窗（三条件 = 有视觉 ∧ pdf ∧ 尺寸窗 4KB~8MB；窗常量单源 ToolMediaSupport；
  // 挂载失败 / 读失败 / 空字节一律不 return、顺序落入解析路——同工作区口径，同调用内回落）
  if (ctx.hasVision && att.mediaType === 'application/pdf' &&
    sizeBytes >= DOC_NATIVE_MIN_BYTES && sizeBytes <= DOC_NATIVE_MAX_BYTES) {
    const b64: string = readWorkspaceFileBase64(fullPath); // 路径无关 fd 读口（全包返 '' 契约）
    if (b64 !== '' && ctx.collectImage('application/pdf', b64)) {
      return composeWorkspaceDocNativeReply(name);
    }
  }
  let parsed: DocumentParseResult;
  try {
    parsed = await docParser.parseAttachment(att);
  } catch (e) {
    return JSON.stringify({ error: workspaceParseErrorReply(name, (e as Error).message, limitText) });
  }
  if (ctx.hasVision) {
    if (parsed.success !== true) {
      return JSON.stringify({ error: workspaceParseErrorReply(name, parsed.error, limitText) });
    }
    const thinV: boolean = pdfTextThin(name, parsed.textChars, parsed.textPages);
    if (thinV && parsed.pageImages.length > 0) {
      let attachedAll: boolean = true;
      for (const page of parsed.pageImages) {
        if (!ctx.collectPageImage(page.mimeType, page.data)) {
          attachedAll = false; // 页图整批放弃 → 纯文本回执（thin 提示句照给）
          break;
        }
      }
      if (attachedAll) {
        const metaV: string = workspaceDocMetaLine(parsed.engine, parsed.pageCount, false,
          parsed.warning) + '页面图片已随本轮请求发送。';
        return composeWorkspaceReadReply(relPath, parsed.text, offset, limit, metaV, col);
      }
    }
    return composeWorkspaceReadReply(relPath, parsed.text, offset, limit,
      workspaceDocMetaLine(parsed.engine, parsed.pageCount, thinV, parsed.warning), col);
  }
  // 无视觉（挂载无预识别：恒当场判定）
  if (parsed.success !== true) {
    return JSON.stringify({ error: workspaceParseErrorReply(name, parsed.error, limitText) });
  }
  const thin: boolean = pdfTextThin(name, parsed.textChars, parsed.textPages);
  if (!(thin && parsed.pageImages.length > 0)) {
    // 非扫描件（文字层文档含 docx 等）：解析文本照常（空文本句子由读回执承载）
    return composeWorkspaceReadReply(relPath, parsed.text, offset, limit,
      workspaceDocMetaLine(parsed.engine, parsed.pageCount, thin, parsed.warning), col);
  }
  // 扫描件页图即识别（决明 2026-10-08 拍板口径——有页图就走，不要求文本为空）
  if (!ocrEnabled()) {
    return composeMountDocOcrReply(name, 'ocr_disabled');
  }
  const sources: OcrImageSource[] = [];
  for (const page of parsed.pageImages) {
    sources.push({ kind: 'base64', data: page.data });
  }
  const ocr: OcrOutcome = await runOcr(sources, (_msg: string): void => {
    // 回退 toast 通道空实现（回执引擎名承载——同图片路）
  });
  if (!ocr.ok) {
    return composeMountDocOcrReply(name, 'ocr_failed');
  }
  if (ocr.text === '') {
    return composeMountDocOcrReply(name, 'ocr_empty');
  }
  return composeMountDocOcrReply(name, 'ocr_text', ocr.text, ocr.engine);
}

export class MountReadExecutor implements ToolExecutor {
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const mountId: number = argsMountId(parsed, 'mountId');
    if (!(mountId > 0)) {
      return JSON.stringify({ error: '缺少挂载编号。请先调用 mount_list 查看挂载清单，' +
        '再带 mountId 与 path 重试。' });
    }
    const gate: MountGateOutcome = await mountGate(mountId, argsString(parsed, 'path'));
    if (gate.rejectText !== '') {
      return JSON.stringify({ error: gate.rejectText });
    }
    const row: FolderMountRow = gate.row as FolderMountRow; // 闸通过后 row 必在场
    if (gate.relPath === '') {
      return JSON.stringify({ error: '请给出要读取的文件路径。' +
        '可以先用 mount_list 查看挂载里的文件。' });
    }
    const fullPath: string = joinMountPath(gate.rootPath, gate.relPath);
    let st: fs.Stat;
    try {
      st = fs.statSync(fullPath);
    } catch (e) {
      return JSON.stringify({ error: mountFsFailText(e, mountGoneText(row.name, gate.relPath)) });
    }
    if (st.isDirectory()) {
      return JSON.stringify({ error: '「' + gate.relPath + '」是文件夹，不是文件。' +
        '要看里面的内容，把它的路径填入 mount_list 的 path。' });
    }
    // ★ M3 笔2 分派（闸后 stat → 类型判定）：image / doc 两路各有专属链；text 与未知后缀
    //（other）维持文本路（NUL 探测兜底保留——未知后缀可能是文本，二进制才拒）
    const kind: string = mountKindOf(gate.relPath);
    if (kind === MOUNT_KIND_IMAGE) {
      return await readMountImageReply(gate.relPath, fullPath, st.size, ctx);
    }
    if (kind === MOUNT_KIND_DOC) {
      return await readMountDocReply(gate.relPath, fullPath, st.size,
        argsNumber(parsed, 'offset'), argsNumber(parsed, 'limit'), argsNumber(parsed, 'col'), ctx);
    }
    let slice: MountTextSlice;
    try {
      slice = readMountTextPrefix(fullPath, st.size);
    } catch (e) {
      return JSON.stringify({ error: mountFsFailText(e, mountGoneText(row.name, gate.relPath)) });
    }
    if (slice.binary) {
      return JSON.stringify({ error: '「' + gate.relPath +
        '」不是文本文件，暂不支持读取内容。请只使用它的名称与大小信息。' });
    }
    const offset: number = argsNumber(parsed, 'offset');
    const limit: number = argsNumber(parsed, 'limit');
    const col: number = argsNumber(parsed, 'col');
    const meta: string = slice.truncated ? mountReadTruncatedMeta(slice.text.length) : '';
    // 回执行级分页复用工作区单源（首尾越界 / 行内截断 col 指针 / 代理对防护全在该函数内）
    return composeWorkspaceReadReply(gate.relPath, slice.text, offset, limit, meta, col);
  }
}

// ── mount_write：写挂载内文本文件（三方式）──

// 确认预检（写确认类——契约：全包 try/catch 恒不抛）。fail-closed 分阶段：解析失败等「执行器
// 必有错误回执拦下」的坏形态返 null；**已判定真实写操作之后**的异常（查库失败等）返保守人工
// 卡不返 null（null = 直通，预检挂而执行成 = 写动作无卡直发）。档位：新建/追加 = 写操作档跟
// 数据管理档三档（routeConfirmPrompt 归一——「一律放行」只豁免本档）；**整写覆盖 = 不可逆档**
//（routeConfirmPrompt 对不可逆档恒不豁免，「每次确认」直指人工、其余交审批闸且模型放行也落
// 人工卡——与删除类同立意，确认链既有语义零新机制）
export async function mountWriteNeedsConfirm(argsJson: string,
  _ctx: ToolExecutionContext): Promise<ConfirmPrompt | null> {
  let mountId = 0;
  let path = '';
  let writeMode = '';
  let contentLen = 0;
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    mountId = argsMountId(parsed, 'mountId');
    path = argsString(parsed, 'path');
    writeMode = argsString(parsed, 'mode').trim();
    const content = parsed['content'];
    contentLen = typeof content === 'string' ? content.length : 0;
  } catch (e) {
    return null; // 坏形态：执行器必有参数错误回执
  }
  // 执行器必拒的形态不走确认（参数缺/方式非法/超长——错误回执即反馈，不占用户一次作答）
  if (!(mountId > 0) || path.trim() === '' || mountWriteModeLabel(writeMode) === '' ||
    contentLen > MOUNT_WRITE_MAX_CHARS) {
    return null;
  }
  const relPath: string = mountRelPathNormalize(path);
  try {
    const rows: FolderMountRow[] = await queryFolderMounts();
    let row: FolderMountRow | undefined = undefined;
    for (const candidate of rows) {
      if (candidate.id === mountId) {
        row = candidate;
        break;
      }
    }
    if (row === undefined) {
      return null; // 执行器查行闸拒
    }
    if (row.mode !== MOUNT_MODE_READ_WRITE) {
      return null; // 只读挂载：执行器模式闸拒（无需弹卡问人一个必拒动作）
    }
    const overwrite: boolean = writeMode === MOUNT_WRITE_MODE_OVERWRITE;
    const prompt: ConfirmPrompt = {
      text: overwrite ?
        '助手要覆盖挂载「' + row.name + '」里的整个文件「' + relPath + '」，原内容将被替换。' :
        writeMode === MOUNT_WRITE_MODE_CREATE ?
          '助手要在挂载「' + row.name + '」里新建文件「' + relPath + '」。' :
          '助手要向挂载「' + row.name + '」里的文件「' + relPath + '」追加内容。',
      level: overwrite ? CONFIRM_LEVEL_IRREVERSIBLE : CONFIRM_LEVEL_WRITE,
      detail: '写入方式：' + mountWriteModeLabel(writeMode) + ' · 内容约 ' + contentLen +
        ' 字符 · 目标是用户授权的原文件，修改直接生效'
    };
    // 三档归一单点（数据管理档：ask 直指人工 / auto 只豁免写操作档 / 其余交审批闸）
    return routeConfirmPrompt(prompt, dataApproveMode());
  } catch (e) {
    // fail-closed：已判定写操作后的异常返保守人工卡（对齐 H3-5 写确认类口径）
    return {
      text: '写入前的确认检查出现异常，本次写入需要你确认。',
      level: CONFIRM_LEVEL_WRITE,
      route: CONFIRM_ROUTE_HUMAN
    };
  }
}

// ── mount_write 覆盖写 diff 预读：域已外迁 ToolMountWriteDiff.ets，执行器只引入口
//    readMountWriteDiffTail；★ 读序铁律：必须在执行器 fs.openSync（overwrite ⊇ TRUNC）之前
//    调用——open 即毁旧文 ──

export class MountWriteExecutor implements ToolExecutor {
  async execute(argsJson: string, _ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const mountId: number = argsMountId(parsed, 'mountId');
    if (!(mountId > 0)) {
      return JSON.stringify({ error: '缺少挂载编号。请先调用 mount_list 查看挂载清单，' +
        '再带 mountId 与 path 重试。' });
    }
    const writeMode: string = argsString(parsed, 'mode').trim();
    if (mountWriteModeLabel(writeMode) === '') {
      return JSON.stringify({ error: '写入方式必须是 create、append 或 overwrite。' });
    }
    const content: string = argsString(parsed, 'content');
    if (content.length > MOUNT_WRITE_MAX_CHARS) {
      return JSON.stringify({ error: '单次写入最多 ' + MOUNT_WRITE_MAX_CHARS +
        ' 个字符。更长内容请分多次用 append 追加写入。' });
    }
    const gate: MountGateOutcome = await mountGate(mountId, argsString(parsed, 'path'));
    if (gate.rejectText !== '') {
      return JSON.stringify({ error: gate.rejectText });
    }
    const row: FolderMountRow = gate.row as FolderMountRow; // 闸通过后 row 必在场
    if (row.mode !== MOUNT_MODE_READ_WRITE) {
      return JSON.stringify({ error: '「' + row.name + '」是' + mountModeLabel(row.mode) +
        '挂载，不能写入。请让用户在 设置 → 文件夹挂载 中把它切换为读写模式。' });
    }
    if (gate.relPath === '') {
      return JSON.stringify({ error: '请给出要写入的文件路径，不能写挂载根目录。' });
    }
    const fullPath: string = joinMountPath(gate.rootPath, gate.relPath);
    // create 已存在拒（openSync 无 EXCL 旗标——单应用进程内无并发写手，stat 后 open 的窗口
    // 可忽略；openSync 明文支持 URI 但本域统一走转换后路径，与读面同源）
    if (writeMode === MOUNT_WRITE_MODE_CREATE && fs.accessSync(fullPath)) {
      return JSON.stringify({ error: '「' + gate.relPath + '」已经存在。要追加内容用 append，' +
        '要替换整个文件用 overwrite。' });
    }
    // 覆盖写旧文摘录预读——**必须在下方 fs.openSync（overwrite ⊇ TRUNC）之前**：open 即毁
    // 旧文；读失败/超阈/非文本一律降级无尾行（内部全包，'' 即不附加，写语义零变化）
    let diffTail: string = '';
    if (writeMode === MOUNT_WRITE_MODE_OVERWRITE) {
      diffTail = readMountWriteDiffTail(fullPath, gate.relPath, content);
    }
    const openMode: number = writeMode === MOUNT_WRITE_MODE_APPEND ?
      fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.APPEND :
      fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC;
    // 期望字节数（utf-8，byteLength 静态法——@ohos.buffer 的 Buffer 无 byteLength 实例属性；
    // writeSync 返回实写字节——两者不等 = 部分写入，回执如实报）
    const expectedBytes: number = content === '' ? 0 : buffer.byteLength(content, 'utf-8');
    let writtenBytes: number = 0;
    // 失败相位标志：open 成功即 TRUNC（overwrite/create）或 APPEND 已生效——此后的失败必须
    // 如实报「文件可能被截断/只写入了一部分」，不得与「打开失败 = 文件未动」混为一条文案
    //（writeSync 抛错拿不到 writtenBytes，只落通用「操作失败」会与「部分写入不回滚、回执
    // 如实报」的安全面承诺相抵）
    let openedForWrite: boolean = false;
    try {
      const file: fs.File = fs.openSync(fullPath, openMode);
      openedForWrite = true;
      try {
        writtenBytes = content === '' ? 0 : fs.writeSync(file.fd, content);
      } finally {
        fs.closeSync(file); // 成对释放：open 同段 close，异常路径同样走到
      }
    } catch (e) {
      if (openedForWrite) {
        const afterOpen: string = writeMode === MOUNT_WRITE_MODE_OVERWRITE ?
          '文件原内容可能已被截断，新内容可能只写入了一部分' : '文件内容可能只写入了一部分';
        return JSON.stringify({ error: '写入中断：' + toolErrorText(e) + '。' + afterOpen +
          '，请先读取文件确认现状，再决定重写或补写。' });
      }
      // 打开失败的未找到 = 父目录不存在（openSync CREATE 只建文件不建目录）——给逐级确认指引
      return JSON.stringify({
        error: mountFsFailText(e, '挂载「' + row.name + '」里没有「' + gate.relPath +
          '」的位置。父目录不存在时无法创建文件，请先用 mount_list 逐级确认完整路径。') });
    }
    return composeMountWriteReply(gate.relPath, writeMode, writtenBytes, expectedBytes, diffTail);
  }
}

// ── mount_copy_out：挂载内文件复制进文件工作区（零确认——源只读、写沙箱、可逆；落库闸链
//    与行 upsert 单源 WorkspaceDb.mountCopyIntoWorkspace，经 ChatDb 委托）──
export class MountCopyOutExecutor implements ToolExecutor {
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const mountId: number = argsMountId(parsed, 'mountId');
    if (!(mountId > 0)) {
      return JSON.stringify({ error: '缺少挂载编号。请先调用 mount_list 查看挂载清单，' +
        '再带 mountId 与 path 重试。' });
    }
    const gate: MountGateOutcome = await mountGate(mountId, argsString(parsed, 'path'));
    if (gate.rejectText !== '') {
      return JSON.stringify({ error: gate.rejectText });
    }
    const row: FolderMountRow = gate.row as FolderMountRow; // 闸通过后 row 必在场
    if (gate.relPath === '') {
      return JSON.stringify({ error: '请给出要复制的文件路径。' +
        '可以先用 mount_list 查看挂载里的文件。' });
    }
    const fullPath: string = joinMountPath(gate.rootPath, gate.relPath);
    let st: fs.Stat;
    try {
      st = fs.statSync(fullPath);
    } catch (e) {
      return JSON.stringify({ error: mountFsFailText(e, mountGoneText(row.name, gate.relPath)) });
    }
    if (st.isDirectory()) {
      return JSON.stringify({ error: '「' + gate.relPath + '」是文件夹，不是文件。' +
        '一次只能复制一个文件。' });
    }
    // 落库名取路径尾段（工作区侧 sanitize 清洗；目录冲突与容量闸全在落库壳内）
    const rawName: string = gate.relPath.substring(gate.relPath.lastIndexOf('/') + 1);
    const dir: string = argsString(parsed, 'dir').trim();
    const outcome = await mountCopyToWorkspace(fullPath, rawName, st.size,
      ctx.conversationId, ctx.assistantId, mountRelPathNormalize(dir));
    if (!outcome.ok) {
      return JSON.stringify({ error: outcome.errorText });
    }
    return composeMountCopyOutReply(row.name, gate.relPath, outcome.displayName,
      mountRelPathNormalize(dir), formatWorkspaceSize(outcome.sizeBytes),
      workspaceOverwriteNote(outcome.overwriteKind ?? ''));
  }
}

// ── mount_copy_in：工作区文件复制进挂载（决明拍板只做 AI 工具面，用户面入口不做）──
// 方向防混：mount_copy_out = 出挂载、进工作区；mount_copy_in = 出工作区、进挂载（本件）。
// 写挂载侧行为与 mount_write 同族：闸序 = 公共闸 → 模式闸 → 源校验 → fd 分块拷贝；确认链
// 两档（目标探测驱动——不存在走写操作档、已存在 = 覆盖销毁原内容不可逆档恒问）。

// 源定位产物（errorText '' = 通过；非空即拒不抛）
interface MountCopySourceOutcome {
  errorText: string;
  name: string;
  absPath: string;
  size: number;
}

// 源定位（copy_in 源校验单源：执行器与确认预检同走本函数，两处判据禁二写）：拆路径 → 工作
// 区侧两闸（workspaceNameRejectReason / workspaceDirRejectReason 直引禁新写）→ 按（dir,
// name）查行（多命中 = 数据异常；零命中先判同段名子文件夹 = 目录指引，再给列工作区指引）→
// 目录行命中同样拒（暂不支持复制文件夹）→ 物理路径拼装（filesDir + localPath）→ stat。
// 全包 try/catch：异常一律转中文回执串（P0-1 不给半截假绿），恒不抛——确认预检按边界判 null
async function locateMountCopySource(workspacePath: string): Promise<MountCopySourceOutcome> {
  const miss = (text: string): MountCopySourceOutcome =>
    ({ errorText: text, name: '', absPath: '', size: 0 });
  const cut: number = workspacePath.lastIndexOf('/');
  const dir: string = cut >= 0 ? workspacePath.substring(0, cut) : '';
  const name: string = cut >= 0 ? workspacePath.substring(cut + 1) : workspacePath;
  const nameReject: string = workspaceNameRejectReason(name);
  if (nameReject !== '') {
    return miss(nameReject);
  }
  const dirReject: string = workspaceDirRejectReason(dir);
  if (dirReject !== '') {
    return miss(dirReject);
  }
  const isDirText: string = '「' + workspacePath + '」是文件夹，暂不支持复制文件夹。' +
    '一次只能复制一个文件。';
  try {
    const matches: WorkspaceFileRow[] = await queryWorkspaceFilesByName(dir, name);
    if (matches.length > 1) {
      return miss('工作区里存在多个名为「' + name + '」的文件（数据异常），' +
        '无法确定要复制哪一个。');
    }
    if (matches.length === 0) {
      const rows: WorkspaceFileRow[] = await queryWorkspaceFiles(WORKSPACE_ROWS_READ_MAX);
      const dirs = deriveWorkspaceDirListing(rows, dir).dirs;
      for (const d of dirs) {
        if (d.name === name) {
          return miss(isDirText);
        }
      }
      return miss('文件工作区里没有「' + workspacePath + '」。' +
        '请先用 workspace_list 查看工作区里的文件。');
    }
    if (isWorkspaceDirRow(matches[0])) {
      return miss(isDirText);
    }
    const filesDir: string = workspaceFilesDir();
    if (filesDir === '') {
      return miss('工作区目录未就绪，无法读取文件。');
    }
    const absPath: string = filesDir + '/' + matches[0].localPath;
    const st: fs.Stat = fs.statSync(absPath);
    if (st.isDirectory()) {
      return miss(isDirText);
    }
    if (st.size > MOUNT_COPY_TO_MOUNT_MAX_BYTES) {
      return miss('文件超过 ' + (MOUNT_COPY_TO_MOUNT_MAX_BYTES / (1024 * 1024)) +
        'MB 的复制上限，无法复制到挂载。');
    }
    return { errorText: '', name: name, absPath: absPath, size: st.size };
  } catch (e) {
    return miss('工作区文件读取失败：' + toolErrorText(e));
  }
}

// 拷贝分块（字节）：分块读写较整文件单次读内存占用低，且短写可精确计数——部分复制回执的
// 「实写字节」即由此累计
const MOUNT_COPY_CHUNK_BYTES: number = 1024 * 1024;

// copy_in 预检便签两值（载荷词表本域自定义，信道 = 执行上下文 preflightMemo——写点
// mountCopyInNeedsConfirm 探测后、读点 MountCopyInExecutor 失败关闭臂）：exists = 预检时
// 目标已在（覆盖已按不可逆档确认，执行器放行）；absent = 预检时目标不在（执行器开写前复探，
// 已出现即失败关闭）
const MOUNT_COPY_MEMO_EXISTS: string = 'exists';
const MOUNT_COPY_MEMO_ABSENT: string = 'absent';

// 确认预检（copy_in 写确认类——契约：全包 try/catch 恒不抛）。fail-closed 边界 = 源已定位且
// 挂载为读写之后：目标存在性探测驱动分档——不存在 = 写操作档经 routeConfirmPrompt 归一数据
// 管理档三档（「一律放行」豁免本档）；已存在 = 不可逆档恒问（覆盖销毁原内容，与整写覆盖同
// 立意）。★ 预检异常返保守人工卡且按**不可逆档**加严（与 M2 mount_write 保守卡「write 档」
// 有意分叉：本路探测驱动、catch 时目标状态未知，加严恰好堵住「本会话内允许」漏过存在性
// 未知的覆盖面）
export async function mountCopyInNeedsConfirm(argsJson: string,
  ctx: ToolExecutionContext): Promise<ConfirmPrompt | null> {
  let mountId = 0;
  let workspacePath = '';
  let dir = '';
  let name = '';
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    mountId = argsMountId(parsed, 'mountId');
    workspacePath = argsString(parsed, 'workspacePath').trim();
    dir = argsString(parsed, 'dir').trim();
    name = argsString(parsed, 'name').trim();
  } catch (e) {
    return null; // 坏形态：执行器必有参数错误回执
  }
  if (!(mountId > 0) || workspacePath === '') {
    return null; // 执行器必拒
  }
  const srcTail: string = workspacePath.substring(workspacePath.lastIndexOf('/') + 1);
  const targetName: string = name === '' ? srcTail : name;
  const rawTarget: string = dir === '' ? targetName : dir + '/' + targetName;
  if (mountRelPathRejectReason(rawTarget) !== '') {
    return null; // 执行器路径闸必拒（无需弹卡问人一个必拒动作）
  }
  try {
    const src: MountCopySourceOutcome = await locateMountCopySource(workspacePath);
    if (src.errorText !== '') {
      return null; // 源形态执行器必拒（不存在 / 是文件夹 / 超限 / 坏路径）
    }
    const rows: FolderMountRow[] = await queryFolderMounts();
    let row: FolderMountRow | undefined = undefined;
    for (const candidate of rows) {
      if (candidate.id === mountId) {
        row = candidate;
        break;
      }
    }
    if (row === undefined) {
      return null; // 执行器查行闸拒
    }
    if (row.mode !== MOUNT_MODE_READ_WRITE) {
      return null; // 只读挂载：执行器模式闸拒
    }
    // 目标探测前置 = 激活（与执行器同闸同缓存——持久授权按进程激活，未激活探测必失准）；
    // 激活失败 = 执行器必报授权文案，不弹卡
    try {
      await ensureMountActivated(row);
    } catch (e) {
      return null;
    }
    const relPath: string = mountRelPathNormalize(rawTarget);
    const targetPath: string = joinMountPath(mountRootPathFromUri(row.dirUri), relPath);
    const exists: boolean = fs.accessSync(targetPath);
    // TOCTOU 便签写点——探测结论随本调用执行上下文交执行器比对（信道与写入纪律见
    // MessageContracts.preflightMemo 注释；执行器侧失败关闭臂见 MountCopyInExecutor）。
    // 只写结论不写身份：信道按调用隔离（预检与执行同一上下文对象），载荷无需身份段
    ctx.preflightMemo = exists ? MOUNT_COPY_MEMO_EXISTS : MOUNT_COPY_MEMO_ABSENT;
    const sizeText: string = formatWorkspaceSize(src.size);
    const prompt: ConfirmPrompt = {
      text: exists ?
        '助手要用文件工作区的「' + src.name + '」（' + sizeText + '）覆盖挂载「' + row.name +
          '」里的「' + relPath + '」，原文件内容将被替换。' :
        '助手要把文件工作区的「' + src.name + '」（' + sizeText + '）复制到挂载「' + row.name +
          '」的「' + relPath + '」。',
      level: exists ? CONFIRM_LEVEL_IRREVERSIBLE : CONFIRM_LEVEL_WRITE,
      detail: '复制产生的是一份副本，工作区里的原文件不受影响 · 目标是用户授权的原文件夹，' +
        '复制会直接写入'
    };
    // 三档归一单点（数据管理档：ask 直指人工 / auto 只豁免写操作档 / 其余交审批闸）
    return routeConfirmPrompt(prompt, dataApproveMode());
  } catch (e) {
    // fail-closed：源已定位后的异常 = 目标是否存在未知 ⇒ 按不可逆档保守人工卡（见函数头注）
    return {
      text: '复制前的确认检查出现异常，本次复制需要你确认。',
      level: CONFIRM_LEVEL_IRREVERSIBLE,
      route: CONFIRM_ROUTE_HUMAN
    };
  }
}

export class MountCopyInExecutor implements ToolExecutor {
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const mountId: number = argsMountId(parsed, 'mountId');
    if (!(mountId > 0)) {
      return JSON.stringify({ error: '缺少挂载编号。请先调用 mount_list 查看挂载清单，' +
        '再带 mountId 与 workspacePath 重试。' });
    }
    const workspacePath: string = argsString(parsed, 'workspacePath').trim();
    if (workspacePath === '') {
      return JSON.stringify({ error: '请给出要复制的工作区文件路径。' +
        '可以先用 workspace_list 查看工作区里的文件。' });
    }
    // 目标相对路径（name 缺省 = 源文件名；仅字符串派生，正式源校验在闸序第③步）
    const name: string = argsString(parsed, 'name').trim();
    const dir: string = argsString(parsed, 'dir').trim();
    const srcTail: string = workspacePath.substring(workspacePath.lastIndexOf('/') + 1);
    const targetName: string = name === '' ? srcTail : name;
    const rawTarget: string = dir === '' ? targetName : dir + '/' + targetName;
    // 闸序①公共闸（路径闸同时拦 dir 与 name 的 .. / \ / NUL / 超长）
    const gate: MountGateOutcome = await mountGate(mountId, rawTarget);
    if (gate.rejectText !== '') {
      return JSON.stringify({ error: gate.rejectText });
    }
    const row: FolderMountRow = gate.row as FolderMountRow; // 闸通过后 row 必在场
    // 闸序②模式闸（只读挂载拒写——mount_write 同句族）
    if (row.mode !== MOUNT_MODE_READ_WRITE) {
      return JSON.stringify({ error: '「' + row.name + '」是' + mountModeLabel(row.mode) +
        '挂载，不能写入。请让用户在 设置 → 文件夹挂载 中把它切换为读写模式。' });
    }
    if (gate.relPath === '') {
      return JSON.stringify({ error: '请给出要复制到的文件名，不能复制到挂载根目录本身。' });
    }
    // 闸序③源校验（单源 = locateMountCopySource，与确认预检同函数）
    const src: MountCopySourceOutcome = await locateMountCopySource(workspacePath);
    if (src.errorText !== '') {
      return JSON.stringify({ error: src.errorText });
    }
    const destAbs: string = joinMountPath(gate.rootPath, gate.relPath);
    // ★ TOCTOU 失败关闭臂——预检便签记「目标不在」时，开写前复探目标；已出现（确认窗口内
    // 被外部应用创建）＝ 覆盖未经「不可逆档」确认 ⇒ 失败关闭不落一字节（宁拒不错；回执指引
    // 重试 = 重走确认链按覆盖恒问）。便签非 absent 两态照旧放行：'exists' = 覆盖已按不可逆档
    // 确认；''（预检异常走保守人工卡、获批后无便签）＝ 人工已确认「存在性未知」的操作。
    // 残留窗口 = 本复探到 openSync 之间的微秒级（平台 OpenMode 无 EXCL 原子位，严格闭合
    // 不可达——登记于变更记录）；本臂内零写调用
    if (ctx.preflightMemo === MOUNT_COPY_MEMO_ABSENT) {
      let targetNowExists: boolean = false;
      try {
        targetNowExists = fs.accessSync(destAbs);
      } catch (e) {
        targetNowExists = true; // 复探失败 = 目标状态不可确认 → 按已出现走失败关闭（宁拒不错）
      }
      if (targetNowExists) {
        return JSON.stringify({ error: '目标文件在确认之后才出现，可能由其他应用创建。' +
          '为避免覆盖未经确认的内容，本次复制已取消。请重新发起复制，确认流程会按覆盖处理。' });
      }
    }
    // fd 分块拷贝（相位诚实 = mount_write 同款：目标打开即 TRUNC 生效——此前失败 = 目标未动，
    // 此后失败 / 短写 = 目标可能不完整，如实报实写字节且不回滚；成对释放 finally 双 close）
    let writtenBytes: number = 0;
    let srcFile: fs.File | null = null;
    let destFile: fs.File | null = null;
    try {
      srcFile = fs.openSync(src.absPath, fs.OpenMode.READ_ONLY);
      destFile = fs.openSync(destAbs,
        fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      // ★ offset 语义坑（自检轮修复）：运行时实现里 ReadOptions / WriteOptions 的 offset
      // **直通 uv_fs_read / uv_fs_write**（缺省 -1 = 当前位并推进；显式值 = 绝对定位读写且
      // **不推进指针**）——原写法读侧恒传 offset: 0 ⇒ 每轮重读文件头、readLen 恒 > 0 ＝
      // **死循环**，目标文件每轮一块**无界膨胀**至写失败为止。本地 d.ts 另写「current
      // filePointer plus offset」相对口径（⇒ 同一写法会静默产零填充坏件）——两口径下显式
      // offset 都不可依赖，故两侧一律不传、位推进由缺省 -1 指针自持
      const buf: ArrayBuffer = new ArrayBuffer(MOUNT_COPY_CHUNK_BYTES);
      let readLen: number = fs.readSync(srcFile.fd, buf, { length: MOUNT_COPY_CHUNK_BYTES });
      while (readLen > 0) {
        const chunk: ArrayBuffer = readLen === buf.byteLength ? buf : buf.slice(0, readLen);
        const wrote: number = fs.writeSync(destFile.fd, chunk, { length: readLen });
        writtenBytes += wrote;
        if (wrote < readLen) {
          break; // 短写 = 部分完成（目标空间不足等），跳出走如实回执
        }
        readLen = fs.readSync(srcFile.fd, buf, { length: MOUNT_COPY_CHUNK_BYTES });
      }
    } catch (e) {
      if (destFile !== null) {
        return JSON.stringify({ error: '复制中断：' + toolErrorText(e) + '。' +
          composeMountCopyInPartialReply(writtenBytes, src.size) });
      }
      if (srcFile !== null) {
        // 源已开、目标未开 = 目标打开失败（未找到 = 父目录不存在，CREATE 只建文件不建目录——
        // 逐级确认指引；P0-1 不做 mkdir，M2 同克制）
        return JSON.stringify({ error: mountFsFailText(e, '挂载「' + row.name + '」里没有「' +
          gate.relPath + '」的位置。父目录不存在时无法创建文件，' +
          '请先用 mount_list 逐级确认完整路径。') });
      }
      return JSON.stringify({ error: '工作区文件读取失败：' + toolErrorText(e) +
        '。请先用 workspace_list 确认工作区里的文件。' });
    } finally {
      if (srcFile !== null) {
        fs.closeSync(srcFile); // 成对释放：open 同段 close，异常路径同样走到
      }
      if (destFile !== null) {
        fs.closeSync(destFile);
      }
    }
    if (writtenBytes < src.size) {
      return JSON.stringify({ error: composeMountCopyInPartialReply(writtenBytes, src.size) });
    }
    return composeMountCopyInReply(row.name, gate.relPath, src.name, writtenBytes);
  }
}

// ═══ 工具注册面（自 ToolTypes.ets 整族外迁——本件自注册）═══
// 组标题常量 TOOL_GROUP_MOUNT 随注册面同居本件（聚合根引回入 TOOL_GROUP_ORDER 组序数组；
// 「组标签 + 注册块」同落自注册域件 = 域件不能反向引聚合根，组标签留聚合根则自注册无解）。
// 注册序位置由聚合根调用点保持（toolGroups 分组视图与 toolRegistry.all() 序恒等——六件全
// defaultEnabled=false，默认集合解析零漂移）。
// ★ 形态约束：本段（组标题常量 + 注册函数）须保持为**文件末位构件**——断言夹具
//（sse-assert ㉔ 组 / set-pref-tool-check 工具页组）自「export const TOOL_GROUP_MOUNT」行
// 切片直拼求值副本（切片意义 = 真实注册内容装进夹具同一注册表实例，非第二份注册源）；
// 本行之后追加任何顶层构件前先同步两脚本切片锚，否则夹具副本求值 ReferenceError 即红。
export const TOOL_GROUP_MOUNT: string = '文件夹挂载';

// 挂载六件注册块：
export function registerMountTools(): void {
  // 文件夹挂载只读两件——mount_list 列出挂载目录内容（不传 mountId 回挂载清单，模型首调
  // 即发现面）/ mount_read 读取挂载内文件。常规工具：defaultEnabled=false 不进任何默认集合
  //（用户显式开）；零政策字段；零 preflight（只读无写面）。
  toolRegistry.register({
    name: TOOL_MOUNT_LIST,
    group: TOOL_GROUP_MOUNT,
    title: '列出挂载文件',
    desc: MOUNT_LIST_DESC,
    parametersJson: MOUNT_LIST_SCHEMA,
    defaultEnabled: false,
    executor: new MountListExecutor()
  });
  toolRegistry.register({
    name: TOOL_MOUNT_READ,
    group: TOOL_GROUP_MOUNT,
    title: '读取挂载文件',
    desc: MOUNT_READ_DESC,
    parametersJson: MOUNT_READ_SCHEMA,
    defaultEnabled: false,
    executor: new MountReadExecutor()
  });
  // 写入与两向复制三件。mount_write 与 mount_copy_in = 本域写面——均带 preflight
  //（mountWriteNeedsConfirm：新建/追加 = 写操作档归一三档、整写覆盖 = 不可逆档恒问；
  // mountCopyInNeedsConfirm：目标探测驱动——不存在走写操作档、已存在 = 不可逆档恒问）；
  // mount_copy_out = 拷出源只读、写沙箱、可逆——零 preflight。件同组同姿态：defaultEnabled=
  // false 用户显式开、零政策字段。
  toolRegistry.register({
    name: TOOL_MOUNT_WRITE,
    group: TOOL_GROUP_MOUNT,
    title: '写入挂载文件',
    desc: MOUNT_WRITE_DESC,
    parametersJson: MOUNT_WRITE_SCHEMA,
    defaultEnabled: false,
    executor: new MountWriteExecutor(),
    preflight: mountWriteNeedsConfirm
  });
  toolRegistry.register({
    name: TOOL_MOUNT_COPY_OUT,
    group: TOOL_GROUP_MOUNT,
    title: '复制挂载文件到工作区',
    desc: MOUNT_COPY_OUT_DESC,
    parametersJson: MOUNT_COPY_OUT_SCHEMA,
    defaultEnabled: false,
    executor: new MountCopyOutExecutor()
  });
  // mount_copy_in = 工作区文件复制进挂载（方向与上方 copy_out 相反——出工作区、进挂载；
  // 写挂载侧故带确认链，覆盖态不可逆档恒问）
  toolRegistry.register({
    name: TOOL_MOUNT_COPY_IN,
    group: TOOL_GROUP_MOUNT,
    title: '复制工作区文件到挂载',
    desc: MOUNT_COPY_IN_DESC,
    parametersJson: MOUNT_COPY_IN_SCHEMA,
    defaultEnabled: false,
    executor: new MountCopyInExecutor(),
    preflight: mountCopyInNeedsConfirm
  });
  // mount_delete = 把挂载内文件或文件夹删除到系统回收站（决明拍板「AI 删除走既有确认/
  // 审批链；删除走系统回收站」）——带 preflight（mountDeleteNeedsConfirm：恒不可逆档 +
  // 条目身份便签 TOCTOU 复探）。defaultEnabled=false 用户显式开、零政策字段。
  toolRegistry.register({
    name: TOOL_MOUNT_DELETE,
    group: TOOL_GROUP_MOUNT,
    title: '删除挂载文件',
    desc: MOUNT_DELETE_DESC,
    parametersJson: MOUNT_DELETE_SCHEMA,
    defaultEnabled: false,
    executor: new MountDeleteExecutor(),
    preflight: mountDeleteNeedsConfirm
  });
}

