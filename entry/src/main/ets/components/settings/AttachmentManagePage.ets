// 附件管理页（2026-09-15 附件管理列表笔，任务书-附件管理列表-20260915）：设置 → 存储管理 →
// 「会话附件」卡 push——按会话分组列出全部已发送附件，可展开逐件查看、预览、单件删除。
// 壳体 = 自包 PageShell（照 StoragePage）；列表 = List + LazyForEach（官方长列表红线）+
// 扁平项模型（规避嵌套 LazyForEach：展开 = 该组子行 splice 进本数组，折叠 = 移出）。
//
// 分页有界（决明 2026-09-15 问句「显示条数呢，后面附件会话数量膨胀怎么办」的正答）：
// · 一级每批 20 组、触底自动续批、到底即停（groupsExhausted——照 ChatOlderCtrl 既有有界
//   口径：返回不足一批即置位，此后不再触发；无界连拉是禁区）；
// · 二级展开才查、每批 50 件、组尾「显示更多」显式续批（组内不自动续——书内自定口径：
//   自动续会把长组越拉越长、观众失焦）；未展开的组零查询零渲染；
// · 查询不取 parsedText（AttachmentDb.AttachmentListRow 类型级封死大字段）；
// · 峰值内存 = 已加载组行（≤20×n）+ 已展开组行（≤50×m），且折叠即丢弃该组行对象，再展开
//   重新取第一批（有界优先，代价 = 续批进度不保留）。
//
// 为何新开件（反碎片下限②书面理由）：StoragePage 是「存储占用展示 + 可安全清理」定位，本页
// 承担第二职责（附件逐件管理：分组/展开/预览/删除）且体量必然越 800 软引导线；亦不能并入
// AttachmentDb（store 层零 UI）。
// 刷新链（规范-数据存储获取刷新方案 §3 白名单）：aboutToAppear 首载 + 失败重试键——删除走
// 页内即时更新（拍板 4：不设刷新键），无子页编辑无保存动作故不挂 onShown 重进重拉（每次
// push 都是新实例，进页即现读）。
// 删除（拍板 2 + 红线 3/4）：按附件行 id 单件删，行走 ChatDb 委托入口（行 + 文件成对铁律，
// 页面侧不碰文件原语）；库内消息文本里的「[附件] 文件名」标注一字不动，气泡侧照旧显示、
// 点开提示「文件已不在本机」。
// 查看器承载 = **导航栈内二级页**（★ 2026-09-15 二级页化笔；本页前一形态 = 全屏模态
// bindContentCover，再前一形态 = 页内覆盖层）：行点击经共享件 AttachmentUtil.openAttachmentViewer
// push 查看器页（ROUTE_ATTACHMENT_VIEWER_PAGE，页面 = components/chat/AttachmentViewerPage.ets）
// ——页内不再持有查看器状态（原 viewerItems/viewerIndex/viewerOpen 三 @State 与模态挂载链
// 删净），返回归官方返回链。列表行是**类型图标**、无缩略图（决明「附件管理用不了共享元素
// 动画」即在这一点），故本页不写共享元素广播键——键由查看器内部随页写、由查看器页销毁时清。
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PageShell } from '../../common/PageShell';
import { AttachmentBrief, extLabel, formatFileSize, openAttachmentViewer,
  isSystemPreviewKind, openSystemPreview } from '../../common/AttachmentUtil';
import { AttachmentGroupRow, AttachmentListRow,
  AttachmentTotalRow } from '../../common/store/AttachmentDb';
import { deleteAttachments, isReady, queryAttachmentGroups,
  queryAttachmentTotal, queryAttachmentsByConversation } from '../../common/store/ChatDb';
import { CARD_SPACING, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';
import { formatBytes } from '../../common/StorageStats';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg,
  fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect,
  overlayMaterial } from '../../common/ImmersiveLevel';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import { formatConvTime } from '../chat/SessionSearchPanels';

const DOMAIN: number = 0xD5A1;
const TAG: string = 'AttachManage';
// 页名/入口卡名单源（StoragePage 引用同一常量——两处显示名必然一致）
export const ATTACH_MANAGE_TITLE: string = '会话附件';
// 一级分页批大小（会话组数）：首屏一屏略多、单次查询轻量（书内自定口径）
const PAGE_GROUPS: number = 20;
// 二级分页批大小（单组附件件数）：同上
const PAGE_FILES: number = 50;
// 会话标题缺位兜底显示名（库行缺失或标题为空串）
const UNTITLED_CONV: string = '未命名会话';
// 组折叠动画时长（2026-09-17 折叠动画统一笔；官方 FAQ faqs-arkui-769 折叠示例同值 300ms，
// 与价格卡 / 工具卡同形制；助手工具页折叠 2026-09-18 随分类卡重组退役）。★ 本页折叠机制与
// 另两处不同——不是条件渲染
// 而是扁平列表行的增删（LazyForEach 数据源 insertRange/removeRange），animateTo 包的是
// 数据变更：行出现/消失与其余行的让位随之插值
const GROUP_FOLD_ANIM_MS: number = 300;

// 扁平列表项（LazyForEach 单数组三类行：kind = 'group' | 'file' | 'more'）。★ 键含可变展示态
// （规范 §3 主通道「键变重建」）：组头的件数/占用/已载数/展开态随交互与删除变化，键不变则
// LazyForEach 只 diff 不重建，卡面会停在旧值。
interface ManageItem {
  key: string;
  kind: string;
  conversationId: string;
  // 组头行字段
  title: string;
  count: number;
  bytes: number;
  loaded: number;
  expanded: boolean;
  // 文件行字段（absPath = filesDir + 相对 localPath——库内相对、运行时绝对）
  fileId: string;
  messageId: string;
  name: string;
  attachKind: string;
  size: number;
  absPath: string;
  createdAt: number;
}

function groupKeyOf(conversationId: string, count: number, bytes: number, loaded: number,
  expanded: boolean): string {
  return 'g|' + conversationId + '|' + count + '|' + bytes + '|' + loaded + '|' + expanded;
}

function moreKeyOf(conversationId: string): string {
  return 'm|' + conversationId;
}

// 聚合行 → 组头项（未展开：loaded 0 / expanded false）
function groupItemOf(row: AttachmentGroupRow): ManageItem {
  return {
    key: groupKeyOf(row.conversationId, row.count, row.bytes, 0, false),
    kind: 'group',
    conversationId: row.conversationId,
    title: row.title !== '' ? row.title : UNTITLED_CONV,
    count: row.count,
    bytes: row.bytes,
    loaded: 0,
    expanded: false,
    fileId: '', messageId: '', name: '', attachKind: '', size: 0, absPath: '', createdAt: 0
  };
}

// 库行 → 文件项（键 = 附件 id——库内主键稳定，行内容不变）
function fileItemOf(row: AttachmentListRow, filesDir: string): ManageItem {
  return {
    key: 'f|' + row.id,
    kind: 'file',
    conversationId: row.conversationId,
    title: '', count: 0, bytes: 0, loaded: 0, expanded: false,
    fileId: row.id,
    messageId: row.messageId,
    name: row.name,
    attachKind: row.kind,
    size: row.size,
    absPath: filesDir + '/' + row.localPath,
    createdAt: row.createdAt
  };
}

// 组尾「显示更多」项（仅在该组已展开且未取满时存在；点击 = 该组再取一批）
function moreItemOf(group: ManageItem): ManageItem {
  return {
    key: moreKeyOf(group.conversationId),
    kind: 'more',
    conversationId: group.conversationId,
    title: '', count: 0, bytes: 0, loaded: 0, expanded: true,
    fileId: '', messageId: '', name: '', attachKind: '', size: 0, absPath: '', createdAt: 0
  };
}

// 扁平项数据源（LazyForEach 契约）。变更一律走 notifyDataReloaded：键含可变展示态，键变者
// 重建、未变者复用——列表规模有界（已加载组 + 已展开组行），全量通知开销可忽略
class ManageDataSource implements IDataSource {
  private list: ManageItem[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.list.length;
  }

  getData(index: number): ManageItem {
    return this.list[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  // 只读视图（页面侧滑切集合装配 / 计数用）
  items(): ManageItem[] {
    return this.list;
  }

  // 已加载组数 = 下一批聚合查询的 OFFSET（组行与文件行混排，须单独数）
  groupCount(): number {
    let n: number = 0;
    for (const item of this.list) {
      if (item.kind === 'group') {
        n++;
      }
    }
    return n;
  }

  indexOfKey(key: string): number {
    for (let i = 0; i < this.list.length; i++) {
      if (this.list[i].key === key) {
        return i;
      }
    }
    return -1;
  }

  indexOfConversation(conversationId: string): number {
    for (let i = 0; i < this.list.length; i++) {
      if (this.list[i].kind === 'group' && this.list[i].conversationId === conversationId) {
        return i;
      }
    }
    return -1;
  }

  groupOf(conversationId: string): ManageItem | null {
    const index: number = this.indexOfConversation(conversationId);
    return index >= 0 ? this.list[index] : null;
  }

  // 组行区段末尾下标（下一条组头行之前 / 数组末尾）——续批与「显示更多」行的插入点
  groupEndIndex(conversationId: string): number {
    const start: number = this.indexOfConversation(conversationId);
    if (start < 0) {
      return this.list.length;
    }
    for (let i = start + 1; i < this.list.length; i++) {
      if (this.list[i].kind === 'group') {
        return i;
      }
    }
    return this.list.length;
  }

  // 该组当前已加载的附件行数（删除后重算 loaded 用）
  filesOf(conversationId: string): number {
    let n: number = 0;
    for (const item of this.list) {
      if (item.kind === 'file' && item.conversationId === conversationId) {
        n++;
      }
    }
    return n;
  }

  setAll(rows: ManageItem[]): void {
    this.list = rows;
    this.notifyChanged();
  }

  // 追加到数组末尾（一级续批——新组恒排在既有组之后）
  appendItems(rows: ManageItem[]): void {
    if (rows.length === 0) {
      return;
    }
    this.list = this.list.concat(rows);
    this.notifyChanged();
  }

  insertRange(at: number, rows: ManageItem[]): void {
    if (rows.length === 0) {
      return;
    }
    this.list = this.list.slice(0, at).concat(rows, this.list.slice(at));
    this.notifyChanged();
  }

  removeRange(at: number, count: number): void {
    if (count <= 0) {
      this.notifyChanged();
      return;
    }
    this.list = this.list.slice(0, at).concat(this.list.slice(at + count));
    this.notifyChanged();
  }

  // 全量通知（键含可变展示态——键变者重建，未变者复用）
  notifyChanged(): void {
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }
}

@Component
export struct AttachmentManagePage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 路由栈（普通成员——PageMapBuilder 注入；行点击开查看器二级页用）
  pathStack: NavPathStack = new NavPathStack();
  // 首载完成标记（false = 总显「正在统计…」不显 0——官方【推荐】加载态不误导，存储页先例）
  @State private loaded: boolean = false;
  @State private loadFailed: boolean = false;
  // 顶部合计（进页取一次；删除后本地递减——拍板 4 不重复聚合）
  @State private totalFiles: number = 0;
  @State private totalBytes: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 扁平项数据源（普通成员——变更经自身 notify 驱动 LazyForEach，无 @State 需求）
  private source: ManageDataSource = new ManageDataSource();
  // 查询重入闸（首载与一级续批共用；瞬态门闩无 UI 呈现需求）
  private loading: boolean = false;
  // 组内展开/续批在途闸（同刻只允许一个组在查——防连点叠查）
  private groupBusy: boolean = false;
  // 到底即停（一级分页：返回不足一批置位，此后 onReachEnd 不再触发查询——有界红线）
  private groupsExhausted: boolean = false;
  // 删除在途闸
  private deleting: boolean = false;
  // 沙箱根（absPath 拼接用；进页取上下文时写入）
  private filesDir: string = '';
  // 删除确认弹窗（构造在组件成员位——坑7 约束；动态文案经 openDeleteConfirm 重建，
  // 先例 StoragePage.openConfirm）
  private confirmCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: ConfirmDialog({
      title: '删除附件',
      message: '',
      confirmLabel: '删除',
      onConfirm: (): void => {
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });

  aboutToAppear(): void {
    this.load();
  }

  // 首载：聚合第一批（20 组）+ 全局合计并行取（互不依赖）；失败中文 toast + 失败态可重试
  private load(): void {
    if (this.loading) {
      return;
    }
    const ctx: common.Context | undefined =
      this.getUIContext().getHostContext() as common.Context | undefined;
    if (ctx === undefined) {
      this.loadFailed = true;
      this.getUIContext().getPromptAction().showToast({ message: '无法获取应用上下文' });
      return;
    }
    if (!isReady()) {
      this.loadFailed = true;
      this.getUIContext().getPromptAction().showToast({ message: '数据库尚未就绪，请稍后再试' });
      return;
    }
    this.filesDir = ctx.filesDir;
    this.loading = true;
    this.loadFailed = false;
    this.groupsExhausted = false;
    this.source.setAll([]);
    Promise.all([queryAttachmentGroups(PAGE_GROUPS, 0), queryAttachmentTotal()])
      .then((results: [AttachmentGroupRow[], AttachmentTotalRow]): void => {
        const rows: ManageItem[] = [];
        for (const group of results[0]) {
          rows.push(groupItemOf(group));
        }
        this.source.setAll(rows);
        this.totalFiles = results[1].count;
        this.totalBytes = results[1].bytes;
        this.groupsExhausted = results[0].length < PAGE_GROUPS;
        this.loaded = true;
      })
      .catch((e: Object): void => {
        this.loadFailed = true;
        const err: BusinessError = e as BusinessError;
        hilog.error(DOMAIN, TAG, '附件聚合查询失败：code %{public}d %{public}s',
          typeof err.code === 'number' ? err.code : -1, (e as Error).message);
        this.getUIContext().getPromptAction().showToast({
          message: '附件列表加载失败，请重试（code ' + err.code + '）'
        });
      })
      .finally((): void => {
        this.loading = false;
      });
  }

  // 一级续批（List.onReachEnd 触底自动续）：首载未完成/在途/已到底都直接返回；返回不足一批
  // = 到底即停，之后不再触发（有界红线口径）。★ 2026-09-15 全面自检笔补去重：一级排序键是
  // **体积**（可变聚合值）——已加载组被删件后 bytes 回落，在新排序里可能后移，按位置续批
  // 会把已在列表的组再带回来（同一会话出现两个组头、各自独立展开与删除；两卡状态完全一致
  // 时键全同 = LazyForEach 重复键行为未定义）。去重丢弃已加载组；残留限制如实记账 =
  // 「漏组」仍在（漂移使个别未加载组落到本批已消费位置之前即被跳过）——offset 式分页对
  // 可变排序键的固有面，重进页面自愈，结构性收口另议
  private loadMoreGroups(): void {
    if (this.loading || this.groupsExhausted || !this.loaded || this.loadFailed) {
      return;
    }
    this.loading = true;
    queryAttachmentGroups(PAGE_GROUPS, this.source.groupCount())
      .then((rows: AttachmentGroupRow[]): void => {
        if (rows.length < PAGE_GROUPS) {
          this.groupsExhausted = true;
        }
        const items: ManageItem[] = [];
        for (const group of rows) {
          if (this.source.indexOfConversation(group.conversationId) >= 0) {
            continue; // 已在列表（排序漂移回带）——丢弃防重复组头
          }
          items.push(groupItemOf(group));
        }
        this.source.appendItems(items);
      })
      .catch((e: Object): void => {
        const err: BusinessError = e as BusinessError;
        hilog.error(DOMAIN, TAG, '会话分组续批失败：code %{public}d %{public}s',
          typeof err.code === 'number' ? err.code : -1, (e as Error).message);
        this.getUIContext().getPromptAction().showToast({
          message: '加载更多会话失败，请重试（code ' + err.code + '）'
        });
      })
      .finally((): void => {
        this.loading = false;
      });
  }

  // 组头行点击：展开（首次才查）/ 折叠（丢弃该组行对象）
  private toggleGroup(group: ManageItem): void {
    if (group.expanded) {
      this.collapseGroup(group);
    } else {
      this.expandGroup(group);
    }
  }

  private expandGroup(group: ManageItem): void {
    if (this.groupBusy) {
      return;
    }
    if (this.source.indexOfConversation(group.conversationId) < 0) {
      hilog.warn(DOMAIN, TAG, '展开未命中会话组：%{public}s', group.conversationId);
      return;
    }
    this.groupBusy = true;
    queryAttachmentsByConversation(group.conversationId, PAGE_FILES, 0)
      .then((rows: AttachmentListRow[]): void => {
        const at: number = this.source.indexOfConversation(group.conversationId);
        if (at < 0) {
          hilog.warn(DOMAIN, TAG, '展开回填时会话组已不在列表：%{public}s', group.conversationId);
          return;
        }
        const children: ManageItem[] = [];
        for (const row of rows) {
          children.push(fileItemOf(row, this.filesDir));
        }
        // 2026-09-17 折叠动画统一笔：数据变更（子行入列 + 组头键变）包进 animateTo——行出现
        // 与其余行让位随之插值（本页是 LazyForEach 行增删式折叠，非条件渲染）。展开须等
        // 查询返回，动画在数据到位后播（点击不被阻塞）
        this.getUIContext().animateTo({ duration: GROUP_FOLD_ANIM_MS, curve: Curve.EaseInOut },
          (): void => {
            group.loaded = rows.length;
            group.expanded = true;
            group.key = groupKeyOf(group.conversationId, group.count, group.bytes, group.loaded, true);
            // 未取满（或还可能有下批）→ 组尾挂「显示更多」
            if (group.loaded < group.count) {
              children.push(moreItemOf(group));
            }
            this.source.insertRange(at + 1, children);
          });
      })
      .catch((e: Object): void => {
        const err: BusinessError = e as BusinessError;
        hilog.error(DOMAIN, TAG, '单组附件查询失败：code %{public}d %{public}s',
          typeof err.code === 'number' ? err.code : -1, (e as Error).message);
        this.getUIContext().getPromptAction().showToast({
          message: '加载附件列表失败，请重试（code ' + err.code + '）'
        });
      })
      .finally((): void => {
        this.groupBusy = false;
      });
  }

  // 折叠：移出该组全部子行（含「显示更多」行）——行对象即丢弃，再展开重新取第一批。
  // 2026-09-17 折叠动画统一笔：数据变更（子行移出 + 组头键变）包进 animateTo（同展开路）
  private collapseGroup(group: ManageItem): void {
    const at: number = this.source.indexOfConversation(group.conversationId);
    if (at < 0) {
      return;
    }
    const end: number = this.source.groupEndIndex(group.conversationId);
    this.getUIContext().animateTo({ duration: GROUP_FOLD_ANIM_MS, curve: Curve.EaseInOut },
      (): void => {
        group.loaded = 0;
        group.expanded = false;
        group.key = groupKeyOf(group.conversationId, group.count, group.bytes, 0, false);
        this.source.removeRange(at + 1, Math.max(end - at - 1, 0));
      });
  }

  // 组内续批（「显示更多」点击）：新行插在该组「显示更多」行之前，取满则撤掉该行
  private loadMoreFiles(more: ManageItem): void {
    if (this.groupBusy) {
      return;
    }
    const group: ManageItem | null = this.source.groupOf(more.conversationId);
    if (group === null) {
      return;
    }
    const offset: number = group.loaded;
    this.groupBusy = true;
    queryAttachmentsByConversation(more.conversationId, PAGE_FILES, offset)
      .then((rows: AttachmentListRow[]): void => {
        const current: ManageItem | null = this.source.groupOf(more.conversationId);
        const moreIndex: number = this.source.indexOfKey(moreKeyOf(more.conversationId));
        if (current === null || moreIndex < 0) {
          hilog.warn(DOMAIN, TAG, '续批回填时组已变化：%{public}s', more.conversationId);
          return;
        }
        const children: ManageItem[] = [];
        for (const row of rows) {
          children.push(fileItemOf(row, this.filesDir));
        }
        current.loaded += rows.length;
        current.key = groupKeyOf(current.conversationId, current.count, current.bytes,
          current.loaded, true);
        this.source.insertRange(moreIndex, children);
        if (current.loaded >= current.count) {
          // 取满：撤掉「显示更多」行（原下标 + 本批件数 = 该行新下标）
          this.source.removeRange(moreIndex + children.length, 1);
        }
      })
      .catch((e: Object): void => {
        const err: BusinessError = e as BusinessError;
        hilog.error(DOMAIN, TAG, '组内续批失败：code %{public}d %{public}s',
          typeof err.code === 'number' ? err.code : -1, (e as Error).message);
        this.getUIContext().getPromptAction().showToast({
          message: '加载更多附件失败，请重试（code ' + err.code + '）'
        });
      })
      .finally((): void => {
        this.groupBusy = false;
      });
  }

  // 单件删确认（危险操作前置确认——ConfirmDialog 先例；文案走面向用户规约，无冒号分号括号连环）
  private openDeleteConfirm(item: ManageItem): void {
    if (this.deleting) {
      return;
    }
    const message: string = '将删除「' + item.name +
      '」。消息里的附件标注会保留，之后点开会提示文件已不在本机。';
    this.confirmCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '删除附件',
        message: message,
        confirmLabel: '删除',
        onConfirm: (): void => {
          this.doDelete(item);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.confirmCtrl.open();
  }

  // 删除执行：行走 ChatDb 委托入口（附件行 + 文件成对，页面不碰文件原语）→ 成功原地移除；
  // 失败中文 toast 不静默（P0-1）——注意按附件行 id 删（一条消息可挂多件，按 messageId 删
  // 会误伤同消息其余附件）
  private async doDelete(item: ManageItem): Promise<void> {
    if (this.deleting) {
      return;
    }
    this.deleting = true;
    try {
      await deleteAttachments([item.fileId]);
      this.dropFileRow(item);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, '附件删除失败：code %{public}d %{public}s',
        typeof err.code === 'number' ? err.code : -1, (e as Error).message);
      this.getUIContext().getPromptAction().showToast({
        message: '删除失败，请重试（code ' + err.code + '）'
      });
    } finally {
      this.deleting = false;
    }
  }

  // 页内移除单行（拍板 4：删完原地移除不重查库）：文件行移除 → 组头件数/体积递减 → 归零组
  // 行消失 → 顶部合计回落；「显示更多」行按 loaded < count 现算存在性
  private dropFileRow(item: ManageItem): void {
    const index: number = this.source.indexOfKey(item.key);
    if (index < 0) {
      return;
    }
    const group: ManageItem | null = this.source.groupOf(item.conversationId);
    this.source.removeRange(index, 1);
    if (group !== null) {
      group.count = group.count > 0 ? group.count - 1 : 0;
      group.bytes = group.bytes > item.size ? group.bytes - item.size : 0;
      group.loaded = this.source.filesOf(group.conversationId);
      if (group.count === 0) {
        const groupIndex: number = this.source.indexOfConversation(group.conversationId);
        this.source.removeRange(groupIndex, 1);
      } else {
        group.key = groupKeyOf(group.conversationId, group.count, group.bytes, group.loaded,
          group.expanded);
        this.syncMoreRow(group);
      }
    }
    this.totalFiles = this.totalFiles > 0 ? this.totalFiles - 1 : 0;
    this.totalBytes = this.totalBytes > item.size ? this.totalBytes - item.size : 0;
    this.source.notifyChanged();
  }

  // 「显示更多」行存在性同步（删除后可能重新出现——该组又变成未取满）
  private syncMoreRow(group: ManageItem): void {
    const need: boolean = group.expanded && group.loaded < group.count;
    const moreIndex: number = this.source.indexOfKey(moreKeyOf(group.conversationId));
    if (need && moreIndex < 0) {
      this.source.insertRange(this.source.groupEndIndex(group.conversationId), [moreItemOf(group)]);
    } else if (!need && moreIndex >= 0) {
      this.source.removeRange(moreIndex, 1);
    }
  }

  // 点开预览（行点击；删除键另有独立热区）：存在性现检（单次 syscall，非轮询、不做灰态）→
  // 文档类走系统预览共享件 → 图片按「同一会话已加载图片行」滑切 → 文本单件
  private openPreview(item: ManageItem): void {
    if (!fs.accessSync(item.absPath)) {
      // 「行在文件不在」（沿第三轮拍板语义）：点击时现检 + 中文提示
      this.getUIContext().getPromptAction().showToast({ message: '文件已不在本机' });
      return;
    }
    if (isSystemPreviewKind(item.name)) {
      openSystemPreview(this.getUIContext(), item.name, item.absPath);
      return;
    }
    if (item.attachKind === 'image') {
      const scope: AttachmentBrief[] = [];
      for (const row of this.source.items()) {
        if (row.kind === 'file' && row.conversationId === item.conversationId &&
          row.attachKind === 'image') {
          scope.push({
            id: row.fileId, name: row.name, kind: row.attachKind, size: row.size,
            absPath: row.absPath
          });
        }
      }
      const index: number =
        scope.findIndex((brief: AttachmentBrief): boolean => brief.id === item.fileId);
      if (index < 0) {
        hilog.warn(DOMAIN, TAG, '图片滑切集合未命中点击件：%{public}s', item.fileId);
        return;
      }
      this.openViewer(scope, index);
    } else {
      this.openViewer([{
        id: item.fileId, name: item.name, kind: item.attachKind, size: item.size,
        absPath: item.absPath
      }], 0);
    }
  }

  // 打开查看器（二级页 push 单点收敛）：★ 本页不写共享广播键——列表行是**类型图标**、无缩略图
  // （决明「附件管理用不了共享元素动画」即在这一点），键由查看器内部随页写、由查看器页销毁时清；
  // push 与连点防重入在共享件 openAttachmentViewer 内（与会话页共用同一入口）
  private openViewer(items: AttachmentBrief[], startIndex: number): void {
    openAttachmentViewer(this.pathStack, items, startIndex);
  }

  // 顶部合计文本（加载态不显 0；失败显失败——存储页同口径）
  private summaryText(): string {
    if (this.loadFailed) {
      return '统计失败';
    }
    if (!this.loaded) {
      return '正在统计…';
    }
    return '共 ' + this.totalFiles + ' 件，合计 ' + formatBytes(this.totalBytes);
  }

  // ── 列表行 ──
  // 组头行（整卡可点 = 展开/折叠；右侧 = 件数与占用）
  @Builder
  GroupRow(item: ManageItem) {
    Button() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(16)
          .fontColor([cardDescColor()])
          .rotate({ angle: item.expanded ? 180 : 0 })
        Text(item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(item.count + ' 件 · ' + formatBytes(item.bytes))
          .fontSize(13)
          .fontColor(cardDescColor())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .type(ButtonType.Normal)
    .width('100%')
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .padding(14)
    .onClick((): void => {
      this.toggleGroup(item);
    })
  }

  // 附件行（整卡可点 = 预览；右上删除键独立热区不串——先例 ChatAttachmentStrip 两热区）。
  // 名称 + 类型/大小/时间副行；不渲染缩略图（解码成本与内存有界优先，书 §2.2 展示面）
  @Builder
  FileRow(item: ManageItem) {
    Button() {
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text(item.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(extLabel(item.name) + ' · ' + formatFileSize(item.size) + ' · ' +
            formatConvTime(item.createdAt))
            .fontSize(13)
            .fontColor(cardDescColor())
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        // 行内图标键（删除类）：无底 TEXTUAL + font_secondary，禁四件套——行内按钮规范 §1 表
        Button() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .onClick((): void => {
          this.openDeleteConfirm(item);
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .type(ButtonType.Normal)
    .width('100%')
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .padding(14)
    .onClick((): void => {
      this.openPreview(item);
    })
  }

  // 组尾「显示更多」行（内容区文字键 = fallbackButton* 双态，行内按钮规范 §1 表第 2 行；
  // 单键不套卡片——列表卡片规范 §4.3「单键禁独立卡」）
  @Builder
  MoreRow(item: ManageItem) {
    Row() {
      Button('显示更多')
        .fontColor(fallbackButtonFont(this.contentFallback, true))
        .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .onClick((): void => {
          this.loadMoreFiles(item);
        })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 4, bottom: 4 })
  }

  // 页级空态卡（列表卡片规范 §4.3：整页无数据仍用卡承载，卡宽随宿主 padding = 全宽）
  @Builder
  EmptyCard() {
    Column({ space: 6 }) {
      Text('还没有已发送的附件')
        .fontSize(15)
        .fontColor(cardTitleColor())
      Text('在会话里发送图片或文档后，会出现在这里')
        .fontSize(13)
        .fontColor(cardDescColor())
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Center)
  }

  // 失败态卡（三条失败路径同置 loadFailed；重试走 load 单一路径——P0-1 不静默不假成功）
  @Builder
  FailCard() {
    Column({ space: 10 }) {
      Text('附件列表加载失败')
        .fontSize(15)
        .fontColor(cardTitleColor())
      Button('重试')
        .fontColor(fallbackButtonFont(this.contentFallback, true))
        .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .onClick((): void => {
          this.load();
        })
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  Content() {
    // 列表页骨架（同族：ProviderPage/SearchEnginePage/MemorySortPage/自检页等）：Stack 顶
    // 对齐承载滚动层；滚动层 List 铺满整页、顶/底留白走官方 offset——内容上滚
    // 滑入标题栏渐变模糊蒙层背后被透出 = 顶部光感接上（2026-09-15 决明报障修复）
    // ★ 2026-09-15 查看器二级页化笔后本 Stack 只承载滚动层（原为查看器全屏模态挂载点，
    // 模态随本笔退役）
    // ★ 合计条**随内容滚动**（List 首项，不悬浮）：纯信息行不做悬浮件——固定条与滚上来的
    // 卡片观感割裂（2026-09-15 决明真机指令；同族悬浮件一律是交互件〔分段胶囊〕，纯信息行
    // 无悬浮先例，勿回迁）
    Stack({ alignContent: Alignment.Top }) {
      // 滚动层 = List 铺满整页；失败/空态同为 **List 内条件项**（不在 List 外另立分支：
      // 短内容也上下可拖、回弹时短暂滑入标题栏蒙层——SearchEnginePage 空态条件项同款
      // 定稿口径）；触底自动续批由 onReachEnd 触发，守卫（加载中/到底停/首载未完成）
      // 全在 loadMoreGroups 内
      // ★ 官方 LazyForEach 使用限制「不建议容器内混排 ListItem / ForEach / LazyForEach」
      //（2026-09-15 自检轮查证）：本页为「固定前导项 + 条件项」形态，先例同款 = 消息列表
      //（ChatPageContent 同结构，真机长期在用）——若真机出现滚动/复用异常，此项列第一
      // 嫌疑；换法 = 特殊行并入数据源 kind，使 List 内只剩 LazyForEach
      List({ space: CARD_SPACING }) {
        // 顶部合计（首项，随内容滚动；左内距由 List 的左右 padding 统一承担）
        ListItem() {
          Text(this.summaryText())
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
            .padding({ top: 8, bottom: 8 })
        }
        LazyForEach(this.source, (item: ManageItem): void => {
          ListItem() {
            if (item.kind === 'group') {
              this.GroupRow(item)
            } else if (item.kind === 'more') {
              this.MoreRow(item)
            } else {
              this.FileRow(item)
            }
          }
        }, (item: ManageItem): string => item.key)
        if (this.loadFailed) {
          ListItem() {
            this.FailCard()
          }
        } else if (this.loaded && this.source.totalCount() === 0) {
          ListItem() {
            this.EmptyCard()
          }
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16 })
      // ★ 顶/底留白走官方 offset（留白属滚动内容；容器 padding = 视口缩进会裁掉内容
      //   ——坑9 根因，见 Content 头注释，勿回迁）
      .contentStartOffset(Math.max(this.topPad, 0))
      .contentEndOffset(this.bottomPad + 16)
      // 滚动内容不足视口时顶对齐（坑18：List/Scroll align 默认可垂直居中）+ 短内容
      // 也上下可拖（回弹时内容短暂滑入标题栏蒙层、光感可见——ProviderPage 同款口径）
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
      .onReachEnd((): void => {
        this.loadMoreGroups();
      })

      // 附件查看器（★ 2026-09-15 二级页化笔：改导航栈内二级页 push——本层不再挂弹层/模态，
      // 文档类不进查看器，分派直走系统预览窗）
    }
    .width('100%')
    .height('100%')
  }

  build() {
    PageShell({
      title: ATTACH_MANAGE_TITLE,
      content: (): void => {
        this.Content();
      }
    })
  }
}
