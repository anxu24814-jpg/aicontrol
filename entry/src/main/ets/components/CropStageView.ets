// 「编辑图片」裁剪阶段视图（2026-08-21 自 ImageEditUi.ets 拆出——该文件 411 行超 400
// 行红线，按「阶段视图」模式拆：CropStageView.ets / AdjustStageView.ets）。
// 纯展示 + 事件回调上行，零业务逻辑——图像处理与保存流程留在 ImageEditPage。
// 状态自包含约定（2026-08-21 闪退修复同轮重构，根因见 ImageEditPage 头注释）：
// - 手势驱动的高频值（imgScale/tx/ty/zoomPct）为本组件 @State——V1 语义下普通成员入参在父重建时
//   只重新赋值、不触发子组件重渲染；高频更新留在子组件内渲染，不穿越父组件。
// - 变化中的标量经 onGeometryChange 实时上报父组件普通成员镜像（父仅「下一步」时读取）。
// - PixelMap 为 native 对象不可 @Prop 深拷贝：父组件用 if 守卫保证 PixelMap 非空才创建
//   子组件（普通成员入参创建时赋值即可，生命周期内不变）。
// 拆分规则：页面再超 400 行继续按「阶段视图」模式拆（头注释写契约）。
import { image } from '@kit.ImageKit';
import { CARD_PANEL_WIDTH } from '../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect } from '../common/ImmersiveLevel';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SliderRow } from './SliderRow';

// 裁剪手势 Modifier（官方编程式手势 API，@since 12；官方「动态手势设置」示例同款模式）：
// PanGesture/PinchGesture 是 DSL 全局工厂（SDK d.ts 中 declare const），只能在 build 上下文
// 中调用——在字段初始化器/aboutToAppear 中创建会访问空 build 上下文，进程直接崩溃
// （2026-08-21 真机「点编辑图片即闪退」根因，hilog 打点定位于此）。GestureHandler 系列是
// 普通类（declare class + constructor），任意位置可实例化；gestureModifier 不支持自定义
// 组件，须挂在内置组件（Image）上。
// 2026-08-22 缩放改滑轨（决明要求）：手势域 = 单指平移，双指缩放移除（PinchGestureHandler
// 删除；缩放走预览框下方滑轨、绕裁剪框中心，见 handleZoomChange）。
// 回调由宿主组件在 aboutToAppear 注入（创建 Modifier 时组件成员尚未就绪）。
class CropGestureModifier implements GestureModifier {
  onPanStart: (e: GestureEvent) => void = (e: GestureEvent) => {
  };
  onPanUpdate: (e: GestureEvent) => void = (e: GestureEvent) => {
  };

  applyGesture(event: UIGestureEvent): void {
    // 单指平移（addGesture 默认 NORMAL 优先级 = .gesture() 默认；单手势无需分组包装）
    event.addGesture(new PanGestureHandler({ fingers: 1, direction: PanDirection.All, distance: 5 })
      .onActionStart(this.onPanStart)
      .onActionUpdate(this.onPanUpdate));
  }
}

// 阶段一：裁剪视图（屏幕比例容器 + 拖动手势图片 + 白色裁剪框边界 + 缩放滑轨 + 提示 + 下一步）。
// imgScale/tx/ty/zoomPct 为本组件 @State（手势/滑轨高频更新只重渲染本组件）；缩放 = 预览框
// 下方滑轨（0~100 线性映射 1.0×~5.0×，绕裁剪框中心——见 handleZoomChange 注释），双指缩放
// 已按决明要求移除（手势域 = 仅平移）；几何经 onGeometryChange 上报父组件镜像（初始一次 +
// 每次手势/滑轨更新，父仅「下一步」映射裁剪区域时读取）。
@Component
export struct CropStageView {
  topPad: number = 0;
  // 解码基准图（= 裁剪页原图 origPixelMap）：父组件 if 守卫保证创建时非空；**生命周期内引用
  // 不变且内容不被原地修改**（2026-08-22 region 传递方案：「下一步」只传裁剪 region，调整页
  // 自解码自裁剪——本组件在栈下层保持存活、原图完整，返回后可直接继续手势编辑；早前
  // 「克隆原图裁剪后 push」的双图制已随坑43 废除）
  srcPixelMap: image.PixelMap | null = null;
  cropBoxW: number = 0; // 容器宽（= 图显示宽）
  cropBoxH: number = 0; // 容器高（屏幕比例）
  // ── 恢复的上次保存缩放/平移（2026-08-22 缩放丢失修复）──
  // 普通成员入参（创建时赋值一次、生命周期内不变——恢复仅需一次）：ImageEditPage 从
  // AppStorage 读 CROP_STATE 的 [scale, tx, ty] 传入；aboutToAppear 在 scale0 计算后恢复
  // （scale 钳位 [scale0, scale0×5]、zoomPct 反推显示、tx/ty 原值 + clampTranslate 兜底）
  initialScale: number = 0;
  initialTx: number = 0;
  initialTy: number = 0;
  // 几何上报：imgVpW/imgVpH 图显示尺寸、scale/tx/ty 当前变换（父镜像为普通成员，不触发父重渲染）
  onGeometryChange: (imgVpW: number, imgVpH: number, scale: number, tx: number, ty: number) => void =
    (imgVpW: number, imgVpH: number, scale: number, tx: number, ty: number) => {
    };
  onNext: () => void = () => {
  };

  // 沉浸光感档位（AppStorage 自订阅，驱动「下一步」按钮材质——2026-08-22 光感化新增；
  // 同 AdjustStageView 先例）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关（2026-09-03）：true = 本按钮官方实底（新规范下内容区材质不生效）；
  // false = 原材质光感；AppStorage 订阅式切换即刷（坑16 正解，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 系统颜色模式（2026-08-22 检查补齐）：按钮材质 materialColor 深浅灰分治依赖此值——
  // 不订阅则运行中切换深浅色灰底停留在旧值（resolvedButtonMaterial 读 AppStorage 非响应式）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  @State imgScale: number = 1; // 当前缩放（[scale0, scale0×5]；命名避开 CustomComponent 基类 scale）
  @State zoomPct: number = 0; // 缩放滑轨值 0~100（线性映射 1.0×~5.0× = scale0×(1+pct/25)）
  @State tx: number = 0; // 平移 x（边界钳位）
  @State ty: number = 0;
  private imgVpW: number = 0; // 图显示宽（= cropBoxW）
  private imgVpH: number = 0; // 图显示高（按像素纵横比）
  private scale0: number = 1; // 初始适配（Cover 最小填满，缩放下限防露白）
  private baseTx: number = 0;
  private baseTy: number = 0;
  // 编程式手势 Modifier：普通类实例，字段初始化器创建安全（见 CropGestureModifier 头注释）；
  // 成员缓存同一引用，重渲染不重建手势（官方文档：进行中的手势切换在下一次手势生效）。
  // 命名避开 CustomComponent 基类 gestureModifier 成员（同名遮蔽 ArkTS 编译错误 10505001）
  private cropGestureModifier: CropGestureModifier = new CropGestureModifier();

  // 初始化裁剪几何 + 绑手势回调（aboutToAppear 时入参已就绪）
  aboutToAppear(): void {
    const pm: image.PixelMap | null = this.srcPixelMap;
    if (pm === null) {
      return; // 父守卫保证非空；防御（渲染分支同样判空）
    }
    const info: image.ImageInfo = pm.getImageInfoSync();
    this.imgVpW = this.cropBoxW;
    this.imgVpH = this.cropBoxW * info.size.height / info.size.width;
    this.scale0 = Math.max(this.cropBoxW / this.imgVpW, this.cropBoxH / this.imgVpH);
    this.imgScale = this.scale0;
    this.cropGestureModifier.onPanStart = (e: GestureEvent) => {
      this.baseTx = this.tx;
      this.baseTy = this.ty;
    };
    this.cropGestureModifier.onPanUpdate = (e: GestureEvent) => {
      this.tx = this.baseTx + e.offsetX;
      this.ty = this.baseTy + e.offsetY;
      this.clampTranslate();
      this.reportGeometry();
    };
    // 初始几何上报（用户未动手势直接「下一步」时父镜像即为初始满框值）
    // ★ 恢复上次保存的缩放/平移（2026-08-22）：scale 钳位 [scale0, scale0×5]（同设备同源图
    // 精确；跨设备/换图 scale0 不同则钳位兜底）→ zoomPct 反推滑轨显示、tx/ty 原值 + clamp
    // 兜底，恢复后重新上报（父「下一步」镜像 = 恢复后的几何——不恢复直接下一步会按满框裁）。
    // 语义 = 「最后一次保存成功值」（编辑当前背景 = 同一 src 原图文件，精确恢复）
    if (this.initialScale > 0 || this.initialTx !== 0 || this.initialTy !== 0) {
      this.imgScale = Math.min(this.scale0 * 5, Math.max(this.scale0, this.initialScale));
      this.zoomPct = Math.round((this.imgScale / this.scale0 - 1) * 25);
      this.tx = this.initialTx;
      this.ty = this.initialTy;
      this.clampTranslate();
    }
    this.reportGeometry();
  }

  // 缩放滑轨（2026-08-22 新增，代替原双指缩放）：线性 0~100 → 1.0×~5.0×
  // （imgScale = scale0×(1+pct/25)；上下限沿用原 Pinch 定稿 [scale0, scale0×5]——下限防露白）。
  // ★ 绕裁剪框中心缩放（决明批准方案）：视觉矩形 = 框中心 + translate(小写 t) + 尺寸×scale，
  // 绕框中心缩放 k 倍 ⇒ t' = t×k（tx/ty 同乘 k）——缩放中框中心内容不动、与平移解耦，先拖
  // 到位再放大目标仍在框心附近；旧 Pinch 绕图片视觉中心的行为（缩放时内容整体飘走）随双指
  // 缩放一并移除。最后照常 clampTranslate 防露白。
  // 不改「下一步」映射公式：补偿后视觉矩形仍是「中心偏移 + 尺寸×scale」同一数学形式
  // （ImageEditPage.cropVisibleRegion 语义不变，镜像链未破）。纯 UI 变换无异步 → 不节流。
  private handleZoomChange(v: number, mode: SliderChangeMode): void {
    this.zoomPct = v;
    const newScale: number = this.scale0 * (1 + v / 25);
    const k: number = newScale / this.imgScale;
    this.tx *= k;
    this.ty *= k;
    this.imgScale = newScale;
    this.clampTranslate();
    this.reportGeometry();
  }

  // 平移边界钳位：图缩放后不小于容器时，可平移范围 = (图显示尺寸 − 容器)/2（防露白）
  private clampTranslate(): void {
    const maxTx: number = Math.max(0, (this.imgVpW * this.imgScale - this.cropBoxW) / 2);
    const maxTy: number = Math.max(0, (this.imgVpH * this.imgScale - this.cropBoxH) / 2);
    this.tx = Math.min(maxTx, Math.max(-maxTx, this.tx));
    this.ty = Math.min(maxTy, Math.max(-maxTy, this.ty));
  }

  private reportGeometry(): void {
    this.onGeometryChange(this.imgVpW, this.imgVpH, this.imgScale, this.tx, this.ty);
  }

  build() {
    // 内容区 Scroll 包裹（2026-08-21 决明要求：两页均可上下滑动——内容超出视口（小屏/
    // 大字号）时提示/滑轨/按钮可滚动；裁剪框 Pan 手势挂在裁剪框 Stack 容器上
    // 深度优先命中，不冲突——真机点验项）
    Scroll() {
      Column({ space: 20 }) {
        Stack() {
          if (this.srcPixelMap !== null) {
            Image(this.srcPixelMap)
              .width(this.cropBoxW)
              .height(this.imgVpH)
              .scale({ x: this.imgScale, y: this.imgScale })
              .translate({ x: this.tx, y: this.ty })
          }
          // 裁剪框边界提示（白细线 80%，无背景；hitTestBehavior(Transparent) 保证不拦截手势——
          // 覆盖在 Image 上方的组件默认可能参与命中测试，2026-08-21 手势不生效排查时显式声明）
          // ★ border radius（2026-08-21 修复白线不完整）：原矩形 border 四角被父级圆角 clip
          // 切掉（圆角处无白线）；BorderOptions.radius @since 9 官方参数——border 沿圆角绘制，
          // 与父级 clip 圆角（同 xl 档）一致 → 白线完整包住四周含圆角
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
        .width(this.cropBoxW)
        .height(this.cropBoxH)
        .clip(true)
        // ★ 手势与 Block 挂 Stack 容器（2026-08-22 审查修复，原挂 Image）：命中测试基于
        // 布局区域、scale/translate 纯视觉变换不扩展命中区——宽幅/方形图 imgVpH < cropBoxH
        // 时 Image 布局矩形只占框中间一条，框内上下两侧「看得见图但拖不动、还会穿透触发
        // Scroll 滚动」（死区合计可达框高 65%）；改挂 Stack 后整个裁剪框内任意位置都可
        // 拖图且 Block 阻断祖先 Scroll（白线 Column 为 Transparent 不受 Block 影响；
        // PanGesture 的 offsetX/offsetY 为手势累计位移、与挂载目标无关，手势逻辑不变）。
        // Block 语义（@since 9，d.ts 原文「自身响应命中测试，并阻止子/兄弟/祖先节点的命中
        // 测试」）：2026-08-21 决明要求「裁剪预览框内不触发上下滚动防止误触」
        .hitTestBehavior(HitTestMode.Block)
        // 官方编程式手势（原 .gesture(DSL 工厂) 改 .gestureModifier，见类注释）
        .gestureModifier(this.cropGestureModifier)
        // ★ 圆角改官方设备自适应大圆角档（2026-08-21 决明反馈：16vp 与设备实际圆角观感不符；
        // 官方无「设备屏幕圆角」API（display/window 均无 cornerRadius，系统 corner_radius 资源
        // 全部组件级）——官方近似 = ohos_id_corner_radius_default_xl（官方最大圆角档，系统按
        // 设备/版本自动取值 ≈ 24~36vp，天然自适应），两页预览框一致）
        .borderRadius($r('sys.float.ohos_id_corner_radius_default_xl'))
        // ★ 深色画布底色（2026-08-21 浅色模式闪白回归修复）：原透明（坑40 修复）依赖
        // 「透出内容为深色」（当时背景 = 深色壁纸）；bgSolid 纯色例外后浅色模式透出页面
        // 浅灰 #F1F3F5 → 闪白回归。显式深色画布 #121212 自给自足（编辑器惯例，与深色图/
        // 下层衔接，任何背景不闪）；修正坑40 表述：**浅色实体底才是闪白源，深色画布不是**
        // （图片来源无关）。图片 Cover 填满后画布不可见（首帧前窗口可见）
        .backgroundColor('#121212')

        Text('拖动移动图片，下方滑轨缩放。框内区域即为最终背景')
          .fontSize(13)
          .fontColor($r('sys.color.font_tertiary'))
          .textAlign(TextAlign.Center)

        // 缩放滑轨（2026-08-22 新增，代替原双指缩放——决明要求「预览框下方一条滑轨」）：
        // 公共 SliderRow（自 AdjustStageView 提取）——标题「缩放」左、右侧当前倍数「×N.N」
        // （valueFormatter：0→×1.0、100→×5.0），官方 InSet 滑块 + 沉浸光感材质（归「其他
        // 控件」分项）——材质/宽度/厚度完全参考调整页滑轨真机定稿先例。框外 + 官方 Slider
        // 消费触摸不触发外层 Scroll（调整页真机先例），无需 hitTestBehavior；交互逻辑见
        // handleZoomChange 注释（绕裁剪框中心缩放）
        SliderRow({
          title: '缩放',
          value: this.zoomPct,
          onChange: (v: number, mode: SliderChangeMode) => {
            this.handleZoomChange(v, mode);
          },
          valueFormatter: (v: number) => {
            return '×' + (1 + v / 25).toFixed(1);
          }
        })

        // 主操作按钮（2026-08-22 沉浸光感化 v3 + 2026-09-03 内容区回退双态）：光感态 =
        // 官方蓝灰配色 + 材质光感——透明底 + systemMaterial(resolvedButtonMaterial(…,
        // primary=true)：REGULAR + 形变/光效 + materialColor 官方强调蓝 + colorInvert
        // 官方文字反色，随沉浸光感总档）+ font_on_primary（蓝底恒白字）；实底态 =
        // fallbackButton* 强制官方强调蓝实底 + 恒白字 + stateEffect(true) 原生按压。
        // 高度官方默认（40vp）；触摸反馈：材质档关闭原生按压（材质接管形变/光效），
        // 实底/无光感档保留原生按压（fallbackButtonStateEffect 恒 true）
        Button('下一步')
          .width(CARD_PANEL_WIDTH)
          .fontColor(fallbackButtonFont(this.contentFallback, true))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .onClick(() => {
            this.onNext();
          })
      }
      .width('100%')
      .padding({ top: this.topPad, left: 16, right: 16 })
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
