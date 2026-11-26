// 记忆快照详情页（记忆历史页点行卡 push 的三级页）：只读列出那一版快照里的条目，供用户确认「这一版存的是什么」。
// · 不设恢复键（恢复入口唯一在历史页行卡右侧——多入口 = 误触与歧义）；本页纯展示。
// · 条目读取 = queryMemorySnapshotItems（存储层解析口径单源）；解析失败抛中文错误原样上屏。
// · 行卡形制抄 AssistantMemoryPage 只读条目行（内容单行省略 + 副行来源与更新时间；无键无 onClick）。
// · 长列表 = List + Repeat.virtualScroll（V1 壳保参数解析与读取，渲染拆同文件 @ComponentV2 件 + 构造处桥接，
//   规范 §4.6）；数据源整体替换恒刷新（纪元键已退役）；让位走 offset 轨；0 行分支壳侧 Scroll 兜底。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { UIUtils } from '@kit.ArkUI';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, SECTION_HEADER_GAP, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS
} from '../../common/Theme';
import { PageShell } from '../../common/PageShell';
import { SectionHeader } from '../SectionHeader';
import { formatConvTime } from '../chat/SessionSearchPanels';
import { ROUTE_MEMORY_SNAPSHOT_PAGE } from '../../common/RouteNames';
import { MemoryRow, queryMemorySnapshotItems } from '../../common/store/MemoryDb';
// 来源标注 → 副行文案（原内联二元式在导入条目上会显示「自动整理」= 假话——本页是「确认这一版存了什么」的页面，
// 快照 payload 原样携带 source，导入条目必须同走单源；memorySourceLabel 三处消费点自此同源）
import { memorySourceLabel } from '../../common/MemoryText';
import { MemorySnapshotParam } from './MemoryHistoryPage';

@Component
export struct MemorySnapshotPage {
  // 页面存活守卫：置位后本组件迟到异步回调不写状态、不碰 UI、不上行；写库意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 该份快照的条目（只读；查询/解析失败走 errorText 与空列表；整体替换即刷）
  @State private rows: MemoryRow[] = [];
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
        if (this.departed) {
          return;
        }
        this.rows = rows;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: (e as Error).message });
      });
  }

  // 板块头（只留标题——副标题行 2026-11-01 退役；壳侧 V1 内容，经头槽进 V2 首行 / 0 行分支直挂）
  @Builder
  SnapshotHead() {
    SectionHeader({
      title: '快照条目',
      hint: '这是存档当时该库的完整内容。恢复入口在记忆历史页对应的那一行上。'
    })
  }

  @Builder
  Content() {
    if (this.rows.length === 0) {
      // 0 行分支（壳侧 Scroll 兜底——Repeat 无行可挂；结构与间距沿用原 Scroll 形态）
      Scroll() {
        Column({ space: CARD_SPACING }) {
          Column({ space: SECTION_HEADER_GAP }) {
            this.SnapshotHead()
            Text('这一版没有条目。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
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
      .scrollBar(BarState.Off)
    } else {
      SnapshotRows({
        rows: UIUtils.enableV2Compatibility(this.rows),
        appColorMode: this.appColorMode,
        topPad: this.topPad,
        bottomPad: this.bottomPad,
        headSlot: (): void => {
          this.SnapshotHead()
        }
      })
        .width('100%')
        .height('100%')
    }
  }

  build() {
    PageShell({
      title: '快照详情',
      content: (): void => {
        this.Content();
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}

// 快照条目渲染域（同文件同域——壳引渲染件单向）：List + Repeat.virtualScroll（V2），数据源壳侧桥接；键只写
// 条目 id；头槽（@BuilderParam）= 壳侧板块头挂首行随内容滚；让位 = offset 轨；0 行由壳侧分支渲染（本件不兜底）
@ComponentV2
struct SnapshotRows {
  // 该份快照的条目（壳侧构造处桥接传入——Repeat 懒加载要求数据源具 V2 观察能力）
  @Param rows: MemoryRow[] = [];
  @Param appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @Param topPad: number = 0;
  @Param bottomPad: number = 0;
  // 首行头槽（板块头——壳侧 V1 Builder）
  @BuilderParam headSlot: () => void;

  // 只读条目行（内容 + 副行来源标注与更新时间；显示读当前 ri.item，禁构造期快照。卡体挂 CARD_PANEL_WIDTH
  // 而非 width('100%')：宿主无左右 padding，收窄责任在卡体，规范 §4.3）
  @Builder
  ReadonlyMemoryRow(ri: RepeatItem<MemoryRow>) {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(ri.item.content)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(memorySourceLabel(ri.item.source) + ' · ' + formatConvTime(ri.item.updatedAt))
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
    .borderRadius(CARD_RADIUS)
  }

  build() {
    List({ space: CARD_SPACING }) {
      Repeat<MemoryRow>(this.rows)
        .each((ri: RepeatItem<MemoryRow>) => {
          ListItem() {
            // 首行 = 板块头 + 首卡（标题与卡间隙 SECTION_HEADER_GAP）；保真层 Column 居中（ListItem 子项不水平
            // 居中致 CARD_PANEL_WIDTH 卡整列左偏——实锤）
            Column({ space: SECTION_HEADER_GAP }) {
              if (ri.index === 0) {
                this.headSlot()
              }
              this.ReadonlyMemoryRow(ri)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }
        })
        // 键 = 条目 id（身份唯一；交互态不塞键——本页纯展示无行级态）
        .key((row: MemoryRow): string => row.id)
        .virtualScroll()
    }
    .width('100%')
    .height('100%')
    // 让位 offset 轨（原 Scroll padding top/bottom 同值等价）
    .contentStartOffset(this.topPad)
    .contentEndOffset(this.bottomPad + 16)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
    // 单版快照条目 ≤ 库上限 200，5 为屏内缓冲（轻行卡；按页设值非全局口径）
    .cachedCount(5)
  }
}
