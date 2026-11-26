/**
 * 一个实时正文的显示成本反馈（职能改判自「间隔调节」为「速率调节」——间隔自由度收归
 * ChatAppendThrottle 档位单源〔100/200/300 + 67ms 硬下限〕，本域只产出每拍揭示步长建议，
 * 禁两套调节叠在同一自由度上）。
 * 仅持标量、无回调/正文/全局仓；消息换绑定时旧样本失效。
 * 消费耗时只涵盖同步解析与提交，不当作布局/GPU帧时。未采到成本时返回 -1，调用方沿用
 * 默认基准步长。步长物理义 = 按近期每字符解析成本，单拍显示工作预算能负担的揭示字符数：
 * 解析成本高 → 降基准步长（揭示变慢、拍频稳定）；成本低 → 升步长（上界由调用方
 * REVEAL_MAX_CHARS 钳）。
 */
const DISPLAY_FRAME_WORK_MS: number = 12; // 单拍显示工作预算（毫秒）：67ms 揭示间隔下限内约一帧 60fps 余量

export class ChatDisplayBudget {
  private binding: string = '';
  private recentCostMs: number = -1;
  private lastLength: number = 0;
  private lastSampleAt: number = 0;

  record(binding: string, length: number, elapsedMs: number, now: number): void {
    if (binding === '' || length <= 0 || !Number.isFinite(elapsedMs) || elapsedMs < 0) { return; }
    if (this.binding !== binding || length < this.lastLength) { this.recentCostMs = -1; }
    this.binding = binding;
    this.lastLength = length;
    this.lastSampleAt = now;
    // 变重立即收紧，变轻逐步释放；避免单帧噪声令揭示步长在快慢两端反复跳变。
    this.recentCostMs = this.recentCostMs < 0 ? elapsedMs :
      Math.max(elapsedMs, this.recentCostMs * 0.75 + elapsedMs * 0.25);
  }

  /** 构建期成本补采样：代码尾块高亮等 build 期 @Computed 的实测耗时并入当拍成本——只抬
   * 不降（不走 0.75 缓释公式，防补采样被反向稀释），长度锚仍归解析拍 record，补采样只抬
   * 近端成本并刷新新鲜度。未立锚（binding 空 = 尚无解析样本）不采——无长度锚的成本样本
   * 对「每字符成本」无意义。 */
  recordBuildCost(elapsedMs: number, now: number): void {
    if (this.binding === '' || this.recentCostMs < 0 ||
      !Number.isFinite(elapsedMs) || elapsedMs <= 0) { return; }
    this.recentCostMs += elapsedMs;
    this.lastSampleAt = now;
  }

  // 每拍揭示步长建议（字符数；-1 = 无可信样本，调用方沿用默认基准步长）。大于上一完整
  // 样本的突发由调用方退回默认步长，不以小尾差低估处理成本（growth ≤ 2 语义沿用旧 interval）。
  // 零成本样本 = 极轻信号：建议不设限；极端值由调用方在移动平均**之前**钳入 REVEAL 域
  // 上界（防离群样本毒化平均）。
  stepHint(binding: string, length: number, pendingUnits: number, now: number): number {
    if (this.binding !== binding || this.recentCostMs < 0 || length < this.lastLength ||
      pendingUnits > this.lastLength || now - this.lastSampleAt > 1000) {
      return -1;
    }
    if (this.recentCostMs <= 0) {
      return Number.MAX_SAFE_INTEGER;
    }
    const growth: number = Math.min((this.lastLength + pendingUnits) / this.lastLength, 2);
    const perCharMs: number = (this.recentCostMs / Math.max(1, this.lastLength)) * growth;
    return Math.floor(DISPLAY_FRAME_WORK_MS / perCharMs);
  }
}
