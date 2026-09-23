// 「编辑图片」调整阶段二级页（2026-08-21 自 ImageEditPage 拆出，两阶段编辑改官方系统级转场）：
// 裁剪页（ImageEditPage）点「下一步」经 pushPathByName 入栈（系统级右侧滑入，与其他二级页
// 同一转场机制），本页负责模糊/遮罩调整 + 保存；「上一步」/标题栏返回键/系统返回键/侧滑
// 一律 pop 回裁剪页（系统级滑出），保存成功后 popToName(ROUTE_APPEARANCE_PAGE) 一次弹两级退出编辑。
// 标题与裁剪页一致（引用 SETTING_TITLE_EDIT_IMAGE 常量，两级标题栏均为官方规格，
// 见 common/PageShell.ets）。
// 参数契约（push 时经 param 传入，本页 aboutToAppear 用 getParamByName 取）：
// - srcUri：编辑对象 URI（2026-08-22 起两种来源——选择图片 = 新选图沙箱临时文件 /
//   编辑图片 = 当前背景 URI；解码源推导 + 保存后清旧文件的依据均以它为准）；
// - region：裁剪区域（原图像素坐标）——2026-08-22 变色根修：裁剪自裁剪页迁至本页，
//   PixelMap 不再随参数传递（传引用双方 release 互相干扰；且克隆搬运 R/B 翻转——根因见
//   ImageEditPage 头注释）。本页按 srcUri 自解码（官方「文件→解码」，resolveEditDecodePath
//   与裁剪页同源：可编辑原图 src_* 优先）+ applyCropSync 裁剪得基准图 srcPixelMap——
//   **归本页自持**，aboutToDisappear 释放；其模糊预览实例归 AdjustStageView 自管
//   （见 AdjustStageView 头注释）；
// - cropState：裁剪状态 [scale, tx, ty]（2026-08-22 缩放状态修复）——保存成功时写入
//   CROP_STATE 记忆，重进编辑页恢复缩放/平移（语义同模糊/遮罩 = 最后一次保存成功值）。
// 保存流程（2026-08-21 双文件方案，修复「模糊调 0 仍模糊」——原实现只写烧录图，重进编辑
// 解码的基准图已带模糊，参数不可逆；2026-08-22 扩为**三文件**：加可编辑原图
// page_background_src_* = 未裁剪的编辑源副本，供下次「编辑当前背景」恢复缩放/裁剪——
// 缩放状态丢失根因）。按镜像百分比重算模糊 → 遮罩烧录 → **三写**唯一名沙箱 jpg
// （src 原图 + clean 干净底图 + 烧录显示图 = pageBg 指向）→ 清旧文件（保留新三名）→
// 退出编辑；失败 toast 停留当前页（详情见 save()）。
// 路由注册见 HomeNavigation.ets PageMap（if/else if 链尾，两处同步）。
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { display, uiMaterial } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { fileUri } from '@kit.CoreFileKit';
import {
  IMMERSIVE_LEVEL_KEY, resolvedUiMaterial
} from '../common/ImmersiveLevel';
import { ensureBgPixelMap } from '../common/BgCache';
import { applyBlur, applyMask, bgFileNameFromUri, bgTripleNames, BoxSize, cleanBgFileName, cleanBgFiles, copyFileExact, cropPixelMap, decodeScaled, EDIT_BLUR_PCT_KEY, EDIT_CROP_STATE_KEY, EDIT_MASK_PCT_KEY, newBgFileName, previewBoxMetrics, resolveEditDecodePath, saveJpg, srcBgFileName } from '../common/ImageEditUtil';
import { PageShell } from '../common/PageShell';
import { SETTING_TITLE_EDIT_IMAGE } from '../common/SettingSearch';
import { ROUTE_APPEARANCE_PAGE, ROUTE_IMAGE_ADJUST_PAGE } from '../common/RouteNames';
import { AdjustStageView } from './AdjustStageView';
import { EditPlaceholder } from './EditPlaceholder';

// 延迟释放槽（2026-08-22 防 Use-After-Release）：基准图归本页自持后，aboutToDisappear
// 立即释放有 UAR 窗口——销毁时 save() 的 await 链（编码/模糊/遮罩）或 AdjustStageView 的
// 模糊预览可能正在 native 层读基准图（真异步任务，disposed 标志只防回调不防进行中的读取）。
// 故销毁时不立即释放，移入本槽延迟到下次进入本页时释放（同 BgCache prevPm 延迟释放模式，
// 彼时异步链路早已完成，安全窗口充足）。有界：槽内至多 1 张（栈顶守卫保证本页不重复入栈，
// 返回后再进时 aboutToAppear 先清槽）；进程退出由 OS 回收
let pendingRelease: image.PixelMap | null = null;
// 保存在途标志（2026-08-22 审查补竞态守卫）：旧页销毁时其 save() 的 await 链可能仍在
// native 层读基准图（disposed 只在 await 点后拦截、拦不住进行中的那一次读取）；在途期间
// aboutToAppear 不得清槽（否则 UAR），由 save() 的 finally 收尾兜底释放
let saveInFlight: boolean = false;

// push 参数（ArkTS 显式接口；2026-08-22 起不再传 PixelMap——region 传递 + 本页自解码，
// 见文件头注释）。裁剪页（ImageEditPage）构造参数对象后经 pushPathByName 传入，本页
// aboutToAppear 取回。cropState（2026-08-22 缩放状态修复）= [scale, tx, ty] 保存时写入
// CROP_STATE 记忆（重进编辑页恢复缩放/平移，语义同模糊/遮罩 = 最后一次保存成功值）
export interface AdjustPageParam {
  srcUri: string;
  region: image.Region;
  cropState: number[];
}

@Component
export struct ImageAdjustPage {
  // 顶部留白（vp，HomeNavigation PageMap 传入，同其他二级页）：HDS 路径内容区延伸到标题栏背后，
  // 使预览区完整落在标题栏下沿之下
  topPad: number = 0;
  // 路由栈（HomeNavigation PageMap 传入，与根 Navigation 同一引用）：pop 回裁剪页 /
  // popToName 退出编辑
  pathStack: NavPathStack = new NavPathStack();
  // 沉浸光感整体档位（驱动 Toast/滑轨材质，同 ImageEditPage）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;

  // ── 编辑状态 ──
  // 裁剪结果基准图（**本页自持**：aboutToAppear 按 srcUri 自解码 + 按 region 裁剪的产物——
  // 2026-08-22 变色根修后不再从参数接收 PixelMap；aboutToDisappear 释放）。@State：解码
  // 异步完成后赋值触发渲染，同时驱动 if 守卫（非空才创建 AdjustStageView——PixelMap 不可
  // @Prop 深拷贝，同 ImageEditPage 模式）
  @State srcPixelMap: image.PixelMap | null = null;
  // 编辑对象 URI 镜像（清旧文件依据——保存前 AppStorage['pageBg'] 仍指向旧背景/空；
  // 选图入口的 srcUri = 临时文件，保存后由下方 cleanBgFiles 按保留名单外清掉）
  private srcUri: string = '';
  // 裁剪区域（push 参数传入，原图像素坐标）：aboutToAppear 解码后据此 applyCropSync；
  // save()「模糊 0% 且遮罩 >0%」分支重解码备用实例时复用（见 save 注释）
  private cropRegion: image.Region = { x: 0, y: 0, size: { width: 0, height: 0 } };
  // 解码源沙箱路径（resolveEditDecodePath 推导：可编辑原图 src_* 优先——2026-08-22 三文件
  // 方案；aboutToAppear 与 save() 重解码分支共用）
  private srcDecodePath: string = '';
  // 裁剪状态镜像（2026-08-22 缩放状态修复）：push 参数传来 [scale, tx, ty]，保存成功时
  // 写入 CROP_STATE 记忆（重进编辑页恢复缩放/平移——语义同模糊/遮罩 = 最后一次保存成功值）
  private cropState: number[] = [0, 0, 0];
  private saving: boolean = false; // 防重复保存
  private disposed: boolean = false; // 页面已销毁（解码/保存异步回调晚到时释放结果防泄漏）
  // ── 预览框几何（vp；公共函数，与裁剪页完全一致——设备比例 + 统一预留，见
  // ImageEditUtil.previewBoxMetrics 注释；AdjustStageView 预览区按此固定尺寸显示）──
  private boxW: number = 0; // 预览框宽
  private boxH: number = 0; // 预览框高
  // ── 子组件上报镜像（普通成员——父不渲染这些值，仅「保存」时读取；同 ImageEditPage）──
  private mirrorBlurPct: number = 0; // 模糊百分比（保存时重算最终图）
  private mirrorMaskPct: number = 0; // 遮罩百分比
  // ── 恢复的上次保存值（2026-08-21 参数记忆）──
  // aboutToAppear 从 AppStorage 读回（钳位 0~100 兜底异常值）并初始化 mirror 镜像
  // （子组件 aboutToAppear 上报前的双保险），经 initial* 入参传给 AdjustStageView 恢复
  // 滑轨与预览；语义 = 最后一次保存成功的值（键与持久化见 ImageEditUtil.ets）
  private restoredBlurPct: number = 0;
  private restoredMaskPct: number = 0;

  // 取 push 参数（srcUri + region）：pushPathByName 时已入栈，aboutToAppear 可直接取；
  // 同名页面多次入栈取最新一条（返回后再进时旧条目已随 pop 移除，兜底取末尾）。
  // 基准图自解码（2026-08-22 变色根修，见文件头注释）：decodeScaled 的 maxW 必须与裁剪页
  // 一致（同取屏宽 px）——region 是原图像素坐标，两页解码产物尺寸一致映射才有效（隐含
  // 契约，勿只改其一；BgCache 缓存同宽，裁剪页借用路径亦一致）
  aboutToAppear(): void {
    // 清延迟释放槽（上一次编辑销毁时移入的基准图——此时其异步链路早已完成，释放安全；
    // 见模块级 pendingRelease 注释）。在途保存例外：save() 的 native 读取未收尾时跳过，
    // 由 save() 的 finally 兜底释放（防 UAR 竞态，2026-08-22 审查补）
    if (pendingRelease !== null && !saveInFlight) {
      pendingRelease.release();
      pendingRelease = null;
    }
    // getParamByName 官方签名返回 Array<unknown>，断言为本页参数接口（ArkTS 禁显式 unknown）；
    // 路由名引用 ROUTE_* 常量（禁裸字符串——改名时编译期即报，2026-08-22 审查修正）
    const params: Array<AdjustPageParam> =
      this.pathStack.getParamByName(ROUTE_IMAGE_ADJUST_PAGE) as Array<AdjustPageParam>;
    if (params.length === 0) {
      console.error('image adjust param missing');
      this.toast('图片数据缺失');
      this.pathStack.pop();
      return;
    }
    const param: AdjustPageParam = params[params.length - 1];
    this.srcUri = param.srcUri;
    this.cropRegion = param.region;
    // 裁剪状态镜像（2026-08-22 缩放状态修复）：保存成功时写入 CROP_STATE 记忆；
    // 清零已上移到 ImageEditPage.aboutToAppear（选图流程三键清零、裁剪页创建前生效——
    // 本页原清零块删除，单一来源防两处判定漂移）
    this.cropState = param.cropState;
    // 预览框几何（与裁剪页同源同尺寸，见字段注释）
    const box: BoxSize = previewBoxMetrics(this.topPad);
    this.boxW = box.w;
    this.boxH = box.h;
    // 恢复上次保存的模糊/遮罩百分比（2026-08-21 参数记忆）：钳位 0~100 兜底异常持久化值；
    // 同时初始化 mirror 镜像（子组件 aboutToAppear 上报前的双保险——用户不重新调整直接
    // 「保存」也按恢复值重算，最终图与上次一致）。
    // ★ 读侧判定（2026-08-22 自检重构：写清零改读侧判定，同 ImageEditPage 语义——AppStorage
    // 值永远 = 当前背景最后一次保存值）：选图流程（srcUri ≠ pageBg）恢复值直接 0（新图从
    // 0 开始、不写 AppStorage——取消/保存失败零副作用）
    const isNewPick: boolean = this.srcUri !== (AppStorage.get<string>('pageBg') ?? '');
    const blur: number | undefined = AppStorage.get<number>(EDIT_BLUR_PCT_KEY);
    const mask: number | undefined = AppStorage.get<number>(EDIT_MASK_PCT_KEY);
    this.restoredBlurPct = isNewPick ? 0 : Math.min(100, Math.max(0, blur ?? 0));
    this.restoredMaskPct = isNewPick ? 0 : Math.min(100, Math.max(0, mask ?? 0));
    this.mirrorBlurPct = this.restoredBlurPct;
    this.mirrorMaskPct = this.restoredMaskPct;
    // 自解码 + 裁剪（官方「文件→解码→applyCropSync」，无自写 buffer 搬运——变色根修）
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined) {
      console.error('image adjust decode failed: host context unavailable');
      this.toast('图片加载失败');
      this.pathStack.pop();
      return;
    }
    this.srcDecodePath = resolveEditDecodePath(context.filesDir, this.srcUri);
    decodeScaled(this.srcDecodePath, display.getDefaultDisplaySync().width).then((pm: image.PixelMap) => {
      if (this.disposed) {
        pm.release(); // 页面已销毁（解码慢于用户退出）：结果直接释放防泄漏
        return;
      }
      try {
        cropPixelMap(pm, this.cropRegion); // 官方 applyCropSync 原地裁剪
      } catch (e) {
        pm.release(); // 裁剪失败：解码产物本页尚未接管，直接释放防泄漏
        console.error('image adjust crop failed: code=' + String((e as BusinessError)?.code) + ', message=' + (e as BusinessError)?.message);
        this.toast('裁剪失败');
        if (!this.disposed) {
          this.pathStack.pop();
        }
        return;
      }
      const info: image.ImageInfo = pm.getImageInfoSync();
      console.info('ImageAdjustPage decode+crop done, size=' + info.size.width + 'x' + info.size.height + ', pixelFormat=' + info.pixelFormat);
      this.srcPixelMap = pm; // @State 赋值触发渲染 → if 守卫创建 AdjustStageView
    }).catch((e: BusinessError) => {
      // BusinessError 的 code/message 不可枚举，JSON.stringify 只得 {}——须显式取字段
      console.error('image adjust decode failed: code=' + String(e?.code) + ', message=' + e?.message);
      this.toast('图片加载失败');
      if (!this.disposed) {
        this.pathStack.pop();
      }
    });
  }

  // 成对释放：基准图 srcPixelMap 归本页自持（2026-08-22 起为自解码产物）——但销毁时**不
  // 立即释放**，移入延迟释放槽（防 Use-After-Release：save() await 链 / AdjustStageView
  // 模糊预览可能正在 native 层读它，见模块级 pendingRelease 注释）；模糊预览实例归
  // AdjustStageView 自管（其 aboutToDisappear 判等跳过基准图）
  aboutToDisappear(): void {
    this.disposed = true;
    if (this.srcPixelMap !== null) {
      // 2026-08-22 审查补守卫：槽内旧图与保存在途（saveInFlight）不对称释放会 Use-After-
      // Release（旧页 save 链可能正在 native 读它）——在途时不释放、新图直接覆盖入槽
      // （旧图让位泄漏 1 张，无 UAR 风险；窗口极小、有界，下轮 aboutToAppear 清槽时释放）；
      // 非在途则先清防泄漏（原防御逻辑）
      if (pendingRelease !== null && !saveInFlight) {
        pendingRelease.release();
      }
      pendingRelease = this.srcPixelMap;
      this.srcPixelMap = null;
    }
  }

  // 「保存」：最终图 = 按镜像百分比重算模糊（预览节流可能滞后最后一次）→ 遮罩烧录 →
  // **三写**沙箱 jpg（可编辑原图 src + 干净底图 + 烧录显示图，三文件方案见文件头注释）→
  // 刷新 pageBg → 退出编辑（popToName 一次弹两级：本页 + 裁剪页）。
  // 输出实例来源（2026-08-22 变色根修，克隆链整体移除——克隆搬运 R/B 翻转根因见
  // ImageEditPage 头注释）：
  // - 模糊 >0%：drawing 库 BlurImageFilter 官方生成新实例（≠基准图）；
  // - 模糊 0% 且遮罩 >0%：**重新解码 + 裁剪**独立实例（~300ms 仅此组合——基准图只读，
  //   遮罩烧录在副本上执行，保存失败重试不二次叠加）；
  // - 全 0%：无输出实例，最终图 = 基准图本身（applyMask 0% 跳过，零修改零拷贝）。
  // 基准图（srcPixelMap/base）全程只读、不在此释放——归本页 aboutToDisappear；输出实例
  // 在 finally 统一释放（成功/失败/disposed 提前返回都不泄漏）。
  // 保存中用户退出（disposed）：不再弹栈（避免误弹上级页），已写新文件无人引用由
  // cleanOrphanFiles 扫删清掉（防孤儿残留）
  private async save(): Promise<void> {
    if (this.saving || this.srcPixelMap === null) {
      return;
    }
    this.saving = true;
    saveInFlight = true; // 在途标志：拦截 aboutToAppear 清槽（见模块级注释）
    // 基准图局部常量：判空收窄对 this 成员在 await 后不保持，后续链路统一用 base
    //（归本页生命周期，finally 判等跳过不释放）
    const base: image.PixelMap = this.srcPixelMap;
    // 诊断日志（2026-08-21 保存未生效排查，保留）：确认保存时读到的镜像百分比
    console.info('image adjust save: blur=' + this.mirrorBlurPct + ', mask=' + this.mirrorMaskPct);
    let out: image.PixelMap | null = null; // 本次生成的输出实例（blur 输出 / 重解码副本）
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (context === undefined) {
        throw new Error('host context unavailable');
      }
      // 唯一名保存（坑34 修复，同 BackgroundPanel）：新文件名 → 保存 → set 新 URI →
      // 删旧文件（编辑对象：旧背景显示图或选图临时文件；先 set 后删，旧文件无引用后再删）。
      // ★ 三文件（2026-08-22 缩放状态修复，见文件头注释）：三名共用同一时间戳基数
      // （cleanBgFileName/srcBgFileName 推导）——先复制可编辑原图（src）、再写干净底图
      // （基准图只读不修改）、最后写烧录显示图；任一失败走 catch，已写文件由下次扫删自愈
      const destName: string = newBgFileName();
      const cleanName: string = cleanBgFileName(destName);
      const srcName: string = srcBgFileName(destName);
      const destPath: string = context.filesDir + '/' + destName;
      // ★ 可编辑原图复制（2026-08-22 三文件方案）：本次编辑源（srcDecodePath——选图 =
      // 临时文件 / 编辑当前背景 = 上次的 src 原图）复制为新 src 名——下次「编辑当前背景」
      // 基于该副本解码，缩放/平移状态得以精确恢复（用户核心诉求）；公共函数
      // copyFileExact（fd 级，同 BackgroundPanel 拷贝链路）
      copyFileExact(this.srcDecodePath, context.filesDir + '/' + srcName);
      await saveJpg(base, context.filesDir + '/' + cleanName);
      if (this.disposed) {
        this.cleanOrphanFiles(context.filesDir);
        return;
      }
      if (this.mirrorBlurPct > 0) {
        out = await applyBlur(base, this.mirrorBlurPct); // 官方 drawing BlurImageFilter 新实例（≠基准图）
      } else if (this.mirrorMaskPct > 0) {
        // 模糊 0% 且遮罩 >0%：重新解码 + 裁剪得独立实例（不克隆）；decodeScaled 的 maxW 与
        // aboutToAppear 一致（同屏宽 px，region 映射才有效——隐含契约）
        out = await decodeScaled(this.srcDecodePath, display.getDefaultDisplaySync().width);
        cropPixelMap(out, this.cropRegion);
      }
      // 全 0%：out 保持 null，最终图 = 基准图（零修改零拷贝）
      if (this.disposed) {
        this.cleanOrphanFiles(context.filesDir);
        return; // 输出实例由 finally 统一释放；显示图尚未写入
      }
      const final: image.PixelMap = out !== null ? out : base;
      await applyMask(final, this.mirrorMaskPct); // 0% 跳过零开销
      if (this.disposed) {
        this.cleanOrphanFiles(context.filesDir);
        return;
      }
      await saveJpg(final, destPath);
      if (this.disposed) {
        // 已退出：不再弹栈（避免误弹上级页）；刚写入的新文件无人引用（pageBg 未更新指向
        // 它），扫删保留编辑前背景（srcUri 对应显示图 + 其干净底图），清掉新文件
        this.cleanOrphanFiles(context.filesDir);
        return;
      }
      const newUri: string = fileUri.getUriFromPath(destPath);
      // ★ 预热缓存（2026-08-22 选图流程合并配套）：保存的显示图未在 BgCache 中（选图入口
      // 不再预热——选择时并不写 pageBg；编辑当前背景入口保存后同样是新文件未命中），不预热则
      // popToName 回外观页时 PageBackground 先显示旧图、解码完成才切新图（可见跳变窗口）；
      // 预热后 @StorageProp 触发时同步命中零延迟（先例 BackgroundPanel 选图路径，
      // ensure 失败仅日志返回 null，不影响保存）
      await ensureBgPixelMap(destPath);
      if (this.disposed) {
        this.cleanOrphanFiles(context.filesDir);
        return;
      }
      AppStorage.setOrCreate<string>('pageBg', newUri);
      // 清旧文件（扫删保留新三名：显示图 + 干净底图 + 可编辑原图——编辑前背景/临时文件/
      // 历史孤儿一次清光，沙箱有界；bgTripleNames 公共推导）
      cleanBgFiles(context.filesDir, bgTripleNames(destName));
      // 记录参数记忆（2026-08-21 决明反馈：保存后重新进入编辑页要能回到上次的模糊/遮罩
      // 百分比——语义 = 最后一次保存成功值；PersistentStorage 已注册，重启保留）
      AppStorage.setOrCreate<number>(EDIT_BLUR_PCT_KEY, this.mirrorBlurPct);
      AppStorage.setOrCreate<number>(EDIT_MASK_PCT_KEY, this.mirrorMaskPct);
      // 裁剪状态记忆（2026-08-22 缩放状态修复）：保存成功时写入本次裁剪状态
      // [scale, tx, ty]（来自裁剪页上报镜像，经 push 参数传来）；重进编辑页恢复缩放/平移
      AppStorage.setOrCreate<number[]>(EDIT_CROP_STATE_KEY, this.cropState);
      this.toast('已保存');
      // 退出编辑：一次弹两级（本页 + 裁剪页）回「外观显示」，官方系统级转场
      this.pathStack.popToName(ROUTE_APPEARANCE_PAGE);
    } catch (e) {
      console.error('image adjust save failed: code=' + String((e as BusinessError)?.code) + ', message=' + (e as BusinessError)?.message);
      this.toast('保存失败');
    } finally {
      // 统一释放本次生成的输出实例（blur 输出 / 重解码副本——均 ≠ 基准图；基准图归本页
      // aboutToDisappear 释放，判等双保险跳过）。成功/失败/提前 return 各路径都经此收敛
      if (out !== null && out !== base) {
        out.release();
      }
      this.saving = false;
      saveInFlight = false;
      // 注：不清 pendingRelease 槽——槽内基准图可能还被旧页 AdjustStageView 的在途模糊预览
      // 读取；留待下次进入本页 aboutToAppear 释放（有界：至多 1 张，寿命延长一次会话）
    }
  }

  // 保存中退出（disposed）的孤儿清理：扫删保留**当前背景**（AppStorage pageBg 指向的显示图
  // + 其干净底图 + 其可编辑原图——2026-08-22 审查修正：原按 srcUri 推导，选图流程 srcUri =
  // 临时文件、pageBg 背景不入名单会被误删致背景丢失；改取 pageBg 推导（三名规则同
  // cleanBgFiles 保留名单）后两流程统一——编辑当前流程 srcUri == pageBg，行为等价），
  // 本次新写文件（无 pageBg 引用）被清掉——防孤儿残留（save 内多个 disposed 分支共用）
  private cleanOrphanFiles(filesDir: string): void {
    cleanBgFiles(filesDir, bgTripleNames(bgFileNameFromUri(AppStorage.get<string>('pageBg') ?? '')));
  }

  // Toast（沉浸光感：随沉浸光感总档，同 ImageEditPage）
  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: msg,
      systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.THICK, this.immersiveLevel, false)
    });
  }

  // 调整阶段内容：if 守卫 PixelMap 非空才创建 AdjustStageView（普通成员入参创建时赋值）
  @Builder
  AdjustContent() {
    if (this.srcPixelMap !== null) {
      AdjustStageView({
        topPad: this.topPad,
        srcPixelMap: this.srcPixelMap,
        boxW: this.boxW,
        boxH: this.boxH,
        // 恢复的上次保存值（2026-08-21 参数记忆；普通成员创建时赋值，见字段注释）
        initialBlurPct: this.restoredBlurPct,
        initialMaskPct: this.restoredMaskPct,
        onBlurChange: (v: number) => {
          this.mirrorBlurPct = v;
        },
        onMaskChange: (v: number) => {
          this.mirrorMaskPct = v;
        },
        // 「上一步」= pop 回裁剪页（系统级滑出；标题栏返回键/系统返回键/侧滑同此）
        onBack: () => {
          this.pathStack.pop();
        },
        onSave: () => {
          this.save();
        }
      })
    } else {
      // ★ 解码/裁剪中占位（2026-08-22 提取 EditPlaceholder）：未就绪窗口预览框区域显示
      // 深色画布（浅色模式不闪白），几何 = 预览框；外层布局与 AdjustStageView 预览区对齐
      EditPlaceholder({ topPad: this.topPad, boxW: this.boxW, boxH: this.boxH })
    }
  }

  build() {
    // bgSolid 例外（2026-08-21 决明要求）：模糊预览框叠在壁纸上看不清，本页强制纯色背景，
    // 不显示自定义壁纸（与裁剪页一致，见 PageBackground.ets 头注释）
    PageShell({
      title: SETTING_TITLE_EDIT_IMAGE,
      bgSolid: true,
      content: () => {
        this.AdjustContent()
      }
    })
  }
}
