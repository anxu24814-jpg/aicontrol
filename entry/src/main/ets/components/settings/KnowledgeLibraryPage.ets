// 知识库管理页：设置页「指令面」组卡「知识库」行的一级入口，★ 决明拍板后为唯一入口（助手侧
//「管理知识库」入口行已撤除；悬空 id 由各写口级联清理）。自包 PageShell 壳，形制照技能库页。
// · 清单：行卡 = 书名（单行收敛）+「N 条条目」副行；点行进书详情页；右侧四点键 → 官方菜单
//  （重命名 / 导出 / 导出为通用格式——★ 菜单「删除」项已退役，删除统一走行左滑确认链）。
// · 标题栏〔＋新建|⋯更多〕双热区胶囊（新建为左热区、⋯ 恒最右为菜单锚点几何前提）：新建走
//   onNewBook 上限闸（链未动），导入仍收在「更多」菜单（域件 KnowledgeTitleMenu.ets，单项
//   导入知识库）。
// · 建库：先查数量，达 KNOWLEDGE_BOOK_MAX 就地拦截（toast 且不弹输入框，不让白填）；未达才弹
//   命名对话框，确认后落库并直接进新书详情页。
// · 导出：行卡菜单「导出」→ 取库内条目（含来源标签）→ serializeKnowledgeBook → 写沙箱件 →
//   官方分享面板（自带「另存为文件」）。单本可分享，与「数据同步」整机备份恢复分工不重叠。
// · 通用格式导出：serializeKnowledgeBookCompat（RikkaHub 信封，只写条目名/正文/关键词）→ 同一套
//   写件分享链；**无关键词条目整条不写**并在 toast 说明（对方按关键词触发，写了永不生效）——
//   仅确有排除时提示。
// · 导入链（五闸）：库满先拦（不弹选择器）→ 选择器单件 .json → 扩展名分派 → 解析（自家格式四拒；
//   外部世界书 RikkaHub / Kelivo / SillyTavern World Info v2 / Kelivo 裸形态走同一审阅链，附注随
//   载荷带回）→ 条目数上限闸 → 逐条分派（全不可导入即拒）→ 书名重名拒 → 审阅弹窗 → 确认后
//   **恒新建一本**串行落库（副本语义永不覆盖）→ 广播 → 直接进新书详情页；单条失败不炸整批。
// · 删除：确认弹窗（文案写明全部条目一并删除、已启用它的助手将同步移除）；确认后
//   KnowledgeDb.deleteBookCascade 事务级联删。重命名：命名对话框（初值 = 当前书名）→ 落库 → 广播。
// · 刷新链：@StorageProp(KNOWLEDGE_LIST_TICK_KEY) @Watch → reload（写点 = KnowledgeDb 各写函数
//   收口的 broadcastKnowledgeList）。本页刷新主源 = 该广播（doDelete 不自刷，靠广播回来；导入同）；
//   下探书详情页另带 push 回调作第二源——子页现形为无 result pop，该回调实际不触发，留作幂等
//   兜底，勿据此删广播。
// ★ 搜索（常显搜索框，形制照 MemoryLibraryPage.SearchSection）：命中两路——①书名内存过滤
//   filterBooksByKeyword；②**书内条目**标题/关键词/正文命中，countEntryHitsByBook 一条 GROUP BY
//   出每本命中数，副行显「命中 N 条条目」。★ 容器维持 Scroll + ForEach + 纪元键（不迁 Repeat：
//   assert-knowledge-domain 151 钉住，§4.6.3 键变重建族「禁抄禁迁」）——命中数属上屏成分，随条数
//   进**内层键**（上屏成分不入键 = 卡面定格）。★ 异步竞态：SQL 回包按递增令牌校验关键词未变才落地。
// ★ 搜索框承载：搜索框上移标题栏下方带（SearchTopBand 恒 REGULAR 光感；内容顶让位算式
//   searchBandContentTop 单源该件）。
import { CARD_RADIUS } from '../../common/Theme';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { fileUri, picker } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { AppMenuHost } from '../../common/AppMenuHost';
import { ComponentContent, LengthMetrics, SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { PageShell } from '../../common/PageShell';
import { ROUTE_KNOWLEDGE_BOOK_PAGE } from '../../common/RouteNames';
import {
  CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor, menuDividerColor
} from '../../common/Theme';
import { IMMERSIVE_LEVEL_KEY, overlayMaterial, resolvedUiMaterial } from '../../common/ImmersiveLevel';
// 库页搜索过滤纯函数（本页命中两路：书名 + 书内条目命中集）
import { filterBooksByKeyword } from '../../common/LibrarySearch';
// 标题栏下方带搜索框承载件 + 内容顶让位算式
import { SearchTopBand, searchBandContentTop } from '../SearchTopBand';
import { TITLE_BAR_EDGE_INSET, TitleBarActionCapsule } from '../TitleBarKeys';
// 标题栏「更多」菜单域件（单项「导入知识库」；菜单内容 / 宿主 / 隐形锚点在此）
import { KnowledgeMoreMenuAnchor, KnowledgeTitleMenuCallbacks,
  KnowledgeTitleMenuHost } from './KnowledgeTitleMenu';
import { ConfirmDialog, ConfirmDialogTone } from '../chat/ConfirmDialog';
import { InputDialog } from '../chat/InputDialog';
// 行级左滑删除横滑层（交互基准 = SessionSwipeItem；键位与 SwipeGroup 口径见该件头注释）
import { RowSwipeDelete, SwipeGroup } from '../RowSwipeDelete';
import { SETTING_TITLE_KNOWLEDGE_LIBRARY } from '../../common/SettingSearch';
import {
  broadcastKnowledgeList, countBooks, countEntriesOfBooks, countEntryHitsByBook,
  deleteBookCascade, insertBook,
  insertEntry, KNOWLEDGE_BOOK_MAX, KNOWLEDGE_ENTRY_MAX, KNOWLEDGE_LIST_TICK_KEY,
  KnowledgeBookRow, KnowledgeEntryRow, queryBooks, queryEntries, renameBook, toBookItems,
  toEntryItems
} from '../../common/store/KnowledgeDb';
import { KNOWLEDGE_TITLE_MAX, knowledgeBookNameTaken } from '../../common/KnowledgeText';
// 导入导出域符号单源 = KnowledgeImportText.ets（TITLE_MAX 与书名判定仍留 KnowledgeText）
import {
  KNOWLEDGE_FILE_EXT, composeKnowledgeCompatExportTip, composeKnowledgeImportPreview,
  KnowledgeFileEntry, KnowledgeFileRead, KnowledgeScreenResult, screenKnowledgeEntries
} from '../../common/KnowledgeImportText';
import {
  exportKnowledgeBook, exportKnowledgeBookCompat, KnowledgeCompatWrite, knowledgeFileExt,
  readPickedKnowledgeFile
} from '../../common/KnowledgePack';

// ── 行卡四点键菜单：重命名 / 导出 / 导出为通用格式（锚点 = 四点键自身，勿锚整卡；形制照
//    SkillRowMenu。★ 菜单「删除」项已退役——删除统一走行左滑确认链）──
const KNOWLEDGE_ROW_MENU_ID_PREFIX: string = 'knowledgeRowMenu_';

interface KnowledgeRowMenuCallbacks {
  id: string;
  onRename: () => void;
  onExport: () => void;
  onExportCompat: () => void;
}

@Builder
function KnowledgeRowMenuBuilder(params: KnowledgeRowMenuCallbacks) {
  Menu() {
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')), content: '重命名' })
      .onClick(() => {
        params.onRename();
      })
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_arrow_down')), content: '导出' })
      .onClick(() => {
        params.onExport();
      })
    // 通用格式：写对方读得懂的形态，用来把整本交给别的应用
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.share')), content: '导出为通用格式' })
      .onClick(() => {
        params.onExportCompat();
      })
  }
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

class KnowledgeRowMenuHost extends AppMenuHost<KnowledgeRowMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: KnowledgeRowMenuCallbacks): ComponentContent<KnowledgeRowMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(KnowledgeRowMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出（基类弹前重建——按当前深浅色/材质重建 UI 树；targetSpace 5 同卡片菜单口径）
  open(uiContext: UIContext, callbacks: KnowledgeRowMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, KNOWLEDGE_ROW_MENU_ID_PREFIX + callbacks.id,
      // 第三参 true = 交互形变 + 触点流光（菜单光感笔；官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true),
      { targetSpace: LengthMetrics.vp(5) });
  }
}

@Component
export struct KnowledgeLibraryPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI、不上行；写库照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  @State private books: KnowledgeBookRow[] = [];
  // 搜索词与过滤后的可见书单（列表数据源）；空词 = 全显
  @State private keyword: string = '';
  @State private visibleBooks: KnowledgeBookRow[] = [];
  // 列表重建纪元（reload 成功自增；外层列表键只含纪元，行级上屏成分由内层行键承接，坑16 家族）
  @State private listEpoch: number = 0;
  // 各库条目数（一次 GROUP BY 查回，禁逐库查——P1-2；普通成员 + 纪元键保证重建时读到新值）
  private counts: Map<string, number> = new Map<string, number>();
  // 各库**条目命中数**（搜索第二路：书内条目命中——同一条 GROUP BY 形态，禁逐库查；普通成员，
  // 内层键含命中数保证重建时读到新值）
  private entryHits: Map<string, number> = new Map<string, number>();
  // 搜索回包令牌（防「先发后到」：旧关键词的 SQL 回包到达时按令牌作废，不盖新词）
  private searchSeq: number = 0;
  // 列表刷新广播（递增 tick——写点在 KnowledgeDb 各写函数收口处；@Watch 对同值不触发故用递增）
  @StorageProp(KNOWLEDGE_LIST_TICK_KEY) @Watch('onListTick') listTick: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 行卡菜单节点宿主（init 一次 / 弹出前重建 / dispose 成对）
  private rowMenu: KnowledgeRowMenuHost = new KnowledgeRowMenuHost();
  // 标题栏「更多」菜单节点宿主（init 一次 / 弹出前重建 / dispose 成对；内容与锚点在域件）
  private titleMenu: KnowledgeTitleMenuHost = new KnowledgeTitleMenuHost();
  // 行左滑互斥组（搜索重算时 collapse，滚动开始经组收口；reload 走纪元键整表重建，行实例
  // 随建随清，无需另行收口）
  private swipeGroup: SwipeGroup = new SwipeGroup();
  private deleteTarget: KnowledgeBookRow | null = null;
  // 命名对话框（新建 / 重命名两用——message 与初值随场景变，按需构造赋成员位；坑7 姿态）
  private nameCtrl: CustomDialogController | null = null;
  // 待导入载荷（审阅弹窗期间持有；书名单独持一份供落库）。弹窗异步确认，载荷须跨帧存活
  private pendingImport: KnowledgeScreenResult | null = null;
  private pendingName: string = '';
  // 导入审阅弹窗控制器（按需构造——坑7；message 依载荷动态拼，不能预建）
  private importCtrl: CustomDialogController | null = null;
  // 删除确认弹窗（坑7：必须组件成员位构造——普通类 open() 静默无效真机实锤）
  private confirmCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: ConfirmDialog({
      title: '删除知识库',
      message: '删除后无法恢复。该库的全部条目一并删除，已启用它的助手将同步移除。',
      confirmLabel: '删除',
      onConfirm: (): void => {
        this.doDelete();
      }
    }),
    autoCancel: true
  });

  aboutToAppear(): void {
    this.rowMenu.init(this.getUIContext(), {
      id: '',
      onRename: (): void => {
      },
      onExport: (): void => {
      },
      onExportCompat: (): void => {
      }
    });
    this.titleMenu.init(this.getUIContext(), this.titleMenuCallbacks());
    this.reload();
  }

  aboutToDisappear(): void {
    this.departed = true;
    this.rowMenu.dispose();
    this.titleMenu.dispose();
  }

  private onListTick(): void {
    this.reload();
  }

  private reload(): void {
    queryBooks()
      .then((rows: KnowledgeBookRow[]): Promise<void> => {
        if (this.departed) {
          return Promise.resolve();
        }
        this.books = rows;
        const ids: string[] = rows.map((row: KnowledgeBookRow): string => row.id);
        return countEntriesOfBooks(ids).then((counts: Map<string, number>): void => {
          if (this.departed) {
            return;
          }
          this.counts = counts;
          this.listEpoch = this.listEpoch + 1; // 键变重建（条数/书名变化也刷新）
          // 搜索态下库清单/条目数变了也重算可见集与条目命中（关键词不因重拉被清空）
          this.refreshSearch();
        });
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({
          message: '知识库读取失败：' + (e as Error).message
        });
      });
  }

  // 行副行（条数取自本页缓存；查不到 = 0 条兜底——新库还没有行）
  private entryCountOf(bookId: string): number {
    return this.counts.get(bookId) ?? 0;
  }

  // 该库条目命中数（搜索第二路结果；查不到 = 0 兜底——没命中的库不进 Map）
  private entryHitsOf(bookId: string): number {
    return this.entryHits.get(bookId) ?? 0;
  }

  // 行副行文案两态分派单源（关键词非空且该库有命中 → 报命中数，用户才知道这本书为何在场；
  // 其余报总条数——仅书名命中的库仍报总数，信息不丢）
  private bookSubtitle(bookId: string): string {
    const hits: number = this.entryHitsOf(bookId);
    if (this.keyword.trim() !== '' && hits > 0) {
      return '命中 ' + hits + ' 条条目';
    }
    return this.entryCountOf(bookId) + ' 条条目';
  }

  // 搜索重算（唯一写点 = 搜索框 onChange 与 reload 成功）。两路命中：书名同步内存过滤即时出
  // 结果（先清命中集：宁可先少出不失准）；书内条目异步 SQL，回包按令牌校验关键词未变才落地。
  // 空词 = 不查库（清命中集 + 全显），与另两页同口径
  private refreshSearch(): void {
    const kw: string = this.keyword;
    // 可见集重算 → 收起左滑展开行（reload 侧走纪元键整表重建天然归位）
    this.swipeGroup.collapse();
    this.entryHits = new Map<string, number>();
    this.visibleBooks = filterBooksByKeyword(this.books, kw, this.entryHits);
    this.searchSeq = this.searchSeq + 1;
    if (kw.trim() === '') {
      return; // 空词不查库（空词判据单源在 LibrarySearch.normalizeSearchKeyword 侧，此处是第二道）
    }
    const token: number = this.searchSeq;
    countEntryHitsByBook(kw)
      .then((hits: Map<string, number>): void => {
        if (this.departed) {
          return;
        }
        if (token !== this.searchSeq) {
          return; // 关键词已变，旧词的回包作废
        }
        this.entryHits = hits;
        this.visibleBooks = filterBooksByKeyword(this.books, this.keyword, hits);
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        // 条目命中这一路失败不静默（P0-1）：书名命中仍在场，提示后用户可改词重试
        this.getUIContext().getPromptAction().showToast({
          message: '条目检索失败：' + (e as Error).message
        });
      });
  }

  // 0 行态提示文案（两态不可混）：库空 = 新建引导；搜索无命中 = 单句提示改词或清词
  private emptyHintText(): string {
    if (this.books.length === 0) {
      return '暂无知识库。点右上角的「＋」新建，再到助手编辑页的知识库里启用。';
    }
    return '没有匹配的知识库。';
  }

  // 外层列表键（纪元——行级上屏成分由内层行键 id/书名/条数/命中数承接）
  private listKey(): string {
    return 'knowledgeLib|' + this.listEpoch;
  }

  // 内容顶留白（搜索框在标题栏下方带，让位 = 框底 + 分段承载先例间距 28；算式单源
  // searchBandContentTop）
  private contentTopPad(): number {
    return searchBandContentTop(this.topPad, 28);
  }

  // 新建：达上限即就地拦截（P0-1 明确提示，不静默失败；不弹输入框让用户白填一遍）
  private onNewBook(): void {
    countBooks()
      .then((count: number): void => {
        if (this.departed) {
          return;
        }
        if (count >= KNOWLEDGE_BOOK_MAX) {
          this.getUIContext().getPromptAction().showToast({
            message: '知识库数量已达上限，请先删除不再使用的知识库。'
          });
          return;
        }
        this.askName('新建知识库', '', (text: string): void => {
          this.createBook(text);
        });
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({
          message: '知识库读取失败：' + (e as Error).message
        });
      });
  }

  // 建库落库（重名先拦）：判定单源 KnowledgeText.knowledgeBookNameTaken（工具侧 create_book 同用，
  // 禁另写比较）；命中 toast 不落库；**现查一次**（不拿页面缓存）压缩并发窗口
  private createBook(name: string): void {
    queryBooks()
      .then((rows: KnowledgeBookRow[]): void => {
        if (knowledgeBookNameTaken(toBookItems(rows), name, '')) {
          if (this.departed) {
            return;
          }
          this.getUIContext().getPromptAction().showToast({
            message: '已有同名知识库，换一个名称再试。'
          });
          return;
        }
        insertBook(name)
          .then((row: KnowledgeBookRow): void => {
            if (this.departed) {
              return; // 建库写库照常，只放弃已亡组件上的广播与跳转
            }
            broadcastKnowledgeList();
            // 新库必为空库，直接进条目页（省一步「返回再点进来」）
            this.openBook(row.id);
          })
          .catch((e: Object): void => {
            if (this.departed) {
              return;
            }
            this.getUIContext().getPromptAction().showToast({
              message: '创建失败：' + (e as Error).message
            });
          });
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({
          message: '知识库读取失败：' + (e as Error).message
        });
      });
  }

  // 重命名（行菜单 → 命名对话框，初值 = 当前书名；InputDialog 自带空值 toast 留窗 / 同值静默跳过）
  private askRename(book: KnowledgeBookRow): void {
    this.askName('重命名知识库', book.name, (text: string): void => {
      this.renameBookIfFree(book, text);
    });
  }

  // 改名落库（重名先拦，**排除自身 id**——改回原名不算重名；同值改名由 InputDialog 静默跳过。
  // 与建库同一判定单源）
  private renameBookIfFree(book: KnowledgeBookRow, name: string): void {
    queryBooks()
      .then((rows: KnowledgeBookRow[]): void => {
        if (this.departed) {
          return;
        }
        if (knowledgeBookNameTaken(toBookItems(rows), name, book.id)) {
          this.getUIContext().getPromptAction().showToast({
            message: '已有同名知识库，换一个名称再试。'
          });
          return;
        }
        renameBook(book.id, name)
          .then((): void => {
            broadcastKnowledgeList();
          })
          .catch((e: Object): void => {
            if (this.departed) {
              return;
            }
            this.getUIContext().getPromptAction().showToast({
              message: '重命名失败：' + (e as Error).message
            });
          });
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({
          message: '知识库读取失败：' + (e as Error).message
        });
      });
  }

  // 命名对话框（新建/重命名共用——重复两次的逻辑提子程序 P2-4）
  private askName(title: string, initial: string, onConfirm: (text: string) => void): void {
    this.nameCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: title,
        initialText: initial,
        placeholder: '例如 前端规范、项目术语',
        confirmLabel: '确认',
        maxLength: KNOWLEDGE_TITLE_MAX,
        onConfirm: onConfirm
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.nameCtrl.open();
  }

  private askDelete(book: KnowledgeBookRow): void {
    this.deleteTarget = book;
    this.confirmCtrl.open();
  }

  // 左滑删除入口（行 id → 行对象后走既有确认链；行已在重拉中消失 = 静默不弹）
  private askDeleteById(id: string): void {
    const row: KnowledgeBookRow | undefined =
      this.books.find((r: KnowledgeBookRow): boolean => r.id === id);
    if (row !== undefined) {
      this.askDelete(row);
    }
  }

  private doDelete(): void {
    const target: KnowledgeBookRow | null = this.deleteTarget;
    this.deleteTarget = null;
    if (target === null) {
      return;
    }
    // 级联删（条目 + 助手引用 + 书行同一事务）+ 广播都在 KnowledgeDb 侧；本页只报结果
    deleteBookCascade(target.id)
      .then((): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '已删除' });
        broadcastKnowledgeList();
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
      });
  }

  // 进书详情页（返回经 onPop 重拉——条目数可能已变；坑17：子页 pop 带 result 才触发）
  private openBook(bookId: string): void {
    this.pathStack.pushPathByName(ROUTE_KNOWLEDGE_BOOK_PAGE, bookId, (): void => {
      this.reload();
    });
  }

  // ── 导出链 ──

  // 导出：取库内已保存条目（含来源标签，不涉编辑态表单）→ 序列化 → 写沙箱件 → 官方分享面板；
  // 失败 toast 中文原因不静默（P0-1）
  private async exportBook(book: KnowledgeBookRow): Promise<void> {
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      const rows: KnowledgeEntryRow[] = await queryEntries(book.id);
      if (this.departed) {
        return;
      }
      const path: string = exportKnowledgeBook(ctx,
        book.name !== '' ? book.name : '未命名知识库', toEntryItems(rows),
        rows.map((row: KnowledgeEntryRow): string => row.source));
      await this.shareFile(path, ctx);
      if (this.departed) {
        return;
      }
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '导出失败：' + (e as Error).message });
    }
  }

  // 通用格式导出：只写对方读得懂的三字段（条目名 / 正文 / 关键词），**无关键词条目整条不写**
  // ——对方按关键词触发，写了永不生效，不如不写并明示原因。toast 仅确有排除时出现（纯函数无
  // 排除返空串），且排在分享面板之前——面板是系统窗口，弹出后会盖住 toast
  private async exportBookCompat(book: KnowledgeBookRow): Promise<void> {
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      const rows: KnowledgeEntryRow[] = await queryEntries(book.id);
      if (this.departed) {
        return;
      }
      const written: KnowledgeCompatWrite = exportKnowledgeBookCompat(ctx,
        book.name !== '' ? book.name : '未命名知识库', toEntryItems(rows));
      const tip: string = composeKnowledgeCompatExportTip(written.exported, written.dropped);
      if (tip !== '') {
        this.getUIContext().getPromptAction().showToast({ message: tip });
      }
      await this.shareFile(written.path, ctx);
      if (this.departed) {
        return;
      }
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '导出失败：' + (e as Error).message });
    }
  }

  // 分享面板（utd / label 走既有 FILE 形态；面板自带「另存为文件」）
  private async shareFile(path: string, ctx: common.Context): Promise<void> {
    const fileName: string = path.substring(path.lastIndexOf('/') + 1);
    const record: systemShare.SharedRecord = {
      utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
      uri: fileUri.getUriFromPath(path),
      title: fileName,
      label: 'FILE'
    };
    const controller: systemShare.ShareController =
      new systemShare.ShareController(new systemShare.SharedData(record));
    await controller.show(ctx as common.UIAbilityContext, {});
  }

  // ── 导入链（五闸）──

  // 导入：库满先拦（不弹选择器）→ 选择器单件 .json → 扩展名分派 → 解析（整份拒四态）→ 条目数
  // 上限闸 → 逐条分派（全不可导入即拒并报首条原因）→ 书名重名拒（单源 knowledgeBookNameTaken，
  // 现查一次）→ 审阅弹窗；任何一步失败都 toast 中文原因，不静默
  private async importBook(): Promise<void> {
    try {
      const count: number = await countBooks();
      if (this.departed) {
        return;
      }
      if (count >= KNOWLEDGE_BOOK_MAX) {
        this.getUIContext().getPromptAction().showToast({
          message: '知识库数量已达上限，请先删除不再使用的知识库。'
        });
        return;
      }
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({
        message: '知识库读取失败：' + (e as Error).message
      });
      return;
    }
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      // 导入 = 单件动作（只取 uris[0]）：maxSelectNumber=1 守卫多选静默丢失
      const selectOpts: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      selectOpts.maxSelectNumber = 1;
      // 后缀过滤（d.ts：'|' 左描述右后缀；「该参数仅部分设备能力可用」）不得当唯一防线——真闸
      // 是下方扩展名分派 + 中文兜底提示
      selectOpts.fileSuffixFilters = ['知识库文件|.json'];
      const uris: Array<string> = await docPicker.select(selectOpts);
      if (this.departed) {
        return;
      }
      if (uris.length === 0) {
        return; // 用户取消，静默
      }
      if (knowledgeFileExt(uris[0]) !== KNOWLEDGE_FILE_EXT) {
        this.getUIContext().getPromptAction().showToast({ message: '只能导入 .json 知识库文件' });
        return;
      }
      const read: KnowledgeFileRead = readPickedKnowledgeFile(ctx, uris[0]);
      if (!read.ok) {
        this.getUIContext().getPromptAction().showToast({ message: read.error });
        return;
      }
      if (read.entries.length > KNOWLEDGE_ENTRY_MAX) {
        // 整份拒（部分导入会产出半成品副本，比明确拒绝更接近静默丢件）；文案给出路：原应用拆两本
        this.getUIContext().getPromptAction().showToast({
          message: '这本有 ' + read.entries.length + ' 条，超过单库 ' + KNOWLEDGE_ENTRY_MAX +
            ' 条上限，未能导入。'
        });
        return;
      }
      const screen: KnowledgeScreenResult = screenKnowledgeEntries(read.entries);
      if (screen.importable.length === 0) {
        this.getUIContext().getPromptAction().showToast({
          message: screen.skipped.length > 0 ? screen.skipped[0] : '文件里没有可导入的条目。'
        });
        return;
      }
      const books: KnowledgeBookRow[] = await queryBooks();
      if (this.departed) {
        return;
      }
      if (knowledgeBookNameTaken(toBookItems(books), read.name, '')) {
        this.getUIContext().getPromptAction().showToast({
          message: '知识库「' + read.name + '」已存在，请先改名或删除后再导入。'
        });
        return;
      }
      this.confirmImport(read.name, screen, read.notice);
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '导入失败：' + (e as Error).message });
    }
  }

  // 审阅确认（ConfirmDialog 按需构造——坑7；message 由纯函数拼装，条目名封顶 8 项 / 未导入封顶
  // 3 条 / 安全行恒末，长清单不把两键顶出屏）。取消键回收载荷；遮罩关闭无回调，由下次导入覆盖
  //（单份载荷有界）。notice = 外部世界书附注，自家格式恒空串——原样透传，本页不解读
  private confirmImport(name: string, screen: KnowledgeScreenResult, notice: string): void {
    this.pendingImport = screen;
    this.pendingName = name;
    this.importCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: ConfirmDialog({
        title: '导入知识库',
        message: composeKnowledgeImportPreview(name, screen, notice),
        confirmLabel: '导入',
        confirmTone: ConfirmDialogTone.NORMAL,
        onConfirm: (): void => {
          this.doImport();
        },
        onCancel: (): void => {
          this.pendingImport = null;
          this.pendingName = '';
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.importCtrl.open();
  }

  // 落库：恒新建一本（副本语义，永不覆盖）→ 逐条**串行**插入 → 广播 → 直接进新书详情页
  private doImport(): void {
    const screen: KnowledgeScreenResult | null = this.pendingImport;
    const name: string = this.pendingName;
    this.pendingImport = null;
    this.pendingName = '';
    if (screen === null || name === '') {
      return;
    }
    insertBook(name)
      .then((book: KnowledgeBookRow): void => {
        this.importOne(book.id, screen, 0, 0);
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({
          message: '导入失败：' + (e as Error).message
        });
      });
  }

  // 单条落库（串行递归，不并发——容量判定与写入之间不留竞态窗口；单条失败不炸整批，计入未导入
  // 继续）。全部完成后：广播一次 → 汇总 toast → 进新书页
  private importOne(bookId: string, screen: KnowledgeScreenResult, index: number,
    done: number): void {
    if (index >= screen.importable.length) {
      broadcastKnowledgeList();
      this.reportImport(screen, done);
      this.openBook(bookId);
      return;
    }
    const item: KnowledgeFileEntry = screen.importable[index];
    // 触发精度四字段随条目落库（漏这一层则导入后配置全是默认值且无任何报错；值已在解析层 clamp）
    insertEntry(bookId, { title: item.title, keywords: item.keywords, content: item.content,
      matchCase: item.matchCase, matchWhole: item.matchWhole,
      priority: item.priority, scanDepth: item.scanDepth },
      item.source)
      .then((): void => {
        this.importOne(bookId, screen, index + 1, done + 1);
      })
      .catch((): void => {
        this.importOne(bookId, screen, index + 1, done);
      });
  }

  // 导入结果一句话（已导入 / 未导入 / 关键词截断三项按实际拼接，不含缺项）
  private reportImport(screen: KnowledgeScreenResult, done: number): void {
    const parts: string[] = [];
    if (done > 0) {
      parts.push('已导入 ' + done + ' 条');
    }
    const missed: number = screen.importable.length - done + screen.skipped.length;
    if (missed > 0) {
      parts.push(missed + ' 条未导入');
    }
    if (screen.clippedKeywords > 0) {
      parts.push(screen.clippedKeywords + ' 条的关键词过长已截断');
    }
    this.getUIContext().getPromptAction().showToast({ message: parts.join('，') });
  }

  private openRowMenu(book: KnowledgeBookRow): void {
    this.rowMenu.open(this.getUIContext(), {
      id: book.id,
      onRename: (): void => {
        this.askRename(book);
      },
      onExport: (): void => {
        this.exportBook(book);
      },
      onExportCompat: (): void => {
        this.exportBookCompat(book);
      }
    }, this.immersiveLevel);
  }

  // 标题栏「更多」菜单动作快照（每次弹出现取；现仅导入一项，链未动——importBook 五闸；新建已回
  // 胶囊左热区 onNewBook，不在菜单内）
  private titleMenuCallbacks(): KnowledgeTitleMenuCallbacks {
    return {
      onImport: (): void => {
        this.importBook();
      }
    };
  }

  // 弹出标题栏「更多」菜单（定位 = 隐形锚点 KnowledgeMoreMenuAnchor，几何见域件）
  private openMoreMenu(): void {
    this.titleMenu.open(this.getUIContext(), this.titleMenuCallbacks(), this.immersiveLevel);
  }

  // 标题栏下方带搜索框：承载件恒 REGULAR 光感，几何与命中透传见该件头注释
  @Builder
  SearchBand() {
    SearchTopBand({
      keyword: $keyword,
      placeholder: '搜索书名或条目内容',
      onInput: (value: string): void => {
        this.keyword = value;
        this.refreshSearch();
      }
    })
  }

  // 行卡（点卡进条目页 + 右侧四点键菜单）。★ 蒙层边距：卡底 Column 四周 padding 4，壳 padding 10 回添
  @Builder
  BookCard(row: KnowledgeBookRow) {
    Column() {
      Button() {
        Row({ space: 10 }) {
          Column({ space: 3 }) {
            Text(row.name !== '' ? row.name : '未命名知识库')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            // 副行两态分派单源 = bookSubtitle（搜索态命中条目的库报命中数，其余报总条数）
            Text(this.bookSubtitle(row.id))
              .fontSize(13)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Button() {
            SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
              .fontSize(18)
              .fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .id(KNOWLEDGE_ROW_MENU_ID_PREFIX + row.id)
          .onClick((): void => {
            this.openRowMenu(row);
          })
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
        this.openBook(row.id);
      })
    }
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  // 标题栏覆盖层（HDS 路径〔＋新建|⋯更多〕双热区胶囊）——组件内 @Builder 是硬约束（坑30：全局
  // @Builder 被官方 titleBar napi 直接调用无视图上下文，启动即闪退）；键件几何走 TitleBarKeys 共用件。
  // 新建为左热区（onNewBook 上限闸），⋯ 恒最右弹单项导入菜单（域件 KnowledgeTitleMenu.ets）；
  // ⋯ 最右是锚点几何前提（锚点右缘 = 该键右缘 = 屏宽 − TITLE_BAR_EDGE_INSET）
  @Builder
  TitleBarContent() {
    Row() {
      TitleBarActionCapsule({
        leftIcon: $r('sys.symbol.plus'),
        leftLabel: '新建知识库',
        rightIcon: $r('sys.symbol.dot_grid_2x2'),
        rightLabel: '更多',
        immersiveLevel: this.immersiveLevel,
        onLeftTap: (): void => {
          this.onNewBook();
        },
        onRightTap: (): void => {
          this.openMoreMenu();
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding({ right: TITLE_BAR_EDGE_INSET })
    .justifyContent(FlexAlign.End)
    .alignItems(VerticalAlign.Center)
    // 命中透传（二级页必需——覆盖层整栏铺在返回键上方，默认命中档会挡住返回键，真机实锤）
    .hitTestBehavior(HitTestMode.Transparent)
  }

  // 内容区（Stack 同层两件 = 「更多」菜单隐形锚点 + 内容层，顶部对齐）
  @Builder
  Content() {
    Stack({ alignContent: Alignment.Top }) {
      // 「更多」菜单隐形锚点（openMenu 的 TargetInfo 目标；几何 = 「按钮下沿」公式，见域件；
      // HitTest.None 不拦滚动与触摸）
      KnowledgeMoreMenuAnchor({ topPad: this.topPad })
      Scroll() {
        Column({ space: 10 }) {
          if (this.visibleBooks.length === 0) {
            // 空态行内提示行（13fp cardDescColor 无卡底）；两态文案分派单源 = emptyHintText
            Text(this.emptyHintText())
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
          } else {
            ForEach([this.listKey()], (_key: string) => {
              ForEach(this.visibleBooks, (row: KnowledgeBookRow) => {
                // 行卡包横滑层（书行全量可删、无内置行）；展开态是行内交互态不进键，键含上屏字段
                //（id / 书名 / 条数 / 命中数）
                RowSwipeDelete({
                  rowId: row.id,
                  group: this.swipeGroup,
                  content: (): void => {
                    this.BookCard(row)
                  },
                  onSwipeDelete: (id: string): void => {
                    this.askDeleteById(id);
                  }
                })
              }, (row: KnowledgeBookRow): string => row.id + '|' + row.name + '|' +
                this.entryCountOf(row.id) + '|' + this.entryHitsOf(row.id))
            }, (key: string): string => key)
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        // 顶留白：让出标题栏下方带搜索框框位（contentTopPad）
        .padding({ top: this.contentTopPad(), bottom: this.bottomPad + 16 })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
      // 竖滚开始收起左滑展开行（会话层同款行为；互斥经 SwipeGroup 单源）
      .onScrollStart((): void => {
        this.swipeGroup.collapse();
      })
    }
  }

  build() {
    PageShell({
      title: SETTING_TITLE_KNOWLEDGE_LIBRARY,
      // 标题栏〔＋新建|⋯更多〕双热区胶囊 = 覆盖层（menuHds 传 null；keepStackTitle = true 保住主标题，
      // 否则覆盖层会把标题置空）
      menuHds: null,
      titleBarStack: (): void => {
        this.TitleBarContent();
      },
      keepStackTitle: true,
      // 标题栏下方带搜索框。与上方 stackBuilder 分居标题栏行内与下方带两区，并存形态已真机验正常
      titleBarBottom: (): void => {
        this.SearchBand();
      },
      content: (): void => {
        this.Content();
      }
    })
  }
}
