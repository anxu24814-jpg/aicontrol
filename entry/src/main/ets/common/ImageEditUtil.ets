// 图像编辑工具集（2026-08-21 新增，「编辑图片」功能图像管线）：
// 解码(限尺寸) → 裁剪(applyCropSync 官方) → 模糊(drawing 库 BlurImageFilter 官方，2026-08-22
// 由 effectKit 换入——黑边根因见 applyBlur 注释) → 遮罩(像素烧录自写) → 编码(ImagePacker)。
// 全部官方 API（@kit.ImageKit + @kit.ArkGraphics2D），无 UI 纯工具；
// 调用方：components/ImageEditPage.ets（裁剪）+ ImageAdjustPage.ets（调整/保存）+ BgCache.ets +
// PageBackground.ets + BackgroundPanel.ets（沙箱文件管理/解码）。裁剪区域的像素坐标映射在页面层
// 计算后经 cropPixelMap 执行（官方 applyCropSync，API 26 推荐姿势，旧 crop/cropSync 弃用）。
// 性能约定：解码限尺寸（等比至 maxW 内）保证全流程单 PixelMap、内存可控（1080 级而非相册原图）；
// 模糊/遮罩 0% 直接跳过（返回原引用/零操作），保存时一次性执行。
import { image } from '@kit.ImageKit';
import { drawing } from '@kit.ArkGraphics2D';
import { fileIo as fs } from '@kit.CoreFileKit';
import { display } from '@kit.ArkUI';

// 背景图沙箱文件管理（2026-08-21 唯一名方案，防「相同 URI 不触发 @StorageProp 刷新」——
// 坑34：固定文件名覆盖 + file:// URI 每次都相同，第二次换图/编辑保存后已挂载页面的
// PageBackground 不刷新（@StorageProp 相同字符串不触发），重建页面/重启才正常（真机复现）。
// 方案：每次换图/编辑保存生成新文件名（时间戳），pageBg URI 必然变化必然刷新；
// 旧文件经 cleanBgFiles 扫删（保留当前），沙箱确定性有界。
// ★ 2026-08-22 三文件方案（缩放状态恢复配套）：每次保存产出**三名一基数**（同一次保存共用
// 时间戳基数，前缀互推）——显示图 page_background_<t>.jpg（pageBg 指向，烧录模糊/遮罩）/
// 干净底图 page_background_clean_<t>.jpg（未烧模糊/遮罩的裁剪结果，参数可逆）/
// 可编辑原图 page_background_src_<t>.jpg（本次编辑源原图复制，供下次「编辑当前背景」
// 解码 + 恢复缩放/裁剪——原实现保存后原图被清，「编辑当前背景」只能对已裁图操作）。
// 扫删前缀 page_background_ 天然覆盖三类；正常路径背景文件 = 3 个/背景。
// 三处共用：BackgroundPanel 拷贝目标 / ImageEditPage 解码源与保存目标 / 清旧文件。

// ═════════════ 编辑参数记忆键（2026-08-21 新增——决明反馈：调整页保存的模糊/遮罩百分比
// 未存储，保存退出再进回到 0）═════════════
// 语义：记录**最后一次保存成功**的模糊/遮罩百分比（不保存的调整视为放弃）；
// EntryAbility PersistentStorage.persistProp 注册（重启保留），ImageAdjustPage 保存成功时
// 写入、挂载时读回恢复滑轨/预览（读写姿势同 ServiceConfig 的键）
export const EDIT_BLUR_PCT_KEY: string = 'editBlurPct';
export const EDIT_MASK_PCT_KEY: string = 'editMaskPct';
// 裁剪状态记忆（2026-08-22 新增——决明反馈「重进编辑缩放丢失、模糊遮罩还在」）：
// number[] = [zoomPct(0~100), tx(vp), ty(vp)]，语义同模糊/遮罩 = 「最后一次保存成功值」；
// 保存成功时写入（镜像值），编辑页 aboutToAppear 读回并恢复裁剪视图（同设备同源图精确，
// 跨设备/换图由 clampTranslate 钳位兜底）；选图流程由编辑页判定清零（新图从 0 开始）
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

// 干净底图文件名推导（2026-08-21 双文件方案：保存时除烧录显示图外同时写未烧模糊/遮罩的
// 干净裁剪结果底图，供重新编辑时解码——模糊/遮罩参数因此可逆，调 0 = 真零模糊）：
// 与显示图一一对应（同一次保存共用 newBgFileName 生成的时间戳基数，前缀插入 clean_）。
// 入参不以 page_background_ 开头（旧持久化纯路径/异常名）或已是 clean/src 名时返回 ''（调用方跳过）
export function cleanBgFileName(bgFileName: string): string {
  if (!bgFileName.startsWith('page_background_') || bgFileName.startsWith('page_background_clean_') ||
    bgFileName.startsWith('page_background_src_')) {
    return '';
  }
  return bgFileName.replace('page_background_', 'page_background_clean_');
}

// 可编辑原图文件名推导（2026-08-22 三文件方案）：前缀插入 src_，与显示图/干净底图共享时
// 间戳基数（清洁管理：扫删保留名单/旧文件清理全部三名单向推导）。入参规则同 cleanBgFileName
export function srcBgFileName(bgFileName: string): string {
  if (!bgFileName.startsWith('page_background_') || bgFileName.startsWith('page_background_clean_') ||
    bgFileName.startsWith('page_background_src_')) {
    return '';
  }
  return bgFileName.replace('page_background_', 'page_background_src_');
}

/**
 * 编辑页解码来源路径（2026-08-22 三文件方案扩容）：**可编辑原图（src_*）存在则解码原图**
 * ——「编辑当前背景」重进时基于未裁剪原图，缩放/平移状态得以精确恢复（用户核心诉求）；
 * 无 src（旧背景/选图首次）退回干净底图（上轮保存的裁剪结果，模糊/遮罩不二次叠加——
 * 调 0 = 真零模糊）；再退显示图。名推导失败（旧纯路径/异常名，返回 ''）或文件不存在
 * 均逐级回退——'' 会拼出目录路径且 accessSync 对目录返回 true，必须判空。仅存在性判断，O(1)。
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

// 清空旧背景文件（换图/编辑保存成功后调用）：扫删指定目录内指定前缀的文件，保留 keepFileNames
// 名单内的文件（空数组 = 全部清空；2026-08-21 双文件方案改数组——编辑保存需同时保留
// 烧录显示图 + 干净底图两名）。2026-08-21 扫删自愈：原「精确删旧」在删除失败/换图后被杀
// （set 新 URI 后、删旧前）会残留孤儿且永不清理——扫删每次全清、删除失败下次自愈，沙箱
// 确定性有界。clean 底图名（page_background_clean_）以 page_background_ 开头，单前缀
// 扫描天然覆盖两类文件。前缀为本应用私有（只有背景图写 page_background_*），无误删风险；
// listFileSync + 循环 unlink 在用户换图动作时执行一次（文件数个位数），非轮询（P1-2）。
function cleanBgFilesIn(dir: string, keepFileNames: string[], prefix: string): void {
  const names: string[] = fs.listFileSync(dir);
  for (const name of names) {
    if (!name.startsWith(prefix)) {
      continue;
    }
    if (keepFileNames.indexOf(name) >= 0) {
      continue;
    }
    try {
      fs.unlinkSync(dir + '/' + name);
    } catch (e) {
      // 单文件删除失败仅日志（下次换图扫删自愈；禁止静默失败）
      console.error('remove old background file failed: ' + name + ', ' + JSON.stringify(e));
    }
  }
}

export function cleanBgFiles(filesDir: string, keepFileNames: string[]): void {
  // 常规清理：filesDir 内正确命名的背景文件（前缀 page_background_，含 clean 底图）
  cleanBgFilesIn(filesDir, keepFileNames, 'page_background_');
  // 兼容清理（坑37）：2026-08-21 新名方案初期 filesDir 拼接缺 '/'，文件写在 filesDir 同级、
  // 文件名成了 filespage_background_*（pageBg URI 曾指向它们）——扫父目录全删；
  // '..' 路径若不被 fs 解析则 listFileSync 抛异常（catch 日志，功能无碍）
  try {
    cleanBgFilesIn(filesDir + '/..', [], 'filespage_background_');
  } catch (e) {
    console.error('clean legacy background files failed: ' + JSON.stringify(e));
  }
}

// 解码：URI（file:// 或沙箱路径）或字节（ArrayBuffer,Kimi 媒体用）→ PixelMap，等比限制在 maxW 内。
// ★ 二四七改等比修正（决明「选图后预览与最终背景都拉伸,一直就有」根因）：desiredSize
// 官方语义 = 「If the output size is different from the original size, the output is
// **stretched or scaled** to the specified size」（d.ts 亲核,@ohos.multimedia.image:3283）
// ——**非等比**,原正方形 (maxW, maxW) 把所有非方图拉变形,预览/保存/壁纸全链路继承
// （原注释「官方等比缩放语义（只缩小不放大）」与 d.ts 相悖,坑52 家族新例：解码参数
// 必须查 d.ts 不信注释）。现先 getImageInfo 读原图尺寸等比算目标：宽 ≤ maxW 不传
// desiredSize（原尺寸解码,小图不再被拉大）;宽 > maxW 传精确等比 (maxW, round(h×maxW/w))
// ——「scaled」等比无变形,超大图内存可控意图不变。
// desiredPixelFormat 显式锁 RGBA_8888 保留（坑41 防御：下游 applyMask 字节级处理依赖格式确定）
// fitLongEdge 可选参（二四七改,Kimi 媒体/缩略图内存场景用）：true = 限**最长边**（产物
// 内接于 maxW² 正方形——横竖图内存同界,原「1280² 采样解码内存优化」意图的等比修正版）；
// 缺省 false = 限宽（背景链语义:产物宽 = maxW,清晰度最优假设）。
// ★ 2026-08-31 修正：本参此前仅有签名、函数体未分支（恒走限宽——与二四七改注释相悖，
// dshinhm 同源同病）；附件链引入（长截图防爆内存）真实现之。false 路径行为不变（背景链
// 既有语义零回归）；true 路径产物长边 ≤ maxW。
export async function decodeScaled(uri: string | ArrayBuffer, maxW: number,
  fitLongEdge: boolean = false): Promise<image.PixelMap> {
  let source: image.ImageSource | null = null;
  try {
    // createImageSource 多重载（string/ArrayBuffer/RawFileDescriptor）——union 实参编译器
    // 无法选重载，typeof 收窄分支直取（两分支同返回类型 ImageSource）
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

// 模糊：百分比 0~100 → 模糊半径 = round(图宽 × pct / 1000)（1080px 宽时 100% ≈ 108px，
// 视觉已很强）；官方 drawing 库 BlurImageFilter（native 实现，生成新 PixelMap）；0% 返回原引用零开销。
// ★ 2026-08-22 弃用 effectKit 换 drawing 库（黑边根因）：effectKit blur 的 tileMode 官方仅支持
// DECAL（越界采样按透明处理），模糊半径大时边缘一圈混入透明变暗、四边与中间观感不一致
// （真机黑边，决明反馈，本地 SDK d.ts + 官方文档双确认）——drawing.ImageFilter.createBlurImageFilter
// 完整支持 TileMode.CLAMP（越界用边缘颜色填充，业界标准：Photoshop / OpenCV BORDER_REPLICATE /
// Android ScriptIntrinsicBlur 同语义），边缘与中心观感统一。链路：Canvas(out) 以新 PixelMap 为
// 绘制目标 + Brush.setImageFilter + attachBrush → drawImage(pm, 0, 0) 1:1 绘制 → detachBrush，
// 输出即目标 PixelMap（无像素读回搬运）。
// sigma 标定（2026-08-22 三轮真机）：高斯视觉半径 ≈ 2σ，radius→sigma 系数 0.5 → 0.75 →
// 1.0（决明拍板；100% 时 σ=108、视觉半径 ≈216px @1080 宽），全档位同比增强；
// 如仍偏强/偏弱微调此常量即可（唯一标定点）
export async function applyBlur(pm: image.PixelMap, pct: number): Promise<image.PixelMap> {
  if (pct <= 0) {
    return pm;
  }
  const info: image.ImageInfo = pm.getImageInfoSync();
  const width: number = info.size.width;
  const height: number = info.size.height;
  const radius: number = Math.max(1, Math.round(width * pct / 1000));
  const sigma: number = radius * 1.0; // 视觉标定系数（真机三轮，见函数头注释）
  // 目标 PixelMap：editable 必须 true（Canvas 以 PixelMap 为绘制目标的要求）+ 显式锁 RGBA_8888
  // （先例坑：不同解码器输出格式不同——文件名/通道序在此与源无关，输出格式恒定可预期）
  const opts: image.InitializationOptions = {
    editable: true,
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    size: { width: width, height: height }
  };
  const out: image.PixelMap = await image.createPixelMap(new ArrayBuffer(width * height * 4), opts);
  // ★ 异常兜底释放（2026-08-22 全面检查）：绘制段（Canvas/attachBrush/drawImage）抛异常时
  // 调用方拿不到 out 引用无法释放（await 赋值未完成，调用方 out 变量保持 null）——此处
  // try/catch 内释放后 rethrow，成对释放闭环（防 Use-After-Release / 泄漏双风险）；
  // drawing Canvas/Brush/ImageFilter 官方无 release API（GC 回收），无需释放
  try {
    const canvas: drawing.Canvas = new drawing.Canvas(out);
    const brush: drawing.Brush = new drawing.Brush();
    brush.setImageFilter(drawing.ImageFilter.createBlurImageFilter(sigma, sigma, drawing.TileMode.CLAMP));
    canvas.attachBrush(brush);
    canvas.drawImage(pm, 0, 0); // 1:1 无缩放（绘制坐标 = 目标 PixelMap 坐标系）
    canvas.detachBrush();
  } catch (e) {
    out.release();
    // ArkTS 限制 throw 仅接受 Error 类型值（arkts-limited-throw）——断言转换；
    // 运行时对象不变（BusinessError 实例），调用方 catch 读 code/message 不受影响
    throw e as Error;
  }
  return out;
}

// 遮罩：像素级暗化——每像素 RGB × (1 − mask/100)，alpha 不变（每像素 4 字节；RGBA/BGRA 均兼容——
// RGB 三通道等比缩放与通道顺序无关，2026-08-21 克隆物格式跟随源后覆盖两种序）。
// 官方无现成「遮罩」API（brightness 语义不同），自写像素算法；0% 跳过零开销。
// 性能：1080×1920 ≈ 200 万像素单次遍历，仅保存时执行一次（预估 <1s）
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

// 三名名单推导（2026-08-22 三文件方案配套，P2-4：BackgroundPanel/ImageAdjustPage 三处
// 拼 keep 名单重复 3 次）：入参 = 背景文件名（display 名，可空/异常）；返回非空项数组
// [display, clean, src]（各名推导失败返回 '' 时跳过；空名返回空数组——调用方直接塞
// keep 名单即可，语义 = 该背景的三名全量保文件名）
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

// fd 级文件复制（2026-08-22 提取，P2-4：BackgroundPanel 媒体库拷贝 / ImageAdjustPage
// srcCopy 两处同款三嵌套）：openSync READ_ONLY / CREATE|READ_WRITE + copyFileSync(fd, fd) +
// 成对 closeSync；异常向上抛（调用方 catch 收敛）。
// ★ src 必须走 openSync 取 fd——媒体库 URI 直接传 fs.copy/copyFile 字符串解析不可靠，
// 真机报「路径或文件不存在」（2026-08-20 实测）；纯沙箱路径同样适用（同 fd 链路）。
// 入参为路径或媒体库 URI 字符串；dest 须为可写沙箱路径
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

// 预览框几何：比例 = 设备宽高比（随设备自适应）；框高 = 屏高 − topPad − 预留——两页统一预留
// （预留值历史：2026-08-22 由 190 调到 340（框从 ≈屏高 58% 缩到 ≈41%）——190 时预览
// 放大发虚 + 提示/按钮挤出视口（决明真机反馈）；同日稍后回调至 300：决明反馈 340 框偏小。
// 300 = 调整页内容池（提示 + 滑轨×2 ≈80 + 按钮 40 + space/间距 + 底部 padding 24 ≈214vp）
// 留约 86vp 富余，**两页框完全一致**且均不溢出。
// 2026-08-29 决明再反馈「300 框偏小，略微增大但按钮不得跑出屏幕」→ **预留 272**：
// 框高 +28vp（≈+9%），调整页内容池富余 86→58vp 仍安全（裁剪页内容池更小富余更大）；
// **上限 480vp**（防平板/大屏框过高——1280 高屏减两预留仍超 480 时钳位）；下限 200vp
// 保留；宽 = 高 × aspect；宽屏（aspect>1）反向兜底（按屏宽 −32 反推，原逻辑保留）
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
