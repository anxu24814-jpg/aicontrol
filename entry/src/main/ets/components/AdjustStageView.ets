// 「编辑图片」调整阶段视图（2026-08-21 自 ImageEditUi.ets 拆出——该文件 411 行超 400
// 行红线，按「阶段视图」模式拆：CropStageView.ets / AdjustStageView.ets）。
// 调整滑轨用公共 SliderRow（2026-08-22 提取至 ./SliderRow.ets——裁剪页缩放滑轨同构共用）。
// 纯展示 + 事件回调上行，零业务逻辑——图像处理与保存流程留在
// ImageAdjustPage。状态自包含约定（同 CropStageView.ets 头注释）：
// - 滑轨驱动的高频值（blurPct/maskPct）与预览位图（displayPixelMap）为本组件 @State；
// - 变化中的百分比经 onBlurChange/onMaskChange 实时上报父组件普通成员镜像（父「保存」时
//   按镜像重算最终图）；
// - PixelMap 为 native 对象不可 @Prop 深拷贝：父组件用 if 守卫保证非空才创建子组件。
// 拆分规则：页面再超 400 行继续按「阶段视图」模式拆（头注释写契约）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { IMMERSIVE_LEVEL_KEY, CONTENT_FALLBACK_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect } from '../common/ImmersiveLevel';
import { applyBlur } from '../common/ImageEditUtil';
import { SliderRow } from './SliderRow';

// 阶段二：调整视图（预览 + 模糊/遮罩滑轨 + 上一步/保存）。
// 滑轨百分比与模糊预览管线均为本组件自包含：百分比经 onBlurChange/onMaskChange 实时上报
// 父镜像（父「保存」时按镜像重算最终图）；PixelMap 生命周期：模糊新实例替换时释放旧实例，
// aboutToDisappear 释放当前预览（基准图 srcPixelMap 归父组件统一释放，此处判等跳过）。
// 初始值恢复（2026-08-21 编辑参数记忆）：父组件传入 initialBlurPct/initialMaskPct（= 上次
// 保存成功值），aboutToAppear 据此初始化滑轨 @State + 上报父镜像（保存按恢复值重算）+ 预览
// 立即刷新一次——重进调整页回到上次的模糊/遮罩，不再从 0 开始。
@Component
export struct AdjustStageView {
  topPad: number = 0;
  // 裁剪结果基准图：父组件 if 守卫保证创建时非空，生命周期内不变（模糊只生成新实例不污染基准图）
  srcPixelMap: image.PixelMap | null = null;
  // 恢复的上次保存值（父组件 aboutToAppear 从 AppStorage 读回，普通成员创建时赋值、生命周期
  // 内不变；仅用于 aboutToAppear 一次性初始化，调整页每次进入都是新实例故不受响应式影响）
  initialBlurPct: number = 0;
  initialMaskPct: number = 0;
  // 预览框尺寸（vp，父组件经 previewBoxMetrics 计算——与裁剪页完全一致：设备比例 + 统一预留，
  // 见 ImageEditUtil.previewBoxMetrics 注释；2026-08-21 原 layoutWeight(1) 全宽改为固定尺寸）
  boxW: number = 0;
  boxH: number = 0;
  // 事件上行：模糊/遮罩百分比（实时上报，父保存用镜像）、上一步、保存
  onBlurChange: (v: number) => void = (v: number) => {
  };
  onMaskChange: (v: number) => void = (v: number) => {
  };
  onBack: () => void = () => {
  };
  onSave: () => void = () => {
  };

  @State displayPixelMap: image.PixelMap | null = null; // 当前预览（= src 或模糊新实例）
  @State blurPct: number = 0; // 模糊 0~100（无级）
  @State maskPct: number = 0; // 遮罩 0~100（无级）
  // 沉浸光感档位（AppStorage 自订阅，驱动按钮材质——2026-08-22 光感化新增；SliderRow 有
  // 同款双键，本组件按钮用）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关（2026-09-03）：true = 本键官方实底（新规范下内容区材质不生效）；
  // false = 原材质光感；AppStorage 订阅式切换即刷（坑16 正解，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 系统颜色模式（2026-08-22 审查补齐，同 CropStageView 先例）：按钮材质 materialColor
  // 深浅灰分治依赖此值——不订阅则页面存活期间切深浅色，胶囊按钮灰底停留在旧值
  //（resolvedButtonMaterial 读 AppStorage 非响应式）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  private blurSeq: number = 0; // 模糊请求序号（防异步乱序覆盖）
  private lastBlurTs: number = 0; // 节流时间戳（≥100ms 处理一次）
  private disposed: boolean = false; // 组件已销毁（模糊异步回调晚到时释放结果防泄漏）

  aboutToAppear(): void {
    this.displayPixelMap = this.srcPixelMap;
    // 恢复上次保存值（2026-08-21 参数记忆）：初始化滑轨 + 上报父镜像（保证保存按恢复值
    // 重算，用户不重新调整直接「保存」最终图与上次一致）+ 恢复值 >0 时立即刷新预览一次
    // （几十 ms 级，与滑轨拖动同一管线 blurSeq 防乱序；0% 时预览 = 基准图本就正确）
    this.blurPct = this.initialBlurPct;
    this.maskPct = this.initialMaskPct;
    this.onBlurChange(this.blurPct);
    this.onMaskChange(this.maskPct);
    if (this.blurPct > 0) {
      this.refreshPreview();
    }
  }

  // 成对释放：销毁时释放当前模糊预览实例（基准图归父组件释放，判等跳过）
  aboutToDisappear(): void {
    this.disposed = true;
    const old: image.PixelMap | null = this.displayPixelMap;
    if (old !== null && old !== this.srcPixelMap) {
      old.release();
    }
  }

  // 模糊滑块：立即上报父镜像（保存重算用，不受预览节流影响）+ 拖动中（Moving）节流 ≥100ms
  // 刷预览；松手/点击（End/Click/Begin）跳过节流强制刷新——拖动最后一帧可能因节流被跳过
  // 致预览停在倒数第二帧（2026-08-21 全面检查优化；保存链路本就按镜像重算，不受节流影响）
  private handleBlurChange(v: number, mode: SliderChangeMode): void {
    this.blurPct = v;
    this.onBlurChange(v);
    const now: number = Date.now();
    if (mode === SliderChangeMode.Moving && now - this.lastBlurTs < 100) {
      return;
    }
    this.lastBlurTs = now;
    this.refreshPreview();
  }

  // 模糊预览：官方 drawing BlurImageFilter（CLAMP 边模式）生成新实例；
  // blurSeq 丢弃过期异步结果并释放其新实例
  private async refreshPreview(): Promise<void> {
    try {
      const base: image.PixelMap | null = this.srcPixelMap;
      if (base === null || this.disposed) {
        return;
      }
      const seq: number = ++this.blurSeq;
      const out: image.PixelMap = await applyBlur(base, this.blurPct);
      // 过期结果（新请求已发起）或组件已销毁（无释放机会）：丢弃并释放新实例防泄漏
      if (seq !== this.blurSeq || this.disposed) {
        if (out !== base) {
          out.release();
        }
        return;
      }
      const old: image.PixelMap | null = this.displayPixelMap;
      this.displayPixelMap = out;
      if (old !== null && old !== base) {
        old.release(); // 替换时释放旧模糊实例
      }
    } catch (err) {
      // 2026-08-22 检查补：applyBlur 等失败不静默（未处理 promise rejection 属缺陷红线）；
      // 预览保持上一帧，滑动可再触发
      console.error('refresh preview failed: ' + JSON.stringify(err));
    }
  }

  // 遮罩滑块：UI 黑层实时模拟（保存时父组件才像素烧录）+ 上报父镜像
  private onMask(v: number): void {
    this.maskPct = v;
    this.onMaskChange(v);
  }

  build() {
    // 内容区 Scroll 包裹（2026-08-21 决明要求：两页均可上下滑动；预览区无手势，无冲突）
    Scroll() {
      Column({ space: 12 }) {
        // 预览区：处理结果 + 遮罩叠层（遮罩预览 = UI 层实时模拟，保存时才像素烧录）。
        // 固定尺寸 = 预览框几何（与裁剪页一致，父组件传入）；图 Cover 填充——裁剪后图 =
        // 屏幕比例 = 框比例，无变形；layoutWeight 全宽改固定（2026-08-21，见字段注释）
        Stack() {
          if (this.displayPixelMap !== null) {
            Image(this.displayPixelMap)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
          }
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(Color.Black)
            .opacity(this.maskPct / 100)
          // ★ 边界提示白线（2026-08-21 决明选「两页均加白线看效果」：与裁剪页一致——
          // 完整白框（border radius 沿圆角，与父级 clip 同档）；最上层（遮罩暗化时白线
          // 保持可见）；Transparent 不参与命中（预览区滑动 Scroll 正常）
          Column()
            .width('100%')
            .height('100%')
            .border({
              width: 1.5,
              color: '#CCFFFFFF',
              radius: $r('sys.float.ohos_id_corner_radius_default_xl')
            })
            .hitTestBehavior(HitTestMode.Transparent)
        }
        .width(this.boxW)
        .height(this.boxH)
        .clip(true)
        // 圆角 = 官方设备自适应大圆角档（与裁剪页一致，2026-08-21 决明反馈；官方无设备屏幕
        // 圆角 API，用 ohos_id_corner_radius_default_xl 官方近似——见裁剪框处注释）
        .borderRadius($r('sys.float.ohos_id_corner_radius_default_xl'))
        // 深色画布底色（与裁剪画布一致：Image 首帧前窗口深色，不依赖透出背景——见裁剪框注释）
        .backgroundColor('#121212')

        SliderRow({
          title: '模糊', value: this.blurPct, onChange: (v: number, mode: SliderChangeMode) => {
            this.handleBlurChange(v, mode);
          }
        })
        SliderRow({
          title: '遮罩', value: this.maskPct, onChange: (v: number, mode: SliderChangeMode) => {
            this.onMask(v); // UI 黑层实时模拟无异步，mode 不需要
          }
        })

        Row({ space: 12 }) {
          // 次操作（上一步）：官方灰 + font_primary 文字（官方支持反色资源，深浅自动黑/白）
          // + 材质光感（2026-08-22 v3 官方蓝灰配色定稿，姿势同 CropStageView「下一步」）；
          // 光感态 = 原材质…（contentFallback=false 走 resolvedButton*）；实底态 = fallbackButton*
          // 官方实底（contentFallback=true，新规范下内容区材质不生效）；按压反馈随态切换——
          // 光感 false 交给材质形变、实底/无光感档 true 原生（fallbackButtonStateEffect）
          Button('上一步')
            .layoutWeight(1)
            .fontColor(fallbackButtonFont(this.contentFallback, false))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .onClick(() => {
              this.onBack();
            })
          // 主操作（保存）：官方强调蓝 + font_on_primary 恒白 + 材质光感（双态口径同上一句）
          Button('保存')
            .layoutWeight(1)
            .fontColor(fallbackButtonFont(this.contentFallback, true))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .onClick(() => {
              this.onSave();
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ top: this.topPad, left: 16, right: 16, bottom: 24 })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    // 内容不足视口时顶对齐（坑18：Scroll align 默认 Center 会垂直居中）
    .align(Alignment.TopStart)
    // 官方边缘回弹：滑到边界继续滑一段距离、松手回弹
    .edgeEffect(EdgeEffect.Spring)
  }
}
