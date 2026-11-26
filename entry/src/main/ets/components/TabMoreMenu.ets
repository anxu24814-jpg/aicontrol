// 一级页页签标题栏域件（助手 / 对话两页签）。沿革速览（详情见 docs/变更记录.md 对应节）：
// 自 dshinhm TabMenuBuilder.ets 同域改写；标题栏键构多轮收敛（三键〔🔍＋⋯〕→ 双键胶囊
//〔＋|⋯〕→ 现态单圆键〔⋯更多〕，「＋新建会话」收入「更多」菜单首项——2026-10-29 二改笔，
// 决明「把『双键胶囊』改为更多，加号收入更多菜单」）；助手页签「更多」菜单因排序改列表
// 原位长按拖拽而整域退役（2026-09-27 落地笔），标题栏回到单键〔＋新建助手〕。
// ★ 会话列表右下悬浮新建键（components/chat/SessionNewFab，智感握姿左右跟随）与标题栏
//   〔＋〕同一个 onOpenNewSession → newConversation 链并存——两入口同动作，标题栏键不撤。
// 后续加菜单项 = 本文件接口加字段 + builder 加 MenuItem，HomeNavigation 零改动多耦合。
// 域边界：一级页两页签各自的标题栏键与菜单——HDS 覆盖层键构造 / 菜单内容 builder / 隐形
// 锚点 / 节点宿主与弹出（对话页签另有：多选指令计数器下发与标题栏内嵌分段承载）。
// 弹出机制选型（dshinhm docs/菜单弹窗定位规范 同款）：标题栏按钮是系统渲染层（HDS 标题栏
// 按钮只有 icon + action 回调，拿不到组件实例挂不了 bindMenu；Menu 组件无编程式弹出 API）
// → 官方「无 UI 组件场景弹菜单」姿势 = PromptAction.openMenu + 页面内隐形锚点。
// 「多选」下发 = AppStorage 一次性指令计数器（ChatSessionList @StorageProp @Watch 消费，
// 键常量在 ChatSessionList.ets——HomeNavigation→HdsTabs→TabContent 多层透传的零耦合替代，
// 坑3 口径）。排序项曾短暂入菜单后迁偏好设置页（「阅读与会话」板块分段单卡），子菜单
// builder 三件随迁退役——本菜单现为无子菜单普通菜单，宽度恒挂 MENU_UNIFIED_WIDTH（统一
// 宽三处口径，判据见规范 §3.2）；判据原文见变更记录一千二百一十八节。
import { ComponentContent, SegmentButtonV2Items, SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { AppMenuHost } from '../common/AppMenuHost';
import { resolvedUiMaterial } from '../common/ImmersiveLevel';
import { MENU_UNIFIED_WIDTH, MORE_MENU_ANCHOR_RIGHT, MORE_MENU_BUTTON_BOTTOM_INSET,
  TITLE_BAR_MASK_EXTRA_HEIGHT,
  TITLE_CENTER_ZONE_WIDTH, TITLE_CENTER_ZONE_MIN_WIDTH, TITLE_CENTER_ZONE_MAX_WIDTH,
  menuDividerColor } from '../common/Theme';
import { TITLE_BAR_EDGE_INSET, TitleBarRoundKey } from './TitleBarKeys';
// 标题栏内嵌分段（★ 2026-10-29 笔）：胶囊本体与标题栏档几何走 SegmentBar 封装，本件只给
// 定宽容器（缩短）与光感旁路（materialPinned）——方向 = 标题栏域件单向消费分段件，无环
import { SegmentBar } from './SegmentBar';

// ── HDS 路径：「对话」页签标题栏覆盖层（官方标题栏自定义区）──
// 现态（2026-10-29 二改笔，决明「取消搜索键；吸顶分段胶囊缩短移入标题栏居中」「把『双键
// 胶囊』改为更多，加号收入更多菜单」「分段胶囊略微加宽一些」）= **中央定宽分段胶囊 + 右端
// 单圆键〔⋯更多〕**两区：
//   · 搜索圆键退场，入口下沉 ⋯ 菜单（动作一字未动 = newSessionSearch）；「＋新建会话」为
//     菜单首项（动作一字未动 = HomeNavigation.newConversation，含多选守卫；菜单项序 =
//     新建会话 / 搜索会话 / 多选；原第四项「加密会话」随 2026-11-17 整体退役加密会话笔撤除）；
//     单动作页用单键而非双热区胶囊 = 共用件既定
//     判据（先例 = KnowledgeBookPage.TitleBarContent）；
//   · 「全部/收藏」分段自宿主标题栏下方带迁入本层中央（带随之整条取消），几何沿用
//     SegmentBar **标准档**（背板 40 与同栏 40vp 自绘键等高、热区合规）；
//   · **主标题保留**：keepStackTitle 仍为 true，标题「对话」照常由官方层渲染在左上，三区
//     互不遮挡（几何账见下方 SEGMENT_TITLE_* 常量注）。
// 官方依据：UI Design Kit《设置自定义区域》原文「例如在标题栏上方区域增加分段按钮」——
// 同文档示例 stackBuilder 即 Button + SegmentButton(width 150) + Button 三件；同文三条注意
// 事项逐条命中本实现。
// 键件与几何/光感双态全走共用件 components/TitleBarKeys.ets（几何/双态故事在该件头注释）。
// ★ 必须是**组件**（不可做成全局 @Builder）——HDS 的 titleBar napi 直接调用 stackBuilder
//   时无视图上下文，全局 @Builder 编译产物的 this 为 undefined → 运行期 TypeError 启动即
//   闪退（2026-09-09 真机实锤）。组件由 HomeNavigation.ChatTabTitleBarOverlay（组件内
//   @Builder）挂载，组件内 @Builder 编译为类方法、this 恒有绑定。
// 覆盖层根 = Stack（中央居中 + 右端对齐两区）：官方主标题由 keepStackTitle 保留（左侧标题区
// 不占），官方菜单数组本页签传 undefined（标题栏键已并入本覆盖层）

// 中央分段胶囊宽度（决明两轮加宽定稿后于 2026-10-30 连收两档）：**39% / 130~170
// （360vp 屏 = 140.4）**。右侧空间来自同笔「双键胶囊 → 单圆键」（+52vp），故加宽不压键——
// 几何手算（右组左缘 = 屏宽 − 16 − 40）：360 → 分段右缘 250.2、余 53.8vp；320 窄屏触下限
// 130、右缘 225、余 39vp（最紧）；336 余 46.5；384 余 61.1；400vp = 156，约 436vp 起封顶 170。
// 左侧标题「对话」右缘约 76：360 分段左缘 109.8、320 左缘 95——最窄屏仍不压标题。
// 上限守「不超双键胶囊两倍」口径 = 184（现 170）。
// ★ 2026-11-15 聊天页标题栏两态笔：数值上收 common/Theme.ets TITLE_CENTER_ZONE_* 三常量
//   （聊天页新会话态胶囊与两行标题共用同一宽度档），本处三别名保留 = 使用点/㊹ 组判据零改。
const SEGMENT_TITLE_WIDTH: string = TITLE_CENTER_ZONE_WIDTH;
const SEGMENT_TITLE_MIN_WIDTH: number = TITLE_CENTER_ZONE_MIN_WIDTH;
const SEGMENT_TITLE_MAX_WIDTH: number = TITLE_CENTER_ZONE_MAX_WIDTH;

@Component
export struct ChatTabTitleBar {
  // 光感档位（生效档位由共用件内 resolveEffectiveLevel 解析——本组件不再自持 keyLevel）
  @Prop immersiveLevel: number = 0;
  // 分段选项（纯展示普通成员——来源 = 宿主 HomeNavigation 传入的 CHAT_FAV_SEG_ITEMS 单源；
  // 本件不自造表，也不 import 会话列表域（避免标题栏域件反向依赖 ChatSessionList））
  items: SegmentButtonV2Items = new SegmentButtonV2Items([]);
  // 分段选中索引（@Link 与宿主 @State 双向同步——同 SegmentBar 契约，宿主传 $chatFavSegment）
  @Link selectedIndex: number;
  // 分段在场开关：多选态传 false——主标题切「已选 N 项」计数态，分段让位（多选中标题变长，
  // 中央区必须让出）。★ 必须是 @Prop 而非普通成员（坑24/坑57 族「普通成员 = 构造期快照」）：
  // 本值随父状态变化（宿主 = !sessionSelectMode），写普通成员则多选态切进来时不刷新，分段
  // 留在中央与「已选 N 项」长标题相压、且仍可点
  @Prop showSegment: boolean = true;
  onMore: () => void = (): void => {
  };

  build() {
    // Stack 叠两层：先右组（下层，全宽占位仅右端出键）、后中央分段（上层）——顺序不可反，
    // 反了则全宽的右组 Row 压住中央胶囊的点击热区（ArkUI 同层兄弟按书写序叠放）
    Stack({ alignContent: Alignment.Center }) {
      Row() {
        // 「更多」单圆键（原〔＋|⋯〕双热区胶囊拆开——加号收入「更多」菜单首项，本栏只留
        // 一枚「更多」键；单动作页用单键，胶囊右热区无动作 = 死控件）
        TitleBarRoundKey({
          icon: $r('sys.symbol.dot_grid_2x2'),
          label: '更多',
          immersiveLevel: this.immersiveLevel,
          onTap: (): void => {
            this.onMore();
          }
        })
      }
      .width('100%')
      .height('100%')
      .padding({ right: TITLE_BAR_EDGE_INSET })
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Center)
      // 中央分段：定宽 Column 逼官方分段组件缩短（组件宽恒等于父容器，无 width 参数——见
      // SegmentBar build 注释）；几何取**标准档**（背板 40 = 标题栏键同高，一排三件齐平；
      // 热区也保住官方最小 40vp——32vp 矮档位真机视觉「中间凹一块」）；materialPinned 恒
      // 光感（本层在标题栏生效区内，与迁移前 PageTopSegmentBand 同一旁路）
      if (this.showSegment) {
        Column() {
          SegmentBar({
            items: this.items,
            selectedIndex: $selectedIndex,
            materialPinned: true,
            // 2026-11-01 决明点名（取代 2026-10-30「选中字图标蓝」口径）：选中项统一 HDS 蓝
            // ——浅色白/灰胶囊 + 强调蓝字，深色强调蓝 30% 淡染底白字（取值依据见 SegmentBar
            // 头注释「选中态强调蓝变体」★条）。消费点两处 = 对话页标题栏覆盖层分段（本处）
            // + 侧栏面板分段（DrawerSidePanel.BandBottomBuilder，2026-11-18 侧栏优化③笔）
            emphasizeSelected: true
          })
        }
        .width(SEGMENT_TITLE_WIDTH)
        .constraintSize({
          minWidth: SEGMENT_TITLE_MIN_WIDTH,
          maxWidth: SEGMENT_TITLE_MAX_WIDTH
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}

// ── HDS 路径：「助手」页签标题栏覆盖层（官方标题栏自定义区）──
// 排序改助手页列表原位长按拖拽后，本页签「更多」菜单整域退役，本栏自此**单动作**（只有
//「＋新建助手」），按共用件既定判据「单动作页用单键而非双热区胶囊」改用 TitleBarRoundKey；
// 本组件保留为覆盖层壳（挂载死规矩仍适用）。
// 覆盖层根 Row 全宽全高 + 内容右对齐：官方主标题由 keepStackTitle 保留（覆盖层只占右侧）。
// ★ 覆盖层根**不挂** hitTestBehavior：Transparent 是**二级页**专属口径（整栏铺在返回键上方
//   会挡返回键——规范《行内按钮与光感》§4），本栏一级页 hideBackButton(true) 无返回键、
//   无此冲突，与同栏 ChatTabTitleBar 同口径。
// ★ 必须是**组件**（不可做成全局 @Builder）：HDS 的 titleBar napi 直接调用 stackBuilder 时
//   无视图上下文，全局 @Builder 编译产物取 this 为 undefined → 启动即闪退（坑30，真机实锤）。
//   组件由 HomeNavigation.AssistantTitleBarOverlay（组件内 @Builder）挂载。
@Component
export struct AssistantTitleBarKeys {
  // 光感档位（生效档位由共用件内 resolveEffectiveLevel 解析——本组件不自持 keyLevel）
  @Prop immersiveLevel: number = 0;
  onAdd: () => void = (): void => {
  };

  build() {
    Row() {
      TitleBarRoundKey({
        icon: $r('sys.symbol.plus'),
        label: '新建助手',
        immersiveLevel: this.immersiveLevel,
        onTap: (): void => {
          this.onAdd();
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding({ right: TITLE_BAR_EDGE_INSET })
    .justifyContent(FlexAlign.End)
    .alignItems(VerticalAlign.Center)
  }
}

// ═════════════ 「对话」页签更多菜单（openMenu 整域） ═════════════
// 「更多」菜单锚点 id（openMenu 的 TargetInfo 定位目标组件，页面内唯一——见 TabMoreMenuAnchor；
// 助手页签菜单退役后由对话页签独用）
export const TAB_MORE_MENU_ANCHOR_ID: string = 'tabMoreMenuAnchor';

// 锚点顶（距锚点父容器 Stack 顶，vp）· 几何单源 = Theme「按钮下沿」公式
//（MORE_MENU_ANCHOR_RIGHT + topInset − TITLE_BAR_MASK_EXTRA_HEIGHT −
// MORE_MENU_BUTTON_BOTTOM_INSET）。★ 2026-11-18 对齐笔：原页签专用 DELTA=30 定稿退役——
// 它把菜单顶放在按钮下沿再向下 30vp，与日志页/服务商管理页/聊天页等所有标题栏「更多」菜单
// 不一致；决明报「非侧栏形态一级页右上角更多菜单偏下」即此。现全站（含页签主页面）一律锚
// 「按钮下沿」，两套几何并存的旧规废止。
// 24vp 差额来源：topInset 含蒙层下延 16，按钮 40 在 56 栏内垂直居中（下沿距栏底 8），
// 故 topInset − 16 − 8 恰落在按钮下沿。
// ★ 2026-11-24 真机回归修（页签形态锚点偏上）：本锚点 topInset 原为**普通成员**（构造期
// 快照），而 TabShell 冷启动首帧即建立、statusBarHeight 由 Index 异步实测（首帧恒 0）——
// 锚点永久冻结在「56 + 16」口径，比按钮下沿高一个状态栏高；旧 DELTA=30 恰把这截状态栏高
// 补回，故 11-18 改统一公式后才显形（决明报「关闭偏好开关时一级对话页右上角更多菜单锚点
// 又偏上了」）。修 = topInset 升 @Prop（同 2208 ChatPageContent.topPad 同族判例），晚到实测
// 值穿透本层；公式与其余菜单零改动。

// 本菜单固定宽 = 项目级 **MENU_UNIFIED_WIDTH**（`common/Theme.ets`，三处菜单共用单一来源
// 防复制魔数——列表卡片菜单 / 消息页标题栏菜单与本案同值，横比无宽窄差）。本菜单现为无
// 子菜单普通菜单，宽度恒挂本值保留理由 = 三处统一宽口径；值推导与「只有固定值 width 触发
// 官方『子项取固定宽』规则（constraintSize / width('100%') 两形态已证无效勿回填）」的机制
// 教训见 Theme 常量注释。

// 「更多」菜单隐形锚点组件（openMenu 的 TargetInfo 定位目标组件）：普通布局定位
//（Row 全宽 + Blank 撑开 + padding right）——锚点右缘 = 屏宽 - MORE_MENU_ANCHOR_RIGHT =
// 「更多」按钮右缘（标题栏 padding end）。全高层 + HitTestMode.None 穿透触摸（禁
// position/calc 字符串定位——真机不生效，dshinhm 踩坑①）
@Component
export struct TabMoreMenuAnchor {
  // 锚点顶偏移（vp，宿主 titleBarInset() 传入 = 状态栏 + MINI 栏高 + 蒙层溢出）。
  // ★ 必须 @Prop（2026-11-24 修）：TabShell 冷启动首帧构造时 statusBarHeight 尚为 0（Index
  // 异步实测），普通成员会把 topInset 冻结在无状态栏口径 = 锚点整体偏上一个状态栏高；
  // @Prop 让宿主晚到的实测值穿透本层（同 2208 ChatPageContent.topPad 判例），勿退回普通成员。
  @Prop topInset: number = 0;

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Row() {
        Blank()
        Column()
          .width(1)
          .height(1)
          .id(TAB_MORE_MENU_ANCHOR_ID)
      }
      .width('100%')
      .padding({ right: MORE_MENU_ANCHOR_RIGHT })
      .margin({ top: Math.max(this.topInset - TITLE_BAR_MASK_EXTRA_HEIGHT -
        MORE_MENU_BUTTON_BOTTOM_INSET, 0) })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}

// 菜单回调（openMenu 的 ComponentContent 参数载体：全局 @Builder 无法访问组件实例，
// 回调经参数传入；后续加菜单项 = 接口加字段 + builder 加 MenuItem）
export interface TabMoreMenuCallbacks {
  // 新建会话（动作 = HomeNavigation.newConversation——懒创建 + push 对话页；多选守卫在方法内）
  onNew: () => void;
  // 搜索会话（动作 = HomeNavigation.newSessionSearch——push SessionSearchPage 二级页）。
  // **不是**一级页原地过滤：那条路线（页顶搜索框 + keyword 上提）已按决明「收入更多菜单，
  // 点击仍进二级页」放弃
  onSearch: () => void;
  onMultiselect: () => void;
}

// 「更多」菜单内容（官方 Menu 组件，三项 = 新建会话 / 搜索会话 / 多选）：宽度挂
// 项目统一固定值 MENU_UNIFIED_WIDTH（三处菜单统一宽口径，见上方常量注释；右缘对齐「更多」
// 按钮仍由 placement 保证）；list_checkmark 字形 SDK 符号表实锤（坑72 口径）。
// 分割线：Menu.menuItemDivider 默认不显示须显式设置，mode 必须 EMBEDDED_IN_MENU（FLOATING
// 悬浮层被菜单项盖住不可见），颜色走 menuDividerColor 深浅分治；全局 @Builder 无组件实例，
// AppStorage.get 直读——菜单节点每次弹出前重建，读取始终为当前深浅色
@Builder
export function TabMoreMenuBuilder(params: TabMoreMenuCallbacks) {
  Menu() {
    // 新建会话（首项——三项里使用频率最高；plus = 原左热区同符号，迁移后图标语义不断）
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.plus')), content: '新建会话' })
      .onClick(() => {
        params.onNew();
      })
    // 搜索会话（位次第二；magnifyingglass = 原圆键同符号，语义不断）
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.magnifyingglass')), content: '搜索会话' })
      .onClick(() => {
        params.onSearch();
      })
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.list_checkmark')), content: '多选' })
      .onClick(() => {
        params.onMultiselect();
      })
  }
  // 固定宽度恒定保留：与列表卡片菜单（`ChatSessionList.SessionCardMenuBuilder`）、消息页
  // 标题栏菜单（`ChatMoreMenu.ChatMoreMenuBuilder`）三处同值。★ 勿因「本菜单项短」删宽回
  // 自适应——三处横比是本常量存在的理由，单独回退即与另外两处拉开 20vp 差（官方默认基准
  // 160），口径见规范 §3.2
  .width(MENU_UNIFIED_WIDTH)
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 「更多」菜单节点宿主（AppMenuHost 薄壳——节点生命周期与弹出组装在基类，本壳只实现
// buildNode（wrapBuilder 须直呼自家 @Builder 函数，编译器静态校验）与便捷 open（材质解析 +
// 锚点 id），页面侧 init/open/dispose 调用零变化）
export class TabMoreMenuHost extends AppMenuHost<TabMoreMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: TabMoreMenuCallbacks): ComponentContent<TabMoreMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(TabMoreMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出菜单（基类弹前重建——按当前深浅色/材质重新构建 UI 树；材质 REGULAR 基准随沉浸光感
  // 总档在此解析，页面侧只传档位值）。★ 第三参 true = 交互形变 + 触点流光（官方最佳实践
  // 口径，勿回改 false）
  open(uiContext: UIContext, callbacks: TabMoreMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, TAB_MORE_MENU_ANCHOR_ID,
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true));
  }
}

// ═════════════ （「助手」页签「更多」菜单整域——已退役）═════════════
// 退役原因：排序改助手页列表原位长按拖拽后，本页签「更多」菜单再无菜单项，留着即是空壳键
// ⇒ 回调接口 / 内容 builder / 节点宿主三件与 HomeNavigation 侧 init·open·dispose 调用、
// AssistantTitleBarKeys 的右热区一并删除；标题栏回到单键。原文与判据见 docs/变更记录.md
// 一千一百一十六节。对话页签的「更多」菜单域仍在文件上半部；锚点 TAB_MORE_MENU_ANCHOR_ID
// 由对话页签独用（锚点组件与常量保留）。
