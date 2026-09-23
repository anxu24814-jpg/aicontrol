// 记忆快照详情页（2026-09-22 记忆优化历史，方案-记忆优化历史-20260922 §7.3）：记忆历史页
// 点行卡 push 的三级页——只读列出那一版快照里的条目，供用户确认「这一版存的是什么」。
// · **不设恢复键**（D9：恢复入口唯一在历史页的行卡右侧——多入口 = 误触与歧义）；本页纯展示。
// · 条目读取 = queryMemorySnapshotItems（存储层解析口径单源）；解析失败抛中文错误原样上屏。
// · 行卡形制抄 AssistantMemoryPage 的只读条目行（内容单行省略 + 副行来源与更新时间；无四点键
//   无 onClick，纯展示）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor
} from '../../common/Theme';
import { PageShell } from '../../common/PageShell';
import { SectionHeader } from '../SectionHeader';
import { formatConvTime } from '../chat/SessionSearchPanels';
import { ROUTE_MEMORY_SNAPSHOT_PAGE } from '../../common/RouteNames';
import { MemoryRow, queryMemorySnapshotItems } from '../../common/store/MemoryDb';
// 来源标注 → 副行文案（★ 2026-09-22 记忆导入笔自检轮补：原内联二元式在导入条目上会显示
// 「自动整理」= 假话——本页是「确认这一版存了什么」的页面，快照 payload 原样携带 source，
// 导入条目必须同走单源函数；memorySourceLabel 三处消费点（库管理页行卡 / 助手记忆页只读行卡
// / 本页只读行卡）自此同源）
import { memorySourceLabel } from '../../common/MemoryText';
import { MemorySnapshotParam } from './MemoryHistoryPage';

@Component
export struct MemorySnapshotPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 该份快照的条目（只读；查询/解析失败走 errorText 与空列表）
  @State private rows: MemoryRow[] = [];
  @State private listEpoch: number = 0;
  private snapshotId: string = '';
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  aboutToAppear(): void {
    const params: Array<Object | null> =
      (this.pathStack.getParamByName(ROUTE_MEMORY_SNAPSHOT_PAGE) ?? []) as Array<Object | null>;
    const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
    const parsed: MemorySnapshotParam | null =
      last !== null && typeof last !== 'string' ? last as MemorySnapshotParam : null;
    if (parsed === null || typeof parsed.snapshotId !== 'string' || parsed.snapshotId === '') {
      // 异常路径弹回（AssistantMemoryPage 缺参同款守卫——不静默留在空白页）
      this.getUIContext().getPromptAction().showToast({ message: '缺少快照参数' });
      this.pathStack.pop();
      return;
    }
    this.snapshotId = parsed.snapshotId;
    this.load();
  }

  private load(): void {
    queryMemorySnapshotItems(this.snapshotId)
      .then((rows: MemoryRow[]): void => {
        this.rows = rows;
        this.listEpoch = this.listEpoch + 1;
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: (e as Error).message });
      });
  }

  // 列表重建键（纪元——每次载入自增）
  private listKey(): string {
    return 'snapshot|' + this.snapshotId + '|' + this.listEpoch;
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        Column({ space: 6 }) {
          SectionHeader({
            title: '快照条目',
            subtitle: this.rows.length + ' 条',
            hint: '这是存档当时该库的完整内容。恢复入口在记忆历史页对应的那一行上。'
          })
          if (this.rows.length === 0) {
            Text('这一版没有条目。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
          } else {
            ForEach([this.listKey()], (_key: string) => {
              Column({ space: CARD_SPACING }) {
                ForEach(this.rows, (row: MemoryRow) => {
                  this.ReadonlyMemoryRow(row)
                }, (row: MemoryRow): string => row.id)
              }
              .width('100%')
            }, (key: string): string => key)
          }
        }
        .width('100%')
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

  // 只读条目行（内容 + 副行来源标注与更新时间——AssistantMemoryPage 只读行同形制；卡体挂
  // CARD_PANEL_WIDTH 而非 width('100%')：宿主滚动列无左右 padding，收窄责任在卡体，
  // 规范-列表卡片与组卡 §4.3）
  @Builder
  ReadonlyMemoryRow(row: MemoryRow) {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(row.content)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(memorySourceLabel(row.source) + ' · ' + formatConvTime(row.updatedAt))
          .fontSize(13)
          .fontColor(cardDescColor())
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width(CARD_PANEL_WIDTH)
    .alignItems(VerticalAlign.Center)
    .padding(14)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
  }

  build() {
    PageShell({
      title: '快照详情',
      content: (): void => {
        this.Content();
      }
    })
  }
}
