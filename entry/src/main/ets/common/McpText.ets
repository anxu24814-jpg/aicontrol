// MCP 文本纯函数域（照 SkillText / KnowledgeText 家族立件）：MCP 服务器域全部纯逻辑——
// 助手绑定清单解析与序列化 / 工具缓存 JSON 对 / 请求头元数据 JSON 对 / 服务器名校验 /
// 三段工具名拼装与 provider 合规校验。
// **零 import 纯函数约束**（坑50：McpDb / McpTools / McpClient / 页面均引本件，本件不引
// 任何件；scripts/assert-tool-domain.mjs 复制本件为 .ts 直跑）。IO 编排（DB 读写 / Asset
// 存取 / 网络同步）在 McpDb.ets / KeyStore.ets / McpClient.ets，不在本域。
//
// ★ 与 skills / knowledge / tools 三列的语义分界（最易被后人按错口径改坏的一点）：
// assistants.mcpServers 的 ''（含坏 JSON）= **空集合** = 不启用任何 MCP 服务器——语义照
// skills / knowledge，与 tools 的「'' = 默认集合」相反，**禁合并复用**（四列各留一份 =
// 有意为之，不是重复代码）。
//
// ★ 密钥红线（负向钉，代码与断言双声明）：本域一切函数**永不接触请求头明文值**——
// headersJson 元数据只有名称与 hasValue 标记，值明文只在 Asset（KeyStore 分流）。

// ── 上限常量族（方案 §2.1 拍板值；数据有界红线）──
// 服务器上限（达限抛中文错 P0-1 不静默；8 × 32 = 256 自然封顶工具注入面，按助手绑定再收敛）
export const MCP_SERVERS_MAX: number = 8;
// 单服务器工具缓存上限（tools/list 超限 = 同步失败报中文错「工具数超过上限」，不静默截断）
export const MCP_TOOLS_CACHE_MAX: number = 32;
// 请求头行数上限（B5 编辑页表单闸同源；KeyStore 组级先删后加按本值区间扫尾）
export const MCP_HEADERS_MAX: number = 5;

// 三段工具名前缀（'mcp__<服务器名>__<工具名>'——多服务器冲突靠服务器名前缀隔离；模型面
// 与执行面全链只认该前缀判 MCP 归属）
export const MCP_TOOL_NAME_PREFIX: string = 'mcp__';

// ── 助手绑定清单（assistants.mcpServers 列 JSON 串 ⇄ 服务器 id 数组；DB v59）──
// '' / 坏 JSON / 非数组 → **空数组**（= 不启用任何服务器，与 tools 列语义相反，见头注释）；
// 只收非空字符串项并去重；未知 id 容忍（读取侧「启用 ∩ 现存」过滤是第二道保险，本层不查库）
export function parseEnabledMcpServerIds(json: string): string[] {
  if (json === '') {
    return [];
  }
  let raw: object[] | null = null;
  try {
    const parsed: object = JSON.parse(json);
    raw = Array.isArray(parsed) ? parsed as object[] : null;
  } catch (e) {
    return [];
  }
  if (raw === null) {
    return [];
  }
  const ids: string[] = [];
  for (const item of raw) {
    if (typeof item === 'string' && item !== '' && !ids.includes(item)) {
      ids.push(item);
    }
  }
  return ids;
}

// id 数组 → 列 JSON 串：空集合落 ''（库列默认形态 = 零勾选，新建助手零配置零写入）
export function serializeEnabledMcpServerIds(ids: string[]): string {
  if (ids.length === 0) {
    return '';
  }
  return JSON.stringify(ids);
}

// ── 认证方式取值域与归一（mcp_servers.authKind 列）──
// 四档：'none' 无需认证 / 'bearer' / 'apiKey' / 'custom'（存量默认）。底层链路零分叉——
// 后三档保存时均由编辑页组装为请求头组（headersJson + Asset），本列只标记「如何组装」。
// normalize 为数据层脏值防御（未知值一律归 'custom'——回填现行自定义头组形态，不产生未定义档）
export const MCP_AUTH_NONE: string = 'none';
export const MCP_AUTH_BEARER: string = 'bearer';
export const MCP_AUTH_API_KEY: string = 'apiKey';
export const MCP_AUTH_CUSTOM: string = 'custom';

export function normalizeMcpAuthKind(kind: string): string {
  if (kind === MCP_AUTH_NONE || kind === MCP_AUTH_BEARER || kind === MCP_AUTH_API_KEY) {
    return kind;
  }
  return MCP_AUTH_CUSTOM;
}

// ── 工具缓存（mcp_servers.toolsJson 列 JSON 串 ⇄ 缓存项数组）──
// 缓存项 = tools/list 结果映射的三字段 + 单工具启停位 enabled；inputSchema 恒为 $ref 展开
// 态（展开函数 = 本件 inlineRefExpansion，本层只透传原串）。'' / 坏 JSON / 非数组 → 空数组
//（该服务器无缓存，调用方按「未同步」处理）；条目缺 name 或非对象丢弃；**enabled 缺字段
// = true**（存量缓存免迁移——宽容解析单点）。McpToolInput = 新鲜清单的宽松输入面（enabled
// 可选）——零 import 不引 McpRpc.McpListedTool，结构同构直接互认
export interface McpToolInput {
  name: string;
  description: string;
  inputSchema: string;
  enabled?: boolean;
}

export interface McpToolCacheItem {
  name: string;
  description: string;
  inputSchema: string;
  enabled: boolean;
}

export function parseMcpToolCache(json: string): McpToolCacheItem[] {
  if (json === '') {
    return [];
  }
  let raw: object[] | null = null;
  try {
    const parsed: object = JSON.parse(json);
    raw = Array.isArray(parsed) ? parsed as object[] : null;
  } catch (e) {
    return [];
  }
  if (raw === null) {
    return [];
  }
  const items: McpToolCacheItem[] = [];
  for (const item of raw) {
    if (item === null || typeof item !== 'object' || Array.isArray(item)) {
      continue;
    }
    const rec: Record<string, Object> = item as Record<string, Object>;
    const name: Object | undefined = rec['name'];
    const description: Object | undefined = rec['description'];
    const inputSchema: Object | undefined = rec['inputSchema'];
    const enabled: Object | undefined = rec['enabled'];
    if (typeof name !== 'string' || name === '') {
      continue;
    }
    items.push({
      name: name,
      description: typeof description === 'string' ? description : '',
      inputSchema: typeof inputSchema === 'string' ? inputSchema : '',
      enabled: typeof enabled === 'boolean' ? enabled : true
    });
  }
  return items;
}

export function serializeMcpToolCache(items: McpToolCacheItem[]): string {
  return JSON.stringify(items);
}

// 刷新合并（逐工具启停不在刷新时被重置）：按 name 保留旧缓存的用户开关，新工具默认 true，
// 消失的工具自然淘汰。O(旧×新) 双循环——两侧均有界（≤32），零 import 不引 Map。现消费点 =
// 编辑页保存自动测连 / 管理页行卡同步两处写点；后续新增 toolsJson 整表替换写点须同笔接本函数
export function mergeMcpToolEnablement(oldCache: McpToolCacheItem[],
  freshTools: McpToolInput[]): McpToolCacheItem[] {
  const merged: McpToolCacheItem[] = [];
  for (const fresh of freshTools) {
    let enabled: boolean = true;
    for (const old of oldCache) {
      if (old.name === fresh.name) {
        enabled = old.enabled;
        break;
      }
    }
    merged.push({
      name: fresh.name,
      description: fresh.description,
      inputSchema: fresh.inputSchema,
      enabled: enabled
    });
  }
  return merged;
}

// ── 请求头元数据（mcp_servers.headersJson 列 JSON 串 ⇄ 元数据数组）──
// 元数据 = 名称 + hasValue 两字段——★ 值明文恒不在场（Asset 分流，见头注释密钥红线）。
// '' / 坏 JSON / 非数组 → 空数组；条目缺 name 丢弃；hasValue 非 true 归 false
export interface McpHeaderMetaItem {
  name: string;
  hasValue: boolean;
}

export function parseMcpHeaderMeta(json: string): McpHeaderMetaItem[] {
  if (json === '') {
    return [];
  }
  let raw: object[] | null = null;
  try {
    const parsed: object = JSON.parse(json);
    raw = Array.isArray(parsed) ? parsed as object[] : null;
  } catch (e) {
    return [];
  }
  if (raw === null) {
    return [];
  }
  const items: McpHeaderMetaItem[] = [];
  for (const item of raw) {
    if (item === null || typeof item !== 'object' || Array.isArray(item)) {
      continue;
    }
    const rec: Record<string, Object> = item as Record<string, Object>;
    const name: Object | undefined = rec['name'];
    if (typeof name !== 'string' || name === '') {
      continue;
    }
    items.push({ name: name, hasValue: rec['hasValue'] === true });
  }
  return items;
}

export function serializeMcpHeaderMeta(items: McpHeaderMetaItem[]): string {
  return JSON.stringify(items);
}

// ── 服务器名与三段工具名 ──
// 服务器名合法判据：^[A-Za-z0-9]+$（非空且仅字母数字）——名称同时是三段工具名前缀段，
// 字符集受限防拼出非法工具名（编辑页实时校验 + McpDb 增改闸 + 同步期兜底三道共用本判据源）
export function isValidMcpServerName(name: string): boolean {
  if (name === '') {
    return false;
  }
  for (let i: number = 0; i < name.length; i++) {
    const c: string = name.charAt(i);
    const isLower: boolean = c >= 'a' && c <= 'z';
    const isUpper: boolean = c >= 'A' && c <= 'Z';
    const isDigit: boolean = c >= '0' && c <= '9';
    if (!(isLower || isUpper || isDigit)) {
      return false;
    }
  }
  return true;
}

// 三段名拼装（'mcp__<服务器名>__<工具名>'）：多服务器工具名冲突的隔离键。调用方保证服务器名
// 已过校验（执行与闸判定不靠名字反解——executor 直持三元组；显示面反解用对偶 serverNameOfMcpToolName）
export function mcpToolNameOf(serverName: string, toolName: string): string {
  return MCP_TOOL_NAME_PREFIX + serverName + '__' + toolName;
}

// 三段名前缀判据（注册表注册/注销面按前缀识别 MCP 域条目；不反解段内容）
export function isMcpToolName(name: string): boolean {
  return name.startsWith(MCP_TOOL_NAME_PREFIX);
}

// 三段名反解（**mcpToolNameOf 的对偶**）：去 'mcp__' 前缀后取首个 '__' 前段 = 服务器名段。
// 服务器名纯字母数字（isValidMcpServerName 单源，不含下划线），首个 '__' 必是服务器名与
// 工具名的分隔、反解无歧义；未命中 '__' 的非完整三段名回余段整段（容错不报错）。
// **仅显示面消费**（用量面板「工具·MCP·<服务器名>」分组），不参与任何闸判定——执行面
// 直持三元组；预算域 ToolLimits 另有同式私判（零 import 复制面纪律），
// 同值关系由 assert-ctx-usage 直跑钉守
export function serverNameOfMcpToolName(name: string): string {
  const rest: string = name.startsWith(MCP_TOOL_NAME_PREFIX) ?
    name.substring(MCP_TOOL_NAME_PREFIX.length) : name;
  const sep: number = rest.indexOf('__');
  return sep >= 0 ? rest.substring(0, sep) : rest;
}

// 三段注册名的 provider 合规判据：注册名会原样下发为 provider 的 function name——OpenAI
// 兼容口约束 ^[A-Za-z0-9_-]{1,64}$（Gemini 口另要求首字符字母/下划线；'mcp__' 前缀恒字母
// 开头，同一判据覆盖两口径）。不合规名字会让 provider 拒整个 tools 声明请求（400 整轮），
// 故同步期注册前必须跳过并回写服务器 lastError（不静默）。入参 = mcpToolNameOf 拼装后的
// 完整三段名，不是服务器返回的原工具名
export const MCP_PROVIDER_TOOL_NAME_MAX: number = 64;

export function isValidMcpProviderToolName(name: string): boolean {
  if (name === '' || name.length > MCP_PROVIDER_TOOL_NAME_MAX) {
    return false;
  }
  for (let i: number = 0; i < name.length; i++) {
    const c: string = name.charAt(i);
    const isLower: boolean = c >= 'a' && c <= 'z';
    const isUpper: boolean = c >= 'A' && c <= 'Z';
    const isDigit: boolean = c >= '0' && c <= '9';
    const isUnder: boolean = c === '_';
    const isDash: boolean = c === '-';
    if (!(isLower || isUpper || isDigit || isUnder || isDash)) {
      return false;
    }
  }
  return true;
}

// ── 工具结果截断 ──
// 网页抓取/代码库类工具单次输出可远超上下文预算——超上限截为预览段 + 截断标记（模型可感知
// 被截、换窄化参数重调）；限内原样（含空串）。两常量即截断契约（32K 上限 / 4K 预览），
// 消费点 = McpToolExecutor 回填前（McpTools.ets），不在此触碰任何 IO
export const MCP_TOOL_RESULT_MAX_CHARS: number = 32000;
export const MCP_TOOL_RESULT_PREVIEW_CHARS: number = 4096;

export function truncateToolResult(text: string): string {
  if (text.length <= MCP_TOOL_RESULT_MAX_CHARS) {
    return text;
  }
  return text.substring(0, MCP_TOOL_RESULT_PREVIEW_CHARS) +
    '\n[工具输出超过 ' + MCP_TOOL_RESULT_MAX_CHARS + ' 字符，已截断，此处仅保留前 ' +
    MCP_TOOL_RESULT_PREVIEW_CHARS + ' 字符预览]';
}

// ── schema $ref 递归内联展开 ──
// MCP 工具 inputSchema 可含 $defs + '#/$defs/…' 文档内引用；部分模型口（Gemini 原生）拒
// 悬空 $ref 会 400 整请求——同步落缓存前把 $ref 递归内联为扁平 schema（缓存里的
// inputSchema 恒为展开态）。三规则：循环引用处只留 type；无法解析的引用（外部 ref / $defs
// 无该定义 / 超深）退化为不限类型空对象；只沿 schema 承载关键字遍历（字面量字段原样保留）。
// '' 与坏 JSON 原样返回（注册面按空 schema 兜底）。消费点 = tools/list 结果 → 缓存落库的映射处
const MCP_REF_DEF_HOLDERS: string[] = ['$defs', 'definitions'];
const MCP_REF_PREFIXES: string[] = ['#/$defs/', '#/definitions/'];
// 对象字典位（键 = 属性名原样、值 = schema 递归）
const MCP_REF_CARRY_DICT_KEYS: string[] = ['properties', 'patternProperties'];
// schema 数组位（逐项递归）
const MCP_REF_CARRY_ARRAY_KEYS: string[] = ['allOf', 'anyOf', 'oneOf', 'prefixItems'];
// schema 单值位（对象即递归；additionalProperties 兼布尔原样）
const MCP_REF_CARRY_SINGLE_KEYS: string[] = ['items', 'additionalProperties', 'not',
  'contains', 'propertyNames'];
// 递归深度上限（防恶意/异常超深 schema——超深按「无法解析」退化不限类型）
const MCP_REF_DEPTH_MAX: number = 100;

// JSON pointer 段名转义还原（RFC 6901：~1 = /、~0 = ~）
function mcpUnescapeRefToken(token: string): string {
  return token.replace(/~1/g, '/').replace(/~0/g, '~');
}

// $defs 与 draft-07 旧位 definitions 两处定义合并收集（同名以 $defs 优先——位序后扫胜出）
function mcpCollectDefs(root: Record<string, Object>): Record<string, Object> {
  const defs: Record<string, Object> = {};
  for (const holder of MCP_REF_DEF_HOLDERS) {
    const val: Object | undefined = root[holder];
    if (val !== undefined && val !== null && typeof val === 'object' && !Array.isArray(val)) {
      const rec: Record<string, Object> = val as Record<string, Object>;
      for (const key of Object.keys(rec)) {
        defs[key] = rec[key];
      }
    }
  }
  return defs;
}

// 引用目标段名：只认文档内 '#/$defs/<名>' 与 '#/definitions/<名>' 单段形态；其余（外部
// URL / 多级指针）回 '' 由调用方按无法解析退化
function mcpRefTargetOf(ref: string): string {
  for (const prefix of MCP_REF_PREFIXES) {
    if (ref.startsWith(prefix)) {
      return mcpUnescapeRefToken(ref.substring(prefix.length));
    }
  }
  return '';
}

// 递归展开单值：字典位沿属性名逐值递归、数组位逐项递归、单值位对象递归、字面量原样；
// $ref 整对象替换为定义展开产物（2020-12 前 $ref 兄弟字段本就被忽略，替换语义与规范一致）
function mcpExpandValue(value: Object | undefined, defs: Record<string, Object>,
  stack: string[], depth: number): Object | undefined {
  if (depth > MCP_REF_DEPTH_MAX) {
    const over: Record<string, Object> = {};
    return over;
  }
  if (value === undefined || value === null || typeof value !== 'object') {
    return value;
  }
  if (Array.isArray(value)) {
    const arr: (Object | null)[] = [];
    for (const item of value as Object[]) {
      const expanded: Object | undefined = mcpExpandValue(item, defs, stack, depth);
      if (expanded !== undefined) {
        arr.push(expanded);
      }
    }
    return arr;
  }
  const rec: Record<string, Object> = value as Record<string, Object>;
  const refVal: Object | undefined = rec['$ref'];
  if (typeof refVal === 'string') {
    const target: string = mcpRefTargetOf(refVal);
    if (target === '') {
      const missing: Record<string, Object> = {};
      return missing;
    }
    const def: Object | undefined = defs[target];
    if (def === undefined || def === null || typeof def !== 'object' || Array.isArray(def)) {
      const missing: Record<string, Object> = {};
      return missing;
    }
    if (stack.includes(target)) {
      // 循环引用：只留 type（无 type 则空对象 = 不限类型）
      const typeVal: Object | undefined = (def as Record<string, Object>)['type'];
      const cycle: Record<string, Object> = {};
      if (typeof typeVal === 'string') {
        cycle['type'] = typeVal;
      }
      return cycle;
    }
    return mcpExpandValue(def, defs, stack.concat([target]), depth + 1);
  }
  const out: Record<string, Object> = {};
  for (const key of Object.keys(rec)) {
    const v: Object | undefined = rec[key];
    if (MCP_REF_CARRY_DICT_KEYS.includes(key)) {
      if (v !== undefined && v !== null && typeof v === 'object' && !Array.isArray(v)) {
        const src: Record<string, Object> = v as Record<string, Object>;
        const props: Record<string, Object> = {};
        for (const p of Object.keys(src)) {
          const expandedProp: Object | undefined = mcpExpandValue(src[p], defs, stack, depth + 1);
          if (expandedProp !== undefined) {
            props[p] = expandedProp;
          }
        }
        out[key] = props;
      } else {
        out[key] = v;
      }
    } else if (MCP_REF_CARRY_ARRAY_KEYS.includes(key)) {
      if (Array.isArray(v)) {
        const expandedArr: Object | undefined = mcpExpandValue(v, defs, stack, depth);
        if (expandedArr !== undefined) {
          out[key] = expandedArr;
        }
      } else {
        out[key] = v;
      }
    } else if (MCP_REF_CARRY_SINGLE_KEYS.includes(key)) {
      if (v !== undefined && v !== null && typeof v === 'object') {
        const expandedSingle: Object | undefined = mcpExpandValue(v, defs, stack, depth + 1);
        if (expandedSingle !== undefined) {
          out[key] = expandedSingle;
        }
      } else {
        out[key] = v;
      }
    } else {
      out[key] = v;
    }
  }
  return out;
}

export function inlineRefExpansion(schemaJson: string): string {
  let parsed: Record<string, Object> | null = null;
  try {
    const raw: object = JSON.parse(schemaJson);
    if (typeof raw === 'object' && raw !== null && !Array.isArray(raw)) {
      parsed = raw as Record<string, Object>;
    }
  } catch (e) {
    return schemaJson;
  }
  if (parsed === null) {
    return schemaJson;
  }
  const defs: Record<string, Object> = mcpCollectDefs(parsed);
  // 整根一次递归展开（不能按根键逐个调 mcpExpandValue——properties/patternProperties 的值
  // 是「键→schema」映射而非 schema，拆开传会把字典当普通对象、$ref 静默不展开；整根传则
  // 字典位分支在场，逐属性递归生效）
  const expandedRoot: Record<string, Object> =
    mcpExpandValue(parsed, defs, [], 0) as Record<string, Object>;
  // 定义已全部内联，不再随缓存携带；新对象重建剔除而非 delete（ArkTS 无 delete 用法先例）
  const out: Record<string, Object> = {};
  for (const key of Object.keys(expandedRoot)) {
    if (MCP_REF_DEF_HOLDERS.includes(key)) {
      continue;
    }
    out[key] = expandedRoot[key];
  }
  return JSON.stringify(out);
}

// tools/list 结果 → 缓存落库前的 schema 展开批处理（管理页刷新与编辑页保存测连两处写点
// 共用；McpListedTool 与 McpToolInput 结构同构可直接传入）。空串/坏 JSON 原样透传
//（注册面 mcpSchemaForRegistration 另有空 schema 兜底）
export function expandMcpToolSchemas(items: McpToolInput[]): McpToolCacheItem[] {
  const expanded: McpToolCacheItem[] = [];
  for (const item of items) {
    expanded.push({
      name: item.name,
      description: item.description,
      inputSchema: inlineRefExpansion(item.inputSchema),
      // enabled 缺省 = true、缓存 false 原样保留——防「缓存→expand→缓存」路径剥掉用户开关位
      enabled: item.enabled !== false
    });
  }
  return expanded;
}
