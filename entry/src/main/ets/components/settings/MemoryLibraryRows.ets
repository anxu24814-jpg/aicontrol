// 记忆库条目渲染域：职责 =「记忆库条目列表渲染——List 容器 + 记忆行卡 + 头槽 + 原位拖拽接线」。
// 与业务壳 MemoryLibraryPage.ets 分家（壳 = 数据读取 / 搜索过滤 / 窗口判定 / 弹窗 / 半模态 /
// 编辑导航；本件 = 纯渲染 + 事件上抛）；依赖方向单向（壳引本件），无模块环（坑50）。
// ★ 容器 = LazyForEach（V1）+ 静态首项头槽，不用 Repeat：Repeat 限制「滚动容器内只能含一个
//   Repeat，不建议混排 ListItem/ForEach/LazyForEach」⇒ 头槽只能塞进首条，长按首条会连头槽
//   一起拖。头槽改静态 ListItem 后不在数据源内 ⇒ 天然排除在拖拽索引域外，原位拖拽可行
//  （与服务商管理页 / 助手页同形态）。0 行态并回同一个 List（条件尾项）——头槽恒在场，搜索框
//   不再有被换掉的自锁风险。让位走 offset 轨（contentStartOffset / contentEndOffset）。
//   ★ 数据面 = MemoryRowsSource（壳侧单写口 reset / refresh；与壳侧数组由构造保证同序）。
//   ★ 拖拽卡四件套（规范《列表卡片与组卡》§4.8）缺第一件是有据的：容器零水平 padding、卡宽
//   CARD_PANEL_WIDTH 自承收窄 ⇒ 视口边界 = 屏缘，不存在「水平 padding 即视口缩进」的裁切
//   根因，不挂 .clip(false)（空操作）。其余三件照挂：条目层同值圆角 / 卡壳 stateEffect(false)
//   / 落定重建数据源顺序。
// ★★ 行级态刷新（本件最关键机制，勿凭直觉改回纯 @Prop 传导）：LazyForEach 子项刷新是键驱动
//   的——官方 d.ts：键不变的项复用原组件，键变的项新建。故两条配套机制：
//   ① 键含全部可变展示成分（memoryRowKey：身份 id + 内容版本位 row.updatedAt + 窗口位 +
//      多选勾选位）。漏版本位 ⇒ 编辑 / 优化记忆后 reload 重拉但键不变，卡面停在旧内容（官方
//      FAQ 605；坑44 同族真机实锤）。版本位取 updatedAt = MemoryDb 各内容写点恒将 content 与
//      updatedAt 同写，等价内容版本号；**新增内容写点须同守此约**（改内容不刷 updatedAt =
//      本键失明）。
//   ② 数据源重载通知口 MemoryRowsSource.refresh()：不动数据、只重派 onDataReloaded，由
//      @Prop @Watch 在壳侧选中集 / 多选态 / 窗口集更新后触发（@Watch 回调读到新值）。
//   · 多选态让位原位拖拽：onMove 参数为 Optional<OnMoveHandler>，多选态传 undefined 关闭长按
//   拖拽（点行语义已换成勾选）；壳侧 applyDragMove 另有第二道守卫。
// · 行卡事件（点卡编辑或切勾选）透传壳侧。四点键菜单整链已退役（编辑 = 点卡、删除 = 左滑、
//   移到窗口内 = 长按拖拽近似）。
// ★★ 四库左滑笔：行卡包 RowSwipeDelete（基准 = 会话页 SessionSwipeItem）：
//   · 展开态不进键（横滑位移是行内交互态），键变重建时横滑层随建随复位 = 天然归位；
//   · enabled = !multiSelect（构建期求值即可：多选进出经键重算全量换装）；
//   · 互斥经 group（壳侧单源下发 SwipeGroup——行内 @Param 传播在键驱动混合列表下不可行）；
//     列表滚动开始经组收起展开行；
//   · 与 onMove 长按拖拽共存：快横滑 = PanGesture（≥8vp）、长按拖 = 500ms，按类型天然互斥；
//     共存观感待真机（BLOCKED 真机清单）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS
} from '../../common/Theme';
import { MemoryRow } from '../../common/store/MemoryDb';
import { memorySourceLabel } from '../../common/MemoryText';
import { formatConvTime } from '../chat/SessionSearchPanels';
// 行级左滑删除横滑层（交互基准 = 会话页 SessionSwipeItem）
import { RowSwipeDelete, SwipeGroup } from '../RowSwipeDelete';

// ★★ 混合列表（静态头槽 + LazyForEach）的 onMove 落位坑（真机取证）：
//   · 上报值：from/to 是数据源下标（官方口径，本页无偏移）。
//   · 坑在框架自己的落位渲染：本形态下框架把「第 i 条移位」画成「第 i+1 条移位」（画面与
//   数据错开一条），且不看 App 的数据更新——实测守卫全拒、数据零变更的那一发画面照样错位
//   ⇒「松手后被拖的那条回原位、旁边一条动了」。
//   · 本件对策：不做任何下标换算（错的不是数据是渲染），落定由壳侧重建数据源顺序
//   （MemoryRowsSource.reset → onDataReloaded，索引直读、画面必按数据重排）；官方
//   「onDataMove = 只改顺序才保落位动画」那条通道在本形态下不可信，勿改回。
//   · 另两处原位拖拽页（服务商 / 助手）是纯循环列表（无静态项），落位通道正常，不走本对策。

// LazyForEach 数据源（契约同 ChatDataSource / AttachmentManagePage.ManageDataSource）：本件
// 渲染 = 壳侧「可见行」序（搜索态下是过滤后的子集），故本源与壳侧 visibleRows 恒同序。
// 唯一数据写口 = reset（重拉 / 过滤 / 拖拽落定三处）：整表替换 + 派发 onDataReloaded。
// ★ 不实现 move/onDataMove 落位通道——理由见上方「onMove 落位坑」段；落定一律按新序整表重建。
export class MemoryRowsSource implements IDataSource {
  private rows: MemoryRow[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): MemoryRow {
    return this.rows[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos: number = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }

  // 整表替换（入参另存副本：壳侧数组与本源不得互相经过引用被对方改写）
  reset(rows: MemoryRow[]): void {
    this.rows = rows.slice();
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }

  // 重载通知口（不动数据，只重派 onDataReloaded）：行级态（多选勾选 / 进出多选模式）变更后由
  // 渲染件 @Watch 触发，让 LazyForEach 按键重算复用/新建（见文件头「行级态刷新」段）。
  // ★ 与 reset 分工勿混：reset = 数据换；refresh = 数据不换、只重算键与重渲染
  refresh(): void {
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }
}

@Component
export struct MemoryLibraryRows {
  // 列表数据源（壳侧单写口维护；★ 普通成员——LazyForEach 自订阅数据源通知，不经组件参数观察）
  source: MemoryRowsSource = new MemoryRowsSource();
  // 注入窗口内的条目 id（壳侧按全量卡序算好传入——判定纯函数在 MemoryText.computeMemoryWindow）。
  // 并入行级键（「窗口外」后缀是卡面可变展示态）——窗口重算赋新数组即经 @Watch 触发键重算
  @Prop @Watch('onRowStateChanged') windowIds: string[] = [];
  // 多选模式与选中集（V1 @Prop——行级态刷新靠键 + 数据源重载通知，见文件头「行级态刷新」段）
  @Prop @Watch('onRowStateChanged') multiSelect: boolean = false;
  @Prop @Watch('onRowStateChanged') selectedIds: string[] = [];
  // 0 行提示文案（'' = 有行不出；文案单源在壳侧 emptyHintText）
  @Prop emptyText: string = '';
  @Prop appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 头槽（状态行区 + 条目板块头〔+ 回退路径的搜索框〕——壳侧 V1 Builder；恒为列表首项，随内容滚）
  @BuilderParam headSlot: () => void;
  // 左滑互斥组（壳侧单源下发；普通成员照 source 先例——V1 @Param 不承载类引用的互斥登记语义）
  group: SwipeGroup = new SwipeGroup();
  // 事件三枚（透传壳侧回调——点卡编辑 / 拖拽落定 / 勾选切换）
  onOpen: (row: MemoryRow) => void = () => {
  };
  onMove: (from: number, to: number) => void = () => {
  };
  onToggle: (id: string) => void = () => {
  };
  // 左滑删除（删除键与长距直达共用——事件上行行对象，壳侧走既有确认链）
  onSwipeDelete: (row: MemoryRow) => void = () => {
  };

  // 行级态变更 → 数据源重载通知（键重算 ⇒ 勾选圈回显 / 窗口外后缀随位；机制见文件头——
  // LazyForEach 子项刷新键驱动，只改 @Prop 值不会重跑行渲染）。三参同挂
  private onRowStateChanged(): void {
    this.source.refresh();
  }

  // LazyForEach 键（必须含全部可变展示成分，坑44 两问落实）：身份 + 内容版本位 + 窗口位
  //（+ 多选勾选位）。键变者新建取新值上屏；键不变者复用 ⇒ 常态浏览零重建（勿漏成分——漏项
  // 即静默冻结）。位序不并：LazyForEach 按键映射位置，拖拽重排由框架搬移
  private memoryRowKey(row: MemoryRow): string {
    // 窗口位：窗口重算（拖拽 / 移到窗口内 / 重拉）赋新数组即经 @Watch 重算
    const win: string = this.windowIds.includes(row.id) ? '1' : '0';
    if (!this.multiSelect) {
      return row.id + '|' + row.updatedAt + '|' + win;
    }
    return row.id + '|' + row.updatedAt + '|' + win + '|' +
      (this.selectedIds.indexOf(row.id) >= 0 ? '1' : '0');
  }

  // 原位拖拽回调（多选态不挂——传 undefined 关闭长按拖拽，见 build 内注释）
  private dragMoveHandler(): ((from: number, to: number) => void) | undefined {
    if (this.multiSelect) {
      return undefined;
    }
    return (from: number, to: number): void => {
      this.onMove(from, to);
    };
  }

  // 单条记忆卡（形制对齐会话提示词库页 TemplateRow：点卡编辑；显示读当前行参）
  // ★ 卡壳 Button 挂 stateEffect(false)（规范 §4.8 第三件——长按浮起后卡上带被按中的灰色蒙层
  // 的根治）。多选态勾选圈贴右缘（Checkbox 纯视觉 hitTestBehavior(None) + 卡片 onClick 单一
  // 通路，坑5）；常态右缘四点键已退役，留空
  @Builder
  MemoryRowCard(row: MemoryRow) {
    Button() {
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text(row.content)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            // 单行截断（行卡不必展示记忆完整内容，行数上限恒定卡高才恒定）
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          // 副行 = 来源 · 时间 +（窗口外标记——窗口内不缀任何字样，只有窗口外才加，与板块头
          // 副标题的条数互相印证）
          Text(memorySourceLabel(row.source) + ' · ' +
            formatConvTime(row.updatedAt) +
            (this.windowIds.includes(row.id) ? '' : ' · 窗口外'))
            .fontSize(13)
            .fontColor(cardDescColor())
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        if (this.multiSelect) {
          // 勾选圈（多选态）：官方 Checkbox 纯视觉指示器——勾选态刷新靠壳侧 selectedIds 经键
          // 并入 + 数据源重载
          Checkbox()
            .select(this.selectedIds.indexOf(row.id) >= 0)
            .hitTestBehavior(HitTestMode.None)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .type(ButtonType.Normal)
    // ★ 卡宽 = 条目宽 100%（窄宽由条目层 CARD_PANEL_WIDTH 承担——本页列表零水平 padding）。
    // ★ 禁在此再写 CARD_PANEL_WIDTH：会按父（条目）二次收窄成屏宽-64
    .width('100%')
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(14)
    // 关原生按压蒙层（规范 §4.8 第三件；代价 = 点卡进编辑页不再有按压变淡反馈，反馈由转场承担）
    .stateEffect(false)
    .onClick((): void => {
      // 多选态：点卡通勾选（编辑入口让位——切换语义并入行点击，同另两页多选先例）
      if (this.multiSelect) {
        this.onToggle(row.id);
        return;
      }
      this.onOpen(row);
    })
  }

  build() {
    List({ space: CARD_SPACING }) {
      // 头槽（静态首项——不在数据源内 ⇒ 不进拖拽索引域，长按不浮起不拖动；★ 恒在场：0 命中时
      // 头槽（含搜索框与已输入关键词）随之常在，自锁面不存在）
      ListItem() {
        this.headSlot()
      }
      // 条目（键见 memoryRowKey；行级事件读当前行参；原位拖拽 = 官方 onMove）。行卡包横滑层：
      // 展开态不进键，多选进出经键重算全量换装、enabled 构建期求值即可
      LazyForEach(this.source, (row: MemoryRow) => {
        ListItem() {
          RowSwipeDelete({
            rowId: row.id,
            swipeEnabled: !this.multiSelect,
            // 卡体满宽（卡宽 = 条目宽，§4.8）→ 让位 0；其余库页卡窄于行、居中（默认 16）
            cardInset: 0,
            group: this.group,
            content: (): void => {
              this.MemoryRowCard(row)
            },
            onSwipeDelete: (id: string): void => {
              this.onSwipeDelete(row);
            }
          })
        }
        // ★ 条目宽 = 卡宽（CARD_PANEL_WIDTH）+ 卡体 width('100%')——两处同值即逐边重合：拖拽
        // 快照背板按条目轮廓画（规范 §4.8 第二件），条目比卡宽则背板在卡左右各露一条。
        // ★ 本页列表零水平 padding（与「padding 16 + 卡 100%」写法不同），窄宽由条目层承担；
        // ★ 禁在卡体再写 CARD_PANEL_WIDTH：百分比按父（条目）解算，会二次收窄成屏宽-64
        //（真机报障「记忆卡短了」的根因，规范 §4.3 禁双重收窄同族）
        .width(CARD_PANEL_WIDTH)
        .borderRadius(CARD_RADIUS)
      }, (row: MemoryRow): string => this.memoryRowKey(row))
        // 官方拖拽排序（长按条目即拖；上报值 = 数据源下标，本件只透传不做换算；落定对策见上方
        // 「onMove 落位坑」段）。多选态让位（dragMoveHandler 返回 undefined——onMove 参数为
        // Optional<OnMoveHandler>）
        .onMove(this.dragMoveHandler())
      // 0 行提示（条件尾项；文案两态单源在壳侧）
      if (this.emptyText !== '') {
        ListItem() {
          Text(this.emptyText)
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
        }
        .width(CARD_PANEL_WIDTH)
      }
    }
    .width('100%')
    .height('100%')
    // 让位 offset 轨（留白属滚动内容；容器 padding 顶/底 = 视口缩进会裁掉内容）
    .contentStartOffset(this.topPad)
    .contentEndOffset(this.bottomPad + 16)
    // 卡片水平居中（卡宽 CARD_PANEL_WIDTH 窄于列表 ⇒ 靠本属性居中；头槽/空态项为 100% 不受影响）
    .alignListItem(ListItemAlign.Center)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
    // 库内条目上限 200，5 为屏内缓冲（轻行卡；按页设值非全局口径）
    .cachedCount(5)
    // 竖滚开始收起左滑展开行（互斥经 SwipeGroup 单源；与长按拖拽不冲突——拖拽启动时无展开行）
    .onScrollStart((): void => {
      this.group.collapse();
    })
  }
}
