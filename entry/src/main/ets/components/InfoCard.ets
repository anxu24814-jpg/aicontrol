// info 提示蓝卡（记忆两页组卡化笔抽共用；形制单源 = 挂载管理页页首 info 卡先例）：
// 行内 info_circle 符号（项目主蓝 usageAccentColor）+ 13fp 正文
//（cardTitleColor 浅底黑字 / 深底白字），底色 app.color.info_card_bg（base #E8EEFB /
// dark #17223A 浅深分治），圆角 CARD_RADIUS（20），卡宽 CARD_PANEL_WIDTH。
// 扩展（提示语统一笔）：①可选 title（16fp Medium，对齐说明卡标题形制）——
// 原说明卡「标题 + 正文」两排区分迁入 info 卡时保留；②text / title 改 @Prop——
// 动态文案（挂载浏览失效两因、日志占用行等）随调用方状态刷新，静态消费方行为不变；
// ③可选 fullWidth（能力位，默认 false）——宿主容器自带水平 16 padding 的列表态
//（工作区文件夹/临时段列表首项先例，规范 §4.8 形态①）传 true 改 width('100%') 与
// 行卡对齐，缺省仍挂 CARD_PANEL_WIDTH。
// ★ 首行对齐（决明「只有一行文字时图标和文字对不齐」）：外层 Row 的 Top 对齐
// 保留（多行正文时图标仍贴首行），图标改为「盒高 = 首行行高、盒内垂直居中」——单行正文时
// 图标与文字视觉同心；符号占位显式 18（= fontSize；官方 d.ts：SymbolGlyph 的 width/height
// 只改占位、不改符号显示大小）。两个行高常量同时供 Text.lineHeight 与图标盒高，是真机微调
// 旋钮（改一处两处同步）。
import { CARD_PANEL_WIDTH, cardTitleColor, usageAccentColor, CARD_RADIUS } from '../common/Theme';

const INFO_TITLE_LINE_HEIGHT: number = 22;
const INFO_TEXT_LINE_HEIGHT: number = 18;

@Component
export struct InfoCard {
  @Prop title: string = '';
  @Prop text: string = '';
  fullWidth: boolean = false;
  @StorageProp('appColorMode') appColorMode: number = 0;

  build() {
    Row({ space: 8 }) {
      // 首行对齐盒：盒高 = 首行行高（有 title 取标题行 22，无 title 取正文行 18），
      // 符号占位 18 在盒内垂直居中——单行正文时图标与文字同心；多行正文时图标仍只
      // 对齐首行（外层 Row 保持 Top）。
      Row() {
        SymbolGlyph($r('sys.symbol.info_circle'))
          .fontSize(18)
          .height(18)
          .fontColor([usageAccentColor(this.appColorMode)])
      }
      .height(this.title !== '' ? INFO_TITLE_LINE_HEIGHT : INFO_TEXT_LINE_HEIGHT)
      .alignItems(VerticalAlign.Center)

      Column({ space: 3 }) {
        if (this.title !== '') {
          Text(this.title)
            .fontSize(16)
            .lineHeight(INFO_TITLE_LINE_HEIGHT)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .width('100%')
        }
        Text(this.text)
          .fontSize(13)
          .lineHeight(INFO_TEXT_LINE_HEIGHT)
          .fontColor(cardTitleColor())
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width(this.fullWidth ? '100%' : CARD_PANEL_WIDTH)
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.info_card_bg'))
    .borderRadius(CARD_RADIUS)
    .alignItems(VerticalAlign.Top)
  }
}
