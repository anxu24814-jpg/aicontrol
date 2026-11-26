// 导航分发壳（2026-11-16 首页布局双形态笔瘦身为形态分发器，方案档 §2.2）：HdsNavigation
// 官方壳（标题栏/路由栈/分栏）+ 公共命令链（分享路由/启动落点判定/横幅直达/询问助手）留本件，
// 首页内容按 PREF_HOME_LAYOUT_KEY 热切两装——'tabs' 底栏页签壳（TabShell.ets，现状三页签
// 装配原样搬迁）/'drawer' 侧栏对话形态（DrawerMainArea.ets 主区 + DrawerSidePanel.ets 面板）。
// ★ 2026-11-18 侧栏二级页化笔（决明拍板「伪侧边栏实际二级页」，取代 2235 自绘抽屉壳）：
//   DrawerHost 自绘 Overlay / DrawerVisibility 显隐键 / Index 返回拦截整族退役——侧栏改为
//   真二级页 ROUTE_SIDE_PANEL_PAGE（DrawerSidePanel 页形态，全宽），汉堡键栈空时 push；
//   入场 = push 瞬显（animated=false——系统默认转场时长不可控且无结束信号，入场在途窗口
//   是点卡一帧漏态源）；退场 = 点卡瞬收 / 系统返回与返回键走官方动画（2235-b 二次校正起，
//   首版自定义转场 + SIDE_PANEL_SHIFT_KEY 渲染键已整条退役——自绘位移破坏标题栏避让且
//   非官方观感）。侧栏多选 + 删除域随页迁入
//   DrawerSidePanel，本件保留 tabs 形态多选镜像与命令链。
// ★ 2026-11-18 2235 自绘抽屉壳（历史沿革，现无任何代码面）：原生 SideBarContainer 整件退役，
//   改 DrawerHost 根 Stack 内容层 + 85% 面板层（直角满铺、整壳 translate）；DrawerHost 与
//   DrawerVisibility 均已随二级页化笔整件删除。下文 2026-11-17 各条中「SideBarContainer 受控
//   显隐 / $$ 原生回写 / 宽三锁 / 原生手势 / DrawerVisibility 显隐单源」均为历史沿革。
// ★ 2026-11-17 侧栏容器上根大改笔（决明「大改，先查清官方的，对齐」）：drawer 形态的
//   SideBarContainer(Overlay) 提到本件 build 根——两子 = 侧栏面板 + Stack{HdsNavigation 整壳
//   + 开态蒙层}，面板因此物理压在官方标题栏 stackBuilder 覆盖层（DrawerHomeTitleBar）之上，
//   「抽屉盖不住会话标题」的结构根因（侧栏住在 navBar 内容区、标题栏覆盖层永远在上）被消除。
//   官方依据 = HDS《设置overlay模式的侧边栏》示例把 HdsSideBar 挂页面根、内容区可为整页；
//   HdsSideBar contentAreaMask 默认 true 的蒙层语义由本件自绘蒙层承接（原生 SideBarContainer
//   Overlay 无蒙层参数）。HdsSideBar 本件两轮真机实证在 navBar 区不可用（2204 节），本笔不赌
//   根挂复活，继续用已实证可用的原生官方容器——结构对齐官方，组件沿用既有实证选型。
//   配套结构调整：①开态蒙层拦截并点击收抽屉（防标题栏右键/输入栏右端在开态仍可点）；
//   ②面板 push 前先收抽屉；③多选/删除域自 DrawerShell 迁入本件（跨 SideBarContainer 两侧
//   共享同一份状态）；④showSideBar 走 $$ 双向绑定（原生手势回写唯一通道）。
// ★ 2026-11-17 侧栏导航架构收敛笔（方案档 `docs/方案-侧栏导航架构收敛-20261117.md`）：
//   关闭态不再接受原生右滑开启（原生左滑开启通道整条退役，实现通道后由手感笔收窄为恒
//   false，见下条）。开启入口收窄为显式命令（汉堡键）后，2209～2211 为解决「原生开启手势与
//   二级页右滑返回同轴竞争」而叠加的整族补偿（返回抑制窗 / 内容区触点锁 / 导航锁 / push 后
//   冷却守卫 / 延迟回收 / 程序性写入标记 / navDepth 深度镜像）全部失去独立消费者，整族删除
//   （DrawerGate.ets 随之下线），不留休眠开关。现行不变量：①页面位置只看 NavPathStack
//   （`pathStack.size()` 实时判，不维护生命周期镜像）；②抽屉只在首页存在（栈非空不打开、
//   面板 push 先关闭、onNavBarStateChange 只做幂等关闭兜底）；③一个存储一个业务写入口
//   （DrawerVisibility.ets 持键 + 唯一 setter；2235 起无原生回写通道）；④不用固定毫秒数表达
//   导航正确性；⑤drawer 形态从二级位置打开会话 = 清回对话首页并展示目标会话
//   （revealConversation 单动作；tabs 形态 push 语义零改）。
// ★ 2026-11-17 侧栏入场动效笔（真机实验 A 结论先于施工：showSideBarWithGesture 恒 false 后
//   开 / 关 / 点蒙层 / 系统返回四通道仍全无动画 ⇒ Overlay + showControlButton(false) + 外部
//   赋值组合下，原生容器不提供可见显隐动画，应用侧无法调用）。故面板改自绘入场：DrawerPanelHost
//   挂 translate + @Watch 播一次 animateTo（280ms，与蒙层 transition 同参）。
//   **入场不动状态机**——sideBarShow 仍二值、setter 与 $$ 零改、无中间态、无动画结束回写。
//   ★ 2026-11-17「滑动收起也没有动画」笔改判：滑动收尾这一个入口补**滑出动画**——
//   closeDrawerBySwipe 先播 translate 到 -100%（200ms EaseIn），onFinish 才写 false；
//   显隐真值仍二值（不是「关闭中」第三态），在途只用一个非 UI 闩拦重复触发。其余关闭
//   入口（点蒙层 / 系统返回 / 程序性收）仍保持瞬时，语义与 2215 不变量不变。
// ★ 2026-11-17 侧栏收起手感修复笔（决明报「滑动收侧栏时阻力大有回弹 / 偶发收后蒙层仍在 /
//   入场未到位时终点处先有一条线」）：三处根因各自独立——①分割线 = 容器默认 divider 画在
//   侧栏右缘（与蒙层无关），宽 0 + 全透明退役；②阻力与回弹 = 原生 showSideBarWithGesture 的
//   100vp 阈值 + 跟手拖拽改宽度，叠加宽三锁 min=max=85%（越界阻尼、未过阈值回弹），且与
//   自绘 60vp 构成双判定 ⇒ 原生手势整条退役，关闭只留自绘左滑一条通道；③蒙层残留 = 关闭
//   方向面板瞬收而蒙层仍 200ms 淡出 ⇒ 改非对称转场（入场同参 / 退场 80ms）。
// ★ 2026-11-17 手感二修（决明「动画感觉更快了，能否往慢优化」+「偶发在有绘画处左滑收起面板，
//   收起的同时也切到了那条会话」）：①入场 200ms → **280ms**、曲线 Friction → **EaseInOut**
//   （Friction 前段速度高，200ms 下像「弹一下就到」；两端缓配 280ms 更从容），蒙层 appear 同参；
//   ②左滑判据的甩动分支加 **30vp 位移下限**——轻扫（位移与 tap slop 同量级、速度却已过甩动线）
//   会同时落进「行侧滑」与「行点击」两个窗口，表现为「收面板 + 切会话」；下限把甩动锁在行点击
//   必然失效的位移区间，两件事不再同帧发生。
// ★ 热切换（方案档 §2.1）：@StorageProp @Watch——键变即先复位抽屉态 + clear(false)
// 清导航栈回根 + 条件渲染重建壳（数据真源全在 RDB + AppStorage，重建重查即恢复；丢的只是
// 滚动位等临时态）；不重启（全项目偏好键零「需重启」先例）。
// ★ 窗口口径：全屏布局与 HDS 标题栏簇互为配套——沉浸标题栏与页签距底避让均以全屏窗口为
// 前提（全屏配方 = EntryAbility setWindowLayoutFullScreen + RESIZE_WITH_CARET）。距底
// 口径 = barBottomMargin 避让区高（坑1 的「非全屏 margin 0」口径作废）。
// 壁纸底座 = PageBackground 单实例常驻（TabShell 内；自定义背景写 AppStorage['pageBg']
// 全局跟随，默认官方灰底）。二级页铺底换装见 PageMapBuilder.ets。
// PageMap 域拆分：分支链在 PageMapBuilder.ets；设置域 push/搜索菜单在 HomeNavActions.ets；
// 挂载死规矩——navDestination 挂组件内 @Builder 方法（坑51），由它调 buildPageMap 注入
// pathStack/留白/档位/会话参数。页签域（currentTab 驱动的标题栏覆盖层/设置带联动/更多菜单）
// 留本件——两形态不同时在场，drawer 形态下该域零消费（标题栏走空标题档，主区 ChatPage 自绘）。
// ★ 2026-11-18 抽屉域拆分笔（2224 技术债务指令；方案档 §3——**历史沿革，DrawerHost 已于
//   2235 整件退役**）：该笔曾把抽屉装配域整域迁 DrawerHost.ets，本件保留形态分发与公共
//   命令链；现行装配直接在本件 build 的 NavHost 分支，多选业务域与删除确认链已随二级页化
//   迁入 DrawerSidePanel 页内自持（fresh 标记族与标题栏页签域仍在本件）。
import {
  BottomBuilderParams,
  HdsNavigation,
  HdsNavigationMenuContentOptions,
  HdsNavigationTitleMode,
  HideMode,
  TitleSize
} from '@kit.UIDesignKit';
import { ComponentContent } from '@kit.ArkUI';
import { CHAT_FAV_SEG_ITEMS, SESSION_MULTISELECT_CMD_KEY, SESSION_SELECT_COUNT_KEY, SESSION_SELECT_MODE_KEY } from '../chat/ChatSessionList';
// 预置标题播种（点卡进页首帧即两行标题态，2026-11-15 反馈二笔；协议与键见 ChatTitleMenuFactory）
import { seedTitlePreset } from '../chat/ChatTitleMenuFactory';
import { AssistantTitleBarKeys,
  ChatTabTitleBar, TabMoreMenuCallbacks,
  TabMoreMenuHost } from '../TabMoreMenu';
import {
  nextMessageId
} from '../../common/store/ChatDb';
import { ASSISTANT_CREATE_CMD_KEY } from '../assistants/AssistantPage';
import { buildPageMap } from './PageMapBuilder';
import { HomeNavActions } from './HomeNavActions';
import { PageBackground } from '../../common/PageBackground';
import { TabShell } from './TabShell';
import { DrawerMainArea } from './DrawerMainArea';
import { DrawerHomeTitleBar, SIDE_DRAWER_TOGGLE_CMD_KEY } from './DrawerHomeTitleBar';
import {
  ROUTE_CHAT_PAGE,
  ROUTE_SESSION_SEARCH_PAGE,
  ROUTE_SIDE_PANEL_PAGE
} from '../../common/RouteNames';
import {
  hdsTitleBarOptions,
  IMMERSIVE_LEVEL_KEY,
  segmentBandParams
} from '../../common/ImmersiveLevel';
import {
  HOME_LAYOUT_DRAWER,
  isHomeLayoutDrawer,
  isLaunchNewChatEnabled,
  PREF_HOME_LAYOUT_KEY,
  PREF_LAST_CONV_ID_KEY,
  PREF_LOADED_KEY
} from '../../common/AppPreferences';
import { resolveHomeLayout } from '../../common/AppPreferences';
import { isExpandedLayout, LAYOUT_SIZE_CLASS_KEY, SPLIT_NAV_BAR_MAX, SPLIT_NAV_BAR_MIN,
  SPLIT_NAV_BAR_WIDTH } from '../../common/LayoutProfile';
import { TITLE_BAR_MASK_EXTRA_HEIGHT, TITLE_BAR_MINI_HEIGHT } from '../../common/Theme';
import { nextSettingsBandHidden, SETTINGS_BAND_HIDE_OFFSET, SearchTopBand } from '../SearchTopBand';
import {
  CHAT_LAUNCH_HANDOFF_KEY,
  PENDING_SHARES_TICK_KEY,
  PENDING_SHARE_INCOMING_KEY,
  SESSION_LIST_RELOAD_KEY
} from '../../common/AppBroadcastKeys';
import { HelpCenterPage, CONSOLE_ASK_CMD_KEY } from '../settings/HelpCenterPage';
import { parseProactiveOpenCmd, PROACTIVE_OPEN_CMD_KEY } from '../../common/ProactiveGen';

// 页面底部留白（vp）：悬浮页签胶囊高约 56vp + 呼吸间距（页签壳装配随迁 TabShell，本值
// 留此供 pageBottomPad 算式——TabShell 收算好的 bottomPad）
const PAGE_BOTTOM_CLEARANCE: number = 80;

// （抽屉域常量族 DRAWER_OPEN_TOP_GAP / DRAWER_ENTER_MS / DRAWER_EXIT_MS /
// DRAWER_MASK_FADE_OUT_MS / DRAWER_CLOSE_* 与入场帧类 DrawerEnterFrame 曾随 2026-11-18
// 拆域笔整族迁 DrawerHost.ets；该件已于同日二级页化笔整件删除，常量与入场帧类均无现行
// 消费方）

// 分栏空栈右栏占位页（splitPlaceholder 只收 ComponentContent——全局 @Builder 包装）：
// 内容 = PageBackground 铺底，与左栏壁纸同图连续共享缓存；Stack 模式下挂载无效果零副作用。
// 不加占位文案（P2-4 克制）
@Builder
function splitPlaceholderView() {
  Stack() {
    PageBackground()
  }
  .width('100%')
  .height('100%')
}

// （页签配置函数族 tabSymbol/chatTabBar/assistantTabBar/settingsTabBar/newTabBar 与
// TAB_BAR_KEY_* / NEW_TAB_ITEM_INDEX 常量已随页签壳装配整族迁 TabShell.ets——2026-11-16
// 首页布局双形态笔域级最小拆分，方法体原样搬迁零行为变化）

@Component
export struct HomeNavigation {
  // 系统避让区高度（vp，Index 异步实测下发）。★ 必须 @Prop（坑57 同族）：状态驱动重渲染
  // 才能把后到的异步真值送进各留白
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  // 当前页签（0=助手，1=对话，2=设置）：启动直达对话页 = 初始 1（换序只动位置不动启动页）；
  // onChange 回写唯一事实源。'tabItem' 档第四项（下标 3）是动作位不承载页面，由
  // onContentWillChange 拦截切页，永不入本状态（标题栏/菜单按 0/1/2 分支零改动）
  @State currentTab: number = 1;
  // 「对话」页签「全部/收藏」分段选中：与 ChatSessionList 共用同一份状态（实例化传
  // $chatFavSegment）；承载位 = 标题栏覆盖层中央（ChatTabTitleBar 的 @Link 位）
  @State private chatFavSegment: number = 0;
  // ★ 首页布局形态（2026-11-16 双形态笔）：'tabs' 底栏页签（默认）/ 'drawer' 侧栏对话形态
  //——分发判据 + 热切回根（@Watch：键变即 clear(false) 清导航栈回根，条件渲染重建壳即新
  // 形态生效；方案档 §2.1/§3.9）。@StorageProp 首帧初始化不触发 @Watch（且冷启动栈本空，
  // clear 幂等无害）
  @StorageProp(PREF_HOME_LAYOUT_KEY) @Watch('onHomeLayoutChanged') homeLayout: string = 'tabs';
  // （页签切换动画 tabSwitchAnim 与快捷新建键 newSessionEntry 两 @StorageProp 已随页签壳
  // 装配迁 TabShell.ets——消费面全在该件；drawer 形态下页签壳不在场零消费）
  // 沉浸光感档位（AppStorage 单键；EntryAbility 恒置强档 IMMERSIVE_LEVEL_FIXED——本
  // @StorageProp 缺省 0 仅键未注册时兜底）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 官方路由栈：会话卡片 push 对话页（系统级转场 + 侧滑/返回键自动 pop）
  private pathStack: NavPathStack = new NavPathStack();
  // 设置域导航动作（push 编排 + 搜索菜单——域拆至 HomeNavActions）
  private actions: HomeNavActions = new HomeNavActions(this.pathStack);
  // 进入对话页的目标会话（卡片点击时记录，PageMap 构造 ChatPage 消费；会话标题由对话页
  // 自包壳按 id 查询）
  @State private activeConvId: string = '';
  // 最近一次本地新造会话 id（2026-11-18 乐观空态笔）：与 activeConvId 同源比对得出
  // freshSession；写入 = 全部 nextMessageId('conv') 处，清除 = openSession 与形态热切
  //（不清则「新建→发消息→退出→点卡回来」先闪一帧空态）。用 id 而非布尔 = 漏清不永久误判
  @State private freshConvId: string = '';
  // ── 侧栏页域（2026-11-18 二级页化笔：显隐键/多选域/删除链整族迁 DrawerSidePanel 页内
  // 自持，本件只留「汉堡命令消费 + 转场 delegate + 删除命中主区换轨上行承接」）──
  // 开侧栏页命令回执（DrawerHomeTitleBar 汉堡键 → 命令键下行；@Watch 只在变化时触发，
  // 计数器初值 0 不触发）：栈空时 push 侧栏页——页面位置只看 NavPathStack 实时判
  //（二级页在场汉堡键被盖住不可点，本判据是第二道防线）
  @StorageProp(SIDE_DRAWER_TOGGLE_CMD_KEY) @Watch('onDrawerToggleCmd') drawerToggleCmd: number = 0;
  // 会话列表多选中（ChatSessionList 广播——多选中收起页签避免与批量条重叠：HdsTabs
  // barBottomMargin 巨值推出视口）
  @StorageProp(SESSION_SELECT_MODE_KEY) sessionSelectMode: boolean = false;
  // 会话多选已选计数（多选中主标题「已选 N 项」的 N；tabTitle 消费）
  @StorageProp(SESSION_SELECT_COUNT_KEY) sessionSelectCount: number = 0;
  // 「询问助手」指令（HelpCenterPage 内置卡触发；首帧初始 0 不触发 @Watch）
  @StorageProp(CONSOLE_ASK_CMD_KEY) @Watch('onConsoleAskCmd') consoleAskCmd: number = 0;
  // 横幅点击直达会话命令（ProactiveBanner 下发——值 = convId + '#' + 自增序号，命令键同族
  // @StorageProp @Watch 消费范式；首帧初始 '' 不触发）
  @StorageProp(PROACTIVE_OPEN_CMD_KEY) @Watch('onProactiveOpenCmd') proactiveOpenCmd: string = '';
  // 「对话」页签更多菜单节点宿主（init/open/dispose 成对见 TabMoreMenu.ets 注释）
  private tabMoreMenu: TabMoreMenuHost = new TabMoreMenuHost();
  // 设置页签滚动联动三件（带内假框 ⇄ 右上角键互斥，2026-11-02 笔）：
  // settingsScroller = 设置页 Scroll 控制器（构造传 SettingsPage 挂 Scroll(controller)，
  // 本壳 .bindToScrollable 绑定作官方滚动感知来源——dynamicHideTitleBar 依赖）；
  // settingsBandHidden = 带收起态（false = 带在、页面顶部、无右上键 / true = 带收起、右上
  // 搜索键出现），唯一写点 = onSettingsScrollOffset 状态机（48 收 / 24 复位滞后带）；
  // settingsBandKeyword = 哑位词（带内假框不可输入不绑词，传 $settingsBandKeyword 仅满足
  // SearchTopBand @Link 必传契约，恒空不消费）
  private settingsScroller: Scroller = new Scroller();
  @State settingsBandHidden: boolean = false;
  @State settingsBandKeyword: string = '';
  // 断点档位（Index.ets 窗口实测下发；缺省 0 = COMPACT——断点不持久，口径见 LayoutProfile）
  @StorageProp(LAYOUT_SIZE_CLASS_KEY) layoutSizeClass: number = 0;
  // 分栏空栈右栏占位内容（aboutToAppear 构造 / aboutToDisappear dispose 成对——内存红线；
  // build 恒晚于 aboutToAppear，属性链处非空不变量成立）
  private splitContent: ComponentContent<Object> | null = null;

  // 偏好键就绪信号（EntryAbility 注册完全部 persistProp 后置 1）。★ 不赌「本组件与注册
  // 谁先谁后」时序（loadContent 回调执行上下文不明确）——两路径都收敛到
  // tryEnterLaunchConversation（风险说明见 AppPreferences.PREF_LOADED_KEY）
  @StorageProp(PREF_LOADED_KEY) @Watch('onPrefsLoaded') prefsLoaded: number = 0;
  // 启动进入判定一次性消费标记：进程内只判定一次——用户运行期改开关不触发（切换下次启动生效）
  private launchConsumed: boolean = false;
  // 分享路由 tick 订阅：EntryAbility 解析到分享/打开方式待发件后自增——本壳订阅并路由
  // 新建会话页（拍板：分享落点恒新建会话，已在会话页再分享 = 再叠一页新会话）；见
  // maybeRoutePendingShares
  @StorageProp(PENDING_SHARES_TICK_KEY) @Watch('onPendingSharesTick') pendingSharesTick: number = 0;
  // 已路由的分享 tick（进程内去重——@Watch 后到路径与 aboutToAppear 就绪路径共用）
  private routedShareTick: number = 0;

  aboutToAppear(): void {
    // 更多菜单节点首次构建（getUIContext 需组件就绪；与 aboutToDisappear dispose 成对）
    this.tabMoreMenu.init(this.getUIContext(), this.tabMenuCallbacks());
    // 分栏占位内容构造（与 aboutToDisappear dispose 成对）
    this.splitContent = new ComponentContent<Object>(this.getUIContext(),
      wrapBuilder(splitPlaceholderView));
    // 分享拉起路由（两路径收敛：tick 已在 AppStorage 的冷启动走这里，后到路径见
    // onPendingSharesTick）——先于启动进入判定（让位语义在判定内）
    this.maybeRoutePendingShares();
    // 冷启动默认进入新对话判定（就绪信号已在场路径走这里，后到路径见 onPrefsLoaded）
    this.tryEnterLaunchConversation();
  }

  // 就绪信号到达（注册后到路径）：补做启动进入判定
  private onPrefsLoaded(): void {
    this.tryEnterLaunchConversation();
  }

  // ★ 热切回根（方案档 §3.9，双形态笔）：偏好键变化（「偏好与外观」开关拨动）——先清导航
  // 栈回根（clear(false) 关转场——正在二级页切形态 = 切完看到新形态首页，可预期），条件渲染
  // 分支随 homeLayout 值切换重建壳即新形态生效。丢临时态（滚动位/侧栏开合/导航栈）——极低频
  // 操作可接受（方案档 §2.1）；NavPathStack.clear 官方 API（d.ts @since 10，清空栈内全部
  // 页面回 navBar 首页）
  private onHomeLayoutChanged(): void {
    // 新造标记随旧形态作废（热切后主区/路由页会重建，旧标记不再对应任何在场页面）；
    // 侧栏页随 clear 弹出（其 aboutToDisappear 自收口：转场键复位 + 多选广播撤销）
    this.clearFreshConversation();
    this.pathStack.clear(false);
  }

  // ── 侧栏页域方法（2026-11-18 二级页化笔：原抽屉域十二法整族退役，多选/删除链随页迁出，
  // 本件只留三法——命令消费 / 转场 delegate / 删除命中换轨承接）──
  // 汉堡命令消费：栈空（首页位）才开侧栏页——页面位置只看 NavPathStack 实时 size
  //（二级页在场时汉堡键本就被盖住，本判据是第二道防线；push animated = false 瞬显——
  // 系统默认转场时长不可控且无结束信号，入场在途窗口是点卡一帧漏态源）
  private onDrawerToggleCmd(): void {
    if (this.pathStack.size() > 0) {
      return;
    }
    this.pathStack.pushPathByName(ROUTE_SIDE_PANEL_PAGE, null, false);
  }

  // 删除命中主区会话承接（侧栏页删除链上行）：主区换本地新造会话态（markFreshConversation
  // + activeConvId，被删会话不可常驻主区）——不清栈不弹页，侧栏页留守继续操作列表；
  // 主区宿主常驻 navBar，activeConvId 先落定即消费（revealConversation 同理）
  private onActiveSessionDeleted(freshId: string): void {
    this.markFreshConversation(freshId);
    this.activeConvId = freshId;
  }

  // （侧栏页自绘左向转场已随 2026-11-18 二次校正笔退役：customNavContentTransition 的位移
  // 通道须在页面根挂 translate，真机实证会破坏标题栏避让（两排带压进状态栏）且动画非官方
  // 观感；现侧栏页 = 完全正常的二级页，入场 = push 瞬显（animated=false），关闭 = 点卡
  // 瞬收（clear(false)）/ 返回键 / 系统返回手势走官方动画）

  // 分发判据（build 分支与标题栏档位共用；归一防脏值）
  private isDrawerMode(): boolean {
    return resolveHomeLayout(this.homeLayout) === HOME_LAYOUT_DRAWER;
  }

  // 分享 tick 到达（@Watch 后到路径）：补做分享路由
  private onPendingSharesTick(): void {
    this.maybeRoutePendingShares();
  }

  // 分享拉起路由（两路径共用）：每个未路由过的新 tick 恒落**新建会话**（拍板：分享落点恒新
  // 建会话）。tabs 形态 = push 新建会话页（push 参数 = tick，会话页按 shareTick 匹配桥批次
  // 消费）；drawer 形态 = 主区换新会话 id（shareTick 经 DrawerMainArea 构造时现读，
  // key 重建构造时携带——消费链同为 AttachmentPickCtrl.consumePendingShareInto）；lazy
  // 创建语义两形态同（首条消息才落库）；tick 去重：@Watch 与 aboutToAppear 两路径 +
  // 同值重复 set 均不重路由
  private maybeRoutePendingShares(): void {
    const tick: number = AppStorage.get<number>(PENDING_SHARES_TICK_KEY) ?? 0;
    if (tick === 0 || tick === this.routedShareTick) {
      return;
    }
    this.routedShareTick = tick;
    const newId: string = nextMessageId('conv');
    // 分享落点同为本地新造会话（两形态同源标记——drawer 主区 / tabs 路由页都据此先行空态）
    this.markFreshConversation(newId);
    if (isHomeLayoutDrawer()) {
      // drawer 形态：分享落点 = 回首页新会话（任意二级页拉起同语义，方案档 §2.5）
      this.revealConversation(newId);
      return;
    }
    this.activeConvId = newId;
    this.pathStack.pushPathByName(ROUTE_CHAT_PAGE, tick, false);
  }

  // 本地新造会话标记写入（2026-11-18 乐观空态笔）：只许接在 nextMessageId('conv') 之后
  private markFreshConversation(conversationId: string): void {
    this.freshConvId = conversationId;
  }

  // 本地新造会话标记清除（打开已有会话 / 形态热切两路共用）
  private clearFreshConversation(): void {
    this.freshConvId = '';
  }

  // 启动进入判定（两路径共用，一次性）：tabs 形态开关开启时 push 懒创建新会话（aboutToAppear
  // 路径下本方法早于 build，pathStack 已带一条记录，导航组件首次构建即渲染该 NavDestination
  //——官方 FAQ faqs-arkui-1018 同款姿势；animated=false 关转场）；drawer 形态主区常驻——
  // 开 = 主区落新会话态、关 = 落上次会话（PREF_LAST_CONV_ID_KEY，空/已删兜底新会话态——
  // 已删 id 进 ChatPage = 无行会话语义，首条消息建行复活，方案档 §4.1-8）。后台回前台不重建
  // 组件 = 不重复进新对话。★ 分享冷启动让位（分享落点同为新建会话，本判定让位防双推）：
  // ①桥 tick 已在场 = 分享即将由 maybeRoutePendingShares 路由；②tick 未到但拉起原因已在场
  //（PENDING_SHARE_INCOMING——getSharedData 异步返回晚于本判定）。两者任一在即一次性消费
  // 本判定（解析失败无 tick 时本次落回主页/主区新会话态）
  private tryEnterLaunchConversation(): void {
    if (this.launchConsumed) {
      return;
    }
    if ((AppStorage.get<number>(PENDING_SHARES_TICK_KEY) ?? 0) > 0 ||
      AppStorage.get<boolean>(PENDING_SHARE_INCOMING_KEY) === true) {
      this.launchConsumed = true;
      return;
    }
    if (isHomeLayoutDrawer()) {
      // drawer 主区落点（一次性）：新对话偏好开 = 新会话态；关 = 上次会话（空兜底新会话态）
      this.launchConsumed = true;
      // 启动落点 = 主区会话页（三种子分支同）：置一次性衔接标记，会话页首帧即画启动页图标
      // （DB 初始化/读库窗口不再纯背景；消费点 = ChatPageLifecycle.enter，读后清）
      AppStorage.setOrCreate<boolean>(CHAT_LAUNCH_HANDOFF_KEY, true);
      if (isLaunchNewChatEnabled()) {
        const freshStartId: string = nextMessageId('conv');
        this.markFreshConversation(freshStartId);
        this.activeConvId = freshStartId;
        return;
      }
      const lastConvId: string = AppStorage.get<string>(PREF_LAST_CONV_ID_KEY) ?? '';
      if (lastConvId !== '') {
        this.activeConvId = lastConvId;
        return;
      }
      // 无落点（首装 / 落点已清空）= 兜底新会话态，同属本地新造——空态可先行
      const freshFallbackId: string = nextMessageId('conv');
      this.markFreshConversation(freshFallbackId);
      this.activeConvId = freshFallbackId;
      return;
    }
    if (!isLaunchNewChatEnabled()) {
      return;
    }
    this.launchConsumed = true;
    // 启动落点 = push 的新会话页：置一次性衔接标记（同上，消费点 = ChatPageLifecycle.enter）
    AppStorage.setOrCreate<boolean>(CHAT_LAUNCH_HANDOFF_KEY, true);
    this.pushNewConversation(false);
  }

  aboutToDisappear(): void {
    // 更多菜单节点释放（与 aboutToAppear init 成对）
    this.tabMoreMenu.dispose();
    // 分栏占位内容释放（与 aboutToAppear 构造成对）
    this.splitContent?.dispose();
    this.splitContent = null;
  }

  // 滚动内容顶部留白（vp）：内容区从窗口顶延伸到标题栏背后（渐变模糊蒙层透出滚动内容），
  // 留白使首卡静止时完整落在蒙层下方
  private titleBarInset(): number {
    return this.statusBarHeight + TITLE_BAR_MINI_HEIGHT + TITLE_BAR_MASK_EXTRA_HEIGHT;
  }

  // 页面底部留白（vp）：悬浮页签让位（胶囊高 + 呼吸 + 底部避让区）
  private pageBottomPad(): number {
    return this.navBarHeight + PAGE_BOTTOM_CLEARANCE;
  }

  // 页签标题（唯一事实源 = currentTab）：会话多选中主标题改「已选 N 项」（计数显示由标题
  // 承担，决明拍板不加右上两键，批量动作仍在底部条）；多选态只存在于对话页签（页签已收起
  // 不可切），退出即恢复页签名
  private tabTitle(): string {
    if (this.sessionSelectMode) {
      return '已选 ' + this.sessionSelectCount + ' 项';
    }
    return this.currentTab === 0 ? '助手' : this.currentTab === 1 ? '对话' : '设置';
  }

  // 点会话卡片（两形态共同入口：面板点行 / 搜索页点卡 / 主动消息横幅 / 询问助手 /
  // 分享拉起）：
  // · tabs 形态 = 记目标会话 + 官方路由 push（现状零改）
  // · drawer 形态 = revealConversation（回对话首页并展示目标会话）——二级位置（搜索页 /
  //   设置页横幅等）打开会话时清栈回首页，不再「主区已切、用户仍停在搜索页」（方案档 §2.5）
  // presetTitle = 点卡行标题（列表/搜索页在手，异步反查永远晚于首帧——播种后 ChatPage
  // 首帧即两行态，两形态同链）
  // freshSession = 目标 id 是否本地新造（询问助手等"边走 openSession 边新建"的入口传 true；
  // 缺省 false = 打开已有会话，清新造标记——两态互斥单源在此，调用方不得自写标记）
  // writeLaunchPoint = 是否写「上次会话」启动落点键（★ 2026-11-18 待拍板 2 收口，决明拍板
  // 「落点键按你的」：缺省 true = 点卡/搜索/横幅全链照记；询问助手传 false——它开的是懒创建
  // 会话（首条消息才落库），落点键若被它覆写，冷启动「上次会话」会指向一个可能永远无行的
  // conv id，落点语义被冲淡；2216 P2 登记的「询问助手半边」两分口径就此归一）
  private openSession(conversationId: string, presetTitle?: string,
    freshSession: boolean = false, writeLaunchPoint: boolean = true): void {
    if (freshSession) {
      this.markFreshConversation(conversationId);
    } else {
      // 打开的是已有会话（点卡/搜索/横幅全汇于此）——新造标记必须清，
      // 否则「新建→发消息→退出→点卡回来」会先闪一帧空态（2026-11-18 乐观空态笔）
      this.clearFreshConversation();
    }
    if (isHomeLayoutDrawer()) {
      // 记「上次会话」启动落点键（点卡 / 搜索 / 横幅同链，与原 DrawerShell 口径一致；
      // 询问助手显式传 false 免写——见 writeLaunchPoint 形参注释）
      if (writeLaunchPoint) {
        AppStorage.setOrCreate<string>(PREF_LAST_CONV_ID_KEY, conversationId);
      }
      this.revealConversation(conversationId, presetTitle);
      return;
    }
    seedTitlePreset(conversationId, presetTitle);
    this.activeConvId = conversationId;
    this.pathStack.pushPathByName(ROUTE_CHAT_PAGE, null);
  }

  // drawer 形态唯一会话 reveal 动作（方案档 §2.5）：目标 id 播种 + 主区换轨 + 收抽屉 +
  // 栈非空清回对话首页。清栈是「用户选择会话」的有意行为（只限 drawer 形态；tabs 的 push
  // 与返回栈不动）。首页首帧即消费目标 id：activeConvId 先落定，主区宿主常驻 navBar
  // （清栈不销毁 DrawerMainArea），@Watch 已翻双交替分支。不写数据库——无行会话首条消息
  // 才建行（懒创建语义不变）
  private revealConversation(conversationId: string, presetTitle?: string): void {
    seedTitlePreset(conversationId, presetTitle);
    this.activeConvId = conversationId;
    // 侧栏页二级页化后：清栈即弹页（瞬时收口，无出场动画——与原「点行瞬收抽屉」同语义；
    // 页面 aboutToDisappear 自收转场键复位与多选广播）
    if (this.pathStack.size() > 0) {
      this.pathStack.clear(false);
    }
  }

  // 「对话」页签新建会话（入口 = 「更多」菜单首项 / 页签栏旁圆键 / 列表顶部新会话草稿行，
  // 三处同此法）：懒创建语义——本地生成会话 id 走 push 既有链路，不落库（首条消息发送时
  // ChatDb 才建行）；多选中忽略（批量条占位 + 新建语义冲突）
  private newConversation(): void {
    if (this.sessionSelectMode) {
      return;
    }
    if (isHomeLayoutDrawer()) {
      // drawer 形态：reveal 回首页新会话态（懒创建，首条消息才落库）+ 收抽屉；多选守卫同上
      //（批量语义优先）。不写「上次会话」键——新建会话不改变冷启动落点语义
      const freshId: string = nextMessageId('conv');
      this.markFreshConversation(freshId);
      this.revealConversation(freshId);
      return;
    }
    this.pushNewConversation(true);
  }

  // 懒创建新会话并进入（菜单项与冷启动默认进入两处共用）：本地生成会话 id + push 对话页，
  // 不落库；助手归属 = 当前助手（ACTIVE_ASSISTANT_KEY，无行兜底）；animated = false 用于
  // 冷启动首帧（无推入转场动画）
  private pushNewConversation(animated: boolean): void {
    const freshId: string = nextMessageId('conv');
    this.markFreshConversation(freshId);
    this.activeConvId = freshId;
    this.pathStack.pushPathByName(ROUTE_CHAT_PAGE, null, animated);
  }

  // 「对话」页签标题栏搜索键：push 独立二级搜索页 SessionSearchPage（同设置搜索形态）；
  // 多选中忽略守卫（newConversation 同款）
  private newSessionSearch(): void {
    if (this.sessionSelectMode) {
      return;
    }
    this.pathStack.pushPathByName(ROUTE_SESSION_SEARCH_PAGE, null);
  }

  // 设置页签滚动偏移状态机（SettingsPage.onDidScroll 上抛 yOffset）：阈值与滞后带判据
  // 单源 = SearchTopBand.nextSettingsBandHidden（侧栏设置二级页同函数同判据）；只在变化时
  // 写 @State（onDidScroll 高频回调，重复写同值状态触发无意义重渲染——性能红线）
  private onSettingsScrollOffset(offsetY: number): void {
    const next: boolean = nextSettingsBandHidden(offsetY, this.settingsBandHidden);
    if (next !== this.settingsBandHidden) {
      this.settingsBandHidden = next;
    }
  }

  // 设置页签标题栏下方带参数：带在（设置页签 + 未收带）⇒ 假框带（hdsTitleBarOptions 第 7 参
  // bottomBuilder）；其余 undefined = 不写该区。算式单源 = ImmersiveLevel.segmentBandParams
  //（下移 8 + 内容高 40 ⇒ 带高 48）；builder 用箭头包装组件内 @Builder（坑30 死规矩同
  // tabTitleBarStack——this 绑定组件实例，全局化即闪退）
  private settingsBandParams(): BottomBuilderParams | undefined {
    if (this.currentTab !== 2 || this.settingsBandHidden) {
      return undefined;
    }
    return segmentBandParams((): void => {
      this.SettingsSearchBand();
    });
  }

  // 「询问助手」（改指当前助手——决明拍板保留通道但不再归属控制台〔已退役〕）：懒创建新
  // 会话 push（不落库、不写任何覆盖标记），聊天页加载链走 effectiveAssistantId 兜底 =
  // 当前助手 ?? 默认助手，首条消息落行时写入会话行。多选中忽略（newConversation 同守卫）
  private onConsoleAskCmd(): void {
    if (this.sessionSelectMode) {
      return;
    }
    const convId: string = nextMessageId('conv');
    this.getUIContext().getPromptAction().showToast({ message: '已开新会话，归属当前助手' });
    // 询问助手 = 新建会话（走 openSession 是为了统一 drawer 收抽屉 / tabs 落链），
    // 第三参显式声明"本地新造"——空态可先行（2026-11-18 乐观空态笔）；第四参 false =
    // 懒创建会话不写启动落点键（★ 2026-11-18 待拍板 2 收口：原注释「记落点」半边与
    // 「新建不改落点语义」口径冲突，拍板归一为不记——newConversation 同判）
    this.openSession(convId, undefined, true, false);
  }

  // 横幅直达会话（ProactiveBanner 点击 → PROACTIVE_OPEN_CMD_KEY）：解析会话 id 走
  // openSession 直达（与点会话卡片同链路）；多选中忽略；空命令（脏值）不导航
  private onProactiveOpenCmd(): void {
    if (this.sessionSelectMode) {
      return;
    }
    const convId: string = parseProactiveOpenCmd(this.proactiveOpenCmd);
    if (convId !== '') {
      this.openSession(convId);
    }
  }

  // 「助手」页签标题栏「＋」新建：经一次性指令计数器下发（菜单域无法直达 TabContent 内
  // 组件——AssistantPage @StorageProp @Watch 消费弹名称对话框，坑3 口径；确认 insert +
  // reload 全在 AssistantPage 内）
  private newAssistant(): void {
    AppStorage.setOrCreate<number>(ASSISTANT_CREATE_CMD_KEY,
      (AppStorage.get<number>(ASSISTANT_CREATE_CMD_KEY) ?? 0) + 1);
  }

  // （排序写点沿革：本页 → 偏好设置页 → 现唯一写点 PrefSessionReadPage 排序分段卡，本页
  // 零排序面，真链路见该页成员注释）

  // 「对话」页签更多菜单回调（init/open 两处共用；「多选」经 AppStorage 一次性指令计数器
  // 下发 ChatSessionList（@StorageProp @Watch 消费——多层宿主链零透传，坑3 口径）。后续加
  // 菜单项 = TabMoreMenu 接口加字段 + 本处加回调）
  private tabMenuCallbacks(): TabMoreMenuCallbacks {
    return {
      // 新建会话（菜单首项）——直通 newConversation（多选守卫在方法内），懒创建语义与
      // 页签栏圆键、列表草稿行同链
      onNew: (): void => {
        this.newConversation();
      },
      // 搜索会话（第二项）——直通 newSessionSearch，二级页契约零改动
      onSearch: (): void => {
        this.newSessionSearch();
      },
      onMultiselect: (): void => {
        AppStorage.setOrCreate<number>(SESSION_MULTISELECT_CMD_KEY,
          (AppStorage.get<number>(SESSION_MULTISELECT_CMD_KEY) ?? 0) + 1);
      }
    };
  }

  // 「对话」页签更多菜单弹出：标题栏按钮 action 触发，节点宿主每次弹出前重建（深浅色/材质安全）
  private openTabMoreMenu(): void {
    this.tabMoreMenu.open(this.getUIContext(), this.tabMenuCallbacks(),
      this.immersiveLevel);
  }

  // （「助手」页签更多菜单域整域退役：排序改助手页列表原位长按拖拽后菜单再无项 ⇒ 回调/
  // 宿主/弹出方法三处随 ⋯ 键一并删除；标题栏覆盖层见 AssistantTitleBarOverlay——现单键）

  // 页签标题栏菜单（HDS 主路径）：助手 = 不传（单键迁标题栏覆盖层 AssistantTitleBarKeys）/
  // 对话 = 不传（中央分段 + 右端单键〔⋯更多〕迁标题栏覆盖层 ChatTabTitleBar 组件）/
  // 设置 = 搜索键（★ 与带内假框互斥——带在时顶部搜索入口 = 标题栏下方假框（settingsBandParams
  // 承载），右上角无键；带收起（settingsBandHidden）后键出现。两入口点击都直达同一二级搜索页）
  private tabMenusHds(): HdsNavigationMenuContentOptions | undefined {
    if (this.currentTab === 0 || this.currentTab === 1) {
      return undefined;
    }
    if (!this.settingsBandHidden) {
      return undefined;
    }
    return this.actions.settingsSearchMenu();
  }

  // 本页签是否有标题栏自绘键覆盖层（助手 0 / 对话 1 两页签有，设置页签无——用官方搜索键；
  // 覆盖层下的主标题须保留，见下方 titleBar 两参）
  private hasTitleOverlay(): boolean {
    return this.currentTab === 0 || this.currentTab === 1;
  }

  // 「对话」页签标题栏覆盖层（组件内 @Builder 挂载——★ 死规矩：覆盖层必须是组件形态，
  // 禁做成全局 @Builder：HDS 的 titleBar napi 直接调用 stackBuilder 时无视图上下文，
  // 全局 @Builder 的 this 为 undefined → 启动即闪退「Cannot read property
  // observeComponentCreation2 of undefined」（2026-09-09 真机实锤，栈见 ChatTabTitleBar
  // 头注释）；组件内 @Builder 编译为类方法、this 恒有绑定）。
  // items 单源直传（本组件已 import CHAT_FAV_SEG_ITEMS，标题栏域件不反向依赖会话列表域）、
  // selectedIndex 与 ChatSessionList 共用同一份 @State（$chatFavSegment 同传，违例 = 两处
  // 各显各的段）、showSegment 多选态归 false（标题切「已选 N 项」，中央须让位）；覆盖层只余
  // onMore 一枚回调（〔⋯更多〕单圆键，新建/搜索收入 ⋯ 菜单）
  @Builder
  ChatTabTitleBarOverlay() {
    ChatTabTitleBar({
      immersiveLevel: this.immersiveLevel,
      items: CHAT_FAV_SEG_ITEMS,
      selectedIndex: $chatFavSegment,
      showSegment: !this.sessionSelectMode,
      onMore: (): void => {
        this.openTabMoreMenu();
      }
    })
  }

  // 「助手」页签标题栏覆盖层（挂载死规矩同上条——必须是组件 + 组件内 @Builder 挂载，
  // 禁全局 @Builder）
  @Builder
  AssistantTitleBarOverlay() {
    AssistantTitleBarKeys({
      immersiveLevel: this.immersiveLevel,
      // 「＋」动作走指令键下发 AssistantPage 弹名称对话框；onMore 已随助手更多菜单域退役，
      // 本栏单键
      onAdd: (): void => {
        this.newAssistant();
      }
    })
  }

  // 页签标题栏覆盖层构造器（档位与回调经组件参数注入——档位读取发生在标题栏构建期，
  // 光感档位变化自动重建）。
  // ★ 内层页签守卫：覆盖层只在助手/对话两页签出键——builder 每次执行都现读页签，切走即
  // 内容为空。真机实测 = 官方在 stackBuilder 传 undefined 时**会清除**既有覆盖层（切页签后
  // 官方单键恢复）；守卫保留为第二道防线（该行为官方未文档化，版本升级若变语义可自愈）
  private tabTitleBarStack(): CustomBuilder {
    return (): void => {
      if (this.currentTab === 1) {
        this.ChatTabTitleBarOverlay();
      } else if (this.currentTab === 0) {
        this.AssistantTitleBarOverlay();
      }
    };
  }

  // 侧栏形态标题栏覆盖层构造器（drawer 分支 stackBuilder——装配死规矩同 tabTitleBarStack：
  // 组件内 @Builder，坑30）。覆盖层本体 = DrawerHomeTitleBar（广播/命令桥自持——思考态镜像
  // 键双向、开抽屉/开模型/开更多三条命令键下行 HomeNavigation/ChatPage 消费；2026-11-17
  // 侧栏形态对齐二级对话页笔：主区标题栏自「蒙层下缘自绘行」上收官方 stackBuilder 插槽，
  // 键回官方生效区出材质光圈。★ 上根大改笔后面板开态盖住本覆盖层，汉堡键只在合态可见）
  private drawerTitleBarStack(): CustomBuilder {
    return (): void => {
      this.DrawerTitleBarOverlay();
    };
  }

  @Builder
  DrawerTitleBarOverlay() {
    DrawerHomeTitleBar()
  }

  // （「对话」页签标题栏下方带整条取消——原 ChatFavBand 带唯一用途就是承载「全部/收藏」
  // 分段，分段迁入标题栏覆盖层后带内无内容。连带 = titleBar 恢复 7 参、列表首卡让位由
  // 48 收到 8（见 ChatSessionRows topClearance）。将来若要在带里再放
  // 东西，按 PageShell titleBarBottom 契约重接即可（壳能力未删）。

  // （底部页签迷你栏「新建会话」圆键 @Builder TabBarNewConversationKey 已随页签壳装配
  // 迁 TabShell.ets——动作改经 onNewConversation 回调上行本件 newConversation，链路不变）

  // 设置页签标题栏下方带（openOnly 假框档，经 settingsBandParams 交 hdsTitleBarOptions
  // 第 7 参 bottomBuilder）：页面在顶部时搜索入口呈带内假框（整框点击直达搜索二级页）；
  // 下滑过 48vp 官方动效收带（dynamicHideTitleBar）+ 右上角搜索键出现（menu 互斥见
  // tabMenusHds）。@Builder 挂载死规矩同 ChatTabTitleBarOverlay（坑30：必须是组件内
  // @Builder——builder 经官方 napi 直接调用，全局化即 this undefined 闪退）。
  // settingsBandKeyword = 哑位词（假框不可输入，仅满足 SearchTopBand @Link 必传契约）
  @Builder
  SettingsSearchBand() {
    SearchTopBand({
      keyword: $settingsBandKeyword,
      openOnly: true,
      placeholder: '搜索设置项',
      onOpen: (): void => {
        this.actions.pushSearch();
      }
    })
  }

  // 二级页路由表（官方 navDestination builder；★ 坑51 死规矩：必须挂组件内 @Builder
  // 方法——lambda 直挂全局 @Builder 真机白屏）。分支链已迁 PageMapBuilder.ets（见该文件头
  // 注释）；本方法只负责注入 pathStack/留白/会话参数与打开会话编排回调（捕获 this 合法，
  // 坑51 只禁 lambda 直挂 navDestination）——标题栏档位材质由各页 PageShell 内部
  // @StorageProp 自订阅，不经本链透传
  @Builder
  PageMap(name: string, param: Object) {
    buildPageMap(name, param, this.pathStack, this.titleBarInset(), this.navBarHeight,
      this.activeConvId, this.freshConvId, (conversationId: string, presetTitle?: string): void => {
        this.openSession(conversationId, presetTitle);
      }, (): void => {
        this.newConversation();
      }, (freshId: string): void => {
        this.onActiveSessionDeleted(freshId);
      })
  }

  // （@Builder DrawerPanelHost / DrawerContentHost 两侧子装配曾随 2026-11-18 拆域笔整域迁
  // DrawerHost.ets；该件已随同日二级页化笔整件删除——现无面板装配，NavHost 直接在本件
  // build 挂载，侧栏为路由压栈的 DrawerSidePanel 页）

  // HdsNavigation 官方壳（drawer 形态 = 被侧栏容器包住的整页内容；tabs 形态 = 页面根）
  @Builder
  NavHost() {
    HdsNavigation(this.pathStack) {
      // ★ 形态分发区（双形态笔，方案档 §2.2）：navBar 区两种装法——TabShell（底栏页签壳，
      // 现状装配原样搬迁）或 DrawerMainArea（侧栏对话形态主区：ChatPage 常驻 + 批量条）。
      // 公共链（pathStack/PageMap/warmup/广播/二级页 push）两形态共享零改动；热切经 @Watch
      // 回根重建（onHomeLayoutChanged）。壁纸底座/页签菜单锚点随页签壳住在 TabShell 内；
      // DrawerMainArea 自带主区背景。★ 上根大改笔：侧栏面板与蒙层在 build 根的容器另一子，
      // 本处只装主区——标题栏覆盖层（DrawerHomeTitleBar）仍在本壳，开态被面板盖住
      if (this.isDrawerMode()) {
        DrawerMainArea({
          activeConvId: $activeConvId,
          // 乐观空态标记（2026-11-18）：当前 id 即最近一次本地新造 id = 必然空——
          // 双交替重建时 @Prop 构造即读，空态不等读库回执
          freshSession: this.freshConvId !== '' && this.activeConvId === this.freshConvId,
          // 主区菜单新建上行：先打新造标记再换 id（顺序红线见 DrawerMainArea 成员注释）
          onFreshSession: (newId: string): void => {
            this.markFreshConversation(newId);
            this.activeConvId = newId;
          },
          topPad: this.titleBarInset(),
          bottomPad: this.navBarHeight,
          pathStack: this.pathStack
        })
      } else {
        TabShell({
          currentTab: $currentTab,
          chatFavSegment: $chatFavSegment,
          topInset: this.titleBarInset(),
          bottomPad: this.pageBottomPad(),
          navBarHeight: this.navBarHeight,
          pathStack: this.pathStack,
          actions: this.actions,
          settingsScroller: this.settingsScroller,
          onOpenSession: (conversationId: string, presetTitle?: string): void => {
            this.openSession(conversationId, presetTitle);
          },
          onNewConversation: (): void => {
            this.newConversation();
          },
          onNewSessionSearch: (): void => {
            this.newSessionSearch();
          },
          onSettingsScrollOffset: (offsetY: number): void => {
            this.onSettingsScrollOffset(offsetY);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    // 官方 HDS 沉浸标题栏：渐变模糊 + 光感材质（沉浸光感总档驱动）+ avoidLayoutSafeArea
    // 避让状态栏（参数定稿见 common/ImmersiveLevel.ets）。tabs 形态右上角键：「助手」页签 =
    // 覆盖层自绘单键〔＋新建助手〕/「对话」页签 = 覆盖层自绘（中央「全部/收藏」分段胶囊 +
    // 右端〔⋯更多〕单圆键，新建与搜索收入菜单）/「设置」页签 = 搜索键。两页签覆盖层下主标题
    // 须保留（keepStackTitle = true——官方 stackBuilder 默认置空主标题；对话页胶囊屏幕
    // 居中，与左侧标题、右侧键三区互不遮挡）；根不再挂 backgroundColor(page_bg)——
    // 不透明性由内容区 Stack 的 PageBackground 铺满保证。
    // drawer 形态走**官方 stackBuilder 覆盖层**（2026-11-17 侧栏形态对齐二级对话页笔：主区
    // 标题栏自「蒙层下缘自绘行」上收官方插槽——DrawerHomeTitleBar 桥件，汉堡键 + 两态中央区
    // + 更多键与 tabs 形态同机制同观感，思考态经镜像键、动作经命令键下行；keepStackTitle=true
    // 主标题本就是空串，值不影响渲染只随 tabs 形态口径）：标题栏承担状态栏避让与沉浸光感底；
    // 页签域标题参数全不消费（TabShell 不在场，currentTab 恒初值 1）
    .titleBar(this.isDrawerMode() ?
      hdsTitleBarOptions('', this.immersiveLevel, TitleSize.TITLE_ML, undefined, this.drawerTitleBarStack(), true, undefined) :
      hdsTitleBarOptions(this.tabTitle(),
        this.immersiveLevel, TitleSize.TITLE_ML, this.tabMenusHds(),
        this.hasTitleOverlay() ? this.tabTitleBarStack() : undefined, this.hasTitleOverlay(),
        // 设置页签带内假框（第 7 参 bottomBuilder）：带在 ⇒ 假框带（settingsBandParams 内含
        // 「设置页签 + 未收带」判据），其余页签 / 带收起 ⇒ undefined 不写该区
        this.settingsBandParams()))
    // 标题栏模式显式 MINI：固定小标题（56vp）不随滚动位移/缩放；一级页无上级页面显式
    // 隐藏返回键（官方 MINI 默认出现返回键）
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    // 设置页签官方滚动联动（dynamicHideTitleBar：滚过 SETTINGS_BAND_HIDE_OFFSET 官方动效
    // 收带——hideBottomBuilder 只收标题栏下方带、标题区不动；HideMode.SCROLL_UP_TO = 滚到
    // 阈值才收；hideRatio 默认 2.0 渐进收起非跳变）。非设置页签传全默认 false = 不隐藏任何区
    // （恒挂零副作用，与下方分栏四参数同口径）；bindToScrollable = 官方滚动感知绑定（Scroller
    // 为设置页 Scroll 控制器，恒挂——非设置页签该控制器无源，绑定空转零副作用）。
    // ★ 真机待验项见 BLOCKED「设置页搜索互斥切换 真机清单」：menu 切换重建 titleBar options
    // 是否打断渐收动效 / SCROLL_UP_TO 方向语义
    .dynamicHideTitleBar(this.currentTab === 2 ? {
      hideBottomBuilder: true,
      mode: HideMode.SCROLL_UP_TO,
      hideOffset: SETTINGS_BAND_HIDE_OFFSET
    } : { hideBottomBuilder: false })
    .bindToScrollable([this.settingsScroller])
    // 二级页路由表注册（坑51：挂组件内 @Builder 方法）
    .navDestination(this.PageMap)
    // ★ 平板分栏：EXPANDED ≥840vp → Split 左右主详形态（navBar 区 = HdsTabs 三页签主
    // 界面在左持续显示，二级页 NavDestination 自动进右栏——push 链零改动），COMPACT/
    // MEDIUM → Stack（现状等价）；断点切换 = Index 实测档位驱动 mode 属性重渲染（官方
    // 默认带切换动画）。宽高四参数官方语义均仅 Split 模式生效（恒挂零副作用）：
    // navBarWidth 初始 360vp / 拖拽范围 280~520vp / enableDragBar 显式 true 保底 /
    // splitPlaceholder 空栈右栏壁纸铺底。查证结论汇总见 common/LayoutProfile.ets 头注释
    .mode(isExpandedLayout(this.layoutSizeClass) ? NavigationMode.Split : NavigationMode.Stack)
    .navBarWidth(SPLIT_NAV_BAR_WIDTH)
    .navBarWidthRange({ minWidth: SPLIT_NAV_BAR_MIN, maxWidth: SPLIT_NAV_BAR_MAX })
    .enableDragBar(true)
    .splitPlaceholder(this.splitContent as ComponentContent<Object>)
  }

  build() {
    // 形态分发（2026-11-18 二级页化笔：DrawerHost 自绘 Overlay 整族退役——drawer 形态的
    // 侧栏 = ROUTE_SIDE_PANEL_PAGE 二级页，两形态页面根同为 HdsNavigation 整壳；形态差异
    // 全在 navBar 区装法〔NavHost 内 DrawerMainArea / TabShell 分支〕与标题栏参数）
    this.NavHost()
  }
}
