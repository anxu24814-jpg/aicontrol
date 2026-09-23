// 模板选择半模态共享件（2026-09-11 三处模板统一半模态 + 余额配置二级页化，方案 v3 四百零三
// ~五节）：职责一句话 = 「模板选择的行卡与半模态容器」——协议 / 价格 / 余额三处宿主共用
//（套用协议模板半模态-20260911 拍板：三份壳 + 三份回退分支必然漂，合一处）。
// · 行卡 = HDS HdsListItemCard 优选（textItem 主副行 + SuffixText 尾标 + cardHeight 72 +
//   cardBg + 圆角 16，ChatPromptSheet 卡同款字段，d.ts 实锤 @since 6.0.0(20)——API 26 可用）
//   + canIUse('SystemCapability.UIDesign.HDSComponent.Full') 回退自制卡（SettingsPage/
//   ChatPromptSheet 同款门槛）；行卡不挂 .width()——HDS 卡宽语义 = 容器 −32vp，**容器须
//   零左右边距**才会等于卡宽基准 CARD_PANEL_WIDTH（规范-半模态 §4 验收第 4 条，防双重
//   收窄与全宽复发；2026-09-11 真机反馈前本件容器多挂了左右 16，行卡整体窄 32vp，已摘）；
// · 数据三单源在宿主（CATALOG_PRESETS / @Link templates / BALANCE_TEMPLATES 各自映射为
//   TemplatePickRow[]），本件纯渲染零数据；
// · 点选即填入即关：onPick 上行后由宿主关面板——顺序钉死「先回填 + toast，后关面板」
//   （钉 B4，防吞 toast / 回填丢失）；本件不含 bindSheet（宿主挂，同 ModelFetchSheet 契约）；
// · 壳 = HdsNavigation MODAL + sheetTitleBarOptions（KimiSheetCommon 单源，勿另写标题）+
//   List clip(false) 穿透 GRADIENT_BLUR + [MEDIUM, LARGE] 档（sheetPanelOptions 默认即此，
//   宿主传参）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { TextModifier } from '@kit.ArkUI';
import { HdsListItemCard, HdsNavigation, HdsNavigationTitleMode, SuffixText } from '@kit.UIDesignKit';
import { CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';
import { IMMERSIVE_LEVEL_KEY } from '../../common/ImmersiveLevel';
import { sheetTitleBarOptions } from '../chat/KimiSheetCommon';

// 行卡数据（三处宿主各自构造：title = 模板名 / subtitle = 地址或价格摘要 / suffix = 协议名
// 或币种——价格处 suffix 恒 ''，空串不渲染尾标）
export interface TemplatePickRow {
  title: string;
  subtitle: string;
  suffix: string;
}

// 单张模板行卡（HDS 优选 + canIUse 回退自制卡——回退形制对齐 HDS 卡：高 72 / 圆角 16 /
// cardBg 底 / 主副行 + 尾标）
@Component
export struct TemplatePickRowCard {
  row: TemplatePickRow = { title: '', subtitle: '', suffix: '' };
  onPick: () => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 官方 HDS 列表卡可用性（ChatPromptSheet 同款门槛）
  private hdsListCardAvailable: boolean = canIUse('SystemCapability.UIDesign.HDSComponent.Full');

  build() {
    if (this.hdsListCardAvailable) {
      HdsListItemCard({
        textItem: {
          primaryText: { text: this.row.title },
          secondaryText: { text: this.row.subtitle }
        },
        suffixItem: new SuffixText({
          text: this.row.suffix,
          modifier: new TextModifier().fontColor($r('sys.color.font_tertiary'))
        }),
        cardHeight: 72,
        cardBorderRadius: 16,
        cardBackgroundColor: cardBg(this.appColorMode),
        onClick: (): void => {
          this.onPick();
        }
      })
    } else {
      Button() {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text(this.row.title)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.row.subtitle)
              .fontSize(13)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if (this.row.suffix !== '') {
            Text(this.row.suffix)
              .fontSize(13)
              .fontColor($r('sys.color.font_tertiary'))
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .type(ButtonType.Normal)
      .width(CARD_PANEL_WIDTH)
      .height(72)
      .backgroundColor(cardBg(this.appColorMode))
      .borderRadius(16)
      .padding({ left: 16, right: 16 })
      .onClick((): void => {
        this.onPick();
      })
    }
  }
}

// 半模态内容件（壳 + 行卡列表；不含 bindSheet——宿主挂 sheetPanelOptions 与本件，档位
// [MEDIUM, LARGE] 由宿主 sheetPanelOptions 默认值承担）
@Component
export struct TemplatePickSheet {
  mainTitle: string = '';
  subTitle: string = '';
  rows: TemplatePickRow[] = [];
  // 点选上行（index 命中宿主数据源——宿主在 onPick 内做回填 + toast 后自行关面板，钉 B4）
  onPick: (index: number) => void = () => {
  };
  onClose: () => void = () => {
  };
  // 标题栏材质随沉浸光感总档（KimiSheetCommon 规格，@StorageProp 自订阅）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 滚动控制器（标题栏 bindToScrollable 绑渐变模糊）
  private scroller: Scroller = new Scroller();

  build() {
    HdsNavigation() {
      List({ space: 10, scroller: this.scroller }) {
        ForEach(this.rows, (row: TemplatePickRow, index: number) => {
          ListItem() {
            TemplatePickRowCard({
              row: row,
              onPick: (): void => {
                this.onPick(index);
              }
            })
          }
        }, (row: TemplatePickRow, index: number): string => index + '|' + row.title)
      }
      .width('100%')
      .height('100%')
      // 内容穿透（滚动内容滚入标题栏背后被 GRADIENT_BLUR 模糊采样——ProviderBalancePanel
      // / ChatPromptSheet 同款三件套之一，clip(false) 是穿透开关）
      .clip(false)
      // ★ 2026-09-11 决明真机反馈修正：容器**不设左右边距**（规范-半模态面板与卡片布局
      // §4 验收第 4 条「容器不设左右边距 + 方卡组 16 / HDS 卡 −32 / 回退卡 CARD_PANEL_WIDTH」）
      // ——原写 left/right 16 = 双重收窄：HDS 卡自带 −32，容器再收 16+16 后行卡实宽 = 卡宽
      // 基准 −32，两分支同窄（回退分支 CARD_PANEL_WIDTH 相对同被收窄的容器再算一次，结果
      // 一致），与同页其余卡不齐。摘掉后 HDS 卡 = 容器−32 = CARD_PANEL_WIDTH 基准，回退卡
      // = calc(100%−32vp) 同值，三线对齐
      .padding({ bottom: 24 })
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
    }
    // 标题栏（KimiSheetCommon 单源：主副标题 + xmark 关闭 + AUTO 分割线 + 静止渐变模糊 +
    // 材质随档——勿自绘标题）
    .titleBar(sheetTitleBarOptions(this.mainTitle, this.subTitle, (): void => {
      this.onClose();
    }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
  }
}
