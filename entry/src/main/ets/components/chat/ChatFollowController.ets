// 流式滚动跟随控制器（2026-08-28 二三四改，方案 A——调研四要素落地，见
// docs/kimi重写/开源参考与渲染选型.md 流式滚动节）：业界标准 = 贴底才跟随 /
// 用户上拉即停 / 发送等动作强制到底。本类为纯逻辑，不持组件引用（仅构造传入
// Scroller），页面级生命周期（随页面创建销毁）。★ 2026-09-09 回顶/回底悬浮键全面退役
//（决明指令）——本类只删了为该键服务的 isFollowing() 查询口，跟随状态机
//（following/maybeFollow/forceToBottom/校正链）一行未动。
// ★ 2026-09-02 偏好开关「流式输出自动跟随」：maybeFollow（流式增量自动滚底的唯一通道，
// 两引擎共用）首行现读 isStreamAutoFollow——关 = 增量不自动滚（需重新开启开关才恢复）；
// 只拦自动滚，forceToBottom（发送等手动动作）不受开关影响；AppStorage 现读 =
// 切换即时生效；默认开 = 现状行为零回归。
// 消费方：ChatPageContent（手势方向置停 / onTouch 触摸闸 / onReachEnd 恢复 /
// onScrollIndex 进页校正喂入）、ChatSendCtrl（流式增量跟随 maybeFollow /
// 发送强制 forceToBottom）与 ChatPageLoad（初始载入 jumpToBottomAt——2026-09-06 进页
// 滚底直达，见方法注释）——独立类避免组件间反向依赖。状态变化不驱动 UI。
// ★ 2026-09-04 触摸闸：onListTouchStart/End（onTouch Down 与 Up/Cancel 喂入）——手指
// 在屏期间 maybeFollow 一律熄火（Cube ChatScrollUiFlow onScrollStart 释放同思路最小化）；
// 被闸拦下的增量记 pendingFollow，松手仅在有真被压住的增量时才补滚一次（★ 2026-09-06
// 修复：原松手无条件补滚 scrollEdge 瞬移——非流式纯浏览松手（following 未被方向闸清时）
// 也被强吸到底，瞬移与松手残余惯性/边缘回弹互抢 = 「松手跳动一下、末条被输入栏挡一截」
// 根因；RikkaHub 同口径 = 跟随仅「贴底 + 流式中 + 未拖拽」三条件触发，松手不主动吸底）。
// ★ 2026-09-06 进页定位校正链：jumpToBottomAt 记录待校正下标，List onScrollIndex 事件
// 驱动逼近收敛（rebuild 同帧 LazyForEach 未布局完成时 scrollToIndex 按已布局内容估算
// 落点偏上；Cube scrollToIndexWithStabilization 校正循环同思路的事件驱动最小化——零定时器
// 零人为延时，P1-3）。★ 同日二稿（「进旧会话停在中间偏下」真机实锤）：初版「末条入视口
// + 一次终校即消费」收敛过早——contentEndOffset（浮层实测高，chips 行晚到变高）漂移与
// 内容原地长高无 onScrollIndex 回调 = 收敛后无自愈；二稿 = 偏移级 isAtEnd 到位判据 +
// 待校正态常驻 + onContentShift 钩子重校。★ 同日三稿（「拉完松手跳回原地、反复才到底」
// +「有的进页仍不在底」真机实锤）：用户任意方向拖拽即取消校正链（原朝底拖拽不取消，
// 惯性滑行期被 scrollToIndex 打断跳回估算落点）+ 逼近计数改无进展才计数。★ 同日四稿
//（决明拍板「移植 Cube」——本地仓 cubeagent-stream-test 机制移植，非整搬：873 行
// ChatScrollUiFlow 的 28 依赖注入状态机与 setTimeout 群违反 P1-3 不搬，只取治「估算
// 落点偏上」两核心机制事件驱动化）：①进底预加载跳（jumpToBottomAt 先跳到末条前 3 条
// 强制 LazyForEach 实测尾部项，估算变实测——Cube scrollNearBottomEdgeForPreload 同值
// 移植）；②项级实测上报（消息项 onAreaChange 0.5vp 去抖喂 onItemAreaChange，内容原地
// 长高精确触发重校——Cube handleMessageItemAreaChanged 同思路，替换三稿 onReachEnd
// 猜测通道），详见 jumpToBottomAt/onItemAreaChange 注释。
// ★ 二三四改前 = ChatWsBridge 每帧无条件 scrollEdge(Edge.Bottom)：与用户手势打架
// （「很难拉到最新处」）+ 高频拽底与内容长高互相放大（「闪动抽搐」）。
import { isStreamAutoFollow } from '../../common/AppPreferences';

const FOLLOW_THROTTLE_MS: number = 80;
// 进页定位校正逼近重试上限（Cube INDEXED_SCROLL_CORRECTION_MAX_COUNT=8 同值；布局充分后
// end 单调逼近目标，正常 1~2 次即收敛，上限仅防极端布局异常死循环）
const INITIAL_ALIGN_MAX_ATTEMPTS: number = 8;
// 进底预加载项数（2026-09-06 四稿，Cube BOTTOM_EDGE_PRELOAD_ITEM_COUNT=3 同值移植）：
// 先跳到末条前 N 条强制尾部真实布局，END 对齐时尾部高度已实测不吃估算偏差
const INITIAL_ALIGN_PRELOAD_ITEMS: number = 3;
// 项高去抖阈值（vp，Cube handleMessageItemAreaChanged 0.5 同值移植——小于此的高度抖动
// 视为布局噪声不重校）
const ITEM_HEIGHT_DEBOUNCE_VP: number = 0.5;

export class ChatFollowController {
  private scroller: Scroller;
  // 跟随意图（true = 用户在底部附近，流式增量跟随滚动；手势上拉即 false）
  private following: boolean = true;
  // 上次跟随滚动时刻（节流：高频流式帧合并滚动调用，省布局成本——Open WebUI rAF
  // 批处理同思路；80ms 内的帧丢滚动无害，下一帧补齐贴底）
  private lastAt: number = 0;
  // 触摸闸（2026-09-04 手感修复，Cube ChatScrollUiFlow「onScrollStart 一触摸即释放程序
  // 跟随」同思路最小化）：手指在屏期间 maybeFollow 程序滚动链一律熄火——不等首帧位移
  //（>2vp 才停跟随的方向闸拦不住「按住停惯性→立刻下滑」窗口内的 scrollEdge 点火）
  private touchActive: boolean = false;
  // 触摸期间被触摸闸拦下的待补增量标记（2026-09-06）：true = 有尾部增量真被压住，松手
  // 凭它补滚一次；false = 无增量可补，松手不滚（治非流式浏览松手瞬移吸底跳动——
  // 松手补滚从「无条件」收紧为「按需」，见 onListTouchEnd）
  private pendingFollow: boolean = false;
  // ── 进页定位校正态（2026-09-06 校正链；同日二稿——到位后不主动消费、待校正态常驻
  // 至取消点，布局晚长由 onContentShift 钩子重校，详见 onScrollIndex 注释；常态
  // pendingAlignIndex=-1，onScrollIndex/onContentShift 首行直返零开销）──
  // 待校正目标列表项下标
  private pendingAlignIndex: number = -1;
  // 逼近重试计数（上限 INITIAL_ALIGN_MAX_ATTEMPTS）
  private alignAttempts: number = 0;
  // 上次校正事件的末个可见下标（2026-09-06 三稿，逼近进度判据——end 有推进即清
  // attempts，仅「连续无进展重试」计数；防进页布局事件密集但推进正常时被上限误杀
  // 悬挂中间位）
  private lastAlignEnd: number = -1;
  // 项高基线表（2026-09-06 四稿，项级实测上报的去抖基线——消息 id → 上次实测高 vp；
  // 寿命与 pendingAlignIndex 成对：jumpToBottomAt 建档时清、各取消点经 clearPendingAlign
  // 清，数据有界不跨会话残留）
  private itemHeights: Map<string, number> = new Map();
  // 输入框交互闸（2026-09-09 二修之三）：展开/收起期间浮层高度变化会经 onContentShift
  // 触发重校——用户正在操作输入栏，此时把列表无动画拽到底（尤其用户在看历史时）极突兀。
  // 合闸 = 校正链暂停（待校正态保留，开闸后由后续事件续校）；与 touchActive 同族
  //（用户交互优先于程序滚动）
  private hold: boolean = false;

  constructor(scroller: Scroller) {
    this.scroller = scroller;
  }

  // 闸门控制（ChatPageContent 经 ChatInputBar.onExpandState 喂入：展开即合闸，收起动画
  // 结束才开闸——收起动画期间浮层高度仍在变化，同属交互窗口）
  setHold(on: boolean): void {
    this.hold = on;
  }

  // 用户翻看历史（ChatPageContent onTouch Move **手指下移**判定——触摸滚动语义：
  // 手指下移 = offset 减小往回翻历史，二三四改代码方向写反、二三六改修正）：立即停跟随；
  // 并进页定位校正一并取消（手势优先——用户上手翻历史即不再拽底，2026-09-06 校正链）
  onUserScrollUp(): void {
    this.following = false;
    this.clearPendingAlign();
  }

  // 手指按下（ChatPageContent onTouch Down 喂入）：触摸闸合闸，程序滚动链即刻熄火
  onListTouchStart(): void {
    this.touchActive = true;
  }

  // 手指抬起/取消（onTouch Up/Cancel 喂入）：触摸闸开闸；仅触摸期间真被闸拦下过增量
  //（pendingFollow）才清零节流补滚一次——吃掉被压住的尾部增量（maybeFollow 内
  // following/偏好/触摸闸三连判，不在跟随态零副作用）。★ 2026-09-06 修复：原无条件
  // 补滚在非流式纯浏览松手时也瞬移吸底（手指上移朝最新方向翻 following 保持 true），
  // 与松手残余惯性/边缘回弹互抢 = 「跳动一下 + 末条被输入栏浮层挡一截」；现无增量
  // 可补即不滚（RikkaHub「松手后不主动吸底」同口径）
  onListTouchEnd(): void {
    this.touchActive = false;
    if (!this.pendingFollow) {
      return;
    }
    this.pendingFollow = false;
    this.lastAt = 0;
    this.maybeFollow();
  }

  // 滚动到达底部（List.onReachEnd，含用户回拉到底与代码滚底）：恢复跟随。
  // ★「真到底」闸在调用点（ChatPageContent onReachEnd 内 isAtEnd 现读）——官方事件在
  // 末项露头即触发，未闸会提前恢复跟随、被流式增量拽底打断用户手势（2026-09-04 滚动修复）
  onReachEnd(): void {
    this.following = true;
  }

  // 强制滚底（发送消息/重试等用户主动动作；重置跟随意图；进页待校正一并取消——
  // 发送追加新消息后旧目标下标已非末条，2026-09-06 二稿）
  forceToBottom(): void {
    this.following = true;
    this.clearPendingAlign();
    this.lastAt = Date.now();
    this.scroll();
  }

  // 取消进页待校正（用户任意方向拖拽让位手势〔ChatPageContent onTouch 两向均调——
  // 朝底向不经 onUserScrollUp，须本方法〕/触顶翻页 prepend 头部前插下标平移失真；
  // 2026-09-06 二稿立、三稿扩至朝底拖拽——「拉完松手跳回原地」根修见 onScrollIndex 注释）
  cancelAlign(): void {
    this.clearPendingAlign();
  }

  // 待校正态清理（2026-09-06 四稿提取——下标复位 + 项高基线表清空成对，防上会话
  // 基线串味；所有取消点统一走此）
  private clearPendingAlign(): void {
    this.pendingAlignIndex = -1;
    this.itemHeights.clear();
  }

  // 进页初始定位（2026-09-06 会话进入加载体验优化）：历史回放重建后无动画直达底部末条。
  // 替代原 forceToBottom（scrollEdge）的两个缺陷面——①LazyForEach 未布局完成时只滚到
  // 已布局内容的底，后续项陆续布局后位置漂移 = 「先见顶部旧消息再跳滚到底」中间态；
  // ②布局竞态下 scrollEdge 可能抛异常被静默吞掉停在顶部。scrollToIndex(末条, false,
  // ScrollAlign.END) 依据（本地 scroll.d.ts + 线上官方 List 参考页双覆盖）：END 对齐
  // 计入 contentEndOffset——末条对齐到 contentEndOffset 位置（本列表 = 输入栏浮层实测
  // 高），静止位与原语义一致末条不被输入栏遮；smooth=false 无动画直达；官方要求
  // 「LazyForEach 数据刷新完成后调用」——调用链在 notifyReload（onDataReloaded 同步
  // 投递）之后，满足。下标 = messageCount-1：rebuild 后 olderAttempted=false，
  // 头部提示行不挂载（ChatPageContent 挂载条件；rebuildFromHistory 复位翻页态，
  // refreshPage 复用本链同口径），LazyForEach 数据位与列表项一一对齐。
  // ★ 2026-09-06 校正链启用（原「备选方案」转正——真机实锤「进旧会话停在中间偏下」）：
  // rebuild 同帧 LazyForEach 未布局完成，scrollToIndex 按已布局内容估算落点偏上——
  // 记录 pendingAlignIndex 待校正，列表 onScrollIndex 事件驱动逼近收敛（见 onScrollIndex
  // 方法注释）；首调落空（坑63 族未绑定/竞态）也由校正链兜底，故异常只静默不清待校正态
  jumpToBottomAt(index: number): void {
    this.following = true;
    if (index < 0) {
      // 空会话（新会话/隐私/空历史回放空表）无消息项不定位——待校正态一并复位
      //（上会话悬挂值对本会话 = 越界下标，scrollToIndex 越界不滚空耗 attempts 到上限；
      // 自检域 2 发现，生命周期成对：记录/复位同点对称）
      this.clearPendingAlign();
      return;
    }
    this.pendingAlignIndex = index;
    this.alignAttempts = 0;
    this.lastAlignEnd = -1;
    this.itemHeights.clear();
    this.lastAt = Date.now();
    // ★ 2026-09-06 四稿预加载跳（Cube scrollNearBottomEdgeForPreload 机制移植）：
    // 先跳到末条前 3 条强制 LazyForEach 把尾部项真实布局出来——尾部高度从估算变实测，
    // 随后的 END 对齐不吃估算偏差（「估算落点偏上」根修）。同帧不再直发 END 对齐——
    // 同帧二次 scrollToIndex 会覆盖预加载目标使其失效；预加载跳本身改变可见下标必触发
    // onScrollIndex，由校正链接力 END 对齐（事件驱动替代 Cube 的 50ms 定时，P1-3）。
    // 短会话（目标下标 ≤ 预加载项数）无需预加载直对齐；预加载抛异常（坑63 族）也直对齐兜底
    let preloadIssued: boolean = false;
    if (index > INITIAL_ALIGN_PRELOAD_ITEMS && !this.touchActive) {
      try {
        this.scroller.scrollToIndex(index - INITIAL_ALIGN_PRELOAD_ITEMS, false, ScrollAlign.START);
        preloadIssued = true;
      } catch (e) {
        // 坑63 族静默——走直对齐兜底
      }
    }
    if (!preloadIssued) {
      this.alignScroll(); // 首调落空（坑63 族未绑定/竞态）由校正链兜底，异常只静默不清待校正态
    }
  }

  // 进页定位校正链（2026-09-06 初版，同日二稿修「进旧会话停在中间偏下」——初版收敛
  // 判据 end>=target（末条入视口）+ 一次终校即消费，「可见≠到底」：终校时浮层实测高
  //（contentEndOffset，chips 行随连接解析晚到变高）未稳则 END 对齐基准偏小，链消费后
  // 浮层长高、末条下沉被遮；且 onScrollIndex 只在可见下标变化时触发，内容原地长高无
  // 回调 = 收敛后无自愈，与浮层时序竞态凑巧才正常 = 间歇性根因）。二稿判据 = end>=target
  // 且偏移级 isAtEnd() 现读（scroll.d.ts「scrolled to the end position」= 含
  // contentEndOffset 的最大偏移，ChatPageContent.isAtEndSafe 同口径）；到位不主动
  // 消费——待校正态常驻，布局漂移由 onContentShift 钩子（浮层 onAreaChange）重校自愈，
  // 取消点 = 手势翻历史（onUserScrollUp）/发送（forceToBottom）/触顶翻页
  //（prepend 处 cancelAlign）。★ 同日三稿（决明真机再报「拉完松手跳回原地、重复两三遍
  // 才到底」）：进页未到底时用户自主往底拉（手指上移）原不取消待校正态——松手后惯性
  // 滑行期间 touchActive 已 false，每个 onScrollIndex 回调见 !isAtEnd 即 scrollToIndex
  // 无动画打断惯性、跳回未稳布局的估算落点 = 跳回原地，布局量准前反复 = 真机根因；
  // 三稿 = 用户任意方向拖拽即取消进页校正（手势让位，见 ChatPageContent onTouch），
  // 逼近计数改「end 有推进清零、仅连续无进展计数」。★ 同日四稿（Cube 机制移植）：
  // jumpToBottomAt 预加载跳把尾部项估算变实测（「估算落点偏上」根修）+ 项级实测上报
  // onItemAreaChange 替换三稿 onReachEnd 猜测通道（覆盖消息项异步长高但可见下标不变、
  // onScrollIndex 无回调的悬挂盲区）。事件驱动零定时器（P1-3）；常态
  // pendingAlignIndex=-1 首行直返（滚动高频回调零开销）
  onScrollIndex(end: number): void {
    if (this.pendingAlignIndex < 0) {
      return;
    }
    if (end >= this.pendingAlignIndex && this.isAtEndSafe()) {
      return; // 真到底 = 到位；不消费（晚长由 onContentShift/onItemAreaChange 重校）
    }
    if (end > this.lastAlignEnd) {
      // 布局推进中（末个可见下标前进）= 逼近正常，重试计数清零
      this.alignAttempts = 0;
      this.lastAlignEnd = end;
    } else {
      this.alignAttempts++;
      if (this.alignAttempts > INITIAL_ALIGN_MAX_ATTEMPTS) {
        this.clearPendingAlign(); // 连续无进展重试超上限放弃（极端布局异常兜底）
        return;
      }
    }
    this.alignScroll();
  }

  // 项级实测上报（2026-09-06 四稿，Cube handleMessageItemAreaChanged 机制移植——消息项
  // onAreaChange 喂入，0.5vp 去抖）：「末条已在视口、内容原地长高、可见下标不变」时
  // onScrollIndex 无回调，本通道是长高的**精确**触发源（替换三稿 onReachEnd 猜测通道）。
  // 首报只建档基线不重校（挂载初报非「长高」）；高度变化超阈值 = 内容真长 → 重对齐末条。
  // 待校正态取消（-1）首行直返零开销——常规滚动/流式期本回调空转成本可忽略
  onItemAreaChange(id: string, height: number): void {
    if (this.pendingAlignIndex < 0) {
      return;
    }
    const prev: number | undefined = this.itemHeights.get(id);
    if (prev !== undefined && Math.abs(height - prev) < ITEM_HEIGHT_DEBOUNCE_VP) {
      return;
    }
    this.itemHeights.set(id, height);
    if (prev === undefined) {
      return;
    }
    this.alignScroll();
  }

  // 内容布局位移钩子（2026-09-06 二稿）：浮层实测高回写（contentEndOffset 漂移）等
  // 「内容原地长高、可见下标不变」场景 onScrollIndex 无回调，由此通道补入——校正链
  // 存活期重对齐末条；链已取消（-1）首行直返零开销
  onContentShift(): void {
    if (this.pendingAlignIndex < 0) {
      return;
    }
    this.alignScroll();
  }

  // 校正重滚（逼近/漂移/项长高三通道共用）：触摸闸/输入框交互闸一致性——手指在屏或用户
  // 正在操作输入栏时不程序滚动（待校正态保留；用户拖拽即由 onTouch Move 取消链，轻点无
  // 位移则由 onScrollIndex/onItemAreaChange/onContentShift 通道续校）；坑63 族未绑定/竞态
  // 异常静默（待校正态保留，后续事件仍驱动重试；有界性 = 连续无进展 attempts 上限兜底）
  private alignScroll(): void {
    if (this.touchActive || this.hold) {
      return;
    }
    try {
      this.scroller.scrollToIndex(this.pendingAlignIndex, false, ScrollAlign.END);
    } catch (e) {
      // 静默（理由见上）
    }
  }

  // 偏移级在底现读（含 contentEndOffset；坑63 族异常按「不在底」处理——校正链宁重滚
  // 勿早收敛，ChatPageContent.isAtEndSafe 同口径）
  private isAtEndSafe(): boolean {
    try {
      return this.scroller.isAtEnd();
    } catch (e) {
      return false;
    }
  }

  // 流式增量跟随滚动（仅 following 且过节流闸才滚；★ 2026-09-02 偏好开关拦截：
  // isStreamAutoFollow 现读——关 = 增量不自动滚底，手动动作（forceToBottom）不受影响；
  // ★ 2026-09-04 触摸闸：手指在屏期间一律不滚——程序滚动与手势互抢的窗口整个掐灭；
  // 被拦增量记 pendingFollow（2026-09-06），松手由 onListTouchEnd 凭它按需补滚）
  maybeFollow(): void {
    if (!this.following) {
      return;
    }
    if (this.touchActive) {
      this.pendingFollow = true; // 增量被触摸闸压住——松手补滚凭据（2026-09-06）
      return;
    }
    if (!isStreamAutoFollow()) {
      return;
    }
    const now: number = Date.now();
    if (now - this.lastAt < FOLLOW_THROTTLE_MS) {
      return;
    }
    this.lastAt = now;
    this.scroll();
  }

  private scroll(): void {
    try {
      this.scroller.scrollEdge(Edge.Bottom);
    } catch (e) {
      // 坑63 族：Scroller 未绑定/竞态时滚动 API 可能抛 BusinessError——静默
      // （内容未变无补偿动作；跟随场景下一帧重试）
    }
  }
}
