// 模型引用检测（2026-09-17 服务商模型卡菜单与删除笔）：删除模型前的「有使用」检查——
// 模型卡菜单点「删除」时先探一遍，删除确认弹窗据此多提示一句，让用户看清删完谁受影响。
// 检测三面（与 ProviderDb.deleteModel 的级联清两面 + 功能模型槽位面同源，改级联须回改本件）：
// ①功能模型五槽（AppStorage 键对）：默认对话 / 标题生成 / 记忆提取 / 记忆优化 / 文字识别的
//   视觉模型；★ 主动消息复用记忆提取两键（ProactiveGen），开关开着时标签并入点名——否则
//   用户删完会发现主动消息也停了却没人告诉过他；★ OCR 面只按「已选模型」两键判定，引擎
//   段位在系统识别/内置识别时该两键仍可能留着旧值，故标签按「文字识别」名义给出（段位
//   不查：段位是引擎选择不是引用关系，查了会把没在用的模型报成在用）。
// ②助手绑定（assistants 表 providerId/modelId 两列，DB v10）。
// ③会话级覆盖（conversations 表 modelProviderId/modelId 两列，DB v24）。
// 三面之外还有用量账本的历史归属（token_usage_events 按 providerId/modelId 记快照）——
// **属历史记录非活引用，不进本检测**：删模型是正常操作，拿历史数据拦人没有道理。
// 形态口径：键对命中判据（modelPairHit）与文本组装（usageWarningText）皆纯函数，两函数
// 不碰 import 绑定，剥 import 后可节点直跑（断言面）；查询与 AppStorage 读取集中在
// checkModelUsage 一函数内（规格表也就地构造，不在顶层读导入常量——坑50 家族口径）。
// ★ 检测不拦删除：查失败由调用方 catch 兜底并降级为不提示（删除照常走完），别把一次
// 读库失败变成删不掉模型（P0-1 的留痕在调用侧）。
import { DEFAULT_MODEL_KEY, DEFAULT_PROVIDER_KEY, OCR_MODEL_KEY, OCR_PROVIDER_KEY,
  TITLE_MODEL_KEY, TITLE_PROVIDER_KEY } from './ProviderDb';
import { MEMORY_MODEL_KEY, MEMORY_PROVIDER_KEY } from '../MemoryGen';
import { MEMORY_OPT_MODEL_KEY, MEMORY_OPT_PROVIDER_KEY } from '../MemoryOpt';
import { PROACTIVE_ENABLED_KEY } from '../ProactiveGen';
import { COMPRESS_MODEL_KEY, COMPRESS_PROVIDER_KEY } from '../CompressGen';
import { SETTING_TITLE_COMPRESS, SETTING_TITLE_DEFAULT_MODEL, SETTING_TITLE_MEMORY_MODEL,
  SETTING_TITLE_MEMORY_OPT_MODEL, SETTING_TITLE_OCR, SETTING_TITLE_TITLE_MODEL } from '../SettingSearch';
import { AssistantRow, queryAssistants } from './AssistantDb';
import { countConversationsByModel } from './ChatDb';

// 检测结果（三面各自计数/清单；slots 恒非空串元素，顺序 = 规格表序）
export interface ModelUsageInfo {
  slots: string[];
  assistantCount: number;
  conversationCount: number;
}

// 槽位读取规格（键对 + 用户可见显示名）
interface ModelSlotSpec {
  providerKey: string;
  modelKey: string;
  label: string;
}

// 键对命中（纯函数）：两键同非空且**严格等于**目标对——与发送链①级覆盖「严格对验证、
// 不自愈换模」同一判据（空串对 = 未配置，不算命中）
export function modelPairHit(providerId: string, modelId: string,
  slotProviderId: string, slotModelId: string): boolean {
  if (providerId === '' || modelId === '') {
    return false;
  }
  return slotProviderId === providerId && slotModelId === modelId;
}

// 提示文本组装（纯函数）：三面各成一句，空面不出句；无任一面命中 = 空串（调用方不拼）
export function usageWarningText(info: ModelUsageInfo): string {
  const parts: string[] = [];
  if (info.slots.length > 0) {
    parts.push('该模型正在被' + info.slots.join('、') + '使用，删除后相关功能会失效或改用其他模型。');
  }
  if (info.assistantCount > 0) {
    parts.push('另有 ' + info.assistantCount + ' 个助手绑定该模型，删除后这些助手会改用其他模型。');
  }
  if (info.conversationCount > 0) {
    parts.push('另有 ' + info.conversationCount + ' 个会话单独选择了该模型，删除后这些会话会改用其他模型。');
  }
  return parts.join('');
}

// 检测失败兜底文案（P0-1 不静默：查不出来也要在弹窗里说一句，不能让用户以为「没提示 =
// 没在用」；删除照常——检测只是提示面，不拦操作）
export const CHECK_MODEL_USAGE_FAIL_TEXT: string = '未能检测该模型的使用情况，删除后相关功能可能失效。';

// 记忆提取槽显示名：主动消息复用记忆两键，开关开着时并入点名（见头注释①）
function memorySlotLabel(): string {
  const proactiveOn: boolean = AppStorage.get<boolean>(PROACTIVE_ENABLED_KEY) ?? false;
  return proactiveOn ? SETTING_TITLE_MEMORY_MODEL + '和主动消息' : SETTING_TITLE_MEMORY_MODEL;
}

// 逐面检测（三面全查；任一读失败整体上抛，由调用方兜底降级）
export async function checkModelUsage(providerId: string,
  modelId: string): Promise<ModelUsageInfo> {
  const slots: string[] = [];
  if (providerId !== '' && modelId !== '') {
    const specs: ModelSlotSpec[] = [
      { providerKey: DEFAULT_PROVIDER_KEY, modelKey: DEFAULT_MODEL_KEY,
        label: SETTING_TITLE_DEFAULT_MODEL },
      { providerKey: TITLE_PROVIDER_KEY, modelKey: TITLE_MODEL_KEY,
        label: SETTING_TITLE_TITLE_MODEL },
      { providerKey: MEMORY_PROVIDER_KEY, modelKey: MEMORY_MODEL_KEY,
        label: memorySlotLabel() },
      { providerKey: MEMORY_OPT_PROVIDER_KEY, modelKey: MEMORY_OPT_MODEL_KEY,
        label: SETTING_TITLE_MEMORY_OPT_MODEL },
      { providerKey: OCR_PROVIDER_KEY, modelKey: OCR_MODEL_KEY,
        label: SETTING_TITLE_OCR },
      // 上下文压缩槽（2026-09-23 上下文压缩笔）：已配置才点名（modelPairHit 空对不命中）——
      // 空槽回退当前会话模型，不构成「删模型影响面」
      { providerKey: COMPRESS_PROVIDER_KEY, modelKey: COMPRESS_MODEL_KEY,
        label: SETTING_TITLE_COMPRESS }
    ];
    for (const spec of specs) {
      const slotProviderId: string = AppStorage.get<string>(spec.providerKey) ?? '';
      const slotModelId: string = AppStorage.get<string>(spec.modelKey) ?? '';
      if (modelPairHit(providerId, modelId, slotProviderId, slotModelId)) {
        slots.push(spec.label);
      }
    }
  }
  // 助手绑定（助手为手建小数据集，全量拉回内存过滤——ProviderCardItem 同款「查询有界」口径）；
  // 判据走 modelPairHit（三面同源——裸相等会把「目标对也为空」的情形判成命中未绑定助手，
  // 与另两面的「空对 = 未配置不命中」口径相左）
  const assistants: AssistantRow[] = await queryAssistants();
  const assistantCount: number = assistants.filter((row: AssistantRow): boolean =>
    modelPairHit(providerId, modelId, row.providerId, row.modelId)).length;
  const conversationCount: number = await countConversationsByModel(providerId, modelId);
  return {
    slots: slots, assistantCount: assistantCount, conversationCount: conversationCount
  };
}
