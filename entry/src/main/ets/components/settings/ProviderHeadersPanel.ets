// 服务商详情 · 配置页签自定义请求头卡（2026-08-30 三协议新增）：kv 行列表两输入 +
// 删除键 + 「添加请求头」行。表单值在父页（ProviderDetailPage @State headerPairs，@Link
// 双向直写——ProviderConfigPanel 契约同款）；落库走标题栏「保存」键（序列化丢弃空 k 或
// 空 v 行——AiTypes.serializeHeaderPairs，拍板）。发送时三协议统一逐条追加、允许覆盖
// 内置头含认证头（ChatStreamBase.start 单一落点）。新建态也可编辑（纯表单值，随保存落库）。
// 行键 = 下标（HeaderPair 无稳定 id；删除移位后同键换数据刷新—— TextInput 内容随
// text 参数重置，可接受；深编辑态删中间行的焦点漂移属表单常态）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HeaderPair } from '../../common/providers/AiTypes';
import { CARD_PANEL_WIDTH, badgeBg, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect } from '../../common/ImmersiveLevel';
import { InfoHintButton } from '../InfoHintButton';

// 头名/头值输入长度上限（输入有界红线）
const HEADER_KEY_MAX: number = 100;
const HEADER_VALUE_MAX: number = 500;

@Component
export struct ProviderHeadersPanel {
  // kv 行数组（父页 @State 持有，保存动作在标题栏键；@Link 双向直写）
  @Link pairs: HeaderPair[];
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 沉浸光感档位（行内添加/删除键材质随档——按钮光感簇，
  // 见 ImmersiveLevel resolvedButton*/fallbackButton*；与 ProviderKeysPanel 同口径）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 内容区回退开关（2026-09-03）：true = 本键官方实底（新规范下内容区材质不生效）；
  // false = 原材质光感；AppStorage 订阅式切换即刷（坑16 正解，同档位键契约）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;

  // 添加行（尾部追加空行；空行保存时丢弃——不在这里拦，允许先填一半再补）
  private addRow(): void {
    this.pairs.push({ k: '', v: '' });
  }

  private removeRow(index: number): void {
    this.pairs.splice(index, 1);
  }

  build() {
    Column({ space: 12 }) {
      // 标题行：标题 + 右上角 ⓘ 更多信息键（发送语义说明移入气泡——卡面不留长文本）
      Row() {
        Text('自定义请求头')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        InfoHintButton({
          text: '发送时逐条追加，允许覆盖内置头，含认证头。名称或值为空的行保存时丢弃'
        })
      }
      .width('100%')
      if (this.pairs.length === 0) {
        Text('暂无自定义头。中转站验证头等场景在此添加')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      }
      ForEach(this.pairs, (pair: HeaderPair, index: number) => {
        Row({ space: 8 }) {
          TextInput({ placeholder: 'Header 名，例如 X-Api-Source', text: pair.k })
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
      }, (pair: HeaderPair, index: number): string => 'h' + index)
      // 「添加请求头」= 主操作（2026-09-02 决明要求：官方蓝底——primary=true 强调蓝 +
      // 恒白字；2026-09-03 内容区回退双态：光感态 = 原材质（resolvedButton*），实底态 =
      // fallbackButton* 官方强调蓝实底）
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
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }
}
