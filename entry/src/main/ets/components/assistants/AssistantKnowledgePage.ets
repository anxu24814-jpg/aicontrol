// 助手知识库启用页（2026-09-21 世界书知识库首版，任务书-世界书知识库-20260921 §4.5④；
// 用户可见名「知识库」）：助手编辑页「知识库」分区卡 push，param = 助手 id——形制照
// AssistantSkillPage 助手模式（开关组卡 + 管理入口行 + 上限拦截 + 失败回灌）。
// · 开关组卡（GroupSettingCard 开关行形态——只点开关切换，规范 §4.1）：行 = 书名（副标题 =
//   「N 条条目」）+ 行尾官方 Toggle；开关即时落库（KnowledgeText.serializeEnabledKnowledgeIds
//   唯一序列化落点）；页顶说明句 = 能力语义（模型按需自己去查，不是常驻注入）+ 上限。
// · ★ 启用上限 KNOWLEDGE_ENABLED_MAX（10）：第 11 个开关**在页面上直接拒**（toast + 纪元
//   回弹）——上限执行在开关面而非发送链，用户当场知道为什么开不上；判定在写入之前做
//   **整集合**判定（只按「当前个数 ≥ 上限」判会在连点/并发下漏）。
// · 「管理知识库」入口行：push 知识库库页（deep entry 第二入口，与设置页行卡成双入口）；
//   返回时**两样都要重读**（库页里可能删了书——不重读，内存里的悬空 id 会被下次拨开关
//   随序列化写回库，级联清列刚清掉的白写回来；AssistantSkillPage 同款理由）。
// · 空态：仓库为空时给引导语（先去设置 → 知识库建一本），组卡不出（空组卡无意义）。
// · 刷新链：@State enabledIds 驱动组卡重建键（键含状态 + 纪元——GroupSettingCard 头注释
//   「开关显示刷新责任在调用方」）；库页返回经 push 回调 reload。
// · 返回带 result（坑17）——pop({ saved: true }) 触发编辑页 onPop 重拉「已启用 N 个知识库」摘要。
import { PageShell } from '../../common/PageShell';
import { CARD_SPACING, cardDescColor, CARD_PANEL_WIDTH } from '../../common/Theme';
import { GroupEntryItem, GroupSettingCard } from '../GroupSettingCard';
import {
  AssistantRow, queryAssistant, updateAssistantKnowledge
} from '../../common/store/AssistantDb';
import {
  countEntriesOfBooks, KnowledgeBookRow, KNOWLEDGE_ENABLED_MAX, queryBooks
} from '../../common/store/KnowledgeDb';
import {
  parseEnabledKnowledgeIds, serializeEnabledKnowledgeIds
} from '../../common/KnowledgeText';
import { ROUTE_ASSISTANT_KNOWLEDGE_PAGE, ROUTE_KNOWLEDGE_LIBRARY_PAGE } from '../../common/RouteNames';

@Component
export struct AssistantKnowledgePage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 库内知识库清单（aboutToAppear 与库页返回时重拉）
  @State private books: KnowledgeBookRow[] = [];
  // 已启用知识库 id（助手行 knowledge 列解析产物；Toggle 上行即写库 + 写本状态驱动组卡重建）
  @State private enabledIds: string[] = [];
  // 组卡重建纪元（★ 坑16 家族 / AssistantSkillPage.toggleEpoch 同款）：GroupSettingCard.items
  // 是普通成员入参，父组件重渲不更新它、组件自身无状态变化 → 行 Toggle 定格首帧。尤其
  // **第 11 个开关被拒**这条：Toggle 内部态已随用户点击翻成开，而拒绝路径不写任何数据——
  // 若纪元不自增，键不变 → 组卡不重建 → 开关停在「开」的假象上。故本纪元在**载入与每次
  // 开关交互（含被拒）**都自增
  @State private toggleEpoch: number = 0;
  private rowId: string = '';

  aboutToAppear(): void {
    const params: Array<string> =
      this.pathStack.getParamByName(ROUTE_ASSISTANT_KNOWLEDGE_PAGE) as Array<string>;
    const param: string | undefined = params.length > 0 ? params[params.length - 1] : undefined;
    if (param === undefined || param === '') {
      this.getUIContext().getPromptAction().showToast({ message: '缺少助手参数' });
      this.pathStack.pop();
      return;
    }
    this.rowId = param;
    queryAssistant(param)
      .then((row: AssistantRow | null): void => {
        if (row === null) {
          this.getUIContext().getPromptAction().showToast({ message: '助手不存在或已删除' });
          this.pathStack.pop();
          return;
        }
        this.enabledIds = parseEnabledKnowledgeIds(row.knowledge);
        this.toggleEpoch += 1; // 库读回也自增（进页即拉新值，不依赖首帧）
        this.reloadBooks();
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({
          message: '知识库启用清单读取失败：' + (e as Error).message
        });
        this.pathStack.pop();
      });
  }

  // 各库条目数（行副标题用；一次 GROUP BY 查回，禁逐库查——P1-2；普通成员 + 纪元键保证
  // 重建时读到新值）
  private counts: Map<string, number> = new Map<string, number>();

  // 知识库清单重拉（库页返回时调用——库内增删后本页清单同步；失败 toast 不静默 P0-1）
  private reloadBooks(): Promise<void> {
    return queryBooks()
      .then((rows: KnowledgeBookRow[]): Promise<void> => {
        this.books = rows;
        const ids: string[] = rows.map((row: KnowledgeBookRow): string => row.id);
        return countEntriesOfBooks(ids).then((counts: Map<string, number>): void => {
          this.counts = counts;
          this.toggleEpoch += 1; // 条数变化也要让组卡重建（副标题在行上）
        });
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({
          message: '知识库读取失败：' + (e as Error).message
        });
      });
  }

  // 开关目标集合 + 整集合上限判定：返回 null = 超限已拒（toast + 纪元回弹已做）。
  // ★ 上限判定在写入之前做**整集合**判定：只按「当前个数 ≥ 上限」判会在连点/并发下漏
  //（同一刻度内两次开都通过），故按本次目标集合长度判——目标集合超限即拒，开关状态不动
  private nextToggleSet(bookId: string, isOn: boolean): string[] | null {
    const next: string[] = isOn ?
      (this.enabledIds.includes(bookId) ? this.enabledIds.slice() :
        this.enabledIds.concat([bookId])) :
      this.enabledIds.filter((item: string): boolean => item !== bookId);
    if (isOn && next.length > KNOWLEDGE_ENABLED_MAX) {
      this.getUIContext().getPromptAction().showToast({
        message: '最多启用 ' + KNOWLEDGE_ENABLED_MAX + ' 个知识库'
      });
      // 数据不动（本页是唯一控制面，无第二真相），但**纪元必须自增**——Toggle 内部态已被
      // 这次点击翻成开，纪元不动 = 键不变 = 卡不重建 = 开关停在开（假象）；自增即重建回读
      // enabledIds → 开关弹回关，与 toast 一起构成「拒了且没生效」的完整反馈
      this.toggleEpoch += 1;
      return null;
    }
    return next;
  }

  // 开关落库（即时生效，失败 toast + 回读回滚——P0-1）
  private toggleBook(bookId: string, isOn: boolean): void {
    const next: string[] | null = this.nextToggleSet(bookId, isOn);
    if (next === null) {
      return;
    }
    this.enabledIds = next;
    this.toggleEpoch += 1;
    const serialized: string = serializeEnabledKnowledgeIds(next);
    updateAssistantKnowledge(this.rowId, serialized)
      .catch((e: Object): void => {
        this.reloadEnabledIds();
        this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
      });
  }

  // 失败回滚：库读回灌（单一真源——AssistantSkillPage 同款理由：取反回滚在连点时会把
  // 第二笔的态一并推翻）
  private reloadEnabledIds(): void {
    queryAssistant(this.rowId)
      .then((row: AssistantRow | null): void => {
        if (row !== null) {
          this.enabledIds = parseEnabledKnowledgeIds(row.knowledge);
          this.toggleEpoch += 1; // 回滚/重读也自增（「每次启用集写入都自增」这条不变量不留缺口）
        }
      })
      .catch((): void => {
      });
  }

  // 开关行数据（GroupSettingCard 开关行：toggleValue/onToggle 两字段齐全，行尾官方 Toggle
  // 唯一控制面；副标题 = 「N 条条目」——空副标题行会掉到 56vp 档观感不一致）
  private bookRows(): GroupEntryItem[] {
    const items: GroupEntryItem[] = [];
    for (const book of this.books) {
      items.push({
        icon: $r('sys.symbol.book'),
        label: book.name !== '' ? book.name : '未命名知识库',
        secondary: (this.counts.get(book.id) ?? 0) + ' 条条目',
        toggleValue: (): boolean => this.enabledIds.includes(book.id),
        onToggle: (isOn: boolean): void => {
          this.toggleBook(book.id, isOn);
        }
      });
    }
    return items;
  }

  // 「管理知识库」入口行（跳转行形态：onClick 上抛 push）
  private manageRow(): GroupEntryItem[] {
    return [{
      icon: $r('sys.symbol.bookshelf'),
      label: '管理知识库',
      secondary: '新建、编辑或删除知识库',
      onClick: (): void => {
        this.openKnowledgeLibrary();
      }
    }];
  }

  // 组卡重建键（键含启用集 + 库内清单 + **重建纪元**——任一变即重建拉新 Toggle；
  // GroupSettingCard 头注释「开关显示刷新责任在调用方」）
  private switchGroupKey(): string {
    const ids: string = this.enabledIds.join(',');
    const names: string = this.books.map((row: KnowledgeBookRow): string =>
      row.id + ':' + row.name + ':' + (this.counts.get(row.id) ?? 0)).join(',');
    return ids + '|' + names + '|' + this.toggleEpoch;
  }

  // 「管理知识库」跳转：返回时**两样都要重读**（库里删掉某本书后，页内 enabledIds 里那条
  // id 还在内存里，下次拨任何开关都会把它随序列化一起写回库——级联清列刚清掉的白写回来）
  private openKnowledgeLibrary(): void {
    this.pathStack.pushPathByName(ROUTE_KNOWLEDGE_LIBRARY_PAGE, null, (): void => {
      this.reloadBooks().then((): void => {
        this.reloadEnabledIds();
      });
    });
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        // 页顶说明小字（13fp 次要色 + 卡宽无卡底——空态行同款归一形态）。句意 = 这功能怎么
        // 生效（模型按需自己去查，不是把条目常驻塞进对话）+ **工具卡前置**（★ 2026-09-21
        // 自检轮补：检索工具 defaultEnabled=false，用户只开本页开关而「知识库」卡未开时
        // 功能静默不生效——帮助条目同笔补同义句，两处互为兜底）+ 上限（数字随常量拼接不写死）。
        // ★ 2026-09-21 剥离笔：卡名随形「本地检索」→「知识库」（search_knowledge 已自本地检索
        // 卡移到本名的卡，旧句指错卡 = 用户照做仍不生效——151 组文案钉同笔随形）
        Text('知识库是助手按需查阅的词条本。开启后，助手觉得需要某领域的知识时会自己去查。'
          + '检索知识库的工具默认关闭，先在「工具调用」里打开「知识库」卡。最多同时启用 '
          + KNOWLEDGE_ENABLED_MAX + ' 个知识库。')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width(CARD_PANEL_WIDTH)
        if (this.books.length === 0) {
          // 空态行内提示行（13fp 次要色 + 卡宽无卡底；本页不进空组卡——一张没有行的开关卡
          // 在页面上是纯噪声）
          Text('还没有知识库。可在设置 → 知识库里新建。')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
        } else {
          ForEach([this.switchGroupKey()], (_key: string) => {
            GroupSettingCard({ items: this.bookRows() })
          }, (key: string): string => key)
        }
        GroupSettingCard({ items: this.manageRow() })
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
      title: '知识库',
      onBackPressed: (): boolean => {
        // 完成返回带 result（坑17）：编辑页 onPop 据此重拉「已启用 N 个知识库」摘要
        this.pathStack.pop({ saved: true });
        return true;
      },
      content: (): void => {
        this.Content();
      }
    })
  }
}
