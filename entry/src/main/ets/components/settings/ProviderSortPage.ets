// 服务商排序页（2026-08-30 反馈轮 6，领导方案）：管理页拖拽浮起被列表内容区裁切（坑10，
// dragPreview 亦无效）转向——管理页摘拖拽，排序独立成页。卡片仅承担排序（拖拽手柄 +
// 名称；无点击编辑、无信息展示、无开关菜单——领导明示）。
// ★ 卡几何 = 防切关键：List 无水平 padding（内容区整宽 = 裁剪边界即屏幕缘）+
// alignListItem(Center) 居中 + ListItem 宽 calc(100% - 48vp)（卡缘距内容区边界 24vp 头部
// 空间）——浮起放大约 1.05 倍（系统默认动效）超出卡缘 ≈8vp，落在头部空间内 = 不再被内容
// 区裁切（管理页卡缘贴边界即切边根因，坑10；dshinhm 全宽列表无切边同款几何）。ListItem
// 同 borderRadius 16（快照轮廓随条目，轮 2 四角修复口径）。
// 排序持久化：onMove 离手位置变化回调 splice + saveProviderOrder 全量回写（管理页原逻辑
// 迁入，服务商小数据集开销可忽略）。刷新通道（2026-08-30 坑17 统一）：返回 = onBackPressed
// 拦截官方返回链 → pop({ saved: true }) → 管理页 onPop 自动 reload 重拉新序（触发条件 =
// pop 必带 result）；菜单「刷新」键仍作手动兜底。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { ProviderRow, queryProviders, saveProviderOrder } from '../../common/store/ProviderDb';
import { CARD_SPACING, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';

// 排序条目宽（= 屏宽 - 48：两侧 24vp 头部空间容纳浮起放大出头，防内容区裁切——头注释；
// 勿改回屏宽-32：头部空间缩水后放大切边复现）
const SORT_ITEM_WIDTH: string = 'calc(100% - 48vp)';

@Component
export struct ProviderSortPage {
  // 顶部/底部留白（PageMapBuilder 注入，offset 轨消费——ProviderPage 同款）
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 官方路由栈（PageMapBuilder 注入——返回时 pop 带 result 触发管理页 onPop，坑17）
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State private rows: ProviderRow[] = [];

  aboutToAppear(): void {
    this.reload();
  }

  // （2026-08-30 刷新链路收敛：原 aboutToDisappear 广播已删——管理页新序靠菜单「刷新」键）

  private reload(): void {
    queryProviders()
      .then((rows: ProviderRow[]): void => {
        this.rows = rows;
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '服务商列表读取失败：' + (e as Error).message });
      });
  }

  // 拖拽落定：数据源 splice（官方 onMove 语义）+ 全量回写 sortOrder（管理页原逻辑迁入）
  private applyDragMove(from: number, to: number): void {
    const next: ProviderRow[] = this.rows.slice();
    const moved: ProviderRow = next.splice(from, 1)[0];
    next.splice(to, 0, moved);
    this.rows = next;
    saveProviderOrder(next.map((row: ProviderRow): string => row.id))
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '排序保存失败：' + (e as Error).message });
      });
  }

  // 列表内容（坑39 红线：@BuilderParam content 位挂组件内 @Builder 方法）
  @Builder
  Content() {
    List({ space: CARD_SPACING }) {
      ForEach(this.rows, (row: ProviderRow) => {
        ListItem() {
          Row({ space: 10 }) {
            // 拖拽手柄（自绘两横线——ProviderCardItem 同款形制；拖拽由长按整卡触发）
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

            Text(row.name)
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
      }, (row: ProviderRow): string => row.id)
        // 官方拖拽排序（ForEach.onMove——管理页原逻辑迁入，语义见头注释）
        .onMove((from: number, to: number): void => {
          this.applyDragMove(from, to);
        })

      if (this.rows.length === 0) {
        ListItem() {
          Text('暂无服务商，先在管理页新建')
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
      title: '排序服务商',
      content: (): void => {
        this.Content()
      },
      // 坑17：拦截官方返回链 → pop 带 result 触发管理页 onPop 重拉新序（排序 onMove
      // 已实时落库，返回即需刷新；未拖拽直接返回同样触发 reload，代价 = 一次查询可忽略）
      onBackPressed: (): boolean => {
        this.pathStack.pop({ saved: true });
        return true;
      }
    })
  }
}
