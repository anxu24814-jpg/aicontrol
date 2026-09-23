// 助手记忆页（2026-09-08 记忆域，任务书 §2.5——助手编辑页「记忆」分区卡转真页；
// ★ 2026-09-20 助手级记忆改造）：顶部「记忆作用域」分段卡（★ v35 两段「全局记忆/助手记忆」
// ——assistants.memoryScope 列即时落库，形制照 MemoryPage 读取方式分段卡同款：独立分段卡
// + 说明小字在操作行上方，SegmentBar 消费侧只传 items/selectedIndex）+ 注入/沉淀两开关行
// （GroupSettingCard 开关行形态）+ 「记忆条目」只读列表（当前选中作用域库的条目纯展示——
// 决明拍板「助手页仅可查看对应的记忆」，无四点键无点卡编辑，管理入口在设置 → 记忆页的
// 分库列表）。
// · 开关即时落库（updateAssistantMemoryFlags / updateAssistantMemoryScope）无保存动作 →
//   返回经 onBackPressed 拦截 pop({saved:true})（坑17「无保存动作的完成返回」标准姿势——
//   编辑页 onPop 重拉卡面摘要）；
// · 开关显示刷新 = 恒单例纪元键 ForEach（规范 §4.1「刷新责任在调用方」——键含两开关值，
//   变动即组卡重建拉新 Toggle；PreferencesPage.chatGroupKey 同款先例）；分段同理（键含
//   scope 值与库条目纪元）；
// · 取参：push param = 助手 id（AssistantEditPage「记忆」卡 push，恒编辑态——空参 push
//   = 异常路径弹回，AssistantEditPage 同款守卫）；
// · 说明文字收入板块头 ⓘ 气泡（2026-09-08 决明「提示卡全宽改气泡」口径——原独立全宽
//   说明卡删除，改走 SectionHeader.hint）。
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { PageShell } from '../../common/PageShell';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, SEGMENT_BAR_HEIGHT, cardBg, cardDescColor, cardTitleColor
} from '../../common/Theme';
import { GroupEntryItem, GroupSettingCard } from '../GroupSettingCard';
import { SectionHeader } from '../SectionHeader';
import { SegmentBar } from '../SegmentBar';
import { formatConvTime } from '../chat/SessionSearchPanels';
import { AssistantRow, queryAssistant, updateAssistantMemoryFlags,
  updateAssistantMemoryScope } from '../../common/store/AssistantDb';
import {
  ASSISTANT_MEMORY_LIST_TICK_KEY, MEMORY_LIST_TICK_KEY, MEMORY_SCOPE_ASSISTANT,
  MEMORY_SCOPE_GLOBAL, MemoryRow, queryAssistantMemories, queryMemories
} from '../../common/store/MemoryDb';
// 来源标注 → 副行文案（三态单源；★ 2026-09-22 记忆导入笔：原内联二元式改为纯函数调用——
// 与库管理页行卡同源，两处若各写各的，导入条目在漏改的那处会被标成「自动整理」）
import { memorySourceLabel } from '../../common/MemoryText';
import { ROUTE_ASSISTANT_MEMORY_PAGE } from '../../common/RouteNames';

@Component
export struct AssistantMemoryPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 两开关态（aboutToAppear 库读初值；Toggle 上行即写库 + 写 @State 驱动键变重建）
  @State private memoryInject: boolean = true;
  @State private memorySink: boolean = true;
  // 记忆作用域（v35；'global' 默认 = 全局记忆 / 'assistant' = 助手记忆——分段下标 0 = 全局
  // / 1 = 助手，双向映射守卫与读取方式分段同款）
  @State private memoryScope: string = MEMORY_SCOPE_GLOBAL;
  @State @Watch('onScopeIndexChanged') scopeIndex: number = 0;
  // 分段选项（顺序契约：下标 0 = 全局记忆（默认项在前，与读取方式分段同构）/ 1 = 助手记忆）
  private scopeItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '全局记忆' },
    { text: '助手记忆' }
  ]);
  // 只读列表（当前选中作用域库的条目——排序三键由各 query 保证）
  @State private memories: MemoryRow[] = [];
  @State private listEpoch: number = 0;
  private rowId: string = '';
  // 两库广播读点（任一库写操作后只读列表随刷——本页两段都展示库内容，不判库直接重拉幂等）
  @StorageProp(MEMORY_LIST_TICK_KEY) @Watch('onLibraryTick') globalTick: number = 0;
  @StorageProp(ASSISTANT_MEMORY_LIST_TICK_KEY) @Watch('onLibraryTick') assistantTick: number = 0;
  @StorageProp('appColorMode') appColorMode: number = 0;

  aboutToAppear(): void {
    const params: Array<string> =
      this.pathStack.getParamByName(ROUTE_ASSISTANT_MEMORY_PAGE) as Array<string>;
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
        this.memoryInject = row.memoryInject;
        this.memorySink = row.memorySink;
        this.memoryScope = row.memoryScope !== '' ? row.memoryScope : MEMORY_SCOPE_GLOBAL;
        this.scopeIndex = this.memoryScope === MEMORY_SCOPE_ASSISTANT ? 1 : 0;
        this.reloadLibrary();
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '记忆开关读取失败：' + (e as Error).message });
        this.pathStack.pop();
      });
  }

  // 开关落库（即时生效；失败 toast 不静默 + 回滚——P0-1）。★ 回滚 = 库读回灌（单一真源）：
  // 原「取反回滚」在连点两开关时首笔失败会把第二笔的态一并推翻（写失败 + 快速连点才触发，
  // 2026-09-08 自检轮修）
  private persistFlags(inject: boolean, sink: boolean): void {
    updateAssistantMemoryFlags(this.rowId, inject, sink)
      .catch((e: Object): void => {
        this.reloadFlags();
        this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
      });
  }

  // 作用域落库（v35：分段切换即时写 assistants.memoryScope；失败库读回灌同款口径——
  // 两种段的守卫链在发送/沉淀/工具侧各闸消费，本页只管配置）
  private persistScope(scope: string): void {
    updateAssistantMemoryScope(this.rowId, scope)
      .catch((e: Object): void => {
        this.reloadScope();
        this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
      });
  }

  // 失败回滚：库读回灌两开关与作用域（读失败保持现状——toast 已由调用方给出，不重复打扰）
  private reloadFlags(): void {
    queryAssistant(this.rowId)
      .then((row: AssistantRow | null): void => {
        if (row !== null) {
          this.memoryInject = row.memoryInject;
          this.memorySink = row.memorySink;
          this.memoryScope = row.memoryScope !== '' ? row.memoryScope : MEMORY_SCOPE_GLOBAL;
          this.scopeIndex = this.memoryScope === MEMORY_SCOPE_ASSISTANT ? 1 : 0;
        }
      })
      .catch((): void => {
      });
  }

  // 回滚复用（persistScope 失败路径——与 reloadFlags 同一读取，别名收口防两处漂移）
  private reloadScope(): void {
    this.reloadFlags();
  }

  // 分段下标 → 写作用域（下标 0 = global / 1 = assistant；互设守卫同值不递归）
  private onScopeIndexChanged(): void {
    const scope: string =
      this.scopeIndex === 1 ? MEMORY_SCOPE_ASSISTANT : MEMORY_SCOPE_GLOBAL;
    if (scope !== this.memoryScope) {
      this.memoryScope = scope;
      this.persistScope(scope);
      this.reloadLibrary();
    }
  }

  // 当前选中库条目读取（只读列表数据源——'global' = 全局库 / 'assistant' = 该助手库）
  private reloadLibrary(): void {
    const read: Promise<MemoryRow[]> = this.memoryScope === MEMORY_SCOPE_ASSISTANT ?
      queryAssistantMemories(this.rowId) : queryMemories();
    read
      .then((rows: MemoryRow[]): void => {
        this.memories = rows;
        this.listEpoch = this.listEpoch + 1;
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '记忆读取失败：' + (e as Error).message });
      });
  }

  private onLibraryTick(): void {
    this.reloadLibrary();
  }

  // 两开关行数据（GroupSettingCard 开关行：toggleValue/onToggle 两字段齐全，行尾官方
  // Toggle 唯一控制面；secondary = 行内说明小字）。★ 2026-09-13 记忆按需读取：「注入记忆」
  // 行名不改（记忆域词汇表全局统一用「注入」，单改一处制造跨页不一致——方案 §2.7 自检
  // 核正），开关语义随读取方式扩形 = 参与记忆读取（注入或检索），仅副标题按双形态改写
  private switchGroup(): GroupEntryItem[] {
    return [
      {
        icon: $r('sys.symbol.arrow_down_circle'),
        label: '注入记忆',
        secondary: '该助手的会话按读取方式携带长期记忆',
        toggleValue: (): boolean => this.memoryInject,
        onToggle: (isOn: boolean): void => {
          this.memoryInject = isOn;
          this.persistFlags(isOn, this.memorySink);
        }
      },
      {
        icon: $r('sys.symbol.memory_module'),
        label: '沉淀记忆',
        secondary: '该助手的会话退出时自动整理沉淀',
        toggleValue: (): boolean => this.memorySink,
        onToggle: (isOn: boolean): void => {
          this.memorySink = isOn;
          this.persistFlags(this.memoryInject, isOn);
        }
      }
    ];
  }

  // 组卡重建键（恒单例纪元键——键含两开关值，变动即重建拉新 Toggle，§4.1 刷新责任）
  private switchGroupKey(): string {
    return String(this.memoryInject) + '|' + String(this.memorySink);
  }

  // 只读列表重建键（纪元 + 作用域——段切换必重建）
  private listKey(): string {
    return 'assistMem|' + this.memoryScope + '|' + this.listEpoch;
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        // ── 记忆作用域分段卡（v35；★ 说明小字在操作行上方——宪法「功能设置卡布局次序」
        //    条；独立分段卡形制与 MemoryPage 读取方式卡同款）──
        Column({ space: 6 }) {
          SectionHeader({
            title: '记忆开关',
            subtitle: '记忆对这名助手的生效范围',
            hint: '选择助手记忆后注入与沉淀都只使用该助手自己的记忆库。选择全局记忆则使用所有助手共用的全局记忆库。记忆整理使用功能模型页「记忆提取」卡选的模型，未选择时无法整理。隐私会话不注入也不沉淀。加密会话只注入不沉淀。全局开关与条目管理在设置 → 记忆页。'
          })
          Column({ space: 10 }) {
            Column({ space: 2 }) {
              Text('记忆作用域')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
              Text('助手记忆只有本助手使用，全局记忆所有助手共用。')
                .fontSize(13)
                .fontColor(cardDescColor())
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            Column() {
              SegmentBar({
                items: this.scopeItems,
                selectedIndex: $scopeIndex
              })
            }
            .width('100%')
            .height(SEGMENT_BAR_HEIGHT)
          }
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(16)
          .width(CARD_PANEL_WIDTH)
          ForEach([this.switchGroupKey()], (_key: string) => {
            GroupSettingCard({ items: this.switchGroup() })
          }, (key: string): string => key)
        }
        .width('100%')

        // ── 记忆条目（只读——无四点键无点卡编辑，管理入口在设置 → 记忆页分库列表）──
        Column({ space: 6 }) {
          SectionHeader({
            title: '记忆条目',
            subtitle: this.memories.length + ' 条',
            hint: '此处只读。条目的新增、编辑、删除与整理在设置 → 记忆页对应的库里。'
          })
          if (this.memories.length === 0) {
            Text(this.memoryScope === MEMORY_SCOPE_ASSISTANT ?
              '暂无助手记忆。' : '暂无全局记忆。')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
          } else {
            ForEach([this.listKey()], (_key: string) => {
              Column({ space: CARD_SPACING }) {
                ForEach(this.memories, (row: MemoryRow) => {
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

  // 只读条目行（内容 + 副行来源标注与更新时间——与库管理页行卡同形制但无四点键、
  // 无 onClick，纯展示）。★ 卡宽 2026-09-20 决明报障核正：卡体挂 CARD_PANEL_WIDTH
  // 而非 width('100%')——宿主滚动列无左右 16vp padding，收窄责任在卡体（规范-列表卡片与组卡
  // §4.3 增补十一/十二判据；库管理页行卡同款写法）
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
      title: '记忆',
      onBackPressed: (): boolean => {
        // 完成返回带 result（坑17——编辑页 onPop 重拉「注入开 · 沉淀开」摘要）
        this.pathStack.pop({ saved: true });
        return true;
      },
      content: (): void => {
        this.Content();
      }
    })
  }
}
