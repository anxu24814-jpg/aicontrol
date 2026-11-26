/**
 * 语义快照的稳定节点列表。排版与入场均为显示投影，不回调解析器或消息滚动控制器。
 * 原生动画只插值已提交布局；普通增长不改 Repeat 键，不保存高度或逐帧历史快照。
 */
import { FrameCallback, UIContext, UIUtils } from '@kit.ArkUI';
import { MarkdownNode, MarkdownSemanticSnapshot } from '../../../common/markdown/MarkdownSemanticModel';
import { ChatDisplayBudget } from '../../../common/chat/ChatDisplayBudget';
// DS 来源角标区间类型（S3③ 最小穿透——只透传类型与值，本件不判读）
import { DsCitationSpan } from '../ChatMessageCompose';
import { MarkdownPresentationFrame, markdownBlockGap } from '../../../common/markdown/MarkdownPresentation';
import { FONT_FAMILY_MONO, FONT_FAMILY_SYSTEM } from '../../../common/ChatFont';
import { MarkdownBlockView } from './MarkdownBlockView';
import { LONG_MSG_COLLAPSE_CHARS } from './MarkdownScrollableBlock';
import { MarkdownAnchorEntry, MarkdownReferenceJump, markdownAnchorEntries, markdownAnchorId, markdownAnchorTarget,
  markdownHasNode } from '../../../common/markdown/MarkdownNavigation';

// ── 长消息渐进揭示 ──
// 为什么：非流式长正文整棵块树一次同步建树（真机探针：121~189 块 1.2~3.2 秒），期间主线程
// 占满、动画与手势停摆。本机制拆成「首屏块立即出内容 + 其余按全局帧预算逐块追加」，总耗
// 时不变但每帧只付固定块数。服务对象 = 源字符数超折叠阈值 LONG_MSG_COLLAPSE_CHARS 的超长
// 正文（与折叠门同源同值）；常规消息首帧全量 = 进会即终态。★ 历史修正：原 8ms 预算循环
// 只计时度量不建块，分帧实际失效；现为固定块数配额由全局调度器逐帧派发，多文档共享每帧
// 预算。★ 尾先（tailFirst）：底锚进页的末条消息先建最后 FIRST_BLOCKS 块（首屏直接看到
// 回答末尾），更早的块逐帧从上方补入；从收起条展开不走尾先（宿主传 false）。只作用于非
// 流式正文；流式有自己的增量揭示链。总开关（kill-switch）：false = 一次全量建树。
const MARKDOWN_PROGRESSIVE_REVEAL_ENABLED: boolean = true;
const MD_PROGRESSIVE_MIN_NODES: number = 24;       // 低于该块数不启用（短消息一次建完更省）
const MD_PROGRESSIVE_FIRST_BLOCKS: number = 8;     // 首屏先建的块数（约 0.15~0.4 秒可见内容）
// 每帧全局块预算（跨文档合计）；真机手感不对只改这一个数。
const MD_PROGRESSIVE_FRAME_BLOCKS: number = 2;
// 滚动暂停揭示（kill switch）：true = 列表滚动期间暂停全部揭示任务派发（建块成本不与
// 滚动争帧、滚动中挂载的长行先出骨架），停止后续跑；false = 旧行为
const MARKDOWN_REVEAL_PAUSE_ON_SCROLL_ENABLED: boolean = true;

class MarkdownAnchorFrame extends FrameCallback {
  private callback: (() => void) | null;
  constructor(callback: () => void) { super(); this.callback = callback; }
  cancel(): void { this.callback = null; }
  onIdle(_time: number): void {
    const callback: (() => void) | null = this.callback;
    this.callback = null;
    if (callback !== null) { callback(); }
  }
}

// 渐进揭示任务：step 返回 true = 本任务已结束（全部块已加入或被取消）。
class MarkdownRevealTask {
  private step: (budget: number) => boolean;
  private alive: boolean = true;

  constructor(step: (budget: number) => boolean) {
    this.step = step;
  }

  cancel(): void {
    this.alive = false;
  }

  isAlive(): boolean {
    return this.alive;
  }

  run(budget: number): boolean {
    if (!this.alive) {
      return true;
    }
    return this.step(budget);
  }
}

class MarkdownRevealFrame extends FrameCallback {
  private callback: (() => void) | null;

  constructor(callback: () => void) {
    super();
    this.callback = callback;
  }

  cancel(): void {
    this.callback = null;
  }

  onFrame(_time: number): void {
    const callback: (() => void) | null = this.callback;
    this.callback = null;
    if (callback !== null) {
      callback();
    }
  }
}

// 全局揭示调度器（模块级单例）：多条长消息共享每帧块预算（避免各文档同帧叠加）；队列空
// 即停帧，滚动期 pause/resume。寿命匹配：只持任务对象不持组件引用——文档销毁必须注销。
class MarkdownRevealScheduler {
  private tasks: MarkdownRevealTask[] = [];
  private idleListeners: Set<() => void> = new Set<() => void>();
  private frame: MarkdownRevealFrame | null = null;
  private cursor: number = 0;
  private ui: UIContext | null = null;
  private idleNotified: boolean = false;
  private paused: boolean = false;

  register(task: MarkdownRevealTask, ui: UIContext): void {
    if (this.tasks.indexOf(task) >= 0) {
      return;
    }
    if (this.tasks.length === 0) {
      this.idleNotified = false;
    }
    this.ui = ui;
    this.tasks.push(task);
    this.schedule();
  }

  unregister(task: MarkdownRevealTask): void {
    const index: number = this.tasks.indexOf(task);
    if (index < 0) {
      return;
    }
    this.tasks.splice(index, 1);
    if (index < this.cursor) {
      this.cursor--;
    }
    if (this.tasks.length === 0) {
      this.cursor = 0;
      this.cancelFrame();
      this.notifyIdle();
    }
  }

  isRunning(): boolean {
    return this.tasks.length > 0;
  }

  isPaused(): boolean {
    return this.paused;
  }

  // 滚动开始：停在途帧、停止派发（任务进度保留，UI 不再被揭示建块挤占帧预算）
  pause(): void {
    if (this.paused) {
      return;
    }
    this.paused = true;
    this.cancelFrame();
  }

  // 滚动停止：恢复派发（队列非空才重排；空队列零动作）
  resume(): void {
    if (!this.paused) {
      return;
    }
    this.paused = false;
    this.schedule();
  }

  // 揭示队列清空回调（进页预创建行数延迟恢复消费；一次性订阅由调用方自行释放）
  onIdle(listener: () => void): () => void {
    this.idleListeners.add(listener);
    return (): void => {
      this.idleListeners.delete(listener);
    };
  }

  private schedule(): void {
    if (this.paused || this.frame !== null || this.tasks.length === 0 || this.ui === null) {
      return;
    }
    const frame: MarkdownRevealFrame = new MarkdownRevealFrame((): void => {
      if (this.frame === frame) {
        this.pump();
      }
    });
    this.frame = frame;
    try {
      this.ui.postFrameCallback(frame);
    } catch (_error) {
      frame.cancel();
      this.frame = null;
    }
  }

  private pump(): void {
    this.frame = null;
    if (this.paused) {
      return; // 暂停拍：迟到帧不派发（resume 已重排）
    }
    let budget: number = MD_PROGRESSIVE_FRAME_BLOCKS;
    while (budget > 0 && this.tasks.length > 0) {
      if (this.cursor >= this.tasks.length) {
        this.cursor = 0;
      }
      const task: MarkdownRevealTask = this.tasks[this.cursor];
      const done: boolean = task.run(1);
      budget--;
      if (done || !task.isAlive()) {
        this.tasks.splice(this.cursor, 1);
        if (this.cursor >= this.tasks.length) {
          this.cursor = 0;
        }
      } else {
        this.cursor++;
      }
    }
    if (this.tasks.length === 0) {
      this.cancelFrame();
      this.notifyIdle();
      return;
    }
    this.schedule();
  }

  private cancelFrame(): void {
    this.frame?.cancel();
    this.frame = null;
  }

  private notifyIdle(): void {
    if (this.idleNotified) {
      return;
    }
    this.idleNotified = true;
    if (this.idleListeners.size === 0) {
      return;
    }
    const listeners: (() => void)[] = [];
    this.idleListeners.forEach((listener: () => void): void => {
      listeners.push(listener);
    });
    for (const listener of listeners) {
      listener();
    }
  }
}

const markdownRevealScheduler: MarkdownRevealScheduler = new MarkdownRevealScheduler();

// 滚动暂停揭示开关出口（判据见常量区 kill switch 行）；kill switch 关 = 两函数空转 = 旧行为。
export function pauseMarkdownReveal(): void {
  if (!MARKDOWN_REVEAL_PAUSE_ON_SCROLL_ENABLED) {
    return;
  }
  markdownRevealScheduler.pause();
}

export function resumeMarkdownReveal(): void {
  if (!MARKDOWN_REVEAL_PAUSE_ON_SCROLL_ENABLED) {
    return;
  }
  markdownRevealScheduler.resume();
}

// 等揭示队列清空再执行（有界兜底）：空闲 = 立即执行，否则订阅空闲回调 + 兜底计时器，返回
// 释放函数（幂等）。进页预创建行数恢复消费——不落进 ChatPageContent（该件已越 1200 硬线）。
export function whenMarkdownRevealIdle(onIdle: () => void, fallbackMs: number): () => void {
  if (!markdownRevealScheduler.isRunning()) {
    onIdle();
    return (): void => {};
  }
  let done: boolean = false;
  let timer: number = -1;
  let releaseIdle: () => void = (): void => {};
  const finish = (): void => {
    if (done) {
      return;
    }
    done = true;
    releaseIdle();
    if (timer >= 0) {
      clearTimeout(timer);
      timer = -1;
    }
    onIdle();
  };
  releaseIdle = markdownRevealScheduler.onIdle((): void => {
    finish();
  });
  if (fallbackMs > 0) {
    timer = setTimeout((): void => {
      timer = -1;
      finish();
    }, fallbackMs);
  }
  return (): void => {
    if (done) {
      return;
    }
    done = true;
    releaseIdle();
    if (timer >= 0) {
      clearTimeout(timer);
      timer = -1;
    }
  };
}

@ComponentV2
export struct MarkdownDocumentView {
  @Param snapshot: MarkdownSemanticSnapshot | null = null;
  @Param source: string = '';
  @Param darkMode: boolean = false;
  @Param presentation: MarkdownPresentationFrame = { kind: 'initial', enteringIds: [] };
  @Param motionEnabled: boolean = false;
  @Param aiContent: boolean = true;
  @Param compact: boolean = false;
  // 流式态标量：live = 行仍在流式输出，沿正文链下行至 MarkdownCodeText 的降载判据；缺省
  // false = 非流式（阅读半模态/预览/历史回放等旁路消费点零改动即安全）。
  @Param live: boolean = false;
  // 尾先揭示（判据见常量区 ★ 尾先）：先建最后 FIRST_BLOCKS 块再逐帧从上方补入；占位形态恒头先无观感差。
  @Param tailFirst: boolean = false;
  // 占位揭示：true = 首帧不出可见块（revealLimit 从 0 起步），由全局调度器逐帧在 opacity 0
  // 的正文层背后建块，宿主行内只显示静态骨架，揭示完成由 onRevealDone 一次性显现。写点 =
  // 宿主展开动作置位（ChatMessageItem）或滚动暂停期挂载自行判定。
  @Param placeholder: boolean = false;
  // 显示成本预算：行级预算实例沿同一链下行至 MarkdownCodeText 供 build 期高亮耗时补采样；
  // 缺省 undefined = 不采样。
  @Param displayBudget: ChatDisplayBudget | undefined = undefined;
  // 消息字体家族串：V1 宿主换算后沿正文链下行，各层只透传不改写
  //（默认参 = 系统默认字体与通用等宽，与未配置逐字同）
  @Param bodyFontFamily: string = FONT_FAMILY_SYSTEM;
  @Param codeFontFamily: string = FONT_FAMILY_MONO;
  // DS 来源角标（S3③ 最小穿透，缺省空数组零行为变化）：随正文链下传至行内视图；本件
  // 不判读（白名单缺口登记——S3 施工面按行内视图最小穿透处置，笔记与交付回复申报）
  @Param citations: DsCitationSpan[] = [];

  @Computed
  get compactParagraph(): boolean {
    return this.compact && this.visibleNodes.length === 1 && this.visibleNodes[0].kind === 'paragraph';
  }
  @Event onAnchor: (id: string) => void = (_id: string): void => {};
  // 角标点击上行（S3③ 最小穿透——行内视图直发，不进 navigate 文档内锚点解析）
  @Event onCitation: (entry: number) => void = (_entry: number): void => {};
  // 渐进揭示完成（或无需揭示）上行：宿主据此解除「展开中」静默位；组件回收时也发一次，
  // 防揭示中途滚离后标记残留
  @Event onRevealDone: () => void = (): void => {};
  // 占位形态上行：滚动暂停期挂载的长正文由本件自行进入占位，上行让宿主同步置占位标记
  //（骨架/不透明度/行高静默判据）；仅判定进入占位时发一次，揭示完成经 onRevealDone 清位。
  @Event onRevealPlaceholder: (placeholder: boolean) => void = (_placeholder: boolean): void => {};
  @Local private referenceJump: MarkdownReferenceJump = { referenceId: 0, serial: 0 };
  // 已揭示块数（-1 = 全量/非渐进态；≥0 = 渐进态下当前已建块数）
  @Local private revealLimit: number = -1;
  private lastReferences: Map<string, number> = new Map<string, number>();
  private namespace: string = '';
  private alive: boolean = false;
  private pendingFrame: MarkdownAnchorFrame | null = null;
  // 渐进揭示任务（全局调度器持有；本件完成/销毁时注销）
  private revealTask: MarkdownRevealTask | null = null;
  private revealDoneFrame: MarkdownAnchorFrame | null = null;
  private revealInitialized: boolean = false;
  // 已启动过揭示的文档身份（快照 token 派生的 namespace）：同一文档的后续快照不重新收起，
  // 避免流式收尾/终态落定把已全量显示的正文闪回 8 块
  private revealDocumentKey: string = '';

  aboutToAppear(): void {
    this.alive = true;
    this.syncNamespace();
    // 快照监听不覆盖首挂初值——首次进入也要决定是否渐进
    this.resetProgressiveReveal();
  }
  aboutToDisappear(): void {
    this.alive = false;
    // 仅在确有揭示在途/达成回告待发时上行（普通卸载不写父状态）
    const notifyDone: boolean = this.revealLimit >= 0 || this.revealTask !== null ||
      this.revealDoneFrame !== null;
    this.pendingFrame?.cancel();
    this.pendingFrame = null;
    this.cancelRevealTask();
    this.revealDoneFrame?.cancel();
    this.revealDoneFrame = null;
    this.lastReferences.clear();
    if (notifyDone) {
      // 组件回收即视为揭示结束（宿主解除静默位；消息对象随会话复用时不残留）
      this.onRevealDone();
    }
  }

  @Monitor('snapshot')
  private onSnapshotChanged(): void {
    this.syncNamespace();
    this.resetProgressiveReveal();
  }

  private syncNamespace(): void {
    const current: string = this.snapshot === null ? '' : markdownAnchorId(this.snapshot.token, 0);
    if (current !== this.namespace) {
      this.namespace = current;
      this.lastReferences.clear();
      this.pendingFrame?.cancel();
      this.pendingFrame = null;
      this.referenceJump = { referenceId: 0, serial: this.referenceJump.serial + 1 };
    }
  }

  @Computed
  get anchors(): MarkdownAnchorEntry[] {
    return this.snapshot === null ? [] : markdownAnchorEntries(this.snapshot.nodes);
  }

  private navigate(destination: string): void {
    if (this.snapshot === null || !this.alive) { return; }
    this.syncNamespace();
    let target: string = destination;
    if (destination.startsWith('reference:')) {
      const reference: MarkdownAnchorEntry | undefined = this.anchors.find((entry: MarkdownAnchorEntry): boolean =>
        entry.destination === destination);
      if (reference?.footnote !== undefined) {
        this.lastReferences.set(reference.footnote, reference.number);
        target = reference.footnote;
      }
    } else if (destination.startsWith('back:')) {
      const referenceId: number = this.lastReferences.get(destination.substring(5)) ?? 0;
      if (referenceId > 0) {
        target = 'reference:' + referenceId.toString();
        // 表格先切到原引用的行列/单格部分，再在真实下一帧布局后读其锚点几何。
        UIUtils.applySync((): void => {
          this.referenceJump = { referenceId: referenceId, serial: this.referenceJump.serial + 1 };
        });
      }
    }
    const id: number = markdownAnchorTarget(this.anchors, target);
    if (id > 0 && markdownHasNode(this.snapshot.nodes, id)) {
      const anchor: string = markdownAnchorId(this.snapshot.token, id);
      this.pendingFrame?.cancel();
      if (destination.startsWith('back:') && target.startsWith('reference:')) {
        const namespace: string = this.namespace;
        const revision: number = this.snapshot.token.revision;
        const frame: MarkdownAnchorFrame = new MarkdownAnchorFrame((): void => {
          if (this.alive && this.namespace === namespace && this.pendingFrame === frame && this.snapshot !== null &&
            this.snapshot.token.revision === revision && markdownAnchorId(this.snapshot.token, id) === anchor &&
            markdownHasNode(this.snapshot.nodes, id)) {
            this.pendingFrame = null;
            this.onAnchor(anchor);
          }
        });
        this.pendingFrame = frame;
        this.getUIContext().postFrameCallback(frame);
      } else {
        this.pendingFrame = null;
        this.onAnchor(anchor);
      }
    } else {
      this.getUIContext().getPromptAction().showToast({ message: '未找到此文档内的目标' });
    }
  }

  @Computed
  get visibleNodes(): MarkdownNode[] {
    if (this.snapshot === null) {
      return [];
    }
    return this.snapshot.nodes.filter((node: MarkdownNode): boolean =>
      node.kind !== 'blank' && node.kind !== 'referenceDefinition');
  }

  // 渐进态实际渲染窗口的起始下标（尾先 = 从末尾往前留 revealLimit 块；头先 = 0）
  @Computed
  get shownStart(): number {
    const all: MarkdownNode[] = this.visibleNodes;
    if (this.revealLimit < 0 || this.revealLimit >= all.length) {
      return 0;
    }
    return this.tailFirst ? all.length - this.revealLimit : 0;
  }

  // 渐进态实际渲染的块（非渐进态 = 全量）。头先 = 前缀；尾先 = 后缀。窗口内块保持
  // visibleNodes 的原始下标（build 里按 shownStart 还原），补入更早块时既有块参数不变。
  @Computed
  get shownNodes(): MarkdownNode[] {
    const all: MarkdownNode[] = this.visibleNodes;
    if (this.revealLimit < 0 || this.revealLimit >= all.length) {
      return all;
    }
    const start: number = this.tailFirst ? all.length - this.revealLimit : 0;
    return all.slice(start, start + this.revealLimit);
  }

  // 快照变化/首挂时决定揭示形态：流式（live）恒全量（流式有自己的增量揭示链）；长正文
  // 判据与首帧形态见常量区；同一文档的后续快照只换内容不重新收起（见 revealDocumentKey）；
  // 占位形态首帧不出可见块（revealLimit=0 起步），全部块建完再一次性显现；非占位保持
  // 首屏 8 块可见渐进。
  private resetProgressiveReveal(): void {
    const firstMount: boolean = !this.revealInitialized;
    this.revealInitialized = true;
    const documentKey: string = this.namespace;
    const documentChanged: boolean = this.revealDocumentKey !== documentKey;
    this.revealDocumentKey = documentKey;
    if (!firstMount && !documentChanged) {
      return;
    }
    this.cancelRevealTask();
    const total: number = this.visibleNodes.length;
    // 字符门槛判据（见方法头注释）：仅超折叠阈值的长正文分帧
    const sourceLength: number = this.snapshot === null ? 0 : this.snapshot.sourceLength;
    const progressive: boolean = MARKDOWN_PROGRESSIVE_REVEAL_ENABLED && !this.live &&
      total > MD_PROGRESSIVE_MIN_NODES && sourceLength > LONG_MSG_COLLAPSE_CHARS;
    if (!progressive) {
      this.revealLimit = -1;
      // 首挂/新文档（短正文也可能带展开中标记）需要回告宿主；同一文档的后续快照不回告
      this.scheduleRevealDone();
      return;
    }
    const placeholderMode: boolean = this.placeholder || markdownRevealScheduler.isPaused();
    this.revealLimit = placeholderMode ? 0 : Math.min(MD_PROGRESSIVE_FIRST_BLOCKS, total);
    if (placeholderMode) {
      // 滚动暂停期挂载 = 本件自行进入占位（宿主展开动作已在挂载前置位，重复上行幂等）
      this.onRevealPlaceholder(true);
    }
    this.startRevealTask();
  }

  private startRevealTask(): void {
    if (this.revealTask !== null) {
      return;
    }
    const task: MarkdownRevealTask = new MarkdownRevealTask((budget: number): boolean =>
      this.stepReveal(budget));
    this.revealTask = task;
    markdownRevealScheduler.register(task, this.getUIContext());
  }

  private cancelRevealTask(): void {
    const task: MarkdownRevealTask | null = this.revealTask;
    if (task === null) {
      return;
    }
    this.revealTask = null;
    task.cancel();
    markdownRevealScheduler.unregister(task);
  }

  // 全局调度器每帧派发一次；budget = 本次允许追加的块数。这里只改 revealLimit，建块发生
  // 在状态写入后的渲染帧里——每帧只新增固定块数，主线程不会再被单次全量补齐占满。
  private stepReveal(budget: number): boolean {
    if (!this.alive || this.revealLimit < 0) {
      return true;
    }
    const total: number = this.visibleNodes.length;
    if (this.revealLimit >= total) {
      this.finishReveal();
      return true;
    }
    const next: number = Math.min(total, this.revealLimit + Math.max(1, budget));
    this.revealLimit = next;
    if (next >= total) {
      this.finishReveal();
      return true;
    }
    return false;
  }

  private finishReveal(): void {
    this.revealLimit = -1;
    // 任务由调度器在本次 run 返回 true 后移除；此处只清本件引用，避免销毁钩子二次回告
    this.revealTask = null;
    if (this.alive) {
      this.onRevealDone();
    }
  }

  // 延后一帧回告（首挂 aboutToAppear 内直接写父状态会撞构建期）
  private scheduleRevealDone(): void {
    if (!this.alive) {
      return;
    }
    this.revealDoneFrame?.cancel();
    const frame: MarkdownAnchorFrame = new MarkdownAnchorFrame((): void => {
      if (this.revealDoneFrame !== frame) {
        return;
      }
      this.revealDoneFrame = null;
      if (this.alive) {
        this.onRevealDone();
      }
    });
    this.revealDoneFrame = frame;
    this.getUIContext().postFrameCallback(frame);
  }

  private nodeKey(node: MarkdownNode): string {
    if (this.snapshot === null) {
      return node.id.toString();
    }
    const documentId: string = this.snapshot.token.documentId;
    return documentId.length.toString() + ':' + documentId + ':' +
      this.snapshot.token.generation.toString() + ':' + node.id.toString();
  }

  private blockGap(index: number): number {
    return markdownBlockGap(this.visibleNodes[index], index > 0 ? this.visibleNodes[index - 1] : null);
  }

  build() {
    Column() {
      if (this.snapshot !== null) {
        Repeat<number>(this.shownNodes.map((node: MarkdownNode): number => node.id))
          .each((row: RepeatItem<number>) => {
            // 原始下标 = shownStart + row.index：尾先补入更早块时既有块的 index/gap/documentTail
            // 不变，避免整行重渲（UI 语法内不能声明局部变量，四处表达式同位展开）
            MarkdownBlockView({
              node: this.shownNodes[row.index],
              index: this.shownStart + row.index,
              token: this.snapshot!.token,
              source: this.source,
              headingEntries: this.snapshot!.outline,
              darkMode: this.darkMode,
              gap: this.blockGap(this.shownStart + row.index),
              entering: this.presentation.enteringIds.indexOf(this.shownNodes[row.index].id) >= 0,
              motionEnabled: this.motionEnabled,
              aiContent: this.aiContent,
              compact: this.compactParagraph,
              live: this.live,
              displayBudget: this.displayBudget,
              anchors: this.anchors,
              referenceJump: this.referenceJump,
              bodyFontFamily: this.bodyFontFamily,
              codeFontFamily: this.codeFontFamily,
              // 文档级终态随快照下行（自动折叠双层口径的文档面；本件不判读）
              bodyEndReason: this.snapshot!.endReason,
              // 文档尾块：最后一个可见节点 = 文本仍可能在增长（渐进窗口），供 HTML 投影护栏
              // 禁渲染；本件只判位不判读语义。
              documentTail: this.shownStart + row.index === this.visibleNodes.length - 1,
              citations: this.citations,
              onNavigate: (destination: string): void => { this.navigate(destination); },
              onCitationTap: (entry: number): void => { this.onCitation(entry); }
            })
              .transition(TransitionEffect.IDENTITY)
          })
          .key((_id: number, index: number): string => this.nodeKey(this.shownNodes[index]))
      }
    }
    .width(this.compactParagraph ? undefined : '100%')
    .alignItems(HorizontalAlign.Start)
  }
}
