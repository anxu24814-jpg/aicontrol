// AI 配置工具域 · 模型管理：manage_models 六动作——add / update / reset_caps / enable /
// disable / remove，薄封装 ProviderDb 模型面既有引擎（insertModel / updateModel /
// setModelEnabled / deleteModel）。
// ★ 定位纪律：providerId + modelId 双键定位行（rowId 是库行身份不外显）；modelId 不可改
//   （行身份，与 UI 编辑页同约束）；caps 校验走 MODEL_CAP_CODES 单源；生效能力回执一律
//   capLabels(effectiveCaps(row))「生效」口径（派生值也算）。
// ★ 确认链：六动作全写/删——remove 不可逆档恒问人，其余写档；预检 fail-closed 同
//   ToolProviderAdmin（判定写/删后异常返保守人工卡，坏形态返 null）。
// ★ 坑50：契约自 ToolContracts 叶子引、工具名自 ToolIds 引；本件只被聚合根 ToolTypes 引，
//   不反向引任何聚合根，无环。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { clipReceiptDiffValue, ConfirmPrompt, CONFIRM_LEVEL_IRREVERSIBLE, CONFIRM_LEVEL_WRITE,
  CONFIRM_ROUTE_HUMAN, ToolExecutor, toolArgsParseErrorText, toolErrorText } from './ToolContracts';
import { routeConfirmPrompt } from './ConfirmRouting';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { dataApproveMode } from '../AppPreferences';
import { effectiveCapsOf } from './AiTypes';
import { capLabels, deleteModel, effectiveCaps, insertModel, ModelRow, MODEL_CAP_CODES,
  MODEL_CAP_LABELS, queryModels, queryProviders, ProviderRow, setModelEnabled,
  updateModel } from '../store/ProviderDb';

const DOMAIN: number = 0xD5A7;
const TAG: string = 'ToolModelAdmin';

function readStrArg(parsed: Record<string, Object>, key: string): string {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'string' ? raw.trim() : '';
}

function readIntArg(parsed: Record<string, Object>, key: string, fallback: number): number {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'number' && Number.isInteger(raw) ? raw : fallback;
}

// ── 参数校验纯函数（自包含可直跑）──

export interface ManageModelsValidation {
  ok: boolean;
  error: string;
  action: string;
  providerId: string;
  modelId: string;
  name: string;
  caps: string; // '' = 未传（add 未传 = 自动派生；update 未传 = 不改）
  kind: string; // '' = 未传（add 缺省 chat）
  contextWindow: number; // -1 = 未传（add 缺省 0；update 未传不改）
}

function rejectModelsArgs(error: string): ManageModelsValidation {
  return { ok: false, error: error, action: '', providerId: '', modelId: '', name: '',
    caps: '', kind: '', contextWindow: -1 };
}

const MANAGE_MODELS_ACTIONS: string[] = ['add', 'update', 'reset_caps', 'enable', 'disable',
  'remove'];
const MODEL_KIND_VALUES: string[] = ['chat', 'embedding'];

export function validateManageModelsArgs(argsJson: string): ManageModelsValidation {
  let parsed: Record<string, Object>;
  try {
    parsed = JSON.parse(argsJson) as Record<string, Object>;
  } catch (e) {
    return rejectModelsArgs(toolArgsParseErrorText(argsJson));
  }
  const action: string = readStrArg(parsed, 'action');
  if (!MANAGE_MODELS_ACTIONS.includes(action)) {
    return rejectModelsArgs('action 必须是 ' + MANAGE_MODELS_ACTIONS.join('、') + ' 之一。');
  }
  const v: ManageModelsValidation = {
    ok: true, error: '', action: action,
    providerId: readStrArg(parsed, 'providerId'),
    modelId: readStrArg(parsed, 'modelId'),
    name: readStrArg(parsed, 'name'),
    caps: readStrArg(parsed, 'caps'),
    kind: readStrArg(parsed, 'kind'),
    contextWindow: readIntArg(parsed, 'contextWindow', -1)
  };
  if (v.providerId === '') {
    return rejectModelsArgs('需要 providerId，请先调用 get_provider_config 取得。');
  }
  if (v.action === 'add' && v.modelId === '') {
    return rejectModelsArgs('add 需要 modelId（模型标识，逐字取自模型清单或用户提供的名称）。');
  }
  if (v.action !== 'add' && v.modelId === '') {
    return rejectModelsArgs(v.action + ' 需要 modelId 定位目标模型。');
  }
  if (v.kind !== '' && !MODEL_KIND_VALUES.includes(v.kind)) {
    return rejectModelsArgs('kind 只能是 chat 或 embedding。');
  }
  if (v.caps !== '') {
    const codes: string[] = v.caps.split(',').map((code: string): string => code.trim())
      .filter((code: string): boolean => code !== '');
    for (const code of codes) {
      if (!MODEL_CAP_CODES.includes(code)) {
        return rejectModelsArgs('caps 含未知能力码「' + code + '」。合法码：' +
          MODEL_CAP_CODES.join('、') + '，多个用逗号分隔，不传则自动识别。');
      }
    }
    v.caps = codes.join(',');
  }
  if (v.contextWindow < -1) {
    return rejectModelsArgs('contextWindow 不能是负数。');
  }
  return v;
}

// ── schema 与 desc ──

export const MANAGE_MODELS_SCHEMA: string = '{"type":"object","properties":{' +
  '"action":{"type":"string","enum":["add","update","reset_caps","enable","disable","remove"],' +
  '"description":"add=添加模型，update=修改模型，reset_caps=恢复能力自动识别，' +
  'enable/disable=启停模型，remove=删除模型"},' +
  '"providerId":{"type":"string","description":"服务商 id，逐字取自 get_provider_config 概览"},' +
  '"modelId":{"type":"string","description":"模型标识。add 必填；其余动作用它定位，不可改"},' +
  '"name":{"type":"string","description":"add 与 update 可选显示名，缺省显示 modelId"},' +
  '"caps":{"type":"string","description":"能力码逗号串，可取 tool、reason、web、vision、image。' +
  'add 与 update 可选，不传则自动识别"},' +
  '"kind":{"type":"string","enum":["chat","embedding"],"description":"add 可选类型，缺省 chat"},' +
  '"contextWindow":{"type":"integer","description":"上下文窗口 token 数。add 与 update 可选，' +
  '不传则跟随内置参考值"}},' +
  '"required":["action","providerId"]}';

export function buildManageModelsDesc(): string {
  return '代替用户管理服务商的模型清单。用户要求添加、修改、启停或删除模型时调用。' +
    'action 取 add 添加（modelId 必填，可带名称、能力、类型与上下文窗口；多个模型逐个调用即批量），' +
    'update 修改（按 modelId 定位，只传要改的字段），reset_caps 把能力恢复自动识别，' +
    'enable 与 disable 启停，remove 删除。需要先从 get_provider_config 取得 providerId。' +
    '用户给出模型清单让你挑选时，按用户点名的添加，不要自行增减。添加完成后可再用连接测试验证。' +
    '模型标识不可修改，改标识请删除后重新添加。';
}

// ── 确认链预检 ──

export async function manageModelsNeedsConfirm(argsJson: string,
  _ctx: ToolExecutionContext): Promise<ConfirmPrompt | null> {
  const v: ManageModelsValidation = validateManageModelsArgs(argsJson);
  if (!v.ok) {
    return null; // 坏形态阶段：执行器必有错误回执拦下
  }
  const level: string = v.action === 'remove' ? CONFIRM_LEVEL_IRREVERSIBLE : CONFIRM_LEVEL_WRITE;
  try {
    let text: string = '';
    if (v.action === 'add') {
      text = '为服务商「' + v.providerId + '」添加模型「' + v.modelId + '」';
    } else if (v.action === 'update') {
      text = '修改服务商「' + v.providerId + '」的模型「' + v.modelId + '」';
    } else if (v.action === 'reset_caps') {
      text = '把模型「' + v.modelId + '」的能力恢复自动识别';
    } else if (v.action === 'enable' || v.action === 'disable') {
      // 停用会清掉引用该模型的助手绑定、会话覆盖与功能模型槽——确认卡先讲明可见后果，
      // 执行后回执再给解除处数
      text = v.action === 'enable' ?
        '启用服务商「' + v.providerId + '」的模型「' + v.modelId + '」' :
        '停用服务商「' + v.providerId + '」的模型「' + v.modelId + '」，同时解除引用它的模型选择';
    } else {
      text = '删除服务商「' + v.providerId + '」的模型「' + v.modelId + '」';
    }
    return routeConfirmPrompt({ text: text, level: level }, dataApproveMode());
  } catch (e) {
    return { text: '即将执行模型配置修改（' + v.action + '）。预检失败，为安全起见请人工确认',
      level: level, route: CONFIRM_ROUTE_HUMAN };
  }
}

// ── 执行器 ──

// update 成功回执（oldValue/newValue 可选——仅实际改动字段拼行时附带，供工具卡红绿
// diff；无可显改动时两键缺席，键序照旧）
interface ManageModelsUpdateReceipt {
  ok: boolean;
  providerId: string;
  modelId: string;
  caps: string[];
  oldValue?: string;
  newValue?: string;
}

export class ManageModelsExecutor implements ToolExecutor {
  async execute(argsJson: string, _ctx: ToolExecutionContext): Promise<string> {
    const v: ManageModelsValidation = validateManageModelsArgs(argsJson);
    if (!v.ok) {
      return JSON.stringify({ error: v.error });
    }
    try {
      const providers: ProviderRow[] = await queryProviders();
      const provider: ProviderRow | undefined =
        providers.find((row: ProviderRow): boolean => row.id === v.providerId);
      if (provider === undefined) {
        return JSON.stringify({ error: '未找到该服务商，请先调用 get_provider_config 查询。' });
      }
      const rows: ModelRow[] = await queryModels(provider.id, '');
      const hit: ModelRow | undefined =
        rows.find((row: ModelRow): boolean => row.modelId === v.modelId);
      switch (v.action) {
        case 'add':
          return await this.add(provider, rows, v);
        case 'update':
          return await this.update(provider, hit, v);
        case 'reset_caps':
          return await this.resetCaps(provider, hit, v);
        case 'enable':
        case 'disable':
          return await this.toggle(provider, hit, v);
        default:
          return await this.remove(provider, hit, v);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'manage_models 失败：%{public}s', toolErrorText(e));
      return JSON.stringify({ error: '模型管理操作失败：' + toolErrorText(e) });
    }
  }

  private modelNotFound(modelId: string): string {
    return JSON.stringify({ error: '未找到模型「' + modelId + '」。请用 get_provider_config ' +
      '传该服务商名查模型清单核对。' });
  }

  // add：同服务商 modelId 查重 → 落库（caps 未传 = 空串 = 自动派生，insertModel 自动判
  // caps_user_modified）→ 回执带生效能力标签（派生值也算）
  private async add(provider: ProviderRow, rows: ModelRow[],
    v: ManageModelsValidation): Promise<string> {
    const dup: ModelRow | undefined =
      rows.find((row: ModelRow): boolean => row.modelId === v.modelId);
    if (dup !== undefined) {
      return JSON.stringify({ error: '模型「' + v.modelId + '」已存在，可用 update 修改。' });
    }
    const kind: string = v.kind !== '' ? v.kind : 'chat';
    const contextWindow: number = v.contextWindow >= 0 ? v.contextWindow : 0;
    const row: ModelRow = await insertModel(provider.id, v.modelId, v.name, kind, v.caps, '',
      contextWindow);
    return JSON.stringify({ ok: true, providerId: provider.id, modelId: row.modelId,
      caps: capLabels(effectiveCaps(row)) });
  }

  // update：读-改-写整写六列——未传的 name/kind/priceConfig/contextWindow 一律传现值
  // 原样回写（漏传会清空用户价格配置，P0-1 级；priceConfig 与 kind 不开放修改）。
  // 回执 diff 三行（名称/上下文窗口/能力）见 ManageModelsUpdateReceipt 注释
  private async update(provider: ProviderRow, hit: ModelRow | undefined,
    v: ManageModelsValidation): Promise<string> {
    if (hit === undefined) {
      return this.modelNotFound(v.modelId);
    }
    if (v.name === '' && v.caps === '' && v.contextWindow === -1) {
      return JSON.stringify({ error: '没有要修改的字段。可改 name、caps、contextWindow，' +
        '至少传一项。' });
    }
    const name: string = v.name !== '' ? v.name : hit.name;
    const contextWindow: number = v.contextWindow >= 0 ? v.contextWindow : hit.contextWindow;
    const caps: string = v.caps !== '' ? v.caps : hit.caps;
    // caps 传入 → 手改固化（UI 同口径）；未传 → 现值原样（含现固化态）
    const capsUserModified: boolean = v.caps !== '' ? true : hit.capsUserModified;
    await updateModel(hit.id, name, hit.kind, caps, capsUserModified, hit.priceConfig,
      contextWindow);
    // 回执回生效口径标签：传入 = 该码表标签；未传 = 现行生效（派生或固化）
    const capsOut: string[] = v.caps !== ''
      ? v.caps.split(',').filter((code: string): boolean => code !== '')
        .map((code: string): string => capsLabelOf(code))
      : capLabels(effectiveCaps(hit));
    const oldLines: string[] = [];
    const newLines: string[] = [];
    const pushPair = (label: string, before: string, after: string): void => {
      if (before !== after) {
        oldLines.push(label + ' ' + before);
        newLines.push(label + ' ' + after);
      }
    };
    // 名称行两侧均走显示名口径（name 空显示 modelId，与界面一致）——未传 name 时两侧
    // 同显示名自然相等不产行，防「空名模型改他字段」被误报成名称变更
    pushPair('名称', hit.name !== '' ? hit.name : hit.modelId,
      name !== '' ? name : hit.modelId);
    pushPair('上下文窗口', String(hit.contextWindow), String(contextWindow));
    pushPair('能力', capLabels(effectiveCaps(hit)).join('、'), capsOut.join('、'));
    const receipt: ManageModelsUpdateReceipt = { ok: true, providerId: provider.id,
      modelId: hit.modelId, caps: capsOut };
    if (oldLines.length > 0) {
      receipt.oldValue = clipReceiptDiffValue(oldLines.join('\n'));
      receipt.newValue = clipReceiptDiffValue(newLines.join('\n'));
    }
    return JSON.stringify(receipt);
  }

  // reset_caps：照 UI ModelEditPage 能力卡「重置」链——caps 落空串 + 标志位落 false
  //（此后读侧走 effectiveCaps 按模型名派生）
  private async resetCaps(provider: ProviderRow, hit: ModelRow | undefined,
    v: ManageModelsValidation): Promise<string> {
    if (hit === undefined) {
      return this.modelNotFound(v.modelId);
    }
    await updateModel(hit.id, hit.name, hit.kind, '', false, hit.priceConfig, hit.contextWindow);
    return JSON.stringify({ ok: true, providerId: provider.id, modelId: hit.modelId,
      caps: capLabels(effectiveCapsOf(false, '', hit.modelId)) });
  }

  private async toggle(provider: ProviderRow, hit: ModelRow | undefined,
    v: ManageModelsValidation): Promise<string> {
    if (hit === undefined) {
      return this.modelNotFound(v.modelId);
    }
    // 停用会解除恰好引用该模型的助手绑定/会话覆盖/功能槽——有解除时回执补字段；启用恒 0
    const cleared: number = await setModelEnabled(hit.id, v.action === 'enable');
    if (cleared > 0) {
      return JSON.stringify({ ok: true, providerId: provider.id, modelId: hit.modelId,
        enabled: v.action === 'enable', clearedBindings: cleared });
    }
    return JSON.stringify({ ok: true, providerId: provider.id, modelId: hit.modelId,
      enabled: v.action === 'enable' });
  }

  // remove：deleteModel 既有级联（清助手绑定 + 会话覆盖）随之生效
  private async remove(provider: ProviderRow, hit: ModelRow | undefined,
    v: ManageModelsValidation): Promise<string> {
    if (hit === undefined) {
      return this.modelNotFound(v.modelId);
    }
    await deleteModel(hit.id);
    return JSON.stringify({ ok: true, providerId: provider.id, removed: hit.modelId });
  }
}

// 能力码 → 中文标签（回执用；码表与标签表均 ProviderDb 单源，禁自持副本）
function capsLabelOf(code: string): string {
  const idx: number = MODEL_CAP_CODES.indexOf(code);
  return idx >= 0 ? MODEL_CAP_LABELS[idx] : code;
}
