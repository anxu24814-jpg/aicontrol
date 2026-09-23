// 模型能力卡（2026-08-30 反馈轮 13 自 ModelEditPage.ets 域级最小拆出——该文件 399 行距
// 400 红线 1 行，本轮「重置键去胶囊遮罩」改动前按防屎山红线先拆本域）：五项能力多选
// 胶囊 + 重置；卡壳（宽/底/圆角）随本组件。纯展示 + 回调上行——状态归属 ModelEditPage
//（caps 布尔数组 @Link 订阅（2026-09-11 O6 改，原 @Prop 深拷贝），翻转/重置都走父侧整组
// 替换后回流刷新；本卡挂 PageShell.content 内，禁 @Prop 下发热点）。
// ★ 重置键 = 纯 Text（2026-08-30 反馈轮 13 领导指令「去掉点按的灰色胶囊遮罩，对齐」：
// 原 TEXTUAL Button 自带灰胶囊按压蒙层且行高大于标题——Text 无遮罩、行高与标题一致）。
// 排版定稿（轮 12）：标题行顶对齐——标题与模型/模型类型卡同顶位、重置键右上角对称。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { MODEL_CAP_LABELS } from '../../common/store/ProviderDb';
import { CARD_PANEL_WIDTH, badgeBg, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';

@Component
export struct ModelCapsCard {
  // 五项能力选中态（★ 2026-09-11 自检轮 O6 改 @Link：本卡与价格卡同在 PageShell.content
  //（@BuilderParam）之内，宪法刷新黑名单明令禁 @Prop 下发热点——坑16 家族两度真机实锤；
  // @Link 为规范 §3 指定正解，本仓同位置先例 = StatGrid / SegmentBar / SliderValueCard。
  // 本卡对 caps 只读不写：翻转经 onToggleCap 上行走父侧整组替换，不直写本值）
  @Link caps: boolean[];
  // 派生/覆盖态（2026-09-03 Cube 吸收 A1，v15）：false = 未手改——勾选态由父侧按
  // effectiveCaps 派生值回填，卡内显示「自动识别」说明行；点击翻转后父侧置 true
  //（说明行随之消失——保存即固化）。★ 2026-09-17 v33 重置语义修正：「重置」不再置 true，
  // 而是回 false + 勾选态回填派生值（恢复自动识别，说明行复现）。★ 同批 O6 改 @Link：
  // 本值同样是**异步回填**（queryModels 完成才赋），@Prop 若首帧冻结则该说明行永不出现
  //（旧形态兼容的默认 true 恰好掩盖之）
  @Link userModified: boolean;
  // 单项翻转回调（index，父侧整组替换）
  onToggleCap: (index: number) => void = () => {
  };
  // 重置回调（2026-09-17 v33 语义修正：父侧恢复自动识别——标志位回 false + 勾选态回填
  // 模型名派生值，保存后回「从未手改」同态；原「全 false 固化」口径作废）
  onReset: () => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  build() {
    Column({ space: 10 }) {
      // 标题行顶对齐（轮 12 定稿）
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
            .fontColor(this.caps[index] ? $r('sys.color.ohos_id_color_emphasize') : cardDescColor())
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(14)
            .backgroundColor(this.caps[index] ? $r('sys.color.comp_background_secondary') :
              badgeBg(this.appColorMode))
            .margin({ right: 8, bottom: 8 })
            .onClick((): void => {
              this.onToggleCap(index);
            })
        }, (label: string): string => label)
      }
      .width('100%')
      // 派生态说明行（未手改 = 能力由引擎按模型名自动识别；一旦手动调整保存即固定）
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
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }
}
