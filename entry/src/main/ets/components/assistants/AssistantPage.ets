// 助手页签一级页（悬浮页签「助手」居首〔助手0/对话1/设置2〕；参照 RikkaHub AssistantPage
// 裁剪至 aicontrol 已支持能力）。
// ★ 卡片点击语义（决明指令）：**点卡 = 进助手编辑页**；切换当前助手收敛到「更多」菜单的
// 「切换到此助手」项（动作本体 = 写 AppStorage 持久键 ACTIVE_ASSISTANT_KEY + 本页选中态
// 直刷 + SESSION_LIST_RELOAD_KEY 广播历史列表重拉，重读 active 过滤；卡面「当前」选中标记
// 与 ForEach 键含选中态后缀照旧）。
// ★ 更多键（决明「助手卡右侧直接的功能键收为更多键放菜单里」）：原卡内编辑/删除两键收为
// 右缘**单个更多键**（dot_grid_2x2 TEXTUAL）→ 官方 openMenu 弹菜单〔切换到此助手 / 删除；
// 删除项仅用户手建卡渲染——内置默认卡禁删不显示〕，键形制与菜单机制照 ProviderCardItem/
// ModelCardItem 同族定稿。
// ★ 卡面：48 三态头像（共享件 AssistantAvatar 传 avatarSize 48，圆角方形 + 名称首字身份色；
// 编辑页详情卡仍走默认 64、消息轮头 32 各传各的）+ 18fp 名称（LIST_CARD_TITLE_FONTSIZE）+
//「当前」徽章（实底胶囊 StatusBadge，仅当前助手，文案仍「当前」）+ 名称下**固定两排**信息
//（名称排 + 模型排〔未绑定 = 「跟随全局默认」，模型排永不为空——解析回执前先显裸 modelId〕；
// 描述行与模型排 AI_model 前置图标已随精简笔退役，两排间距 = SpaceBetween 自然留缝）+
// 0.5vp 分割线 + 摘要行（计数并列句——工具/技能/知识库/MCP/会话，同质同形某项 0 整项不出；
// 记忆不上卡：开/关二元多数恒开非计数；取舍判据 = 上卡看区分度与可短文本化，全参数总览
// 职责在编辑页 chip 行）。更多键在摘要行右端（14 图标/20 热区——家法尺 18/28 两轮精简
// 拍板缩档），键高撑行 = 元信息加高；**空摘要（计数全 0）时键恒在本行**——切换/删除唯一入口
// 不可随摘要消失，分割线随键入住恒显示。摘要不做警告色——工具少开是按需配置不是错误；
// 会话计数未就绪整项不出（不谎报 0）。
// ★ 三条计数口径：①工具按**用户可见入口**（工具页分类卡）计数而非底层件数（七百三十二节
// 决明口径「对用户展示的入口个数应该对应更改」——判定单源 ToolTypes.toolGroupAllOn，与
// 工具页卡开关、编辑页卡面摘要逐条同源）；②技能/知识库/MCP = skills / knowledge /
// mcpServers 三列各自解析计数；③会话 = **归属该助手名下会话数**（AssistantDb.
// queryAssistantConversationCounts 一条 GROUP BY 拉全，按 historyFilterIds 归并——默认助手
// 名下含 '' 存量未绑定行，与历史列表过滤同口径，卡面数 = 点进对话页签看到的条数；★ 与删除
// 预检 queryAssistantConversationCount 的「仅显式绑定」口径刻意不同——那一处数的是级联会
// 删掉的行）。
// ★ 刷新链：onPop reload（编辑页返回）+ 会话列表变更 SESSION_LIST_RELOAD_KEY @StorageProp
// @Watch（对话页签新建/删除会话后重拉——本页属 TabContent 切页签不触发 pop/onShown，而
// 「会话」项数据源只在 reload 里取）+ cardEpoch 纪元整卡重建；读取链单源 =
// HomeListWarmup.fetchAssistantListSnapshot 三读并行（列表 + 显示名 + 计数）**一次返回**，
// 本页**一次落屏一次纪元**（多次自增纪元 = 卡片反复整卡重建 = 首切「闪一下再出现」），首建
// 另有预热快照同步路径（见 aboutToAppear）；失败落本页报告行不静默、计数缺数不出「会话」项。
// ★ 删除 = 级联删除（拍板 = RikkaHub 删助手同款硬级联）：deleteAssistantCascade 事务三删
// 名下会话与消息——确认文案写明「名下 N 个会话一并删除不可恢复」；删除当前助手则 active
// 键重置默认 + 历史列表重拉广播。内置默认助手卡（固定 id assistant-default，启动
// ensureDefaultAssistant 幂等 seed）禁删（存储层 deleteAssistantCascade 另有禁删守卫兜底）；
// 编辑页进其「提示词」分区 = 只读提示词页（提示词恒同步系统提示词、禁改——AssistantDb
// 读时联结，同步显示落在只读页与选助手面板摘要）。（内置控制台助手卡已随控制台合并笔退役。）
// ★ 卡序 = assistants.sortOrder 单键承载（本页恒按 queryAssistants 读出序渲染），「内置两
// 张恒列头部」硬钉已撤销（决明拍板，与四家竞品一致）——内置卡与其他助手一样可拖到任意位置，
// 唯一内置特权仍是禁删。
// ★ 拖拽排序 = **本页列表原位长按拖拽**（官方 onMove 限 List，本页滚动层 = List + offset
// 轨）：**勿回迁 padding 式顶/底让位**（坑9：List padding = 视口缩进，内容永远滚不进标题栏
// 蒙层 = 渐变模糊空转；contentStartOffset/contentEndOffset 属滚动内容即等价原 Scroll 的
// padding 随内容滚，ProviderPage/记忆库页同为 List + offset 轨）；左右 16 仍走 padding
//（水平收窄，其拖拽浮起裁切由 `.clip(false)` 消解——坑10）。
// ★ 新建 = 标题栏「＋」经 ASSISTANT_CREATE_CMD_KEY 指令键触发本页弹 InputDialog 输入名称 →
// 确认 insert 落行（空提示词）+ reload（RikkaHub「添加弹名称输入」同款；取消不落行）；配置
// 走点卡进编辑页。RikkaHub 的克隆/搜索过滤 v1 不做；DB 就绪守卫 whenReady 在读取链内
//（HomeListWarmup 单源）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ComponentContent, LengthMetrics, SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { AppMenuHost } from '../../common/AppMenuHost';
import {
  ACTIVE_ASSISTANT_KEY, ASSISTANT_DEFAULT_ID, ASSISTANT_NAME_MAX,
  AssistantRow, deleteAssistantCascade, historyFilterIds, insertAssistant,
  queryAssistantConversationCount, saveAssistantOrder
} from '../../common/store/AssistantDb';
import { SESSION_LIST_RELOAD_KEY } from '../../common/AppBroadcastKeys';
import { CONN_RESOLVE_TICK_KEY } from '../../common/store/ProviderDb';
import { parseEnabledToolIds, ToolGroup } from '../../common/providers/ToolTypes';
// 卡显示态判定单源（工具计数口径）
import { toolGroupAllOn, visibleToolGroups } from '../../common/providers/ToolCardView';
import { parseEnabledKnowledgeIds } from '../../common/KnowledgeText';
import { parseEnabledMcpServerIds } from '../../common/McpText';
import { parseEnabledSkillIds } from '../../common/SkillText';
// 模型显示名解析单源在读取链件 HomeListWarmup（本页 desc 行消费 resolved 快照——labels
// Map 随 cardEpoch 纪元重建上屏）；快照新鲜度判定同件（懒加载首建晚于预热采集、跨页会话
// 广播错过无自愈——停旧转现查）
import { AssistantListSnapshot, assistantSnapshotStale, homeListWarmup } from '../../common/store/HomeListWarmup';
import { ROUTE_ASSISTANT_EDIT_PAGE } from '../../common/RouteNames';
import { removeDraftsOfAssistant } from '../chat/ChatDraftStore';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import { InputDialog } from '../chat/InputDialog';
import { AssistantAvatar, AssistantEditParam } from './AssistantCardParts';
// 全站状态词徽标形制单源（「当前」徽章实底胶囊）
import { StatusBadge } from '../StatusBadge';
import {
  CARD_SPACING, LIST_CARD_TITLE_FONTSIZE, cardBg, cardBorderColor, cardDescColor, cardTitleColor,
  menuDividerColor, CARD_RADIUS
} from '../../common/Theme';
import { IMMERSIVE_LEVEL_KEY, overlayMaterial, resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { PREF_CARD_ALPHA_LEVEL_KEY, CARD_ALPHA_DEFAULT } from '../../common/AppPreferences';

// 「当前」chip 文案（chip 文本清单与 chip 强调态判定共用一处字面量——两处各写一份会漂移）
const CHIP_CURRENT: string = '当前';

// 首行统计 = List 静态首项：不在 ForEach 数据源内（不进 onMove 拖拽索引域、长按不起拖），
// 随列表滚动；记忆库页 headSlot 同款形态

// 卡上更多键几何：14 图标 / 20×20 热区（家法尺 18/28 的两轮精简拍板缩档，2026-11-01 精简笔
// 与同日高度追加笔；键随摘要行右置、键高撑行即元信息加高；TEXTUAL 无底色）
const CARD_MORE_ICON_SIZE: number = 14;
const CARD_MORE_KEY_SIZE: number = 20;

// 标题行文字块高：与一级页卡传入的 avatarSize 48 同源（编辑页详情卡走 AssistantAvatar 默认
// 64，不受本常量影响）；文字块压 minHeight 到与头像同高再 SpaceBetween 上下撑齐
const CARD_TEXT_BLOCK_HEIGHT: number = 48;

// 「＋」新建指令键（AppStorage 一次性计数器——坑3 口径）：标题栏「＋」在 HomeNavigation
// （菜单域）无法直达本组件（TabContent 内非 push 页，本键在 TabContent 内实测可用——
// ChatSessionList 多选指令键同机制）；+1 → 弹新建对话框
export const ASSISTANT_CREATE_CMD_KEY: string = 'assistantCreateCmd';

// （ASSISTANT_ORDER_CMD_KEY 已随排序页退役删除——排序改本页原位拖拽后，序变由 applyDragMove
// 就地落 this.rows + 落库，无跨组件重拉需求）

// ═══ 助手卡「更多」菜单 ═══
// 机制 = 卡上四点键（dot_grid_2x2）+ 官方 openMenu 编程式路径（ComponentContent 建/重建/
// dispose 成对 + 锚点 TargetInfo 定位 + 官方菜单材质 REGULAR 基准随沉浸光感总档）——
// ProviderCardMenu / ModelCardMenu / 会话卡菜单同族姿势。本件并回页面文件（单消费方 + 动作
// 执行本就归本页回调，宪法反碎片下限②「并入既有同域文件优先」）。
// 菜单项 = 切换到此助手（switchActive 写当前助手；内置卡同样渲染，进编辑页由点卡承担）/
// 删除（确认弹窗 + 硬级联；仅用户手建卡渲染——内置默认助手禁删，双保险）。排法照全工程
// 行卡菜单定稿「主操作在上、删除垫底」（破坏性项离拇指最远）。
// 宽度官方内容自适应（规范-菜单与二级菜单 §3.1）；分割线 EMBEDDED_IN_MENU 深浅分治
//（AppStorage.get 直读——节点每次弹出前重建取当前深浅色）；锚点 = 卡上四点键（id 前缀 +
// 助手 id，**勿锚整卡**——整卡锚点菜单偏低 ≈30vp）；targetSpace 5vp = 卡片菜单基准。

// 卡片锚点 id 前缀（openMenu TargetInfo 定位目标 = 卡上四点键）
export const ASSISTANT_CARD_MENU_ID_PREFIX: string = 'assistantCardMenu_';

// 菜单回调（openMenu 的 ComponentContent 参数载体：全局 @Builder 无组件实例，数据与动作
// 经参数注入）
interface AssistantCardMenuCallbacks {
  item: AssistantRow;
  onSwitch: (item: AssistantRow) => void;
  onDelete: (item: AssistantRow) => void;
}

// 菜单内容：切换 = arrow_left_arrow_right（切换语义，全工程既有先例）/ 删除 = trash（两符号
// 全工程真机验证过，坑72 口径）
@Builder
function AssistantCardMenuBuilder(params: AssistantCardMenuCallbacks) {
  Menu() {
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_left_arrow_right')),
      content: '切换到此助手' })
      .onClick(() => {
        params.onSwitch(params.item);
      })
    // 删除（仅用户手建助手渲染；存储层另有禁删守卫兜底——双保险）
    if (params.item.id !== ASSISTANT_DEFAULT_ID) {
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')), content: '删除' })
        .onClick(() => {
          params.onDelete(params.item);
        })
    }
  }
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 菜单节点宿主（AppMenuHost 薄壳——节点生命周期与弹出组装在基类，本壳只实现 buildNode 与
// 便捷 open：材质解析 + 逐卡锚点拼接 + targetSpace 5）
class AssistantCardMenuHost extends AppMenuHost<AssistantCardMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: AssistantCardMenuCallbacks): ComponentContent<AssistantCardMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(AssistantCardMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出菜单（基类弹前重建——按当前深浅色/材质重新构建 UI 树）；空 id 占位行不弹（列表未
  // 加载场景的 init 占位守卫）
  open(uiContext: UIContext, callbacks: AssistantCardMenuCallbacks, immersiveLevel: number): void {
    if (callbacks.item.id === '') {
      return;
    }
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, ASSISTANT_CARD_MENU_ID_PREFIX + callbacks.item.id,
      // ★ 第三参 true = 交互形变 + 触点流光（官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true),
      { targetSpace: LengthMetrics.vp(5) });
  }
}

@Component
export struct AssistantPage {
  // 页面存活守卫：置位后本组件迟到异步回调不写状态、不碰 UI、不上行；写库等数据层意图照常完成
  private departed: boolean = false;
  // 顶部留白（vp，HomeNavigation 注入——首卡落标题栏蒙层下方）
  @Prop topPad: number = 0;
  // 底部留白（vp = 避让区高 + 悬浮页签让位，HomeNavigation 注入）
  @Prop bottomPad: number = 0;
  // 官方路由栈（点卡 push 编辑页）
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位只读订阅（助手页签常驻卡面即时面）
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  // 沉浸光感档位（助手卡菜单材质随总档——openCardMenu 消费）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @State private rows: AssistantRow[] = [];
  @State private hintText: string = '';
  // 首拉完成闸（ChatSessionList.loaded 同语义）：false = 首次读取在途——列表整层 opacity 0
  //（藏空白帧）；落屏（applyAssistantSnapshot）置 1 触发 200ms 渐显（见 build 内渐显注释）；
  // 失败路径由 hintText 判据兜底可见——不是刷新闸（reload 不复位，渐显只首建播一次）
  @State private loaded: boolean = false;
  // 首行统计文本（「N 个助手 · M 个会话」13fp 灰字、列表上方；0 助手 = 空 = 不渲染）
  @State private statsText: string = '';
  // 当前助手 id（选中态显示；菜单切换/删除重置直写——自持有 + AppStorage 持久键同源）
  @State private activeId: string = ASSISTANT_DEFAULT_ID;
  // 卡片重建纪元（编辑页 onPop → reload 自增 → ForEach 键变整卡重建；唯一写点在 reload，勿加）
  @State private cardEpoch: number = 0;
  // 归属会话计数（assistantId 原始分桶 → 行数，reload 一条 GROUP BY 拉全；普通成员——Map
  // 非观察类型，刷新靠 cardEpoch 纪元键整卡重建〔坑16 值参快照，普通中间量不驱动 UI〕）
  private sessionCounts: Map<string, number> = new Map();
  // 会话计数读取成功态（false = 读取未完成或失败 → 「会话」项不出——不谎报 0，P0-1）
  @State private sessionCountsOk: boolean = false;
  // 模型显示名（assistantId → 显示名；模型行数据源——普通成员 + cardEpoch 纪元键重建，坑16
  // 同 sessionCounts；绑行走单源 resolveModelDisplayLabel 解析，未绑定不进表）
  private modelLabels: Map<string, string> = new Map();
  // 工具分类卡视图（aboutToAppear 一次性读取——注册表进程级不变；卡面「工具」计数的分子
  // 分母都用它。应用管理卡对全部助手可见，分母统一）
  private groupsNormal: ToolGroup[] = [];
  // 会话列表变更广播（「会话」计数刷新源）：本页属 TabContent 常驻不重建、切页签不触发
  // pop/onShown，而数据源只在 reload 里取——无本订阅则对话页签增删会话后计数停在旧数，与
  // 「卡面数 = 点进对话页签看到的条数」相悖。★ 回调必须**真重查**（走 reload）：
  // sessionCounts 是普通成员，只增 cardEpoch 不会重读 Map。★ 自回声抑制（R1）：本页自身写
  // 该键（切助手 / 删助手）原会经本订阅回声多起一条读取链——现写键前登记将写的值进
  // selfBroadcastTick，回调见值相等一次性抑制；外部写值必然不等照常 reload，键本身真自增
  // 不变（外部消费方 ChatSessionList 照旧收到）
  @StorageProp(SESSION_LIST_RELOAD_KEY) @Watch('onSessionListChanged') sessionListTick: number = 0;
  // 本页自写广播键的登记值（R1 自回声抑制）：-1 = 无自写在途；写键前登记，回调见相等即清
  // 标记跳过 reload（一次性抑制）
  private selfBroadcastTick: number = -1;
  // 读取批次号（R1 批次归属）：reload 入口自增并捕获为局部常量，四处异步回执（whenReady /
  // 列表 then / 计数 then / catch）首句比对，落后即整段弃——并发两次 reload（编辑页 onPop /
  // 会话广播 / 删除三来源可交叠）时旧回执不覆盖新状态。普通成员纯逻辑闸（不驱动 build）
  private reloadBatch: number = 0;
  // 「＋」新建指令（标题栏菜单域经指令键下发触发本页弹对话框——见键常量注释）
  @StorageProp(ASSISTANT_CREATE_CMD_KEY) @Watch('onCreateCmd') createCmd: number = 0;
  // 删除确认弹窗控制器（★ 组件成员位——坑7：普通类成员构造 open() 静默无效）
  private confirmCtrl: CustomDialogController | null = null;
  // 菜单删除目标（确认弹窗回调持引用）
  private pendingDelete: AssistantRow | null = null;
  // 新建对话框控制器（★ 组件成员位——坑7）
  private createCtrl: CustomDialogController | null = null;
  // 助手卡「更多」菜单节点宿主（init/open/dispose 成对，见文件头菜单节）
  private cardMenu: AssistantCardMenuHost = new AssistantCardMenuHost();

  aboutToAppear(): void {
    // 工具分类卡视图一次性读取（见字段注释）
    this.groupsNormal = visibleToolGroups();
    // 预热快照同步消费（首建一次成型）：命中即 build 前同步落屏——页面首帧即完整卡片（首切
    // 页签不闪的根治路径）；miss（预热未完成 / 空快照 / 已消费 / 停旧——本页签懒加载首建
    // 晚于预热采集，窗口内对话页签的会话广播本页错过无自愈，counts 停旧即转现查，见
    // assistantSnapshotStale）转 reload 异步链（在途时与启动链预热共享同一查询，不双发）
    const warm: AssistantListSnapshot | null = homeListWarmup.peekAssistantSnapshot();
    if (warm !== null && !assistantSnapshotStale(warm)) {
      this.activeId = AppStorage.get<string>(ACTIVE_ASSISTANT_KEY) ?? ASSISTANT_DEFAULT_ID;
      this.applyAssistantSnapshot(warm);
    } else {
      this.reload();
    }
    // 菜单节点首次构建（getUIContext 需组件就绪；与 aboutToDisappear dispose 成对）。init
    // 仅建节点需占位行，open 时必传真实行重建——空 id 占位（宿主守卫不弹）
    this.cardMenu.init(this.getUIContext(), this.menuCallbacks(this.emptyRow()));
  }

  aboutToDisappear(): void {
    this.departed = true;
    // 菜单节点释放（与 aboutToAppear init 成对——ComponentContent 不 dispose 泄漏）
    this.cardMenu.dispose();
  }

  // 空占位行（init 建节点用，open 时必传真实行重建；空 id = 守卫不弹）
  private emptyRow(): AssistantRow {
    return {
      id: '', name: '', prompt: '', createdAt: 0, sortOrder: 0, providerId: '', modelId: '',
      thinkLevel: '', advancedParams: '', tools: '', memoryInject: true, memorySink: true,
      skills: '', memoryScope: 'global', knowledge: '', avatar: '', knowledgeAutoInject: false,
      mcpServers: ''
    };
  }

  // 首行统计：statsText 由 build 里的静态 ListItem 直接渲染（见常量注释），不构造哨兵行

  // 指令键回调（+1 即弹新建对话框；首帧初始 0 不触发 @Watch）
  onCreateCmd(): void {
    this.openCreateDialog();
  }

  // 原位拖拽落定：from/to = this.rows 直接下标（统计行是 List 静态首项不在索引域，无偏移
  // 换算）；splice 后整表回写 sortOrder = 数组下标（saveAssistantOrder；读侧 queryAssistants
  // 按 sortOrder 升序 + createdAt 决胜）。落库失败 toast 不静默（P0-1），内存序保留（重进页
  // 回库里的旧序——不谎报成功）
  private applyDragMove(from: number, to: number): void {
    if (from === to || from < 0 || to < 0 ||
      from >= this.rows.length || to >= this.rows.length) {
      return;
    }
    const next: AssistantRow[] = this.rows.slice();
    const moved: AssistantRow = next.splice(from, 1)[0];
    next.splice(to, 0, moved);
    this.rows = next;
    saveAssistantOrder(next.map((row: AssistantRow): string => row.id))
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '排序保存失败：' + (e as Error).message });
      });
  }

  // 新建对话框（「＋」触发）：输入名称 → 确认 insert（空提示词）+ reload（新卡即时出现，
  // 配置走点卡进编辑页——引导入 toast）；取消不落行；InputDialog 自带空值校验
  private openCreateDialog(): void {
    this.createCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: '新建助手',
        initialText: '',
        placeholder: '如 翻译助手、代码顾问',
        confirmLabel: '创建',
        maxLength: ASSISTANT_NAME_MAX,
        onConfirm: (text: string): void => {
          insertAssistant(text, '')
            .then((): void => {
              if (this.departed) {
                return;
              }
              this.getUIContext().getPromptAction().showToast({ message: '已创建，点更多键继续配置' });
              this.reload();
            })
            .catch((e: Object): void => {
              if (this.departed) {
                return;
              }
              this.getUIContext().getPromptAction().showToast({ message: '创建失败：' + (e as Error).message });
            });
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.createCtrl.open();
  }

  // 重拉（挂载 / 编辑页返回 / 新建与删除 / 会话列表变更广播后）。读取链单源 =
  // HomeListWarmup.fetchAssistantListSnapshot——whenReady 就绪守卫 + 三读（列表 / 模型显示名 /
  // 会话计数）并行**一次返回**，本页**一次落屏一次纪元**（纪元在 ForEach 键里，多次自增 =
  // 卡片反复整卡重建 = 首切「闪一下再出现」）。失败落本页报告行不静默（P0-1），三族文案由
  // fetch 侧拼好。★ R1 批次归属：入口自增读取批次，回执首句比对——落后批次整段弃（不写
  // rows / labels / counts / sessionCountsOk / hintText / cardEpoch）
  private reload(): void {
    // 当前助手选中态入口同步读（规范 §2 自持有范式；缺省 = 默认助手）
    this.activeId = AppStorage.get<string>(ACTIVE_ASSISTANT_KEY) ?? ASSISTANT_DEFAULT_ID;
    this.reloadBatch++;
    const batch: number = this.reloadBatch;
    homeListWarmup.awaitAssistantSnapshot()
      .then((snap: AssistantListSnapshot): void => {
        if (this.departed) {
          return;
        }
        if (batch !== this.reloadBatch) {
          return; // 落后批次回执整段弃（R1）
        }
        this.applyAssistantSnapshot(snap);
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        if (batch !== this.reloadBatch) {
          return; // 落后批次回执整段弃（R1）——不写报告行
        }
        this.hintText = (e as Error).message;
        this.updateStatsText(); // 助手数照报；列表失败不挂「M 个会话」
      });
  }

  // 快照一次落屏（预热同步路径与 reload 异步路径共用）：三读产物同帧全部赋值 + **单次**
  // 纪元自增；计数软失败文案随快照落报告行（'' = 成功清空）；statsText 同帧更新；loaded
  // 置位触发首建渐显（同步路径首帧即 1 = 直显不播）
  private applyAssistantSnapshot(snap: AssistantListSnapshot): void {
    this.rows = snap.rows;
    this.modelLabels = snap.labels;
    this.sessionCounts = snap.counts;
    this.sessionCountsOk = snap.countsOk;
    this.hintText = snap.countsError;
    this.cardEpoch += 1;
    this.loaded = true;
    this.updateStatsText();
  }

  // 会话列表变更 → 重拉（复用 reload 单一读取链——助手列表与计数一并取新，**勿在此另写
  // 只查计数的第二套读取**，两处各写一套 = 漂移源；「必须真重查」见订阅字段注释）。
  // R1 自回声抑制：本页自写该键的回声（值 === selfBroadcastTick 登记）清标记并跳过 reload
  //——删除路径的读取链由其显式 reload 承担、切换路径本页数据未变无需重读；外部写值必然
  // 不等照常 reload。禁靠延时/去抖实现（P1-3）
  private onSessionListChanged(): void {
    if (this.sessionListTick === this.selfBroadcastTick) {
      this.selfBroadcastTick = -1; // 一次性抑制：清标记后下一次外部写照常触发
      return;
    }
    this.reload();
  }

  // 编辑页跳转（卡体点击的唯一动作）——onPop 回 reload（子页 pop 必带 result，坑17 契约）。
  // 默认系统转场（与其他页一致；跨页头像一镜到底已退役，官方不可兼得说明见
  // AssistantCardParts「共享元素退役说明」节）。param 携带 avatar/name 首帧种子（编辑页
  // 读库前直赋，防读库空窗 '?' 占位跳变）
  private openEdit(row: AssistantRow): void {
    const param: AssistantEditParam = { id: row.id, avatar: row.avatar, name: row.name };
    this.pathStack.pushPathByName(ROUTE_ASSISTANT_EDIT_PAGE, param, (): void => {
      this.reload();
    });
  }

  // 菜单回调组装（init/open 两处共用——宿主建节点需要完整 callbacks 对象；显式接口构造，
  // 坑72：union 上下文禁匿名对象字面量）
  private menuCallbacks(row: AssistantRow): AssistantCardMenuCallbacks {
    const callbacks: AssistantCardMenuCallbacks = {
      item: row,
      onSwitch: (item: AssistantRow): void => {
        this.switchActive(item);
      },
      onDelete: (item: AssistantRow): void => {
        this.openDeleteConfirm(item);
      }
    };
    return callbacks;
  }

  // 卡上更多键点击弹官方菜单
  private openCardMenu(row: AssistantRow): void {
    this.cardMenu.open(this.getUIContext(), this.menuCallbacks(row), this.immersiveLevel);
  }

  // 删除确认（官方实底弹窗，构造在组件成员位坑7）：先查名下会话数 → 级联语义入文案
  //（拍板 = RikkaHub 删助手同款硬级联无软删除）；预检失败不开弹窗（P0-1 不静默）
  private openDeleteConfirm(row: AssistantRow): void {
    this.pendingDelete = row;
    queryAssistantConversationCount(row.id)
      .then((count: number): void => {
        if (this.departed) {
          return;
        }
        this.confirmCtrl = new CustomDialogController({
          systemMaterial: overlayMaterial(),
          builder: ConfirmDialog({
            title: '删除助手',
            message: count > 0 ? '将删除「' + row.name + '」及其名下 ' + count +
              ' 个会话的全部聊天记录，不可恢复。' : '将删除「' + row.name + '」，不可恢复。',
            confirmLabel: '删除',
            onConfirm: (): void => {
              this.deletePending();
            }
          }),
          autoCancel: true,
          alignment: DialogAlignment.Center
        });
        this.confirmCtrl.open();
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '删除预检失败：' + (e as Error).message });
      });
  }

  // 删除执行（级联编排；存储层 deleteAssistantCascade 另有内置禁删守卫兜底——菜单删除项
  // 对内置卡不渲染，双保险）：事务三删（名下会话消息 + 会话行 + 助手行）→ 内存草稿级联
  //（removeDraftsOfAssistant，WithFiles 档）→ 删的是当前助手则 active 键重置默认 →
  // SESSION_LIST_RELOAD_KEY 广播历史列表重拉 → reload + toast；失败 toast 可重试（P0-1）
  private deletePending(): void {
    const row: AssistantRow | null = this.pendingDelete;
    this.pendingDelete = null;
    if (row === null) {
      return;
    }
    deleteAssistantCascade(row.id)
      .then((delCount: number): void => {
        if (delCount >= 0) {
        // 草稿级联（数据层动作放销毁守卫之前不豁免）：会话行已随事务删除，名下会话草稿与其
        // '__new__' 槽条目失去可达载体，WithFiles 档清条目与附件文件（防进程内不可达残留）
          removeDraftsOfAssistant(row.id);
        }
        if (this.departed) {
          return;
        }
        if (delCount < 0) {
          this.getUIContext().getPromptAction().showToast({ message: '内置助手不可删除' });
          return;
        }
        if (this.activeId === row.id) {
          AppStorage.setOrCreate<string>(ACTIVE_ASSISTANT_KEY, ASSISTANT_DEFAULT_ID);
          this.activeId = ASSISTANT_DEFAULT_ID;
          // 当前助手归默认 = 无行会话②级输入变化（方案 a 同族写点，切回直接发送须重解析）
          AppStorage.setOrCreate<number>(CONN_RESOLVE_TICK_KEY,
            (AppStorage.get<number>(CONN_RESOLVE_TICK_KEY) ?? 0) + 1);
        }
        // 自写广播登记 + 真自增（R1）：值登记进 selfBroadcastTick 抑制本页订阅回声（本页的
        // 读取链由下方显式 reload 承担，不跑两条）；外部消费方照旧收到
        this.selfBroadcastTick = (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1;
        AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY, this.selfBroadcastTick);
        this.getUIContext().getPromptAction().showToast({
          message: delCount > 0 ? '已删除助手及其 ' + delCount + ' 个会话' : '已删除'
        });
        this.reload();
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
      });
  }

  // 切换当前助手（入口 = 「更多」菜单「切换到此助手」项）：写持久键 + 本页选中态直刷 +
  // SESSION_LIST_RELOAD_KEY 广播历史列表重拉（重读 active 过滤）；同值重点幂等跳过
  //（不重复广播/toast）
  private switchActive(row: AssistantRow): void {
    if (this.activeId === row.id) {
      return;
    }
    AppStorage.setOrCreate<string>(ACTIVE_ASSISTANT_KEY, row.id);
    this.activeId = row.id;
    // 自写广播登记 + 真自增（R1）：本页数据未变（选中态上面一行已直刷），抑制回声即无需重读；
    // 外部消费方照旧收到（按 active 过滤重拉）
    this.selfBroadcastTick = (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1;
    AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY, this.selfBroadcastTick);
    // 当前助手切换 = 无行会话②级输入变化（方案 a 同族写点，切回直接发送须重解析）
    AppStorage.setOrCreate<number>(CONN_RESOLVE_TICK_KEY,
      (AppStorage.get<number>(CONN_RESOLVE_TICK_KEY) ?? 0) + 1);
    this.getUIContext().getPromptAction().showToast({ message: '已切换到「' + row.name + '」' });
  }

  // 卡面摘要句（决明拍板「方案甲」）：计数并列——工具 / 技能 / 知识库 / MCP / 会话（同质
  // 同形，**某项为 0 整项不出**）；记忆不上卡：开/关二元多数恒开，非计数。工具 = 已开分类卡/
  // 可见卡总数（口径①）；会话项另受读取态把守。空摘要时整行只剩更多键（见卡内摘要行注释）
  private metaSummary(row: AssistantRow): string {
    const parts: string[] = [];
    const toolsOn: number = this.toolCardsOn(row);
    if (toolsOn > 0) {
      parts.push('工具 ' + toolsOn + '/' + this.groupsNormal.length);
    }
    this.pushCount(parts, '技能', parseEnabledSkillIds(row.skills).length);
    this.pushCount(parts, '知识库', parseEnabledKnowledgeIds(row.knowledge).length);
    this.pushCount(parts, 'MCP', parseEnabledMcpServerIds(row.mcpServers).length);
    if (this.sessionCountsOk) {
      this.pushCount(parts, '会话', this.sessionCountOf(row.id));
    }
    return parts.join(' · ');
  }

  // 计数项统一「0 不出」（拍板口径；会话项另有读取态把守在调用侧）
  private pushCount(parts: string[], label: string, count: number): void {
    if (count > 0) {
      parts.push(label + ' ' + count);
    }
  }

  // 首行统计：N 个助手 [· M 个会话]；0 助手不显示（空态卡自己会说「暂无助手」，不重复）；
  // 计数未就绪/失败只报助手数，不谎报会话 0。会话总数 = 原始分桶求和（每行会话只属一个
  // assistantId）
  private updateStatsText(): void {
    if (this.departed) {
      return;
    }
    if (this.rows.length === 0) {
      this.statsText = '';
      return;
    }
    let total: number = 0;
    this.sessionCounts.forEach((count: number): void => {
      total += count;
    });
    let text: string = this.rows.length + ' 个助手';
    if (this.sessionCountsOk) {
      text += ' · ' + total + ' 个会话';
    }
    if (this.statsText !== text) {
      this.statsText = text;
    }
  }

  // 模型排（副信息第二排）：**全员统一两排**（名称排 + 模型排——描述行已随精简笔退役，
  // 决明「上面只保留两排信息」）。字号 13fp = 全站说明小字统一档。模型排永不为空（绑定未
  // 解析回执时先显示裸 modelId，回执后换显示名——不占位不留空行）；未绑定 = 「跟随全局
  // 默认」（发送链四级兜底②级语义）
  private modelLine(row: AssistantRow): string {
    if (row.providerId === '' || row.modelId === '') {
      return '跟随全局默认';
    }
    const label: string | undefined = this.modelLabels.get(row.id);
    return label !== undefined && label !== '' ? label : row.modelId;
  }

  // （模型显示名批量解析单源在 HomeListWarmup——本页经 AssistantListSnapshot.labels 消费）

  // 已开分类卡数（判定单源 = ToolTypes.toolGroupAllOn——与工具页卡开关、编辑页卡面摘要逐条
  // 同口径：联网压制件不进分母，全开才算该卡已开；应用管理卡对全部助手计入分母）
  private toolCardsOn(row: AssistantRow): number {
    const ids: string[] = parseEnabledToolIds(row.tools);
    let on: number = 0;
    for (const group of this.groupsNormal) {
      if (toolGroupAllOn(group, ids)) {
        on++;
      }
    }
    return on;
  }

  // 归属会话数（historyFilterIds 单源归并——默认助手 = 显式绑定 + '' 存量未绑定行，其余 =
  // 自身 id 单值；与历史列表过滤同口径，卡面数 = 点进对话页签所见条数。★ 与删除确认的
  // queryAssistantConversationCount「仅显式绑定」口径刻意不同——那一处数的是级联会删掉的行）
  private sessionCountOf(assistantId: string): number {
    let total: number = 0;
    for (const key of historyFilterIds(assistantId)) {
      total += this.sessionCounts.get(key) ?? 0;
    }
    return total;
  }

  // 助手卡（重建即最新；ForEach 键含纪元 + 选中态后缀）。卡面三层：①标题行（头像 + 名称 +
  // 「当前」徽章/两行副信息）；②0.5vp 分割线；③摘要行 + 右端更多键。口径：徽章紧贴名称右侧
  //（实底胶囊 StatusBadge + 官方强调蓝，不做绿色「使用中」）；★ 点卡 = 进编辑页（切换/删除
  // 在更多键菜单——卡体 + 键嵌套点击不冒泡，坑72 口径）。
  @Builder
  AssistantCard(row: AssistantRow) {
    // Button(Normal) 包壳（官方原生按压蒙层形制；行内更多键子组件先命中，嵌套点击关系不变）。
    // ★ 拖拽例外：本页列表**可拖拽** ⇒ 外壳 Button 关原生按压（`stateEffect(false)`，见链尾）
    //——长按浮起后按压蒙层会跟进拖拽预览 = 起手灰、拖动一点才变白（真机报障；根因与同款
    // 处置完整口径见 `ProviderCardItem.build` 头注释）；行内更多键的按压反馈不受影响
    Button() {
      Column() {
        // 标题行（头像 + 名称/徽章/两行副信息；上下居中——更多键在摘要行右端）
        Row({ space: 12 }) {
          // 头像（共享三态件 AssistantAvatar——首字/文字/图片随 assistants.avatar 列渲染；
          // ★ 不传 onEditClick = 无角标无热区，点击穿透卡体，点卡仍是「进编辑页」；
          // avatarSize 48 = 精简拍板缩档，编辑页详情卡仍走默认 64）
          AssistantAvatar({ spec: row.avatar, fallbackText: row.name, avatarSize: 48 })
          Column() {
            // 名称行（★ 单行 Row 勿改 Flex wrap：wrap 在「长名 + 当前徽章」同排超宽时把徽章
            // 挤到第二行 ⇒ 行高 24→约 46 ⇒ 头像被压低、三向等距 16 破坏〔真机报障的机制
            // 根因〕。单行下徽章恒占定宽、名称 layoutWeight 让位并省略〔徽章不被挤走，判据
            // 同目标〕，名称行恒 24 ⇒ 行高恒 = 头像高，三向 16 由数值保证而非巧合）
            Row({ space: 6 }) {
              Text(row.name)
                .fontSize(LIST_CARD_TITLE_FONTSIZE)
                .lineHeight(24)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              if (row.id === this.activeId) {
                StatusBadge({ text: CHIP_CURRENT })
              }
            }
            .width('100%')
            // 模型排（副信息第二排，见 modelLine 注释；AI_model 前置图标已随精简笔退役——
            // 纯文字形态与原描述行同形，单行省略渲染）
            Text(this.modelLine(row))
              .fontSize(13)
              .lineHeight(17)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          // 文字块与头像上下齐平（决明「助手名跟头像上边齐平」沿用；描述句已随精简笔退役，
          // 改两排信息——名称排顶到头像上沿、模型排底到头像下沿，两排间距 = SpaceBetween
          // 自然留缝）：块高 minHeight 压到头像同高（CARD_TEXT_BLOCK_HEIGHT，内容超高自然
          // 生长不截断）+ SpaceBetween 两段撑开 + 显式行高收紧字面内默认留白（18fp ≈25→24、
          // 13fp ≈18→17——真机嫌不齐只调两处 lineHeight）。全部标准布局属性零自绘，勿回退
          //「居中」形态（那是旧主诉）
          .constraintSize({ minHeight: CARD_TEXT_BLOCK_HEIGHT })
          .justifyContent(FlexAlign.SpaceBetween)
        }
        .width('100%')
        // 行高显式锁头像高（48）——头像底边即行底 ⇒ 分割线到头像底边的间距 = 头像顶边到
        // 卡顶的间距（两处 12）由数值保证，不依赖「内容恰好不超高」的巧合（换行型超高会经
        // Center 居中把头像顶起）
        .height(CARD_TEXT_BLOCK_HEIGHT)
        .alignItems(VerticalAlign.Center)
        // 摘要行 + 更多键（决明「更多键缩小放到下排右侧」）：13fp 摘要句 maxLines(1)（恒定
        // 卡高，5 项全开极端形态走省略号，全量明细在编辑页 chip 行），有值时 layoutWeight(1)
        // 占满、键自然靠右；空摘要（计数全 0，新建未配置卡）时文本不出、**键仍恒在本行右端**
        //——切换/删除唯一入口不可随摘要消失，原「空摘要整行连分割线不出」判据随键入住消解
        //（分割线下方恒有键行，不再是孤儿细线）。分割线上边距 12 = 上下等距判据（决明
        // 2026-11-01「分割线到头像底边的间距 = 头像顶边到卡片顶边的间距」，两处同值 12；
        // 原三向等距 16 判据同日废止，左右 padding 仍 16 不动）；行 margin top 6 与卡底
        // padding bottom 6 对称 = 下排在「分割线—卡底边」盒级居中（真机嫌偏调这对同值）。
        Divider()
          .strokeWidth(0.5)
          .color(cardBorderColor(this.appColorMode))
          .width('100%')
          .margin({ top: 12 })
        Row({ space: 8 }) {
          if (this.metaSummary(row) !== '') {
            Text(this.metaSummary(row))
              .fontSize(13)
              .lineHeight(17)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          // 更多键（TEXTUAL 无底色；菜单锚点 id 挂键自身——键位变更不影响 openMenu 定位机制）
          Button() {
            SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
              .fontSize(CARD_MORE_ICON_SIZE)
              .fontColor([$r('sys.color.font_secondary')])
          }
          .width(CARD_MORE_KEY_SIZE)
          .height(CARD_MORE_KEY_SIZE)
          .padding(0)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .id(ASSISTANT_CARD_MENU_ID_PREFIX + row.id)
          .onClick((): void => {
            this.openCardMenu(row);
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(VerticalAlign.Center)
        .margin({ top: 6 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .type(ButtonType.Normal)
    .width('100%')
    // top 12 = 分割线上边距同值（上下等距判据，决明 2026-11-01 高度追加笔）；bottom 6 =
    // 摘要行 margin top 同值（盒级居中判据）；左右保持 16 不动（横向未点名）
    .padding({ top: 12, right: 16, bottom: 6, left: 16 })
    .backgroundColor(cardBg(this.appColorMode, this.cardAlphaLevel))
    .borderRadius(CARD_RADIUS)
    // 关原生按压蒙层（拖拽例外，见 AssistantCard 头注释；点卡的反馈由「当前」徽章更新与
    // 转场承担）
    .stateEffect(false)
    .onClick((): void => {
      // 点卡 = 进编辑页（切换当前助手在「更多」菜单里）
      this.openEdit(row);
    })
  }

  // 列表顶部内距（比 topPad 收紧 4vp；回退路径 topPad=0 时钳 0，避免负值）
  private contentTopInset(): number {
    return this.topPad > 4 ? this.topPad - 4 : 0;
  }

  build() {
    // 列表（统计行 = List 静态首项，不进拖拽索引域，见常量注释）。间距：标题栏→首行 =
    // topPad−4、首行→首卡 = List space 10。顶/底让位仍走 offset 轨，勿改 padding（坑9，见文件头）
    List({ space: CARD_SPACING }) {
        if (this.statsText !== '') {
          // 首行统计（静态项：不参与拖拽；随列表滚动）
          ListItem() {
            Text(this.statsText)
              .fontSize(13)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        ForEach(this.rows, (row: AssistantRow) => {
          ListItem() {
            this.AssistantCard(row)
          }
          // ★ 条目层同挂 borderRadius(CARD_RADIUS)——**拖拽快照的矩形底靠它消**（长按后卡片
          // 圆角处露直角蒙层的真机实拍报障；条目宽 = 卡宽故两处同值逐边重合）。★ 勿删：删掉
          // 即复发（服务商管理页同款同因）
          .borderRadius(CARD_RADIUS)
          // 键含选中态后缀 + 纪元（选中变 / 编辑页返回 / 会话计数与模型显示名回填〔含对话
          // 页签增删会话经订阅重拉的回填〕均经纪元键变整卡重建；摘要句随建随算最新值）
        }, (row: AssistantRow): string =>
          row.id + (row.id === this.activeId ? '|cur' : '') + '|' + this.cardEpoch)
          // 原位拖拽排序（官方 onMove）：长按卡片即拖，离手上报 from/to = this.rows 直接
          // 下标 → applyDragMove 重排 + 回写 sortOrder。长按与卡内交互互不抢（点卡/更多键
          // 为单击，拖拽为长按，真机对照已验）
          .onMove((from: number, to: number): void => {
            this.applyDragMove(from, to);
          })

        if (this.rows.length === 0 && this.hintText === '') {
          ListItem() {
            Column({ space: 8 }) {
              Text('暂无助手')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
              Text('点右上角「＋」新建。点卡片进入编辑页，卡片右侧更多键可切换或删除')
                .fontSize(13)
                .fontColor(cardDescColor())
            }
            .width('100%')
            .padding(24)
            .backgroundColor(cardBg(this.appColorMode, this.cardAlphaLevel))
            .borderRadius(CARD_RADIUS)
            .alignItems(HorizontalAlign.Start)
          }
        }
        if (this.hintText !== '') {
          ListItem() {
            Text(this.hintText)
              .fontSize(12)
              .fontColor($r('sys.color.ohos_id_color_warning'))
              .width('100%')
          }
        }
      }
      .width('100%')
      .height('100%')
      // 进场渐显（决明拍板，时长 200ms）：首建读取在途（loaded=false 且无失败提示）列表整层
      // opacity 0 藏空白，落屏置位后 200ms EaseOut 渐显——「空白→卡片整批跳变」翻成有意进场。
      // ★ 预热快照同步命中路径（aboutToAppear 内 apply 已置 loaded）首帧即 1 = 直显不播；
      // reload 刷新 loaded 恒 1 不重播（只有首建播）。★ animation 辖域只辖 opacity，声明位
      // 紧随其后
      .opacity(this.loaded || this.hintText !== '' ? 1 : 0)
      .animation({ duration: 200, curve: Curve.EaseOut })
      // 顶/底让位 = offset 轨（topPad−4 = 首行/首卡静止位、bottomPad = 悬浮页签让位；首行
      // 随列表滚动）。左右 16 = 卡片水平收窄（页签页口径）
      .contentStartOffset(this.contentTopInset())
      .contentEndOffset(this.bottomPad + 16)
      .padding({ left: 16, right: 16 })
      // 关裁剪（坑10）：水平 padding = 视口缩进，不关则长按拖拽浮起放大的卡片被削成直边
      //（官方对 onMove 预览无旋钮——真机结论：挂 `.clip(false)` 四向不裁）
      .clip(false)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
  }
}
