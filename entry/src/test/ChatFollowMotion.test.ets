import { describe, expect, it } from '@ohos/hypium';
import { ChatFollowMotionState, ChatFollowMotionStep, advanceFollowMotion, initialFollowMotion }
  from '../main/ets/common/chat/ChatFollowMotion';

import { ChatFollowFeedback } from '../main/ets/common/chat/ChatFollowFeedback';
import { ChatDisplayBudget } from '../main/ets/common/chat/ChatDisplayBudget';
import { ChatScrollOwnership } from '../main/ets/common/chat/ChatScrollOwnership';
import { ChatReadingViewport } from '../main/ets/common/chat/ChatReadingViewport';

export default function chatFollowMotionTest(): void {
  describe('ChatFollowMotion', () => {
    it('retainsProgressAcrossPublicationTargetsAndSettles', 0, (): void => {
      for (const interval of [100, 200, 300]) {
        const state: ChatFollowMotionState = initialFollowMotion();
        let offset: number = 0;
        let target: number = 0;
        for (let time: number = 0; time < 1500; time += 10) {
          if (time % interval === 0) { target += 22; }
          const step: ChatFollowMotionStep = advanceFollowMotion(state, target - offset, time * 1000000);
          expect(step.delta >= 0 && step.delta <= target - offset).assertTrue();
          if (time >= interval) { expect(step.delta > 0 && step.active).assertTrue(); }
          offset += step.delta;
        }
        let settled: boolean = false;
        for (let time: number = 1500; time < 3000; time += 10) {
          const step: ChatFollowMotionStep = advanceFollowMotion(state, target - offset, time * 1000000);
          offset += step.delta;
          if (!step.active) { settled = true; break; }
        }
        expect(settled).assertTrue();
        expect(Math.abs(target - offset) < 0.001).assertTrue();
      }
    });
    it('waitsForActualScrollAndRetainsFractionalRemainder', 0, (): void => {
      const feedback: ChatFollowFeedback = new ChatFollowFeedback();
      feedback.issue(2, 10, 0, false);
      feedback.didLayout();
      expect(feedback.reconcile(10, 16000000, 0.5)).assertEqual(0);
      feedback.didScroll(1.5);
      expect(feedback.reconcile(11.5, 32000000, 0.5)).assertEqual(1);
      expect(feedback.distance(2, 100, 0.5)).assertEqual(2.5);
      feedback.reset();
      expect(feedback.distance(0.2, 100, 0.5)).assertEqual(0);
      expect(feedback.distance(0.2, 100, 0.5)).assertEqual(0);
      expect(feedback.distance(0.2, 100, 0.5) > 0.5).assertTrue();
      feedback.issue(3, 0, 0, false);
      expect(feedback.reconcile(0, 1000000000, 0.5)).assertEqual(-1);
      feedback.reset();
      expect(feedback.reconcile(0, 1000000000, 0.5)).assertEqual(1);
    });
    it('usesAcceptedScrollReceiptInsteadOfEstimatedTotalOffset', 0, (): void => {
      const feedback: ChatFollowFeedback = new ChatFollowFeedback();
      feedback.issue(3, 100, 0, false);
      feedback.didScroll(20);
      expect(feedback.reconcile(100, 16000000, 0.5)).assertEqual(0);
      feedback.willScroll(3, 0.5);
      expect(feedback.reconcile(155, 24000000, 0.5)).assertEqual(0);
      feedback.didScroll(3);
      expect(feedback.reconcile(155, 32000000, 0.5)).assertEqual(1);
      expect(feedback.distance(2, 100, 0.5)).assertEqual(2);
      feedback.issue(3, 155, 40000000, false);
      feedback.willScroll(3, 0.5);
      feedback.didScroll(2.5);
      expect(feedback.reconcile(120, 56000000, 0.5)).assertEqual(1);
      expect(feedback.distance(2, 100, 0.5)).assertEqual(2.5);
    });
    it('readingViewportUsesWindowCoordinatesAndFreezesInputInteraction', 0, (): void => {
      const viewport: ChatReadingViewport = new ChatReadingViewport();
      viewport.input(620);
      expect(viewport.resolve(100)).assertEqual(0);
      viewport.host(20, 800);
      expect(viewport.resolve(100)).assertEqual(600);
      viewport.hold(true);
      viewport.input(480);
      expect(viewport.resolve(100)).assertEqual(600);
      viewport.host(20, 450);
      expect(viewport.resolve(100)).assertEqual(450);
      viewport.host(20, 800);
      viewport.input(620);
      viewport.hold(false);
      expect(viewport.resolve(100)).assertEqual(600);
      viewport.input(Number.NaN);
      expect(viewport.resolve(100)).assertEqual(600);
    });
    it('keepsDisplayBudgetLocalAndRespondsToCost', 0, (): void => {
      // 2026-10-12 RIK 第四笔笔三改判：预算域自间隔调节改速率调节（stepHint = 每拍揭示
      // 步长建议；间隔自由度收归 ChatAppendThrottle 档位单源）
      const budget: ChatDisplayBudget = new ChatDisplayBudget();
      expect(budget.stepHint('a', 100, 1, 0)).assertEqual(-1);
      budget.record('a', 100, 1, 0);
      const light: number = budget.stepHint('a', 100, 1, 0);
      budget.record('a', 110, 30, 0);
      const heavy: number = budget.stepHint('a', 110, 1, 0);
      expect(heavy > 0 && heavy < light).assertTrue();
      budget.record('a', 120, 1, 0);
      const next: number = budget.stepHint('a', 120, 1, 0);
      expect(next > heavy && next < light).assertTrue();
      expect(budget.stepHint('b', 120, 1, 0)).assertEqual(-1);
      expect(budget.stepHint('a', 120, 1, 2000)).assertEqual(-1);
    });
    it('boundsLateFramesAndRejectsInvalidGeometry', 0, (): void => {
      const state: ChatFollowMotionState = initialFollowMotion();
      expect(advanceFollowMotion(state, 500, 0).delta).assertEqual(0);
      const step: ChatFollowMotionStep = advanceFollowMotion(state, 500, 9000000000);
      expect(step.delta > 0 && step.delta < 500).assertTrue();
      expect(advanceFollowMotion(state, -20, 9016000000).active).assertFalse();
      expect(state.velocity).assertEqual(0);
      expect(advanceFollowMotion(state, Number.NaN, 9032000000).active).assertFalse();
    });
    it('userTouchOwnsScrollAndReviewIntentNeverRestoresFollow', 0, (): void => {
      const owner: ChatScrollOwnership = new ChatScrollOwnership();
      expect(owner.isFollowing()).assertTrue();
      expect(owner.touchStart()).assertTrue();
      expect(owner.isTouching()).assertTrue();
      expect(owner.userOwnsScroll()).assertTrue();
      // 微步累计自 0.5 至总量超过 16：跟随退出恰一次且不回翻，退出点不锚定具体阈值
      let dragTotal: number = 0;
      let followExits: number = 0;
      let wasFollowing: boolean = owner.isFollowing();
      while (Math.abs(dragTotal) <= 16) {
        dragTotal -= 0.5;
        owner.drag(-0.5);
        const nowFollowing: boolean = owner.isFollowing();
        if (wasFollowing && !nowFollowing) { followExits += 1; }
        wasFollowing = nowFollowing;
      }
      expect(followExits).assertEqual(1);
      expect(owner.isFollowing()).assertFalse();
      expect(owner.userOwnsScroll()).assertTrue();
      // 回看中的微反向不足以翻回朝底意图，惯性延长占用且不凭到底回报恢复
      owner.drag(3);
      owner.touchEnd(false);
      owner.continueMotion();
      expect(owner.needsRelease()).assertFalse();
      owner.didReachEnd(true);
      expect(owner.isFollowing()).assertFalse();
      expect(owner.userOwnsScroll()).assertTrue();
      owner.scrollStop();
      expect(owner.needsRelease()).assertTrue();
      expect(owner.release(true)).assertFalse();
      expect(owner.isFollowing()).assertFalse();
      expect(owner.userOwnsScroll()).assertFalse();
    });
    it('towardEndReachesBottomRestoresFollowOnlyAfterSettledRelease', 0, (): void => {
      // 先放手后停：到底事实跨内容增长成立，停止收尾后 release(false) 恢复跟随
      const liftFirst: ChatScrollOwnership = new ChatScrollOwnership();
      expect(liftFirst.touchStart()).assertTrue();
      liftFirst.drag(12);
      expect(liftFirst.isFollowing()).assertFalse();
      liftFirst.didReachEnd(true);
      liftFirst.didReachEnd(false);
      liftFirst.touchEnd(false);
      liftFirst.scrollStop();
      expect(liftFirst.release(false)).assertTrue();
      expect(liftFirst.isFollowing()).assertTrue();
      expect(liftFirst.userOwnsScroll()).assertFalse();
      // 先停后放手：按压期间停止仍占用，提前释放被拒，放手后才恢复
      const stopFirst: ChatScrollOwnership = new ChatScrollOwnership();
      expect(stopFirst.touchStart()).assertTrue();
      stopFirst.drag(12);
      stopFirst.didReachEnd(true);
      stopFirst.didReachEnd(false);
      stopFirst.scrollStop();
      expect(stopFirst.isTouching()).assertTrue();
      expect(stopFirst.userOwnsScroll()).assertTrue();
      expect(stopFirst.needsRelease()).assertFalse();
      expect(stopFirst.release(false)).assertFalse();
      stopFirst.touchEnd(false);
      expect(stopFirst.needsRelease()).assertTrue();
      expect(stopFirst.release(false)).assertTrue();
      expect(stopFirst.isFollowing()).assertTrue();
      // 停止后惯性重启：未收尾的 release 一律拒绝且不改跟随判定
      const restarted: ChatScrollOwnership = new ChatScrollOwnership();
      expect(restarted.touchStart()).assertTrue();
      restarted.drag(12);
      restarted.scrollStop();
      restarted.continueMotion();
      expect(restarted.release(false)).assertFalse();
      expect(restarted.isFollowing()).assertFalse();
      expect(restarted.userOwnsScroll()).assertTrue();
      restarted.scrollStop();
      restarted.touchEnd(false);
      expect(restarted.release(false)).assertFalse();
      expect(restarted.isFollowing()).assertFalse();
      // 明确进入惯性：Stop后新的惯性回报继续占用，最终结束才允许恢复
      const flinging: ChatScrollOwnership = new ChatScrollOwnership();
      expect(flinging.touchStart()).assertTrue();
      flinging.drag(12);
      flinging.didReachEnd(true);
      flinging.touchEnd(false);
      flinging.stopDragging(true);
      flinging.continueMotion();
      expect(flinging.userOwnsScroll()).assertTrue();
      expect(flinging.needsRelease()).assertFalse();
      flinging.scrollStop();
      expect(flinging.needsRelease()).assertTrue();
      flinging.stopDragging(true);
      expect(flinging.needsRelease()).assertFalse();
      expect(flinging.release(false)).assertFalse();
      expect(flinging.isFollowing()).assertFalse();
      flinging.stopFling();
      expect(flinging.needsRelease()).assertTrue();
      expect(flinging.release(false)).assertTrue();
      expect(flinging.isFollowing()).assertTrue();
      expect(flinging.userOwnsScroll()).assertFalse();
      flinging.touchStart();
      flinging.drag(12);
      flinging.didReachEnd(true);
      flinging.touchEnd(false);
      flinging.stopDragging(true);
      flinging.scrollStop();
      expect(flinging.release(false)).assertTrue();
      expect(flinging.userOwnsScroll()).assertFalse();
    });
    it('staleReachIntentsNeverSurviveCancelsResetsAndLightTaps', 0, (): void => {
      // 取消触摸即清到底事实，此后被动到底回报与 release 都不能恢复跟随
      const cancelled: ChatScrollOwnership = new ChatScrollOwnership();
      expect(cancelled.touchStart()).assertTrue();
      cancelled.drag(12);
      cancelled.didReachEnd(true);
      cancelled.touchEnd(true);
      expect(cancelled.userOwnsScroll()).assertFalse();
      expect(cancelled.release(true)).assertFalse();
      expect(cancelled.isFollowing()).assertFalse();
      cancelled.didReachEnd(true);
      expect(cancelled.isFollowing()).assertFalse();
      // 新触摸清掉上一手势的过期到底事实，旧手势的待确认释放不再恢复跟随
      const retouched: ChatScrollOwnership = new ChatScrollOwnership();
      expect(retouched.touchStart()).assertTrue();
      retouched.drag(12);
      retouched.didReachEnd(true);
      retouched.scrollStop();
      retouched.touchEnd(false);
      expect(retouched.needsRelease()).assertTrue();
      expect(retouched.touchStart()).assertTrue();
      expect(retouched.needsRelease()).assertFalse();
      retouched.touchEnd(false);
      expect(retouched.release(false)).assertFalse();
      expect(retouched.isFollowing()).assertFalse();
      // 新触摸打断惯性：无 stopFling 也开得出新手势，旧手势的到底事实不泄漏进新收尾
      const interrupted: ChatScrollOwnership = new ChatScrollOwnership();
      expect(interrupted.touchStart()).assertTrue();
      interrupted.drag(12);
      interrupted.didReachEnd(true);
      interrupted.touchEnd(false);
      interrupted.stopDragging(true);
      expect(interrupted.userOwnsScroll()).assertTrue();
      expect(interrupted.needsRelease()).assertFalse();
      expect(interrupted.touchStart()).assertTrue();
      expect(interrupted.isTouching()).assertTrue();
      interrupted.drag(12);
      interrupted.scrollStop();
      interrupted.touchEnd(false);
      expect(interrupted.release(false)).assertFalse();
      expect(interrupted.isFollowing()).assertFalse();
      expect(interrupted.userOwnsScroll()).assertFalse();
      // 未真到底放手不恢复，释放后被动到底回报也不能恢复
      const shortDrag: ChatScrollOwnership = new ChatScrollOwnership();
      expect(shortDrag.touchStart()).assertTrue();
      shortDrag.drag(12);
      shortDrag.scrollStop();
      shortDrag.touchEnd(false);
      expect(shortDrag.release(false)).assertFalse();
      expect(shortDrag.isFollowing()).assertFalse();
      shortDrag.didReachEnd(true);
      expect(shortDrag.isFollowing()).assertFalse();
      expect(shortDrag.userOwnsScroll()).assertFalse();
      // reset 是重挂载/强制回底/卸载的复位入口，preserveTouch 决定按压事实去留
      const lifecycle: ChatScrollOwnership = new ChatScrollOwnership();
      lifecycle.reset(false);
      expect(lifecycle.isFollowing()).assertFalse();
      expect(lifecycle.touchStart()).assertTrue();
      lifecycle.reset(true);
      expect(lifecycle.isFollowing()).assertTrue();
      expect(lifecycle.isTouching()).assertFalse();
      expect(lifecycle.userOwnsScroll()).assertFalse();
      expect(lifecycle.touchStart()).assertTrue();
      lifecycle.drag(12);
      expect(lifecycle.isFollowing()).assertFalse();
      lifecycle.reset(true, true);
      expect(lifecycle.isFollowing()).assertTrue();
      expect(lifecycle.isTouching()).assertTrue();
      expect(lifecycle.userOwnsScroll()).assertTrue();
      lifecycle.touchEnd(false);
      expect(lifecycle.release(false)).assertFalse();
      expect(lifecycle.isFollowing()).assertTrue();
      lifecycle.reset(false);
      expect(lifecycle.isTouching()).assertFalse();
      expect(lifecycle.userOwnsScroll()).assertFalse();
      expect(lifecycle.isFollowing()).assertFalse();
      // 稳定在底的纯轻点不退出跟随，亚阈微动走完停止收尾后同样不退出
      const tapped: ChatScrollOwnership = new ChatScrollOwnership();
      expect(tapped.touchStart()).assertTrue();
      tapped.touchEnd(false);
      expect(tapped.release(false)).assertFalse();
      expect(tapped.isFollowing()).assertTrue();
      expect(tapped.userOwnsScroll()).assertFalse();
      const wobbled: ChatScrollOwnership = new ChatScrollOwnership();
      expect(wobbled.touchStart()).assertTrue();
      const tapWobble: number[] = [0.5, -0.5];
      for (const step of tapWobble) {
        wobbled.drag(step);
      }
      expect(wobbled.isFollowing()).assertTrue();
      wobbled.touchEnd(false);
      wobbled.scrollStop();
      expect(wobbled.needsRelease()).assertTrue();
      expect(wobbled.release(false)).assertFalse();
      expect(wobbled.isFollowing()).assertTrue();
      expect(wobbled.userOwnsScroll()).assertFalse();
    });
  });
}
