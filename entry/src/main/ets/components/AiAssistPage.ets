// 「AI 辅助开发声明」二级页（2026-08-23 二十二改新增；「关于」页卡片进入——决明需求
// 「关于页增加卡片，点击进二级页，列出参与开发的 AI」；二十三改版式定稿：两个分组
// （AI / Agent 工具），**分组标题在卡外左上**（官方设置列表姿势——PermissionPage
// 「允许"应用名"访问」先例：CARD_PANEL_WIDTH 左对齐 + 16 Medium font_primary + 与卡间距
// 8vp（二十四改：12vp 决明反馈过大）），标题下为一张大卡（条目 + 官方 Divider 分割线
// ——HDS 无分组卡组件，用官方组件拼装：InfoPage 分组卡先例，cardBg 圆角 16，无轮廓线
// （二十五改：官方 HdsListItemCard 无描边，自制卡一致——此前挂 border 1px 轮廓线与官方
// 不一致）；分割线左右各缩进 16vp（二十五改：不延伸至卡片两端，左沿对齐条目文字））；
// 卡片宽度 = CARD_PANEL_WIDTH（官方 HdsListItemCard 的 width() 实际不生效、渲染宽 =
// 容器 100%−32vp，挂 CARD_WIDTH 86% 会窄于官方卡——决明真机反馈不一致；依据见
// Theme.ets CARD_PANEL_WIDTH 注释）；组间距 16vp（区块间距
// 非卡片间距，不走 CARD_SPACING）。
// ★ 名单数据 = 下方 AI_CREDIT_GROUPS 常量（2026-08-29 决明拍板与 dshinhm 旧项目对齐：
//   名单内容与名称排版同 dshinhm AiAssistPage 定稿——模型名按官方写法（Kimi K3 /
//   DeepSeek V4 Flash / V4 Flash Vision Exp / V4 Pro），工具名按品牌名规范化（Z Code /
//   Kimi Code / DeepSeek Harness）；后续改名单只动该常量）。
// ★ 2026-09-20 决明追补两条模型（「ai辅助开发加上 deepseekv4.1flash 和 glm5.3flash，注意
//   大小写」）：DeepSeek V4.1 Flash 排 DeepSeek 簇末、GLM 5.3 Flash 紧跟 GLM 5.3；大小写
//   按官方写法落字（品牌 DeepSeek / GLM 原样，版本 V 大写、Flash 首字母大写）。自此本名单
//   比 dshinhm 同名页多这两条（旧项目未同步），「与旧项目对齐」口径收窄为其余条目同款；
//   名单内容与序由 scripts/assert-app-domain.mjs 135 组两钉守（逐字 + 品牌词形大小写）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import {
  CARD_PANEL_WIDTH,
  cardBg,
  cardBorderColor
} from '../common/Theme';
import { SETTING_TITLE_AI_ASSIST } from '../common/SettingSearch';
import { PageShell } from '../common/PageShell';

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
      'DeepSeek V4 Flash',
      'DeepSeek V4 Flash Vision Exp',
      'DeepSeek V4 Pro',
      'DeepSeek V4.1 Flash',
      'GLM 5.3',
      'GLM 5.3 Flash'
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

  // 分组大卡（自制分组卡：InfoPage 分组卡先例——cardBg 圆角 16，视觉与 HDS 列表卡同规格；
  // ★ 无轮廓线（2026-08-23 二十五改）：官方 HdsListItemCard 无描边（列表卡片规范「无描边」），
  //   自制卡一致——此前沿 InfoPage 先例挂了 border 1px 轮廓线，决明反馈与官方不一致，已去；
  // ★ 分割线两侧留空（2026-08-23 二十五改）：两侧各 16vp（左沿与条目文字对齐、右侧对称留空
  //   ——官方设置列表分割线惯例，不延伸至卡片两端）；条目条间官方 Divider（颜色/粗细组件
  //   默认 + cardBorderColor 显式——同 InfoPage）；最后一条后不留分割线（无边框无需再防双线，
  //   统一「条间线」语义）；条目纯展示无点击（无按压态无箭头）。
  // ★ 宽度用 CARD_PANEL_WIDTH 而非 CARD_WIDTH（2026-08-23 二十四改）：官方 HdsListItemCard
  //   的 .width() 实际不生效（组件内部固定样式优先，渲染宽 = 容器 100% − 内部 16vp×2，
  //   真机实测依据 Theme.ets CARD_PANEL_WIDTH 注释）——其他「关于」系页面卡实际即此宽；
  //   自制卡 width 会生效，若挂 CARD_WIDTH(86%) 会比官方卡窄（决明真机反馈不一致）
  @Builder
  GroupCard(group: AiCreditGroup) {
    Column() {
      ForEach(group.items, (name: string) => {
        Text(name)
          .fontSize(15)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 13, bottom: 13 })
        Divider()
          .color(cardBorderColor(this.appColorMode))
          // 分割线不延伸至卡片两端：左右各缩进 16vp（左沿对齐条目文字，右对称留空）
          .padding({ left: 16, right: 16 })
      }, (name: string) => name)
    }
    .width(CARD_PANEL_WIDTH)
    .borderRadius(16)
    .backgroundColor(cardBg(this.appColorMode))
    .clip(true)
    // 组间距 = 卡片块自身 margin（@Builder 返回值 void 不能链——margin 挂卡容器上；
    // 分组块属大区块非卡片间距，组间距 16vp 不进 CARD_SPACING 规范）
    .margin({ bottom: 16 })
  }

  // 分组（卡外左上标题 + 卡片；标题宽度 CARD_PANEL_WIDTH 使左沿与卡片左沿对齐——
  // PermissionPage 先例；标题与卡片间距 8vp（二十四改：12vp 决明反馈过大——「观感
  // 标题悬空」，官方 4 网格紧凑级）；组间距 = GroupCard 内 margin bottom 16（二十四改：
  // 原外层 space CARD_SPACING 10vp 决明反馈太小——分组块属「大区块」非卡片，用区块
  // 间距 16vp，AboutPage 图标区 24vp 同族先例）
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
          // 声明说明段（通用措辞；宽度 CARD_PANEL_WIDTH 左对齐——与卡片左沿对齐）
          Text('本应用的部分开发工作由 AI 辅助完成。以下为参与开发的 AI 模型与 Agent 工具。')
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
            .lineHeight(21)
            .width(CARD_PANEL_WIDTH)
            .margin({ bottom: 16 })

          // 分组列（组间间距由 GroupBlock 内 margin 16 管理——分组块属大区块非卡片，
          // 不走 CARD_SPACING 卡片间距规范；24 改：原 space CARD_SPACING 叠 margin 会双计）
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
      // 滚动内容不足视口时顶对齐（2026-08-20 根因修复：Scroll align 默认 Center——同 AboutPage）
      .align(Alignment.TopStart)
      // 官方边缘回弹：滑到边界继续滑一段距离、松手回弹
      .edgeEffect(EdgeEffect.Spring)
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
