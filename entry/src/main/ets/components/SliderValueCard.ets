// 通用滑轨值卡（2026-09-09 上限可设置笔自 AssistantContextPage.ContextSliderCard 原样迁出
// ——上下文消息数/最大输出长度/工具调用轮数上限三处同构，P2-4「重复 2 次以上提取」）：
// 卡形制 = 标题行（标题 + 右侧蓝值 + square_and_pencil 编辑键〔弹 InputDialog 数字输入，
// 精确值不受滑块 step 限制〕）+ 12fp 灰说明小字 + 官方 InSet 滑块（形制同采样页/沉浸光感
// 档位页）。★ 2026-09-10 搜索条数卡笔起说明小字置于滑块上方（宪法「功能设置卡布局次序」
// 条——先说明后操作；原实现垫在滑块下方，四个消费方一并位移）。
// ★ value 用 @Link（坑16 家族：@BuilderParam content 内 @Prop 不随父 @State 更新——拖动
// onChange 直写回父，编辑弹窗改父 @State 也同步进滑块进度）；format 为父传纯函数（创建时
// 传入不变，合法普通成员），随 @Link value 刷新文案。
// ★ showEdit（2026-09-12 主动消息频次两卡笔新增，默认 true 零影响既有四方消费）：编辑键
// 语义 = 弹数字输入做「滑块 step 之外的精确值」（AssistantContextPage 头注释），离散小档
// 域（如主动消息间隔 1~24 八档）无中间值可输，传 false 隐藏整键，禁传 false 仍挂 onEdit
// （隐藏后回调永不到达 = 死代码）。
// ★ 为何独立成文件而不并入 AssistantContextPage：本卡现有四个消费方（上下文与输出页两卡 +
// 工具调用页的轮数上限卡与搜索结果条数卡），且属通用形制与页面职责无关；SliderRow.ets 是裸行
// 形制（无卡底/无编辑键/无说明行，三页在用），并入会把两形制混在一处，故独立（反碎片下限①职责缝）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';
import { cardBg, cardDescColor, cardTitleColor, sliderTrackColor, CARD_PANEL_WIDTH } from '../common/Theme';
import {
  IMMERSIVE_LEVEL_KEY, leveledUiMaterial, resolveEffectiveLevel
} from '../common/ImmersiveLevel';

@Component
export struct SliderValueCard {
  title: string = '';
  @Link value: number;
  min: number = 0;
  max: number = 100;
  step: number = 1;
  // 右侧蓝值文案（父传纯函数，含 0 值语义——'不限制'/'20 条'/'64K'）
  format: (v: number) => string = (v: number): string => String(v);
  desc: string = '';
  // 编辑键显隐（默认 true——上下文/输出/轮数/条数四方照旧；离散档域传 false 隐藏）
  showEdit: boolean = true;
  onEdit: () => void = () => {
  };
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  build() {
    Column({ space: 12 }) {
      Row() {
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
        Blank()
        // 右侧蓝值（主题蓝——与滑块已选段同色系；读 @Link value 随刷）
        Text(this.format(this.value))
          .fontSize(15)
          .fontColor($r('sys.color.ohos_id_color_emphasize'))
        // 编辑键（square_and_pencil 图标键——助手编辑页详情卡同款形制，弹数字输入；
        // showEdit false 整键不渲染——离散档域无精确输入语义）
        if (this.showEdit) {
          Button() {
            SymbolGlyph($r('sys.symbol.square_and_pencil'))
              .fontSize(18)
              .fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .onClick((): void => {
            this.onEdit();
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // 说明小字置于滑轨（操作控件）上方——宪法「功能设置卡布局次序」条（先说明后操作，
      // 禁把说明垫在操作行下方作 footer；范式 = 功能模型页 TitleModelCard「显示行 → 说明
      // 小字 → 双键行」）。★ 2026-09-10 搜索条数卡笔同笔调整：原实现说明在滑轨下方，
      // 四个消费方（上下文与输出页两卡 + 工具调用页上限卡与搜索条数卡）一并位移，同卡体
      // 内顺序统一
      Text(this.desc)
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      Slider({ value: this.value, min: this.min, max: this.max, step: this.step,
        style: SliderStyle.InSet })
        .width('100%')
        .trackThickness(20)
        .blockSize({ width: 12, height: 12 })
        .trackBorderRadius(10)
        // 半透明滑轨色（沉浸光感材质透出——LevelSlider/SliderRow 同款）
        .trackColor(sliderTrackColor(this.appColorMode))
        .sliderInteractionMode(SliderInteraction.SLIDE_AND_CLICK)
        .borderRadius(10)
        .systemMaterial(leveledUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
          resolveEffectiveLevel(this.immersiveLevel), false))
        .onChange((v: number) => {
          // 整数域（step 整数）+ 越界 clamp；@Link 直写回父 @State（拖动即时生效）
          this.value = Math.round(Math.min(Math.max(v, this.min), this.max));
        })
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }
}
