// 消息区加载蒙层（2026-10-15 渲染性能与五项功能优化批 U4b）。
// 域定义一句话：**进会话历史加载期间消息区加载指示的独立视觉件**——淡蒙层 + 居中卡 +
// LoadingProgress + OPACITY 渐隐退场，形制照 BusyOverlay.ets 先例（形态复用非组件直用，
// 只盖消息区）。★ 2026-10-15 拆域笔自 ChatPageContent 迁出成立本件（ChatPageContent 剔头
// 1174 软引导区，蒙层整域内联会推它越 1200 硬线——宪法硬线唯一出路 = 该改动所属功能域
// 先拆独立文件再动手；方法体原样搬迁零行为变化）。
// · 显隐相位（与空态三分支互斥的「第四分支」内核）：messageCount===0 且 !historyLoaded 且
//   无错误——判定走 @ObjectLink 订阅 @Track 的既有通道（build 期直读；**禁 @Prop 下发热点**，
//   坑16 家族）。换会话靠页面重建、分支切换不清旧消息——加载相只在首挂命中，蒙层生命周期
//   天然与页面同寿。
// · ★ 2026-11-17 加载相锚点后移笔（决明报「侧边模式启动进会话为什么会有加载动画」）：
//   **起手门前置**——entryLoadEpoch 为 0（尚未起手）时一律不亮；每次 loadHistory 起手该
//   批次号 +1，经 @Prop 数值翻转 + Watch 起拍。原时间轴自组件挂载起算，而真正装载要等
//   whenReady（DB 初始化十步串行维护链）——冷启动这段空窗被
//   误算成「加载中」，侧栏形态首页主区常驻 ChatPage，启动即挂载，故每次启动必亮 150ms 延迟
//   + 400ms 最短显示。门后语义 = 「读库真正起手后才起拍」：DB 等待期纯背景（与加载中空态层
//   同观感）；空会话/短会话仍在 150ms 窗内装完（零闪现）；长会话真超窗才亮（加载动画本义）。
//   起手批次号写点唯一 = ChatPageLoadCtrl.beginEntryFirstScreenWindow（进页读库唯一入口）。
//   1000ms 首屏兜底不动——它是「已起手后帧信号丢失」的兜底，不承担 DB 等待期。
// · ★ 2026-10-18 中间层退役：原「进页校正相」（S5，以暴露窗口 entryHoldback 为源，覆盖
//   空闲重进 messageCount 恒 >0 的裸窗）随窗口整域删除。空闲重进现走全量读库链（折叠默认
//   开后为 0.2 秒量级），本件只承担 fresh 加载相——这就是用户初衷里的「加载动画」本体。
// · 双时间参数（方案档待拍板 2 保守档起步，真机可调两常量单源）：最短延迟出现防快加载与
//   路由转场期闪现（窗内完成即零闪现——「一闪而过」的加载态比没有更差）；最短显示时间防
//   「刚亮就灭」的 false-positive 闪现（新会话空历史加载略超延迟窗的场景——亮起即切空态
//   引导层前先稳住尾窗再渐隐）。
// · 可见性 = build 期直读判据（@Track / @StorageProp / @Prop 重渲染天然收分支）+ 两定时器
//   只管时间轴——**不挂 Watch 到 @ObjectLink**（官方对「对象属性变化触发变量级 Watch 回调」
//   无明示承诺；时间轴起拍只挂 aboutToAppear 与 errorText / 偏好两 Watch——@Prop 与
//   @StorageProp 的 Watch 均为官方明示支持通道，且本件 @Watch 已按官方建议序「状态装饰器
//   在前」书写）。
// · HitTestMode.None：蒙层只做视觉指示，不挡输入栏与列表手势；禁 backgroundBlurStyle
//（ChatPageContent 渐变蒙层注释在档的三案实验记录——实时渲染形态 pop 转场卡）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ChatDataSource } from './ChatDataSource';
import { markEnterProbe } from './ChatEnterProbe';
import { PREF_CHAT_LOADING_OVERLAY_KEY, PREF_CARD_ALPHA_LEVEL_KEY, CARD_ALPHA_DEFAULT }
  from '../../common/AppPreferences';
import { cardBg, cardTitleColor, SHEET_MASK_COLOR } from '../../common/Theme';

// 最短延迟出现（ms）：加载启动后至少等本毫秒数才亮蒙层
const CHAT_LOADING_OVERLAY_DELAY_MS: number = 150;
// 最短显示时间（ms）：蒙层一旦亮起至少保留本毫秒数才退场
const CHAT_LOADING_OVERLAY_MIN_SHOWN_MS: number = 400;

@Component
export struct ChatLoadingOverlay {
  // 消息数据源（@ObjectLink 订阅 @Track messageCount / historyLoaded——相位判据通道）
  @ObjectLink dataSource: ChatDataSource;
  // 进页装载起手批次号（@Prop @Watch：0 → 1 起、每次 loadHistory 起手 +1 = 读库链真正
  // 起手，起拍 150ms 延迟窗）。★ 为何不靠 aboutToAppear 起拍：判据原自组件挂载即成立，
  // 冷启动等 DB 就绪的空窗被误算成加载中（侧栏形态启动必现假动画）。@Prop 的变量级 Watch
  // 是官方明示支持通道（@ObjectLink 对象属性变化不挂 Watch——本件头注释既有红线）；
  // 本字段每进页只翻一次，非热点（禁 @Prop 下发热点针对高频字段）
  @Prop @Watch('onLoadingOverlayTick') entryLoadEpoch: number = 0;
  // 初始加载失败提示（'' = 无）：错误在场即非加载相（蒙层让位错误覆盖层——宿主页错误分支
  // 在蒙层之下亦不可见，蒙层自身判据即不含错误态）；错误清空重拉 = 加载相重入（Watch 起拍）
  @Prop @Watch('onLoadingOverlayTick') errorText: string = '';
  // 偏好开关（prefChatLoadingOverlay 默认开）：关态 = 纯背景（2026-09-06 空态分层笔的
  // 刻意形态，与开关引入前逐字同）
  @StorageProp(PREF_CHAT_LOADING_OVERLAY_KEY) @Watch('onLoadingOverlayTick') chatLoadingOverlay: boolean = true;
  // 系统颜色模式（卡底深浅分治）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 卡底透明度档位只读订阅（2026-10-25 卡底透明度笔即时面——会话页常驻浮层卡）
  @StorageProp(PREF_CARD_ALPHA_LEVEL_KEY) cardAlphaLevel: number = CARD_ALPHA_DEFAULT;
  // 延迟窗已过且当时仍在加载相（亮起置位；离开加载相或偏好关闭即失效——见 evaluate 注释）
  @State private overlayArmed: boolean = false;
  // 最短显示尾窗（亮起置位、到点定时器清除——加载完成的快场景靠它压住「亮起即灭」闪现）
  @State private overlayLinger: boolean = false;
  private showTimer: number = -1;
  private lingerTimer: number = -1;

  aboutToAppear(): void {
    // 时间轴首拍（Watch 初始化不触发——首挂加载相在此起排延迟窗）
    this.evaluateLoadingOverlay();
  }

  aboutToDisappear(): void {
    // 定时器成对释放（show / linger 两定时器与组件同寿）
    this.releaseLoadingOverlayTimers();
  }

  // 加载相判定：**先过起手门**（读库已真正起手——见 entryLoadEpoch 注释），再判历史加载相
  //（无消息且历史未加载完成，或首屏就绪信号未真）；且无错误、偏好开。
  //（★ 2026-10-18 一次出现笔：数据安装后蒙层再盖到首个内容帧——OFF 态不再「数据装好即
  // 退蒙层、留下干转圈逐块填」；ON 态收起条首帧即就绪，等效读库期即退）。
  // ★ 2026-10-18：进页暴露窗口退役，原「窗口开启态」校正相随整域删除——窗口期
  // messageCount 恒 >0 的裸窗场景不再存在，本判据回归单一加载相
  // ★ 2026-11-17 加载相锚点后移笔：起手门是最外层前置——DB 等待期（entryLoadEpoch=0）
  // 无论 messageCount/historyLoaded 如何都不得亮
  // ★ 2026-11-18 乐观空态笔：freshEntry（本地新造会话）不参与加载相——空态引导层已按
  // 「必然空」先行成立，蒙层再盖上即自相矛盾（同判据在 ChatPageEmptyLayer 空态分支）
  private loadingPhase(): boolean {
    return this.entryLoadEpoch > 0 &&
      !this.dataSource.freshEntry &&
      ((this.dataSource.messageCount === 0 && !this.dataSource.historyLoaded) ||
        !this.dataSource.entryFirstScreenReady) &&
      this.errorText === '' && this.chatLoadingOverlay;
  }

  // 时间轴起拍评估：加载相内 → 排最短延迟定时器（到点仍在加载相才亮）；离开加载相 →
  // 撤定时器并 disarm（分支渲染由 build 直读判据承载——加载完成的收分支不需要本函数参与，
  // @Track 变化驱动的重渲染天然把分支收掉；本函数只管「亮起」的时间轴与重入）。起拍源四处
  // = aboutToAppear + entryLoadEpoch / errorText / 偏好三 Watch（★ 2026-11-17 锚点后移笔：
  // entryLoadEpoch 自增是主起拍源，其余三处只管重入/失效）
  private evaluateLoadingOverlay(): void {
    if (this.loadingPhase()) {
      if (this.overlayArmed || this.showTimer !== -1) {
        return; // 已亮或已排队
      }
      this.showTimer = setTimeout((): void => {
        this.showTimer = -1;
        if (!this.loadingPhase()) {
          return; // 窗内加载已完成 / 偏好已关——零闪现（不亮）
        }
        this.overlayArmed = true;
        this.overlayLinger = true;
        // ★ U0 观测（2026-10-18 方案档扩面，纯 hilog 零行为）：蒙层实际亮起时点入时轴——
        // 对照 150ms 理论延迟值（S1 蒙层丢失/迟到频次量化）
        markEnterProbe('overlayOn');
        this.lingerTimer = setTimeout((): void => {
          this.lingerTimer = -1;
          // 最短显示尾窗到点：清 linger；armed 仅在**已离开加载相**时一并复位。仍在加载相则
          // armed 保留（蒙层持续到加载完成由 build 判据收分支——长加载中途不灭，U4 续工笔
          // 收尾修复）；已在尾窗内完成加载的，armed 在此复位 = 下一轮加载相重新走延迟窗
          this.overlayLinger = false;
          if (!this.loadingPhase()) {
            this.overlayArmed = false;
          }
        }, CHAT_LOADING_OVERLAY_MIN_SHOWN_MS);
      }, CHAT_LOADING_OVERLAY_DELAY_MS);
      return;
    }
    if (this.showTimer !== -1) {
      clearTimeout(this.showTimer);
      this.showTimer = -1;
    }
    this.overlayArmed = false;
  }

  private onLoadingOverlayTick(): void {
    this.evaluateLoadingOverlay();
  }

  private releaseLoadingOverlayTimers(): void {
    if (this.showTimer !== -1) {
      clearTimeout(this.showTimer);
      this.showTimer = -1;
    }
    if (this.lingerTimer !== -1) {
      clearTimeout(this.lingerTimer);
      this.lingerTimer = -1;
    }
  }

  build() {
    // 空 Stack = 空闲零尺寸零命中（BusyOverlay 同款：不设 width/height 即内容自适应）
    Stack() {
      if ((this.overlayArmed && this.loadingPhase()) || this.overlayLinger) {
        Column() {
          Column({ space: 8 }) {
            LoadingProgress()
              .width(28)
              .height(28)
              .color(cardTitleColor())
            Text('正在加载对话')
              .fontSize(14)
              .fontColor(cardTitleColor())
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .constraintSize({ minWidth: 108, maxWidth: 240 })
          .padding({ left: 20, right: 20, top: 16, bottom: 16 })
          .backgroundColor(cardBg(this.appColorMode, this.cardAlphaLevel))
          .borderRadius(20)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(SHEET_MASK_COLOR)
        .hitTestBehavior(HitTestMode.None)
        // 官方 TransitionEffect 渐隐退场（BusyOverlay 先例同款；禁全局 animateTo——
        // UIContext 纪律）
        .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))
      }
    }
  }
}
