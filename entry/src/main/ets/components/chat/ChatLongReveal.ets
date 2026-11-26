// 长消息揭示的页面级联动域（自 ChatPageContent 域级拆出）：①进页预创建行数三档窗口；
// ②展开阅读期底锚冻结（revealHold）；③滚动暂停揭示接线。ChatPageContent 只留 @State 与
// 薄接线（applyCachedRows / onHoldChanged 两回调）与 armEntryCacheFrame 一次调用。
// · 域外依赖全部经构造回调注入（现读闭包，禁持已销毁组件引用——先例 = ChatOlderCtrl）。
// · 寿命匹配：本件只持帧/订阅句柄与数据源身份，不持页面组件引用；页面销毁必须 dispose()
//   成对释放（帧 cancel + 空闲订阅释放）。
import { UIContext } from '@kit.ArkUI';
import { ChatDataSource } from './ChatDataSource';
import { ChatEntryCacheFrame } from './ChatContentFrames';
import { markEnterProbe } from './ChatEnterProbe';
import { pauseMarkdownReveal, resumeMarkdownReveal,
  whenMarkdownRevealIdle } from './markdown/MarkdownDocumentView';

// 进页预创建行数三档：0 = 进页首帧不预建屏外行（首帧减载）；1 = 揭示在途期保留一行预创建
//（滚动中挂载的长行走占位形态、预建成本低，快滑不空窗——原「揭示期保持 0」已改判：0 档
// 快滑要滑到哪行才建哪行，是滑动卡顿的叠加源）；5 = 稳态快滑预建保障。
export const LIST_CACHED_ENTRY: number = 0;
const LIST_CACHED_REVEALING: number = 1;
const LIST_CACHED_STEADY: number = 5;
// 进页预创建行数恢复的兜底时限（ms）：揭示队列空闲信号丢失/异常时不至于永久停在低档
const LIST_CACHED_RESTORE_FALLBACK_MS: number = 4000;

export interface ChatLongRevealRefs {
  // 页面存活现读（组件销毁后一切帧/回调零动作）
  alive: () => boolean;
  // 数据源现读（换源 / 重进重挂面——底锚冻结的身份比对用）
  dataSource: () => ChatDataSource;
  // 帧注册通道（页面 UIContext；与旧进页减载帧同源）
  ui: () => UIContext;
  // 写回页面 @State 的预创建行数（本件只决策，状态由页面持有）
  applyCachedRows: (rows: number) => void;
  // 底锚冻结态变化（页面据此同步 List .stackFromEnd 与 followCtrl 模式位）
  onHoldChanged: (suspended: boolean) => void;
}

export class ChatLongRevealCtrl {
  private refs: ChatLongRevealRefs;
  private entryCacheFrame: ChatEntryCacheFrame | null = null;
  private entryCacheGateRelease: (() => void) | null = null;
  // 展开阅读期底锚冻结源：非空 = 冻结中。存数据源**对象身份**——换源（同页换新数据源）
  // 后旧冻结自动失效，无需另接换源清理点（身份比对见 isSuspended）
  private holdSource: ChatDataSource | null = null;

  constructor(refs: ChatLongRevealRefs) {
    this.refs = refs;
  }

  // ── 进页预创建行数三档窗口 ──
  // 首帧空闲回调后调用：揭示在途 = 先落 1 档并等队列清空恢复 5；队列空 = 立即 5（与旧
  // 行为同，whenMarkdownRevealIdle 对空队列同步回调）。
  armCachedRowsRestore(): void {
    if (!this.refs.alive()) {
      return;
    }
    this.clearEntryCacheGate();
    this.refs.applyCachedRows(LIST_CACHED_REVEALING);
    this.entryCacheGateRelease = whenMarkdownRevealIdle((): void => {
      this.applySteadyCachedRows();
    }, LIST_CACHED_RESTORE_FALLBACK_MS);
  }

  // 进页首帧减载：注册一次性空闲帧 → 恢复判据；注册失败 fail-safe 直判（零揭示任务时
  // armCachedRowsRestore 立即恢复稳态，与旧行为逐字同）
  armEntryCacheFrame(): void {
    if (!this.refs.alive()) {
      return;
    }
    this.entryCacheFrame?.cancel();
    const frame: ChatEntryCacheFrame = new ChatEntryCacheFrame((): void => {
      if (!this.refs.alive()) {
        return;
      }
      this.armCachedRowsRestore();
    });
    this.entryCacheFrame = frame;
    try {
      this.refs.ui().postFrameCallback(frame);
    } catch (_error) {
      this.entryCacheFrame = null;
      this.armCachedRowsRestore();
    }
  }

  private applySteadyCachedRows(): void {
    this.clearEntryCacheGate();
    if (!this.refs.alive()) {
      return;
    }
    this.refs.applyCachedRows(LIST_CACHED_STEADY);
    markEnterProbe('cache');
  }

  private clearEntryCacheGate(): void {
    const release: (() => void) | null = this.entryCacheGateRelease;
    if (release !== null) {
      this.entryCacheGateRelease = null;
      release();
    }
  }

  // ── 展开阅读期底锚冻结（方案档 §4.3 的页面级锚定静默）──
  // 展开 = 阅读动作：置位后 List 不钉底，行高增长不把视口拖向展开内容末尾。清位三路 =
  // 用户回到底部（onReachEnd）、发送（页面 sendWithHoldRelease）、换源（isSuspended 身份
  // 比对自动失效）；页面销毁随组件状态消失。
  hold(): void {
    this.holdSource = this.refs.dataSource();
    this.refs.onHoldChanged(true);
  }

  release(): void {
    if (this.holdSource === null) {
      return;
    }
    this.holdSource = null;
    this.refs.onHoldChanged(false);
  }

  isSuspended(): boolean {
    return this.holdSource !== null && this.holdSource === this.refs.dataSource();
  }

  // ── 滚动暂停揭示接线（建块成本不与滚动争帧；kill switch 在 MarkdownDocumentView）──
  // ★ 暂停位成对复位（2026-11-15 报障修复「进会话一直占位空气泡 / 气泡变矮不出内容」）：
  // 揭示调度器是全局单例，pause/resume 成对依赖滚动 start/stop 事件；本实例记自己是否
  // 处于暂停态——滚动中销毁页面（stop 不再到达）时由 dispose 复位，防 paused 位遗留
  // 到下次进会话（遗留态下所有长消息揭示恒不进块 = revealLimit 0 + 占位骨架永不撤）
  private revealPaused: boolean = false;

  onScrollStart(): void {
    this.revealPaused = true;
    pauseMarkdownReveal();
  }

  onScrollStop(): void {
    this.revealPaused = false;
    resumeMarkdownReveal();
  }

  // 页面销毁成对释放（帧 cancel + 空闲订阅释放 + 暂停位复位；幂等）
  dispose(): void {
    // 仅在本实例确实 pause 过时复位——避免误放别的实例（或后到的滚动 stop）的暂停
    if (this.revealPaused) {
      this.revealPaused = false;
      resumeMarkdownReveal();
    }
    this.entryCacheFrame?.cancel();
    this.entryCacheFrame = null;
    this.clearEntryCacheGate();
    this.holdSource = null;
  }
}
