// 模型两键 → 显示名解析：功能模型九卡+既有四卡共用。
// 原各卡各写一份 queryProviders/queryModels 链（行化前已五份，行化后若不收敛将达十份），
// 按 P2-4「重复两次以上提取」收成单源。语义与原 FunctionalModelPage.resolveModelDisplay
// 逐字一致：服务商行缺失 = missing；模型行缺失 = missing；查询失败由调用方 catch 兜底
// modelId（展示增强，不阻断卡面）。只回显示名，不回服务商名（决明口径）。
import { ModelRow, ProviderRow, queryModels, queryProviders } from './ProviderDb';

export interface ModelDisplayLabel {
  label: string;
  missing: boolean;
}

export async function resolveModelDisplayLabel(providerId: string,
  modelId: string): Promise<ModelDisplayLabel> {
  const state: ModelDisplayLabel = { label: '', missing: false };
  if (providerId === '' || modelId === '') {
    return state;
  }
  const providers: ProviderRow[] = await queryProviders();
  const provider: ProviderRow | undefined =
    providers.find((row: ProviderRow): boolean => row.id === providerId);
  if (provider === undefined) {
    state.missing = true;
    return state;
  }
  const models: ModelRow[] = await queryModels(provider.id, 'chat');
  const model: ModelRow | undefined =
    models.find((row: ModelRow): boolean => row.modelId === modelId);
  if (model !== undefined) {
    state.label = model.name !== '' ? model.name : model.modelId;
  } else {
    state.missing = true;
  }
  return state;
}
