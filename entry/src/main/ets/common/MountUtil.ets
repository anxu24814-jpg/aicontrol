// 文件夹挂载域纯函数单源（模式位映射 / 名称与路径派生 / 失效警示与失败文案 / 上限常量 /
// 浏览页排序与行键——全部无副作用纯函数）。
// ★ 零 import 纪律：本件刻意零 import（node 剥桩可直跑——assert-mount-domain 复制后直接
//   求值纯函数面，线上同一实现不断言副本）。因此 fileShare.OperationMode 模式位以字面量
//   **镜像**（值读自本机 SDK d.ts：READ=0b1 / WRITE=0b10 / CREATE=0b100 / DELETE=0b1000 /
//   RENAME=0b10000），镜像保真由断言钉住（改值即红）。
// · 模式位纪律：只读挂载 = READ 单授；读写挂载 = READ|WRITE 双授；**CREATE / DELETE /
//   RENAME 三位恒不授**——官方明示三位仅支持临时授权，混进持久化掩码会被系统整条拒绝
//   （真机实锤：persist 报 PolicyErrorCode 1，文案曾误呈为「可能已达挂载数量上限」）。
//   新建文件无需 CREATE：父目录有 WRITE 即覆盖新建。
// · 不碰 store、不碰 UI，名称与状态文案单源在此。

// 应用层模式镜像（folder_mounts.mode 列值域；系统真值在授权模式位）
export const MOUNT_MODE_READ_ONLY: number = 0;
export const MOUNT_MODE_READ_WRITE: number = 1;

// 应用层挂载件数上限（先于系统条目上限触发可管理行为——达到即添加键置灰并说明，不赌系统数字）
export const MOUNT_MAX_COUNT: number = 8;

// 清单读取上限（防库内意外多行致无界读；正常路径件数由 MOUNT_MAX_COUNT 把守）
export const MOUNT_ROWS_READ_MAX: number = 64;

// 挂载名称长度上限（用户起的纯标签，与文件夹真名无关——不吃文件名约束，只防超长撑破卡面）
export const MOUNT_NAME_MAX_CHARS: number = 30;

// 模式位（镜像 fileShare.OperationMode 低两位，见文件头；CREATE 位不设常量——不在任何
// 持久化掩码里，设了反而是召回隐患）
const MOUNT_BIT_READ: number = 0b1;
const MOUNT_BIT_WRITE: number = 0b10;

// 模式 → 系统持久授权模式位（persist / revoke / check 三处共用本单源）
export function mountModeMask(mode: number): number {
  if (mode === MOUNT_MODE_READ_WRITE) {
    return MOUNT_BIT_READ | MOUNT_BIT_WRITE;
  }
  return MOUNT_BIT_READ;
}

// 模式中文档位（卡面与 toast 共用）
export function mountModeLabel(mode: number): string {
  return mode === MOUNT_MODE_READ_WRITE ? '读写' : '只读';
}

// 模式切换目标（只读 ↔ 读写两值互切）
export function mountOtherMode(mode: number): number {
  return mode === MOUNT_MODE_READ_WRITE ? MOUNT_MODE_READ_ONLY : MOUNT_MODE_READ_WRITE;
}

// 卡失效警示文案（仅失效态保留警示行——正常态状态行已退役、模式归卡头徽章；granted = 进页
// checkPersistentPermission 探测结果）
export function mountWarningLine(granted: boolean): string {
  return granted ? '' : '需重新授权';
}

// 挂载默认名（先剥 query 再取 URI 末段解码——选择器 URI 尾段可能带 query，带进默认名会
// 失真；空段/解码失败走 fallback——选择器选根目录等场景，名只是默认值用户可改）
export function mountNameFromUri(uri: string, fallback: string): string {
  const cut: number = uri.indexOf('?');
  const bare: string = cut >= 0 ? uri.substring(0, cut) : uri;
  const tail: string = bare.substring(bare.lastIndexOf('/') + 1);
  try {
    const decoded: string = decodeURIComponent(tail);
    if (decoded !== '' && decoded !== '/' && decoded !== '.') {
      return decoded;
    }
  } catch {
    // 非法编码走兜底（不静默改变语义——名只是默认值，用户可改）
  }
  return fallback;
}

// 卡面路径展示（URI → 可读路径：剥 'file://docs' 前缀 + 解码；不匹配前缀或解码失败原样
// 返回——如实展示优先于美化）
export function mountPathDisplay(uri: string): string {
  const prefix: string = 'file://docs';
  let body: string = uri;
  if (uri.startsWith(prefix)) {
    body = uri.substring(prefix.length);
  }
  try {
    return decodeURIComponent(body);
  } catch {
    return body;
  }
}

// 挂载名称校验（'' = 通过；非空返回拒绝原因。挂载名是纯标签——只查空与超长，不做文件名级校验）
export function mountNameRejectReason(raw: string): string {
  const name: string = raw.trim();
  if (name === '') {
    return '请输入挂载名称';
  }
  if (name.length > MOUNT_NAME_MAX_CHARS) {
    return '名称最多 ' + MOUNT_NAME_MAX_CHARS + ' 个字符';
  }
  return '';
}

// 卡列表键（列表键纪律：键必须覆盖该行全部可变展示成分——漏一项即静默冻结。成分 = 身份
// id + 名称 + 目录 URI + 模式（卡头徽章）+ 警示文案（失效态行）；「允许 AI 使用」开关已
// 整面退役、不在成分内。键覆盖两问已重过：卡名/路径/徽章/警示行全在键里
export function mountCardKey(id: number, name: string, dirUri: string, mode: number,
  warningText: string): string {
  return id + '|' + name + '|' + dirUri + '|' + mode + '|' + warningText;
}

// ── 工具面（mount_list / mount_read 的纯函数单源；执行器在 common/providers/ToolMount.ets）──

// 挂载内相对路径总长上限（字符；只防超长参数顶穿回执预算与系统调用）
export const MOUNT_REL_PATH_MAX_CHARS: number = 400;

// 列目录分页（条目数；回执另有 8192 预算逐行收口兜底——两闸取小者生效）
export const MOUNT_LIST_PAGE_DEFAULT: number = 100;
export const MOUNT_LIST_PAGE_MAX: number = 300;

// 有界读上限（字符；对齐附件域 12 万字符惯例——零 import 纪律故字面量镜像，值变更时同步核
// AttachmentUtil.TEXT_ATTACH_MAX_CHARS）
export const MOUNT_READ_MAX_CHARS: number = 120000;

// 回执预算（字符；与 WORKSPACE_REPLY_BUDGET / ToolClip 全局截断同值——零 import 纪律故镜像）
export const MOUNT_REPLY_BUDGET: number = 8192;

// 尾注预留（字符；「继续查看」指针句与省略句上界，含数字位宽余量——帧体预算证明用）
const MOUNT_TAIL_RESERVE: number = 60;

// 相对路径归一（'' = 挂载根；剥首尾与重复 /，丢 . 段——不产生语义变化；.. 段的拒绝在闸函数内）
export function mountRelPathNormalize(raw: string): string {
  const parts: string[] = raw.trim().split('/');
  const kept: string[] = [];
  for (const part of parts) {
    if (part !== '' && part !== '.') {
      kept.push(part);
    }
  }
  return kept.join('/');
}

// 相对路径闸（'' = 通过；非空返回拒绝原因）。只收挂载内相对路径：.. 段可越出挂载根即拒
//（系统持久权只授到挂载根，应用层再拦一层逃逸）；\ 与 NUL 非法；先导 / 由归一剥除（= 挂载根，不拒）
export function mountRelPathRejectReason(raw: string): string {
  const trimmed: string = raw.trim();
  if (trimmed.indexOf('\\') >= 0) {
    return '路径不能包含 \\';
  }
  if (trimmed.indexOf('\0') >= 0) {
    return '路径包含非法字符';
  }
  for (const seg of trimmed.split('/')) {
    if (seg === '..') {
      return '路径不能包含 ..（只能在挂载的文件夹里面）';
    }
  }
  if (trimmed.length > MOUNT_REL_PATH_MAX_CHARS) {
    return '路径超过 ' + MOUNT_REL_PATH_MAX_CHARS + ' 个字符的上限';
  }
  return '';
}

// 挂载清单条目（mount_list 不传 mountId 时的清单视图）
export interface MountBrief {
  id: number;
  name: string;
  mode: number;
}

// 挂载清单回执（编号 · 名称 · 模式；空清单给管理页指引——模型据此知道用户还没添加挂载）
export function composeMountInventoryReply(briefs: MountBrief[]): string {
  if (briefs.length === 0) {
    return '还没有已授权的文件夹。请让用户在 设置 → 文件夹挂载 中添加。';
  }
  const lines: string[] = ['已授权 ' + briefs.length + ' 个文件夹：'];
  for (const b of briefs) {
    lines.push(b.id + ' · ' + b.name + ' · ' + mountModeLabel(b.mode));
  }
  lines.push('请让用户在 设置 → 文件夹挂载 中管理这些挂载。');
  return lines.join('\n');
}

// 目录条目视图（执行器 stat 后组装；sizeText / timeText 用工作区格式化单源预渲染——零
// import 纪律不引 WorkspaceUtil，格式化在外、装配在内；sizeText '' = 属性读取失败）
export interface MountListEntry {
  name: string;
  isDir: boolean;
  sizeText: string;
  timeText: string;
}

// 条目行（目录 = 「名/ · 文件夹」；文件 = 「名 · 大小 · 时间」；属性不可读如实呈报）
function mountEntryLine(entry: MountListEntry): string {
  if (entry.isDir) {
    return entry.name + '/ · 文件夹';
  }
  if (entry.sizeText === '') {
    return entry.name + ' · 无法读取属性';
  }
  return entry.name + ' · ' + entry.sizeText + ' · ' + entry.timeText;
}

// 分页起点越界判定（目录模式专用）：空目录恒不越界——total=0 必须落空态消息、不得落「起始
// 序号已超出末尾」错误（原执行器内联判据 offset >= total 对空目录 0 >= 0 恒真，空目录被误报越界）
export function mountListOffsetBeyond(total: number, offset: number): boolean {
  return total > 0 && offset >= total;
}

// 列目录回执（对齐工作区 list 形制——首行报位置与规模，条目按名称序，预算逐行收口 + 末尾
// offset 指针；offset = 本次页起始序号 0 起）。预算证明：帧体 = 回执预算 − 头部上界 −
// 尾注预留，合计恒 ≤ 8192
export function composeMountListReply(mountName: string, relPath: string, total: number,
  offset: number, entries: MountListEntry[]): string {
  const where: string = relPath === '' ? '根目录' : '「' + relPath + '」目录';
  const subject: string = '挂载「' + mountName + '」' + where;
  if (total === 0) {
    return subject + '还没有文件与子文件夹。';
  }
  if (entries.length === 0 || offset >= total) {
    return subject + '共 ' + total + ' 个条目，请求的起始序号已超出末尾。' +
      '可用 offset=0 从第一个条目查看。';
  }
  const frameBudget: number = MOUNT_REPLY_BUDGET - subject.length - 60 - MOUNT_TAIL_RESERVE;
  const bodyLines: string[] = [];
  let used: number = 0;
  for (const entry of entries) {
    const line: string = mountEntryLine(entry);
    if (used + line.length + 1 > frameBudget) {
      break;
    }
    bodyLines.push(line);
    used += line.length + 1;
  }
  const shown: number = bodyLines.length;
  const head: string = subject + '下共 ' + total + ' 个条目，以下为第 ' + (offset + 1) + '~' +
    (offset + shown) + ' 项：';
  let text: string = head + '\n' + bodyLines.join('\n');
  const nextIndex: number = offset + shown;
  if (nextIndex < total) {
    // 单尾注两因合流：本页被截短与列表未完的续看入口都是 nextIndex——省略句按因分派，指针恒一致
    const lead: string = shown < entries.length ?
      '[本页其余条目已省略，可用 offset=' : '[未完部分可用 offset=';
    text += '\n' + lead + nextIndex + ' 继续查看]';
  }
  return text;
}

// 大文件截断说明行（readChars = 实际读到字符数；行内明示「后文不在本条回执中」防模型误判文件已尽）
export function mountReadTruncatedMeta(readChars: number): string {
  return '文件较大，本条回执只包含前 ' + readChars + ' 个字符的内容。';
}

// 工具面授权失败文案（policyCode 取 err.data[0].code，无则 0。4 = PERMISSION_NOT_PERSISTED
//——最典型「授权已失效」面，指引到管理页重新授权）
export function mountToolGrantErrorText(policyCode: number): string {
  if (policyCode === 4) {
    return '这个文件夹的授权已失效。请让用户在 设置 → 文件夹挂载 中为它重新授权。';
  }
  return '这个文件夹的访问授权当前不可用。请让用户在 设置 → 文件夹挂载 中检查该挂载并重新授权。';
}

// 持久授权失败文案（code 13900001 + 逐 URI PolicyErrorCode 如实透传——底层 code 不美化）。
// policyCode 取 err.data[0].code，无 data 传 0
export function mountPolicyErrorText(code: number, policyCode: number): string {
  if (policyCode === 1) {
    // PERSISTENCE_FORBIDDEN——已知两因：①掩码混入仅支持临时授权的模式位（已由模式位纪律
    // 堵死）；②系统策略与条目上限（文案保留上限提示——修复后即残留主因）
    return '系统不允许挂载这个文件夹，可能已达到设备的挂载数量上限';
  }
  if (policyCode === 2) {
    // INVALID_MODE
    return '系统不支持所选访问模式，请换一种再试';
  }
  if (policyCode === 3) {
    // INVALID_PATH
    return '文件夹路径无效，请重新选择';
  }
  if (policyCode === 4) {
    // PERMISSION_NOT_PERSISTED
    return '授权没有写入系统，请重试';
  }
  return '挂载失败（code ' + code + '）';
}

// ── 写面（mount_write / mount_copy_out 的常量与回执纯函数；执行器与确认预检在 ToolMount.ets）──

// 单次写入上限（字符；与 MOUNT_READ_MAX_CHARS 同值对称——超出提示分次写，值变更与读上限同批核）
export const MOUNT_WRITE_MAX_CHARS: number = 120000;

// 写方式三值（mount_write 的 mode 参数值域；append 到不存在的文件 = 自动新建，类 shell >>）
export const MOUNT_WRITE_MODE_CREATE: string = 'create';
export const MOUNT_WRITE_MODE_APPEND: string = 'append';
export const MOUNT_WRITE_MODE_OVERWRITE: string = 'overwrite';

// 写方式中文（确认卡 detail 与回执共用）
export function mountWriteModeLabel(writeMode: string): string {
  if (writeMode === MOUNT_WRITE_MODE_CREATE) {
    return '新建';
  }
  if (writeMode === MOUNT_WRITE_MODE_APPEND) {
    return '追加';
  }
  if (writeMode === MOUNT_WRITE_MODE_OVERWRITE) {
    return '整写覆盖';
  }
  return '';
}

// 写回执（writtenBytes / expectedBytes = 实写与期望字节数）。部分写入如实报：挂载内无原子
// 替换（RENAME 不可持久授权），整写 = 原位 TRUNC 后写，中途失败留残缺——「不回滚已写内容、
// 如实报实际写入」是安全面承诺不是可选项。diffTail（第 5 可选参，缺省 ''——存量四参调用
// 逐字不变）= 覆盖写旧文摘录/超阈行数对，**只在全量写成功拍附加**（部分写入档照实报残缺）
export function composeMountWriteReply(relPath: string, writeMode: string,
  writtenBytes: number, expectedBytes: number, diffTail: string = ''): string {
  const label: string = mountWriteModeLabel(writeMode);
  const actionText: string = writeMode === MOUNT_WRITE_MODE_CREATE ?
    '已在挂载里新建「' + relPath + '」' :
    writeMode === MOUNT_WRITE_MODE_APPEND ?
      '已向「' + relPath + '」末尾追加' : '已整写「' + relPath + '」';
  if (writtenBytes < expectedBytes) {
    return '写入没有完成，文件可能不完整：本次只写入了 ' + writtenBytes + ' / ' +
      expectedBytes + ' 字节（' + label + '）。写入失败不回滚已写内容，请先读取文件确认' +
      '现状再决定重写或补写。';
  }
  return actionText + '，写入 ' + writtenBytes + ' 字节。' +
    (diffTail === '' ? '' : '\n' + diffTail);
}

// copy_out 回执（挂载内文件复制进工作区；overwriteNote 非空 = 覆盖了他会话/上传归属既有件
// 的注记句，由工作区侧单源产，此处拼尾）
export function composeMountCopyOutReply(mountName: string, relPath: string,
  displayName: string, dir: string, sizeText: string, overwriteNote: string): string {
  let text: string = '已把挂载「' + mountName + '」里的「' + relPath + '」复制到文件工作区' +
    (dir === '' ? '' : '的「' + dir + '」文件夹') + '，保存为「' + displayName + '」，共 ' +
    sizeText + '。用户在 设置 → 文件工作区 可以查看';
  if (overwriteNote !== '') {
    text += '。' + overwriteNote;
  }
  return text;
}

// ── 浏览页（页面 = components/settings/MountBrowsePage.ets；工具面共用 joinMountPath / mountKindOf）──

// 单层条目显示上限（超出尾行提示「仅显示前 N 条」——列表内存与渲染有界，不随用户目录无界增长）
export const MOUNT_BROWSE_MAX_ROWS: number = 1000;

// 浏览页路由参数（接口落域件而非页面文件——common 层不反向依赖 UI 组件）
export interface MountBrowseParam {
  mountId: number;
}

// 浏览页单条目录项（列目录 stat 现读产物；mtimeMs 已按坑32 由秒换算毫秒执行）
export interface MountBrowseRow {
  name: string;
  isDir: boolean;
  size: number;
  mtimeMs: number;
}

// 行键（列表键纪律：行卡消费的可变成分 = 名称/类型/大小/修改时间，全在键里——任一变化即键变重建）
export function mountBrowseRowKey(row: MountBrowseRow): string {
  return row.name + '|' + (row.isDir ? 'd' : 'f') + '|' + row.size + '|' + row.mtimeMs;
}

// 排序（文件夹在前 + 名称升序；localeCompare——中文与数字混排比码元序自然，与系统文件管理器观感一致）
export function compareMountBrowseRows(a: MountBrowseRow, b: MountBrowseRow): number {
  if (a.isDir !== b.isDir) {
    return a.isDir ? -1 : 1;
  }
  return a.name.localeCompare(b.name);
}

// 相对路径拼接（relPath '' = 挂载根本身）；工具面与浏览页共用单源（禁止两份并存）。根路径
// 转换 mountRootPathFromUri 因需 fileUri（@kit.CoreFileKit import）留在 ToolMount.ets 并已导出
export function joinMountPath(rootPath: string, relPath: string): string {
  return relPath === '' ? rootPath : rootPath + '/' + relPath;
}

// 挂载内文件类型（'image' | 'text' | 'doc' | 'other'；浏览页图标分档与 mount_read 分派共用）
export const MOUNT_KIND_IMAGE: string = 'image';
export const MOUNT_KIND_TEXT: string = 'text';
export const MOUNT_KIND_DOC: string = 'doc';
export const MOUNT_KIND_OTHER: string = 'other';

// 三张扩展名白名单（与 WorkspaceUtil.classifyWorkspaceName / AttachmentUtil.classifyByName
// 同值**镜像**——零 import 纪律故字面量，同值关系由 assert-mount-domain 钉守；值变更三处同批核）
const MOUNT_IMAGE_EXTS: string[] = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif'];
const MOUNT_TEXT_EXTS: string[] = ['txt', 'md', 'log', 'json', 'csv', 'xml', 'html', 'htm', 'yml',
  'yaml', 'toml', 'ini', 'sh', 'bat', 'ps1', 'py', 'js', 'ts', 'c', 'h', 'cpp', 'java', 'css'];
const MOUNT_DOC_EXTS: string[] = ['pdf', 'docx', 'xlsx', 'xls', 'ofd', 'pptx'];

// 文件名扩展名（小写、无点；无扩展名回 ''——与两域 extOf 同形同值）
export function mountExtOf(name: string): string {
  const dot: number = name.lastIndexOf('.');
  if (dot < 0 || dot >= name.length - 1) {
    return '';
  }
  return name.substring(dot + 1).toLowerCase();
}

// 类型判定（入参可带目录段，只取尾段判扩展名；未知/无后缀落 other——回执由消费方按 kind 分派）
export function mountKindOf(relPath: string): string {
  const name: string = relPath.substring(relPath.lastIndexOf('/') + 1);
  const ext: string = mountExtOf(name);
  if (MOUNT_IMAGE_EXTS.indexOf(ext) >= 0) {
    return MOUNT_KIND_IMAGE;
  }
  if (MOUNT_TEXT_EXTS.indexOf(ext) >= 0) {
    return MOUNT_KIND_TEXT;
  }
  if (MOUNT_DOC_EXTS.indexOf(ext) >= 0) {
    return MOUNT_KIND_DOC;
  }
  return MOUNT_KIND_OTHER;
}

// ── M3 笔2（图片档 + 文档档 + 复制入挂载；执行器与确认预检在 ToolMount.ets）──

// 单张图片读取上限（字节；与 MOUNT_COPY_IN_MAX_BYTES〔WorkspaceDb〕及下方
// MOUNT_COPY_TO_MOUNT_MAX_BYTES 同值 30MB——零 import 纪律字面量镜像，三处同值由钉守）
export const MOUNT_IMAGE_MAX_BYTES: number = 30 * 1024 * 1024;

// 单次「复制入挂载」（copy_in 方向）上限（字节；与〔复制**出**挂载进工作区〕的
// MOUNT_COPY_IN_MAX_BYTES 刻意区分命名——两方向同名易混）
export const MOUNT_COPY_TO_MOUNT_MAX_BYTES: number = 30 * 1024 * 1024;

// 文档 OCR 回执（读挂载内文档/扫描件页图的四态回执；「文档」措辞——复用图片版回执会把
// PDF 说成图片，故立本版。ocr_text 整条经 MOUNT_REPLY_BUDGET 收口；outcome 未知值兜底
// ocr_failed 形态）
export function composeMountDocOcrReply(name: string, outcome: string, detail: string = '',
  engine: string = ''): string {
  if (outcome === 'ocr_text') {
    const engineLabel: string = engine === 'system' ? '系统识别' :
      (engine === 'builtin' ? '内置识别' : (engine === 'model' ? '视觉模型' : ''));
    const head: string = '文档「' + name + '」已识别出文字内容' +
      (engineLabel !== '' ? '（引擎 ' + engineLabel + '）' : '') + '，如下。';
    return mountClipReply(head + '\n' + detail);
  }
  if (outcome === 'ocr_empty') {
    return '文档「' + name + '」未识别到文字。它可能是扫描件且文字不清晰，' +
      '请结合文件名与上下文判断内容，或让用户在应用内查看该文档。';
  }
  if (outcome === 'ocr_disabled') {
    return '文档「' + name + '」无法识别文字，因为应用的文字识别功能未开启。' +
      '请让用户在应用的设置中开启文字识别，或在应用内查看该文档。';
  }
  return '文档「' + name + '」文字识别未成功。请让用户在应用内查看该文档，或稍后重试。';
}

// 回执预算收口（零 import 纪律故自理；形制镜像 WorkspaceUtil.clipWorkspaceReply——防 OCR 长文本顶穿预算）
function mountClipReply(text: string): string {
  if (text.length <= MOUNT_REPLY_BUDGET) {
    return text;
  }
  return text.substring(0, MOUNT_REPLY_BUDGET) + '\n[内容过长已截断]';
}

// copy_in 成功回执（工作区文件复制进挂载；与 composeMountCopyOutReply 反向对称——拷出报
// 工作区落库名，拷入报挂载落点路径）
export function composeMountCopyInReply(mountName: string, relPath: string, srcName: string,
  writtenBytes: number): string {
  return '已把文件工作区的「' + srcName + '」复制到挂载「' + mountName + '」的「' + relPath +
    '」，共 ' + writtenBytes + ' 字节。';
}

// copy_in 部分复制/中断如实回执（writtenBytes < totalBytes 时消费；「不回滚已写入内容」与
// 写回执部分写入同款诚实——挂载内无原子替换，TRUNC 后中途失败留残缺，如实报是安全面承诺）
export function composeMountCopyInPartialReply(writtenBytes: number, totalBytes: number): string {
  return '复制没有完成，目标文件可能不完整：本次只写入了 ' + writtenBytes + ' / ' + totalBytes +
    ' 字节。复制失败不回滚已写入内容，请先查看目标文件确认现状，再决定重试。';
}

// ── 删除与系统文件管理跳转（决明拍板「删除走系统回收站 + 只读挂载置灰与指引 + mount_delete
//    走既有确认链」；回收站调用本体在 common/MountTrash.ets）──

// 系统文件管理「打开目录」deeplink（官方 FAQ 指名：openLink 传本串、parameters 传 {'fileUri': …}）
export const FILE_MANAGER_OPEN_DIRECTORY_LINK: string = 'filemanager://openDirectory';

// 挂载内条目的文档类 URI（dirUri + 相对路径逐段 encodeURIComponent；relPath '' = 根原样）。
// 消费 = 回收站删除与系统文件管理跳转（都只吃 URI）；与 joinMountPath 的路径形态拼接互为
// 正反——本函数只服务「对外交付 URI」、不做文件系统寻址。段名来自目录列表真实名（已解码）
// 故逐段编码；fileUri 取值语义官方未定义（FAQ 示例传空串），本仓传目标 URI、成效由真机验证
export function mountChildUri(dirUri: string, relPath: string): string {
  let base: string = dirUri;
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  const normalized: string = mountRelPathNormalize(relPath);
  if (normalized === '') {
    return base;
  }
  const encoded: string[] = [];
  for (const seg of normalized.split('/')) {
    encoded.push(encodeURIComponent(seg));
  }
  return base + '/' + encoded.join('/');
}

// 删除回执（写明去向 = 系统回收站与恢复途径——「删除可恢复」是本域删除语义核心承诺）
export function composeMountDeleteReply(mountName: string, relPath: string, isDir: boolean): string {
  const what: string = isDir ? '文件夹' : '文件';
  return '已把挂载「' + mountName + '」里的' + what + '「' + relPath +
    '」删除到系统回收站。它可以在系统文件管理的回收站里恢复。';
}
