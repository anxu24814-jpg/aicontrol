// 记忆页标题栏键与「更多」菜单域（决明「记忆页标题栏整理/优化/排序均收入更多菜单，只保留更多与新建两个」；
// 自 ProviderTitleMenu 同域模式复制改写，独立成件先例 = ProviderTitleMenu / LogPageMoreMenu / TabMoreMenu）：
// HDS 标题栏覆盖层 / openMenu 内容 builder / 隐形锚点 / 节点宿主（回退 Navigation.menus 双键数组
// 已随 2026-10-31 HDS 兜底撤除整笔退役）。
// ★ 形态：HDS 路径标题栏恰两键且合并为一枚双热区胶囊〔＋新建 | ⋯更多〕（决明「同消息页」）——官方菜单数组
//   每项只渲染独立圆钮、画不出合并形态（d.ts 实查：HdsNavigationBadgeIconOptions 无自定义 builder 位），故走
//   官方标题栏自定义区 stackBuilder 覆盖层（组件 = MemoryTitleBarKeys，键件与几何/双态走共用件
//   TitleBarKeys.ets），官方菜单数组本页传 null。胶囊两热区序 = ＋ 在左、⋯ 恒最右——「⋯」是菜单锚点几何
//   前提（锚点右缘 = 标题栏键右缘）。五键在「更多」菜单：四项库级动作 + 多选模式入口垫底（决明拍板「末位」；
//  「排序」项已退役）。
// 几何：菜单锚点走《Theme》按钮下沿公式（MORE_MENU_ANCHOR_RIGHT + topPad - TITLE_BAR_MASK_EXTRA_HEIGHT -
//   MORE_MENU_BUTTON_BOTTOM_INSET）——与日志页/服务商管理页同款，新页一律用本几何；「更多」必须末键/右热区。
import { ComponentContent, SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { AppMenuHost } from '../../common/AppMenuHost';
import { resolvedUiMaterial } from '../../common/ImmersiveLevel';
import {
  MORE_MENU_ANCHOR_RIGHT, MORE_MENU_BUTTON_BOTTOM_INSET, TITLE_BAR_MASK_EXTRA_HEIGHT,
  menuDividerColor
} from '../../common/Theme';
import { TITLE_BAR_EDGE_INSET, TitleBarActionCapsule } from '../TitleBarKeys';

// 锚点 id（页面内唯一——与对话页签/服务商管理页锚点区分，防 openMenu 跨页同名误定位）
export const MEMORY_TITLE_MENU_ANCHOR_ID: string = 'memoryTitleMenuAnchor';

// HDS 路径：记忆页标题栏覆盖层（官方标题栏自定义区）。键件与几何/光感双态全走共用件 TitleBarKeys.ets。
// ★ 必须是**组件**（不可做成全局 @Builder）——HDS 的 titleBar napi 直接调用 stackBuilder 时无视图上下文，
//   全局 @Builder 编译产物的 this 为 undefined → 运行期 TypeError 启动即闪退（真机实锤）；组件内 @Builder
//   编译为类方法、this 恒有绑定。
// 覆盖层根 Row 全宽全高 + 内容右对齐 + 空白区命中透传（Transparent）：官方主标题由 PageShell.keepStackTitle
// 保留；命中透传是二级页必需——覆盖层整栏铺在返回键上方，默认命中档会挡住返回键（真机实锤，规范《行内
// 按钮与光感》§4 二级页同规③）
@Component
export struct MemoryTitleBarKeys {
  // 光感档位（生效档位由共用件内 resolveEffectiveLevel 解析——本组件不自持 keyLevel）
  @Prop immersiveLevel: number = 0;
  onAdd: () => void = (): void => {
  };
  onMore: () => void = (): void => {
  };

  build() {
    Row() {
      // 合并胶囊（左加号右更多，各一热区——自绘键无可见文字，label 供读屏与自动化识别）
      TitleBarActionCapsule({
        leftIcon: $r('sys.symbol.plus'),
        leftLabel: '新建',
        rightIcon: $r('sys.symbol.dot_grid_2x2'),
        rightLabel: '更多',
        immersiveLevel: this.immersiveLevel,
        onLeftTap: (): void => {
          this.onAdd();
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

// 菜单回调（openMenu 的 ComponentContent 参数载体：全局 @Builder 无组件实例，回调经参数传入——五项动作
// 编排全在库管理页侧方法）。「排序」项已退役（改列表原位长拖拽），本接口随之少一字段
export interface MemoryTitleMenuCallbacks {
  onSink: () => void;
  onOptimize: () => void;
  onHistory: () => void;
  onImport: () => void;
  // 多选：进入批量删除模式（形态照会话列表/提示词库页，批量条/删除编排在库管理页侧）
  onMultiselect: () => void;
}

// 菜单内容（官方 Menu 组件）：宽度不设——官方默认按内容自适应（右缘对齐「更多」键由 placement 保证）；
// 图标：整理 = arrow_down_to_line（下沉沉淀）/ 优化 = wand_and_stars（智能改写）/ 记忆历史 = clock /
// 导入 = square_and_arrow_down（导入语义，本机符号表已验）。分割线：Menu.menuItemDivider 默认不显示须显式
// 设置，mode 必须 EMBEDDED_IN_MENU（FLOATING 悬浮层被菜单项盖住不可见），颜色走 menuDividerColor 深浅分治；
// 全局 @Builder 无组件实例，AppStorage.get 直读——菜单节点每次弹出前重建，读取始终为当前深浅色
@Builder
export function MemoryTitleMenuBuilder(params: MemoryTitleMenuCallbacks) {
  Menu() {
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_down_to_line')), content: '立即整理' })
      .onClick(() => {
        params.onSink();
      })
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.wand_and_stars')), content: '优化记忆' })
      .onClick(() => {
        params.onOptimize();
      })
    // 记忆历史（图标 sys.symbol.clock，本工程已在用）
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.clock')), content: '记忆历史' })
      .onClick(() => {
        params.onHistory();
      })
    MenuItem({
      symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_arrow_down')),
      content: '从其他平台导入'
    })
      .onClick(() => {
        params.onImport();
      })
    // 多选：末位（决明拍板「多选垫底」——模式类入口排在库级动作项之后）。图标 = sys.symbol.list_checkmark
    //（列表勾选语义，与对话页签「更多」菜单「多选」项同符号——勿用 dot_grid_2x2，那是「更多」键语义）
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.list_checkmark')),
      content: '多选' })
      .onClick(() => {
        params.onMultiselect();
      })
  }
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 菜单节点宿主（AppMenuHost 薄壳——节点生命周期与弹出组装在基类，本壳只实现 buildNode 与便捷 open
//（材质解析 + 锚点 id），页面侧 init/open/dispose 调用零变化）
export class MemoryTitleMenuHost extends AppMenuHost<MemoryTitleMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: MemoryTitleMenuCallbacks): ComponentContent<MemoryTitleMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(MemoryTitleMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出菜单（基类弹前重建——按当前深浅色/材质重新构建 UI 树；材质 REGULAR 基准随沉浸光感总档在此解析）
  open(uiContext: UIContext, callbacks: MemoryTitleMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, MEMORY_TITLE_MENU_ANCHOR_ID,
      // 第三参 true = 交互形变 + 触点流光（官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true));
  }
}

// 菜单隐形锚点（openMenu 的 TargetInfo 定位目标组件）：普通布局定位（Row 全宽 + Blank 撑开 + padding
// right）——锚点右缘 = 屏宽 - MORE_MENU_ANCHOR_RIGHT = 「更多」键右缘；锚点顶 = 按钮下沿（topPad - 蒙层
// 增量 - 按钮下沿内缩，否则菜单整体偏低 8vp）。全高层 + HitTestMode.None 穿透触摸（禁 position/calc 字符串
// 定位——真机不生效；公式逐字同 LogPageContent / ProviderPage，勿另立一套）。
@Component
export struct MemoryMoreMenuAnchor {
  // 页面顶部留白（vp，HomeNavigation PageMap 传入：HDS = 状态栏 + 标题栏 + 蒙层；回退 = 0）
  topPad: number = 0;

  build() {
    Row() {
      Blank()
      Column()
        .width(1)
        .height(1)
        .id(MEMORY_TITLE_MENU_ANCHOR_ID)
    }
    .width('100%')
    .padding({ right: MORE_MENU_ANCHOR_RIGHT })
    .margin({
      top: Math.max(this.topPad - TITLE_BAR_MASK_EXTRA_HEIGHT - MORE_MENU_BUTTON_BOTTOM_INSET, 0)
    })
    .hitTestBehavior(HitTestMode.None)
  }
}
