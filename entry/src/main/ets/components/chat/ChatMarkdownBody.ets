/** 正文渲染唯一入口（旧双库与调试双闸已退役，正式包即本入口）。 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { accessibility } from '@kit.AccessibilityKit';
import { UIUtils } from '@kit.ArkUI';
import { MarkdownDisplayBinding, MarkdownDisplayMetrics } from '../../common/markdown/MarkdownDisplayBinding';
import { ChatDisplayBudget } from '../../common/chat/ChatDisplayBudget';
import { MarkdownEndReason } from '../../common/markdown/MarkdownDocumentModel';
import { MarkdownSemanticSnapshot } from '../../common/markdown/MarkdownSemanticModel';
import { MARKDOWN_BODY_FONT_SIZE, MARKDOWN_BODY_LINE_HEIGHT, MarkdownPresentationFrame,
  MarkdownPresentationTracker }
  from '../../common/markdown/MarkdownPresentation';
import { CHAT_STREAM_TRACE_ENABLED } from './ChatStreamTrace';
import { ChatStreamTrace } from './ChatStreamTrace';
import { FONT_FAMILY_SYSTEM, FONT_FAMILY_MONO } from '../../common/ChatFont';
import { DsCitationSpan } from './ChatMessageCompose';
import { MarkdownDocumentView } from './markdown/MarkdownDocumentView';
// 进页转场窗信号（掉帧修复刀②：持让期首挂的解析+建块挪出 push 转场窗）
import { chatTransitionDefer, chatTransitionHeld } from './ChatTransitionHold';

export function markdownMotionEnabled(): boolean {
  try {
    return !accessibility.isAnimationReduceEnabledSync();
  } catch (error) {
    hilog.warn(0xD5A0, 'ChatMarkdownBody', '无法读取减弱动态效果，按静态显示：%{public}s',
      (error as Error).message);
    return false;
  }
}

@ComponentV2
export struct ChatMarkdownBody {
  @Param bindingId: string = '';
  @Param content: string = '';
  @Param endReason: MarkdownEndReason | undefined = undefined;
  @Param darkMode: boolean = false;
  // 消息字体家族串：V1 宿主自订阅字体键换算下发；正文链各叶件只透传不改写，
  // 家族串推导单源 = common/ChatFont.ets
  @Param bodyFontFamily: string = FONT_FAMILY_SYSTEM;
  @Param codeFontFamily: string = FONT_FAMILY_MONO;
  @Param live: boolean = false;
  // 尾先揭示：底锚进页的末条消息先出尾部；占位形态恒头先无观感差
  @Param tailFirst: boolean = false;
  // 占位揭示：宿主展开动作置位——正文在不可见层背后分帧建块、行内只显骨架，揭示完成一次性
  // 显现；缺省 false = 既有可见渐进
  @Param placeholder: boolean = false;
  @Param displayBudget: ChatDisplayBudget | undefined = undefined;
  @Param aiContent: boolean = true;
  @Param compact: boolean = false;
  // DS 来源角标（S3③，可选——缺省空数组零渲染零行为变化）：UTF-16 码元区间 + 来源卡序号，
  // 沿正文链下传行内视图按区间锚定上标序号；点击上行序号，宿主（ChatMessageItem）换算
  // 来源卡行锚点走既有滚动链
  @Param citations: DsCitationSpan[] = [];
  @Event onAnchor: (id: string) => void = (_id: string): void => {};
  @Event onCitation: (entry: number) => void = (_entry: number): void => {};
  // 长正文分帧揭示完成（或无需揭示/组件回收）上行——宿主解除「展开中」静默位
  @Event onRevealDone: () => void = (): void => {};
  // 占位形态上行：滚动暂停期挂载由正文链自行进入占位时上行，宿主同步置占位标记（骨架/
  // 不透明度/行高静默判据）；展开路径宿主已前置位，重复幂等
  @Event onRevealPlaceholder: (placeholder: boolean) => void = (_placeholder: boolean): void => {};
  @Local private snapshot: MarkdownSemanticSnapshot | null = null;
  // 源范围只可切与当前快照同次提交的原文，不能在 Monitor 之前读到下一帧 content。
  @Local private displaySource: string = '';
  @Local private presentation: MarkdownPresentationFrame = { kind: 'initial', enteringIds: [] };
  private presentationTracker: MarkdownPresentationTracker = new MarkdownPresentationTracker();
  @Local private failed: boolean = false;
  @Local private motionEnabled: boolean = false;
  private input: MarkdownDisplayBinding | null = null;
  private failedBindingId: string = '';
  // 解析占比探针一次性标记（U0 观测面，纯观测零行为）：live=false 首帧打一行独立 hilog
  //（同域 0xD5A0 tag 'ChatEnterProbe'）——真机占比 >30% 则 U5/U7 立项依据成立，<10% 降级；
  // 标记随组件消亡（有界），失败路径未标记则下次成功帧补打
  private parseProbeLogged: boolean = false;
  private alive: boolean = false;
  // 进页转场持让推迟中（掉帧修复刀②）：aboutToAppear 遇持让窗未解析即待释放回调消费。
  // ★ 销毁时**不清**宿主骨架位——位由下一个渲染者接管（重挂批置位/解析、重进换源
  // resetLongMessageExpansion 复位、运行态回收重建），残留自愈链全在；销毁直调清位会误清
  // 交叠新 body 持有的骨架位 = 「退出重进 空气泡→气泡塌缩→内容」闪两次根因（2026-11-15
  // 决明报障修复，原销毁兜底删除）
  private transitionDeferred: boolean = false;
  private motionSubscription: ((enabled: boolean) => void) | null = null;
  private motionUnavailable: boolean = false;

  aboutToAppear(): void {
    this.alive = true;
    this.input = new MarkdownDisplayBinding();
    this.presentationTracker = new MarkdownPresentationTracker();
    this.failedBindingId = '';
    this.failed = false;
    this.motionUnavailable = false;
    this.syncMotionPreference();
    // 进页转场持让（掉帧修复刀②）：非流式首挂遇持让窗——解析与建块整段挪出 push 转场窗
    //（不与转场动画争主线程）。骨架先行（onRevealPlaceholder 上行复用滚动暂停占位同通道，
    // 该构建期上行链现行在跑——MarkdownDocumentView.aboutToAppear 同款）；defer 期正文链
    // 收到空快照的「短文档回告」在 build 转发口被 transitionDeferred 拦截（否则骨架一帧即
    // 清、持让窗剩段显示空气泡——见转发口注释）。流式行不持让（增量链单帧成本低，且生成中
    // 重进应立即可见）。持让期 Monitor 若被参数变更触发会直接解析——提前消费无害（其完成
    // 回告经 build 转发口的 snapshot!==null 支照常透传清位，见转发口注释）。
    if (!this.live && chatTransitionHeld()) {
      this.transitionDeferred = true;
      chatTransitionDefer((): void => {
        this.transitionDeferred = false;
        if (this.alive) {
          // ★ 硬清位先于解析（P0 修复，2026-11-15 决明报障「进会话一直占位空气泡 / 气泡
          // 变矮不出内容」）：清位**不得依赖正文链揭示完成回告**——旧形态下释放后快照落定
          // 时 placeholder 仍 true，正文链判定走占位分支 revealLimit=0（首帧零块），清位只
          // 能等揭示任务跑完；而揭示调度器为全局单例、paused 位随滚动 start/stop 翻转，
          // 任一停摆（程序化定位滚动的 start 无对应 stop / 帧派发失败不重排）即永久卡在
          // 0 块：骨架不撤 + 正文零块 = 空气泡且气泡变矮。先清位再解析 ⇒ 正文链收到非空
          // 快照时 placeholder 已 false，走普通渐进（首屏 MD_PROGRESSIVE_FIRST_BLOCKS 块
          // 立即上屏）——与优化前形态一致，调度器停摆至多影响后续块的节奏、不影响可见性。
          // 同帧执行：宿主清位与快照落定同批渲染，无中间空白帧
          this.onRevealDone();
          this.consumeFrame();
        }
      });
      this.onRevealPlaceholder(true);
      return;
    }
    this.consumeFrame();
  }

  private syncMotionPreference(): void {
    if (!this.live) {
      this.releaseMotionPreference();
      this.motionEnabled = false;
      return;
    }
    if (this.motionSubscription !== null || this.motionUnavailable) {
      return;
    }
    this.motionEnabled = markdownMotionEnabled();
    const listener: (enabled: boolean) => void = (enabled: boolean): void => {
      if (!this.alive || this.motionSubscription !== listener) {
        return;
      }
      this.motionEnabled = !enabled;
    };
    try {
      accessibility.onAnimationReduceStateChange(listener);
      this.motionSubscription = listener;
    } catch (error) {
      this.motionUnavailable = true;
      this.motionEnabled = false;
      hilog.warn(0xD5A0, 'ChatMarkdownBody', '无法监听减弱动态效果，按静态显示：%{public}s',
        (error as Error).message);
    }
  }

  private releaseMotionPreference(): void {
    const listener: ((enabled: boolean) => void) | null = this.motionSubscription;
    this.motionSubscription = null;
    if (listener !== null) {
      try {
        accessibility.offAnimationReduceStateChange(listener);
      } catch (error) {
        hilog.warn(0xD5A0, 'ChatMarkdownBody', '减弱动态效果监听释放失败：%{public}s',
          (error as Error).message);
      }
    }
  }

  @Monitor('bindingId', 'content', 'endReason', 'live')
  private onDisplayFrame(): void {
    this.consumeFrame();
  }

  private consumeFrame(): void {
    if (!this.alive) {
      return;
    }
    this.syncMotionPreference();
    if (this.failed && this.failedBindingId === this.bindingId) {
      return;
    }
    try {
      if (this.input === null) {
        this.input = new MarkdownDisplayBinding();
      }
      const source: string = this.content;
      const budget: ChatDisplayBudget | undefined = this.live ? this.displayBudget : undefined;
      const traceStart: number = CHAT_STREAM_TRACE_ENABLED || budget !== undefined ? Date.now() : 0;
      // U0 探针：live=false 首帧 Date.now 差分（metrics 只读不存快照——「不缓存解析产物」拍板口径零触）
      const parseProbeFirst: boolean = !this.live && !this.parseProbeLogged;
      const parseProbeStart: number = parseProbeFirst ? Date.now() : 0;
      const next: MarkdownSemanticSnapshot = this.input.consume(this.bindingId, source, this.endReason);
      if (parseProbeFirst) {
        this.parseProbeLogged = true;
        const probeMetrics: MarkdownDisplayMetrics | null = this.input.metrics();
        const syncParseMs: number = Date.now() - parseProbeStart;
        hilog.info(0xD5A0, 'ChatEnterProbe',
          'parseProbe bind=%{public}s len=%{public}d ms=%{public}d scanned=%{public}d',
          this.bindingId.substring(0, 8), next.sourceLength, syncParseMs,
          probeMetrics !== null ? probeMetrics.source.scannedUnits : -1);
      }
      const frame: MarkdownPresentationFrame = this.presentationTracker.consume(next, this.live);
      if (CHAT_STREAM_TRACE_ENABLED) {
        ChatStreamTrace.consume(frame.kind, next.sourceLength, Date.now() - traceStart,
          this.bindingId, next.token.generation, next.token.revision, next.token.documentId);
      }
      this.failed = false;
      this.failedBindingId = '';
      if (this.snapshot === next && frame.kind === 'unchanged') {
        return;
      }
      if (frame.kind === 'initial') {
        this.presentation = frame;
        this.displaySource = source;
        this.snapshot = next;
        budget?.record(this.bindingId, source.length, Date.now() - traceStart, Date.now());
        return;
      }
      const commit = (): void => {
        this.presentation = frame;
        this.displaySource = source;
        this.snapshot = next;
      };
      UIUtils.applySync(commit);
      budget?.record(this.bindingId, source.length, Date.now() - traceStart, Date.now());
    } catch (error) {
      if (this.input !== null) {
        this.input.dispose();
        this.input = null;
      }
      this.presentationTracker.dispose();
      this.presentationTracker = new MarkdownPresentationTracker();
      this.snapshot = null;
      this.displaySource = '';
      this.failedBindingId = this.bindingId;
      this.failed = true;
      hilog.error(0xD5A0, 'ChatMarkdownBody', '正文解析失败，已显示原文：%{public}s',
        (error as Error).message);
    }
  }

  aboutToDisappear(): void {
    this.alive = false;
    // 持让推迟未消费即销毁（转场窗内退出 / 重进 rebuild 全键变更重挂）：**不清**宿主骨架位
    // ——位由下一个渲染者接管（重挂批置位/解析、重进换源复位、运行态回收重建），残留自愈
    // 链全在；销毁直调清位会误清交叠新 body 的骨架位 = 重进「空气泡→气泡塌缩→内容」闪两
    // 次根因（2026-11-15 决明报障，原兜底删除，见字段注释）
    this.releaseMotionPreference();
    this.presentationTracker.dispose();
    if (this.input !== null) {
      this.input.dispose();
      this.input = null;
    }
    this.failedBindingId = '';
    // 不在销毁钩子写@Local。显示快照随组件树释放，输入持有已同步dispose。
  }

  build() {
    if (this.failed) {
      Column({ space: 6 }) {
        Text('正文暂时以原文显示')
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
        Text(this.content)
          .fontSize(MARKDOWN_BODY_FONT_SIZE)
          .lineHeight(MARKDOWN_BODY_LINE_HEIGHT)
          .fontColor($r('sys.color.font_primary'))
          .fontFamily(this.bodyFontFamily)
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    } else {
      MarkdownDocumentView({ snapshot: this.snapshot, source: this.displaySource, darkMode: this.darkMode,
        presentation: this.presentation, motionEnabled: this.motionEnabled, aiContent: this.aiContent,
        compact: this.compact, live: this.live, tailFirst: this.tailFirst,
        placeholder: this.placeholder,
        displayBudget: this.displayBudget,
        citations: this.citations,
        bodyFontFamily: this.bodyFontFamily, codeFontFamily: this.codeFontFamily,
        onAnchor: (id: string): void => { if (this.alive) { this.onAnchor(id); } },
        onCitation: (entry: number): void => { this.onCitation(entry); },
        onRevealDone: (): void => {
          // 持让推迟期拦截正文链回告：defer 期间本件给 MarkdownDocumentView 的 snapshot=null
          // 会走「首挂短文档回告」分支（progressive=false → scheduleRevealDone 下一帧即上行
          // onRevealDone）——不拦则骨架位一帧即清、持让窗剩约 380ms 显示空气泡。拦住后骨架
          // 保持到释放回调解析落定，由正文链按真实内容揭示完成回告清位。第二支放行「提前
          // 消费」：持让期 Monitor 参数变更触发直解析时本标记未翻但快照已落定，其完成回告
          // 必须照常透传（拦住会让已就绪正文卡在骨架下直到销毁）。defer 未消费即销毁时不清
          // 位——骨架位由重挂批/重进换源复位/运行态回收接管（销毁直调清位误清交叠骨架，
          // 2026-11-15 修，见字段注释）
          if (!this.transitionDeferred || this.snapshot !== null) {
            this.onRevealDone();
          }
        },
        onRevealPlaceholder: (placeholder: boolean): void => {
          if (this.alive) { this.onRevealPlaceholder(placeholder); }
        } })
    }
  }
}
