// 技能库行卡菜单域（照 PromptTemplateMenu 同域模式——官方 openMenu 编程式菜单：
// ComponentContent 建/重建/dispose 成对 + 锚点 TargetInfo 定位 + 官方菜单材质 REGULAR 随沉浸光感
// 总档，宿主 = AppMenuHost 基类）：
// · 行卡右侧四点键（dot_grid_2x2）→ RowMenu：导出 SKILL.md / 导出技能包；锚点 = 四点键自身
//   .id(前缀 + 技能 id) + targetSpace 5vp（勿锚整卡）；导出取得的是库里已保存行。
// · 「编辑」「删除」已退役（决明拍板）：编辑 = 行卡本体点击直进编辑页（内置行亦可进，编辑页
//   保存被预拦截 + DB throw 双道拦），删除 = 行左滑确认链（内置行 swipeEnabled false 不挂，
//   DB deleteSkill 首行守卫兜底）。
// · 触发方式为显式键点击，无手势依赖（bindMenu 长按菜单转场后残留——真机实锤，弃用）。
import { ComponentContent, LengthMetrics, uiMaterial, SymbolGlyphModifier } from '@kit.ArkUI';
import { AppMenuHost } from '../../common/AppMenuHost';
import { resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { menuDividerColor } from '../../common/Theme';
import { SkillFileRow, SkillRow } from '../../common/store/SkillDb';

// 行卡四点键锚点 id 前缀（前缀 + 技能 id）
export const SKILL_ROW_MENU_ID_PREFIX: string = 'skillRowMenu_';
// 编辑页附件文件行四点键锚点 id 前缀（前缀 + 文件 id）
export const SKILL_FILE_ROW_MENU_ID_PREFIX: string = 'skillFileRowMenu_';

// 行卡四点菜单：导出两项
export interface SkillRowMenuCallbacks {
  item: SkillRow;
  onExportMd: (item: SkillRow) => void;
  onExportPack: (item: SkillRow) => void;
}

@Builder
export function SkillRowMenuBuilder(params: SkillRowMenuCallbacks) {
  Menu() {
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_arrow_down')), content: '导出 SKILL.md' })
      .onClick(() => {
        params.onExportMd(params.item);
      })
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_arrow_down')), content: '导出技能包' })
      .onClick(() => {
        params.onExportPack(params.item);
      })
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
      // 第三参 true = 交互形变 + 触点流光（官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true),
      { targetSpace: LengthMetrics.vp(5) });
  }
}

// 编辑页附件文件行菜单：编辑 / 删除（行内两枚图标键收成更多）
export interface SkillFileRowMenuCallbacks {
  item: SkillFileRow;
  onEdit: (item: SkillFileRow) => void;
  onDelete: (item: SkillFileRow) => void;
}

@Builder
export function SkillFileRowMenuBuilder(params: SkillFileRowMenuCallbacks) {
  Menu() {
    MenuItem({
      symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')),
      content: '编辑'
    })
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

export class SkillFileRowMenuHost extends AppMenuHost<SkillFileRowMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: SkillFileRowMenuCallbacks): ComponentContent<SkillFileRowMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(SkillFileRowMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  open(uiContext: UIContext, callbacks: SkillFileRowMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, SKILL_FILE_ROW_MENU_ID_PREFIX + callbacks.item.id,
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true),
      { targetSpace: LengthMetrics.vp(5) });
  }
}
