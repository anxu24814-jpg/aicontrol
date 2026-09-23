// 通用确认对话框（2026-08-29 会话多选删除新建；2026-08-30 材质统一改版）：官方自定义
// 对话框（CustomDialogController + @CustomDialog，调用方弹出）。
// ★ 机制选型根因（勿改回 showAlertDialog）：多选删除首版用 UIContext.showAlertDialog，
// 真机（领导实测）批量条「删除」点击无反应、弹窗不出现——坑64 同族形态（HDS 容器槽内的
// 弹层绑定失效；aicontrol 弹出点在 HdsTabs→TabContent→ChatSessionList 内）。dshinhm 的
// showAlertDialog 先例（AccountPage/AddressInfoPage）都在页面上下文，非 TabContent 槽内；
// 而 dshinhm 在同型上下文（KimiSessionList 会话列表，HdsTabs→TabContent 内）真机验证过的
// 弹窗机制 = CustomDialogController（重命名弹窗，一八二改）——本组件照该机制建。
// ★ 材质统一（2026-08-30 领导指令「多选删除和长按删除弹窗材质统一为重命名的」）：原版
// customStyle: true + 内容根自绘 systemMaterial 光感面板（反馈轮 2 回补形态）；重命名
// InputDialog（dshinhm 同源件）= customStyle 默认 false 官方对话框样式（32vp 圆角/
// 网格自适应宽/官方底板/遮罩/居中动画，custom_dialog_controller.d.ts 原文核实）。本组件
// 改为与 InputDialog 完全同款：官方实底底板 + 内容根 width('100%') 纯排版（不设
// backgroundColor/borderRadius/systemMaterial——官方面板接管）；customStyle 随之在调用方
// 移除。三路删除确认弹窗（多选/长按）与重命名弹窗观感从此单一来源。
// ★ 官方样式图对齐（2026-08-30 领导发官方规范图后续修）：标题/正文居中（d.ts 实锤
// API 20+ 官方 AlertDialog 标题居中 + 图像素实测中心偏移 0px）；标题 18fp Medium
//（图实测标题行高 ≈18.6vp = 正文 14fp 的 1.27 倍，16/14=1.14 不符、18/14=1.29 吻合；
// 官方字号阶梯为偶数档）；按钮横排两键各占半宽居中（图实测取消黑 28% 位/删除红 74%
// 位——与既有半宽 layoutWeight 布局一致，保持）。
// 纯展示组件：title/message/confirmLabel/onConfirm 参数入、回调出；数据与删除编排全在
// 调用方（项目「纯展示」惯例）。按钮布局遵循「弹窗按钮布局约定」：取消左 / 确认右；
// 本组件定位危险操作确认，确认键显式通讯红（app.color.dialog_confirm_red——dshinhm
// AccountPage 退出登录同源色）。
// 按钮 = 官方文字按钮 ButtonStyleMode.TEXTUAL（★ 坑24 dshinhm 版：不在 @kit.ArkUI 导出
// 清单，全局裸用不可 import）；两键各占半宽 layoutWeight(1)——点击区=整半行（InputDialog
// 一八三改沉淀）。
// 关闭姿势：取消/确认自管理 controller.close()；点遮罩 = autoCancel 官方默认 true。

// ★ 2026-09-12 UI 同形异构归一笔 5 扩参（向后兼容）：①confirmTone——确认键语气双色
// （DANGER = 原 dialog_confirm_red 删除/清理类破坏语义；NORMAL = font_primary 常规
// 语义，与官方 showDialog 确认键现值一致），既有调用零变化（默认 DANGER）；②onCancel——
// 取消键回调（缺省空 = 不回调）；③cancelLabel（同日双取消键统一笔追加）——取消键文案
// （缺省「取消」；去向选择类弹窗取消位是有效选项非「取消」，如「留在本页」），既有调用
// 零变化。★ 遮罩/返回键关闭路径的回调须由调用方在
// CustomDialogControllerOptions.onWillDismiss（@since 12，custom_dialog_controller.d.ts
// 实存）桥接：注册后遮罩/返回不再自动关、回调内 action.dismiss() 放行——autoCancel 直关
// 不进任何回调，Promise 式编排若缺桥接会在遮罩关闭时永挂（先例 = DataSyncPage 上传确认）。

// 确认键语气（归一笔 5：破坏性 DANGER 红 / 常规 NORMAL 主色）
export enum ConfirmDialogTone {
  DANGER,
  NORMAL
}

@CustomDialog
export struct ConfirmDialog {
  // 官方 @CustomDialog 约定字段（关闭弹窗用；由外层 builder 注入，编译器此处免初始化）
  controller: CustomDialogController;
  // 对话框标题（「删除会话」——调用方定）
  title: string = '';
  // 正文说明（含后果警示语，调用方定）
  message: string = '';
  // 确认键文案（危险动作语义词，如「删除」）
  confirmLabel: string = '确认';
  // 取消键文案（缺省「取消」；去向选择类弹窗取消位是有效选项，如「留在本页」）
  cancelLabel: string = '取消';
  // 确认键语气（默认 DANGER = 既有 11 处调用观感零变化；上传/优化类常规动作用 NORMAL）
  confirmTone: ConfirmDialogTone = ConfirmDialogTone.DANGER;
  // 取消回调（取消键路径；遮罩/返回键路径须经 controller 的 onWillDismiss 桥接，见头注释）
  onCancel: () => void = () => {
  };
  // 确认回调（弹窗已自关，编排方只做后续动作）
  onConfirm: () => void = () => {
  };

  build() {
    Column() {
      // 标题：官方对话框标题档（2026-08-30 官方样式图对齐：**居中** + 18fp Medium——像素
      // 实测官方图标题行高 ≈18.6vp（正文 14fp 的 1.27 倍）+ 官方偶数字号阶梯，16fp 旧值
      // 偏小偏细；font_primary 深浅自适应。d.ts 佐证：API 20+ 官方 AlertDialog 标题居中）
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)

      // 正文：14fp 次要色（官方 AlertDialog message 层级）+ 居中（官方样式图对齐）
      Text(this.message)
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 12 })

      // 按钮行：取消左 / 确认右，两键各占半宽 + 间距 8vp——官方样式图像素实测 =
      // 横排两键各占半区居中（取消黑 28% 位/删除红 74% 位），本布局已对齐保持；
      // 确认键色随 confirmTone（归一笔 5：DANGER 红 / NORMAL 主色）
      Row({ space: 8 }) {
        Button(this.cancelLabel)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .layoutWeight(1)
          .onClick(() => {
            this.controller.close();
            this.onCancel();
          })
        Button(this.confirmLabel)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .layoutWeight(1)
          .fontColor(this.confirmTone === ConfirmDialogTone.NORMAL ?
            $r('sys.color.font_primary') : $r('app.color.dialog_confirm_red'))
          .onClick(() => {
            this.controller.close();
            this.onConfirm();
          })
      }
      .width('100%')
      .margin({ top: 14 })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 20, bottom: 12 })
  }
}
