// 功能模型槽位绑定维护：8 个功能槽「服务商两键」的引用维护——
// 重映射（备份导入让位、内置重复行收敛）与清空（停用、删除、启动对账）。
// ★ 槽表 8 槽 = 功能模型页全部模型卡：默认对话 / 标题生成 / 推荐问题 / 上下文压缩 /
//   记忆提取 / 记忆优化 / 文字识别 / 命令审批。其中 10 键常量单一来源 = ProviderDb。
// ★ 记忆/压缩六键在**本件以字面量登记**（下方 MEMORY_* / COMPRESS_* 常量）——它们的域件
//   （MemoryGen / MemoryOpt / CompressGen）依赖链含 ChatContextSource / ChatMessageCompose
//   等聊天与 UI 层，本件若从彼处 import，ProviderDb 的删改函数就会把整张重型依赖图拉进 store
//   层（RDB 直跑夹具实测：kit 面被拽到 uniformTypeDescriptor 而崩）。字面量与域件常量的一致性
//   由断言关系钉守（assert-app-domain 新增组：逐键读两侧现比）；键名是持久化契约不可改名。
// ★ 依赖方向：本件 → ProviderDb（取 10 键常量）；而 ProviderDb 的删除与启停函数反向调本件
//   ⇒ 两模块成环。故**所有外部绑定只在函数体内读**，模块顶层只留接口、常量与函数声明
//   （坑50：有环模块顶层读外部绑定 = TDZ 崩溃）。
// ★ 本件只写 AppStorage（八个槽位两键 + 文字识别引擎档键，均 persistProp 注册，落盘由框架
//   负责），不碰库——调用点必须在对应 DB 事务提交之后，事务回滚时槽位不动。
// ★ 位移语义（决明拍板「停用即回到未选择、复启仍显示未选择」）：清空是**不可逆**
//   的——停用服务商/模型、删除行、备份恢复后指针悬空，都让槽位回到「未选择」，重新启用来
//   不回填。功能链自身对空两键恒早退（零请求），显示面八卡与选择半模态都读「未选择」。
import {
  APPROVAL_MODEL_KEY, APPROVAL_PROVIDER_KEY, DEFAULT_MODEL_KEY, DEFAULT_PROVIDER_KEY,
  OCR_ENGINE_KEY, OCR_ENGINE_MODEL, OCR_MODEL_KEY, OCR_PROVIDER_KEY, SUGGEST_MODEL_KEY,
  SUGGEST_PROVIDER_KEY, TITLE_MODEL_KEY, TITLE_PROVIDER_KEY
} from './ProviderDb';

// 记忆提取两键（字面量登记；来源 = common/MemoryGen.ets 同名常量，关系钉守）
const MEMORY_PROVIDER_KEY: string = 'memoryProvider';
const MEMORY_MODEL_KEY: string = 'memoryModel';
// 记忆优化两键（来源 = common/MemoryOpt.ets 同名常量）
const MEMORY_OPT_PROVIDER_KEY: string = 'memoryOptProvider';
const MEMORY_OPT_MODEL_KEY: string = 'memoryOptModel';
// 上下文压缩两键（来源 = common/CompressGen.ets 同名常量）
const COMPRESS_PROVIDER_KEY: string = 'compressProviderId';
const COMPRESS_MODEL_KEY: string = 'compressModelId';

// 槽位两键对（providerKey 归属判定 + modelKey 成对清）
export interface FunctionalSlotPair {
  providerKey: string;
  modelKey: string;
}

// 槽表（函数体内构造：见头注释「成环 + 顶层读」红线）
export function functionalSlotPairs(): FunctionalSlotPair[] {
  return [
    { providerKey: DEFAULT_PROVIDER_KEY, modelKey: DEFAULT_MODEL_KEY },
    { providerKey: TITLE_PROVIDER_KEY, modelKey: TITLE_MODEL_KEY },
    { providerKey: SUGGEST_PROVIDER_KEY, modelKey: SUGGEST_MODEL_KEY },
    { providerKey: COMPRESS_PROVIDER_KEY, modelKey: COMPRESS_MODEL_KEY },
    { providerKey: MEMORY_PROVIDER_KEY, modelKey: MEMORY_MODEL_KEY },
    { providerKey: MEMORY_OPT_PROVIDER_KEY, modelKey: MEMORY_OPT_MODEL_KEY },
    { providerKey: OCR_PROVIDER_KEY, modelKey: OCR_MODEL_KEY },
    { providerKey: APPROVAL_PROVIDER_KEY, modelKey: APPROVAL_MODEL_KEY }
  ];
}

function slotValue(key: string): string {
  return AppStorage.get<string>(key) ?? '';
}

// 成对清空（只清 provider 键会留下孤 model 键——两键语义恒成对）。
// ★ 文字识别槽另复位引擎档：引擎键显式指视觉模型时，
// 解绑后已无目标——留在 'model' 会让卡面出现「视觉模型选中 + 模型未选择」的自相矛盾，
// 识别链也会先空跑一次视觉模型再回退。只复位显式 'model'（system / builtin / 未写不是
// 本槽绑定，不动）；复位后 resolveOcrEngine 按未写口径推导落系统识别，与「未选择」一致。
function clearPair(pair: FunctionalSlotPair): void {
  AppStorage.setOrCreate<string>(pair.providerKey, '');
  AppStorage.setOrCreate<string>(pair.modelKey, '');
  if (pair.providerKey === OCR_PROVIDER_KEY &&
    (AppStorage.get<string>(OCR_ENGINE_KEY) ?? '') === OCR_ENGINE_MODEL) {
    AppStorage.setOrCreate<string>(OCR_ENGINE_KEY, '');
  }
}

// 服务商重映射（备份导入让位 / 内置重复行收敛）：把 provider 键等于 fromId 的槽位改指 toId。
// 只改 provider 键——模型按 modelId 业务标识匹配，同一服务商目录下的 modelId 不变。
// 返回改动槽数（调用方记账/留痕用）。调用点：ProviderBuiltinDedup 删行前、导入偏好回写后。
// 连接重解析广播不在此发——恢复链自身已有会话列表广播，停用链由 setProviderEnabled 统一补。
export function remapSlotProvider(fromId: string, toId: string): number {
  if (fromId === '' || toId === '' || fromId === toId) {
    return 0;
  }
  let changed: number = 0;
  for (const pair of functionalSlotPairs()) {
    if (slotValue(pair.providerKey) !== fromId) {
      continue;
    }
    AppStorage.setOrCreate<string>(pair.providerKey, toId);
    changed++;
  }
  return changed;
}

// 清空指向某服务商的所有槽位（停用服务商 / 删服务商 / 启动对账）
export function clearSlotsForProvider(providerId: string): number {
  if (providerId === '') {
    return 0;
  }
  let changed: number = 0;
  for (const pair of functionalSlotPairs()) {
    if (slotValue(pair.providerKey) !== providerId) {
      continue;
    }
    clearPair(pair);
    changed++;
  }
  return changed;
}

// 清空恰好指向（providerId, modelId）这一对的槽位（停用/删除单个模型）——同服务商换绑其他
// 模型的槽位不受影响
export function clearSlotsForModel(providerId: string, modelId: string): number {
  if (providerId === '' || modelId === '') {
    return 0;
  }
  let changed: number = 0;
  for (const pair of functionalSlotPairs()) {
    if (slotValue(pair.providerKey) !== providerId || slotValue(pair.modelKey) !== modelId) {
      continue;
    }
    clearPair(pair);
    changed++;
  }
  return changed;
}

// 启动对账：usable = 启用服务商 → 其启用对话模型 modelId 集。不在此集的槽位一律清空
// （行已删 / 服务商停用 / 模型停用 / kind 非 chat 同归「不可用」）。返回清空槽数。
// 调用点 = ModelBindingReconcile（启动 loadContent 回调尾）；幂等，干净库零写
export function reconcileFunctionalSlots(usable: Map<string, Set<string>>): number {
  let changed: number = 0;
  for (const pair of functionalSlotPairs()) {
    const providerId: string = slotValue(pair.providerKey);
    const modelId: string = slotValue(pair.modelKey);
    if (providerId === '' && modelId === '') {
      continue;
    }
    const models: Set<string> | undefined = usable.get(providerId);
    if (providerId !== '' && modelId !== '' && models !== undefined && models.has(modelId)) {
      continue;
    }
    clearPair(pair);
    changed++;
  }
  return changed;
}

// 悬空引擎档归一（启动对账附属一块）：引擎键显式指视觉模型而模型两键不齐 = 解绑后残留的
// 无目标档位（正常 UI 不可达——未选模型时选视觉段会被段位回退支挡回）。复位的意义：卡面
// 不再同时显示「视觉模型选中」与「模型未选择」，识别链不再先空跑一次视觉模型再回退，也
// 不给进页自动弹面板的旧触发态留活口。返回是否改动（0/1）；干净态零写。
// 调用点 = ModelBindingReconcile（启动 loadContent 回调尾）。只判显式 'model'：system /
// builtin / 未写不是槽位绑定，不动。
export function normalizeDanglingOcrEngine(): number {
  if ((AppStorage.get<string>(OCR_ENGINE_KEY) ?? '') !== OCR_ENGINE_MODEL) {
    return 0;
  }
  if (slotValue(OCR_PROVIDER_KEY) !== '' && slotValue(OCR_MODEL_KEY) !== '') {
    return 0;
  }
  AppStorage.setOrCreate<string>(OCR_ENGINE_KEY, '');
  return 1;
}
