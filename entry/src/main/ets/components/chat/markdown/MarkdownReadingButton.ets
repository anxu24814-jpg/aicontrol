/** 阅读域功能键。独立于内容分派，预览与数学组件不反向引入正文组件树。 */
// ★ 四档口径：本组件全族 = 轻动作文字键（无底 TEXTUAL + font_secondary），阅读器
// 浮层键不占实底档；禁用态由 Button.enabled 官方自动压暗。fallbackButton* 与 primary 档已退役。
@Component
export struct MarkdownReadingButton {
  @Prop label: string = '';
  @Prop isEnabled: boolean = true;
  // stretch = 跟随父容器宽（半模态吸底键两键各半）。自定义组件非渲染节点，width 不进内部
  // 根节点（真机实锤），满宽只能由根 Button 自身承载；用 constraintSize minWidth 而非
  // width('auto')（后者在 Button 上无官方语义承诺）。缺省保持官方内容自适应宽。
  @Prop stretch: boolean = false;
  onAction: () => void = (): void => {};

  build() {
    Button(this.label)
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .fontColor($r('sys.color.font_secondary'))
      .constraintSize({ minWidth: this.stretch ? '100%' : 0 })
      .enabled(this.isEnabled)
      .onClick((): void => { this.onAction(); })
  }
}
