// 聊天内容区帧回调件（自 ChatPageContent 域级拆出，类体原样搬迁）：阅读边界单槽合帧器
//（ChatReadingFrame）+ 进页减载一次性空闲帧（ChatEntryCacheFrame）。
// · 为何不并入既有件（反碎片下限②申报）：既有帧原语均随其宿主域私有（ChatFollowController
//   的 ChatFollowFrame / ChatPageLifecycle 的 ChatEnterFrame / ChatEntryWindow 的
//   ChatEntryGrowFrame），不外借；本件是「内容区帧原语」共享缝——同族一次性帧同件收拢，
//   避免在拆分对象内继续堆帧类。
// · 生命周期：两枚均一次性、cancel 清闭包（迟到重复驱动自然免疫）；调用方成对 cancel 见
//   ChatPageContent.aboutToDisappear / silenceFrames。
import { FrameCallback } from '@kit.ArkUI';

// 父子Area回调没有固定顺序，合并到下一帧后再消费两侧最新测量。
export class ChatReadingFrame extends FrameCallback {
  private action: (() => void) | null;
  constructor(action: () => void) { super(); this.action = action; }
  cancel(): void { this.action = null; }
  onFrame(): void {
    const action: (() => void) | null = this.action;
    this.action = null;
    action?.();
  }
}

// 进页减载帧：首帧渲染任务结束后恢复稳态预创建行数；一次性，取消清闭包
export class ChatEntryCacheFrame extends FrameCallback {
  private action: (() => void) | null;
  constructor(action: () => void) { super(); this.action = action; }
  cancel(): void { this.action = null; }
  onIdle(_timeLeftInNano: number): void {
    const action: (() => void) | null = this.action;
    this.action = null;
    if (action !== null) { action(); }
  }
}

// 蒙层首屏就绪帧：装载安装提交后的首个内容帧，把 dataSource.entryFirstScreenReady 置真
// ——加载蒙层据此退场（盖到首屏块就绪，而不是数据一装好就退、留下干转圈逐块填）。
// 一次性、取消清闭包（页面销毁成对 cancel）。
export class ChatEntryReadyFrame extends FrameCallback {
  private action: (() => void) | null;
  constructor(action: () => void) { super(); this.action = action; }
  cancel(): void { this.action = null; }
  onFrame(): void {
    const action: (() => void) | null = this.action;
    this.action = null;
    action?.();
  }
}
