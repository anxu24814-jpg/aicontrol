// 模型能力卡：五项能力多选胶囊 + 重置；卡壳（宽/底/圆角）随本组件。纯展示 + 回调上行——
// 状态归属 ModelEditPage（caps / userModified 两键 @Link，翻转与重置都走父侧整组替换后回流刷新）。
// ★ 选项类 chips 范式（本卡为全仓先例：chips 是选项非按钮，不适用行内按钮形制）：未选 = 淡蓝底
// 蓝字，选中 = 强调蓝实底白字；1vp 透明边占位防切换时整块跳动。
// ★ 重置键 = 纯 Text（原 TEXTUAL Button 自带灰胶囊按压蒙层且行高大于标题）。
// 排版定稿：标题行顶对齐——标题与模型/模型类型卡同顶位、重置键右上角对称。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { MODEL_CAP_LABELS } from '../../common/store/ProviderDb';
import {
  CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor, selectChipBg, selectChipBorderColor,
  selectChipTextColor, CARD_RADIUS
} from '../../common/Theme';

@Component
export struct ModelCapsCard {
  // 五项能力选中态（@Link：本卡在 PageShell.content 内，宪法刷新黑名单禁 @Prop 下发热点——
  // 坑16 家族两度真机实锤；本卡对 caps 只读不写，翻转经 onToggleCap 上行父侧整组替换）
  @Link caps: boolean[];
  // 派生/覆盖态：false = 未手改——勾选态由父侧按 effectiveCaps 派生值回填，卡内显示「自动识别」
  // 说明行；点击翻转后父侧置 true（说明行消失——保存即固化）。重置 = 回 false + 勾选态回填派生
  // 值（恢复自动识别）。@Link 同上：异步回填若被 @Prop 首帧冻结，说明行永不出现
  @Link userModified: boolean;
  // 单项翻转回调（index，父侧整组替换）
  onToggleCap: (index: number) => void = () => {
  };
  // 重置回调（父侧恢复自动识别：标志位回 false + 勾选态回填模型名派生值，保存后回「从未手改」同态）
  onReset: () => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  build() {
    Column({ space: 10 }) {
      // 标题行顶对齐（重置键右上角对称，见头注释排版定稿）
      Row() {
        Text('模型能力')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
        Blank()
        Text('重置')
          .fontSize(13)
          .fontColor($r('sys.color.font_emphasize'))
          .onClick((): void => {
            this.onReset();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(MODEL_CAP_LABELS, (label: string, index: number) => {
          Text(label)
            .fontSize(13)
            .fontColor(selectChipTextColor(this.caps[index], this.appColorMode))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(14)
            // 未选 = 淡蓝底蓝字；选中 = 强调蓝实底白字（2026-10-25 反馈二笔）；1vp
            // 透明边占位，防切换时整块跳动
            .backgroundColor(selectChipBg(this.caps[index], this.appColorMode))
            .border({ width: 1, color: selectChipBorderColor(this.caps[index]) })
            .margin({ right: 8, bottom: 8 })
            .onClick((): void => {
              this.onToggleCap(index);
            })
        }, (label: string): string => label)
      }
      .width('100%')
      // 派生态说明行（仅未手改时显示；手动调整保存即固定）
      if (!this.userModified) {
        Text('能力由模型名自动识别，手动调整后固定')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }
}
