// 服务商详情 · 高级页签自定义 Body 卡（2026-09-02 领导指令，RikkaHub「自定义请求体」
// 对齐）：kv 行列表两输入（k = 请求体顶层键名 / v = 多行 JSON 值）+ 删除键 + 「添加
// Body」行——表单形制照 ProviderHeadersPanel 同构（输入有界上限因 JSON 值较长放宽）。
// · 表单值在父页（ProviderDetailPage @State bodyPairs，@Link 双向直写——headers 契约
// 同款）；落库走标题栏「保存」键：序列化复用 AiTypes.serializeHeaderPairs（结构同构
// [{k,v}]，空 k/v 行丢弃），入库前由父页校验各 v 合法 JSON（非法 toast 拦截保存——
// P0-1 不静默，headers 无此校验因头值无 JSON 语义）。
// · 发送语义：ChatStreamBase.start mergeBodyOverrides 统一把各键 JSON.parse 后覆盖/
//   追加到组装完成的请求体根对象——四协议单一落点（协议无关），同键覆盖内置键（与
//   headers「允许覆盖认证头」同语义拍板）；v 建议填 JSON 值文本（数字 512、布尔 true、
//   字符串 "abc"、对象 {"a":1} 均可）。
// · 行键 = 下标（HeaderPair 无稳定 id——HeadersPanel 同款；深编辑态删中间行的焦点漂移
//   属表单常态）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { HeaderPair } from '../../common/providers/AiTypes';
import { CARD_PANEL_WIDTH, badgeBg, cardBg, cardDescColor, cardTitleColor } from '../../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial, fallbackButtonStateEffect } from '../../common/ImmersiveLevel';
import { InfoHintButton } from '../InfoHintButton';

// 键名/JSON 值输入长度上限（输入有界红线——值放宽容纳对象形态）
const BODY_KEY_MAX: number = 100;
const BODY_VALUE_MAX: number = 2000;

@Component
export struct ProviderBodyPanel {
  // kv 行数组（父页 @State 持有，保存动作在标题栏键；@Link 双向直写）
  @Link pairs: HeaderPair[];
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 沉浸光感档位（行内添加/删除键材质随档——按钮光感簇，同
  // ProviderHeadersPanel 口径）
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
        Text('自定义 Body')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        InfoHintButton({
          text: '发送时把值按键覆盖或追加到请求体顶层，值为合法 JSON。同键覆盖内置字段。名称或值为空的行保存时丢弃'
        })
      }
      .width('100%')
      if (this.pairs.length === 0) {
        Text('暂无自定义 Body。服务商要求的额外顶层字段，例如顶配参数，在此添加')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      }
      ForEach(this.pairs, (pair: HeaderPair, index: number) => {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            TextInput({ placeholder: 'Body 键，顶层字段名', text: pair.k })
              .maxLength(BODY_KEY_MAX)
              .layoutWeight(1)
              .onChange((value: string): void => {
                pair.k = value;
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
          .alignItems(VerticalAlign.Center)
          // 值 = 多行 JSON 文本（TextArea——对象/长值形态）
          TextArea({ placeholder: 'Body 值，JSON，例如 512 或 "abc" 或 {"a":1}', text: pair.v })
            .maxLength(BODY_VALUE_MAX)
            .height(80)
            .width('100%')
            .onChange((value: string): void => {
              pair.v = value;
            })
        }
        .width('100%')
        .padding(10)
        .borderRadius(12)
        .backgroundColor(badgeBg(this.appColorMode))
        .alignItems(HorizontalAlign.Start)
      }, (pair: HeaderPair, index: number): string => 'b' + index)
      // 「添加 Body」= 主操作（2026-09-02 决明要求：官方蓝底——primary=true 强调蓝 +
      // 恒白字；2026-09-03 内容区回退双态：光感态 = 原材质光感（resolvedButton*），实底态 =
      // fallbackButton* 官方强调蓝实底 + 恒白字）
      Button('添加 Body')
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
