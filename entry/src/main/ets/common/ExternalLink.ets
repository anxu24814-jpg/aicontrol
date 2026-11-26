// 外链跳转单源：全仓「交给系统处理的外部链接」唯一出口。
// 形态 = UIAbilityContext.openLink（官方《拉起指定应用概述》推荐路径：https 先 App Linking
// 目标直达、未中退化 Deep Linking、再不中开默认浏览器；自定义 scheme 走 Deep Linking 匹配
// 目标应用）。hideFailureTipDialog: true 关闭系统的「暂无可用打开方式」弹窗（API 21+，
// 本地 d.ts 实锤），失败统一由调用方决定提示形态——onFailure 缺省 = 静默（引文卡既有
// 「不打断阅读」口径），传回调则联动提示（消息链接与隐私页口径）。
// ★ parameters 通道：文件管理跳转（filemanager://openDirectory）经
// OpenLinkOptions.parameters 传 {'fileUri': 目标 URI}（官方 FAQ faqs-ability-116 做法）；
// 参数原样透传、本件不裁语义。
// 为何不并入既有件（反碎片下限②一句话理由）：消费方横跨聊天/设置/隐私三域，并入任一域
// 造成跨域依赖；本件零状态、只透传 context 参数，是叶子姿态。
import { common } from '@kit.AbilityKit';

// 打开外链：url 须已过调用方准入（消息链接用 markdownLaunchTarget；引文/隐私页原样透传），
// 本件不重复裁定准入。同步抛出与 Promise 失败统一走 onFailure（缺省静默）。
export function launchExternalLink(context: common.UIAbilityContext, url: string, onFailure?: () => void,
  parameters?: Record<string, Object>): void {
  const fail = (): void => {
    if (onFailure !== undefined) {
      onFailure();
    }
  };
  try {
    if (parameters === undefined) {
      context.openLink(url, { hideFailureTipDialog: true }).catch(fail);
    } else {
      context.openLink(url, { hideFailureTipDialog: true, parameters: parameters }).catch(fail);
    }
  } catch (error) {
    fail();
  }
}
