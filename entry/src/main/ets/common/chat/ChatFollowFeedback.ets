/**
 * 单个滚动请求的落地对账。布局完成或实际位移确认后才发下一步；保留分数余量，
 * 不把逐帧量化误差当成新目标，也不把尚未落地的请求重复相加。只持标量，不持UI对象。
 */
const FOLLOW_ACK_TIMEOUT_NS: number = 128000000;

export class ChatFollowFeedback {
  private pending: boolean = false;
  private requested: number = 0;
  private issuedOffset: number = 0;
  private issuedAt: number = 0;
  private acknowledged: number = 0;
  private scrollReported: boolean = false;
  private sourceAccepted: boolean = false;
  private layoutReady: boolean = false;
  private remainder: number = 0;
  private stalled: number = 0;
  private settling: boolean = false;

  reset(): void {
    this.pending = false;
    this.requested = 0;
    this.acknowledged = 0;
    this.scrollReported = false;
    this.sourceAccepted = false;
    this.layoutReady = false;
    this.remainder = 0;
    this.stalled = 0;
  }

  didLayout(): void {
    if (this.pending) { this.layoutReady = true; }
  }

  willScroll(delta: number, pixelVp: number): void {
    if (!this.pending || !Number.isFinite(delta) || delta < 0 ||
      delta > this.requested + pixelVp || this.sourceAccepted) { return; }
    // 单槽请求在SCROLLER来源获准后才接收回执，此前迟到回报不并入本次。
    this.sourceAccepted = true;
    this.acknowledged = 0;
    this.scrollReported = false;
  }

  didScroll(delta: number): void {
    // 回执并入只认 SCROLLER 来源获准后的回报（willScroll 先行置位）。onDidScroll 无来源参，
    // EDGE_EFFECT 贴底尾波等非程序回报无法区分——pending 未获准时忽略，防污染对账卡至 ACK
    // 超时误杀弹簧（真机轨迹实锤）。
    if (this.pending && !this.sourceAccepted) { return; }
    if (this.pending && Number.isFinite(delta)) {
      this.acknowledged += delta;
      this.scrollReported = true;
    }
  }

  // 1 = 可发下一步，0 = 等上一请求，-1 = 原生无进展，交回布局事件唤醒。
  reconcile(offset: number, nowNs: number, pixelVp: number): number {
    if (!this.pending) { return 1; }
    const observed: number = offset - this.issuedOffset;
    if (this.sourceAccepted && !this.scrollReported) {
      return nowNs - this.issuedAt >= FOLLOW_ACK_TIMEOUT_NS ? -1 : 0;
    }
    // 已确认本次程序来源时，用实际回报而非懒加载总偏移估值。缺来源时保留相容性兜底。
    const reported: boolean = this.scrollReported &&
      (this.sourceAccepted || Math.abs(this.acknowledged - observed) <= pixelVp);
    const moved: number = reported ? this.acknowledged : observed;
    if (!reported && Math.abs(moved) < 0.001) {
      return nowNs - this.issuedAt >= FOLLOW_ACK_TIMEOUT_NS ? -1 : 0;
    }
    if (!this.layoutReady && !reported && moved + 0.001 < this.requested) {
      return nowNs - this.issuedAt >= FOLLOW_ACK_TIMEOUT_NS ? -1 : 0;
    }
    this.pending = false;
    // offset在懒加载时含估计量。只保留一物理像素内的误差，较大偏差交下一帧真实几何重定基准。
    this.remainder = Math.max(-pixelVp, Math.min(pixelVp, this.requested - moved));
    this.stalled = Math.abs(moved) < 0.001 && (this.requested >= pixelVp || this.settling) ?
      this.stalled + 1 : 0;
    return this.stalled >= 3 ? -1 : 1;
  }

  distance(delta: number, remaining: number, pixelVp: number): number {
    const next: number = delta + this.remainder;
    if (next < pixelVp && remaining > pixelVp) {
      this.remainder = next;
      return 0;
    }
    this.remainder = Math.min(0, next);
    return Math.max(0, Math.min(remaining, next));
  }

  issue(delta: number, offset: number, nowNs: number, settling: boolean): void {
    this.settling = settling;
    this.pending = true;
    this.requested = delta;
    this.issuedOffset = offset;
    this.issuedAt = nowNs;
    this.acknowledged = 0;
    this.scrollReported = false;
    this.sourceAccepted = false;
    this.layoutReady = false;
  }
}
