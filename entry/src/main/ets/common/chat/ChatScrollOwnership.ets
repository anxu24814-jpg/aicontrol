/** 用户拖动、原生惯性与自动跟随的控制权；只记本手势事实，不发滚动或持UI回调。 */
type ChatUserScrollPhase = 'idle' | 'moving' | 'flinging' | 'stopped';
type ChatUserScrollIntent = 'none' | 'review' | 'towardEnd';

const CHAT_DRAG_SLOP_VP: number = 2;
const CHAT_REVERSE_SLOP_VP: number = 8;

export class ChatScrollOwnership {
  private follow: boolean = true;
  private pressed: boolean = false;
  private phase: ChatUserScrollPhase = 'idle';
  private intent: ChatUserScrollIntent = 'none';
  private travel: number = 0;
  private extreme: number = 0;
  private reachedEnd: boolean = false;

  phaseName(): string { return this.phase; }
  isFollowing(): boolean { return this.follow; }
  isTouching(): boolean { return this.pressed; }
  userOwnsScroll(): boolean { return this.pressed || this.phase !== 'idle'; }
  needsRelease(): boolean { return !this.pressed && this.phase === 'stopped'; }

  private clearGesture(): void {
    this.phase = 'idle';
    this.intent = 'none';
    this.travel = 0;
    this.extreme = 0;
    this.reachedEnd = false;
  }

  reset(follow: boolean, preserveTouch: boolean = false): void {
    this.follow = follow;
    if (!preserveTouch) { this.pressed = false; }
    this.clearGesture();
  }

  touchStart(): boolean {
    if (this.pressed) { return false; }
    this.pressed = true;
    this.clearGesture();
    return true;
  }

  touchEnd(cancelled: boolean): void {
    this.pressed = false;
    if (cancelled) { this.clearGesture(); }
  }

  review(): void {
    this.follow = false;
    this.intent = 'review';
    this.reachedEnd = false;
  }

  drag(distance: number): void {
    if (!Number.isFinite(distance) || Math.abs(distance) < 0.001) { return; }
    if (this.phase === 'idle') { this.clearGesture(); }
    this.phase = 'moving';
    this.travel += distance;
    if (this.intent === 'towardEnd') {
      this.extreme = Math.max(this.extreme, this.travel);
      if (this.extreme - this.travel > CHAT_DRAG_SLOP_VP) {
        this.review();
        this.extreme = this.travel;
      }
    } else if (this.intent === 'review') {
      this.extreme = Math.min(this.extreme, this.travel);
      if (this.travel - this.extreme > CHAT_REVERSE_SLOP_VP) {
        this.intent = 'towardEnd';
        this.extreme = this.travel;
      }
    } else if (Math.abs(this.travel) > CHAT_DRAG_SLOP_VP) {
      this.follow = false;
      this.intent = this.travel < 0 ? 'review' : 'towardEnd';
      this.extreme = this.travel;
    }
  }

  continueMotion(): void {
    // 惯性/回弹只延长用户占用，不把速度正负当成一次新的主动回底。
    if (this.phase !== 'flinging') { this.phase = 'moving'; }
  }

  stopDragging(willFling: boolean): void {
    if (willFling || this.phase !== 'idle') { this.phase = willFling ? 'flinging' : 'stopped'; }
  }

  stopFling(): void {
    if (this.phase !== 'idle') { this.phase = 'stopped'; }
  }

  didReachEnd(atEnd: boolean): void {
    if (this.phase !== 'idle' && this.intent === 'towardEnd' && atEnd) {
      this.reachedEnd = true;
    }
  }

  scrollStop(): void {
    // Stop只是结束候选；控制器下一帧确认，新惯性回报会在确认前重新占用。
    if (this.phase !== 'idle') { this.phase = 'stopped'; }
  }

  release(atEnd: boolean): boolean {
    if (this.pressed || this.phase === 'moving' || this.phase === 'flinging') { return false; }
    const resumed: boolean = this.intent === 'towardEnd' && (this.reachedEnd || atEnd);
    if (resumed) { this.follow = true; }
    this.clearGesture();
    return resumed;
  }

  // 释放意图只读口：控制器在 release() 清态前快照「本手势意图」事实用（只读零副作用）
  releaseIntentTowardEnd(): boolean { return this.intent === 'towardEnd'; }

  // 失败评估后的受闩重放：把快照意图按原样回灌，再走同一条 release() 判据——复跟写点仍
  // 唯一在 release() 内，不新增判据分支与「在底」事实源（atEnd 由控制器现读传入）；新手势
  // 已开始一律拒绝。reachedEnd 回灌恒 false（若曾为 true，原次 release 必已成功、无档可重放）。
  replayRelease(atEnd: boolean): boolean {
    if (this.pressed || this.phase !== 'idle') { return false; }
    this.intent = 'towardEnd';
    this.reachedEnd = false;
    return this.release(atEnd);
  }
}
