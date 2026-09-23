// 「帮助中心」页（2026-09-05 新增；「更多信息」页行卡进入——决明需求「设置页增加帮助
// 中心，放更多信息页，帮助中心页分板块/卡片说明目前应用的功能与用法，语言面向用户」）。
// 版式随 OpenSourcePage 定稿：总览卡（2026-09-05 决明指令「顶部提示改单独卡片命名总览」
// ——卡外标题 + 大卡单段正文，面向大众描述应用作用） + 分组块（分组标题在卡外左上 +
// 一张大卡，条目两行式 = 功能名 + 一句话短描述，条间官方 Divider）。
// ★ 二级页化（2026-09-05 同日决明指令「卡片描述改简短，点击卡片进二级页看详细用法」）：
//   条目卡可点击，push HelpTopicPage（param = 条目 id），详细用法在详情页展示——
//   帮助内容单源在 common/HelpContent.ets（desc 一句话 / detail 详细段落），增删条目
//   只动该文件（2026-09-05 下沉 common 层：设置搜索注册表程序化生成帮助条目，须同层
//   导入避开「common 不反向 import components」红线；帮助条目已接入设置搜索，生成函数
//   buildHelpSearchItems 在 common/SettingSearch.ets，本页与详情页均不受影响）。
// ★ 询问控制台助手卡（2026-09-05 控制台助手）：总览卡后单卡入口，点击经 CONSOLE_ASK_CMD_KEY
//   下发 HomeNavigation 切内置控制台助手并进新会话（编排与防循环理由见键常量注释）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  CARD_PANEL_WIDTH,
  cardBg,
  cardBorderColor,
  cardDescColor
} from '../../common/Theme';
import { SETTING_TITLE_HELP_CENTER } from '../../common/SettingSearch';
import { ROUTE_HELP_TOPIC_PAGE } from '../../common/RouteNames';
import { PageShell } from '../../common/PageShell';
import { HELP_GROUPS, HelpGroup, HelpItem } from '../../common/HelpContent';

// 「询问控制台助手」指令键（AppStorage 一次性计数器——坑3 口径：本页〔设置域二级页〕无法
// 直达 HomeNavigation 路由方法，+1 下发；HomeNavigation @StorageProp @Watch 消费 = 切当前
// 助手为内置控制台助手 + 懒创建新会话 push〔ChatPage 盖全导航，问完 pop 回本页〕。常量
// 定义在本页〔触发方〕、HomeNavigation 引——ASSISTANT_CREATE_CMD_KEY 同构反向，防
// HomeNavigation→PageMapBuilder→本页→HomeNavigation 循环 import）
export const CONSOLE_ASK_CMD_KEY: string = 'consoleAskCmd';

@Component
export struct HelpCenterPage {
  // 顶部留白（vp，PageShell 内容位自处理——同 OpenSourcePage：首个控件静止时完整落在
  // 渐变模糊蒙层下方）。创建后不变，普通成员（状态最小化）
  topPad: number = 0;
  // 路由栈（PageMap 传入，与根 Navigation 同一引用）：条目卡点击 pushPathByName 进
  // 帮助条目详情页（2026-09-05 二级页化起传入）
  pathStack: NavPathStack = new NavPathStack();
  // 系统颜色模式（EntryAbility 写入 AppStorage，深浅色切换自动刷新卡片背景/分割线配色）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  // 分组大卡（自制分组卡：OpenSourcePage 先例——cardBg 圆角 16，条目两行式（功能名
  // 15sp 主色 + 一句话短描述 13sp 次要色，右侧 chevron 指示可点进详情），条间官方
  // Divider 左右各缩进 16vp）
  @Builder
  GroupCard(group: HelpGroup) {
    Column() {
      ForEach(group.items, (item: HelpItem) => {
        // 条目行 Button(Normal) 包裹 = 官方原生按压蒙层（2026-09-12 UI 同形异构归一笔 1；
        // 卡内行语境照 GroupSettingCard.EntryRow 形制 = 透明底 + 圆角 16，卡底仍在分组卡体）
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
            // 可点进详情的视觉指示（AboutPageCards 跳转卡同款形制）
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
        // 蒙层圆角与卡体同值 16（两处同改铁律）
        .borderRadius(16)
        .padding({ left: 16, right: 16, top: 13, bottom: 13 })
        // 进详情页（param = 条目 id「分组标题::条目标题」，HelpContent.findHelpTopic 还原）
        .onClick(() => {
          this.pathStack.pushPathByName(ROUTE_HELP_TOPIC_PAGE, group.title + '::' + item.title);
        })
        Divider()
          .color(cardBorderColor(this.appColorMode))
          // 分割线不延伸至卡片两端：左右各缩进 16vp（同 OpenSourcePage）
          .padding({ left: 16, right: 16 })
      }, (item: HelpItem) => item.title)
    }
    .width(CARD_PANEL_WIDTH)
    .borderRadius(16)
    .backgroundColor(cardBg(this.appColorMode))
    .clip(true)
    // 组间距 = 卡片块自身 margin（分组块属大区块非卡片间距，16vp 不进 CARD_SPACING）
    .margin({ bottom: 16 })
  }

  // 询问控制台助手卡（2026-09-05 控制台助手入口——总览卡后单卡：帮助场景没找到答案时
  // 直接问；形制 = 分组条目同款两行式 + 图标 + chevron，questionmark_circle 符号表实锤；
  // 点击经 CONSOLE_ASK_CMD_KEY 指令键下发 HomeNavigation 编排）
  @Builder
  AskConsoleCard() {
    // Button(Normal) 包裹 = 官方原生按压蒙层（2026-09-12 UI 同形异构归一笔 1，独立卡
    // 形制——卡底随卡体搬 Button，与分组条目行的卡内行形制区分）
    Button() {
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.questionmark_circle'))
          .fontSize(20)
          .fontColor([cardDescColor()])
        Column({ space: 4 }) {
          Text('询问控制台助手')
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
          Text('进入控制台助手会话，直接提问应用用法')
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
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .margin({ bottom: 16 })
    .onClick(() => {
      AppStorage.setOrCreate<number>(CONSOLE_ASK_CMD_KEY,
        (AppStorage.get<number>(CONSOLE_ASK_CMD_KEY) ?? 0) + 1);
    })
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
          // ── 总览卡（2026-09-05 决明指令「顶部提示改单独卡片命名总览」——版式随分组块
          // 标题卡外 + 大卡；文案面向大众描述应用作用）──
          Text('总览')
            .width(CARD_PANEL_WIDTH)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .margin({ bottom: 8 })
          Column({ space: 4 }) {
            Text('AI 控制台是一款连接多家 AI 服务的聊天助手，配置好密钥即可开始提问，获得写作、翻译、编程等日常帮助。聊天记录只保存在手机本地，密钥加密存放，请放心使用。以下按板块列出各项功能，点卡片可查看详细用法。')
              .fontSize(13)
              .lineHeight(19)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }
          .width(CARD_PANEL_WIDTH)
          .padding(16)
          .backgroundColor(cardBg(this.appColorMode))
          .borderRadius(16)
          .alignItems(HorizontalAlign.Start)
          .margin({ bottom: 16 })

          // ── 询问控制台助手（2026-09-05 控制台助手入口——总览卡后单卡）──
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
