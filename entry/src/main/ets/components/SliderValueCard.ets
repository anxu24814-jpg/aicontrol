// 通用滑轨值卡（自 AssistantContextPage.ContextSliderCard 原样迁出——多页同构，P2-4 提取）：
// 卡形制 = 标题行（标题 + 右侧「蓝值 + 箭头」编辑热区）+ 说明小字（滑块上方——宪法「功能
// 设置卡布局次序」条先说明后操作）+ 分割线 + 「标签 + 短滑轨」操作行（SLIDER_ROW_* 两常量
// 即改即全站生效，复合卡 PrefInputSendPage 同源复用）。
// ★ value 用 @Link（坑16 家族：@BuilderParam content 内 @Prop 不随父 @State 更新——拖动
// onChange 直写回父，编辑弹窗改父 @State 也同步进滑块进度）；format 为父传纯函数（创建时
// 传入不变，合法普通成员），随 @Link value 刷新文案。
// ★ showEdit：编辑键语义 = 弹数字输入做「滑块 step 之外的精确值」；离散小档域（如主动消息
// 间隔 1~24 八档）无中间值可输，传 false 隐藏整键，禁传 false 仍挂 onEdit（隐藏后回调永不
// 到达 = 死代码）。编辑热区 = 「蓝值 + 箭头」包同一 Row 整体可点（点值与点箭头同弹数字输入
//——决明「热区加上＞与左边字样」正解）；箭头形制 = GroupSettingCard 入口行同款裸箭头，
// 禁升灰底文字键（capsule 观感，已试撤回）；false 只渲染裸蓝值不可点。
// ★ rowLabel：非空 = 行式布局（分割线 + 标签 + 右侧 192vp 短滑轨；现全站统一形态），空串 =
// 原全宽滑轨。窄屏不足时标签/卡标题 flexShrink(1) 先让位，滑轨与编辑键保形。
// ★ 为何独立成文件而不并入 AssistantContextPage：多页消费方 + 属通用形制与页面职责无关；
// SliderRow.ets 是裸行形制（无卡底/无编辑键/无说明行），并入会把两形制混在一处（反碎片
// 下限①职责缝）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';
import {
 cardBg, cardBorderColor, cardDescColor, cardTitleColor, sliderTrackColor,
  CARD_PANEL_WIDTH, CARD_RADIUS
} from '../common/Theme';
import { IMMERSIVE_LEVEL_KEY, leveledUiMaterial, resolveEffectiveLevel } from '../common/ImmersiveLevel';
import { PREF_CARD_ALPHA_LEVEL_KEY, CARD_ALPHA_DEFAULT } from '../common/AppPreferences';

// 行式布局滑轨宽（与左侧标签同排、右对齐；标签挂 flexShrink(1) 兜窄屏，不足时标签先让位、
// 滑轨保宽）。导出 = 复合卡（PrefInputSendPage 开关 + 滑轨两卡）复用
export const SLIDER_ROW_WIDTH: number = 192;
// 行式布局下排行高（24vp：20vp 轨道上下各余 2vp）。行与 Slider 同挂本值，防行高与控件高
// 两处漂移
export const SLIDER_ROW_HEIGHT: number = 24;
// 非行式（rowLabel 空）时沿用 Slider 默认高度，显式写值只为让同一条属性链两档同形
const SLIDER_FULL_HEIGHT: number = 40;

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
  // 行式布局左标签（'' = 原全宽滑轨形态；非空 = 分割线 + 标签 + 右侧缩短滑轨）
  rowLabel: string = '';
  // 编辑键显隐（默认 true——上下文/输出/轮数/条数四方照旧；离散档域传 false 隐藏）
  showEdit: boolean = true;
  onEdit: () => void = () => {
  };
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位只读订阅：本卡是滑轨卡共享组件（含未来的透明度滑轨卡自身——拖动时
  // 用户指下这张卡也要变），订阅落共享组件覆盖全部消费实例
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;

  build() {
    Column({ space: 12 }) {
      Row() {
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          // 窄屏不足时标题先让位（三笔起滑轨加宽与右侧热区保形配套）——右侧蓝值与箭头保形
          .flexShrink(1)
        Blank()
        // 右侧蓝值（主题蓝——与滑块已选段同色系；读 @Link value 随刷）
        // ★ 编辑热区（四笔定稿）：showEdit true = 「蓝值 + 箭头」包同一 Row 整体可点（点值
        // 与点箭头同弹数字输入——决明「热区加上＞与左边字样」正解；箭头形制 =
        // GroupSettingCard 入口行同款裸箭头）；false = 只渲染裸蓝值不可点（离散档域）
        if (this.showEdit) {
          Row({ space: 4 }) {
            Text(this.format(this.value))
              .fontSize(15)
              .fontColor($r('sys.color.ohos_id_color_emphasize'))
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([cardDescColor()])
          }
          .alignItems(VerticalAlign.Center)
          .onClick((): void => {
            this.onEdit();
          })
        } else {
          Text(this.format(this.value))
            .fontSize(15)
            .fontColor($r('sys.color.ohos_id_color_emphasize'))
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // 说明小字置于滑轨（操作控件）上方——宪法「功能设置卡布局次序」条（先说明后操作，
      // 禁把说明垫在操作行下方作 footer；范式 = 功能模型页 TitleModelCard「显示行 → 说明
      // 小字 → 双键行」）
      Text(this.desc)
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      // 行式布局（rowLabel 非空）：分割线分开说明区与操作行（颜色同 cardBorderColor）；
      // 滑轨 192vp 靠右，左侧标签与滑轨垂直居中。空串 = 原全宽滑轨
      if (this.rowLabel !== '') {
        Divider()
          .strokeWidth(0.5)
          .color(cardBorderColor(this.appColorMode))
          .width('100%')
      }
      Row({ space: 12 }) {
        if (this.rowLabel !== '') {
          Text(this.rowLabel)
            // 左标签 = 行操作对象名（PrefInputSendPage「提醒间隔」行同款 15fp Medium 主字色）
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            // 窄屏不足时标签先让位——滑轨保 192 定宽
            .flexShrink(1)
          Blank()
        }
        Slider({ value: this.value, min: this.min, max: this.max, step: this.step,
          style: SliderStyle.InSet })
          .width(this.rowLabel === '' ? '100%' : SLIDER_ROW_WIDTH)
          // 下排行高：与 Row 同值（防两处漂移），装下 20vp 轨道（上下各余 2vp）；
          // 非行式沿用 40vp 默认高
          .height(this.rowLabel === '' ? SLIDER_FULL_HEIGHT : SLIDER_ROW_HEIGHT)
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
      .width('100%')
      .height(this.rowLabel === '' ? SLIDER_FULL_HEIGHT : SLIDER_ROW_HEIGHT)
      .alignItems(VerticalAlign.Center)
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode, this.cardAlphaLevel))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }
}
