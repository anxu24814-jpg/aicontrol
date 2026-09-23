// 预置服务商卡 seed 执行器（2026-08-31 二期任务书，清单单源 = ProviderCatalog.PROVIDER_
// PRESETS）：首启把 12 家主流服务商一次性落库（3 启 9 停），用户点开填 Key 即用。
// 域拆说明：任务书原文「ProviderDb.ets 加 seedProviderPresets」，但该文件 396 行 +
// 本域必超 400 红线，照 ProviderBalanceDb/ProviderKeyDb 先例独立域件。
// ★ 幂等与硬语义（任务书 a~d 条）：
// · 完成标记 = AppStorage persistProp 键 provider_presets_seeded（注册在 EntryAbility
//   loadContent 回调既有 persistProp 区——坑17 时机，本文件只读写值，不建 preferences）；
// · 标记已 '1' 直接 return——用户删除的预置卡**永不回填**；
// · 未标记时逐家处理：按 name+baseUrl 双等查重（queryProviders 快照比对，已存在跳过
//   该家），不存在则 insertProvider 一步插入并随行带 enabled 初值（2026-09-21 B-3 由
//   两步法改一步：两步法第二步失败后重跑会被查重 continue 跳过，停用位永久补不上）；
// · 单家失败 hilog.error 不阻断后续家；**只要有失败家就不写标记**（下次启动重跑，查重
//   保证不重复、只补失败家——兑现「seed 失败不阻断启动，hilog 留痕下次补齐」）；
//   全部家处理完成才写 '1'（标记写入必晚于全部家处理）。
// ★ 注册门闩（时序自检设计，非轮询）：seed 由 onCreate 迁移链尾发起，而标记键的
// persistProp 注册在 loadContent 回调——若 seed 先于注册读标记，磁盘上的 '1' 尚未加载
// 进 AppStorage（get 得 undefined），会误判「从未 seed」重跑、回填用户删过的卡（违反硬
// 语义）。故函数体先 await 门闩：EntryAbility 在 persistProp 注册完该键后调
// notifyPresetSeedKeyRegistered() 放行（官方文档查证：persistProp 初始化优先级 =
// 磁盘已有值 > AppStorage 已有值 > 默认值——放行后磁盘 '1' 必已在 AppStorage）。
// loadContent 失败路径（err.code 早退）不放行 → seed 挂起：页面本身未加载应用不可用，
// 下次启动重试，语义无损。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PROVIDER_PRESETS } from '../providers/ProviderCatalog';
import { insertProvider, ProviderRow, queryProviders } from './ProviderDb';

const DOMAIN: number = 0xD5A3;
const TAG: string = 'ProviderPresetSeed';

// 完成标记键（持久化注册在 EntryAbility；值 '1' = seed 已完成，此后永不重跑）
export const PROVIDER_PRESETS_SEEDED_KEY: string = 'provider_presets_seeded';

// 注册门闩：resolve 句柄由模块加载时同步捕获，notify 一次性放行（重复调用无害）
let releaseGate: (() => void) | null = null;
const keyRegistered: Promise<void> = new Promise<void>((resolve: () => void): void => {
  releaseGate = resolve;
});

// EntryAbility 在标记键 persistProp 注册完成后调用（loadContent 回调既有 persistProp 区末尾）
export function notifyPresetSeedKeyRegistered(): void {
  if (releaseGate !== null) {
    releaseGate();
  }
}

// 首启预置落库（fire-and-forget，调用点 = EntryAbility onCreate 迁移链尾；整体异常由
// 调用方 catch 打日志——标记未写，下次启动重试）
export async function seedProviderPresets(): Promise<void> {
  await keyRegistered;
  if ((AppStorage.get<string>(PROVIDER_PRESETS_SEEDED_KEY) ?? '') === '1') {
    return;
  }
  const existing: ProviderRow[] = await queryProviders();
  let allSeeded: boolean = true;
  for (const preset of PROVIDER_PRESETS) {
    try {
      const dup: ProviderRow | undefined = existing.find((row: ProviderRow): boolean =>
        row.name === preset.shortName && row.baseUrl === preset.baseUrl);
      if (dup !== undefined) {
        continue; // 已在库（含用户手建同名家）——跳过不覆盖，用户配置优先
      }
      await insertProvider(preset.shortName, preset.baseUrl, preset.protocol, preset.endpoint,
        '', '', preset.enabled);
    } catch (e) {
      allSeeded = false;
      hilog.error(DOMAIN, TAG, '预置家落库失败（下次启动补齐）：%{public}s %{public}s',
        preset.shortName, (e as Error).message);
    }
  }
  if (allSeeded) {
    AppStorage.setOrCreate<string>(PROVIDER_PRESETS_SEEDED_KEY, '1');
    hilog.info(DOMAIN, TAG, '预置服务商卡 seed 完成（%{public}d 家）', PROVIDER_PRESETS.length);
  }
}
