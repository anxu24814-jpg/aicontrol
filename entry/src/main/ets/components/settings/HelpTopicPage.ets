// 「帮助条目详情」页：帮助中心页条目卡点击进入，单页承载全部条目（push param = 条目 id
// 「分组标题::条目标题」，页面内 getParamByName 取参，MemoryLibraryPage 同款姿势）。
// 内容经 common/HelpContent.findHelpTopic 还原——帮助内容单源在 common/HelpContent.ets，
// 增删条目只动该文件。
// 版式 = 单张正文卡（决明拍板：正文包进卡片避免标点换行问题；cardBg + CARD_RADIUS + 内边距 16，
// 段落流无标题——页面标题栏已承载），滚动跟随 PageShell。
// 返回无参 pop（无数据变化，不挂 onPop——坑17 口径）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_HELP_TOPIC_PAGE } from '../../common/RouteNames';
import { findHelpTopic } from '../../common/HelpContent';
import { CARD_PANEL_WIDTH, cardBg, cardDescColor, CARD_RADIUS } from '../../common/Theme';

@Component
export struct HelpTopicPage {
  // 顶部留白（vp，PageMap 传入；首个控件须落在渐变模糊蒙层下方）。创建后不变，普通成员（状态最小化）
  topPad: number = 0;
  // 路由栈（PageMap 传入，与根 Navigation 同一引用）：仅用于 aboutToAppear 读 push 参数
  pathStack: NavPathStack = new NavPathStack();
  // 系统颜色模式（EntryAbility 写入 AppStorage，深浅色切换自动刷新兜底文案配色）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 标题栏标题 + 正文段落（aboutToAppear 一次性定值，创建后不变——普通成员非状态。
  // 参数异常时标题兜底「帮助」+ 段落留空走防御提示）
  private pageTitle: string = '帮助';
  private paragraphs: string[] = [];

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
    }
  }

  @Builder
  Content() {
    // 内容区用 Column 占满（NavDestination 内容区非 Flex 容器，Scroll 直接挂 layoutWeight 会塌陷）；
    // Scroll 内必须套 width('100%') + 居中的包裹 Column——CARD_PANEL_WIDTH = calc(100% - 32vp)
    // 靠外层居中才两侧各留 16vp（真机实锤：内容直挂 Scroll + TopStart 会贴左屏）
    Column() {
      Scroll() {
        Column() {
          if (this.paragraphs.length > 0) {
            // 正文卡（与帮助中心列表页卡片同构；无卡片时墨迹右端无边界锚定、观感右侧留白大）
            Column({ space: 10 }) {
              ForEach(this.paragraphs, (para: string, idx: number) => {
                Text(para)
                  // 正文字号 15/24（区别于卡片区副行的 13/19，层级差保持）
                  .fontSize(15)
                  .lineHeight(24)
                  // 正文黑字 font_primary（区别于列表页副行的次要灰）
                  .fontColor($r('sys.color.font_primary'))
                  .width('100%')
              }, (para: string, idx: number) => idx.toString())
            }
            .width(CARD_PANEL_WIDTH)
            .padding(16)
            .backgroundColor(cardBg(this.appColorMode))
            .borderRadius(CARD_RADIUS)
            .clip(true)
            .alignItems(HorizontalAlign.Start)
          } else {
            // 参数异常兜底（结构性防御——正常链路不会命中）
            Text('未找到该条目的说明内容。')
              .fontSize(14)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        // 顶部留白 topPad（同 OpenSourcePage）
        .padding({ top: this.topPad, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      // 滚动内容不足视口时顶对齐（Scroll align 默认 Center）+ 官方边缘回弹
      //（坑76：短内容页须显式 alwaysEnabled）
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
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
