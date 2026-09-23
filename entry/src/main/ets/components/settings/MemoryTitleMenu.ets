// 记忆页标题栏键与「更多」菜单域（2026-09-13 决明「记忆页标题栏整理/优化/排序均收入更多
// 菜单，只保留更多与新建两个」——原 MemoryPage.ets 内联的标题栏覆盖层件退役，键集与菜单
// 自 MemoryPage 外迁本件 + 形态改版）。自 ProviderTitleMenu.ets 同域模式复制改写（机制/
// 生命周期/材质单一故事同源；独立成件的理由 = 记忆页已列软引导区，且标题栏菜单在工程内
// 一律独立域件——ProviderTitleMenu / LogPageMoreMenu / TabMoreMenu 三先例）：
// HDS 标题栏覆盖层 / 回退 Navigation.menus 双键数组 / openMenu 内容 builder / 隐形锚点
// / 节点宿主（init 建 / open 前重建 / dispose 成对释放）。
// ★ 形态（2026-09-15 改版，两次改版的来龙去脉见 MemoryPage.ets 头注释）：HDS 路径标题栏
//   恰两键且**合并为一枚双热区胶囊**〔＋新建 | ⋯更多〕——决明「记忆页右上角更多/加号合为
//   双键，同消息页」：官方菜单数组每项只渲染独立圆钮、画不出合并形态（本地 SDK d.ts 实查：
//   项 = HdsNavigationBadgeIconOptions{content.icon/action}，无自定义 builder 位），故改走
//   官方标题栏自定义区 stackBuilder 覆盖层（组件 = MemoryTitleBarKeys，键件与几何/双态走
//   共用件 components/TitleBarKeys.ets），官方菜单数组本页传 null。数组序（左→右）与胶囊
//   两热区序一致 = ＋ 在左、⋯ 恒最右——「⋯」是菜单锚点几何前提（锚点右缘 = 标题栏键右缘）。
//   「立即整理」「优化记忆」「记忆历史」「从其他平台导入」「排序」五键仍在「更多」菜单里
//   （项序 = 立即整理 / 优化记忆 / 记忆历史 / 从其他平台导入 / 排序垫底，先四件用模型的动作、
//   末位视图类项，ProviderPage「排序垫底」同序）。
// ★ 回退路径（设备无 HDS Core syscap）无 stackBuilder 机制，保持官方菜单数组两键（形态
//   与覆盖层不同 = 机制所限，键集/动作/顺序与覆盖层逐项对齐，仅多一份 value 文案）。
// ★ 覆盖层与 TitleBarKeys 的三次往来（消费方清单见该件头注释）：2026-09-11 本页覆盖层
//   〔加号圆键 + 整理|优化 胶囊〕= 共用件抽取的第三处来源 → 2026-09-13 覆盖层整块退役
//   （键入菜单后合并形态不再需要）→ 2026-09-15 以〔＋|⋯〕合并胶囊形态回归（本笔）。
// 几何：菜单锚点走《Theme》「按钮下沿」公式（MORE_MENU_ANCHOR_RIGHT +
//   topPad - TITLE_BAR_MASK_EXTRA_HEIGHT - MORE_MENU_BUTTON_BOTTOM_INSET）——与日志页/
//   服务商管理页完全同款（2026-08-30 领导拍板：新页一律用本几何，页签 DELTA=30 为主页面
//   存量勿扩散）；锚点右缘 = 标题栏「更多」键右缘（覆盖层时代 = 胶囊右缘 = 屏宽 −
//   TITLE_BAR_EDGE_INSET，与 MORE_MENU_ANCHOR_RIGHT 同值），故「更多」必须是末键/右热区
//   （键序也是几何前提）。
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

// ── HDS 路径：记忆页标题栏覆盖层（官方标题栏自定义区，2026-09-15 合并胶囊笔）──
// 键件与几何/光感双态全走共用件 components/TitleBarKeys.ets（双热区胶囊；本页是该件抽取
// 的第三处来源、退役后再回归——故事见该件头注释与下方「三次往来」）。
// ★ 必须是**组件**（不可做成全局 @Builder）——HDS 的 titleBar napi 直接调用 stackBuilder
//   时无视图上下文，全局 @Builder 编译产物 `(parent ? parent : this).observeComponentCreation2`
//   的 this 为 undefined → 运行期 TypeError 启动即闪退（2026-09-09 真机实锤，故障栈
//   hdsBaseComponent.js:111 → 全局 builder entry）；组件由 MemoryPage.TitleBarKeys
//   （组件内 @Builder）挂载，组件内 @Builder 编译为类方法、this 恒有绑定。
// 覆盖层根 Row 全宽全高 + 内容右对齐 + 空白区命中透传（Transparent）：官方主标题由
//   PageShell.keepStackTitle 保留（覆盖层只占标题栏右侧，左侧标题区与返回键区不占位）；
//   命中透传是二级页必需——覆盖层整栏铺在返回键上方，默认命中档会挡住返回键（2026-09-11
//   真机实锤「点返回键没反应」，规范《行内按钮与光感》§4 二级页同规③）
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
      // 合并胶囊（左加号右更多，各一热区；图标与无障碍文案 —— 自绘键无可见文字，
      // 读屏与自动化按 label 识别）
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

// 回退路径（设备无 HDS Core syscap）：Navigation.menus 数组构造——无 stackBuilder 机制、
// 拼不出合并形态，仍是官方两键数组，键集与动作顺序同上（API 10+ 文字不可见仅图标；value
// 仍写全称：兼作无障碍文案与自动化识别名）
export function memoryTitleMenuNav(onAdd: () => void, onMore: () => void): NavigationMenuItem[] {
  return [{
    value: '新建',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.plus')),
    action: onAdd
  } as NavigationMenuItem, {
    value: '更多',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.dot_grid_2x2')),
    action: onMore
  } as NavigationMenuItem];
}

// 菜单回调（openMenu 的 ComponentContent 参数载体：全局 @Builder 无组件实例，回调经参数
// 传入——立即整理 / 优化记忆 / 记忆历史 / 从其他平台导入 / 排序五键的动作编排全在库管理页侧
// 方法）
export interface MemoryTitleMenuCallbacks {
  onSort: () => void;
  onSink: () => void;
  onOptimize: () => void;
  onHistory: () => void;
  onImport: () => void;
}

// 菜单内容（官方 Menu 组件）：宽度不设——官方默认按内容自适应（右缘对齐「更多」键由
// placement 保证，不依赖宽度已知）；symbolStartIcon：整理 = arrow_down_to_line〔下沉沉淀
// 语义〕/ 优化 = wand_and_stars〔智能改写语义〕/ 排序 = sys.symbol.sort（★ 2026-09-22 八百
// 七十七节跟笔：原 arrow_up_and_down_square_portrait〔上下箭头夹方框〕退役，改与「服务商
// 管理页」「助手页签」两处「排序」项同符号——决明「记忆页改，以后用新的」。符号证据 =
// ProviderTitleMenu.ets 单源注释：SDK 符号表码位 0xF0AF9 + 128px 渲染核验 = 顶线最长 →
// 底线最短三横线）。/ 记忆历史 = sys.symbol.clock（本工程已在用：PreferencesPage /
// SkillIcons 两处）/ 从其他平台导入 = sys.symbol.square_and_arrow_down（导入语义，本机符号表
// 已验——ProviderTitleMenu「导入配置」等三处先例）。
// 分割线：Menu.menuItemDivider 默认不显示须显式设置，mode 必须 EMBEDDED_IN_MENU（FLOATING
// 悬浮层被菜单项盖住不可见），颜色走 menuDividerColor 深浅分治；全局 @Builder 无组件实例，
// AppStorage.get 直读——菜单节点每次弹出前重建，读取始终为当前深浅色（TabMoreMenu 同款）
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
    // 记忆历史（2026-09-22 记忆优化历史）：插在「优化记忆」之后、「排序」之前——项序规则 =
    // 视图类项（排序）恒垫底，动作类项在前。图标 sys.symbol.clock（本工程已在用：
    // PreferencesPage / SkillIcons 两处，零核实成本）
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.clock')), content: '记忆历史' })
      .onClick(() => {
        params.onHistory();
      })
    // 从其他平台导入（2026-09-22 记忆导入）：插在「记忆历史」之后、「排序」之前——项序规则
    // 同上（动作类项在前、视图类项垫底）。图标 sys.symbol.square_and_arrow_down = 导入语义，
    // 本机符号表已验（先例 ProviderTitleMenu「导入配置」/ SkillRowMenu 两处「导出」/
    // KnowledgeLibraryPage「导出」，均同符号）
    MenuItem({
      symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_arrow_down')),
      content: '从其他平台导入'
    })
      .onClick(() => {
        params.onImport();
      })
    MenuItem({
      symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.sort')),
      content: '排序'
    })
      .onClick(() => {
        params.onSort();
      })
  }
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 菜单节点宿主（AppMenuHost 薄壳——节点生命周期与弹出组装在基类，本壳只实现 buildNode
// 与便捷 open（材质解析 + 锚点 id），页面侧 init/open/dispose 调用零变化）
export class MemoryTitleMenuHost extends AppMenuHost<MemoryTitleMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: MemoryTitleMenuCallbacks): ComponentContent<MemoryTitleMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(MemoryTitleMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出菜单（基类弹前重建——按当前深浅色/材质重新构建 UI 树；材质 REGULAR 基准随
  // 沉浸光感总档在此解析）
  open(uiContext: UIContext, callbacks: MemoryTitleMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, MEMORY_TITLE_MENU_ANCHOR_ID,
      // ★ 第三参 true = 交互形变 + 触点流光（2026-09-18 菜单光感笔；官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true));
  }
}

// 菜单隐形锚点（openMenu 的 TargetInfo 定位目标组件）：**普通布局定位**（Row 全宽 +
// Blank 撑开 + padding right）——锚点右缘 = 屏宽 - MORE_MENU_ANCHOR_RIGHT = 「更多」键右缘
// （标题栏 end padding）；锚点顶 = 按钮下沿（topPad - 蒙层增量 - 按钮下沿内缩，否则菜单
// 整体偏低 8vp）。全高层 + HitTestMode.None 穿透触摸（禁 position/calc 字符串定位——真机
// 不生效，dshinhm 踩坑①；公式逐字同 LogPageContent / ProviderPage，勿另立一套）。
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
