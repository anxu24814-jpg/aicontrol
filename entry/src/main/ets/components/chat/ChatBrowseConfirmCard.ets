// 高危动作确认卡（2026-09-18 内置浏览器 P2·B 单元，任务书-内置浏览器P2-20260918
// §2.6-3，形制照 ChatAskUserCard 裁剪）：工具轮预检命中高危（browse_act 词表/属性层判定
// 或 http_request 写方法）时暂停执行先问用户——点「允许一次」放行（browse_act 经注册表
// onApproved 写单次批准戳），点「拒绝」回拒绝文案让模型收尾。
// ★ 2026-09-19 HTTP 请求工具笔确认卡泛化：渲染不再限 browse_act（ChatToolCard 判据
// 已去工具名条件）；卡面标题与小字按 msg.toolName 分支——browse_act 两句逐字不动，
// 其余（现役 = http_request）走网络请求文案（补「卡上不预览请求内容」边界句）；中间说明
// 串由 msg.toolConfirmText 通用承载（各工具预检产自己的说明串）。
// ★ 2026-09-20 审批卡视觉迁移笔 A（方案 §2.1）：①标题行**删除**——标题已上移专属卡头
//（ChatToolCard.confirmTitle，防与卡体逐字重复）；②主因句自 13fp 次要色升 14fp 主色、
// 最多 2 行；③不可逆档新增风险块（底 = 危险红 8% / 14%，圆角 12、内距 12，红字 12fp）。
// 脚注、双键形制（等宽 fallbackButton* 四件套）与容器内距均逐字不动。
// ★ 2026-09-20 审批卡会话级允许笔 C（方案 §2.6）：非不可逆档键行改**三键**——中位新增
//「本会话内允许」（点一次 = 本次启动内、该会话内、这个工具不再弹确认卡），不可逆档仍两键。
// 键行几何按试验台 C5 圈选样张（字号 13 + 内距 6/6），为本主题第四处自绘例外（申报）。
// 渲染位 = ChatToolCard 卡体的确认卡分支（running 且 toolConfirmText 非空且未作答
// ——见 ChatToolCard.confirmAwaiting）；作答后卡转回执分支，说明串保留供回执行体首取用。
// 组件只做展示与上行，零业务（同 ChatAskUserCard 契约）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { cardDescColor, cardTitleColor } from '../../common/Theme';
import { CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont,
  fallbackButtonMaterial, fallbackButtonStateEffect } from '../../common/ImmersiveLevel';
import { CONFIRM_LEVEL_IRREVERSIBLE } from '../../common/providers/ToolContracts';
import { TOOL_BROWSE_ACT } from '../../common/providers/ToolTypes';
import { ChatMessage } from './ChatMessageCompose';

@Component
export struct ChatBrowseConfirmCard {
  @ObjectLink msg: ChatMessage;
  // 作答上行（ChatToolCard 透传 ChatPage → ChatSendCtrl.resolveBrowseConfirm）
  onSubmit: (callId: string, approved: boolean) => void = (callId: string,
    approved: boolean): void => {};
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;

  // 卡面小字（按工具分支：browse_act 原句逐字不动；http_request 补不预览边界句）。
  // 标题自本件迁出（笔 A）——只余此一句，卡头标题在 ChatToolCard.confirmTitle
  private confirmNote(): string {
    return this.msg.toolName === TOOL_BROWSE_ACT ?
      '这个操作会改动网站上的数据。允许后只执行这一次，需要时助手会再次征求你的同意。' :
      '这个请求会发送到对方服务器，卡上不预览请求内容。允许后只执行这一次，需要时助手会再次征求你的同意。';
  }

  // 不可逆档判据（风险块显隐；undefined = 写操作档兜底——老数据不因缺字段而错显红块）
  private irreversible(): boolean {
    return this.msg.toolConfirmLevel === CONFIRM_LEVEL_IRREVERSIBLE;
  }

  // 风险块底色（★ 自绘·已拍板两处之一：危险红浅档 8% / 深档 14%，AARRGGBB 前置写法；
  // 与档位徽章的实底红同源单色，见 Theme/资源 dialog_confirm_red）
  private riskFill(): string {
    return this.appColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ?
      '#24E84026' : '#14E84026';
  }

  build() {
    Column({ space: 10 }) {
      // 主因句（笔 A：13fp 次要色 → 14fp 主色、最多 2 行；文本 = 预检产的说明串）
      Text(this.msg.toolConfirmText ?? '')
        .fontSize(14)
        .fontColor(cardTitleColor())
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      // 风险块（仅不可逆档——写操作档不出现）
      if (this.irreversible()) {
        Text('这个动作可能无法撤销，请确认后再允许。')
          .fontSize(12)
          .fontColor($r('app.color.dialog_confirm_red'))
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .backgroundColor(this.riskFill())
      }
      Text(this.confirmNote())
        .fontSize(12)
        .fontColor(cardDescColor())
        .width('100%')
      // 键行两分支（★ 2026-09-20 笔 C §3.1/§3.4）：不可逆档 = 两键官方几何逐字不动；
      // 非不可逆档 = 三键（几何 = 试验台 C5 圈选样张：字号 13 + 内距 6/6，本笔第四处自绘
      // 例外申报）——「本会话内允许」六字在 324vp 键行、每键约 103vp 的可用宽下装不下官方
      // 形制（按 16fp 估六字 ≈ 96vp 已近满宽），扣掉官方内距必然裁切或换行
      // ★ 两分支的键各自内联五属性（不套 @Builder）：五属性随 contentFallback /
      // immersiveLevel 两个 @StorageProp 变化，内联是本工程真机验证过的响应形态——同一枚键
      // 的写法在件内出现多次属有意为之的形态重复，不是漏提取
      if (this.irreversible()) {
        Row({ space: 10 }) {
          // 两键 = 内容区组件，按惯例走 fallbackButton* 双态（规范-行内按钮与光感 §3）——
          // 2026-09-18 决明真机反馈：原 resolvedButton*（弹窗/标题栏豁免区族）在光感档下
          // 背景恒透明靠材质垫底，内容区材质官方不生效，主钮白字落白卡 = 「允许一次」不可见
          Button('拒绝')
            .fontColor(fallbackButtonFont(this.contentFallback, false))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .layoutWeight(1)
            .onClick((): void => {
              this.onSubmit(this.msg.toolCallId ?? '', false);
            })
          Button('允许一次')
            .fontColor(fallbackButtonFont(this.contentFallback, true))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .layoutWeight(1)
            .onClick((): void => {
              this.onSubmit(this.msg.toolCallId ?? '', true);
            })
        }
        .width('100%')
      } else {
        Row({ space: 8 }) {
          Button('拒绝')
            .fontSize(13)
            .padding({ left: 6, right: 6 })
            .fontColor(fallbackButtonFont(this.contentFallback, false))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .layoutWeight(1)
            .onClick((): void => {
              this.onSubmit(this.msg.toolCallId ?? '', false);
            })
          // 第三键（笔 C §3.2）：意图先行——同一同步块内先写意图再上行，工具轮读到必然为真
          Button('本会话内允许')
            .fontSize(13)
            .padding({ left: 6, right: 6 })
            .fontColor(fallbackButtonFont(this.contentFallback, false))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .layoutWeight(1)
            .onClick((): void => {
              this.msg.toolConfirmSessionAllow = true;
              this.onSubmit(this.msg.toolCallId ?? '', true);
            })
          Button('允许一次')
            .fontSize(13)
            .padding({ left: 6, right: 6 })
            .fontColor(fallbackButtonFont(this.contentFallback, true))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .layoutWeight(1)
            .onClick((): void => {
              this.onSubmit(this.msg.toolCallId ?? '', true);
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 12, top: 4, bottom: 8 })
  }
}
