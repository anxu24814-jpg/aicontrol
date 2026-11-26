// 服务商管理页标题栏键与「更多」菜单域。菜单项 = 分享配置 / 导入配置 / 价格模板（末位）——分享配置 =
// 打包全部已启用服务商（exportShareAll）、导入配置 = 批量导入（importShareConfig），两编排均在
// ProviderShareFlow.ets 模块级，本域只做回调透传；「刷新」项已撤（手动 reload 与进页/返回 onShown 重拉及
// 各写动作自刷重复）；「排序」项与 ProviderSortPage 已退役（排序回列表原位长按拖拽，坑10 已由 List 挂
// clip(false) 消解）。自 TabMoreMenu.ets 同域模式复制（机制/生命周期/材质同源）。
// 组成：HDS 标题栏自定义区 stackBuilder 覆盖层（组件 = ProviderTitleBarKeys）/ openMenu 内容 builder /
// 隐形锚点（组件内联在 ProviderPage.Content——几何 = LogPageContent 同款「按钮
// 下沿」公式；★ 2026-11-18 对齐笔后页签主页面同用本公式，全站一套锚点几何）/ 节点宿主
//（init 建 / open 前重建 / dispose 成对释放）。
// ★ 键形：HDS 路径右上角恰两键且**合并为一枚双热区胶囊**〔＋新建服务商 | ⋯更多〕（决明指令，功能不变），
//   键件与几何/双态走共用件 TitleBarKeys.ets；「新建服务商」移出菜单，＋ 键仍走 openDetail('')。合并形态
//   无官方实现——官方菜单数组每项只渲染独立圆钮（d.ts 实查无自定义 builder 位），故入覆盖层、官方菜单
//   数组传 null（providerMoreMenuHds 已整支退役）。数组序 = 胶囊两热区序 = ＋ 在左、⋯ 恒最右——「⋯」是
//   菜单锚点几何前提（锚点右缘 = 标题栏「更多」键右缘 = 屏宽 − TITLE_BAR_EDGE_INSET，与
//   Theme.MORE_MENU_ANCHOR_RIGHT 同值 16）。
// ★ 二级页覆盖层两条硬约束（真机/自检实锤，勿省）：①必须是**组件**、由**组件内 @Builder** 挂载——HDS 的
//   titleBar napi 直接调用 stackBuilder 时无视图上下文，全局 @Builder 的 this 为 undefined → 运行期
//   TypeError 启动即闪退（坑30）；②根 Row 须挂 hitTestBehavior(Transparent)——覆盖层整栏铺在返回键上方，
//   默认命中档会挡住返回键（HitTestMode.None 不可用，规范《行内按钮与光感》§4 二级页同规③）。
import { ComponentContent, SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { AppMenuHost } from '../../common/AppMenuHost';
import { resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { menuDividerColor } from '../../common/Theme';
import { TITLE_BAR_EDGE_INSET, TitleBarActionCapsule } from '../TitleBarKeys';

// 锚点 id（页面内唯一——与对话页签/记忆页锚点区分，防 openMenu 跨页同名误定位）
export const PROVIDER_TITLE_MENU_ANCHOR_ID: string = 'providerTitleMenuAnchor';

// HDS 路径：服务商管理页标题栏覆盖层（官方标题栏自定义区）。键件与几何/光感双态全走共用件 TitleBarKeys.ets
//（双热区胶囊，消费方清单与全仓使用点自动对账，见该件头注释）。
// 覆盖层根 Row 全宽全高 + 内容右对齐 + 空白区命中透传（Transparent）：官方主标题由 PageShell.keepStackTitle
// 保留（覆盖层只占标题栏右侧，左侧标题区与返回键区不占位）。
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

// 菜单回调（openMenu 的 ComponentContent 参数载体：全局 @Builder 无组件实例，数据与动作经参数注入；
// 「新建服务商」在覆盖层组件入参，不在菜单内；「排序」随排序页退役，「刷新」已撤——本接口余三项）
export interface ProviderTitleMenuCallbacks {
  onShareAll: () => void;
  onImportAll: () => void;
  onPriceTemplates: () => void;
}

// 菜单内容（官方 Menu 组件）：分享配置 = share（ProviderCardMenu 分享键同款已验）/ 导入配置 =
// square_and_arrow_down（符号表实锤）/ 价格模板 = yuansign_circle（与设置页「费用统计」行同款）；项序 =
// 分享配置 / 导入配置 / 价格模板（末位）。
// ★★ 全工程「排序」项符号单源 = sys.symbol.sort（顶线最长 → 底线最短三横线；决明定稿，SDK 符号表实锤，
//    坑72 口径）：消费点现有**只剩一处** = 记忆页「更多」菜单（MemoryTitleMenu）。**新增排序入口一律用
//    本符号**；断言 = assert-ui-shape 159 组「排序符号同源」钉（单边改即红）。
// 分割线 EMBEDDED_IN_MENU 深浅分治（TabMoreMenuBuilder 同款，AppStorage.get 直读——节点弹出前重建取深浅色）
@Builder
export function ProviderTitleMenuBuilder(params: ProviderTitleMenuCallbacks) {
  Menu() {
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.share')), content: '分享配置' })
      .onClick(() => {
        params.onShareAll();
      })
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_arrow_down')), content: '导入配置' })
      .onClick(() => {
        params.onImportAll();
      })
    // 价格模板（末位）：push 服务商选择页（非破坏性管理入口，无垫底语义）
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.yuansign_circle')), content: '价格模板' })
      .onClick(() => {
        params.onPriceTemplates();
      })
  }
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 菜单节点宿主（AppMenuHost 薄壳——节点生命周期与弹出组装在基类，本壳只实现 buildNode 与便捷 open，
// 页面侧 init/open/dispose 调用零变化）。
export class ProviderTitleMenuHost extends AppMenuHost<ProviderTitleMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: ProviderTitleMenuCallbacks): ComponentContent<ProviderTitleMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(ProviderTitleMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出菜单（基类弹前重建——按当前深浅色/材质重建 UI 树；材质 REGULAR 基准随沉浸光感总档在此解析）
  open(uiContext: UIContext, callbacks: ProviderTitleMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, PROVIDER_TITLE_MENU_ANCHOR_ID,
      // ★ 第三参 true = 交互形变 + 触点流光（菜单光感笔；官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true));
  }
}
