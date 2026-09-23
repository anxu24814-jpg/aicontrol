// 提示词库存储域（2026-08-30 提示词注入新建，照 ProviderKeyDb 域拆先例——ChatDb 加模板
// CRUD 必超 400 红线）：prompt_templates 表 CRUD + conversations.promptId 会话引用读写。
// 语义（领导拍板；2026-08-31 修订——系统提示词与模板「分开」，独立页管理、库页不显示、
// 内置默认可重置，细则见 docs/规范-数据存储获取刷新方案.md §3.5）：
// ①系统提示词 = isGlobal=1 唯一行（固定 id 'prompt-global'，名「系统提示词」，启动兜底
//   ensurePromptGlobal 幂等：无行插内置内容 / 存量空内容行填充内置——可更改可重置）；
//   注入语义（★2026-09-04 归属与注入解耦，细则见 ChatPromptState 头注释）= 会话提示词 >
//   助手提示词 > 系统提示词三级回退——系统提示词行是注入基座兜底；
// ②引用跟随——会话存模板 id 引用，模板修改后所有引用会话自动用新版；③会话 promptId
//   空 = 未启用注入（走归属助手/系统提示词回退链）；④删模板前查引用数（deleteTemplate 返回引用数——
//   调用方确认文案含「N 个会话引用，删除后回退助手提示词」，不静默）；系统提示词行不可
//   删（deleteTemplate 守卫——库页不再触达，作旧残留兜底）。
import { relationalStore } from '@kit.ArkData';
import { nextMessageId, sharedRdbStore } from './ChatDb';

// 全局默认行固定 id（启动兜底与查询共用；2026-08-31 起仅 SystemPromptPage/注入链消费）
export const PROMPT_GLOBAL_ID: string = 'prompt-global';
// 系统提示词内置默认（2026-08-31 领导给定原文；「恢复」键回此文本 + 注入配置默认
// system+head+0——可更改可重置）
// ★ 2026-09-01 更新：追加时间/日期变量描述（{{date}}/{{time}}/{{weekday}}/{{datetime}}
//   ——变量替换见 providers/PromptVariables.ets，发送前应用层字符串替换）；旧版全文保留在
//   SYSTEM_PROMPT_DEFAULT_LEGACY_V1 供迁移判定（ensurePromptGlobal：行内容 == 旧默认 =
//   用户从未改过的默认态 → 更新为新默认；用户改过的内容零覆盖）
export const SYSTEM_PROMPT_DEFAULT: string =
  '你是一个严谨、友好的助手。复杂先给结论再展开；公式用 LaTeX，代码可直接运行；' +
  '信息不足/不确定就明说，禁止编造，关键事实注明来源；篇幅以解决问题为限。' +
  '需要当前时间/日期时使用提示词变量：{{date}} 为当前日期（如 2026-09-01），' +
  '{{time}} 为当前时间（如 14:30），{{weekday}} 为星期（如 星期二），' +
  '{{datetime}} 为日期时间（如 2026-09-01 14:30）；示例：「现在是 {{time}}，' +
  '今天是 {{date}}（{{weekday}}）」。涉及时间请优先引用变量，不要凭空编造。';
// 旧版内置默认（2026-08-31 原文——仅迁移判定用：行内容等于它 = 用户从未改过 = 默认态）
export const SYSTEM_PROMPT_DEFAULT_LEGACY_V1: string =
  '你是一个严谨、友好的助手。复杂先给结论再展开；公式用 LaTeX，代码可直接运行；' +
  '信息不足/不确定就明说，禁止编造，关键事实注明来源；篇幅以解决问题为限。';
// 模板名称/内容长度上限（编辑页 maxLength 同值；有界红线：模板内容 = 注入上下文体积，
// 防无界增长——2000 字符已远超日常人设/指令）
export const TEMPLATE_NAME_MAX: number = 50;
export const TEMPLATE_CONTENT_MAX: number = 2000;

export interface PromptTemplateRow {
  id: string;
  name: string;
  content: string;
  isGlobal: boolean;
  createdAt: number;
  // 注入配置（v7 新增；默认值 = 现状注入行为 system+head+0，组合语义与协议适配见
  // RequestCompose.composeSendMessages 注释）：injectRole 'system' 系统身份 / 'user'
  // 用户身份（拼接进目标用户消息）/ 'assistant' AI 回复身份；injectPosition 'head'
  // 系统提示位 / 'depth' 在用户消息深度 N；injectDepth 0~4（仅 depth 生效，0 = 最新
  // 用户消息，1 = 倒数第 2 条用户消息，依此类推；不足钳位到最早）
  injectRole: string;
  injectPosition: string;
  injectDepth: number;
}

// 后置占位（未调 ensurePromptGlobal 时的查询兜底——空全局行 isGlobal=true；
// 2026-08-30 改名行名 = 「系统提示词」，与 DB 行名对齐）
const GLOBAL_EMPTY_ROW: PromptTemplateRow = {
  id: PROMPT_GLOBAL_ID, name: '系统提示词', content: '', isGlobal: true, createdAt: 0,
  injectRole: 'system', injectPosition: 'head', injectDepth: 0
};

function requireStore(): relationalStore.RdbStore {
  return sharedRdbStore();
}

// 全量模板（库页 = 用户模板清单——★ 2026-08-31 起过滤 isGlobal=0：系统提示词行不入库页，
// 与模板「分开」由独立页管理；其余创建先后序；用户手建小数据集自然有界）
export async function queryTemplates(): Promise<PromptTemplateRow[]> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('prompt_templates');
  predicates.equalTo('isGlobal', 0);
  predicates.orderByAsc('createdAt');
  const columns: string[] =
    ['id', 'name', 'content', 'isGlobal', 'createdAt', 'injectRole', 'injectPosition', 'injectDepth'];
  const result: relationalStore.ResultSet = await requireStore().query(predicates, columns);
  const rows: PromptTemplateRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        id: result.getString(result.getColumnIndex('id')),
        name: result.getString(result.getColumnIndex('name')),
        content: result.getString(result.getColumnIndex('content')),
        isGlobal: result.getLong(result.getColumnIndex('isGlobal')) === 1,
        createdAt: result.getLong(result.getColumnIndex('createdAt')),
        injectRole: result.getString(result.getColumnIndex('injectRole')),
        injectPosition: result.getString(result.getColumnIndex('injectPosition')),
        injectDepth: result.getLong(result.getColumnIndex('injectDepth'))
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// 系统提示词行（独立页回填 / 注入链 ChatSendCtrl.loadPromptState 读取；isGlobal=1 唯一；
// 2026-08-31 起谓词直查——不依赖 queryTemplates（后者已过滤全局行）；兜底失败/未初始化
// = 空内容占位——不炸 UI）
export async function queryGlobalTemplate(): Promise<PromptTemplateRow> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('prompt_templates');
  predicates.equalTo('isGlobal', 1);
  const result: relationalStore.ResultSet = await requireStore().query(predicates,
    ['id', 'name', 'content', 'isGlobal', 'createdAt', 'injectRole', 'injectPosition', 'injectDepth']);
  try {
    if (result.rowCount > 0 && result.goToNextRow()) {
      return {
        id: result.getString(result.getColumnIndex('id')),
        name: result.getString(result.getColumnIndex('name')),
        content: result.getString(result.getColumnIndex('content')),
        isGlobal: result.getLong(result.getColumnIndex('isGlobal')) === 1,
        createdAt: result.getLong(result.getColumnIndex('createdAt')),
        injectRole: result.getString(result.getColumnIndex('injectRole')),
        injectPosition: result.getString(result.getColumnIndex('injectPosition')),
        injectDepth: result.getLong(result.getColumnIndex('injectDepth'))
      };
    }
  } finally {
    result.close();
  }
  return GLOBAL_EMPTY_ROW;
}

// 按 id 查模板（会话引用解析用；查不到 = 模板已删/坏 id → null，调用方回退全局默认）
export async function queryTemplate(id: string): Promise<PromptTemplateRow | null> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('prompt_templates');
  predicates.equalTo('id', id);
  const result: relationalStore.ResultSet = await requireStore().query(predicates,
    ['id', 'name', 'content', 'isGlobal', 'createdAt', 'injectRole', 'injectPosition', 'injectDepth']);
  try {
    if (result.rowCount > 0 && result.goToNextRow()) {
      return {
        id: result.getString(result.getColumnIndex('id')),
        name: result.getString(result.getColumnIndex('name')),
        content: result.getString(result.getColumnIndex('content')),
        isGlobal: result.getLong(result.getColumnIndex('isGlobal')) === 1,
        createdAt: result.getLong(result.getColumnIndex('createdAt')),
        injectRole: result.getString(result.getColumnIndex('injectRole')),
        injectPosition: result.getString(result.getColumnIndex('injectPosition')),
        injectDepth: result.getLong(result.getColumnIndex('injectDepth'))
      };
    }
    return null;
  } finally {
    result.close();
  }
}

// 系统提示词行兜底（启动一次性，幂等——失败下次启动重试）：①已有 isGlobal=1 行——行名
// 不对齐「系统提示词」则修正（2026-08-30 改名）；内容为空 = 旧版/改名期空行 → 一次性填充
// 内置默认（2026-08-31 内置化；用户已改过非空 = 零覆盖不丢失；「恢复」键重置亦走
// updateTemplate）；★ 2026-09-01 默认值更新：行内容 == 旧版默认（SYSTEM_PROMPT_DEFAULT_
// LEGACY_V1——用户从未改过的默认态）→ 同步为新默认（默认值演进 = 存量默认行跟进，用户
// 自定义内容不覆盖）；②无行（新装）→ 插内置内容「系统提示词」行（不再空行）。
export async function ensurePromptGlobal(): Promise<void> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('prompt_templates');
  predicates.equalTo('isGlobal', 1);
  const result: relationalStore.ResultSet = await requireStore().query(predicates,
    ['id', 'name', 'content']);
  let rowId: string = '';
  let rowName: string = '';
  let rowContent: string = '';
  try {
    if (result.rowCount > 0 && result.goToNextRow()) {
      rowId = result.getString(result.getColumnIndex('id'));
      rowName = result.getString(result.getColumnIndex('name'));
      rowContent = result.getString(result.getColumnIndex('content'));
    }
  } finally {
    result.close();
  }
  if (rowId !== '') {
    const bucket: relationalStore.ValuesBucket = {};
    let touch: boolean = false;
    if (rowName !== '系统提示词') {
      bucket['name'] = '系统提示词';
      touch = true;
    }
    if (rowContent === '' || rowContent === SYSTEM_PROMPT_DEFAULT_LEGACY_V1) {
      bucket['content'] = SYSTEM_PROMPT_DEFAULT;
      touch = true;
    }
    if (touch) {
      const byId: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('prompt_templates');
      byId.equalTo('id', rowId);
      await requireStore().update(bucket, byId);
    }
    return;
  }
  const now: number = Date.now();
  const bucket: relationalStore.ValuesBucket = {
    'id': PROMPT_GLOBAL_ID, 'name': '系统提示词', 'content': SYSTEM_PROMPT_DEFAULT,
    'isGlobal': 1, 'createdAt': now
  };
  await requireStore().insert('prompt_templates', bucket);
}

// 新增模板（名称非空由调用方校验；全局行禁止经此新增——全局只有一条，编辑走 update）
export async function insertTemplate(name: string, content: string,
  injectRole: string, injectPosition: string, injectDepth: number): Promise<PromptTemplateRow> {
  const row: PromptTemplateRow = {
    id: nextMessageId('prompt'),
    name: name,
    content: content,
    isGlobal: false,
    createdAt: Date.now(),
    injectRole: injectRole,
    injectPosition: injectPosition,
    injectDepth: injectDepth
  };
  const bucket: relationalStore.ValuesBucket = {
    'id': row.id, 'name': row.name, 'content': row.content, 'isGlobal': 0, 'createdAt': row.createdAt,
    'injectRole': row.injectRole, 'injectPosition': row.injectPosition, 'injectDepth': row.injectDepth
  };
  await requireStore().insert('prompt_templates', bucket);
  return row;
}

// 更新模板（名称/内容/注入配置；引用跟随语义——所有引用会话下次发送自动用新版）。
// ★ 2026-08-31 存储链路复查：update 返回行数校验——目标行不存在（系统提示词行未及启动
// 兜底/被误删）时原生 update 静默 0 行，调用方 toast「已保存」= 假成功（P0-1 诚实反馈）；
// 0 行 throw → 调用方既有 catch 通道呈报「保存失败」（零调用方改动）
export async function updateTemplate(id: string, name: string, content: string,
  injectRole: string, injectPosition: string, injectDepth: number): Promise<void> {
  const bucket: relationalStore.ValuesBucket = {
    'name': name, 'content': content,
    'injectRole': injectRole, 'injectPosition': injectPosition, 'injectDepth': injectDepth
  };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('prompt_templates');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标提示词行不存在（已被删除或未初始化），保存未生效');
  }
}

// 删除模板（全局默认行守卫不可删——调用方也不应触发；返回引用该模板的会话数——
// 确认文案提示「N 个会话引用，删除后回退全局默认」；引用不级联清（注入解析查不到 =
// 回退全局默认，弱容错不阻断）
export async function deleteTemplate(id: string): Promise<number> {
  if (id === PROMPT_GLOBAL_ID) {
    return -1;
  }
  const refPredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  refPredicates.equalTo('promptId', id);
  const refResult: relationalStore.ResultSet = await requireStore().query(refPredicates, ['id']);
  let refCount: number = 0;
  try {
    while (refResult.goToNextRow()) {
      refCount++;
    }
  } finally {
    refResult.close();
  }
  const delPredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('prompt_templates');
  delPredicates.equalTo('id', id);
  await requireStore().delete(delPredicates);
  return refCount;
}

// 会话提示词引用（conversations.promptId；空串 = 未选 → 注入回退全局默认）
export async function queryConversationPromptId(conversationId: string): Promise<string> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', conversationId);
  const result: relationalStore.ResultSet = await requireStore().query(predicates, ['promptId']);
  try {
    if (result.rowCount > 0 && result.goToNextRow()) {
      return result.getString(result.getColumnIndex('promptId'));
    }
    return '';
  } finally {
    result.close();
  }
}

export async function updateConversationPromptId(conversationId: string, promptId: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'promptId': promptId };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', conversationId);
  await requireStore().update(bucket, predicates);
}
