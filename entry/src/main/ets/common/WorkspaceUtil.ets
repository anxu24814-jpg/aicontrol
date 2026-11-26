// 文件工作区纯函数域：目录名/限额常量单源、名称与路径闸、显示名与文件名派生、行构建、
// 回执组装与收口（回执组装域已外迁 common/WorkspaceReply.ets——该件单向 import 本件；
// 检索两工具纯函数域在 common/WorkspaceSearchUtil.ets，系越 1200 硬线拆出，202 组零
// import 钉续守）。
// · 零 import 纪律（照 ToolIds 叶子先例）：本文件是断言直跑的纯函数叶子——引一次就把
//   可求值依赖带回叶子（断言剥 import 直跑、环与求值序风险一起回来），故与附件域的
//   extOf / classifyByName / formatFileSize 同值的实现在此**自持第二份**（两文件互不
//   import，同值由 assert-workspace-domain 断言钉一致——照 AttachmentUtil.ATTACH_DIR
//   同值先例）。
// · 消费方：store 层 WorkspaceDb.ets（行构建/路径派生/闸判定）、工具域 ToolWorkspace.ets
//  （名称闸/回执组装）、UI 层 WorkspaceManagePage.ets 与 WorkspaceListRows.ets /
//   WorkspaceSessionView.ets（会话分组/路径导航/移动目标/子树统计四族派生单源在此）。
// · 与代码工作台对表（方案 §7.4）：目录名常量与三闸数值是未来代码工作台的单源——改值 =
//   改它的限额，两处实现须逐条对齐。
// · 安全边界单源：模型恒按显示名引用、路径永不入参——name 含 / \ .. \0 或纯空白按名称
//   非法拒绝（name 恒为单段显示名）；dir 是对模型/UI 的**逻辑路径**（相对工作区根、
//   / 分隔），过 workspaceDirRejectReason 受闸后才可触 IO；实际文件路径恒由应用侧派生
//   workspace/[dir段…/]<fileId>.<ext>——模型无法影响物理路径的 UUID 段，目录段也只能
//   在受闸白名单形态内（.. \ \0 与空段全拒）。
// · kind='dir' 行 = 文件夹一等行（一行 = 一个文件或一个文件夹）：name=段名、dir=父目录、
//   size=0、localPath=目录相对路径（workspace/[段…]，无尾斜杠）；文件分类四档
//   image/text/doc/other 冻结不动，'dir' 是**行类型判别位**非文件分类；统计与三闸件数
//   口径排除目录行（文件夹不计件数不占容量）。

// ── 目录与限额常量（全仓单源；数值照代码工作台书对表）──
// 工作区目录名（挂 filesDir 下；与 WorkspaceDb 侧消费经本常量派生，无第二字面量）
export const WORKSPACE_DIR_NAME: string = 'workspace';
// 总件数上限（模型写入与用户上传共用；决明拍板上调 1000——下载产物默认入工作区。管理页
// 列表随改 List + LazyForEach 懒加载——件数放宽须分页/懒加载）
export const WORKSPACE_MAX_COUNT: number = 1000;
// 行集读取上限（自检轮修）：凡「一次查全表行集」的 queryWorkspaceFiles 实参一律用本常量，
// 件数闸仍用 WORKSPACE_MAX_COUNT——两值语义不同不可互替。行集 = 文件行（≤ 件数硬闸）+
// 目录行（无产品闸），原「全表实参 = 件数上限」使行总数越 1000 即截断：对账把未读到的行
// 当「无行」重复补录（静默数据破损）、创建面把守与 list/管理页缺行。本值 = 件数上限 ×4
//（目录行预算余量）；「文件夹数产品闸」为已登记的待拍板观察项
export const WORKSPACE_ROWS_READ_MAX: number = WORKSPACE_MAX_COUNT * 4;
// 总量上限（字节；模型写入与用户上传共用。决明定值 1GB——竞品均无总量配额，保守大闸 +
// 管理页手动清理兜底）
export const WORKSPACE_MAX_TOTAL_BYTES: number = 1024 * 1024 * 1024;
// 模型写单件上限（字节）
export const WORKSPACE_WRITE_MAX_BYTES: number = 1024 * 1024;
// 用户上传单件上限（字节）
export const WORKSPACE_UPLOAD_MAX_BYTES: number = 10 * 1024 * 1024;
// 模型读回执单段上限（字符；= offset/limit 分段读的缺省与上限同值——长文分次读完，尾注
// 给下一 offset 指针）
export const WORKSPACE_READ_MAX_CHARS: number = 8000;
// xlsx 写出行数上限（行；与桥页读侧每 sheet ≤10000 行写读同界对称——写侧上限单源住本
// 常量，WorkspaceXlsx 消费方禁散写 10000 字面量）
export const WORKSPACE_XLSX_MAX_ROWS: number = 10000;
// xlsx 单元格文字上限（字符；Excel 单格规格硬限，超限静默截断保存——desc 注明句在
// WORKSPACE_WRITE_XLSX_DESC，消费方禁散写 32767 字面量）
export const WORKSPACE_XLSX_CELL_MAX_CHARS: number = 32767;
// 显示名长度上限（字符）
export const WORKSPACE_NAME_MAX_CHARS: number = 80;
// 目录深度上限（段数；定序契约代决值，改值 = 全链单源生效）
export const WORKSPACE_DIR_MAX_DEPTH: number = 8;
// 目录总长上限（字符；同上代决值单源）
export const WORKSPACE_DIR_MAX_CHARS: number = 256;
// 三件工具回执总预算（字符；照 clipToolResult 8192 同值——工具域全工具回执硬顶）
export const WORKSPACE_REPLY_BUDGET: number = 8192;
// 助手默认文件夹根段：助手保存文件未指定位置时的缺省落点 = assistants/<助手id>——目录形态
// 单源派生（下方 defaultWorkspaceDirForAssistant 族），assistants 表不加列（列值恒等于
// 派生值 = 值抄本）
export const WORKSPACE_ASSISTANT_DIR_ROOT: string = 'assistants';
// doc meta 的 warning 回显上限（字符；有界口径）：warning 来自桥页解析结果，docx 路 =
// mammoth messages 全量 join——由外部文档内容决定、长度无上限（其余引擎为定值短句）。
// 原样拼进 meta 会顶穿帧体预算：超 8K 时 frameBudget 为负，截断路径产出无效续读指针
//（col 负值不前移，模型按指针重发原地循环）。回显位截断 + '…'，正常 warning 逐字不变
export const WORKSPACE_DOC_WARNING_MAX_CHARS: number = 200;
// 目录行判别值（kind 第五值 = 行类型位非文件分类——文件分类四档冻结不动；统计 / 三闸 /
// 管理页平铺列表 / 上传匹配均按「排除本值行」消费，文件夹派生〔list 子目录条目、
// dirChildSegments〕按「读本值行」消费）
export const WORKSPACE_KIND_DIR: string = 'dir';

// 来源四值（产生者标注：'user' 用户上传 / 'assistant' 助手保存（含导入件——模型把会话
// 附件存入工作区）/ 'download' HTTP 下载件 / 'recovered' 启动对账补录的磁盘恢复件——外部
// 塞进沙箱目录的文件重启后入册的来源档）——UI 与回执的来源标签均经 sourceLabel 派生，
// 禁散写中文字面量
export const WORKSPACE_SOURCE_USER: string = 'user';
export const WORKSPACE_SOURCE_ASSISTANT: string = 'assistant';
export const WORKSPACE_SOURCE_DOWNLOAD: string = 'download';
export const WORKSPACE_SOURCE_RECOVERED: string = 'recovered';

// ── 压缩包三工具限额组（2026-10-31 ZIP 三件笔立；模型可见数字与 desc 单源，断言侧经
//    ZipGateLimits 参数传值做关系判据、禁抄常量值进判据）──
// zip 输入单包上限（zip_list / zip_extract 共用；字节）——读侧整读闸
export const ZIP_INPUT_MAX_BYTES: number = 100 * 1024 * 1024;
// 解压声明展开总量上限（字节；声明值预检 + 实测值执法两道共用口径——实测是第二道闸，
// 声明值可伪造；量级对齐 tmp 区总闸但两闸独立无关系钉）
export const ZIP_EXPAND_MAX_BYTES: number = 256 * 1024 * 1024;
// zip 条目数上限（解压与打包共用；条）
export const ZIP_ENTRY_MAX_COUNT: number = 5000;
// 解压单件上限（字节；压缩炸弹缓解——声明与实测两道都过它）
export const ZIP_MEMBER_MAX_BYTES: number = 50 * 1024 * 1024;
// 打包产物上限（字节；按源文件合计预检）
export const ZIP_CREATE_OUTPUT_MAX_BYTES: number = 100 * 1024 * 1024;
// Office 补丁输入上限（字节；office_patch 单件读侧闸）——对齐桥页 Office 读侧线
// DocumentParse EXCEL_HARD_BYTES 同值 20MB，留解包改写中间态裕量
export const OFFICE_PATCH_INPUT_MAX_BYTES: number = 20 * 1024 * 1024;

// ── 扩展名白名单（与 AttachmentUtil 三表同值——见头注释同值钉约定）──
const IMAGE_EXTS: string[] = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif'];
const TEXT_EXTS: string[] = ['txt', 'md', 'log', 'json', 'csv', 'xml', 'html', 'htm', 'yml',
  'yaml', 'toml', 'ini', 'sh', 'bat', 'ps1', 'py', 'js', 'ts', 'c', 'h', 'cpp', 'java', 'css'];
const DOC_EXTS: string[] = ['pdf', 'docx', 'xlsx', 'xls', 'ofd', 'pptx'];
// 行首图标档位白名单（workspaceIconTierOf 专用）：表格档与 WorkspaceStatsUtil.SHEET_EXTS
// 逐字同值（同一 csv 在数据总览归「表格」、列表图标同档——防两处口径漂移，断言钉守）；
// 压缩/音视频三表本域自持
const SHEET_EXTS: string[] = ['xlsx', 'xls', 'csv'];
const ARCHIVE_EXTS: string[] = ['zip', '7z', 'rar'];
const AUDIO_EXTS: string[] = ['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg', 'opus'];
const VIDEO_EXTS: string[] = ['mp4', 'mov', 'mkv', 'avi', 'webm', '3gp'];

// 文件名扩展名（小写、无点；无扩展名回 ''——与 AttachmentUtil.extOf 同形同值）
export function extOfWorkspaceName(name: string): string {
  const dot: number = name.lastIndexOf('.');
  if (dot < 0 || dot >= name.length - 1) {
    return '';
  }
  return name.substring(dot + 1).toLowerCase();
}

// 按扩展名判定类：'image' | 'text' | 'doc' | ''（空 = 不支持——上传闸拒收；与
// AttachmentUtil.classifyByName 同形同值，白名单三表同值）
export function classifyWorkspaceName(name: string): string {
  const ext: string = extOfWorkspaceName(name);
  if (IMAGE_EXTS.indexOf(ext) >= 0) {
    return 'image';
  }
  if (TEXT_EXTS.indexOf(ext) >= 0) {
    return 'text';
  }
  if (DOC_EXTS.indexOf(ext) >= 0) {
    return 'doc';
  }
  return '';
}

// 行首图标档位：ext 专属档先行（pdf / 表格 / 压缩 / 音视频——pdf·xlsx·xls 在 kind 档归
// doc、csv 归 text，跨档故按扩展名单判），kind 兜底（image / text / 其余）。返回档位键
//——$r() 须编译期字面量、禁动态拼接，符号映射在 UI 侧（WorkspaceListRows.iconOf）
export function workspaceIconTierOf(name: string, kind: string): string {
  const ext: string = extOfWorkspaceName(name);
  if (ext === 'pdf') {
    return 'pdf';
  }
  if (SHEET_EXTS.indexOf(ext) >= 0) {
    return 'sheet';
  }
  if (ARCHIVE_EXTS.indexOf(ext) >= 0) {
    return 'archive';
  }
  if (AUDIO_EXTS.indexOf(ext) >= 0) {
    return 'audio';
  }
  if (VIDEO_EXTS.indexOf(ext) >= 0) {
    return 'video';
  }
  if (kind === 'image') {
    return 'image';
  }
  if (kind === 'text') {
    return 'text';
  }
  return 'file';
}

// MIME 按扩展名派生（模型写入与用户上传两路统一走本函数；无命中兜底空串——先例口径
// docMime / imageOutMime，本表按文件本体扩展名映射，不做编码转换）
export function workspaceMimeOf(name: string): string {
  const ext: string = extOfWorkspaceName(name);
  if (ext === 'pdf') {
    return 'application/pdf';
  }
  if (ext === 'docx') {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  if (ext === 'xlsx') {
    return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  }
  if (ext === 'xls') {
    return 'application/vnd.ms-excel';
  }
  if (ext === 'ofd') {
    return 'application/ofd';
  }
  if (ext === 'pptx') {
    return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
  }
  if (ext === 'png') {
    return 'image/png';
  }
  if (ext === 'jpg' || ext === 'jpeg') {
    return 'image/jpeg';
  }
  if (ext === 'webp') {
    return 'image/webp';
  }
  if (ext === 'gif') {
    return 'image/gif';
  }
  if (ext === 'bmp') {
    return 'image/bmp';
  }
  if (ext === 'heic' || ext === 'heif') {
    return 'image/heic';
  }
  if (TEXT_EXTS.indexOf(ext) >= 0) {
    return 'text/plain';
  }
  return '';
}

// ── 名称闸（模型入参安全边界）──
// 拒绝理由（中文，'' = 放行）：含路径成分（/ \ ..）/ 含空字节 / 纯空白 / 超长。只做拒绝
// 不做改写——write 路的清洗走 sanitizeWorkspaceName（写入侧防线），read 路的名称必须取自
// workspace_list 返回值，两者判据同源（本函数）
export function workspaceNameRejectReason(name: string): string {
  if (name.indexOf('/') >= 0 || name.indexOf('\\') >= 0) {
    return '文件名不能包含 / 或 \\';
  }
  if (name.indexOf('..') >= 0) {
    return '文件名不能包含 ..';
  }
  if (name.indexOf('\0') >= 0) {
    return '文件名包含非法字符';
  }
  if (name.trim() === '') {
    return '文件名不能为空';
  }
  if (name.length > WORKSPACE_NAME_MAX_CHARS) {
    return '文件名超过 ' + WORKSPACE_NAME_MAX_CHARS + ' 个字符的上限';
  }
  return '';
}

// 目录路径闸（与文件名闸两层分工）：dir 是相对工作区根的 / 分隔逻辑路径，'' = 放行即根
// 目录。与文件名闸的唯一差异点 = / 在 dir 语境是合法分隔符；段内判据沿用名称闸族（\ ..
// \0 纯空白超长全拒），另加两条结构性规则：①空段拒（首尾 / 与连续 //——放行会造成
// a/./b 与 a/b 两串指同目录，逻辑路径失稳）；②. 整段拒（路径语义保留字，与 .. 同族）。
// 只做拒绝不做清洗（与名称闸的分工：显示名有 sanitize 兜底改写是因为上传路名来自外部
// 不可控；dir 只来自模型入参与本域工具，全部过闸后才触 IO——再建清洗会引入「回执目录 ≠
// 落库目录」的漂移第二面）
export function workspaceDirRejectReason(dir: string): string {
  if (dir === '') {
    return '';
  }
  if (dir.indexOf('\\') >= 0) {
    return '目录路径不能包含 \\';
  }
  if (dir.indexOf('..') >= 0) {
    return '目录路径不能包含 ..';
  }
  if (dir.indexOf('\0') >= 0) {
    return '目录路径包含非法字符';
  }
  if (dir.length > WORKSPACE_DIR_MAX_CHARS) {
    return '目录路径超过 ' + WORKSPACE_DIR_MAX_CHARS + ' 个字符的上限';
  }
  const segments: string[] = dir.split('/');
  if (segments.length > WORKSPACE_DIR_MAX_DEPTH) {
    return '目录路径超过 ' + WORKSPACE_DIR_MAX_DEPTH + ' 层的深度上限';
  }
  for (const seg of segments) {
    if (seg === '') {
      return '目录路径不能包含连续或首尾的 /';
    }
    if (seg === '.') {
      return '目录路径不能包含 . 段';
    }
    if (seg.trim() === '') {
      return '目录路径不能包含空白段';
    }
    if (seg.length > WORKSPACE_NAME_MAX_CHARS) {
      return '目录路径的单个名称超过 ' + WORKSPACE_NAME_MAX_CHARS + ' 个字符的上限';
    }
    for (const ch of seg) {
      const code: number = ch.charCodeAt(0);
      if (code < 0x20 || code === 0x7F) {
        return '目录路径包含非法字符';
      }
    }
  }
  return '';
}

// ── 助手默认目录派生与 dir 入参归一（目录形态恒 assistants/<id> 纯函数派生，DB 零升版；
//    消费方 = ToolWorkspace 十件执行器缺省接线）──
// 助手默认目录：assistantId 空串或纯空白 → ''（回退根目录——assistantId 理论恒在场但值源
// 是 RunIdentity 快照，空值回退比崩溃好；system 作用域恒 '' = 落根）；否则
// 'assistants/<id>'。目录懒建复用写入链 ensureWorkspaceDir 链（零新代码）
export function defaultWorkspaceDirForAssistant(assistantId: string): string {
  if (assistantId.trim() === '') {
    return '';
  }
  return WORKSPACE_ASSISTANT_DIR_ROOT + '/' + assistantId;
}

// dir 入参归一（十件定位类工具缺省语义的统一入口，闸之前插）：trim 后空串（缺省）→ 助手
// 默认文件夹；'/' → ''（根的字面形态归一——存储层 dir 恒无 '/' 字面，根恒 ''，闸函数与
// 库内数据零改动）；其余原样返回（后续照旧过 workspaceDirRejectReason）。检索两件
//（glob/grep）不经本函数——检索缺省 = 整个工作区，「跨目录找东西」语义不参与缺省切换
export function normalizeWorkspaceDirParam(rawDir: string, assistantId: string): string {
  const trimmed: string = rawDir.trim();
  if (trimmed === '') {
    return defaultWorkspaceDirForAssistant(assistantId);
  }
  if (trimmed === '/') {
    return '';
  }
  return trimmed;
}

// 助手文件夹判别与 id 提取（显示名反查的纯函数底座）：「前缀 assistants/ 且恰一段」——
// dir 正是 assistants/<id> 时命中；更深路径（assistants/<id>/子目录）与其它路径不命中。
// UI 两消费点（管理页文件夹段目录行卡与面包屑段名）经此反查助手名，失败回退原始目录名
export function isAssistantWorkspaceDir(dir: string): boolean {
  return assistantIdFromWorkspaceDir(dir) !== '';
}

export function assistantIdFromWorkspaceDir(dir: string): string {
  if (!dir.startsWith(WORKSPACE_ASSISTANT_DIR_ROOT + '/')) {
    return '';
  }
  const rest: string = dir.substring(WORKSPACE_ASSISTANT_DIR_ROOT.length + 1);
  if (rest === '' || rest.indexOf('/') >= 0) {
    return '';
  }
  return rest;
}

// 写入侧显示名清洗：非法字符（\/:*?"<>| 与控制符）替换为 _、连续点归位、超 80 字符截断、
// 空名兜底默认名。模型路 name 已过名称闸、上传路 picker 派生名原样——两路都经本函数收口，
// 保证落库显示名恒过名称闸（上传名不过闸 = 助手 read 永拒、write 同名清洗后另铸新名）。
// · 连续点归位：'..' 过不了名称闸，落库后助手永远读不到——2 个以上连续点折叠为 1 个
//  （'报告..md' → '报告.md'，扩展名保留；名称闸先于本函数拒绝 '..'，本规则只对上传路生效）。
// · 超 80 截断不劈代理对：截点前一码元为高代理时退一格——孤代理会污染 UI 显示与后续名称匹配
export function sanitizeWorkspaceName(name: string): string {
  let cleaned: string = '';
  for (const ch of name) {
    const code: number = ch.charCodeAt(0);
    if ('\\/:*?"<>|'.indexOf(ch) >= 0 || code < 0x20 || code === 0x7F) {
      cleaned += '_';
    } else {
      cleaned += ch;
    }
  }
  cleaned = cleaned.replace(/\.{2,}/g, '.');
  cleaned = cleaned.trim();
  if (cleaned === '') {
    return '未命名文件.txt';
  }
  if (cleaned.length > WORKSPACE_NAME_MAX_CHARS) {
    let cut: number = WORKSPACE_NAME_MAX_CHARS;
    const prev: number = cleaned.charCodeAt(cut - 1);
    if (prev >= 0xD800 && prev <= 0xDBFF) {
      cut -= 1;
    }
    cleaned = cleaned.substring(0, cut);
  }
  return cleaned;
}

// ── 文件名与路径派生（应用侧单源——模型只给显示名，物理名恒由此铸造）──
// 物理文件名：<fileId>.<ext>（无扩展名 = 裸 fileId；fileId 由 WorkspaceDb 铸 UUID）
export function workspaceFileName(fileId: string, ext: string): string {
  return ext === '' ? fileId : fileId + '.' + ext;
}

// 相对路径（入库红线：localPath 只存相对 filesDir 的 workspace/[dir段…/]<fileId>.<ext>，
// 禁绝对路径——与附件域 relativeAttachPath 同口径；dir 为 '' 时单层平铺 = 既有形态）
export function relativeWorkspacePath(dir: string, fileName: string): string {
  return WORKSPACE_DIR_NAME + (dir === '' ? '' : '/' + dir) + '/' + fileName;
}

// picker uri 尾段显示名提取（decode 后带扩展名才可信；取不到/无扩展名兜底 fallback
// ——与 AttachmentPickCtrl.pickerFileName 同形，该件为模块私有不可 import，本域自持）
export function uriDisplayName(uri: string, fallback: string): string {
  const tail: string = uri.substring(uri.lastIndexOf('/') + 1);
  try {
    const decoded: string = decodeURIComponent(tail);
    if (decoded !== '' && decoded !== '/' && decoded.indexOf('.') > 0) {
      return decoded;
    }
  } catch {
    // 非法编码走兜底
  }
  return fallback;
}

// 显示名拆分（序号避重用：'报告' + 'pdf'；无扩展名 ext = ''）
interface WorkspaceNameExt {
  base: string;
  ext: string;
}

function splitNameExt(name: string): WorkspaceNameExt {
  const dot: number = name.lastIndexOf('.');
  if (dot <= 0 || dot >= name.length - 1) {
    return { base: name, ext: '' };
  }
  return { base: name.substring(0, dot), ext: name.substring(dot + 1) };
}

// 上传同名自动追加序号（「报告.pdf」→「报告(2).pdf」→「报告(3).pdf」；取现有最大序号 +1，
// 同序号被占则递增至空闲——existing = 现存全部显示名；入参名不在 existing 时原样返回）
export function dedupeWorkspaceName(name: string, existing: string[]): string {
  if (existing.indexOf(name) < 0) {
    return name;
  }
  const parts: WorkspaceNameExt = splitNameExt(name);
  const dotSuffix: string = parts.ext === '' ? '' : '.' + parts.ext;
  let seq: number = 2;
  while (existing.indexOf(parts.base + '(' + seq + ')' + dotSuffix) >= 0) {
    seq++;
  }
  return parts.base + '(' + seq + ')' + dotSuffix;
}

// 截短防劈（cut 点两避）：高代理高位退格防孤代理（sanitizeWorkspaceName 截断同款判据）；
// hasExt 时尾点退格防拼回「名..ext」连续点（sanitize 已折叠连续点，base 内点至多单挂，
// 退一格即净且新尾必非代理高位——代理对相邻、点非低代理）。base 首字符为点时 ext 必空
//（splitNameExt 的 dot≤0 判据），尾点退格不至负
function cutBaseForSuffix(name: string, cut: number, hasExt: boolean): string {
  if (hasExt && name.charAt(cut - 1) === '.') {
    cut -= 1;
  }
  const prev: number = name.charCodeAt(cut - 1);
  if (prev >= 0xD800 && prev <= 0xDBFF) {
    cut -= 1;
  }
  return name.substring(0, cut);
}

// 上传显示名收口（单源）：预留避重后缀位先截短 base（6 = '(N)' 上限宽，序号受件数闸
// 约束 4 位封顶），避重一次成型、无第二道截回——原「sanitize → 避重 → 越线截回」三段链
// 的截回可把「贴 80 既有名 + (2)」截回还原撞名原名（name 列无唯一约束，落库即同目录同名
// 双行恒二义）；ext 病态超长（>73 字符）预算放不下 base 时整名截短（ext 尾部牺牲）。出口
// 恒 ≤ 80 且不在 existing；短名不撞名时逐字透传
export function workspaceUploadDisplayName(rawName: string, existing: string[]): string {
  const cleaned: string = sanitizeWorkspaceName(rawName);
  const parts: WorkspaceNameExt = splitNameExt(cleaned);
  const dotSuffix: string = parts.ext === '' ? '' : '.' + parts.ext;
  // 预算 = 80 − 6 − 后缀宽：候选 ≤ 74，避重最坏 +6 仍 ≤ 80
  const budget: number = WORKSPACE_NAME_MAX_CHARS - 6 - dotSuffix.length;
  let candidate: string;
  if (budget >= 1) {
    const base: string = parts.base.length > budget ?
      cutBaseForSuffix(parts.base, budget, parts.ext !== '') : parts.base;
    candidate = base + dotSuffix;
  } else {
    // 该形态不拼后缀，无尾点风险
    candidate = cleaned.length > WORKSPACE_NAME_MAX_CHARS - 6 ?
      cutBaseForSuffix(cleaned, WORKSPACE_NAME_MAX_CHARS - 6, false) : cleaned;
  }
  return dedupeWorkspaceName(candidate, existing);
}

// ── 三闸判定（模型写与用户上传共用总量两闸；单件闸分路传入）──
// 拒绝理由（中文，'' = 放行）：单件超限 / 件数满 / 总量满；超限文案指向清理路径（P0-1）
export function workspaceWriteGateReason(sizeBytes: number, count: number,
  totalBytes: number): string {
  if (sizeBytes > WORKSPACE_WRITE_MAX_BYTES) {
    return '单个文件超过 ' + formatWorkspaceSize(WORKSPACE_WRITE_MAX_BYTES) +
      ' 的上限，无法保存。请缩短内容后重试。';
  }
  return workspaceCapacityReason(sizeBytes, count, totalBytes);
}

// 容量两闸（写入与上传共用）：件数满 / 总量满（新建路才需要——覆盖写不增件数，但总量
// 会随新内容变化，调用方按「新总量 = 现总量 − 旧 size + 新 size」折算后传 totalBytes）
export function workspaceCapacityReason(sizeBytes: number, count: number,
  totalBytes: number): string {
  if (count >= WORKSPACE_MAX_COUNT) {
    return '工作区已满 ' + WORKSPACE_MAX_COUNT + ' 个文件，无法保存。请在 设置 → 文件工作区 中删除一些文件。';
  }
  if (totalBytes + sizeBytes > WORKSPACE_MAX_TOTAL_BYTES) {
    return '工作区总大小将超过 ' + formatWorkspaceSize(WORKSPACE_MAX_TOTAL_BYTES) +
      ' 的上限，无法保存。请在 设置 → 文件工作区 中删除一些文件。';
  }
  return '';
}

// 上传闸：单件大小（10MB）。'' = 放行。★ 类型闸已放宽——三类白名单外可入（kind 落 other
// 档：可管理、不可预览）：下载产物可为 .zip/.bin 等任意类型，上传路同口径放行（原「三类
// 分外拒收」拦截与下载语义死锁，决明拍板放宽）；name 形参保留供调用方日志与文案取用
export function workspaceUploadGateReason(name: string, sizeBytes: number): string {
  if (sizeBytes > WORKSPACE_UPLOAD_MAX_BYTES) {
    return '文件超过 ' + formatWorkspaceSize(WORKSPACE_UPLOAD_MAX_BYTES) +
      ' 的上限，无法上传。';
  }
  return '';
}

// ── 展示与回执格式化 ──
// 大小格式化（与 AttachmentUtil.formatFileSize 同形同值：B/KB/MB/GB 四档两位小数——
// 工作区总量闸升 1GB 后闸文案与统计行需要 GB 档，附件域同值先例）
export function formatWorkspaceSize(size: number): string {
  if (size < 1024) {
    return size + ' B';
  }
  if (size < 1024 * 1024) {
    return (size / 1024).toFixed(2) + ' KB';
  }
  if (size < 1024 * 1024 * 1024) {
    return (size / (1024 * 1024)).toFixed(2) + ' MB';
  }
  return (size / (1024 * 1024 * 1024)).toFixed(2) + ' GB';
}

// 回执时间格式化（'2026-10-01 14:30'——本地时区分）
export function formatWorkspaceTime(ms: number): string {
  const d: Date = new Date(ms);
  const pad = (n: number): string => n < 10 ? '0' + n : '' + n;
  return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' +
    pad(d.getHours()) + ':' + pad(d.getMinutes());
}

// 来源标签（UI 与回执共用单源；'recovered' = 对账补录的磁盘恢复件档）
export function sourceLabel(source: string): string {
  if (source === WORKSPACE_SOURCE_USER) {
    return '我上传';
  }
  if (source === WORKSPACE_SOURCE_DOWNLOAD) {
    return '下载';
  }
  if (source === WORKSPACE_SOURCE_RECOVERED) {
    return '恢复';
  }
  return '助手保存';
}

// 类型中文名（read 回执「不能读取内容」文案用）：'image' → 图片 / 'doc' → 文档 / 其余
//（'other' 档，随类型闸放宽新增）→ 其他类型——原读口二元式把 'other' 一并说成「文档」
// = 报给模型的类型名失实
export function workspaceKindLabel(kind: string): string {
  if (kind === 'image') {
    return '图片';
  }
  if (kind === 'doc') {
    return '文档';
  }
  return '其他类型';
}

// 可发送类型过滤（「重发文件」面板工作区段，2026-10-31 附件重发笔立）：kind 正向白名单三值
// 放行——dir 行（行类型位非文件分类）与 other 档不列（附件入列的类型闸本会拦，面板先滤免得
// 点了才报错）；白名单外未知值一律拒（fail-closed，禁「非 dir 非 other 即放」的反向判法）
export function workspaceSendableKind(kind: string): boolean {
  return kind === 'image' || kind === 'text' || kind === 'doc';
}

// 重发面板工作区段最终可发送判定（★ 2026-10-31「重发大文档叠加降级与两小修」笔 §四-4 增）：
// 在 kind 白名单之上再滤「无扩展名」件。理由 = 附件入列的类型判定靠扩展名（classifyByName），
// 无扩展名件列出来点了恒报「暂仅支持图片、文本与文档类附件」，属面板先滤免得点了才报错的同
// 一条纪律。扩展名判据与 AttachmentUtil.extOf(name) === '' 同义（点存在且不在末位）——本件
// 零 import 是断言整文件拷贝直跑的前提（490 组），故不复引 extOf，两处同义由 490 组真值表守。
export function workspaceReissueSendable(kind: string, name: string): boolean {
  const dot: number = name.lastIndexOf('.');
  return workspaceSendableKind(kind) && dot >= 0 && dot < name.length - 1;
}

// 回执通用收口（超预算截头保留 + 尾标注明——照 clipToolResult 尾标形态；list 回执自带
// 逐行明细的更细粒度收口，本函数兜底）
export function clipWorkspaceReply(text: string, budget: number): string {
  if (text.length <= budget) {
    return text;
  }
  return text.substring(0, budget) + '\n[内容过长已截断]';
}

// ── 行与回执数据形态 ──
// 工作区文件行（workspace_files 表全列投影；id = fileId 与物理文件名同源）
export interface WorkspaceFileRow {
  id: string;
  name: string; // 显示名（模型给的 name / 用户原文件名，非法字符已替换）
  dir: string; // 相对工作区根的 / 分隔路径串，'' = 根（同时是物理目录结构）
  kind: string; // 'image' | 'text' | 'doc' | 'other' | 'dir'（'dir' = 行类型判别位非文件分类）
  mime: string;
  size: number;
  localPath: string; // 相对 filesDir（workspace/[dir段…/]<fileId>.<ext>，红线：禁绝对路径）
  source: string; // 'user' | 'assistant'（含导入件）| 'download' | 'recovered'
  conversationId: string; // 追溯（模型写入路填充；上传路恒 ''；不级联不置空）
  ownerAssistantId: string; // 追溯（同上；助手删除后 id 悬空仅作追溯）
  createdAt: number;
  updatedAt: number;
  // 目录行自定义序（★ 只目录行消费——文件行恒 0 不参与任何排序。写点单源 = WorkspaceDb
  //「目录排序域」：UI 拖拽落定整组回写 0..n-1 / 目录行铸造与跨层移动取父层 max+1 落层底；
  // 存量 0 = 名称字典序兜底 = 升级前列表序零漂移）
  sortOrder: number;
}

// 列表回执简报行（list 工具与管理页统计共用形态——不含 localPath 等 IO 面字段）
export interface WorkspaceListBrief {
  name: string;
  dir: string;
  kind: string;
  size: number;
  createdAt: number;
  source: string;
}

export function briefFromRow(row: WorkspaceFileRow): WorkspaceListBrief {
  return { name: row.name, dir: row.dir, kind: row.kind, size: row.size,
    createdAt: row.createdAt, source: row.source };
}

// 目录条目简报（list 按目录一层列举的子文件夹行；fileCount = 该子目录的直接子文件数；
// folderCount = 直接子文件夹数〔显式目录行与文件路径派生段按名去重全集〕——UI 文件夹行
// 副标题三态消费，AI list 回执措辞不消费本字段口径不动）
export interface WorkspaceDirBrief {
  name: string;
  fileCount: number;
  folderCount: number;
}

// 子文件夹下层段登记（folderCount 去重集写入口）：文件路径派生段与显式目录行两路共用——
// 同名段两路并存（用户在隐式文件夹下建显式同名文件夹）只计一次
function addSubSegName(map: Map<string, Set<string>>, seg: string, subName: string): void {
  const set: Set<string> | undefined = map.get(seg);
  if (set === undefined) {
    map.set(seg, new Set<string>([subName]));
    return;
  }
  set.add(subName);
}

// 行构建（模型写入 / 上传 / 下载与导入多路共用）：物理名与路径由此铸造，显示名须先过
// sanitize。kindFallback = classify 回 ''（扩展名不在白名单）时的兜底档：模型写入路默认
// 'text'（写入的恒是文本——无扩展名显示名按文本可预览）；上传与下载路传 'other'（类型闸
// 放宽后三类外可入 other 档：可管理、不可预览）。
// ★ dir 追加在参数列表**最末位**（kindFallback 之后——禁插中间）：既有调用以第 8 位置
// 实参传 kindFallback（HttpBinary 两壳 + assert-tool-domain 两用例），插中间会把 'other'
// 静默解释为 dir 造成行指向 workspace/other/ 而物理文件在根的数据错位；追加最末后这四处
// 缺省落根零改动
export function buildWorkspaceRow(fileId: string, displayName: string, size: number,
  source: string, conversationId: string, ownerAssistantId: string, now: number,
  kindFallback: string = 'text', dir: string = ''): WorkspaceFileRow {
  const ext: string = extOfWorkspaceName(displayName);
  const fileName: string = workspaceFileName(fileId, ext);
  const kind: string = classifyWorkspaceName(displayName);
  return {
    id: fileId,
    name: displayName,
    dir: dir,
    kind: kind === '' ? kindFallback : kind,
    mime: workspaceMimeOf(displayName),
    size: size,
    localPath: relativeWorkspacePath(dir, fileName),
    source: source,
    conversationId: conversationId,
    ownerAssistantId: ownerAssistantId,
    createdAt: now,
    updatedAt: now,
    sortOrder: 0 // 文件行恒 0——自定义序只目录行消费
  };
}

// 目录行构建（mkdir 显式铸造 / write·import 隐式铸造 / 对账登记三路共用）：kind='dir'、
// mime 空、size=0、localPath=目录相对路径（workspace/[段…] 无尾斜杠——对账的死行判定
// accessSync 对目录同样生效，物理目录亡即行删）。段名来自受闸 dir（mkdir/隐式）或物理目录
// 名照录（对账登记——外部塞的怪名目录可见可删）。★ 新铸行 sortOrder 缺省 0，**父层落底序
// 由存储层铸造点回填**（nextWorkspaceDirOrder——本函数不碰 db 保持纯函数；WorkspaceDb 两
// 铸造点各一行赋值）
export function buildWorkspaceDirRow(id: string, segName: string, parentDir: string,
  source: string, conversationId: string, ownerAssistantId: string,
  now: number): WorkspaceFileRow {
  return {
    id: id,
    name: segName,
    dir: parentDir,
    kind: WORKSPACE_KIND_DIR,
    mime: '',
    size: 0,
    localPath: relativeWorkspacePath(parentDir, segName),
    source: source,
    conversationId: conversationId,
    ownerAssistantId: ownerAssistantId,
    createdAt: now,
    updatedAt: now,
    sortOrder: 0
  };
}

// 目录行判定（消费方分流单源——统计/三闸/管理页/上传匹配按「排除」、文件夹派生按「读」）
export function isWorkspaceDirRow(row: WorkspaceFileRow): boolean {
  return row.kind === WORKSPACE_KIND_DIR;
}

// 目录链逐段冲突检查：dir 的**每个前缀段** (父段, 段名) 撞文件行（kind != 'dir'）即拒——
// 拦「文件行撞目录路径段」通路（根有文件 a 再 write dir='a'、mkdir 'a/b' 的中间段 a——该
// 通路目录行尚不存在，行级查重够不着，必须逐段查文件行）。段已有目录行 = 已入账放行。
// 纯函数吃全表行集（行集读取上限有界一次查，write/import/mkdir 三路共用单源）；'' = 放行
export function workspaceDirChainReject(rows: WorkspaceFileRow[], dir: string): string {
  if (dir === '') {
    return '';
  }
  const segs: string[] = dir.split('/');
  let parent: string = '';
  for (const seg of segs) {
    for (const row of rows) {
      if (row.dir === parent && row.name === seg && !isWorkspaceDirRow(row)) {
        return '目录路径「' + dir + '」无法使用，其中「' + seg +
          '」与所在位置的文件同名。请换一个目录路径，或先处理同名文件。';
      }
    }
    parent = parent === '' ? seg : parent + '/' + seg;
  }
  return '';
}

// ── 列表排序方式（六档常量与解析单源——偏好键值 / 管理页「更多」菜单子菜单项 / 管理页
//    与 list 工具解析全走本段）──
// 六档语义（两段联动）：custom = 自定义（默认，现状零回归——文件夹行按拖拽自定义序、
// 文件行按最近更新在前）；name = 两段皆名称字典序；timeDesc / timeAsc = 文件夹行按创建
// 时间、文件行按最近更新时间 降/升；sizeDesc / sizeAsc = 文件夹行按子树合计、文件行按
// 自身大小 降/升。纯显示层换序——DB 查询排序键与成员集不动（排序键不构成任何 LIMIT
// 成员集判据）
export const WS_SORT_CUSTOM: string = 'custom';
export const WS_SORT_NAME: string = 'name';
export const WS_SORT_TIME_DESC: string = 'timeDesc';
export const WS_SORT_TIME_ASC: string = 'timeAsc';
export const WS_SORT_SIZE_DESC: string = 'sizeDesc';
export const WS_SORT_SIZE_ASC: string = 'sizeAsc';

// 偏好值解析（写入侧与读取侧共用）：六值白名单外的脏值（老备份 / 手工改值 / 未来降版残留）
// 一律回 'custom' 默认行为——解析面零崩溃、零未知档漂移
export function resolveWorkspaceSortMode(value: string | undefined): string {
  if (value === WS_SORT_NAME || value === WS_SORT_TIME_DESC || value === WS_SORT_TIME_ASC ||
    value === WS_SORT_SIZE_DESC || value === WS_SORT_SIZE_ASC) {
    return value;
  }
  return WS_SORT_CUSTOM;
}

// 名称字典序比较（码元序——与既有默认 sort() 及并列兜底语义一致）
function compareWorkspaceNames(a: string, b: string): number {
  return a < b ? -1 : (a > b ? 1 : 0);
}

// 目录段排序比较（六档；custom 分支 = 现状序逐字节等价）。键缺口兜底：无目录行的前缀
// 派生段（对账窗口短暂态）时间档按 0 参与、大小档按 0 参与；全部并列回落名称序
function compareWorkspaceDirSegs(a: string, b: string, dirRows: Map<string, WorkspaceFileRow>,
  dirBytes: Map<string, number>, sortMode: string): number {
  const rowA: WorkspaceFileRow | undefined = dirRows.get(a);
  const rowB: WorkspaceFileRow | undefined = dirRows.get(b);
  if (sortMode === WS_SORT_NAME) {
    return compareWorkspaceNames(a, b);
  }
  if (sortMode === WS_SORT_TIME_DESC || sortMode === WS_SORT_TIME_ASC) {
    const createdA: number = rowA === undefined ? 0 : rowA.createdAt;
    const createdB: number = rowB === undefined ? 0 : rowB.createdAt;
    if (createdA !== createdB) {
      return sortMode === WS_SORT_TIME_DESC ? createdB - createdA : createdA - createdB;
    }
    return compareWorkspaceNames(a, b);
  }
  if (sortMode === WS_SORT_SIZE_DESC || sortMode === WS_SORT_SIZE_ASC) {
    const bytesA: number = dirBytes.get(a) ?? 0;
    const bytesB: number = dirBytes.get(b) ?? 0;
    if (bytesA !== bytesB) {
      return sortMode === WS_SORT_SIZE_DESC ? bytesB - bytesA : bytesA - bytesB;
    }
    return compareWorkspaceNames(a, b);
  }
  // custom（现状）：sortOrder 升序 → 名称兜底
  const orderA: number = rowA === undefined ? 0 : rowA.sortOrder;
  const orderB: number = rowB === undefined ? 0 : rowB.sortOrder;
  if (orderA !== orderB) {
    return orderA - orderB;
  }
  return compareWorkspaceNames(a, b);
}

// 文件行排序比较（custom 不调用——保持调用方传入序 = query 的 updatedAt DESC 单一真源；
// 时间/大小档并列回落名称序）
function compareWorkspaceFileRows(a: WorkspaceFileRow, b: WorkspaceFileRow,
  sortMode: string): number {
  if (sortMode === WS_SORT_NAME) {
    return compareWorkspaceNames(a.name, b.name);
  }
  if (sortMode === WS_SORT_TIME_DESC || sortMode === WS_SORT_TIME_ASC) {
    if (a.updatedAt !== b.updatedAt) {
      return sortMode === WS_SORT_TIME_DESC ?
        b.updatedAt - a.updatedAt : a.updatedAt - b.updatedAt;
    }
    return compareWorkspaceNames(a.name, b.name);
  }
  if (a.size !== b.size) {
    return sortMode === WS_SORT_SIZE_DESC ? b.size - a.size : a.size - b.size;
  }
  return compareWorkspaceNames(a.name, b.name);
}

// 按目录一层拆分（list 语义核心——定序契约冻结）：子文件夹条目自**目录行直接取**
//（kind='dir' 且父目录 = dir——空目录与纯中间层目录天然可见，「list 不显示空文件夹」旧
// 语义废止），文件行前缀派生**保留为并集兜底**（对账未完成的窗口期目录行未补时 list 不缺
// 目录）。纯函数不碰 IO，行集由调用方一次查全表（行集读取上限有界）内存过滤——后代判定
// 用 startsWith 前缀比较，禁 SQL LIKE（dir 段合法含 % _，通配注入面）。子文件夹条目 =
// sortOrder 升序（目录行自定义序，写点单源 WorkspaceDb「目录排序域」），并列回落名称字典
// 序；存量目录行全 0 = 名称序 = 升级前回执逐字节零漂移。文件侧（briefs updatedAt 降序）与
// 调用方 in() 成员集面零改动——排序键不构成任何 LIMIT 成员集判据。sortMode 第三参缺省
// custom = 上述行为逐字节不变；非 custom 档目录侧走 compareWorkspaceDirSegs 模式键、文件侧
// 显式排序（custom 档不排 = 传入序）。大小档的文件夹子树合计在**本函数一次遍历内聚合**
//（needDirBytes 时按第一段累加——与 deriveWorkspaceSubtreeStats 同判据：含深层文件、目录行
// 不计；非大小档零额外开销）
export function deriveWorkspaceDirListing(rows: WorkspaceFileRow[], dir: string,
  sortMode: string = WS_SORT_CUSTOM): WorkspaceDirListing {
  const mode: string = resolveWorkspaceSortMode(sortMode);
  const fileRows: WorkspaceFileRow[] = [];
  const dirCount: Map<string, number> = new Map<string, number>();
  const dirBytes: Map<string, number> = new Map<string, number>();
  const prefix: string = dir === '' ? '' : dir + '/';
  const childDirNames: Set<string> = new Set<string>();
  // 目录行名单：本层目录行 (段名 → 行)；文件前缀派生的段名无目录行不入表，比较侧零档
  // 兜底（对账窗口与纯派生段名恒按名称档参与）
  const dirRows: Map<string, WorkspaceFileRow> = new Map<string, WorkspaceFileRow>();
  const needDirBytes: boolean = mode === WS_SORT_SIZE_DESC || mode === WS_SORT_SIZE_ASC;
  // ★ 每个直接子文件夹段的下层第一段名字集合（folderCount = 集合大小）——显式目录行与
  // 文件路径派生段两路登记、按名去重
  const subSegNames: Map<string, Set<string>> = new Map<string, Set<string>>();
  for (const row of rows) {
    if (isWorkspaceDirRow(row)) {
      if (row.dir === dir) {
        childDirNames.add(row.name);
        dirRows.set(row.name, row);
      } else if (row.dir.startsWith(prefix)) {
        // 显式目录行挂在某直接子文件夹段下（父路径去前缀后恰为一段）→ 该段 folderCount 位
        const rest: string = row.dir.substring(prefix.length);
        if (rest !== '' && rest.indexOf('/') < 0) {
          addSubSegName(subSegNames, rest, row.name);
        }
      }
      continue;
    }
    if (row.dir === dir) {
      fileRows.push(row);
      continue;
    }
    if (row.dir.startsWith(prefix)) {
      // 该目录下（或更深层）的文件——直接子文件夹段 = 去前缀后的第一段
      const rest: string = row.dir.substring(prefix.length);
      const seg: string = rest.split('/')[0];
      if (seg !== '') {
        childDirNames.add(seg);
      }
      if (rest.indexOf('/') < 0) {
        dirCount.set(seg, (dirCount.get(seg) ?? 0) + 1);
      } else {
        // 更深层文件的第一、二段 = 子文件夹 seg 与它的直接子段（隐式）→ folderCount 位
        const segs: string[] = rest.split('/');
        if (segs.length > 1 && segs[1] !== '') {
          addSubSegName(subSegNames, segs[0], segs[1]);
        }
      }
      if (needDirBytes) {
        dirBytes.set(seg, (dirBytes.get(seg) ?? 0) + row.size);
      }
    }
  }
  const dirNames: string[] = [];
  childDirNames.forEach((name: string): void => {
    dirNames.push(name);
  });
  dirNames.sort((a: string, b: string): number =>
    compareWorkspaceDirSegs(a, b, dirRows, dirBytes, mode));
  const dirs: WorkspaceDirBrief[] = dirNames.map((name: string): WorkspaceDirBrief => {
    const subSet: Set<string> | undefined = subSegNames.get(name);
    return { name: name, fileCount: dirCount.get(name) ?? 0,
      folderCount: subSet === undefined ? 0 : subSet.size };
  });
  if (mode !== WS_SORT_CUSTOM) {
    fileRows.sort((a: WorkspaceFileRow, b: WorkspaceFileRow): number =>
      compareWorkspaceFileRows(a, b, mode));
  }
  const briefs: WorkspaceListBrief[] = fileRows.map(briefFromRow);
  return { dirs: dirs, briefs: briefs };
}

// 目录一层列举结果（deriveWorkspaceDirListing 的返回形态）
export interface WorkspaceDirListing {
  dirs: WorkspaceDirBrief[];
  briefs: WorkspaceListBrief[];
}

// ── UI 层派生（管理页「文件夹 / 会话」双视图的纯函数底座；消费方 = WorkspaceManagePage
//    与 WorkspaceSessionView；零 import 纪律不变）──
// 会话聚合分组（'' = 未关联会话，恒排末位——覆盖上传件与恢复件两类来源；lastAt = 组内
// 最大 updatedAt）
export interface WorkspaceSessionGroup {
  conversationId: string;
  fileCount: number;
  bytes: number;
  lastAt: number;
}

// 按 conversationId 归组（★ 目录行硬排除——目录行 conversationId 恒追溯性空值但形态上是
// 行，不过滤会让「未关联会话」组件数虚高、文件夹混进件数口径）；非空 id 组按 lastAt 降序，
// '' 组无论时间恒末位；空表 → []
export function deriveWorkspaceSessionGroups(rows: WorkspaceFileRow[]): WorkspaceSessionGroup[] {
  const map: Map<string, WorkspaceSessionGroup> = new Map<string, WorkspaceSessionGroup>();
  for (const row of rows) {
    if (isWorkspaceDirRow(row)) {
      continue;
    }
    let group: WorkspaceSessionGroup | undefined = map.get(row.conversationId);
    if (group === undefined) {
      group = { conversationId: row.conversationId, fileCount: 0, bytes: 0, lastAt: row.updatedAt };
      map.set(row.conversationId, group);
    }
    group.fileCount++;
    group.bytes += row.size;
    if (row.updatedAt > group.lastAt) {
      group.lastAt = row.updatedAt;
    }
  }
  const named: WorkspaceSessionGroup[] = [];
  let unlinked: WorkspaceSessionGroup | undefined = undefined;
  map.forEach((group: WorkspaceSessionGroup): void => {
    if (group.conversationId === '') {
      unlinked = group;
    } else {
      named.push(group);
    }
  });
  named.sort((a: WorkspaceSessionGroup, b: WorkspaceSessionGroup): number => b.lastAt - a.lastAt);
  if (unlinked !== undefined) {
    named.push(unlinked);
  }
  return named;
}

// 会话内文件派生：只含该会话件（conversationId === '' 取未关联组）、按 updatedAt 降序；
// 目录行同排除
export function deriveWorkspaceSessionFiles(rows: WorkspaceFileRow[],
  conversationId: string): WorkspaceFileRow[] {
  return rows.filter((row: WorkspaceFileRow): boolean =>
    !isWorkspaceDirRow(row) && row.conversationId === conversationId)
    .sort((a: WorkspaceFileRow, b: WorkspaceFileRow): number => b.updatedAt - a.updatedAt);
}

// 上一级目录（'' 根回根；'a/b' → 'a'；'a' → ''）
export function workspaceParentDir(dir: string): string {
  const slash: number = dir.lastIndexOf('/');
  return slash < 0 ? '' : dir.substring(0, slash);
}

// 面包屑段数组（含根段「工作区」；'' 根 = 单段）——段数组形态（可点面包屑需逐段跳转
// 目标，整串文本不再够用）
export function workspaceDirSegments(dir: string): string[] {
  if (dir === '') {
    return ['工作区'];
  }
  return ['工作区'].concat(dir.split('/'));
}

// 面包屑段跳转目标（段下标含根段：0 = 回根 → ''；i ≥ 1 = 前 i 段 join——与 dir 段序同源；
// dir 空时任何段下标均回根）
export function workspaceDirJumpTarget(dir: string, segIndex: number): string {
  if (segIndex <= 0 || dir === '') {
    return '';
  }
  return dir.split('/').slice(0, segIndex).join('/');
}

// 当前目录直接文件（与 folders 单源对齐的薄函数：deriveWorkspaceDirListing 的文件集形态
// 是 WorkspaceListBrief[]〔list 工具回执简报〕，UI 预览与动作需 localPath 等全列，故在此补
// 整行版——过滤与排序逻辑只此一份，两形态各自派生不重复）；sortMode 缺省 custom = 按
// updatedAt 降序（现状零漂移），其余档走 compareWorkspaceFileRows（行集成员不变，仅换序）
export function workspaceFilesInDir(rows: WorkspaceFileRow[], dir: string,
  sortMode: string = WS_SORT_CUSTOM): WorkspaceFileRow[] {
  const mode: string = resolveWorkspaceSortMode(sortMode);
  const files: WorkspaceFileRow[] = rows.filter((row: WorkspaceFileRow): boolean =>
    !isWorkspaceDirRow(row) && row.dir === dir);
  if (mode === WS_SORT_CUSTOM) {
    return files.sort((a: WorkspaceFileRow, b: WorkspaceFileRow): number =>
      b.updatedAt - a.updatedAt);
  }
  return files.sort((a: WorkspaceFileRow, b: WorkspaceFileRow): number =>
    compareWorkspaceFileRows(a, b, mode));
}

// 段序树形比较（移动目标排序单源）：按 '/' 分段逐段比较、前缀短者在前——父目录恒紧邻其
// 子树之前；纯字典序在名字含 '.'/'-' 等码位低于 '/' 的字符时会把兄弟插进父子之间（如 a、
// a-b、a/c），层级读法会错从属（消费方 = 下钻逐层列表排序 + 目标集次序）
function compareWorkspaceDirPaths(a: string, b: string): number {
  const sa: string[] = a === '' ? [] : a.split('/');
  const sb: string[] = b === '' ? [] : b.split('/');
  const n: number = Math.min(sa.length, sb.length);
  for (let i = 0; i < n; i++) {
    if (sa[i] !== sb[i]) {
      return sa[i] < sb[i] ? -1 : 1;
    }
  }
  return sa.length - sb.length;
}

// 移动条目自身路径（根/非根两态通式——陷阱：fromDir + '/' + name 在 fromDir === '' 时得
// '/name'，与 dir 值 'name' 不等 ⇒ 根级文件夹的自身与其子树会漏排除；消费方 =
// deriveWorkspaceMoveTargets 与工作区移动面板宿主）
export function workspaceMoveSelfPath(fromDir: string, name: string): string {
  return fromDir === '' ? name : fromDir + '/' + name;
}

// 移动目标派生：候选 = 根（''，恒首位——段序树形序天然最前）+ 目录行完整路径（含空目录
//——原「全表 dir 去重」不含无文件目录）∪ 文件行 dir 去重；排除当前位置与「自身路径及其
// 前缀子树」（自身路径算式 = workspaceMoveSelfPath 单源）；空表也返回根（fromDir 已是根
// 则空——无处可移）。排序 = 段序树形序（比较器见上）
export function deriveWorkspaceMoveTargets(rows: WorkspaceFileRow[], fromDir: string,
  name: string): string[] {
  const selfPath: string = workspaceMoveSelfPath(fromDir, name);
  const targets: Set<string> = new Set<string>();
  targets.add('');
  for (const row of rows) {
    if (isWorkspaceDirRow(row)) {
      targets.add(joinDirName(row.dir, row.name));
    } else if (row.dir !== '') {
      targets.add(row.dir);
    }
  }
  const list: string[] = [];
  targets.forEach((target: string): void => {
    if (target === fromDir || target === selfPath ||
      target.startsWith(selfPath + '/')) {
      return;
    }
    list.push(target);
  });
  list.sort(compareWorkspaceDirPaths);
  return list;
}

// 移动面板下钻层子目录（逐层进入式选目标）：全目录集里 parent === dir 且非隐藏分支（移动
// 中的文件夹自身路径——不从树里出现，其子树随之不可达；文件移动传 ''）的完整路径，段序
// 升序（与页面文件夹列表同序）。dir 根段 '' 表工作区根层
export function deriveWorkspaceDrillChildren(allDirs: string[], dir: string,
  hiddenPrefix: string): string[] {
  const children: string[] = [];
  for (const p of allDirs) {
    if (p !== hiddenPrefix && workspaceParentDir(p) === dir) {
      children.push(p);
    }
  }
  children.sort(compareWorkspaceDirPaths);
  return children;
}

// 下钻行尾「＞」判据（有子文件夹的行才显——与 deriveWorkspaceDrillChildren 同一过滤：隐藏
// 分支不计；空文件夹不显箭头、仍可进入后按底部键落点）
export function workspaceDirHasDrillChild(allDirs: string[], dir: string,
  hiddenPrefix: string): boolean {
  for (const p of allDirs) {
    if (p !== hiddenPrefix && workspaceParentDir(p) === dir) {
      return true;
    }
  }
  return false;
}

// 子树统计（删文件夹确认弹窗的件数与合计口径）
export interface WorkspaceFolderStats {
  fileCount: number;
  bytes: number;
}

// 前缀 dir + '/' + name 下的文件计数与字节求和（根下属 = name 前缀——fromDir '' 时前缀就是
// 段名本身）；目录行不计件数不占容量；startsWith(prefix + '/') 判据保证兄弟目录不误收
//（'资料' 不吃 '资料夹'）；空命中返回 {0, 0}
export function deriveWorkspaceSubtreeStats(rows: WorkspaceFileRow[], dir: string,
  name: string): WorkspaceFolderStats {
  const prefix: string = dir === '' ? name : dir + '/' + name;
  const stats: WorkspaceFolderStats = { fileCount: 0, bytes: 0 };
  for (const row of rows) {
    if (isWorkspaceDirRow(row)) {
      continue;
    }
    if (row.dir === prefix || row.dir.startsWith(prefix + '/')) {
      stats.fileCount++;
      stats.bytes += row.size;
    }
  }
  return stats;
}

// ── 工具回执组装域已外迁 common/WorkspaceReply.ets（composeWorkspace* 回执族 /
//   workspaceDocMetaLine / workspaceParseErrorReply / 覆盖注记族整段迁出；该件单向 import
//   本件，消费方 ToolWorkspace / ToolCodeExec / HttpBinary / WorkspaceDb 族 /
//   WorkspaceEditUtil 改自新件引）──

// 目录 + 段名拼接（rename/move/delete 回执里文件夹语境的完整路径串；dir = '' 时裸段名；
// 回执侧消费已随 WorkspaceReply.ets 外迁，本件保留自用与外部消费）
export function joinDirName(dir: string, name: string): string {
  return dir === '' ? name : dir + '/' + name;
}
