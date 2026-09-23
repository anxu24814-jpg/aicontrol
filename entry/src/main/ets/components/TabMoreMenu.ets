// 一级页页签标题栏域件（助手 / 对话两页签——2026-09-22 助手页签并入，原「只做对话页签」
// 的域边界随之放宽；2026-08-29 会话多选删除 自 dshinhm
// TabMenuBuilder.ets 同域改写——「搜索会话/已归档」是 kap 语义不迁；2026-09-04 加
// 「隐私会话」项；后续加菜单项 = 本文件接口加字段 + builder 加 MenuItem，HomeNavigation
// 零改动多耦合；
// ★ 2026-08-31 领导指令：新建会话悬浮键上移标题栏——键构造改双键〔＋新建／⋯更多〕；
// 2026-09-08 会话搜索与收藏再扩三键〔🔍搜索／＋新建／⋯更多〕；
// ★ 2026-09-09 决明「一级对话页右上角的『加号』和『更多』按钮合并为双键胶囊型，可直接
//   参考消息页右上角的胶囊」：HDS 路径三键数组退役（官方数组每项只渲染独立圆钮、画不出
//   合并形态），改标题栏自定义区覆盖层 ChatTabTitleBar（组件）= 搜索圆键 + 合并胶囊
//   〔＋|⋯〕；回退路径无 stackBuilder 机制，仍是官方三键数组 sessionsMoreMenuFallback）。
// ★ 2026-09-11 迁移笔（决明「先把这个迁了」）：覆盖层键件改消费共用件
//   `components/TitleBarKeys.ets`（本处原持 TAB_* 八常量 + 内联键件，已删；本处是共用件
//   抽取的「第二处」来源）——几何/双态单源在该件，改动前先看 sse-assert 60 组。
// ★ 2026-09-22 助手页签合并胶囊笔（决明「助手页标题栏改为＋/更多双键胶囊，加保持原功能，
//   点击更多弹菜单，放排序键（功能先不做）」）：助手页签标题栏由官方菜单数组**单键「＋」**
//   改为**一枚双热区胶囊〔＋新建助手 | ⋯更多〕**（与消息页 / 记忆页 / 服务商管理页同形），
//   ⋯ 弹出「更多」菜单，现仅「排序」一项（排序功能尚未实现，点击给占位提示）；回退路径
//   （无 HDS Core syscap）无 stackBuilder 机制、拼不出合并形态，仍是官方菜单数组，**键集/
//   动作/顺序与胶囊逐项对齐** = 两键数组〔＋新建助手〕〔⋯更多〕（本页签此前为单键）。
//   ★ 「＋」动作一字未动 = 仍经 ASSISTANT_CREATE_CMD_KEY 指令键下发 AssistantPage 弹名称
//   对话框（2026-09-01 按钮区退役轮口径）；菜单锚点与对话页签菜单共用（两键右缘几何同源）。
// 域边界：一级页两页签各自的标题栏键与菜单——HDS 覆盖层键构造 / 回退 Navigation.menus
// 数组构造 / 菜单内容 builder / 隐形锚点 / 节点宿主与弹出（对话页签另有：多选指令计数器下发）。
// 弹出机制选型（dshinhm docs/菜单弹窗定位规范 同款）：标题栏按钮是系统渲染层（HDS 标题栏
// 按钮只有 icon + action 回调，拿不到组件实例挂不了 bindMenu；Menu 组件无编程式弹出 API）
// → 官方「无 UI 组件场景弹菜单」姿势 = PromptAction.openMenu + 页面内隐形锚点。
// 「多选」下发 = AppStorage 一次性指令计数器（ChatSessionList @StorageProp @Watch 消费，
// 键常量在 ChatSessionList.ets——HomeNavigation→HdsTabs→TabContent 多层透传的零耦合替代，
// 坑3 口径）。
import { ComponentContent, SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { AppMenuHost } from '../common/AppMenuHost';
import { resolvedUiMaterial } from '../common/ImmersiveLevel';
import { MORE_MENU_ANCHOR_RIGHT, TITLE_BAR_MASK_EXTRA_HEIGHT, menuDividerColor } from '../common/Theme';
import { TITLE_BAR_EDGE_INSET, TITLE_KEY_GAP, TitleBarActionCapsule,
  TitleBarRoundKey } from './TitleBarKeys';

// ── HDS 路径：「对话」页签标题栏覆盖层（官方标题栏自定义区，2026-09-09 合并胶囊笔）──
// 键件与几何/光感双态全走共用件 components/TitleBarKeys.ets（单圆键 + 双热区胶囊；形制
// 「第三处出现」后抽取，2026-09-11 迁移笔本处改消费共用件——原 TAB_* 八常量的几何与双态
// 故事（含「第二处暂不抽、第三处再抽」的约定）已并入该件头注释）。
// 「对话」页签标题栏覆盖层（自绘键，右组 = 搜索圆键 + 合并胶囊〔＋|⋯〕；符号 = 官方
// 符号表实锤，坑72 口径）。
// ★ 必须是**组件**（不可做成全局 @Builder）——HDS 的 titleBar napi 直接调用 stackBuilder
//   时无视图上下文，全局 @Builder 编译产物 `(parent ? parent : this).observeComponentCreation2`
//   的 this 为 undefined → 运行期 TypeError「Cannot read property observeComponentCreation2
//   of undefined」启动即闪退（2026-09-09 真机实锤，故障栈 hdsBaseComponent.js:111 → 全局
//   builder entry）。组件由 HomeNavigation.ChatTabTitleBarOverlay（组件内 @Builder）挂载，
//   组件内 @Builder 编译为类方法、this 恒有绑定。
// 覆盖层根 Row 全宽全高 + 内容右对齐：官方主标题由 keepStackTitle 保留（左侧标题区不占），
// 官方菜单数组本页签传 undefined（三键已并入本覆盖层）
@Component
export struct ChatTabTitleBar {
  // 光感档位（生效档位由共用件内 resolveEffectiveLevel 解析——本组件不再自持 keyLevel）
  @Prop immersiveLevel: number = 0;
  onSearch: () => void = (): void => {
  };
  onNew: () => void = (): void => {
  };
  onMore: () => void = (): void => {
  };

  build() {
    Row({ space: TITLE_KEY_GAP }) {
      // 搜索键（push 独立二级搜索页 SessionSearchPage——原官方菜单键同动作）
      TitleBarRoundKey({
        icon: $r('sys.symbol.magnifyingglass'),
        label: '搜索会话',
        immersiveLevel: this.immersiveLevel,
        onTap: (): void => {
          this.onSearch();
        }
      })
      // 合并胶囊（左加号右更多，各一热区——共用件形制同消息页胶囊）
      TitleBarActionCapsule({
        leftIcon: $r('sys.symbol.plus'),
        leftLabel: '新建会话',
        rightIcon: $r('sys.symbol.dot_grid_2x2'),
        rightLabel: '更多',
        immersiveLevel: this.immersiveLevel,
        onLeftTap: (): void => {
          this.onNew();
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
  }
}

// 回退路径（设备无 HDS Core syscap）：Navigation.menus 数组构造（dshinhm buildFallbackMenus
// 同款）——NavigationMenuItem 官方菜单：API 10+ 文字不可见仅图标，symbolIcon 优先于 icon
export function sessionsMoreMenuFallback(onSearch: () => void, onNew: () => void,
  onMore: () => void): NavigationMenuItem[] {
  return [{
    value: '搜索会话',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.magnifyingglass')),
    action: onSearch
  } as NavigationMenuItem, {
    value: '新建会话',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.plus')),
    action: onNew
  } as NavigationMenuItem, {
    value: '更多',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.dot_grid_2x2')),
    action: onMore
  } as NavigationMenuItem];
}

// ── HDS 路径：「助手」页签标题栏覆盖层（官方标题栏自定义区，2026-09-22 合并胶囊笔）──
// 一枚双热区胶囊〔＋新建助手 | ⋯更多〕，键件与几何/光感双态全走共用件
// components/TitleBarKeys.ets（本页签为共用件消费方——对话页签同件，两页签同栏同形）。
// ★ 覆盖层根**不挂** hitTestBehavior：Transparent 是**二级页**专属口径（整栏铺在返回键上方
//   会挡返回键——规范《行内按钮与光感》§4 + 服务商管理页 158 组），本栏一级页
//   hideBackButton(true) 无返回键、无此冲突，与同栏 ChatTabTitleBar 同口径。
// ★ 必须是**组件**（不可做成全局 @Builder）：HDS 的 titleBar napi 直接调用 stackBuilder 时
//   无视图上下文，全局 @Builder 编译产物取 this 为 undefined → 启动即闪退（坑30，2026-09-09
//   真机实锤，栈见 ChatTabTitleBar 头注释）。组件由 HomeNavigation.AssistantTitleBarOverlay
//   （组件内 @Builder）挂载，组件内 @Builder 编译为类方法、this 恒有绑定。
// 覆盖层根 Row 全宽全高 + 内容右对齐：官方主标题由 keepStackTitle 保留（覆盖层只占右侧）。
@Component
export struct AssistantTitleBarKeys {
  // 光感档位（生效档位由共用件内 resolveEffectiveLevel 解析——本组件不自持 keyLevel）
  @Prop immersiveLevel: number = 0;
  onAdd: () => void = (): void => {
  };
  onMore: () => void = (): void => {
  };

  build() {
    Row() {
      // 合并胶囊（左加号右更多，各一热区；★ 键序是几何前提：「⋯」恒最右 = 菜单锚点右缘
      // 与键右缘齐——锚点几何见下方 TabMoreMenuAnchor）
      TitleBarActionCapsule({
        leftIcon: $r('sys.symbol.plus'),
        leftLabel: '新建助手',
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
  }
}

// 「助手」页签回退路径（Navigation.menus 数组构造）：键集/动作/顺序与胶囊逐项对齐 = 两键
// 〔＋新建助手〕〔⋯更多〕（API 10+ 文字不可见仅图标；value 仍写全称：兼作无障碍文案与自动化
// 识别名）。★ 序 = ＋ 在前、⋯ 末键——⋯ 是末键时其右缘才落在标题栏 end padding 16 上
export function assistantsMoreMenuFallback(onAdd: () => void,
  onMore: () => void): NavigationMenuItem[] {
  return [{
    value: '新建助手',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.plus')),
    action: onAdd
  } as NavigationMenuItem, {
    value: '更多',
    symbolIcon: new SymbolGlyphModifier($r('sys.symbol.dot_grid_2x2')),
    action: onMore
  } as NavigationMenuItem];
}

// ═════════════ 「对话」页签更多菜单（openMenu 整域） ═════════════
// 「更多」菜单锚点 id（openMenu 的 TargetInfo 定位目标组件，页面内唯一——见 TabMoreMenuAnchor）
// ★ 两个页签的「更多」菜单**共用本锚点**（2026-09-22 助手页签合并胶囊笔）：两枚胶囊的 ⋯ 热区
//   同处标题栏右缘（右内距同为 TITLE_BAR_EDGE_INSET = MORE_MENU_ANCHOR_RIGHT），锚点几何逐值
//   相同，无须第二枚隐形锚点；两菜单宿主各自持节点，弹出互斥（一次只会弹一个）
export const TAB_MORE_MENU_ANCHOR_ID: string = 'tabMoreMenuAnchor';

// 锚点顶（距锚点父容器 Stack 顶，vp）：HDS = 蒙层下沿 + 本增量（唯一调参点）。定稿值
// DELTA = 30 沿用 dshinhm 真机收敛史（2026-08-25 真机截图 + 观感四轮：56.9 → 47 → 32 →
// 30 定稿，菜单顶贴按钮下沿观感同官方；同为一极页 HdsNavigation 标题栏几何、同 SDK 同
// 常量族——后续设备差异只允许 targetSpace/offset 或本常量微调，勿回改按钮几何公式）
const MORE_MENU_ANCHOR_DELTA: number = 30;

// 「更多」菜单隐形锚点组件（openMenu 的 TargetInfo 定位目标组件）：普通布局定位
//（Row 全宽 + Blank 撑开 + padding right）——锚点右缘 = 屏宽 - MORE_MENU_ANCHOR_RIGHT =
// 「更多」按钮右缘（标题栏 padding end）。全高层 + HitTestMode.None 穿透触摸（禁
// position/calc 字符串定位——真机不生效，dshinhm 踩坑①）
@Component
export struct TabMoreMenuAnchor {
  // 锚点顶偏移（vp，宿主 titleBarInset() 传入：HDS = 状态栏 + MINI 栏高 + 蒙层溢出；回退 = 0）
  topInset: number = 0;

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
      .margin({ top: Math.max(this.topInset - TITLE_BAR_MASK_EXTRA_HEIGHT +
        MORE_MENU_ANCHOR_DELTA, 0) })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}

// 菜单回调（openMenu 的 ComponentContent 参数载体：全局 @Builder 无法访问组件实例，
// 回调经参数传入——「多选」「隐私会话」两项；后续加菜单项 = 接口加字段 + builder 加 MenuItem）
export interface TabMoreMenuCallbacks {
  onMultiselect: () => void;
  // 隐私会话（2026-09-04）：进 ChatPage 隐私模式——纯内存会话不落盘不进历史，离页即焚；
  // 行为编排全在 ChatPage/ChatSendCtrl 隐私分支，本菜单只做入口转发
  onPrivateSession: () => void;
  // 加密会话（2026-09-05 决明指令「入口在对话一级页右上角菜单」）：先过官方生物识别，
  // 通过后进懒创建新会话——加密标记经 PENDING_LOCKED_CONV_KEY 随首条消息落行（编排全在
  // HomeNavigation.newEncryptedSession，本菜单只做入口转发）
  onNewEncryptedSession: () => void;
}

// 「更多」菜单内容（官方 Menu 组件）：宽度不设——官方默认按内容自适应（右缘对齐「更多」
// 按钮由 placement 保证，不依赖宽度已知）；list_checkmark 字形 SDK 符号表实锤（坑72 口径）。
// 分割线：Menu.menuItemDivider 默认不显示须显式设置，mode 必须 EMBEDDED_IN_MENU（FLOATING
// 悬浮层被菜单项盖住不可见），颜色走 menuDividerColor 深浅分治；全局 @Builder 无组件实例，
// AppStorage.get 直读——菜单节点每次弹出前重建，读取始终为当前深浅色（ChatMoreMenu 同款）
@Builder
export function TabMoreMenuBuilder(params: TabMoreMenuCallbacks) {
  Menu() {
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.list_checkmark')), content: '多选' })
      .onClick(() => {
        params.onMultiselect();
      })
    // 隐私会话（2026-09-04）：eye_slash 符号 SDK 符号表实锤（坑72 口径）
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.eye_slash')), content: '隐私会话' })
      .onClick(() => {
        params.onPrivateSession();
      })
    // 加密会话（2026-09-05）：lock 符号——列表卡片锁标同符号（字形已在用，坑72 口径）
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.lock')), content: '加密会话' })
      .onClick(() => {
        params.onNewEncryptedSession();
      })
  }
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 「更多」菜单节点宿主（2026-08-30 反馈轮 13 起为 AppMenuHost 薄壳——节点生命周期与
// 弹出组装在基类，本壳只实现 buildNode（wrapBuilder 须直呼自家 @Builder 函数，编译器
// 静态校验）与便捷 open（材质解析 + 锚点 id），页面侧 init/open/dispose 调用零变化）
export class TabMoreMenuHost extends AppMenuHost<TabMoreMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: TabMoreMenuCallbacks): ComponentContent<TabMoreMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(TabMoreMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  // 弹出菜单（基类弹前重建——按当前深浅色/材质重新构建 UI 树；材质 REGULAR 基准随
  // 沉浸光感总档在此解析，页面侧只传档位值）
  // ★ 第三参 true = 交互形变 + 触点流光（2026-09-18 菜单光感笔；官方最佳实践口径，勿回改 false）
  open(uiContext: UIContext, callbacks: TabMoreMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, TAB_MORE_MENU_ANCHOR_ID,
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true));
  }
}

// ═════════════ 「助手」页签「更多」菜单（openMenu 整域，2026-09-22 合并胶囊笔新增） ═════════════
// 菜单回调（openMenu 的 ComponentContent 参数载体：全局 @Builder 无法访问组件实例，回调经
// 参数传入——现仅「排序」一项；后续加菜单项 = 接口加字段 + builder 加 MenuItem）
export interface AssistantTitleMenuCallbacks {
  // 排序（★ 本笔只放键、**功能尚未实现**——点击给占位提示不静默；落地时改 push 助手排序页，
  // 先例 = 服务商管理页 ROUTE_PROVIDER_SORT_PAGE / 记忆页 ROUTE_MEMORY_SORT_PAGE）
  onSort: () => void;
}

// 「助手」页签「更多」菜单内容（官方 Menu 组件）：排序项符号 = sys.symbol.sort——字形即
// 决明要的「由上到下从长到短三线」（2026-09-22 决明「排序图标…换成由上到下从长到短三线，
// 官方有吗」；SDK 符号表实锤：previewer resources.txt 码位 0xF0AF9，字形 128px 渲染核验 =
// 顶线最长→底线最短三横线；服务商管理页同笔、记忆页 877 节跟笔，三处同源——符号证据与
// 「以后排序一律用本符号」口径见 ProviderTitleMenu.ets 单源注释）。
// 分割线 EMBEDDED_IN_MENU 深浅分治（TabMoreMenuBuilder 同款，AppStorage.get 直读——节点
// 每次弹出前重建取当前深浅色）
@Builder
export function AssistantTitleMenuBuilder(params: AssistantTitleMenuCallbacks) {
  Menu() {
    MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.sort')), content: '排序' })
      .onClick(() => {
        params.onSort();
      })
  }
  .menuItemDivider({
    color: menuDividerColor(AppStorage.get<number>('appColorMode')),
    mode: DividerMode.EMBEDDED_IN_MENU
  })
}

// 「助手」页签「更多」菜单节点宿主（AppMenuHost 薄壳，口径同 TabMoreMenuHost；锚点共用
// TAB_MORE_MENU_ANCHOR_ID——两页签 ⋯ 热区几何同源，见该常量注释）
export class AssistantTitleMenuHost extends AppMenuHost<AssistantTitleMenuCallbacks> {
  protected buildNode(uiContext: UIContext,
    callbacks: AssistantTitleMenuCallbacks): ComponentContent<AssistantTitleMenuCallbacks> {
    return new ComponentContent(uiContext, wrapBuilder(AssistantTitleMenuBuilder), callbacks,
      { nestingBuilderSupported: true });
  }

  open(uiContext: UIContext, callbacks: AssistantTitleMenuCallbacks, immersiveLevel: number): void {
    this.rebuild(uiContext, callbacks);
    this.show(uiContext, TAB_MORE_MENU_ANCHOR_ID,
      resolvedUiMaterial(uiMaterial.ImmersiveStyle.REGULAR, immersiveLevel, true));
  }
}
