// 费用估计页（设置页「用量统计+费用估计」组卡第二行 push）：骨架照 UsageStatsPage——PageShell +
// 吸顶光感分段胶囊（近七天/近三十天/全部，时段起点 rangeSinceMs 同源）+ Scroll 卡列 + loadSeq
// 连切守卫；无保存动作 → 返回无参 pop 不挂 onPop（坑17）。
// 三卡：费用总览（2026-11-09 改版 = 用量页 TokenCard 同形制：大字总额 + 等高信息行 + 分割线
// + 输入/缓存/输出三列 + 未配置提示行，info 卡色底）→ 模型费用排行（占比分段条 + Top10 单形态，
// 不搬环形图切换键）→ 用途分布（五类金额+占比条，全零用途行不显示）。
// 口径：模型价格 × token 用量折算的估算值，实际计费以服务商账单为准；全局人民币、元/百万
// tokens；未配置价格的模型不计入金额（计数提示）；缓存写入并入输入按输入价计（已知近似）；
// 谷时按记录时间落点判价。数据单源 = UsageStatsDb.queryCostEvents + ProviderDb.queryAllModels；
// 折算/聚合纯函数 = CostStatsCalc.ets（断言钉死）；空态 = 时段内 pricedEventCount === 0。
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { PageShell } from '../../common/PageShell';
import { SETTING_TITLE_COST_STATS } from '../../common/SettingSearch';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, SEGMENT_BAR_HEIGHT, SEGMENT_BAR_BAND_TOP_INSET_STATS,
  badgeBg, cardBg, cardBorderColor, cardDescColor, cardTitleColor,
  usageAccentColor, CARD_RADIUS
} from '../../common/Theme';
import { queryCostEvents } from '../../common/store/UsageStatsDb';
import { ModelRow, queryAllModels } from '../../common/store/ProviderDb';
import { CostAggregate, CostByModelRow, CostByPurposeRow, CostEventInput,
  ModelPriceSourceRow, aggregateCosts, buildPriceMap, fmtCost, purposeLabel } from '../../common/store/CostStatsCalc';
import { UsageStatCell, buildCostCells, rangeSinceMs } from '../../common/store/UsageStatsCalc';
import { PageTopSegmentBand } from '../SegmentBar';

@Component
export struct CostStatsPage {
  // 页面存活守卫：迟到异步回调不写状态、不碰 UI、不上行；写库意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 时段档（0 近七天默认 / 1 近三十天 / 2 全部）：@Watch 切档即重查
  @State @Watch('onRangeChange') private rangeIndex: number = 0;

  // 标题栏下方带承载（HDS 路径；下移量取 STATS 档 16 = 本页现状——Theme 常量注释）
  @Builder
  TopSegmentBand() {
    PageTopSegmentBand({
      items: this.rangeItems,
      selectedIndex: $rangeIndex,
      inset: SEGMENT_BAR_BAND_TOP_INSET_STATS
    })
  }
  @State private agg: CostAggregate | null = null;
  // 总览四格值（loadStats 先算后赋；2026-11-09 起首卡大字取第 1 格、三列取后 3 格，
  // 页内 ForEach 直接消费——StatGrid 随首卡改版在本页退役，用量页仍用）
  @State private costCells: UsageStatCell[] = [];
  // 首卡信息行的所选时段日期范围（loadStats 先算后赋；空串 = 全部档零事件，不显行）
  @State private rangeLabel: string = '';
  @State private loaded: boolean = false;
  @StorageProp('appColorMode') appColorMode: number = 1;
  // 重查序号守卫：快速连切时段时丢弃旧响应（后发查询的响应才算数）
  private loadSeq: number = 0;
  private rangeItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '近七天' },
    { text: '近三十天' },
    { text: '全部' }
  ]);

  aboutToAppear(): void {
    this.loadStats();
  }

  private onRangeChange(): void {
    this.loadStats();
  }

  // 拉取与折算（两炮并行）；失败 = toast 明示 + agg 维持旧值（首载失败走空态卡，P0-1 不静默）
  private loadStats(): void {
    const seq: number = ++this.loadSeq;
    const reqRange: number = this.rangeIndex;
    // 同帧基准：查询窗口与日期标签共用这一次取的系统时间（comparisonSinceMs 同口径——
    // 禁在 then 里二次读 Date.now()，跨零点会把终点日期算成查询窗口之外的一天）
    const nowMs: number = Date.now();
    const since: number = rangeSinceMs(reqRange, nowMs);
    Promise.all([queryCostEvents(since), queryAllModels()])
      .then((results: [CostEventInput[], ModelRow[]]): void => {
        if (this.departed) {
          return;
        }
        if (seq !== this.loadSeq) {
          return; // 已有更新档查询发出，丢弃本次旧响应
        }
        const sourceRows: ModelPriceSourceRow[] = results[1].map((row: ModelRow):
          ModelPriceSourceRow => {
          return { providerId: row.providerId, modelId: row.modelId, priceConfig: row.priceConfig };
        });
        const agg: CostAggregate = aggregateCosts(results[0], buildPriceMap(sourceRows));
        // 连续赋值先算后赋（同帧合并为一次刷新）；四格构造 = UsageStatsCalc 单源
        this.agg = agg;
        this.costCells = buildCostCells(agg.totals.total, agg.totals.inputCost,
          agg.totals.cachedCost, agg.totals.outputCost);
        this.rangeLabel = this.buildRangeLabel(reqRange, since, results[0], nowMs);
        this.loaded = true;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        if (seq !== this.loadSeq) {
          return;
        }
        this.getUIContext().getPromptAction().showToast(
          { message: '费用数据读取失败：' + (e as Error).message });
        this.loaded = true; // 首载失败也进展示态（agg null 走空态卡）
      });
  }

  // 占比百分比串（分母 ≤ 0 回 '0'——与用量统计页 pctWidth 同口径；2 位小数防小占比丢精度）
  private pctOf(part: number): string {
    const total: number = this.agg === null ? 0 : this.agg.totals.total;
    if (total <= 0) {
      return '0';
    }
    return (part / total * 100).toFixed(2);
  }

  // 大字读数（costCells[0].value 形如 '¥12.34'——货币符号由单位 Span 承担，故去掉
  // 前缀；空数组兜底 '0'，与用量页 tokenTotalText 同款防御）
  private costTotalText(): string {
    return this.costCells.length > 0 ? this.costCells[0].value.replace('¥', '') : '0';
  }

  // 所选时段日期范围（何时到何时）：近七天/近三十天取 rangeSinceMs 的本地零点，全部档取
  // 时段内最早事件时间（吃 queryCostEvents 已返回的事件，零新查询）；同年只写一次年份，
  // 跨年补终点年份。无起点（全部档零事件）回空串，由信息行条件渲染吃掉。
  // 终点取 nowMs 入参而非现读系统时间——与 since 同帧同基准（comparisonSinceMs 同口径）。
  private buildRangeLabel(rangeIndex: number, since: number, events: CostEventInput[],
    nowMs: number): string {
    let startMs: number = since;
    if (rangeIndex === 2) {
      let earliest: number = 0;
      for (const event of events) {
        if (event.createdAt > 0 && (earliest === 0 || event.createdAt < earliest)) {
          earliest = event.createdAt;
        }
      }
      startMs = earliest;
    }
    if (startMs <= 0) {
      return '';
    }
    const start: Date = new Date(startMs);
    const end: Date = new Date(nowMs);
    const sameYear: boolean = start.getFullYear() === end.getFullYear();
    return start.getFullYear() + '年' + (start.getMonth() + 1) + '月' + start.getDate() +
      '日 至 ' + (sameYear ? '' : end.getFullYear() + '年') +
      (end.getMonth() + 1) + '月' + end.getDate() + '日';
  }

  // 卡1 费用总览（2026-11-09 视觉批次：形制对齐用量页 TokenCard——标题 + 说明小字 →
  // 大字总额 → 等高信息行 → 卡内分割线 → 输入/缓存/输出三列；反馈笔改 info 卡色底。
  // 数据层 buildCostCells 四格零改动：第 1 格作大字、后 3 格作三列；说明小字仍在数据上方
  //（功能设置卡布局次序规约），未配置提示行落三列下方、N=0 不显）
  @Builder
  OverviewCard() {
    Column({ space: 10 }) {
      Text('费用总览')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .width('100%')
      Text('所选时段内已配置价格模型的折算估算，实际计费以服务商账单为准')
        .fontSize(12)
        .fontColor(cardDescColor())
        .width('100%')
      // 大字与单位 = 单 Text 双 Span 天然基线平齐（用量页首卡同款）
      Text() {
        Span(this.costTotalText())
          .fontSize(46)
          .fontWeight(FontWeight.Bold)
          .fontColor(cardTitleColor())
        Span(' 元')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardDescColor())
      }
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
      // 信息行：费用页无上期查询口径（不发第二炮 SQL），改显所选时段的日期范围；
      // 固定 20vp 等高占位与用量页首卡对齐——任何档卡高都不跳（切档不闪）
      Row() {
        if (this.rangeLabel !== '') {
          Text(this.rangeLabel)
            .fontSize(14)
            .maxFontSize(14)
            .minFontSize(11)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontWeight(FontWeight.Medium)
            .fontColor(cardDescColor())
        }
      }
      .height(20)
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Divider()
        .strokeWidth(1)
        .color(cardBorderColor(this.appColorMode))
        .width('100%')
      // 分割线下三列：数值在上、标签在下，列间竖线走官方 borderWidth 左边框。
      // ForEach 键覆盖格值（坑44/80：值随切档变，漏进键即静默冻结）
      Row() {
        ForEach(this.costCells.slice(1), (cell: UsageStatCell, index: number): void => {
          Column({ space: 4 }) {
            Text(cell.value)
              .fontSize(21)
              .maxFontSize(21)
              .minFontSize(14)
              .maxLines(1)
              .fontWeight(FontWeight.Bold)
              .fontColor(cardTitleColor())
            Text(cell.label)
              .fontSize(12)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .padding({ left: index > 0 ? 12 : 0 })
          .borderWidth({ left: index > 0 ? 1 : 0 })
          .borderColor(cardBorderColor(this.appColorMode))
        }, (cell: UsageStatCell): string => cell.key + '|' + cell.value)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      if (this.agg !== null && this.agg.unpricedModels.length > 0) {
        Text(this.agg.unpricedModels.length + ' 个模型未配置价格，仅统计已配置部分')
          .fontSize(12)
          .fontColor(cardDescColor())
          .width('100%')
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    // info 卡色（2026-11-09 反馈笔）：与 InfoCard 共用 app.color.info_card_bg 资源色，
    // 不加渐变、不叠卡底透明度档、不加描边（info 卡无形制描边）
    .backgroundColor($r('app.color.info_card_bg'))
    .alignItems(HorizontalAlign.Start)
  }

  // 卡2 模型费用排行（占比分段条 + Top10 行，单形态；未配置价格的模型不进排行，尾行计数提示）
  @Builder
  ModelRankCard() {
    Column({ space: 10 }) {
      Text('模型费用排行')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .width('100%')
      Text('Top 10 · 按费用排序')
        .fontSize(12)
        .fontColor(cardDescColor())
        .width('100%')
      if (this.agg !== null && this.agg.totals.total > 0) {
        Row({ space: 2 }) {
          ForEach(this.agg.byModel, (row: CostByModelRow): void => {
            Row()
              .width(this.pctOf(row.total) + '%')
              .height(8)
              .backgroundColor(usageAccentColor(this.appColorMode))
          }, (row: CostByModelRow): string => row.modelId + '|' + row.total)
        }
        .width('100%')
        .borderRadius(4)
        .clip(true)
      }
      if (this.agg === null || this.agg.byModel.length === 0) {
        Text('暂无已配置价格模型的记录')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      } else {
        ForEach(this.agg.byModel, (row: CostByModelRow, index: number): void => {
          Row() {
            Text('' + (index + 1))
              .fontSize(14)
              .fontWeight(index < 3 ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(cardDescColor())
              .width(24)
            Text(row.modelId)
              .fontSize(15)
              .fontColor(cardTitleColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text('¥' + fmtCost(row.total))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }, (row: CostByModelRow): string => row.modelId + '|' + row.total)
        if (this.agg.pricedModelCount > this.agg.byModel.length) {
          Text('其余 ' + (this.agg.pricedModelCount - this.agg.byModel.length) + ' 个模型未展示')
            .fontSize(12)
            .fontColor(cardDescColor())
            .width('100%')
        }
        if (this.agg.unpricedModels.length > 0) {
          Text('另有 ' + this.agg.unpricedModels.length + ' 个模型未配置价格，未计入排行')
            .fontSize(12)
            .fontColor(cardDescColor())
            .width('100%')
        }
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  // 卡3 用途分布（五类定序行——标签 + 占比条 + 金额；全零时整卡不渲染，见 Content 分支）
  @Builder
  PurposeCard() {
    Column({ space: 10 }) {
      Text('用途分布')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .width('100%')
      Text('按功能场景汇总的折算费用')
        .fontSize(12)
        .fontColor(cardDescColor())
        .width('100%')
      ForEach(this.agg === null ? [] : this.agg.byPurpose, (row: CostByPurposeRow): void => {
        if (row.total > 0) {
          Row({ space: 8 }) {
            Text(purposeLabel(row.purpose))
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(72)
            // 占比条：底槽 badgeBg + 填充段强调色（宽 = 占总额百分比）
            Row() {
              Row()
                .width(this.pctOf(row.total) + '%')
                .height(6)
                .borderRadius(3)
                .backgroundColor(usageAccentColor(this.appColorMode))
            }
            .layoutWeight(1)
            .height(6)
            .borderRadius(3)
            .backgroundColor(badgeBg(this.appColorMode))
            Text('¥' + fmtCost(row.total))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(cardTitleColor())
              .width(88)
              .textAlign(TextAlign.End)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
      }, (row: CostByPurposeRow): string => row.purpose + '|' + row.total)
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  Content() {
    // Stack 叠加（UsageStatsPage 吸顶同款姿势）：内容滚动层
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column({ space: CARD_SPACING }) {
          if (!this.loaded) {
            Text('正在读取费用数据…')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
          } else if (this.agg === null || this.agg.pricedEventCount === 0) {
            // 空态卡（官方正色卡底——禁灰置）：时段内无已配置价格模型的记录（含首载失败降级）
            Column({ space: 8 }) {
              Text('暂无费用数据')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(cardTitleColor())
              Text('费用估计按模型价格折算用量得出。先在 设置 → 服务商管理 打开服务商详情，在模型页签点开模型的编辑页，于「模型价格」卡填写价格。配置后新记录与历史记录都会折算，未配置价格的模型不计入。')
                .fontSize(13)
                .fontColor(cardDescColor())
            }
            .alignItems(HorizontalAlign.Start)
            .width(CARD_PANEL_WIDTH)
            .padding(16)
            .backgroundColor(cardBg(this.appColorMode))
            .borderRadius(CARD_RADIUS)
          } else {
            this.OverviewCard()
            this.ModelRankCard()
            // 用途分布卡：四类全零（只发生过未计价消耗或无记录）不渲染空卡
            if (this.agg !== null && this.agg.totals.total > 0) {
              this.PurposeCard()
            }
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .padding({
          top: Math.max(this.topPad, 0) + SEGMENT_BAR_HEIGHT + CARD_SPACING,
          bottom: this.bottomPad + 16
        })
      }
      .width('100%')
      .height('100%')
      // 滚动内容不足视口时顶对齐（坑18：Scroll align 默认 Center 会垂直居中）
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  build() {
    PageShell({
      title: SETTING_TITLE_COST_STATS,
      // 标题栏下方带承载（HDS 分段胶囊经此挂载）
      titleBarBottom: (): void => {
        this.TopSegmentBand();
      },
      titleBarBottomInset: SEGMENT_BAR_BAND_TOP_INSET_STATS,
      content: (): void => {
        this.Content();
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
