// 「文件夹挂载」浏览页：管理页点正常态挂载卡进入，浏览该文件夹——面包屑（根 = 挂载名，逐段 =
// 挂载内相对路径，可横滑、点中间段直达该层、尾段不可点）+ 条目列表（文件夹在前、名称升序；行 =
// 图标 + 名称 + 副行 + 行尾「更多」键）+ 预览三路（图片进应用内查看器并支持本层滑切 / 文本进
// 应用内文本预览 / 文档与其余拷缓存后跳系统预览窗）。
// · 动作面（原「只读」口径已作废）：行尾「更多」菜单 = 文件行「复制到工作区」（源只读、写沙箱、
//   可逆）+「删除」；文件夹行「在文件管理中打开」（openLink 走 filemanager://openDirectory，
//   官方 FAQ faqs-ability-116）+「删除」（File Manager Service Kit 删到系统回收站、可恢复）。
//   只读挂载删除项置灰 + 项内指引小字「需读写模式」，复制项照常可用。重命名 / 移动 / 编辑不做
//   ——RENAME 类持久授权位系统不授（见 MountUtil 文件头模式位纪律），工具面亦无此类件。AI 侧
//   mount_delete 与本页共用回收站共享件 common/MountTrash.ets，本页只消费。
// · 数据链：进页 checkPersistentPermission（API 17 起免权限版）——假即落页内失效说明卡；真则
//   activatePermission **await**（官方 FAQ：未等完成即读文件报无权限；页面寿命内一次）→ 列目录
//   + 逐条 stat。★ 不复用工具面的进程级激活缓存 Set（activatedGrantKeys 是 AI 工具面懒激活位）
//   ——两域各自成对，避免共享态耦合。
// · 路径安全：进层只由列表点击驱动（segs 段名全来自目录列表真实名），无自由文本路径输入；
//   拼接前过 mountRelPathNormalize + 根路径经 mountRootPathFromUri（单源在 ToolMount）。
// · 时间口径（坑32）：fs.stat 的 mtime 单位是**秒**，展示前 ×1000；格式化直引工作区单源
//   （formatWorkspaceSize / formatWorkspaceTime），本页不新写。
// · 长列表选型（《规范-列表卡片与组卡》§4.6.1）：条数随用户目录增长（硬顶 MOUNT_BROWSE_MAX_ROWS）
//   ⇒ List + Repeat.virtualScroll（V2 渲染件 MountBrowseList，V1 壳经 UIUtils.enableV2Compatibility
//   传值）。滚动复位由壳侧在数据赋值后直调 scroller.scrollEdge(Edge.Top)——0 位对新旧内容同值。
// · 观感与滚动（真机反馈修复，与工作区页逐件同构）：面包屑条体 = 共用件 WorkspaceBreadcrumbBar，
//   经 PageShell.titleBarBottom 挂标题栏下方带（titleBarBottomHeight = WORKSPACE_BREADCRUMB_HEIGHT
//   40，带高 8 + 40 = 48），入沉浸光感生效区才有材质。列表视口铺满整页、让位走官方 offset 轨
//   （contentStartOffset = 带底 + 间距、contentEndOffset = 底部留白），内容自标题栏与条体背后
//   滚过，上下两端同表现。
// · 条体数据面两槽：tmpSegs = 本页段数组（mountName + segs 派生，WorkspaceCrumbSeg 同形）；
//   currentDir = 恒定占位（本页无文件夹派生源）。滚尾机制随条体内部 @Watch 自带。带收起两态
//   （loading / blocked）：titleBarBottomHidden 收起、让位同步归 topPad。
// · 面包屑「＞」缺失根因（真机实锤）= 段键漏「尾段标记」成分：进层那一步只有 isLast 变、键不变
//   ⇒ ForEach 复用旧节点不重建，段间 ＞ 与尾段加粗永不出现。syncCrumb 两处键 = 文本|跳转目标|
//   尾段标记，与条体件文件夹派生同契约（坑44/坑80 家族）；断言守「段键含尾段标记」零回流。
// · 行点击路径基准（静默错值面）：进层/跳层装载异步（逐条 stat，大目录窗口可达秒级）——窗口内
//   旧列表仍在屏，按 this.segs 算会落到新层同名件。修法 = rowsRelPath 与 rows **同拍**赋值，
//   行动作一律按该行所见层算（absPathOf / rowsSegs 消费之）。
// · 复制到工作区的体积口径：列表快照 row.size 会过期 ⇒ 拷贝前 fs.statSync 现读（工具面
//   mount_copy_out 同款；兼作存在性检查，失败如实提示）。
// · 预览取数链（实读 AttachmentViewer / AttachmentImagePage）：查看器只消费 AttachmentBrief
//   五字段、不绑 attachments 目录、不查 DB ⇒ 挂载文件绝对路径可直接进查看器，图片与文本两路
//   不必拷缓存；doc / other 两路拷 cacheDir 再跳系统预览（Preview Kit 转授权约束未文档化，不赌
//   直传）。真机仍须复验查看器里持久授权路径的可读性（BLOCKED「M3 浏览页 真机清单」）。
// · 返回：删除等动作不改挂载行与管理页回显 ⇒ 仍无参 pop、**不挂 onPop**（坑17 触发条件不成立：
//   子页 pop 必带 result 才需要）。
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs, fileShare } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UIUtils } from '@kit.ArkUI';
import { PageShell } from '../../common/PageShell';
import { isReady, mountCopyToWorkspace, queryFolderMounts } from '../../common/store/ChatDb';
import { FolderMountRow } from '../../common/store/MountDb';
import {
  FILE_MANAGER_OPEN_DIRECTORY_LINK,
  MOUNT_BROWSE_MAX_ROWS,
  MOUNT_KIND_IMAGE,
  MOUNT_KIND_TEXT,
  MOUNT_MODE_READ_WRITE,
  MountBrowseParam,
  MountBrowseRow,
  compareMountBrowseRows,
  joinMountPath,
  mountChildUri,
  mountKindOf,
  mountModeMask,
  mountRelPathNormalize,
  mountRelPathRejectReason
} from '../../common/MountUtil';
import { mountRootPathFromUri } from '../../common/providers/ToolMount';
import { MOUNT_TRASH_CODE_MISSING, MountTrashOutcome, deleteMountEntryToTrash }
  from '../../common/MountTrash';
import { launchExternalLink } from '../../common/ExternalLink';
import { WORKSPACE_SOURCE_USER } from '../../common/WorkspaceUtil';
import { workspaceOverwriteNote } from '../../common/WorkspaceReply';
import { AttachmentBrief, openAttachmentViewer, openSystemPreview } from '../../common/AttachmentUtil';
import { CARD_PANEL_WIDTH, SEGMENT_BAR_BAND_TOP_INSET, cardDescColor } from '../../common/Theme';
import { InfoCard } from '../InfoCard';
import { IMMERSIVE_LEVEL_KEY, overlayMaterial } from '../../common/ImmersiveLevel';
import { ROUTE_MOUNT_BROWSE_PAGE } from '../../common/RouteNames';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import { MountBrowseList } from './MountBrowseRows';
import { MountRowMenuCallbacks, MountRowMenuHost } from './MountRowMenu';
import { WORKSPACE_BAND_CONTENT_GAP, WORKSPACE_BREADCRUMB_HEIGHT, WorkspaceBreadcrumbBar,
  WorkspaceCrumbSeg } from './WorkspaceBreadcrumb';
import { searchBandContentTop } from '../SearchTopBand';

const DOMAIN: number = 0xD5B0;
const TAG: string = 'MountBrowsePage';

// 页态（loading = 进页装载中；ok = 可浏览；blocked = 失效/读不到，出说明卡）
const BROWSER_STATE_LOADING: string = 'loading';
const BROWSER_STATE_OK: string = 'ok';
const BROWSER_STATE_BLOCKED: string = 'blocked';

// 失效说明卡文案（两因分派：授权探测为假 / 根目录读不到但授权仍在——文案如实分指，不混为一条）
const BLOCKED_GRANT_TEXT: string = '授权已失效。文件夹可能被改名或移动，请到管理页重新授权。';
const BLOCKED_LIST_TEXT: string = '读不到这个文件夹，它可能已被移动或删除。请到管理页检查。';

// 文档类预览缓存目录（cacheDir 下；同名覆盖，首次使用时清旧——不动 EntryAbility 的启动清扫）
const MOUNT_PREVIEW_DIR: string = 'mountPreview';

// 进层深度兜底（挂载内真实目录层级；防病态深链把段数组撑到无界——正常使用到不了）
const MOUNT_BROWSE_MAX_DEPTH: number = 32;

// 行菜单首建占位行（节点 init 需入参载体；弹出前必 rebuild 实参——占位从不渲染/从不派发动作）
const EMPTY_BROWSE_ROW: MountBrowseRow = { name: '', isDir: false, size: 0, mtimeMs: 0 };

@Component
export struct MountBrowsePage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI；写库等数据层意图照常完成
  private departed: boolean = false;
  // 顶部/底部留白（vp，PageMap 传入）
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 路由栈（取参 + 预览二级页 push；无保存类动作，返回归官方返回链）
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('appColorMode') appColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  // 挂载名（标题与面包屑根段；进页查行后赋值）
  @State private mountName: string = '';
  @State private state: string = BROWSER_STATE_LOADING;
  @State private blockedText: string = '';
  // 当前层段数组（空数组 = 根目录；段名全来自目录列表真实名）
  @State private segs: string[] = [];
  @State private rows: MountBrowseRow[] = [];
  // 尾行提示（截断 / 属性读取失败计数；'' = 无。两因互斥，见 loadDir 注释）
  @State private tailNotice: string = '';
  // 复制到工作区在途位（行尾「更多」键置灰；同一时刻只跑一件——轻量串行，不逐行记在途）
  @State private copying: boolean = false;
  // 条体覆盖源（tmpSegs 槽；mountName + segs 派生，单写口 = syncCrumb——赋值即触发条体 @Watch 滚尾）
  @State private crumbSegs: WorkspaceCrumbSeg[] = [];
  // 条体 currentDir 槽占位（本页无文件夹派生源，本值从不参与渲染）
  @State private crumbDirPlaceholder: string = '';

  // 本页挂载行（进页查行一次；只读快照——本页不改行）
  private row: FolderMountRow | undefined = undefined;
  // 挂载根转换路径（进页一次算好；转换失败落 blocked）
  private rootPath: string = '';
  // 行所属层相对路径（loadDir 与 rows 同拍赋值；行动作一律按该行所见层算路径与进层——装载窗口
  // 内旧列表仍在屏，按当前 segs 算会落到新层同名件。根层 = ''）
  private rowsRelPath: string = '';
  // 列表滚动器（V2 渲染件消费；复位由壳侧直调——见文件头「滚动复位」注）
  private listScroller: Scroller = new Scroller();
  // 列目录在途闸与合并重载位（进层连点防重入；在途期再点记意图，收尾时补跑一次）
  private loadingDir: boolean = false;
  private pendingReload: boolean = false;
  // 文档预览缓存目录已就绪（首次使用清旧；页面实例内一次）
  private previewDirReady: boolean = false;
  // 删除在途位（复制与删除互相避让，行尾「更多」键同置灰；轻量串行不逐行记在途）
  @State private deleting: boolean = false;
  // 沉浸光感档位（行菜单材质随总档——openMenu 宿主弹出时解析，@StorageProp 自订阅）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 行菜单宿主（AppMenuHost 薄壳——节点 init/dispose 成对，域件见 MountRowMenu）
  private rowMenuHost: MountRowMenuHost = new MountRowMenuHost();
  // 删除确认弹窗（构造在组件成员位——坑7；动态文案经 openDeleteConfirm 重建，管理页同款）
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

  aboutToAppear(): void {
    // 行菜单节点首建（getUIContext 需组件就绪故不在构造期）；初参为空行占位，弹出前必 rebuild 实参
    this.rowMenuHost.init(this.getUIContext(), this.rowCallbacks(EMPTY_BROWSE_ROW, false));
    this.init();
  }

  aboutToDisappear(): void {
    this.departed = true;
    this.rowMenuHost.dispose(); // 与 init 成对（ComponentContent 不 dispose 泄漏——SDK d.ts NOTE）
  }

  // ── 进页装载（取参 → 查行 → 授权探测 → 激活 → 列根目录）──
  private async init(): Promise<void> {
    const params: Array<MountBrowseParam> =
      this.pathStack.getParamByName(ROUTE_MOUNT_BROWSE_PAGE) as Array<MountBrowseParam>;
    if (params.length === 0) {
      // 理论不可达（开页方恒带参）——不给白屏，如实提示后可返回（官方返回键在位）
      hilog.warn(DOMAIN, TAG, '浏览页缺少路由参数');
      this.blockedText = '没有找到要浏览的挂载，请返回重试。';
      this.state = BROWSER_STATE_BLOCKED;
      return;
    }
    const mountId: number = params[params.length - 1].mountId;
    if (!isReady()) {
      this.showToast('数据库尚未就绪，请稍后再试');
      return;
    }
    let mounts: FolderMountRow[];
    try {
      mounts = await queryFolderMounts();
      if (this.departed) {
        return;
      }
    } catch (e) {
      if (this.departed) {
        return;
      }
      hilog.error(DOMAIN, TAG, '挂载清单读取失败：%{public}s', (e as Error).message);
      this.showToast('加载挂载信息失败，请重试');
      return;
    }
    for (const candidate of mounts) {
      if (candidate.id === mountId) {
        this.row = candidate;
        break;
      }
    }
    if (this.row === undefined) {
      // 挂载已被移除（并发窗口：管理页移除后浏览页仍在栈上）——如实提示并返回
      this.showToast('挂载已不存在');
      this.pathStack.pop();
      return;
    }
    this.mountName = this.row.name;
    this.syncCrumb();
    if (!(await this.checkGrant())) {
      if (this.departed) {
        return;
      }
      this.blockedText = BLOCKED_GRANT_TEXT;
      this.state = BROWSER_STATE_BLOCKED;
      return;
    }
    try {
      // 按需激活（官方「每次启动需按需激活、不要盲目全量激活」）——必须 await 后再动文件
      const policy: fileShare.PolicyInfo = { uri: this.row.dirUri,
        operationMode: mountModeMask(this.row.mode) };
      await fileShare.activatePermission([policy]);
      if (this.departed) {
        return;
      }
    } catch (e) {
      if (this.departed) {
        return;
      }
      hilog.error(DOMAIN, TAG, '浏览页激活授权失败：%{public}s', (e as Error).message);
      this.blockedText = BLOCKED_GRANT_TEXT;
      this.state = BROWSER_STATE_BLOCKED;
      return;
    }
    try {
      this.rootPath = mountRootPathFromUri(this.row.dirUri);
    } catch (e) {
      if (this.departed) {
        return;
      }
      hilog.error(DOMAIN, TAG, '挂载根路径转换失败：%{public}s', (e as Error).message);
      this.blockedText = BLOCKED_LIST_TEXT;
      this.state = BROWSER_STATE_BLOCKED;
      return;
    }
    await this.loadDir();
  }

  // 授权存活探测（免权限版；异常按未授权呈报并留痕——探测失败不给假绿，照管理页 checkGrant）
  private async checkGrant(): Promise<boolean> {
    const row: FolderMountRow | undefined = this.row;
    if (row === undefined) {
      return false;
    }
    try {
      const policy: fileShare.PolicyInfo = { uri: row.dirUri,
        operationMode: mountModeMask(row.mode) };
      const result: boolean[] = await fileShare.checkPersistentPermission([policy]);
      return result.length > 0 && result[0];
    } catch (e) {
      hilog.error(DOMAIN, TAG, '持久授权探测异常：%{public}s', (e as Error).message);
      return false;
    }
  }

  // ── 列目录与排序（当前层；stat 失败的条目跳过并计数，尾行如实呈报）──
  private async loadDir(): Promise<void> {
    if (this.loadingDir) {
      this.pendingReload = true; // 在途期再进层/回层：收尾补跑一次（不静默丢意图）
      return;
    }
    if (this.row === undefined) {
      return;
    }
    this.loadingDir = true;
    const relPath: string = this.segs.join('/');
    // 段名恒来自列表点击（真实名），过闸函数只为兜底（无自由文本输入面）
    const reject: string = mountRelPathRejectReason(relPath);
    if (reject !== '') {
      hilog.error(DOMAIN, TAG, '浏览路径被闸拒绝：%{public}s', reject);
      this.loadingDir = false;
      this.blockedText = BLOCKED_LIST_TEXT;
      this.state = BROWSER_STATE_BLOCKED;
      return;
    }
    const dirPath: string = joinMountPath(this.rootPath, mountRelPathNormalize(relPath));
    try {
      // 异步面（官方 Promise 版）——大目录逐条 stat 期间让出 UI 线程，避免一次性同步阻塞
      const names: string[] = await fs.listFile(dirPath);
      if (this.departed) {
        return;
      }
      const listed: MountBrowseRow[] = [];
      let unreadable: number = 0;
      for (const name of names) {
        try {
          const st: fs.Stat = await fs.stat(joinMountPath(dirPath, name));
          // 坑32：Stat.mtime 单位是秒，×1000 转毫秒与全仓时间戳口径一致
          listed.push({ name: name, isDir: st.isDirectory(), size: st.size,
            mtimeMs: st.mtime * 1000 });
        } catch (e) {
          unreadable++; // 单条属性读取失败不阻断整页（计数进尾行，不静默）
        }
      }
      listed.sort(compareMountBrowseRows);
      const truncated: boolean = listed.length > MOUNT_BROWSE_MAX_ROWS;
      this.rows = truncated ? listed.slice(0, MOUNT_BROWSE_MAX_ROWS) : listed;
      this.rowsRelPath = relPath; // 与 rows 同拍（行动作路径基准，见成员注释）
      // 尾行两因互斥（截断优先——截断句已含「仅显示前 N 条」，两因并报反而冗长）
      this.tailNotice = truncated ?
        '条目较多，仅显示前 ' + MOUNT_BROWSE_MAX_ROWS + ' 条' :
        (unreadable > 0 ? '有 ' + unreadable + ' 个条目无法读取' : '');
      this.state = BROWSER_STATE_OK;
      // 进层/回层回顶（Edge.Top 的 0 位对新旧内容同值）；条体滚尾由 syncCrumb 赋值触发，不在此管
      this.resetListToTop();
    } catch (e) {
      await this.onListFailed(e);
    } finally {
      this.loadingDir = false;
      if (this.pendingReload) {
        this.pendingReload = false;
        await this.loadDir();
      }
    }
  }

  // 列表回顶（Scroller 未绑定/竞态时滚动 API 可抛 BusinessError，静默停在原位——坑63 家族口径）
  private resetListToTop(): void {
    try {
      this.listScroller.scrollEdge(Edge.Top);
    } catch (e) {
      // 静默：内容仍可手动滑回
    }
  }

  // 列目录失败分流：授权检测为假 = 失效说明卡；授权仍在 = 目标多已移动/删除——非根层回退一层
  // 并如实提示，根层落说明卡。不静默
  private async onListFailed(e: Object): Promise<void> {
    const err: BusinessError = e as BusinessError;
    hilog.error(DOMAIN, TAG, '列目录失败：code %{public}d %{public}s',
      typeof err.code === 'number' ? err.code : -1, (e as Error).message);
    if (!(await this.checkGrant())) {
      if (this.departed) {
        return;
      }
      this.blockedText = BLOCKED_GRANT_TEXT;
      this.state = BROWSER_STATE_BLOCKED;
      return;
    }
    if (this.departed) {
      return;
    }
    if (this.segs.length > 0) {
      this.showToast('读不到这个文件夹，可能已被移动或删除');
      this.segs = this.segs.slice(0, this.segs.length - 1);
      this.syncCrumb();
      await this.loadDir();
      return;
    }
    this.blockedText = BLOCKED_LIST_TEXT;
    this.state = BROWSER_STATE_BLOCKED;
  }

  // ── 行点击分派：文件夹进层；文件按类型三路预览 ──
  private enterFolder(row: MountBrowseRow): void {
    // 进层基准 = 行所属层（装载窗口内点旧列表时 this.segs 可能已进新层——见 rowsRelPath 注释）
    const base: string[] = this.rowsSegs();
    if (base.length >= MOUNT_BROWSE_MAX_DEPTH) {
      this.showToast('这个文件夹的层级太深了');
      return;
    }
    const next: string[] = [];
    for (const seg of base) {
      next.push(seg);
    }
    next.push(row.name);
    this.segs = next;
    this.syncCrumb();
    this.loadDir();
  }

  private openFile(row: MountBrowseRow): void {
    const kind: string = mountKindOf(row.name);
    if (kind === MOUNT_KIND_IMAGE) {
      // 组本层图片集（滑切集合 = 当前层全部图片，序同列表），起始下标 = 本行在集合中的位次
      const briefs: AttachmentBrief[] = [];
      let index: number = -1;
      for (const it of this.rows) {
        if (it.isDir || mountKindOf(it.name) !== MOUNT_KIND_IMAGE) {
          continue;
        }
        if (it.name === row.name) {
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
    if (kind === MOUNT_KIND_TEXT) {
      // 应用内文本预览（查看器按首件 kind 判模式：非 image 即文本；截断上限在查看器内）
      openAttachmentViewer(this.pathStack, [this.briefOf(row)], 0, true);
      return;
    }
    this.openBySystemPreview(row);
  }

  // 文档与其余类型：拷 cacheDir 再跳系统预览窗（Preview Kit 要求调用方有 uri 转授权能力，持久
  // 授权形态未文档化——不赌直传；先例 = 附件域 openSystemPreview）
  private async openBySystemPreview(row: MountBrowseRow): Promise<void> {
    const ctx: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (ctx === undefined) {
      hilog.warn(DOMAIN, TAG, '系统预览未执行：host context 不可达');
      this.showToast('预览失败，请重试');
      return;
    }
    const dir: string = ctx.cacheDir + '/' + MOUNT_PREVIEW_DIR;
    try {
      fs.mkdirSync(dir, true);
    } catch (e) {
      if ((e as BusinessError).code !== 13900015) {
        hilog.error(DOMAIN, TAG, '预览缓存目录创建失败：%{public}s', (e as Error).message);
        this.showToast('预览失败，请重试');
        return;
      }
    }
    if (!this.previewDirReady) {
      this.previewDirReady = true;
      this.clearPreviewDir(dir);
    }
    const dest: string = dir + '/' + row.name;
    try {
      fs.copyFileSync(this.absPathOf(row), dest);
    } catch (e) {
      hilog.error(DOMAIN, TAG, '预览副本拷贝失败：%{public}s', (e as Error).message);
      this.showToast('打开预览失败，请重试');
      return;
    }
    openSystemPreview(this.getUIContext(), row.name, dest);
  }

  // 预览缓存清旧（首次使用一次；单文件失败跳过——有界自愈，照 sweepAttachDir 口径）
  private clearPreviewDir(dir: string): void {
    try {
      const names: string[] = fs.listFileSync(dir);
      for (const name of names) {
        try {
          fs.unlinkSync(dir + '/' + name);
        } catch (e) {
          // 单文件失败跳过（下次进页再清）
        }
      }
    } catch (e) {
      // 目录不存在 = 干净（目标状态）
    }
  }

  // 行绝对路径（运行时路径 = 根转换路径 + **行所属层**相对路径 + 名；本页唯一拼接口）。
  // 基准恒取 rowsRelPath、非 this.segs——装载窗口内二者可以不同层（见成员注释）
  private absPathOf(row: MountBrowseRow): string {
    return joinMountPath(joinMountPath(this.rootPath, this.rowsRelPath), row.name);
  }

  // 行层段数组（rowsRelPath → 段数组；进层动作的基准，同上勿改用 this.segs）
  private rowsSegs(): string[] {
    return this.rowsRelPath === '' ? [] : this.rowsRelPath.split('/');
  }

  private briefOf(row: MountBrowseRow): AttachmentBrief {
    const absPath: string = this.absPathOf(row);
    return { id: absPath, name: row.name, kind: mountKindOf(row.name), size: row.size,
      absPath: absPath };
  }

  // ── 复制到工作区（复用 M2 落库壳：零确认——源只读、写沙箱、可逆；归属两列恒空串 +
  //    source='user'，与工作区管理页上传同形；入口 = 行尾「更多」菜单文件行首项）──
  private async onCopyToWorkspace(row: MountBrowseRow): Promise<void> {
    if (this.copying || this.deleting) {
      return;
    }
    const absPath: string = this.absPathOf(row);
    let sizeBytes: number = row.size;
    try {
      // 体积闸与落库记账按拷贝时刻真实大小现读（列表快照会过期；工具面 mount_copy_out 同款，
      // 兼作存在性检查，失败如实提示不静默）
      sizeBytes = fs.statSync(absPath).size;
    } catch (e) {
      this.showToast('文件已不在这个文件夹里');
      return;
    }
    this.copying = true;
    try {
      const outcome = await mountCopyToWorkspace(absPath, row.name, sizeBytes,
        '', '', '', WORKSPACE_SOURCE_USER);
      if (this.departed) {
        return;
      }
      if (!outcome.ok) {
        // 失败态文案单源在落库壳（超 30MB / 容量不足 / 位置冲突等，全中文）——原样透传
        this.showToast(outcome.errorText);
        return;
      }
      const note: string = workspaceOverwriteNote(outcome.overwriteKind ?? '');
      this.showToast('已把「' + outcome.displayName + '」复制到文件工作区。' + note);
    } catch (e) {
      if (this.departed) {
        return;
      }
      hilog.error(DOMAIN, TAG, '复制到工作区失败：%{public}s', (e as Error).message);
      this.showToast('复制失败，请重试');
    } finally {
      this.copying = false;
    }
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  // ── 行菜单与复制 / 删除 / 跳转 ──
  // 行尾「更多」键上行分派：菜单内容与动作按点击当刻行数据生成；readWrite 取自挂载行快照
  // ——只读挂载删除项在域件内置灰（不接收点击），复制项不受只读影响
  private onRowMore(row: MountBrowseRow): void {
    if (this.deleting || this.copying) {
      return;
    }
    const mountRow: FolderMountRow | undefined = this.row;
    const readWrite: boolean = mountRow !== undefined && mountRow.mode === MOUNT_MODE_READ_WRITE;
    this.rowMenuHost.open(this.getUIContext(), this.rowCallbacks(row, readWrite),
      this.immersiveLevel);
  }

  // 菜单回调装配（init 占位与 open 实参同一装配口——锚点 id 在域件按行键拼接）
  private rowCallbacks(row: MountBrowseRow, readWrite: boolean): MountRowMenuCallbacks {
    return {
      row: row,
      readWrite: readWrite,
      onCopyToWorkspace: (r: MountBrowseRow): void => {
        this.onCopyToWorkspace(r);
      },
      onOpenInFileManager: (r: MountBrowseRow): void => {
        this.openInFileManager(r);
      },
      onDelete: (r: MountBrowseRow): void => {
        this.openDeleteConfirm(r);
      }
    };
  }

  // 行在当前层内的相对路径（删除与跳转共用目标基准，恒取 rowsRelPath；normalize 为兜底）
  private rowChildRelPath(row: MountBrowseRow): string {
    return mountRelPathNormalize(joinMountPath(this.rowsRelPath, row.name));
  }

  // 删除入口：只读兜底拒 → 确认弹窗（DANGER 默认色调）→ doDelete。只读挂载菜单项已在域件置灰
  // （平台不派发点击），此处分支为语义兜底
  private openDeleteConfirm(row: MountBrowseRow): void {
    if (this.deleting || this.copying) {
      return;
    }
    const mountRow: FolderMountRow | undefined = this.row;
    if (mountRow === undefined || mountRow.mode !== MOUNT_MODE_READ_WRITE) {
      this.showToast('当前是只读挂载，不能删除。请到管理页切换为读写模式。');
      return;
    }
    const what: string = row.isDir ? '文件夹' : '文件';
    const message: string = row.isDir ?
      '将删除文件夹「' + row.name + '」及里面的全部内容。删除的内容会放进系统文件管理的' +
        '回收站，之后可以恢复。' :
      '将删除文件「' + row.name + '」。它会放进系统文件管理的回收站，之后可以恢复。';
    this.confirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '删除' + what,
        message: message,
        confirmLabel: '删除',
        onConfirm: (): void => {
          this.doDelete(row);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.confirmCtrl.open();
  }

  // 删除执行（共享件 deleteMountEntryToTrash；失败如实提示，「已不在」顺手刷新列表让陈旧行退场）
  private async doDelete(row: MountBrowseRow): Promise<void> {
    if (this.deleting || this.copying) {
      return;
    }
    const mountRow: FolderMountRow | undefined = this.row;
    if (mountRow === undefined) {
      return;
    }
    const relPath: string = this.rowChildRelPath(row);
    if (mountRelPathRejectReason(relPath) !== '') {
      // 兜底（段名产自目录列表、无自由文本输入面，理论不可达）——不静默
      hilog.error(DOMAIN, TAG, '删除路径被闸拒绝：%{public}s', relPath);
      this.showToast('删除失败，请重试。');
      return;
    }
    this.deleting = true;
    try {
      const outcome: MountTrashOutcome = await deleteMountEntryToTrash(mountRow.dirUri, relPath);
      if (this.departed) {
        return;
      }
      if (!outcome.ok) {
        this.showToast(outcome.errorText);
        if (outcome.code === MOUNT_TRASH_CODE_MISSING) {
          await this.loadDir();
        }
        return;
      }
      this.showToast('已删除「' + row.name + '」，可以在系统文件管理的回收站里恢复。');
      await this.loadDir();
      if (this.departed) {
        return;
      }
    } finally {
      this.deleting = false;
    }
  }

  // 系统文件管理跳转（文件夹行菜单）：openLink 走 filemanager://openDirectory + parameters.fileUri
  // 传文件夹 URI（官方 FAQ faqs-ability-116）——拉起时系统弹「是否允许跳转」确认框；失败统一
  // toast（外链单源 launchExternalLink）
  private openInFileManager(row: MountBrowseRow): void {
    const mountRow: FolderMountRow | undefined = this.row;
    const ctx: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (mountRow === undefined || ctx === undefined) {
      this.showToast('打不开系统文件管理，请重试。');
      return;
    }
    const relPath: string = this.rowChildRelPath(row);
    if (mountRelPathRejectReason(relPath) !== '') {
      hilog.error(DOMAIN, TAG, '跳转路径被闸拒绝：%{public}s', relPath);
      this.showToast('打不开系统文件管理，请重试。');
      return;
    }
    const targetUri: string = mountChildUri(mountRow.dirUri, relPath);
    launchExternalLink(ctx, FILE_MANAGER_OPEN_DIRECTORY_LINK, (): void => {
      this.showToast('打不开系统文件管理，请重试。');
    }, { 'fileUri': targetUri });
  }

  // ── 面包屑（条体 = 共用件 WorkspaceBreadcrumbBar 单源：几何 / 材质 / 横滑 / 点段 / 滚尾全在
  //    其内；本页只供段数组〔tmpSegs 槽〕与跳转分派）──
  // 段数组派生（mountName + segs → 条体覆盖源；target 载段深度字符串）。★ 键必须覆盖全部可变展示
  // 成分（文本 + 跳转目标 + 尾段标记，与条体件同契约）——尾段标记缺位时进层只有 isLast 变、键不变
  // ⇒ ForEach 复用旧节点，段间「＞」与尾段加粗静默冻结（坑44/坑80 家族）。单写口 = 本方法：每次路径
  // 变更后赋值，换数组引用即触发条体 @Watch 置滚尾标记
  private syncCrumb(): void {
    const out: WorkspaceCrumbSeg[] = [];
    const rootTarget: string = '0';
    const rootLast: boolean = this.segs.length === 0;
    out.push({ key: this.mountName + '|' + rootTarget + '|' + rootLast, text: this.mountName,
      target: rootTarget, isLast: rootLast });
    for (let i = 0; i < this.segs.length; i++) {
      const isLast: boolean = i === this.segs.length - 1;
      const target: string = '' + (i + 1);
      out.push({ key: this.segs[i] + '|' + target + '|' + isLast, text: this.segs[i],
        target: target, isLast: isLast });
    }
    this.crumbSegs = out;
  }

  // 条体点段回跳（target = 段深度字符串；尾段不可点故回传值恒 < 当前层深，越界兜底短路）
  private jumpToCrumb(target: string): void {
    const depth: number = Number.parseInt(target, 10);
    if (Number.isNaN(depth) || depth >= this.segs.length) {
      return;
    }
    const next: string[] = [];
    for (let i = 0; i < depth; i++) {
      next.push(this.segs[i]);
    }
    this.segs = next;
    this.syncCrumb();
    this.loadDir();
  }

  // 内容区顶让位（标题栏下带底 + 间距，单源 searchBandContentTop）。带收起两态（loading /
  // blocked）让位归 topPad，判据与 build 的 titleBarBottomHidden 同式，勿单边改
  private contentTop(): number {
    if (this.state !== BROWSER_STATE_OK) {
      return Math.max(this.topPad, 0);
    }
    return Math.max(searchBandContentTop(this.topPad, WORKSPACE_BAND_CONTENT_GAP,
      WORKSPACE_BREADCRUMB_HEIGHT), 0);
  }

  // ── 条体挂点（标题栏下方带）──
  // 标题栏下方带（形态沿 WorkspaceTopBand：水平居中 + 带内下移 inset + 整带命中透传——不挡下方
  // 列表拖动，条体自身仍可点可横滑）
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

  // 条体本体（挂点唯一共用体；槽位绑定同形——currentDir 占位 + tmpSegs 覆盖源，见成员注释）
  @Builder
  CrumbBar() {
    WorkspaceBreadcrumbBar({
      currentDir: $crumbDirPlaceholder,
      tmpSegs: $crumbSegs,
      onJump: (target: string): void => {
        this.jumpToCrumb(target);
      }
    })
  }

  // 空目录说明（P0-1：零行不静默；顶让位与列表同算式——带收起态归 topPad）
  @Builder
  EmptyHint() {
    Text('这个文件夹是空的')
      .fontSize(13)
      .fontColor(cardDescColor())
      .width(CARD_PANEL_WIDTH)
      .textAlign(TextAlign.Center)
      .padding({ top: 32, bottom: 32 })
      .margin({ top: this.contentTop() })
  }

  // 失效/读不到说明卡（InfoCard 单源，text 随 blockedText 两因分派刷新）；该态带收起 ⇒ 让位等价
  // topPad，返回归官方标题栏返回键
  @Builder
  BlockedCard() {
    InfoCard({ text: this.blockedText })
      .margin({ top: this.contentTop() })
  }

  @Builder
  Content() {
    Column() {
      if (this.state === BROWSER_STATE_BLOCKED) {
        this.BlockedCard()
      } else if (this.state === BROWSER_STATE_OK) {
        // 列表视口铺满整页、让位走官方 offset 轨（渲染件内；工作区页 FolderList 逐参同款）
        // ——内容自标题栏与条体背后滚过
        if (this.rows.length === 0) {
          this.EmptyHint()
        } else {
          MountBrowseList({
            rows: UIUtils.enableV2Compatibility(this.rows),
            // 列表内容顶让位（带底 + 间距；带收起态归 topPad——见 contentTop 注释）
            contentTop: this.contentTop(),
            bottomPad: this.bottomPad,
            copying: this.copying,
            deleting: this.deleting,
            tailNotice: this.tailNotice,
            appColorMode: this.appColorMode,
            scroller: this.listScroller,
            onOpenFolder: (row: MountBrowseRow): void => {
              this.enterFolder(row);
            },
            onOpenFile: (row: MountBrowseRow): void => {
              this.openFile(row);
            },
            onMore: (row: MountBrowseRow): void => {
              this.onRowMore(row);
            }
          })
        }
      }
      // loading 态不渲染中间区（毫秒级，闪显反而更差——管理页首载同口径）
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    PageShell({
      title: this.mountName,
      // 页顶条体带：单行档内容高 = 条体高 40（带高 = inset 8 + 40 = 48），与工作区页
      // 同机制同件同材质（入生效区即出 REGULAR 恒光感）
      titleBarBottom: (): void => {
        this.TopCrumbBand();
      },
      titleBarBottomInset: SEGMENT_BAR_BAND_TOP_INSET,
      titleBarBottomHeight: WORKSPACE_BREADCRUMB_HEIGHT,
      // 带收起两态（loading / blocked）：无浏览内容可指；收起后内容让位随 contentTop 归 topPad
      titleBarBottomHidden: this.state !== BROWSER_STATE_OK,
      content: (): void => {
        this.Content()
      }
    })
  }
}


