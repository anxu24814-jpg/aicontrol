// 知识库书详情页（2026-09-21 世界书知识库首版，任务书-世界书知识库-20260921 §4.5②）：
// 单本知识库的条目清单——库管理页点行卡进本页（param = 书名 id），本页点条目行进条目编辑页。
// · 页标题 = 书名（aboutToAppear 按 param 查库；查不到 = 库已被删 → toast + 返回上一页——
//   不留一个标题空着、按什么都会失败的页面）。
// · 列表上方一行计数说明（共 N 条），条目行卡 = 标题（主行，助手写的行尾带「助手写入」小字标
//   〔2026-09-21 知识库第二笔下本：来源 = 行层 row.source，用户写的行无标〕）+ 副行摘要
//   （knowledgeEntrySummary：有关键词显示关键词，否则正文首段）+ 右侧四点键菜单（删除）。
// · 标题栏〔＋〕单键 = 新建条目（同库页，用共用件的单圆键）；条目数达 KNOWLEDGE_ENTRY_MAX
//   就地拦截 toast 且**不进编辑页**。
// · 删除：确认弹窗 → deleteEntry → 广播 + 本页重拉（本页自己就是条目清单，不需等广播）。
// · 刷新链：子页（条目编辑页）pop 带 result → onPop 重拉；本页删除后直接 reload；
//   @StorageProp(KNOWLEDGE_LIST_TICK_KEY) @Watch 兜底（其它入口改了同一本书时同步）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ComponentContent, LengthMetrics, SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { AppMenuHost } from '../../common/AppMenuHost';
import { PageShell } from '../../common/PageShell';
import { ROUTE_KNOWLEDGE_BOOK_PAGE, ROUTE_KNOWLEDGE_EDIT_PAGE } from '../../common/RouteNames';
import {
  CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor, menuDividerColor
} from '../../common/Theme';
import {
  IMMERSIVE_LEVEL_KEY, overlayMaterial, resolvedUiMaterial
} from '../../common/ImmersiveLevel';
import { TITLE_BAR_EDGE_INSET, TitleBarRoundKey } from '../TitleBarKeys';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import {
  broadcastKnowledgeList, countEntries, deleteEntry, KNOWLEDGE_ENTRY_MAX,
  KNOWLEDGE_LIST_TICK_KEY, KnowledgeBookRow, KnowledgeEntryRow, queryBook, queryEntries,
  toEntryItem
} from '../../common/store/KnowledgeDb';
import { knowledgeEntrySummary } from '../../common/KnowledgeText';

// 条目编辑页 push 参数载体（单源在本文件——编辑页只 import 消费，禁本地复写）
export interface KnowledgeEditParam {
  bookId: string;
  entryId: string; // '' = 新建
}

// ── 条目行卡四点键菜单：删除（锚点 = 四点键自身勿锚整卡）──
const KNOWLEDGE_ENTRY_MENU_ID_PREFIX: string = 'knowledgeEntryMenu_';

interface KnowledgeEntryMenuCallbacks {
  id: string;
  onDelete: () => void;
}

@Builder
function KnowledgeEntryMenuBuilder(params: KnowledgeEntryMenuCallbacks) {
  Menu() {
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

class KnowledgeEntryMenuHost extends AppMenuHost<KnowledgeEntryMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: KnowledgeEntryMenuCallbacks): ComponentContent<KnowledgeEntryMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(KnowledgeEntryMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  open(uiContext: UIContext, callbacks: KnowledgeEntryMenuCallbacks,
    immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, KNOWLEDGE_ENTRY_MENU_ID_PREFIX + callbacks.id,
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true),
      { targetSpace: LengthMetrics.vp(5) });
  }
}

// 回退路径（无 HDS Core syscap）：官方菜单数组单键
function knowledgeBookMenuNav(onNew: () => void): NavigationMenuItem[] {
  return [{
    value: '新建条目',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.plus')),
    action: onNew
  } as NavigationMenuItem];
}

@Component
export struct KnowledgeBookPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 页标题 = 书名（查询回填；未回填时占位——正常进页一帧内即填）
  @Prop title: string = '知识库';
  private bookId: string = '';
  @State private entries: KnowledgeEntryRow[] = [];
  // 列表重建纪元（reload 成功自增——键含「行身份 + 展示成分 + 纪元」，坑16 家族）
  @State private listEpoch: number = 0;
  @StorageProp(KNOWLEDGE_LIST_TICK_KEY) @Watch('onListTick') listTick: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  private rowMenu: KnowledgeEntryMenuHost = new KnowledgeEntryMenuHost();
  private deleteTarget: KnowledgeEntryRow | null = null;
  // 删除确认弹窗（坑7：组件成员位构造）
  private confirmCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: ConfirmDialog({
      title: '删除条目',
      message: '删除后无法恢复。',
      confirmLabel: '删除',
      onConfirm: (): void => {
        this.doDelete();
      }
    }),
    autoCancel: true
  });

  aboutToAppear(): void {
    const params: Array<Object | null> =
      (this.pathStack.getParamByName(ROUTE_KNOWLEDGE_BOOK_PAGE) ?? []) as Array<Object | null>;
    const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
    const bookId: string = typeof last === 'string' ? last : '';
    if (bookId === '') {
      this.getUIContext().getPromptAction().showToast({ message: '缺少知识库参数' });
      this.pathStack.pop();
      return;
    }
    this.bookId = bookId;
    this.rowMenu.init(this.getUIContext(), {
      id: '',
      onDelete: (): void => {
      }
    });
    queryBook(bookId)
      .then((book: KnowledgeBookRow | null): void => {
        if (book === null) {
          this.getUIContext().getPromptAction().showToast({ message: '知识库不存在或已删除' });
          this.pathStack.pop();
          return;
        }
        // 页标题随书（@Prop 单向同步，PageShell 内 @Prop title 会驱动标题栏重算）
        this.title = book.name;
        this.reload();
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({
          message: '知识库读取失败：' + (e as Error).message
        });
        this.pathStack.pop();
      });
  }

  aboutToDisappear(): void {
    this.rowMenu.dispose();
  }

  private onListTick(): void {
    this.reload();
  }

  private reload(): void {
    if (this.bookId === '') {
      return;
    }
    queryEntries(this.bookId)
      .then((rows: KnowledgeEntryRow[]): void => {
        this.entries = rows;
        this.listEpoch = this.listEpoch + 1;
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({
          message: '条目读取失败：' + (e as Error).message
        });
      });
  }

  // 列表重建键（纪元——条目增删改一律重建：行上屏成分含名称/关键词/正文摘要，任一变都要刷）
  private listKey(): string {
    return 'knowledgeBook|' + this.bookId + '|' + this.listEpoch;
  }

  // 新建条目：达上限即就地拦截（P0-1 明确提示；不进编辑页让用户白填一遍）
  private onNewEntry(): void {
    countEntries(this.bookId)
      .then((count: number): void => {
        if (count >= KNOWLEDGE_ENTRY_MAX) {
          this.getUIContext().getPromptAction().showToast({
            message: '这本知识库的条目已达上限，请先删除不再使用的条目。'
          });
          return;
        }
        this.openEditPage('');
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({
          message: '条目读取失败：' + (e as Error).message
        });
      });
  }

  // 进条目编辑页（entryId = '' 新建；返回经 onPop 重拉——子页保存 pop 带 result，坑17）
  private openEditPage(entryId: string): void {
    const param: KnowledgeEditParam = { bookId: this.bookId, entryId: entryId };
    this.pathStack.pushPathByName(ROUTE_KNOWLEDGE_EDIT_PAGE, param, (): void => {
      this.reload();
    });
  }

  private openRowMenu(entry: KnowledgeEntryRow): void {
    this.rowMenu.open(this.getUIContext(), {
      id: entry.id,
      onDelete: (): void => {
        this.deleteTarget = entry;
        this.confirmCtrl.open();
      }
    }, this.immersiveLevel);
  }

  private doDelete(): void {
    const target: KnowledgeEntryRow | null = this.deleteTarget;
    this.deleteTarget = null;
    if (target === null) {
      return;
    }
    deleteEntry(target.id)
      .then((): void => {
        this.getUIContext().getPromptAction().showToast({ message: '已删除' });
        // 本页就是条目清单：先自刷，再广播让库页的「N 条条目」跟着走
        this.reload();
        broadcastKnowledgeList();
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
      });
  }

  // 条目行卡（点卡进编辑页 + 右侧四点键菜单）
  @Builder
  EntryCard(row: KnowledgeEntryRow) {
    Button() {
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Row({ space: 6 }) {
            Text(row.title !== '' ? row.title : '未命名条目')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            // 助手写入的行尾小字标（★ 2026-09-21 知识库第二笔下本）：来源 = 行层 row.source
            //（'user' / 'assistant'，只在 create 时定、编辑不翻转；用户写的行**无标**——默认态
            // 不噪，照技能库只标「内置」行同款）。形制与技能库「内置」标逐字同源：13fp +
            // sys.color.ohos_id_color_emphasize（SkillLibraryPage 先例，禁自创色值/字号）。
            // ★ 不占 maxLines 名行的截断预算（标记是同行尾随，标题先截断）
            if (row.source === 'assistant') {
              Text('助手写入')
                .fontSize(13)
                .fontColor($r('sys.color.ohos_id_color_emphasize'))
            }
          }
          .alignItems(VerticalAlign.Center)
          Text(knowledgeEntrySummary(toEntryItem(row)))
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
        .id(KNOWLEDGE_ENTRY_MENU_ID_PREFIX + row.id)
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
      this.openEditPage(row.id);
    })
  }

  @Builder
  TitleBarContent() {
    Row() {
      TitleBarRoundKey({
        icon: $r('sys.symbol.plus'),
        label: '新建条目',
        immersiveLevel: this.immersiveLevel,
        onTap: (): void => {
          this.onNewEntry();
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding({ right: TITLE_BAR_EDGE_INSET })
    .justifyContent(FlexAlign.End)
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 10 }) {
        // 计数说明行（列表上方——先说明后操作同精神；13fp 次要色无卡底）
        Text('共 ' + this.entries.length + ' 条')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width(CARD_PANEL_WIDTH)
        if (this.entries.length === 0) {
          Text('暂无条目。点右上角的「＋」新建。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
        } else {
          ForEach([this.listKey()], (_key: string) => {
            ForEach(this.entries, (row: KnowledgeEntryRow) => {
              this.EntryCard(row)
            }, (row: KnowledgeEntryRow): string => row.id + '|' + row.title + '|' +
              row.keywords + '|' + row.content)
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
      title: this.title,
      menuHds: null,
      titleBarStack: (): void => {
        this.TitleBarContent();
      },
      keepStackTitle: true,
      menuNav: knowledgeBookMenuNav((): void => {
        this.onNewEntry();
      }),
      content: (): void => {
        this.Content();
      }
    })
  }
}
