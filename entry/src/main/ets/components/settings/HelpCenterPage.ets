// 「帮助中心」页（决明需求：设置页增加帮助中心，放更多信息页，按板块/卡片说明功能与用法，语言面向用户；
// 「更多信息」页行卡进入）。版式随 OpenSourcePage：总览卡（卡外标题 + 大卡单段正文）+ 分组块（分组标题卡外
// 左上 + 一张大卡，条目两行式 = 功能名 + 一句话短描述，条间官方 Divider）。
// ★ 二级页化（决明指令「卡片描述改简短，点击卡片进二级页看详细用法」）：条目卡可点击，push HelpTopicPage
//  （param = 条目 id），详细用法在详情页展示。帮助内容三方单源 = common/HelpContent.ets（desc 一句话 /
//  detail 详细段落）；增删条目只动该文件（下沉 common 层：设置搜索注册表程序化生成帮助条目须同层导入，
//  避开「common 不反向 import components」红线；生成函数 buildHelpSearchItems 在 common/SettingSearch.ets）。
// ★ 询问助手卡：总览卡后单卡入口，点击经 CONSOLE_ASK_CMD_KEY 下发 HomeNavigation 懒创建新会话，归属走
//  当前助手 ?? 默认助手兜底。
// ★ 帮助条目写作规范本体 = common/HelpContent.ets 头注释（增删条目前先读该节）
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  CARD_PANEL_WIDTH,
  cardBg,
  cardBorderColor,
  cardDescColor, CARD_RADIUS
} from '../../common/Theme';
import { SETTING_TITLE_HELP_CENTER } from '../../common/SettingSearch';
import { ROUTE_HELP_TOPIC_PAGE } from '../../common/RouteNames';
import { PageShell } from '../../common/PageShell';
import { HELP_GROUPS, HelpGroup, HelpItem } from '../../common/HelpContent';

// 「询问助手」指令键（AppStorage 一次性计数器——坑3：本页无法直达 HomeNavigation 路由方法，+1 下发；
// HomeNavigation @StorageProp @Watch 消费 = 懒创建新会话 push。常量定义在本页〔触发方〕、HomeNavigation 引——
// ASSISTANT_CREATE_CMD_KEY 同构反向，防 HomeNavigation→PageMapBuilder→本页→HomeNavigation 循环 import）
export const CONSOLE_ASK_CMD_KEY: string = 'consoleAskCmd';

@Component
export struct HelpCenterPage {
  // 顶部留白（vp，首个控件静止时完整落在渐变模糊蒙层下方）；创建后不变，普通成员
  topPad: number = 0;
  // 路由栈（PageMap 传入，与根 Navigation 同一引用）：条目卡点击 pushPathByName 进详情页
  pathStack: NavPathStack = new NavPathStack();
  // 系统颜色模式（EntryAbility 写入 AppStorage，深浅色切换自动刷新卡片背景/分割线配色）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  // 分组大卡（OpenSourcePage 先例——cardBg 圆角 CARD_RADIUS，条目两行式 + 右侧 chevron，条间官方 Divider
  // 左右各缩进 16vp）。★ 按压蒙层形制 = 组卡范式（规范-列表卡片与组卡 §4.19，2026-11-03 蒙层合规笔
  // 改判）：卡底上下 pad 4 + 行外包容器左右 padding 4 → 蒙层距卡外圈四周各 4vp；内容 padding 扣 4
  // 回添（16→12、13→9）距卡缘视觉零位移；蒙层圆角 = 卡圆角 CARD_RADIUS（§5 红线 2 整卡面族现行
  // 口径，同心式推广须另立笔）；行缩进禁 margin 写法（§5 红线 1，真机实锤蒙层不缩进）
  @Builder
  GroupCard(group: HelpGroup) {
    Column() {
      ForEach(group.items, (item: HelpItem, index: number) => {
        // 行左右缩 4 由外包容器 padding 承担（GroupSettingCard.EntryRow 同款）——蒙层 = 卡宽 −8vp
        // 悬浮条，四周均匀露白 4vp
        Column() {
          // 条目行 Button(Normal) 包裹 = 官方原生按压蒙层；透明底 + 圆角 CARD_RADIUS
          Button() {
            Row() {
              Column({ space: 4 }) {
                Text(item.title)
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                Text(item.desc)
                  .fontSize(13)
                  .lineHeight(19)
                  .fontColor($r('sys.color.font_secondary'))
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(16)
                .fontColor([cardDescColor()])
                .margin({ left: 8 })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .type(ButtonType.Normal)
          .width('100%')
          .backgroundColor(Color.Transparent)
          // 蒙层圆角与卡体同值 CARD_RADIUS（20）（两处同改铁律）
          .borderRadius(CARD_RADIUS)
          // 内容 padding 扣 4 回添（16→12、13→9）——外包缩进 4 + 卡底 pad 4，内容距卡缘零位移
          .padding({ left: 12, right: 12, top: 9, bottom: 9 })
          // 进详情页（param = 条目 id「分组标题::条目标题」，HelpContent.findHelpTopic 还原）
          .onClick(() => {
            this.pathStack.pushPathByName(ROUTE_HELP_TOPIC_PAGE, group.title + '::' + item.title);
          })
        }
        .width('100%')
        .padding({ left: 4, right: 4 })
        // 条间官方 Divider，末行不显（组卡单源 GroupSettingCard 同款；卡底补 pad 4 后贴边线会裸露）
        if (index < group.items.length - 1) {
          Divider()
            .color(cardBorderColor(this.appColorMode))
            // 分割线不延伸至卡片两端：左右各缩进 16vp（同 OpenSourcePage）
            .padding({ left: 16, right: 16 })
        }
      }, (item: HelpItem) => item.title)
    }
    .width(CARD_PANEL_WIDTH)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .clip(true)
    // 卡上下 pad 4（组卡口径——蒙层上缘距卡顶 4vp，与设置页组卡同观感）
    .padding({ top: 4, bottom: 4 })
    // 组间距 = 卡片块自身 margin（分组块属大区块非卡片间距，16vp 不进 CARD_SPACING）
    .margin({ bottom: 16 })
  }

  // 询问助手卡（帮助场景没找到答案时直接开一条新会话问；形制 = 分组条目同款两行式 + 图标 + chevron，
  // 点击经 CONSOLE_ASK_CMD_KEY 指令键下发 HomeNavigation 编排）
  @Builder
  AskConsoleCard() {
    // Button(Normal) 包裹 = 官方原生按压蒙层（独立卡形制——卡底随卡体搬 Button，与分组条目行的卡内行区分）；
    // 卡底 Column + 四周 padding 4 让蒙层距卡外圈 4vp，壳 padding 16→12 回添，几何零位移；margin 随迁卡底
    Column() {
      Button() {
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.questionmark_circle'))
            .fontSize(20)
            .fontColor([cardDescColor()])
          Column({ space: 4 }) {
            Text('询问助手')
              .fontSize(15)
              .fontColor($r('sys.color.font_primary'))
            Text('开一条新会话，直接提问应用用法')
              .fontSize(13)
              .lineHeight(19)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([cardDescColor()])
            .margin({ left: 8 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .type(ButtonType.Normal)
      .width('100%')
      .padding(12)
      .backgroundColor(Color.Transparent)
      .borderRadius(CARD_RADIUS)
      .onClick(() => {
        AppStorage.setOrCreate<number>(CONSOLE_ASK_CMD_KEY,
          (AppStorage.get<number>(CONSOLE_ASK_CMD_KEY) ?? 0) + 1);
      })
    }
    .width(CARD_PANEL_WIDTH)
    .padding(4)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .margin({ bottom: 16 })
  }

  // 分组（卡外左上标题 + 卡片；标题宽度与卡片左沿对齐——同 OpenSourcePage）
  @Builder
  GroupBlock(group: HelpGroup) {
    Text(group.title)
      .width(CARD_PANEL_WIDTH)
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_primary'))
      .margin({ bottom: 8 })
    this.GroupCard(group)
  }

  @Builder
  Content() {
    // 内容区用 Column 占满（NavDestination 内容区非 Flex 容器，Scroll 直接挂 layoutWeight
    // 会塌陷——OpenSourcePage 同款坑）
    Column() {
      Scroll() {
        Column() {
        // 总览卡（卡外标题 + 大卡；文案面向大众描述应用作用）
        Text('总览')
            .width(CARD_PANEL_WIDTH)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .margin({ bottom: 8 })
          Column({ space: 4 }) {
            Text('AI 控制台连接多家 AI 服务，配置好密钥即可开始提问，获得写作、翻译、编程等日常帮助。聊天记录只保存在本机，密钥加密存放。以下按板块列出各项功能，点卡片可查看详细用法。')
              .fontSize(13)
              .lineHeight(19)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }
          .width(CARD_PANEL_WIDTH)
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(CARD_RADIUS)
          .alignItems(HorizontalAlign.Start)
          .margin({ bottom: 16 })

          this.AskConsoleCard()

          ForEach(HELP_GROUPS, (group: HelpGroup) => {
            this.GroupBlock(group)
          }, (group: HelpGroup) => group.title)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        // 顶部留白 topPad（同 OpenSourcePage：首元素完整落在渐变模糊蒙层下方）
        .padding({ top: this.topPad, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      // 滚动内容不足视口时顶对齐（Scroll align 默认 Center）+ 官方边缘回弹
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  build() {
    // 页面骨架统一由 PageShell 提供（背景层/透明背景/标题栏/HDS 回退双分支）
    PageShell({
      title: SETTING_TITLE_HELP_CENTER,
      content: () => {
        this.Content()
      }
    })
  }
}
