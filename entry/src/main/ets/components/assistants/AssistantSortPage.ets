// 助手排序三级页（2026-09-22 助手自定义列表序，决明拍板）：1:1 同构 MemorySortPage /
// ProviderSortPage（拖拽排序母版——防切几何三坑随范式全带）。
// · 入口与形制：助手页签标题栏「⋯」更多菜单的「排序」项 push（原占位提示笔 876 的兑现）；
//   **进二级页而非列表内拖拽**不是照抄先例而是几何约束——ForEach.onMove 官方限 List 组件
//   （SDK common.d.ts「only applicable in a List component」），而助手页是 Scroll+Column
//   （为标题栏渐变模糊，坑9 红线；改回 List 会让 List padding 变视口缩进 = 蒙层空转），
//   故拖拽只能另起一页（服务商/记忆两页同款结论）。
// · 排序语义 = 卡片序即列表序：拖拽落定整表回写 sortOrder = 下标（saveAssistantOrder），
//   读侧 queryAssistants 按 sortOrder 升序 + createdAt 决胜出序。★ 本笔同时撤除旧读侧的
//   「内置两张恒列头部」硬钉——内置默认/控制台助手与其他助手一样可被拖到任意位置
//   （决明 2026-09-22 拍板；四家竞品一致：内置项不置顶，唯一内置特权是禁删）。存量设备的
//   可见序由 v39→v40 迁移回填复刻，升级后列表逐字不变。
// · 卡内容 = 名称单行省略（助手名上限 ASSISTANT_NAME_MAX 50 字，卡高一致口径与助手页卡同源）；
//   「当前助手」在本页不额外标记——本页只承担排序（ProvidersSort 同口径：无点击无信息展示）。
// · 刷新链（坑17 范式）：onBackPressed 拦截官方返回链 → pop({ saved: true }) → 助手页签
//   经指令键重拉新序（助手页属 TabContent 非常驻 push 页，菜单域无法直达其 reload——走
//   ASSISTANT_ORDER_CMD_KEY 指令键，与 ASSISTANT_CREATE_CMD_KEY 同机制、坑3 口径）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { AssistantRow, queryAssistants, saveAssistantOrder } from '../../common/store/AssistantDb';
import { CARD_SPACING, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';

// 排序条目宽（= 屏宽 - 48：两侧 24vp 头部空间容纳浮起放大出头，防内容区裁切——母版
// 同款；勿改回屏宽-32：头部空间缩水后放大切边复现）
const SORT_ITEM_WIDTH: string = 'calc(100% - 48vp)';

@Component
export struct AssistantSortPage {
  // 顶部/底部留白（PageMapBuilder 注入，offset 轨消费——母版同款）
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 官方路由栈（PageMapBuilder 注入——返回时 pop 带 result 触发助手页重拉，坑17）
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State private rows: AssistantRow[] = [];

  aboutToAppear(): void {
    this.reload();
  }

  private reload(): void {
    queryAssistants()
      .then((rows: AssistantRow[]): void => {
        this.rows = rows;
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '助手列表读取失败：' + (e as Error).message });
      });
  }

  // 拖拽落定：数据源 splice（官方 onMove 语义）+ 全量回写 sortOrder（母版同形制）
  private applyDragMove(from: number, to: number): void {
    const next: AssistantRow[] = this.rows.slice();
    const moved: AssistantRow = next.splice(from, 1)[0];
    next.splice(to, 0, moved);
    this.rows = next;
    saveAssistantOrder(next.map((row: AssistantRow): string => row.id))
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '排序保存失败：' + (e as Error).message });
      });
  }

  // 列表内容（坑39 红线：@BuilderParam content 位挂组件内 @Builder 方法）
  @Builder
  Content() {
    List({ space: CARD_SPACING }) {
      ForEach(this.rows, (row: AssistantRow) => {
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

            // 助手名单行省略（名上限 50 字——卡高一致口径与助手页卡同源；空名兜底 '?'）
            Text(row.name !== '' ? row.name : '?')
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
      }, (row: AssistantRow): string => row.id)
        // 官方拖拽排序（ForEach.onMove——母版同款，语义见头注释）
        .onMove((from: number, to: number): void => {
          this.applyDragMove(from, to);
        })

      if (this.rows.length === 0) {
        ListItem() {
          Text('暂无助手，先在助手页新建')
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
      title: '排序助手',
      content: (): void => {
        this.Content()
      },
      // 坑17：拦截官方返回链 → pop 带 result 触发助手页重拉新序（排序 onMove 已实时落库，
      // 返回即需刷新；未拖拽直接返回同样触发重拉，代价 = 一次查询可忽略）
      onBackPressed: (): boolean => {
        this.pathStack.pop({ saved: true });
        return true;
      }
    })
  }
}
