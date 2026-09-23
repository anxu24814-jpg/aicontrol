// 控制台助手功能模型域工具（2026-09-08 决明拍板立项，候选①功能模型对 + ②标题生成提示词；
// 四项拍板：独立新工具不并入 set_app_preference 白名单 / 两件各司其职 / 各自带 get /
// 不开「关闭标题生成」——工具操作面 ⊆ UI 操作面纪律，manage_prompts 不开 delete 同理）。
// ★ 2026-09-10 第二笔扩面（决明指令）：set_functional_model 加第三槽「记忆提取模型」
//（MEMORY_PROVIDER_KEY/MEMORY_MODEL_KEY，与标题槽同构复用显示名定位 + 启用口径过滤；未
// 配置 = 功能未启用不整理记忆，不回退标题模型——同日决明取消回退，desc 不得暗示回退）；
// edit_title_prompt 泛化为带 target 的两槽（含标题生成提示词与记忆整理提示词，同 get/set/
// reset 语义、同强制 {content} 校验与 2000 上限；{maxItems} 不强制——缺 = 用户显式去掉条数
// 约束，解析侧上限兜底）。泛化而非新开工具：两提示词完全同构，工具数增长推高每请求 token 账。
// 不传 target 按标题生成提示词处理（向后兼容，既有说法行为零变化）。
// 两个内置工具，均 defaultEnabled=false + console-exclusive 反向拦截（AssistantToolsPage，
// 同 set_app_preference 族）：
// · set_functional_model——功能模型四槽（默认对话 default 两键 / 标题生成 title 两键 / 记忆
//   提取模型 memory 两键 / 记忆优化模型 memoryOpt 两键，★ 第四槽 2026-09-11「记忆优化模型」
//   二期扩面，键定义见 MemoryOpt 头注释；键定义与四级兜底语义见 ProviderDb 头注释、记忆两键
//   见 MemoryGen）
//   查看、列可选清单与设置。合法值口径 = 功能模型页选择器同款（仅启用服务商 + 其启用的对话
//   模型）；定位用界面显示名（provider.name / 模型 name 空则 modelId——与 FunctionalModelPage
//   .resolveModelDisplay 同口径），0 匹配回显可用清单、多匹配拒歧义（manage_prompts 先例）。
//   ★ list action（2026-09-08 决明「已有的模型可以接入查询吗」补笔）：可选项清单查询面——
//   此前用户问「有哪些模型」无路可查，只能 set 传错名靠错误回显，list 补齐后模型可自行对齐
//   用户口语名与界面显示名，客户端不做模糊匹配（模型擅长对齐，客户端加模糊规则反引入误改
//   风险）。★默认对话写后打 CONN_RESOLVE_TICK 广播——FunctionalModelPage.onPickModel 同款
//   副作用（改全局默认后已开会话页须重解析连接，漏打 = 已开会话仍走旧连接缓存，正确性缺口
//   非优化）；标题与记忆模型不进发送链无广播（记忆生成链 MemoryGen.resolveMemoryModel 现读，
//   写键即生效，无缓存消费点）。四槽的键对/广播/回执提示走 FUNCTIONAL_SLOT_SPECS 映射表单源
//   （schema 枚举 / 校验 / 执行器 / 断言四处同读，禁同一分派各写一遍）。
// · edit_title_prompt——生成提示词五槽（标题 TITLE_PROMPT_KEY / 记忆整理 MEMORY_PROMPT_KEY /
//   记忆优化 MEMORY_OPT_PROMPT_KEY / 文字识别 OCR_PROMPT_KEY / 记忆导入
//   MEMORY_IMPORT_PROMPT_KEY，'' = 未定制 = 生效各自内置模板，TitleGen / MemoryGen /
//   MemoryOpt / OcrVisionApi / MemoryImport 各自单源）查看/修改/恢复。★ 2026-09-11
//   第三槽（决明「记忆优化模型完全对齐标题生成与记忆提取的提示词展示与编辑功能」；方案-记忆
//   整理优化-20260911 §9 Q5 原列「少一个工具槽」即本槽，UI 开编辑后工具面同步跟上，否则同一
//   能力两个面不对称）。★ 2026-09-17 第四槽（决明「接入工具」）：文字识别卡视觉模型段的
//   「提示词」键开编辑后同款跟上面（同第三槽先例）；该槽**无占位符**（识别图以附件部件随请求
//   发送，非文本插值），校验按 required 为空跳过占位符要求（空内容仍拒——required 空 + 空串
//   会写回 '' = 静默回内置，观感与动作不符，与功能模型页 savePrompt 同判据）。★ 2026-09-22
//   第五槽（记忆导入，同第三/四槽先例：功能模型页「记忆提取」卡开出第三键「导入提示词」后
//   工具面同步跟上，否则同一能力两个面不对称）；该槽 required = {content}（插的是待整理的
//   外部文本），{maxItems} 与本域第二槽同口径可选。
//   set 校验必须含
//   该槽位要求的占位符（标题、记忆整理与记忆导入 = {content}，记忆优化 = {memories}——★ 逐槽取而非
//   统一 {content}：优化链插的是条目清单不是对话原文，统一校验会让「没有 {memories} 的优化
//   提示词」通过，模型拿不到清单，优化静默空转）+ 长度上限 TEMPLATE_CONTENT_MAX 与编辑面板
//   maxLength 同值；reset = 清各自键回退内置（清删式语义，内置模板升级自动跟随）。工具名不改
//   （协议面 + seed 串 + 助手 tools CSV 列值——本笔只加槽，schema 枚举 / desc / 校验 / 执行器
//   全走规格表自动跟随，seed 零改动）。
// 不开放「关闭标题生成」（清两键回零请求态）：UI 无此入口，工具不领先 UI；desc 不提关闭。
// 边界：模型/服务商 DB 读写与键定义在 ProviderDb，标题提示词真源在 TitleGen、记忆两键与
// 记忆提示词真源在 MemoryGen——本文件只做工具协议层（schema/desc/校验纯函数/执行器）；
// 校验纯函数自包含可断言（searchHelpTopics 同款姿势，断言脚本剥 TS 求值直跑）。
import { ToolExecutor } from './ToolContracts';
import { CONN_RESOLVE_TICK_KEY, DEFAULT_MODEL_KEY, DEFAULT_PROVIDER_KEY, ModelRow,
  ProviderRow, TITLE_MODEL_KEY, TITLE_PROVIDER_KEY, queryModels, queryProviders } from '../store/ProviderDb';
import { TEMPLATE_CONTENT_MAX } from '../store/PromptTemplateDb';
import { TITLE_PROMPT_CONTENT, TITLE_PROMPT_KEY, resolveTitlePromptTemplate } from '../TitleGen';
import { MEMORY_MODEL_KEY, MEMORY_PROMPT_CONTENT, MEMORY_PROMPT_KEY,
  MEMORY_PROMPT_MAX_ITEMS, MEMORY_PROVIDER_KEY,
  resolveMemoryPromptTemplate } from '../MemoryGen';
import { MEMORY_IMPORT_PROMPT_CONTENT, MEMORY_IMPORT_PROMPT_KEY,
  resolveMemoryImportPromptTemplate } from '../MemoryImport';
import { COMPRESS_PROMPT_CONVERSATION, COMPRESS_PROMPT_KEY, COMPRESS_PROMPT_SUPPLEMENT,
  resolveCompressPromptTemplate } from '../CompressGen';
import { MEMORY_OPT_MODEL_KEY, MEMORY_OPT_PROMPT_KEY, MEMORY_OPT_PROMPT_MEMORIES,
  MEMORY_OPT_PROVIDER_KEY, resolveMemoryOptPromptTemplate } from '../MemoryOpt';
import { OCR_PROMPT_KEY, resolveOcrPromptTemplate } from './OcrVisionApi';
import { SETTING_TITLE_DEFAULT_MODEL, SETTING_TITLE_MEMORY_MODEL,
  SETTING_TITLE_MEMORY_OPT_MODEL, SETTING_TITLE_TITLE_MODEL } from '../SettingSearch';

// 工具名常量 TOOL_SET_FUNCTIONAL_MODEL / TOOL_EDIT_TITLE_PROMPT 归口 ToolTypes.ets
//（与注册/反向拦截/seed 同源引用，本域不重复定义防漂移）。

// ── 槽位名常量与分派表（schema 枚举 / 校验 / 执行器 / 断言四处同源单读）──

// 功能模型四槽：槽位名沿用功能模型页的界面标题常量（模型据此对齐用户口语名；顺序 =
// 页内卡序 = 快照 slots 顺序）。★ 2026-09-16：后两槽随卡名去「模型」二字为「记忆提取」
// 「记忆优化」（前两槽 2026-09-06 同款去法）——schema 枚举与 desc 由本数组拼出，自动跟随，
// 本域零改动；帮助条目里的口语示例同笔跟改。
export const FUNCTIONAL_SLOTS: string[] = [SETTING_TITLE_DEFAULT_MODEL,
  SETTING_TITLE_TITLE_MODEL, SETTING_TITLE_MEMORY_MODEL, SETTING_TITLE_MEMORY_OPT_MODEL];

// 提示词五槽：UI 侧没有这五个名字的界面标题（入口是各自卡里的提示词键），本域自开常量
// 单源；不塞 SettingSearch——那边常量被 setting-search-check 巡「须被注册表或 UI 引用」，
// 为非 UI 语义常量消 notes 会顺手注册搜索条目 = 越界。★ 槽名与各链的界面标题不构成契约
//（三槽历史上即不同名，如记忆整理槽 vs 面板「记忆提取提示词」），取词只按「模型能对齐用户
// 口语名」定；第四槽与面板标题现为同字面量属巧合，不是需要维持的约束（★ 2026-09-22 第五槽
// 与面板「记忆导入提示词」同字面量同理）
export const TOOL_PROMPT_SLOT_TITLE: string = '标题生成提示词';
export const TOOL_PROMPT_SLOT_MEMORY: string = '记忆整理提示词';
export const TOOL_PROMPT_SLOT_MEMORY_OPT: string = '记忆优化提示词';
export const TOOL_PROMPT_SLOT_OCR: string = '文字识别提示词';
// ★ 2026-09-22 记忆导入笔第五槽：既有第二槽的值是「记忆整理提示词」（历史命名，用途 = 从
// 会话记录里提取记忆），本槽是从**外部平台文本**里整理记忆（导入页「AI 整理」用），用途不同
// 故独立成槽；命名照同族「记忆导入提示词」
export const TOOL_PROMPT_SLOT_MEMORY_IMPORT: string = '记忆导入提示词';
// ★ 2026-09-23 上下文压缩笔第七槽（任务书-上下文压缩-20260923）：上下文压缩的交接摘要
// 生成提示词——输入域（会话转写文本）与其余六槽皆不同，独立成槽；键与内置模板单源
// CompressGen 域（COMPRESS_PROMPT_KEY / COMPRESS_PROMPT_CONTENT /
// resolveCompressPromptTemplate）
export const TOOL_PROMPT_SLOT_COMPRESS: string = '上下文压缩提示词';
export const TOOL_PROMPT_SLOTS: string[] = [TOOL_PROMPT_SLOT_TITLE, TOOL_PROMPT_SLOT_MEMORY,
  TOOL_PROMPT_SLOT_MEMORY_OPT, TOOL_PROMPT_SLOT_OCR, TOOL_PROMPT_SLOT_MEMORY_IMPORT,
  TOOL_PROMPT_SLOT_COMPRESS];

// 提示词槽规格（schema 枚举 / 校验 / 执行器 / 断言四处同源单读，禁同一分派各写一遍）：
// key = 定制键；required = 必须保留的占位符（逐槽不同——见文件头；'' = 本槽无占位符不校验，
// 现仅文字识别槽如此）；requiredTip = 缺占位符文案的用途后缀（required 为空时不使用）；
// when = 生效时机（get/set/reset 回执转述用）；effective = 生效模板现读函数（各域单源，
// 本域不重写选择规则）
export interface PromptSlotSpec {
  target: string;
  key: string;
  required: string;
  requiredTip: string;
  when: string;
  effective: () => string;
}

export const PROMPT_SLOT_SPECS: PromptSlotSpec[] = [
  { target: TOOL_PROMPT_SLOT_TITLE, key: TITLE_PROMPT_KEY, required: TITLE_PROMPT_CONTENT,
    requiredTip: '用于插入对话内容', when: '生成标题', effective: resolveTitlePromptTemplate },
  { target: TOOL_PROMPT_SLOT_MEMORY, key: MEMORY_PROMPT_KEY, required: MEMORY_PROMPT_CONTENT,
    requiredTip: '用于插入对话内容', when: '整理记忆', effective: resolveMemoryPromptTemplate },
  { target: TOOL_PROMPT_SLOT_MEMORY_OPT, key: MEMORY_OPT_PROMPT_KEY,
    required: MEMORY_OPT_PROMPT_MEMORIES, requiredTip: '用于插入记忆条目清单', when: '优化记忆',
    effective: resolveMemoryOptPromptTemplate },
  { target: TOOL_PROMPT_SLOT_OCR, key: OCR_PROMPT_KEY, required: '',
    requiredTip: '', when: '识别', effective: resolveOcrPromptTemplate },
  { target: TOOL_PROMPT_SLOT_MEMORY_IMPORT, key: MEMORY_IMPORT_PROMPT_KEY,
    required: MEMORY_IMPORT_PROMPT_CONTENT, requiredTip: '用于插入待整理的文本',
    when: '导入页整理外部文本', effective: resolveMemoryImportPromptTemplate },
  { target: TOOL_PROMPT_SLOT_COMPRESS, key: COMPRESS_PROMPT_KEY,
    required: COMPRESS_PROMPT_CONVERSATION, requiredTip: '用于插入待压缩的对话记录',
    when: '压缩上下文', effective: resolveCompressPromptTemplate }
];

// 槽规格查找（校验与执行器共用；未命中回 undefined——校验据此拒非法 target，执行器处是
// 类型守卫分支）
export function findPromptSlotSpec(target: string): PromptSlotSpec | undefined {
  return PROMPT_SLOT_SPECS.find((row: PromptSlotSpec): boolean => row.target === target);
}

// 四槽分派规格：providerKey/modelKey = 目标键对；broadcast = 是否打连接重解析广播（仅默认
// 对话进发送链）；hint = set 回执提示（面向模型转述，不用工程词）
export interface FunctionalSlotSpec {
  target: string;
  providerKey: string;
  modelKey: string;
  broadcast: boolean;
  hint: string;
}

export const FUNCTIONAL_SLOT_SPECS: FunctionalSlotSpec[] = [
  { target: SETTING_TITLE_DEFAULT_MODEL, providerKey: DEFAULT_PROVIDER_KEY,
    modelKey: DEFAULT_MODEL_KEY, broadcast: true,
    hint: '已保存，未选择模型的会话下次发送自动使用新默认模型' },
  { target: SETTING_TITLE_TITLE_MODEL, providerKey: TITLE_PROVIDER_KEY,
    modelKey: TITLE_MODEL_KEY, broadcast: false,
    hint: '已保存，之后新会话完成首条对话后用新模型生成标题' },
  { target: SETTING_TITLE_MEMORY_MODEL, providerKey: MEMORY_PROVIDER_KEY,
    modelKey: MEMORY_MODEL_KEY, broadcast: false,
    hint: '已保存，之后整理记忆时使用新模型' },
  { target: SETTING_TITLE_MEMORY_OPT_MODEL, providerKey: MEMORY_OPT_PROVIDER_KEY,
    modelKey: MEMORY_OPT_MODEL_KEY, broadcast: false,
    hint: '已保存，之后优化记忆时使用新模型' }
];

// ── set_functional_model ──

export const SET_FUNCTIONAL_MODEL_SCHEMA: string =
  '{"type":"object","properties":{"action":{"type":"string",' +
  '"description":"get 查看各槽位当前配置，list 列出当前可选的启用服务商与模型，' +
  'set 设置指定槽位的模型","enum":["get","list","set"]},' +
  '"target":{"type":"string","description":"action 为 set 时必填，要设置的功能槽位",' +
  '"enum":["' + FUNCTIONAL_SLOTS.join('","') + '"]},' +
  '"provider":{"type":"string","description":"action 为 set 时必填，服务商名称，' +
  '须与服务商管理页显示名完全一致"},' +
  '"model":{"type":"string","description":"action 为 set 时必填，模型名称，' +
  '须与该服务商模型列表中的显示名完全一致"}},"required":["action"]}';

// desc 动态拼槽位标题常量（单源防漂移；模型清单不进 desc——合法值随 DB 动态变化，
// 注册时静态生成的 schema/desc 装不下，调用纪律 + 执行层校验兜底。★ 2026-09-08 补 list
// 面：用户问「有哪些模型可选」过去无路可查（只能 set 传错名靠错误回显），list 补齐查询面
// ——清单由模型侧对齐用户口语名与界面显示名，客户端不做模糊匹配）
export function buildSetFunctionalModelDesc(): string {
  return '查看或修改本应用的功能模型。' + SETTING_TITLE_DEFAULT_MODEL +
    '模型在会话未选择模型且助手未绑定模型时自动用于发送；' + SETTING_TITLE_TITLE_MODEL +
    '模型用于自动生成会话标题，未配置则不启用标题生成；' + SETTING_TITLE_MEMORY_MODEL +
    '用于整理记忆时提取记忆条目，未配置则不整理记忆，也不会改用标题生成模型；' +
    SETTING_TITLE_MEMORY_OPT_MODEL + '用于对已有的记忆做去重与改写，未配置则不优化，' +
    '也不会改用前面的模型。' +
    'action 取 get 返回各槽位当前的' +
    '服务商名与模型名，list 列出当前可选的启用服务商与其启用对话模型；' +
    'set 用 target 指定槽位，provider 与 model 传界面上显示的名称，' +
    '只能选已启用服务商下的已启用对话模型，传错会返回当前可选清单。' +
    '用户询问有哪些模型可选时用 list；用户说的模型名不确定时可以先 list 对齐后再 set。' +
    'set 仅在用户明确要求切换功能模型时调用，不要猜测或主动建议。';
}

// 校验结果（纯函数可断言）
export interface SetFunctionalModelValidation {
  ok: boolean;
  action: string;
  target: string;
  provider: string;
  model: string;
  error: string;
}

function rejectSetFunctional(error: string): SetFunctionalModelValidation {
  return { ok: false, action: '', target: '', provider: '', model: '', error: error };
}

// 参数校验纯函数：坏 JSON / 缺 action / 非法 action / set 缺 target、provider、model /
// target 不在四槽位枚举全拒；get 与 list 宽松（多余参数忽略——两 action 均恒返回全量）
export function validateSetFunctionalModelArgs(argsJson: string): SetFunctionalModelValidation {
  let action: string = '';
  let target: string = '';
  let provider: string = '';
  let model: string = '';
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    const rawAction: Object | undefined = parsed['action'];
    const rawTarget: Object | undefined = parsed['target'];
    const rawProvider: Object | undefined = parsed['provider'];
    const rawModel: Object | undefined = parsed['model'];
    if (typeof rawAction === 'string') {
      action = rawAction.trim();
    }
    if (typeof rawTarget === 'string') {
      target = rawTarget.trim();
    }
    if (typeof rawProvider === 'string') {
      provider = rawProvider.trim();
    }
    if (typeof rawModel === 'string') {
      model = rawModel.trim();
    }
  } catch (e) {
    return rejectSetFunctional('参数解析失败，需要 action 参数');
  }
  if (action !== 'get' && action !== 'list' && action !== 'set') {
    return rejectSetFunctional('action 必须是 get、list 或 set');
  }
  if (action === 'get' || action === 'list') {
    return { ok: true, action: action, target: '', provider: '', model: '', error: '' };
  }
  if (!FUNCTIONAL_SLOTS.includes(target)) {
    return rejectSetFunctional('target 必须是：' + FUNCTIONAL_SLOTS.join('、'));
  }
  if (provider === '') {
    return rejectSetFunctional('action 为 set 时需要 provider 参数，值为服务商名称');
  }
  if (model === '') {
    return rejectSetFunctional('action 为 set 时需要 model 参数，值为模型名称');
  }
  return { ok: true, action: action, target: target, provider: provider, model: model, error: '' };
}

// get 槽位快照条目（configured = 两键有值；missing = 有值但指向的服务商或模型行已删
// ——功能模型页 missing 同语义，模型侧如实转述「已删除须重选」）
interface FunctionalSlotState {
  target: string;
  provider: string;
  model: string;
  configured: boolean;
  missing: boolean;
}

interface FunctionalGetPayload {
  ok: boolean;
  action: string;
  slots: FunctionalSlotState[];
}

// list 清单条目（服务商名 + 其启用对话模型显示名——与功能模型页选择器同口径：停用商、
// 停用模型、非对话模型均不列）
interface FunctionalModelOption {
  provider: string;
  models: string[];
}

interface FunctionalListPayload {
  ok: boolean;
  action: string;
  providers: FunctionalModelOption[];
  note: string;
}

// set 回执（old* = 写前旧对的显示名，解析失败给空串——best effort 供模型转述改了什么）
interface SetFunctionalReceipt {
  ok: boolean;
  action: string;
  target: string;
  provider: string;
  model: string;
  oldProvider: string;
  oldModel: string;
  hint: string;
}

// 模型显示名（name 空则 modelId——FunctionalModelPage.resolveModelDisplay 同口径，
// 匹配与回显同用此名，模型从用户原话直接取词零映射歧义）
function modelDisplayName(row: ModelRow): string {
  return row.name !== '' ? row.name : row.modelId;
}

// 功能模型执行器：get 四槽位快照（按规格读键对 + 查表解析显示名）；list 可选项清单（启用
// 服务商 → 其启用对话模型显示名）；set 按显示名定位（启用服务商 → 其启用对话模型，0 匹配
// 回显清单 / 多匹配拒歧义）→ 按规格写键对（默认对话另打 tick 广播对齐 UI，标题与记忆槽
// 无广播）。DB 查询抛错上抛由 executeToolCall 统一包装 error JSON
export class SetFunctionalModelExecutor implements ToolExecutor {
  execute(argsJson: string): Promise<string> {
    const v: SetFunctionalModelValidation = validateSetFunctionalModelArgs(argsJson);
    if (!v.ok) {
      return Promise.resolve(JSON.stringify({ error: v.error }));
    }
    if (v.action === 'get') {
      return this.buildSnapshot().then((payload: FunctionalGetPayload): string =>
        JSON.stringify(payload));
    }
    if (v.action === 'list') {
      return this.buildOptions();
    }
    return queryProviders().then(async (providers: ProviderRow[]): Promise<string> => {
      const enabled: ProviderRow[] = providers
        .filter((row: ProviderRow): boolean => row.enabled);
      const hits: ProviderRow[] = enabled
        .filter((row: ProviderRow): boolean => row.name === v.provider);
      if (hits.length === 0) {
        const names: string = enabled.map((row: ProviderRow): string => row.name).join('、');
        return JSON.stringify({ error: '没有名为「' + v.provider + '」的启用服务商。当前启用' +
          '服务商：' + (names === '' ? '（暂无）' : names) });
      }
      if (hits.length > 1) {
        return JSON.stringify({ error: '存在 ' + hits.length + ' 个同名服务商「' + v.provider +
          '」，无法确定要设置哪一个' });
      }
      const provider: ProviderRow = hits[0];
      const models: ModelRow[] = (await queryModels(provider.id, 'chat'))
        .filter((row: ModelRow): boolean => row.enabled);
      const mHits: ModelRow[] = models
        .filter((row: ModelRow): boolean => modelDisplayName(row) === v.model);
      if (mHits.length === 0) {
        const names: string = models.map((row: ModelRow): string => modelDisplayName(row)).join('、');
        return JSON.stringify({ error: '服务商「' + v.provider + '」没有名为「' + v.model +
          '」的启用对话模型。该服务商可用模型：' + (names === '' ? '（暂无）' : names) });
      }
      if (mHits.length > 1) {
        return JSON.stringify({ error: '服务商「' + v.provider + '」存在 ' + mHits.length +
          ' 个同名模型「' + v.model + '」，无法确定要设置哪一个' });
      }
      const modelRow: ModelRow = mHits[0];
      // 四槽分派走映射表单源（校验已保证 target 在枚举内，undefined 分支是类型守卫）
      const spec: FunctionalSlotSpec | undefined = FUNCTIONAL_SLOT_SPECS
        .find((row: FunctionalSlotSpec): boolean => row.target === v.target);
      if (spec === undefined) {
        return JSON.stringify({ error: '未知的功能模型槽位：' + v.target });
      }
      // 写前读旧对并解析显示名（旧对可能未配置或行已删——best effort 给空串）
      const oldProviderId: string = AppStorage.get<string>(spec.providerKey) ?? '';
      const oldModelId: string = AppStorage.get<string>(spec.modelKey) ?? '';
      let oldProviderName: string = '';
      let oldModelName: string = '';
      if (oldProviderId !== '' && oldModelId !== '') {
        const oldProvider: ProviderRow | undefined = providers
          .find((row: ProviderRow): boolean => row.id === oldProviderId);
        if (oldProvider !== undefined) {
          oldProviderName = oldProvider.name;
          const oldModel: ModelRow | undefined = (await queryModels(oldProviderId, 'chat'))
            .find((row: ModelRow): boolean => row.modelId === oldModelId);
          oldModelName = oldModel !== undefined ? modelDisplayName(oldModel) : '';
        }
      }
      AppStorage.setOrCreate<string>(spec.providerKey, provider.id);
      AppStorage.setOrCreate<string>(spec.modelKey, modelRow.modelId);
      if (spec.broadcast) {
        // 广播解析输入变化（FunctionalModelPage.onPickModel 同款）：改全局默认后已开着的
        // 会话页 @Watch 重解析，否则切回直接发送仍走旧连接缓存
        AppStorage.setOrCreate<number>(CONN_RESOLVE_TICK_KEY,
          (AppStorage.get<number>(CONN_RESOLVE_TICK_KEY) ?? 0) + 1);
      }
      const receipt: SetFunctionalReceipt = {
        ok: true, action: 'set', target: v.target,
        provider: provider.name, model: modelDisplayName(modelRow),
        oldProvider: oldProviderName, oldModel: oldModelName,
        hint: spec.hint
      };
      return JSON.stringify(receipt);
    });
  }

  // 四槽位快照（顺序 = 映射表序 = 功能模型页卡序）：按规格读键对 → 查表解析显示名
  //（行已删 = missing 置位；未配置 = provider/model 空串——模型可如实回答「标题生成、
  // 记忆提取模型未配置即未启用」）
  private async buildSnapshot(): Promise<FunctionalGetPayload> {
    const slots: FunctionalSlotState[] = [];
    for (const spec of FUNCTIONAL_SLOT_SPECS) {
      slots.push(await this.resolveSlot(spec.target,
        AppStorage.get<string>(spec.providerKey) ?? '',
        AppStorage.get<string>(spec.modelKey) ?? ''));
    }
    return { ok: true, action: 'get', slots: slots };
  }

  // 可选项清单（list action）：启用服务商 → 其启用对话模型显示名（与 set 定位、功能模型页
  // 选择器三处同口径——停用商/停用模型/非对话模型均不列，模型按此清单对齐用户口语名）；
  // 全空带 note 指引（空载荷须可感知，A3 教训）
  private buildOptions(): Promise<string> {
    return queryProviders().then(async (providers: ProviderRow[]): Promise<string> => {
      const options: FunctionalModelOption[] = [];
      for (const provider of providers) {
        if (!provider.enabled) {
          continue;
        }
        const models: ModelRow[] = (await queryModels(provider.id, 'chat'))
          .filter((row: ModelRow): boolean => row.enabled);
        if (models.length > 0) {
          options.push({ provider: provider.name,
            models: models.map((row: ModelRow): string => modelDisplayName(row)) });
        }
      }
      const payload: FunctionalListPayload = { ok: true, action: 'list', providers: options,
        note: options.length === 0
          ? '当前没有可选的模型。需要先在 设置 → 服务商管理 添加服务商、获取模型并保持启用。'
          : '' };
      return JSON.stringify(payload);
    });
  }

  private async resolveSlot(target: string, providerId: string,
    modelId: string): Promise<FunctionalSlotState> {
    if (providerId === '' || modelId === '') {
      return { target: target, provider: '', model: '', configured: false, missing: false };
    }
    const providers: ProviderRow[] = await queryProviders();
    const provider: ProviderRow | undefined = providers
      .find((row: ProviderRow): boolean => row.id === providerId);
    if (provider === undefined) {
      return { target: target, provider: '', model: '', configured: true, missing: true };
    }
    const models: ModelRow[] = await queryModels(provider.id, 'chat');
    const model: ModelRow | undefined = models
      .find((row: ModelRow): boolean => row.modelId === modelId);
    if (model === undefined) {
      return { target: target, provider: provider.name, model: '', configured: true, missing: true };
    }
    return { target: target, provider: provider.name, model: modelDisplayName(model),
      configured: true, missing: false };
  }
}

// ── edit_title_prompt ──

export const EDIT_TITLE_PROMPT_SCHEMA: string =
  '{"type":"object","properties":{"action":{"type":"string",' +
  '"description":"get 查看当前生效的提示词，set 全文替换，reset 恢复内置默认",' +
  '"enum":["get","set","reset"]},' +
  '"target":{"type":"string","description":"要操作的提示词槽位，不传按 ' +
  TOOL_PROMPT_SLOT_TITLE + ' 处理","enum":["' + TOOL_PROMPT_SLOTS.join('","') + '"]},' +
  '"content":{"type":"string","description":"action 为 set 时必填，提示词全文，' +
  '须包含该槽位要求的占位符（无占位符要求的槽位不受此限），将整体替换现有内容"}},' +
  '"required":["action"]}';

// desc 动态拼槽位名、占位符与上限（常量单源，防两处漂移；target 缺省语义写进 desc——
// 既有说法不传 target，模型按标题槽处理即向后兼容）
export function buildEditTitlePromptDesc(): string {
  return '查看、修改或恢复本应用的生成提示词。target 取 ' + TOOL_PROMPT_SLOTS.join('、') +
    '，不传 target 时按 ' + TOOL_PROMPT_SLOT_TITLE + ' 处理。' +
    TOOL_PROMPT_SLOT_TITLE + '在新会话首条对话完成后把对话总结成标题；' +
    TOOL_PROMPT_SLOT_MEMORY + '在整理记忆时按规则从对话中提取记忆条目；' +
    TOOL_PROMPT_SLOT_MEMORY_OPT + '在优化记忆时按规则对已有条目做去重与改写；' +
    TOOL_PROMPT_SLOT_OCR + '在用视觉模型识别图片文字时作为要求发给模型；' +
    TOOL_PROMPT_SLOT_MEMORY_IMPORT + '在导入页把其他 AI 平台的记忆总结整理成条目；' +
    TOOL_PROMPT_SLOT_COMPRESS + '在压缩上下文时把对话记录整理成交接摘要。' +
    '前两类提示词中的 ' + TITLE_PROMPT_CONTENT + ' 占位符会被替换为对话内容，必须保留；' +
    TOOL_PROMPT_SLOT_MEMORY_OPT + '中的 ' + MEMORY_OPT_PROMPT_MEMORIES + ' 占位符会被替换为' +
    '记忆条目清单，同样必须保留；' + TOOL_PROMPT_SLOT_MEMORY_IMPORT + '中的 ' +
    MEMORY_IMPORT_PROMPT_CONTENT + ' 占位符会被替换为待整理的文本，同样必须保留；' +
    TOOL_PROMPT_SLOT_COMPRESS + '中的 ' + COMPRESS_PROMPT_CONVERSATION +
    ' 占位符会被替换为待压缩的对话记录，同样必须保留；' +
    TOOL_PROMPT_SLOT_OCR + '不含占位符，直接写识别要求即可。' +
    MEMORY_PROMPT_MAX_ITEMS + ' 占位符仅 ' + TOOL_PROMPT_SLOT_MEMORY + ' 与 ' +
    TOOL_PROMPT_SLOT_MEMORY_IMPORT + ' 可选，会被替换为' +
    '条数上限，去掉则不限制条数；' + COMPRESS_PROMPT_SUPPLEMENT + ' 占位符仅 ' +
    TOOL_PROMPT_SLOT_COMPRESS + ' 可选，会被替换为本次压缩的补充要求，去掉则不追加。' +
    'action 取 get 返回当前生效全文与是否定制，set 用 content ' +
    '全文替换（上限 ' + TEMPLATE_CONTENT_MAX + ' 字，必须包含该槽位要求的占位符），' +
    'reset 恢复为内置默认。仅在用户明确要求查看或修改提示词时调用；' +
    'set 是整体替换，用户只想局部调整时先 get 再基于原文生成新全文。保存后下次生成、整理、优化或识别时生效。';
}

// 校验结果（纯函数可断言；target 为规范化后的槽位名——缺省已注入默认槽）
export interface EditTitlePromptValidation {
  ok: boolean;
  action: string;
  target: string;
  content: string;
  error: string;
}

function rejectEditTitle(error: string): EditTitlePromptValidation {
  return { ok: false, action: '', target: '', content: '', error: error };
}

// 参数校验纯函数：坏 JSON / 非法 action / target 缺省注入默认槽、非法值拒 / set 缺 content /
// 缺该槽位要求的占位符（required 为空槽——文字识别——跳过占位符要求，改判 content 非空，
// 空串会写回 '' 静默回内置）/ 超限全拒（占位符缺失文案与功能模型页保存 toast 同源——两处
// 同语义同句话；{maxItems} 不强制校验——缺 = 用户显式去掉条数约束，解析侧上限兜底）
export function validateEditTitlePromptArgs(argsJson: string): EditTitlePromptValidation {
  let action: string = '';
  let target: string = '';
  let content: string = '';
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    const rawAction: Object | undefined = parsed['action'];
    const rawTarget: Object | undefined = parsed['target'];
    const rawContent: Object | undefined = parsed['content'];
    if (typeof rawAction === 'string') {
      action = rawAction.trim();
    }
    if (typeof rawTarget === 'string') {
      target = rawTarget.trim();
    }
    if (typeof rawContent === 'string') {
      content = rawContent.trim();
    }
  } catch (e) {
    return rejectEditTitle('参数解析失败，需要 action 参数');
  }
  if (action !== 'get' && action !== 'set' && action !== 'reset') {
    return rejectEditTitle('action 必须是 get、set 或 reset');
  }
  if (target === '') {
    target = TOOL_PROMPT_SLOT_TITLE;
  }
  const spec: PromptSlotSpec | undefined = findPromptSlotSpec(target);
  if (spec === undefined) {
    return rejectEditTitle('target 必须是：' + TOOL_PROMPT_SLOTS.join('、'));
  }
  if (action === 'set') {
    if (content === '') {
      return rejectEditTitle('action 为 set 时需要 content 参数，值为提示词全文');
    }
    if (spec.required !== '' && !content.includes(spec.required)) {
      return rejectEditTitle('提示词须包含 ' + spec.required + ' 占位符，' + spec.requiredTip);
    }
    if (content.length > TEMPLATE_CONTENT_MAX) {
      return rejectEditTitle('content 超过 ' + TEMPLATE_CONTENT_MAX + ' 字上限，当前 ' +
        content.length + ' 字，请精简后再保存');
    }
  }
  return { ok: true, action: action, target: target, content: content, error: '' };
}

// 生成提示词执行器：get 生效模板现读（标题 resolveTitlePromptTemplate、记忆
// resolveMemoryPromptTemplate、记忆优化 resolveMemoryOptPromptTemplate、文字识别
// resolveOcrPromptTemplate，各自单源——定制键非空走定制、空回退各自内置）+ customized 标记
//（读各自定制键）；set 写各自定制键；reset 清各自键回内置（清删式语义，内置模板升级自动
// 跟随）。生效时机：四链每次生成、整理、优化或识别时现读，零缓存零广播
export class EditTitlePromptExecutor implements ToolExecutor {
  execute(argsJson: string): Promise<string> {
    const v: EditTitlePromptValidation = validateEditTitlePromptArgs(argsJson);
    if (!v.ok) {
      return Promise.resolve(JSON.stringify({ error: v.error }));
    }
    const spec: PromptSlotSpec | undefined = findPromptSlotSpec(v.target);
    if (spec === undefined) {
      // 校验已保证 target 在枚举内，此处仅类型守卫（新槽只加一张规格表行即可，不落到这里）
      return Promise.resolve(JSON.stringify({ error: '未知的提示词槽位：' + v.target }));
    }
    if (v.action === 'get') {
      const content: string = spec.effective();
      const customized: boolean = (AppStorage.get<string>(spec.key) ?? '') !== '';
      return Promise.resolve(JSON.stringify({ ok: true, action: 'get', target: v.target,
        content: content, customized: customized, chars: content.length }));
    }
    if (v.action === 'set') {
      AppStorage.setOrCreate<string>(spec.key, v.content);
      return Promise.resolve(JSON.stringify({ ok: true, action: 'set', target: v.target,
        chars: v.content.length, hint: '已保存，下次' + spec.when + '生效' }));
    }
    AppStorage.setOrCreate<string>(spec.key, '');
    return Promise.resolve(JSON.stringify({ ok: true, action: 'reset', target: v.target,
      hint: '已恢复为内置默认，下次' + spec.when + '生效' }));
  }
}
