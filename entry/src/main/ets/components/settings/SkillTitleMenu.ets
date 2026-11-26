// 技能库页标题栏键与「更多」菜单域。自 MemoryTitleMenu.ets 同域模式复制（机制/生命周期/材质同源）；
// 独立成件的理由 = 标题栏菜单在工程内一律独立域件（四先例），且本域自带菜单锚点与节点宿主，与行卡
// 菜单 SkillRowMenu 是两条职责缝。组成 = HDS 标题栏覆盖层 / openMenu 内容 builder / 隐形锚点 / 节点
// 宿主（init 建 / open 前重建 / dispose 成对释放）；回退 Navigation.menus 双键数组已随 2026-10-31
// HDS 兜底撤除整笔退役。
// ★ 键形：HDS 路径标题栏恰两键且**合并为一枚双热区胶囊**〔＋新建技能 | ⋯更多〕——官方菜单数组每项只
//   渲染独立圆钮、画不出合并形态，故走官方标题栏自定义区 stackBuilder 覆盖层，键件与几何/双态走共用件
//   TitleBarKeys.ets，官方菜单数组本页传 null。数组序（左→右）= 胶囊两热区序 = ＋ 在左、⋯ 恒最右——
//   「⋯」是菜单锚点几何前提（锚点右缘 = 标题栏键右缘）。导入入口由右热区挪进菜单（换位不换链，底层
//   导入链未动）；「多选」为批量删除入口，项序 = 导入技能 / 多选（多选末位，模式入口垫底，决明拍板）。
// 几何：菜单锚点走《Theme》「按钮下沿」公式（MORE_MENU_ANCHOR_RIGHT + topPad -
//   TITLE_BAR_MASK_EXTRA_HEIGHT - MORE_MENU_BUTTON_BOTTOM_INSET），全站统一本几何（★ 2026-11-18
//   对齐笔后页签主页面同用，旧 DELTA=30 定稿退役）；锚点右缘 = 「更多」键右缘，故「更多」必须是末键/右热区。
// 菜单宽度：**不设**——官方内容自适应（《规范-菜单与二级菜单》§3.1；两项皆短，写死宽会留大片空白）
import { ComponentContent, SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { AppMenuHost } from '../../common/AppMenuHost';
import { resolvedUiMaterial } from '../../common/ImmersiveLevel';
import {
  MORE_MENU_ANCHOR_RIGHT, MORE_MENU_BUTTON_BOTTOM_INSET, TITLE_BAR_MASK_EXTRA_HEIGHT,
  menuDividerColor
} from '../../common/Theme';
import { TITLE_BAR_EDGE_INSET, TitleBarActionCapsule } from '../TitleBarKeys';

// 锚点 id（页面内唯一——与记忆库页/对话页签锚点区分，防 openMenu 跨页同名误定位）
export const SKILL_TITLE_MENU_ANCHOR_ID: string = 'skillTitleMenuAnchor';

// HDS 路径：技能库页标题栏覆盖层（官方标题栏自定义区）。键件与几何/光感双态全走共用件 TitleBarKeys.ets
//（双热区胶囊；本页是该件抽取的第四处来源，见该件头注释消费方清单）。
// ★ 必须是**组件**（不可做成全局 @Builder）——HDS 的 titleBar napi 直接调用 stackBuilder 时无视图
//   上下文，全局 @Builder 编译产物的 this 为 undefined → 运行期 TypeError 启动即闪退（坑30，真机实锤；
//   先例 = ChatPage.TitleBarContent / MemoryPage.TitleBarKeys）。组件内 @Builder 编译为类方法、this 恒有绑定。
// 覆盖层根 Row 全宽全高 + 内容右对齐 + 空白区命中透传（Transparent）：官方主标题「技能库」由
//   PageShell.keepStackTitle 保留；命中透传是二级页必需——覆盖层整栏铺在返回键上方，默认命中档会挡住
//   返回键（真机实锤，规范《行内按钮与光感》§4 二级页同规③）
@Component
export struct SkillTitleBarKeys {
  // 光感档位（生效档位由共用件内 resolveEffectiveLevel 解析——本组件不自持 keyLevel）
  @Prop immersiveLevel: number = 0;
  onAdd: () => void = (): void => {
  };
  onMore: () => void = (): void => {
  };

  build() {
    Row() {
      // 合并胶囊（左加号右更多，各一热区；图标与无障碍文案——自绘键无可见文字，读屏与自动化
      // 按 label 识别）
      TitleBarActionCapsule({
        leftIcon: $r('sys.symbol.plus'),
        leftLabel: '新建技能',
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
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.Transparent)
  }
}

// 菜单回调（openMenu 的 ComponentContent 参数载体：全局 @Builder 无组件实例，回调经参数传入——动作编排
// 全在库管理页侧；后续加菜单项 = 接口加字段 + builder 加 MenuItem）
export interface SkillTitleMenuCallbacks {
  // 导入技能（单入口双格式：同一项按扩展名分派 .zip 与 .md；入口自标题栏右热区挪入本菜单，底层链未动）
  onImport: () => void;
  // 多选：进入批量删除模式（形态照会话列表/提示词库页——批量条/删除编排在库管理页侧）
  onMultiselect: () => void;
}

// 菜单内容（官方 Menu 组件）：宽度不设——官方按内容自适应（《规范-菜单与二级菜单》§3.1 一级
// 口径）；symbolStartIcon：导入 = arrow_down_to_line（导入语义）/ 多选 = list_checkmark（列表勾选
// 语义；勿用 dot_grid_2x2，那是「更多」键语义）。项序 = 导入技能 / 多选（多选末位，决明拍板）。
// 分割线：menuItemDivider 默认不显示须显式设置，mode 必须 EMBEDDED_IN_MENU（FLOATING 悬浮层被菜单项
// 盖住不可见），颜色走 menuDividerColor 深浅分治；AppStorage.get 直读（节点弹出前重建，恒当前深浅色）
@Builder
export function SkillTitleMenuBuilder(params: SkillTitleMenuCallbacks) {
  Menu() {
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_down_to_line')),
      content: '导入技能' })
      .onClick(() => {
        params.onImport();
      })
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.list_checkmark')),
      content: '多选' })
      .onClick(() => {
        params.onMultiselect();
      })
  }
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 菜单节点宿主（AppMenuHost 薄壳——节点生命周期与弹出组装在基类，本壳只实现 buildNode 与便捷 open，
// 页面侧 init/open/dispose 调用零变化）
export class SkillTitleMenuHost extends AppMenuHost<SkillTitleMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: SkillTitleMenuCallbacks): ComponentContent<SkillTitleMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(SkillTitleMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出菜单（基类弹前重建——按当前深浅色/材质重建 UI 树；材质 REGULAR 基准随沉浸光感总档在此解析）
  open(uiContext: UIContext, callbacks: SkillTitleMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, SKILL_TITLE_MENU_ANCHOR_ID,
      // ★ 第三参 true = 交互形变 + 触点流光（菜单光感笔；官方最佳实践口径）
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true));
  }
}

// 菜单隐形锚点（openMenu 的 TargetInfo 定位目标）：**普通布局定位**（Row 全宽 + Blank 撑开 + padding
// right）——锚点右缘 = 屏宽 - MORE_MENU_ANCHOR_RIGHT = 「更多」键右缘；锚点顶 = 按钮下沿（topPad - 蒙层
// 增量 - 按钮下沿内缩，否则菜单整体偏低 8vp）。全高层 + HitTestMode.None 穿透触摸（禁 position/calc
// 字符串定位——真机不生效，dshinhm 踩坑①；公式逐字同 MemoryMoreMenuAnchor / LogPageContent / ProviderPage）
@Component
export struct SkillMoreMenuAnchor {
  // 页面顶部留白（vp，页面侧传入：HDS = 状态栏 + 标题栏 + 蒙层；回退 = 0）
  topPad: number = 0;

  build() {
    Row() {
      Blank()
      Column()
        .width(1)
        .height(1)
        .id(SKILL_TITLE_MENU_ANCHOR_ID)
    }
    .width('100%')
    .padding({ right: MORE_MENU_ANCHOR_RIGHT })
    .margin({
      top: Math.max(this.topPad - TITLE_BAR_MASK_EXTRA_HEIGHT - MORE_MENU_BUTTON_BOTTOM_INSET, 0)
    })
    .hitTestBehavior(HitTestMode.None)
  }
}
