// 挂载浏览页行菜单域（照 PromptTemplateMenu 范式：官方 openMenu 编程式菜单——ComponentContent
// 建/重建/dispose 成对 + 锚点 TargetInfo 定位 + 官方菜单材质 REGULAR 随沉浸光感总档，宿主 =
// AppMenuHost 基类。触发 = 行尾「更多」键显式点击，无手势依赖（真机教训：bindMenu/长按菜单
// 在转场后残留，弃用）。
// 菜单项：文件夹行 = 「在文件管理中打开」（跳转系统文件管理对应位置）+「删除」；文件行 =
// 「复制到工作区」+「删除」。破坏性项恒垫底（删除离拇指最远）。「复制到工作区」原为文件行行内
// 独立图标键，现收进本菜单；复制只收文件，只读挂载下照常可用（源只读、写沙箱、可逆）。
// 只读挂载的删除项 = 置灰与指引（决明拍板）：.enabled(false) 官方置灰态 + labelInfo 短指引
// 「需读写模式」——平台约束：置灰项不接收点击，故长指引在帮助中心条目。
// 菜单宽度不设（普通菜单官方自适应——《规范-菜单与二级菜单》§3；MENU_UNIFIED_WIDTH 仅三处
// 已定统一宽，本菜单不在其列）。
import { ComponentContent, LengthMetrics, SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { AppMenuHost } from '../../common/AppMenuHost';
import { resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { menuDividerColor } from '../../common/Theme';
import { MountBrowseRow, mountBrowseRowKey } from '../../common/MountUtil';

// 行尾「更多」键锚点 id 前缀（挂键自身勿锚整卡——ProviderCardItem/SessionCardItem 同款姿势；
// id 后缀 = 行键，与渲染件挂键处逐字同式）
export const MOUNT_ROW_MENU_ID_PREFIX: string = 'mountRowMenu_';

// 行菜单回调载体（row = 菜单内容与动作按点击当刻行数据生成；readWrite = 挂载读写态，控制删除项
// 可点性）
export interface MountRowMenuCallbacks {
  row: MountBrowseRow;
  readWrite: boolean;
  onCopyToWorkspace: (row: MountBrowseRow) => void;
  onOpenInFileManager: (row: MountBrowseRow) => void;
  onDelete: (row: MountBrowseRow) => void;
}

@Builder
export function MountRowMenuBuilder(params: MountRowMenuCallbacks) {
  Menu() {
    if (!params.row.isDir) {
      // 复制只收文件（文件夹不支持——与页面侧 onCopyToWorkspace 语义一致）
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.doc_filled_on_doc')),
        content: '复制到工作区' })
        .onClick(() => {
          params.onCopyToWorkspace(params.row);
        })
    }
    if (params.row.isDir) {
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_up_right')),
        content: '在文件管理中打开' })
        .onClick(() => {
          params.onOpenInFileManager(params.row);
        })
    }
    if (params.readWrite) {
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')), content: '删除' })
        .onClick(() => {
          params.onDelete(params.row);
        })
    } else {
      // 只读挂载：置灰不可点 + 项内指引小字（平台不派发点击，长指引见帮助中心条目）
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')), content: '删除',
        labelInfo: '需读写模式' })
        .enabled(false)
    }
  }
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 菜单节点宿主（AppMenuHost 薄壳——节点生命周期与弹出组装在基类，本壳只实现 buildNode 与
// 便捷 open：材质解析 + 逐行锚点拼接）
export class MountRowMenuHost extends AppMenuHost<MountRowMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: MountRowMenuCallbacks): ComponentContent<MountRowMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(MountRowMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出（基类弹前重建；placement 恒 BottomRight = 菜单右缘对锚点右缘、键下沿下方弹出；
  // targetSpace 5 = 与卡片菜单同距的按钮锚点间距）
  open(uiContext: UIContext, callbacks: MountRowMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, MOUNT_ROW_MENU_ID_PREFIX + mountBrowseRowKey(callbacks.row),
      // 第三参 true = 交互形变 + 触点流光（官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true),
      { targetSpace: LengthMetrics.vp(5) });
  }
}
