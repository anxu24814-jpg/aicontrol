// 断点判定单一来源（2026-09-04 平板分栏适配任务 1 新件；纯函数 + AppStorage 键常量，
// 无 UI 无状态——规格自 docs/任务书-平板分栏适配-20260903.md；Cube 参考工程断点常量
// 同值借鉴，窗格宽度/拖拽钳位函数族不搬——Split 模式宽度由 navBarWidth/navBarWidthRange
// 官方管理）。
// ★ 官方查证结论（2026-09-04 任务 0 联网官方文档 + 本地 SDK d.ts 实锤，动工前置）：
// · 模式口径：NavigationMode 为显式设置（Stack 单栏 / Split 分栏两态；Auto 为官方自适应
//   模式——按任务书拍板不采用，MEDIUM 档维持 Stack，断点切换 = 自算档位驱动 mode 属性
//   重渲染实时切换；HdsNavigation mode :2288 / onNavigationModeChange :2394 透传实锤，
//   enableModeChangeAnimation 官方默认带切换动画，不额外配置）。
// · 拖拽调宽：官方 HdsNavigation 参考页实锤「仅设 navBarWidth 不支持分割线拖拽，
//   navBarWidthRange 指定分割线可拖拽范围」——NavBarWidthRangeOptions{minWidth,maxWidth}
//   （d.ts :2047）设置后拖拽由 HDS 自动携带；enableDragBar(:2434，@since 6.0.0(20))
//   显式传 true 保底（默认值未注明，显式化 = 需求必需非额外开关）。
// · 占位与转场：分栏空栈右栏走 splitPlaceholder(:2484，@since 6.1.0(23)，ComponentContent
//   形态)；NavDestination 在右栏内转场由官方接管（divider 分割线默认显示，null 才隐藏，
//   保留默认）；minContentWidth 不设（官方默认管理）。
// · 宽度源与刷新纪律：Index.ets window.getLastWindow 链上 on('windowSizeChange') 实测
//   （@ohos.window.d.ts :5360，Callback<Size> px 单位经 px2vp 换算），**仅档位跨越时写
//   AppStorage**（窗口连续拖动不逐帧刷新——性能红线）；断点不持久（persistProp 不需要），
//   AppStorage 缺省 = COMPACT——手机竖屏/窄悬浮窗恒 COMPACT，分栏路径零触达 = 窄屏
//   行为零变化。
// 三档口径（Cube 同值）：COMPACT < 600vp / MEDIUM 600~840 / EXPANDED ≥ 840。

// AppStorage 断点档位键（消费方 @StorageProp 订阅；0/1/2 = COMPACT/MEDIUM/EXPANDED）
export const LAYOUT_SIZE_CLASS_KEY: string = 'LAYOUT_SIZE_CLASS';

// 档位常量（AppStorage 存 number——@StorageProp 直接以 number 收，缺省 0 = COMPACT）
export const LAYOUT_COMPACT: number = 0;
export const LAYOUT_MEDIUM: number = 1;
export const LAYOUT_EXPANDED: number = 2;

// 断点阈值（vp，Cube 同值）：600 ≈ 平板竖屏下沿 / 840 ≈ 折叠展开态·平板横屏下沿
const MEDIUM_MIN_VP: number = 600;
const EXPANDED_MIN_VP: number = 840;

// 宽度（vp）→ 档位：纯函数（Index.ets 窗口实测宽后调用）
export function resolveLayoutSizeClass(widthVp: number): number {
  if (widthVp >= EXPANDED_MIN_VP) {
    return LAYOUT_EXPANDED;
  }
  return widthVp >= MEDIUM_MIN_VP ? LAYOUT_MEDIUM : LAYOUT_COMPACT;
}

// 档位 → 是否分栏：仅 EXPANDED 进 Split（MEDIUM 维持 Stack——任务书「仅 Split/Stack
// 两态」拍板，MEDIUM 特殊布局后置）
export function isExpandedLayout(sizeClass: number): boolean {
  return sizeClass === LAYOUT_EXPANDED;
}

// ═══ 分栏 navBar 宽度参数（vp，任务书建议值——真机定稿可调） ═══
// 初始宽 360 / 拖拽范围 280~520（HomeNavigation 唯一消费方；仅 Split 模式生效）
export const SPLIT_NAV_BAR_WIDTH: number = 360;
export const SPLIT_NAV_BAR_MIN: number = 280;
export const SPLIT_NAV_BAR_MAX: number = 520;
