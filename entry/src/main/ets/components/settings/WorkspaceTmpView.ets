// 临时产物区视图件（工作区管理页「临时」段承载）：
// · 顶层会话组卡（标题三态反查复用会话视图「正常 / 已删除的会话 / 未命名会话」逻辑形态——孤儿
//   临时目录〔会话已删但级联漏网〕因此可见可清）→ 点卡下探文件行（行菜单两动作 = 保存〔转存正式
//   工作区〕/ 删除）；组卡行菜单「清理」；段级「清理临时区」在页标题栏「更多」菜单（父页编排，
//   经 @Link 广播键 reloadTick 回本件 assemble 重扫——刷新白名单形态，@Prop 下发黑名单规避）。
// · 数据面与文件夹/会话两视图分叉（不并入 WorkspaceSessionView）：扫盘驱动非表驱动（临时区三不
//   红线——不进 workspace_files 表），自带转存/清理动作面；首扫 + 动作后重扫，不经父页 rows @Link。
// · 下探层级显示上收页顶 WorkspaceBreadcrumbBar：本件经 onDrillChange 上行段数组（上行点 = 组卡
//   点击下探 / exitDrill / assemble 发现下探组消失自动回退）；页顶条点「工作区/临时」段经下行
//   广播键 exitTick 触发 exitDrill。未下探上报根态常量 WORKSPACE_TMP_ROOT_SEGS（本件导出），页顶
//   条全态亮起；下探两态 drilled/openedId 仍本件自持有——只桥接显示层。
// · 标题反查 = ChatDb.queryConversationTitlesByIds（令牌防先发后到 + aboutToDisappear 置
//   disposed）；反查失败降级「未命名会话」不谎报已删除。
// · 动作经 ChatDb 委托口（clearWorkspaceTmpAllOp / deleteWorkspaceTmpConversationOp /
//   deleteWorkspaceTmpFileOp / promoteWorkspaceTmpFileOp）；转存成功经 onMutated 让父页重载
//  （纯清理动作不动工作区表，不回调）。
// · 空态文案即预期管理（exec_code 已落地、临时段有真实写入方——空态仅出现在尚无脚本运行过的新会话）。
// ★ 统计行「共 N 个会话 · 占用 X」退役（总占用在页标题栏「更多」菜单「数据总览」，同屏不两处显示
//   同一数据）；动作键收菜单（文件行「保存/删除」与组卡「清理」→ 行尾四点键菜单，形制照
//   WorkspaceListRows 行卡族）——全部「换位不换链」，转存/删除/清理四委托口零改动。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { deleteWorkspaceTmpConversationOp, deleteWorkspaceTmpFileOp,
  listWorkspaceTmpGroups, listWorkspaceTmpFiles,
  promoteWorkspaceTmpFileOp } from '../../common/store/ChatDb';
import { queryConversationTitlesByIds } from '../../common/store/ChatDbReadSearch';
import { WORKSPACE_TMP_LIST_MAX, WorkspaceTmpGroupBrief, WorkspaceTmpScan }
  from '../../common/WorkspaceTmpUtil';
import { formatWorkspaceSize } from '../../common/WorkspaceUtil';
import {
 CARD_SPACING, cardBg, cardDescColor, cardTitleColor,
  menuDividerColor, CARD_RADIUS
} from '../../common/Theme';
import { IMMERSIVE_LEVEL_KEY, resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { formatConvTime } from '../chat/SessionSearchPanels';
import { WorkspaceCrumbSeg } from './WorkspaceBreadcrumb';
import { WorkspaceTmpSelectRow } from './WorkspaceMultiselect';
import { WorkspaceEmptyHint } from './WorkspaceListRows';
import { InfoCard } from '../InfoCard';

const DOMAIN: number = 0xD5A7;
const TAG: string = 'WorkspaceTmp';

// 多选态列表尾让位（vp；与 WorkspaceFolderView / ChatSessionRows 同值 56，禁跨件 import 私有常量）
const MULTISELECT_BAR_CLEARANCE: number = 56;

// 临时段根态段数组（未下探即由页面上报本常量——页顶条亮起显示「工作区 > 临时」两段，尾段 =
// 当前层加粗不可点，与文件夹段根目录亮「工作区」同构；下探后由 reportDrill 上行三段覆盖，退出
// 下探回到本值。target 恒 ''，根态「工作区」段跳转语义 = 页面分派切段。只读共享：消费面仅
// 页面 @State 赋值与条体渲染，无 mutate 面）
export const WORKSPACE_TMP_ROOT_SEGS: WorkspaceCrumbSeg[] = [
  { key: '工作区|false', text: '工作区', target: '', isLast: false },
  { key: '临时|true', text: '临时', target: '', isLast: true }
];

// 组列表行载荷（标题已解析的视图模型；键含全部可变展示成分——坑44/坑16 家族）
interface TmpGroupEntry {
  key: string;
  conversationId: string;
  title: string;
  fileCount: number;
  bytes: number;
  lastAt: number;
}

// 文件行载荷（key = 会话 id + 名 + 大小 + 时间全成分）
interface TmpFileEntry {
  key: string;
  conversationId: string;
  name: string;
  size: number;
  mtime: number;
}

// 组列表数据源（LazyForEach 契约同 WorkspaceRowsSource——行类型不同故本件自持一份）
class TmpGroupSource implements IDataSource {
  private rows: TmpGroupEntry[] = [];
  private listeners: DataChangeListener[] = [];

  reload(entries: TmpGroupEntry[]): void {
    this.rows = entries;
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }

  // 重载通知口（新增；不动数据、只重派 onDataReloaded——多选态两态/勾选变化后让 LazyForEach 按
  // **键**重算复用/新建。与 reload 分工勿混：reload = 数据换，refresh = 只重算键）
  refresh(): void {
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): TmpGroupEntry {
    return this.rows[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }
}

// 文件行数据源（同上契约）
class TmpFileSource implements IDataSource {
  private rows: TmpFileEntry[] = [];
  private listeners: DataChangeListener[] = [];

  reload(entries: TmpFileEntry[]): void {
    this.rows = entries;
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }

  // 重载通知口（语义同 TmpGroupSource.refresh）
  refresh(): void {
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): TmpFileEntry {
    return this.rows[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }
}

@Component
export struct WorkspaceTmpView {
  // 顶部让位（父页 contentTop() 算好传入——创建期定值）
  @Prop topPad: number = 0;
  // 底部让位（导航壳下发）
  @Prop bottomPad: number = 0;
  // 转存成功回调（父页重载两表驱动段——纯清理动作不触发）
  onMutated: () => void = (): void => {
  };
  // 下探层级上行（段数组上报父页 tmpCrumbSegs 驱动页顶条覆盖源；退出下探上行根态常量。上行点 =
  // 组卡点击下探 reportDrill / exitDrill——assemble 组消失自动回退经 exitDrill 委托）
  onDrillChange: (segs: WorkspaceCrumbSeg[]) => void = (segs: WorkspaceCrumbSeg[]): void => {
  };
  // 下探两态（照 WorkspaceSessionView：'' 为合法组目标哨兵拆两态）
  @State private drilled: boolean = false;
  @State private openedId: string = '';
  @State private groups: TmpGroupEntry[] = [];
  @State private fileEntries: TmpFileEntry[] = [];
  // 下探列表越列举上限截断（列表尾如实申报说明行的显隐——WorkspaceTmpScan.truncated 消费位）
  @State private fileTruncated: boolean = false;
  // 重扫广播键（父页「清理临时区」执行后自增——@Link + @Watch 驱动重扫；只承载「变了」信号，值无语义）
  @Link @Watch('onReloadTick') reloadTick: number;
  // 下探退出广播键（页顶条临时段可点段触发，本件消费触发 exitDrill；drilled 守卫为冗余防御）
  @Link @Watch('onExitTick') exitTick: number;
  // ── 多选两态（壳侧下行 @Link；@Watch 收敛 = 重派数据源刷新 + 进入多选上行行集；点卡只切换勾选）──
  @Link @Watch('onSelectStateChanged') selectMode: boolean;
  @Link @Watch('onSelectStateChanged') selectedKeys: string[];
  // 勾选切换上行（壳侧 toggleSelectKey 单源；入参 = 行基础键）
  onToggle: (key: string) => void = (_key: string): void => {
  };
  // 当前层行载荷上行（壳侧多选可见集 / 全选 / 批量删除反查的输入；上行点 = refreshOpenedFiles +
  // 进入多选补报）
  onSelectRows: (rows: WorkspaceTmpSelectRow[]) => void =
    (_rows: WorkspaceTmpSelectRow[]): void => {
    };
  // 系统颜色模式（卡底配色）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  private groupSource: TmpGroupSource = new TmpGroupSource();
  private fileSource: TmpFileSource = new TmpFileSource();
  // 标题反查令牌 + 销毁标志
  private loadSeq: number = 0;
  private disposed: boolean = false;
  // 动作在途闸（转存涉及拷贝与落库；防连点）
  private promoting: boolean = false;

  aboutToAppear(): void {
    this.assemble();
  }

  aboutToDisappear(): void {
    this.disposed = true;
  }

  // 重扫广播键消费（父页「清理临时区」执行后触发）
  private onReloadTick(): void {
    this.assemble();
  }

  // 下探退出广播键消费（父页页顶条临时段可点段触发；drilled 守卫防冗余动作）
  private onExitTick(): void {
    if (this.drilled) {
      this.exitDrill();
    }
  }

  // ── 多选（★ 2026-10-09 临时段多选笔）──

  private isSelected(key: string): boolean {
    return this.selectedKeys.indexOf(key) >= 0;
  }

  // 行键生成器（多选态并入模式位与勾选位——键须含该行全部可变展示成分，坑44 两问；常态 = 基础键）
  private groupRowKey(item: TmpGroupEntry): string {
    if (!this.selectMode) {
      return item.key;
    }
    return item.key + '|m1|' + (this.isSelected(item.key) ? '1' : '0');
  }

  private fileRowKey(item: TmpFileEntry): string {
    if (!this.selectMode) {
      return item.key;
    }
    return item.key + '|m1|' + (this.isSelected(item.key) ? '1' : '0');
  }

  // 多选态变化收敛（@Watch 即键驱动刷新的唯一入口）：重派两数据源重载通知（勾选位在键里）+ 进入
  // 多选补报行集
  private onSelectStateChanged(): void {
    this.groupSource.refresh();
    this.fileSource.refresh();
    if (this.selectMode) {
      this.reportSelectRows();
    }
  }

  // 当前层选中行载荷上行（selectMode 关闭时不上行）。组级 size = 组占用字节、文件级 = 文件字节
  private reportSelectRows(): void {
    if (!this.selectMode) {
      return;
    }
    const rows: WorkspaceTmpSelectRow[] = [];
    if (this.drilled) {
      for (const f of this.fileEntries) {
        rows.push({ key: f.key, conversationId: f.conversationId, name: f.name,
          size: f.size, isGroup: false });
      }
    } else {
      for (const g of this.groups) {
        rows.push({ key: g.key, conversationId: g.conversationId, name: '',
          size: g.bytes, isGroup: true });
      }
    }
    this.onSelectRows(rows);
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  // 装配：扫盘（同步）→ 标题反查（异步，令牌守卫）→ 落组列表；下探目标组消失自动回组列表（防死路）
  private assemble(): void {
    this.loadSeq++;
    const seq: number = this.loadSeq;
    const scan: WorkspaceTmpGroupBrief[] = listWorkspaceTmpGroups();
    if (this.drilled && !this.hasGroup(scan, this.openedId)) {
      // 下探目标组消失（清空/级联删）：统一走 exitDrill（含层级上行根态，页顶条同步回落）
      this.exitDrill();
    }
    const ids: string[] = [];
    for (const group of scan) {
      ids.push(group.conversationId);
    }
    queryConversationTitlesByIds(ids)
      .then((titles: Map<string, string>): void => {
        if (seq !== this.loadSeq || this.disposed) {
          return;
        }
        this.applyGroups(scan, titles, true);
      })
      .catch((e: Object): void => {
        if (seq !== this.loadSeq || this.disposed) {
          return;
        }
        hilog.warn(DOMAIN, TAG, '临时组标题反查失败（降级未命名）：%{public}s',
          (e as Error).message);
        this.applyGroups(scan, new Map<string, string>(), false);
      });
  }

  private hasGroup(groups: WorkspaceTmpGroupBrief[], conversationId: string): boolean {
    for (const group of groups) {
      if (group.conversationId === conversationId) {
        return true;
      }
    }
    return false;
  }

  // 反查结果合并（三态标题：命中 / 已删除的会话〔仅反查成功时成立〕/ 未命名会话）
  private applyGroups(scan: WorkspaceTmpGroupBrief[], titles: Map<string, string>,
    titlesResolved: boolean): void {
    const view: TmpGroupEntry[] = [];
    for (const group of scan) {
      const hit: string | undefined = titles.get(group.conversationId);
      let title: string = '未命名会话';
      if (hit !== undefined && hit !== '') {
        title = hit;
      } else if (hit === undefined) {
        title = titlesResolved ? '已删除的会话' : '未命名会话';
      }
      view.push({ key: 't|' + group.conversationId + '|' + title + '|' + group.fileCount +
        '|' + group.bytes + '|' + group.lastAt, conversationId: group.conversationId,
        title: title, fileCount: group.fileCount, bytes: group.bytes, lastAt: group.lastAt });
    }
    this.groups = view;
    this.groupSource.reload(view);
    this.refreshOpenedFiles();
  }

  // 下探文件行重派生（扫盘现值；会话 id 由组列表派生保证有效）。truncated 随扫盘消费——越列举
  // 上限时列表尾如实申报
  private refreshOpenedFiles(): void {
    if (!this.drilled) {
      this.fileTruncated = false;
      this.fileEntries = [];
      this.fileSource.reload([]);
      this.reportSelectRows();
      return;
    }
    const scan: WorkspaceTmpScan = listWorkspaceTmpFiles(this.openedId);
    const entries: TmpFileEntry[] = [];
    for (const f of scan.files) {
      entries.push({ key: this.openedId + '|' + f.name + '|' + f.size + '|' + f.mtime,
        conversationId: this.openedId, name: f.name, size: f.size, mtime: f.mtime });
    }
    this.fileEntries = entries;
    this.fileTruncated = scan.truncated;
    this.fileSource.reload(entries);
    this.reportSelectRows();
  }

  // ── 动作 ──
  // 转存「保存」键：编排全在委托口（闸拒绝中文透传）；成功 toast 终名 + 重扫 + 通知父页重载
  private async promoteFile(item: TmpFileEntry): Promise<void> {
    if (this.promoting) {
      return;
    }
    this.promoting = true;
    try {
      const outcome = await promoteWorkspaceTmpFileOp(item.conversationId, item.name);
      if (!outcome.ok) {
        this.showToast('保存失败，' + outcome.errorText);
        return;
      }
      this.showToast('已保存为「' + outcome.displayName + '」');
      this.assemble();
      this.onMutated();
    } catch (e) {
      this.showToast('保存失败，' + (e as Error).message);
    } finally {
      this.promoting = false;
    }
  }

  // 删除单件（临时件是中间产物，无确认弹窗——任务书 §四动作面；best-effort 后重扫）
  private removeFile(item: TmpFileEntry): void {
    deleteWorkspaceTmpFileOp(item.conversationId, item.name);
    this.assemble();
  }

  // 组卡「清理」键（删该会话整个临时目录；无确认——「清理临时区」才带弹窗，任务书 §3.3-2）
  private clearGroup(item: TmpGroupEntry): void {
    deleteWorkspaceTmpConversationOp(item.conversationId);
    this.assemble();
  }

  // 下探段数组上报：三段「工作区 > 临时 > 会话标题」。target 恒 ''（跳转语义父页按段位分派）；
  // key = text|isLast 已含全部可变展示成分。title 用组卡上行时点已解析标题（下探中无改名入口）
  private reportDrill(title: string): void {
    const segs: WorkspaceCrumbSeg[] = [
      { key: '工作区|false', text: '工作区', target: '', isLast: false },
      { key: '临时|false', text: '临时', target: '', isLast: false },
      { key: title + '|true', text: title, target: '', isLast: true }
    ];
    this.onDrillChange(segs);
  }

  // 前段点击统一回组列表（临时段只有一层下探，无更浅目标）；页顶条可点段（经 exitTick）与组消失
  // 自动回退共用本出口。退出即上报根态常量——页顶条保持亮起显示「工作区 > 临时」
  private exitDrill(): void {
    this.drilled = false;
    this.openedId = '';
    this.refreshOpenedFiles();
    this.onDrillChange(WORKSPACE_TMP_ROOT_SEGS);
  }

  // 勾选圈（多选态；WorkspaceListRows 行卡族 CheckKeyBuilder 同构）：官方 Checkbox +
  // hitTestBehavior(None) 纯视觉指示器，点击穿透落到卡 onClick 切换勾选（坑5）；40vp 占位防行宽跳
  @Builder
  CheckKeyBuilder(selected: boolean) {
    Column() {
      Checkbox()
        .select(selected)
        .hitTestBehavior(HitTestMode.None)
    }
    .height(40)
    .justifyContent(FlexAlign.Center)
  }

  // ── 组卡（组列表态）：图标 + 标题 + 件数 · 大小 · 最近时间；整卡可点下探，行尾四点键菜单
  //「清理」（行内图标键 TEXTUAL 无底 + bindMenu THIN 材质，宪法「行内图标键」形制）；多选态行尾
  // 键换勾选圈（两态互斥）、点卡 = 切换勾选──
  @Builder
  TmpGroupMenu(item: TmpGroupEntry) {
    Menu() {
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')),
        content: '清理' })
        .onClick((): void => {
          this.clearGroup(item);
        })
    }
    .menuItemDivider({
      color: menuDividerColor(this.appColorMode),
      mode: DividerMode.EMBEDDED_IN_MENU
    })
  }

  @Builder
  TmpGroupCard(item: TmpGroupEntry) {
    // 卡底 Column + 四周 padding 4 = 蒙层距卡外圈 4vp（壳 padding 回添，几何零位移）
    Column() {
      Button() {
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.message'))
            .fontSize(20)
            .fontColor([cardDescColor()])
          Column({ space: 3 }) {
            Text(item.title)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(item.fileCount + ' 个文件 · ' + formatWorkspaceSize(item.bytes) + ' · ' +
              formatConvTime(item.lastAt))
              .fontSize(13)
              .fontColor(cardDescColor())
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if (this.selectMode) {
            this.CheckKeyBuilder(this.isSelected(item.key))
          } else {
            Button() {
              SymbolGlyph($r('sys.symbol.ellipsis_circle'))
                .fontSize(18)
                .fontColor([$r('sys.color.font_secondary')])
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .bindMenu(this.TmpGroupMenu(item), {
              placement: Placement.BottomRight,
              systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
                this.immersiveLevel, true)
            })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .type(ButtonType.Normal)
      .width('100%')
      .backgroundColor(Color.Transparent)
      .borderRadius(CARD_RADIUS)
      .padding(10)
      .onClick((): void => {
        // 多选态点卡 = 切换勾选（下探动作让位——切换语义并入行点击，文件夹段行卡同款）
        if (this.selectMode) {
          this.onToggle(item.key);
          return;
        }
        this.drilled = true;
        this.openedId = item.conversationId;
        // 下探层级上报页顶条（★ 面包屑复用笔：title 取组卡载荷已解析标题）+ 文件行装配
        this.reportDrill(item.title);
        this.refreshOpenedFiles();
      })
    }
    .width('100%')
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  // ── 文件行卡：图标 + 名 + 大小 · 时间 + 行尾四点键菜单「保存 / 删除」（形制同组卡；两动作均
  // 无确认弹窗——临时件是中间产物）；多选态行尾键换勾选圈、点卡 = 切换勾选──
  @Builder
  TmpFileMenu(item: TmpFileEntry) {
    Menu() {
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_down_to_line')),
        content: '保存' })
        .onClick((): void => {
          this.promoteFile(item);
        })
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')),
        content: '删除' })
        .onClick((): void => {
          this.removeFile(item);
        })
    }
    .menuItemDivider({
      color: menuDividerColor(this.appColorMode),
      mode: DividerMode.EMBEDDED_IN_MENU
    })
  }
  @Builder
  TmpFileCard(item: TmpFileEntry) {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(20)
        .fontColor([cardDescColor()])
      Column({ space: 3 }) {
        Text(item.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        // 来源标注：宿主溢出件名恒以 exec-output- 开头，据此标「脚本输出」——判据在渲染侧、零 DB
        // 零物理改动；不设写入侧拒写（脚本写同前缀名不拦，风险限于标注轻微失真）
        Text(formatWorkspaceSize(item.size) + ' · ' + formatConvTime(item.mtime) +
          (item.name.indexOf('exec-output-') === 0 ? ' · 脚本输出' : ''))
          .fontSize(13)
          .fontColor(cardDescColor())
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.selectMode) {
        this.CheckKeyBuilder(this.isSelected(item.key))
      } else {
        Button() {
          SymbolGlyph($r('sys.symbol.ellipsis_circle'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .bindMenu(this.TmpFileMenu(item), {
          placement: Placement.BottomRight,
          systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
            this.immersiveLevel, true)
        })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(14)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .onClick((): void => {
      // 多选态点卡 = 切换勾选（普通态 = 无动作——本行动作全在行尾菜单键，勿把点击派给别的）
      if (this.selectMode) {
        this.onToggle(item.key);
      }
    })
  }

  build() {
    if (!this.drilled) {
      // 组列表态：说明小字 + 组卡列表 + 空态（尚无脚本运行过的新会话即空态，文案即预期管理）。
      // 统计行与段级清理键退役——总占用归标题栏「更多」菜单「数据总览」，段级清理归同菜单项
      List({ space: CARD_SPACING }) {
        ListItem() {
          InfoCard({ text: '临时文件是助手运行脚本产生的中间文件，按会话分组。删除对应会话时会一并删除。', fullWidth: true })
        }
        .padding({ bottom: 8 })

        LazyForEach(this.groupSource, (item: TmpGroupEntry): void => {
          ListItem() {
            this.TmpGroupCard(item)
          }
        }, (item: TmpGroupEntry): string => this.groupRowKey(item))

        if (this.groups.length === 0) {
          ListItem() {
            WorkspaceEmptyHint({
              main: '暂无临时文件',
              sub: '助手运行脚本产生的中间文件会按会话显示在这里。'
            })
          }
          .width('100%')
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16 })
      .contentStartOffset(Math.max(this.topPad, 0))
      // 多选态尾部追加批量条让位（56 = MULTISELECT_BAR_CLEARANCE——批量条悬浮贴底，不加让位则末卡被遮）
      .contentEndOffset(this.bottomPad + 16 + (this.selectMode ? MULTISELECT_BAR_CLEARANCE : 0))
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
    } else {
      // 下探态：该会话临时文件行（层级显示上收页顶条，让位算式 topPad 不变）
      List({ space: CARD_SPACING }) {
        LazyForEach(this.fileSource, (item: TmpFileEntry): void => {
          ListItem() {
            this.TmpFileCard(item)
          }
        }, (item: TmpFileEntry): string => this.fileRowKey(item))

        // 截断如实申报（列表只显前 N 件、删除仍作用于全量——契约见 WorkspaceTmpUtil）
        if (this.fileTruncated) {
          ListItem() {
            Text('临时文件较多，仅显示最近修改的前 ' + WORKSPACE_TMP_LIST_MAX + ' 个。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width('100%')
          }
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16 })
      .contentStartOffset(Math.max(this.topPad, 0))
      // 多选态尾部追加批量条让位（56 = MULTISELECT_BAR_CLEARANCE，同前）
      .contentEndOffset(this.bottomPad + 16 + (this.selectMode ? MULTISELECT_BAR_CLEARANCE : 0))
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
    }
  }
}
