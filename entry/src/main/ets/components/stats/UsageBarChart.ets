// 用量趋势柱状图纯展示组件：「峰值行 + 柱区 + 范围行」趋势图一件独立事。趋势点 @Link 下发
//（★坑16：PageShell.content @BuilderParam 内禁 @Prop），深浅色自订阅 appColorMode。逐日/
// 逐月本组件不分辨（key 原样进范围行）。
// ★ 峰值 peak 由页面在 loadStats 完成后计算、经 @Link 下发——@Watch 首帧初始化不触发
//（官方《@Watch 触发时机》），子组件自算首载停 0 → 全灰矮柱；父算下发初值即正确值（与
// UsageHeatMap.maxTotal 同修）。
// 布局死参数：柱区高 132vp——柱数 ≤14 = Row 均分（柱宽 16），>14 = 横向滚动（柱宽 12）并
// 初始/换档定位最右（坑63 家族 try/catch）；横滚分支 .align(TopStart)（官方默认 Center，
// 窄内容居中悬空观感，与热力图同修）；柱高公式与零值/圆角死参数见 barHeight 与 build；
// 零值灰 = badgeBg；无逐柱标签，卡底范围行 = 轴首末 key。
// ★ 2026-11-08 回弹笔：横滚分支显式 edgeEffect(Spring, alwaysEnabled true)——SDK 26 的
// Scroll 默认 EdgeEffect.None，不显式设则横滑到头没有回弹（UsageHeatMap / UsageLineChart 同款）。
import { TrendPoint, fmtCompact } from '../../common/store/UsageStatsCalc';
import { badgeBg, cardDescColor, usageAccentColor } from '../../common/Theme';

@Component
export struct UsageBarChart {
  // 趋势点数组（升序；逐日档 key = 'YYYY-MM-DD'、逐月档 key = 'YYYY-MM'）
  @Link @Watch('onPointsChange') points: TrendPoint[];
  // 峰值（柱高分母；页面 loadStats 完成时算好下发——见头注释）
  @Link peak: number;
  // 深浅色模式（柱体主蓝/零值灰分治）
  @StorageProp('appColorMode') appColorMode: number = 1;
  private scroller: Scroller = new Scroller();
  // 定位最右待执行标记（初始 true = 首载定位最右；points 变更时重置 → 换档后再定位）
  private pendingEdge: boolean = true;

  private onPointsChange(): void {
    // 仅重置定位标记；peak 由父下发，不在本组件遍历
    this.pendingEdge = true;
  }

  // 柱高死参数：value > 0 → max(8, round(value/峰值×120))；零值 → 3
  private barHeight(value: number): number {
    if (value <= 0 || this.peak <= 0) {
      return 3;
    }
    return Math.max(8, Math.round((value / this.peak) * 120));
  }

  build() {
    Column({ space: 8 }) {
      // 峰值行
      Row({ space: 6 }) {
        Text('峰值')
          .fontSize(12)
          .fontColor(cardDescColor())
        Text(fmtCompact(this.peak))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(usageAccentColor(this.appColorMode))
      }
      .alignItems(VerticalAlign.Bottom)

      // 柱区（柱数 ≤14 Row 均分，>14 横向滚动——两形态柱宽 16/12 死参数见头注释）
      if (this.points.length <= 14) {
        Row() {
          ForEach(this.points, (p: TrendPoint): void => {
            Column() {
              // 柱体（@Builder 值参直调动态样式首帧后冻结是坑16 黑名单——柱体原位展开不走
              // @Builder；零值条高 3 圆角 1.5 灰底，有量条圆角 6 主蓝）
              Column()
                .width(16)
                .height(this.barHeight(p.totalTokens))
                .borderRadius(p.totalTokens > 0 ? 6 : 1.5)
                .backgroundColor(p.totalTokens > 0 ? usageAccentColor(this.appColorMode) :
                  badgeBg(this.appColorMode))
            }
            .layoutWeight(1)
            .height('100%')
            .justifyContent(FlexAlign.End)
            .alignItems(HorizontalAlign.Center)
          }, (p: TrendPoint): string => p.key + '|' + p.totalTokens)
        }
        .width('100%')
        .height(132)
      } else {
        Scroll(this.scroller) {
          Row({ space: 3 }) {
            ForEach(this.points, (p: TrendPoint): void => {
              Column() {
                Column()
                  .width(12)
                  .height(this.barHeight(p.totalTokens))
                  .borderRadius(p.totalTokens > 0 ? 6 : 1.5)
                  .backgroundColor(p.totalTokens > 0 ? usageAccentColor(this.appColorMode) :
                    badgeBg(this.appColorMode))
              }
              .height('100%')
              .justifyContent(FlexAlign.End)
              .alignItems(HorizontalAlign.Center)
            }, (p: TrendPoint): string => p.key + '|' + p.totalTokens)
          }
          .height('100%')
          .onAreaChange((): void => {
            // 内容宽就绪/变化后定位最右（首触发消费标记防重复；坑63 家族 try/catch）
            if (this.pendingEdge) {
              this.pendingEdge = false;
              try {
                this.scroller.scrollEdge(Edge.End);
              } catch (e) {
                // 滚动器未就绪时容错（观感降级为从最早一根显示，不阻断渲染）
              }
            }
          })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        // SDK 26 的 Scroll 默认 EdgeEffect.None——显式挂 Spring 才有滑到头的回弹
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .height(132)
        // 内容窄于视口时靠左（官方默认 Center 居中悬空；理由见头注释）
        .align(Alignment.TopStart)
      }

      // 范围行（轴首末值：逐日档「YYYY-MM-DD 至 YYYY-MM-DD」、月档「YYYY-MM 至 YYYY-MM」）
      Text(this.points.length > 0 ?
        this.points[0].key + ' 至 ' + this.points[this.points.length - 1].key : '')
        .fontSize(12)
        .fontColor(cardDescColor())
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
