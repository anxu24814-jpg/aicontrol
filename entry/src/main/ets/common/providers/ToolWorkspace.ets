// 文件工作区工具域：workspace_list / read / write / write_xlsx / import 五件 +
// mkdir / rename / move / delete 目录四件 + glob / grep 检索两件（主路 = DB 行集内存匹配零
// 物理枚举，闸与回执全在 WorkspaceSearchUtil 纯函数，本件只管参数闸与 IO 注入）+
// workspace_stage 入向桥（工作区件拷贝进本会话临时区交脚本处理，store 编排在
// WorkspaceDbTmp.stageWorkspaceFileToTmp）的 desc / schema / 执行器与 delete 预检。
// · 常量归口 ToolIds.ets、注册块落 ToolTypes.ets（本文件只产定义件与执行器——「独立工具
//   域先拆，聚合根只注册」全工具域同构）；契约（ToolExecutor / toolArgsParseErrorText /
//   ConfirmPrompt）自叶子 ToolContracts 引（坑50：禁从聚合根 ToolTypes 引——引一次就把环
//   接回来一次）；预检三件套照 ToolKnowledge 先例引（routeConfirmPrompt 自 ConfirmRouting、
//   dataApproveMode 自 AppPreferences）。
// · 依赖方向：本件 → ChatDb 委托口（查/存/目录四操作）+ WorkspaceDb 文件读出口 + 纯函数
//   两件（WorkspaceUtil + WorkspaceSearchUtil，闸/回执组装）——store 层不反向引工具域，单向无环。
// · 安全边界：模型恒按显示名引用、name 恒单段（含 / \ .. \0 或纯空白按名称非法拒绝并中文
//   报错）；dir 是受闸逻辑路径（相对工作区根、/ 分隔，过 workspaceDirRejectReason——..
//   \ \0 空段零容忍）；实际文件路径恒由应用侧派生；无全局开关——声明面 = 执行面（助手清单
//   控制），执行器不另设开关复查（http_request 同款）。
// · 回执口径：成功 = 纯文本（工具卡通用文本渲染），失败 = JSON { error }（全工具统一形态）；
//   回执组装单源 WorkspaceUtil 与 WorkspaceSearchUtil（收口 ≤8192 与截断注明都在纯函数层）。
//   write 覆盖路写前读旧文产回执尾行（摘录对/超阈行数对单行 JSON）——读失败/无行/超阈一律
//   降级无尾行不阻塞写；门槛单源 MOUNT_WRITE_MAX_CHARS 跨域单引（调值有意联动，勿造第二常数）。
// · 确认链：delete 带预检 workspaceDeleteNeedsConfirm——不可逆档任何数据管理档位都恒问人
//  （照 manage_knowledge 删除先例）；mkdir/rename/move 不带 preflight 照 write §8-8 拍板
//  （可逆、用户可在管理页删）。
// · 不进 ToolPref 白名单（本域零模型可写设置）、collectTools 零改动（常规工具经
//   assistants.tools 天然进链，用户显式开）。
import { fileIo as fs } from '@kit.CoreFileKit';
import { ATTACHMENT_MATCH_WINDOW_MAX } from './ToolLimits';
// PDF 原件直传尺寸窗两常量（能力判据叶子 ToolMediaSupport；协议半边判据同件单源——本件
// 禁写第二份协议判断）
import { DOC_NATIVE_MIN_BYTES, DOC_NATIVE_MAX_BYTES } from './ToolMediaSupport';
import { ToolExecutor, toolArgsParseErrorText, toolErrorText, ConfirmPrompt,
  CONFIRM_LEVEL_IRREVERSIBLE, buildReceiptDiffExcerptTail,
  buildReceiptDiffOversizeTail } from './ToolContracts';
import { routeConfirmPrompt } from './ConfirmRouting';
import { dataApproveMode, PREF_WORKSPACE_SORT_KEY } from '../AppPreferences';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { queryAttachmentsByConversation, queryWorkspaceFiles, queryWorkspaceFilesByName,
  queryWorkspaceTotal, saveWorkspaceText, saveWorkspaceXlsx, createWorkspaceDirOp,
  renameWorkspaceEntryOp, moveWorkspaceEntryOp, deleteWorkspaceEntryOp,
  editWorkspaceText } from '../store/ChatDb';
import { AttachmentListRow } from '../store/AttachmentDb';
import { importAttachmentToWorkspace } from './HttpBinary';
import { buildXlsxToTemp } from '../WorkspaceXlsx';
import { readWorkspaceFileText, readWorkspaceFileBase64,
  physicalWorkspaceDirExists, workspaceFilesDir, workspaceCacheDir } from '../store/WorkspaceDb';
// 入向桥 store IO 面（工作区件 → 会话临时区，拷贝语义）
import { stageWorkspaceFileToTmp } from '../store/WorkspaceDbTmp';
import { docParser, docHardLimitBytes, pdfTextThin, DocumentParseResult } from '../DocumentParse';
import { encodeImageBase64 } from '../AttachmentUtil';
import { ocrEnabled, runOcr, OcrImageSource, OcrOutcome } from '../OcrEngine';
import { PendingAttachment, AiImagePart } from './AiTypes';
import { WorkspaceFileRow, briefFromRow,
  deriveWorkspaceDirListing, formatWorkspaceSize, isWorkspaceDirRow, joinDirName,
  normalizeWorkspaceDirParam, relativeWorkspacePath, workspaceDirRejectReason,
  resolveWorkspaceSortMode, sanitizeWorkspaceName,
  workspaceKindLabel, workspaceNameRejectReason,
  WORKSPACE_ROWS_READ_MAX, WORKSPACE_SOURCE_ASSISTANT } from '../WorkspaceUtil';
// 覆盖写旧文读门槛同源单引（勿造第二常数——该写上限调值时本件读门槛有意联动）
import { MOUNT_WRITE_MAX_CHARS } from '../MountUtil';
import { composeWorkspaceListReply, composeWorkspaceReadReply, composeWorkspaceWriteReply,
  composeWorkspaceDirCreatedReply, composeWorkspaceRenameReply,
  composeWorkspaceMoveReply, composeWorkspaceDeleteReply, workspaceDocMetaLine,
  workspaceParseErrorReply, composeWorkspaceImageReply, composeWorkspaceOcrFreshReply,
  composeWorkspaceDocNativeReply, workspaceOverwriteNote } from '../WorkspaceReply';
import { composeWorkspaceGlobReply, composeWorkspaceGrepReply,
  matchWorkspaceGlob, buildWorkspaceGrepRegex, normalizeWorkspaceGrepLimit,
  scanWorkspaceGrep } from '../WorkspaceSearchUtil';
// 预识别优先——指纹/来源标注纯函数（WorkspaceDbOcr 单源直引）
import { queryWorkspaceOcr } from '../store/ChatDb';
import { ocrStateOf, workspaceOcrSourceLabel } from '../store/WorkspaceDbOcr';
// 编辑域纯函数（匹配器在 WorkspaceEditUtil——成功回执/E9/E10 文案单源）+ 先读后编硬门读态表
//（WorkspaceReadState 零 import 叶子）+ 定位文案单源（WorkspaceDbEdit 的 E3/E4/E5/E6 构造器，
// 链内外两侧共用）
import { composeWorkspaceEditReply, workspaceEditLineCount } from '../WorkspaceEditUtil';
import { checkWorkspaceRead, markWorkspaceRead } from '../WorkspaceReadState';
import { editNoHitText, editMultiHitText, editIsDirText,
  editKindNotEditableText } from '../store/WorkspaceDbEdit';

// ── desc（请求侧 description，中文三段式——调用时机 / 用法 / 划界；定位类 dir 缺省句统一
//    「缺省为该助手的默认文件夹，/ 表示根目录」，检索两件缺省恒整个工作区不在改面）──
export const WORKSPACE_LIST_DESC: string =
  '列出文件工作区一个目录里的内容。dir 是目录路径，多级用 / 分隔，缺省为该助手的默认文件夹，/ 表示根目录。列表显示的是该目录下的内容，要看整个工作区的顶层用 / 。返回该目录下的子文件夹与文件，子文件夹在前，文件带名称、大小、时间和来源。要查看某个子文件夹里的内容时，把它的名字填入 dir 再调用。用户问工作区里有什么文件、提到之前保存或上传过的文件时，先用本工具确认，不要凭记忆回答。';

export const WORKSPACE_READ_DESC: string =
  '读取文件工作区里某个文件的内容。name 必须取自 workspace_list 返回的文件名，dir 是它所在的目录，缺省为该助手的默认文件夹，/ 表示根目录。文本文件按原文返回，每一行前面带行号，与 workspace_grep 结果里的行号一致。文件较长时用 offset 与 limit 分段读取，offset 是起始行号，从 1 起，limit 是本次最多读取的行数，返回会注明总行数与继续读取的位置。单条回执有长度上限，内容超过上限时会截断，并给出继续读取的指引。某一行在行内被截断时，指引会包含 offset 与 col。col 是该行内的起始字符位置，从 1 起，可随时主动指定，继续读取被截断的行时按指引传入 col。pdf、docx、xlsx、xls、ofd、pptx 文档会解析出其中的文字内容返回，解析结果不含图片与排版，pdf 的文字按页分段，每页的文字在一行里。扫描件 pdf 的文字较少，支持图片的模型会收到逐页页面图片，页面图片随本轮请求一起发送。支持直接阅读原件的模型会收到 pdf 原件，能读取其中的图片与排版。图片文件可以读取。支持图片输入的模型会直接收到图片。图片会作为读取结果的一部分随本轮请求发送。不支持的模型会使用识别出的文字，优先使用用户在应用里提前识别并校对过的文字，没有时才当场识别，无法识别时返回说明。其他二进制文件不能读取内容，只使用它们的名称与大小信息。';

export const WORKSPACE_WRITE_DESC: string =
  '把一个文本文件保存到文件工作区，保存后用户在应用的设置里可以查看与删除。name 是文件名，例如 报告.md。content 是文件内容。dir 是目标目录路径，缺省保存到该助手的默认文件夹，/ 表示根目录，目录不存在会自动创建。同名文件会被覆盖。目标位置已有同名文件夹时会保存失败并说明原因。文件超过大小上限或工作区已满时会保存失败并说明原因。二进制内容与图片不支持用本工具写入。需要生成 Excel 表格文件时用 workspace_write_xlsx 工具。';

// rows 为 JSON 二维数组原串（string 型全 provider 兼容——嵌套数组各端解析差异大）
export const WORKSPACE_WRITE_XLSX_DESC: string =
  '把表格数据生成为 Excel 文件保存到文件工作区。rows 是 JSON 二维数组原串，第一行为表头，例如 [[\"品名\",\"数量\"],[\"苹果\",3]]。dir 是目标目录路径，缺省保存到该助手的默认文件夹，/ 表示根目录，目录不存在会自动创建。单元格支持文字与数字，其他类型的值会转成文字，单个单元格文字过长会截断保存。生成后用户在应用的设置里可以查看与分享。文件超过大小上限或工作区已满时会保存失败并说明原因。';

export const WORKSPACE_IMPORT_DESC: string =
  '把当前会话中用户发送过的附件存入文件工作区。用户要求把某个附件保存到工作区时用。附件名取对话中的「[附件]」标注。dir 是目标目录路径，缺省保存到该助手的默认文件夹，/ 表示根目录，目录不存在会自动创建。同名的工作区文件会被覆盖，保存后用户在应用的设置里可以查看与删除。';

// ── 目录四工具 desc（调用时机 / 用法 / 划界）──
export const WORKSPACE_MKDIR_DESC: string =
  '在文件工作区里创建文件夹。dir 是要创建的目录路径，多级用 / 分隔，缺省为该助手的默认文件夹，/ 表示根目录，例如 资料/2026。目录已存在时不报错。同位置已有同名文件时创建失败并说明原因。保存文件时不必先建目录，workspace_write 会按 dir 自动创建缺失的目录，本工具用于提前整理出空的文件夹。';

export const WORKSPACE_RENAME_DESC: string =
  '重命名文件工作区里的一个文件或文件夹。name 是当前名称，dir 是它所在的目录，缺省为该助手的默认文件夹，/ 表示根目录。new_name 是新名称，只改名字不换目录。改名前先用 workspace_list 确认。同目录内已有同名文件或文件夹时改名失败并说明原因。';

export const WORKSPACE_MOVE_DESC: string =
  '把文件工作区里的一个文件或文件夹移动到另一个文件夹。name 是要移动的文件或文件夹名，dir 是它当前所在的目录，缺省为该助手的默认文件夹，/ 表示根目录。to_dir 是目标目录，缺省为该助手的默认文件夹，/ 表示根目录，目标目录必须已经存在。移动文件夹时它里面的所有文件会一起移动。';

export const WORKSPACE_DELETE_DESC: string =
  '删除文件工作区里的一个文件或整个文件夹。name 是要删除的文件或文件夹名，dir 是它所在的目录，缺省为该助手的默认文件夹，/ 表示根目录。删除文件夹会连同里面所有文件一起删除，删除后无法恢复。每次删除都会先征求用户同意，用户同意后才会执行。';

// ── 检索两工具 desc（防模型误读为缺陷的三处说明——glob 无 / 任意深度等效、不支持 [] 与 !、
//    grep 扫描计数只统计文本文件——均已写入 desc 正文）──
export const WORKSPACE_GLOB_DESC: string =
  '按名称模式查找文件工作区里的文件与文件夹。pattern 是通配模式，例如 **/*.md 匹配所有目录下的 md 文件。* 匹配一段内的字符，不跨 /，** 可跨目录，? 匹配单个字符，{a,b} 表示任选其一。模式不含 / 时按文件名匹配任意深度的文件，此时 * 与 ** 效果相同，只查某一层时用 dir 限定。模式不支持 [ ] 字符集与 ! 排除，方括号会按普通字符处理。dir 是查找的起始目录，缺省为根目录，pattern 相对该目录匹配。返回的路径是相对工作区根的完整路径，文件夹以 / 结尾。结果过多时只返回一部分并注明，可用更具体的 pattern 或 dir 收窄。';

export const WORKSPACE_GREP_DESC: string =
  '在文件工作区的文本文件内容里搜索正则表达式。pattern 是正则表达式，书写无效时按普通文本查找。dir 是限定搜索的目录路径，缺省为根目录。ignore_case 为 true 时不区分大小写。limit 是最多返回的匹配数，不传则用缺省上限，达到上限后停止扫描。每条结果格式为 路径:行号: 内容。搜索范围只含文本类文件，例如 md、txt、csv、json 与代码文件，pdf、docx、xlsx 等文档与图片、二进制文件不参与搜索，回执里的扫描计数也只统计文本文件。结果过多时只返回前面一部分并注明，可用更具体的 pattern 或 dir 收窄。';

// ── 编辑工具 desc（任务书定稿全文逐字——勿改写）──
export const WORKSPACE_EDIT_DESC: string =
  '对文件工作区里的文本文件做替换编辑。name 是要编辑的文件名，取自 workspace_list 的结果，dir 是它所在的目录，缺省为该助手的默认文件夹，/ 表示根目录。编辑前先用 workspace_read 读取该文件，old_string 从读取结果里原样复制，只取行内容，去掉每行开头的行号与制表符。old_string 需要在文件里唯一出现。出现多处时编辑失败，请多带一些前后文让它唯一，或把 replace_all 设为 true 替换全部。找不到时会按空白宽容方式再找一次。new_string 是替换后的内容。编辑直接写回原文件，不支持撤销。文档、图片与其他二进制文件不能编辑。要整体重写内容用 workspace_write，要生成 Excel 用 workspace_write_xlsx。';

// ── schema（JSON Schema 原串——ArkTS 禁无类型对象字面量，全工具同款姿势；dir 描述句两版
//    分治：定位版 = 缺省落助手默认文件夹、/ 表根；检索版 = 缺省整个工作区——语义见
//    normalizeWorkspaceDirParam，禁回填单一同文）──
const DIR_PROP: string = '"dir":{"type":"string","description":"目录路径，多级用 / 分隔。' +
  '缺省为该助手的默认文件夹，/ 表示根目录。取自 workspace_list 返回的子文件夹。"}';
const DIR_PROP_SEARCH: string = '"dir":{"type":"string","description":"搜索的目录范围，' +
  '多级用 / 分隔，缺省为整个工作区。"}';

export const WORKSPACE_LIST_SCHEMA: string =
  '{"type":"object","properties":{' + DIR_PROP + '}}';
// read 分段读：offset/limit = 行级（1-based 行号 / 行数），col = 1-based 行内字符位（可随时
// 主动指定，续读被截断的超长行按回执指引传入）；desc 不写死数值防与常量漂移（P2-5）
export const WORKSPACE_READ_SCHEMA: string = '{"type":"object","properties":{' +
  '"name":{"type":"string","description":"要读取的工作区文件名，取自 workspace_list 的结果。"},' +
  '"offset":{"type":"number","description":"起始行号，从 1 起，不传则从第 1 行读。"},' +
  '"limit":{"type":"number","description":"本次最多读取的行数，不传则读到长度上限。"},' +
  '"col":{"type":"number","description":"行内起始字符位置，从 1 起，不传则从行首读。可随时主动指定，从该位置起读。继续读取被截断的超长行时，按返回的指引传入。"},' +
  DIR_PROP + '},' +
  '"required":["name"]}';
export const WORKSPACE_WRITE_SCHEMA: string = '{"type":"object","properties":{' +
  '"name":{"type":"string","description":"文件名，例如 报告.md。"},' +
  '"content":{"type":"string","description":"文件内容，纯文本。"},' +
  DIR_PROP + '},' +
  '"required":["name","content"]}';
export const WORKSPACE_IMPORT_SCHEMA: string = '{"type":"object","properties":{' +
  '"name":{"type":"string","description":"要存入工作区的附件文件名，取当前会话中用户发送过的附件名。"},' +
  DIR_PROP + '},' +
  '"required":["name"]}';

export const WORKSPACE_WRITE_XLSX_SCHEMA: string = '{"type":"object","properties":{' +
  '"name":{"type":"string","description":"文件名，以 .xlsx 结尾。"},' +
  '"rows":{"type":"string","description":"表格数据的 JSON 二维数组原串，第一行为表头，' +
  '例如 [[\\"品名\\",\\"数量\\"],[\\"苹果\\",3]]。"},' +
  '"sheet":{"type":"string","description":"工作表名称，可省略。"},' +
  DIR_PROP + '},' +
  '"required":["name","rows"]}';

export const WORKSPACE_MKDIR_SCHEMA: string =
  '{"type":"object","properties":{' + DIR_PROP + '}}';
export const WORKSPACE_RENAME_SCHEMA: string = '{"type":"object","properties":{' +
  DIR_PROP + ',' +
  '"name":{"type":"string","description":"要重命名的文件或文件夹名，取自 workspace_list。"},' +
  '"new_name":{"type":"string","description":"新名称，单段文件名，不含 /。"}},' +
  '"required":["name","new_name"]}';
export const WORKSPACE_MOVE_SCHEMA: string = '{"type":"object","properties":{' +
  DIR_PROP + ',' +
  '"name":{"type":"string","description":"要移动的文件或文件夹名，取自 workspace_list。"},' +
  '"to_dir":{"type":"string","description":"目标目录路径，多级用 / 分隔，缺省为该助手的默认文件夹，/ 表示根目录。目标目录必须已存在。"}},' +
  '"required":["name"]}';
export const WORKSPACE_DELETE_SCHEMA: string = '{"type":"object","properties":{' +
  DIR_PROP + ',' +
  '"name":{"type":"string","description":"要删除的文件或文件夹名，取自 workspace_list。"}},' +
  '"required":["name"]}';

// ── 检索两工具 schema（dir 描述句挂检索版 DIR_PROP_SEARCH——检索缺省 = 整个工作区，
//    不参与缺省切换）──
export const WORKSPACE_GLOB_SCHEMA: string = '{"type":"object","properties":{' +
  '"pattern":{"type":"string","description":"通配模式。* 匹配一段内的任意字符，不跨 /。** 可跨目录。? 匹配单个字符。{a,b} 表示任选其一。不含 / 时按文件名匹配任意深度的文件。不支持 [ ] 与 !。"},' +
  DIR_PROP_SEARCH + '},' +
  '"required":["pattern"]}';

export const WORKSPACE_GREP_SCHEMA: string = '{"type":"object","properties":{' +
  '"pattern":{"type":"string","description":"要搜索的正则表达式，书写无效时按普通文本查找。"},' +
  '"ignore_case":{"type":"boolean","description":"为 true 时不区分大小写，缺省区分大小写。"},' +
  '"limit":{"type":"number","description":"最多返回的匹配数，不传则用缺省上限。"},' +
  DIR_PROP_SEARCH + '},' +
  '"required":["pattern"]}';

// ── 编辑工具 schema（定稿 JSON 原串——DIR_PROP 单源复用）──
export const WORKSPACE_EDIT_SCHEMA: string = '{"type":"object","properties":{' +
  '"name":{"type":"string","description":"要编辑的工作区文件名，取自 workspace_list 的结果。"},' +
  '"old_string":{"type":"string","description":"要替换的原文，从 workspace_read 的结果里原样复制，不含行号与制表符前缀。"},' +
  '"new_string":{"type":"string","description":"替换后的新内容。"},' +
  '"replace_all":{"type":"boolean","description":"为 true 时替换文件里全部相同的原文，缺省只替换唯一的一处。"},' +
  DIR_PROP + '},' +
  '"required":["name","old_string","new_string"]}';

// ── 入向桥工具 desc/schema（desc 的五个指路锚〔name / dir / workspace_list / fs.readBytes
//    / fs.save〕不得缺项——断言关系钉守）──
export const WORKSPACE_STAGE_DESC: string =
  '把文件工作区里的一个文件复制到本会话的临时区，交给脚本处理。要用脚本计算或转换工作区里的文件时用，例如读取 Excel 表格里的数据、查看图片或压缩包的字节。name 是文件名，取自 workspace_list 的结果，dir 是它所在的目录，缺省为该助手的默认文件夹，/ 表示根目录。放入的是副本，工作区里的原文件不受影响。临时区里已有同名文件时，本次放入的文件会自动换成带序号的名字，回执会给出最终文件名。放入后用脚本里的 fs.readBytes 读它的字节，文本文件也可以用 fs.read。临时区里的文件随会话删除一起清除，也可以在文件工作区管理页的临时分段里查看与清理。本工具只复制文件，不能复制文件夹。要把脚本生成的文件长期保留到工作区，用脚本里的 fs.save。';

export const WORKSPACE_STAGE_SCHEMA: string = '{"type":"object","properties":{' +
  '"name":{"type":"string","description":"要放入临时区的工作区文件名，取自 workspace_list 的结果。"},' +
  DIR_PROP + '},' +
  '"required":["name"]}';

// args 解析取串（工具域共用形态：JSON.parse 后按键取 string；解析失败回执由调用处给）
function argsString(parsed: Record<string, Object>, key: string): string {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'string' ? raw : '';
}

// args 解析取数（read 分段读 offset/limit 与行内续读 col 用；schema 声明 number 类型，模型
// 传非数 → NaN，归一兜底在 composeWorkspaceReadReply——非有限数落缺省）
function argsNumber(parsed: Record<string, Object>, key: string): number {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'number' ? raw : Number.NaN;
}

// args 解析取布尔（grep ignore_case 用；缺省 false）
function argsBoolean(parsed: Record<string, Object>, key: string): boolean {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'boolean' ? raw : false;
}

// 文件 stat 指纹现读（★ 2026-10-04 识别文字笔：读路 fresh 判定用——单文件一次 statSync，
// 轻量；mtime 秒 ×1000 转 ms 与识别链入库口径同源）。读失败 = 指纹必不命中，两值落 -1
//（不与任何真实 mtime/size 相等）→ 状态落 none/stale 走兜底识别路
interface WorkspaceStatFingerprint {
  mtimeMs: number;
  size: number;
}

function readWorkspaceStatFingerprint(absPath: string): WorkspaceStatFingerprint {
  try {
    const st: fs.Stat = fs.statSync(absPath);
    return { mtimeMs: st.mtime * 1000, size: st.size };
  } catch (e) {
    return { mtimeMs: -1, size: -1 };
  }
}

// ── 定位失败三句单源（read 与 stage 两执行器共用同一 (dir, name) 定位链，二次实现 = 漂移面）──
function workspaceLocateMissingText(dir: string, name: string): string {
  return '工作区' + (dir === '' ? '根目录' : '「' + dir + '」目录') +
    '没有名为「' + name + '」的文件。请先用 workspace_list 查看该目录里的文件名。';
}

function workspaceLocateMultiText(dir: string, name: string): string {
  return '工作区' + (dir === '' ? '根目录' : '「' + dir + '」目录') +
    '存在多个名为「' + name + '」的文件（数据异常），无法确定读取哪一份。' +
    '请用户在 设置 → 文件工作区 中删除重复文件。';
}

function workspaceLocateIsDirText(name: string): string {
  return '「' + name + '」是文件夹，不是文件。' +
    '要看里面的内容，把 ' + name + ' 填入 dir 调用 workspace_list。';
}

// 列出工作区一个目录的内容（按 dir 一层列举；dir 缺省归一助手默认文件夹——十件定位类统一
// 在闸前插 normalizeWorkspaceDirParam，闸与后续调用零改动）：
// dir 归一 → 闸 → 查全表（件数硬顶不变）→ 纯函数拆「该目录文件 + 子目录条目」→ 回执
export class WorkspaceListExecutor implements ToolExecutor {
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const dir: string = normalizeWorkspaceDirParam(argsString(parsed, 'dir'), ctx.assistantId);
    const dirReject: string = workspaceDirRejectReason(dir);
    if (dirReject !== '') {
      return JSON.stringify({ error: dirReject });
    }
    try {
      const rows: WorkspaceFileRow[] = await queryWorkspaceFiles(WORKSPACE_ROWS_READ_MAX);
      // 回执顺序跟随用户在管理页所选的排序方式（同序不变量——AI 与用户看到的顺序一致；
      // 偏好脏值经 resolve 兜底 'custom'，AppStorage 现读即用）
      const listing = deriveWorkspaceDirListing(rows, dir,
        resolveWorkspaceSortMode(AppStorage.get<string>(PREF_WORKSPACE_SORT_KEY)));
      return composeWorkspaceListReply(dir, listing.dirs, listing.briefs);
    } catch (e) {
      return JSON.stringify({ error: '工作区文件列表读取失败：' + (e as Error).message });
    }
  }
}

// 读取工作区文件：名称闸 + dir 闸 → (dir, name) 定位（零/多命中与类型不可读都中文报错；
// 零命中且该位置有同名子文件夹 = 给「是文件夹」指引）→ 读原文。read 四路分派 = doc（桥页
// 解析）/ image（有视觉挂图 / 无视觉 OCR）/ text（分段读）/ other（拒绝）
export class WorkspaceReadExecutor implements ToolExecutor {
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const name: string = argsString(parsed, 'name').trim();
    const dir: string = normalizeWorkspaceDirParam(argsString(parsed, 'dir'), ctx.assistantId);
    const offset: number = argsNumber(parsed, 'offset');
    const limit: number = argsNumber(parsed, 'limit');
    const col: number = argsNumber(parsed, 'col');
    const reject: string = workspaceNameRejectReason(name);
    if (reject !== '') {
      return JSON.stringify({ error: reject });
    }
    const dirReject: string = workspaceDirRejectReason(dir);
    if (dirReject !== '') {
      return JSON.stringify({ error: dirReject });
    }
    try {
      const matches: WorkspaceFileRow[] = await queryWorkspaceFilesByName(dir, name);
      if (matches.length === 0) {
        // 零命中升级（P0-1 给下一步指引）：该目录下有同段名子文件夹 = 指引模型改用 list
        const rows: WorkspaceFileRow[] = await queryWorkspaceFiles(WORKSPACE_ROWS_READ_MAX);
        const dirs = deriveWorkspaceDirListing(rows, dir).dirs;
        for (const d of dirs) {
          if (d.name === name) {
            return JSON.stringify({ error: workspaceLocateIsDirText(name) });
          }
        }
        return JSON.stringify({ error: workspaceLocateMissingText(dir, name) });
      }
      if (matches.length > 1) {
        return JSON.stringify({ error: workspaceLocateMultiText(dir, name) });
      }
      const row: WorkspaceFileRow = matches[0];
      if (isWorkspaceDirRow(row)) {
        // 目录行命中 = 文件夹（与零命中同段名指引同款文案——空文件夹命名撞文件名时模型
        // 得到的是指引不是「其他类型」误报）
        return JSON.stringify({ error: workspaceLocateIsDirText(name) });
      }
      const filesDir: string = workspaceFilesDir();
      if (filesDir === '') {
        return JSON.stringify({ error: '工作区目录未就绪，无法读取文件' });
      }
      if (row.kind === 'doc') {
        // doc 路：复用附件域桥页解析链（DocumentParse 四引擎）——上限前置闸（省大文件读盘 +
        // base64）→ 错误映射中文返回；执行器全程 await 不设额外超时（桥页 45s 上限即界），
        // throw 兜底（超时/未就绪/读副本失败）转错误映射
        const att: PendingAttachment = {
          fileId: row.id, name: row.name, mediaType: row.mime, size: row.size,
          kind: 'doc', localPath: filesDir + '/' + row.localPath
        };
        const hardLimit: number = docHardLimitBytes(att);
        const limitText: string = formatWorkspaceSize(hardLimit);
        if (hardLimit > 0 && row.size > hardLimit) {
          return JSON.stringify({
            error: workspaceParseErrorReply(row.name, 'file_too_large', limitText) });
        }
        // PDF 原件直传原生路——判据三条件 = 有视觉 ∧ doc+pdf（kind 由外层分支承接）∧ 尺寸窗
        // 4KB~8MB（DOC_NATIVE_* 单源 ToolMediaSupport）。协议×模型能力半边**不在此判**——由
        // collectImage 挂载返回值承接（禁本件写第二份协议判断）。任一环节不过（读失败 / 空
        // 字节 / 挂载 false）不 return、顺序落入下方解析路——同一调用内回落，用户与模型无感
        //（协议不支持时白读一次 ≤8MB 是登记过的代价）
        if (ctx.hasVision && row.mime === 'application/pdf' &&
          row.size >= DOC_NATIVE_MIN_BYTES && row.size <= DOC_NATIVE_MAX_BYTES) {
          const b64: string = readWorkspaceFileBase64(filesDir + '/' + row.localPath);
          if (b64 !== '' && ctx.collectImage('application/pdf', b64)) {
            return composeWorkspaceDocNativeReply(row.name);
          }
        }
        // 有视觉走 parseAttachment 全路径——thin 命中渲页成功时逐页挂图（collectPageImage 缝，
        // 不吃 8 张上限、单册 ≤ RENDER_MAX_PAGES 为界），回执 = meta 行 + 「页面图片已随本轮
        // 请求发送」说明句 + 文本照附；**有效预识别文本不参与本路**（有视觉 = 原件优先，即使
        // 已校对）；非 thin（文字层）与渲染降级照旧纯文本回执
        if (ctx.hasVision) {
          let parsedV: DocumentParseResult;
          try {
            parsedV = await docParser.parseAttachment(att);
          } catch (e) {
            return JSON.stringify({
              error: workspaceParseErrorReply(row.name, (e as Error).message, limitText) });
          }
          if (parsedV.success !== true) {
            return JSON.stringify({
              error: workspaceParseErrorReply(row.name, parsedV.error, limitText) });
          }
          const thinV: boolean = pdfTextThin(row.name, parsedV.textChars, parsedV.textPages);
          if (thinV && parsedV.pageImages.length > 0) {
            let attachedAll: boolean = true;
            for (const page of parsedV.pageImages) {
              if (!ctx.collectPageImage(page.mimeType, page.data)) {
                // 挂载失败（重发链等本轮 user 消息不可达）= 页图整批放弃 → 纯文本回执
                //（thin 提示句照给，模型据此知晓文字稀薄）
                attachedAll = false;
                break;
              }
            }
            if (attachedAll) {
              const metaV: string = workspaceDocMetaLine(parsedV.engine, parsedV.pageCount,
                false, parsedV.warning) + '页面图片已随本轮请求发送。';
              return composeWorkspaceReadReply(row.name, parsedV.text, offset, limit, metaV, col);
            }
          }
          return composeWorkspaceReadReply(row.name, parsedV.text, offset, limit,
            workspaceDocMetaLine(parsedV.engine, parsedV.pageCount, thinV, parsedV.warning), col);
        }
        // 无视觉：预识别优先——fresh 文本存在回执直接用（含来源标注，模型与用户读同一份）；
        // 否则现状 parseTextOnly（薄文本 + 提示句，渲染零开销）
        const ocrRec = await queryWorkspaceOcr(row.id);
        if (ocrRec !== null) {
          const docFp: WorkspaceStatFingerprint =
            readWorkspaceStatFingerprint(filesDir + '/' + row.localPath);
          const docState: string = ocrStateOf(ocrRec, docFp.mtimeMs, docFp.size);
          if (docState === 'fresh') {
            return composeWorkspaceReadReply(row.name, ocrRec.ocrText, offset, limit,
              '以下为' + workspaceOcrSourceLabel(docState, ocrRec.ocrEditedAt > 0) + '。', col);
          }
        }
        let parsed: DocumentParseResult;
        try {
          parsed = await docParser.parseTextOnly(att);
        } catch (e) {
          // 解析超时 / 解析器未就绪 / 读副本失败等 throw → 错误映射中文返回（已知 throw
          // message 有专属映射，其余原样透传保留诊断面）
          return JSON.stringify({
            error: workspaceParseErrorReply(row.name, (e as Error).message, limitText) });
        }
        if (parsed.success !== true) {
          return JSON.stringify({
            error: workspaceParseErrorReply(row.name, parsed.error, limitText) });
        }
        // doc 路行级分页——桥页长行经行内截断 + offset/col 续读指针读到底，与 text 路（本执行
        // 器末段）同形态；col 随回执指引透传
        return composeWorkspaceReadReply(row.name, parsed.text, offset, limit,
          workspaceDocMetaLine(parsed.engine, parsed.pageCount,
            pdfTextThin(row.name, parsed.textChars, parsed.textPages), parsed.warning), col);
      }
      if (row.kind === 'image') {
        // 图片路：回执恒纯文本，图经 ctx.collectImage 挂进本轮请求历史 user 消息 images
        //（AiChatMessage.images 既有通道——续传轮即带图、跨发送随历史重建消失，与附件本体
        // 同生命周期）；无视觉走 OCR 三态（runOcr 永不 reject；引擎回退 toast 在工具路不适
        // 用，告知由回执引擎名承载）。回执形态五路单源 = composeWorkspaceImageReply
        const absPath: string = filesDir + '/' + row.localPath;
        if (ctx.hasVision) {
          const imgAtt: PendingAttachment = {
            fileId: row.id, name: row.name, mediaType: row.mime, size: row.size,
            kind: 'image', localPath: absPath
          };
          let part: AiImagePart;
          try {
            part = await encodeImageBase64(imgAtt); // 附件链同规格：2048 长边缩边 + JPEG q85
          } catch (e) {
            return JSON.stringify({ error: '「' + row.name + '」图片读取失败：' +
              (e as Error).message + '。请让用户在应用的文件工作区中查看该图片。' });
          }
          if (!ctx.collectImage(part.mimeType, part.data)) {
            // 挂载失败 = 本轮 user 消息不可达（重发链）或超单发送图数上限
            //（TOOL_IMAGE_ATTACH_MAX）——中文回执说明，不静默
            return composeWorkspaceImageReply(row.name, 'attach_failed');
          }
          return composeWorkspaceImageReply(row.name, 'attached');
        }
        // 预识别优先——fresh 文本存在回执直接用（含来源标注），**不再当场 OCR**（模型与用户
        // 读同一份校对文本）；否则现状兜底（当场识别，结果只进回执不入库）
        const ocrRec = await queryWorkspaceOcr(row.id);
        if (ocrRec !== null) {
          const imgFp: WorkspaceStatFingerprint = readWorkspaceStatFingerprint(absPath);
          const imgState: string = ocrStateOf(ocrRec, imgFp.mtimeMs, imgFp.size);
          if (imgState === 'fresh') {
            return composeWorkspaceOcrFreshReply(row.name,
              workspaceOcrSourceLabel(imgState, ocrRec.ocrEditedAt > 0), ocrRec.ocrText);
          }
        }
        if (!ocrEnabled()) {
          return composeWorkspaceImageReply(row.name, 'ocr_disabled');
        }
        const sources: OcrImageSource[] = [{ kind: 'path', data: absPath }];
        const ocr: OcrOutcome = await runOcr(sources, (_msg: string): void => {
          // 回退 toast 通道空实现（见分支头注）——OcrEngine.notify 契约要求调用方注入
        });
        if (!ocr.ok) {
          return composeWorkspaceImageReply(row.name, 'ocr_failed');
        }
        if (ocr.text === '') {
          return composeWorkspaceImageReply(row.name, 'ocr_empty');
        }
        return composeWorkspaceImageReply(row.name, 'ocr_text', ocr.text, ocr.engine);
      }
      if (row.kind !== 'text') {
        // 拒绝域收窄为 other 档（image 档移出进上方图片路）；类型名走单源 workspaceKindLabel
        return JSON.stringify({ error: '「' + name + '」是' +
          workspaceKindLabel(row.kind) +
          '文件，不能读取内容。请使用它的名称与大小信息，或让用户在应用的文件工作区中查看。' });
      }
      const content: string = readWorkspaceFileText(filesDir + '/' + row.localPath);
      // 先读后编硬门登记触点——文本路回执成功处按行现值登记（doc / image 路不登记：不可
      // 编辑，登记无消费方；write/import/xlsx 三路不刷新读态，模型刚写完要编辑时会多一步
      // read——语义简单优先拍板）
      markWorkspaceRead(ctx.conversationId, row.id, row.size, row.updatedAt);
      return composeWorkspaceReadReply(name, content, offset, limit, '', col);
    } catch (e) {
      return JSON.stringify({ error: '工作区文件读取失败：' + (e as Error).message });
    }
  }
}

// ── 覆盖写 diff 尾行预读：写前经 ChatDb 委托定位既有行 → 读旧文 → 产尾行（摘录对或超阈
//    行数对）。仅覆盖语义接——无行（新建）→ 无尾行；读失败 / 非文本档 / 目录未就绪一律
//    降级无尾行——读旧文纯增益，写语义零变化（不阻塞写）。量纲 = 读后按字符复核（DB 行
//    sizeBytes 可能滞后——写文件与写行非原子，复核以实读为准）──
async function readWorkspaceWriteDiffTail(dir: string, rawName: string,
  content: string): Promise<string> {
  try {
    const filesDir: string = workspaceFilesDir();
    if (filesDir === '') {
      return '';
    }
    // 定位名与 store 写入路同源清洗（sanitize 后才是落库显示名——原名带非法字符时按原名
    // 查必落空）
    const rows: WorkspaceFileRow[] = await queryWorkspaceFilesByName(dir,
      sanitizeWorkspaceName(rawName));
    if (rows.length !== 1) {
      return '';
    }
    const row: WorkspaceFileRow = rows[0];
    if (isWorkspaceDirRow(row) || row.kind !== 'text') {
      return '';
    }
    const prevText: string = readWorkspaceFileText(filesDir + '/' + row.localPath);
    if (prevText.length > MOUNT_WRITE_MAX_CHARS) {
      return buildReceiptDiffOversizeTail(workspaceEditLineCount(prevText),
        workspaceEditLineCount(content));
    }
    return buildReceiptDiffExcerptTail(prevText, content);
  } catch {
    return '';
  }
}

// 保存文本到工作区（write 工具唯一写口 = ChatDb.saveWorkspaceText 委托；闸拒绝与 IO 失败
// 的中文原因经 WorkspaceSaveOutcome.errorText 原样透传——底层报错不美化，拍板设计）
export class WorkspaceWriteExecutor implements ToolExecutor {
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const name: string = argsString(parsed, 'name');
    const content: string = argsString(parsed, 'content');
    const dir: string = normalizeWorkspaceDirParam(argsString(parsed, 'dir'), ctx.assistantId);
    const dirReject: string = workspaceDirRejectReason(dir);
    if (dirReject !== '') {
      return JSON.stringify({ error: dirReject });
    }
    try {
      // 覆盖写读旧文产尾行（读失败/无行/超阈一律降级无尾行，不阻塞写——diffTail 只在下方
      // 成功路消费）
      const diffTail: string = await readWorkspaceWriteDiffTail(dir, name, content);
      const outcome = await saveWorkspaceText(name, content, WORKSPACE_SOURCE_ASSISTANT,
        ctx.conversationId, ctx.assistantId, dir);
      if (!outcome.ok) {
        return JSON.stringify({ error: outcome.errorText });
      }
      // 回执名取**实际落库显示名**（outcome.displayName——清洗后），不复用原始入参 name：
      // 含 :*?"<>| 的名清洗后落库为别的名字，报原名 = 名漂移（模型随后按回执名 read 必失败）。
      // 覆盖注记由 store 判据置位，执行器只透传——`?? ''` 把 undefined〔新建/失败态〕与空档
      // 一并收进不注记（xlsx 路下方同款透传）
      return composeWorkspaceWriteReply(outcome.displayName, outcome.sizeBytes,
        outcome.totalCount, outcome.overwriteKind ?? '', diffTail);
    } catch (e) {
      return JSON.stringify({ error: '工作区保存失败：' + (e as Error).message });
    }
  }
}

// 会话附件按名导入工作区（附件按 name 精确匹配唯一命中才导，零/多命中中文报错指引；
// 动作壳 = HttpBinary.importAttachmentToWorkspace——30MB 单件闸 + 容量两闸 + 同名覆盖
// upsert，闸拒绝与 IO 失败中文透传不美化；dir 定位落点）
export class WorkspaceImportExecutor implements ToolExecutor {
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const name: string = argsString(parsed, 'name').trim();
    const dir: string = normalizeWorkspaceDirParam(argsString(parsed, 'dir'), ctx.assistantId);
    if (name.indexOf('/') >= 0 || name.indexOf('\\') >= 0 || name.indexOf('..') >= 0 ||
      name === '') {
      return JSON.stringify({ error: '附件名不合法，请给当前会话中用户发送过的附件名' });
    }
    const dirReject: string = workspaceDirRejectReason(dir);
    if (dirReject !== '') {
      return JSON.stringify({ error: dirReject });
    }
    try {
      // 匹配窗口单源 ATTACHMENT_MATCH_WINDOW_MAX（ToolLimits，与 http 域上传源匹配同值
      // 同源）——单会话附件超窗时更早的附件不在匹配域（已知边界）
      const rows = await queryAttachmentsByConversation(ctx.conversationId,
        ATTACHMENT_MATCH_WINDOW_MAX, 0);
      const hits = rows.filter((row: AttachmentListRow): boolean => row.name === name);
      if (hits.length === 0) {
        return JSON.stringify({ error: '会话中没有名为「' + name +
          '」的附件。可用的附件名单见对话中的「[附件]」标注' });
      }
      if (hits.length > 1) {
        return JSON.stringify({ error: '有 ' + hits.length + ' 个名为「' + name +
          '」的附件，暂不支持区分，请先删除多余同名附件' });
      }
      const outcome = await importAttachmentToWorkspace(hits[0], ctx.conversationId,
        ctx.assistantId, dir);
      if (!outcome.ok) {
        return JSON.stringify({ error: outcome.errorText });
      }
      // 覆盖注记：与 write / write_xlsx 两路共用单源句（workspaceOverwriteNote）；本回执
      // 基句尾无句号——非空档先补「。」再接句（空档零拼接，与既有回执逐字一致）
      const note: string = workspaceOverwriteNote(outcome.overwriteKind ?? '');
      return '已把「' + outcome.name + '」存入文件工作区' +
        (dir === '' ? '' : '的「' + dir + '」文件夹') + '，共 ' + outcome.size +
        ' 字节。用户在 设置 → 文件工作区 可以查看' + (note === '' ? '' : '。' + note);
    } catch (e) {
      return JSON.stringify({ error: '附件存入工作区失败：' + (e as Error).message });
    }
  }
}

// ── xlsx 生成执行器（三段编排：产出核临时件 → 桥页反读自检〔坏件永不落工作区——zip 结构
//    类缺陷在生成当场暴露〕→ 落库编排〔闸与行写全在 WorkspaceDbXlsx〕。临时件成败两路
//    都删——成对释放红线）──

// 临时件 best-effort 删除（编排成功路已删；闸拒绝面与自检失败路由本口兜删）
function removeTempFileQuiet(tempPath: string): void {
  try {
    fs.unlinkSync(tempPath);
  } catch {
    // cacheDir 残留由系统清缓存兜底，不吞上游错误
  }
}

export class WorkspaceWriteXlsxExecutor implements ToolExecutor {
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const name: string = argsString(parsed, 'name');
    const rows: string = argsString(parsed, 'rows');
    const sheet: string = argsString(parsed, 'sheet');
    const dir: string = normalizeWorkspaceDirParam(argsString(parsed, 'dir'), ctx.assistantId);
    const dirReject: string = workspaceDirRejectReason(dir);
    if (dirReject !== '') {
      return JSON.stringify({ error: dirReject });
    }
    const cacheDir: string = workspaceCacheDir();
    if (cacheDir === '') {
      return JSON.stringify({ error: '工作区目录未就绪，无法生成表格文件' });
    }
    let tempPath: string = '';
    try {
      try {
        tempPath = await buildXlsxToTemp(rows, sheet, cacheDir);
      } catch (e) {
        // 产出核的中文校验错（非法 JSON / 非二维数组 / 行列超限 / 打包失败）原样透传
        return JSON.stringify({ error: (e as Error).message });
      }
      // 反读自检（桥页在会话页上下文恒在场）：SheetJS 解析临时件，success 且非空文本才放行
      // 落库——解析失败或空文本 = 结构缺陷坏件，删除并中文报错（P0-1）。失败原因随回执带出
      //（吞掉 parse error 只报「请检查数据格式」会让 zip 结构类真因不可见）
      let checkText = '';
      let checkOk = false;
      let checkError: string = '';
      try {
        const checkAtt: PendingAttachment = {
          fileId: 'xlsx_selfcheck', name: '工作区表格自检.xlsx',
          mediaType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          size: 0, kind: 'doc', localPath: tempPath
        };
        const checkResult = await docParser.parseTextOnly(checkAtt);
        checkOk = checkResult.success === true;
        checkText = checkResult.text;
        checkError = checkResult.error;
      } catch (e) {
        checkError = (e as Error).message;
      }
      if (!checkOk || checkText === '') {
        removeTempFileQuiet(tempPath);
        return JSON.stringify({
          error: '表格文件生成结果校验未通过，已放弃保存。' +
            (checkError !== '' ? '原因：' + checkError : '请稍后重试。') });
      }
      const outcome = await saveWorkspaceXlsx(name, tempPath, WORKSPACE_SOURCE_ASSISTANT,
        ctx.conversationId, ctx.assistantId, dir);
      if (!outcome.ok) {
        // 编排的闸拒绝面未删临时件（编排只在拷贝后删）——本口兜删（成对释放）
        removeTempFileQuiet(tempPath);
        return JSON.stringify({ error: outcome.errorText });
      }
      // 覆盖注记档透传（xlsx 路与文本路同款判据单源）
      return composeWorkspaceWriteReply(outcome.displayName, outcome.sizeBytes,
        outcome.totalCount, outcome.overwriteKind ?? '');
    } catch (e) {
      if (tempPath !== '') {
        removeTempFileQuiet(tempPath);
      }
      return JSON.stringify({ error: '表格文件保存失败：' + (e as Error).message });
    }
  }
}

// ── 目录四工具执行器（照既有四类形态：JSON.parse try/catch → 参数闸 → ChatDb 委托 →
//    回执；失败 JSON error）──

// 建文件夹：dir 归一（缺省 = 助手默认文件夹）→ 闸在动作壳内（createWorkspaceDirOp 产中文
// errorText；传会话追溯两参供目录行铸造）
export class WorkspaceMkdirExecutor implements ToolExecutor {
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const dir: string = normalizeWorkspaceDirParam(argsString(parsed, 'dir'), ctx.assistantId);
    try {
      const outcome = await createWorkspaceDirOp(dir, WORKSPACE_SOURCE_ASSISTANT,
        ctx.conversationId, ctx.assistantId);
      if (!outcome.ok) {
        return JSON.stringify({ error: outcome.errorText });
      }
      return composeWorkspaceDirCreatedReply(dir, outcome.alreadyExists);
    } catch (e) {
      return JSON.stringify({ error: '文件夹创建失败：' + (e as Error).message });
    }
  }
}

// 重命名：dir/newName 双闸 → 动作壳 → 回执（文件夹语境报段名路径，纯函数组装）
export class WorkspaceRenameExecutor implements ToolExecutor {
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const dir: string = normalizeWorkspaceDirParam(argsString(parsed, 'dir'), ctx.assistantId);
    const name: string = argsString(parsed, 'name').trim();
    const newName: string = argsString(parsed, 'new_name').trim();
    const reject: string = workspaceNameRejectReason(name);
    if (reject !== '') {
      return JSON.stringify({ error: reject });
    }
    try {
      const outcome = await renameWorkspaceEntryOp(dir, name, newName);
      if (!outcome.ok) {
        return JSON.stringify({ error: outcome.errorText });
      }
      return composeWorkspaceRenameReply(dir, name, newName, outcome.isDir);
    } catch (e) {
      return JSON.stringify({ error: '重命名失败：' + (e as Error).message });
    }
  }
}

// 移动：dir/toDir 双闸 → 动作壳 → 回执（移到根两态，纯函数组装）。to_dir 与 dir 同款归一
//（移动目标缺省 = 助手默认文件夹，/ 表根）
export class WorkspaceMoveExecutor implements ToolExecutor {
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const dir: string = normalizeWorkspaceDirParam(argsString(parsed, 'dir'), ctx.assistantId);
    const name: string = argsString(parsed, 'name').trim();
    const toDir: string = normalizeWorkspaceDirParam(argsString(parsed, 'to_dir'), ctx.assistantId);
    const reject: string = workspaceNameRejectReason(name);
    if (reject !== '') {
      return JSON.stringify({ error: reject });
    }
    try {
      const outcome = await moveWorkspaceEntryOp(dir, name, toDir);
      if (!outcome.ok) {
        return JSON.stringify({ error: outcome.errorText });
      }
      return composeWorkspaceMoveReply(toDir,
        outcome.isDir ? joinDirName(dir, name) : name, outcome.isDir);
    } catch (e) {
      return JSON.stringify({ error: '移动失败：' + (e as Error).message });
    }
  }
}

// 删除：dir 闸 → 动作壳（删前统计随结果回）→ 回执（文件夹报件数与合计）
export class WorkspaceDeleteExecutor implements ToolExecutor {
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const dir: string = normalizeWorkspaceDirParam(argsString(parsed, 'dir'), ctx.assistantId);
    const name: string = argsString(parsed, 'name').trim();
    const reject: string = workspaceNameRejectReason(name);
    if (reject !== '') {
      return JSON.stringify({ error: reject });
    }
    try {
      const outcome = await deleteWorkspaceEntryOp(dir, name);
      if (!outcome.ok) {
        return JSON.stringify({ error: outcome.errorText });
      }
      return composeWorkspaceDeleteReply(
        outcome.isDir ? joinDirName(dir, name) : name, outcome.isDir,
        outcome.fileCount, outcome.totalBytes);
    } catch (e) {
      return JSON.stringify({ error: '删除失败：' + (e as Error).message });
    }
  }
}

// ── 检索两工具执行器（闸与回执全在 WorkspaceSearchUtil 纯函数——执行器只管参数闸与 IO
//    注入；行集贴 WORKSPACE_ROWS_READ_MAX 时回执尾注如实申报「结果可能不全」〔行集截断面〕）──

// 按名称模式查找：dir 闸 → 行集 → 纯函数匹配（编译失败按内部错误兜底——五规则全覆盖不该
// 发生，兜底回执防崩）→ 回执
export class WorkspaceGlobExecutor implements ToolExecutor {
  async execute(argsJson: string, _ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const pattern: string = argsString(parsed, 'pattern').trim();
    const dir: string = argsString(parsed, 'dir').trim();
    if (pattern === '') {
      return JSON.stringify({ error: '查找模式不能为空' });
    }
    const dirReject: string = workspaceDirRejectReason(dir);
    if (dirReject !== '') {
      return JSON.stringify({ error: dirReject });
    }
    try {
      const rows: WorkspaceFileRow[] = await queryWorkspaceFiles(WORKSPACE_ROWS_READ_MAX);
      try {
        const result = matchWorkspaceGlob(rows, pattern, dir);
        return composeWorkspaceGlobReply(pattern, dir, result.matches, result.truncated,
          rows.length >= WORKSPACE_ROWS_READ_MAX);
      } catch {
        return JSON.stringify({ error: '查找模式无法解析，请换一个模式重试' });
      }
    } catch (e) {
      return JSON.stringify({ error: '工作区文件查找失败：' + (e as Error).message });
    }
  }
}

// 文本内容搜索：dir 闸 → 正则构造（非法回退字面量 literal 注明；嵌套量词等高危形态降级
// 字面量 risky 注明）→ 行集 → 纯函数扫描（读入经 readWorkspaceFileText 注入；单件读失败
// 跳过计数在纯函数内）→ 回执
export class WorkspaceGrepExecutor implements ToolExecutor {
  async execute(argsJson: string, _ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const pattern: string = argsString(parsed, 'pattern').trim();
    const dir: string = argsString(parsed, 'dir').trim();
    const ignoreCase: boolean = argsBoolean(parsed, 'ignore_case');
    const limit: number = argsNumber(parsed, 'limit');
    if (pattern === '') {
      return JSON.stringify({ error: '搜索内容不能为空' });
    }
    const dirReject: string = workspaceDirRejectReason(dir);
    if (dirReject !== '') {
      return JSON.stringify({ error: dirReject });
    }
    const filesDir: string = workspaceFilesDir();
    if (filesDir === '') {
      return JSON.stringify({ error: '工作区目录未就绪，无法搜索文件内容' });
    }
    try {
      const regex = buildWorkspaceGrepRegex(pattern, ignoreCase);
      const limitEff: number = normalizeWorkspaceGrepLimit(limit);
      const rows: WorkspaceFileRow[] = await queryWorkspaceFiles(WORKSPACE_ROWS_READ_MAX);
      const scan = scanWorkspaceGrep(rows, dir, regex.regex, limitEff,
        (localPath: string): string => readWorkspaceFileText(filesDir + '/' + localPath));
      return composeWorkspaceGrepReply(pattern, regex.literal, dir, scan,
        rows.length >= WORKSPACE_ROWS_READ_MAX, regex.risky);
    } catch (e) {
      return JSON.stringify({ error: '工作区文件内容搜索失败：' + (e as Error).message });
    }
  }
}

// ── 编辑工具执行器（链外闸全在本层：E1 解析 / E2 名称与目录闸 / E7 空原文 / E8 无变化 /
//    E3~E6 前置定位（文案单源 WorkspaceDbEdit 构造器）/ E11·E12 先读后编硬门
//   （WorkspaceReadState 行为门——门过与链内重读之间的并行窗口由链内现读匹配兜底）；
//    存储编排（链内现读 → 匹配 → 写回 → 行更新）全在 ChatDb.editWorkspaceText 委托的
//    runWriteQueued 链节内）──
export class WorkspaceEditExecutor implements ToolExecutor {
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const name: string = argsString(parsed, 'name').trim();
    const dir: string = normalizeWorkspaceDirParam(argsString(parsed, 'dir'), ctx.assistantId);
    const oldText: string = argsString(parsed, 'old_string');
    const newText: string = argsString(parsed, 'new_string');
    const replaceAll: boolean = argsBoolean(parsed, 'replace_all');
    const reject: string = workspaceNameRejectReason(name);
    if (reject !== '') {
      return JSON.stringify({ error: reject });
    }
    const dirReject: string = workspaceDirRejectReason(dir);
    if (dirReject !== '') {
      return JSON.stringify({ error: dirReject });
    }
    if (oldText === '') {
      return JSON.stringify({
        error: '要替换的原文不能为空。请从 workspace_read 的结果里选择要修改的内容。' });
    }
    if (oldText === newText) {
      return JSON.stringify({
        error: '要替换的原文与替换后的内容相同，没有需要修改的内容。' });
    }
    try {
      // 链外前置定位（E3/E4/E5/E6——文案与存储编排链内同源）；零命中不查文件夹升级
      //（编辑语境无「进目录」出路，直接指引重查文件名）
      const matches: WorkspaceFileRow[] = await queryWorkspaceFilesByName(dir, name);
      if (matches.length === 0) {
        return JSON.stringify({ error: editNoHitText(dir, name) });
      }
      if (matches.length > 1) {
        return JSON.stringify({ error: editMultiHitText(dir, name) });
      }
      const row: WorkspaceFileRow = matches[0];
      if (isWorkspaceDirRow(row)) {
        return JSON.stringify({ error: editIsDirText(name) });
      }
      if (row.kind !== 'text') {
        return JSON.stringify({ error: editKindNotEditableText(name, row.kind) });
      }
      // 先读后编硬门（E11 未读 / E12 已过期——键含会话 id，跨会话不共用）
      const readState: string =
        checkWorkspaceRead(ctx.conversationId, row.id, row.size, row.updatedAt);
      if (readState === 'missing') {
        return JSON.stringify({
          error: '编辑前需要先读取文件。请先用 workspace_read 读取「' + name + '」，再重试编辑。' });
      }
      if (readState === 'stale') {
        return JSON.stringify({
          error: '「' + name + '」在读取之后被修改过。请用 workspace_read 重新读取，' +
            '再按新内容调整 old_string 后重试。' });
      }
      const outcome = await editWorkspaceText(dir, name, oldText, newText, replaceAll,
        ctx.conversationId);
      if (!outcome.ok) {
        return JSON.stringify({ error: outcome.errorText });
      }
      // 编辑成功处刷新登记（否则「连改两处」第二次被自己的首次编辑判过期）
      markWorkspaceRead(ctx.conversationId, outcome.fileId, outcome.sizeBytes,
        outcome.updatedAt);
      return composeWorkspaceEditReply(outcome.displayName, outcome.strategy,
        outcome.replacements, outcome.beforeLineCount, outcome.afterLineCount,
        outcome.sizeBytes, outcome.overwriteKind ?? '');
    } catch (e) {
      return JSON.stringify({ error: '工作区文件编辑失败：' + (e as Error).message });
    }
  }
}

// ── 入向桥执行器（workspace_stage——工作区件 → 本会话临时区。定位链与 read 同款〔三态
//    文案单源 workspaceLocate* 三函数〕，kind 全放行〔text/doc/image/other——二进制正是
//    目的〕只拒目录行；执行编排全在 store 侧 stageWorkspaceFileToTmp〔入写链 + 两闸 + 终名
//    + fd 拷贝 + 失败自清〕。原「代码工作台总开关三面闸」已随总开关退役——声明面随助手
//   「脚本工作台」卡进出，无全局闸）──
export class WorkspaceStageExecutor implements ToolExecutor {
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const name: string = argsString(parsed, 'name').trim();
    const dir: string = normalizeWorkspaceDirParam(argsString(parsed, 'dir'), ctx.assistantId);
    const reject: string = workspaceNameRejectReason(name);
    if (reject !== '') {
      return JSON.stringify({ error: reject });
    }
    const dirReject: string = workspaceDirRejectReason(dir);
    if (dirReject !== '') {
      return JSON.stringify({ error: dirReject });
    }
    // 临时区按会话分目录——无会话即无落点
    if (ctx.conversationId === '') {
      return JSON.stringify({ error: '本工具只在会话中可用，当前执行上下文没有会话。' });
    }
    try {
      const matches: WorkspaceFileRow[] = await queryWorkspaceFilesByName(dir, name);
      if (matches.length === 0) {
        return JSON.stringify({ error: workspaceLocateMissingText(dir, name) });
      }
      if (matches.length > 1) {
        return JSON.stringify({ error: workspaceLocateMultiText(dir, name) });
      }
      const row: WorkspaceFileRow = matches[0];
      if (isWorkspaceDirRow(row)) {
        return JSON.stringify({ error: workspaceLocateIsDirText(name) });
      }
      const outcome = await stageWorkspaceFileToTmp(ctx.conversationId, row.localPath, row.name);
      if (!outcome.ok) {
        return JSON.stringify({ error: outcome.errorText });
      }
      // 回执恒报终名（撞名时含序号——模型按回执名读件必命中）；改名态补同名说明句
      if (outcome.name !== row.name) {
        return '已把工作区文件「' + row.name + '」放进本会话临时区。临时区里已有同名文件，' +
          '本次的文件名为「' + outcome.name + '」，共 ' + outcome.size +
          ' 字节。脚本用 fs.readBytes 读取它的字节。';
      }
      return '已把工作区文件「' + row.name + '」放进本会话临时区，共 ' + outcome.size +
        ' 字节。脚本用 fs.readBytes 读取它的字节。';
    } catch (e) {
      return JSON.stringify({ error: '放入临时区失败：' + toolErrorText(e) });
    }
  }
}

// 确认链预检（仅 delete；形态照 manageKnowledgeNeedsConfirm——全包 try/catch 恒 null）：
// 解析 dir/name → **dir 与执行器同款归一**（缺省 = 助手默认文件夹——预检与执行器归一不
// 一致时，缺省 dir 的删除会在根目录定位 → 预检 null 不弹卡 → 执行器却在助手文件夹命中直删，
//「删除恒问人」契约被跳过）→ 闸不过或 name 空 = null（执行器报参数错，不弹卡）→ 一次全表
// 内存判定文件/文件夹与规模 → 文件 = IRREVERSIBLE 卡；文件夹 = 同卡 + detail 件数与合计
//（结构化预览先例 ToolContracts.detail，卡面折叠渲染）；定位未命中 / 同段名文件×文件夹二义
// = null（不弹卡交执行器出专属拒文——照 browse_act 先例）
export async function workspaceDeleteNeedsConfirm(argsJson: string,
  ctx: ToolExecutionContext): Promise<ConfirmPrompt | null> {
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    const dirRaw: Object | undefined = parsed['dir'];
    const nameRaw: Object | undefined = parsed['name'];
    const dir: string = normalizeWorkspaceDirParam(
      typeof dirRaw === 'string' ? dirRaw : '', ctx.assistantId);
    const name: string = typeof nameRaw === 'string' ? nameRaw.trim() : '';
    if (dir === '' ? false : workspaceDirRejectReason(dir) !== '') {
      return null;
    }
    if (name === '' || workspaceNameRejectReason(name) !== '') {
      return null;
    }
    const rows: WorkspaceFileRow[] = await queryWorkspaceFiles(WORKSPACE_ROWS_READ_MAX);
    let fileHit: WorkspaceFileRow | undefined = undefined;
    let dirHit: WorkspaceFileRow | undefined = undefined;
    for (const row of rows) {
      if (row.dir === dir && row.name === name) {
        // 命中分流——目录行 = 文件夹态（件数统计只数文件行，目录行 size=0 不贡献 bytes
        // 也不计件数）
        if (isWorkspaceDirRow(row)) {
          dirHit = row;
        } else {
          fileHit = row;
        }
        break;
      }
    }
    const childPath: string = joinDirName(dir, name);
    let count = 0;
    let bytes = 0;
    for (const row of rows) {
      if (row.dir === childPath || row.dir.startsWith(childPath + '/')) {
        if (!isWorkspaceDirRow(row)) {
          count++;
          bytes += row.size;
        }
      }
    }
    if (fileHit !== undefined && count > 0) {
      return null; // 同段名文件行与文件夹前缀并存 = 二义，不弹卡（执行器报错）
    }
    if (fileHit !== undefined) {
      return routeConfirmPrompt({ text: '删除文件工作区的「' + name + '」',
        level: CONFIRM_LEVEL_IRREVERSIBLE }, dataApproveMode());
    }
    if (dirHit !== undefined || count > 0) {
      return routeConfirmPrompt({ text: '删除文件工作区的「' + name + '」',
        level: CONFIRM_LEVEL_IRREVERSIBLE,
        detail: count > 0 ? '将删除 ' + count + ' 个文件，合计 ' + formatWorkspaceSize(bytes) :
          '删除后无法恢复' }, dataApproveMode());
    }
    // 物理探测兜底：无行空物理目录同样弹卡——「删除恒问人」契约不因探测态跳过（不探测则
    // 执行器能删而预检放空 = 跳卡删除）
    const filesDir: string = workspaceFilesDir();
    if (filesDir !== '' &&
      physicalWorkspaceDirExists(filesDir + '/' + relativeWorkspacePath(dir, name))) {
      return routeConfirmPrompt({ text: '删除文件工作区的「' + name + '」',
        level: CONFIRM_LEVEL_IRREVERSIBLE, detail: '删除后无法恢复' }, dataApproveMode());
    }
    return null; // 未命中 = 执行器报未命中
  } catch (e) {
    return null;
  }
}
