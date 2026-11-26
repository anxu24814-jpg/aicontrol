// 提示词变量插入条（表单重构批 6 新件）：职责一句话 = 「编辑器底栏的变量插入条
// 单源」——提示词编辑页 / 系统提示词页 / 助手提示词页三处原本各写一份 3 列 Grid 变量卡
// （P2-4：同一形态重复三次），本笔收进编辑器底栏时提取为一件，三页只传标题与说明。
// · 形态依据 = `docs/设计-表单重构新增样式候选-20261025.html` 08/09 帧：变量从独立卡移到编辑器底栏、
//   贴近输入位置；胶囊单行横滑，不再占一整块版面。
// · 底色 = chip 淡蓝（`Theme.fallbackBlueBg`，反馈二笔灰→蓝）：本件落点从
//   「页底无卡体」改为「白卡内」，仍走《规范-行内按钮与光感》§1 的 chip 族；提示词变量
//   插入胶囊属该条的拍板例外：官方胶囊 + 显式实色 + 原生按压，不接光感。
// · 刷新责任在调用方：本件只消费 PROMPT_VARIABLES 单源，不持有变量集；卡片透明度档位
//   经 @StorageProp 订阅（即时面，拖动滑轨即刷）。
// · 2026-11-05 键盘遮挡处置（三笔）：先做的「聚焦态独立浮条」被决明否决——浮条自带背板
//   成了第二张卡、还把内容挤下去；现走卡内路线：本件形态零变化，由三页在聚焦时压短编辑器
//   并按卡底实测位置滚到位，整张卡底边（含本件说明行）落在键盘上沿之上
//（见各页 editing 高度与 common/KeyboardCardScroll）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PREF_CARD_ALPHA_LEVEL_KEY, CARD_ALPHA_DEFAULT } from '../common/AppPreferences';
import { PROMPT_VARIABLES, PromptVariableInfo } from '../common/providers/PromptVariables';
import { cardDescColor, fallbackBlueBg, selectChipTextColor } from '../common/Theme';

@Component
export struct PromptVariableStrip {
  // 标题（提示词编辑页「插入变量」/ 两提示词页「点击插入变量」）
  label: string = '插入变量';
  // 说明小字（三页文案略有差异，故由调用方给；空串 = 不渲染）
  hint: string = '';
  // 点按上行（父页按自身光标位规则插入 token，本件不碰文本）
  onPick: (info: PromptVariableInfo) => void = (): void => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;

  build() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.wand_and_stars'))
          .fontSize(14)
          .fontColor([cardDescColor()])
        Text(this.label)
          .fontSize(13)
          .fontColor(cardDescColor())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 横向单行（八枚变量不折行）：官方 Scroll 横滚，滚动条按全站统一隐藏；胶囊 =
      // 官方 Capsule + 显式淡蓝底 + 原生按压（变量插入例外，勿改四件套）。
      // focusOnTouch(false)：官方默认点击不获焦，此处显式写死——点胶囊不得把焦点从编辑器
      // 抢走（抢走即键盘收起、编辑框回弹，连点第二枚会落空）
      Scroll() {
        Row({ space: 6 }) {
          ForEach(PROMPT_VARIABLES, (info: PromptVariableInfo) => {
            Button() {
              Text(info.label)
                .fontSize(13)
                .fontColor(selectChipTextColor(false, this.appColorMode))
                .maxLines(1)
            }
            .type(ButtonType.Capsule)
            .padding({ top: 6, bottom: 6, left: 12, right: 12 })
            .backgroundColor(fallbackBlueBg(this.appColorMode, this.cardAlphaLevel))
            .focusOnTouch(false)
            .onClick((): void => {
              this.onPick(info);
            })
          }, (info: PromptVariableInfo): string => info.token)
        }
      }
      .width('100%')
      // 横滚条显式高度（横滚 Scroll 在纵滚 Column 内不设高会取父约束，实测先例都要定高：
      // 13fp 文字 + 上下 6 内距 ≈ 30，取 34 留按压余量）
      .height(34)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)

      if (this.hint !== '') {
        Text(this.hint)
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
