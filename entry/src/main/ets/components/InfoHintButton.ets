// 卡片右上角「更多信息」图标键（2026-09-02 三卡共用件，2026-09-07 光感新规范开关卡接入）：
// info_circle 图标钮（ButtonStyleMode.TEXTUAL 形态照卡内双键先例——SymbolGlyph 18fp +
// font_secondary 灰）+ bindPopup 官方气泡（毛玻璃底/圆角/箭头/遮罩关闭均系统默认样式——
// popupColor 不设 = API 11+ TRANSPARENT + COMPONENT_ULTRA_THICK 官方形态；文字 sys.color
// 自适应深浅色）。
// 用途 = 长说明文字移入气泡、卡面只留标题（线索：ProviderHeadersPanel / ProviderBodyPanel /
// ProviderBalancePanel 三卡 + AppearancePage 光感新规范开关卡；ProviderConfigPanel 协议卡
// 因含 if 分支多段气泡为专属 @Builder 未并入本件）。触发 = 点击弹出（bindTips 仅悬浮触发
// 不适用触屏——选 bindPopup）；再点/点页面其他区域 = 关闭（autoCancel 默认）；系统路径
// 关闭（遮罩/自动移位）经 onStateChange 回写复位，保证再次点击可重开。
// ★ 2026-09-22 决明指令「气泡全 thick」：气泡改挂弹层族材质（overlayMaterial，基准 THICK
// 随沉浸光感总档；「无」档 = Material.empty，回落官方默认毛玻璃形态）——本件一处即覆盖
// 全部 ⓘ 说明气泡落点。
import { overlayMaterial } from '../common/ImmersiveLevel';

@Component
export struct InfoHintButton {
  // 气泡说明全文（静态文本——表单场景无动态刷新需求；@Prop 值传参）
  @Prop text: string = '';
  // 气泡显示开关（bindPopup 受控 show）
  @State private showHint: boolean = false;

  build() {
    Button() {
      SymbolGlyph($r('sys.symbol.info_circle'))
        .fontSize(18)
        .fontColor([$r('sys.color.font_secondary')])
    }
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .onClick((): void => {
      this.showHint = !this.showHint;
    })
    .bindPopup(this.showHint, {
      builder: (): void => {
        this.hintPopup();
      },
      placement: Placement.BottomRight,
      // 弹层族材质（2026-09-22 决明指令「气泡全 thick」）
      systemMaterial: overlayMaterial(),
      onStateChange: (event: PopupStateChangeParam): void => {
        if (!event.isVisible) {
          this.showHint = false;
        }
      }
    })
  }

  // 气泡内容（CustomPopupOptions.builder——首层容器禁 position 属性）：宽度固定 280
  // 防超长文本单行出界；对齐/内距与协议卡专属气泡同款
  @Builder
  hintPopup() {
    Column() {
      Text(this.text)
        .fontSize(13)
        .fontColor($r('sys.color.font_primary'))
        .lineHeight(20)
        .width('100%')
    }
    .width(280)
    .padding(12)
    .alignItems(HorizontalAlign.Start)
  }
}
