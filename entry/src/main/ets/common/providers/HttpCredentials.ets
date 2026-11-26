// HTTP 凭据域：按 owner 分组的「名称+私密值」凭据库解析与注入。owner = 助手 id（助手私有）
// 或 'global'（所有助手共享，决明拍板「全局凭据域」）；同名冲突**助手级优先**（更具体覆盖
// 更通用）。条目带可选 desc（上限 30 字，给助手看的备注，随 env_list 回执与编辑页可见，
// 不参与 {{名称}} 解析）。名称放开编辑（决明拍板，推翻原「创建后不可改」）：名称只是偏好
// JSON 元数据，值按 id 存 Asset，改名零 Asset 触碰；改名必须 invalidateCredCache(owner)
//（值缓存键是名称）；旧 {{旧名}} 引用走 missingCredErrorText 错误回执（附可用名单，模型
// 可自愈）。
// ★ 引用语法（模型面契约）：模型在 http_request 的 headers 值与 URL query 参数值里写
// {{名称}}，应用发出前替换真值；记号出现在 URL 路径段或 body = 违规（错误回执拦下——值只
// 允许进 header/query 两个 sink）。值**永不出现在对话**（工具回执会随对话发服务商，硬边界）：
// env_list 只返回名称清单，卡面/日志/落库/回执全程只见 {{名称}}（call.argsJson 原样不改 =
// 天然脱敏的前提）。
// ★ 明文红线（照搜索 key / 池条目同款）：值只进 Asset（KeyStore aic.h. 第六形态），偏好
// JSON 键 PREF_HTTP_CREDENTIALS_CFG_KEY 只存 {owner:[{id,name,hasValue}]}。
// ★ 结构纪律：纯函数区（上半，零 import 依赖、全参数化）导出供断言直跑副本执行级验证；
// 下半缓存与 Asset 组合区 import AppPreferences/KeyStore，断言副本剥 import 后不触达
//（模块级缓存惰性构造，顶层零求值——坑50 家族副本纪律，同 ToolHttp hostGate 惰性形制）。
import { getHttpCredentialsCfgJson, PREF_HTTP_CREDENTIALS_CFG_KEY } from '../AppPreferencesHttp';
import { HTTP_CRED_OWNER_GLOBAL, loadHttpCredential, removeHttpCredential,
  saveHttpCredential } from '../store/KeyStore';

// ── 纯函数区（断言直跑面）──

// 元数据条目（对应偏好 JSON 内一条）：id = Asset 别名尾段；name = 模型引用名（可改名——
// 纯元数据覆盖写，零 Asset 触碰）；hasValue = UI 标记（Asset 真值兜底，值缺失的条目不进
// 注入面）；desc = 用途说明可选项，不参与引用解析
export interface HttpCredEntry {
  id: string;
  name: string;
  hasValue: boolean;
  desc: string;
}

// owner → 条目列表（'' = 无任何配置）
export type HttpCredCfg = Map<string, HttpCredEntry[]>;

// 元数据解析（坏 JSON / 非对象 / 值非数组 / 条目缺字段一律容错丢弃，回空态可自愈——
// parseEngineCfg 同款口径：配置面回默认，UI 重存即修复）
export function parseHttpCredCfg(json: string): HttpCredCfg {
  const map: HttpCredCfg = new Map<string, HttpCredEntry[]>();
  if (json === '') {
    return map;
  }
  let rec: Record<string, Object> | null = null;
  try {
    const parsed: object = JSON.parse(json);
    rec = parsed as Record<string, Object>;
  } catch (e) {
    return map;
  }
  for (const owner of Object.keys(rec)) {
    const raw: Object | undefined = rec[owner];
    if (typeof raw !== 'object' || raw === null || !Array.isArray(raw)) {
      continue;
    }
    const entries: HttpCredEntry[] = [];
    for (const item of raw as Object[]) {
      if (typeof item !== 'object' || item === null) {
        continue;
      }
      const e: Record<string, Object> = item as Record<string, Object>;
      const id: Object = e['id'];
      const name: Object = e['name'];
      const hasValue: Object = e['hasValue'];
      const desc: Object = e['desc'];
      if (typeof id === 'string' && id !== '' && typeof name === 'string' &&
        name !== '' && typeof hasValue === 'boolean') {
        // desc 可选（2026-10-07 前的旧 JSON 无此字段——容错回空串，向后兼容）
        entries.push({ id: id, name: name, hasValue: hasValue,
          desc: typeof desc === 'string' ? desc : '' });
      }
    }
    if (entries.length > 0) {
      map.set(owner, entries);
    }
  }
  return map;
}

// 序列化伴生接口（ArkTS 对象字面量须显式类型——坑59① 家族）
interface HttpCredEntryJson {
  id: string;
  name: string;
  hasValue: boolean;
  desc: string;
}

// 元数据序列化（整键覆盖写；空 Map 序列化为 '{}' = 全默认态；desc 恒写含空串——字段
// 全量落盘，读取侧免二次判型）
export function serializeHttpCredCfg(map: HttpCredCfg): string {
  const rec: Record<string, Object> = {};
  map.forEach((entries: HttpCredEntry[], owner: string): void => {
    const arr: Object[] = [];
    for (const e of entries) {
      const item: HttpCredEntryJson =
        { id: e.id, name: e.name, hasValue: e.hasValue, desc: e.desc };
      arr.push(item as Object);
    }
    rec[owner] = arr as Object;
  });
  return JSON.stringify(rec);
}

// 某 owner 的名称清单（env_list 回执与错误回执附单共用；无条目回 []）
export function credNamesOf(cfg: HttpCredCfg, owner: string): string[] {
  const entries: HttpCredEntry[] | undefined = cfg.get(owner);
  const names: string[] = [];
  if (entries !== undefined) {
    for (const e of entries) {
      names.push(e.name);
    }
  }
  return names;
}

// 名称占用判定（新建时的唯一性校验——同 owner 内名称是引用键，禁重复）
export function credNameTaken(cfg: HttpCredCfg, owner: string, name: string): boolean {
  return credNamesOf(cfg, owner).includes(name);
}

// 名称占用判定·改名用：编辑态排除自身 id 后再判——名称允许原值不变保存（只改值/说明时
// 查重不得自拦）
export function credNameTakenExcept(cfg: HttpCredCfg, owner: string, name: string,
  excludeId: string): boolean {
  const entries: HttpCredEntry[] | undefined = cfg.get(owner);
  if (entries === undefined) {
    return false;
  }
  return entries.some((e: HttpCredEntry): boolean => e.id !== excludeId && e.name === name);
}

// 名称上限（照 KNOWLEDGE_TITLE_MAX = 50 同档）：名称进 env_list 回执与错误回执文本（随
// 对话发服务商），无界名称可撑破工具回执 8192 预算；UI maxLength 与本常量单源
export const HTTP_CRED_NAME_MAX_CHARS: number = 50;

// 值上限（依据 = 官方 asset-js-add「SECRET 长度 1-1024 字节」）：maxLength 按 ASCII 1:1
// 取同值；多字节字符按 3 字节/字折算超限时 Asset add 抛错，由 UI 保存失败 toast 兜底
export const HTTP_CRED_VALUE_MAX_CHARS: number = 1024;

// 每 owner（全局 / 单个助手）凭据条数上限（决明拍板 50）：回执与附单随对话发服务商，
// 条数×名称长收在工具回执 8192 预算内；凭据无工具写入面、备份回填不新增条目，UI 添加闸
// 即全集
export const HTTP_CRED_MAX_PER_OWNER: number = 50;

// 用途说明上限（决明拍板 30 字）：可选字段随 env_list 回执发服务商，50 条 ×（名称 50 +
// 说明 30 + JSON 结构开销）≈ 5500 字符仍在回执 8192 预算内；UI maxLength 与本常量单源
export const HTTP_CRED_DESC_MAX_CHARS: number = 30;

// 用途说明合法性（可选字段：trim 后非空才有限长意义，空串 = 未填恒合法；说明不参与
// {{名称}} 解析，无花括号限制。UI 与断言直跑共用本函数）
export function credDescValid(desc: string): boolean {
  const trimmed: string = desc.trim();
  return trimmed === '' || trimmed.length <= HTTP_CRED_DESC_MAX_CHARS;
}

// 名称合法性（引用记号语法前提：非空、不含花括号〔破坏 {{名称}} 解析〕、长度上限；
// 唯一性另行 credNameTaken 判——UI 与断言直跑共用本函数）
export function credNameValid(name: string): boolean {
  return name !== '' && name.length <= HTTP_CRED_NAME_MAX_CHARS &&
    !name.includes('{') && !name.includes('}');
}

// ── 记号语法（{{名称}}；手写 indexOf 扫描——不依赖正则全局态，边界与替换实现共享同
// 一套「开-闭配对」语义，两处判据不漂移）──

// 提取文本里的全部记号名称（去重保序；空名与未闭合不产出）
export function extractCredRefs(text: string): string[] {
  const names: string[] = [];
  let idx: number = 0;
  while (true) {
    const open: number = text.indexOf('{{', idx);
    if (open < 0) {
      break;
    }
    const close: number = text.indexOf('}}', open + 2);
    if (close < 0) {
      break;
    }
    const name: string = text.substring(open + 2, close).trim();
    if (name !== '' && !names.includes(name)) {
      names.push(name);
    }
    idx = close + 2;
  }
  return names;
}

// 替换结果（missing = resolve 不到的名称——记号原样保留，调用方整体转错误回执禁发）
export interface CredReplaceOutcome {
  text: string;
  missing: string[];
}

// 替换文本内全部记号（resolver 返回 null = 未知名，原样保留并登记——错误路径可组合，
// 调用方拿到 missing 非空即整体拦下）
export function replaceCredRefsInText(text: string,
  resolve: (name: string) => string | null): CredReplaceOutcome {
  let out: string = '';
  let idx: number = 0;
  const missing: string[] = [];
  while (true) {
    const open: number = text.indexOf('{{', idx);
    if (open < 0) {
      out += text.substring(idx);
      break;
    }
    const close: number = text.indexOf('}}', open + 2);
    if (close < 0) {
      out += text.substring(idx);
      break;
    }
    const name: string = text.substring(open + 2, close).trim();
    const value: string | null = name === '' ? null : resolve(name);
    if (value === null) {
      out += text.substring(idx, close + 2);
      if (name !== '' && !missing.includes(name)) {
        missing.push(name);
      }
    } else {
      out += text.substring(idx, open) + value;
    }
    idx = close + 2;
  }
  const outcome: CredReplaceOutcome = { text: out, missing: missing };
  return outcome;
}

// URL 切分 [问号前, 问号后]（无 '?' 或 '?' 在 '#' 后 = 整串在前段——记号只允许出现在
// query 段的参数值里，路径段出现即违规）
export function splitUrlQuery(url: string): string[] {
  const q: number = url.indexOf('?');
  if (q < 0) {
    return [url, ''];
  }
  const hash: number = url.indexOf('#');
  if (hash >= 0 && hash < q) {
    return [url, ''];
  }
  return [url.substring(0, q), url.substring(q + 1)];
}

// 位置白名单违规扫描：URL 路径段与 body 里出现的记号 = 违规（返回去重名称清单，空 = 合法）
export function credRefsOutsideAllowedPlaces(url: string, body: string): string[] {
  const parts: string[] = splitUrlQuery(url);
  const bad: string[] = [];
  for (const n of extractCredRefs(parts[0])) {
    if (!bad.includes(n)) {
      bad.push(n);
    }
  }
  for (const n of extractCredRefs(body)) {
    if (!bad.includes(n)) {
      bad.push(n);
    }
  }
  return bad;
}

// 两级解析器（助手级优先于全局——同名时更具体的命名空间赢；UI 的{{名称}}解析与
// httpRequestRaw 传输层替换共用本函数产出）
export function makeCredResolver(assistantOwned: Map<string, string>,
  globalOwned: Map<string, string>): (name: string) => string | null {
  return (name: string): string | null => {
    const own: string | undefined = assistantOwned.get(name);
    if (own !== undefined) {
      return own;
    }
    const shared: string | undefined = globalOwned.get(name);
    return shared === undefined ? null : shared;
  };
}

// 未配置凭据错误文本（错误回执给模型：点名缺失名 + 附可用清单——省一轮 env_list 往返；
// 清单只含名称，值级信息零出现）
export function missingCredErrorText(missing: string[], assistantNames: string[],
  globalNames: string[]): string {
  let text: string = '凭据 ' + missing.join('、') + ' 未配置。';
  const known: string[] = assistantNames.concat(globalNames);
  if (known.length === 0) {
    text += '当前没有已配置的凭据。请让用户在设置中添加，或去掉请求里的凭据引用。';
  } else {
    text += '可用凭据名：' + known.join('、') + '。也可调用 env_list 查询。';
  }
  return text;
}

// 记号违规错误文本（路径段/body 引用 → 指引改放 header/query）
export function credRefMisplacedErrorText(names: string[]): string {
  return '凭据引用 ' + names.join('、') +
    ' 只能放在请求头的值或 URL 查询参数的值里。请勿放在网址路径或请求体中。';
}

// ── 缓存与 Asset 组合区（断言副本不触达；模块级缓存惰性构造——顶层零求值）──
// 缓存 = owner → (name → value)。请求链上禁逐条 await Asset（代理密码族同款纪律），miss
// 时一次批量装载后常驻；UI 写点经 invalidateCredCache(owner) 失效重装（懒加载 = 启动零
// 成本，未配凭据的设备永不装载）
let credValueCache: Map<string, Map<string, string>> | null = null;

function credCache(): Map<string, Map<string, string>> {
  if (credValueCache === null) {
    credValueCache = new Map<string, Map<string, string>>();
  }
  return credValueCache;
}

// owner → 缓存代际号：invalidateCredCache 每次失效自增。装载飞行期间到达的 invalidate
// 原是 no-op（缓存键尚不存在，delete 落空），装载完成若无比对会把飞行前的陈旧快照写回——
// 实害如装载中删除的凭据值在缓存存活期仍可注入（删除泄露 key 的安全意图被静默违背）。
// credentialValuesOf 装载开始记代际、完成 set 前比对，不一致即弃写（本次调用照回飞行前
// 快照——请求已在途；下一次调用经 miss 重装载到新态）。模块级惰性构造（顶层零求值——
// 坑50 家族副本纪律）
let credCacheEpoch: Map<string, number> | null = null;

function currentCredEpoch(owner: string): number {
  return credCacheEpoch === null ? 0 : (credCacheEpoch.get(owner) ?? 0);
}

function bumpCredEpoch(owner: string): void {
  if (credCacheEpoch === null) {
    credCacheEpoch = new Map<string, number>();
  }
  credCacheEpoch.set(owner, (credCacheEpoch.get(owner) ?? 0) + 1);
}

// owner 的名称→值映射（miss 时按元数据逐条读 Asset 装载；Asset 缺失的条目跳过——
// hasValue 标记与真值脱钩时以真值为准，缺失条目不进注入面）
export async function credentialValuesOf(owner: string): Promise<Map<string, string>> {
  const cached: Map<string, string> | undefined = credCache().get(owner);
  if (cached !== undefined) {
    return cached;
  }
  const epoch: number = currentCredEpoch(owner);
  const cfg: HttpCredCfg = parseHttpCredCfg(getHttpCredentialsCfgJson());
  const entries: HttpCredEntry[] | undefined = cfg.get(owner);
  const values: Map<string, string> = new Map<string, string>();
  if (entries !== undefined) {
    for (const e of entries) {
      const value: string = await loadHttpCredential(owner, e.id);
      if (value !== '') {
        values.set(e.name, value);
      }
    }
  }
  // 装载期间未发生失效才落缓存；代际不一致 = 飞行中有 UI 写点已失效，弃写陈旧快照
  if (currentCredEpoch(owner) === epoch) {
    credCache().set(owner, values);
  }
  return values;
}

// 缓存失效（UI 写点调用；删 owner 传整个键移除）。代际自增同时作废飞行中的装载（键不
// 存在时 delete 落空，装载完成后靠代际比对弃写；缓存未构造则不可能有装载在飞，代际无需
// 自增）
export function invalidateCredCache(owner: string): void {
  if (credValueCache !== null) {
    credValueCache.delete(owner);
    bumpCredEpoch(owner);
  }
}

// 元数据读-改-写封装（禁裸 JSON.parse 散落消费方——AppPreferences 立规；AppStorage 整键
// 覆盖写）。upsert 新建（hasValue 恒 true——Asset 与元数据同笔写入）；remove 删除；
// update 改名/改说明（hasValue 原值保留）
export function upsertCredMeta(owner: string, id: string, name: string, desc: string): void {
  const cfg: HttpCredCfg = parseHttpCredCfg(getHttpCredentialsCfgJson());
  const entries: HttpCredEntry[] = cfg.get(owner) ?? [];
  entries.push({ id: id, name: name, hasValue: true, desc: desc });
  cfg.set(owner, entries);
  AppStorage.setOrCreate<string>(PREF_HTTP_CREDENTIALS_CFG_KEY, serializeHttpCredCfg(cfg));
}

// 元数据原位更新（改名/改说明；Asset 值零触碰）。**调用方必须经 editCredential 走统一缓存
// 失效**——名称是值缓存键，改名后旧键残留会让旧 {{名}} 仍可解析、新名解析不到；禁直调本
// 函数后自写失效的路径
export function updateCredMeta(owner: string, id: string, name: string, desc: string): void {
  const cfg: HttpCredCfg = parseHttpCredCfg(getHttpCredentialsCfgJson());
  const entries: HttpCredEntry[] | undefined = cfg.get(owner);
  if (entries === undefined) {
    return;
  }
  let changed: boolean = false;
  for (let i: number = 0; i < entries.length; i++) {
    if (entries[i].id === id) {
      entries[i] = { id: id, name: name, hasValue: entries[i].hasValue, desc: desc };
      changed = true;
      break;
    }
  }
  if (!changed) {
    return;
  }
  cfg.set(owner, entries);
  AppStorage.setOrCreate<string>(PREF_HTTP_CREDENTIALS_CFG_KEY, serializeHttpCredCfg(cfg));
}

export function removeCredMeta(owner: string, id: string): void {
  const cfg: HttpCredCfg = parseHttpCredCfg(getHttpCredentialsCfgJson());
  const entries: HttpCredEntry[] | undefined = cfg.get(owner);
  if (entries === undefined) {
    return;
  }
  const kept: HttpCredEntry[] = [];
  for (const e of entries) {
    if (e.id !== id) {
      kept.push(e);
    }
  }
  if (kept.length === 0) {
    cfg.delete(owner);
  } else {
    cfg.set(owner, kept);
  }
  AppStorage.setOrCreate<string>(PREF_HTTP_CREDENTIALS_CFG_KEY, serializeHttpCredCfg(cfg));
}

// UI 组合操作（Asset 与元数据同笔成对 + 缓存失效；调用方先做名称唯一性与非空校验）
export async function addCredential(owner: string, id: string, name: string, desc: string,
  value: string): Promise<void> {
  await saveHttpCredential(owner, id, value);
  upsertCredMeta(owner, id, name, desc);
  invalidateCredCache(owner);
}

// 编辑组合操作：value 非空 = 值与元数据同笔更新；value 空 = 仅元数据（改名/改说明，Asset
// 原明文零触碰）。统一失效原因同 updateCredMeta 注——名称是值缓存键
export async function editCredential(owner: string, id: string, name: string, desc: string,
  value: string): Promise<void> {
  if (value !== '') {
    await saveHttpCredential(owner, id, value);
  }
  updateCredMeta(owner, id, name, desc);
  invalidateCredCache(owner);
}

export async function deleteCredential(owner: string, id: string): Promise<void> {
  await removeHttpCredential(owner, id);
  removeCredMeta(owner, id);
  invalidateCredCache(owner);
}

// ── 删助手级联三件（AssistantDb.deleteAssistantCascade 消费；时序铁律 = 串行链内事务前
// 快照 id、commit 后删元数据与 Asset 同区——★ 偏好不参与 RDB 事务，事务内写遇回滚无法
// 同步回滚 = 半删态，元数据删除已移出事务）──

// 取 owner 的条目 id 清单（事务前快照——Asset 侧按名逐条删，Asset 无前缀查询）
export function credIdsOf(owner: string): string[] {
  const cfg: HttpCredCfg = parseHttpCredCfg(getHttpCredentialsCfgJson());
  const entries: HttpCredEntry[] | undefined = cfg.get(owner);
  const ids: string[] = [];
  if (entries !== undefined) {
    for (const e of entries) {
      ids.push(e.id);
    }
  }
  return ids;
}

// 删整个 owner 的元数据键（commit 后调用——★ 已移出 RDB 事务：偏好写不参与事务回滚，
// 留事务内会产生半删态；owner 键整体移除——助手行已随之删除）
export function removeCredOwnerMeta(owner: string): void {
  const cfg: HttpCredCfg = parseHttpCredCfg(getHttpCredentialsCfgJson());
  if (cfg.delete(owner)) {
    AppStorage.setOrCreate<string>(PREF_HTTP_CREDENTIALS_CFG_KEY, serializeHttpCredCfg(cfg));
  }
}

// commit 后清 owner 全部 Asset 条目并失效缓存（credIds = 事务前 credIdsOf 快照；
// 逐条删失败上抛——级联失败要让调用方可见，静默漏删 = 跨卸载残留的明文孤儿）
export async function purgeOwnerAssets(owner: string, credIds: string[]): Promise<void> {
  for (const credId of credIds) {
    await removeHttpCredential(owner, credId);
  }
  invalidateCredCache(owner);
}

// env_list 回执条目（名称 + 用途说明；说明未填为空串——模型侧统一结构，不做字段裁剪）
export interface EnvCredItem {
  name: string;
  desc: string;
}

// env_list 回执数据（assistantId = '' 时助手组为空——系统作用域调用只看全局；条目含 desc
// 用途说明，值级信息零出现不变）
export interface EnvCredGroups {
  global: EnvCredItem[];
  assistant: EnvCredItem[];
}

// 函数名保留「NameGroups」为断言锚不漂移（产出已改带说明条目组——见 EnvCredGroups 注）
export function credentialNameGroups(assistantId: string): EnvCredGroups {
  const cfg: HttpCredCfg = parseHttpCredCfg(getHttpCredentialsCfgJson());
  const toItems = (entries: HttpCredEntry[] | undefined): EnvCredItem[] => {
    const items: EnvCredItem[] = [];
    if (entries !== undefined) {
      for (const e of entries) {
        items.push({ name: e.name, desc: e.desc });
      }
    }
    return items;
  };
  const groups: EnvCredGroups = {
    global: toItems(cfg.get(HTTP_CRED_OWNER_GLOBAL)),
    assistant: assistantId === '' ? [] : toItems(cfg.get(assistantId))
  };
  return groups;
}

// 凭据管理页 push 参数：owner = 'global' 或助手 id；readOnly = true = 助手编辑页入口的
// **只读清单**（新增/编辑/删除只在设置侧「HTTP 请求 → HTTP 凭据」总览页入口）。载体放
// 本域而非页面文件 = 生产方与消费方跨 components 子目录，单源在公共域免组件件互引；
// 字符串形态仍兼容（旧调用 = 可管理，与 MemoryEditParam 双形态同姿势）
export interface HttpCredManageParam {
  owner: string;
  readOnly: boolean;
}
