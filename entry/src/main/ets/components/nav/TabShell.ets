// 底栏形态页签壳（2026-11-16 首页布局双形态笔域级最小拆分自 HomeNavigation——方案档 §2.2
// 「navBar 区两种装法」的底栏装法，现状三页签装配原样搬迁零行为变化）：HdsTabs 悬浮底栏
// 三 TabContent（助手 0 / 对话 1 / 设置 2，启动直达对话页 = 初始 1）+ 可选第四项「新建」
// 动作位（快捷新建键 'tabItem' 档）+ 页签栏旁「新建会话」圆键（'tabBar' 档迷你栏）。
// · 壳层分工（双形态拆分后）：HdsNavigation（路由栈/标题栏/分栏）与命令链（分享路由/启动
//   判定/横幅直达）留 HomeNavigation 分发器；本件只装「navBar 区内容」——页签状态
//   （currentTab/chatFavSegment）@Link 回连分发器（标题栏覆盖层与分段胶囊在分发器侧），
//   页签内编排（开会话/新建/搜索/设置滚动联动）经回调上抛分发器既有方法，不复制链路。
// · 快捷新建键两档的生效面全在本件（原 HomeNavigation 消费点随迁）：'tabBar' 档迷你栏
//   圆键 + 'tabItem' 档第四 TabContent 条件挂载与两官方事件接线（assert-session-fab 440
//   组判据读源随迁指本件）。
// · 坑位随迁：页签图标 TabBarSymbol 包 SymbolGlyphModifier（坑11）+ 对象字面量赋值（坑12
//   纯数据类无构造函数）；迷你栏圆键自持材质 out of scope 负向结论与「无按压反馈」申报见
//   TabBarNewConversationKey 注释（原样保留）；内容区背景显式透明（HdsTabs/TabContent 官方
//   默认白底真机实锤）。
import { HdsBarStyle, HdsTabs } from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { ChatSessionList, SESSION_SELECT_MODE_KEY } from '../chat/ChatSessionList';
import { SettingsPage } from '../settings/SettingsPage';
import { AssistantPage } from '../assistants/AssistantPage';
import { PageBackground } from '../../common/PageBackground';
import { TabMoreMenuAnchor } from '../TabMoreMenu';
import { HomeNavActions } from './HomeNavActions';
import { IMMERSIVE_LEVEL_KEY, resolvedHdsMaterialParams } from '../../common/ImmersiveLevel';
import {
  NEW_SESSION_ENTRY_TAB_BAR,
  NEW_SESSION_ENTRY_TAB_ITEM,
  PREF_NEW_SESSION_ENTRY_KEY,
  PREF_TAB_SWITCH_ANIM_KEY,
  resolveNewSessionEntry
} from '../../common/AppPreferences';

// 页签栏旁「新建会话」圆键（vp）：键 56 = 悬浮页签栏默认高（官方 HdsTabs barHeight 默认
// 56vp，迷你栏与页签栏等高 ⇒ 56×56 即正圆）；图标 24 = 官方图标尺寸；键铺满迷你栏折叠宽
// = 整个圆面都是热区，不留 4vp 死环
const TAB_BAR_KEY_SIZE: number = 56;
const TAB_BAR_KEY_ICON_SIZE: number = 24;

// 页签第四项「新建」动作位下标（快捷新建键 'tabItem' 档专属）：仅该档挂载第四 TabContent，
// 其余档页签只到 2、下标 3 不存在，两事件回调对 3 的比较自然空转
const NEW_TAB_ITEM_INDEX: number = 3;

// 页签图标：系统符号须 TabBarSymbol 包 SymbolGlyphModifier（直接传 $r('sys.symbol.xxx')
// 资源不渲染——坑11 实锤）；★坑12：TabBarSymbol 是纯数据类、运行时没有构造函数（new 即
// jscrash「TabBarSymbol is not defined」），必须对象字面量赋值。普通态描边/选中态实心，
// 配色用官方默认值
function tabSymbol(normal: Resource, selected: Resource): TabBarSymbol {
  const symbol: TabBarSymbol = {
    normal: new SymbolGlyphModifier(normal),
    selected: new SymbolGlyphModifier(selected)
  };
  return symbol;
}

// HdsTabs 距屏底高度：官方示例模式「导航指示条高度，无则 32vp」（barBottomMargin
// 默认 0 不自动避让，必须显式传避让区高度；前提 = 全屏窗口）
function tabBarBottomMargin(navBarHeight: number): number {
  return navBarHeight > 0 ? navBarHeight : 32;
}

// 对话页签（官方 BottomTabBarStyle「图标在上、文字在下」布局，verticalAlign 显式官方默认居中）
function chatTabBar(): BottomTabBarStyle {
  return new BottomTabBarStyle(tabSymbol($r('sys.symbol.message'), $r('sys.symbol.message_fill')), '对话')
    .verticalAlign(VerticalAlign.Center);
}

function assistantTabBar(): BottomTabBarStyle {
  return new BottomTabBarStyle(tabSymbol($r('sys.symbol.person'), $r('sys.symbol.person_fill')), '助手')
    .verticalAlign(VerticalAlign.Center);
}

function settingsTabBar(): BottomTabBarStyle {
  return new BottomTabBarStyle(tabSymbol($r('sys.symbol.gearshape'), $r('sys.symbol.gearshape_fill')), '设置')
    .verticalAlign(VerticalAlign.Center);
}

// 第四项「新建」动作位页签（快捷新建键 'tabItem' 档，见 NEW_TAB_ITEM_INDEX）：形制随三页签
//（图标在上文字在下）；plus 无实心变体、两态同图——动作位被 onContentWillChange 拦截永不可
// 选中，选中态符号不会出现
function newTabBar(): BottomTabBarStyle {
  return new BottomTabBarStyle(tabSymbol($r('sys.symbol.plus'), $r('sys.symbol.plus')), '新建')
    .verticalAlign(VerticalAlign.Center);
}

@Component
export struct TabShell {
  // 当前页签（0=助手，1=对话，2=设置）：状态真源在分发器（标题栏域大量消费——tabTitle/
  // 覆盖层守卫/收带判据），本件 @Link 回连；onChange 回写经链路传导
  @Link currentTab: number;
  // 「全部/收藏」分段选中：与分发器标题栏覆盖层共用同一份状态（三级 @Link 链下发
  // ChatSessionList，违例 = 两处各显各的段）
  @Link chatFavSegment: number;
  // 顶部留白（vp，分发器 titleBarInset() 算好下发 = 状态栏 + 标题栏 + 蒙层让位）
  @Prop topInset: number = 0;
  // 页面底部留白（vp，分发器 pageBottomPad() 算好下发 = 避让区高 + 悬浮页签让位）
  @Prop bottomPad: number = 0;
  // 系统避让区高度（vp，分发器透传 Index 异步实测值——悬浮页签距底与批量条定位消费）
  @Prop navBarHeight: number = 0;
  // 官方路由栈（分发器注入同一实例——AssistantPage 三级页 push 共用；@Prop：navBarHeight
  // 异步实测须状态驱动重渲染，坑57 同族，heights 均经 @Prop 下发）
  pathStack: NavPathStack = new NavPathStack();
  // 设置域导航动作（分发器注入同一实例——SettingsPage 约 20 个 onOpenXxx 回调消费）
  actions: HomeNavActions = new HomeNavActions(this.pathStack);
  // 设置页滚动控制器（分发器持引用经 bindToScrollable 绑官方滚动感知——设置带收起状态机
  // 在分发器侧，控制器两处共用同一实例）
  settingsScroller: Scroller = new Scroller();
  // 点会话卡片上行（分发器 openSession：写 activeConvId + push 二级页一步到位）
  onOpenSession: (conversationId: string, presetTitle?: string) => void = () => {
  };
  // 新建会话上行（分发器 newConversation——「更多」菜单/圆键/草稿行三处同此口，多选守卫在彼）
  onNewConversation: () => void = () => {
  };
  // 搜索会话上行（分发器 newSessionSearch——push 独立二级搜索页）
  onNewSessionSearch: () => void = () => {
  };
  // 设置页滚动偏移上行（分发器 onSettingsScrollOffset 状态机——48 收 / 24 复位滞后带）
  onSettingsScrollOffset: (offsetY: number) => void = () => {
  };
  // ── 自持订阅（@StorageProp 同键多订阅 = 项目常态，标题栏域在分发器侧另持同键）──
  // 页签切换动画（true = 横向滑切 300 / false = 点按直达 0）
  @StorageProp(PREF_TAB_SWITCH_ANIM_KEY) tabSwitchAnim: boolean = true;
  // 快捷新建键三档（'tabBar' 迷你栏圆键默认 / 'tabItem' 第四项 / 'float' 悬浮键——第三档
  // 生效面在 ChatSessionList，前两档在本件；判据经 resolveNewSessionEntry 归一）
  @StorageProp(PREF_NEW_SESSION_ENTRY_KEY) newSessionEntry: string = NEW_SESSION_ENTRY_TAB_BAR;
  // 沉浸光感档位（悬浮页签材质 systemMaterialEffect 消费）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 会话多选中（barBottomMargin 巨值把悬浮胶囊推出视口，批量条独占其位）
  @StorageProp(SESSION_SELECT_MODE_KEY) sessionSelectMode: boolean = false;

  // 底部页签迷你栏「新建会话」圆键（★ 快捷新建键，决明拍板页签栏旁档）。载体 = 官方
  // HdsTabs 迷你栏（barFloatingStyle.miniBar——官方「迷你栏跟页签栏高度相等且水平对齐」，
  // 圆底与材质由迷你栏背景跟随页签栏给出），本键只画透明热区 + 符号，不垫任何自绘底色。
  // ★ 真机实锤：键自身 systemMaterial 在 HdsTabs 底栏内 out of scope（材质整个消失——官方
  // 生效区不含该位置）⇒ 材质回退由迷你栏背景承担（光感在）；官方触摸光晕属材质内部能力
  // 拿不到，clickEffect 缩放真机看不出 ⇒ 本键**无按压反馈**，如实申报。图标取官方次要图标色
  //（页签未选中项同为灰）。★ 必须组件内 @Builder（坑30）；动作走 onNewConversation 上行
  //（多选中页签栏整体推出视口，圆键随之下线）
  @Builder
  TabBarNewConversationKey() {
    Button() {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(TAB_BAR_KEY_ICON_SIZE)
        .fontColor([$r('sys.color.icon_secondary')])
    }
    .type(ButtonType.Circle)
    .width(TAB_BAR_KEY_SIZE)
    .height(TAB_BAR_KEY_SIZE)
    .padding(0)
    .backgroundColor(Color.Transparent)
    // 材质生效时开原生按压会叠色（坑58）⇒ stateEffect 关；本键无按压反馈（理由见上）
    .stateEffect(false)
    .accessibilityText('新建会话')
    .onClick((): void => {
      this.onNewConversation();
    })
  }

  build() {
    // 统一页面背景垫底：背景在 Tabs 外层单实例常驻——懒加载/重建 TabContent 不闪；二级页
    // push 覆盖整个导航（含本背景）。homeTab = true：一级页签常驻实例冷启动「纯色→壁纸」
    // 改 200ms 渐显（单实例只播一次，切页签不重挂；时长分档口径见 PageBackground homeTab
    // 注释）
    Stack() {
      PageBackground({ homeTab: true })
      // 两页签更多菜单隐形锚点（openMenu TargetInfo；全高层 + HitTest.None 穿透）
      TabMoreMenuAnchor({ topInset: this.topInset })
      HdsTabs({ index: this.currentTab }) {
        TabContent() {
          AssistantPage({
            topPad: this.topInset,
            bottomPad: this.bottomPad,
            pathStack: this.pathStack
          })
        }
        // 内容区背景显式透明（HdsTabs/TabContent 官方默认白底，真机实锤——下同）
        .backgroundColor(Color.Transparent)
        .tabBar(assistantTabBar())
        TabContent() {
          ChatSessionList({
            topPad: this.topInset,
            bottomPad: this.bottomPad,
            barBottom: this.navBarHeight + 16,
            // 「全部/收藏」分段状态（标题栏覆盖层与悬浮层共用——@Link 链中转）
            favSegment: $chatFavSegment,
            onOpen: (conversationId: string, presetTitle?: string): void => {
              this.onOpenSession(conversationId, presetTitle);
            },
            // 新会话合成行点击：走新建链（多选中忽略守卫在分发器 newConversation 内）
            onOpenNewSession: (): void => {
              this.onNewConversation();
            }
          })
        }
        // 内容区背景显式透明（同上）
        .backgroundColor(Color.Transparent)
        .tabBar(chatTabBar())
        TabContent() {
          SettingsPage({
            topPad: this.topInset,
            bottomPad: this.bottomPad,
            // 滚动联动三件套之两件：控制器（分发器 bindToScrollable 共用）与偏移上抛
            //（带收起状态机在分发器 onSettingsScrollOffset）
            scroller: this.settingsScroller,
            onScrollOffset: (yOffset: number): void => {
              this.onSettingsScrollOffset(yOffset);
            },
            onOpenProvider: (): void => {
              this.actions.pushProvider();
            },
            onOpenInfo: (): void => {
              this.actions.pushInfo();
            },
            onOpenPrompts: (): void => {
              this.actions.pushPrompts();
            },
            onOpenSkillLibrary: (): void => {
              this.actions.pushSkillLibrary();
            },
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
            onOpenTools: (): void => {
              this.actions.pushTools();
            },
            onOpenWorkspace: (): void => {
              this.actions.pushWorkspace();
            },
            onOpenMount: (): void => {
              this.actions.pushMount();
            },
            onOpenNetwork: (): void => {
              this.actions.pushNetwork();
            },
            onOpenWebService: (): void => {
              this.actions.pushWebService();
            }
          })
        }
        .backgroundColor(Color.Transparent)
        .tabBar(settingsTabBar())
        // 页签第四项「新建」动作位（★ 快捷新建键 'tabItem' 档）：不承载页面——内容空栈 +
        // 透明底，onContentWillChange 拦截一切切入（点按/横滑/键盘，官方契约 return false
        // 不切换），onTabBarClick 接既有新建链。挂载门控经归一（脏值 = 缺省 'tabBar'，与
        // 偏好页显示段一致），非该档不挂 = 页签栏回纯三页签；动作位不可选中 ⇒ currentTab
        // 恒 0~2，标题栏/菜单分支零改动
        if (resolveNewSessionEntry(this.newSessionEntry) === NEW_SESSION_ENTRY_TAB_ITEM) {
          TabContent() {
            Stack() {
            }
          }
          .backgroundColor(Color.Transparent)
          .tabBar(newTabBar())
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      // 悬浮三件套（官方示例模式）+ 项目行为：点按切换动画（tabSwitchAnim 键——
      // animationDuration 显式 300 = 官方通用默认时长，官方语义 BottomTabBarStyle 下
      // 不设默认 0 仍无动画，必须显式正值；关 = 0 点按直达）。官方 tabs.d.ts 与 HdsTabs
      // API 参考双源实证：animationDuration 只管点按与 changeIndex 切换动画时长，
      // TabContent 内滑动翻页动画走 interpolatingSpring 内参
      .barOverlap(true)
      .vertical(false)
      .barPosition(BarPosition.End)
      // 横滑翻页恒关（scrollable 官方默认 true，显式 false 压掉——仅点按切换）：原
      // 「页签横滑切换」偏好已随 2026-10-31 拍板整键退役——开横滑与对话页会话卡侧滑
      // 五键（SessionSwipeItem PanGesture Horizontal，规范 §4.18）同轴竞争真机实锤，
      // 官方仲裁对该形态无明文背书，兜底删除；恢复 = 重立偏好键走新笔（变更记录
      // 两千零三十八节）
      .scrollable(false)
      .animationDuration(this.tabSwitchAnim ? 300 : 0)
      .onChange((index: number) => {
        this.currentTab = index;
      })
      // 第四项动作位两事件（★ 'tabItem' 档；官方 HdsTabs 事件，6.0.0(20) 起，与官方文档
      // 核对过——onContentWillChange 覆盖点按/横滑/键盘全部切入路径，false = 不切换）：
      // 点第四项触发新建（onNewConversation 上行，多选守卫在分发器，页签高亮不动）+ 拦截
      // 一切入第四项的切页。非 'tabItem' 档第四项不挂载、下标 3 不存在，两回调自然空转；
      // onTabBarClick 对其余页签点击是空操作（下标比 3 不中）
      .onTabBarClick((index: number) => {
        if (index === NEW_TAB_ITEM_INDEX) {
          this.onNewConversation();
        }
      })
      .onContentWillChange((currentIndex: number, comingIndex: number): boolean => {
        return comingIndex !== NEW_TAB_ITEM_INDEX;
      })
      // 悬浮样式定稿：距底避让（全屏窗口下 = 避让区高，坑1 配方）/ 材质一个字段接管 /
      // gradientMask 关闭（决明定稿；恢复官方默认删该字段）。会话多选中 barBottomMargin
      // 巨值把悬浮胶囊推出视口（1000vp 远超任何机型屏高，胶囊连同触摸热区一起离屏，
      // 批量条不受残留热区遮挡），退出多选恢复定稿值——dshinhm 同款（barHeight 改值/
      // attributeModifier 两替代案真机均实证失败后废弃）
      .barFloatingStyle({
        barBottomMargin: this.sessionSelectMode ? 1000 : tabBarBottomMargin(this.navBarHeight),
        systemMaterialEffect: resolvedHdsMaterialParams(this.immersiveLevel),
        gradientMask: { maskColor: Color.Transparent },
        // 迷你栏（★ 快捷新建键）：官方「胶囊旁并列独立区域」唯一插槽。取值理由——
        // ① miniBarStyle: COLLAPSE 钉折叠态（该字段仅 HdsTabs 宽度 <600vp 生效，手机
        // 竖屏即此档）；② miniBarWidth 三档同值 56 兜住 ≥600vp 的官方强制展开态（MEDIUM
        // 平板全宽档）——展开宽 = 折叠宽，状态切换视觉恒等，不会长成一条空胶囊；③ 不设
        // barLayoutMode（官方默认即左右布局）；④ 不设 enableMiniBarBackground（默认
        // true = 跟随页签栏背景 ⇒ 圆底与光感同源自带）。'float' / 'tabItem' 档 ⇒
        // undefined（前者页签栏回纯三页签，后者页签栏带第四项「新建」动作位）；判据经
        // resolveNewSessionEntry 归一（脏值 = 缺省 'tabBar'，与偏好页显示段一致）
        miniBar: resolveNewSessionEntry(this.newSessionEntry) === NEW_SESSION_ENTRY_TAB_BAR ? {
          miniBarBuilder: (): void => {
            this.TabBarNewConversationKey();
          },
          miniBarStyle: HdsBarStyle.COLLAPSE,
          miniBarWidth: {
            smallWidth: TAB_BAR_KEY_SIZE,
            mediumWidth: TAB_BAR_KEY_SIZE,
            largeWidth: TAB_BAR_KEY_SIZE
          }
        } : undefined
      })
    }
    .width('100%')
    .height('100%')
  }
}
