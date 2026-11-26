// 知识库库页标题栏「更多」菜单域（独立域件，与记忆库页 / 技能库页 / 服务商管理页 /
// 文件工作区 / 提示词库页等先例同构：菜单内容 builder〔官方 Menu〕+ AppMenuHost 节点宿主 +
// 隐形锚点）。★ 标题栏为〔＋新建知识库 | ⋯更多〕双热区胶囊（键件内联在 KnowledgeLibraryPage.
// TitleBarContent）——新建走胶囊左热区（onNewBook 落库链未动），本菜单只承载右热区弹出的
// 单项「导入知识库」（importBook 五闸链未动）。沿革 = 2026-11-18 曾把双键胶囊改单圆「更多」键、
// 两动作同收本菜单；同日再拍板恢复双键胶囊，新建回左热区、菜单余导入一项。
// 几何：隐形锚点走《Theme》「按钮下沿」公式（MORE_MENU_ANCHOR_RIGHT + topPad −
// TITLE_BAR_MASK_EXTRA_HEIGHT − MORE_MENU_BUTTON_BOTTOM_INSET），与其余页签 / 库页同款，勿另立一套；
// 锚点右缘 = 屏宽 − 16 = 标题栏「⋯更多」键右缘（胶囊右热区最右，几何前提不变）。
// 光感：菜单节点每次弹出前重建（按当前深浅色 / 材质重建 UI 树）；材质 REGULAR 基准随沉浸光感
// 总档在此解析，第三参 true = 交互形变 + 触点流光（官方最佳实践口径，勿回改 false）。
// 菜单宽度：不设——官方内容自适应（《规范-菜单与二级菜单》§3.1；现仅一项，写死宽留大片空白）。
import { ComponentContent, SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { AppMenuHost } from '../../common/AppMenuHost';
import { resolvedUiMaterial } from '../../common/ImmersiveLevel';
import {
  MORE_MENU_ANCHOR_RIGHT, MORE_MENU_BUTTON_BOTTOM_INSET, TITLE_BAR_MASK_EXTRA_HEIGHT,
  menuDividerColor
} from '../../common/Theme';

// 锚点 id（页面内唯一——与记忆库页 / 技能库页 / 工作区等锚点区分，防 openMenu 跨页同名误定位）
export const KNOWLEDGE_TITLE_MENU_ANCHOR_ID: string = 'knowledgeTitleMenuAnchor';

// 菜单回调（openMenu 的 ComponentContent 参数载体：全局 @Builder 无组件实例，回调经参数传入——
// 动作编排全在库管理页侧；后续加菜单项 = 接口加字段 + builder 加 MenuItem）
export interface KnowledgeTitleMenuCallbacks {
  // 导入知识库（链未动，仍为五闸 + 审阅弹窗 + 恒新建落库；新建已回胶囊左热区，不在本菜单）
  onImport: () => void;
}

// 菜单内容（官方 Menu 组件）：现仅单项「导入知识库」（新建已回胶囊左热区）。
// symbolStartIcon：导入 = arrow_down_to_line（导入语义，勿改 dot_grid_2x2 那是「更多」键语义）。
// 分割线 menuItemDivider 默认不显示须显式设置，mode 必须 EMBEDDED_IN_MENU（FLOATING 悬浮层被
// 菜单项盖住不可见），颜色走 menuDividerColor 深浅分治；AppStorage.get 直读（节点弹出前重建恒当前色）
@Builder
export function KnowledgeTitleMenuBuilder(params: KnowledgeTitleMenuCallbacks) {
  Menu() {
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_down_to_line')),
      content: '导入知识库' })
      .onClick(() => {
        params.onImport();
      })
  }
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 菜单节点宿主（AppMenuHost 薄壳——节点生命周期与弹出组装在基类，本壳只实现 buildNode 与便捷 open，
// 页面侧 init/open/dispose 调用零变化）
export class KnowledgeTitleMenuHost extends AppMenuHost<KnowledgeTitleMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: KnowledgeTitleMenuCallbacks): ComponentContent<KnowledgeTitleMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(KnowledgeTitleMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出菜单（基类弹前重建——按当前深浅色 / 材质重建 UI 树；材质 REGULAR 基准随沉浸光感总档在此解析）
  open(uiContext: UIContext, callbacks: KnowledgeTitleMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, KNOWLEDGE_TITLE_MENU_ANCHOR_ID,
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true));
  }
}

// 菜单隐形锚点（openMenu 的 TargetInfo 定位目标）：普通布局定位（Row 全宽 + Blank 撑开 + padding
// right）——锚点右缘 = 屏宽 − MORE_MENU_ANCHOR_RIGHT = 「更多」键右缘；锚点顶 = 按钮下沿（topPad −
// 蒙层增量 − 按钮下沿内缩，否则菜单整体偏低 8vp）。全高层 + HitTestMode.None 穿透触摸；禁
// position/calc 字符串定位（真机不生效，dshinhm 踩坑①；公式逐字同记忆库页 / 技能库页 / 工作区）
// 挂载 = 页面内容区 Stack 同层（与行卡、空态等兄弟节点并列，hitTest None 不拦滚动触摸）
@Component
export struct KnowledgeMoreMenuAnchor {
  // 页面顶部留白（vp，页面侧传入：HDS = 状态栏 + 标题栏 + 蒙层）
  topPad: number = 0;

  build() {
    Row() {
      Blank()
      Column()
        .width(1)
        .height(1)
        .id(KNOWLEDGE_TITLE_MENU_ANCHOR_ID)
    }
    .width('100%')
    .padding({ right: MORE_MENU_ANCHOR_RIGHT })
    .margin({
      top: Math.max(this.topPad - TITLE_BAR_MASK_EXTRA_HEIGHT - MORE_MENU_BUTTON_BOTTOM_INSET, 0)
    })
    .hitTestBehavior(HitTestMode.None)
  }
}
