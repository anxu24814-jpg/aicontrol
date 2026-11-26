// DS 历史归档的纯函数域（DS 全家桶二期 S1 自 DsHistoryZip 域级最小拆分迁出）。
// 一句话职责 =「三闸判据 + 原始 JSON → 可导入全树会话」——纯函数面，零 IO 零 kit 依赖
//（解压/读取/枚举在 DsHistoryZip；本件只吃文本与原始对象）。
// · 拆出理由（宪法 1200 硬线）：S1 真保真新增联网片段映射、全树建树与分支头产出后，
//   DsHistoryZip 剔头超线；按「域级最小拆分」把纯映射段整体外迁，IO 壳一行不动。
// · 纯函数面（断言直跑 = assert-ds-integration 己组）：本件零 import，剥注释即可直跑。
// · 两个 DS 工具类型字面量在本件内镜像（与 DsServerTools 同值）——直跑面不能依赖 import
//   绑定，取同值镜像 + 断言逐字比对（先例 = ChatAnswerChoice 镜像库侧词表）。
// · 归档结构与映射口径的完整说明见 DsHistoryZip 文件头（本件不重复）。

// ── 三闸常量（代决 7 版本闸与体积闸；格式版本单源 = demo format.ts EXPORT_FORMAT_VERSION）──
export const DS_EXPORT_FORMAT_VERSION: number = 3;
export const DS_ZIP_MAX_TOTAL_BYTES: number = 512 * 1024 * 1024;
export const DS_JSON_MAX_BYTES: number = 20 * 1024 * 1024;

// ── 解析产物类型（预览三态计数与落库输入共用同一份结构）──

// 图片条目（FILE 片段 is_image=true 且 export_path 非空者；sourceAbs 由 IO 面配对后回填）
export interface DsParsedImage {
  name: string;
  sizeBytes: number;
  mime: string;
  // zip 条目名（chat_sessions/{sid}_files/{fid}_{fname} 形态；'' = 未导出/不配对）
  exportRel: string;
  // 解压根下的绝对路径（'' = 未配对）；present = 配对成功且文件在场非空
  sourceAbs: string;
  present: boolean;
}

// 消息节点（全树；落库一行 + 可挂多图 + 联网过程串）
export interface DsParsedMessage {
  dsId: number; // DS 归档内消息 id（分支表与父链按此定位）
  parentDsId: number | null; // null = 根
  role: string; // 'user' | 'assistant'
  content: string;
  reasoning: string;
  status: string; // 'done' | 'error'（库行词表）
  createdAtMs: number;
  images: DsParsedImage[];
  serverToolsJson: string; // {"server_tool_calls":[…]} —— '' = 本节点无联网过程
}

// 分支头（一条分支 = 根到该点头的路径；activeBranchId 指向 head = 当前停留点那条）
export interface DsParsedBranch {
  headDsId: number;
  createdAtMs: number;
}

// 全树会话（messages = 全树节点按 DS id 升序；落库 seq 同序 ⇒ 父先于子）
export interface DsParsedSession {
  dsId: string;
  title: string; // '' = DS 侧无标题
  createdAtMs: number;
  updatedAtMs: number;
  messages: DsParsedMessage[];
  branches: DsParsedBranch[];
  currentDsId: number; // 用户当前停留的消息（DS current_message_id）
}

// 聚合呈报面（预览态出说明行；坏点计数与成功计数严格分账）
export interface DsParseReport {
  sessionCount: number;
  messageCount: number; // 全树节点数（含各版本分支）
  imageCount: number; // 配对成功的图片数（缺失图不计）
  brokenChainSessions: number; // 父链断裂/环的会话数（截断线照导；整会话跳过的另计下一项）
  missingCurrentSessions: number; // 找不到当前停留消息被整会话跳过的会话数（自检轮分账）
  badSessions: number; // 会话容器字段不合法被跳过的会话数
  badMessageRows: number; // 消息行字段不合法被跳过的行数
  duplicateMessageRows: number; // 同 id 重号被丢弃的消息行数（自检轮分账——此前静默丢）
  droppedFragments: number; // 仍不支持/校验失败的内容片段数
  preservedToolFragments: number; // 联网过程片段已保留段数（步骤行与来源卡料）
  missingImages: number; // FILE 片段声明但包内缺失/未导出的图片数
  missingSessionFiles: number; // 索引列出而包内无文件的会话数
  oversizedSessions: number; // 节点数超上限被整会话拒绝的会话数
  oversizedMaxNodes: number; // 其中最大的节点数（提示「实际 N 个节点」）
}

export interface DsParsedArchive {
  sessions: DsParsedSession[];
  report: DsParseReport;
}

// 解析句柄（rootDir 交调用方 finally 释放——见文件头成对释放说明）
export interface DsParsedZip {
  archive: DsParsedArchive;
  rootDir: string;
}

// 原始行解析计数器（解析链内累积，产物落 report）
export interface DsParseCounters {
  badSessions: number;
  brokenChainSessions: number; // 断链/环会话数（dsParseSessionText 内累计，与 badSessions 分账）
  missingCurrentSessions: number; // 当前停留消息缺失 → 整会话跳过（与上一项分账，呈报口径不同）
  badMessageRows: number;
  duplicateMessageRows: number; // 同 id 重号丢弃行数（与 badMessageRows 分账）
  droppedFragments: number;
  preservedToolFragments: number;
  oversizedSessions: number;
  oversizedMaxNodes: number;
}

// 单会话节点数上限（代决：超限整会话拒绝，不截断——截断产半残消息树比拒绝更糟）。
// 页面提示与解析侧引用同一常量（单源）。
export const DS_IMPORT_MAX_NODES: number = 3000;

// DS 官方服务端工具类型字面量镜像（与 DsServerTools 两常量同值；本件直跑面不能引 import，
// 断言逐字比对守漂移——先例 = ChatAnswerChoice 镜像库侧词表）
const DS_TOOL_TYPE_SEARCH: string = 'deepseek_web_search';
const DS_TOOL_TYPE_READ: string = 'deepseek_read_url';

// ── 纯函数面（断言直跑）──

// 白名单路径模式判据（读什么 + export_path 配对安全闸共用）。四类模式：
// manifest.json / chat_session_index.json / chat_sessions/*.json / chat_sessions/*_files/*。
// 穿越防御：'..' 段、绝对路径、反斜杠、空段一律 false（zip 条目名不可信，先判形态再判模式）。
export function dsZipPathAllowed(relPath: string): boolean {
  if (relPath === '' || relPath.length > 512) {
    return false;
  }
  if (relPath.indexOf('\\') >= 0 || relPath.startsWith('/') || relPath.indexOf('//') >= 0) {
    return false;
  }
  const segments: string[] = relPath.split('/');
  for (const seg of segments) {
    if (seg === '' || seg === '.' || seg === '..') {
      return false;
    }
  }
  if (segments.length === 1) {
    return segments[0] === 'manifest.json' || segments[0] === 'chat_session_index.json';
  }
  // 会话 JSON = chat_sessions/{sid}.json 两段（README 归档结构第二类；条目名 = 会话 id 拼装，
  // 禁 _files 目录名混入——那是图片目录形态，且 .json 结尾的图片条目不在此通道）
  if (segments.length === 2 && segments[0] === 'chat_sessions') {
    return segments[1] !== '' && segments[1].endsWith('.json') && !segments[1].endsWith('_files');
  }
  // 图片 = chat_sessions/{sid}_files/{file_id}_{file_name} 三段（README 归档结构第四类；
  // 条目名不限定扩展名——DS 侧按 FILE.export_path 原样配对）
  if (segments.length === 3 && segments[0] === 'chat_sessions') {
    return segments[1].endsWith('_files') && segments[1].length > '_files'.length &&
      segments[2] !== '';
  }
  return false;
}

// zip 解包累计体积闸（'' = 放行，非空 = 中文拒收理由）
export function dsZipTotalSizeVerdict(totalBytes: number): string {
  if (totalBytes > DS_ZIP_MAX_TOTAL_BYTES) {
    return '备份包解包后超过 512MB 上限，已取消导入';
  }
  return '';
}

// 单 JSON 体积闸（'' = 放行，非空 = 中文拒收理由）
export function dsJsonSizeVerdict(fileBytes: number): string {
  if (fileBytes > DS_JSON_MAX_BYTES) {
    return '备份包内有文件超过 20MB 上限，已取消导入';
  }
  return '';
}

// ZIP 中央目录累计解压字节（解压前体积闸的判据面，纯函数）：cd = 中央目录原始字节，
// entryCount = EOCD 声明条目数。逐条读 uncompressed size（中央目录项 offset 24）累加；
// 签名错位/越界/ZIP64 标记（0xFFFFFFFF）回 -1 = 不预判，交解压后闸兜底。★ 这是包头
// **声明值**（恶意包可谎报），故只作早退闸，解压后 dsWalkTotalBytes 仍保留（双层闸）。
export function dsZipCentralDirTotal(cd: ArrayBuffer, entryCount: number): number {
  if (entryCount <= 0 || entryCount > 200000) {
    return -1;
  }
  const view: DataView = new DataView(cd);
  let offset: number = 0;
  let total: number = 0;
  for (let i = 0; i < entryCount; i++) {
    if (offset + 46 > cd.byteLength) {
      return -1;
    }
    if (view.getUint32(offset, true) !== 0x02014b50) { // PK\x01\x02
      return -1;
    }
    const uncompressed: number = view.getUint32(offset + 24, true);
    if (uncompressed === 0xffffffff) {
      return -1; // ZIP64：不预判
    }
    total += uncompressed;
    if (total > DS_ZIP_MAX_TOTAL_BYTES) {
      return total; // 已超限，无需继续扫
    }
    const nameLen: number = view.getUint16(offset + 28, true);
    const extraLen: number = view.getUint16(offset + 30, true);
    const commentLen: number = view.getUint16(offset + 32, true);
    offset += 46 + nameLen + extraLen + commentLen;
  }
  return total;
}

// manifest 版本闸（'' = 放行，非空 = 中文拒收理由；≠3 一律拒——只支持当前数据格式，
// demo 口径「不提供旧数据库迁移」，新旧版本都不导入）
export function dsManifestVerdict(value: Object | null): string {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    return '备份包不是合法的 DeepSeek 导出格式，已取消导入';
  }
  const rec: Record<string, Object> = value as Record<string, Object>;
  const v: Object | undefined = rec['export_format_version'];
  if (typeof v !== 'number' || !Number.isFinite(v) || v !== DS_EXPORT_FORMAT_VERSION) {
    return '备份包版本不受支持，仅支持版本 3 的 DeepSeek 导出包';
  }
  return '';
}

// DS 时间 → epoch 毫秒（NaN = 不合法）。RFC 3339 Z 结尾可选小数秒；小数秒截断到 3 位再
// 交 Date.parse（demo 同款补齐截断口径——各引擎对 >3 位小数的解析行为不一，先归一保证一致）
export function dsTimeToMs(value: Object): number {
  if (typeof value !== 'string') {
    return Number.NaN;
  }
  const m: RegExpExecArray | null =
    /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d+))?Z$/.exec(value);
  if (m === null) {
    return Number.NaN;
  }
  const frac: string = ((m[2] ?? '') + '000').substring(0, 3);
  const normalized: string = m[1] + '.' + frac + 'Z';
  const ms: number = Date.parse(normalized);
  return Number.isFinite(ms) ? ms : Number.NaN;
}

// 非负安全整数判据（u32 语义 id/count 共用）
function dsIsCount(value: Object): boolean {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;
}

// 扩展名（不含点、全小写；无扩展名回 ''）
export function dsExtOf(name: string): string {
  const cut: number = name.lastIndexOf('.');
  if (cut < 0 || cut < name.lastIndexOf('/')) {
    return '';
  }
  return name.substring(cut + 1).toLowerCase();
}

// 图片 MIME（扩展名派生；未知兜底 octet-stream——kind 由落库面定 'image'，mime 仅展示与
// 桥输入口径。demo 口径「无法识别时仍按图片处理」，这里不因 mime 未知拒收）
export function dsImageMimeOf(name: string): string {
  const ext: string = dsExtOf(name);
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
  return 'application/octet-stream';
}

// ── 原始行宽松读面（字段不合法 = 该行/该片段进计数器，不上抛）──

// FILE 片段的图片条目（is_image=true 才收——非图片附件 DS 导出无本体，落库即坏泡，不导入）
interface DsRawFileEntry {
  fileName: string;
  sizeBytes: number;
  exportRel: string; // '' = 未导出
}

// 会话 JSON 的单条原始消息（宽松读后、建树前）
interface DsRawMessage {
  id: number;
  parentId: number | null;
  role: string; // 'USER' | 'ASSISTANT'（照 DS 词表，映射面转小写）
  status: string;
  createdAtMs: number;
  textParts: string[]; // REQUEST / RESPONSE / TEMPLATE_RESPONSE 载荷按序
  thinkParts: string[]; // THINK 载荷按序
  images: DsRawFileEntry[];
  tools: DsToolFrag[]; // 联网过程片段按序（TOOL_SEARCH / TOOL_OPEN / TOOL_FIND / READ_LINK /
  // TOOL_IMAGE_SEARCH 映射产物，S1 新增）
}

// 单片段宽松读产物（text/think/files/tools 四通道按片段类型恰一非空——匿名对象字面量类型
// 在 ArkTS 禁用，落显式接口）
interface DsRawFragment {
  text: string | null;
  think: string | null;
  files: DsRawFileEntry[] | null;
  tools: DsToolFrag[];
}

// 来源条目种子（SearchResult / ImageSearchResult 归一后的渲染料；url 已过 http(s) 准入）
interface DsSourceSeed {
  url: string;
  title: string;
  snippet: string;
  siteName: string;
  publishedAt: string;
}

// 单个联网过程片段（归一动作；展示与落库都从本结构派生 call JSON）
interface DsToolFrag {
  action: string; // 'search' | 'open_page' | 'find_in_page' | 'read_link'
  image: boolean; // 图搜（action=search 且 kind=image_search）
  status: string; // 'completed' | 'failed' | 'in_progress'
  queries: string[];
  url: string;
  title: string;
  publishedAt: string;
  pattern: string;
  results: DsSourceSeed[];
}

// 可选字符串字段（非 string / 缺省 → ''）
function dsOptStringOf(value: Object | undefined): string {
  return typeof value === 'string' ? value : '';
}

// 链接准入（链接会渲染成可点 URL——只接受 http / https，其余按空串丢弃；与 demo isWebUrl 口径
// 一致，不新增 URL 解析面：前缀判定足够且零异常路径）
function dsHttpUrlOf(value: Object | undefined): string {
  if (typeof value !== 'string') {
    return '';
  }
  const t: string = value.trim();
  if (t.startsWith('http://') || t.startsWith('https://')) {
    return t;
  }
  return '';
}

// 字符串数组读取（非数组 / 非字符串项跳过）
function dsStringListOf(value: Object | undefined): string[] {
  const out: string[] = [];
  if (!Array.isArray(value)) {
    return out;
  }
  for (const item of value as Object[]) {
    if (typeof item === 'string' && item !== '') {
      out.push(item);
    }
  }
  return out;
}

// DS 工具状态 → 官方 call status 词表（FINISHED/NO_RESULT → completed、FAILED → failed、
// WIP → in_progress；缺省与未知按 completed——已归档内容按完成态展示，与 demo 宽容口径一致）
function dsToolStatusOf(value: Object | undefined): string {
  if (value === 'FAILED') {
    return 'failed';
  }
  if (value === 'WIP') {
    return 'in_progress';
  }
  return 'completed';
}

// 搜索结果数组归一（url 过 http(s) 准入，缺 url 的条目跳过；站点名/发布时间仅展示料）
function dsSourceSeedsOf(value: Object | undefined, urlKey: string): DsSourceSeed[] {
  const out: DsSourceSeed[] = [];
  if (!Array.isArray(value)) {
    return out;
  }
  for (const item of value as Object[]) {
    if (item === null || typeof item !== 'object' || Array.isArray(item)) {
      continue;
    }
    const rec: Record<string, Object> = item as Record<string, Object>;
    const url: string = dsHttpUrlOf(rec[urlKey]);
    if (url === '') {
      continue;
    }
    out.push({
      url: url,
      title: dsOptStringOf(rec['title']),
      snippet: dsOptStringOf(rec['snippet']),
      siteName: dsOptStringOf(rec['site_name']),
      publishedAt: dsOptStringOf(rec['published_at'])
    });
  }
  return out;
}

// 联网过程片段 → 归一动作（空数组 = 该片段无展示面：无链接的 TOOL_OPEN / 无合法 url 的
// READ_LINK 照 demo 口径丢弃；未知类型也回空）。READ_LINK 一条片段可含多个结果 → 多动作
// （每个结果自成一 call，与实时链「一步一调用」同形）。
function dsToolFragsOf(type: string, rec: Record<string, Object>): DsToolFrag[] {
  const out: DsToolFrag[] = [];
  if (type === 'TOOL_SEARCH') {
    out.push({
      action: 'search', image: false, status: dsToolStatusOf(rec['status']),
      queries: dsStringListOf(rec['queries']), url: '', title: '', publishedAt: '', pattern: '',
      results: dsSourceSeedsOf(rec['results'], 'url')
    });
    return out;
  }
  if (type === 'TOOL_OPEN') {
    const url: string = dsHttpUrlOf(rec['url']);
    if (url === '') {
      return out; // 无链接的打开步骤无展示面（demo 同口径）
    }
    out.push({
      action: 'open_page', image: false, status: dsToolStatusOf(rec['status']),
      queries: [], url: url, title: dsOptStringOf(rec['title']),
      publishedAt: dsOptStringOf(rec['published_at']), pattern: '', results: []
    });
    return out;
  }
  if (type === 'TOOL_FIND') {
    out.push({
      action: 'find_in_page', image: false, status: dsToolStatusOf(rec['status']),
      queries: [], url: '', title: '', publishedAt: '',
      pattern: dsOptStringOf(rec['pattern']), results: []
    });
    return out;
  }
  if (type === 'TOOL_IMAGE_SEARCH') {
    out.push({
      action: 'search', image: true, status: dsToolStatusOf(rec['status']),
      queries: [], url: '', title: '', publishedAt: '', pattern: '',
      results: dsSourceSeedsOf(rec['results'], 'source_page_url')
    });
    return out;
  }
  if (type === 'READ_LINK') {
    const results: Object | undefined = rec['results'];
    if (!Array.isArray(results)) {
      return out;
    }
    for (const item of results as Object[]) {
      if (item === null || typeof item !== 'object' || Array.isArray(item)) {
        continue;
      }
      const rr: Record<string, Object> = item as Record<string, Object>;
      const url: string = dsHttpUrlOf(rr['url']);
      if (url === '') {
        continue; // 仅签名的结果无展示面且本批不存 signature（方案档 §4.1 拍板）
      }
      out.push({
        action: 'read_link', image: false, status: 'completed', queries: [], url: url,
        title: dsOptStringOf(rr['title']), publishedAt: '', pattern: '', results: []
      });
    }
    return out;
  }
  return out;
}

// 单片段宽松读：type 不在保真/丢弃白名单、或消费面字段不合法 → 返 null 计 droppedFragments。
// 联网过程五类 → DsToolFrag 列表（非空计 preservedToolFragments）；TIP / CONTENT_RISK /
// PARTIAL_FILE_READ / 其余未知类型 → 丢弃计数。FILE 片段整体读（条目级不合法 → 整片段丢，
// 照 demo「单个内容片段不兼容不影响其余消息」）
function dsRawFragmentOf(value: Object, counters: DsParseCounters): DsRawFragment | null {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    counters.droppedFragments++;
    return null;
  }
  const rec: Record<string, Object> = value as Record<string, Object>;
  const typeValue: Object | undefined = rec['type'];
  if (typeof typeValue !== 'string') {
    counters.droppedFragments++;
    return null;
  }
  const type: string = typeValue;
  if (type === 'REQUEST' || type === 'RESPONSE' || type === 'TEMPLATE_RESPONSE') {
    const c: Object | undefined = rec['content'];
    if (typeof c !== 'string') {
      counters.droppedFragments++;
      return null;
    }
    return { text: c, think: null, files: null, tools: [] };
  }
  if (type === 'THINK') {
    const c: Object | undefined = rec['content'];
    if (typeof c !== 'string') {
      counters.droppedFragments++;
      return null;
    }
    return { text: null, think: c, files: null, tools: [] };
  }
  if (type === 'FILE') {
    const filesValue: Object | undefined = rec['files'];
    if (!Array.isArray(filesValue)) {
      counters.droppedFragments++;
      return null;
    }
    const files: DsRawFileEntry[] = [];
    for (const item of filesValue as Object[]) {
      if (item === null || typeof item !== 'object' || Array.isArray(item)) {
        counters.droppedFragments++;
        return null;
      }
      const fr: Record<string, Object> = item as Record<string, Object>;
      const nameValue: Object | undefined = fr['file_name'];
      const sizeValue: Object | undefined = fr['file_size'];
      const isImageValue: Object | undefined = fr['is_image'];
      const exportValue: Object | undefined = fr['export_path'];
      if (typeof nameValue !== 'string' || nameValue === '' ||
        !dsIsCount(sizeValue === undefined ? -1 : (sizeValue as number)) ||
        typeof isImageValue !== 'boolean') {
        counters.droppedFragments++;
        return null;
      }
      if (isImageValue as boolean) {
        // export_path：null 或缺省 = 未导出（''）；字符串 = 条目名
        let exportRel: string = '';
        if (typeof exportValue === 'string') {
          exportRel = exportValue;
        }
        files.push({ fileName: nameValue, sizeBytes: sizeValue as number, exportRel: exportRel });
      }
      // 非图片条目仅元数据（DS 导出无本体），不收——见 DsRawFileEntry 注释
    }
    return { text: null, think: null, files: files, tools: [] };
  }
  const tools: DsToolFrag[] = dsToolFragsOf(type, rec);
  if (tools.length > 0) {
    counters.preservedToolFragments += tools.length;
    return { text: null, think: null, files: null, tools: tools };
  }
  // 丢弃族：TIP / CONTENT_RISK / PARTIAL_FILE_READ / 无展示面的联网片段 / 其余未知类型
  counters.droppedFragments++;
  return null;
}

// 单消息宽松读：消费面字段严格校验（id/parent/role/status/时间/片段表），不消费字段
// （thinking_enabled/search_enabled/accumulated_token_usage）不校验——宽容导入，坏字段
// 不炸好包（与 demo 严格 schema 的差异 = 有意为之，本件头注释导入映射口径节）
function dsRawMessageOf(value: Object, counters: DsParseCounters): DsRawMessage | null {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    counters.badMessageRows++;
    return null;
  }
  const rec: Record<string, Object> = value as Record<string, Object>;
  const idValue: Object | undefined = rec['id'];
  const parentValue: Object | undefined = rec['parent_id'];
  const roleValue: Object | undefined = rec['role'];
  const statusValue: Object | undefined = rec['status'];
  const timeValue: Object | undefined = rec['inserted_at'];
  const fragsValue: Object | undefined = rec['fragments'];
  if (!dsIsCount(idValue === undefined ? -1 : (idValue as number))) {
    counters.badMessageRows++;
    return null;
  }
  let parentId: number | null = null;
  if (parentValue !== undefined && parentValue !== null) {
    if (!dsIsCount(parentValue)) {
      counters.badMessageRows++;
      return null;
    }
    parentId = parentValue as number;
  }
  if (roleValue !== 'USER' && roleValue !== 'ASSISTANT') {
    counters.badMessageRows++;
    return null;
  }
  if (typeof statusValue !== 'string') {
    counters.badMessageRows++;
    return null;
  }
  const createdAtMs: number = timeValue === undefined ? Number.NaN : dsTimeToMs(timeValue);
  if (Number.isNaN(createdAtMs)) {
    counters.badMessageRows++;
    return null;
  }
  if (!Array.isArray(fragsValue)) {
    counters.badMessageRows++;
    return null;
  }
  const textParts: string[] = [];
  const thinkParts: string[] = [];
  const images: DsRawFileEntry[] = [];
  const tools: DsToolFrag[] = [];
  for (const item of fragsValue as Object[]) {
    const frag = dsRawFragmentOf(item, counters);
    if (frag === null) {
      continue; // 坏片段/丢弃族已计数
    }
    if (frag.text !== null) {
      textParts.push(frag.text);
    }
    if (frag.think !== null) {
      thinkParts.push(frag.think);
    }
    if (frag.files !== null) {
      for (const f of frag.files) {
        images.push(f);
      }
    }
    for (const t of frag.tools) {
      tools.push(t);
    }
  }
  return {
    id: idValue as number,
    parentId: parentId,
    role: roleValue as string,
    status: statusValue as string,
    createdAtMs: createdAtMs,
    textParts: textParts,
    thinkParts: thinkParts,
    images: images,
    tools: tools
  };
}

// ── 全树建树 + 分支头（S1 真保真）──
// 输出四件：nodes = 全树可达节点按 id 升序（父先于子，落库 seq 同序）；branchHeads = 分支头
// （当前停留点 + 每个「非选中子节点」的选中链最深后代，按 id 升序）；currentId = 有效当前
// 消息（0 = 不在树内，调用方整会话跳过并计断链）；broken = 父缺失 / 环 / 当前消息缺失
// （照导不炸包）。「选中子」= 当前路径上的子优先、否则最大 id（DS 归档 id 单调 ⇒ 最后生成
// 的版本）——与 demo buildTree「其余节点默认选中 id 最大的子消息」同口径。
// 纯函数，断言直跑。
export interface DsTreeResult {
  nodes: DsRawMessage[];
  branchHeads: number[];
  currentId: number;
  broken: boolean;
  duplicates: number; // 同 id 重号被丢弃的行数（呈报分账用；首见为准）
}

export function dsTreeOf(messages: DsRawMessage[], currentId: number): DsTreeResult {
  const sorted: DsRawMessage[] = messages.slice();
  sorted.sort((a: DsRawMessage, b: DsRawMessage): number => a.id - b.id);
  const byId: Map<number, DsRawMessage> = new Map<number, DsRawMessage>();
  const unique: DsRawMessage[] = [];
  let duplicates: number = 0; // 自检轮补：此前 continue 静默丢，预览总数差额无呈报
  for (const m of sorted) {
    if (byId.has(m.id)) {
      duplicates++;
      continue; // 重号脏形态：首见为准（后写覆盖会让同 id 的父链语义不确定）
    }
    byId.set(m.id, m);
    unique.push(m);
  }
  let broken: boolean = false;
  const childMap: Map<number, number[]> = new Map<number, number[]>();
  const roots: number[] = [];
  for (const m of unique) {
    const parent: number | null = m.parentId;
    if (parent === null) {
      roots.push(m.id);
      continue;
    }
    if (parent === m.id || !byId.has(parent)) {
      broken = true; // 自环 / 父缺失——当根照导（内容不丢）
      roots.push(m.id);
      continue;
    }
    const kids: number[] = childMap.get(parent) ?? [];
    kids.push(m.id); // unique 已按 id 升序 ⇒ 每父子表升序
    childMap.set(parent, kids);
  }
  // 当前路径集（环/断链上行走不动即停——路径只用于「选中子优先」，残缺不致错）
  const currentExists: boolean = currentId > 0 && byId.has(currentId);
  if (!currentExists) {
    broken = true;
  }
  const onPath: Set<number> = new Set<number>();
  if (currentExists) {
    let cursor: number = currentId;
    while (!onPath.has(cursor)) {
      onPath.add(cursor);
      const node: DsRawMessage | undefined = byId.get(cursor);
      if (node === undefined || node.parentId === null) {
        break;
      }
      cursor = node.parentId;
    }
  }
  const selectedOf = (parent: number): number => {
    const kids: number[] = childMap.get(parent) ?? [];
    if (kids.length === 0) {
      return 0;
    }
    for (const kid of kids) {
      if (onPath.has(kid)) {
        const k: DsRawMessage | undefined = byId.get(kid);
        if (k !== undefined && k.parentId === parent) {
          return kid;
        }
      }
    }
    return kids[kids.length - 1];
  };
  const deepestOf = (start: number): number => {
    let cursor: number = start;
    const guard: Set<number> = new Set<number>();
    while (!guard.has(cursor)) {
      guard.add(cursor);
      const next: number = selectedOf(cursor);
      if (next === 0) {
        return cursor;
      }
      cursor = next;
    }
    return cursor; // 环兜底：停在重复点
  };
  const heads: Set<number> = new Set<number>();
  if (currentExists) {
    heads.add(currentId);
  }
  childMap.forEach((kids: number[], parent: number): void => {
    const chosen: number = selectedOf(parent);
    for (const kid of kids) {
      if (kid !== chosen) {
        heads.add(deepestOf(kid));
      }
    }
  });
  // 可达集（根 + 环兜底伪根——环内节点互为父、无根可达，按 id 升序各补一次）
  const visited: Set<number> = new Set<number>();
  const collect = (start: number): void => {
    const stack: number[] = [start];
    while (stack.length > 0) {
      const id: number = stack.pop() as number;
      if (visited.has(id)) {
        continue;
      }
      visited.add(id);
      const kids: number[] = childMap.get(id) ?? [];
      for (const kid of kids) {
        if (!visited.has(kid)) {
          stack.push(kid);
        }
      }
    }
  };
  for (const r of roots) {
    collect(r);
  }
  for (const m of unique) {
    if (!visited.has(m.id)) {
      broken = true; // 环：无根可达
      collect(m.id);
    }
  }
  const nodes: DsRawMessage[] = [];
  for (const m of unique) {
    if (visited.has(m.id)) {
      nodes.push(m);
    }
  }
  const branchHeads: number[] = [];
  heads.forEach((id: number): void => {
    if (visited.has(id)) {
      branchHeads.push(id);
    }
  });
  branchHeads.sort((a: number, b: number): number => a - b);
  return { nodes: nodes, branchHeads: branchHeads,
    currentId: currentExists ? currentId : 0, broken: broken, duplicates: duplicates };
}

// 消息状态映射（demo toLocal 口径收敛到库行词表 done/error——streaming 不可能是导入产物）：
// 错误族 FAILED/CONTEXT_LENGTH_EXCEEDED/TIMEOUT 与拒绝 CONTENT_FILTER → 'error'（正文与
// 模板文案保真在 content，行级状态只驱动错误展示面）；FINISHED 与已停族 INCOMPLETE/WIP →
// 'done'——本应用停止轮的行态也落 done（cancelled 显示态由本应用自身机制派生，导入数据无
// 该信号），且 demo 口径已停轮有正文可进上下文，标 done 语义一致；其余（含未知新值）→
// 'done' 宽容导入
function dsRowStatusOf(dsStatus: string): string {
  if (dsStatus === 'FAILED' || dsStatus === 'CONTEXT_LENGTH_EXCEEDED' ||
    dsStatus === 'TIMEOUT' || dsStatus === 'CONTENT_FILTER') {
    return 'error';
  }
  return 'done';
}

// 联网动作 → 官方 call 对象（渲染面三纯函数 dsStepTitleOf / serverStepStateOf /
// dsSourceEntriesOf 的吃入形态：type / kind / action / status / sources / page）。
// kind = read_link（读链接）/ image_search（图搜）/ 本消息搜索系（deep_search 当同消息含
// 打开或页内查找，否则 search——demo toLocal 同判据）。
function dsCallOf(frag: DsToolFrag, searchKind: string): Record<string, Object> {
  const action: Record<string, Object> = {};
  action['type'] = frag.action;
  if (frag.action === 'search') {
    action['queries'] = frag.queries;
  } else if (frag.action === 'open_page' || frag.action === 'read_link') {
    action['url'] = frag.url;
  } else if (frag.action === 'find_in_page') {
    action['url'] = '';
    action['pattern'] = frag.pattern;
  }
  const call: Record<string, Object> = {};
  call['type'] = frag.action === 'read_link' ? DS_TOOL_TYPE_READ : DS_TOOL_TYPE_SEARCH;
  if (frag.action === 'read_link') {
    call['kind'] = 'read_link';
  } else if (frag.image) {
    call['kind'] = 'image_search';
  } else {
    call['kind'] = searchKind;
  }
  call['action'] = action;
  call['status'] = frag.status;
  if (frag.results.length > 0) {
    const sources: Record<string, Object>[] = [];
    for (const r of frag.results) {
      const s: Record<string, Object> = {};
      s['url'] = r.url;
      s['title'] = r.title;
      s['snippet'] = r.snippet;
      if (r.siteName !== '') {
        s['site_name'] = r.siteName;
      }
      if (r.publishedAt !== '') {
        s['published_at'] = r.publishedAt;
      }
      sources.push(s);
    }
    call['sources'] = sources;
  }
  // 读链接 / 打开网页的页面信息（来源卡 page 段；完成态才挂——失败轮无页面可指）
  if ((frag.action === 'read_link' || frag.action === 'open_page') &&
    frag.status === 'completed') {
    const page: Record<string, Object> = {};
    page['url'] = frag.url;
    page['title'] = frag.title;
    if (frag.publishedAt !== '') {
      page['published_at'] = frag.publishedAt;
    }
    call['page'] = page;
  }
  return call;
}

// 联网过程片段 → 列载荷串（CC 形态 {"server_tool_calls":[{"index":n,"calls":[call]}]}——
// 一动作一步，与实时链「一个已见 call 自成一文本步」的部分结构同形；回放侧
// dsServerCallJsonsOf 按 step.calls 展开即得每步一行）。空数组回 ''（不写列）。
function dsServerToolsJsonOf(frags: DsToolFrag[]): string {
  if (frags.length === 0) {
    return '';
  }
  let deep: boolean = false;
  for (const f of frags) {
    if (f.action === 'open_page' || f.action === 'find_in_page') {
      deep = true;
    }
  }
  const searchKind: string = deep ? 'deep_search' : 'search';
  const steps: Record<string, Object>[] = [];
  for (let i = 0; i < frags.length; i++) {
    const calls: Record<string, Object>[] = [dsCallOf(frags[i], searchKind)];
    const step: Record<string, Object> = {};
    step['index'] = i;
    step['calls'] = calls;
    steps.push(step);
  }
  const envelope: Record<string, Object> = {};
  envelope['server_tool_calls'] = steps;
  return JSON.stringify(envelope);
}

// 单个树节点 → 可导入消息（正文 = 文本片段按序 \n\n 连接——RESPONSE 与 TEMPLATE_RESPONSE
// 并存时两者都保真；思考 = THINK 按序连接；图 = FILE is_image 条目；联网过程 → server_tools
// 串）。零可展示内容的节点**保留**（空正文）——否则分支父链断裂、多版本无法还原；这类节点
// 的展示沿用现有空正文异常轮口径，纯工具轮由 serverstep 步骤行填充
export function dsMapChainMessage(raw: DsRawMessage): DsParsedMessage {
  const images: DsParsedImage[] = [];
  for (const f of raw.images) {
    images.push({ name: f.fileName, sizeBytes: f.sizeBytes, mime: dsImageMimeOf(f.fileName),
      exportRel: f.exportRel, sourceAbs: '', present: false });
  }
  return {
    dsId: raw.id,
    parentDsId: raw.parentId,
    role: raw.role === 'USER' ? 'user' : 'assistant',
    content: raw.textParts.join('\n\n'),
    reasoning: raw.thinkParts.join('\n\n'),
    status: dsRowStatusOf(raw.status),
    createdAtMs: raw.createdAtMs,
    images: images,
    serverToolsJson: dsServerToolsJsonOf(raw.tools)
  };
}

// 会话文本 → 可导入会话（纯函数，断言直跑；容器级不合法 / 当前消息缺失 → null 并计数，
// 消息行级不合法跳行计数——两账严格分立）。text = chat_sessions/{sid}.json 全文
export function dsParseSessionText(text: string, counters: DsParseCounters): DsParsedSession | null {
  let parsed: Object;
  try {
    parsed = JSON.parse(text) as Object;
  } catch (e) {
    counters.badSessions++;
    return null;
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    counters.badSessions++;
    return null;
  }
  const rec: Record<string, Object> = parsed as Record<string, Object>;
  // 会话 id 条件（照 demo sessionId：非空 + 不含路径分隔符 + 非 . / ..——条目名拼装安全前提）
  const idValue: Object | undefined = rec['id'];
  if (typeof idValue !== 'string' || idValue === '' || idValue === '.' || idValue === '..' ||
    idValue.indexOf('/') >= 0 || idValue.indexOf('\\') >= 0) {
    counters.badSessions++;
    return null;
  }
  const currentIdValue: Object | undefined = rec['current_message_id'];
  if (!dsIsCount(currentIdValue === undefined ? -1 : (currentIdValue as number))) {
    counters.badSessions++;
    return null;
  }
  const insertedMs: number = rec['inserted_at'] === undefined
    ? Number.NaN : dsTimeToMs(rec['inserted_at']);
  const updatedMs: number = rec['updated_at'] === undefined
    ? Number.NaN : dsTimeToMs(rec['updated_at']);
  if (Number.isNaN(insertedMs) || Number.isNaN(updatedMs)) {
    counters.badSessions++;
    return null;
  }
  const messagesValue: Object | undefined = rec['messages'];
  if (!Array.isArray(messagesValue)) {
    counters.badSessions++;
    return null;
  }
  const raws: DsRawMessage[] = [];
  for (const item of messagesValue as Object[]) {
    const row: DsRawMessage | null = dsRawMessageOf(item, counters);
    if (row !== null) {
      raws.push(row);
    }
  }
  // 节点数上限（代决）：超限整会话拒绝并呈报（节点数是本次材料的事实，即使部分坏行被跳过，
  // 也按归档声明的行数判——超限包的解压与解析本身已是负担，不做截断）
  const declaredRows: number = (messagesValue as Object[]).length;
  if (declaredRows > DS_IMPORT_MAX_NODES) {
    counters.oversizedSessions++;
    if (declaredRows > counters.oversizedMaxNodes) {
      counters.oversizedMaxNodes = declaredRows;
    }
    return null;
  }
  // 标题宽容读（null/缺省 = ''；非法类型不炸容器——标题只是展示面）
  const titleValue: Object | undefined = rec['title'];
  const title: string = typeof titleValue === 'string' ? titleValue : '';
  const tree: DsTreeResult = dsTreeOf(raws, currentIdValue as number);
  counters.duplicateMessageRows += tree.duplicates;
  if (tree.currentId === 0) {
    // 当前消息缺失——无 activeBranchId 可指，整会话跳过。★ 自检轮分账：本支是「整会话
    // 未导入」，不能并进「截断线照导」计数（否则页面文案说「只导入能接上的部分」而用户
    // 根本找不到该会话）
    counters.missingCurrentSessions++;
    return null;
  }
  if (tree.broken) {
    counters.brokenChainSessions++; // 断链/环——截断线照导（与上面整会话跳过分账）
  }
  const mapped: DsParsedMessage[] = [];
  const createdAtOf: Map<number, number> = new Map<number, number>();
  for (const node of tree.nodes) {
    mapped.push(dsMapChainMessage(node));
    createdAtOf.set(node.id, node.createdAtMs);
  }
  const branches: DsParsedBranch[] = [];
  for (const head of tree.branchHeads) {
    branches.push({ headDsId: head, createdAtMs: createdAtOf.get(head) ?? insertedMs });
  }
  return {
    dsId: idValue as string,
    title: title,
    createdAtMs: insertedMs,
    updatedAtMs: updatedMs,
    messages: mapped,
    branches: branches,
    currentDsId: tree.currentId
  };
}

