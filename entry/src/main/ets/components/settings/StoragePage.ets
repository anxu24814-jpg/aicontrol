// 存储管理页：设置页「存储管理」卡 push——应用总占用 + 分类组卡 + 可安全清理 + 快速清理四卡。
// 官方《存储空间使用与文件生命周期管理》V1【应当】条落地：应用内清理入口 / 统计与系统一致 /
// 清理范围与统计范围一致。
// · 卡1 应用总占用（内容卡）：大数字（appSize + dataSize）+ 图区（占比条 ↔ 环形图，右上角切换键）
//   + 图例（色点 + 分类名，无数值）。分类序与段色单源 = StorageStats.storageCategories /
//   categoryBytes。默认占比条（官方 DataPanel 线性型），切 RingChart（6 段 ≤ 上限 9；不传中心文字
//   ——总占用由大数字承载）；入参为普通成员，经含数值与色模式的键下发（规范 §3 键变重建）。
// · 卡2 分类组卡（GroupSettingCard）：六分类按占用降序（序单源 categoryRowsBySize，同值保持原序）、
//   行尾 valueText、行图标映射系统符号（坑72）。★ 入口判据单源 categoryHasManageEntry，现仅
//   「对话附件」可点进附件管理页，其余只读无 onClick（同一动作不设第二入口）；items 普通成员入参，
//   刷新走键变重建（坑57 家族）。
// · 卡3 可安全清理（内容卡）：说明小字在按钮行上方（宪法「功能设置卡布局次序」）+ 三行只读明细
//   （应用临时文件 / 残留附件文件 / 运行日志）+ 主键「清理」（皆无可清时置灰 + 状态提示行）；
//   说明明示清理范围与卡2「缓存」行的扣减关系。
// · 卡4 快速清理（单条目入口卡）：整卡可点 push 三级页；标题后官方 warning 色符号（决明指令）；
//   危险操作列末位；builder 固定在 Content() 之后（切片锚，见 QuickCleanCard 注释）。
// · 历史撤除（防回游）：会话附件入口卡收编为卡2「对话附件」行（行名走分类名单源，管理页标题仍为
//   「会话附件」——两处不同名是有意的，避免同屏两名同一分类）；浏览器数据卡收归快速清理三级页；
//   文件工作区入口卡改挂设置页「联网搜索 + 工具调用」卡。
// · 刷新链：aboutToAppear 首载 + onShown 重进现读（坑25「onShown 是可靠姿势，含 pop 返回」；与
//   aboutToAppear 同帧双触发由 loading 守卫去重）+「更多」菜单刷新项 + 清理完成后重载。
// · 加载/失败态：官方【推荐】加载完成前不显 0——大数字与分类值显「正在统计…」，官方值缺位显「—」
//   且自扫四项照常；三条失败路径（catch / 无上下文 / 库未就绪）同置 loadFailed，「统计失败」上屏、
//   主键置灰，下一次尝试开始即复位。卡2 只在统计成功且非失败态渲染（失败时 breakdown 保旧值）。
// · 明细刷新键（规范 §3 主通道；坑16 家族）：卡1 图例键 = key + 分类名 + 段色（圆点色走 @Builder
//   值参快照）；卡2 外层键 = detailKey()（含各行值文本、行序与色模式）。
// · toast 统一入口 showToast（P2-4 提取，失败提示仍逐处显式调用）；只提取不接光感材质，零视觉变化。
//   无保存动作 → 返回无参 pop 不挂 onPop（坑17）。页面骨架照 UsageStatsPage（卡宽 CARD_PANEL_WIDTH
//   / 间距 CARD_SPACING / Scroll 顶对齐坑18）。
// · 标题栏「更多」菜单（域件 StorageTitleMenu.ets）：刷新项 +「清理聊天附件」项开半模态。清理半模态
//   = 四档行卡（今天 / 近7天 / 近30天 / 全部 = 保留窗口，单源 attachCleanItems）+ confirmSheetClose
//   确认 + deleteAttachmentsByCutoff 执行（refs 成对清 + commit 后删文件，cutoff 快照贯穿「显示数 =
//   实删数」）；五件式关闭-再开协调（成员用全站标准名，329 组判据）。清理只作用于聊天附件，不含
//   工作区、壁纸、缓存、日志、数据库；按时间清理附件的唯一入口是本页菜单。
import { LengthMetrics } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_ATTACHMENT_MANAGE_PAGE, ROUTE_QUICK_CLEAN_PAGE } from '../../common/RouteNames';
import { SETTING_TITLE_STORAGE } from '../../common/SettingSearch';
import {
 CARD_PANEL_WIDTH, CARD_SPACING, badgeBg, cardBg, cardDescColor, cardTitleColor,
  usageAccentColor, CARD_RADIUS
} from '../../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg,
  fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect,
  overlayMaterial } from '../../common/ImmersiveLevel';
import { AttachCleanItem, CleanPreview, CleanResult, StorageBreakdown, StorageCategory,
  StorageCategoryValue,
  attachCleanConfirmMessage, attachCleanCutoffMs, attachCleanItems, categoryBytes,
  categoryHasManageEntry, categoryRowsBySize, cleanCache,
  cleanOrphanAttachments, cleanSandboxLogs, formatBytes, officialDependentKeys,
  readStorageBreakdown, scanCleanables, storageCategories } from '../../common/StorageStats';
import { AttachmentTotalRow } from '../../common/store/AttachmentDb';
import { deleteAttachmentsByCutoff, isReady, readAttachmentCleanPreview,
  sharedRdbStore } from '../../common/store/ChatDb';
import { DIVIDER_LEFT_ICON_LARGE, GroupEntryItem, GroupSettingCard, SETTING_ICON_BLUE } from '../GroupSettingCard';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import { confirmSheetClose, sheetPanelOptions, sheetTitleBarOptions } from '../chat/KimiSheetCommon';
import { RingChart } from '../stats/RingChart';
import { QUICK_CLEAN_TITLE } from './QuickCleanPage';
import { StorageMoreMenuAnchor, StorageTitleMenuCallbacks, StorageTitleMenuHost } from './StorageTitleMenu';

// 明细行数据（ArkTS 禁 build 内匿名对象数组；卡3 三行只读明细用）
interface StorageRowItem {
  key: string;
  label: string;
  text: string;
}

// 图例项（段色圆点 + 分类名；数值在卡2 组卡行）
interface LegendItem {
  key: string;
  label: string;
  color: string;
}

// 清理面板行载荷：cutoff 开面板时一次算定并存入行——行尾读数、确认文案与执行链全携此值，
// 「显示数 = 实删数」精确成立（时间档快照后新发送件不进读数；全部档会一并删除，确认文案预告）。
// count = -1 表读数未就绪（显「—」置灰，不显 0——官方同口径；失败同态，重开面板重试）
interface AttachCleanRowView {
  key: string;
  label: string;
  desc: string;
  cutoff: number | null;
  count: number;
  bytes: number;
}

@Component
export struct StoragePage {
  // 页面存活守卫：置位后迟到异步回调不写状态不碰 UI 不上行，写库照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 路由栈（卡2「对话附件」行 push 附件管理页）
  pathStack: NavPathStack = new NavPathStack();
  // 统计就绪标记（false = 显「正在统计…」，不显 0——官方【推荐】）
  @State private loaded: boolean = false;
  @State private breakdown: StorageBreakdown | null = null;
  @State private preview: CleanPreview | null = null;
  // 清理进行中（主键文案转「清理中…」并置灰）
  @State private cleaning: boolean = false;
  // 统计失败态（三条失败路径置位、下一次尝试开始复位）
  @State private loadFailed: boolean = false;
  // 图形态切换（决明指令）：false = 占比条（默认）/ true = 环形图；形制照用量统计页排行卡，
  // 会话内态不持久化（避免偏好面扩散）
  @State private ringOn: boolean = false;
  // ── 标题栏「更多」菜单（域件 StorageTitleMenu.ets；init↔dispose 成对）──
  private titleMenu: StorageTitleMenuHost = new StorageTitleMenuHost();
  // ── 清理聊天附件半模态（菜单 → 四档选择面板 → confirmSheetClose 确认 → 执行链）──
  // 可见性挂 @Watch = 关闭-再开兜底网（五件式，MountManagePage 同律）；成员名 = 329 组判据标准名
  @State @Watch('onSheetVisibleChanged') private cleanSheetShow: boolean = false;
  // 离场动效在途位（requestCloseClean 置位 / onSheetGone 清位）与开意图位
  private sheetClosing: boolean = false;
  private pendingOpen: boolean = false;
  // 四档行载荷（开面板整组重赋驱动键变重建；cutoff 快照存行内——见 AttachCleanRowView）
  @State private attachCleanRows: AttachCleanRowView[] = [];
  // 附件清理在途（置灰快照 + 防重入；与卡3 cleaning 分立，置灰判据同时读两者）
  @State private attachCleaning: boolean = false;
  // 半模态滚动感知（bindToScrollable 绑定）
  private cleanScroller: Scroller = new Scroller();
  // 重入守卫：onShown 首显与 aboutToAppear 同帧双触发去重（不叠两次目录扫描）
  private loading: boolean = false;
  @StorageProp('appColorMode') appColorMode: number = 1;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 清理确认弹窗（组件成员位构造——坑7 约束；动态文案经 openConfirm 重建）
  private confirmCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: ConfirmDialog({
      title: '清理存储',
      message: '',
      confirmLabel: '清理',
      onConfirm: (): void => {
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });

  aboutToAppear(): void {
    this.load();
    // 标题栏「更多」菜单宿主接线（WorkspaceManagePage 同款：init↔dispose 成对——内存防线）
    this.titleMenu.init(this.getUIContext(), this.menuCallbacks());
  }

  // 统计 + 可清理预览并行拉取（互不依赖）；失败 toast 明示（P0-1 不静默）并置失败态
  private load(): void {
    if (this.loading) {
      return;
    }
    const ctx: common.Context | undefined =
      this.getUIContext().getHostContext() as common.Context | undefined;
    if (ctx === undefined) {
      this.loadFailed = true;
      this.showToast('无法获取应用上下文');
      return;
    }
    const db: relationalStore.RdbStore | null = this.takeStore();
    if (db === null) {
      this.loadFailed = true;
      return;
    }
    this.loading = true;
    this.loadFailed = false;
    Promise.all([readStorageBreakdown(ctx), scanCleanables(ctx, db)])
      .then((results: [StorageBreakdown, CleanPreview]): void => {
        if (this.departed) {
          return;
        }
        this.breakdown = results[0];
        this.preview = results[1];
        this.loaded = true;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.loadFailed = true;
        const err: BusinessError = e as BusinessError;
        this.showToast('存储统计失败，请重试（code ' + err.code + '）');
      })
      .finally((): void => {
        this.loading = false;
      });
  }

  // 手动刷新（菜单刷新项）：清理中忽略（清理结束自带重载，避免扫半清理态）；统计中忽略；
  // 失败态点击即重试（load 开头复位 loadFailed）
  private onRefresh(): void {
    if (this.cleaning || this.loading) {
      return;
    }
    this.load();
  }

  // 库句柄（ChatDb 红线「未就绪禁发送」同口径——未就绪 toast 明示并中断，不静默）
  private takeStore(): relationalStore.RdbStore | null {
    if (!isReady()) {
      this.showToast('数据库尚未就绪，请稍后再试');
      return null;
    }
    return sharedRdbStore();
  }

  // 本页 toast 统一入口（P2-4 提取）；只提取不加材质，零视觉变化
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  // ── 标题栏「更多」菜单：弹前快照组装 + 动作编排 ──
  // 置灰语义（弹时快照，菜单节点弹前重建）：刷新项 = 任一清理/统计在途置灰；清理项 = 任一清理
  // 在途置灰（不留可点静默无反应的死项）
  private menuCallbacks(): StorageTitleMenuCallbacks {
    return {
      refreshEnabled: !this.cleaning && !this.loading && !this.attachCleaning,
      cleanEnabled: !this.cleaning && !this.attachCleaning,
      onRefresh: (): void => {
        this.onRefresh();
      },
      onClean: (): void => {
        this.onCleanMenuTap();
      }
    };
  }

  // 「更多」菜单弹出
  private openStorageMoreMenu(): void {
    this.titleMenu.open(this.getUIContext(), this.menuCallbacks(), this.immersiveLevel);
  }

  // 菜单「清理聊天附件」项：在途守卫后记开意图（五件式 requestOpen，关闭动效在途由 onSheetGone 补开）
  private onCleanMenuTap(): void {
    if (this.cleaning || this.attachCleaning) {
      return;
    }
    this.requestOpenClean();
  }

  // ── 清理面板关闭-再开协调五件式（规范-半模态 §1；MountManagePage 同律，成员名 = 329 组标准名）──
  private requestOpenClean(): void {
    this.pendingOpen = true;
    if (this.sheetClosing) {
      return; // 离场动效在途：只记开意图（onSheetGone 正路 / onSheetVisibleChanged 兜底补开）
    }
    this.applyOpen();
  }

  // 全文件唯一写可见性 true 处（329 组判据）；写入即触发四档读数现读（cutoff 随之算定）
  private applyOpen(): void {
    if (!this.pendingOpen) {
      return;
    }
    this.cleanSheetShow = true;
    this.loadCleanRows();
  }

  private onSheetGone(): void {
    this.sheetClosing = false;
    if (!this.cleanSheetShow) {
      this.applyOpen();
    }
  }

  // 兜底网（离场动效在途期框架收尾回写压回时按意图补开一次）
  private onSheetVisibleChanged(): void {
    if (!this.cleanSheetShow) {
      this.applyOpen();
    }
  }

  // 关闭单入口（标题栏 xmark / 手势 / 程序化三路同调）：先清开意图 → 置在途位 → 再写
  // 可见性，序不可倒置——先写 false 会让兜底补开误触
  private requestCloseClean(): void {
    this.pendingOpen = false;
    this.sheetClosing = true;
    this.cleanSheetShow = false;
  }

  // 四档读数现读（开面板一次）：cutoff 口径见 AttachCleanRowView；读数完成按行整组重赋
  //（@State 重赋驱动键变重建）；失败行留 -1，不弹「将删除 0 个」误导确认
  private loadCleanRows(): void {
    const now: number = Date.now();
    const items: AttachCleanItem[] = attachCleanItems();
    const rows: AttachCleanRowView[] = [];
    for (const item of items) {
      rows.push({ key: item.key, label: item.label, desc: item.desc,
        cutoff: attachCleanCutoffMs(item.key, now), count: -1, bytes: 0 });
    }
    this.attachCleanRows = rows;
    for (let i = 0; i < rows.length; i++) {
      const idx: number = i;
      readAttachmentCleanPreview(rows[idx].cutoff)
        .then((preview: AttachmentTotalRow): void => {
          if (this.departed) {
            return;
          }
          const next: AttachCleanRowView[] = [];
          for (let j = 0; j < this.attachCleanRows.length; j++) {
            const row: AttachCleanRowView = this.attachCleanRows[j];
            if (j === idx) {
              next.push({ key: row.key, label: row.label, desc: row.desc, cutoff: row.cutoff,
                count: preview.count, bytes: preview.bytes });
            } else {
              next.push(row);
            }
          }
          this.attachCleanRows = next;
        })
        .catch((): void => {
          if (this.departed) {
            return;
          }
          // 该行读数失败：留 -1（显「—」置灰）——重开面板重试
        });
    }
  }

  // 档位行图标（按保留窗口时间语义；符号已对 SDK 核实，坑72；兜底 = paperclip）
  private cleanRowIcon(key: string): Resource {
    if (key === 'today') {
      return $r('sys.symbol.clock');
    }
    if (key === 'd7') {
      return $r('sys.symbol.calendar');
    }
    if (key === 'd30') {
      return $r('sys.symbol.clock_arrow_2_circlepath');
    }
    return $r('sys.symbol.paperclip');
  }

  // 面板行数据（label/desc 单源 attachCleanItems；valueText = 行尾读数，口径不显 0；零读数与
  // 未就绪行置灰，不留可点无反应的死项）
  private cleanRowItems(): GroupEntryItem[] {
    const items: GroupEntryItem[] = [];
    for (const row of this.attachCleanRows) {
      const ready: boolean = row.count >= 0;
      items.push({
        icon: this.cleanRowIcon(row.key),
        iconBg: SETTING_ICON_BLUE,
        label: row.label,
        secondary: row.desc,
        valueText: ready ? row.count + ' 个 ' + formatBytes(row.bytes) : '—',
        enabled: ready && row.count > 0 && !this.attachCleaning,
        onClick: (): void => {
          this.openCleanConfirm(row);
        }
      });
    }
    return items;
  }

  // 面板行签名（键含 label+valueText+enabled，四档读数逐档到位即整卡重建；卡2 detailKey 同款）
  private cleanRowsKey(): string {
    const items: GroupEntryItem[] = this.cleanRowItems();
    const parts: string[] = [];
    for (const item of items) {
      parts.push(item.label + '=' + (item.valueText ?? '') +
        (item.enabled === false ? '#off' : ''));
    }
    return parts.join(',');
  }

  // 行卡点击 → 确认弹窗（confirmSheetClose UIContext 形态，三非确认出口留面板；message 单源
  // attachCleanConfirmMessage，范围句数字即读数快照＝实删数）。确认键为 font_primary 主色
  //（无 DANGER 红位——破坏性由 message「删除后无法恢复」承担，裁定接受的代价）
  private async openCleanConfirm(row: AttachCleanRowView): Promise<void> {
    if (this.attachCleaning) {
      return;
    }
    const preview: AttachmentTotalRow = { count: row.count, bytes: row.bytes };
    const approved: boolean = await confirmSheetClose(this.getUIContext(), {
      title: '清理聊天附件',
      message: attachCleanConfirmMessage(row.key, preview),
      cancelLabel: '取消',
      confirmLabel: '清理'
    });
    if (this.departed) {
      return;
    }
    if (!approved) {
      return; // 取消键 / 点蒙层 / 弹窗异常三非确认出口：留在面板不动
    }
    this.doAttachClean(row);
  }

  // 清理执行链：程序化关面板 → 入链删除（cutoff 与读数同值）→ toast 回报实删数 → 重扫统计 →
  // 清在途位；失败直显错误码 + 重扫保留已完成部分
  private async doAttachClean(row: AttachCleanRowView): Promise<void> {
    this.requestCloseClean();
    this.attachCleaning = true;
    try {
      const removed: number = await deleteAttachmentsByCutoff(row.cutoff);
      if (this.departed) {
        return;
      }
      this.load();
      this.showToast('已清理 ' + removed + ' 个附件');
    } catch (e) {
      if (this.departed) {
        return;
      }
      const err: BusinessError = e as BusinessError;
      this.load();
      this.showToast('清理失败（code ' + err.code + '）');
    } finally {
      this.attachCleaning = false;
    }
  }


  // 大数字文本：失败显「统计失败」/ 加载中显「正在统计…」/ 官方值缺位显「—」/ 否则格式化总占用
  private totalText(): string {
    if (this.loadFailed) {
      return '统计失败';
    }
    if (!this.loaded || this.breakdown === null) {
      return '正在统计…';
    }
    if (!this.breakdown.officialOk) {
      return '—';
    }
    return formatBytes(this.breakdown.total);
  }

  // 卡1 图例行（固定序 = storageCategories 序 = 占比段序，三处同源；段色 = segColor）
  private legendRows(): LegendItem[] {
    const categories: StorageCategory[] = storageCategories();
    const rows: LegendItem[] = [];
    for (let i = 0; i < categories.length; i++) {
      rows.push({ key: categories[i].key, label: categories[i].label, color: this.segColor(i) });
    }
    return rows;
  }

  // 分类行图标（仅 UI 映射，注册表不带资源；资源名已对 SDK 核实——坑72）
  private rowIcon(key: string): Resource {
    if (key === 'app') {
      return $r('sys.symbol.square_grid_2x2');
    }
    if (key === 'attachments') {
      return $r('sys.symbol.paperclip');
    }
    if (key === 'database') {
      return $r('sys.symbol.hard_disk');
    }
    if (key === 'wallpaper') {
      return $r('sys.symbol.picture');
    }
    if (key === 'cache') {
      return $r('sys.symbol.archivebox');
    }
    return $r('sys.symbol.ellipsis_circle');
  }

  // 分类行逐色分派已退役（组卡同色笔：六行统一蓝——按占用降序重排下逐行取色会漂移）

  // 附件管理页入口（卡2「对话附件」行）
  private openAttachManage(): void {
    this.pathStack.pushPathByName(ROUTE_ATTACHMENT_MANAGE_PAGE, null);
  }

  // 卡2 行数据（域侧已按占用降序，页面不重排；官方值缺位显「—」；入口判据
  // categoryHasManageEntry，非入口行不带 onClick = 只读无按压）
  private detailItems(): GroupEntryItem[] {
    const b: StorageBreakdown | null = this.breakdown;
    if (b === null) {
      return [];
    }
    const rows: StorageCategoryValue[] = categoryRowsBySize(b);
    const officialKeys: string[] = officialDependentKeys();
    const items: GroupEntryItem[] = [];
    for (const row of rows) {
      const text: string =
        (!b.officialOk && officialKeys.includes(row.key)) ? '—' : formatBytes(row.bytes);
      if (categoryHasManageEntry(row.key)) {
        items.push({
          icon: this.rowIcon(row.key),
          iconBg: SETTING_ICON_BLUE,
          label: row.label,
          valueText: text,
          chevron: true,
          onClick: (): void => {
            this.openAttachManage();
          }
        });
      } else {
        items.push({
          icon: this.rowIcon(row.key),
          iconBg: SETTING_ICON_BLUE,
          label: row.label,
          valueText: text
        });
      }
    }
    return items;
  }

  // 卡2 数据签名（键含各行值文本与色模式；items 为普通成员入参，键变重建是唯一刷新通道）
  private detailKey(): string {
    const items: GroupEntryItem[] = this.detailItems();
    const parts: string[] = [];
    for (const item of items) {
      parts.push(item.label + '=' + (item.valueText ?? ''));
    }
    return parts.join(',') + '|' + this.appColorMode;
  }

  // 卡3 三行明细（键含文本 → 清理后数字变化即重建，规范 §3 主通道；失败态显「—」不显旧值）
  private cleanRows(): StorageRowItem[] {
    return [
      { key: 'cache', label: '应用临时文件', text: this.cacheText() },
      { key: 'orphan', label: '残留附件文件', text: this.orphanText() },
      { key: 'log', label: '运行日志', text: this.logText() }
    ];
  }

  private cacheText(): string {
    return (this.preview === null || this.loadFailed) ? '—' : formatBytes(this.preview.cacheBytes);
  }

  private orphanText(): string {
    return (this.preview === null || this.loadFailed) ? '—' : formatBytes(this.preview.orphanBytes);
  }

  private logText(): string {
    return (this.preview === null || this.loadFailed) ? '—' : formatBytes(this.preview.logBytes);
  }

  // 有无可清理内容（三项皆无可清 = 主键置灰 + 状态提示行）
  private canClean(): boolean {
    return this.preview !== null &&
      (this.preview.cacheBytes > 0 || this.preview.orphanCount > 0 || this.preview.logBytes > 0);
  }

  // 占比段色（同 UsageRankRing 手法：主蓝 ARGB 半透明阶梯，前五段 255→64，末段「其他」=
  // badgeBg 灰——零新增色值，半透明透卡底自适应深浅）
  private segColor(index: number): string {
    if (index >= 5) {
      return badgeBg(this.appColorMode);
    }
    const alpha: number = Math.round(255 - index * (255 - 64) / 4);
    const hex: string = alpha < 16 ? '0' + alpha.toString(16) : alpha.toString(16);
    return '#' + hex.toUpperCase() + usageAccentColor(this.appColorMode).substring(1);
  }

  private segColors(): string[] {
    const colors: string[] = [];
    for (let i = 0; i < 6; i++) {
      colors.push(this.segColor(i));
    }
    return colors;
  }

  // 环形入环值（六分类恒 6 段 ≤ DataPanel 上限 9，无需「其余」聚合；未就绪返回空数组）
  private ringValues(): number[] {
    const b: StorageBreakdown | null = this.breakdown;
    return b === null ? [] : categoryBytes(b);
  }

  // 图形态数据签名（键含数值与色模式；RingChart 入参为普通成员，父重渲不更新）
  private ringKey(): string {
    return this.ringValues().join(',') + '|' + this.appColorMode;
  }

  // 清理确认（列三项大小——官方【推荐】「清理前展示可清理内容与大小并确认范围」）
  private openConfirm(): void {
    if (!this.canClean() || this.cleaning) {
      return;
    }
    const preview: CleanPreview | null = this.preview;
    if (preview === null) {
      return;
    }
    const message: string = '将清理临时文件 ' + formatBytes(preview.cacheBytes) +
      '、残留附件文件 ' + preview.orphanCount + ' 个共 ' + formatBytes(preview.orphanBytes) +
      '、运行日志 ' + preview.logCount + ' 份共 ' + formatBytes(preview.logBytes) +
      '。不影响已发送的消息。';
    this.confirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '清理存储',
        message: message,
        confirmLabel: '清理',
        onConfirm: (): void => {
          this.doClean();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.confirmCtrl.open();
  }

  // 清理执行：临时文件 → 残留附件 → 旧日志（顺序 best-effort 不中断）；完成后重载统计，
  // 失败直显错误码 + 重载保留已完成部分
  private async doClean(): Promise<void> {
    const ctx: common.Context | undefined =
      this.getUIContext().getHostContext() as common.Context | undefined;
    if (ctx === undefined) {
      this.showToast('无法获取应用上下文');
      return;
    }
    const db: relationalStore.RdbStore | null = this.takeStore();
    if (db === null) {
      return;
    }
    this.cleaning = true;
    try {
      const cacheRes: CleanResult = await cleanCache(ctx);
      if (this.departed) {
        return;
      }
      const orphanRes: CleanResult = await cleanOrphanAttachments(ctx, db);
      if (this.departed) {
        return;
      }
      const logRes: CleanResult = cleanSandboxLogs();
      const freed: number = cacheRes.bytes + orphanRes.bytes + logRes.bytes;
      const failed: number = cacheRes.failed + orphanRes.failed + logRes.failed;
      this.load();
      this.showToast(failed > 0 ? '已清理 ' + formatBytes(freed) + '，' + failed + ' 项未清理' :
        '已清理 ' + formatBytes(freed));
    } catch (e) {
      if (this.departed) {
        return;
      }
      const err: BusinessError = e as BusinessError;
      this.load();
      this.showToast('清理失败（code ' + err.code + '）');
    } finally {
      this.cleaning = false;
    }
  }

  // 卡1 应用总占用（内容卡：大数字 + 图区 + 图例；详情行剥离至卡2 组卡）
  @Builder
  UsageCard() {
    Column({ space: 10 }) {
      // 标题行 + 图形态切换键（形制照用量页排行卡：TEXTUAL SymbolGlyph 18 + font_secondary；
      // 图标示目标形态——占比条态显环形图标，环形态显柱状图标）
      Row() {
        Text('应用总占用')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        Button() {
          SymbolGlyph(this.ringOn ? $r('sys.symbol.rectangle_3_group') :
            $r('sys.symbol.circle_on_circle'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .onClick((): void => {
          this.ringOn = !this.ringOn;
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      if (this.loaded && this.breakdown !== null && !this.loadFailed) {
        Text(this.totalText())
          .fontSize(32)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .width('100%')
        // 图形态分支（切换转场 = 用量页同款 transition 交叉淡化 250ms EaseOut）
        if (this.ringOn) {
          Column() {
            ForEach([this.ringKey()], (_key: string) => {
              // 不传中心文字（真机反馈环内总占用与环重叠）；两串皆空即不渲染
              RingChart({
                values: this.ringValues(),
                colors: this.segColors(),
                note: '环段按分类顺序，灰色为其他'
              })
            }, (key: string): string => key)
          }
          .width('100%')
          .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut }))
        } else {
          // 占比条：官方 DataPanel 线性型（max: 0 = 按值比例铺满；段色与图例圆点同源）
          DataPanel({ values: categoryBytes(this.breakdown), max: 0, type: DataPanelType.Line })
            .width('100%')
            .height(10)
            .strokeWidth(10)
            .valueColors(this.segColors())
            .trackBackgroundColor(Color.Transparent)
            .closeEffect(true)
            .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut }))
        }
        // 图例（固定序 = 占比段序；无数值——只承担段色与分类对照）
        this.Legend()
      } else {
        Text(this.totalText())
          .fontSize(20)
          .fontColor(cardDescColor())
          .width('100%')
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  // 图例行容器（Flex 折行；键含段色——只含文本时深浅色切换圆点停旧色）
  @Builder
  Legend() {
    Flex({ wrap: FlexWrap.Wrap,
      space: { main: LengthMetrics.vp(12), cross: LengthMetrics.vp(6) } }) {
      ForEach(this.legendRows(), (row: LegendItem): void => {
        this.LegendItem(row)
      }, (row: LegendItem): string => row.key + '|' + row.label + '|' + row.color)
    }
    .width('100%')
  }

  // 图例项（段色圆点 + 分类名；数值在卡2 组卡行）
  @Builder
  LegendItem(row: LegendItem) {
    Row({ space: 6 }) {
      Circle({ width: 8, height: 8 })
        .fill(row.color)
      Text(row.label)
        .fontSize(13)
        .fontColor(cardDescColor())
    }
    .alignItems(VerticalAlign.Center)
  }

  // 卡2 分类组卡（外层键 = detailKey() 键变重建下发普通成员 items）。
  // ★ 条件渲染：items 为空会画出「只有 8vp 内边距的空白条」，加载中/失败时须不渲染；
  // ★ 守卫含 !loadFailed——刷新失败时 breakdown 保旧值（「失败态恒 null」只对首载成立），
  // 否则显旧数字，与卡1/卡3「失败不显旧数字」口径相悖
  @Builder
  DetailCard() {
    if (this.breakdown !== null && !this.loadFailed) {
      ForEach([this.detailKey()], (_key: string): void => {
        GroupSettingCard({ items: this.detailItems(), dividerLeft: DIVIDER_LEFT_ICON_LARGE })
      }, (key: string): string => key)
    }
  }

  // 卡3 可安全清理（内容卡；说明小字在按钮行上方——宪法「功能设置卡布局次序」）
  @Builder
  CleanCard() {
    Column({ space: 10 }) {
      Text('可安全清理')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .width('100%')
      Text('清理临时文件、应用缓存与运行日志。清理后上方「缓存」的数字会同步减少。')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      ForEach(this.cleanRows(), (row: StorageRowItem): void => {
        this.CleanRow(row)
      }, (row: StorageRowItem): string => row.key + '|' + row.text)
      Button(this.cleaning ? '清理中…' : '清理')
        .width('100%')
        .fontColor(fallbackButtonFont(this.contentFallback, true))
        .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel,
          true))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .enabled(this.canClean() && !this.cleaning && !this.loadFailed)
        .onClick((): void => {
          this.openConfirm();
        })
      if (this.loadFailed) {
        Text('统计失败，请重试')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      // 空态文案只在统计成功后出——加载中显「暂无可清理」与卡1「正在统计…」同屏矛盾
      } else if (this.loaded && !this.canClean() && !this.cleaning) {
        Text('暂无可清理内容')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  // 清理明细行（只读：名称 + 右侧数值）
  @Builder
  CleanRow(row: StorageRowItem) {
    Row() {
      Text(row.label)
        .fontSize(15)
        .fontColor(cardTitleColor())
        .layoutWeight(1)
      Text(row.text)
        .fontSize(15)
        .fontColor(cardDescColor())
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  Content() {
    // ★ alignContent 必须 Top：缺省 Center 会把 1vp 锚点行垂直居中，「更多」菜单弹到屏幕中部
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column({ space: CARD_SPACING }) {
          this.UsageCard()
          // 卡2 分类组卡（决明指令 = 新组卡放在「应用总占用」下）
          this.DetailCard()
          this.CleanCard()
          // 卡4 快速清理入口卡（破坏性最强故列末位——决明指令「仍在最底下」）
          this.QuickCleanCard()
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
      }
      .width('100%')
      .height('100%')
      // 滚动内容不足视口时顶对齐（坑18：Scroll align 默认 Center 会垂直居中）
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)

      // 「更多」菜单隐形锚点（锚点不随滚动；挂内容区 Stack 同层）
      StorageMoreMenuAnchor({ topPad: this.topPad })
    }
    .width('100%')
    .height('100%')
  }

  // 卡4 快速清理：整卡可点 push 三级页（六项合组卡勾选 + 底部统一清除键一次确认——
  // 2026-11-15 批量多选笔改批量口径，「逐项确认」旧口径只在聚合项保留）。★ 警示符号在右侧原「前往」位
  //（2026-11-15 决明「去掉前往二字，警示图标放原前往处」笔自标题尾迁入——标题行只剩标题）
  // 快速清理卡（2026-11-04 蒙层合规笔：整卡自绘，§4.19 范式——卡底 + padding 4 + 透明
  // Button 蒙层，四缘各 4vp；卡高 72 = 4×2 + 64，内容内距 12 + 外层 4 = 原官方卡内距 16）。
  // 警示符走 SymbolGlyph 16 警告色（原 primarySuffixSymbol 的 SymbolGlyphModifier 随官方卡
  // 退役；2026-11-15 起居右侧、与 chevron_right 同行）；builder 顺序约定（切片锚）：
  // 固定在 Content() 之后、build() 之前——插入 UsageCard→DetailCard→CleanCard 三件之间会连带误红
  private openQuickClean(): void {
    this.pathStack.pushPathByName(ROUTE_QUICK_CLEAN_PAGE, null);
  }

  @Builder
  QuickCleanCard() {
    Column() {
      Button() {
        Row({ space: 8 }) {
          Column({ space: 0 }) {
            Row({ space: 4 }) {
              Text(QUICK_CLEAN_TITLE)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('100%')
            Text('批量清除本机数据，勾选后统一确认执行')
              .fontSize(14)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          // 警示符居原「前往」位（2026-11-15 决明笔迁入）+ 右缘灰箭头示意「可进下一页」
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
              .fontSize(16)
              .fontColor([$r('sys.color.ohos_id_color_warning')])
              .flexShrink(0)
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(20)
              .fontColor([cardDescColor()])
          }
          .flexShrink(0)
        }
        .width('100%')
        .height('100%')
      }
      .type(ButtonType.Normal)
      .width('100%')
      .height(64)
      .padding({ left: 12, right: 12 })
      .backgroundColor(Color.Transparent)
      .borderRadius(CARD_RADIUS)
      .onClick((): void => {
        this.openQuickClean();
      })
    }
    .width(CARD_PANEL_WIDTH)
    .height(72)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  build() {
    PageShell({
      title: SETTING_TITLE_STORAGE,
      // 右上角「更多」菜单键（刷新与清理聊天附件收入菜单；菜单项是普通参数不随 @State 更新，
      // 置灰走弹时快照 + 页面侧守卫兜底）
      menuHds: {
        value: [{
          content: {
            icon: $r('sys.symbol.dot_grid_2x2'),
            action: (): void => {
              this.openStorageMoreMenu();
            }
          }
        }]
      },
      // 页面每次显示重拉（坑25：onShown 含 pop 返回；同帧双触发由 loading 守卫去重）
      onShown: (): void => {
        this.load();
      },
      content: (): void => {
        this.Content();
      }
    })
      // 清理面板挂页面根 PageShell 链（判据三条全过）；detents 缺省半屏起可上拉，零暂存站点恒放行
      // ——无关闭确认，把关在行卡确认弹窗
      .bindSheet($$this.cleanSheetShow, this.CleanSheet(), sheetPanelOptions(
        (action: DismissSheetAction): void => {
          action.dismiss();
          this.requestCloseClean();
        },
        undefined, undefined,
        (): void => {
          this.onSheetGone();
        }))
  }

  // 清理聊天附件面板（内联 @Builder）：说明小字 + 四行组卡；键 = cleanRowsKey() 整卡重建。
  // 滚动容器 clip(false)（缺省裁剪 = 标题栏动态模糊空转）。★ builder 固定在 build() 之后——
  // 不进三件切片区段，也不落 assert-quick-clean 的 warnSymbol→build 段
  @Builder
  CleanSheet() {
    HdsNavigation() {
      Scroll(this.cleanScroller) {
        Column({ space: CARD_SPACING }) {
          Text('按发送时间清理已发送的聊天附件。只清理附件，会话、消息与工作区不受影响。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
            .textAlign(TextAlign.Start)
          ForEach([this.cleanRowsKey()], (_key: string): void => {
            GroupSettingCard({ items: this.cleanRowItems(), dividerLeft: DIVIDER_LEFT_ICON_LARGE })
          }, (key: string): string => key)
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .padding({ top: 12, bottom: 24 })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
      .clip(false)
      .align(Alignment.TopStart)
    }
    .titleBar(sheetTitleBarOptions('清理聊天附件', '', (): void => {
      this.requestCloseClean();
    }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.cleanScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }

  aboutToDisappear(): void {
    // 标题栏菜单节点销毁（与 aboutToAppear 的 init 对称；菜单宿主持 UIContext 引用）
    this.titleMenu.dispose();
    this.departed = true;
  }
}
