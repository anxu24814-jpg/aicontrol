// 消息列表跟随与进页定位。正文完整提交后按已布局几何更新目标，单槽帧任务保留速度，
// 只用即时 scrollBy 推进位移；不依赖自然高度动画，也不重复启动原生 smooth 动画。
// 用户手势、偏好、输入闸与换代优先；进页/历史显式定位仍走原校正链。
// finish 期 450ms 收尾保持窗：迟到 Δh 由布局完成事件重锚承接。
import { isStreamAutoFollow } from '../../common/AppPreferences';
import { ChatFollowMotionState, ChatFollowMotionStep, advanceFollowMotion, initialFollowMotion }
  from '../../common/chat/ChatFollowMotion';
import { ChatFollowFeedback } from '../../common/chat/ChatFollowFeedback';
import { ChatScrollOwnership } from '../../common/chat/ChatScrollOwnership';
import { CHAT_STREAM_TRACE_ENABLED, ChatStreamTrace } from './ChatStreamTrace';
// ★ 进会话性能回归修复笔随施工打点（观测面，见 ChatEnterProbe 头注释）
import { markEnterProbe } from './ChatEnterProbe';
import { accessibility } from '@kit.AccessibilityKit';
import { FrameCallback, UIContext } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

export interface ChatFollowLayout {
  epoch: number;
  lastIndex: number;
  viewportHeight: number;
  endInset: number;
  // 触顶翻页在途（场景②超屏在顶修复笔）：beginRowPin 起钉闸守卫消费——必填非可选，
  // 编译器强制所有喂入点同步，防守卫静默失联成死判据
  olderLoading: boolean;
}

// 一次性下一帧任务；取消时清闭包，框架即使迟到调用也不再持有宿主。
class ChatFollowFrame extends FrameCallback {
  private action: ((time: number) => void) | null;

  constructor(action: (time: number) => void) { super(); this.action = action; }
  cancel(): void { this.action = null; }
  onFrame(time: number): void {
    const action: ((time: number) => void) | null = this.action;
    this.action = null;
    if (action !== null) { action(time); }
  }
}
// 进页定位校正逼近重试上限（Cube INDEXED_SCROLL_CORRECTION_MAX_COUNT=8 同值；布局充分后
// end 单调逼近目标，正常 1~2 次即收敛，上限仅防极端布局异常死循环）
const INITIAL_ALIGN_MAX_ATTEMPTS: number = 8;
// 进底预加载项数（Cube BOTTOM_EDGE_PRELOAD_ITEM_COUNT=3 同值移植）：先跳到末条前 N 条强制
// 尾部真实布局，END 对齐时尾部高度已实测不吃估算偏差
const INITIAL_ALIGN_PRELOAD_ITEMS: number = 3;
// 项高去抖阈值（vp，Cube 0.5 同值——小于此的高度抖动视为布局噪声不重校）
const ITEM_HEIGHT_DEBOUNCE_VP: number = 0.5;
// 展开局部锚校正（会话展开钉顶笔）：阈值同上；校正发数上限——钉位只在「翻 stackFromEnd
// 档位」与「首帧布局」两个瞬时窗口需要，三发足够覆盖且天然防与动画/用户滚动互相拉扯
//（超限即停，fail-safe 朝不动侧收敛）
const PIN_FIX_DEBOUNCE_VP: number = 0.5;
const PIN_FIX_LIMIT: number = 3;
// 收尾保持窗长（对标 KEL scroll_controller.dart 收尾保持窗）：finish 信号后窗内布局完成
// 事件重锚末条底边，吸收终态 replace 重解析大布局与「可信本轮耗时」行异步加入两股迟到 Δh
//（底部「收尾一跳 / 短一截」缺口）
const FINISH_ANCHOR_HOLD_MS: number = 450;
// U1b 释放底带（流式四症状修复轮）：末条底边距阅读线的余量 ≤ 带宽即视作「在底」（kelivo
// 56px ≈ 56vp 近似起点，真机校准；单位口径 = Flutter logical pixel ≈ vp，只当调参起点）。
// 带宽只在常量上单点调；真机判「没到底也恢复」过灵敏 → 单独 revert U1b 笔保留 U1a，零牵连
const RELEASE_BAND_VP: number = 56;
// 跳底时点戳限流上限（U0 观测面）：每实例最多打 8 行（随实例消亡，有界）；命中上限后静默零动作
const JUMP_STAMP_LIMIT: number = 8;

export class ChatFollowController {
  private scroller: Scroller;
  private ownership: ChatScrollOwnership = new ChatScrollOwnership();
  private releaseFrame: ChatFollowFrame | null = null;
  private gestureEpoch: number = -1;
  private ui: UIContext | null = null;
  private readLayout: (() => ChatFollowLayout) | null = null;
  private pendingFrame: ChatFollowFrame | null = null;
  private followEpoch: number = -1;
  private followRequested: boolean = false;
  // 仅索引定位有待布局目标；即时scrollBy不能靠回写估算总偏移来“取消”。
  private nativeTargetPending: boolean = false;
  private motion: ChatFollowMotionState = initialFollowMotion();
  private motionEnabled: boolean = false;
  private motionSubscription: ((enabled: boolean) => void) | null = null;
  private feedback: ChatFollowFeedback = new ChatFollowFeedback();
  private layoutSubscription: (() => void) | null = null;
  private pixelVp: number = 1;
  private lastVisibleIndex: number = -1;
  // 触摸期间被触摸闸拦下的待补增量标记：true = 有尾部增量真被压住，松手凭它补滚一次；
  // false = 无增量可补，松手不滚（松手补滚从「无条件」收紧为「按需」，见 onListTouchEnd）
  private pendingFollow: boolean = false;
  // 进页定位校正态：到位后常驻至取消点；已提交流式跟随接管时取消旧下标，避免两条定位链竞争。
  // 待校正目标列表项下标
  private pendingAlignIndex: number = -1;
  // ★「进页定位未收敛」标志（施工总案 S2）：进页校正存活期 = jumpToBottomAt 武装起、
  // 至收敛/放弃/取消止。与 pendingAlignIndex 严格区分：收敛后 pendingAlignIndex 常驻 ≥0
  //（供晚长 onContentShift/onItemAreaChange 自愈重校），本位即清——消费方
  //（ChatOlderCtrl.tryLoadOlder 第五守卫）只认本位，禁按字面 pendingAlignIndex ≥ 0 判断
  //（会把整个会话的触顶翻页全拦死）。置位唯一 = jumpToBottomAt（rearmAlignChain 手势重
  // 武装不经此、不置位——重武装非进页校正，不拦翻页）；清位 = onScrollIndex 收敛分支 +
  // clearPendingAlign 统一取消出口（手势接管/发送/翻页前插/重试放弃/detach 全覆盖）
  private entryAlignActive: boolean = false;
  // 逼近重试计数（上限 INITIAL_ALIGN_MAX_ATTEMPTS）
  private alignAttempts: number = 0;
  // 上次校正事件的末个可见下标（逼近进度判据——end 有推进即清 attempts，仅连续无进展计数；
  // 防布局事件密集但推进正常时被上限误杀悬挂中间位）
  private lastAlignEnd: number = -1;
  // 项高基线表（项级实测上报的去抖基线——消息 id → 上次实测高 vp；寿命与 pendingAlignIndex
  // 成对：jumpToBottomAt 建档时清、各取消点经 clearPendingAlign 清，数据有界不跨会话残留）
  private itemHeights: Map<string, number> = new Map();
  // 输入框交互闸：展开/收起期间浮层高度变化会经 onContentShift 触发重校——用户正在操作
  // 输入栏，此时把列表无动画拽到底极突兀。合闸 = 校正链暂停（待校正态保留，开闸后由后续
  // 事件续校）；与用户控制权同族（用户交互优先于程序滚动）。★ P3：闸与「持阅读位」判据
  // 对齐——hold 期仅当用户持阅读位（follow=false，在看历史）才拦；跟随时（在底）照常重钉
  //（真机收键盘不失焦时 hold 长期驻留，原「hold 即拦」把在底跟随态的键盘跟随也拦死；
  // 见 alignScroll 注释）
  private hold: boolean = false;
  // 底锚模式位（RIK 四笔笔二）：true = List stackFromEnd 布局底锚，贴底弹簧补偿链整体短路
  //（maybeFollow/scheduleFollow 入口早退——布局自身从底端起算，内容增长无跨帧补偿需求）；
  // 三类主动滚动照旧可达（用户回底恢复 release / 发送 forceToBottom / 进页 jumpToBottomAt
  // 校正链）；手势生命周期喂入与 trace 照旧。false（默认）= 旧路径逐字节保留（回退承诺）。
  // ★ 喂入随锚态动态（U4 失配修复）：CHAT_STACK_FROM_END_ENABLED && anchored，与 List 的
  // .stackFromEnd 表达式同拍同值——贴顶期（anchored=false）补偿链武装但天然空转，判据迟到
  // 窗由弹簧链兜住、不再零钉底
  private stackAnchored: boolean = false;

  // ── 展开局部锚（会话展开钉顶笔）──
  // 用户点过程段控制行 / 步骤详情展开或收起：把被点展示项的上沿钉在当前屏位，增量向下生长
  //（而非底锚的「底边不动、卡顶被推走」）。三个字段 = 几何位本体（钉哪一行、钉在哪个屏位、
  // 已校正几发）；渲染位（List 的 stackFromEnd 判据）在 ChatListAnchorJudge.rowPin，两处由
  // 页面同一入口原子同写。只短路跟随补偿链（maybeFollow/scheduleFollow 入口），**不改
  // ownership**——手势接管、发布层冻结门（userHoldsReadingPosition）、回底释放全按既有判据
  // 走，零第二套语义；清位三路 = 用户回底（页面 onReachEnd）/ 发送（sendWithHoldRelease）/
  // 换源（pinHeld 代次不符自清）+ detach 兜底
  private rowPinned: boolean = false;
  private pinIndex: number = -1;
  private pinTop: number = 0;
  private pinFixes: number = 0;
  // 起钉时的会话代次（readLayout().epoch）：换源/换会话后旧钉位自动失效（判据器 reset 已清
  // 渲染位，几何位由 pinHeld 首次消费时自清）
  private pinEpoch: number = -1;

  // 转场前静默位（掉帧期3 R1-a / 施工总案 U16）：pop 转场开始即置真——scheduleFollow 入口
  // 停排帧（在途待发帧同拍取消、弹簧运动停摆），但**不解绑不释放**：订阅（motion/layout）、
  // ownership、待校正态与跟随意图（followRequested/followEpoch）一律原样保留（禁以 detach
  // 替代——那是成对释放点），转场取消/页面回显由 resume 原样恢复。本件同时是该静默的
  //**单一来源位**：发布层揭示停拍（ChatStreamFlowCtrl.flushFrame）与页面组件帧驱动
  //（ChatPageContent）均经只读面/回调消费它，全链一个开关零第二套状态
  private silenced: boolean = false;
  // 静默态变更回调（页面组件帧驱动停/启接线用；null = 未登记/已解绑——销毁成对）
  private silenceListener: ((silenced: boolean) => void) | null = null;

  // U1 释放重评闩：release 评估失败（intent=towardEnd 而 reachedEnd/atEnd 双假——典型 =
  // 松手下一帧回弹在途 isAtEndSafe 读假）后本手势意图的受闩快照代次。生命周期有界：成功
  // 重放 / cancelRelease 全部既有取消点 / 代次不符 即清——不跨手势、不跨会话记忆，无定时器
  //（结构性有界：评估失败后 phase=idle，能让 isAtEndSafe 变真的只剩回弹沉降本身；发布冻结期
  // 内容不增长；程序滚动通道 forceToBottom/jumpToBottomAt 均先清闩）
  private releaseRetryEpoch: number = -1;

  private clearReleaseRetry(): void { this.releaseRetryEpoch = -1; }

  // ── 跳底时点戳族（U0 观测面——纯 hilog 零行为）：独立 hilog 行（同域同 tag
  // 'ChatEnterProbe'），不经 markEnterProbe 差分通道、不写其模块状态；打「绝对时点 + 与本窗
  // reveal 差分」——差分锚 = 最近一次 retargetAlignToTail 时点（该调用与暴露窗口完成步的
  // reveal 戳同一同步块，故 sinceRetarget ≈ 与本窗 reveal 的差分；无锚期打 -1）。限流 =
  // 实例普通计数成员，上限 JUMP_STAMP_LIMIT 行（随实例消亡，有界）。定位目标 = 完成步重钉
  //（retarget）后布局事件驱动 alignScroll vs stackFromEnd 底锚自身行为——读数侧按 abs 时点
  // 序列判读驱动事件
  private jumpStampCount: number = 0;
  private jumpStampRetargetMs: number = -1;

  private stampJumpEvent(kind: string): void {
    if (this.jumpStampCount >= JUMP_STAMP_LIMIT) {
      return;
    }
    this.jumpStampCount++;
    const now: number = Date.now();
    const sinceRetarget: number = this.jumpStampRetargetMs >= 0 ? now - this.jumpStampRetargetMs : -1;
    hilog.info(0xD5A0, 'ChatEnterProbe',
      'jump %{public}s abs=%{public}d sinceRetarget=%{public}d idx=%{public}d',
      kind, now, sinceRetarget, this.pendingAlignIndex);
  }

  constructor(scroller: Scroller) {
    this.scroller = scroller;
  }

  attach(ui: UIContext, readLayout: () => ChatFollowLayout): void {
    if (this.ui !== null) { this.detach(); }
    this.ui = ui;
    this.readLayout = readLayout;
    this.ownership.reset(true);
    this.bindMotionPreference();
    try {
      const pixelVp: number = ui.px2vp(1);
      if (Number.isFinite(pixelVp) && pixelVp > 0) { this.pixelVp = pixelVp; }
      const listener: () => void = (): void => {
        if (this.ui === ui && this.layoutSubscription === listener) {
          this.feedback.didLayout();
          this.retireNativeTarget();
          this.fixRowPin(); // 展开局部锚：翻档/首帧跳变在布局完成同拍吸收（未钉零动作）
          this.traceLayout();
          this.pumpFinishHold(); // 收尾保持窗内存活期重锚（笔五；窗外零动作）
        }
      };
      ui.getUIObserver().on('didLayout', listener);
      this.layoutSubscription = listener;
    } catch (error) {
      hilog.warn(0xD5A0, 'ChatFollow', '布局完成监听不可用，按实际滚动回报校准：%{public}s',
        (error as Error).message);
    }
  }

  private bindMotionPreference(): void {
    try {
      this.motionEnabled = !accessibility.isAnimationReduceEnabledSync();
      const listener: (enabled: boolean) => void = (enabled: boolean): void => {
        if (this.motionSubscription !== listener || this.ui === null) { return; }
        this.motionEnabled = !enabled;
        this.stopMotion();
        this.scheduleFollow();
      };
      accessibility.onAnimationReduceStateChange(listener);
      this.motionSubscription = listener;
    } catch (error) {
      this.motionEnabled = false;
      hilog.warn(0xD5A0, 'ChatFollow', '无法读取或监听减弱动态效果，按静态跟随：%{public}s',
        (error as Error).message);
    }
  }

  detach(): void {
    this.cancelFollow();
    this.endRowPin(); // 展开局部锚几何位成对清（渲染位由 anchorJudge.reset 清；离场不漏位）
    const listener: ((enabled: boolean) => void) | null = this.motionSubscription;
    this.motionSubscription = null;
    if (listener !== null) {
      try { accessibility.offAnimationReduceStateChange(listener); }
      catch (error) {
        hilog.warn(0xD5A0, 'ChatFollow', '减弱动态效果监听释放失败：%{public}s', (error as Error).message);
      }
    }
    const layoutListener: (() => void) | null = this.layoutSubscription;
    this.layoutSubscription = null;
    if (layoutListener !== null && this.ui !== null) {
      try { this.ui.getUIObserver().off('didLayout', layoutListener); }
      catch (error) {
        hilog.warn(0xD5A0, 'ChatFollow', '布局完成监听释放失败：%{public}s', (error as Error).message);
      }
    }
    this.motionEnabled = false;
    this.lastVisibleIndex = -1;
    this.cancelRelease();
    this.cancelFinishHold(); // 收尾保持窗定时器成对释放（笔五——内存与资源防线）
    this.ownership.reset(false);
    this.gestureEpoch = -1;
    this.ui = null;
    this.readLayout = null;
    this.hold = false;
    this.clearPendingAlign();
    ChatStreamTrace.dump('detach');
    ChatStreamTrace.release();
  }

  private cancelFrame(): void {
    this.pendingFrame?.cancel();
    this.pendingFrame = null;
  }

  private nativeTargetAtEnd(): boolean {
    if (this.readLayout === null) { return false; }
    const layout: ChatFollowLayout = this.readLayout();
    try {
      const tail: RectResult | null = layout.lastIndex >= 0 ? this.itemRect(layout.lastIndex) :
        { x: 0, y: 0, width: 0, height: 0 };
      return layout.viewportHeight > 0 && tail !== null && tail.height > 0 &&
        tail.y + tail.height <= layout.viewportHeight - layout.endInset + this.pixelVp && this.scroller.isAtEnd();
    } catch (_error) { return false; }
  }

  private retireNativeTarget(): void {
    if (this.nativeTargetPending && this.nativeTargetAtEnd()) { this.nativeTargetPending = false; }
  }

  private stopMotion(): void {
    this.retireNativeTarget();
    this.motion = initialFollowMotion();
    this.feedback.reset();
    ChatStreamTrace.cancel('motion-stop');
    if (!this.nativeTargetPending) { return; }
    this.nativeTargetPending = false;
    try {
      // 同拍读取与写回同一偏移。List.scrollTo还会清未布局的targetIndex，scrollBy(0,0)不会。
      const offset: OffsetResult = this.scroller.currentOffset();
      this.scroller.scrollTo({ xOffset: offset.xOffset, yOffset: offset.yOffset, animation: false });
    } catch (error) {
      hilog.warn(0xD5A0, 'ChatFollow', '跟随中断时列表尚不可用：%{public}s', (error as Error).message);
    }
  }

  private cancelFollow(): void {
    this.cancelFrame();
    this.stopMotion();
    this.followRequested = false;
    this.pendingFollow = false;
    this.followEpoch = -1;
  }

  onFollowPreferenceChanged(): void {
    if (!isStreamAutoFollow()) { this.cancelFollow(); }
  }

  // 底锚模式位喂入（★ U4 失配修复起随锚态动态调用）：语义见 stackAnchored 字段注释——
  // ChatPageContent 初值 + 每拍重评同拍喂入，本方法只落位零副作用（不清 pending 帧/意图，
  // 升格拍在途帧 remaining=0 自然静止、降格拍链无缝重武装）
  setStackAnchored(enabled: boolean): void {
    this.stackAnchored = enabled;
  }

  // ── 展开局部锚：起钉 / 换钉 / 释放 ──
  // listIndex = 被点展示项在 List 里的项位（头部提示行在场时已由数据源换算）；< 0 = 释放。
  // 起钉闸专用的「已无下方余量」现读（场景②超屏在顶修复笔）：isAtEnd 读失败按「在底」处理
  //（保守侧 = 不接管）。★ 与 isAtEndSafe（catch 按「不在底」= 宁重滚勿早收敛）catch 语义
  // 相反，勿混用/勿合并——两口的失败方向各自服务所在链的 fail-safe 侧，合并即制造单向缺陷。
  // catch 为防御性捕获（isAtEnd 无 @throws 标注，坑63 族静默惯例）
  private atEndForPinGate(): boolean {
    try { return this.scroller.isAtEnd(); }
    catch (_error) { return true; } // 防御性捕获：视为无余量，不接管
  }

  // 起钉三重判据（任一不成立即不接管 = 退回原向上生长行为）：
  // ① 顶部已滚出（yOffset > 0），或内容已越屏尚有余量（isAtEnd 为假）——区分『不可滚的 0』
  //    与『超屏在顶的 0』，后者翻档理论无缝；不可滚（内容不满屏）时上方还有余量可吸收，钉顶
  //    反而让 List 从「底对齐」翻成「顶对齐」，空出底部留白（短会话观感倒退）；② 该行已物化
  //    （实测矩形高 > 0）；③ 已接线（ui 在场）。起钉只记屏位不滚动——首次校正交给布局完成
  //    事件（fixRowPin），避免在点击帧里与「展示字段写入 + 200ms 高度动画」抢同一拍
  beginRowPin(listIndex: number): void {
    this.endRowPin();
    if (listIndex < 0 || this.ui === null) { return; }
    let offset: number = 0;
    try {
      offset = this.scroller.currentOffset().yOffset;
    } catch (_error) {
      return; // 未绑定 / 竞态：按「不接管」处理（坑63 族静默惯例）
    }
    if (!(offset > 0) && this.atEndForPinGate()) { return; }
    if (this.readLayout !== null && this.readLayout().olderLoading) { return; }
    // 触顶翻页在途（olderLoading）不起钉：头部提示行已挂载、加载完成 prepend 前插会使全部
    // 项位整体平移且不推进 epoch（epoch 写点仅 clear/rebuild/reanchor 三处）——此刻起钉 =
    // 钉位 index 错位不被代次自清捕获（fixRowPin 按错行校正 + ChatOlderCtrl.restoreAnchor
    // 主动滚动拽视口）。翻页落定后再点即正常接管
    const rect: RectResult | null = this.itemRect(listIndex);
    if (rect === null || rect.height <= 0) { return; }
    this.rowPinned = true;
    this.pinIndex = listIndex;
    this.pinTop = rect.y;
    this.pinFixes = 0;
    this.pinEpoch = this.readLayout !== null ? this.readLayout().epoch : -1;
  }

  endRowPin(): void {
    this.rowPinned = false;
    this.pinIndex = -1;
    this.pinTop = 0;
    this.pinFixes = 0;
    this.pinEpoch = -1;
  }

  // 钉位是否仍有效（换源 / 换会话后旧钉位自动作废，零第二处清理点）：代次不符即就地清位
  private pinHeld(): boolean {
    if (!this.rowPinned) { return false; }
    const epoch: number = this.readLayout !== null ? this.readLayout().epoch : -1;
    if (epoch !== this.pinEpoch) {
      this.endRowPin();
      return false;
    }
    return true;
  }

  // 只读透传（页面把同一事实写进 ChatListAnchorJudge.rowPin；消费面 = stackAnchored() 单源）
  isRowPinned(): boolean {
    return this.pinHeld();
  }

  // 钉位校正（两通道喂入：布局完成事件 + 被钉行长高回报）：只抵消「钉位行上沿的位移」。
  // 展开动画向下生长的部分 rect.y 恒定 → 天然零动作；真正被吸收的是翻 stackFromEnd 档位的
  // 瞬时跳变。发数有界（PIN_FIX_LIMIT），用户一旦滚动即由 onWillScroll 置满停校——程序
  // 绝不把用户拽回钉位（fail-safe 朝不动侧收敛）
  private fixRowPin(): void {
    if (!this.pinHeld() || this.pinFixes >= PIN_FIX_LIMIT) { return; }
    const rect: RectResult | null = this.itemRect(this.pinIndex);
    if (rect === null || rect.height <= 0) { return; }
    const delta: number = rect.y - this.pinTop;
    if (Math.abs(delta) < PIN_FIX_DEBOUNCE_VP) { return; }
    this.pinFixes++;
    try {
      this.scroller.scrollBy(0, delta);
    } catch (error) {
      hilog.warn(0xD5A0, 'ChatFollow', '钉位校正暂不可用：%{public}s', (error as Error).message);
    }
  }

  // ── 转场前静默（掉帧期3 R1-a / U16）：停帧驱动与弹簧运动但不解绑 ──
  // 静默（pop 转场开始调用）：在途待发帧取消 + 运动停摆（复用两既有私有出口，可见性不动）；
  // ownership/订阅/跟随意图全保留——静默只是停驱动，不是取消跟随（与 cancelFollow 的显式
  // 取消语义区分）
  silence(): void {
    this.silenced = true;
    this.cancelFrame();
    this.stopMotion();
    this.notifySilence(true);
  }

  // 解冻（解冻点 = onShown——坑25 可靠姿势：每次页面显示触发，含 pop 返回与转场取消回显）：
  // 清静默位 + 按保留的跟随意图续排（跟随意图未被静默清，续排即原样恢复；用户退跟态下
  // scheduleFollow 入口自守零动作）
  resume(): void {
    if (!this.silenced) {
      return;
    }
    this.silenced = false;
    this.notifySilence(false);
    this.scheduleFollow();
  }

  // 静默位只读透传（发布层揭示停拍判据消费——ChatStreamFlowCtrl.flushFrame，同
  // userHoldsReadingPosition 只读透传形制）
  isSilenced(): boolean {
    return this.silenced;
  }

  // 静默态变更回调登记（页面组件把自身帧驱动接线到静默开关；null = 解绑——销毁成对）
  setSilenceListener(listener: ((silenced: boolean) => void) | null): void {
    this.silenceListener = listener;
  }

  private notifySilence(on: boolean): void {
    const listener: ((silenced: boolean) => void) | null = this.silenceListener;
    if (listener !== null) {
      listener(on);
    }
  }

  // 用户持阅读位只读透传（RIK 四笔笔四，方案 §6 冻结门判据）：单源 = ChatScrollOwnership
  // 的 follow 标志（!isFollowing）——上滑拖过 2vp 死区（CHAT_DRAG_SLOP_VP，drag() 阈）退跟
  // 起真、滑回真底 release() 复跟止真；消费方 = ChatStreamFlowCtrl.flushFrame 发布层冻结门。
  // 勿在本件另设第二套判据或死区（轻点/亚阈触摸 follow 不退即不冻结，死区语义由既有 slop
  // 逻辑天然承接；注意与 userOwnsScroll「触摸/惯性瞬时占用」严格区分：回看位停稳后占用已
  // 释放而阅读位仍在——冻结判据取后者）
  userHoldsReadingPosition(): boolean {
    return !this.ownership.isFollowing();
  }

  // 输入栏交互闸只读透传（四症状修复轮 U4 守卫消费：hold 期锚评估推迟——输入栏展开期
  // 浮层几何在变，此刻翻 stackFromEnd 会拽动用户正盯着的输入区）
  isHold(): boolean {
    return this.hold;
  }

  // 进页定位未收敛只读透传（★ 施工总案 S2，照 isSilenced 只读透传形制）：置位/清位点见
  // entryAlignActive 字段注释；消费方 = ChatOlderCtrl.tryLoadOlder 第五守卫（进页待校正
  // 存活期触顶不发自动翻页链——杀重进被拽顶杀手链 H1 第 2 步：onReachStart 在列表
  // initialIndex=0 初始化即触发一次，list.d.ts 实锤）
  isEntryAlignActive(): boolean {
    return this.entryAlignActive;
  }

  // ── 收尾保持窗（RIK 四笔笔五，方案 §7）：finish 期 450ms 贴底保持 ──
  // 窗存活期内每个布局完成事件重锚末条底边（didLayout 监听经 pumpFinishHold 转发
  // scheduleFollow——复用其全部既有闸），窗终止由单个有界定时器释放（P1-3 允许必要定时器、
  // 禁轮询）；重复开窗 = 清旧定时器再立新期限（多轮收尾各持各窗）。底锚开态下 scheduleFollow
  // 入口短路 = 窗自然空转（双态共用一套实现，不按态分叉）；关态下本窗是收尾锚定的主保护
  private finishHoldUntil: number = -1;
  private finishHoldTimer: number = -1;

  // 开窗（done/error/stop 三路共用——接线单点 = ChatStreamFlowCtrl.finishStream 的
  // maybeFollow 旁）：窗只影响跟随锚定，不延迟落库与轮收尾时序；窗内用户手势优先
  //（手势清 followRequested 后泵自然静默，窗不得反向拽回）
  holdFinishAnchor(): void {
    if (this.ui === null) {
      return; // 未接线 / 已离场不开窗（detach 已成对清态）
    }
    this.cancelFinishHold();
    this.finishHoldUntil = Date.now() + FINISH_ANCHOR_HOLD_MS;
    this.finishHoldTimer = setTimeout((): void => {
      this.finishHoldTimer = -1;
      this.finishHoldUntil = -1;
    }, FINISH_ANCHOR_HOLD_MS);
  }

  private cancelFinishHold(): void {
    if (this.finishHoldTimer >= 0) {
      clearTimeout(this.finishHoldTimer);
      this.finishHoldTimer = -1;
    }
    this.finishHoldUntil = -1;
  }

  // 窗内布局事件重锚泵（didLayout 监听内调用）：窗存活期把每个布局完成当作一次收尾
  // 迟到 Δh 的补偿请求——不新增第二套滚动路径，一切闸门沿用 scheduleFollow 既有语义
  private pumpFinishHold(): void {
    if (this.finishHoldUntil >= 0 && Date.now() < this.finishHoldUntil) {
      this.scheduleFollow();
    }
  }

  // 闸门控制（ChatPageContent 经 ChatInputBar.onExpandState 喂入：展开即合闸，收起动画
  // 结束才开闸——收起动画期间浮层高度仍在变化，同属交互窗口）
  setHold(on: boolean): void {
    this.hold = on;
    if (on) {
      this.pendingFollow = this.pendingFollow || this.pendingFrame !== null || this.nativeTargetPending;
      this.cancelFrame();
      this.stopMotion();
    } else if (this.pendingFollow) {
      this.scheduleFollow();
    }
  }

  // 正文锚点等显式回看入口；与列表纵向拖动共享取消出口。
  onUserScrollUp(): void {
    this.ownership.reset(false);
    this.cancelRelease();
    this.cancelFollow();
    this.clearPendingAlign();
  }

  private traceLayout(): void {
    if (!CHAT_STREAM_TRACE_ENABLED || this.readLayout === null) { return; }
    const layout: ChatFollowLayout = this.readLayout();
    try {
      const tail: RectResult | null = layout.lastIndex >= 0 ? this.itemRect(layout.lastIndex) :
        { x: 0, y: 0, width: 0, height: 0 };
      const offset: number = this.scroller.currentOffset().yOffset;
      if (tail !== null) {
        ChatStreamTrace.geometry(tail.height, offset,
          offset + tail.y + tail.height - layout.viewportHeight + layout.endInset, this.motion.velocity,
          tail.y + tail.height, layout.viewportHeight);
      }
      ChatStreamTrace.frame(layout.epoch, this.ownership.phaseName(), this.ownership.isFollowing(),
        this.ownership.isTouching());
    } catch (error) {
      hilog.warn(0xD5A0, 'ChatFollow', '诊断布局尚不可读：%{public}s', (error as Error).message);
    }
  }

  private traceInput(event: string): void {
    if (!CHAT_STREAM_TRACE_ENABLED) { return; }
    ChatStreamTrace.input(event, this.ownership.phaseName(), this.ownership.isFollowing(),
      this.ownership.isTouching());
  }

  onListTouchStart(): void {
    if (!this.ownership.touchStart()) { return; }
    this.traceInput('down');
    this.gestureEpoch = this.readLayout?.().epoch ?? -1;
    this.cancelRelease();
    this.pendingFollow = this.pendingFollow || this.pendingFrame !== null || this.nativeTargetPending;
    this.cancelFrame();
    this.stopMotion();
  }

  onWillScroll(offset: number, _state: ScrollState, source: ScrollSource): ScrollResult {
    if (this.ownership.userOwnsScroll() &&
      (source === ScrollSource.SCROLLER || source === ScrollSource.SCROLLER_ANIMATION)) {
      return { offsetRemain: 0 };
    }
    if (source === ScrollSource.SCROLLER) { this.feedback.willScroll(offset, this.pixelVp); }
    // U1：非用户占用域的 EDGE_EFFECT 帧 = 回弹沉降至末端的天然信号源（P3 沉降信号并入的
    // 指定落点）——只喂重评泵，不改变下方手势分支「非用户占用整体跳过」的既有语义
    if (source === ScrollSource.EDGE_EFFECT && !this.ownership.userOwnsScroll()) {
      this.retryReleaseIfSettled();
    }
    const drag: boolean = source === ScrollSource.DRAG || source === ScrollSource.OTHER_USER_INPUT ||
      source === ScrollSource.SCROLL_BAR;
    // EDGE_EFFECT 只在用户占用域算惯性尾波（松手回弹）。跟随贴底域（owner=idle）它是内容
    // 增长/贴底对齐引发的系统尾波——真机轨迹实锤（RIK 三笔组D）：每批发布瞬时触底一次，
    // 尾波经本分支杀弹簧（stopMotion 归零 + 相位被拖入 moving 断回执流），底边超深滞留
    // 最长 685ms = 「气泡底边随文字高度变化」。故非用户占用时该来源整体跳过手势分支。
    const inertia: boolean = source === ScrollSource.FLING || source === ScrollSource.SCROLL_BAR_FLING ||
      (source === ScrollSource.EDGE_EFFECT && this.ownership.userOwnsScroll());
    if (Number.isFinite(offset) && Math.abs(offset) > 0.001 && (drag || inertia)) {
      // 展开局部锚：用户一动手就停钉位校正（钉位仍留着 = 仍不钉底，但程序不再按旧基准
      // 回拉——否则用户滑走后下一帧布局事件会把他拽回被点行）
      this.pinFixes = PIN_FIX_LIMIT;
      if (!this.ownership.userOwnsScroll()) { this.gestureEpoch = this.readLayout?.().epoch ?? -1; }
      if (drag) { this.ownership.drag(offset); }
      else { this.ownership.continueMotion(); }
      this.traceInput(drag ? 'drag' : 'inertia');
      this.clearPendingAlign();
      this.pendingFollow = this.pendingFollow || this.pendingFrame !== null || this.nativeTargetPending;
      this.cancelFrame();
      this.stopMotion();
      if (!this.ownership.isFollowing()) {
        this.followRequested = false;
        this.pendingFollow = false;
        this.followEpoch = -1;
      }
      this.cancelRelease();
    }
    return { offsetRemain: offset };
  }

  onListTouchEnd(cancelled: boolean = false): void {
    this.ownership.touchEnd(cancelled);
    this.traceInput(cancelled ? 'cancel' : 'up');
    if (cancelled) {
      this.cancelRelease();
      this.cancelFollow();
      this.clearPendingAlign();
      return;
    }
    if (this.ownership.needsRelease()) { this.scheduleRelease(); }
    else if (!this.ownership.userOwnsScroll() && this.pendingFollow) { this.scheduleFollow(); }
  }

  // 只有真实纵向用户动作才授予到底事实；位置回调本身不发滚动或改写原生惯性。
  onDidScroll(offset: number, _state: ScrollState): void {
    if (!Number.isFinite(offset)) { return; }
    this.recordUserEnd();
    this.retireNativeTarget();
    ChatStreamTrace.scrolled(offset);
    this.retryReleaseIfSettled(); // U1：回弹尾波帧在失败清态后 phase=idle 恰穿此区；泵自带占用守卫
    if (this.ownership.userOwnsScroll()) { return; }
    this.feedback.didScroll(offset);
  }

  onDidStopDragging(willFling: boolean): void {
    this.recordUserEnd();
    this.ownership.stopDragging(willFling);
    this.traceInput(willFling ? 'drag-end-fling' : 'drag-end');
    this.cancelRelease();
    if (this.ownership.needsRelease()) { this.scheduleRelease(); }
  }

  onDidStopFling(): void {
    this.recordUserEnd();
    this.ownership.stopFling();
    this.traceInput('fling-end');
    if (this.ownership.needsRelease()) { this.scheduleRelease(); }
  }

  onUserScrollStop(): void {
    this.recordUserEnd();
    this.ownership.scrollStop();
    this.traceInput('scroll-stop');
    if (this.ownership.needsRelease()) { this.scheduleRelease(); }
    this.retryReleaseIfSettled(); // U1：终停兜底（平台 Stop 含回弹收尾，list.d.ts:1662-1690）
  }

  private recordUserEnd(): void {
    if (this.ownership.userOwnsScroll() && this.readLayout?.().epoch === this.gestureEpoch) {
      // U1b：拖拽途中进入带内即立「到过底」事实，松手即释（kelivo :1861-1863 活动期带内
      // 即恢复的判据面等价物）
      this.ownership.didReachEnd(this.isAtEndSafe() || this.withinReleaseBand());
    }
  }

  private cancelRelease(): void {
    this.clearReleaseRetry(); // U1：闩的清理与释放帧取消对称（全部既有取消点经此成对清闩）
    this.releaseFrame?.cancel();
    this.releaseFrame = null;
  }

  private scheduleRelease(): void {
    const ui: UIContext | null = this.ui;
    if (ui === null || this.releaseFrame !== null) { return; }
    const epoch: number = this.gestureEpoch;
    // Stop与Up不预设顺序；下一帧前若又有拖动/惯性，则本次确认作废而非抢回控制。
    const frame: ChatFollowFrame = new ChatFollowFrame((_time: number): void => {
      if (this.releaseFrame !== frame || this.ui !== ui) { return; }
      this.releaseFrame = null;
      if (this.readLayout?.().epoch !== epoch) {
        this.ownership.reset(false, true);
        this.cancelFollow();
        return;
      }
      if (!this.ownership.needsRelease()) { return; }
      const towardEnd: boolean = this.ownership.releaseIntentTowardEnd(); // 清态前快照（U1）
      const atEnd: boolean = this.isAtEndSafe() || this.withinReleaseBand(); // U1b：带内即真
      const resumed: boolean = this.ownership.release(atEnd);
      this.traceInput('release');
      if (resumed && !atEnd) { this.maybeFollow(); }
      else if (this.ownership.isFollowing() && this.pendingFollow) { this.scheduleFollow(); }
      if (resumed) {
        this.clearReleaseRetry();
        if (atEnd) { this.rearmAlignChain(); } // P2：手势在底释放成功 = 自愈链重新武装
      } else if (towardEnd) { this.releaseRetryEpoch = epoch; } // U1：失败即闩，后续事件重放
    });
    this.releaseFrame = frame;
    try { ui.postFrameCallback(frame); }
    catch (error) {
      this.cancelRelease();
      this.ownership.reset(false);
      hilog.warn(0xD5A0, 'ChatFollow', '手势结束确认不可用，保留用户阅读位置：%{public}s',
        (error as Error).message);
    }
  }

  // U1 重评泵（事件驱动零定时器）：闩在场且已沉降才重放 release——「在底」判据与
  // scheduleRelease 同口径并联（isAtEndSafe 严格底 || withinReleaseBand 带内：回弹沉降落
  // 在带内但未到严格底时同算在底，闩不再空挂等滴流拍才续上）；未至底零动作等下一事件；
  // 拖拽/滚动中绝不恢复（userOwnsScroll 复查，对标 kelivo message_list_view.dart 守卫）。
  // 回弹沉降帧走 onDidScroll / onWillScroll 的 EDGE_EFFECT 非占用分支，终停走
  // onUserScrollStop。两读任一异常/未就绪即 false——fail-safe 仍朝不恢复侧收敛。成功后
  // 冻结门（userHoldsReadingPosition = !isFollowing）自然开，下一节流拍续上、积压按 ≤1.5×
  // 上拍阶梯有界流出——无补发逻辑、无一次性甩全量；闩未挂时首行布尔短路零成本
  private retryReleaseIfSettled(): void {
    if (this.releaseRetryEpoch < 0) { return; }
    if (this.readLayout?.().epoch !== this.releaseRetryEpoch) { this.clearReleaseRetry(); return; }
    if (this.ownership.userOwnsScroll()) { return; }
    const settled: boolean = this.isAtEndSafe() || this.withinReleaseBand();
    if (!settled) { return; }
    // 传现读而非字面 true——与上方守卫同帧等价，语义自解释
    const resumed: boolean = this.ownership.replayRelease(settled);
    this.traceInput('release-retry');
    if (resumed) {
      this.clearReleaseRetry();
      // P2：重放成功 = 同口径的在底释放（settled 已由本方法守卫为真）——自愈链一并重新武装
      this.rearmAlignChain();
      if (this.ownership.isFollowing() && this.pendingFollow) { this.scheduleFollow(); }
    }
  }

  onReachEnd(): void {
    this.recordUserEnd();
    this.retryReleaseIfSettled(); // U1：弹簧回弹至末尾再触发一次 = 沉降至末端信号（幂等重评）
  }

  // 强制滚底（发送消息/重试等用户主动动作；重置跟随意图；进页待校正一并取消——
  // 发送追加新消息后旧目标下标已非末条，2026-09-06 二稿）
  forceToBottom(): void {
    this.ownership.reset(true, true);
    this.gestureEpoch = -1;
    this.cancelRelease();
    this.cancelFollow();
    this.clearPendingAlign();
    this.scroll();
  }

  // 历史前插或过程段显式操作撤旧定位；纵向拖动由onWillScroll走同一清理出口。
  cancelAlign(): void {
    this.cancelFollow();
    this.clearPendingAlign();
  }

  // 待校正态清理（下标复位 + 项高基线表清空成对，防上会话基线串味；所有取消点统一走此；
  // ★ S2：进页未收敛位一并清——进页校正期随待校正态终止即放开触顶翻页守卫）
  private clearPendingAlign(): void {
    this.pendingAlignIndex = -1;
    this.entryAlignActive = false;
    this.itemHeights.clear();
  }

  // 回底重挂校正链（键盘避让残余修复轮 P2）：手势在底释放成功即重新武装进页校正链——
  //「底带/浮层几何变化 → 弹回真底」的自愈通道此前只被进页 jumpToBottomAt 武装、任何纵向
  // 拖动 clearPendingAlign 杀死后会话内无重建点（真机「滚动一次后再抬/收键盘位置回不来、
  // 重进才恢复」根因链之一）；而真机收键盘不失焦（hold 长期驻留）又把这唯一通道拦死（同轮
  // P3 对齐）。重挂点仅「用户手势回到/已在底部」（resumed && atEnd，含 U1b 带内——与释放
  // 判据同谓词，不另设死区）——停在半途看历史不重挂；重挂不动现行位置（首次重钉由下一次
  // onContentShift 的 alignScroll 判据自然触发，nativeTargetAtEnd 早退即零动作）；用户任意
  // 拖动仍由 onWillScroll 即时取消（既有语义）；流式 maybeFollow 的 clearPendingAlign
  // 保留 = 两条定位链不竞争。下标取 readLayout 现读末条（空表/未就绪零动作，fail-safe）
  private rearmAlignChain(): void {
    if (this.readLayout === null) { return; }
    const last: number = this.readLayout().lastIndex;
    if (last < 0) { return; }
    this.pendingAlignIndex = last;
    this.alignAttempts = 0;
    this.lastAlignEnd = -1;
    this.itemHeights.clear();
  }

  // 进页放量收窗对齐基线重钉（自检修复·高3，S4 放量完成步消费）：与 rearmAlignChain 同体
  //——只把 pendingAlignIndex 同步到当前暴露末条（读口单源 = readLayout().lastIndex），
  // 不重置手势纪要不主动滚动；首步旧下标不再滞留，键盘/底带变化触发的 alignScroll 不会把
  // 视图拉回尾部窗口旧条目
  retargetAlignToTail(): void {
    this.jumpStampRetargetMs = Date.now(); // ★ U0 观测锚：与完成步 reveal 戳同一同步块（见字段注释）
    this.stampJumpEvent('retarget'); // ★ U0 观测：完成步重钉实调
    this.rearmAlignChain();
  }

  // 进页初始定位：历史回放重建后无动画直达底部末条，替代原 forceToBottom（scrollEdge）的
  // 两个缺陷面——①LazyForEach 未布局完成时只滚到已布局内容的底，后续项陆续布局后位置漂移
  //（「先见顶部旧消息再跳滚到底」中间态）；②布局竞态下 scrollEdge 可能抛异常被静默吞掉
  // 停在顶部。scrollToIndex(末条, false, ScrollAlign.END) 依据（本地 scroll.d.ts + 官方
  // List 参考页双覆盖）：END 对齐计入 contentEndOffset（末条不被输入栏浮层遮）；smooth=false
  // 无动画直达；官方要求「LazyForEach 数据刷新完成后调用」——调用链在 notifyReload 之后
  // 满足。下标 = 展示项数 −1（dataSource.displayCount() −1；列表下标空间 = 展示项，过程段
  // 占一位）：rebuild 后 olderAttempted=false 头部提示行不挂载，LazyForEach 数据位与列表项
  // 一一对齐。
  // ★ 校正链启用（真机实锤「进旧会话停在中间偏下」）：rebuild 同帧 LazyForEach 未布局完成，
  // scrollToIndex 按已布局内容估算落点偏上——记录 pendingAlignIndex 待校正，列表
  // onScrollIndex 事件驱动逼近收敛（见 onScrollIndex 方法注释）；首调落空（坑63 族未绑定/
  // 竞态）也由校正链兜底，故异常只静默不清待校正态。
  // ★ 改二（进会话性能回归修复笔）：`stackAnchoredNow` 形参 = 底锚开态（**调用点现读谓词**
  // CHAT_STACK_FROM_END_ENABLED && anchorJudge.anchored 传入；禁读本件 stackAnchored 字段
  //——其喂入挂 ChatPageContent 帧驱动，重进窗口的调用时序可读到过期 false，修复会静默
  // 落空）。开态跳过预载跳（index−3 START）直达 END（走 !preloadIssued 直对齐落点）：预载
  // 跳是非底锚时代为「估算落点偏上」设计，底锚开态尾部本就实测布局，预跳只会造成「先跳
  // index−3 再校正到 END」的两段跳（B 场景闪动源）；默认 false = 全量链/非底锚原行为逐字
  // 不变（短会话 ≤ 预加载项数、触摸中照旧直对齐）
  jumpToBottomAt(index: number, stackAnchoredNow: boolean = false): void {
    this.ownership.reset(true, true);
    this.gestureEpoch = -1;
    this.cancelRelease();
    this.cancelFollow();
    if (index < 0) {
      // 空会话（新会话/隐私/空历史回放空表）无消息项不定位——待校正态一并复位（上会话悬挂
      // 值对本会话 = 越界下标，scrollToIndex 越界不滚空耗 attempts 到上限；生命周期成对：
      // 记录/复位同点对称）
      this.clearPendingAlign();
      return;
    }
    this.pendingAlignIndex = index;
    this.entryAlignActive = true; // ★ S2：置位唯一（进页校正存活期起——见字段注释；rearmAlignChain 不置位）
    this.alignAttempts = 0;
    this.lastAlignEnd = -1;
    this.itemHeights.clear();
    // ★ 预加载跳（Cube scrollNearBottomEdgeForPreload 机制移植）：先跳到末条前 3 条强制
    // LazyForEach 把尾部项真实布局出来——尾部高度从估算变实测，随后的 END 对齐不吃估算偏差。
    // 同帧不直发 END 对齐（二次 scrollToIndex 会覆盖预加载目标使其失效）；预加载跳改变可见
    // 下标必触发 onScrollIndex，由校正链接力 END 对齐（事件驱动替代 Cube 的 50ms 定时，
    // P1-3）。短会话（目标下标 ≤ 预加载项数）直对齐；预加载抛异常（坑63 族）直对齐兜底；
    // 底锚开态（stackAnchoredNow）同直对齐——见方法头改二注释
    let preloadIssued: boolean = false;
    if (!stackAnchoredNow && index > INITIAL_ALIGN_PRELOAD_ITEMS &&
      !this.ownership.userOwnsScroll()) {
      try {
        this.scroller.scrollToIndex(index - INITIAL_ALIGN_PRELOAD_ITEMS, false, ScrollAlign.START);
        this.nativeTargetPending = true;
        preloadIssued = true;
      } catch (e) {
        // 坑63 族静默——走直对齐兜底
      }
    }
    if (!preloadIssued) {
      this.alignScroll(); // 首调落空（坑63 族未绑定/竞态）由校正链兜底，异常只静默不清待校正态
    }
  }

  // 进页定位校正链（初版判据 end>=target + 一次终校即消费，「可见≠到底」：终校时浮层实测
  // 高〔contentEndOffset，chips 行随连接解析晚到变高〕未稳则 END 对齐基准偏小，链消费后
  // 浮层长高、末条下沉被遮；且内容原地长高无 onScrollIndex 回调 = 收敛后无自愈，间歇性
  // 根因。二稿判据 = end>=target 且偏移级 isAtEnd() 现读（scroll.d.ts「scrolled to the
  // end position」= 含 contentEndOffset 的最大偏移）；到位不主动消费——待校正态常驻，布局
  // 漂移由 onContentShift 钩子（浮层 onAreaChange）重校自愈，取消点 = 手势翻历史
  //（onUserScrollUp）/发送（forceToBottom）/触顶翻页（prepend 处 cancelAlign）。三稿
  //（真机「拉完松手跳回原地、重复两三遍才到底」）：进页未到底时用户自主往底拉原不取消待
  // 校正态——松手惯性滑行期间每个回调见 !isAtEnd 即 scrollToIndex 无动画打断惯性、跳回
  // 未稳布局的估算落点 = 跳回原地根因；改为用户任意方向拖拽即取消进页校正（现由 List
  // onWillScroll 纵向来源承接），逼近计数改「end 有推进清零、仅连续无进展计数」。四稿
  //（Cube 机制移植）：jumpToBottomAt 预加载跳把尾部项估算变实测 + 项级实测上报
  // onItemAreaChange 替换三稿 onReachEnd 猜测通道（覆盖消息项异步长高但可见下标不变、
  // onScrollIndex 无回调的悬挂盲区）。事件驱动零定时器（P1-3）；常态 pendingAlignIndex=-1
  // 首行直返（滚动高频回调零开销）
  onScrollIndex(end: number): void {
    const changed: boolean = this.lastVisibleIndex !== end;
    this.lastVisibleIndex = end;
    if (changed && this.followRequested) { this.scheduleFollow(); }
    if (this.pendingAlignIndex < 0) {
      return;
    }
    if (end >= this.pendingAlignIndex && this.isAtEndSafe()) {
      this.retireNativeTarget();
      // ★ S2 收敛清位：进页校正期即结束、触顶翻页守卫放开——pendingAlignIndex 照旧常驻
      //（晚长自愈重校语义不变，勿在此改消费语义）
      this.entryAlignActive = false;
      // ★ 打点④：校正链收敛 = 定位稳定；owner 随携（打点件只认本窗进页页面的跟随器——
      // 旧页销毁收尾的残存落位事件不入本窗读数，机制见 ChatEnterProbe 头注释）
      markEnterProbe('anchor', this);
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

  // 项级实测上报（Cube handleMessageItemAreaChanged 机制移植——消息项 onAreaChange 喂入，
  // 0.5vp 去抖）：「末条已在视口、内容原地长高、可见下标不变」时 onScrollIndex 无回调，
  // 本通道是长高的**精确**触发源。首报只建档基线不重校（挂载初报非「长高」）；高度变化超
  // 阈值 = 内容真长 → 重对齐末条。流式跟随只关心新旧高度差，不因滚动造成的 y 位移重发。
  // 历史校正仍独立维护去抖基线
  onItemAreaChange(id: string, height: number, previousHeight: number = height): void {
    // 展开局部锚：被钉行（段卡）长高即校正一次——「翻档后首帧」与「动画中间帧」两处
    // 位移都在本通道可见；未钉省一次布尔读
    if (this.rowPinned) { this.fixRowPin(); }
    if (this.followRequested && Math.abs(height - previousHeight) >= ITEM_HEIGHT_DEBOUNCE_VP) {
      this.scheduleFollow();
    }
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
  // 存活期重对齐末条；流式目标存在时只合并下一帧请求，无目标不主动吸底
  onContentShift(): void {
    if (this.followRequested) { this.scheduleFollow(); }
    if (this.pendingAlignIndex < 0) {
      return;
    }
    this.alignScroll();
  }

  // 校正重滚（逼近/漂移/项长高三通道共用）：触摸闸/输入框交互闸一致性——手指在屏时不做
  // 程序滚动；输入闸（hold）期仅当用户持阅读位（follow=false，正在看历史）才拦——跟随时
  //（在底）输入交互期的底带/浮层几何变化照常重钉（★ P3：真机收键盘不失焦，hold 长期驻留，
  // 原「hold 即拦」把在底跟随态的键盘跟随一并拦死——滚动杀链后再抬/收键盘几何变化零重钉，
  // 即「收起后仍被输入框盖住」；「看历史不被拽底」动机由 follow 判据原样承接，同一判据家族
  // 的收紧、非新判据）。待校正态保留（用户纵向拖动即取消链，轻点无位移则由
  // onScrollIndex/onItemAreaChange/onContentShift 通道续校）；坑63 族未绑定/竞态异常静默
  //（待校正态保留，后续事件仍驱动重试；有界性 = 连续无进展 attempts 上限兜底）
  private alignScroll(): void {
    if (this.ownership.userOwnsScroll() || (this.hold && this.userHoldsReadingPosition())) {
      return;
    }
    this.retireNativeTarget();
    if (!this.nativeTargetPending && this.nativeTargetAtEnd()) {
      // ★ 打点④：已到底早退（无需滚动 = 定位已稳）——与收敛分支同口径；owner 随携（同上）
      markEnterProbe('anchor', this);
      return;
    }
    try {
      this.scroller.scrollToIndex(this.pendingAlignIndex, false, ScrollAlign.END);
      this.nativeTargetPending = true;
      this.stampJumpEvent('align'); // ★ U0 观测：只在实滚分支打（上方两早退分支不打——防刷屏）
    } catch (e) {
      // 静默（理由见上）
    }
  }

  // 偏移级在底现读（含 contentEndOffset；坑63 族异常按「不在底」处理——校正链宁重滚
  // 勿早收敛；本件同时用于主动回底事实确认）
  private isAtEndSafe(): boolean {
    try {
      return this.scroller.isAtEnd();
    } catch (e) {
      return false;
    }
  }

  // U1b 释放底带判读（position-truth 带化输入，与 isAtEndSafe 同族——只喂释放链两消费点，
  // 不另设死区判据）：末条底边距阅读线（viewportHeight − max(0, endInset)）的余量 ≤
  // RELEASE_BAND_VP 即视作「在底」。几何源 = itemRect(lastIndex)，与 advanceMotion 的
  // remaining 同源同式；末条未布局或视口未就绪 → false =「不在带内」——误判不在底只多等
  // 一帧、误判在底会抢恢复，fail-safe 朝不恢复侧收敛
  private withinReleaseBand(): boolean {
    if (this.readLayout === null) { return false; }
    const layout: ChatFollowLayout = this.readLayout();
    if (layout.lastIndex < 0 || layout.viewportHeight <= 0) { return false; }
    const tail: RectResult | null = this.itemRect(layout.lastIndex);
    if (tail === null || tail.height <= 0) { return false; }
    const bottom: number = layout.viewportHeight - Math.max(0, layout.endInset);
    return tail.y + tail.height - bottom <= RELEASE_BAND_VP;
  }

  // 只在显示写入之后提出请求；一帧内多次写入合为一个最新目标，不按网络 delta 抢跑。
  maybeFollow(): void {
    // 底锚短路（RIK 四笔笔二）：贴底交给布局（stackFromEnd 末条底边恒 = 底锚），发布拍
    // 不再请求补偿——入口即返，followRequested 不置位（各事件钩子的跟随分支自然静默）
    if (this.stackAnchored) { return; }
    // 展开局部锚短路：钉位期不请求补偿——增量长在钉位行下方（屏外），
    // 视口由用户在读，程序不拽底；清钉后下一拍发布自然续跟（零补发逻辑）
    if (this.pinHeld()) { return; }
    if (!this.ownership.isFollowing() || this.readLayout === null || this.ui === null) { return; }
    if (!isStreamAutoFollow()) { this.cancelFollow(); return; }
    const layout: ChatFollowLayout = this.readLayout();
    if (layout.lastIndex < 0) { return; }
    if (this.followEpoch >= 0 && this.followEpoch !== layout.epoch) { this.cancelFollow(); }
    this.clearPendingAlign();
    this.followEpoch = layout.epoch;
    this.followRequested = true;
    ChatStreamTrace.follow('req');
    this.scheduleFollow();
  }

  private scheduleFollow(): void {
    // 底锚短路（RIK 四笔笔二）：弹簧补偿链唯一排帧口——开态下所有间接续排入口（setHold
    // 开闸 / 松手补滚 / onScrollIndex / onItemAreaChange / onContentShift / 释放帧 / 运动链
    // 自续）一律到此为止，advanceMotion 不可达；三类主动滚动不经本方法不受影响
    if (this.stackAnchored) { return; }
    // 展开局部锚短路（见 rowPinned 字段注释）：同一单一口，间接续排入口
    //（松手补滚 / onScrollIndex / onItemAreaChange / onContentShift / 释放帧 / 运动链自续）
    // 一律到此为止；三类主动滚动（回底 / 发送 / 进页）不经本方法不受影响
    if (this.pinHeld()) { return; }
    // 转场前静默（R1-a U16）：静默期停排帧——在途待发帧已由 silence() 取消、跟随意图
    // 保留未清，resume() 后经既有续排入口原样恢复（同为本方法单一收口）
    if (this.silenced) { return; }
    const ui: UIContext | null = this.ui;
    const read: (() => ChatFollowLayout) | null = this.readLayout;
    if (!this.followRequested || !this.ownership.isFollowing() || ui === null || read === null) { return; }
    if (!isStreamAutoFollow() || read().epoch !== this.followEpoch) {
      this.cancelFollow();
      return;
    }
    this.pendingFollow = true;
    if (this.ownership.userOwnsScroll() || this.hold || this.pendingFrame !== null) { return; }
    const frame: ChatFollowFrame = new ChatFollowFrame((time: number): void => {
      if (this.pendingFrame !== frame || this.ui !== ui || this.readLayout !== read) { return; }
      this.pendingFrame = null;
      const latest: ChatFollowLayout = read();
      if (latest.epoch !== this.followEpoch || !this.ownership.isFollowing() || !isStreamAutoFollow()) {
        this.cancelFollow();
        return;
      }
      if (this.ownership.userOwnsScroll() || this.hold) { return; }
      this.pendingFollow = false;
      if (latest.lastIndex < 0) { this.cancelFollow(); return; }
      try {
        if (!this.motionEnabled) {
          this.scroller.scrollToIndex(latest.lastIndex, false, ScrollAlign.END);
          this.nativeTargetPending = true;
          return;
        }
        this.advanceMotion(latest, time);
      } catch (error) {
        this.stopMotion();
        hilog.warn(0xD5A0, 'ChatFollow', '跟随目标暂不可用，等待下一次显示布局：%{public}s',
          (error as Error).message);
      }
    });
    this.pendingFrame = frame;
    try { ui.postFrameCallback(frame); }
    catch (error) {
      this.cancelFrame();
      hilog.warn(0xD5A0, 'ChatFollow', '无法提交跟随帧：%{public}s', (error as Error).message);
    }
  }

  private advanceMotion(layout: ChatFollowLayout, frameTimeNs: number): void {
    if (layout.viewportHeight <= 0) { this.stopMotion(); return; }
    const offset: number = this.scroller.currentOffset().yOffset;
    const bottom: number = layout.viewportHeight - Math.max(0, layout.endInset);
    const tail: RectResult | null = this.itemRect(layout.lastIndex);
    if (tail === null) { this.stopMotion(); return; } // 读几何异常（坑63 面）：静默停排待布局事件重启
    let remaining: number = tail.height > 0 ? Math.max(0, tail.y + tail.height - bottom) : 0;
    if (tail.height <= 0 && !this.scroller.isAtEnd()) {
      // 平台零矩形（未物化瞬态）：按末个可见项矩形有限推进。可见项读取抛错同走停排；
      // 可见项亦为零矩形（双零）→ 只挂帧等待布局物化、**不归零弹簧**——真机轨迹实锤
      //（RIK 三笔组D 复采）：此处 stopMotion 令每批发布后的弹簧反复重启（首帧零步进 +
      // 加速期），新块落地至首步进迟 230ms+ = 底边下探滞留病根。永续防护 = followRequested
      // 生命周期（手势/偏好/换代/离场清）+ detach，双零态下零滚动调用无副作用。
      const visible: RectResult | null = this.lastVisibleIndex >= 0 ?
        this.itemRect(Math.min(this.lastVisibleIndex, layout.lastIndex)) : tail;
      if (visible === null) { this.stopMotion(); return; }
      if (visible.height <= 0) { this.scheduleFollow(); return; }
      remaining = Math.max(layout.viewportHeight * 0.25, visible.y + visible.height - bottom);
    }
    if (!Number.isFinite(offset) || !Number.isFinite(remaining)) { this.stopMotion(); return; }
    ChatStreamTrace.geometry(tail.height, offset, offset + remaining, this.motion.velocity);
    const progress: number = this.feedback.reconcile(offset, frameTimeNs, this.pixelVp);
    if (progress < 0) { this.stopMotion(); return; }
    if (progress === 0) {
      this.motion.lastFrameNs = frameTimeNs;
      this.scheduleFollow();
      return;
    }
    // 上一请求已落地，自然收敛不再写回估算offset。只有仍在途的取消才调用scrollTo清原生目标。
    this.nativeTargetPending = false;
    const step: ChatFollowMotionStep = advanceFollowMotion(this.motion, remaining, frameTimeNs);
    const distance: number = this.feedback.distance(step.delta, remaining, this.pixelVp);
    if (distance > 0) {
      this.feedback.issue(distance, offset, frameTimeNs, !step.active);
      this.scroller.scrollBy(0, distance);
      ChatStreamTrace.displacement(offset, remaining, distance);
    }
    if (step.active || distance > 0) { this.scheduleFollow(); }
    else { this.stopMotion(); }
  }

  // null = getItemRect 抛错（坑63 注入/竞态异常）——与「平台返回零矩形（未物化瞬态）」严格
  // 区分：异常停排（原语义，防异常态日志洪水与空转），零矩形续排等待（RIK 三笔组D，杀弹簧
  // = 每批发布重启致底边迟启动）。消费方逐点判 null。
  private itemRect(index: number): RectResult | null {
    try { return this.scroller.getItemRect(index); }
    catch (error) {
      hilog.warn(0xD5A0, 'ChatFollow', '跟随项尚未布局，保留当前可读位置：%{public}s',
        (error as Error).message);
      return null;
    }
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
