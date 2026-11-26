// 助手记忆页：助手编辑页「记忆」分区卡 push，param = 助手 id（空参 push = 异常路径弹回）。
// 页面 = 页首 info 蓝卡（说明单源 MEMORY_CONTROLS_INFO）+「记忆开关」组卡 +「记忆条目」
// 只读列表（决明拍板「助手页仅可查看对应的记忆」——无四点键无点卡编辑，管理入口在
// 设置 → 记忆页的分库列表）。
// ★ 组卡形制（决明拍板「前两卡形态相近合并为组卡」+「分段胶囊放组卡内、不上下」）：组卡 =
//   卡头行（左「记忆作用域」标题 + 右定宽分段胶囊——官方组件宽度 = 父容器宽，外层包
//   SEGMENT_BAR_ROW_WIDTH 定宽容器约束；胶囊容器定高与背板等高，原定高与上下内距叠加会
//   顶穿卡边 = 样式报障根因）+ 注入/沉淀两开关行（SettingSwitchRow）；分割线 = 卡头行下
//   一条 + 行间一条。info 蓝卡置板块头标题上面 = 页面首元素（决明「info 放到首卡」）。
// · 开关即时落库（updateAssistantMemoryFlags / updateAssistantMemoryScope）无保存动作 →
//   返回经 onBackPressed 拦截 pop({saved:true})（坑17「无保存动作的完成返回」标准姿势
//   ——编辑页 onPop 重拉卡面摘要）。
// · 开关显示刷新 = 恒单例纪元键 ForEach（规范 §4.1「刷新责任在调用方」——键含两开关值，
//   变动即组卡重建拉新 Toggle）；分段同理（键含 scope 值与库条目纪元）。
// ★ 长列表 = List + Repeat.virtualScroll（V1 壳保全部业务与控制区状态，条目渲染拆同文件
//   @ComponentV2 渲染件 + 构造处桥接，规范 §4.6）。控制区（SectionHeader @Prop /
//   SegmentBar $ 双向 / GroupSettingCard items 普通成员纪元键重建）是 V1 机制簇——@Link
//   官方禁 V2 初始化、@Prop/普通成员跨边界刷新无保证，故全部留壳侧 @Builder、经
//   @BuilderParam 头槽进 V2 首行随内容滚动；条目列表纪元键（listKey/listEpoch）退役
//  （Repeat 数据源整体替换恒刷新）；让位沿用原 Scroll padding 的等价 offset 轨；0 行分支
//   壳侧 Scroll 兜底。
import { SegmentButtonV2Items, UIUtils } from '@kit.ArkUI';
import { PageShell } from '../../common/PageShell';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, SEGMENT_BAR_HEIGHT, SEGMENT_BAR_ROW_WIDTH,
  SECTION_GAP, SECTION_HEADER_GAP, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS
} from '../../common/Theme';
import { SectionHeader } from '../SectionHeader';
import { InfoCard } from '../InfoCard';
import { SettingSwitchRow } from '../settings/FunctionalSettingRows';
import { SegmentBar } from '../SegmentBar';
import { formatConvTime } from '../chat/SessionSearchPanels';
import { AssistantRow, queryAssistant, updateAssistantMemoryFlags,
  updateAssistantMemoryScope } from '../../common/store/AssistantDb';
import {
  ASSISTANT_MEMORY_LIST_TICK_KEY, MEMORY_LIST_TICK_KEY, MEMORY_SCOPE_ASSISTANT,
  MEMORY_SCOPE_GLOBAL, MemoryRow, queryAssistantMemories, queryMemories
} from '../../common/store/MemoryDb';
// 来源标注 → 副行文案（三态单源——与库管理页行卡同源，两处各写会漂移：导入条目在漏改处
// 会被标成「自动整理」）
import { memorySourceLabel } from '../../common/MemoryText';
import { ROUTE_ASSISTANT_MEMORY_PAGE } from '../../common/RouteNames';

// 记忆开关板块 info 蓝卡正文（说明单点；面向用户文案规约：句号分句、无冒号分号括号连环）
const MEMORY_CONTROLS_INFO: string = '助手记忆仅用于本助手，全局记忆所有助手共用。' +
  '整理用功能模型页「记忆提取」卡的模型，未选择时无法整理。' +
  '隐私会话不注入不沉淀。' +
  '条目只读，新增、编辑、删除与整理在设置 → 记忆页。';

@Component
export struct AssistantMemoryPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI；写库等数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 两开关态（aboutToAppear 库读初值；Toggle 上行即写库 + 写 @State 驱动键变重建）
  @State private memoryInject: boolean = true;
  @State private memorySink: boolean = true;
  // 记忆作用域（'global' 默认 = 全局记忆 / 'assistant' = 助手记忆——分段下标 0 = 全局 /
  // 1 = 助手，双向映射守卫与读取方式分段同款）
  @State private memoryScope: string = MEMORY_SCOPE_GLOBAL;
  @State @Watch('onScopeIndexChanged') scopeIndex: number = 0;
  // 分段选项（顺序契约：下标 0 = 全局记忆（默认项在前，与读取方式分段同构）/ 1 = 助手记忆）
  private scopeItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '全局记忆' },
    { text: '助手记忆' }
  ]);
  // 只读列表（当前选中作用域库的条目——排序由各 query 保证；Repeat 整体替换即刷）
  @State private memories: MemoryRow[] = [];
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
        if (this.departed) {
          return;
        }
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
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '记忆开关读取失败：' + (e as Error).message });
        this.pathStack.pop();
      });
  }

  // 开关落库（即时生效；失败 toast 不静默 + 回滚——P0-1）。★ 回滚 = 库读回灌（单一真源）：
  //「取反回滚」在连点两开关时首笔失败会把第二笔的态一并推翻（写失败 + 快速连点才触发）
  private persistFlags(inject: boolean, sink: boolean): void {
    updateAssistantMemoryFlags(this.rowId, inject, sink)
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.reloadFlags();
        this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
      });
  }

  // 作用域落库（分段切换即时写 assistants.memoryScope；失败库读回灌同款口径——守卫链在
  // 发送/沉淀/工具侧各闸消费，本页只管配置）
  private persistScope(scope: string): void {
    updateAssistantMemoryScope(this.rowId, scope)
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.reloadScope();
        this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
      });
  }

  // 失败回滚：库读回灌两开关与作用域（读失败保持现状——toast 已由调用方给出，不重复打扰）
  private reloadFlags(): void {
    queryAssistant(this.rowId)
      .then((row: AssistantRow | null): void => {
        if (this.departed) {
          return;
        }
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
        if (this.departed) {
          return;
        }
        this.memories = rows;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '记忆读取失败：' + (e as Error).message });
      });
  }

  private onLibraryTick(): void {
    this.reloadLibrary();
  }

  // 组卡重建键（恒单例纪元键——键含两开关值，变动即重建拉新 Toggle，§4.1 刷新责任）
  private switchGroupKey(): string {
    return String(this.memoryInject) + '|' + String(this.memorySink);
  }

  // ── 控制区（info 蓝卡 + 板块头 + 开关组卡〔卡头行含分段胶囊〕）──迁 Repeat 后抽为独立
  //    @Builder：非空分支经头槽进 V2 首行、空分支直挂，单一来源两处复用；SegmentBar $
  //    绑定与组卡纪元键全在此壳侧 V1 上下文，机制原样零改 ──
  @Builder
  ControlsSection() {
    Column({ space: SECTION_HEADER_GAP }) {
      // info 蓝卡：页首独立蓝卡、板块头之上——InfoCard 缺省挂 CARD_PANEL_WIDTH（宿主无
      // 水平 padding，规范 §4.3 收窄责任在卡体）
      InfoCard({ text: MEMORY_CONTROLS_INFO })
      SectionHeader({ title: '记忆开关' })
      ForEach([this.switchGroupKey()], (_key: string) => {
        Column() {
          // 卡头行：左「记忆作用域」标题 + 右置分段胶囊（官方组件宽度 = 父容器宽，外层定宽
          // 容器取 SEGMENT_BAR_ROW_WIDTH；左右 12 = 行内容左缘〔行缩进 4 + 行内 8〕，与行
          // 标题同一竖线、与行尾 Toggle 同右缘）
          Row() {
            Text('记忆作用域')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Column() {
              SegmentBar({
                items: this.scopeItems,
                selectedIndex: $scopeIndex
              })
            }
            .width(SEGMENT_BAR_ROW_WIDTH)
            .height(SEGMENT_BAR_HEIGHT)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .alignItems(VerticalAlign.Center)
          // 无障碍标签（标题可见后仍留读屏名——语义名与可见名同值，读屏不重复播报）
          .accessibilityText('记忆作用域')
          // 「注入记忆」行名不改（记忆域词汇表统一用「注入」），开关语义随读取方式扩形 =
          // 参与记忆读取（注入或检索）。分割线：卡头行下一条归首行 dividerTop，行间一条归末行
          SettingSwitchRow({
            label: '注入记忆',
            subtitle: '该助手的会话按读取方式携带长期记忆',
            isOn: this.memoryInject,
            dividerTop: true,
            onToggle: (isOn: boolean): void => {
              this.memoryInject = isOn;
              this.persistFlags(isOn, this.memorySink);
            }
          })
          SettingSwitchRow({
            label: '沉淀记忆',
            subtitle: '该助手的会话退出时自动整理沉淀',
            isOn: this.memorySink,
            dividerTop: true,
            onToggle: (isOn: boolean): void => {
              this.memorySink = isOn;
              this.persistFlags(this.memoryInject, isOn);
            }
          })
        }
        .width(CARD_PANEL_WIDTH)
        .padding({ top: 4, bottom: 4 })
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(CARD_RADIUS)
        .alignItems(HorizontalAlign.Start)
      }, (key: string): string => key)
    }
    .width('100%')
  }

  // 条目板块头（只留标题——副标题行 2026-11-01 退役）
  @Builder
  EntriesHead() {
    SectionHeader({ title: '记忆条目' })
  }

  // 非空分支头槽（控制区 + 条目板块头——两板块间隙 SECTION_GAP；头槽内末段到首卡
  // SECTION_HEADER_GAP 间隙由渲染域首行 Column 承担，见 AssistantMemoryRows）
  @Builder
  RowsHead() {
    Column({ space: SECTION_GAP }) {
      this.ControlsSection()
      this.EntriesHead()
    }
    .width('100%')
  }

  @Builder
  Content() {
    if (this.memories.length === 0) {
      // 0 行分支（壳侧 Scroll 兜底——Repeat 无行可挂；结构与间距沿用原 Scroll 形态，
      // 两板块 Builder 单一来源复用，控制区交互在空列表下同样可用）
      Scroll() {
        Column({ space: SECTION_GAP }) {
          this.ControlsSection()
          Column({ space: SECTION_HEADER_GAP }) {
            this.EntriesHead()
            Text(this.memoryScope === MEMORY_SCOPE_ASSISTANT ?
              '暂无助手记忆。' : '暂无全局记忆。')
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
      AssistantMemoryRows({
        memories: UIUtils.enableV2Compatibility(this.memories),
        appColorMode: this.appColorMode,
        topPad: this.topPad,
        bottomPad: this.bottomPad,
        headSlot: (): void => {
          this.RowsHead()
        }
      })
        .width('100%')
        .height('100%')
    }
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

  aboutToDisappear(): void {
    this.departed = true;
  }
}

// ═══ 记忆条目渲染域（迁 Repeat 拆出，同文件同域——壳引渲染件单向）═══
// 机制 = List + Repeat.virtualScroll（V2）：数据源壳侧构造处桥接；键只写条目 id；头槽
//（@BuilderParam）= 壳侧控制区 + 条目板块头挂首行随内容滚（V1 机制簇留壳，见壳侧头注释）；
// 让位 = offset 轨（原 Scroll padding 同值）；0 行由壳侧分支渲染（本件不兜底）。
@ComponentV2
struct AssistantMemoryRows {
  // 当前作用域库条目（壳侧构造处桥接传入——Repeat 懒加载要求数据源具 V2 观察能力；
  // 作用域切换 = 壳侧 reloadLibrary 整体替换 → 此处恒刷新）
  @Param memories: MemoryRow[] = [];
  // 颜色模式（默认 0 对齐本页 @StorageProp 既有约定——EntryAbility 首帧前写入真值）
  @Param appColorMode: number = 0;
  @Param topPad: number = 0;
  @Param bottomPad: number = 0;
  // 首行头槽（控制区 + 条目板块头——壳侧 V1 Builder）
  @BuilderParam headSlot: () => void;

  // 只读条目行（与库管理页行卡同形制但无四点键、无 onClick，纯展示）。★ 卡宽挂
  // CARD_PANEL_WIDTH 而非 width('100%')——宿主无左右 16vp padding，收窄责任在卡体
  //（规范-列表卡片与组卡 §4.3 判据）；显示读当前 ri.item，禁构造期快照
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
      Repeat<MemoryRow>(this.memories)
        .each((ri: RepeatItem<MemoryRow>) => {
          ListItem() {
            // 首行 = 头槽 + 首卡（板块头与首卡间隙 SECTION_HEADER_GAP）；保真层 Column 居中
            //（实锤：ListItem 子项不水平居中致 CARD_PANEL_WIDTH 卡整列左偏）
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
    // 单库条目上限 200，5 为屏内缓冲（轻行卡；按页设值非全局口径）
    .cachedCount(5)
  }
}
