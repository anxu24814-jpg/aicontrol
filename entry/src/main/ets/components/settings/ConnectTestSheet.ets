// 连接能力三项测试半模态面板（内容件，不含 bindSheet——宿主 = ProviderKeysPanel 根，规范-半模态 §1「最近
// 可达根」三判据全过、§8「面板内容件」清单）。形制同 ContextUsageSheet / MessageCopySheet 四件套
//（HdsNavigation MODAL 壳 + sheetTitleBarOptions 主副标题 + bindToScrollable + 底部安全区延伸），滚动容器
// clip(false)（规范 §2：渐变模糊要有内容可透）。
// · 内容 = 三张结果卡（一项能力一卡，卡体与行体合一由 ForEach 展开）：卡左 = 标签 + 详情（最多三行省略），
//   卡右 = 状态区（测试中 LoadingProgress / 通过 checkmark 主色 / 失败 xmark 警示色 / 未测试纯文字——零新色
//   零新符号）。
// · 底部吸底单键「测试」（重跑全部三项）：形制照 MessageCopySheet（规范 §2 第三条）——Stack 底对齐叠〔Scroll
//   全高 + 蒙层 + 键带〕，键不随内容滚动、内容经蒙层渐隐穿出；Scroll 尾占位 = 蒙层高（含安全区），两处同源
//   单常量；键带透明 + hitTestBehavior(Transparent)。「取消」键不做——关闭走标题栏 xmark。
// · 数据 = @Link 三参（model 副标题 / rows 结果行 / testing 重跑门闩）：结果陆续回来、副标题异步回填，故
//   一律 @Link（普通值参在 builder 位不随父更新）；行数据模型与四态字单源在 KeyConnectTester /
//   ConnectTestJudge。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont,
  fallbackButtonMaterial, fallbackButtonStateEffect
} from '../../common/ImmersiveLevel';
import { cardBg, cardDescColor, cardTitleColor, CARD_PANEL_WIDTH, CARD_SPACING, pageBgFade, CARD_RADIUS } from '../../common/Theme';
import {
  PROBE_FAIL, PROBE_IDLE, PROBE_OK, PROBE_RUNNING
} from '../../common/providers/ConnectTestJudge';
import { ConnectTestRow } from './KeyConnectTester';
import { sheetTitleBarOptions } from '../chat/KimiSheetCommon';

// 底部渐变蒙层高（vp，单源：蒙层与 Scroll 尾占位同用「本值 + 安全区」；键带基高 64 + 26vp 渐隐余量）。
// 底部安全区兜底（vp）：宿在服务商详情页深处，拿不到页面侧 bottomPad，按同域先例取 24（ModelFetchSheet /
// ProviderModelsPanel 同值），键带底 padding 与蒙层高同源本值
const TEST_BOTTOM_FADE_HEIGHT: number = 90;
const TEST_BOTTOM_SAFE_PAD: number = 24;

@Component
export struct ConnectTestSheet {
  // 副标题（模型名；打开面板时未知，探针解析完模型后经宿主回填）
  @Link model: string;
  // 三行结果（宿主整组替换驱动重建——键含 state/detail）
  @Link rows: ConnectTestRow[];
  // 重跑门闩（true = 进行中，键禁用——防连点叠加）
  @Link testing: boolean;
  // 关闭上行（xmark——宿主置 sheetShow = false；手势关闭走 bindSheet onWillDismiss）
  onClose: () => void = () => {
  };
  // 重跑上行（宿主整组重置为「测试中」后重发三项）
  onRetest: () => void = () => {
  };
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  private scroller: Scroller = new Scroller();

  private bottomFadeHeight(): number {
    return TEST_BOTTOM_FADE_HEIGHT + TEST_BOTTOM_SAFE_PAD;
  }

  // 四态字 → 展示字（值域单源在 ConnectTestJudge；未知值原样显示不吞）
  private stateText(state: string): string {
    if (state === PROBE_IDLE) {
      return '未测试';
    }
    if (state === PROBE_RUNNING) {
      return '测试中';
    }
    if (state === PROBE_OK) {
      return '通过';
    }
    if (state === PROBE_FAIL) {
      return '失败';
    }
    return state;
  }

  // 状态字色（仅失败走项目警示色先例，其余走卡内正文/次要色——零新色）
  private stateColor(state: string): Resource {
    return state === PROBE_FAIL ? $r('sys.color.ohos_id_color_warning') : cardDescColor();
  }

  // 单行结果卡（每次调用即一张卡，卡数由 ForEach 展开）
  @Builder
  ResultRow(row: ConnectTestRow) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(row.label)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
        if (row.detail !== '') {
          Text(row.detail)
            .fontSize(13)
            .fontColor(cardDescColor())
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Row({ space: 4 }) {
        if (row.state === PROBE_RUNNING) {
          LoadingProgress()
            .width(16)
            .height(16)
        } else if (row.state === PROBE_OK) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(16)
            .fontColor([cardTitleColor()])
        } else if (row.state === PROBE_FAIL) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('sys.color.ohos_id_color_warning')])
        }
        Text(this.stateText(row.state))
          .fontSize(13)
          .fontColor(this.stateColor(row.state))
      }
      .alignItems(VerticalAlign.Center)
    }
    // 卡体（自绘卡：宽走 CARD_PANEL_WIDTH，圆角 CARD_RADIUS 与卡内边距 16 同各面板先例）
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(VerticalAlign.Top)
  }

  build() {
    HdsNavigation() {
      // 吸底键条层：Stack 底对齐叠〔Scroll 全高 + 蒙层 + 键带〕——键不随滚动、内容滚出到键后（规范 §2 第三条）
      Stack({ alignContent: Alignment.Bottom }) {
        Scroll(this.scroller) {
          Column({ space: CARD_SPACING }) {
            // 结果卡 ×3（卡体在 ResultRow，随 ForEach 展开）。★ 禁改裸 row.key：键不变则 ForEach 复用旧节点、
            // 卡面定格（官方 FAQ faqs-arkui-41；规范-列表卡片坑57 家族）——守钉 = assert-ui-shape 146 组键三载荷
            ForEach(this.rows, (row: ConnectTestRow) => {
              this.ResultRow(row)
            }, (row: ConnectTestRow): string => row.key + '|' + row.state + '|' + row.detail)
            // 尾部占位 = 蒙层高（★ 与蒙层同源 bottomFadeHeight）；Row 空占位——
            // Blank 在部分容器下编译 10905201，规范 §2 先例用 Row
            Row()
              .height(this.bottomFadeHeight())
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 12, bottom: 12 })
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .height('100%')
        // 滚动内容穿透标题栏背后被 GRADIENT_BLUR 模糊采样（规范 §2：缺省裁剪 = 模糊空转）
        .clip(false)
        .align(Alignment.TopStart)

        // 底部渐变蒙层（上透下实 / pageBgFade 深浅分治 / hitTestBehavior(None) 不拦滚动）
        Column()
          .width('100%')
          .height(this.bottomFadeHeight())
          .linearGradient({
            angle: 180,
            colors: [[pageBgFade(this.appColorMode), 0], [$r('app.color.page_bg'), 1]]
          })
          .hitTestBehavior(HitTestMode.None)

        // 底部吸底键带（条透明 + Transparent 不阻断下层滚动；键自身四件套承担两态）
        Column() {
          Row() {
            // 「测试」= 主操作（官方强调蓝 + 恒白字；fallbackButton* 四件套）
            Button('测试')
              .width('100%')
              .fontColor(fallbackButtonFont(this.contentFallback, true))
              .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
              .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
              .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
              .enabled(!this.testing)
              .onClick((): void => {
                this.onRetest();
              })
          }
          .width(CARD_PANEL_WIDTH)
        }
        .width('100%')
        .hitTestBehavior(HitTestMode.Transparent)
        // 单一 padding（ArkUI 同属性后设覆盖——MessageCopySheet 同款教训）
        .padding({ top: 12, bottom: TEST_BOTTOM_SAFE_PAD + 12 })
      }
      .width('100%')
      .height('100%')
    }
    // 主副标题位现成（主标题固定 + 副标题 = 模型名），禁自绘标题区（规范 §1）
    .titleBar(sheetTitleBarOptions('测试连接', this.model, (): void => {
      this.onClose();
    }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
