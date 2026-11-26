// 「编辑图片」调整阶段视图（自 ImageEditUi.ets 按「阶段视图」模式拆出）。
// 调整滑轨用公共 SliderRow（./SliderRow.ets，裁剪页缩放滑轨同构共用）。
// 纯展示 + 事件回调上行，零业务逻辑——图像处理与保存流程留在
// ImageAdjustPage。状态自包含约定（同 CropStageView.ets 头注释）：
// - 滑轨驱动的高频值（blurPct/maskPct）与预览位图（displayPixelMap）为本组件 @State；
// - 变化中的百分比经 onBlurChange/onMaskChange 实时上报父组件普通成员镜像（父「保存」时
//   按镜像重算最终图）；
// - PixelMap 为 native 对象不可 @Prop 深拷贝：父组件用 if 守卫保证非空才创建子组件。
// 拆分规则：页面再超 400 行继续按「阶段视图」模式拆（头注释写契约）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { IMMERSIVE_LEVEL_KEY, CONTENT_FALLBACK_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect } from '../common/ImmersiveLevel';
import { applyBlur } from '../common/ImageEditUtil';
import { SliderRow } from './SliderRow';

// 阶段二：调整视图（预览 + 模糊/遮罩滑轨 + 上一步/保存）。
// PixelMap 生命周期：模糊新实例替换时释放旧实例，aboutToDisappear 释放当前预览（基准图
// srcPixelMap 归父组件统一释放，此处判等跳过）。初始值恢复（编辑参数记忆）：父传入
// initialBlurPct/initialMaskPct（= 上次保存成功值），aboutToAppear 据此初始化滑轨 @State +
// 上报父镜像（保存按恢复值重算）+ 预览立即刷新一次——重进调整页回到上次的模糊/遮罩。
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
  // 见 ImageEditUtil.previewBoxMetrics 注释）
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
  // 沉浸光感档位（AppStorage 自订阅，驱动按钮材质；SliderRow 有同款双键）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关：true = 本键官方实底（新规范下内容区材质不生效）、false = 原材质光感；
  // AppStorage 订阅式切换即刷（坑16 正解，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 系统颜色模式（同 CropStageView 先例）：按钮材质 materialColor 深浅灰分治依赖此值——
  // 不订阅则页面存活期间切深浅色，胶囊按钮灰底停留在旧值（resolvedButtonMaterial 读
  // AppStorage 非响应式）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  private blurSeq: number = 0; // 模糊请求序号（防异步乱序覆盖）
  private lastBlurTs: number = 0; // 节流时间戳（≥100ms 处理一次）
  private disposed: boolean = false; // 组件已销毁（模糊异步回调晚到时释放结果防泄漏）

  aboutToAppear(): void {
    this.displayPixelMap = this.srcPixelMap;
    // 恢复上次保存值：初始化滑轨 + 上报父镜像（保证保存按恢复值重算，用户不重新调整直接
    // 「保存」最终图与上次一致）+ 恢复值 >0 时立即刷新预览一次（与滑轨拖动同一管线 blurSeq
    // 防乱序；0% 时预览 = 基准图本就正确）
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
  // 致预览停在倒数第二帧（保存链路按镜像重算，不受节流影响）
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
      // applyBlur 等失败不静默（未处理 promise rejection 属缺陷红线）；预览保持上一帧，滑动可再触发
      hilog.error(0xD5A0, 'AdjustStageView', 'refresh preview failed: %{public}s', JSON.stringify(err));
    }
  }

  // 遮罩滑块：UI 黑层实时模拟（保存时父组件才像素烧录）+ 上报父镜像
  private onMask(v: number): void {
    this.maskPct = v;
    this.onMaskChange(v);
  }

  build() {
    // 内容区 Scroll 包裹（决明要求：两页均可上下滑动；预览区无手势，无冲突）
    Scroll() {
      Column({ space: 12 }) {
        // 预览区：处理结果 + 遮罩叠层（遮罩预览 = UI 层实时模拟，保存时才像素烧录）。
        // 固定尺寸 = 预览框几何（与裁剪页一致，父组件传入）；图 Cover 填充——裁剪后图 =
        // 屏幕比例 = 框比例，无变形
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
          // ★ 边界提示白线（决明拍板两页均加，与裁剪页一致）：完整白框（border radius 沿
          // 圆角，与父级 clip 同档）；最上层（遮罩暗化时白线保持可见）；Transparent 不参与
          // 命中（预览区滑动 Scroll 正常）
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
        // 圆角 = 官方设备自适应大圆角档（与裁剪页一致；官方无设备屏幕圆角 API——见裁剪页注释）
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
          // 次操作（上一步）：官方灰 + font_primary 文字（深浅自动黑/白）+ 材质光感（姿势同
          // CropStageView「下一步」）；双态走 fallbackButton* 单源（contentFallback 切实底/光感），
          // 按压反馈随态切换（光感档交材质形变、实底/无光感档原生）
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
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off)
  }
}
