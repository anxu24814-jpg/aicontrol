// 聊天页进页转场窗信号（模块级单例，2026-11-15 掉帧修复笔立）。
// 域定义一句话：**push 转场窗内「谁该让路」的共享信号**——进页链置位、转场尾窗释放；
// 持让期挂载的 markdown 正文（解析+建块整段）与用量/上下文估算等非首屏必需段经 defer
// 挪出转场窗，不与转场动画争主线程（反复进出会话 push 掉帧的修复主刀位之一）。
// 为何不能并入既有件（反碎片下限②申报）：消费方横跨 markdown 渲染域（ChatMarkdownBody）
// 与页面编排域（ChatPageLifecycle / ChatPageLoadCtrl），并入任一方都造成跨域反向依赖；
// 本件零依赖纯信号态，独立成件。
// 寿命匹配（内存红线）：回调表寿命 = 持让窗本身（≤ CHAT_TRANSITION_HOLD_MS 兜底定时器 +
// leave 双保险，二者先到即释放清空）；回调闭包虽持页面/组件引用，跨窗必达释放 ⇒ 有界，
// 各回调体首行自检存活（alive / 取消闸），迟到执行零写面。
// 竞态面：hold 只在 ChatPage.aboutToAppear 同步段（enter 链头）；leave 挂 aboutToDisappear
// ——框架销毁推迟，pop 收尾可晚于下一次 push 置位（onBackPressedExitGate 注释既有实证
// 「框架销毁推迟落新窗」），窗口**有交叠**：新窗已 schedule、旧页 leave 才到。故持让窗按
// 代次（generation）归属：schedule 递增取代，页面实例存本窗代次；leave 的 cancel 按代丢弃
// ——代次不符 = 新窗已接管，held 与兜底定时器一概不动，只过滤丢弃本页代的残留回调
//（2026-11-15 P0 回归修复：无代次守卫的 cancel 把新窗 pending 与兜底定时器一并清掉，
// 新窗首屏 defer 行永卡骨架 = 「立即重进空气泡」；隔久重进正常正因旧页销毁已完成）。
import { hilog } from '@kit.PerformanceAnalysisKit';

// 持让窗时长（ms）：官方 push 转场约 300ms + 尾余，进页即起算、装载快慢统一兜底——装载慢时
// 可见行尚未挂载，释放后挂载即直解析（转场已完无争帧）；装载快时骨架停至窗尾。真机观感
//（骨架停留过长 / 内容涌现抖动）只调本值。
const CHAT_TRANSITION_HOLD_MS: number = 400;

let held: boolean = false;
// 持让窗代次：schedule 每开窗递增（自 1 起，0 = 未开窗的页面初值）；defer 项记注册时
// 代次，cancel 按代归属丢弃——跨窗交叠时旧页的迟到 cancel 不误丢新窗回调
let generation: number = 0;

interface ChatTransitionDeferItem {
  gen: number;
  callback: () => void;
}

let pending: ChatTransitionDeferItem[] = [];

// 持让中？（ChatMarkdownBody 首挂判定）
export function chatTransitionHeld(): boolean {
  return held;
}

// 持让窗内延迟执行、已释放立即执行（调用方零分支）。回调体须自检存活（见件头寿命注释）。
export function chatTransitionDefer(callback: () => void): void {
  if (!held) {
    callback();
    return;
  }
  pending.push({ gen: generation, callback: callback });
}

// 置位（scheduleChatTransitionHold 内单点；直接调用仅测试面）
export function chatTransitionHold(): void {
  held = true;
}

// 释放（转场尾窗到点；幂等）。先摘表再逐个执行——执行中经 chatTransitionDefer
// 新注册的回调走「已释放立即执行」支，不混入本批。退页路径不走本函数（走丢弃式
// cancelChatTransition——pending 属已退出页面的白做段，见彼函数注释）。
export function chatTransitionRelease(): void {
  held = false;
  if (pending.length === 0) {
    return;
  }
  const batch: ChatTransitionDeferItem[] = pending;
  pending = [];
  for (const item of batch) {
    try {
      item.callback();
    } catch (error) {
      // 单个回调异常不废整批（后续回调照跑）；留痕非静默（P0-1）
      hilog.warn(0xD5A0, 'ChatTransitionHold', '释放回调执行失败：%{public}s',
        (error as Error).message);
    }
  }
}

// ── 释放调度（模块级单句柄，与 ChatPageLifecycle 的 leaveReloadDebounceHandle 同模式：
//    任意时刻至多一个挂起计时器，先清后挂成对无泄漏）──
let releaseTimer: number = -1;

// 进页置位 + 兜底定时（ChatPageLifecycle.enter 链头调用）。递增代次并返回——页面实例
// 存本窗代次，leave 时按代丢弃（跨窗交叠守卫见件头竞态面注释）
export function scheduleChatTransitionHold(): number {
  generation++;
  chatTransitionHold();
  clearTimeout(releaseTimer);
  releaseTimer = setTimeout((): void => {
    releaseTimer = -1;
    chatTransitionRelease();
  }, CHAT_TRANSITION_HOLD_MS);
  return generation;
}

// 退页丢弃（ChatPageLifecycle.leave 调用，携本页所持窗代次；幂等——已释放零动作）。
// 为何丢弃不执行（2026-11-15 自检观察③修法）：pending 回调属已退出页面的白做段
//（markdown 解析 / 用量查询发起 / 上下文估算），执行即浪费；且用量回调的
// historyLoadAbandoned 守卫受 kill 开关控制（默认关恒 false），「执行靠守卫跳过」在开关关时
// 不成立——丢弃是唯一不依赖开关的省法。各注册者的残留面自愈（如 ChatMarkdownBody 的骨架
// 位由重挂批置位/重进换源复位接管，销毁**不**清位——销毁直调清位会误清交叠新 body 骨架，
// 2026-11-15 报障「重进闪两次」修，见其字段注释）。★ defer 注册契约：回调必须可丢弃或自带兜底。
// leave 后 whenReady 迟到链再注册时 held 已 false → 立即执行，由调用方 departed 守卫跳过
// ★ 代次守卫（2026-11-15 P0 回归修复）：本页 pop 销毁收尾晚于下一页 push 置位时（框架销毁
// 推迟，窗口交叠见件头），gen 已翻 = 新窗接管——held 与兜底定时器归新窗一概不动，只过滤
// 丢弃本页代残留；若无差别全清，新窗首屏 defer 行回调被丢 + 兜底被清 → transitionDeferred
// 永卡 + 骨架拦截回告 = 永久空气泡（「立即重进 / 重进别的会话空气泡」根因）
export function cancelChatTransition(gen: number): void {
  if (gen !== generation) {
    pending = pending.filter((item: ChatTransitionDeferItem): boolean => item.gen !== gen);
    return;
  }
  clearTimeout(releaseTimer);
  releaseTimer = -1;
  held = false;
  pending = [];
}
