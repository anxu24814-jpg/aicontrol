// 侧栏形态主区（2026-11-17 侧栏容器上根大改笔，自 DrawerShell.MainAreaHost 域级搬迁）：
// HdsNavigation navBar 内容区的对话本体——PageBackground 垫底 + ChatPage 主区常驻
//（换会话双交替重建）。职责一句话：drawer 形态主区的装配件。
// ★ 层级（2026-11-18 侧栏二级页化笔后）：自绘抽屉层（DrawerHost 根 Stack）已整族退役，
//   侧栏改为 ROUTE_SIDE_PANEL_PAGE 真 NavDestination——本件仍在 HdsNavigation 的 navBar
//   内容区常驻；侧栏页开态经官方路由压栈盖住本区（含标题栏覆盖层），关闭即弹页回主区。
// · 主区常驻（2207 真机回归修）：activeConvId 变化只改传参不重建 ChatPage——通用 .key()
//   官方定位是测试标识、不承担「换 key 即销毁重建」语义；@Watch 翻 chatSlotEven 双交替分支
//   = 旧实例销毁新实例创建（dshinhm Index.webPageSeq 先例）。同值重复点同一会话不触发。
// · 分享拉起 tick 不订阅：构造 ChatPage 时 AppStorage 现读一次；分享路由换 activeConvId
//   触发双交替重建 = 新实例构造重读，重建即携带新 tick（消费链 = ChatPageLifecycle 分享桥）。
// · 多选批量条 2026-11-17 迁回侧栏面板底部（2026-11-18 二级页化后随 DrawerSidePanel
//   页内自持）：主区不再挂任何浮层——侧栏页不在场时批量条随页不可见；多选真源在页内。
// · 背景会话页标记：sessionPage = 「背景仅用于会话页」开关生效，与二级对话页同语义；
//   渐显纪元 bump 由本 Stack onAppear 承接（主区无 NavDestination 壳，对齐 PageShell.onShown
//   时机；2208 消息区 onReShown 修在 ChatPage 内，与本件无关）。
// ★ homeMode 宿主契约边界（2026-11-17 侧栏导航架构收敛笔，方案档 §2.6——边界固化，不是
//   为本笔「架构好看」再做等价搬迁）：本件是 drawer 形态的常驻首页宿主，ChatPage 的
//   homeMode 分支与之对接，既有契约六项列此备查——
//   ①全高 Stack：`Stack({ alignContent: Alignment.Bottom })` 满幅，内容层 topPad 由内容
//     自行消费（外层不缩矮容器，2205/2206 真机两轮实证）；
//   ②@Prop 让位：topPad / bottomPad 均为 @Prop——冷启动异步晚到的状态栏/导航条真值必须
//     能穿透到内容层（2208 真机「更多菜单偏上」根因）；
//   ③挂载后 onReShown：主区无 NavDestination 壳，ChatPage 根 Stack `.onAppear` 调
//     `lifecycle.onReShown()` 承接显示到达（2208 消息区 opacity 恒 0 根因）；
//   ④官方标题栏命令桥：标题栏在 HomeNavigation stackBuilder 插槽（DrawerHomeTitleBar），
//     开抽屉/开模型/开更多经命令键下行，本件不持标题栏；
//   ⑤双交替重建：换会话由 @Watch 翻 chatSlotEven 分支销毁重建（2207 真机「只换标题不换
//     正文」根因；通用 .key() 不承担换键重建语义）；
//   ⑥PageBackground 显示纪元：本件背景带 sessionPage 标记，壁纸渐显由挂载 bump 驱动。
//   后续修改若触及以上任一项，一律在本件与 ChatPage 两端既有接口对接，**不得另建
//   HomeChatShell / HomeChatController 等第三层包装**（方案档 §2.6 明令）。
import { PageBackground, bumpBgShownEpoch } from '../../common/PageBackground';
import { ChatPage } from '../chat/ChatPage';
import { PENDING_SHARES_TICK_KEY } from '../../common/AppBroadcastKeys';

@Component
export struct DrawerMainArea {
  // 主区当前会话 id（真源 = HomeNavigation @State；@Link 回连——面板点会话 / 新建 /
  // 「更多」菜单新建由本链路写回，@Watch 翻双交替分支重建换会话）
  @Link @Watch('onActiveConvChanged') activeConvId: string;
  // 本地新造会话标记（2026-11-18 乐观空态笔）：真源 = HomeNavigation（activeConvId ===
  // freshConvId），@Prop 下传 ChatPage——主区常驻初建即需该值，@Link/@Watch 通道不必
  //（换会话走双交替重建，构造即读新值）
  @Prop freshSession: boolean = false;
  // 顶部让位（vp，HomeNavigation 下发 = titleBarInset 口径〔状态栏 + MINI 标题栏 + 蒙层下延〕
  //——主区仍在 HdsNavigation navBar 内容区，标题栏覆盖层与渐变蒙层仍在其上，让位口径不变）
  @Prop topPad: number = 0;
  // 底部留白（vp，HomeNavigation 下发 = 避让区高——输入栏避让手势条）
  @Prop bottomPad: number = 0;
  // 官方路由栈（HomeNavigation 注入同一实例——主区 ChatPage 二级页共用）
  pathStack: NavPathStack = new NavPathStack();
  // 主区「更多」菜单新建会话上行（2026-11-18 乐观空态笔）：新 id 由 ChatPage 菜单域本地
  // 生成，新造标记只有同一生成者可打——本件不再直写 @Link，改经 HomeNavigation 统一
  // 「先 mark 再写 activeConvId」（顺序红线：反序会让重建出的 ChatPage 读到 false，
  // 而普通成员构造后不再重读，空态先行永久失效）
  onFreshSession: (newId: string) => void = () => {
  };
  // （多选批量条 2026-11-17 迁回侧栏面板底部：本件不再持多选域参数——主区只负责会话本体，
  //  批量条随面板开合显隐，输入栏上方不再出现悬空条）
  // 主区双交替分支（2207 真机回归修；机制见件头注释）
  @State private chatSlotEven: boolean = true;

  // 主区会话换轨（@Link 值变化驱动双交替分支翻面）
  private onActiveConvChanged(): void {
    this.chatSlotEven = !this.chatSlotEven;
  }

  // 主区 ChatPage 装配（双交替分支的共同内容——分支翻面即整件销毁重建）
  @Builder
  ChatPageHost() {
    ChatPage({
      conversationId: this.activeConvId,
      homeMode: true,
      freshSession: this.freshSession,
      topPad: this.topPad,
      bottomPad: this.bottomPad,
      pathStack: this.pathStack,
      shareTick: AppStorage.get<number>(PENDING_SHARES_TICK_KEY) ?? 0,
      onHomeNewSession: (newId: string): void => {
        // 主区「更多」菜单首项「新建会话」——上抛 HomeNavigation：先打新造标记再换
        // activeConvId（顺序红线见 onFreshSession 成员注释）
        this.onFreshSession(newId);
      }
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 主区背景垫底（sessionPage 标记见件头注释）
      PageBackground({ sessionPage: true })
      if (this.chatSlotEven) {
        this.ChatPageHost()
      } else {
        this.ChatPageHost()
      }
    }
    .width('100%')
    .height('100%')
    // 背景显示纪元 bump（对齐 PageShell.onShown：sessionPage 实例壁纸渐显；挂载顺序保证
    // 先于本回调完成订阅）
    .onAppear((): void => {
      bumpBgShownEpoch();
    })
  }
}
