// AI 配置工具域 · 连接测试与余额：test_provider 两动作（test 连接探针 / fetch_models 模型
// 发现）与 manage_balance 三动作（get / set / query），全部薄封装既有引擎（ModelListApi 的
// fetchModelIds / probeAnthropicMessages + BalanceApi.fetchBalance + ProviderBalanceDb），零重写。
// ★ 探针口径（照 KeyConnectTester.testKeyConnection 同判定，但不引该 UI 件——components
//   层反向依赖禁令）：openai / gemini 走 fetchModelIds 列模型（零 token）；anthropic 走
//   probeAnthropicMessages（模型取该服务商首个启用行，max_tokens=1 最小消耗，purpose='test'
//   记账为引擎既有行为）。三项能力测试（runConnectTests）与 UI 面板不封装。
// ★ 密钥明文纪律：明文只进网络请求参数位——loadPoolKey / firstEnabledPoolKey 的返回值零回执
//   零日志零错误文案；回执只回「通过/失败 + 引擎中文原因/清单」。余额专用 Key 与 balance
//   自定义头的**值**一律不回显（get 只回 hasKey / headerCount；set 读现值原样写回——必要
//   读取面照测试探针先例，只进写回参数位）。
// ★ 双封顶：模型发现清单直接复用只读件 ToolProvider 已导出的
//   PROVIDER_MODEL_LIST_MAX / PROVIDER_RESULT_MAX_CHARS（同域单源、单向无环）。
// ★ 确认链：manage_balance 的 set 写档；test / fetch_models / get / query 只读零确认
//   （query 落上次值 = 徽章同源写，非配置写）。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { clipReceiptDiffValue, ConfirmPrompt, CONFIRM_LEVEL_WRITE, CONFIRM_ROUTE_HUMAN,
  ToolExecutor, toolArgsParseErrorText, toolErrorText } from './ToolContracts';
import { routeConfirmPrompt } from './ConfirmRouting';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { dataApproveMode } from '../AppPreferences';
import { fetchBalance, BalanceQuery, BalanceResult } from './BalanceApi';
import { fetchModelIds, probeAnthropicMessages } from './ModelListApi';
import { HeaderPair, parseHeaderPairs, serializeHeaderPairs } from './AiTypes';
import { HeaderKV, isCredentialHeaderName, mergeHeaderPairs } from './HeaderGuard';
import { PROVIDER_MODEL_LIST_MAX, PROVIDER_RESULT_MAX_CHARS } from './ToolProvider';
import { ModelRow, queryModels, queryProviders, ProviderRow } from '../store/ProviderDb';
import { loadPoolKey } from '../store/KeyStore';
import { firstEnabledPoolKey, ProviderKeyRow, queryProviderKeys } from '../store/ProviderKeyDb';
import { BalanceConfig, BalanceState, queryBalanceState, saveBalanceText,
  updateBalanceConfig } from '../store/ProviderBalanceDb';

const DOMAIN: number = 0xD5A8;
const TAG: string = 'ToolProviderProbe';

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

// 密钥未配置引导回执（test / fetch_models / query 的回退 key 路共用——零明文）
function keyGuideResult(): string {
  return JSON.stringify({ error: '还没有可用的密钥，请先让用户在设置页服务商管理的密钥池里填入密钥。' });
}

// 清单双封顶纯函数（条数上限 + 字符预算取先到者；截断计数如实）——断言直跑面
export interface ProbeListClip {
  shown: string[];
  truncated: number;
}

export function clipModelIdList(ids: string[], maxCount: number, maxChars: number): ProbeListClip {
  let count: number = ids.length < maxCount ? ids.length : maxCount;
  while (true) {
    const shown: string[] = ids.slice(0, count);
    if (JSON.stringify(shown).length <= maxChars || count === 0) {
      return { shown: shown, truncated: ids.length - count };
    }
    count = Math.floor(count * 0.9);
  }
}

// ── schema 与 desc ──

export const TEST_PROVIDER_SCHEMA: string = '{"type":"object","properties":{' +
  '"action":{"type":"string","enum":["test","fetch_models"],' +
  '"description":"test=测试服务商连接，fetch_models=从服务商拉取可用模型清单"},' +
  '"providerId":{"type":"string","description":"服务商 id，逐字取自 get_provider_config 概览"}},' +
  '"required":["action","providerId"]}';

export function buildTestProviderDesc(): string {
  return '测试服务商连通性或发现可用模型。用户配好服务商后要求测一下连接时用 test，' +
    '要求拉取或看看有哪些模型时用 fetch_models。两者都需先从 get_provider_config 取得 ' +
    'providerId，并用该服务商首个启用的密钥发起请求。test 通过返回通过与可用模型数，' +
    '失败返回引擎的中文原因，不会消耗对话 token。fetch_models 只返回清单不写入配置，' +
    '把清单给用户挑，用户确认需要哪些后再逐个添加。余额查询的配置与查询用余额工具。';
}

export const MANAGE_BALANCE_SCHEMA: string = '{"type":"object","properties":{' +
  '"action":{"type":"string","enum":["get","set","query"],' +
  '"description":"get=查看余额查询配置，set=修改配置，query=查询余额"},' +
  '"providerId":{"type":"string","description":"服务商 id，逐字取自 get_provider_config 概览"},' +
  '"enabled":{"type":"boolean","description":"set 可选，余额查询总开关"},' +
  '"baseUrl":{"type":"string","description":"set 可选，专用查询地址，留空则用服务商地址"},' +
  '"path":{"type":"string","description":"set 可选，查询路径，例如 /v1/user/balance"},' +
  '"resultPath":{"type":"string","description":"set 可选，响应中余额字段的点路径"},' +
  '"currency":{"type":"string","description":"set 可选，币种兜底值，点路径未取到时显示"},' +
  '"currencyPath":{"type":"string","description":"set 可选，响应中币种字段的点路径"},' +
  '"addHeaders":{"type":"array","items":{"type":"object","properties":{"k":{"type":"string"},' +
  '"v":{"type":"string"}}},"description":"set 可选，新增或更新的自定义请求头，凭据类头名会被拒绝"},' +
  '"removeHeaders":{"type":"array","items":{"type":"string"},' +
  '"description":"set 可选，要删除的自定义请求头名"}},' +
  '"required":["action","providerId"]}';

export function buildManageBalanceDesc(): string {
  return '代替用户配置与查询服务商余额。用户要求配一下余额查询时先用 get 看现有配置，' +
    '再用 set 修改（只传要改的字段，至少一项），然后用 query 查询余额返回数字与币种。' +
    '需先从 get_provider_config 取得 providerId。查询只支持 GET 方式，路径与点路径按用户' +
    '提供的填写。余额专用密钥与自定义请求头由用户在设置页填写，工具只代改开关、地址、' +
    '路径与币种这些非敏感字段，值不会显示在对话里。';
}

// ── 定位助手 ──

async function locateProvider(providerId: string): Promise<ProviderRow | null> {
  const rows: ProviderRow[] = await queryProviders();
  const hit: ProviderRow | undefined =
    rows.find((row: ProviderRow): boolean => row.id === providerId);
  return hit ?? null;
}

function providerNotFound(): string {
  return JSON.stringify({ error: '未找到该服务商，请先调用 get_provider_config 查询。' });
}

// 首个启用密钥条目行（test 用：明文经 loadPoolKey 只进请求参数位）
async function firstEnabledKeyRow(providerId: string): Promise<ProviderKeyRow | null> {
  const rows: ProviderKeyRow[] = await queryProviderKeys(providerId);
  const hit: ProviderKeyRow | undefined =
    rows.find((row: ProviderKeyRow): boolean => row.enabled);
  return hit ?? null;
}

// ── test_provider 执行器（test / fetch_models 两动作，只读零确认）──

export class TestProviderExecutor implements ToolExecutor {
  async execute(argsJson: string, _ctx: ToolExecutionContext): Promise<string> {
    let action: string = '';
    let providerId: string = '';
    try {
      const parsed = JSON.parse(argsJson) as Record<string, Object>;
      action = readStrArg(parsed, 'action');
      providerId = readStrArg(parsed, 'providerId');
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    if (providerId === '') {
      return JSON.stringify({ error: '需要 providerId，请先调用 get_provider_config 取得。' });
    }
    const provider: ProviderRow | null = await locateProvider(providerId);
    if (provider === null) {
      return providerNotFound();
    }
    try {
      if (action === 'fetch_models') {
        return await this.fetchModels(provider);
      }
      if (action === 'test') {
        return await this.test(provider);
      }
      return JSON.stringify({ error: 'action 必须是 test 或 fetch_models。' });
    } catch (e) {
      // 失败 detail = 引擎中文原因（引擎错误不含密钥——请求层只回状态与响应体摘要）；
      // 此处不再拼接任何本地变量，防明文间接混入（回执纪律 §3.0-C）
      hilog.warn(DOMAIN, TAG, 'test_provider 失败：%{public}s', toolErrorText(e));
      return JSON.stringify({ error: toolErrorText(e) });
    }
  }

  // 薄探针（照 testKeyConnection 同口径，不引 UI 件）：openai/gemini 列模型零 token；
  // anthropic 首个启用模型最小消耗探针
  private async test(provider: ProviderRow): Promise<string> {
    const keyRow: ProviderKeyRow | null = await firstEnabledKeyRow(provider.id);
    if (keyRow === null) {
      return keyGuideResult();
    }
    const key: string = await loadPoolKey(provider.id, keyRow.id); // 只进下方请求参数位
    if (provider.protocol === 'anthropic') {
      const modelId: string = await firstEnabledChatModelId(provider.id);
      if (modelId === '') {
        return JSON.stringify({ error: '该服务商还没有启用的对话模型，请先添加模型再测试。' });
      }
      await probeAnthropicMessages(provider.baseUrl, key, modelId);
      return JSON.stringify({ ok: true, protocol: provider.protocol,
        detail: '连接与鉴权通过（模型 ' + modelId + '）' });
    }
    const ids: string[] = await fetchModelIds(provider.baseUrl, key, provider.protocol);
    return JSON.stringify({ ok: true, protocol: provider.protocol,
      detail: '连接与鉴权通过，服务端返回 ' + ids.length + ' 个模型' });
  }

  private async fetchModels(provider: ProviderRow): Promise<string> {
    const key: string = await firstEnabledPoolKey(provider.id);
    if (key === '') {
      return keyGuideResult();
    }
    const ids: string[] = await fetchModelIds(provider.baseUrl, key, provider.protocol);
    const clip: ProbeListClip = clipModelIdList(ids, PROVIDER_MODEL_LIST_MAX,
      PROVIDER_RESULT_MAX_CHARS);
    // 清单不入库——desc 教「把清单给用户挑，用户确认后用模型管理工具添加」
    return JSON.stringify({ ok: true, providerId: provider.id, models: clip.shown,
      truncated: clip.truncated });
  }
}

// anthropic 探针模型选取（启用对话模型首个；testKeyConnection 同判据）
async function firstEnabledChatModelId(providerId: string): Promise<string> {
  const rows: ModelRow[] = await queryModels(providerId, 'chat');
  const hit: ModelRow | undefined = rows.find((row: ModelRow): boolean => row.enabled);
  return hit !== undefined ? hit.modelId : '';
}

// ── manage_balance 确认链（只拦 set；get / query 只读返 null）──

export async function manageBalanceNeedsConfirm(argsJson: string,
  _ctx: ToolExecutionContext): Promise<ConfirmPrompt | null> {
  let action: string = '';
  let providerId: string = '';
  let path: string = '';
  let resultPath: string = '';
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    action = readStrArg(parsed, 'action');
    providerId = readStrArg(parsed, 'providerId');
    path = readStrArg(parsed, 'path');
    resultPath = readStrArg(parsed, 'resultPath');
  } catch (e) {
    return null; // 坏形态阶段：执行器必有错误回执拦下
  }
  if (action !== 'set') {
    return null; // get / query 只读
  }
  try {
    const detail: string = (path !== '' ? '路径 ' + path : '') +
      (resultPath !== '' ? (path !== '' ? ' · ' : '') + '余额点路径 ' + resultPath : '');
    return routeConfirmPrompt({
      text: '修改服务商「' + providerId + '」的余额查询配置',
      level: CONFIRM_LEVEL_WRITE,
      detail: detail
    }, dataApproveMode());
  } catch (e) {
    return { text: '即将修改余额查询配置。预检失败，为安全起见请人工确认',
      level: CONFIRM_LEVEL_WRITE, route: CONFIRM_ROUTE_HUMAN };
  }
}

// ── manage_balance 执行器（get / set / query）──

// set 成功回执（★ oldValue/newValue 可选——仅实际改动字段拼行时附带，供工具卡红绿 diff；
// 无可显改动时两键缺席，其余键序逐字照旧）
interface ManageBalanceSetReceipt {
  ok: boolean;
  providerId: string;
  headerCount: number;
  oldValue?: string;
  newValue?: string;
}

export class ManageBalanceExecutor implements ToolExecutor {
  async execute(argsJson: string, _ctx: ToolExecutionContext): Promise<string> {
    let action: string = '';
    let providerId: string = '';
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
      action = readStrArg(parsed, 'action');
      providerId = readStrArg(parsed, 'providerId');
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    if (providerId === '') {
      return JSON.stringify({ error: '需要 providerId，请先调用 get_provider_config 取得。' });
    }
    if (action !== 'get' && action !== 'set' && action !== 'query') {
      return JSON.stringify({ error: 'action 必须是 get、set 或 query。' });
    }
    const provider: ProviderRow | null = await locateProvider(providerId);
    if (provider === null) {
      return providerNotFound();
    }
    try {
      if (action === 'get') {
        return this.get(provider.id);
      }
      if (action === 'set') {
        return await this.set(provider, parsed);
      }
      return await this.query(provider);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'manage_balance 失败：%{public}s', toolErrorText(e));
      return JSON.stringify({ error: '余额操作失败：' + toolErrorText(e) });
    }
  }

  // get：六配置字段 + hasKey + headerCount——key 与头值零回显
  private async get(providerId: string): Promise<string> {
    const st: BalanceState = await queryBalanceState(providerId);
    return JSON.stringify({ ok: true, enabled: st.enabled, baseUrl: st.baseUrl, path: st.path,
      resultPath: st.resultPath, currency: st.currency, currencyPath: st.currencyPath,
      hasKey: st.key !== '', headerCount: parseHeaderPairs(st.headers).length });
  }

  // set：读-改-写整写八列——key 保持现值原样传回（工具不改密钥明文；此读取为「不改密钥」
  // 的必要读取面，明文只进写回参数位、零回执零日志）；addHeaders 过凭据黑名单
  private async set(provider: ProviderRow, parsed: Record<string, Object>): Promise<string> {
    const st: BalanceState = await queryBalanceState(provider.id);
    const enabled: boolean | null = readBoolOpt(parsed, 'enabled');
    const baseUrl: string = readStrArg(parsed, 'baseUrl');
    const path: string = readStrArg(parsed, 'path');
    const resultPath: string = readStrArg(parsed, 'resultPath');
    const currency: string = readStrArg(parsed, 'currency');
    const currencyPath: string = readStrArg(parsed, 'currencyPath');
    const addHeaders: HeaderKV[] = readHeaderKvArgs(parsed, 'addHeaders');
    const removeHeaders: string[] = readStrArrayArg(parsed, 'removeHeaders');
    if (enabled === null && baseUrl === '' && path === '' && resultPath === '' && currency === '' &&
      currencyPath === '' && addHeaders.length === 0 && removeHeaders.length === 0) {
      return JSON.stringify({ error: '没有要修改的字段。至少传一项。' });
    }
    const blocked: string[] = addHeaders
      .filter((pair: HeaderKV): boolean => isCredentialHeaderName(pair.k))
      .map((pair: HeaderKV): string => pair.k);
    if (blocked.length > 0) {
      return JSON.stringify({ error: '含凭据类请求头（' + blocked.join('、') +
        '），不能代填。请让用户在余额配置页手动添加。' });
    }
    const existing: HeaderKV[] = parseHeaderPairs(st.headers).map((pair: HeaderPair): HeaderKV =>
      ({ k: pair.k, v: pair.v }));
    const merged: HeaderKV[] = mergeHeaderPairs(existing, addHeaders, removeHeaders);
    const cfg: BalanceConfig = {
      enabled: enabled !== null ? enabled : st.enabled,
      baseUrl: baseUrl !== '' ? baseUrl : st.baseUrl,
      path: path !== '' ? path : st.path,
      resultPath: resultPath !== '' ? resultPath : st.resultPath,
      currency: currency !== '' ? currency : st.currency,
      currencyPath: currencyPath !== '' ? currencyPath : st.currencyPath,
      key: st.key, // 现值原样写回（工具不改密钥明文）
      headers: serializeHeaderPairs(merged.map((pair: HeaderKV): HeaderPair =>
        ({ k: pair.k, v: pair.v })))
    };
    await updateBalanceConfig(provider.id, cfg);
    // ★ 回执加 oldValue/newValue（仅实际改动字段拼行——开关/查询地址/查询路径/余额点路径/
    // 币种/币种点路径六行；自定义请求头行只报条数——**头值禁进 diff**〔件头密钥纪律，同回执
    // 只回计数的既有口径〕；值经 clipReceiptDiffValue 单源截断）；无实际改动不带两键
    const oldLines: string[] = [];
    const newLines: string[] = [];
    const pushPair = (label: string, before: string, after: string): void => {
      if (before !== after) {
        oldLines.push(label + ' ' + before);
        newLines.push(label + ' ' + after);
      }
    };
    pushPair('开关', st.enabled ? '开启' : '关闭', cfg.enabled ? '开启' : '关闭');
    pushPair('查询地址', st.baseUrl, cfg.baseUrl);
    pushPair('查询路径', st.path, cfg.path);
    pushPair('余额点路径', st.resultPath, cfg.resultPath);
    pushPair('币种', st.currency, cfg.currency);
    pushPair('币种点路径', st.currencyPath, cfg.currencyPath);
    pushPair('自定义请求头', existing.length + ' 条', merged.length + ' 条');
    const receipt: ManageBalanceSetReceipt = { ok: true, providerId: provider.id,
      headerCount: merged.length };
    if (oldLines.length > 0) {
      receipt.oldValue = clipReceiptDiffValue(oldLines.join('\n'));
      receipt.newValue = clipReceiptDiffValue(newLines.join('\n'));
    }
    return JSON.stringify(receipt);
  }

  // query：无确认链（只读 + 落上次值 = 徽章同源写）；enabled 关 → 引导先 set；
  // key 空回退池首启用（必要读取面——只进请求参数位）；成功落 saveBalanceText
  private async query(provider: ProviderRow): Promise<string> {
    const st: BalanceState = await queryBalanceState(provider.id);
    if (!st.enabled) {
      return JSON.stringify({ error: '余额查询未启用，请先用 set enabled 开启。' });
    }
    let key: string = st.key;
    if (key === '') {
      key = await firstEnabledPoolKey(provider.id);
    }
    if (key === '') {
      return keyGuideResult();
    }
    const query: BalanceQuery = {
      baseUrl: st.baseUrl !== '' ? st.baseUrl : provider.baseUrl,
      path: st.path,
      key: key, // 只进请求参数位
      resultPath: st.resultPath,
      currencyPath: st.currencyPath,
      headers: parseHeaderPairs(st.headers)
    };
    const result: BalanceResult = await fetchBalance(query);
    await saveBalanceText(provider.id, result.text);
    const currency: string = result.currency !== '' ? result.currency : st.currency;
    return JSON.stringify({ ok: true, balance: result.text,
      currency: currency !== '' ? currency : '' });
  }
}

function readBoolOpt(parsed: Record<string, Object>, key: string): boolean | null {
  const raw: Object | undefined = parsed[key];
  if (raw === undefined) {
    return null;
  }
  return raw === true;
}
