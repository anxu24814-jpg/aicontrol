// 服务商卡片菜单域（自 SessionCardMenu 同域模式复制改写，机制/生命周期/材质与该件同源）：
// 卡片右侧四点键（dot_grid_2x2）弹官方 openMenu 编程式菜单（ComponentContent 建/重建/dispose
// 成对 + 锚点 TargetInfo 定位 + 官方菜单材质 REGULAR 随沉浸光感总档）。
// 菜单项 = 编辑（进详情页）/ 分享（单家导出唯一编排 ProviderShareFlow.exportShareConfig）/
// 打开官网（末位，跳各家开放平台控制台，目标地址单源 ProviderCatalog.providerOfficialSite；
// siteUrl 空串整项不渲染）。
// 「删除」已退役（决明拍板）：删除统一走行左滑（RowSwipeDelete，内置行 swipeEnabled false 不挂），
// 确认弹窗仍归 ProviderPage.openDeleteConfirm 同链。
// 锚点 = 卡上四点键（id 前缀 + 服务商 id 经 menuAnchorId 参数挂在 ProviderCardItem 按钮上）——
// 勿锚整卡（按钮卡内垂直居中，整卡锚点使菜单低于按钮约 30vp 观感偏低），targetSpace 5vp
// 比标题栏菜单（官方默认 8vp）再近一点（坑11 卡片菜单条目）。动作执行经回调注入——归 ProviderPage。
// 与长按菜单（SessionCardMenu = LongPressGesture 触发）的差异：本域触发方式 = 卡片右侧显式
// 菜单键点击，无手势依赖。
import { ComponentContent, LengthMetrics, uiMaterial, SymbolGlyphModifier } from '@kit.ArkUI';
import { AppMenuHost } from '../../common/AppMenuHost';
import { resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { menuDividerColor } from '../../common/Theme';
import { ProviderRow } from '../../common/store/ProviderDb';

// 卡片四点键锚点 id 前缀（定位目标 = 四点键自身，id = 前缀 + 服务商 id）
export const PROVIDER_CARD_MENU_ID_PREFIX: string = 'providerCardMenu_';

// 菜单回调（openMenu 的 ComponentContent 参数载体：全局 @Builder 无组件实例，数据与
// 动作经参数注入）
export interface ProviderCardMenuCallbacks {
  item: ProviderRow;
  // 「打开官网」目标：'' = 不显示此项。准入在页面侧裁定（内置行 + 官网表域名命中），
  // 本件只按空串决定有无，不重复判家——两处各判一套必失步
  siteUrl: string;
  onEdit: (item: ProviderRow) => void;
  onShare: (item: ProviderRow) => void;
  onOpenSite: (item: ProviderRow) => void;
}

// 菜单内容（官方 Menu 组件）：编辑 = square_and_pencil / 分享 = share（坑72 口径，符号表验证）/
// 打开官网 = arrow_up_right（条件项）。宽度官方内容自适应；分割线 EMBEDDED_IN_MENU 深浅分治
//（AppStorage.get 直读——节点每次弹出前重建取当前深浅色）
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
    // 打开官网：只在内置家出现——siteUrl 空串即整项不渲染（自定义行、改过 Base URL 的内置行同规）。
    // 符号 arrow_up_right = 系统表在册的「外部打开」语义（id_defined.json 实锤；globe/earth/safari
    // 不在表内，勿凭直觉换）
    if (params.siteUrl !== '') {
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_up_right')),
        content: '打开官网'
      })
        .onClick(() => {
          params.onOpenSite(params.item);
        })
    }
  }
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 菜单节点宿主（AppMenuHost 薄壳——节点生命周期与弹出组装在基类，本壳只实现 buildNode 与
// 便捷 open：材质解析 + 逐卡锚点拼接 + targetSpace 5）
export class ProviderCardMenuHost extends AppMenuHost<ProviderCardMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: ProviderCardMenuCallbacks): ComponentContent<ProviderCardMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(ProviderCardMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出菜单（基类弹前重建——按当前深浅色/材质重新构建 UI 树）
  open(uiContext: UIContext, callbacks: ProviderCardMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, PROVIDER_CARD_MENU_ID_PREFIX + callbacks.item.id,
      // 第三参 true = 交互形变 + 触点流光（官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true),
      { targetSpace: LengthMetrics.vp(5) });
  }
}
