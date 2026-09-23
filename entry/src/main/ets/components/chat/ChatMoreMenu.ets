// 聊天页菜单层（2026-08-29 对话页 UI 对齐任务 3 自 dshinhm ChatMoreMenu **去 kap 改写**；
// 2026-09-14 消息气泡底栏笔扩为两菜单：页面「更多」+ 消息「更多」，同基类同纪律见文末）
// ：官方全局菜单 openMenu（@since 18）的内容构建与弹出——**姿势沿用原因**：HDS 路径
// 的「更多」键自二百二十七起虽是覆盖层内自绘 Button（可挂 bindMenu 了），但菜单弹出与关闭
// 语义（锚点几何、每次弹出前按当前深浅色重建 ComponentContent、材质 REGULAR 基准）已按
// openMenu + 页面内隐形锚点调稳，换 bindMenu 属行为变更，非需求不动（回退路径的「更多」
// 仍是系统渲染层菜单项，只有 icon + action 回调，本就挂不了 bindMenu；Menu 组件无编程式
// 弹出 API）——官方「无 UI 组件场景弹菜单」姿势 = openMenu + 隐形锚点组件做 target
//（锚点组件见 ChatPageContent.ets ②层；几何常量 MORE_MENU_ANCHOR_RIGHT /
// MORE_MENU_BUTTON_BOTTOM_INSET 见 common/Theme.ets）。
// 去 kap 改写：菜单项 = 「刷新」（重拉历史消息 + 重读连接配置）+「新建会话」（跳转，
// 会话行懒创建）；dshinhm 的「工作区选择」是 kap 语义裁除。
// ★ 2026-09-19 联网开关迁入（决明指令「全按官方，需要自绘的就不做」，原输入框联网 chip
// 退役）：新增「联网」项——可用时点开**官方二级菜单**（MenuItem builder 子菜单，开启/关闭
// 两档打勾；官方指南触发达二级菜单只写鼠标 hover，触屏点击展开为真机验证项），不可用时
// 点击出指引 toast（原 chip 置灰提示语义，文案与分派逻辑随迁 ChatPage）。★ 子菜单 builder
// 形态 = 页内 @Builder 方法经回调载体传入（ChatMoreMenuCallbacks.webSubMenu）——坑51/62
// 口径「CustomBuilder 位挂组件内 @Builder 方法，lambda 直调全局 @Builder 运行时闪退」，
// 本文件 ChatMoreMenuBuilder 是全局 builder（无组件实例可挂方法），故由消费方 ChatPage
// 持有子菜单 builder 传入（titleBarStack → PageShell 同款已证形态）。菜单项状态 = 弹出一刻
// 的快照（refreshDisabled 同款纪律——节点每次弹出前重建）。图标 = sys.symbol.magnifyingglass
//（search_web 工具页同形，SDK sysResource 编译期名称表实锤；globe/network 等裸名不存在）。
// ★ 2026-09-19 决明拍板换官方堆叠展开：真机验收 SIDE_EXPAND 二级面板无动画反馈（一级弹
// 出是文档明写的弹簧曲线，二级树内瞬间展开无动画参数——transition 字段仅在一级
// ContextMenuOptions/PopupOptions），改挂 subMenuExpandingMode(STACK_EXPAND)——官方
// 枚举（API 12）「子菜单浮于主菜单上方展开」，系统默认展开符号 chevron_forward 自带
// 90° 顺时针旋转动效（官方 subMenuExpandSymbol 文档实锤；默认符号够用不引 API 20 自定义）。
// 无状态：内容节点由 ChatPage 创建/持有/销毁——每次弹出前重建（ComponentContent 固化
// UI 树不随深浅色切换，坑69 家族）、aboutToDisappear dispose 成对释放。
import { ComponentContent, uiMaterial, SymbolGlyphModifier } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { AppMenuHost } from '../../common/AppMenuHost';
import { resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { menuDividerColor } from '../../common/Theme';
import { PREF_SEARCH_SERVICE_ENABLED_KEY } from '../../common/AppPreferences';
import { CHAT_WEBSEARCH_ALLOWED_KEY } from './ChatParamChipBar';

// 菜单回调（openMenu 的 ComponentContent 参数载体：全局 @Builder 无法访问组件实例，
// 回调经参数传入）
export interface ChatMoreMenuCallbacks {
  // 刷新：重拉历史消息 + 重读连接配置（接 ChatPage loadHistory/reloadConn）
  onRefresh: () => void;
  // 新建会话：replacePath 跳转新会话（2026-08-29 懒创建——不建行、不广播，列表零变化；
  // 原注释「建行 + 广播」为 dshinhm 旧语义残留，2026-09-04 勘误）
  onNewSession: () => void;
  // ★ 2026-09-15 流式禁用（决明指令）：true = 流式中，刷新项置灰不可点——菜单节点每次弹出
  // 前重建（open 传当时值），快照即弹出一刻的流式态；新建会话不受影响
  refreshDisabled: boolean;
  // ★ 2026-09-19 联网开关迁入（原输入框 chip，语义不变）：webSearchEnabled = 可用性快照
  // （总开关开 且 助手启用联网——false = 「联网」项无二级菜单，点击走 onWebSearchDenied
  // 指引 toast）；onPickWebSearch = 选择上行（写本会话覆盖，落点 ChatPage.onPickWebSearch）；
  // webSubMenu = 二级菜单 builder——页内 @Builder 方法经此传入（坑51/62 形态约束与快照
  // 纪律见文件头注释）。★ 二级菜单打勾快照经 webSubMenu 闭包参数传入 WebSearchMenu.on，
  // 本接口不设其字段——2026-09-20 D6-1 清死字段（原 webSearchOn 声明 + 调用点注入零消费）
  webSearchEnabled: boolean;
  onPickWebSearch: (on: boolean) => void;
  onWebSearchDenied: () => void;
  webSubMenu: CustomBuilder;
  // ★ 2026-09-19 会话统计项（SessionStatsSheet 半模态）：statsEnabled = 可见性快照
  // （false = 隐私会话——全程零落库，库侧统计恒全零，显示全零面板是误导，入口整项隐藏）；
  // onOpenStats = 点击上行（落点 ChatPage.openStatsSheet）
  statsEnabled: boolean;
  onOpenStats: () => void;
  // ★ 2026-09-23 上下文用量菜单项撤回（决明口径「只留输入框环形入口」——与
  // docs/归档/任务书-归档-03 会话上下文用量方案 §4.3「输入条圆环（已拍板落点）」同源）：
  // 原 usageEnabled/onOpenUsage 两字段删（当日上下文压缩笔按任务书 §3.3 加过一枚「上下文用量」
  // 项，同日撤除）；用量面板仍由输入条圆环（主入口）与压缩摘要轻提示行两处可达
}

// 「更多」菜单锚点 id（openMenu 的 TargetInfo 定位目标组件，页面内唯一）
export const CHAT_MORE_MENU_ANCHOR_ID: string = 'chatMoreMenuAnchor';

// ═══ 联网开关域（★ 2026-09-19 迁入笔随域收拢）═══
// 「联网」项的可用性判定、指引 toast 与二级菜单本体三件从 ChatPage / 原 ChatParamChipBar
// 随形并入本件——反碎片下限②（并入既有同域文件优先于新开）：联网开关的 UI 面现整体归属
// 「更多菜单」域（项形态在本件 Menu builder、子菜单组件与两帮助函数在此），ChatPage 只留
// 组件内 @Builder 壳（坑51/62 形态要求）+ 写库落点 onPickWebSearch（本笔未动的既有域）。
// ChatPage 剔头越 1200 硬线即本笔的拆分项（见变更记录）。
// · 可用性 = 总开关开 且 助手启用联网（两源合一，原 chip webEnabled 口径）——弹出一刻经
//   AppStorage 现读（open 前重建节点，值即当时值；不设 @StorageProp——两值不驱动 UI，
//   状态最小化红线）。
// · 图标 = sys.symbol.magnifyingglass（search_web 工具页同形；SDK sysResource 编译期
//   名称表实锤，globe/network 等裸名不存在）；尾部展开符号走 STACK 模式系统默认（文件头）。

// 联网可用性现读（两源合一）：true = 更多菜单「联网」项挂二级菜单 / false = 点击出指引
export function webSearchEnabledNow(): boolean {
  return (AppStorage.get<boolean>(PREF_SEARCH_SERVICE_ENABLED_KEY) ?? true) &&
    (AppStorage.get<boolean>(CHAT_WEBSEARCH_ALLOWED_KEY) ?? true);
}

// 「不可用」指引 toast（原 ChatParamChipBar.notifyWebOff 原样搬迁——总开关优先呈现：它是
// 更外层的不可用原因，助手清单再开也无法联网，见帮助条目同口径）
export function notifyWebOff(uiContext: UIContext): void {
  uiContext.getPromptAction().showToast({
    message: (AppStorage.get<boolean>(PREF_SEARCH_SERVICE_ENABLED_KEY) ?? true) ?
      '当前助手未启用联网搜索，可在助手编辑页的工具调用中开启' :
      '联网搜索总开关已关闭，可在设置的联网搜索页打开'
  });
}

// 联网二级菜单本体（原 chip 两档菜单随形迁入——两档 = **本会话**的开启/关闭，「开启」=
// 清本会话覆盖跟随助手、「关闭」= 写本会话覆盖，选择经 onPick 上行页面 onPickWebSearch）。
// 组件形态（ThinkingMenu 同款先例）= 页面 @Builder 壳可实例化的共享菜单体；打勾态按 on
// 快照（菜单节点每次弹出前重建，值参快照语义）
@Component
export struct WebSearchMenu {
  // 弹出一刻的本会话生效值（页面壳传入）
  @Prop on: boolean;
  // 档位选择回调（页面落本会话覆盖）
  onPick: (on: boolean) => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  build() {
    Menu() {
      MenuItem({ content: '开启' })
        .selected(this.on)
        .selectIcon(true)
        .onClick(() => {
          this.onPick(true);
        })
      MenuItem({ content: '关闭' })
        .selected(!this.on)
        .selectIcon(true)
        .onClick(() => {
          this.onPick(false);
        })
    }
    .menuItemDivider({
      color: menuDividerColor(this.appColorMode),
      mode: DividerMode.EMBEDDED_IN_MENU
    })
  }
}

// 「更多」菜单内容（官方 Menu 组件，openMenu 的 ComponentContent 载体）：
// 宽度不设——官方默认按内容自适应（右缘对齐「更多」按钮由 placement 保证）；
// 图标为官方系统符号（HMSymbolVF.ttf 字形，dshinhm 核字形存在性：arrow_clockwise /
// plus——坑72 口径：sys.symbol.image/document 等不存在，选用前先核字形表）
@Builder
export function ChatMoreMenuBuilder(params: ChatMoreMenuCallbacks) {
  Menu() {
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_clockwise')), content: '刷新' })
      // ★ 2026-09-15 流式禁用（决明指令）：流式中刷新项置灰——.enabled 为官方通用属性
      //（「禁用控制」ts-universal-attributes-enable，MenuItem 支持通用属性，官方文档实查）；
      // 快照语义 = 弹出一刻的流式态（置灰后点击由系统拦截不派发，页面侧另有兜底守卫）
      .enabled(!params.refreshDisabled)
      .onClick(() => {
        params.onRefresh();
      })
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.plus')), content: '新建会话' })
      .onClick(() => {
        params.onNewSession();
      })
    // ★ 2026-09-19 联网开关迁入：单项双态——builder 传 undefined = 不设（官方「默认不显示
    // 二级菜单」）；点击守卫分派：有子菜单时点击由系统接管展开（守卫使 onClick 空转），
    // 无子菜单时出指引 toast。子菜单形制见 ChatPage.WebSearchSubMenu。
    // 尾部展开符号不手动配（原 SIDE_EXPAND 期手动补过 chevron_right）——STACK 模式系统
    // 默认在带 builder 的项尾显示展开符号（chevron_forward，旋转 90° 动效），手动再配
    // 会双箭头叠加。不可用时无 builder，系统不显示展开符号，项尾自然无箭头
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.magnifyingglass')),
      content: '联网',
      builder: params.webSearchEnabled ? params.webSubMenu : undefined })
      .onClick(() => {
        if (!params.webSearchEnabled) {
          params.onWebSearchDenied();
        }
      })
    // ★ 2026-09-19 会话统计项（末位——只读信息面板不与动作项抢位置）：隐私会话整项隐藏
    //（口径见 callbacks.statsEnabled 注释）；图标 = sys.symbol.data_proportion（会话统计
    // 语义；SDK loader sysResource symbol 段实名核过——chart 系裸名〔chart_bar/chart_pie/
    // gauge〕不存在，坑72 两步核验法第一步已过，构建绿为第二步终证）
    if (params.statsEnabled) {
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.data_proportion')),
        content: '会话统计' })
        .onClick(() => {
          params.onOpenStats();
        })
    }
    // ★ 2026-09-23 上下文用量菜单项撤回（决明口径「只留输入框环形入口」——入口史与理由见
    // callbacks 接口注释；原「末位——与「会话统计」同族只读信息面板」一项整段删除，菜单
    // 不含此项后本菜单项序回到：新会话/联网/会话统计）
  }
  // ★ 2026-09-19 官方堆叠展开（决明拍板，缘起见文件头）：subMenuExpandingMode 是 Menu 级
  // 属性（作用于本菜单所有带 builder 的项；本菜单仅「联网」项有子菜单），挂一级 Menu——
  // 消息菜单无子菜单项不涉及
  .subMenuExpandingMode(SubMenuExpandingMode.STACK_EXPAND)
  // 官方菜单项分割线标准姿势（menuItemDivider 默认不显示须显式设置；mode 必须
  // EMBEDDED_IN_MENU——FLOATING 悬浮层被菜单项盖住不可见；颜色走公共入口
  // menuDividerColor 深浅色分治；全局 @Builder 无组件实例，深浅色直接读 AppStorage——
  // 菜单节点每次弹出前重建，读取始终为当前深浅色）
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 「更多」菜单节点宿主（2026-08-30 反馈轮 13 起为 AppMenuHost 薄壳——节点生命周期与
// 弹出组装在基类，本壳只实现 buildNode 与便捷 open（材质解析 + 锚点 id），页面侧
// init/open/dispose 调用零变化）
export class ChatMoreMenuHost extends AppMenuHost<ChatMoreMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: ChatMoreMenuCallbacks): ComponentContent<ChatMoreMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(ChatMoreMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出菜单（基类弹前重建——按当前深浅色/材质重新构建 UI 树；材质 REGULAR 基准随
  // 沉浸光感总档在此解析，页面侧只传档位值）
  open(uiContext: UIContext, callbacks: ChatMoreMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, CHAT_MORE_MENU_ANCHOR_ID,
      // ★ 第三参 true = 交互形变 + 触点流光（2026-09-18 菜单光感笔；官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true));
  }
}

// ═══ 消息「更多」菜单（2026-09-14 消息气泡底栏任务书 §2.5，并入本文件而非新开域件——
// 反碎片下限②：与页面「更多」同域〔聊天页 openMenu 菜单，同一宿主基类、同一消费方
// ChatPage、同一深浅色重建纪律〕，菜单内容差异仅在 builder 两项）═══
// 本期两项均为占位（拍板 3：键位 A——更多菜单内放分支与删除；点击 toast 暂未开放，照
// onRetryTurn 占位先例）；真实现各属独立任务（任务书 §1.4 不做项①②——删除/分支）。
// ⚠ 锚点在 LazyForEach 列表项内（既有六域锚点均在固定卡片上）——列表滚动中弹菜单/
// 菜单开着时项滚出视口/项回收后重弹三态为真机验证项（任务书 §2.5）；失败路径基类
// show 已 catch + hilog 不静默

// 消息菜单锚点 id 前缀（openMenu TargetInfo 定位目标 = 气泡底栏「更多」键：
// .id(前缀 + 消息 id)，照 SESSION_CARD_MENU_ID_PREFIX 先例；前缀与本 host 拼接同源）
export const MESSAGE_MENU_ANCHOR_PREFIX: string = 'chatMsgMenu_';

// 消息菜单回调（占位期两动作只 toast——回调经参数注入，真实现接手时改 ChatPage 注入即可）
export interface ChatMessageMenuCallbacks {
  // 「创建分支」占位（真实现属分支功能独立立项）
  onBranch: () => void;
  // 「删除消息」占位（真实现属删除功能独立一笔）
  onDeleteMsg: () => void;
}

// 消息「更多」菜单内容（形制照会话卡菜单先例 = 普通 MenuItem；删除项本仓先例不用红字
// ——Cube 侧红字形态本仓无先例，观感待定项登记变更记录不预写）
@Builder
export function ChatMessageMenuBuilder(params: ChatMessageMenuCallbacks) {
  Menu() {
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.message_badge_plus')),
      content: '创建分支' })
      .onClick(() => {
        params.onBranch();
      })
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')),
      content: '删除消息' })
      .onClick(() => {
        params.onDeleteMsg();
      })
  }
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 消息「更多」菜单节点宿主（AppMenuHost 薄壳；open 按消息 id 拼锚点——callbacks 由
// ChatPage 在点击一刻构造，可闭包捕获该消息上下文）
export class ChatMessageMenuHost extends AppMenuHost<ChatMessageMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: ChatMessageMenuCallbacks): ComponentContent<ChatMessageMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(ChatMessageMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出菜单（msgId = 目标消息 id，锚点 = 气泡底栏「更多」键；材质同页面「更多」菜单）
  open(uiContext: UIContext, callbacks: ChatMessageMenuCallbacks, msgId: string,
    immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, MESSAGE_MENU_ANCHOR_PREFIX + msgId,
      // ★ 第三参 true = 交互形变 + 触点流光（2026-09-18 菜单光感笔；官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true));
  }
}
