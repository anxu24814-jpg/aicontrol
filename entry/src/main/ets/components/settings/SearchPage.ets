// 设置项搜索页（2026-08-29 M2c 自 dshinhm 同名页随迁；设置页签标题栏右上角搜索键 → 官方
// 路由 push 进入）：顶部官方 Search 搜索框（defaultFocus 自动获焦拉起输入法 + searchButton
// 搜索钮 + 键盘搜索键默认 EnterKeyType.Search，三者点击均触发 onSubmit——本地 SDK
// search.d.ts 核实）+ 下方内容区：未提交时显示搜索历史（点击词条直接搜、可清空）与最近
// 使用，提交后显示结果列表（标题/面包屑走官方 HdsListItemCard 默认样式，点击经官方系统级
// 转场 push 到目标页）。
// 数据：注册表/匹配/历史持久化全部在 common/SettingSearch.ets（单一数据源，同步约定见该
// 文件头注释）；本页只做展示与跳转。
// 防循环：注册表不含本页（搜索页自身不可被搜到），跳转永远离开本页；
// 内存：历史 MAX_SEARCH_HISTORY 条、最近使用 MAX_RECENT_USE 条均有界、结果数组每次搜索
// 整体替换，无订阅无定时器，aboutToDisappear 无需释放。
// ★ 页面骨架改道说明（PROGRESS.md 风险①）：aicontrol 无 PageShell——ProviderPage 模板的
// HdsNavDestination/NavDestination 壳在 HomeNavigation.PageMap 内，而标题栏 stackBuilder
// 搜索框依赖本页 keyword 状态（$$ 双向绑定），壳在 PageMap 内无法把 builder 传回标题栏。
// 故本页自包壳（=dshinhm PageShell 已验证形态同构）：HDS 路径 HdsNavDestination 根透明 +
// 页内铺底层 + 官方标题栏（搜索框经 stackBuilder 嵌入标题栏、与返回键横向并排）；回退路径
// 普通 NavDestination + 搜索框在内容区顶部（回退无 stackBuilder 机制）。
// 搜索框位置（dshinhm 2026-08-22 改版定稿随迁）：HDS 路径内容区整幅滚动、延伸到标题栏
// 背后经渐变模糊蒙层透出（与其它二级页同规格），顶部留白 topPad 保首项静止位置。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';
import { HdsListItemCard, HdsNavDestination, TitleSize } from '@kit.UIDesignKit';
import {
  findItemByTitle,
  MAX_RECENT_USE,
  recordRecentUse,
  recordSearchHistory,
  RECENT_USE_KEY,
  SEARCH_HISTORY_KEY,
  searchSettingItems,
  SettingSearchItem
} from '../../common/SettingSearch';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, hdsTitleBarOptions, resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { HistorySection, RecentSection } from './SearchSections';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor } from '../../common/Theme';

@Component
export struct SearchPage {
  // 顶部留白（vp，导航壳下发）：HDS 路径滚动内容顶部留白，首项静止时落在渐变模糊蒙层
  // 下方（同其它二级页）；回退路径壳传 0
  @Prop topPad: number = 0;
  // 页面底部留白（vp，导航壳下发——底部避让区让位）
  @Prop bottomPad: number = 0;
  // 路由栈（导航壳传入，与根 Navigation 同一引用）：点击结果项 pushPathByName 入栈目标
  // 设置页（官方系统级转场）
  pathStack: NavPathStack = new NavPathStack();
  // 系统颜色模式（深浅色切换自动刷新卡片/词条配色）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 沉浸光感整体档位（搜索框材质随沉浸光感总档，
  // 先例 = 弹窗/按钮，见 common/ImmersiveLevel.ets）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关（2026-09-03）：仅回退路径消费——HDS 路径搜索框嵌标题栏（stackBuilder，
  // 属材质生效区）恒光感不受本开关影响；回退路径搜索框在内容区顶部（受影响区），true =
  // 官方灰实底 / false = REGULAR 材质。AppStorage 订阅式切换即刷（坑16 正解，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 搜索历史/最近使用长度（@StorageLink 仅用于本页「首次进入」空态判断——有数据时渲染
  // HistorySection/RecentSection（分区展示已拆至 SearchSections.ets，子组件自持
  // @StorageLink 读数据与清空）；记录/清空走 SettingSearch 函数写 AppStorage，本处自动刷新。
  // ★ 2026-09-20 自检修复：最近使用的两处判据不再直读本数组，一律走 displayableRecentCount
  // （展示侧同源过滤——持久化里的退役 title 不喂判据，见该函数注释）
  @StorageLink(SEARCH_HISTORY_KEY) history: string[] = [];
  @StorageLink(RECENT_USE_KEY) recent: string[] = [];
  // 输入中的关键词（Search 组件 $$ 双向绑定；历史词条点击回填也走它）
  @State keyword: string = '';
  // 是否已提交搜索（false = 显示历史区；true = 显示结果区）
  @State submitted: boolean = false;
  // 本次搜索结果（每次搜索整体替换，有界——注册表总量有限）
  @State results: SettingSearchItem[] = [];
  // 官方 HDS 导航可用性（与 HomeNavigation 根容器同一能力位）：决定搜索框位置——
  // HDS 嵌入标题栏（stackBuilder 覆盖层）/ 回退在内容区顶部
  private hdsAvailable: boolean = canIUse('SystemCapability.UIDesign.HDSComponent.Core');
  // 官方 HDS 列表项卡片可用性（要求 HDSComponent.Full，比 Core 更严格；与 SettingsPage
  // 行卡同一能力位——决定结果卡片用官方 HdsListItemCard / 回退自制卡片）
  private hdsListCardAvailable: boolean = canIUse('SystemCapability.UIDesign.HDSComponent.Full');

  // 执行搜索（onSubmit / 历史词条点击统一入口）：精确匹配 + 记录历史 + 切到结果区
  private doSearch(term: string): void {
    const kw: string = term.trim();
    if (kw === '') {
      return;
    }
    this.keyword = kw;
    this.results = searchSettingItems(kw);
    this.submitted = true;
    recordSearchHistory(kw);
  }

  // 可展示的最近使用条数（★ 2026-09-20 自检修复：挂载与空态两处判据与展示侧同源）——展示侧
  //（SearchSections.recentItems）逐条经注册表反查过滤，注册表里没有的 title 不渲染；而设置项
  // 退役会让持久化里残留的旧 title 解析不到（如应用内自检退役后残留的「自检」，该键在备份
  // 排除表、不随恢复覆盖）——判据若仍直读未过滤数组，会出现「最近使用」板块只剩标题行与
  // 清空键、且首次引导句被一并挡住的空壳。故两处判据一律走本函数（读 this.recent 保
  // @StorageLink 响应性；注册表反查在调用期做——P-9 求值序，不可放进模块顶层初始化式）
  private displayableRecentCount(): number {
    let count: number = 0;
    const limit: number = Math.min(this.recent.length, MAX_RECENT_USE);
    for (let i = 0; i < limit; i++) {
      if (findItemByTitle(this.recent[i]) !== undefined) {
        count++;
      }
    }
    return count;
  }

  // 点击结果项：记录最近使用 + 官方路由 push 目标页（系统级转场；tab >= 0 时带分段参数，
  // 本轮外观页仅光感面板不消费该参数——「背景」面板迁入时接 initialTab）
  private openItem(item: SettingSearchItem): void {
    recordRecentUse(item.title);
    // params 透传（2026-08-30 系统提示词条目：param = 编辑对象 id；未定义 = 现行为不变）
    this.pathStack.pushPathByName(item.pageName,
      item.param !== undefined ? item.param : (item.tab >= 0 ? item.tab : null));
  }

  // 结果项卡片（dshinhm 定稿随迁）：官方 HdsListItemCard 两行 = 标题 primaryText + 面包屑
  // secondaryText（官方主/副文本样式）；宽度不设 width（官方示例姿势）——实际 = 容器 100%
  // − 内部 16vp×2 = CARD_PANEL_WIDTH，与本页历史区/搜索框天然对齐；
  // 回退路径（无 HDS Full 能力）保留自制卡片（Text 16vp 无字重），两级仍一致
  @Builder
  ResultCard(item: SettingSearchItem) {
    if (this.hdsListCardAvailable) {
      HdsListItemCard({
        textItem: {
          primaryText: { text: item.title },
          secondaryText: { text: item.path }
        },
        cardBorderRadius: 16,
        onClick: () => {
          this.openItem(item);
        }
      })
    } else {
      // 回退自制卡（Button(Normal) 包裹 = 官方原生按压蒙层，2026-09-12 UI 同形异构归一
      // 笔 1——与 HdsListItemCard 分支按压反馈对齐；Text 16vp 无字重两级一致）
      Button() {
        Column({ space: 4 }) {
          Text(item.title)
            .fontSize(16)
            .fontColor($r('sys.color.font_primary'))
          Text(item.path)
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .type(ButtonType.Normal)
      .width(CARD_PANEL_WIDTH)
      .padding(16)
      .borderRadius(16)
      .backgroundColor(cardBg(this.appColorMode))
      .onClick(() => {
        this.openItem(item);
      })
    }
  }

  // 空态提示（无结果 / 首次进入引导共用）：官方放大镜符号 + 主/副文案垂直居中。
  // 纯文字+符号组件、无 HDS 依赖，两路径天然一致；符号/副文案用 font_secondary 弱化视觉，
  // 主文案 font_primary 深浅色自动反色
  @Builder
  EmptyHint(main: string, sub: string) {
    Column({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(24)
        .fontColor([cardDescColor()])
      Text(main)
        .fontSize(16)
        .fontColor($r('sys.color.font_primary'))
      Text(sub)
        .fontSize(14)
        .fontColor(cardDescColor())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .margin({ top: 32 })
  }

  // 搜索框本体（两路径共用：HDS 内嵌标题栏 / 回退在内容区顶部）：
  // defaultFocus(true) 进页自动获焦 + 拉起输入法（@since 9，NavDestination 层级页面
  // 生效；enableKeyboardOnFocus 默认 true 勿多写）；
  // searchButton 框尾「搜索」文字钮（点击同时触发 onSubmit，d.ts 核实）；
  // 键盘搜索键 = EnterKeyType.Search（Search 默认值，无需显式设）；
  // $$ 双向绑定：历史词条点击回填搜索框；
  // 沉浸光感材质：基准档 REGULAR（2026-09-12 输入族统一，原官方场景搜索框为 THIN），
  // 随沉浸光感总档（「无」档显式关闭）；官方姿势：先透明背景再设材质；
  // ★ 双态（2026-09-03 内容区回退）：回退路径（内容区，受影响）= 按 contentFallback 开关
  // 实底（官方灰，语义色自动深浅反色）/ 光感（REGULAR）；HDS 路径（标题栏 stackBuilder，
  // 生效区）= 恒光感不受开关影响——正是本组件的「两路径共用」口径下开关只作用于回退路径
  // 的落地（hdsAvailable 判定即路径判定）；
  // 高度 40vp 与标题栏返回键（官方 40vp 圆钮）对齐（应用市场搜索页同款观感）；
  // 宽度 100% 由外层容器约束（HDS = 标题栏覆盖层剩余宽度；回退 = CARD_PANEL_WIDTH）
  @Builder
  SearchBox() {
    Search({ value: $$this.keyword, placeholder: '搜索设置项' })
      .searchButton('搜索')
      .defaultFocus(true)
      // 回退路径实底态 = 官方灰阶实色（app.color.comp_fallback_gray 深浅分治、不透明）；
      // 其余（HDS 恒光感 / 回退光感态）= 先透明背景再设材质（官方姿势）
      .backgroundColor(!this.hdsAvailable && this.contentFallback ?
        $r('app.color.comp_fallback_gray') : Color.Transparent)
      .systemMaterial(!this.hdsAvailable && this.contentFallback ? uiMaterial.Material.empty :
        resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, this.immersiveLevel, false))
      .width('100%')
      .height(40)
      .onChange((value: string) => {
        // 清空输入时退回历史区（结果区只在提交后出现）；非空修改不自动重搜——
        // 提交式搜索设计（onSubmit 才出结果，与搜索历史记录时机一致，dshinhm 定稿随迁）
        if (value.trim() === '') {
          this.submitted = false;
          this.results = [];
        }
      })
      .onSubmit((value: string) => {
        this.doSearch(value);
      })
  }

  // 标题栏覆盖层（官方 stackBuilder @since 6.0.0(20)，经 hdsTitleBarOptions 第 6 参——
  // 官方指南《设置自定义区域》）：搜索框与返回键横向并排。
  // 左侧留白 = 返回键避让：标题栏起始 padding 16vp + 返回键 40vp + 间隔 8vp = 64vp
  //（HDS 标题栏几何真机量测值，dshinhm AGENTS.md「菜单弹窗定位约定」节；右侧与菜单按钮
  // 同规格 16vp）；命中测试 Transparent——覆盖层整栏铺在返回键上方，空白区不拦截
  // 触摸、返回键保持可点
  @Builder
  TitleBarSearch() {
    Row() {
      this.SearchBox()
    }
    .width('100%')
    .height('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 64, right: 16 })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  // 内容区（两路径共用；HDS 路径搜索框在标题栏内不重复布局，回退路径搜索框固定在内容区
  // 顶部）：下方 = 历史/最近使用/结果三态 + 空态；键盘弹起盖住底部时可滚动查看
  @Builder
  PageContent() {
    Column() {
      if (!this.hdsAvailable) {
        Column() {
          this.SearchBox()
        }
        .width(CARD_PANEL_WIDTH)
        .margin({ top: this.topPad, bottom: 16 })
      }

      Scroll() {
        Column({ space: CARD_SPACING }) {
          if (!this.submitted) {
            if (this.history.length > 0) {
              HistorySection({ onSearch: (term: string) => {
                this.doSearch(term)
              } })
            }
            if (this.displayableRecentCount() > 0) {
              // 板块间距（dshinhm 决明反馈定稿随迁）：「最近使用」板块 margin top 12 拉开
              // 层级——结果区（submitted）卡片间距仍 CARD_SPACING 不受影响
              RecentSection({ onOpen: (item: SettingSearchItem) => {
                this.openItem(item)
              } })
                .margin({ top: 12 })
            }
            // 首次进入（无历史、无最近使用）：内容区全空白无引导——空态与无结果共用
            // EmptyHint，引导用户输入
            if (this.history.length === 0 && this.displayableRecentCount() === 0) {
              this.EmptyHint('输入关键词搜索设置项', '例如 光感、材质、模型')
            }
          } else if (this.results.length > 0) {
            ForEach(this.results, (item: SettingSearchItem) => {
              this.ResultCard(item)
            }, (item: SettingSearchItem) => item.title)
          } else {
            // 无匹配空态（官方符号 + 主/副文案，dshinhm 定稿随迁）
            this.EmptyHint('未找到相关设置项', '换个关键词试试')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Start)
        .padding({ top: this.hdsAvailable ? this.topPad : 0, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      // 滚动内容不足视口时顶对齐（Scroll align 默认 Center 坑——同 InfoPage）
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
  }

  build() {
    // ★ 自包壳（见头注释改道说明）：HDS/回退双分支与 ProviderPage 模板同构（根透明 +
    // 页内铺底 + 标题栏 TITLE_S）；HDS 路径搜索框经 stackBuilder 嵌标题栏（传入即主标题
    // 置空，hdsTitleBarOptions 内部处理），回退路径搜索框由 PageContent 在内容区顶部提供
    if (this.hdsAvailable) {
      HdsNavDestination() {
        Column() {
          this.PageContent()
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_bg'))
      }
      .backgroundColor(Color.Transparent)
      .titleBar(hdsTitleBarOptions('搜索', this.immersiveLevel,
        TitleSize.TITLE_S, undefined, (): void => this.TitleBarSearch()))
    } else {
      NavDestination() {
        Column() {
          this.PageContent()
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_bg'))
      }
      .backgroundColor(Color.Transparent)
      .title('搜索')
    }
  }
}
