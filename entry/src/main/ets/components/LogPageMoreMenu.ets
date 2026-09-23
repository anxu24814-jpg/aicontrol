// 「运行日志」页「更多」菜单层（2026-08-21 自 LogPage.ets 拆出，拆分规则见 LogPage.ets 头注释）：
// 官方全局菜单 openMenu 的内容构建与节点宿主（锚点与定位几何见 LogPageContent.ets 锚点
// 注释，选型与旋钮优先级见 AGENTS.md「菜单弹窗定位约定」节）。★ 2026-08-30 反馈轮 13：
// 节点生命周期与弹出组装迁 AppMenuHost 基类，本文件只留 builder/回调接口/锚点 id/宿主壳。
import { ComponentContent, SymbolGlyphModifier } from '@kit.ArkUI';
import { AppMenuHost } from '../common/AppMenuHost';
import { menuDividerColor } from '../common/Theme';

// 「更多」菜单回调（openMenu 的 ComponentContent 参数载体：@Builder 全局函数无法访问
// 组件实例，回调经参数传入——刷新 / 导出为文件 / 清空沙箱日志）
export interface MoreMenuCallbacks {
  onRefresh: () => void;
  onExport: () => void;
  onClear: () => void;
}

// 「更多」菜单锚点 id（openMenu 的 TargetInfo 定位目标组件，页面内唯一；锚点组件见
// LogPageContent.ets）
export const LOG_MORE_MENU_ANCHOR_ID: string = 'logMoreMenuAnchor';

// 「更多」菜单内容（官方 Menu 组件，openMenu 的 ComponentContent 载体）：
// 宽度不设——官方默认按内容自适应（菜单项文字只有几个字，固定宽度会留出大量空白；
// 右缘对齐「更多」按钮由基类 show 的 placement 保证，不依赖宽度已知）
@Builder
export function LogMoreMenuBuilder(params: MoreMenuCallbacks) {
  Menu() {
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_clockwise')), content: '刷新' })
      .onClick(() => {
        params.onRefresh();
      })
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.folder')), content: '分享/导出' })
      .onClick(() => {
        params.onExport();
      })
    // 清空沙箱日志（2026-09-04 新增）：官方 hilog.clean()（删除沙箱内全部 hilog 日志文件），
    // 实现见 LogPage.clearSandboxLogs；trash 图标 = 项目既有删除键先例
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')), content: '清空沙箱日志' })
      .onClick(() => {
        params.onClear();
      })
  }
  // 官方菜单项分割线（menuItemDivider @since 12，官方文档「菜单项间分割线」接口；不设
  // 该属性不显示分割线）：只覆盖 color 与 mode，其余走官方默认（1px、左右边距 16vp）。
  // ★ mode 必须 EMBEDDED_IN_MENU：2026-08-21 真机反馈上一版（默认 FLOATING_ABOVE_MENU）
  // 分割线完全不可见——该模式是「浮于菜单上方」的悬浮层，菜单项紧密排列 + THICK 材质下
  // 被盖住；官方示例（菜单组件文档「设置分割线样式」）特意用 EMBEDDED 内嵌绘制在菜单项
  // 内才可见。颜色走公共入口 menuDividerColor（深浅色分治，规范见 docs/菜单弹窗定位
  // 规范.md 五点五节）——全局 @Builder 无组件实例，深浅色直接读 AppStorage（EntryAbility
  // 写入；菜单节点每次弹出前重建，读取始终为当前深浅色）
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 菜单节点宿主（2026-08-30 反馈轮 13 起 AppMenuHost 薄壳——buildNode 直呼自家 @Builder
// 函数（编译器静态校验），生命周期/弹出在基类；LogPage 侧 init/rebuild/show/dispose）
export class LogMoreMenuHost extends AppMenuHost<MoreMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: MoreMenuCallbacks): ComponentContent<MoreMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(LogMoreMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }
}
