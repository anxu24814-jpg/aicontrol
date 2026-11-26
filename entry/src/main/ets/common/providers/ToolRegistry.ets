// 工具注册表容器（2026-10-01 方案-HTTP工具完善 批 3 笔 6 自 ToolTypes.ets 域级最小拆分）：
// 拆分缘由 = 宪法 1200 硬线条款——ToolTypes.ets 已越线，而笔6「请求复用面」要给容器加
// unregister（HTTP 请求模板动态注册/注销的唯一写点）；「本次改动所属的功能域」= 注册表
// 容器域，故整域迁出本件再动。类体与单例逐字搬迁（register/get/all/defsFor 零行为变化），
// 新增 unregister 一枚。ToolTypes.ets 以 import 后再 export 的形态转出两者（照 MemoryGen /
// AiTypes 先例），存量 `import { toolRegistry } from './ToolTypes'` 消费方零改动。
// ★ 坑50 纪律：本件只引叶子（ToolContracts / AiTypes——均零依赖类型件），禁引任何工具域
// 实现件与聚合根；运行时无环。
import { AiToolDef } from './AiTypes';
import { ToolEntry } from './ToolContracts';

// 注册表单例容器（定义 + 展示 + 执行器三合一的条目表；内置工具启动注册幂等——
// registerBuiltinTools 守卫在 ToolTypes）
export class ToolRegistry {
  private entries: Map<string, ToolEntry> = new Map<string, ToolEntry>();

  register(entry: ToolEntry): void {
    this.entries.set(entry.name, entry);
  }

  // 注销（2026-10-01 笔6 新增，唯一消费方 = HttpTemplate.syncTemplateTools 的模板删除/
  // 收缩路径）：模板删除后注册表残留 entry = 无界增长（数据有界红线）+ defsFor 会继续
  // 命中死定义，故动态域注销必须真删。返回值 = 是否确有删除（幂等重入安全）
  unregister(name: string): boolean {
    return this.entries.delete(name);
  }

  get(name: string): ToolEntry | undefined {
    return this.entries.get(name);
  }

  // 全量条目（工具页签 UI 渲染源；注册序 = 数组序稳定）
  all(): ToolEntry[] {
    const list: ToolEntry[] = [];
    this.entries.forEach((entry: ToolEntry): void => {
      list.push(entry);
    });
    return list;
  }

  // 启用清单 → 请求侧声明（ChatSendCtrl 发送前消费；未知 id 过滤——脏数据防御）
  defsFor(enabledIds: string[]): AiToolDef[] {
    const defs: AiToolDef[] = [];
    for (const id of enabledIds) {
      const entry: ToolEntry | undefined = this.entries.get(id);
      if (entry !== undefined) {
        defs.push({ name: entry.name, description: entry.desc,
          parametersJson: entry.parametersJson });
      }
    }
    return defs;
  }
}

// 全局注册表单例（进程级；内置工具首用注册幂等——registerBuiltinTools 守卫）
export const toolRegistry: ToolRegistry = new ToolRegistry();
