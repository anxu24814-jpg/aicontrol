// 提问卡分页域（2026-11-08 两千一百二十八笔新增功能域）：单题分页的页码判据与 ‹ n/N ›
// 步进器。职责一句话 = 「当前第几题」的边界计算与切题控件，题干/选项/键区仍归
// ChatAskUserCard（本件零业务、零草稿、零提交）。
// · 为什么新开本件（宪法「新增功能域不论行数一律先拆」+ 反碎片下限三问）：①职责一句话 =
//   分页导航；②无既有同域可并——ChatDockTitles 是标题/进度纯函数，步进器是 UI；③非纯转接
//   壳：clamp/标签/边界判据是分页语义本体，且被三处消费（卡件 Body 头行、键区上一题禁用、
//   草稿恢复夹取）。同一形制第三处出现后再抽共用件的规则不适用（本次即三处）。
// · 形制单源 = ChatMessageItem 回答版本步进器（TEXTUAL 无底图标键 + 次要色计数文字 +
//   边界侧箭头 enabled(false)+opacity(0.4)）；计数文案「n/N」与竞品图一致，不自创
//   「第 n 题 / 共 N 题」双行。
// · 分页态真源在 ChatAskUserCard.currentIndex（随 msg.askDraft 持久化，虚拟列表回收重建
//   后停在原题）；本件只读 @Prop 与上行 delta，禁自持页码。
import { PREF_FONT_BODY_KEY, PREF_FONT_LIB_KEY, FONT_BODY_DEFAULT, bodyFontFamily }
  from '../../common/ChatFont';

// 页码夹取（坏草稿/换题后题数缩短/末题提交时删题等一律收敛到 [0, count-1]；count 0 → 0）
export function clampAskPage(index: number, count: number): number {
  if (count <= 1) {
    return 0;
  }
  if (index < 0) {
    return 0;
  }
  return index >= count ? count - 1 : index;
}

// 计数标签（单题不渲染步进器，调用方先判 count >= 2；本函数对 count<=0 回 '' 防误显 0/0）
export function askPageLabel(index: number, count: number): string {
  if (count <= 0) {
    return '';
  }
  return (clampAskPage(index, count) + 1) + '/' + count;
}

@Component
export struct ChatAskPager {
  // 当前页下标与总题数（父件 currentIndex / questions.length 直传）
  @Prop index: number = 0;
  @Prop count: number = 0;
  // 切题上行（-1 上一题 / +1 下一题；边界侧控件已禁用，上行值父件仍会夹取一次）
  onStep: (delta: number) => void = (_delta: number): void => {};
  @StorageProp(PREF_FONT_BODY_KEY) fontBodyValue: string = FONT_BODY_DEFAULT;
  @StorageProp(PREF_FONT_LIB_KEY) fontLibJson: string = '';

  private resolveBodyFamily(): string {
    return bodyFontFamily(this.fontBodyValue, this.fontLibJson);
  }

  build() {
    if (this.count >= 2) {
      Row({ space: 2 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(16)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        // 边界置灰不可点（官方 enabled 只断交互不改色，须显式压暗——规范 §1 轻动作文字键条）
        .enabled(this.index > 0)
        .opacity(this.index > 0 ? 1.0 : 0.4)
        .onClick((): void => {
          this.onStep(-1);
        })
        Text(askPageLabel(this.index, this.count))
          .fontSize(13)
          .fontFamily(this.resolveBodyFamily())
          .fontColor($r('sys.color.font_secondary'))
          .padding({ left: 4, right: 4 })
        Button() {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .enabled(this.index < this.count - 1)
        .opacity(this.index < this.count - 1 ? 1.0 : 0.4)
        .onClick((): void => {
          this.onStep(1);
        })
      }
    }
  }
}
