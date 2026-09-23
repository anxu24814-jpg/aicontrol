// 用量趋势柱状图纯展示组件（2026-09-06 任务书-用量统计页改版，自 UsageStatsPage 拆出——
// 职责缝 = 「峰值行 + 柱区 + 范围行」趋势图一件独立事；为何不并入页面与热力图同笔登记
// 在变更记录当日节）：趋势点 @Link 下发（★坑16——PageShell.content @BuilderParam 内
// 禁 @Prop），深浅色自订阅 appColorMode。逐日/逐月本组件不分辨（key 原样进范围行）。
// ★ 2026-09-07 修复（与 UsageHeatMap.maxTotal 同批，同根因）：峰值 peak 改由页面在
//   loadStats 完成后计算、经 @Link 下发——原实现 = 子组件 @Watch 内算普通成员，@Watch
//   对首帧初始化不触发（官方《@Watch 触发时机》），首载档 peak 停在 0 → barHeight
//   全部回落 3vp 零值条（首载趋势图 = 全灰矮柱）；父算下发 = 初值即正确值。（坑16 禁
//   @Prop，peak 同走 @Link。）
// 布局死参数（任务书）：峰值行 Row({space:6}) 底对齐 =「峰值」12fp 灰 + 值 14fp Medium
// 主蓝；柱区高 132vp——柱数 ≤14 = Row 均分（柱容器 layoutWeight(1)，柱宽 16），>14 =
// 横向滚动 Row({space:3})（柱宽 12）并初始/换档定位最右（同 UsageHeatMap 姿势，坑63
// 家族 try/catch）；★ 2026-09-07 横向滚动分支补 .align(Alignment.TopStart)（官方默认
// Center——15 柱 ≈222vp 仍窄于视口时会居中悬空，同热力图观感问题，同批修复）；
// 柱高 = value>0 ? max(8, round(value/峰值×120)) : 3，圆角 6（3vp 零值条 1.5），零值灰
// = badgeBg；无逐柱日期标签，卡底范围行 12fp 灰 = 轴首末 key。
import { TrendPoint, fmtCompact } from '../../common/store/UsageStatsCalc';
import { badgeBg, cardDescColor, usageAccentColor } from '../../common/Theme';

@Component
export struct UsageBarChart {
  // 趋势点数组（升序；逐日档 key = 'YYYY-MM-DD'、逐月档 key = 'YYYY-MM'）
  @Link @Watch('onPointsChange') points: TrendPoint[];
  // 峰值（柱高分母；页面 loadStats 完成时算好下发——见头注释 2026-09-07 修复）
  @Link peak: number;
  // 深浅色模式（柱体主蓝/零值灰分治）
  @StorageProp('appColorMode') appColorMode: number = 1;
  private scroller: Scroller = new Scroller();
  // 定位最右待执行标记（初始 true = 首载定位最右；points 变更时重置 → 换档后再定位）
  private pendingEdge: boolean = true;

  private onPointsChange(): void {
    // 仅重置定位标记；peak 由父下发，不在本组件遍历（数据变更的遍历在页面侧）
    this.pendingEdge = true;
  }

  // 柱高（任务书死参数）：value > 0 → max(8, round(value/峰值×120))；零值 → 3
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

      // 柱区（高 132vp；柱数 ≤14 Row 均分，>14 横向滚动——两形态柱宽 16/12 死参数）
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
            // 内容宽就绪/变化后定位最右（首次触发消费标记即解除防重复；坑63 家族 try/catch）
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
        .width('100%')
        .height(132)
        // 内容窄于视口时靠左（官方默认 Center——15 柱 ≈222vp 仍窄时居中悬空；
        // 超宽时 align 不生效，滚动定位最右逻辑不变）
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
