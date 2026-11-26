// 排队入口条（排队插队施工总案 U1）：队列非空时出现在标题栏下方带
//（PageShell.titleBarBottom，形制对齐 SearchTopBand：高 40 / CARD_PANEL_WIDTH / 半圆角 /
// REGULAR 恒光感 / 整带命中透传），有排队才显示、空则收起（titleBarBottomHidden 与内容区
// 让位同一 queueBandActive 同源驱动，防「带隐藏了让位还在」错位）。内容 = 队列符号 + 状态
// 文案，整条可点开排队半模态。
// · 两形态共用：HDS 路径 = 标题栏下方带承载（floating=false，带内下移 inset，带顶 = 标题栏
//   下沿，不是 topPad——topPad 含蒙层下延 16vp，同 SearchTopBand 口径）；非 HDS 回退 =
//   内容区顶部悬浮条（floating=true，无带承载，条顶 = max(topPad − 8, 0)）。两形态二选一
//   互斥禁双份（页面按 canIUse 分派：HDS 只走带、回退只走内容区悬浮条）。
//   材质同 WorkspaceBreadcrumbBar 两形态判例：带内 = 透明底 + REGULAR 恒光感；回退悬浮 =
//   app.color.comp_fallback_off_card 实底 + Material.empty（内容区件在 API 26 不出沉浸材质）。
// · 状态经 @Link 下行（queueCount / queuePaused）：本件居 PageShell.titleBarBottom 的构建位，
//   @Prop 不随父刷新会冻结在首帧（坑16 家族），@Link 为订阅式正常通道（SearchTopBand 同先例）。
// · 反碎片下限②申报（为何不能并入）：SearchTopBand 是搜索族带形**输入**件（持搜索词与过滤
//   语义）；本件持排队域展示与点击入口，职责不同、无同域既有件可并。
// · 文案遵守面向用户文案写作规约：常态「排队 N 条消息」、暂停「排队已暂停 N 条」。
import { uiMaterial } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { CARD_PANEL_WIDTH, cardDescColor, SEGMENT_BAR_BAND_TOP_INSET,
  SEGMENT_BAR_HEIGHT, fallbackOffCardBg } from '../common/Theme';
import { PREF_CARD_ALPHA_LEVEL_KEY, CARD_ALPHA_DEFAULT } from '../common/AppPreferences';
import { IMMERSIVE_LEVEL_KEY, resolvedUiMaterial } from '../common/ImmersiveLevel';

@Component
export struct QueueTopBand {
  // 排队条数（页面 @State → 本件 @Link；titleBarBottom 构建位不随父重渲的坑16 正解通道）
  @Link queueCount: number;
  // 队列是否处于暂停态（文案分档：暂停「排队已暂停 N 条」/ 常态「排队 N 条消息」）
  @Link queuePaused: boolean;
  // 整条点击上行（页面开排队半模态；本件不知面板存在，只报点击）
  onOpenQueue: () => void = (): void => {
  };
  // true = 非 HDS 回退：内容区顶部悬浮形态（条顶 = 标题栏下沿 + 8，同带内内容位；材质转
  // 实底 + 空材质——见头注释）；false = HDS 标题栏下方带承载形态
  floating: boolean = false;
  // 顶部留白（仅悬浮形态消费，页面 topPad 原样；算式 max(topPad − 8, 0) 与带内下移同源）
  topPad: number = 0;
  // 带内下移量（vp）：与 SearchTopBand 同默认 8 = 条底与带底齐平（带高 = inset + 40）
  inset: number = SEGMENT_BAR_BAND_TOP_INSET;
  // 沉浸光感档位（AppStorage 自订阅——「无」档归一 Material.empty，同搜索带链免逐页透传）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 深浅模式与卡底透明度档位：悬浮实底 off-card 随档叠 alpha（会话页常驻面订阅即刷）；
  // mode 供 Theme.fallbackOffCardBg 深浅分治
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;

  private statusText(): string {
    return this.queuePaused ? '排队已暂停 ' + this.queueCount + ' 条'
      : '排队 ' + this.queueCount + ' 条消息';
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        // 符号 = sys.symbol.list_bullet（队列清单语义；SDK resources.txt 在表 + 构建绿两道门，
        // 项目内已有消费先例——坑72）
        SymbolGlyph($r('sys.symbol.list_bullet'))
          .fontSize(20)
          .fontColor([cardDescColor()])
        Text(this.statusText())
          .fontSize(15)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width(CARD_PANEL_WIDTH)
      .height(SEGMENT_BAR_HEIGHT)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      // 半圆角与条高同源（面包屑条体判例 BREADCRUMB_RADIUS = 高/2；clip 保证底与材质随圆角）
      .borderRadius(SEGMENT_BAR_HEIGHT / 2)
      .clip(true)
      // 底/材质两形态分治（WorkspaceBreadcrumbBar 同款判例）：带内透明底 + REGULAR；回退
      // 悬浮实底 off-card + 空材质
      .backgroundColor(this.floating ?
        fallbackOffCardBg(this.appColorMode, this.cardAlphaLevel) : Color.Transparent)
      .systemMaterial(this.floating ? uiMaterial.Material.empty :
        resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, this.immersiveLevel, false))
      .onClick((): void => {
        this.onOpenQueue();
      })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Start)
    // 带内 = 带顶 + inset；悬浮 = 条顶 = max(topPad − 8, 0)（与带内容顶逐像素同源）
    .padding({ top: this.floating ?
      Math.max(this.topPad - SEGMENT_BAR_BAND_TOP_INSET, 0) : this.inset })
    // 整带命中透传：带体不挡下方列表拖动，条体自身仍可点（SearchTopBand 同款）
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
