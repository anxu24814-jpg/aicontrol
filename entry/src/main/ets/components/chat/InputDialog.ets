// 通用单输入对话框（2026-08-26 一八四改自 RenameSessionDialog.ets 泛化：
// 重命名会话 + 命令控制带参命令（/btw、/compact）两处复用——重复 2 次以上提取为子程序；
// 原文件/组件名随泛化同步更名，重命名调用点行为不变）。
// ★ aicontrol 迁移（2026-08-30）：自 dshinhm 同名件拷入（依赖仅 @kit.ArkUI）；
// 当日官方样式图对齐修订：标题改居中 + 18fp Medium（原 dshinhm 版 16fp 居左——修订
// 依据见 ConfirmDialog.ets 同处注释），其余（官方实底/空值校验/同值跳过语义）保持
// dshinhm 同款。本项目当前唯一消费方 = 会话卡片长按菜单「重命名」（ChatSessionList）。
// 官方自定义对话框（CustomDialogController + @CustomDialog，调用方弹出）：
// customStyle 默认 false = 官方对话框样式（32vp 圆角/网格自适应宽/遮罩/居中动画，
// custom_dialog_controller.d.ts 原文核实），内容自绘——本地 SDK 26.0.0 Beta2 核实：
// AlertDialogParam 无自定义内容参数（仅 title/subtitle/message/按钮，alert_dialog.d.ts），
// 「官方弹窗 + 中间输入框 + 取消/确认」的唯一官方姿势即本组件。
// ★ 已核正（2026-09-22，原结论作废）：本行原写「CustomDialogControllerOptions 无
// systemMaterial 参数——对话框窗口为官方实底样式（非沉浸光感点位，勿与 AlertDialog 材质化
// 弹窗混同）」系 SDK 26.0.0 Beta2 时点结论；本地 SDK 26.0.0.105 实查
// custom_dialog_controller.d.ts:681 有 `systemMaterial?: SystemUiMaterial`（@since 26.0.0），
// 官方《组件适配沉浸光感》「弹出框」节亦明示该字段 ⇒ 对话框窗口可挂沉浸光感。本组件自身
// 不设材质（窗口材质由调用方 controller options 决定）——全站弹窗调用点已统一挂弹层族材质
//（ImmersiveLevel.overlayMaterial，基准 THICK，2026-09-22 决明指令「半模态/弹窗也改 thick」）。
// 纯展示组件：title/initialText/placeholder/confirmLabel/onConfirm 参数入、回调出，
// 数据与网络编排全在调用方（项目「纯展示」惯例——AppStorage/网络不进弹窗）。
// 按钮布局遵循 AGENTS.md「弹窗按钮布局约定」：取消左 / 确认右（非危险操作不显式红色）。
// 按钮 = 官方文字按钮 ButtonStyleMode.TEXTUAL（@since 11，d.ts 原文「simple text
// without any background color」= 对话框文字按钮形态；★ 坑24：ButtonStyleMode 不在
// @kit.ArkUI 导出清单，**全局裸用不可 import**——import 编译报 10505001）。
// 关闭姿势：取消/确认自管理 controller.close()（取消键另广播 onCancel——见该字段注释，
// 2026-09-10 报障修复）；点遮罩/返回键/Esc = autoCancel 官方默认 + 调用方控制器级 cancel。

@CustomDialog
export struct InputDialog {
  // 官方 @CustomDialog 约定字段（关闭弹窗用；由外层 builder 注入，编译器此处免初始化）
  controller: CustomDialogController;
  // 对话框标题（会话重命名 =「重命名会话」；命令带参 = 命令名等，调用方定）
  title: string = '';
  // 初始文本（重命名 = 当前标题显示先取；命令带参 = ''）
  initialText: string = '';
  // 输入框占位提示（调用方语定）
  placeholder: string = '';
  // 确认键文案（默认「确认」；重命名语义曾为「确认」不变）
  confirmLabel: string = '确认';
  // 允许空输入（一八九改：技能参数可留空——技能激活 args 可选；重命名/命令带参保持
  // false 不变——空值仍 toast「内容不能为空」）
  allowEmpty: boolean = false;
  // 密码型输入（2026-08-30 多 Key 池：添加 API Key 弹窗用——明文脱敏显示；默认 false
  // = 既有调用点（重命名等）行为不变）
  password: boolean = false;
  // 数字型输入（2026-09-01 助手高级设定：上下文消息数/最大输出长度编辑键弹窗用——
  // 数字键盘；默认 false = 既有调用点行为不变。数值范围校验在调用方 onConfirm 内做）
  number: boolean = false;
  // 输入长度上限（2026-09-01 助手重命名接入加——名称有 ASSISTANT_NAME_MAX 约束；0 =
  // 不限〔官方默认 Infinity〕，既有调用点行为不变）
  maxLength: number = 0;
  // 确认回调（默认 trim 后非空文本出；allowEmpty 时空串也出（trim 后仍空 = 传空串）；
  // 弹窗已自校验并 close，编排方只做后续动作）
  onConfirm: (text: string) => void = () => {
  };
  // 取消回调（2026-09-10 报障修复——口令弹窗取消后按钮置灰的根因）：控制器级 cancel 只
  // 覆盖「返回键 / 点遮罩 / Esc」（custom_dialog_controller.d.ts 原文：Callback invoked
  // when the dialog box is closed after the Back button or mask is touched or the Esc key
  // is pressed），弹窗内「取消」键走程序化 controller.close() **不触发它**——凡以本弹窗
  // 关闭为 Promise 出口的调用点（口令输入类 askPassphrase），点「取消」会让 Promise 永不
  // settle，调用方 await 永挂、busy 卡死（重进页面才复位）。故把「取消」键的关闭动作显式
  // 广播出来。默认空实现 = 既有单向回调型调用点（重命名/命令带参等）行为不变。
  onCancel: () => void = () => {
  };
  // 输入框当前文本（@State 驱动回显/confirm 读取；aboutToAppear 由 initialText 播种）
  @State text: string = '';

  aboutToAppear(): void {
    this.text = this.initialText;
  }

  // 确认键：空/纯空白且非 allowEmpty = toast 保留弹窗可重输（P0-1 不静默）；allowEmpty
  // 时空串直接通过；与初值相同 = 视为取消直接关（无网络请求——幂等冗余也不发）；
  // 否则 close + 回调（失败 toast 在编排方）
  private confirm(): void {
    const trimmed: string = this.text.trim();
    if (trimmed === '' && !this.allowEmpty) {
      this.getUIContext().getPromptAction().showToast({ message: '内容不能为空' });
      return;
    }
    this.controller.close();
    // allowEmpty = 参数语义：空串也是用户的合法输入（直接发）；非 allowEmpty = 跳过
    // 恒同值（幂等冗余不发——如重命名未改动）
    if (this.allowEmpty || trimmed !== this.initialText.trim()) {
      this.onConfirm(trimmed);
    }
  }

  build() {
    Column() {
      // 标题：官方对话框标题档（2026-08-30 官方样式图对齐：**居中** + 18fp Medium——
      // 像素实测依据见 ConfirmDialog.ets 同处注释；font_primary 深浅自适应）
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)

      // 输入框：官方 TextInput 默认样式（单行；初值预填便于修改）；
      // defaultFocus 期望打开即弹键盘（CustomDialog overlay 内行为未实测——不生效则点框
      // 聚焦，影响可接受；勿因此加手写焦点控制）。输入内容保持居左（官方输入弹窗惯例
      // ——仅标题/正文居中，可编辑文字居左）
      TextInput({ text: $$this.text, placeholder: this.placeholder })
        .fontSize(15)
        .type(this.password ? InputType.Password :
          (this.number ? InputType.Number : InputType.Normal))
        .showPasswordIcon(this.password)
        // 长度上限（0 = 官方默认 Infinity 不限——d.ts 实锤默认值 Infinity 且「值超 2^31-1
        // 可能异常」，勿用 MAX_SAFE_INTEGER；既有调用点行为不变）
        .maxLength(this.maxLength > 0 ? this.maxLength : Infinity)
        // 官方默认输入样式（背景/边框深浅自适应——勿覆盖，与对话框官方底同体系）
        .defaultFocus(true)
        .width('100%')
        .margin({ top: 16 })

      // 按钮行：取消左 / 确认右（官方文字按钮），两键各占半宽 layoutWeight(1) + 间距 8vp
      // ——官方样式图像素实测 = 横排两键各占半区居中（按钮布局与 ConfirmDialog 同款）
      Row({ space: 8 }) {
        Button('取消')
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .layoutWeight(1)
          .onClick(() => {
            this.controller.close();
            this.onCancel();
          })
        Button(this.confirmLabel)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .layoutWeight(1)
          .onClick(() => {
            this.confirm();
          })
      }
      .width('100%')
      .margin({ top: 14 })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 20, bottom: 12 })
  }
}
