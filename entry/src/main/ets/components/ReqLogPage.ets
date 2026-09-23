// 「请求日志」三级页（「更多信息」页入口，2026-09-23 请求日志笔；照竞品 RikkaHub「Logs」形制
// 定形——开关 + 条目列表 + 点条目看详情面板）：
// 把真机实际发出的 HTTP 请求摊开给人看（请求头已掩码 / 请求体已截断 / 响应码与耗时 / 错误
// 响应体尾部），供「连不上 / 发不出 / 用不了」类问题在应用内自查，不必连电脑看 DevEco。
//
// 三件套职责（照 LogPage 四件套范式裁剪：本页更小，菜单层并入本件不另开文件——反碎片下限
// ①「新文件须能一句话说清独立职责」，两个菜单项不值一件）：
// · 本件 = 页面外壳（@State、生命周期、刷新/清空调度、开关卡、列表行、菜单节点宿主、详情
//   面板宿主）；· ReqLogDetailSheet.ets = 面板内容件（不含 bindSheet，宿主挂——规范-半模态
//   §8 先例）；· common/ReqLog.ets = 数据与逻辑（环形缓冲 / 掩码 / 截断）。
//
// 交互（与「运行日志」页的异同）：**进页读一次**（本页数据是进程内内存缓冲，进页即应见现场
// ——与运行日志页「进页空白待刷新」不同，那是为避开读沙箱日志文件的启动开销）+ 标题栏
// 右上「更多」菜单（刷新 / 清空记录）；**退出本页清已刷新内容**（aboutToDisappear，照
// 运行日志页 2026-08-21 决明口径：页面文本只在停留期间留存，防长文本状态越积越多；内存
// 缓冲本身不随退出清空——那要用户点「清空记录」）。
//
// 开关行 = 单开关卡形态（自绘卡 cardBg + 圆角 16 + CARD_PANEL_WIDTH + 官方 Toggle 右置，
// BackgroundPanel.SessionOnlySwitchCard 先例；规范-列表卡片与组卡 §1.1 第三行）。@StorageLink
// 双向绑定 = 点开关即写即落盘（persistProp 已注册，见 EntryAbility）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ComponentContent, SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { AppMenuHost } from '../common/AppMenuHost';
import { IMMERSIVE_LEVEL_KEY, resolvedUiMaterial } from '../common/ImmersiveLevel';
import {
  CARD_PANEL_WIDTH,
  CARD_SPACING,
  MORE_MENU_ANCHOR_RIGHT,
  MORE_MENU_BUTTON_BOTTOM_INSET,
  TITLE_BAR_MASK_EXTRA_HEIGHT,
  badgeBg,
  cardBg,
  cardDescColor,
  cardTitleColor,
  menuDividerColor
} from '../common/Theme';
import { PageShell } from '../common/PageShell';
import { SETTING_TITLE_REQ_LOG } from '../common/SettingSearch';
import {
  PREF_REQ_LOG_KEY,
  REQ_LOG_FILTER_ALL,
  REQ_LOG_FILTER_FAIL,
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

// 「更多」菜单内容（官方 Menu 组件）：两项——刷新 / 清空记录。分割线 mode 必须
// EMBEDDED_IN_MENU（2026-08-21 真机实锤：默认 FLOATING_ABOVE_MENU 在 THICK 材质下完全不可见，
// LogPageMoreMenu 同款）
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
  // 记录开关（@StorageLink 双向绑定——点开关即写即落盘，persistProp 已注册；ReqLog 侧
  // 每次现读 AppStorage，故切换即时生效，下一个请求按新值）
  @StorageLink(PREF_REQ_LOG_KEY) reqLogOn: boolean = false;
  // 列表条目全量快照（非状态量：只喂 shownRows 与统计行，不直接上屏——见「状态最小化」）
  private allRows: ReqLogEntry[] = [];
  // 上屏用列表（全量经筛选档过滤后的产物；驱动 UI）
  @State private shownRows: ReqLogEntry[] = [];
  // 筛选档（chips 选中态；判据在 ReqLog.reqLogMatchFilter 单源）
  @State private filter: string = REQ_LOG_FILTER_ALL;
  // 统计行文案（空串 = 不显示）
  @State private meta: string = '';
  // 详情面板显隐 + 选中条目快照
  @State private sheetOpen: boolean = false;
  @State private sheetEntry: ReqLogEntry = emptyReqLogEntry();
  private moreMenu: ReqLogMenuHost = new ReqLogMenuHost();

  // 进页：菜单节点初始化 + 读一次快照（见文件头「交互」段——本页数据是内存缓冲，进页即应
  // 见现场，不学运行日志页的空白待刷新）
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

  // 退出本页：释放菜单内容节点（官方 SDK 要求 ComponentContent 用完 dispose，否则随进入
  // 次数累积泄漏——LogPage 同款）+ 清已刷新内容（内存缓冲不随之清空，见文件头「交互」段）
  aboutToDisappear(): void {
    this.moreMenu.dispose();
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

  // 应用筛选档（刷新与切档两处共用单点；40 条上限下逐条判据是纯比较，无性能顾虑）
  private applyFilter(): void {
    const out: ReqLogEntry[] = [];
    for (const row of this.allRows) {
      if (reqLogMatchFilter(row.status, this.filter)) {
        out.push(row);
      }
    }
    this.shownRows = out;
  }

  // 切换筛选档（chips 点击）
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

  // 弹出「更多」官方菜单（★ 每次弹出前重建节点——ComponentContent 固化 UI 树不随深浅色切换
  // 更新，LogPage 2026-08-21 真机实锤；dispose 与新建成对无泄漏）
  private openMoreMenu(): void {
    this.moreMenu.rebuild(this.getUIContext(), this.menuCallbacks());
    this.moreMenu.show(this.getUIContext(), REQ_LOG_MENU_ANCHOR_ID,
      // 第三参 true = 交互形变 + 触点流光（官方最佳实践口径，同 LogPage）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.THICK, this.immersiveLevel, true));
  }

  private openDetail(row: ReqLogEntry): void {
    this.sheetEntry = row;
    this.sheetOpen = true;
  }

  // 详情面板关闭**单入口**（规范-半模态 §1 新码硬约束：标题栏自绘 xmark 与 onWillDismiss
  // 两路都必须经它，方法内决定「直接关 / 先确认」）。本面板是纯信息展示、无暂存态 ⇒ 直接关；
  // 集中一处的意义 = 将来若加确认（§1 三门槛）只需改这里，不会漏掉某一路
  private requestCloseDetail(): void {
    this.sheetOpen = false;
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: message,
      systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.THICK, this.immersiveLevel, false)
    });
  }

  // 记录开关卡（单开关卡形态；文案受「面向用户文案写作规约」约束——顿号并列，无冒号括号连环）
  @Builder
  RecordSwitchCard() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text('记录请求')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
        Text('捕获请求头、正文和响应元数据，记录只存本机内存，退出应用即清')
          .fontSize(13)
          .fontColor(cardDescColor())
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.reqLogOn })
        .onChange((isOn: boolean): void => {
          this.reqLogOn = isOn;
          // 开关状态切换后立刻刷一次：新记录要等下次请求才产生，但统计行与空态提示
          // 语义随开关变化（关闭态空列表提示「先开启记录」，开着则是「暂无记录」）
          this.refresh();
        })
    }
    .alignItems(VerticalAlign.Center)
    .width(CARD_PANEL_WIDTH)
    .padding({ left: 16, right: 16, top: 13, bottom: 13 })
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
  }

  // 空态提示行（规范-列表卡片与组卡 §4.3：行内提示行，13fp 次要色 + 卡宽约束、无卡底）。
  // 三态：开关关着 / 有记录但被筛选档滤空 / 真为空——第二态若不单独提示，用户会以为记录
  // 丢了（「只看失败」开着时列表空 ≠ 没有记录）
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
      return '没有失败的记录。切回全部可以看其余记录';
    }
    return '暂无记录。发起一次对话或测试连接后再刷新';
  }

  // 筛选 chip（选项类——**「选项」不是按钮**，故照 ModelCapsCard 范式：纯 Text + 自绘胶囊底，
  // 不套 Button 四件套；宪法「选项类 chips 照 ModelCapsCard 范式」条）
  @Builder
  FilterChip(label: string, value: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.filter === value ? $r('sys.color.ohos_id_color_emphasize') : cardDescColor())
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(this.filter === value ? $r('sys.color.comp_background_secondary') :
        badgeBg(this.appColorMode))
      .onClick((): void => {
        this.pickFilter(value);
      })
  }

  // 列表条目卡（规范 §1.1 第六行「列表条目卡」形制：自绘 Button Normal + 内容列
  // layoutWeight(1)；卡宽 / 圆角 16 / padding 14 / 标题 15fp Medium / 副行 13fp 照
  // PromptLibraryPage.TemplateRow——尾部为状态与耗时两个数据项，无行内动作键）
  @Builder
  LogRow(row: ReqLogEntry) {
    Button() {
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Row({ space: 8 }) {
            // 来源 · 模型（2026-09-23 扩充笔）：多模型与多中转站下 URL 完全一样，不带模型名
            // 就看不出这条是谁发的；模型为空（拉模型清单这类）时只显示来源
            Text(row.source + (row.model !== '' ? ' · ' + row.model : ''))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              // ★ layoutWeight 是必需项而非排版偏好（2026-09-23 真机报障「日志卡标题过长顶出
              // 右边」；模型名用户手填，最长 200 字符）：官方 layoutWeight 口径——行内出现生效值
              // >0 的权重子组件时，非权重子组件先按自然尺寸占位、权重子组件吃完全部剩余宽度，
              // 且 flexShrink/flexGrow 一律不再参与本行布局。故状态与耗时恒有其位（贴右缘），
              // 标题恒被压到剩下的宽度上、超出即省略号。只写 maxLines+ellipsis 拦不住——每个
              // 兄弟各自量到「整行宽」上限，行内依次排布时总和仍越界，把状态与耗时挤出卡右缘
              //（坑27 家族；坑76 记形）
              .layoutWeight(1)
            Text(reqLogStatusText(row.status))
              .fontSize(13)
              .fontColor(reqLogIsFailure(row.status) ? $r('sys.color.ohos_id_color_alert') :
                $r('sys.color.font_emphasize'))
            // Blank 已撤（原用于把时间推到右缘）：权重子组件存在时 Blank 的 flexGrow 不参与
            // 布局，其宽度恒 0、只白占一个 8vp 间隙；右推责任已由标题的 layoutWeight 承担
            Text(reqLogClockText(row.at) +
              (reqLogDurationText(row.durationMs) !== '' ?
                ' · ' + reqLogDurationText(row.durationMs) : ''))
              .fontSize(13)
              .fontColor(cardDescColor())
          }
          .width('100%')

          Text(row.method + ' ' + row.url)
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
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .padding(14)
    .onClick((): void => {
      this.openDetail(row);
    })
  }

  // 内容区（@Builder：PageShell 的 @BuilderParam 须传 @Builder 方法，不能 lambda 内直接写 UI）
  @Builder
  Content() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column({ space: CARD_SPACING }) {
          this.RecordSwitchCard()
          if (this.meta !== '') {
            Text(this.meta)
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
              .textAlign(TextAlign.Start)
          }
          // 筛选档（有记录才摆——空列表下筛什么都是空，chips 是纯噪音）
          if (this.allRows.length > 0) {
            Row({ space: 8 }) {
              this.FilterChip('全部', REQ_LOG_FILTER_ALL)
              this.FilterChip('只看失败', REQ_LOG_FILTER_FAIL)
            }
            .width(CARD_PANEL_WIDTH)
            .justifyContent(FlexAlign.Start)
          }
          // 列表（Scroll + Column + ForEach——规范 §2：列表条目卡禁塞进 List；键含状态与耗时，
          // 否则「进行中 → 完成」的回填不会驱动行重建）
          ForEach(this.shownRows, (row: ReqLogEntry) => {
            this.LogRow(row)
          }, (row: ReqLogEntry): string => row.id + '|' + row.status + '|' + row.durationMs)
          if (this.shownRows.length === 0) {
            this.EmptyHint()
          }
          // 尾部占位（底部避让区 + 卡距，末卡不贴屏幕底）
          Row()
            .height(this.bottomPad + 16)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: this.topPad, bottom: 0 })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      // 滚动内容穿透标题栏背后被渐变模糊采样（PageShell 蒙层需有内容可透）
      .clip(false)

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

  // 详情半模态内容（面板内容件在 ReqLogDetailSheet——本处只组装参数；bindSheet 挂页面根，
  // 规范-半模态 §1 挂点判据三条：合法树内 / 存活期不因数据销毁（页面根不随行重建）/
  // isShow 与触发键同位（sheetOpen 与列表行同组件位））
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
    // 页面骨架统一由 PageShell 提供（背景层/透明背景/标题栏/HDS 回退双分支）；本页特有：
    // 右上角「更多」菜单（HDS 传 menuHds、回退传 menuNav——两体系菜单类型不同，分别原样传，
    // LogPage 同款）。bindSheet 挂页面根（MemoryLibraryPage 先例形态）
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
      menuNav: [{
        value: '更多',
        // 符号资源须走 symbolIcon（`icon` 是图片槽位，Symbol 不显示——2026-09-13 全族收口）
        symbolIcon: new SymbolGlyphModifier($r('sys.symbol.dot_grid_2x2')),
        action: () => {
          this.openMoreMenu();
        }
      }],
      content: () => {
        this.Content()
      }
    })
      .bindSheet(this.sheetOpen, this.DetailSheet(), sheetPanelOptions(
        (): void => {
          this.requestCloseDetail();
        }))
  }
}
