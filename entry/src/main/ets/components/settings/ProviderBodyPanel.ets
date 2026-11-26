// 服务商详情 · 高级页签自定义 Body 卡：表单形制与 ProviderHeadersPanel 同构
//（输入有界上限因 JSON 值较长放宽）。
// · 表单 = 公共件 KeyValueWell 多行行型（上排键 + 圆删、下排值 TextArea）；行增删/键纪律/
//   输入形制全在井内单源（判据与键纪律 = docs/规范-列表卡片与组卡.md §4.12），本卡不持行键仓。
// · 表单值在父页（ProviderDetailPage @State bodyPairs，@Link 双向直写）；落库走标题栏「保存」：
//   序列化复用 AiTypes.serializeHeaderPairs（空 k/v 行丢弃），入库前父页校验各值合法 JSON
//   （非法 toast 拦截保存——P0-1 不静默；headers 无此校验，因头值无 JSON 语义）。
// · 发送语义：ChatStreamBase.start 的 mergeBodyOverrides 统一把各键 JSON.parse 后覆盖/追加到
//   组装完成的请求体根对象——四协议单一落点，同键覆盖内置键（与 headers 覆盖认证头同语义）。
// · 折叠：标题行行尾折叠箭头 + 整行可点切换 + animateTo 条件渲染（形制照价格卡 ModelPriceCard，
//   官方 FAQ faqs-arkui-769）；收起态行值仍在父页 @State，展开重建即回填；收放态持久化键
//   PREF_BODY_CARD_COLLAPSED_KEY（@StorageLink 双向）。
// · 标题行不带按压蒙层（裸 Row + .onClick，无 Button 包壳）：折叠行热区只在标题行，
//   整行按压蒙层与「整卡可点」观感不对位。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PREF_BODY_CARD_COLLAPSED_KEY } from '../../common/AppPreferences';
import { HeaderPair } from '../../common/providers/AiTypes';
import { CARD_PANEL_WIDTH, CARD_SECTION_TITLE_FONTSIZE, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';
import { KeyValueWell } from '../KeyValueWell';
import { InfoHintButton } from '../InfoHintButton';

// 键名/JSON 值输入长度上限（输入有界红线——值放宽容纳对象形态）
const BODY_KEY_MAX: number = 100;
const BODY_VALUE_MAX: number = 2000;

// 折叠动画时长（官方 FAQ faqs-arkui-769 示例同值；与价格卡 FOLD_ANIM_MS 同族，UIContext 形态）
const FOLD_ANIM_MS: number = 300;

@Component
export struct ProviderBodyPanel {
  // kv 行数组（父页 @State 持有，保存动作在标题栏键；@Link 双向直写，再透传给井）
  @Link pairs: HeaderPair[];
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡收放态（缺省 false = 默认展开）。@StorageLink 双向 = 用户点标题行即写即落盘
  //（persistProp 已注册），切页签/重进/重启保持——与价格卡同款通道
  @StorageLink(PREF_BODY_CARD_COLLAPSED_KEY) collapsed: boolean = false;

  build() {
    Column({ space: 12 }) {
      // 标题行：标题 + 右上角 ⓘ 信息键（发送语义说明在气泡，卡面不留长文本）+ 行尾折叠箭头；
      // 整行可点切换，箭头 rotate 双态与卡体条件渲染同源 this.collapsed。
      // ⓘ 键为 Button 拦截点击不触发折叠（ChatToolCard 行内按钮先例）
      Row({ space: 8 }) {
        Text('自定义 Body')
          .fontSize(CARD_SECTION_TITLE_FONTSIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        InfoHintButton({
          text: '发送时按键写入请求体顶层，值为合法 JSON，同键覆盖内置字段。名称或值为空的行保存时丢弃。'
        })
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(12)
          .fontColor([cardDescColor()])
          .rotate({ angle: this.collapsed ? 0 : 180 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        this.getUIContext().animateTo({ duration: FOLD_ANIM_MS, curve: Curve.EaseInOut },
          (): void => {
            this.collapsed = !this.collapsed;
          });
      })
      // 卡体（空态小字 + 键值井）：收起态整体隐藏。折叠纯 UI 态，行值仍在父页 @State，
      // 展开重建即回填——零数据链改动。multiline = true 走多行行型（值 TextArea 高度归井内常量）
      if (!this.collapsed) {
        KeyValueWell({
          rows: $pairs,
          keyPlaceholder: 'Body 键，顶层字段名',
          valuePlaceholder: 'Body 值，JSON，例如 512 或 "abc" 或 {"a":1}',
          addLabel: '＋ 添加 Body',
          keyMaxLength: BODY_KEY_MAX,
          valueMaxLength: BODY_VALUE_MAX,
          multiline: true,
          emptyHint: '暂无自定义 Body。服务商要求的额外顶层字段，例如顶配参数，在此添加。'
        })
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }
}
