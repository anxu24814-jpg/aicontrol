// 统计格网公共件（2026-09-10 费用估计笔自 UsageStatsPage 内私有 @Builder 提取——用量
// 统计与费用估计两页同形制复用，属本需求内复用非顺手重构）：2 列「上标签下数值 + 右缘
// 单位底对齐」格网；格底 badgeBg、圆角 12、内距 12（2026-09-07 决明拍板「8 卡去图标」
// 定稿排版原样随迁）。
// ★ 数据通道 = @Link（坑16 红线：PageShell.content @BuilderParam 内子组件 @Prop 首帧
// 冻结实锤，禁 @Prop 下发——父侧 loadStats 先算后赋、与触发态同帧合并刷新，本件
// ForEach 键含格值即重建）。★ 本件不构造格值——文案与数值公式在调用方（用量统计 =
// UsageStatsCalc.buildOverviewCells/buildTokenCells 单源；费用估计 = 页内四格），本件
// 只管排版，禁加业务字段。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { UsageStatCell } from '../../common/store/UsageStatsCalc';
import { badgeBg, cardDescColor, cardTitleColor } from '../../common/Theme';

@Component
export struct StatGrid {
  // 格数据（父 @State 数组 $ 下发；空数组 = 零格渲染）
  @Link cells: UsageStatCell[];
  @StorageProp('appColorMode') appColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  build() {
    Grid() {
      ForEach(this.cells, (cell: UsageStatCell): void => {
        GridItem() {
          Column({ space: 6 }) {
            Text(cell.label)
              .fontSize(14)
              .fontColor(cardTitleColor())
            Row() {
              Text(cell.value)
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor(cardTitleColor())
              if (cell.unit !== '') {
                // 单位靠单元格右缘底对齐（决明供图参考稿观感，随迁原样）
                Blank()
                Text(cell.unit)
                  .fontSize(13)
                  .fontColor(cardDescColor())
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Bottom)
          }
          .alignItems(HorizontalAlign.Start)
          .padding(12)
          .borderRadius(12)
          .backgroundColor(badgeBg(this.appColorMode))
        }
      }, (cell: UsageStatCell): string => cell.key + '|' + cell.value + cell.unit)
    }
    .columnsTemplate('1fr 1fr')
    .columnsGap(8)
    .rowsGap(8)
    .height('auto')
    .width('100%')
  }
}
