// 通用确认对话框（官方 CustomDialogController + @CustomDialog，调用方弹出）。
// ★ 机制选型根因（勿改回 showAlertDialog）：多选删除首版用 UIContext.showAlertDialog，真机
//（领导实测）批量条「删除」点击无反应、弹窗不出现——坑64 同族形态（HDS 容器槽内的弹层
// 绑定失效；aicontrol 弹出点在 HdsTabs→TabContent→ChatSessionList 内）；dshinhm 在同型上下文
//（KimiSessionList 会话列表，HdsTabs→TabContent 内）真机验证过的弹窗机制 =
// CustomDialogController——本组件照该机制建。
// ★ 材质与样式（领导指令与重命名 InputDialog 完全同款，三路删除确认/重命名观感单一来源）：
// customStyle 默认 false 官方对话框样式（32vp 圆角/网格自适应宽/官方底板/遮罩/居中动画，
// custom_dialog_controller.d.ts 核实）；内容根纯排版（不设 backgroundColor/borderRadius/
// systemMaterial——官方面板接管）。标题/正文居中，标题 18fp Medium（API 20+ 官方
// AlertDialog 标题居中 d.ts 实锤 + 官方样式图像素实测：标题行高 ≈18.6vp = 正文 14fp 的
// 1.27 倍）；按钮横排两键各占半宽居中（图实测取消黑 28% 位/删除红 74% 位）。
// 纯展示组件：title/message/confirmLabel/onConfirm 参数入、回调出；数据与删除编排全在
// 调用方。按钮布局遵循「弹窗按钮布局约定」：取消左 / 确认右；本组件定位危险操作确认，
// 确认键显式通讯红（app.color.dialog_confirm_red——dshinhm AccountPage 退出登录同源色）。
// 按钮 = 官方文字按钮 ButtonStyleMode.TEXTUAL（★ 坑24：不在 @kit.ArkUI 导出清单，全局裸用
// 不可 import）；两键各占半宽 layoutWeight(1)——点击区 = 整半行。
// 关闭姿势：取消/确认自管理 controller.close()；点遮罩 = autoCancel 官方默认 true。

// ★ 扩参三件（向后兼容，既有调用零变化）：①confirmTone——确认键语气双色（DANGER = 原
// dialog_confirm_red 删除/清理类破坏语义；NORMAL = font_primary 常规语义）；②onCancel——
// 取消键回调（缺省空 = 不回调）；③cancelLabel——取消键文案（缺省「取消」；去向选择类弹窗
// 取消位是有效选项非「取消」，如「留在本页」）。★ 遮罩/返回键关闭路径的回调须由调用方在
// CustomDialogControllerOptions.onWillDismiss（@since 12）桥接：注册后遮罩/返回不再自动关、
// 回调内 action.dismiss() 放行——autoCancel 直关不进任何回调，Promise 式编排若缺桥接会在
// 遮罩关闭时永挂（先例 = DataSyncPage 上传确认）。

// 确认键语气（破坏性 DANGER 红 / 常规 NORMAL 主色）
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
  // 确认键语气（默认 DANGER；上传/优化类常规动作用 NORMAL）
  confirmTone: ConfirmDialogTone = ConfirmDialogTone.DANGER;
  // 取消回调（取消键路径；遮罩/返回键路径须经 controller 的 onWillDismiss 桥接，见头注释）
  onCancel: () => void = () => {
  };
  // 确认回调（弹窗已自关，编排方只做后续动作）
  onConfirm: () => void = () => {
  };

  build() {
    Column() {
      // 标题：官方对话框标题档（居中 18fp Medium——取证见头注释「材质与样式」条；font_primary
      // 深浅自适应）
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

      // 按钮行：取消左 / 确认右，两键各占半宽 + 间距 8vp（官方样式图横排两键各占半区居中
      // 已对齐）；确认键色随 confirmTone（DANGER 红 / NORMAL 主色）
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
