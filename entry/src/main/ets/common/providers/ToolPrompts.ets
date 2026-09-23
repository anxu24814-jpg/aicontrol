// 控制台助手提示词读写工具域（2026-09-06 扩面新增；宪法「新增功能域一律先拆」——
// ToolTypes 已在软引导区且本域与既有工具集是独立职责缝，域级最小拆分独立成文件，
// ToolTypes 只做注册）。两个内置工具，均 defaultEnabled=false + console-exclusive
// 反向拦截（AssistantToolsPage，同 set_app_preference 族）：
// · edit_system_prompt——系统提示词（prompt_templates.isGlobal=1 唯一行）查看/修改/恢复
//   内置默认。复用 PromptTemplateDb 既有 API（queryGlobalTemplate/updateTemplate，0 行
//   throw 防 P0-1 假成功），写入固定注入三列 system/head/0（SystemPromptPage 保存同口径
//   ——2026-08-31 领导拍板取消系统提示词注入配置）；长度上限 TEMPLATE_CONTENT_MAX 与
//   编辑页 maxLength 同值（注入上下文有界红线）。
// · manage_prompts——会话提示词库（prompt_templates 用户模板）列出/新建/修改。
//   ★ 删除不开放：工具直删跳过 UI 确认链（「N 个会话引用」确认文案）且不可逆——desc 与
//   错误路径恒指引 设置 → 会话提示词 手动删除；修改按 name 精确匹配定位（0 匹配回显名单、
//   多匹配拒歧义——库页无重名检查），只改 content，注入配置保留原值不覆盖。
// 生效时机（回执 hint 语义基线）：注入链 ChatSendCtrl.loadPromptState 每次发送现读——
// 系统提示词与模板修改（引用跟随）均下次发送即生效，零缓存零广播。
// 边界：DB 读写在本文件执行器内；校验纯函数自包含可断言（searchHelpTopics 同款姿势，
// 断言脚本剥 TS 求值直跑）；协议方言/工具循环编排不属本域（ToolTypes/ChatSendCtrl）。
import { INJECT_POSITION_HEAD, INJECT_ROLE_SYSTEM } from './RequestInject';
import { ToolExecutor } from './ToolContracts';
import { insertTemplate, PROMPT_GLOBAL_ID, PromptTemplateRow, queryGlobalTemplate,
  queryTemplates, SYSTEM_PROMPT_DEFAULT, TEMPLATE_CONTENT_MAX, TEMPLATE_NAME_MAX,
  updateTemplate } from '../store/PromptTemplateDb';

// 工具名常量 TOOL_EDIT_SYSTEM_PROMPT / TOOL_MANAGE_PROMPTS 归口 ToolTypes.ets
//（与注册/反向拦截/seed 同源引用，本域不重复定义防漂移）。

// ── edit_system_prompt ──

export const EDIT_SYSTEM_PROMPT_SCHEMA: string =
  '{"type":"object","properties":{"action":{"type":"string",' +
  '"description":"get 查看当前内容，set 全文替换，reset 恢复内置默认","enum":["get","set","reset"]},' +
  '"content":{"type":"string","description":"action 为 set 时必填，系统提示词全文，' +
  '将整体替换现有内容"}},"required":["action"]}';

// desc 动态拼上限数值（常量单源，防两处漂移）
export function buildEditSystemPromptDesc(): string {
  return '查看、修改或恢复本应用的系统提示词。它作为所有对话的注入基座，' +
    '只在会话未启用会话提示词且助手未设置提示词时注入。' +
    'action 取 get 返回当前全文，set 用 content 全文替换（上限 ' + TEMPLATE_CONTENT_MAX +
    ' 字），reset 恢复为内置默认。仅在用户明确要求查看或修改系统提示词时调用；' +
    'set 是整体替换，用户只想局部调整时先 get 再基于原文生成新全文。' +
    '保存后下次发送生效。';
}

// 校验结果（纯函数可断言）：ok = true 时 action/content 有效
export interface EditSystemPromptValidation {
  ok: boolean;
  action: string;
  content: string;
  error: string;
}

function rejectEditPrompt(error: string): EditSystemPromptValidation {
  return { ok: false, action: '', content: '', error: error };
}

// 参数校验纯函数：坏 JSON / 缺 action / 非法 action / set 缺 content / content 超限全拒
export function validateEditSystemPromptArgs(argsJson: string): EditSystemPromptValidation {
  let action: string = '';
  let content: string = '';
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    const rawAction: Object | undefined = parsed['action'];
    const rawContent: Object | undefined = parsed['content'];
    if (typeof rawAction === 'string') {
      action = rawAction.trim();
    }
    if (typeof rawContent === 'string') {
      content = rawContent.trim();
    }
  } catch (e) {
    return rejectEditPrompt('参数解析失败，需要 action 参数');
  }
  if (action !== 'get' && action !== 'set' && action !== 'reset') {
    return rejectEditPrompt('action 必须是 get、set 或 reset');
  }
  if (action === 'set') {
    if (content === '') {
      return rejectEditPrompt('action 为 set 时需要 content 参数，值为系统提示词全文');
    }
    if (content.length > TEMPLATE_CONTENT_MAX) {
      return rejectEditPrompt('content 超过 ' + TEMPLATE_CONTENT_MAX + ' 字上限，当前 ' +
        content.length + ' 字，请精简后再保存');
    }
  }
  return { ok: true, action: action, content: content, error: '' };
}

// 系统提示词编辑执行器：校验 → 按 action 分路（get 只读 / set 全文替换 / reset 写内置
// 默认）；DB 抛错上抛由 executeToolCall 统一包装 error JSON（不炸链路不静默）。
// 导出 = ToolTypes 注册引用 + 断言脚本剥桩求值实态（两消费方同源）
export class EditSystemPromptExecutor implements ToolExecutor {
  execute(argsJson: string): Promise<string> {
    const v: EditSystemPromptValidation = validateEditSystemPromptArgs(argsJson);
    if (!v.ok) {
      return Promise.resolve(JSON.stringify({ error: v.error }));
    }
    if (v.action === 'get') {
      return queryGlobalTemplate().then((row: PromptTemplateRow): string =>
        JSON.stringify({ ok: true, action: 'get', content: row.content,
          chars: row.content.length }));
    }
    const target: string = v.action === 'reset' ? SYSTEM_PROMPT_DEFAULT : v.content;
    return updateTemplate(PROMPT_GLOBAL_ID, '系统提示词', target,
      INJECT_ROLE_SYSTEM, INJECT_POSITION_HEAD, 0)
      .then((): string => JSON.stringify({ ok: true, action: v.action,
        chars: target.length,
        hint: v.action === 'reset' ? '已恢复为内置默认，下次发送生效' : '已保存，下次发送生效' }));
  }
}

// ── manage_prompts ──

export const MANAGE_PROMPTS_SCHEMA: string =
  '{"type":"object","properties":{"action":{"type":"string",' +
  '"description":"list 列出全部模板，create 新建，update 修改指定模板的内容",' +
  '"enum":["list","create","update"]},"name":{"type":"string",' +
  '"description":"create 为新模板名；update 为要修改的模板名，须与现有名逐字一致"},' +
  '"content":{"type":"string","description":"create 与 update 必填，模板全文，' +
  '将整体替换现有内容"}},"required":["action"]}';

// desc：删除不开放的原因与手动路径在此明示（模型被要求删除时如实转述，不硬删）
export function buildManagePromptsDesc(): string {
  return '管理本应用的会话提示词模板库。action 取 list 列出全部模板（含名称与全文），' +
    'create 用 name 与 content 新建模板，update 用 name 精确匹配定位后以 content 整体替换' +
    '（name 与 content 上限分别为 ' + TEMPLATE_NAME_MAX + ' 与 ' + TEMPLATE_CONTENT_MAX +
    ' 字）。不支持删除——用户要删除模板时，指引用户前往 设置 → 会话提示词 手动删除，' +
    '不要尝试用其他方式删除。仅在用户明确要求时调用。模板修改后，引用它的会话下次发送' +
    '自动使用新版。';
}

// 校验结果（纯函数可断言）
export interface ManagePromptsValidation {
  ok: boolean;
  action: string;
  name: string;
  content: string;
  error: string;
}

function rejectManagePrompts(error: string): ManagePromptsValidation {
  return { ok: false, action: '', name: '', content: '', error: error };
}

// 参数校验纯函数：坏 JSON / 非法 action / create 与 update 缺 name 或 content / 超限全拒
export function validateManagePromptsArgs(argsJson: string): ManagePromptsValidation {
  let action: string = '';
  let name: string = '';
  let content: string = '';
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    const rawAction: Object | undefined = parsed['action'];
    const rawName: Object | undefined = parsed['name'];
    const rawContent: Object | undefined = parsed['content'];
    if (typeof rawAction === 'string') {
      action = rawAction.trim();
    }
    if (typeof rawName === 'string') {
      name = rawName.trim();
    }
    if (typeof rawContent === 'string') {
      content = rawContent.trim();
    }
  } catch (e) {
    return rejectManagePrompts('参数解析失败，需要 action 参数');
  }
  if (action !== 'list' && action !== 'create' && action !== 'update') {
    return rejectManagePrompts('action 必须是 list、create 或 update。' +
      '删除不受支持，请指引用户前往 设置 → 会话提示词 手动删除');
  }
  if (action === 'create' || action === 'update') {
    if (name === '') {
      return rejectManagePrompts('action 为 ' + action + ' 时需要 name 参数');
    }
    if (name.length > TEMPLATE_NAME_MAX) {
      return rejectManagePrompts('name 超过 ' + TEMPLATE_NAME_MAX + ' 字上限');
    }
    if (content === '') {
      return rejectManagePrompts('action 为 ' + action + ' 时需要 content 参数，值为模板全文');
    }
    if (content.length > TEMPLATE_CONTENT_MAX) {
      return rejectManagePrompts('content 超过 ' + TEMPLATE_CONTENT_MAX + ' 字上限，当前 ' +
        content.length + ' 字，请精简后再保存');
    }
  }
  return { ok: true, action: action, name: name, content: content, error: '' };
}

// 库清单条目（list 回执载荷）
interface ManagePromptItem {
  name: string;
  chars: number;
  content: string;
}

interface ManagePromptsPayload {
  ok: boolean;
  action: string;
  count: number;
  prompts: ManagePromptItem[];
}

// 会话提示词库管理执行器：list 全量（工具结果 8192 截断兜底——模板内容为注入上下文级
// 长度，条目多时可能触界，clipToolResult 结构化截断不适用本载荷，硬截尾标可感知）；
// create 固定默认注入三列（与编辑页新建默认同口径，用户可在编辑页调整）；update 按 name
// 精确匹配唯一行、保留原注入配置只换 content——0 匹配回显名单、多匹配拒歧义（库页无
// 重名检查，歧义删除面封死）。导出理由同 EditSystemPromptExecutor
export class ManagePromptsExecutor implements ToolExecutor {
  execute(argsJson: string): Promise<string> {
    const v: ManagePromptsValidation = validateManagePromptsArgs(argsJson);
    if (!v.ok) {
      return Promise.resolve(JSON.stringify({ error: v.error }));
    }
    if (v.action === 'list') {
      return queryTemplates().then((rows: PromptTemplateRow[]): string => {
        const items: ManagePromptItem[] = rows.map((row: PromptTemplateRow): ManagePromptItem =>
          ({ name: row.name, chars: row.content.length, content: row.content }));
        const payload: ManagePromptsPayload = { ok: true, action: 'list',
          count: items.length, prompts: items };
        return JSON.stringify(payload);
      });
    }
    if (v.action === 'create') {
      return insertTemplate(v.name, v.content, INJECT_ROLE_SYSTEM, INJECT_POSITION_HEAD, 0)
        .then((_row: PromptTemplateRow): string => JSON.stringify({ ok: true,
          action: 'create', name: v.name,
          hint: '已新建。注入配置为默认，可在模板编辑页调整。会话内通过提示词注入面板选择启用。' }));
    }
    // update：name 精确匹配定位
    return queryTemplates().then((rows: PromptTemplateRow[]): Promise<string> => {
      const hits: PromptTemplateRow[] = rows.filter((row: PromptTemplateRow): boolean =>
        row.name === v.name);
      if (hits.length === 0) {
        const names: string = rows.map((row: PromptTemplateRow): string => row.name).join('、');
        return Promise.resolve(JSON.stringify({ error: '没有名为「' + v.name +
          '」的模板。现有模板：' + (names === '' ? '（库为空）' : names) }));
      }
      if (hits.length > 1) {
        return Promise.resolve(JSON.stringify({ error: '存在 ' + hits.length +
          ' 个同名模板，无法确定要修改哪一个，请指引用户前往 设置 → 会话提示词 手动修改' }));
      }
      const row: PromptTemplateRow = hits[0];
      return updateTemplate(row.id, row.name, v.content, row.injectRole,
        row.injectPosition, row.injectDepth)
        .then((): string => JSON.stringify({ ok: true, action: 'update', name: row.name,
          hint: '已保存。引用该模板的会话下次发送自动使用新版' }));
    });
  }
}
