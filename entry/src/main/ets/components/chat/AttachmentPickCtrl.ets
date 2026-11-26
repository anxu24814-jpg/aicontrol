// 聊天页「添加附件」控制器（自 dshinhm KimiAttachmentCtrl 成熟链路改写：三入口官方选择器 →
// 沙箱副本 → 缩略图 → 附件入列；页面只持 @State attachments 唯一事实源，经 refs 注入读写
//——页面 → 控制器单向依赖，零循环 import）。
// 与 dshinhm 的差异（无自有服务器，副本落沙箱后不经服务器中转）：
// · 副本以唯一 fileId 命名落 filesDir/attachments 常驻（隐私会话临时区分流已随隐私会话退役
//   删除），发送成功保留供会话内预览；回收点 = 离页整目录清扫 + 启动兜底；发送时读副本编码；
// · 照片入口多选（maxSelectNumber = 剩余额度；dshinhm 单选——服务器逐个上传场景）；
// · 类型收窄：图片（base64 进请求）+ 纯文本（内容并入 content）——全协议通吃零逐厂特判；
//   其余类型在选择入口即拦截（中文提示），不产生 kind='video' 附件。
// 链路决策（沿用 dshinhm 实锤结论）：相机 cameraPicker 二路——默认 saveUri 预创建覆盖写
//（免相机权限 + 无授权时效 + 只落沙箱）；「拍照保存到相册」开时不传 saveUri（官方语义「未
// 配置默认存入媒体库」——系统相机落相册，返回媒体库 URI 临时授权可读，再 fd 级拷入沙箱）。
// PhotoViewPicker / DocumentViewPicker（context 构造）均免权限。picker 返回 URI 为临时授权
// → 必须 fd 级拷入沙箱（copyFileExact）；图片附件入列前解码缩略图，解码失败 = 图片不可用
// 当场拒绝（发送时编码同链路，入列后失败无回收通道）。
import { camera, cameraPicker } from '@kit.CameraKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { AiConnection, PendingAttachment } from '../../common/providers/AiTypes';
import { copyFileExact, decodeScaled } from '../../common/ImageEditUtil';
import { PENDING_SHARES_KEY, PENDING_SHARES_TICK_KEY, PendingSharedItem } from '../../common/AppBroadcastKeys';
import {
  ATTACH_THUMB_EDGE_PX, classifyByName, docMime, ensureAttachDir, extOf, imageOutMime,
  PhotoEditOutcome, removeAttachFile, removeAttachFiles, ReissueGuideContext,
  shouldGuideTruncatedDoc
} from '../../common/AttachmentUtil';
import { AttachmentListRow, copyAttachmentResource } from '../../common/store/AttachmentDb';
import { joinDirName, sanitizeWorkspaceName, WorkspaceFileRow } from '../../common/WorkspaceUtil';
import { queryWorkspaceFilesByName } from '../../common/store/ChatDb';
import { importAttachmentToWorkspace, ImportOutcome } from '../../common/providers/HttpBinary';
import { DocumentParseResult, docHardLimitBytes, docParser } from '../../common/DocumentParse';
import { OcrImageSource, OcrOutcome, ocrEnabled, runOcr } from '../../common/OcrEngine';
import { isDsDocServerEnabled, isPhotoEditEnabled, isPhotoSaveGalleryEnabled } from '../../common/AppPreferences';
import {
  DS_FILES_PURPOSE_RICH, DS_FILES_UPLOAD_MAX_BYTES, dsFilesPurposeFor,
  dsFilesRejectReason, DsFilesUploadOutcome, DsFilesUploadTarget, resolveDsUploadTarget,
  uploadDsFile
} from '../../common/providers/DsFilesClient';
import { CHAT_DS_OFFICIAL_AVAILABLE_KEY, isDsFlashConnection }
  from '../../common/providers/DsServerTools';
import { CHAT_PERMISSION_MODE_CONV_KEY } from '../../common/AppPreferences';
import { putThumb, removeThumb } from './AttachmentThumbStore';
import { hilog } from '@kit.PerformanceAnalysisKit';

// 数量上限（人为防误操作堆积——协议无上限）；单文件大小上限：图片 20MB（重采样后常态
// <1MB）、文本 30MB（上限只决定能不能加进来；运行时代价由 AttachmentUtil.readAttachmentText
// 的 12 万字符有界读兜住——准入放宽后请求体与内存不随之放大）、文档 30MB（分型硬上限的
// 最宽值——入列粗拦，精判在解析域 docHardLimitBytes）
export const MAX_ATTACHMENTS: number = 5;
export const MAX_IMAGE_BYTES: number = 20 * 1024 * 1024;
export const MAX_TEXT_BYTES: number = 30 * 1024 * 1024;
export const MAX_DOC_BYTES: number = 30 * 1024 * 1024;

// 附件入口三形态（半模态三格方卡：拍照 / 照片 / 系统文件）
export type FilePickKind = 'camera' | 'photo' | 'file';

// 页面状态回落回调（注入——「页面 → 控制器」单向依赖；附件常驻区口径见文件头，本接口
// 无 isPrivate 位）
export interface AttachmentPickRefs {
  getHostContext: () => common.UIAbilityContext | undefined;
  getAttachments: () => PendingAttachment[];
  setAttachments: (attachments: PendingAttachment[]) => void;
  toast: (text: string) => void;
  // 当前会话连接只读通道（ChatPage.conn 活连接——本会话内存覆盖的同链真值）。
  // ★ 2026-11-14 自检报告 §4.1 修：服务端附件上传目标解析需要它——新建会话尚无
  // conversations 行时 DB 查不到模型覆盖，只读 DB 会落到默认助手连接（多服务商下
  // 选 PDF 报「未能定位官方连接」）；活连接优先 + DB 链回落（见 DsFilesClient）。
  conn: () => AiConnection | null;
  // 待发图片裁剪页跳转（ChatPage 注入路由栈）：入参 = 已落沙箱的图片绝对路径，
  // 回执 = 成品路径 / 原图路径（编辑失败按原图入列）/ ''（返回键放弃这张）+ 预解缩略图
  //（PhotoEditOutcome，非空即免二次解码，见该接口注释）。
  // 契约：永不 reject，异常由本控制器降级为「按原图入列 + 中文提示」
  editPhoto: (srcPath: string) => Promise<PhotoEditOutcome>;
}

// 时间戳文件名（yyyyMMdd_HHmmss，纯展示用途，本地时区；dshinhm 同款）
function timestampName(): string {
  const d: Date = new Date();
  const pad = (n: number): string => n < 10 ? '0' + n : '' + n;
  return '' + d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate()) + '_' +
    pad(d.getHours()) + pad(d.getMinutes()) + pad(d.getSeconds());
}

// 粘贴件显示名：与「拍照_/照片_/文件_」先例同形——前缀标明来源、时间戳区分同秒多件；
// .txt 落在文本白名单内，enqueue 的类型判定天然放行（物理名另取 fileId，与显示名分离）。
// 导出为纯函数以便断言直跑
export function pastedTextName(): string {
  return '粘贴_' + timestampName() + '.txt';
}

// 预创建空白文件（相机 saveUri 目标——系统相机直接覆写；先删后建防旧残留）
function prepareEmptyFile(path: string): void {
  try {
    fs.unlinkSync(path);
  } catch {
    // 文件不存在 = 目标状态
  }
  const f: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
  fs.closeSync(f);
}

// 整段写文本文件（READ_WRITE|CREATE|TRUNC 覆盖写 + finally 成对 closeSync）。失败上抛给调用方处置
function writeTextFile(path: string, content: string): void {
  const f: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE |
    fs.OpenMode.TRUNC);
  try {
    fs.writeSync(f.fd, content);
  } finally {
    fs.closeSync(f);
  }
}

// picker uri 尾部文件名提取（decode 后带扩展名才可信；取不到/无扩展名兜底 fallback）
function pickerFileName(uri: string, fallback: string): string {
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

// 缩略图目标边长单源在 AttachmentUtil.ATTACH_THUMB_EDGE_PX（编辑页预解与入列解码同尺，
// 两处各写一份字面量会漂移）；本文件只消费该常量

// 组合清理（缩略图仓库 release + 沙箱副本删除）：未发送附件离页、移除、载荷失败降级三处
// 调用——「未随消息发送的附件不驻留」防线在此收口
export function cleanupAttachments(atts: PendingAttachment[]): void {
  for (const att of atts) {
    removeThumb(att.fileId);
  }
  removeAttachFiles(atts);
}

// 仅释放缩略图：发送成功路径——文件常驻 filesDir 供历史气泡附件条与预览消费，只清内存态
// 缩略图（PixelMap 有界红线）
export function releaseAttachmentThumbs(atts: PendingAttachment[]): void {
  for (const att of atts) {
    removeThumb(att.fileId);
  }
}

// 粘贴/批量上屏拦截判定：开关开、文本非纯空白、长度达到阈值（含等于）三条件同时成立才把
// 这段文本转成附件。★ 判定规则**只此一处**：输入栏 onPaste / onWillInsert 与直跑断言同引
// 本函数，禁在组件里另写一份条件（两处即漂移面）。纯函数无平台依赖。
// ★ 两条通路文本来源不同、判据同一个：onPaste 给「剪贴板里要粘贴的内容」，onWillInsert
// 给「输入法这一次要插入的内容」——后者含输入法剪贴板粘贴与语音输入等批量上屏（普通打字
// 每次 1~2 字恒不过线）
export function shouldPasteAsFile(value: string, enabled: boolean, threshold: number): boolean {
  return enabled && value.trim() !== '' && value.length >= threshold;
}

// 输入法通路的拦截判定：被拦 = 这一段不是 onPaste 已受理的那段（去重——真机若出现
// preventDefault 没拦下的情形，两条通路上屏同一段文本会各转一次），且判定函数说该转。
// ★ 阈值与开关仍只由 shouldPasteAsFile 判，本函数只多管「是不是重复的一段」
export function shouldInterceptInsert(inserted: string, lastHandled: string, enabled: boolean,
  threshold: number): boolean {
  return inserted !== lastHandled && shouldPasteAsFile(inserted, enabled, threshold);
}

// 本次粘贴的原文是否已落进输入框（= 原生插入发生了）。判据 = 长度恰好多出本次粘贴的长度，
// 且去掉其中一处该原文后与粘贴前逐字相同（插在中间也认——不假定插在末尾）。
// ★ 原文与框内已有文本构成重复子串时逐位置试删（循环 indexOf 前进一位）：只试第一处会在
// 重叠面误判未落框——settlePastedText 随之走错分支，破坏「二者恰有其一」不变式
export function pasteLanded(current: string, before: string, pasted: string): boolean {
  if (pasted === '' || current.length !== before.length + pasted.length) {
    return false;
  }
  let at: number = current.indexOf(pasted);
  while (at >= 0) {
    if (current.substring(0, at) + current.substring(at + pasted.length) === before) {
      return true;
    }
    at = current.indexOf(pasted, at + 1);
  }
  return false;
}

// 粘贴收口：对账「附件建成了没有」与「原文落框了没有」两个事实，返回输入框应有的文本。
// ★ 不变式 = 二者恰有其一（用户要么看到附件、要么看到原文，不重复也不落空）：
//  · converted 真且 landed 真 → 撤回粘贴前快照（附件已代表它，框里不该再留一份）
//  · converted 假且 landed 假 → 向**当前**文本追加（转附件没成，内容一字不丢）
//  · 其余两种（一致态）= 已成立，原样返回入参（调用方据此零写入）
// ★ 补回一支取 `current` 而非 `before` 起头：转附件是异步落盘，返回时用户可能继续打了字
// ——以 before 起头会把那几个字吞掉。
// 为何要这一层：PasteEvent.preventDefault 是可选成员，拦不拦得住原生插入是平台行为——
// 拦住了 landed 恒假（与旧行为逐字等价），拦不住才需要本函数把重复/丢失纠正回来
export function settlePastedText(current: string, before: string, pasted: string,
  converted: boolean): string {
  const landed: boolean = pasteLanded(current, before, pasted);
  if (converted && landed) {
    return before;
  }
  if (!converted && !landed) {
    return current + pasted;
  }
  return current;
}

// 未发送附件按下标移除（自 ChatPage 迁入——附件数组的增删都在本件，页面只持 @State 本体）。
// 删除三件成对：缩略图 release + 沙箱副本删除（cleanupAttachments）+ 数组去掉该项——本地
// 状态独占，无网络副作用
export function removePendingAttachment(atts: PendingAttachment[],
  index: number): PendingAttachment[] {
  const removed: PendingAttachment = atts[index];
  cleanupAttachments([removed]);
  return atts.filter((_: PendingAttachment, i: number): boolean => i !== index);
}

// 草稿回写：取消三路（取消键 / 遮罩 / 返回键）须把用户打的这段文字还回去，否则附件留了、
// 文字没了。回写通道由调用方注入（覆盖式重写，与面板「关闭即回写胶囊」同一条链）；
// 空串不回写（零状态写）
export function restoreDraftText(writeback: (text: string) => void, text: string): void {
  if (text !== '') {
    writeback(text);
  }
}

// 系统分享桥消费（域函数单源——调用方仅 ChatPage.onPageShown 一处接线）：shareTick 与桥批次号
//（PENDING_SHARES_TICK_KEY）匹配才消费——本页即该批次落点页；旧分享页重显与非分享拉起页
//（tick 0）零动作。分发：文件件（uri 非空）→ addFromSharedUris 批量入列；文本件 → 追并一段
// 进输入框（回写通道由调用方注入）。消费即清桥（一次性）；桥损坏按空批处理留痕。
// 永不 reject（与 addPastedText 契约族同）
export function consumePendingShareInto(shareTick: number, ctrl: AttachmentPickCtrl,
  writeInput: (text: string) => void): void {
  if (shareTick <= 0) {
    return; // 非分享拉起的页面（标题栏「＋」/ 打开会话 / 打开方式以外的普通 push）
  }
  const currentTick: number = AppStorage.get<number>(PENDING_SHARES_TICK_KEY) ?? 0;
  if (currentTick !== shareTick) {
    return; // 旧分享页重显：批次已被新批次覆写顶替（桥恒只留最新一批）
  }
  const stored: string | undefined = AppStorage.get<string>(PENDING_SHARES_KEY);
  if (stored === undefined || stored === '') {
    return;
  }
  let items: PendingSharedItem[] = [];
  try {
    const parsed: object = JSON.parse(stored) as object;
    // 非数组形态按空批（写入侧只有 EntryAbility 自产 stringify，正常不可达——防御面）
    if (Array.isArray(parsed)) {
      items = parsed as PendingSharedItem[];
    }
  } catch (e) {
    // 桥损坏按空批处理（P0-1 留痕）
    hilog.warn(0xD5A0, 'AttachPick', '分享桥数据损坏按空批处理：%{public}s', (e as Error).message);
    return;
  }
  AppStorage.setOrCreate<string>(PENDING_SHARES_KEY, '[]');
  const fileItems: PendingSharedItem[] = [];
  let textAcc: string = '';
  for (const item of items) {
    if (item.uri !== '') {
      fileItems.push(item);
    } else if (item.content !== '') {
      textAcc = textAcc === '' ? item.content : textAcc + '\n' + item.content;
    }
  }
  if (textAcc !== '') {
    writeInput(textAcc);
  }
  if (fileItems.length > 0) {
    ctrl.addFromSharedUris(fileItems); // 内部逐件 try/catch 永不 reject
  }
}

export class AttachmentPickCtrl {
  private apply: AttachmentPickRefs;
  private seq: number = 0; // fileId 会话内序号（+ 时间戳保证跨会话唯一）

  constructor(apply: AttachmentPickRefs) {
    this.apply = apply;
  }

  // 面板三卡入口 → 选择器 → 拷沙箱 → 入列；用户取消静默；失败中文提示
  async pick(kind: FilePickKind): Promise<void> {
    const current: PendingAttachment[] = this.apply.getAttachments();
    if (current.length >= MAX_ATTACHMENTS) {
      this.apply.toast('最多同时附加 ' + MAX_ATTACHMENTS + ' 个文件');
      return;
    }
    let ctx: common.UIAbilityContext | undefined = undefined;
    try {
      ctx = this.apply.getHostContext();
      if (ctx === undefined) {
        throw new Error('无法获取应用上下文');
      }
      const dir: string = ensureAttachDir(ctx, true);
      const stamp: string = timestampName();
      // 「添加图片时编辑」现读（拨动即生效）：只作用于相机与相册两入口，系统文件/重发/分享/
      // 粘贴件一律不传（缺省 false），逐字保持既有入列链
      const editFirst: boolean = isPhotoEditEnabled();
      if (kind === 'camera') {
        if (isPhotoSaveGalleryEnabled()) {
          // 拍照保存到相册开：不传 saveUri——系统相机直接落系统相册（官方语义「未配置该项
          // 默认存入媒体库」），返回媒体库 URI（临时授权可读）；随后 fd 级拷入沙箱供发送
          //（与「照片」入口同链）。★ 取消无预创建文件、零清理
          const result: cameraPicker.PickerResult = await cameraPicker.pick(ctx,
            [cameraPicker.PickerMediaType.PHOTO],
            { cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK });
          if (result.resultCode !== 0) {
            return; // 用户取消/失败：静默（取消是常见路径）
          }
          await this.enqueue('拍照_' + stamp + '.jpg', dir, result.resultUri, null, null, editFirst);
        } else {
          // 默认路：官方 saveUri 姿势——预创建沙箱空白文件（唯一名），系统相机直接覆写，
          // resultUri === saveUri、无授权时效；只落沙箱、相册零痕迹
          const ext: string = 'jpg';
          const path: string = dir + '/' + this.nextFileId() + '.' + ext;
          prepareEmptyFile(path);
          const result: cameraPicker.PickerResult = await cameraPicker.pick(ctx,
            [cameraPicker.PickerMediaType.PHOTO],
            {
              cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK,
              saveUri: fileUri.getUriFromPath(path)
            });
          if (result.resultCode !== 0) {
            removeAttachFile(path); // 取消：清预创建空文件
            return; // 用户取消/失败：静默（取消是常见路径）
          }
          await this.enqueue('拍照_' + stamp + '.jpg', dir, null, path, null, editFirst);
        }
      } else if (kind === 'photo') {
        // 官方图片选择器（免权限）：多选至剩余额度；临时授权 URI → fd 级拷入沙箱
        const remain: number = MAX_ATTACHMENTS - current.length;
        const photoPicker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
        const selectResult: photoAccessHelper.PhotoSelectResult = await photoPicker.select({
          MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
          maxSelectNumber: remain
        });
        if (selectResult.photoUris.length === 0) {
          return; // 用户取消，静默
        }
        for (let i = 0; i < selectResult.photoUris.length; i++) {
          const name: string = selectResult.photoUris.length > 1 ?
            '照片_' + stamp + '_' + (i + 1) + '.jpg' : '照片_' + stamp + '.jpg';
          await this.enqueue(name, dir, selectResult.photoUris[i], null, null, editFirst);
        }
      } else {
        // 官方文档选择器（context 构造，免权限声明）：按扩展名分流，循环入列至剩余额度。
        // ★ 必须显式设 maxSelectNumber = 剩余额度——未设时系统面板默认多选（d.ts 上限
        // 500），选超额度的件在下方循环被 i < remain 静默截断丢弃
        const remain: number = MAX_ATTACHMENTS - current.length;
        const docOpts: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
        docOpts.maxSelectNumber = remain;
        const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
        const uris: Array<string> = await docPicker.select(docOpts);
        if (uris.length === 0) {
          return; // 用户取消，静默
        }
        for (let i = 0; i < uris.length && i < remain; i++) {
          const fallback: string = uris.length > 1 ?
            '文件_' + stamp + '_' + (i + 1) : '文件_' + stamp;
          await this.enqueue(pickerFileName(uris[i], fallback), dir, uris[i], null);
        }
      }
    } catch (e) {
      this.apply.toast('添加附件失败：' + (e as Error).message);
    }
  }

  // 粘贴长文本转附件：写盘成一个 .txt 附件并入列——用户看到的是附件条上多一件，而不是
  // 输入框里多一大段。返回值 = 是否已入列；false = 未入列（**toast 已由本方法发出**，
  // 调用方只需把粘贴文本回退给输入框）。契约：**永不 reject**——一切失败都转成 false +
  // 中文 toast，调用方不写 try/catch（同 runOcr 契约族）。
  // 校验一律下沉：空文件闸/大小闸/类型判定/入库行形态全由 enqueue 承担（禁在粘贴侧重写一份）
  async addPastedText(text: string): Promise<boolean> {
    if (text.trim() === '') {
      return false; // 空白自守（输入栏侧已同步判掉——防将来第二个调用方直接调本方法）
    }
    if (this.apply.getAttachments().length >= MAX_ATTACHMENTS) {
      // 与 pick() 同源同句（上限文案只此一处来源）
      this.apply.toast('最多同时附加 ' + MAX_ATTACHMENTS + ' 个文件');
      return false;
    }
    let dir: string = '';
    let path: string = '';
    try {
      const ctx: common.UIAbilityContext | undefined = this.apply.getHostContext();
      if (ctx === undefined) {
        this.apply.toast('无法获取应用上下文');
        return false;
      }
      dir = ensureAttachDir(ctx, true); // 恒常驻区（口径见文件头）
      // 物理名与显示名分离（相机路先例）：物理名 = fileId（唯一，且入库存相对路径），
      // 显示名 = 粘贴_<时间戳>.txt；连续多次粘贴各成一件、互不覆盖
      path = dir + '/' + this.nextFileId() + '.txt';
      writeTextFile(path, text);
    } catch (e) {
      removeAttachFile(path); // 删半成品（禁留无行文件给启动收敛）
      hilog.warn(0xD5A0, 'AttachPick', '粘贴件写盘失败：%{public}s', (e as Error).message);
      this.apply.toast('粘贴转附件失败');
      return false;
    }
    try {
      await this.enqueue(pastedTextName(), dir, null, path);
      return true;
    } catch (e) {
      // enqueue 拒绝（类型不支持/空文件/越限等）——越限时它已自删副本，此处 removeAttachFile
      // 幂等，重复调用无害；toast 用其既有中文文案（如「…超过 30MB 上限」），不另造提示
      removeAttachFile(path);
      this.apply.toast((e as Error).message);
      return false;
    }
  }

  // 重发文件复制入列（「会话设置」面板「重发文件」子面板行点击上行）：把已发附件或工作区
  // 文件复制成新副本再走 enqueue 全链（与选择器/粘贴入口完全同源——类型/空文件/大小/图片
  // 解码闸全部沿用，本方法零新校验）。契约同 addPastedText：**永不 reject**，返回是否已入列
  // （false 时 toast 已由本方法发出）。
  // · srcRelPath 收任意 filesDir 相对路径（附件行 localPath 与工作区行 localPath 两源通吃——
  //   copyAttachmentResource 对源无前缀校验只查在场与非空，r2 复核实证）；dest 恒落
  //   attachments/<新名>，与 ensureAttachDir(ctx, true) 同目录；三闸 fail-closed 中文 Error +
  //   失败自清半截目标 + 在途保护（mtime 晚于进程启动不判孤儿）全在 AttachmentDb 内收口。
  // · 物理名与显示名分离（粘贴路先例）：新 fileId 铸名、源行名只作显示名——同一行可再点，
  //   每次新副本互不覆盖。
  // · guide（★ 2026-10-31 重发降级笔）：重发面板行来源上下文，只在解析完成且正文截断时消费
  //   （degradeTruncatedDoc）；普通三入口与粘贴/分享链不传 = 恒 null = 零降级。
  async addCopiedFromFile(displayName: string, srcRelPath: string,
    guide: ReissueGuideContext | null = null): Promise<boolean> {
    if (this.apply.getAttachments().length >= MAX_ATTACHMENTS) {
      // 与 pick() 同源同句（上限文案只此一处来源——第五处同句）
      this.apply.toast('最多同时附加 ' + MAX_ATTACHMENTS + ' 个文件');
      return false;
    }
    let dir: string = '';
    let path: string = '';
    try {
      const ctx: common.UIAbilityContext | undefined = this.apply.getHostContext();
      if (ctx === undefined) {
        this.apply.toast('无法获取应用上下文');
        return false;
      }
      dir = ensureAttachDir(ctx, true); // 恒常驻区（幂等预建；副本落点与它同目录）
      const newRelPath: string = copyAttachmentResource(srcRelPath,
        this.nextFileId() + '.' + extOf(displayName));
      path = ctx.filesDir + '/' + newRelPath;
    } catch (e) {
      // 源缺失/源为空/IO 失败（copyAttachmentResource 三闸，含「行在文件不在」存量形态）——
      // 半截目标已由库函数自清；点名句式照 fork 先例（ConversationForkCopy）
      hilog.warn(0xD5A0, 'AttachPick', '重发件复制失败：%{public}s', (e as Error).message);
      this.apply.toast('附件「' + displayName + '」复制失败：' + (e as Error).message);
      return false;
    }
    try {
      await this.enqueue(displayName, dir, null, path, guide);
      return true;
    } catch (e) {
      // enqueue 拒绝（类型闸在 path 生成前 throw 且不删调用方文件——照 addPastedText 先例补删；
      // 其余拒绝闸已自带副本自删，此处 removeAttachFile 幂等无害）；toast 用其既有中文文案
      removeAttachFile(path);
      this.apply.toast((e as Error).message);
      return false;
    }
  }

  // 系统分享件批量入列：分享/打开方式拉起的文件件（uri 非空）逐一走 enqueue 全链（与选择器
  // 入口完全同源——禁另立一份入列链）。数量闸 = 剩余额度截断（文案与 pick 同源同句）；单件
  // 失败不停整批（enqueue 已自删半成品并带中文文案，本层逐件透传 toast）。★ 整体 try 必须包
  // 全函数：本函数被消费链 fire-and-forget 调用（consumePendingShareInto 不 await），且
  // ensureAttachDir 非 EEXIST 即 throw——开头段异常若不 toast 兜住 = unhandled rejection +
  // 附件静默丢失（「永不 reject」承诺面 = 全函数，不只循环内）
  async addFromSharedUris(items: PendingSharedItem[]): Promise<void> {
    try {
      const current: PendingAttachment[] = this.apply.getAttachments();
      const room: number = MAX_ATTACHMENTS - current.length;
      if (room <= 0) {
        this.apply.toast('最多同时附加 ' + MAX_ATTACHMENTS + ' 个文件');
        return;
      }
      const batch: PendingSharedItem[] = items.length > room ? items.slice(0, room) : items;
      if (batch.length < items.length) {
        this.apply.toast('最多同时附加 ' + MAX_ATTACHMENTS + ' 个文件');
      }
      const ctx: common.UIAbilityContext | undefined = this.apply.getHostContext();
      if (ctx === undefined) {
        this.apply.toast('无法获取应用上下文');
        return;
      }
      const dir: string = ensureAttachDir(ctx, true); // 恒常驻区（与选择器入口同）
      for (const item of batch) {
        try {
          await this.enqueue(this.sharedDisplayName(item), dir, item.uri, null);
        } catch (e) {
          this.apply.toast((e as Error).message);
        }
      }
    } catch (e) {
      this.apply.toast((e as Error).message);
    }
  }

  // 分享件显示名：title 优先但须带点（类型判定靠扩展名，发送方可自拟无扩展名的标题——
  // 无点不可信）；无点则从 uri 尾段提取（pickerFileName 自带 decode 与「带点才可信」判定，
  // 与选择器入口同款）；再兜时间戳名（无扩展名会被 enqueue 类型判定拦下——不留判不出的件）
  private sharedDisplayName(item: PendingSharedItem): string {
    const title: string = item.title.trim();
    if (title !== '' && title.indexOf('.') > 0) {
      return title;
    }
    return pickerFileName(item.uri, title !== '' ? title : '分享_' + timestampName());
  }

  // 单个附件入列：类型判定（不支持即拦）→ 落位（preparedPath = 相机已落沙箱的成品路径，否则
  // fd 级拷贝 srcUri）→【可选】待发图片裁剪页编辑（回执含预解缩略图）→ 大小校验 → 缩略图
  // 入仓（预解命中即免二次解码）→ 入列上行。
  // ★ editFirst 只由 pick 的相机/相册两分支传入：源图先落沙箱才进编辑页（媒体库临时授权
  // URI 不跨页），回执 = 成品路径 / 原图路径 / ''（放弃）。原图副本在**入列成功后**才删，
  // 保证大小闸或解码闸拒绝时照片不丢。
  private async enqueue(displayName: string, dir: string, srcUri: string | null,
    preparedPath: string | null, guide: ReissueGuideContext | null = null,
    editFirst: boolean = false): Promise<void> {
    const kind: string = classifyByName(displayName);
    if (kind === '') {
      throw new Error('暂仅支持图片、文本与文档类附件（' + displayName + '）');
    }
    const fileId: string = this.nextFileId();
    const path: string = preparedPath !== null ? preparedPath :
      dir + '/' + fileId + '.' + extOf(displayName);
    if (srcUri !== null) {
      copyFileExact(srcUri, path);
    }
    let finalPath: string = path;
    // 编辑页预解缩略图（所有权在本层）：唯一转交出口 = putThumb，其余出口（放弃 / 空文件 /
    // 超上限 / 读盘失败）一律当场 release——PixelMap 是 native 资源，不释放不会被 GC 回收
    let prewarmedThumb: image.PixelMap | null = null;
    const dropPrewarm: () => void = (): void => {
      if (prewarmedThumb !== null) {
        prewarmedThumb.release();
        prewarmedThumb = null;
      }
    };
    if (editFirst && kind === 'image') {
      let edited: PhotoEditOutcome | null = null;
      try {
        edited = await this.apply.editPhoto(path);
      } catch (e) {
        // 编辑页契约承诺永不 reject；此处兜底 = 中文提示 + 按原图入列（零静默失败/零丢失）
        this.apply.toast('图片编辑失败，将使用原图：' + (e as Error).message);
        edited = null; // null = 兜底按原图入列（≠ 放弃），finalPath 保持原图副本
      }
      if (edited !== null) {
        if (edited.path === '') {
          // 编辑页返回键 = 放弃这张照片：删沙箱副本，本件不入列（多选时继续下一张）。
          // 契约外防御：放弃回执本不带预解图，真带了也必须释放
          if (edited.thumb !== null) {
            edited.thumb.release();
          }
          removeAttachFile(path);
          return;
        }
        finalPath = edited.path;
        prewarmedThumb = edited.thumb;
      }
    }
    let stat: fs.Stat;
    try {
      stat = fs.statSync(finalPath);
    } catch (e) {
      // 成品读盘失败（外部清盘的极端面）：预解图当场释放，中文原因上抛给 pick 的 catch
      dropPrewarm();
      throw new Error('文件读取失败（' + displayName + '）：' + (e as Error).message);
    }
    if (stat.size <= 0) {
      dropPrewarm();
      removeAttachFile(finalPath);
      throw new Error('文件为空（' + displayName + '）');
    }
    // DS 服务端解析候选（S4② 判据：镜像键「DeepSeek 官方可用」× 文档解析开关 × 三扩展
    // 〔dsFilesPurposeFor 落 RICH 档〕——纯函数面在 DsFilesClient，本处只组 AppStorage 现读）。
    // 命中时单件闸换 100MiB 档（DS_FILES_UPLOAD_MAX_BYTES——官方 PDF/Word/PPT 上限），未命中
    // 照既有分型上限（.pdf 30MB 等）
    const dsServerCandidate: boolean = kind === 'doc' &&
      AppStorage.get<boolean>(CHAT_DS_OFFICIAL_AVAILABLE_KEY) === true && isDsDocServerEnabled() &&
      dsFilesPurposeFor(displayName) === DS_FILES_PURPOSE_RICH;
    const cap: number = dsServerCandidate ? DS_FILES_UPLOAD_MAX_BYTES :
      (kind === 'image' ? MAX_IMAGE_BYTES :
        (kind === 'doc' ? MAX_DOC_BYTES : MAX_TEXT_BYTES));
    if (stat.size > cap) {
      dropPrewarm();
      removeAttachFile(finalPath);
      throw new Error(displayName + ' 超过 ' + (cap / 1024 / 1024) + 'MB 上限');
    }
    if (kind === 'image') {
      // 缩略图入模块级仓库（PixelMap 不走组件参数——@Prop 深拷贝破坏，见仓库头注释）。
      // ★ 编辑页已预解则直接入仓、跳过这次解码：旧链这里要等一次异步解码（真机实测 16ms），
      // 入列因此落进返回转场第 2 帧，胶囊高度一帧内 93→173vp 跳变 = 观感「闪」
      //（2026-11-05 2109 闪修）；解码与预解都拿不到 = 图片不可解码（发送时同链路必失败）
      //——删副本当场拒绝，不留无回收通道的附件
      let thumb: image.PixelMap | undefined = prewarmedThumb !== null ? prewarmedThumb : undefined;
      if (thumb === undefined) {
        try {
          thumb = await decodeScaled(finalPath, ATTACH_THUMB_EDGE_PX, true);
        } catch {
          thumb = undefined;
        }
      }
      if (thumb === undefined) {
        removeAttachFile(finalPath);
        throw new Error('图片无法解码（' + displayName + '）');
      }
      putThumb(fileId, thumb);
      prewarmedThumb = null; // 所有权移交仓库，不再由本层释放
    }
    const next: PendingAttachment[] = this.apply.getAttachments().slice();
    const att: PendingAttachment = {
      fileId: fileId,
      name: displayName,
      mediaType: kind === 'image' ? imageOutMime(displayName) :
        (kind === 'doc' ? docMime(displayName) : 'text/plain'),
      size: stat.size,
      kind: kind,
      localPath: finalPath
    };
    // 图片附件 OCR 预置：同步先置 running 再入列——先 await 后置态会留一个「无识别文本、
    // 状态也非 running」的窗口，此刻发送会静默退回无 OCR 行为（终态兜底红线）
    if (kind === 'image' && ocrEnabled()) {
      att.ocrState = 'running';
    }
    next.push(att);
    this.apply.setAttachments(next);
    // 裁剪产物已入列且大小闸/解码闸都过了，此刻才删原图副本不留孤儿（成品路径由离页
    // cleanupAttachments 统一回收）。编辑失败回执 = 原图路径，两路径相同恒不删
    if (finalPath !== path) {
      removeAttachFile(path);
    }
    if (kind === 'doc') {
      // DS 服务端解析旁路（DS 全家桶接入批 S4②）：候选判据全中（镜像键 × 开关 × 三扩展，
      // 上限已由 cap 换 100MiB 档把守）→ 跳过本地解析走异步上传——**不跑本地 OCR 与页图**
      //（分型上限判据链不触发的旁路，docParser 队列零占用）。文件名字节闸（≤512，官方限制）
      // 在此终检——越限中文报错拒收（同族闸既有形态：自清副本 + throw 给 pick 的 catch 呈报）
      if (dsServerCandidate) {
        const reject: string = dsFilesRejectReason(displayName, stat.size);
        if (reject !== '') {
          removeAttachFile(finalPath);
          throw new Error(reject);
        }
        this.uploadToDsServer(fileId, finalPath, displayName, att.mediaType, stat.size);
        return;
      }
      // 文档解析排程：入列即异步解析（分型上限精判在解析域，超限置 toolarge 态）；完成态
      // 经附件数组整体替换上行刷新——发送前置拦 attachBlockingReason（解析域
      // docBlockingReason + OCR running）
      const patch: (result: DocumentParseResult, state: string) => void =
        (result: DocumentParseResult, state: string): void => {
          this.patchAttachment(fileId, (target: PendingAttachment): void => {
            target.parseState = state;
            target.parsedText = result.text;
            target.parseError = result.error;
            target.parseTruncated = result.truncated;
            // 页图与全量页数（非 PDF/未渲染 = 空数组与 0）
            target.pageImages = result.pageImages;
            target.pageCount = result.pageCount;
          });
        };
      const limit: number = docHardLimitBytes(att);
      if (limit > 0 && att.size > limit) {
        patch(new DocumentParseResult(), 'toolarge');
        return;
      }
      patch(new DocumentParseResult(), 'parsing');
      docParser.parseAttachment(att)
        .then(async (result: DocumentParseResult): Promise<void> => {
          // 空文本成功态归 failed：解析成功但 text 空（扫描件/图片型文档）≠ 可发送，防
          // 「标注在、内容缺」。★ 放宽：判据命中且**页图拉齐**的 PDF 不归 failed——页图即
          // 内容（零文字层扫描件正是要打通的）；无页图（渲染失败/未命中判据）时维持旧语义
          //（文本也空 = failed 照旧拦，docx/xlsx/ofd 零回归）
          if (result.success && result.text.trim() === '' && result.pageImages.length === 0) {
            result.success = false;
            result.error = '未提取到文本内容（可能是扫描件或图片型文档）';
          }
          // OCR 步骤（doc 路）：解析成功且带页图的扫描件在此续识别——done 态在「解析 +
          // 渲染 + 识别」全完成后才由下方 patch 置位，识别期间附件保持 'parsing'（UI 零新增
          // 态），发送阻断天然覆盖
          if (ocrEnabled() && result.success && result.pageImages.length > 0) {
            const sources: OcrImageSource[] = [];
            for (const page of result.pageImages) {
              sources.push({ kind: 'base64', data: page.data });
            }
            this.patchAttachment(fileId, (target: PendingAttachment): void => {
              target.ocrState = 'running';
            });
            // 终态兜底：runOcr 契约永不 reject，try/finally 再兜一层——异常若跳过定态 =
            // 附件永停 'parsing' = 用户永久发不出去
            try {
              const outcome: OcrOutcome = await runOcr(sources, this.apply.toast);
              this.patchAttachment(fileId, (target: PendingAttachment): void => {
                target.ocrText = outcome.ok ? outcome.text : '';
                target.ocrState = outcome.ok ? 'done' : 'failed';
              });
            } finally {
              this.patchAttachment(fileId, (target: PendingAttachment): void => {
                if (target.ocrState === 'running') {
                  target.ocrText = '';
                  target.ocrState = 'failed';
                }
              });
            }
          }
          patch(result, result.success ? 'done' : 'failed');
          // 重发入列件的叠加式降级判定（★ 重发降级笔 §四-1）：只在本链（guide 非空）判；
          // 普通选择器/粘贴/分享件 guide 恒 null——即使截断也不降级（授权范围只到重发域）。
          // 自带 try 兜底（2026-10-31 自检修复笔）：此刻态已定 done，异常若放给外层 catch
          // 会把完成件改判 failed（错误文案还是空的）——降级链失败语义 = 不挂指引照常发送，
          // 绝不翻已定终态
          try {
            await this.degradeTruncatedDoc(att.name, fileId, result, guide);
          } catch (e) {
            hilog.warn(0xD5A0, 'AttachPick', '重发降级链异常：%{public}s', (e as Error).message);
          }
        })
        .catch((e: Object): void => {
          const failed: DocumentParseResult = new DocumentParseResult();
          failed.error = (e as Error).message;
          patch(failed, 'failed');
        });
    } else if (kind === 'image' && ocrEnabled()) {
      // 图片附件识别：异步发起不阻塞入列循环——多选时逐件串行由 OcrEngine 内部队列保证；
      // 终态经 patchAttachment 上行（附件被删 = fileId 不在列静默丢弃，防幽灵写回）。
      // 识别失败不阻断发送
      runOcr([{ kind: 'path', data: att.localPath }], this.apply.toast)
        .then((outcome: OcrOutcome): void => {
          this.patchAttachment(fileId, (target: PendingAttachment): void => {
            target.ocrText = outcome.ok ? outcome.text : '';
            target.ocrState = outcome.ok ? 'done' : 'failed';
          });
        })
        .catch((e: Object): void => {
          // runOcr 契约永不 reject——防御分支仍定终态（漏定态 = 附件永停识别中）
          hilog.warn(0xD5A0, 'AttachPick', '图片识别异常终态兜底：%{public}s', (e as Error).message);
          this.patchAttachment(fileId, (target: PendingAttachment): void => {
            target.ocrText = '';
            target.ocrState = 'failed';
          });
        });
    }
  }

  // DS 服务端上传链（DS 全家桶接入批 S4②）：入列即异步上传取 file_id——目标解析
  //（resolveDsUploadTarget：会话级连接同链收敛 + 启用序首支 key，落空 = fail-closed 置
  // failed 态不误传非官方端点）→ uploadDsFile（multipart，parseState 复用三态：'parsing'
  // 上传中 / 'done' 带 remoteFileId / 'failed' 带中文错误）。remotePending 与 parseState
  // 同拍写（附件官方标记笔——副行区分「上传中」与本地「解析中」，终态清除）。
  // ★ 组件异步链销毁守卫（1712 全站纪律）：状态写全经 patchAttachment——fileId 不在列
  //（附件被删/离页清扫）= 零状态写静默丢弃（本件既有异步链同款 departed 判，docParser /
  // OCR 回调同口径）；上传请求本体照常（不因离页中止——「写库/对象更新照常、只放弃 UI
  // 与上行」）；toast 走 refs 注入通道（离页后晚到与重发降级链同形，契约族允许）
  // 单件重试（二期 S4 #12；附件条失败态经 AttachmentRetrySupport 一跳到达）。口径：
  // · **只处理 parseState='failed' 的文档件**——parsing/done/toolarge 点了不动作（不做无意义
  //   重传，也不打断进行中的解析）；图片件不走上传链，无此失败态。
  // · 按**当前**连接档位分派：官方档重走服务端上传（localPath 绝对路径仍在，pick 链只清
  //   缩略图不删原件）；非官方档的失败不是上传失败，给出可执行说明而不是假装重试。
  // · 本地解析失败的重跑不在本笔范围：docParser 未进 AttachmentPickRefs，要接须改 refs 契约
  //   与 ChatPage 注入面（另一笔的活）。本笔范围收窄已在变更记录登记。
  retryOne(fileId: string): void {
    const att: PendingAttachment | undefined = this.apply.getAttachments()
      .find((item: PendingAttachment): boolean => item.fileId === fileId);
    if (att === undefined || att.parseState !== 'failed' || att.kind !== 'doc') {
      return;
    }
    const conn: AiConnection | null = this.apply.conn();
    if (!isDsFlashConnection(conn)) {
      this.apply.toast('当前会话没有启用服务端解析，请删除后重新添加该文件');
      return;
    }
    this.uploadToDsServer(att.fileId, att.localPath, att.name, att.mediaType, att.size);
  }

  private uploadToDsServer(fileId: string, path: string, displayName: string,
    mime: string, size: number): void {
    this.patchAttachment(fileId, (target: PendingAttachment): void => {
      target.parseState = 'parsing';
      target.parseError = '';
      target.remotePending = true;
    });
    // convId 现读（CHAT_PERMISSION_MODE_CONV_KEY 广播键——写点 = ChatPage enterConversation
    // 既有调用〔aboutToAppear / onShown〕，'' = 本次运行尚未进过会话页；读法与
    // PermissionMode.activeConversationId 同源同值，该函数未导出故按键常量现读）。
    // 第二参 = 页面活连接（§4.1 修）：无行新会话只有内存覆盖，DB 链查不到，活连接优先命中
    resolveDsUploadTarget(AppStorage.get<string>(CHAT_PERMISSION_MODE_CONV_KEY) ?? '',
      this.apply.conn())
      .then((target: DsFilesUploadTarget | null): Promise<DsFilesUploadOutcome> => {
        if (target === null) {
          // 解析落空（新会话无行窗口 / 连接已切走 / 池明文缺失）——可见失败不静默（P0-1），
          // 也不回退本地解析（用户显式开了服务端解析，静默改道 = 静默忽略设置）
          throw new Error('未能定位 DeepSeek 官方连接，请确认当前会话模型与服务商密钥后重试');
        }
        return uploadDsFile(target, path, displayName, mime, size);
      })
      .then((outcome: DsFilesUploadOutcome): void => {
        if (!outcome.ok) {
          this.patchAttachment(fileId, (target: PendingAttachment): void => {
            target.parseState = 'failed';
            target.parseError = outcome.errorText;
            target.remotePending = false;
          });
          this.apply.toast('「' + displayName + '」' + outcome.errorText);
          return;
        }
        this.patchAttachment(fileId, (target: PendingAttachment): void => {
          target.parseState = 'done';
          target.remoteFileId = outcome.fileId;
          target.parseError = '';
          target.remotePending = false;
        });
      })
      .catch((e: Object): void => {
        const reason: string = (e as Error).message;
        this.patchAttachment(fileId, (target: PendingAttachment): void => {
          target.parseState = 'failed';
          target.parseError = reason;
          target.remotePending = false;
        });
        this.apply.toast('「' + displayName + '」上传失败，' + reason);
      });
  }

  // 截断件叠加式降级（★ 2026-10-31 重发降级笔）：解析完成且正文被截断才降级——字节大但未
  // 截断的件内联得下，本就不需要指引（触发信号 = parseTruncated，单源）。两段来源不同：
  // 工作区段直接用面板传来的工作区相对路径（joinDirName(dir, name) 模型面坐标，源本就在
  // 工作区，零导入）；附件段把源行导入工作区拿第二副本（30MB 单件闸 + 容量闸 + 同名覆盖
  // 全在库内收口，本层不重写）。失败路 = 中文 toast + 不挂指引（该件照现状内联截断文本发），
  // 绝不阻断发送。
  private async degradeTruncatedDoc(displayName: string, fileId: string,
    result: DocumentParseResult, guide: ReissueGuideContext | null): Promise<void> {
    // null 显式判在谓词前：谓词只收窄语义、ArkTS 不据此收窄类型（后续取字段须本地非空）
    if (guide === null ||
      !shouldGuideTruncatedDoc(guide, result.success, result.truncated === true)) {
      return;
    }
    let guidePath: string = guide.workspacePath;
    if (guidePath === '') {
      const row: AttachmentListRow | null = guide.sourceRow;
      if (row === null) {
        return; // 双段皆无来源（防御位：面板两段恒给其一）
      }
      try {
        const outcome: ImportOutcome = await importAttachmentToWorkspace(row,
          guide.conversationId, guide.assistantId);
        if (!outcome.ok) {
          this.apply.toast('「' + displayName + '」存入工作区失败，' + outcome.errorText);
          return;
        }
        // 导入回执只带显名与字节数，落位行按 (根目录, 清洗后名) 二元组回查（落库名单源
        // 清洗 = sanitizeWorkspaceName，与导入判定同一份名）。★ 指引路径取 joinDirName(dir,
        // name) 工作区相对路径（2026-10-31 自检修复笔）——workspace 族工具按 (dir, name)
        // 显示名定位，行 localPath 是 filesDir 物理路径带 fileId 铸名，模型面不可解析
        const hits: WorkspaceFileRow[] =
          await queryWorkspaceFilesByName('', sanitizeWorkspaceName(row.name));
        guidePath = hits.length > 0 ? joinDirName(hits[0].dir, hits[0].name) : '';
      } catch (e) {
        this.apply.toast('「' + displayName + '」存入工作区失败，' + (e as Error).message);
        return;
      }
      if (guidePath === '') {
        this.apply.toast('「' + displayName + '」存入工作区后找不到记录，仍按截断内容发送');
        return;
      }
    }
    this.patchAttachment(fileId, (target: PendingAttachment): void => {
      target.guideWorkspacePath = guidePath;
    });
    if (!guide.workspaceToolOn) {
      // 建议非阻断：工具没开时模型仍有头部分可用，指引照组（开启后下轮即生效）
      this.apply.toast('文件过大需转工作区供模型读取，建议在助手工具页开启文件工作区工具');
    }
  }

  // 附件字段原位修补（fileId 定位 → 整数组替换上行——@State 刷新语义与 enqueue 同款；
  // fileId 不在列 = 已被删除，静默丢弃解析结果防幽灵写回）
  private patchAttachment(fileId: string, mutate: (att: PendingAttachment) => void): void {
    const current: PendingAttachment[] = this.apply.getAttachments();
    let hit: boolean = false;
    const next: PendingAttachment[] = current.map((att: PendingAttachment): PendingAttachment => {
      if (att.fileId !== fileId) {
        return att;
      }
      hit = true;
      const copy: PendingAttachment = {
        fileId: att.fileId, name: att.name, mediaType: att.mediaType, size: att.size,
        kind: att.kind, localPath: att.localPath, parseState: att.parseState,
        parsedText: att.parsedText, parseError: att.parseError,
        parseTruncated: att.parseTruncated, pageImages: att.pageImages,
        pageCount: att.pageCount, ocrText: att.ocrText, ocrState: att.ocrState,
        guideWorkspacePath: att.guideWorkspacePath,
        // DS 服务端解析件标记（S4②——上传链写位，漏带 = 每次 patch 丢 remoteFileId，
        // 发送载荷与 collectTools 提示参全空）
        remoteFileId: att.remoteFileId,
        // 官方档上传中标记（附件官方标记笔）：与 remoteFileId 同理逐次带出——本项写点虽只在
        // uploadToDsServer 三拍内，但任何别的 patch（未来新增）漏带即静默清标，键覆盖论不再成立
        remotePending: att.remotePending
      };
      mutate(copy);
      return copy;
    });
    if (hit) {
      this.apply.setAttachments(next);
    }
  }

  private nextFileId(): string {
    this.seq++;
    return 'att' + Date.now() + '_' + this.seq;
  }
}
