// 联网搜索·引擎注册表与编排层（2026-09-10 多引擎一期）：声明式引擎表（顺序即 UI 顺序）
// + Map 分发表 + fallback 解析链 + 取钥分发编排。骨架 = Cube 快照 services/search/
// SearchEngineRegistration/Registry + WebSearchService 分发表（cube调研 02 §⑦⑧ 原文在案，
// 同构零转译）；能力二分（canSearch/canScrape + 能力级 requiresApiKey）= CherryStudio
// 预设表思想（调研档 03 §1.1.1——同一引擎可「搜索要 key、抓取不要 key」，UI 与运行时
// 同表驱动不漂移；一期四家 canScrape 全 false——scrape 恒走本地 HTML 解析，留位给二期
// Reader 类引擎）。
// 分层：引擎实现在 ApiSearchEngines.ets（本文件 import 它注册分发表，禁其反向 import 本
// 文件防环）；query 加工在 SearchQueryClean.ets（零 import）；解析纯函数在
// WebSearchParse.ets；执行器壳（终态语义 + 载荷组装）在 ToolTypes。本文件管「有哪些
// 引擎、当前用哪个、怎么取钥分发」。
// 偏好四键契约见 AppPreferences.ets 联网搜索域节（本文件只 import 键常量与兜底读值）。
import { WebSearchOutcome } from '../providers/WebSearch';
import {
  CHAT_SEARCH_COUNT_KEY, SEARCH_RESULT_COUNT_DEFAULT, resolveSearchResultCount
} from './SearchLimits';
import { getSearchEnabledEngineIds, getSearchEngineCfgJson, getSearchEngineId,
  isSearchServiceEnabled, PREF_SEARCH_ENGINE_CFG_KEY } from '../AppPreferences';
import { loadSearchEngineKey } from '../store/KeyStore';
import { SearchEngineRuntime, bingLocalSearch, bochaSearch, metasoSearch,
  serperSearch } from './ApiSearchEngines';

// 引擎描述符（声明式注册表条目——Cherry 能力二分并入：canSearch/canScrape 各自独立，
// requiresApiKey 为能力级标记而非引擎级）
export interface SearchEngineDescriptor {
  id: string;
  label: string; // UI 展示名
  canSearch: boolean; // 是否能执行 search_web（一期四家全 true，留位）
  canScrape: boolean; // 是否能执行 scrape_web（一期全 false——本地抓取不换引擎）
  requiresApiKey: boolean; // 搜索能力是否需 key（bing_local = false 免配置）
  defaultBaseUrl: string; // 官方默认入口（用户配置空串时生效；'' = 无单入口概念〔bing 双入口〕）
  keyHint: string; // key 形态提示——详情页密钥输入框 placeholder 消费（2026-09-10 决明拍板
                   // 接回：博查「sk- 开头」/秘塔「mk- 开头」拼成「粘贴 API Key，sk- 开头」）；
                   // '' = 该引擎无公开前缀约定，placeholder 回退「粘贴 API Key」
}

// 引擎注册表（顺序即设置页 UI 顺序；★ 加引擎 = 此表加一行 + ApiSearchEngines 加实现
// + SEARCH_HANDLERS 加注册——描述符驱动 UI 与运行时同一张表，Cherry 思想）
export const SEARCH_ENGINES: SearchEngineDescriptor[] = [
  {
    id: 'bing_local', label: 'Bing', canSearch: true, canScrape: false,
    requiresApiKey: false, defaultBaseUrl: '', keyHint: ''
  },
  {
    id: 'bocha', label: '博查', canSearch: true, canScrape: false,
    requiresApiKey: true, defaultBaseUrl: 'https://api.bochaai.com', keyHint: 'sk- 开头'
  },
  {
    id: 'metaso', label: '秘塔', canSearch: true, canScrape: false,
    requiresApiKey: true, defaultBaseUrl: 'https://metaso.cn', keyHint: 'mk- 开头'
  },
  {
    id: 'serper', label: 'Serper', canSearch: true, canScrape: false,
    requiresApiKey: true, defaultBaseUrl: 'https://google.serper.dev', keyHint: ''
  }
];

// 全量引擎 id（EntryAbility persistProp 注册默认 = 默认全开；单一来源本表派生）
export const ALL_SEARCH_ENGINE_IDS: string[] =
  SEARCH_ENGINES.map((e: SearchEngineDescriptor): string => e.id);

// 分发表（替代 if-else——Cube WebSearchService.searchHandlers 同构；新增引擎在此注册。
// 构造走 builder 函数（ArkTS 对字面量元组数组初始化 Map 无先例——空 Map + set 为工程
// 唯一形制，ToolRegistry 同款））
function buildSearchHandlers(): Map<string, (query: string, ctx: SearchEngineRuntime) =>
  Promise<WebSearchOutcome>> {
  const map: Map<string, (query: string, ctx: SearchEngineRuntime) => Promise<WebSearchOutcome>> =
    new Map<string, (query: string, ctx: SearchEngineRuntime) => Promise<WebSearchOutcome>>();
  map.set('bing_local', bingLocalSearch);
  map.set('bocha', bochaSearch);
  map.set('metaso', metasoSearch);
  map.set('serper', serperSearch);
  return map;
}

const SEARCH_HANDLERS: Map<string, (query: string, ctx: SearchEngineRuntime) =>
  Promise<WebSearchOutcome>> = buildSearchHandlers();

export function engineById(id: string): SearchEngineDescriptor | undefined {
  return SEARCH_ENGINES.find((e: SearchEngineDescriptor): boolean => e.id === id);
}

// ── 引擎配置 JSON（{engineId:{baseUrl,hasKey}}）纯函数面（node 直跑断言消费——
//   sse-assert ㊿ 组剥 import 直跑；坏 JSON 容错回空态）──

export interface EngineCfgEntry {
  baseUrl: string;
  hasKey: boolean;
}

export function parseEngineCfg(json: string): Map<string, EngineCfgEntry> {
  const map: Map<string, EngineCfgEntry> = new Map<string, EngineCfgEntry>();
  if (json === '') {
    return map;
  }
  try {
    const parsed: object = JSON.parse(json);
    const rec: Record<string, Object> = parsed as Record<string, Object>;
    for (const engine of SEARCH_ENGINES) {
      const raw: Object | undefined = rec[engine.id];
      if (raw === undefined || typeof raw !== 'object' || Array.isArray(raw)) {
        continue;
      }
      const entry: Record<string, Object> = raw as Record<string, Object>;
      const baseUrl: Object | undefined = entry['baseUrl'];
      const hasKey: Object | undefined = entry['hasKey'];
      map.set(engine.id, {
        baseUrl: typeof baseUrl === 'string' ? (baseUrl as string) : '',
        hasKey: hasKey === true
      });
    }
  } catch (e) {
    // 坏 JSON 回空态（半写/手改脏值——禁静默失败口径的例外：配置面回默认可自愈，UI 重存即修复）
  }
  return map;
}

// 序列化伴生接口（ArkTS 对象字面量须显式类型——Record 直填字面量禁用，坑59① 家族）
interface EngineCfgItemJson {
  baseUrl: string;
  hasKey: boolean;
}

export function serializeEngineCfg(map: Map<string, EngineCfgEntry>): string {
  const rec: Record<string, Object> = {};
  map.forEach((entry: EngineCfgEntry, id: string): void => {
    const item: EngineCfgItemJson = { baseUrl: entry.baseUrl, hasKey: entry.hasKey };
    rec[id] = item as Object;
  });
  return JSON.stringify(rec);
}

// 生效 baseUrl：配置空串/缺条目 = 引擎默认（bing_local 默认 '' = 双入口现状语义）
export function effectiveBaseUrlOf(engineId: string, cfg: Map<string, EngineCfgEntry>): string {
  const desc: SearchEngineDescriptor | undefined = engineById(engineId);
  const entry: EngineCfgEntry | undefined = cfg.get(engineId);
  const custom: string = entry !== undefined ? entry.baseUrl.trim() : '';
  if (custom !== '') {
    return custom.replace(/\/+$/, '');
  }
  return desc !== undefined ? desc.defaultBaseUrl : '';
}

// 引擎当前是否「已配置可用」（免 key 引擎恒可用；需 key 引擎看 hasKey 标记——标记由
// 设置页保存/清除 key 时同步写，Asset 真值兜底在 dispatchSearch 取钥一步）
function engineReady(engine: SearchEngineDescriptor, cfg: Map<string, EngineCfgEntry>): boolean {
  if (!engine.requiresApiKey) {
    return true;
  }
  const entry: EngineCfgEntry | undefined = cfg.get(engine.id);
  return entry !== undefined && entry.hasKey;
}

// ── hasKey 按本机 Asset 真值回填（2026-09-10 方案-偏好与密钥接入备份 §4.5；导入链专用）──
// 背景：hasKey 是写偏好时的快照标记，而明文只在本机 Asset（IS_PERSISTENT = 同设备重装/
// 恢复天然还在）——备份包里的 hasKey 对「本机现在能不能搜」没有发言权（engineReady 只看
// 标记，标记 stale 会让可用引擎被静默跳过、设置页显示「未配置」与实情不符）。
// 回填口径：明文在 → hasKey true（含 cfg 里原本没有该条目的情形，补条目）；明文缺失 →
// false。同设备恢复 = 显示已配置且为真，换设备 = 未配置，两边自动正确且用户零重填。
// 纯函数面（sse-assert 54 组直跑）：本机真值经 hasPlaintext 回调注入，IO 在下方薄封装。
export function withAssetTruth(cfg: Map<string, EngineCfgEntry>,
  hasPlaintext: (engineId: string) => boolean): Map<string, EngineCfgEntry> {
  const out: Map<string, EngineCfgEntry> = new Map<string, EngineCfgEntry>();
  cfg.forEach((entry: EngineCfgEntry, id: string): void => {
    out.set(id, { baseUrl: entry.baseUrl, hasKey: entry.hasKey });
  });
  for (const engine of SEARCH_ENGINES) {
    if (!engine.requiresApiKey) {
      continue; // 免 key 引擎无 hasKey 语义
    }
    const present: boolean = hasPlaintext(engine.id);
    const cur: EngineCfgEntry | undefined = out.get(engine.id);
    if (cur === undefined) {
      if (present) {
        out.set(engine.id, { baseUrl: '', hasKey: true });
      }
      continue;
    }
    if (cur.hasKey !== present) {
      out.set(engine.id, { baseUrl: cur.baseUrl, hasKey: present });
    }
  }
  return out;
}

// 回填并落盘（导入链调用）：逐引擎探一次本机 Asset（需 key 引擎三条封顶的有界查询，非
// 轮询）。空表回写 ''（保持「未配置任何引擎」的注册默认形态，不留 '{}' 残迹）
export async function refreshEngineHasKeyFromAsset(): Promise<void> {
  const cfg: Map<string, EngineCfgEntry> = parseEngineCfg(getSearchEngineCfgJson());
  const presence: Map<string, boolean> = new Map<string, boolean>();
  for (const engine of SEARCH_ENGINES) {
    if (!engine.requiresApiKey) {
      continue;
    }
    presence.set(engine.id, (await loadSearchEngineKey(engine.id)) !== '');
  }
  const fixed: Map<string, EngineCfgEntry> = withAssetTruth(cfg,
    (engineId: string): boolean => presence.get(engineId) === true);
  AppStorage.setOrCreate<string>(PREF_SEARCH_ENGINE_CFG_KEY,
    fixed.size === 0 ? '' : serializeEngineCfg(fixed));
}

// fallback 解析链（Cube WebSearchService「至少一个可用」守卫同构）：当前引擎可用 →
// 启用清单按注册表序首个可用 → bing_local 终态兜底（用户显式全关也保底可搜——搜索是
// 基础能力，全关状态语义 = 「不再优先任何付费引擎」，不是「禁搜」；总开关才是禁搜闸）。
// enabledIds 里的未知 id 忽略（脏数据防御）
export function resolveEngineId(currentId: string, enabledIds: string[],
  cfg: Map<string, EngineCfgEntry>): string {
  const current: SearchEngineDescriptor | undefined = engineById(currentId);
  if (current !== undefined && current.canSearch && enabledIds.includes(current.id) &&
    engineReady(current, cfg)) {
    return current.id;
  }
  for (const engine of SEARCH_ENGINES) {
    if (engine.canSearch && enabledIds.includes(engine.id) && engineReady(engine, cfg)) {
      return engine.id;
    }
  }
  return 'bing_local';
}

// 按引擎取 handler（设置页「测试搜索」用——不经偏好 fallback 链，测用户点名的引擎；
// ctx 由调用方自组：key 可取 Asset 已存值、baseUrl 可取表单当前值，未保存也能测，
// KeyConnectTester「用当前表单值验证」同语义）
export function searchHandlerOf(engineId: string):
  ((query: string, ctx: SearchEngineRuntime) => Promise<WebSearchOutcome>) | undefined {
  return SEARCH_HANDLERS.get(engineId);
}

// ── 编排面（读偏好 → resolve → 取钥 → 分发；IO 面不进 node 断言）──

function failedOutcome(query: string, engineId: string, message: string): WebSearchOutcome {
  return { success: false, query: query, searchEngine: engineId,
    references: [], contentForAI: '', errorMessage: message };
}

// 搜索编排唯一入口（ToolTypes 执行器消费；设置页「测试搜索」另走 searchHandlerOf 直测
// 表单当前值——不经本函数的偏好 fallback 链）：总开关守卫 → resolve
// → 需 key 引擎取 Asset 明文（hasKey 标记与 Asset 真值不一致时以 Asset 为准——标记丢失
// 〔半写/手改偏好〕但明文在，搜索照常；明文缺失则明确报错并给配置路径，终态语义不重试）
export async function dispatchSearch(query: string): Promise<WebSearchOutcome> {
  if (!isSearchServiceEnabled()) {
    return failedOutcome(query, getSearchEngineId(),
      '联网搜索已关闭。请让用户在 设置 → 联网搜索 打开总开关后重试，本次不要重复搜索。');
  }
  // 偏好单次快照（两次现读间用户改配置会产生 engine/baseUrl 跨版本错配——一次解析贯传）
  const cfg: Map<string, EngineCfgEntry> = parseEngineCfg(getSearchEngineCfgJson());
  const engineId: string = resolveEngineId(getSearchEngineId(), getSearchEnabledEngineIds(), cfg);
  const desc: SearchEngineDescriptor | undefined = engineById(engineId);
  const handler: ((query: string, ctx: SearchEngineRuntime) => Promise<WebSearchOutcome>) | undefined =
    SEARCH_HANDLERS.get(engineId);
  if (desc === undefined || handler === undefined) {
    return failedOutcome(query, engineId, `搜索引擎 ${engineId} 不可用`);
  }
  // 搜索条数（2026-09-10 搜索条数助手级可调）：值经发送链中转键到达——搜索执行器接口
  // execute(argsJson) 无上下文、读不到助手行（机制与理由见 SearchLimits 头注释）。键缺失
  //（非会话路径调用：控制台助手等）/脏值 = 默认 5；换算收口在 resolveSearchResultCount
  const resultCount: number = resolveSearchResultCount(
    AppStorage.get<number>(CHAT_SEARCH_COUNT_KEY) ?? SEARCH_RESULT_COUNT_DEFAULT);
  const ctx: SearchEngineRuntime = {
    apiKey: '', baseUrl: effectiveBaseUrlOf(engineId, cfg), resultCount: resultCount
  };
  if (desc.requiresApiKey) {
    try {
      ctx.apiKey = await loadSearchEngineKey(engineId);
    } catch (e) {
      return failedOutcome(query, engineId,
        `${desc.label} 密钥读取失败：${(e as Error).message}`);
    }
    if (ctx.apiKey === '') {
      return failedOutcome(query, engineId,
        `${desc.label} API Key 未配置。请让用户在 设置 → 联网搜索 配置后重试，本次不要重复发起同义搜索。`);
    }
  }
  return handler(query, ctx);
}
