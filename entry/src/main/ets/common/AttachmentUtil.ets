// 附件工具域：常驻/临时副本管理 + 类型判定 + 发送载荷组装（图片重采样编码 base64 /
// 文本有界读）+ 文件清理 + 预览/分享共享件。
// 链路（aicontrol 无自有服务器，学 dshinhm 上传链路骨架）：选择器临时授权 URI → fd 级
// 拷贝进沙箱（picker 授权时效 + fs.copyFile 对媒体库 URI 解析不可靠双险，copyFileExact
// 先例）→ 附件入列 → 发送时读副本组装协议载荷。
// 副本分区：普通会话常驻 filesDir/attachments（选到即直写、发送零迁移；发送成功后
// 文件保留供历史气泡与预览消费，元数据随消息落 message_attachments 表）；隐私会话走
// cacheDir/attachments 临时区——发送成功后**留盘供会话内预览**（决明拍板，「发送即删」
// 旧口径作废），回收点 = 离页整目录清扫；组装失败降级纯文本时副本仍即删。
// 生命周期防线（成对 + 有界）：
// · 常驻区文件随消息行生命周期：删会话/删助手同事务级联删行、commit 后删文件（入口 =
//   ChatDb.deleteConversations + AssistantDb.deleteAssistantCascade）；启动
//   reconcileAttachments 按库比对清孤儿（AttachmentDb.ets）；
// · 临时区（隐私会话）：离页清扫（ChatPage aboutToDisappear sweepAttachDir，已发送 +
//   未发送一并）+ 启动整目录清扫（crash 残留兜底）。
// 分层：本件属 common，被 components/chat 侧 AttachmentPickCtrl（选择入列）/ ChatSendCtrl
//（发送组装）单向消费；MessageAttachmentRow 取自 common/store/AttachmentDb（AttachmentDb
// 不 import 本文件——单向防循环）。openSystemPreview（文档类 Preview Kit 系统预览窗）与
// shareAttachment（系统分享面板）为自会话页/查看器抽出的共享件——「该不该走系统窗」判定
// isSystemPreviewKind 本就在此，判定与执行同源。本件纯函数均被断言脚本复制直跑（下文
//「断言直跑」同此义，不逐条展开）。
import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { filePreview } from '@kit.PreviewKit';
import { systemShare } from '@kit.ShareKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { AiImagePart, PendingAttachment } from './providers/AiTypes';
import { decodeScaled } from './ImageEditUtil';
import { AttachmentListRow, MessageAttachmentRow } from './store/AttachmentDb';
import { ROUTE_ATTACHMENT_VIEWER_PAGE } from './RouteNames';
// 新模块边（OCR 二期）：解析域阻断判定与抽取上限单源复用——DocumentParse 不反向 import
// 本文件（已核无环）
import { docBlockingReason, MAX_EXTRACTED_CHARS } from './DocumentParse';
// DS 服务端解析件判据与镜像键（DS 全家桶接入批 S4——判据单源 DsServerTools，本件是
// attach 域阻断消费方；DsServerTools 不反向 import 本件，无环）
import { CHAT_DS_OFFICIAL_AVAILABLE_KEY, CHAT_DS_RESPONSES_ENDPOINT_KEY,
  dsServerDocBlockReason } from './providers/DsServerTools';

// 附件目录名（常驻区挂 filesDir 下、临时区挂 cacheDir 下；与 AttachmentDb.ATTACH_DIR_NAME
// 同值——两文件互不 import，sse-assert 断言钉一致）
const ATTACH_DIR: string = 'attachments';
// 图片重采样目标长边（px）：官方图片解码内存优化实践 + OpenAI vision 指南（长边约 2000
// 级识别效果与成本平衡）；等比缩放（decodeScaled fitLongEdge），产物内接 2048²
export const IMAGE_MAX_EDGE_PX: number = 2048;
// JPEG 编码质量（PackingOption.quality，0~100；PNG 恒无损不受此参影响）
const IMAGE_JPEG_QUALITY: number = 85;
// 待发附件缩略图目标边长（px）：64vp × 3x 密度 ≈ 192——官方图片解码内存优化实践，等比限
// 最长边（横竖图内存同界）、总量 ≤ MAX_ATTACHMENTS 张有界。★ 双消费方单源：入列解码
//（AttachmentPickCtrl.enqueue）与待发图片裁剪页保存后预解（PhotoEditPage.onUse）——两处各
// 写一份字面量会漂移，而预解产物必须与入列规格同尺（否则缩略图清晰度/内存口径分叉）
export const ATTACH_THUMB_EDGE_PX: number = 192;

// 待发图片编辑回执（编辑页 → 附件控制器）。path 三态 = '' 放弃这张 / 原图路径 编辑失败按
// 原图入列 / 成品路径 裁剪成功（见 PhotoEditPage 头注释）。thumb = 编辑页保存后预解的
// 缩略图（规格 = ATTACH_THUMB_EDGE_PX）——非空则入列侧直接入仓、免第二次解码：解码从
// 「pop 之后」搬到「pop 之前」，附件随返回转场首帧即到位，输入栏几何不在转场相里跳变
//（2026-11-05 真机实测：旧链入列晚于转场起点 24ms，恰跨过第一帧 ⇒ 胶囊 93→173vp 一帧
// 跳变 = 观感「闪」）。成对释放：入列侧只有两个出口吞下它——putThumb 转交仓库，或大小闸
// 拒绝时当场 release；null = 无预解（放弃/按原图/预解失败，入列侧自解）
export interface PhotoEditOutcome {
  path: string;
  thumb: image.PixelMap | null;
}

// 图片扩展名白名单（小写；选择入口按扩展名分流——PhotoViewPicker 天然只出图，
// DocumentViewPicker 全类型开放须自判）
const IMAGE_EXTS: string[] = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif'];
// 文本扩展名白名单（读出内容并入协议 content——纯文本全协议通吃，无逐协议特判）
const TEXT_EXTS: string[] = ['txt', 'md', 'log', 'json', 'csv', 'xml', 'html', 'htm', 'yml',
  'yaml', 'toml', 'ini', 'sh', 'bat', 'ps1', 'py', 'js', 'ts', 'c', 'h', 'cpp', 'java', 'css'];
// 文档扩展名白名单（WebView 解析器四引擎可提取格式——.doc/.ppt 二进制旧格式不支持
//（mammoth/JSZip 仅 docx/pptx）不进白名单；pptx 走桥页 JSZip 抽 slide XML 文本）
const DOC_EXTS: string[] = ['pdf', 'docx', 'xlsx', 'xls', 'ofd', 'pptx'];

// 文件名扩展名（小写、无点；无扩展名回 ''）
export function extOf(name: string): string {
  const dot: number = name.lastIndexOf('.');
  if (dot < 0 || dot >= name.length - 1) {
    return '';
  }
  return name.substring(dot + 1).toLowerCase();
}

// 文件副行扩展名段（自 ChatAttachmentStrip 上收单源：「TXT」形态，无扩展名兜底 FILE——
// 附件气泡与输入栏附件条两消费方同口径，断言钉同源）
export function extLabel(name: string): string {
  const ext: string = extOf(name);
  return ext === '' ? 'FILE' : ext.toUpperCase();
}

// ── 查看器标题截断 ──
// 为何要自截：官方 HDS 标题栏 mainTitle 只吃裸 ResourceStr、不暴露任何截断控制项（本地
// d.ts grep maxLines/ellipsis/TextOverflow = 0 命中），超长固定走「缩字号 → 折两行 → 尾
// 省略」；查看器要的是「单行、尾省略、不缩字号」，故**喂进 mainTitle 前先按单行预算截好**
//——光感材质 / 字号 / 位置仍全部由官方绘制（零自绘；禁改成覆盖层自绘标题——偏离官方
// 标题形制，《行内按钮与光感》§4「二级页同规」①）。规则 = 普通尾省略、不保扩展名（决明
// 拍板），与附件管理页行名 / 聊天气泡文件名 / 输入栏附件条三处 maxLines(1) +
// TextOverflow.Ellipsis 同观感。三个纯函数（断言直跑）：textUnits / viewerTitleName /
// titleBudgetUnits。

// 单位宽度判定：CJK（含全角标点）计 2、其余计 1——中英混排在同一预算下长度才可比。区间表
// （书内自定口径）：0x2E80–0x9FFF / 0xAC00–0xD7A3 / 0xF900–0xFAFF / 0xFE30–0xFE4F /
// 0xFF00–0xFF60 / 0xFFE0–0xFFE6
function isWideCode(code: number): boolean {
  return (code >= 0x2E80 && code <= 0x9FFF) || (code >= 0xAC00 && code <= 0xD7A3) ||
    (code >= 0xF900 && code <= 0xFAFF) || (code >= 0xFE30 && code <= 0xFE4F) ||
    (code >= 0xFF00 && code <= 0xFF60) || (code >= 0xFFE0 && code <= 0xFFE6);
}

// i 处是否代理对起始（emoji 等四字节字符的首码元——文件名极少见，整体按 1 单位近似，书内自定口径）
function isSurrogateHead(s: string, i: number): boolean {
  const code: number = s.charCodeAt(i);
  return code >= 0xD800 && code <= 0xDBFF && i + 1 < s.length &&
    s.charCodeAt(i + 1) >= 0xDC00 && s.charCodeAt(i + 1) <= 0xDFFF;
}

// i 处字符的视觉单位数（i 须落在字符首码元）
function charUnitsAt(s: string, i: number): number {
  return isSurrogateHead(s, i) ? 1 : (isWideCode(s.charCodeAt(i)) ? 2 : 1);
}

// i 处字符占用的码元数（代理对 2、其余 1）——与 charUnitsAt 同源供量宽与切串共用（同一把尺）
function charSpanAt(s: string, i: number): number {
  return isSurrogateHead(s, i) ? 2 : 1;
}

// 串的视觉宽度单位
export function textUnits(s: string): number {
  let units: number = 0;
  let i: number = 0;
  while (i < s.length) {
    units += charUnitsAt(s, i);
    i += charSpanAt(s, i);
  }
  return units;
}

// 标题省略号（U+2026 单字符，不是三个半角点）——与渲染层省略号观感对齐
const TITLE_ELLIPSIS: string = '…';

// 标题显示名：普通尾省略——超预算时取「前半 + '…'」，**不保扩展名**
//（决明拍板）。前半按单位累加、不切半个汉字，尾部空白 trim；'…' 占 1 单位计入预算。
// 三态：未超（恰等也算）原样返回；空名回空串（页面空集回落口径）；预算 ≤ 1 或前半不够时
// 只回 '…'（禁回空串——空标题会让官方标题栏空栏）
export function viewerTitleName(name: string, budgetUnits: number): string {
  if (name === '') {
    return '';
  }
  if (textUnits(name) <= budgetUnits) {
    return name;
  }
  const headBudget: number = budgetUnits - 1;
  let used: number = 0;
  let end: number = 0;
  while (end < name.length) {
    const cost: number = charUnitsAt(name, end);
    if (used + cost > headBudget) {
      break;
    }
    used += cost;
    end += charSpanAt(name, end);
  }
  return name.substring(0, end).replace(/\s+$/, '') + TITLE_ELLIPSIS;
}

// 官方 HDS 标题栏 TitleSize.TITLE_S 的等效字号（vp）：官方文档未公开数值（本地 d.ts 只有枚举名
// TITLE_S = 0）→ 书内自定初值 20，**真机量一次后写死**（真机校准值；改它即改标题截断点）
const TITLE_FONT_VP: number = 20;

// 标题单行预算单位：入参 = 标题区可用宽（vp）= 屏宽 − 两侧让位（几何
// 单源在 components/TitleBarKeys，本件属 common 不引 UI 组件）。预算 = floor(可用宽 × 2 ÷
// TITLE_FONT_VP)（×2 = 预算单位按半角字符当量计）。360 宽常见屏 ⇒ (360−128)×2÷20 = 23
export function titleBudgetUnits(availWidthVp: number): number {
  return Math.floor(availWidthVp * 2 / TITLE_FONT_VP);
}

// 文件副行大小段（同上上收单源：「16.39 KB」两位小数，B/KB/MB/GB 四档——GB 档与
// WorkspaceUtil.formatWorkspaceSize 同值先例不漂移；附件侧 50MB 上限内到不了 GB 档，仅保同形）
export function formatFileSize(size: number): string {
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

// 按扩展名判定附件类：'image' | 'text' | 'doc' | ''（空 = 不支持——选择入口拦截并中文提示）
export function classifyByName(name: string): string {
  const ext: string = extOf(name);
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

// 文档附件 MIME（扩展名派生——解析器按扩展名分派引擎，mime 仅展示与桥输入口径；未知兜底
// octet-stream。表值与 WorkspaceUtil.workspaceMimeOf 文档段同源对齐——白名单收了而 MIME
// 漏配会让模型可见文本块标错类型）
export function docMime(name: string): string {
  const ext: string = extOf(name);
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
  return 'application/octet-stream';
}

// 图片编码输出 MIME：png 保 png（无损 + 保透明通道——JPEG 无 alpha 透明区变黑），
// 其余（含 heic/webp/gif/bmp）统一转 JPEG（有损 q85——白名单格式四协议全兼容）
export function imageOutMime(name: string): string {
  return extOf(name) === 'png' ? 'image/png' : 'image/jpeg';
}

// 附件目录分流：persistent = true → filesDir/attachments（普通会话常驻区——发送零迁移，
// 副本明文落盘与消息同口径）；false → cacheDir/attachments（隐私会话临时区）。
// 分流在选择侧读取 isPrivate（会话态在页面生命周期内不变，不得发送时才定目录——文件已落盘无法迁移）
export function attachDir(ctx: common.UIAbilityContext, persistent: boolean): string {
  return (persistent ? ctx.filesDir : ctx.cacheDir) + '/' + ATTACH_DIR;
}

// 目录就绪（返回绝对路径；EEXIST = 目标状态静默，其他错误上抛给调用方报中文）
export function ensureAttachDir(ctx: common.UIAbilityContext, persistent: boolean): string {
  const dir: string = attachDir(ctx, persistent);
  try {
    fs.mkdirSync(dir, true);
  } catch (e) {
    const err = e as BusinessError;
    if (err.code !== 13900015) {
      throw e as Error; // ArkTS 限 throw 仅接受 Error 值（先例 applyBlur 断言转换）
    }
  }
  return dir;
}

// 相对路径构造（入库红线：localPath 只存相对 filesDir 的 attachments/<id>.<ext>，禁绝对
// 路径——换设备/将来导出迁移拼当前沙箱前缀即可用）；入参 = 附件副本绝对路径，取文件名
export function relativeAttachPath(localPath: string): string {
  return ATTACH_DIR + '/' + localPath.substring(localPath.lastIndexOf('/') + 1);
}

// 附件元数据行构建：id = fileId（与文件名同源）、localPath = 相对
// 路径、parsedText 仅 kind='doc' 取解析产出（其余恒 ''——图片走重采样编码、文本内容并入
// 协议 content，均无需随行保存）
export function buildAttachmentRows(atts: PendingAttachment[], messageId: string,
  conversationId: string, createdAt: number): MessageAttachmentRow[] {
  const rows: MessageAttachmentRow[] = [];
  for (const att of atts) {
    rows.push({
      id: att.fileId,
      messageId: messageId,
      conversationId: conversationId,
      kind: att.kind,
      name: att.name,
      mime: att.mediaType,
      size: att.size,
      localPath: relativeAttachPath(att.localPath),
      parsedText: att.kind === 'doc' ? (att.parsedText ?? '') : '',
      createdAt: createdAt
    });
  }
  return rows;
}

// 临时区启动清扫（隐私会话 crash 残留兜底；目录不存在 = 目标状态静默）。启动执行一次、
// 非轮询（P1-2）。★ 只清 cacheDir 临时区——filesDir 常驻区由 reconcileAttachments 按库
// 比对清孤儿，不再整目录扫删
export function sweepAttachDir(ctx: common.UIAbilityContext): void {
  const dir: string = attachDir(ctx, false);
  try {
    const names: string[] = fs.listFileSync(dir);
    for (const name of names) {
      try {
        fs.unlinkSync(dir + '/' + name);
      } catch {
        // 单文件失败跳过——下次启动再清（有界自愈）
      }
    }
  } catch {
    // 目录不存在 = 干净，目标状态
  }
}

// 删单个副本（删除失败仅日志——启动清扫/下次覆盖自愈，不打扰用户）
export function removeAttachFile(path: string): void {
  try {
    fs.unlinkSync(path);
  } catch {
    // 文件不存在 = 目标状态，静默
  }
}

// 图片附件 → 协议部件：沙箱副本 → 限长边重采样解码 → JPEG/PNG 编码 → 裸 base64。
// 解码失败抛错（调用方中文呈报）；PixelMap/Packer 成对释放（内存防线）
export async function encodeImageBase64(att: PendingAttachment): Promise<AiImagePart> {
  const mime: string = imageOutMime(att.name);
  let pm: image.PixelMap | null = null;
  const packer: image.ImagePacker = image.createImagePacker();
  try {
    pm = await decodeScaled(att.localPath, IMAGE_MAX_EDGE_PX, true);
    // packToData = packing 的官方接替 API（packing @deprecated since 13，d.ts useinstead）
    const buf: ArrayBuffer = await packer.packToData(pm, { format: mime, quality: IMAGE_JPEG_QUALITY });
    const data: string = new util.Base64Helper().encodeToStringSync(new Uint8Array(buf));
    return { mimeType: mime, data: data };
  } finally {
    packer.release();
    if (pm !== null) {
      pm.release();
    }
  }
}

// ArrayBuffer 入口的同构编码（网络图链下载字节 → 限长边重采样 → 编码 → 裸 base64）：
// 与 encodeImageBase64 的唯一差异 = 入参形态，压缩参数完全复用（长边 2048 / JPEG q85）。
// nameHint = url 末段文件名（'' / 未知扩展名经 imageOutMime 兜底 image/jpeg）。解码失败
// 抛错（调用方全捕获跳过该链）；PixelMap/Packer 成对释放，同上函数内存防线口径
export async function encodeImageBuffer(data: ArrayBuffer, nameHint: string): Promise<AiImagePart> {
  const mime: string = imageOutMime(nameHint);
  let pm: image.PixelMap | null = null;
  const packer: image.ImagePacker = image.createImagePacker();
  try {
    pm = await decodeScaled(data, IMAGE_MAX_EDGE_PX, true);
    const buf: ArrayBuffer = await packer.packToData(pm, { format: mime, quality: IMAGE_JPEG_QUALITY });
    const encoded: string = new util.Base64Helper().encodeToStringSync(new Uint8Array(buf));
    return { mimeType: mime, data: encoded };
  } finally {
    packer.release();
    if (pm !== null) {
      pm.release();
    }
  }
}

// ── 渲染层附件简报 ──
// 不带 messageId——装配侧按消息归并；absPath 恒绝对路径（相对路径红线只对入库生效，
// 运行时拼绝对路径供 Image/预览/读文件消费）
export interface AttachmentBrief {
  id: string; // = 库行 id / 待发 fileId（点击派发与滑切定位键）
  name: string;
  kind: string; // 'image' | 'text' | 'doc'（classifyByName 全集）
  size: number;
  absPath: string;
}

// 库行 → 简报（历史回放装配与附件管理列表共用；absPath = filesDir + 相对 localPath——库内
// 相对、运行时绝对，红线沿用；入参加 AttachmentListRow 窄行，两消费方同一实现）。纯函数
export function briefsFromRows(rows: AttachmentListRow[],
  filesDir: string): AttachmentBrief[] {
  const briefs: AttachmentBrief[] = [];
  for (const row of rows) {
    briefs.push({
      id: row.id,
      name: row.name,
      kind: row.kind,
      size: row.size,
      absPath: filesDir + '/' + row.localPath
    });
  }
  return briefs;
}

// 待发附件 → 简报（发送链装配用；PendingAttachment.localPath 已是绝对路径——常驻区
// filesDir / 隐私区 cacheDir 两形态天然兼容，原样保留）。纯函数，断言直跑
export function briefsFromPending(atts: PendingAttachment[]): AttachmentBrief[] {
  const briefs: AttachmentBrief[] = [];
  for (const att of atts) {
    briefs.push({
      id: att.fileId,
      name: att.name,
      kind: att.kind,
      size: att.size,
      absPath: att.localPath
    });
  }
  return briefs;
}

// 文档类判定（走系统预览的 kind）：恒 = classifyByName === 'doc'（五后缀全集单源——禁
// 另写扩展名表，改白名单只动 DOC_EXTS 一处）
export function isSystemPreviewKind(name: string): boolean {
  return classifyByName(name) === 'doc';
}

// ── 文档类系统预览分派共享件（自 ChatPageContent 抽出，两消费方 = 会话页分派单点 +
// 附件管理页行点击；行为零变化）──
// 官方约束与红线全在件内收口：uri 必转（fileUri.getUriFromPath——沙箱裸路径官方不吃）、
// mimeType 传空串（项目 ofd mime 与官方表不一致，系统按 uri 后缀自判，勿自填）、1 秒防重入
// 闸（官方「1 秒内重复调用无效」——时间戳比较，无定时器残留）、ctx 判空、失败中文 toast 不
// 静默（P0-1）。闸语义：成功后 1 秒内忽略重复点击，失败即复位
let previewGateUntilMs: number = 0;

export function openSystemPreview(uiCtx: UIContext, name: string, absPath: string): void {
  if (Date.now() < previewGateUntilMs) {
    return; // 闸内忽略重复点击
  }
  const ctx: common.UIAbilityContext | undefined =
    uiCtx.getHostContext() as common.UIAbilityContext | undefined;
  if (ctx === undefined) {
    hilog.warn(0xD5A0, 'AttachmentUtil', '系统预览未执行：host context 不可达');
    uiCtx.getPromptAction().showToast({ message: '预览失败，请重试' });
    return;
  }
  filePreview.openPreview(ctx, {
    title: name,
    uri: fileUri.getUriFromPath(absPath),
    mimeType: ''
  })
    .then((): void => {
      // 成功后置闸 1s（到点自动放行，无需定时器）
      previewGateUntilMs = Date.now() + 1000;
    })
    .catch((e: Object): void => {
      previewGateUntilMs = 0; // 失败即复位
      const err = e as BusinessError;
      hilog.warn(0xD5A0, 'AttachmentUtil', '系统预览失败：code %{public}d %{public}s',
        typeof err.code === 'number' ? err.code : -1, (e as Error).message);
      uiCtx.getPromptAction().showToast({ message: '预览失败：' + (e as Error).message });
    });
}

// ── 附件分享共享件（自 AttachmentViewer 抽出：分享键迁官方标题栏右上角，链路原样搬迁；
// 与 openSystemPreview 同域同形——附件对外一次性动作、UIContext 由调用方传入、失败中文
// toast 不静默）──
// 链路 = 系统分享面板（@kit.ShareKit，LogPage / SkillPack 同款）：官方 d.ts 核实面板默认
// 操作区自带「另存为文件」，故本键一并覆盖分享与另存为；分享对象 = 调用方指定的**单个**
// 附件。uri 必转（面板只吃 App file URI）；host context 判空（异步回调晚到时组件可能已销毁）。
export function shareAttachment(uiCtx: UIContext, brief: AttachmentBrief): void {
  const ctx: common.UIAbilityContext | undefined =
    uiCtx.getHostContext() as common.UIAbilityContext | undefined;
  if (ctx === undefined) {
    hilog.warn(0xD5A0, 'AttachmentUtil', '分享未执行：host context 不可达');
    uiCtx.getPromptAction().showToast({ message: '分享失败，请重试' });
    return;
  }
  // 附件类两态覆盖查看器全部件型（图片 = 官方图像 UTD；文本 = 纯文本）
  const record: systemShare.SharedRecord = {
    utd: brief.kind === 'image' ?
      uniformTypeDescriptor.UniformDataType.IMAGE :
      uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
    uri: fileUri.getUriFromPath(brief.absPath),
    title: brief.name,
    label: extLabel(brief.name)
  };
  new systemShare.ShareController(new systemShare.SharedData(record))
    .show(ctx, {})
    .catch((e: Object): void => {
      hilog.warn(0xD5A0, 'AttachmentUtil', '分享面板拉起失败：%{public}s', (e as Error).message);
      uiCtx.getPromptAction().showToast({ message: '分享失败，请重试' });
    });
}

// ── 共享元素转场广播键 ──
// 单一广播键：值 = 当前参与共享元素转场的附件元素 id（空串 = 无）。三处消费同一判据
//（消息气泡缩略图 / 输入栏缩略图 / 查看器图片页 Image），各自 @StorageProp 订阅 +
// sharedGeomId 计算 geometryTransition id——只有「我的 id === 当前共享 id」的那一枚绑定
//（官方约束：同一 id 恰两个组件），其余取空串（官方「清除绑定关系」语义）。键落点 = 本件
//（瞬时运行态键随域件走先例）；不入 AppPreferences（预览期瞬时态，关闭即清）。
// ★ 写点全量（全仓恰 3 处，计数钉在 assert-attach-domain）：①会话页分派（打开前写命中件
// id；文本写空串自愈残留绑定）；②查看器内容件 Swiper.onChange（随页）；③查看器页面壳
// aboutToDisappear 清空（与①对称成对；管理页本就不写键——列表行是类型图标，无缩略图飞行）。
// ★ 返场飞行丢失备选：清键若嫌过早（pop 动画期键已清 = 返场无绑定），改由上一页 onShown
// 清——动前先测
export const ATTACH_SHARED_ID_KEY: string = 'attachSharedId';

// geometryTransition id 单源前缀（禁裸拼——三处同源经 sharedGeomId，断言钉零旁路）
export const SHARED_ATTACH_PREFIX: string = 'gt-attach-';

// 共享元素 id 判据：ownId === 当前共享 id → 前缀 + ownId，否则空串
export function sharedGeomId(ownId: string, currentSharedId: string): string {
  return currentSharedId === ownId ? SHARED_ATTACH_PREFIX + ownId : '';
}

// 共享元素转场时长（ms）——消费方 = 列表侧两件（AttachmentBubble / ChatAttachmentStrip）
// 的「激活期 OPACITY 动画」时长（与查看器开关同值，曲线 Curve.Friction 同源官方模态组合
// 示例）。调观感只改本值
export const ATTACH_PREVIEW_ANIM: number = 320;

// ── 附件查看器二级页开页件 ──
// 查看器路由参数（页面内 getParamByName 取回）：items = 查看集（图片模式 = 滑切集合 /
// 文本模式 = 单件）、index = 起始下标。接口落本件（而非页面文件）= 开页件与页面两侧同用，
// 落页面文件会让 common 层反向依赖 UI 组件（分层红线）
export interface AttachmentViewerParam {
  items: AttachmentBrief[];
  index: number;
}

// 开查看器二级页（多宿主共用；先例 = openSystemPreview 的调用侧收口）：
// ①**防重入**——modal 时代连点缩略图幂等（同一 @State 重设），改 push 后连点会叠两层页
//（返回要按两次）。判据取「栈顶已是本路由且参数指向同一件」（getParamByName 取栈顶参数）
// 比时间闸准（不误杀「关了立刻再开同一张」），故不引时间闸。②形状 = pushPathByName(name,
// param, animated) 三参：animated 由调用方按有无共享元素绑定显式声明——会话页宿主（气泡/
// 输入栏缩略图绑 geometryTransition id、广播键 push 前写入）传 false 给共享元素飞行让位；
// 设置类三页（附件管理/挂载浏览/工作区管理，列表行类型图标不绑 id）传 true 走官方默认
// push/pop 转场。路由名引用常量（禁裸字符串：改名时编译期即报）。
export function openAttachmentViewer(pathStack: NavPathStack, items: AttachmentBrief[],
  index: number, animated: boolean): void {
  const names: string[] = pathStack.getAllPathName();
  if (names.length > 0 && names[names.length - 1] === ROUTE_ATTACHMENT_VIEWER_PAGE) {
    const stackParams: Array<AttachmentViewerParam> =
      pathStack.getParamByName(ROUTE_ATTACHMENT_VIEWER_PAGE) as Array<AttachmentViewerParam>;
    const top: AttachmentViewerParam | undefined =
      stackParams.length > 0 ? stackParams[stackParams.length - 1] : undefined;
    const target: AttachmentBrief | undefined =
      index >= 0 && index < items.length ? items[index] : undefined;
    if (top !== undefined && target !== undefined && top.items.length > 0 &&
      top.index >= 0 && top.index < top.items.length &&
      top.items[top.index].id === target.id) {
      return; // 连点同一件——已在栈顶，不再叠页
    }
  }
  const param: AttachmentViewerParam = { items: items, index: index };
  pathStack.pushPathByName(ROUTE_ATTACHMENT_VIEWER_PAGE, param, animated);
}

// 显示层剥离标注（拍板 5：库内不改写，只在气泡渲染时隐去）：text 尾部与
// '\n\n[附件] 名单' 逐字吻合才切掉该段；纯附件消息（发送时无文字）剥到空串——空文本判定
//「消息泡整只不渲染」的前提；名单为空恒原样（导入/老数据回退显示标注）；任一不吻合原样
// 返回（误剥防线：用户手打同款字样不动它）
export function hideAttachAnnotate(text: string, names: string[]): string {
  if (names.length === 0) {
    return text;
  }
  const annotate: string = '[附件] ' + names.join('、');
  if (text === annotate) {
    return '';
  }
  const tail: string = '\n\n' + annotate;
  if (text.length > tail.length && text.endsWith(tail)) {
    return text.substring(0, text.length - tail.length);
  }
  return text;
}

// 文本查看器截断上限（拍板 6 落地参数：纯文本原样、10 万字符封顶）；超出截断，
// 由调用方追加提示行（本函数只裁文本，不拼文案）
export const TEXT_VIEW_MAX_CHARS: number = 100000;

// 文本查看器裁剪（≤上限原样返回）
export function clipForTextViewer(text: string): string {
  return text.length > TEXT_VIEW_MAX_CHARS ? text.substring(0, TEXT_VIEW_MAX_CHARS) : text;
}

// ── 视觉门控两判据 + OCR 分流三纯函数 ──
// 该件本轮是否走「识别文本」通道：主模型**无**视觉 且 该件有识别产出——已改走文本的件
// 本轮不再发图（页图/图片停发，识别文本进 protocolAppend）
export function routeToOcrText(att: PendingAttachment, hasVision: boolean): boolean {
  return !hasVision && (att.ocrText ?? '') !== '';
}

// 本轮是否真的会带图：任一附件为图片附件（kind='image'）或带页图（扫描件 PDF），**已分流
// 走识别文本的件除外**。★ 判据取「实际产物」不取 kind——doc 附件渲染失败（pageImages 空）
// 不该触发确认框，否则「不支持视觉」的提示与实际请求不符
export function willSendImages(atts: PendingAttachment[], hasVision: boolean): boolean {
  for (const att of atts) {
    if (routeToOcrText(att, hasVision)) {
      continue; // 已分流文本 → 本轮不发图
    }
    if (att.kind === 'image') {
      return true;
    }
    if (att.pageImages !== undefined && att.pageImages.length > 0) {
      return true;
    }
  }
  return false;
}

// 发送前置阻断（doc 解析阻断 + 服务端解析件连接失配 + OCR 识别中；返回中文阻断原因，
// '' = 放行）：doc 域判定单源原样复用；服务端解析件判据单源 dsServerDocBlockReason
//（DsServerTools）+ 镜像键现读；OCR 只在 **running** 态阻断（done/failed 不拦——failed
// 走一期行为）；ocrEnabled() 为假时排程侧不会置 running，天然不阻断。
// ★ S4③ 两支落位说明：A 支（服务端件 failed 阻断带中文错误）无新码——上传失败置
// parseState='failed' + parseError 中文错误，docBlockingReason failed 支天然阻断并带出
// 错误（不另立同判据第二支，真值表钉在 assert-attach-domain 100 与 ds-integration 丁组）；
// B 支（连接已非 DS 官方档）在下方循环内新落。镜像键 = ChatPage.setConnInfo 写入的
// 「DeepSeek 官方可用」广播（kill switch × 连接四合一），本函数无 conn 形参（调用点
// ChatPage.sendWithAttachments 不透传），镜像键是现成通道
export function attachBlockingReason(atts: PendingAttachment[]): string {
  const docBlocked: string = docBlockingReason(atts);
  if (docBlocked !== '') {
    return docBlocked;
  }
  const dsOfficialAvailable: boolean =
    AppStorage.get<boolean>(CHAT_DS_OFFICIAL_AVAILABLE_KEY) === true;
  // Responses 形态：官方档判据为真但 file item 形态官方未给——发送前拦下并提示切 CC 形态
  //（自检轮补；下传纯函数，本函数仍无 conn 形参，镜像键是现成通道）
  const responsesEndpoint: boolean =
    AppStorage.get<boolean>(CHAT_DS_RESPONSES_ENDPOINT_KEY) === true;
  for (const att of atts) {
    const serverDocBlocked: string =
      dsServerDocBlockReason(att, dsOfficialAvailable, responsesEndpoint);
    if (serverDocBlocked !== '') {
      return serverDocBlocked;
    }
    if (att.ocrState === 'running') {
      return `附件文字识别中，请稍候：${att.name}`;
    }
  }
  return '';
}

// 生效能力串是否含视觉理解（caps 逗号串形态，与 ProviderDb.capLabels 同口径切分）。
// ★ 入参必须是 effectiveCaps 的产物（ProviderDb 单源），禁直读 row.caps——派生能力
// 不进库（A1 明令）
export function hasVisionCap(caps: string): boolean {
  return caps.split(',').indexOf('vision') >= 0;
}

// 发送载荷（组装产物）：annotate = 追加到 user 消息文本的标注（DB/气泡/历史可见——
//「发了什么」可追溯）；protocolAppend = 仅进协议 content 的文本附件内容；images = 图片
// 部件（随本轮请求发送）。历史轮不再重发（协议历史取自消息文本 = 标注态——附件本体仅随
// 当前轮）
export interface AttachmentPayload {
  annotate: string;
  protocolAppend: string;
  images: AiImagePart[];
}

// 识别文本块：与文档解析块同形（`[附件内容开始: 名 (mime)]` 头尾——
// 少一种新块形态、模型侧语义一致），总长上限与截断标注同源 MAX_EXTRACTED_CHARS；空识别
//（ocrText 空）恒回 ''。只进 protocolAppend，**annotate 一字不动**（hideAttachAnnotate
// 重建式剥离的耦合面）
export function appendOcrBlock(att: PendingAttachment): string {
  const text: string = att.ocrText ?? '';
  if (text === '') {
    return '';
  }
  let body: string = text;
  if (body.length > MAX_EXTRACTED_CHARS) {
    body = body.substring(0, MAX_EXTRACTED_CHARS) + '\n[识别文字已截断]';
  }
  return `[附件内容开始: ${att.name} (${att.mediaType})]\n${body}\n[附件内容结束: ${att.name}]`;
}

// ── 文本附件有界读单源 ──
// 文本附件单件上限 30MB（AttachmentPickCtrl.MAX_TEXT_BYTES），若照旧全量读，发送链与
// 上下文面板活算会把整份文件塞进协议请求与内存——故「发送协议 / 面板活算 / 附件查看器」
// 三条路的读取量一律有界在 MAX_EXTRACTED_CHARS（12 万字符，与文档解析抽取上限**同值单源**
//——模型侧看到的最大正文量与文档类一致）。读失败上抛，由调用方按既有路径处置（发送链
// 降级 / 面板转提示行 / 查看器中文提示面）
export const TEXT_ATTACH_MAX_CHARS: number = MAX_EXTRACTED_CHARS;

export interface AttachmentTextSlice {
  text: string;
  truncated: boolean;
}

// 有界读（本地路径 → 文本切片）。快路径判据取**字节数**：字节 ≤ N 时字符必 ≤ N（UTF-8
// 单字符至少 1 字节），全读即在上限内。超限时才按字节读 MAX*4 + 8（单字符至多 4 字节，
// 多读 8 字节避开边界），解出文本再按字符裁到 N。解码抛错 = 切在多字节字符中间（残缺尾
// 字节若被解成替换字符，必落在第 N 个之后、被 substring 裁掉，无害）——每次减 1 字节
// 重试至多 3 次；仍失败即上抛（P0-1：宁可报错中断，不返回半截静默成功的假文本）
export function readAttachmentText(localPath: string): AttachmentTextSlice {
  if (fs.statSync(localPath).size <= TEXT_ATTACH_MAX_CHARS) {
    return { text: fs.readTextSync(localPath), truncated: false };
  }
  let length: number = TEXT_ATTACH_MAX_CHARS * 4 + 8;
  for (let i = 0; i < 3; i++) {
    try {
      const raw: string = fs.readTextSync(localPath,
        { offset: 0, length: length, encoding: 'utf-8' });
      // 截断标记按**解出文本的实际长度**判（非「进了本分支就标」）：字节超限 ≠ 字符超限
      //——中英混排文件可能字节过线而字符未过线，标截断会让模型以为还有后续内容
      return { text: raw.substring(0, TEXT_ATTACH_MAX_CHARS),
        truncated: raw.length > TEXT_ATTACH_MAX_CHARS };
    } catch {
      length -= 1;
    }
  }
  throw new Error('文本附件读取失败（' + localPath + '）');
}

// ── 重发大文档叠加式降级（★ 2026-10-31「重发大文档叠加降级与两小修」笔 §四-1/3）──
// 语义：仅「重发文件」面板复制入列的件在解析截断后转指引件——全文副本落工作区，协议侧只组
// 头部分正文 + 工作区路径指引（叠加：头部分照留，全文交给工作区工具读，不做替换式降级）。
// 头部分长度单源；调大 = 模型首轮看到更多正文，调小 = 省 token。
export const REISSUE_GUIDE_HEAD_CHARS: number = 2000;

// 降级上下文（重发面板行点击 → 宿主透传 → AttachmentPickCtrl.addCopiedFromFile → 解析完成
// 回调消费）。两段形态不同：附件段有源行（须导入工作区拿第二副本）、工作区段有工作区相对
// 路径（源本就在工作区，零导入）。
export interface ReissueGuideContext {
  // 工作区段：工作区相对路径（joinDirName(dir, name) 形——workspace 族工具按 (dir, name)
  // 显示名定位的模型面坐标，非 filesDir 物理路径），非空 = 零导入直接作指引；附件段恒空串
  //（降级时按导入回查重取）
  workspacePath: string;
  // 附件段源行（importAttachmentToWorkspace 入参）；工作区段 null
  sourceRow: AttachmentListRow | null;
  // 导入行的会话与助手归属（工作区行 provenance 列）
  conversationId: string;
  assistantId: string;
  // 本会话工具集是否含 workspace_read（false → 降级后 toast 一句建议开启，不阻断）
  workspaceToolOn: boolean;
}

// 降级判定单源（★ 重发降级笔 §四-1）：重发入列件（guide 非空）+ 解析成功 + 正文被截断
// 三条同时成立才降级。抽成纯函数 = 控制器只按返回值走导入编排、断言直跑真值表（禁把判据
// 写进组件分支里）。字节大但未截断的件内联得下 → 不降级；guide 空 = 普通选择器/粘贴/分享件
// → 即使截断也不降级（授权范围只到重发域）。
export function shouldGuideTruncatedDoc(guide: ReissueGuideContext | null, success: boolean,
  truncated: boolean): boolean {
  return guide !== null && success && truncated;
}

// ── 待发附件足迹 ──
// 单件附件的协议文本侧块（空数组 = 该件文本侧无内容）。发送链载荷组装与上下文面板活算
//**共用本实现**——单源纪律同 collectTools（两处各算即漂移面：面板显示的构成会与实际发出
// 的内容不符）。分型（= 发送链历史的逐支逻辑）：
// · image：无视觉 + 有识别文本 → 识别文本块（图不发）；否则文本侧无内容
// · doc：解析块（`[附件内容开始/结束]` 头尾，截断带标注）恒在前；其后 OCR 分流——改走
//   识别文本则追加识别块，否则真发页图时附一行模型可见说明行。★ 指引件（guideWorkspacePath
//   非空）把解析块换成「头部分 + 工作区路径指引」支——面板活算与发送链同吃本函数，两处自动同源
// · 其余（text）：读沙箱副本内容并入协议（标注文件名分界）；读盘只在本支发生，失败上抛由
//   调用方处置；走 readAttachmentText 有界读（12 万字符封顶 + 截断尾注，与 doc 支同形）
export function attachTextBlocksOf(att: PendingAttachment, hasVision: boolean): string[] {
  const blocks: string[] = [];
  if (att.kind === 'image') {
    if (routeToOcrText(att, hasVision)) {
      const block: string = appendOcrBlock(att);
      if (block !== '') {
        blocks.push(block);
      }
    }
    return blocks;
  }
  if (att.kind === 'doc') {
    const text: string = att.parsedText ?? '';
    // 指引件支（★ 重发降级笔）：只组头部分 + 工作区路径指引，全量截断文本不再内联——
    // 叠加式 = 头部分正文照留（模型能据此判断要不要读全文），不是替换成一句话
    const guide: string = att.guideWorkspacePath ?? '';
    if (guide !== '') {
      const head: string = text.length > REISSUE_GUIDE_HEAD_CHARS ?
        text.substring(0, REISSUE_GUIDE_HEAD_CHARS) : text;
      blocks.push(`[附件内容开始: ${att.name} (${att.mediaType})]\n` +
        `${att.name} 开头部分：\n${head}\n` +
        `完整文件已存入工作区 \`${guide}\`，路径相对工作区根目录，可用文件读取工具按路径读取。\n` +
        `[附件内容结束: ${att.name}]`);
    } else if (text !== '') {
      const truncatedNote: string = att.parseTruncated === true ?
        `\n[附件内容已截断，仅包含前 ${text.length} 个字符]` : '';
      blocks.push(`[附件内容开始: ${att.name} (${att.mediaType})]\n${text}${truncatedNote}` +
        `\n[附件内容结束: ${att.name}]`);
    }
    const pages: AiImagePart[] = att.pageImages ?? [];
    if (routeToOcrText(att, hasVision)) {
      const block: string = appendOcrBlock(att);
      if (block !== '') {
        blocks.push(block);
      }
    } else if (pages.length > 0) {
      const totalPages: number = att.pageCount ?? pages.length;
      blocks.push(totalPages > pages.length ?
        `[附件页图: ${att.name} 共 ${totalPages} 页，已发送前 ${pages.length} 页]` :
        `[附件页图: ${att.name} 第 1~${pages.length} 页]`);
    }
    return blocks;
  }
  const slice: AttachmentTextSlice = readAttachmentText(att.localPath);
  const truncatedNote: string = slice.truncated ?
    `\n[附件内容已截断，仅包含前 ${slice.text.length} 个字符]` : '';
  blocks.push('[文件 ' + att.name + ']\n' + slice.text + truncatedNote);
  return blocks;
}

// 单件附件本轮的视觉通道张数（图片件 1 张 / 扫描件页图按页数；已改走识别文本的件与非图
// 件恒 0）——判据与发送链发图支同源（routeToOcrText + pageImages 实际产物，取产物不取
// kind，同 willSendImages 口径）
export function attachImageCountOf(att: PendingAttachment, hasVision: boolean): number {
  if (routeToOcrText(att, hasVision)) {
    return 0;
  }
  if (att.kind === 'image') {
    return 1;
  }
  if (att.kind === 'doc' && att.pageImages !== undefined) {
    return att.pageImages.length;
  }
  return 0;
}

// 待发附件足迹（上下文面板活算口径）：text = 协议文本侧内容（与发送链单源，含 doc 解析
// 正文 / OCR 文本 / 文本附件内容）、imageCount = 视觉通道张数、pending = 有件尚未处理完
//（doc 解析中或未开始 / 识别中）——此刻文本侧不全，面板据此显一行提示。★ failed/
// toolarge 不计 pending：那类件本来就不会发正文（条上已有状态文案），提示它反而是噪声
export interface PendingAttachFootprint {
  text: string;
  imageCount: number;
  pending: boolean;
}

export function pendingAttachFootprint(atts: PendingAttachment[],
  hasVision: boolean): PendingAttachFootprint {
  const blocks: string[] = [];
  let imageCount: number = 0;
  let pending: boolean = false;
  for (const att of atts) {
    for (const block of attachTextBlocksOf(att, hasVision)) {
      blocks.push(block);
    }
    imageCount += attachImageCountOf(att, hasVision);
    if (att.parseState === 'parsing' || att.parseState === 'idle' || att.ocrState === 'running') {
      pending = true;
    }
  }
  return { text: blocks.join('\n\n'), imageCount: imageCount, pending: pending };
}

// 发送载荷组装：图片逐张编码（串行——峰值内存单张界）+ 文本逐个读出 + 标注串。任一附件
// 失败即整体抛错（调用方 toast + 降级纯文本发送，不让单附件卡死发送链）。
// ★ 空数组短路：'[附件] ' + names.join 在空数组时产出非空尾巴「[附件] 」——纯文本轮次也
// 被拼上空标注；空附件直接返回全空载荷（零组装零消耗），标注仅在有附件时产生。
// ★ hasVision 形参（OCR 分流）：主模型有视觉 = 现状零变化（图/页图照发、识别文本不发）；
// 无视觉且该件有识别文本 = 图/页图停发、识别文本块进 protocolAppend（thin PDF 的解析文本
// 块照旧并存——页图停发 ≠ 解析文本停，红线 12）。文本侧逐支逻辑已上收 attachTextBlocksOf
//（单源）——本函数只留「件序拼接 + 视觉通道编码」，产物逐字等价
export async function buildAttachmentPayload(atts: PendingAttachment[],
  hasVision: boolean): Promise<AttachmentPayload> {
  if (atts.length === 0) {
    return { annotate: '', protocolAppend: '', images: [] };
  }
  const names: string[] = [];
  const appends: string[] = [];
  const images: AiImagePart[] = [];
  for (const att of atts) {
    names.push(att.name);
    for (const block of attachTextBlocksOf(att, hasVision)) {
      appends.push(block);
    }
    if (routeToOcrText(att, hasVision)) {
      continue; // 已分流文本 → 不发图
    }
    if (att.kind === 'image') {
      // 附件身份随部件带出（二期 #11 自愈按 attachId 精确回写；base64 图片件本身不走
      // file_id，带出只为同轮混排时部件与附件行一一可对）
      const imgPart: AiImagePart = await encodeImageBase64(att);
      imgPart.attachId = att.fileId;
      images.push(imgPart);
    } else if (att.remoteFileId !== undefined && att.remoteFileId !== '') {
      // DS 服务端解析件（DS 全家桶接入批 S4④）：file 部件借道 images 通道——无 base64
      //（data 空串占位，该件不走本地编码），composeOpenAiBody 按 remoteFileId 分流产
      // {type:'file', file_id}（§0 CC 引用扁平形态），其他协议 compose 对该字段防御性
      // 跳过（判据单源 RequestCompose.isRemoteFilePart）。件序即 images 序，与图片附件混排
      // 时按附件顺序排
      images.push({ mimeType: att.mediaType, data: '', remoteFileId: att.remoteFileId,
        attachId: att.fileId });
    } else if (att.kind === 'doc' && att.pageImages !== undefined) {
      // 页图：逐页图进视觉通道——与图片附件**同一通道**（payload.images → userReq.images
      // → 四协议 image 部件），协议层零改动；件序即 images 序（多件同轮按附件顺序排）
      for (const page of att.pageImages) {
        images.push(page);
      }
    }
  }
  return {
    // 空数组已在函数头早退，此处无需再判（旧防御残留已清理）
    annotate: '[附件] ' + names.join('、'),
    protocolAppend: appends.join('\n\n'),
    images: images
  };
}

// 副本清理（发送组装完成/失败后与页面销毁时调用；与缩略图仓库 release 的组合清理在
// components/chat 侧 AttachmentPickCtrl.cleanupAttachments——分层：common 不引 UI 层）
export function removeAttachFiles(atts: PendingAttachment[]): void {
  for (const att of atts) {
    removeAttachFile(att.localPath);
  }
}
