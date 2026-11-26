// 工作区会话聚合视图件：管理页「会话」段承载——按会话聚合助手保存的文件（组列表）+ 会话内
// 文件下探（页内二级，不 push 新页）。
// · 数据面：父页持全表 rows（@Link 整表新数组 + @Watch 重派生——PageShell.content 内 hot 值禁
//   @Prop〔坑16〕，@Link 是指定通道；topPad/bottomPad 首帧快照常量用 @Prop 正当）；动作经回调
//   上抛页面统一执行（零删除零上传链）。
// · 装配两入口 = aboutToAppear 首装配（@Watch 不对初值触发）+ onRowsChanged；标题反查 =
//   queryConversationTitlesByIds（IN 一次查回），令牌防先发后到 + disposed 防销毁后写状态；
//   反查失败降级「未命名会话」+ hilog 不阻断（不谎报已删除）。
// · 组行与会话文件行载荷异构，双源分置；文件行复用 WorkspaceListRows 行卡（副行带位置前缀）。
// · 会话段识别文字入口（2026-10-31 补口）：行态派生（ocrStateOf）与动作（onOcr）经父页透传
//   域件 WorkspaceOcrActions——与文件夹段同链，完成后自动进查看页同享；态位刷新经 ocrTick
//   广播键 @Link + @Watch 重派生下探行集（键含 ocrState——坑44）。
// · 会话三态标题：正常 / 已删除（反查缺失，仅反查成功时成立）/ 未命名（标题空串）；未关联组
//   （conversationId === ''，覆盖上传件与恢复件）恒末位。
// · 组行键 = 会话标识 + 全部可变展示成分（标题/件数/大小/最近时间）——LazyForEach 行卡唯一更新
//   路径 = 键变重建，键漏项 = 卡面静默定格（坑44/坑16 家族）。
// · 下探两态（drilled + openedId）：原单串哨兵「'' = 组列表」与「未关联会话」组的 conversationId
//   '' 相撞（@State 赋同值不重渲）；拆后 '' 是合法下探目标，该组与其他组同权（删空自动回列表）。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { queryConversationTitlesByIds } from '../../common/store/ChatDbReadSearch';
import { workspaceFilesDir } from '../../common/store/WorkspaceDb';
import { WorkspaceFileRow, WorkspaceSessionGroup, deriveWorkspaceSessionFiles,
  deriveWorkspaceSessionGroups, formatWorkspaceSize } from '../../common/WorkspaceUtil';
import { CARD_SPACING, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';
import { formatConvTime } from '../chat/SessionSearchPanels';
import { WorkspaceListEntry, WorkspaceNavCard, WorkspaceFileRowCard,
  WorkspaceRowsSource, workspaceEntryKey } from './WorkspaceListRows';

const DOMAIN: number = 0xD5A6;
const TAG: string = 'WorkspaceSession';

// 组列表行载荷（标题已解析的会话组视图模型；本件私有——会话行不复用 WorkspaceListEntry）
interface WorkspaceSessionEntry {
  key: string; // 's|' + conversationId + 全部可变展示成分（键漏项 = 卡面定格——见头注释修复笔）
  conversationId: string;
  title: string;
  fileCount: number;
  bytes: number;
  lastAt: number;
}

// 组列表数据源（LazyForEach 契约同 WorkspaceRowsSource——行类型不同故自持一份，泛型化不划算）
class SessionRowsSource implements IDataSource {
  private rows: WorkspaceSessionEntry[] = [];
  private listeners: DataChangeListener[] = [];

  reload(entries: WorkspaceSessionEntry[]): void {
    this.rows = entries;
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): WorkspaceSessionEntry {
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
export struct WorkspaceSessionView {
  // 全表行集（父页 @State rows 整表重赋驱动重派生；@Link 下传用 $rows 官方写法）
  @Link @Watch('onRowsChanged') rows: WorkspaceFileRow[];
  // 识别态位广播键（父页识别文字域件态位刷新后自增；@Link + @Watch 重派生下探行集——@Prop
  // 下发黑名单。值无语义，只承载「变了」信号）
  @Link @Watch('onOcrTickChanged') ocrTick: number;
  // 顶部让位（父页 contentTop() 算好传入；创建期定值，首帧快照型常量）
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // ── 动作回调（页面统一执行；scope = 滑切可见集〔当前会话文件项〕——图片预览只滑本层）──
  onPreview: (entry: WorkspaceListEntry, scope: WorkspaceListEntry[]) => void =
    (entry: WorkspaceListEntry, scope: WorkspaceListEntry[]): void => {
    };
  onShare: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  onRename: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  onMove: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  onDelete: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  // 识别文字动作上行（父页透传域件 WorkspaceOcrActions 编排；'running' 态壳侧守卫点击无效）
  onOcr: (entry: WorkspaceListEntry) => void = (entry: WorkspaceListEntry): void => {
  };
  // 行识别态位派生回调（父页透传域件 stateOf 单源；undefined = 本行不出「识别文字」菜单项）
  ocrStateOf: (row: WorkspaceFileRow) => string | undefined =
    (row: WorkspaceFileRow): string | undefined => {
      return undefined;
    };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 下探两态：drilled = 是否下探；openedId = 目标（'' 为合法目标 =「未关联会话」组）
  @State private drilled: boolean = false;
  @State private openedId: string = '';
  // 组列表（标题已解析；数据源与数组同点同步——装配方法内唯一赋值处）
  @State private groups: WorkspaceSessionEntry[] = [];
  private groupSource: SessionRowsSource = new SessionRowsSource();
  @State private fileEntries: WorkspaceListEntry[] = [];
  private fileSource: WorkspaceRowsSource = new WorkspaceRowsSource();
  // 装配令牌（自增取号、回填前比对——后发先至防串台）与销毁标志（防销毁后写状态）
  private loadSeq: number = 0;
  private disposed: boolean = false;

  aboutToAppear(): void {
    this.assemble();
  }

  aboutToDisappear(): void {
    this.disposed = true;
  }

  onRowsChanged(): void {
    this.assemble();
  }

  // 识别态位广播（父页域件态位刷新后触发）：只重派生下探行集（组列表不消费识别态位）
  onOcrTickChanged(): void {
    this.refreshOpenedFiles();
  }

  // 装配：分组派生（同步）→ 标题反查（异步，令牌守卫）→ 单点落组列表与下探行集；下探目标组
  // 消失（含 '' 组删空）自动回组列表
  private assemble(): void {
    this.loadSeq++;
    const seq: number = this.loadSeq;
    const groups: WorkspaceSessionGroup[] = deriveWorkspaceSessionGroups(this.rows);
    if (this.drilled && !this.hasGroup(groups, this.openedId)) {
      this.drilled = false;
      this.openedId = '';
    }
    const ids: string[] = [];
    for (const group of groups) {
      if (group.conversationId !== '') {
        ids.push(group.conversationId);
      }
    }
    queryConversationTitlesByIds(ids)
      .then((titles: Map<string, string>): void => {
        if (seq !== this.loadSeq || this.disposed) {
          return;
        }
        this.applyGroups(groups, titles, true);
      })
      .catch((e: Object): void => {
        if (seq !== this.loadSeq || this.disposed) {
          return;
        }
        hilog.warn(DOMAIN, TAG, '会话标题反查失败（降级未命名）：%{public}s',
          (e as Error).message);
        this.applyGroups(groups, new Map<string, string>(), false);
      });
  }

  private hasGroup(groups: WorkspaceSessionGroup[], conversationId: string): boolean {
    for (const group of groups) {
      if (group.conversationId === conversationId) {
        return true;
      }
    }
    return false;
  }

  // 反查结果合并（单点赋值处）：缺失 = 已删除（仅反查成功时成立）、空串 = 未命名、'' 组 = 未关联会话
  private applyGroups(groups: WorkspaceSessionGroup[], titles: Map<string, string>,
    titlesResolved: boolean): void {
    const view: WorkspaceSessionEntry[] = [];
    for (const group of groups) {
      let title: string = '未命名会话';
      if (group.conversationId === '') {
        title = '未关联会话';
      } else {
        const hit: string | undefined = titles.get(group.conversationId);
        if (hit !== undefined && hit !== '') {
          title = hit;
        } else if (hit === undefined) {
          title = titlesResolved ? '已删除的会话' : '未命名会话';
        }
      }
      // 键含行全部可变展示成分（标题/件数/大小/最近时间——见头注释修复笔）
      view.push({ key: 's|' + group.conversationId + '|' + title + '|' + group.fileCount + '|' +
        group.bytes + '|' + group.lastAt, conversationId: group.conversationId,
        title: title, fileCount: group.fileCount, bytes: group.bytes, lastAt: group.lastAt });
    }
    this.groups = view;
    this.groupSource.reload(view);
    this.refreshOpenedFiles();
  }

  // 下探文件行重派生（rows 变化 / 进出下探两入口）；absPath 运行时派生（库内相对红线不变）
  private refreshOpenedFiles(): void {
    if (!this.drilled) {
      this.fileEntries = [];
      this.fileSource.reload([]);
      return;
    }
    const filesDir: string = workspaceFilesDir();
    const entries: WorkspaceListEntry[] = [];
    for (const row of deriveWorkspaceSessionFiles(this.rows, this.openedId)) {
      const entry: WorkspaceListEntry = { key: '', kind: 'file', row: row,
        absPath: filesDir + '/' + row.localPath, dirName: '', dirPath: '', fileCount: 0 };
      // 识别文字态位（父页透传域件 stateOf 单源；键含 ocrState——态位变即行重建换菜单文案）
      entry.ocrState = this.ocrStateOf(row);
      entry.key = workspaceEntryKey(entry);
      entries.push(entry);
    }
    this.fileEntries = entries;
    this.fileSource.reload(entries);
  }

  // 当前下探会话的标题（位置卡用；组列表反查——openedId 由分组派生保证在 groups 内）
  private openedTitle(): string {
    for (const group of this.groups) {
      if (group.conversationId === this.openedId) {
        return group.title;
      }
    }
    return '未命名会话';
  }

  // ── 会话行卡（组列表态）：标题 + 件数 · 大小 · 最近时间；整卡可点下探，无会话级动作 ──
  @Builder
  SessionCard(item: WorkspaceSessionEntry) {
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
        this.drilled = true;
        this.openedId = item.conversationId;
        this.refreshOpenedFiles();
      })
    }
    .width('100%')
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  build() {
    if (!this.drilled) {
      List({ space: CARD_SPACING }) {
        LazyForEach(this.groupSource, (item: WorkspaceSessionEntry): void => {
          ListItem() {
            this.SessionCard(item)
          }
        }, (item: WorkspaceSessionEntry): string => item.key)
        // 空态按组列表空判（只有空文件夹、零文件时 rows 非空而 groups 空，按 rows 判会整段纯白）
        if (this.groups.length === 0) {
          ListItem() {
            Column({ space: 6 }) {
              Text('工作区还没有文件')
                .fontSize(15)
                .fontColor(cardTitleColor())
              Text('助手在对话里保存的文件会按会话显示在这里。')
                .fontSize(13)
                .fontColor(cardDescColor())
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .padding({ top: 24, bottom: 24 })
            .alignItems(HorizontalAlign.Center)
          }
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16 })
      .contentStartOffset(Math.max(this.topPad, 0))
      .contentEndOffset(this.bottomPad + 16)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
    } else {
      List({ space: CARD_SPACING }) {
        ListItem() {
          WorkspaceNavCard({
            label: '当前会话',
            title: this.openedTitle(),
            upEnabled: true,
            onUp: (): void => {
              this.drilled = false;
              this.openedId = '';
              this.refreshOpenedFiles();
            },
            actionLabel: ''
          })
        }
        .width('100%')

        LazyForEach(this.fileSource, (item: WorkspaceListEntry): void => {
          ListItem() {
            WorkspaceFileRowCard({
              entry: item,
              showDir: true,
              onPreview: (entry: WorkspaceListEntry): void => {
                this.onPreview(entry, this.fileEntries);
              },
              onShare: this.onShare,
              onOcr: this.onOcr,
              onRename: this.onRename,
              onMove: this.onMove,
              onDelete: this.onDelete
            })
          }
        }, (item: WorkspaceListEntry): string => item.key)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16 })
      .contentStartOffset(Math.max(this.topPad, 0))
      .contentEndOffset(this.bottomPad + 16)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
    }
  }
}
