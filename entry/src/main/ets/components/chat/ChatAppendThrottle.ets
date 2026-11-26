// 追加发布的单槽合并器。档位约束相邻实际发布的最小间隔，不从每次空闲后的到达重新等整档。
// 首批及已过预算间隔的慢流投递到最近任务；同拍增量合并。
// ★ 契约改判（原「绝不按字符拆分二次揭示」退役）：发布侧改为有界平滑揭示（显示文本 =
// 权威累积的有界前缀，取值在 ChatStreamFlowCtrl.flushFrame），界公式三条：①单帧揭示量
// ≤ 1.5 × 上帧（移动平均防单拍跳变）；②收尾 400ms 预算排空（不一次性甩出）；③揭示间隔
// ≥ 67ms（REVEAL_INTERVAL_FLOOR_MS——1554 节「50ms 发布重复工作近翻倍」反例依据，当前
// 档位恒满足、显式化防后人调破）。
// 两自由度各归单源：本域管**间隔**（100/200/300 长度档 + 67ms 硬下限）；**步长**单源在
// ChatDisplayBudget.stepHint（原 interval() 间隔调节退役，禁两套调节叠在同一自由度上）。
// 长度档分档判据 = flush 回调返回的权威累积长度（勿以显示前缀长度分档——长文显示滞后时
// 显示长度低估规模，会把慢流误判快档）。
// 流首/换源清时钟与旧任务；终态由调用方覆盖权威全文并drop，位移动画不参与文本发布时序。

export type AppendFlush = (frameId: string, delta: string) => number;

export class ChatAppendThrottle {
  private static THROTTLE_MID_CHARS: number = 8 * 1024;   // ≥8K 字符进中档
  private static THROTTLE_SLOW_CHARS: number = 30 * 1024; // ≥30K 字符进慢档
  private static FLUSH_MS_FAST: number = 100;
  private static FLUSH_MS_MID: number = 200;
  private static FLUSH_MS_SLOW: number = 300;
  private static REVEAL_INTERVAL_FLOOR_MS: number = 67;   // 揭示间隔硬下限（1554 节反例依据）

  private nextFlushMs: number = ChatAppendThrottle.FLUSH_MS_FAST;
  private pending: Map<string, string> = new Map();
  private timer: number = -1;
  private lastFlushAt: number = -1;
  private scheduleEpoch: number = 0;
  private onFlush: AppendFlush;

  constructor(flush: AppendFlush) {
    this.onFlush = flush;
  }

  private interval(): number {
    return Math.max(this.nextFlushMs, ChatAppendThrottle.REVEAL_INTERVAL_FLOOR_MS);
  }

  // 流式增量入列（未知帧由回调侧守卫——本域不判）
  enqueue(frameId: string, delta: string): void {
    const prev: string | undefined = this.pending.get(frameId);
    this.pending.set(frameId, (prev ?? '') + delta);
    if (this.timer < 0) {
      const interval: number = this.interval();
      const elapsed: number = this.lastFlushAt < 0 ? interval :
        Math.max(0, Date.now() - this.lastFlushAt);
      const wait: number = Math.max(0, interval - elapsed);
      const epoch: number = this.scheduleEpoch;
      this.timer = setTimeout((): void => {
        if (epoch === this.scheduleEpoch) { this.flush(); }
      }, wait);
    }
  }

  // 终态权威清：frame.upsert 全量文本已含增量，未刷增量必须丢弃（防二次拼接重复）
  drop(frameId: string): void {
    this.pending.delete(frameId);
  }

  reset(): void {
    this.scheduleEpoch++;
    if (this.timer >= 0) { clearTimeout(this.timer); }
    this.timer = -1;
    this.pending.clear();
    this.lastFlushAt = -1;
    this.nextFlushMs = ChatAppendThrottle.FLUSH_MS_FAST;
  }

  private flush(): void {
    this.timer = -1;
    if (this.pending.size === 0) { return; }
    this.lastFlushAt = Date.now();
    const batch: Map<string, string> = this.pending;
    this.pending = new Map();
    let maxLen: number = 0;
    batch.forEach((delta: string, frameId: string): void => {
      const len: number = this.onFlush(frameId, delta);
      if (len > maxLen) {
        maxLen = len;
      }
    });
    // 下一档间隔：按本次 flush 回报的最长权威累积长度分档（揭示前缀会滞后低估规模，
    // 禁以显示前缀分档；回调返回值语义见 ChatStreamFlowCtrl.flushFrame）
    this.nextFlushMs = maxLen >= ChatAppendThrottle.THROTTLE_SLOW_CHARS ?
      ChatAppendThrottle.FLUSH_MS_SLOW :
      (maxLen >= ChatAppendThrottle.THROTTLE_MID_CHARS ? ChatAppendThrottle.FLUSH_MS_MID :
      ChatAppendThrottle.FLUSH_MS_FAST);
  }
}
