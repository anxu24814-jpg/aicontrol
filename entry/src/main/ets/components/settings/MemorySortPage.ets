// 记忆排序页（2026-09-12 记忆自定义注入顺序——决明拍板「增加自定义注入顺序功能，用类似
// 服务商页的卡片排序方式，按卡片序注入」+ 同日自检轮补拍板「全链卡序」）：1:1 同构
// ProviderSortPage.ets（拖拽排序母版——防切几何三坑随范式全带）。
// · 排序语义 = 卡片序即注入序：拖拽落定整库回写 sortOrder = 下标，三键（sortOrder →
// createdAt → content）四路消费同源（页面显示 / 注入选取 / 提取去重清单 / 优化输入序号
// 基准）——顶部 30 条 = 注入窗口；★ v35（2026-09-20 助手级记忆）按库上下文读写——
// push param = { libraryId }（'global' = 全局库 / 助手 id = 助手库），读 queryMemories /
// queryAssistantMemories，写 saveMemoryOrder / saveAssistantMemoryOrder；
// · 卡内容 = 记忆条目内容单行省略（500 字上限内容禁全量直出；行卡不必展示完整内容，
// 卡高一致口径与记忆库管理页行卡同源）；
// · 刷新链（坑17 范式）：onBackPressed 拦截官方返回链 → pop({ saved: true }) → 库管理页
// onPop 自动 reload 重拉新序；
// · 母版三坑（ProviderSortPage 头注释）：①List 无水平 padding + alignListItem(Center) +
// ListItem 宽 calc(100% - 48vp)（两侧 24vp 头部空间容纳浮起放大出头，防内容区裁切坑10）；
// ②ListItem 同挂 borderRadius(16)（拖拽快照四角不带矩形底）；③管理页（库管理页）不留
// 拖拽手柄防误导。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_MEMORY_SORT_PAGE } from '../../common/RouteNames';
import { MEMORY_SCOPE_GLOBAL, MemoryRow, queryAssistantMemories, queryMemories,
  saveAssistantMemoryOrder, saveMemoryOrder } from '../../common/store/MemoryDb';
import { CARD_SPACING, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';
// push 参数载体（interface 单源 = MemoryLibraryPage.ets）
import { MemorySortParam } from './MemoryLibraryPage';

// 排序条目宽（= 屏宽 - 48：两侧 24vp 头部空间容纳浮起放大出头，防内容区裁切——母版
// 同款；勿改回屏宽-32：头部空间缩水后放大切边复现）
const SORT_ITEM_WIDTH: string = 'calc(100% - 48vp)';

@Component
export struct MemorySortPage {
  // 顶部/底部留白（PageMapBuilder 注入，offset 轨消费——ProviderSortPage 同款）
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 官方路由栈（PageMapBuilder 注入——返回时 pop 带 result 触发库管理页 onPop，坑17）
  pathStack: NavPathStack = new NavPathStack();
  // 目标库（aboutToAppear 从 push param 解析——'global' = 全局库 / 助手 id = 助手库）
  private libraryId: string = MEMORY_SCOPE_GLOBAL;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State private rows: MemoryRow[] = [];

  aboutToAppear(): void {
    // param 解析（对象形态 { libraryId }；字符串/缺省 = 全局库兜底——旧形态零破坏）
    const params: Array<Object | null> =
      (this.pathStack.getParamByName(ROUTE_MEMORY_SORT_PAGE) ?? []) as Array<Object | null>;
    const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
    if (last !== null && typeof last !== 'string') {
      const parsed = last as MemorySortParam;
      if (typeof parsed.libraryId === 'string' && parsed.libraryId !== '') {
        this.libraryId = parsed.libraryId;
      }
    }
    this.reload();
  }

  private reload(): void {
    const read: Promise<MemoryRow[]> = this.libraryId === MEMORY_SCOPE_GLOBAL ?
      queryMemories() : queryAssistantMemories(this.libraryId);
    read
      .then((rows: MemoryRow[]): void => {
        this.rows = rows;
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '记忆列表读取失败：' + (e as Error).message });
      });
  }

  // 拖拽落定：数据源 splice（官方 onMove 语义）+ 全量回写 sortOrder（母版同形制；按库
  // 分派回写原语——ids = 本库全量 id）
  private applyDragMove(from: number, to: number): void {
    const next: MemoryRow[] = this.rows.slice();
    const moved: MemoryRow = next.splice(from, 1)[0];
    next.splice(to, 0, moved);
    this.rows = next;
    const write: Promise<void> = this.libraryId === MEMORY_SCOPE_GLOBAL ?
      saveMemoryOrder(next.map((row: MemoryRow): string => row.id)) :
      saveAssistantMemoryOrder(next.map((row: MemoryRow): string => row.id));
    write
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '排序保存失败：' + (e as Error).message });
      });
  }

  // 列表内容（坑39 红线：@BuilderParam content 位挂组件内 @Builder 方法）
  @Builder
  Content() {
    List({ space: CARD_SPACING }) {
      ForEach(this.rows, (row: MemoryRow) => {
        ListItem() {
          Row({ space: 10 }) {
            // 拖拽手柄（自绘两横线——母版同款形制；拖拽由长按整卡触发）
            Column({ space: 3 }) {
              Row()
                .width(14)
                .height(2)
                .borderRadius(1)
                .backgroundColor(cardDescColor())
              Row()
                .width(14)
                .height(2)
                .borderRadius(1)
                .backgroundColor(cardDescColor())
            }
            .padding(4)

            // 记忆内容单行省略（500 字上限内容禁全量直出——卡高一致口径与记忆页行卡同源）
            Text(row.content)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(16)
          .alignItems(VerticalAlign.Center)
        }
        .borderRadius(16)
        .width(SORT_ITEM_WIDTH)
      }, (row: MemoryRow): string => row.id)
        // 官方拖拽排序（ForEach.onMove——母版同款，语义见头注释）
        .onMove((from: number, to: number): void => {
          this.applyDragMove(from, to);
        })

      if (this.rows.length === 0) {
        ListItem() {
          Text('暂无记忆，先在记忆库管理页新增')
            .fontSize(13)
            .fontColor(cardDescColor())
            .textAlign(TextAlign.Center)
            .width('100%')
            .padding(24)
            .backgroundColor(cardBg(this.appColorMode))
            .borderRadius(16)
        }
        .borderRadius(16)
        .width(SORT_ITEM_WIDTH)
      }
    }
    .width('100%')
    .height('100%')
    // ★ 防切几何（头注释）：无水平 padding = 内容区整宽（裁剪边界即屏幕缘），窄卡由
    // ListItem 宽 + alignListItem 居中承担——浮起放大落在头部空间内不再被裁（坑10）
    .alignListItem(ListItemAlign.Center)
    .contentStartOffset(this.topPad)
    .contentEndOffset(this.bottomPad + 16)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
  }

  build() {
    PageShell({
      title: '排序记忆',
      content: (): void => {
        this.Content()
      },
      // 坑17：拦截官方返回链 → pop 带 result 触发记忆页 onPop 重拉新序（排序 onMove
      // 已实时落库，返回即需刷新；未拖拽直接返回同样触发 reload，代价 = 一次查询可忽略）
      onBackPressed: (): boolean => {
        this.pathStack.pop({ saved: true });
        return true;
      }
    })
  }
}
