// Cube 三频道节流编排的 aicontrol 桥（2026-09-02 阶段 2 新建）：把 chatcube ChatViewModel
// 的三 flusher 结构（firstChunk / content / reasoning 三通道 + 首块分流 + 流末吐完释放——
// 源 viewmodels/ChatViewModel.ets L168-242 的 createStreamFlusher / resetStreamFlushers /
// throttleStreamContentChunk / flushStreamContentFlushers 四方法族）封装成实验引擎控制件
// （2026-09-18 前为 ChatSendCtrl 实验分支，拆分后 = CubeEngineCtrl）可持有的单一编排件。
// MIT 溯源与适配声明见 DisplaySyncTypewriter.ets 头注释。
// 改动点（对照上游，台账登记）：
// 1. 三参数方法族 → 类封装（首块分流状态内聚；喂入/吐完/释放三入口语义等价）；
// 2. 上游兜底 ThrottleUtil(150ms 时间片) 未随迁——上游拿不到 UIContext 时降级 V1；本工程
//    ChatSendCtrl 由 ChatPage 持有、UIContext 恒可达（refs 闭包延迟求值），兜底分支由
//    ChatSendCtrl 退化原生 ChatAppendThrottle 承担（既有资产，不引入第二套时间片节流器）；
// 3. emit 回调消费方语义 = 揭示指针（CubeEngineCtrl.revealChunk 持 revealed 计数，
//    msg.text = full.substring(0, revealed)）——aicontrol 渲染栈是全量覆盖式，非上游
//    @Trace text += 的 append 式；打字机逐字 emit 时揭示指针逐步推进，效果等价。
// 生命周期（TypewriterFlusher.reset 后不可复用）：一轮请求 = 一个实例；工具轮每轮新建
// （CubeEngineCtrl.rebuild 是唯一构造点）。
import { UIContext } from '@kit.ArkUI';
import { StreamFlusher, TypewriterFlusher } from './DisplaySyncTypewriter';

export class CubeStreamFlushers {
  // 首块专用通道（上游语义：首块经独立 flusher 立即上屏，不与后续正文共用积压节奏）
  private firstChunkFlusher: StreamFlusher;
  // 正文通道（首块之后）
  private contentFlusher: StreamFlusher;
  // 思考链通道（独立节奏，与正文互不积压）
  private reasoningFlusher: StreamFlusher;
  // 已收到正文首块（emit 时置位——上游 throttleStreamContentChunk 同款时序）
  private hasFirstChunk: boolean = false;
  // 揭示回调（CubeEngineCtrl.revealChunk 绑定；频道内不持消息引用，frameId 由消费方闭包持有）
  private onContentReveal: (chunk: string) => void;
  private onReasoningReveal: (chunk: string) => void;

  constructor(uiContext: UIContext, onContentReveal: (chunk: string) => void,
    onReasoningReveal: (chunk: string) => void) {
    this.firstChunkFlusher = new TypewriterFlusher(uiContext);
    this.contentFlusher = new TypewriterFlusher(uiContext);
    this.reasoningFlusher = new TypewriterFlusher(uiContext);
    this.onContentReveal = onContentReveal;
    this.onReasoningReveal = onReasoningReveal;
  }

  // 正文增量（首块自动分流首块通道；isFirst 快照在闭包内——emit 时才置位，与上游一致）。
  // ★ 思考保序（阶段 4 补，Cube flushPendingReasoningBeforeContent 语义）：首块正文入队前
  // 先冲思考频道——思考块在上、正文在下，思考积压未吐完就开正文会出现「下文先出」乱序感；
  // 只在首块冲（思考流是前缀式，正文开始 = 思考已全部到达；后续冲恒空幂等，且避开
  // displaySync stop 后重启不可靠的实测坑——引入件源码 L202-207 注释）
  feedContent(delta: string): void {
    const isFirst: boolean = !this.hasFirstChunk;
    if (isFirst) {
      this.reasoningFlusher.flush(this.onReasoningReveal);
    }
    const flusher: StreamFlusher = isFirst ? this.firstChunkFlusher : this.contentFlusher;
    flusher.throttle(delta, (throttled: string): void => {
      this.onContentReveal(throttled);
      if (isFirst) {
        this.hasFirstChunk = true;
      }
    });
  }

  // 思考链增量（无首块分流——上游 reasoning 独立通道同款）
  feedReasoning(delta: string): void {
    this.reasoningFlusher.throttle(delta, this.onReasoningReveal);
  }

  // 流末收口：三频道同步吐完（硬约束 4：先吐完再落库）→ reset 释放（硬约束 3：
  // complete 路径必 dispose；reset 后实例不可复用）
  finish(): void {
    this.firstChunkFlusher.flush(this.onContentReveal);
    this.contentFlusher.flush(this.onContentReveal);
    this.reasoningFlusher.flush(this.onReasoningReveal);
    this.reset();
  }

  // 纯释放（cancel/销毁路径专用——不吐剩余字符，静默丢弃；与 finish 的区别在上游对应
  // stopGeneration 直接 cleanup 不 flush 的分叉）
  reset(): void {
    this.firstChunkFlusher.reset();
    this.contentFlusher.reset();
    this.reasoningFlusher.reset();
    this.hasFirstChunk = false;
  }
}
