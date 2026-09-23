// 「编辑图片」裁剪阶段二级页（2026-08-21 新增；2026-08-22 编辑对象来源改 push 参数
// EditImageParam.srcUri——BackgroundPanel 两入口：①选择图片 = 新选图沙箱临时文件
// （选图后进入编辑页，保存成功才生效）；②编辑图片 = 当前背景 pageBg URI（恢复上次参数）。
// 无参数回退 pageBg 仅作防御（旧调用姿势遗留）。编辑对象 = 沙箱文件（唯一名，文件名从
// srcUri 提取——2026-08-21 坑34 修复后不再固定）：
// 屏幕比例（display 官方 API 取设备宽高比）固定裁剪框 + 图片手势缩放平移（边界钳位防露白），
// 「下一步」把容器可见区域映射为 PixelMap 像素坐标执行官方 applyCropSync 裁剪，然后
// pushPathByName(ROUTE_IMAGE_ADJUST_PAGE) 入栈——模糊/遮罩调整与保存迁至调整阶段二级页
// components/ImageAdjustPage.ets（2026-08-21 两阶段改官方系统级转场，与其他二级页同一
// 转场机制；保存流程见该文件头注释）。本页只负责裁剪：图像管线在 common/ImageEditUtil.ets，
// 裁剪视图在 components/CropStageView.ets（CropStageView 状态自包含子组件：手势高频值为
// 子组件 @State，经回调上报父组件普通成员镜像，契约见该文件头注释）。
// 路由注册见 HomeNavigation.ets PageMap（if/else if 链）。
// 2026-08-21 闪退根因（两版真机实证 + hilog 打点定位）：GestureGroup/PanGesture/PinchGesture
// 是 DSL 全局工厂 const，仅可在 build 上下文调用——在字段初始化器/aboutToAppear 创建即访问
// 空 build 上下文，进程直接崩溃且无 faultlog 落盘；修复 = 改官方编程式手势
// （GestureModifier + GestureHandler 类，子组件内 .gestureModifier 挂载，见 CropStageView.ets）。
// ★ 2026-08-22 变色根修（推翻双图制，决明真机反馈「裁剪页变色/模糊页正常」）：根因 =
// 自写 buffer 搬运克隆（readPixelsToBuffer→createPixelMap）每执行一次 R/B 翻转一次——
// 裁剪页 orig = 克隆×1（错）、模糊页 cropped = 克隆×2（翻转两次恢复=对），奇偶次判别
// 特征实锤（d.ts 佐证：API 26 已推荐 createPixelMapFromPixels/readAllPixelsToBuffer 替代
// 该对 API 且警告 stride 对齐；官方解码产物直显一直正常 = 官方链路自洽，错在自写搬运）。
// 现彻底移除克隆：origPixelMap = BgCache 命中则**借用**（不克隆不释放，缓存归系统管；
// 换图/恢复默认仅外观页可操作，与编辑页存活互斥，借用安全），未命中则本页 decodeScaled
// 自持（aboutToDisappear 释放）。两条路径均为官方「文件→解码→直显」，无自写搬运。
// 「下一步」只算裁剪 region 随路由参数传递（PixelMap 不可随参数传递——传引用则双方
// release 互相干扰），像素级裁剪在调整页执行（自解码 + applyCropSync，见 ImageAdjustPage）。
// 往返幂等性不变：原图生命周期内永不原地修改，每次裁剪基于完整原图 + 当前手势。
// PixelMap 生命周期约定（防泄漏）：origPixelMap 仅自持时由本页 aboutToDisappear 释放
// （借用缓存不释放）；调整页 srcPixelMap 归其自管自释放，模糊预览实例归 AdjustStageView。
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import {
  display, uiMaterial
} from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import {
  IMMERSIVE_LEVEL_KEY, resolvedUiMaterial
} from '../common/ImmersiveLevel';
import { BoxSize, decodeScaled, EDIT_CROP_STATE_KEY, previewBoxMetrics, resolveEditDecodePath } from '../common/ImageEditUtil';
import { getBgPixelMap } from '../common/BgCache';
import { PageShell } from '../common/PageShell';
import { SETTING_TITLE_EDIT_IMAGE } from '../common/SettingSearch';
import { ROUTE_IMAGE_ADJUST_PAGE, ROUTE_IMAGE_EDIT_PAGE } from '../common/RouteNames';
import { AdjustPageParam } from './ImageAdjustPage';
import { CropStageView } from './CropStageView';
import { EditPlaceholder } from './EditPlaceholder';

// push 参数（ArkTS 显式接口；2026-08-22 选图流程合并引入——BackgroundPanel 构造参数对象
// 后经 pushPathByName 传入，本页 aboutToAppear 取回；参照 AdjustPageParam 先例放本导出。
// 无参数时回退 AppStorage pageBg 作防御，见 aboutToAppear）
export interface EditImageParam {
  srcUri: string;
}

@Component
export struct ImageEditPage {
  // 顶部留白（vp，HomeNavigation PageMap 传入）：HDS 路径内容区延伸到标题栏背后（渐变模糊
  // 蒙层透出内容），使首个控件静止时完整落在蒙层下方；回退路径传 0（同其它二级页）
  topPad: number = 0;
  // 路由栈（HomeNavigation PageMap 传入，与根 Navigation 同一引用）：「下一步」push 调整页、
  // 空背景/解码失败时 pop 返回（系统返回键自动 pop，零代码）
  pathStack: NavPathStack = new NavPathStack();
  // 沉浸光感整体档位（驱动 Toast/滑轨材质，同 BackgroundPanel）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;

  // ── 编辑状态 ──
  // 原图（@State——解码异步完成后赋值需触发 UI 渲染，同时驱动子组件 if 守卫：非空
  // 才创建裁剪视图，PixelMap 不可 @Prop 深拷贝）。**生命周期内永不做原地修改**
  // （往返裁剪幂等，见文件头注释）；来源 = BgCache 借用 或 本页解码自持（origOwned 区分）
  @State origPixelMap: image.PixelMap | null = null;
  // origPixelMap 是否本页自持（true = decodeScaled 产物，aboutToDisappear 释放；
  // false = 借用 BgCache 共享缓存，不释放——缓存实例被全页面背景引用）
  private origOwned: boolean = false;
  // 编辑对象 URI 镜像（aboutToAppear 取 push 参数 srcUri，无参数回退 pageBg）：解码源依据，
  // 随 push 参数传给调整页（唯一名方案 2026-08-21，见 ImageEditUtil.ets 头注释——坑34 修复）。
  // 注意：选图入口的临时文件**不**在本页 aboutToDisappear 删除——调整页保存在途链有
  // decodeScaled(srcDecodePath) 重解码分支，销毁时删文件会与在途读取竞态；残留由
  // BackgroundPanel 下次选图时的 cleanBgFiles 扫删自愈（任意时刻 ≤1 个，见该文件注释）
  private srcUri: string = '';
  // ── 恢复的上次保存缩放/平移（2026-08-22 缩放丢失修复）──
  // aboutToAppear 从 AppStorage 读回 CROP_STATE = [scale, tx, ty] 并初始化镜像，经 initial*
  // 入参传给 CropStageView（普通成员创建时赋值——恢复仅需一次）；语义同模糊/遮罩 =
  // 「最后一次保存成功值」（选图流程本页清零、新图从 0 开始，见 aboutToAppear）。
  // scale 钳位交由 CropStageView 按 scale0 执行（本页不重复钳）
  private restoredScale: number = 0;
  private restoredTx: number = 0;
  private restoredTy: number = 0;
  private disposed: boolean = false; // 页面已销毁（解码异步回调晚到时释放结果防泄漏）
  // ── 裁剪几何（vp；aboutToAppear 由屏幕尺寸初始化）──
  // 裁剪框 = 屏幕宽高比且完整落在可视区内（公共函数 previewBoxMetrics 统一，与调整页一致；
  // 定框依据与宽屏兜底见 ImageEditUtil.ets 该函数注释——2026-08-21 两页统一 190 预留、
  // 2026-08-22 调 340 + 480 上限、当日回调 300（预览框调大：原框高占比过大致预览发虚/
  // 按钮挤出视口；340 框偏小）
  private cropBoxW: number = 0; // 裁剪容器宽
  private cropBoxH: number = 0; // 裁剪容器高
  // ── 子组件上报镜像（普通成员——父不渲染这些值，仅「下一步」映射裁剪区域时读取；
  // 高频手势更新不穿越父组件重渲染，子组件内同名值为 @State 自渲染）──
  private gmImgVpW: number = 0; // 图显示宽（= cropBoxW）
  private gmImgVpH: number = 0; // 图显示高（按像素纵横比）
  private gmScale: number = 1; // 当前缩放
  private gmTx: number = 0; // 当前平移
  private gmTy: number = 0;

  // 加载编辑对象图并初始化裁剪几何（异步解码；失败 toast + 返回）。
  // 编辑对象来源（2026-08-22 流程合并）：优先取 push 参数（选择图片 = 新选图临时文件 /
  // 编辑图片 = 当前背景，两入口均携带）；无参数回退 AppStorage pageBg（防御——正常流程
  // 不再走此路径，保留拦截兜底）
  aboutToAppear(): void {
    // 诊断日志（2026-08-21 闪退排查沉淀，保留）：各阶段打点，异常时据此定位
    console.info('ImageEditPage appeared, pageBg=' + (AppStorage.get<string>('pageBg') ?? '').length);
    // 预览框几何（公共函数，与调整页一致：设备比例 + 统一预留，见 ImageEditUtil.previewBoxMetrics）
    const box: BoxSize = previewBoxMetrics(this.topPad);
    this.cropBoxH = box.h;
    this.cropBoxW = box.w;
    // getParamByName 官方签名返回 Array<unknown>，断言为本页参数接口（ArkTS 禁显式 unknown）；
    // 路由名引用 ROUTE_* 常量（禁裸字符串——改名时编译期即报，2026-08-22 审查修正）。
    // 同名页面多次入栈取最新一条（返回后再进时旧条目已随 pop 移除，兜底取末尾，
    // 先例 ImageAdjustPage.aboutToAppear）
    const params: Array<EditImageParam> =
      this.pathStack.getParamByName(ROUTE_IMAGE_EDIT_PAGE) as Array<EditImageParam>;
    const uri: string = params.length > 0 ? params[params.length - 1].srcUri :
      (AppStorage.get<string>('pageBg') ?? '');
    if (uri.length === 0) {
      this.toast('请先选择图片');
      this.pathStack.pop();
      return;
    }
    this.srcUri = uri; // 镜像：解码源文件名从它提取（清旧文件由调整页按 push 参数执行）
    // ★ 编辑参数记忆读侧判定（2026-08-22 自检重构：写清零改读侧判定——AppStorage 三键的
    // 值永远 = 当前 pageBg 背景的最后一次保存值）：编辑对象 ≠ 当前背景（= 选图流程）时
    // 恢复值直接取 0（新图从 0 开始），**不写 AppStorage**——选图后取消/保存失败退出零
    // 副作用，旧背景三键记忆不丢（517b576 语义，原「编辑页写清零」回归修复）；「编辑
    // 当前背景」（srcUri == pageBg）读保存值。保存成功由调整页写最终值覆盖（唯一显式
    // 写零点 = 恢复默认）
    const isNewPick: boolean = uri !== (AppStorage.get<string>('pageBg') ?? '');
    const cropState: number[] = isNewPick ? [0, 0, 0] :
      (AppStorage.get<number[]>(EDIT_CROP_STATE_KEY) ?? [0, 0, 0]);
    // isFinite 防御（2026-08-22 自检补）：持久化 JSON 反序列化异常值（NaN→null→?? 0 已兜，
    // 非数元素穿透 ?? 时 NaN 入链）——NaN 充入会经 restore→Region→applyCropSync 抛异常，
    // 显式判有限值归 0
    const v0: number = cropState[0] ?? 0;
    const v1: number = cropState[1] ?? 0;
    const v2: number = cropState[2] ?? 0;
    this.restoredScale = Number.isFinite(v0) ? v0 : 0;
    this.restoredTx = Number.isFinite(v1) ? v1 : 0;
    this.restoredTy = Number.isFinite(v2) ? v2 : 0;
    // 解码源（resolveEditDecodePath，2026-08-22 提取公共函数——裁剪页/调整页同源）：
    // 干净底图（page_background_clean_*，未烧模糊/遮罩的裁剪结果）存在则优先解码它——
    // 重新编辑基于干净底图，模糊/遮罩参数可逆（调 0 = 真零模糊）；不存在（新换图未编辑过）
    // 解码显示图本身（此时即干净图）。文件名拼沙箱目录（file:// URI 整体传 createImageSource
    // 不认，2026-08-21 两次 decode failed 实证；绝对沙箱路径是确定支持的形式）
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined) {
      console.error('image edit decode failed: host context unavailable');
      this.toast('图片加载失败');
      this.pathStack.pop();
      return;
    }
    const path: string = resolveEditDecodePath(context.filesDir, uri);
    // ★ 2026-08-22 变色根修：缓存命中**借用**（原实现克隆——自写 buffer 搬运 R/B 翻转，
    // 见文件头注释）。借用安全：换图/恢复默认仅外观页可操作，与本页存活互斥；不释放
    // （origOwned=false）。同步赋值秒开，无解码窗口即无闪白窗口
    const cached: image.PixelMap | null = getBgPixelMap(path);
    if (cached !== null) {
      this.origOwned = false;
      const cachedInfo: image.ImageInfo = cached.getImageInfoSync();
      console.info('ImageEditPage borrow cache: ' + path + ', pixelFormat=' + cachedInfo.pixelFormat);
      this.origPixelMap = cached; // @State 赋值触发渲染 → if 守卫创建 CropStageView
      return;
    }
    // 缓存未命中（多源路径：src 原图 / clean 底图均不命中 BgCache——单张缓存专供显示图，
    // 2026-08-22 三文件方案后「编辑当前背景」解码 src 原图路径恒不命中、每次全量解码，
    // 频率低可接受（占位框兜底）；或杀进程后首进）：
    // 本页解码自持（origOwned=true，aboutToDisappear 释放）；~300ms 解码窗口由 bgSolid
    // 纯色背景 + StageContent 深色占位框双保险兜底（无闪白，2026-08-21 修复沿用）
    console.info('ImageEditPage decode start: ' + path);
    decodeScaled(path, display.getDefaultDisplaySync().width).then((pm: image.PixelMap) => {
      if (this.disposed) {
        pm.release(); // 页面已销毁（解码慢于用户退出）：结果直接释放防泄漏
        return;
      }
      // pixelFormat 入日志（变色根因坐信佐证：3=RGBA_8888 / 4=BGRA_8888）
      const info: image.ImageInfo = pm.getImageInfoSync();
      console.info('ImageEditPage decode done, size=' + info.size.width + 'x' + info.size.height + ', pixelFormat=' + info.pixelFormat);
      this.origOwned = true;
      this.origPixelMap = pm; // @State 赋值触发渲染 → if 守卫创建 CropStageView
    }).catch((e: BusinessError) => {
      // BusinessError 的 code/message 不可枚举，JSON.stringify 只得 {}——须显式取字段
      console.error('image edit decode failed: code=' + String(e?.code) + ', message=' + e?.message);
      // 解码失败不可编辑：toast 后返回上级（与空背景分支行为一致），避免停在空加载页
      this.toast('图片加载失败');
      if (!this.disposed) {
        this.pathStack.pop();
      }
    });
  }

  // 成对释放：仅自持实例（origOwned=true 的解码产物）由本页释放；借用的 BgCache 共享
  // 缓存不释放（归缓存生命周期，被全页面背景引用——本页释放会致全局 Use-After-Release）
  aboutToDisappear(): void {
    this.disposed = true;
    if (this.origOwned && this.origPixelMap !== null) {
      this.origPixelMap.release();
    }
    this.origPixelMap = null;
  }

  // 容器可见区域 → PixelMap 像素坐标：图初始居中 + translate 平移后，容器左上角在
  // 图坐标系 = ((图显示宽×scale − 容器宽)/2 − tx, ...)/scale（vp）；像素 = vp × (图宽px/图显示宽vp)
  // 几何值用子组件上报镜像（gm*）；区域基于**原图**（gm 镜像由 CropStageView 对原图手势产生，
  // 原图生命周期内尺寸不变，区域映射稳定）
  private cropVisibleRegion(): image.Region {
    const pm: image.PixelMap | null = this.origPixelMap;
    if (pm === null) {
      throw new Error('src pixel map unavailable');
    }
    const info: image.ImageInfo = pm.getImageInfoSync();
    const ratio: number = info.size.width / (this.gmImgVpW * this.gmScale);
    const offX: number = Math.max(0, (this.gmImgVpW * this.gmScale - this.cropBoxW) / 2 - this.gmTx) * ratio;
    const offY: number = Math.max(0, (this.gmImgVpH * this.gmScale - this.cropBoxH) / 2 - this.gmTy) * ratio;
    return {
      x: offX,
      y: offY,
      size: {
        width: Math.min(info.size.width - offX, this.cropBoxW * ratio),
        height: Math.min(info.size.height - offY, this.cropBoxH * ratio)
      }
    };
  }

  // 「下一步」（同步，零像素拷贝——2026-08-22 变色根修：裁剪自本页迁至调整页，克隆链
  // 整体移除）：按当前手势镜像算裁剪 region（基于原图，尺寸不变映射稳定）→ 随路由参数
  // 传递（普通对象可随参数传递；PixelMap 不可——传引用则双方 release 互相干扰）→ push
  // 调整阶段二级页（官方系统级转场，与其他二级页同一机制）。往返幂等：原图永不原地
  // 修改，每次裁剪基于完整原图 + 当前手势；返回后手势状态保留，可直接继续编辑
  private nextStage(): void {
    if (this.origPixelMap === null) {
      return;
    }
    // 防重入：push 动画期间本页仍可点（页面覆盖在动画后才生效），连点会重复入栈——
    // 栈顶已是调整页则忽略；返回裁剪页后栈顶变回本页，可再次进入（getAllPathName @since 10）
    const names: Array<string> = this.pathStack.getAllPathName();
    if (names.length > 0 && names[names.length - 1] === ROUTE_IMAGE_ADJUST_PAGE) {
      return;
    }
    try {
      const region: image.Region = this.cropVisibleRegion();
      // param 传裁剪 region + 编辑前背景 URI + 裁剪状态（[scale, tx, ty]——保存时写入
      // CROP_STATE 记忆，重进编辑页恢复缩放/平移；调整页保存成功时写 AppStorage，
      // 见 ImageAdjustPage save 注释）+ 调整页自解码 + 裁剪 + 保存清旧文件依据，
      // 见 ImageAdjustPage 头注释）；push 收进 try——onNext 回调里 push 抛异常时在此收敛
      // （catch 有日志 + toast，不成未捕获异常）
      const param: AdjustPageParam = {
        srcUri: this.srcUri,
        region: region,
        cropState: [this.gmScale, this.gmTx, this.gmTy]
      };
      this.pathStack.pushPathByName(ROUTE_IMAGE_ADJUST_PAGE, param);
    } catch (e) {
      console.error('next stage failed: code=' + String((e as BusinessError)?.code) + ', message=' + (e as BusinessError)?.message);
      this.toast('裁剪失败');
    }
  }

  // Toast（沉浸光感：随沉浸光感总档，同 BackgroundPanel）
  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: msg,
      systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.THICK, this.immersiveLevel, false)
    });
  }

  // 裁剪阶段视图（HDS/回退双分支共用；UI 子组件在 CropStageView.ets，状态自包含 + 回调上行，
  // 见该文件头注释）。if 守卫：原图非空才创建裁剪视图（普通成员入参创建时赋值）。
  @Builder
  StageContent() {
    if (this.origPixelMap !== null) {
      CropStageView({
        topPad: this.topPad,
        srcPixelMap: this.origPixelMap,
        cropBoxW: this.cropBoxW,
        cropBoxH: this.cropBoxH,
        // 恢复的上次保存缩放/平移（2026-08-22；普通成员创建时赋值，见字段注释）
        initialScale: this.restoredScale,
        initialTx: this.restoredTx,
        initialTy: this.restoredTy,
        onGeometryChange: (imgVpW: number, imgVpH: number, scale: number, tx: number, ty: number) => {
          this.gmImgVpW = imgVpW;
          this.gmImgVpH = imgVpH;
          this.gmScale = scale;
          this.gmTx = tx;
          this.gmTy = ty;
        },
        onNext: () => {
          this.nextStage();
        }
      })
    } else {
      // ★ 解码中占位（2026-08-22 提取 EditPlaceholder，两页同款收敛）：未就绪窗口预览框
      // 区域显示深色画布（浅色模式不闪白），几何 = 裁剪框；外层布局与 CropStageView 同
      // （padding topPad + 居中）——位置对齐无跳位
      EditPlaceholder({ topPad: this.topPad, boxW: this.cropBoxW, boxH: this.cropBoxH })
    }
  }

  build() {
    // 页面骨架统一由 PageShell 提供（背景层/透明背景/标题栏/HDS 回退双分支，2026-08-21
    // 防屎山提取，见 common/PageShell.ets 头注释）；本页只提供标题与内容（裁剪阶段视图）。
    // bgSolid 例外（2026-08-21 决明要求）：裁剪预览框叠在壁纸上看不清，本页强制纯色背景，
    // 不显示自定义壁纸（与调整页一致，见 PageBackground.ets 头注释）
    PageShell({
      title: SETTING_TITLE_EDIT_IMAGE,
      bgSolid: true,
      content: () => {
        this.StageContent()
      }
    })
  }
}
