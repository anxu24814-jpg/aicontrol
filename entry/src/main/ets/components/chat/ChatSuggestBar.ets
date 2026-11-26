// 推荐问题 chips 行（挂点 = ChatMessageItem 助手气泡体 Column 内、底栏之后同位）：横排可
// 换行，胶囊形制照 ModelCapsCard chips 先例（选项类 chips 非按钮，不适用行内按钮形制条款
// ——宪法「行内操作按钮官方形制」条 chips 豁免口径）；底色与助手气泡统一同取 cardBg
//（挂点在气泡卡外下方，同底色即同族观感；原 badgeBg 灰底已退役）。纯展示 + 点击上行
//（onPick → ChatMessageItem.onSuggestSend → ChatPageContent 复用 onSend(text, []) 直接发送；
// 发送后建议随「发送即清空」收起）。无选中态——点击即发送的一次性选项，与 ModelCapsCard
// 能力多选 chips 的「选中固定」语义不同，故不接 @Link 双态
import { ConfigurationConstant } from '@kit.AbilityKit';
import { cardBg, cardDescColor } from '../../common/Theme';
import { PREF_CARD_ALPHA_LEVEL_KEY, CARD_ALPHA_DEFAULT } from '../../common/AppPreferences';
import { FONT_BODY_DEFAULT, PREF_FONT_BODY_KEY, PREF_FONT_LIB_KEY, bodyFontFamily }
  from '../../common/ChatFont';

@Component
export struct ChatSuggestBar {
  // 建议清单（ChatMessageItem 由 msg.suggestions ?? [] 传入——判据在挂点侧 suggestVisible，
  // 本组件只渲染非空清单；@Observed 对象级观察驱动父组件重渲，本数组随挂点刷新）
  suggestions: string[] = [];
  // chip 点击上行（text = 建议原文——直接发送，不填充输入框，决策 2）
  onPick: (text: string) => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位只读订阅：胶囊底色表达式显式传参建依赖
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  // 正文字体两键 @StorageProp 自订阅：推荐语属会话页消息显示面，随正文字体选择即时变化；
  // 家族串推导单源 = ChatFont.bodyFontFamily
  @StorageProp(PREF_FONT_BODY_KEY) fontBodyValue: string = FONT_BODY_DEFAULT;
  @StorageProp(PREF_FONT_LIB_KEY) fontLibJson: string = '';

  private resolveBodyFamily(): string {
    return bodyFontFamily(this.fontBodyValue, this.fontLibJson);
  }

  build() {
    Flex({ wrap: FlexWrap.Wrap }) {
      // 键 = 下标 + 原文（修复 D2-2）：原文来自模型输出，解析链只压空白与截 10 字、零去重
      //（两条不同建议可被归并成同一串），裸原文作键可重复——ArkUI 要求 ForEach 键唯一；
      // 键内保原文 = 原文变则键变（不复用旧组件，避免下标键的陈旧渲染）
      ForEach(this.suggestions, (item: string) => {
        Text(item)
          .fontSize(13)
          .fontFamily(this.resolveBodyFamily())
          .fontColor(cardDescColor())
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor(cardBg(this.appColorMode, this.cardAlphaLevel))
          .margin({ right: 8, bottom: 4 })
          .onClick((): void => {
            this.onPick(item);
          })
      }, (item: string, index: number): string => index + '|' + item)
    }
    .width('100%')
    .margin({ top: 2 })
  }
}
