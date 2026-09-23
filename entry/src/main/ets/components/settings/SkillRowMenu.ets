// 技能库行卡菜单域（2026-09-13 技能层笔 1 新建，照 PromptTemplateMenu 同域模式——官方
// openMenu 编程式菜单：ComponentContent 建/重建/dispose 成对 + 锚点 TargetInfo 定位 +
// 官方菜单材质 REGULAR 基准随沉浸光感总档，宿主 = AppMenuHost 基类）：
// · 行卡右侧四点键（dot_grid_2x2，ProviderCardItem/PromptLibraryPage 同款锚点姿势）→
//   RowMenu：编辑 / 导出 SKILL.md / 导出技能包 / 删除（锚点 = 四点键自身 .id(前缀 + 技能 id)
//   + targetSpace 5vp——勿锚整卡，反馈轮 8 口径）。★ 两导出 2026-09-13 自技能编辑页操作卡
//   移入（入口调整笔：底层导出链未动，只换入口；危险项恒排末位，导出取得的是库里已保存行）。
// · ★ 2026-09-13 会话中创建技能笔：内置行（source='builtin'）隐藏「删除」项——DB 侧
//   deleteSkill 首行守卫兜底，菜单先不露不可用入口；「编辑」保留（编辑页可看正文与预览，
//   保存被预拦截 + DB throw 双道拦）；「导出」两项保留（无破坏性，随备份语义）。
// · 触发方式为显式键点击，无手势依赖（bindMenu 长按菜单在转场后残留——2026-08-30 真机
//   截图实锤，弃用）。
import { ComponentContent, LengthMetrics, uiMaterial, SymbolGlyphModifier } from '@kit.ArkUI';
import { AppMenuHost } from '../../common/AppMenuHost';
import { resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { menuDividerColor } from '../../common/Theme';
import { SkillRow } from '../../common/store/SkillDb';

// 行卡四点键锚点 id 前缀（前缀 + 技能 id）
export const SKILL_ROW_MENU_ID_PREFIX: string = 'skillRowMenu_';

// ── 行卡四点菜单：编辑 / 导出 SKILL.md / 导出技能包 / 删除 ──
export interface SkillRowMenuCallbacks {
  item: SkillRow;
  onEdit: (item: SkillRow) => void;
  onExportMd: (item: SkillRow) => void;
  onExportPack: (item: SkillRow) => void;
  onDelete: (item: SkillRow) => void;
}

@Builder
export function SkillRowMenuBuilder(params: SkillRowMenuCallbacks) {
  Menu() {
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')), content: '编辑' })
      .onClick(() => {
        params.onEdit(params.item);
      })
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_arrow_down')), content: '导出 SKILL.md' })
      .onClick(() => {
        params.onExportMd(params.item);
      })
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_arrow_down')), content: '导出技能包' })
      .onClick(() => {
        params.onExportPack(params.item);
      })
    // 内置行不出「删除」（源文件头注释——DB deleteSkill 首行守卫兜底）
    if (params.item.source !== 'builtin') {
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')), content: '删除' })
        .onClick(() => {
          params.onDelete(params.item);
        })
    }
  }
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

export class SkillRowMenuHost extends AppMenuHost<SkillRowMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: SkillRowMenuCallbacks): ComponentContent<SkillRowMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(SkillRowMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  open(uiContext: UIContext, callbacks: SkillRowMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, SKILL_ROW_MENU_ID_PREFIX + callbacks.item.id,
      // ★ 第三参 true = 交互形变 + 触点流光（2026-09-18 菜单光感笔；官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true),
      { targetSpace: LengthMetrics.vp(5) });
  }
}
