// 助手页签一级页（2026-09-01 助手域新建——悬浮页签「助手」，同日领导指令换序居首
//〔助手0/对话1/设置2〕；参照 RikkaHub AssistantPage 裁剪至 aicontrol 已支持能力）。
// ★ 卡片点击语义（2026-09-01 会话历史绑定助手改造，领导指令：**点卡片 = 切换当前助手**
// ——写 AppStorage 持久键 ACTIVE_ASSISTANT_KEY + 本页选中态直刷 + SESSION_LIST_RELOAD_KEY
// 广播历史列表重拉（重读 active 过滤，对话页签即见该助手名下会话）；卡面显示「当前」
// 选中标记〔ForEach 键含选中态后缀，键变重建〕。**编辑键加回卡内**〔square_and_pencil
// TEXTUAL，反馈轮 2 形制——点卡语义让位切换后编辑回收到本键〕→ push 编辑页；右缘删除键
// 保留〔确认弹窗——内置默认助手卡不渲染禁删〕）。
// ★ 卡面改版——卡面计数 chip（2026-09-20 决明「助手页助手卡优化，样式类似服务商编辑页
// 服务商卡，下加 chip，显示该助手启用的工具与技能数，还希望显示归属该助手的会话数，
// 注意排版」）：形制对齐服务商详情卡 ProviderHeadCard——64 圆底首字头像（28fp 首字，原
// 22fp/44 尺退役；与编辑页详情卡 DetailCard 同尺）+ 18fp 名称（LIST_CARD_TITLE_FONTSIZE）
// + chip 行（Flex wrap，窄屏/长数字换行不裁切；小徽章几何 = 服务商卡 Badge 同款
// 10fp/胶囊 6-2/圆角 6/badgeBg）。chip 四项 = 「当前」（仅当前助手，勾号 + 强调色）/
// 「工具 已开卡/卡总数」/「技能 N」/「会话 N」。★ 三条口径：
// ①工具按**用户可见入口单位**（工具页分类卡）计数而非底层件数（七百三十二节决明口径
//   「对用户展示的入口个数应该对应更改」——判定单源 ToolTypes.toolGroupAllOn，与工具页卡
//   开关、编辑页「工具调用」卡面摘要逐条同源，含 console-exclusive 与联网压制两因）；
// ②技能 = assistants.skills 解析计数（与编辑页技能摘要同口径）；③会话 = **归属该助手名下
//   会话数**（AssistantDb.queryAssistantConversationCounts 一条 GROUP BY 拉全，按 historyFilterIds
//   归并——默认助手名下含 '' 存量未绑定行，与历史列表过滤同口径，卡面数 = 点进对话页签
//   看到的条数；与删除预检 queryAssistantConversationCount 的「仅显式绑定」口径刻意不同）。
// 刷新链 = onPop reload（编辑页返回）+ 联网总开关 @StorageProp @Watch（工具 chip 含压制口径）
// + 会话列表变更 SESSION_LIST_RELOAD_KEY @StorageProp @Watch（对话页签新建/删除会话后重拉
// ——「会话」chip 数据源只在 reload 里取，而本页属 TabContent 切页签不触发 pop/onShown）
// + cardEpoch 纪元键整卡重建；两读取一次拉全（列表 + 计数），失败落本页报告行不静默、计数
// 缺数时不出「会话」chip（不谎报 0）。**点卡切换与卡内两键的交互语义一字未动**。
// 删除 = 级联删除（拍板 = RikkaHub 删助手同款硬级联）：deleteAssistantCascade 事务三删
// 名下会话与消息——确认文案写明「名下 N 个会话一并删除不可恢复」；删除当前助手则 active
// 键重置默认 + 历史列表重拉广播。
// 内置默认助手卡（固定 id assistant-default，启动 ensureDefaultAssistant 幂等 seed）禁删；
// 编辑页进其「提示词」分区 = 只读提示词页（反馈轮 3：提示词恒同步
// 系统提示词、禁改——AssistantDb 读时联结，同步显示落在只读页与选助手面板摘要）；存储层
// deleteAssistantCascade 另有禁删守卫兜底。★ 内置控制台助手卡（2026-09-05 控制台助手：
// 固定 id assistant-console）同禁删；其「提示词」分区同为只读页（内容 =
// AssistantDb 读时联结的内置路由提示词，与默认助手「只读展示禁修改」同口径，文案分支
// 在 AssistantPromptPage）。★ 2026-09-22 助手自定义列表序笔：卡序改由 assistants.sortOrder
// 单键承载（本页恒按 queryAssistants 读出序渲染），**旧「内置两张恒列头部」硬钉撤销**——
// 两张内置卡与其他助手一样可被拖到任意位置，唯一内置特权仍是禁删（决明拍板，与四家竞品
// 一致）；存量设备升级后的可见序由 v39→v40 迁移回填复刻，逐字不变。
// RikkaHub 的克隆/搜索过滤 v1 不做（裁剪清单见 docs/调研与待办-助手与提示词变量.md）；
// 拖拽排序 2026-09-22 落地（标题栏「⋯」更多菜单「排序」→ AssistantSortPage 二级页，
// 不在本页内拖——ForEach.onMove 官方限 List 而本页是 Scroll+Column，见该页头注释）。
// ★ 滚动层 = Scroll + Column + padding（对话/设置一级页同款光感口径——首版误用 List +
// padding，List padding = 视口缩进、内容永远滚不进标题栏蒙层 = 渐变模糊空转〔坑9 形态，
// 领导真机反馈「助手页标题栏无渐变模糊」根因〕；Scroll 的 padding 属滚动内容随滚，卡片
// 上滚滑入标题栏蒙层背后被 GRADIENT_BLUR 模糊透出——ChatSessionList/SettingsPage 同款）。
// ★ 新建 = 对话框（2026-09-01 按钮区退役轮领导指令）：标题栏「＋」经 ASSISTANT_CREATE_CMD_KEY
// 指令键触发本页弹 InputDialog 输入名称 → 确认 insert 落行（空提示词）+ reload（RikkaHub
// 「添加弹名称输入」同款；取消不落行）；配置走点卡进编辑页。
// 刷新链（规范-数据存储获取刷新方案）：编辑页返回经 onBackPressed pop 带 result → onPop
// 回 reload → cardEpoch 纪元进 ForEach 键整卡重建（重命名后名称刷新）；「＋」在
// HomeNavigation（菜单域）无法直达 TabContent 内组件 → 指令键下发（ChatSessionList 多选
// 同机制，坑3 口径）；DB 就绪守卫 whenReady（启动竞态，ChatSessionList/ProviderPage 同族）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { LengthMetrics } from '@kit.ArkUI';
import { whenReady } from '../../common/store/ChatDb';
import {
  ACTIVE_ASSISTANT_KEY, ASSISTANT_CONSOLE_ID, ASSISTANT_DEFAULT_ID, ASSISTANT_NAME_MAX,
  AssistantRow, deleteAssistantCascade, historyFilterIds, insertAssistant,
  queryAssistantConversationCount, queryAssistantConversationCounts, queryAssistants
} from '../../common/store/AssistantDb';
import { SESSION_LIST_RELOAD_KEY } from '../chat/ChatSessionList';
import { CONN_RESOLVE_TICK_KEY } from '../../common/store/ProviderDb';
import { PREF_SEARCH_SERVICE_ENABLED_KEY } from '../../common/AppPreferences';
import { parseEnabledToolIds, ToolGroup, toolGroupAllOn, visibleToolGroups }
  from '../../common/providers/ToolTypes';
import { parseEnabledSkillIds } from '../../common/SkillText';
import { ROUTE_ASSISTANT_EDIT_PAGE } from '../../common/RouteNames';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import { InputDialog } from '../chat/InputDialog';
import {
  badgeBg, CARD_SPACING, LIST_CARD_TITLE_FONTSIZE, cardBg, cardDescColor, cardTitleColor
} from '../../common/Theme';
import { overlayMaterial } from '../../common/ImmersiveLevel';

// 「当前」chip 文案（chip 文本清单与 chip 强调态判定共用一处字面量——两处各写一份会漂移）
const CHIP_CURRENT: string = '当前';

// 「＋」新建指令键（AppStorage 一次性计数器——坑3 口径）：标题栏「＋」在 HomeNavigation
// （菜单域）无法直达本组件（TabContent 内非 push 页，本键在 TabContent 内实测可用——
// ChatSessionList 多选指令键同机制）；+1 → 弹新建对话框
export const ASSISTANT_CREATE_CMD_KEY: string = 'assistantCreateCmd';

// 排序返回重拉指令键（AppStorage 一次性计数器，2026-09-22 助手自定义列表序笔——与
// ASSISTANT_CREATE_CMD_KEY 同一机制与同一缘由：排序页从菜单域 push，返回时「谁去重拉本页
// 卡序」只能走指令键下发；写点 = HomeNavigation 排序页 push 的 onPop 回调，消费 = 本页
// @Watch → reload）；+1 → 重拉
export const ASSISTANT_ORDER_CMD_KEY: string = 'assistantOrderCmd';

@Component
export struct AssistantPage {
  // 顶部留白（vp，HomeNavigation 注入——首卡落标题栏蒙层下方）
  @Prop topPad: number = 0;
  // 底部留白（vp = 避让区高 + 悬浮页签让位，HomeNavigation 注入）
  @Prop bottomPad: number = 0;
  // 官方路由栈（点卡 push 编辑页）
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State private rows: AssistantRow[] = [];
  @State private hintText: string = '';
  // 当前助手 id（选中态显示；点卡切换/删除重置直写——自持有 + AppStorage 持久键同源）
  @State private activeId: string = ASSISTANT_DEFAULT_ID;
  // 卡片重建纪元（编辑页 onPop → reload 自增 → ForEach 键变整卡重建；联网总开关翻转经
  // @Watch 同增——chip 文本含压制口径，重算须走键变重建，见 onWebServiceChanged）
  @State private cardEpoch: number = 0;
  // 归属会话计数（assistantId 原始分桶 → 行数——reload 一条 GROUP BY 拉全，卡面「会话」chip
  // 数据源；普通成员 + cardEpoch 驱动重建：Map 非观察类型，刷新靠纪元键整卡重建，同 toolsRaw
  // 家族姿势〔坑16 值参快照〕）
  private sessionCounts: Map<string, number> = new Map();
  // 会话计数读取成功态（false = 读取未完成或失败 → 「会话」chip 不出——不谎报 0，P0-1；
  // @State 驱动 build 重跑）
  @State private sessionCountsOk: boolean = false;
  // 工具分类卡视图（aboutToAppear 一次性读取——注册表进程级不变，AssistantToolsPage 同款；
  // 卡面「工具」chip 的已开卡计数与分母都用它）
  private groups: ToolGroup[] = [];
  // 联网搜索总开关（★ 卡面「工具」chip 的已开卡判定含联网压制口径——总开关关闭时联网从属件
  // 不进可开件分母，如清单只开 search_web 时该卡由未开变已开；助手页属 TabContent，切页签
  // 回来不发生 pop（onPop 只管编辑页返回），故本订阅是本页在场刷新源之一，勿按「onPop 兜底」
  // 删——编辑页同名订阅同源）
  @StorageProp(PREF_SEARCH_SERVICE_ENABLED_KEY) @Watch('onWebServiceChanged') searchServiceEnabled: boolean =
    true;
  // 会话列表变更广播（2026-09-20 卡面「会话」chip 刷新源：键写点 = 对话页离页时 ChatPage 自增
  // 〔新建/改行〕**与对话页签列表内两处删除成功支**〔ChatSessionList.deleteOne / deleteSelected
  // ——★ 复验轮补：删行不经对话页、原稿此侧零写点，删完切回本页签 chip 停在旧数〕）：本页属
  // TabContent 常驻不重建、切页签不触发 pop/onShown
  // （同上条同一结论），而「会话」chip 的数据源只在 reload 里取——无本订阅则对话页签新建或
  // 删除会话后 chip 停在旧数，与「卡面数 = 点进对话页签看到的条数」相悖。★ 回调必须**真重查**
  // （走 reload）：sessionCounts 是普通成员，只增 cardEpoch 不会重读 Map（纪元只驱动整卡重建）。
  // 本页自身写该键（切助手 / 删助手）会多触发一次重拉——幂等无害、无回环（reload 不写该键）
  @StorageProp(SESSION_LIST_RELOAD_KEY) @Watch('onSessionListChanged') sessionListTick: number = 0;
  // 「＋」新建指令（标题栏菜单域经指令键下发触发本页弹对话框——见键常量注释）
  @StorageProp(ASSISTANT_CREATE_CMD_KEY) @Watch('onCreateCmd') createCmd: number = 0;
  // 排序返回重拉指令（排序页从菜单域 push，返回时经本键下发重拉——见键常量注释；
  // 与「＋」同机制同槽位，勿合并成一个键：语义不同，合并会让新建也触发一次重拉）
  @StorageProp(ASSISTANT_ORDER_CMD_KEY) @Watch('onOrderChanged') orderCmd: number = 0;
  // 删除确认弹窗控制器（★ 组件成员位——坑7：普通类成员构造 open() 静默无效）
  private confirmCtrl: CustomDialogController | null = null;
  // 菜单删除目标（确认弹窗回调持引用）
  private pendingDelete: AssistantRow | null = null;
  // 新建对话框控制器（★ 组件成员位——坑7）
  private createCtrl: CustomDialogController | null = null;

  aboutToAppear(): void {
    // 工具分类卡视图一次性读取（注册表进程级不变，AssistantToolsPage 同款；卡面「工具」chip
    // 的已开卡计数与分母消费）
    this.groups = visibleToolGroups();
    this.reload();
  }

  // 指令键回调（+1 即弹新建对话框；首帧初始 0 不触发 @Watch）
  onCreateCmd(): void {
    this.openCreateDialog();
  }

  // 排序页返回 → 重拉（新卡序落屏；本页列表序 = queryAssistants 的 sortOrder 序，
  // 重拉即取新序——卡序 chip 内容不变但顺序变，故必须真重查而非只增纪元）
  onOrderChanged(): void {
    this.reload();
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
              this.getUIContext().getPromptAction().showToast({ message: '已创建，点编辑键继续配置' });
              this.reload();
            })
            .catch((e: Object): void => {
              this.getUIContext().getPromptAction().showToast({ message: '创建失败：' + (e as Error).message });
            });
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.createCtrl.open();
  }

  // 重拉（挂载 / 编辑页返回 / 新建与删除 / 会话列表变更广播后）：两读一次拉全——助手列表
  // （主数据，先落屏）+ 归属会话计数（卡面 chip 数据，一条 GROUP BY）。失败落本页报告行不
  // 静默（P0-1），stage 记失败步名使提示不误指；计数失败另置 sessionCountsOk=false 关掉
  // 「会话」chip（缺数不谎报 0——0 是真值，不可与失败混同）
  private reload(): void {
    // 当前助手选中态入口同步读（规范 §2 自持有范式；缺省 = 默认助手）
    this.activeId = AppStorage.get<string>(ACTIVE_ASSISTANT_KEY) ?? ASSISTANT_DEFAULT_ID;
    // DB 就绪守卫（启动竞态——init 与页面加载并行时直查抛错钉死提示）
    whenReady().then((ok: boolean): void => {
      if (!ok) {
        this.hintText = '数据库初始化失败，请重启应用重试';
        return;
      }
      let stage: string = '助手列表';
      queryAssistants()
        .then((rows: AssistantRow[]): Promise<Map<string, number>> => {
          this.rows = rows;
          this.cardEpoch += 1; // 先落屏（计数未回时「会话」chip 暂缺）
          stage = '会话数';
          return queryAssistantConversationCounts();
        })
        .then((counts: Map<string, number>): void => {
          this.sessionCounts = counts;
          this.sessionCountsOk = true;
          this.hintText = '';
          this.cardEpoch += 1;
        })
        .catch((e: Object): void => {
          if (stage === '会话数') {
            this.sessionCountsOk = false;
          }
          this.hintText = stage + '读取失败：' + (e as Error).message;
        });
    });
  }

  // 联网总开关变更 → 卡面「工具」chip 的已开卡重算（chip 文本含压制口径，须键变重建——
  // 只增纪元，卡面 build 随键重建自然取新值；编辑页同名订阅同源）
  private onWebServiceChanged(): void {
    this.cardEpoch += 1;
  }

  // 会话列表变更 → 重拉（对话页签新建/删除会话后本页重取，卡面「会话」chip 随新计数重建；
  // 复用 reload 单一读取链 = 助手列表与计数一并取新的「两读一次拉全」口径不变，勿在此另写
  // 只查计数的第二套读取——两处各写一套 = 漂移源。见上条订阅注释的「必须真重查」）
  private onSessionListChanged(): void {
    this.reload();
  }

  // 编辑页跳转（2026-09-01 会话绑定轮：点卡 = 切换当前助手，进编辑页回收到卡内「编辑」键
  // ——卡体 onClick 与卡内键并存，ProviderCardItem 卡体+四点键同款嵌套点击先例）——onPop
  // 回 reload（子页保存/删除 pop 必带 result，坑17 契约）
  private openEdit(assistantId: string): void {
    this.pathStack.pushPathByName(ROUTE_ASSISTANT_EDIT_PAGE, assistantId, (): void => {
      this.reload();
    });
  }

  // 删除确认（官方实底弹窗——删除会话/服务商同款；构造在组件成员位坑7）：先查名下会话数
  // → 级联语义入文案（2026-09-01 拍板 = RikkaHub 删助手同款硬级联无软删除）；预检失败
  // 不开弹窗（P0-1 不静默）
  private openDeleteConfirm(row: AssistantRow): void {
    this.pendingDelete = row;
    queryAssistantConversationCount(row.id)
      .then((count: number): void => {
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
        this.getUIContext().getPromptAction().showToast({ message: '删除预检失败：' + (e as Error).message });
      });
  }

  // 删除执行（级联编排，2026-09-01 会话绑定拍板 = RikkaHub 同款硬级联；存储层
  // deleteAssistantCascade 另有内置默认禁删守卫兜底——本页删除键对默认卡不渲染，双保险）：
  // 事务三删（名下会话消息 + 会话行 + 助手行）→ 删的是当前助手则 active 键重置默认
  // → SESSION_LIST_RELOAD_KEY 广播历史列表重拉 → reload
  // + toast；失败 toast 可重试（P0-1）
  private deletePending(): void {
    const row: AssistantRow | null = this.pendingDelete;
    this.pendingDelete = null;
    if (row === null) {
      return;
    }
    deleteAssistantCascade(row.id)
      .then((delCount: number): void => {
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
        AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
          (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
        this.getUIContext().getPromptAction().showToast({
          message: delCount > 0 ? '已删除助手及其 ' + delCount + ' 个会话' : '已删除'
        });
        this.reload();
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
      });
  }

  // 点卡切换当前助手（2026-09-01 会话绑定，拍板：点卡 = 切换 / 编辑键进编辑页 / 留页签
  // 显选中态）：写持久键 + 本页选中态直刷 + SESSION_LIST_RELOAD_KEY 广播历史列表重拉
  //（重读 active 过滤）；同值重点幂等跳过（不重复广播/toast）
  private switchActive(row: AssistantRow): void {
    if (this.activeId === row.id) {
      return;
    }
    AppStorage.setOrCreate<string>(ACTIVE_ASSISTANT_KEY, row.id);
    this.activeId = row.id;
    AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
      (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
    // 当前助手切换 = 无行会话②级输入变化（方案 a 同族写点，切回直接发送须重解析）
    AppStorage.setOrCreate<number>(CONN_RESOLVE_TICK_KEY,
      (AppStorage.get<number>(CONN_RESOLVE_TICK_KEY) ?? 0) + 1);
    this.getUIContext().getPromptAction().showToast({ message: '已切换到「' + row.name + '」' });
  }

  // 卡面小徽章（文字胶囊；几何 = 服务商卡 Badge 同款——badgeBg 半透明灰底 / 10fp / 内边距
  // 6-2 / 圆角 6；check = 「当前」形态：勾号 + 强调色文字，其余为灰字计数徽章）。仅经 ForEach
  // 调用——坑16：@Builder 值参直调 = 按值快照不重渲，键变（文本本身）才重建
  @Builder
  Chip(text: string, check: boolean) {
    Row({ space: 2 }) {
      if (check) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(10)
          .fontColor([$r('sys.color.ohos_id_color_emphasize')])
      }
      Text(text)
        .fontSize(10)
        .fontColor(check ? $r('sys.color.ohos_id_color_emphasize') : cardDescColor())
    }
    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
    .borderRadius(6)
    .backgroundColor(badgeBg(this.appColorMode))
  }

  // 卡面 chip 文本清单（ForEach 数据源；顺序 = 当前标记〔仅当前助手，行首〕/ 工具 / 技能 /
  // 会话）。★ 工具 = 已开分类卡/可见卡总数（七百三十二节「对用户展示的入口个数」口径——
  // 不报底层件数）；技能 = skills 列解析计数；会话 = 归属该助手名下会话数（计数读取未就绪
  // 或失败时整条不出——缺数不谎报 0）
  private chipTexts(row: AssistantRow): string[] {
    const list: string[] = [];
    if (row.id === this.activeId) {
      list.push(CHIP_CURRENT);
    }
    list.push('工具 ' + this.toolCardsOn(row) + '/' + this.groups.length);
    list.push('技能 ' + parseEnabledSkillIds(row.skills).length);
    if (this.sessionCountsOk) {
      list.push('会话 ' + this.sessionCountOf(row.id));
    }
    return list;
  }

  // 已开分类卡数（判定单源 = ToolTypes.toolGroupAllOn——与工具页卡开关、编辑页「工具调用」
  // 卡面摘要逐条同口径：console-exclusive 与联网压制件不进分母、联网总开关态参与判定，
  // 全开才算该卡已开）
  private toolCardsOn(row: AssistantRow): number {
    const ids: string[] = parseEnabledToolIds(row.tools);
    let on: number = 0;
    for (const group of this.groups) {
      if (toolGroupAllOn(group, ids, row.id === ASSISTANT_CONSOLE_ID, this.searchServiceEnabled)) {
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

  // 助手卡（行数据 + 卡面计数 chip；重建即最新；ForEach 键含纪元 + 选中态后缀）。★ 2026-09-20
  // 卡面改版：形制对齐服务商详情卡 ProviderHeadCard——64 圆底首字头像 + 18fp 名称 + chip 行。
  // ★ 2026-09-01 会话绑定轮领导指令：**点卡 = 切换当前助手**（卡体 onClick → switchActive）；
  // 「编辑」键加回卡内（square_and_pencil，反馈轮 2 形制）→ push 编辑页（默认助手卡亦渲染
  // ——其编辑页为只读提示词入口）；右缘删除键保留（仅用户手建卡——内置默认禁删）；TEXTUAL
  // 图标键形制 = ProviderCardItem 四点键同款（卡体 + 键嵌套点击不冒泡——既有删除键先例，
  // 坑72 口径）；当前助手卡 chip 行首显「✓ 当前」（官方强调色）
  @Builder
  AssistantCard(row: AssistantRow) {
    // Button(Normal) 包裹 = 官方原生按压蒙层（2026-09-12 UI 同形异构归一笔 1——行内
    // 编辑/删除键子组件先命中，嵌套点击关系不变）
    Button() {
      Row({ space: 12 }) {
        // 首字圆底头像（64 = 编辑页详情卡 DetailCard 与服务商详情卡品牌圆底同尺；空名兜底 '?'）
        Text(row.name !== '' ? row.name.substring(0, 1) : '?')
          .fontSize(28)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_on_primary'))
          .width(64)
          .height(64)
          .borderRadius(32)
          .backgroundColor($r('sys.color.ohos_id_color_emphasize'))
          .textAlign(TextAlign.Center)
        Column({ space: 4 }) {
          Text(row.name)
            .fontSize(LIST_CARD_TITLE_FONTSIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          // chip 行（Flex wrap——列宽随名称与两个图标键让位浮动，窄屏或三位数计数自动换行
          // 不裁切；两轴间距 = 徽章行同款 6，行距 4）
          Flex({ wrap: FlexWrap.Wrap,
            space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(4) } }) {
            ForEach(this.chipTexts(row), (text: string) => {
              this.Chip(text, text === CHIP_CURRENT)
            }, (text: string): string => text)
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        // 编辑键（2026-09-01 加回：点卡语义让位切换后，进编辑页回收到本键）
        Button() {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .onClick((): void => {
          this.openEdit(row.id);
        })
        // 删除键（仅用户手建卡渲染——内置默认与控制台助手卡禁删不显示）
        if (row.id !== ASSISTANT_DEFAULT_ID && row.id !== ASSISTANT_CONSOLE_ID) {
          Button() {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(18)
              .fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .onClick((): void => {
            this.openDeleteConfirm(row);
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .type(ButtonType.Normal)
    .width('100%')
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .onClick((): void => {
      this.switchActive(row);
    })
  }

  build() {
    // 滚动层 = Scroll + Column（对话/设置一级页同款——见文件头注释「滚动层」节：Scroll
    // padding 随内容滚动，卡片可滑入标题栏蒙层被渐变模糊透出；★ 勿改回 List——List
    // padding = 视口缩进，坑9 形态）；align TopStart = 短内容顶对齐（坑18）+ 可拖回弹
    //（坑76）
    Scroll() {
      Column({ space: CARD_SPACING }) {
        ForEach(this.rows, (row: AssistantRow) => {
          this.AssistantCard(row)
          // 键含选中态后缀 + 纪元（选中变 / 编辑页返回 / 会话计数回填〔含对话页签增删会话
          // 后经订阅重拉的回填〕/ 联网总开关翻转均经纪元键变整卡重建——SessionCardItem 同款
          // 机制；chip 行随建随算最新值）
        }, (row: AssistantRow): string => row.id +
          (row.id === this.activeId ? '|cur' : '') + '|' + this.cardEpoch)

        if (this.rows.length === 0 && this.hintText === '') {
          Column({ space: 8 }) {
            Text('暂无助手')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
            Text('点右上角「＋」新建。点卡片切换当前助手，编辑键进配置')
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .width('100%')
          .padding(24)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(16)
          .alignItems(HorizontalAlign.Start)
        }
        if (this.hintText !== '') {
          Text(this.hintText)
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_warning'))
            .width('100%')
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      // 留白随内容滚动（Scroll 语义）：topPad = 首卡静止落蒙层下方、bottomPad = 悬浮页签
      // 让位；左右 16 = 卡片水平收窄（页签页口径）
      .padding({ top: this.topPad, bottom: this.bottomPad + 16, left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }
}
