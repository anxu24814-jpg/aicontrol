// MCP 服务器卡片菜单域（自 ProviderCardMenu 同域模式复制改写，机制/生命周期/材质单一故事同源）：
// 卡片右侧四点键（dot_grid_2x2）弹官方 openMenu 编程式菜单（ComponentContent 建/重建/dispose
// 成对 + 锚点 TargetInfo 定位 + 官方菜单材质 REGULAR 随沉浸光感总档）。
// 「编辑」「删除」已退役（决明拍板）：编辑 = 卡片本体点击直进编辑页，删除 = 行左滑确认链；
// 菜单只余「同步」（测连 + 工具刷新 + 缓存回写——原行内刷新键三合一动作）。
// 锚点 = 卡上四点键（id 前缀 + 服务器 id 挂在 McpPage 行卡按钮上；勿锚整卡——整卡锚点使菜单低于
// 按钮约 30vp 观感偏低）；targetSpace 5vp 比标题栏菜单略近（坑11 卡片菜单条目）。动作经回调注入
// ——归 McpPage。
import { ComponentContent, LengthMetrics, uiMaterial, SymbolGlyphModifier } from '@kit.ArkUI';
import { AppMenuHost } from '../../common/AppMenuHost';
import { resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { menuDividerColor } from '../../common/Theme';
import { McpServerRow } from '../../common/store/McpDb';

// 卡片锚点 id 前缀（openMenu TargetInfo 定位目标 = 卡片四点键）
export const MCP_CARD_MENU_ID_PREFIX: string = 'mcpCardMenu_';

// 菜单回调（openMenu 的 ComponentContent 参数载体：全局 @Builder 无组件实例，数据与
// 动作经参数注入）
export interface McpCardMenuCallbacks {
  item: McpServerRow;
  onSync: (item: McpServerRow) => void;
}

// 菜单内容（官方 Menu 组件）：同步 = arrow_clockwise（原行内刷新键同符号）；宽度官方内容自适应；
// 分割线 EMBEDDED_IN_MENU 深浅分治（AppStorage.get 直读——节点每次弹出前重建取当前深浅色）
@Builder
export function McpCardMenuBuilder(params: McpCardMenuCallbacks) {
  Menu() {
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_clockwise')), content: '同步' })
      .onClick(() => {
        params.onSync(params.item);
      })
  }
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 菜单节点宿主（AppMenuHost 薄壳——节点生命周期与弹出组装在基类，本壳只实现 buildNode 与
// 便捷 open：材质解析 + 逐卡锚点拼接 + targetSpace 5）
export class McpCardMenuHost extends AppMenuHost<McpCardMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: McpCardMenuCallbacks): ComponentContent<McpCardMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(McpCardMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出菜单（基类弹前重建——按当前深浅色/材质重新构建 UI 树）
  open(uiContext: UIContext, callbacks: McpCardMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, MCP_CARD_MENU_ID_PREFIX + callbacks.item.id,
      // 第三参 true = 交互形变 + 触点流光（官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true),
      { targetSpace: LengthMetrics.vp(5) });
  }
}
