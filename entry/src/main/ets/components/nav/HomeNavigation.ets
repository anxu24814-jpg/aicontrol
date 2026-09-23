// 导航壳（一级页沉浸光感中枢，2026-08-29 反馈轮 4 接入标题栏——底部页签光感 M2a 已随迁）。
// 层级（学 dshinhm HomeNavigation，不搬本体）：主路径 HdsNavigation 根（官方 HDS 标题栏
// GRADIENT_BLUR 常显渐变模糊 + 光感材质 + avoidLayoutSafeArea 避让状态栏）+ HdsTabs 悬浮
// 页签内容区（助手/对话/设置三页签——2026-09-01 助手域新建，同日领导指令换序助手居首：
// 页签序 = 助手0/对话1/设置2；启动直达对话页维持〔M2a 拍板〕= 初始 1；助手页签 =
// 助手卡片列表，标题栏〔＋新建助手|⋯更多〕胶囊（2026-09-22 合并胶囊笔）+ 点卡片切换当前
// 助手、卡内编辑键进编辑页；对话页签 = 历史会话列表，点卡片经
// 官方路由 push 对话页全屏覆盖）；无 HDS 设备回退普通 Navigation + 自制胶囊 BottomTabBar。
// ★ 窗口口径（轮 4 定稿，覆盖轮 2 的非全屏定稿）：全屏布局 + HDS 标题栏簇是配套前提——
// 标题栏沉浸（avoidLayoutSafeArea）只有 HDS 组件支持，普通 Navigation 全屏下标题顶入状态栏
// 且 expandSafeArea 裁 TOP 无效（坑2 真机实锤）；本轮标题栏迁移即满足配套，全屏配方随之
// 启用（EntryAbility setWindowLayoutFullScreen + RESIZE_WITH_CARET，dshinhm 同款）。
// 距底口径随切回全屏恢复 dshinhm 定稿：barBottomMargin = 避让区高（tabBarBottomMargin，
// 坑1 的「非全屏 margin 0」口径作废）。页面留白：topPad = 状态栏 + MINI 标题栏 56 + 蒙层
// 下延 16（首卡静止时完整落在渐变模糊蒙层下方，滚动时滑入蒙层——dshinhm 列表卡片法则）；
// bottomPad = navBarHeight + 80（悬浮页签让位）。
// ★ 壁纸底座接入（2026-08-29 M3，拍板 4）：主路径 HdsNavigation 内容区改 Stack{
// PageBackground + HdsTabs}——统一页面背景组件垫底（dshinhm 同款：单实例常驻，冷启动即
// 解码缓存，切页签不闪；自定义背景写入 AppStorage['pageBg'] 全局跟随，默认 = 官方灰底
// 深浅自动），替换原 Navigation backgroundColor(page_bg)（灰底变壁纸底）。回退路径同款
// 包底（dshinhm 回退分支无壁纸，此处为两路径观感一致接入——已记变更记录）。二级页
// 铺底换装见 PageMapBuilder.ets（轮 6 预留位兑现）。
// ★ PageMap 域拆分（2026-08-29 M3，拍板 2）：分支链迁 components/nav/PageMapBuilder.ets
// 全局 @Builder（本文件 398 行触 400 红线）；2026-09-01 助手域三页签接入再拆两域：
// 设置域 push/搜索菜单 → HomeNavActions.ets；挂载死规矩不变——navDestination 挂组件内
// @Builder 方法（坑51），由它调 buildPageMap 注入 pathStack/留白/档位/会话参数。
// syscap 口径：HDS 导航组件族（HdsNavigation/HdsTabs/HdsNavDestination）用 Core 自检
//（dshinhm 主路径实测口径；Full 是 HdsListItemCard 的门槛）——无 Core 回退分支。
// ★ 2026-09-01 反碎片并回：NavTabBarConfig.ets（底部页签配置——页签图标构造/各页签
// tabBar 样式/距底高度，本文件单消费方、同域「主导航装配」）并入——原拆分动因 = 行数
// 搬运，宪法修订（600 软引导 / 1000 硬线 + 反碎片下限）后按「并入既有同域文件优先」复归。
import {
  HdsNavigation,
  HdsNavigationMenuContentOptions,
  HdsNavigationTitleMode,
  HdsTabs,
  TitleSize
} from '@kit.UIDesignKit';
import { ComponentContent, SymbolGlyphModifier } from '@kit.ArkUI';
import { ChatSessionList, SESSION_MULTISELECT_CMD_KEY, SESSION_SELECT_MODE_KEY } from '../chat/ChatSessionList';
import { AssistantTitleBarKeys, AssistantTitleMenuCallbacks, AssistantTitleMenuHost,
  ChatTabTitleBar, TabMoreMenuAnchor, TabMoreMenuCallbacks, TabMoreMenuHost,
  assistantsMoreMenuFallback, sessionsMoreMenuFallback } from '../TabMoreMenu';
import { nextMessageId, PENDING_LOCKED_CONV_KEY } from '../../common/store/ChatDb';
import { biometricGate, BiometricGateOutcome, BiometricGateResult, gateOutcomeMessage } from '../../common/BiometricGate';
import { SettingsPage } from '../settings/SettingsPage';
import { AssistantPage, ASSISTANT_CREATE_CMD_KEY, ASSISTANT_ORDER_CMD_KEY } from '../assistants/AssistantPage';
import { BottomTabBar } from './BottomTabBar';
import { buildPageMap } from './PageMapBuilder';
import { HomeNavActions } from './HomeNavActions';
import { PageBackground } from '../../common/PageBackground';
import {
  ROUTE_ASSISTANT_SORT_PAGE,
  ROUTE_CHAT_PAGE,
  ROUTE_SESSION_SEARCH_PAGE
} from '../../common/RouteNames';
import {
  hdsTitleBarOptions,
  IMMERSIVE_LEVEL_KEY,
  resolvedHdsMaterialParams
} from '../../common/ImmersiveLevel';
import { isLaunchNewChatEnabled, PREF_LOADED_KEY, PREF_TAB_SWITCH_ANIM_KEY } from '../../common/AppPreferences';
import { isExpandedLayout, LAYOUT_SIZE_CLASS_KEY, SPLIT_NAV_BAR_MAX, SPLIT_NAV_BAR_MIN,
  SPLIT_NAV_BAR_WIDTH } from '../../common/LayoutProfile';
import { TITLE_BAR_MASK_EXTRA_HEIGHT, TITLE_BAR_MINI_HEIGHT } from '../../common/Theme';
import {
  ACTIVE_ASSISTANT_KEY, ASSISTANT_CONSOLE_ID
} from '../../common/store/AssistantDb';
import { SESSION_LIST_RELOAD_KEY } from '../chat/ChatSessionList';
import { CONN_RESOLVE_TICK_KEY } from '../../common/store/ProviderDb';
import { HelpCenterPage, CONSOLE_ASK_CMD_KEY } from '../settings/HelpCenterPage';
import { parseProactiveOpenCmd, PROACTIVE_OPEN_CMD_KEY } from '../../common/ProactiveGen';

// 页面底部留白（vp）：悬浮页签胶囊高约 56vp + 呼吸间距（dshinhm 页面让位定值）
const PAGE_BOTTOM_CLEARANCE: number = 80;

// 分栏空栈右栏占位页（2026-09-04 平板分栏适配任务 2）：splitPlaceholder 只收
// ComponentContent（全局 @Builder 包装，无参构造重载 d.ts 实锤）——内容 = PageBackground
// 铺底（与左栏壁纸同图连续，BgCache 共享缓存零重复解码），Stack 模式下挂载无效果恒挂零
// 副作用。不加占位文案（P2-4 克制：铺底 = 分栏观感必需；提示文字后置真机定）
@Builder
function splitPlaceholderView() {
  Stack() {
    PageBackground()
  }
  .width('100%')
  .height('100%')
}

// ═══ 底部页签配置（2026-08-29 M2a 新写精简版——姿势照 dshinhm HomeTabBarConfig.ets 不搬
// 本体；2026-09-01 自 NavTabBarConfig.ets 并回本文件。页签序 = 助手/对话/设置——装配序
// 由本文件 TabContent 顺序决定，此处只出各页签构造）═══

// 底部页签图标：官方 BottomTabBarStyle 的 icon 要显示系统符号，须用 TabBarSymbol 包
// SymbolGlyphModifier（直接传 $r('sys.symbol.xxx') 资源不渲染、只显示文字——dshinhm 坑11
// 真机实锤；符号名实存性已对 SDK resources.txt 核实：message/gearshape/person 三系均存在）。
// 坑12：TabBarSymbol 是纯数据类、运行时没有构造函数（真机 jscrash「TabBarSymbol is not
// defined」），必须用对象字面量赋值，禁止 new TabBarSymbol()；普通态描边符号、选中态
// 实心符号，选中高亮/未选中灰度配色用官方默认值，图标+文字整体居中由官方
// BottomTabBarStyle 布局负责
function tabSymbol(normal: Resource, selected: Resource): TabBarSymbol {
  const symbol: TabBarSymbol = {
    normal: new SymbolGlyphModifier(normal),
    selected: new SymbolGlyphModifier(selected)
  };
  return symbol;
}

// 回退胶囊/HdsTabs 距屏底高度：官方示例模式「导航指示条高度，无则 32vp」（dshinhm 坑10
// 定稿——barBottomMargin 默认 0 不自动避让，必须显式传避让区高度；前提 = 全屏窗口）
function tabBarBottomMargin(navBarHeight: number): number {
  return navBarHeight > 0 ? navBarHeight : 32;
}

// 对话页签（图标+文字：官方 BottomTabBarStyle「图标在上、文字在下」布局，verticalAlign
// 显式设官方默认 VerticalAlign.Center——图片+文字整体在页签高度内垂直居中，dshinhm 定稿）
function chatTabBar(): BottomTabBarStyle {
  return new BottomTabBarStyle(tabSymbol($r('sys.symbol.message'), $r('sys.symbol.message_fill')), '对话')
    .verticalAlign(VerticalAlign.Center);
}

// 助手页签（person 系官方符号，resources.txt 实锤——描边/实心配对同 message/gearshape 惯例）
function assistantTabBar(): BottomTabBarStyle {
  return new BottomTabBarStyle(tabSymbol($r('sys.symbol.person'), $r('sys.symbol.person_fill')), '助手')
    .verticalAlign(VerticalAlign.Center);
}

// 设置页签（gearshape 系官方符号，resources.txt 实锤 0xF0020/0xF001F）
function settingsTabBar(): BottomTabBarStyle {
  return new BottomTabBarStyle(tabSymbol($r('sys.symbol.gearshape'), $r('sys.symbol.gearshape_fill')), '设置')
    .verticalAlign(VerticalAlign.Center);
}

@Component
export struct HomeNavigation {
  // 系统避让区高度（vp，Index 异步实测下发）。★ 必须 @Prop（坑57 同族）：首建异步值未到，
  // 状态驱动重渲染才能把真值送进标题栏留白/页签距底/页面留白
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  // 当前页签（0=助手，1=对话，2=设置——2026-09-01 换序助手居首）：启动直达对话页 =
  // 初始 1（M2a 拍板维持——换序只动位置不动启动页）；onChange 回写唯一事实源
  @State currentTab: number = 1;
  // 页签切换动画开关（2026-09-08 偏好设置第 9 项，键单一来源 AppPreferences.ets）：true =
  // 横向滑切（animationDuration 300）/ false = 点按直达（0）；@StorageProp 订阅 = 状态
  // 驱动重渲染即时生效，无广播需求（与流式引擎开关同契约）
  @StorageProp(PREF_TAB_SWITCH_ANIM_KEY) tabSwitchAnim: boolean = true;
  // 沉浸光感档位（AppStorage；2026-09-12 分项退役后恒为单键——原「悬浮底栏」「其他控件」
  // 两分项跟随总档；无外观页恒为缺省 0 = dshinhm 定稿默认档「自适应」）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 官方 HDS 导航组件族可用性（Core 口径，见文件头注释）；无 Core 回退普通 Navigation
  private hdsAvailable: boolean = canIUse('SystemCapability.UIDesign.HDSComponent.Core');
  // 官方路由栈：会话卡片 push 对话页（系统级转场 + 侧滑/返回键自动 pop）
  private pathStack: NavPathStack = new NavPathStack();
  // 设置域导航动作（push 编排 + 搜索菜单——2026-09-01 域拆至 HomeNavActions，三页签
  // 接入腾行数红线）
  private actions: HomeNavActions = new HomeNavActions(this.pathStack);
  // 进入对话页的目标会话（卡片点击时记录，PageMap 构造 ChatPage 消费；一次一个对话页；
  // 会话标题由对话页自包壳按 id 查询——activeConvTitle 随任务 4 壳改造撤销）
  @State private activeConvId: string = '';
  // 隐私会话标记（2026-09-04，与 activeConvId 同生命周期语义）：true = push 进 ChatPage
  // 隐私模式（纯内存不落盘，见 ChatPage isPrivate 注释）；写 false = openSession/
  // newConversation 两入口，页内「新建会话」replacePath 不经此自然继承——隐私态直到 pop
  @State private activePrivate: boolean = false;
  // 会话列表多选中（ChatSessionList 广播——多选中收起页签避免与批量条重叠：HDS 路径
  // HdsTabs barBottomMargin 巨值推出视口（下方 barFloatingStyle），回退路径隐藏 BottomTabBar
  // 胶囊——dshinhm 二二二改/二二四改同款语义）
  @StorageProp(SESSION_SELECT_MODE_KEY) sessionSelectMode: boolean = false;
  // 「询问控制台助手」指令（HelpCenterPage 内置卡 +1 触发——见 CONSOLE_ASK_CMD_KEY 注释；
  // 首帧初始 0 不触发 @Watch）
  @StorageProp(CONSOLE_ASK_CMD_KEY) @Watch('onConsoleAskCmd') consoleAskCmd: number = 0;
  // 横幅点击直达会话命令（2026-09-12 主动消息第二笔：ProactiveBanner 点击经
  // PROACTIVE_OPEN_CMD_KEY 下发——值 = convId + '#' + 自增序号，CONSOLE_ASK_CMD_KEY
  // 命令键同族 @StorageProp @Watch 消费范式；首帧初始 '' 不触发）
  @StorageProp(PROACTIVE_OPEN_CMD_KEY) @Watch('onProactiveOpenCmd') proactiveOpenCmd: string = '';
  // 「对话」页签更多菜单节点宿主（init/open/dispose 成对见 TabMoreMenu.ets 注释）
  private tabMoreMenu: TabMoreMenuHost = new TabMoreMenuHost();
  // 「助手」页签更多菜单节点宿主（2026-09-22 助手页签合并胶囊笔新增；两页签共用隐形锚点，
  // 节点各自持有——init/dispose 与 tabMoreMenu 同法成对）
  private assistantMoreMenu: AssistantTitleMenuHost = new AssistantTitleMenuHost();
  // 断点档位（Index.ets 窗口实测下发；缺省 0 = COMPACT——断点不持久，口径见 LayoutProfile）
  @StorageProp(LAYOUT_SIZE_CLASS_KEY) layoutSizeClass: number = 0;
  // 分栏空栈右栏占位内容（splitPlaceholder 只收 ComponentContent；aboutToAppear 构造 /
  // aboutToDisappear dispose 成对——内存红线。build 恒晚于 aboutToAppear，属性链处非空
  // 不变量成立）
  private splitContent: ComponentContent<Object> | null = null;

  // 偏好键就绪信号（AppStorage 进程内一次性：EntryAbility 注册完全部 persistProp 后置 1）。
  // ★ 2026-09-08 自检轮发现并修复：本组件与「persistProp 注册」谁先谁后未实测（项目注释称
  // 注册在先，但那是推断，loadContent d.ts 反注「回调内当前 UI 的执行上下文可能不明确」），
  // 原实现只在 aboutToAppear 一次性现读——若注册后到即读到缺省值 = 设置静默失效。现两路径
  // 都收敛到 tryEnterLaunchConversation，不赌时序（风险说明见 AppPreferences.PREF_LOADED_KEY）
  @StorageProp(PREF_LOADED_KEY) @Watch('onPrefsLoaded') prefsLoaded: number = 0;
  // 启动进入判定一次性消费标记：进程内只判定一次——就绪信号进程内只置一次，用户运行期改
  // 开关不会触发（切换下次启动生效，与键注释口径一致）
  private launchConsumed: boolean = false;

  aboutToAppear(): void {
    // 更多菜单节点首次构建（getUIContext 需组件就绪；与 aboutToDisappear dispose 成对）
    this.tabMoreMenu.init(this.getUIContext(), this.tabMenuCallbacks());
    // 助手页签更多菜单节点首建（同上；两页签菜单宿主各自成对）
    this.assistantMoreMenu.init(this.getUIContext(), this.assistantMenuCallbacks());
    // 分栏占位内容构造（与 aboutToDisappear dispose 成对）
    this.splitContent = new ComponentContent<Object>(this.getUIContext(),
      wrapBuilder(splitPlaceholderView));
    // 冷启动默认进入新对话判定（就绪信号已在场路径——注册先于本组件时走这里；后到路径见
    // onPrefsLoaded。两路径共用一次性标记，语义见 tryEnterLaunchConversation）
    this.tryEnterLaunchConversation();
  }

  // 就绪信号到达（注册后到路径）：补做启动进入判定
  private onPrefsLoaded(): void {
    this.tryEnterLaunchConversation();
  }

  // 启动进入判定（两路径共用，一次性）：开关开启时进入懒创建新会话——aboutToAppear 路径下
  // 本方法早于 build，pathStack 已带一条记录，导航组件首次构建即渲染该 NavDestination
  //（官方 FAQ faqs-arkui-1018 场景一同款姿势：页面 aboutToAppear 里 push 子页）；animated=false
  // 关转场动画（冷启动不该有推入动画）。后台回前台不重建组件 = 不重复进新对话
  private tryEnterLaunchConversation(): void {
    if (this.launchConsumed || !isLaunchNewChatEnabled()) {
      return;
    }
    this.launchConsumed = true;
    this.pushNewConversation(false);
  }

  aboutToDisappear(): void {
    // 更多菜单节点释放（与 aboutToAppear init 成对；本组件常驻导航壳，正常仅应用退出触发）
    this.tabMoreMenu.dispose();
    // 助手页签更多菜单节点释放（同上成对）
    this.assistantMoreMenu.dispose();
    // 分栏占位内容释放（与 aboutToAppear 构造成对）
    this.splitContent?.dispose();
    this.splitContent = null;
  }

  // 滚动内容顶部留白（vp）：HDS 路径内容区从窗口顶延伸到标题栏背后（渐变模糊蒙层透出
  // 滚动内容），留白使首卡静止时完整落在蒙层下方；回退路径内容区天然在标题栏下方 = 0
  private titleBarInset(): number {
    return this.hdsAvailable ?
      this.statusBarHeight + TITLE_BAR_MINI_HEIGHT + TITLE_BAR_MASK_EXTRA_HEIGHT : 0;
  }

  // 页面底部留白（vp）：悬浮页签让位（胶囊高 + 呼吸 + 底部避让区）
  private pageBottomPad(): number {
    return this.navBarHeight + PAGE_BOTTOM_CLEARANCE;
  }

  // 页签标题（标题栏随页签切换的唯一事实源 = currentTab；序 = 助手0/对话1/设置2）
  private tabTitle(): string {
    return this.currentTab === 0 ? '助手' : this.currentTab === 1 ? '对话' : '设置';
  }

  // 点会话卡片：记录目标会话 + 官方路由 push（隐私标记复位——普通入口恒普通模式）
  private openSession(conversationId: string): void {
    this.activePrivate = false;
    this.activeConvId = conversationId;
    this.pathStack.pushPathByName(ROUTE_CHAT_PAGE, null);
  }

  // 「对话」页签标题栏「＋」新建会话（2026-08-31 领导指令：右下角新建悬浮键上移标题栏，点击仍执行
  // 新建会话）：懒创建语义同原悬浮键——本地生成会话 id 走 push 既有链路，不落库（首条消息
  // 发送时 ChatDb 才建行）；多选中忽略（原悬浮键多选中隐藏语义：批量条占位 + 新建
  // 语义冲突）
  private newConversation(): void {
    if (this.sessionSelectMode) {
      return;
    }
    this.pushNewConversation(true);
  }

  // 懒创建新会话并进入（2026-09-08 提取：标题栏「＋」与冷启动默认进入两处共用——P2-4
  // 重复逻辑提子程序）：本地生成会话 id + 复位隐私标记 + push 对话页，不落库；助手归属 =
  // 当前助手（ACTIVE_ASSISTANT_KEY，ChatPromptState.effectiveAssistantId 无行兜底）；
  // animated = false 用于冷启动首帧（无推入转场动画）
  private pushNewConversation(animated: boolean): void {
    this.activePrivate = false;
    this.activeConvId = nextMessageId('conv');
    this.pathStack.pushPathByName(ROUTE_CHAT_PAGE, null, animated);
  }

  // 「对话」页签标题栏搜索键（2026-09-08 会话搜索改版：原 AppStorage 指令展开一级页搜索态
  // 退役——改 push 独立二级搜索页 SessionSearchPage，同设置搜索形态；决明指令「之前全放
  // 一级页了，改」）。多选中忽略守卫 = 原消费端 onSearchCmd 语义上移（newConversation 同款
  // 守卫先例——多选中不响应搜索键）
  private newSessionSearch(): void {
    if (this.sessionSelectMode) {
      return;
    }
    this.pathStack.pushPathByName(ROUTE_SESSION_SEARCH_PAGE, null);
  }

  // 「更多」菜单「隐私会话」（2026-09-04）：同 newConversation 懒创建语义 + 隐私标记置位
  //——push 进 ChatPage 隐私模式，整个路由生命周期（页内「新建会话」replacePath 继承标记）
  // 不产生任何 DB 行，pop 后 openSession/newConversation 写回 false（注释见 activePrivate）
  private newPrivateSession(): void {
    if (this.sessionSelectMode) {
      return;
    }
    this.activePrivate = true;
    this.activeConvId = nextMessageId('conv');
    this.pathStack.pushPathByName(ROUTE_CHAT_PAGE, null);
  }

  // 「更多」菜单「加密会话」（2026-09-05 决明指令「入口在对话一级页右上角菜单」）：先过
  // 官方生物识别——通过后进懒创建新会话（空会话退出 = 历史无痕），加密标记经
  // PENDING_LOCKED_CONV_KEY 精确绑定新 id，首条消息落行时 ChatDb 消费置 locked=1（列表
  // 锁标与再进验证走既有链）。取消静默，其余 gateOutcomeMessage 分文案（code 直显取证）
  private newEncryptedSession(): void {
    if (this.sessionSelectMode) {
      return;
    }
    biometricGate('验证身份，新建加密会话')
      .then((gate: BiometricGateResult): void => {
        if (gate.outcome !== BiometricGateOutcome.PASSED) {
          const message: string = gateOutcomeMessage(gate);
          if (message !== '') {
            this.getUIContext().getPromptAction().showToast({ message: message });
          }
          return;
        }
        const newId: string = nextMessageId('conv');
        AppStorage.setOrCreate<string>(PENDING_LOCKED_CONV_KEY, newId);
        this.openSession(newId);
      });
  }

  // 「询问控制台助手」（2026-09-05 控制台助手入口——HelpCenterPage 经 CONSOLE_ASK_CMD_KEY
  // 触发）：切当前助手为内置控制台助手三连写（照 AssistantPage.switchActive 同族——写
  // ACTIVE 持久键 + 历史列表重拉 + 连接解析 tick）+ 懒创建新会话 push（不落库，首条消息
  // 发送时按当前助手落行绑定 = 控制台助手）；多选中忽略（newConversation 同守卫）。★ 切换
  // 会持久生效（既有助手页点卡语义），toast 明示；问完切回 = 助手页点其他助手卡
  private onConsoleAskCmd(): void {
    if (this.sessionSelectMode) {
      return;
    }
    AppStorage.setOrCreate<string>(ACTIVE_ASSISTANT_KEY, ASSISTANT_CONSOLE_ID);
    AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
      (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
    AppStorage.setOrCreate<number>(CONN_RESOLVE_TICK_KEY,
      (AppStorage.get<number>(CONN_RESOLVE_TICK_KEY) ?? 0) + 1);
    this.getUIContext().getPromptAction().showToast({ message: '已切换到「控制台助手」' });
    this.openSession(nextMessageId('conv'));
  }

  // 横幅直达会话（2026-09-12 主动消息第二笔：ProactiveBanner 点击 → PROACTIVE_OPEN_
  // CMD_KEY）：解析会话 id 走 openSession 直达（隐私标记复位 + push 对话页——与点会话
  // 卡片同链路）；多选中忽略（newConversation 同守卫先例——多选中不响应横幅导航）；空
  // 命令（脏值）不导航
  private onProactiveOpenCmd(): void {
    if (this.sessionSelectMode) {
      return;
    }
    const convId: string = parseProactiveOpenCmd(this.proactiveOpenCmd);
    if (convId !== '') {
      this.openSession(convId);
    }
  }

  // 「助手」页签标题栏「＋」新建（2026-09-01 按钮区退役轮：「＋」不再 push 编辑页——新建
  // 改弹名称对话框，对话框在 AssistantPage 内〔组件成员位坑7〕）：经一次性指令计数器下发
  //（菜单域无法直达 TabContent 内组件——AssistantPage @StorageProp @Watch 消费弹窗，
  // ChatSessionList 多选指令键同机制，坑3 口径；确认 insert + reload 全在 AssistantPage 内）
  private newAssistant(): void {
    AppStorage.setOrCreate<number>(ASSISTANT_CREATE_CMD_KEY,
      (AppStorage.get<number>(ASSISTANT_CREATE_CMD_KEY) ?? 0) + 1);
  }

  // 「对话」页签更多菜单回调（init/open 两处共用，P2-4 提取；「多选」经 AppStorage 一次性
  // 指令计数器下发 ChatSessionList（@StorageProp @Watch 消费——多层宿主链零透传，坑3
  // 口径；键常量见 ChatSessionList.ets）；「隐私会话」直调本组件路由方法。后续加菜单项 =
  // TabMoreMenu 接口加字段 + 本处加回调）
  private tabMenuCallbacks(): TabMoreMenuCallbacks {
    return {
      onMultiselect: (): void => {
        AppStorage.setOrCreate<number>(SESSION_MULTISELECT_CMD_KEY,
          (AppStorage.get<number>(SESSION_MULTISELECT_CMD_KEY) ?? 0) + 1);
      },
      onPrivateSession: (): void => {
        this.newPrivateSession();
      },
      onNewEncryptedSession: (): void => {
        this.newEncryptedSession();
      }
    };
  }

  // 「对话」页签更多菜单弹出：标题栏按钮 action 触发，节点宿主每次弹出前重建
  //（深浅色/材质安全）
  private openTabMoreMenu(): void {
    this.tabMoreMenu.open(this.getUIContext(), this.tabMenuCallbacks(),
      this.immersiveLevel);
  }

  // 「助手」页签更多菜单回调（2026-09-22 合并胶囊笔；现仅「排序」一项——★ 2026-09-22
  // 助手自定义列表序笔落地：占位提示退役，改为 push 助手排序页（ROUTE_ASSISTANT_SORT_PAGE，
  // 先例 = ProviderSortPage/MemorySortPage）；助手页属 TabContent（菜单域无法直达其 reload），
  // 返回经 ASSISTANT_ORDER_CMD_KEY 指令键下发重拉新卡序——与「＋」新建同一机制、坑3 口径）
  private assistantMenuCallbacks(): AssistantTitleMenuCallbacks {
    return {
      onSort: (): void => {
        this.pathStack.pushPathByName(ROUTE_ASSISTANT_SORT_PAGE, null, (): void => {
          AppStorage.setOrCreate<number>(ASSISTANT_ORDER_CMD_KEY,
            (AppStorage.get<number>(ASSISTANT_ORDER_CMD_KEY) ?? 0) + 1);
        });
      }
    };
  }

  // 「助手」页签更多菜单弹出（节点宿主每次弹出前重建，同 openTabMoreMenu）
  private openAssistantMoreMenu(): void {
    this.assistantMoreMenu.open(this.getUIContext(), this.assistantMenuCallbacks(),
      this.immersiveLevel);
  }

  // 页签标题栏菜单（HDS 主路径）：助手 = 不传（两键迁标题栏覆盖层 AssistantTitleBarKeys
  // ——2026-09-22 合并胶囊笔「＋ 与更多合为双键胶囊」）/ 对话 = 不传（三键迁标题栏覆盖层
  // ChatTabTitleBar 组件——2026-09-09 合并胶囊笔，官方数组画不出合并形态）/ 设置 =
  // 搜索键（序 = 助手 0/对话1/设置2）
  private tabMenusHds(): HdsNavigationMenuContentOptions | undefined {
    if (this.currentTab === 0 || this.currentTab === 1) {
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
  // 头注释）；组件内 @Builder 编译为类方法、this 恒有绑定）
  @Builder
  ChatTabTitleBarOverlay() {
    ChatTabTitleBar({
      immersiveLevel: this.immersiveLevel,
      onSearch: (): void => {
        this.newSessionSearch();
      },
      onNew: (): void => {
        this.newConversation();
      },
      onMore: (): void => {
        this.openTabMoreMenu();
      }
    })
  }

  // 「助手」页签标题栏覆盖层（2026-09-22 合并胶囊笔；挂载死规矩同下条——必须是组件 +
  // 组件内 @Builder 挂载，禁全局 @Builder）
  @Builder
  AssistantTitleBarOverlay() {
    AssistantTitleBarKeys({
      immersiveLevel: this.immersiveLevel,
      // 「＋」动作一字未动：仍走指令键下发 AssistantPage 弹名称对话框（保持原功能）
      onAdd: (): void => {
        this.newAssistant();
      },
      onMore: (): void => {
        this.openAssistantMoreMenu();
      }
    })
  }

  // 页签标题栏覆盖层构造器（HDS 路径专用；档位与回调经组件参数注入——档位读取发生在
  // 标题栏构建期，光感档位变化自动重建。回退路径无 stackBuilder 机制，两页签各键仍在官方
  // menus 数组，形态必然不同）。
  // ★ 内层页签守卫：覆盖层只在助手/对话两页签出键——builder 每次执行都现读页签，切走即
  // 内容为空。真机实测（2026-09-09 二百三十四节）= 官方在 stackBuilder 传 undefined 时
  // **会清除**既有覆盖层（切页签后官方单键恢复）；守卫保留为第二道防线（该行为官方未文档化，
  // 版本升级若变语义可自愈）。两页签覆盖层互斥（同一时刻只画当前页签那枚）
  private tabTitleBarStack(): CustomBuilder {
    return (): void => {
      if (this.currentTab === 1) {
        this.ChatTabTitleBarOverlay();
      } else if (this.currentTab === 0) {
        this.AssistantTitleBarOverlay();
      }
    };
  }

  // 页签标题栏菜单（回退路径 Navigation.menus）：同 tabMenusHds 三分支——助手/对话两页签
  // 各自两键/三键数组（无 stackBuilder 机制，合并不了）
  private tabMenusNav(): NavigationMenuItem[] {
    if (this.currentTab === 0) {
      return assistantsMoreMenuFallback((): void => {
        this.newAssistant();
      }, (): void => {
        this.openAssistantMoreMenu();
      });
    }
    if (this.currentTab === 1) {
      return sessionsMoreMenuFallback((): void => {
        this.newSessionSearch();
      }, (): void => {
        this.newConversation();
      }, (): void => {
        this.openTabMoreMenu();
      });
    }
    return this.actions.settingsSearchMenuFallback();
  }

  // 二级页路由表（官方 navDestination builder；★ 坑51 死规矩：必须挂组件内 @Builder
  // 方法——lambda 直挂全局 @Builder 真机白屏）。分支链已迁 PageMapBuilder.ets（M3 拆分，
  // 见该文件头注释）；本方法只负责注入 pathStack/留白/会话参数（含隐私标记）与打开会话
  // 编排回调（2026-09-08 会话搜索二级页消费——闭包直传本组件方法 openSession，含
  // activePrivate 复位；捕获 this 合法，坑51 只禁 lambda 直挂 navDestination）——标题栏
  // 档位材质 2026-09-07 起由各页 PageShell 内部 @StorageProp 自订阅，不再经本链透传
  @Builder
  PageMap(name: string, param: Object) {
    buildPageMap(name, param, this.pathStack, this.titleBarInset(), this.navBarHeight,
      this.activeConvId, this.activePrivate, (conversationId: string): void => {
        this.openSession(conversationId);
      })
  }

  build() {
    if (this.hdsAvailable) {
      // ┌──────── 主路径：HdsNavigation 沉浸标题栏 + HdsTabs 悬浮页签 ────────┐
      HdsNavigation(this.pathStack) {
        // 统一页面背景垫底（M3 拍板 4，dshinhm 同款）：背景在 Tabs 外层单实例常驻——
        // 懒加载/重建 TabContent 不闪；二级页 push 覆盖整个导航（含本背景）
        Stack() {
          PageBackground()
          // 两页签更多菜单隐形锚点（openMenu TargetInfo；全高层 + HitTest.None 穿透，
          // 组件见 TabMoreMenu.ets）
          TabMoreMenuAnchor({ topInset: this.titleBarInset() })
          HdsTabs({ index: this.currentTab }) {
            TabContent() {
              AssistantPage({
                topPad: this.titleBarInset(),
                bottomPad: this.pageBottomPad(),
                pathStack: this.pathStack
              })
            }
            // 内容区背景显式透明（dshinhm 真机实锤：HdsTabs/TabContent 官方默认白底）
            .backgroundColor(Color.Transparent)
            .tabBar(assistantTabBar())
            TabContent() {
              ChatSessionList({
                topPad: this.titleBarInset(),
                bottomPad: this.pageBottomPad(),
                barBottom: this.navBarHeight + 16,
                onOpen: (conversationId: string): void => {
                  this.openSession(conversationId);
                }
              })
            }
            // 内容区背景显式透明（dshinhm 真机实锤：HdsTabs/TabContent 官方默认白底）
            .backgroundColor(Color.Transparent)
            .tabBar(chatTabBar())
            TabContent() {
              SettingsPage({
                topPad: this.titleBarInset(),
                bottomPad: this.pageBottomPad(),
                onOpenProvider: (): void => {
                  this.actions.pushProvider();
                },
                onOpenAppearance: (): void => {
                  this.actions.pushAppearance();
                },
                onOpenInfo: (): void => {
                  this.actions.pushInfo();
                },
                onOpenPrompts: (): void => {
                  this.actions.pushPrompts();
                },
                onOpenSystemPrompt: (): void => {
                  this.actions.pushSystemPrompt();
                },
                // 技能库行卡接线（2026-09-13 技能层笔 1——HDS 与回退两路径同款，勿单补一路）
                onOpenSkillLibrary: (): void => {
                  this.actions.pushSkillLibrary();
                },
                // 知识库行卡接线（2026-09-21 世界书知识库首版——HDS 与回退两路径同款，勿单补一路）
                onOpenKnowledgeLibrary: (): void => {
                  this.actions.pushKnowledgeLibrary();
                },
                onOpenPreferences: (): void => {
                  this.actions.pushPreferences();
                },
                onOpenDataSync: (): void => {
                  this.actions.pushDataSync();
                },
                onOpenFunctionalModel: (): void => {
                  this.actions.pushFunctionalModel();
                },
                onOpenUsageStats: (): void => {
                  this.actions.pushUsageStats();
                },
                onOpenCostStats: (): void => {
                  this.actions.pushCostStats();
                },
                onOpenMemory: (): void => {
                  this.actions.pushMemory();
                },
                onOpenProactive: (): void => {
                  this.actions.pushProactive();
                },
                onOpenStorage: (): void => {
                  this.actions.pushStorage();
                },
                onOpenSearchEngine: (): void => {
                  this.actions.pushSearchEngine();
                },
                onOpenTools: (): void => {
                  this.actions.pushTools();
                }
              })
            }
            .backgroundColor(Color.Transparent)
            .tabBar(settingsTabBar())
          }
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          // 悬浮三件套（官方示例模式）+ 项目行为：点按切换 = 横向滑切动画（2026-09-08
          // 决明拍板开回 + 同日偏好设置第 9 项开关控制）：animationDuration 显式 300 =
          // 官方通用默认时长——官方语义 = BottomTabBarStyle 下不设/删行默认 0（仍无
          // 动画），必须显式正值（tabs.d.ts「11+：BottomTabBarStyle 默认 0，其他样式
          // 300」）；tabSwitchAnim 关 = 0（点按直达，无过渡）；「不加页面间横滑切换」=
          // 手势滑动保持关闭（scrollable(false)，原值不动）
          .barOverlap(true)
          .vertical(false)
          .barPosition(BarPosition.End)
          .scrollable(false)
          .animationDuration(this.tabSwitchAnim ? 300 : 0)
          .onChange((index: number) => {
            this.currentTab = index;
          })
          // 悬浮样式定稿（dshinhm 节）：距底避让（全屏窗口下 = 避让区高，坑1 配方）/ 材质
          // 一个字段接管 / gradientMask 关闭（2026-08-21 决明定稿；恢复官方默认删该字段）。
          // 会话多选中 barBottomMargin 巨值把悬浮胶囊推出视口（1000vp 远超任何机型屏高，
          // 胶囊连同触摸热区一起离屏，批量条不受残留热区遮挡），退出多选恢复定稿值——
          // dshinhm 二二四改同款（恢复值零猜测：barHeight 改值/attributeModifier 两案
          // dshinhm 真机均实证失败后废弃的定稿方案）
          .barFloatingStyle({
            barBottomMargin: this.sessionSelectMode ? 1000 : tabBarBottomMargin(this.navBarHeight),
            systemMaterialEffect: resolvedHdsMaterialParams(this.immersiveLevel),
            gradientMask: { maskColor: Color.Transparent }
          })
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      // 官方 HDS 沉浸标题栏：GRADIENT_BLUR 常显渐变模糊 + 光感材质（沉浸光感总档驱动）
      // + avoidLayoutSafeArea 避让状态栏（参数定稿见 common/ImmersiveLevel.ets）；
      // 右上角键：「助手」页签 = 标题栏覆盖层自绘两键〔＋新建助手|⋯更多〕（2026-09-22 决明
      // 「＋/更多双键胶囊，加保持原功能，点击更多弹菜单」——原官方菜单数组单键 ＋ 退役）/
      // 「对话」页签 = 标题栏覆盖层自绘（搜索圆键 + 合并胶囊〔＋|⋯〕——2026-09-09 决明「加号
      // 和更多合并为双键胶囊」，官方菜单数组退役）/「设置」页签 = 搜索键。两页签覆盖层下主标题
      // 须保留（keepStackTitle = true——官方 stackBuilder 默认置空主标题）；根不再挂
      // backgroundColor(page_bg)——不透明性由内容区 Stack 的 PageBackground 铺满保证（M3 拍板 4）
      .titleBar(hdsTitleBarOptions(this.tabTitle(),
        this.immersiveLevel, TitleSize.TITLE_ML, this.tabMenusHds(),
        this.hasTitleOverlay() ? this.tabTitleBarStack() : undefined, this.hasTitleOverlay()))
      // 标题栏模式显式 MINI：固定小标题（56vp）不随滚动位移/缩放；一级页无上级页面显式
      // 隐藏返回键（官方 MINI 默认出现返回键，dshinhm 同款）
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      // 二级页路由表注册（坑51：挂组件内 @Builder 方法）
      .navDestination(this.PageMap)
      // ★ 平板分栏（2026-09-04 任务书任务 2）：EXPANDED ≥840vp → Split 左右主详形态
      //（navBar 区 = HdsTabs 三页签主界面在左持续显示，二级页 NavDestination 自动进右栏
      //——push 链零改动），COMPACT/MEDIUM → Stack（现状等价，全屏 push 行为零变化）；
      // 断点切换 = Index 实测档位驱动 mode 属性重渲染（官方默认带切换动画）。宽高四参数
      // 官方语义均仅 Split 模式生效（恒挂零副作用）：navBarWidth 初始 360vp / 拖拽范围
      // 280~520vp（官方自动携带，值真机定稿可调）/ enableDragBar 显式 true 保底 /
      // splitPlaceholder 空栈右栏壁纸铺底。查证结论汇总见 common/LayoutProfile.ets 头注释
      .mode(isExpandedLayout(this.layoutSizeClass) ? NavigationMode.Split : NavigationMode.Stack)
      .navBarWidth(SPLIT_NAV_BAR_WIDTH)
      .navBarWidthRange({ minWidth: SPLIT_NAV_BAR_MIN, maxWidth: SPLIT_NAV_BAR_MAX })
      .enableDragBar(true)
      .splitPlaceholder(this.splitContent as ComponentContent<Object>)
      // └────────────────────────────────────────────────┘
    } else {
      // ┌──────────── 回退路径（设备无 HDS Core syscap）────────────┐
      Navigation(this.pathStack) {
        // PageBackground 垫底 + 原内容栈（M3 接入；dshinhm 回退分支无壁纸，此处为两路径
        // 观感一致接入——默认态 = page_bg 纯色与原 backgroundColor 同色，行为不变）
        Stack({ alignContent: Alignment.Bottom }) {
          PageBackground()
          // 两页签更多菜单隐形锚点（回退路径同款；topInset=0 → 钳位贴顶）
          TabMoreMenuAnchor({ topInset: 0 })
          if (this.currentTab === 0) {
            AssistantPage({
              topPad: this.titleBarInset(),
              bottomPad: this.pageBottomPad(),
              pathStack: this.pathStack
            })
          } else if (this.currentTab === 1) {
            ChatSessionList({
              topPad: this.titleBarInset(),
              bottomPad: this.pageBottomPad(),
              barBottom: this.navBarHeight + 16,
              onOpen: (conversationId: string): void => {
                this.openSession(conversationId);
              }
            })
          } else {
            SettingsPage({
              topPad: this.titleBarInset(),
              bottomPad: this.pageBottomPad(),
              onOpenProvider: (): void => {
                this.actions.pushProvider();
              },
              onOpenAppearance: (): void => {
                this.actions.pushAppearance();
              },
              onOpenInfo: (): void => {
                this.actions.pushInfo();
              },
              onOpenPrompts: (): void => {
                this.actions.pushPrompts();
              },
              onOpenSystemPrompt: (): void => {
                this.actions.pushSystemPrompt();
              },
              // 技能库行卡接线（2026-09-13 技能层笔 1——与 HDS 主路径同款）
              onOpenSkillLibrary: (): void => {
                this.actions.pushSkillLibrary();
              },
              // 知识库行卡接线（2026-09-21 世界书知识库首版——与 HDS 主路径同款）
              onOpenKnowledgeLibrary: (): void => {
                this.actions.pushKnowledgeLibrary();
              },
              onOpenPreferences: (): void => {
                this.actions.pushPreferences();
              },
              onOpenDataSync: (): void => {
                this.actions.pushDataSync();
              },
              // 回退路径补 functionalModel 接线（2026-09-06 顺手修：HDS 主路径有此回调而
              // 回退路径漏接——无 HDS 设备点功能模型卡无响应的存量缺口，随本笔接线域补齐）
              onOpenFunctionalModel: (): void => {
                this.actions.pushFunctionalModel();
              },
              onOpenUsageStats: (): void => {
                this.actions.pushUsageStats();
              },
              onOpenCostStats: (): void => {
                this.actions.pushCostStats();
              },
              onOpenMemory: (): void => {
                this.actions.pushMemory();
              },
              onOpenProactive: (): void => {
                this.actions.pushProactive();
              },
              onOpenStorage: (): void => {
                this.actions.pushStorage();
              },
              onOpenSearchEngine: (): void => {
                this.actions.pushSearchEngine();
              },
              onOpenTools: (): void => {
                this.actions.pushTools();
              }
            })
          }
          // 会话多选中隐藏回退胶囊页签（避免与多选批量条重叠——HDS 路径经 HdsTabs
          // barBottomMargin 巨值同步收起，语义见 sessionSelectMode 注释）
          if (!this.sessionSelectMode) {
            BottomTabBar({
              currentTab: this.currentTab,
              onTabChange: (index: number) => {
                this.currentTab = index;
              }
            })
            .margin({ bottom: tabBarBottomMargin(this.navBarHeight) })
          }
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      // 页面标题走官方 Navigation 标题栏（勿手写标题 Text）：MINI 固定小标题 + 一级页
      // 显式隐藏返回键；标题随页签切换；右上角键（回退路径，与 HDS 分支同一入口）——
      // 助手 = 两键〔＋/⋯〕/ 对话 = 三键〔搜索/＋/⋯〕（回退无 stackBuilder 机制，合并不了）/ 设置 =
      // 搜索键（回退 menus 姿势）
      .title(this.tabTitle())
      .titleMode(NavigationTitleMode.Mini)
      .hideBackButton(true)
      .menus(this.tabMenusNav())
      .navDestination(this.PageMap)
      // 全屏窗口下回退标题避让未真机验证（坑2：expandSafeArea 裁 TOP 实测无效）；本分支
      // 仅无 HDS 设备触达（API 26+ 华为设备均有 HDS），如标题顶入状态栏按坑2 结论处理
      .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.KEYBOARD, SafeAreaType.CUTOUT], [SafeAreaEdge.BOTTOM])
      // └────────────────────────────────────────────┘
    }
  }
}
