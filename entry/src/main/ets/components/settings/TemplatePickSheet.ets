// 模板选择半模态共享件：职责 = 「模板选择的行卡与半模态容器」——协议 / 价格 / 余额三处宿主共用（三份壳
// 必然漂，故合一处）。数据三单源在宿主（各自映射为 TemplatePickRow[]），本件纯渲染零数据；
// 不含 bindSheet（宿主挂，同 ModelFetchSheet 契约）。
// · 行卡 = 整卡自绘（2026-11-04 蒙层合规笔；类名沿用 SelfListCard 形制——卡底 + padding 4 +
// 透明 Button 蒙层，四缘 4vp；高 72 = 4×2 + 64，内距 12 + 外层 4 = 原官方卡内距 16）
//   CARD_RADIUS，d.ts @since 6.0.0(20)）；行卡不挂 .width()
//   ——HDS 卡宽语义 = 容器 −32vp，**容器须零左右边距**才等于卡宽基准 CARD_PANEL_WIDTH（规范-半模态 §4 验收
//   第 4 条，防双重收窄与全宽复发）。
// · 点选即填入即关：onPick 上行后由宿主关面板——顺序钉死「先回填 + toast，后关面板」（钉 B4）。
// · 壳 = HdsNavigation MODAL + sheetTitleBarOptions（KimiSheetCommon 单源，勿另写标题）+ Scroll clip(false)
//   穿透 GRADIENT_BLUR + [MEDIUM, LARGE] 档。★ 勿改回 List：List 对滚出视口的行做布局级虚拟化，clip(false)
//   只管绘制裁剪、管不住行回收，行卡滑到视口上缘即整张消失；Scroll 不回收子项，配 clip(false) 才是滑进
//   标题栏渐变模糊区的正确形态。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { CARD_PANEL_WIDTH, CARD_SPACING, cardBg, cardDescColor, CARD_RADIUS } from '../../common/Theme';
import { IMMERSIVE_LEVEL_KEY } from '../../common/ImmersiveLevel';
import { sheetTitleBarOptions } from '../chat/KimiSheetCommon';
// 全站状态词徽标形制单源（2026-10-20 实底统一笔：生效项「当前」尾标换实底胶囊）
import { StatusBadge } from '../StatusBadge';

// 行卡数据（三处宿主各自构造：title = 模板名 / subtitle = 地址或价格摘要 / suffix = 协议名或币种；价格处
// suffix 恒 ''，空串不渲染尾标）。★ suffixEmphasis：true = 尾标是状态词（如「当前」），渲染为实底胶囊
// StatusBadge；缺省/false = 普通尾标（协议名 / 币种等元数据）。只有 SearchEnginePage 传 true
export interface TemplatePickRow {
  title: string;
  subtitle: string;
  suffix: string;
  suffixEmphasis?: boolean;
}

// 单张模板行卡（2026-11-04 蒙层合规笔：整卡自绘——高 72 / CARD_RADIUS / cardBg / 主副行 + 尾标；
// 蒙层四缘 4vp）
@Component
export struct TemplatePickRowCard {
  row: TemplatePickRow = { title: '', subtitle: '', suffix: '' };
  onPick: () => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  // 尾标（状态词 = 实底胶囊 / 普通尾标 = 次要色文字；空串不渲染——行卡恒调本 builder，
  // 必须在此自守空值，否则空尾标会画出一颗空胶囊）
  @Builder
  SuffixCell() {
    if (this.row.suffix !== '') {
      if (this.row.suffixEmphasis === true) {
        StatusBadge({ text: this.row.suffix })
      } else {
        Text(this.row.suffix)
          .fontSize(13)
          .fontColor($r('sys.color.font_tertiary'))
      }
    }
  }

  build() {
    Column() {
      Button() {
        Row({ space: 8 }) {
          Column({ space: 0 }) {
            Text(this.row.title)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.row.subtitle)
              .fontSize(14)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          this.SuffixCell()
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
        this.onPick();
      })
    }
    .width(CARD_PANEL_WIDTH)
    .height(72)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .padding(4)
  }
}

// 半模态内容件（壳 + 行卡列表；不含 bindSheet——宿主挂 sheetPanelOptions 与本件，档位 [MEDIUM, LARGE] 由
// 宿主默认值承担）。★ 滚动骨架 = Scroll + Column（非 List）：List 布局级虚拟化会回收滑出视口的行卡，
// clip(false) 只管绘制裁剪、管不住行本身回收，行卡滑到视口上缘即整张消失；Scroll 不回收子项，才是滑进
// 标题栏渐变模糊区的正确形态（决明报障后改；三处宿主同源受益）
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
      Scroll(this.scroller) {
        Column({ space: CARD_SPACING }) {
          ForEach(this.rows, (row: TemplatePickRow, index: number) => {
            TemplatePickRowCard({
              row: row,
              onPick: (): void => {
                this.onPick(index);
              }
            })
          }, (row: TemplatePickRow, index: number): string => index + '|' + row.title)
          // 尾部安全区让位（ignoreLayoutSafeArea BOTTOM 后末卡不贴导航条——ConvPickerSheet / ModelFetchSheet 同款）
          Row()
            .width('100%')
            .height(24)
        }
        .width('100%')
        // 行卡水平居中（HDS 卡 = 容器−32，容器不设左右 padding——规范-半模态 §4 验收第 4 条）
        .alignItems(HorizontalAlign.Center)
        // 卡间距走 Column space（原 List space 10 同值）；top 20 / bottom 24 照 ConvPickerSheet
        .padding({ top: 20, bottom: 24 })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      // 内容穿透（clip(false) 是穿透开关——滚入标题栏背后被 GRADIENT_BLUR 模糊采样；本件已无 List 虚拟化回收）
      .clip(false)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
    }
    // 标题栏（KimiSheetCommon 单源：主副标题 + xmark 关闭 + 分割线 + 静止渐变模糊 + 材质随档——勿自绘标题）
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
