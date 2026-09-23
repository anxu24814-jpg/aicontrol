// 余额请求头编辑卡（2026-08-31 新增，半模态内嵌区块，自 ProviderBalancePanel 拆出腾红线）：
// kv 行两输入 + 删除键 + 「添加请求头」键——ProviderHeadersPanel 同构形制（项目已有 kv 行
// UI），无卡片壳（半模态 List 内容直排风格）。表单值 @Link 双向直写父页
//（ProviderDetailPage @State balHeaderPairs），随标题栏「保存」统一落库（balance_headers
// JSON 列，空 k/v 行丢弃——serializeHeaderPairs 既有语义）；发送 = 余额查询时逐条追加、
// 同名覆盖默认 Authorization/Accept 头（BalanceApi——new-api 系 New-Api-User 校验头场景）。
// 行键 = 下标（HeaderPair 无稳定 id；删除移位后同键换数据刷新——TextInput 内容随 text
// 参数重置，可接受；ProviderHeadersPanel 同款取舍）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HeaderPair } from '../../common/providers/AiTypes';
import { badgeBg, cardDescColor, cardTitleColor } from '../../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect } from '../../common/ImmersiveLevel';

// 头名/头值输入长度上限（与聊天链路自定义头同界）
const HEADER_KEY_MAX: number = 100;
const HEADER_VALUE_MAX: number = 500;

@Component
export struct BalanceHeadersCard {
  // kv 行数组（父页 BalanceConfigPage @State 持有，保存动作在本页标题栏键〔2026-09-11
  // 余额配置二级页化——原「详情页标题栏键」口径随迁页作废〕；@Link 双向直写）
  @Link pairs: HeaderPair[];
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 沉浸光感档位（行内添加/删除键双态随档——光感态 resolvedButton*
  // 原材质光感、实底态 fallbackButton* 官方实底，同 ProviderHeadersPanel 口径）
  // 内容区回退开关（2026-09-03）：true = 本键官方实底（新规范下内容区材质不生效）；
  // false = 原材质光感；AppStorage 订阅式切换即刷（坑16 正解，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;

  private addRow(): void {
    this.pairs.push({ k: '', v: '' });
  }

  private removeRow(index: number): void {
    this.pairs.splice(index, 1);
  }

  build() {
    Column({ space: 12 }) {
      Text('余额请求头')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .width('100%')
      Text('查询时逐条追加，同名覆盖默认认证头，例如中转站要求的 New-Api-User。名称或值为空的行保存时丢弃')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      if (this.pairs.length === 0) {
        Text('暂无自定义头。官方端点通常无需填写')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      }
      ForEach(this.pairs, (pair: HeaderPair, index: number) => {
        Row({ space: 8 }) {
          TextInput({ placeholder: 'Header 名，例如 New-Api-User', text: pair.k })
            .maxLength(HEADER_KEY_MAX)
            .layoutWeight(1)
            .onChange((value: string): void => {
              pair.k = value;
            })
          TextInput({ placeholder: '值', text: pair.v })
            .maxLength(HEADER_VALUE_MAX)
            .layoutWeight(1)
            .onChange((value: string): void => {
              pair.v = value;
            })
          // 删除键（2026-09-04 决明指令「去掉圈选圆框，只保留删除按钮」）：灰实底在真机上
          // 观感如选中圈——退役光感化四件套，改无底图标键（TEXTUAL，刷新键/更多键/助手卡
          // 删除键同款官方形制；内容区材质本就不生效——09-03 定论，TEXTUAL 自带官方按压
          // 变淡反馈，功能不变）
          Button() {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(16)
              .fontColor([$r('sys.color.font_secondary')])
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .onClick((): void => {
            this.removeRow(index);
          })
        }
        .width('100%')
        .padding(10)
        .borderRadius(12)
        .backgroundColor(badgeBg(this.appColorMode))
        .alignItems(VerticalAlign.Center)
      }, (pair: HeaderPair, index: number): string => 'bh' + index)
      // 「添加请求头」= 主操作（2026-09-02 决明要求：官方蓝底——primary=true 强调蓝 +
      // 恒白字，与 ProviderHeadersPanel / ProviderBodyPanel 同构）——内容区双态：光感态
      // resolvedButton*（官方蓝灰 + 材质光感）、实底态 fallbackButton*（官方强调蓝实底 + 恒白）
      Button('添加请求头')
        .fontColor(fallbackButtonFont(this.contentFallback, true))
        .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .width('100%')
        .onClick((): void => {
          this.addRow();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
