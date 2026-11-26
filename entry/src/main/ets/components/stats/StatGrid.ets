// 统计格网公共件（用量统计与费用估计两页同形制复用）：2 列「上标签下数值 + 右缘单位底对齐」
// 格网；格底 statCellBg 淡蓝（原 badgeBg 灰底，2026-11-09 视觉批次改判；两页同改）、圆角 12、内距 12。
// ★ 数据通道 = @Link（坑16：PageShell.content @BuilderParam 内禁 @Prop——ForEach 键含格值
// 即重建）。★ 本件不构造格值——文案与数值公式在调用方（单源见 UsageStatsCalc），本件只管
// 排版，禁加业务字段。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { UsageStatCell } from '../../common/store/UsageStatsCalc';
import { statCellBg, cardDescColor, cardTitleColor } from '../../common/Theme';

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
                // 单位靠单元格右缘底对齐（决明供图参考稿观感）
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
          .backgroundColor(statCellBg(this.appColorMode))
        }
      }, (cell: UsageStatCell): string => cell.key + '|' + cell.value + cell.unit)
    }
    .columnsTemplate('1fr 1fr')
    .columnsGap(8)
    .rowsGap(8)
    .height('auto')
    .width('100%')
    .scrollBar(BarState.Off)
  }
}
