// 会话列表页（M2a：对话页签 = 历史会话列表，点卡片经官方路由 push 对话页——输入栏随对话页
// 全屏覆盖页签，底部避让冲突从结构上消除，dshinhm 同款架构不搬本体）。数据 = ChatDb
// conversations 表（每次收发 touch updatedAt，列表时间序即真实最近使用序）。
// ★ 2026-09-25 首页 Repeat 试迁（决明指定）：渲染域（List 容器 + Repeat + 行卡 + 提示行）
// 已拆出至 components/chat/ChatSessionRows.ets，本壳只留数据与业务（读取/分段过滤/菜单/
// 弹窗/删除/多选状态）与事件接线；机制实读（Repeat 懒加载须配 V2 / RepeatItem 须整体
// 传参 / 键只写身份、禁键变重建）与红线见该件头注释。前史两点结论：①「一级页禁 List 沉淀」
//（2026-09-04，坑50）系当年结论——2026-09-25 实验分支真机三验已过（切段/滚动/状态六项
// 全对），List 骨架在本页重新可用，本轮按官方选型换 Repeat（官方指南「建议开发者优先使用
// Repeat」）；②本地 RDB 全量查询拍板不动——QUERY_TAIL_LIMIT 50 上限与滚动加载分页链已全撤
//（本地库一次查全量毫秒级，dshinhm 服务端分页是远程协议必然，无此约束）。
// ★ 列表 = 当前助手名下（读取链单源 HomeListWarmup 内读 ACTIVE_ASSISTANT_KEY 过滤，切换
// 助手后经 SESSION_LIST_RELOAD_KEY 广播重拉即变）。
// 空态卡：列表空（首拉完成 loaded 且 rows 空、无失败提示）→ 全高居中「该助手暂无会话」
// 次要色（细则见 build 内注释）。
// 刷新通道：Tab 内容无 onShown 生命周期——对话页 pop 后由 ChatPageLifecycle.leave 尾沿去抖
// 自增 SESSION_LIST_RELOAD_KEY（本组件 @StorageProp @Watch 消费）重拉列表；重拉与回包落屏
// 再受滚动空闲闸约束（R2-c，见字段注释），滑动中不在同一帧替换整表数据源。
// ★ U9 会话列表 loading：退页不断流后生成在运行时继续——reload 行合成读运行时生成中标记
//（reconcileSessionRows 内 isGenerating），行卡渲染生成中转圈；生成收尾在
// 离页期由运行时收尾钩子自增 SESSION_LIST_RELOAD_KEY（ChatSessionRuntime.onRoundSettled）
// 驱动重拉清退标记（一次性计数器通道，坑3 口径白名单纪律；R2-a 比对吞掉无变化重拉）。
// ★ 多选模式（dshinhm 二二一改同款——官方 Checkbox 右侧勾选圈/点卡片切换勾选/底部批量条
// 悬浮 HitTestMode.Transparent 空白区触摸穿透）：「对话」页签更多菜单「多选」进入
//（AppStorage 一次性指令计数器下发，HomeNavigation→本组件零透传——坑3 口径；键常量本文件
// 导出）；勾选后「删除 N」→ 确认弹窗（彻底删除不可恢复，CustomDialogController +
// ConfirmDialog——TabContent 槽内 showAlertDialog 真机不弹，坑64 族，机制选型见
// ConfirmDialog.ets 文件头；取消左/删除右通讯红）→ deleteConversations 事务级联删消息+会话
// 行 → 成功本地移除 + toast + 退出多选；失败 toast 保留选择可重试（P0-1）。多选中点卡片
// 不再进会话；勾选圈显隐与选中回显走卡片 @Param（迁 Repeat 后不再用「键含选中态后缀」的
// 键变重建机制，见 ChatSessionRows.ets 头注释机制③）。多选中广播 SESSION_SELECT_MODE_KEY
//（bool 持续状态非一次性）——宿主收起悬浮页签（避免页签与批量条重叠，barBottomMargin 巨值
// 推出视口，退出恢复定稿值）。
// ★ 卡片菜单（2026-10-30 两千零一十节定稿：长按卡片 → 标准官方上下文菜单，无预览浮起、
// 无蒙层；触发方式与参数全在拆件 SessionCardMenu.ets——原「卡片右缘四点键 + 官方 openMenu」
// 形制已退役，勿按旧形制补回可见入口）：删除 =
// 确认弹窗 + deleteConversations 事务级联（同多选删除链路）；重命名 = InputDialog 弹窗
//（dshinhm 一八二改同款）+ renameConversation 直写（不动 updatedAt 时间序）→ 重拉列表；
// 多选态不挂长按菜单（勾选中误弹会与批量语义打架）。
// ★ 2026-11-17 整体退役加密会话笔：原「加密会话」菜单项/侧滑键/锁标/进入生物识别守卫
// 全链撤除（含 common/BiometricGate.ets 整件与 conversations.locked 读写；v66 迁移已清零
// 存量标记）。本页进入卡片一律直通，动作面 = 重命名/移动/收藏/删除四项。
// ★ 会话收藏（2026-09-08 任务书；同日改版：搜索功能全量迁独立二级页 SessionSearchPage.ets，
// 本页只留收藏）：收藏 = DB v19 favorite 列——卡片菜单「收藏/取消收藏」+ 卡片星标（仅收藏
// 卡显示）+ 「全部/收藏」分段过滤（ProviderPage 悬浮吸顶形制逐参数同款）；
// 收藏不改时间排序（updatedAt 零新写点）。★ 2026-10-29 标题栏内嵌分段笔：HDS 路径承载位
// 自「标题栏下方带」迁入「标题栏覆盖层中央」（ChatTabTitleBar 内嵌，96~120vp 定宽），下方
// 带整条取消、列表首卡让位 48→8；本件消费面不变（@Link favSegment 与宿主标题栏承载件
// 共用同一份状态）。搜索入口 = ⋯ 菜单「搜索会话」项（2026-10-29：原标题栏搜索圆键
// 退役，入口下沉菜单首项，动作与二级页契约不动）→ push SessionSearchPage（搜索范围 = 当前
// 助手名下全部会话标题）。本页搜索域（一级页内嵌搜索态）全量退役；焦点结论留档备查：
// defaultFocus 仅对路由页/模态容器「新进入首次」生效（d.ts 限定 Page/NavDestination/Dialog
// 族 + FAQ faqs-arkui-1501），TabContent 内动态挂载不适用——搜索迁路由二级页后 defaultFocus
// 语义直接可用，原 requestFocus hack 随迁退役。最近进入记录点保留于本页 handleOpenCard
//（列表页点卡进入仍记——键/上限/函数见 common/SessionSearch.ets，另一记录点 =
// SessionSearchPage.openConv）。
// ★ 2026-10-27 闲时治理 C3（除雷笔）：行派生纯函数族（conversationRowsEqual /
// applyDraftRows / reconcileSessionRows / repinDraftTop）并入会话行模型件
// ChatSessionRowModel.ets（类型属主即函数属主，SessionListRow 定义在彼件；2026-11-16 P0
// 再自 ChatSessionRows.ets 域级拆出；断言装载读点见 assert-chat-runtime 351/403/2185 组）。
import { SegmentButtonV2Items, UIUtils } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ConversationRow, countWorkspaceTmpFiles, deleteConversations,
  listWorkspaceTmpGroups, renameConversation,
  setConversationFavorite } from '../../common/store/ChatDb';
import { CONV_TITLE_TICK_KEY } from '../../common/TitleGen';
import { PREF_SESSION_CARD_GRID_KEY,
  PREF_NEW_SESSION_ENTRY_KEY, NEW_SESSION_ENTRY_TAB_BAR, NEW_SESSION_ENTRY_FLOAT,
  PREF_CARD_ALPHA_LEVEL_KEY, CARD_ALPHA_DEFAULT,
  resolveNewSessionEntry }
  from '../../common/AppPreferences';
import { cardDescColor } from '../../common/Theme';
import { IMMERSIVE_LEVEL_KEY, overlayMaterial } from '../../common/ImmersiveLevel';
import { recordSessionRecentConv } from '../../common/SessionSearch';
import { PROACTIVE_UNREAD_CONV_KEY, SESSION_LIST_RELOAD_KEY }
  from '../../common/AppBroadcastKeys';
// ★ C3：行派生纯函数族随族并入行模型件（ChatSessionRowModel.ets，2026-11-16 P0 域级拆出）；
// 本壳只引 P0 重拉单点 reconcileSessionRows（按 id 逐行复用旧行，未变行零 new）
import { SessionRows } from './ChatSessionRows';
import { SessionListRow, reconcileSessionRows } from './ChatSessionRowModel';
// 方块档渲染域（2026-11-11 新增）：与 List 档并列的两列 WaterFlow 容器，由偏好整页切换
import { SessionGridRows } from './SessionGridRows';
// ★ 2026-10-16 进会话性能回归修复笔随施工打点（方案 §五「随笔打点」——观测面，见彼件）
import { markEnterProbe } from './ChatEnterProbe';
// 右下悬浮新建键（2026-10-25 复活笔；握姿订阅与几何在彼件，本页只挂载与回调上行）
import { SessionNewFab } from './SessionNewFab';
import {
  hasHiddenSelection, isAllSelectedIn, nextSelectAllIds, SessionMultiselectActionBar
} from './SessionMultiselectBar';
import { ConfirmDialog } from './ConfirmDialog';
import { InputDialog } from './InputDialog';
import { sheetPanelOptions, SheetDetents } from './KimiSheetCommon';
import { SessionMovePanel } from './SessionMovePanel';
// 会话草稿仓库（列表合成打标/合成行/删除级联单源在彼件；★ C3：合成族已并入
// ChatSessionRows，本件只余 NEW_DRAFT_KEY 判据与删除级联）
import { NEW_DRAFT_KEY, removeDraftsWithFiles } from './ChatDraftStore';
// 一级页签列表首查预热（首切闪修复笔）：读取链单源（whenReady + 列表/摘要两读并行）+
// 冷启动预热快照，机制与规范偏离申报见彼件头注释
import { homeListWarmup, SessionListSnapshot } from '../../common/store/HomeListWarmup';

// ★ 本组键已迁零 import 叶子 common/AppBroadcastKeys.ets——与 common 侧 ProactiveGen 写点
// 共享，留在本件构成 common→components 反向依赖（模块环一条边）。
// 多选进入指令键（一次性计数器，勿持久化——防同值不触发 @Watch）：发布方 = HomeNavigation，
// 消费方 = 本组件 @StorageProp @Watch
export const SESSION_MULTISELECT_CMD_KEY: string = 'sessionMultiselectCmd';
// 多选状态广播键（bool 持续状态——勿 persistProp）：本组件写入，宿主消费收起悬浮页签
//（barBottomMargin 巨值推出视口）
export const SESSION_SELECT_MODE_KEY: string = 'sessionSelectMode';
// 多选已选计数广播键（number 持续状态——勿 persistProp）：selectedIds @Watch 写入，
// 宿主消费拼「已选 N 项」
export const SESSION_SELECT_COUNT_KEY: string = 'sessionSelectCount';

// 标题栏内嵌分段后的首卡呼吸间距（vp）：分段胶囊迁入标题栏覆盖层后 HDS 路径无带可让，
// 列表首卡只留 8vp（延续原带内 inset 观感）。真值归本壳，渲染域只收参数
const TITLE_BAR_ROWS_GAP: number = 8;

// ★ 首页 Repeat 试迁：卡片与列表容器两件已迁址 ChatSessionRows.ets（渲染域分立）。

// ═══ 会话卡片菜单（2026-10-30 迁出本件）═══
// 菜单内容、长按参数与材质全部落在渲染域的拆件 SessionCardMenu.ets——本壳不再持菜单
// Builder / ComponentContent 宿主 / openMenu 调用，只把四个动作方法经 SessionRows 下传。
// 触发方式由「卡片右缘四点键点击 + PromptAction.openMenu」改为「长按卡片 + bindContextMenu
// 标准上下文菜单」（同日两千零一十节再退役预览浮起）；原实现保留在 git 历史，勿按旧形制
// 重建锚点 id 或宿主类。

// 「全部/收藏」分段选项单源：胶囊承载位单源在宿主 HomeNavigation 的标题栏覆盖层（本组件
// 经 export 供宿主 import，勿另造副本）
export const CHAT_FAV_SEG_ITEMS: SegmentButtonV2Items = new SegmentButtonV2Items([
  { text: '全部' },
  { text: '收藏' }
]);

@Component
export struct ChatSessionList {
  // 页面存活守卫：置位后本组件迟到异步回调不写状态、不碰 UI、不上行；
  // 写库等数据层意图照常完成
  private departed: boolean = false;
  // 顶部留白（vp，宿主 titleBarInset 下发）：内容区延伸到标题栏背后，首卡静止时
  // 完整落在渐变模糊蒙层下方
  @Prop topPad: number = 0;
  // 底部留白（vp，宿主下发——悬浮页签让位）
  @Prop bottomPad: number = 0;
  // 多选批量条距屏底（vp，宿主传 navBarHeight + 16——批量条悬浮在页签上方；navBarHeight
  // 因设备导航条而异不能写死；多选中页签收起后批量条贴屏底）
  @Prop barBottom: number = 96;
  // 刷新广播（对话页 pop 后重拉列表；见上键注释）
  @StorageProp(SESSION_LIST_RELOAD_KEY) @Watch('onReloadTick') reloadTick: number = 0;
  // 标题刷新广播（AI 写回/占位升级成功 → 重拉列表刷标题行——与上键共用 onReloadTick 回调，
  // 只读幂等多触发无害；common/TitleGen 单键驱动两订阅侧）
  @StorageProp(CONV_TITLE_TICK_KEY) @Watch('onReloadTick') titleTick: number = 0;
  // 更多菜单「多选」指令（计数器——@Watch 值变回调进入多选模式）
  @StorageProp(SESSION_MULTISELECT_CMD_KEY) @Watch('onMultiselectCmd') multiselectCmd: number = 0;
  // 主动消息未读会话（只读订阅——ProactiveGen 落库写入、ChatPage.onPageShown 清空；
  // 红点判定 = row.id === unreadConvId，零 DB 改动零新查询）
  @StorageProp(PROACTIVE_UNREAD_CONV_KEY) unreadConvId: string = '';
  // 点会话卡片回调（宿主执行 push 对话页；presetTitle = 本行标题上抛供首帧预置——
  // 2026-11-15 反馈二笔：异步反查永远晚于首帧，行数据在手同步播种，标题态首帧即达）
  onOpen: (conversationId: string, presetTitle?: string) => void = () => {
  };
  // 新会话合成行点击：宿主接线 HomeNavigation.newConversation 同款逻辑（本地生成会话 id
  // + push 对话页）——进页新 id、查行 null → 认领 '__new__' 槽恢复。★ 右下悬浮新建键
  //（SessionNewFab）共用本回调——同动作单入口，禁另开第二个回调或在此复制 push 链
  onOpenNewSession: () => void = () => {
  };
  // 系统颜色模式（卡底配色；EntryAbility 未写键时缺省浅色——M1 既有缺口，BLOCKED.md 待裁决）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位（★ V2 渲染域三件〔SessionRows/SessionSwipeItem/SessionCardItem〕不能挂
  // V1 @StorageProp，由本壳订阅后标量 @Param 下发；壳侧键变 → build 重跑 → 参数下行即刷）
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  // 沉浸光感档位（长按菜单背板材质随总档——经标量 @Param 下发渲染域，构造 bindContextMenu
  // 的 options 时消费；悬浮新建键恒走官方实底不消费档位，故消费方只有长按菜单）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 会话宫格视图（用户面名称，内部代号方块档；2026-11-11 新增，默认关 = 现有单列列表）：整页换渲染域，非列表档内分叉。
  // 方块档 = 两列 WaterFlow + 两档卡高 + 四点更多键 + 长按菜单，无左右滑；列表档零改动。
  @StorageProp(PREF_SESSION_CARD_GRID_KEY) @Watch('onSessionCardGridChanged')
  sessionCardGrid: boolean = false;
  // 快捷新建键（与 HomeNavigation 迷你栏圆键共用同一键）：只有 'float' 档才挂载右下悬浮
  // 新建键——'off' 与 'tabBar' 档都不建组件；'tabBar' 档圆键由页签栏迷你栏承担，两入口
  // 互斥由单键值域结构性保证。默认 'tabBar'（决明「默认开启页签栏旁这个」），判据经
  // resolveNewSessionEntry 归一（脏值 = 缺省档，与偏好页显示段一致）；@StorageProp 订阅 =
  // 偏好页换档后返回即刷
  @StorageProp(PREF_NEW_SESSION_ENTRY_KEY) newSessionEntry: string = NEW_SESSION_ENTRY_TAB_BAR;
  // 全量行（查询结果本体；迁 Repeat 后与 favSegment 一并 @Watch 汇聚——任一赋值即重算
  // visibleRows，见 syncVisibleRows）
  @State @Watch('syncVisibleRows') private rows: SessionListRow[] = [];
  // 可见行（「全部/收藏」分段过滤产物 = 传给渲染域 Repeat 的数据源本体）。★ 为何落 @State：
  // 官方《状态管理V1和V2混用指导》要求跨 V1→V2 传递的复杂类型须为 V1 状态变量且经
  // UIUtils.enableV2Compatibility 使能 V2 观察（Repeat 懒加载模式的数据源必须具 V2 观察能力）；
  // 唯一写入口 = syncVisibleRows——漏挂 @Watch 即列表停旧态且静默（本机制唯一失效面，迁移
  // 四页同型）
  @State private visibleRows: SessionListRow[] = [];
  @State private hintText: string = '';
  // 首拉完成闸：false = 首次查询在途——空态卡不显示（防列表初值空态闪现）；查询落定
  //（成功/失败）置真后空列表才显示空态
  @State private loaded: boolean = false;
  // ── 会话收藏（搜索域已随改版迁二级页 SessionSearchPage，本页只留收藏分段）──
  // 收藏分段（0 = 全部 / 1 = 收藏）：切换内存过滤不重查库（@Watch 收敛到 syncVisibleRows
  // 重算——Repeat 数据源整体换新，不再逐项重建）。★ @State 改 **@Link**——状态上提到宿主
  // HomeNavigation（胶囊标题栏承载件在它那侧）；@Watch 留在本侧
  //（@Link 可挂 @Watch，父侧赋值经链路传导即回调）；实例化传 `$chatFavSegment`
  @Link @Watch('syncVisibleRows') favSegment: number;
  // 分段选项表 = 模块级 CHAT_FAV_SEG_ITEMS（单源，见文件头）
  // 首行额外让位（vp）：分段胶囊在标题栏覆盖层内、下方无带 ⇒ 恒 8vp 呼吸
  //（TITLE_BAR_ROWS_GAP，延续原带内 inset 语义）。渲染域 topClearance 参与 0 行提示行
  // margin 两处共用本方法单源——各写一份即两处让位分叉
  private topClearance(): number {
    return TITLE_BAR_ROWS_GAP;
  }
  // ── 多选模式（dshinhm KimiSessionList 二二一改同款）──
  // 多选中（菜单指令进入；批量删除成功/手动取消退出）。★ 补挂 @Watch 汇聚
  // syncVisibleRows——新会话合成行的多选过滤（进出两向重算）需它驱动，不补则进出多选
  // 不重算、过滤不生效；对既有「已选 ⊆ 可见」清空不变量无副作用（进多选时已选空、出多选
  // 时 ids 全可见，均不触发清空分支——方案 §6.1-3 实锤）
  @State @Watch('syncVisibleRows') private selectMode: boolean = false;
  // 选中待删除的会话 id（点卡片切换；数据有界：上限 = 当前列表条数）。★ @Watch 挂计数
  // 广播——勾选切换/全选/可见集清空/退出四路写点全走整体赋值即触发，宿主标题
  //「已选 N 项」随勾选实时刷
  @State @Watch('syncSelectCount') private selectedIds: string[] = [];
  // 界面实宽（vp，根容器 onAreaChange 实测）：只服务右下悬浮键的左位定位（position.right =
  // 宽度 − 键宽 − 16）——不参与列表布局，0 = 未测得时键维持右侧
  @State private viewWidth: number = 0;
  // 上次已同步的分段值（切分段清空已选的判据——syncVisibleRows 内逐次比较，初值 0 = 缺省段，
  // 挂载首帧无差异故不清空；非状态变量，不驱动 UI）
  private lastSyncedSegment: number = 0;
  // 批量删除请求进行中（批量按钮防重复点击 + 确认弹窗防重开）
  @State private deleting: boolean = false;
  // 删除确认/重命名弹窗控制器（★ 组件成员——d.ts:735「CustomDialogController is effective
  // only when it is a member variable of the @CustomDialog and @Component」：普通类成员构造
  // open() 静默无效（坑7 真机实锤）。每次打开重建，无强制 dispose 要求）
  private confirmCtrl: CustomDialogController | null = null;
  private renameCtrl: CustomDialogController | null = null;
  // ── 会话移动 ── 移动目标会话 id（卡片菜单/侧滑「移动」键回调写入；面板经 MoveSheet 载体读取）
  @State private moveTargetId: string = '';
  // 移动面板开关（bindSheet 挂本件根 Stack——规范-半模态 §1 判据三条天然满足：合法树内 /
  // 根 Stack 不随数据销毁 / isShow 与触发键同组件位。★ TabContent 槽内 bindSheet 可用性
  // 本项目无先例 = 本笔最大待验项：真机首验项入 BLOCKED；若不弹按调研档 §四第 2 步备选
  // 改挂 HomeNavigation 根〔面板件与回调契约逐字不变，只换宿主〕）
  @State @Watch('onSheetVisibleChanged') private moveSheetShow: boolean = false;
  // ── 关闭-再开协调（机制单源 = KimiSheetCommon.sheetPanelOptions 第四参注释）──：关闭后
  // 离场动效在途期内再点「移动到助手」，直接写的可见性 true 会被吞或被压回——在途期只记
  // 开意图，动效结束再补开
  private sheetClosing: boolean = false;
  private pendingOpen: boolean = false;
  // ── R2-b 重拉合并闩（非 UI 状态用普通成员——状态最小化红线）──
  // reload 在途闩 + 尾部补跑意图。机制：reload 单入口先查闩，在途期的新请求（同帧多次
  // tick、#22 撞车、收藏/重命名等直调）**不叠发并发查询**（并发两查乱序落地 = 旧数据覆盖
  // 新数据），只记意图；收尾（finishReload 单点）时意图在场**必补跑一次**——★ 禁丢弃：在途
  // 那查可能取不到意图背后的新写入（DB 落库晚于查询执行），尾部真跑是唯一保刷新手段，丢刷新
  // = 列表停旧态；补跑结果一致则被 R2-a 比对吞掉（只多一次毫秒级本地查询）。同帧 N 次 tick
  // 收敛 = 恰 1 次立即 + 至多 1 次尾部
  private reloadInFlight: boolean = false;
  private reloadPending: boolean = false;
  // ── R2-c 滚动空闲闸（非 UI 状态，不驱动渲染）──
  // 退页 400ms 只是推迟查询起点，不能保证回包与整表赋值避开用户滑动。滚动中 reload 只记
  // reloadPending，不发起新查询；已经在途的回包只保留最新一份 deferredSnap。onScrollStop
  // 先落该回包、再按 pending 补查，兼顾「滑动中来 tick」与「查询在途时开始滑动」两种交错。
  private listScrolling: boolean = false;
  private deferredSnap: SessionListSnapshot | null = null;

  aboutToAppear(): void {
    // 预热快照同步消费（首切闪修复笔，首建一次成型）：命中即 build 前同步走完行合成 + 比对
    // + 赋值——首帧即完整列表；miss（预热未完成 / 空快照 / 已消费）转 reload 异步链
    //（在途时与启动链预热共享同一查询，不双发）
    const warm: SessionListSnapshot | null = homeListWarmup.peekSessionSnapshot();
    if (warm !== null) {
      this.applySessionSnapshot(warm);
    } else {
      this.reload();
    }
  }

  aboutToDisappear(): void {
    this.departed = true;
    // 寿命匹配：组件带多选态销毁时撤销页签收起广播——否则 AppStorage 残留 true、页签永久
    // 收起无法恢复；计数一并归零（标题「已选 N 项」的 N 不残留）
    if (this.selectMode) {
      AppStorage.setOrCreate<boolean>(SESSION_SELECT_MODE_KEY, false);
      AppStorage.setOrCreate<number>(SESSION_SELECT_COUNT_KEY, 0);
    }
  }

  // 空占位 item（原 openMenu 宿主 init 用）随菜单宿主退役——长按菜单每次按下按当前行
  // 现场组装参数，不存在「列表未加载时先建占位节点」的场景。

  // 菜单回调组装与 openCardMenu 已随菜单域迁出本件（2026-10-30）：渲染域按「按下当刻」
  // 的行对象自行组装 menuParams，四个动作经 SessionRows 的 @Event 回到本件的同名方法。

  // ── 会话移动（调研档 = docs/调研-会话移动-竞品机制与落地风险-20260930.md）──

  // 打开移动面板（卡片菜单「移动到助手」唯一入口）
  private openMoveSheet(row: ConversationRow): void {
    this.moveTargetId = row.id;
    this.requestOpen();
  }

  // ── 关闭-再开协调（机制说明见字段注释；与会话轨迹页/请求日志页同配方）──
  // 开意图落定 → 动效在途挂起 / 否则即开（applyOpen 单入口，补开两路共用）
  private requestOpen(): void {
    this.pendingOpen = true;
    if (this.sheetClosing) {
      return; // 动效在途：待补开
    }
    this.applyOpen();
  }

  private applyOpen(): void {
    if (!this.pendingOpen) {
      return;
    }
    this.moveSheetShow = true;
  }

  // 离场动效结束（sheetPanelOptions 第四参——d.ts：动画结束后回调）：清在途位 + 按开意图补开
  private onSheetGone(): void {
    this.sheetClosing = false;
    if (!this.moveSheetShow) {
      this.applyOpen();
    }
  }

  // 可见性变化兜底（@Watch）：框架 `$$` 收尾回写把可见性压回 false 时按开意图补一次；
  // 用户关闭必经 requestCloseMove（先清开意图再写 false），不会误触本支
  private onSheetVisibleChanged(): void {
    if (!this.moveSheetShow) {
      this.applyOpen();
    }
  }

  // 移动面板关闭入口（规范 §1 硬约束：标题栏 xmark 与 onWillDismiss 两路同调本方法；面板
  // 无暂存不接确认弹窗——点选即落库属负面清单「点一下就落库的」）。关闭单入口 = 先清开意图
  // + 置离场动效在途位，再写可见性（关闭-再开协调，见字段注释）
  private requestCloseMove(): void {
    this.pendingOpen = false;
    this.sheetClosing = true;
    this.moveSheetShow = false;
  }

  // 移动面板内容（坑51 红线：bindSheet builder 位挂组件内 @Builder；数据自持有在面板件内）
  @Builder
  MoveSheet() {
    SessionMovePanel({
      conversationId: this.moveTargetId,
      // 尾部让位（barBottom = 宿主下发的导航条高 + 16——本件可得口径；面板内再 +24 固定呼吸）
      bottomInset: this.barBottom,
      onMoved: (): void => {
        this.requestCloseMove();
        this.reload();
        // 落库广播（源/目标两侧消费：助手页「会话 N」chip 等订阅方；一次性计数器形态自增
        //——写固定值 @Watch 不触发；本页自订阅多一次重拉幂等无害，同 deleteOne 口径）
        AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
          (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
      },
      onClose: (): void => {
        this.requestCloseMove();
      }
    })
  }

  // 收藏开关执行（菜单「收藏/取消收藏」唯一入口）：落库 → toast + 重拉（新行对象经
  // Repeat item 比对刷星标；收藏段内取消收藏 = rows 重算后自然离列）；失败 toast 可重试
  //（P0-1）。不动 updatedAt（时间序不变）
  private async toggleFavorite(row: ConversationRow): Promise<void> {
    try {
      await setConversationFavorite(row.id, !row.favorite);
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast(
        { message: row.favorite ? '已取消收藏' : '已收藏' });
      this.reload();
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast(
        { message: (row.favorite ? '取消收藏失败：' : '收藏失败：') + (e as Error).message });
    }
  }

  // 点击卡片进入（2026-11-17 整体退役加密会话后无门禁）：记录最近进入后上行宿主 push。
  // ★ 最近进入记录（本页点卡进入仍是记录点之一）：去重移头、上限 3 条在 SessionSearch 内收敛
  private handleOpenCard(row: ConversationRow): void {
    // ★ 新会话合成行守卫（首行）：跳过 recordSessionRecentConv（防 '__new__' 记进持久记录
    // 留脏 id）+ 走新建链上行（进页查行 null → 认领 '__new__' 槽恢复）。严禁把 '__new__'
    // 直接当 conversationId push（ensureConversation 会建出 id='__new__' 的脏行）
    if (row.id === NEW_DRAFT_KEY) {
      this.onOpenNewSession();
      return;
    }
    // ★ 打点（进会话性能回归修复笔方案 §五）：点击参考点——进页链各时点（shell/swap/
    // content/anchor）均按本点输出差分毫秒（读数口径见 ChatEnterProbe）
    markEnterProbe('tap');
    recordSessionRecentConv(row.id);
    this.onOpen(row.id, row.title);
  }

  // 重拉广播回调（两键共用；★ R2-b：标题 tick 与退出 tick 同帧/在途撞车〔#22〕由 reload
  // 单入口的 reloadInFlight 闩收敛——同帧多次只一次立即在途 + 尾部必跑一次，机制见闩注释）
  onReloadTick(): void {
    this.reload();
  }

  onMultiselectCmd(): void {
    // 进入多选（重复点击菜单 = 已在多选中无操作幂等；退出通道 = 批量条「取消」或
    // 批量删除成功）+ 广播状态（页签收起——HomeNavigation 消费）+ 计数显式归零
    //（防上次实例残留脏值——@Watch 只在赋值时触发，空集进场不触发）
    if (!this.selectMode) {
      this.selectMode = true;
      AppStorage.setOrCreate<boolean>(SESSION_SELECT_MODE_KEY, true);
      AppStorage.setOrCreate<number>(SESSION_SELECT_COUNT_KEY, this.selectedIds.length);
    }
  }

  // 已选计数广播（selectedIds 唯一 @Watch 汇聚——勾选切换/全选切换/可见集清空/退出四路
  // 写点全走整体赋值即触发；宿主 HomeNavigation tabTitle 消费拼「已选 N 项」）
  private syncSelectCount(): void {
    AppStorage.setOrCreate<number>(SESSION_SELECT_COUNT_KEY, this.selectedIds.length);
  }

  // 可见行重算（唯一入口：rows / favSegment / selectMode 三状态 @Watch 汇聚；★ 迁 Repeat
  // 由「build 内派生」改「@Watch 收敛的状态重算」——理由见 visibleRows 成员注释；分段内存
  // 过滤不重查库、不动时间序）
  private syncVisibleRows(): void {
    const segmentRows: SessionListRow[] = this.favSegment === 1
      ? this.rows.filter((row: SessionListRow): boolean => row.favorite)
      : this.rows;
    // 多选守卫（与 favSegment 过滤同位）：selectMode 为真时滤掉 '__new__' 合成行——不可
    // 勾选、不被全选 sweep 进 deleteConversations(['__new__'])
    const guarded: SessionListRow[] = this.selectMode
      ? segmentRows.filter((row: SessionListRow): boolean => row.id !== NEW_DRAFT_KEY)
      : segmentRows;
    // 顺序恒「最新在上」——排序偏好已退役、行为固化为不可反转，不再做显示层 reverse 与
    // 草稿重钉顶；收藏分段过滤与多选守卫保留在前，多选「已选 ⊆ 可见」不变量不受影响。
    const next: SessionListRow[] = guarded;
    const segmentChanged: boolean = this.favSegment !== this.lastSyncedSegment;
    this.lastSyncedSegment = this.favSegment;
    // ★ 可见集一变即清空已选，保住「已选 ⊆ 可见」不变量——否则批量条两态判据失真（主按钮
    // 计数会含屏幕上看不见的行，一点删除就删掉看不到的会话）。两路触发：①段值变；②已选含
    // 不可见行——同一条不变量的兜底，覆盖段值不变而可见集整体换掉的同类源：换助手（reload
    // 按 ACTIVE_ASSISTANT_KEY 重过滤，而 HDS 路径本组件活在 TabContent 里跨页签不销毁）、
    // 备份恢复、他处删行。★ rows 单纯的「增长」不触发（主动消息落库 / 标题写回重拉）——已选
    // 仍在可见集内，用户手上的选择不被后台写入打断；second 支带空选短路，非多选态零开销
    if (segmentChanged || (this.selectedIds.length > 0
      && hasHiddenSelection(this.idsOf(next), this.selectedIds))) {
      this.selectedIds = [];
    }
    this.visibleRows = next;
  }

  // 空态文案（分段分治）：收藏段空 = 「暂无收藏会话」；全部段空维持「该助手暂无会话」
  private emptyText(): string {
    return this.favSegment === 1 ? '暂无收藏会话' : '该助手暂无会话';
  }

  // 列表/宫格切换时旧容器可能来不及回送 onScrollStop；换档即按停止收口，防滚动位卡住
  private onSessionCardGridChanged(): void {
    this.onListScrollingChanged(false);
  }

  // 两档滚动事件唯一入口：重复起止幂等；首拉 loaded=false 不在 reload/apply 中推迟。
  // 停止时先消费在途成功回包，再兑现滚动期间累积的补查意图（pending 只存一个，天然合并）。
  private onListScrollingChanged(scrolling: boolean): void {
    if (this.departed || this.listScrolling === scrolling) {
      return;
    }
    this.listScrolling = scrolling;
    if (scrolling) {
      return;
    }
    const snap: SessionListSnapshot | null = this.deferredSnap;
    this.deferredSnap = null;
    if (snap !== null) {
      this.applySessionSnapshot(snap);
    }
    if (this.reloadPending) {
      this.reloadPending = false;
      this.reload();
    }
  }

  private reload(): void {
    // ★ R2-c 首拉完成后，滚动中只记尾部意图，连查询与摘要清洗也推迟到停止后
    if (this.listScrolling && this.loaded) {
      this.reloadPending = true;
      return;
    }
    // ★ R2-b 在途闩：在途期只记意图不叠发（同帧多次 tick 收敛 + #22 撞车合并；直调方同守）
    if (this.reloadInFlight) {
      this.reloadPending = true;
      return;
    }
    this.reloadInFlight = true;
    // 读取链单源 = HomeListWarmup.fetchSessionSnapshot（首切闪修复笔外迁，页面与预热共用）：
    // DB 就绪守卫（whenReady——冷启动 DB 未就绪即查库会抛错钉死提示，init 失败提示重启）
    // + 助手过滤现读（缺省 = 默认助手；'' 存量行归默认口径在 historyFilterIds）+ 摘要与列表
    // 两读并行（摘要失败回落空 Map 不阻断列表）；预热在途时与启动链预热共享同一查询不双发。
    // ★ R2-b 单链收尾：三条出路（查询成功 / 快照交付 / 查询失败）全部必经 finishReload，闩不卡死
    homeListWarmup.awaitSessionSnapshot()
      .then((snap: SessionListSnapshot): void => {
        if (this.departed) {
          return;
        }
        this.applySessionSnapshot(snap);
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.hintText = (e as Error).message; // fetch 侧拼好（DB 未就绪 / 读取失败两族文案）
      })
      .finally((): void => {
        this.finishReload();
      });
  }

  // 查询结果落屏单点（aboutToAppear 预热同步路径与 reload 异步路径共用）：P0 逐行复用 →
  // R2-a 全等跳过 → 一次性赋值。★ U9 行合成：DB 行 + 运行态生成中标记（loading 进比对清单
  //——漏比即标记静默冻结）；草稿行合成接续：草稿打标 + '__new__' 合成行（reconcileSessionRows，
  // draft 进比对清单同族；合成行随行序头部插入 = newest 默认序恒置顶）；合成参数 activeId
  // 用快照携带的查询时刻值（与行数据同一过滤口径——混用现读值会在切助手竞态下错配）。
  // ★ P0（2026-11-16）：reconcileSessionRows 按 id 复用旧行，未变行不再 new；返回 null =
  // 新旧行集逐项同引用同序，跳过辅助赋值（R2-a 语义不变）。旧路径 applyDraftRows 每次重拉
  // 先造 2N 个对象再比对，退页重拉落在滑动窗口时这批垃圾会推高 GC 触发概率。
  private applySessionSnapshot(snap: SessionListSnapshot): void {
    // 查询起点早于本次滑动时，回包仍可能在滚动中到达；只留最新快照，停止后统一落屏。
    // 首拉不推迟，保证空列表首次查询无论是否触发回弹滚动都能立即出内容。
    if (this.listScrolling && this.loaded) {
      this.deferredSnap = snap;
      return;
    }
    this.deferredSnap = null;
    // ★ 成功读取即清上次失败提示（2026-11-16 自检轮修）：hintText 只在 reload 的 catch 写，
    // 成功路径不清则一次读取失败后提示行永久跟随末卡（visibleRows>0 时由渲染件尾行呈现，
    // 且空态卡判据要求 hintText==='' 故空列表也不再显示空态）——本函数是唯一落屏单点，
    // 清点放此处 = 两分支（null 跳过赋值 / 赋值）共同收口；同值赋值不触发刷新，零开销
    this.hintText = '';
    const rows: SessionListRow[] | null = reconcileSessionRows(this.rows, snap.queried,
      snap.activeId, snap.snippets);
    if (rows === null) {
      this.loaded = true;
      return;
    }
    this.rows = rows;
    this.loaded = true;
  }

  // R2-b 收尾单点（reload 全部出路的汇合处）：释闩 + 意图在场必补跑一次——★ 尾部必跑、
  // 禁丢弃（丢刷新 = 列表停旧态，见闩注释）；补跑再入 reload 时闩已释，无递归在途叠加
  private finishReload(): void {
    this.reloadInFlight = false;
    if (this.reloadPending) {
      this.reloadPending = false;
      this.reload();
    }
  }

  // ── 多选模式（dshinhm KimiSessionList 二二一改同款）──

  // 行集 → id 集（全选两态判据、全选动作与「已选含不可见行」判据的共同输入——可见集单源，
  // 勿在别处重造）
  private idsOf(rows: SessionListRow[]): string[] {
    return rows.map((row: ConversationRow): string => row.id);
  }

  // 全选/全不选（批量条左端键）：全选态 → 清空已选；否则 → 选中当前可见全部（分段过滤后的
  // 可见集，非全量 rows——「所见即所选」）。判据纯函数在 SessionMultiselectBar（两页共用单源）
  private toggleSelectAll(): void {
    this.selectedIds = nextSelectAllIds(this.idsOf(this.visibleRows), this.selectedIds);
  }

  // 点击卡片切换勾选（selectedIds 整体替换；勾选圈回显 = 渲染域逐行 @Param selected 传播
  //——迁 Repeat 后不再用键含选中后缀的重建机制）
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
      // customStyle 不传 = 官方对话框底板（领导指令「删除弹窗材质统一为重命名的」——与
      // InputDialog 同款官方实底，形态单一来源见 ConfirmDialog.ets 文件头）
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
    // 临时区级联拦截句（地基笔 §3.4-② + 勘误改判条件句：listWorkspaceTmpGroups 一次扫根，
    // 与选中集有交集才加句——无交集零提示，不做逐会话计数）
    const tmpGroups = listWorkspaceTmpGroups();
    let tmpHit = false;
    for (const group of tmpGroups) {
      if (this.selectedIds.indexOf(group.conversationId) >= 0) {
        tmpHit = true;
        break;
      }
    }
    this.openDeleteConfirm('将彻底删除选中的 ' + this.selectedIds.length
      + ' 个会话及其全部聊天记录，不可恢复。'
      + (tmpHit ? '选中会话的临时文件将一并删除。' : ''), (): void => {
      this.deleteSelected();
    });
  }

  // 打开重命名官方弹窗（领导指令「重命名参考旧项目」——dshinhm 一八二改同款 InputDialog；
  // 每次打开重建 controller；构造在组件成员位——坑7）；初值 = 当前标题（空标题兜底
  //「新对话」，与卡片展示一致）
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

  // 单条删除确认（★ 自会话侧滑笔自 menuCallbacks.onDelete 内联段抽出——卡片菜单与侧滑删除
  // 键共用同一确认链，避免两处文案/计数逻辑漂移）。临时区级联拦截句（点开时轻量扫该会话
  // 临时目录计数，>0 才加句——同步 fs 列举毫秒级，不逐会话预查）；确认后走 deleteOne 事务
  // 级联。★ 决明令：'__new__' 合成行删除 = 删草稿本体（无会话行无库记录——WithFiles 档
  // 单元素数组清条目与附件文件，reload 后合成行随 reconcileSessionRows 自然消失，无 DB 变更不广播）
  private confirmDeleteOne(row: ConversationRow): void {
    if (row.id === NEW_DRAFT_KEY) {
      this.openDeleteConfirm('将删除该草稿，不可恢复。', (): void => {
        removeDraftsWithFiles([NEW_DRAFT_KEY]);
        this.reload();
        this.getUIContext().getPromptAction().showToast({ message: '草稿已删除' });
      });
      return;
    }
    const tmpCount: number = countWorkspaceTmpFiles(row.id);
    this.openDeleteConfirm('将彻底删除会话「'
      + (row.title !== '' ? row.title : '新对话')
      + '」及其全部聊天记录，不可恢复。'
      + (tmpCount > 0 ? '删除后该会话的 ' + tmpCount + ' 个临时文件将一并删除。' : ''),
      (): void => {
        this.deleteOne(row.id);
      });
  }

  // 单条删除执行：确认弹窗与删除链路同多选删除（ConfirmDialog + deleteConversations 事务
  // 级联，单 id 数组为新建普通数组非代理——坑6 族无暴露）；失败 toast 可重试（P0-1）
  private async deleteOne(id: string): Promise<void> {
    try {
      const count: number = await deleteConversations([id]);
      if (this.departed) {
        return;
      }
      // 草稿级联清（DB 事务碰不到内存草稿与其无库行附件文件，UI 侧显式级联——WithFiles
      // 档：删条目 + 级联删附件，方案 §4 调用点①）
      removeDraftsWithFiles([id]);
      this.rows = this.rows.filter((row: ConversationRow): boolean => row.id !== id);
      // 删行已落库 → 广播重拉（★ 复验轮补写点：本页本地移除只覆盖自己在场时的列表，跨页签
      // 消费方不知道——助手页「会话 N」chip 正订阅同键；一次性计数器自增。本页自订阅重拉
      // 一次幂等无害）
      AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
        (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
      this.getUIContext().getPromptAction().showToast({ message: '已删除 ' + count + ' 个会话' });
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
    }
  }

  // 重命名执行（空值/同值校验在弹窗内，此处 P0-1 兜底 toast）：本地 DB 直写 → 成功 toast
  // + 重拉列表（不动 updatedAt 故时间序不变）；失败 toast、列表不动可重试
  private async applyRename(id: string, text: string): Promise<void> {
    try {
      await renameConversation(id, text);
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '已重命名' });
      this.reload();
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '重命名失败：' + (e as Error).message });
    }
  }

  // 批量删除执行（确认弹窗「删除」回调）：全成功本地移除 + 广播重拉 + toast + 退出多选；
  // 失败 toast 且保留选择（可调整后重试，P0-1 不静默）。★ 复验轮改写：本地移除只考虑了
  // 本页自己——跨页签的助手页卡面「会话 N」chip 订阅同键，删完切回助手页签即停旧数，故此侧
  // 必须广播；本地移除保留（即时反馈，不等重查），自订阅多一次重拉幂等无害
  private async deleteSelected(): Promise<void> {
    if (this.selectedIds.length === 0 || this.deleting) {
      return;
    }
    this.deleting = true;
    try {
      const ids: string[] = this.selectedIds;
      const count: number = await deleteConversations(ids);
      if (this.departed) {
        return;
      }
      // 草稿级联清（同 deleteOne——方案 §4 调用点②批形态；合成行已被多选守卫滤出，不进 ids）
      removeDraftsWithFiles(ids);
      this.rows = this.rows.filter((row: ConversationRow): boolean => ids.indexOf(row.id) < 0);
      // 删行已落库 → 广播重拉（同上 deleteOne：单条/批量两条删除链都不得漏此写点——漏一处
      // 即「删了会话、助手页 chip 不停更」；一次性计数器形态自增）
      AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
        (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
      this.getUIContext().getPromptAction().showToast({ message: '已删除 ' + count + ' 个会话' });
      this.exitMultiselect();
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
    } finally {
      this.deleting = false;
    }
  }

  build() {
    // alignContent Top（顶部对齐：0 行提示行 margin 定位依赖；既有全尺寸子组件不受对齐影响）
    Stack({ alignContent: Alignment.Top }) {
      // ── 会话列表（★ 首页 Repeat 试迁：Scroll+Column+ForEach → 渲染域组件 SessionRows
      //    〔List + Repeat.virtualScroll，V2 机制〕——卡片与列表容器在 ChatSessionRows.ets，
      //    机制实读与红线见该件头注释；数据源与全部行级状态在此按官方《状态管理V1和V2混用
      //    指导》桥接：visibleRows 与 selectedIds 两个 V1 @State 经 UIUtils.enableV2Compatibility
      //    传入〔构造处调用——整体赋值随壳 build 重跑重新使能〕，其余为标量 @Param）──
      // ── 会话列表两档（2026-11-11 决明拍板「新增偏好开关，可把对话页卡显示成方块」）：
      //    整页换渲染域，不在 List 档里分叉（顺手大重构禁区）。两档参数逐项对齐，点卡 /
      //    勾选 / 四个动作全部复用本壳既有方法，零新增业务路径；数据源仍经
      //    UIUtils.enableV2Compatibility 桥接（Repeat 懒加载要求 V2 观察能力，见
      //    ChatSessionRows 机制①）。方块档交互与形制见 SessionGridRows.ets 头注释 ──
      if (this.sessionCardGrid) {
        SessionGridRows({
          visibleRows: UIUtils.enableV2Compatibility(this.visibleRows),
          hintText: this.hintText,
          topPad: this.topPad,
          topClearance: this.topClearance(),
          bottomPad: this.bottomPad,
          selectMode: this.selectMode,
          selectedIds: UIUtils.enableV2Compatibility(this.selectedIds),
          unreadConvId: this.unreadConvId,
          appColorMode: this.appColorMode,
          cardAlphaLevel: this.cardAlphaLevel,
          immersiveLevel: this.immersiveLevel,
          onScrollingChanged: (scrolling: boolean): void => {
            this.onListScrollingChanged(scrolling);
          },
          onOpen: (row: ConversationRow): void => {
            this.handleOpenCard(row);
          },
          onToggle: (id: string): void => {
            this.toggleSelect(id);
          },
          onFavorite: (row: ConversationRow): void => {
            this.toggleFavorite(row);
          },
          onRename: (row: ConversationRow): void => {
            this.openRenameDialog(row);
          },
          onMove: (row: ConversationRow): void => {
            this.openMoveSheet(row);
          },
          onDelete: (row: ConversationRow): void => {
            this.confirmDeleteOne(row);
          }
        })
          .width('100%')
          .height('100%')
          // 渐显链与列表档同源（冷启动首拉在途藏空白，落屏 200ms EaseOut）
          .opacity(this.loaded || this.hintText !== '' ? 1 : 0)
          .animation({ duration: 200, curve: Curve.EaseOut })
      } else {
        SessionRows({
          visibleRows: UIUtils.enableV2Compatibility(this.visibleRows),
          hintText: this.hintText,
          topPad: this.topPad,
          // 顶部额外让位：恒 TITLE_BAR_ROWS_GAP（胶囊在标题栏覆盖层内，无带可让），
          // 多选态归零由渲染件 selectMode 三目承接
          topClearance: this.topClearance(),
          bottomPad: this.bottomPad,
          selectMode: this.selectMode,
          selectedIds: UIUtils.enableV2Compatibility(this.selectedIds),
          unreadConvId: this.unreadConvId,
          appColorMode: this.appColorMode,
          cardAlphaLevel: this.cardAlphaLevel,
          // 沉浸光感档位（长按菜单背板材质随总档——渲染域标量消费，不自己挂 V1 订阅）
          immersiveLevel: this.immersiveLevel,
          onScrollingChanged: (scrolling: boolean): void => {
            this.onListScrollingChanged(scrolling);
          },
          onOpen: (row: ConversationRow): void => {
            this.handleOpenCard(row); // 读当前行（记录最近进入 + 上行 push）
          },
          onToggle: (id: string): void => {
            this.toggleSelect(id);
          },
          // 四个动作（侧滑四键与长按菜单共用同一批）：全部落到本件既有动作方法，不新增业务
          // 路径——收藏 = toggleFavorite（落库 + reload）、删除 = confirmDeleteOne（确认弹窗 +
          // 级联）、重命名 = InputDialog、移动 = 半模态
          onFavorite: (row: ConversationRow): void => {
            this.toggleFavorite(row);
          },
          onRename: (row: ConversationRow): void => {
            this.openRenameDialog(row);
          },
          onMove: (row: ConversationRow): void => {
            this.openMoveSheet(row);
          },
          onDelete: (row: ConversationRow): void => {
            this.confirmDeleteOne(row);
          },
          // 触摸预载整件已退役（2026-10-18）：进页一律走读库单一路径
        })
          .width('100%')
          .height('100%')
          // 进场渐显（★ 首切闪修复观感笔，决明拍板「列表也做渐显」+ 调参 500→200ms）：冷启动
          // 首拉在途（loaded=false 且无失败提示）列表整层 opacity 0 藏空白，数据落屏置位后
          // 200ms EaseOut 渐显（区别于消息区/会话页壁纸的 500 档）。预热快照同步命中路径首帧
          // 即 1 = 直显不播——一次成型场景零动画开销；reload 刷新 loaded 恒 1 不重播（只有
          // 首建播）。提示行/空态卡在外层条件渲染不受本层辖——失败报告行即时可见（P0-1）。
          // ★ animation 辖域只辖 opacity，声明位紧随其后
          .opacity(this.loaded || this.hintText !== '' ? 1 : 0)
          .animation({ duration: 200, curve: Curve.EaseOut })
      }

      // ── 读取失败提示行 · 0 行兜底（★ Repeat 迁）：>0 行时由渲染域随末卡尾行呈现；0 行时
      //    Repeat 无行可挂，本层以同一定位常量补位——hintText 即便 0 行也能见（P0-1）──
      if (this.visibleRows.length === 0 && this.hintText !== '') {
        Text(this.hintText)
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_warning'))
          .width('calc(100% - 32vp)')
          // 让位与首行同源（多选态分段面收起 → 同步归零；常态让位吃 topClearance 单源方法，
          // 与渲染域同值）
          .margin({ top: this.topPad + (this.selectMode ? 0 : this.topClearance()) })
      }

      // ── 空态卡：当前分段结果为空时全高垂直居中提示——dshinhm 同款形态（居中文字 +
      // 次要色深浅自适应，底部抵消 topPad 悬蒙层下视觉居中）。文案分治见 emptyText；
      // 首拉在途（loaded=false）与加载失败（hintText 覆盖层提示）不显示 ──
      if (this.loaded && this.hintText === '' && this.visibleRows.length === 0) {
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

      // ── 「全部/收藏」分段胶囊：承载位单源在宿主标题栏覆盖层中央（ChatTabTitleBar 内嵌），
      // 本组件内容区不渲染胶囊、勿在此按旧悬浮层形制补回；favSegment @Link 状态由宿主
      // 承载件与本壳共用，切换内存过滤不重查库（@Watch 收敛到 syncVisibleRows 重算）；
      // 多选态胶囊由宿主侧收起（标题切「已选 N 项」计数态），首行让位经 selectMode
      // 三目同步归零 ──

      // ── 多选批量条（决明拍板「采用无主按钮路线」：SessionMultiselectActionBar 图标三键
      //（HdsActionBar，计数文字随形态退役——计数反馈保留在确认弹窗）。多选中才挂载——
      // 普通模式零渲染零命中负担 ──
      if (this.selectMode) {
        SessionMultiselectActionBar({
          // 全选两态（驱动图标 fill/描边切换——判据纯函数单源在 SessionMultiselectBar 件）
          allSelected: isAllSelectedIn(this.idsOf(this.visibleRows), this.selectedIds),
          deleting: this.deleting,
          // 距底去 16vp 呼吸间距 = 与悬浮页签常态几何重合（多选中页签已收起，批量条
          // 独占其位；barBottom 口径见 HomeNavigation）
          barBottom: this.barBottom - 16,
          onCancel: (): void => {
            this.exitMultiselect();
          },
          onPrimary: (): void => {
            this.confirmDeleteSelected();
          },
          onToggleAll: (): void => {
            this.toggleSelectAll();
          }
        })
      }
      // ── 右下悬浮新建键（复活笔，决明指令「一级页右下悬浮新建键（智感握姿跟随）」；
      //    标题栏新建入口不撤〔现 = 「更多」菜单首项〕，两入口同动作）。组件件自持 motion
      //    握姿订阅（on/off 成对，寿命 = 组件而非本页壳）；形制 = 局部容器绝对定位（键以外
      //    零覆盖，卡片无按压蒙层）；多选态 hide（Visibility 隐藏不销毁，保留左右位与订阅）；
      //    点击走 onOpenNewSession 既有链，禁复制 push 逻辑。挂载条件 = 偏好 'float' 档
      //    ——与页签栏旁圆键共用两档键〔★ 2026-10-30 两档化，原 'off' 档退役〕、互斥由值域
      //    保证；判据经 resolveNewSessionEntry 归一──
      if (resolveNewSessionEntry(this.newSessionEntry) === NEW_SESSION_ENTRY_FLOAT) {
        SessionNewFab({
          hide: this.selectMode,
          barBottom: this.barBottom,
          contentWidth: this.viewWidth,
          onTap: (): void => {
            this.onOpenNewSession();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    // 界面实宽实测（局部容器的左位 position.right 需要内容区宽度；普通成员语义但需驱动
    // 子件重算 → @State；一次实测后仅换机/分栏变化才变）
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const width: number = newArea.width as number;
      if (width > 0 && width !== this.viewWidth) {
        this.viewWidth = width;
      }
    })
    // 会话移动半模态（挂本件根 Stack；档位 [MEDIUM, LARGE] 半屏起——规范-半模态 §4 选择器/
    // 列表类；onWillDismiss 与面板标题栏 xmark 两路同调 requestCloseMove 单一关闭入口——
    // 规范 §1 硬约束。可见性 `$$` 双向 + onWillDismiss 内 action.dismiss() 放行（官方契约，
    // KimiSheetCommon 注释）；第四参 onDisappear 补开〔关闭-再开协调，见字段注释〕）
    .bindSheet($$this.moveSheetShow, this.MoveSheet(), sheetPanelOptions(
      (action: DismissSheetAction): void => {
        action.dismiss();
        this.requestCloseMove();
      }, [SheetSize.MEDIUM, SheetSize.LARGE] as SheetDetents, undefined,
      (): void => {
        this.onSheetGone();
      }))
  }
}