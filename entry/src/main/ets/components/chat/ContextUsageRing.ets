// 上下文用量进度环（自 ChatInputBar.ContextRingKey 内环提取共用——输入条圆环键消费；
// 面板总览卡 2026-11-09 改线性进度条后不再用环，但占比色档仍走本件导出的
// contextUsageToneColor，两种可视化同档防漂移）。
// 为何独立成件（宪法反碎片下限②）：两消费方互为平级功能件（输入条件 / 面板内容件），
// 并入任一方都会造成功能件互相 import 的倒挂依赖；本件职责一句话可说清 = 「上下文占比
// 环的官方形态封装 + 占比色档单源」。
// 形态 = 官方 ProgressType.Ring（本仓 Ring 首例；20vp 直径下官方默认描边 4vp 过粗故显式
// 3vp，大尺寸消费方经 ringSize/ringStroke 覆盖——★ 不叫 size：与组件通用属性 .size()
// 同名编译 10505001 实锤）；value ≤ 0 仅底环（窗口未知不显占比）。色档三档：常态主题
// 次要色 / ≥80 官方警示 / ≥95 官方错误——深浅自适应系统接管。
// ★ 色档单源（2026-11-09）：环与首卡线性进度条共三档，阈值与色值只在下方函数写一次，
// 消费侧禁复写；导出的同时仍留在本件 = 与环同域，不新开碎文件。
export function contextUsageToneColor(pct: number): ResourceColor {
  if (pct >= 95) {
    return $r('sys.color.ohos_id_color_alert');
  }
  if (pct >= 80) {
    return $r('sys.color.ohos_id_color_warning');
  }
  return $r('sys.color.font_secondary');
}

@Component
export struct ContextUsageRing {
  // 占比 0~100；≤0 = 窗口未知或无数据（仅底环仍可点——可点性在消费方的包裹键上，本件纯显示）
  @Prop pct: number = -1;
  // 环直径与描边（vp）：默认 = 输入条圆环键口径（20/3，见 ChatInputBar CTX 环注释演进）
  @Prop ringSize: number = 20;
  @Prop ringStroke: number = 3;

  // 色档三档单源 = 本件导出的 contextUsageToneColor（环与面板首卡线性进度条共用）
  private ringColor(): ResourceColor {
    return contextUsageToneColor(this.pct);
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
