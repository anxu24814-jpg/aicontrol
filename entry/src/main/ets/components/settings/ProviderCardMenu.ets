// 服务商卡片菜单域（2026-08-30 服务商管理域新建，自 SessionCardMenu.ets 同域模式复制
// 改写——机制/生命周期/材质与该件单一故事同源）：卡片右侧四点键（dot_grid_2x2）弹官方
// openMenu 编程式菜单（ComponentContent 建/重建/dispose 成对 + 锚点 TargetInfo 定位 +
// 官方菜单材质 REGULAR 基准随沉浸光感总档）。菜单项 = 编辑（进详情页）/ 分享（2026-09-03
// 新增：单家导出唯一编排 ProviderShareFlow.exportShareConfig——★ 2026-09-20 高级页同名
// 「导出配置」按钮随配置迁移卡退役，自此本键是该编排唯一入口，放编辑与删除之间，决明
// 指令）/ 删除（确认弹窗 + 事务级联）。锚点 = 卡上四点键（id 前缀 +
// 服务商 id 经 menuAnchorId 参数挂在 ProviderCardItem 按钮上）——★ 2026-08-30 反馈轮 8
// 领导拍板：勿锚整卡（按钮卡内垂直居中，整卡锚点使菜单低于按钮 ≈30vp 观感偏低），且
// targetSpace 5vp = 比标题栏菜单（官方默认 8vp）再近一点点（坑11 卡片菜单条目）。动作执行
// （跳转/分享/删除编排/列表刷新）经回调注入——归 ProviderPage。
// ★ 与长按菜单（SessionCardMenu = LongPressGesture 触发）的差异：本域触发方式 = 卡片
// 右侧显式菜单键点击（图片参考形态：卡片右缘四点键），无手势依赖。
import { ComponentContent, LengthMetrics, uiMaterial, SymbolGlyphModifier } from '@kit.ArkUI';
import { AppMenuHost } from '../../common/AppMenuHost';
import { resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { menuDividerColor } from '../../common/Theme';
import { ProviderRow } from '../../common/store/ProviderDb';

// 卡片锚点 id 前缀（openMenu TargetInfo 定位目标 = 卡片自身）
export const PROVIDER_CARD_MENU_ID_PREFIX: string = 'providerCardMenu_';

// 菜单回调（openMenu 的 ComponentContent 参数载体：全局 @Builder 无组件实例，数据与
// 动作经参数注入）
export interface ProviderCardMenuCallbacks {
  item: ProviderRow;
  onEdit: (item: ProviderRow) => void;
  onShare: (item: ProviderRow) => void;
  onDelete: (item: ProviderRow) => void;
}

// 菜单内容（官方 Menu 组件）：编辑 = square_and_pencil / 分享 = share（2026-09-03 新增，
// sys.symbol.share id_defined.json 实锤）/ 删除 = trash（三符号两项目内真机验证过，坑72
// 口径——share 同族符号表验证）；宽度官方内容自适应；分割线 EMBEDDED_IN_MENU 深浅分治
//（SessionCardMenu 同款，AppStorage.get 直读——节点每次弹出前重建取当前深浅色）
@Builder
export function ProviderCardMenuBuilder(params: ProviderCardMenuCallbacks) {
  Menu() {
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')), content: '编辑' })
      .onClick(() => {
        params.onEdit(params.item);
      })
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.share')), content: '分享' })
      .onClick(() => {
        params.onShare(params.item);
      })
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')), content: '删除' })
      .onClick(() => {
        params.onDelete(params.item);
      })
  }
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 菜单节点宿主（2026-08-30 反馈轮 13 起为 AppMenuHost 薄壳——节点生命周期与弹出组装
// 在基类，本壳只实现 buildNode 与便捷 open（材质解析/逐卡锚点拼接/targetSpace 5），
// 页面侧 init/open/dispose 调用零变化）。
export class ProviderCardMenuHost extends AppMenuHost<ProviderCardMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: ProviderCardMenuCallbacks): ComponentContent<ProviderCardMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(ProviderCardMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出菜单（基类弹前重建——按当前深浅色/材质重新构建 UI 树）：锚点 = 四点键（逐卡
  // 拼前缀）；targetSpace 5 = 比标题栏菜单略近（轮 8 领导拍板）
  open(uiContext: UIContext, callbacks: ProviderCardMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, PROVIDER_CARD_MENU_ID_PREFIX + callbacks.item.id,
      // ★ 第三参 true = 交互形变 + 触点流光（2026-09-18 菜单光感笔；官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true),
      { targetSpace: LengthMetrics.vp(5) });
  }
}
