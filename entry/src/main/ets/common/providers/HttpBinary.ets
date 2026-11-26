// HTTP 工具域·二进制进出域：下载落盘入工作区 / 上传源两段式匹配（会话附件优先 → 工作区
// 兜底，决明拍板）/ multipart 入参组装 / 导入拷贝。纯函数（文件名派生 / 落库名合成 / 匹配 /
// 组装）与 I/O 薄壳（落盘 / 读源 / 拷贝）同件——纯函数全 export 供断言直跑。零 import 工具
// 域（坑50：ToolHttp 引本件，本件不引 ToolHttp）；依赖 = WorkspaceUtil 纯函数叶 +
// WorkspaceDb 文件面 + ChatDb 委托 + DbWriteQueue 写串行链 + NetworkKit 类型位 +
// HttpReceipt 纯函数叶。
// ★ 三修（下载链首用与并发面）：①下载落库名走 composeDownloadDisplayName 合成（无扩展名
// 补三档派生扩展 / 点串归位保过名称闸 / 撞名照用户上传追号）；②两壳入写串行链（工具轮
// Promise.all 并发下「查名 / 查配额 → 写」穿窗）；③两壳先行 ensureWorkspaceDir（首次工作区
// 操作即下载或导入时目录未建，openSync 即 ENOENT）。
// · 隐私会话专项防御**零实现**：隐私会话功能已全链退役（ChatSendCtrl 头注释），原「隐私
//   会话一律禁用 download」段前提消失——按「开工以当刻实读为准」处理，变更记录登记；上传
//   两段式对普通会话照常。
// · 安全定案：模型恒按显示名引用上传源，路径解析全在应用侧（匹配纯函数入参含 / 或 .. 按
//   未命中处理——路径注入防线）；文件内容不进出站哨兵扫描面（用户数据非模型生成，哨兵
//   目的 = 防模型粘贴凭据明文）。
import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { WorkspaceFileRow, buildWorkspaceRow, dedupeWorkspaceName, extOfWorkspaceName,
  isWorkspaceDirRow, relativeWorkspacePath, workspaceCapacityReason, workspaceDirChainReject,
  workspaceDirRejectReason,
  WORKSPACE_ROWS_READ_MAX, WORKSPACE_SOURCE_ASSISTANT, WORKSPACE_SOURCE_DOWNLOAD,
  sanitizeWorkspaceName,
  WORKSPACE_NAME_MAX_CHARS } from '../WorkspaceUtil';
// 覆盖注记族在 WorkspaceReply（判据单源自该件引）
import { workspaceOverwriteKindOf } from '../WorkspaceReply';
import { dirChildSegments, ensureWorkspaceDir, physicalWorkspaceDirExists,
  workspaceFilesDir } from '../store/WorkspaceDb';
import { queryWorkspaceFiles, queryWorkspaceFilesByName, queryWorkspaceTotal,
  ensureWorkspaceDirRowsOp, upsertWorkspaceFile } from '../store/ChatDb';
import { runWriteQueued } from '../store/DbWriteQueue';
import { AttachmentListRow } from '../store/AttachmentDb';
import { isTextContentType } from './HttpReceipt';

// ── 闸常量（模型可见数字与 desc/schema 单源）──
// 下载单件上限（= 官方 maxLimit 档；超限应用先按响应头 content-length 拦，无头由 maxLimit
// 兜底抛 2300063）
export const HTTP_DOWNLOAD_MAX_LIMIT_BYTES: number = 20 * 1024 * 1024;
// 上传单件上限（file 直传与 multipart 文件件同受）
export const HTTP_UPLOAD_FILE_MAX_BYTES: number = 10 * 1024 * 1024;
// multipart 件数与字段数闸
export const HTTP_MULTIPART_FILES_MAX: number = 5;
export const HTTP_MULTIPART_FIELDS_MAX: number = 20;

// ── 下载文件名派生（纯函数，断言直跑）──
// URL 尾段扩展名（剥 query 与 fragment → decode → 小写；无点或点在首位回 ''；超长截 10 防
// 尾段被当扩展名灌长）
export function extFromUrlTail(url: string): string {
  let tail: string = url.split('#')[0].split('?')[0];
  const slash: number = tail.lastIndexOf('/');
  if (slash >= 0) {
    tail = tail.substring(slash + 1);
  }
  try {
    tail = decodeURIComponent(tail);
  } catch {
    // 非法编码按原串处理
  }
  const dot: number = tail.lastIndexOf('.');
  if (dot <= 0 || dot >= tail.length - 1) {
    return '';
  }
  const ext: string = tail.substring(dot + 1).toLowerCase();
  if (!/^[a-z0-9]+$/.test(ext)) {
    return '';
  }
  return ext.length > 10 ? ext.substring(0, 10) : ext;
}

// Content-Type → 扩展名小映射表（URL 派生不出时的第二档；~12 行常见档）
export function extFromContentType(contentType: string): string {
  const lower: string = contentType.toLowerCase().split(';')[0].trim();
  if (lower === 'image/jpeg') {
    return 'jpg';
  }
  if (lower === 'image/png') {
    return 'png';
  }
  if (lower === 'image/webp') {
    return 'webp';
  }
  if (lower === 'image/gif') {
    return 'gif';
  }
  if (lower === 'image/bmp') {
    return 'bmp';
  }
  if (lower === 'application/pdf') {
    return 'pdf';
  }
  if (lower === 'application/zip') {
    return 'zip';
  }
  if (lower === 'application/json') {
    return 'json';
  }
  if (lower === 'text/plain' || lower.startsWith('text/')) {
    return 'txt';
  }
  return '';
}

// 下载显示名（URL 尾段 decode + 非法字符替换 _ + 空兜底「下载文件」+ 超 80 截尾——与
// WorkspaceUtil.sanitizeWorkspaceName 的分界：那件管写入侧收口含连续点归位与默认名，本函数
// 管下载侧派生且**保留原扩展名语义**〔截尾在整名上〕；两件同受 WORKSPACE_NAME_MAX_CHARS）
export function deriveDownloadDisplayName(url: string): string {
  let tail: string = url.split('#')[0].split('?')[0];
  const slash: number = tail.lastIndexOf('/');
  if (slash >= 0) {
    tail = tail.substring(slash + 1);
  }
  try {
    tail = decodeURIComponent(tail);
  } catch {
    // 非法编码按原串处理
  }
  let cleaned: string = '';
  for (const ch of tail) {
    const code: number = ch.charCodeAt(0);
    if ('\\/:*?"<>|'.indexOf(ch) >= 0 || code < 0x20 || code === 0x7F) {
      cleaned += '_';
    } else {
      cleaned += ch;
    }
  }
  cleaned = cleaned.trim();
  if (cleaned === '') {
    return '下载文件';
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

// 下载文件名三元派生（URL 尾段 → Content-Type 映射 → 兜底：文本 .txt / 其余 .bin）——
// 返回扩展名由 composeDownloadDisplayName 消费（原实现本函数算出即弃用、物理名随显示名
// 派生，URL 无扩展名〔下载接口带 query 的常见形态〕即落无扩展名文件，系统预览按 uri 后缀
// 自判打不开）
export function deriveDownloadExt(url: string, contentType: string): string {
  const fromUrl: string = extFromUrlTail(url);
  if (fromUrl !== '') {
    return fromUrl;
  }
  const fromCt: string = extFromContentType(contentType);
  if (fromCt !== '') {
    return fromCt;
  }
  return isTextContentType(contentType) ? 'txt' : 'bin';
}

// 下载落库显示名合成（纯函数，断言直跑；下载命名三缺陷收口一处）：①URL 尾段无扩展名时补
// 三档派生扩展（补名后 kind / mime / 物理名 / 缩略图 / 系统预览五处同源一致）；②名称过
// sanitizeWorkspaceName（连续点归位——URL 尾段带 '..' 的名过不了工具侧名称闸，落库后模型
// read / write 永拒）；③撞名照用户上传同款追加序号（同 URL 重下不造同名两行）。existingNames
// = 工作区现存全部显示名（查名在调用方，纯函数不碰 IO）；返回名恒 ≤80 字符且过名称闸。
// ★ 长度收口**扩展名感知**——主体先按「80 − 扩展名 − 1」预算截断再重挂扩展名（「补完再
// 截」链路里 sanitize 内部截 80 不看扩展名边界，贴线长名补扩展名后被截残/截丢——kind 落
// other 档、物理名与系统预览按残名后缀打不开）；撞名追号推过上限时同样收主体后重跑避重。
// ★ 重挂扩展名自 derived **原样大小写**切分（extOfWorkspaceName 的小写化只作「有无扩展名」
// 判据；按小写化重建会让 'Report.PDF' → 'Report.pdf'，跨版本重下与旧行精确比较去不中，落
// 成仅大小写不同的第二行而非 (2) 追号）。「有扩展名」路径与旧实现输出逐字一致，仅「补档」
// 与「追号收主体」两路径有新行为
export function composeDownloadDisplayName(url: string, contentType: string,
  existingNames: string[]): string {
  const derived: string = deriveDownloadDisplayName(url);
  const extLower: string = extOfWorkspaceName(derived);
  const dot: number = derived.lastIndexOf('.');
  let base: string = derived;
  let ext: string = '';
  if (extLower === '') {
    ext = deriveDownloadExt(url, contentType); // 补档路径恒小写（extFromUrlTail / extFromContentType 均小写返回）
  } else {
    base = derived.substring(0, dot);
    ext = derived.substring(dot + 1);
  }
  // 主体预算收口（代理对退格同 deriveDownloadDisplayName 的截点收口——孤代理污染显示与匹配）
  const room: number = WORKSPACE_NAME_MAX_CHARS - ext.length - 1;
  if (base.length > room) {
    let cut: number = room;
    if (cut > 0 && base.charCodeAt(cut - 1) >= 0xD800 && base.charCodeAt(cut - 1) <= 0xDBFF) {
      cut -= 1;
    }
    base = base.substring(0, Math.max(cut, 0));
  }
  let name: string = sanitizeWorkspaceName(base + '.' + ext);
  name = dedupeWorkspaceName(name, existingNames);
  // 追号在扩展名前，可能把贴线名推过上限：按溢出量收主体重跑避重（dedupe 契约 = 返回不在
  // existing 的名，截后必须重验才闭环；每轮主体至少收 1 字符，循环必有界，常态一轮收敛）
  while (name.length > WORKSPACE_NAME_MAX_CHARS && base.length > 0) {
    let cut: number = base.length - (name.length - WORKSPACE_NAME_MAX_CHARS);
    if (cut < 0) {
      cut = 0;
    }
    if (cut > 0 && base.charCodeAt(cut - 1) >= 0xD800 && base.charCodeAt(cut - 1) <= 0xDBFF) {
      cut -= 1;
    }
    base = base.substring(0, cut);
    name = dedupeWorkspaceName(sanitizeWorkspaceName(base + '.' + ext), existingNames);
  }
  // 理论兜底（主体收空仍超长的极限形态，常态不可达）：sanitize 收口保「恒 ≤80 且过闸」
  if (name.length > WORKSPACE_NAME_MAX_CHARS) {
    name = sanitizeWorkspaceName(name);
  }
  return name;
}

// ── 上传源两段式匹配（纯函数，断言直跑；决明拍板：会话附件优先 → 工作区兜底）──
// 匹配结果五态：'conv' 会话附件唯一命中 / 'ws' 工作区兜底命中 / 'multi' 会话域同名多命中
//（防线报错）/ 'ws-multi' 工作区跨目录同名多命中（歧义报错——write/import 覆盖判定按
// (dir, name) 二元组，跨目录同名是合法形态非数据异常）/ 'none' 两域皆空。ws 匹配面 = 全部
// 目录的文件行（声明面无「仅根目录」限定，目录行笔的 dir === '' 过滤曾无心殃及子目录文件、
// 已扩面修复）。入参含 / 或 .. 按未命中处理（路径注入防线——模型不得借名拼路径）
export interface UploadSourceMatch {
  state: string;
  kind: string; // 命中文件的 kind（image/text/doc/other）
  mime: string;
  size: number;
  localPath: string; // 相对 filesDir（附件域或工作区目录，按命中来源）
  displayName: string;
}

function nameUnsafeForMatch(name: string): boolean {
  return name.indexOf('/') >= 0 || name.indexOf('\\') >= 0 || name.indexOf('..') >= 0;
}

export function matchUploadSource(name: string,
  conversationRows: AttachmentListRow[], workspaceRows: WorkspaceFileRow[]): UploadSourceMatch {
  const none: UploadSourceMatch = { state: 'none', kind: '', mime: '', size: 0,
    localPath: '', displayName: name };
  if (name.trim() === '' || nameUnsafeForMatch(name)) {
    return none;
  }
  const convHits: AttachmentListRow[] = conversationRows.filter((row: AttachmentListRow): boolean =>
    row.name === name);
  if (convHits.length === 1) {
    const row: AttachmentListRow = convHits[0];
    return { state: 'conv', kind: row.kind, mime: row.mime, size: row.size,
      localPath: row.localPath, displayName: row.name };
  }
  if (convHits.length > 1) {
    return { state: 'multi', kind: '', mime: '', size: 0, localPath: '', displayName: name };
  }
  // ws 兜底匹配排除目录行（dir 行的 name 是文件夹段名非文件名——上传源恒文件）；匹配面 =
  // 全部目录的文件行（子目录行 localPath 含目录段〔workspace/<dir段…/>fileId.<ext>〕，调用
  // 方 filesDir 拼接读取零适配）；跨目录同名多命中升独立歧义态 'ws-multi'（报错带可行解法，
  // HttpFlow 消费），不与会话域 'multi' 防线态混用
  const wsHits: WorkspaceFileRow[] = workspaceRows.filter((row: WorkspaceFileRow): boolean =>
    row.name === name && !isWorkspaceDirRow(row));
  if (wsHits.length === 1) {
    const row: WorkspaceFileRow = wsHits[0];
    return { state: 'ws', kind: row.kind, mime: row.mime, size: row.size,
      localPath: row.localPath, displayName: row.name };
  }
  if (wsHits.length > 1) {
    return { state: 'ws-multi', kind: '', mime: '', size: 0, localPath: '', displayName: name };
  }
  return none;
}

// ── multipart 组装（纯函数，断言直跑；官方通道——boundary 系统生成，禁自拼）──
// 输入 = 已匹配命中的文件件（filePath 绝对路径由调用侧拼，纯函数不碰 IO）；输出 =
// multiFormDataList 或中文报错。闸：件数 ≤5、字段数 ≤20、文件件 ≤10MB（与 file 直传同闸）
export interface MultipartFieldInput {
  name: string;
  value: string;
}

export interface MultipartFileInput {
  fieldName: string; // 表单字段名（缺省 'file' 由本函数兜底）
  attachment: string; // 显示名（报错文案用）
  kind: string;
  mime: string;
  size: number;
  filePath: string; // 沙箱绝对路径
}

export interface MultipartBuildOutcome {
  ok: boolean;
  errorText: string;
  data: http.MultiFormData[];
}

export function buildMultiFormData(fields: MultipartFieldInput[],
  files: MultipartFileInput[]): MultipartBuildOutcome {
  if (files.length === 0) {
    return { ok: false, errorText: 'multipart 的 files 不能为空', data: [] };
  }
  if (files.length > HTTP_MULTIPART_FILES_MAX) {
    return { ok: false, errorText: 'multipart 最多携带 ' + HTTP_MULTIPART_FILES_MAX +
      ' 个文件，请精简后重试', data: [] };
  }
  if (fields.length > HTTP_MULTIPART_FIELDS_MAX) {
    return { ok: false, errorText: 'multipart 最多携带 ' + HTTP_MULTIPART_FIELDS_MAX +
      ' 个文本字段，请精简后重试', data: [] };
  }
  const data: http.MultiFormData[] = [];
  for (const field of fields) {
    data.push({ name: field.name, contentType: 'text/plain', data: field.value });
  }
  for (const file of files) {
    if (file.size > HTTP_UPLOAD_FILE_MAX_BYTES) {
      return { ok: false, errorText: '文件「' + file.attachment + '」超过 ' +
        (HTTP_UPLOAD_FILE_MAX_BYTES / (1024 * 1024)) + 'MB 的上传上限，无法发送',
        data: [] };
    }
    const mime: string = file.mime !== '' ? file.mime : 'application/octet-stream';
    data.push({
      name: file.fieldName !== '' ? file.fieldName : 'file',
      contentType: mime,
      filePath: file.filePath,
      remoteFileName: file.attachment
    });
  }
  return { ok: true, errorText: '', data: data };
}

// ── I/O 薄壳 ──
// 下载落盘入工作区（先落文件 → 后写行，行写失败自清——WorkspaceDb 写序铁律同款）。返回
// 回执 saved 面字段；失败 errorText 中文。★ 全程入写串行链——工具轮并发执行
//（ChatToolRoundCtrl Promise.all）下「查名 / 查配额 → 写」穿窗 = 同名两行与容量溢出
//（照 saveWorkspaceTextFile 同款纪律；入链的是查写整段）
export interface DownloadSaveOutcome {
  ok: boolean;
  errorText: string;
  fileId: string;
  name: string;
  kind: string;
  size: number;
  path: string; // 工作区相对路径（workspace/<fileId>.<ext>——非绝对路径，卡面预览拼 filesDir 用）
}

export function saveDownloadToWorkspace(bytes: ArrayBuffer, url: string,
  contentType: string, conversationId: string, assistantId: string): Promise<DownloadSaveOutcome> {
  return runWriteQueued('saveDownloadToWorkspace', async (): Promise<DownloadSaveOutcome> => {
    const failed = (text: string): DownloadSaveOutcome => ({ ok: false, errorText: text,
      fileId: '', name: '', kind: '', size: 0, path: '' });
    if (workspaceFilesDir() === '') {
      return failed('工作区目录未就绪，无法保存文件');
    }
    // 落库名合成（现存名一次取回供撞名避重，行集读取上限为界；下载恒落根，避重只看根目录
    // 名——跨目录同名不参与追号；根目录**目录行**的段名天然在名单内——下载名不与文件夹
    // 撞名，零额外代码）
    const existingNames: string[] = [];
    const nameRows: WorkspaceFileRow[] = await queryWorkspaceFiles(WORKSPACE_ROWS_READ_MAX);
    for (const nameRow of nameRows) {
      if (nameRow.dir === '') {
        existingNames.push(nameRow.name);
      }
    }
    const displayName: string = composeDownloadDisplayName(url, contentType, existingNames);
    const fileId: string = util.generateRandomUUID(true);
    // 行构建（other 兜底档——下载可为任意类型；source='download'，追溯字段照填）
    const row: WorkspaceFileRow = buildWorkspaceRow(fileId, displayName, bytes.byteLength,
      WORKSPACE_SOURCE_DOWNLOAD, conversationId, assistantId, Date.now(), 'other');
    // 容量两闸（总量/件数——单件 20MB 由传输层 maxLimit 先拦）
    const total = await queryWorkspaceTotal();
    const capacityReason: string = workspaceCapacityReason(bytes.byteLength, total.count,
      total.bytes);
    if (capacityReason !== '') {
      return failed(capacityReason);
    }
    // 目录就绪（首次工作区操作即下载时目录未建，不先行建即 openSync ENOENT）
    let dir: string = '';
    try {
      dir = ensureWorkspaceDir();
    } catch (e) {
      return failed('文件写入失败：' + (e as Error).message);
    }
    const absPath: string = dir + '/' +
      row.localPath.substring(row.localPath.lastIndexOf('/') + 1);
    const file: fs.File = fs.openSync(absPath, fs.OpenMode.READ_WRITE |
      fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, bytes);
    } catch (e) {
      try {
        fs.unlinkSync(absPath);
      } catch {
        // 自清失败留残留：「清空工作区」清整个目录兜底，不吞原始错误
      }
      return failed('文件写入失败：' + (e as Error).message);
    } finally {
      fs.closeSync(file);
    }
    try {
      await upsertWorkspaceFile(row);
    } catch (e) {
      try {
        fs.unlinkSync(absPath);
      } catch {
        // 同上：残留由清空工作区兜底
      }
      return failed('工作区记录写入失败：' + (e as Error).message);
    }
    return { ok: true, errorText: '', fileId: fileId, name: row.name, kind: row.kind,
      size: row.size, path: row.localPath };
  });
}

// 读上传源为 ArrayBuffer（file 直传路；10MB 内整读——闸在执行器先检）。读满循环 + 按实读
// 长度截断：单次 readSync 可短读（并发变小 / 分段返回），stat 尺寸分配的尾部零填充混入
// 会污染请求体（90 组短读红线——每处 readSync 赋值消费返回长度）。
// ★ 续读**不用** ReadOptions.offset——其语义是文件读取起点（本地 d.ts 实锤，且 readSync
// 无 buffer 偏移参数、数据恒写入 buffer 开头），把 offset 当 buffer 偏移复用 buf 会让短读
// 第二轮把后续批次写进 buf 头部覆盖前批，产出「头部错乱 + 尾部零填充」的静默污染请求体
//（错乱不报错、直接发出）。改：首轮整读走原路径（常规一轮读满零额外开销），短读才入续读
// 循环——每轮读入独立临时缓冲再 set 到目标位，指针顺序读（默认自当前位续读，不赌 offset
// 语义），读多少拼多少
export function readUploadSourceAsBuffer(absPath: string): ArrayBuffer {
  const stat: fs.Stat = fs.statSync(absPath);
  const buf: ArrayBuffer = new ArrayBuffer(stat.size);
  const file: fs.File = fs.openSync(absPath, fs.OpenMode.READ_ONLY);
  try {
    let total: number = fs.readSync(file.fd, buf);
    while (total > 0 && total < stat.size) {
      const tmp: ArrayBuffer = new ArrayBuffer(stat.size - total);
      const n: number = fs.readSync(file.fd, tmp);
      if (n <= 0) {
        break; // EOF 早于 stat（文件并发变小）——按已读长度截断
      }
      new Uint8Array(buf).set(new Uint8Array(tmp, 0, n), total);
      total += n;
    }
    return total === stat.size ? buf : buf.slice(0, total);
  } finally {
    fs.closeSync(file);
  }
}

// 导入会话附件入工作区（workspace_import 的动作壳：拷贝 → 入库 source='assistant'、同名
// 覆盖走 write 覆盖链——复用 saveWorkspaceText 不可〔那是文本写入〕，本壳按「拷文件 + 行
// upsert」实现覆盖语义：唯一同名命中 = 覆写该行文件与 size/updatedAt；零命中 = 新建）。
// ★ 覆盖判定按**清洗后的落库名**查（原按附件原名查——原名含清洗字符时查不到既有行，覆盖
// 语义退化成同名两行）；全程入写串行链（同下载壳）。末参 dir（缺省 '' = 根）：dir 闸 →
// (dir, name) 查重 → 子文件夹段名冲突检查 → 目录隐式创建 → 物理路径随 dir
export interface ImportOutcome {
  ok: boolean;
  errorText: string;
  name: string;
  size: number;
  // 覆盖路命中非本会话归属时的注记档（判据单源 workspaceOverwriteKindOf，取值经既有行
  // conversationId 在覆盖前算出——upsert 后新行归属已改写，故必须在覆盖判定处取值）；新建
  // 路与失败态缺省 undefined，回执按空串不注记
  overwriteKind?: string;
}

export const WORKSPACE_IMPORT_MAX_BYTES: number = 30 * 1024 * 1024;

export function importAttachmentToWorkspace(sourceRow: AttachmentListRow,
  conversationId: string, assistantId: string,
  dir: string = ''): Promise<ImportOutcome> {
  return runWriteQueued('importAttachmentToWorkspace', async (): Promise<ImportOutcome> => {
    const failed = (text: string): ImportOutcome => ({ ok: false, errorText: text, name: '', size: 0 });
    const dirReject: string = workspaceDirRejectReason(dir);
    if (dirReject !== '') {
      return failed(dirReject);
    }
    const filesDir: string = workspaceFilesDir();
    if (filesDir === '') {
      return failed('工作区目录未就绪，无法保存文件');
    }
    if (sourceRow.size > WORKSPACE_IMPORT_MAX_BYTES) {
      return failed('附件超过 ' + (WORKSPACE_IMPORT_MAX_BYTES / (1024 * 1024)) +
        'MB 的导入上限，无法存入工作区');
    }
    const srcAbs: string = filesDir + '/' + sourceRow.localPath;
    // 落库名（清洗在此定稿——覆盖判定与行构建用同一份名，两处同源）
    const displayName: string = sanitizeWorkspaceName(sourceRow.name);
    // 同名覆盖判定（(dir, name) 二元组；跨目录同名各存一份不互扰）
    const matches: WorkspaceFileRow[] = await queryWorkspaceFilesByName(dir, displayName);
    if (matches.length > 1) {
      return failed('工作区' + (dir === '' ? '根目录' : '「' + dir + '」目录') +
        '存在多个名为「' + displayName + '」的文件（数据异常），无法保存');
    }
    const existing: WorkspaceFileRow | undefined = matches.length === 1 ? matches[0] : undefined;
    // 子文件夹段名冲突 + 目录链逐段 + 物理探测兜底（与 write 路同款三层把守——附件名与既有
    // 文件夹同名时静默落库会制造「同名文件 × 文件夹」二义态，该显示名下 rename/move/delete/
    // write 此后全被定位面拒；判据与 write 路单源同款〔dirChildSegments 内存派生，禁 SQL
    // LIKE〕，文案亦同；全表一次查两检查共用）
    const allRowsImp: WorkspaceFileRow[] = await queryWorkspaceFiles(WORKSPACE_ROWS_READ_MAX);
    if (dirChildSegments(allRowsImp, dir).indexOf(displayName) >= 0) {
      return failed('该位置已有同名文件夹，请换一个名称或先删除该文件夹。');
    }
    const chainReject: string = workspaceDirChainReject(allRowsImp, dir);
    if (chainReject !== '') {
      return failed(chainReject);
    }
    if (physicalWorkspaceDirExists(filesDir + '/' +
      relativeWorkspacePath(dir, displayName))) {
      return failed('该位置已有同名文件夹，请换一个名称或先删除该文件夹。');
    }
    const total = await queryWorkspaceTotal();
    const capacityReason: string = existing !== undefined ?
      workspaceCapacityReason(sourceRow.size, total.count - 1, total.bytes - existing.size) :
      workspaceCapacityReason(sourceRow.size, total.count, total.bytes);
    if (capacityReason !== '') {
      return failed(capacityReason);
    }
    const fileId: string = existing !== undefined ? existing.id : util.generateRandomUUID(true);
    const row: WorkspaceFileRow = buildWorkspaceRow(fileId, displayName, sourceRow.size,
      WORKSPACE_SOURCE_ASSISTANT, conversationId, assistantId, Date.now(),
      sourceRow.kind === '' ? 'other' : sourceRow.kind, dir);
    // 目录就绪（首次工作区操作即导入时目录未建，不先行建即 openSync ENOENT；隐式创建含
    // dir 全中间层）+ 目录行铸造（隐式建目录的入账面，经 ChatDb 委托口——本壳无 db 句柄；
    // 仍在写链内）
    let dirAbs: string = '';
    try {
      dirAbs = ensureWorkspaceDir(dir);
      await ensureWorkspaceDirRowsOp(dir, WORKSPACE_SOURCE_ASSISTANT, conversationId,
        assistantId);
    } catch (e) {
      return failed('文件拷贝失败：' + (e as Error).message);
    }
    const absPath: string = dirAbs + '/' +
      row.localPath.substring(row.localPath.lastIndexOf('/') + 1);
    // 拷贝（fd 流——30MB 内不整读内存；覆盖路物理名可能随扩展名不同而不同：旧行文件残留
    // 由「清空工作区」兜底清，行 localPath 指向新文件为准）
    const src: fs.File = fs.openSync(srcAbs, fs.OpenMode.READ_ONLY);
    try {
      const dest: fs.File = fs.openSync(absPath, fs.OpenMode.READ_WRITE |
        fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.copyFileSync(src.fd, dest.fd);
      } finally {
        fs.closeSync(dest);
      }
    } catch (e) {
      if (existing === undefined) {
        try {
          fs.unlinkSync(absPath);
        } catch {
          // 残留由清空工作区兜底，不吞原始错误
        }
      }
      return failed('文件拷贝失败：' + (e as Error).message);
    } finally {
      fs.closeSync(src);
    }
    // 行 upsert（覆盖沿用既有 id〔追溯列随新行值重写〕；新建铸新 id——先落文件后写行铁律，
    // 行写失败自清仅新建路〔覆盖路旧行仍在，自清会毁用户旧文件，残留由重试收敛〕）
    try {
      await upsertWorkspaceFile(row);
    } catch (e) {
      if (existing === undefined) {
        try {
          fs.unlinkSync(absPath);
        } catch {
          // 残留由清空工作区兜底，不吞原始错误
        }
      }
      return failed('工作区记录写入失败：' + (e as Error).message);
    }
    return { ok: true, errorText: '', name: row.name, size: row.size,
      // 覆盖注记档：覆盖判定处的既有行归属与本次导入会话比对（existing 仍是 old 行——
      // upsert 未发生，新行归属改写不影响本值）
      overwriteKind: existing !== undefined ?
        workspaceOverwriteKindOf(existing.conversationId, conversationId) : '' };
  });
}
