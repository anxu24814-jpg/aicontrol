// AI 配置工具域 · 服务商管理：manage_providers 十一动作（create / update / enable / disable /
// delete / add_key / rename_key / toggle_key / delete_key / set_headers / assign_key），全部
// 薄封装既有引擎（ProviderDb / ProviderKeyDb / ProviderCatalog），零重写。
// ★ 密钥明文硬边界：本域**不向模型暴露任何密钥明文**——args 与回执零明文（回执只带
//   keyHintOf 尾号掩码）。明文触碰仅两处既定面：delete 路径的 removePoolKeys（只删不读）与
//   assign_key 转运路径（读用户暂存槽 + 池内查重 + 写 Asset——明文 = 用户在安全输入面板
//   「暂存」的输入，模型全程不可见不参与）。密钥条目由 add_key / create 建「明文缺失」占位
//   行，或由 assign_key 从暂存槽转运填充；设置页重填链照旧。
// ★ 确认链：写动作 CONFIRM_LEVEL_WRITE / 删动作 CONFIRM_LEVEL_IRREVERSIBLE，归一走
//   routeConfirmPrompt(prompt, dataApproveMode())；fail-closed 分阶段——已判定写/删之后的任何
//   异常一律返保守人工卡（恒 CONFIRM_ROUTE_HUMAN）不返 null，坏形态阶段（解析失败等，执行器
//   必有错误回执拦下）仍返 null（定案口径见 ToolContracts preflight 注）。内置服务商 delete
//   **不弹卡**——直接错误回执「不可删除，可停用」。
// ★ 定位纪律：统一 providerId（经 get_provider_config 概览取得）；id 不存在 → 回执指引先查
//   概览（不猜名）。
// ★ 坑50 import 方向：契约自 ToolContracts 叶子引、工具名自 ToolIds 叶子引（禁经聚合根
//   ToolTypes）；HeaderGuard 零 import 叶子；本件不反向被 ProviderDb 引用，无环。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { clipReceiptDiffValue, ConfirmPrompt, CONFIRM_LEVEL_IRREVERSIBLE, CONFIRM_LEVEL_WRITE,
  CONFIRM_ROUTE_HUMAN, ToolExecutor, toolArgsParseErrorText, toolErrorText } from './ToolContracts';
import { routeConfirmPrompt } from './ConfirmRouting';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { dataApproveMode } from '../AppPreferences';
import { deleteProvider, insertProvider, ProviderRow, PROVIDER_SECURE_INPUT_TARGET_KEY,
  queryProviders, setProviderEnabled, updateProvider } from '../store/ProviderDb';
import { deleteProviderKey, insertKeyPlaceholder, insertProviderKey, ProviderKeyRow,
  queryProviderKeys, renameProviderKey, setProviderKeyEnabled } from '../store/ProviderKeyDb';
import { clearPendingKey, getPendingKey, keyHintOf, loadPoolKey, removePoolKeys,
  savePoolKey } from '../store/KeyStore';
import { CatalogPreset, CATALOG_PRESETS } from './ProviderCatalog';
import { ENDPOINT_CHAT, ENDPOINT_VALUES, HeaderPair, parseHeaderPairs, PROTOCOL_OPENAI,
  PROTOCOL_VALUES, serializeHeaderPairs } from './AiTypes';
import { HeaderKV, isCredentialHeaderName, mergeHeaderPairs } from './HeaderGuard';

const DOMAIN: number = 0xD5A6;
const TAG: string = 'ToolProviderAdmin';

// ── 参数读取助手（ToolKnowledge 同族口径：trim 取串 / 整数缺省回退；本件局部实现）──
function readStrArg(parsed: Record<string, Object>, key: string): string {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'string' ? raw.trim() : '';
}

function readBoolArg(parsed: Record<string, Object>, key: string): boolean {
  const raw: Object | undefined = parsed[key];
  return raw === true;
}

function readHeaderKvArgs(parsed: Record<string, Object>, key: string): HeaderKV[] {
  const raw: Object | undefined = parsed[key];
  if (raw === undefined || !Array.isArray(raw)) {
    return [];
  }
  const out: HeaderKV[] = [];
  for (const item of raw as Object[]) {
    const map: Record<string, Object> = item as Record<string, Object>;
    const k: string = typeof map['k'] === 'string' ? (map['k'] as string).trim() : '';
    const v: string = typeof map['v'] === 'string' ? (map['v'] as string) : '';
    if (k !== '') {
      out.push({ k: k, v: v });
    }
  }
  return out;
}

function readStrArrayArg(parsed: Record<string, Object>, key: string): string[] {
  const raw: Object | undefined = parsed[key];
  if (raw === undefined || !Array.isArray(raw)) {
    return [];
  }
  const out: string[] = [];
  for (const item of raw as Object[]) {
    if (typeof item === 'string' && item.trim() !== '') {
      out.push(item.trim());
    }
  }
  return out;
}

// ── 参数校验纯函数（自包含可直跑——断言副本剥 import 后以源值桩接替枚举常量）──

export interface ManageProvidersValidation {
  ok: boolean;
  error: string;
  action: string;
  providerId: string;
  name: string;
  baseUrl: string;
  protocol: string; // '' = 未传（create 无 preset 时缺省 openai 由执行器补）
  endpoint: string; // '' = 未传（缺省 chat；非 openai 协议钳位 chat 在执行器）
  preset: string;
  label: string;
  keyId: string;
  keyEnabled: boolean;
  addHeaders: HeaderKV[];
  removeHeaders: string[];
}

function rejectProvidersArgs(error: string): ManageProvidersValidation {
  return { ok: false, error: error, action: '', providerId: '', name: '', baseUrl: '',
    protocol: '', endpoint: '', preset: '', label: '', keyId: '', keyEnabled: false,
    addHeaders: [], removeHeaders: [] };
}

const MANAGE_PROVIDERS_ACTIONS: string[] = ['create', 'update', 'enable', 'disable', 'delete',
  'add_key', 'rename_key', 'toggle_key', 'delete_key', 'set_headers', 'assign_key'];

export function validateManageProvidersArgs(argsJson: string): ManageProvidersValidation {
  let parsed: Record<string, Object>;
  try {
    parsed = JSON.parse(argsJson) as Record<string, Object>;
  } catch (e) {
    return rejectProvidersArgs(toolArgsParseErrorText(argsJson));
  }
  const action: string = readStrArg(parsed, 'action');
  if (!MANAGE_PROVIDERS_ACTIONS.includes(action)) {
    return rejectProvidersArgs('action 必须是 ' + MANAGE_PROVIDERS_ACTIONS.join('、') +
      ' 之一。');
  }
  const v: ManageProvidersValidation = {
    ok: true, error: '', action: action,
    providerId: readStrArg(parsed, 'providerId'),
    name: readStrArg(parsed, 'name'),
    baseUrl: readStrArg(parsed, 'baseUrl'),
    protocol: readStrArg(parsed, 'protocol'),
    endpoint: readStrArg(parsed, 'endpoint'),
    preset: readStrArg(parsed, 'preset'),
    label: readStrArg(parsed, 'label'),
    keyId: readStrArg(parsed, 'keyId'),
    keyEnabled: readBoolArg(parsed, 'enabled'),
    addHeaders: readHeaderKvArgs(parsed, 'add'),
    removeHeaders: readStrArrayArg(parsed, 'remove')
  };
  // create 外一律要 providerId；create 要 name（preset 只回填地址三件，不代取名）
  if (action !== 'create' && v.providerId === '') {
    return rejectProvidersArgs(action + ' 需要 providerId，请先调用 get_provider_config 取得。');
  }
  if (action === 'create' && v.name === '') {
    return rejectProvidersArgs('create 需要 name（服务商名称）。');
  }
  // 协议 / 接口形态给了就校验枚举（缺省与钳位语义在执行器）
  if (v.protocol !== '' && !PROTOCOL_VALUES.includes(v.protocol)) {
    return rejectProvidersArgs('protocol 只能是 ' + PROTOCOL_VALUES.join('、') + '。');
  }
  if (v.endpoint !== '' && !ENDPOINT_VALUES.includes(v.endpoint)) {
    return rejectProvidersArgs('endpoint 只能是 ' + ENDPOINT_VALUES.join('、') + '。');
  }
  // 无 preset 的 create 必须给 baseUrl 且带协议前缀（ProviderDetailPage 保存链同口径）
  if (action === 'create' && v.preset === '') {
    if (v.baseUrl === '') {
      return rejectProvidersArgs('create 需要 baseUrl（API 地址，以 http:// 或 https:// 开头），' +
        '或给 preset 按模板回填。');
    }
    if (!v.baseUrl.startsWith('http://') && !v.baseUrl.startsWith('https://')) {
      return rejectProvidersArgs('baseUrl 需以 http:// 或 https:// 开头。');
    }
  }
  // baseUrl 显式传入时一律验前缀（含 preset 场景的覆盖值）
  if (v.baseUrl !== '' && !v.baseUrl.startsWith('http://') && !v.baseUrl.startsWith('https://')) {
    return rejectProvidersArgs('baseUrl 需以 http:// 或 https:// 开头。');
  }
  if (action === 'rename_key' && v.label === '') {
    return rejectProvidersArgs('rename_key 需要 label（新名称）。');
  }
  if (action === 'delete_key' && v.keyId === '') {
    return rejectProvidersArgs('delete_key 需要 keyId。');
  }
  return v;
}

// ── 入参 schema（静态串；动作语义写在 description，模型据此选路——MANAGE_KNOWLEDGE_SCHEMA 同式）──

export const MANAGE_PROVIDERS_SCHEMA: string = '{"type":"object","properties":{' +
  '"action":{"type":"string","enum":["create","update","enable","disable","delete","add_key",' +
  '"rename_key","toggle_key","delete_key","set_headers","assign_key"],' +
  '"description":"create=新建服务商，update=修改服务商配置，enable/disable=启停服务商，' +
  'delete=删除服务商（内置服务商不可删），add_key=新增密钥条目（占位，明文由用户手动填），' +
  'rename_key=重命名密钥条目，toggle_key=启停密钥条目，delete_key=删除密钥条目，' +
  'set_headers=增删自定义请求头，assign_key=把用户暂存的密钥配置到该服务商"},' +
  '"providerId":{"type":"string","description":"服务商 id。除 create 外必填，逐字取自 ' +
  'get_provider_config 概览"},' +
  '"name":{"type":"string","description":"create 必填服务商名称；update 可选改名"},' +
  '"baseUrl":{"type":"string","description":"API 地址，需以 http:// 或 https:// 开头"},' +
  '"protocol":{"type":"string","enum":["openai","anthropic","gemini"],' +
  '"description":"协议。缺省 openai"},' +
  '"endpoint":{"type":"string","enum":["chat","responses"],' +
  '"description":"接口形态。缺省 chat，仅 openai 协议支持 responses"},' +
  '"preset":{"type":"string","description":"create 可选模板名。给定时按模板整组回填地址三件，' +
  '显式传入的字段优先。可选模板见工具说明"},' +
  '"label":{"type":"string","description":"add_key 可选条目名（缺省自动编号）；' +
  'rename_key 必填新名称"},' +
  '"keyId":{"type":"string","description":"密钥条目 id。rename_key/toggle_key/delete_key 必填"},' +
  '"enabled":{"type":"boolean","description":"toggle_key 必填，true 启用 false 停用"},' +
  '"add":{"type":"array","items":{"type":"object","properties":{"k":{"type":"string"},' +
  '"v":{"type":"string"}}},"description":"set_headers 新增或更新的请求头，凭据类头名会被拒绝"},' +
  '"remove":{"type":"array","items":{"type":"string"},' +
  '"description":"set_headers 要删除的请求头名"}},' +
  '"required":["action"]}';

// ── desc 单源（模板清单自 CATALOG_PRESETS 动态拼、零双源；文案守「面向用户文案写作规约」）──

export function buildManageProvidersDesc(): string {
  const presetNames: string = CATALOG_PRESETS
    .map((preset: CatalogPreset): string => preset.displayName).join('、');
  return '代替用户管理服务商配置。用户要求新建、修改、启停或删除服务商时调用。' +
    'action 取 create 新建（name 必填；地址三件可直接给，或给 preset 模板整组回填，可选模板有 ' +
    presetNames + '），update 修改（只传要改的字段），enable 与 disable 启停，' +
    'delete 删除（内置服务商不可删，只能停用），add_key 为服务商新增密钥条目（只建条目不含内容），' +
    'assign_key 把用户暂存的密钥配置到服务商（用户先在输入区「安全输入」粘贴并暂存过密钥；' +
    '自动填充占位条目或新建一条，无需先 add_key），rename_key、toggle_key、delete_key 管理密钥条目，' +
    'set_headers 增删自定义请求头。除 create 外都需先从 get_provider_config 概览取得 providerId。' +
    '密钥填写两条路：新建或新增密钥条目后，引导用户点开输入区的「安全输入」直接填入待填条目；' +
    '用户说已暂存密钥（如消息带「已暂存」尾号提示）时用 assign_key 直接配置。' +
    '配置完成后可再用连接测试验证。密钥明文绝不可要求用户在对话中输入或粘贴，' +
    '只能引导用户在「安全输入」面板或设置页手动填写。凭据类请求头（如认证、令牌、密钥类头名）不能代填，' +
    '请让用户在服务商详情页手动添加。';
}

// ── 定位助手 ──

function locateProviderById(rows: ProviderRow[], providerId: string): ProviderRow | undefined {
  return rows.find((row: ProviderRow): boolean => row.id === providerId);
}

// 定位失败回执（不猜名，指引先查概览）
function providerNotFound(): string {
  return JSON.stringify({ error: '未找到该服务商，请先调用 get_provider_config 查询。' });
}

// 密钥条目定位（keyId 未命中时回执列出该服务商条目 id/名称/启停——模型据此自纠，
// 明文零出现；池空同此路）
async function locateKeyRow(providerId: string, keyId: string): Promise<ProviderKeyRow | null> {
  const rows: ProviderKeyRow[] = await queryProviderKeys(providerId);
  const hit: ProviderKeyRow | undefined =
    rows.find((row: ProviderKeyRow): boolean => row.id === keyId);
  if (hit !== undefined) {
    return hit;
  }
  return null;
}

function keyNotFoundRows(rows: ProviderKeyRow[]): string {
  if (rows.length === 0) {
    return JSON.stringify({ error: '该服务商还没有密钥条目，可先用 add_key 新增。' });
  }
  const briefs: string[] = rows.map((row: ProviderKeyRow): string =>
    row.label + '（id ' + row.id + '，' + (row.enabled ? '启用' : '停用') + '）');
  return JSON.stringify({ error: '未找到该密钥条目。现有条目：' + briefs.join('、') });
}

// ── 确认链预检（fail-closed 分阶段）──

function humanConfirmFallback(text: string, level: string): ConfirmPrompt {
  return { text: text, level: level, route: CONFIRM_ROUTE_HUMAN };
}

const PROVIDERS_WRITE_ACTIONS: string[] = ['create', 'update', 'enable', 'disable', 'add_key',
  'rename_key', 'toggle_key', 'set_headers', 'assign_key'];

export async function manageProvidersNeedsConfirm(argsJson: string,
  _ctx: ToolExecutionContext): Promise<ConfirmPrompt | null> {
  // 坏形态阶段（解析失败 / 非法 action）：执行器必有错误回执拦下，此处返 null（直通）
  const v: ManageProvidersValidation = validateManageProvidersArgs(argsJson);
  if (!v.ok) {
    return null;
  }
  const level: string = v.action === 'delete' || v.action === 'delete_key' ?
    CONFIRM_LEVEL_IRREVERSIBLE : CONFIRM_LEVEL_WRITE;
  const isWriteOrDelete: boolean = PROVIDERS_WRITE_ACTIONS.includes(v.action) ||
    v.action === 'delete' || v.action === 'delete_key';
  if (!isWriteOrDelete) {
    return null; // 防御：枚举外的值已在校验拦下，此分支不可达
  }
  try {
    // 删服务商遇内置行：不弹卡（执行器直接错误回执「不可删除，可停用」）
    if (v.action === 'delete') {
      const rows: ProviderRow[] = await queryProviders();
      const hit: ProviderRow | undefined = locateProviderById(rows, v.providerId);
      if (hit !== undefined && hit.builtin) {
        return null;
      }
    }
    let text: string = '';
    let detail: string = '';
    if (v.action === 'create') {
      text = '新建服务商「' + v.name + '」';
      // 地址要上卡面——用户肉眼核对防钓鱼
      detail = (v.baseUrl !== '' ? v.baseUrl : v.preset) +
        (v.protocol !== '' ? ' · ' + v.protocol : '');
    } else if (v.action === 'update') {
      text = '修改服务商「' + v.providerId + '」的配置';
      detail = v.baseUrl !== '' ? v.baseUrl : '';
    } else if (v.action === 'enable' || v.action === 'disable') {
      // 停用即解绑：停用会清掉引用它的助手绑定、会话覆盖与功能模型槽，确认卡先讲明
      //（用户可见后果），执行后回执再给解除处数
      text = v.action === 'enable' ?
        '启用服务商「' + v.providerId + '」' :
        '停用服务商「' + v.providerId + '」，同时解除引用它的模型选择';
    } else if (v.action === 'add_key') {
      text = '为服务商「' + v.providerId + '」新增密钥条目';
    } else if (v.action === 'assign_key') {
      // 槽空无可配 → 不弹卡直通（执行器错误回执指引先暂存——空槽弹卡会误导用户去确认
      // 一次注定失败的操作）
      if (getPendingKey().trim() === '') {
        return null;
      }
      text = '将暂存密钥配置到服务商「' + v.providerId + '」';
      // 尾号掩码上卡（非明文）——用户与输入区暂存条/发送提示对认
      detail = '密钥尾号 ' + keyHintOf(getPendingKey());
    } else if (v.action === 'rename_key') {
      text = '重命名服务商「' + v.providerId + '」的密钥条目为「' + v.label + '」';
    } else if (v.action === 'toggle_key') {
      text = (v.keyEnabled ? '启用' : '停用') + '服务商「' + v.providerId + '」的密钥条目';
    } else if (v.action === 'set_headers') {
      text = '修改服务商「' + v.providerId + '」的请求头';
      detail = '新增或更新 ' + v.addHeaders.length + ' 条，删除 ' + v.removeHeaders.length + ' 条';
    } else if (v.action === 'delete') {
      text = '删除服务商「' + v.providerId + '」';
    } else {
      text = '删除服务商「' + v.providerId + '」的密钥条目';
    }
    return routeConfirmPrompt({ text: text, level: level, detail: detail }, dataApproveMode());
  } catch (e) {
    // 已判定写/删之后的异常：保守人工卡，不返 null（null = 直通执行 = 绕过确认红线）
    return humanConfirmFallback('即将执行服务商配置修改（' + v.action +
      '）。预检读取配置失败，为安全起见请人工确认', level);
  }
}

// ── 执行器 ──

// update 成功回执：oldValue/newValue 可选——仅实际改动字段拼行时附带（供工具卡红绿 diff）；
// 无可显改动时两键缺席，其余键序逐字照旧
interface ManageProvidersUpdateReceipt {
  ok: boolean;
  providerId: string;
  name: string;
  baseUrl: string;
  protocol: string;
  endpoint: string;
  oldValue?: string;
  newValue?: string;
}

export class ManageProvidersExecutor implements ToolExecutor {
  async execute(argsJson: string, _ctx: ToolExecutionContext): Promise<string> {
    const v: ManageProvidersValidation = validateManageProvidersArgs(argsJson);
    if (!v.ok) {
      return JSON.stringify({ error: v.error });
    }
    try {
      const rows: ProviderRow[] = await queryProviders();
      switch (v.action) {
        case 'create':
          return await this.create(rows, v);
        case 'update':
          return await this.update(rows, v);
        case 'enable':
        case 'disable':
          return await this.toggle(rows, v);
        case 'delete':
          return await this.remove(rows, v);
        case 'add_key':
          return await this.addKey(rows, v);
        case 'assign_key':
          return await this.assignKey(rows, v);
        case 'rename_key':
          return await this.renameKey(rows, v);
        case 'toggle_key':
          return await this.toggleKey(rows, v);
        case 'delete_key':
          return await this.deleteKey(rows, v);
        default:
          return await this.setHeaders(rows, v);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'manage_providers 失败：%{public}s', toolErrorText(e));
      return JSON.stringify({ error: '服务商管理操作失败：' + toolErrorText(e) });
    }
  }

  // 密钥引导句：优先提输入区「安全输入」入口（desc 同句已在）；设置页重填链仍真作次选；
  // 暂存路径 = 用户先「暂存」再由本工具 assign_key 转运
  private static keyGuideText(): string {
    return '密钥尚未配置。请引导用户点开输入区的「安全输入」直接填入该条目；' +
      '用户也可先粘贴暂存，再用 assign_key 配置。也可到 设置 → 服务商管理 的密钥池点「重填」。';
  }

  // create：preset 回填（显式字段覆盖）→ 校验 → 一步落库 → 占位密钥行 + 中转键
  private async create(rows: ProviderRow[], v: ManageProvidersValidation): Promise<string> {
    let baseUrl: string = v.baseUrl;
    let protocol: string = v.protocol;
    let endpoint: string = v.endpoint;
    if (v.preset !== '') {
      const preset: CatalogPreset | undefined = CATALOG_PRESETS.find(
        (row: CatalogPreset): boolean => row.displayName === v.preset);
      if (preset === undefined) {
        const names: string = CATALOG_PRESETS
          .map((row: CatalogPreset): string => row.displayName).join('、');
        return JSON.stringify({ error: '未找到模板「' + v.preset + '」。可用模板：' + names });
      }
      if (baseUrl === '') {
        baseUrl = preset.baseUrl;
      }
      if (protocol === '') {
        protocol = preset.protocol;
      }
      if (endpoint === '') {
        endpoint = preset.endpoint;
      }
    }
    if (protocol === '') {
      protocol = PROTOCOL_OPENAI;
    }
    // 非 openai 协议钳位 chat（resolveActiveConnection 同款保守语义——responses 仅 openai 有意义）
    endpoint = protocol === PROTOCOL_OPENAI && endpoint !== '' ? endpoint : ENDPOINT_CHAT;
    const row: ProviderRow = await insertProvider(v.name, baseUrl, protocol, endpoint, '', '', true);
    const key: ProviderKeyRow = await insertKeyPlaceholder(row.id, 'Key 1');
    AppStorage.setOrCreate(PROVIDER_SECURE_INPUT_TARGET_KEY,
      JSON.stringify({ providerId: row.id, keyId: key.id }));
    return JSON.stringify({ ok: true, providerId: row.id, name: row.name, protocol: row.protocol,
      baseUrl: row.baseUrl, keyId: key.id, note: ManageProvidersExecutor.keyGuideText() });
  }

  // update：读-改-写（headers/body_overrides 现值原样传回——工具不碰两列）。回执加
  // oldValue/newValue（仅实际改动字段拼行——名称/地址/协议/兼容端点，值经
  // clipReceiptDiffValue 单源截断）供工具卡红绿 diff；传值与现值全等不带两键——不造全等红绿对
  private async update(rows: ProviderRow[], v: ManageProvidersValidation): Promise<string> {
    const hit: ProviderRow | undefined = locateProviderById(rows, v.providerId);
    if (hit === undefined) {
      return providerNotFound();
    }
    if (v.name === '' && v.baseUrl === '' && v.protocol === '' && v.endpoint === '') {
      return JSON.stringify({ error: '没有要修改的字段。可改 name、baseUrl、protocol、endpoint，' +
        '至少传一项。' });
    }
    const name: string = v.name !== '' ? v.name : hit.name;
    const baseUrl: string = v.baseUrl !== '' ? v.baseUrl : hit.baseUrl;
    const protocol: string = v.protocol !== '' ? v.protocol : hit.protocol;
    const endpoint: string = v.endpoint !== '' ? v.endpoint : hit.endpoint;
    await updateProvider(hit.id, name, baseUrl, protocol, hit.headers, endpoint, hit.bodyOverrides);
    const oldLines: string[] = [];
    const newLines: string[] = [];
    const pushPair = (label: string, before: string, after: string): void => {
      if (before !== after) {
        oldLines.push(label + ' ' + before);
        newLines.push(label + ' ' + after);
      }
    };
    pushPair('名称', hit.name, name);
    pushPair('地址', hit.baseUrl, baseUrl);
    pushPair('协议', hit.protocol, protocol);
    pushPair('兼容端点', hit.endpoint, endpoint);
    const receipt: ManageProvidersUpdateReceipt = { ok: true, providerId: hit.id, name: name,
      baseUrl: baseUrl, protocol: protocol, endpoint: endpoint };
    if (oldLines.length > 0) {
      receipt.oldValue = clipReceiptDiffValue(oldLines.join('\n'));
      receipt.newValue = clipReceiptDiffValue(newLines.join('\n'));
    }
    return JSON.stringify(receipt);
  }

  private async toggle(rows: ProviderRow[], v: ManageProvidersValidation): Promise<string> {
    const hit: ProviderRow | undefined = locateProviderById(rows, v.providerId);
    if (hit === undefined) {
      return providerNotFound();
    }
    // 停用即解绑：停用会解除引用它的模型选择（助手绑定/会话覆盖/功能模型槽），有解除时
    // 回执补字段——模型据此转述，槽位变「未选择」有据可查；启用恒 0
    const cleared: number = await setProviderEnabled(hit.id, v.action === 'enable');
    if (cleared > 0) {
      return JSON.stringify({ ok: true, providerId: hit.id, name: hit.name,
        enabled: v.action === 'enable', clearedBindings: cleared });
    }
    return JSON.stringify({ ok: true, providerId: hit.id, name: hit.name,
      enabled: v.action === 'enable' });
  }

  // delete：内置拒（不弹卡路径）→ 三步「查池 id → deleteProvider → removePoolKeys」
  //（ProviderPage.deletePending 同序——Asset 成对释放铁律）
  private async remove(rows: ProviderRow[], v: ManageProvidersValidation): Promise<string> {
    const hit: ProviderRow | undefined = locateProviderById(rows, v.providerId);
    if (hit === undefined) {
      return providerNotFound();
    }
    if (hit.builtin) {
      return JSON.stringify({ error: '内置服务商不可删除，可改为停用。' });
    }
    const keyRows: ProviderKeyRow[] = await queryProviderKeys(hit.id);
    const keyIds: string[] = keyRows.map((row: ProviderKeyRow): string => row.id);
    await deleteProvider(hit.id);
    await removePoolKeys(hit.id, keyIds);
    return JSON.stringify({ ok: true, deleted: hit.name, removedKeyCount: keyIds.length });
  }

  private async addKey(rows: ProviderRow[], v: ManageProvidersValidation): Promise<string> {
    const hit: ProviderRow | undefined = locateProviderById(rows, v.providerId);
    if (hit === undefined) {
      return providerNotFound();
    }
    const key: ProviderKeyRow = await insertKeyPlaceholder(hit.id, v.label);
    AppStorage.setOrCreate(PROVIDER_SECURE_INPUT_TARGET_KEY,
      JSON.stringify({ providerId: hit.id, keyId: key.id }));
    return JSON.stringify({ ok: true, providerId: hit.id, keyId: key.id, label: key.label,
      note: '已新增密钥条目「' + key.label + '」（尚无内容）。' +
        ManageProvidersExecutor.keyGuideText() });
  }

  // assign_key：把用户暂存的密钥（AppStorage 内存槽，安全输入面板「暂存」写入）配置到指定
  // 服务商——池内已有相同明文 → 拒不重复写入；有「明文缺失」占位行（add_key / create 链
  // 所建）→ 填第一支；无占位 → insertProviderKey 新建。写完清暂存槽；被填条目恰为中转键
  // 指向条目时连中转键一并清（直填语义闭环，键残留会指着已有明文的条目误导重填）。回执只
  // 带条目名与尾号掩码，零明文
  private async assignKey(rows: ProviderRow[], v: ManageProvidersValidation): Promise<string> {
    const hit: ProviderRow | undefined = locateProviderById(rows, v.providerId);
    if (hit === undefined) {
      return providerNotFound();
    }
    const plain: string = getPendingKey().trim();
    if (plain === '') {
      return JSON.stringify({ error: '暂存槽中没有密钥。请引导用户点开输入区的「安全输入」' +
        '粘贴密钥并暂存，再调用本动作。' });
    }
    const keyRows: ProviderKeyRow[] = await queryProviderKeys(hit.id);
    let placeholder: ProviderKeyRow | null = null;
    for (const row of keyRows) {
      const existing: string = (await loadPoolKey(hit.id, row.id)).trim();
      if (existing === '') {
        if (placeholder === null) {
          placeholder = row; // 首支占位行（query 已按 sortOrder 升序）
        }
        continue;
      }
      if (existing === plain) {
        return JSON.stringify({ error: '该服务商已存在相同密钥（条目「' + row.label +
          '」），未重复写入。' });
      }
    }
    let filled: ProviderKeyRow;
    if (placeholder !== null) {
      await savePoolKey(hit.id, placeholder.id, plain);
      filled = placeholder;
    } else {
      filled = await insertProviderKey(hit.id, plain);
    }
    clearPendingKey();
    try {
      const target: Record<string, Object> =
        JSON.parse(AppStorage.get<string>(PROVIDER_SECURE_INPUT_TARGET_KEY) ?? '') as
        Record<string, Object>;
      if (target['keyId'] === filled.id) {
        AppStorage.setOrCreate(PROVIDER_SECURE_INPUT_TARGET_KEY, '');
      }
    } catch (e) {
      // 坏 JSON 留置——面板 open 时走失效降级暂存态自愈，此处不清不抛
    }
    return JSON.stringify({ ok: true, providerId: hit.id, keyId: filled.id,
      label: filled.label, hint: keyHintOf(plain),
      note: '已把暂存密钥填入条目「' + filled.label + '」，暂存已清出。' });
  }

  private async renameKey(rows: ProviderRow[], v: ManageProvidersValidation): Promise<string> {
    const hit: ProviderRow | undefined = locateProviderById(rows, v.providerId);
    if (hit === undefined) {
      return providerNotFound();
    }
    const keyRows: ProviderKeyRow[] = await queryProviderKeys(hit.id);
    const key: ProviderKeyRow | null = await locateKeyRow(hit.id, v.keyId);
    if (key === null) {
      return keyNotFoundRows(keyRows);
    }
    await renameProviderKey(key.id, v.label);
    return JSON.stringify({ ok: true, keyId: key.id, label: v.label });
  }

  private async toggleKey(rows: ProviderRow[], v: ManageProvidersValidation): Promise<string> {
    const hit: ProviderRow | undefined = locateProviderById(rows, v.providerId);
    if (hit === undefined) {
      return providerNotFound();
    }
    const keyRows: ProviderKeyRow[] = await queryProviderKeys(hit.id);
    const key: ProviderKeyRow | null = await locateKeyRow(hit.id, v.keyId);
    if (key === null) {
      return keyNotFoundRows(keyRows);
    }
    await setProviderKeyEnabled(key.id, v.keyEnabled);
    return JSON.stringify({ ok: true, keyId: key.id, label: key.label, enabled: v.keyEnabled });
  }

  private async deleteKey(rows: ProviderRow[], v: ManageProvidersValidation): Promise<string> {
    const hit: ProviderRow | undefined = locateProviderById(rows, v.providerId);
    if (hit === undefined) {
      return providerNotFound();
    }
    const keyRows: ProviderKeyRow[] = await queryProviderKeys(hit.id);
    const key: ProviderKeyRow | null = await locateKeyRow(hit.id, v.keyId);
    if (key === null) {
      return keyNotFoundRows(keyRows);
    }
    await deleteProviderKey(hit.id, key.id); // Asset 明文随删（先删明文后删行，KeyStore 既有序）
    return JSON.stringify({ ok: true, keyId: key.id, label: key.label });
  }

  // set_headers：凭据黑名单整调用拒（HeaderGuard 单源）→ 增量 merge → 整写（其余字段原样）
  private async setHeaders(rows: ProviderRow[], v: ManageProvidersValidation): Promise<string> {
    const hit: ProviderRow | undefined = locateProviderById(rows, v.providerId);
    if (hit === undefined) {
      return providerNotFound();
    }
    const blocked: string[] = v.addHeaders
      .filter((pair: HeaderKV): boolean => isCredentialHeaderName(pair.k))
      .map((pair: HeaderKV): string => pair.k);
    if (blocked.length > 0) {
      return JSON.stringify({ error: '含凭据类请求头（' + blocked.join('、') +
        '），不能代填。请让用户在服务商详情页手动添加。' });
    }
    if (v.addHeaders.length === 0 && v.removeHeaders.length === 0) {
      return JSON.stringify({ error: '没有要改的请求头。请传 add 或 remove，至少一项。' });
    }
    const existing: HeaderPair[] = parseHeaderPairs(hit.headers);
    const existingKv: HeaderKV[] = existing.map((pair: HeaderPair): HeaderKV =>
      ({ k: pair.k, v: pair.v }));
    const merged: HeaderKV[] = mergeHeaderPairs(existingKv, v.addHeaders, v.removeHeaders);
    const mergedJson: string = serializeHeaderPairs(merged.map((pair: HeaderKV): HeaderPair =>
      ({ k: pair.k, v: pair.v })));
    // 回执只回计数与头名（值零回显，回执纪律）
    let updated: number = 0;
    for (const pair of v.addHeaders) {
      const before: HeaderPair | undefined = existing.find((row: HeaderPair): boolean =>
        row.k.trim().toLowerCase() === pair.k.trim().toLowerCase());
      if (before !== undefined) {
        updated++;
      }
    }
    const addedCount: number = v.addHeaders.length - updated;
    let removedCount: number = 0;
    for (const name of v.removeHeaders) {
      if (existing.some((row: HeaderPair): boolean =>
        row.k.trim().toLowerCase() === name.toLowerCase())) {
        removedCount++;
      }
    }
    await updateProvider(hit.id, hit.name, hit.baseUrl, hit.protocol, mergedJson, hit.endpoint,
      hit.bodyOverrides);
    const names: string = merged.map((pair: HeaderKV): string => pair.k).join('、');
    return JSON.stringify({ ok: true, providerId: hit.id, added: addedCount, updated: updated,
      removed: removedCount, total: merged.length, headerNames: names });
  }
}
