// 功能模型域工具（决明拍板立项；四项拍板：独立新工具不并入设置白名单
// / 两件各司其职 / 各自带 get / 不开「关闭标题生成」——工具操作面 ⊆ UI 操作面纪律，
// manage_prompts 不开 delete 同理）。
// 两个内置工具，均 defaultEnabled=false（普通助手工具页「应用管理」卡显式开启；原
// console-exclusive 反向拦截随控制台合并笔退役）：
// · set_functional_model——功能模型五槽（默认对话 default / 标题生成 title / 记忆提取
//   memory / 记忆优化 memoryOpt / 命令审批 approval，各两键）查看、列可选清单与设置。合法值
//   口径 = 功能模型页选择器同款（仅启用服务商 + 其启用的对话模型）；定位用界面显示名
//  （provider.name / 模型 name 空则 modelId——与 FunctionalModelPage.resolveModelDisplay 同
//   口径），0 匹配回显可用清单、多匹配拒歧义。list action = 可选项清单查询面（客户端不做
//   模糊匹配——模型擅长对齐口语名与显示名，客户端加模糊规则反引入误改风险）。★默认对话
//   写后打 CONN_RESOLVE_TICK 广播（FunctionalModelPage.onPickModel 同款副作用——改全局默认
//   后已开会话页须重解析连接，漏打 = 已开会话仍走旧连接缓存，正确性缺口非优化）；标题与
//   记忆模型不进发送链无广播（生成链现读，写键即生效，无缓存消费点）。五槽的键对/广播/
//   回执提示走 FUNCTIONAL_SLOT_SPECS 映射表单源（schema 枚举 / 校验 / 执行器 / 断言四处
//   同读，禁同一分派各写一遍）。
// · edit_title_prompt——生成提示词七槽（标题 / 记忆整理 / 记忆优化 / 文字识别 / 记忆导入 /
//   上下文压缩 / 审批；'' = 未定制 = 生效各自内置模板）查看/修改/恢复。各槽随 UI 卡开
//   提示词键同批跟上（同一能力两个面不对称即缺口，历槽先例）。set 校验必须含该槽
//   requiredList 占位符（标题/记忆整理/记忆导入 = {content}，记忆优化 = {memories}，上下文
//   压缩 = {conversation}，命令审批 = 五占位符全——缺任一 = 该段信息不随请求给模型 = 盲判，
//   安全弱化；★ 逐槽取而非统一 {content}：优化链插的是条目清单不是对话原文，统一校验会让
//   缺 {memories} 的优化提示词通过、优化静默空转；多占位符槽缺项逐项列出）+ 长度上限
//   TEMPLATE_CONTENT_MAX 与编辑面板 maxLength 同值；reset = 清各自键回退内置（清删式语义，
//   内置模板升级自动跟随）。文字识别槽无占位符（识别图以附件部件随请求发送，非文本插值）
//   ——requiredList 空跳过占位符校验但空内容仍拒（空串写回 '' = 静默回内置，观感与动作
//   不符）。{maxItems} 不强制——缺 = 用户显式去掉条数约束，解析侧上限兜底。不传 target 按
//   标题生成提示词处理（向后兼容，既有说法行为零变化）。工具名不改（协议面 + seed 串 +
//   助手 tools CSV 列值；加槽只动规格表，schema/desc/校验/执行器自动跟随）。
// 关闭标题生成 / 关闭命令审批：UI 两卡各有总开关（TITLE_ENABLED_KEY / APPROVAL_ENABLED_KEY），
// 工具面**不提供**开关动作（安全与行为开关不给模型代操面——设置查询白名单克制
// 同款，防提示注入翻转安全设置）；desc 不提开关。
// 边界：模型/服务商 DB 读写与键定义在 ProviderDb，各提示词真源在各自域件（TitleGen /
// MemoryGen / MemoryOpt / OcrVisionApi / MemoryImport / CompressGen / ApprovalGate）——本文件
// 只做工具协议层（schema/desc/校验纯函数/执行器）；校验纯函数自包含可断言（断言脚本剥 TS
// 求值直跑）。
import { clipReceiptDiffValue, ConfirmPrompt, CONFIRM_LEVEL_WRITE,
  ToolExecutor } from './ToolContracts';
import { routeConfirmPrompt } from './ConfirmRouting';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { dataApproveMode } from '../AppPreferences';
import { CONN_RESOLVE_TICK_KEY, DEFAULT_MODEL_KEY, DEFAULT_PROVIDER_KEY, APPROVAL_MODEL_KEY,
  APPROVAL_PROVIDER_KEY, ModelRow,
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
import { APPROVAL_PROMPT_KEY, APPROVAL_PROMPT_REQUIRED,
  resolveApprovalPromptTemplate } from './ApprovalGate';
import { SETTING_TITLE_APPROVAL, SETTING_TITLE_DEFAULT_MODEL, SETTING_TITLE_MEMORY_MODEL,
  SETTING_TITLE_MEMORY_OPT_MODEL, SETTING_TITLE_TITLE_MODEL } from '../SettingSearch';

// 工具名常量 TOOL_SET_FUNCTIONAL_MODEL / TOOL_EDIT_TITLE_PROMPT 归口 ToolTypes.ets
//（与注册/反向拦截/seed 同源引用，本域不重复定义防漂移）。

// ── 槽位名常量与分派表（schema 枚举 / 校验 / 执行器 / 断言四处同源单读）──

// 功能模型五槽：槽位名沿用功能模型页的界面标题常量（模型据此对齐用户口语名；顺序 =
// 页内卡序 = 快照 slots 顺序）；schema 枚举与 desc 由本数组拼出、自动跟随
export const FUNCTIONAL_SLOTS: string[] = [SETTING_TITLE_DEFAULT_MODEL,
  SETTING_TITLE_TITLE_MODEL, SETTING_TITLE_MEMORY_MODEL, SETTING_TITLE_MEMORY_OPT_MODEL,
  SETTING_TITLE_APPROVAL];

// 提示词七槽：UI 侧没有同名界面标题（入口是各自卡里的提示词键），本域自开常量单源；不塞
// SettingSearch——那边常量被 setting-search-check 巡「须被注册表或 UI 引用」，非 UI 语义
// 常量会被顺手注册搜索条目 = 越界。★ 槽名与各链界面标题不构成契约，取词只按「模型能对齐
// 用户口语名」定（现与面板标题同字面量的槽属巧合，不是需要维持的约束）
export const TOOL_PROMPT_SLOT_TITLE: string = '标题生成提示词';
export const TOOL_PROMPT_SLOT_MEMORY: string = '记忆整理提示词';
export const TOOL_PROMPT_SLOT_MEMORY_OPT: string = '记忆优化提示词';
export const TOOL_PROMPT_SLOT_OCR: string = '文字识别提示词';
// 记忆导入槽与第二槽用途不同：第二槽「记忆整理提示词」从会话记录提取记忆，本槽从
// **外部平台文本**整理记忆（导入页「AI 整理」用），故独立成槽
export const TOOL_PROMPT_SLOT_MEMORY_IMPORT: string = '记忆导入提示词';
// 上下文压缩槽：交接摘要生成提示词——输入域（会话转写文本）与其余槽皆不同，独立成槽；
// 键与内置模板单源 CompressGen 域
export const TOOL_PROMPT_SLOT_COMPRESS: string = '上下文压缩提示词';
// 审批槽（决明拍板「审批提示词开放编辑」）：命令审批提示词查看/修改/恢复，UI 卡开键后
// 同批跟上（同前面各槽先例）；键与内置模板单源 ApprovalGate 域
export const TOOL_PROMPT_SLOT_APPROVAL: string = '审批提示词';
export const TOOL_PROMPT_SLOTS: string[] = [TOOL_PROMPT_SLOT_TITLE, TOOL_PROMPT_SLOT_MEMORY,
  TOOL_PROMPT_SLOT_MEMORY_OPT, TOOL_PROMPT_SLOT_OCR, TOOL_PROMPT_SLOT_MEMORY_IMPORT,
  TOOL_PROMPT_SLOT_COMPRESS, TOOL_PROMPT_SLOT_APPROVAL];

// 提示词槽规格（schema 枚举 / 校验 / 执行器 / 断言四处同源单读，禁同一分派各写一遍）：
// key = 定制键；requiredList = 必须保留的占位符数组（逐槽不同见文件头；[] = 本槽无占位符
// 不校验，现仅文字识别槽如此）；requiredTip = 缺占位符文案的用途后缀（requiredList 空槽或
// 多占位符槽不用）；when = 生效时机（回执转述用）；effective = 生效模板现读函数（各域
// 单源，本域不重写选择规则）
export interface PromptSlotSpec {
  target: string;
  key: string;
  requiredList: string[];
  requiredTip: string;
  when: string;
  effective: () => string;
}

export const PROMPT_SLOT_SPECS: PromptSlotSpec[] = [
  { target: TOOL_PROMPT_SLOT_TITLE, key: TITLE_PROMPT_KEY, requiredList: [TITLE_PROMPT_CONTENT],
    requiredTip: '用于插入对话内容', when: '生成标题', effective: resolveTitlePromptTemplate },
  { target: TOOL_PROMPT_SLOT_MEMORY, key: MEMORY_PROMPT_KEY, requiredList: [MEMORY_PROMPT_CONTENT],
    requiredTip: '用于插入对话内容', when: '整理记忆', effective: resolveMemoryPromptTemplate },
  { target: TOOL_PROMPT_SLOT_MEMORY_OPT, key: MEMORY_OPT_PROMPT_KEY,
    requiredList: [MEMORY_OPT_PROMPT_MEMORIES], requiredTip: '用于插入记忆条目清单', when: '优化记忆',
    effective: resolveMemoryOptPromptTemplate },
  { target: TOOL_PROMPT_SLOT_OCR, key: OCR_PROMPT_KEY, requiredList: [],
    requiredTip: '', when: '识别', effective: resolveOcrPromptTemplate },
  { target: TOOL_PROMPT_SLOT_MEMORY_IMPORT, key: MEMORY_IMPORT_PROMPT_KEY,
    requiredList: [MEMORY_IMPORT_PROMPT_CONTENT], requiredTip: '用于插入待整理的文本',
    when: '导入页整理外部文本', effective: resolveMemoryImportPromptTemplate },
  { target: TOOL_PROMPT_SLOT_COMPRESS, key: COMPRESS_PROMPT_KEY,
    requiredList: [COMPRESS_PROMPT_CONVERSATION], requiredTip: '用于插入待压缩的对话记录',
    when: '压缩上下文', effective: resolveCompressPromptTemplate },
  { target: TOOL_PROMPT_SLOT_APPROVAL, key: APPROVAL_PROMPT_KEY,
    requiredList: APPROVAL_PROMPT_REQUIRED, requiredTip: '用于插入审批所需的各项信息',
    when: '审批工具调用', effective: resolveApprovalPromptTemplate }
];

// 槽规格查找（校验与执行器共用；未命中回 undefined——校验据此拒非法 target，执行器处是
// 类型守卫分支）
export function findPromptSlotSpec(target: string): PromptSlotSpec | undefined {
  return PROMPT_SLOT_SPECS.find((row: PromptSlotSpec): boolean => row.target === target);
}

// 五槽分派规格：providerKey/modelKey = 目标键对；broadcast = 是否打连接重解析广播（仅默认
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
    hint: '已保存，之后优化记忆时使用新模型' },
  // 审批槽：两键 = ApprovalGate 审批闸消费，未配置 = 确认链照旧弹人工卡；broadcast false =
  // 不进发送链零广播（同标题/记忆槽口径）
  { target: SETTING_TITLE_APPROVAL, providerKey: APPROVAL_PROVIDER_KEY,
    modelKey: APPROVAL_MODEL_KEY, broadcast: false,
    hint: '已保存，之后需要确认的工具调用先由新审批模型自动审核' }
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

// desc 动态拼槽位标题常量（单源防漂移；模型清单不进 desc——合法值随 DB 动态变化，注册时
// 静态生成的 schema/desc 装不下，调用纪律 + 执行层校验兜底）
export function buildSetFunctionalModelDesc(): string {
  return '查看或修改本应用的功能模型。' + SETTING_TITLE_DEFAULT_MODEL +
    '模型在会话未选择模型且助手未绑定模型时自动用于发送；' + SETTING_TITLE_TITLE_MODEL +
    '模型用于自动生成会话标题，未配置则不启用标题生成；' + SETTING_TITLE_MEMORY_MODEL +
    '用于整理记忆时提取记忆条目，未配置则不整理记忆，也不会改用标题生成模型；' +
    SETTING_TITLE_MEMORY_OPT_MODEL + '用于对已有的记忆做去重与改写，未配置则不优化，' +
    '也不会改用前面的模型。' + SETTING_TITLE_APPROVAL +
    '用于在执行需要确认的工具调用前自动审核，通过即执行、拒绝则拒绝，未配置则照旧请求用户确认，' +
    '也不会改用前面的模型。' +
    'action 取 get 返回各槽位当前的' +
    '服务商名与模型名，list 列出当前可选的启用服务商与其启用对话模型；' +
    'set 用 target 指定槽位，provider 与 model 传界面上显示的名称，' +
    '只能选已启用服务商下的已启用对话模型，传错会返回当前可选清单。' +
    '用户询问有哪些模型可选时用 list；用户说的模型名不确定时可以先 list 对齐后再 set。' +
    'set 仅在用户明确要求切换功能模型时调用，不要猜测或主动建议。';
}

// 确认链预检：只拦写向 set——功能槽模型绑定改的是全局功能路由（标题 / 记忆 / 审批等链路
// 用哪个模型）；get / list 读向直通。档位恒 CONFIRM_LEVEL_WRITE（改绑定可再改回，非删除族；
// 三档豁免与去向归一在 routeConfirmPrompt 单点）。卡面主因句带槽位、服务商与模型名。
// 全包 try/catch 恒 null
export async function setFunctionalModelNeedsConfirm(argsJson: string,
  _ctx: ToolExecutionContext): Promise<ConfirmPrompt | null> {
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    const actionRaw: Object | undefined = parsed['action'];
    if (typeof actionRaw !== 'string' || actionRaw.trim() !== 'set') {
      return null;
    }
    const readStr = (key: string): string => {
      const raw: Object | undefined = parsed[key];
      return typeof raw === 'string' ? raw.trim() : '';
    };
    const target: string = readStr('target');
    if (target === '') {
      return null; // 槽位缺 = 执行器会报参数错，不弹卡
    }
    return routeConfirmPrompt({ text: '将「' + target + '」功能模型改为「' + readStr('provider') +
      '」的「' + readStr('model') + '」', level: CONFIRM_LEVEL_WRITE }, dataApproveMode());
  } catch (e) {
    return null;
  }
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
// target 不在五槽位枚举全拒；get 与 list 宽松（多余参数忽略——两 action 均恒返回全量）
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

// 功能模型执行器：get 五槽位快照（按规格读键对 + 查表解析显示名）；list 可选项清单（启用
// 服务商 → 其启用对话模型显示名）；set 按显示名定位（启用服务商 → 其启用对话模型，0 匹配
// 回显清单 / 多匹配拒歧义）→ 按规格写键对（默认对话另打 tick 广播对齐 UI，标题与记忆槽
// 无广播）。DB 查询抛错上抛由 executeToolCall 统一包装 error JSON
export class SetFunctionalModelExecutor implements ToolExecutor {
  execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
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
      // 五槽分派走映射表单源（校验已保证 target 在枚举内，undefined 分支是类型守卫）
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

  // 五槽位快照（顺序 = 映射表序 = 功能模型页卡序）：按规格读键对 → 查表解析显示名
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
    TOOL_PROMPT_SLOT_COMPRESS + '在压缩上下文时把对话记录整理成交接摘要；' +
    TOOL_PROMPT_SLOT_APPROVAL + '在需要确认的工具调用执行前由审批模型按其中的规则自动审核。' +
    '前两类提示词中的 ' + TITLE_PROMPT_CONTENT + ' 占位符会被替换为对话内容，必须保留；' +
    TOOL_PROMPT_SLOT_MEMORY_OPT + '中的 ' + MEMORY_OPT_PROMPT_MEMORIES + ' 占位符会被替换为' +
    '记忆条目清单，同样必须保留；' + TOOL_PROMPT_SLOT_MEMORY_IMPORT + '中的 ' +
    MEMORY_IMPORT_PROMPT_CONTENT + ' 占位符会被替换为待整理的文本，同样必须保留；' +
    TOOL_PROMPT_SLOT_COMPRESS + '中的 ' + COMPRESS_PROMPT_CONVERSATION +
    ' 占位符会被替换为待压缩的对话记录，同样必须保留；' +
    TOOL_PROMPT_SLOT_APPROVAL + '中的 ' + APPROVAL_PROMPT_REQUIRED.join('、') +
    ' 五个占位符会被替换为对话前文、工具名、风险档位、预检说明与参数，全部必须保留；' +
    TOOL_PROMPT_SLOT_OCR + '不含占位符，直接写识别要求即可。' +
    MEMORY_PROMPT_MAX_ITEMS + ' 占位符仅 ' + TOOL_PROMPT_SLOT_MEMORY + ' 与 ' +
    TOOL_PROMPT_SLOT_MEMORY_IMPORT + ' 可选，会被替换为' +
    '条数上限，去掉则不限制条数；' + COMPRESS_PROMPT_SUPPLEMENT + ' 占位符仅 ' +
    TOOL_PROMPT_SLOT_COMPRESS + ' 可选，会被替换为本次压缩的补充要求，去掉则不追加。' +
    'action 取 get 返回当前生效全文与是否定制，set 用 content ' +
    '全文替换（上限 ' + TEMPLATE_CONTENT_MAX + ' 字，必须包含该槽位要求的占位符），' +
    'reset 恢复为内置默认。仅在用户明确要求查看或修改提示词时调用；' +
    'set 是整体替换，用户只想局部调整时先 get 再基于原文生成新全文。保存后下次生成、整理、优化、识别或审批时生效。';
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
// 缺该槽 requiredList 占位符全拒（requiredList 空槽——文字识别——跳过占位符要求、改判
// content 非空：空串写回 '' = 静默回内置；单占位符槽原文案含用途说明，多占位符槽逐项列缺
// 哪个）/ 超限全拒（占位符缺失文案与功能模型页保存 toast 同源——两处同语义同句话；
// {maxItems} 不强制——缺 = 用户显式去掉条数约束，解析侧上限兜底）
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
    const missing: string[] = spec.requiredList
      .filter((p: string): boolean => !content.includes(p));
    if (missing.length > 0) {
      return rejectEditTitle(spec.requiredList.length === 1
        ? '提示词须包含 ' + spec.requiredList[0] + ' 占位符，' + spec.requiredTip
        : '提示词缺少占位符 ' + missing.join('、') + '，缺少时保存会被拦截');
    }
    if (content.length > TEMPLATE_CONTENT_MAX) {
      return rejectEditTitle('content 超过 ' + TEMPLATE_CONTENT_MAX + ' 字上限，当前 ' +
        content.length + ' 字，请精简后再保存');
    }
  }
  return { ok: true, action: action, target: target, content: content, error: '' };
}

// 生成提示词执行器：get 生效模板现读（经规格表 effective 各域单源——定制键非空走定制、
// 空回退各自内置）+ customized 标记（读各自定制键）；set 写各自定制键；reset 清各自键回
// 内置（清删式语义，内置模板升级自动跟随）。各链每次生成/整理/优化/识别时现读，零缓存零广播
export class EditTitlePromptExecutor implements ToolExecutor {
  execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
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
      // 写前读旧生效文（get 分支同源 spec.effective）——回执带 oldValue/newValue 供工具卡
      // 红绿 diff；值经 clipReceiptDiffValue 单源截断
      const oldValue: string = clipReceiptDiffValue(spec.effective());
      AppStorage.setOrCreate<string>(spec.key, v.content);
      return Promise.resolve(JSON.stringify({ ok: true, action: 'set', target: v.target,
        chars: v.content.length, oldValue: oldValue, newValue: clipReceiptDiffValue(v.content),
        hint: '已保存，下次' + spec.when + '生效' }));
    }
    // reset 不加 diff 键（恢复内置默认无前后对比语义，回执逐字不变）
    AppStorage.setOrCreate<string>(spec.key, '');
    return Promise.resolve(JSON.stringify({ ok: true, action: 'reset', target: v.target,
      hint: '已恢复为内置默认，下次' + spec.when + '生效' }));
  }
}
