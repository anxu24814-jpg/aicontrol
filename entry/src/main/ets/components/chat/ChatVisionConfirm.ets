// 无视觉能力二次确认弹窗域（自 ChatPage 域级拆出，弹窗文案、按钮文案、语气、关闭姿势逐字
// 照搬）：职责 = 「模型不支持视觉理解」确认弹窗的 options 工厂。controller 仍在 ChatPage
// 组件内构造（builder 需要组件上下文），本件只产 options——不在模块函数里 new
// CustomDialogController 的零风险拆法。
// 内容 = ConfirmDialog + 遮罩/返回键桥接（onWillDismiss 注册后官方不再自动关，须在回调内
// action.dismiss() 放行——见 ConfirmDialog 头注释 / 官方 d.ts）+ 弹层族材质（overlayMaterial
// 基准 THICK，决明指令「半模态/弹窗也改 thick」）。
// 调用方 = ChatPage.openVisionConfirm（确认 = 走原发送体；取消/遮罩/返回 = 草稿回写）。
import { ConfirmDialog, ConfirmDialogTone } from './ConfirmDialog';
import { overlayMaterial } from '../../common/ImmersiveLevel';

// 两路回调契约（ChatPage 接线到发送链与草稿回写链）
export interface VisionConfirmHandlers {
  onConfirm: () => void;
  onCancel: () => void;
}

export function visionConfirmOptions(handlers: VisionConfirmHandlers): CustomDialogControllerOptions {
  return {
    builder: ConfirmDialog({
      title: '模型不支持视觉理解',
      message: '图片附件可能无法被识别，仍要发送吗',
      confirmLabel: '仍然发送',
      cancelLabel: '取消',
      confirmTone: ConfirmDialogTone.NORMAL,
      onConfirm: handlers.onConfirm,
      onCancel: handlers.onCancel
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    // 弹层族材质（「无」档 = Material.empty 回落官方底板）
    systemMaterial: overlayMaterial(),
    onWillDismiss: (action: DismissDialogAction): void => {
      handlers.onCancel(); // 遮罩/返回键 = 取消同语义（官方 d.ts：仅交互式关闭进此回调）
      action.dismiss();
    }
  };
}
