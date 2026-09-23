// 模型卡片菜单域（2026-09-17 服务商模型卡菜单与删除笔，自 ProviderCardMenu.ets 同域模式
// 复制改写——机制/生命周期/材质与该件单一故事同源）：模型卡右侧四点键（dot_grid_2x2）弹
// 官方 openMenu 编程式菜单（ComponentContent 建/重建/dispose 成对 + 锚点 TargetInfo 定位 +
// 官方菜单材质 REGULAR 基准随沉浸光感总档）。菜单项 = 编辑（进编辑模型页）/ 删除（确认
// 弹窗 + 事务级联 + 删除前使用检测提示）——排法照全工程行卡菜单定稿「编辑在上、删除垫底」
//（2026-09-12 UI 同形异构归一笔 1：破坏性项离拇指最远）。锚点 = 卡上四点键（id 前缀 +
// 模型行 id 经 menuAnchorId 参数挂在 ModelCardItem 按钮上）；targetSpace 5vp = 卡片菜单
// 基准（比标题栏菜单略近，坑11 卡片菜单条目）。动作执行（push 编辑页 / 删除编排 / 清单
// 刷新）经回调注入——归 ProviderModelsPanel。★ 卡片点击进编辑已随本笔退役（决明指令：
// 编辑只能从菜单进），卡片本体不再挂 onClick。
import { ComponentContent, LengthMetrics, uiMaterial, SymbolGlyphModifier } from '@kit.ArkUI';
import { AppMenuHost } from '../../common/AppMenuHost';
import { resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { menuDividerColor } from '../../common/Theme';
import { ModelRow } from '../../common/store/ProviderDb';

// 卡片锚点 id 前缀（openMenu TargetInfo 定位目标 = 卡片四点键）
export const MODEL_CARD_MENU_ID_PREFIX: string = 'modelCardMenu_';

// 菜单回调（openMenu 的 ComponentContent 参数载体：全局 @Builder 无组件实例，数据与
// 动作经参数注入）
export interface ModelCardMenuCallbacks {
  item: ModelRow;
  onEdit: (item: ModelRow) => void;
  onDelete: (item: ModelRow) => void;
}

// 菜单内容（官方 Menu 组件）：编辑 = square_and_pencil / 删除 = trash（两符号均全工程
// 真机验证过，坑72 口径）；宽度官方内容自适应；分割线 EMBEDDED_IN_MENU 深浅分治
//（ProviderCardMenu 同款，AppStorage.get 直读——菜单节点每次弹出前重建，读取始终为当前
// 深浅色）
@Builder
export function ModelCardMenuBuilder(params: ModelCardMenuCallbacks) {
  Menu() {
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')), content: '编辑' })
      .onClick(() => {
        params.onEdit(params.item);
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

// 菜单节点宿主（AppMenuHost 薄壳——节点生命周期与弹出组装在基类，本壳只实现 buildNode
// 与便捷 open：材质解析 / 逐卡锚点拼接 / targetSpace 5）
export class ModelCardMenuHost extends AppMenuHost<ModelCardMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: ModelCardMenuCallbacks): ComponentContent<ModelCardMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(ModelCardMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出菜单（基类弹前重建——按当前深浅色/材质重新构建 UI 树）：锚点 = 四点键（逐卡拼前缀；
  // 空 id 行不弹——菜单只对已落库行有意义）
  open(uiContext: UIContext, callbacks: ModelCardMenuCallbacks, immersiveLevel: number): void {
    if (callbacks.item.id === '') {
      return;
    }
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, MODEL_CARD_MENU_ID_PREFIX + callbacks.item.id,
      // ★ 第三参 true = 交互形变 + 触点流光（2026-09-18 菜单光感笔；官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true),
      { targetSpace: LengthMetrics.vp(5) });
  }
}
