// 流式工具调用聚合纯域（2026-10-06 拆分笔自立：自 common/providers/ToolTypes.ets 尾部整域外迁
// ——该件越 1200 硬线，按宪法「越线件实质改动前先拆本次改动所属功能域」先拆聚合器域再动；建档
// 与偿还落账 = docs/变更记录.md 本笔条目）。
// 域职责一句话：四协议 SseToolDelta 增量 → 完整 AiToolCall 的聚合器（id/name 分片拼接、args
// 拼接与全量替换两式；聚合语义对齐 RikkaHub StreamChunkHandler）。
// · 为何单开新件（反碎片下限②申报）：本域是解析面与编排层之间的纯逻辑桥，两个并入方向皆不
//   成立——并入 SseParser（解析域）会让解析器持有跨帧状态（解析器是无状态逐帧归一，聚合器是
//   每发送轮一实例的生命周期，重建点在编排层）；回并入 ToolTypes 即回复越线原状。消费者唯一
//   （ChatToolRoundCtrl），与注册表零耦合。
// · 依赖纪律：仅 import 两个类型（AiToolCall / SseToolDelta，编译期擦除）；**禁 import
//   ToolTypes / ToolRegistry / ToolContracts**——聚合器与注册表零耦合（断环红线同 ToolContracts
//   先例）。断言直跑 = 复制本件 .tmp 副本（剥 import 行后自足，照既有 ToolTypes 副本形制）。
// · 沿革：本件内容 = 2026-09-02 工具调用底层笔在 ToolTypes 落码的聚合器块（B13）整域搬迁，
//   方法体逐字、零语义变化。
import { AiToolCall } from './AiTypes';
import { SseToolDelta } from './SseParser';
// ── 流式工具调用聚合器（四协议 SseToolDelta → 完整 AiToolCall；每发送轮一实例，
//   ChatSendCtrl.reset 时重建）──
interface AccEntry {
  id: string;
  name: string;
  args: string;
}

export class ToolCallAccumulator {
  private byIndex: Map<number, AccEntry> = new Map<number, AccEntry>();
  private completes: AccEntry[] = []; // index<0（gemini）整调用直落此
  private seq: number = 0; // 无 id 调用的兜底序号

  feed(deltas: SseToolDelta[]): void {
    for (const d of deltas) {
      if (d.index < 0) {
        // 整调用（gemini functionCall / 无序位方言）：name + argsFull 全量直收
        this.completes.push({ id: this.genId(), name: d.name ?? '', args: d.argsFull ?? '{}' });
        continue;
      }
      let entry: AccEntry | undefined = this.byIndex.get(d.index);
      if (entry === undefined) {
        entry = { id: '', name: '', args: '' };
        this.byIndex.set(d.index, entry);
      }
      if (d.id !== undefined) {
        entry.id = d.id;
      }
      // name 双语义（2026-09-06 修复「search_helpsearch_help」重名循环）：nameFull 全量
      // 替换（responses added/done 各带完整名，+= 会拼重名——真机 bugtest 转录实锤，
      // 重名命不中声明集 →「未在本轮启用」→ 模型重试 → 循环至轮上限）；name 分片拼接
      //（openai chat 事实形态——首帧片段续片累拼）
      if (d.nameFull !== undefined) {
        entry.name = d.nameFull;
      } else if (d.name !== undefined) {
        entry.name += d.name;
      }
      if (d.argsFull !== undefined) {
        entry.args = d.argsFull; // 全量替换式（responses done）
      } else if (d.argsDelta !== undefined) {
        entry.args += d.argsDelta; // 增量拼接式
      }
    }
  }

  // 快照（流结束取全量）：id 空 → 生成兜底 id（CubeAgent 同款）；args 空 → '{}' 归一
  snapshot(): AiToolCall[] {
    const calls: AiToolCall[] = [];
    const indices: number[] = [];
    this.byIndex.forEach((_entry: AccEntry, index: number): void => {
      indices.push(index);
    });
    indices.sort((a: number, b: number): number => a - b);
    for (const index of indices) {
      const entry: AccEntry | undefined = this.byIndex.get(index);
      if (entry === undefined) {
        continue;
      }
      calls.push({
        id: entry.id !== '' ? entry.id : this.genId(),
        name: entry.name,
        argsJson: entry.args !== '' ? entry.args : '{}'
      });
    }
    for (const entry of this.completes) {
      calls.push({ id: entry.id, name: entry.name, argsJson: entry.args });
    }
    return calls;
  }

  private genId(): string {
    this.seq++;
    return 'tool_call_' + Date.now() + '_' + this.seq;
  }
}