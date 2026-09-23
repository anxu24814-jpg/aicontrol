// 提示词页菜单域（2026-08-30 新建，照 ProviderCardMenu/LogPageMoreMenu 同域模式——官方
// openMenu 编程式菜单：ComponentContent 建/重建/dispose 成对 + 锚点 TargetInfo 定位 +
// 官方菜单材质 REGULAR 基准随沉浸光感总档，宿主 = AppMenuHost 基类）：
// · ★ 2026-08-31 领导指令：标题栏「更多」弹窗菜单（新建/多选）拆为并列双键（高频）——
//   页级菜单域件随之退役（双键实现 = 库页标题栏工厂，照 ChatTitleMenu 同构；本文件
//   只剩行卡四点键）；
// · 行卡右侧四点键（dot_grid_2x2，ProviderCardItem 同款锚点姿势）→ RowMenu：编辑 / 删除
//  （锚点 = 四点键自身 .id(前缀 + 模板 id) + targetSpace 5vp——勿锚整卡，反馈轮 8 口径）。
// 触发方式均为显式键点击，无手势依赖（真机回流：bindMenu 长按菜单在转场后残留——
// 2026-08-30 领导截图实锤，弃用）。
import { ComponentContent, LengthMetrics, uiMaterial, SymbolGlyphModifier } from '@kit.ArkUI';
import { AppMenuHost } from '../../common/AppMenuHost';
import { resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { menuDividerColor } from '../../common/Theme';
import { PromptTemplateRow } from '../../common/store/PromptTemplateDb';

// 行卡四点键锚点 id 前缀（ProviderCardItem 同款：前缀 + 模板 id）
export const PROMPT_ROW_MENU_ID_PREFIX: string = 'promptRowMenu_';

// ── 行卡四点菜单：编辑 / 删除 ──
export interface PromptRowMenuCallbacks {
  item: PromptTemplateRow;
  onEdit: (item: PromptTemplateRow) => void;
  onDelete: (item: PromptTemplateRow) => void;
}

@Builder
export function PromptRowMenuBuilder(params: PromptRowMenuCallbacks) {
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

export class PromptRowMenuHost extends AppMenuHost<PromptRowMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: PromptRowMenuCallbacks): ComponentContent<PromptRowMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(PromptRowMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  open(uiContext: UIContext, callbacks: PromptRowMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, PROMPT_ROW_MENU_ID_PREFIX + callbacks.item.id,
      // ★ 第三参 true = 交互形变 + 触点流光（2026-09-18 菜单光感笔；官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true),
      { targetSpace: LengthMetrics.vp(5) });
  }
}
