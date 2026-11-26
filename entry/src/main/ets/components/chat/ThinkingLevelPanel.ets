// 思考档位滑轨面板（★ 2026-11-25 思考档位滑轨笔，决明「把对话思考等级改为类似这种滑轨」+
// 「关闭就放滑轨最左端」+「档位前不用图标」）：聊天页标题栏热区的弹层内容——顶行左 = 模型入口
//（显示名 + 右箭头，点开模型选择半模态）、右 = 当前档名，下方一条带档位原点的官方 Slider；
// 拖动期只改本地预览，松手才上抛一次。
// · 承载 = 气泡（bindPopup），本件只管内容；圆角/宽度/材质/关闭链全在挂载点
//   （ChatTitleBarOverlay 的滑轨形态分支），故本件零色值字面量、零背景、零阴影。
// · 轨道序 ≠ 源序：源选项集 = ModelRegistry.MR_THINKING_OPTIONS_DEFAULT
//   ['', 'off', 'low', 'high', 'max']（'' 首位、off 次位），轨道按决明指令「关闭最左」重排为
//   off → '' → low → high → max；收窄域由 options 过滤自适应（thinkingStops 单源）。
//   ★ 五轮：单档死轨闸自挂载点迁到本件——stops 不足 2 档时整条 Slider 不渲染（卡片只剩模型
//   入口行），挂载点不再按档数翻形态；档序仍只此一处生成，禁第二份实现。
// · 上抛时机 = SliderChangeMode.End / Click 两种落定态；Begin/Moving 只更新本地预览
//   （previewIdx）。绝不逐帧上抛：上层 thinkingValue 是 @Link 真源，写它等于整条
//   标题栏→页面→请求组装链重建。
// · 同档重复点不重复提交（target !== value 才 onPick），防菜单路径的重复写点语义漂移。
// · 文案 = thinkingLevelLabel（'' → 自动 / off → 关闭 / low·high·max → 低·高·最高），与菜单
//   路径的 thinkingDisplayLabel 刻意分开——菜单回退路径须逐字节零回归。
// · 面板内图标口径（★ 五轮改判）：**档位名之前仍禁任何图标**（决明首轮「档位前不用图标」）；
//   模型入口的右箭头 `sys.symbol.chevron_right` 是本件唯一允许的 SymbolGlyph（恰一枚），
//   Image 仍全禁（assert-ui-shape 2293 组钉守）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { cardDescColor, cardTitleColor, selectedAccentBlue, sliderStepColor, sliderTrackColor,
  thinkingLevelTextColor, thinkingTopGradient } from '../../common/Theme';
import { thinkingLevelLabel } from './ChatParamChipBar';

// 模型名最大宽（vp）：面板宽 280 − 左右内距 28 = 内容区 252；右侧档位名 16fp×2 ≈ 32、
// 箭头 16、缝 2 ⇒ 252 − 32 − 16 − 2 = 202，取 196 留 6vp 余量。★ 面板宽度改判时本值须同步
//（宿主 `ChatTitleBarOverlay` 的 bindPopup width）。
const MODEL_NAME_MAX_WIDTH: number = 196;

// 轨道序生成（**全仓单源**：档序生成与面板内单档死轨闸共用；五轮起挂载点不再消费——闸随
// 滑轨形态恒在，档序只此一处生成）。「关闭」档只在支持域出现
// （options 含 'off' 且 offOk——语义与菜单路径完全一致）；'' 恒第二；其余按低→高→最高。
export function thinkingStops(options: string[], offOk: boolean): string[] {
  const out: string[] = [];
  if (offOk && options.includes('off')) {
    out.push('off');
  }
  if (options.includes('')) {
    out.push('');
  }
  const levels: string[] = ['low', 'high', 'max'];
  for (let i = 0; i < levels.length; i++) {
    if (options.includes(levels[i])) {
      out.push(levels[i]);
    }
  }
  return out;
}

@Component
export struct ThinkingLevelPanel {
  // 当前档位（真源在上层 @Link；本件只读，落值经 onPick 上抛）
  @Prop @Watch('syncPreview') value: string = '';
  // 源选项集（按 thinkingStops 过滤成轨道序）
  @Prop options: string[] = [''];
  // 「关闭」档可用（仅支持域——服务商方言能力，判据由上层传）
  @Prop offOk: boolean = false;
  // 当前模型显示名（★ 2026-11-25 五轮「模型思考热区合一」）：卡内顶部左侧模型入口文案，
  // 由宿主解析后传入（显示名优先、取不到回落模型 ID，空值兜底在宿主统一处理）——本件不查库、
  // 不做第二份回落。
  @Prop modelName: string = '';
  // 模型入口点击（宿主先收卡放守卫，再开模型选择半模态——本件只管上行）
  onOpenModel: () => void = (): void => {
  };
  // 档位落定回调（上层写回 thinkingValue）
  onPick: (option: string) => void = (_option: string): void => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 拖动期本地预览下标（不写上层；标题行随它实时变，这是拖动期唯一的手感反馈）
  @State private previewIdx: number = 0;

  aboutToAppear(): void {
    // 首次构建对齐当前档（popup 内容组件生命周期与显隐无关——d.ts 明示，故 @Watch 同步同链兜底）
    this.previewIdx = this.currentIndex();
  }

  // 外部值变化（菜单/换会话/偏好重置）时把预览拉回真值；拖动落定后值回流与预览同值，无跳变
  private syncPreview(): void {
    this.previewIdx = this.currentIndex();
  }

  private stops(): string[] {
    return thinkingStops(this.options, this.offOk);
  }

  private currentIndex(): number {
    const idx: number = this.stops().indexOf(this.value);
    return idx >= 0 ? idx : 0; // 脏值（收窄后存量非法档位）归 0，不抛错
  }

  private maxIndex(): number {
    const n: number = this.stops().length;
    return n > 0 ? n - 1 : 0;
  }

  private isTop(idx: number): boolean {
    return idx === this.maxIndex();
  }

  private labelOf(idx: number): string {
    const list: string[] = this.stops();
    return idx >= 0 && idx < list.length ? thinkingLevelLabel(list[idx]) : '';
  }

  // 档位名文字色（★ 2026-11-25 六轮，决明「关闭 自动到最高，依次为灰、黑、浅蓝、深蓝到紫」
  // → 真机回执「高低没区分，蓝色都用一样的」拍板）：源档位值经 stops() 取（与 labelOf 同链），
  // 色阶单源 = Theme 的 thinkingLevelTextColor；越界下标回落 ''（自动档主字色）——文案本身也已
  // 被 labelOf 置空，两者同链不留半态。轨道 selectedColor 不随本函数变（决明只点名档位名）。
  private labelColorOf(idx: number): ResourceColor {
    const list: string[] = this.stops();
    const option: string = idx >= 0 && idx < list.length ? list[idx] : '';
    return thinkingLevelTextColor(this.appColorMode, option);
  }

  build() {
    // 内距 = { left 14, right 14, top 12, bottom 16 }；顶行与轨道间距 10
    //（2026-11-25 四轮「卡整体略小」：16/16/14/18 + 间距 12 各收一档）
    Column({ space: 10 }) {
      // 顶行（★ 2026-11-25 五轮「模型思考热区合一」）：左 = 模型入口（显示名 + 右箭头，点击上行
      // 开模型半模态；宿主先收本卡再开面板），右 = 当前档位名（拖动期随 previewIdx 实时跟变）。
      // ★ 五轮修笔（决明「档位字号偏大，可以把它缩小统一」+「箭头字号也统一」）：模型名 / 档位名 /
      // 右箭头三者统一 16fp（档位名由 18fp 收到 16fp），文本行高统一 22。
      // 模型名单行省略、上限 MODEL_NAME_MAX_WIDTH（与面板宽度同账），空白由 Blank 吃掉
      // ——档位名 flexShrink(0) 永不被挤掉。
      Row() {
        Row({ space: 2 }) {
          Text(this.modelName)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .lineHeight(22)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: MODEL_NAME_MAX_WIDTH })
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([cardDescColor()])
        }
        .alignItems(VerticalAlign.Center)
        // 模型入口热区（含箭头）：无障碍语义 = 切换模型；点击动作由宿主承接（收卡 → 开半模态）
        .accessibilityText('切换模型')
        .onClick((): void => {
          this.onOpenModel();
        })
        Blank()
        Text(this.labelOf(this.previewIdx))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          // 档位名色阶（★ 六轮：关闭灰 / 自动黑 / 低·高蓝 / 最高紫）——单源 =
          // Theme.thinkingLevelTextColor，随 previewIdx 拖动期实时跟变
          .fontColor(this.labelColorOf(this.previewIdx))
          .lineHeight(22)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(0)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // 官方 Slider（不挂 systemMaterial——材质只由 popup 单层承接，两层叠色发灰）：
      // ★ 2026-11-25 五轮：单档域（非推理模型只有「默认」一档）整条不渲染——防单档死轨；
      // 此时卡片只剩上面的模型入口行，点开卡仍可换模型。
      if (this.maxIndex() > 0) {
        // 高 44 = 触控高（不随四轮整体缩小，保触控热区）；轨厚 26 + 半圆端头 13 = 厚轨观感。
        // ★ 2026-11-25 二轮观感修笔（决明「光圈改完全官方」）：撤掉上轮的 SHAPE 自绘块，回到
        // DEFAULT 圆块——按压/悬停光圈重新由引擎按官方形制绘制（blockPressedColor 叠
        // hotCircleShadowWidth × focused_scale_value，应用侧无尺寸参数，官方多大就多大）。
        // ★ 三轮（决明「去掉描边，或者官方是怎样的」）：blockBorder* 整支不写——官方默认
        // blockBorderColor 透明 / blockBorderWidth 0，不写即官方无描边。
        // ★ 四轮（决明「卡整体略小」）：白球 22→20、轨厚 28→26（圆角 13），整体缩一档。
        // ★ 五轮（决明「最高档能改为这种渐变吗」）：末档实色紫改蓝→紫渐变（Theme.thinkingTopGradient；
        // 渐变两头 = 普通档蓝与末档紫，两档语义接续），其余档仍强调蓝。
        Slider({ value: this.previewIdx, min: 0, max: this.maxIndex(), step: 1, style: SliderStyle.InSet })
          .width('100%')
          .height(44)
          .blockSize({ width: 20, height: 20 })
          .blockColor(Color.White)
          .trackColor(sliderTrackColor(this.appColorMode))
          .trackThickness(26)
          .trackBorderRadius(13)
          .selectedBorderRadius(13)
          // 已选段着色：末档整条蓝→紫渐变、其余档强调蓝
          .selectedColor(this.isTop(this.previewIdx) ?
            thinkingTopGradient(this.appColorMode) : selectedAccentBlue(this.appColorMode))
          .stepColor(sliderStepColor(this.appColorMode))
          .showSteps(true)
          // 每过一档一记触觉（官方默认 true，显式写为意图声明；前置 = module.json5 声明
          // ohos.permission.VIBRATE——slider.d.ts 明示缺该权限时触觉静默不生效）
          .enableHapticFeedback(true)
          .accessibilityText('思考档位')
          .onChange((v: number, mode: SliderChangeMode): void => {
            this.previewIdx = Math.round(v);
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              const list: string[] = this.stops();
              const target: string = this.previewIdx >= 0 && this.previewIdx < list.length ?
                list[this.previewIdx] : '';
              if (target !== this.value) {
                this.onPick(target);
              }
            }
          })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 14, right: 14, top: 12, bottom: 16 })
  }
}
