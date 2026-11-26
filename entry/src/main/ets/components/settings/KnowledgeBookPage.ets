// 知识库书详情页：单本知识库的条目清单——库管理页点行卡进本页（param = 书名 id），点条目行
// 进条目编辑页；标题栏〔＋〕新建条目（达上限就地拦截 toast 且不进编辑页）。
// · 页标题 = 书名（aboutToAppear 按 param 查库；查不到 = 库已删 → toast + 返回，不留空标题死页）。
// · 条目行卡 = 标题（助手写入的行尾带 Badge）+ 摘要行 + 启用开关（行尾唯一控件）；右侧四点键
//   菜单已退役，删除唯一走行左滑确认链。
// · 删除：确认弹窗 → deleteEntry → 广播 + 本页重拉（本页就是清单，不等广播）。
// · 刷新链：子页 pop 带 result → onPop 重拉；本页删除后直接 reload；KNOWLEDGE_LIST_TICK_KEY
//   @Watch 兜底（其它入口改了同一本书时同步）。
// · 长列表 = List + Repeat.virtualScroll（V1 壳 + V2 渲染件，规范 §4.6）：键只写条目 id，上屏
//   字段靠同 id 新对象 item 比对刷新（坑16 等价接替）；头槽挂计数行；让位 offset 轨。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { UIUtils } from '@kit.ArkUI';
import { PageShell } from '../../common/PageShell';
import { ROUTE_KNOWLEDGE_BOOK_PAGE, ROUTE_KNOWLEDGE_EDIT_PAGE } from '../../common/RouteNames';
import {
  CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS
} from '../../common/Theme';
import {
  IMMERSIVE_LEVEL_KEY, overlayMaterial
} from '../../common/ImmersiveLevel';
import { TITLE_BAR_EDGE_INSET, TitleBarRoundKey } from '../TitleBarKeys';
import { ConfirmDialog } from '../chat/ConfirmDialog';
import {
  broadcastKnowledgeList, countEntries, deleteEntry, KNOWLEDGE_ENTRY_MAX,
  KNOWLEDGE_LIST_TICK_KEY, KnowledgeBookRow, KnowledgeEntryRow, queryBook, queryEntries,
  setEntryEnabled, toEntryItem
} from '../../common/store/KnowledgeDb';
import { knowledgeEntrySummary } from '../../common/KnowledgeText';
// 全站状态徽标形制单源（实底胶囊）
import { StatusBadge } from '../StatusBadge';
// 行级左滑删除层（交互基准 = 会话页 SessionSwipeItem；互斥口径见该件头注释）
import { RowSwipeDelete, SwipeGroup } from '../RowSwipeDelete';

// 条目编辑页 push 参数载体（单源在本文件——编辑页只 import 消费，禁本地复写）
export interface KnowledgeEditParam {
  bookId: string;
  entryId: string; // '' = 新建
}

@Component
export struct KnowledgeBookPage {
  // 页面存活守卫（销毁治理）：迟到异步回调不写状态、不碰 UI、不上行；写库照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  @Prop title: string = '知识库';
  private bookId: string = '';
  @State private entries: KnowledgeEntryRow[] = [];
  @StorageProp(KNOWLEDGE_LIST_TICK_KEY) @Watch('onListTick') listTick: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  private deleteTarget: KnowledgeEntryRow | null = null;
  // 行左滑互斥组（容器单源——reload 重拉时 collapse，滚动开始经组收口）
  private swipeGroup: SwipeGroup = new SwipeGroup();
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
    queryBook(bookId)
      .then((book: KnowledgeBookRow | null): void => {
        if (this.departed) {
          return;
        }
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
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({
          message: '知识库读取失败：' + (e as Error).message
        });
        this.pathStack.pop();
      });
  }

  aboutToDisappear(): void {
    this.departed = true;
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
        if (this.departed) {
          return;
        }
        // 可见行重拉 → 收起左滑展开行（会话层侧滑五笔同口径：可见集变化由容器侧统一收回）
        this.swipeGroup.collapse();
        this.entries = rows;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({
          message: '条目读取失败：' + (e as Error).message
        });
      });
  }

  // 新建条目：达上限即就地拦截（P0-1 明确提示；不进编辑页让用户白填一遍）
  private onNewEntry(): void {
    countEntries(this.bookId)
      .then((count: number): void => {
        if (this.departed) {
          return;
        }
        if (count >= KNOWLEDGE_ENTRY_MAX) {
          this.getUIContext().getPromptAction().showToast({
            message: '这本知识库的条目已达上限，请先删除不再使用的条目。'
          });
          return;
        }
        this.openEditPage('');
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
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

  // 删除确认单入口（左滑删除键 / 长距直达同链；四点菜单退役后为唯一删除路径）
  private askDeleteEntry(entry: KnowledgeEntryRow): void {
    this.deleteTarget = entry;
    this.confirmCtrl.open();
  }

  // 启用开关（自编辑页迁入）：乐观整体替换 + 单列写库 + 失败恢复旧数组。
  // Repeat 键只写条目 id，必须换新数组让同 id 新对象 item 比对驱动 Toggle/角标刷新；
  // 成功广播供库页刷新，本页 @Watch 随之 reload 以库为准（P0-1 失败不静默）。
  private toggleEntryEnabled(row: KnowledgeEntryRow, isOn: boolean): void {
    const prev: KnowledgeEntryRow[] = this.entries;
    const next: KnowledgeEntryRow[] = [];
    for (const item of this.entries) {
      if (item.id !== row.id) {
        next.push(item);
        continue;
      }
      const changed: KnowledgeEntryRow = {
        id: item.id, bookId: item.bookId, title: item.title, keywords: item.keywords,
        content: item.content, source: item.source, injectRole: item.injectRole,
        injectPosition: item.injectPosition, injectDepth: item.injectDepth,
        enabled: isOn ? 1 : 0, createdAt: item.createdAt, updatedAt: item.updatedAt,
        sortOrder: item.sortOrder,
        // 触发精度四字段原样携带（乐观替换不改配置值）
        matchCase: item.matchCase, matchWhole: item.matchWhole,
        priority: item.priority, scanDepth: item.scanDepth
      };
      next.push(changed);
    }
    this.entries = next;
    setEntryEnabled(row.id, isOn)
      .then((): void => {
        if (this.departed) {
          return;
        }
        broadcastKnowledgeList();
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.entries = prev;
        this.getUIContext().getPromptAction().showToast({
          message: '保存失败：' + (e as Error).message
        });
      });
  }

  private doDelete(): void {
    const target: KnowledgeEntryRow | null = this.deleteTarget;
    this.deleteTarget = null;
    if (target === null) {
      return;
    }
    deleteEntry(target.id)
      .then((): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '已删除' });
        // 本页就是条目清单：先自刷，再广播让库页的「N 条条目」跟着走
        this.reload();
        broadcastKnowledgeList();
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
      });
  }

  @Builder
  CountLine() {
    Text('共 ' + this.entries.length + ' 条')
      .fontSize(13)
      .fontColor(cardDescColor())
      .width(CARD_PANEL_WIDTH)
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
    if (this.entries.length === 0) {
      // 0 行分支（壳侧 Scroll 兜底——Repeat 无行可挂；结构与间距沿用原 Scroll 形态）
      Scroll() {
        Column({ space: 10 }) {
          this.CountLine()
          Text('暂无条目。点右上角的「＋」新建。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
    } else {
      KnowledgeBookRows({
        entries: UIUtils.enableV2Compatibility(this.entries),
        appColorMode: this.appColorMode,
        topPad: this.topPad,
        bottomPad: this.bottomPad,
        group: this.swipeGroup,
        headSlot: (): void => {
          this.CountLine()
        },
        onOpen: (row: KnowledgeEntryRow): void => {
          this.openEditPage(row.id);
        },
        onToggleEnabled: (row: KnowledgeEntryRow, isOn: boolean): void => {
          this.toggleEntryEnabled(row, isOn);
        },
        // 左滑删除（删除键与长距直达同链，弹既有确认框——2026-10-25 四库左滑笔）
        onSwipeDelete: (row: KnowledgeEntryRow): void => {
          this.askDeleteEntry(row);
        }
      })
        .width('100%')
        .height('100%')
    }
  }

  build() {
    PageShell({
      title: this.title,
      menuHds: null,
      titleBarStack: (): void => {
        this.TitleBarContent();
      },
      keepStackTitle: true,
      content: (): void => {
        this.Content();
      }
    })
  }
}

// ═══ 条目清单渲染域（迁 Repeat 拆出，同文件同域——壳引渲染件单向）═══
// List + Repeat.virtualScroll（V2）：数据源壳侧构造处桥接；键只写条目 id（上屏字段靠同 id 新
// 对象 item 比对刷新，坑16 键载荷机制等价接替）；头槽 = 壳侧计数行挂首行；让位 offset 轨；
// 0 行壳侧分支渲染。行卡事件上行壳侧执行。
// ★ 行卡包 RowSwipeDelete（共享横滑层——左滑删除键 + 长距直达）；展开态不进键；滚动开始经组
// 收起；启用开关为行尾唯一控件（Toggle 自吞点击不冒泡卡片 onClick）。
@ComponentV2
struct KnowledgeBookRows {
  // 条目清单（壳侧构造处桥接传入——Repeat 懒加载要求数据源具 V2 观察能力）
  @Param entries: KnowledgeEntryRow[] = [];
  @Param appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 左滑互斥组（壳侧单源）
  @Param group: SwipeGroup = new SwipeGroup();
  @Param topPad: number = 0;
  @Param bottomPad: number = 0;
  // 首行头槽（计数说明行——壳侧 V1 Builder，条数随整体替换刷新）
  @BuilderParam headSlot: () => void;
  // 事件透传壳侧回调（点卡进编辑 / 启用开关；★ 读当前 ri.item，禁构造期快照）
  @Event onOpen: (row: KnowledgeEntryRow) => void = () => {
  };
  @Event onToggleEnabled: (row: KnowledgeEntryRow, isOn: boolean) => void = () => {
  };
  @Event onSwipeDelete: (row: KnowledgeEntryRow) => void = () => {
  };

  // 条目行卡（点卡进编辑 + 启用开关；显示读当前 ri.item；卡 padding 4 + 壳 padding 10）
  @Builder
  EntryCard(ri: RepeatItem<KnowledgeEntryRow>) {
    Column() {
      Button() {
        Row({ space: 10 }) {
          Column({ space: 3 }) {
            Row({ space: 6 }) {
              Text(ri.item.title !== '' ? ri.item.title : '未命名条目')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              // 助手写入行尾标（source = 行层，用户行无标）；实底胶囊，不占名行截断预算
              if (ri.item.source === 'assistant') {
                StatusBadge({ text: '助手写入' })
              }
              // 两类角标（形制同「助手写入」；系统位且启用 = 无角标）：「已停用」= enabled 0（注入
              // 与检索双隐藏，灰字弱化）；「深度注入」= 深度位非 system 条目（system 身份的 depth
              // 脏值在注入链归系统块，角标与实际行为一致）
              if (ri.item.enabled === 0) {
                Text('已停用')
                  .fontSize(13)
                  .fontColor($r('sys.color.font_secondary'))
              }
              if (ri.item.injectPosition === 'depth' && ri.item.injectRole !== 'system') {
                StatusBadge({ text: '深度注入' })
              }
            }
            .alignItems(VerticalAlign.Center)
            Text(knowledgeEntrySummary(toEntryItem(ri.item)))
              .fontSize(13)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          // 启用开关（自编辑页迁入；ProviderCardItem 同形制）：停用 = 不参与自动注入与工具检索，
          // 管理清单仍可见——即时可逆不弹确认；Toggle 自吞点击不冒泡卡片 onClick
          Toggle({ type: ToggleType.Switch, isOn: ri.item.enabled !== 0 })
            .onChange((isOn: boolean): void => {
              this.onToggleEnabled(ri.item, isOn);
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
        this.onOpen(ri.item);
      })
    }
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  build() {
    List({ space: 10 }) {
      Repeat<KnowledgeEntryRow>(this.entries)
        .each((ri: RepeatItem<KnowledgeEntryRow>) => {
          ListItem() {
            Column({ space: 10 }) {
              if (ri.index === 0) {
                this.headSlot()
              }
              // 行卡包横滑层：头槽在包层外（横滑只移卡），收起态全穿透
              RowSwipeDelete({
                rowId: ri.item.id,
                group: this.group,
                content: (): void => {
                  this.EntryCard(ri)
                },
                onSwipeDelete: (id: string): void => {
                  this.onSwipeDelete(ri.item);
                }
              })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }
        })
        // 键 = 条目 id（身份唯一；上屏字段变化靠整体替换后 item 比对刷新，禁键载荷回潮）
        .key((row: KnowledgeEntryRow): string => row.id)
        .virtualScroll()
    }
    .width('100%')
    .height('100%')
    // 让位 offset 轨（原 Scroll padding top/bottom 同值等价）
    .contentStartOffset(this.topPad)
    .contentEndOffset(this.bottomPad + 16)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
    // 单书条目上限 100，5 为屏内缓冲（轻行卡；按页设值非全局口径）
    .cachedCount(5)
    .onScrollStart((): void => {
      this.group.collapse();
    })
  }
}
