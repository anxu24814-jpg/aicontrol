// 应用入口：挂导航壳 HomeNavigation（见 components/nav/HomeNavigation.ets）；本页负责系统
// 避让区高度实测下发（全屏窗口下页面留白/页签距底的唯一数据源）+ 断点档位实测下发（先写
// 初始档位再注册 windowSizeChange，仅跨档才落键——连续拖动不逐帧刷新，性能红线；档位口径
// 见 common/LayoutProfile.ets）。
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HomeNavigation } from '../components/nav/HomeNavigation';
import { ProactiveBanner } from '../components/ProactiveBanner';
import { BusyOverlay } from '../components/BusyOverlay';
import { PrivacyConsentGate } from '../components/PrivacyConsentGate';
import { LAYOUT_COMPACT, LAYOUT_SIZE_CLASS_KEY, resolveLayoutSizeClass } from '../common/LayoutProfile';

@Entry
@Component
struct Index {
  // 顶部避让区（vp）= 状态栏高：标题栏蒙层下滚动内容首卡留白（titleBarInset）的组成项
  @State statusBarHeight: number = 0;
  // 底部避让区（vp）= 导航条/手势指示条高：悬浮页签距底 + 页面底部留白的组成项
  @State navBarHeight: number = 0;
  // 主窗口引用（注册/注销 windowSizeChange 成对用；@Entry 根页与窗口同寿命无泄漏）
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
      hilog.error(0x0001, 'Index', 'aboutToAppear failed: host context unavailable');
      return;
    }
    window.getLastWindow(hostContext).then((win: window.Window) => {
      this.mainWindow = win;
      // 本 SDK getWindowAvoidArea 同步返回 px，必须经 UIContext.px2vp 换算（否则放大 density 倍）
      const systemArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.statusBarHeight = uiContext.px2vp(systemArea.topRect.height);
      this.navBarHeight = Math.max(this.navBarHeight, uiContext.px2vp(systemArea.bottomRect.height));
      const indicatorArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.navBarHeight = Math.max(this.navBarHeight, uiContext.px2vp(indicatorArea.bottomRect.height));
      // 断点监听（与 aboutToDisappear 注销成对——内存红线）：先写初始档位（首帧即正确，
      // 冷启动宽屏直进 Split）再注册监听；回调内仅跨档落键
      this.onWindowSizeChange({ width: win.getWindowProperties().windowRect.width,
        height: win.getWindowProperties().windowRect.height });
      win.on('windowSizeChange', this.onWindowSizeChange);
    }).catch((err: Error) => {
      // 失败保持 0：页签距底退官方兜底 32vp（tabBarBottomMargin）、断点缺省 COMPACT，不影响功能
      hilog.error(0x0001, 'Index', 'getWindowAvoidArea failed: %{public}s', JSON.stringify(err));
    });
  }

  aboutToDisappear(): void {
    // 断点监听注销（与 aboutToAppear 成对；@Entry 根页实际仅应用退出触发）
    if (this.mainWindow !== null) {
      this.mainWindow.off('windowSizeChange', this.onWindowSizeChange);
      this.mainWindow = null;
    }
  }

  // （根页系统返回拦截已随 2026-11-18 侧栏二级页化笔退役：侧栏是真 NavDestination，
  // 官方返回链自行消费，根页无抽屉可收、回落应用默认返回）

  build() {
    // @Entry 根节点必须是容器。根 Stack 供顶层常驻 ProactiveBanner / 长任务遮罩 / 同意闸
    // 叠层（覆盖含二级页在内的全部页面；alignContent Top = 横幅贴顶，HomeNavigation 自带
    // 100% 全幅不受对齐影响）
    Stack({ alignContent: Alignment.Top }) {
      HomeNavigation({
        statusBarHeight: this.statusBarHeight,
        navBarHeight: this.navBarHeight
      })
      ProactiveBanner({ statusBarHeight: this.statusBarHeight })
      // 手动长任务遮罩：盖住含官方标题栏在内的全部页面（标题栏返回键物理不可点，系统返回
      // 由宿主页拦截确认）；详见 BusyOverlay 头注释
      BusyOverlay()
      // 首启隐私同意闸（最顶层）：未同意时半模态蒙层挡下层一切命中（含标题栏与二级页），
      // 只能同意或退出；挂在最后（同意前不存在长任务场景，两层互不冲突）；口径见组件头注释
      PrivacyConsentGate()
    }
    .width('100%')
    .height('100%')
  }
}
