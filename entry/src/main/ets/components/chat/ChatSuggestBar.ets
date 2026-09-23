// 推荐问题 chips 行（2026-09-19 推荐问题功能，任务书-推荐问题-20260919；挂点 =
// ChatMessageItem 助手气泡体 Column 内、底栏之后——底栏挂气泡体 Column 内、双渲染器之后
// 同位）：横排可换行，胶囊形制照 ModelCapsCard chips 先例（选项类 chips 非按钮，不适用
// 行内按钮形制条款——宪法「行内操作按钮官方形制」条 chips 豁免口径）。纯展示 + 点击上行
//（onPick → ChatMessageItem.onSuggestSend → ChatPageContent 复用 onSend(text, []) 直接
// 发送，决策 2；发送后建议随「发送即清空」收起）。无选中态——点击即发送的一次性选项，
// 与 ModelCapsCard 能力多选 chips 的「选中固定」语义不同，故不接 @Link 双态
import { ConfigurationConstant } from '@kit.AbilityKit';
import { badgeBg, cardDescColor } from '../../common/Theme';

@Component
export struct ChatSuggestBar {
  // 建议清单（ChatMessageItem 由 msg.suggestions ?? [] 传入——判据在挂点侧 suggestVisible，
  // 本组件只渲染非空清单；@Observed 对象级观察驱动父组件重渲，本数组随挂点刷新）
  suggestions: string[] = [];
  // chip 点击上行（text = 建议原文——直接发送，不填充输入框，决策 2）
  onPick: (text: string) => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  build() {
    Flex({ wrap: FlexWrap.Wrap }) {
      // 键 = 下标 + 原文（★ 2026-09-20 修复 D2-2）：原文来自模型输出，解析链只压空白与
      // 截 10 字、零去重（两条不同建议可被归并成同一串），裸原文作键可重复——ArkUI 要求
      // ForEach 键唯一；键内保原文 = 原文变则键变（不复用旧组件，避免下标键的陈旧渲染）
      ForEach(this.suggestions, (item: string) => {
        Text(item)
          .fontSize(13)
          .fontColor(cardDescColor())
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor(badgeBg(this.appColorMode))
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
