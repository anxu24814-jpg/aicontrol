// 只读井（W3；表单重构批 3 首消费于凭据编辑页，第二消费面（反馈页）出现时按反碎片③上收
// 本件——原注释约定「第二处消费出现时再上收 components/ReadonlyField.ets」）。
// 职责一句话 = 「一行只读键值容器的形制单源」：浅灰井底 + 锁图标 + 标签（灰）+ 等宽值。
// 判据与形态单源 = docs/规范-列表卡片与组卡.md §4.17（改形制先读该节）。
// · 用途：把「值不可编辑」这件事显性化——凭据编辑页的「值不回显」、反馈页的环境信息，
//   都需要一行确定态，而不是让空输入框或裸文本自己解释。
// · 形态：行高 36、圆角 10、井底 Theme.wellBg（随卡底透明度档位叠 alpha）、左右内距 12；
//   图标 13fp（默认锁；凭据引用方式传 key）+ 标签 13fp cardDescColor + 值 13fp 等宽
//   （代码字族单源 ChatFont）单行省略。
//   warn = true 时值走系统警告色（缺失 / 不可用态），标签与图标不变。
// · 不做：不接点击（纯展示）、不加输入能力、不做成「可复制的输入框外观」——那是另一个形态。
//   刷新责任在调用方（普通成员入参，父状态变化随父重建即刷；坑16 家族）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { CARD_ALPHA_DEFAULT, PREF_CARD_ALPHA_LEVEL_KEY } from '../common/AppPreferences';
import { codeFontFamilyNow } from '../common/ChatFont';
import { cardDescColor, wellBg } from '../common/Theme';

@Component
export struct ReadonlyField {
  // 标签（空串 = 只显示值；标签文案归调用方，本件不自造）
  label: string = '';
  // 值（等宽显示；只读，不接受编辑）
  value: string = '';
  // 值显示行数（默认 1 行省略；环境信息这类「整行都要看见」的长值传 2——仍是只读井，
  // 不是第二种控件）
  valueLines: number = 1;
  // 警告态（值缺失 / 不可用——走系统警告色，标签与图标不变）
  warn: boolean = false;
  // 行首图标（默认锁 = 「不可编辑」；凭据引用方式传 key——同形制不同语义，不另开组件）
  icon: Resource = $r('sys.symbol.lock');
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 井底随卡底透明度档位（与全站灰面同口径，档位变化即刷）
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;

  build() {
    Row({ space: 8 }) {
      SymbolGlyph(this.icon)
        .fontSize(13)
        .fontColor([cardDescColor()])
      if (this.label !== '') {
        Text(this.label)
          .fontSize(13)
          .fontColor(cardDescColor())
      }
      Text(this.value)
        .fontSize(13)
        // 等宽字体走全站代码字族单源（ChatFont；用户可在「消息字体」里换）——禁写字面量族名
        .fontFamily(codeFontFamilyNow())
        .fontColor(this.warn ? $r('sys.color.ohos_id_color_warning') :
          $r('sys.color.font_secondary'))
        .layoutWeight(1)
        .maxLines(this.valueLines)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .constraintSize({ minHeight: 36 })
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .borderRadius(10)
    .backgroundColor(wellBg(this.appColorMode, this.cardAlphaLevel))
    .alignItems(VerticalAlign.Center)
  }
}
