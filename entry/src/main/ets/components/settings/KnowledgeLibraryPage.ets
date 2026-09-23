// 知识库管理页（2026-09-21 世界书知识库首版，任务书-世界书知识库-20260921 §4.5①）：
// 设置页「指令面」组卡「知识库」行的一级入口 + 助手知识库页「管理知识库」入口（双入口）——
// 自包 PageShell 壳，形制照 SkillLibraryPage（技能库页）。
// · 清单：行卡 = 书名（主行单行收敛）+ 「N 条条目」副行；点行卡进书详情页（条目清单）；
//   行卡右侧四点键 → 官方菜单（重命名 / 导出 / 导出为通用格式 / 删除——两个导出项相邻、
//   危险项恒末位）。
// · 标题栏〔＋|导入〕双热区胶囊（★ 2026-09-22 导入导出笔由单圆键改）：加「导入」后本页
//   两动作，单键形态不再成立（文件头旧判据：只有一个动作才用 TitleBarRoundKey，胶囊多出的
//   右热区没有动作 = 死控件；两动作起改 TitleBarActionCapsule，与技能库页同款几何/光感）。
//   左〔＋新建〕右〔导入〕，回退数组同步两键。
// · 建库流程：先查数量，达 KNOWLEDGE_BOOK_MAX 就地拦截（toast 并**不弹输入框**——不让用户
//   白填一遍名字再被拒）；未达上限才弹命名对话框，确认后落库并直接进新书详情页（省一步）。
// · 导出链（2026-09-22 导入导出笔）：行卡菜单「导出」→ 取库里已保存条目（含来源标签）→
//   KnowledgeText.serializeKnowledgeBook → KnowledgePack.exportKnowledgeBook 写沙箱件 →
//   官方分享面板（自带「另存为文件」）。空库允许导出；与「设置 → 数据同步」的全量备份分工
//   （这边是单本、可分享、可给别的设备，那边是整机备份恢复——两者不重叠不互改）。
// · 通用格式导出（2026-09-22 第三步，方案 §12.1）：行卡菜单「导出为通用格式」→
//   serializeKnowledgeBookCompat（RikkaHub 信封 + 只写条目名/正文/关键词，其余字段省略由对方
//   补它自己的默认）→ 同一套写件与分享链。**无关键词的条目整条不写**并在 toast 里说明原因
//   （对方按关键词触发，没有关键词的条目在那边永不生效）——本页只在确有排除时弹提示，无则不打扰。
// · 导入链（五闸，方案-知识库导入导出-20260922 §4）：库满先拦（不弹选择器不让白选）→
//   选择器单件 .json → 扩展名分派 → 解析（自家格式四拒；**外部世界书**——RikkaHub / Kelivo
//   信封、SillyTavern World Info v2、Kelivo 裸形态——走同一条审阅链，附注随载荷带回）→
//   条目数上限闸 → 逐条分派（全不可导入即拒）→ 书名重名拒 → 审阅弹窗（书名 + 条数 + 条目名
//   清单 + 未导入逐条说明 + 外部件附注，纯函数拼装带结构上界）→ 确认后**恒新建一本**串行落库
//   （副本语义，永不覆盖）→ 广播 → 直接进新书详情页。单条插入失败不炸整批（计入未导入呈报）。
// · 删除：确认弹窗（文案写明「该库的全部条目一并删除，已启用它的助手将同步移除」——
//   这两条后果用户必须事先看见）；确认后级联删（KnowledgeDb.deleteBookCascade 事务）。
// · 重命名：命名对话框（初值 = 当前书名）→ 落库 → 广播。
// · 刷新链：@StorageProp(KNOWLEDGE_LIST_TICK_KEY) @Watch → reload（写点 = KnowledgeDb 各写
//   函数收口处的 broadcastKnowledgeList；本页在栈中不显示时也能收到 tick，pop 回来即是新列表）。
//   本页刷新主源 = 该广播（含本页自己的删后刷新——doDelete **不发自刷**，靠广播回来，
//   2026-09-21 自检轮钉住该链）；导入落库走同一条广播（串行插完广播一次再进新书页）；
//   下探书详情页时另带 push 回调重拉作第二源（子页现形为无 result 的 pop，该回调实际不触发，
//   留着是幂等兜底——勿据此删广播）。
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
import {
  IMMERSIVE_LEVEL_KEY, overlayMaterial, resolvedUiMaterial
} from '../../common/ImmersiveLevel';
import { TITLE_BAR_EDGE_INSET, TitleBarActionCapsule } from '../TitleBarKeys';
import { ConfirmDialog, ConfirmDialogTone } from '../chat/ConfirmDialog';
import { InputDialog } from '../chat/InputDialog';
import { SETTING_TITLE_KNOWLEDGE_LIBRARY } from '../../common/SettingSearch';
import {
  broadcastKnowledgeList, countBooks, countEntriesOfBooks, deleteBookCascade, insertBook,
  insertEntry, KNOWLEDGE_BOOK_MAX, KNOWLEDGE_ENTRY_MAX, KNOWLEDGE_LIST_TICK_KEY,
  KnowledgeBookRow, KnowledgeEntryRow, queryBooks, queryEntries, renameBook, toBookItems,
  toEntryItems
} from '../../common/store/KnowledgeDb';
import {
  KNOWLEDGE_FILE_EXT, KNOWLEDGE_TITLE_MAX, knowledgeBookNameTaken,
  composeKnowledgeCompatExportTip, composeKnowledgeImportPreview, KnowledgeFileEntry,
  KnowledgeFileRead, KnowledgeScreenResult, screenKnowledgeEntries
} from '../../common/KnowledgeText';
import {
  exportKnowledgeBook, exportKnowledgeBookCompat, KnowledgeCompatWrite, knowledgeFileExt,
  readPickedKnowledgeFile
} from '../../common/KnowledgePack';

// ── 行卡四点键菜单：重命名 / 导出 / 导出为通用格式 / 删除（锚点 = 四点键自身勿锚整卡；形制照
//    SkillRowMenu / MemoryRowMenu；两个导出项相邻排「重命名」之后、「删除」之前——危险项恒末位）──
const KNOWLEDGE_ROW_MENU_ID_PREFIX: string = 'knowledgeRowMenu_';

interface KnowledgeRowMenuCallbacks {
  id: string;
  onRename: () => void;
  onExport: () => void;
  onExportCompat: () => void;
  onDelete: () => void;
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
    // 通用格式（2026-09-22 第三步）：写对方读得懂的形态，用来把整本交给别的应用
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.share')), content: '导出为通用格式' })
      .onClick(() => {
        params.onExportCompat();
      })
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')), content: '删除' })
      .onClick(() => {
        params.onDelete();
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

// 回退路径（设备无 HDS Core syscap）：Navigation.menus 数组构造——无 stackBuilder 机制，
// 拼不出覆盖层，仍是官方两键数组（数组成员序 = 显示序 =【＋新建】在左、【导入】在右；
// 2026-09-22 导入导出笔起两键，value 兼作无障碍文案与自动化识别名）
function knowledgeLibMenuNav(onNew: () => void, onImport: () => void): NavigationMenuItem[] {
  return [{
    value: '新建知识库',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.plus')),
    action: onNew
  } as NavigationMenuItem, {
    value: '导入知识库',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_down_to_line')),
    action: onImport
  } as NavigationMenuItem];
}

@Component
export struct KnowledgeLibraryPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  @State private books: KnowledgeBookRow[] = [];
  // 列表重建纪元（reload 成功自增——键含「行身份 + 条数 + 纪元」，防同键不刷：改书名后
  // 返回、条目数变化都属于「键必须变」的形态，坑16 家族）
  @State private listEpoch: number = 0;
  // 各库条目数（一次 GROUP BY 查回，禁逐库查——P1-2；普通成员 + 纪元键保证重建时读到新值）
  private counts: Map<string, number> = new Map<string, number>();
  // 列表刷新广播（递增 tick——写点在 KnowledgeDb 各写函数收口处；@Watch 对同值不触发故用递增）
  @StorageProp(KNOWLEDGE_LIST_TICK_KEY) @Watch('onListTick') listTick: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 行卡菜单节点宿主（init 一次 / 弹出前重建 / dispose 成对——见域件注释）
  private rowMenu: KnowledgeRowMenuHost = new KnowledgeRowMenuHost();
  private deleteTarget: KnowledgeBookRow | null = null;
  // 命名对话框（新建 / 重命名两用——message 与初值随场景变，故按需构造赋成员位；坑7 姿态）
  private nameCtrl: CustomDialogController | null = null;
  // 待导入载荷（审阅弹窗期间持有；导入或取消后清空——弹窗是异步确认，载荷必须跨帧存活；
  // 书名单独持一份：落库时用，避免从 screen 里倒推）
  private pendingImport: KnowledgeScreenResult | null = null;
  private pendingName: string = '';
  // 导入审阅弹窗控制器（★ 按需构造赋成员位——坑7 姿态；message 依载荷动态拼，不能预建；
  // 技能页 importCtrl 同款姿势）
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
      },
      onDelete: (): void => {
      }
    });
    this.reload();
  }

  aboutToDisappear(): void {
    this.rowMenu.dispose();
  }

  private onListTick(): void {
    this.reload();
  }

  private reload(): void {
    queryBooks()
      .then((rows: KnowledgeBookRow[]): Promise<void> => {
        this.books = rows;
        const ids: string[] = rows.map((row: KnowledgeBookRow): string => row.id);
        return countEntriesOfBooks(ids).then((counts: Map<string, number>): void => {
          this.counts = counts;
          this.listEpoch = this.listEpoch + 1; // 键变重建（条数/书名变化也刷新）
        });
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({
          message: '知识库读取失败：' + (e as Error).message
        });
      });
  }

  // 行副行（条数取自本页缓存；查不到 = 0 条兜底——新库还没有行）
  private entryCountOf(bookId: string): number {
    return this.counts.get(bookId) ?? 0;
  }

  // 列表重建键（行身份 + 书名 + 条数 + 纪元——上屏成分全含，任一变化即重建）
  private listKey(): string {
    return 'knowledgeLib|' + this.listEpoch;
  }

  // 新建：达上限即就地拦截（P0-1 明确提示，不静默失败；不弹输入框让用户白填一遍）
  private onNewBook(): void {
    countBooks()
      .then((count: number): void => {
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
        this.getUIContext().getPromptAction().showToast({
          message: '知识库读取失败：' + (e as Error).message
        });
      });
  }

  // 建库落库（★ 2026-09-22 八百七十一节补重名拦截）：判定单源 = KnowledgeText.
  // knowledgeBookNameTaken（工具侧 create_book 同用，禁本页另写一套比较逻辑）；命中即 toast 并
  // **中断不落库**，照编辑页同名条目同款形制。判定时**现查一次**（不拿页面缓存），把「用户填名
  // 期间他处建了同名书」的窗口压到最小
  private createBook(name: string): void {
    queryBooks()
      .then((rows: KnowledgeBookRow[]): void => {
        if (knowledgeBookNameTaken(toBookItems(rows), name, '')) {
          this.getUIContext().getPromptAction().showToast({
            message: '已有同名知识库，换一个名称再试。'
          });
          return;
        }
        insertBook(name)
          .then((row: KnowledgeBookRow): void => {
            broadcastKnowledgeList();
            // 新库必为空库，直接进条目页（省一步「返回再点进来」）
            this.openBook(row.id);
          })
          .catch((e: Object): void => {
            this.getUIContext().getPromptAction().showToast({
              message: '创建失败：' + (e as Error).message
            });
          });
      })
      .catch((e: Object): void => {
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

  // 改名落库（重名先拦，**排除自身 id**——改回原名不算重名，与条目编辑页排除自身同口径；
  // 同值改名由 InputDialog 静默跳过，不会走到本判定）。与建库同一判定单源
  private renameBookIfFree(book: KnowledgeBookRow, name: string): void {
    queryBooks()
      .then((rows: KnowledgeBookRow[]): void => {
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
            this.getUIContext().getPromptAction().showToast({
              message: '重命名失败：' + (e as Error).message
            });
          });
      })
      .catch((e: Object): void => {
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

  private doDelete(): void {
    const target: KnowledgeBookRow | null = this.deleteTarget;
    this.deleteTarget = null;
    if (target === null) {
      return;
    }
    // 级联删（条目 + 助手引用 + 书行同一事务）+ 广播都在 KnowledgeDb 侧；本页只报结果
    deleteBookCascade(target.id)
      .then((): void => {
        this.getUIContext().getPromptAction().showToast({ message: '已删除' });
        broadcastKnowledgeList();
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
      });
  }

  // 进书详情页（返回经 onPop 重拉——条目数可能已变；坑17：子页 pop 带 result 才触发）
  private openBook(bookId: string): void {
    this.pathStack.pushPathByName(ROUTE_KNOWLEDGE_BOOK_PAGE, bookId, (): void => {
      this.reload();
    });
  }

  // ── 导出链（2026-09-22 导入导出笔；方案 §5）──

  // 导出（行卡菜单「导出」）：取库里已保存的条目（含来源标签，不涉任何编辑态表单）→ 序列化
  // → 写沙箱件 → 官方分享面板。失败 toast 中文原因不静默（P0-1）
  private async exportBook(book: KnowledgeBookRow): Promise<void> {
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      const rows: KnowledgeEntryRow[] = await queryEntries(book.id);
      const path: string = exportKnowledgeBook(ctx,
        book.name !== '' ? book.name : '未命名知识库', toEntryItems(rows),
        rows.map((row: KnowledgeEntryRow): string => row.source));
      await this.shareFile(path, ctx);
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '导出失败：' + (e as Error).message });
    }
  }

  // 通用格式导出（行卡菜单第三项，2026-09-22 第三步）：只写对方读得懂的三个字段（条目名 / 正文 /
  // 关键词），**无关键词的条目整条不写**——对方按关键词触发，没有关键词的条目在那边永不生效，
  // 与其产出一个死条目不如不写并明示原因（方案 §14-5 口径 C）。
  // toast 仅在**确实有条目被排除**时出现（提示纯函数在无排除时返空串 = 不打扰）；它排在分享面板
  // 之前弹——面板是系统窗口，弹出后 toast 会被它盖住
  private async exportBookCompat(book: KnowledgeBookRow): Promise<void> {
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      const rows: KnowledgeEntryRow[] = await queryEntries(book.id);
      const written: KnowledgeCompatWrite = exportKnowledgeBookCompat(ctx,
        book.name !== '' ? book.name : '未命名知识库', toEntryItems(rows));
      const tip: string = composeKnowledgeCompatExportTip(written.exported, written.dropped);
      if (tip !== '') {
        this.getUIContext().getPromptAction().showToast({ message: tip });
      }
      await this.shareFile(written.path, ctx);
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '导出失败：' + (e as Error).message });
    }
  }

  // 分享面板（照 SkillLibraryPage.shareFile 形制——utd 与 label 走 LogPage/ProviderShare 既有
  // 链的 FILE 形态；面板自带「另存为文件」）
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

  // ── 导入链（方案 §4 五闸）──

  // 导入知识库：库满先拦（不弹选择器不让用户白选一遍）→ 选择器单件 .json → 扩展名分派 →
  // 解析（整份拒四态）→ 条目数上限闸 → 逐条分派（全不可导入即拒并报首条原因）→ 书名重名拒
  // （判定单源 knowledgeBookNameTaken，现查一次把窗口压到最小——与建库链同款）→ 审阅弹窗。
  // 任何一步失败都 toast 中文原因，不静默（P0-1）
  private async importBook(): Promise<void> {
    try {
      const count: number = await countBooks();
      if (count >= KNOWLEDGE_BOOK_MAX) {
        this.getUIContext().getPromptAction().showToast({
          message: '知识库数量已达上限，请先删除不再使用的知识库。'
        });
        return;
      }
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({
        message: '知识库读取失败：' + (e as Error).message
      });
      return;
    }
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      // 导入 = 单件动作（只取 uris[0]）：maxSelectNumber=1 守卫多选静默丢失
      //（DataSyncPage.doImport / 技能页 importPack 同款）
      const selectOpts: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      selectOpts.maxSelectNumber = 1;
      // 后缀过滤（d.ts 形制：'|' 左描述右后缀）。「该参数仅部分设备能力可用」（d.ts 原文），
      // 不得当唯一防线——真闸是下方扩展名分派 + 中文兜底提示
      selectOpts.fileSuffixFilters = ['知识库文件|.json'];
      const uris: Array<string> = await docPicker.select(selectOpts);
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
        // 整份拒（部分导入会产出「缺了后 M-100 条」的半成品副本，比明确拒绝更接近静默丢件；
        // 拒绝文案给出路：可在原应用里拆成两本再分别导入——方案 §4.2）
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
      if (knowledgeBookNameTaken(toBookItems(books), read.name, '')) {
        this.getUIContext().getPromptAction().showToast({
          message: '知识库「' + read.name + '」已存在，请先改名或删除后再导入。'
        });
        return;
      }
      this.confirmImport(read.name, screen, read.notice);
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '导入失败：' + (e as Error).message });
    }
  }

  // 审阅确认（ConfirmDialog 按需构造赋成员位——坑7；message 由纯函数拼装，带结构上界：
  // 条目名封顶 8 项 / 未导入封顶 3 条 / 安全行恒末，长清单不会把两键顶出屏）。取消键回收
  // 载荷（技能页自检轮补丁同款；遮罩关闭无回调，由下次导入覆盖，单份载荷有界）。
  // notice = 外部世界书的附注（已停用条数 / 注入设置未导入），自家格式恒空串——原样透传给
  // 拼装函数，本页不解读
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
  //（与建库链同款省一步）
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
        this.getUIContext().getPromptAction().showToast({
          message: '导入失败：' + (e as Error).message
        });
      });
  }

  // 单条落库（串行递归——不并发：容量判定与实际写入之间不留竞态窗口，技能批量导入
  // importOne 同口径；单条失败不炸整批，计入未导入继续）。全部完成后：广播一次 → 汇总
  // toast → 进新书页
  private importOne(bookId: string, screen: KnowledgeScreenResult, index: number,
    done: number): void {
    if (index >= screen.importable.length) {
      broadcastKnowledgeList();
      this.reportImport(screen, done);
      this.openBook(bookId);
      return;
    }
    const item: KnowledgeFileEntry = screen.importable[index];
    insertEntry(bookId, { title: item.title, keywords: item.keywords, content: item.content },
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
      },
      onDelete: (): void => {
        this.askDelete(book);
      }
    }, this.immersiveLevel);
  }

  // 行卡（点卡进条目页 + 右侧四点键菜单）
  @Builder
  BookCard(row: KnowledgeBookRow) {
    Button() {
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text(row.name !== '' ? row.name : '未命名知识库')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.entryCountOf(row.id) + ' 条条目')
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
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .padding(14)
    .onClick((): void => {
      this.openBook(row.id);
    })
  }

  // 标题栏覆盖层（HDS 路径：右上角〔＋|导入〕双热区胶囊，2026-09-22 导入导出笔起两动作）——
  // 组件内 @Builder 挂载是硬约束（坑30：全局 @Builder 被官方 titleBar napi 直接调用时无视图
  // 上下文，启动即闪退）；键件与几何/光感双态走共用件 components/TitleBarKeys.ets，本页只
  // 注入两动作（技能库页同款）
  @Builder
  TitleBarContent() {
    Row() {
      TitleBarActionCapsule({
        leftIcon: $r('sys.symbol.plus'),
        leftLabel: '新建知识库',
        rightIcon: $r('sys.symbol.arrow_down_to_line'),
        rightLabel: '导入知识库',
        immersiveLevel: this.immersiveLevel,
        onLeftTap: (): void => {
          this.onNewBook();
        },
        onRightTap: (): void => {
          this.importBook();
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding({ right: TITLE_BAR_EDGE_INSET })
    .justifyContent(FlexAlign.End)
    .alignItems(VerticalAlign.Center)
    // 命中透传（二级页必需——覆盖层整栏铺在返回键上方，默认命中档会挡住返回键，
    // 2026-09-11 记忆页真机实锤）
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 10 }) {
        if (this.books.length === 0) {
          // 空态行内提示行（13fp cardDescColor + CARD_PANEL_WIDTH 无卡底——同形先例归一形态）
          Text('暂无知识库。点右上角的「＋」新建，再到助手编辑页的知识库里启用。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
        } else {
          ForEach([this.listKey()], (_key: string) => {
            ForEach(this.books, (row: KnowledgeBookRow) => {
              this.BookCard(row)
            }, (row: KnowledgeBookRow): string => row.id + '|' + row.name + '|' +
              this.entryCountOf(row.id))
          }, (key: string): string => key)
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  build() {
    PageShell({
      title: SETTING_TITLE_KNOWLEDGE_LIBRARY,
      // 标题栏两键（★ 2026-09-22 导入导出笔）：HDS 路径 = 官方标题栏自定义区覆盖层里的双热区
      // 胶囊〔＋新建 | 导入〕（menuHds 传 null，键件与几何走共用件 TitleBarKeys；keepStackTitle
      // = true 保住主标题「知识库」，否则覆盖层会把标题置空）；回退路径无 stackBuilder 机制，
      // 仍是官方菜单数组两键（menuNav）
      menuHds: null,
      titleBarStack: (): void => {
        this.TitleBarContent();
      },
      keepStackTitle: true,
      menuNav: knowledgeLibMenuNav((): void => {
        this.onNewBook();
      }, (): void => {
        this.importBook();
      }),
      content: (): void => {
        this.Content();
      }
    })
  }
}
