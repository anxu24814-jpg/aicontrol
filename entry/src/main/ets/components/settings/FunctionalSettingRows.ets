// 功能设置卡共用件：十张功能卡与助手编辑页「模型与提示词」卡共用的「卡头 + 四种行」单源。
// · 卡头：标题 16fp Medium（卡内小节标题档 CARD_SECTION_TITLE_FONTSIZE——2026-11-01 板块
//   标题改档笔自 SECTION_TITLE 档迁入，卡内标题不随板块档走）+ 行尾 ⓘ。
// · 值行：主标题 + 副标题 + 右侧当前值 15fp（限宽 55%），整行可点、无箭头——决明拍板
//   「不加箭头」，值本身就是入口；值垂直居中于 64/56vp 行盒。
// · 开关行：行尾官方 Toggle = 唯一控制面，行本身不可点不设按压。
// · 提示词行：值 = 默认 / 已自定义；宿主保存或恢复默认后递增 PROMPT_STATE_EPOCH_KEY，
//   本行 @StorageProp 订阅即刷（广播键口径，坑16 正解）。
// · 思考档位行：整行原生 bindMenu，与会话页「思考」热区同机制，组件不持显隐状态（状态
//   驱动版在外部点击/返回关闭时不回写 false，导致菜单关后无法再开）。
// ★ 规格照 docs/规范-列表卡片与组卡 §3 官方实测：行高 64/56vp 固定分档、卡上下 padding 4vp、
//   行左右缩进 4vp（外包 Column padding，禁 margin 写法——红线1）、按压蒙层 = 卡宽−8vp +
//   官方 stateEffect、蒙层圆角同 CARD_RADIUS（红线2 两处同改）、分割线 0.5vp 左 8 / 右 4；
//   卡头左右 12vp = 行缩进 4 + 行内 padding 8，标题与行内容左缘同一条竖线。
// ★ 动态值走 @Prop（卡 → 行单向同步：卡持 @StorageProp/@State，变化触发卡 build 重跑下发）；
//   行组件不跨 PageShell 边界接收父页状态（坑16 家族）。
// ★ dividerTop 为实例静态值（渲染在行内容上方）——避免 OCR 卡按行是否存在动态增删分割线；
//   每张卡首行传 false，其余行传 true。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';
import {
  CARD_SECTION_TITLE_FONTSIZE, cardBorderColor, cardDescColor, cardTitleColor,
  menuDividerColor, menuEndCheck, CARD_RADIUS
} from '../../common/Theme';
import { IMMERSIVE_LEVEL_KEY, resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { InfoHintButton } from '../InfoHintButton';
import { ThinkingMenu, thinkingDisplayLabel } from '../chat/ChatParamChipBar';
import { PROMPT_STATE_EPOCH_KEY, isPromptCustomized } from './PromptSlotSpec';

// 行高两档（官方实测：有副标题 64 / 无 56——内容垂直居中，非内容自适应）
export const FUNCTIONAL_ROW_HEIGHT: number = 64;
const FUNCTIONAL_ROW_HEIGHT_SINGLE: number = 56;
// 行左右缩进（按压蒙层 = 卡宽−8vp；外包 Column padding 实现，禁 Button margin 写法）
const ROW_INSET: number = 4;
// 行内左右 padding（8 + 缩进 4 = 卡内 12，与卡头左右 12 同一条竖线）
const ROW_PADDING: number = 8;
// 分割线左右缩进（官方实测：无图标行左 8 / 右 4）
const DIVIDER_LEFT: number = 8;
const DIVIDER_RIGHT: number = 4;
// 卡头左右内距（= 行缩进 + 行内 padding，标题与行内容左缘对齐）
const HEADER_PADDING: number = 12;
// 行标题 / 副标题 / 右侧值字级（官方实测与 GroupSettingCard 同源）
const ROW_TITLE_FONTSIZE: number = 16;
const ROW_SUBTITLE_FONTSIZE: number = 14;
const ROW_VALUE_FONTSIZE: number = 15;

// 值行纯展示体（值行与思考档位行共用——视觉单源；全局 @Builder 无组件实例，取色走模块级
// 函数，行高由调用方按有无副标题传入）
interface SettingRowBodyParams {
  label: string;
  subtitle: string;
  value: string;
  valueMuted: boolean;
  height: number;
}

@Builder
function SettingRowBody(params: SettingRowBodyParams) {
  Row({ space: 12 }) {
    Column({ space: 2 }) {
      Text(params.label)
        .fontSize(ROW_TITLE_FONTSIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (params.subtitle !== '') {
        Text(params.subtitle)
          .fontSize(ROW_SUBTITLE_FONTSIZE)
          .fontColor(cardDescColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    Text(params.value)
      .fontSize(ROW_VALUE_FONTSIZE)
      .fontColor(params.valueMuted ? cardDescColor() : cardTitleColor())
      .constraintSize({ maxWidth: '55%' })
      .textAlign(TextAlign.End)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }
  .width('100%')
  .height(params.height)
  .padding({ left: ROW_PADDING, right: ROW_PADDING })
  .alignItems(VerticalAlign.Center)
}

// 卡头：标题 + 行尾 ⓘ（说明收气泡）
@Component
export struct FunctionalCardHeader {
  title: string = '';
  hint: string = '';

  build() {
    Row({ space: 8 }) {
      Text(this.title)
        .fontSize(CARD_SECTION_TITLE_FONTSIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.hint !== '') {
        InfoHintButton({ text: this.hint })
      }
    }
    .width('100%')
    .padding({ left: HEADER_PADDING, right: HEADER_PADDING })
    .alignItems(VerticalAlign.Center)
  }
}

// 值行：左主副标题 + 右当前值，整行可点
@Component
export struct SettingValueRow {
  label: string = '';
  // ★ subtitle 必须 @Prop：普通成员是构造期快照，父侧状态变化不传导（真机报障——value
  // 已是「已设置」而副行仍停在「未设置」）
  @Prop subtitle: string = '';
  @Prop value: string = '';
  @Prop valueMuted: boolean = true;
  dividerTop: boolean = false;
  onTap: () => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  private rowHeight(): number {
    return this.subtitle !== '' ? FUNCTIONAL_ROW_HEIGHT : FUNCTIONAL_ROW_HEIGHT_SINGLE;
  }

  build() {
    Column() {
      if (this.dividerTop) {
        Divider()
          .strokeWidth(0.5)
          .color(cardBorderColor(this.appColorMode))
          .margin({ left: DIVIDER_LEFT, right: DIVIDER_RIGHT })
      }
      Column() {
        Button() {
          SettingRowBody({
            label: this.label,
            subtitle: this.subtitle,
            value: this.value,
            valueMuted: this.valueMuted,
            height: this.rowHeight()
          })
        }
        .type(ButtonType.Normal)
        .width('100%')
        .padding(0)
        .backgroundColor(Color.Transparent)
        .borderRadius(CARD_RADIUS)
        .stateEffect(true)
        .onClick((): void => {
          this.onTap();
        })
      }
      .width('100%')
      .padding({ left: ROW_INSET, right: ROW_INSET })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

// 思考档位行：值行特化 + 整行原生 bindMenu（机制见文件头）。两个消费方 = 功能思考档位卡
// （全局八链档位）/ 助手编辑页模型与提示词卡（助手级档位）；菜单锚定行右侧
// （Placement.BottomRight，视觉落点即右侧档位值）
@Component
export struct SettingThinkingRow {
  label: string = '思考档位';
  subtitle: string = '';
  // 当前档位（@Link 双向——菜单勾选随值刷新；'' = 默认不传 / off = 关闭 / 其余档位原文）
  @Link value: string;
  // 菜单选项集（'' 首项为「默认」；「关闭」项须选项含 'off' 且 offOk 为 true）
  @Prop options: string[] = [''];
  @Prop offOk: boolean = false;
  dividerTop: boolean = false;
  // 档位选择回调（消费方落值：写持久键 / 落库后回写 @Link）
  onPick: (option: string) => void = (_option: string): void => {
  };
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  private rowHeight(): number {
    return this.subtitle !== '' ? FUNCTIONAL_ROW_HEIGHT : FUNCTIONAL_ROW_HEIGHT_SINGLE;
  }

  // 菜单体（bindMenu builder 位——组件内 @Builder，坑51/62：禁 lambda 直调全局 builder）
  @Builder
  private TierMenuBuilder() {
    ThinkingMenu({ value: $value, options: this.options, offOk: this.offOk,
      onPick: (option: string): void => {
        this.onPick(option);
      }
    })
  }

  build() {
    Column() {
      if (this.dividerTop) {
        Divider()
          .strokeWidth(0.5)
          .color(cardBorderColor(this.appColorMode))
          .margin({ left: DIVIDER_LEFT, right: DIVIDER_RIGHT })
      }
      Column() {
        Button() {
          SettingRowBody({
            label: this.label,
            subtitle: this.subtitle,
            value: thinkingDisplayLabel(this.value),
            valueMuted: this.value === '',
            height: this.rowHeight()
          })
        }
        .type(ButtonType.Normal)
        .width('100%')
        .padding(0)
        .backgroundColor(Color.Transparent)
        .borderRadius(CARD_RADIUS)
        .stateEffect(true)
        // 无 isShow 状态——显隐由官方菜单接管
        .bindMenu(this.TierMenuBuilder, {
          placement: Placement.BottomRight,
          // 第三参 true = 交互形变 + 触点流光（勿回改 false）
          systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
            this.immersiveLevel, true)
        })
      }
      .width('100%')
      .padding({ left: ROW_INSET, right: ROW_INSET })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

// 通用枚举值行：值行 + 行内原生 bindMenu（机制照 SettingThinkingRow，选项集与显示名由调用方
// 全权给出）。2026-11-11 MCP 协议版本笔新建——协议版本是任意枚举（'' = 自动协商 + 四个日期
// 版本），SettingThinkingRow 的菜单体写死 ThinkingMenu 的「默认 / 关闭 / low / high / max」
// 语义，不适配；本件只负责「选项 → 菜单项 → 上行」的机械映射，不解释选项含义。
// ★ 为何不能并入 SettingThinkingRow（反碎片下限②申报）：并入需在该件内保留两条菜单路径
// （思考档专用 + 任意枚举），组件从「一个职责」变成「按调用方分派」，比两件更差。
@Component
export struct SettingMenuRow {
  label: string = '';
  @Prop subtitle: string = '';
  // 当前值（显示名按 optionLabels 同序映射；未命中回退值原文）
  @Prop value: string = '';
  // 选项值集（顺序即菜单序）
  @Prop options: string[] = [];
  // 选项显示名（与 options 同序；缺项 / 越界回退该选项值原文）
  @Prop optionLabels: string[] = [];
  dividerTop: boolean = false;
  // 选项选择回调（父侧落值，本件不持选中态）
  onPick: (option: string) => void = (_option: string): void => {
  };
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  private rowHeight(): number {
    return this.subtitle !== '' ? FUNCTIONAL_ROW_HEIGHT : FUNCTIONAL_ROW_HEIGHT_SINGLE;
  }

  private labelOf(option: string): string {
    const index: number = this.options.indexOf(option);
    return index >= 0 && index < this.optionLabels.length ? this.optionLabels[index] : option;
  }

  // 菜单体（bindMenu builder 位——组件内 @Builder，坑51/62：禁 lambda 直调全局 builder）
  @Builder
  private OptionMenuBuilder() {
    Menu() {
      ForEach(this.options, (option: string) => {
        MenuItem({
          content: this.labelOf(option),
          symbolEndIcon: menuEndCheck(this.value === option)
        })
          .onClick((): void => {
            this.onPick(option);
          })
      // ★ 键含勾选态（坑44 家族 / 宪法「列表键纪律」）：行内可变展示成分 = 当前值的项尾勾，
      // 键只写选项值时，「勾从 A 项挪到 B 项」是同键复用、项配置不重渲 ⇒ 勾冻结在首帧；
      // 键变触发整项重建。与 ChatPromptSheet.WebSearchMenu 同形制（该件 2026-11-11 勾位
      // 笔同样保留勾选态布尔）
      }, (option: string): string => 'mo' + option + '|' + String(this.value === option))
    }
    .menuItemDivider({
      color: menuDividerColor(this.appColorMode),
      mode: DividerMode.EMBEDDED_IN_MENU
    })
  }

  build() {
    Column() {
      if (this.dividerTop) {
        Divider()
          .strokeWidth(0.5)
          .color(cardBorderColor(this.appColorMode))
          .margin({ left: DIVIDER_LEFT, right: DIVIDER_RIGHT })
      }
      Column() {
        Button() {
          SettingRowBody({
            label: this.label,
            subtitle: this.subtitle,
            value: this.labelOf(this.value),
            valueMuted: false,
            height: this.rowHeight()
          })
        }
        .type(ButtonType.Normal)
        .width('100%')
        .padding(0)
        .backgroundColor(Color.Transparent)
        .borderRadius(CARD_RADIUS)
        .stateEffect(true)
        .bindMenu(this.OptionMenuBuilder, {
          placement: Placement.BottomRight,
          // 第三参 true = 交互形变 + 触点流光（勿回改 false）
          systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR,
            this.immersiveLevel, true)
        })
      }
      .width('100%')
      .padding({ left: ROW_INSET, right: ROW_INSET })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

// 开关行：左主副标题 + 行尾 Toggle（唯一控制面，行本身不可点）
@Component
export struct SettingSwitchRow {
  label: string = '';
  subtitle: string = '';
  @Prop isOn: boolean = false;
  dividerTop: boolean = false;
  onToggle: (isOn: boolean) => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  private rowHeight(): number {
    return this.subtitle !== '' ? FUNCTIONAL_ROW_HEIGHT : FUNCTIONAL_ROW_HEIGHT_SINGLE;
  }

  build() {
    Column() {
      if (this.dividerTop) {
        Divider()
          .strokeWidth(0.5)
          .color(cardBorderColor(this.appColorMode))
          .margin({ left: DIVIDER_LEFT, right: DIVIDER_RIGHT })
      }
      Row() {
        Column({ space: 2 }) {
          Text(this.label)
            .fontSize(ROW_TITLE_FONTSIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.subtitle !== '') {
            Text(this.subtitle)
              .fontSize(ROW_SUBTITLE_FONTSIZE)
              .fontColor(cardDescColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.isOn })
          .onChange((isOn: boolean): void => {
            this.onToggle(isOn);
          })
      }
      .width('100%')
      .height(this.rowHeight())
      .padding({ left: HEADER_PADDING, right: HEADER_PADDING })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

// 提示词行：值行特化，值 = 默认 / 已自定义
@Component
export struct PromptSettingRow {
  slotKind: string = '';
  label: string = '提示词';
  subtitle: string = '';
  dividerTop: boolean = false;
  onTap: () => void = () => {
  };
  // 提示词状态广播（保存 / 恢复默认后宿主 +1；本行订阅刷新「默认 / 已自定义」）
  @StorageProp(PROMPT_STATE_EPOCH_KEY) @Watch('refresh') promptEpoch: number = 0;
  @State private customized: boolean = false;

  aboutToAppear(): void {
    this.refresh();
  }

  // 定制键非空 = 已自定义（与 effectivePromptOf 的 '' 回内置同判据）
  private refresh(): void {
    this.customized = isPromptCustomized(this.slotKind);
  }

  build() {
    SettingValueRow({
      label: this.label,
      subtitle: this.subtitle,
      value: this.customized ? '已自定义' : '默认',
      valueMuted: !this.customized,
      dividerTop: this.dividerTop,
      onTap: this.onTap
    })
  }
}
