// 模型用量排行环形图组件（2026-09-08 排行卡图表切换笔，决明指令「模型用量排行新增饼状图
// 切换，卡右上角切换图标」）：本件 = **数据加工**（Top8 + 其余聚合 + 段色阶梯），渲染交
// 通用件 components/stats/RingChart（2026-09-09 提炼，存储管理页卡1 同源复用——官方
// DataPanel 环形调研结论见该件头注释）。
//   · values 数组上限 9 段（超出取前 9，d.ts/官方文档同义）——Top10 排行不可能全量入环：
//     取前 8 名 + 「其余」聚合灰段（= 最多 9 段闭环）；max 传 0 = 按总和比例铺满整环；
//   · 段色 valueColors：主蓝 ARGB 半透明阶梯（排行第 1 名最实、按名次渐淡——usageHeatColor
//     同手法单源视觉语言，半透明透卡底自动深浅适配）；「其余」段 = badgeBg 灰。
// 数据契约同 UsageBarChart/UsageHeatMap（坑16 热点：PageShell.content @BuilderParam 内
// 图组件禁 @Prop——排行行与总览经 @Link 下发，切档重查自动刷新）；纯派生（values/colors
// 均读时计算，无本地状态）。空态由页面守卫（总额 ≤ 0 不渲染本件，与占比分段条同条件）。
// ★ 渲染层刷新通道：RingChart 入参是普通成员（不随本件重渲更新）——build 内经键含数据
// 签名的 ForEach 下发（规范 §3 主通道「键变重建」，先例 PreferencesPage 恒单例纪元键）。
import { UsageByModelRow, UsageOverview } from '../../common/store/UsageStatsDb';
import { fmtCompact } from '../../common/store/UsageStatsCalc';
import { badgeBg, rampColor, usageAccentColor } from '../../common/Theme';
import { RingChart } from './RingChart';

// 环形图入环段数上限（DataPanel values ≤ 9：前 8 名 + 其余聚合灰段 = 9 封顶）
const RING_TOP_N: number = 8;
// 段色 rampColor 2026-09-17 提取共用至 Theme.ets（上下文用量面板分段条同手法——两消费
// 方单源）

@Component
export struct UsageRankRing {
  // 排行行（SQL 端 Top10，totalTokens 降序）与总览（分母 totalTokens + usedModels）——
  // 页面 @State 经 $ 语法 @Link 下发（坑16：图组件禁 @Prop）
  @Link byModel: UsageByModelRow[];
  @Link overview: UsageOverview | null;
  // 深浅色（段色阶梯 / 灰段 / 中心文字分治）
  @StorageProp('appColorMode') appColorMode: number = 1;

  // 时段总 token（其余段分母；总额 ≤ 0 页面侧不渲染本件，此处只做展示用兜底）
  private totalTokens(): number {
    return this.overview === null ? 0 : this.overview.totalTokens;
  }

  // 「其余」聚合量（= 总量 − 前 8 名和；> 0 才成段——与占比分段条灰段同分母同条件）
  private restTokens(): number {
    let shown: number = 0;
    const limit: number = Math.min(this.byModel.length, RING_TOP_N);
    for (let i = 0; i < limit; i++) {
      shown += this.byModel[i].totalTokens;
    }
    return this.totalTokens() - shown;
  }

  // 入环值序列：前 8 名 totalTokens + 「其余」聚合——段序即排行序
  private ringValues(): number[] {
    const values: number[] = [];
    const limit: number = Math.min(this.byModel.length, RING_TOP_N);
    for (let i = 0; i < limit; i++) {
      values.push(this.byModel[i].totalTokens);
    }
    if (this.restTokens() > 0) {
      values.push(this.restTokens());
    }
    return values;
  }

  // 段色：名次蓝阶梯 + （有其余段时）末段 badgeBg 灰——与列表排行序对应，无需逐段图例
  private ringColors(): string[] {
    const values: number[] = this.ringValues();
    const blueCount: number = Math.min(this.byModel.length, RING_TOP_N);
    const hasRest: boolean = this.restTokens() > 0;
    const colors: string[] = [];
    for (let i = 0; i < values.length; i++) {
      colors.push(hasRest && i === values.length - 1 ? badgeBg(this.appColorMode) :
        rampColor(this.appColorMode, i, blueCount));
    }
    return colors;
  }

  // 渲染层数据签名（键变重建通道：RingChart 入参为普通成员，本件重渲不更新它——规范 §3
  // 主通道；键含段值与色模式，切档重查/深浅色切换均触发重建）
  private ringKey(): string {
    return this.ringValues().join(',') + '|' + this.appColorMode;
  }

  build() {
    // ForEach 须与容器组件配合（官方《ForEach：循环渲染》原文「需要与容器组件配合使用」——
    // 组件 build 根直接放 ForEach 无父容器，2026-09-09 自检轮修正）；外层 Column 仅作容器，
    // width 100% 与 RingChart 根一致，布局等价
    Column() {
      ForEach([this.ringKey()], (_key: string) => {
        RingChart({
          values: this.ringValues(),
          colors: this.ringColors(),
          centerLabel: '总 token',
          centerValue: fmtCompact(this.totalTokens()),
          // 口径备注（排行段与列表名次对应、灰段聚合语义——替分段条原「卡底色漏出天然分段线」
          // 的自解释性，环段无间隙需文字说明）
          note: '环段按排行从深到浅，灰色为其余模型'
        })
      }, (key: string): string => key)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
