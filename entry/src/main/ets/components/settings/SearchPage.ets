// 设置项搜索页（设置页签标题栏右上角搜索键 → 官方路由 push）：顶部官方 Search 搜索框
// （defaultFocus 自动获焦拉起输入法、searchButton 搜索钮、键盘搜索键 EnterKeyType.Search，
// 三者均触发 onSubmit——本地 search.d.ts 核实）+ 内容区：未提交时显示搜索历史与最近使用，
// 提交后显示结果列表（标题/面包屑走 HdsListItemCard 默认样式，点击经官方转场 push）。
// 数据：注册表/匹配/历史持久化全部在 common/SettingSearch.ets（单一数据源），本页只做
// 展示与跳转。防循环：注册表不含本页，跳转永远离开本页。内存：历史/最近使用均有界、结果
// 数组每次整体替换，无订阅无定时器，aboutToDisappear 无需释放。
// ★ 自包壳（本工程无 PageShell 可用）：标题栏 stackBuilder 搜索框依赖本页 keyword 状态
// （$$ 绑定），壳在 PageMap 内无法把 builder 传回标题栏——故 HdsNavDestination 根透明 +
// 页内铺底 + 官方标题栏（搜索框经 stackBuilder 嵌入，与返回键并排）。
// 搜索框位置：内容区整幅滚动、延伸到标题栏背后经渐变模糊蒙层透出（与其它二级页同规格），
// 顶部留白 topPad 保首项静止位置。
import { CARD_RADIUS } from '../../common/Theme';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';
import { HdsNavDestination, TitleSize } from '@kit.UIDesignKit';
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
import { IMMERSIVE_LEVEL_KEY, hdsTitleBarOptions, resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { HistorySection, RecentSection } from './SearchSections';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor } from '../../common/Theme';

@Component
export struct SearchPage {
  // 顶部留白（vp，导航壳下发）：滚动内容顶部留白，首项静止时落在渐变模糊蒙层下
  @Prop topPad: number = 0;
  // 页面底部留白（vp，导航壳下发——底部避让区让位）
  @Prop bottomPad: number = 0;
  // 路由栈（导航壳传入，与根 Navigation 同一引用）：结果项 pushPathByName 入栈目标设置页
  pathStack: NavPathStack = new NavPathStack();
  // 系统颜色模式（深浅色切换自动刷新卡片/词条配色）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 沉浸光感整体档位（搜索框材质随总档，见 common/ImmersiveLevel.ets）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 搜索历史/最近使用（@StorageLink 供本页「首次进入」空态判断；分区展示已拆至
  // SearchSections.ets，子组件自持读取与清空）。★ 最近使用判据一律走 displayableRecentCount，
  // 不直读本数组（见该函数注释）
  @StorageLink(SEARCH_HISTORY_KEY) history: string[] = [];
  @StorageLink(RECENT_USE_KEY) recent: string[] = [];
  // 输入中的关键词（Search 组件 $$ 双向绑定；历史词条点击回填也走它）
  @State keyword: string = '';
  // 是否已提交搜索（false = 显示历史区；true = 显示结果区）
  @State submitted: boolean = false;
  // 本次搜索结果（每次搜索整体替换，有界——注册表总量有限）
  @State results: SettingSearchItem[] = [];

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

  // 可展示的最近使用条数——判据与展示侧（SearchSections）同源：展示侧逐条经注册表反查过滤，
  // 注册表里没有的退役 title 不渲染；判据若直读未过滤数组，会出现「最近使用」板块只剩标题行
  // 与清空键的空壳。故两处一律走本函数（读 this.recent 保 @StorageLink 响应性；注册表反查
  // 在调用期做——P-9 求值序，不可放进模块顶层初始化式）
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

  // 点击结果项：记录最近使用 + 官方路由 push 目标页（tab 参数为历史字段，重梳后全表 -1
  // 无分段消费页，见 SettingSearch 注册表）
  private openItem(item: SettingSearchItem): void {
    recordRecentUse(item.title);
    // params 透传（param = 编辑对象 id；未定义 = 现行为不变）
    this.pathStack.pushPathByName(item.pageName,
      item.param !== undefined ? item.param : (item.tab >= 0 ? item.tab : null));
  }

  // 结果项卡片（2026-11-04 蒙层合规笔：整卡自绘，§4.19 范式——卡底 + padding 4 + 透明 Button
  // 蒙层，四缘各 4vp；卡高 72 = 4×2 + 64，内容内距 12 + 外层 4 = 原官方卡内距 16）：
  // 两行 = 标题 primary + 面包屑 secondary；卡宽 CARD_PANEL_WIDTH 与历史区/搜索框三线对齐
  @Builder
  ResultCard(item: SettingSearchItem) {
    Column() {
      Button() {
        Row({ space: 8 }) {
          Column({ space: 0 }) {
            Text(item.title)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(item.path)
              .fontSize(14)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(20)
            .fontColor([cardDescColor()])
            .flexShrink(0)
        }
        .width('100%')
        .height('100%')
      }
      .type(ButtonType.Normal)
      .width('100%')
      .height(64)
      .padding({ left: 12, right: 12 })
      .backgroundColor(Color.Transparent)
      .borderRadius(CARD_RADIUS)
      .onClick((): void => {
        this.openItem(item);
      })
    }
    .width(CARD_PANEL_WIDTH)
    .height(72)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  // 空态提示（无结果 / 首次进入引导共用）：官方放大镜符号 + 主/副文案垂直居中；符号与副
  // 文案用 font_secondary 弱化，主文案 font_primary 深浅色自动反色
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

  // 搜索框本体（嵌标题栏覆盖层）：defaultFocus(true) 进页自动获焦 + 拉起输入法
  //（enableKeyboardOnFocus 默认 true 勿多写）；searchButton 框尾「搜索」钮（点击同时触发
  // onSubmit，d.ts 核实）；键盘搜索键 = EnterKeyType.Search（默认值，无需显式设）；$$ 双向
  // 绑定：历史词条点击回填搜索框。材质恒光感基准 THICK，随沉浸光感总档（「无」档显式
  // 关闭；2026-11-05 调薄笔自 ULTRA_THICK 回落一档，强档生效 REGULAR 与全族一致）。
  // 高度 40vp 与标题栏返回键（官方 40vp 圆钮）对齐；宽度 100% 由外层容器约束（标题栏覆盖
  // 层剩余宽度）
  @Builder
  SearchBox() {
    Search({ value: $$this.keyword, placeholder: '搜索设置项' })
      .searchButton('搜索')
      .defaultFocus(true)
      // 透明底勿删——Search 内容层默认底会遮 systemMaterial 背板（官方 FAQ），2033 撤兜底曾连带删此行致输入变白
      .backgroundColor(Color.Transparent)
      .systemMaterial(resolvedUiMaterial(uiMaterial.ImmersiveStyle.THICK,
        this.immersiveLevel, false))
      .width('100%')
      .height(40)
      .onChange((value: string) => {
        // 清空输入时退回历史区（结果区只在提交后出现）；非空修改不自动重搜——提交式搜索
        // 设计（onSubmit 才出结果，与搜索历史记录时机一致）
        if (value.trim() === '') {
          this.submitted = false;
          this.results = [];
        }
      })
      .onSubmit((value: string) => {
        this.doSearch(value);
      })
  }

  // 标题栏覆盖层（官方 stackBuilder，经 hdsTitleBarOptions 第 6 参）：搜索框与返回键横向
  // 并排。左侧留白 = 返回键避让：标题栏起始 padding 16 + 返回键 40 + 间隔 8 = 64vp（HDS
  // 几何真机量测值，见 dshinhm AGENTS.md「菜单弹窗定位约定」；右侧与菜单按钮同规格 16vp）；
  // 命中测试 Transparent——覆盖层整栏铺在返回键上方，空白区不拦截触摸
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

  // 内容区（搜索框在标题栏内不重复布局）：下方 = 历史/最近使用/结果三态 + 空态；键盘弹起
  // 盖住底部时可滚动查看
  @Builder
  PageContent() {
    Column() {
      Scroll() {
        Column({ space: CARD_SPACING }) {
          if (!this.submitted) {
            if (this.history.length > 0) {
              HistorySection({ onSearch: (term: string) => {
                this.doSearch(term)
              } })
            }
            if (this.displayableRecentCount() > 0) {
              // 板块间距：「最近使用」margin top 12 拉开层级——结果区卡片间距仍 CARD_SPACING
              RecentSection({ onOpen: (item: SettingSearchItem) => {
                this.openItem(item)
              } })
                .margin({ top: 12 })
            }
            // 首次进入（无历史、无最近使用）：用空态引导用户输入
            if (this.history.length === 0 && this.displayableRecentCount() === 0) {
              // ★ 示例词须有对应设置项——原「光感、材质」已无设置项，示例会指向零结果
              this.EmptyHint('输入关键词搜索设置项', '例如 字体、背景、模型')
            }
          } else if (this.results.length > 0) {
            ForEach(this.results, (item: SettingSearchItem) => {
              this.ResultCard(item)
            }, (item: SettingSearchItem) => item.title)
          } else {
            // 无匹配空态
            this.EmptyHint('未找到相关设置项', '换个关键词试试')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Start)
        .padding({ top: this.topPad, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      // 滚动内容不足视口时顶对齐（Scroll align 默认 Center 坑——同 InfoPage）
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  build() {
    // ★ 自包壳（见头注释）：根透明 + 页内铺底 + 标题栏 TITLE_S；搜索框经 stackBuilder 嵌
    // 标题栏（传入即主标题置空，hdsTitleBarOptions 内部处理）
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
  }
}
