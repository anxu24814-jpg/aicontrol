// 编辑页解码中占位框（2026-08-22 提取：ImageEditPage/ImageAdjustPage 两页 else 分支
// 完全同款——深色圆角框 + 「图片加载中…」）：未就绪窗口预览框区域显示深色画布 #121212
// 而非透出页面浅色底（浅色模式 #F1F3F5 近白 → 闪白，坑40/43 配套；深色与最终深色图/下层
// 壁纸色调衔接）；几何 = 预览框（boxW/boxH 由调用页传入，两页共用同源尺寸），外层布局
// padding topPad + 居中与就绪视图对齐——就绪后无跳位。
// 2026-09-01 修复（真机反馈「预览框内容全黑 + 预览框错位」，转场动画期间可见、动画结束
// 解码完成即恢复）：
// ① 错位根因 = 外层 Column 未指定高度——PageShell 内容区 = Stack（alignContent 默认
//    Alignment.Center，SDK stack.d.ts 实锤），高度自适应（topPad+框高）的占位框被垂直居中，
//    与就绪后预览框（Scroll 撑满 + align(TopStart) 顶对齐，坑18 教训）位置不一致 → 解码
//    完成瞬间预览框从屏中央「跳」回顶部；解码 ~300ms 与转场动画重叠，动画期间正看到错位
//    （占位黑框实际显示在屏高约 1/3 处，与就绪位置差 100vp+）。修复 = 外层 Column 撑满
//    （height 100%；Column 默认 justifyContent Start = 顶对齐，与就绪视图同位置）。
// ② 全黑观感 = 黑框内仅暗色小字无加载信号 → 补官方 LoadingProgress 转圈指示（深色画布上
//    默认前景色可见），「加载中」可感知；底色 #121212 保持（防闪白定稿，勿改浅色）。
// 纯展示零逻辑，普通成员入参（创建时赋值）。
@Component
export struct EditPlaceholder {
  // 顶部留白（vp，同调用页 topPad——HDS 路径内容区延伸到标题栏背后）
  topPad: number = 0;
  boxW: number = 0; // 占位框宽（= 预览框宽）
  boxH: number = 0; // 占位框高（= 预览框高）

  build() {
    Column() {
      Column() {
        // 官方加载指示（LoadingProgress @since 8）：解码中窗口黑框内可见「在加载」而非
        // 纯黑——2026-09-01 真机反馈「预览框内容全黑」；深色画布上默认前景色对比足够，
        // 不自定颜色
        LoadingProgress()
          .width(32)
          .height(32)
        Text('图片加载中…')
          .fontSize(14)
          .fontColor($r('sys.color.font_tertiary'))
          .margin({ top: 8 })
      }
      .width(this.boxW)
      .height(this.boxH)
      .borderRadius($r('sys.float.ohos_id_corner_radius_default_xl'))
      .backgroundColor('#121212')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    // ★ 2026-09-01 错位修复：必须撑满（height 100%）——PageShell 内容区 = Stack
    // （alignContent 默认 Alignment.Center，d.ts 实锤），不撑满则高度自适应（topPad+框高）
    // 的占位框被垂直居中、与就绪后预览框（顶对齐）位置不一致 → 就绪瞬间跳位（见头注释）
    .height('100%')
    .padding({ top: this.topPad })
    .alignItems(HorizontalAlign.Center)
  }
}
