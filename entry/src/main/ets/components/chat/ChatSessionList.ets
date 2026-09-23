// 会话列表页（2026-08-29 M2a 领导指令：对话页签 = 历史会话列表，点卡片经官方路由 push
// 对话页——输入栏随对话页全屏覆盖页签，输入框与悬浮页签的底部避让冲突从结构上消除，
// dshinhm ChatTab/KimiSessionList 同款架构不搬本体）。数据 = ChatDb conversations 表
//（每次收发 touch updatedAt，列表时间序即真实最近使用序）。
// ★ 2026-09-04 二级修正（决明两点）：①一级页 HdsNavigation 下 List 兼容坑（dshinhm
// 2026-08-20 真机实锤「顶蒙层点不了滑不动」）——一级页禁 List 沉淀，容器回 Scroll+Column
// +ForEach；②本地 RDB 全量查询拍板——删 QUERY_TAIL_LIMIT 50 上限与滚动加载分页链
//（SessionDataSource/游标查询/onReachEnd/到底闸全撤——本地库一次查全量毫秒级，dshinhm
// 服务端分页是远程协议必然，无此约束）。此前 List 化的两真机回归（卡片偏左/标题栏分割线
// 无光感，坑9 族）随回退一并消除，备忘见 SessionCardItem 卡宽注释。
// ★ 2026-09-01 会话绑定助手：列表 = 当前助手名下（reload 读 ACTIVE_ASSISTANT_KEY 过滤，
// 切换助手后经 SESSION_LIST_RELOAD_KEY 广播重拉即变）。
// 空态卡（2026-08-31 任务 C）：列表空（首拉完成 loaded 且 rows 空、无失败提示）→ 全高
// 居中「该助手暂无会话」次要色（dshinhm 同款形态；细则见 build 内注释）。
// 刷新通道：Tab 内容无 onShown 生命周期（dshinhm 同款结论）——对话页 pop 后由宿主
// NavDestination.onDisappear 自增 reloadTick（@Prop @Watch 消费）重拉列表。
// ★ 多选模式（2026-08-29 会话多选删除，交互与 dshinhm KimiSessionList 二二一改同款——
// 官方 Checkbox 右侧勾选圈/点击卡片切换勾选/底部批量条悬浮 HitTestMode.Transparent 容器
// 空白区触摸穿透）：「对话」页签更多菜单「多选」进入（AppStorage 一次性指令计数器下发，
// HomeNavigation→本组件零透传——坑3 口径；键常量本文件导出）；勾选后「删除 N」→ 确认
// 弹窗（彻底删除不可恢复，CustomDialogController + ConfirmDialog——机制选型根因见
// ConfirmDialog.ets 文件头：TabContent 槽内 showAlertDialog 真机不弹，坑64 族；取消左/
// 删除右通讯红）→ ChatDb.deleteConversations 事务级联删消息+会话行 → 成功本地
// 移除 + toast + 退出多选；失败 toast 且保留选择可重试（P0-1）。多选中点击卡片不再进
// 会话；ForEach 键含选中态后缀（dshinhm 归档页同款——键变即重建刷新勾选圈）。
// 多选中广播 SESSION_SELECT_MODE_KEY（持续状态非一次性）——宿主 HomeNavigation 消费收起
// 悬浮页签（dshinhm 二二二改/二二四改：避免页签与批量条重叠，HdsTabs barBottomMargin
// 巨值推出视口，退出恢复定稿值）。
// ★ 卡片菜单（2026-08-31 领导指令：长按弹菜单改卡片右侧更多键点击，功能不变——服务商卡
// 四点键同款）：卡片右缘四点键点击 → 官方 openMenu（SessionCardMenu 域件——自 dshinhm
// KimiSessionMenu 同处改写，bindContextMenu 真机不弹的回归教训在案）；菜单项 = 删除/重命名。
// 删除 = 确认弹窗 + deleteConversations 事务级联（同多选删除链路，机制选型见 ConfirmDialog.ets
// 文件头）；重命名 = InputDialog 弹窗（dshinhm 一八二改同款，verbatim 迁入）+ renameConversation
// 直写（不动 updatedAt 时间序）→ 重拉列表；多选中菜单键隐藏（原长按禁用守卫语义）。
// ★ 2026-09-01 反碎片并回：SessionCardItem.ets（会话卡片）+ SessionCardMenu.ets（卡片
// 菜单）并入——两件均本文件单消费方、同域「会话列表卡片」，原拆分动因 = 本文件当年触
// 400 旧红线，宪法修订（600 软引导 / 1000 硬线 + 反碎片下限）后按「并入既有同域文件
// 优先」复归（卡片与菜单域内单消费方，动作执行仍归本页回调）。
// ★ 加密会话（2026-09-04 决明指令）：卡片更多菜单「加密会话/解除加密」→ 官方生物识别
//（userAuth.getUserAuthInstance——封装在 common/BiometricGate.ets，接口/权限/信任级
// 查证依据见其头注释）→ 通过落 conversations.locked（DB v16，ChatDb.setConversationLocked，
// 不动 updatedAt 时间序）；带锁卡片点击进入前同样需通过认证（每次进入都验证，不维持
// 解锁态）。只改进入门禁，会话产生/消息读写/存储链路零改动；锁标在卡片时间左侧
//（sys.symbol.lock）；ForEach 键含锁定态后缀——开关锁即键变重建刷标。
// ★ 会话搜索与收藏（2026-09-08 任务书-会话搜索与收藏-20260907 执行；同日改版：决明指令
// 「会话搜索要同设置搜索一样点击 push 二级页，之前全都放一级页了改」——搜索功能全量迁
// 独立二级页 SessionSearchPage.ets，本页只留收藏）：
// ①收藏 = DB v19 favorite 列——卡片菜单「收藏/取消收藏」（追加于加密项后）+ 卡片星标
//（锁标同区、仅收藏卡显示）+ 标题栏下「全部/收藏」分段过滤（ProviderPage 悬浮吸顶形制逐
// 参数同款）；收藏不改时间排序（updatedAt 零新写点）。
// ②搜索 = 对话页签标题栏搜索键（三键最左）→ push SessionSearchPage（HomeNavigation.
// newSessionSearch——搜索范围 = 当前助手名下全部会话标题，与分段叠加语义随迁页作废）。
// 本页搜索域（一级页内嵌搜索态：展开指令 SESSION_SEARCH_CMD_KEY/搜索框行/记录区/query
// 过滤/顶让位/焦点管理）全量退役，明细见 git diff 与变更记录一百零九节。焦点结论（官方
// 查证 2026-09-08）留档备查：defaultFocus 仅对路由页/模态容器「新进入首次」生效（d.ts:
// 18823 限定 Page/NavDestination/Dialog 族 + FAQ faqs-arkui-1501 场景一），TabContent 内
// 动态挂载不适用——搜索迁路由二级页后 defaultFocus 语义直接可用，原 requestFocus hack
//（FAQ 场景二）随迁退役。最近进入记录点保留于本页 handleOpenCard（列表页点卡进入仍记
// ——键/上限/函数见 common/SessionSearch.ets，另一记录点 = SessionSearchPage.openConv）。
import { ComponentContent, LengthMetrics, SegmentButtonV2Items, uiMaterial, SymbolGlyphModifier } from '@kit.ArkUI';
import {
  HdsListItemCard, PrefixIcon, SuffixCustomBuilder
} from '@kit.UIDesignKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ConversationRow, deleteConversations, queryConversations,
  renameConversation, setConversationFavorite, setConversationLocked, whenReady } from '../../common/store/ChatDb';
import { CONV_TITLE_TICK_KEY } from '../../common/TitleGen';
import { biometricGate, BiometricGateOutcome, BiometricGateResult, gateOutcomeMessage } from '../../common/BiometricGate';
import { PREF_SESSION_ICON_KEY, PREF_SESSION_TIME_KEY } from '../../common/AppPreferences';
import {
  ACTIVE_ASSISTANT_KEY, ASSISTANT_DEFAULT_ID, historyFilterIds
} from '../../common/store/AssistantDb';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor,
  menuDividerColor } from '../../common/Theme';
import { IMMERSIVE_LEVEL_KEY, overlayMaterial, resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { recordSessionRecentConv } from '../../common/SessionSearch';
import { PROACTIVE_UNREAD_CONV_KEY } from '../../common/ProactiveGen';
import { formatConvTime } from './SessionSearchPanels';
import { SegmentBar } from '../SegmentBar';
import { AppMenuHost } from '../../common/AppMenuHost';
import { SessionMultiselectBar } from './SessionMultiselectBar';
import { ConfirmDialog } from './ConfirmDialog';
import { InputDialog } from './InputDialog';

// 会话列表刷新广播键（一次性计数器，勿持久化）：写点 = 对话页离页（ChatPage.aboutToDisappear
// ——新建/改行后广播）、本组件两条删除链成功支（deleteOne / deleteSelected——★ 2026-09-20
// 复验轮补：删行发生在对话页签列表内、不经对话页，此侧原零写点）、助手页切/删助手、备份恢复
// （DataSyncPage）、主动消息落库（ProactiveGen）；消费方 = 本组件 + 助手页卡面「会话 N」chip
// + 会话搜索页，各自 @Watch 重拉。走 AppStorage 广播而非 @Prop 透传——2026-08-29 真机实测
// @Prop 计数器经 HdsTabs/TabContent 多层未传导（返回后时间序不刷新，冷启动数据正确），
// dshinhm 多选指令同款 AppStorage 姿势与组件树层级无关
export const SESSION_LIST_RELOAD_KEY: string = 'sessionListReloadTick';
// 多选进入指令键（一次性计数器，勿持久化——计数器形态防同值不触发，@Watch 只在值变化
// 时回调）：发布方 = HomeNavigation（更多菜单「多选」项），消费方 = 本组件 @StorageProp
// @Watch
export const SESSION_MULTISELECT_CMD_KEY: string = 'sessionMultiselectCmd';
// 多选状态广播键（bool，持续状态非一次性——勿 persistProp）：本组件写入，宿主
// HomeNavigation 消费收起悬浮页签（HDS 路径 barBottomMargin 巨值/回退路径隐藏 BottomTabBar）
export const SESSION_SELECT_MODE_KEY: string = 'sessionSelectMode';

// 滚动内容顶部让位常量（vp）：分段悬浮层 = 官方背板高 40（SegmentBar 头注释 resources
// 实锤 segment_button_v2_singleline_background_height）+ 上间隙 8（margin 已含 topPad-8，
// 此处补带高与下间隙）= 48。微调以真机首卡不遮挡为准（任务书 §2.3），微调值记变更记录
const SEGMENT_TOP_CLEARANCE: number = 48;

// ═══ 会话卡片（2026-08-30 自本页拆出、2026-09-01 反碎片并回；★ 2026-09-08 卡形统一）═══
// 形态 = 与「会话搜索」二级页（SessionSearchPage.ResultCard / SessionRecentSection.RecentCard
// 同款——决明指令「历史卡统一为搜索页卡形」，搜索页真机已验收「卡形合适」）：官方
// HdsListItemCard（HDSComponent.Full 可用时）= 前缀 message 符号 + 标题/时间两行 + C 区
// 自绘功能键；无 Full 回退自制卡同构（搜索页回退卡 + 右缘键）。骨架换官方行卡后行高/字级/
// 按压蒙层/深浅色随官方内建（即搜索页已验收形态），卡宽不挂 .width（官方姿势 = 容器 100%
// − 内部 16vp×2 = CARD_PANEL_WIDTH 三线对齐——搜索页同口径，旧「Scroll+Column 下挂
// CARD_PANEL_WIDTH」注释随之退役）。
// 功能矩阵（与旧自制卡逐项对齐，零削减）：
//   · 点击 = 进会话（多选中 = 切换勾选；加密守卫/记最近进入在宿主 handleOpenCard，上行
//     onOpen 不变）；
//   · 星标（favorite）/锁标（locked）等状态标记 = 副行（时间）**后**（★ 定稿位置三改——
//     决明「改回显示在副标题时间后」：111 版键坐标为锚——官方行卡 C 区左锚 + 内容自适应
//     宽，标记进 C 区必推键（112 反馈）/固定宽右推（113 反馈）/边距非目标（114 澄清），
//     定稿 = C 区只放键（=111 版键位置原样）；星/锁符号位历程 = 副行前缀（111→被否）/标题
//     行尾（115）/标题首位（116）/**副行后缀即现行**（118，决明拍板）：secondarySuffixSymbol
//     /secondarySuffixSubSymbol（时间文本右侧、官方排版不推键、与时间显隐开关独立——副行
//     条件副行存在性见回退分支）；★ SubSymbol 依赖修复沿用（117 节决明反馈实锤）：官方
//     语义 = 第 2 符号位仅在第 1 符号位存在时才显示——第 1 位动态填充（星优先、无星有锁
//     则锁占第 1 位）、第 2 位 = 仅星锁并存放锁，组合全覆盖且顺序（星、锁）不变（脚本
//     断言 4 组合 PASS——117 节）；后续同类标记追加点 = 本行符号位（仅两盏且第 2 位依赖
//     第 1 位——再增标记须优先考虑回退分支同构的自绘方案或 B 区 customBuilder，勿在
//     符号位堆叠）；
//   · C 区（右缘）= 只放键（普通态更多键 TEXTUAL 无显式高〔2026-09-12 UI 同形异构归一
//     笔 1 对齐 ProviderCardItem 基准〕+ 锚点 id 前缀
//     SESSION_CARD_MENU_ID_PREFIX——SessionCardMenuHost.open 拼接同源，旧锚点语义不变 /
//     多选态勾选圈：官方 Checkbox + hitTestBehavior(None) 纯视觉——坑5：Checkbox 自带
//     点击处理会消费事件与 selectedIds 脱钩；40vp 占位 = 两态统一基准【2026-09-06 决明
//     拍板，圈 20vp 曾把卡压矮】）。★ 不走官方 SuffixIcon/SuffixButton = SuffixIconOptions
//     无 id（openMenu 锚点须键自身 id——ProviderCardMenu 轮 8 先例「勿锚整卡，菜单偏低
//     ≈30vp」）、SuffixButton 仅文字钮无符号——故经 SuffixCustomBuilder 自绘（形制/锚点/
//     点击穿透与旧自制卡零变化，宿主组件仅换官方骨架，无项目先例 = 官方文档 API 参考
//     查证 + 真机验证项）；
//   · 标题 16fp 官方行卡默认（primaryText 内建单行省略/截断，官方无 maxLines/overflow
//     配置项——TextOptions 仅 text+modifier【d.ts 核实】，「标题过长，调整字数截断」=
//     行卡内建行为 + 真机验证点：长标题（AI 生成常见长度）须显示省略号；回退自制卡
//     maxLines(1)+Ellipsis 显式兜底（占位/AI 生成/用户重命名长标题——旧三件套职责保留）；
//     若官方内建不截断 → 退路 = textItem.customBuilder 自绘标题（仿官方字级 + maxLines）。
// ★ 2026-09-19 前缀图标显隐开关（偏好设置页·阅读与会话组第 3 行，决明指令）：message
//     前缀符号受 PREF_SESSION_ICON_KEY 控制（@StorageProp 自订阅切换即刷——坑16 正解，
//     无需宿主透传与 ForEach 键变）；官方分支 prefixItem 三目传 undefined（d.ts 可选属性
//     实锤）走无前缀布局标题左移，回退分支条件渲染同效。默认开 = 现状零回归；真机验证
//     点 = 官方行卡关图标后标题贴左 padding 无空位残留。
// ★ 键坐标（最终定稿 = 一百一十一「刚调回官方卡时」坐标）：官方行卡 C 区内容只键 →
// 键位置即 111 版原样（无 cardSuffixMargin、无固定宽——一百一十三/一百一十四两版修复
// 目标错位后全回退，本行以上为唯一真源）；回退自制卡标题列 layoutWeight 撑满推键贴
// 卡内容右缘（卡 padding 16 内缩）——两分支键缘同线（111 版验收坐标）。
// 底色 = 官方行卡默认卡底色随 appColorMode 深浅（不传 cardBackgroundColor——搜索页同款）；
// appColorMode @Prop 保留 = 回退自制卡 cardBg 消费。
// 菜单入口（2026-08-31 领导指令：长按弹菜单改卡片右侧更多键点击——服务商卡四点键同款形制
// dot_grid_2x2）：键点击弹官方菜单，锚点 id（前缀 + 会话 id）挂键自身（勿锚整卡先例）；
// 长按手势已清除；多选中菜单键隐藏（原长按多选守卫语义）。
// ★ 2026-09-04 会话时间显示开关：时间文本显隐走 @StorageProp 自订阅（坑16 正解——
// 开关切换标签页即刷；仅隐藏显示，updatedAt 照常记录，数据链路零改动）。
@Component
struct SessionCardItem {
  // 卡片数据（宿主 ForEach 项；键含选中态/锁定态/收藏态后缀——变化即重建，本成员建后不变）
  row: ConversationRow = { id: '', title: '', providerId: '', createdAt: 0, updatedAt: 0,
    locked: false, titleSource: '', favorite: false };
  // 会话时间显示开关（2026-09-04 偏好设置页第 6 项：true = 显示最后消息时间（默认）/
  // false = 只隐藏时间文本——@StorageProp 自订阅切换即刷，无需宿主透传）
  @StorageProp(PREF_SESSION_TIME_KEY) sessionTimeOn: boolean = true;
  // 会话图标显示开关（2026-09-19 偏好设置页·阅读与会话组第 3 行：true = 卡片左侧显示
  // 消息图标（默认，现状）/ false = 图标不显示，标题内容随之左移——@StorageProp 自订阅
  // 切换即刷，无需宿主透传与 ForEach 键变（坑16 正解，与会话时间开关同款契约）
  @StorageProp(PREF_SESSION_ICON_KEY) sessionIconOn: boolean = true;
  // 未读红点（2026-09-12 主动消息第二笔：主动消息落库写 PROACTIVE_UNREAD_CONV_KEY =
  // 目标会话 id，用户进该会话页 onPageShown 清空——本组件 @Prop 单向接收宿主判定；
  // 键进宿主 ForEach 键后缀，变化即重建刷新红点）
  @Prop unread: boolean = false;
  // 多选模式（@Prop：宿主状态变化须刷新勾选圈显隐——坑57 族入参不重渲染的正解）
  @Prop selectMode: boolean = false;
  // 本卡是否选中（@Prop 驱动 Checkbox select 回显）
  @Prop selected: boolean = false;
  // 系统颜色模式（卡底配色深浅；宿主 @StorageProp 下发）
  @Prop appColorMode: number = 1;
  // 点卡片回调（普通模式 = 进会话；多选中由本组件内守卫切换为勾选）
  onOpen: (id: string) => void = () => {
  };
  // 勾选切换回调（多选中点卡片）
  onToggle: (id: string) => void = () => {
  };
  // 更多键点击回调（普通模式弹官方菜单）
  onMenu: (row: ConversationRow) => void = () => {
  };
  // 官方 HDS 行卡可用性（HdsListItemCard 要求 HDSComponent.Full——搜索结果页/记录区同款
  // 能力位判定）：True = build 走官方行卡分支；False = 回退自制卡（同构）
  private hdsListCardAvailable: boolean = canIUse('SystemCapability.UIDesign.HDSComponent.Full');
  // 更多键（C 区自绘，普通态）：形制/锚点/回调与旧自制卡零变化——TEXTUAL（★ 2026-09-12
  // UI 同形异构归一笔 1 去显式 height(40)：对齐 ProviderCardItem 四点键基准形制 = 无显式
  // 高吃官方默认热区，热区变化列真机验收）+ 锚点 id 挂键自身（前缀 + 会话 id，勿锚整卡
  // 先例）+ 事件上行 onMenu。
  // ★ 键位置回退定稿（2026-09-08 决明拍板「刚调回官方卡时坐标」）：官方行卡 C 区 = 左锚 +
  // 内容自适应宽——C 区内容宽变即键位动。故 C 区**只放键**（一百一十一版形态，键位置即
  // 决明第一次见官方卡的坐标），星/锁改走 primarySuffix 官方符号位（标题行尾、紧邻键
  // 左侧，见 build 注释）；一百一十二~一百一十四三版（标记进 C 区/固定宽锚定/cardSuffixMargin
  // 16）全部回退——标记进 C 区被推（112 反馈）、固定宽右推 44vp（113 反馈「整体太右」）、
  // 边距非目标坐标（114 澄清）
  @Builder
  MenuKeyBuilder() {
    Button() {
      SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
        .fontSize(18)
        .fontColor([$r('sys.color.font_secondary')])
    }
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .id(SESSION_CARD_MENU_ID_PREFIX + this.row.id)
    .onClick((): void => {
      this.onMenu(this.row);
    })
  }
  // 勾选圈（C 区自绘，多选态）：官方 Checkbox + hitTestBehavior(None) 纯视觉指示器（坑5：
  // Checkbox 自带点击处理会消费事件与 selectedIds 脱钩——点击穿透落到行卡 onClick 单一
  // 通路切换勾选，与旧自制卡交互逐像素一致）；40vp 占位 = 两态统一基准（圈 20vp 缩水先例）
  @Builder
  CheckKeyBuilder() {
    Column() {
      Checkbox()
        .select(this.selected)
        .hitTestBehavior(HitTestMode.None)
    }
    .height(40)
    .justifyContent(FlexAlign.Center)
  }

  // 未读红点显隐判定（2026-09-12 主动消息第二笔：多选模式不显示——与勾选圈键位互斥，
  // 避免视觉冲突〔任务书 §二〕；官方/回退两分支共用唯一判据）
  private showUnreadDot(): boolean {
    return !this.selectMode && this.unread;
  }

  // C 区键行（普通态 = 红点 + 更多键 / 多选态 = 勾选圈）：红点在菜单键左侧、不动官方
  // 两位符号位（secondarySuffixSymbol / secondarySuffixSubSymbol 星/锁位——§1.1 ②硬约束）；
  // ★ CustomBuilder lambda 体内禁声明式组件尾随闭包（Row(){} 语法只在 @Builder/build
  // 上下文合法，lambda 内直写编译期「';' expected」）——故抽本 @Builder 方法、suffixItem
  // lambda 只做调用（CheckKeyBuilder/MenuKeyBuilder 同款结构）
  @Builder
  SuffixRowBuilder() {
    Row({ space: 4 }) {
      if (this.showUnreadDot()) {
        Circle({ width: 8, height: 8 })
          .fill($r('sys.color.warning'))
      }
      if (this.selectMode) {
        this.CheckKeyBuilder()
      } else {
        this.MenuKeyBuilder()
      }
    }
  }

  build() {
    if (this.hdsListCardAvailable) {
      // 官方行卡（搜索页 ResultCard 同款骨架）：前缀 message 符号（★ 2026-09-19 起受
      // 会话图标显示开关控制——关时 prefixItem 传 undefined〔d.ts 可选属性实锤，与
      // secondaryText/secondarySuffixSymbol 传 undefined 同款姿势〕，官方走无前缀布局
      // 标题左移）+ 标题/时间两行 + C 区
      // 只放键（★ 回到一百一十一版坐标——官方行卡 C 区左锚 + 内容自适应宽，内容只键则
      // 键位置即决明「刚调回官方卡时」坐标；星/锁 = 副行（时间）后官方符号位——
      // secondarySuffixSymbol/secondarySuffixSubSymbol，位置与动态填充规则见上方组件头
      // 「星标（favorite）/锁标（locked）」条〔118 定稿，本注释 2026-09-08 自检轮对齐——
      // 此前误留 115/116 版「标题行尾 primary 符号位」措辞〕）；删 cardSuffixMargin
      // （一百一十四版边距非目标坐标）
      HdsListItemCard({
        prefixItem: this.sessionIconOn ?
          new PrefixIcon({ iconValue: { symbol: $r('sys.symbol.message') } }) : undefined,
        textItem: {
          primaryText: { text: this.row.title !== '' ? this.row.title : '新对话' },
          // 星/锁 = 副行（时间）**后**（2026-09-08 决明拍板「改回显示在副标题时间后」——
          // 从标题首位前缀改回副行后缀位；官方符号位 = secondarySuffixSymbol（右侧第 1
          // 个）/secondarySuffixSubSymbol（右侧第 2 个，**仅第 1 位存在时才显示**——d.ts
          // 语义，SubSymbol 依赖坑 117 节实锤）。
          // ★ 动态填充沿用 117 修复：第 1 位 = 收藏优先星、无星有锁则锁占位（独立显示）；
          // 第 2 位 = 仅星锁并存时放锁（顺序 = 星、锁不变）。组合覆盖 = 仅星（星）/仅锁
          // （锁）/星锁并存（星、锁）/无标记（空）；时间显隐开关只控时间文本，符号恒显
          //（加密标记恒在拍板——时间关时副行 = [星/锁]）；回退分支自绘 Row 无依赖问题。
          secondarySuffixSymbol: this.row.favorite ? { symbol: $r('sys.symbol.star_fill') } :
            (this.row.locked ? { symbol: $r('sys.symbol.lock') } : undefined),
          secondarySuffixSubSymbol: this.row.favorite && this.row.locked ?
            { symbol: $r('sys.symbol.lock') } : undefined,
          secondaryText: this.sessionTimeOn ?
            { text: formatConvTime(this.row.updatedAt) } : undefined
        },
        // 红点 + 键分支收敛在 SuffixRowBuilder（lambda 体内禁组件尾随闭包，见其注释）
        suffixItem: new SuffixCustomBuilder((): void => {
          this.SuffixRowBuilder()
        }),
        cardBorderRadius: 16,
        onClick: (): void => {
          if (this.selectMode) {
            this.onToggle(this.row.id);
            return;
          }
          this.onOpen(this.row.id);
        }
      })
    } else {
      // 回退自制卡（搜索页回退卡同构 + 右缘键）：前缀 message 符号（受会话图标显示开关
      // 控制——关时条件渲染不挂，Column 成为首子元素、Row space 14 不产左侧空隙，标题
      // 自然左移）+ 标题/时间两行；星/锁
      // 在副行（时间）后（与官方分支 secondarySuffix 同位次——时间右、自带 space 8；时间
      // 开关关时星/锁仍在——副行条件 = sessionTimeOn || 有标记）；右缘只键（位置 = 卡内容
      // 右缘，与官方分支键缘同线——外层 Row 标题列 layoutWeight 撑满推键贴右）；
      // Button(Normal) 包裹 = 官方原生按压蒙层（2026-09-12 UI 同形异构归一笔 1——与
      // HDS 分支按压反馈对齐，selectMode 分支逻辑原样）
      Button() {
        Row({ space: 14 }) {
          if (this.sessionIconOn) {
            SymbolGlyph($r('sys.symbol.message'))
              .fontSize(20)
              .fontColor([cardDescColor()])
          }
          Column({ space: 4 }) {
            Text(this.row.title !== '' ? this.row.title : '新对话')
              .fontSize(16)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%') // Column 内横向撑满（★ 勿用 layoutWeight——Column 主轴=垂直，
            // 会用剩余高度拉伸文本行；width 100% = 保长标题单行省略生效，2026-09-08 自检轮修）
            if (this.sessionTimeOn || this.row.favorite || this.row.locked || this.showUnreadDot()) {
              Row({ space: 8 }) {
                if (this.sessionTimeOn) {
                  Text(formatConvTime(this.row.updatedAt))
                    .fontSize(13)
                    .fontColor(cardDescColor())
                }
                if (this.row.favorite) {
                  SymbolGlyph($r('sys.symbol.star_fill'))
                    .fontSize(14)
                    .fontColor([$r('sys.color.font_secondary')])
                }
                if (this.row.locked) {
                  SymbolGlyph($r('sys.symbol.lock'))
                    .fontSize(14)
                    .fontColor([$r('sys.color.font_secondary')])
                }
                // 未读红点（官方分支同构：标记容器尾部追加，多选模式不显示）
                if (this.showUnreadDot()) {
                  Circle({ width: 8, height: 8 })
                    .fill($r('sys.color.warning'))
                }
              }
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if (this.selectMode) {
            this.CheckKeyBuilder()
          } else {
            this.MenuKeyBuilder()
          }
        }
        .width('100%')
        .padding(16)
      }
      .type(ButtonType.Normal)
      .width(CARD_PANEL_WIDTH)
      .borderRadius(16)
      .backgroundColor(cardBg(this.appColorMode))
      .onClick((): void => {
        if (this.selectMode) {
          this.onToggle(this.row.id);
          return;
        }
        this.onOpen(this.row.id);
      })
    }
  }
}

// ═══ 会话卡片菜单（2026-08-30 建、2026-09-01 反碎片并回；机制原样）═══
// 机制 = dshinhm 真机回归修复同款——卡片长按 bindContextMenu 真机不弹，改走项目内真机
// 已验证的 PromptAction.openMenu 编程式路径（ComponentContent 建/重建/dispose + 锚点
// TargetInfo 定位 + 官方菜单材质）。域边界：菜单内容（删除/重命名）+ ComponentContent
// 宿主生命周期 + 弹出函数；动作执行（确认弹窗删除/重命名弹窗 + 列表刷新）经回调注入归
// 本页。弹窗/材质红线：菜单宽度官方内容自适应；systemMaterial 基准 REGULAR 随沉浸光感总档；每次弹出前 dispose + 重建（深浅色/材质安全）；菜单已开时再点更多键 = 先关旧菜单。

// 卡片锚点 id 前缀（openMenu TargetInfo 定位目标 = 卡片右缘四点键：.id(前缀 + 会话 id)）
const SESSION_CARD_MENU_ID_PREFIX: string = 'sessionCardMenu_';

// 菜单回调（openMenu 的 ComponentContent 参数载体：全局 @Builder 无组件实例，数据与
// 动作经参数注入）
interface SessionCardMenuCallbacks {
  item: ConversationRow;
  onDelete: (item: ConversationRow) => void;
  onRename: (item: ConversationRow) => void;
  // 加密开关（2026-09-04 加密会话：菜单文案按 item.locked 分「加密会话/解除加密」，
  // 动作执行 = 本页 toggleConversationLock——先认证后落库）
  onToggleLock: (item: ConversationRow) => void;
  // 收藏开关（2026-09-08 会话收藏：文案按 item.favorite 分「收藏/取消收藏」，动作执行 =
  // 本页 toggleFavorite——直落库无认证前置）
  onToggleFavorite: (item: ConversationRow) => void;
}

// 会话卡片菜单内容（官方 Menu 组件）：重命名 = square_and_pencil / 加密 = lock（解除 =
// lock_open）/ 收藏 = star（取消 = star_fill）/ 删除 = trash（字形 SDK 符号表
// resources.txt 实锤，坑72 口径）。菜单项顺序 = 重命名/加密会话/收藏/删除（★ 2026-09-12
// UI 同形异构归一笔 1：「删除」自首位移到末位垫底——与其余全部行卡菜单「编辑在上、删除
// 垫底」对齐，破坏性项离拇指最远）。宽度官方内容自适应。
// 分割线：Menu.menuItemDivider 默认不显示须显式设置，mode 必须 EMBEDDED_IN_MENU（FLOATING
// 悬浮层被菜单项盖住不可见），颜色走 menuDividerColor 深浅分治；全局 @Builder 无组件实例，
// AppStorage.get 直读——菜单节点每次弹出前重建，读取始终为当前深浅色（ChatMoreMenu.ets
// 同款姿势）。
@Builder
function SessionCardMenuBuilder(params: SessionCardMenuCallbacks) {
  Menu() {
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')), content: '重命名' })
      .onClick(() => {
        params.onRename(params.item);
      })
    MenuItem({
      symbolStartIcon: params.item.locked ? new SymbolGlyphModifier($r('sys.symbol.lock_open')) : new SymbolGlyphModifier($r('sys.symbol.lock')),
      content: params.item.locked ? '解除加密' : '加密会话'
    })
      .onClick(() => {
        params.onToggleLock(params.item);
      })
    MenuItem({
      symbolStartIcon: params.item.favorite ? new SymbolGlyphModifier($r('sys.symbol.star')) : new SymbolGlyphModifier($r('sys.symbol.star_fill')),
      content: params.item.favorite ? '取消收藏' : '收藏'
    })
      .onClick(() => {
        params.onToggleFavorite(params.item);
      })
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')), content: '删除' })
      .onClick(() => {
        params.onDelete(params.item);
      })
  }
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 菜单节点宿主（2026-08-30 反馈轮 13 起为 AppMenuHost 薄壳——节点生命周期与弹出组装在
// 基类，本壳只实现 buildNode 与便捷 open（材质解析 + 逐卡锚点拼接），页面侧
// init/open/dispose 调用零变化）。锚点 = 卡片右缘四点键（id 按会话逐卡不同，open 时拼前缀）。
class SessionCardMenuHost extends AppMenuHost<SessionCardMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: SessionCardMenuCallbacks): ComponentContent<SessionCardMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(SessionCardMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出菜单（基类弹前重建——按当前深浅色/材质重新构建 UI 树；材质 REGULAR 基准随沉浸光感总档在此解析）：placement = BottomRight——菜单右缘对锚点右缘
  //（四点键右缘）、键下沿下方弹出（ProviderCardMenu 同款锚键姿势）；targetSpace 5 =
  // 锚点同为按钮的卡片菜单统一间距（轮 8 领导拍板）
  open(uiContext: UIContext, callbacks: SessionCardMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, SESSION_CARD_MENU_ID_PREFIX + callbacks.item.id,
      // ★ 第三参 true = 交互形变 + 触点流光（2026-09-18 菜单光感笔；官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true),
      { targetSpace: LengthMetrics.vp(5) });
  }
}

@Component
export struct ChatSessionList {
  // 顶部留白（vp，宿主 titleBarInset 下发）：HDS 路径内容区延伸到标题栏背后，首卡静止时
  // 完整落在渐变模糊蒙层下方；回退路径 = 0
  @Prop topPad: number = 0;
  // 底部留白（vp，宿主下发——悬浮页签让位）
  @Prop bottomPad: number = 0;
  // 多选批量条距屏底（vp，宿主传 navBarHeight + 16——批量条悬浮在页签上方；与 bottomPad
  // 分开传，navBarHeight 因设备导航条而异不能写死；多选中页签收起后批量条贴屏底）
  @Prop barBottom: number = 96;
  // 刷新广播（对话页 pop 后重拉列表；见上键注释）
  @StorageProp(SESSION_LIST_RELOAD_KEY) @Watch('onReloadTick') reloadTick: number = 0;
  // 标题刷新广播（2026-09-05 AI 会话标题：AI 写回/占位升级成功 → 重拉列表刷标题行——
  // 与上键共用 onReloadTick 回调，只读幂等多触发无害；common/TitleGen 单键驱动两订阅侧）
  @StorageProp(CONV_TITLE_TICK_KEY) @Watch('onReloadTick') titleTick: number = 0;
  // 更多菜单「多选」指令（计数器——@Watch 值变回调进入多选模式）
  @StorageProp(SESSION_MULTISELECT_CMD_KEY) @Watch('onMultiselectCmd') multiselectCmd: number = 0;
  // 主动消息未读会话（2026-09-12 主动消息第二笔：只读订阅——ProactiveGen 落库写入、
  // ChatPage.onPageShown 清空；红点判定 = row.id === unreadConvId，零 DB 改动零新查询）
  @StorageProp(PROACTIVE_UNREAD_CONV_KEY) unreadConvId: string = '';
  // 点会话卡片回调（宿主执行 push 对话页；标题由对话页自包壳按 id 查询，不上抛——
  // 任务 4 壳改造收敛）
  onOpen: (conversationId: string) => void = () => {
  };
  // 系统颜色模式（卡底配色；EntryAbility 未写键时缺省浅色——M1 既有缺口，BLOCKED.md 待裁决）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 沉浸光感档位（会话卡片菜单材质随沉浸光感总档——openCardMenu 经 SessionCardMenuHost.open
  // 消费；★ 本页原「新建悬浮键」消费方 2026-08-31 随键上移标题栏退役，现消费方仅卡片菜单）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @State private rows: ConversationRow[] = [];
  @State private hintText: string = '';
  // 首拉完成闸（2026-08-31 空态卡配套）：false = 首次查询在途——空态卡不显示（防列表
  // 初值空态闪现「暂无历史会话」）；查询落定（成功/失败）置真后空列表才显示空态
  @State private loaded: boolean = false;
  // ── 会话收藏（2026-09-08，任务书-会话搜索与收藏-20260907；搜索域已随改版迁二级页
  // SessionSearchPage，本页只留收藏分段）──
  // 收藏分段（0 = 全部 / 1 = 收藏）：切换内存过滤不重查库（visibleRows 派生）
  @State private favSegment: number = 0;
  // 分段选项（SegmentButtonV2Items 纯展示，普通成员——ProviderPage segItems 同款）
  private favSegItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '全部' },
    { text: '收藏' }
  ]);
  // ── 多选模式（dshinhm KimiSessionList 二二一改同款）──
  // 多选中（菜单指令进入；批量删除成功/手动取消退出）
  @State private selectMode: boolean = false;
  // 选中待删除的会话 id（点卡片切换；数据有界：上限 = 当前列表条数）
  @State private selectedIds: string[] = [];
  // 批量删除请求进行中（批量按钮防重复点击 + 确认弹窗防重开）
  @State private deleting: boolean = false;
  // 删除确认/重命名弹窗控制器（★ 组件成员——d.ts:735 原文「CustomDialogController is
  // effective only when it is a member variable of the @CustomDialog and @Component」：
  // 普通类成员构造 open() 静默无效（2026-08-30 坑7 真机实锤——三路弹窗全失效根因）。
  // 每次打开重建，官方无强制 dispose 要求——dshinhm 一八二改同款）
  private confirmCtrl: CustomDialogController | null = null;
  private renameCtrl: CustomDialogController | null = null;
  // 会话卡片长按菜单节点宿主（init/open/dispose 成对，见 SessionCardMenu.ets）
  private cardMenu: SessionCardMenuHost = new SessionCardMenuHost();

  aboutToAppear(): void {
    this.reload();
    // 长按菜单节点首次构建（getUIContext 需组件就绪；与 aboutToDisappear dispose 成对）。
    // init 仅建节点需占位 item，open 时必传真实 item 重建——空占位行（列表未加载场景，
    // dshinhm 同款）
    this.cardMenu.init(this.getUIContext(), this.menuCallbacks(this.emptyItem()));
  }

  aboutToDisappear(): void {
    // 长按菜单节点释放（与 aboutToAppear init 成对）
    this.cardMenu.dispose();
    // 寿命匹配（dshinhm 二二二改）：组件带多选态销毁时撤销页签收起广播——否则
    // AppStorage 残留 true、页签永久收起无法恢复
    if (this.selectMode) {
      AppStorage.setOrCreate<boolean>(SESSION_SELECT_MODE_KEY, false);
    }
  }

  // 空占位 item（init 时列表未加载，宿主仅建节点不含真实数据；open 时必传真实 item 重建）
  private emptyItem(): ConversationRow {
    return { id: '', title: '', providerId: '', createdAt: 0, updatedAt: 0, locked: false,
      titleSource: '', favorite: false };
  }

  // 菜单回调组装（init/open 两处共用——宿主建节点需要完整 callbacks 对象；显式接口
  // 构造，坑72：union 上下文禁匿名对象字面量）
  private menuCallbacks(item: ConversationRow): SessionCardMenuCallbacks {
    const callbacks: SessionCardMenuCallbacks = {
      item: item,
      onDelete: (row: ConversationRow): void => {
        this.openDeleteConfirm('将彻底删除会话「'
          + (row.title !== '' ? row.title : '新对话')
          + '」及其全部聊天记录，不可恢复。', (): void => {
          this.deleteOne(row.id);
        });
      },
      onRename: (row: ConversationRow): void => {
        this.openRenameDialog(row);
      },
      onToggleLock: (row: ConversationRow): void => {
        this.toggleConversationLock(row);
      },
      onToggleFavorite: (row: ConversationRow): void => {
        this.toggleFavorite(row);
      }
    };
    return callbacks;
  }

  // 卡片更多键点击弹官方菜单（服务商卡四点键同款触发；多选中菜单键隐藏——卡片侧不渲染）
  private openCardMenu(row: ConversationRow): void {
    this.cardMenu.open(this.getUIContext(), this.menuCallbacks(row),
      this.immersiveLevel);
  }

  // ── 加密会话（2026-09-04 决明指令；官方接口/权限查证依据见 BiometricGate.ets 头注释）──

  // 加密开关执行（菜单「加密会话/解除加密」唯一入口）：先过官方生物识别——开锁同样要
  // 验证（门禁的钥匙不能留在门上），通过才落库 + 重拉列表；失败 toast 保持原态可重试
  //（P0-1 不静默）。锁定/解除均不动 updatedAt（列表时间序不变）
  private async toggleConversationLock(row: ConversationRow): Promise<void> {
    const gate: BiometricGateResult = await biometricGate(
      row.locked ? '验证身份，解除会话加密' : '验证身份，加密此会话');
    if (gate.outcome !== BiometricGateOutcome.PASSED) {
      this.toastGateOutcome(gate);
      return;
    }
    try {
      await setConversationLocked(row.id, !row.locked);
      this.getUIContext().getPromptAction().showToast(
        { message: row.locked ? '已解除加密' : '已加密，进入需验证身份' });
      this.reload(); // 键含锁定态后缀——重拉即键变重建，锁标随新数据刷新
    } catch (e) {
      this.getUIContext().getPromptAction().showToast(
        { message: (row.locked ? '解除加密失败：' : '加密失败：') + (e as Error).message });
    }
  }

  // 收藏开关执行（2026-09-08 会话收藏，菜单「收藏/取消收藏」唯一入口；归
  // toggleConversationLock 同构——无生物识别前置）：落库 → 成功 toast + 重拉列表（键含
  // 收藏态后缀，星标随新数据刷新）；失败 toast 错误信息、状态不变可重试（P0-1 不静默）。
  // 收藏/取消均不动 updatedAt（列表时间序不变）
  private async toggleFavorite(row: ConversationRow): Promise<void> {
    try {
      await setConversationFavorite(row.id, !row.favorite);
      this.getUIContext().getPromptAction().showToast(
        { message: row.favorite ? '已取消收藏' : '已收藏' });
      this.reload();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast(
        { message: (row.favorite ? '取消收藏失败：' : '收藏失败：') + (e as Error).message });
    }
  }

  // 点击卡片进入守卫：加密会话先过官方生物识别，通过才上行进入（每次进入都验证，
  // 不维持解锁态）；未加密直通零改动；取消静默、失败按原因提示不进入。
  // ★ 最近进入记录（2026-09-08 会话搜索；记录区展示已随搜索迁 SessionSearchPage，本页
  // 点卡进入仍是记录点之一）：实际放行进入才记（未通过认证/取消不算进入）——去重移头、
  // 上限 3 条在 SessionSearch 内收敛
  private handleOpenCard(row: ConversationRow): void {
    if (!row.locked) {
      recordSessionRecentConv(row.id);
      this.onOpen(row.id);
      return;
    }
    biometricGate('验证身份，进入加密会话')
      .then((gate: BiometricGateResult): void => {
        if (gate.outcome === BiometricGateOutcome.PASSED) {
          recordSessionRecentConv(row.id);
          this.onOpen(row.id);
          return;
        }
        this.toastGateOutcome(gate);
      });
  }

  // 认证结果提示（开关锁/进入三处共用）：取消静默（用户主动行为非故障），其余按原因
  // 分文案——文案单源已抽 BiometricGate.gateOutcomeMessage（2026-09-05 加密新入口第四处
  // 消费时提取），本壳只管 toast
  private toastGateOutcome(gate: BiometricGateResult): void {
    const message: string = gateOutcomeMessage(gate);
    if (message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
  }

  onReloadTick(): void {
    this.reload();
  }

  // 未读红点行级判定（2026-09-12 主动消息第二笔：多选中不显示——红点条件与 ForEach
  // 未读后缀共用本判据；多选切换时 ForEach 键含多选后缀整列重建，红点随键自然进退）
  private rowUnread(row: ConversationRow): boolean {
    return !this.selectMode && row.id === this.unreadConvId;
  }

  onMultiselectCmd(): void {
    // 进入多选（重复点击菜单 = 已在多选中无操作幂等；退出通道 = 批量条「取消」或
    // 批量删除成功）+ 广播状态（页签收起——HomeNavigation 消费）
    if (!this.selectMode) {
      this.selectMode = true;
      AppStorage.setOrCreate<boolean>(SESSION_SELECT_MODE_KEY, true);
    }
  }

  // 渲染派生过滤（2026-09-08 收藏分段——任务书 §2.5 build 内派生方法形态；搜索 keyword
  // 过滤段已随搜索功能迁二级页 SessionSearchPage 退役）：rows 全量 @State 不变，分段内存
  // 过滤不动时间序
  private visibleRows(): ConversationRow[] {
    let list: ConversationRow[] = this.rows;
    if (this.favSegment === 1) {
      list = list.filter((row: ConversationRow): boolean => row.favorite);
    }
    return list;
  }

  // 空态文案（2026-09-08 搜索分支退役后只剩分段分治）：收藏段空 = 「暂无收藏会话」；全部
  // 段空维持「该助手暂无会话」
  private emptyText(): string {
    return this.favSegment === 1 ? '暂无收藏会话' : '该助手暂无会话';
  }

  private reload(): void {
    // DB 就绪守卫（2026-08-30 竞态修复）：EntryAbility 异步初始化与页面加载并行——冷
    // 启动时 DB 未就绪即查库会抛「数据库未就绪」且无任何自动重试（钉死在错误提示，重启
    // 才好）；先等 whenReady 再查。init 失败（doInit 缓存 false，本会话无重试）提示重启
    whenReady().then((ok: boolean): void => {
      if (!ok) {
        this.hintText = '数据库初始化失败，请重启应用重试';
        return;
      }
      // 历史只显示当前助手名下（2026-09-01 会话绑定改造）：active 键入口同步读（缺省 =
      // 默认助手）；'' 存量行归默认口径在 historyFilterIds
      const activeId: string = AppStorage.get<string>(ACTIVE_ASSISTANT_KEY) ?? ASSISTANT_DEFAULT_ID;
      queryConversations(historyFilterIds(activeId))
        .then((rows: ConversationRow[]): void => {
          // 全量查询一次性赋值（2026-09-04 拍板：本地库无分页必要；连续状态修改合并为
          // 一次刷新）
          this.rows = rows;
          this.loaded = true;
        })
        .catch((e: Object): void => {
          this.hintText = '会话列表读取失败：' + (e as Error).message;
        });
    });
  }

  // ── 多选模式（dshinhm KimiSessionList 二二一改同款）──

  // 点击卡片切换勾选（selectedIds 整体替换；ForEach 键值含选中态——该项键变即重建,
  // 勾选圈随新键刷新）
  private toggleSelect(id: string): void {
    if (this.selectedIds.includes(id)) {
      this.selectedIds = this.selectedIds.filter((i: string): boolean => i !== id);
    } else {
      this.selectedIds = this.selectedIds.concat([id]);
    }
  }

  // 退出多选（取消按钮 / 批量删除成功后自动）：清空选择回到普通浏览 + 撤销页签收起广播
  private exitMultiselect(): void {
    this.selectMode = false;
    this.selectedIds = [];
    AppStorage.setOrCreate<boolean>(SESSION_SELECT_MODE_KEY, false);
  }

  // 删除确认弹窗统一入口（多选/单条共用——P2-4 同构提取；构造在组件成员位——坑7 约束；
  // hilog 留点 = 静默故障定位锚）
  private openDeleteConfirm(message: string, onConfirm: () => void): void {
    hilog.info(0xD5A1, 'ChatSessionList', 'confirm delete dialog open');
    this.confirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '删除会话',
        message: message,
        confirmLabel: '删除',
        onConfirm: (): void => {
          onConfirm();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
      // customStyle 不传 = 官方对话框底板（2026-08-30 领导指令「删除弹窗材质统一为重命名的」
      // ——与 InputDialog 同款官方实底，形态单一来源见 ConfirmDialog.ets 文件头）
    });
    this.confirmCtrl.open();
  }

  // 多选批量删除入口（批量条主操作）：空选/进行中首行守卫（与 dshinhm 归档页同款不加
  // 禁用态——守卫拦住即可）；删除不可恢复，确认弹窗兜一层
  private confirmDeleteSelected(): void {
    if (this.selectedIds.length === 0 || this.deleting) {
      return;
    }
    hilog.info(0xD5A1, 'ChatSessionList', 'confirm delete %{public}d conversations',
      this.selectedIds.length);
    this.openDeleteConfirm('将彻底删除选中的 ' + this.selectedIds.length
      + ' 个会话及其全部聊天记录，不可恢复。', (): void => {
      this.deleteSelected();
    });
  }

  // 打开重命名官方弹窗（2026-08-30 领导指令「重命名参考旧项目」——dshinhm KimiSessionList
  // 一八二改同款 InputDialog 复用；每次打开重建 controller；构造在组件成员位——坑7 约束）；
  // 初值 = 当前标题（空标题兜底「新对话」，与卡片展示一致）
  private openRenameDialog(row: ConversationRow): void {
    this.renameCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: '重命名会话',
        initialText: row.title !== '' ? row.title : '新对话',
        placeholder: '会话名称',
        onConfirm: (text: string): void => {
          this.applyRename(row.id, text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.renameCtrl.open();
  }

  // 长按单条删除（2026-08-30 领导指令「删除同新项目右上角菜单删除」）：确认弹窗与删除
  // 链路同多选删除（ConfirmDialog + ChatDb.deleteConversations 事务级联，单 id 数组为
  // 新建普通数组非代理——坑6 族无暴露）；失败 toast 可重试（长按菜单再开即可，P0-1）
  private async deleteOne(id: string): Promise<void> {
    try {
      const count: number = await deleteConversations([id]);
      this.rows = this.rows.filter((row: ConversationRow): boolean => row.id !== id);
      // 删行已落库 → 广播重拉（★ 2026-09-20 复验轮补写点：本页本地移除只覆盖自己在场时的
      // 列表，跨页签消费方不知道——助手页卡面「会话 N」chip 正订阅同键，无此写点则删除后
      // 切回助手页签仍显示旧数；一次性计数器形态自增，写固定值 @Watch 不触发。本页自订阅
      // 同样重拉一次 = 幂等无害、无回环（同 AssistantPage 切助手自写先例）
      AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
        (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
      this.getUIContext().getPromptAction().showToast({ message: '已删除 ' + count + ' 个会话' });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
    }
  }

  // 重命名执行（2026-08-30 领导指令「重命名参考旧项目」；弹窗构造在 SessionCardActions，
  // dshinhm 一八二改同款 InputDialog——空值/同值校验在弹窗内，此处 P0-1 兜底 toast）：
  // 本地 DB 直写 → 成功 toast + 重拉列表（不动 updatedAt 故时间序不变）；失败 toast
  // 错误信息、列表不动可重试
  private async applyRename(id: string, text: string): Promise<void> {
    try {
      await renameConversation(id, text);
      this.getUIContext().getPromptAction().showToast({ message: '已重命名' });
      this.reload();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '重命名失败：' + (e as Error).message });
    }
  }

  // 批量删除执行（确认弹窗「删除」回调）：全成功本地移除 + 广播重拉 + toast + 退出多选；
  // 失败 toast 且保留选择（可调整后重试，P0-1 不静默）。★ 2026-09-20 复验轮改写：原稿
  // 「本地移除不再广播重拉（删除方持有最新列表，dshinhm archiveSelected 同款）」只考虑了
  // 本页自己——跨页签的助手页卡面「会话 N」chip 订阅同键，删完切回助手页签即停旧数，
  // 故此侧必须广播；本地移除保留（即时反馈，不等重查），自订阅多一次重拉幂等无害
  private async deleteSelected(): Promise<void> {
    if (this.selectedIds.length === 0 || this.deleting) {
      return;
    }
    this.deleting = true;
    try {
      const ids: string[] = this.selectedIds;
      const count: number = await deleteConversations(ids);
      this.rows = this.rows.filter((row: ConversationRow): boolean => ids.indexOf(row.id) < 0);
      // 删行已落库 → 广播重拉（同上 deleteOne：单条/批量两条删除链都不得漏此写点——漏一处
      // 即「删了会话、助手页 chip 不停更」；一次性计数器形态自增）
      AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
        (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
      this.getUIContext().getPromptAction().showToast({ message: '已删除 ' + count + ' 个会话' });
      this.exitMultiselect();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
    } finally {
      this.deleting = false;
    }
  }

  build() {
    // alignContent Top（2026-09-08 搜索/分段悬浮层定位需要——ProviderPage 同款；既有
    // 全尺寸子组件 Scroll/空态卡/批量条不受对齐影响）
    Stack({ alignContent: Alignment.Top }) {
      // ── 会话列表（2026-09-04 回退定稿：级页在 HdsNavigation 下 List 兼容坑 = 一级页
      //    禁 List 沉淀（dshinhm 2026-08-20 真机实锤「顶蒙层点不了滑不动」）——回 Scroll
      //    +Column+ForEach；全量查询（本地库无分页必要）──
      Scroll() {
        Column({ space: CARD_SPACING }) {
          // 派生过滤渲染（rows 全量不变——收藏分段内存过滤，见 visibleRows；搜索过滤已
          // 随搜索迁二级页退役）
          ForEach(this.visibleRows(), (row: ConversationRow) => {
            SessionCardItem({
              row: row,
              selectMode: this.selectMode,
              selected: this.selectedIds.includes(row.id),
              unread: this.rowUnread(row),
              appColorMode: this.appColorMode,
              onOpen: (id: string): void => {
                this.handleOpenCard(row); // 加密会话先认证再进入（未加密直通）——row 闭包
              },
              onToggle: (id: string): void => {
                this.toggleSelect(id);
              },
              onMenu: (cardRow: ConversationRow): void => {
                this.openCardMenu(cardRow);
              }
            })
            // 键含多选/选中/锁定/收藏态后缀（dshinhm 归档页同款机制——键变即重建，勾选圈/
            // 锁标/星标/形态随新键刷新；selectMode 切换 = 全列表键变重建，与 dshinhm 同代价
            // 可接受）
          }, (row: ConversationRow): string => row.id +
            (row.locked ? '|L' : '') +
            '|' + row.title + // 标题进键（2026-09-05 AI 会话标题）：CONV_TITLE_TICK 广播
            // 重拉后标题变化即键变重建卡片——键不变则 SessionCardItem 构造快照不刷（坑16）
            (row.favorite ? '|F' : '') + // 收藏态进键（2026-09-08）：开关收藏即重建刷星标
            (this.rowUnread(row) ? '|U' : '') + // 未读态进键（2026-09-12 主动消息第二笔）：
            // 未读键写入/清除即键变重建刷红点（坑16 族——@Prop 传入变化不经键不重渲染）
            '|' + row.updatedAt + // 时间进键（2026-09-08 自检轮补修）：发消息/reload 后
            // updatedAt 变化即键变重建刷时间——键不含时间则复用旧快照显示陈旧时间
            //（110 版起预存在，坑16 族；搜索页键含时间同款姿势）
            (this.selectMode ? (this.selectedIds.includes(row.id) ? '|s1' : '|s0') : ''))

          if (this.hintText !== '') {
            Text(this.hintText)
              .fontSize(12)
              .fontColor($r('sys.color.ohos_id_color_warning'))
              .width('calc(100% - 32vp)')
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        // 顶/底留白 = 滚动内容内部 padding（随内容滚走、卡片滑入标题栏蒙层透出——坑9
        // 正解在 Scroll+Column 下天然成立；多选中批量条悬浮贴屏底 = 末卡固定让位）。
        // 顶让位（2026-09-08）：分段悬浮位 48（常量见文件头 SEGMENT_TOP_CLEARANCE；搜索
        // 框行让位随搜索迁二级页退役）
        .padding({
          top: this.topPad + SEGMENT_TOP_CLEARANCE,
          bottom: this.bottomPad + 16 + (this.selectMode ? 56 : 0)
        })
      }
      .width('100%')
      .height('100%')
      // 滚动内容不足视口时顶对齐（坑18：Scroll align 默认 Center）+ 短内容可拖拽回弹（坑76）
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      // ── 空态卡（2026-08-31 任务 C，四域复检观察项；2026-09-08 文案分治）：当前分段
      // 结果为空时全高垂直居中提示——dshinhm KimiSessionList 同款形态（居中文字 + 次要色
      // 深浅自适应，底部抵消 topPad 悬蒙层下视觉居中）。文案分治见 emptyText；首拉在途
      //（loaded=false）与加载失败（hintText 覆盖层提示）不显示 ──
      if (this.loaded && this.hintText === '' && this.visibleRows().length === 0) {
        Column() {
          Text(this.emptyText())
            .fontSize(13)
            .fontColor(cardDescColor())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ bottom: this.topPad })
      }

      // ── 「全部/收藏」分段悬浮层（2026-09-08 会话收藏；ProviderPage :431-443 悬浮吸顶
      // 形制逐参数同款：Stack({ alignContent: Alignment.Top }) 顶层 + width(CARD_PANEL_
      // WIDTH) + margin top = max(topPad - 8, 0)；SegmentBar A 档参数单一来源，本体零
      // 改动。切换内存过滤不重查库——favSegment @State → visibleRows 派生）──
      Column() {
        SegmentBar({
          items: this.favSegItems,
          selectedIndex: $favSegment
        })
      }
      .width(CARD_PANEL_WIDTH)
      .margin({ top: Math.max(this.topPad - 8, 0) })

      // ── 多选批量条（组件 = SessionMultiselectBar——dshinhm 同款独立域件，形态/穿透/
      // 材质说明见该文件头注释）。多选中才挂载——普通模式零渲染零命中负担 ──
      if (this.selectMode) {
        SessionMultiselectBar({
          // 三态文案（dshinhm 二二四改补请求态反馈）：删除请求在途显示「删除中…」防
          // 重复点击 + 用户可见反馈；N=0 空选守卫见 confirmDeleteSelected 首行
          barText: this.deleting ? '删除中…' : this.selectedIds.length > 0
            ? '删除 ' + this.selectedIds.length + ' 个会话' : '删除会话',
          barBottom: this.barBottom,
          onCancel: (): void => {
            this.exitMultiselect();
          },
          onPrimary: (): void => {
            this.confirmDeleteSelected();
          }
        })
      }
      // ── 新建会话入口 2026-08-31 上移标题栏（领导指令：右下角悬浮键去掉，标题栏四点键
      // 左侧加号键点击新建——HomeNavigation 标题栏双键负责，本页不再挂悬浮键）──
    }
    .width('100%')
    .height('100%')
  }
}