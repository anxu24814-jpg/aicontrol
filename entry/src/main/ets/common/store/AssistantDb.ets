// 助手存储域（照 PromptTemplateDb 域拆先例）：assistants 表 CRUD + conversations.assistantId
// 会话引用读写。语义参照 RikkaHub 助手裁剪（清单见 docs/调研与待办-助手与提示词变量.md）：
// ①助手 = 名称 + 提示词；提示词支持 {{date}}/{{time}} 等变量（发送前应用层替换，任意注入源
//   统一生效，PromptVariables.ets）；
// ②引用跟随——会话存助手 id，助手修改后引用会话下次发送自动用新版；
// ③注入优先级（ChatPromptState 解析；2026-09-04 决明拍板归属与注入解耦）：会话恒归属一个
//   助手，提示词注入 = 独立开关（开 = 模板覆盖不注入助手提示词、关 = 注入归属助手提示词）；
//   优先级 = 会话提示词 > 助手提示词 > 系统提示词；归属助手的高级参数/工具恒生效不随开关清
//   空；行 ''（存量未绑定）= 内置默认助手兜底显式归属，无行新会话 = 面板覆盖 ?? 当前助手 ??
//   默认助手（「跟随当前」语义已撤销）；
// ④删助手 = 硬级联无软删除（RikkaHub 同款拍板）：deleteAssistantCascade 同事务多删
//   （messages → conversations → assistants；v35 起加删 assistant_memories、v41 起加删
//   memory_snapshots——库跟着人走，与全局 memories 置空保留口径刻意不同；v57/v58 起加删
//   send_queue_items/state——会话删后队列不可达，残留即孤儿行）；确认文案写明「名下 N 个
//   会话一并删除不可恢复」；删当前助手由调用方（AssistantPage）重置 active 键 + 重拉广播；
// ⑤内置默认助手 = 固定 id ASSISTANT_DEFAULT_ID 行，禁删禁改（提示词恒与系统提示词同步）：
//   ensureDefaultAssistant 启动幂等兜底（无行才插）；deleteAssistantCascade 守卫禁删；提示词
//   同步机制 = **读时联结**（syncDefaultPrompt）——行 prompt 列恒 '' 不落盘，读取时以
//   queryGlobalTemplate 内容替换，单一真源 = prompt-global 行，无缓存无同步窗口；编辑页对
//   默认卡只读；
// ⑥内置控制台助手已退役（2026-10-25 决明拍板）：行随 ChatDbMigrate v62 删除、名下会话改指
//   默认助手，原独占工具域开放给全部助手，seed 迁移机制与读时联结同笔退役（沿革见变更记录）；
// ⑦名称与提示词分页编辑，各单列 UPDATE（名称行卡对话框即时落库 / 提示词二级页「保存」键）；
//   新建 = 列表页「＋」对话框（取消不落行）；删除唯一入口 = 列表卡「更多」菜单「删除」项；
// ⑧模型绑定（DB v10 三列）：providerId/modelId（'' = 未绑定，选择即落库不经保存键）+
//   thinkLevel（枚举同 AiTypes.THINKING_OPTIONS）；清删 = 删服务商/删模型时级联清列
//   （clearAssistantBindingByProvider/ByModel）；发送链 = resolveActiveConnection 四级兜底
//   第②级（会话页所选 > 本绑定 > 全局默认 > 首个启用模型），消费链见 ProviderDb 头注释；
// ⑨高级设定（DB v11）：advancedParams = 采样与上下文参数 JSON 串（'' = 未配置 = 全部不发送；
//   结构/解析在 AiTypes）；删服务商/删模型**不清本列**（采样参数跨模型通用，与 thinkLevel
//   语义不同）；发送链 = ChatPromptState.load → ChatSendCtrl → RequestCompose 落点；
// ⑩knowledge（DB v38）= 启用知识库 id 清单 JSON 串（'' = 空集合 = 不启用，与 skills 同义、
//   与 tools 相反；解析单点 = KnowledgeText）；上限 KNOWLEDGE_ENABLED_MAX 在页面侧拦截；
//   清删 = KnowledgeDb.deleteBookCascade 事务内联动清列（读取侧「启用 ∩ 现存」过滤是第二道
//   保险）；启用集非空时 search_knowledge 进声明。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { relationalStore } from '@kit.ArkData';
import { nextMessageId, sharedRdbStore } from './ChatDb';
import { runWriteQueued } from './DbWriteQueue';
import { attachmentFilesDir, deleteAttachmentsForConversations, removeAttachmentFiles } from './AttachmentDb';
import { deleteAvatarFile } from '../AvatarSpec';
import { credIdsOf, purgeOwnerAssets, removeCredOwnerMeta } from '../providers/HttpCredentials';
// ToolLimits/SearchLimits 两默认值 import 已随工具运行参数全局化笔移除（本域不再持这两个默认值）
import { PromptTemplateRow, queryGlobalTemplate } from './PromptTemplateDb';
import { clearMemoryAssistantRef, deleteAssistantMemoriesOfAssistant,
  deleteMemorySnapshotsOfAssistant, MEMORY_SCOPE_GLOBAL } from './MemoryDb';
// 会话临时区与两执行域级联（门 2 同笔补齐对称缺口——对照 ChatDb.deleteConversations 的
// commit 后 best-effort 三段：临时区目录 / Python 命名空间 / Node 会话 worker；依赖方向
// store → { WorkspaceDbTmp, pyexec, nodeexec } 均无回边）
import { collectTmpForConversations, deleteWorkspaceTmpConversationsQuiet } from './WorkspaceDbTmp';
import { dropPyNamespacesQuiet } from '../pyexec/PyRuntime';
import { dropNodeForConversation } from '../nodeexec/NodeScheduler';

const DOMAIN: number = 0xD5A4;
const TAG: string = 'AssistantDb';

// 内置默认助手固定 id（seed 兜底与禁删守卫共用；UI 判定「菜单不出删除项」同用）
export const ASSISTANT_DEFAULT_ID: string = 'assistant-default';
export const ASSISTANT_DEFAULT_NAME: string = '默认助手';

// 当前助手持久键（AppStorage persistProp）：写入点唯一 = 助手页签；消费方 = 历史列表过滤
//（historyFilterIds）/ 新会话落行绑定 / 注入链新会话回退（ChatPromptState）
export const ACTIVE_ASSISTANT_KEY: string = 'activeAssistantId';

// 历史列表过滤口径（'' 统一 = 内置默认助手，「跟随当前」语义已撤销）：默认助手名下 = 显式
// 绑定 + 存量 '' 行；其余助手 = 自身 id 单值。返回纯数组字面量（坑6 族：in() 入参须非观察代理）
export function historyFilterIds(activeId: string): string[] {
  return activeId === ASSISTANT_DEFAULT_ID ? [ASSISTANT_DEFAULT_ID, ''] : [activeId];
}

// 名称/提示词长度上限（编辑页 maxLength 同值；有界红线：提示词 = 注入上下文体积）
export const ASSISTANT_NAME_MAX: number = 50;
export const ASSISTANT_PROMPT_MAX: number = 2000;

export interface AssistantRow {
  id: string;
  name: string;
  prompt: string;
  createdAt: number;
  // 列表自定义序（v40）：小者在前、0 起——列表序唯一权威（UI 无任何位置特判）。回写 =
  // saveAssistantOrder 按卡片序赋下标；新建取 max+1 落尾；并列时 createdAt 决胜
  sortOrder: number;
  // 模型绑定三列（v10）：providerId/modelId（'' = 未绑定）；thinkLevel 枚举同
  // AiTypes.THINKING_OPTIONS
  providerId: string;
  modelId: string;
  thinkLevel: string;
  // 高级设定参数（v11）：采样与上下文参数 JSON 串（'' = 未配置；解析单点在 AiTypes，本域只存原串）
  advancedParams: string;
  // 启用工具 id 清单（v14）：JSON 串（'' = 默认集合；解析单点 = ToolTypes，本域只存原串）
  tools: string;
  // 记忆两开关（v20）：memoryInject = 发送时注入记忆块 / memorySink = 退出会话时整理沉淀；
  // 默认 true = 存量助手升级后默认参与（零行为变化）
  memoryInject: boolean;
  memorySink: boolean;
  // 工具调用轮数/搜索条数两列（v22/v25）★已退役墓碑（2026-09-27 全局化笔拍板）——两值改由
  // 全局偏好键 prefToolStepLimit / prefSearchResultCount 承载（控制面 = 设置页工具调用页），
  // 本接口不取这两列、库内保留墓碑不迁移、禁接回（见 ChatDbSchema 同列注释）
  // 启用技能 id 清单（v30）：JSON 串（★语义与 tools **刻意相反**——'' = 空集合 = 不启用任何
  // 技能；解析单点 = SkillText，本域只存原串）
  skills: string;
  // 记忆作用域（v35）：'global' 默认 = memories 表路径 / 'assistant' = assistant_memories
  // 自己的库；枚举常量在 MemoryDb，读取空串兜底 'global'
  memoryScope: string;
  // 启用知识库 id 清单（v38）：JSON 串（★语义与 skills 相同、与 tools 相反——'' = 空集合 = 不启用任何知识库；
  // 解析单点 = KnowledgeText，本域只存原串）
  knowledge: string;
  // 头像（v45）：'' = 首字圆底；'text:<内容>'（≤2 码点）；'image:<uri>'；解析单点 = AvatarSpec
  avatar: string;
  // 关键词自动注入开关（v51）：true = 发送时对最近对话做关键词匹配、命中条目自动进上下文；
  // 默认 **false = 关**（拍板——存量助手升级后不自动注入，请求逐字节同升级前）；消费链 =
  // ChatPromptState → ChatSnapshotCtrl.buildKnowledgeBlock；写点 = 本页开关行函数
  knowledgeAutoInject: boolean;
  // 启用 MCP 服务器 id 清单（v59）：JSON 串（★语义照 skills/knowledge——'' 含坏 JSON = 空集合；
  // 启用口径 = 全局 enabled 行 ∩ 本列勾选）。解析单点 = McpText（**禁复用 skills/knowledge/
  // tools 既有解析函数**——四列语义各异）；写点 = updateAssistantMcpServers；删服务器时
  // McpDb 联动剔列
  mcpServers: string;
}

function requireStore(): relationalStore.RdbStore {
  return sharedRdbStore();
}

// 助手表读投影列清单（单源）：列表读与单行读共用，新增列只改这一处；行映射 = mapAssistantRow
const ASSISTANT_COLUMNS: string[] = ['id', 'name', 'prompt', 'createdAt', 'sortOrder',
  'providerId', 'modelId', 'thinkLevel', 'advancedParams', 'tools', 'memoryInject', 'memorySink',
  'skills', 'memoryScope', 'knowledge', 'avatar', 'knowledgeAutoInject', 'mcpServers'];

// 当前行 → AssistantRow（行映射单源）：===1 布尔归一与 memoryScope 空串兜底，两处 query 共用
function mapAssistantRow(result: relationalStore.ResultSet): AssistantRow {
  return {
    id: result.getString(result.getColumnIndex('id')),
    name: result.getString(result.getColumnIndex('name')),
    prompt: result.getString(result.getColumnIndex('prompt')),
    createdAt: result.getLong(result.getColumnIndex('createdAt')),
    sortOrder: result.getLong(result.getColumnIndex('sortOrder')),
    providerId: result.getString(result.getColumnIndex('providerId')),
    modelId: result.getString(result.getColumnIndex('modelId')),
    thinkLevel: result.getString(result.getColumnIndex('thinkLevel')),
    advancedParams: result.getString(result.getColumnIndex('advancedParams')),
    tools: result.getString(result.getColumnIndex('tools')),
    memoryInject: result.getLong(result.getColumnIndex('memoryInject')) === 1,
    memorySink: result.getLong(result.getColumnIndex('memorySink')) === 1,
    skills: result.getString(result.getColumnIndex('skills')),
    memoryScope: result.getString(result.getColumnIndex('memoryScope')) || MEMORY_SCOPE_GLOBAL,
    knowledge: result.getString(result.getColumnIndex('knowledge')),
    avatar: result.getString(result.getColumnIndex('avatar')),
    knowledgeAutoInject: result.getLong(result.getColumnIndex('knowledgeAutoInject')) === 1,
    mcpServers: result.getString(result.getColumnIndex('mcpServers'))
  };
}

// 全量助手（列表 / 选助手面板 / 设置记忆页库列表；序 = sortOrder 升序 + createdAt 升序决胜
// ——v40 起列表序单键权威，内置两张可被用户拖到任意位置、唯一内置特权 = 禁删，存量序由 v40
// 迁移回填复刻）。默认助手 prompt 经读时联结替换为系统提示词；用户手建小数据集自然有界
export async function queryAssistants(): Promise<AssistantRow[]> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.orderByAsc('sortOrder');
  predicates.orderByAsc('createdAt');
  const result: relationalStore.ResultSet = await requireStore().query(predicates, ASSISTANT_COLUMNS);
  const rows: AssistantRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push(mapAssistantRow(result));
    }
  } finally {
    result.close();
  }
  const def: AssistantRow | undefined =
    rows.find((row: AssistantRow): boolean => row.id === ASSISTANT_DEFAULT_ID);
  if (def !== undefined) {
    await syncDefaultPrompt(def);
  }
  return rows;
}

// 列表序持久化（saveProviderOrder 同形制）：ids = 全量 id 数组，逐行回写 sortOrder = 下标
//（小数据集整表回写开销可忽略；不回写 createdAt）
export async function saveAssistantOrder(ids: string[]): Promise<void> {
  for (let i = 0; i < ids.length; i++) {
    const bucket: relationalStore.ValuesBucket = { 'sortOrder': i };
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
    predicates.equalTo('id', ids[i]);
    await requireStore().update(bucket, predicates);
  }
}

// 下一位列表序（新建落尾，取 max+1；空表 = 0）；单列聚合查询不触发读时联结与全列投影
async function nextAssistantSortOrder(): Promise<number> {
  const result: relationalStore.ResultSet =
    await requireStore().querySql('SELECT MAX(sortOrder) AS maxOrder FROM assistants');
  try {
    if (result.goToNextRow()) {
      const idx: number = result.getColumnIndex('maxOrder');
      // 空表 MAX = NULL（getLong 降级值不保证 0，显式判空给 0）
      return result.isColumnNull(idx) ? 0 : result.getLong(idx) + 1;
    }
    return 0;
  } finally {
    result.close();
  }
}

// 默认助手提示词读时联结（头注释⑤）：行 prompt 恒 '' 不落盘，读取时以系统提示词行内容替换
// ——注入链与全部 UI 展示自动同源；读取失败保留行内值（'' = 无注入）不炸链路
async function syncDefaultPrompt(row: AssistantRow): Promise<AssistantRow> {
  try {
    const globalRow: PromptTemplateRow = await queryGlobalTemplate();
    row.prompt = globalRow.content;
  } catch (e) {
  }
  return row;
}

// 内置默认助手兜底（启动一次性幂等，失败下次重试）：无行才插；已存在零触碰不覆盖
export async function ensureDefaultAssistant(): Promise<void> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', ASSISTANT_DEFAULT_ID);
  const result: relationalStore.ResultSet = await requireStore().query(predicates, ['id']);
  try {
    if (result.rowCount > 0) {
      return;
    }
  } finally {
    result.close();
  }
  const bucket: relationalStore.ValuesBucket = {
    'id': ASSISTANT_DEFAULT_ID, 'name': ASSISTANT_DEFAULT_NAME, 'prompt': '',
    'createdAt': Date.now(), 'sortOrder': await nextAssistantSortOrder()
  };
  await requireStore().insert('assistants', bucket);
}

// 按 id 查助手（查不到 = null，调用方回退既有注入链）；默认助手经读时联结——返回 prompt =
// 系统提示词内容（注入链与展示共用，同步语义单点落位）
export async function queryAssistant(id: string): Promise<AssistantRow | null> {
  if (id === '') {
    return null;
  }
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const result: relationalStore.ResultSet = await requireStore().query(predicates, ASSISTANT_COLUMNS);
  try {
    if (result.rowCount > 0 && result.goToNextRow()) {
      const row: AssistantRow = mapAssistantRow(result);
      if (row.id === ASSISTANT_DEFAULT_ID) {
        return syncDefaultPrompt(row);
      }
      return row;
    }
    return null;
  } finally {
    result.close();
  }
}

// 新增助手（名称非空由调用方校验；列表序 = max+1 落尾）。写默认同源：返回行与写库 bucket
// 由同一构造派生，默认值集合只写一处（'' 系列列 + 两记忆开关 true + memoryScope global 等）
export async function insertAssistant(name: string, prompt: string): Promise<AssistantRow> {
  const sortOrder: number = await nextAssistantSortOrder();
  const row: AssistantRow = {
    id: nextMessageId('asst'),
    name: name,
    prompt: prompt,
    createdAt: Date.now(),
    sortOrder: sortOrder,
    providerId: '',
    modelId: '',
    thinkLevel: '',
    advancedParams: '',
    tools: '',
    memoryInject: true,
    memorySink: true,
    // 工具运行参数全局化笔：toolStepLimit / searchResultCount 两键已自本桶移除（改由全局
    // 偏好键承载，不再按助手落库；墓碑列由建表默认值兜）
    skills: '',
    memoryScope: MEMORY_SCOPE_GLOBAL,
    knowledge: '',
    avatar: '',
    knowledgeAutoInject: false, // 默认关（列 DEFAULT 0 同源）
    mcpServers: '' // 默认空集合（列 DEFAULT '' 同源）
  };
  const bucket: relationalStore.ValuesBucket = {
    'id': row.id, 'name': row.name, 'prompt': row.prompt, 'createdAt': row.createdAt,
    'sortOrder': row.sortOrder,
    'providerId': row.providerId, 'modelId': row.modelId, 'thinkLevel': row.thinkLevel,
    'advancedParams': row.advancedParams, 'tools': row.tools,
    'memoryInject': row.memoryInject ? 1 : 0, 'memorySink': row.memorySink ? 1 : 0,
    'skills': row.skills,
    'memoryScope': row.memoryScope, 'knowledge': row.knowledge, 'avatar': row.avatar,
    'knowledgeAutoInject': row.knowledgeAutoInject ? 1 : 0,
    'mcpServers': row.mcpServers
  };
  await requireStore().insert('assistants', bucket);
  return row;
}

// 更新助手名称（分区化单列 UPDATE）。0 行 throw = P0-1 假成功防御（行已删时调用方 toast
//「已保存」= 撒谎，下同）
export async function updateAssistantName(id: string, name: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'name': name };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 更新助手提示词（提示词二级页「保存」；引用跟随）。0 行 throw 同上
export async function updateAssistantPrompt(id: string, prompt: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'prompt': prompt };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 更新助手头像（换头像面板四方式统一落库口；入参 = AvatarSpec 序列化产物或 ''）。旧本地
// 头像文件删除不在本层（调用方编排：写库前查旧值、成功后 best-effort 删，避免半成品态）。
// 0 行 throw 同上
export async function updateAssistantAvatar(id: string, avatar: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'avatar': avatar };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 更新模型绑定（选择即时落库不经保存键；providerId+modelId 一个语义单元同批 UPDATE）。
// 0 行 throw 同上
export async function updateAssistantModelBinding(id: string, providerId: string,
  modelId: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'providerId': providerId, 'modelId': modelId };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 更新思考档位（值域 = AiTypes.THINKING_OPTIONS，'' = 默认不传）。0 行 throw 同上
export async function updateAssistantThinkLevel(id: string, level: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'thinkLevel': level };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 更新高级设定参数（三级页返回统一落库；入参 = AiTypes 序列化串，'' = 全默认）。0 行 throw 同上
export async function updateAssistantAdvancedParams(id: string, params: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'advancedParams': params };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 更新启用工具清单（入参 = ToolTypes 序列化串，默认集合存 ''）。0 行 throw 同上
export async function updateAssistantTools(id: string, tools: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'tools': tools };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 更新记忆两开关（注入/沉淀一个语义单元同批 UPDATE）。0 行 throw 同上
export async function updateAssistantMemoryFlags(id: string, memoryInject: boolean,
  memorySink: boolean): Promise<void> {
  const bucket: relationalStore.ValuesBucket =
    { 'memoryInject': memoryInject ? 1 : 0, 'memorySink': memorySink ? 1 : 0 };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 更新记忆作用域（'global'/'assistant' 枚举校验在调用方，本层直存）。0 行 throw 同上
export async function updateAssistantMemoryScope(id: string, scope: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'memoryScope': scope };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 原两 update 函数（工具轮数/搜索条数）已随全局化笔删除——两值改由全局偏好键承载（设置页
// 工具调用页写即持久化），本域不再有按助手写这两值的入口；两列库内退役为墓碑不迁移、禁接回
//（见 ChatDbSchema 同列注释）

// 更新启用技能清单（入参 = SkillText 序列化串，'' = 空集合；上限 SKILL_ENABLED_MAX 在页面
// 侧拦截，本层不二次判定——两处判定 = 两处漂移面）。0 行 throw 同上
export async function updateAssistantSkills(id: string, skills: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'skills': skills };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 更新启用知识库清单（入参 = KnowledgeText 序列化串，'' = 空集合；上限在页面侧拦截，与
// updateAssistantSkills 同口径）。0 行 throw 同上
export async function updateAssistantKnowledge(id: string, knowledge: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'knowledge': knowledge };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 更新关键词自动注入开关（开关改动下次发送即生效——读取走 load 链重读 DB 无缓存）。0 行 throw 同上
export async function updateAssistantKnowledgeAutoInject(id: string,
  flag: boolean): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'knowledgeAutoInject': flag ? 1 : 0 };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 更新启用 MCP 服务器清单（入参 = McpText 序列化串，'' = 空集合；上限 MCP_SERVERS_MAX 在
// 页面侧拦截，与 skills/knowledge 同口径）。0 行 throw 同上
export async function updateAssistantMcpServers(id: string, mcpServers: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'mcpServers': mcpServers };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 级联清绑定列（deleteProvider 事务内调用）：该服务商绑定全清（三列一起归空——档位离开
// 原服务商无意义）。返回清空行数（停用路径据此给回执）
export async function clearAssistantBindingByProvider(providerId: string): Promise<number> {
  const bucket: relationalStore.ValuesBucket =
    { 'providerId': '', 'modelId': '', 'thinkLevel': '' };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('providerId', providerId);
  return await requireStore().update(bucket, predicates);
}

// 级联清绑定列（deleteModel 调用）：只清「绑定该服务商该模型」的行（换绑其他模型不受影响）。
// 返回清空行数
export async function clearAssistantBindingByModel(providerId: string, modelId: string): Promise<number> {
  const bucket: relationalStore.ValuesBucket =
    { 'providerId': '', 'modelId': '', 'thinkLevel': '' };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('providerId', providerId);
  predicates.equalTo('modelId', modelId);
  return await requireStore().update(bucket, predicates);
}

// 助手名下会话数（删除确认文案用；只查显式绑定值——删助手不级联未绑定会话）。★ 与
// queryAssistantConversationCounts 口径刻意不同，禁合并（见其注释）
export async function queryAssistantConversationCount(id: string): Promise<number> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('assistantId', id);
  const result: relationalStore.ResultSet = await requireStore().query(predicates, ['id']);
  try {
    return result.rowCount;
  } finally {
    result.close();
  }
}

// 全助手会话计数（卡面「会话」chip 用，一条 GROUP BY 免逐助手循环）。★ 回**原始分桶**（键 =
// assistantId 原值含 '' 桶），归并交调用方按 historyFilterIds 做（默认助手名下 = 显式绑定 +
// ''，与历史列表同口径）；上函数回单助手显式绑定行数（级联预检——级联只删显式绑定行），两处
// 数字在默认助手上本就不同且都正确，禁合并。querySql 直查（RdbPredicates 无聚合能力）
export async function queryAssistantConversationCounts(): Promise<Map<string, number>> {
  const result: relationalStore.ResultSet = await requireStore().querySql(
    'SELECT assistantId, COUNT(*) AS cnt FROM conversations GROUP BY assistantId');
  const counts: Map<string, number> = new Map();
  try {
    while (result.goToNextRow()) {
      counts.set(result.getString(result.getColumnIndex('assistantId')),
        result.getLong(result.getColumnIndex('cnt')));
    }
  } finally {
    result.close();
  }
  return counts;
}

// Node 会话 worker 级联释放（best-effort；与 ChatDb 同名帮助函数同款——两处各 6 行不抽公共
// 件：nodeexec 域不持 store 侧日志域，反向 import 会破坏 store → nodeexec 单向依赖）。
// 会话 id 即 Node sessionId；同步段先递增取消代次并撤回排队，异步 drop 失败只留痕不回滚。
function dropNodeWorkersQuiet(conversationIds: string[]): void {
  for (const conversationId of conversationIds) {
    dropNodeForConversation(conversationId, conversationId).catch((e: Object): void => {
      hilog.warn(DOMAIN, TAG, 'Node 会话 worker 级联删除失败（会话 %{public}s）：%{public}s',
        conversationId, (e as Error).message);
    });
  }
}

// 删除助手 = 硬级联无软删除（RikkaHub 同款拍板；默认助手守卫禁删兜底）：同事务级联
// message_attachments → messages → token_usage_events（统计页不残留已删会话用量，与
// deleteConversations 口径④）→ 图侧五表 → send_queue_items/state → conversations →
// assistants 行，任一失败 rollBack 不半删（P0-1；会话 id 集自 ResultSet 收集 = 纯数组坑6 族）。
// **级联铁律：任何新增「删 messages」路径必须在同函数同事务内删附件行**（全仓删 messages
// 落点 = 本函数 + ChatDb.deleteConversations）。附件文件本体删除在 commit 后 best-effort。
// 返回级联删除的会话数；删当前助手的 active 键重置 + 重拉广播在调用方编排（AssistantPage）
export async function deleteAssistantCascade(id: string): Promise<number> {
  // 默认助手守卫禁删（UI 本就不渲染删除项，此为兜底）
  if (id === ASSISTANT_DEFAULT_ID) {
    return -1;
  }
  const db: relationalStore.RdbStore = requireStore();
  const refPredicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('conversations');
  refPredicates.equalTo('assistantId', id);
  const refResult: relationalStore.ResultSet = await db.query(refPredicates, ['id']);
  const convIds: string[] = [];
  try {
    while (refResult.goToNextRow()) {
      convIds.push(refResult.getString(refResult.getColumnIndex('id')));
    }
  } finally {
    refResult.close();
  }
  // 头像删除前置（v45）：事务前查 avatar，本地图片型才在 commit 后删（事务中禁文件 I/O）；
  // 行将随本函数删除，此刻不查没有第二时机
  const avPredicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('assistants');
  avPredicates.equalTo('id', id);
  const avResult: relationalStore.ResultSet = await db.query(avPredicates, ['avatar']);
  let avatarSpec: string = '';
  try {
    if (avResult.rowCount > 0 && avResult.goToNextRow()) {
      avatarSpec = avResult.getString(avResult.getColumnIndex('avatar'));
    }
  } finally {
    avResult.close();
  }
  // 写串行链入链（级联删事务段入链；commit 后文件删除时序不变）
  return runWriteQueued('deleteAssistantCascade', async (): Promise<number> => {
    // 临时区级联收集（与 ChatDb.deleteConversations 对称面：已过排队、事务未开纯 fs 收集；
    // 收集逻辑在 WorkspaceDbTmp——本件不堆逻辑）
    const tmpConvIds: string[] = collectTmpForConversations(convIds);
    // HTTP 凭据条目 id 快照（须在串行链内取——链外读有排队窗口，他笔新建条目元数据会随整键
    // 删而其 Asset 明文不在快照集 = 无主明文）；此刻已过排队、事务未开，快照即终态；Asset 无
    // 前缀查询，元数据删后没有第二时机
    const httpCredIds: string[] = credIdsOf(id);
    db.beginTransaction();
    try {
      let attachPaths: string[] = [];
      if (convIds.length > 0) {
        // 附件行级联：先 SELECT 收集 localPath 再删行；文件 I/O 在 commit 后
        attachPaths = await deleteAttachmentsForConversations(db, convIds);
        const msgPredicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('messages');
        msgPredicates.in('conversationId', convIds);
        await db.delete(msgPredicates);
        // 用量账本级联：名下会话用量事件一并删（统计页只反映现存会话）
        const usagePredicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('token_usage_events');
        usagePredicates.in('conversationId', convIds);
        await db.delete(usagePredicates);
        // 图侧级联：图侧行随删防孤儿，与 deleteConversations 同款五表（facts→runs 依赖序）
        await db.executeSql('DELETE FROM attachment_refs WHERE conversationId IN (' +
          convIds.map((_id: string): string => '?').join(',') + ')', convIds);
        await db.executeSql('DELETE FROM summary_bindings WHERE conversationId IN (' +
          convIds.map((_id: string): string => '?').join(',') + ')', convIds);
        await db.executeSql('DELETE FROM tool_facts WHERE runId IN (SELECT id FROM ' +
          'generation_runs WHERE conversationId IN (' +
          convIds.map((_id: string): string => '?').join(',') + '))', convIds);
        await db.executeSql('DELETE FROM generation_runs WHERE conversationId IN (' +
          convIds.map((_id: string): string => '?').join(',') + ')', convIds);
        await db.executeSql('DELETE FROM branches WHERE conversationId IN (' +
          convIds.map((_id: string): string => '?').join(',') + ')', convIds);
        // 排队行级联（v57）：待发排队行随会话同删，与 deleteConversations 同笔对称
        await db.executeSql('DELETE FROM send_queue_items WHERE conversationId IN (' +
          convIds.map((_id: string): string => '?').join(',') + ')', convIds);
        // 排队运行态级联（v58）：同上对称
        await db.executeSql('DELETE FROM send_queue_state WHERE conversationId IN (' +
          convIds.map((_id: string): string => '?').join(',') + ')', convIds);
        const convPredicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('conversations');
        convPredicates.in('id', convIds);
        await db.delete(convPredicates);
      }
      // 记忆归属级联置空：该助手沉淀的记忆条目保留（跨会话资产），assistantId 归空去标注
      await clearMemoryAssistantRef(id);
      // 助手级记忆库级联删行（v35）：库跟着人走，与全局库置空保留口径刻意不同
      await deleteAssistantMemoriesOfAssistant(id);
      // 记忆优化历史快照级联删：同「库跟着人走」口径（不是跨会话资产）；不删 = 孤儿行堆积
      await deleteMemorySnapshotsOfAssistant(id);
      const delPredicates: relationalStore.RdbPredicates =
        new relationalStore.RdbPredicates('assistants');
      delPredicates.equalTo('id', id);
      await db.delete(delPredicates);
      db.commit();
      removeAttachmentFiles(attachPaths); // best-effort：失败留启动收敛自愈
      // 头像文件删除（best-effort；filesDir 未捕获时内部静默跳过，P0-1 有界不冒险）
      deleteAvatarFile(attachmentFilesDir(), avatarSpec);
      // 会话临时区级联删除（与 ChatDb 对称：commit 后 best-effort 不回滚；漏网孤儿目录
      // 管理页可见可清）
      deleteWorkspaceTmpConversationsQuiet(tmpConvIds);
      // Python 会话命名空间级联（同款对称缺口补齐：best-effort，余量由 native LRU 与进程
      // 重启兜底）
      dropPyNamespacesQuiet(tmpConvIds);
      // Node 会话 worker 级联（门 2：撤回排队 + 终止在跑 + drop；best-effort 不阻塞删除链）
      dropNodeWorkersQuiet(convIds);
      // HTTP 凭据级联清理（元数据与 Asset 删除同区 commit 后执行）。不能在事务内写偏好：
      // 偏好不参与 RDB 事务，事务内写遇 rollBack 无法回滚 = 半删态且 Asset 明文跨卸载残留
      //（IS_PERSISTENT）。残余风险 = commit 后本调用异常时偏好残留为惰性孤儿元数据（明文已
      // 删、UI 不可达、量受上界），好于无主明文永久残留。护栏：commit 已落，异常不得回流
      // rollBack（对已提交事务回滚 = 误报路径）
      try {
        removeCredOwnerMeta(id);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'HTTP 凭据元数据级联删除失败（助手 %{public}s）', id);
      }
      // Asset 级联：按链内快照逐条删（Asset 无前缀查询；不删 = 跨卸载残留明文孤儿）
      if (httpCredIds.length > 0) {
        try {
          await purgeOwnerAssets(id, httpCredIds);
        } catch (e) {
          hilog.warn(DOMAIN, TAG,
            'HTTP 凭据 Asset 级联删除失败（助手 %{public}s，条目 %{public}d 个）', id,
            httpCredIds.length);
        }
      }
      return convIds.length;
    } catch (e) {
      db.rollBack();
      throw e as Error;
    }
  });
}

// 会话助手引用（'' = 未显式绑定 = 默认助手名下口径，「跟随当前」语义已撤销，见
// ChatPromptState）。返回三态：null = 会话行不存在（懒创建新会话——注入链走面板覆盖 ??
// 当前助手 ?? 默认）；'' = 行在但未显式绑定；非 '' = 已绑定助手 id
export async function queryConversationAssistantId(conversationId: string): Promise<string | null> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', conversationId);
  const result: relationalStore.ResultSet = await requireStore().query(predicates, ['assistantId']);
  try {
    if (result.rowCount > 0 && result.goToNextRow()) {
      return result.getString(result.getColumnIndex('assistantId'));
    }
    return null;
  } finally {
    result.close();
  }
}

// 改会话归属：返回受影响行数——0 行只可能是「面板打开期间会话被另一路径删除」（并发窗口），
// 调用方据此 toast 不静默。单列 UPDATE 按拍板在写串行链之外（单语句写撞窗靠透传自愈）
export async function updateConversationAssistantId(conversationId: string,
  assistantId: string): Promise<number> {
  const bucket: relationalStore.ValuesBucket = { 'assistantId': assistantId };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', conversationId);
  return await requireStore().update(bucket, predicates);
}
