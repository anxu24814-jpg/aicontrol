// 服务商管理页标题栏键与「更多」菜单域（2026-08-30 反馈轮 6，领导方案——原「+」键改更多菜单，
// 菜单项 = 新建 / 排序 / ★刷新（2026-08-30 刷新链路收敛：列表/计数/余额徽章自动重拉
// 已删，手动刷新键即菜单项，点击回调 reload + toast）：排序 push 独立排序页，管理页自此
// 摘拖拽（坑10 浮起被列表内容区裁切转向））。2026-09-07 批量分享/导入两项加入：分享配置
// = 打包全部已启用服务商（exportShareAll，对话框三选同单服务商）、导入配置 = 批量导入
//（importShareConfig，预览分服务商）——两编排均在 ProviderShareFlow.ets 模块级，
// 本域只做回调透传。自 TabMoreMenu.ets 同域模式复制改写（机制/
// 生命周期/材质单一故事同源）：
// HDS 路径 = 官方标题栏自定义区 stackBuilder 覆盖层（组件 = ProviderTitleBarKeys）/ 回退
// Navigation.menus 数组 / openMenu 内容 builder / 隐形锚点（锚点组件内联在 ProviderPage.
// Content——几何 = 日志页 LogPageContent 同款「按钮下沿」公式；页签 DELTA=30 公式是主页面
// HdsNavigation 定稿值，二级页沿用菜单整体偏低 38vp = 轮 6「菜单离按钮太远」已修，两套
// 几何勿混用）/ 节点宿主（init 建 / open 前重建 / dispose 成对释放）。
// ★ 2026-09-22 决明「服务商管理页标题栏更多菜单，新建键移出与更多形成双键胶囊，参考消息页
//   实现，功能不变」——形态改版（第三次改版，前两次见上）：HDS 路径右上角恰两键且**合并为
//   一枚双热区胶囊**〔＋新建服务商 | ⋯更多〕，键件与几何/双态走共用件 components/
//   TitleBarKeys.ets（与消息页/记忆页同形）；「新建服务商」自此**移出「更多」菜单**（菜单
//   余四项 = 刷新 / 分享配置 / 导入配置 / 排序），动作与链路一字未动（＋ 键仍走
//   openDetail('') 新建态、菜单四项回调照旧）。合并形态无官方实现——官方菜单数组每项只渲染
//   独立圆钮（本地 SDK d.ts 实查：项 = HdsNavigationBadgeIconOptions{content.icon/action}，
//   无自定义 builder 位），故入覆盖层、官方菜单数组传 null（providerMoreMenuHds 整支退役，
//   死代码不留）。数组序（左→右）与胶囊两热区序一致 = ＋ 在左、⋯ 恒最右——「⋯」是菜单锚点
//   几何前提（锚点右缘 = 标题栏「更多」键右缘 = 屏宽 − TITLE_BAR_EDGE_INSET，与
//   Theme.MORE_MENU_ANCHOR_RIGHT 同值 16）。
// ★ 二级页覆盖层两条硬约束（两处均有真机/自检实锤，勿省）：
//   ①必须是**组件**，由**组件内 @Builder** 挂载——HDS 的 titleBar napi 直接调用 stackBuilder
//     时无视图上下文，全局 @Builder 编译产物 `(parent ? parent : this).observeComponentCreation2`
//     的 this 为 undefined → 运行期 TypeError 启动即闪退（坑30，2026-09-09 真机实锤）；
//   ②根 Row 须挂 `hitTestBehavior(HitTestMode.Transparent)`——覆盖层整栏铺在返回键上方，
//     默认命中档会挡住返回键（真机表现「点返回键没反应」，2026-09-11 自检 P1-1 实锤；
//     HitTestMode.None 不可用，规范《行内按钮与光感》§4 二级页同规③）。
// 回退路径（设备无 HDS Core syscap）无 stackBuilder 机制，保持官方菜单数组两键（形态与覆盖层
//   不同 = 机制所限，键集/动作/顺序与覆盖层逐项对齐，仅多一份 value 文案）。
import { ComponentContent, SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { AppMenuHost } from '../../common/AppMenuHost';
import { resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { menuDividerColor } from '../../common/Theme';
import { TITLE_BAR_EDGE_INSET, TitleBarActionCapsule } from '../TitleBarKeys';

// 锚点 id（页面内唯一——与对话页签/记忆页锚点区分，防 openMenu 跨页同名误定位）
export const PROVIDER_TITLE_MENU_ANCHOR_ID: string = 'providerTitleMenuAnchor';

// ── HDS 路径：服务商管理页标题栏覆盖层（官方标题栏自定义区，2026-09-22 合并胶囊笔）──
// 键件与几何/光感双态全走共用件 components/TitleBarKeys.ets（双热区胶囊，本页为第七处消费方——
// 消费方清单与全仓使用点自动对账，见该件头注释）。
// 覆盖层根 Row 全宽全高 + 内容右对齐 + 空白区命中透传（Transparent）：官方主标题由
// PageShell.keepStackTitle 保留（覆盖层只占标题栏右侧，左侧标题区与返回键区不占位）。
@Component
export struct ProviderTitleBarKeys {
  // 光感档位（生效档位由共用件内 resolveEffectiveLevel 解析——本组件不自持 keyLevel）
  @Prop immersiveLevel: number = 0;
  onAdd: () => void = (): void => {
  };
  onMore: () => void = (): void => {
  };

  build() {
    Row() {
      // 合并胶囊（左加号右更多，各一热区；图标与无障碍文案——自绘键无可见文字，
      // 读屏与自动化按 label 识别；★ 键序是几何前提：「⋯」恒最右 = 锚点右缘与键右缘齐）
      TitleBarActionCapsule({
        leftIcon: $r('sys.symbol.plus'),
        leftLabel: '新建服务商',
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
    .hitTestBehavior(HitTestMode.Transparent)
  }
}

// 回退路径（设备无 HDS Core syscap）：Navigation.menus 数组构造——无 stackBuilder 机制、
// 拼不出合并形态，仍是官方两键数组，键集与动作顺序同上（API 10+ 文字不可见仅图标；value
// 仍写全称：兼作无障碍文案与自动化识别名）。★ 序 = ＋ 在前、⋯ 末键（锚点右缘几何前提——
// ⋯ 是末键时其右缘才落在标题栏 end padding 16 上）
export function providerMoreMenuNav(onAdd: () => void, onMore: () => void): NavigationMenuItem[] {
  return [{
    value: '新建服务商',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.plus')),
    action: onAdd
  } as NavigationMenuItem, {
    value: '更多',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.dot_grid_2x2')),
    action: onMore
  } as NavigationMenuItem];
}

// 菜单回调（openMenu 的 ComponentContent 参数载体：全局 @Builder 无组件实例，数据与
// 动作经参数注入；★ 2026-09-22 起「新建服务商」不在菜单内——＋ 键动作经覆盖层组件入参，
// 本接口只余菜单四项）
export interface ProviderTitleMenuCallbacks {
  onRefresh: () => void;
  onShareAll: () => void;
  onImportAll: () => void;
  onSort: () => void;
}

// 菜单内容（官方 Menu 组件）：刷新 = arrow_clockwise / 分享配置 = share（ProviderCardMenu
// 分享键同款已验）/ 导入配置 = square_and_arrow_down（2026-09-07 符号表实锤）/ 排序 =
// sys.symbol.sort（★ 2026-09-22 决明「排序图标…换成由上到下从长到短三线，官方有吗」——
// 原 arrow_down_and_line_horizontal_and_arrow_up（上下箭头夹一横线）退役；新符号字形 =
// 顶线最长 → 底线最短三横线，SDK 符号表实锤：previewer resources.txt 码位 0xF0AF9 +
// 128px 渲染核验，坑72 口径）。
// ★★ 全工程「排序」项符号单源 = 本符号（sys.symbol.sort）：现消费三处——本页 / 助手页签
//    「更多」菜单（TabMoreMenu）/ 记忆页「更多」菜单（MemoryTitleMenu，2026-09-22 八百七十七
//    节跟笔，原 arrow_up_and_down_square_portrait 退役）。**新增排序入口一律用本符号**
//    （决明 2026-09-22「记忆页改，以后用新的」）；改符号只改本注释与三处消费点，
//    断言 = assert-ui-shape 159 组「排序符号三处同源」钉（单边改回旧符号即红）。
// 分割线 EMBEDDED_IN_MENU 深浅分治（TabMoreMenuBuilder 同款，AppStorage.get 直读——节点
// 每次弹出前重建取当前深浅色）
@Builder
export function ProviderTitleMenuBuilder(params: ProviderTitleMenuCallbacks) {
  Menu() {
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_clockwise')), content: '刷新' })
      .onClick(() => {
        params.onRefresh();
      })
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.share')), content: '分享配置' })
      .onClick(() => {
        params.onShareAll();
      })
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_arrow_down')), content: '导入配置' })
      .onClick(() => {
        params.onImportAll();
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

// 菜单节点宿主（2026-08-30 反馈轮 13 起为 AppMenuHost 薄壳——节点生命周期与弹出组装
// 在基类，本壳只实现 buildNode 与便捷 open（材质解析 + 锚点 id），页面侧 init/open/
// dispose 调用零变化）。
export class ProviderTitleMenuHost extends AppMenuHost<ProviderTitleMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: ProviderTitleMenuCallbacks): ComponentContent<ProviderTitleMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(ProviderTitleMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出菜单（基类弹前重建——按当前深浅色/材质重新构建 UI 树；材质 REGULAR 基准随
  // 沉浸光感总档在此解析）
  open(uiContext: UIContext, callbacks: ProviderTitleMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, PROVIDER_TITLE_MENU_ANCHOR_ID,
      // ★ 第三参 true = 交互形变 + 触点流光（2026-09-18 菜单光感笔；官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true));
  }
}
