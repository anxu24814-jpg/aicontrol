// 上下文用量进度环（2026-09-18 会话上下文增量笔：自 ChatInputBar.ContextRingKey 内环
// 提取共用——输入条圆环键与面板总览卡两处消费，官方 Progress Ring 同形制同色档防漂移）。
// 为何独立成件（宪法反碎片下限②）：两消费方互为平级功能件（输入条件 / 面板内容件），
// 并入任一方都会造成功能件互相 import 的倒挂依赖；本件职责一句话可说清 = 「上下文占比
// 环的官方形态封装」（含色档三档单源）。
// 形态 = 官方 ProgressType.Ring（本仓 Ring 首例 2026-09-17 输入条圆环键；20vp 直径下官方
// 默认描边 4vp 过粗故显式 3vp，大尺寸消费方经 ringSize/ringStroke 覆盖——★ 不叫 size：
// 与组件通用属性 .size() 同名编译 10505001 实锤）；value ≤ 0 仅底环（窗口未知不显占比，
// 拍板 P4 环侧形态）。色档三档（拍板 P7）：常态主题次要色 / ≥80 官方警示 / ≥95 官方错误
// ——深浅自适应系统接管。
@Component
export struct ContextUsageRing {
  // 占比 0~100；≤0 = 窗口未知或无数据（仅底环仍可点——可点性在消费方的包裹键上，本件纯显示）
  @Prop pct: number = -1;
  // 环直径与描边（vp）：默认 = 输入条圆环键口径（20/3，见 ChatInputBar CTX 环注释演进）
  @Prop ringSize: number = 20;
  @Prop ringStroke: number = 3;

  // 色档三档（拍板 P7）——原 ChatInputBar.ctxRingColor 单点迁入，两处消费同源
  private ringColor(): ResourceColor {
    if (this.pct >= 95) {
      return $r('sys.color.ohos_id_color_alert');
    }
    if (this.pct >= 80) {
      return $r('sys.color.ohos_id_color_warning');
    }
    return $r('sys.color.font_secondary');
  }

  build() {
    Progress({ value: this.pct > 0 ? this.pct : 0, total: 100, type: ProgressType.Ring })
      .style({ strokeWidth: this.ringStroke, enableSmoothEffect: true })
      .color(this.ringColor())
      .backgroundColor($r('sys.color.comp_divider'))
      .width(this.ringSize)
      .height(this.ringSize)
  }
}
