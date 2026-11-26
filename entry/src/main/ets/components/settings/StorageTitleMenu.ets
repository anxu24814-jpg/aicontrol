// 存储管理页标题栏「更多」菜单域：原右上角单键 = arrow_clockwise 直调刷新，现改〔⋯ 更多〕单键 + openMenu
// 菜单，「刷新」与「清理聊天附件」两项收入菜单，均**换位不换链**——刷新仍走页面 onRefresh 单一路径，清理项
// 开清理半模态。三件一体（标题栏菜单一律独立域件，第九例；回退路径键数组已随 HDS 唯一路径化退役）：
// 菜单内容 builder（官方 Menu）+ 节点宿主（AppMenuHost 薄壳）+ 隐形锚点。
// ★ 键形：HDS 标题栏走官方菜单数组单键（icon + action，LogPage 先例）。
// ★ 项序：刷新（非破坏）在前、清理聊天附件（破坏性）垫底——「破坏性项离拇指最远」（容器先于内容；
//   WorkspaceTitleMenu 同规）。清理项文案带宾语（同页卡 3 已有「清理」主键，同词两义易混）；符号 =
//   sys.symbol.trash（全仓删除键统一符号）。
// ★ 置灰语义（弹时快照，非响应式；ChatMoreMenu「刷新」项先例）：刷新项 = 清理中 / 统计中 / 附件清理在途皆置灰
//（onRefresh 守卫同源）；清理项 = 任一清理在途置灰。置灰后点击由系统拦截，页面侧守卫仍兜底。
// ★ 菜单宽度：**不设宽**（已裁定）= 官方内容自适应（规范-菜单与二级菜单 §3.1；两项短文案无需统一宽——
//   范本 WorkspaceTitleMenu 挂 MENU_UNIFIED_WIDTH 属 §3.2 内嵌子菜单折行的特定拍板例外，本案不挂）。
// ★ 图标：〔⋯ 更多〕= dot_grid_2x2（全仓单源）；刷新 = arrow_clockwise；清理 = trash（三符号均对本地 SDK 符号
//   两道门核实，坑72，构建绿为终证）。
// 几何：锚点走《Theme》「按钮下沿」公式（MORE_MENU_ANCHOR_RIGHT + topPad − TITLE_BAR_MASK_EXTRA_HEIGHT −
//   MORE_MENU_BUTTON_BOTTOM_INSET），新页一律用本几何（拍板）；锚点挂页面内容区 Stack 同层（HDS / 回退两
//   路径均挂，回退 topPad=0 钳位 0）。
import { ComponentContent, SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { AppMenuHost } from '../../common/AppMenuHost';
import { resolvedUiMaterial } from '../../common/ImmersiveLevel';
import {
  MORE_MENU_ANCHOR_RIGHT, MORE_MENU_BUTTON_BOTTOM_INSET, TITLE_BAR_MASK_EXTRA_HEIGHT,
  menuDividerColor
} from '../../common/Theme';

// 锚点 id（页面内唯一——与其余标题栏菜单锚点区分，防 openMenu 跨页同名误定位）
export const STORAGE_TITLE_MENU_ANCHOR_ID: string = 'storageTitleMenuAnchor';

// 菜单回调（openMenu 的 ComponentContent 参数载体：回调和置灰态经参数传入——动作编排全在页面侧方法；
// 置灰态由页面在**弹出前**按实况组装快照）
export interface StorageTitleMenuCallbacks {
  // 刷新项可用态（弹时快照 = !cleaning && !loading && !attachCleaning——清理中重扫会扫到半清理态、统计中
  // 守卫会再拦，提前置灰省一次调用）
  refreshEnabled: boolean;
  // 清理聊天附件项可用态（弹时快照 = !cleaning && !attachCleaning——任一清理在途不开第二动作）
  cleanEnabled: boolean;
  onRefresh: () => void;
  onClean: () => void;
}

// 菜单内容（官方 Menu 组件，openMenu 的 ComponentContent 载体）：两项 = 刷新 / 清理聊天附件（破坏性垫底）。
// 宽度不设（官方内容自适应；右缘对齐「更多」键由基类 show 的 placement BottomRight 保证）
@Builder
export function StorageTitleMenuBuilder(params: StorageTitleMenuCallbacks) {
  Menu() {
    MenuItem({
      symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_clockwise')),
      content: '刷新'
    })
      .enabled(params.refreshEnabled)
      .onClick(() => {
        params.onRefresh();
      })
    MenuItem({
      symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')),
      content: '清理聊天附件'
    })
      .enabled(params.cleanEnabled)
      .onClick(() => {
        params.onClean();
      })
  }
  // 官方菜单项分割线（mode 必须 EMBEDDED_IN_MENU——FLOATING 悬浮层被菜单项盖住不可见；颜色走
  // menuDividerColor 深浅分治，AppStorage.get 直读（弹出前重建，恒当前深浅色）。全仓标题栏菜单同款）
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 菜单节点宿主（AppMenuHost 薄壳——节点生命周期与弹出组装在基类，本壳只实现 buildNode 与便捷 open，
// 页面侧 init/open/dispose 调用零变化）
export class StorageTitleMenuHost extends AppMenuHost<StorageTitleMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: StorageTitleMenuCallbacks): ComponentContent<StorageTitleMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(StorageTitleMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出菜单（基类弹前重建——按当前深浅色/材质重建；材质 REGULAR 随沉浸光感总档解析；第三参 true =
  // 交互形变 + 触点流光，WorkspaceTitleMenu 同款）
  open(uiContext: UIContext, callbacks: StorageTitleMenuCallbacks,
    immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, STORAGE_TITLE_MENU_ANCHOR_ID,
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true));
  }
}

// 菜单隐形锚点（openMenu 的 TargetInfo 定位目标）：**普通布局定位**（Row 全宽 + Blank 撑开 + padding right）
// ——锚点右缘 = 屏宽 − MORE_MENU_ANCHOR_RIGHT = 标题栏「更多」键右缘；锚点顶 = 按钮下沿（topPad − 蒙层增量
// − 按钮下沿内缩）。全高层 + HitTestMode.None 穿透触摸（禁 position/calc 字符串定位——真机不生效，dshinhm
// 踩坑①；公式逐字同 WorkspaceMoreMenuAnchor）。挂载 = 页面内容区 Stack 同层（HDS / 回退两路径均挂，
// 回退 topPad=0 钳位 0）
@Component
export struct StorageMoreMenuAnchor {
  // 页面顶部留白（vp，页面侧传入：HDS = 状态栏 + 标题栏 + 蒙层；回退 = 0）
  topPad: number = 0;

  build() {
    Row() {
      Blank()
      Column()
        .width(1)
        .height(1)
        .id(STORAGE_TITLE_MENU_ANCHOR_ID)
    }
    .width('100%')
    .padding({ right: MORE_MENU_ANCHOR_RIGHT })
    .margin({
      top: Math.max(this.topPad - TITLE_BAR_MASK_EXTRA_HEIGHT - MORE_MENU_BUTTON_BOTTOM_INSET, 0)
    })
    .hitTestBehavior(HitTestMode.None)
  }
}
