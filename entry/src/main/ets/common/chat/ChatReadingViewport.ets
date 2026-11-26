/** 消息阅读视口几何。只保存宿主与输入胶囊的测量，按实测即时给出阅读高与底带。 */
export class ChatReadingViewport {
  private hostTop: number = 0;
  private hostHeight: number = 0;
  private inputTop: number = 0;
  private hasInput: boolean = false;

  host(top: number, height: number): void {
    if (!Number.isFinite(top) || !Number.isFinite(height) || height <= 0) { return; }
    this.hostTop = top;
    this.hostHeight = height;
  }

  input(top: number): void {
    if (!Number.isFinite(top)) { return; }
    this.inputTop = top;
    this.hasInput = true;
  }

  // 实测即时（改判史防回游：hold 冻结与展开增量扣减两形态均已撤）——旧冻结分支在键盘
  // RESIZE 压矮宿主时退化为「阅读高 = 宿主高」→ 底带塌 0（末条沉到输入框身后 = 遮挡根因）；
  // 扣减实测工具行高形态在收键盘不失焦 hold 驻留时恒压末条下移（报障根源）。本件只给
  // 几何实测值，逐帧跟随。
  resolve(fallbackInset: number): number {
    if (this.hostHeight <= 0) { return 0; }
    const measured: number = this.inputTop - this.hostTop;
    const height: number = this.hasInput && measured > 0 && measured <= this.hostHeight ? measured :
      this.hostHeight - Math.max(0, fallbackInset);
    return Math.max(1, Math.min(this.hostHeight, height));
  }

  // 底带 = 宿主实测高 − 阅读高，即宿主底到阅读线的遮挡带：与 resolve 同帧同源（内部走
  // 同一 resolve，幂等），禁在本件之外另行测量推带（第二处口径 = 新错位）。宿主未实测
  //（resolve 回 0）整带兜底。展开增量扣减与呼吸量加性一律在宿主层底带单源落点处理
  //（ChatPageContent.scheduleReadingViewport），本件只给几何实测值。
  bandOf(fallbackInset: number): number {
    const reading: number = this.resolve(fallbackInset);
    return reading <= 0 ? fallbackInset : Math.max(0, this.hostHeight - reading);
  }
}
