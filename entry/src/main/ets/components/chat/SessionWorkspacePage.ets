// 会话工作区页：会话页「更多」菜单「会话工作区」项 push 的二级页——只显示**本会话**的工作区
// 文件。骨架照 SessionTracePage（空参守卫 + PageShell + departed 销毁守卫），动作壳照
// WorkspaceManagePage 收窄（无文件夹行、无 OCR）。
// · 数据口径：当前会话文件 = workspace_files 表 conversationId 追溯列命中件；**上传与挂载
//   复制件 conversationId 恒空串不进本页**；临时区文件不含；OCR 动作不带；帮助条目不加。
// · 快照语义：进页读一次，生成中新落库文件不自动出现——重进页或动作后 load() 刷新；移动到
//   其他文件夹仍在本页（move 不改 conversationId）。
// · 复用面（全部纯 import 零修改）：WorkspaceFileRowCard / WorkspaceBreadcrumbBar /
//   WorkspaceEmptyHint / WorkspaceFailCard / WorkspaceRowsSource + WorkspaceMovePanel +
//   纯函数族；不改 WorkspaceSessionView 本体。
// · 四动作壳与关闭-再开协调五法复制改编自 WorkspaceManagePage 同名方法（引用宿主私有成员，
//   非组件复用；共享抽取被 WorkspaceManagePage 越线阻断，技术债务登记观察项）。
// · 面包屑：单段「会话工作区」按拍板口径 disabled: true 全段置灰、不传 onJump（亮态可点
//   为待决 OQ，保守照设置页现形）。
// · 键纪律（坑44/80 家族）：LazyForEach 键 = workspaceEntryKey 单源，行卡全部可变成分在键
//   里；动作后 load() 整表重拉 + source.reload 承接刷新。
// · 半模态：页面根唯一 bindSheet 挂 WorkspaceMovePanel（坑64 姿势）；关闭链四件（$$ 双向 /
//   onWillDismiss 放行 / 不复位内容形态 / 关闭-再开协调）。
// · 只读页无保存动作 → 返回无参 pop 不挂 onPop（坑17 口径）。
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { PageShell } from '../../common/PageShell';
import { AttachmentBrief, openAttachmentViewer, openSystemPreview,
  shareAttachment } from '../../common/AttachmentUtil';
import { deleteWorkspaceFiles, isReady, moveWorkspaceEntryOp,
  queryWorkspaceFiles, renameWorkspaceEntryOp } from '../../common/store/ChatDb';
import { WorkspaceEntryOpOutcome } from '../../common/store/WorkspaceDbEntries';
import { workspaceFilesDir } from '../../common/store/WorkspaceDb';
import { WorkspaceFileRow, WORKSPACE_NAME_MAX_CHARS, WORKSPACE_ROWS_READ_MAX,
  deriveWorkspaceMoveTargets, deriveWorkspaceSessionFiles, isWorkspaceDirRow,
  joinDirName } from '../../common/WorkspaceUtil';
import { CARD_PANEL_WIDTH, CARD_SPACING, SEGMENT_BAR_BAND_TOP_INSET } from '../../common/Theme';
import { overlayMaterial } from '../../common/ImmersiveLevel';
import { searchBandContentTop } from '../SearchTopBand';
import { ConfirmDialog } from './ConfirmDialog';
import { InputDialog } from './InputDialog';
import { sheetPanelOptions } from './KimiSheetCommon';
import { WorkspaceListEntry, WorkspaceRowsSource, WorkspaceEntryAddr,
  WorkspaceEmptyHint, WorkspaceFailCard, WorkspaceFileRowCard,
  workspaceEntryAddr, workspaceEntryKey } from '../settings/WorkspaceListRows';
import { WORKSPACE_BAND_CONTENT_GAP, WORKSPACE_BREADCRUMB_HEIGHT,
  WorkspaceBreadcrumbBar, WorkspaceCrumbSeg } from '../settings/WorkspaceBreadcrumb';
import { WorkspaceMovePanel } from '../settings/WorkspaceMovePanel';
import { ROUTE_SESSION_WORKSPACE_PAGE } from '../../common/RouteNames';

const DOMAIN: number = 0xD5B3;
const TAG: string = 'SessionWorkspace';

// 面包屑段数组（恒单段；键三成分 text|target|isLast，段结构不变键不变）
const WORKSPACE_CRUMB_SEGS: WorkspaceCrumbSeg[] = [{
  key: '会话工作区||true', text: '会话工作区', target: '', isLast: true
}];

@Component
export struct SessionWorkspacePage {
  // 页面存活守卫：置位后本组件迟到异步回调不写状态、不碰 UI、不上行；写库等数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 路由栈（PageMap 注入；param = 会话 id，getParamByName 取——SessionTracePage 同款）
  pathStack: NavPathStack = new NavPathStack();
  private conversationId: string = '';
  // 首载完成标记与失败态（读取毫秒级不设加载指示；状态最小化）
  @State private loaded: boolean = false;
  @State private loadFailed: boolean = false;
  // 全表行集（含目录行与他会话件——派生侧内存过滤本会话；动作后整表重赋）
  @State private rows: WorkspaceFileRow[] = [];
  // 本会话扁平项（数据源与数组同点同步）
  @State private entries: WorkspaceListEntry[] = [];
  private source: WorkspaceRowsSource = new WorkspaceRowsSource();
  // 查询/删除在途闸（瞬态门闩，无 UI 消费面——普通成员，状态最小化红线）
  private loading: boolean = false;
  private deleting: boolean = false;
  // ── 移动半模态（照 WorkspaceManagePage 收窄单形态）：三件快照打开时现派生（面板每次打开
  //    重建，创建期取值恒为本次条目）+ 被移动条目 ──
  // 可见性单源挂 $$ 双向 + @Watch 兜底（框架收尾回写压回可见性时按开意图补开一次）
  @State @Watch('onSheetVisibleChanged') private sheetShow: boolean = false;
  @State private moveTargets: string[] = [];
  @State private moveAllDirs: string[] = [];
  @State private moveHiddenPrefix: string = '';
  private moveEntry: WorkspaceListEntry | null = null;
  // 移动在途闸（防面板内连点重入）
  private moving: boolean = false;
  // ── 关闭-再开协调（机制与官方依据单源 = KimiSheetCommon.sheetPanelOptions 第四参注释）：
  //    关闭后离场动效在途期内再点「移动」，直接写的可见性 true 会被框架收尾回写压回——
  //    在途期只记开意图，等动效结束再补开 ──
  private sheetClosing: boolean = false;
  private pendingOpen: boolean = false;
  // 面包屑（tmpSegs 覆盖源恒单段；currentDir 槽恒空占位——本页无文件夹派生源）
  @State private crumbSegs: WorkspaceCrumbSeg[] = [];
  @State private crumbDirPlaceholder: string = '';
  // 删除确认与改名输入弹窗（组件成员位构造——坑7；动态文案经 open* 方法重建）
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
    const params: Array<Object | null> =
      (this.pathStack.getParamByName(ROUTE_SESSION_WORKSPACE_PAGE) ?? []) as Array<Object | null>;
    const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
    this.conversationId = typeof last === 'string' ? last : '';
    if (this.conversationId === '') {
      this.getUIContext().getPromptAction().showToast({ message: '缺少会话参数' });
      this.pathStack.pop();
      return;
    }
    this.crumbSegs = WORKSPACE_CRUMB_SEGS;
    this.load();
  }

  aboutToDisappear(): void {
    this.departed = true;
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  // ── 装载与派生 ──
  // 首载与动作后刷新的单一路径：全表行集一次查回（上限为界），本会话过滤在派生侧；失败中文
  // toast + 失败态可重试（P0-1 不静默）。不查 queryWorkspaceTotal（无数据总览面）。
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
    queryWorkspaceFiles(WORKSPACE_ROWS_READ_MAX)
      .then((rows: WorkspaceFileRow[]): void => {
        if (this.departed) {
          return;
        }
        this.rows = rows;
        this.deriveEntries();
        this.loaded = true;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.loadFailed = true;
        const err: BusinessError = e as BusinessError;
        hilog.error(DOMAIN, TAG, '会话工作区查询失败：code %{public}d %{public}s',
          typeof err.code === 'number' ? err.code : -1, (e as Error).message);
        this.showToast('工作区列表加载失败，请重试（code ' + err.code + '）');
      })
      .finally((): void => {
        this.loading = false;
      });
  }

  // 本会话文件行派生：deriveWorkspaceSessionFiles 单源（conversationId 命中 + 目录行排除 +
  // updatedAt 降序）；absPath 运行时派生（库内相对路径红线不变）；键 = workspaceEntryKey 单源
  private deriveEntries(): void {
    const filesDir: string = workspaceFilesDir();
    const entries: WorkspaceListEntry[] = [];
    for (const row of deriveWorkspaceSessionFiles(this.rows, this.conversationId)) {
      const entry: WorkspaceListEntry = { key: '', kind: 'file', row: row,
        absPath: filesDir + '/' + row.localPath, dirName: '', dirPath: '', fileCount: 0 };
      entry.key = workspaceEntryKey(entry);
      entries.push(entry);
    }
    this.entries = entries;
    this.source.reload(entries);
  }

  // 内容区顶让位（算式单源 = searchBandContentTop，第三参传条体高 40）
  private contentTop(): number {
    return Math.max(searchBandContentTop(this.topPad, WORKSPACE_BAND_CONTENT_GAP,
      WORKSPACE_BREADCRUMB_HEIGHT), 0);
  }

  // ── 预览（行点击，scope = 本会话集——图片滑切只滑本会话）：doc 走系统预览窗；图片按集
  //    滑切；其余单件进查看器 ──
  private openPreview(entry: WorkspaceListEntry, scope: WorkspaceListEntry[]): void {
    const row: WorkspaceFileRow | null = entry.row;
    if (row === null) {
      return;
    }
    if (!fs.accessSync(entry.absPath)) {
      // 「行在文件不在」：现检 + 中文提示（行不删——附件域拍板先例）
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

  // ── 分享（系统面板自带另存为——现行惯例）──
  private shareItem(entry: WorkspaceListEntry): void {
    if (!fs.accessSync(entry.absPath)) {
      this.showToast('文件已不在本机');
      return;
    }
    shareAttachment(this.getUIContext(), this.briefOf(entry));
  }

  // ── 删除（仅文件支——本页无文件夹行；确认弹窗 → 按 id 精确删 → load 刷新）──
  private openDeleteConfirm(entry: WorkspaceListEntry): void {
    if (this.deleting) {
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
      hilog.error(DOMAIN, TAG, '会话工作区文件删除失败：code %{public}d %{public}s',
        typeof err.code === 'number' ? err.code : -1, (e as Error).message);
      this.showToast('删除失败，请重试（code ' + err.code + '）');
    } finally {
      this.deleting = false;
    }
  }

  // ── 改名（folders rename 委托口——重名拒/未命中/二义拒原样透传，不做目录重名预检）──
  private openRenameDialog(entry: WorkspaceListEntry): void {
    const currentName: string = entry.row !== null ? entry.row.name : '';
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
    // 定位二元组单源（workspaceEntryAddr）
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
      hilog.error(DOMAIN, TAG, '会话工作区重命名失败：code %{public}d %{public}s',
        typeof err.code === 'number' ? err.code : -1, (e as Error).message);
      this.showToast('重命名失败，请重试（code ' + err.code + '）');
    }
  }

  // ── 移动（folders move 委托口）：可落点集与全部目录集打开时现派生（含他会话目录——移动
  //    是全工作区操作）；文件移动不隐藏子树（hiddenPrefix 恒 ''）──
  private openMoveSheet(entry: WorkspaceListEntry): void {
    const addr: WorkspaceEntryAddr = workspaceEntryAddr(entry);
    const targets: string[] = deriveWorkspaceMoveTargets(this.rows, addr.dir, addr.name);
    if (targets.length === 0) {
      this.noMoveTarget();
      return;
    }
    const allDirs: string[] = [];
    for (const row of this.rows) {
      if (isWorkspaceDirRow(row)) {
        allDirs.push(joinDirName(row.dir, row.name));
      }
    }
    this.moveEntry = entry;
    this.moveTargets = targets;
    this.moveAllDirs = allDirs;
    this.moveHiddenPrefix = '';
    this.requestOpen();
  }

  // 无可移动目标指引（「移动」项在场、无处可移时出指引——项不摘除）
  private noMoveTarget(): void {
    this.showToast('没有可移动到的其他文件夹');
  }

  // ── 关闭-再开协调（机制见字段注释）──
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

  // 离场动效结束（sheetPanelOptions 第四参——d.ts：动画结束后回调）：清在途位 + 按开意图补开
  private onSheetGone(): void {
    this.sheetClosing = false;
    if (!this.sheetShow) {
      this.applyOpen();
    }
  }

  // 可见性变化兜底：框架 `$$` 收尾回写把可见性压回 false 时按开意图补一次；用户关闭必经
  // requestCloseMove（先清开意图再写 false），不会误触本支
  private onSheetVisibleChanged(): void {
    if (!this.sheetShow) {
      this.applyOpen();
    }
  }

  // 面板关闭单源（标题栏 xmark 与手势 onWillDismiss 两路同调——半模态规范新码硬约束；
  // 关闭 = sheetShow 复位（$$ 双向可见性），内容快照恒不复位）
  private requestCloseMove(): void {
    this.pendingOpen = false;
    this.sheetClosing = true;
    this.sheetShow = false;
  }

  // 面板点选执行（点选即落库无二次确认；成功关面板 + toast + 重载；失败 toast 后保留面板
  // 可重试——P0-1 不静默；在途闸防连点）
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
      hilog.error(DOMAIN, TAG, '会话工作区移动失败：code %{public}d %{public}s',
        typeof err.code === 'number' ? err.code : -1, (e as Error).message);
      this.showToast('移动失败，请重试（code ' + err.code + '）');
    } finally {
      this.moving = false;
    }
  }

  // ── 条体挂点 ──
  // 标题栏下方带（水平居中 + 带内下移 inset + 整带命中透传——MountBrowsePage 同构）
  @Builder
  TopCrumbBand() {
    Row() {
      Column() {
        this.CrumbBar()
      }
      .width(CARD_PANEL_WIDTH)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Top)
    .padding({ top: SEGMENT_BAR_BAND_TOP_INSET })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  // 条体本体（currentDir 占位 + tmpSegs 覆盖源；拍板口径见文件头）
  @Builder
  CrumbBar() {
    WorkspaceBreadcrumbBar({
      currentDir: $crumbDirPlaceholder,
      tmpSegs: $crumbSegs,
      disabled: true
    })
  }

  // 本会话文件列表（行卡 width 100% ⇒ 水平 padding 16 收边；让位走官方 offset 轨——带内
  // 面包屑在生效区，内容自其背后滚过；键 = workspaceEntryKey）
  @Builder
  FileList() {
    List({ space: CARD_SPACING }) {
      LazyForEach(this.source, (item: WorkspaceListEntry): void => {
        ListItem() {
          WorkspaceFileRowCard({
            entry: item,
            showDir: true,
            onPreview: (entry: WorkspaceListEntry): void => {
              this.openPreview(entry, this.entries);
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
        }
      }, (item: WorkspaceListEntry): string => item.key)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16 })
    .contentStartOffset(this.contentTop())
    .contentEndOffset(this.bottomPad + 16)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
    .clip(false)
  }

  // 空态（口径边界：禁写「会话的全部文件」、禁暗示会话专属目录——原因见文件头数据口径）
  @Builder
  EmptyState() {
    Scroll() {
      Column() {
        WorkspaceEmptyHint({ main: '本会话还没有工作区文件', sub: '助手在本会话保存的文件会显示这里' })
          .width(CARD_PANEL_WIDTH)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: this.contentTop(), bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .clip(false)
  }

  // 失败态（单卡可重试——重试链 = load 单一路径）
  @Builder
  FailState() {
    List() {
      ListItem() {
        WorkspaceFailCard({
          onRetry: (): void => {
            this.load();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16 })
    .contentStartOffset(this.contentTop())
    .contentEndOffset(this.bottomPad + 16)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
    .clip(false)
  }

  @Builder
  Content() {
    Column() {
      if (this.loadFailed) {
        this.FailState()
      } else if (!this.loaded) {
        // 装载中：空白（读取毫秒级，不设加载指示）
        Column()
          .width('100%')
          .layoutWeight(1)
      } else if (this.entries.length === 0) {
        this.EmptyState()
      } else {
        this.FileList()
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
  }

  // 移动半模态内容（坑51：bindSheet builder 位挂组件内 @Builder；三件快照在 openMoveSheet
  // 现派生；落点/关闭意图全在本页编排收口）
  @Builder
  SheetHost() {
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
  }

  build() {
    PageShell({
      title: '会话工作区',
      // 页顶条体带（经标题栏下方带承载）：单行档内容高 = 条体高 40（带高 = inset 8 + 40 = 48）
      titleBarBottom: (): void => {
        this.TopCrumbBand();
      },
      titleBarBottomInset: SEGMENT_BAR_BAND_TOP_INSET,
      titleBarBottomHeight: WORKSPACE_BREADCRUMB_HEIGHT,
      content: (): void => {
        this.Content();
      }
    })
      // 半模态单面板（页面根唯一挂载点，坑64 姿势；关闭链四件见文件头，onWillDismiss 路由到
      // requestCloseMove 单入口；档位与 WorkspaceManagePage 在产实参同形；第四参 = 动效结束信号）
      .bindSheet($$this.sheetShow, this.SheetHost(), sheetPanelOptions(
        (action: DismissSheetAction): void => {
          action.dismiss();
          this.requestCloseMove();
        }, [SheetSize.MEDIUM, SheetSize.LARGE], undefined,
        (): void => {
          this.onSheetGone();
        }))
  }
}
