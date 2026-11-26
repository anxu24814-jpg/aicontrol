// 进会话性能打点（纯 hilog 观测面，只读不产，除本件外零状态无 UI 面）：把一次会话进入的各
// 时点打上同一时间轴的差分毫秒 hilog——读数者跑 B 场景（进 → 退 → 5 秒内再进）后从日志直读
//「tap→content」「tap→anchor」两口径毫秒数。域沿用 0xD5A0。
// · 七时点（跨五件调用；逐点语义与调用点）：
//   tap    = 列表侧 handleOpenCard 入口（ChatSessionList——点击参考点，开窗）
//   shell  = 进页链入口（ChatPageLifecycle.enter 首行；同拍登记当页 follow 实例为 owner）
//   swap   = 重进换源写回时（ChatPageLifecycle.ensureRuntimeState 重挂分支——进页同步段）
//   content= 换源后首帧帧回调（enter 注册 post-frame；换源已在内容区首建前完成）——「点击
//            →内容第一眼/UI 忙窗结束」口径
//   anchor = 进页校正链收敛或已到底早退（ChatFollowController 两处）——「点击→位置稳定」
//            口径；短会话不经校正链时本点可能缺席（B 场景为重会话，恒达）
//   cache  = 进页预创建行数实际恢复时点（真分帧修正后可能晚于首帧——有长消息揭示时等揭示
//            队列清空才恢复；非验收项）
//   reveal = （已退役）原进页暴露窗口收窗时点——窗口整域退役后本相位无写者，留档防按旧档
//            寻找该读数（preHit 预载命中相位同因整件删除退役）
//   另两活跃扩面相位（走 markEnterProbe 既有差分）：install（fresh 安装点，ChatPageLoad.
//   attachUsageMeta 内 rebuildAndMount 成功返回处——A 场景主口径 tap→install）、overlayOn
//  （蒙层实际亮起，ChatLoadingOverlay overlayArmed 置位处——对照 150ms 理论延迟值）。
// · 另有独立 hilog 行三族（同域同 TAG、不经本件差分通道、不写本件模块状态——「单窗口有界」
//   三标量契约不破）：teardown（ChatPageContent.aboutToDisappear 首行绝对时点——判读旧页
//   销毁是否落新窗）、jump retarget/align（ChatFollowController 跳底时点戳族，实例内限 8 行
//  ——「加载完瞬间跳底」机制定位）、parseProbe（ChatMarkdownBody 历史行 live=false 首帧解析
//   耗时——Σ解析耗时/忙窗全长占比 >30% 则性能立项依据成立，<10% 降级）。
// · owner 过滤：anchor 只认**本窗进页页面的跟随器**——重进窗口内上一页整树销毁收尾的残存
//   落位事件可能串入同一窗口（真机实测疑点），未过滤会把旧页事件记成本窗读数。shell 时登记
//  （owner = 当页 follow 实例），anchor 携自身实例随调，不等即弃；tap 开窗时清空（未壳期
//   anchor 一律弃）。
// · 单窗口有界（内存防线）：一次 tap 开一窗，anchor 落账即关窗（此后同窗其余 anchor 事件
//   静默）；未收敛则下一次 tap 直接覆盖起点——全部状态 = 三个模块级标量，无表无增长。
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xD5A0;
const TAG: string = 'ChatEnterProbe';

// 当前窗口起点（Date.now() ms；-1 = 无窗口——非 tap 打点在无窗口时静默）
let probeStartMs: number = -1;
// anchor 已落账（关窗标记——落账后同窗其余 anchor 事件静默）
let probeAnchorLogged: boolean = false;
// 本窗 owner（进页页面的 follow 实例；shell 登记、tap 清空——anchor 只认它）
let activeOwner: Object | null = null;

export function markEnterProbe(phase: string, owner?: Object): void {
  const now: number = Date.now();
  if (phase === 'tap') {
    probeStartMs = now;
    probeAnchorLogged = false;
    activeOwner = null;
    hilog.info(DOMAIN, TAG, 'tap +0ms');
    return;
  }
  if (phase === 'shell' && owner !== undefined) {
    activeOwner = owner;
  }
  if (probeStartMs < 0) {
    return; // 无窗口（非点击路径进入）——静默
  }
  if (phase === 'anchor') {
    if (owner === undefined || owner !== activeOwner) {
      return; // 非本页跟随器（旧页销毁收尾/跨窗残存事件）——不入本窗
    }
    if (probeAnchorLogged) {
      return; // 同窗 anchor 只落账一次（复位/重挂等后续收敛事件不重复）
    }
    probeAnchorLogged = true;
  }
  hilog.info(DOMAIN, TAG, '%{public}s +%{public}dms', phase, now - probeStartMs);
}
