// 侧栏形态首页标题栏覆盖层（2026-11-17 侧栏形态对齐二级对话页笔新建）：挂官方 HdsNavigation
// 标题栏 stackBuilder 插槽（HomeNavigation.DrawerTitleBarOverlay 组件内 @Builder 装配——坑30
// 死规矩：官方 titleBar napi 直调 builder，全局 @Builder 无视图上下文启动即闪退），把侧栏形态
// 主区标题栏与 tabs 形态 / 二级对话页对齐到同一机制——键在官方生效区内出材质光圈，取代真机
// 修复二的「蒙层下缘自绘行 + flatKeys 实底档」取舍（该档随本笔整档退役，覆盖层 flatKeys 参数
// 一并删除）。
// · 结构 = ChatTitleBarOverlay 原件全量复用（showSidebarKey 汉堡键 + 两态中央区 + 更多键）：
//   左端汉堡键即原二级对话页返回键位（TITLE_BAR_EDGE_INSET），点击开侧栏会话二级页
//   （2026-11-18 二级页化笔：SIDE_DRAWER_TOGGLE_CMD_KEY 下行 HomeNavigation 栈空时 push
//   ROUTE_SIDE_PANEL_PAGE；侧栏页压栈后盖住本覆盖层，汉堡键只在首页位可见）。
// · 跨层桥（覆盖层装配在 HomeNavigation 栈层、页面态真源在 ChatPage @State，分居两层不可
//   @Link 直连——广播键是项目既有跨层正解）：
//   ① 思考档位 CHAT_THINKING_VALUE_KEY 双向镜像——页面 @Watch 发布 → 本件 @StorageProp 订阅
//      同步 → 覆盖层菜单；菜单落值 → 本件发布 → 页面 @Watch 消费回真源。双端同值守卫，收敛
//      无环（换会话由新页面实例初值发布复位，上一会话档位不泄漏）。
//   ② 思考交互期 CHAT_THINKING_HOLD_KEY 单向下行——菜单开合/按压上报写键，页面 @Watch 消费
//      回 thinkingHold @State（既有 @Link 三级链下发 ChatInputBar 收起守卫契约不变）。
//   ③ 动作命令键三条（一次性计数器，勿持久化）下行——消费方 = HomeNavigation（开抽屉）与
//      ChatPage（开模型面板 / 开更多菜单；更多菜单编程式 openMenu 锚点在 ChatPageContent，
//      弹出位与触发键位置解耦）。drawer 覆盖层与二级页形态 ChatPage 恒不同时在场（drawer
//      形态无二级对话页 push 面），命令键无跨形态误触面。
// · 为何单独成件（反碎片下限②申报）：本件是侧栏首页标题域的广播/命令桥装配层——并入
//   HomeNavigation 会让分发器持有 chat 域思考态 shim（分发器瘦身体裁冲突）；并入
//   ChatTitleBarOverlay 会把 drawer 桥机制耦合进二级页共用件（其 @Link 直连页面的现行契约
//   不动）。
import { ChatTitleBarOverlay } from '../chat/ChatTitleBarOverlay';
import { CHAT_THINKING_HOLD_KEY, CHAT_THINKING_VALUE_KEY } from '../chat/ChatParamChipBar';

// ── 动作命令与显隐键（命令键一次性计数器勿持久化；本件是唯一写点，消费方与语义见各键注释）──
// 开侧栏页命令（消费方 = HomeNavigation @StorageProp @Watch → 栈空时 push
// ROUTE_SIDE_PANEL_PAGE；侧栏页开态盖住按键，首页位点键开页。★ 2026-11-18 二级页化笔：
// 原「取反显隐」语义随自绘抽屉退役——侧栏关闭统一走页面出场，键只管开）
export const SIDE_DRAWER_TOGGLE_CMD_KEY: string = 'sideDrawerToggleCmd';
// （原抽屉显隐共享键 SIDE_DRAWER_VISIBLE_KEY 及其读写入口已随 2026-11-18 侧栏二级页化笔
// 与 DrawerVisibility.ets 整件退役——显隐由 NavPathStack 栈位承载，无第二存储）
// 开模型选择面板命令（消费方 = ChatPage @StorageProp @Watch → sheetCtrl.openModel）
export const CHAT_HOME_OPEN_MODEL_CMD_KEY: string = 'chatHomeOpenModelCmd';
// 开更多菜单命令（消费方 = ChatPage @StorageProp @Watch → openMoreMenu——编程式 openMenu，
// 弹出锚点在 ChatPageContent 顶部右缘，与触发键所在层级无关）
export const CHAT_HOME_MORE_CMD_KEY: string = 'chatHomeMoreCmd';

// 命令键自增（一次性计数器语义：@Watch 对同值不触发，递增保证每次点击都到达）
function bumpHomeCmd(key: string): void {
  AppStorage.setOrCreate<number>(key, (AppStorage.get<number>(key) ?? 0) + 1);
}

@Component
export struct DrawerHomeTitleBar {
  // 思考档位镜像（@StorageProp 订阅键 → 本地 @State 喂覆盖层 @Link；菜单落值经 @Link 写回
  // 本地 @State、@Watch 发布回键——双向桥，双端同值守卫收敛无环）
  @StorageProp(CHAT_THINKING_VALUE_KEY) @Watch('syncThinkingIn') keyThinkingValue: string = '';
  @State @Watch('publishThinkingValue') thinkingValue: string = '';
  // 思考键交互期（覆盖层菜单开合/按压经 @Link 写回本地 → @Watch 发布键下行页面；本件不消费键）
  @State @Watch('publishThinkingHold') thinkingHold: boolean = false;

  aboutToAppear(): void {
    // 初值采纳（键可能残留上一形态/上一会话档位——页面实例的初值发布随后到达即收敛）；
    // 交互期清残留（挂载即 false——菜单只在覆盖层在场时开合，残留 true 会卡输入栏收起守卫）
    this.thinkingValue = AppStorage.get<string>(CHAT_THINKING_VALUE_KEY) ?? '';
    AppStorage.setOrCreate<boolean>(CHAT_THINKING_HOLD_KEY, false);
  }

  // 键 → 本地（页面发布驱动覆盖层刷新；同值不写防回环）
  private syncThinkingIn(): void {
    if (this.keyThinkingValue !== this.thinkingValue) {
      this.thinkingValue = this.keyThinkingValue;
    }
  }

  // 本地 → 键（菜单落值与键同步两种来路共用——键来路时同值守卫拦下，零回写）
  private publishThinkingValue(): void {
    if (AppStorage.get<string>(CHAT_THINKING_VALUE_KEY) !== this.thinkingValue) {
      AppStorage.setOrCreate<string>(CHAT_THINKING_VALUE_KEY, this.thinkingValue);
    }
  }

  private publishThinkingHold(): void {
    AppStorage.setOrCreate<boolean>(CHAT_THINKING_HOLD_KEY, this.thinkingHold);
  }

  build() {
    // 官方生效区内挂载：键走沉浸光感材质档，与 tabs 形态覆盖层同观感；
    // 汉堡键/模型/更多三动作全走命令键下行（见头注释③）
    ChatTitleBarOverlay({
      thinkingValue: $thinkingValue,
      thinkingHold: $thinkingHold,
      showSidebarKey: true,
      onOpenSidebar: (): void => {
        bumpHomeCmd(SIDE_DRAWER_TOGGLE_CMD_KEY);
      },
      onOpenModel: (): void => {
        bumpHomeCmd(CHAT_HOME_OPEN_MODEL_CMD_KEY);
      },
      onOpenMoreMenu: (): void => {
        bumpHomeCmd(CHAT_HOME_MORE_CMD_KEY);
      }
    })
  }
}
