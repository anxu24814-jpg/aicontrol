// 聊天页「添加附件」控制器（2026-08-31 附件上传新增——自 dshinhm KimiAttachmentCtrl
// 成熟链路改写：三入口官方选择器 → 沙箱副本 → 缩略图 → 附件入列；页面只持 @State
// attachments（唯一事实源，经 refs 注入读写）——页面 → 控制器单向依赖，零循环 import）。
// 与 dshinhm 的差异（无自有服务器，副本落沙箱后不经服务器中转）：
// · dshinhm 上传服务器后即删沙箱副本（fileId = 服务端 id）；aicontrol 副本以唯一
//   fileId 命名落沙箱（★ 2026-09-09 附件落盘第一轮起：普通/加密会话 = filesDir/
//   attachments 常驻、发送成功保留供预览；隐私会话 = cacheDir/attachments 临时区
//   ——★ 2026-09-15 预览笔起发送成功同样留盘供会话内预览，回收点 = 离页整目录清扫 +
//   启动兜底），发送时读副本编码（AttachmentUtil）；
// · 照片入口多选（maxSelectNumber = 剩余额度；dshinhm 单选——服务器逐个上传场景）；
// · 类型收窄：图片（base64 进请求）+ 纯文本（内容并入 content）——全协议通吃零逐厂
//   特判；其余类型在选择入口即拦截（中文提示），不产生 kind='video' 附件。
// 链路决策（沿用 dshinhm 实锤结论）：相机 cameraPicker.saveUri 预创建覆盖写（免相机
// 权限 + 无授权时效）/ PhotoViewPicker 免权限 / DocumentViewPicker context 构造免权限；
// picker 返回 URI 为临时授权 → 必须 fd 级拷入沙箱（copyFileExact）；图片附件入列前
// 解码缩略图（解码失败 = 图片不可用，当场拒绝——比 dshinhm「降级图标卡仍上传」更严，
// 因发送时编码同链路，入列后失败无回收通道）。
import { camera, cameraPicker } from '@kit.CameraKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { PendingAttachment } from '../../common/providers/AiTypes';
import { copyFileExact, decodeScaled } from '../../common/ImageEditUtil';
import {
  classifyByName, docMime, ensureAttachDir, extOf, imageOutMime, removeAttachFile,
  removeAttachFiles
} from '../../common/AttachmentUtil';
import { DocumentParseResult, docHardLimitBytes, docParser } from '../../common/DocumentParse';
import { OcrImageSource, OcrOutcome, ocrEnabled, runOcr } from '../../common/OcrEngine';
import { putThumb, removeThumb } from './AttachmentThumbStore';
import { hilog } from '@kit.PerformanceAnalysisKit';

// 数量上限（人为防误操作堆积——协议无上限）；单文件大小上限：图片 20MB（重采样后常态
// <1MB）、文本 30MB（★ 2026-09-23 粘贴长文本转文件笔自 1MB 放开，与文档同值：上限只决定
// 用户能不能加进来；运行时代价由 AttachmentUtil.readAttachmentText 的 12 万字符有界读
// 兜住〔读入协议与面板活算皆走它〕——故准入放宽后请求体与内存不随之放大）、文档 30MB
//（第三批②：分型硬上限 25/20/30MB 的最宽值——入列粗拦，精判在解析域 docHardLimitBytes）
export const MAX_ATTACHMENTS: number = 5;
export const MAX_IMAGE_BYTES: number = 20 * 1024 * 1024;
export const MAX_TEXT_BYTES: number = 30 * 1024 * 1024;
export const MAX_DOC_BYTES: number = 30 * 1024 * 1024;

// 附件入口三形态（半模态三格方卡：拍照 / 照片 / 系统文件）
export type FilePickKind = 'camera' | 'photo' | 'file';

// 页面状态回落回调（注入；dshinhm KimiAttachmentCtrl 同款「页面 → 控制器」单向依赖）。
// ★ isPrivate（2026-09-09 附件落盘第一轮）：选择侧目录分流——true = 隐私会话附件落
// cacheDir/attachments 临时区（退出即删、零落库）；false = 普通/加密会话落 filesDir/
// attachments 常驻区（pick 时读取——会话态在页面生命周期内不变，不得发送时才定目录）
export interface AttachmentPickRefs {
  getHostContext: () => common.UIAbilityContext | undefined;
  getAttachments: () => PendingAttachment[];
  setAttachments: (attachments: PendingAttachment[]) => void;
  isPrivate: () => boolean;
  toast: (text: string) => void;
}

// 时间戳文件名（yyyyMMdd_HHmmss，纯展示用途，本地时区；dshinhm 同款）
function timestampName(): string {
  const d: Date = new Date();
  const pad = (n: number): string => n < 10 ? '0' + n : '' + n;
  return '' + d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate()) + '_' +
    pad(d.getHours()) + pad(d.getMinutes()) + pad(d.getSeconds());
}

// 粘贴件显示名（2026-09-23 粘贴长文本转文件笔）：与「拍照_/照片_/文件_」先例同形——前缀
// 标明来源，时间戳区分同秒多件；扩展名 .txt 落在文本白名单内，故 enqueue 的类型判定天然放行
//（物理名另取 fileId，与显示名分离，照相机路先例）。导出为纯函数以便断言直跑
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

// 整段写文本文件（2026-09-23 粘贴长文本转文件笔；照 common/KnowledgePack.ets 的 writeText
// 先例：READ_WRITE|CREATE|TRUNC 覆盖写 + finally 成对 closeSync）。失败上抛给调用方处置
function writeTextFile(path: string, content: string): void {
  const f: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE |
    fs.OpenMode.TRUNC);
  try {
    fs.writeSync(f.fd, content);
  } finally {
    fs.closeSync(f);
  }
}

// picker uri 尾部文件名提取（decode 后带扩展名才可信；取不到/无扩展名兜底 fallback
//——doc 选择器返回 uri 通常含原文件名，照片/相机固定用时间戳名；dshinhm 同款）
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

// 缩略图目标边长（px）：64vp × 3x 密度 ≈ 192——官方图片解码内存优化实践；等比限最长边
//（fitLongEdge 修正版，横竖图内存同界）；总量 ≤ MAX_ATTACHMENTS 张有界
const THUMB_TARGET_PX: number = 192;

// 组合清理（缩略图仓库 release + 沙箱副本删除）：未发送附件离页（页面销毁/移除）、隐私
// 会话发送后、载荷失败降级三处调用——「未随消息发送的附件不驻留」防线在此收口
export function cleanupAttachments(atts: PendingAttachment[]): void {
  for (const att of atts) {
    removeThumb(att.fileId);
  }
  removeAttachFiles(atts);
}

// 仅释放缩略图（2026-09-09 附件落盘第一轮）：普通/加密会话**发送成功**路径——文件常驻
// filesDir 供第三轮历史气泡附件条与预览消费，只清内存态缩略图（PixelMap 有界红线）
export function releaseAttachmentThumbs(atts: PendingAttachment[]): void {
  for (const att of atts) {
    removeThumb(att.fileId);
  }
}

// 粘贴/批量上屏拦截判定（2026-09-23 粘贴长文本转文件笔；2026-09-24 扩用于输入法通路）：
// 三条件同时成立才把这段文本转成附件——开关开、文本非纯空白、长度达到阈值（含等于）。
// ★ 判定规则**只此一处**：输入栏 onPaste / onWillInsert 与两处直跑断言同引本函数，禁在组件里
// 另写一份条件（两处即漂移面）。纯函数无平台依赖。
// ★ 两条通路的文本来源不同、判据同一个：onPaste 给的是「剪贴板里要粘贴的内容」，onWillInsert
// 给的是「输入法这一次要插入的内容」——后者含输入法剪贴板粘贴与语音输入等批量上屏（普通打字
// 每次 1~2 字恒不过线）
export function shouldPasteAsFile(value: string, enabled: boolean, threshold: number): boolean {
  return enabled && value.trim() !== '' && value.length >= threshold;
}

// 输入法通路的拦截判定（2026-09-24）：被拦 = 这一段不是 onPaste 已经受理的那段（去重——真机若
// 出现 preventDefault 没拦下的情形，两条通路上屏同一段文本会各转一次），且判定函数说该转。
// ★ 与 shouldPasteAsFile 同族：阈值与开关仍只由它判，本函数只多管「是不是重复的一段」
export function shouldInterceptInsert(inserted: string, lastHandled: string, enabled: boolean,
  threshold: number): boolean {
  return inserted !== lastHandled && shouldPasteAsFile(inserted, enabled, threshold);
}

// 本次粘贴的原文是否已落进输入框（= 原生插入发生了）。判据 = 长度恰好多出本次粘贴的长度，
// 且去掉其中一处该原文后与粘贴前逐字相同（插在中间也认——不假定插在末尾）。纯函数无平台依赖
export function pasteLanded(current: string, before: string, pasted: string): boolean {
  if (pasted === '' || current.length !== before.length + pasted.length) {
    return false;
  }
  const at: number = current.indexOf(pasted);
  return at >= 0 && current.substring(0, at) + current.substring(at + pasted.length) === before;
}

// 粘贴收口（2026-09-23 粘贴长文本转文件笔）：把「附件建成了没有」与「原文落进输入框了没有」
// 两个事实对账，返回输入框应有的文本。★ 不变式 = 二者恰有其一（用户要么看到附件、要么看到
// 原文，不会重复也不会两头落空）：
//  · converted 真且 landed 真 → 撤回粘贴前快照（附件已代表它，框里不该再留一份）
//  · converted 假且 landed 假 → 向**当前**文本追加（转附件没成，内容一字不丢）
//  · 其余两种（真/假 与 落/未落 一致）= 已成立，原样返回入参（调用方据此零写入）
// ★ 补回一支取 `current` 而非 `before` 起头：转附件是异步落盘，返回时用户可能在窗口期继续打了字
// ——以 before 起头会把那几个字吞掉；以 current 起头则「新打的字 + 补回的原文」都在
// 为何要这一层：`PasteEvent.preventDefault` 是可选成员，拦不拦得住原生插入是平台行为——
// 拦住了 landed 恒假（本函数与旧行为逐字等价），拦不住才需要本函数把重复/丢失纠正回来
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

// 未发送附件按下标移除（2026-09-23 粘贴长文本转文件笔自 ChatPage 迁入——附件数组的增删本就
// 都在本件，页面只持 @State 本体；逐行原样搬迁，零语义变化）。
// 删除三件成对：缩略图 release + 沙箱副本删除（cleanupAttachments）+ 数组去掉该项——本地
// 状态独占，无网络副作用
export function removePendingAttachment(atts: PendingAttachment[],
  index: number): PendingAttachment[] {
  const removed: PendingAttachment = atts[index];
  cleanupAttachments([removed]);
  return atts.filter((_: PendingAttachment, i: number): boolean => i !== index);
}

// 草稿回写（2026-09-23 粘贴长文本转文件笔自 ChatPage.restoreVisionDraft 迁入，逐行原样搬迁、
// 零语义变化，改的是「谁持有」而非行为）：取消三路（取消键 / 遮罩 / 返回键）须把用户打的
// 这段文字还回去，否则附件留了、文字没了。回写通道由调用方注入（会话页给 applyFullInputDraft
// 的闭包——该通道是 fullInputDraft + fullInputCmd 覆盖式重写，与面板「关闭即回写胶囊」同一条
// 链）；空串不回写（零状态写）
export function restoreDraftText(writeback: (text: string) => void, text: string): void {
  if (text !== '') {
    writeback(text);
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
      const dir: string = ensureAttachDir(ctx, !this.apply.isPrivate());
      const stamp: string = timestampName();
      if (kind === 'camera') {
        // 官方 saveUri 姿势：预创建沙箱空白文件（唯一名），系统相机直接覆写——
        // resultUri === saveUri、无授权时效（不传则存媒体库临时授权）
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
        await this.enqueue('拍照_' + stamp + '.jpg', dir, null, path);
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
          await this.enqueue(name, dir, selectResult.photoUris[i], null);
        }
      } else {
        // 官方文档选择器（context 构造，免权限声明）：按扩展名分流。★ 2026-09-03 技能
        // 实测轮修复：原仅取 uris[0]——循环入列至剩余额度；★ 2026-09-14 全面自检第3轮
        // 笔 3（坑47 同族第 5 处收口）：补设 maxSelectNumber = 剩余额度——未设时系统面板
        // 默认多选（d.ts 上限 500），选超额度的件在下方循环被 i < remain 静默截断丢弃
        //（DataSyncPage/ProviderShareFlow/SkillEditPage/SkillLibraryPage 四先例同款收口）
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

  // 粘贴长文本转附件（2026-09-23 粘贴长文本转文件笔）：把粘贴进来的长文本写盘成一个 .txt
  // 附件并入列——用户看到的是附件条上多一件，而不是输入框里多一大段。
  // 返回值 = 是否已转成附件入列；false = 未入列（**toast 已由本方法发出**，调用方只需把粘贴
  // 文本回退给输入框）。契约：**永不 reject**——一切失败都转成 false + 中文 toast，调用方不写
  // try/catch（同 runOcr 契约族）。
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
      dir = ensureAttachDir(ctx, !this.apply.isPrivate()); // 目录分流随会话类型，同 pick()
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

  // 单个附件入列：类型判定（不支持即拦）→ 落位（preparedPath = 相机已落沙箱的成品路径；
  // 否则 fd 级拷贝 srcUri 到唯一名目标）→ 大小校验 → 图片解码缩略图（失败 = 不可用附件，
  // 删副本拒绝）→ 追加数组上行
  private async enqueue(displayName: string, dir: string, srcUri: string | null,
    preparedPath: string | null): Promise<void> {
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
    const stat: fs.Stat = fs.statSync(path);
    if (stat.size <= 0) {
      removeAttachFile(path);
      throw new Error('文件为空（' + displayName + '）');
    }
    const cap: number = kind === 'image' ? MAX_IMAGE_BYTES :
      (kind === 'doc' ? MAX_DOC_BYTES : MAX_TEXT_BYTES);
    if (stat.size > cap) {
      removeAttachFile(path);
      throw new Error(displayName + ' 超过 ' + (cap / 1024 / 1024) + 'MB 上限');
    }
    if (kind === 'image') {
      // 解码缩略图入模块级仓库（PixelMap 不走组件参数——@Prop 深拷贝破坏，见仓库头注释）；
      // 失败 = 图片不可解码（发送时同链路必失败）——删副本当场拒绝，不留无回收通道的附件
      let thumb: image.PixelMap | undefined = undefined;
      try {
        thumb = await decodeScaled(path, THUMB_TARGET_PX, true);
      } catch {
        thumb = undefined;
      }
      if (thumb === undefined) {
        removeAttachFile(path);
        throw new Error('图片无法解码（' + displayName + '）');
      }
      putThumb(fileId, thumb);
    }
    const next: PendingAttachment[] = this.apply.getAttachments().slice();
    const att: PendingAttachment = {
      fileId: fileId,
      name: displayName,
      mediaType: kind === 'image' ? imageOutMime(displayName) :
        (kind === 'doc' ? docMime(displayName) : 'text/plain'),
      size: stat.size,
      kind: kind,
      localPath: path
    };
    // 图片附件 OCR 预置（2026-09-15 附件 OCR 二期，§3.5 image 路）：同步先置 running 再
    // 入列——先 await 后置态会留一个「无识别文本、状态也非 running」的窗口，此刻发送会
    // 静默退回一期行为（终态兜底红线，任务书 §3.5 末条）
    if (kind === 'image' && ocrEnabled()) {
      att.ocrState = 'running';
    }
    next.push(att);
    this.apply.setAttachments(next);
    if (kind === 'doc') {
      // 文档解析排程（2026-09-03 第三批②）：入列即异步解析（分型上限精判在解析域，
      // 超限置 toolarge 态）；完成态经附件数组整体替换上行刷新——发送阻断判定
      // attachBlockingReason（解析域 docBlockingReason + OCR running，2026-09-15 二期）
      // 在页面发送前置拦
      const patch: (result: DocumentParseResult, state: string) => void =
        (result: DocumentParseResult, state: string): void => {
          this.patchAttachment(fileId, (target: PendingAttachment): void => {
            target.parseState = state;
            target.parsedText = result.text;
            target.parseError = result.error;
            target.parseTruncated = result.truncated;
            // 页图与全量页数（2026-09-15 页渲染一期；非 PDF/未渲染 = 空数组与 0）
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
          // 空文本成功态归 failed（2026-09-03 技能实测轮修复——Cube applyDocumentParseResult
          // 同语义：解析成功但 text 空（扫描件/图片型文档）≠ 可发送，防「标注在、内容缺」）。
          // ★ 2026-09-15 页渲染一期放宽（任务书 §2.3 定态规则表）：判据命中且**页图拉齐**的
          // PDF 不归 failed——页图即内容，正是本期要打通的「零文字层扫描件」；无页图（渲染
          // 失败/未命中判据）时维持旧语义（文本也空 = failed 照旧拦，docx/xlsx/ofd 零回归）
          if (result.success && result.text.trim() === '' && result.pageImages.length === 0) {
            result.success = false;
            result.error = '未提取到文本内容（可能是扫描件或图片型文档）';
          }
          // OCR 步骤（2026-09-15 附件 OCR 二期，§3.5 doc 路）：解析成功且带页图的扫描件
          // 在此续识别——done 态在「解析 + 渲染 + 识别」全完成后才由下方 patch 置位，
          // 识别期间附件保持 'parsing'（UI 零新增态），发送阻断天然覆盖
          if (ocrEnabled() && result.success && result.pageImages.length > 0) {
            const sources: OcrImageSource[] = [];
            for (const page of result.pageImages) {
              sources.push({ kind: 'base64', data: page.data });
            }
            this.patchAttachment(fileId, (target: PendingAttachment): void => {
              target.ocrState = 'running';
            });
            // 终态兜底（红线 3 同款）：runOcr 契约永不 reject，try/finally 再兜一层——
            // 异常若跳过定态 = 附件永停 'parsing' = 用户永久发不出去
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
        })
        .catch((e: Object): void => {
          const failed: DocumentParseResult = new DocumentParseResult();
          failed.error = (e as Error).message;
          patch(failed, 'failed');
        });
    } else if (kind === 'image' && ocrEnabled()) {
      // 图片附件识别（§3.5 image 路）：异步发起不阻塞入列循环——多选时逐件串行由
      // OcrEngine 内部队列保证；终态经 patchAttachment 上行（附件被删 = fileId 不在列
      // 静默丢弃，防幽灵写回）。识别失败不阻断发送（走一期行为，§2.1 行为 3）
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
        pageCount: att.pageCount, ocrText: att.ocrText, ocrState: att.ocrState
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
