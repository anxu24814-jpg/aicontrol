// 「关于」页卡片列（自 AboutPage 拆出，防 400 行红线「先拆再加」）：三张卡片（AI 辅助开发
// 声明 / 开源项目鸣谢 / 版本信息）；★ 顺序约定（决明定稿）：版本信息恒为最后一张——后续
// 新增卡片一律插在其前（保持「更新检测最后」的收尾语义）。权限信息与隐私政策两卡已移至
// 更多信息页 InfoPage 行卡、获取安装包卡已移除（决明指令，防公开签名 HAP 外传侧载）。
// UI 移入本组件，AboutPage 只留调用与回调处理。
// 组件契约：
// · appVersion 版本号（@Prop：父 @State appVersion 查询完成后同步刷新副文本——普通成员
//   入参不重渲染，坑57；本值会变必须 @Prop）；
// · onVersionCheck/onAiAssist/onOpenSource 卡片点击回调（上行 AboutPage 处理——
//   toast 占位/AI 声明页 push/开源鸣谢页 push；函数入参稳定，普通成员传引用即够，
//   同 PageShell.onShown 先例）。
// 卡片样式（2026-11-04 蒙层合规笔）：整卡自绘，按规范 §4.19 范式——卡底 Column 承
// CARD_PANEL_WIDTH + cardBg + CARD_RADIUS + padding 4，内层透明 Button 做按压蒙层
// （四缘各 4vp）；卡高 72 = 4×2 + 64，内容内距 12 + 外层 4 = 原官方卡内距 16。
// 为什么弃官方 HdsListItemCard：其原生蒙层贴卡缘 0vp 且无蒙层几何参数（§4.19⑤ 终局）。
// 宽度 CARD_PANEL_WIDTH、卡片间间距由本组件容器
// Column({ space: CARD_SPACING }) 管理（列表卡片规范：禁止对卡片挂 margin 管间距）。
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, CARD_RADIUS } from '../common/Theme';
import {
  SETTING_TITLE_AI_ASSIST,
  SETTING_TITLE_OPEN_SOURCE,
  SETTING_TITLE_VERSION_INFO
} from '../common/SettingSearch';
import { ConfigurationConstant } from '@kit.AbilityKit';

@Component
export struct AboutPageCards {
  // 应用版本号（父 @State 同步；readBundleInfo 完成后刷新版本卡副文本）
  @Prop appVersion: string = '';
  // 系统颜色模式（EntryAbility 写入 AppStorage，深浅色切换时自动刷新配色；卡片底色 cardBg 取参用）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡片点击回调（AboutPage 注入：版本检测占位 / AI 声明页 push / 开源鸣谢页 push）
  onVersionCheck: () => void = () => {
  };
  // AI 辅助开发声明（AboutPage 注入：push AiAssistPage）
  onAiAssist: () => void = () => {
  };
  // 开源项目鸣谢（AboutPage 注入：push OpenSourcePage）
  onOpenSource: () => void = () => {
  };

  // 单条目入口卡（三卡同形制）：标题 + 副标题 + 右侧「文字 + 箭头」；整行可点，蒙层四缘 4vp
  @Builder
  LinkCard(title: string, subtitle: string, suffix: string, onTap: () => void) {
    Column() {
      Button() {
        Row({ space: 8 }) {
          Column({ space: 0 }) {
            Text(title)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(subtitle)
              .fontSize(14)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Row({ space: 4 }) {
            Text(suffix)
              .fontSize(14)
              .fontColor($r('sys.color.font_tertiary'))
              .maxLines(1)
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(20)
              .fontColor([cardDescColor()])
          }
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
        onTap();
      })
    }
    .width(CARD_PANEL_WIDTH)
    .height(72)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }

  build() {
    // 卡片列：卡片间距统一由容器 space 管理（官方《设置列表卡片样式》示例
    // List({ space: 10 })，同 SearchSections/MyPage 等先例——禁止对卡片挂 margin 管间距）
    Column({ space: CARD_SPACING }) {
      // AI 辅助开发声明卡片（push 声明页 AiAssistPage）；插在版本信息卡之前（顺序约定见头注释）
      this.LinkCard(SETTING_TITLE_AI_ASSIST, '参与开发的 AI 与工具', '查看', (): void => {
        this.onAiAssist();
      })

      // 开源项目鸣谢卡片（push 鸣谢页 OpenSourcePage）；插在版本信息卡之前（顺序约定见头注释）
      this.LinkCard(SETTING_TITLE_OPEN_SOURCE, '参考的开源项目与组件', '查看', (): void => {
        this.onOpenSource();
      })

      // 版本信息卡片（右侧「已是最新版本 >」，点击占位 toast，逻辑在 AboutPage；恒为最后一张
      // ——顺序约定见头注释）
      this.LinkCard(SETTING_TITLE_VERSION_INFO, this.appVersion, '已是最新版本', (): void => {
        this.onVersionCheck();
      })
    }
    .width('100%')
  }
}
