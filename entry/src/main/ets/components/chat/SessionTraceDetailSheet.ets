// 会话轨迹记录详情半模态面板（2026-10-07 会话轨迹视图笔；任务书-会话轨迹视图-20261007 §5.4）：
// 面板内容件（**不含 bindSheet**——宿主 = SessionTracePage 页面根唯一挂载点，规范-半模态
// §1 挂点「页面根」、§8「面板内容件」先例）。形制照 SessionStatsSheet / ReqLogDetailSheet
// 同款三件套（HdsNavigation MODAL 壳 + sheetTitleBarOptions + bindToScrollable 滚动感知 +
// 底部安全区延伸 + 滚动容器 clip(false)）。
// 内容段（照任务书 §5.4）：概览卡（名称 / 状态 / 时刻 / 耗时）+ 轮级用量卡（输入 / 缓存 /
// 输出 / 总计 + 首字耗时 / 生成时长 / 生成速度）+ 参数与结果两卡（工具行且事实配对成功时
// 才出——对不齐不猜的展示面；JSON 原文不脱敏，权限面同会话正文与工具卡）。快照语义 =
// 点行一刻的记录与关联事实传入，打开期间不跟进（ReqLogDetailSheet 同款口径）；纯展示面板
// 不加关闭确认（规范-半模态 §1 三门槛不成立）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { IMMERSIVE_LEVEL_KEY } from '../../common/ImmersiveLevel';
import { cardBg, cardDescColor, cardTitleColor, CARD_PANEL_WIDTH, CARD_SPACING, CARD_RADIUS } from '../../common/Theme';
import { tokenShort } from '../../common/TokenEstimate';
import { traceDurationText, traceFullTimeText, traceSecondsText, traceStatusTextOf,
  TraceFactIn, TraceRecord, TraceUsage } from '../../common/chat/SessionTraceModel';
import { sheetTitleBarOptions } from './KimiSheetCommon';
import { prettyJson } from './ChatToolRoundCtrl';

@Component
export struct SessionTraceDetailSheet {
  // 记录快照与关联（点行一刻；普通成员——快照语义，见头注释）
  record: TraceRecord | null = null;
  usage: TraceUsage | null = null;
  fact: TraceFactIn | null = null;
  onClose: () => void = () => {
  };
  // 底部系统导航条高（vp，宿主注入——滚动尾占位让位）
  bottomInset: number = 0;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  private scroller: Scroller = new Scroller();

  // 键值行（值可长按选择——报障场景把原文粘给别人看）
  @Builder
  InfoLine(label: string, value: string) {
    Row({ space: 12 }) {
      Text(label)
        .fontSize(13)
        .fontColor(cardDescColor())
        .width(72)
      Text(value)
        .fontSize(13)
        .fontColor(cardTitleColor())
        .layoutWeight(1)
        .copyOption(CopyOptions.LocalDevice)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  // 概览卡（状态 / 名称 / 时刻 / 耗时——记录四要素）
  @Builder
  OverviewCard() {
    Column({ space: 6 }) {
      this.InfoLine('名称', this.record !== null ? this.record.title : '—')
      this.InfoLine('状态', this.record !== null ? traceStatusTextOf(this.record.status) : '—')
      this.InfoLine('时刻', this.record !== null ? traceFullTimeText(this.record.timeMs) : '—')
      this.InfoLine('耗时', this.record !== null && this.record.durationMs > 0 ?
        traceDurationText(this.record.durationMs) : '—')
    }
    .width(CARD_PANEL_WIDTH)
    .padding(14)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  // 轮级用量卡（输入 / 缓存 / 输出 / 总计 + 计时三项；缓存与三计时都按 >0 门显——0 与未知
  // 区分同用量面板口径；速度 = 输出 ÷ 时长秒，与统计半模态同式）
  @Builder
  UsageCard() {
    Column({ space: 6 }) {
      if (this.usage !== null) {
        this.InfoLine('输入', tokenShort(this.usage.promptTokens))
        if (this.usage.cachedTokens > 0) {
          this.InfoLine('缓存', tokenShort(this.usage.cachedTokens))
        }
        this.InfoLine('输出', tokenShort(this.usage.completionTokens))
        this.InfoLine('总计', tokenShort(this.usage.totalTokens))
        if (this.usage.firstTokenMs > 0) {
          this.InfoLine('首字耗时', traceSecondsText(this.usage.firstTokenMs))
        }
        if (this.usage.durationMs > 0) {
          this.InfoLine('生成时长', traceDurationText(this.usage.durationMs))
          if (this.usage.completionTokens > 0) {
            this.InfoLine('生成速度', Math.round(this.usage.completionTokens /
              (this.usage.durationMs / 1000)) + ' tok/s')
          }
        }
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(14)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  // JSON 文本卡（参数 / 结果两卡共用；等宽小字 + 面板内滚动——任务书 §4.5；原文不脱敏）
  @Builder
  JsonCard(title: string, payload: string) {
    Column({ space: 8 }) {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
      Text(payload)
        .fontSize(12)
        .lineHeight(18)
        .fontFamily('monospace')
        .fontColor(cardTitleColor())
        .textAlign(TextAlign.Start)
        .width('100%')
        .copyOption(CopyOptions.LocalDevice)
    }
    .width(CARD_PANEL_WIDTH)
    .padding(14)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: CARD_SPACING }) {
          this.OverviewCard()
          if (this.usage !== null) {
            this.UsageCard()
          }
          // 参数与结果（工具行且事实配对成功才出——对不齐不猜：不显示耗时也不显示内容）
          if (this.fact !== null) {
            if (this.fact.payload !== '') {
              this.JsonCard('参数', prettyJson(this.fact.payload))
            }
            if (this.fact.result !== '') {
              this.JsonCard('结果', prettyJson(this.fact.result))
            }
          }
          // 尾部安全区让位（ignoreLayoutSafeArea BOTTOM 后末卡不贴导航条；Row 空占位）
          Row()
            .height(this.bottomInset + 12)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 12, bottom: 12 })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
      // 滚动内容穿透标题栏背后被 GRADIENT_BLUR 模糊采样（规范-半模态 §2：缺省裁剪 = 模糊空转）
      .clip(false)
      .align(Alignment.TopStart)
    }
    .titleBar(sheetTitleBarOptions('轨迹详情', '', (): void => {
      this.onClose();
    }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
