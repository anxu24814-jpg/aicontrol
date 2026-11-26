// 「AI 辅助开发声明」二级页（「关于」页卡片进入）：两个分组（AI / Agent 工具），**分组标题
// 在卡外左上**（官方设置列表姿势，PermissionPage 先例：CARD_PANEL_WIDTH 左对齐 + 16 Medium
// font_primary + 与卡间距 8vp），标题下为一张大卡（条目 + 官方 Divider 分割线——HDS 无分组
// 卡组件，用官方组件拼装：InfoPage 分组卡先例，cardBg 圆角 CARD_RADIUS、无轮廓线〔官方
// HdsListItemCard 无描边，自制卡一致〕；分割线左右各缩进 16vp、不延伸至卡片两端）；卡片
// 宽度 = CARD_PANEL_WIDTH（官方 HdsListItemCard 的 width() 实际不生效、渲染宽 = 容器
// 100%−32vp，挂 CARD_WIDTH 86% 会窄于官方卡——依据见 Theme.ets CARD_PANEL_WIDTH 注释）；
// 组间距 16vp（区块间距非卡片间距，不走 CARD_SPACING）。
// ★ 名单数据 = 下方 AI_CREDIT_GROUPS 常量（后续改名单只动该常量）。名单排版同 dshinhm
//   AiAssistPage 定稿（模型名/工具名按官方写法与品牌名规范化）；本页比 dshinhm 多
//   DeepSeek V4.1 Flash / GLM 5.3 Flash / GPT 6 Astra 三条（决明追补，旧项目未同步）；
//   2026-11-24 决明再追补 DeepSeek V4.1 Flash 1017 / GLM 5.4 / Kimi K3.1 Pro 三条。
//   条目按品牌归组（Kimi → DeepSeek → GLM → GPT），追补条排同品牌组末位。
//   名单内容与序由 scripts/assert-app-domain.mjs 135 组两钉守（逐字 + 品牌词形大小写）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  CARD_PANEL_WIDTH,
  cardBg,
  cardBorderColor, CARD_RADIUS
} from '../common/Theme';
import { SETTING_TITLE_AI_ASSIST } from '../common/SettingSearch';
import { PageShell } from '../common/PageShell';
import { InfoCard } from './InfoCard';

// 分组条目（卡外左上标题 + 卡片条目清单，条间官方 Divider）
interface AiCreditGroup {
  // 分组标题（卡片左上方，如「AI」「Agent 工具」）
  title: string;
  // 条目（模型/工具名称；纯展示一条一行）
  items: string[];
}

const AI_CREDIT_GROUPS: AiCreditGroup[] = [
  {
    title: 'AI',
    items: [
      'Kimi K3',
      'Kimi K3.1 Pro',
      'DeepSeek V4 Flash',
      'DeepSeek V4 Flash Vision Exp',
      'DeepSeek V4 Pro',
      'DeepSeek V4.1 Flash',
      'DeepSeek V4.1 Flash 1017',
      'GLM 5.3',
      'GLM 5.3 Flash',
      'GLM 5.4',
      'GPT 6 Astra'
    ]
  },
  {
    title: 'Agent 工具',
    items: [
      'Z Code',
      'Kimi Code',
      'DeepSeek Harness'
    ]
  }
];

@Component
export struct AiAssistPage {
  // 顶部留白（vp，HomeNavigation PageMap 传入）：同其它二级页（首个控件静止时完整落在
  // 渐变模糊蒙层下方；回退路径传 0）。创建后不变，用普通成员（状态最小化）
  topPad: number = 0;
  // 系统颜色模式（EntryAbility 写入 AppStorage，深浅色切换自动刷新配色；卡片背景/分割线用）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  // 分组大卡（自制分组卡，InfoPage 分组卡先例——cardBg 圆角 CARD_RADIUS，视觉与 HDS 列表卡
  // 同规格）：无轮廓线（官方 HdsListItemCard 无描边，自制卡一致）；分割线两侧各 16vp（左沿
  // 对齐条目文字，官方设置列表惯例，不延伸至卡片两端），末条后不留（「条间线」语义）；
  // 条目纯展示无点击。宽度用 CARD_PANEL_WIDTH 而非 CARD_WIDTH：自制卡 width 会生效，挂
  // CARD_WIDTH(86%) 会比官方卡窄（真机反馈不一致，依据见 Theme.ets 注释）
  @Builder
  GroupCard(group: AiCreditGroup) {
    Column() {
      ForEach(group.items, (name: string, index: number) => {
        Text(name)
          .fontSize(15)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 13, bottom: 13 })
        // 末条后不留分割线（「条间线」语义）
        if (index < group.items.length - 1) {
          Divider()
            .color(cardBorderColor(this.appColorMode))
            .padding({ left: 16, right: 16 })
        }
      }, (name: string) => name)
    }
    .width(CARD_PANEL_WIDTH)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .clip(true)
    // 组间距 = 卡片块自身 margin（@Builder 返回值 void 不能链——margin 挂卡容器上；
    // 分组块属大区块非卡片间距，组间距 16vp 不进 CARD_SPACING 规范）
    .margin({ bottom: 16 })
  }

  // 分组（卡外左上标题 + 卡片；标题宽度 CARD_PANEL_WIDTH 与卡片左沿对齐——PermissionPage
  // 先例；标题与卡片间距 8vp；组间距 = GroupCard 内 margin bottom 16，分组块属「大区块」
  // 非卡片，不走 CARD_SPACING）
  @Builder
  GroupBlock(group: AiCreditGroup) {
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
    // 会塌陷——同 AboutPage 坑）
    Column() {
      Scroll() {
        Column() {
          // 声明说明段（通用措辞，InfoCard 单源件）
          InfoCard({ text: '本应用的部分开发工作由 AI 辅助完成。以下为参与开发的 AI 模型与 Agent 工具。' })
            .margin({ bottom: 16 })

          // 分组列（组间间距由 GroupBlock 内 margin 16 管理——外层再挂 space 会与 margin 双计）
          ForEach(AI_CREDIT_GROUPS, (group: AiCreditGroup) => {
            this.GroupBlock(group)
          }, (group: AiCreditGroup) => group.title)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        // 顶部留白 topPad（规范同 AboutPage：首元素静止时完整落在渐变模糊蒙层下方）
        .padding({ top: this.topPad, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      // 滚动内容不足视口时顶对齐（Scroll align 默认 Center——同 AboutPage）
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
      title: SETTING_TITLE_AI_ASSIST,
      content: () => {
        this.Content()
      }
    })
  }
}
