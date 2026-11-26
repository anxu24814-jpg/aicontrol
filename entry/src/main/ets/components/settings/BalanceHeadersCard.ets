// 余额请求头编辑卡（半模态内嵌区块）：表单值 @Link 双向直写宿主页
//（BalanceConfigPage @State balHeaderPairs），随标题栏「保存」统一落库（balance_headers JSON 列，
// 空 k/v 行丢弃——serializeHeaderPairs 既有语义）；发送 = 余额查询时逐条追加、同名覆盖默认
// Authorization/Accept 头（BalanceApi——new-api 系 New-Api-User 校验头场景）。
// · 行组挂公共件 KeyValueWell 单源：行键与增删全在井内，本卡只留「标题 + 说明 + 折叠 + 挂井」。
// · 折叠：标题行行尾折叠箭头 + 整行可点切换 + animateTo 条件渲染（形制照四卡收起展开族，
//   官方 FAQ faqs-arkui-769）；说明小字恒显示，收起态 = 标题 + 说明两行短卡；行值仍在宿主页
//   @State，展开重建即回填；收放态持久化键 PREF_BALANCE_HEADERS_CARD_COLLAPSED_KEY（@StorageLink）。
// · 标题行不带按压蒙层（裸 Row + .onClick，无 Button 包壳）：理由见 ProviderHeadersPanel。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PREF_BALANCE_HEADERS_CARD_COLLAPSED_KEY } from '../../common/AppPreferences';
import { HeaderPair } from '../../common/providers/AiTypes';
import { cardDescColor, cardTitleColor } from '../../common/Theme';
import { KeyValueWell } from '../KeyValueWell';

// 头名/头值输入长度上限（与聊天链路自定义头同界；井的入参穿透下去）
const HEADER_KEY_MAX: number = 100;
const HEADER_VALUE_MAX: number = 500;

// 折叠动画时长（官方 FAQ faqs-arkui-769 示例同值；与四卡收起展开笔 FOLD_ANIM_MS 同族，UIContext 形态）
const FOLD_ANIM_MS: number = 300;

@Component
export struct BalanceHeadersCard {
  // 键值行数组（宿主页 BalanceConfigPage @State 持有，保存动作在本页标题栏键；@Link 双向直写）
  @Link pairs: HeaderPair[];
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡收放态（缺省 false = 默认展开）。@StorageLink 双向 = 用户点标题行即写即落盘
  //（persistProp 已注册），退出重进/重启保持
  @StorageLink(PREF_BALANCE_HEADERS_CARD_COLLAPSED_KEY) collapsed: boolean = false;

  build() {
    Column({ space: 12 }) {
      // 标题行 + 说明小字：整行可点切换，说明小字恒显示——收起态 = 标题 + 说明两行短卡
      //（形制同 HTTP 域名两卡：标题紧贴说明成组，再 12 间距进卡体）。箭头 rotate 双态与卡体
      // 条件渲染同源 this.collapsed；裸 Row 无按压蒙层
      Column({ space: 2 }) {
        Row() {
          Text('余额请求头')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
            .layoutWeight(1)
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
        Text('查询时逐条追加，同名覆盖默认认证头，例如中转站要求的 New-Api-User。名称或值为空的行保存时丢弃')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      // 卡体（键值井）：收起态整体隐藏。折叠纯 UI 态，行值仍在宿主页 @State，展开重建即回填
      if (!this.collapsed) {
        KeyValueWell({
          rows: $pairs,
          keyPlaceholder: 'Header 名，例如 New-Api-User',
          valuePlaceholder: '值',
          addLabel: '＋ 添加请求头',
          keyMaxLength: HEADER_KEY_MAX,
          valueMaxLength: HEADER_VALUE_MAX,
          emptyHint: '暂无自定义头。官方端点通常无需填写'
        })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
