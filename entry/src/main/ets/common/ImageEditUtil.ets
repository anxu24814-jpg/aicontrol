// 图像编辑工具集（「编辑图片」功能图像管线）：解码(限尺寸) → 裁剪(applyCropSync 官方) →
// 模糊(drawing 库 BlurImageFilter 官方，黑边根因见 applyBlur 注释) → 遮罩(像素烧录自写) →
// 编码(ImagePacker)。全部官方 API，无 UI 纯工具；调用方：ImageEditPage / ImageAdjustPage /
// BgCache / PageBackground / BackgroundPanel（背景链）+ PhotoEditPage / AttachmentPickCtrl
//（待发图片链：裁剪页解码与裁剪、入列缩略图）。裁剪区域的像素坐标映射在页面层计算后经
// cropPixelMap 执行（旧 crop/cropSync 弃用）。★ 两条链共用图像管线纯函数，**不共用定框策略**
//（背景链 = 屏幕比例 previewBoxMetrics / 待发图片链 = 图片比例 photoBoxMetrics）。
// 性能约定：解码限尺寸（等比至 maxW 内）保证全流程单 PixelMap、内存可控（1080 级而非相册
// 原图）；模糊/遮罩 0% 直接跳过（返回原引用/零操作），保存时一次性执行。
import { image } from '@kit.ImageKit';
import { drawing } from '@kit.ArkGraphics2D';
import { fileIo as fs } from '@kit.CoreFileKit';
import { display } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { notifyBgChanged } from './BgRefreshBus';

// 背景图沙箱文件管理（坑34：固定文件名覆盖 + file:// URI 相同 → 已挂载页面的
// PageBackground 不刷新〔@StorageProp 相同字符串不触发〕）：每次换图/编辑保存生成新文件名
//（时间戳），URI 必然变化必然刷新；旧文件扫删保留当前，沙箱有界。
// ★ 三文件方案：每次保存产出**三名一基数**（共用时间戳，前缀互推）——显示图
// page_background_<t>.jpg（烧录模糊/遮罩）/ 干净底图 page_background_clean_<t>.jpg（未烧，
// 参数可逆，调 0 = 真零模糊）/ 可编辑原图 page_background_src_<t>.jpg（本次编辑源原图复制，
// 供下次「编辑当前背景」恢复缩放/裁剪）。扫删前缀 page_background_ 天然覆盖三类；
// 正常路径背景文件 = 3 个/背景。三处共用：BackgroundPanel 拷贝目标 / ImageEditPage 解码源
// 与保存目标 / 清旧文件。

// 编辑参数记忆键（决策反馈补）：记录**最后一次保存成功**的模糊/遮罩百分比（不保存的调整
// 视为放弃）；persistProp 注册重启保留，保存成功时写入、挂载读回恢复滑轨/预览
export const EDIT_BLUR_PCT_KEY: string = 'editBlurPct';
export const EDIT_MASK_PCT_KEY: string = 'editMaskPct';
// 裁剪状态记忆：number[] = [zoomPct(0~100), tx(vp), ty(vp)]，语义同上 =「最后一次保存成功值」；
// 编辑页 aboutToAppear 读回恢复裁剪视图（跨设备/换图由 clampTranslate 钳位兜底）；选图流程
// 由编辑页判定清零（新图从 0 开始）
export const EDIT_CROP_STATE_KEY: string = 'editCropState';

// 生成新背景文件名（时间戳毫秒 + 随机 4 位兜底——同毫秒连续换图也不会同名退化回同 URI）
export function newBgFileName(): string {
  return 'page_background_' + Date.now() + '_' + Math.floor(Math.random() * 10000) + '.jpg';
}

// 从 pageBg（file:// URI 或旧版纯路径）提取文件名：取最后一个 '/' 之后段。
// 兼容两种形态（旧持久化值可能是纯路径，见 PageBackground.ets bgSrc() 兼容注释）；
// 空/异常返回 ''（调用方据此跳过删除）
export function bgFileNameFromUri(uri: string): string {
  if (uri.length === 0) {
    return '';
  }
  return uri.substring(uri.lastIndexOf('/') + 1);
}

// 干净底图名推导（前缀插 clean_，与显示图共享时间戳基数，模糊/遮罩参数因此可逆）；入参非
// page_background_ 开头（旧纯路径/异常名）或已是 clean/src 名时返回 ''（调用方跳过）
export function cleanBgFileName(bgFileName: string): string {
  if (!bgFileName.startsWith('page_background_') || bgFileName.startsWith('page_background_clean_') ||
    bgFileName.startsWith('page_background_src_')) {
    return '';
  }
  return bgFileName.replace('page_background_', 'page_background_clean_');
}

// 可编辑原图名推导（前缀插 src_，与显示图/干净底图共享时间戳基数）。入参规则同 cleanBgFileName
export function srcBgFileName(bgFileName: string): string {
  if (!bgFileName.startsWith('page_background_') || bgFileName.startsWith('page_background_clean_') ||
    bgFileName.startsWith('page_background_src_')) {
    return '';
  }
  return bgFileName.replace('page_background_', 'page_background_src_');
}

/**
 * 编辑页解码来源路径：**可编辑原图（src_*）存在则解码原图**——「编辑当前背景」重进时基于
 * 未裁剪原图，缩放/平移状态精确恢复（用户核心诉求）；无 src（旧背景/选图首次）退干净底图
 *（上轮裁剪结果，模糊/遮罩不二次叠加——调 0 = 真零模糊）；再退显示图。名推导失败（返回
 * ''）或文件不存在均逐级回退——'' 会拼出目录路径且 accessSync 对目录返回 true，必须判空。
 */
export function resolveEditDecodePath(filesDir: string, uri: string): string {
  const baseName: string = bgFileNameFromUri(uri);
  const srcName: string = srcBgFileName(baseName);
  if (srcName.length > 0) {
    const srcPath: string = filesDir + '/' + srcName;
    if (fs.accessSync(srcPath)) {
      return srcPath;
    }
  }
  const cleanName: string = cleanBgFileName(baseName);
  if (cleanName.length > 0) {
    const cleanPath: string = filesDir + '/' + cleanName;
    if (fs.accessSync(cleanPath)) {
      return cleanPath;
    }
  }
  return filesDir + '/' + baseName;
}

// 清空旧背景文件（换图/编辑保存成功后调用）：扫删目录内指定前缀的文件、保留 keepFileNames
// 名单（空数组 = 全清；编辑保存需同时保留三名）。扫删自愈：删除失败/换图被杀残留的孤儿
// 下次扫删清理（原「精确删旧」会永久残留）。前缀为应用私有（只有背景图写 page_background_*）
// 无误删风险；listFileSync + 循环 unlink 在换图动作时执行一次（文件数个位数），非轮询。
// 返回 = **实际删除成功**的文件数（回报数须量已发生的事实——删失败/目录读不到都不得计入）
function cleanBgFilesIn(dir: string, keepFileNames: string[], prefix: string): number {
  const names: string[] = fs.listFileSync(dir);
  let removed: number = 0;
  for (const name of names) {
    if (!name.startsWith(prefix)) {
      continue;
    }
    if (keepFileNames.indexOf(name) >= 0) {
      continue;
    }
    try {
      fs.unlinkSync(dir + '/' + name);
      removed++;
    } catch (e) {
      // 单文件删除失败仅日志（下次换图扫删自愈；禁止静默失败）
      hilog.error(0xD5A0, 'ImageEditUtil', 'remove old background file failed: %{public}s, %{public}s',
        name, JSON.stringify(e));
    }
  }
  return removed;
}

export function cleanBgFiles(filesDir: string, keepFileNames: string[]): number {
  // 常规清理：filesDir 内正确命名的背景文件（前缀 page_background_，含 clean 底图）
  let removed: number = cleanBgFilesIn(filesDir, keepFileNames, 'page_background_');
  // 兼容清理（坑37）：新名方案初期 filesDir 拼接缺 '/'，文件名成了 filespage_background_* 落
  // 在 filesDir 同级（pageBg URI 曾指向它们）——扫父目录全删；'..' 路径不被解析则 listFileSync
  // 抛异常（catch 日志，功能无碍）
  try {
    removed += cleanBgFilesIn(filesDir + '/..', [], 'filespage_background_');
  } catch (e) {
    hilog.error(0xD5A0, 'ImageEditUtil', 'clean legacy background files failed: %{public}s', JSON.stringify(e));
  }
  return removed;
}

// 恢复默认背景（**唯一实现单源**，背景面板恢复默认键与快速清理页两调用点共用同一行为）：
// 四步＝①扫删全部背景文件（不清则「恢复默认→再换图」每轮 +1，违反数据有界）②清空 pageBg
//③清零编辑参数记忆三键（参数跟随当前背景图，本处为**唯一显式清零点**——「新图从 0」走读
// 侧判定不写 AppStorage）④由 pageBg 变化驱动 PageBackground 现读清空解码缓存（页面侧先置空
// 显示引用再释缓存，安全）。文件删除失败仅日志不抛（显示回官方灰底不受影响，下次换图扫删
// 自愈），故无失败返回。filesDir 传空串 = 只清指向与三键、不碰文件（调用点取不到上下文时的
// 降级）。返回 = cleanBgFiles 实际删除成功的文件数（快速清理页回报用；不另起目录预扫计数
//——预扫量的是「删前有哪些文件」，与「删掉了几个」在失败时不等价）
export function resetPageBackground(filesDir: string): number {
  const removed: number = filesDir === '' ? 0 : cleanBgFiles(filesDir, []);
  AppStorage.setOrCreate<string>('pageBg', '');
  AppStorage.setOrCreate<number>(EDIT_BLUR_PCT_KEY, 0);
  AppStorage.setOrCreate<number>(EDIT_MASK_PCT_KEY, 0);
  AppStorage.setOrCreate<number[]>(EDIT_CROP_STATE_KEY, [0, 0, 0]);
  // 直达通知：恢复默认即点名全部存活实例重读重判（pageBg 已置空，load 走清空分支同步清缓存）
  //——未来新调用方免逐点接线；import 零依赖叶子 BgRefreshBus 无环（防环论证见其头注释）
  notifyBgChanged();
  return removed;
}

// 解码：URI（file:// 或沙箱路径）或字节（ArrayBuffer）→ PixelMap，等比限制在 maxW 内。
// ★ desiredSize 官方语义 = stretched or scaled（**非等比**，d.ts 亲核——坑52 家族新例：
// 解码参数必须查 d.ts 不信注释）：先 getImageInfo 读原图尺寸等比算目标——宽 ≤ maxW 不传
// desiredSize（原尺寸解码，小图不再被拉大）；宽 > maxW 传精确等比 (maxW, round(h×maxW/w))。
// desiredPixelFormat 显式锁 RGBA_8888 保留（坑41 防御：下游 applyMask 字节级处理依赖格式
// 确定）。fitLongEdge 可选参：true = 限**最长边**（产物内接于 maxW²——Kimi 媒体/长截图防爆
// 内存场景）；缺省 false = 限宽（背景链语义，产物宽 = maxW 清晰度最优）
export async function decodeScaled(uri: string | ArrayBuffer, maxW: number,
  fitLongEdge: boolean = false): Promise<image.PixelMap> {
  let source: image.ImageSource | null = null;
  try {
    // createImageSource 多重载——union 实参编译器无法选重载，typeof 收窄分支直取
    if (typeof uri === 'string') {
      source = image.createImageSource(uri);
    } else {
      source = image.createImageSource(uri);
    }
    const info: image.ImageInfo = await source.getImageInfo();
    const opts: image.DecodingOptions = {
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    };
    if (fitLongEdge) {
      // 限最长边：长边超 maxW 才缩，等比目标内接于 maxW²（宽高各取缩放后值）；小图原样
      const longEdge: number = Math.max(info.size.width, info.size.height);
      if (longEdge > maxW && longEdge > 0) {
        const scale: number = maxW / longEdge;
        opts.desiredSize = {
          width: Math.max(1, Math.round(info.size.width * scale)),
          height: Math.max(1, Math.round(info.size.height * scale))
        };
      }
    } else if (info.size.width > maxW && info.size.width > 0) {
      const scaled: image.Size = {
        width: maxW,
        height: Math.max(1, Math.round(info.size.height * maxW / info.size.width))
      };
      opts.desiredSize = scaled;
    }
    return await source.createPixelMap(opts);
  } finally {
    // 成对释放（ImageSource 用完即 release，官方 API）
    if (source !== null) {
      source.release();
    }
  }
}

// 裁剪：PixelMap 原地裁剪（官方 applyCropSync，region 像素坐标由页面手势层映射）
export function cropPixelMap(pm: image.PixelMap, region: image.Region): void {
  pm.applyCropSync(region);
}

// 模糊：百分比 0~100 → 模糊半径 = round(图宽 × pct / 1000)（1080px 宽时 100% ≈ 108px，视觉
// 已很强）；0% 返回原引用零开销。★ 弃 effectKit 换 drawing 库（黑边根因）：effectKit blur
// 仅支持 DECAL（越界采样按透明处理），大半径边缘混入透明变暗 = 真机黑边；drawing.
// ImageFilter.createBlurImageFilter 完整支持 TileMode.CLAMP（越界用边缘色填充，业界标准），
// 边缘与中心观感统一。链路：Canvas(out) + Brush.setImageFilter + attachBrush → drawImage
// 1:1 → detachBrush，输出即目标 PixelMap。sigma 系数 1.0 为三轮真机标定（决明拍板）；如仍
// 偏强/偏弱微调此常量（唯一标定点）
export async function applyBlur(pm: image.PixelMap, pct: number): Promise<image.PixelMap> {
  if (pct <= 0) {
    return pm;
  }
  const info: image.ImageInfo = pm.getImageInfoSync();
  const width: number = info.size.width;
  const height: number = info.size.height;
  const radius: number = Math.max(1, Math.round(width * pct / 1000));
  const sigma: number = radius * 1.0; // 视觉标定系数（真机三轮，见函数头注释）
  // 目标 PixelMap：editable 必须 true（Canvas 以 PixelMap 为绘制目标的要求）+ 显式锁
  // RGBA_8888（不同解码器输出格式不同，锁格式使输出恒定可预期）
  const opts: image.InitializationOptions = {
    editable: true,
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    size: { width: width, height: height }
  };
  const out: image.PixelMap = await image.createPixelMap(new ArrayBuffer(width * height * 4), opts);
  // 异常兜底释放：绘制段抛异常时调用方拿不到 out 引用无法释放——try/catch 内释放后 rethrow
  //（成对释放闭环）；drawing Canvas/Brush/ImageFilter 官方无 release API（GC 回收）
  try {
    const canvas: drawing.Canvas = new drawing.Canvas(out);
    const brush: drawing.Brush = new drawing.Brush();
    brush.setImageFilter(drawing.ImageFilter.createBlurImageFilter(sigma, sigma, drawing.TileMode.CLAMP));
    canvas.attachBrush(brush);
    canvas.drawImage(pm, 0, 0); // 1:1 无缩放（绘制坐标 = 目标 PixelMap 坐标系）
    canvas.detachBrush();
  } catch (e) {
    out.release();
    // arkts-limited-throw：throw 仅接受 Error 类型值——断言转换；运行时对象不变（BusinessError
    // 实例），调用方 catch 读 code/message 不受影响
    throw e as Error;
  }
  return out;
}

// 遮罩：像素级暗化——每像素 RGB × (1 − mask/100)，alpha 不变（RGBA/BGRA 均兼容——RGB 三通道
// 等比缩放与通道顺序无关）。官方无现成「遮罩」API（brightness 语义不同），自写像素算法；
// 0% 跳过零开销。性能：1080×1920 ≈ 200 万像素单次遍历，仅保存时执行一次（<1s）
export async function applyMask(pm: image.PixelMap, pct: number): Promise<void> {
  if (pct <= 0) {
    return;
  }
  const info: image.ImageInfo = pm.getImageInfoSync();
  const buf: ArrayBuffer = new ArrayBuffer(info.size.width * info.size.height * 4);
  await pm.readPixelsToBuffer(buf);
  const px: Uint8Array = new Uint8Array(buf);
  const k: number = 1 - pct / 100;
  for (let i = 0; i < px.length; i += 4) {
    px[i] = Math.round(px[i] * k);
    px[i + 1] = Math.round(px[i + 1] * k);
    px[i + 2] = Math.round(px[i + 2] * k);
  }
  await pm.writeBufferToPixels(buf);
}

// 三名名单推导（P2-4：三处拼 keep 名单重复收口单源）：入参 = 背景显示名（可空/异常）；
// 返回非空项数组 [display, clean, src]——调用方直接塞 keep 名单
export function bgTripleNames(fileName: string): string[] {
  const names: string[] = [];
  if (fileName.length === 0) {
    return names;
  }
  names.push(fileName);
  const clean: string = cleanBgFileName(fileName);
  if (clean.length > 0) {
    names.push(clean);
  }
  const src: string = srcBgFileName(fileName);
  if (src.length > 0) {
    names.push(src);
  }
  return names;
}

// 保存：PixelMap → jpg（质量 90）写沙箱文件（fd 级姿势，同 BackgroundPanel 拷贝链路）。
// TRUNC 截断覆盖同名旧文件（背景图固定同名，避免堆积）
export async function saveJpg(pm: image.PixelMap, destPath: string): Promise<void> {
  const packer: image.ImagePacker = image.createImagePacker();
  try {
    const file: fs.File = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      const opts: image.PackingOption = { format: 'image/jpeg', quality: 90 };
      await packer.packToFile(pm, file.fd, opts);
    } finally {
      fs.closeSync(file);
    }
  } finally {
    // 成对释放（ImagePacker 用完即 release，官方 API）
    packer.release();
  }
}

// 屏幕几何（vp + 宽高比）：裁切框比例 = 所在设备屏幕比例（官方 display API）。
// ArkTS 禁止对象字面量类型，显式 interface（arkts-no-obj-literals-as-types）
export interface ScreenMetrics {
  widthVp: number;
  heightVp: number;
  aspect: number;
}

// fd 级文件复制（openSync + copyFileSync(fd, fd) + 成对 closeSync；异常向上抛）。★ src 必须
// 走 openSync 取 fd——媒体库 URI 直接传字符串解析不可靠，真机报「路径或文件不存在」；纯
// 沙箱路径同链路适用。dest 须为可写沙箱路径
export function copyFileExact(srcPath: string, destPath: string): void {
  const srcFile: fs.File = fs.openSync(srcPath, fs.OpenMode.READ_ONLY);
  try {
    const destFile: fs.File = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    try {
      fs.copyFileSync(srcFile.fd, destFile.fd);
    } finally {
      fs.closeSync(destFile);
    }
  } finally {
    fs.closeSync(srcFile);
  }
}

// 屏幕宽高比（宽/高，竖屏 <1）：与 px 比例一致（densityPixels 同缩放）
export function screenMetrics(): ScreenMetrics {
  const d: display.Display = display.getDefaultDisplaySync();
  const metrics: ScreenMetrics = {
    widthVp: d.width / d.densityPixels,
    heightVp: d.height / d.densityPixels,
    aspect: (d.width / d.densityPixels) / (d.height / d.densityPixels)
  };
  return metrics;
}

// 编辑图片预览框尺寸（vp；2026-08-21 自 ImageEditPage 迁入，裁剪页/调整页共用——两页框一致）
export interface BoxSize {
  w: number;
  h: number;
}

// 预览框几何：比例 = 设备宽高比（随设备自适应）；框高 = 屏高 − topPad − 预留 272（决明两轮
// 真机反馈定标——190 时放大发虚 + 按钮挤出视口，340 偏小，272 = 调整页内容池留约 58vp 富余，
// **两页框完全一致**且均不溢出）；上限 480vp（防平板/大屏框过高）、下限 200vp；宽 = 高 ×
// aspect，宽屏（aspect>1）反向兜底（按屏宽 −32 反推）
export function previewBoxMetrics(topPad: number): BoxSize {
  const m: ScreenMetrics = screenMetrics();
  let h: number = Math.min(480, Math.max(200, m.heightVp - topPad - 272));
  let w: number = h * m.aspect;
  const maxW: number = m.widthVp - 32;
  if (w > maxW) {
    w = maxW;
    h = w / m.aspect;
  }
  const box: BoxSize = { w: w, h: h };
  return box;
}

// ── 待发图片编辑（拍照/相册选图后裁剪）共用几何 ──
// 与 previewBoxMetrics 的分工：背景链框比例恒 = 屏幕比例（壁纸语义）；待发图片链框比例恒
// = **图片自身比例**（照片语义，构图不被强制），且宽高各不超过屏幕 2/3。两链共用下面的
// visibleCropRegion 与解码/裁剪/编码纯函数，不共用定框策略（判据不同，勿合并成一个函数）。
export const PHOTO_BOX_SCREEN_RATIO: number = 2 / 3;
// 框高除屏幕 2/3 外另留内容池：标题栏蒙层 topPad + 提示/滑轨/主按钮约 200vp，防平板与
// 大字号下按钮挤出视口（照背景链 272vp 预留的同族做法，取更宽松值）
export const PHOTO_BOX_CONTENT_RESERVE_VP: number = 200;
// 待发图片解码上限（限最长边，保原比例）：与发送链 IMAGE_MAX_EDGE_PX 同值（2048），编辑
// 产物发送时再编码不再被二次降采样。★ 此处独立取同值而非 import 发送链常量——AttachmentUtil
// 反向依赖本件（encodeImageBase64 用本件 decodeScaled），import 即成模块环（坑50）；代价 =
// 两处字面量，改任一侧须同步另一侧（AttachmentUtil.IMAGE_MAX_EDGE_PX）
export const PHOTO_EDIT_MAX_EDGE_PX: number = 2048;

// 裁剪几何镜像（CropStageView 上报的五个高频值 + 裁剪框尺寸；纯数据，ArkTS 显式接口）
export interface CropGeometry {
  imgVpW: number;
  imgVpH: number;
  scale: number;
  tx: number;
  ty: number;
  boxW: number;
  boxH: number;
}

// 容器可见区域 → PixelMap 像素坐标：图初始居中 + translate 平移后，容器左上角在图坐标系
// = ((图显示宽×scale − 容器宽)/2 − tx, ...)/scale（vp）；像素 = vp × (图宽px/图显示宽vp)。
// 背景链与待发图片链共用同一份映射（原为 ImageEditPage.cropVisibleRegion 私有方法，两次
// 消费时按「重复 2 次以上提取为子程序」下迁本件，方法体逐字未改）。
export function visibleCropRegion(pm: image.PixelMap, g: CropGeometry): image.Region {
  const info: image.ImageInfo = pm.getImageInfoSync();
  const ratio: number = info.size.width / (g.imgVpW * g.scale);
  const offX: number = Math.max(0, (g.imgVpW * g.scale - g.boxW) / 2 - g.tx) * ratio;
  const offY: number = Math.max(0, (g.imgVpH * g.scale - g.boxH) / 2 - g.ty) * ratio;
  return {
    x: offX,
    y: offY,
    size: {
      width: Math.min(info.size.width - offX, g.boxW * ratio),
      height: Math.min(info.size.height - offY, g.boxH * ratio)
    }
  };
}

// 待发图片预览框：比例 = 图片宽高比；宽 ≤ 屏宽 2/3、高 ≤ 屏高 2/3 且为内容池让位后仍
// 放得下。按 maxW 起算再以 maxH 反推，保证两上限同时成立且比例不变。
export function photoBoxMetrics(topPad: number, imgW: number, imgH: number): BoxSize {
  const m: ScreenMetrics = screenMetrics();
  const maxW: number = m.widthVp * PHOTO_BOX_SCREEN_RATIO;
  const maxH: number = Math.min(m.heightVp * PHOTO_BOX_SCREEN_RATIO,
    Math.max(120, m.heightVp - topPad - PHOTO_BOX_CONTENT_RESERVE_VP));
  const aspect: number = imgH > 0 && imgW > 0 ? imgW / imgH : 1;
  let w: number = maxW;
  let h: number = maxW / aspect;
  if (h > maxH) {
    h = maxH;
    w = h * aspect;
  }
  const box: BoxSize = { w: Math.max(1, w), h: Math.max(1, h) };
  return box;
}
