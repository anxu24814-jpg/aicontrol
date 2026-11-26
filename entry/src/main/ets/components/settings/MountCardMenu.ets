// 挂载卡「更多」菜单域（照 MountRowMenu 范式：官方 openMenu 编程式菜单——ComponentContent
// 建/重建/dispose 成对 + 锚点 TargetInfo 定位 + 官方菜单材质 REGULAR 随沉浸光感总档，宿主 =
// AppMenuHost 基类。触发 = 卡内下排「更多」键显式点击，无手势依赖；bindMenu 在转场后有残留
// 前科，本域同族不采用）。
// 菜单项（决明 2026-11-16 卡面改版拍板，项序 = 编辑在前、读写切换在后）：
// · 重命名 = 卡头铅笔键收编入菜单（square_and_pencil，原卡内行内图标键整键退役）；
// · 切换至读写 / 切换至只读 = 卡内「只读 / 读写」分段胶囊退役后唯一的模式切换入口，文案按
//   当前模式取「目标态」（mountOtherMode + mountModeLabel 单源，勿在菜单内另写一份档位名）。
// 失效态（needReauth = 系统持久授权已失效）：切换项 .enabled(false) 官方置灰 + labelInfo 短指引
// 「需重新授权」——与原「失效态不渲染胶囊」同语义（胶囊留着会暗示可切），长指引在帮助中心条目；
// 重命名改的是本地标签、与授权无关，失效态照常可用。
// 菜单宽度不设（普通菜单官方自适应——《规范-菜单与二级菜单》§3）。
import { ComponentContent, LengthMetrics, SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { AppMenuHost } from '../../common/AppMenuHost';
import { resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { menuDividerColor } from '../../common/Theme';
import { mountModeLabel, mountOtherMode } from '../../common/MountUtil';

// 卡内「更多」键锚点 id 前缀（挂键自身勿锚整卡——MountRowMenu / ProviderCardItem 同款姿势；
// id 后缀 = 挂载行 id，与渲染件挂键处逐字同式）
export const MOUNT_CARD_MENU_ID_PREFIX: string = 'mountCardMenu_';

// 卡菜单回调载体（mode / needReauth = 菜单内容与置灰判据按点击当刻卡数据生成，不吃首帧快照）
export interface MountCardMenuCallbacks {
  id: number;
  mode: number;
  needReauth: boolean;
  onRename: () => void;
  onSwitchMode: () => void;
}

@Builder
export function MountCardMenuBuilder(params: MountCardMenuCallbacks) {
  Menu() {
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')),
      content: '重命名' })
      .onClick(() => {
        params.onRename();
      })
    // 切换项：文案恒为「目标态」；失效态置灰 + 项内指引（平台不派发点击，故不挂动作）
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_left_arrow_right')),
      content: '切换至' + mountModeLabel(mountOtherMode(params.mode)),
      labelInfo: params.needReauth ? '需重新授权' : '' })
      .enabled(!params.needReauth)
      .onClick(() => {
        params.onSwitchMode();
      })
  }
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 菜单节点宿主（AppMenuHost 薄壳——节点生命周期与弹出组装在基类，本壳只实现 buildNode 与
// 便捷 open：材质解析 + 逐卡锚点拼接）
export class MountCardMenuHost extends AppMenuHost<MountCardMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: MountCardMenuCallbacks): ComponentContent<MountCardMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(MountCardMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出（基类弹前重建；placement 恒 BottomRight = 菜单右缘对锚点右缘、键下沿下方弹出；
  // targetSpace 5 = 与卡片菜单同距的按钮锚点间距）
  open(uiContext: UIContext, callbacks: MountCardMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, MOUNT_CARD_MENU_ID_PREFIX + callbacks.id,
      // 第三参 true = 交互形变 + 触点流光（官方最佳实践口径，勿回改 false）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true),
      { targetSpace: LengthMetrics.vp(5) });
  }
}
