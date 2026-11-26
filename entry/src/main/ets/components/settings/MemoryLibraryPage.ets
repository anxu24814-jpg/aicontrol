// 记忆库管理页（设置记忆页一级分库列表 push 的二级库管理页）：条目管理面自 MemoryPage.ets
// 域级最小拆分整体搬迁（方法体原样迁移只换数据源）。
// · 库参数（MemoryLibraryParam.libraryId）：'global' = 全局库（memories 表）/ 助手 id = 助手库
//  （assistant_memories 表）；标题随库（助手名，行删/失败兜底「助手记忆」）。
// · 标题栏〔＋|⋯〕胶囊与「更多」菜单（立即整理 / 优化记忆 / 记忆历史 / 从其他平台导入 /
//   多选）整组自一级页迁入——操作面跟库走；键件/菜单/锚点/宿主 = MemoryTitleMenu.ets。
//   多选 = 批量删除模式（形态照 PromptLibraryPage）：标题换「已选 N 项」、搜索带收起、拖拽让位。
// · 立即整理：选会话面板按库过滤，落库目标 = 入口库（sinkMemoryNow 第二参）。优化：
//   prepareMemoryOpt / applyMemoryOpt 带库参数。编辑：push 带库上下文，保存落对应库。
// · 刷新链三通道：本页删除即时 reload；增改经子页 onPop 重拉；onShown 重拉（栈下兜底）；两库
//   广播键各挂 @StorageProp @Watch，回调判当前库匹配才重拉（键为编译期常量，分派在回调内）。
// · 上限：库内 ≤ MEMORY_MAX_TOTAL 在「＋」push 前拦截（两库库级独立计数）。
// · 长列表 = **LazyForEach + 头槽静态首项**（Repeat 与头槽混排会使首条连头槽一起拖，原位拖拽
//   不可行——防回游）；容器细节 = MemoryLibraryRows.ets 头注释，壳侧数据源 = MemoryRowsSource
//   单写口两处。选会话半模态（Scroll+ForEach ≤20 有界）不迁。
// · 渲染件已拆 MemoryLibraryRows.ets——本文件为纯业务壳（读取 / 过滤 / 窗口判定 / 弹窗 /
//   半模态 / 导航）。
// · 搜索框承载（决明拍板版式）：框上移标题栏下方带（承载件 SearchTopBand.ets，
//   REGULAR 恒光感；让位算式 searchBandContentTop 单源该件），框吸顶、板块头即内容区首项。
import { CARD_RADIUS } from '../../common/Theme';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { PageShell } from '../../common/PageShell';
import { bumpBusyOverlay, confirmLeaveBusyPage, releaseBusyOverlay } from '../BusyOverlay';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, SECTION_GAP, SECTION_HEADER_GAP, cardBg, cardDescColor, cardTitleColor
} from '../../common/Theme';
import { SectionHeader } from '../SectionHeader';
import { ConfirmDialog, ConfirmDialogTone } from '../chat/ConfirmDialog';
// 多选批量条（共用件——图标三键形态）
import {
  isAllSelectedIn, nextSelectAllIds, SessionMultiselectActionBar
} from '../chat/SessionMultiselectBar';
import { formatConvTime } from '../chat/SessionSearchPanels';
import { IMMERSIVE_LEVEL_KEY, overlayMaterial } from '../../common/ImmersiveLevel';
import {
  ROUTE_MEMORY_EDIT_PAGE, ROUTE_MEMORY_HISTORY_PAGE, ROUTE_MEMORY_IMPORT_PAGE,
  ROUTE_MEMORY_LIBRARY_PAGE
} from '../../common/RouteNames';
import { ConversationRow, queryConversations } from '../../common/store/ChatDb';
import {
  ASSISTANT_MEMORY_LIST_TICK_KEY, deleteAssistantMemory, deleteMemory, MEMORY_LIST_TICK_KEY,
  MEMORY_MAX_TOTAL, MEMORY_SCOPE_GLOBAL, MemoryRow, queryAssistantMemories, queryMemories,
  saveAssistantMemoryOrder, saveMemoryOrder
} from '../../common/store/MemoryDb';
import { AssistantRow, historyFilterIds, queryAssistant } from '../../common/store/AssistantDb';
import {
  MEMORY_ENABLED_KEY, MEMORY_FULL_TIP, MEMORY_SINKING_KEY, MemoryModelPick,
  MemorySinkResult, memorySinkToastText, resolveMemoryModel, sinkMemoryNow
} from '../../common/MemoryGen';
import {
  applyMemoryOpt, MEMORY_OPT_RUNNING_KEY, MemoryOptPrepare, prepareMemoryOpt,
  resolveMemoryOptModel
} from '../../common/MemoryOpt';
import {
  computeMemoryWindow, filterMemoryItemsByKeyword, memoryOptConfirmText, memoryOptToastText,
  MemoryOptOutcome, MemoryOptPlan, MemoryWindowInfo, MemoryWindowItem
} from '../../common/MemoryText';
// 渲染件域（壳单向引渲染件，渲染件不引壳，无模块环）
import { MemoryLibraryRows, MemoryRowsSource } from './MemoryLibraryRows';
// 标题栏下方带搜索框承载件 + 内容顶让位算式
import { SearchTopBand, searchBandContentTop } from '../SearchTopBand';
import { sheetPanelOptions, sheetTitleBarOptions } from '../chat/KimiSheetCommon';
import {
  MemoryMoreMenuAnchor, MemoryTitleBarKeys, MemoryTitleMenuCallbacks, MemoryTitleMenuHost
} from './MemoryTitleMenu';
import { MemoryLibraryParam } from './MemoryPage';
import { InfoCard } from '../InfoCard';
// 行级左滑删除横滑层（交互基准 = 会话页 SessionSwipeItem）
import { SwipeGroup } from '../RowSwipeDelete';

// 记忆功能关闭时的前置提示（菜单项无禁用态可表达，改动作内引导；两键同用一句，单源此处）
const MEMORY_OFF_TIP: string = '记忆功能已关闭，请先在「记忆开关」中打开';

// push 参数载体（编辑页解析；libraryId 判据 = 'global' | 助手 id）
export interface MemoryEditParam {
  id: string;
  libraryId: string;
}

// 导入页 push 参数载体（★ 声明单源 = 本页；消费方 import 消费，禁本地复写——两份声明漂移
// 编译不报错，undefined 被 typeof 兜到 'global' 会静默写错库）
export interface MemoryImportParam {
  libraryId: string;
}

// 库参数载体 MemoryLibraryParam 的声明单源在 MemoryPage.ets（push 发起方）——本文件只 import
// 消费，禁本地复写（机理同上条）

// ── 行卡四点键菜单域已退役：编辑 = 点卡既有通道、删除 = 行左滑、移到窗口内由长按拖拽近似 ──

@Component
export struct MemoryLibraryPage {
  // 页面存活守卫：置位后本组件迟到异步回调不写状态、不碰 UI、不上行；写库等数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 库标识（aboutToAppear 从 push param 解析）：'global' = 全局库 / 助手 id = 助手库
  private libraryId: string = MEMORY_SCOPE_GLOBAL;
  // 页面标题（全局库恒「全局记忆」；助手库 = 助手名，查询失败兜底）
  @Prop title: string = '全局记忆';
  // 条目列表（当前库全量；排序由查询口保证；整体替换即刷）
  @State private memories: MemoryRow[] = [];
  // 搜索词与过滤后的可见行（列表数据源）；空词 = 全显
  @State private keyword: string = '';
  @State private visibleRows: MemoryRow[] = [];
  // 注入窗口：windowIds = 会进注入块的条目 id（卡序）、windowOutCount = 窗口外条数。refreshWindow
  // 单点重算；★ 恒按**全量卡序**算（不是过滤后的显示集），搜索态与窗口态互不干扰
  @State private windowIds: string[] = [];
  @State private windowOutCount: number = 0;
  // 多选模式与选中集（批量删除传库前逐元素拷贝纯数组〔坑6 观察代理数组入 napi〕）
  @State private multiSelect: boolean = false;
  @State private selectedIds: string[] = [];
  // 列表数据源（LazyForEach 契约——壳持本源；唯一写口 = reset，两处调用点 = applyFilter /
  // applyDragMove，均与 visibleRows 同份新序同写，构造上不可漂移）
  private rowsSource: MemoryRowsSource = new MemoryRowsSource();
  // 行左滑互斥组（容器单源——可见集重算 / 拖拽落定 / 进多选 / 渲染件滚动开始均经组收口）
  private swipeGroup: SwipeGroup = new SwipeGroup();
  // 两库广播键各挂一路（回调内按当前库分派——无关 tick 重拉也幂等，分派省一次查询）
  @StorageProp(MEMORY_LIST_TICK_KEY) @Watch('onGlobalTick') globalTick: number = 0;
  @StorageProp(ASSISTANT_MEMORY_LIST_TICK_KEY) @Watch('onAssistantTick') assistantTick: number = 0;
  // 整理 / 优化进行中计数（状态行区两提示行）
  @StorageProp(MEMORY_SINKING_KEY) sinkingCount: number = 0;
  @StorageProp(MEMORY_OPT_RUNNING_KEY) optRunning: number = 0;
  @StorageProp(MEMORY_ENABLED_KEY) memoryEnabled: boolean = true;
  // 选会话半模态（坑64：bindSheet 页面根挂载）
  @State @Watch('onSheetVisibleChanged') private sheetOpen: boolean = false;
  // ── 关闭-再开协调（依据 = KimiSheetCommon.sheetPanelOptions 第四参注释）：离场动效在途期
  // 再点开会被吞或被框架收尾压回——在途期只记开意图，动效结束再补开
  private sheetClosing: boolean = false;
  private pendingOpen: boolean = false;
  @State private conversations: ConversationRow[] = [];
  // 选会话面板滚动控制器（壳 bindToScrollable 绑标题栏渐变模糊）
  private convPickerScroller: Scroller = new Scroller();
  // 删除确认弹窗（坑7：组件成员位构造）
  private confirmCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: ConfirmDialog({
      title: '删除记忆',
      message: '删除后不可恢复。',
      confirmLabel: '删除',
      onConfirm: (): void => {
        this.doDelete();
      }
    }),
    autoCancel: true
  });
  private deleteTarget: MemoryRow | null = null;
  // 优化确认弹窗（message 依赖本次计划，openOptConfirm 内按需重建）
  private optConfirmCtrl: CustomDialogController | null = null;
  // 待应用的优化计划（确认时取用；取消 = 不回填，计划作废）
  private optPlan: MemoryOptPlan | null = null;
  // 标题栏「更多」菜单节点宿主（菜单内容与锚点在 MemoryTitleMenu.ets）
  private titleMenu: MemoryTitleMenuHost = new MemoryTitleMenuHost();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;

  aboutToAppear(): void {
    // push param 解析（缺省/异常 = 全局库兜底）
    const params: Array<Object | null> =
      (this.pathStack.getParamByName(ROUTE_MEMORY_LIBRARY_PAGE) ?? []) as Array<Object | null>;
    const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
    if (last !== null) {
      const parsed = last as MemoryLibraryParam;
      if (typeof parsed.libraryId === 'string' && parsed.libraryId !== '') {
        this.libraryId = parsed.libraryId;
      }
    }
    this.titleMenu.init(this.getUIContext(), this.titleMenuCallbacks());
    if (this.libraryId === MEMORY_SCOPE_GLOBAL) {
      this.title = '全局记忆';
      this.reload();
    } else {
      // 助手库：标题 = 助手名（查询失败兜底「助手记忆」——行删/坏 id 时页面仍可用）
      queryAssistant(this.libraryId)
        .then((row: AssistantRow | null): void => {
          if (this.departed) {
            return;
          }
          this.title = row !== null ? row.name : '助手记忆';
        })
        .catch((): void => {
          if (this.departed) {
            return;
          }
          this.title = '助手记忆';
        });
      this.reload();
    }
  }

  aboutToDisappear(): void {
    this.departed = true;
    this.titleMenu.dispose();
  }

  // 当前库条目读取（唯一数据源分派点——'global' = memories 表，助手 id = assistant_memories）
  private readLibrary(): Promise<MemoryRow[]> {
    return this.libraryId === MEMORY_SCOPE_GLOBAL ?
      queryMemories() : queryAssistantMemories(this.libraryId);
  }

  // 重拉（唯一三态同源点）：全量 memories → 窗口重算（全量卡序）→ 可见行按当前关键词重算
  //（★ 关键词不因重拉被清空）
  private reload(): void {
    this.readLibrary()
      .then((rows: MemoryRow[]): void => {
        if (this.departed) {
          return;
        }
        this.memories = rows;
        this.refreshWindow(rows);
        this.applyFilter(rows);
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '记忆读取失败：' + (e as Error).message });
      });
  }

  // 窗口判定重算（写点：reload 成功与拖拽落库后）——全量卡序 → MemoryText 注入同口径纯函数。
  // ★ 禁在 build 里现算（宪法「渲染克制」），也禁改读过滤后的显示集
  private refreshWindow(rows: MemoryRow[]): void {
    const items: MemoryWindowItem[] = [];
    for (const row of rows) {
      items.push({ id: row.id, content: row.content, createdAt: row.createdAt });
    }
    const info: MemoryWindowInfo = computeMemoryWindow(items);
    this.windowIds = info.inIds;
    this.windowOutCount = info.outCount;
  }

  // 可见行重算（纯内存过滤，不查库；空词 = 全显）。同序写 visibleRows 与数据源（reset 派发
  // 整表重载通知）
  private applyFilter(rows: MemoryRow[]): void {
    // 可见集重算 → 收起左滑展开行（键不变复用的行收不到重算，由容器侧统一收回）
    this.swipeGroup.collapse();
    const visible: MemoryRow[] = filterMemoryItemsByKeyword(rows, this.keyword);
    this.visibleRows = visible;
    this.rowsSource.reset(visible);
  }

  // 原位拖拽落定（onMove 上报数据源下标 = 当前可见行序，本页无偏移）。搜索态下可见行是子集、
  // 落库序是全量卡序 ⇒ 做「可见行槽位回填」：遍历全量序，凡属可见集的位置按新可见序回填，被
  // 过滤掉的条目相对位置不动；非搜索态退化为普通 splice。落库后**不整页 reload**：窗口标记就地
  // 重算，列表按新可见序重建。失败 toast 不静默（P0-1），内存序保留不谎报成功。
  private applyDragMove(from: number, to: number): void {
    // 第二道守卫：多选态不让位（渲染件 dragMoveHandler 已传 undefined；本守卫兜挂载时序边缘）
    if (this.multiSelect) {
      return;
    }
    const visible: MemoryRow[] = this.visibleRows;
    if (from === to || from < 0 || to < 0 || from >= visible.length || to >= visible.length) {
      return;
    }
    const nextVisible: MemoryRow[] = visible.slice();
    const moved: MemoryRow = nextVisible.splice(from, 1)[0];
    nextVisible.splice(to, 0, moved);
    // 可见集判据与回填同源（同一份 id 名单——两处分家会让「显示序」与「可见集」失步）
    const visibleIds: string[] = [];
    for (const row of visible) {
      visibleIds.push(row.id);
    }
    let cursor: number = 0;
    const nextAll: MemoryRow[] = this.memories.slice();
    for (let i = 0; i < nextAll.length; i++) {
      if (visibleIds.indexOf(nextAll[i].id) >= 0) {
        nextAll[i] = nextVisible[cursor];
        cursor++;
      }
    }
    this.memories = nextAll;
    this.visibleRows = nextVisible;
    this.refreshWindow(nextAll);
    // ★ 落定 = **重建数据源顺序**（reset → onDataReloaded），**不用 onDataMove 落位通道**：
    //   混合列表（静态头槽 + LazyForEach）下框架落位动画把「第 i 条移位」画成「第 i+1 条」且
    //   不看数据更新（真机实锤，被拖那条被画回原位）；重建走索引直读，画面必按 nextVisible 重排。
    //   代价 = 放弃落位动画（正确性优先）。
    this.rowsSource.reset(nextVisible);
    // 拖拽落定重建数据源序 → 同帧收起左滑展开行（同 applyFilter 口径，与重排同一同步块）
    this.swipeGroup.collapse();
    const write: Promise<void> = this.libraryId === MEMORY_SCOPE_GLOBAL ?
      saveMemoryOrder(nextAll.map((row: MemoryRow): string => row.id)) :
      saveAssistantMemoryOrder(nextAll.map((row: MemoryRow): string => row.id));
    write
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '排序保存失败：' + (e as Error).message });
      });
  }

  // 0 行态提示文案（两态不可混，分派单源）：库空——全局库多一句自动整理引导（助手库无自动
  // 整理）；搜索无命中（库非空）——单句，不带新增引导
  private emptyHintText(): string {
    if (this.memories.length === 0) {
      return this.libraryId === MEMORY_SCOPE_GLOBAL ?
        '暂无记忆。退出会话时自动整理，也可点右上角「＋」新增，或从菜单导入其他 AI 平台的记忆。' :
        '暂无记忆。点右上角「＋」新增，或从菜单导入其他 AI 平台的记忆。';
    }
    return '没有匹配的记忆。';
  }

  // 全局库广播读点（当前库 = 全局库才重拉——助手库 tick 与本页无关）
  private onGlobalTick(): void {
    if (this.libraryId === MEMORY_SCOPE_GLOBAL) {
      this.reload();
    }
  }

  // 助手库广播读点（tick 不带库标识，以「任一助手库 tick + 当前库为助手库」收窄；跨助手库的
  // 误刷新 = 一次幂等查询，可忽略）
  private onAssistantTick(): void {
    if (this.libraryId !== MEMORY_SCOPE_GLOBAL) {
      this.reload();
    }
  }

  // ── 添加 / 编辑（均 push 编辑页；新增空 id、编辑带 id——库上下文随参数同传）──
  // 上限守卫在 push 前（编辑链不受限）；多选态新建让位（push 返回后残留会与批量删除交错）
  private openAdd(): void {
    if (this.multiSelect) {
      return;
    }
    if (this.memories.length >= MEMORY_MAX_TOTAL) {
      // 库满一句单源（MemoryGen.MEMORY_FULL_TIP——「立即整理」撞上限同句）
      this.getUIContext().getPromptAction().showToast({ message: MEMORY_FULL_TIP });
      return;
    }
    this.openEditPage('');
  }

  private openEditPage(rowId: string): void {
    // onPop 回调 = 子页 pop 带 result 时重拉（坑17——无参 pop 不触发）
    const param: MemoryEditParam = { id: rowId, libraryId: this.libraryId };
    this.pathStack.pushPathByName(ROUTE_MEMORY_EDIT_PAGE, param, (): void => {
      this.reload();
    });
  }

  // ── 记忆历史（优化前自动存档的回看与整库回退入口）──
  // push 参数复用 MemoryLibraryParam（声明单源在 MemoryPage.ets，禁本地复写——漂移会静默落错库）
  private openHistoryPage(): void {
    const param: MemoryLibraryParam = { libraryId: this.libraryId };
    this.pathStack.pushPathByName(ROUTE_MEMORY_HISTORY_PAGE, param, (): void => {
      this.reload();
    });
  }

  // ── 从其他平台导入（别的 AI 平台的用户总结整理成条目批量入库）──
  // 入口守卫两级（同 onSinkKey）：总开关关 → 「记忆功能已关闭」；提取模型两键未配 → 指路功能
  // 模型页。**守卫在打开页面前判**（不让用户白进一页再被弹回）
  private openImportPage(): void {
    if (!this.memoryEnabled) {
      this.getUIContext().getPromptAction().showToast({ message: MEMORY_OFF_TIP });
      return;
    }
    const picked: MemoryModelPick = resolveMemoryModel();
    if (picked.providerId === '' || picked.modelId === '') {
      this.getUIContext().getPromptAction().showToast({
        message: '请先在功能模型页的「记忆提取」卡选择模型'
      });
      return;
    }
    // onPop 回调 = 子页 pop 带 result 时重拉（坑17——无参 pop 不触发）
    const param: MemoryImportParam = { libraryId: this.libraryId };
    this.pathStack.pushPathByName(ROUTE_MEMORY_IMPORT_PAGE, param, (): void => {
      this.reload();
    });
  }

  // ── 标题栏「更多」菜单（立即整理 / 优化记忆 / 记忆历史 / 从其他平台导入 / 多选五项）──
  private titleMenuCallbacks(): MemoryTitleMenuCallbacks {
    return {
      onSink: (): void => {
        this.onSinkKey();
      },
      onOptimize: (): void => {
        this.onOptimizeKey();
      },
      onHistory: (): void => {
        this.openHistoryPage();
      },
      onImport: (): void => {
        this.openImportPage();
      },
      onMultiselect: (): void => {
        this.onMultiSelect();
      }
    };
  }

  // 弹出「更多」菜单（定位 = 隐形锚点 MemoryMoreMenuAnchor，几何见 MemoryTitleMenu.ets）。
  // 多选态让位：原键位一律让位、动作集中在批量条（一处守卫闭全菜单）
  private openMoreMenu(): void {
    if (this.multiSelect) {
      return;
    }
    this.titleMenu.open(this.getUIContext(), this.titleMenuCallbacks(), this.immersiveLevel);
  }

  // ── 多选（菜单「多选」项 → 批量删除模式，形态照 PromptLibraryPage）──
  // 进入多选：幂等 + 进入即清空已选（清空只留批量条「全不选」一处，防两入口）
  private onMultiSelect(): void {
    if (this.multiSelect) {
      return;
    }
    // 多选接管 → 收起左滑展开行（侧滑与批量选择互斥）
    this.swipeGroup.collapse();
    this.multiSelect = true;
    this.selectedIds = [];
  }

  private exitMultiSelect(): void {
    this.multiSelect = false;
    this.selectedIds = [];
  }

  // 可见行 id 集（全选判据与动作的共同输入——**可见集**单源：吃全量会选中屏上看不见的行）
  private visibleRowIds(): string[] {
    return this.visibleRows.map((row: MemoryRow): string => row.id);
  }

  // 全选/全不选（批量条左端键）；判据纯函数在 SessionMultiselectBar（共用单源）
  private toggleSelectAll(): void {
    this.selectedIds = nextSelectAllIds(this.visibleRowIds(), this.selectedIds);
  }

  // 勾选切换（渲染件上行行 id——与点卡通勾选同一逻辑）
  private toggleSelectId(id: string): void {
    const idx: number = this.selectedIds.indexOf(id);
    if (idx >= 0) {
      this.selectedIds = this.selectedIds.filter((item: string): boolean => item !== id);
    } else {
      this.selectedIds = this.selectedIds.concat([id]);
    }
  }

  // 批量删除确认（批量条主操作）；文案与单删同一句（不写动态条数）；空选由本守卫拦住
  private confirmDeleteSelected(): void {
    if (this.selectedIds.length === 0) {
      return;
    }
    this.confirmCtrl.open();
  }

  // ── 删除（菜单「删除」→ 确认弹窗；按库分派删除原语）──
  private askDelete(row: MemoryRow): void {
    this.deleteTarget = row;
    this.confirmCtrl.open();
  }

  private doDelete(): void {
    if (this.multiSelect) {
      this.doDeleteSelected();
      return;
    }
    const target: MemoryRow | null = this.deleteTarget;
    this.deleteTarget = null;
    if (target === null) {
      return;
    }
    const del: Promise<void> = this.libraryId === MEMORY_SCOPE_GLOBAL ?
      deleteMemory(target.id) : deleteAssistantMemory(target.id);
    del
      .then((): void => {
        this.reload();
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
      });
  }

  // 批量删除（逐条调既有单条原语、按库分派——不新增库层批量原语〔两处实现 = 两处漂移面〕；
  // 库内上限有界，逐条代价可接受）。全成才报成功条数，任一失败如实说「部分删除失败」；完成/
  // 失败都退出多选。★ 计数变量名 = settled（勿改回 done——与 assert-skill-domain 负向钉同名）
  private doDeleteSelected(): void {
    const ids: string[] = [];
    for (const id of this.selectedIds) {
      ids.push(id);
    }
    let settled: number = 0;
    let failed: boolean = false;
    for (const id of ids) {
      const del: Promise<void> = this.libraryId === MEMORY_SCOPE_GLOBAL ?
        deleteMemory(id) : deleteAssistantMemory(id);
      del
        .then((): void => {
          settled++;
          if (settled === ids.length) {
            this.reportDeleteSelected(ids.length, failed);
          }
        })
        .catch((): void => {
          failed = true;
          settled++;
          if (settled === ids.length) {
            this.reportDeleteSelected(ids.length, failed);
          }
        });
    }
  }

  // 批量删除结果（单点呈报——成功报条数，失败如实说部分失败不逐条列名；先 toast 再退多选与重拉）
  private reportDeleteSelected(total: number, failed: boolean): void {
    if (failed) {
      this.getUIContext().getPromptAction().showToast({ message: '部分记忆删除失败，请重试' });
    } else {
      this.getUIContext().getPromptAction().showToast({ message: '已删除 ' + total + ' 条记忆' });
    }
    this.exitMultiSelect();
    this.reload();
  }

  // ── 立即整理（半模态选会话；落库目标 = 入口库）──
  // 数据源按库收窄：全局库 = queryConversations([])（in 空数组 = 落全表）；助手库 =
  // queryConversations(historyFilterIds(libraryId))（默认助手含存量未绑定 '' 行，单源同口径）。
  // 取前 20（★ 2026-11-17 整体退役加密会话笔：原「排除加密会话」过滤已删，全部会话可整理）
  private openConvPicker(): void {
    const filterIds: string[] = this.libraryId === MEMORY_SCOPE_GLOBAL ?
      [] : historyFilterIds(this.libraryId);
    queryConversations(filterIds)
      .then((rows: ConversationRow[]): void => {
        if (this.departed) {
          return;
        }
        const usable: ConversationRow[] = [];
        for (const row of rows) {
          usable.push(row);
          if (usable.length >= 20) {
            break;
          }
        }
        this.conversations = usable;
        this.requestOpen();
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '会话读取失败：' + (e as Error).message });
      });
  }

  // ── 关闭-再开协调（机制见字段注释）：开意图落定 → 动效在途挂起 / 否则即开（applyOpen 单入口）──
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
    this.sheetOpen = true;
  }

  // 离场动效结束（sheetPanelOptions 第四参回调）：清在途位 + 按开意图补开
  private onSheetGone(): void {
    this.sheetClosing = false;
    if (!this.sheetOpen) {
      this.applyOpen();
    }
  }

  // 可见性兜底（@Watch）：框架 $$ 收尾回写压回 false 时按开意图补一次；用户关闭先清开意图，
  // 不会误触
  private onSheetVisibleChanged(): void {
    if (!this.sheetOpen) {
      this.applyOpen();
    }
  }

  // 关闭单入口（xmark / 手势 / 点选会话三路同调）：先清开意图 + 置离场在途位，再写可见性
  private requestClose(): void {
    this.pendingOpen = false;
    this.sheetClosing = true;
    this.sheetOpen = false;
  }

  private onPickConversation(conv: ConversationRow): void {
    this.requestClose();
    // 整理完成即重拉 + 结果提示（广播在栈下层不刷新——回调上行才可靠）；目标库 = 入口库。
    // 执行段遮罩：模型请求期间盖应用级浮层 + 拦返回（sinkMemoryNow 全吞错误恒 resolve，
    // finally 归还令牌——BusyOverlay 头注释）
    const busyToken: number = bumpBusyOverlay('正在整理记忆');
    sinkMemoryNow(conv.id, this.libraryId)
      .then((result: MemorySinkResult): void => {
        if (this.departed) {
          return;
        }
        this.reload();
        const tip: string = memorySinkToastText(result);
        if (tip !== '') {
          this.getUIContext().getPromptAction().showToast({ message: tip });
        }
      })
      .finally((): void => {
        releaseBusyOverlay(busyToken);
      });
  }

  // ── 「更多」菜单「立即整理」项（守卫两级 = 总开关 → 提取模型两键；菜单项表达不了禁用态，
  // 守卫落在动作里）──
  private onSinkKey(): void {
    if (!this.memoryEnabled) {
      this.getUIContext().getPromptAction().showToast({ message: MEMORY_OFF_TIP });
      return;
    }
    // 未选记忆提取模型 = 不整理（决明指令取消回退）——前置 toast 引导，不弹选会话面板；
    // 两键齐才算已配置
    const picked: MemoryModelPick = resolveMemoryModel();
    if (picked.providerId === '' || picked.modelId === '') {
      this.getUIContext().getPromptAction().showToast({
        message: '请先在功能模型页的「记忆提取」卡选择模型'
      });
      return;
    }
    this.openConvPicker();
  }

  // ── 「更多」菜单「优化记忆」项（守卫两级同「立即整理」）──
  private onOptimizeKey(): void {
    if (!this.memoryEnabled) {
      this.getUIContext().getPromptAction().showToast({ message: MEMORY_OFF_TIP });
      return;
    }
    // 两键齐才算已配置（只判 providerId 会让半配置态走进请求、最后落 config 态）
    const picked: MemoryModelPick = resolveMemoryOptModel();
    if (picked.providerId === '' || picked.modelId === '') {
      this.getUIContext().getPromptAction().showToast({
        message: '请先在功能模型页的「记忆优化」卡选择模型'
      });
      return;
    }
    this.runOptimize();
  }

  // ── 优化记忆（两段式：先生成计划出确认弹窗，确认后才落库；目标库 = 本页库）──
  // 执行段遮罩只盖 prepare（模型请求可达分钟级）；落库段是秒级事务不盖；计划确认弹窗两段
  // 之间天然不遮（BusyOverlay 头注释）。离开 = 正在生成的计划放弃
  private runOptimize(): void {
    const busyToken: number =
      bumpBusyOverlay('正在生成优化计划', '现在离开，本次优化将被放弃。');
    prepareMemoryOpt(this.libraryId)
      .then((prep: MemoryOptPrepare): void => {
        if (this.departed) {
          return;
        }
        if (prep.plan === null) {
          // 无事可做或出不去——文案与「空串不出提示」规则单源在 memoryOptToastText，本页只负责弹
          const tip: string = memoryOptToastText(prep.outcome);
          if (tip !== '') {
            this.getUIContext().getPromptAction().showToast({ message: tip });
          }
          return;
        }
        this.openOptConfirm(prep.plan);
      })
      .finally((): void => {
        releaseBusyOverlay(busyToken);
      });
  }

  // 确认弹窗（摘要单源 = memoryOptConfirmText）；confirmTone NORMAL（批量改写非删除不配红）
  private openOptConfirm(plan: MemoryOptPlan): void {
    this.optPlan = plan;
    this.optConfirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '优化记忆',
        message: memoryOptConfirmText(plan),
        confirmLabel: '开始优化',
        confirmTone: ConfirmDialogTone.NORMAL,
        onConfirm: (): void => {
          this.doOptimize();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.optConfirmCtrl.open();
  }

  // 落库（确认后）：一个事务改内容 + 删被并入行（目标库 = 本页库）；完成即重拉 + 结果提示
  private doOptimize(): void {
    const plan: MemoryOptPlan | null = this.optPlan;
    this.optPlan = null;
    if (plan === null) {
      return;
    }
    applyMemoryOpt(plan, this.libraryId).then((outcome: MemoryOptOutcome): void => {
      if (this.departed) {
        return;
      }
      this.reload();
      const tip: string = memoryOptToastText(outcome);
      if (tip !== '') {
        this.getUIContext().getPromptAction().showToast({ message: tip });
      }
    });
  }

  // 标题栏覆盖层（HDS 路径：右上角合并胶囊〔＋|⋯〕）——组件内 @Builder 挂载是硬约束（坑30：
  // 全局 @Builder 被 titleBar napi 调用时无视图上下文，启动即闪退）；键件与几何在
  // MemoryTitleMenu.ets，本页只注入两动作
  @Builder
  TitleBarKeys() {
    MemoryTitleBarKeys({
      immersiveLevel: this.immersiveLevel,
      onAdd: (): void => {
        this.openAdd();
      },
      onMore: (): void => {
        this.openMoreMenu();
      }
    })
  }

  // 内容区（Stack 同层三件 = 「更多」菜单隐形锚点 + 内容滚动层 + 多选批量条，顶部对齐）
  @Builder
  Content() {
    Stack({ alignContent: Alignment.Top }) {
      // 「更多」菜单隐形锚点（openMenu 的 TargetInfo 目标；几何 = 「按钮下沿」公式，见域件；
      // HitTest.None 不拦滚动与触摸）
      MemoryMoreMenuAnchor({ topPad: this.topPad })
      this.ContentScroll()
      // 多选批量条（图标三键 ActionBar〔计数在确认弹窗〕；barBottom = bottomPad + 16）。
      // 全选吃**可见集**（visibleRowIds——不选屏外行）
      if (this.multiSelect) {
        SessionMultiselectActionBar({
          allSelected: isAllSelectedIn(this.visibleRowIds(), this.selectedIds),
          barBottom: this.bottomPad + 16,
          onCancel: (): void => {
            this.exitMultiSelect();
          },
          onPrimary: (): void => {
            this.confirmDeleteSelected();
          },
          onToggleAll: (): void => {
            this.toggleSelectAll();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  // 状态行区（总开关关的停用说明 + 两条进行中提示；列表仍可管理——数据管理不依赖开关；
  // 独立 @Builder 供头槽/空分支复用）
  @Builder
  StatusSection() {
    Column({ space: 6 }) {
      if (!this.memoryEnabled) {
        InfoCard({ text: '记忆功能已关闭，不注入也不沉淀。已有条目仍可查看、编辑和删除。' })
      }
      if (this.sinkingCount > 0) {
        Text('正在整理')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width(CARD_PANEL_WIDTH)
      }
      if (this.optRunning > 0) {
        Text('正在优化')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width(CARD_PANEL_WIDTH)
      }
    }
    .width('100%')
  }

  // 条目板块头（只留标题——副标题行 2026-11-01 退役，原三态拼装 entriesSubtitle 随撤）
  @Builder
  EntriesHead() {
    SectionHeader({
      title: '记忆条目',
      hint: '不要存口令、密钥等敏感信息。库内上限 200 条，注入时最多带 30 条。'
    })
  }

  // 内容顶留白：让出标题栏下方带内框位（算式单源 = searchBandContentTop，本页只分派）。
  // 多选态带收起 → 归 topPad
  private contentTopPad(): number {
    return !this.multiSelect ? searchBandContentTop(this.topPad, 28) : this.topPad;
  }

  // 标题栏下方带搜索框：SearchTopBand 恒 REGULAR 光感，几何与命中透传见该件。
  // ★ 决明拍板：框上移到带内 ⇒ 内容区首项变成「记忆条目」板块头
  @Builder
  SearchBand() {
    SearchTopBand({
      keyword: $keyword,
      placeholder: '搜索记忆内容',
      onInput: (value: string): void => {
        this.keyword = value;
        this.applyFilter(this.memories);
      }
    })
  }

  // 非空分支头槽（状态区→板块头 SECTION_GAP、板块头→内容 SECTION_HEADER_GAP；末段到首卡随
  // List space，规范 §4.11），头槽末段 = 「记忆条目」板块头
  @Builder
  RowsHead() {
    Column({ space: SECTION_GAP }) {
      this.StatusSection()
      Column({ space: SECTION_HEADER_GAP }) {
        this.EntriesHead()
      }
      .width('100%')
    }
    .width('100%')
  }

  // 列表内容（0 行分支并回渲染件同一 List——头槽是静态首项恒在场；
  // 空态文案经 emptyText 下发，'' = 有行不出，两态单源 = emptyHintText）
  @Builder
  ContentScroll() {
    MemoryLibraryRows({
      // 数据源 = 过滤后的可见行（壳侧单写口维护的 MemoryRowsSource；窗口判定与「移到窗口内」
      // 仍按全量 memories 算，两者互不影响）
      source: this.rowsSource,
      // 左滑互斥组（壳侧单源下发）
      group: this.swipeGroup,
      windowIds: this.windowIds,
      // 多选态与选中集（渲染件侧 @Prop @Watch → 数据源重载通知，勾选圈走「键并入勾选位」机制）
      multiSelect: this.multiSelect,
      selectedIds: this.selectedIds,
      emptyText: this.visibleRows.length === 0 ? this.emptyHintText() : '',
      appColorMode: this.appColorMode,
      // 顶留白：让出标题栏下方带框位（contentTopPad）
      topPad: this.contentTopPad(),
      bottomPad: this.bottomPad,
      headSlot: (): void => {
        this.RowsHead();
      },
      onOpen: (row: MemoryRow): void => {
        this.openEditPage(row.id);
      },
      // 左滑删除（删除键与长距直达同链，弹既有确认框；删除唯一走本链）
      onSwipeDelete: (row: MemoryRow): void => {
        this.askDelete(row);
      },
      onMove: (from: number, to: number): void => {
        this.applyDragMove(from, to);
      },
      onToggle: (id: string): void => {
        this.toggleSelectId(id);
      }
    })
      .width('100%')
      .height('100%')
  }

  // 选会话半模态（最近 20 条；点选即整理）——按《规范-半模态面板与卡片布局》§1/§2
  // 接入沉浸光感样式
  @Builder
  ConvPickerSheet() {
    Column() {
      HdsNavigation() {
        Scroll(this.convPickerScroller) {
          Column({ space: CARD_SPACING }) {
            if (this.conversations.length === 0) {
              Text(this.libraryId === MEMORY_SCOPE_GLOBAL ?
                '暂无可整理的会话' : '该助手暂无可整理的会话')
                .fontSize(13)
                .fontColor(cardDescColor())
                .width(CARD_PANEL_WIDTH)
                .padding({ top: 16, bottom: 16 })
            } else {
              ForEach(this.conversations, (conv: ConversationRow) => {
                // 会话选择行（Button(Normal) = 官方原生按压蒙层）。★ 蒙层边距统一口径：卡底
                // Column + 四周 padding 4，蒙层距卡外圈 4vp；壳 padding 12/9 回添，几何零位移
                Column() {
                  Button() {
                    Row({ space: 12 }) {
                      Column({ space: 4 }) {
                        Text(conv.title !== '' ? conv.title : '新对话')
                          .fontSize(15)
                          .fontColor(cardTitleColor())
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(formatConvTime(conv.updatedAt))
                          .fontSize(13)
                          .fontColor(cardDescColor())
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                      SymbolGlyph($r('sys.symbol.chevron_right'))
                        .fontSize(14)
                        .fontColor([$r('sys.color.font_secondary')])
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Center)
                  }
                  .type(ButtonType.Normal)
                  .width('100%')
                  .padding({ left: 12, right: 12, top: 9, bottom: 9 })
                  .backgroundColor(Color.Transparent)
                  .borderRadius(CARD_RADIUS)
                  .onClick((): void => {
                    this.onPickConversation(conv);
                  })
                }
                .width(CARD_PANEL_WIDTH)
                .padding(4)
                .backgroundColor(cardBg(this.appColorMode))
                .borderRadius(CARD_RADIUS)
              }, (conv: ConversationRow): string => conv.id)
            }
            // 尾部安全区让位（ignoreLayoutSafeArea BOTTOM 后末卡不贴导航条）
            Row()
              .width('100%')
              .height(24)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 20, bottom: 24 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .clip(false)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .scrollBar(BarState.Off)
      }
      // 标题栏（sheetTitleBarOptions 同源，勿另写——规范 §1）
      .titleBar(sheetTitleBarOptions('选择要整理的会话', '点选一个会话立即整理成记忆',
        (): void => {
          this.requestClose();
        }, this.immersiveLevel))
      .titleMode(HdsNavigationTitleMode.MODAL)
      .hideBackButton(true)
      .bindToScrollable([this.convPickerScroller])
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  build() {
    PageShell({
      // 主标题：多选态 = 「已选 N 项」随勾选实时刷（@Prop 传导）；常态 = 库标题
      title: this.multiSelect ? '已选 ' + this.selectedIds.length + ' 项' : this.title,
      // 页面每次显示重拉（坑25 定稿「onShown 是可靠姿势」——广播在栈下层收不到时的兜底）
      onShown: (): void => {
        this.reload();
      },
      // 执行段返回拦截（BusyOverlay 单源——整理/优化进行中弹「任务进行中」确认，离开 =
      // 撤遮罩 + 任务继续后台跑）
      onBackPressed: (): boolean => {
        return confirmLeaveBusyPage(this.getUIContext(), (): void => {
          this.pathStack.pop();
        });
      },
      // 标题栏两键：覆盖层合并胶囊〔＋|⋯〕（menuHds 传 null，keepStackTitle 保主标题）
      menuHds: null,
      titleBarStack: (): void => {
        this.TitleBarKeys();
      },
      keepStackTitle: true,
      // 标题栏下方带搜索框。多选态带收起（titleBarBottomHidden 经 @Prop 进壳早退）；
      // 内容让位 = contentTopPad
      titleBarBottom: (): void => {
        this.SearchBand();
      },
      titleBarBottomHidden: this.multiSelect,
      content: (): void => {
        this.Content();
      }
    })
      // 关闭链：$$ 双向 + onWillDismiss 内 action.dismiss() 放行（官方契约）；关闭走 requestClose
      // 单入口 + 第四参 onDisappear 补开（关闭-再开协调见字段注释）
      .bindSheet($$this.sheetOpen, this.ConvPickerSheet(), sheetPanelOptions(
        (action: DismissSheetAction): void => {
          action.dismiss();
          this.requestClose();
        }, [SheetSize.MEDIUM, SheetSize.LARGE], undefined,
        (): void => {
          this.onSheetGone();
        }))
  }
}

