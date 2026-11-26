// 「请求日志」三级页（「更多信息」页入口，照竞品 RikkaHub「Logs」形制定形：开关 + 条目列表 +
// 点条目看详情面板）：把真机实际发出的 HTTP 请求摊开给人看（请求头已掩码 / 请求体已截断 /
// 响应码与耗时 / 错误响应体尾部），供「连不上 / 发不出 / 用不了」类问题应用内自查。
//
// 三件套：本件 = 页面外壳（@State、刷新/清空调度、开关卡、列表行、菜单宿主、面板宿主）；
// ReqLogDetailSheet.ets = 面板内容件（不含 bindSheet，宿主挂——规范-半模态 §8 先例）；
// common/ReqLog.ets = 数据与逻辑（环形缓冲 / 掩码 / 截断）。菜单层并入本件（反碎片下限：
// 两个菜单项不值一件）。
//
// 交互（与「运行日志」页的异同）：**进页读一次**（本页是进程内内存缓冲，进页即见现场——
// 运行日志页「进页空白待刷新」是为避开读沙箱日志文件的启动开销，本页不适用）+ 右上「更多」
// 菜单（刷新 / 清空记录）；**退出清已刷新内容**（2026-08-21 决明口径：页面文本只在停留期间
// 留存，防长文本状态越积越多；内存缓冲不随退出清空——那要用户点「清空记录」）。
// 开关行 = 单开关卡形态（BackgroundPanel.SessionOnlySwitchCard 先例，规范-列表卡片与组卡
// §1.1 第三行）；@StorageLink 双向 = 点开关即写即落盘（persistProp 已注册）。
// ★ 2026-09-25 长列表统一迁 Repeat：List + Repeat.virtualScroll（V1 壳保交互、行卡渲染拆
//   同文件 @ComponentV2 渲染件 + 构造处桥接）；「键含状态与耗时」防线退役——回填走重查
//   整体替换，同 id 新对象靠 item 比对刷新（坑16 键载荷机制等价接替）；0 行分支壳侧 Scroll 兜底。
// ★ 2026-10-04 去重笔：筛选 chips 扩第三档「只看 HTTP 请求」——「出站记录」入口退役的承接；
//   判据（status + source + filter 三参）见 ReqLog.reqLogMatchFilter。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ComponentContent, SymbolGlyphModifier, uiMaterial , UIUtils } from '@kit.ArkUI';
import { AppMenuHost } from '../common/AppMenuHost';
import { IMMERSIVE_LEVEL_KEY, resolvedUiMaterial } from '../common/ImmersiveLevel';
import {
  CARD_PANEL_WIDTH,
  CARD_SPACING,
  MORE_MENU_ANCHOR_RIGHT,
  MORE_MENU_BUTTON_BOTTOM_INSET,
  TITLE_BAR_MASK_EXTRA_HEIGHT,
  cardBg,
  cardDescColor,
  cardTitleColor,
  menuDividerColor,
  selectChipBg,
  selectChipBorderColor,
  selectChipTextColor, CARD_RADIUS
} from '../common/Theme';
import { PageShell } from '../common/PageShell';
import { SETTING_TITLE_REQ_LOG } from '../common/SettingSearch';
import {
  PREF_REQ_LOG_KEY,
  REQ_LOG_FILTER_ALL,
  REQ_LOG_FILTER_FAIL,
  REQ_LOG_FILTER_HTTP,
  REQ_LOG_MAX,
  ReqLogEntry,
  emptyReqLogEntry,
  reqLogClear,
  reqLogClockText,
  reqLogDurationText,
  reqLogIsFailure,
  reqLogMatchFilter,
  reqLogSnapshot,
  reqLogStatusText
} from '../common/ReqLog';
import { sheetPanelOptions } from './chat/KimiSheetCommon';
import { ReqLogDetailSheet } from './ReqLogDetailSheet';

// 「更多」菜单锚点 id（openMenu 的 TargetInfo 定位目标，页面内唯一）
const REQ_LOG_MENU_ANCHOR_ID: string = 'reqLogMenuAnchor';

// 「更多」菜单回调（openMenu 的 ComponentContent 参数载体：@Builder 全局函数无法访问组件
// 实例，回调经参数传入）
interface ReqLogMenuCallbacks {
  onRefresh: () => void;
  onClear: () => void;
}

// 「更多」菜单内容（官方 Menu 组件）：刷新 / 清空记录两项。分割线 mode 必须
// EMBEDDED_IN_MENU（2026-08-21 真机实锤：默认 FLOATING_ABOVE_MENU 在 THICK 材质下完全不可见）
@Builder
function ReqLogMenuBuilder(params: ReqLogMenuCallbacks) {
  Menu() {
    MenuItem({
      symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_clockwise')),
      content: '刷新'
    })
      .onClick(() => {
        params.onRefresh();
      })
    MenuItem({
      symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')),
      content: '清空记录'
    })
      .onClick(() => {
        params.onClear();
      })
  }
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 菜单节点宿主（AppMenuHost 薄壳——生命周期/弹出组装在基类，LogMoreMenuHost 同款）
class ReqLogMenuHost extends AppMenuHost<ReqLogMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: ReqLogMenuCallbacks): ComponentContent<ReqLogMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(ReqLogMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }
}

@Component
export struct ReqLogPage {
  // 沉浸光感整体档位（AppStorage 共享，驱动菜单材质）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 顶部留白（vp，PageMap 传入）：HDS 路径内容区延伸到标题栏背后（渐变模糊蒙层透出滚动内容）
  topPad: number = 0;
  bottomPad: number = 0;
  // 记录开关（@StorageLink 双向即写即落盘；ReqLog 侧每次现读 AppStorage，切换即时生效）
  @StorageLink(PREF_REQ_LOG_KEY) reqLogOn: boolean = false;
  // 列表条目全量快照（非状态量：只喂 shownRows 与统计行，不直接上屏——见「状态最小化」）
  private allRows: ReqLogEntry[] = [];
  // 上屏用列表（全量经筛选档过滤后的产物；驱动 UI）
  @State private shownRows: ReqLogEntry[] = [];
  // 筛选档（chips 选中态；判据在 ReqLog.reqLogMatchFilter 单源）
  @State private filter: string = REQ_LOG_FILTER_ALL;
  // 统计行文案（空串 = 不显示）
  @State private meta: string = '';
  // 详情面板显隐 + 选中条目快照。★ 显隐挂 @Watch = 关闭-再开协调的兜底网（离场动效在途期
  // 再点新行、框架收尾回写压回可见性时按开意图补开；官方依据见 KimiSheetCommon.sheetPanelOptions
  // 第四参注释）
  @State @Watch('onSheetVisibleChanged') private sheetOpen: boolean = false;
  @State private sheetEntry: ReqLogEntry = emptyReqLogEntry();
  // 离场动效在途位（requestCloseDetail 置位 / SheetOptions.onDisappear 清位）与开意图
  // （点行即记、用户关闭清；两处补开据此取件）
  private sheetClosing: boolean = false;
  private intentEntry: ReqLogEntry | null = null;
  private moreMenu: ReqLogMenuHost = new ReqLogMenuHost();

  // 进页：菜单节点初始化 + 读一次快照（内存缓冲，进页即见现场，见文件头「交互」段）
  aboutToAppear(): void {
    this.moreMenu.init(this.getUIContext(), this.menuCallbacks());
    this.refresh();
  }

  private menuCallbacks(): ReqLogMenuCallbacks {
    return {
      onRefresh: (): void => {
        this.refresh();
      },
      onClear: (): void => {
        this.clearRecords();
      }
    };
  }

  // 退出本页：释放菜单内容节点（ComponentContent 用完必须 dispose，否则随进入次数累积泄漏）
  // + 清已刷新内容（内存缓冲不随之清空，见文件头「交互」段）
  aboutToDisappear(): void {
    this.moreMenu.dispose();
    // 先清开意图（防销毁期框架回写可见性触发兜底补开——写已销毁组件），再清展示态
    this.intentEntry = null;
    this.allRows = [];
    this.shownRows = [];
    this.meta = '';
    this.filter = REQ_LOG_FILTER_ALL;
    this.sheetOpen = false;
    this.sheetEntry = emptyReqLogEntry();
  }

  // 刷新（进页 + 菜单触发）：整表快照替换（ReqLog 内部拷贝出栈，调用方改不动缓冲）
  private refresh(): void {
    this.allRows = reqLogSnapshot();
    this.meta = '最近 ' + this.allRows.length + ' 条记录，最多保留 ' + REQ_LOG_MAX + ' 条';
    this.applyFilter();
  }

  // 应用筛选档（刷新与切档共用单点；上限 50 条逐条纯比较，无性能顾虑）。
  // ★ 2026-10-04 去重笔：判据扩来源参（「只看 HTTP 请求」档按来源标签）
  private applyFilter(): void {
    const out: ReqLogEntry[] = [];
    for (const row of this.allRows) {
      if (reqLogMatchFilter(row.status, row.source, this.filter)) {
        out.push(row);
      }
    }
    this.shownRows = out;
  }

  private pickFilter(next: string): void {
    if (this.filter === next) {
      return;
    }
    this.filter = next;
    this.applyFilter();
  }

  // 清空记录（菜单触发）：先清缓冲再刷新——顺序反了会清掉刚刷出来的快照，列表看似没反应
  private clearRecords(): void {
    reqLogClear();
    this.refresh();
    this.showToast('请求记录已清空');
  }

  // 弹出「更多」官方菜单（★ 每次弹出前重建节点——ComponentContent 固化 UI 树不随深浅色
  // 切换更新，2026-08-21 真机实锤；dispose 与新建成对无泄漏）
  private openMoreMenu(): void {
    this.moreMenu.rebuild(this.getUIContext(), this.menuCallbacks());
    this.moreMenu.show(this.getUIContext(), REQ_LOG_MENU_ANCHOR_ID,
      // 第三参 true = 交互形变 + 触点流光（官方最佳实践口径）；档位随 2026-10-17 菜单统一笔改 REGULAR
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, this.immersiveLevel, true));
  }

  // 点行卡开详情。★ 关闭-再开协调：离场动效在途期只记开意图、不写可见性（官方契约：动效
  // 结束后才可再次拉起；在途期写下的 true 会被吞或被收尾回写压回——症状 = 新面板立即被收起）
  private openDetail(row: ReqLogEntry): void {
    this.intentEntry = row;
    if (this.sheetClosing) {
      return; // 动效在途：待补开（onSheetGone 正路 / onSheetVisibleChanged 兜底）
    }
    this.applyOpen();
  }

  // 按开意图落内容与可见性（直开与两处补开共用单入口；无意图即无动作）
  private applyOpen(): void {
    const entry: ReqLogEntry | null = this.intentEntry;
    if (entry === null) {
      return;
    }
    this.sheetEntry = entry;
    this.sheetOpen = true;
  }

  // 离场动效结束（SheetOptions.onDisappear——d.ts：动画结束后回调）：清在途位 + 按开意图补开
  private onSheetGone(): void {
    this.sheetClosing = false;
    if (!this.sheetOpen) {
      this.applyOpen();
    }
  }

  // 可见性变化兜底：非用户关闭路径把可见性写回 false 时按开意图补一次（框架 `$$` 收尾回写
  // 落在动效之后的时序差）；用户关闭必经 requestCloseDetail（先清开意图再写 false），不误触
  private onSheetVisibleChanged(): void {
    if (!this.sheetOpen) {
      this.applyOpen();
    }
  }

  // 详情面板关闭**单入口**（规范-半模态 §1 硬约束：标题栏自绘 xmark 与 onWillDismiss 两路
  // 都必须经它）。本面板纯信息展示、无暂存态 ⇒ 直接关；将来若加确认（§1 三门槛）只需改这里。
  // ★ 关闭-再开协调：先清开意图 + 置离场动效在途位，再写可见性
  private requestCloseDetail(): void {
    this.intentEntry = null;
    this.sheetClosing = true;
    this.sheetOpen = false;
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: message,
      systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.THICK, this.immersiveLevel, false)
    });
  }

  // 记录开关卡（单开关卡形态；文案受「面向用户文案写作规约」约束）
  @Builder
  RecordSwitchCard() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text('记录请求')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
        Text('捕获请求头、正文和响应元数据，记录只存本机内存，退出应用即清，不会自动上传')
          .fontSize(13)
          .fontColor(cardDescColor())
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.reqLogOn })
        .onChange((isOn: boolean): void => {
          this.reqLogOn = isOn;
          // 切换后立刻刷一次：新记录要等下次请求才产生，但统计行与空态提示语义随开关变化
          this.refresh();
        })
    }
    .alignItems(VerticalAlign.Center)
    .width(CARD_PANEL_WIDTH)
    .padding({ left: 16, right: 16, top: 13, bottom: 13 })
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
  }

  // 空态提示行（规范-列表卡片与组卡 §4.3：13fp 次要色 + 卡宽约束、无卡底）。三态：开关关着 /
  // 有记录但被筛选档滤空 / 真为空——第二态须单独提示，否则用户会以为记录丢了
  @Builder
  EmptyHint() {
    Text(this.emptyHintText())
      .fontSize(13)
      .fontColor(cardDescColor())
      .width(CARD_PANEL_WIDTH)
      .textAlign(TextAlign.Start)
  }

  private emptyHintText(): string {
    if (!this.reqLogOn) {
      return '开启记录请求后，这里会列出最近的请求记录';
    }
    if (this.allRows.length > 0) {
      // 有记录但被当前档滤空（提示随档——「只看 HTTP 请求」下别报「没有失败」）
      return this.filter === REQ_LOG_FILTER_HTTP ?
        '没有 HTTP 请求工具发出的记录。切回全部可以看其余记录' :
        '没有失败的记录。切回全部可以看其余记录';
    }
    return '暂无记录。发起一次对话或测试连接后再刷新';
  }

  // 筛选 chip（选项类不是按钮——照 ModelCapsCard 范式：纯 Text + 自绘圆角底，不套 Button 四件套）
  @Builder
  FilterChip(label: string, value: string) {
    Text(label)
      .fontSize(13)
      .fontColor(selectChipTextColor(this.filter === value, this.appColorMode))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(selectChipBg(this.filter === value, this.appColorMode))
      .border({ width: 1, color: selectChipBorderColor(this.filter === value) })
      .onClick((): void => {
        this.pickFilter(value);
      })
  }

  // 列表条目卡（规范 §1.1「列表条目卡」形制：自绘 Button Normal + 内容列 layoutWeight(1)；
  // 卡宽 / 圆角 / padding / 字号照 PromptLibraryPage.TemplateRow——尾部为状态与耗时数据项，无行内动作键）
  // ── 列表头槽（开关卡 + 统计行 + 筛选 chips——非空分支挂 V2 首行 / 空分支直挂，两处复用；
  //    chips 只在有记录时摆——空列表下筛什么都是空）──
  @Builder
  RowsHead() {
    Column({ space: CARD_SPACING }) {
      this.RecordSwitchCard()
      if (this.meta !== '') {
        Text(this.meta)
          .fontSize(13)
          .fontColor(cardDescColor())
          .width(CARD_PANEL_WIDTH)
          .textAlign(TextAlign.Start)
      }
      if (this.allRows.length > 0) {
        Row({ space: 8 }) {
          this.FilterChip('全部', REQ_LOG_FILTER_ALL)
          this.FilterChip('只看失败', REQ_LOG_FILTER_FAIL)
          // 「只看 HTTP 请求」：来源标签与 HttpTransport 实参同引 REQ_LOG_SOURCE_HTTP（单一来源）
          this.FilterChip('只看 HTTP 请求', REQ_LOG_FILTER_HTTP)
        }
        .width(CARD_PANEL_WIDTH)
        .justifyContent(FlexAlign.Start)
      }
    }
    .width('100%')
  }

  @Builder
  Content() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.shownRows.length === 0) {
        // 0 行分支（壳侧 Scroll 兜底——Repeat 无行可挂；开关卡/统计行/空态提示原样）
        Scroll() {
          Column({ space: CARD_SPACING }) {
            this.RowsHead()
            this.EmptyHint()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        // 滚动内容穿透标题栏背后被渐变模糊采样（PageShell 蒙层需有内容可透）
        .clip(false)
      } else {
        ReqLogRows({
          shownRows: UIUtils.enableV2Compatibility(this.shownRows),
          appColorMode: this.appColorMode,
          topPad: this.topPad,
          bottomPad: this.bottomPad,
          headSlot: (): void => {
            this.RowsHead()
          },
          onOpen: (row: ReqLogEntry): void => {
            this.openDetail(row);
          }
        })
          .width('100%')
          .height('100%')
      }

      // 「更多」菜单隐形锚点（1×1 定位点；几何照 LogPageContent —— 右缘距屏边
      // MORE_MENU_ANCHOR_RIGHT，垂直落标题栏键中位）
      Row() {
        Blank()
        Column()
          .width(1)
          .height(1)
          .id(REQ_LOG_MENU_ANCHOR_ID)
      }
      .width('100%')
      .padding({ right: MORE_MENU_ANCHOR_RIGHT })
      .margin({
        top: Math.max(this.topPad - TITLE_BAR_MASK_EXTRA_HEIGHT - MORE_MENU_BUTTON_BOTTOM_INSET, 0)
      })
    }
    .width('100%')
    .height('100%')
  }

  // 详情半模态（面板内容在 ReqLogDetailSheet，本处只组装参数）；bindSheet 挂页面根，
  // 规范-半模态 §1 挂点判据三条：合法树内 / 存活期不因数据销毁 / isShow 与触发键同位
  @Builder
  DetailSheet() {
    ReqLogDetailSheet({
      entry: this.sheetEntry,
      bottomInset: this.bottomPad,
      onClose: (): void => {
        this.requestCloseDetail();
      }
    })
  }

  build() {
    // 页面骨架统一由 PageShell 提供；本页特有：右上「更多」菜单（menuHds 原样传）
    PageShell({
      title: SETTING_TITLE_REQ_LOG,
      menuHds: {
        value: [{
          content: {
            icon: $r('sys.symbol.dot_grid_2x2'),
            action: () => {
              this.openMoreMenu();
            }
          }
        }]
      },
      content: () => {
        this.Content()
      }
    })
      // ★ 关闭链统一：可见性 `$$` 双向 + onWillDismiss 放行后路由到 requestCloseDetail 单入口；
      // 第四参 onDisappear = 关闭-再开协调的动效结束信号（在途期待开在此补开）
      .bindSheet($$this.sheetOpen, this.DetailSheet(), sheetPanelOptions(
        (action: DismissSheetAction): void => {
          action.dismiss();
          this.requestCloseDetail();
        },
        undefined, undefined,
        (): void => {
          this.onSheetGone();
        }))
  }
}

// ═══ 日志清单渲染域（2026-09-25 迁 Repeat 拆出，同文件同域——壳引渲染件单向）═══
// 机制 = List + Repeat.virtualScroll（V2）：★ 键只写日志 id（原「键含状态与耗时」防线退役
// ——回填走重查整体替换，同 id 新对象靠 item 比对刷新）；头槽挂首行；让位 = offset 轨；
// 0 行由壳侧分支渲染；行卡点击上行壳侧 openDetail。
@ComponentV2
struct ReqLogRows {
  // 可见行（壳侧按筛选档派生——筛切换整体替换即刷）
  @Param shownRows: ReqLogEntry[] = [];
  @Param appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @Param topPad: number = 0;
  @Param bottomPad: number = 0;
  // 首行头槽（开关卡 + 统计行 + 筛选 chips——壳侧 V1 Builder）
  @BuilderParam headSlot: () => void;
  // 点行卡上行（壳侧 openDetail 拉详情半模态；★ 读当前 ri.item，禁构造期快照）
  @Event onOpen: (row: ReqLogEntry) => void = () => {
  };

  // 日志行卡（来源·模型 + 状态 + 耗时行 / 方法 + URL 行；★ layoutWeight 必需项语义随卡体
  // 原样迁移——标题过长顶出右边的真机报障防线，规范-列表卡片与组卡 §5 红线 8）。
  // 蒙层边距：卡底 Column + 四周 padding 4（蒙层距卡外圈 4vp，壳 padding 14→10 回添）
  @Builder
  LogRow(ri: RepeatItem<ReqLogEntry>) {
    Column() {
      Button() {
        Row({ space: 10 }) {
          Column({ space: 3 }) {
            Row({ space: 8 }) {
              // 来源 · 模型（多模型与多中转站下 URL 完全一样，不带模型名就看不出这条是谁
              // 发的；模型为空（拉模型清单这类）时只显示来源）
              Text(ri.item.source + (ri.item.model !== '' ? ' · ' + ri.item.model : ''))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                // ★ layoutWeight 是必需项而非排版偏好（标题最长 200 字符）：权重子组件吃满
                // 剩余宽度，状态与耗时恒有其位（贴右缘），标题超出即省略号（坑27 家族；坑76 记形）
                .layoutWeight(1)
              Text(reqLogStatusText(ri.item.status))
                .fontSize(13)
                .fontColor(reqLogIsFailure(ri.item.status) ? $r('sys.color.ohos_id_color_alert') :
                  $r('sys.color.font_emphasize'))
              // Blank 已撤：权重子组件存在时其 flexGrow 不参与布局、恒 0 宽白占间隙；右推
              // 责任由标题的 layoutWeight 承担
              Text(reqLogClockText(ri.item.at) +
                (reqLogDurationText(ri.item.durationMs) !== '' ?
                  ' · ' + reqLogDurationText(ri.item.durationMs) : ''))
                .fontSize(13)
                .fontColor(cardDescColor())
            }
            .width('100%')

            Text(ri.item.method + ' ' + ri.item.url)
              .fontSize(13)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
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
    List({ space: CARD_SPACING }) {
      Repeat<ReqLogEntry>(this.shownRows)
        .each((ri: RepeatItem<ReqLogEntry>) => {
          ListItem() {
            // 首行 = 头槽 + 首卡；保真层居中（CARD_PANEL_WIDTH 卡防整列左偏）
            Column({ space: CARD_SPACING }) {
              if (ri.index === 0) {
                this.headSlot()
              }
              this.LogRow(ri)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }
        })
        // 键 = 日志 id（身份唯一；状态/耗时变化靠重查整体替换后 item 比对刷新）
        .key((row: ReqLogEntry): string => row.id)
        .virtualScroll()
    }
    .width('100%')
    .height('100%')
    // 让位 offset 轨（原 Scroll padding + 尾部占位行的等价）
    .contentStartOffset(this.topPad)
    .contentEndOffset(this.bottomPad + 16)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    // 滚动内容穿透标题栏背后被渐变模糊采样（PageShell 蒙层需有内容可透）
    .clip(false)
    // 请求日志上限 50 有界，5 为屏内缓冲（按页设值非全局口径）
    .cachedCount(5)
  }
}
