// 文件工作区管理页标题栏「更多」菜单域（独立域件，与日志页/记忆库页/技能库页等先例同构：
// 菜单内容 builder（官方 Menu）+ AppMenuHost 节点宿主 + 隐形锚点；回退路径键数组已随 HDS
// 唯一路径化退役）。
// 项序（查看类不垫底、破坏性项聚垫底、清空工作区恒最垫底）：上传文件 / 多选 / 排序 /
// 数据总览 / 清理临时区 / 清空工作区。上传/清空/清理临时区均为换位不换链。
// ★ 2026-11-18 决明拍板「更多键改双键胶囊、新建文件夹键放进胶囊」：原菜单首项「新建文件夹」
//   自本菜单移出，改标题栏双热区胶囊 WorkspaceTitleBarKeys 左热区〔folder_badge_plus 新建文件夹〕，
//   右热区〔⋯更多〕弹本菜单；新建动作链 openCreateDirDialog 未动（换位不换链）。
// ★ 置灰语义（弹时快照，非响应式；决明拍板「在不生效的地方应置灰」）：上传 = 会话段
//   置灰；多选 = 会话段置灰，多选态下整菜单由页面 openMoreMenu 守卫让位不弹；排序 = 仅
//   文件夹段可用；数据总览 = 三段皆可用；清理临时区 = 临时段且临时区有组；清空 = 有件且无
//   删除/清空在途。.enabled 是 MenuItem 官方属性，置灰后点击由系统拦截（页面守卫兜底）。
// ★ 宽度：主菜单与排序子菜单同挂 MENU_UNIFIED_WIDTH 固定宽——只有固定值 width 触发官方
//   「子项取固定宽」规则，与子菜单同值同默认 padding 才两侧等宽；constraintSize / 百分比 /
//   padding 归零三形态已证无效勿回填；子项蒙层略短于一级项 = 官方内嵌固有面孔勿修。
// ★ 键形（2026-11-18 双键胶囊笔）：标题栏走官方自定义区覆盖层，键件 = WorkspaceTitleBarKeys
//  （消费 TitleBarKeys 共用件 TitleBarActionCapsule，双热区〔新建文件夹|更多〕）；官方菜单数组
//  传 null。「更多」恒最右 = 锚点几何前提。
// ★ 落点语义：菜单节点每次弹出前重建（rebuild = dispose + 按当前态重建），点击回调实时读页面
//   currentDir——上传/新建落点 = 弹出时刻的当前文件夹。
// 图标：新建 = folder_badge_plus；上传 = arrow_down_to_line；多选 = list_checkmark（TabMoreMenu
//   同款）；排序 = line_arrowtriangle_2_inward；数据总览 = list_bullet；清理/清空 = trash（全仓
//   删除键统一符号）。符号名以 SDK 符号表在册 + 构建绿为终证（坑72）。
// 几何：锚点走《Theme》按钮下沿公式（MORE_MENU_ANCHOR_RIGHT + topPad −
//   TITLE_BAR_MASK_EXTRA_HEIGHT − MORE_MENU_BUTTON_BOTTOM_INSET），与日志页/记忆库页/
//   服务商管理页同款（领导拍板：新页一律用本几何，勿另立一套）。
import { ComponentContent, SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { AppMenuHost } from '../../common/AppMenuHost';
import { resolvedUiMaterial } from '../../common/ImmersiveLevel';
import {
  MENU_UNIFIED_WIDTH, MORE_MENU_ANCHOR_RIGHT, MORE_MENU_BUTTON_BOTTOM_INSET,
  TITLE_BAR_MASK_EXTRA_HEIGHT, menuDividerColor, menuEndCheck
} from '../../common/Theme';
import { WS_SORT_CUSTOM, WS_SORT_NAME, WS_SORT_SIZE_ASC, WS_SORT_SIZE_DESC,
  WS_SORT_TIME_ASC, WS_SORT_TIME_DESC } from '../../common/WorkspaceUtil';
import { TITLE_BAR_EDGE_INSET, TitleBarActionCapsule } from '../TitleBarKeys';

// 标题栏覆盖层（官方自定义区）：双热区胶囊〔新建文件夹 | ⋯更多〕。组件内挂载是硬约束
//（坑30：全局 @Builder 被 titleBar napi 调用无视图上下文，启动即闪退）；根 Row 空白区命中透传
//（二级页覆盖层铺在返回键上方，默认命中档挡返回键——MemoryPage 自检轮实测，规范 §4）。
// 键序 = 视觉左→右、⋯ 恒最右（菜单锚点右缘几何前提）。
@Component
export struct WorkspaceTitleBarKeys {
  @Prop immersiveLevel: number = 0;
  onNewFolder: () => void = (): void => {
  };
  onMore: () => void = (): void => {
  };

  build() {
    Row() {
      TitleBarActionCapsule({
        leftIcon: $r('sys.symbol.folder_badge_plus'),
        leftLabel: '新建文件夹',
        rightIcon: $r('sys.symbol.dot_grid_2x2'),
        rightLabel: '更多',
        immersiveLevel: this.immersiveLevel,
        onLeftTap: (): void => {
          this.onNewFolder();
        },
        onRightTap: (): void => {
          this.onMore();
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding({ right: TITLE_BAR_EDGE_INSET })
    .justifyContent(FlexAlign.End)
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.Transparent)
  }
}

// 锚点 id（页面内唯一——与日志页/记忆库页/技能库页等锚点区分，防 openMenu 跨页同名误定位）
export const WORKSPACE_TITLE_MENU_ANCHOR_ID: string = 'workspaceTitleMenuAnchor';

// 菜单回调（openMenu 的 ComponentContent 参数载体：全局 @Builder 无组件实例，回调与置灰态
// 经参数传入——动作编排全在管理页侧方法；置灰态由页面在**弹出前**按实况组装快照）
export interface WorkspaceTitleMenuCallbacks {
  // 上传项可用态（弹时快照：文件夹段且无上传在途；会话段置灰）
  uploadEnabled: boolean;
  // 多选项可用态（弹时快照：文件夹段且列表就绪，或临时段；会话段置灰。多选态下整菜单由
  // 页面 openMoreMenu 守卫让位，本字段不承载该语义）
  multiselectEnabled: boolean;
  // 排序项可用态（弹时快照：仅文件夹段——会话/临时段置灰）
  sortEnabled: boolean;
  // 清空项可用态（弹时快照：有件且无删除/清空在途）
  clearEnabled: boolean;
  // 清理临时区项可用态（弹时快照：临时段且临时区有组；判据在页面侧现扫）
  clearTmpEnabled: boolean;
  onUpload: () => void;
  onMultiselect: () => void;
  // 数据总览项：查看类项，三段皆可用——内容随当前段（文件夹/会话段 = 工作区数据；临时段 =
  // 临时区数据），故不设置灰位
  onOverview: () => void;
  // 清理临时区项（编排上提父页——确认弹窗 + clearWorkspaceTmpAllOp + 重扫广播键都在页面侧）
  onClearTmp: () => void;
  onClear: () => void;
  // 排序子菜单 builder（坑51/62 形态照 TabMoreMenu 先例——CustomBuilder 位挂页面组件内 @Builder
  // 壳；六档选择回调由壳闭包直写偏好键，本接口不设 onPickSort）
  sortSubMenu: CustomBuilder;
}

// 排序二级菜单本体（组件内 @Prop 快照 + onPick 回调 + 右勾 symbolEndIcon 条件挂）。
// ★ 2026-11-15 勾色笔：六档右勾自内联 `new SymbolGlyphModifier(checkmark)` 收敛到
// common/Theme.menuEndCheck 单源——与思考/权限/联网等菜单同字形、同勾位、同色（选中态强调蓝
// selectedAccentBlue，顶部分段胶囊选中同色），改色只动 Theme 一处。
// 六档 = 自定义 / 按名称 / 最新在上 / 最早在上 / 最大在上 / 最小在上（档位语义见 WorkspaceUtil
// 「列表排序方式」段注释）。宽度同挂 MENU_UNIFIED_WIDTH（固定值定案修法，机制与禁令见文件头）
@Component
export struct WorkspaceSortMenu {
  // 弹出一刻的排序模式（宿主壳传入；六值域外脏值由 resolveWorkspaceSortMode 兜底）
  @Prop current: string;
  // 档位选择回调（宿主壳闭包直写偏好键）
  onPick: (mode: string) => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  build() {
    Menu() {
      MenuItem({
        content: '自定义',
        symbolEndIcon: menuEndCheck(this.current === WS_SORT_CUSTOM)
      })
        .onClick(() => {
          this.onPick(WS_SORT_CUSTOM);
        })
      MenuItem({
        content: '按名称',
        symbolEndIcon: menuEndCheck(this.current === WS_SORT_NAME)
      })
        .onClick(() => {
          this.onPick(WS_SORT_NAME);
        })
      MenuItem({
        content: '最新在上',
        symbolEndIcon: menuEndCheck(this.current === WS_SORT_TIME_DESC)
      })
        .onClick(() => {
          this.onPick(WS_SORT_TIME_DESC);
        })
      MenuItem({
        content: '最早在上',
        symbolEndIcon: menuEndCheck(this.current === WS_SORT_TIME_ASC)
      })
        .onClick(() => {
          this.onPick(WS_SORT_TIME_ASC);
        })
      MenuItem({
        content: '最大在上',
        symbolEndIcon: menuEndCheck(this.current === WS_SORT_SIZE_DESC)
      })
        .onClick(() => {
          this.onPick(WS_SORT_SIZE_DESC);
        })
      MenuItem({
        content: '最小在上',
        symbolEndIcon: menuEndCheck(this.current === WS_SORT_SIZE_ASC)
      })
        .onClick(() => {
          this.onPick(WS_SORT_SIZE_ASC);
        })
    }
    .width(MENU_UNIFIED_WIDTH)
    .menuItemDivider({
      color: menuDividerColor(this.appColorMode),
      mode: DividerMode.EMBEDDED_IN_MENU
    })
  }
}

// 菜单内容（官方 Menu 组件，openMenu 的 ComponentContent 载体）：六项见文件头项序；宽度挂
// MENU_UNIFIED_WIDTH，右缘对齐「更多」键由基类 show 的 placement BottomRight 保证
@Builder
export function WorkspaceTitleMenuBuilder(params: WorkspaceTitleMenuCallbacks) {
  Menu() {
    MenuItem({
      symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_down_to_line')),
      content: '上传文件'
    })
      .enabled(params.uploadEnabled)
      .onClick(() => {
        params.onUpload();
      })
    // 多选（图标 = TabMoreMenu「多选」项同款单源）：弹时快照置灰——判据在页面 menuCallbacks
    MenuItem({
      symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.list_checkmark')),
      content: '多选'
    })
      .enabled(params.multiselectEnabled)
      .onClick(() => {
        params.onMultiselect();
      })
    // 排序：点开内嵌展开二级六档切列表顺序，打勾快照经 sortSubMenu 壳闭包传入。尾部展开符号
    // 不手动配（endIcon / subMenuExpandSymbol 皆不配）——EMBEDDED 模式系统默认 chevron_down、
    // 展开时顺时针旋转 180°，手动再配会符号叠加。图标 = line_arrowtriangle_2_inward
    MenuItem({
      symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.line_arrowtriangle_2_inward')),
      content: '排序',
      builder: params.sortSubMenu
    })
      .enabled(params.sortEnabled)
    // 数据总览：三段皆可用不置灰（内容随段，半模态面板由页面 openDataOverview 现派生载荷后
    // 经 sheetKind='overview' 挂载）。图标 = list_bullet（明细清单语义）
    MenuItem({
      symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.list_bullet')),
      content: '数据总览'
    })
      .onClick(() => {
        params.onOverview();
      })
    // 清理临时区：置灰 = 非临时段或临时区无组（弹时快照，判据在页面 menuCallbacks）。符号 =
    // trash 与清空工作区同款（全仓删除键统一符号，两项文案已区分）
    MenuItem({
      symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')),
      content: '清理临时区'
    })
      .enabled(params.clearTmpEnabled)
      .onClick(() => {
        params.onClearTmp();
      })
    MenuItem({
      symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')),
      content: '清空工作区'
    })
      .enabled(params.clearEnabled)
      .onClick(() => {
        params.onClear();
      })
  }
  // ★ 固定宽度（只有固定值 width 触发官方「子项取固定宽」规则，与子菜单同值同默认 padding
  // ⇒ 两侧子项宽一致）：一级项与分割线随之铺满。★ 官方内嵌展开（决明拍板「内嵌展开非浮起」
  // ——d.ts 三值 SIDE/EMBEDDED/STACK，本菜单取 EMBEDDED）。subMenuExpandingMode 是 Menu 级
  // 属性，作用于本菜单所有带 builder 的项（本菜单仅「排序」项有子菜单）
  .width(MENU_UNIFIED_WIDTH)
  .subMenuExpandingMode(SubMenuExpandingMode.EMBEDDED_EXPAND)
  // 官方菜单项分割线（mode 必须 EMBEDDED_IN_MENU——FLOATING 悬浮层被菜单项盖住不可见；颜色
  // 走 menuDividerColor 深浅分治；全局 @Builder 无组件实例，直读 AppStorage——菜单节点每次
  // 弹出前重建，读取始终为当前深浅色）
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 菜单节点宿主（AppMenuHost 薄壳——节点生命周期与弹出组装在基类，本壳只实现 buildNode
// 与便捷 open）
export class WorkspaceTitleMenuHost extends AppMenuHost<WorkspaceTitleMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: WorkspaceTitleMenuCallbacks): ComponentContent<WorkspaceTitleMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(WorkspaceTitleMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出菜单（基类弹前重建——按当前深浅色/材质重新构建 UI 树；材质 REGULAR 基准随沉浸光感
  // 总档在此解析；第三参 true = 交互形变 + 触点流光，勿回改 false）
  open(uiContext: UIContext, callbacks: WorkspaceTitleMenuCallbacks,
    immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, WORKSPACE_TITLE_MENU_ANCHOR_ID,
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true));
  }
}

// 菜单隐形锚点（openMenu 的 TargetInfo 定位目标）：普通布局定位（Row 全宽 + Blank 撑开 +
// padding right）——锚点右缘 = 屏宽 − MORE_MENU_ANCHOR_RIGHT = 标题栏「更多」键右缘；锚点顶
// = 按钮下沿（topPad − 蒙层增量 − 按钮下沿内缩）。全高层 + HitTestMode.None 穿透触摸；禁
// position/calc 字符串定位（真机不生效，dshinhm 踩坑①；公式逐字同日志页/记忆库页/技能库页，
// 勿另立一套）。挂载 = 页面内容区 Stack 同层（HDS / 回退两路径均挂，回退 topPad=0 钳位 0）
@Component
export struct WorkspaceMoreMenuAnchor {
  // 页面顶部留白（vp，页面侧传入：HDS = 状态栏 + 标题栏 + 蒙层；回退 = 0）
  topPad: number = 0;

  build() {
    Row() {
      Blank()
      Column()
        .width(1)
        .height(1)
        .id(WORKSPACE_TITLE_MENU_ANCHOR_ID)
    }
    .width('100%')
    .padding({ right: MORE_MENU_ANCHOR_RIGHT })
    .margin({
      top: Math.max(this.topPad - TITLE_BAR_MASK_EXTRA_HEIGHT - MORE_MENU_BUTTON_BOTTOM_INSET, 0)
    })
    .hitTestBehavior(HitTestMode.None)
  }
}
