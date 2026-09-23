// 通用滑轨行（2026-08-22 自 AdjustStageView.ets 提取——裁剪页缩放滑轨与调整页模糊/遮罩
// 滑轨同构，P2-4 重复 2 次提取共用；AdjustStageView 原实现逻辑零改动迁出，仅新增
// valueFormatter 参数）：节标题（左） + 当前值（右，默认百分比「NN%」，可经 valueFormatter
// 定制） + 官方 InSet 无级滑块（0~100 step 1）+ 沉浸光感滑轨材质（形态同「外观显示」档位
// 滑块；systemMaterial 随沉浸光感总档，「无」档显式关闭）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';
import { IMMERSIVE_LEVEL_KEY, leveledUiMaterial, resolveEffectiveLevel } from '../common/ImmersiveLevel';
import { cardTitleColor, sliderTrackColor } from '../common/Theme';

@Component
export struct SliderRow {
  title: string = '';
  // 当前百分比：@Prop 跟随父 @State 同步刷新（LevelSlider 先例；普通成员不触发重渲染）
  @Prop value: number = 0;
  // mode 透传官方 SliderChangeMode（2026-08-21 优化：调用方据此在松手/点击时跳过节流强制
  // 刷新预览——拖动中最后一帧可能被节流跳过，预览与滑轨终值不一致；Begin/Moving/End/Click）
  onChange: (v: number, mode: SliderChangeMode) => void = (v: number, mode: SliderChangeMode) => {
  };
  // 数值显示格式化（2026-08-22 裁剪页缩放滑轨新增；默认 = 现行为「NN%」，调整页两滑轨
  // 不传即保持原样；裁剪页传倍数格式「×N.N」，见 CropStageView 缩放滑轨）
  valueFormatter: (v: number) => string = (v: number) => {
    return Math.round(v) + '%';
  };
  // 沉浸光感整体档位（滑轨材质驱动；2026-09-12 分项退役前含「其他控件」分项）+ 系统颜色模式
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  build() {
    Column() {
      Row() {
        Text(this.title)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(cardTitleColor())
        Blank()
        Text(this.valueFormatter(this.value))
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
      Slider({ value: this.value, min: 0, max: 100, step: 1, style: SliderStyle.InSet })
        .width('100%')
        .trackThickness(20)
        .blockSize({ width: 12, height: 12 })
        .trackBorderRadius(10)
        .trackColor(sliderTrackColor(this.appColorMode))
        .sliderInteractionMode(SliderInteraction.SLIDE_AND_CLICK)
        .borderRadius(10)
        // 材质：总档「无」经 resolveEffectiveLevel 归一 -1 后由 leveledUiMaterial 内部收敛
        // 关闭（单一来源，2026-08-22 审查去掉调用点冗余三元守卫）
        .systemMaterial(leveledUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
          resolveEffectiveLevel(this.immersiveLevel), false))
        .onChange((v: number, mode: SliderChangeMode) => {
          this.onChange(v, mode);
        })
    }
    .width('100%')
  }
}
