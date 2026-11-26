// 服务商详情 · 高级页签自定义请求头卡（本卡挂载在高级页签〔ProviderDetailPage〕）。
// · 表单 = 公共件 KeyValueWell（整组请求头只占一个视觉容器，见 docs/规范-列表卡片与组卡.md §4.12）；
//   本卡只负责卡头、折叠与三件文案，行的增删/键纪律/输入形制全在井内单源，不持行键仓。
// · 表单值在父页（ProviderDetailPage @State headerPairs，@Link 双向直写）；落库走标题栏「保存」，
//   序列化丢弃空 k 或空 v 行（AiTypes.serializeHeaderPairs）。
// · 发送时三协议统一逐条追加、允许覆盖内置头含认证头（ChatStreamBase.start 单一落点）。
//   新建态也可编辑（纯表单值，随保存落库）。
// · 折叠：标题行行尾折叠箭头 + 整行可点切换 + animateTo 条件渲染（形制照价格卡 ModelPriceCard，
//   官方 FAQ faqs-arkui-769）；收起态行值仍在父页 @State，展开重建即回填；收放态持久化键
//   PREF_HEADERS_CARD_COLLAPSED_KEY（@StorageLink 双向）。
// · 标题行不带按压蒙层（裸 Row + .onClick，无 Button 包壳）：折叠行热区只在标题行，
//   整行按压蒙层与「整卡可点」观感不对位。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PREF_HEADERS_CARD_COLLAPSED_KEY } from '../../common/AppPreferences';
import { HeaderPair } from '../../common/providers/AiTypes';
import { CARD_PANEL_WIDTH, CARD_SECTION_TITLE_FONTSIZE, cardBg, cardDescColor, cardTitleColor, CARD_RADIUS } from '../../common/Theme';
import { KeyValueWell } from '../KeyValueWell';
import { InfoHintButton } from '../InfoHintButton';

// 头名/头值输入长度上限（输入有界红线）
const HEADER_KEY_MAX: number = 100;
const HEADER_VALUE_MAX: number = 500;

// 折叠动画时长（官方 FAQ faqs-arkui-769 示例同值；与价格卡 FOLD_ANIM_MS 同族，UIContext 形态）
const FOLD_ANIM_MS: number = 300;

@Component
export struct ProviderHeadersPanel {
  // kv 行数组（父页 @State 持有，保存动作在标题栏键；@Link 双向直写，再透传给井）
  @Link pairs: HeaderPair[];
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡收放态（缺省 false = 默认展开）。@StorageLink 双向 = 用户点标题行即写即落盘
  //（persistProp 已注册），切页签/重进/重启保持——与价格卡同款通道
  @StorageLink(PREF_HEADERS_CARD_COLLAPSED_KEY) collapsed: boolean = false;

  build() {
    Column({ space: 12 }) {
      // 标题行：标题 + 右上角 ⓘ 信息键（发送语义说明在气泡，卡面不留长文本）+ 行尾折叠箭头；
      // 整行可点切换，箭头 rotate 双态与卡体条件渲染同源 this.collapsed。
      // ⓘ 键为 Button 拦截点击不触发折叠（ChatToolCard 行内按钮先例）
      Row({ space: 8 }) {
        Text('自定义请求头')
          .fontSize(CARD_SECTION_TITLE_FONTSIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        InfoHintButton({
          text: '发送时逐条追加，允许覆盖内置头，含认证头。名称或值为空的行保存时丢弃。'
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
      // 展开重建即回填——零数据链改动
      if (!this.collapsed) {
        KeyValueWell({
          rows: $pairs,
          keyPlaceholder: 'Header 名，例如 X-Api-Source',
          valuePlaceholder: '值',
          addLabel: '＋ 添加请求头',
          keyMaxLength: HEADER_KEY_MAX,
          valueMaxLength: HEADER_VALUE_MAX,
          multiline: false,
          emptyHint: '暂无自定义头。中转站验证头等场景在此添加'
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
