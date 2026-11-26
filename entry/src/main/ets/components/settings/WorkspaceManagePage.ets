// 文件工作区管理页（设置 → 文件工作区）：文件夹 / 会话 / 临时三段，默认文件夹，进页不持久化。
// · 页顶两行 = 面包屑条（可点段 + 横滑 + 尾段当前层）+ 分段胶囊，整域 WorkspaceBreadcrumb.ets：
//   承载 = 标题栏下方带〔PageShell.titleBarBottom〕。
// · 文件夹视图 = 层级导航（folders 书 dir 列）：面包屑上一级 = 点父段；文件夹行在前（名称
//   字典序）文件行在后（updatedAt 降序，与 list 工具回执同序）；行菜单改名 / 移动
//   （WorkspaceMovePanel 半模态）/ 删除（文件按 id，文件夹走递归口，确认含件数与合计）；
//   上传落当前目录（避重集 = 当前目录文件名 ∪ 子文件夹段名）。
// · 会话视图 = WorkspaceSessionView（按会话聚合 + 页内下探），rows 经 @Link 整表下传
//   （PageShell.content 内组件 hot 值禁 @Prop——坑16 家族）。
// · 渲染域拆 WorkspaceListRows（行卡族 + 数据源）与 WorkspaceFolderView（文件夹渲染段，hot
//   值 @Link，contentTop 与行键生成器经函数槽注入）；本页 = 装载 / 编排 / 弹窗 / 刷新链，
//   零 bindMenu 行菜单（全经行卡回调上抛）。骨架 = 每视图 List + LazyForEach（行集读取上限
//   WORKSPACE_ROWS_READ_MAX；键含全部可变展示成分，workspaceEntryKey 单源）。
// · 识别文字域拆 WorkspaceOcrActions（行态派生 / 态位刷新 / 动作编排 / 完成收尾）：文件夹段
//   与会话段两段同链共用，会话段经 ocrTick 广播键重派生；本页只持宿主回调与生命周期挂钩。
// · 刷新链（规范-数据存储获取刷新方案 §3 白名单）：aboutToAppear 首载 + 动作后 load() 单一
//   路径；进子目录 / 面包屑跳转是纯内存派生不走库；currentDir 单源经 @Link 下传；无参 pop
//   不挂 onPop（坑17）。
// · 删除走 ChatDb 委托口；「行在文件不在」预览时现检提示，行不删。清空工作区 = 删全表行 +
//   清空目录整棵树，成功回根目录。
// · 标题栏双热区胶囊〔新建文件夹 | ⋯更多〕（2026-11-18 决明拍板：原官方菜单数组单「⋯更多」键
//   退役，新建文件夹自菜单首项移出成胶囊左热区——换位不换链，落点仍 = currentDir）。「⋯更多」
//   菜单（整域 WorkspaceTitleMenu.ets）：项 = 上传文件 / 多选 / 排序方式 / 数据总览 / 清理临时区 /
//   清空工作区（破坏性项垫底）；菜单域不读 @State——弹时快照（坑16 家族免疫）；不生效项置灰
//   （决明拍板）。
// · 上传链：picker → 显示名收口（sanitize → dedupe → 超线截短）→ fd 拷入 → statSync 过
//   10MB 闸 → 容量两闸 → 入库 source='user'；kindFallback 显式 'other'（白名单外件不得被
//   模型按文本读取——P0-1，WorkspaceUtil 头注释同口径）。
// · 文件夹段原位拖拽（照 MemoryLibraryPage.applyDragMove 先例）：只文件夹行可拖，文件行保持
//   updatedAt 序（与 list 工具回执同序 invariant）；落库 = saveWorkspaceDirOrder 整组回写
//   sortOrder；拖拽卡四件套照规范 §4.8；混合列表**禁走 onDataMove 落位通道**（框架自渲染
//   错开一条，真机实锤）；拒绝路数据零变更但仍重载数据源复位画面。
// · 多选批量删除：范围 = 文件夹段 + 临时段（会话段无附着面不接入）；纯函数在
//   WorkspaceMultiselect.ets；临时段行载荷经 onSelectRows 上行 WorkspaceTmpSelectRow（扫盘
//   驱动、不进 entries ⇒ visibleKeys() 段感知）；切段一律退出多选；任一失败如实报「部分删除
//   失败」且重载（P0-1 不静默），完成/失败都退出多选。
// · 排序六档（决明拍板：拖拽与排序二选一 / AI 跟随同序 / 记住选择；语义见 WorkspaceUtil
//   「列表排序方式」段）：PREF_WORKSPACE_SORT_KEY 持久化，现读 currentSortMode() 不挂订阅
//   （写入后显式重派生）；非「自定义」档拖拽停用；排序项只在文件夹段可用；
//   workspace_list 工具回执读同键（AI 与用户同序不变量）。
// · 数据总览 = 菜单 → WorkspaceOverviewSheet 半模态（决明「换个显示位置」，原统计行退役，
//   同屏不两处同一口径）；载荷打开时现派生，纯函数在 WorkspaceStatsUtil。
// · 半模态关闭链按官方契约：单挂载点双态（sheetShow + sheetKind）+ onWillDismiss 放行 +
//   关闭恒不复位内容形态（真机「关不掉 / 变空白」双根因，见 bindSheet 挂载点注释）。
// · 临时段接线：「清理临时区」确认与清库链上提本页，执行后 tmpReloadTick++ 重扫；下探态
//   面包屑走 tmpCrumbSegs 覆盖源（WorkspaceNavCard 现役消费点仅剩会话视图）。
// ★ 面向用户文案走「文案写作规约」（无冒号分号括号连环）。
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { PageShell } from '../../common/PageShell';
import { AttachmentBrief, openAttachmentViewer, openSystemPreview,
  shareAttachment } from '../../common/AttachmentUtil';
import { clearWorkspaceAll, clearWorkspaceTmpAllOp, createWorkspaceDirOp,
  deleteWorkspaceEntryOp,
  deleteWorkspaceFiles,
  deleteWorkspaceTmpConversationOp, deleteWorkspaceTmpFileOp,
  insertWorkspaceFile, isReady, listWorkspaceTmpGroups,
  moveWorkspaceEntryOp,
  queryWorkspaceFiles,
  queryWorkspaceTotal,
  renameWorkspaceEntryOp, saveWorkspaceDirOrder,
  scanWorkspaceTmpOverview } from '../../common/store/ChatDb';
import { queryAssistantNameByIds } from '../../common/store/ChatDbReadSearch';
import { WorkspaceTotalRow, copyUriIntoWorkspace,
  workspaceFilesDir } from '../../common/store/WorkspaceDb';
// 目录四操作域在拆分件 WorkspaceDbEntries（outcome 类型自该件引）
import { WorkspaceEntryOpOutcome } from '../../common/store/WorkspaceDbEntries';
import { PREF_WORKSPACE_SORT_KEY } from '../../common/AppPreferences';
import { WorkspaceFileRow, WorkspaceFolderStats, WORKSPACE_NAME_MAX_CHARS,
  WORKSPACE_ROWS_READ_MAX, WORKSPACE_SOURCE_USER, WS_SORT_CUSTOM,
  assistantIdFromWorkspaceDir, buildWorkspaceRow,
  deriveWorkspaceDirListing, deriveWorkspaceMoveTargets,
  deriveWorkspaceSubtreeStats, extOfWorkspaceName,
  workspaceMoveSelfPath,
  formatWorkspaceSize, isWorkspaceDirRow, joinDirName,
  resolveWorkspaceSortMode,
  uriDisplayName, workspaceCapacityReason,
  workspaceNameRejectReason, workspaceParentDir, workspaceUploadDisplayName,
  workspaceUploadGateReason,
  workspaceFilesInDir } from '../../common/WorkspaceUtil';
import { buildWorkspaceDataStats, WorkspaceDataStats }
  from '../../common/WorkspaceStatsUtil';
import { SEGMENT_BAR_BAND_TOP_INSET } from '../../common/Theme';
import { IMMERSIVE_LEVEL_KEY, overlayMaterial } from '../../common/ImmersiveLevel';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import { InputDialog } from '../chat/InputDialog';
import { searchBandContentTop } from '../SearchTopBand';
import { SETTING_TITLE_WORKSPACE } from '../../common/SettingSearch';
import { WorkspaceListEntry, WorkspaceRowsSource, WorkspaceEntryAddr,
  workspaceEntryKey,
  workspaceEntryAddr } from './WorkspaceListRows';
import { WorkspaceFolderView } from './WorkspaceFolderView';
import { WorkspaceSessionView } from './WorkspaceSessionView';
import { WorkspaceTmpView, WORKSPACE_TMP_ROOT_SEGS } from './WorkspaceTmpView';
import { WORKSPACE_BAND_CONTENT_GAP, WORKSPACE_BAND_CONTENT_HEIGHT,
  WorkspaceCrumbSeg, WorkspaceTopBand } from './WorkspaceBreadcrumb';
import { WorkspaceMoreMenuAnchor, WorkspaceSortMenu, WorkspaceTitleBarKeys,
  WorkspaceTitleMenuCallbacks, WorkspaceTitleMenuHost } from './WorkspaceTitleMenu';
import { WorkspaceMovePanel } from './WorkspaceMovePanel';
import { WorkspaceOverviewSheet } from './WorkspaceOverviewSheet';
import { collectWorkspaceMultiselectStats, workspaceMultiselectMessage,
  workspaceMultiselectTargets, workspaceTmpMultiselectMessage,
  workspaceTmpMultiselectTargets, WorkspaceMultiselectStats,
  WorkspaceTmpSelectRow } from './WorkspaceMultiselect';
import { hasHiddenSelection, isAllSelectedIn, nextSelectAllIds,
  SessionMultiselectActionBar } from '../chat/SessionMultiselectBar';
import { sheetPanelOptions } from '../chat/KimiSheetCommon';
// 识别文字动作域件 WorkspaceOcrActions（行态派生 / 动作编排 / 完成收尾，识别链与引擎释放经
// 域件消费）+ 识别文字页路由（进页单点 pushOcrPage 用）
import { ROUTE_WORKSPACE_OCR_PAGE } from '../../common/RouteNames';
import { WorkspaceOcrPageParam } from './WorkspaceOcrPage';
import { WorkspaceOcrActions, WorkspaceOcrActionsHost } from './WorkspaceOcrActions';

const DOMAIN: number = 0xD5A5;
const TAG: string = 'WorkspaceManage';
// 页名单源 = SettingSearch.SETTING_TITLE_WORKSPACE（行卡、本页标题栏、搜索注册表三处共用）

// 分段索引与选项表（模块级单源，SegmentBar 契约）：不持久化（进页回默认文件夹）；
// 「临时」段 = 临时产物区扫盘驱动，视图件 WorkspaceTmpView
const WS_SEG_FOLDER: number = 0;
const WS_SEG_SESSION: number = 1;
const WS_SEG_TMP: number = 2;
const WS_SEG_ITEMS: SegmentButtonV2Items = new SegmentButtonV2Items([
  { text: '文件夹' },
  { text: '会话' },
  { text: '临时' }
]);
// 带底间距共用 WORKSPACE_BAND_CONTENT_GAP（两页单源，消费侧勿另写数值）

// 助手名反查行（数组入 @State——V1 对 Map 无可观察先例，整组重赋即重渲）
interface WorkspaceAssistantName {
  id: string;
  name: string;
}

@Component
export struct WorkspaceManagePage {
  // 页面存活守卫：置位后本组件迟到异步回调不写状态、不碰 UI、不上行；写库等数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 首载完成标记（false = 加载提示态不渲染两视图——「没读完」不被显示成空态）
  @State private loaded: boolean = false;
  @State private loadFailed: boolean = false;
  // 全表行集（含目录行——文件夹视图派生 / 会话视图 @Link 下传共用真源；动作后整表重赋）
  @State private rows: WorkspaceFileRow[] = [];
  // 文件夹视图扁平项（文件夹行在前文件行在后；与数据源在 deriveEntries 与 applyDragMove
  // 落定两处同点同步，双轨不漂移）
  @State private entries: WorkspaceListEntry[] = [];
  private source: WorkspaceRowsSource = new WorkspaceRowsSource();
  // 分段索引（默认文件夹，不持久化）；挂 @Watch——切段即退出多选（多选扩临时段后一律切段退出）
  @State @Watch('onSegChanged') private segIndex: number = WS_SEG_FOLDER;
  // 文件夹视图当前位置（'' = 根；写点 = 进子目录 / 面包屑跳转 / 清空复位；新建文件夹不动位置）
  @State private currentDir: string = '';
  @State private totalFiles: number = 0;
  @State private totalBytes: number = 0;
  // 助手名反查集（行卡与面包屑共用；助手改名随 rows 重载刷新）
  @State private assistantNames: WorkspaceAssistantName[] = [];
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // ── 列表排序方式 ──
  // 现读 currentSortMode()，不挂 @StorageProp 订阅（坑16 家族「不赌传导」）：写点唯一，
  // 写入后显式重派生
  // ── 多选模式（两态 @Watch 收敛到 source.refresh()——键驱动刷新，勾选位并入行键）──
  // 多选中（菜单「多选」项进入；批量条取消/批量删除完成退出；切段自动退出）
  @State @Watch('onMultiselectStateChanged') private selectMode: boolean = false;
  // 选中待删除条目的基础键集（workspaceEntryKey 单值；数据有界 = 上限为当前层条目数）
  @State @Watch('onMultiselectStateChanged') private selectedKeys: string[] = [];
  // 临时段当前层行载荷（扫盘驱动、不进 entries；子件 onSelectRows 上行，供可见集/全选/反查）
  @State private tmpSelectRows: WorkspaceTmpSelectRow[] = [];
  // 拖拽可用态（结构分支驱动位）：onMove 挂/摘是 LazyForEach 挂载结构，属性摘除不随页内重渲
  // 生效（真机实锤须退出重进）→ @State 驱动 if 分支重建；同步点在 syncDragEnabled 调用处
  @State private dragEnabled: boolean = true;
  // 在途闸（瞬态门闩；上传在途经「更多」菜单置灰呈现）。deleting 升 @State：批量条消费它
  // 驱动「删除中」反馈——普通成员赋值不触发父组件重渲、@Prop 收不到新值（坑57）
  private loading: boolean = false;
  @State private deleting: boolean = false;
  private uploading: boolean = false;
  // ── 半模态单挂载点·双态：一个组件节点只能绑一个 bindSheet（官方限制）——页面根唯一
  //    bindSheet 经 sheetShow / sheetKind 分流多面板。sheetShow 挂 $$ 双向（程序化关闭 = 赋
  //    false）；交互式关闭经 onWillDismiss 内 action.dismiss() 放行——漏调则一切关闭不响应
  //    （真机「关不掉」根因一）。sheetKind = 内容形态，关闭恒不复位——关闭动画期间内容树恒在
  //    （关时置空 = 「面板变空白」根因二，勿回填）。
  //    ★ 加内容形态时三处同步：本注释、SheetHost 分支、各面板 onClose 接线
  @State @Watch('onSheetVisibleChanged') private sheetShow: boolean = false;
  @State private sheetKind: string = 'overview';
  // ── 关闭-再开协调（依据 = KimiSheetCommon.sheetPanelOptions 第四参注释）：离场动效在途期
  // 再点开会被吞或被框架收尾压回——在途期只记开意图，动效结束再补开
  private sheetClosing: boolean = false;
  private pendingOpen: boolean = false;
  // ── 移动面板：三件快照（打开时现派生，面板每次打开重建）+ 被移动条目（普通成员）──
  @State private moveTargets: string[] = [];
  @State private moveAllDirs: string[] = [];
  @State private moveHiddenPrefix: string = '';
  private moveEntry: WorkspaceListEntry | null = null;
  // 移动在途闸（防面板内连点重入——原菜单形态点一次即收菜单，面板形态需要）
  private moving: boolean = false;
  // ── 数据总览面板：载荷打开时现派生（工作区 = 内存行集；临时 = 一次扫盘）。null = 从未打开 ──
  @State private overviewStats: WorkspaceDataStats | null = null;
  // 载荷数据源标记（false = 工作区数据；true = 临时区数据——驱动面板副标题与上限行显隐）
  @State private overviewTmp: boolean = false;
  // 临时视图重扫广播键（@Link + @Watch 重扫；@Prop 下发是黑名单。值无语义，只承载「变了」信号）
  @State private tmpReloadTick: number = 0;
  // 临时段下探面包屑覆盖源（子件 onDrillChange 上行；临时段期间恒非空，空数组仅在另外两段；
  // 数据仍子件自持有，本页只桥接显示层）
  @State private tmpCrumbSegs: WorkspaceCrumbSeg[] = [];
  // 下探退出广播键（页顶条可点段自增，WorkspaceTmpView @Watch 消费触发 exitDrill；值无语义）
  @State private tmpExitTick: number = 0;
  // 会话段识别态位广播键（识别文字域件态位刷新后自增，WorkspaceSessionView @Watch 重派生——
  // @Link 白名单形态。值无语义，只承载「变了」信号）
  @State private ocrTick: number = 0;
  // 「更多」菜单节点宿主（init 建 / open 弹前重建 / dispose 成对释放；域件 WorkspaceTitleMenu.ets）
  private titleMenu: WorkspaceTitleMenuHost = new WorkspaceTitleMenuHost();
  // ── 识别文字（域件 WorkspaceOcrActions.ets）：行态派生 / 态位刷新 / 动作编排 / 完成收尾
  //    全在域件，本页只持宿主回调与生命周期挂钩；文件夹段与会话段两段同链共用 ──
  // 宿主回调面（字面量显式注型——arkts-no-untyped-obj-literals）
  private ocrHost: WorkspaceOcrActionsHost = {
    departed: (): boolean => this.departed,
    pageMounted: (): boolean => this.pageMounted,
    rows: (): WorkspaceFileRow[] => this.rows,
    showToast: (message: string): void => this.showToast(message),
    redraw: (): void => this.redrawOcrStates(),
    stackSize: (): number => this.pathStack.size(),
    pushOcrPage: (fileId: string, name: string): void => this.pushOcrPage(fileId, name)
  };
  private ocrActions: WorkspaceOcrActions = new WorkspaceOcrActions(this.ocrHost);
  // 组件存活位（识别完成回调据此丢弃已亡页收尾——落库在流程内已完成，页亡只影响刷新与自动进页）
  private pageMounted: boolean = false;
  // 确认 / 输入弹窗（构造在成员位——坑7；动态文案经 open* 重建）
  private confirmCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: ConfirmDialog({
      title: '',
      message: '',
      confirmLabel: '',
      onConfirm: (): void => {
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });
  private inputCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: InputDialog({
      title: '',
      placeholder: '',
      confirmLabel: '确认',
      onConfirm: (text: string): void => {
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });

  aboutToAppear(): void {
    // 拖拽可用态初读（首渲染即挂对分支）
    this.syncDragEnabled();
    this.pageMounted = true;
    // 识别文字域：落定监听挂（他处发起任务的落定也刷新行态位——onComplete 归发起方，此处补刷标签）
    this.ocrActions.attach();
    this.load();
    this.titleMenu.init(this.getUIContext(), this.menuCallbacks());
  }

  // 成对释放：宿主 dispose（ComponentContent 不 dispose 泄漏，SDK d.ts NOTE）+ 识别文字域
  // detach（ocrRelease 页级成对释放与 ChatPage 同款——排队列尾不打 in-flight 识别；摘落定监听）
  aboutToDisappear(): void {
    this.departed = true;
    this.pageMounted = false;
    this.ocrActions.detach();
    this.titleMenu.dispose();
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  // ── 装载与派生 ──
  // 首载：全表行集（含目录行）+ 合计并行取；失败 toast + 失败态可重试（P0-1 不静默）；
  // 成功后 rows 整表赋值 + 当前层派生
  private load(): void {
    if (this.loading) {
      return;
    }
    if (!isReady()) {
      this.loadFailed = true;
      this.showToast('数据库尚未就绪，请稍后再试');
      return;
    }
    const filesDir: string = workspaceFilesDir();
    if (filesDir === '') {
      this.loadFailed = true;
      this.showToast('工作区目录未就绪，请稍后再试');
      return;
    }
    this.loading = true;
    this.loadFailed = false;
    Promise.all([queryWorkspaceFiles(WORKSPACE_ROWS_READ_MAX), queryWorkspaceTotal()])
      .then((results: [WorkspaceFileRow[], WorkspaceTotalRow]): void => {
        if (this.departed) {
          return;
        }
        this.rows = results[0];
        this.resolveAssistantNames();
        this.ocrActions.refreshOcrStates();
        this.deriveEntries();
        this.totalFiles = results[1].count;
        this.totalBytes = results[1].bytes;
        this.loaded = true;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.loadFailed = true;
        const err: BusinessError = e as BusinessError;
        hilog.error(DOMAIN, TAG, '工作区列表查询失败：code %{public}d %{public}s',
          typeof err.code === 'number' ? err.code : -1, (e as Error).message);
        this.showToast('工作区列表加载失败，请重试（code ' + err.code + '）');
      })
      .finally((): void => {
        this.loading = false;
      });
  }

  // 助手名反查（目录行卡与面包屑共用）：收集面 = 「assistants/<id> 恰一段」目录行 ∪ 当前路径
  // 前两段；失败回退原始段名（不谎报）；回填后重派生（键含 displayName，键变即重建）
  private resolveAssistantNames(): void {
    const ids: string[] = [];
    const seen: Set<string> = new Set<string>();
    for (const row of this.rows) {
      if (!isWorkspaceDirRow(row)) {
        continue;
      }
      const id: string = assistantIdFromWorkspaceDir(joinDirName(row.dir, row.name));
      if (id !== '' && !seen.has(id)) {
        seen.add(id);
        ids.push(id);
      }
    }
    if (this.currentDir.indexOf('/') >= 0) {
      const twoSeg: string = this.currentDir.split('/').slice(0, 2).join('/');
      const id: string = assistantIdFromWorkspaceDir(twoSeg);
      if (id !== '' && !seen.has(id)) {
        seen.add(id);
        ids.push(id);
      }
    }
    if (ids.length === 0) {
      this.assistantNames = [];
      return;
    }
    queryAssistantNameByIds(ids)
      .then((names: Map<string, string>): void => {
        if (this.departed) {
          return;
        }
        const resolved: WorkspaceAssistantName[] = [];
        names.forEach((name: string, id: string): void => {
          if (name !== '') {
            resolved.push({ id: id, name: name });
          }
        });
        this.assistantNames = resolved;
        this.deriveEntries();
      })
      .catch((): void => {
      });
  }

  // 助手名查值（'' = 调用方回退段名）
  private assistantNameOf(id: string): string {
    for (const pair of this.assistantNames) {
      if (pair.id === id) {
        return pair.name;
      }
    }
    return '';
  }

  // 面包屑助手段显示名（当前路径前两段 = assistants/<id> 时反查；'' = 无替换）
  private assistantSegName(): string {
    if (this.currentDir.indexOf('/') < 0) {
      return '';
    }
    const id: string =
      assistantIdFromWorkspaceDir(this.currentDir.split('/').slice(0, 2).join('/'));
    return id === '' ? '' : this.assistantNameOf(id);
  }

  // 当前层扁平项派生：文件夹行在前（sortOrder 自定义序，并列回落字典序）文件行在后
  //（updatedAt 降序），与 list 工具回执同序；传 currentSortMode() 现读值；助手文件夹段显示
  // 助手名（displayName——定位与动作仍用段名原值）
  private deriveEntries(): void {
    const filesDir: string = workspaceFilesDir();
    const entries: WorkspaceListEntry[] = [];
    for (const dirBrief of deriveWorkspaceDirListing(this.rows, this.currentDir,
      this.currentSortMode()).dirs) {
      const dirPath: string = joinDirName(this.currentDir, dirBrief.name);
      const entry: WorkspaceListEntry = { key: '', kind: 'folder', row: null, absPath: '',
        dirName: dirBrief.name, dirPath: dirPath,
        fileCount: dirBrief.fileCount, folderCount: dirBrief.folderCount };
      const assistantId: string = assistantIdFromWorkspaceDir(dirPath);
      const displayName: string =
        assistantId !== '' ? this.assistantNameOf(assistantId) : '';
      if (displayName !== '') {
        entry.displayName = displayName;
      }
      entry.key = workspaceEntryKey(entry);
      entries.push(entry);
    }
    for (const row of workspaceFilesInDir(this.rows, this.currentDir, this.currentSortMode())) {
      const entry: WorkspaceListEntry = { key: '', kind: 'file', row: row,
        absPath: filesDir + '/' + row.localPath, dirName: '', dirPath: '', fileCount: 0 };
      // 识别文字态位（域件 stateOf 单源）：undefined = 菜单项不出
      entry.ocrState = this.ocrActions.stateOf(row);
      entry.key = workspaceEntryKey(entry);
      entries.push(entry);
    }
    this.entries = entries;
    // 多选兜底清洗：可见集换掉而已选含不可见键即清空——守「已选 ⊆ 可见」不变量（防批量条
    // 计数含不可见行）
    if (this.selectMode && this.selectedKeys.length > 0 &&
      hasHiddenSelection(this.visibleKeys(), this.selectedKeys)) {
      this.selectedKeys = [];
    }
    this.source.reload(entries);
  }

  // 内容区顶留白（算式单源 = searchBandContentTop）；多选态两行带收起 → 归 topPad
  private contentTop(): number {
    if (this.selectMode) {
      return Math.max(this.topPad, 0);
    }
    return Math.max(searchBandContentTop(this.topPad, WORKSPACE_BAND_CONTENT_GAP,
      WORKSPACE_BAND_CONTENT_HEIGHT), 0);
  }

  // 当前目录避重名集：文件名 ∪ 子文件夹段名（守「名与同目录文件夹段名互斥」不变量，新建
  // 预检与上传避重共用）
  private existingNamesInCurrentDir(): string[] {
    const existing: string[] = [];
    for (const row of this.rows) {
      if (!isWorkspaceDirRow(row) && row.dir === this.currentDir) {
        existing.push(row.name);
      }
    }
    for (const dirBrief of deriveWorkspaceDirListing(this.rows, this.currentDir).dirs) {
      existing.push(dirBrief.name);
    }
    return existing;
  }

  // ── 预览：doc 走系统预览窗；图片按 scope 可见图片滑切（文件夹段 = 当前层 / 会话段 =
  // 当前会话）；其余单件进查看器 ──
  private openPreview(entry: WorkspaceListEntry, scope: WorkspaceListEntry[]): void {
    const row: WorkspaceFileRow | null = entry.row;
    if (row === null) {
      return;
    }
    if (!fs.accessSync(entry.absPath)) {
      // 「行在文件不在」：现检提示，行不删（附件域拍板先例）
      this.showToast('文件已不在本机');
      return;
    }
    if (row.kind === 'doc') {
      openSystemPreview(this.getUIContext(), row.name, entry.absPath);
      return;
    }
    if (row.kind === 'image') {
      const briefs: AttachmentBrief[] = [];
      let index: number = -1;
      for (const it of scope) {
        const itRow: WorkspaceFileRow | null = it.row;
        if (itRow === null || itRow.kind !== 'image') {
          continue;
        }
        if (itRow.id === row.id) {
          index = briefs.length;
        }
        briefs.push(this.briefOf(it));
      }
      if (index < 0) {
        return;
      }
      openAttachmentViewer(this.pathStack, briefs, index, true);
      return;
    }
    openAttachmentViewer(this.pathStack, [this.briefOf(entry)], 0, true);
  }

  private briefOf(entry: WorkspaceListEntry): AttachmentBrief {
    const row: WorkspaceFileRow | null = entry.row;
    return { id: row !== null ? row.id : '', name: row !== null ? row.name : '',
      kind: row !== null ? row.kind : 'other', size: row !== null ? row.size : 0,
      absPath: entry.absPath };
  }

  // ── 分享（系统面板自带另存为——本工程保存到公共目录的现行惯例）──
  private shareItem(entry: WorkspaceListEntry): void {
    if (!fs.accessSync(entry.absPath)) {
      this.showToast('文件已不在本机');
      return;
    }
    shareAttachment(this.getUIContext(), this.briefOf(entry));
  }

  // ── 删除分流：文件走按 id 精确删（现链）；文件夹走递归口（确认弹窗含件数与合计）──
  private openDeleteConfirm(entry: WorkspaceListEntry): void {
    if (this.deleting) {
      return;
    }
    if (entry.kind === 'folder') {
      this.openFolderDeleteConfirm(entry);
      return;
    }
    const row: WorkspaceFileRow | null = entry.row;
    if (row === null) {
      return;
    }
    this.confirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '删除文件',
        message: '将删除「' + row.name + '」。删除后无法恢复。',
        confirmLabel: '删除',
        onConfirm: (): void => {
          this.doDelete(row.id);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.confirmCtrl.open();
  }

  private async doDelete(id: string): Promise<void> {
    if (this.deleting) {
      return;
    }
    this.deleting = true;
    try {
      await deleteWorkspaceFiles([id]);
      if (this.departed) {
        return;
      }
      this.load();
    } catch (e) {
      if (this.departed) {
        return;
      }
      const err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, '工作区文件删除失败：code %{public}d %{public}s',
        typeof err.code === 'number' ? err.code : -1, (e as Error).message);
      this.showToast('删除失败，请重试（code ' + err.code + '）');
    } finally {
      this.deleting = false;
    }
  }

  // 删除文件夹：子树统计 → 确认（件数与合计；空文件夹省略件数句）→ 递归口整棵删除
  private openFolderDeleteConfirm(entry: WorkspaceListEntry): void {
    const parentDir: string = workspaceParentDir(entry.dirPath);
    const stats: WorkspaceFolderStats =
      deriveWorkspaceSubtreeStats(this.rows, parentDir, entry.dirName);
    const message: string = stats.fileCount === 0 ?
      '将删除文件夹「' + entry.dirPath + '」。删除后无法恢复。' :
      '将删除文件夹「' + entry.dirPath + '」及里面的 ' + stats.fileCount + ' 个文件，合计 ' +
      formatWorkspaceSize(stats.bytes) + '。删除后无法恢复。';
    this.confirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '删除文件夹',
        message: message,
        confirmLabel: '删除',
        onConfirm: (): void => {
          this.doDeleteFolder(parentDir, entry.dirPath, entry.dirName);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.confirmCtrl.open();
  }

  private async doDeleteFolder(parentDir: string, dirPath: string,
    dirName: string): Promise<void> {
    if (this.deleting) {
      return;
    }
    this.deleting = true;
    try {
      const outcome: WorkspaceEntryOpOutcome = await deleteWorkspaceEntryOp(parentDir, dirName);
      if (this.departed) {
        return;
      }
      if (!outcome.ok) {
        this.showToast(outcome.errorText);
        return;
      }
      this.showToast('已删除文件夹「' + dirPath + '」');
      this.load();
    } catch (e) {
      if (this.departed) {
        return;
      }
      const err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, '工作区文件夹删除失败：code %{public}d %{public}s',
        typeof err.code === 'number' ? err.code : -1, (e as Error).message);
      this.showToast('删除失败，请重试（code ' + err.code + '）');
    } finally {
      this.deleting = false;
    }
  }

  // ── 标题栏「更多」菜单（域件 WorkspaceTitleMenu.ets）：弹前快照组装 + 动作编排 ──
  // 置灰语义（弹时快照）：新建/上传 = 文件夹段；多选 = 文件夹段且就绪，或临时段（会话段置灰
  // = 决明「在不生效的地方应置灰」）；排序 = 文件夹段；清空 = 有件且在途空闲；清理临时区 =
  // 临时段且现扫有组（listWorkspaceTmpGroups 同步毫秒级；非临时段零开销短路）
  private menuCallbacks(): WorkspaceTitleMenuCallbacks {
    return {
      uploadEnabled: this.segIndex === WS_SEG_FOLDER && !this.uploading,
      // 多选扩到临时段（临时段不另判两表装载态——临时视图本就只在 loaded && !loadFailed 时在场）
      multiselectEnabled: (this.segIndex === WS_SEG_FOLDER || this.segIndex === WS_SEG_TMP) &&
        this.loaded && !this.loadFailed,
      sortEnabled: this.segIndex === WS_SEG_FOLDER,
      clearEnabled: !this.deleting && this.totalFiles > 0,
      clearTmpEnabled: this.segIndex === WS_SEG_TMP &&
        listWorkspaceTmpGroups().length > 0,
      onUpload: (): void => {
        this.onUpload();
      },
      onMultiselect: (): void => {
        this.onMultiSelect();
      },
      // 数据总览（三段皆可用不置灰——内容随段，无「不生效的段」）
      onOverview: (): void => {
        this.openDataOverview();
      },
      // 清理临时区（确认与清库编排在本页，执行后广播键重扫）
      onClearTmp: (): void => {
        this.openClearTmpConfirm();
      },
      onClear: (): void => {
        this.openClearConfirm();
      },
      // 排序子菜单壳（坑51/62——CustomBuilder 位挂组件内 @Builder 经 callbacks 传入；
      // current 为弹出一刻快照）
      sortSubMenu: (): void => {
        this.SortSubMenu();
      }
    };
  }

  // 当前排序方式现读（子菜单快照 / 两派生函数 / 拖拽守卫共用）：AppStorage 现读 + resolve 兜底
  //（脏值回 custom）；不挂订阅，写入后显式重派生
  private currentSortMode(): string {
    return resolveWorkspaceSortMode(AppStorage.get<string>(PREF_WORKSPACE_SORT_KEY));
  }

  // 排序偏好唯一写点：写入即持久化（persistProp）+ 同拍显式重派生 + 拖拽结构分支同步
  private writeSortMode(mode: string): void {
    AppStorage.setOrCreate<string>(PREF_WORKSPACE_SORT_KEY, resolveWorkspaceSortMode(mode));
    this.syncDragEnabled();
    this.deriveEntries();
  }

  // 排序二级菜单挂点（菜单本体 = WorkspaceSortMenu，current 弹出一刻现读）
  @Builder
  SortSubMenu() {
    WorkspaceSortMenu({
      current: this.currentSortMode(),
      onPick: (mode: string): void => {
        this.writeSortMode(mode);
      }
    })
  }

  // 标题栏覆盖层（官方自定义区）：双热区胶囊〔新建文件夹|⋯更多〕。组件内 @Builder 挂载是硬约束
  //（坑30：全局 @Builder 被 titleBar napi 直调无视图上下文，启动闪退）；键件在域件 WorkspaceTitleMenu
  @Builder
  TitleBarContent() {
    WorkspaceTitleBarKeys({
      immersiveLevel: this.immersiveLevel,
      onNewFolder: (): void => {
        this.openCreateDirDialog();
      },
      onMore: (): void => {
        this.openMoreMenu();
      }
    })
  }

  private openMoreMenu(): void {
    // 多选态让位（原键位一律让位、动作集中在批量条——两库页/会话列表同款）
    if (this.selectMode) {
      return;
    }
    this.titleMenu.open(this.getUIContext(), this.menuCallbacks(), this.immersiveLevel);
  }

  // ── 多选（状态与执行编排归壳，纯函数在 WorkspaceMultiselect.ets）──

  // 两态 @Watch 收敛（唯一行级态刷新口）：勾选位并入行键，重载通知后被勾行重建、其余复用；
  // 只改成员值不重派通知 = 行卡静默定格，勿删本回调。并同步拖拽结构分支
  private onMultiselectStateChanged(): void {
    this.syncDragEnabled();
    this.source.refresh();
  }

  // 切段退出多选（批量条不悬浮在非当前段）；并维护临时段面包屑覆盖源——临时段填根态两段
  // 常量，其余段清空。子件随分支切换销毁重建，无残留
  private onSegChanged(): void {
    // 多选扩到临时段后一律切段退出（选中键与可见集都按当前段口径，跨段携带必错乱）
    if (this.selectMode) {
      this.exitMultiselect();
    }
    this.tmpCrumbSegs = this.segIndex === WS_SEG_TMP ? WORKSPACE_TMP_ROOT_SEGS : [];
  }

  // 进入多选：幂等 + 进入即清空已选（清空动作只留批量条「全不选」一处，防两入口）
  private onMultiSelect(): void {
    if (this.selectMode) {
      return;
    }
    this.selectMode = true;
    this.selectedKeys = [];
  }

  private exitMultiselect(): void {
    this.selectMode = false;
    this.selectedKeys = [];
  }

  // 可见行基础键集（全选判据与动作的共同输入，可见集单源勿重造；与行键基础段同源）：临时段
  // 取子件上行行键（「所见即所选」）
  private visibleKeys(): string[] {
    if (this.segIndex === WS_SEG_TMP) {
      return this.tmpSelectRows.map((row: WorkspaceTmpSelectRow): string => row.key);
    }
    return this.entries.map((entry: WorkspaceListEntry): string => entry.key);
  }

  // 全选/全不选（批量条左端键）：判据纯函数在 SessionMultiselectBar（多页单源）
  private toggleSelectAll(): void {
    this.selectedKeys = nextSelectAllIds(this.visibleKeys(), this.selectedKeys);
  }

  // 勾选切换（行卡上行 entry.key 基础键）
  private toggleSelectKey(key: string): void {
    if (this.selectedKeys.indexOf(key) >= 0) {
      this.selectedKeys = this.selectedKeys.filter((k: string): boolean => k !== key);
    } else {
      this.selectedKeys = this.selectedKeys.concat([key]);
    }
  }

  // LazyForEach 行键生成器（经函数槽下传）：常态 = entry.key；多选态并入模式位与勾选位——
  // 进出模式全表换装、勾选只重建被勾行（键不变项复用）。定位高亮位随 U6 定位域整支退役
  //（两千零九十节），不再有第二可变成分
  private multiselectEntryKey(entry: WorkspaceListEntry): string {
    if (this.selectMode) {
      return entry.key + '|m1|' + (this.selectedKeys.indexOf(entry.key) >= 0 ? '1' : '0');
    }
    return entry.key;
  }

  // 原位拖拽处理器透传（挂/摘是结构分支决策，本函数恒返回；壳侧 applyDragMove 另有第二道守卫）
  private applyDragMoveHandler(): ((from: number, to: number) => void) {
    return (from: number, to: number): void => {
      this.applyDragMove(from, to);
    };
  }

  // 拖拽可用态同步：赋值 @State 驱动结构分支重建（切换即生效，不依赖属性 patch）
  private syncDragEnabled(): void {
    this.dragEnabled = !this.selectMode && this.currentSortMode() === WS_SORT_CUSTOM;
  }

  // 批量删除确认（批量条主操作）：空选/在途守卫（不加禁用态）；统计与文案在域件纯函数
  //（总量含文件夹子树）
  private confirmDeleteSelected(): void {
    if (this.selectedKeys.length === 0 || this.deleting) {
      return;
    }
    // 临时段：目标 = 子件上行当前层行载荷（组级/文件级成套）；执行 doDeleteTmpSelected
    //（逐条 fs 委托口）；确认口径与文件夹段一致
    if (this.segIndex === WS_SEG_TMP) {
      const tmpTargets: WorkspaceTmpSelectRow[] =
        workspaceTmpMultiselectTargets(this.tmpSelectRows, this.selectedKeys);
      if (tmpTargets.length === 0) {
        return;
      }
      this.confirmCtrl = new CustomDialogController({
        systemMaterial: overlayMaterial(),
        builder: ConfirmDialog({
          title: '批量删除',
          message: workspaceTmpMultiselectMessage(tmpTargets),
          confirmLabel: '删除',
          onConfirm: (): void => {
            this.doDeleteTmpSelected(tmpTargets);
          }
        }),
        autoCancel: true,
        alignment: DialogAlignment.Center
      });
      this.confirmCtrl.open();
      return;
    }
    const stats: WorkspaceMultiselectStats = collectWorkspaceMultiselectStats(this.rows,
      workspaceMultiselectTargets(this.entries, this.selectedKeys));
    this.confirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '批量删除',
        message: workspaceMultiselectMessage(stats),
        confirmLabel: '删除',
        onConfirm: (): void => {
          this.doDeleteSelected();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.confirmCtrl.open();
  }

  // 批量删除执行：文件按 id 批量口一次删；文件夹递归口逐个删（库层无批量口，条目有界）。
  // 任一失败如实报「部分删除失败」且重载（P0-1 不静默；已删不回滚）；完成/失败都退出多选 + 重载
  private async doDeleteSelected(): Promise<void> {
    if (this.deleting) {
      return;
    }
    const targets: WorkspaceListEntry[] =
      workspaceMultiselectTargets(this.entries, this.selectedKeys);
    if (targets.length === 0) {
      return;
    }
    this.deleting = true;
    let failed: boolean = false;
    try {
      const fileIds: string[] = [];
      for (const entry of targets) {
        if (entry.kind === 'folder' || entry.row === null) {
          continue;
        }
        fileIds.push(entry.row.id);
      }
      if (fileIds.length > 0) {
        try {
          await deleteWorkspaceFiles(fileIds);
        } catch (e) {
          failed = true;
          const err: BusinessError = e as BusinessError;
          hilog.error(DOMAIN, TAG, '工作区多选批量删文件失败：code %{public}d %{public}s',
            typeof err.code === 'number' ? err.code : -1, (e as Error).message);
        }
      }
      for (const entry of targets) {
        if (entry.kind !== 'folder') {
          continue;
        }
        const addr: WorkspaceEntryAddr = workspaceEntryAddr(entry);
        try {
          const outcome: WorkspaceEntryOpOutcome = await deleteWorkspaceEntryOp(addr.dir, addr.name);
          if (!outcome.ok) {
            failed = true;
          }
        } catch (e) {
          failed = true;
          const err: BusinessError = e as BusinessError;
          hilog.error(DOMAIN, TAG, '工作区多选批量删文件夹失败：code %{public}d %{public}s',
            typeof err.code === 'number' ? err.code : -1, (e as Error).message);
        }
      }
      this.showToast(failed ? '部分删除失败，请重试' : '已删除 ' + targets.length + ' 项');
      this.exitMultiselect();
      this.load();
    } finally {
      this.deleting = false;
    }
  }

  // 临时段批量删除：组行 = 删该会话整个临时目录（孤儿目录同命中），文件行 = 单件删。任一
  // 失败如实报「部分删除失败」（P0-1 不静默）；完成/失败都退出多选 + tmpReloadTick++ 重扫
  //（不 load()——临时件不在两表）
  private doDeleteTmpSelected(targets: WorkspaceTmpSelectRow[]): void {
    if (this.deleting || targets.length === 0) {
      return;
    }
    this.deleting = true;
    let failed: boolean = false;
    try {
      for (const row of targets) {
        try {
          if (row.isGroup) {
            deleteWorkspaceTmpConversationOp(row.conversationId);
          } else {
            deleteWorkspaceTmpFileOp(row.conversationId, row.name);
          }
        } catch (e) {
          failed = true;
          const err: BusinessError = e as BusinessError;
          hilog.error(DOMAIN, TAG, '临时区多选批量删除失败：code %{public}d %{public}s',
            typeof err.code === 'number' ? err.code : -1, (e as Error).message);
        }
      }
      this.showToast(failed ? '部分删除失败，请重试' : '已删除 ' + targets.length + ' 项');
      this.exitMultiselect();
      this.tmpReloadTick++;
    } finally {
      this.deleting = false;
    }
  }

  // ── 临时区清理（链自 WorkspaceTmpView 上提，入口 = 标题菜单项；执行后 tmpReloadTick++
  // 重扫，子件在临时段视图位必在场）──
  private openClearTmpConfirm(): void {
    if (this.segIndex !== WS_SEG_TMP || listWorkspaceTmpGroups().length === 0) {
      return; // 弹时快照同判据兜底（置灰拦截外的第二道防线）
    }
    this.confirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '清理临时区',
        message: '将删除全部会话的临时文件，此操作不可恢复。',
        confirmLabel: '清理',
        onConfirm: (): void => {
          this.doClearTmp();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.confirmCtrl.open();
  }

  private doClearTmp(): void {
    clearWorkspaceTmpAllOp();
    this.tmpReloadTick++;
  }

  // ── 清空工作区（标题栏「⋯」菜单 → 确认 → 删全表行 + 清空目录整棵树；成功回根目录）──
  private openClearConfirm(): void {
    if (this.deleting || this.totalFiles === 0) {
      return;
    }
    this.confirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '清空工作区',
        message: '将删除工作区里全部 ' + this.totalFiles + ' 个文件，合计 ' +
          formatWorkspaceSize(this.totalBytes) + '。删除后无法恢复。',
        confirmLabel: '清空',
        onConfirm: (): void => {
          this.doClear();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.confirmCtrl.open();
  }

  private async doClear(): Promise<void> {
    if (this.deleting) {
      return;
    }
    this.deleting = true;
    try {
      await clearWorkspaceAll();
      if (this.departed) {
        return;
      }
      this.currentDir = '';
      this.load();
      this.showToast('工作区已清空');
    } catch (e) {
      if (this.departed) {
        return;
      }
      const err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, '工作区清空失败：code %{public}d %{public}s',
        typeof err.code === 'number' ? err.code : -1, (e as Error).message);
      this.showToast('清空失败，请重试（code ' + err.code + '）');
    } finally {
      this.deleting = false;
    }
  }

  // ── 新建文件夹（入口 = 标题菜单项）：名称闸 + 重名预检 → createWorkspaceDirOp（folders 四
  // 委托口之一，成功后 reload 即现新行）──
  private openCreateDirDialog(): void {
    this.inputCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: '新建文件夹',
        placeholder: '例如 资料',
        confirmLabel: '创建',
        maxLength: WORKSPACE_NAME_MAX_CHARS,
        onConfirm: (text: string): void => {
          this.doCreateDir(text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.inputCtrl.open();
  }

  private async doCreateDir(rawName: string): Promise<void> {
    const name: string = rawName.trim();
    const reject: string = workspaceNameRejectReason(name);
    if (reject !== '') {
      this.showToast(reject);
      return;
    }
    if (this.existingNamesInCurrentDir().indexOf(name) >= 0) {
      this.showToast('该位置已有同名文件或文件夹');
      return;
    }
    try {
      const dirPath: string = joinDirName(this.currentDir, name);
      const outcome: WorkspaceEntryOpOutcome =
        await createWorkspaceDirOp(dirPath, WORKSPACE_SOURCE_USER, '', '');
        if (this.departed) {
          return;
        }
      if (!outcome.ok) {
        this.showToast(outcome.errorText);
        return;
      }
      if (outcome.alreadyExists) {
        this.showToast('该位置已有同名文件或文件夹');
        return;
      }
      this.showToast('已创建文件夹「' + name + '」');
      this.load();
    } catch (e) {
      if (this.departed) {
        return;
      }
      const err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, '工作区新建文件夹失败：code %{public}d %{public}s',
        typeof err.code === 'number' ? err.code : -1, (e as Error).message);
      this.showToast('新建文件夹失败，请重试（code ' + err.code + '）');
    }
  }

  // ── 改名（文件与文件夹共用弹窗；folders rename 委托口——重名拒/未命中/二义拒原样透传）──
  private openRenameDialog(entry: WorkspaceListEntry): void {
    const isFolder: boolean = entry.kind === 'folder';
    const currentName: string = isFolder ? entry.dirName :
      (entry.row !== null ? entry.row.name : '');
    this.inputCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: '重命名',
        initialText: currentName,
        confirmLabel: '保存',
        maxLength: WORKSPACE_NAME_MAX_CHARS,
        onConfirm: (text: string): void => {
          this.doRename(entry, text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.inputCtrl.open();
  }

  private async doRename(entry: WorkspaceListEntry, rawName: string): Promise<void> {
    const newName: string = rawName.trim();
    // 定位二元组单源
    const addr: WorkspaceEntryAddr = workspaceEntryAddr(entry);
    try {
      const outcome: WorkspaceEntryOpOutcome = await renameWorkspaceEntryOp(addr.dir, addr.name, newName);
      if (this.departed) {
        return;
      }
      if (!outcome.ok) {
        this.showToast(outcome.errorText);
        return;
      }
      this.showToast('已改名为「' + newName + '」');
      this.load();
    } catch (e) {
      if (this.departed) {
        return;
      }
      const err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, '工作区重命名失败：code %{public}d %{public}s',
        typeof err.code === 'number' ? err.code : -1, (e as Error).message);
      this.showToast('重命名失败，请重试（code ' + err.code + '）');
    }
  }

  // ── 移动（folders move 委托口；下钻式半模态逐层进入）：可落点集 = 根 + 全部目录，不含
  // 当前目录/自身/子树（deriveWorkspaceMoveTargets 保证）；空候选 toast 指引不开空面板 ──
  private openMoveSheet(entry: WorkspaceListEntry): void {
    const addr: WorkspaceEntryAddr = workspaceEntryAddr(entry);
    const targets: string[] = deriveWorkspaceMoveTargets(this.rows, addr.dir, addr.name);
    if (targets.length === 0) {
      this.noMoveTarget();
      return;
    }
    // 下钻数据：全部目录路径（逐层列表源）+ 隐藏分支（文件夹自身子树，workspaceMoveSelfPath
    // 单源；文件不隐藏）
    const allDirs: string[] = [];
    for (const row of this.rows) {
      if (isWorkspaceDirRow(row)) {
        allDirs.push(joinDirName(row.dir, row.name));
      }
    }
    this.moveEntry = entry;
    this.moveTargets = targets;
    this.moveAllDirs = allDirs;
    this.moveHiddenPrefix = entry.kind === 'folder' ? workspaceMoveSelfPath(addr.dir, addr.name) : '';
    this.sheetKind = 'move';
    this.requestOpen();
  }

  // 无可移动目标指引（菜单项不摘除，点击出 toast）
  private noMoveTarget(): void {
    this.showToast('没有可移动到的其他文件夹');
  }

  // ── 识别文字（动作域件 WorkspaceOcrActions）──
  // 进识别文字页单点（行菜单「查看识别文字」与识别完成自动进共用）：返回刷新链（坑17：pop
  // 恒带 result 才触发）——行态位重派生
  private pushOcrPage(fileId: string, name: string): void {
    const param: WorkspaceOcrPageParam = { fileId: fileId, name: name };
    this.pathStack.pushPathByName(ROUTE_WORKSPACE_OCR_PAGE, param, (): void => {
      this.ocrActions.refreshOcrStates();
    });
  }

  // 识别态位重派生单点（域件 redraw 宿主回调）：文件夹视图重派生 + 会话段广播键自增
  private redrawOcrStates(): void {
    this.deriveEntries();
    this.ocrTick++;
  }

  // ── 关闭-再开协调（机制见字段注释）──
  // 开意图落定 → 动效在途挂起 / 否则即开（applyOpen 单入口，两面板补开两路共用）
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
    this.sheetShow = true;
  }

  // 离场动效结束（sheetPanelOptions 第四参回调）：清在途位 + 按开意图补开
  private onSheetGone(): void {
    this.sheetClosing = false;
    if (!this.sheetShow) {
      this.applyOpen();
    }
  }

  // 可见性兜底（@Watch）：框架 $$ 收尾回写压回 false 时按开意图补一次；用户关闭先清开意图，
  // 不会误触
  private onSheetVisibleChanged(): void {
    if (!this.sheetShow) {
      this.applyOpen();
    }
  }

  // 面板关闭单源（xmark 与手势两路同调——半模态规范硬约束）：先清开意图 + 置离场在途位，
  // 再写 false；内容形态恒不复位
  private requestCloseMove(): void {
    this.pendingOpen = false;
    this.sheetClosing = true;
    this.sheetShow = false;
  }

  // 数据总览关闭单源（同上；onWillDismiss 按当前态路由）
  private requestCloseOverview(): void {
    this.pendingOpen = false;
    this.sheetClosing = true;
    this.sheetShow = false;
  }

  // ── 数据总览（标题菜单 → 半模态面板）──
  // 数据面随段：文件夹/会话段 = 全库内存行集现派生（与列表所见同源）；临时段 = 一次扫盘
  //（不经 rows，库未就绪也可用）
  private openDataOverview(): void {
    if (this.segIndex === WS_SEG_TMP) {
      this.overviewTmp = true;
      this.overviewStats = scanWorkspaceTmpOverview();
      this.sheetKind = 'overview';
      this.requestOpen();
      return;
    }
    if (!this.loaded || this.loadFailed) {
      // 工作区侧数据未就绪/失败：中文 toast 不静默（P0-1）
      this.showToast(this.loadFailed ? '工作区列表加载失败，请重试' : '正在读取工作区，请稍后再试');
      return;
    }
    this.overviewTmp = false;
    this.overviewStats = buildWorkspaceDataStats(this.rows);
    this.sheetKind = 'overview';
    this.requestOpen();
  }

  // 面板点选即落库：成功关面板 + toast + 重载；失败 toast 后保留面板可重试（P0-1）；在途闸
  // 防连点
  private async moveEntryTo(targetDir: string): Promise<void> {
    if (this.moving) {
      return;
    }
    const entry: WorkspaceListEntry | null = this.moveEntry;
    if (entry === null) {
      return;
    }
    this.moving = true;
    const addr: WorkspaceEntryAddr = workspaceEntryAddr(entry);
    try {
      const outcome: WorkspaceEntryOpOutcome = await moveWorkspaceEntryOp(addr.dir, addr.name, targetDir);
      if (this.departed) {
        return;
      }
      if (!outcome.ok) {
        this.showToast(outcome.errorText);
        return;
      }
      this.requestCloseMove();
      this.showToast(targetDir === '' ? '已移动到工作区根目录' : '已移动到「' + targetDir + '」');
      this.load();
    } catch (e) {
      if (this.departed) {
        return;
      }
      const err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, '工作区移动失败：code %{public}d %{public}s',
        typeof err.code === 'number' ? err.code : -1, (e as Error).message);
      this.showToast('移动失败，请重试（code ' + err.code + '）');
    } finally {
      this.moving = false;
    }
  }

  // 进入子目录（currentDir 单写口之一；纯内存派生不走库）
  private openFolder(entry: WorkspaceListEntry): void {
    this.currentDir = entry.dirPath;
    this.deriveEntries();
  }

  // 面包屑点段跳转（currentDir 单写口之二；上一级 = 点父段，尾段不可点故同值守卫仅作防线）。
  // 临时段两态：下探态任一可点段 = 经 tmpExitTick 下发子件 exitDrill 回组列表；根态「工作区」
  // 段 = 切回文件夹段根层（段胶囊同步切走 + currentDir 回根）。文件夹段走目录跳转
  private onBreadcrumbJump(dir: string): void {
    if (this.segIndex === WS_SEG_TMP && this.tmpCrumbSegs.length > 0) {
      if (this.tmpCrumbSegs.length > WORKSPACE_TMP_ROOT_SEGS.length) {
        this.tmpExitTick++;
      } else {
        this.segIndex = WS_SEG_FOLDER;
        this.currentDir = '';
        this.deriveEntries();
      }
      return;
    }
    if (dir === this.currentDir) {
      return;
    }
    this.currentDir = dir;
    this.deriveEntries();
  }

  // ── 文件夹段原位拖拽落定（MemoryLibraryPage.applyDragMove 同构；onMove 上报数据源下标，
  // 本页无偏移）。范围守卫：from/to 两端都须是文件夹行。落定三拍：
  // ①entries 纯 splice（无搜索无过滤，可见集即全量）；
  // ②rows 同拍写 sortOrder（不写则 deriveEntries 按旧序重排，结果页内回退）；ids 按新序收集，
  //   与文件夹数不齐即放弃落库（内存序保留，下次 load 校准）；
  // ③source.reload 整表重建——混合列表（静态头 + 条目 + 条件尾）**禁走 onDataMove 落位通道**
  //   （框架自渲染错开一条且不看数据更新，真机实锤）；拒绝路数据零变更但仍须重建复位画面。
  // 持久化失败 toast 不静默（P0-1），内存序保留不回滚；拖拽不走 load()（刷新链特例）。
  private applyDragMove(from: number, to: number): void {
    // 第二道守卫（第一道 = 渲染侧结构分支不挂 onMove）：多选态与非「自定义」档同判——拖拽
    // 只改自定义序
    if (this.selectMode || this.currentSortMode() !== WS_SORT_CUSTOM) {
      return;
    }
    const entries: WorkspaceListEntry[] = this.entries;
    if (from === to || from < 0 || to < 0 || from >= entries.length || to >= entries.length) {
      return;
    }
    if (entries[from].kind !== 'folder' || entries[to].kind !== 'folder') {
      // 拒绝路复位（文件行参与或跨界；文件行不做自定义序见头注释）
      this.source.reload(entries);
      return;
    }
    const next: WorkspaceListEntry[] = entries.slice();
    const moved: WorkspaceListEntry = next.splice(from, 1)[0];
    next.splice(to, 0, moved);
    this.entries = next;
    const ids: string[] = [];
    let folderCount: number = 0;
    let order: number = 0;
    for (const entry of next) {
      if (entry.kind !== 'folder') {
        continue;
      }
      folderCount++;
      for (const row of this.rows) {
        if (isWorkspaceDirRow(row) && row.dir === this.currentDir &&
          row.name === entry.dirName) {
          row.sortOrder = order;
          ids.push(row.id);
          break;
        }
      }
      order++;
    }
    // 落定 = 重建数据源顺序（禁 onDataMove——混合列表落位坑，见上）
    this.source.reload(next);
    if (folderCount === 0 || ids.length !== folderCount) {
      return; // 行集缺行不落库（防线，见上②）——内存序保留到下次 load 校准
    }
    saveWorkspaceDirOrder(ids)
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.showToast('排序保存失败：' + (e as Error).message);
      });
  }

  // 上传中途拒收：删刚拷入的文件（best-effort，残留由「清空工作区」兜底）+ toast（P0-1）；
  // 大小闸与容量闸共用
  private rejectUpload(absPath: string, message: string): void {
    try {
      fs.unlinkSync(absPath);
    } catch {
      // 删不掉留残留，由「清空工作区」兜底
    }
    this.showToast(message);
  }

  // ── 上传链（picker → 名收口 → fd 拷入当前目录 → 大小闸 → 容量闸 → 入库）──
  private async onUpload(): Promise<void> {
    if (this.uploading) {
      return;
    }
    const ctx: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (ctx === undefined) {
      this.showToast('无法获取应用上下文');
      return;
    }
    if (!isReady()) {
      this.showToast('数据库尚未就绪，请稍后再试');
      return;
    }
    this.uploading = true;
    try {
      // 官方文档选择器（context 构造免权限；单选）
      const docOpts: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      docOpts.maxSelectNumber = 1;
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      const uris: Array<string> = await docPicker.select(docOpts);
      if (this.departed) {
        return;
      }
      if (uris.length === 0) {
        return; // 用户取消，静默
      }
      const uri: string = uris[0];
      const rawName: string = uriDisplayName(uri, '上传文件_' + Date.now());
      // 显示名收口（单源 workspaceUploadDisplayName）：预留避重后缀位先截短 base 一次成型——
      // 原「越线截回」可还原撞名，name 列无唯一约束即双行二义。避重只看当前目录，扩展名自
      // 最终显示名派生
      const displayName: string =
        workspaceUploadDisplayName(rawName, this.existingNamesInCurrentDir());
      // fd 拷入（新 UUID 物理名；临时授权必须拷进沙箱；落点 = 当前目录）；失败 toast 中止
      const fileId: string = util.generateRandomUUID(true);
      const ext: string = extOfWorkspaceName(displayName);
      let localPath: string = '';
      try {
        localPath = copyUriIntoWorkspace(uri, fileId, ext, this.currentDir);
      } catch (e) {
        if (this.departed) {
          return;
        }
        this.showToast('文件拷贝失败：' + (e as Error).message);
        return;
      }
      const filesDir: string = workspaceFilesDir();
      const absPath: string = filesDir + '/' + localPath;
      // 大小闸（拷后 statSync 取准确值；超限删刚拷文件）
      const size: number = fs.statSync(absPath).size;
      const sizeGate: string = workspaceUploadGateReason(rawName, size);
      if (sizeGate !== '') {
        this.rejectUpload(absPath, sizeGate);
        return;
      }
      // 容量两闸（上传与写入共用——WorkspaceUtil 单源）：现读合计防页面缓存过期
      const total: WorkspaceTotalRow = await queryWorkspaceTotal();
      const capacityGate: string = workspaceCapacityReason(size, total.count, total.bytes);
      if (capacityGate !== '') {
        this.rejectUpload(absPath, capacityGate);
        return;
      }
      // 入库（source='user'，追溯两列恒空串；kindFallback 显式 'other'——白名单外件不得被模型
      // 按文本读取（P0-1）；dir 末参 = 落点）
      const row: WorkspaceFileRow = buildWorkspaceRow(fileId, displayName, size,
        WORKSPACE_SOURCE_USER, '', '', Date.now(), 'other', this.currentDir);
      await insertWorkspaceFile(row);
      if (this.departed) {
        return;
      }
      this.showToast('已上传「' + displayName + '」到 ' +
        (this.currentDir === '' ? '工作区根目录' : '「' + this.currentDir + '」'));
      this.load();
    } catch (e) {
      if (this.departed) {
        return;
      }
      const err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, '工作区上传失败：code %{public}d %{public}s',
        typeof err.code === 'number' ? err.code : -1, (e as Error).message);
      this.showToast('上传失败：' + (e as Error).message);
    } finally {
      this.uploading = false;
    }
  }

  // 半模态面板内容（坑51 红线：bindSheet builder 位挂组件内 @Builder——sheetKind 分支链）：
  // 'move' = 移动面板（三件快照打开时现派生）；'overview' = 数据总览（stats null 分支不可达，
  // 仍留空态护航不白屏）
  @Builder
  SheetHost() {
    if (this.sheetKind === 'move') {
      WorkspaceMovePanel({
        targets: this.moveTargets,
        allDirs: this.moveAllDirs,
        hiddenPrefix: this.moveHiddenPrefix,
        bottomInset: this.bottomPad,
        onPickTarget: (target: string): void => {
          this.moveEntryTo(target);
        },
        onClose: (): void => {
          this.requestCloseMove();
        }
      })
    } else if (this.sheetKind === 'overview') {
      WorkspaceOverviewSheet({
        fileCount: this.overviewStats !== null ? this.overviewStats.fileCount : 0,
        bytes: this.overviewStats !== null ? this.overviewStats.bytes : 0,
        subCount: this.overviewStats !== null ? this.overviewStats.subCount : 0,
        tmp: this.overviewTmp,
        types: this.overviewStats !== null ? this.overviewStats.types : [],
        bottomInset: this.bottomPad,
        onClose: (): void => {
          this.requestCloseOverview();
        }
      })
    }
  }

  // 标题栏下方带两行承载（几何/材质/命中透传在域件）：面包屑只在文件夹段可用；临时段下探态
  // 经 tmpSegs 覆盖源亮起（「工作区 > 临时 > 会话标题」）
  @Builder
  TopSegmentBand() {
    WorkspaceTopBand({
      currentDir: $currentDir,
      tmpSegs: $tmpCrumbSegs,
      segIndex: $segIndex,
      segItems: WS_SEG_ITEMS,
      enabledSegIndex: WS_SEG_FOLDER,
      assistantSegName: this.assistantSegName(),
      onJump: (dir: string): void => {
        this.onBreadcrumbJump(dir);
      }
    })
  }

  @Builder
  Content() {
    // Stack 壳：内容层 + 「更多」菜单隐形锚点同层挂载（锚点命中穿透、不占布局流）
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        // 页级三态守卫 + 三视图分派：判据 = 文件夹段或页级两态（loadFailed → 失败卡 / !loaded
        // → 加载提示 / 就绪且文件夹段 → 列表）；两态分支不看段位，失败/加载拦在所有视图之外。
        // 临时段 = WorkspaceTmpView 扫盘驱动，不经 rows。两函数槽注入 = contentTop 算式与
        // multiselectEntryKey 行键生成器（现读，非值快照）
        if (this.segIndex === WS_SEG_FOLDER || this.loadFailed || !this.loaded) {
          WorkspaceFolderView({
            entries: $entries,
            selectMode: $selectMode,
            selectedKeys: $selectedKeys,
            dragEnabled: $dragEnabled,
            currentDir: $currentDir,
            loadFailed: $loadFailed,
            loaded: $loaded,
            source: this.source,
            contentTop: (): number => {
              return this.contentTop();
            },
            bottomPad: this.bottomPad,
            entryKey: (entry: WorkspaceListEntry): string => {
              return this.multiselectEntryKey(entry);
            },
            onOpen: (entry: WorkspaceListEntry): void => {
              this.openFolder(entry);
            },
            onToggle: (entry: WorkspaceListEntry): void => {
              this.toggleSelectKey(entry.key);
            },
            onRename: (entry: WorkspaceListEntry): void => {
              this.openRenameDialog(entry);
            },
            onMove: (entry: WorkspaceListEntry): void => {
              this.openMoveSheet(entry);
            },
            onDelete: (entry: WorkspaceListEntry): void => {
              this.openDeleteConfirm(entry);
            },
            onPreview: (entry: WorkspaceListEntry, scope: WorkspaceListEntry[]): void => {
              this.openPreview(entry, scope);
            },
            onShare: (entry: WorkspaceListEntry): void => {
              this.shareItem(entry);
            },
            onOcr: (entry: WorkspaceListEntry): void => {
              this.ocrActions.onOcrAction(entry);
            },
            onRetry: (): void => {
              this.load();
            },
            onRowDragMove: this.applyDragMoveHandler()
          })
            .layoutWeight(1)
        } else if (this.segIndex === WS_SEG_SESSION) {
          WorkspaceSessionView({
            rows: $rows,
            topPad: this.contentTop(),
            bottomPad: this.bottomPad,
            // 会话段识别文字入口（2026-10-31 补口）：态位广播键 + 派生与动作透传域件——与文
            // 件夹段同链，完成后自动进查看页同享（广播键 @Link 白名单形态）
            ocrTick: $ocrTick,
            ocrStateOf: (row: WorkspaceFileRow): string | undefined => {
              return this.ocrActions.stateOf(row);
            },
            onOcr: (entry: WorkspaceListEntry): void => {
              this.ocrActions.onOcrAction(entry);
            },
            onPreview: (entry: WorkspaceListEntry, scope: WorkspaceListEntry[]): void => {
              this.openPreview(entry, scope);
            },
            onShare: (entry: WorkspaceListEntry): void => {
              this.shareItem(entry);
            },
            onRename: (entry: WorkspaceListEntry): void => {
              this.openRenameDialog(entry);
            },
            onMove: (entry: WorkspaceListEntry): void => {
              this.openMoveSheet(entry);
            },
            onDelete: (entry: WorkspaceListEntry): void => {
              this.openDeleteConfirm(entry);
            }
          })
            .layoutWeight(1)
        } else {
          WorkspaceTmpView({
            topPad: this.contentTop(),
            bottomPad: this.bottomPad,
            // 多选两态下行（@Link 白名单形态，@Prop 下发黑名单规避）
            selectMode: $selectMode,
            selectedKeys: $selectedKeys,
            // 重扫广播键（标题菜单「清理临时区」执行后自增——@Link 白名单形态）
            reloadTick: $tmpReloadTick,
            // 下探退出广播键（页顶条临时段可点段自增——@Link 同族形制）
            exitTick: $tmpExitTick,
            // 下探层级上行（驱动页顶条覆盖源——回调上行白名单形态）
            onDrillChange: (segs: WorkspaceCrumbSeg[]): void => {
              this.tmpCrumbSegs = segs;
            },
            // 转存落库后重载两表驱动段（切回文件夹/会话段不停旧态；纯清理动作不触发）
            onMutated: (): void => {
              this.load();
            },
            // 勾选切换上行（壳侧 toggleSelectKey 单源）
            onToggle: (key: string): void => {
              this.toggleSelectKey(key);
            },
            // 当前层行载荷上行（可见集/全选/批量删除反查的输入）。已选 ⊆ 可见兜底：重扫后含
            // 不可见键即清空（同 deriveEntries 清洗口径）
            onSelectRows: (rows: WorkspaceTmpSelectRow[]): void => {
              this.tmpSelectRows = rows;
              if (this.selectMode && this.selectedKeys.length > 0 &&
                hasHiddenSelection(this.visibleKeys(), this.selectedKeys)) {
                this.selectedKeys = [];
              }
            }
          })
            .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')

      // 「更多」菜单隐形锚点（openMenu 的 TargetInfo 目标；两路径均挂；几何/穿透见域件注释）
      WorkspaceMoreMenuAnchor({ topPad: this.topPad })

      // 多选批量条（恒挂图标三键 ActionBar；barBottom = bottomPad + 16）。挂载判据 = 多选态
      // 且文件夹/临时段视图在场；全选吃 visibleKeys（「所见即所选」）
      if (this.selectMode && this.loaded && !this.loadFailed &&
        (this.segIndex === WS_SEG_FOLDER || this.segIndex === WS_SEG_TMP)) {
        SessionMultiselectActionBar({
          allSelected: isAllSelectedIn(this.visibleKeys(), this.selectedKeys),
          // 删除在途禁用删除键（删除中反馈）
          deleting: this.deleting,
          barBottom: this.bottomPad + 16,
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
    }
    .width('100%')
    .height('100%')
  }

  build() {
    PageShell({
      // 多选态标题换「已选 N 项」（@Prop 传导，勾选即刷）；titleBarBottomHidden 收起页顶两行
      // 带（多选态原键位让位，退出恢复）
      title: this.selectMode ? '已选 ' + this.selectedKeys.length + ' 项' : SETTING_TITLE_WORKSPACE,
      titleBarBottomHidden: this.selectMode,
      // 标题栏下方带两行承载；带高经 titleBarBottomHeight 传两行内容高
      titleBarBottom: (): void => {
        this.TopSegmentBand();
      },
      titleBarBottomInset: SEGMENT_BAR_BAND_TOP_INSET,
      titleBarBottomHeight: WORKSPACE_BAND_CONTENT_HEIGHT,
      // 标题栏双热区胶囊〔新建文件夹|⋯更多〕（2026-11-18 决明拍板：原官方菜单数组单「更多」键
      // 退役，官方数组传 null）；菜单经更多热区 openMenu 弹出，域不读 @State 由弹前重建 + 弹时
      // 快照免疫——置灰与动作取弹出时刻实况；keepStackTitle = true 保住主标题
      menuHds: null,
      titleBarStack: (): void => {
        this.TitleBarContent();
      },
      keepStackTitle: true,
      content: (): void => {
        this.Content();
      }
    })
      // 半模态挂载点（两面板共用；挂页面根 PageShell——判据：合法树内 / 根不随列表销毁 /
      // 可见性与触发键同组件位）。可见性 = $$this.sheetShow 双向；档位 [MEDIUM, LARGE]。
      // 交互式关闭经 onWillDismiss 内 action.dismiss() 放行后按形态路由各自收口（漏调则一切
      // 关闭不响应——真机根因一；关闭时内容形态恒不复位——真机根因二）
      .bindSheet($$this.sheetShow, this.SheetHost(), sheetPanelOptions(
        (action: DismissSheetAction): void => {
          // 放行交互式关闭（两面板零暂存恒放行）；将来若加关闭确认，dismiss() 须挪入分支按
          // 结果条件调用
          action.dismiss();
          if (this.sheetKind === 'move') {
            this.requestCloseMove();
          } else {
            this.requestCloseOverview();
          }
        }, [SheetSize.MEDIUM, SheetSize.LARGE], undefined,
        (): void => {
          this.onSheetGone();
        }))
  }
}
