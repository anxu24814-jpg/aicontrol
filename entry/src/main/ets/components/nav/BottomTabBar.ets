// 底部悬浮胶囊 Tab 栏 —— 回退路径组件（2026-08-29 M2a 自 dshinhm components/BottomTabBar.ets
// 随迁改两页签版——原版三分支耦合其连接/我的页签，不搬本体）：仅设备无 HDS Full syscap
// 时由 components/nav/HomeNavigation.ets 使用；主路径为官方 HdsTabs 悬浮页签
// （材质/按压形变/触点光效/距底均由官方组件接管）。
//
// 材质：官方沉浸光感组件级开启 systemMaterial（本地 SDK uiMaterial d.ts @since 26.0.0；
// 项目 compatibleSdkVersion 26.0.0 保底，无需版本分流）。基准档 REGULAR（官方通用场景默认），
// 档位由 common/ImmersiveLevel.ets 解析（M2a 无外观页恒为定稿默认档「自适应」）；
// interactive/lightEffect = 官方按压弹性形变/触点光晕。
// 选中态仅用颜色区分（官方 BottomTabBarStyle 选中无底色遮罩）；材质自带背景/描边/阴影，
// 按官方性能约束不再叠加自定义 shadow/背景模糊；同一子树只最外层设一次材质。
import { uiMaterial } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, resolvedUiMaterial } from '../../common/ImmersiveLevel';

@Component
export struct BottomTabBar {
  // 当前选中的页签（0=助手，1=对话，2=设置——2026-09-01 换序助手居首）；本组件只读
  // 展示 + 点击回调，切换由 HomeNavigation 负责
  @Prop currentTab: number = 0;
  onTabChange: (index: number) => void = () => {
  };
  // 系统颜色模式（深浅色切换自动刷新配色；EntryAbility 未写键时缺省浅色——与 M1 既有组件
  // ChatMessageItem 同姿势，缺口统一登记 BLOCKED.md 待裁决，不在本组件单方面补）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 整体沉浸光感档位（AppStorage 共享，见 common/ImmersiveLevel.ets；2026-09-12 分项退役——
  // 原另有「悬浮底栏」分项键，胶囊材质恒跟随总档）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关（2026-09-03）：回退胶囊 TabBar 挂普通 Navigation 路径（非 Tabs tabBar，
  // 规范边界外 = 受影响组件）——true = 官方灰实底；false = 原 REGULAR 材质光感；
  // AppStorage 订阅式切换即刷（坑16 正解，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;

  // 图标/文字颜色：选中用主题蓝（深色模式换亮蓝保证可读），未选中灰色（dshinhm 定稿色值）
  tabColor(selected: boolean): ResourceColor {
    if (!selected) {
      return this.appColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#8A8A8A' : '#999999';
    }
    return this.appColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#4D9BFF' : '#007CFF';
  }

  @Builder
  TabItem(index: number, label: string, icon: Resource) {
    Column({ space: 3 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([this.tabColor(this.currentTab === index)])
      Text(label)
        .fontSize(11)
        .fontColor(this.tabColor(this.currentTab === index))
    }
    .width(72)
    .height(46)
    .borderRadius(23)
    .accessibilityText(label + '页签')
    .onClick(() => {
      this.onTabChange(index);
    })
  }

  build() {
    Row({ space: 4 }) {
      this.TabItem(0, '助手', $r('sys.symbol.person'))
      this.TabItem(1, '对话', $r('sys.symbol.message'))
      this.TabItem(2, '设置', $r('sys.symbol.gearshape'))
    }
    .padding(5)
    .borderRadius(28)
    // 双态（2026-09-03 内容区回退）：实底态 = 官方灰阶实色（app.color.comp_fallback_gray
    // 深浅分治、不透明——原官方语义色带透明度，底部内容透出可读性差，2026-09-03 决明反馈
    // 后换；按压形变/触点光晕不可用——Row 无 stateEffect，无档回退官方灰实底无按压反馈）；
    // 光感态 = 官方沉浸光感材质（置于其他样式属性之后；按压形变 + 触点光晕随沉浸光感
    // 总档解析——2026-09-12 分项退役口径）
    .backgroundColor(this.contentFallback ? $r('app.color.comp_fallback_gray') : Color.Transparent)
    .systemMaterial(this.contentFallback ? uiMaterial.Material.empty :
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, this.immersiveLevel, true))
  }
}
