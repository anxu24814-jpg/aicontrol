// 用量趋势折线图纯展示组件（与 UsageBarChart 双形态切换）：承托 = 官方 Polyline 基础绘图件
//（ArkUI 无折线图图表组件，选官方件零 Canvas 自绘——实现选型第①级）。
// 与 UsageBarChart 同数据契约（@Link points/peak——坑16：PageShell.content @BuilderParam
// 内禁 @Prop）+ 同高度映射公式（折线点 y = 132 − 柱高公式值——切换只换形不换义）；峰值行/
// 范围行逐字复用。宽度：CARD_PANEL_WIDTH 为 calc 字符串非定值，折线 x 需绘图区实宽——
// onAreaChange 实测；≤14 点满宽均分、>14 点定步 15vp 横滚并初始定位最右（柱状图同参数）。
// 峰值 ≤0（全零时段）= 灰线贴底（对零值灰柱）；数据点圆点仅 ≤14 满宽形态渲染（密集形态省点）。
// ★ 2026-11-08 回弹笔：横滚分支显式 edgeEffect(Spring, alwaysEnabled true)——SDK 26 的
// Scroll 默认 EdgeEffect.None，不显式设则横滑到头没有回弹（UsageHeatMap / UsageBarChart 同款）。
import { TrendPoint, fmtCompact } from '../../common/store/UsageStatsCalc';
import { badgeBg, cardDescColor, usageAccentColor } from '../../common/Theme';

// 满宽形态点数上限（与 UsageBarChart Row 均分分支同值：≤14 满宽均分，>14 横滚定步）
const LINE_FILL_MAX: number = 14;
// 绘图区高（vp，与柱状图柱区同值）
const LINE_PLOT_HEIGHT: number = 132;
// 横滚形态逐点步长（vp，= 柱状图柱宽 12 + 间隙 3 同视觉密度）与首尾半描边留边
const LINE_SCROLL_STEP: number = 15;
const LINE_SCROLL_PAD: number = 6;

@Component
export struct UsageLineChart {
  // 趋势点数组（升序；逐日档 key = 'YYYY-MM-DD'、逐月档 key = 'YYYY-MM'）
  @Link @Watch('onPointsChange') points: TrendPoint[];
  // 峰值（y 映射分母；页面 loadStats 完成时算好下发——UsageBarChart 同契约）
  @Link peak: number;
  // 深浅色模式（折线主蓝/全零灰分治）
  @StorageProp('appColorMode') appColorMode: number = 1;
  // 满宽形态绘图区实测宽（vp；onAreaChange 回填——calc 卡宽解不出定值）
  @State private plotWidth: number = 0;
  private scroller: Scroller = new Scroller();
  // 定位最右待执行标记（初始 true；points 变更重置 → 换档后再定位）
  private pendingEdge: boolean = true;

  private onPointsChange(): void {
    this.pendingEdge = true;
  }

  // 点高（与 UsageBarChart.barHeight 同公式；折线点 y = LINE_PLOT_HEIGHT − 本值，两形态同一映射）
  private barHeight(value: number): number {
    if (value <= 0 || this.peak <= 0) {
      return 3;
    }
    return Math.max(8, Math.round((value / this.peak) * 120));
  }

  // 折线点集（vp 坐标，相对绘图区左上）：≤14 满宽均分（x = i×plotWidth/(n−1)，n=1 居中）；
  // >14 定步 15vp。满宽形态 plotWidth 未就绪返回空（onAreaChange 回填后 @State 驱动重建出线）
  private linePoints(): number[][] {
    const n: number = this.points.length;
    if (n === 0) {
      return [];
    }
    const pts: number[][] = [];
    if (n <= LINE_FILL_MAX) {
      if (this.plotWidth <= 0) {
        return [];
      }
      for (let i = 0; i < n; i++) {
        const x: number = n === 1 ? this.plotWidth / 2 : i * this.plotWidth / (n - 1);
        pts.push([x, LINE_PLOT_HEIGHT - this.barHeight(this.points[i].totalTokens)]);
      }
    } else {
      for (let i = 0; i < n; i++) {
        pts.push([LINE_SCROLL_PAD + i * LINE_SCROLL_STEP,
          LINE_PLOT_HEIGHT - this.barHeight(this.points[i].totalTokens)]);
      }
    }
    return pts;
  }

  // 横滚形态内容宽（vp）：首末点各留半步余量（描边不裁切）
  private scrollContentWidth(): number {
    const n: number = this.points.length;
    return n <= 1 ? LINE_SCROLL_STEP :
      (n - 1) * LINE_SCROLL_STEP + LINE_SCROLL_PAD * 2;
  }

  // 折线色：峰值 > 0 主蓝 / 全零灰贴底（对柱状图零值灰柱）
  private lineColor(): string {
    return this.peak > 0 ? usageAccentColor(this.appColorMode) : badgeBg(this.appColorMode);
  }

  // 数据点圆点（仅满宽形态；布局原语圆 = Column 7vp 圆角 3.5，零绘图 API 风险）
  @Builder
  DataDot(x: number, y: number) {
    Column()
      .width(7)
      .height(7)
      .borderRadius(3.5)
      .backgroundColor(this.lineColor())
      .position({ x: x - 3.5, y: y - 3.5 })
  }

  build() {
    Column({ space: 8 }) {
      // 峰值行（UsageBarChart 逐字同款——两形态同一信息面）
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

      // 线区（≤14 满宽均分需实测宽，>14 横滚定步 15 并初始定位最右——见头注释）
      if (this.points.length <= LINE_FILL_MAX) {
        Stack({ alignContent: Alignment.TopStart }) {
          Polyline()
            .width('100%')
            .height(LINE_PLOT_HEIGHT)
            .points(this.linePoints())
            .fillOpacity(0)
            .stroke(this.lineColor())
            .strokeWidth(2)
            .strokeLineCap(LineCapStyle.Round)
            .strokeLineJoin(LineJoinStyle.Round)
          // 圆点键含值段（UsageBarChart 同口径）——@Watch 只在键变时重建，同 key 值变
          // （同日追加用量）若无值段则圆点冻结旧坐标
          ForEach(this.points, (p: TrendPoint, index: number): void => {
            if (this.plotWidth > 0) {
              this.DataDot(this.linePoints()[index][0], this.linePoints()[index][1])
            }
          }, (p: TrendPoint): string => p.key + '|' + p.totalTokens)
        }
        .width('100%')
        .height(LINE_PLOT_HEIGHT)
        .onAreaChange((_oldValue: Area, newValue: Area): void => {
          // Area.width 类型 Length（string|number 联合），运行时回调实为 vp 数值——Number() 收敛
          this.plotWidth = Number(newValue.width);
        })
      } else {
        Scroll(this.scroller) {
          Stack({ alignContent: Alignment.TopStart }) {
            Polyline()
              .width(this.scrollContentWidth())
              .height(LINE_PLOT_HEIGHT)
              .points(this.linePoints())
              .fillOpacity(0)
              .stroke(this.lineColor())
              .strokeWidth(2)
              .strokeLineCap(LineCapStyle.Round)
              .strokeLineJoin(LineJoinStyle.Round)
          }
          .height('100%')
          .onAreaChange((): void => {
            // 内容宽就绪后定位最右（首触发消费标记防重复；坑63 家族 try/catch）
            if (this.pendingEdge) {
              this.pendingEdge = false;
              try {
                this.scroller.scrollEdge(Edge.End);
              } catch (e) {
                // 滚动器未就绪时容错（观感降级为从最早一段显示，不阻断渲染）
              }
            }
          })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        // SDK 26 的 Scroll 默认 EdgeEffect.None——显式挂 Spring 才有滑到头的回弹
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .height(LINE_PLOT_HEIGHT)
        .align(Alignment.TopStart)
      }

      // 范围行（UsageBarChart 逐字同款）
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
