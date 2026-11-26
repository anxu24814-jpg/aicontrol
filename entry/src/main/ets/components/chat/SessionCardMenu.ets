// 会话卡片菜单域（2026-10-30 自 ChatSessionList.ets 拆出并改写触发方式）：职责一句话 =
//「会话卡片的五项菜单内容 + 长按弹出的官方上下文菜单参数」。依赖单向（列表渲染域 → 本件
// → ChatDb / Theme / ImmersiveLevel），不反向引列表件，无模块环（坑50 口径）。
//
// ★ 触发方式沿革：原实现 = 卡片右缘四点键点击 → PromptAction.openMenu（锚点 TargetInfo）；
// 2026-10-30 起四点键退役，改「长按卡片 → bindContextMenu」。同日两千零一十节再改判：预览
// 浮起（自绘卡 + 全屏蒙层）整组退役，回标准官方上下文菜单——菜单按固定锚点定位、无预览卡、无
// 蒙层，卡片不缩放不移位。此前所有闪动与贴边都来自预览布局区、蒙层整层的创建拆除，别再引入。
// ★ 历史教训：2026-08-26 dshinhm 曾用过 bindContextMenu 真机不弹，事后查证是未归因的
// 一次性失败——那次是**无 preview 的非模态形态**且挂在同时有 onClick 的原生 Column 上；
// 本件现为同类无预览形态，仍以真机首验为准（不弹时先查 onClick 与手势竞争）。
//
// 菜单项顺序 = 重命名 / 移动到助手 / 收藏 / 删除（删除垫底——破坏性项离拇指最远，编辑类
// 一组；原第三项「加密会话」随 2026-11-17 整体退役加密会话笔撤除）；宽度机制教训（只有固定值
// width 触发官方「子项取固定宽」规则）见 common/Theme.ets。★ 草稿合成行 '__new__'：前三项
// enabled(false) 官方置灰，删除项照常可点（走壳侧草稿确认链）。
// 分割线：menuItemDivider 须显式设置且 mode 必须 EMBEDDED_IN_MENU（FLOATING 悬浮层被菜单项
// 盖住），颜色走 menuDividerColor 深浅分治；全局 @Builder 无组件实例，AppStorage.get 直读
//——节点每次弹出前重建，读取始终为当前深浅色（ChatMoreMenu.ets 同款姿势）。
import { uiMaterial, SymbolGlyphModifier } from '@kit.ArkUI';
import { ConversationRow } from '../../common/store/ChatDb';
import { MENU_UNIFIED_WIDTH, menuDividerColor } from '../../common/Theme';
import { resolvedUiMaterial } from '../../common/ImmersiveLevel';
import { NEW_DRAFT_KEY } from './ChatDraftStore';

// 菜单回调（交给全局 @Builder 的数据与动作载体——@Builder 无组件实例，一律参数注入）
export interface SessionCardMenuCallbacks {
  item: ConversationRow;
  onDelete: (item: ConversationRow) => void;
  onRename: (item: ConversationRow) => void;
  // 移动到助手（壳侧开半模态选助手 → 落库改归属；菜单入口放行、会话内助手面板保持
  // 锁定——两入口语义不同，口径见调研档 §五 Q1-A）
  onMove: (item: ConversationRow) => void;
  // 收藏开关（文案按 item.favorite 分「收藏/取消收藏」，动作 = 壳侧
  // toggleFavorite——直落库无认证前置）
  onToggleFavorite: (item: ConversationRow) => void;
}

// 会话卡片菜单内容（官方 Menu 组件）：重命名 = square_and_pencil / 移动到助手 =
// arrowshape_right（图标三表实锤、构建绿为终证——坑72）/ 收藏 = star（取消 = star_fill）/
// 删除 = trash（SDK 符号表实锤，坑72）。
@Builder
export function SessionCardMenuBuilder(params: SessionCardMenuCallbacks) {
  Menu() {
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')), content: '重命名' })
      .enabled(params.item.id !== NEW_DRAFT_KEY)
      .onClick(() => {
        params.onRename(params.item);
      })
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrowshape_right')), content: '移动到助手' })
      .enabled(params.item.id !== NEW_DRAFT_KEY)
      .onClick(() => {
        params.onMove(params.item);
      })
    MenuItem({
      symbolStartIcon: params.item.favorite ? new SymbolGlyphModifier($r('sys.symbol.star')) : new SymbolGlyphModifier($r('sys.symbol.star_fill')),
      content: params.item.favorite ? '取消收藏' : '收藏'
    })
      .enabled(params.item.id !== NEW_DRAFT_KEY)
      .onClick(() => {
        params.onToggleFavorite(params.item);
      })
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')), content: '删除' })
      .onClick(() => {
        params.onDelete(params.item);
      })
  }
  .width(MENU_UNIFIED_WIDTH)
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 菜单固定锚点：卡片左下角下方 8vp。anchorPosition 坐标相对绑定行左上角，系统按屏幕余量自动
// 翻到卡片上方；横向不再跟随触点，每次长按同一张卡菜单落位相同。x 取卡片左右内缩 16vp
//（CARD_PANEL_WIDTH = 100% − 32vp），菜单左缘与卡片左缘对齐，不贴屏幕边。
const CARD_MENU_ANCHOR_INSET: number = 16;
const CARD_MENU_ANCHOR_GAP: number = 8;

// 长按上下文菜单参数（options 工厂）：标准官方菜单，无 preview、无蒙层、固定锚点。
// ★ mask 显式 false：不挂 MenuMaskType 就没有全屏模糊层，打开与收起都不会整页闪（官方默认
// 值 = 有预览才开蒙层、无预览即 false，这里写死防回退）。菜单背板材质 = 沉浸光感 REGULAR
// 随全局档位（与全站菜单同源）。onMenuShow 在「动效前」回调——调用方在这里把横滑展开态
// 归位，避免菜单挂着一个已滑开的行。
// ★ 为什么不用 preview（2026-10-30 反馈轮 6~7，决明拍板）：预览浮起不是免费效果——官方对
// 组件型预览有「不超过可用布局区」的缩放约束，横滑行左右零边距又压掉菜单安全边距；全屏蒙层
// 在收起时整块拆除，真机 = 整页闪。四轮参数补丁（自绘白卡 / scale [1,1] / layoutRegionMargin
// 归零 / offset·targetSpace·transition·mask NONE）只能各修一个症状。去掉预览后这些机制全部
// 不存在：卡片不浮起不缩放不移位，菜单按锚点定位，没有蒙层。验收标准见规范 §4.18。
// ★ 锚点为什么固定（反馈轮 7~8，决明「弹出锚点跟手，能否改为固定」→「改到左边对称的吧」）：
// 长按型 bindContextMenu 默认在触点弹出，同一张卡按不同位置长按、菜单位置就变。anchorPosition
// 相对绑定行左上角定位，用卡高实测值钉在卡片左下角下方；卡高未实测时不下发锚点，回官方默认
// 定位。placement 与 anchorPosition 互斥（d.ts 明示预设 placement 不生效），不另设。
export function sessionCardMenuOptions(immersiveLevel: number,
  onMenuShow: () => void, cardHeight: number): ContextMenuOptions {
  const anchor: Position | undefined = cardHeight > 0
    ? { x: CARD_MENU_ANCHOR_INSET, y: cardHeight + CARD_MENU_ANCHOR_GAP }
    : undefined;
  return {
    anchorPosition: anchor,
    mask: false,
    systemMaterial: resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true),
    aboutToAppear: (): void => {
      onMenuShow();
    }
  };
}
