// 背景刷新直达通知注册表（方案 = docs/方案-背景跟随刷新修复-20261026.md）：一句话职责 =
// 背景刷新直达通知注册表（无依赖叶子，防 ImageEditUtil↔PageBackground 环）。
// 背景：全链送达原语 @StorageProp @Watch 在本项目有两条实锤失效（坑16③ push 页内 tick 链
// 实测不触发、坑25 NavDestination 栈下层内容组件订阅不可靠）——背景跟随刷新的核心保障由
// 「订阅送达」改为「写点直达通知」：写点（开关 toggle / 换图保存 / 恢复默认 / 备份恢复收尾）
// 调 notifyBgChanged() 点名全部存活消费实例现读重判（PageBackground.load /
// BackgroundPanel.refreshPreview）；既有订阅链（三条 @Watch / onShown bump / 写点 bump）一条
// 不删全保留为次通道（kill switch 关闭即回退到纯次通道）。
// ★ 零项目内 import（唯一依赖 @kit hilog 打点）是刻意形态：写点 W3 在 ImageEditUtil
// （resetPageBackground 需通知），而既有依赖链 PageBackground → BgCache → ImageEditUtil 已
// 成单向，本表若并入 PageBackground 则 ImageEditUtil → PageBackground 成环——模块求值环 =
// 未初始化 binding 闪退（ToolPref.ets 同型先例，真机 JsError 实锤）。仓内既有零依赖叶子
// 先例 = common/AppBroadcastKeys.ets、common/ReqLog.ets。
// 内存防线（宪法「内存与资源防线」条）：注册/注销严格成对——消费方持**成员初始化式箭头
// 函数**（身份恒定；★ 禁 this.xxx.bind(this) 注册——每次 bind 产生新函数身份，注销拿不到
// 注册时那份 = 注销失位泄漏），aboutToAppear 注册 / aboutToDisappear 注销（与 departed
// 置位同点）；listeners 数 = 存活消费实例数（导航栈深度 + 一级页 1 + 分栏占位 1 + 预览 1），
// 天然有界；notify 快照迭代（listeners.slice()），回调内再注册/注销不扰本轮遍历。
import { hilog } from '@kit.PerformanceAnalysisKit';

// 直达通道总开关（应急回退位）：false = notifyBgChanged() 空转、直达通道停用，刷新行为回到
// 既有订阅次通道（回退是合法操作，断言只钉在场与 notify 内消费、不钉值）。注意边界：W1
// 写点的 setOrCreate 硬化写盘不受本开关管辖（P7 修复方向，不随通道回退退役，方案 §7）
export const BG_DIRECT_REFRESH_ENABLED: boolean = true;

// 消费方刷新回调：现读数据源并重判自身显示；送达 = 普通 JS 函数调用，不经任何框架状态传播
// 原语（@StorageProp 值同步 / @Watch / @Prop / ForEach 键均不涉）——与坑16/坑25 失效面正交
type BgRefreshListener = () => void;

// 注册表（模块态单例）：条目 = 存活消费实例，天然有界（见头注释）
const listeners: BgRefreshListener[] = [];

// 注册（查重防重复注册：同一 listener 身份只入列一次）
export function registerBgRefreshListener(l: BgRefreshListener): void {
  if (listeners.indexOf(l) < 0) {
    listeners.push(l);
  }
}

// 注销（消费方 aboutToDisappear 与 departed 置位同点调用；入参须为注册时的同一函数身份）
export function unregisterBgRefreshListener(l: BgRefreshListener): void {
  const i: number = listeners.indexOf(l);
  if (i >= 0) {
    listeners.splice(i, 1);
  }
}

// 直达通知（写点与 PageShell.onShown 补刷调用）：点名全部存活实例现读重判。无重入（load /
// refreshPreview 不写通知键）；debug 打点一条（送达实例数）——真机诊断直达通道是否工作的
// 取证配套（hilog 内存环形缓冲不落盘，无数据有界问题；真机拉取见 BLOCKED 真机清单备注）
export function notifyBgChanged(): void {
  if (!BG_DIRECT_REFRESH_ENABLED) {
    return;
  }
  const snapshot: BgRefreshListener[] = listeners.slice();
  for (const l of snapshot) {
    l();
  }
  hilog.debug(0xD5A0, 'BgRefreshBus', 'direct refresh notified, listeners=%{public}d',
    snapshot.length);
}
