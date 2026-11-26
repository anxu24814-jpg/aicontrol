// 触顶翻页编排域（2026-08-31 任务 D 自 ChatPageContent 域级拆出——复原 dshinhm 翻页链
// 该文件必超 400 红线，按宪法先拆「触发与滚动锚点保持」域；查询与状态在
// ChatPageLoadCtrl.loadOlder（路径锚沿 parent 链前查 + ChatDataSource.prependMessages），
// 头部提示行 UI 在 ChatPageContent——本域只管 onReachStart 触达、锚点定格与恢复）。
// · 锚点语义（dshinhm 同款）：触发加载时定格第一个可见消息 id；头部前插后内容变长，
//   纯 offset 保持会整屏跳走——按 id 反查新下标 scrollToIndex 贴顶恢复（轻微容差可接受）。
//   锚点在下标 = List 项位（含头部提示行）；定格发生在提示行出现**之前**（守卫刚过、
//   置 loading 前），此时与 LazyForEach 数据位一一对齐——恢复时提示行已收，位序复原。
//   ★ 2026-10-17 施工总案 S3：定格加「用户真实滚动」前置判据（userHoldsReading 闭包 ←
//   followCtrl.userHoldsReadingPosition 只读透传）——列表初始化布局（onScrollIndex 初始化
//   也触发一次，list.d.ts:1611-1613）无手势不定格；拦定格不拦加载（详见 tryLoadOlder 内注释）。
// · 防抖守卫五连：messageCount===0（空会话不翻）/ isBusy（流式停——★ 2026-09-15 决明指令
//   「在流式禁用」，判据/口径见 tryLoadOlder 内注释）/ entryAlignPending（进页定位未收敛停
//   ——★ 2026-10-17 施工总案 S2：重进首物化期触顶不发自动翻页链，杀重进被拽顶链 H1 步2；
//   ★ 2026-10-18 暴露窗口退役后本守卫只认定位未收敛位）/
//   olderLoading（加载中闸——重复触顶防抖）/ olderExhausted（到底停——有界红线，禁止无界连拉）。
// · 失败路径：查询异常（loadOlder 上抛）不恢复锚点——内容未变，位置本就不动。
// · 翻页与流式/跟随共存：本域不触 followCtrl——触顶翻历史时用户已脱底（跟随早停），
//   onReachStart 与 onReachEnd 门控互不干扰。
import { ChatDataSource } from './ChatDataSource';
import { cardDescColor } from '../../common/Theme';

export class ChatOlderCtrl {
  // 延迟求值箭头闭包（持组件 this——ChatSendRefs 同款姿势；构造时组件成员未定序，
  // 调用时求值即安全）
  private getDataSource: () => ChatDataSource;
  private getScroller: () => Scroller;
  private onLoadOlder: () => Promise<void>;
  // 流式判定（★ 2026-09-15 决明指令「在流式禁用」；闭包延迟求值——调用时读总是当时值。
  // 与 ChatSendCtrl refs.sending 的差异：彼为页面 @State 直读，本处经 ChatPageContent
  // @Prop 中转——该通道实测可用，依据与迁移口径见接线点注释〔ChatPageContent.olderCtrl〕）
  private isBusy: () => boolean;
  // 进页定位未收敛判定（★ 2026-10-17 施工总案 S2 第五守卫判据）：闭包延迟求值同 isBusy——
  // 经 ChatPageContent 构造读 followCtrl.isEntryAlignActive()（followCtrl 声明序在前即安全）
  private entryAlignPending: () => boolean;
  // 用户真实滚动判定（★ 2026-10-17 施工总案 S3 定格前置判据）：闭包延迟求值同上——经
  // ChatPageContent 构造读 followCtrl.userHoldsReadingPosition()（= !isFollowing 公开只读；
  // 消费既有 ownership 单源，不设第二套死区判据——红线3）
  private userHoldsReading: () => boolean;
  // 第一个可见项下标（List onScrollIndex 轻量更新，非状态驱动）
  private visibleFirstIndex: number = -1;
  // 触顶时定格的锚点消息 id（'' = 无待恢复锚点）
  private anchorId: string = '';

  constructor(getDataSource: () => ChatDataSource, getScroller: () => Scroller,
    onLoadOlder: () => Promise<void>, isBusy: () => boolean,
    entryAlignPending: () => boolean, userHoldsReading: () => boolean) {
    this.getDataSource = getDataSource;
    this.getScroller = getScroller;
    this.onLoadOlder = onLoadOlder;
    this.isBusy = isBusy;
    this.entryAlignPending = entryAlignPending;
    this.userHoldsReading = userHoldsReading;
  }

  // List.onScrollIndex 回调入口（锚点记录用；滚动时高频轻量更新）
  onScrollIndex(first: number): void {
    this.visibleFirstIndex = first;
  }

  // 触顶入口（List.onReachStart 回调）：守卫 → 定格锚点 → 置加载态 → 上行加载 →
  // resolve 后恢复锚点；异常 toast 在 loadOlder 侧呈报，此处 catch 只收加载态
  //（失败不恢复滚动——内容未变位置本就不动）
  // ★ 2026-09-02 手感修复：用户「滑到顶停止后立刻下滑没反应，过一小会儿才恢复」——
  // 根因 = 加载完成后的 scrollToIndex 锚点恢复把用户下滑拉回（打断正在进行的手势）。
  // 修复 = 用户朝底方向滑动（onTouch 手指上移）时 cancelAnchor 取消待恢复锚点，
  // 加载完成后 restoreAnchor 判空直接跳过——用户已放弃看旧消息，不再拉回
  tryLoadOlder(): void {
    const ds: ChatDataSource = this.getDataSource();
    if (ds.messageCount === 0) {
      return;
    }
    // ★ 2026-09-15 流式禁用（决明指令「在流式禁用吧」；存量观察项销账）：流式期间触顶
    // 不翻页——走查已证「流式增量 × 头部前插」共存自愈（同 id 重挂 + 权威串在域），但
    // 交叉面按指令整体收掉。静默 return（触顶是列表隐式手势，不 toast——与同域三守卫同
    // 姿势）；守卫在 olderAttempted 置位之前 = 流式中触顶零翻页状态写入（翻页态只在非
    // 流式下演进，交叉面归零）。已知取舍：流式期间触顶被跳过，流式结束后列表仍在顶部
    // 时 onReachStart 不会自行重触发（无滚动事件），用户滑离顶部再回顶即正常翻页
    if (this.isBusy()) {
      return;
    }
    // ★ 2026-10-17 施工总案 S2 第五守卫：进页定位未收敛期触顶不翻页。重进首物化若从顶
    // 起算（anchored 翻转晚于首物化的 H2 竞态窗），onReachStart 会被列表初始化触发一次
    //（list.d.ts 实锤 initialIndex=0 初始化即触发）——此刻放行自动翻页链，loadOlder 的
    // cancelAlign 会杀进页校正链 + restoreAnchor 贴顶恢复 = 重进被拽回顶部驻留（调研档
    // §3.2 杀手链 H1 第 2 步）。判据 = followCtrl「进页定位未收敛」只读位（置位唯一 =
    // jumpToBottomAt；收敛/放弃/手势接管后自然放开——正常触顶翻页零回归；禁按字面
    // pendingAlignIndex ≥ 0 判断：其收敛后常驻 ≥0，字面判断会把整个会话的触顶翻页全拦死）。
    // 照 isBusy 形制：静默早退、置位于 olderAttempted 之前 = 进页校正期触顶零翻页状态写入。
    // 暴露窗口已退役（2026-10-18），本守卫只认进页定位未收敛位
    if (this.entryAlignPending()) {
      return;
    }
    ds.olderAttempted = true; // 触达标记（「已到顶」行首次触顶才亮——见 ChatDataSource 注释）
    if (ds.olderLoading || ds.olderExhausted) {
      return;
    }
    const firstIndex: number = this.visibleFirstIndex >= 0 ? this.visibleFirstIndex : 0;
    // ★ 2026-10-08 过程段折叠笔：下标空间 = 展示项（totalCount/getData 同层），锚点仍按
    // **源消息 id** 定格（段项取其首步 id）——恢复时按 id 反查展示项下标，段在前插补全后
    // 改头/合并也不失锚（任务书 §9.A.4 原索引调用点逐项适配）
    if (ds.displayCount() <= firstIndex) {
      return; // 下标越界防御（理论不可达——onScrollIndex 恒在窗口内）
    }
    // ★ 2026-10-17 施工总案 S3 定格前置判据：锚点只在「用户真实滚动」后定格——
    //   userHoldsReading()（= !isFollowing）。列表初始化布局（onScrollIndex 初始化也触发
    //   一次，list.d.ts:1611-1613）期无手势 → isFollowing=true → 拦定格；用户真滑到顶
    //   （拖拽 >2vp 退跟）→ 定格照常。「拦定格 ≠ 拦加载」：加载照发（olderAttempted /
    //   olderLoading / onLoadOlder 均不受影响），prepend 后 restoreAnchor 空锚 no-op、
    //   落位由 notifyReload 重排决定（栈底锚开态下可能自愈回底）——该落位行为未实测，
    //   列真机验证项（方案档 §7-8）。else 显式清锚：失败路径（onLoadOlder 上抛）不清锚，
    //   拦定格时须防陈锚复燃（不定量格却被恢复 = 拽向旧位置）
    if (this.userHoldsReading()) {
      this.anchorId = ds.anchorMessageIdAt(firstIndex);
    } else {
      this.anchorId = '';
    }
    ds.olderLoading = true;
    this.onLoadOlder()
      .then((): void => {
        ds.olderLoading = false;
        this.restoreAnchor();
      })
      .catch((): void => {
        ds.olderLoading = false;
      });
  }

  // 取消待恢复锚点（用户朝底方向滑动 = 放弃看旧消息——2026-09-02 手感修复配合：
  // 加载完成不再 scrollToIndex 拉回，用户下滑即时生效；不打断加载本身，仅跳过恢复）
  cancelAnchor(): void {
    this.anchorId = '';
  }

  // 锚点恢复：按源消息 id 反查展示项新下标（头部前插使展示项下标平移）→ scrollToIndex 贴顶。
  // ★ 2026-10-08 过程段折叠笔：查找走投影映射（displayIndexOfMessage——被折叠步骤命中其所在
  // 段，段项在翻页补全后仍持原成员/原键）
  private restoreAnchor(): void {
    const anchor: string = this.anchorId;
    this.anchorId = '';
    if (anchor === '') {
      return;
    }
    const ds: ChatDataSource = this.getDataSource();
    const target: number = ds.displayIndexOfMessage(anchor);
    if (target >= 0) {
      try {
        this.getScroller().scrollToIndex(target, false);
      } catch (e) {
        // 坑63 族：未绑定/时序竞态下 scrollToIndex 可能抛——静默（内容未变，无补偿动作）
      }
    }
  }
}

// 触顶翻页头部提示行（2026-08-31 任务 D；UI 件随域迁此——ChatPageContent 超线拆分的
// 组成部分，父级 List 内 ListItem 包裹、两态经 @Prop 入）：加载中 = LoadingProgress +
// 「加载更早…」（随 olderLoading 消失）；已到顶 = 「已到顶」次要色居中行（olderExhausted
// 且查过至少一页才由父级渲染——短会话未触顶不常驻）。样式 = dshinhm 列表页尾部
// LoadingProgress 同款姿态
@Component
export struct ChatOlderRow {
  @Prop loading: boolean = false;
  @Prop exhausted: boolean = false;

  build() {
    if (this.loading) {
      Row({ space: 8 }) {
        LoadingProgress()
          .size({ width: 24, height: 24 })
        Text('加载更早…')
          .fontSize(13)
          .fontColor(cardDescColor())
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 8, bottom: 8 })
    } else if (this.exhausted) {
      Text('已到顶')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 8, bottom: 8 })
    }
  }
}
