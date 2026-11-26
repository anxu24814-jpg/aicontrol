// 消息 List 进页锚态与增长期升格的双态判定器。
// 职责：进页复位即定锚（开态恒锚——首帧底锚含空表）+ 增长期 crossing 升格
//（条数闸与行高累积双口径）。
// ★ 换形防重投（对被否 A 轨形态，勿回 A 轨）：
// · 无身份态纯评估器——不持会话 id / 代次 / 守卫旗，复位由页面侧两处调用点同规则调用
//   （ChatPageLoad 重建链安装处；ChatPageLifecycle.ensureRuntimeState acquire 后无条件一次·
//   全量口径 totalItemCount——首建与换源同拍出锚，重进首物化前也要出锚；重试链复用
//   loadHistory 安装链同一链〔即 ChatPageLoad 安装处〕，无独立调用点），代次事实即
//   「谁在调 reset」本身；
// · 判据双口径——条数闸快路（displayCount ≥ COUNT_GATE 直接判满屏，规避 LazyForEach 部分
//   挂载行高缺失的累加误判）+ 行高累积（Σ 展示项实测高 ≥ 阅读跨度 = viewport − 底带 − 顶留白，
//   经行级 onAreaChange 既有通道喂入）；两口径均只服务会话内增长期的 evaluate 升格，reset
//   锚初值开态恒真（含空表；kill-switch 关态回退条数闸）；
// · 行高累积跨幅只认内容增长事件（宿主层按行旧/新 Area.height 是否变化传 viaRowHeight）
//   ——键盘压缩视口 / 收键盘回落帧等几何瞬变会把阅读跨度瞬时压小，照常判跨即伪升格且单向
//   不回（真机两症状：抬键盘内容跳变 + 收键盘后贴底不还原）；内容真增长照旧即时升格，
//   条数闸快路不受本约束；
// · 单向升格——升格后不回落（防临界抖动），复位是唯一降格口（随会话重建同 tick）；
// · 守卫（总开关旁路 / 持阅读位恒推迟 / hold 收紧为「仅内容仍不满屏时推迟」——已越屏
//   即放行升格）在 evaluate 判据前——推迟不丢弃，由后续行高 / 视口 / 阅读带 / 终停事件续评。
// crossing 无缝：贴顶期首越阅读跨度时顶对齐与底对齐差 ≈ 0，此刻翻 stackFromEnd 的布局跳变
// ≈ 0；评估挂在触发改拍的同一行高 onAreaChange 回调内，检测滞后一帧的过冲 ≤ 该拍揭示量。
// @Observed/@Track anchored：复位点在 ChatPageLoad（非组件环境写不了组件 @State），经对象级
// 观察回流驱动 List.stackFromEnd（先例 = dataSource.blockedNotice 同通道）。
// 行高表有界（内存红线）：升格即清；未升格期间仅短会话在屏行入表，无只进不出增长。
import { CHAT_ENTRY_ANCHOR_ALWAYS_ENABLED, CHAT_STACK_FROM_END_ENABLED } from '../Theme';

// 条数闸 24：典型消息行高下 24 行必满屏；宁早勿晚——晚 = 增长期底边走失，早 = 短内容贴底
// 一拍（与 crossing 滞后同族）。真机校准项。reset 开态恒真不再消费本闸——仅 evaluate
// 增长期快路用；kill-switch 关态（CHAT_ENTRY_ANCHOR_ALWAYS_ENABLED = false）时 reset 回退本闸
const COUNT_GATE: number = 24;

@Observed
export class ChatListAnchorJudge {
  // 当前锚态（@Track——build 内直读驱动 stackFromEnd；只经 reset / evaluate 变更）
  @Track anchored: boolean = false;
  // 展开局部锚：用户点过程段/步骤详情展开或收起时由页面置真——底锚暂停（内容向下生长、
  // 被点行上沿不动），ChatFollowController 同因子短路跟随补偿链。@Track 直驱
  // stackAnchored()（build 内直读 = 改值即重渲 List 属性，普通成员改值不触发重渲——本类挂
  // @ObjectLink 正为这条通道）。几何位（钉哪行、哪个屏位）不在此，在 ChatFollowController；
  // 两处由页面同一入口原子同写，禁分叉。清位 = 回底 / 发送 / 换源（reset 同拍复位）。
  @Track rowPin: boolean = false;
  // 展示项实测高累积表（键 = 展示项 key，与 followCtrl.onItemAreaChange 同键空间；
  // last-write-wins——行收缩 / 重排以最新实测为准）
  private rowHeights: Map<string, number> = new Map();

  // 会话重建 / 换源同拍复位（页面侧两处调用点，见件头）：锚初值同步出、不等首批行高回报
  // ——开态恒锚（kill-switch 常量单源 Theme、默认开）：空表即底锚，首条消息不翻档；运行期
  // stackFromEnd 切换有官方顶部滑动异常缺陷，禁在流式期产生翻档；关态 = 回 COUNT_GATE
  // 条数闸（一行回退）。
  // 进页定位红线：首帧即 END 对齐，禁「先顶对齐再翻底锚」中间态
  reset(displayCount: number): void {
    this.anchored = CHAT_ENTRY_ANCHOR_ALWAYS_ENABLED ? true : displayCount >= COUNT_GATE;
    // 会话重建 = 展开局部锚一并作废（换源/重进不带上会话的钉位；几何位由控制器同点清）
    this.rowPin = false;
    this.rowHeights.clear();
  }

  // 行级实测喂入（行 onAreaChange 通道）：已底锚或总开关旁路零动作（表不再增长——有界）
  onRowHeight(key: string, height: number): void {
    if (this.anchored || !CHAT_STACK_FROM_END_ENABLED) { return; }
    this.rowHeights.set(key, height);
  }

  // 重评（四类既有事件驱动：行高 / List 视口 / 阅读带 / 终停）：守卫在判据前；跨幅 = 条数闸
  // 快路优先，未过闸走行高累积对照阅读跨度（viewportHeight 未实测 = 0 时只走条数闸，防误判）。
  // ★ 开态下 anchored 恒真（reset 即出锚）、本升格路径不可达；保留该路径服务关态
  //（kill-switch false——总开关关闭或锚初值回退时仍有增长期升格）。
  // ★ 阅读跨度钳非负 + 退化解禁用行高对照：横屏+展开输入栏时 span 可为负，负阈值下 Σ ≥ 阈值
  // 恒真（空表 0 ≥ 负也中招）会误升格——span ≤ 0 视作判据不可用、只剩条数闸，fail-safe 朝
  // 不升格侧收敛。
  // ★ viaRowHeight 只认内容增长（语义见件头）；条数闸快路不受该约束（24 行必满屏，与该拍
  // 事件源无关）。
  // ★ hold 只在内容仍不满屏时推迟：不满屏期顶↔底对齐差真实存在，展开期翻底锚会拽动用户正
  // 盯着的输入区；已越屏即放行——crossing 翻转跳变 ≈ 0，且 hold 期补偿链同样被暂停、只有
  // 布局底锚钉得住持续增长的内容。readingHeld 仍恒推迟——用户在读历史，恢复链另行接管。
  evaluate(displayCount: number, viewportHeight: number, readingBand: number, topPad: number,
    hold: boolean, readingHeld: boolean, viaRowHeight: boolean): void {
    if (!CHAT_STACK_FROM_END_ENABLED || this.anchored || readingHeld) { return; }
    const readingSpan: number = Math.max(0, viewportHeight - readingBand - topPad);
    const crossed: boolean = displayCount >= COUNT_GATE ||
      (viaRowHeight && viewportHeight > 0 && readingSpan > 0 && this.sumRowHeights() >= readingSpan);
    if (hold && !crossed) { return; }
    if (crossed) {
      this.anchored = true;
      this.rowHeights.clear();
    }
  }

  private sumRowHeights(): number {
    let total: number = 0;
    this.rowHeights.forEach((height: number): void => { total += height; });
    return total;
  }
}
