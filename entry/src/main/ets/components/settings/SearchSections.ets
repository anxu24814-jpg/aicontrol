// 「搜索记录区」区块组件（自 dshinhm 同名文件随迁）：承载搜索页两个记录区块——搜索历史区（HistorySection）
// + 最近使用区（RecentSection）。本文件只放「记录区展示」；搜索提交/结果区/搜索框/空态/路由跳转留在
// SearchPage.ets。数据流契约：
//   · HistorySection：@StorageLink(SEARCH_HISTORY_KEY) 自读自清（清空 = clearSearchHistory 写 AppStorage
//     空数组；提交由 SearchPage.recordSearchHistory 写，响应式自动刷新——双向同步零传参）；词条点击经
//     onSearch(term) 上抛（SearchPage.doSearch 执行搜索）；
//   · RecentSection：@StorageLink(RECENT_USE_KEY) 自读自清；展示经 findItemByTitle 按 title 反查
//    （title 全注册表唯一；反查失败跳过——防持久化残留脏数据），图标用官方 sys.symbol 系统符号（坑72
//     口径，aicontrol 无自定义 media 图标）；卡片点击经 onOpen(item) 上抛（SearchPage.openItem 记最近使用 + 路由 push）。
//   · 空态判定由 SearchPage 持 history/recent 长度判断，本组件只负责「有数据时渲染」。
import { ConfigurationConstant } from '@kit.AbilityKit';
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
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, CARD_RADIUS } from '../../common/Theme';
import { ROUTE_PREF_BACKGROUND_PAGE, ROUTE_PREF_FONT_PAGE, ROUTE_PROMPT_LIBRARY_PAGE, ROUTE_PROVIDER_PAGE } from '../../common/RouteNames';

// 搜索历史区：标题行（左「搜索历史」+ 右垃圾桶清空）+ 词条胶囊流式排列（标题 18vp 加粗 + trash 24vp；
// 胶囊背景 cardBg）
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
        // 展示侧截断：直读 AppStorage 不经 getSearchHistory——上限调整后旧残留只在本次 slice 后消失；
        // key 用词条自身（历史去重后互异，键稳定避免 unshift 重排时 ForEach 全量重建）
        ForEach(this.history.slice(0, MAX_SEARCH_HISTORY), (term: string) => {
          Text(term)
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(cardBg(this.appColorMode))
            .borderRadius(14)
            // 超长词条视觉省略：存储侧已在 SettingSearch 截断，展示侧再限宽 + 单行省略双保险（160vp ≈
            // 11 个中文 14fp 字）
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

// 最近使用区：标题行（左「最近使用」+ 右 X 清空）+ 最近打开项卡片列表（卡片 = 整卡自绘：
// 前缀符号 + 两行文本 + 右箭头，蒙层四缘 4vp）
@Component
export struct RecentSection {
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink(RECENT_USE_KEY) recent: string[] = [];
  // 卡片点击回调（SearchPage.openItem：记最近使用 + 路由 push）
  onOpen: (item: SettingSearchItem) => void = (item: SettingSearchItem) => {
  };

  // 最近使用条目反查（@Builder 内不允许声明变量，反查集中到这里；title 在注册表才展示，防持久化残留脏
  // 数据；展示侧截断同 HistorySection 姿势——直读 AppStorage 不经 getRecentUse）
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

  // 最近使用项图标映射（目标页 → 官方系统符号，坑72 口径）：背景/字体两页 → paintpalette /
  // 服务商管理 → link / 提示词 → textformat / 其余 → doc_text。路由名比较引用 RouteNames 常量——禁裸字符串
  private iconForPage(pageName: string): Resource {
    if (pageName === ROUTE_PREF_BACKGROUND_PAGE || pageName === ROUTE_PREF_FONT_PAGE) {
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

  // 最近使用卡片（2026-11-04 蒙层合规笔：整卡自绘，§4.19 范式——卡底 + padding 4 + 透明
  // Button 蒙层，四缘各 4vp；卡高 72 = 4×2 + 64，内容内距 12 + 外层 4 = 原官方卡内距 16；
  // 前缀符号 24 + 间距 16 = 标题左缘卡内 52，与原官方卡排版同址）
  @Builder
  RecentCard(item: SettingSearchItem) {
    Column() {
      Button() {
        Row({ space: 16 }) {
          SymbolGlyph(this.iconForPage(item.pageName))
            .fontSize(24)
            .fontColor([$r('sys.color.font_primary')])
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
        this.onOpen(item);
      })
    }
    .width(CARD_PANEL_WIDTH)
    .height(72)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
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

      // 内层 Column space = CARD_SPACING——外层无 space，ForEach 直挂外层会让多张卡片 0 间距紧贴
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
