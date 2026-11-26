// 重复内置服务商收敛执行器：
// · 启动收敛 convergeDuplicateBuiltinProviders：跨设备/重装备份导入会与本机 seed 壳并存
//   两份 builtin=1 同名家——导入按 id 查重（ExportImport 行循环），而内置 id 是
//   nextMessageId('prov') 随机生成、每台设备必不同，备份内置行恒判「非冲突」整行插入；
//   三层删除保护（菜单隐藏 / deleteProvider 硬拦截 / AI 工具拒绝）全按 builtin 标志拦，
//   两份谁都删不掉。本函数每次启动按 name+baseUrl 分组收敛（与 ProviderPresetSeed 查重
//   键同源），幂等，干净库一次全表查询零动作。
// · 导入让位 keepBuiltinImportRow / removeRedundantBuiltinAfterImport（唯一消费方 =
//   ExportImport providers 行循环）：备份 builtin=1 行命中本机用户手建同名家（builtin=0）
//   → 跳过备份行（用户配置优先，照 seed「含用户手建同名家跳过不覆盖」语义）；命中全为
//   builtin=1 → 备份行**先正常落库**（密钥档按备份 id 回填 touchedProviders、模型/余额列
//   随行恢复，零映射 machinery）**再让位删除**本机重复行。先插后删的次序是刻意的：失败
//   方向 = 残留重复行（启动收敛下次自愈），反过来先删后插一旦插入失败 = 本机数据已删而
//   备份没进来，不可自愈。
// 域缝说明：不并入 ProviderDb（977 行 CRUD 大域，本域是「重复行发现与让位」独立职责）；
// 不并入 ProviderPresetRetire（彼件 = 境外内置按退役清单清除，本域 = 同名重复行收敛，
// 缝不同）；裁决判据单独落零 import 纯件 ProviderDedupPlan（assert-app-domain 直跑回归面）。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ProviderKeyRow, queryProviderKeys } from './ProviderKeyDb';
import { deleteProvider, queryProviderModelCounts, ProviderRow, queryProviders } from './ProviderDb';
import { removePoolKeys, removeProviderKey } from './KeyStore';
import { sharedRdbStore } from './ChatDb';
import { DedupGroupPlan, DedupProviderSnapshot, planBuiltinDedup } from './ProviderDedupPlan';
import { remapSlotProvider } from './FunctionalSlotBinding';

const DOMAIN: number = 0xD5A5;
const TAG: string = 'ProviderBuiltinDedup';

// 单行删除（四步链，照 ProviderPresetRetire 同款顺序不另抄实现）：池条目 id 先于删行
// 查得（Asset 无前缀枚举，行删后拿不到 id 集——成对释放红线）→ deleteProvider 事务级联
//（allowBuiltin=true 放行口，白名单见 ProviderDb.deleteProvider 头注释）→ removePoolKeys
// 清 Asset 明文 → removeProviderKey 清 v2 遗留单 key（幂等，极老库兜底）。
async function removeProviderRowWithAsset(id: string): Promise<void> {
  const keyRows: ProviderKeyRow[] = await queryProviderKeys(id);
  const keyIds: string[] = keyRows.map((key: ProviderKeyRow): string => key.id);
  await deleteProvider(id, true);
  await removePoolKeys(id, keyIds);
  await removeProviderKey(id);
}

// 导入守卫结论：keep = 备份行可落库；remapTo = 跳过时
// 承接该服务商功能槽绑定的**本机手建行 id**（备份内置行命中本机 builtin=0 同名家 → 备份行
// 跳过，偏好仍按备份写会指向不存在的 id，调用方据此把槽位 provider 键映到本机行）。
// 查不动（库异常）也返 keep=false + remapTo 空——宁少导入一行，不可多出一份删不掉的锁定行
export interface BuiltinImportGuard {
  keep: boolean;
  remapTo: string;
}

// 导入守卫（ExportImport 行循环、INSERT 之前调）：只拦「命中本机 builtin=0 手建行」一种
// 情形；命中全为 builtin=1 不在此拦——备份行先落库再让位（见 removeRedundantBuiltinAfterImport）
export async function keepBuiltinImportRow(name: string,
  baseUrl: string): Promise<BuiltinImportGuard> {
  try {
    const all: ProviderRow[] = await queryProviders();
    const hit: ProviderRow | undefined = all.find((row: ProviderRow): boolean =>
      row.name === name && row.baseUrl === baseUrl && !row.builtin);
    if (hit !== undefined) {
      return { keep: false, remapTo: hit.id };
    }
    return { keep: true, remapTo: '' };
  } catch (e) {
    hilog.error(DOMAIN, TAG, '导入守卫查本机服务商失败（保守跳过该行）：%{public}s',
      (e as Error).message);
    return { keep: false, remapTo: '' };
  }
}

// 导入让位（ExportImport 行循环、备份 builtin 行 INSERT 成功之后调；全链吞错不抛——
// 调用方行级成功账已记，让位失败只残留重复行，启动收敛下次自愈）。keepId = 刚落库的
// 备份行 id；删除对象 = 同 name+baseUrl 的其余 builtin=1 行（本机 seed 壳 / 上轮导入份）。
// ★ 删行前先把功能槽绑定从被删行 remap 到 keepId——跳过策略下
// 偏好不回写，本机槽位可能正指向这一行（重装后先用内置预置配好模型再导备份），不映射
// 就等于「导入备份把刚配好的模型选择清了」；overwrite 策略下偏好随后按备份写，remap 无副作用
export async function removeRedundantBuiltinAfterImport(name: string, baseUrl: string,
  keepId: string): Promise<void> {
  try {
    const all: ProviderRow[] = await queryProviders();
    for (const row of all) {
      if (row.id === keepId || !row.builtin || row.name !== name || row.baseUrl !== baseUrl) {
        continue;
      }
      try {
        remapSlotProvider(row.id, keepId);
        await removeProviderRowWithAsset(row.id);
        hilog.info(DOMAIN, TAG, '备份导入让位：已删本机重复内置行 %{public}s（%{public}s），保留 %{public}s',
          row.id, row.name, keepId);
      } catch (e) {
        hilog.error(DOMAIN, TAG, '备份导入让位删行失败（残留由启动收敛兜底）：%{public}s %{public}s',
          row.id, (e as Error).message);
      }
    }
  } catch (e) {
    hilog.error(DOMAIN, TAG, '备份导入让位查行失败（残留由启动收敛兜底）：%{public}s',
      (e as Error).message);
  }
}

// 快照组装：给一行补齐裁决所需的计数面（keyCount 逐行查、modelCount 走全表 GROUP BY、
// hasSecretColumn 走一次聚合 id 集——只在存在重复组时才会走到这里，量级 = 组内行数）。
async function buildSnapshot(row: ProviderRow, modelCounts: Map<string, number>,
  secretIdSet: Set<string>): Promise<DedupProviderSnapshot> {
  const keyRows: ProviderKeyRow[] = await queryProviderKeys(row.id);
  return {
    id: row.id,
    name: row.name,
    baseUrl: row.baseUrl,
    builtin: row.builtin,
    createdAt: row.createdAt,
    keyCount: keyRows.length,
    modelCount: modelCounts.get(row.id) ?? 0,
    hasSecretColumn: secretIdSet.has(row.id)
  };
}

// 启动收敛（调用点 = EntryAbility onCreate 迁移链、ensureProvidersMigrated 之后——v52
// builtin 列必在；fire-and-forget 失败留痕下次启动重试）。永不删 builtin=0 行（非内置行
// 用户自己能删，自动删越权）；保留裁决 = ProviderDedupPlan.planBuiltinDedup（分数最高者
// 留，同分 createdAt 最早）。逐次删除 hilog 留痕。
export async function convergeDuplicateBuiltinProviders(): Promise<void> {
  const rows: ProviderRow[] = await queryProviders();
  if (rows.length < 2) {
    return; // 少于两行不可能同名重复——省后续全部查询（启动稳态零开销）
  }
  // 内存分组找重复组（组键与 seed 查重键同源）
  const grouped: Record<string, ProviderRow[]> = {};
  for (const row of rows) {
    const key: string = row.name + '\n' + row.baseUrl;
    if (grouped[key] === undefined) {
      grouped[key] = [];
    }
    grouped[key].push(row);
  }
  const duplicated: ProviderRow[][] = [];
  const groupKeys: string[] = Object.keys(grouped);
  for (const key of groupKeys) {
    if (grouped[key].length >= 2) {
      duplicated.push(grouped[key]);
    }
  }
  if (duplicated.length === 0) {
    return; // 干净库：零动作（上方一次全表查询即全部开销）
  }
  const modelCounts: Map<string, number> = await queryProviderModelCounts();
  // 敏感列非空 id 集（balance_key / balance_headers / headers 任一非空；一次聚合查询，
  // 免逐行读 ProviderRow 不带的 balance 两列）
  const secretIdSet: Set<string> = new Set<string>();
  const secretRs = await sharedRdbStore().querySql('SELECT id FROM providers WHERE ' +
    "balance_key != '' OR balance_headers != '' OR headers != ''");
  try {
    while (secretRs.goToNextRow()) {
      secretIdSet.add(secretRs.getString(secretRs.getColumnIndex('id')));
    }
  } finally {
    secretRs.close();
  }
  const snapshots: DedupProviderSnapshot[] = [];
  for (const group of duplicated) {
    for (const row of group) {
      snapshots.push(await buildSnapshot(row, modelCounts, secretIdSet));
    }
  }
  const plans: DedupGroupPlan[] = planBuiltinDedup(snapshots);
  for (const plan of plans) {
    for (const removeId of plan.removeIds) {
      try {
        // 功能槽绑定先 remap 到保留行：收敛删的可能是本机槽位
        // 正指向的那一行——不映射则启动一次就丢模型选择；deleteProvider 的槽位清理随后
        // 对被删 id 恒零命中
        remapSlotProvider(removeId, plan.keepId);
        await removeProviderRowWithAsset(removeId);
        hilog.info(DOMAIN, TAG, '重复内置行收敛：已删 %{public}s（%{public}s @ %{public}s），保留 %{public}s',
          removeId, plan.name, plan.baseUrl, plan.keepId);
      } catch (e) {
        hilog.error(DOMAIN, TAG, '重复内置行收敛删行失败（下次启动重试）：%{public}s %{public}s',
          removeId, (e as Error).message);
      }
    }
  }
  if (plans.length > 0) {
    hilog.info(DOMAIN, TAG, '重复内置行收敛完成（%{public}d 组）', plans.length);
  }
}
