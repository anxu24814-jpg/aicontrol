// 首启隐私政策同意闸（合规整改笔；形态 = 半模态面板〔决明指令「换成半模态，键和排版按
// 规范」，自绘全屏蒙层卡已改〕，全站 bindSheet 挂载点之一）。
// 宿主 = pages/Index.ets 根 Stack 最顶层（ProactiveBanner / BusyOverlay 同位）挂载位不变，
// 条件宿主 if (!agreed) 内 Column（判据二合规：切分支 = 已同意，发生在面板 onDisappear
// 关闭动画结束写键之后，销毁时面板恒已关）。
// 官方依据与存量迁移口径 = common/PrivacyConsent.ets 头注释（faqs-appgallery-33 / 50 / 84
// 三篇实查）；★ AGC 侧「隐私声明 → 自定义隐私政策」须与本章同开（否则双弹窗）。
// ★ 本面板是全站在役半模态唯一「不可关闭」形态——只能同意或退出，无第三条路：
// · 标题栏无关闭键（sheetTitleBarOptions 第 7 参 menuOverride 传空菜单 = 零键，xmark 不在场；
//   排队面板 menuOverride 接管先例）；
// · 下拉 / 点蒙层 / 侧滑返回 / 三键 back / ESC 全部经 onWillDismiss **恒不放行**（不调
//   action.dismiss()——官方《绑定半模态页面（bindSheet）》「二次确认能力」：注册回调后所有
//   关闭操作都需经 dismiss()，不调即关不掉；放行 = 未同意即可操作应用，违反 faqs-appgallery-33
//   「同意隐私政策前应用不应该有任何调用权限 API 的行为」弹窗义务）。被拦的下拉靠
//   pullSpringBack = true（sheetPanelOptions 第三参，含「下拉被拦」形态的回位通道）回位；
// · 关闭-再开协调五件式不适用（329 组 consent 变体判据）：本面板无关闭路径、无再开路径
//   （关闭 = 同意后组件整体撤场），不存在「离场动效在途再开」竞态面，五件式状态机在此
//   形态下是死码——MarkdownReadingCover ephemeral 变体同律（结构式判据替代）。
// 生命周期与写键时序（faqs-appgallery-50 方式二）：①拉起 = aboutToAppear 置可见性 true
// （宿主挂载即弹，MarkdownReadingCover 先例形态；存量迁移已在 EntryAbility 页面实例化前
// 跑完，此处读值即终值）；②同意 → 可见性 false 程序化关闭（规范口诀「流程自己收尾直接关」）
// → onDisappear（官方：动画结束后回调）写 markPrivacyAgreed → @StorageProp 订阅翻转 →
// 条件宿主撤场。写键不在 onClick 而在 onDisappear = 关闭动画不被宿主移除打断；
// ③不同意 → terminateSelf 终止实例（module.json5 removeMissionAfterTerminate 清任务快照），
// 进程直退无关闭动画，onDisappear 不触发，无误写键路径。
// 档位 = [SheetSize.FIT_CONTENT] 单挡（SheetOptions.detents 首档即初始高度）：三句正文 +
// 链接行 + 双键的内容自适应高度，不给上拉全屏与半屏换档面（内容固定无换档意义）；单挡
// 下滑直达关闭尝试（官方嵌套滚动语义「无挡位可收缩则关闭面板」）被恒不放行拦截回位。
// 首启零权限 API：本组件只读一个持久布尔 + 调 terminateSelf，无任何权限申请与出站请求；
// 半模态模态蒙层（官方默认）挡下层一切命中，同意前应用功能不可达不触发配置类动作。
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { launchExternalLink } from '../common/ExternalLink';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonFont,
  fallbackButtonMaterial, fallbackButtonStateEffect
} from '../common/ImmersiveLevel';
import { CARD_PANEL_WIDTH, cardDescColor, cardTitleColor, usageAccentColor } from '../common/Theme';
import { sheetPanelOptions, sheetTitleBarOptions } from './chat/KimiSheetCommon';
import { markPrivacyAgreed, PREF_PRIVACY_AGREED_KEY, PRIVACY_POLICY_URL } from '../common/PrivacyConsent';

// 双键行键高（面板内操作键同档 = ContextUsageSheet 操作行 40）
const CONSENT_BUTTON_HEIGHT: number = 40;

@Component
export struct PrivacyConsentGate {
  // 同意态（持久键订阅；缺省 false = 未同意——合规面宁严不宽，万一键未注册也按未同意处理）。
  // 翻转点 = 本组件 onDisappear 写键（onDisappear 段，不在 onClick——防打断关闭动画）。
  @StorageProp(PREF_PRIVACY_AGREED_KEY) agreed: boolean = false;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 标题栏材质随沉浸光感总档（sheetTitleBarOptions 第四参）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 面板内按钮双态族能力位（恒 true = 官方标准外观，CONTENT_FALLBACK_KEY 是能力位，
  // 用户面无入口——规范-行内按钮与光感 §3）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  // 面板可见性（$$ 双向）：唯一写 true = aboutToAppear 拉起；唯一写 false = 同意键程序化关闭
  @State private sheetShow: boolean = false;

  aboutToAppear(): void {
    // 未同意首启：宿主挂载即拉起（存量迁移在页面实例化前跑完，此处读值即终值——
    // 新装 false 弹 / 存量 true 不弹）
    if (!this.agreed) {
      this.sheetShow = true;
    }
  }

  // 查看全文（统一出口 launchExternalLink，PrivacyPolicyPage 同款）：失败给中文提示不静默
  private openPolicy(): void {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      launchExternalLink(context, PRIVACY_POLICY_URL, (): void => {
        this.getUIContext().getPromptAction().showToast({ message: '无法打开链接，请稍后重试' });
      });
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '无法打开链接，请稍后重试' });
    }
  }

  // 不同意 → 终止应用实例（faqs-appgallery-50 方式二）；失败显式提示不静默。
  // 面板开着直退（进程终止无离场动画），无关闭写点。
  private declineAndExit(): void {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.terminateSelf().catch((e: Error): void => {
        this.getUIContext().getPromptAction().showToast({ message: '退出失败：' + e.message });
      });
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '退出失败，请从最近任务中关闭应用' });
    }
  }

  // 面板内容（规范-半模态 §3：容器不设左右边距，内容块 CARD_PANEL_WIDTH 自理对齐卡宽线；
  // 标题栏「隐私政策」主标题同源自官方壳，正文不再自绘标题）。无滚动容器（内容短自适应），
  // bindToScrollable 与 §2 clip(false) 不适用。
  @Builder
  privacySheet() {
    HdsNavigation() {
      Column({ space: 14 }) {
        // 正文（文案受面向用户文案规约：句号分句、无冒号分号括号连环）
        Text('欢迎使用「AI 控制台」。请先阅读并同意隐私政策，再进行配置与对话。你的会话与配置保存在本机，对话内容只发送给你自行配置的 AI 服务。')
          .fontSize(14)
          .fontColor(cardDescColor())
          .lineHeight(22)
          .width(CARD_PANEL_WIDTH)
        // 全文链接行（超链接语义色 + 下划线，形制同应用内政策页底部链接行）
        Text('查看隐私政策全文')
          .fontSize(14)
          .fontColor(usageAccentColor(this.appColorMode))
          .decoration({ type: TextDecorationType.Underline })
          .width(CARD_PANEL_WIDTH)
          .onClick((): void => {
            this.openPolicy();
          })
        // 双键行（次钮居左 = 不同意退出，主钮居右 = 同意继续；键序同全站确认弹窗——
        // 破坏性/退出居左，主操作居右。键形制 = 面板内容区行内键 fallbackButton* 四件套，
        // 主键第二参 true = primary 强调蓝恒白字，ChatQuoteSheet 操作键同款）
        Row({ space: 10 }) {
          Button('不同意并退出')
            .fontColor(fallbackButtonFont(this.contentFallback, false))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .height(CONSENT_BUTTON_HEIGHT)
            .layoutWeight(1)
            .onClick((): void => {
              this.declineAndExit();
            })
          Button('同意并继续')
            .fontColor(fallbackButtonFont(this.contentFallback, true))
            .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
            .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
            .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
            .height(CONSENT_BUTTON_HEIGHT)
            .layoutWeight(1)
            .onClick((): void => {
              // 程序化关闭（用户意图已明确）：置 false 走官方关闭动画，写键在 onDisappear
              this.sheetShow = false;
            })
        }
        .width(CARD_PANEL_WIDTH)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 4, bottom: 24 })
    }
    .titleBar(sheetTitleBarOptions('隐私政策', '', (): void => {
      // 无自绘关闭键：本回调不参与菜单构造（第 7 参 menuOverride 传空菜单整段接管、零键）；
      // 本面板不可关闭（只能同意或退出），下拉/蒙层/系统返回由宿主 onWillDismiss 恒不放行拦截
    }, this.immersiveLevel, undefined, { value: [] }))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }

  build() {
    // 空 Stack = 已同意零尺寸零命中（BusyOverlay / ProactiveBanner 同款）；条件宿主在
    // if 内（切分支 = 已同意，发生在 onDisappear 写键后，面板恒已关——判据二合规）
    Stack() {
      if (!this.agreed) {
        Column()
          .width('100%')
          .height('100%')
          .bindSheet($$this.sheetShow, this.privacySheet(), sheetPanelOptions(
            // 恒不放行（不调 action.dismiss()）：同意前面板不可经任何手势绕过——见头注释
            // 合规依据；被拦的下拉靠第三参 pullSpringBack=true 回位
            (_action: DismissSheetAction): void => {
            },
            [SheetSize.FIT_CONTENT], true,
            // onDisappear = 官方「动画结束后回调」：写键放此防宿主移除打断关闭动画
            (): void => {
              markPrivacyAgreed();
            }))
      }
    }
  }
}
