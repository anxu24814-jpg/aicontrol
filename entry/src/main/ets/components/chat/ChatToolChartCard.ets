// 工具卡图表块（★「图表正文化」：渲染位自工具卡展开区提升为**消息正文**——展示项
// kind='chart'，挂载点 = ChatPageContent 列表分支；本组件内部绘制链零改动、只换宿主，
// 展开区渲染已退役）。
// 机制蓝本 = rik chart_display 渲染层（只采信机制、禁抄码）：
// · 数据源 = toolInputJson（chart_display 入参 JSON——随消息落库，历史回放重解析重绘零迁移）；
//   解析器单源 = ToolChart.parseChartSpec（宽松解析：坏字段丢弃、构不成图回 null——本件零
//   渲染退原始 JSON 面板，不崩不错画）；上屏判据单源 = ToolChart.chartDisplaySpec（回执
//   success ∧ 入参成图——判不出来就不产图表展示项，本件收不到）
// · 载体 = Canvas 自绘（官方明示适用数据可视化）：line/bar 类目轴 + scatter 数值双轴；数值轴
//   支持 min/max 覆盖与 log，bar 恒含 0 基线（与校验器约束同源）——轴几何/刻度/系列/图例全在
//   本件，无第二渲染实现。
// · 绘制时机三闸：onReady 首绘（0 尺寸画布不可用——宽高显式必补）；onAreaChange 重绘（旋转/
//   分屏/折叠展开改卡宽后自绘新几何——onReady 只触发一次）；onVisibleAreaChange 门控不可见
//   停绘（官方红线：不可见时频繁调绘制接口致指令堆积）——不可见期只记意图，重新可见补一拍。
// · 尺寸红线核（官方：Canvas 宽或高 > 8000px 转 RenderNode、CPU 渲染性能下降）：绘图区恒
//   200vp 高 + 卡片内容宽，距红线一个量级（见 CHART_CANVAS_HEIGHT）；不做缩放大画布。
// · 深浅色适配：网格线复用 cardBorderColor(appColorMode) 单源；轴文字/图例取本件两态常量
//  （Canvas 色参必须色串，Theme 的 Resource 族不可用）；系列色板固定 6 色不随主题（深浅底
//   对比度均达标）。
// · 图例行 = 简式「系列名 + 色块」；图表↔表格切换 = 卡头右置 SegmentBar 紧凑档（决明拍板
//  两轮缩小 + 选中白底，宽度约束单源见 CHART_VIEW_SEGMENT_WIDTH 注释）；表格态 = 数值兜底
//  （Canvas 不可被读屏读取，点数少时用户常要看原值），有界：列 5 系列封顶 + 行 12 封顶 +
//  超额注记行。
// · 状态最小化：spec 为普通成员（构造期一次传入、寿命内不变）；仅视图态下标挂 @State。
import { cardBg, cardBorderColor, cardDescColor, cardTitleColor, BUBBLE_PAD_NEAR, BUBBLE_RADIUS,
  CARD_SPACING, SEGMENT_BAR_COMPACT_HEIGHT } from '../../common/Theme';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PREF_CARD_ALPHA_LEVEL_KEY, CARD_ALPHA_DEFAULT } from '../../common/AppPreferences';
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { SegmentBar } from '../SegmentBar';
import { ChartAxisData, ChartPointData, ChartSeriesData, ChartSpecData } from '../../common/providers/ToolChart';
import { ChatDisplayItem } from './ChatDisplayProjection';
import { ChatRoundHeader } from './ChatMessageHeader';

// 绘图区与画布几何（vp；宽 = 宿主 100%——宿主已有内距无双重收窄，高 = 常量；8000px 红线核
// 见文件头注）
const CHART_CANVAS_HEIGHT: number = 200;
const CHART_PAD_LEFT: number = 46;
const CHART_PAD_RIGHT: number = 12;
const CHART_PAD_TOP: number = 10;
const CHART_PAD_BOTTOM: number = 26;
const CHART_TICK_COUNT: number = 4;
const CHART_MAX_X_LABELS: number = 6;
const CHART_LABEL_MAX_CHARS: number = 8;
// 表格态有界（数据有界红线）：列/行封顶 + 注记行
const CHART_TABLE_MAX_SERIES: number = 5;
const CHART_TABLE_MAX_ROWS: number = 12;
const CHART_SCATTER_DOT_RADIUS: number = 2.5;
// 卡头视图切换分段胶囊容器宽（vp）：官方 CapsuleSegmentButtonV2 无宽度参数且不支持通用属性
//（width 无效），组件宽度 = 父容器宽——卡头右置须由外层定宽容器约束。紧凑档经决明拍板两轮
// 缩小定形，容器随档收至 74；高度恒引 SEGMENT_BAR_COMPACT_HEIGHT（勿回 SEGMENT_BAR_HEIGHT）
const CHART_VIEW_SEGMENT_WIDTH: number = 74;

// 系列固定色板（6 色循环——固定色不随主题，DIFF_* 两色先例；深浅底对比度均达标）
const CHART_SERIES_COLORS: string[] = ['#4A90D9', '#E8774E', '#57A66E', '#B07FD0', '#D4A93C',
  '#4FB3C7'];

// 轴文字色（两态；Canvas 需色串——见文件头深浅色适配条）
function chartAxisTextColor(mode: number): string {
  return mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#99FFFFFF' : '#8A000000';
}

// 空 spec（@Component 普通成员缺省——构造期必被真实 spec 覆盖）
function emptyChartSpec(): ChartSpecData {
  const axis: ChartAxisData = { label: '', min: Number.NaN, max: Number.NaN, log: false };
  const spec: ChartSpecData = {
    style: '', title: '', categories: [], xAxis: axis, yAxis: axis, series: []
  };
  return spec;
}

// 刻度数值文本（线性轴）：至多 4 位小数、去尾零（大数走 toString 原样）
function formatTickValue(v: number): string {
  if (!Number.isFinite(v)) {
    return '';
  }
  const rounded: number = Math.round(v * 10000) / 10000;
  return String(rounded);
}

// 类目/系列名裁字（防超宽标签画穿槽位）
function clipChartLabel(text: string): string {
  return text.length > CHART_LABEL_MAX_CHARS ?
    text.substring(0, CHART_LABEL_MAX_CHARS) + '…' : text;
}

@Component
export struct ChatToolChartCard {
  // 渲染数据（宽松解析产物——构造期一次传入、组件寿命内不变；状态最小化不挂装饰器）
  spec: ChartSpecData = emptyChartSpec();
  @StorageProp('appColorMode') appColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 视图态下标（本组件内唯一 @State；0 = 图表 / 1 = 表格——与 viewItems 顺序同源；不持久化，
  // 重开卡回到图表态）
  @State viewIndex: number = 0;
  // 视图切换选项（顺序 = 下标映射，勿单独乱调）
  private viewItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '图表' },
    { text: '表格' }
  ]);
  // 画布可见位与实测宽（非渲染输入——普通成员；onVisibleAreaChange 门控 + onAreaChange 重绘）
  private canvasVisible: boolean = true;
  private canvasAreaWidth: number = 0;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  // 轴值 → 画布位（含 log 变换与 min/max 覆盖；lo/hi 已按轴设置归一，log 轴取 log10）。
  // 命名按通用轴措辞：y 轴传（上缘、下缘）得纵坐标；x 轴传（左缘、右缘）得横坐标
  private axisValueY(value: number, lo: number, hi: number, log: boolean, edgeStart: number,
    edgeEnd: number): number {
    const v: number = log ? Math.log10(value) : value;
    const ratio: number = hi > lo ? (v - lo) / (hi - lo) : 0.5;
    return edgeEnd - ratio * (edgeEnd - edgeStart);
  }

  // 数值轴刻度（线性：1/2/5×10^k 走步长，log：整十次幂）——返回 [值, log值] 对
  private axisTicks(lo: number, hi: number, log: boolean): number[] {
    const ticks: number[] = [];
    if (log) {
      const from: number = Math.ceil(lo);
      const to: number = Math.floor(hi);
      for (let p = from; p <= to; p++) {
        ticks.push(Math.pow(10, p));
      }
      return ticks;
    }
    const span: number = hi - lo;
    if (!(span > 0)) {
      ticks.push(lo);
      return ticks;
    }
    const rough: number = span / CHART_TICK_COUNT;
    const mag: number = Math.pow(10, Math.floor(Math.log10(rough)));
    const norm: number = rough / mag;
    const step: number = (norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 5 ? 5 : 10) * mag;
    let t: number = Math.ceil(lo / step) * step;
    while (t <= hi + step * 0.001 && ticks.length < 12) {
      ticks.push(t);
      t += step;
    }
    return ticks;
  }

  // 值序列的线性域（min/max 覆盖 + log 前值域；空集回 [0,1]）
  private valueDomain(values: number[], axis: ChartAxisData): number[] {
    let lo: number = Number.POSITIVE_INFINITY;
    let hi: number = Number.NEGATIVE_INFINITY;
    for (const v of values) {
      if (!Number.isFinite(v)) {
        continue;
      }
      if (v < lo) {
        lo = v;
      }
      if (v > hi) {
        hi = v;
      }
    }
    if (!Number.isFinite(lo) || !Number.isFinite(hi)) {
      return [0, 1];
    }
    if (Number.isFinite(axis.min)) {
      lo = axis.min;
    }
    if (Number.isFinite(axis.max)) {
      hi = axis.max;
    }
    if (hi <= lo) {
      hi = lo + 1;
    }
    return [lo, hi];
  }

  // 首绘 + 重绘（onReady / onAreaChange / 重新可见三入口；不可见期不出指令）
  private drawChart(): void {
    if (!this.canvasVisible) {
      return;
    }
    const ctx: CanvasRenderingContext2D = this.context;
    const w: number = this.canvasAreaWidth > 0 ? this.canvasAreaWidth : ctx.width;
    const h: number = ctx.height > 0 ? ctx.height : CHART_CANVAS_HEIGHT;
    if (!(w > 0) || !(h > 0)) {
      return; // 0 尺寸画布不可用（onReady 前/极窄态——等下一触发）
    }
    ctx.clearRect(0, 0, w, h);
    const plotLeft: number = CHART_PAD_LEFT;
    const plotRight: number = w - CHART_PAD_RIGHT;
    const plotTop: number = CHART_PAD_TOP;
    const plotBottom: number = h - CHART_PAD_BOTTOM;
    if (plotRight - plotLeft < 24 || plotBottom - plotTop < 24) {
      return; // 极窄宿主：不画（防负几何指令）
    }
    if (this.spec.style === 'scatter') {
      this.drawScatter(plotLeft, plotRight, plotTop, plotBottom);
    } else {
      this.drawCategoryChart(plotLeft, plotRight, plotTop, plotBottom);
    }
  }

  // 网格与 y 刻度（值域 [,] 已归一；log 轴标签取原值 10^t）
  private drawGrid(loRaw: number, hiRaw: number, log: boolean, plotLeft: number, plotRight: number,
    plotTop: number, plotBottom: number): void {
    const ctx: CanvasRenderingContext2D = this.context;
    const lo: number = log ? Math.log10(loRaw > 0 ? loRaw : 1) : loRaw;
    const hi: number = log ? Math.log10(hiRaw > 0 ? hiRaw : 1) : hiRaw;
    const ticks: number[] = this.axisTicks(lo, hi, log);
    ctx.strokeStyle = cardBorderColor(this.appColorMode);
    ctx.lineWidth = 1;
    ctx.font = '10vp sans-serif';
    ctx.textAlign = 'right';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = chartAxisTextColor(this.appColorMode);
    for (const t of ticks) {
      const y: number = this.axisValueY(log ? Math.pow(10, t) : t, lo, hi, log, plotTop, plotBottom);
      if (y < plotTop - 1 || y > plotBottom + 1) {
        continue;
      }
      ctx.beginPath();
      ctx.moveTo(plotLeft, y);
      ctx.lineTo(plotRight, y);
      ctx.stroke();
      ctx.fillText(formatTickValue(log ? Math.pow(10, t) : t), plotLeft - 6, y);
    }
  }

  // 图形区下方 x 轴标签（类目：均匀取至多 CHART_MAX_X_LABELS 个；数值轴：刻度走 drawGrid 侧）
  private drawXLabels(labels: string[], slotCount: number, plotLeft: number, slotW: number,
    plotBottom: number): void {
    if (labels.length !== slotCount || slotCount === 0) {
      return;
    }
    const ctx: CanvasRenderingContext2D = this.context;
    const stride: number = Math.max(1, Math.ceil(slotCount / CHART_MAX_X_LABELS));
    ctx.font = '10vp sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'top';
    ctx.fillStyle = chartAxisTextColor(this.appColorMode);
    for (let i = 0; i < slotCount; i += stride) {
      ctx.fillText(clipChartLabel(labels[i]), plotLeft + slotW * (i + 0.5), plotBottom + 4);
    }
  }

  // line / bar（类目轴）：values 数组，y 值域 = 数据域（bar 恒含 0；min/max/log 覆盖）
  private drawCategoryChart(plotLeft: number, plotRight: number, plotTop: number,
    plotBottom: number): void {
    const ctx: CanvasRenderingContext2D = this.context;
    const spec: ChartSpecData = this.spec;
    const allValues: number[] = [];
    let maxLen: number = 0;
    for (const s of spec.series) {
      for (const v of s.values) {
        allValues.push(v);
      }
      if (s.values.length > maxLen) {
        maxLen = s.values.length;
      }
    }
    if (maxLen === 0) {
      return;
    }
    const domain: number[] = this.valueDomain(allValues, spec.yAxis);
    let lo: number = domain[0];
    let hi: number = domain[1];
    if (spec.style === 'bar') {
      lo = lo > 0 ? 0 : lo; // bar 恒从 0（下探含负值柱）
      hi = hi < 0 ? 0 : hi;
    }
    const yLog: boolean = spec.yAxis.log && lo > 0 && hi > 0;
    const loT: number = yLog ? Math.log10(lo) : lo;
    const hiT: number = yLog ? Math.log10(hi) : hi;
    this.drawGrid(lo, hi, yLog, plotLeft, plotRight, plotTop, plotBottom);
    const slotW: number = (plotRight - plotLeft) / maxLen;
    let labels: string[] = spec.categories;
    if (labels.length !== maxLen) {
      labels = [];
      for (let i = 0; i < maxLen; i++) {
        labels.push(String(i + 1));
      }
    }
    this.drawXLabels(labels, maxLen, plotLeft, slotW, plotBottom);
    if (spec.style === 'bar') {
      const groupW: number = slotW * 0.72;
      const barW: number = Math.max(1, groupW / spec.series.length);
      const zeroY: number = this.axisValueY(yLog ? 1 : 0, loT, hiT, yLog, plotTop, plotBottom);
      for (let j = 0; j < spec.series.length; j++) {
        ctx.fillStyle = CHART_SERIES_COLORS[j % CHART_SERIES_COLORS.length];
        const values: number[] = spec.series[j].values;
        for (let i = 0; i < values.length; i++) {
          const v: number = values[i];
          if (!Number.isFinite(v)) {
            continue;
          }
          const y: number = this.axisValueY(v, loT, hiT, yLog, plotTop, plotBottom);
          const x: number = plotLeft + slotW * i + (slotW - groupW) / 2 + j * barW;
          const top: number = Math.min(y, zeroY);
          const height: number = Math.max(1, Math.abs(zeroY - y));
          ctx.fillRect(x, top, Math.max(1, barW - 1), height);
        }
      }
      return;
    }
    // line：逐系列折线（非有限值断线）
    for (let j = 0; j < spec.series.length; j++) {
      const values: number[] = spec.series[j].values;
      ctx.strokeStyle = CHART_SERIES_COLORS[j % CHART_SERIES_COLORS.length];
      ctx.lineWidth = 1.5;
      ctx.lineJoin = 'round';
      ctx.lineCap = 'round';
      ctx.beginPath();
      let started: boolean = false;
      for (let i = 0; i < values.length; i++) {
        const v: number = values[i];
        if (!Number.isFinite(v) || (yLog && v <= 0)) {
          started = false; // 断线
          continue;
        }
        const x: number = plotLeft + slotW * (i + 0.5);
        const y: number = this.axisValueY(v, loT, hiT, yLog, plotTop, plotBottom);
        if (started) {
          ctx.lineTo(x, y);
        } else {
          ctx.moveTo(x, y);
          started = true;
        }
      }
      ctx.stroke();
    }
  }

  // scatter（数值双轴）：points 数组，双轴各自值域（min/max/log 覆盖）
  private drawScatter(plotLeft: number, plotRight: number, plotTop: number,
    plotBottom: number): void {
    const ctx: CanvasRenderingContext2D = this.context;
    const spec: ChartSpecData = this.spec;
    const xs: number[] = [];
    const ys: number[] = [];
    for (const s of spec.series) {
      for (const p of s.points) {
        xs.push(p.x);
        ys.push(p.y);
      }
    }
    if (xs.length === 0) {
      return;
    }
    const xd: number[] = this.valueDomain(xs, spec.xAxis);
    const yd: number[] = this.valueDomain(ys, spec.yAxis);
    const xLog: boolean = spec.xAxis.log && xd[0] > 0 && xd[1] > 0;
    const yLog: boolean = spec.yAxis.log && yd[0] > 0 && yd[1] > 0;
    const xLo: number = xLog ? Math.log10(xd[0]) : xd[0];
    const xHi: number = xLog ? Math.log10(xd[1]) : xd[1];
    const yLo: number = yLog ? Math.log10(yd[0]) : yd[0];
    const yHi: number = yLog ? Math.log10(yd[1]) : yd[1];
    this.drawGrid(yd[0], yd[1], yLog, plotLeft, plotRight, plotTop, plotBottom);
    for (let j = 0; j < spec.series.length; j++) {
      ctx.fillStyle = CHART_SERIES_COLORS[j % CHART_SERIES_COLORS.length];
      for (const p of spec.series[j].points) {
        if (!Number.isFinite(p.x) || !Number.isFinite(p.y) ||
          (xLog && p.x <= 0) || (yLog && p.y <= 0)) {
          continue;
        }
        const x: number = this.axisValueY(p.x, xLo, xHi, xLog, plotRight, plotLeft);
        const y: number = this.axisValueY(p.y, yLo, yHi, yLog, plotTop, plotBottom);
        ctx.beginPath();
        ctx.arc(x, y, CHART_SCATTER_DOT_RADIUS, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  }

  // 图例行（简式：色块 + 系列名；同名按序色循环）——Flex 换行有界（≤12 系列）
  @Builder
  ChartLegend() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.spec.series, (s: ChartSeriesData, index: number): void => {
        Row() {
          Column()
            .width(8)
            .height(8)
            .borderRadius(2)
            .backgroundColor(CHART_SERIES_COLORS[index % CHART_SERIES_COLORS.length])
          Text(clipChartLabel(s.name))
            .fontSize(11)
            .fontColor(cardDescColor())
            .margin({ left: 4 })
        }
        .margin({ right: 10, top: 2 })
      }, (s: ChartSeriesData, index: number): string => index.toString() + '#' + s.name)
    }
    .width('100%')
  }

  // 表格态（数值兜底视图；有界：列 ≤5 系列、行 ≤12 + 注记行）——首列 = 类目/序号
  @Builder
  ChartTable() {
    Column({ space: 4 }) {
      Row() {
        Text('').layoutWeight(1)
        ForEach(this.spec.series.slice(0, CHART_TABLE_MAX_SERIES),
          (s: ChartSeriesData, index: number): void => {
          Row() {
            Column()
              .width(8)
              .height(8)
              .borderRadius(2)
              .backgroundColor(CHART_SERIES_COLORS[index % CHART_SERIES_COLORS.length])
            Text(clipChartLabel(s.name))
              .fontSize(11)
              .fontColor(cardDescColor())
              .margin({ left: 4 })
          }
          .layoutWeight(1)
        }, (s: ChartSeriesData, index: number): string => index.toString() + '#' + s.name)
      }
      .width('100%')
      ForEach(this.tableRowIndexes(), (rowIndex: number): void => {
        Row() {
          Text(this.tableRowLabel(rowIndex))
            .fontSize(11)
            .fontColor(cardDescColor())
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          ForEach(this.spec.series.slice(0, CHART_TABLE_MAX_SERIES),
            (s: ChartSeriesData, index: number): void => {
            Text(this.tableCellText(s, rowIndex))
              .fontSize(11)
              .fontColor(cardTitleColor())
              .layoutWeight(1)
              .maxLines(1)
          }, (s: ChartSeriesData, index: number): string => index.toString() + '#' + rowIndex.toString())
        }
        .width('100%')
      }, (rowIndex: number): string => rowIndex.toString())
      if (this.tableNote() !== '') {
        Text(this.tableNote())
          .fontSize(11)
          .fontColor(cardDescColor())
          .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private tableRowCount(): number {
    if (this.spec.style === 'scatter') {
      let n: number = 0;
      for (const s of this.spec.series) {
        if (s.points.length > n) {
          n = s.points.length;
        }
      }
      return n;
    }
    let n: number = 0;
    for (const s of this.spec.series) {
      if (s.values.length > n) {
        n = s.values.length;
      }
    }
    return n;
  }

  private tableRowIndexes(): number[] {
    const out: number[] = [];
    const limit: number = Math.min(this.tableRowCount(), CHART_TABLE_MAX_ROWS);
    for (let i = 0; i < limit; i++) {
      out.push(i);
    }
    return out;
  }

  private tableRowLabel(rowIndex: number): string {
    const cats: string[] = this.spec.categories;
    if (this.spec.style !== 'scatter' && cats.length > rowIndex) {
      return cats[rowIndex];
    }
    return String(rowIndex + 1);
  }

  private tableCellText(s: ChartSeriesData, rowIndex: number): string {
    if (this.spec.style === 'scatter') {
      const p: ChartPointData | undefined = s.points[rowIndex];
      return p === undefined ? '' : formatTickValue(p.x) + ', ' + formatTickValue(p.y);
    }
    const v: number | undefined = s.values[rowIndex];
    return v === undefined ? '' : formatTickValue(v);
  }

  // 注记行（列/行截断说明；无截断回 ''）
  private tableNote(): string {
    const notes: string[] = [];
    if (this.spec.series.length > CHART_TABLE_MAX_SERIES) {
      notes.push('另有 ' + (this.spec.series.length - CHART_TABLE_MAX_SERIES) + ' 个系列未列出');
    }
    const total: number = this.tableRowCount();
    if (total > CHART_TABLE_MAX_ROWS) {
      notes.push('仅列出前 ' + CHART_TABLE_MAX_ROWS + ' 行，共 ' + total + ' 行');
    }
    return notes.join('。');
  }

  build() {
    Column({ space: 4 }) {
      // 卡头行：标题（spec.title 缺省态用「图表」）+ 图表↔表格切换（SegmentBar 紧凑档，
      // 宽度约束见 CHART_VIEW_SEGMENT_WIDTH 注释；选项序 = 图表 → 表格）
      Row() {
        Text(this.spec.title !== '' ? this.spec.title : '图表')
          .fontSize(11)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Column() {
          SegmentBar({
            items: this.viewItems,
            selectedIndex: $viewIndex,
            compact: true
          })
        }
        .width(CHART_VIEW_SEGMENT_WIDTH)
        .height(SEGMENT_BAR_COMPACT_HEIGHT)
        .margin({ left: 8 })
      }
      .width('100%')
      if (this.viewIndex === 1) {
        this.ChartTable()
      } else {
        Canvas(this.context)
          .width('100%')
          .height(CHART_CANVAS_HEIGHT)
          .onReady((): void => {
            this.canvasVisible = true;
            this.drawChart();
          })
          // 旋转 / 分屏 / 折叠展开改卡宽后自绘新几何（onReady 只触发一次）
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            const width: number = newArea.width as number;
            if (Number.isFinite(width) && width > 0 && width !== this.canvasAreaWidth) {
              this.canvasAreaWidth = width;
              this.drawChart();
            }
          })
          // 不可见停绘（官方红线：指令堆积）——不可见期只记位，重新可见补齐一拍
          .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean): void => {
            this.canvasVisible = isVisible;
            if (isVisible) {
              this.drawChart();
            }
          })
      }
      if (this.spec.series.length > 0) {
        this.ChartLegend()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

// ═══ 正文图表行（「图表正文化」——展示项 kind='chart' 的渲染件）═══
// 职责一句话：**图表展示项在消息正文流里的宿主壳**——轮头行（本项为轮内首个上屏项时）+
// 卡体几何（卡底/圆角/内容内距/近侧距）+ 图表卡挂载。
// · 为何并入本件（宪法「反碎片下限」②③）：与图表卡同一功能域，非纯转接壳（卡体几何与轮头
//   判据都在本件消费）；不新开件的硬性动因 = 宿主 ChatPageContent 剔头后加行级壳即越 1200
//   硬线，本分支所属域 = 图表渲染。
// · 外壳几何与相邻消息卡分支同源（宿主只分派、不写几何）：左右近距 BUBBLE_PAD_NEAR + 上距
//   CARD_SPACING（行距模型 = 各行自持上距，见 ChatPageContent 的 List 注释），内容内距照
//   助手正文泡（14/14/10/10）。
// · 轮头行：item.head 为真（本项 = 轮内首个上屏项；轮首项可为步骤/正文/图表三载体之一，
//   判据单源在展示投影 buildDisplayItems）时挂卡外上方——与另两载体互斥、一轮只出一处；
//   模型名取轮级回填值。
// · 状态最小化：item 经 @ObjectLink 消费（chartSpec 由投影装配期算成、寿命内不变——本件
//   构建函数零解析）。
@Component
export struct ChatChartRow {
  @ObjectLink item: ChatDisplayItem;
  @StorageProp('appColorMode') appColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位只读订阅（消息列表内常驻工具卡即时面）
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;

  build() {
    Column({ space: 4 }) {
      if (this.item.head && this.item.msg !== null) {
        ChatRoundHeader({
          modelLabel: this.item.msg.modelLabel ?? ''
        })
      }
      Column() {
        ChatToolChartCard({ spec: this.item.chartSpec as ChartSpecData })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor(cardBg(this.appColorMode, this.cardAlphaLevel))
      .borderRadius(BUBBLE_RADIUS)
    }
    .width('100%')
    .padding({ left: BUBBLE_PAD_NEAR, right: BUBBLE_PAD_NEAR })
    .margin({ top: CARD_SPACING })
  }
}
