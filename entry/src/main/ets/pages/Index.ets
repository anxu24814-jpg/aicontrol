// 应用入口（2026-08-29 反馈轮 4 恢复避让区实测）：挂导航壳 HomeNavigation（HdsNavigation
// 根 + HdsTabs 悬浮页签 + 会话列表路由，见 components/nav/HomeNavigation.ets）；本页负责
// 系统避让区高度实测下发（全屏窗口下页面留白/页签距底的唯一数据源，dshinhm Index 同款姿势）。
// ★ 断点档位实测下发（2026-09-04 平板分栏适配任务 1）：getLastWindow 链上先写初始档位
//（冷启动宽屏直进 Split）再注册 windowSizeChange 监听——仅档位跨越时写 AppStorage
//（窗口连续拖动不逐帧刷新，性能红线）；档位语义与三档口径见 common/LayoutProfile.ets。
import { window } from '@kit.ArkUI';
import { HomeNavigation } from '../components/nav/HomeNavigation';
import { ProactiveBanner } from '../components/ProactiveBanner';
import { LAYOUT_COMPACT, LAYOUT_SIZE_CLASS_KEY, resolveLayoutSizeClass } from '../common/LayoutProfile';

@Entry
@Component
struct Index {
  // 顶部避让区（vp）= 状态栏高：标题栏蒙层下滚动内容首卡留白（titleBarInset）的组成项
  @State statusBarHeight: number = 0;
  // 底部避让区（vp）= 导航条/手势指示条高：悬浮页签距底 + 页面底部留白的组成项
  @State navBarHeight: number = 0;
  // 主窗口引用（getLastWindow 单窗口恒同实例；仅本页 aboutToAppear 注册/aboutToDisappear
  // 注销 windowSizeChange 用——@Entry 根页寿命 = 应用级，与窗口同寿命无泄漏）
  private mainWindow: window.Window | null = null;
  // 窗口尺寸变化回调（成员位 = 注册/注销共用同一引用；px → vp → 档位，跨档才落键）
  private onWindowSizeChange: (size: window.Size) => void = (size: window.Size): void => {
    const widthVp: number = this.getUIContext().px2vp(size.width);
    const next: number = resolveLayoutSizeClass(widthVp);
    if ((AppStorage.get<number>(LAYOUT_SIZE_CLASS_KEY) ?? LAYOUT_COMPACT) !== next) {
      AppStorage.setOrCreate<number>(LAYOUT_SIZE_CLASS_KEY, next);
    }
  };

  aboutToAppear(): void {
    const uiContext = this.getUIContext();
    const hostContext = uiContext.getHostContext();
    if (!hostContext) {
      // 禁止静默失败（P0-1）：取不到宿主上下文则避让区与断点监听全不挂，留日志定位
      console.error('index aboutToAppear failed: host context unavailable');
      return;
    }
    window.getLastWindow(hostContext).then((win: window.Window) => {
      this.mainWindow = win;
      // 本 SDK 中 getWindowAvoidArea 为同步接口（返回 AvoidArea 而非 Promise）；
      // rect 单位 px，布局属性单位 vp，必须经 UIContext.px2vp 换算（否则放大 density 倍）
      const systemArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.statusBarHeight = uiContext.px2vp(systemArea.topRect.height);
      this.navBarHeight = Math.max(this.navBarHeight, uiContext.px2vp(systemArea.bottomRect.height));
      const indicatorArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.navBarHeight = Math.max(this.navBarHeight, uiContext.px2vp(indicatorArea.bottomRect.height));
      // 断点监听（注册/注销成对，注销见 aboutToDisappear——内存红线）：先写初始档位
      //（首帧即正确档位，冷启动 ≥840vp 直进 Split），后注册变化监听；回调内仅跨档落键
      this.onWindowSizeChange({ width: win.getWindowProperties().windowRect.width,
        height: win.getWindowProperties().windowRect.height });
      win.on('windowSizeChange', this.onWindowSizeChange);
    }).catch((err: Error) => {
      // 获取失败保持 0：页签距底退回官方兜底 32vp（tabBarBottomMargin），留白变小不影响功能；
      // 断点档位同守恒缺省 COMPACT（窄屏行为零变化）
      console.error('getWindowAvoidArea failed: ' + JSON.stringify(err));
    });
  }

  aboutToDisappear(): void {
    // 断点监听注销（与 aboutToAppear 注册成对；@Entry 根页实际仅应用退出触发）
    if (this.mainWindow !== null) {
      this.mainWindow.off('windowSizeChange', this.onWindowSizeChange);
      this.mainWindow = null;
    }
  }

  build() {
    // @Entry 根节点必须是容器组件。根 Stack（2026-09-12 主动消息第二笔：顶层常驻
    // ProactiveBanner——覆盖含二级页在内的全部页面；原 Column 单容器无处叠浮层〔项目无
    // 应用级浮层先例，本笔为主方案〕。alignContent Top = 横幅贴顶，HomeNavigation 自带
    // 100% 全幅不受对齐影响；改根三层真机回归〔首页/页签、二级页 push/pop、沉浸背景垫底
    // 与 TabContent 懒加载不闪〕见任务书 §3.2——异常即切降级方案挂 HomeNavigation 内容
    // Stack 内，届时本文件回退 Column）
    Stack({ alignContent: Alignment.Top }) {
      HomeNavigation({
        statusBarHeight: this.statusBarHeight,
        navBarHeight: this.navBarHeight
      })
      ProactiveBanner({ statusBarHeight: this.statusBarHeight })
    }
    .width('100%')
    .height('100%')
  }
}
