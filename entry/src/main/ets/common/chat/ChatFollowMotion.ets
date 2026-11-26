/**
 * 连续跟随的单一位移积分器。输入为布局后的剩余距离，位置以 Scroller 实读为准；
 * 新目标只改变距离，不清速度。纯逻辑回放不代表 ArkUI 的真实布局或呈现帧。
 */
const FOLLOW_ANGULAR_FREQUENCY: number = 14;
const FOLLOW_SETTLE_VP: number = 0.25;
const FOLLOW_MAX_STEP_SECONDS: number = 0.064;

export interface ChatFollowMotionState {
  velocity: number;
  lastFrameNs: number;
}

export interface ChatFollowMotionStep {
  delta: number;
  active: boolean;
}

export function initialFollowMotion(): ChatFollowMotionState {
  return { velocity: 0, lastFrameNs: -1 };
}

export function advanceFollowMotion(state: ChatFollowMotionState, remaining: number,
  frameTimeNs: number): ChatFollowMotionStep {
  if (!Number.isFinite(remaining) || !Number.isFinite(frameTimeNs) || remaining <= 0) {
    state.velocity = 0;
    state.lastFrameNs = -1;
    return { delta: 0, active: false };
  }
  if (remaining <= FOLLOW_SETTLE_VP) {
    state.velocity = 0;
    state.lastFrameNs = -1;
    return { delta: remaining, active: false };
  }
  if (state.lastFrameNs < 0) {
    state.lastFrameNs = frameTimeNs;
    return { delta: 0, active: true };
  }
  const seconds: number = Math.min(FOLLOW_MAX_STEP_SECONDS,
    Math.max(0, (frameTimeNs - state.lastFrameNs) / 1000000000));
  state.lastFrameNs = frameTimeNs;
  if (seconds === 0) { return { delta: 0, active: true }; }
  // 临界阻尼的解析步进不依赖固定帧率；卡顿后限制单步时间，不补播积欠帧。
  const omega: number = FOLLOW_ANGULAR_FREQUENCY;
  const transient: number = omega * remaining - state.velocity;
  const decay: number = Math.exp(-omega * seconds);
  const rest: number = (remaining + transient * seconds) * decay;
  const delta: number = Math.max(0, Math.min(remaining, remaining - rest));
  state.velocity = Math.max(0, (state.velocity + omega * transient * seconds) * decay);
  if (delta >= remaining) {
    state.velocity = 0;
    state.lastFrameNs = -1;
    return { delta: remaining, active: false };
  }
  return { delta: delta, active: true };
}
