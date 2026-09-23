// 「搜索记录区」区块组件（2026-08-29 M2c 自 dshinhm 同名文件随迁）：
// 本文件承载搜索页的两个记录区块——搜索历史区（HistorySection）+ 最近使用区（RecentSection）。
// 拆分规则：本文件只放「记录区展示」；搜索提交/结果区/搜索框/空态/路由跳转留在 SearchPage.ets
// （搜索主流程归页面）。数据流契约：
//   · HistorySection：@StorageLink(SEARCH_HISTORY_KEY) 自读自清（清空 = 直接调
//     clearSearchHistory 写 AppStorage 空数组；搜索词提交由 SearchPage.recordSearchHistory
//     写，AppStorage 响应式自动刷新本组件——双向同步零传参）；
//     词条点击 → props 回调 onSearch(term) 上抛（SearchPage.doSearch 执行搜索）；
//   · RecentSection：@StorageLink(RECENT_USE_KEY) 自读自清；展示经 findItemByTitle 按
//     title 反查（title 全注册表唯一；反查失败跳过——防持久化残留脏数据），图标映射
//     iconForPage 为本节私有逻辑随迁（aicontrol 无自定义 media 图标——用官方 sys.symbol
//     系统符号，resources.txt 实锤口径，与 SettingsPage 行卡 PrefixIcon 同姿势）；
//     卡片点击 → props 回调 onOpen(item) 上抛（SearchPage.openItem 记最近使用 + 路由 push）。
//   · 空态判定（首次进入引导）由 SearchPage 持 history/recent 长度判断（页面级状态编排），
//     本组件只负责「有数据时渲染」。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsListItemCard, PrefixIcon } from '@kit.UIDesignKit';
import {
  clearRecentUse,
  clearSearchHistory,
  findItemByTitle,
  MAX_RECENT_USE,
  MAX_SEARCH_HISTORY,
  RECENT_USE_KEY,
  SEARCH_HISTORY_KEY,
  SettingSearchItem
} from '../../common/SettingSearch';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';
import { ROUTE_APPEARANCE_PAGE, ROUTE_PROMPT_LIBRARY_PAGE, ROUTE_PROVIDER_PAGE } from '../../common/RouteNames';

// ── 搜索历史区：标题行（左「搜索历史」+ 右垃圾桶清空）+ 词条胶囊流式排列 ──
// 样式沿 dshinhm 定稿：标题 18vp 加粗 + 垃圾桶 sys.symbol.trash 24vp；胶囊背景 cardBg
@Component
export struct HistorySection {
  // 系统颜色模式（深浅色切换自动刷新胶囊/标题配色）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 搜索历史（AppStorage 持久化；清空直接写 AppStorage，自动刷新）
  @StorageLink(SEARCH_HISTORY_KEY) history: string[] = [];
  // 词条点击回调（SearchPage.doSearch；只上报，本组件不内嵌搜索逻辑）
  onSearch: (term: string) => void = (term: string) => {
  };

  build() {
    Column() {
      Row() {
        Text('搜索历史')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
          .onClick(() => {
            clearSearchHistory();
          })
      }
      .width(CARD_PANEL_WIDTH)
      .margin({ bottom: 12 })

      Flex({ wrap: FlexWrap.Wrap }) {
        // 展示侧截断：@StorageLink 直读 AppStorage、不经 getSearchHistory——上限调整后旧
        // 持久化残留只在本次 slice 后消失（升级后首屏即 ≤5 条）；
        // keyGenerator 用词条自身（历史去重后互异，键稳定避免 unshift 重排时 ForEach 全量重建）
        ForEach(this.history.slice(0, MAX_SEARCH_HISTORY), (term: string) => {
          Text(term)
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(cardBg(this.appColorMode))
            .borderRadius(14)
            // 超长词条视觉省略：存储侧已在 SettingSearch 截断 MAX_SEARCH_TERM_LENGTH 字，
            // 展示侧再限宽 + 单行省略号双保险（dshinhm 定稿；160vp ≈ 11 个中文 14fp 字）
            .constraintSize({ maxWidth: 160 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ right: 8, bottom: 8 })
            .onClick(() => {
              this.onSearch(term);
            })
        }, (term: string) => term)
      }
      .width(CARD_PANEL_WIDTH)
    }
    .width('100%')
  }
}

// ── 最近使用区：标题行（左「最近使用」+ 右 X 清空）+ 最近打开项卡片列表 ──
// 卡片 = 官方 HdsListItemCard（PrefixIcon 符号前缀 + 两行文本）；回退路径自制卡片
//（符号 + 标题/面包屑）——样式与 SearchPage 结果卡/设置页行卡同构
@Component
export struct RecentSection {
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink(RECENT_USE_KEY) recent: string[] = [];
  // 卡片点击回调（SearchPage.openItem：记最近使用 + 路由 push）
  onOpen: (item: SettingSearchItem) => void = (item: SettingSearchItem) => {
  };
  // 官方 HDS 列表项卡片可用性（HDSComponent.Full，与结果卡/设置页行卡同一能力位）
  private hdsListCardAvailable: boolean = canIUse('SystemCapability.UIDesign.HDSComponent.Full');

  // 最近使用条目反查（title 数组 → 完整条目数组；@Builder 内不允许声明变量，反查集中
  // 到这里；注册表已有的 title 才展示，防持久化残留脏数据）。
  // 展示侧截断（同 HistorySection 姿势）：@StorageLink 直读 AppStorage、不经 getRecentUse
  private recentItems(): SettingSearchItem[] {
    const items: SettingSearchItem[] = [];
    const limit: number = Math.min(this.recent.length, MAX_RECENT_USE);
    for (let i = 0; i < limit; i++) {
      const item: SettingSearchItem | undefined = findItemByTitle(this.recent[i]);
      if (item !== undefined) {
        items.push(item);
      }
    }
    return items;
  }

  // 最近使用项图标映射（目标页 → 官方系统符号；resources.txt 实锤——坑72 口径）：
  // 外观显示 → paintpalette / 服务商管理 → link（与设置页行卡同符号）/ 提示词 → textformat
  // （与设置页行卡同符号）/ 其余（更多信息）→ doc_text。路由名比较引用 RouteNames 常量
  // ——禁止裸字符串，同注册表 pageName 约定
  private iconForPage(pageName: string): Resource {
    if (pageName === ROUTE_APPEARANCE_PAGE) {
      return $r('sys.symbol.paintpalette');
    }
    if (pageName === ROUTE_PROVIDER_PAGE) {
      return $r('sys.symbol.link');
    }
    if (pageName === ROUTE_PROMPT_LIBRARY_PAGE) {
      return $r('sys.symbol.textformat');
    }
    return $r('sys.symbol.doc_text');
  }

  // 最近使用卡片：官方 HdsListItemCard（宽度姿势同结果卡片——不设 width，实际 =
  // CARD_PANEL_WIDTH）；回退自制卡片（符号 + 标题/面包屑，无箭头——轮 9 行卡定稿口径）
  @Builder
  RecentCard(item: SettingSearchItem) {
    if (this.hdsListCardAvailable) {
      HdsListItemCard({
        prefixItem: new PrefixIcon({ iconValue: { symbol: this.iconForPage(item.pageName) } }),
        textItem: {
          primaryText: { text: item.title },
          secondaryText: { text: item.path }
        },
        cardBorderRadius: 16,
        onClick: () => {
          this.onOpen(item);
        }
      })
    } else {
      // 回退自制卡（Button(Normal) 包裹 = 官方原生按压蒙层，2026-09-12 UI 同形异构归一
      // 笔 1——与 HDS 分支官方卡按压反馈对齐）
      Button() {
        Row({ space: 14 }) {
          SymbolGlyph(this.iconForPage(item.pageName))
            .fontSize(20)
            .fontColor([cardTitleColor()])
          Column({ space: 4 }) {
            Text(item.title)
              .fontSize(16)
              .fontColor($r('sys.color.font_primary'))
            Text(item.path)
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding(16)
      }
      .type(ButtonType.Normal)
      .width(CARD_PANEL_WIDTH)
      .borderRadius(16)
      .backgroundColor(cardBg(this.appColorMode))
      .onClick(() => {
        this.onOpen(item);
      })
    }
  }

  build() {
    Column() {
      Row() {
        Text('最近使用')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
          .onClick(() => {
            clearRecentUse();
          })
      }
      .width(CARD_PANEL_WIDTH)
      .margin({ bottom: 12 })

      // 卡片列表：内层 Column space = CARD_SPACING（10vp，列表卡片规范）——外层 Column
      // 无 space（标题行与卡片区间距走标题行 margin bottom 12），ForEach 直挂外层会让
      // 多张卡片 0 间距紧贴（dshinhm 真机发现修复，姿势随迁）
      Column({ space: CARD_SPACING }) {
        ForEach(this.recentItems(), (item: SettingSearchItem) => {
          this.RecentCard(item)
        }, (item: SettingSearchItem) => item.title)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
  }
}
