// 段内中间正文步骤（2026-11-04 一轮收束后折叠中间正文笔）。
// 职责一句话：**收束轮中间正文在过程段内的标题、详情开合与正文交互**——段级折叠由
// ChatProcessSegment 承载，本件只管一条中间正文自己的展开态与交互上行。
// · 为什么新开本件（宪法「反碎片下限」三问）：①职责一句话成立，且与思考/工具两个既有行种
//   的正文形制（Text 灰字 / 工具卡）不同——本行种要挂完整 Markdown 树与长按；②不能
//   并入 ChatProcessSegment——该件已承载段容器 + 步骤壳 + 思考三态内容件，再塞一整条正文
//   渲染链会跨两个功能域；也不能并入 ChatMessageItem——那独立气泡展示项，段内步骤不持气泡
//   壳；③实逻辑非转接壳（详情意愿、Markdown 挂载、两条交互上行都在此）。
// · 挂载时机（本笔唯一性能收益）：段折叠时不挂步骤；段展开但本步骤未展开时**只挂标题**，
//   ChatMarkdownBody 只在用户展开后才上树，不创建即不解析该段。不以 height(0)、透明度或
//   离屏方式假装收起。
// · ★ 2026-11-05 展开动效补笔：详情开合与段级同源（applyProcessPresentation 200ms/EaseOut +
//   减弱动态效果门控）；**只有展开方向起画**，收起直写——条件渲染的内容在状态写入同帧卸载，
//   高度插值只会把卡片留成空盒（同段级与思考详情的改判理由，见 ChatProcessSegment 该函数
//   注释）。动效入口经 ChatProcessSegment 导出复用（两件互相 import 的环是既有形制——函数
//   声明提升、调用期取值，安全）。
// · ★ 2026-11-05 菜单笔改判：省略号「更多」键整条删除（复制正文/查看正文两项功能由长按全文
//   面板覆盖：全选复制 + 复制全文 + 引用），本件不再持菜单锚点与 onMoreMenu 上行。
// · 依赖方向：本件 → ChatMessageCompose（视图模型）/ ChatStepTitleRow（共享标题行）/
//   ChatMarkdownBody（正文唯一渲染入口）/ ChatProcessSegment（动效入口）/ Theme 与 ChatFont
//   单源常量；不 import 展示投影（分组与身份全在投影件），不持任何设置项或进程级状态。
// · 交互归属：复制正文/查看正文走既有长按全文面板（只需上行消息 id）、Markdown 锚点跳转
//   复用宿主的滚动链。本件不复制这些业务，也不接工具回调与轮级操作栏。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SEGMENT_BODY_PAD_L, SEGMENT_ROW_PAD_R } from '../../common/Theme';
import { FONT_BODY_DEFAULT, FONT_CODE_DEFAULT, PREF_FONT_BODY_KEY, PREF_FONT_CODE_KEY,
  PREF_FONT_LIB_KEY, bodyFontFamily, codeFontFamily } from '../../common/ChatFont';
import { ChatMessage } from './ChatMessageCompose';
import { ChatStepTitleRow } from './ChatStepTitleRow';
import { ChatMarkdownBody } from './ChatMarkdownBody';
import { applyProcessPresentation } from './ChatProcessSegment';

@Component
export struct ChatIntermediateBodyStep {
  @ObjectLink msg: ChatMessage;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(PREF_FONT_BODY_KEY) fontBodyValue: string = FONT_BODY_DEFAULT;
  @StorageProp(PREF_FONT_CODE_KEY) fontCodeValue: string = FONT_CODE_DEFAULT;
  @StorageProp(PREF_FONT_LIB_KEY) fontLibJson: string = '';
  // 详情开启上行（仅用户关→开时调用；段据此提升手动展开意愿，收尾事件不抢走正在阅读的详情）
  onDetailOpened: () => void = (): void => {};
  // 两条正文交互上行到 ChatPageContent 的既有宿主（锚点滚动 / 消息全文面板）
  onMarkdownAnchor: (id: string) => void = (_id: string): void => {};
  onCopyText: (msgId: string) => void = (_msgId: string): void => {};

  // 详情意愿缺省 false（与思考行的偏好缺省不同——中间正文默认只显标题，展开才解析正文）。
  // 段级「收起」经 collapseDetails() 清掉本字段，重开段回到收起态。
  private detailExpanded(): boolean {
    return this.msg.detailExpanded === true;
  }

  private resolveBodyFamily(): string {
    return bodyFontFamily(this.fontBodyValue, this.fontLibJson);
  }

  private resolveCodeFamily(): string {
    return codeFontFamily(this.fontCodeValue, this.fontLibJson);
  }

  // 详情切换（用户意图单入口）：关→开先上行为宿主钉顶，再写详情；展开 200ms 卡缘下探，
  // 收起直写（内容同帧卸载，插值只会留空盒）
  private toggleDetail(): void {
    const next: boolean = !this.detailExpanded();
    applyProcessPresentation(this.getUIContext(), (): void => {
      if (next) {
        this.onDetailOpened();
      }
      this.msg.detailExpanded = next;
    }, next);
  }

  // 长按开既有消息全文面板：守卫与 ChatMessageItem.requestCopySheet 同形（非流式且非空）。
  // 挂正文层而非标题键，避免与标题热区的展开按压互相吞手势。★ 正文唯一操作入口（原省略号
  // 菜单已删，复制正文/查看正文两项由该面板覆盖）
  private requestCopySheet(): void {
    if (this.msg.streaming === true || this.msg.text === '') {
      return;
    }
    this.onCopyText(this.msg.id);
  }

  build() {
    Column() {
      ChatStepTitleRow({
        title: '中间正文',
        icon: $r('sys.symbol.doc_text'),
        expandable: this.msg.text !== '' || this.detailExpanded(),
        expanded: this.detailExpanded(),
        onToggle: (): void => {
          this.toggleDetail();
        }
      })
      if (this.detailExpanded()) {
        Column() {
          Column() {
            ChatMarkdownBody({
              bindingId: this.msg.bodyBindingId,
              content: this.msg.text,
              endReason: this.msg.bodyEndReason,
              live: false,
              darkMode: this.appColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK,
              bodyFontFamily: this.resolveBodyFamily(),
              codeFontFamily: this.resolveCodeFamily(),
              onAnchor: (id: string): void => {
                this.onMarkdownAnchor(id);
              }
            })
          }
          .width('100%')
          .padding({ left: SEGMENT_BODY_PAD_L, right: SEGMENT_ROW_PAD_R })
          .gesture(LongPressGesture().onAction((_event: GestureEvent): void => {
            this.requestCopySheet();
          }))
        }
        .width('100%')
        // 条件根显式退出，覆盖上下树的默认 OPACITY 淡出（收起后正文不在动画窗内延留卡外）
        .transition(TransitionEffect.IDENTITY)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
