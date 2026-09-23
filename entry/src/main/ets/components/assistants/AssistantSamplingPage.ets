// 助手采样参数三级页（2026-09-01 高级设定，领导指令照参考图复刻）：编辑页「高级设定」
// 二级页「采样参数」行卡 push 进入，param = 助手 id。
// · 页面形态：PageShell 自包壳（助手域各页同款，顶部光感 = 渐变模糊常显）+ 灰底直放
//   说明行「关闭时使用服务商默认值」（SystemPromptPage 说明行范式）+ 四张开关卡——
//   覆盖温度 / Top P / 覆盖存在惩罚 / 覆盖频率惩罚（RikkaHub 助手参数页同款四项）。
//   开关默认关（关闭 = 不发送该字段，沿用服务商默认值）；打开 → 卡内下部展开官方
//   InSet 滑块 + 右侧数值（领导指令「拖动条官方样式同沉浸光感档位页」= AppearancePage
//   LevelSlider 形制：trackThickness 20 + blockSize 12×12 + 半透明 trackColor + REGULAR
//   材质，不自定义 blockColor/selectedColor——官方默认已选段蓝轨即图示观感）。
//   ★ 2026-09-20 决明指令：四项作用原无提示——各卡补 ⓘ 气泡（ⓘ 在整卡右上角）与卡面
//   说明小字，形态依据见 SamplingToggleCard 头注释。
// · 范围与初值（官方 API 文档查证 2026-09-01，细则见 RequestCompose 头注释）：温度
//   0~2 step 0.1（初值 0.7；Anthropic 官方域 0~1 发送层 clamp）/ Top P 0~1 step 0.05
//   （初值 0.9）/ 双惩罚 -2~2 step 0.1（初值 0；仅 openai chat 与 gemini 发送，
//   Responses/Anthropic 官方无此字段自动不发）。滑块值统一 snap 到 2 位小数（浮点步进
//   累积误差修整）。
// · 保存模式：无保存键——@State 编辑，onBackPressed 拦截统一落库（无改动无参 pop 不
//   触发二级页 onPop；有改动序列化对比 initial 串，落库失败 toast 留页重试 P0-1）→
//   pop({saved:true}) 刷二级页行卡摘要（坑17 契约链）。★ 保存保留原 contextCount/
//   maxOutput 键（上下文页的值不经本页改动）；采样开关关 = 键不落 JSON（undefined 省略）。
// · ★ 2026-09-02 坑16 家族归正（同上下文页同轮）：开关卡 @Prop isOn/value 居
//   PageShell.content（@BuilderParam）内不随父 @State 更新——拖动数值/开关态冻结首帧。
//   改 @Link 订阅式双向（onChange 直写回父 @State，父变化同步进卡）。
// · 生效链：发送时 ChatPromptState 解析缓存 → ChatSendCtrl 透传 → RequestCompose 四
//   协议方言落点（sse-assert ㉓ 组断言）；进行中轮次不受编辑影响（roundSampling 快照）。
// · ★ 2026-09-02 领导指令新增底部「恢复默认」按钮（SystemPromptPage 底部按钮条同款
//   形制）：Stack(alignContent Bottom)——滚动区全高 + 按钮条悬浮底部挂 systemMaterial
//   （THIN 基准档随沉浸光感总档，半透明模糊，内容滚到条后透出）；点击 = 四开关置
//   关 + 四值回开启初值常量（初始开开关显示的参数，开关仍为关闭态）——只改编辑态，
//   落库沿用页面既有「返回时统一保存」链（无新落库通道，改动语义与手调完全一致）；
//   滚动内容底部 padding 让位条高（两处同改，SystemPromptPage 同款注释义务）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';
import { PageShell } from '../../common/PageShell';
import { ROUTE_ASSISTANT_SAMPLING_PAGE } from '../../common/RouteNames';
import {
  CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor, sliderTrackColor
} from '../../common/Theme';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg,
  fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect, leveledUiMaterial,
  resolveEffectiveLevel
} from '../../common/ImmersiveLevel';
import {
  AssistantAdvancedParams, parseAssistantAdvancedParams, serializeAssistantAdvancedParams
} from '../../common/providers/AiTypes';
import { queryAssistant, updateAssistantAdvancedParams } from '../../common/store/AssistantDb';
import { InfoHintButton } from '../InfoHintButton';

// 开启初值（开关从关→开时滑块起始值；0 对惩罚 = 无惩罚基线，用户自行上调）
const DEFAULT_TEMPERATURE: number = 0.7;
const DEFAULT_TOP_P: number = 0.9;
const DEFAULT_PENALTY: number = 0;

// 采样开关卡（页内组件——四参数同构 4 连用提取，P2-4）：顶行 = 标题 + 官方 info 气泡
// （ⓘ 说明该参数作用，2026-09-20 决明指令「四项作用没提示，各自卡加气泡」）；开关行 =
// 13fp 灰说明小字（左，关键句）+ 官方 Toggle（右）；开启时下行 = 官方 InSet 滑块
// （layoutWeight 让位数值）+ 右侧数值。★ isOn/value 用 @Link（坑16 家族：@BuilderParam
// content 内 @Prop 不随父 @State 更新）——官方 Toggle/Slider 支持 isOn/value 受控同步，
// onChange 直写回父 @State 即时生效。★ 气泡与说明行的位置依据 = 卡形制先例（AppearancePage
// FallbackSwitchCard，2026-09-08 决明真机反馈定稿）：气泡必须落**整卡右上角**（标题行撑满
// 卡内宽 + 气泡居尾），开关不与气泡同行；说明小字在开关左侧同行（PreferencesPage 开关行
// 先例，先说明后操作口径不变）——禁把 ⓘ 插进标题与 Toggle 之间（那正是被否过的「开关左上角」）
@Component
struct SamplingToggleCard {
  title: string = '';
  @Link isOn: boolean;
  @Link value: number;
  // 滑块域（纯展示入参，创建后不变）
  min: number = 0;
  max: number = 2;
  step: number = 0.1;
  // 数值格式化（温度/惩罚 1 位小数，Top P 2 位）
  format: (v: number) => string = (v: number): string => v.toFixed(1);
  // 卡面说明小字（开关行左侧关键句）与 ⓘ 气泡全文（完整作用说明）——静态文本值传参
  desc: string = '';
  hint: string = '';
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  build() {
    Column({ space: 12 }) {
      // 顶行 = 标题 + info 气泡（标题 layoutWeight 撑满 → 气泡落整卡右上角，见头注释）
      Row() {
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        InfoHintButton({ text: this.hint })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // 开关行 = 说明小字（左）+ 官方 Toggle（右，唯一控制面——规范-列表卡片与组卡 §4.1）
      Row({ space: 12 }) {
        Text(this.desc)
          .fontSize(13)
          .fontColor(cardDescColor())
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.isOn })
          .onChange((on: boolean) => {
            this.isOn = on;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      if (this.isOn) {
        // 展开区：滑块 + 右侧数值（固定宽防拖动时数值变长抖动）
        Row({ space: 10 }) {
          Slider({ value: this.value, min: this.min, max: this.max, step: this.step,
            style: SliderStyle.InSet })
            .layoutWeight(1)
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
              // 浮点步进累积误差修整（0.1/0.05 步进统一 2 位小数；越界值 clamp）；
              // @Link 直写回父 @State（拖动即时生效）
              const clamped: number = Math.min(Math.max(v, this.min), this.max);
              this.value = parseFloat(clamped.toFixed(2));
            })
          Text(this.format(this.value))
            .fontSize(15)
            // 右值统一强调蓝（2026-09-12 UI 同形异构归一笔 2——对齐 SliderValueCard，
            // 原卡 TitleColor 黑与上下文/工具页同位不同色）
            .fontColor($r('sys.color.ohos_id_color_emphasize'))
            .width(44)
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct AssistantSamplingPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 编辑对象行 id（push param = 助手 id，二级页传入）
  private rowId: string = '';
  // 四参数编辑态（@State 驱动开关卡重建；value 初值 = parse 值 ?? 开启初值常量）
  @State private tempOn: boolean = false;
  @State private tempVal: number = DEFAULT_TEMPERATURE;
  @State private topPOn: boolean = false;
  @State private topPVal: number = DEFAULT_TOP_P;
  @State private presOn: boolean = false;
  @State private presVal: number = DEFAULT_PENALTY;
  @State private freqOn: boolean = false;
  @State private freqVal: number = DEFAULT_PENALTY;
  // 上下文页的值（不经本页改动，保存时原样保留；普通成员——无 UI 直渲染）
  private keepContextCount: number | undefined = undefined;
  private keepMaxOutput: number | undefined = undefined;
  // 进页时库内原串（保存时对比判「无改动」；'' = 未配置）
  private initialJson: string = '';
  // 沉浸光感整体档位（底部恢复默认按钮条材质——SystemPromptPage 先例）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关（2026-09-03）：true = 本键官方实底（新规范下内容区材质不生效）；
  // false = 原材质光感；AppStorage 订阅式切换即刷（坑16 正解，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  aboutToAppear(): void {
    // push 参数（getParamByName 取末条，ModelSettingsPage 同款姿势）：string id（行卡
    // push 必非空；空/缺参 = 异常路径弹回）
    const params: Array<string> =
      this.pathStack.getParamByName(ROUTE_ASSISTANT_SAMPLING_PAGE) as Array<string>;
    const param: string | undefined = params.length > 0 ? params[params.length - 1] : undefined;
    if (param === undefined || param === '') {
      this.getUIContext().getPromptAction().showToast({ message: '缺少助手参数' });
      this.pathStack.pop();
      return;
    }
    this.rowId = param;
    queryAssistant(param)
      .then((row): void => {
        if (row === null) {
          this.getUIContext().getPromptAction().showToast({ message: '助手不存在或已删除' });
          this.pathStack.pop();
          return;
        }
        this.initialJson = row.advancedParams;
        const parsed: AssistantAdvancedParams | null =
          parseAssistantAdvancedParams(row.advancedParams);
        if (parsed !== null) {
          this.tempOn = parsed.temperature !== undefined;
          this.tempVal = parsed.temperature ?? DEFAULT_TEMPERATURE;
          this.topPOn = parsed.topP !== undefined;
          this.topPVal = parsed.topP ?? DEFAULT_TOP_P;
          this.presOn = parsed.presencePenalty !== undefined;
          this.presVal = parsed.presencePenalty ?? DEFAULT_PENALTY;
          this.freqOn = parsed.frequencyPenalty !== undefined;
          this.freqVal = parsed.frequencyPenalty ?? DEFAULT_PENALTY;
          this.keepContextCount = parsed.contextCount;
          this.keepMaxOutput = parsed.maxOutput;
        }
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '助手读取失败：' + (e as Error).message });
        this.pathStack.pop();
      });
  }

  // 返回 = 统一保存（onBackPressed 拦截）：无改动无参 pop（不触发二级页 onPop，摘要无需
  // 刷新）；有改动落库（失败 toast 留页可重按返回重试——P0-1 不静默不丢改动）→
  // pop({saved:true}) 触发二级页 onPop 刷行卡摘要（坑17 契约）

  // 恢复默认（2026-09-02 领导指令，底部按钮）：四开关置关 + 四值回开启初值常量——
  // 只改编辑态，返回时经 onBackPressed 统一落库（与手调同链，无新落库通道）
  private restoreDefaults(): void {
    this.tempOn = false;
    this.tempVal = DEFAULT_TEMPERATURE;
    this.topPOn = false;
    this.topPVal = DEFAULT_TOP_P;
    this.presOn = false;
    this.presVal = DEFAULT_PENALTY;
    this.freqOn = false;
    this.freqVal = DEFAULT_PENALTY;
  }

  @Builder
  Content() {
    // Stack(alignContent Bottom)：滚动区全高 + 底部按钮条悬浮（SystemPromptPage 同款
    // ——半透明材质条，内容可滚到条后透出；滚动内容 padding bottom 让位条高）
    Stack({ alignContent: Alignment.Bottom }) {
    Scroll() {
      Column({ space: 12 }) {
        // 说明行（灰底直放不加卡——SystemPromptPage 说明行范式；图一副标题口径「关闭时
        // 沿用全局配置或服务商默认值」微调：本项目无全局配置层，言行一致改为服务商默认）
        Text('关闭时使用服务商默认值')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width(CARD_PANEL_WIDTH)
        SamplingToggleCard({
          title: '覆盖温度', isOn: $tempOn, value: $tempVal,
          min: 0, max: 2, step: 0.1,
          format: (v: number): string => v.toFixed(1),
          desc: '值越低回复越稳定，越高越发散',
          hint: '控制回复的随机程度。写代码、翻译这类要准确的场景用低值，头脑风暴这类要创意的场景用高值。部分服务商只支持到 1，超出时按 1 发送'
        })
        SamplingToggleCard({
          title: 'Top P', isOn: $topPOn, value: $topPVal,
          min: 0, max: 1, step: 0.05,
          format: (v: number): string => v.toFixed(2),
          desc: '值越小可选词越少，回复越稳定',
          hint: '也叫核采样。模型只在概率最高的一批词里挑下一个词，值越小这批词越少、回复越稳。与温度通常调整其中一个即可'
        })
        SamplingToggleCard({
          title: '覆盖存在惩罚', isOn: $presOn, value: $presVal,
          min: -2, max: 2, step: 0.1,
          format: (v: number): string => v.toFixed(1),
          desc: '抑制重复话题，鼓励谈新内容',
          hint: '对已经说过的内容施加惩罚，鼓励模型讲新内容、少重复。取负值则相反，会更多重复已用过的表达。部分服务商不支持这项参数，不支持时不会发送'
        })
        SamplingToggleCard({
          title: '覆盖频率惩罚', isOn: $freqOn, value: $freqVal,
          min: -2, max: 2, step: 0.1,
          format: (v: number): string => v.toFixed(1),
          desc: '抑制同一个词反复出现',
          hint: '按词出现的次数施加惩罚，重复越多惩罚越重，用来减少复读式表达。部分服务商不支持这项参数，不支持时不会发送'
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      // 底部让位恢复默认按钮条（条高 = 12 + 40 + bottomPad + 16——与按钮条两处同改）
      .padding({ top: this.topPad, bottom: this.bottomPad + 68 })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      // ── 底部操作键条（2026-09-02 决明反馈「无背后蒙层」：条不挂材质——原 THIN 半透明
      // 条被误读为蒙层；按钮自身 fallbackButtonMaterial 已带光感，直接悬浮固定底部）──
      // 条内按钮 = fallbackButton 四件套（2026-09-03 内容区回退双态：光感态 = resolvedButton*
      // 原材质光感；实底态 = fallbackButton* 官方实底，无光感档回退官方灰底），条透明；
      // 让位常量 = 条上内边距 12 + 按钮 40 + 条下内边距 (bottomPad+16)，滚动区 padding
      // bottom 同值（改条高两处同改）
      Column() {
        // 「恢复默认」= 主操作（2026-09-02 决明要求：官方蓝底——primary=true 强调蓝 +
        // 恒白字）
        Button('恢复默认')
          .width(CARD_PANEL_WIDTH)
          .fontColor(fallbackButtonFont(this.contentFallback, true))
          .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
          .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .onClick((): void => {
            this.restoreDefaults();
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
  }

  // 组装保存值（开关关 = 键 undefined = 序列化省略；上下文两键原样保留）
  private buildNextParams(): AssistantAdvancedParams {
    return {
      temperature: this.tempOn ? this.tempVal : undefined,
      topP: this.topPOn ? this.topPVal : undefined,
      presencePenalty: this.presOn ? this.presVal : undefined,
      frequencyPenalty: this.freqOn ? this.freqVal : undefined,
      contextCount: this.keepContextCount,
      maxOutput: this.keepMaxOutput
    };
  }

  build() {
    PageShell({
      title: '采样参数',
      // 右上角无菜单键（纯参数编辑页）
      onBackPressed: (): boolean => {
        const json: string = serializeAssistantAdvancedParams(this.buildNextParams());
        if (json === this.initialJson) {
          this.pathStack.pop(); // 无改动——无参 pop 不触发二级页 onPop
          return true;
        }
        updateAssistantAdvancedParams(this.rowId, json)
          .then((): void => {
            this.pathStack.pop({ saved: true });
          })
          .catch((e: Object): void => {
            this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
          });
        return true; // 拦截返回——落库结果回调内再 pop（失败留页）
      },
      content: (): void => {
        this.Content();
      }
    })
  }
}
