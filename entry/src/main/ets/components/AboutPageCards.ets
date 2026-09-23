// 「关于」页卡片列（2026-08-22 自 AboutPage 拆出）：AboutPage 逼近 400 行防屎山红线，
// 按「先拆再加」规则——三张卡片（AI 辅助开发声明 / 开源项目鸣谢 / 版本信息；
// ★ 顺序约定：版本信息恒为最后一张——后续新增卡片一律插在其前，2026-08-22 决明定稿；
// ★ 2026-09-07 权限信息与隐私政策两卡自本组件移出至更多信息页 InfoPage 行卡——决明指令；
// ★ 2026-09-08 获取安装包卡移除——决明「消除全部影响，再移除获取安装包全链路」，
//   公开签名 HAP 一旦经该卡分享外传任何设备可直接侧载。UI 移入本组件，AboutPage 只留调用与回调处理。
// 组件契约：
// · appVersion 版本号（@Prop：父 @State appVersion 查询完成后同步刷新副文本——普通成员
//   入参不重渲染，坑57；本值会变必须 @Prop）；
// · onVersionCheck/onAiAssist/onOpenSource 卡片点击回调（上行 AboutPage 处理——
//   toast 占位/AI 声明页 push/开源鸣谢页 push；函数入参稳定，普通成员传引用即够，
//   同 PageShell.onShown 先例）。
// 卡片样式：HDS 路径官方 HdsListItemCard + SuffixTextAndArrow；无 HDS Full 回退自制白底
// 卡片（Button + Row，官方设置列表视觉）。宽度 CARD_PANEL_WIDTH、卡片间间距由本组件容器
// Column({ space: CARD_SPACING }) 管理（列表卡片规范：禁止对卡片挂 margin 管间距）。
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, cardTitleColor } from '../common/Theme';
import {
  SETTING_TITLE_AI_ASSIST,
  SETTING_TITLE_OPEN_SOURCE,
  SETTING_TITLE_VERSION_INFO
} from '../common/SettingSearch';
import { HdsListItemCard, SuffixTextAndArrow } from '@kit.UIDesignKit';
import { ConfigurationConstant } from '@kit.AbilityKit';

@Component
export struct AboutPageCards {
  // 应用版本号（父 @State 同步；readBundleInfo 完成后刷新版本卡副文本）
  @Prop appVersion: string = '';
  // 系统颜色模式（EntryAbility 写入 AppStorage，深浅色切换时自动刷新配色；回退卡片用）
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
  // 官方 HDS 列表项卡片可用性：syscap 自检（HdsListItemCard 要求 HDSComponent.Full）
  private hdsListCardAvailable: boolean = canIUse('SystemCapability.UIDesign.HDSComponent.Full');

  build() {
    // 卡片列：卡片间距统一由容器 space 管理（官方《设置列表卡片样式》示例
    // List({ space: 10 })，同 SearchSections/MyPage 等先例——禁止对卡片挂 margin 管间距）
    Column({ space: CARD_SPACING }) {
      // AI 辅助开发声明卡片（2026-08-23 二十二改新增：push 声明页 AiAssistPage——参与
      // 开发的 AI 名单占位待填，见该文件头注释；插在版本信息卡之前——顺序约定：
      // 版本信息恒为最后一张）
      if (this.hdsListCardAvailable) {
        HdsListItemCard({
          textItem: {
            primaryText: { text: SETTING_TITLE_AI_ASSIST },
            secondaryText: { text: '参与开发的 AI 与工具' }
          },
          suffixItem: new SuffixTextAndArrow({ text: '查看' }),
          cardBorderRadius: 16,
          onClick: () => {
            this.onAiAssist();
          }
        })
        .width(CARD_PANEL_WIDTH)
      } else {
        Button() {
          Row() {
            Column({ space: 4 }) {
              Text(SETTING_TITLE_AI_ASSIST)
                .fontSize(16)
                .fontColor(cardTitleColor())
              Text('参与开发的 AI 与工具')
                .fontSize(13)
                .fontColor(cardDescColor())
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('查看')
              .fontSize(13)
              .fontColor(cardDescColor())
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([cardDescColor()])
          }
          .width('100%')
          .padding(16)
        }
        .type(ButtonType.Normal)
        .width(CARD_PANEL_WIDTH)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(16)
        .onClick(() => {
          this.onAiAssist();
        })
      }

      // 开源项目鸣谢卡片（2026-09-02 新增：push 鸣谢页 OpenSourcePage——参考/使用过的
      // 开源项目与组件清单；插在版本信息卡之前——顺序约定：版本信息恒为最后一张）
      if (this.hdsListCardAvailable) {
        HdsListItemCard({
          textItem: {
            primaryText: { text: SETTING_TITLE_OPEN_SOURCE },
            secondaryText: { text: '参考的开源项目与组件' }
          },
          suffixItem: new SuffixTextAndArrow({ text: '查看' }),
          cardBorderRadius: 16,
          onClick: () => {
            this.onOpenSource();
          }
        })
        .width(CARD_PANEL_WIDTH)
      } else {
        Button() {
          Row() {
            Column({ space: 4 }) {
              Text(SETTING_TITLE_OPEN_SOURCE)
                .fontSize(16)
                .fontColor(cardTitleColor())
              Text('参考的开源项目与组件')
                .fontSize(13)
                .fontColor(cardDescColor())
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('查看')
              .fontSize(13)
              .fontColor(cardDescColor())
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([cardDescColor()])
          }
          .width('100%')
          .padding(16)
        }
        .type(ButtonType.Normal)
        .width(CARD_PANEL_WIDTH)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(16)
        .onClick(() => {
          this.onOpenSource();
        })
      }

      // 版本信息卡片（右侧「已是最新版本 >」，点击占位 toast，逻辑在 AboutPage）
      // ★ 顺序约定（2026-08-22 决明定稿）：版本信息恒为最后一张卡——后续新增卡片一律
      //   插在其前，保持「更新检测最后」的收尾语义
      if (this.hdsListCardAvailable) {
        HdsListItemCard({
          textItem: {
            primaryText: { text: SETTING_TITLE_VERSION_INFO },
            secondaryText: { text: this.appVersion }
          },
          // 官方「文字 + 箭头」后缀组合（SuffixTextAndArrow @since 6.0.0(20)，参考图
          // 「已是最新版本 >」同款）；不传 arrowOptions = 官方默认箭头样式
          suffixItem: new SuffixTextAndArrow({ text: '已是最新版本' }),
          // ★ 卡片背景官方默认（同 MainMenu/InfoPage：不传 cardBackgroundColor = 官方
          // 卡片底色深浅色自动反色）
          cardBorderRadius: 16,
          onClick: () => {
            this.onVersionCheck();
          }
        })
        // 卡片宽度统一 CARD_PANEL_WIDTH（屏宽−32vp 居中，aicontrol 口径——原 CARD_WIDTH 86% 已随迁移收敛，见 common/Theme.ets）
        .width(CARD_PANEL_WIDTH)
      } else {
        // 回退：自制白底卡片（无 HDS Full 能力；左「版本信息 / 版本号」+ 右「已是最新版本 +
        // chevron 箭头」，官方设置列表视觉同 InfoPage 回退分支）
        Button() {
          Row() {
            Column({ space: 4 }) {
              Text(SETTING_TITLE_VERSION_INFO)
                .fontSize(16)
                .fontColor(cardTitleColor())
              Text(this.appVersion)
                .fontSize(13)
                .fontColor(cardDescColor())
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('已是最新版本')
              .fontSize(13)
              .fontColor(cardDescColor())
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([cardDescColor()])
          }
          .width('100%')
          .padding(16)
        }
        .type(ButtonType.Normal)
        .width(CARD_PANEL_WIDTH)
        .backgroundColor(cardBg(this.appColorMode))
        .borderRadius(16)
        .onClick(() => {
          this.onVersionCheck();
        })
      }
    }
    .width('100%')
  }
}
