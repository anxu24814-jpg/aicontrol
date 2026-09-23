// 追加帧合并缓冲 + 节流自适应分档（二四〇改自 ChatDataSource 域级拆分——数据源超
// 线红线，本次改动域独立成文件；缓冲本体 = 二三五改，节流分档 = 路线图 §8.2-4a
// 阶段 1 ①）。
// 职责：流式 append 增量入列，按档位间隔定时批量刷入——**写入语义在回调侧**（数据
// 源注入 flush 回调，本域零数据源依赖，只管节奏）。回调返回写入后的消息文本长度，
// 用于下一档间隔判定。
// 节流分档（4a 阶段 1 ①）：@lidary/markdown 每帧渲染成本 ∝ 全文长（全量重解析 +
// tokenList 全量替换），长文降频（10→5→3.3 次/秒）线性换流畅。档位按 flush 回调回报
// 的最长消息字符数（UTF-16 码元）判定，多帧并发取最大档。阈值/间隔 = 调参位，真机
// 按卡顿观测调整。终态 upsert 全量权威（drop 清该帧未刷增量防二次拼接）；会话切换/
// 全量重建 reset（清缓冲 + 快档复位；在飞定时器不清——自然到期回调空转，与二三五改
// 「页面销毁不 dispose」同口径）。

export type AppendFlush = (frameId: string, delta: string) => number;

export class ChatAppendThrottle {
  private static THROTTLE_MID_CHARS: number = 8 * 1024;   // ≥8K 字符进中档
  private static THROTTLE_SLOW_CHARS: number = 30 * 1024; // ≥30K 字符进慢档
  private static FLUSH_MS_FAST: number = 100;             // 短文（二三五改原定值）
  private static FLUSH_MS_MID: number = 200;
  private static FLUSH_MS_SLOW: number = 300;

  private nextFlushMs: number = ChatAppendThrottle.FLUSH_MS_FAST;
  private pending: Map<string, string> = new Map();
  private timer: number = -1;
  private onFlush: AppendFlush;

  constructor(flush: AppendFlush) {
    this.onFlush = flush;
  }

  // 流式增量入列（未知帧由回调侧守卫——本域不判）
  enqueue(frameId: string, delta: string): void {
    const prev: string | undefined = this.pending.get(frameId);
    this.pending.set(frameId, (prev ?? '') + delta);
    if (this.timer < 0) {
      this.timer = setTimeout((): void => {
        this.flush();
      }, this.nextFlushMs);
    }
  }

  // 终态权威清：frame.upsert 全量文本已含增量，未刷增量必须丢弃（防二次拼接重复）
  drop(frameId: string): void {
    this.pending.delete(frameId);
  }

  // 会话切换/全量重建复位：清缓冲 + 快档（旧会话增量不跨会话 flush；在飞定时器不清，
  // 自然到期时空 pending 回调空转——维持二三五改既有语义）
  reset(): void {
    this.pending.clear();
    this.nextFlushMs = ChatAppendThrottle.FLUSH_MS_FAST;
  }

  private flush(): void {
    this.timer = -1;
    let maxLen: number = 0;
    this.pending.forEach((delta: string, frameId: string): void => {
      const len: number = this.onFlush(frameId, delta);
      if (len > maxLen) {
        maxLen = len;
      }
    });
    this.pending.clear();
    // 下一档间隔：按本次 flush 后最长消息文本分档（= 下一次渲染面对的全文规模）
    this.nextFlushMs = maxLen >= ChatAppendThrottle.THROTTLE_SLOW_CHARS ?
      ChatAppendThrottle.FLUSH_MS_SLOW :
      (maxLen >= ChatAppendThrottle.THROTTLE_MID_CHARS ? ChatAppendThrottle.FLUSH_MS_MID :
      ChatAppendThrottle.FLUSH_MS_FAST);
  }
}
