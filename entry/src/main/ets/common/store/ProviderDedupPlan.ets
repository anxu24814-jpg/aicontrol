// 重复内置服务商收敛·纯决策核心：
// 分组 + 保留裁决——零 import 约束（ModelPickFilter 同款范式，scripts/assert-app-domain.mjs
// 复制本文件为 .ts 直跑做行为负例；IO 与启动/导入接线在 ProviderBuiltinDedup，不在本域）。
// 为何独立纯件：保留裁决是最易写错的判据面（打分口径见 dedupKeepScore），落零 import
// 件才能进 .ts-copy 直跑管道；IO 执行器带 store 依赖链无法直跑。
// 背景机理：跨设备备份导入会在本机 seed 壳之外多插一份 builtin=1 同名家（导入按 id 查重，
// 内置 id 每台设备随机必不同；三层删除保护全按 builtin 标志拦死 = 用户谁都删不掉）——
// 收敛按 name+baseUrl 分组（与 ProviderPresetSeed 查重键同源），组内按「用户数据丰富度」
// 裁决保留行，其余 builtin=1 行让位删除。

// 参与裁决的最小行快照（调用侧从 ProviderRow + 计数查询裁剪组装；本域不 import ProviderRow
// ——零 import 红线，结构同构自足）
export interface DedupProviderSnapshot {
  id: string;
  name: string;
  baseUrl: string;
  builtin: boolean;
  createdAt: number;
  keyCount: number; // provider_keys 行数（用户配过 Key 的最强信号）
  modelCount: number; // provider_models 行数（拉过模型清单）
  hasSecretColumn: boolean; // balance_key / balance_headers / headers 任一非空（只配余额未拉模型的形态）
}

// 一组重复行的收敛计划：keepId = 保留行，removeIds = 让位删除行（恒 builtin=1 子集）
export interface DedupGroupPlan {
  name: string;
  baseUrl: string;
  keepId: string;
  removeIds: string[];
}

// 保留分：有池密钥行 3 > 有模型行 2 > 敏感列非空 1 > 空壳 0。
// ★ 密钥分最高是刻意的：只填了 Key 没拉过模型的恢复场景（两份都 0 模型）靠它保住用户
// 密钥份——若按「有模型」优先，该场景两份同分退化成「createdAt 最早」，会把带密钥的
// 导入份误判成待删（恰好反掉本次要保的东西）
export function dedupKeepScore(s: DedupProviderSnapshot): number {
  if (s.keyCount > 0) {
    return 3;
  }
  if (s.modelCount > 0) {
    return 2;
  }
  if (s.hasSecretColumn) {
    return 1;
  }
  return 0;
}

// 分组裁决：入参 = 快照全集（调用侧也可只喂重复组），出参 = 每个有可删余量的组的计划。
// · 组键 = name + '\n' + baseUrl（与 seed 查重键同源；换行分隔防两字段拼接歧义）；
// · 组内排序 = 分数降序 → createdAt 升序，首行保留；
// · removeIds = 其余行中 builtin=1 者——**builtin=0 行永不进待删集**（非内置行用户自己
//   能删，自动删越权；组内无可删行时该组不出场）。
export function planBuiltinDedup(rows: DedupProviderSnapshot[]): DedupGroupPlan[] {
  const grouped: Record<string, DedupProviderSnapshot[]> = {};
  for (const row of rows) {
    const key: string = row.name + '\n' + row.baseUrl;
    if (grouped[key] === undefined) {
      grouped[key] = [];
    }
    grouped[key].push(row);
  }
  const plans: DedupGroupPlan[] = [];
  const keys: string[] = Object.keys(grouped);
  for (const key of keys) {
    const group: DedupProviderSnapshot[] = grouped[key];
    if (group.length < 2) {
      continue;
    }
    const sorted: DedupProviderSnapshot[] = group.slice().sort((a: DedupProviderSnapshot,
      b: DedupProviderSnapshot): number => {
      const scoreDiff: number = dedupKeepScore(b) - dedupKeepScore(a);
      if (scoreDiff !== 0) {
        return scoreDiff;
      }
      return a.createdAt - b.createdAt;
    });
    const removeIds: string[] = sorted.slice(1).filter((r: DedupProviderSnapshot): boolean =>
      r.builtin).map((r: DedupProviderSnapshot): string => r.id);
    if (removeIds.length === 0) {
      continue;
    }
    plans.push({ name: sorted[0].name, baseUrl: sorted[0].baseUrl, keepId: sorted[0].id,
      removeIds: removeIds });
  }
  return plans;
}
