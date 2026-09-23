// 无视觉能力二次确认弹窗域（2026-09-22 自 ChatPage.ets 域级最小拆分；依据宪法「> 1200 行
// 硬线：对它的实质改动须先把本次改动所属功能域拆到独立文件再动手」——本笔要给全站弹窗挂
// 弹层族材质，ChatPage 越线，故先把本域整块迁出；ChatPage 侧净减行，即硬线唯一例外
//「只减不加」的正当形态）。
// 迁移零行为变更：弹窗文案、按钮文案、语气、关闭姿势逐字照搬；controller 仍在 ChatPage
// 组件内构造（builder 需要组件上下文），本件只产 options——这是不引入运行时风险的拆法
//（不在模块函数里 new CustomDialogController）。
// 职责 = 「模型不支持视觉理解」确认弹窗的 options 工厂：ConfirmDialog 内容 + 遮罩/返回键
// 桥接（onWillDismiss 注册后官方不再自动关，须在回调内 action.dismiss() 放行——
// ConfirmDialog 头注释 / 官方 d.ts：DismissDialogAction.dismiss 即放行回调）+ 弹层族材质
//（overlayMaterial 基准 THICK，2026-09-22 决明指令「半模态/弹窗也改 thick」）。
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
    // 弹层族材质（2026-09-22 决明指令；「无」档 = Material.empty 回落官方底板）
    systemMaterial: overlayMaterial(),
    onWillDismiss: (action: DismissDialogAction): void => {
      handlers.onCancel(); // 遮罩/返回键 = 取消同语义（官方 d.ts：仅交互式关闭进此回调）
      action.dismiss();
    }
  };
}
