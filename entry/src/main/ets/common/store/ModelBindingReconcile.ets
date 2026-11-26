// 模型选择启动对账（停用即解绑）：把「绑定目标已不存在或已停用」的模型选择清成
// 未选择，让停用/删除即解绑的语义对存量数据也成立（升级前的历史绑定、任何漏清的路径）。
// 三面 = 功能模型 8 槽（AppStorage 两键，清空实现单源 = FunctionalSlotBinding）+
// 助手绑定（assistants 两列 + 思考档位复位，与 deleteModel 级联同口径）+
// 会话级覆盖（conversations 两列）。另做一块附属归一：文字识别引擎档悬空（显式指视觉模型
// 而模型两键不齐）一并复位，见 FunctionalSlotBinding.normalizeDanglingOcrEngine。
// 可用判据 = 服务商存在且启用 + 该服务商下有同 modelId 的启用 chat 模型（与
// ProviderDb.tryCandidate 严格对验证同口径）；**不含 Key 池**——密钥是资产不是选择态，
// 缺钥由发送链逐支取钥兜底与 notice 呈报，不在本对账清选择。
// 幂等：干净库三面零命中零写；启动 loadContent 回调尾（persistProp 全部注册后）发起，
// fire-and-forget 不阻塞首帧，失败留痕下次启动重试。
// 广播面：助手面清空时自增 SESSION_LIST_RELOAD_KEY（助手页卡面模型行
// 由启动预热快照供给，不广播则卡面停在已解除的模型名）；会话面清空时自增 CONN_RESOLVE_TICK_KEY
// （已开会话页 conn 是进页快照）。本对账另一调用点 = 备份导入收尾（ExportImportApply），同样
// 需要这两次失效。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { relationalStore } from '@kit.ArkData';
import { CONN_RESOLVE_TICK_KEY, ModelRow, ProviderRow, queryModels,
  queryProviders } from './ProviderDb';
import { sharedRdbStore } from './ChatDb';
import { reconcileFunctionalSlots, normalizeDanglingOcrEngine } from './FunctionalSlotBinding';
import { SESSION_LIST_RELOAD_KEY } from '../AppBroadcastKeys';

const DOMAIN: number = 0xD5A6;
const TAG: string = 'ModelBindingReconcile';

export interface ModelBindingReconcileResult {
  slots: number;
  assistants: number;
  conversations: number;
}

// 清掉「绑定目标不可用」的列（COUNT 先行只取摘要数字，命中 0 不写）。SQL 里表名与列名
// 均为本件内部常量（非用户输入），占位符只用于「同 modelId 的另一列」，无注入面。
// 判据面 = 两列任一非空（半绑形态 providerId 有值而 modelId 空同属无效绑定）且该对不在
// 「启用服务商 + 启用 chat 模型」集内——空对属于未绑定，不入清理面
async function clearUnusableBindings(table: string, providerColumn: string,
  resetColumns: string[]): Promise<number> {
  const setClause: string = resetColumns
    .map((column: string): string => column + " = ''").join(', ');
  const condition: string = 'WHERE (' + providerColumn + " != '' OR modelId != '') AND " +
    'NOT EXISTS (SELECT 1 FROM providers p JOIN provider_models m ' +
    'ON m.providerId = p.id WHERE p.id = ' + table + '.' + providerColumn +
    ' AND p.enabled = 1 AND m.modelId = ' + table + ".modelId AND m.enabled = 1 AND m.kind = 'chat')";
  const db: relationalStore.RdbStore = sharedRdbStore();
  const countResult: relationalStore.ResultSet =
    await db.querySql('SELECT COUNT(*) AS n FROM ' + table + ' ' + condition);
  let count: number = 0;
  try {
    if (countResult.goToNextRow()) {
      count = countResult.getLong(countResult.getColumnIndex('n'));
    }
  } finally {
    countResult.close();
  }
  if (count > 0) {
    await db.executeSql('UPDATE ' + table + ' SET ' + setClause + ' ' + condition);
  }
  return count;
}

export async function reconcileModelBindings(): Promise<ModelBindingReconcileResult> {
  // 可用集（启用服务商 → 其启用对话模型 modelId 集）：两次有界全量读，服务商与模型均为手建
  // 小数据集；停用服务商不进表（其下模型一律判不可用）
  const usable: Map<string, Set<string>> = new Map<string, Set<string>>();
  const providers: ProviderRow[] = await queryProviders();
  for (const provider of providers) {
    if (!provider.enabled) {
      continue;
    }
    const modelIds: Set<string> = new Set<string>();
    const models: ModelRow[] = await queryModels(provider.id, 'chat');
    for (const model of models) {
      if (model.enabled) {
        modelIds.add(model.modelId);
      }
    }
    usable.set(provider.id, modelIds);
  }
  // 功能槽清空 + 文字识别悬空引擎档归一（同一性质：解绑残留），两者并入槽位数
  const slots: number = reconcileFunctionalSlots(usable) + normalizeDanglingOcrEngine();
  // 助手绑定：两列归空 + 思考档位复位（档位是模型级画像，绑定没了档位无语义——deleteModel
  // 级联同口径）
  const assistants: number = await clearUnusableBindings('assistants', 'providerId',
    ['providerId', 'modelId', 'thinkLevel']);
  // 会话级覆盖：清列不删会话不删历史，落回助手绑定/全局默认
  const conversations: number = await clearUnusableBindings('conversations', 'modelProviderId',
    ['modelProviderId', 'modelId']);
  if (slots + assistants + conversations > 0) {
    hilog.info(DOMAIN, TAG,
      '模型选择对账：清空功能槽 %{public}d 个 / 助手绑定 %{public}d 条 / 会话覆盖 %{public}d 条',
      slots, assistants, conversations);
  }
  // 清库后补两条失效广播：①助手面 → 助手页卡面的模型行由启动预热快照
  // （HomeListWarmup）供给，新鲜度只认 SESSION_LIST_RELOAD_KEY；快照采集早于本对账，不广播
  // 会让卡面继续显示已解除的模型名（点进编辑页却是未选择）。②会话面 → 已开会话页的 conn 是
  // 进页快照（页签切换不重建），覆盖列被清后仍走旧连接，直到下一次解析输入广播
  if (assistants > 0) {
    AppStorage.setOrCreate<number>(SESSION_LIST_RELOAD_KEY,
      (AppStorage.get<number>(SESSION_LIST_RELOAD_KEY) ?? 0) + 1);
  }
  if (conversations > 0) {
    AppStorage.setOrCreate<number>(CONN_RESOLVE_TICK_KEY,
      (AppStorage.get<number>(CONN_RESOLVE_TICK_KEY) ?? 0) + 1);
  }
  return { slots: slots, assistants: assistants, conversations: conversations };
}
