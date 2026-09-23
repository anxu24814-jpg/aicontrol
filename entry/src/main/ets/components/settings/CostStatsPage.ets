// 费用估计页（2026-09-10 方案-费用估计-20260910；设置页「用量统计+费用估计」组卡第二行
// push）：骨架照 UsageStatsPage——PageShell + 吸顶光感分段胶囊（近七天/近三十天/全部，
// 时段起点 rangeSinceMs 同源）+ Scroll 卡列 + loadSeq 连切守卫；无编辑无保存动作 →
// 返回无参 pop 不挂 onPop（坑17 口径）。
// 三卡自上而下：费用总览（StatGrid 四格 = 总费用/输入费用/缓存输入费用/输出费用 +
// 未配置提示行）→ 模型费用排行（占比分段条 + Top10 行，单形态不搬环形图切换键）→
// 用途分布（聊天/标题生成/记忆整理/测试连接/主动消息五类金额+占比条，全零用途行不显示）。
// 口径（方案 §0/§10）：模型价格 × token 用量折算的估算值，实际计费以服务商账单为准；
// 全局人民币、价格单位 = 元/百万 tokens；未配置价格的模型不计入任何金额（计数提示）；
// 缓存写入并入输入按输入价计（已知近似，帮助条目声明）；谷时按记录时间落点判价。
// 数据单源 = UsageStatsDb.queryCostEvents（全用途事件）+ ProviderDb.queryAllModels（价格
// map）；折算/聚合纯函数 = common/store/CostStatsCalc.ets（断言脚本钉死）；空态 = 时段内
// 无已配置价格模型的记录（pricedEventCount === 0，含读库失败降级形态）显示引导文案。
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { PageShell } from '../../common/PageShell';
import { SETTING_TITLE_COST_STATS } from '../../common/SettingSearch';
import { CARD_PANEL_WIDTH, CARD_SPACING, SEGMENT_BAR_HEIGHT, badgeBg, cardBg, cardDescColor,
  cardTitleColor, usageAccentColor } from '../../common/Theme';
import { queryCostEvents } from '../../common/store/UsageStatsDb';
import { ModelRow, queryAllModels } from '../../common/store/ProviderDb';
import { CostAggregate, CostByModelRow, CostByPurposeRow, CostEventInput,
  ModelPriceSourceRow, aggregateCosts, buildPriceMap, fmtCost, purposeLabel } from '../../common/store/CostStatsCalc';
import { UsageStatCell, buildCostCells, rangeSinceMs } from '../../common/store/UsageStatsCalc';
import { SegmentBar } from '../SegmentBar';
import { StatGrid } from '../stats/StatGrid';

@Component
export struct CostStatsPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 时段档（0 近七天默认 / 1 近三十天 / 2 全部）：@Watch 切档即重查（与用量统计页同款）
  @State @Watch('onRangeChange') private rangeIndex: number = 0;
  // 聚合结果（null = 首载失败降级，走空态卡）
  @State private agg: CostAggregate | null = null;
  // 总览四格值（loadStats 先算后赋 @Link 下发 StatGrid——坑16 同款，值构造在页内）
  @State private costCells: UsageStatCell[] = [];
  @State private loaded: boolean = false;
  @StorageProp('appColorMode') appColorMode: number = 1;
  // 重查序号守卫：快速连切时段时丢弃旧响应（后发查询的响应才算数）
  private loadSeq: number = 0;
  // 分段胶囊选项（与用量统计页逐字一致——两页时段口径同源）
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

  // 拉取与折算（两炮并行：时段内全用途事件 + 全量模型行价格 map；聚合纯函数在 calc 层）。
  // 失败 = toast 明示 + agg 维持旧值（首载失败 agg null 走空态卡，P0-1 不静默假成功）
  private loadStats(): void {
    const seq: number = ++this.loadSeq;
    const since: number = rangeSinceMs(this.rangeIndex, Date.now());
    Promise.all([queryCostEvents(since), queryAllModels()])
      .then((results: [CostEventInput[], ModelRow[]]): void => {
        if (seq !== this.loadSeq) {
          return; // 已有更新档查询发出，丢弃本次旧响应
        }
        const sourceRows: ModelPriceSourceRow[] = results[1].map((row: ModelRow):
          ModelPriceSourceRow => {
          return { providerId: row.providerId, modelId: row.modelId, priceConfig: row.priceConfig };
        });
        const agg: CostAggregate = aggregateCosts(results[0], buildPriceMap(sourceRows));
        // 连续赋值先算后赋（状态最小化条：同帧合并为一次刷新）。★ 四格构造 = UsageStatsCalc
        // 单源（2026-09-13 工具补齐三件：自页内私有方法外迁，get_cost_stats 工具引同一函数）
        this.agg = agg;
        this.costCells = buildCostCells(agg.totals.total, agg.totals.inputCost,
          agg.totals.cachedCost, agg.totals.outputCost);
        this.loaded = true;
      })
      .catch((e: Object): void => {
        if (seq !== this.loadSeq) {
          return;
        }
        this.getUIContext().getPromptAction().showToast(
          { message: '费用数据读取失败：' + (e as Error).message });
        this.loaded = true; // 首载失败也进展示态（agg null 分支渲染空态卡）
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

  // 卡1 费用总览（说明小字置于数据上方——功能设置卡布局次序规约；未配置提示行 N=0 不显）
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
      StatGrid({ cells: $costCells })
      if (this.agg !== null && this.agg.unpricedModels.length > 0) {
        Text(this.agg.unpricedModels.length + ' 个模型未配置价格，仅统计已配置部分')
          .fontSize(12)
          .fontColor(cardDescColor())
          .width('100%')
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(16)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  // 卡2 模型费用排行（占比分段条 + Top10 行——参照用量统计页排行卡占比条段自建单形态；
  // 未配置价格的模型不进排行，尾行计数提示；截断未展示同样提示）
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
        // 占比分段条：各模型费用占总额比（与用量统计页排行卡同形制）
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
    .borderRadius(16)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  // 卡3 用途分布（五类定序行——标签 + 占比条 + 金额；全零用途行不显示，全零时整卡
  // 不渲染见 Content 分支）
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
    .borderRadius(16)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  Content() {
    // Stack 叠加（UsageStatsPage 吸顶同款姿势）：内容滚动层 + 分段胶囊悬浮固定层
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column({ space: CARD_SPACING }) {
          if (!this.loaded) {
            Text('正在读取费用数据…')
              .fontSize(13)
              .fontColor(cardDescColor())
              .width(CARD_PANEL_WIDTH)
          } else if (this.agg === null || this.agg.pricedEventCount === 0) {
            // 空态卡（官方正色卡底——禁灰置）：时段内无已配置价格模型的记录（含首载失败
            // 降级形态）；引导到价格配置路径
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
            .borderRadius(16)
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

      // 分段胶囊悬浮固定层（SegmentBar 公共件参数定稿勿调，UsageStatsPage 同款）
      Column() {
        SegmentBar({ items: this.rangeItems, selectedIndex: $rangeIndex })
      }
      .width(CARD_PANEL_WIDTH)
      .margin({ top: this.topPad })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    PageShell({
      title: SETTING_TITLE_COST_STATS,
      content: (): void => {
        this.Content();
      }
    })
  }
}
