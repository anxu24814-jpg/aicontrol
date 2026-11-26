// 草稿附件单件重试的点击通道（DS 全家桶二期 S4 #12）。
// 为什么不走 @Prop 回调链：附件条由 ChatInputBar 实例化，InputBar 的入参面再由 ChatPageContent
// 透传——而 ChatPageContent 剔头已 1224、在 1200 硬线上（本批红线零触及）。加一个回调要在这
// 两件各开一个参数，等于在超线件里再加行。
// 本件把「键 → 编排」一跳收在零 import 叶子：ChatPage（持有 AttachmentPickCtrl 的层）在构造期
// 登记处理器，ChatAttachmentStrip 直接 request 一下即可。未登记 = no-op（直跑夹具、非会话页
// 形态天然空转）。与 ChatContinueSupport 的续写通道同款（续写入口 2026-11-15 迁消息「更多」
// 菜单，通道形制不变），两处一致。
let retryHandler: ((fileId: string) => void) | null = null;

export function registerAttachmentRetry(handler: (fileId: string) => void): void {
  retryHandler = handler;
}

export function requestAttachmentRetry(fileId: string): void {
  if (retryHandler !== null && fileId !== '') {
    retryHandler(fileId);
  }
}

// 注销口（自检轮补，成对释放）：处理器闭包持有页面级附件控制器——页面销毁必须清空，
// 否则模块级单例长期持有已销毁页的控制器引用（宪法「寿命匹配」红线）
export function clearAttachmentRetry(): void {
  retryHandler = null;
}
