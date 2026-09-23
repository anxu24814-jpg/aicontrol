// 「帮助条目详情」页（2026-09-05 二级页化新增；帮助中心页条目卡点击进入——决明需求
// 「卡片标题仍是功能，描述改为一句话，点击卡片进二级页放详细、面向大众的使用方法」）。
// 单页承载全部条目（push param = 条目 id「分组标题::条目标题」，MemoryLibraryPage 同款
// 页面内 getParamByName 取参姿势），内容经 common/HelpContent.findHelpTopic 还原——
// 帮助内容单源在 common/HelpContent.ets（2026-09-05 下沉 common 层，理由见
// HelpCenterPage 头注释），增删条目只动该文件。
// 版式 = 帮助中心列表页卡片同构（2026-09-05 决明拍板「正文包进卡片避免标点换行问题」）：
// 单张正文卡（cardBg 圆角 16 内边距 16，段落流无标题——页面标题栏已承载），滚动跟随
// PageShell。★ 2026-09-06 起：正文卡下方可选「前往相关设置」跳转按钮（条目 route 字段
// 驱动——HelpContent 配了才显示，pushPathByName 直达对应设置页，页级直达跳页不跳卡，
// 决明拍板；光感四件套 + 内容区回退双态照 DataSyncPage.ActionBtn 一行单按钮同构，
// primary=true 官方强调蓝、官方默认高度/圆角不自绘）。
// 返回无参 pop（无数据变化，不挂 onPop——坑17 口径；目标页系统返回同样原路回本页，
// 跳转无数据回传）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_HELP_TOPIC_PAGE } from '../../common/RouteNames';
import { findHelpTopic } from '../../common/HelpContent';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor } from '../../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg,
  fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect } from '../../common/ImmersiveLevel';

@Component
export struct HelpTopicPage {
  // 顶部留白（vp，PageMap 传入——PageShell 内容位自处理，首个控件落在渐变模糊蒙层
  // 下方）。创建后不变，普通成员（状态最小化）
  topPad: number = 0;
  // 路由栈（PageMap 传入，与根 Navigation 同一引用）：仅用于 aboutToAppear 读 push 参数
  pathStack: NavPathStack = new NavPathStack();
  // 系统颜色模式（EntryAbility 写入 AppStorage，深浅色切换自动刷新兜底文案配色）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 光感档位与内容区回退开关（EntryAbility 写入 AppStorage，订阅式切换即刷——跳转
  // 按钮光感双态所需；DataSyncPage.ActionBtn 同款状态源，坑16 契约）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 标题栏标题 + 正文段落（aboutToAppear 一次性定值，创建后不变——普通成员非状态；
  // 参数异常时标题兜底「帮助」+ 段落留空给防御提示）
  private pageTitle: string = '帮助';
  private paragraphs: string[] = [];
  // 条目跳转目标（HelpItem.route；'' = 不跳不显键。aboutToAppear 一次性定值，
  // 创建后不变——普通成员非状态，状态最小化）
  private route: string = '';

  aboutToAppear(): void {
    const params: Array<string> =
      this.pathStack.getParamByName(ROUTE_HELP_TOPIC_PAGE) as Array<string>;
    // 同路由多实例时取最新一次 push（MemoryLibraryPage 同款口径）
    const param: string | undefined = params.length > 0 ? params[params.length - 1] : undefined;
    if (param === undefined || param === '') {
      return;
    }
    const topic = findHelpTopic(param);
    if (topic !== undefined) {
      this.pageTitle = topic.title;
      this.paragraphs = topic.detail;
      this.route = topic.route ?? '';
    }
  }

  @Builder
  Content() {
    // 内容区用 Column 占满（NavDestination 内容区非 Flex 容器，Scroll 直接挂 layoutWeight
    // 会塌陷——OpenSourcePage 同款坑）；Scroll 内必须套 width('100%') + 居中的包裹 Column——
    // CARD_PANEL_WIDTH = calc(100% - 32vp) 靠外层居中才两侧各留 16vp（2026-09-05 真机实锤：
    // 内容直挂 Scroll + TopStart 贴左屏，HelpCenterPage/PrivacyPolicyPage 同构包裹层先例）
    Column() {
      Scroll() {
        Column() {
          if (this.paragraphs.length > 0) {
            // 正文卡（2026-09-05 决明拍板「正文包进卡片，避免标点/换行问题，无需标题」——
            // 与帮助中心列表页卡片同构：cardBg 圆角 16 + 内边距 16，段落流无标题（页面标题
            // 栏已承载）。真机实测根因：无卡片时墨迹右端参差（满行 1133~1206）无边界锚定，
            // 观感右侧留白大；卡片化后与列表页观感一致）
            Column({ space: 10 }) {
              ForEach(this.paragraphs, (para: string, idx: number) => {
                Text(para)
                  // 正文字号 15/24（2026-09-05 决明指令「详情页字体太小，加大一点点」——
                  // 自 14/22 上调；卡片区副行 13/19 不变，层级差保持）
                  .fontSize(15)
                  .lineHeight(24)
                  // 正文黑字（2026-09-05 决明指令「详情文字用黑字」——font_primary，
                  // 区别于列表页副行的次要灰）
                  .fontColor($r('sys.color.font_primary'))
                  .width('100%')
              }, (para: string, idx: number) => idx.toString())
            }
            .width(CARD_PANEL_WIDTH)
            .padding(16)
            .backgroundColor(cardBg(this.appColorMode))
            .borderRadius(16)
            .clip(true)
            .alignItems(HorizontalAlign.Start)
          } else {
            // 参数异常兜底（结构性防御——正常链路不会命中）
            Text('未找到该条目的说明内容。')
              .fontSize(14)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
          }
          if (this.route !== '' && this.paragraphs.length > 0) {
            // 「前往相关设置」跳转键（2026-09-06）：条目配了 route 才显示——pushPathByName
            // 直达该设置页（页级直达跳页不跳卡，无参；SearchPage 结果跳页同构先例）。
            // 光感四件套 + 内容区回退双态照 DataSyncPage.ActionBtn 一行单按钮（primary=
            // true 官方强调蓝；官方默认高度/圆角不自绘；宽度对齐正文卡）。返回手势原路
            // 回本页——跳转无数据回传，不挂 onPop（坑17 口径）
            Button('前往相关设置')
              .width(CARD_PANEL_WIDTH)
              .fontColor(fallbackButtonFont(this.contentFallback, true))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .margin({ top: CARD_SPACING })
              .onClick((): void => {
                this.pathStack.pushPathByName(this.route, null);
              })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        // 顶部留白 topPad（同 OpenSourcePage：首元素完整落在渐变模糊蒙层下方）
        .padding({ top: this.topPad, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      // 滚动内容不足视口时顶对齐（Scroll align 默认 Center）+ 官方边缘回弹
      //（坑76：短内容页须显式 alwaysEnabled——「历史翻页」等单段条目才可拖拽回弹，
      //InfoPage 同款）
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    // 页面骨架统一由 PageShell 提供（背景层/透明背景/标题栏/HDS 回退双分支）
    PageShell({
      title: this.pageTitle,
      content: (): void => {
        this.Content()
      }
    })
  }
}
